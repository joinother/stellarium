import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const satHpp = readFileSync(new URL('../plugins/Satellites/src/Satellite.hpp', import.meta.url), 'utf8');
const satCpp = readFileSync(new URL('../plugins/Satellites/src/Satellite.cpp', import.meta.url), 'utf8');
const satsCpp = readFileSync(new URL('../plugins/Satellites/src/Satellites.cpp', import.meta.url), 'utf8');
const mainViewCpp = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
const passDetailsEts = readFileSync(new URL('../harmonyos/ets-source/panels/object/SatellitePassDetails.ets', import.meta.url), 'utf8');
const structRowsEts = readFileSync(new URL('../harmonyos/ets-source/panels/object/StructuredDetailRows.ets', import.meta.url), 'utf8');
const satStoreEts = readFileSync(new URL('../harmonyos/ets-source/state/SatelliteStore.ets', import.meta.url), 'utf8');
const mainNodeEts = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');

test('HarmonyOS enables selected-satellite orbit arc by default while preserving global toggle', () => {
  assert.match(satsCpp, /#ifdef Q_OS_OHOS[\s\S]*?conf->setValue\("orbit_line_flag", true\)/);
  assert.match(satsCpp, /#ifdef Q_OS_OHOS[\s\S]*?conf->value\("orbit_line_flag", true\)\.toBool\(\)/);
  assert.match(satStoreEts, /satOrbitLines:\s*boolean\s*=\s*true/);
  assert.match(satCpp, /shouldDisplayOrbit\(\) && Satellite::orbitLinesFlag && orbitValid/);
});

test('selected satellite orbit arc expands smoothly outward as a wide AA ribbon with shadow dashes and landmarks', () => {
  assert.match(satHpp, /float\s+orbitExpandProgress\s*=\s*0\.f;/);
  assert.match(satHpp, /double\s+orbitStepSeconds\s*=\s*5\.0;/);
  const drawOrbit = satCpp.slice(satCpp.indexOf('void Satellite::drawOrbit('), satCpp.indexOf('float Satellite::calculateOrbitSegmentIntensity('));
  // Cubic ease-out outward reveal from centerIdx
  assert.match(drawOrbit, /revealT = orbitDisplayed \? 1\.0f : \(1\.0f - invT \* invT \* invT\)/);
  // Wide 3-band anti-aliased triangle ribbon
  assert.match(drawOrbit, /pushQuad\(p0 - s0 \* oW0, p0 - s0 \* cW0/);
  assert.match(drawOrbit, /pushQuad\(p0 - s0 \* cW0, p0 \+ s0 \* cW0/);
  assert.match(drawOrbit, /pushQuad\(p0 \+ s0 \* cW0, p0 \+ s0 \* oW0/);
  assert.match(drawOrbit, /painter\.drawFromArray\(StelPainter::Triangles, orbitRibbonVerts\.size\(\), 0, true\)/);
  // Dashed Earth-shadow segments & penumbra color
  assert.match(drawOrbit, /penumbraCol/);
  assert.match(drawOrbit, /dashMul/);
  // Orbital landmarks: direction chevron, minute ticks, shadow transition & culmination apex
  assert.match(drawOrbit, /chevronTargetArc/);
  assert.match(drawOrbit, /tickIntervalSec/);
  assert.match(drawOrbit, /emitDiamond/);
  assert.match(drawOrbit, /\+\+orbitDrawCount;/);
});

test('adaptive orbit sampling scales cleanly for LEO, MEO, and GSO while preserving validation guards', () => {
  const compute = satCpp.slice(satCpp.indexOf('void Satellite::computeOrbitPoints()'), satCpp.indexOf('bool operator <'));
  assert.match(compute, /orbitalPeriodMin > 900\.0/);
  assert.match(compute, /orbitalPeriodMin > 150\.0/);
  assert.equal((compute.match(/if \(!validSample\(\)\) return;/g) ?? []).length, 3);
  assert.match(compute, /pSatWrapper->setEpoch\(epochTime\);\r?\n\}/);
});

test('fast-time satellite streaks are razor-sharp needles without wide halos and use smoothstep(clamp(2t,0,1))', () => {
  // Tight instantaneous motion window in Satellite::update
  assert.match(satCpp, /maxSpanDays\s*=\s*0\.00045;/);
  assert.match(satCpp, /motionTrail\.size\(\) > 6/);
  // Razor-sharp needle rendering in Satellites::draw
  const draw = satsCpp.slice(satsCpp.indexOf('void Satellites::draw('), satsCpp.indexOf('void Satellites::drawPointer('));
  assert.match(draw, /const float t2 = qBound\(0\.f, 2\.0f \* static_cast<float>\(motionTrailActivity\), 1\.0f\);/);
  assert.match(draw, /const float trailEnv = t2 \* t2 \* \(3\.0f - 2\.0f \* t2\)/);
  assert.match(draw, /if \(!sunlit && !penumbra\)\s*\n\s*continue;/);
  assert.match(draw, /maxArcRad/);
  assert.match(draw, /std::pow\(u0, 2\.25f\)/);
  assert.doesNotMatch(draw, /emitSatRibbon\(2\.4/);
});

test('satellite detail view surfaces orbital metrics, radio frequencies, TLE age, and one-tap pass preview', () => {
  assert.match(mainViewCpp, /QStringLiteral\("eccentricity"\)/);
  assert.match(mainViewCpp, /QStringLiteral\("orbitalSpeed"\)/);
  assert.match(mainViewCpp, /QStringLiteral\("tleAge"\)/);
  assert.match(mainViewCpp, /QStringLiteral\("radioComms"\)/);
  assert.match(structRowsEts, /case 'tleAge': return '历元时效'/);
  assert.match(structRowsEts, /case 'radioComms': return '无线电频段'/);
  assert.match(passDetailsEts, /Button\('预演过境'\)/);
  assert.match(passDetailsEts, /satelliteCompassDirection/);
  assert.match(passDetailsEts, /satelliteDurationText/);
  assert.match(mainNodeEts, /hours: 48, limit: 5, minElevation: 10/);
  assert.match(mainNodeEts, /private jumpToSatellitePass\(pass: SatellitePass\): void/);
});

test('satellites render subtle zoom-adaptive micro-markers, readable shadow labels, and comfortable pick/frame UX', () => {
  const satCtlEts = readFileSync(new URL('../harmonyos/ets-source/capability/SatelliteController.ets', import.meta.url), 'utf8');
  // One-time migration upgrades legacy config.ini so existing installs get labels & selected orbit arcs
  assert.match(satsCpp, /ohos_sat_ux_v2_migrated/);
  assert.match(satStoreEts, /satLabels:\s*boolean\s*=\s*true/);
  // Micro-marker participates in pickable() & progressively reveals faint/shadow satellites on zoom
  assert.match(satHpp, /bool markerDrawn = false;/);
  assert.match(satHpp, /return pointDrawn \|\| labelDrawn \|\| iconDrawn \|\| markerDrawn;/);
  assert.match(satCpp, /shadowZoomReveal/);
  assert.match(satCpp, /state\.iconDrawn = render\.iconDrawn \|\| render\.markerDrawn;/);
  // Batched micro-marker draw (diamond + station solar wings + center core dot) & wider moving-target capture cone
  assert.match(satsCpp, /struct SatMarkerCandidate/);
  assert.match(satsCpp, /const double effectiveFov = qMin\(limitFov \* 1\.45, 12\.0\);/);
  // Moving to a selected satellite keeps a comfortable framing FOV instead of blind 1.3 deg auto-zoom
  assert.match(mainViewCpp, /selectedObj->getType\(\) == QLatin1String\("Satellite"\)/);
  assert.match(satCtlEts, /const target = 44/);
});
