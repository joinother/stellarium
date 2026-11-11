import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = name => readFileSync(new URL(`../src/core/modules/${name}`, import.meta.url), 'utf8');
const helper = read('AtmosphereVivid.hpp');
const lightweight = read('AtmosphereLightweight.cpp');
const preetham = read('AtmospherePreetham.cpp');
const landscape = read('LandscapeMgr.cpp');
const vec3 = (red, green = red, blue = red) => ({ r: red, g: green, b: blue, x: red, y: green, z: blue });
const dot = (left, right) => left.r * right.r + left.g * right.g + left.b * right.b;
const mix = (left, right, weight) => typeof left === 'number' ? left + (right - left) * weight :
  vec3(mix(left.r, right.r, weight), mix(left.g, right.g, weight), mix(left.b, right.b, weight));
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
const smoothstep = (low, high, value) => {
  const unit = clamp((value - low) / (high - low), 0, 1);
  return unit * unit * (3 - 2 * unit);
};
const shader = helper.match(/return R"\(([\s\S]*?)\)";/)[1];
const executable = shader.replace('uniform float vividStrength;', '')
  .replace(/vec3 vividAtmosphereColor\(([^)]*)\)/, (_, parameters) =>
    `function vividAtmosphereColor(${parameters.replace(/\b(vec3|float) /g, '')})`)
  .replace(/\b(float|vec3) (\w+) =/g, 'let $2 =');
const color = new Function('vec3', 'mix', 'dot', 'smoothstep', 'clamp', 'degrees', 'asin', 'sqrt', 'abs', 'max', 'min',
  executable + '; return vividAtmosphereColor;')(
  vec3, mix, dot, smoothstep, clamp, value => value * 180 / Math.PI,
  Math.asin, Math.sqrt, Math.abs, Math.max, Math.min);
const direction = (elevation, azimuth = 0) => {
  const altitude = elevation * Math.PI / 180;
  const bearing = azimuth * Math.PI / 180;
  return vec3(Math.cos(altitude) * Math.cos(bearing), Math.cos(altitude) * Math.sin(bearing), Math.sin(altitude));
};
const luminance = value => dot(value, vec3(0.2126, 0.7152, 0.0722));
const difference = (left, right) => Math.max(Math.abs(left.r - right.r), Math.abs(left.g - right.g), Math.abs(left.b - right.b));

function body(source, signature) {
  const start = source.indexOf('{', source.indexOf(signature));
  assert.ok(start >= 0, signature);
  let depth = 1;
  let end = start + 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  assert.equal(depth, 0);
  return source.slice(start + 1, end - 1);
}

test('disabled shader returns the exact input, including HDR/negative values', () => {
  for (const input of [vec3(0), vec3(0.2, 0.6, 0.8), vec3(-0.1, 2, 0.4)]) {
    assert.strictEqual(color(input, direction(5), direction(-5), 0), input);
  }
});

test('actual shader produces blue day, sunward orange and antisolar purple twilight, deep blue night', () => {
  const input = vec3(0.2);
  const day = color(input, direction(70), direction(45), 1);
  const dusk = color(input, direction(2), direction(-4), 1);
  const opposite = color(input, direction(2, 180), direction(-4), 1);
  const night = color(vec3(0.002), direction(70), direction(-30), 1);
  assert.ok(day.b > day.g && day.g > day.r);
  assert.ok(dusk.r > dusk.g && dusk.g > dusk.b);
  assert.ok(opposite.b > opposite.r && opposite.r > opposite.g);
  assert.ok(night.b > night.g && night.g > night.r);
  assert.ok(difference(dusk, opposite) > 0.15);
  assert.ok(difference(dusk, color(input, direction(80), direction(-4), 1)) > 0.15);
});

test('color enhancement preserves display luminance and gamut without injecting light into black sky', () => {
  for (const input of [vec3(0), vec3(0.001), vec3(0.4, 0.5, 0.7), vec3(1), vec3(0.95, 0.85, 0.6)]) {
    for (let elevation = -90; elevation <= 90; elevation += 3) {
      for (const view of [direction(0), direction(20, 180), direction(90), direction(-30, 90)]) {
        const output = color(input, view, direction(elevation), 1);
        assert.ok(Math.abs(luminance(input) - luminance(output)) < 1e-12);
        for (const channel of [output.r, output.g, output.b]) assert.ok(Number.isFinite(channel) && channel >= 0 && channel <= 1 + 1e-12);
      }
    }
  }
});

test('sun-height transitions are continuous across sunrise twilight and night boundaries', () => {
  const input = vec3(0.2, 0.3, 0.4);
  for (const altitude of [-18, -6, -1, 0, 12]) {
    for (const view of [direction(2), direction(20, 180), direction(90)]) {
      assert.ok(difference(color(input, view, direction(altitude - 0.0001), 1),
        color(input, view, direction(altitude + 0.0001), 1)) < 0.0001);
    }
  }
  for (let altitude = -25; altitude < 25; altitude += 0.05) {
    assert.ok(difference(color(input, direction(4), direction(altitude), 1),
      color(input, direction(4), direction(altitude + 0.05), 1)) < 0.01);
  }
});

