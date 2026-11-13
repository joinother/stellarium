import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { fileURLToPath } from 'node:url'

const applier = fileURLToPath(new URL('./apply-ohos-feature-flags.mjs', import.meta.url))
const declaration = [
  'export const METERED_MAP_APIS_ENABLED: boolean = true',
  'export const DEV_TOOLS_ENABLED: boolean = true',
  ''
].join('\n')

function makeRoot(source) {
  const root = mkdtempSync(join(tmpdir(), 'ohos-flags-'))
  mkdirSync(join(root, 'common', 'config'), { recursive: true })
  writeFileSync(join(root, 'common', 'config', 'OhosFeatureFlags.ets'), source)
  return root
}

function runArgs(root, args) {
  return spawnSync(process.execPath, [applier, '--ets-root', root, ...args], { encoding: 'utf8' })
}

function run(root, metered, devTools) {
  return runArgs(root, [`--metered-map-apis=${metered}`, `--dev-tools=${devTools}`])
}

test('feature flag applier disables and re-enables both flags', () => {
  const root = makeRoot(declaration)
  try {
    const disabled = run(root, '0', '0')
    assert.equal(disabled.status, 0, disabled.stderr)
    const afterDisable = readFileSync(join(root, 'common', 'config', 'OhosFeatureFlags.ets'), 'utf8')
    assert.match(afterDisable, /METERED_MAP_APIS_ENABLED: boolean = false/)
    assert.match(afterDisable, /DEV_TOOLS_ENABLED: boolean = false/)
    const enabled = run(root, '1', '1')
    assert.equal(enabled.status, 0, enabled.stderr)
    const afterEnable = readFileSync(join(root, 'common', 'config', 'OhosFeatureFlags.ets'), 'utf8')
    assert.match(afterEnable, /METERED_MAP_APIS_ENABLED: boolean = true/)
    assert.match(afterEnable, /DEV_TOOLS_ENABLED: boolean = true/)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})

test('feature flag applier leaves unspecified flags at the tracked source value', () => {
  const source = [
    'export const METERED_MAP_APIS_ENABLED: boolean = true',
    'export const DEV_TOOLS_ENABLED: boolean = false',
    ''
  ].join('\n')
  const root = makeRoot(source)
  try {
    const noArgs = runArgs(root, [])
    assert.equal(noArgs.status, 0, noArgs.stderr)
    assert.equal(readFileSync(join(root, 'common', 'config', 'OhosFeatureFlags.ets'), 'utf8'), source)
    const meteredOnly = runArgs(root, ['--metered-map-apis=0'])
    assert.equal(meteredOnly.status, 0, meteredOnly.stderr)
    const after = readFileSync(join(root, 'common', 'config', 'OhosFeatureFlags.ets'), 'utf8')
    assert.match(after, /METERED_MAP_APIS_ENABLED: boolean = false/)
    assert.match(after, /DEV_TOOLS_ENABLED: boolean = false/)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})

test('feature flag applier fails loudly when the metered declaration moved', () => {
  const root = makeRoot('export const DEV_TOOLS_ENABLED: boolean = true\n')
  try {
    const result = run(root, '0', '1')
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /expected exactly one METERED_MAP_APIS_ENABLED declaration/)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})

test('feature flag applier fails loudly when the dev-tools declaration moved', () => {
  const root = makeRoot('export const METERED_MAP_APIS_ENABLED: boolean = true\n// dev marker removed\n')
  try {
    const result = run(root, '1', '0')
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /expected exactly one DEV_TOOLS_ENABLED declaration/)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})
