import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const getterBody = source.match(/private selectedDisplayValue\(key: string\): string \{([\s\S]*?)\n  \}/)[1];
const getter = new Function('key', getterBody);
const fields = [...getterBody.matchAll(/case '(selected\w+)':/g)].map(match => match[1]);

test('every selected-object value resolves current state rather than a builder snapshot', () => {
  const state = { zhNameOf: value => value };
  for (const field of fields) {
    state[field] = 'first';
    assert.equal(getter.call(state, field), 'first', field);
    state[field] = 'second';
    assert.equal(getter.call(state, field), 'second', field);
  }
});

test('hidden or unavailable coordinates do not retain their last value', () => {
  assert.equal(getter.call({ selectedCoordApparentAltAz: '', selectedCoordAlt: 'fallback' }, 'selectedCoordApparentAltAz'), 'fallback');
  assert.equal(getter.call({ selectedCoordApparentAltAz: '', selectedCoordAlt: '' }, 'selectedCoordApparentAltAz'), '');
});

test('structured row resolves replaced fields and handles fields that disappear', () => {
  const body = source.match(/private detailFieldValue\(key: string\): string \{([\s\S]*?)\n  \}/)[1];
  const value = new Function('key', body.replace('item: ObjectDetailField', 'item'));
  const state = { selectedDetailFields: [{ key: 'range', value: '1200 km' }] };
  assert.equal(value.call(state, 'range'), '1200 km');
  state.selectedDetailFields = [{ key: 'range', value: '1100 km' }];
  assert.equal(value.call(state, 'range'), '1100 km');
  state.selectedDetailFields = [];
  assert.equal(value.call(state, 'range'), '--');
});

test('live detail polling does not wait for optional satellite pass predictions', () => {
  const poll = source.match(/private startDetailAutoRefresh\(\): void \{([\s\S]*?)\n  \}/)[1];
  assert.doesNotMatch(poll, /selectedSatellitePassesLoaded|getSatellitePasses/);
  assert.match(poll, /this\.skyDragging/);
  assert.match(poll, /this\.refreshSelectedObject\(\)/);
});

test('live merging preserves row order and static records while removing expired values', () => {
  const body = source.match(/private updateSelectedLiveDetails\(fields: Array<ObjectDetailField>\): void \{([\s\S]*?)\n  \}/)[1];
  const merge = new Function('fields', body.replaceAll(': ObjectDetailField', ''));
  const state = { selectedDetailFields: [
    { key: 'range', value: '1000', live: true }, { key: 'tleEpoch', value: 'epoch' },
    { key: 'visibility', value: 'visible', live: true }
  ] };
  merge.call(state, [{ key: 'range', value: '900', live: true }, { key: 'height', value: '800', live: true }]);
  assert.deepEqual(state.selectedDetailFields.map(field => field.key), ['range', 'tleEpoch', 'height']);
  assert.equal(state.selectedDetailFields[0].value, '900');
  assert.equal(state.selectedDetailFields[1].value, 'epoch');
  merge.call(state, []);
  assert.deepEqual(state.selectedDetailFields, [{ key: 'tleEpoch', value: 'epoch' }]);
});

test('coordinate, observation and data builders receive stable keys, not string snapshots', () => {
  const calls = source.split('\n').filter(line => /this\.(selectedCoordinateRow|objectDataTile|objectScheduleTile|objectMetric|objectDataRow|tabletInspectorRow|expandedSummaryMetric|expandedSummaryLine)\(/.test(line));
  assert.ok(calls.length > 50);
  for (const line of calls) assert.doesNotMatch(line, /, this\.selected\w+|, this\.zhNameOf/, line);
});
