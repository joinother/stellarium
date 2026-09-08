import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const device = process.argv[2];
assert.ok(device, 'Pass one connected device ID');
const cli = fileURLToPath(new URL('./stellarium-cli.mjs', import.meta.url));
const hdc = process.env.HDC_BIN || '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc';
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const reports = [];
function command(name, payload, timeout = 15000) {
  const args = [cli, '--device', device, '--command', name, '--json', '--timeout', String(timeout)];
  if (payload !== undefined) args.push('--payload', String(payload));
  const result = JSON.parse(execFileSync(process.execPath, args, { encoding: 'utf8', timeout: timeout + 10000 }));
  assert.equal(result.ok, true, JSON.stringify(result));
  return result;
}
async function state(phase, index) {
  for (let attempt = 0; attempt < 20; attempt++) {
    const response = command('getGuideState');
    if (response.state.phase === phase && (index === undefined || response.state.index === index)) {
      reports.push({ phase, index: response.state.index, result: response.result });
      return response.state;
    }
    assert.notEqual(response.state.phase, 'error', JSON.stringify(response));
    await delay(250);
  }
  throw new Error(`Guide did not reach ${phase} / ${index}`);
}
function layout() {
  execFileSync(hdc, ['-t', device, 'shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/guide-layout.json']);
  execFileSync(hdc, ['-t', device, 'file', 'recv', '/data/local/tmp/guide-layout.json', '/tmp/guide-layout.json']);
  const nodes = [];
  function visit(node) {
    if (node.attributes) nodes.push(node.attributes);
    for (const child of node.children || []) visit(child);
  }
  visit(JSON.parse(readFileSync('/tmp/guide-layout.json', 'utf8')));
  return nodes;
}
function tap(id) {
  const found = layout().filter(node => node.id === id);
  assert.equal(found.length, 1, `${id}: one control`);
  const bounds = found[0].bounds.match(/-?\d+/g).map(Number);
  assert.ok(bounds[0] >= 0 && bounds[1] >= 0 && bounds[2] > bounds[0] && bounds[3] > bounds[1]);
  execFileSync(hdc, ['-t', device, 'shell', 'uitest', 'uiInput', 'click',
    String(Math.round((bounds[0] + bounds[2]) / 2)), String(Math.round((bounds[1] + bounds[3]) / 2))]);
}
function screenshot(name) {
  const remote = `/data/local/tmp/guide-${name}.jpeg`;
  const local = `/tmp/guide-${name}.jpeg`;
  execFileSync(hdc, ['-t', device, 'shell', 'snapshot_display', '-f', remote]);
  execFileSync(hdc, ['-t', device, 'file', 'recv', remote, local]);
  reports.push({ image: local });
}

let ready = false;
for (let attempt = 0; attempt < 30; attempt++) {
  ready = command('getPresentationState', undefined, 30000).ready === true;
  if (ready) break;
  await delay(500);
}
assert.equal(ready, true, 'Wait for the cold-start presentation before testing guides');
const original = command('getSessionState');
const originalTime = command('getSimulationTime');
await delay(3000);
try {
  command('openUiPanel', 'scripts');
  await delay(500);
  screenshot('library');
  command('startGuide', 'solar-neighbours');
  await state('observing', 0);
  assert.equal(command('getSessionState').selected, 'Moon');
  assert.equal(command('getAtmosphereFlags').flags.atmosphere, false);
  await delay(1800);
  screenshot('moon');
  tap('guide-pause');
  await state('paused', 0);
  tap('guide-resume');
  await state('observing', 0);
  tap('guide-next');
  await state('observing', 1);
  command('guideAction', 'explore');
  await state('exploring', 1);
  const beforeDrag = command('getSessionState').viewJ2000;
  execFileSync(hdc, ['-t', device, 'shell', 'uitest', 'uiInput', 'swipe', '1400', '400', '1650', '500', '600']);
  assert.notDeepEqual(command('getSessionState').viewJ2000, beforeDrag);
  tap('guide-return');
  await state('observing', 1);
  assert.equal(command('getSessionState').selected, 'Venus');
  for (const [index, target] of [[2, 'Mars'], [3, 'Jupiter'], [4, 'Saturn']]) {
    command('guideAction', 'next');
    await state('observing', index);
    assert.equal(command('getSessionState').selected, target);
  }
  command('guideAction', 'auto-on');
  command('guideAction', 'pause');
  const paused = await state('paused', 4);
  await delay(1100);
  assert.equal(command('getGuideState').state.remaining, paused.remaining);
  tap('guide-stop');
  await state('idle');
  const restored = command('getSessionState');
  assert.equal(restored.selected, original.selected);
  assert.ok(Math.abs(restored.fovDeg - original.fovDeg) < 0.02);
  assert.deepEqual(restored.location, original.location);
  assert.equal(command('getSimulationTime').timeRate, originalTime.timeRate);
  assert.deepEqual(restored.flags, original.flags);
  command('startGuide', 'deep-sky-discovery');
  await state('observing', 0);
  await delay(1800);
  screenshot('m31');
  command('guideAction', 'next');
  await state('observing', 1);
  command('guideAction', 'next');
  await state('observing', 2);
  command('guideAction', 'next');
  await state('idle');
  writeFileSync('/tmp/guide-pad-report.json', JSON.stringify({ passed: true, reports }, null, 2));
  console.log(JSON.stringify({ passed: true, reports }));
} finally {
  command('guideAction', 'stop');
}
