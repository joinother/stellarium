import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const header = read('../src/core/modules/Nebula.hpp');
const source = read('../src/core/modules/Nebula.cpp');
const manager = read('../src/core/modules/NebulaMgr.cpp');
const marker = read('../src/core/MarkerVisibility.hpp');
const painter = read('../src/core/StelPainter.cpp');

function body(sourceText, signature) {
  const start = sourceText.indexOf(signature);
  assert.ok(start >= 0, signature);
  const open = sourceText.indexOf('{', start);
  let depth = 1;
  let end = open + 1;
  for (; depth; ++end) {
    assert.ok(end < sourceText.length);
    if (sourceText[end] === '{') ++depth;
    if (sourceText[end] === '}') --depth;
  }
  return sourceText.slice(open + 1, end - 1);
}

function scalarCpp(text) {
  return text.replace(/\b(\d+(?:\.\d*)?)f\b/g, '$1')
    .replace(/\bconst (?:float|auto|bool) /g, 'const ')
    .replaceAll('std::isfinite', 'Number.isFinite')
    .replaceAll('std::clamp', 'clamp')
    .replaceAll('std::max', 'Math.max').replaceAll('std::min', 'Math.min')
    .replaceAll('std::sqrt', 'Math.sqrt').replaceAll('MarkerVisibility::', 'marker.');
}

const clamp = (value, lower, upper) => Math.min(upper, Math.max(lower, value));
const magnitude = new Function('magnitude', 'limit', 'width', 'clamp', scalarCpp(body(marker, 'inline float magnitudeOpacity')));
const markerMath = { magnitudeOpacity: (value, limit, width = 0.75) => magnitude(value, limit, width, clamp) };
const opacityBody = scalarCpp(body(header, 'inline Opacity opacity'))
  .replace('return {', 'return [').replace(/};\s*$/, '];');
const opacityArray = new Function('magnitude', 'maxHints', 'maxLabels', 'majorAxis', 'angularSizeLimit', 'useOutlines', 'marker', opacityBody);
const opacity = (...args) => {
  const [hints, labels, outlines] = opacityArray(...args, markerMath);
  return { hints, labels, outlines };
};
const canBatchArc = new Function('startX', 'startY', 'endX', 'endY', scalarCpp(body(header, 'inline bool canBatchArc')));
const math = { opacity, canBatchArc };

class Vector extends Array {
  clone() { return new Vector(...this); }
  add(other) { for (let axis = 0; axis < 3; ++axis) this[axis] += other[axis]; return this; }
  normSquared() { return this.reduce((sum, value) => sum + value * value, 0); }
  normalize() { const length = Math.sqrt(this.normSquared()); for (let axis = 0; axis < 3; ++axis) this[axis] /= length; return this; }
}
const vector = (x = 0, y = 0, z = 0) => new Vector(x, y, z);
const list = values => ({ empty: () => !values.length, isEmpty: () => !values.length, size: () => values.length, front: () => values[0], at: index => values[index] });
const textValue = value => ({ isEmpty: () => !value });
class Rect {
  constructor(left, bottom, right, top) { Object.assign(this, { left, bottom, right, top }); }
  intersects(other) { return this.left < other.right && this.right > other.left && this.bottom < other.top && this.top > other.bottom; }
}

