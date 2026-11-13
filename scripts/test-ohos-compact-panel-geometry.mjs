import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const page = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
function method(name, parameters = '') {
  const body = page.match(new RegExp(`  private ${name}\\([^)]*\\): number \\{([\\s\\S]*?)\\n  \\}`))?.[1];
  assert.ok(body, name);
  return new Function('clamp', `return function(${parameters}) {${body.replace(/const (\w+): number/g, 'const $1')}}`)(clamp);
}

test('compact sheets share the Dock baseline across short windows and safe insets', () => {
  for (const height of [320, 400, 469, 600, 900]) {
    for (const inset of [0, 24, 40]) {
      const host = {
        skyHeight: height, isFoldHoverLayout: false, compactPanelSnapRatio: 0.9,
        compactPanelDragOffsetY: -80, activePanel: 'search',
        dockHeight: () => 66, dockBottomClearance: () => inset + 30,
        scriptControlSafeTop: () => 24,
        dockTop: method('dockTop'), compactPanelBottom: method('compactPanelBottom'),
        compactPanelTop: method('compactPanelTop'), compactPanelHeight: method('compactPanelHeight'),
        compactPanelUsableHeight: method('compactPanelUsableHeight')
      };
      assert.equal(host.compactPanelTop() + host.compactPanelHeight(), host.dockTop() - 10);
      assert.ok(host.compactPanelTop() >= 8);
    }
  }
  assert.doesNotMatch(page, /this\.skyHeight - 90/);
  assert.match(page, /\.position\(\{ x: 0, y: this\.compactPanelTop\(\) \}\)/);
});

test('compact time sheet stops at the speed-chip row on phones', () => {
  const host = {
    activePanel: 'time', compactPanelSnapRatio: 0.9, compactPanelDragOffsetY: -80,
    timeSpeedBlockHeight: 240,
    timeStore: { panelSubtitle: () => '2026-11-13 08:30' },
    compactPanelUsableHeight: () => 600,
    timePanelSpeedHeight: method('timePanelSpeedHeight', 'usable, verticalPadding'),
    compactPanelHeight: method('compactPanelHeight')
  };
  // top padding + handle + header + header gap + measured content + bottom padding
  assert.equal(host.compactPanelHeight(), 12 + 30 + 56 + 14 + 240 + 16);
  // Before the first layout pass, keep the previous 0.6 fallback.
  host.timeSpeedBlockHeight = 0;
  assert.equal(host.compactPanelHeight(), 360);
  // The row below the speed chips must not enlarge the sheet; content scrolls.
  host.timeSpeedBlockHeight = 240;
  host.compactPanelSnapRatio = 0.9;
  host.compactPanelDragOffsetY = -1000;
  assert.equal(host.compactPanelHeight(), 12 + 30 + 56 + 14 + 240 + 16);
  // Tablet uses the same helper; only its outer vertical padding differs.
  assert.equal(host.timePanelSpeedHeight(600, 18 + 18), 18 + 30 + 56 + 14 + 240 + 18);
});

test('the More sheet opens raised and keeps its height for subpanels', () => {
  assert.match(page, /const preserveMorePanelHeight = this\.panelVisible && panelRouteRoot\(currentPanel\) === 'more' &&[\s\S]{0,40}panelRouteRoot\(panel\) === 'more'/);
  assert.match(page, /if \(panel === 'more'\) \{\s*this\.compactPanelSnapRatio = 0\.9/);
  assert.match(page, /else if \(!preserveMorePanelHeight\) \{\s*this\.compactPanelSnapRatio = 0\.6/);
});

test('expanded object details and dragging cannot cover the compact Dock', () => {
  for (const height of [320, 400, 469, 600]) {
    for (const offset of [-1000, 0, 1000]) {
      const host = {
        skyHeight: height, isExpandedLayout: false, isFoldHoverLayout: false,
        cardOffsetY: offset, infoWindowStore: { observeCompact: () => false },
        scriptControlSafeTop: () => 24, compactPanelBottom: () => height - 106,
        bottomCardHeight: method('bottomCardHeight'),
        clampedObjectCardOffsetY: method('clampedObjectCardOffsetY', 'base, height')
      };
      const cardHeight = host.bottomCardHeight();
      const top = 24 + host.clampedObjectCardOffsetY(24, cardHeight);
      assert.ok(top >= 24);
      assert.ok(top + cardHeight <= host.compactPanelBottom());
    }
  }
});
