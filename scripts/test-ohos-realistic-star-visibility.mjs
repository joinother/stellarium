import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = path => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const drawerSource = read('src/core/StelSkyDrawer.cpp');
const drawerHeader = read('src/core/StelSkyDrawer.hpp');
const toneSource = read('src/core/StelToneReproducer.cpp');
const toneHeader = read('src/core/StelToneReproducer.hpp');
const managerSource = read('src/core/modules/StarMgr.cpp');
const zonesSource = read('src/core/modules/ZoneArray.cpp');
const objectManagerSource = read('src/core/StelObjectMgr.cpp');

function body(source, marker) {
  const declaration = source.indexOf(marker);
  assert.notEqual(declaration, -1, marker);
  const start = source.indexOf('{', declaration);
  let depth = 0;
  for (let index = start; index < source.length; index++) {
    if (source[index] === '{') depth++;
    if (source[index] === '}' && --depth === 0) return source.slice(start, index + 1);
  }
  assert.fail(`Unclosed ${marker}`);
}

function translate(code) {
  return code
    .replace(/\/\/[^\n]*/g, '')
    .replaceAll('static_cast<float>', 'Number')
    .replaceAll(/\b(\d+(?:\.\d*)?(?:e[-+]?\d+)?)f\b/gi, '$1')
    .replaceAll(/\bconst (?:float|double|bool|int|auto) /g, 'const ')
    .replaceAll(/\b(?:float|double|bool|int) /g, 'let ')
    .replaceAll('RCMag rcmag;', 'const rcmag = {};')
    .replaceAll('&rcmag', 'rcmag')
    .replaceAll('->', '.')
    .replaceAll('std::', 'Math.')
    .replaceAll('Math.fabs', 'Math.abs')
    .replaceAll('M_PIf', 'Math.PI')
    .replaceAll('stelpow10f', 'pow10')
    .replaceAll('qMin', 'Math.min')
    .replaceAll('qMax', 'Math.max')
    .replaceAll('StelApp::getInstance().getScreenScale()', 'screenScale')
    .replaceAll('StelCore::luminanceToNELM', 'luminanceToNELM');
}
function method(source, marker, ...args) {
  return new Function(...args, `with (this) ${translate(body(source, marker))}`);
}

const adapt = method(toneHeader, 'float adaptLuminanceScaledLn(', 'lnWorldLuminance', 'pFact');
const adaptLinear = method(toneHeader, 'float adaptLuminance(', 'worldLuminance');
const setWorld = method(toneSource, 'void StelToneReproducer::setWorldAdaptationLuminance(', '_Lwa');
const setInput = method(toneSource, 'void StelToneReproducer::setInputScale(', 'scale');
const setter = new Function('enabled', `with (this) ${body(drawerSource, 'void StelSkyDrawer::setFlagRealisticStarVisibility(')
  .replace('StelApp::immediateSave', 'save')
  .replace('emit flagRealisticStarVisibilityChanged', 'notify')}`);

