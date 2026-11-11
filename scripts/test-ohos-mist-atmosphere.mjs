import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = name => readFileSync(new URL(`../src/core/modules/${name}`, import.meta.url), 'utf8');
const helper = read('AtmosphereMist.hpp');
const lightweight = read('AtmosphereLightweight.cpp');
const preetham = read('AtmospherePreetham.cpp');
const landscape = read('LandscapeMgr.cpp');
function body(source, signature) {
  const found = source.indexOf(signature);
  assert.ok(found >= 0, signature);
  const start = source.indexOf('{', found);
  let depth = 1;
  let end = start + 1;
  while (depth && end < source.length) {
    if (source[end] === '{') ++depth;
    if (source[end] === '}') --depth;
    ++end;
  }
  assert.equal(depth, 0);
  return source.slice(start + 1, end - 1);
}
const gate = new Function('earth', 'landscape', 'scene', 'mistOpacity',
  body(helper, 'inline float displayStrength(')
    .replaceAll('std::isfinite', 'Number.isFinite')
    .replaceAll('std::max', 'Math.max').replaceAll('std::min', 'Math.min')
    .replaceAll(/(\d+)\.f/g, '$1'));
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
const smoothstep = (low, high, value) => {
  const unit = clamp((value - low) / (high - low), 0, 1);
  return unit * unit * (3 - 2 * unit);
};
const transmission = new Function('worldZ', 'mistUndergroundStrength', 'degrees', 'asin', 'clamp', 'mix', 'smoothstep',
  body(helper, 'highp float mistAtmosphereTransmission(').replace('highp float altitude', 'const altitude'));
const mask = (altitude, strength = 1) => transmission(Math.sin(altitude * Math.PI / 180), strength,
  value => value * 180 / Math.PI, Math.asin, clamp, (left, right, weight) => left + (right - left) * weight, smoothstep);

test('display gate excludes other planets, photos and 3D even with residual mode opacity', () => {
  for (const earth of [false, true]) {
    for (const photo of [false, true]) {
      for (const scene of [false, true]) {
        assert.equal(gate(earth, photo, scene, 1), earth && !photo && !scene ? 1 : 0);
        assert.equal(gate(earth, photo, scene, .4), earth && !photo && !scene ? .4 : 0);
      }
    }
  }
  assert.equal(gate(true, false, false, 0), 0);
  for (const value of [NaN, Infinity, -Infinity, -1]) assert.equal(gate(true, false, false, value), 0);
  assert.equal(gate(true, false, false, 2), 1);
});

test('actual shader keeps the signed lower hemisphere and exact upper hemisphere', () => {
  for (const altitude of [-90, -60, -30, -15]) assert.ok(Math.abs(mask(altitude)) < 1e-14);
  for (let altitude = -3; altitude <= 90; altitude += .25) assert.equal(mask(altitude), 1);
  assert.ok(Math.abs(mask(-9) - .5) < 1e-14);
  assert.equal(mask(9), 1);
  for (let altitude = -90; altitude <= 90; altitude += .25) assert.equal(mask(altitude, 0), 1);
});

test('transition is continuous, monotonic and finite at both boundaries and poles', () => {
  let previous = mask(-90);
  for (let altitude = -89.99; altitude <= 90; altitude += .01) {
    const current = mask(altitude);
    assert.ok(Number.isFinite(current) && current >= previous - 1e-14 && current <= 1);
    assert.ok(current - previous < .002);
    previous = current;
  }
  for (const boundary of [-15, -3]) assert.ok(Math.abs(mask(boundary + 1e-5) - mask(boundary - 1e-5)) < 1e-10);
});

test('mode opacity fades independently of camera portal and vivid', () => {
  const update = body(landscape, 'void LandscapeMgr::update(');
  const expression = update.match(/mistHorizon\.opacity \+= ([^;]+);/)[1];
  const fade = new Function('mistHorizon', 'mistVisible', 'step',
    `mistHorizon.opacity += ${expression.replaceAll('qMin', 'Math.min').replaceAll(/(\d+)\.f/g, '$1')}; return mistHorizon.opacity;`);
  const state = { opacity: 0 };
  for (const enabled of [true, false]) {
    for (let frame = 0; frame < 120; ++frame) {
      const previous = state.opacity;
      fade(state, enabled, 1 / 60);
      const strength = gate(true, false, false, state.opacity);
      assert.equal(mask(-45, strength), 1 - state.opacity);
      assert.ok(enabled ? state.opacity >= previous : state.opacity <= previous);
    }
    assert.ok(enabled ? state.opacity > .999 : state.opacity < .001);
  }
  const draw = body(landscape, 'void LandscapeMgr::draw(');
  const wiring = draw.slice(draw.indexOf('const StelModule* scenery'), draw.indexOf('atmosphere->draw(core);'));
  assert.match(wiring, /getEnglishName\(\) == "Earth", getFlagLandscape\(\), sceneActive, mistHorizon.opacity/);
  assert.match(wiring, /property\("enableScene"\)/);
  assert.doesNotMatch(wiring, /portal|[Vv]ivid/);
});

