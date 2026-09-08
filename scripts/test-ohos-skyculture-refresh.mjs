import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/qability/StellariumResourceBootstrap.ets', import.meta.url), 'utf8');
const match = source.match(/function refreshSkyCultureEditorialResources\([^)]*\): void \{([\s\S]*?)\n\}/);
assert.ok(match);
const body = match[1].replace(': Array<string>', '').replace(/\(path: string\)/g, '(path)');
const factory = new Function('exists', 'fileSize', 'writeRawFile', 'writeMarker', 'hilog', 'RAW_ROOT',
  'SKYCULTURE_EDITORIAL_MARKER', 'LOG_DOMAIN', 'LOG_TAG', `return function(appContext, installRoot) {${body}}`);

function harness({ marker = false, fail = '', missing = '' } = {}) {
  const writes = [];
  const markers = [];
  const directories = {
    'raw/skycultures': ['chinese', 'tukano', '../private', 'TODO.txt', 'empty_culture'],
    'raw/skycultures/chinese': ['index.json', 'description.md'],
    'raw/skycultures/tukano': ['index.json', 'description.md'],
    'raw/skycultures/empty_culture': ['index.json'],
    'raw/translations/stellarium-skycultures-descriptions': ['zh_CN.qm', 'de.qm', '../secret.qm', 'metadata.json'],
  };
  const refresh = factory(() => marker, path => path.endsWith(missing) && missing ? 0 : 1,
    (_context, raw, path) => {
      if (path.endsWith(fail) && fail) throw new Error('write failed');
      writes.push({ raw, path });
    }, path => markers.push(path), { info() {} }, 'raw', 'marker-v3', 0, 'test');
  const context = { resourceManager: { getRawFileListSync: directory => {
    assert.ok(directories[directory], `Unexpected raw directory: ${directory}`);
    return directories[directory];
  } } };
  return { run: () => refresh(context, '/sandbox'), writes, markers };
}

test('refresh includes all bundled culture descriptions, not only three hardcoded cultures', () => {
  const fixture = harness();
  fixture.run();
  assert.deepEqual(fixture.writes.map(write => write.path), [
    '/sandbox/data/skyculture_editorial_context.json', '/sandbox/skycultures/chinese/description.md',
    '/sandbox/skycultures/tukano/description.md', '/sandbox/translations/stellarium-skycultures-descriptions/zh_CN.qm',
    '/sandbox/translations/stellarium-skycultures-descriptions/de.qm',
  ]);
  assert.deepEqual(fixture.markers, ['/sandbox/marker-v3']);
});

test('completed marker avoids rewriting intact resources', () => {
  const fixture = harness({ marker: true });
  fixture.run();
  assert.equal(fixture.writes.length, 0);
  assert.equal(fixture.markers.length, 0);
});

test('missing culture resource invalidates an existing marker', () => {
  const fixture = harness({ marker: true, missing: 'tukano/description.md' });
  fixture.run();
  assert.equal(fixture.writes.length, 5);
});

test('failed refresh cannot write the completion marker', () => {
  const fixture = harness({ fail: 'tukano/description.md' });
  assert.throws(fixture.run, /write failed/);
  assert.equal(fixture.markers.length, 0);
});

test('source attribution covers every selected priority language', () => {
  const context = JSON.parse(readFileSync(new URL('../data/skyculture_editorial_context.json', import.meta.url), 'utf8'));
  assert.equal(context.priorityLanguages.length, 10);
  for (const language of context.priorityLanguages) {
    assert.ok(context.languages.includes(language));
    assert.ok(context.sourceAttribution[language].body);
    if (language !== 'en') assert.notEqual(context.sourceAttribution[language].body, context.sourceAttribution.en.body);
  }
});
