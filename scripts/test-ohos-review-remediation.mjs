import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../harmonyos/ets-source/', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');
const page = read('pages/MainWindowNativeNode.ets');
const resources = read('qability/StellariumResourceBootstrap.ets');
const plain = source => stripTypeScriptTypes(source.replace(/^import [^\n]*\r?\n/gm, '').replaceAll('export ', ''));

function layout(expanded, height, bottomPixels, density) {
  const names = ['isLargeDesktopCanvas', 'dockHeight', 'dockBottomClearance', 'dockTop', 'compactPanelBottom', 'compactPanelUsableHeight'];
  const methods = names.map(name => {
    const match = page.match(new RegExp(`  private ${name}\\([^\\n]*\\n[\\s\\S]*?\\n  \\}`));
    assert.ok(match, name);
    return match[0];
  }).join('\n');
  const Layout = new Function(plain(`class Layout { ${methods} };`) + ';return Layout;')();
  return Object.assign(new Layout(), {
    isExpandedLayout: expanded, isFoldHoverLayout: false, skyWidth: expanded ? 1280 : 390, skyHeight: height,
    screenSafeBottomPixels: bottomPixels, getUIContext: () => ({ px2vp: value => value / density })
  });
}

test('Dock reserves navigation height and 28vp after the existing 2vp idle translation', () => {
  for (const height of [360, 673, 800, 1200]) {
    for (const expanded of [false, true]) {
      for (const density of [1, 1.5, 2, 3]) {
        for (const inset of [0, 24, 72]) {
          const view = layout(expanded, height, inset, density);
          const paintedBottom = view.dockTop() + view.dockHeight() + 2;
          assert.ok(height - inset / density - paintedBottom >= 28 - 0.001);
          assert.equal(view.compactPanelBottom(), view.dockTop() - 10);
        }
      }
    }
  }
});

test('visual Dock and independent touch layer share geometry; navigation strip is not swallowed', () => {
  assert.doesNotMatch(page, /y: this\.skyHeight - (62|80)/);
  assert.match(page, /\.height\(this\.dockHeight\(\)\)\s*\.position\(\{ x: dockLeft\([\s\S]*?y: this\.dockTop\(\) \}\)/);
  // isDockPoint is a pure helper in common/derive/geometry.ets; its hit rectangle
  // is bounded by the Dock's own bottom instead of the sky height, so the
  // navigation strip under the Dock is not swallowed by the blocking layer.
  const geometry = read('common/derive/geometry.ets');
  const hit = geometry.match(/export function isDockPoint\([\s\S]*?\r?\n\}/)[0];
  assert.match(hit, /const bottom = top \+ dockHeightValue/);
  assert.doesNotMatch(hit, /const bottom = skyHeight/);
});

test('large PC typography and panel baseline use the same responsive geometry', () => {
  const names = ['isLargeDesktopCanvas', 'dockHeight', 'dockBottomClearance', 'dockTop', 'dockBottom', 'panelTop', 'expandedPanelAvailableHeight', 'panelFontSize'];
  const methods = names.map(name => {
    const match = page.match(new RegExp(`  private ${name}\\([^\\n]*\\n[\\s\\S]*?\\n  \\}`));
    assert.ok(match, name);
    return match[0];
  }).join('\n');
  const Layout = new Function(plain(`class Layout { ${methods} };`) + ';return Layout;')();
  const view = Object.assign(new Layout(), {
    isExpandedLayout: true, isFoldHoverLayout: false, skyWidth: 1600, skyHeight: 1000,
    screenSafeBottomPixels: 0, panelOffsetY: 0, EDGE_MARGIN: 40,
    getUIContext: () => ({ px2vp: value => value })
  });
  assert.equal(view.isLargeDesktopCanvas(), true);
  assert.ok(view.panelFontSize(12) > 12);
  assert.equal(view.panelTop() + view.expandedPanelAvailableHeight(), view.dockBottom());
});

test('all fixed shell font sizes and adaptive minima meet 10fp', () => {
  // Every fixed font size in the refactored UI (page + panels + shared ui) must
  // meet the 10fp accessibility minimum.
  const files = [new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url)];
  const walk = (url) => {
    for (const entry of readdirSync(url, { withFileTypes: true })) {
      const child = new URL(entry.name + (entry.isDirectory() ? '/' : ''), url);
      if (entry.isDirectory()) walk(child);
      else if (entry.name.endsWith('.ets')) files.push(child);
    }
  };
  walk(new URL('../harmonyos/ets-source/panels/', import.meta.url));
  walk(new URL('../harmonyos/ets-source/common/ui/', import.meta.url));
  let count = 0;
  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    assert.doesNotMatch(text, /\.(?:fontSize|minFontSize)\([^)]*\?\s*\d+\s*:\s*[0-9]\s*\)/);
    for (const match of text.matchAll(/\.(?:fontSize|minFontSize)\((\d+(?:\.\d+)?)\)/g)) {
      // The language-refresh anchor is an invisible 0-size element (opacity 0,
      // width/height 0); it is not a rendered font size.
      if (Number(match[1]) === 0.1) continue;
      count++;
      assert.ok(Number(match[1]) >= 10, `${file.pathname}: ${match[0]}`);
    }
  }
  assert.ok(count > 500, `expected the shell to declare fixed sizes, got ${count}`);
});

