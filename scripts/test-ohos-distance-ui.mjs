import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

// §14 A2-3：距离提示/摘要下沉 ObjectDetailStore（distanceVisible 改为显式入参），
// 可见性判定下沉 InfoWindowStore；夹具改读对应 store 文件。
const detailStore = readFileSync(new URL('../harmonyos/ets-source/state/ObjectDetailStore.ets', import.meta.url), 'utf8');
const infoWindowStore = readFileSync(new URL('../harmonyos/ets-source/state/InfoWindowStore.ets', import.meta.url), 'utf8');
const extract = (src, name) => {
  const m = src.match(new RegExp(`${name}\\(([^)]*)\\): (?:string|boolean) \\{([\\s\\S]*?)\\n  \\}`));
  const params = m[1].replace(/:\s*[^,]+/g, '');
  return new Function('I18n', `return function(${params}) {${m[2]}}`)({
    t: key => key,
    format: (key, args) => key + '|' + args.join(',')
  });
};

test('distance notes distinguish missing data, uncertain parallax and redshift-only catalogues', () => {
  const note = extract(detailStore, 'objectDistanceNoticeText');
  for (const status of ['unavailable', 'low_confidence', 'redshift_only', 'invalid_orbit', 'unsupported_unit', 'estimated']) {
    assert.equal(note.call({ selectedDistanceStatus: status }, true),
      status === 'invalid_orbit' ? 'satellite_propagation_invalid' : 'distance_' + status);
  }
  assert.equal(note.call({ selectedDistanceStatus: 'computed' }, true), '');
});

test('satellite age is distinct from propagation failure and package freshness', () => {
  const note = extract(detailStore, 'objectDistanceNoticeText');
  assert.equal(note.call({ selectedDistanceStatus: 'computed', selectedTleOutdated: true }, true), 'satellite_tle_stale');
  assert.equal(note.call({ selectedDistanceStatus: 'invalid_orbit', selectedTleOutdated: true }, true), 'satellite_propagation_invalid');
});

test('custom mask and brief information modes do not reveal hidden distance data', () => {
  const visible = extract(infoWindowStore, 'distanceInformationVisible');
  assert.equal(visible.call({ infoLevel: 2, informationMode: 'short' }), false);
  assert.equal(visible.call({ infoLevel: 1, informationMode: 'custom', informationMaskHas: () => false }), false);
  const summary = extract(detailStore, 'objectDistanceSummary');
  assert.equal(summary.call({ selectedDistance: '8.6 ly' }, false), '--');
});

test('summary preserves the distance unit without fitting the uncertainty into the compact tile', () => {
  const summary = extract(detailStore, 'objectDistanceSummary');
  assert.equal(summary.call({ selectedDistance: '8.60 ± 0.1 ly', selectedDistanceCompact: '8.60 ly' }, true), '8.60 ly');
  assert.equal(summary.call({ selectedDistance: '' }, true), 'distance_missing');
});

test('stellar map matches desktop parallax safety and absolute magnitude formula', () => {
  const wrapper = readFileSync(new URL('../src/core/modules/StarWrapper.hpp', import.meta.url), 'utf8');
  assert.match(wrapper, /parallax > 0\. && parallaxError > 0\. && parallax \/ parallaxError > 5\./);
  assert.match(wrapper, /5\. \* \(1\. \+ std::log10\(0\.001 \* parallax\)\)/);
  const bridge = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
  assert.match(bridge, /"parallax"\), 1000\., 3, QStringLiteral\(" mas"\)/);
  assert.doesNotMatch(bridge, /qSharedPointerCast<Planet>\(sel\.first\(\)\).*getDistance/);
  assert.match(bridge, /englishName\.isEmpty\(\) \? catalogIdentity : englishName/);
  assert.match(bridge, /localizedName\.isEmpty\(\) \? result.value\("englishName"\)/);
});