test('Lightweight attenuates final RGB for both light passes, not additive alpha', () => {
  const fragment = lightweight.match(/const auto renderFragSrc = R"\(([\s\S]*?)\)";/)[1];
  assert.match(fragment, /color_RGB \*= mistAtmosphereTransmission\(viewDir.z\);/);
  assert.ok(fragment.indexOf('vividAtmosphereColor(') < fragment.indexOf('color_RGB *= mistAtmosphereTransmission'));
  assert.match(fragment, /FRAG_COLOR = vec4\(color_RGB, 1\)/);
  const draw = body(lightweight, 'void AtmosphereLightweight::draw(');
  assert.ok(draw.indexOf('mistUndergroundStrength, mistUndergroundStrength') < draw.indexOf('for (int i = 0; i < DRAW_PARAM_COUNT;'));
  assert.match(draw, /glBlendFunc\(GL_ONE, GL_ONE\)/);
});

test('Preetham reads signed world direction per fragment, never the mirrored skyColor', () => {
  const shader = body(preetham, 'void AtmospherePreetham::compileShaders(');
  assert.match(shader, /projector->getUnProjectShader\(\)/);
  assert.match(shader, /worldDirection = unProject\(gl_FragCoord.x, gl_FragCoord.y, valid\)/);
  assert.match(shader, /mistAtmosphereTransmission\(normalize\(worldDirection\).z\)/);
  assert.match(shader, /if \(!valid \|\| !\(length\(worldDirection\) > .00001\)\)/);
  assert.match(shader, /FRAG_COLOR = vec4\(resultSkyColor \* transmission, 1.\)/);
  assert.doesNotMatch(shader, /mistAtmosphereTransmission\(skyColor/);
  const draw = body(preetham, 'void AtmospherePreetham::draw(');
  assert.match(draw, /getProjection\(StelCore::FrameAltAz, StelCore::RefractionOff\)/);
  assert.match(draw, /worldProjector->setUnProjectUniforms\(\*atmoShaderProgram\)/);
  assert.match(shader, /bindAttributeLocation\("skyVertex", 0\)/);
  assert.match(shader, /bindAttributeLocation\("skyColor", 1\)/);
});

test('Preetham compiles on activation/projection change only and bypasses inverse projection when disabled', () => {
  const draw = body(preetham, 'void AtmospherePreetham::draw(');
  const condition = draw.match(/if \((mistUndergroundStrength > 0.f[^\n]+)\)/)[1];
  const compileNeeded = new Function('mistUndergroundStrength', 'renderProjector', 'worldProjector',
    `return ${condition.replace('0.f', '0').replaceAll('->', '.').replace('*renderProjector', 'renderProjector')};`);
  const fisheye = { kind: 'fisheye', isSameProjection: other => other.kind === 'fisheye' };
  assert.equal(compileNeeded(0, null, fisheye), false);
  assert.equal(compileNeeded(1, null, fisheye), true);
  assert.equal(compileNeeded(1, { kind: 'fisheye' }, fisheye), false);
  assert.equal(compileNeeded(1, { kind: 'stereographic' }, fisheye), true);
  assert.equal(compileNeeded(0, { kind: 'stereographic' }, fisheye), false);
  assert.match(preetham, /if \(mistUndergroundStrength > 0.\)\s*\{\s*bool valid/);
});

test('luminance, astronomy and existing color transformations are not masked', () => {
  for (const [source, model] of [[lightweight, 'AtmosphereLightweight'], [preetham, 'AtmospherePreetham']]) {
    assert.doesNotMatch(body(source, `void ${model}::computeColor(`), /AtmosphereMist|mistUnderground|mistAtmosphereTransmission/);
  }
  assert.doesNotMatch(body(lightweight, 'float AtmosphereLightweight::computeAverageLuminance('), /AtmosphereMist|mistUnderground|mistAtmosphereTransmission/);
  const probe = lightweight.match(/const auto luminanceProbeFragSrc = R"\(([\s\S]*?)\)";/)[1];
  assert.doesNotMatch(probe, /[Mm]ist/);
  assert.match(preetham, /sum_lum\+=lumi/);
  assert.match(preetham, /colorGrid\[i\].set\(pointF\[0\], pointF\[1\], pointF\[2\], lumi\)/);
  assert.match(lightweight, /color_RGB = vividAtmosphereColor\(color_RGB, viewDir, sunDir, vividStrength\)/);
});
