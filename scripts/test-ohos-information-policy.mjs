import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

// 2026-10-05：解散 capability/SettingsController.ets 时，applyCustomInformationMask 按「字段所在处即归宿」
// 并入 state/ObjectDetailStore.ets（30 个被清字段全在该 store）；信息模式 / 掩码判定由调用方以谓词传入。
const source = readFileSync(new URL('../harmonyos/ets-source/state/ObjectDetailStore.ets', import.meta.url), 'utf8');
const match = source.match(/applyCustomInformationMask\(informationMode: string, informationMaskHas: \(key: string\) => boolean\): void \{([\s\S]*?)\n  \}/);
assert.ok(match);
const apply = new Function('informationMode', 'informationMaskHas', match[1].replace('new Map<string, string>', 'new Map').replace('field: ObjectDetailField', 'field'));

// 选中天体的信息字段由 ObjectDetailStore 承载；夹具即该 store 的明细字段快照。
function state(enabled, mode = 'custom') {
  return {
    selectedMagnitude: '3.40', selectedDistance: '2.5 Mly', selectedConstellation: '仙女座',
    selectedCoordEq: '00h42m', selectedCoordGalactic: '121°', selectedName: '仙女座星系',
    selectedDetailFields: [
      { key: 'equatorialOfDate', value: '00h42m' }, { key: 'surfaceBrightness', value: '13.2' },
      { key: 'morphology', value: 'SA(s)b' }
    ]
  };
}
const maskHas = enabled => key => enabled.includes(key);

test('custom empty mask clears information values but preserves selection identity', () => {
  const selected = state([]);
  apply.call(selected, 'custom', maskHas([]));
  assert.equal(selected.selectedMagnitude, '');
  assert.equal(selected.selectedConstellation, '');
  assert.equal(selected.selectedCoordEq, '');
  assert.equal(selected.selectedName, '仙女座星系');
  assert.deepEqual(selected.selectedDetailFields, []);
});

test('custom groups filter both overview values and structured detail rows', () => {
  const selected = state(['magnitude', 'galactic']);
  apply.call(selected, 'custom', maskHas(['magnitude', 'galactic']));
  assert.equal(selected.selectedMagnitude, '3.40');
  assert.equal(selected.selectedCoordGalactic, '121°');
  assert.equal(selected.selectedDistance, '');
  assert.deepEqual(selected.selectedDetailFields.map(field => field.key), ['surfaceBrightness']);
});

test('preset information modes are not filtered by saved custom choices', () => {
  const selected = state([], 'all');
  const original = JSON.stringify(selected);
  apply.call(selected, 'all', maskHas([]));
  assert.equal(JSON.stringify(selected), original);
});
