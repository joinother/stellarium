import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test, { after, before } from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = readFileSync(join(root, 'src/core/modules/Landscape.cpp'), 'utf8');
const render = source.slice(source.indexOf('void LandscapeMist::draw('), source.indexOf('void LandscapeOldStyle::load('));
const temporary = mkdtempSync(join(tmpdir(), 'mist-mesh-test-'));
let metrics;
let meshError;
before(() => {
  try {
    const executable = join(temporary, 'terrain-test');
    execFileSync(process.env.CXX ?? 'clang++', ['-std=c++17', '-O2', '-Wall', '-Wextra', '-pedantic',
      '-I', join(root, 'src/core/modules'), join(root, 'scripts/test-mist-terrain.cpp'), '-o', executable]);
    metrics = JSON.parse(execFileSync(executable, [], { encoding: 'utf8' }));
  } catch (error) {
    meshError = error;
  }
});
after(() => rmSync(temporary, { recursive: true, force: true }));

test('production helper checks continuity, shared topology, projection seams and bounded refinement', () => {
  assert.ifError(meshError);
  assert.equal(metrics.vertices, 49153);
  assert.equal(metrics.triangles, 97920);
  assert.ok(metrics.maximumVertices > metrics.vertices);
  assert.ok(metrics.maximumVertices <= metrics.vertices + 8192);
  assert.ok(metrics.seamTriangles > 0);
  assert.equal(metrics.flowVertices, metrics.vertices);
  assert.ok(metrics.generateMs > 0 && metrics.maximumViewMs > 0);
});

