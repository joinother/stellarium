import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = p => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

test('StelSkyDrawer::drawPointSource pads viewport culling by halo/disk radius instead of 0px projectCheck', () => {
  const skyDrawer = read('src/core/StelSkyDrawer.cpp');
  const start = skyDrawer.indexOf('bool StelSkyDrawer::drawPointSource(');
  const body = skyDrawer.slice(start, start + 1800);
  assert.doesNotMatch(body, /projectCheck\(/, 'drawPointSource must not reject bright halos/stars with 0px projectCheck');
  assert.match(body, /prj->project\(v, win\)/);
  assert.match(body, /hasBigHalo \? qMax\(radius, 150\.f \* scale\)/);
});

test('Planet::draw pads viewportBufferSz by screen-scaled halo and label margin for Moon, Sun, and planets', () => {
  const planet = read('src/core/modules/Planet.cpp');
  assert.match(planet, /englishName == L1S\("Sun"\)[\s\S]{0,120}haloPad = 360\.0 \* scale/);
  assert.match(planet, /englishName == L1S\("Moon"\)[\s\S]{0,120}haloPad = 240\.0 \* scale/);
  assert.match(planet, /const double viewportBufferSz = screenRd \+ haloPad;/);
});

test('StarMgr and ZoneArray preserve edge stars, bright halos, and star labels near viewport borders', () => {
  const starMgr = read('src/core/modules/StarMgr.cpp');
  const zoneArray = read('src/core/modules/ZoneArray.cpp');
  assert.match(starMgr, /edgePad = qMin\(220\.0 \* scale/);
  assert.match(starMgr, /margin = qMax\(margin, edgePad\)/);
  assert.match(zoneArray, /\(starDrawn \|\| !isInsideViewport\) && core->getFlagClearSky\(\) && s->hasName\(\)/);
});

test('Constellation, Asterism, Satellite, Nebula, and MeteorShower labels pad viewport check instead of 0px projectCheck', () => {
  const constellationMgr = read('src/core/modules/ConstellationMgr.cpp');
  const asterismMgr = read('src/core/modules/AsterismMgr.cpp');
  const satellite = read('plugins/Satellites/src/Satellite.cpp');
  const nebulaMgr = read('src/core/modules/NebulaMgr.cpp');
  const meteorShower = read('plugins/MeteorShowers/src/MeteorShower.cpp');

  const constDraw = constellationMgr.slice(
    constellationMgr.indexOf('void ConstellationMgr::drawNames('),
    constellationMgr.indexOf('Constellation* ConstellationMgr::findFromAbbreviation')
  );
  assert.doesNotMatch(constDraw, /projectCheck\(/);
  assert.match(constDraw, /labelMargin = 240\.0/);

  const astDraw = asterismMgr.slice(
    asterismMgr.indexOf('void AsterismMgr::drawNames('),
    asterismMgr.indexOf('Asterism* AsterismMgr::findFromAbbreviation')
  );
  assert.doesNotMatch(astDraw, /projectCheck\(/);
  assert.match(astDraw, /labelMargin = 240\.0/);

  assert.match(satellite, /leftPad\s*=\s*260\.0 \* scale/);
  assert.match(satellite, /prj->project\(XYZ, st\.screenWin\)/);

  const nebulaStart = nebulaMgr.indexOf('const bool inPaddedViewport =');
  assert.ok(nebulaStart > 0, 'NebulaMgr must use padded viewport projection check');
  assert.match(nebulaMgr.slice(nebulaStart, nebulaStart + 600), /projector->project\(n->XYZ, n->XY\)/);

  assert.match(meteorShower, /radiantNearViewport = prj->project\(m_position, win\)/);
});

test('Satellites and NebulaMgr smoothly fade labels & markers during fast zoom-in and zoom-out without binary cliffs', () => {
  const satellite = read('plugins/Satellites/src/Satellite.cpp');
  const satellites = read('plugins/Satellites/src/Satellites.cpp');
  const nebulaMgr = read('src/core/modules/NebulaMgr.cpp');

  assert.match(satellite, /auto smoothRamp =/);
  assert.doesNotMatch(satellites, /maxSatelliteLabels = \(currentFovDeg >= 40\.0\)/);
  assert.doesNotMatch(satellites, /maxMarkers = \(currentFovDeg >= 40\.0\)/);
  assert.match(satellites, /s_satLabelFadeMap/);
  assert.match(satellites, /s_satMarkerFadeMap/);
  assert.match(satellites, /satFadeInStep/);
  assert.match(satellites, /satFadeOutStep/);
  assert.match(nebulaMgr, /dsoFadeCache\(\)/);
  assert.match(nebulaMgr, /fadeInStep\s*=\s*dt \/ 0\.28f/);
  assert.match(nebulaMgr, /fadeOutStep\s*=\s*dt \/ 0\.24f/);
});