const candidateBody = scalarCpp(body(manager, 'void operator()(StelRegionObject* obj)'))
  .replace('Nebula* n = static_cast<Nebula*>(obj);', 'const n = obj;')
  .replace('Nebula::drawFrame', '1')
  .replace('Nebula::DrawVisibility{}', '{labelAlpha: 0, hintAlpha: 0, outlineAlpha: 0}')
  .replaceAll('NebulaDrawing::', 'math.')
  .replaceAll('->', '.')
  .replaceAll('*sPainter', 'sPainter')
  .replace('NebulaMgr::DrawCandidate candidate;', 'const candidate = {labelAlpha: 0, hintAlpha: 0, outlineAlpha: 0, labelKey: "", hintKey: ""};')
  .replace('const int priority', 'const priority')
  .replace('std::numeric_limits<int>::max()', '2147483647')
  .replace('const std::string owner', 'const owner')
  .replace('std::to_string', 'String')
  .replace('const auto& projector', 'const projector')
  .replace(/const ScreenLabelLayout::Rect (\w+)\{([\s\S]*?)\};/g, 'const $1 = new Rect($2);')
  .replaceAll('static_cast<float>', 'Number')
  .replace(/layout.add\(\{(.*?)\}\);/g, 'layout.add([$1]);')
  .replace('candidates.push_back(std::move(candidate));', 'candidates.push(candidate);')
  .replace('Vec3d direction = n.XYZ;', 'let direction = n.XYZ.clone();')
  .replace('direction += aberration;', 'direction.add(aberration);');
const recordDraw = new Function('pass', 'alpha', scalarCpp(body(manager, 'static void recordDraw')));
const drawCandidate = new Function('obj', 'context', 'math', 'Rect', `const {maxMagHints, maxMagLabels, angularSizeLimit, useMagnitudeLimit, magnitudeLimit, useAberration, aberration, sPainter, stats, selected, layout, candidates} = context; ${candidateBody}`);
const renderBody = scalarCpp(body(manager, '\tvoid draw()'))
	.replace('StelPainter::resolveSkyLabelLayout(QStringLiteral("nebulae"));', 'layout.resolve();')
  .replace('for (const auto& candidate : candidates)', 'for (const candidate of candidates)')
  .replace('Nebula* n = candidate.nebula;', 'const n = candidate.nebula;')
  .replaceAll('->', '.').replaceAll('*sPainter', 'sPainter');
const renderCandidates = new Function('context', 'recordDraw', `const {layout, candidates, stats, sPainter, aberration, useAberration} = context; ${renderBody}`);

function candidate(options = {}) {
  const calls = [];
  const object = {
    DSO_nb: options.id ?? 1,
    getScreenLabel: () => textValue(options.label ?? 'test label'),
    getDSODesignation: () => textValue(options.designation ?? 'NGC 1'),
    getHintSize: () => 6,
    drawHintProportional: true,
    XYZ: vector(0, 0, 1), XY: vector(), majorAxisSize: options.size ?? 2,
    culturalNames: list(options.culturalName ? ['name'] : []),
    flagShowOnlyNamedDSO: options.onlyNamed ?? false,
    flagUseOutlines: options.outlinesEnabled ?? true,
    outlineSegments: list(options.outlines ? [[]] : []),
    hintsBrightness: (options.globalFade ?? 1) * (options.hintBrightness ?? 1),
    labelsBrightness: (options.globalFade ?? 1) * (options.labelBrightness ?? 1),
    getEnglishName: () => textValue(options.name ?? ''),
    objectInDisplayedCatalog: () => { calls.push('catalog'); return options.catalog ?? true; },
    objectInAllowedSizeRangeLimits: () => { calls.push('size'); return options.sizeAllowed ?? true; },
    objectInDisplayedType: () => { calls.push('type'); return options.type ?? true; },
    getVisibilityLevelByMagnitude: () => { calls.push('magnitude'); return options.mag ?? 5; },
    drawLabel: (painter, alpha) => calls.push(['label', alpha]),
    drawHints: (painter, alpha, direction) => calls.push(['hint', alpha, direction]),
    drawOutlines: (painter, alpha) => calls.push(['outline', alpha])
  };
  const context = {
    candidates: [], selected: options.selected ? object : null,
    layout: {
      submitted: [],
      add(value) { this.submitted.push(value); },
      resolve() { calls.push('resolve'); },
      accepted(key) { return this.submitted.some(([id]) => id === key) && (options.accepted ?? true); },
      visibility(key) {
        const submitted = this.submitted.find(([id]) => id === key);
        return submitted ? submitted[4] * (submitted[6] ? 1 : options.layoutOpacity?.[key.endsWith(':hint') ? 'hint' : 'label'] ?? 1) : 0;
      }
    },
    stats: { visited: 0, eligible: 0, projected: 0, ...Object.fromEntries(['hints', 'labels', 'outlines'].map(pass => [pass, { candidates: 0, accepted: 0, drawn: 0, alphaSum: 0, alphaMax: 0 }])) },
    maxMagHints: options.hintLimit ?? 10, maxMagLabels: options.labelLimit ?? 8,
    angularSizeLimit: 1, useMagnitudeLimit: options.customLimit !== undefined,
    magnitudeLimit: options.customLimit ?? 99, useAberration: options.aberration ?? false,
    aberration: vector(0.0001, 0, 0),
    sPainter: { skyLabelRect: () => new Rect(20, 20, 80, 50), getProjector: () => ({
      getViewportPosX: () => -100, getViewportPosY: () => -100,
      getViewportWidth: () => 500, getViewportHeight: () => 500,
      getScreenScale: () => 2, getDevicePixelsPerPixel: () => 2,
      projectCheck: () => { calls.push('projectCheck'); return options.onScreen ?? true; },
      project: () => { calls.push('project'); return true; }
    }) }
  };
  drawCandidate(object, context, math, Rect);
  assert.ok(!calls.some(Array.isArray), 'collection must not draw');
  renderCandidates(context, recordDraw);
  return { calls, draws: calls.filter(Array.isArray), stats: context.stats, visibility: object.drawVisibility, submitted: context.layout.submitted };
}

