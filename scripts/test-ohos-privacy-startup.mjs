import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../harmonyos/ets-source/', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');
const logger = { info() {}, warn() {}, error() {} };
const plain = source => stripTypeScriptTypes(source.replace(/^import .*\n/gm, '').replaceAll('export default ', '').replaceAll('export ', ''));
const source = read('qability/QAbility.ets');

function manager() {
  const statement = { type: 1, id: 'policy', versionCode: 4 };
  let results = [{ type: 1, id: 'policy', versionCode: 4, result: 1 }];
  const api = {
    AppPrivacyMgmtType: { FULL_MODE: 1, UNSUPPORTED: 0 },
    AppPrivacyLinkType: { PRIVACY_STATEMENT_LINK: 1 },
    AppPrivacyType: { PRIVACY_AGREEMENT: 1 },
    AppPrivacyResultType: { FULL_MODE_AGREED: 1 },
    getAppPrivacyMgmtInfo: () => ({ type: 1, privacyInfo: [statement] }),
    getAppPrivacyResult: () => results,
    requestAppPrivacyConsent: async () => ({ results }),
  };
  const functions = new Function('privacyManager', 'hilog', 'LOG_DOMAIN', 'LOG_TAG',
    plain(read('qability/PrivacyConsent.ets')) + ';return {hasCurrentPrivacyConsent, requestPrivacyConsent};')(api, logger, 0, 'test');
  return { api, functions, setResults(value) { results = value; }, statement };
}

function ability(accepted = false) {
  const calls = [];
  const qpa = new Proxy({}, { get: (_target, key) => () => calls.push(key) });
  const storage = new Map();
  const Stage = { releasePrivacyGate() { calls.push('release'); }, async initQtAppContextIfNeeded() { calls.push('init'); } };
  const Class = new Function('UIAbility', 'QAbilityStage', 'hasCurrentPrivacyConsent', 'qpa', 'hilog', 'LOG_DOMAIN', 'LOG_TAG', 'AppStorage', 'setInterval', 'clearInterval', 'setDeepSkyImageExtractionForeground', 'LocalStorage', 'QtWindowStageAdapter', 'canIUse',
    plain(source) + ';return QAbility;')(class {}, Stage, () => accepted, qpa, logger, 0, 'test',
      { setOrCreate: (key, value) => storage.set(key, value) }, () => 1, () => {}, () => {}, class extends Map {}, class {}, () => false);
  const instance = new Class();
  instance.context = { getApplicationContext: () => ({}) };
  instance.pendingWant = {};
  instance.pendingLaunchParam = {};
  return { instance, calls, storage };
}

test('current consent requires matching policy id and version and agreed result', () => {
  const fixture = manager();
  assert.equal(fixture.functions.hasCurrentPrivacyConsent(), true);
  for (const override of [{ id: 'other' }, { versionCode: 3 }, { result: 0 }, { type: 2 }]) {
    fixture.setResults([{ type: 1, id: 'policy', versionCode: 4, result: 1, ...override }]);
    assert.equal(fixture.functions.hasCurrentPrivacyConsent(), false);
  }
  fixture.api.getAppPrivacyMgmtInfo = () => { throw new Error('unavailable'); };
  assert.equal(fixture.functions.hasCurrentPrivacyConsent(), false);
});

test('dialog result cannot release startup for an old or unrelated statement', async () => {
  const fixture = manager();
  fixture.setResults([]);
  fixture.api.requestAppPrivacyConsent = async () => ({ results: [{ type: 1, id: 'other', versionCode: 4, result: 1 }] });
  assert.equal((await fixture.functions.requestPrivacyConsent({})).accepted, false);
});

