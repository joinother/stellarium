import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const require = createRequire(import.meta.url);
const ts = require(process.env.TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const source = fs.readFileSync(new URL('../harmonyos/ets-source/state/SatelliteStore.ets', import.meta.url), 'utf8').replace('@Observed', '');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;

function fixture() {
  const intervals = new Map();
  const timeouts = new Map();
  let nextId = 0;
  const exports = {};
  vm.runInNewContext(compiled, {
    exports,
    require: () => ({ I18n: { t: key => key, format: key => key } }),
    setInterval: callback => { intervals.set(++nextId, callback); return nextId; },
    clearInterval: id => intervals.delete(id),
    setTimeout: callback => { timeouts.set(++nextId, callback); return nextId; },
    clearTimeout: id => timeouts.delete(id)
  });
  const store = new exports.SatelliteStore();
  const state = {
    pending: false, reads: 0,
    settings: { updatesEnabled: true, autoAddEnabled: true, autoRemoveEnabled: false,
      autoDisplayEnabled: true, updateFrequencyHours: 72, secondsToUpdate: 259200,
      updateState: 1, lastCheckResult: 1, lastCheckedAt: '2026-11-12T00:00:00Z' }
  };
  store.attachPort({
    requestWhenReady(name, payload, callback) {
      if (name === 'getSatelliteSources') {
        callback({ ok: true, sources: [], settings: { ...state.settings } });
      } else if (name === 'getSatellites') {
        state.reads++;
        callback(state.pending ? { ok: false, error: 'pending' } : {
          ok: true, satellites: { groups: [], items: [], count: 42, matchedCount: 42,
            newestUpdate: '2026-11-10T00:00:00Z', outdatedCount: 0,
            offline: false, observerIsEarth: true, dateInRange: true }
        });
      } else assert.fail(name);
    }
  }, () => {});
  const flush = () => {
    const pending = [...timeouts.values()];
    timeouts.clear();
    for (const callback of pending) callback();
  };
  const poll = () => { for (const callback of [...intervals.values()]) callback(); };
  return { store, state, intervals, timeouts, flush, poll };
}

test('visible panel recovers a pending first catalogue read without reopening', () => {
  const context = fixture();
  context.state.pending = true;
  context.store.observePanel(true);
  context.flush();
  assert.equal(context.state.reads, 1);
  assert.equal(context.store.satelliteListLoading, false);
  context.state.pending = false;
  context.poll();
  context.flush();
  assert.equal(context.store.satCount, 42);
  context.poll();
  context.flush();
  assert.equal(context.state.reads, 2);
  context.store.observePanel(false);
  assert.equal(context.intervals.size, 0);
});

test('background status polling preserves an unsaved interval edit', () => {
  const context = fixture();
  context.store.observePanel(true);
  context.flush();
  context.store.satUpdateFrequencyInput = '12';
  context.poll();
  assert.equal(context.store.satUpdateFrequencyInput, '12');
  context.state.settings.updateFrequencyHours = 24;
  context.poll();
  assert.equal(context.store.satUpdateFrequencyInput, '24');
});

test('unchanged-data completion updates details even when the updating state was missed', () => {
  const context = fixture();
  context.store.observePanel(true);
  context.flush();
  context.state.settings.lastCheckedAt = '2026-11-12T01:00:00Z';
  context.poll();
  context.flush();
  assert.equal(context.state.reads, 2);
  assert.equal(context.store.satSourceStatus, 'sat_refresh_unchanged');
  assert.equal(context.store.satUpdateSettings.lastCheckedAt, context.state.settings.lastCheckedAt);
  assert.equal(context.store.satNewestUpdate, '2026-11-10T00:00:00Z');
});

test('unloaded settings never claim the saved automatic choice is disabled', () => {
  const context = fixture();
  assert.equal(context.store.satelliteUpdateStatusText(), 'sat_reading_settings');
  context.store.observePanel(true);
  assert.equal(context.store.satUpdateSettings.updatesEnabled, true);
  assert.equal(context.store.satelliteUpdateStatusText(), 'sat_update_hours');
});
