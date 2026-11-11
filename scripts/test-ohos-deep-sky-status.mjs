import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
const start = source.indexOf('if (commandName == "getDeepSkyImageStatus")');
assert.ok(start >= 0);
const handler = source.slice(start, source.indexOf('if (commandName == "retryDeepSkyImages")', start));
const collectionStart = handler.indexOf('QStringList activeReady;');
const collectionEnd = handler.indexOf('QJsonArray targets;', collectionStart);
const resultStart = handler.indexOf('result["layerCount"]');
const resultEnd = handler.indexOf('result["targetOffset"]', resultStart);
assert.ok(collectionStart >= 0 && collectionEnd > collectionStart && resultStart > collectionEnd && resultEnd > resultStart);
const collection = handler.slice(collectionStart, collectionEnd)
  .replace(/QStringList (\w+);/g, 'const $1 = [];')
  .replace(/\b(bool|int) (\w+) =/g, 'let $2 =')
  .replace('const let ', 'const ')
  .replace('if (auto* skyLayerMgr = GETSTELMODULE(StelSkyLayerMgr))', 'const skyLayerMgr = manager; if (skyLayerMgr)')
  .replace('const QMap<QString, StelSkyLayerP> layers', 'const layers')
  .replace('for (auto iter = layers.cbegin(); iter != layers.cend(); ++iter)', 'for (const [key, layer] of layers)')
  .replace('const auto* tile = qobject_cast<const StelSkyImageTile*>(iter.value().data());', 'const tile = layer.isTile ? layer : null;')
  .replaceAll('iter.key()', 'key')
  .replaceAll('->', '.')
  .replace(/(active\w+)\.removeDuplicates\(\);/g, '$1.splice(0, $1.length, ...new Set($1));');
const results = handler.slice(resultStart, resultEnd)
  .replace(/(active\w+)\.size\(\)/g, '$1.length')
  .replace(/(active\w+)\.isEmpty\(\)/g, '($1.length === 0)');
const run = new Function('manager', `${collection}\nconst result = {};\n${results}\nreturn result;`);

function probe(enabled, layers = [], present = true) {
  const calls = [];
  const manager = {
    getFlagShow: () => enabled,
    getAllSkyLayers: () => layers.map((layer, index) => [index, {
      isTile: layer.isTile !== false,
      collectTextureStatus(ready, loading, notStarted, errors, viewportOnly) {
        assert.equal(viewportOnly, true);
        calls.push(index);
        ready.push(...(layer.ready ?? []));
        loading.push(...(layer.loading ?? []));
        notStarted.push(...(layer.notStarted ?? []));
        errors.push(...(layer.errors ?? []));
      }
    }]),
    getShowLayer: key => layers[key].show !== false
  };
  return { result: run(present ? manager : null), calls };
}

test('disabled global switch preserves layer visibility but never reports empty ready', () => {
  const { result, calls } = probe(false, [{}]);
  assert.equal(result.renderEnabled, false);
  assert.equal(result.layerVisible, true);
  assert.equal(result.effectiveLayerVisible, false);
  assert.equal(result.activeTextureStatus, 'disabled');
  assert.equal(result.activeTextureReadyCount, 0);
  assert.deepEqual(calls, []);
});

test('disabled switch excludes stale ready, pending and error candidates', () => {
  const { result, calls } = probe(false, [{ ready: ['m31.png'], loading: ['m42.png'], notStarted: ['m13.png'], errors: ['bad.png'] }]);
  for (const field of ['Ready', 'Loading', 'NotStarted', 'Pending', 'Error']) {
    assert.equal(result[`activeTexture${field}Count`], 0);
  }
  assert.equal(result.activeTextureStatus, 'disabled');
  assert.deepEqual(calls, []);
});

test('enabled renderer with no viewport candidates is idle', () => {
  const { result } = probe(true, [{}]);
  assert.equal(result.renderEnabled, true);
  assert.equal(result.effectiveLayerVisible, true);
  assert.equal(result.activeTextureStatus, 'idle');
});

test('hidden layer candidates cannot contaminate visible layer diagnostics', () => {
  const { result, calls } = probe(true, [{ show: false, errors: ['bad.png'], loading: ['hidden.png'] }, { ready: ['m31.png'] }]);
  assert.equal(result.layerCount, 2);
  assert.equal(result.activeTextureStatus, 'ready');
  assert.equal(result.activeTextureErrorCount, 0);
  assert.equal(result.activeTexturePendingCount, 0);
  assert.deepEqual(calls, [1]);
});

test('all image layers hidden remains disabled with global switch on', () => {
  const { result, calls } = probe(true, [{ show: false, ready: ['m31.png'] }]);
  assert.equal(result.renderEnabled, true);
  assert.equal(result.layerVisible, false);
  assert.equal(result.effectiveLayerVisible, false);
  assert.equal(result.activeTextureStatus, 'disabled');
  assert.deepEqual(calls, []);
});

test('ready requires at least one active ready image and deduplicates names', () => {
  const { result } = probe(true, [{ ready: ['m31.png', 'm31.png'] }, { ready: ['m31.png', 'm42.png'] }]);
  assert.equal(result.activeTextureStatus, 'ready');
  assert.equal(result.activeTextureReadyCount, 2);
});

test('pending decode and not-started candidates retain loading semantics', () => {
  for (const candidate of [{ loading: ['m42.png'] }, { notStarted: ['m42.png'] }]) {
    const { result } = probe(true, [{ ready: ['m31.png'], ...candidate }]);
    assert.equal(result.activeTextureStatus, 'loading');
    assert.equal(result.activeTexturePendingCount, 1);
  }
});

test('error and partial-error retain precedence over pending textures', () => {
  for (const ready of [[], ['m31.png']]) {
    const { result } = probe(true, [{ ready, loading: ['m42.png'], errors: ['bad.png', 'bad.png'] }]);
    assert.equal(result.activeTextureStatus, ready.length ? 'partial-error' : 'error');
    assert.equal(result.activeTextureErrorCount, 1);
  }
});

test('absent manager and non-image layers never imply ready', () => {
  assert.equal(probe(true, [], false).result.renderEnabled, false);
  const { result, calls } = probe(true, [{ isTile: false, ready: ['survey.png'] }]);
  assert.equal(result.layerCount, 0);
  assert.equal(result.layerVisible, false);
  assert.equal(result.activeTextureStatus, 'disabled');
  assert.deepEqual(calls, []);
});

test('legacy pagination, file inventory and target states remain available', () => {
  for (const field of ['ok', 'imageRoot', 'indexPresent', 'referencedCount', 'onDiskCount', 'missingCount', 'missingFiles', 'diskBytes', 'targetOffset', 'targetLimit', 'targetTotal', 'targetHasMore', 'targets']) {
    assert.ok(handler.includes(`result["${field}"]`), field);
  }
  assert.ok(handler.includes('probeParts.value(0).compare("all", Qt::CaseInsensitive)'));
  assert.ok(handler.includes('qBound(1, requestedLimit, 64)'));
  for (const state of ['noMatch', 'decodeFailed', 'ready', 'loading', 'notStarted']) {
    assert.ok(handler.includes(`QStringLiteral("${state}")`), state);
  }
});
