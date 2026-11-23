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
  assert.match(catalog, /getVividRenderingState/);
});
