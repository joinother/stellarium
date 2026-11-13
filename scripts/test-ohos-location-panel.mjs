import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const host = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const controller = readFileSync(
  new URL('../harmonyos/ets-source/capability/LocationController.ets', import.meta.url), 'utf8');
const picker = readFileSync(
  new URL('../harmonyos/ets-source/panels/location/LocationPickerPanel.ets', import.meta.url), 'utf8');
const actions = readFileSync(
  new URL('../harmonyos/ets-source/common/derive/actions.ets', import.meta.url), 'utf8');
const store = readFileSync(
  new URL('../harmonyos/ets-source/state/LocationStore.ets', import.meta.url), 'utf8');
const pickerStore = readFileSync(
  new URL('../harmonyos/ets-source/state/LocationPickerStore.ets', import.meta.url), 'utf8');
const searchPanel = readFileSync(
  new URL('../harmonyos/ets-source/panels/location/LocationSearchPanel.ets', import.meta.url), 'utf8');
const place = readFileSync(
  new URL('../harmonyos/ets-source/panels/panels/PlacePanel.ets', import.meta.url), 'utf8');
const chips = readFileSync(
  new URL('../harmonyos/ets-source/panels/location/CityChipsRow.ets', import.meta.url), 'utf8');
const shell = readFileSync(
  new URL('../harmonyos/ets-source/panels/shell/HarmonyShell.ets', import.meta.url), 'utf8');
const shellHeader = readFileSync(
  new URL('../harmonyos/ets-source/panels/shell/PanelHeader.ets', import.meta.url), 'utf8');
const more = readFileSync(
  new URL('../harmonyos/ets-source/panels/panels/MorePanel.ets', import.meta.url), 'utf8');
const locationPort = readFileSync(
  new URL('../harmonyos/ets-source/bridge/LocationPort.ets', import.meta.url), 'utf8');
const fullScreen = readFileSync(
  new URL('../harmonyos/ets-source/panels/location/LocationFullScreenMap.ets', import.meta.url), 'utf8');
const sessionSections = readFileSync(
  new URL('../harmonyos/ets-source/panels/astro/SessionToolSections.ets', import.meta.url), 'utf8');
const labels = readFileSync(
  new URL('../harmonyos/ets-source/common/derive/labels.ets', import.meta.url), 'utf8');
const reverseName = readFileSync(
  new URL('../harmonyos/ets-source/common/location/ReverseGeocodeName.ets', import.meta.url), 'utf8');
const models = readFileSync(
  new URL('../harmonyos/ets-source/common/types/MainWindowModels.ets', import.meta.url), 'utf8');

test('GPS asks for a precise single fix so altitude is available', () => {
  assert.match(host, /locatingPriority: geoLocationManager\.LocatingPriority\.PRIORITY_ACCURACY/);
  assert.match(host, /locatingTimeoutMs:\s*10000/);
  assert.match(host, /results\[1\] === 0/);
  assert.match(host, /return 'precise'/);
  assert.match(host, /\[gps\] fix lat=/);
  assert.match(controller, /permission !== 'precise'/);
  assert.match(controller, /m_gps_precise_required/);
});

