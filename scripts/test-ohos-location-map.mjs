import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const hierarchy = readFileSync(new URL('../harmonyos/ets-source/common/location/hierarchy.ts', import.meta.url), 'utf8')
const names = readFileSync(new URL('../harmonyos/ets-source/common/location/names_zh.ts', import.meta.url), 'utf8')
const fullScreen = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationFullScreenMap.ets', import.meta.url), 'utf8')
const raster = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationRasterMap.ets', import.meta.url), 'utf8')
const place = readFileSync(new URL('../harmonyos/ets-source/panels/panels/PlacePanel.ets', import.meta.url), 'utf8')
const host = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8')
const onlineMap = readFileSync(new URL('../harmonyos/ets-source/pages/LocationOnlineMap.ets', import.meta.url), 'utf8')
const sessionStore = readFileSync(new URL('../harmonyos/ets-source/state/SessionToolStore.ets', import.meta.url), 'utf8')
const mercatorGenerator = readFileSync(new URL('../scripts/build-ohos-mercator-textures.mjs', import.meta.url), 'utf8')
const resourceSyncSh = readFileSync(new URL('../scripts/sync-ohos-resources.sh', import.meta.url), 'utf8')
const resourceSyncPs = readFileSync(new URL('../scripts/sync-ohos-resources-windows.ps1', import.meta.url), 'utf8')
const buildSourcesSh = readFileSync(new URL('../scripts/sync-ohos-build-sources.sh', import.meta.url), 'utf8')

function loadLiteral(source) {
  return Function(`"use strict"; return (${source.slice(source.indexOf('=') + 1).replace(/;\s*$/, '')})`)()
}

const hierarchyObject = loadLiteral('const H = ' + hierarchy.slice(hierarchy.indexOf('=') + 1))
const nameObject = loadLiteral('const N = ' + names.slice(names.indexOf('=') + 1))
const counts = {}
let total = 0
for (const regions of Object.values(hierarchyObject)) {
  for (const cities of Object.values(regions)) {
    for (const city of cities) {
      const planet = city.planet ?? 'Earth'
      counts[planet] = (counts[planet] ?? 0) + 1
      total += 1
    }
  }
}

test('non-Earth locations are present with Chinese names', () => {
  assert.equal(counts.Moon, 63)
  assert.equal(counts.Mars, 16)
  assert.equal(counts.Venus, 14)
  assert.equal(counts.Titan, 1)
  assert.equal(counts.Bennu, 1)
  assert.equal(total, 8174)
  for (const regions of Object.values(hierarchyObject)) {
    for (const cities of Object.values(regions)) {
      for (const city of cities) {
        assert.ok(nameObject[city.n], `missing Chinese name for ${city.n}`)
      }
    }
  }
  assert.equal(nameObject["Chang'e 4"], '嫦娥四号')
  assert.equal(nameObject['Yutu-2'], '玉兔二号')
  assert.equal(nameObject['Zhurong'], '祝融号')
})

test('full-screen map has Petal search, overlay and raster fallback', () => {
  assert.match(fullScreen, /site\.searchByText/)
  assert.match(fullScreen, /MapType\.NONE/)
  assert.match(fullScreen, /setSphereMapEnabled/)
  assert.match(fullScreen, /coverageImage/)
  assert.match(fullScreen, /syncPlanet2DOverlay/)
  assert.match(fullScreen, /addImageOverlay/)
  assert.match(fullScreen, /supports2DMap/)
  assert.match(fullScreen, /maxZoom = supports2DMap/)
  assert.match(fullScreen, /sphereEnabled: true/)
  assert.match(fullScreen, /LocationRasterMap/)
  assert.match(fullScreen, /mapClick/)
  assert.match(fullScreen, /toWgs84/)
})

test('raster fallback uses equirectangular picking', () => {
  assert.match(raster, /x \/ width \* 360 - 180/)
  assert.match(raster, /90 - y \/ height \* 180/)
  assert.match(raster, /onOpenFull/)
  assert.match(raster, /PanGesture/)
  assert.match(raster, /PinchGesture/)
  assert.match(raster, /setZoom/)
})

test('place panel exposes a full-screen overlay and globe preview', () => {
  assert.match(place, /onOpenFullMap/)
  assert.match(host, /LocationFullScreenMap/)
  assert.match(host, /zIndex\(200\)/)
  assert.match(host, /fixedObserverPoint/)
  assert.match(sessionStore, /isObserverOverviewPoint/)
  assert.match(onlineMap, /sphereEnabled: true/)
})

test('mercator overlays are generated from PC textures at build time', () => {
  for (const name of ['moon_4k_mercator.jpg', 'mars_mercator.jpg', 'mercury_mercator.jpg',
    'venus_mercator.jpg', 'jupiter_mercator.jpg', 'saturn_mercator.jpg',
    'uranus_mercator.jpg', 'neptune_mercator.jpg']) {
    assert.ok(mercatorGenerator.includes(name), `missing ${name}`)
  }
  assert.match(mercatorGenerator, /--check/)
  assert.match(mercatorGenerator, /source: 'mars\.png'/)
  assert.match(resourceSyncSh, /build-ohos-mercator-textures\.mjs/)
  assert.match(resourceSyncPs, /build-ohos-mercator-textures\.mjs/)
  assert.match(buildSourcesSh, /build-ohos-mercator-textures\.mjs/)
  assert.match(buildSourcesSh, /MERCATOR_MISSING/)
  // obs_*.jpg are observation diagrams, not equirectangular surface maps.
  assert.doesNotMatch(fullScreen, /obs_mars/)
})
