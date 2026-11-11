import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const landscape = read('src/core/modules/Landscape.cpp');
const renderer = landscape.slice(landscape.indexOf('void LandscapeMist::draw'), landscape.indexOf('void LandscapeOldStyle::load'));
const manager = read('src/core/modules/LandscapeMgr.cpp');
const page = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');

test('mist is a cached world-space mesh without external assets or network dependencies', () => {
  assert.match(renderer, /getAltAzModelViewTransform\(StelCore::RefractionOff\)/);
  assert.ok(renderer.includes('getProjectShader()'));
  assert.ok(renderer.includes('getUnProjectShader()'));
  assert.ok(renderer.includes('getVisionModeNight()'));
  assert.doesNotMatch(renderer, /https?:|QNetwork/);
});

test('stationary geometric normals and distance haze use actual surface positions', () => {
  assert.match(renderer, /float groundDistance\s*=\s*length\(surfacePosition\.xy\);/);
  assert.match(renderer, /surfaceFlow\s*=\s*terrainFlow;/);
  assert.match(renderer, /float front\s*=\s*surfaceFlow;/);
  assert.ok(renderer.includes('normalize(surfaceNormal)'));
  assert.ok(renderer.includes('length(surfacePosition)'));
  assert.ok(renderer.includes('uniform vec3 sunDirection'));
  assert.ok(!renderer.includes('terrainTexture'));
});

test('mesh and noise generation is cached outside draw', () => {
  assert.ok(landscape.includes('if (mistResources) return'));
  assert.ok(landscape.includes('resources.mesh = MistTerrain::generate()'));
  assert.ok(!renderer.includes('MistTerrain::generate()'));
  assert.ok(renderer.includes('texture(noiseTexture'));
  assert.ok(renderer.includes('opacity <= .001f) return'));
});

test('fallback defaults on, but photo and 3D scenes suppress it', () => {
  assert.match(manager, /mistHorizonEnabled && !getFlagLandscape\(\) && !sceneActive/);
  assert.match(manager, /getEnglishName\(\) == "Earth"/);
  assert.match(manager, /landscape\/mist_horizon_enabled", true/);
  assert.match(manager, /immediateSave\("landscape\/mist_horizon_enabled", enabled\)/);
  assert.match(manager, /if \(displayed\)[\s\S]*?setMistHorizonEnabled\(false\)/);
  assert.match(manager, /if \(enabled\)[\s\S]*?setFlagLandscape\(false\)/);
  assert.match(manager, /if \(getFlagLandscape\(\)\)\s*landscape->draw/);
});

test('UI, semantic actions and snapshot properties share the same switch', () => {
  const switchRow = read('harmonyos/ets-source/panels/layers/LayerSwitchRow.ets');
  assert.match(read('src/core/modules/LandscapeMgr.hpp'), /Q_PROPERTY\(bool mistHorizonEnabled/);
  assert.match(manager, /addAction\("actionShow_MistHorizon"/);
  // Phase 3ak：mistHorizon 已迁入 LayerStore；开关行的同值短路从宿主 @Builder switchRow 的
  // actionId 分支搬到了 LayerSwitchRow 组件，调用点直接传解析后的布尔值。
  assert.match(page, /this\.layerStore\.mistHorizon = result\.actionShow_MistHorizon === true/);
  assert.match(switchRow, /if \(value === this\.isOn\) return/);
  // Phase 4f：该调用点随 viewLandscapeTab 下沉到 panels/layers/LayerViewTabs.ets，
  // 开关动作改经 onToggleLayer 回调回注宿主（层开关链路不变）。
  const layerViewTabs = read('harmonyos/ets-source/panels/layers/LayerViewTabs.ets');
  assert.match(layerViewTabs, /LayerSwitchRow\(\{ label: I18n\.t\('mist_horizon'\), isOn: this\.layerStore\.mistHorizon, onToggle: \(value: boolean\) => \{ this\.onToggleLayer\('actionShow_MistHorizon', '', value\) \} \}\)/);
  assert.match(read('harmonyos/ets-source/common/derive/AstronomyGuide.ts'), /actionShow_MistHorizon\|0/);
  assert.match(read('src/StelMainView.cpp'), /result\["mistHorizonOpacity"\]/);
  assert.match(read('src/StelMainView.cpp'), /"actionShow_Ground",\s*"actionShow_MistHorizon"/);
  assert.match(read('harmonyos/ets-source/common/types/StellariumTypes.ets'), /actionShow_MistHorizon\?: boolean/);
});