test('threshold fade is bounded, continuous, monotone and never adds dimmer targets', () => {
  for (const limit of [-2, 0, 8, 15]) {
    assert.equal(markerMath.magnitudeOpacity(limit, limit), 0);
    assert.equal(markerMath.magnitudeOpacity(limit - 0.75, limit), 1);
    assert.equal(markerMath.magnitudeOpacity(limit - 0.375, limit), 0.5);
    let previous = 1;
    for (let step = 0; step <= 1000; ++step) {
      const value = markerMath.magnitudeOpacity(limit - 1 + step / 500, limit);
      assert.ok(value >= 0 && value <= previous && previous - value < 0.005);
      previous = value;
    }
  }
});

test('soft pass support remains inside every legacy candidate and pass gate', () => {
  for (const maxHints of [0, 8, 12]) for (const maxLabels of [2, 7, 14]) {
    for (const major of [0, 0.5, 0.999, 1, 1.001, 1.125, 2]) for (const outlines of [false, true]) {
      for (let step = -20; step <= 180; ++step) {
        const mag = step / 10;
        const result = opacity(mag, maxHints, maxLabels, major, 1, outlines);
        const oldCandidate = major > 1 || major === 0 || mag <= maxHints;
        const old = {
          hints: oldCandidate && !outlines && mag <= maxHints,
          labels: oldCandidate && mag <= maxLabels,
          outlines: oldCandidate && outlines && mag - 3 <= maxHints
        };
        for (const pass of ['hints', 'labels', 'outlines']) {
          assert.ok(result[pass] >= 0 && result[pass] <= 1);
          if (result[pass] > 0) assert.ok(old[pass], `new target ${pass}`);
          const boundary = mag === (pass === 'labels' ? maxLabels : maxHints + (pass === 'outlines' ? 3 : 0))
            || (major > 0 && major <= 1 && mag === maxHints);
          if (old[pass] && !boundary) assert.ok(result[pass] > 0, `lost ${pass}: ${JSON.stringify({ mag, major, maxHints, maxLabels, outlines })}`);
        }
      }
    }
  }
});

test('size fade is scale relative, reversible and retains zero-size catalogue objects', () => {
  for (const scale of [0.01, 1, 100]) {
    let previous = 0;
    for (let step = 0; step <= 100; ++step) {
      const major = scale * (1 + step / 400);
      const value = opacity(11, 10, 13, major, scale, true).outlines;
      assert.ok(value >= previous && value - previous < 0.016);
      assert.equal(value, opacity(11, 10, 13, major, scale, true).outlines);
      previous = value;
    }
    assert.ok(Math.abs(opacity(11, 10, 13, 1.125 * scale, scale, true).outlines - 0.5) < 1e-12);
    assert.equal(opacity(11, 10, 13, 0, scale, true).outlines, 1);
  }
});

