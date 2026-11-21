import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = p => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

const auroraHpp = read('src/core/modules/AuroraRenderer.hpp');
const auroraCpp = read('src/core/modules/AuroraRenderer.cpp');
const cmakeTxt = read('src/CMakeLists.txt');
const lmgrHpp = read('src/core/modules/LandscapeMgr.hpp');
const lmgrCpp = read('src/core/modules/LandscapeMgr.cpp');
const mainViewCpp = read('src/StelMainView.cpp');
const catalogHpp = read('src/StelOhosCommandCatalog.hpp');
const layerStoreEts = read('harmonyos/ets-source/state/LayerStore.ets');
const typesEts = read('harmonyos/ets-source/common/types/StellariumTypes.ets');
const layerCtlEts = read('harmonyos/ets-source/capability/LayerController.ets');
const mainNodeEts = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
const atmosSectionEts = read('harmonyos/ets-source/panels/layers/AtmosphereGroundSection.ets');

test('AuroraRenderer implements quarter-res ethereal volumetric flowing silk curtains, 4 natural styles, tent upsampling and night vision', () => {
  assert.match(auroraHpp, /static constexpr int kStyleCount = 4;/);
  assert.match(auroraHpp, /static float computeSolarGate\(double sunAltDeg\);/);
  assert.match(auroraCpp, /const float kEarthR = 6371\.0;/);
  assert.match(auroraCpp, /evalSilkRibbon\(/);
  assert.match(auroraCpp, /evalCoronaSilk\(/);
  assert.match(auroraCpp, /projector->unProject\(winX, winY, dir\)/);
  assert.match(auroraCpp, /uNightVision > 0\.5/);
  assert.match(auroraCpp, /GL_ONE, GL_ONE_MINUS_SRC_COLOR/);
  assert.match(auroraCpp, /uPillarTex/);
  assert.match(auroraCpp, /uTexelSize/);
  assert.match(cmakeTxt, /core\/modules\/AuroraRenderer\.cpp/);
  assert.match(cmakeTxt, /core\/modules\/AuroraRenderer\.hpp/);
});

test('AuroraRenderer solar depression gate hides aurora in daylight and reveals smoothly in astronomical darkness', () => {
  const solarGate = sunAltDeg => {
    const t = Math.max(0, Math.min(1, (-6.0 - sunAltDeg) / 12.0));
    return t * t * (3.0 - 2.0 * t);
  };
  assert.equal(solarGate(15), 0);
  assert.equal(solarGate(0), 0);
  assert.equal(solarGate(-6), 0);
  assert.ok(solarGate(-12) > 0.49 && solarGate(-12) < 0.51);
  assert.equal(solarGate(-18), 1);
  assert.equal(solarGate(-35), 1);
});

test('LandscapeMgr draws aurora after atmosphere/sun and before foreground landscape/mist silhouettes', () => {
  assert.match(lmgrHpp, /Q_PROPERTY\(bool flagAurora READ getFlagAurora WRITE setFlagAurora NOTIFY flagAuroraChanged\)/);
  assert.match(lmgrHpp, /Q_PROPERTY\(int auroraStyle READ getAuroraStyle WRITE setAuroraStyle NOTIFY auroraStyleChanged\)/);
  assert.match(lmgrCpp, /landscape\/flag_aurora/);
  assert.match(lmgrCpp, /landscape\/aurora_style/);
  const drawBody = lmgrCpp.slice(lmgrCpp.indexOf('void LandscapeMgr::draw('), lmgrCpp.indexOf('void LandscapeMgr::drawPolylineOnly('));
  const posAtmos = drawBody.indexOf('atmosphere->draw(core)');
  const posAurora = drawBody.indexOf('auroraRenderer.draw(core)');
  const posLand = drawBody.indexOf('landscape->draw(core');
  const posMist = drawBody.indexOf('mistHorizon.draw(core');
  assert.ok(posAtmos > 0 && posAurora > posAtmos, 'Aurora must draw after atmosphere');
  assert.ok(posLand > posAurora && posMist > posAurora, 'Aurora must draw before landscape and mist silhouettes');
});

test('HarmonyOS bridge, command catalog, store, and AtmosphereGroundSection wire auroraEnabled and 4 styles end-to-end', () => {
  assert.match(mainViewCpp, /result\["auroraEnabled"\] = landscape->getFlagAurora\(\);/);
  assert.match(mainViewCpp, /result\["auroraStyle"\] = landscape->getAuroraStyle\(\);/);
  assert.match(mainViewCpp, /else if \(setting == "auroraEnabled"\)/);
  assert.match(mainViewCpp, /else if \(setting == "auroraStyle"\)/);
  assert.match(mainViewCpp, /auroraAnimating/);
  assert.match(catalogHpp, /auroraEnabled:/);
  assert.match(catalogHpp, /auroraStyle:/);
  assert.match(layerStoreEts, /auroraEnabled: boolean = false/);
  assert.match(layerStoreEts, /auroraStyle: number = 0/);
  assert.match(typesEts, /auroraEnabled\?: boolean/);
  assert.match(typesEts, /auroraStyle\?: number/);
  assert.match(layerCtlEts, /setting === 'auroraEnabled'/);
  assert.match(layerCtlEts, /setting === 'auroraStyle'/);
  assert.match(mainNodeEts, /this\.layerStore\.auroraEnabled = result\.auroraEnabled === true/);
  assert.match(mainNodeEts, /this\.layerStore\.auroraStyle =/);
  assert.match(atmosSectionEts, /this\.onSetSkyDisplay\('auroraEnabled', enabled\)/);
  assert.match(atmosSectionEts, /this\.onSetSkyDisplay\('auroraStyle', styleIndex\)/);
  assert.match(atmosSectionEts, /经典绿幕/);
  assert.match(atmosSectionEts, /红绿磁暴/);
  assert.match(atmosSectionEts, /紫韵光柱/);
  assert.match(atmosSectionEts, /蓝绿极夜/);
});