function makeDrawer({ world = 40000, realistic = true, fov = 60, display = 50, maxDisplay = 100, nelm = 6.3 } = {}) {
  const displayLog = Math.log10(display);
  const tone = {
    Lwa: world, Lda: display, alphaWa: 0, betaWa: 0,
    alphaDa: 0.4 * displayLog + 1.619,
    betaDa: -0.4 * displayLog ** 2 + 0.218 * displayLog + 6.1642,
    alphaWaOverAlphaDa: 0, term2: 0, lnTerm2: 0,
    term2TimesOneOverMaxdL: 0, term2TimesOneOverMaxdLpOneOverGamma: 0,
    oneOverMaxdL: 1 / maxDisplay, lnOneOverMaxdL: Math.log(1 / maxDisplay),
    oneOverGamma: 1 / 2.2222, inputScale: 1, lnInputScale: 0,
    pow10: value => 10 ** value,
    getWorldAdaptationLuminance() { return this.Lwa; },
    getDisplayAdaptationLuminance() { return this.Lda; },
    getMaxDisplayLuminance() { return 1 / this.oneOverMaxdL; },
    getInputScale() { return this.inputScale; },
    adaptLuminanceScaledLn: adapt, adaptLuminance: adaptLinear,
    adaptLuminanceScaled(value) { return this.adaptLuminance(value) * this.oneOverMaxdL; },
    setInputScale: setInput
  };
  setWorld.call(tone, world);
  const state = {
    eye: tone, flagRealisticStarVisibility: realistic,
    core: { getMovementMgr: () => ({ getCurrentFov: () => fov }), getJD: () => 2461356 },
    maxAdaptFov: 70, minAdaptFov: 0.1, lightPollutionLuminance: 0.001,
    inScale: 1, lnfovFactor: 0, starRelativeScale: 1, starAbsoluteScaleF: 1,
    starLinearScale: 0, limitMagnitude: 0, starLimitMagnitude: 0, limitLuminance: 0,
    screenScale: 1, MAX_LINEAR_RADIUS: 8, EYE_RESOLUTION: 0.25,
    getFlagHasAtmosphere: () => true, luminanceToNELM: () => nelm,
    setInputScale(value) { this.inScale = value; },
    computeRCMag: method(drawerSource, 'bool StelSkyDrawer::computeRCMag(', 'mag', 'rcMag'),
    computeStarRCMag: method(drawerSource, 'bool StelSkyDrawer::computeStarRCMag(', 'mag', 'rcMag'),
    computeRCMagFromRadius: method(drawerSource, 'bool StelSkyDrawer::computeRCMagFromRadius(', 'radius', 'rcMag'),
    pointSourceMagToLnLuminance: method(drawerSource, 'float StelSkyDrawer::pointSourceMagToLnLuminance(', 'mag'),
    computeLimitMagnitude: method(drawerSource, 'float StelSkyDrawer::computeLimitMagnitude(', 'forStars'),
    computeLimitLuminance: method(drawerSource, 'float StelSkyDrawer::computeLimitLuminance('),
    update: method(drawerSource, 'void StelSkyDrawer::update('),
    getStarLimitMagnitude: method(drawerHeader, 'float getStarLimitMagnitude('),
    save: () => {}, notify: () => {}, setFlagRealisticStarVisibility: setter
  };
  state.update();
  return state;
}
function sample(drawer, magnitude, stars = true) {
  const result = {};
  result.visible = (stars ? drawer.computeStarRCMag(magnitude, result) : drawer.computeRCMag(magnitude, result));
  return result;
}
function close(actual, expected) {
  assert.ok(Math.abs(actual - expected) <= 1e-10 * Math.max(1, Math.abs(expected)), `${actual} != ${expected}`);
}

