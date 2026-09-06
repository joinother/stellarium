import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/DetailModelGeometry.ets', import.meta.url), 'utf8');
const geometry = await import('data:text/javascript,' + encodeURIComponent(source.replace(/: number\[\]|: number/g, '')));
const { modelIdentity, modelMultiply, modelVector, modelDrag } = geometry;
const transpose = matrix => [matrix[0], matrix[3], matrix[6], matrix[1], matrix[4], matrix[7], matrix[2], matrix[5], matrix[8]];
const dot = (left, right) => left.reduce((sum, value, index) => sum + value * right[index], 0);
const near = (actual, expected) => actual.forEach((value, index) => assert.ok(Math.abs(value - expected[index]) < 1e-10));

test('visible surface follows all four screen drag directions', () => {
  for (const [deltaX, deltaY] of [[30, 0], [-30, 0], [0, 30], [0, -30]]) {
    const view = modelDrag(modelIdentity(), deltaX, deltaY);
    const point = modelVector(transpose(view), [0, 0, 1]);
    if (deltaX) assert.ok(point[0] * deltaX > 0);
    if (deltaY) assert.ok(-point[1] * deltaY > 0);
  }
});

test('vertical orbit is not limited at poles and can complete a turn', () => {
  near(modelDrag(modelIdentity(), 0, 2 * Math.PI / 0.008), modelIdentity());
  const upsideDown = modelDrag(modelIdentity(), 0, Math.PI / 0.008);
  near(modelVector(upsideDown, [0, 1, 0]), [0, -1, 0]);
});

test('incremental screen drag follows the finger after arbitrary previous rotations', () => {
  const initial = modelDrag(modelDrag(modelIdentity(), 137, -98), -39, 58);
  const centerSurface = modelVector(initial, [0, 0, 1]);
  const rotated = modelDrag(initial, 0, -20);
  const screen = modelVector(transpose(rotated), centerSurface);
  assert.ok(screen[1] > 0);
});

test('body-fixed light follows the texture, not a screen mask', () => {
  const sun = [1, 0, 0];
  const point = [0.8, 0, 0.6];
  const initialBrightness = dot(point, sun);
  const rotation = modelDrag(modelIdentity(), 80, -40);
  const screenPoint = modelVector(transpose(rotation), point);
  const reconstructed = modelVector(rotation, screenPoint);
  assert.ok(Math.abs(dot(reconstructed, sun) - initialBrightness) < 1e-10);
  assert.ok(Math.abs(dot(screenPoint, sun) - initialBrightness) > 0.1);
  assert.notEqual(dot(modelVector(rotation, [0, 0, 1]), sun), dot([0, 0, 1], sun));
});

test('many touch updates retain a proper rotation and sphere shape', () => {
  let rotation = modelIdentity();
  for (let step = 0; step < 10000; step++) rotation = modelDrag(rotation, 2 * Math.sin(step), Math.cos(step));
  near(modelMultiply(rotation, transpose(rotation)), modelIdentity());
});

test('rings stay in body equatorial plane under the same view matrix', () => {
  const transform = modelDrag(modelIdentity(), 60, 55);
  const screenX = 1.3;
  const screenY = 0.2;
  const screenZ = -(transform[3] * screenX + transform[4] * screenY) / transform[5];
  assert.ok(Math.abs(modelVector(transform, [screenX, screenY, screenZ])[1]) < 1e-12);
});

test('render integration uses physical vectors, original resolution and a throttled refresh', () => {
  const ui = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
  const rasterizer = readFileSync(new URL('../harmonyos/ets-source/pages/DetailModelRasterizer.ets', import.meta.url), 'utf8');
  assert.match(rasterizer, /objectX \* lightX \+ objectY \* lightY \+ objectZ \* lightZ/);
  assert.doesNotMatch(ui, /objectInspectorModelIllumination|ModelPitch - deltaY/);
  assert.match(ui, /highQuality \? \(immersive \? 640 : 320\) : 224/);
  assert.match(ui, /const immersive = this\.objectInspectorModelImmersive/);
  assert.match(ui, /immersive: immersive/);
  assert.match(ui, /LastRenderTime >= 250/);
  assert.match(ui, /this\.objectInspectorModelTouchCount !== points.length/);
  const native = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
  assert.match(native, /getObserverHeliocentricEclipticPos\(\) - center/);
  assert.match(native, /getRotEquatorialToVsop87\(\)/);
  assert.match(native, /Vec3d\(local\[0\], local\[2\], -local\[1\]\)/);
});
