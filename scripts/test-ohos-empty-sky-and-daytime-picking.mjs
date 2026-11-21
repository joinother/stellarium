import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = p => readFileSync(new URL(p, import.meta.url), 'utf8');

const touchPickerCpp = read('../src/core/TouchPicker.cpp');
const planetCpp = read('../src/core/modules/Planet.cpp');
const mainWindowEts = read('../harmonyos/ets-source/pages/MainWindowNativeNode.ets');
const skyInputEts = read('../harmonyos/ets-source/capability/SkyInputController.ets');

test('TouchPicker mirrors StarMgr daytime star visibility via computeStarRCMag and getStarLimitMagnitude', () => {
  assert.match(touchPickerCpp, /drawer->getStarLimitMagnitude\(\)/);
  assert.match(touchPickerCpp, /qMin\(static_cast<float>\(drawer->getCustomStarMagnitudeLimit\(\)\),\s*drawerStarLimit\)/);
  assert.match(touchPickerCpp, /drawer->computeStarRCMag\(mag,\s*&rc\)/);
  assert.match(touchPickerCpp, /core->getSkyDrawer\(\)->computeStarRCMag\(mag,\s*&rc\)/);
  assert.match(touchPickerCpp, /star->getVMagnitudeWithVisualExtinction\(core\)/);
  assert.match(touchPickerCpp, /labelLimitMag\s*=\s*\(drawerStarLimit\s*-\s*6\.5\)/);
});

test('TouchPicker enforces visual luminance gate and salience-scaled touch acceptance radii', () => {
  assert.match(touchPickerCpp, /minPickLuminance\s*=\s*core->isBrightDaylight\(\)\s*\?\s*0\.30f\s*:\s*0\.18f/);
  assert.match(touchPickerCpp, /if\s*\(!labelHit\s*&&\s*effectiveLum\s*<\s*minPickLuminance\)/);
  assert.match(touchPickerCpp, /starAcceptVp\s*=\s*qMin\(effectiveRadiusVp,\s*34\.0\)/);
  assert.match(touchPickerCpp, /starAcceptVp\s*=\s*qMin\(effectiveRadiusVp,\s*24\.0\)/);
  assert.match(touchPickerCpp, /starAcceptVp\s*=\s*qMin\(effectiveRadiusVp,\s*14\.0\)/);
  assert.match(touchPickerCpp, /planetAcceptVp\s*=\s*profile\.touch\s*\?\s*qMin\(effectiveRadiusVp,\s*minorBody\s*\?\s*22\.0\s*:\s*38\.0\)/);
  assert.match(touchPickerCpp, /dsoAcceptVp\s*=\s*profile\.touch\s*\?\s*qMin\(effectiveRadiusVp,\s*28\.0\)/);
  assert.match(touchPickerCpp, /satAcceptVp\s*=\s*profile\.touch\s*\?\s*qMin\(effectiveRadiusVp,\s*40\.0\)/);
});

test('Planet::getPickState excludes invisible minor bodies, faint moons, and observer own planet', () => {
  const start = planetCpp.indexOf('StelObjectPickState Planet::getPickState(');
  assert.ok(start >= 0, 'Planet::getPickState missing');
  const end = planetCpp.indexOf('\nVec3f Planet::getInfoColor(', start);
  const body = planetCpp.slice(start, end);
  assert.match(body, /core->getCurrentPlanet\(\)\.data\(\)\s*==\s*this/);
  assert.match(body, /cutDimObjects/);
  assert.match(body, /getMarkerMagThreshold\(\)/);
  assert.match(body, /getVMagnitudeWithVisualExtinction\(core,\s*vMag\)/);
  assert.match(body, /drawer->computeRCMag\(vMagVis,\s*&rc\)/);
  assert.match(body, /!discVisible\s*&&\s*!labelVisible\s*&&\s*!markerVisible\s*&&\s*!haloVisible\s*&&\s*!cometVisible/);
  assert.doesNotMatch(body, /getVMagnitudeWithExtinction\(/);
});

test('Single-tap empty sky cancels selection silently and resets double-tap sequence', () => {
  const start = mainWindowEts.indexOf('private requestSkySelection(');
  assert.ok(start >= 0, 'requestSkySelection missing');
  const end = mainWindowEts.indexOf('private clearSkySelectionFromDoubleTap(', start);
  const body = mainWindowEts.slice(start, end);
  assert.match(body, /this\.skyInputCtl\(\)\.resetSkyTapSequence\(\)/);
  assert.doesNotMatch(body, /flashHint\(I18n\.t\('i0075'\)\)/);
  assert.match(skyInputEts, /tapInterval\s*<=\s*360/);
});

test('Salience-scaled star picking math accepts visible daytime/night stars and rejects empty-sky ghosts', () => {
  function canPickStar({ mag, lum, rVp, distVp, daylight, labelHit = false, effectiveRadiusVp = 66 }) {
    const minLum = daylight ? 0.30 : 0.18;
    if (!labelHit && lum < minLum) return false;
    let acceptVp = effectiveRadiusVp;
    if (mag <= 2.5 || rVp >= 2.2) acceptVp = Math.min(effectiveRadiusVp, 34);
    else if (lum >= 0.65 || mag <= 4.2) acceptVp = Math.min(effectiveRadiusVp, 24);
    else acceptVp = Math.min(effectiveRadiusVp, 14);
    return labelHit || distVp <= acceptVp + rVp;
  }

  // Bright star in daytime (e.g. Vega mag 0.03, lum 1.0) tapped 20vp away -> picked!
  assert.equal(canPickStar({ mag: 0.03, lum: 1.0, rVp: 3.0, distVp: 20, daylight: true }), true);
  // Washed-out dim star in daytime (mag 5.4, lum 0.14) tapped right on top -> rejected!
  assert.equal(canPickStar({ mag: 5.4, lum: 0.14, rVp: 1.0, distVp: 4, daylight: true }), false);
  // Night sub-threshold invisible speck (mag 6.1, lum 0.08) tapped 5vp away -> rejected!
  assert.equal(canPickStar({ mag: 6.1, lum: 0.08, rVp: 0.9, distVp: 5, daylight: false }), false);
  // Night faint visible star (mag 5.0, lum 0.30) tapped directly (10vp) -> picked; empty sky (22vp) -> rejected!
  assert.equal(canPickStar({ mag: 5.0, lum: 0.30, rVp: 1.0, distVp: 10, daylight: false }), true);
  assert.equal(canPickStar({ mag: 5.0, lum: 0.30, rVp: 1.0, distVp: 22, daylight: false }), false);
  // Empty sky 45vp away from even a bright star -> rejected (triggers single-tap cancel)!
  assert.equal(canPickStar({ mag: 0.5, lum: 1.0, rVp: 2.5, distVp: 45, daylight: false }), false);
});
