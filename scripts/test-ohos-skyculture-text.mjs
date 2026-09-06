import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');

for (const method of ['cleanSkyCultureNarration', 'cleanSkyCultureDescription']) {
  const match = source.match(new RegExp(`private ${method}\\(text: string\\): string \\{([\\s\\S]*?)\\n  \\}`));
  assert.ok(match, `Missing ${method}`);
  const clean = new Function('text', match[1]);
  test(`${method} preserves word boundaries and shaping controls`, () => {
    const text = 'می\u200Cکند മലയാള\u200Dം ไทย\u200Bไทย 中文\u2060说明';
    assert.equal(clean(text), text);
  });
  test(`${method} still removes extracted image placeholders and replacement characters`, () => {
    assert.equal(clean('\uFEFF资料\uFFFC\uFFFD'), '资料');
  });
}
