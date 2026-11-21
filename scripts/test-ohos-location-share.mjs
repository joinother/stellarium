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

const { parseSharedLocationText } = await sourceModule('common/location/LocationShareLink.ets');

test('standard geo URIs become an observer point with a display name', () => {
  const point = parseSharedLocationText('geo:39.9042,116.4074?q=39.9042,116.4074(天安门)');
  assert.ok(point);
  assert.equal(point.name, '天安门');
  assert.equal(point.latitude, 39.9042);
  assert.equal(point.longitude, 116.4074);
  assert.equal(point.planet, 'Earth');
  assert.equal(point.source, 'share');

  const zeroBase = parseSharedLocationText('geo:0,0?q=39.9945,116.1925(香山公园)');
  assert.ok(zeroBase);
  assert.equal(zeroBase.name, '香山公园');
  assert.equal(zeroBase.latitude, 39.9945);
  assert.equal(zeroBase.longitude, 116.1925);
});

test('the app deep link accepts query and path forms plus altitude', () => {
  const query = parseSharedLocationText('skyinstrument://location?lat=31.2304&lon=121.4737&name=外滩&alt=8');
  assert.ok(query);
  assert.equal(query.name, '外滩');
  assert.equal(query.latitude, 31.2304);
  assert.equal(query.longitude, 121.4737);
  assert.equal(query.altitude, 8);

  const path = parseSharedLocationText('skyinstrument://location/31.2304,121.4737?name=外滩');
  assert.ok(path);
  assert.equal(path.name, '外滩');

  const clamped = parseSharedLocationText('skyinstrument://location?lat=10&lon=20&alt=12000');
  assert.ok(clamped);
  assert.equal(clamped.altitude, 9000);
});

test('map web links and their common coordinate fields are parsed', () => {
  const ll = parseSharedLocationText('https://maps.example.com/?ll=39.9042,116.4074&q=北京');
  assert.ok(ll);
  assert.equal(ll.name, '北京');
  assert.equal(ll.latitude, 39.9042);

  const at = parseSharedLocationText('https://www.google.com/maps/@39.9042,116.4074,15z');
  assert.ok(at);
  assert.equal(at.latitude, 39.9042);
  assert.equal(at.longitude, 116.4074);

  const place = parseSharedLocationText('https://www.google.com/maps/place/X/data=!3d39.9042!4d116.4074');
  assert.ok(place);
  assert.equal(place.latitude, 39.9042);
  assert.equal(place.longitude, 116.4074);

  // Petal Maps web share uses marker=lat,lon; coordinateType=0 is WGS84.
  const petalWeb = parseSharedLocationText('https://www.petalmaps.com/place/?marker=31.2304,121.4737&placeId=x&z=16&coordinateType=0');
  assert.ok(petalWeb);
  assert.equal(petalWeb.latitude, 31.2304);
  assert.equal(petalWeb.longitude, 121.4737);

  // Petal share links omit coordinateType, which means GCJ02: 外滩 WGS84
  // 31.2304,121.4737 is shared as GCJ02 31.2273778,121.4782231.
  const petalGcj = parseSharedLocationText('https://www.petalmaps.com/place/?z=17&marker=31.22845773757727,121.47822305927693&placeId=452155024294691328&utm_campaign=poi_share&utm_source=share#/');
  assert.ok(petalGcj);
  assert.ok(Math.abs(petalGcj.latitude - 31.2304) < 0.00001, String(petalGcj.latitude));
  assert.ok(Math.abs(petalGcj.longitude - 121.4737) < 0.00001, String(petalGcj.longitude));

  // Amap URI API uses position=lon,lat.
  const amapWeb = parseSharedLocationText('https://uri.amap.com/marker?position=121.4737,31.2304&name=外滩&coordinate=gaode');
  assert.ok(amapWeb);
  assert.equal(amapWeb.name, '外滩');
  assert.equal(amapWeb.latitude, 31.2304);
  assert.equal(amapWeb.longitude, 121.4737);
});

test('native map-app deep links from Petal, Amap and Baidu are parsed', () => {
  const petal = parseSharedLocationText('maps://locationInfo?destinationLatitude=31.2304&destinationLongitude=121.4737&destinationName=外滩&coordinateType=0');
  assert.ok(petal);
  assert.equal(petal.name, '外滩');
  assert.equal(petal.latitude, 31.2304);

  const petalNative = parseSharedLocationText('petalmaps://poidetail?marker=31.22845773757727,121.47822305927693&z=17');
  assert.ok(petalNative);
  assert.ok(Math.abs(petalNative.latitude - 31.2304) < 0.00001, String(petalNative.latitude));
  assert.ok(Math.abs(petalNative.longitude - 121.4737) < 0.00001, String(petalNative.longitude));

  const amap = parseSharedLocationText('amapuri://viewMap?sourceApplication=x&poiname=外滩&lat=31.2304&lon=121.4737&dev=0');
  assert.ok(amap);
  assert.equal(amap.name, '外滩');
  assert.equal(amap.latitude, 31.2304);
  assert.equal(amap.longitude, 121.4737);

  const baidu = parseSharedLocationText('baidumap://map/marker?location=31.2304,121.4737&title=外滩&coord_type=gcj02&src=x');
  assert.ok(baidu);
  assert.equal(baidu.name, '外滩');
  assert.equal(baidu.latitude, 31.2304);
  assert.equal(baidu.longitude, 121.4737);
});

