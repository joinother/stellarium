import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = name => readFileSync(new URL(`../harmonyos/ets-source/capability/${name}.ets`, import.meta.url), 'utf8');
const { HapticFeedback } = await import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(read('HapticFeedback')))}`);
const soft = 'haptic.effect.soft';
const success = 'haptic.notice.success';
const failure = 'haptic.notice.fail';
const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((accept, fail) => { resolve = accept; reject = fail; });
  return { promise, resolve, reject };
};

function fixture(effects = [soft, success, failure]) {
  const state = { consent: true, now: 1000, stored: false, pulses: [], writes: [], queries: [], stops: 0 };
  const driver = {
    async supports(effect) { state.queries.push(effect); return effects.includes(effect); },
    async start(effect, intensity) { state.pulses.push({ effect, intensity }); },
    async stop() { state.stops++; }
  };
  const preferences = {
    async readEnabled() { return state.stored; },
    async writeEnabled(value) { state.writes.push(value); state.stored = value; }
  };
  const guard = { hasConsent: () => state.consent, now: () => state.now };
  const service = new HapticFeedback(driver, preferences, guard);
  const ready = async () => {
    service.setForeground(true);
    await service.initialize();
    assert.equal(await service.setEnabled(true), true);
  };
  return { service, state, driver, preferences, guard, ready };
}

function hostFixture(model) {
  const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
  const names = ['refreshHapticState', 'changeHapticEnabled', 'clearUiBehaviorPreferences',
    'exitAppAfterRestore', 'requestSkySelection', 'activateDockAction'];
  const methods = names.map(name => {
    const match = new RegExp(`^  private (?:async )?${name}\\(`, 'm').exec(source);
    assert.ok(match, `host method ${name} exists`);
    const end = source.indexOf('\n  }', match.index);
    assert.ok(end > match.index, `host method ${name} ends`);
    return source.slice(match.index, end + 4).replace('private ', '');
  }).join('\n');
  const timers = [];
  const clearedStores = [];
  const preferences = { async getPreferences(context, name) {
    return { async clear() { clearedStores.push(name); }, async flush() {} };
  } };
  const Host = new Function('preferences', 'hilog', 'AppStorage', 'I18n', 'Date', 'setTimeout',
    'NIGHT_MODE_STORE', 'QUICK_PANEL_STORE', 'INFO_WINDOW_STORE',
    stripTypeScriptTypes(`class Host { ${methods} };`) + 'return Host;')(
    preferences, { info() {}, warn() {} }, { setOrCreate() {} }, { t: key => key },
    { now: () => model.state.now }, callback => { timers.push(callback); return timers.length; },
    'night', 'quick', 'info'
  );
  const host = new Host();
  const calls = { hints: [], panels: [], selections: [], resets: 0, terminations: 0 };
  const context = { async terminateSelf() { calls.terminations++; } };
  Object.assign(host, {
    hapticFeedback: model.service,
    haptics: () => model.service,
    getUIContext: () => ({ getHostContext: () => context }),
    settingsRepository: { async resetToDefaults() { calls.resets++; } },
    nightModeStore: { nightMode: true },
    flashHint: text => calls.hints.push(text),
    skySelectionRequestSerial: 0, skyWidth: 1024, skyHeight: 768,
    objectDetailStore: { selectedName: '' },
    callInteractive: (command, payload, callback) => calls.selections.push({ command, payload, callback }),
    applySelectedObject: result => { host.objectDetailStore.selectedName = result.found ? result.name : ''; },
    refreshSelectedDynamicValues() {},
    lastDockActionPanel: '', lastDockActionAt: 0,
    setPanel: panel => calls.panels.push(panel),
    showFullObjectInspector: () => calls.panels.push('object')
  });
  return { host, calls, timers, clearedStores };
}

const settle = () => new Promise(resolve => setImmediate(resolve));

test('host switch persists on/off, refreshes from the service and reports failed saves', async () => {
  const model = fixture();
  await model.ready();
  const { host, calls } = hostFixture(model);
  assert.equal(await host.changeHapticEnabled(false), true);
  assert.equal(host.hapticEnabled, false);
  assert.equal(model.state.stored, false);
  const write = deferred();
  model.preferences.writeEnabled = async value => {
    await write.promise;
    model.state.stored = value;
  };
  const saving = host.changeHapticEnabled(true);
  assert.equal(host.hapticBusy, true);
  assert.equal(await model.service.menu(), false);
  write.resolve();
  assert.equal(await saving, true);
  assert.equal(host.hapticEnabled, true);
  assert.equal(host.hapticBusy, false);
  const recreated = new HapticFeedback(model.driver, model.preferences, model.guard);
  recreated.setForeground(true);
  await recreated.initialize();
  assert.equal(recreated.status().enabled, true);
  model.preferences.writeEnabled = async () => { throw new Error('disk'); };
  assert.equal(await host.changeHapticEnabled(false), false);
  assert.equal(host.hapticEnabled, false);
  assert.equal(host.hapticBusy, false);
  assert.equal(calls.hints.length, 1);
});

test('host restore-defaults awaits durable haptic disable before terminating', async () => {
  const model = fixture();
  await model.ready();
  const { host, calls, timers } = hostFixture(model);
  const write = deferred();
  model.preferences.writeEnabled = async value => {
    model.state.writes.push(value);
    await write.promise;
    model.state.stored = value;
  };
  host.exitAppAfterRestore();
  assert.equal(timers.length, 1);
  timers.shift()();
  await settle();
  assert.ok(model.state.writes.includes(false), 'reset reaches the independent haptic preferences');
  assert.equal(model.service.status().enabled, false);
  assert.equal(calls.terminations, 0, 'do not exit while disable is still being flushed');
  write.resolve();
  await settle();
  assert.equal(calls.resets, 1);
  assert.equal(calls.terminations, 1);
  assert.equal(model.state.stored, false);
  const recreated = new HapticFeedback(model.driver, model.preferences, model.guard);
  recreated.setForeground(true);
  await recreated.initialize();
  assert.equal(recreated.status().enabled, false);
});

test('host empty-sky selection resets deduplication and stale replies cannot change it', async () => {
  const model = fixture();
  await model.ready();
  const { host, calls } = hostFixture(model);
  host.requestSkySelection(100, 200);
  calls.selections.at(-1).callback({ ok: true, found: true, name: 'Moon' });
  await settle();
  assert.equal(model.state.pulses.length, 1);
  model.state.now += 1000;
  host.requestSkySelection(200, 300);
  calls.selections.at(-1).callback({ ok: true, found: false });
  await settle();
  assert.equal(model.state.pulses.length, 1, 'empty sky itself is silent');
  host.requestSkySelection(100, 200);
  calls.selections.at(-1).callback({ ok: true, found: true, name: 'Moon' });
  await settle();
  assert.equal(model.state.pulses.length, 2, 'same object buzzes after deselection');
  host.requestSkySelection(200, 300);
  const staleEmpty = calls.selections.at(-1).callback;
  host.requestSkySelection(100, 200);
  calls.selections.at(-1).callback({ ok: true, found: true, name: 'Moon' });
  staleEmpty({ ok: true, found: false });
  await settle();
  model.state.now += 1000;
  host.requestSkySelection(100, 200);
  calls.selections.at(-1).callback({ ok: true, found: true, name: 'Moon' });
  await settle();
  assert.equal(model.state.pulses.length, 2, 'ignored stale empty reply must not reset the current selection');
});

test('host duplicate Dock action is silent beyond service throttle but inside Dock debounce', async () => {
  const model = fixture();
  await model.ready();
  const { host, calls } = hostFixture(model);
  host.activateDockAction({ panel: 'time' });
  await settle();
  assert.deepEqual(calls.panels, ['time']);
  assert.equal(model.state.pulses.length, 1);
  model.state.now += 200;
  host.activateDockAction({ panel: 'time' });
  await settle();
  assert.deepEqual(calls.panels, ['time']);
  assert.equal(model.state.pulses.length, 1, 'host debounce, not 120ms service throttle, rejects this pulse');
  model.state.now += 200;
  host.activateDockAction({ panel: 'time' });
  await settle();
  assert.deepEqual(calls.panels, ['time', 'time']);
  assert.equal(model.state.pulses.length, 2);
  model.state.now += 200;
  host.activateDockAction({ panel: 'more' });
  await settle();
  assert.deepEqual(calls.panels, ['time', 'time', 'more']);
  assert.equal(model.state.pulses.length, 3);
});

test('default off; initialization needs foreground and consent; setting survives recreation', async () => {
  const { service, state, driver, preferences, guard } = fixture();
  await service.initialize();
  assert.equal(service.status().loaded, false);
  service.setForeground(true);
  state.consent = false;
  await service.initialize();
  assert.equal(await service.setEnabled(true), false);
  assert.equal(state.queries.length, 0);
  state.consent = true;
  await service.initialize();
  assert.equal(await service.selection('Moon'), false);
  assert.equal(await service.setEnabled(true), true);
  const recreated = new HapticFeedback(driver, preferences, guard);
  recreated.setForeground(true);
  await recreated.initialize();
  assert.equal(recreated.status().enabled, true);
  assert.equal(await recreated.selection('Moon'), true);
  await recreated.setEnabled(false);
  assert.equal(state.stored, false);
  assert.equal(await recreated.menu(), false);
});

test('semantic presets, gentle gains, duplicate selection and global throttle', async () => {
  const { service, state, ready } = fixture();
  await ready();
  assert.equal(await service.selection('Moon'), true);
  assert.equal(await service.selection('Moon'), false);
  assert.equal(await service.menu(), false);
  state.now += 120;
  assert.equal(await service.menu(), true);
  state.now += 300;
  assert.equal(await service.confirmation(), true);
  state.now += 600;
  assert.equal(await service.error(), true);
  state.now += 120;
  assert.equal(await service.error(), false);
  assert.deepEqual(state.pulses, [
    { effect: soft, intensity: 30 }, { effect: soft, intensity: 30 },
    { effect: success, intensity: 40 }, { effect: failure, intensity: 40 }
  ]);
  await service.selection('');
  state.now += 120;
  assert.equal(await service.selection('Moon'), true);
});

test('ruler only emits for changed detents in an active gesture, never replays skipped ticks', async () => {
  const { service, state, ready } = fixture();
  await ready();
  assert.equal(await service.rulerTick(1), false);
  service.beginRuler(0);
  assert.equal(await service.rulerTick(0), false);
  assert.equal(await service.rulerTick(1), true);
  assert.equal(await service.rulerTick(200), false);
  state.now += 150;
  assert.equal(await service.rulerTick(200), false);
  assert.equal(await service.rulerTick(199), true);
  assert.equal(await service.rulerTick(NaN), false);
  service.endRuler();
  state.now += 150;
  assert.equal(await service.rulerTick(198), false);
  assert.deepEqual(state.pulses.map(pulse => pulse.intensity), [20, 20]);
});

test('unsupported hardware remains silent, semantic presets fall back only to supported soft', async () => {
  const unsupported = fixture([]);
  await unsupported.ready();
  assert.equal(unsupported.service.status().available, false);
  assert.equal(await unsupported.service.error(), false);
  assert.equal(unsupported.state.pulses.length, 0);
  const fallback = fixture([soft]);
  await fallback.ready();
  assert.equal(await fallback.service.confirmation(), true);
  assert.equal(fallback.state.pulses[0].effect, soft);
});

test('foreground and current privacy guard stop feedback; guard exceptions fail closed', async () => {
  const { service, state, guard, ready } = fixture();
  await ready();
  await service.menu();
  service.setForeground(false);
  assert.equal(await service.confirmation(), false);
  assert.equal(state.stops, 1);
  service.setForeground(true);
  state.consent = false;
  state.now += 1000;
  assert.equal(await service.error(), false);
  guard.hasConsent = () => { throw new Error('privacy unavailable'); };
  assert.equal(await service.selection('Mars'), false);
  assert.equal(state.pulses.length, 1);
});

test('late start acknowledgement after background/foreground is cancelled, never queues events', async () => {
  const { service, driver, state, ready } = fixture();
  await ready();
  const start = deferred();
  driver.start = () => start.promise;
  const pulse = service.menu();
  service.setForeground(false);
  service.setForeground(true);
  state.now += 1000;
  assert.equal(await service.confirmation(), false);
  start.resolve();
  assert.equal(await pulse, false);
  assert.ok(state.stops >= 2);
});

test('capability query finishing after background is ignored and emits nothing', async () => {
  const { service, driver, state } = fixture();
  const query = deferred();
  driver.supports = () => query.promise;
  service.setForeground(true);
  const initializing = service.initialize();
  await Promise.resolve();
  service.setForeground(false);
  query.resolve(true);
  await initializing;
  assert.equal(service.status().available, false);
  assert.equal(service.status().probing, false);
  assert.equal(state.pulses.length, 0);
});

for (const rejected of [false, true]) {
  test(`resume restarts an invalidated pending probe after ${rejected ? 'rejection' : 'resolution'}`, async () => {
    const { service, driver, state } = fixture();
    const stale = deferred();
    const fresh = deferred();
    state.stored = true;
    driver.supports = effect => {
      state.queries.push(effect);
      if (state.queries.length === 1) return stale.promise;
      if (state.queries.length === 2) return fresh.promise;
      return Promise.resolve(true);
    };
    service.setForeground(true);
    const initial = service.initialize();
    await settle();
    assert.deepEqual(state.queries, [soft]);
    service.setForeground(false);
    service.setForeground(true);
    const resumed = service.initialize();
    const duplicate = service.initialize();
    let resumedDone = false;
    void resumed.then(() => { resumedDone = true; });
    assert.deepEqual(state.queries, [soft], 'wait for stale probe before starting another');
    if (rejected) stale.reject(new Error('stale query'));
    else stale.resolve(true);
    await initial;
    await settle();
    assert.deepEqual(state.queries, [soft, soft], 'coalesce concurrent resume requests into one fresh probe');
    assert.equal(resumedDone, false, 'resume waits for fresh capability results');
    assert.equal(service.status().available, false, 'stale capability result is discarded');
    assert.equal(await service.menu(), false);
    fresh.resolve(true);
    await Promise.all([resumed, duplicate]);
    assert.deepEqual(state.queries, [soft, soft, success, failure]);
    assert.equal(service.status().probing, false);
    assert.equal(service.status().available, true);
    assert.equal(state.pulses.length, 0, 'initialization never replays feedback');
    assert.equal(await service.menu(), true);
  });
}

test('queued probe restart rechecks foreground and consent when the stale probe settles', async () => {
  for (const revoked of ['foreground', 'consent']) {
    const { service, driver, state } = fixture();
    const stale = deferred();
    driver.supports = effect => { state.queries.push(effect); return stale.promise; };
    service.setForeground(true);
    const initial = service.initialize();
    await settle();
    service.setForeground(false);
    service.setForeground(true);
    const resumed = service.initialize();
    if (revoked === 'foreground') service.setForeground(false);
    else state.consent = false;
    stale.resolve(true);
    await Promise.all([initial, resumed]);
    assert.deepEqual(state.queries, [soft]);
    assert.equal(service.status().probing, false);
    assert.equal(service.status().available, false);
    assert.equal(state.pulses.length, 0);
  }
});

test('rapid preference changes serialize and an old load cannot overwrite a newer off choice', async () => {
  const { service, preferences, state } = fixture();
  const read = deferred();
  preferences.readEnabled = () => read.promise;
  service.setForeground(true);
  const loading = service.initialize();
  const on = service.setEnabled(true);
  const off = service.setEnabled(false);
  await Promise.all([on, off]);
  read.resolve(true);
  await loading;
  assert.deepEqual(state.writes, [true, false]);
  assert.equal(state.stored, false);
  assert.equal(service.status().enabled, false);
});

test('persistence failure fails closed and leaves an explicit error', async () => {
  const { service, preferences, ready } = fixture();
  await ready();
  preferences.writeEnabled = async () => { throw new Error('disk'); };
  assert.equal(await service.setEnabled(false), false);
  assert.equal(service.status().enabled, false);
  assert.equal(service.status().lastFailure, 'preferences-write');
  assert.equal(await service.menu(), false);
});

test('native synchronous throws and rejections are contained without retry storms', async () => {
  for (const asynchronous of [false, true]) {
    const { service, driver, state, ready } = fixture();
    await ready();
    driver.start = () => {
      if (asynchronous) return Promise.reject(new Error('permission'));
      throw new Error('capability');
    };
    driver.stop = () => { throw new Error('stop unavailable'); };
    assert.equal(await service.menu(), false);
    assert.equal(service.status().available, false);
    state.now += 1000;
    assert.equal(await service.error(), false);
  }
});

test('native error code remains observable without exposing the platform error body', async () => {
  const { service, driver, ready } = fixture();
  await ready();
  driver.start = async () => { throw { code: 14600101, message: 'private platform text' }; };
  assert.equal(await service.menu(), false);
  assert.equal(service.status().lastErrorCode, 14600101);
  assert.equal(service.status().lastFailure, 'vibration-start');
  assert.ok(!JSON.stringify(service.status()).includes('private platform text'));
});

test('invalid or backward clock readings suppress feedback', async () => {
  const { service, state, ready } = fixture();
  await ready();
  assert.equal(await service.menu(), true);
  state.now = 0;
  assert.equal(await service.confirmation(), false);
  state.now = NaN;
  assert.equal(await service.error(), false);
});

test('platform adapter persists a boolean, checks capability and uses one system-controlled touch preset', async () => {
  const calls = [];
  let stored;
  const vibrator = {
    VibratorStopMode: { VIBRATOR_STOP_MODE_PRESET: 'preset' },
    async isSupportEffect(effect) { calls.push(['support', effect]); return true; },
    async startVibration(effect, attribute) { calls.push(['start', effect, attribute]); },
    async stopVibration(mode) { calls.push(['stop', mode]); }
  };
  const preferences = { getPreferencesSync(context, options) {
    assert.equal(options.name, 'stellarium_haptics');
    return {
      getSync: (key, fallback) => stored ?? fallback,
      putSync: (key, value) => { assert.equal(key, 'enabled_v1'); stored = value; },
      async flush() { calls.push(['flush']); }
    };
  } };
  const clock = { TimeType: { STARTUP: 0 }, getUptime: () => 1000 };
  const source = stripTypeScriptTypes(read('HarmonyHapticFeedback').replace(/^import .*\n/gm, '').replaceAll('export ', ''));
  const create = new Function('HapticFeedback', 'preferences', 'systemDateTime', 'vibrator', 'canIUse', 'hasCurrentPrivacyConsent', source + ';return createHapticFeedback;')(
    HapticFeedback, preferences, clock, vibrator,
    capability => { assert.equal(capability, 'SystemCapability.Sensors.MiscDevice'); return true; }, () => true
  );
  const service = create({});
  service.setForeground(true);
  await service.initialize();
  await service.setEnabled(true);
  await service.menu();
  assert.deepEqual(calls.find(call => call[0] === 'start'), [
    'start', { type: 'preset', effectId: soft, count: 1, intensity: 30 }, { usage: 'touch' }
  ]);
  service.setForeground(false);
  assert.ok(calls.some(call => call[0] === 'stop' && call[1] === 'preset'));
  assert.equal(stored, true);
});
