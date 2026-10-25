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

test('every shell draws the Dock at the same supplied hit-test baseline', () => {
  for (const name of ['ExpandedShell', 'CompactShell', 'HoverObservatoryShell']) {
    const source = read(`../harmonyos/ets-source/panels/shell/${name}.ets`);
    assert.match(source, /y: this\.dockTop/);
    assert.doesNotMatch(source, /labelFontSize: this\.isExpandedLayout \? 10/);
  }
  const dock = read('../harmonyos/ets-source/panels/shell/BottomDock.ets');
  assert.doesNotMatch(dock, /\.scale\(|\.translate\(/);
});
