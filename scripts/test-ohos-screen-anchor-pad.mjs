import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

const device = process.argv[2];
if (!device) throw new Error('Usage: node scripts/test-ohos-screen-anchor-pad.mjs <device> [report.json]');
const root = new URL('../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const report = { device, cases: [], results: {}, startedAt: new Date().toISOString() };
const pause = milliseconds => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
const call = (command, payload) => {
  const args = [join(root, 'scripts/stellarium-cli.mjs'), '--device', device, '--json', '--timeout', '12000', '--command', command];
  if (payload !== undefined) args.push('--payload', String(payload));
  const result = JSON.parse(execFileSync(process.execPath, args, { encoding: 'utf8', timeout: 20000 }));
  assert.equal(result.ok, true, `${command}: ${JSON.stringify(result)}`);
  return result;
};
const stable = (before, after) => {
  assert.equal(before.valid, true);
  assert.equal(after.valid, true);
  assert.ok(Math.abs(before.xRatio - after.xRatio) * 2560 < 2, 'horizontal release drift');
  assert.ok(Math.abs(before.yRatio - after.yRatio) * 1600 < 2, 'vertical release drift');
};
const original = call('getSessionState');
const originalLock = call('getViewAnchorState').viewLock;
try {
  assert.equal(call('searchObject', 'M31|selectOnly').viewLock, true);
  report.cases.push('selection-default-locked');
  call('moveToSelected');
  pause(1200);
  call('setFOV', '30');
  pause(800);
  call('panBy', '90|60|2560|1600');
  pause(200);
  call('setViewAnchorProbe', 'true');
  const before = call('getGyroGuidePosition');
  const point = `${before.xRatio * 2560}|${before.yRatio * 1600}|2560|1600`;
  call('zoomBy', `1|1|${point}`);
  assert.equal(call('getViewAnchorState').pinchMode, 'selectedObject');
  for (const scale of [4, 16, 2, 32, 80]) call('zoomBy', `${scale}|0|${point}`);
  call('endPinch');
  pause(700);
  const after = call('getGyroGuidePosition');
  stable(before, after);
  const selected = call('getViewAnchorState');
  assert.ok(selected.samples > 0);
  assert.ok(selected.maxErrorPixels < 2, 'per-frame anchor residual');
  assert.equal(selected.pinchActive, false);
  assert.equal(selected.settling, false);
  report.results.selected = { before, after, ...selected };
  report.cases.push('rapid-selected-zoom-and-release');
  call('setViewAnchorProbe', 'true');
  call('zoomBy', '1|1|200|240|2560|1600');
  assert.equal(call('getViewAnchorState').pinchMode, 'skyPoint');
  call('zoomBy', '1.25|0|220|260|2560|1600');
  call('zoomBy', '1.5|0|240|280|2560|1600');
  call('endPinch');
  pause(700);
  const released = call('getGyroGuidePosition');
  pause(600);
  const settled = call('getGyroGuidePosition');
  stable(released, settled);
  assert.ok(Math.hypot(released.xRatio - after.xRatio, released.yRatio - after.yRatio) > 0.01,
    'off-target pinch must move the selected target instead of locking its old position');
  report.results.skyPoint = { released, settled, ...call('getViewAnchorState') };
  report.cases.push('off-target-zoom-handoff-without-snapback');
  call('setViewLock', 'false');
  pause(200);
  assert.equal(call('getViewAnchorState').viewLock, false);
  assert.equal(call('searchObject', 'Moon|selectOnly').viewLock, true);
  call('clearSelection');
  assert.equal(call('getViewAnchorState').viewLock, false);
  report.cases.push('unlock-reselect-clear');
  report.passed = true;
} catch (error) {
  report.passed = false;
  report.error = String(error);
  process.exitCode = 1;
} finally {
  call('setViewAnchorProbe', 'false');
  call('applySessionState', JSON.stringify({ viewJ2000: original.viewJ2000, fovDeg: original.fovDeg, selected: original.selected }));
  if (original.selected) call('setViewLock', originalLock ? 'true' : 'false');
  if (process.argv[3]) writeFileSync(process.argv[3], JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
}