test('OR candidate and AND pass compose without squaring the shared magnitude fade', () => {
  assert.equal(opacity(9.625, 10, 12, 0.1, 1, false).hints, 0.5);
  assert.equal(opacity(9.625, 10, 12, 0.1, 1, false).labels, 0.5);
  assert.equal(opacity(9.625, 10, 12, 0.1, 1, true).outlines, 0.5);
  assert.equal(opacity(12.625, 10, 14, 2, 1, true).outlines, 0.5);
});

test('actual candidate rejects explicit filters before projection, without stale caches', () => {
  for (const options of [{ catalog: false }, { type: false }, { sizeAllowed: false }, { onlyNamed: true }, { customLimit: 4 }]) {
    const result = candidate(options);
    assert.deepEqual(result.draws, []);
    assert.ok(!result.calls.includes('projectCheck'));
    assert.ok(candidate().draws.length > 0);
  }
  assert.equal(candidate({ onlyNamed: true, culturalName: true }).draws.length, 2);
  assert.equal(candidate({ onlyNamed: true, name: 'named' }).draws.length, 2);
});

test('one type/magnitude/center check serves both label and hint, preserving aberration', () => {
  for (const aberration of [false, true]) {
    const { calls, draws } = candidate({ aberration });
    for (const operation of ['type', 'magnitude', 'projectCheck']) assert.equal(calls.filter(call => call === operation).length, 1);
    assert.equal(calls.filter(call => call === 'project').length, Number(aberration));
    assert.deepEqual(draws.map(draw => draw[0]), ['label', 'hint']);
    assert.equal(draws[1][2][0] > 0, aberration);
  }
});

test('outline-only candidates skip center projection and screen-outside centers do not suppress outlines', () => {
  for (const onScreen of [false, true]) {
    const result = candidate({ mag: 11, outlines: true, onScreen });
    assert.deepEqual(result.draws.map(draw => draw[0]), ['outline']);
    assert.ok(!result.calls.includes('projectCheck'));
  }
  assert.deepEqual(candidate({ outlines: true, onScreen: false }).draws.map(draw => draw[0]), ['outline']);
});

test('labels remain independent and enabling outlines suppresses every marker shape', () => {
  assert.deepEqual(candidate({ mag: 11, labelLimit: 14 }).draws.map(draw => draw[0]), ['label']);
  assert.deepEqual(candidate({ mag: 14, labelLimit: 16, outlines: true }).draws.map(draw => draw[0]), ['label']);
  assert.deepEqual(candidate({ outlines: true }).draws.map(draw => draw[0]), ['label', 'outline']);
  assert.deepEqual(candidate({ outlines: true, outlinesEnabled: false }).draws.map(draw => draw[0]), ['label', 'hint']);
  assert.deepEqual(candidate({ mag: 11, labelLimit: 14, size: 0.1, outlines: true }).draws, []);
});

test('threshold opacity multiplies the global layer fade and independent brightness exactly once', () => {
  const result = candidate({ mag: 9.625, labelLimit: 10, size: 0.1, globalFade: 0.4, hintBrightness: 0.6, labelBrightness: 0.8 });
  assert.equal(result.draws[0][1], 0.4 * 0.8 * 0.5);
  assert.equal(result.draws[1][1], 0.4 * 0.6 * 0.5);
  assert.deepEqual(candidate({ globalFade: 0, outlines: true }).draws, []);
  assert.deepEqual(candidate({ hintBrightness: 0, outlines: true }).draws.map(draw => draw[0]), ['label']);
  assert.deepEqual(candidate({ labelBrightness: 0 }).draws.map(draw => draw[0]), ['hint']);
});

