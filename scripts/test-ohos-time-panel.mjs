import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

async function sourceModule(relativePath) {
  const source = readFileSync(new URL('../harmonyos/ets-source/' + relativePath, import.meta.url), 'utf8')
    .replace(/@Observed\r?\n/, '')
    .replace(/^import .*$/gm, '');
  return import('data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source)));
}

const { TimeWheelStore } = await sourceModule('state/TimeWheelStore.ets');
const { TimeStore } = await sourceModule('state/TimeStore.ets');

test('the time wheel starts from the current wall clock, not a hardcoded date', () => {
  const before = new Date();
  const store = new TimeWheelStore();
  const after = new Date();
  const initialMs = Date.UTC(store.timeWheelYear, store.timeWheelMonth - 1, store.timeWheelDay,
    store.timeWheelHour, store.timeWheelMinute, store.timeWheelSecond);
  const beforeMs = Date.UTC(before.getFullYear(), before.getMonth(), before.getDate(),
    before.getHours(), before.getMinutes(), before.getSeconds());
  const afterMs = Date.UTC(after.getFullYear(), after.getMonth(), after.getDate(),
    after.getHours(), after.getMinutes(), after.getSeconds());
  assert.ok(initialMs >= beforeMs - 1000 && initialMs <= afterMs + 1000);
  assert.equal(store.timeWheelTickLabels.length, store.centerTick * 2 + 1);
  assert.ok(store.timeWheelTickLabels.some(label => label.length > 0));
});

test('manual time uses the observation-local wall clock', () => {
  const store = new TimeStore();
  const jd = Date.UTC(2026, 10, 7, 15, 0, 0) / 86400000 + 2440587.5;
  store.syncManualTimeFromJd(jd, 8);
  assert.equal(store.manualYear, 2026);
  assert.equal(store.manualMonth, 11);
  assert.equal(store.manualDay, 7);
  assert.equal(store.manualHour, 23);
  assert.equal(store.manualMinute, 0);
});

test('the tablet clock anchor keeps edgeMargin and skyWidth in the declared order', () => {
  const geometry = readFileSync(new URL('../harmonyos/ets-source/common/derive/geometry.ets', import.meta.url), 'utf8');
  const start = geometry.indexOf('export function chromeRowPosXRight(');
  assert.ok(start >= 0);
  const body = geometry.slice(start, geometry.indexOf('\n}', start) + 2).replace('export ', '');
  const resolve = new Function('dockWidthPixels', 'dockLeft',
    stripTypeScriptTypes(body) + '\nreturn chromeRowPosXRight;')(() => 600, () => 44);
  assert.equal(resolve(true, 44, 1000, false, 0, 0, 80), 356);
  assert.equal(resolve(false, 44, 1000, false, 0, 0, 80), 44);

  const host = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
  assert.match(host, /chromeRowPosXRight\(this\.isExpandedLayout, this\.EDGE_MARGIN, this\.skyWidth,/);
  assert.doesNotMatch(host, /chromeRowPosXRight\(this\.isExpandedLayout, this\.skyWidth, this\.EDGE_MARGIN,/);
  assert.match(host, /if \(panel === 'time' && nextVisible\) this\.prepareTimePanel\(\)/);
  assert.match(host, /this\.wheel\(\)\.seedFromSimulation\(jd\)/);
});
