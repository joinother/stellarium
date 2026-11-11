import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const device = process.argv[2];
assert.ok(device, 'Pass a connected device ID');
const output = resolve(process.argv[3] || '/tmp/mist-motion-pad');
const hdc = process.env.HDC_BIN || '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc';
const cli = fileURLToPath(new URL('./stellarium-cli.mjs', import.meta.url));
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
mkdirSync(output, { recursive: true });
const run = args => execFileSync(hdc, ['-t', device, ...args], { encoding: 'utf8', timeout: 45000 });
function command(name, payload = '') {
  const result = JSON.parse(execFileSync(process.execPath,
    [cli, '--device', device, '--command', name, '--payload', String(payload), '--json'],
    { encoding: 'utf8', timeout: 45000 }));
  assert.equal(result.ok, true, JSON.stringify(result));
  return result;
}
const report = { device, captures: [], moves: [], video: null, restored: false };
let recording = false;
let started = 0;
function recorder(filename) {
  const args = ['shell', 'aa', 'start', '-b', 'com.huawei.hmos.screenrecorder', '-a',
    'com.huawei.hmos.screenrecorder.ServiceExtAbility'];
  if (filename) args.push('--ps', 'CustomizedFileName', filename);
  const result = run(args);
  assert.match(result, /start ability successfully/);
}
function capture(name) {
  const remote = `/data/local/tmp/mist-motion-${name}.jpeg`;
  const image = join(output, `${name}.jpeg`);
  run(['shell', 'snapshot_display', '-f', remote]);
  run(['file', 'recv', remote, image]);
  report.captures.push({ name, image, recordingSeconds: (Date.now() - started) / 1000, view: command('getViewDirection'),
    fov: command('getFieldOfView'), landscape: command('getLandscapeInfo') });
}
async function move(name, azimuth, altitude, seconds = 2.4) {
  report.moves.push({ name, azimuth, altitude, seconds, recordingSeconds: (Date.now() - started) / 1000 });
  command('moveToAltAz', `${azimuth}|${altitude}|${seconds}`);
  await delay(seconds * 1000 + 1400);
  const view = command('getViewDirection');
  assert.ok(Math.abs(view.altitude - altitude) < .6, JSON.stringify(view));
  capture(name);
}

assert.equal(command('getPresentationState').ready, true);
const original = command('getState');
const ui = command('getUiPanelState');
const observer = command('getObserverInfo');
const navigation = command('getNavigationSettings');
const filename = `mist-motion-${Date.now()}.mp4`;
report.recordingFilename = filename;
command('beginGuidedSession');
try {
  command('closeUiPanel');
  command('stopPanInertia');
  command('setTracking', 0);
  command('clearSelection');
  command('setTimeRate', 0);
  command('setProjectionType', 'ProjectionStereographic');
  await delay(1600);
  command('setFOV', 75);
  command('setActionChecked', 'actionShow_Night_Mode|0');
  command('setActionChecked', 'actionShow_MistHorizon|1');
  command('setActionChecked', 'actionShow_Atmosphere|1');
  command('setSkyDisplaySetting', 'realisticStarVisibility|0');
  command('setSkyDisplaySetting', 'vividAtmosphere|0');
  const longitude = Number(observer.longitude);
  assert.ok(Number.isFinite(longitude), JSON.stringify(observer));
  const noon = Math.floor(original.jd) - longitude / 360;
  report.jd = noon;
  command('setJD', noon);
  command('moveToAltAz', '240|10|0');
  await delay(2400);
  recorder(filename);
  recording = true;
  started = Date.now();
  await delay(4000);
  capture('level');
  await move('down', 240, -25);
  await move('deep', 240, -65);
  await move('nadir', 240, -90);
  command('setActionChecked', 'actionShow_MistHorizon|0');
  await delay(1800);
  capture('nadir-off');
  command('setActionChecked', 'actionShow_MistHorizon|1');
  await delay(1800);
  await move('return', 240, 10, 3);
  await move('seam-before', 179.9, 2);
  await move('seam-after', 180.1, 2, .4);
  await move('zoom-direction', 240, 0);
  for (const fov of [30, 12, 75]) {
    command('setFOV', fov);
    await delay(1800);
    capture(`zoom-${fov}`);
  }
  await delay(4000);
  capture('stationary-later');
  assert.ok(Math.abs(command('getState').jd - noon) < 1e-7);
  command('setFOV', 45);
  await move('flow-near-start', 240, -35, 2);
  await delay(4000);
  capture('flow-near-middle');
  await delay(4000);
  capture('flow-near-later');
  command('setFOV', 12);
  await delay(1800);
  capture('flow-close-start');
  await delay(6000);
  capture('flow-close-later');
  command('setFOV', 75);
  await move('flow-to-solid', 240, 12, 3);
  await move('solid-to-flow', 240, -35, 3);
  for (const azimuth of [0, 90, 180, 300]) {
    await move(`ridge-${azimuth}`, azimuth, -8, .6);
  }
  command('setNavigationSetting', 'maxFov|240');
  command('setProjectionType', 'ProjectionStereographic');
  await delay(1600);
  for (const fov of [130, 145, 155, 210, 235]) {
    command('setFOV', fov);
    await move(`wide-day-nadir-${fov}`, 240, -90, .8);
    assert.ok(Math.abs(command('getFieldOfView').fov - fov) < .1);
  }
  await move('wide-day-zenith', 240, 90, 3);
  command('setJD', noon + .5);
  await move('wide-night-nadir', 240, -90, 3);
  command('setActionChecked', 'actionShow_MistHorizon|0');
  await delay(1800);
  capture('wide-night-nadir-off');
  recorder();
  recording = false;
  await delay(1800);
  const query = run(['shell', 'mediatool', 'query', filename, '-u']);
  const uri = query.match(/"(file:\/\/[^\"]+)"/);
  assert.ok(uri, query);
  const copied = run(['shell', 'mediatool', 'recv', uri[1], '/data/local/tmp']);
  const remote = copied.split('\n').find(line => line.startsWith('/data/local/tmp/'))?.trim();
  assert.ok(remote, copied);
  report.video = join(output, filename);
  run(['file', 'recv', remote, report.video]);
} finally {
  if (recording) recorder();
  command('stopPanInertia');
  command('endGuidedSession');
  command('setNavigationSetting', `maxFov|${navigation.maxFov}`);
  if (ui.visible) command('openUiPanel', ui.panel);
  const restored = command('getState');
  for (const flag of ['vividAtmosphere', 'realisticStarVisibility', 'actionShow_MistHorizon', 'actionShow_Ground']) {
    assert.equal(restored[flag], original[flag], `Failed to restore ${flag}`);
  }
  report.restored = true;
  writeFileSync(join(output, 'report.json'), JSON.stringify(report, null, 2));
}
console.log(JSON.stringify({ video: report.video, captures: report.captures.length, restored: report.restored }));