const smoothstep = (low, high, value) => {
  const unit = Math.max(0, Math.min(1, (value - low) / (high - low)));
  return unit * unit * (3 - 2 * unit);
};
const functionBody = name => {
  const start = render.indexOf('float ' + name + '(');
  return render.slice(render.indexOf('{', start) + 1, render.indexOf('}', start));
};
const illumination = new Function('smoothstep', 'solarHeight', functionBody('terrainIllumination')).bind(null, smoothstep);
const aerialPerspective = new Function('exp', 'distance', 'haze', functionBody('aerialPerspective')).bind(null, Math.exp);
const expression = name => {
  const match = render.match(new RegExp(`\\b(?:float|vec2) ${name} = ([^;]+);`));
  assert.ok(match, `shader expression ${name}`);
  return match[1];
};
const mix = (first, second, weight) => first + (second - first) * weight;
const lower = new Function('mix', 'smoothstep', 'altitude', 'flowAmount', 'return ' + expression('lowerFade')).bind(null, mix, smoothstep);
const coverage = new Function('mix', 'lowerFade', 'ribbon', 'flowAmount', 'return ' + expression('coverage')).bind(null, mix);
const alpha = new Function('opacity', 'portal', 'coverage', 'return ' + expression('alpha'));
const front = new Function('surfaceFlow', 'return ' + expression('front'));
const drift = new Function('billow', 'detail', 'return ' + expression('drift'));
const edgeAt = new Function('front', 'drift', 'return ' + expression('edge'));
const solidAt = new Function('smoothstep', 'edge', 'return ' + expression('solid')).bind(null, smoothstep);
const nearOffsetAt = new Function('edge', 'return ' + expression('nearOffset'));
const nearWaveFromOffset = new Function('exp', 'nearOffset', 'return ' + expression('nearWave')).bind(null, Math.exp);
const nearWaveAt = edge => nearWaveFromOffset(nearOffsetAt(edge));
const outerEdgeAt = new Function('front', 'drift', 'detail', 'return ' + expression('outerEdge'));
const outerOffsetAt = new Function('outerEdge', 'return ' + expression('outerOffset'));
const outerWaveFromOffset = new Function('exp', 'outerOffset', 'return ' + expression('outerWave')).bind(null, Math.exp);
const outerWaveAt = outerEdge => outerWaveFromOffset(outerOffsetAt(outerEdge));
const ribbonExpression = render.match(/\n\s*ribbon = ([^;]+);/);
assert.ok(ribbonExpression);
const combineRibbon = new Function('smoothstep', 'solid', 'nearWave', 'outerWave', 'surfaceFlow', 'return ' + ribbonExpression[1]).bind(null, smoothstep);
function ribbonFromFront(surfaceFlow, billow, detail) {
  const boundary = front(surfaceFlow);
  const offset = drift(billow, detail);
  const edge = edgeAt(boundary, offset);
  const outerEdge = outerEdgeAt(boundary, offset, detail);
  const solid = solidAt(edge), nearWave = nearWaveAt(edge), outerWave = outerWaveAt(outerEdge);
  return { front: boundary, drift: offset, edge, outerEdge, solid, nearWave, outerWave,
    ribbon: combineRibbon(solid, nearWave, outerWave, surfaceFlow) };
}
const texture = new Uint8Array(128 * 128);
const seed = source.match(/std::uint32_t random = (0x[\da-f]+)u;/i);
assert.ok(seed);
let random = Number(seed[1]);
for (let index = 0; index < texture.length; index++) {
  random ^= random << 13; random ^= random >>> 17; random ^= random << 5;
  texture[index] = random >>> 24;
}
const noiseBlend = render.match(/\n\s*blend = ([^;]+);/);
assert.ok(noiseBlend);
const blendNoise = new Function('blend', 'return ' + noiseBlend[1]);
const noise = point => {
  const left = Math.floor(point[0]), bottom = Math.floor(point[1]);
  const blendX = blendNoise(point[0] - left), blendY = blendNoise(point[1] - bottom);
  const sample = (column, row) => texture[((row % 128 + 128) % 128) * 128 + ((column % 128 + 128) % 128)] / 255;
  return mix(mix(sample(left, bottom), sample(left + 1, bottom), blendX), mix(sample(left, bottom + 1), sample(left + 1, bottom + 1), blendX), blendY);
};
const windComponents = expression('wind').match(/^vec2\(([^,]+), ([^)]+)\)$/);
assert.ok(windComponents);
const windAt = windComponents.slice(1).map(component => new Function('clockTime', 'return ' + component));
const edgePoint = new Function('groundDirection', 'return ' + expression('edgePoint'));
const noiseAt = name => {
  const argument = expression(name).match(/^softNoise\(([^)]+)\)$/);
  assert.ok(argument);
  const coordinate = new Function('edgePoint', 'wind', 'return ' + argument[1]);
  return (edge, wind) => noise(edge.map((value, axis) => coordinate(value, wind[axis])));
};
const billowAt = noiseAt('billow'), detailAt = noiseAt('detail');
const terrainSource = readFileSync(join(root, 'src/core/modules/MistTerrain.hpp'), 'utf8');
const helperExpression = name => {
  const match = terrainSource.match(new RegExp(`inline double ${name}\\([^)]*\\)\\s*\\{\\s*return ([^;]+);`));
  assert.ok(match, `single-expression helper ${name}`);
  return match[1].replaceAll('std::', 'Math.');
};
const wideFieldWeight = new Function('smooth', 'fovDegrees', 'return ' + helperExpression('wideFieldWeight')).bind(null, smoothstep);
const flowTarget = new Function('smooth', 'wideFieldWeight', 'viewAltitude', 'fovDegrees', 'return ' + helperExpression('flowAmount')).bind(null, smoothstep, wideFieldWeight);
const advanceFlow = new Function('current', 'target', 'seconds', 'return ' + helperExpression('advanceFlow'));
function sampleFront(surfaceFlow, angle, seconds) {
  const edge = [Math.cos(angle), Math.sin(angle)].map(edgePoint);
  const wind = windAt.map(component => component(seconds));
  return ribbonFromFront(surfaceFlow, billowAt(edge, wind), detailAt(edge, wind));
}

test('actual shader distance fog is monotonic and deep night emits no terrain light', () => {
  for (const height of [-1, -.5, -.3]) assert.equal(illumination(height), 0);
  assert.equal(aerialPerspective(0, .5), 0);
  for (const distance of [1, 10, 100, 1000]) {
    assert.ok(aerialPerspective(distance, .5) < aerialPerspective(distance * 2, .5));
  }
  assert.ok(render.includes('normalize(surfaceNormal)'));
  assert.ok(render.includes('dot(lightingNormal, sunDirection)'));
  assert.ok(render.includes('if (nightVision) color = vec3(dot(color, vec3(.3, .59, .11)), 0., 0.)'));
});

