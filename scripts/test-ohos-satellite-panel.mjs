import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const page = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const satelliteStoreSrc = readFileSync(new URL('../harmonyos/ets-source/state/SatelliteStore.ets', import.meta.url), 'utf8');
const satellite = readFileSync(new URL('../plugins/Satellites/src/Satellite.cpp', import.meta.url), 'utf8');
const manager = readFileSync(new URL('../plugins/Satellites/src/Satellites.cpp', import.meta.url), 'utf8');
const method = name => page.match(new RegExp(`private ${name}\\([^\\n]*\\): void \\{([\\s\\S]*?)\\n  \\}`))[1];
// §14 B3-4：loadSatellites 已搬入 SatelliteStore（public 方法），按 store 文件切片。
const storeMethod = name => satelliteStoreSrc.match(new RegExp(`\\n  ${name}\\([^\\n]*\\): void \\{([\\s\\S]*?)\\n  \\}`))[1];
// D13：卫星行为（selectSatelliteGroup / setSatelliteFlag 等）已下沉 capability/SatelliteController.ets。
const satelliteControllerSrc = readFileSync(new URL('../harmonyos/ets-source/capability/SatelliteController.ets', import.meta.url), 'utf8');
const controllerMethod = name => satelliteControllerSrc.match(new RegExp(`\\n  ${name}\\([^\\n]*\\): void \\{([\\s\\S]*?)\\n  \\}`))[1];

test('group selection uses a local non-linear animation and preserves same-value state', () => {
  const select = new Function('group', controllerMethod('selectSatelliteGroup'));
  const model = { satelliteStore: { activeSatGroup: 'visual', satGroups: ['visual', 'beidou'], calls: 0,
    loadSatellites() { this.calls++; } }, errors: [], animated: 0,
    hooks: {
      publishSatellitePanelState(error) { model.errors.push(error); },
      animateSatelliteGroupChange(action) { model.animated++; action(); }
    }
  };
  select.call(model, 'visual');
  assert.equal(model.satelliteStore.calls, 0);
  assert.equal(model.animated, 0);
  select.call(model, 'beidou');
  assert.equal(model.satelliteStore.activeSatGroup, 'beidou');
  assert.equal(model.satelliteStore.calls, 1);
  assert.equal(model.animated, 1);
  select.call(model, 'invalid');
  assert.equal(model.satelliteStore.activeSatGroup, 'beidou');
  assert.equal(model.errors.at(-1), 'unknown satellite group');
  select.call(model, '');
  assert.equal(model.satelliteStore.activeSatGroup, '');
  // 180ms EaseOut 过渡现由宿主 getUIContext().animateTo hook 承载（控制器只回调 hooks）。
  assert.match(page, /animateSatelliteGroupChange: \(action: \(\) => void\): void => \{/);
  assert.match(page, /duration: 180, curve: Curve\.EaseOut/);
});

test('filter rows precede variable results and retain their own bounded scroll container', () => {
  // Phase 4j 复核：`satellites` 分支已在更早的切片下沉为 panels/panels/SatellitesPanel.ets，
  // 因此原按宿主文本切片的断言改读该组件文件（预存失配，本片顺带同步）。
  const panel = readFileSync(new URL('../harmonyos/ets-source/panels/panels/SatellitesPanel.ets', import.meta.url), 'utf8');
  assert.ok(panel.indexOf('SatelliteGroupSelector(') < panel.indexOf('ForEach(this.satelliteStore.satItems'));
  assert.match(panel, /Scroll\(this\.panelScroller\)/);
  const selector = readFileSync(new URL('../harmonyos/ets-source/panels/satellite/SatelliteGroupSelector.ets', import.meta.url), 'utf8');
  assert.match(selector, /Scroll\(this\.scroller\)/);
  assert.match(selector, /height\(180\)/);
  assert.match(selector, /\(group: string\) => group/);
  assert.match(selector, /opacity\(this\.activeGroup === group \? 1 : 0\)/);
});

test('queued filtering invalidates previous results before the debounce fires', () => {
  const load = storeMethod('loadSatellites');
  assert.ok(load.indexOf('++this.satelliteListRequestId') < load.indexOf('const run'));
  assert.match(load, /requestId !== this.satelliteListRequestId/);
  assert.match(load, /flagMutationId === this.satelliteFlagMutationId/);
  assert.match(load, /this.satGroups.join\('\|'\) !== s.groups.join\('\|'\)/);
});

test('panel diagnostics remain available before scroll attachment and after closing', () => {
  const publish = new Function('error', 'AppStorage', method('publishSatellitePanelState').replaceAll(': SatelliteListItem', ''));
  const model = { satelliteStore: { satItems: [], satOrbitLines: false, satelliteListRequestId: 0, satelliteListElapsedMs: 0 },
    satellitePanelScroller: { currentOffset: () => undefined },
    satelliteGroupScroller: { currentOffset: () => undefined } };
  let state;
  publish.call(model, '', { setOrCreate: (key, value) => { state = JSON.parse(value); } });
  assert.equal(state.scrollY, 0);
  assert.equal(state.groupScrollY, 0);
  assert.equal(state.orbitLines, false);
});

test('same-value satellite switch callbacks never dispatch native writes', () => {
  const guard = controllerMethod('setSatelliteFlag').split('const mutationId')[0];
  const check = new Function('name', 'v', guard + '; return "changed";');
  const model = { satelliteStore: { satLabels: true, satOrbitLines: false, satHints: true, satIconicMode: false, satHideInvisible: true } };
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
  assert.match(sampling, /pSatWrapper->setEpoch\(epochTime\);\r?\n\}/);
});