test('read-only draw diagnostics distinguish visited, eligible, projected and each pass', () => {
  const rejected = candidate({ catalog: false }).stats;
  assert.equal(rejected.visited, 1);
  assert.equal(rejected.eligible, 0);
  assert.equal(rejected.projected, 0);
  const outlineOnly = candidate({ mag: 11, outlines: true, onScreen: false }).stats;
  assert.equal(outlineOnly.eligible, 1);
  assert.equal(outlineOnly.projected, 0);
  assert.equal(outlineOnly.labels.drawn, 0);
  assert.equal(outlineOnly.hints.drawn, 0);
  assert.equal(outlineOnly.outlines.drawn, 1);
  const faded = candidate({ mag: 9.625, labelLimit: 10, globalFade: 0.4 }).stats;
  for (const pass of ['hints', 'labels']) {
    assert.deepEqual(faded[pass], { candidates: 1, accepted: 1, drawn: 1, alphaSum: 0.2, alphaMax: 0.2 });
  }
  const draw = body(manager, 'void NebulaMgr::draw(StelCore* core)');
  assert.ok(draw.indexOf('drawStats = DrawStats{};') < draw.indexOf('if (!core->getFlagClearSky())'));
  assert.match(draw, /hintsFader.getInterstate\(\)>0.f && flagShow.getInterstate\(\)>0.f/);
  assert.ok(draw.indexOf('++Nebula::drawFrame;') < draw.indexOf('if (!core->getFlagClearSky())'));
  assert.deepEqual(candidate({ mag: 11, outlines: true, onScreen: false }).visibility,
    { labelAlpha: 0, hintAlpha: 0, outlineAlpha: 1 });
  const visible = new Function('visibilityFrame', 'drawFrame', 'drawVisibility',
    body(header, 'DrawVisibility getDrawVisibility()').replace('DrawVisibility{}', '{ labelAlpha: 0, hintAlpha: 0, outlineAlpha: 0 }'));
  assert.deepEqual(visible(1, 2, { labelAlpha: 1, hintAlpha: 1, outlineAlpha: 1 }),
    { labelAlpha: 0, hintAlpha: 0, outlineAlpha: 0 });
});

test('all DSO pick entry points reject hidden passes at the same actual alpha boundary', () => {
  const pick = body(source, 'StelObjectPickState Nebula::getPickState');
  const start = pick.indexOf('const auto visibility = getDrawVisibility();');
  const end = pick.indexOf('const float mag =', start);
  assert.ok(start >= 0 && end > start);
  const evaluate = new Function('render', 'alpha', 'landscapeVisible', `
    const state = {landscapeVisible};
    const getDrawVisibility = () => ({hintAlpha: alpha.hint, labelAlpha: alpha.label, outlineAlpha: alpha.outline});
    const getAngularRadius = () => 2;
    const core = null, M_PI = Math.PI;
    ${scalarCpp(pick.slice(start, end))}
    return state;
  `);
  const render = {hintDrawn: true, labelDrawn: true, outlineDrawn: true};
  for (const alpha of [0, 0.049, 0.05]) {
    const state = evaluate(render, {hint: alpha, label: alpha, outline: alpha}, true);
    assert.equal(state.pickable, false);
    assert.equal(state.visualRadiusRad, 0);
  }
  for (const pass of ['hint', 'label', 'outline']) {
    const alpha = {hint: 0, label: 0, outline: 0, [pass]: 0.051};
    const state = evaluate(render, alpha, true);
    assert.equal(state.pickable, true);
    assert.equal(state.pointDrawn, pass === 'hint');
    assert.equal(state.labelDrawn, pass === 'label');
    assert.equal(state.outlineDrawn, pass === 'outline');
    assert.equal(state.visualRadiusRad > 0, pass === 'outline');
    assert.equal(evaluate(render, alpha, false).pickable, false);
    assert.equal(evaluate({hintDrawn: false, labelDrawn: false, outlineDrawn: false}, alpha, true).pickable, false);
  }
});

