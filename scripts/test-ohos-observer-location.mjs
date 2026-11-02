import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const plain = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/^@Observed\r?\n/gm, '').replaceAll('export ', ''));
const translate = { t: key => key };
const storage = new Map();
const Controller = new Function('I18n', 'hilog', 'AppStorage', 'planetZh', 'quickLocationLabel', 'approximateTimeZoneDisplay',
  `${plain(read('harmonyos/ets-source/capability/LocationController.ets'))}; return LocationController;`)(
  translate, { info() {}, warn() {} }, { setOrCreate: (key, value) => storage.set(key, value) }, name => name,
  (source, name) => name, () => 'system');
const Store = new Function('I18n', 'planetZh',
  `${plain(read('harmonyos/ets-source/state/SessionToolStore.ets'))}; return SessionToolStore;`)(translate, name => name);

function fixture(planet = 'Moon') {
  const requests = [];
  const writes = [];
  const hints = [];
  const picker = {
    locationPickerName: 'Site', locationPickerLatitude: 12, locationPickerLongitude: 34,
    locationPickerAltitude: 15, locationSource: 'map', hierCity: 'Old city',
    setPickerLocation(name, latitude, longitude, altitude) {
      Object.assign(this, { locationPickerName: name, locationPickerLatitude: latitude,
        locationPickerLongitude: longitude, locationPickerAltitude: altitude });
    },
    locationDisplayName: name => name
  };
  const locations = { locationMapProvider: 'huawei', locSearchQuery: 'Earth city',
    searchLocations(query) { this.locSearchQuery = query; }, formatDegrees: value => String(value) };
  const session = { observerPlanet: planet, observerPlanetPending: false };
  const port = {
    requestWhenReady: (name, payload, success, failure) => requests.push({ name, payload, success, failure }),
    requestInteractive: (name, payload, success) => requests.push({ name, payload, success })
  };
  let persisted = '';
  const controller = new Controller(port, {
    writeObserverLocation: async json => writes.push(JSON.parse(json)),
    readObserverLocation: async () => persisted
  }, picker, locations, session, {
    flashHint: text => hints.push(text), refreshState() {}, loadObserverInfo() {},
    setObserverPlanetCrossStore: name => { session.observerPlanet = name; }, setLocationTexts() {},
    privacyAllowed: () => true, inForeground: () => true, hasPrivacyConsent: () => true
  });
  return { controller, picker, locations, session, requests, writes, hints,
    persist: record => { persisted = JSON.stringify(record); } };
}

test('applying the map retains the selected extraterrestrial observer', () => {
  for (const planet of ['Moon', 'Mars', 'Venus']) {
    const context = fixture(planet);
    context.controller.applyPickerLocation();
    assert.equal(context.requests[0].name, 'setObserverPlanet');
    assert.equal(context.requests[0].payload, `${planet}|12|34|15|Site`);
    assert.deepEqual(context.writes, []);
    context.requests[0].success({ ok: true });
    assert.equal(context.writes[0].planet, planet);
    assert.equal(context.session.observerPlanetPending, false);
  }
});

test('switches are serialized and only native success commits or persists a destination', () => {
  for (const callback of ['success', 'failure']) {
    const context = fixture('Earth');
    context.controller.setObserverPlanet('Mars');
    context.controller.setObserverPlanet('Venus');
    assert.equal(context.requests.length, 1);
    assert.equal(context.session.observerPlanet, 'Earth');
    assert.equal(context.session.observerPlanetPending, true);
    context.requests[0][callback]({ ok: false });
    assert.equal(context.session.observerPlanet, 'Earth');
    assert.equal(context.session.observerPlanetPending, false);
    assert.deepEqual(context.writes, []);
    assert.equal(context.hints.length, 1);
  }
});

test('success uses actual native coordinates and clears Earth-only state when leaving Earth', () => {
  const context = fixture('Earth');
  context.controller.setObserverPlanet('Mars');
  context.requests[0].success({ ok: true, planetName: 'Mars', locationName: 'Landing site', latitude: 11,
    longitude: 22, altitude: 33 });
  assert.deepEqual(context.writes[0], { name: 'Landing site', planet: 'Mars', latitude: 11,
    longitude: 22, altitude: 33, source: 'map' });
  assert.equal(context.locations.locationMapProvider, 'offline');
  assert.equal(context.locations.locSearchQuery, '');
  assert.equal(context.picker.hierCity, '');
});

test('floating GPS altitude is normalized to native integer meters and site separators are escaped', () => {
  const context = fixture();
  context.controller.setLocation('A|B', 12, 34, 15.8, 'Earth', false, 'gps');
  assert.equal(context.requests[0].payload, 'Earth|12|34|16|A B');
  context.requests[0].success({ ok: true });
  assert.equal(context.writes[0].altitude, 16);
  assert.equal(context.writes[0].source, 'gps');
});

test('invalid coordinates cannot reach the native bridge or persistence', () => {
  for (const [latitude, longitude] of [[NaN, 0], [91, 0], [0, 181], [0, Infinity]]) {
    const context = fixture();
    context.controller.setLocation('Invalid', latitude, longitude, 0, 'Earth');
    assert.deepEqual(context.requests, []);
    assert.deepEqual(context.writes, []);
  }
});

test('restoring an extraterrestrial saved point never routes it through Earth', async () => {
  const context = fixture('Earth');
  context.persist({ name: 'Moon base', planet: 'Moon', latitude: -5, longitude: 20, altitude: 100, source: 'map' });
  await context.controller.restoreObserverLocation();
  assert.equal(context.requests[0].payload, 'Moon|-5|20|100|Moon base');
  context.requests[0].success({ ok: true });
  assert.equal(context.writes[0].planet, 'Moon');
  assert.deepEqual(context.hints, []);
});

test('the Earth online map cannot be activated while observing another body', () => {
  const context = fixture();
  context.locations.locationMapProvider = 'offline';
  context.controller.setLocationMapProvider('huawei');
  assert.equal(context.locations.locationMapProvider, 'offline');
  context.session.observerPlanet = 'Earth';
  context.controller.setLocationMapProvider('huawei');
  assert.equal(context.locations.locationMapProvider, 'huawei');
});

test('engine enumeration retains Mercury, Venus and moons, using localized names and safe bundled maps', () => {
  const store = new Store();
  store.attachPort({ requestInteractive: (command, payload, success) => success({ ok: true,
    planets: ['Earth', 'Mercury', 'Venus', 'Io'], observerPlanets: [
      { name: 'Io', displayName: '木卫一', mapTexture: 'io.png' },
      { name: 'Venus', displayName: '金星', mapTexture: '../secret.png' }
    ] }) }, () => {});
  store.loadPlanetList();
  assert.deepEqual(store.planetList, ['Earth', 'Mercury', 'Venus', 'Io']);
  assert.equal(store.observerPlanetLabel('Io'), '木卫一');
  store.observerPlanet = 'Io';
  assert.equal(store.observerPlanetMapTexture(), 'io.png');
  store.observerPlanet = 'Venus';
  assert.equal(store.observerPlanetMapTexture(), '');
});
