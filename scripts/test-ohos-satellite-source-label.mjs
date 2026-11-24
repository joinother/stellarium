import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

// Pure URL-to-display helpers for the satellite TLE source list. Default
// CelesTrak sources share the same prefix, so the GROUP value must stay
// visible instead of being hidden by end ellipsis.
const source = readFileSync(
  new URL('../harmonyos/ets-source/state/SatelliteSourceText.ts', import.meta.url), 'utf8');
const plain = stripTypeScriptTypes(source.replaceAll('export ', ''));
const helpers = new Function(`${plain}; return { satelliteSourceLabel, satelliteSourceHost, isCustomSatelliteSource }`)();

const GP = 'https://celestrak.org/NORAD/elements/gp.php?GROUP=%s&FORMAT=CSV';

test('CelesTrak GP URLs expose the differing GROUP value', () => {
  const url = GP.replace('%s', 'stations');
  assert.equal(helpers.satelliteSourceLabel(url), 'stations');
  assert.equal(helpers.satelliteSourceHost(url), 'celestrak.org');
});

test('GROUP lookup is case-insensitive and decodes percent escapes', () => {
  const url = 'https://celestrak.org/NORAD/elements/gp.php?group=iridium%2DNEXT&format=CSV';
  assert.equal(helpers.satelliteSourceLabel(url), 'iridium-NEXT');
});

test('custom CSV URLs fall back to the file name and host', () => {
  const url = 'https://example.com/tle/active.csv';
  assert.equal(helpers.satelliteSourceLabel(url), 'active.csv');
  assert.equal(helpers.satelliteSourceHost(url), 'example.com');
});

test('local TLE files keep the file name and have no host', () => {
  const url = 'file:///data/storage/el2/base/files/catalog.tle';
  assert.equal(helpers.satelliteSourceLabel(url), 'catalog.tle');
  assert.equal(helpers.satelliteSourceHost(url), '');
});

test('query-only remote URLs use the query as the differing label', () => {
  const url = 'https://example.com?file=beidou';
  assert.equal(helpers.satelliteSourceLabel(url), 'file=beidou');
  assert.equal(helpers.satelliteSourceHost(url), 'example.com');
});

test('blank and malformed values stay displayable', () => {
  assert.equal(helpers.satelliteSourceLabel('   '), '');
  assert.equal(helpers.satelliteSourceHost('   '), '');
  assert.equal(helpers.satelliteSourceLabel('not-a-url'), 'not-a-url');
  assert.equal(helpers.satelliteSourceHost('not-a-url'), '');
});

test('only non-default CelesTrak entries count as custom sources', () => {
  assert.equal(helpers.isCustomSatelliteSource('https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=CSV'), false);
  assert.equal(helpers.isCustomSatelliteSource('https://celestrak.org/NORAD/elements/gp.php?group=stations&FORMAT=CSV'), false);
  assert.equal(helpers.isCustomSatelliteSource('https://example.com/tle/custom.csv'), true);
  assert.equal(helpers.isCustomSatelliteSource('file:///data/storage/el2/base/files/catalog.tle'), true);
  assert.equal(helpers.isCustomSatelliteSource(''), true);
});
