import test from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'

const hierarchy = readFileSync(new URL('../harmonyos/ets-source/common/location/hierarchy.ts', import.meta.url), 'utf8')
const names = readFileSync(new URL('../harmonyos/ets-source/common/location/names_zh.ts', import.meta.url), 'utf8')
const fullScreen = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationFullScreenMap.ets', import.meta.url), 'utf8')
const place = readFileSync(new URL('../harmonyos/ets-source/panels/panels/PlacePanel.ets', import.meta.url), 'utf8')
const picker = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationPickerPanel.ets', import.meta.url), 'utf8')
const overview = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationOverviewCard.ets', import.meta.url), 'utf8')
const searchPanel = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationSearchPanel.ets', import.meta.url), 'utf8')
const featureFlags = readFileSync(new URL('../harmonyos/ets-source/common/config/OhosFeatureFlags.ets', import.meta.url), 'utf8')
const theme = readFileSync(new URL('../harmonyos/ets-source/state/StellariumTheme.ets', import.meta.url), 'utf8')
const flagApplier = readFileSync(new URL('../scripts/apply-ohos-feature-flags.mjs', import.meta.url), 'utf8')
const buildPs = readFileSync(new URL('../scripts/build-ohos-hap-windows.ps1', import.meta.url), 'utf8')
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
  assert.match(picker, /LocationOverviewCard/)
  assert.match(overview, /ic_fullscreen/)
  assert.match(host, /LocationFullScreenMap/)
  assert.match(host, /zIndex\(200\)/)
  assert.match(host, /fixedObserverPoint/)
  assert.match(sessionStore, /isObserverOverviewPoint/)
  // Fixed overview points keep the map image, but the preview is inert.
  assert.match(place, /fixedObserverPreview/)
  assert.match(place, /map_fixed_overview_badge/)
  assert.match(place, /hitTestBehavior\(HitTestMode\.None\)/)
})

test('location overview card is a read-only static terrain preview', () => {
  // The inline overview no longer picks a point; precision picking is the
  // full-screen Map Kit picker. Only the full-screen entry remains.
  assert.doesNotMatch(picker, /handleLocationMapClick/)
  assert.doesNotMatch(picker, /updatePickerFromMap/)
  assert.match(overview, /onOpen/)
  assert.match(overview, /map_preview_terrain/)
  assert.match(overview, /map_preview_offline/)
  assert.match(overview, /map_preview_planet/)
  assert.match(overview, /nightMask/)
  assert.match(overview, /mapNightTint/)
  // Free online terrain basemap, read-only: no static-map API, no pick click,
  // no gestures, fixed zoom 12, and unmounted while the full-screen is open.
  assert.match(overview, /MapComponent/)
  assert.match(overview, /MapType\.TERRAIN/)
  assert.match(overview, /zoom: PREVIEW_ZOOM/)
  assert.match(overview, /scrollGesturesEnabled: false/)
  assert.match(overview, /zoomGesturesEnabled: false/)
  assert.match(overview, /hitTestBehavior\(HitTestMode\.None\)/)
  assert.match(overview, /suspended/)
  assert.doesNotMatch(overview, /mapClick/)
  assert.doesNotMatch(overview, /staticMap/)
  assert.doesNotMatch(overview, /getMapImage/)
  assert.doesNotMatch(overview, /StaticMapPreviewClient/)
  // The old inline picker is gone; the altitude field applies on blur/submit.
  assert.doesNotMatch(picker, /I18n\.t\('i0053'\)/)
  assert.match(picker, /\.onSubmit\(\(\) => \{ this\.commitAltitude\(\) \}\)/)
  assert.match(picker, /\.onBlur\(\(\) => \{ this\.commitAltitude\(\) \}\)/)
  assert.match(picker, /private commitAltitude\(\)/)
})

