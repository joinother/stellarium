import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const device = process.argv[2];
const phase = process.argv[3] || 'after';
assert.ok(device, 'Pass a connected device ID');
assert.ok(['before', 'after'].includes(phase));
const cli = fileURLToPath(new URL('./stellarium-cli.mjs', import.meta.url));
const hdc = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc';
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const report = [];
function command(name, payload) {
  const args = [cli, '--device', device, '--command', name, '--json'];
  if (payload !== undefined) args.push('--payload', String(payload));
  const response = JSON.parse(execFileSync(process.execPath, args, { encoding: 'utf8', timeout: 45000 }));
  assert.equal(response.ok, true, JSON.stringify(response));
  return response;
}

let ready = false;
for (let attempt = 0; attempt < 40; attempt++) {
  ready = command('getPresentationState').ready;
  if (ready) break;
  await delay(500);
}
assert.equal(ready, true);
const original = command('getLandscapeInfo');
command('beginGuidedSession');
try {
  command('closeUiPanel');
  command('setTracking', 0);
  command('clearSelection');
  command('setTimeRate', 0);
  command('setActionChecked', 'actionShow_Ground|1');
  command('setActionChecked', 'actionShow_Fog|0');
  const cases = [
    ['guereins', 90, 60], ['hurricane', 90, 60],
    ...(phase === 'before' ? [] : [
      ['guereins', 89.98, 45], ['guereins', 90.02, 45],
      ['garching', -35, 60], ['garching', 215, 60], ['grossmugl', 90, 60]
    ])
  ];
  for (const [landscape, azimuth, fov] of cases) {
    command('setLandscape', landscape);
    command('setActionChecked', 'actionShow_Fog|0');
    command('setLocation', 'Seam test|46.1086|4.7803|83');
    await delay(1500);
    command('setJD', Date.parse('2026-09-08T12:00:00Z') / 86400000 + 2440587.5);
    command('stopPanInertia');
    command('moveToAltAz', `${azimuth}|-12|0`);
    command('setFOV', fov);
    await delay(2200);
    const view = command('getViewDirection');
    assert.ok(Math.abs(((view.azimuth - azimuth + 540) % 360) - 180) < .1);
    assert.ok(Math.abs(view.altitude + 12) < .1);
    assert.ok(Math.abs(command('getFieldOfView').fov - fov) < .1);
    const state = command('getLandscapeInfo');
    assert.equal(state.id, landscape);
    assert.equal(state.ground, true);
    assert.equal(state.mistHorizonEnabled, false);
    assert.equal(state.fog, false);
    const observer = command('getObserverInfo');
    assert.ok(Math.abs(observer.latitude - 46.1086) < .01);
    assert.ok(Math.abs(observer.longitude - 4.7803) < .01);
    const name = `seam-${phase}-${landscape}-${azimuth}-${fov}.jpeg`;
    const remote = `/data/local/tmp/${name}`;
    execFileSync(hdc, ['-t', device, 'shell', 'snapshot_display', '-f', remote]);
    execFileSync(hdc, ['-t', device, 'file', 'recv', remote, `/tmp/${name}`]);
    report.push({ image: `/tmp/${name}`, view, fov, state, observer });
  }
} finally {
  command('setLandscape', original.id);
  command('endGuidedSession');
  writeFileSync(`/tmp/seam-${phase}-report.json`, JSON.stringify(report, null, 2));
}
console.log(JSON.stringify(report, null, 2));