test('two-stage layout uses stable owner keys, named/selected priority and independent marker/text alpha', () => {
  const unnamed = candidate({ id: 42 });
  assert.deepEqual(unnamed.submitted.map(entry => entry[0]), ['dso:42:label', 'dso:42:hint']);
  assert.ok(unnamed.submitted.every(entry => entry[2] === 0 && entry[5] === 'dso:42'));
  assert.ok(candidate({ name: 'named' }).submitted.every(entry => entry[2] === 1));
  assert.ok(candidate({ culturalName: true }).submitted.every(entry => entry[2] === 1));
  const selected = candidate({ selected: true, layoutOpacity: { label: 0.3, hint: 0 } });
  assert.ok(selected.submitted.every(entry => entry[2] === 2147483647));
  assert.equal(selected.submitted[0][6], true);
  assert.equal(selected.submitted[1][6], true);
  assert.equal(selected.visibility.hintAlpha, 1);
  assert.equal(selected.visibility.labelAlpha, 1);
  const separate = candidate({ layoutOpacity: { label: 0, hint: 0.4 }, accepted: false });
  assert.deepEqual(separate.draws.map(draw => draw[0]), ['hint']);
  assert.equal(separate.visibility.labelAlpha, 0);
  assert.equal(separate.visibility.hintAlpha, 0.4);
  assert.equal(separate.stats.hints.accepted, 0);
  assert.equal(separate.stats.hints.drawn, 1);
});

test('outlines never enter occupancy and layout results cannot hide real outline geometry', () => {
  const result = candidate({ outlines: true, layoutOpacity: { label: 0, hint: 0 } });
  assert.deepEqual(result.submitted.map(entry => entry[0]), ['dso:1:label']);
  assert.deepEqual(result.draws.map(draw => draw[0]), ['outline']);
  assert.equal(result.visibility.outlineAlpha, 1);
  const noText = candidate({ label: '', designation: '' });
  assert.deepEqual(noText.submitted.map(entry => entry[0]), ['dso:1:hint']);
  assert.equal(noText.stats.labels.candidates, 0);
});

test('short-arc batching never accepts an edge the current painter would subdivide', () => {
  const tessellator = body(painter, 'inline void fIter(');
  assert.match(tessellator, /cosAngle>-0\.999f \|\| dist>50\*50 \|\| crossDiscontinuity/);
  assert.equal(canBatchArc(-50, 0, 50, 0), true);
  assert.equal(canBatchArc(-50.001, 0, 50.001, 0), false);
  assert.equal(canBatchArc(-5, 2, 5, 2), false);
  assert.equal(canBatchArc(0, 0, 0, 0), false);
  assert.equal(canBatchArc(NaN, 0, 1, 0), false);
  let seed = 1729;
  const random = () => { seed = (1664525 * seed + 1013904223) >>> 0; return seed / 2 ** 32; };
  for (let sample = 0; sample < 20000; ++sample) {
    const offsets = Array.from({ length: 4 }, () => (random() - 0.5) * 150);
    const [startX, startY, endX, endY] = offsets;
    const dist = Math.sqrt((startX ** 2 + startY ** 2) * (endX ** 2 + endY ** 2));
    const cosAngle = (startX * endX + startY * endY) / dist;
    if (canBatchArc(...offsets)) assert.ok(!(cosAngle > -0.999 || dist > 2500));
  }
});

