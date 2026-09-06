import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const page = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const satellite = readFileSync(new URL('../plugins/Satellites/src/Satellite.cpp', import.meta.url), 'utf8');
const manager = readFileSync(new URL('../plugins/Satellites/src/Satellites.cpp', import.meta.url), 'utf8');
const method = name => page.match(new RegExp(`private ${name}\\([^\\n]*\\): void \\{([\\s\\S]*?)\\n  \\}`))[1];

test('group selection uses a local non-linear animation and preserves same-value state', () => {
  const select = new Function('group', 'Curve', method('selectSatelliteGroup'));
  const model = { activeSatGroup: 'visual', satGroups: ['visual', 'beidou'], calls: 0, errors: [],
    publishSatellitePanelState(error) { this.errors.push(error); },
    getUIContext() { return { animateTo: (options, change) => { assert.equal(options.duration, 180); assert.equal(options.curve, 'EaseOut'); change(); } }; },
    loadSatellites() { this.calls++; }
  };
  select.call(model, 'visual', { EaseOut: 'EaseOut' });
  assert.equal(model.calls, 0);
  select.call(model, 'beidou', { EaseOut: 'EaseOut' });
  assert.equal(model.activeSatGroup, 'beidou');
  assert.equal(model.calls, 1);
  select.call(model, 'invalid', { EaseOut: 'EaseOut' });
  assert.equal(model.activeSatGroup, 'beidou');
  assert.equal(model.errors.at(-1), 'unknown satellite group');
  select.call(model, '', { EaseOut: 'EaseOut' });
  assert.equal(model.activeSatGroup, '');
});

test('filter rows precede variable results and retain their own bounded scroll container', () => {
  const panel = page.slice(page.indexOf("} else if (this.activePanel === 'satellites')"), page.indexOf("} else if (this.activePanel === 'meteorshowers')"));
  assert.ok(panel.indexOf('this.satelliteGroupSelector()') < panel.indexOf('ForEach(this.satItems'));
  assert.match(panel, /Scroll\(this.satellitePanelScroller\)/);
  const selector = page.slice(page.indexOf('private satelliteGroupSelector()'), page.indexOf('private loadSatellites('));
  assert.match(selector, /Scroll\(this.satelliteGroupScroller\)/);
  assert.match(selector, /height\(180\)/);
  assert.match(selector, /\(group: string\) => group/);
  assert.match(selector, /opacity\(this.activeSatGroup === group \? 1 : 0\)/);
});

test('queued filtering invalidates previous results before the debounce fires', () => {
  const load = method('loadSatellites');
  assert.ok(load.indexOf('++this.satelliteListRequestId') < load.indexOf('const run'));
  assert.match(load, /requestId !== this.satelliteListRequestId/);
  assert.match(load, /flagMutationId === this.satelliteFlagMutationId/);
  assert.match(load, /this.satGroups.join\('\|'\) !== s.groups.join\('\|'\)/);
});

test('panel diagnostics remain available before scroll attachment and after closing', () => {
  const publish = new Function('error', 'AppStorage', method('publishSatellitePanelState').replaceAll(': SatelliteListItem', ''));
  const model = { satItems: [], satellitePanelScroller: { currentOffset: () => undefined },
    satelliteGroupScroller: { currentOffset: () => undefined }, satOrbitLines: false };
  let state;
  publish.call(model, '', { setOrCreate: (key, value) => { state = JSON.parse(value); } });
  assert.equal(state.scrollY, 0);
  assert.equal(state.groupScrollY, 0);
  assert.equal(state.orbitLines, false);
});

test('same-value satellite switch callbacks never dispatch native writes', () => {
  const guard = method('setSatelliteFlag').split('const mutationId')[0];
  const check = new Function('name', 'v', guard + '; return "changed";');
  const model = { satLabels: true, satOrbitLines: false, satHints: true, satIconicMode: false, satHideInvisible: true };
  for (const [name, value] of [['labels', true], ['orbitLines', false], ['hints', true], ['iconicMode', false], ['hideInvisible', true]]) {
    assert.equal(check.call(model, name, value), undefined);
    assert.equal(check.call(model, name, !value), 'changed');
  }
});

test('orbit preview does not rewrite saved per-object flags and keeps position updates parallel', () => {
  const update = manager.slice(manager.indexOf('void Satellites::update(double'), manager.indexOf('void Satellites::draw('));
  assert.match(update, /orbitPreview = !selected.isEmpty\(\)/);
  assert.doesNotMatch(update, /orbitDisplayed\s*=/);
  assert.match(update, /sat->update\(core, JD, false\)/);
  assert.ok(update.indexOf('QtConcurrent::blockingMap') < update.indexOf('sat->updateOrbitLines()'));
  assert.match(satellite, /shouldDisplayOrbit\(\) && Satellite::orbitLinesFlag && orbitValid/);
});

test('orbit samples reject failed propagation and restore the current epoch', () => {
  const sampling = satellite.slice(satellite.indexOf('void Satellite::computeOrbitPoints()'), satellite.indexOf('bool operator <'));
  assert.equal((sampling.match(/if \(!validSample\(\)\) return;/g) ?? []).length, 3);
  assert.match(sampling, /getPropagationStatus\(\) == QLatin1String\("valid"\)/);
  assert.match(sampling, /pSatWrapper->setEpoch\(epochTime\);\n\}/);
});