test('pitch-controlled flow opens near slopes but preserves wide-view opaque coverage', () => {
  assert.doesNotMatch(render, /\berosion\b/);
  for (const altitude of [-Math.PI / 2, -1.3, -.8, -.3, 0]) {
    for (const ribbon of [0, .5, 1]) {
      assert.equal(lower(altitude, 0), 1);
      assert.equal(coverage(1, ribbon, 0), 1);
      for (const amount of [0, .2, .5, 1]) {
        const lowerFade = lower(altitude, amount);
        const value = coverage(lowerFade, ribbon, amount);
        assert.ok(value >= 0 && value <= 1);
        assert.equal(alpha(1, 0, value), 0);
        assert.equal(coverage(lowerFade, 1, amount), lowerFade);
      }
    }
  }
  assert.equal(coverage(1, 0, 1), 0);
  assert.equal(coverage(1, 1, 1), 1);
  const flowUniform = render.match(/setUniformValue\("flowAmount", static_cast<float>\(([^;]+)\)\);/);
  const portalUniform = render.match(/setUniformValue\("portal", static_cast<float>\(([^;]+)\)\);/);
  assert.ok(flowUniform && portalUniform);
  const wideFlow = new Function('resources', 'wideField', 'return ' + flowUniform[1]);
  const widePortal = new Function('resources', 'wideField', 'return ' + portalUniform[1]);
  for (const fov of [30, 75, 130]) {
    assert.equal(flowTarget(-25 * Math.PI / 180, fov), 1);
    assert.equal(flowTarget(-.40, fov), 1);
    assert.equal(flowTarget(-.06, fov), 0);
    assert.equal(flowTarget(0, fov), 0);
    let previous = 1;
    for (let index = 0; index <= 1800; index++) {
      const pitch = -Math.PI / 2 + index * Math.PI / 1800;
      const target = flowTarget(pitch, fov);
      assert.ok(target >= 0 && target <= previous);
      previous = target;
    }
    for (const boundary of [-.40, -.06]) {
      assert.ok(Math.abs(flowTarget(boundary - 1e-8, fov) - flowTarget(boundary + 1e-8, fov)) < 1e-10);
    }
  }
  const target = flowTarget(-25 * Math.PI / 180, 75);
  let history = 0, previousCoverage = 1;
  for (let frame = 1; frame <= 180; frame++) {
    const previous = history;
    history = advanceFlow(history, target, 1 / 60);
    assert.ok(history > previous && history - previous < .04);
    const amount = wideFlow({ flow: history }, wideFieldWeight(75));
    const value = coverage(lower(-25 * Math.PI / 180, amount), sampleFront(0, 0, frame / 60).ribbon, amount);
    assert.ok(value <= previousCoverage);
    previousCoverage = value;
    assert.ok(Math.abs(history - (1 - Math.exp(-frame / 60 / .42))) < 1e-12);
  }
  assert.ok(previousCoverage < .001, 'settled down-view no longer mixes a permanent solid foreground');
  assert.equal(advanceFlow(history, 0, 0), history);
  assert.equal(advanceFlow(history, 0, -1), history);
  assert.equal(advanceFlow(history, 0, 1), advanceFlow(history, 0, .1));
  for (let frame = 0; frame < 180; frame++) history = advanceFlow(history, flowTarget(0, 75), 1 / 60);
  assert.ok(history < .001);
  for (const pitch of [-Math.PI / 2, -.40, -.06, 0, Math.PI / 2]) {
    let previous = 1;
    for (let fov = 130; fov <= 155; fov += .25) {
      const amount = wideFlow({ flow: flowTarget(pitch, fov) }, wideFieldWeight(fov));
      assert.ok(amount >= 0 && amount <= previous);
      previous = amount;
    }
    assert.equal(flowTarget(pitch, 155), 0);
    assert.equal(flowTarget(pitch, 210), 0);
  }
  for (const previous of [0, .3, 1]) {
    const resources = { flow: previous, portal: previous };
    const amount = wideFlow(resources, 1);
    assert.equal(amount, 0);
    assert.equal(widePortal(resources, 1), 1);
    assert.equal(coverage(lower(-Math.PI / 2, amount), 0, amount), 1);
  }
  assert.equal(illumination(-.6) * alpha(1, 1, 1), 0);
});
test('view cache accounts for center, flips, stretch and pixel scale', () => {
  assert.ifError(meshError);
  for (const field of ['flipHorz', 'flipVert', 'widthStretch', 'devicePixelsPerPixel', 'maskType']) {
    assert.ok(render.includes('signature.push_back(projectorParams.' + field + ')'));
  }
  for (const axis of [0, 1]) assert.ok(render.includes('signature.push_back(center[' + axis + '])'));
  assert.ok(render.includes('visible.vertices.data() + baseVertices'));
  assert.ok(!render.includes('MistTerrain::generate('));
  assert.ok(render.includes('MistTerrain::prepareVisibleMesh(resources.mesh, resources.viewWorkspace'));
  assert.ok(render.includes('resources.indices->write(0, visible.indices.data(), indexBytes)'));
  assert.ok(metrics.comparedPixels > 100000);
  assert.ok(metrics.narrowProjected < metrics.vertices * .45);
  assert.ok(metrics.narrowIndexBytes < metrics.triangles * 12 * .15);
});

