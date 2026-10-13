import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

// The Dock now splits into the host width helper (MainWindowNativeNode.ets)
// and the shell components (panels/shell/BottomDock.ets + DockButton.ets).
const page = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const bottomDock = readFileSync(new URL('../harmonyos/ets-source/panels/shell/BottomDock.ets', import.meta.url), 'utf8');
const dockButton = readFileSync(new URL('../harmonyos/ets-source/panels/shell/DockButton.ets', import.meta.url), 'utf8');
const widthMethod = page.slice(page.indexOf('private compactDockWidthPercent()'), page.indexOf('private compactDockLabelFontSize()'));

test('phone Dock width is stable when a panel opens', () => {
  assert.doesNotMatch(widthMethod, /this\.panelVisible \?/);
  assert.match(widthMethod, /targetWidth = Math\.min\(420, Math\.max\(288, width - 48\)\)/);
  assert.match(widthMethod, /return clamp\(targetWidth \* 100 \/ width, 82, 92\)/);
  assert.match(bottomDock, /this\.widthPercent \+ '%'/);
});

test('Dock buttons keep feedback without a large press shrink', () => {
  assert.match(dockButton, /\.scale\(\{ x: 0\.97, y: 0\.97 \}\)/);
  assert.doesNotMatch(dockButton, /\.scale\(\{ x: 0\.92, y: 0\.92 \}\)/);
});
