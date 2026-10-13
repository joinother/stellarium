import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

// The smooth astronomy jump now lives in capability/TimeTransitionController.ets;
// the time wheel keeps the upstream gesture-step controller.
const read = path => readFileSync(new URL('../harmonyos/ets-source/' + path, import.meta.url), 'utf8');
const ctl = read('capability/TimeTransitionController.ets');
const duration = ctl.slice(ctl.indexOf('private durationMs('), ctl.indexOf('// 停过渡并（可选）恢复原速率'));
const astro = ctl.slice(ctl.indexOf('animate(targetJd'), ctl.indexOf('private finish('));
const wheel = read('state/TimeWheelController.ets');

test('long astronomy jumps use distance-aware eased timing', () => {
  assert.match(duration, /Math\.log10/);
  assert.match(duration, /Math\.pow\(normalized, 1\.45\)/);
  assert.match(duration, /Math\.max\(900, Math\.min\(7000/);
  assert.match(astro, /const distanceDays = distanceSeconds \/ 86400\.0/);
  assert.match(astro, /this\.durationMs\(distanceDays\)/);
  assert.match(astro, /distanceDays >= 30 \? 32 : 48/);
  assert.match(astro, /const useNativeRate = distanceDays >= 3\.0/);
  assert.match(astro, /this\.usesNativeRate = true/);
  assert.match(astro, /this\.hooks\.setTimeRate\(travelRate\)/);
  assert.match(astro, /if \(useNativeRate\)/);
});

test('the time wheel advances through gesture steps with a bounded velocity multiplier', () => {
  assert.match(wheel, /velocityMultiplier\(/);
  assert.match(wheel, /this\.store\.timeWheelUnit = unit/);
  assert.match(wheel, /dateAtFraction\(/);
});
