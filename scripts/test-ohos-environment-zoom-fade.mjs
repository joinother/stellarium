import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

test('EnvironmentZoomFade defines 14->4 deg mist fade and optional 10->2 deg environment fade', () => {
	const src = read('src/core/modules/EnvironmentZoomFade.hpp');
	assert.match(src, /MIST_FADE_START_FOV\s*=\s*14\.0/);
	assert.match(src, /MIST_FADE_END_FOV\s*=\s*4\.0/);
	assert.match(src, /ENV_FADE_START_FOV\s*=\s*10\.0/);
	assert.match(src, /ENV_FADE_END_FOV\s*=\s*2\.0/);
	assert.match(src, /mistVisibility\s*\(/);
	assert.match(src, /environmentVisibility\s*\(/);
	assert.match(src, /combinedLandscapeTransparency\s*\(/);
});

test('LandscapeMgr and Landscape apply mist zoom fade with draw skip and optional ground zoom fade', () => {
	const lmgrH = read('src/core/modules/LandscapeMgr.hpp');
	const lmgrC = read('src/core/modules/LandscapeMgr.cpp');
	const landH = read('src/core/modules/Landscape.hpp');
	const landC = read('src/core/modules/Landscape.cpp');

	assert.match(lmgrH, /Q_PROPERTY\(bool flagZoomFadeEnvironment/);
	assert.match(lmgrH, /bool flagZoomFadeEnvironment = false;/);
	assert.match(lmgrC, /landscape\/flag_zoom_fade_environment/);
	assert.match(lmgrC, /mistHorizon\.zoomOpacity = EnvironmentZoomFade::mistVisibility\(currentFov\);/);
	assert.match(lmgrC, /EnvironmentZoomFade::combinedLandscapeTransparency\(baseTransparency, envZoom\)/);
	assert.match(lmgrC, /const bool drawGround = pushed < 0\.999;/);
	assert.match(lmgrC, /if \(mistHorizon\.effectiveOpacity\(\) > 0\.001f\)/);
	assert.match(landH, /float effectiveOpacity\(\) const \{ return opacity \* zoomOpacity; \}/);
	assert.match(landC, /const float drawOpacity = effectiveOpacity\(\);/);
});

test('StelSkyDrawer scales atmosphereVisualStrength by environment zoom visibility', () => {
	const drawer = read('src/core/StelSkyDrawer.cpp');
	assert.match(drawer, /#include "EnvironmentZoomFade\.hpp"/);
	assert.match(drawer, /atmosphereVisualStrength \*= EnvironmentZoomFade::environmentVisibility\(/);
});

test('HarmonyOS bridge and AtmosphereGroundSection wire zoomFadeEnvironment switch', () => {
	const mainView = read('src/StelMainView.cpp');
	const catalog = read('src/StelOhosCommandCatalog.hpp');
	const types = read('harmonyos/ets-source/common/types/StellariumTypes.ets');
	const store = read('harmonyos/ets-source/state/LayerStore.ets');
	const ctl = read('harmonyos/ets-source/capability/LayerController.ets');
	const node = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
	const ui = read('harmonyos/ets-source/panels/layers/AtmosphereGroundSection.ets');

	assert.match(mainView, /else if \(setting == "zoomFadeEnvironment"\)/);
	assert.match(mainView, /result\["zoomFadeEnvironment"\] = landscape->getFlagZoomFadeEnvironment\(\);/);
	assert.match(mainView, /result\["mistZoomVisibility"\] = EnvironmentZoomFade::mistVisibility\(currentFov\);/);
	assert.match(catalog, /zoomFadeEnvironment:/);
	assert.match(types, /zoomFadeEnvironment\?: boolean/);
	assert.match(store, /zoomFadeEnvironment: boolean = false/);
	assert.match(ctl, /setting === 'zoomFadeEnvironment'/);
	assert.match(node, /this\.layerStore\.zoomFadeEnvironment = result\.zoomFadeEnvironment === true/);
	assert.match(ui, /this\.onSetSkyDisplay\('zoomFadeEnvironment', enabled\)/);
});