test('eclipse enhancement smoothly vanishes at totality and zenith directions stay finite', () => {
  const input = vec3(0.1, 0.2, 0.3);
  assert.ok(difference(color(input, direction(5), direction(30), 0.0025), input) < 1e-14);
  let previous = 0;
  for (let visibility = 0; visibility <= 1; visibility += 0.01) {
    const amount = difference(color(input, direction(5), direction(30), visibility), input);
    assert.ok(amount >= previous - 1e-12);
    previous = amount;
  }
  for (const solar of [vec3(0, 0, 1), vec3(0, 0, -1)]) {
    const result = color(input, vec3(0, 0, 1), solar, 1);
    assert.ok([result.r, result.g, result.b].every(Number.isFinite));
  }
});

test('both renderers gate Earth/scatter/night vision, lightweight keeps lunar and luminance passes untouched', () => {
  for (const [source, model] of [[lightweight, 'AtmosphereLightweight'], [preetham, 'AtmospherePreetham']]) {
    const compute = body(source, `void ${model}::computeColor(`);
    const gate = compute.match(/vividAtmosphereAllowed = ([^;]+);/)[1];
    const allowed = new Function('currentPlanet', 'noScatter', `return ${gate};`);
    assert.equal(allowed({ getEnglishName: () => 'Earth' }, false), true);
    assert.equal(allowed({ getEnglishName: () => 'Earth' }, true), false);
    for (const name of ['Mars', 'Moon', 'Venus', 'Solar System Observer']) assert.equal(allowed({ getEnglishName: () => name }, false), false);
    assert.doesNotMatch(compute, /flagVividAtmosphere|vividStrength|vividAtmosphereColor/);
    const draw = body(source, `void ${model}::draw(`);
    assert.match(draw, /getVisionModeNight\(\)\)\s*return;/);
    assert.match(draw, /flagVividAtmosphere && vividAtmosphereAllowed/);
  }
  assert.match(lightweight, /i == DRAW_PARAM_SUN \? p\.eclipseFactor : 0\.f/);
  assert.doesNotMatch(body(lightweight, 'float AtmosphereLightweight::computeAverageLuminance('), /[Vv]ivid/);
  const probe = lightweight.match(/const auto luminanceProbeFragSrc = R"\(([\s\S]*?)\)";/)[1];
  assert.doesNotMatch(probe, /[Vv]ivid/);
  assert.match(preetham, /originalAtmosphereMain\(\); resultSkyColor = vividAtmosphereColor/);
});

test('LandscapeMgr setter persists once, updates current and loading models, and supports pre-init calls', () => {
  const setter = body(landscape, 'void LandscapeMgr::setFlagVividAtmosphere(')
    .replaceAll('atmosphere->', 'atmosphere.').replaceAll('loadingAtmosphere->', 'loadingAtmosphere.')
    .replace('StelApp::immediateSave', 'save').replace('emit flagVividAtmosphereChanged', 'notify');
  const run = new Function('state', 'enabled', 'save', 'notify', `with (state) { ${setter} }`);
  for (const initialized of [false, true]) {
    const updates = [];
    const saved = [];
    const signals = [];
    const instance = label => initialized ? { setFlagVividAtmosphere: value => updates.push([label, value]) } : null;
    const state = { flagVividAtmosphere: false, atmosphere: instance('active'), loadingAtmosphere: instance('loading') };
    for (const enabled of [false, true, true, false]) run(state, enabled, (key, value) => saved.push([key, value]), value => signals.push(value));
    assert.deepEqual(saved, [['landscape/flag_vivid_atmosphere', true], ['landscape/flag_vivid_atmosphere', false]]);
    assert.deepEqual(signals, [true, false]);
    assert.deepEqual(updates, initialized ? [['active', true], ['loading', true], ['active', false], ['loading', false]] : []);
  }
  assert.match(landscape, /flagVividAtmosphere = conf->value\("landscape\/flag_vivid_atmosphere", false\)\.toBool\(\)/);
  assert.match(body(landscape, 'void LandscapeMgr::createAtmosphere('), /loadingAtmosphere->setFlagVividAtmosphere\(flagVividAtmosphere\)/);
  assert.match(read('LandscapeMgr.hpp'), /Q_PROPERTY\(bool flagVividAtmosphere READ getFlagVividAtmosphere WRITE setFlagVividAtmosphere NOTIFY flagVividAtmosphereChanged\)/);
});

test('current default model and OHOS resource sync select a supported path', () => {
  assert.match(landscape, /ATMOSPHERE_MODEL_CONF_VAL_DEFAULT\[\]="lightweight"/);
  assert.match(landscape, /new AtmosphereLightweight/);
  assert.match(landscape, /new AtmospherePreetham/);
  const sync = readFileSync(new URL('sync-ohos-resources.sh', import.meta.url), 'utf8');
  assert.match(sync, /DIRS=\([^\n]* atmosphere\)/);
});
