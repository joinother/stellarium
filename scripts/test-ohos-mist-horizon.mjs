import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const landscape = read('src/core/modules/Landscape.cpp');
const renderer = landscape.slice(landscape.indexOf('void LandscapeMist::draw'), landscape.indexOf('void LandscapeOldStyle::load'));
const manager = read('src/core/modules/LandscapeMgr.cpp');
const page = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');

test('mist is a cached world-space renderer without external image or network dependencies', () => {
  assert.match(renderer, /getAltAzModelViewTransform\(StelCore::RefractionOff\)/);
  assert.match(renderer, /precision highp float/);
  assert.match(renderer, /direction.z < -.976/);
  assert.doesNotMatch(renderer, /createTexture|https?:|QNetwork/);
  assert.match(renderer, /getVisionModeNight/);
  assert.ok(renderer.indexOf('float pixelWidth = fwidth(altitude)') < renderer.indexOf('if (!valid'));
  assert.doesNotMatch(renderer, /filament|altitude \* 23\./);
});

test('stationary ridge is periodic at the panorama boundary', () => {
  const fract = value => value - Math.floor(value);
  const hash = (horizontal, vertical) => {
    const seed = [horizontal, vertical, horizontal].map(value => fract(value * .1031));
    const dot = seed[0] * (seed[1] + 33.33) + seed[1] * (seed[2] + 33.33) + seed[2] * (seed[0] + 33.33);
    const mixed = seed.map(value => value + dot);
    return fract((mixed[0] + mixed[1]) * mixed[2]);
  };
  const noise = (longitude, layer, count) => {
    const position = (longitude / (2 * Math.PI) + .5) * count;
    const cell = Math.floor(position);
    const fraction = fract(position);
    const blend = fraction * .65 + fraction * fraction * (3 - 2 * fraction) * .35;
    const wrap = value => ((value % count) + count) % count;
    return hash(wrap(cell), layer) * (1 - blend) + hash(wrap(cell + 1), layer) * blend - .5;
  };
  const ridge = (longitude, depth) => noise(longitude, depth + 7, 17) * .065 +
    noise(longitude, depth + 19, 41) * .022 + noise(longitude, depth + 37, 83) * .007 +
    Math.sin(longitude * 2 + depth * 2.1) * .016;
  for (let depth = 0; depth < 5; depth++) {
    assert.ok(Math.abs(ridge(-Math.PI, depth) - ridge(Math.PI, depth)) < 1e-12);
    for (let angle = -Math.PI; angle <= Math.PI; angle += .01) assert.ok(Number.isFinite(ridge(angle, depth)));
  }
  assert.match(landscape, /const int next = \(first \+ 1\) % count/);
  assert.match(renderer, /vec2 cloudPoint = direction.xy/);
  assert.match(renderer, /height = .*ridgeHeight/);
  assert.doesNotMatch(renderer, /height \+=.*cloud/);
  assert.match(renderer, /uniform vec3 sunDirection/);
});

test('expensive noise and ridge generation is cached, not run per fragment', () => {
  assert.match(landscape, /if \(ridgeTexture && noiseTexture\) return/);
  assert.match(landscape, /setFormat\(QOpenGLTexture::R16F\)/);
  assert.match(renderer, /uniform highp sampler2D ridgeTexture/);
  assert.doesNotMatch(renderer, /hashValue|ridgeNoise|\bsin\(/);
  assert.match(renderer, /texture\(noiseTexture/);
  assert.match(renderer, /opacity <= 0.001f\) return/);
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
  assert.match(read('src/core/modules/LandscapeMgr.hpp'), /Q_PROPERTY\(bool mistHorizonEnabled/);
  assert.match(manager, /addAction\("actionShow_MistHorizon"/);
  assert.match(page, /this.mistHorizon = result.actionShow_MistHorizon === true/);
  assert.match(page, /isOn: actionId === 'actionShow_Ground' \? this.ground/);
  assert.match(page, /actionId === 'actionShow_MistHorizon' && value === this.mistHorizon/);
  assert.match(page, /switchRow\(I18n.t\('mist_horizon'\), this.mistHorizon, 'actionShow_MistHorizon'\)/);
  assert.match(read('harmonyos/ets-source/pages/AstronomyGuide.ts'), /actionShow_MistHorizon\|0/);
  assert.match(read('src/StelMainView.cpp'), /result\["mistHorizonOpacity"\]/);
  assert.match(read('src/StelMainView.cpp'), /"actionShow_Ground",\s*"actionShow_MistHorizon"/);
  assert.match(read('harmonyos/ets-source/pages/StellariumTypes.ets'), /actionShow_MistHorizon\?: boolean/);
});