test('plain shared text recognizes labelled, directional and bare coordinate pairs', () => {
  const labelled = parseSharedLocationText('香山公园\n纬度 39.9945 经度 116.1925');
  assert.ok(labelled);
  assert.equal(labelled.name, '香山公园');
  assert.equal(labelled.latitude, 39.9945);
  assert.equal(labelled.longitude, 116.1925);

  const directional = parseSharedLocationText('N39.9945 E116.1925');
  assert.ok(directional);
  assert.equal(directional.latitude, 39.9945);
  assert.equal(directional.longitude, 116.1925);

  const suffixed = parseSharedLocationText('39.9945°N, 116.1925°E');
  assert.ok(suffixed);
  assert.equal(suffixed.latitude, 39.9945);
  assert.equal(suffixed.longitude, 116.1925);

  const bare = parseSharedLocationText('39.994500,116.192500');
  assert.ok(bare);
  assert.equal(bare.latitude, 39.9945);
  assert.equal(bare.longitude, 116.1925);
  assert.equal(bare.name, '');

  // A "位置：" line that only contains the coordinate pair must not become the name.
  const labelledPair = parseSharedLocationText('我在天安门\n位置：39.9042, 116.4074');
  assert.ok(labelledPair);
  assert.equal(labelledPair.name, '我在天安门');
});

test('unusable or out-of-range shares are rejected', () => {
  assert.equal(parseSharedLocationText(''), null);
  assert.equal(parseSharedLocationText('hello world'), null);
  assert.equal(parseSharedLocationText('geo:0,0?q=天安门'), null);
  assert.equal(parseSharedLocationText('geo:95,200'), null);
  assert.equal(parseSharedLocationText('skyinstrument://location?lat=91&lon=0'), null);
});

test('share intent is registered and routed into the observer pipeline', () => {
  const qability = read('qability/QAbility.ets');
  assert.match(qability, /queueLocationShareWant/);
  assert.match(qability, /systemShare\.getSharedData\(want\)/);
  assert.match(qability, /AppStorage\.setOrCreate\('stellariumLocationShare'/);
  assert.match(qability, /parseSharedLocationText/);
  assert.equal((qability.match(/this\.queueLocationShareWant\(want\)/g) ?? []).length, 2);

  const moduleJson = readFileSync(new URL('harmonyos/module.json5', root), 'utf8');
  assert.match(moduleJson, /"utd": "general\.text"/);
  assert.match(moduleJson, /"utd": "general\.hyperlink"/);
  assert.match(moduleJson, /"scheme": "skyinstrument"/);
  // `geo:` remains a share-text input, but the app does not register the scheme:
  // doing so would let the Stellarium → map fallback route back into Stellarium.
  assert.doesNotMatch(moduleJson, /"scheme": "geo"/);

  const host = read('pages/MainWindowNativeNode.ets');
  assert.match(host, /@StorageLink\('stellariumLocationShare'\)/);
  assert.match(host, /private consumeSharedLocation\(\): void/);
  assert.match(host, /this\.consumeSharedLocation\(\)/);
  assert.match(host, /this\.setPanel\('', true, true\)/);
  assert.match(host, /setLocation\(name, latitude, longitude, altitude, 'Earth', false, 'share'\)/);
  assert.match(host, /loc_share_unrecognized/);
});

test('Stellarium opens Petal Maps at the precise place without navigation', () => {
  const host = read('pages/MainWindowNativeNode.ets');
  assert.match(host, /petalMaps\.openMapPoiDetail\(context/);
  assert.match(host, /coordinateType: mapCommon\.CoordinateType\.WGS84/);
  assert.match(host, /loc_map_unavailable/);
  // Only Petal is integrated for now; no chooser, no Amap/Baidu schemes, and
  // no route planning / turn-by-turn navigation initiated by Stellarium.
  assert.doesNotMatch(host, /showActionMenu|amapuri|baidumap|openMapNavi|openMapRoutePlan|sceneType/);
  assert.doesNotMatch(host, /vehicleType|bundleManager/);

  const moduleJson = readFileSync(new URL('harmonyos/module.json5', root), 'utf8');
  assert.doesNotMatch(moduleJson, /"querySchemes"/);

  const place = read('panels/panels/PlacePanel.ets');
  assert.match(place, /onNavigateCurrent/);
  assert.match(place, /id\('loc-open-map-current'\)/);
  assert.match(place, /loc_open_current_in_map/);
  assert.match(place, /onNavigateLocation/);

  const fullScreen = read('panels/location/LocationFullScreenMap.ets');
  assert.match(fullScreen, /onNavigate: \(latitude: number, longitude: number, name: string\)/);
  assert.match(fullScreen, /id\('loc-open-map-selected'\)/);
  assert.match(fullScreen, /loc_open_in_map/);

  const chips = read('panels/location/CityChipsRow.ets');
  assert.match(chips, /onNavigateLocation/);
  assert.match(chips, /id\('loc-open-map-saved'\)/);
  assert.match(chips, /loc_open_in_map/);

  const i18n = read('capability/I18n.ets');
  assert.match(i18n, /'loc_open_in_map': \{[^}]*'zh_CN': '在地图中打开'/);
});
