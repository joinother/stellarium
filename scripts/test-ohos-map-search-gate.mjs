import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import test from 'node:test'

const source = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationFullScreenMap.ets', import.meta.url), 'utf8')
const methods = ['runSearch', 'onlineSearchAllowed', 'searchPetal', 'resolveAltitude'].map(name => {
  const match = source.match(new RegExp(`  private (?:async )?${name}\\([\\s\\S]*?\\r?\\n  \\}`))
  assert.ok(match, name)
  return match[0]
}).join('\n')
const code = stripTypeScriptTypes(`class SearchHarness { ${methods} }`)

function fixture(enabled = true) {
  let finishRequest
  let calls = 0
  const local = []
  const pending = new Promise(resolve => { finishRequest = resolve })
  const Constructor = new Function('METERED_MAP_APIS_ENABLED', 'site', 'I18n', `${code}; return SearchHarness`)(
    enabled, { searchByText: () => { calls += 1; return pending } }, { isChineseLanguage: () => false })
  const instance = Object.assign(new Constructor(), {
    mapAllowed: true, observerPlanet: 'Earth', searchRequestId: 0,
    hasOnlineNetwork: () => true, searchOffline: query => local.push(query),
    toWgs84: async point => point, petalResults: []
  })
  return { instance, local, calls: () => calls, finishRequest }
}

test('denied, background, offline, non-Earth and disabled searches remain local', async () => {
  for (const overrides of [{ mapAllowed: false }, { hasOnlineNetwork: () => false }, { observerPlanet: 'Mars' }]) {
    const context = fixture()
    Object.assign(context.instance, overrides)
    await context.instance.runSearch('Taipei')
    assert.deepEqual(context.local, ['Taipei'])
    assert.equal(context.calls(), 0)
  }
  const disabled = fixture(false)
  await disabled.instance.runSearch('Taipei')
  assert.equal(disabled.calls(), 0)
})

test('allowed search calls service once and ignores results after gate closes', async () => {
  const context = fixture()
  const request = context.instance.runSearch('Taipei')
  assert.equal(context.calls(), 1)
  context.instance.mapAllowed = false
  context.finishRequest({ sites: [{ name: 'Result', location: { latitude: 25, longitude: 121 }, addressComponent: {} }] })
  await request
  assert.deepEqual(context.instance.petalResults, [])
})

test('altitude lookup falls back locally when the gate closes during coordinate conversion', async () => {
  const context = fixture()
  Object.assign(context.instance, {
    localGlobe: false, altitudeRequestId: 1, altitudeResolving: true,
    locationStore: { altitudeForPoint: () => ({ found: true, altitude: 42, name: 'Local' }) },
    toMapCoordinate: async () => {
      context.instance.mapAllowed = false
      return { latitude: 25, longitude: 121 }
    }
  })
  await context.instance.resolveAltitude(25, 121, 1, undefined, true)
  assert.equal(context.instance.altitudeResolving, false)
  assert.equal(context.instance.selectedAltitude, 42)
  assert.equal(context.instance.selectedName, 'Local')
})
