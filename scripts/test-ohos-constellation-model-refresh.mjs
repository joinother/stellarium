import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import test from 'node:test'

const source = readFileSync(new URL('../harmonyos/ets-source/qability/StellariumResourceBootstrap.ets', import.meta.url), 'utf8')
const registry = readFileSync(new URL('../harmonyos/ets-source/common/config/ConstellationModelAssets.ets', import.meta.url), 'utf8')
const assets = JSON.parse(registry.split('ConstellationModelAsset[] = ')[1].trim().replace(/;$/, ''))
const revision = registry.match(/MODEL_REVISION = '([^']+)'/)[1]
const method = source.match(/async function refreshConstellationModels\([\s\S]*?\r?\n\}/)[0]
const create = new Function('exists', 'fileSize', 'writeRawFileAsync', 'writeMarker', 'hilog',
  'CONSTELLATION_MODEL_ASSETS', 'CONSTELLATION_MODEL_REVISION', 'RAW_ROOT', 'LOG_DOMAIN', 'LOG_TAG',
  `${stripTypeScriptTypes(method)}; return refreshConstellationModels`)

function harness(marker = '', damaged = '', fail = '') {
  const writes = []
  const markers = []
  const warnings = []
  const sizes = new Map(assets.map(asset => [asset.name, asset.bytes]))
  const refresh = create(path => path.endsWith(marker) && marker.length > 0,
    path => path.endsWith(damaged) && damaged.length > 0 ? 13 : sizes.get(path.split('/').at(-1)),
    async (_context, raw, path) => {
      if (fail.length > 0 && path.endsWith(fail)) throw new Error('disk full')
      assert.equal(raw, 'stellarium/' + path.replace('/sandbox/', ''))
      writes.push(path.split('/').at(-1))
    }, path => markers.push(path), { warn: (...args) => warnings.push(args) },
    assets, revision, 'stellarium', 0, 'test')
  return { run: () => refresh({}, '/sandbox'), writes, markers, warnings }
}

test('seven-model installations upgrade all bundled models and write the new marker last', async () => {
  const context = harness('.bundled_v1')
  await context.run()
  assert.deepEqual(context.writes, assets.map(asset => asset.name))
  assert.equal(context.writes.at(-1), 'manifest.json')
  assert.deepEqual(context.markers, [`/sandbox/skycultures/modern/models/.bundled_${revision}`])
})

test('an intact current installation performs no copies', async () => {
  const context = harness(`.bundled_${revision}`)
  await context.run()
  assert.deepEqual(context.writes, [])
})

test('truncated meshes are repaired even when larger than the old minimum size', async () => {
  const context = harness(`.bundled_${revision}`, 'Ori.scm')
  await context.run()
  assert.ok(context.writes.includes('Ori.scm'))
  assert.equal(context.markers.length, 1)
})

test('failed optional copy leaves no completion marker and allows illustration fallback', async () => {
  const context = harness('.bundled_v1', '', 'Ori.scm')
  await context.run()
  assert.equal(context.markers.length, 0)
  assert.equal(context.warnings.length, 1)
  assert.ok(!context.writes.includes('manifest.json'))
})
