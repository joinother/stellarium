import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildCalendarFeedArtifacts,
  buildMpcBrightCometEntries,
  buildNoaaAuroraEntries,
  parseMpcCometsText
} from '../deploy/calendar-feed/build-calendar-feed.mjs';

const SAMPLE_MPC = [
  '    CJ95O010  1997 03 29.0303  0.927253  0.994892  130.7420  281.8184   89.7292  20261121  -2.0  4.0  C/1995 O1 (Hale-Bopp)                                    MPC194091',
  '    CK26A010  2026 12 10.5000  0.850000  0.995000  110.0000  200.0000   45.0000  20261121   5.5  4.0  C/2026 A1 (BrightTest)                                   MPEC 2026-W01',
  '    CK26B020  2026 12 20.2500  1.400000  0.850000  120.0000  210.0000   20.0000  20261121  15.0  4.0  C/2026 B2 (FaintTest)                                    MPEC 2026-W02',
  '    CK26C030  2027 06 15.0000  0.900000  0.990000  120.0000  210.0000   20.0000  20261121   5.0  4.0  C/2026 C3 (TooFarInFuture)                               MPEC 2026-W03'
].join('\n');

test('parseMpcCometsText parses standard MPC 1-line comet columns accurately', () => {
  const comets = parseMpcCometsText(SAMPLE_MPC);
  assert.equal(comets.length, 4);
  assert.equal(comets[0].name, 'C/1995 O1 (Hale-Bopp)');
  assert.equal(comets[0].absMag, -2.0);
  assert.equal(comets[1].name, 'C/2026 A1 (BrightTest)');
  assert.ok(Math.abs(comets[1].q - 0.85) < 1e-6);
});

test('buildMpcBrightCometEntries selects only bright active perihelion comets', () => {
  const nowMs = Date.UTC(2026, 10, 22, 12, 0, 0);
  const entries = buildMpcBrightCometEntries(SAMPLE_MPC, nowMs, 3);
  assert.equal(entries.length, 1);
  assert.equal(entries[0].kind, 'comet-alert');
  assert.equal(entries[0].target, 'C/2026 A1 (BrightTest)');
  assert.equal(entries[0].highlight, true);
  assert.match(entries[0].id, /^remote:comet:c-2026-a1-brighttest-2026$/);
});

test('buildNoaaAuroraEntries merges contiguous Kp>=5 storm slots', () => {
  const nowMs = Date.UTC(2026, 10, 22, 12, 0, 0);
  const rows = [
    ['time_tag', 'kp', 'observed', 'noaa_scale'],
    ['2026-11-22 15:00:00', '5.33', 'predicted', 'G1'],
    ['2026-11-22 18:00:00', '7.00', 'predicted', 'G3'],
    ['2026-11-22 21:00:00', '4.00', 'predicted', null]
  ];
  const entries = buildNoaaAuroraEntries(rows, nowMs);
  assert.equal(entries.length, 1);
  assert.equal(entries[0].kind, 'aurora-alert');
  assert.equal(entries[0].regionFilter.minLat, 40);
  assert.equal(entries[0].highlight, true);
});

test('buildCalendarFeedArtifacts produces valid SHA-256 manifest and prunes expired items', () => {
  const nowMs = Date.UTC(2026, 10, 22, 12, 0, 0);
  const comets = buildMpcBrightCometEntries(SAMPLE_MPC, nowMs, 3);
  const expired = {
    id: 'remote:old-item',
    revision: 1,
    action: 'upsert',
    kind: 'editorial',
    title: 'Expired',
    at: nowMs - 10 * 86400000,
    expiresAt: nowMs - 1000
  };
  const artifacts = buildCalendarFeedArtifacts([...comets, expired], nowMs);
  assert.equal(artifacts.feedDoc.entries.length, 1);
  assert.equal(artifacts.manifestDoc.sha256.length, 64);
  assert.equal(artifacts.manifestDoc.bytes, Buffer.byteLength(artifacts.feedJson, 'utf8'));
});