test('window preparation loads one root before appearance APIs without entering Qt', async () => {
  const fixture = ability();
  let loaded = false;
  let loadCount = 0;
  const stage = {
    getMainWindow: async () => ({
      setWindowBackgroundColor() { assert.equal(loaded, true); },
      async setWindowLayoutFullScreen() {}, async setWindowSystemBarEnable() {},
    }),
    async loadContent(path) { assert.equal(path, 'pages/ApplicationRoot'); loaded = true; loadCount++; },
  };
  assert.equal(await fixture.instance.preparePrivacyHostPage(stage), true);
  assert.equal(await fixture.instance.preparePrivacyHostPage(stage), true);
  assert.equal(loadCount, 1);
  assert.deepEqual(fixture.calls, []);
  assert.equal(fixture.instance.qtWindowPrepared, false);
  assert.equal(fixture.storage.get('stellariumPrivacyNativeStartupAllowed'), false);
  assert.equal((source.match(/\.loadContent\(/g) ?? []).length, 1);
});

test('Qt initialization is guarded even when called outside the startup handler', async () => {
  const fixture = ability(false);
  fixture.instance.privacyAccepted = true;
  await assert.rejects(fixture.instance.initializeQtAbilityIfNeeded(), /privacy consent/);
  assert.deepEqual(fixture.calls, []);
});

test('unaccepted startup cannot launch another ability or initialize Qt', async () => {
  const fixture = ability(false);
  fixture.instance.pendingWindowStage = {};
  await fixture.instance.requestPrivacyThenStart();
  await fixture.instance.requestPrivacyThenStart();
  assert.deepEqual(fixture.calls, []);
  assert.equal(fixture.instance.privacyAccepted, false);
  assert.doesNotMatch(source, /requestPrivacyConsent\(this.context\)/);
  assert.doesNotMatch(source, /\.startAbility\(/);
});

test('privacy view notifies the existing ability instead of starting a new window', () => {
  const page = read('pages/PrivacyBootstrap.ets');
  assert.ok(page.indexOf('hasCurrentPrivacyConsent()') < page.indexOf('notifyConsentAccepted()'));
  assert.doesNotMatch(page, /disableService|FULL_MODE_AGREED\s*:|\.startAbility\(|libqohos|libentry/);
});

test('application has one ability and one root; no temporary privacy mission', () => {
  const moduleText = readFileSync(new URL('../harmonyos/module.json5', import.meta.url), 'utf8');
  assert.doesNotMatch(moduleText, /PrivacyAbility|excludeFromMissions/);
  assert.match(read('pages/ApplicationRoot.ets'), /this.nativeAllowed && this.qtContentReady/);
  assert.match(source, /setWindowLayoutFullScreen\(true\)/);
  assert.match(source, /setWindowSystemBarEnable\(\[\]\)/);
});

test('Qt content adapter preserves createInfo identity and never reloads native UIContent', async () => {
  let accepted = false;
  const updates = new Map();
  const shared = new Map();
  const Adapter = new Function('hasCurrentPrivacyConsent', 'AppStorage', 'hilog',
    plain(read('qability/QtWindowStageAdapter.ets')) + ';return QtWindowStageAdapter;')(
      () => accepted, { setOrCreate: (key, value) => updates.set(key, value) }, logger);
  const adapter = new Adapter({ loadContent() { throw new Error('must not reload'); } },
    { setOrCreate: (key, value) => shared.set(key, value) });
  const info = { xComponentId: 'test-node', onAttach() {}, onAppear() {}, onDisAppear() {} };
  const storage = { get: () => info };
  await assert.rejects(adapter.loadContent('pages/MainWindowNativeNode', storage), /privacy consent/);
  assert.equal(shared.size, 0);
  accepted = true;
  await adapter.loadContent('pages/MainWindowNativeNode', storage);
  assert.equal(shared.get('createInfo'), info);
  assert.equal(updates.get('stellariumQtContentReady'), true);
  await assert.rejects(adapter.loadContent('pages/unknown', storage), /Unsupported/);
  await assert.rejects(adapter.loadContent('pages/MainWindowNativeNode'), /missing/);
  let called = false;
  await new Promise(resolve => adapter.loadContent('pages/MainWindowNativeNode', storage, error => {
    assert.equal(error.code, 0); called = true; resolve();
  }));
  assert.equal(called, true);
});

test('accepted privacy view enters serialized startup without a second ability', async () => {
  const fixture = ability(true);
  let started = 0;
  fixture.instance.pendingWindowStage = {};
  fixture.instance.startQtIfReady = async () => { started++; };
  await fixture.instance.requestPrivacyThenStart();
  await fixture.instance.requestPrivacyThenStart();
  assert.equal(started, 1);
  assert.equal(fixture.instance.privacyAccepted, true);
});

test('Qt stage rechecks consent after asynchronous resource preparation', async () => {
  let accepted = true;
  let setups = 0;
  const Class = new Function('AbilityStage', 'QAbility', 'hasCurrentPrivacyConsent', 'prepareStellariumResourcesAsync', 'prepareStellariumResources', 'hilog', 'LOG_DOMAIN', 'LOG_TAG', 'qpa',
    plain(read('qabilitystage/QAbilityStage.ets')) + ';return QAbilityStage;')(
      class {}, class {}, () => accepted, async () => { accepted = false; }, () => { throw new Error('must not run'); }, logger, 0, 'test', { setupQtApplication() { setups++; } });
  Class.releasePrivacyGate();
  await assert.rejects(Class.initQtAppContextIfNeeded({}));
  assert.equal(setups, 0);
  assert.throws(() => Class.releasePrivacyGate());
});

test('reentrant startup is serialized and background return cannot release native gate', async () => {
  const fixture = ability(true);
  fixture.instance.privacyAccepted = true;
  fixture.instance.pendingWindowStage = {};
  let resolve;
  let initializations = 0;
  fixture.instance.initializeQtAbilityIfNeeded = async () => { initializations++; await new Promise(done => { resolve = done; }); };
  const first = fixture.instance.startQtIfReady();
  await fixture.instance.startQtIfReady();
  assert.equal(initializations, 1);
  fixture.instance.isForeground = false;
  resolve();
  await first;
  assert.equal(fixture.instance.qtInitialized, false);
  assert.equal(fixture.instance.qtStartupInProgress, false);
  assert.notEqual(fixture.storage.get('stellariumPrivacyNativeStartupAllowed'), true);
});

test('sensor and location entrypoints gate privacy and location rechecks after awaits', () => {
  const page = read('pages/MainWindowNativeNode.ets');
  const sensorStart = page.slice(page.indexOf('  private startGyroscope()'), page.indexOf('  private probeGyroSensor('));
  assert.ok(sensorStart.indexOf('hasCurrentPrivacyConsent()') < sensorStart.indexOf('sensor.on('));
  const location = page.slice(page.indexOf('  private async useDeviceLocation()'), page.indexOf('  private applyPickerLocation()'));
  assert.equal((location.match(/hasCurrentPrivacyConsent\(\)/g) ?? []).length, 3);
  assert.match(location, /permissionResult.authResults.some/);
  assert.match(location, /finally\s*\{\s*this.deviceLocationRequestInProgress = false/);
});

test('incomplete installations are repaired asynchronously, never by full sync extraction', () => {
  const resources = read('qability/StellariumResourceBootstrap.ets');
  const method = resources.match(/function hasStartupResourceFiles\([^)]*\): boolean \{[\s\S]*?\n\}/)[0];
  let missing = '';
  const check = new Function('exists', 'MARKER', 'SKYCULTURE_ART_COMPAT_MARKER', plain(method) + ';return hasStartupResourceFiles;')(
    path => !missing || !path.endsWith(missing), 'marker', 'compat');
  assert.equal(check('/sandbox'), true);
  for (const file of ['marker', 'compat', 'data/default_cfg.ini', 'translations/stellarium/zh_CN.qm', 'skycultures/modern/illustrations/andromeda.png']) {
    missing = file;
    assert.equal(check('/sandbox'), false);
  }
  const finalizer = resources.slice(resources.indexOf('export function prepareStellariumResources('));
  assert.doesNotMatch(finalizer, /extractRawTree\(/);
});

test('normal sensor probes contain counts rather than raw orientation measurements', () => {
  const page = read('pages/MainWindowNativeNode.ets');
  const probe = page.match(/  private emitGyroPoseProbe\([^\n]*\n[\s\S]*?\n  \}/)[0];
  assert.doesNotMatch(probe, /rawAz=|rawAlt=|gravity=|magnetic=|qNorm=/);
  assert.doesNotMatch(page, /\[GYRO_ORIENTATION\]/);
});

test('both policy artifacts name the actual sensor types and remain marked as drafts', () => {
  for (const path of ['../docs/PRIVACY-POLICY.md', '../docs/privacy/index.html']) {
    const text = readFileSync(new URL(path, import.meta.url), 'utf8');
    for (const term of ['重力传感器', '磁场传感器', '旋转矢量', '方向传感器', '整改草案']) assert.ok(text.includes(term));
    assert.doesNotMatch(text, /不收集、不存储、不上传.*任何用户个人信息/);
  }
});

test('startup compatibility marker is visible to the HAP packager and emitted after conversion', () => {
  const resources = read('qability/StellariumResourceBootstrap.ets');
  const marker = resources.match(/const SKYCULTURE_ART_COMPAT_MARKER = '([^']+)'/)[1];
  assert.ok(marker.split('/').every(segment => !segment.startsWith('.')));
  const sync = readFileSync(new URL('./sync-ohos-resources.sh', import.meta.url), 'utf8');
  assert.ok(sync.indexOf(marker) > sync.indexOf('Sky-culture illustration compatibility pass'));
});

test('privacy settings are reachable through the existing CLI navigation route', () => {
  const page = read('pages/MainWindowNativeNode.ets');
  assert.match(page, /'settingsInformation', 'settingsTime', 'settingsPrivacy'/);
  assert.match(page, /panel === 'settingsTime' \? 3 : -1/);
});

test('unaccepted stage lifecycle and direct setup never enter Qt', async () => {
  const calls = [];
  const qpa = new Proxy({}, { get: (_target, key) => () => calls.push(key) });
  const Class = new Function('AbilityStage', 'QAbility', 'hasCurrentPrivacyConsent',
    'prepareStellariumResourcesAsync', 'prepareStellariumResources', 'hilog', 'LOG_DOMAIN', 'LOG_TAG', 'qpa',
    plain(read('qabilitystage/QAbilityStage.ets')) + ';return QAbilityStage;')(
      class {}, class {}, () => false, async () => { calls.push('resources'); },
      () => { calls.push('syncResources'); }, logger, 0, 'test', qpa);
  const stage = new Class();
  stage.onCreate();
  assert.equal(stage.onAcceptWant({}), '');
  assert.equal(stage.onNewProcessRequest({}), '');
  assert.throws(() => Class.releasePrivacyGate(), /not accepted/);
  await assert.rejects(Class.initQtAppContextIfNeeded({}), /requires privacy consent/);
  stage.onDestroy();
  assert.equal(Class.isQtApplicationInitialized(), false);
  assert.deepEqual(calls, []);
});

test('Qt module initialization is single-flight and follows accepted resource preparation', async () => {
  const calls = [];
  const qpa = {
    setupQtApplication() { calls.push('setup'); },
    handleAbilityStageOnCreate() { calls.push('stage'); },
  };
  const Class = new Function('AbilityStage', 'QAbility', 'QChildProcess', 'QtUtils', 'APP_LIBRARY_NAME',
    'hasCurrentPrivacyConsent', 'prepareStellariumResourcesAsync', 'prepareStellariumResources',
    'hilog', 'LOG_DOMAIN', 'LOG_TAG', 'qpa',
    plain(read('qabilitystage/QAbilityStage.ets')) + ';return QAbilityStage;')(
      class {}, class {}, class {}, { getModulesFactoriesMapForQt: () => ({}) }, 'test',
      () => true, async () => { calls.push('prepare'); }, () => { calls.push('resourcesReady'); },
      logger, 0, 'test', qpa);
  new Class().onCreate();
  assert.deepEqual(calls, []);
  Class.releasePrivacyGate();
  const first = Class.initQtAppContextIfNeeded({});
  assert.equal(first, Class.initQtAppContextIfNeeded({}));
  await first;
  await Class.initQtAppContextIfNeeded({});
  assert.deepEqual(calls, ['prepare', 'resourcesReady', 'setup', 'stage']);
});
