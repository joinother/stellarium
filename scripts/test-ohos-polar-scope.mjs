import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const core = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
const page = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const overlay = readFileSync(new URL('../harmonyos/ets-source/panels/overlay/PolarScopeOverlay.ets', import.meta.url), 'utf8');
const geometry = readFileSync(new URL('../harmonyos/ets-source/common/derive/geometry.ets', import.meta.url), 'utf8');
const draw = core.slice(core.indexOf('void drawOhosPolarScopeOverlay'), core.indexOf('QString formatLx200Ra'));

test('reticle uses one uncompressed pixel radius and screen-space painting', () => {
  assert.match(draw, /const double scopeRadius = poleStarRadius/);
  assert.match(draw, /StelPainter painter\(core->getProjection2d\(\)\)/);
  assert.doesNotMatch(draw, /poleScreen.set|checkInViewport\(starScreen\)|qMin\(poleStarRadius/);
  assert.match(draw, /innerLabelRadius = scopeRadius - metrics.height/);
  assert.doesNotMatch(core, /ohosPolarScopeSafeRadius/);
});

test('labels are centred, spaced, culled at UI edges and avoid other labels', () => {
  assert.match(draw, /reticleFont.setPixelSize\(12\)/);
  assert.match(draw, /QFontMetrics metrics\(measuredFont\)/);
  assert.match(draw, /measuredFont.setPixelSize\(qMax\(1, qRound\(reticleFont.pixelSize\(\) \* projector->getDevicePixelsPerPixel\(\)\)\)\)/);
  assert.match(draw, /polarScopeLabelStep\(scopeRadius/);
  assert.match(draw, /labelBounds.contains\(bounds\)/);
  assert.match(draw, /occupied.intersects\(bounds\)/);
  assert.match(draw, /x - width \/ 2/);
  assert.match(draw, /getNameI18n\(\)/);
});

test('floating controls and manual hit routing share width and footer geometry', () => {
  assert.match(overlay, /width\(this\.controlWidth\)/);
  assert.match(overlay, /height\(this\.footerHeight\)/);
  assert.match(overlay, /id\('polar-scope-center'\)/);
  assert.match(overlay, /id\('polar-scope-close'\)/);
  assert.match(overlay, /ButtonType\.Circle/);
  assert.match(overlay, /hitTestBehavior\(HitTestMode\.BLOCK_HIERARCHY\)/);
  assert.match(overlay, /this\.onSkyTouch\(event\)/);
  assert.doesNotMatch(overlay, /HitTestMode\.Transparent|Blank\(\)/);
  assert.match(overlay, /y: this\.topInset/);
  assert.match(overlay, /y: this\.skyHeight - this\.footerHeight - 12/);
  assert.equal((overlay.match(/border\(\{ width: 1, color: 'rgba\(255,255,255,0.10\)' \}\)\s*\.hitTestBehavior\(HitTestMode\.Default\)/g) || []).length, 2);
  assert.doesNotMatch(overlay, /rgba\(3, 4, 7/);
  assert.match(page, /const right = \(this\.skyWidth \+ this\.polarScopeControlWidth\(\)\) \/ 2 - 6/);
  // The overlay geometry stays host-owned: the manual hit routing and the
  // floating control both read the same computed width / inset / footer.
  assert.match(page, /private polarScopeControlWidth\(\): number \{/);
  assert.match(page, /private polarScopeTopInset\(\): number \{/);
  assert.match(page, /private polarScopeFooterHeight\(\): number \{/);
  assert.match(page, /handleSkyTouch\(event\)/);
});

test('hidden shell does not intercept polar-scope sky gestures', () => {
  const uiHit = page.slice(page.indexOf('  private isUiPoint('), page.indexOf('  private handleUiTap('));
  assert.match(uiHit, /polarScopeFooterHeight\(\)[\s\S]*?return true\s*\}\s*return false/);
  const dockHit = geometry.slice(geometry.indexOf('export function isDockPoint('), geometry.indexOf('export function objectActionBarY('));
  assert.match(dockHit, /if \(polarScopeVisible\) return false/);
});
