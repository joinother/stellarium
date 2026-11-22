import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const geometry = read('../harmonyos/ets-source/common/ui/DockGeometry.ets');
const dockItemIndex = new Function(`${geometry.replace('export ', '').replace(/: number/g, '')}; return dockItemIndex;`)();

test('all five Dock buttons remain reachable across local sizes and padded edges', () => {
  for (const width of [288, 360, 520, 720]) {
    for (const height of [66, 72, 78]) {
      for (const padding of [8, 12]) {
        const itemWidth = (width - 2 * padding) / 5;
        for (let index = 0; index < 5; index++) {
          for (const fraction of [0.1, 0.5, 0.9]) {
            const localX = padding + itemWidth * (index + fraction);
            for (const localY of [1, height / 2, height - 1]) {
              assert.equal(dockItemIndex(localX, localY, width, height, 5, padding), index);
            }
          }
        }
        for (const [localX, localY] of [[0, 20], [width, 20], [width / 2, -1], [width / 2, height + 1]]) {
          assert.equal(dockItemIndex(localX, localY, width, height, 5, padding), -1);
        }
      }
    }
  }
});

test('top-level pointer hit surface uses local coordinates without duplicate click activation', () => {
  const page = read('../harmonyos/ets-source/pages/MainWindowNativeNode.ets');
  assert.match(page, /handleDockTouch\(event, true\)/);
  assert.match(page, /activateDockAtLocal\(points\[0\]\.x, points\[0\]\.y\)/);
  assert.doesNotMatch(page, /onClick\(\(event: ClickEvent\) => \{ this\.activateDockAtLocal\(event\.x, event\.y\)/);
  assert.match(page, /event\.stopPropagation\(\)/);
});

test('Dock memory never restores a panel from another Dock entry', () => {
  const page = read('../harmonyos/ets-source/pages/MainWindowNativeNode.ets');
  const actions = read('../harmonyos/ets-source/common/derive/actions.ets');
  const routeRootSource = actions
    .match(/export function panelRouteRoot[\s\S]*?\n\}/)[0]
    .replace('export ', '')
    .replace(/: string/g, '');
  const panelRouteRoot = new Function(`${routeRootSource}; return panelRouteRoot;`)();

  // Reported cases: More → Settings → sky layers, and Quick title → Place.
  // Layers belongs to the Layers entry and Place to More, so neither may be
  // restored under the entry that happened to open it.
  assert.equal(panelRouteRoot('layers'), 'layers');
  assert.equal(panelRouteRoot('place'), 'more');
  assert.notEqual(panelRouteRoot('layers'), 'more');
  assert.notEqual(panelRouteRoot('place'), 'quick');

  // The visible panel decides the Dock owner; the navigation stack can still
  // point at the entry that opened a cross-domain subpage.
  assert.match(page, /if \(this\.activePanel\.length > 0\) return panelRouteRoot\(this\.activePanel\)/);
  assert.match(page, /stackRoot\.length === 0 \|\| stackRoot === owner/);
  assert.match(page, /panelRouteRoot\(saved\.activePanel\) === item\.panel/);
  assert.match(page, /if \(saved !== undefined\) this\.dockPanelMemory\.delete\(item\.panel\)/);
});

test('every shell draws the Dock at the same supplied hit-test baseline', () => {
  for (const name of ['ExpandedShell', 'CompactShell', 'HoverObservatoryShell']) {
    const source = read(`../harmonyos/ets-source/panels/shell/${name}.ets`);
    assert.match(source, /y: this\.dockTop/);
    assert.doesNotMatch(source, /labelFontSize: this\.isExpandedLayout \? 10/);
  }
  const dock = read('../harmonyos/ets-source/panels/shell/BottomDock.ets');
  assert.doesNotMatch(dock, /\.scale\(|\.translate\(/);
});
