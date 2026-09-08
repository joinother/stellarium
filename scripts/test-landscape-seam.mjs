import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../src/core/modules/Landscape.cpp', import.meta.url), 'utf8');
const shader = source.slice(source.indexOf('void LandscapeOldStyle::draw('), source.indexOf('void LandscapeOldStyle::drawFog('));
const round = Math.fround;
const fullTurn = round(2 * round(Math.PI));
function coordinate(angle, count) {
  const turns = round(round(angle) / fullTurn);
  const position = round(round(turns - Math.floor(turns)) * count);
  const index = Math.min(Math.trunc(position), count - 1);
  return { index, fraction: Math.min(1, Math.max(0, round(position - index))) };
}

test('old integer side selection can escape the panorama at the wrap', () => {
  const angle = round(-1e-8);
  const oldAzimuth = round(angle + fullTurn);
  assert.equal(Math.trunc(round(oldAzimuth / round(fullTurn / 8))), 8);
  assert.ok(coordinate(angle, 8).index < 8);
});

test('all side boundaries and both sides of zero stay in range', () => {
  for (const count of [1, 2, 4, 7, 8, 9, 16, 31, 64]) {
    for (let boundary = -count; boundary <= count; boundary++) {
      for (const offset of [-1e-5, -1e-8, 0, 1e-8, 1e-5]) {
        const result = coordinate(boundary * 2 * Math.PI / count + offset, count);
        assert.ok(result.index >= 0 && result.index < count);
        assert.ok(result.fraction >= 0 && result.fraction <= 1);
      }
    }
  }
});

test('side coordinates agree with expected interior position', () => {
  for (const count of [4, 8, 9, 16]) {
    for (let side = 0; side < count; side++) {
      for (const fraction of [.1, .5, .9]) {
        let angle = (side + fraction) * 2 * Math.PI / count;
        if (angle > Math.PI) angle -= 2 * Math.PI;
        const result = coordinate(angle, count);
        assert.equal(result.index, side);
        assert.ok(Math.abs(result.fraction - fraction) < 1e-5);
      }
    }
  }
});

test('native shader keeps angular arithmetic and derivatives seam safe', () => {
  assert.ok(shader.indexOf('precision highp float;') < shader.indexOf('prj->getUnProjectShader()'));
  assert.match(shader, /fract\(atan\(viewDir\.x, viewDir\.y\)\/\(2\.\*PI\)\)/);
  assert.match(shader, /min\(int\(sidePosition\), totalNumberOfSides-1\)/);
  assert.match(shader, /dFdx\(texCoordInUnitRange\) \* deltaT/);
  assert.match(shader, /max\(dot\(modelPos\.xy, modelPos\.xy\), 1e-12\)/);
  assert.doesNotMatch(shader, /int\(azimuth\/sideAngularWidth\)/);
});
