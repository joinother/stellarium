import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const card = source.slice(source.indexOf('  tabletInspectorMedia() {'), source.indexOf('    } else if (this.objectInspectorMediaNoMatch)'));
const preview = source.slice(source.indexOf('  private objectInspectorMediaPreviewOverlay() {'), source.indexOf('  private openObjectInspectorMediaPreview(): void'));

test('detail images preserve their entire frame instead of covering the viewport', () => {
  assert.match(card, /Image\(this\.objectInspectorMediaPixelMap\)[\s\S]*?objectFit\(ImageFit\.Contain\)/);
  assert.doesNotMatch(card, /ImageFit\.Cover/);
});

test('caption follows the image viewport, with no fixed height on the outer column', () => {
  assert.match(card, /Column\(\{ space: 0 \}\) \{\s+Stack\(\{ alignContent: Alignment\.Center \}\)/);
  assert.match(card, /\}\.width\('100%'\)\.height\(this\.objectInspectorImageHeight\(\)\)\s+Row\(\{ space: 6 \}\)/);
  assert.match(card, /\}\s+\.width\('100%'\)\.clip\(true\)\.borderRadius/);
});

test('preview shrinks to the available detail viewport without growing beyond 210vp', () => {
  const body = source.match(/private objectInspectorImageHeight\(\): number \{([\s\S]*?)\n  \}/)[1];
  const height = new Function(body);
  for (const available of [160, 210, 300, 500]) {
    const result = height.call({ objectInspectorMediaViewportHeight: available });
    assert.ok(result >= 72 && result <= 210);
    assert.ok(result + 88 <= available);
  }
});

test('full-screen image keeps aspect fit and a working close action', () => {
  assert.match(preview, /Image\(this\.objectInspectorMediaPixelMap\)[\s\S]*?objectFit\(ImageFit\.Contain\)/);
  assert.match(preview, /onClick\(\(\) => \{ this\.closeObjectInspectorMediaPreview\(\) \}\)/);
});
