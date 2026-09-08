import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const device = process.argv[2];
assert.ok(device, 'Pass a connected device ID');
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
function frames() {
  return execFileSync(hdc, ['-t', device, 'shell', 'hilog', '-x', '-T', 'StellariumFps'],
    { encoding: 'utf8', timeout: 15000 }).split('\n').filter(line => line.includes('frame: total='));
}
function summarize(values) {
  const sorted = [...values].sort((first, second) => first - second);
  return { median: sorted[Math.floor(sorted.length / 2)], p95: sorted[Math.ceil(sorted.length * .95) - 1],
    maximum: sorted.at(-1) };
}

assert.equal(command('getPresentationState').ready, true);
command('beginGuidedSession');
try {
  command('closeUiPanel');
  command('setTracking', 0);
  command('clearSelection');
  command('setTimeRate', 0);
  command('setJD', Date.parse('2026-09-08T09:30:00Z') / 86400000 + 2440587.5);
  command('setActionChecked', 'actionShow_Ground|0');
  command('setFOV', 70);
  for (const enabled of [false, true, false, true]) {
    command('stopPanInertia');
    command('moveToAltAz', '180|-7|0');
    command('setActionChecked', `actionShow_MistHorizon|${Number(enabled)}`);
    await delay(1800);
    const before = new Set(frames());
    for (let pass = 0; pass < 4; pass++) {
      command('startPanInertia', `${pass % 2 ? -1 : 1}|0`);
      await delay(1800);
    }
    command('stopPanInertia');
    const rows = frames().filter(line => !before.has(line));
    assert.ok(rows.length >= 5, 'Insufficient fresh frame samples');
    const metrics = {};
    for (const key of ['total', 'cmd', 'update', 'draw', 'submit']) {
      metrics[key] = summarize(rows.map(line => Number(line.match(new RegExp(`${key}=([\\d.]+)ms`))[1])));
    }
    const result = { enabled, samples: rows.length, metrics, state: command('getLandscapeInfo'),
      presentation: command('getPresentationState'), rows };
    assert.equal(result.state.mistHorizonEnabled, enabled);
    report.push(result);
    console.log(JSON.stringify({ enabled, samples: rows.length, metrics }));
  }
} finally {
  command('stopPanInertia');
  command('endGuidedSession');
  writeFileSync('/tmp/mist-performance.json', JSON.stringify(report, null, 2));
}
