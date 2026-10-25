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
