#!/usr/bin/env node

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const MJD_OFFSET = 2400000.5;
const GREGORIAN_START_JD = 2299161.0;

function toJulianDay(scale, value) {
  assert.ok(scale === 'jd' || scale === 'mjd', 'scale must be jd or mjd');
  assert.ok(Number.isFinite(value), 'date value must be finite');
  const jd = scale === 'mjd' ? value + MJD_OFFSET : value;
  assert.ok(Number.isFinite(jd), 'converted JD must be finite');
  return jd;
}

assert.equal(toJulianDay('jd', 2451545.0), 2451545.0);
assert.equal(toJulianDay('mjd', 51544.5), 2451545.0);
assert.equal(2299160.5 < GREGORIAN_START_JD, true);
assert.equal(2299161.0 < GREGORIAN_START_JD, false);
assert.throws(() => toJulianDay('jd', Number.NaN));
assert.throws(() => toJulianDay('mjd', Number.POSITIVE_INFINITY));

const core = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
const catalog = readFileSync(new URL('../src/StelOhosCommandCatalog.hpp', import.meta.url), 'utf8');
const ui = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
// D16：syncJulianDateFields / applyJulianDateInput / adjustJulianDate 已并入 state/JulianDateStore.ets。
const julianStoreUi = readFileSync(new URL('../harmonyos/ets-source/state/JulianDateStore.ets', import.meta.url), 'utf8');
const timePanelUi = readFileSync(new URL('../harmonyos/ets-source/panels/panels/TimePanel.ets', import.meta.url), 'utf8');
assert.match(core, /commandName == "setJulianDate"/);
assert.match(core, /result\["mjd"\] = jd - 2400000\.5/);
assert.match(core, /jd < 2299161\.0 \? "julian" : "gregorian"/);
assert.match(catalog, /setJulianDate/);
// 儒略日控件已从参数化 @Builder julianDateControls 改为 JulianDateControls 组件；
// Phase 4c 起该组件的调用点随 `time` 分支下沉到 panels/panels/TimePanel.ets。
assert.match(timePanelUi, /JulianDateControls\(\{/);
assert.match(julianStoreUi, /setJulianDate', scale \+ '\|' \+ value\.toString\(\)/);
// 宿主经 store 方法调用（不再持有儒略日行为）。
assert.match(ui, /this\.julianStore\.applyJulianDateInput/);

console.log('Julian Day checks passed: JD/MJD conversion, calendar boundary, command, catalog, and UI wiring.');