test('actual crest-relative shader keeps the center clear and distant solid with continuous moving waves', () => {
  for (const name of ['nearOffset', 'nearWave', 'outerOffset', 'outerWave']) {
    assert.doesNotMatch(expression(name), /\bpow\s*\(/, `${name} must not use GLSL pow with potentially negative offsets`);
  }
  assert.ok(Math.abs(drift(0, 0) + .0525) < 1e-12);
  assert.ok(Math.abs(drift(1, 1) - .0525) < 1e-12);
  assert.equal(combineRibbon(0, .35, .12, 1), 1 - .65 * .88);
  for (const [wave, peak, width, amplitude] of [[nearWaveAt, .53, .18, .35], [outerWaveAt, .27, .13, .12]]) {
    assert.equal(wave(peak), amplitude);
    for (let index = 0; index < 100; index++) {
      const distance = width * index / 25;
      assert.ok(wave(peak + distance) >= wave(peak + distance + width / 25));
      assert.ok(Math.abs(wave(peak - distance) - wave(peak + distance)) < 1e-12);
    }
    assert.ok(wave(peak + 4 * width) < 1e-7);
  }
  for (let billowIndex = 0; billowIndex <= 10; billowIndex++) {
    for (let detailIndex = 0; detailIndex <= 10; detailIndex++) {
      let previousSolid = -1;
      for (let index = 0; index <= 300; index++) {
        const surfaceFlow = index / 200;
        const current = ribbonFromFront(surfaceFlow, billowIndex / 10, detailIndex / 10);
        assert.ok(Number.isFinite(current.ribbon) && current.ribbon >= 0 && current.ribbon <= 1);
        assert.ok(current.solid >= previousSolid, 'only the solid component must be monotonic');
        previousSolid = current.solid;
        assert.ok(Math.abs(current.edge - surfaceFlow) <= .0525 + 1e-12);
        assert.ok(Math.abs(current.outerEdge - surfaceFlow) <= .0515 + 1e-12);
        if (surfaceFlow === 0) assert.equal(current.ribbon, 0);
        if (surfaceFlow <= .02) assert.ok(current.ribbon < .002, 'center fade suppresses Gaussian tails');
        if (surfaceFlow >= .12) assert.ok(current.ribbon + 1e-12 >= current.solid);
        if (current.solid === 0) assert.ok(current.ribbon <= 1 - .65 * .88 + 1e-12);
        if (surfaceFlow >= 1.14) {
          assert.equal(current.solid, 1);
          assert.equal(current.ribbon, 1, 'phase noise never opens the distant solid region');
        }
      }
    }
  }
  for (const seconds of [0, 3, 8, 120]) {
    for (let degrees = 0; degrees < 360; degrees += 5) {
      const angle = degrees * Math.PI / 180;
      assert.equal(sampleFront(0, angle, seconds).ribbon, 0);
      assert.equal(sampleFront(1.14, angle, seconds).ribbon, 1);
    }
    for (const seam of [0, Math.PI, 2 * Math.PI]) {
      for (const surfaceFlow of [0, .02, .12, .2, .27, .4, .53, .64, .86, 1.14]) {
        const left = sampleFront(surfaceFlow, seam - 1e-8, seconds);
        const right = sampleFront(surfaceFlow, seam + 1e-8, seconds);
        for (const field of ['edge', 'outerEdge', 'solid', 'nearWave', 'outerWave', 'ribbon']) {
          assert.ok(Math.abs(left[field] - right[field]) < 1e-6, `${field} is continuous across angular seam ${seam}`);
        }
      }
    }
  }
  for (const [surfaceFlow, field] of [[.86, 'solid'], [.4, 'nearWave'], [.2, 'outerWave'], [.4, 'ribbon']]) {
    let changesAtThree = 0, changesAtEight = 0, maximumFrameChange = 0;
    for (let degrees = 0; degrees < 360; degrees += 5) {
      const angle = degrees * Math.PI / 180;
      const initial = sampleFront(surfaceFlow, angle, 0)[field];
      if (Math.abs(initial - sampleFront(surfaceFlow, angle, 3)[field]) > .001) changesAtThree++;
      if (Math.abs(initial - sampleFront(surfaceFlow, angle, 8)[field]) > .001) changesAtEight++;
      for (let frame = 0; frame < 480; frame++) {
        maximumFrameChange = Math.max(maximumFrameChange, Math.abs(
          sampleFront(surfaceFlow, angle, frame / 60)[field] - sampleFront(surfaceFlow, angle, (frame + 1) / 60)[field]));
      }
    }
    assert.ok(changesAtThree > 20 && changesAtEight > 20, `${field} changes over 3 and 8 seconds`);
    assert.ok(maximumFrameChange > 0 && maximumFrameChange < .01, `${field} remains continuous at 60fps`);
  }
  assert.equal((render.match(/= softNoise\(/g) ?? []).length, 2);
});
test('private depth target composites with caller clipping and without shared depth writes', () => {
  assert.ok(render.includes('CombinedDepthStencil'));
  assert.ok(render.includes('gl_FragDepth = distance / (distance + 128.)'));
  const composite = render.slice(render.indexOf('gl.glBindFramebuffer(GL_FRAMEBUFFER, state.drawFramebuffer)'));
  assert.ok(composite.includes('state.scissor) gl.glEnable(GL_SCISSOR_TEST)'));
  assert.ok(composite.includes('state.stencil) gl.glEnable(GL_STENCIL_TEST)'));
  assert.ok(composite.includes('glDepthMask(GL_FALSE)'));
  assert.ok(composite.includes('glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)'));
});

test('GLES 3 mesh and composite shader pairs link with projector interface stubs', context => {
  assert.ok(source.includes('bindAttributeLocation("terrainFlow", 2)'));
  assert.ok(render.includes('surfaceFlow = terrainFlow;'));
  assert.ok(render.includes('gl.glVertexAttribPointer(2, 1, GL_FLOAT, GL_FALSE, sizeof(MistTerrain::Vertex), reinterpret_cast<const void*>(6 * sizeof(float)))'));
  assert.ok(render.includes('gl.glEnableVertexAttribArray(2)'));
  if (spawnSync('glslangValidator', ['--version']).error) return context.skip('glslangValidator unavailable');
  const extract = marker => {
    const start = render.indexOf(marker);
    assert.ok(start >= 0);
    return render.slice(start, render.indexOf('\n)"', start));
  };
  for (const [name, vertex, fragment] of [
    ['mesh', 'vec3 project(vec3 position) { return position; }\n' + extract('ATTRIBUTE highp vec3 terrainPosition;'),
      'vec3 unProject(float horizontal, float vertical, out bool valid) { valid=true; return vec3(horizontal,vertical,1.); }\n' + extract('VARYING highp vec3 surfacePosition;\nVARYING highp vec3 surfaceNormal;\nVARYING highp float surfaceFlow;\nuniform highp vec4 terrainViewport;\nuniform sampler2D')],
    ['composite', extract('ATTRIBUTE highp vec2 vertex;'), extract('VARYING highp vec2 terrainUv;\nuniform sampler2D')]
  ]) {
    const vertexPath = join(temporary, name + '.vert');
    const fragmentPath = join(temporary, name + '.frag');
    writeFileSync(vertexPath, '#version 300 es\nprecision highp float;\n#define ATTRIBUTE in\n#define VARYING out\n' + vertex);
    writeFileSync(fragmentPath, '#version 300 es\nprecision highp float;\n#define VARYING in\n#define FRAG_COLOR fragmentColor\nout vec4 fragmentColor;\n' + fragment);
    execFileSync('glslangValidator', ['-l', vertexPath, fragmentPath]);
  }
});
