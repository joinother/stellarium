import test from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, readFileSync, statSync } from 'node:fs'

const atmosphere = readFileSync(new URL('../harmonyos/ets-source/common/derive/atmosphere.ets', import.meta.url), 'utf8')
const barometer = readFileSync(new URL('../harmonyos/ets-source/capability/BarometerReader.ets', import.meta.url), 'utf8')
const section = readFileSync(new URL('../harmonyos/ets-source/panels/location/PlaceEnvironmentSection.ets', import.meta.url), 'utf8')
const place = readFileSync(new URL('../harmonyos/ets-source/panels/panels/PlacePanel.ets', import.meta.url), 'utf8')
const store = readFileSync(new URL('../harmonyos/ets-source/state/LocationPickerStore.ets', import.meta.url), 'utf8')
const map = readFileSync(new URL('../harmonyos/ets-source/panels/location/LocationFullScreenMap.ets', import.meta.url), 'utf8')
const host = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8')
const i18n = readFileSync(new URL('../harmonyos/ets-source/capability/I18n.ets', import.meta.url), 'utf8')
const native = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8')
const observationAid = readFileSync(new URL(
  '../harmonyos/ets-source/panels/layers/ObservationAidBlock.ets', import.meta.url), 'utf8')
const settingsPanel = readFileSync(new URL(
  '../harmonyos/ets-source/panels/panels/SettingsPanel.ets', import.meta.url), 'utf8')
const layerTabs = readFileSync(new URL(
  '../harmonyos/ets-source/panels/layers/LayerViewTabs.ets', import.meta.url), 'utf8')
const layerController = readFileSync(new URL(
  '../harmonyos/ets-source/capability/LayerController.ets', import.meta.url), 'utf8')

function numberConstant(name) {
  const match = new RegExp(`${name}: number = ([0-9.eE-]+)`).exec(atmosphere)
  assert.ok(match, `missing atmosphere constant ${name}`)
  return Number(match[1])
}

test('standard-atmosphere pressure and temperature follow the ISA constants', () => {
  const seaLevelPressure = numberConstant('SEA_LEVEL_PRESSURE_HPA')
  const seaLevelTemperature = numberConstant('SEA_LEVEL_TEMPERATURE_C')
  const lapse = numberConstant('TEMPERATURE_LAPSE_C_PER_M')
  assert.equal(seaLevelPressure, 1013.25)
  assert.equal(seaLevelTemperature, 15)
  assert.equal(lapse, 0.0065)
  assert.match(atmosphere, /2\.25577e-5 \* h, 5\.25588/)
  assert.match(atmosphere, /pressureAtAltitudeHpa\(altitudeM: number\): number/)
  assert.match(atmosphere, /temperatureAtAltitudeC\(altitudeM: number\): number/)
  assert.match(atmosphere, /Math\.max\(1, Math\.min\(1500, value\)\)/)
  assert.match(atmosphere, /Math\.max\(-60, Math\.min\(60, value\)\)/)

  // Well-known reference values used by the UI.
  const pressureAt = (h) => seaLevelPressure * Math.pow(1 - 2.25577e-5 * h, 5.25588)
  assert.ok(Math.abs(pressureAt(0) - 1013.25) < 0.01)
  assert.ok(Math.abs(pressureAt(1000) - 898.75) < 0.2)
  assert.ok(Math.abs(pressureAt(5000) - 540.2) < 0.5)
  assert.equal(seaLevelTemperature - lapse * 1000, 8.5)
  assert.ok(Math.abs(seaLevelTemperature - lapse * 8848 - (-42.512)) < 0.001)
})

