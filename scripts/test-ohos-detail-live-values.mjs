import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const getterBody = source.match(/private selectedDisplayValue\(key: string\): string \{([\s\S]*?)\n  \}/)[1];
// Phase A1-3：zhNameOf 已迁到 common/derive/labels.ets，宿主方法体改用自由变量调用它；
// 提取出来的函数体通过形参拿到一个替身（本测试只验 selectedDisplayValue 读的是当前状态）。
const getter = new Function('key', 'zhNameOf', getterBody);
const zhNameOf = value => value;
const fields = [...getterBody.matchAll(/case '(selected\w+)':/g)].map(match => match[1]);

// 选中天体的取值统一改由 ObjectDetailStore 承载（本轮状态搬迁），
// 因此下面的假宿主改为注入 objectDetailStore，断言“取值读的是当前状态”这一不变式。

test('every selected-object value resolves current state rather than a builder snapshot', () => {
  const state = { objectDetailStore: {} };
  for (const field of fields) {
    state.objectDetailStore[field] = 'first';
    assert.equal(getter.call(state, field, zhNameOf), 'first', field);
    state.objectDetailStore[field] = 'second';
    assert.equal(getter.call(state, field, zhNameOf), 'second', field);
  }
});

test('hidden or unavailable coordinates do not retain their last value', () => {
  const state = { objectDetailStore: { selectedCoordApparentAltAz: '', selectedCoordAlt: 'fallback' } };
  assert.equal(getter.call(state, 'selectedCoordApparentAltAz', zhNameOf), 'fallback');
  state.objectDetailStore.selectedCoordAlt = '';
  assert.equal(getter.call(state, 'selectedCoordApparentAltAz', zhNameOf), '');
});

test('equatorial formatting does not indent coordinate table values', () => {
  const state = { objectDetailStore: { selectedCoordEq: '   3h45m47.8s  +24°40\'48.9"', selectedCoordEqJ2000: '   3h44m11.5s  +24°35\'42.4"' } };
  assert.equal(getter.call(state, 'selectedCoordEq'), state.objectDetailStore.selectedCoordEq.trim());
  assert.equal(getter.call(state, 'selectedCoordEqJ2000'), state.objectDetailStore.selectedCoordEqJ2000.trim());
});