test('realistic mode retains the original point-source result across lighting and FOV', () => {
  for (const world of [0.1, 3.75, 100, 40000]) {
    for (const fov of [5, 60, 120]) {
      const drawer = makeDrawer({ world, fov });
      for (const magnitude of [-6, -1, 0, 2, 4, 6, 10, 15]) {
        assert.deepEqual(sample(drawer, magnitude), sample(drawer, magnitude, false));
      }
      assert.equal(drawer.getStarLimitMagnitude(), drawer.limitMagnitude);
    }
  }
});
test('teaching mode shows daytime stars using the existing night tone model', () => {
  for (const display of [30, 50, 100]) {
    const teaching = makeDrawer({ realistic: false, display });
    const reference = makeDrawer({ world: 3.75, display });
    assert.equal(sample(makeDrawer({ display }), 2).visible, false);
    assert.equal(sample(teaching, 2).visible, true);
    for (const magnitude of [-2, 0, 2, 4, 6, 10]) {
      const actual = sample(teaching, magnitude);
      const expected = sample(reference, magnitude);
      assert.equal(actual.visible, expected.visible);
      close(actual.radius, expected.radius);
      close(actual.luminance, expected.luminance);
    }
    close(teaching.getStarLimitMagnitude(), reference.getStarLimitMagnitude());
  }
});
test('teaching mode does not mutate the shared eye or alter nonstellar point sources', () => {
  const drawer = makeDrawer();
  const before = { ...drawer.eye };
  const planetBefore = sample(drawer, -4, false);
  const backgroundBefore = drawer.eye.adaptLuminanceScaled(20000);
  drawer.setFlagRealisticStarVisibility(false);
  drawer.update();
  for (let magnitude = -6; magnitude <= 12; magnitude += 0.5) sample(drawer, magnitude);
  assert.deepEqual(drawer.eye, before);
  assert.deepEqual(sample(drawer, -4, false), planetBefore);
  assert.equal(drawer.eye.adaptLuminanceScaled(20000), backgroundBefore);
  drawer.setFlagRealisticStarVisibility(true);
  drawer.update();
  assert.deepEqual(sample(drawer, 2), sample(drawer, 2, false));
});
test('already-dark scenes are unchanged and zoom still reveals fainter stars', () => {
  for (const world of [0.001, 0.1, 3.75]) {
    const drawer = makeDrawer({ world, realistic: false });
    for (const magnitude of [-2, 2, 5, 9]) assert.deepEqual(sample(drawer, magnitude), sample(drawer, magnitude, false));
  }
  const wide = makeDrawer({ realistic: false, fov: 60 });
  const zoomed = makeDrawer({ realistic: false, fov: 5 });
  assert.ok(zoomed.getStarLimitMagnitude() > wide.getStarLimitMagnitude() + 1);
});
test('LOD searches the same visible stellar levels as the rendering table', () => {
  const searchCode = translate(body(managerSource, 'int StarMgr::getMaxSearchLevel()'))
    .replace('for (const auto* z : gridLevels)', 'for (const z of gridLevels)')
    .replace('StelApp::getInstance().getCore().getSkyDrawer()', 'drawer');
  const search = new Function('gridLevels', 'drawer', searchCode);
  const levels = [-2, 1, 4, 7, 10].map((magnitude, level) => ({ mag_min: magnitude * 1000, level }));
  const realistic = makeDrawer();
  const teaching = makeDrawer({ realistic: false });
  assert.ok(search(levels, teaching) > search(levels, realistic));
  const lastLevel = search(levels, teaching);
  assert.equal(sample(teaching, levels[lastLevel].mag_min / 1000).visible, true);
  assert.equal(sample(teaching, levels[lastLevel + 1].mag_min / 1000).visible, false);
  assert.match(body(managerSource, 'void StarMgr::draw('), /computeStarRCMag\(mag, &rcmag_table\[i\]\)/);
  assert.match(body(managerSource, 'void StarMgr::draw('), /getStarLimitMagnitude\(\)/);
});
test('the setting defaults true, persists false, reloads and emits only on changes', () => {
  const saved = new Map();
  const events = [];
  const drawer = makeDrawer();
  drawer.save = (key, value) => saved.set(key, value);
  drawer.notify = enabled => events.push(enabled);
  const initialization = drawerSource.match(/setFlagRealisticStarVisibility\(conf->value\([^;]+;/)[0];
  const initialize = new Function('conf', `with (this) { ${initialization.replace('conf->', 'conf.').replace('.toBool()', '')} }`);
  const conf = { value: (key, fallback) => saved.has(key) ? saved.get(key) : fallback };
  initialize.call(drawer, conf);
  assert.equal(drawer.flagRealisticStarVisibility, true);
  drawer.setFlagRealisticStarVisibility(false);
  drawer.setFlagRealisticStarVisibility(false);
  assert.deepEqual(events, [false]);
  const restarted = makeDrawer();
  initialize.call(restarted, conf);
  assert.equal(restarted.flagRealisticStarVisibility, false);
  assert.equal(saved.get('viewing/flag_realistic_star_visibility'), false);
  assert.match(drawerHeader, /Q_PROPERTY\(bool flagRealisticStarVisibility READ getFlagRealisticStarVisibility WRITE setFlagRealisticStarVisibility NOTIFY flagRealisticStarVisibilityChanged\)/);
});
test('existing user cutoff and extinction still reject stars in teaching mode', () => {
  const cutoffStart = zonesSource.indexOf('int cutoffMagStep=limitMagIndex;');
  const cutoffEnd = zonesSource.indexOf('Q_ASSERT_X', cutoffStart);
  const cutoffCode = translate(zonesSource.slice(cutoffStart, cutoffEnd))
    .replace(/static_cast<int>\(([^;]+)\)/g, 'Math.trunc($1)');
  const cutoff = new Function('drawer', 'limitMagIndex', 'mag_min', `${cutoffCode}\nreturn { cutoffMagStep, cutoffMag };`);
  const drawer = makeDrawer({ realistic: false });
  assert.equal(sample(drawer, 4).visible, true);
  drawer.getFlagStarMagnitudeLimit = () => true;
  drawer.getCustomStarMagnitudeLimit = () => 2;
  const limits = cutoff(drawer, 400, 0);
  assert.equal(limits.cutoffMag, 2000);
  assert.equal(limits.cutoffMagStep, 180);
  const extinctionStart = zonesSource.indexOf('extinctedMagIndex +=');
  const extinctionEnd = zonesSource.indexOf('tmpRcmag =', extinctionStart);
  const extinctionCode = translate(zonesSource.slice(extinctionStart, extinctionEnd))
    .replace(/static_cast<int>\(([^;]+)\)/g, 'Math.trunc($1)')
    .replace('continue;', 'return false;');
  const visible = new Function('extinctedMagIndex', 'extMagShift', 'cutoffMagStep', `${extinctionCode}\nreturn true;`);
  assert.equal(visible(170, 0, limits.cutoffMagStep), true);
  assert.equal(visible(170, 1, limits.cutoffMagStep), false);
  assert.match(zonesSource, /getFlagHasAtmosphere\(\) && extinction.getExtinctionCoefficient/);
  assert.match(zonesSource, /extinction.forward\(altAz, &extMagShift\)/);
  assert.match(managerSource, /core->getProjection\(StelCore::FrameJ2000\)/);
});

const filterStart = objectManagerSource.indexOf('const float limitMag =');
const filterEnd = objectManagerSource.indexOf('candidates = tmp;', filterStart);
assert.ok(filterStart >= 0 && filterEnd > filterStart);
const filterCandidates = new Function('core', 'candidates', translate(objectManagerSource.slice(filterStart, filterEnd)
  .replace('for (const auto& obj : std::as_const(candidates))', 'for (const obj of candidates)')
  .replace('QList<StelObjectP> tmp;', 'const tmp = [];')
  .replaceAll('tmp.append', 'tmp.push')
  .replaceAll('QLatin1String', 'String')) + '\nreturn tmp;');
const candidate = (type, priority) => ({ getType: () => type, getSelectPriority: () => priority });
function pick(drawer, candidates, customLimit) {
  drawer.getFlagStarMagnitudeLimit = () => customLimit !== undefined;
  drawer.getCustomStarMagnitudeLimit = () => customLimit;
  drawer.getLimitMagnitude = () => drawer.limitMagnitude;
  drawer.getFlagRealisticStarVisibility = () => drawer.flagRealisticStarVisibility;
  return filterCandidates({ getSkyDrawer: () => drawer }, candidates);
}

test('daylight teaching stars pass the actual final picking filter without admitting other faint objects', () => {
  const drawer = makeDrawer({ realistic: false });
  const star = candidate('Star', 2);
  assert.equal(sample(drawer, 2).visible, true);
  assert.deepEqual(pick(drawer, [star, candidate('Planet', 2), candidate('Nebula', 2)]), [star]);
  const realistic = makeDrawer();
  assert.deepEqual(pick(realistic, [star]), []);
});

test('stellar picking respects both user cutoff and the teaching visibility cutoff', () => {
  const drawer = makeDrawer({ realistic: false });
  const bright = candidate('Star', 1);
  const faint = candidate('Star', 4);
  const extincted = candidate('Star', drawer.getStarLimitMagnitude() + 1);
  assert.deepEqual(pick(drawer, [bright, faint, extincted], 2), [bright]);
  assert.deepEqual(pick(drawer, [bright, faint, extincted], 20), [bright, faint]);
});

test('nonstellar thresholds and realistic-mode selection retain the original filter exactly', () => {
  for (const realistic of [true, false]) {
    for (const world of [0.1, 3.75, 40000]) {
      for (const customLimit of [undefined, 2, 10]) {
        const drawer = makeDrawer({ realistic, world });
        const legacyLimit = customLimit ?? drawer.limitMagnitude;
        const types = realistic ? ['Star', 'Planet', 'Nebula', 'Satellite'] : ['Planet', 'Nebula', 'Satellite'];
        const candidates = types.flatMap(type => [-10, -2, 1, 4, 8, 12].map(priority => candidate(type, priority)));
        assert.deepEqual(pick(drawer, candidates, customLimit),
          candidates.filter(object => object.getSelectPriority() <= legacyLimit));
      }
    }
  }
});
