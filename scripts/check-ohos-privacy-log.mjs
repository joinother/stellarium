import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const [file, processId, mode = 'accepted'] = process.argv.slice(2);
assert.ok(file && /^\d+$/.test(processId ?? ''), 'Pass a log file and the exact app process ID');
assert.ok(['accepted', 'pending'].includes(mode));
const lines = readFileSync(file, 'utf8').split('\n').filter(line =>
  line.match(/^\S+\s+\S+\s+(\d+)\s+\d+\s/)?.[1] === processId);
assert.ok(lines.some(line => line.includes('phase=ability-create')), 'Capture must include process startup');
const gate = lines.findIndex(line => line.includes('phase=qt-host-gate-released-after-consent'));
const accepted = lines.findIndex(line => line.includes('system privacy consent accepted;'));
const setup = lines.findIndex(line => line.includes('phase=qt-setup-start'));
const deviceReads = lines.flatMap((line, index) => line.includes('phase=sdk-device-info-read-start') ? [index] : []);
if (mode === 'pending') {
  assert.ok(lines.some(line => line.includes('phase=dialog-request-start')));
  assert.equal(accepted, -1);
  assert.equal(gate, -1);
  assert.equal(setup, -1);
  assert.equal(deviceReads.length, 0);
  assert.ok(!lines.some(line => /IDeviceInfo|GetSerialID|GetUdid/.test(line)));
} else {
  assert.ok(accepted >= 0 && gate > accepted && setup > gate);
  assert.equal(deviceReads.length, 1);
  assert.ok(deviceReads[0] > setup);
  assert.ok(lines.some(line => line.includes('phase=sdk-device-info-read-finish')));
}
console.log(JSON.stringify({ ok: true, mode, deviceInitializationCount: deviceReads.length,
  scope: 'App process initialization probes only; not a system personal-information audit' }));
