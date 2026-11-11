import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
const start = source.indexOf('if (commandName == "moveToAltAz")');
assert.ok(start >= 0);
const handler = source.slice(start, source.indexOf('if (commandName == "beginGyroViewTransition")', start));
const applyStart = handler.indexOf('if (duration == 0.f)');
assert.ok(applyStart >= 0);
const applyEnd = handler.indexOf('mvmgr->moveToAltAzi(aim, aimUp, duration);', applyStart);
assert.ok(applyEnd >= 0);
const apply = new Function('duration', 'aim', 'aimUp', 'mvmgr', 'core', handler
  .slice(applyStart, applyEnd + 'mvmgr->moveToAltAzi(aim, aimUp, duration);'.length)
  .replace('0.f', '0')
  .replace('StelCore* core = StelApp::getInstance().getCore();', '')
  .replaceAll('StelCore::RefractionOff', '"off"')
  .replaceAll('->', '.'));

const dot = (left, right) => left.reduce((sum, value, index) => sum + value * right[index], 0);
const cross = (left, right) => [
  left[1] * right[2] - left[2] * right[1],
  left[2] * right[0] - left[0] * right[2],
  left[0] * right[1] - left[1] * right[0]
];
const normalize = vector => vector.map(value => value / Math.hypot(...vector));
const subtract = (left, right) => left.map((value, index) => value - right[index]);
const scale = (vector, factor) => vector.map(value => value * factor);
const vectorStart = handler.indexOf('Vec3d aim;');
const vectorEnd = handler.indexOf('if (parts.size() > 3', vectorStart);
assert.ok(vectorStart >= 0 && vectorEnd > vectorStart);
function translateMotion(code) {
  return code
  .replace(/\/\/[^\n]*/g, '')
  .replace('Vec3d aim;', 'let aim = [0, 0, 0];')
  .replace('Vec3d aimUp(0., 0., 1.);', 'let aimUp = [0, 0, 1];')
  .replaceAll('aimUp -= aim * aim.dot(aimUp);', 'aimUp = subtract(aimUp, scale(aim, dot(aim, aimUp)));')
  .replaceAll('aimUp.normSquared()', 'dot(aimUp, aimUp)')
  .replace('Vec3d(-cos(az * M_PI / 180.), -sin(az * M_PI / 180.), 0.) * (alt >= 0. ? 1. : -1.)',
    'scale([-cos(az * M_PI / 180.), -sin(az * M_PI / 180.), 0], alt >= 0 ? 1 : -1)')
  .replaceAll('aimUp.normalize();', 'aimUp = normalize(aimUp);')
  .replace('aimUp /= upLength;', 'aimUp = scale(aimUp, 1 / upLength);')
  .replace('bool okUpX', 'let okUpX')
  .replace('const double upLength', 'const upLength')
  .replace(/parts\[(\d)\]\.toDouble\(&(okUp\w)\)/g,
    'parseComponent(parts[$1], valid => { $2 = valid; })')
  .replace('aimUp = Vec3d(', 'aimUp = Array.of(')
  .replaceAll('parts.size()', 'parts.length')
  .replaceAll('std::hypot', 'Math.hypot')
  .replaceAll('std::isfinite', 'Number.isFinite')
  .replace('StelCore* core = StelApp::getInstance().getCore();', '')
  .replaceAll('StelCore::RefractionOff', '"off"')
  .replaceAll('->', '.')
  .replace('0.f', '0')
  .replaceAll('M_PI', 'Math.PI')
  .replaceAll(/\b(cos|sin)\(/g, 'Math.$1(');
}
const makeVectors = new Function('az', 'alt', 'dot', 'subtract', 'scale', 'normalize',
  translateMotion(handler.slice(vectorStart, vectorEnd)) + '\nreturn { aim, aimUp };');
const vectors = (az, alt) => makeVectors(az, alt, dot, subtract, scale, normalize);
const execute = new Function('az', 'alt', 'duration', 'parts', 'mvmgr', 'core',
  'dot', 'subtract', 'scale', 'normalize', 'parseComponent',
  'const result = {};\n' + translateMotion(handler.slice(vectorStart,
    applyEnd + 'mvmgr->moveToAltAzi(aim, aimUp, duration);'.length)) + '\nreturn { ok: true };');
function command(azimuth, altitude, duration, explicitUp, state) {
  const parts = [String(azimuth), String(altitude), String(duration), ...explicitUp.map(String)];
  return execute(azimuth, altitude, duration, parts, state.manager, state.core,
    dot, subtract, scale, normalize, (text, setValid) => {
      const value = Number(text);
      setValid(text.trim() !== '' && (!Number.isNaN(value) || text.toLowerCase() === 'nan'));
      return value;
    });
}

function harness() {
  const calls = [];
  const rotation = [[0.36, -0.8, 0.48], [0.48, 0.6, 0.64], [-0.8, 0, 0.6]];
  const rotate = vector => rotation.map(row => dot(row, vector));
  const core = {
    altAzToJ2000(vector, refraction) {
      assert.equal(refraction, 'off');
      return rotate(vector);
    }
  };
  const manager = {
    autoMove: true,
    targetObject: 'old target',
    up: [0, 0, 1],
    cancelAutoMove() {
      calls.push('cancel');
      this.autoMove = false;
      this.targetObject = null;
    },
    setViewUpVectorJ2000(up) { calls.push('up'); this.up = up; },
    setViewDirectionJ2000(direction) {
      calls.push('direction');
      this.direction = direction;
      this.upAtLookAt = [...this.up];
      this.side = normalize(cross(direction, this.up));
    },
    moveToAltAzi(...args) { calls.push('animated'); this.animatedArgs = args; }
  };
  return { calls, core, manager, rotate };
}

for (const altitude of [90, -90, 89, 0]) {
  test(`instant altitude ${altitude} cancels movement and applies a finite camera basis in J2000`, () => {
    for (const azimuth of [0, 45, 180, 270]) {
      const { aim, aimUp } = vectors(azimuth, altitude);
      const { calls, core, manager, rotate } = harness();
      apply(0, aim, aimUp, manager, core);
      assert.deepEqual(calls, ['cancel', 'up', 'direction']);
      assert.equal(manager.autoMove, false);
      assert.equal(manager.targetObject, null);
      assert.deepEqual(manager.direction, rotate(aim));
      assert.deepEqual(manager.upAtLookAt, rotate(aimUp));
      assert.ok(manager.side.every(Number.isFinite));
      assert.ok(Math.abs(dot(manager.upAtLookAt, manager.direction)) < 1e-12);
      assert.ok(Math.abs(dot(manager.side, manager.direction)) < 1e-12);
    }
  });
}

test('instant moves retain an explicitly supplied valid roll vector', () => {
  const { calls, core, manager, rotate } = harness();
  apply(0, [0, 0, 1], [0, 1, 0], manager, core);
  assert.deepEqual(calls, ['cancel', 'up', 'direction']);
  assert.deepEqual(manager.upAtLookAt, rotate([0, 1, 0]));
});

test('nonzero durations retain the existing animation call without touching camera state', () => {
  const { aim, aimUp } = vectors(30, 90);
  for (const duration of [0.5, 1, 3, -1]) {
    const { calls, core, manager } = harness();
    apply(duration, aim, aimUp, manager, core);
    assert.deepEqual(calls, ['animated']);
    assert.deepEqual(manager.animatedArgs, [aim, aimUp, duration]);
    assert.equal(manager.autoMove, true);
    assert.equal(manager.targetObject, 'old target');
    assert.equal(manager.direction, undefined);
  }
});

test('invalid explicit up rejects both duration paths without modifying camera or pending movement', () => {
  const invalidVectors = [[], [0], [0, 1], [0, 0, 0], [0, 0.001, 0],
    [1, 0, 0], [-1, 0, 0], [1, 1e-6, 0], [-1, 0, 1e-6],
    ['bad', 1, 0], ['', 1, 0], [NaN, 1, 0], [Infinity, 1, 0], [0, -Infinity, 1]];
  for (const duration of [0, 0.5]) {
    for (const explicitUp of invalidVectors.filter(vector => vector.length > 0)) {
      const state = harness();
      const before = { ...state.manager };
      const result = command(0, 0, duration, explicitUp, state);
      assert.equal(result.ok, false, JSON.stringify({ duration, explicitUp }));
      assert.equal(typeof result.error, 'string');
      assert.deepEqual(state.calls, []);
      assert.deepEqual(state.manager, before);
    }
  }
});

test('valid explicit up is orthogonalized and normalized before either duration path', () => {
  for (const duration of [0, 0.5]) {
    for (const explicitUp of [[2, 3, 0], [0, 1e200, 0]]) {
      const state = harness();
      assert.equal(command(0, 0, duration, explicitUp, state).ok, true);
      if (duration === 0) {
        assert.deepEqual(state.calls, ['cancel', 'up', 'direction']);
        assert.deepEqual(state.manager.upAtLookAt, state.rotate([0, 1, 0]));
      } else {
        assert.deepEqual(state.calls, ['animated']);
        assert.deepEqual(state.manager.animatedArgs, [[1, 0, 0], [0, 1, 0], duration]);
      }
    }
  }
});

test('omitted explicit up retains safe automatic vectors at both poles', () => {
  for (const altitude of [-90, 90]) {
    const state = harness();
    assert.equal(command(0, altitude, 0, [], state).ok, true);
    assert.ok(state.manager.side.every(Number.isFinite));
  }
});

test('view direction readback remains finite at floating-point pole overshoot', () => {
  const readbackStart = source.indexOf('if (commandName == "getViewDirection")');
  const readback = source.slice(readbackStart, source.indexOf('return result;', readbackStart));
  assert.ok(readback.includes('altAz.normalize();'));
  const expression = readback.match(/double alt = ([^;]+);/)[1];
  const altitude = new Function('altAz', expression
    .replace('asin(', 'return Math.asin(')
    .replace('qBound(-1.0, altAz[2], 1.0)', 'Math.max(-1, Math.min(1, altAz[2]))')
    .replace('M_PI', 'Math.PI'));
  for (const height of [1 + Number.EPSILON, 1, -1, -1 - Number.EPSILON]) {
    assert.equal(altitude([0, 0, height]), Math.sign(height) * 90);
  }
});
