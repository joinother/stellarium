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

test('star halo boost and hot core stay behind the vivid shader branch', () => {
  const drawer = read('src/core/StelSkyDrawer.cpp');
  const fallback = drawer.indexOf('if (vivid < 0.5)');
  const coreHot = drawer.indexOf('coreHot');
  const haloBoost = drawer.indexOf('haloBoost');
  assert.ok(fallback >= 0, 'missing classic vivid fallback branch');
  assert.ok(coreHot > fallback, 'coreHot must run only after the classic fallback returns');
  assert.ok(haloBoost > fallback, 'haloBoost must run only after the classic fallback returns');
  assert.match(drawer, /flagDrawBigStarHalo/);
  assert.match(drawer, /conf->value\("stars\/flag_star_halo",true\)/);
  assert.match(drawer, /flagRealisticStarVisibility/);
  assert.match(drawer, /atmosphereVisualStrength = 1\.f/);
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

test('satellite photometric point gate stays upstream and marker limit is separate', () => {
  const satellite = read('plugins/Satellites/src/Satellite.cpp');
  assert.match(satellite, /st\.pointDrawn = st\.magSat <= st\.limitMag;/);
  assert.match(satellite, /const float markerLimit = st\.limitMag \+ 3\.2f \* zoomReveal;/);
  assert.doesNotMatch(satellite, /st\.pointDrawn = \(sunlit \|\| penumbra\) && \(st\.magSat <= markerLimit\)/);
});

test('satellite pick state keeps upstream magnitude and exposes markerDrawn', () => {
  const satellite = read('plugins/Satellites/src/Satellite.cpp');
  const pick = read('src/core/StelObject.hpp');
  assert.match(satellite, /state\.iconDrawn = render\.iconDrawn;/);
  assert.match(satellite, /state\.markerDrawn = render\.markerDrawn;/);
  assert.match(satellite, /state\.magnitude = \(render\.pointDrawn \|\| render\.iconDrawn\) \? render\.magSat : render\.txtMag;/);
  assert.match(pick, /bool markerDrawn = false;/);
});

test('satellite marker layer has an independent platform switch', () => {
  const plugin = read('plugins/Satellites/src/Satellites.cpp');
  const header = read('plugins/Satellites/src/Satellites.hpp');
  const store = read('harmonyos/ets-source/state/SatelliteStore.ets');
  const controller = read('harmonyos/ets-source/capability/SatelliteController.ets');
  const panel = read('harmonyos/ets-source/panels/panels/SatellitesPanel.ets');
  assert.match(header, /flagMarkerLayer/);
  assert.match(plugin, /marker_layer", true/);
  assert.match(plugin, /marker_layer", false/);
  assert.match(store, /satMarkerLayer: boolean = true/);
  assert.match(controller, /name === 'markerLayer'/);
  assert.match(panel, /c_show_markers/);
});

test('satellite touch picking uses markerDrawn instead of faking icon magnitude', () => {
  const picker = read('src/core/TouchPicker.cpp');
  assert.match(picker, /state\.markerDrawn/);
  assert.match(picker, /state\.markerDrawn && !state\.pointDrawn && !state\.iconDrawn/);
});

test('comet analytical tail has an independent switch linked to vivid mode', () => {
  const solar = read('src/core/modules/SolarSystem.cpp');
  const comet = read('src/core/modules/Comet.cpp');
  const landscape = read('src/core/modules/LandscapeMgr.cpp');
  const bridge = read('src/StelMainView.cpp');
  const tabs = read('harmonyos/ets-source/panels/layers/LayerViewTabs.ets');
  assert.match(solar, /flag_analytical_comet_tail/);
  assert.match(solar, /setFlagAnalyticalCometTail/);
  assert.match(comet, /isAnalyticalTailEnabled\(\) && ensureShaders\(\)/);
  assert.match(comet, /!analyticalTail \|\| shaderInitFailed/);
  assert.match(comet, /!Comet::isAnalyticalTailEnabled\(\) \|\| screenRd > 1\.0 \|\| shaderInitFailed/);
  assert.match(landscape, /setFlagAnalyticalCometTail\(true\)/);
  assert.match(bridge, /setCometAnalyticalTail/);
  assert.match(tabs, /setCometAnalyticalTail/);
});
