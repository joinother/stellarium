import test from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'

const hierarchy = readFileSync(new URL('../harmonyos/ets-source/common/location/hierarchy.ts', import.meta.url), 'utf8')
const names = readFileSync(new URL('../harmonyos/ets-source/common/location/names_zh.ts', import.meta.url), 'utf8')
const fullScreen = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationFullScreenMap.ets', import.meta.url), 'utf8')
const place = readFileSync(new URL('../harmonyos/ets-source/panels/panels/PlacePanel.ets', import.meta.url), 'utf8')
const picker = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationPickerPanel.ets', import.meta.url), 'utf8')
const host = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8')
const locationStore = readFileSync(new URL('../harmonyos/ets-source/state/LocationStore.ets', import.meta.url), 'utf8')
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

test('full-screen map is Map Kit only, with search and a retryable error state', () => {
  assert.match(fullScreen, /site\.searchByText/)
  assert.match(fullScreen, /MapType\.NONE/)
  assert.match(fullScreen, /setSphereMapEnabled/)
  assert.match(fullScreen, /typeof controller\.setSphereMapEnabled !== 'function'/)
  assert.match(fullScreen, /coverageImage/)
  assert.match(fullScreen, /syncPlanet2DOverlay/)
  assert.match(fullScreen, /addImageOverlay/)
  assert.match(fullScreen, /supports2DMap/)
  assert.match(fullScreen, /sphereEnabled: true/)
  assert.match(fullScreen, /mapClick/)
  assert.match(fullScreen, /toWgs84/)
  assert.match(fullScreen, /toMapCoordinate/)
  assert.match(fullScreen, /placeInitialPoint/)
  assert.match(fullScreen, /setPadding/)
  assert.match(fullScreen, /expandedLayout/)
  assert.match(fullScreen, /searchLocations\(query, this\.observerPlanet\)/)
  assert.match(fullScreen, /map_search_offline_section/)
  assert.match(fullScreen, /map_search_planet_placeholder/)
  assert.match(fullScreen, /enableLocalGlobe/)
  assert.match(fullScreen, /earth_cmap_mercator/)
  assert.match(fullScreen, /map_surface_globe/)
  assert.match(fullScreen, /hasDefaultNetSync/)
  assert.match(fullScreen, /localGlobeAllowed/)
  assert.match(fullScreen, /mapFailed/)
  assert.match(fullScreen, /map_unavailable_sdk/)
  assert.match(fullScreen, /map_unavailable_texture/)
  assert.match(fullScreen, /map_unavailable_privacy/)
  assert.match(fullScreen, /map_retry/)
  assert.match(fullScreen, /retryMap/)
  // Title bar: body name as the title, surface source as the subtitle, on a
  // full-width glass plate so bright map tiles cannot wash out the text.
  assert.match(fullScreen, /Text\(this\.planetLabel\(this\.observerPlanet\)\)/)
  assert.match(fullScreen, /Text\(this\.surfaceLabel\(\)\)/)
  // Separate pill-shaped title and circular back button, both with glass backing.
  assert.match(fullScreen, /Text\(this\.surfaceLabel\(\)\)[\s\S]{0,800}borderRadius\(UI_RADIUS_PILL\)/)
  assert.match(fullScreen, /borderRadius\(22\)/)
  assert.doesNotMatch(fullScreen, /map_tool_title/)
})

test('full-screen map has no raster fallback', () => {
  assert.equal(existsSync(new URL('../harmonyos/ets-source/panels/location/LocationRasterMap.ets',
    import.meta.url)), false)
  assert.doesNotMatch(fullScreen, /LocationRasterMap/)
  assert.doesNotMatch(fullScreen, /worldmap\.jpg/)
  assert.doesNotMatch(fullScreen, /pickOnRaster/)
})

test('full-screen map resolves altitude and has Earth-only GPS', () => {
  assert.match(fullScreen, /site\.reverseGeocode/)
  assert.match(fullScreen, /altitudeForCityName/)
  assert.match(fullScreen, /altitudeForPoint/)
  assert.match(fullScreen, /map_altitude_city/)
  assert.match(fullScreen, /map_altitude_gps/)
  assert.match(fullScreen, /map_altitude_offline/)
  assert.match(fullScreen, /selectedAltitudeSource/)
  assert.match(fullScreen, /setMyLocationStyle/)
  assert.match(fullScreen, /TRACK_ROTATE/)
  assert.match(fullScreen, /myLocationClick/)
  assert.match(fullScreen, /mapSideTools/)
  assert.match(fullScreen, /map_view_selected/)
  assert.match(fullScreen, /map_gps_locate/)
  assert.match(fullScreen, /setMyLocationControlsEnabled\(false\)/)
  assert.match(fullScreen, /recenterZoomed/)
  // GPS-selected points switch the draft pin from red to blue.
  assert.match(fullScreen, /ic_map_pin_blue/)
  assert.match(fullScreen, /ic_map_pin_red/)
  assert.match(fullScreen, /setIcon/)
  assert.match(fullScreen, /ic_gps_hit/)
  assert.match(fullScreen, /markerClick/)
  assert.match(fullScreen, /gpsHitMarker/)
  // Terrain / satellite Petal map layers in the bottom-right side bar.
  assert.match(fullScreen, /setMapLayerType/)
  assert.match(fullScreen, /mapLayerType/)
  assert.match(fullScreen, /MapType\.TERRAIN/)
  assert.match(fullScreen, /MapType\.SATELLITE/)
  assert.match(fullScreen, /map_layer_terrain/)
  assert.match(fullScreen, /map_layer_satellite/)
  // The online map label uses the converted map coordinate; the draft stays
  // WGS84 for the pick result.
  assert.match(fullScreen, /onOnlineMap/)
  assert.match(fullScreen, /borderRadius\(UI_RADIUS_PANEL\)/)
  assert.doesNotMatch(fullScreen, /applyGpsSelectedStyle/)
  assert.doesNotMatch(fullScreen, /gpsSelectedMarker/)
  assert.doesNotMatch(fullScreen, /mapControls/)
  assert.match(locationStore, /altitudeForPoint\(/)
  assert.match(locationStore, /altitudeForCityName\(/)
  assert.match(locationStore, /OFFLINE_ALTITUDE_MAX_DISTANCE_DEG/)
})

test('place panel exposes a full-screen overlay and globe preview', () => {
  assert.match(place, /onOpenFullMap/)
  assert.doesNotMatch(place, /LocationMapSection/)
  assert.match(picker, /onOpenFullMap/)
  assert.match(picker, /ic_fullscreen/)
  assert.match(host, /LocationFullScreenMap/)
  assert.match(host, /zIndex\(200\)/)
  assert.match(host, /fixedObserverPoint/)
  assert.match(sessionStore, /isObserverOverviewPoint/)
  // Fixed overview points keep the map image, but the preview is inert.
  assert.match(place, /fixedObserverPreview/)
  assert.match(place, /map_fixed_overview_badge/)
  assert.match(place, /hitTestBehavior\(HitTestMode\.None\)/)
})

test('mercator overlays are generated from PC textures at build time', () => {
  for (const name of ['earth_cmap_mercator.jpg', 'moon_4k_mercator.jpg', 'mars_mercator.jpg',
    'mercury_mercator.jpg', 'venus_mercator.jpg', 'jupiter_mercator.jpg', 'saturn_mercator.jpg',
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
