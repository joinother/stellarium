import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const app = read('src/core/StelApp.cpp');
const manager = read('src/core/StelTextureMgr.cpp');
const view = read('src/StelMainView.cpp');
const texture = read('src/core/StelTexture.cpp');

test('each initialized core draw resets its upload budget before any render pass', () => {
  const draw = app.match(/void StelApp::draw\(\)\r?\n\{[\s\S]*?\r?\n\}/)[0];
  assert.equal((draw.match(/textureMgr->beginFrame\(\)/g) ?? []).length, 1);
  assert.ok(draw.indexOf('return;') < draw.indexOf('textureMgr->beginFrame()'));
  assert.ok(draw.indexOf('textureMgr->beginFrame()') < draw.indexOf('prepareRenderBuffer()'));
  assert.ok(draw.indexOf('textureMgr->beginFrame()') < draw.indexOf('highGraphicsModeDraw()'));
});

test('upload budget does not depend on a desktop window frame-finished signal', () => {
  assert.doesNotMatch(manager, /StelMainView::frameFinished|onFrameFinished/);
  assert.match(manager, /void StelTextureMgr::beginFrame\(\)\s*\{\s*totalLoadTimeTaken = 0;\s*\}/);
  assert.match(manager, /totalLoadTimeTaken \+= textureLoadTimer.nsecsElapsed\(\)/);
});

test('both window and independent HarmonyOS render paths use core draw', () => {
  assert.ok((view.match(/app\.draw\(\)/g) ?? []).length >= 2);
  const pumpDraw = view.lastIndexOf('app.draw();');
  assert.ok(view.indexOf('submitOhosFramebuffer(gl)', pumpDraw) > pumpDraw);
});

test('fix retains per-frame upload limit and full-resolution image inputs', () => {
  assert.match(texture, /!prioritizeUpload && textureMgr->getTotalLoadTimeTaken\(\) > maxTimeNS/);
  assert.match(texture, /glLoad\(loader->result\(\)\)/);
  assert.match(manager, /tex->loadParams = params/);
});