test('detail tabs and coordinate rows share restrained type sizing and flexible row heights', () => {
  // The detail rows/tiles are components now (DetailRows / DetailTiles /
  // DetailLiveRows / StructuredDetailRows); they use explicit restrained font
  // sizes instead of the removed host objectDetailFontSize helper.
  const detailRows = readFileSync(new URL('../harmonyos/ets-source/panels/object/DetailRows.ets', import.meta.url), 'utf8');
  const detailTiles = readFileSync(new URL('../harmonyos/ets-source/panels/object/DetailTiles.ets', import.meta.url), 'utf8');
  const detailLive = readFileSync(new URL('../harmonyos/ets-source/panels/object/DetailLiveRows.ets', import.meta.url), 'utf8');
  const structured = readFileSync(new URL('../harmonyos/ets-source/panels/object/StructuredDetailRows.ets', import.meta.url), 'utf8');
  const tab = detailTiles.slice(detailTiles.indexOf('export struct ObjectDetailTab'), detailTiles.indexOf('export struct ObjectCompactMetric'));
  const coord = detailLive.slice(detailLive.indexOf('export struct SelectedCoordinateRow'), detailLive.indexOf('export struct SelectedCoordinateRows'));
  for (const body of [tab, coord]) {
    assert.match(body, /\.fontSize\(/);
    assert.doesNotMatch(body, /panelFontSize/);
  }
  for (const src of [detailRows, detailTiles, detailLive, structured]) {
    assert.doesNotMatch(src, /panelFontSize/);
  }
});

test('structured row resolves replaced fields and handles fields that disappear', () => {
  // 段落助手（detailFieldLabel/detailFieldValue/...）已随结构化资料界面搬进 StructuredDetailRows.ets，
  // 并改成接收 store 的文件作用域函数。
  const detailSource = readFileSync(new URL('../harmonyos/ets-source/panels/object/StructuredDetailRows.ets', import.meta.url), 'utf8');
  const body = detailSource.match(/function detailFieldValue\(store: ObjectDetailStore, key: string\): string \{([\s\S]*?)\n\}/)[1];
  const value = new Function('store', 'key', body.replace('item: ObjectDetailField', 'item'));
  const store = { selectedDetailFields: [{ key: 'range', value: '1200 km' }] };
  assert.equal(value(store, 'range'), '1200 km');
  store.selectedDetailFields = [{ key: 'range', value: '1100 km' }];
  assert.equal(value(store, 'range'), '1100 km');
  store.selectedDetailFields = [];
  assert.equal(value(store, 'range'), '--');
});

test('live detail polling does not wait for optional satellite pass predictions', () => {
  // D1：startDetailAutoRefresh 已下沉 capability/DetailConnectorController.ets（宿主状态经 hooks 回读）。
  const connectorCtl = readFileSync(new URL('../harmonyos/ets-source/capability/DetailConnectorController.ets', import.meta.url), 'utf8');
  const poll = connectorCtl.match(/startDetailAutoRefresh\(\): void \{([\s\S]*?)\n  \}/)[1];
  assert.doesNotMatch(poll, /selectedSatellitePassesLoaded|getSatellitePasses/);
  assert.match(poll, /this\.hooks\.skyDragging\(\)/);
  assert.match(poll, /this\.hooks\.refreshSelectedObject\(\)/);
});

test('live merging preserves row order and static records while removing expired values', () => {
  const body = source.match(/private updateSelectedLiveDetails\(fields: Array<ObjectDetailField>\): void \{([\s\S]*?)\n  \}/)[1];
  const merge = new Function('fields', body.replaceAll(': ObjectDetailField', ''));
  const state = { objectDetailStore: { selectedDetailFields: [
    { key: 'range', value: '1000', live: true }, { key: 'tleEpoch', value: 'epoch' },
    { key: 'visibility', value: 'visible', live: true }
  ] } };
  merge.call(state, [{ key: 'range', value: '900', live: true }, { key: 'height', value: '800', live: true }]);
  assert.deepEqual(state.objectDetailStore.selectedDetailFields.map(field => field.key), ['range', 'tleEpoch', 'height']);
  assert.equal(state.objectDetailStore.selectedDetailFields[0].value, '900');
  assert.equal(state.objectDetailStore.selectedDetailFields[1].value, 'epoch');
  merge.call(state, []);
  assert.deepEqual(state.objectDetailStore.selectedDetailFields, [{ key: 'tleEpoch', value: 'epoch' }]);
});

// 详情卡片的行/贴片已全部组件化（DetailRows / DetailTiles / DetailLiveRows / ObjectDetailTabs），
// 宿主里不再有"参数化 @Builder 内部按 key 查值"的形态 —— 那正是子树首帧冻结的来源（§13.1 规则 3）。
// 卡片三页整段也已搬进 ObjectDetailTabs，故下面同时检查宿主与组件文件。
const tabs = readFileSync(new URL('../harmonyos/ets-source/panels/object/ObjectDetailTabs.ets', import.meta.url), 'utf8');
const chrome = readFileSync(new URL('../harmonyos/ets-source/panels/object/ObjectDetailCardChrome.ets', import.meta.url), 'utf8');
// Phase 6c：hover/expanded 两壳已下沉为组件，详情卡的其余两处调用点随之搬到对应组件文件。
const hoverShell = readFileSync(new URL('../harmonyos/ets-source/panels/shell/HoverObservatoryShell.ets', import.meta.url), 'utf8');
const expandedShell = readFileSync(new URL('../harmonyos/ets-source/panels/shell/ExpandedShell.ets', import.meta.url), 'utf8');

test('detail rows and tiles come from components while the host keeps the lookups', () => {
  for (const wired of [
    'ObjectDataRow({ label:',
    'ObjectDataTile({ label:',
    'ObjectMetric({ label:',
    'ObjectScheduleTile({ label:',
    'ObjectDetailTab({ label:',
    'ObjectCompactMetric({ label:',
    'SelectedCoordinateRows({ store: ',
    'SelectedLiveInfoRows({ store: this.store',
    'ObjectDistanceNotice({ text: this.distanceText })'
  ]) {
    assert.ok((source + tabs + chrome).includes(wired), wired);
  }
  assert.ok(tabs.includes("value: this.resolve('selectedRise')"), 'the tab components resolve tile values through the injected resolver');
  assert.ok((source + hoverShell + expandedShell).includes('activeIndex: this.bottomCardIndex'), 'the active tab derives from live state');
});

test('tile components receive resolved values while the host keeps the lookups', () => {
  for (const tile of ['ObjectDataTile', 'ObjectMetric', 'ObjectScheduleTile']) {
    assert.ok((source + tabs + chrome).includes(`${tile}({ label: `), tile);
  }
  assert.ok(tabs.includes("value: this.resolve('selectedRise')"));
  assert.ok(chrome.includes('ObjectDetailTab({ label:'), 'the tab bar comes from the component');
  assert.ok((source + hoverShell + expandedShell).includes('activeIndex: this.bottomCardIndex'), 'the active tab is derived from live state');
  assert.ok(source.includes('resolve: (key: string) => this.selectedDisplayValue(key)'), 'the host injects the resolver');
  // Phase 3ad 回归修复：页头三枚摘要直接读 @ObjectLink store，否则切换天体时元素不被标脏而冻结。
  assert.ok(chrome.includes("ObjectCompactMetric({ label: I18n.t('i0007'), value: this.store.selectedMagnitude })"), 'the magnitude metric reads the observed store directly');
  assert.ok(chrome.includes('value: this.nameOf(this.store.selectedConstellation)'), 'the constellation metric reads the observed store directly');
  assert.ok(chrome.includes('value: this.distanceSummary(this.store.selectedDistance, this.store.selectedDistanceCompact)'), 'the distance metric reads the observed store directly');
});