test('panel dragging and scrolling disable the expensive backdrop blur and shadow', () => {
  assert.match(host, /@State private panelDragging: boolean = false/);
  assert.match(host, /@State private panelScrolling: boolean = false/);
  assert.match(host, /@State private panelTouching: boolean = false/);
  assert.match(host, /private panelChromeBusy\(\): boolean \{\s*return this\.panelDragging \|\| this\.panelScrolling\s*\}/);
  assert.match(host, /backdropBlur\(this\.panelChromeBusy\(\) \? 0 : 30\)/);
  assert.match(host, /shadow\(\{ radius: this\.panelChromeBusy\(\) \? 0 : 30/);
  assert.match(host, /shadow\(\{ radius: this\.panelChromeBusy\(\) \? 0 : 34/);
  assert.match(host, /animation\(\{ duration: \(this\.panelChromeBusy\(\) \|\| this\.panelTouching\) \? 0 : 320/);
  assert.match(host, /this\.panelTouching = true[\s\S]{0,160}this\.resetPanelIdle\(\)/);
  assert.match(host, /if \(!this\.panelDragging\) this\.panelDragging = true/);
  assert.match(host, /onFinish: \(\) => \{ this\.panelDragging = false \}/);
  assert.match(host, /\.onScrollStart\(\(\) => \{ if \(!this\.panelScrolling\) this\.panelScrolling = true \}\)/);
  assert.match(host, /\.onScrollStop\(\(\) => \{ this\.panelScrolling = false \}\)/);
  assert.match(host, /this\.panelScrolling = false\s*\n\s*this\.panelTouching = false\s*\n\s*\/\/ 时间面板首帧/);
});

test('location search folding avoids ICU-backed locale lowercasing', () => {
  assert.match(actions, /export function normalizeLocationSearchText\(value: string\): string \{\s*\/\/[\s\S]*?const lowered = value\.toLowerCase\(\)/);
  assert.doesNotMatch(actions, /toLocaleLowerCase/);
});

test('location search scans on demand instead of warming an index', () => {
  assert.doesNotMatch(store, /warmLocationSearchIndex/);
  assert.doesNotMatch(store, /buildLocationSearchIndex/);
  assert.doesNotMatch(store, /LocationSearchEntry/);
  assert.doesNotMatch(searchPanel, /warmLocationSearchIndex/);
  assert.match(actions, /export function foldLocationSearchText\(value: string\): string/);
  assert.match(actions, /const LOCATION_FOLD_CACHE: Map<string, string>/);
  assert.match(actions, /export function locationFieldScore\(folded: string, query: string, best: number\)/);
  assert.match(store, /foldLocationSearchText\(q\)/);
  assert.match(store, /locationFieldScore\(foldLocationSearchText\(city\.n\)/);
  assert.match(store, /locationSearchScanChinese/);
  assert.match(pickerStore, /locationDisplayNameForSearch/);
  assert.match(pickerStore, /locationSearchCountryNameForSearch/);
});

test('location translations cache per-language maps and country names', () => {
  assert.match(pickerStore, /let regionMapCache: Record<string, string> \| null = null/);
  assert.match(pickerStore, /private regionNameMap\(\): Record<string, string>/);
  assert.match(pickerStore, /const COUNTRY_DISPLAY_CACHE: Map<string, string>/);
  assert.doesNotMatch(pickerStore, /const regionMap: Record<string, string> = \{/);
});

test('map overview is read-only and opens the full-screen picker', () => {
  assert.doesNotMatch(picker, /handleLocationMapClick/);
  assert.doesNotMatch(picker, /handleLocationMapTouch/);
  assert.doesNotMatch(picker, /mapTouchMoved/);
  assert.match(picker, /LocationOverviewCard/);
  assert.match(picker, /onOpenFullMap/);
});

test('picker uses search/map/region tabs and removes duplicate coordinates', () => {
  assert.match(picker, /loc_tab_search/);
  assert.match(picker, /loc_tab_map/);
  assert.match(picker, /loc_tab_region/);
  assert.match(picker, /locationPickMode === 'search'/);
  assert.match(picker, /locationPickMode === 'map'/);
  assert.match(picker, /locationPickMode === 'hierarchy'/);
  // The picker defaults to the map tab and resets to it when the panel opens.
  assert.match(pickerStore, /locationPickMode: string = 'map'/);
  assert.match(place, /aboutToAppear\(\)[\s\S]{0,400}locationPickMode = 'map'/);
  // Applied coordinates live once in the two label/value rows; altitude is
  // folded into the coordinate line.
  assert.doesNotMatch(picker, /pickerCoordinateText/);
  assert.doesNotMatch(place, /CurrentObserverCard/);
  assert.match(place, /I18n\.t\('i0014'\)/);
  assert.match(place, /I18n\.t\('i0015'\)/);
  assert.match(place, /coordinateText \+ \(this\.altitudeText/);
  // GPS moved to the panel title bar, immediately left of the close button.
  assert.match(host, /activePanel === 'place'[\s\S]{0,220}I18n\.t\('i0052'\)/);
  assert.match(host, /activePanel === 'place' && this\.sessionToolStore\.observerPlanet === 'Earth'[\s\S]{0,160}useDeviceLocation/);
  assert.match(host, /headerActionAccent: this\.activePanel === 'place'/);
  assert.match(shellHeader, /headerActionAccent/);
  assert.match(shellHeader, /this\.headerActionAccent \? this\.c\.accent : this\.c\.input/);
  assert.match(shellHeader, /this\.headerActionAccent \? this\.c\.onAccent : this\.c\.text/);
  assert.match(shellHeader, /id\('panel-header-action'\)[\s\S]{0,900}id\('panel-close'\)/);
});

test('non-Earth altitude is read-only and Earth altitude is clamped', () => {
  assert.match(picker, /\.enabled\(this\.isEarth\(\)\)/);
  assert.match(picker, /EARTH_ALTITUDE_MIN/);
  assert.match(picker, /EARTH_ALTITUDE_MAX/);
  assert.match(picker, /loc_altitude_non_earth/);
  assert.match(controller, /EARTH_ALTITUDE_MIN/);
  assert.match(controller, /EARTH_ALTITUDE_MAX/);
  assert.match(controller, /Math\.max\(LocationController\.EARTH_ALTITUDE_MIN/);
});

test('saved locations carry coordinates and support rename, delete and recent use', () => {
  assert.match(chips, /recentLocations/);
  assert.match(chips, /renameSavedLocation/);
  assert.match(chips, /deleteSavedLocation|onDeleteLocation/);
  assert.match(chips, /savedLocationKey/);
  assert.match(chips, /LongPressGesture/);
  assert.match(chips, /loc_delete_confirm/);
  assert.match(store, /recordRecentLocation/);
  assert.match(store, /renameSavedLocation/);
  assert.match(store, /recentLocations/);
  // Saved entries are a vertical, scrollable list (not a full-length chip bar)
  // and the newest save goes first.
  assert.match(chips, /savedRow/);
  assert.match(chips, /ScrollDirection\.Vertical/);
  assert.match(chips, /this\.store\.savedLocations\.length \* 52/);
  assert.match(store, /this\.savedLocations = \[item, \.\.\.this\.savedLocations\]/);
  // The hardcoded China/world city chips are gone.
  assert.doesNotMatch(chips, /Text\('中国城市'\)/);
  assert.doesNotMatch(chips, /Text\('世界城市'\)/);
  assert.doesNotMatch(chips, /city_Beijing/);
  assert.doesNotMatch(chips, /city_Tokyo/);
});

test('online map picks use the smallest reverse-geocoded administrative division', () => {
  assert.match(fullScreen, /smallestAdminDivision/);
  assert.match(reverseName, /adminLevel5/);
  assert.match(reverseName, /adminLevel4/);
  assert.match(reverseName, /adminLevel3/);
  assert.match(reverseName, /adminLevel2/);
  assert.match(reverseName, /adminLevel1/);
  // The pick card shows one short admin name, not a street/address string.
  assert.doesNotMatch(fullScreen, /streetNumber\?\.streetName/);
  assert.doesNotMatch(fullScreen, /neighborhoods\[0\].*return/);
  assert.match(fullScreen, /resolveName/);
  assert.match(fullScreen, /this\.selectedName = nextName/);
  // The applied label must keep the reverse-geocoded name for map picks.
  assert.match(labels, /source === 'map'[\s\S]{0,220}displayName !== I18n\.t\('custom_location'\)/);
  // Search-result names are passed explicitly and must not be overwritten by
  // the reverse geocoder (resolveName is false on that path).
  assert.match(fullScreen, /item\.name/);
  // The old explanatory line between the body selector and picker is gone.
  assert.doesNotMatch(sessionSections, /m_observer_map_hint/);
  // Saved locations are presented as a titled card with a count badge.
  assert.match(chips, /savedLocations\.length\.toString\(\)/);
  assert.match(chips, /padding\(\{ left: 10, right: 10, top: 10, bottom: 10 \}\)/);
});

test('observer planet dropdown follows night mode like the language dropdown', () => {
  assert.match(sessionSections, /stellariumNightMode/);
  assert.match(sessionSections, /menuBackgroundColor\(this\.menuBackground\(\)\)/);
  assert.match(sessionSections, /optionBgColor\(this\.menuBackground\(\)\)/);
  assert.match(sessionSections, /selectedOptionBgColor\(this\.c\.accent\)/);
  assert.match(sessionSections, /menuBackgroundBlurStyle\(BlurStyle\.NONE\)/);
});

test('saved locations persist through the preferences port', () => {
  assert.match(locationPort, /readSavedLocations/);
  assert.match(locationPort, /writeSavedLocations/);
  assert.match(host, /readSavedLocations: \(\): Promise<string> => this\.hostLocationPort\.readSavedLocations\(\)/);
  assert.match(host, /writeSavedLocations: \(json: string\)/);
  assert.match(host, /store\.put\('savedLocations', json\)/);
  assert.match(store, /hooks\.readSavedLocations\(\)/);
  assert.match(store, /hooks\.writeSavedLocations\(json\)/);
  assert.doesNotMatch(store, /AppStorage\.setOrCreate<Record<string, Object>>\('stellariumPrefs'/);
});

test('location changes use plain hints without a snackbar button', () => {
  assert.doesNotMatch(controller, /flashHintAction|loc_retry|loc_undo|appliedLocation/);
  assert.match(controller, /flashHint\(I18n\.t\('loc_apply_failed'\)\)/);
  assert.match(controller, /flashHint\(I18n\.t\('loc_gps_denied_settings'\)\)/);
  assert.match(controller, /recordRecentLocation/);
  assert.match(controller, /if \(!silent\) \{[\s\S]{0,220}flashHint\(I18n\.t\('i0073'\)/);
  assert.doesNotMatch(shell, /actionHintLabel|onHintAction/);
  assert.doesNotMatch(host, /flashHintAction|actionHintLabel/);
});

test('GPS reports accuracy and permission guidance', () => {
  assert.match(locationPort, /accuracy\?: number/);
  assert.match(controller, /current\.accuracy/);
  assert.match(controller, /current\.altitudeAccuracy/);
  assert.match(controller, /loc_gps_accuracy/);
  assert.match(controller, /loc_gps_altitude_accuracy/);
  assert.match(controller, /loc_gps_denied_settings/);
  const fullScreen = readFileSync(
    new URL('../harmonyos/ets-source/panels/location/LocationFullScreenMap.ets', import.meta.url), 'utf8');
  assert.match(fullScreen, /loc_gps_accuracy/);
  assert.match(fullScreen, /loc_gps_denied_settings/);
});

test('GPS label appends the reverse-geocoded smallest admin division', () => {
  assert.match(locationPort, /reverseGeocodePlaceName/);
  assert.match(host, /async reverseGeocodePlaceName/);
  assert.match(host, /site\.reverseGeocode/);
  assert.match(host, /smallestAdminDivision/);
  assert.match(controller, /gpsPlaceDetail/);
  assert.match(pickerStore, /gpsPlaceDetail/);
  assert.match(controller, /resolveGpsPlaceName/);
  assert.match(controller, /METERED_MAP_APIS_ENABLED/);
  assert.match(controller, /gpsNameRequestId/);
  assert.match(host, /locationPickerStore\.gpsPlaceDetail/);
  assert.match(labels, /detail: string = ''/);
  assert.match(labels, /loc_source_gps'\) \+ ' · ' \+ detail/);
});

test('GPS admin division is persisted with the observer location record', () => {
  assert.match(models, /detail\?: string/);
  assert.match(controller, /detail: this\.pickerStore\.locationSource === 'gps' \? this\.pickerStore\.gpsPlaceDetail : ''/);
  // The enrichment writes the record after the name arrives, and restore reads
  // it back before committing the observer.
  assert.match(controller, /this\.pickerStore\.gpsPlaceDetail = detail[\s\S]{0,220}saveObserverLocationToStorage/);
  assert.match(controller, /const detail = typeof rec\.detail === 'string' \? rec\.detail : ''/);
  assert.match(controller, /this\.pickerStore\.gpsPlaceDetail = source === 'gps' \? detail : ''/);
  // Legacy records without `detail` are re-resolved once after the commit.
  assert.match(controller, /restoreDetailPending/);
  assert.match(controller, /pickerAtLocation/);
});

test('developer tools use a dedicated panel while tonight stays in place', () => {
  assert.doesNotMatch(place, /PointingTestSection/);
  assert.doesNotMatch(place, /WatchGyroSection/);
  assert.match(place, /TonightEventsSection/);
  assert.doesNotMatch(more, /PointingTestSection/);
  assert.doesNotMatch(more, /WatchGyroSection/);
  const devTools = readFileSync(
    new URL('../harmonyos/ets-source/panels/panels/DevToolsPanel.ets', import.meta.url), 'utf8');
  assert.match(devTools, /PointingTestSection/);
  assert.match(devTools, /WatchGyroSection/);
  assert.match(host, /DEV_TOOLS_ENABLED && this\.activePanel === 'devTools'/);
  const actions = readFileSync(
    new URL('../harmonyos/ets-source/common/derive/actions.ets', import.meta.url), 'utf8');
  assert.match(actions, /DEV_TOOLS_ENABLED/);
  assert.match(actions, /panel: 'devTools'/);
});
