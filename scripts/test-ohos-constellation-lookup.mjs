import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const core = readFileSync(new URL('../src/core/StelCore.cpp', import.meta.url), 'utf8');
const lookupSource = core.slice(core.indexOf('QString StelCore::getIAUConstellation('), core.indexOf('// NELM ='));
const rows = readFileSync(new URL('../data/constellations_spans.dat', import.meta.url), 'utf8')
  .split(/\r?\n/).filter(line => line.trim() && !line.trim().startsWith('#')).map(line => {
    const [low, high, dec, name] = line.trim().split(/\s+/);
    const hours = value => { const parts = value.split(':').map(Number); return parts[0] + parts[1] / 60 + parts[2] / 3600; };
    const [degrees, minutes] = dec.split(':').map(Number);
    return { RAlow: hours(low), RAhigh: hours(high), decLow: degrees + (degrees < 0 ? -minutes : minutes) / 60, constellation: name };
  });
const predicate = lookupSource.match(/if \((dec1875 >= span\.decLow[^\n]+)\)/)[1];
const matches = new Function('span', 'RA1875', 'dec1875', `return ${predicate};`);

test('constellation lookup rejects invalid vectors and never indexes beyond its table', () => {
  assert.match(lookupSource, /!std::isfinite\(positionLength\) \|\| positionLength <= 0\./);
  assert.match(lookupSource, /!std::isfinite\(RA1875\) \|\| !std::isfinite\(dec1875\)/);
  assert.doesNotMatch(lookupSource, /iau_constlineVec->at\(entry\)/);
});

test('half-open RA intervals cover the meridian, poles and the complete sky grid', () => {
  for (let declination = -90; declination <= 90; declination += 0.5) {
    for (let ascension = 0; ascension < 24; ascension += 0.05) {
      assert.ok(rows.find(row => matches(row, ascension, declination)), `No constellation at ${ascension}, ${declination}`);
    }
  }
  assert.match(lookupSource, /RA1875 >= 24\.\) RA1875 = 0\./);
  for (const ascension of [0, 12, 23.999999]) {
    assert.equal(rows.find(row => matches(row, ascension, -90)).constellation, 'Oct');
    assert.equal(rows.find(row => matches(row, ascension, 90)).constellation, 'UMi');
  }
});
