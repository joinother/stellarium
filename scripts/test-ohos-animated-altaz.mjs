import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../src/core/StelMovementMgr.cpp', import.meta.url), 'utf8');
const updateStart = source.indexOf('void StelMovementMgr::updateVisionVector');
const noTargetStart = source.indexOf('else // no targetObject:', updateStart);
const stepStart = source.indexOf('move.coef+=', noTargetStart);
const stepEndText = 'setViewDirectionJ2000(mountFrameToJ2000(tmp));';
const stepEnd = source.indexOf(stepEndText, stepStart) + stepEndText.length;
assert.ok(updateStart >= 0 && noTargetStart > updateStart && stepEnd > stepStart);
const resetUp = source.slice(source.indexOf('{', noTargetStart) + 1, stepStart).replace(/}\s*$/, '');
const nativeStep = resetUp + source.slice(stepStart, stepEnd);

class Vector extends Array {
  get v() { return this; }
  dot(other) { return this.reduce((sum, value, index) => sum + value * other[index], 0); }
  normSquared() { return this.dot(this); }
  normalize() {
    const length = Math.hypot(...this);
    for (let index = 0; index < 3; ++index) this[index] /= length;
    return this;
  }
}
const vector = values => new Vector(...values);
const subtract = (left, right) => vector(left.map((value, index) => value - right[index]));
const scale = (value, factor) => vector(value.map(component => component * factor));
const add = (left, right) => vector(left.map((value, index) => value + right[index]));
const cross = (left, right) => new Vector(
  left[1] * right[2] - left[2] * right[1],
  left[2] * right[0] - left[0] * right[2],
  left[0] * right[1] - left[1] * right[0]);
const spheToRect = (azimuth, altitude) => new Vector(
  Math.cos(altitude) * Math.cos(azimuth), Math.cos(altitude) * Math.sin(azimuth), Math.sin(altitude));
const rectToSphe = value => [Math.atan2(value[1], value[0]), Math.asin(Math.max(-1, Math.min(1, value[2] / Math.hypot(...value))))];
const radians = degrees => degrees * Math.PI / 180;
const tangent = (azimuth, altitude) => new Vector(
  -Math.sin(altitude) * Math.cos(azimuth), -Math.sin(altitude) * Math.sin(azimuth), Math.cos(altitude));

