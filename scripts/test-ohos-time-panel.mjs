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
const { TimeWheelController } = await sourceModule('state/TimeWheelController.ets');

globalThis.TouchType = { Down: 0, Move: 1, Up: 2, Cancel: 3 };

function touchEvent(type, x, y) {
  return { type, touches: [{ x, y }], changedTouches: [{ x, y }] };
}

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

test('vertical panel scrolling never pauses or changes the time wheel', () => {
  const store = new TimeWheelStore();
  store.timeWheelYear = 2026;
  store.timeWheelMonth = 11;
  store.timeWheelDay = 20;
  store.timeWheelHour = 22;
  store.timeWheelMinute = 0;
  store.timeWheelSecond = 0;
  store.timeWheelUnit = 'hour';
  store.timeWheelVisualOffset = 0;
  store.timeWheelAppliedSteps = 0;
  store.refreshTicks();
  let seeks = 0;
  let stops = 0;
  const wheel = new TimeWheelController(store, () => { seeks += 1; }, () => { stops += 1; }, () => 0, () => {});

  wheel.handleTouch(touchEvent(TouchType.Down, 100, 100));
  wheel.handleTouch(touchEvent(TouchType.Move, 102, 40));
  assert.equal(store.timeWheelDragging, false);
  assert.equal(stops, 0);
  wheel.handleTouch(touchEvent(TouchType.Up, 102, 40));
  assert.equal(seeks, 0);
  assert.equal(store.timeWheelDragging, false);

  // A clear horizontal drag still takes over and seeks the simulation time.
  wheel.handleTouch(touchEvent(TouchType.Down, 100, 100));
  wheel.handleTouch(touchEvent(TouchType.Move, 170, 102));
  assert.equal(store.timeWheelDragging, true);
  wheel.handleTouch(touchEvent(TouchType.Up, 170, 102));
  assert.equal(stops, 1);
  assert.ok(seeks > 0);
  wheel.stop();
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
  assert.doesNotMatch(host, /onWheelTouch: \(event: TouchEvent\)/);
  assert.doesNotMatch(host, /onWheelPanStart/);
  assert.match(host, /onWheelRect: \(x: number, y: number, width: number, height: number\) => \{/);
  assert.match(host, /this\.handleTimeWheelTouch\(event\)/);
  assert.match(host, /this\.wheel\(\)\.beginPan\(this\.timeWheelTouchStartX, this\.timeWheelTouchStartY\)/);
  const canvas = readFileSync(new URL('../harmonyos/ets-source/panels/time/TimeWheelCanvas.ets', import.meta.url), 'utf8');
  assert.doesNotMatch(canvas, /\.gesture\(/);
  assert.match(canvas, /\.hitTestBehavior\(HitTestMode\.None\)/);
});

test('time wheel flywheel caps runaway speed and immediately reverses when pushed in the opposite direction', () => {
  const store = new TimeWheelStore();
  store.timeWheelYear = 2026;
  store.timeWheelMonth = 11;
  store.timeWheelDay = 22;
  store.timeWheelHour = 16;
  store.timeWheelMinute = 0;
  store.timeWheelSecond = 0;
  store.timeWheelUnit = 'hour';
  store.refreshTicks();

  const wheel = new TimeWheelController(store, () => {}, () => {}, () => 8, () => {});
  const realNow = Date.now;
  let fakeNow = 100000;
  Date.now = () => fakeNow;
  try {
    // 1. Spin hard to the left (negative visual velocity) multiple times.
    for (let rep = 0; rep < 4; rep++) {
      wheel.beginPan(300, 100);
      fakeNow += 20;
      wheel.updatePan(180);
      fakeNow += 20;
      wheel.updatePan(60);
      fakeNow += 10;
      wheel.endPan(false);
    }
    assert.equal(wheel.isSpinning(), true);
    const leftVel = wheel.inertiaVelocity;
    assert.ok(leftVel < -0.5, `expected strong leftward spin, got ${leftVel}`);
    assert.ok(Math.abs(leftVel) <= 2.6 + 1e-6, `expected flywheel capped <= 2.6 vp/ms, got ${leftVel}`);

    // 2. While spinning fast left, push hard to the RIGHT: must immediately spin RIGHT (positive)!
    fakeNow += 30;
    wheel.captureSpinOnTouchDown();
    wheel.beginPan(80, 100);
    fakeNow += 20;
    wheel.updatePan(180);
    fakeNow += 20;
    wheel.updatePan(280);
    fakeNow += 10;
    wheel.endPan(false);
    assert.equal(wheel.isSpinning(), true);
    assert.ok(wheel.inertiaVelocity > 0.2, `expected immediate reversal to rightward spin, got ${wheel.inertiaVelocity}`);

    // 3. Pause finger >= 100ms before lift: must brake cleanly without flinging.
    fakeNow += 30;
    wheel.captureSpinOnTouchDown();
    wheel.beginPan(100, 100);
    fakeNow += 20;
    wheel.updatePan(160);
    fakeNow += 120;
    wheel.endPan(false);
    assert.equal(wheel.isSpinning(), false);
  } finally {
    Date.now = realNow;
    wheel.stop();
  }
});

test('time speed ladder has true 1h/s (3600s/s), immediate visible first tap, and coherent rewind/fast/slower rules', async () => {
  const { TIME_SPEED_STEPS, TIME_SPEED_IDX_STOP, TIME_SPEED_IDX_REALTIME, TIME_SPEED_IDX_FAST_START, TIME_SPEED_IDX_REWIND_START } =
    await sourceModule('state/TimeStore.ets');
  assert.equal(TIME_SPEED_STEPS[TIME_SPEED_IDX_STOP], 0);
  assert.ok(Math.abs(TIME_SPEED_STEPS[TIME_SPEED_IDX_REALTIME] - 1 / 86400) < 1e-12);
  assert.ok(Math.abs(TIME_SPEED_STEPS[TIME_SPEED_IDX_FAST_START] - 600 / 86400) < 1e-12, 'first fast tap must be 10m/s');
  assert.ok(Math.abs(TIME_SPEED_STEPS[TIME_SPEED_IDX_FAST_START + 1] - 3600 / 86400) < 1e-12, '1h/s must be true 3600s/s');
  assert.ok(Math.abs(TIME_SPEED_STEPS[TIME_SPEED_IDX_REWIND_START] - (-600 / 86400)) < 1e-12, 'first rewind tap must be -10m/s');
  assert.ok(Math.abs(TIME_SPEED_STEPS[TIME_SPEED_IDX_REWIND_START - 1] - (-3600 / 86400)) < 1e-12, '-1h/s must be true -3600s/s');

  const ctrlSrc = readFileSync(new URL('../harmonyos/ets-source/capability/TimeController.ets', import.meta.url), 'utf8');
  assert.ok(ctrlSrc.includes('this.hooks.stopTimeWheel?.()'), 'speed buttons must stop spinning time wheel');
  const chipsSrc = readFileSync(new URL('../harmonyos/ets-source/panels/time/TimeSpeedChips.ets', import.meta.url), 'utf8');
  assert.ok(chipsSrc.includes('statusRateSummary()'), 'TimeSpeedChips must always display live speed summary');
});
