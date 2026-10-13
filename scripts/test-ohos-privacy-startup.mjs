import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../harmonyos/ets-source/', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');
const logger = { info() {}, warn() {}, error() {} };
const plain = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replaceAll('export default ', '').replaceAll('export ', ''));
const source = read('qability/QAbility.ets');

function manager() {
  const statement = { type: 1, id: 'policy', versionCode: 4 };
  let results = [{ type: 1, id: 'policy', versionCode: 4, result: 1 }];
  const api = {
    AppPrivacyMgmtType: { FULL_MODE: 1, UNSUPPORTED: 0 },
    AppPrivacyLinkType: { PRIVACY_STATEMENT_LINK: 1, USER_AGREEMENT_LINK: 2 },
    AppPrivacyType: { PRIVACY_AGREEMENT: 1, USER_AGREEMENT: 2 },
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
  const effects = [];
  const timers = new Map();
  let nextTimer = 1;
  const qpa = new Proxy({}, { get: (_target, key) => () => calls.push(key) });
  const storage = new Map();
  const Stage = { releasePrivacyGate() { calls.push('release'); }, async initQtAppContextIfNeeded() { calls.push('init'); } };
  const Class = new Function('UIAbility', 'QAbilityStage', 'hasCurrentPrivacyConsent', 'qpa', 'hilog', 'LOG_DOMAIN', 'LOG_TAG', 'AppStorage', 'setInterval', 'clearInterval', 'setDeepSkyImageExtractionForeground', 'LocalStorage', 'QtWindowStageAdapter', 'canIUse', 'notifyLifecycle', 'command', 'deviceInfo', 'BuildProfile',
    plain(source) + ';return QAbility;')(class {}, Stage, () => accepted, qpa, logger, 0, 'test',
      { setOrCreate: (key, value) => storage.set(key, value) },
      (callback, delay) => { const key = nextTimer++; timers.set(key, { callback, delay }); return key; },
      key => timers.delete(key), enabled => effects.push(['extraction', enabled]), class extends Map {}, class {}, () => false,
      enabled => effects.push(['lifecycle', enabled]), (name, payload) => effects.push([name, payload]),
      // 真机（非模拟器）release 配置：engineLessEmulatorUiOnly() 必须保持为 false。
      { productModel: 'phone', abiList: 'arm64-v8a' }, { DEBUG: false });
  const instance = new Class();
  instance.context = { getApplicationContext: () => ({}) };
  instance.pendingWant = {};
  instance.pendingLaunchParam = {};
  return { instance, calls, storage, effects, timers, setAccepted(value) { accepted = value; } };
}

test('all configured user agreements require their own current id, type and version', async () => {
  const fixture = manager();
  const terms = [{ type: 2, id: 'terms', versionCode: 5 }, { type: 2, id: 'extra', versionCode: 2 }];
  fixture.api.getAppPrivacyMgmtInfo = () => ({ type: 1, privacyInfo: [fixture.statement, ...terms] });
  const current = [fixture.statement, ...terms].map(item => ({ ...item, result: 1 }));
  fixture.setResults(current);
  assert.equal(fixture.functions.hasCurrentPrivacyConsent(), true);
  for (const override of [{ versionCode: 4 }, { result: 2 }, { result: 0 }, { type: 1 }, { id: 'old' }]) {
    fixture.setResults([current[0], { ...current[1], ...override }, current[2]]);
    assert.equal(fixture.functions.hasCurrentPrivacyConsent(), false);
    assert.equal((await fixture.functions.requestPrivacyConsent({})).accepted, false);
  }
  fixture.setResults(current.slice(0, 2));
  assert.equal(fixture.functions.hasCurrentPrivacyConsent(), false);
  fixture.setResults([...current, { ...current[1], result: 2 }]);
  assert.equal(fixture.functions.hasCurrentPrivacyConsent(), false);
  fixture.setResults(current);
  assert.equal((await fixture.functions.requestPrivacyConsent({})).accepted, true);
});

test('foreground entry does not create a second agreement workflow or poll periodically', () => {
  const fixture = ability(false);
  fixture.instance.qtInitialized = true;
  fixture.instance.qtAbilityCreated = true;
  fixture.instance.privacyAccepted = true;
  fixture.instance.onForeground();
  assert.equal(fixture.instance.qtInitialized, true);
  assert.equal(fixture.storage.has('stellariumPrivacyRenewalRequired'), false);
  assert.deepEqual(fixture.calls, ['handleAbilityOnForeground']);
  assert.equal([...fixture.timers.values()].some(timer => timer.delay === 30000), false);
  assert.ok(!fixture.effects.some(effect => effect[0] === 'lifecycle' && effect[1] === false));
  assert.ok(!fixture.calls.includes('init'));
  fixture.instance.onBackground();
  assert.equal(fixture.timers.size, 0);
});

test('repeated foreground visits preserve one input diagnostic timer, not a consent poll', () => {
  const fixture = ability(true);
  fixture.instance.qtInitialized = true;
  fixture.instance.qtAbilityCreated = true;
  fixture.instance.privacyAccepted = true;
  fixture.instance.onForeground();
  fixture.instance.onForeground();
  assert.deepEqual([...fixture.timers.values()].map(timer => timer.delay), [500]);
  fixture.instance.onBackground();
  assert.equal(fixture.timers.size, 0);
});

test('agreement version changing during the system dialog cannot release the newer version', async () => {
  const fixture = manager();
  fixture.setResults([]);
  let finish;
  fixture.api.requestAppPrivacyConsent = () => new Promise(resolve => { finish = resolve; });
  const pending = fixture.functions.requestPrivacyConsent({});
  const old = { type: 1, id: 'policy', versionCode: 4, result: 1 };
  fixture.statement.versionCode = 5;
  fixture.setResults([old]);
  finish({ results: [old] });
  assert.equal((await pending).accepted, false);
});

test('read-only privacy CLI works before native initialization without accepting or opening a dialog', () => {
  const fixture = ability(false);
  const responses = [];
  fixture.instance.finishCliRequest = (_request, response) => responses.push(JSON.parse(response));
  fixture.instance.queueCliRequest({ parameters: {
    'skyinstrument.cli.command': 'getPrivacyConsentState', 'skyinstrument.cli.requestId': 'privacy-check'
  } });
  assert.deepEqual(responses, [{ ok: true, currentAgreementsAccepted: false,
    nativeInitialized: false, foreground: true }]);
  assert.deepEqual(fixture.calls, []);
  assert.equal(fixture.instance.cliRequests.length, 0);
});

test('deferred window restore waits for fresh consent without loading another root', () => {
  const fixture = ability(false);
  fixture.instance.pendingPrivacyWindowRestore = true;
  fixture.instance.rootContentLoaded = true;
  fixture.instance.qtWindowStage = {};
  fixture.instance.restoreWindowAfterConsent();
  assert.deepEqual(fixture.calls, []);
  assert.equal(fixture.instance.pendingPrivacyWindowRestore, true);
  fixture.setAccepted(true);
  fixture.instance.restoreWindowAfterConsent();
  fixture.instance.restoreWindowAfterConsent();
  assert.deepEqual(fixture.calls, ['handleAbilityOnWindowStageRestore']);
  assert.equal(fixture.storage.get('stellariumPrivacyNativeStartupAllowed'), true);
  assert.equal(fixture.instance.pendingPrivacyWindowRestore, false);
});

test('system owns renewal without an app overlay, polling or automatic revocation', () => {
  const root = read('pages/ApplicationRoot.ets');
  const page = read('pages/PrivacyBootstrap.ets');
  assert.match(root, /if \(!this\.nativeAllowed \|\| !this\.qtContentReady\)/);
  for (const code of [source, root, page, read('qability/PrivacyConsent.ets')]) {
    assert.doesNotMatch(code, /privacyRenewalRequired|renewalRequired|privacyMonitorTimer|startPrivacyMonitor|suspendForPrivacyRenewal|privacy_review_required/);
    assert.doesNotMatch(code, /disableService\(/);
  }
});

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

test('Qt child process cannot enter the SDK without current policy consent', () => {
  const syncScript = readFileSync(new URL('../scripts/sync-ohos-build-sources.sh', import.meta.url), 'utf8');
  assert.ok(syncScript.includes('harmonyos/ets-source'), 'sync script must mirror the ets-source tree (including process/QChildProcess.ets)');
  const fixture = manager();
  const calls = [];
  const Child = new Function('ChildProcess', 'QtUtils', 'hasCurrentPrivacyConsent', 'qpa', 'hilog', 'LOG_DOMAIN', 'LOG_TAG',
    plain(read('process/QChildProcess.ets')) + ';return QChildProcess;')(
    class {}, { getModulesFactoriesMapForQt: () => { calls.push('factories'); return {}; } },
    fixture.functions.hasCurrentPrivacyConsent, { runQtChildProcess: () => calls.push('run') }, logger, 0, 'test');
  const child = new Child();
  for (const results of [[], [{ type: 1, id: 'policy', versionCode: 3, result: 1 }],
    [{ type: 1, id: 'policy', versionCode: 4, result: 0 }]]) {
    fixture.setResults(results);
    child.onStart();
    assert.deepEqual(calls, []);
  }
  fixture.setResults([{ type: 1, id: 'policy', versionCode: 4, result: 1 }]);
  child.onStart();
  assert.deepEqual(calls, ['factories', 'run']);
  fixture.api.getAppPrivacyMgmtInfo = () => { throw new Error('unavailable'); };
  child.onStart();
  assert.deepEqual(calls, ['factories', 'run']);
});

test('dialog result cannot release startup for an old or unrelated statement', async () => {
  const fixture = manager();
  fixture.setResults([]);
  fixture.api.requestAppPrivacyConsent = async () => ({ results: [{ type: 1, id: 'other', versionCode: 4, result: 1 }] });
  assert.equal((await fixture.functions.requestPrivacyConsent({})).accepted, false);
});

test('concurrent privacy requests share one system dialog and allow explicit retry after refusal', async () => {
  const fixture = manager();
  fixture.setResults([]);
  let complete;
  let dialogs = 0;
  fixture.api.requestAppPrivacyConsent = () => {
    dialogs++;
    return new Promise(resolve => { complete = resolve; });
  };
  const first = fixture.functions.requestPrivacyConsent({});
  const second = fixture.functions.requestPrivacyConsent({});
  const third = fixture.functions.requestPrivacyConsent({});
  assert.equal(dialogs, 1);
  assert.equal(first, second);
  assert.equal(second, third);
  complete({ results: [] });
  for (const result of await Promise.all([first, second, third])) {
    assert.deepEqual(result, { accepted: false, dialogShown: true });
  }
  const retry = fixture.functions.requestPrivacyConsent({});
  assert.equal(dialogs, 2);
  fixture.setResults([{ type: 1, id: 'policy', versionCode: 4, result: 1 }]);
  complete({ results: fixture.api.getAppPrivacyResult() });
  assert.equal((await retry).accepted, true);
  fixture.setResults([]);
  const afterRevocation = fixture.functions.requestPrivacyConsent({});
  assert.equal(dialogs, 3);
  complete({ results: [] });
  assert.equal((await afterRevocation).accepted, false);
});

test('a shared failed privacy request releases its lock for retry', async () => {
  const fixture = manager();
  fixture.setResults([]);
  let rejectDialog;
  fixture.api.requestAppPrivacyConsent = () => new Promise((_resolve, reject) => { rejectDialog = reject; });
  const first = fixture.functions.requestPrivacyConsent({});
  const second = fixture.functions.requestPrivacyConsent({});
  rejectDialog({ code: 1006700001 });
  assert.equal((await first).errorCode, 1006700001);
  assert.equal((await second).accepted, false);
  fixture.api.requestAppPrivacyConsent = async () => ({ results: [] });
  assert.deepEqual(await fixture.functions.requestPrivacyConsent({}), { accepted: false, dialogShown: true });
});

function bootstrap(accepted = false) {
  const page = read('pages/PrivacyBootstrap.ets');
  const start = page.indexOf('  private onHostReady(): void');
  const end = page.indexOf('  private async requestConsent()', start);
  const calls = [];
  let listener;
  const timers = new Map();
  const storage = new Map();
  const events = {
    async createSubscriber() { calls.push('create'); return {}; },
    subscribe(_subscriber, callback) { calls.push('subscribe'); listener = callback; },
    unsubscribe(_subscriber, callback) { calls.push('unsubscribe'); callback(undefined); },
  };
  const Page = new Function('commonEventManager', 'hasCurrentPrivacyConsent', 'notifyConsentAccepted', 'hilog', 'AppStorage', 'setTimeout', 'clearTimeout', stripTypeScriptTypes(`class Page {
    hostReady = false;
    observationStarted = false;
    disposed = false;
    consentCompleted = false;
    requestFailed = false;
    helpAvailable = false;
    helpTimer = -1;
    requesting = false;
    errorCode = 0;
    requests = 0;
    async requestConsent() { this.requests++; }
    ${page.slice(start, end)}
  }`) + ';return Page;')(events, () => accepted, () => calls.push('accepted'), logger,
    { setOrCreate: (key, value) => storage.set(key, value) },
    (callback, delay) => { assert.equal(delay, 15000); timers.set(1, callback); return 1; },
    key => timers.delete(key));
  return { instance: new Page(), calls, events, timers, storage,
    emit: error => listener(error), setAccepted(value) { accepted = value; } };
}

test('hosted startup observes system consent without creating a second privacy dialog', async () => {
  const { instance, calls } = bootstrap();
  instance.onHostReady();
  assert.equal(instance.requests, 0);
  instance.hostReady = true;
  instance.onHostReady();
  instance.onHostReady();
  instance.hostReady = false;
  instance.onHostReady();
  instance.hostReady = true;
  instance.onHostReady();
  await Promise.resolve();
  assert.equal(instance.requests, 0);
  assert.deepEqual(calls, ['create', 'subscribe']);
  assert.equal(instance.requestFailed, false);
  assert.equal(instance.helpAvailable, false);
  await instance.requestConsent();
  assert.equal(instance.requests, 1);
  assert.match(read('pages/PrivacyBootstrap.ets'), /onClick\(\(\) => \{ void this\.requestConsent\(\) \}\)/);
});

test('system consent events require verified current agreement and notify once', async () => {
  const fixture = bootstrap();
  fixture.instance.hostReady = true;
  fixture.instance.onHostReady();
  await Promise.resolve();
  fixture.emit();
  fixture.emit({ code: 1 });
  assert.equal(fixture.calls.includes('accepted'), false);
  fixture.setAccepted(true);
  fixture.instance.requestFailed = true;
  fixture.instance.helpAvailable = true;
  fixture.instance.requesting = true;
  fixture.instance.errorCode = 1006700003;
  fixture.emit();
  fixture.emit();
  assert.equal(fixture.calls.filter(call => call === 'accepted').length, 1);
  assert.equal(fixture.instance.requests, 0);
  assert.equal(fixture.instance.requestFailed, false);
  assert.equal(fixture.instance.helpAvailable, false);
  assert.equal(fixture.instance.requesting, false);
  assert.equal(fixture.instance.errorCode, 0);
  assert.equal(fixture.timers.size, 0);
  assert.equal(fixture.storage.get('stellariumPrivacyConsentVerifiedUi'), true);
  assert.equal(fixture.storage.has('stellariumPrivacyNativeStartupAllowed'), false);
  fixture.instance.aboutToDisappear();
  assert.equal(fixture.calls.at(-1), 'unsubscribe');
});

test('already accepted or consent recorded during subscription needs no second dialog', async () => {
  const fixture = bootstrap();
  fixture.instance.hostReady = true;
  fixture.instance.onHostReady();
  fixture.setAccepted(true);
  await Promise.resolve();
  assert.deepEqual(fixture.calls, ['create', 'subscribe', 'accepted']);
  assert.equal(fixture.instance.requests, 0);
});

test('destroyed privacy page cannot subscribe or release startup from late callbacks', async () => {
  const fixture = bootstrap(true);
  fixture.instance.hostReady = true;
  fixture.instance.onHostReady();
  fixture.instance.aboutToDisappear();
  await Promise.resolve();
  assert.deepEqual(fixture.calls, ['create']);
  const subscribed = bootstrap();
  subscribed.instance.hostReady = true;
  subscribed.instance.onHostReady();
  await Promise.resolve();
  subscribed.instance.aboutToDisappear();
  subscribed.setAccepted(true);
  subscribed.emit();
  assert.equal(subscribed.calls.includes('accepted'), false);
});

test('subscription failure keeps startup blocked and manual recovery available', async () => {
  const fixture = bootstrap();
  fixture.events.createSubscriber = async () => { throw new Error('service error'); };
  fixture.instance.hostReady = true;
  fixture.instance.onHostReady();
  await Promise.resolve();
  assert.equal(fixture.instance.requestFailed, true);
  assert.equal(fixture.instance.requests, 0);
  assert.equal(fixture.calls.includes('accepted'), false);
});

test('long system prompt wait offers manual help without reporting failure or requesting a dialog', async () => {
  const fixture = bootstrap();
  fixture.instance.hostReady = true;
  fixture.instance.onHostReady();
  await Promise.resolve();
  fixture.emit();
  assert.equal(fixture.instance.requestFailed, false);
  fixture.timers.get(1)();
  assert.equal(fixture.instance.helpAvailable, true);
  assert.equal(fixture.instance.requestFailed, false);
  assert.equal(fixture.instance.requests, 0);
  assert.equal(fixture.calls.includes('accepted'), false);
  fixture.instance.aboutToDisappear();
});

test('destroying waiting page cancels delayed recovery and cannot change state afterwards', async () => {
  const fixture = bootstrap();
  fixture.instance.hostReady = true;
  fixture.instance.onHostReady();
  await Promise.resolve();
  const callback = fixture.timers.get(1);
  fixture.instance.aboutToDisappear();
  assert.equal(fixture.timers.size, 0);
  callback();
  assert.equal(fixture.instance.helpAvailable, false);
});

test('privacy service faults remain blocked and are distinguishable from refusal', async () => {
  const fixture = manager();
  fixture.setResults([]);
  assert.deepEqual(await fixture.functions.requestPrivacyConsent({}), { accepted: false, dialogShown: true });
  for (const failure of [{ code: 1006700003 }, { code: 1006700001 }, new Error('unavailable'), null]) {
    fixture.api.getAppPrivacyMgmtInfo = () => { throw failure; };
    const result = await fixture.functions.requestPrivacyConsent({});
    assert.equal(result.accepted, false);
    assert.equal(result.dialogShown, false);
    assert.equal(result.errorCode, failure?.code ?? -1);
    assert.equal(fixture.functions.hasCurrentPrivacyConsent(), false);
  }
});

test('missing hosted privacy configuration never requests or assumes agreement', async () => {
  const fixture = manager();
  fixture.api.requestAppPrivacyConsent = async () => { throw new Error('must not request'); };
  for (const management of [{ type: 0, privacyInfo: [] }, { type: 1, privacyInfo: [] },
    { type: 1, privacyInfo: [{ type: 2, id: 'other', versionCode: 4 }] }]) {
    fixture.api.getAppPrivacyMgmtInfo = () => management;
    assert.deepEqual(await fixture.functions.requestPrivacyConsent({}),
      { accepted: false, dialogShown: false, errorCode: 1006700003 });
  }
});

test('privacy retry retains diagnostics without rapid repeated requests', () => {
  const page = read('pages/PrivacyBootstrap.ets');
  assert.match(page, /this\.errorCode = consent\.errorCode \?\? 0/);
  assert.match(page, /privacy_service_unconfigured/);
  assert.match(page, /privacy_service_unavailable/);
  assert.match(page, /Date\.now\(\) - this\.lastRequestAt < 1500/);
  assert.match(page, /\.enabled\(!this\.requesting\)/);
  assert.match(page, /if \(this\.requestFailed && !this\.requesting\)/);
  assert.match(page, /if \(this\.disposed \|\| this\.consentCompleted\) return/);
  const rootPage = read('pages/ApplicationRoot.ets');
  assert.match(rootPage, /if \(this\.nativeAllowed \|\| this\.consentVerifiedUi\)/);
  assert.match(rootPage, /if \(this\.nativeAllowed && this\.qtContentReady\)/);
});

test('manual recovery clears stale failure while waiting and restores actionable failure on refusal', async () => {
  const fixture = bootstrap();
  fixture.instance.hostReady = true;
  fixture.instance.requestFailed = true;
  fixture.instance.lastRequestAt = 0;
  fixture.instance.getUIContext = () => ({ getHostContext: () => ({}) });
  let finish;
  let requests = 0;
  const page = read('pages/PrivacyBootstrap.ets');
  const methods = page.slice(page.indexOf('  private async requestConsent()'), page.indexOf('  build()'));
  const Recovery = new Function('requestPrivacyConsent', 'hasCurrentPrivacyConsent', 'hilog',
    stripTypeScriptTypes(`class Recovery { ${methods} }; Recovery;`) + ';return Recovery;')(
      () => { requests++; return new Promise(resolve => { finish = resolve; }); }, () => false, logger);
  const first = Recovery.prototype.requestConsent.call(fixture.instance);
  assert.equal(fixture.instance.requestFailed, false);
  assert.equal(fixture.instance.requesting, true);
  await Recovery.prototype.requestConsent.call(fixture.instance);
  assert.equal(requests, 1);
  finish({ accepted: false, dialogShown: true });
  await first;
  assert.equal(fixture.instance.requestFailed, true);
  assert.equal(fixture.instance.requesting, false);
  assert.equal(fixture.calls.includes('accepted'), false);
});

test('late manual request error cannot restore failure after verified system consent', async () => {
  const fixture = bootstrap();
  fixture.instance.hostReady = true;
  fixture.instance.lastRequestAt = 0;
  fixture.instance.getUIContext = () => ({ getHostContext: () => ({}) });
  let reject;
  const page = read('pages/PrivacyBootstrap.ets');
  const methods = page.slice(page.indexOf('  private async requestConsent()'), page.indexOf('  build()'));
  const Recovery = new Function('requestPrivacyConsent', 'hasCurrentPrivacyConsent', 'hilog',
    stripTypeScriptTypes(`class Recovery { ${methods} }; Recovery;`) + ';return Recovery;')(
      () => new Promise((_resolve, fail) => { reject = fail; }), () => true, logger);
  const pending = Recovery.prototype.requestConsent.call(fixture.instance);
  fixture.setAccepted(true);
  fixture.instance.finishVerifiedConsent();
  reject(new Error('late dialog teardown'));
  await pending;
  assert.equal(fixture.instance.requestFailed, false);
  assert.equal(fixture.instance.requesting, false);
  assert.equal(fixture.calls.filter(call => call === 'accepted').length, 1);
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

test('overlapping window create and restore prepare a single privacy root', async () => {
  const fixture = ability();
  let finishWindow;
  let loaded = 0;
  let preparations = 0;
  const stage = {
    getMainWindow() {
      preparations++;
      return new Promise(resolve => { finishWindow = resolve; });
    },
    async loadContent() { loaded++; },
  };
  fixture.instance.enterImmersive = async () => {};
  const first = fixture.instance.preparePrivacyHostPage(stage);
  const second = fixture.instance.preparePrivacyHostPage(stage);
  const third = fixture.instance.preparePrivacyHostPage(stage);
  assert.equal(preparations, 1);
  finishWindow({});
  assert.deepEqual(await Promise.all([first, second, third]), [true, true, true]);
  assert.equal(loaded, 1);
  assert.deepEqual(fixture.calls, []);
});

test('failed privacy root preparation can retry without leaving a pending lock', async () => {
  const fixture = ability();
  const failed = { async getMainWindow() { throw new Error('window unavailable'); } };
  assert.equal(await fixture.instance.preparePrivacyHostPage(failed), false);
  let loaded = 0;
  fixture.instance.enterImmersive = async () => {};
  assert.equal(await fixture.instance.preparePrivacyHostPage({
    async getMainWindow() { return {}; },
    async loadContent() { loaded++; },
  }), true);
  assert.equal(loaded, 1);
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
  // M1-B 子组①：startGyroscope/stopGyroscope 已下沉 capability/SensorController.ets；
  // 隐私门禁经 hooks.canUseSensors() 回注，必须早于任何传感器订阅。
  const sensor = read('capability/SensorController.ets');
  const sensorStart = sensor.slice(sensor.indexOf('  startGyroscope()'), sensor.indexOf('  stopGyroscope('));
  assert.ok(sensorStart.indexOf('canUseSensors()') < sensorStart.indexOf('subscribeRotationVector('));
  // §15.12：useDeviceLocation/applyPickerLocation 已下沉 capability/LocationController.ets；权限与
  // 定位 NAPI 收在宿主具名适配器 HostLocationPort，隐私门禁经 hooks 回注（仍是 3 处复检）。
  const locationController = read('capability/LocationController.ets');
  const location = locationController.slice(
    locationController.indexOf('  async useDeviceLocation()'),
    locationController.indexOf('  applyPickerLocation()'));
  assert.equal((location.match(/hasPrivacyConsent\(\)/g) ?? []).length, 3);
  assert.match(page, /permissionResult\.authResults\.some/);
  assert.match(location, /finally\s*\{\s*this\.deviceLocationRequestInProgress = false/);
});

test('incomplete installations are repaired asynchronously, never by full sync extraction', () => {
  const resources = read('qability/StellariumResourceBootstrap.ets');
  const method = resources.match(/function hasStartupResourceFiles\([^)]*\): boolean \{[\s\S]*?\n\}/)[0];
  let missing = '';
  const check = new Function('exists', 'fileSize', 'hilog', 'LOG_DOMAIN', 'LOG_TAG', 'MARKER', 'SKYCULTURE_ART_COMPAT_MARKER', plain(method) + ';return hasStartupResourceFiles;')(
    path => !missing || !path.endsWith(missing), path => (!missing || !path.endsWith(missing)) ? 1 : 0,
    logger, 0, 'test', 'marker', 'compat');
  assert.equal(check('/sandbox'), true);
  for (const file of ['marker', 'compat', 'data/default_cfg.ini', 'translations/stellarium/zh_CN.qm', 'skycultures/modern/illustrations/andromeda.png']) {
    missing = file;
    assert.equal(check('/sandbox'), false);
  }
  const finalizerStart = resources.indexOf('export async function prepareStellariumResources(');
  assert.ok(finalizerStart >= 0);
  const finalizer = resources.slice(finalizerStart);
  assert.doesNotMatch(finalizer, /extractRawTree\(/);
  assert.doesNotMatch(finalizer, /\bwriteRawFile\(/);
});

test('normal sensor probes contain counts rather than raw orientation measurements', () => {
  // M1-B 子组①：emitGyroPoseProbe 已下沉 capability/SensorController.ets。
  const sensor = read('capability/SensorController.ets');
  const probe = sensor.match(/  private emitGyroPoseProbe\([^\n]*\n[\s\S]*?\n  \}/)[0];
  assert.doesNotMatch(probe, /rawAz=|rawAlt=|gravity=|magnetic=|qNorm=/);
  assert.doesNotMatch(sensor, /\[GYRO_ORIENTATION\]/);
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
  const cliPanels = read('common/derive/skycult.ets');
  assert.match(cliPanels, /'settingsInformation', 'settingsTime', 'settingsPrivacy'/);
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