function translate(code) {
  return code
    .replace(/\/\/[^\n]*/g, '')
    .replace(/Q_ASSERT\([^\n]+\);/g, '')
    .replace(/static_cast<double>\(/g, '(')
    .replace(/static_cast<float>\(/g, '(')
    .replace(/\b(\d+(?:\.\d*)?)f\b/g, '$1')
    .replace(/\bconst (?:float|double)\b/g, 'const')
    .replace(/\bdouble\b/g, 'let')
    .replace('const auto rollFor = [](const Vec3d& up, let azimuth, let altitude)',
      'const rollFor = (up, azimuth, altitude) =>')
    .replace(/const Vec3d (\w+)\(/g, 'const $1 = new Vector(')
    .replace(/const Vec3d (\w+)/g, 'const $1')
    .replace(/Vec3d (\w+)\(/g, 'let $1 = new Vector(')
    .replace(/Vec3d (\w+)/g, 'let $1')
    .replaceAll('Vec3d(', 'new Vector(')
    .replaceAll('move.aimUpCopy - tmp * tmp.dot(move.aimUpCopy)',
      'subtract(move.aimUpCopy, scale(tmp, tmp.dot(move.aimUpCopy)))')
    .replace('vertical * std::cos(roll) + lateral * std::sin(roll)',
      'add(scale(vertical, Math.cos(roll)), scale(lateral, Math.sin(roll)))')
    .replace(/StelUtils::rectToSphe\(&(\w+), &(\w+), (\w+)\);/g, '[$1, $2] = rectToSphe($3);')
    .replace('StelUtils::spheToRect(ra_now, de_now, tmp);', 'tmp = spheToRect(ra_now, de_now);')
    .replaceAll('std::isfinite', 'Number.isFinite')
    .replaceAll('std::hypot', 'Math.hypot')
    .replaceAll('std::remainder', 'remainder')
    .replaceAll('std::atan', 'Math.atan')
    .replaceAll('std::sin', 'Math.sin')
    .replaceAll('std::cos', 'Math.cos')
    .replaceAll('fabs(', 'Math.abs(')
    .replaceAll('powf(', 'Math.pow(')
    .replaceAll('M_PI', 'Math.PI');
}
const step = new Function('state', 'Vector', 'subtract', 'scale', 'rectToSphe', 'spheToRect', 'add',
  `with (state) { ${translate(nativeStep)} }`);

function harness(startAltitude, targetAltitude, { azimuth = 240, duration = 3, up, startRoll = 0, zoomingMode = 0, mountMode = 0 } = {}) {
  const angle = radians(azimuth);
  const rotation = [[.36, -.8, .48], [.48, .6, .64], [-.8, 0, .6]];
  const rotate = value => vector(rotation.map(row => vector(row).dot(value)));
  const inverse = value => vector(rotation[0].map((_, column) => rotation.reduce((sum, row, index) => sum + row[column] * value[index], 0)));
  const initialUp = add(scale(tangent(angle, radians(startAltitude)), Math.cos(radians(startRoll))),
    scale(new Vector(-Math.sin(angle), Math.cos(angle), 0), Math.sin(radians(startRoll))));
  const state = {
    MountAltAzimuthal: 0, ZoomIn: 1, ZoomOut: 2, zoomingMode,
    deltaTime: 0, flagAutoMove: true,
    viewDirectionMountFrame: spheToRect(angle, radians(startAltitude)),
    upVectorMountFrame: initialUp,
    move: {
      coef: 0, speed: 1 / (duration * 1000), mountMode,
      start: spheToRect(angle, radians(startAltitude)),
      aim: scale(spheToRect(angle, radians(targetAltitude)), 2),
      aimUpCopy: up ?? tangent(angle, radians(targetAltitude)),
      startUp: vector(initialUp),
      targetObject: { isNull: () => true }
    },
    mountFrameToJ2000: rotate,
    remainder(value, period) {
      return value > period / 2 ? value - period : value < -period / 2 ? value + period : value;
    },
    j2000ToMountFrame: inverse,
    getViewUpVectorJ2000() { return rotate(this.upVectorMountFrame); },
    setViewUpVectorJ2000(value) { this.upVectorMountFrame = inverse(value); },
    setViewUpVector(value) { this.upVectorMountFrame = vector(value); },
    setViewDirectionJ2000(value) {
      this.viewDirectionMountFrame = inverse(value).normalize();
      this.upAtLookAt = vector(this.upVectorMountFrame).normalize();
      this.sideAtLookAt = cross(this.viewDirectionMountFrame, this.upAtLookAt);
    }
  };
  state.tick = seconds => {
    state.deltaTime = seconds;
    step(state, Vector, subtract, scale, rectToSphe, spheToRect, add);
  };
  return state;
}

function assertBasis(state) {
  assert.ok(state.viewDirectionMountFrame.every(Number.isFinite));
  assert.ok(state.upAtLookAt.every(Number.isFinite));
  assert.ok(state.sideAtLookAt.normSquared() > .999999, 'camera side must retain unit length before normalization');
  assert.ok(Math.abs(state.viewDirectionMountFrame.dot(state.upAtLookAt)) < 1e-10, 'up must be perpendicular before lookAt');
}

for (const targetAltitude of [90, -90]) {
  for (const seconds of [3, 4]) {
    test(`animated ${targetAltitude} final frame after ${seconds}s does not use previous-frame pole detection`, () => {
      const state = harness(0, targetAltitude);
      state.tick(seconds);
      assertBasis(state);
      assert.equal(state.flagAutoMove, false);
      assert.ok(Math.abs(state.viewDirectionMountFrame[2] - Math.sign(targetAltitude)) < 1e-12);
    });
  }
  test(`animated ${targetAltitude} stays safe across irregular frames and a final large step`, () => {
    const state = harness(-targetAltitude, targetAltitude);
    for (const seconds of [0, .016, .033, .2, .8, .45, 2]) {
      state.tick(seconds);
      assertBasis(state);
    }
    assert.equal(state.flagAutoMove, false);
  });
  test(`zoom-in reaching ${targetAltitude} before animation completion has a valid basis`, () => {
    const state = harness(0, targetAltitude, { zoomingMode: 1 });
    state.tick(2.8);
    assertBasis(state);
    assert.equal(state.flagAutoMove, true);
    assert.ok(Math.abs(state.viewDirectionMountFrame[2] - Math.sign(targetAltitude)) < 1e-12);
  });
}

test('animated explicit roll survives the final frame at both poles and away from poles', () => {
  for (const altitude of [90, -90, 40]) {
    const up = new Vector(-Math.sin(radians(240)), Math.cos(radians(240)), 0);
    const state = harness(0, altitude, { up });
    state.tick(3);
    assertBasis(state);
    assert.ok(state.upAtLookAt.dot(up) > .999999);
  }
});

test('native AltAz callers supplying parallel or nonfinite final up retain the tangent fallback', () => {
  for (const altitude of [-90, 90]) {
    for (const up of [new Vector(0, 0, 1), new Vector(0, 0, 0), new Vector(NaN, 0, 0)]) {
      const state = harness(0, altitude, { up });
      state.tick(4);
      assertBasis(state);
    }
  }
});

test('consecutive zenith, nadir and horizon animations remain well conditioned', () => {
  let altitude = -90;
  for (const target of [90, -90, 0, 89, -89, 90]) {
    const state = harness(altitude, target);
    for (const seconds of [.2, .7, .6, 1.5]) {
      state.tick(seconds);
      assertBasis(state);
    }
    altitude = target;
  }
});

test('non-AltAz animation retains the existing world-up path', () => {
  const state = harness(0, 35, { mountMode: 1 });
  state.tick(.5);
  assert.ok(state.upAtLookAt.dot(new Vector(0, 0, 1)) > .999999);
});

test('explicit target roll changes continuously, including the final frame at poles', () => {
  for (const altitude of [90, -90, 40]) {
    const angle = radians(240);
    const targetUp = new Vector(-Math.sin(angle), Math.cos(angle), 0);
    const state = harness(0, altitude, { up: targetUp });
    let previousRoll = 0;
    for (let frame = 0; frame <= 120; ++frame) {
      state.tick(frame === 0 ? 0 : 3 / 120);
      assertBasis(state);
      const currentAltitude = rectToSphe(state.viewDirectionMountFrame)[1];
      const roll = Math.atan2(state.upAtLookAt.dot(targetUp), state.upAtLookAt.dot(tangent(angle, currentAltitude)));
      assert.ok(roll >= previousRoll - 1e-10);
      assert.ok(roll - previousRoll < radians(3), 'roll must not snap on completion');
      previousRoll = roll;
    }
    assert.ok(state.upAtLookAt.dot(targetUp) > .999999);
  }
});

test('starting roll is retained and shortest-path interpolation crosses the 180-degree seam', () => {
  const angle = radians(240);
  const lateral = new Vector(-Math.sin(angle), Math.cos(angle), 0);
  const targetUp = add(scale(tangent(angle, radians(45)), Math.cos(radians(-170))), scale(lateral, Math.sin(radians(-170))));
  const state = harness(20, 45, { startRoll: 170, up: targetUp });
  const initialUp = vector(state.upVectorMountFrame);
  state.tick(0);
  assertBasis(state);
  assert.ok(initialUp.dot(state.upAtLookAt) > .999999, 'first frame must retain the initial roll');
  state.tick(1.5);
  assertBasis(state);
  assert.ok(state.upAtLookAt.dot(tangent(angle, radians(32.5))) < -.999999, 'short arc passes through 180, not zero');
  state.tick(1.5);
  assertBasis(state);
  assert.ok(state.upAtLookAt.dot(targetUp) > .999999);
});

test('horizontal up from a rolled non-pole view does not trigger pole departure', () => {
  const start = source.indexOf('void StelMovementMgr::moveToAltAzi');
  const setup = source.slice(start, source.indexOf('Vec3d StelMovementMgr::j2000ToMountFrame', start));
  assert.ok(setup.includes('move.startUp=currentUp;'));
  const condition = setup.match(/if \(([^\n]*currentUp\[2\][^\n]*)\)/)[1];
  const isPoleDeparture = new Function('move', 'currentUp', `return ${translate(condition)};`);
  assert.equal(isPoleDeparture({ start: spheToRect(0, radians(30)) }, new Vector(0, 1, 0)), false);
  assert.equal(isPoleDeparture({ start: spheToRect(0, radians(90)) }, new Vector(0, 1, 0)), true);
  assert.equal(isPoleDeparture({ start: spheToRect(0, radians(-90)) }, new Vector(0, 1, 0)), true);
});