test('metered Map Kit APIs have a build-time switch', () => {
  assert.match(featureFlags, /METERED_MAP_APIS_ENABLED/)
  // Search and reverse geocoding are the only metered calls left; the panel's
  // terrain preview and the online Petal basemap are free and stay enabled.
  assert.ok((fullScreen.match(/METERED_MAP_APIS_ENABLED/g) ?? []).length >= 3)
  assert.match(fullScreen, /if \(METERED_MAP_APIS_ENABLED && this\.observerPlanet === 'Earth'\)/)
  assert.match(fullScreen, /!this\.localGlobe && METERED_MAP_APIS_ENABLED/)
  assert.match(flagApplier, /metered-map-apis/)
  assert.match(flagApplier, /METERED_MAP_APIS_ENABLED/)
  assert.match(buildSourcesSh, /apply-ohos-feature-flags\.mjs/)
  assert.match(buildSourcesSh, /OHOS_METERED_MAP_APIS/)
  assert.match(buildPs, /DisableMeteredMapApis/)
  assert.match(buildPs, /OHOS_METERED_MAP_APIS/)
  // The free online Petal basemap and its layers are not part of the switch.
  assert.match(fullScreen, /mapLayerAvailable/)
  assert.doesNotMatch(fullScreen, /prepareMap\(\)[\s\S]{0,400}METERED_MAP_APIS_ENABLED/)
  assert.doesNotMatch(overview, /METERED_MAP_APIS_ENABLED/)
})

test('full-screen map follows the app night mode with a red wash', () => {
  assert.match(fullScreen, /DayNightMode\.NIGHT/)
  assert.match(fullScreen, /DayNightMode\.AUTO/)
  assert.match(fullScreen, /setDayNightMode/)
  assert.match(fullScreen, /onWillApplyTheme[\s\S]{0,400}applyMapNightMode/)
  assert.match(fullScreen, /mapNightTint/)
  assert.match(theme, /mapNightTint/)
  assert.match(theme, /rgba\(165,0,0,0\.42\)/)
})

test('tonight stays in the place panel, developer tools use a dedicated panel', () => {
  assert.doesNotMatch(place, /PointingTestSection/)
  assert.doesNotMatch(place, /WatchGyroSection/)
  assert.match(place, /TonightEventsSection/)
  assert.match(place, /OFFLINE_APPGALLERY_BUILD/)
  const devTools = readFileSync(new URL('../harmonyos/ets-source/panels/panels/DevToolsPanel.ets',
    import.meta.url), 'utf8')
  assert.match(devTools, /PointingTestSection/)
  assert.match(devTools, /WatchGyroSection/)
  const actions = readFileSync(new URL('../harmonyos/ets-source/common/derive/actions.ets', import.meta.url), 'utf8')
  assert.match(actions, /DEV_TOOLS_ENABLED/)
  assert.match(actions, /panel: 'devTools'/)
  // Session continuation now lives in the astro panel's "tonight" tab.
  assert.doesNotMatch(place, /ContinuationSection/)
  const astro = readFileSync(new URL('../harmonyos/ets-source/panels/astro/AstroPanel.ets', import.meta.url), 'utf8')
  assert.match(astro, /ContinuationSection/)
})

test('panel search merges online Petal POI results with debounce', () => {
  assert.match(searchPanel, /site\.searchByText/)
  assert.match(searchPanel, /ONLINE_SEARCH_DEBOUNCE_MS: number = 400/)
  assert.match(searchPanel, /scheduleOnlineSearch/)
  assert.match(searchPanel, /onlineRequestId/)
  assert.match(searchPanel, /locSearchOnlineResults/)
  assert.match(searchPanel, /locSearchOnlineState/)
  assert.match(searchPanel, /METERED_MAP_APIS_ENABLED/)
  assert.match(searchPanel, /observerPlanet !== 'Earth'/)
  assert.match(searchPanel, /onlineToWgs84/)
  assert.match(searchPanel, /map_search_online_section/)
  assert.match(searchPanel, /map_search_online_badge/)
  assert.match(searchPanel, /map_search_local_hint/)
  // The offline scan keeps its own faster debounce and still runs first.
  assert.match(searchPanel, /setTimeout\(\(\) => \{ this\.onSearch\(value\) \}, 260\)/)
  assert.match(picker, /observerPlanet: this\.observerPlanet/)
  assert.match(picker, /onlineAllowed: this\.onlineAllowed/)
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
