import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('StelApp owns a cached vivid flag with a generation counter', () => {
  const header = read('src/core/StelApp.hpp');
  const source = read('src/core/StelApp.cpp');
  assert.match(header, /getFlagVividRendering\(\)/);
  assert.match(header, /setFlagVividRendering\(bool enabled\)/);
  assert.match(header, /getVividRenderingGeneration\(\)/);
  assert.match(header, /std::atomic<bool> flagVividRendering/);
  assert.match(source, /flagVividRendering\.exchange/);
  assert.match(source, /vividRenderingGeneration\.fetch_add/);
});

test('LandscapeMgr keeps the vivid atmosphere switch and the cached flag in sync', () => {
  const landscape = read('src/core/modules/LandscapeMgr.cpp');
  assert.match(landscape, /flagVividAtmosphere = conf->value\("landscape\/flag_vivid_atmosphere"/);
  assert.match(landscape, /setFlagVividRendering\(flagVividAtmosphere\)/);
  assert.match(landscape, /setFlagVividRendering\(enabled\)/);
});

test('star point shader falls back to the upstream formula when vivid is off', () => {
  const drawer = read('src/core/StelSkyDrawer.cpp');
  assert.match(drawer, /uniform mediump float vivid;/);
  assert.match(drawer, /if \(vivid < 0\.5\)/);
  assert.match(drawer, /texture2D\(tex, texc\) \* vec4\(outColor, 1\.0\)/);
  assert.match(drawer, /setUniformValue\(starShaderVars\.vivid/);
});

test('spectral B-V table is only installed in vivid mode', () => {
  const drawer = read('src/core/StelSkyDrawer.cpp');
  assert.match(drawer, /if \(vividRendering && !customColorTable\)/);
  assert.match(drawer, /s_legacyColorTable/);
  assert.match(drawer, /getVividRenderingGeneration\(\)/);
});

test('motion trails remain an independent switch outside vivid mode', () => {
  const starMgr = read('src/core/modules/StarMgr.cpp');
  assert.doesNotMatch(starMgr, /getFlagVividRendering/);
  assert.match(starMgr, /if \(!flagMotionTrails\)/);
});

test('vivid diagnostics command is present in the bridge and catalog', () => {
  const bridge = read('src/StelMainView.cpp');
  const catalog = read('src/StelOhosCommandCatalog.hpp');
  assert.match(bridge, /commandName == "getVividRenderingState"/);
  assert.match(bridge, /result\["starTrails"\]/);
  assert.match(bridge, /result\["meteorAtmosphereGate"\]/);
  assert.match(catalog, /getVividRenderingState/);
});

test('sporadic meteors require atmosphere and expose the suppression reason', () => {
  const manager = read('src/core/modules/SporadicMeteorMgr.cpp');
  assert.match(manager, /getFlagHasAtmosphere\(\) && !getFlagForcedMeteorsActivity\(\)/);
  assert.match(manager, /atmosphere-disabled/);
  assert.match(manager, /getFlagVividRendering\(\).*triggerPreviewSalvo|triggerPreviewSalvo[\s\S]*getFlagVividRendering/);
});

test('meteor rendering has separate classic and vivid paths', () => {
  const meteor = read('src/core/modules/Meteor.cpp');
  const header = read('src/core/modules/Meteor.hpp');
  assert.match(header, /int m_segments;/);
  assert.match(meteor, /void Meteor::initLegacy/);
  assert.match(meteor, /bool Meteor::updateLegacy/);
  assert.match(meteor, /void Meteor::drawLegacy/);
  assert.match(meteor, /void Meteor::buildColorVectorsLegacy/);
  assert.match(meteor, /void Meteor::drawTrainLegacy/);
  assert.match(meteor, /void Meteor::drawBolideLegacy/);
  assert.match(meteor, /getFlagVividRendering\(\)/);
});

test('sporadic meteor palette retains the upstream classic colors', () => {
  const sporadic = read('src/core/modules/SporadicMeteor.cpp');
  assert.match(sporadic, /ColorPair\("white", 100\)/);
  assert.match(sporadic, /ColorPair\("orangeYellow", 20\)/);
  assert.match(sporadic, /getFlagVividRendering\(\)/);
});
