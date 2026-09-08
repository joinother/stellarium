import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const device = process.argv[2];
assert.ok(device, 'Pass a connected device ID');
const cli = fileURLToPath(new URL('./stellarium-cli.mjs', import.meta.url));
const hdc = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc';
const reports = [];
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
function command(name, payload) {
  const args = [cli, '--device', device, '--command', name, '--json', '--timeout', '30000'];
  if (payload !== undefined) args.push('--payload', String(payload));
  const result = JSON.parse(execFileSync(process.execPath, args, { encoding: 'utf8', timeout: 45000 }));
  assert.equal(result.ok, true, JSON.stringify(result));
  return result;
}
function screenshot(name) {
  const view = command('getViewDirection');
  const path = `/tmp/mist-${name}.jpeg`;
  const remote = `/data/local/tmp/mist-${name}.jpeg`;
  execFileSync(hdc, ['-t', device, 'shell', 'snapshot_display', '-f', remote]);
  execFileSync(hdc, ['-t', device, 'file', 'recv', remote, path]);
  reports.push({ image: path, view, fov: command('getFieldOfView').fov });
}
async function moveView(payload) {
  command('stopPanInertia');
  command('moveToAltAz', payload);
  const [azimuth, altitude] = payload.split('|').map(Number);
  for (let attempt = 0; attempt < 20; attempt++) {
    const actual = command('getViewDirection');
    const azimuthError = Math.abs(((actual.azimuth - azimuth + 540) % 360) - 180);
    if (Math.abs(actual.altitude - altitude) < .1 && azimuthError < .1) return;
    await delay(250);
  }
  throw new Error(`Camera did not reach requested direction: ${payload}`);
}
async function opacity(visible) {
  for (let attempt = 0; attempt < 15; attempt++) {
    const response = command('getLandscapeInfo');
    if (visible ? response.mistHorizonOpacity > .95 : response.mistHorizonOpacity < .01) {
      reports.push({ visible, opacity: response.mistHorizonOpacity, enabled: response.mistHorizonEnabled });
      return;
    }
    await delay(300);
  }
  throw new Error(`Mist visibility did not become ${visible}`);
}

let ready = false;
for (let attempt = 0; attempt < 40; attempt++) {
  ready = command('getPresentationState').ready;
  if (ready) break;
  await delay(500);
}
assert.equal(ready, true, 'Wait for first correctly sized sky frames');
const original = command('getLandscapeInfo');
command('beginGuidedSession');
try {
  command('closeUiPanel');
  command('setTracking', 0);
  command('clearSelection');
  command('setTimeRate', 0);
  command('setJD', Date.parse('2026-09-08T09:30:00Z') / 86400000 + 2440587.5);
  command('setActionChecked', 'actionShow_Ground|0');
  command('setActionChecked', 'actionShow_MistHorizon|1');
  await moveView('90|-7|0');
  command('setFOV', 70);
  await opacity(true);
  assert.equal(command('getState').actionShow_MistHorizon, true);
  await delay(1500);
  screenshot('on');
  await delay(6000);
  screenshot('motion');
  reports.push({ fps: command('getFPS') });
  command('setActionChecked', 'actionShow_MistHorizon|0');
  await opacity(false);
  assert.equal(command('getState').actionShow_MistHorizon, false);
  await delay(1500);
  reports.push({ fpsOff: command('getFPS') });
  screenshot('off');
  const observer = command('getObserverInfo');
  command('setLandscape', original.id === 'garching' ? 'guereins' : 'garching');
  assert.equal(command('getLandscapeInfo').ground, false);
  assert.deepEqual(command('getObserverInfo'), observer);
  await opacity(false);
  command('setActionChecked', 'actionShow_Ground|1');
  await opacity(false);
  assert.equal(command('getState').actionShow_MistHorizon, false);
  screenshot('photo');
  command('setActionChecked', 'actionShow_MistHorizon|1');
  await opacity(true);
  assert.equal(command('getState').actionShow_Ground, false);
  for (const view of ['180|-7|0', '-179.9|-7|0', '90|-89|0']) {
    await moveView(view);
    await delay(1200);
    screenshot(view.startsWith('90') ? 'nadir' : view.startsWith('180') ? 'wrap-a' : 'wrap-b');
  }
  await moveView('90|-7|0');
  command('setFOV', 30);
  await delay(1500);
  screenshot('zoom');
  command('setFOV', 70);
  command('setJD', Date.parse('2026-09-08T15:00:00Z') / 86400000 + 2440587.5);
  await delay(1500);
  screenshot('night');
  command('openUiPanel', 'layers');
  command('setLayerTab', 4);
  await delay(1500);
  screenshot('settings');
} finally {
  command('setLandscape', original.id);
  command('endGuidedSession');
  await delay(1500);
  const restored = command('getLandscapeInfo');
  assert.equal(restored.mistHorizonEnabled, original.mistHorizonEnabled);
  reports.push({ restored: true });
  writeFileSync('/tmp/mist-pad-report.json', JSON.stringify(reports, null, 2));
}
console.log(JSON.stringify(reports, null, 2));
