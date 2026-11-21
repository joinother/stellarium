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

test('compact time sheet stops exactly at the speed-chip row on phones', () => {
  const host = {
    activePanel: 'time', compactPanelSnapRatio: 0.9, compactPanelDragOffsetY: -80,
    timeSpeedBlockHeight: 240,
    timeStore: { panelSubtitle: () => '2026-11-13 08:30' },
    compactPanelUsableHeight: () => 600,
    panelTopChromeHeight: (isCompact) => (isCompact ? 12 : 18) + 30 + 54 + 10,
    timePanelSpeedHeight: method('timePanelSpeedHeight', 'usable, isCompact'),
    compactPanelHeight: method('compactPanelHeight')
  };
  // Actual chrome height + measured block + 8vp margin of the next chips row.
  assert.equal(host.compactPanelHeight(), 12 + 30 + 54 + 10 + 240 + 8);
  // Before the first layout pass, keep the previous 0.6 fallback.
  host.timeSpeedBlockHeight = 0;
  assert.equal(host.compactPanelHeight(), 360);
  // The row below the speed chips must not enlarge the sheet; content scrolls.
  host.timeSpeedBlockHeight = 240;
  host.compactPanelSnapRatio = 0.9;
  host.compactPanelDragOffsetY = -1000;
  assert.equal(host.compactPanelHeight(), 12 + 30 + 54 + 10 + 240 + 8);
  // Tablet uses the same helper with the floating sheet's 18vp bottom padding.
  assert.equal(host.timePanelSpeedHeight(600, false), 18 + 30 + 54 + 10 + 240 + 18);
});

test('the More sheet opens raised and fits its measured content', () => {
  assert.match(page, /const preserveMorePanelHeight = this\.panelVisible && panelRouteRoot\(currentPanel\) === 'more' &&[\s\S]{0,40}panelRouteRoot\(panel\) === 'more'/);
  assert.match(page, /if \(panel === 'more'\) \{\s*this\.compactPanelSnapRatio = 0\.9/);
  assert.match(page, /else if \(!preserveMorePanelHeight\) \{\s*this\.compactPanelSnapRatio = 0\.6/);
  const host = {
    activePanel: 'more', compactPanelSnapRatio: 0.9, compactPanelDragOffsetY: 0,
    morePanelContentHeight: 420, compactPanelUsableHeight: () => 600,
    panelTopChromeHeight: () => 96,
    compactPanelHeight: method('compactPanelHeight')
  };
  assert.equal(host.compactPanelHeight(), 96 + 420);
  // Before the list reports its height, keep the raised 0.9 fallback.
  host.morePanelContentHeight = 0;
  assert.equal(host.compactPanelHeight(), 540);
  assert.doesNotMatch(page, /activePanel === 'more'\) return 0/);
  assert.match(page, /if \(this\.activePanel === 'time'\) return 20[\s\S]{0,160}return 50/);
  const morePanel = readFileSync(new URL('../harmonyos/ets-source/panels/panels/MorePanel.ets', import.meta.url), 'utf8');
  assert.match(morePanel, /onContentHeight: \(height: number\) => void/);
  assert.match(morePanel, /this\.onContentHeight\(height\)/);
  assert.doesNotMatch(morePanel, /padding\(\{ bottom: 12 \}\)/);
  assert.match(page, /onContentHeight: \(height: number\) => \{[\s\S]{0,120}morePanelContentHeight = height/);
});

test('all Settings tabs share the host panel scroll', () => {
  const settings = readFileSync(new URL('../harmonyos/ets-source/panels/panels/SettingsPanel.ets', import.meta.url), 'utf8');
  assert.doesNotMatch(settings, /Scroll\(this\.contentScroller\)/);
  assert.doesNotMatch(settings, /Scroll\(this\.scroller\)/);
  assert.doesNotMatch(settings, /\.scrollable\(ScrollDirection\.Vertical\)/);
  assert.match(settings, /\.height\('auto'\)/);
  assert.match(settings, /\.layoutWeight\(0\)/);
  assert.match(settings, /onRequestScrollTop: \(\) => void/);
  assert.match(settings, /this\.onRequestScrollTop\(\)/);
  assert.match(settings, /else if \(this\.configTab === 8\) \{[\s\S]{0,120}AboutSection\(/);
  const labels = readFileSync(new URL('../harmonyos/ets-source/common/derive/labels.ets', import.meta.url), 'utf8');
  assert.match(labels, /if \(configTab === 8\) return I18n\.t\('c_about'\)/);
  assert.match(page, /onRequestScrollTop: \(\) => \{ this\.resetActivePanelScroll\(\) \}/);
  assert.match(page, /private resetActivePanelScroll\(\): void/);
});

test('Settings drops redundant tools and scripts tabs and More lists Settings before Tools', () => {
  const settings = readFileSync(new URL('../harmonyos/ets-source/panels/panels/SettingsPanel.ets', import.meta.url), 'utf8');
  assert.doesNotMatch(settings, /\{ label: I18n\.t\('c0004'\), id: 4 \}/);
  assert.doesNotMatch(settings, /configTab === 4/);
  assert.doesNotMatch(settings, /\{ label: I18n\.t\('c0005'\), id: 5 \}/);
  assert.doesNotMatch(settings, /configTab === 5/);
  assert.doesNotMatch(settings, /scriptTabContent/);
  const actions = readFileSync(new URL('../harmonyos/ets-source/common/derive/actions.ets', import.meta.url), 'utf8');
  const more = actions.slice(actions.indexOf('export function moreActions'), actions.indexOf('export function observingHubActions'));
  const settingsIndex = more.indexOf("panel: 'settings'");
  const toolsIndex = more.indexOf("panel: 'tools'");
  assert.ok(settingsIndex >= 0, 'settings entry');
  assert.ok(toolsIndex > settingsIndex, 'settings before tools');
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
