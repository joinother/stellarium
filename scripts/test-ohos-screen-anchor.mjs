import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import test from 'node:test';

const root = new URL('../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const source = readFileSync(join(root, 'src/StelMainView.cpp'), 'utf8');
const section = (begin, end) => source.slice(source.indexOf(begin), source.indexOf(end, source.indexOf(begin)));

test('new native selections enable fixed position without taking control from scripts', () => {
  const handler = section('connect(&stelApp->getStelObjectMgr(), &StelObjectMgr::selectedObjectChanged', '//this makes sure');
  assert.match(handler, /scriptIsRunning\(\).*return/);
  assert.match(handler, /s_viewLock = !stelApp->getStelObjectMgr\(\).getSelectedObject\(\).isEmpty\(\)/);
  assert.match(handler, /ohosCaptureSelectedZoomAnchor\(\)/);
  assert.doesNotMatch(handler, /moveToObject|zoomTo/);
  assert.match(section('QJsonObject selectedObjectJson(', 'const QString infoMode'), /result\["viewLock"\] = s_viewLock/);
});

test('pinch uses the displayed FOV, cancels previous zoom and never replays the old aim', () => {
  const pinch = section('if (commandName == "zoomBy")', 'if (commandName == "endPinch")');
  assert.match(pinch, /movementMgr->cancelAutoZoom\(\)/);
  assert.match(pinch, /s_ohosPinchStartFov = movementMgr->getCurrentFov\(\)/);
  assert.match(pinch, /setFov\(s_ohosPinchStartFov \/ scale\)/);
  assert.doesNotMatch(pinch, /handlePinch|getAimFov/);
});

test('release is finalized after this frame corrects its anchor', () => {
  const end = section('if (commandName == "endPinch")', 'if (commandName == "getSelectedObjectInfo")');
  assert.match(end, /s_ohosPinchEndPending = s_ohosPinchActive/);
  assert.doesNotMatch(end, /ohosCaptureSelectedZoomAnchor|ohosMaintain|s_ohosCaptureSelectedAnchorAfterPan = true/);
  const frame = section('void StelMainView::renderOhosFrameNow()', 'void StelMainView::initTitleI18n()');
  assert.ok(frame.indexOf('ohosUpdatePinchSettle(dt)') < frame.indexOf('app.update(dt)'));
  assert.ok(frame.indexOf('app.update(dt)') < frame.indexOf('ohosMaintainPinchSkyAnchor()'));
  assert.ok(frame.indexOf('ohosMaintainSelectedZoomAnchor()') < frame.indexOf('if (s_ohosPinchEndPending)'));
  assert.match(frame, /qBound\(-1\.5, s_ohosPinchSettleVelocity, 1\.5\)/);
});

test('off-target zoom hands back the final position, not the pre-gesture position', () => {
  const maintain = section('static void ohosMaintainPinchSkyAnchor()', 'static void ohosDeferSelectedAnchor');
  assert.ok(maintain.indexOf('ohosAnchorSkyDirection(') < maintain.indexOf('ohosCaptureSelectedZoomAnchor()'));
  const anchor = section('static void ohosAnchorSkyDirection(', 'static void ohosBeginPinchAnchor(');
  assert.match(anchor, /params.fov = static_cast<float>\(movementMgr->getCurrentFov\(\)\)/);
  assert.doesNotMatch(anchor, /dragView|qRound|panView|app.update/);
  assert.match(anchor, /FrameAltAz, StelCore::RefractionOff/);
  assert.match(anchor, /j2000ToAltAz\(directionJ2000, StelCore::RefractionAuto\)/);
});

test('native rotation preserves off-center coordinates across rapid extreme zooms', (context) => {
  const qt = process.env.QT_HOST_PATH ?? '/Users/jiexuanyang/Qt/6.12.0/macos';
  if (!existsSync(join(qt, 'lib/QtCore.framework/Headers/QtGlobal'))) {
    context.skip('Qt host headers are required for the native numerical test');
    return;
  }
  const rotate = source.match(/const auto rotate = \[&rotationAxis, cosine\]\(const Vec3d& vector\) \{[\s\S]*?\n\t\};/)[0];
  const directory = mkdtempSync(join(tmpdir(), 'stellarium-anchor-test-'));
  try {
    writeFileSync(join(directory, 'anchor.cpp'), `
#include "VecMath.hpp"
#include <cassert>
#include <iostream>
Vec3d applyRotation(Vec3d desired, Vec3d target, Vec3d value) {
  desired.normalize(); target.normalize();
  const double cosine = desired.dot(target);
  const Vec3d rotationAxis = desired ^ target;
  ${rotate}
  return rotate(value);
}
int main() {
  int cases = 0;
  for (double oldFov : {150., 90., 30., 1., 0.01}) {
    for (double newFov : {150., 60., 5., 0.1, 0.001}) {
      for (double horizontal : {-0.7, 0., 0.7}) {
        for (double vertical : {-0.6, 0., 0.6}) {
          const double oldScale = std::tan(oldFov * M_PI / 360.);
          const double newScale = std::tan(newFov * M_PI / 360.);
          Vec3d target(horizontal * oldScale, vertical * oldScale, 1.);
          Vec3d desired(horizontal * newScale, vertical * newScale, 1.);
          target.normalize(); desired.normalize();
          const Vec3d forward = applyRotation(desired, target, Vec3d(0., 0., 1.));
          const Vec3d up = applyRotation(desired, target, Vec3d(0., 1., 0.));
          const Vec3d right = applyRotation(desired, target, Vec3d(1., 0., 0.));
          const double depth = target.dot(forward);
          assert(depth > 0.);
          assert(std::abs(target.dot(right) / depth / newScale - horizontal) < 1e-8);
          assert(std::abs(target.dot(up) / depth / newScale - vertical) < 1e-8);
          assert(std::abs(up.dot(forward)) < 1e-12);
          assert(std::abs(forward.normSquared() - 1.) < 1e-12);
          const Vec3d reverse = applyRotation(target, desired, forward);
          assert((reverse - Vec3d(0., 0., 1.)).normSquared() < 1e-20);
          ++cases;
        }
      }
    }
  }
  std::cout << cases << " native rotation cases passed\\n";
}
`);
    execFileSync('clang++', ['-std=c++17', '-I', join(root, 'src/core'), '-F', join(qt, 'lib'),
      '-I', join(qt, 'lib/QtCore.framework/Headers'), '-I', join(qt, 'lib/QtGui.framework/Headers'),
      '-framework', 'QtCore', '-framework', 'QtGui', '-Wl,-rpath,' + join(qt, 'lib'),
      join(directory, 'anchor.cpp'), '-o', join(directory, 'anchor')], { encoding: 'utf8' });
    assert.match(execFileSync(join(directory, 'anchor'), { encoding: 'utf8' }), /225 native rotation cases passed/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
