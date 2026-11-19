import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/common/derive/skycult.ets', import.meta.url), 'utf8');

for (const method of ['cleanSkyCultureNarration', 'cleanSkyCultureDescription']) {
  const match = source.match(new RegExp(`export function ${method}\\(text: string\\): string \\{([\\s\\S]*?)\\n\\}`));
  assert.ok(match, `Missing ${method}`);
  const clean = new Function('text', match[1]);
  test(`${method} preserves word boundaries and shaping controls`, () => {
    const text = 'می\u200Cکند മലയാള\u200Dം ไทย\u200Bไทย 中文\u2060说明';
    assert.equal(clean(text), text);
  });
  test(`${method} still removes extracted image placeholders and replacement characters`, () => {
    assert.equal(clean('\uFEFF资料\uFFFC\uFFFD'), '资料');
  });
  test(`${method} strips tabs, residual markdown emphasis, and citation hashes while preserving footnotes and star IDs`, () => {
    assert.equal(clean('\t_仙女座_即安德洛墨达公主，见[#40]。'), '仙女座即安德洛墨达公主，见[40]。');
    assert.equal(clean('狐狸座_星座最初由赫维留斯创立，原名为_Vulpecula cum Ansere。'), '狐狸座星座最初由赫维留斯创立，原名为Vulpecula cum Ansere。');
    assert.equal(clean('仙王座的*造父一*与<notr>天稷*</notr>及 S_Sco'), '仙王座的造父一与天稷*及 S_Sco');
  });
}

test('cleanSkyCultureNarration cleans markdown headings and links', () => {
  const match = source.match(/export function cleanSkyCultureNarration\(text: string\): string \{([\s\S]*?)\n\}/);
  const clean = new Function('text', match[1]);
  assert.equal(
    clean('### 星座\n\n详见[中国星官](https://example.com/a_b)与**北斗**。'),
    '星座\n\n详见中国星官与北斗。'
  );
});

test('C++ and ArkUI skyculture block pipelines group tables by row with cells', () => {
  const cpp = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
  assert.ok(cpp.includes('QTextTable* table = QTextCursor(block).currentTable()'), 'missing QTextTable row grouping');
  assert.ok(cpp.includes('item[QStringLiteral("cells")] = cells;'), 'missing cells payload in descriptionBlocks');
  assert.ok(cpp.includes('QStringLiteral("tableHeader")'), 'missing tableHeader kind');
  const view = readFileSync(new URL('../harmonyos/ets-source/common/ui/SkyCultureDescriptionBlockView.ets', import.meta.url), 'utf8');
  assert.ok(view.includes('@Prop cells: string[]'), 'missing cells prop in SkyCultureDescriptionBlockView');
  assert.ok(view.includes("this.kind === 'tableHeader'"), 'missing tableHeader rendering branch');
});