test('barometer is a one-shot, no-permission sensor read with a timeout', () => {
  assert.match(barometer, /sensor\.getSensorListSync\(\)/)
  assert.match(barometer, /item\.sensorId === sensor\.SensorId\.BAROMETER/)
  assert.match(barometer, /sensor\.once\(sensor\.SensorId\.BAROMETER/)
  assert.match(barometer, /data\.pressure/)
  assert.match(barometer, /BAROMETER_TIMEOUT_MS: number = 2000/)
  assert.match(barometer, /reject\(new Error\('barometer-timeout'\)\)/)
  assert.doesNotMatch(barometer, /requestPermissionsFromUser/)
})

test('place environment derives pressure/temperature and applies explicitly', () => {
  assert.match(section, /pressureAtAltitudeHpa\(this\.altitude\)/)
  assert.match(section, /temperatureAtAltitudeC\(this\.altitude\)/)
  assert.match(section, /BarometerReader\.available\(\)/)
  assert.match(section, /BarometerReader\.read\(\)/)
  assert.match(section, /this\.mode = 'estimate'/)
  assert.match(section, /if \(mode === 'barometer'\) this\.measure\(\)/)
  assert.match(section, /place_env_barometer_failed/)
  assert.match(section, /const pressure = this\.activePressure\(\)/)
  assert.match(section, /this\.lastAppliedPressure = pressure/)
  assert.match(section, /this\.onApply\(pressure, temperature\)/)
  assert.match(section, /place_env_current_model/)
  // The module itself carries the group backing requested in the panel.
  assert.match(section, /\.backgroundColor\(this\.c\.soft\)/)
  assert.match(section, /\.border\(\{ width: 1, color: this\.c\.softStrong \}\)/)
  assert.match(section, /\.id\('place-environment'\)/)
  assert.match(section, /\.id\('place-environment-apply'\)/)
  for (const key of ['place_env_title', 'place_env_hint', 'place_env_mode_estimate',
    'place_env_mode_barometer', 'place_env_apply', 'place_env_applied', 'place_env_current_model']) {
    assert.match(i18n, new RegExp(`'${key}'\\s*:\\s*\\{`))
  }
})

test('environment card is Earth-only and wired to the atmosphere bridge', () => {
  assert.match(place, /@ObjectLink atmosphereStore: AtmosphereStore/)
  assert.match(place, /PlaceEnvironmentSection\(\{/)
  assert.match(place, /observerPlanet === 'Earth'/)
  assert.match(place, /onApplyEnvironment: \(pressure: number, temperature: number\)/)
  assert.match(host, /onApplyEnvironment: \(pressure: number, temperature: number\) => \{/)
  assert.match(host, /applyAtmosphere\(pressure, temperature, this\.atmosphereStore\.atmoExtinction\)/)
  // Panels reload the persisted engine values when opened, instead of showing
  // the AtmosphereStore defaults after a restart.
  assert.match(host, /private loadAtmosphereParams\(\): void/)
  // A restored panel can mount before Qt is ready, so the read must retry
  // instead of dropping the first {pending}/not-ready reply.
  assert.match(host, /requestWhenReady\('getAtmosphereParams'/)
  // aboutToAppear alone is not enough: a panel restored at startup stays
  // mounted, so every open re-reads the engine values.
  assert.match(host, /if \(nextVisible && \(panel === 'place' \|\| panel === 'layers'\)\) this\.loadAtmosphereParams\(\)/)
  assert.match(host, /onLoadAtmosphere: \(\) => \{ this\.loadAtmosphereParams\(\) \}/)
  assert.match(place, /onLoadAtmosphere: \(\) => void/)
  assert.match(place, /aboutToAppear\(\): void \{[\s\S]{0,120}this\.onLoadAtmosphere\(\)/)
})

test('planet places are listed independently from the hierarchy selection', () => {
  assert.match(store, /const PLANET_PLACES_CACHE: Record<string, Array<HierCity>> = \{\}/)
  const start = store.indexOf('planetPlaces(observerPlanet: string)')
  assert.ok(start >= 0, 'planetPlaces method is missing')
  const end = store.indexOf('hierarchySelectionFor', start)
  const block = store.slice(start, end > start ? end : start + 900)
  assert.doesNotMatch(block, /hierCityList/)
  assert.match(block, /isCurrentObserverPlanet\(city, observerPlanet\)/)
  assert.match(block, /PLANET_PLACES_CACHE\[observerPlanet\] = places/)
})

test('full-screen picker labels non-Earth sites and selects them on tap', () => {
  assert.match(map, /namedPlaces: HierCity\[\] = \[\]/)
  assert.match(map, /placeLabel: \(name: string\) => string/)
  assert.match(map, /this\.syncNamedPlaceMarkers\(\)/)
  assert.match(map, /annotations: \[\{/)
  assert.match(map, /content: label/)
  assert.match(map, /annotationPosition: mapCommon\.TextPosition\.TOP/)
  assert.match(map, /mapCommon\.CollisionRule\.NONE/)
  assert.match(map, /this\.placeMarkerIds\.indexOf\(clickedId\)/)
  assert.match(map, /this\.chooseNamedPlace\(this\.placeMarkerPlaces\[index\]\)/)
  assert.match(map, /this\.selectedPointSource = 'named'/)
  assert.match(map, /place\.al,\s*\n\s*this\.observerPlanet === 'Earth' \? 'city' : 'offline'/)
  assert.match(map, /this\.removeNamedPlaceMarkers\(\)/)
  assert.match(host, /namedPlaces: this\.sessionToolStore\.observerPlanet === 'Earth'/)
  assert.match(host, /planetPlaces\(this\.sessionToolStore\.observerPlanet\)/)
  assert.match(host, /hierarchyItemLabel\(\s*\n?\s*'city', name, this\.sessionToolStore\.observerPlanet\)/)
})

test('3D globe background uses the generated starfield for offline bodies', () => {
  const imagePath = new URL('../harmonyos/ets-source/resources/base/media/space_starfield.png', import.meta.url)
  assert.ok(existsSync(imagePath), 'space_starfield.png is missing')
  const png = readFileSync(imagePath)
  assert.equal(png.toString('ascii', 1, 4), 'PNG')
  assert.equal(png.readUInt32BE(16), 2048)
  assert.equal(png.readUInt32BE(20), 1024)
  assert.ok(statSync(imagePath).size < 4 * 1024 * 1024, 'starfield should stay small enough for the HAP')
  assert.match(map, /getMediaContent\(\$r\('app\.media\.space_starfield'\)\)/)
  assert.match(map, /params\.backgroundImage = starPixelMap/)
  assert.match(map, /coverageImage: pixelMap/)
  const generator = readFileSync(new URL('../scripts/build-ohos-starfield-background.mjs', import.meta.url), 'utf8')
  assert.match(generator, /const WIDTH = 2048/)
  assert.match(generator, /const HEIGHT = 1024/)
  assert.match(generator, /mulberry32\(0x5EED1234\)/)
})

test('place labels declutter with Map Kit projection and annotation visibility', () => {
  assert.match(map, /private refreshPlaceLabelVisibility\(\): void/)
  assert.match(map, /controller\.getProjection\(\)/)
  assert.match(map, /projection\.toScreenLocation\(position\)/)
  assert.match(map, /marker\.setAnnotationVisible\(visible\)/)
  assert.match(map, /typeof marker\.setAnnotationVisible === 'function'/)
  assert.match(map, /private angularDistanceDeg\(/)
  assert.match(map, /PLACE_GLOBE_VISIBLE_ANGLE_DEG/)
  assert.match(map, /private placeLabelWidthPx\(/)
  assert.match(map, /private labelRectsOverlap\(/)
  assert.match(map, /priority: placeIndex/)
  assert.match(map, /this\.selectedPlaceIndex = index/)
  assert.match(map, /cameraIdle[\s\S]{0,160}refreshPlaceLabelVisibility/)
  assert.match(map, /for \(const other of accepted\)/)
})

test('named sites have a larger map-click hit target than the marker icon', () => {
  assert.match(map, /const PLACE_TAP_RADIUS_VP: number = 44/)
  assert.match(map, /private nearestPlaceAt\(position: mapCommon\.LatLng\): number/)
  assert.match(map, /const nearbyPlace = this\.nearestPlaceAt\(position\)/)
  assert.match(map, /this\.selectedPlaceIndex = nearbyPlace/)
  assert.match(map, /await this\.chooseNamedPlace\(this\.placeMarkerPlaces\[nearbyPlace\]\)/)
  assert.match(map, /clickable: false/)
  assert.doesNotMatch(map, /addMarker\(\{ position: point, icon: icon \}\)/)
  const icon = readFileSync(new URL(
    '../harmonyos/ets-source/resources/base/media/ic_map_dot.svg', import.meta.url), 'utf8')
  assert.match(icon, /width="32" height="32"/)
})

test('atmosphere wheels are app-themed and support negative temperatures', () => {
  assert.doesNotMatch(observationAid, /Slider\(/)
  assert.doesNotMatch(observationAid, /showTextPickerDialog/)
  // Custom overlay instead of the system dialog, so light system themes do not
  // produce white-on-white and night mode can use the app's red text.
  assert.match(observationAid, /bindContentCover\(this\.editorOpen, this\.editorCover\)/)
  assert.match(observationAid, /TextPicker\(\{ range: range, selected: selected \}\)/)
  assert.match(observationAid, /selectedTextStyle\(\{ color: this\.c\.text/)
  // The sign is merged into the temperature whole-value wheel; "-0" keeps
  // negative fractions such as -0.5 selectable.
  assert.doesNotMatch(observationAid, /tempSign/)
  assert.match(observationAid, /temperatureRange\.push\('-0'\)/)
  assert.match(observationAid, /this\.wheelColumn\(this\.tempWholeRange, this\.tempWholeIndex, 'tempWhole'\)/)
  assert.match(observationAid, /this\.tempFracIndex/)
  assert.match(observationAid, /return this\.c\.isNight \? '#150505' : '#101E2C'/)
  assert.match(observationAid, /private openEditor\(target: string\): void/)
  // 海拔推算 / 气压计实测与位置面板共用同一组件。
  assert.match(observationAid, /import \{ PlaceEnvironmentSection \} from '\.\.\/location\/PlaceEnvironmentSection'/)
  assert.match(observationAid, /PlaceEnvironmentSection\(\{/)
  assert.match(observationAid, /altitude: this\.altitude/)
  assert.match(observationAid, /onApply: \(pressure: number, temperature: number\)/)
  assert.match(observationAid, /this\.onAtmosphere\(pressure, temperature, this\.atmoExtinction\)/)
})

test('atmosphere parameters persist to config.ini under the startup keys', () => {
  assert.match(native, /commandName == "setAtmosphereParams"/)
  assert.match(native, /immediateSaveNow\("landscape\/pressure_mbar", drawer->getAtmospherePressure\(\)\)/)
  assert.match(native, /immediateSaveNow\("landscape\/temperature_C", drawer->getAtmosphereTemperature\(\)\)/)
  assert.match(native, /immediateSaveNow\("landscape\/atmospheric_extinction_coefficient", drawer->getExtinctionCoefficient\(\)\)/)
})

test('view settings drop the save button and move max FOV before navigation controls', () => {
  assert.doesNotMatch(settingsPanel, /settings_save_all/)
  assert.doesNotMatch(settingsPanel, /saveAllCoreSettings/)
  const maxFov = settingsPanel.indexOf("I18n.t('settings_view_max_fov')")
  const navigation = settingsPanel.lastIndexOf("I18n.t('settings_view_navigation_controls')")
  assert.ok(maxFov >= 0 && navigation > maxFov, 'max FOV must precede the navigation controls')
  assert.match(settingsPanel, /Button\(I18n\.t\('settings_restore_defaults'\)\)/)
})

test('layer controls share the toggle-row backing and Bortle uses +/− buttons', () => {
  assert.ok((layerTabs.match(/backgroundColor\(this\.c\.bg\)\.border\(\{ width: 1, color: this\.c\.dividerSoft \}\)/g) || []).length >= 4)
  assert.match(layerTabs, /Text\('光污染等级'\)/)
  assert.match(layerTabs, /Button\('−'\)/)
  assert.match(layerTabs, /Button\('\+'\)/)
  // 银河亮度与光污染共用同一行版式：标题在左，步进控件整体靠右，中间留白。
  assert.match(layerTabs, /milkyWayBright\.toString\(\)\)[\s\S]{0,140}\.width\(40\)\.textAlign\(TextAlign\.Center\)/)
  assert.match(layerTabs, /Bortle ' \+ this\.layerViewStore\.bortleScale\)[\s\S]{0,140}\.width\(72\)\.textAlign\(TextAlign\.Center\)/)
  assert.doesNotMatch(layerTabs, /milkyWayBright\.toString\(\)[\s\S]{0,120}width\(24\)/)
  assert.equal((layerTabs.match(/Button\('−'\)\.fontSize\(15\)/g) || []).length, 2)
  assert.equal((layerTabs.match(/Button\('\+'\)\.fontSize\(15\)/g) || []).length, 2)
  assert.equal((layerTabs.match(/\}\.layoutWeight\(1\)\.justifyContent\(FlexAlign\.End\)/g) || []).length, 2)
  assert.match(layerTabs, /this\.onSetSkyDisplay\('bortleScale', Math\.max\(1, this\.layerViewStore\.bortleScale - 1\)\)/)
  assert.match(layerTabs, /this\.onSetSkyDisplay\('bortleScale', Math\.min\(9, this\.layerViewStore\.bortleScale \+ 1\)\)/)
  assert.doesNotMatch(layerTabs, /Slider\(\{ value: this\.layerViewStore\.bortleScale/)
  assert.match(layerController, /Do not refresh the whole state for bortleScale/)
  assert.match(layerController, /if \(typeof value === 'boolean' \|\| setting === 'environmentMode'\) this\.hooks\.refreshState\(\)/)
  assert.match(layerController, /enableAtmosphereLayer\(\): void/)
  assert.match(layerController, /this\.port\.requestInteractive\('setActionChecked', 'actionShow_Atmosphere\|1'/)
})
