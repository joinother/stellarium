import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const root = new URL('../', import.meta.url);
const read = (file) => readFileSync(new URL('harmonyos/ets-source/' + file, root), 'utf8');

async function sourceModule(relativePath) {
  // Drop both single-line and multiline ES imports; the pure header helper does
  // not need the native http module or the parser module at import time.
  const source = read(relativePath)
    .replace(/^import\s+(?:\{[^}]*\}|\w+)\s+from\s+'[^']+';?[ \t]*$/gm, '');
  return import('data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source)));
}

const { locationHeaderValue } = await sourceModule('common/location/LocationShareResolver.ets');

test('Location header lookup is case-insensitive and string-only', () => {
  assert.equal(locationHeaderValue({ location: 'http://wb.amap.com/?q=1,2,x' }), 'http://wb.amap.com/?q=1,2,x');
  assert.equal(locationHeaderValue({ Location: 'https://uri.amap.com/marker?position=1,2' }),
    'https://uri.amap.com/marker?position=1,2');
  assert.equal(locationHeaderValue({ 'status-line': 'HTTP/1.1 302' }), '');
  assert.equal(locationHeaderValue({ location: 42 }), '');
});

test('short-link resolver keeps requests bounded and allowlisted', () => {
  const resolver = read('common/location/LocationShareResolver.ets');
  assert.match(resolver, /maxRedirects: 0/);
  assert.doesNotMatch(resolver, /maxRedirects: [1-9]/);
  assert.match(resolver, /headersReceive/);
  assert.match(resolver, /AMAP_SHORT_LINK_TIMEOUT_MS: number = 5000/);
  assert.match(resolver, /AMAP_SHORT_LINK_MAX_BODY_BYTES: number = 64 \* 1024/);
  assert.match(resolver, /findAmapShortLink\(raw\)/);
  assert.match(resolver, /isAllowedAmapRedirect\(location\)/);
  assert.match(resolver, /request\.destroy\(\)/);
});