test('navigation avoid-area changes replace old insets, including hiding the indicator', () => {
  const ability = read('qability/QAbility.ets');
  const method = ability.match(/  private publishNavigationSafeArea\([^\n]*\n[\s\S]*?\n  \}/)[0];
  const values = [];
  const Owner = new Function('AppStorage', plain(`class Owner { ${method} };`) + ';return Owner;')({ setOrCreate: (_key, value) => values.push(value) });
  const instance = new Owner();
  for (const value of [72, 24, 0, -2, NaN]) instance.publishNavigationSafeArea(value);
  assert.deepEqual(values, [72, 24, 0, 0, 0]);
  assert.match(ability, /TYPE_NAVIGATION_INDICATOR\) \{\s*this.publishNavigationSafeArea\(data.area.bottomRect.height\)/);
});

test('resource finalization awaits all startup copies and consent is checked afterwards', () => {
  for (const name of ['refreshTextureCompatibility', 'refreshObjectTypeTranslations', 'refreshSkyCultureEditorialResources', 'refreshDetailModelTextures', 'copyDeepSkyIndexes', 'prepareStellariumResources']) {
    const match = resources.match(new RegExp(`async function ${name}\\([\\s\\S]*?\\n\\}`));
    assert.ok(match, name);
    assert.doesNotMatch(match[0], /\bwriteRawFile\(|getRawFileListSync\(/);
  }
  const stage = read('qabilitystage/QAbilityStage.ets');
  assert.match(stage, /await prepareStellariumResources\(appContext\);\s*if \(!hasCurrentPrivacyConsent\(\)\)/);
});

function writer(counts) {
  const events = [];
  const fs = {
    OpenMode: { CREATE: 1, TRUNC: 2, WRITE_ONLY: 4 },
    accessSync: () => true,
    open: async () => ({ fd: 1 }),
    write: async (_fd, buffer) => {
      events.push(['write', [...new Uint8Array(buffer)]]);
      return counts.shift();
    },
    close: async () => events.push(['close']),
    rename: async () => events.push(['rename']),
    unlinkSync: () => events.push(['cleanup'])
  };
  const logger = { info() {}, warn() {}, error() {} };
  const write = new Function('fs', 'hilog', 'LOG_DOMAIN', 'LOG_TAG', plain(resources) + ';return writeRawFileAsync;')(fs, logger, 0, 'test');
  const context = { resourceManager: { getRawFileContent: async () => new Uint8Array([1, 2, 3, 4]) } };
  return { run: () => write(context, 'source', '/sandbox/file'), events };
}

test('partial asynchronous writes finish before atomically replacing the resource', async () => {
  const fixture = writer([2, 2]);
  await fixture.run();
  assert.deepEqual(fixture.events.slice(0, 4), [['write', [1, 2, 3, 4]], ['write', [3, 4]], ['close'], ['rename']]);
});

test('failed asynchronous write preserves the previously installed resource', async () => {
  const fixture = writer([0]);
  await assert.rejects(fixture.run(), /Failed to write raw resource/);
  assert.ok(!fixture.events.some(event => event[0] === 'rename'));
  assert.ok(fixture.events.some(event => event[0] === 'close'));
  assert.ok(fixture.events.some(event => event[0] === 'cleanup'));
});
