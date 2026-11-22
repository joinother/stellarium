import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const root = new URL('../', import.meta.url);
const read = (file) => readFileSync(new URL('harmonyos/ets-source/' + file, root), 'utf8');

async function sourceModule(relativePath) {
  const source = read(relativePath).replace(/^import .*$/gm, '');
  return import('data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source)));
}

const { wgs84ToGcj02Point } = await sourceModule('common/location/LocationShareLink.ets');

test('Amap and Baidu links receive GCJ02 destination coordinates', () => {
  // Amap/Baidu deep links require GCJ-02; Stellarium stores WGS84.
  const gcj = wgs84ToGcj02Point(31.2304, 121.4737);
  assert.ok(Math.abs(gcj[0] - 31.22845773757727) < 0.00001, String(gcj[0]));
  assert.ok(Math.abs(gcj[1] - 121.47822305927693) < 0.00001, String(gcj[1]));

  // Outside the GCJ02 region the function is the identity transform.
  const outside = wgs84ToGcj02Point(48.8566, 2.3522);
  assert.equal(outside[0], 48.8566);
  assert.equal(outside[1], 2.3522);
});

test('route planning uses the unified system navigation panel', () => {
  const host = read('pages/MainWindowNativeNode.ets');
  assert.match(host, /private launchRoutePlanningSystemPanel\(\): void/);
  assert.match(host, /startAbilityByType\('navigation'/);
  assert.match(host, /'sceneType': 1/);
  assert.match(host, /'destinationName': name/);
  assert.match(host, /'destinationLatitude': gcj\[0\]/);
  assert.match(host, /'destinationLongitude': gcj\[1\]/);
  assert.match(host, /'vehicleType': 0/);
  assert.match(host, /wgs84ToGcj02Point\(latitude, longitude\)/);
  // Per-app route links and route rows are gone.
  assert.doesNotMatch(host, /openMapRoutePlan|openRouteInPetalMaps|openRouteInAmap|openRouteInBaiduMaps/);
  assert.doesNotMatch(host, /amapuri:\/\/route|baidumap:\/\/map\/direction/);
});

test('view place keeps Petal/Baidu adapters and a geo system outlet', () => {
  const host = read('pages/MainWindowNativeNode.ets');
  // Petal: Map Kit POI detail with WGS84 coordinates.
  assert.match(host, /petalMaps\.openMapPoiDetail\(context, \{/);
  assert.match(host, /coordinateType: mapCommon\.CoordinateType\.WGS84/);
  // Baidu: GCJ-02 marker link.
  assert.match(host, /'baidumap:\/\/map\/marker\?location='/);
  assert.match(host, /'&coord_type=gcj02&src=skyinstrument'/);
  // Other apps: geo: URI handed to the system "open with" chooser (WGS84).
  // Petal Maps renders percent escapes literally in the title, so the label
  // must stay unencoded.
  const otherFn = host.match(/private openPlaceInOtherMaps\([\s\S]*?\n  \}/)?.[0] ?? '';
  assert.match(otherFn, /'geo:' \+ point \+ '\?q=' \+ point/);
  assert.match(otherFn, /'\(' \+ label \+ '\)'/);
  assert.doesNotMatch(otherFn, /encodeURIComponent/);
  // No dedicated Amap/Ovital branches.
  assert.doesNotMatch(host, /openPlaceInAmap|openPlaceInOvital|amapuri:\/\/viewMap|ovitalMapHm/);
});

test('all map entry points open the in-app share sheet directly', () => {
  const place = read('panels/panels/PlacePanel.ets');
  assert.match(place, /id\('loc-open-map-current'\)/);
  assert.match(place, /sys\.symbol\.share/);
  // 系统线形符号用 600 字重，与 Dock/面板的实心 SVG 图标保持同一粗细。
  assert.match(place, /SymbolGlyph\(\$r\('sys\.symbol\.share'\)\)\.fontSize\(17\)\.fontWeight\(600\)/);
  assert.match(place, /onClick\(\(\) => \{ this\.onShareCurrent\(\) \}\)/);
  assert.doesNotMatch(place, /bindPopup|MapActionMenu|mapMenuOpen/);

  const fullScreen = read('panels/location/LocationFullScreenMap.ets');
  assert.match(fullScreen, /id\('loc-open-map-selected'\)/);
  assert.match(fullScreen, /onClick\(\(\) => \{ this\.shareSelected\(\) \}\)/);
  assert.doesNotMatch(fullScreen, /bindPopup|MapActionMenu|mapMenuOpen/);

  const chips = read('panels/location/CityChipsRow.ets');
  assert.match(chips, /id\('loc-open-map-saved'\)/);
  assert.match(chips, /onClick\(\(\) => \{ this\.shareForAction\(\) \}\)/);
  assert.doesNotMatch(chips, /bindPopup|MapActionMenu|mapMenuOpen/);

  // The host draws the large share sheet: route card is an action, view rows
  // are the installed Petal/Baidu/other-geo entries.
  const host = read('pages/MainWindowNativeNode.ets');
  assert.match(host, /mapActionPickerOpen: boolean/);
  assert.match(host, /mapActionPickerApps: MapAppEntry\[\]/);
  assert.match(host, /mapPickerCapability\('route'/);
  assert.match(host, /mapPickerCapability\('view'/);
  // 大弹窗的两个能力卡片与查看应用行同样使用 600 字重。
  assert.match(host, /SymbolGlyph\(icon\)[\s\S]{0,160}\.fontWeight\(600\)/);
  assert.match(host, /SymbolGlyph\(app\.iconSymbol\)[\s\S]{0,80}\.fontWeight\(600\)/);
  assert.match(host, /id\('map-app-mode-' \+ id\)/);
  assert.match(host, /loc_map_share_title/);
  assert.match(host, /ForEach\(this\.mapViewApps\(\)/);
  assert.match(host, /launchPlaceAction\(app\.id\)/);
  assert.match(host, /map-app-' \+ app\.id/);
  // 返回手势先关闭分享大弹窗，再处理弹窗下面的面板。
  assert.match(host, /if \(this\.mapActionPickerOpen\) \{ this\.mapActionPickerOpen = false; return \}/);
});

test('view app catalog uses bundled icons and scheme probes', () => {
  const catalog = read('common/location/MapAppCatalog.ets');
  // HarmonyOS does not expose other apps' BundleInfo/icons to third-party
  // apps; availability is probed through declared schemes instead.
  assert.match(catalog, /bundleManager\.canOpenLink/);
  assert.match(catalog, /petalmaps:\/\/poidetail/);
  assert.match(catalog, /baidumap:\/\/map\/marker/);
  assert.match(catalog, /probeLink: 'geo:\/\/maps'/);
  assert.match(catalog, /labelKey: 'loc_map_other_apps'/);
  assert.match(catalog, /iconColor: '#/);
  assert.match(catalog, /iconSymbol: \$r\('sys\.symbol\./);
  assert.match(catalog, /installed: canOpen\(spec\.probeLink\)/);
  const catalogCode = catalog.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  assert.doesNotMatch(catalogCode, /getBundleInfo|GET_BUNDLE_INFO|iconResource|PixelMap|alwaysShow/);
  // No dedicated Amap/Ovital entries.
  assert.doesNotMatch(catalog, /id: 'amap'|id: 'ovital'|amapuri|ovitalMapHm/);

  const moduleJson = readFileSync(new URL('harmonyos/module.json5', root), 'utf8');
  assert.match(moduleJson, /"querySchemes": \[[\s\S]*?"petalmaps"[\s\S]*?"baidumap"[\s\S]*?"geo"/);
  assert.doesNotMatch(moduleJson, /ohos\.permission\.GET_BUNDLE_INFO/);
});

test('map menu copy is localized and has no direct-guidance entry', () => {
  const i18n = read('capability/I18n.ets');
  assert.match(i18n, /'loc_map_actions': \{[^}]*'zh_CN': '地图与导航'/);
  assert.match(i18n, /'loc_map_route_plan': \{[^}]*'zh_CN': '规划路线'/);
  assert.match(i18n, /'loc_map_view_place': \{[^}]*'zh_CN': '查看地点'/);
  assert.match(i18n, /'loc_map_share_title': \{[^}]*'zh_CN': '分享位置'/);
  assert.match(i18n, /'map_app_petal': \{[^}]*'zh_CN': '花瓣地图'/);
  assert.match(i18n, /'map_app_baidu': \{[^}]*'zh_CN': '百度地图'/);
  assert.match(i18n, /'loc_map_other_apps': \{[^}]*'zh_CN': '其他支持的应用'/);
  assert.match(i18n, /'loc_map_unavailable': \{[^}]*'zh_CN':/);
  assert.doesNotMatch(i18n, /'loc_map_start_navigation'|'loc_map_petal_detail'|'loc_map_baidu_detail'|'loc_map_picker_|'map_app_amap'|'map_app_ovital'/);
});
