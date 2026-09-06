import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const extract = name => new Function('I18n', `return function() {${source.match(new RegExp(`private ${name}\\(\\): (?:string|boolean) \\{([\\s\\S]*?)\\n  \\}`))[1]}}`)({t: key => key});

test('distance notes distinguish missing data, uncertain parallax and redshift-only catalogues', () => {
  const note = extract('objectDistanceNoticeText');
  for (const status of ['unavailable', 'low_confidence', 'redshift_only', 'invalid_orbit', 'unsupported_unit', 'estimated']) {
    assert.equal(note.call({ distanceInformationVisible: () => true, selectedDistanceStatus: status }),
      status === 'invalid_orbit' ? 'satellite_propagation_invalid' : 'distance_' + status);
  }
  assert.equal(note.call({ distanceInformationVisible: () => true, selectedDistanceStatus: 'computed' }), '');
});

test('satellite age is distinct from propagation failure and package freshness', () => {
  const note = extract('objectDistanceNoticeText');
  assert.equal(note.call({ distanceInformationVisible: () => true, selectedDistanceStatus: 'computed', selectedTleOutdated: true }), 'satellite_tle_stale');
  assert.equal(note.call({ distanceInformationVisible: () => true, selectedDistanceStatus: 'invalid_orbit', selectedTleOutdated: true }), 'satellite_propagation_invalid');
});

test('custom mask and brief information modes do not reveal hidden distance data', () => {
  const visible = extract('distanceInformationVisible');
  assert.equal(visible.call({ infoLevel: 2, informationMode: 'short' }), false);
  assert.equal(visible.call({ infoLevel: 1, informationMode: 'custom', informationMaskHas: () => false }), false);
  const summary = extract('objectDistanceSummary');
  assert.equal(summary.call({ distanceInformationVisible: () => false, selectedDistance: '8.6 ly' }), '--');
});

test('summary preserves the distance unit without fitting the uncertainty into the compact tile', () => {
  const summary = extract('objectDistanceSummary');
  assert.equal(summary.call({ distanceInformationVisible: () => true, selectedDistance: '8.60 ± 0.1 ly', selectedDistanceCompact: '8.60 ly' }), '8.60 ly');
  assert.equal(summary.call({ distanceInformationVisible: () => true, selectedDistance: '' }), 'distance_missing');
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