test('draw and pick share thresholds; marker branches forward alpha; outline fallback and GL state stay explicit', () => {
  const pick = body(source, 'Nebula::RenderState Nebula::getRenderState');
  assert.match(pick, /NebulaDrawing::opacity/);
  for (const pass of ['hint', 'label', 'outline']) assert.match(pick, new RegExp(`state\\.${pass}Drawn = base && opacity\\.${pass}s > 0\\.f`));
  const hint = body(source, 'void Nebula::drawHints');
  for (const call of hint.matchAll(/render\w+\(sPainter[^;]+;/g)) assert.match(call[0], /, alpha\);$/);
  for (const method of ['drawLabel', 'drawHints', 'renderDarkNebulaMarker', 'renderRoundMarker', 'renderEllipticMarker', 'renderMarkerRoundedRect', 'renderMarkerPointedCircle']) {
    assert.doesNotMatch(body(source, `void Nebula::${method}`), /hintsBrightness|labelsBrightness|objectInDisplayedType|getVisibilityLevelByMagnitude|projectCheck/);
  }
  const outline = body(source, 'void Nebula::drawOutlines');
  assert.match(outline, /!projector->intersectViewportDiscontinuity\(point1, point2\)/);
  assert.match(outline, /projector->projectInPlace\(midpoint\)/);
  assert.match(outline, /if \(!batched\)\s*\{\s*flush\(\);\s*sPainter.drawGreatCircleArc\(point1, point2, &viewportHalfspace\);/);
  assert.match(outline, /vertices.size\(\) == 256/);
  assert.match(outline, /drawFromArray\(StelPainter::Lines, vertices.size\(\), 0, false\)/);
  assert.match(outline, /enableClientStates\(false\)/);
  assert.match(outline, /flush\(\);\s*sPainter.setLineSmooth\(false\);/);
});

class VertexBuffer {
  values = [];
  isEmpty() { return !this.values.length; }
  size() { return this.values.length; }
  constData() { return this.values; }
  append(value) { this.values.push(value); }
  clear() { this.values.length = 0; }
}

const outlineBody = scalarCpp(body(source, 'void Nebula::drawOutlines'))
  .replace('const auto& projector', 'const projector')
  .replace('const SphericalCap& viewportHalfspace', 'const viewportHalfspace')
  .replace('QVarLengthArray<Vec3f, 256> vertices;', 'const vertices = new VertexBuffer();')
  .replace('const flush = [&]()', 'const flush = () =>')
  .replace('const apparentPosition = [&](Vec3d point)\n\t{', 'const apparentPosition = input => { let point = input.clone();')
  .replace('point += aberration;', 'point.add(aberration);')
  .replace('for (const auto* points : outlineSegments)', 'for (const points of outlineSegments)')
  .replace('Vec3d point1 =', 'let point1 =')
  .replace('const Vec3d point2 =', 'const point2 =')
  .replace('size_t index', 'let index')
  .replace('Vec3d screen1, screen2;', 'const screen1 = vector(), screen2 = vector();')
  .replace('bool batched =', 'let batched =')
  .replace('Vec3d midpoint = point1 + point2;', 'const midpoint = point1.clone().add(point2);')
  .replaceAll('static_cast<float>', 'Math.fround')
  .replaceAll('Vec3f(', 'vector(')
  .replaceAll('NebulaDrawing::', 'math.')
  .replaceAll('StelPainter::Lines', '"lines"')
  .replaceAll('GL_FLOAT', '"float"')
  .replaceAll('&viewportHalfspace', 'viewportHalfspace')
  .replaceAll('->', '.');
const drawOutline = new Function('sPainter', 'alpha', 'aberration', 'useAberration', 'outlineSegments', 'math', 'vector', 'VertexBuffer', `const getHintColor = () => [0.2, 0.3, 0.4]; const nType = 0; ${outlineBody}`);

function outlineRun(segments, options = {}) {
  const calls = [];
  const cap = { contains: point => options.capContains?.(point) ?? true };
  const project = (point, screen) => {
    const projected = [1000 * point[0] / (1 + point[2]), 1000 * point[1] / (1 + point[2]), 1];
    for (let axis = 0; axis < 3; ++axis) screen[axis] = projected[axis];
    return true;
  };
  const projector = {
    getScreenScale: () => 2,
    getBoundingCap: () => cap,
    intersectViewportDiscontinuity: () => options.discontinuity ?? false,
    projectCheck: (point, screen) => project(point, screen) && (options.centerVisible ?? true),
    projectInPlace: point => project(point.clone(), point) && (options.midpointValid ?? true)
  };
  let vertexData;
  const painter = {
    getProjector: () => projector,
    setColor: (color, alpha) => calls.push({ kind: 'color', color, alpha }),
    setLineWidth: width => calls.push({ kind: 'width', width }),
    setBlending: value => calls.push({ kind: 'blend', value }),
    setLineSmooth: value => calls.push({ kind: 'smooth', value }),
    enableClientStates: value => calls.push({ kind: 'client', value }),
    setVertexPointer: (dimension, type, values) => { assert.equal(dimension, 3); vertexData = values; },
    drawFromArray: (mode, count, offset, doProj) => {
      assert.equal(mode, 'lines'); assert.equal(offset, 0); assert.equal(doProj, false);
      calls.push({ kind: 'batch', vertices: vertexData.map(point => [...point]), count });
    },
    drawGreatCircleArc: (start, end, clipping) => {
      assert.equal(clipping, cap);
      calls.push({ kind: 'fallback', start: [...start], end: [...end] });
    }
  };
  drawOutline(painter, 0.37, options.aberration ?? vector(), Boolean(options.aberration), segments.map(list), math, vector, VertexBuffer);
  return calls;
}

const direction = x => vector(x, 0, 1).normalize();

test('actual outline path batches independent short edges with identical endpoints and bounded storage', () => {
  const points = Array.from({ length: 301 }, (_, index) => direction((index - 150) * 0.001));
  const calls = outlineRun([[], [direction(0)], points]);
  const batches = calls.filter(call => call.kind === 'batch');
  assert.equal(calls.filter(call => call.kind === 'fallback').length, 0);
  assert.deepEqual(batches.map(batch => batch.count), [256, 256, 88]);
  const vertices = batches.flatMap(batch => batch.vertices);
  for (let index = 0; index < points.length - 1; ++index) {
    for (const endpoint of [0, 1]) {
      const point = points[index + endpoint];
      assert.deepEqual(vertices[2 * index + endpoint], [1000 * point[0] / (1 + point[2]), 0, 1]);
    }
  }
  assert.equal(calls[0].alpha, 0.37);
  assert.deepEqual(calls.at(-1), { kind: 'smooth', value: false });
  assert.deepEqual(calls.filter(call => call.kind === 'client').map(call => call.value), [true, false, true, false, true, false]);
});

test('invalid projection, clipping, seams, long or degenerate edges preserve original arc fallback', () => {
  const short = [direction(0), direction(0.01)];
  for (const options of [{ discontinuity: true }, { capContains: () => false }, { midpointValid: false }, { centerVisible: false }]) {
    const draws = outlineRun([short], options).filter(call => ['batch', 'fallback'].includes(call.kind));
    assert.deepEqual(draws, [{ kind: 'fallback', start: [...short[0]], end: [...short[1]] }]);
  }
  for (const points of [[direction(0), direction(1)], [direction(0), direction(0)], [vector(0, 0, 1), vector(0, 0, -1)]]) {
    assert.equal(outlineRun([points]).filter(call => call.kind === 'fallback').length, 1);
  }
});

test('fallback flush preserves draw order, disconnected segments and aberrated endpoints', () => {
  const first = [direction(0), direction(0.01)];
  const second = [direction(0.2), direction(0.21)];
  const calls = outlineRun([first, second], { capContains: point => point[0] < 0.1 });
  assert.deepEqual(calls.filter(call => ['batch', 'fallback'].includes(call.kind)).map(call => call.kind), ['batch', 'fallback']);
  const aberration = vector(0.001, 0.002, 0);
  const shifted = outlineRun([first], { aberration, discontinuity: true }).find(call => call.kind === 'fallback');
  assert.deepEqual(shifted.start, [...first[0].clone().add(aberration).normalize()]);
  assert.deepEqual(shifted.end, [...first[1].clone().add(aberration).normalize()]);
  assert.deepEqual(first[0], direction(0));
});
