import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const device = process.argv[2];
assert.ok(device, 'Pass the connected Pad device ID');
const cli = fileURLToPath(new URL('./stellarium-cli.mjs', import.meta.url));
const hdc = process.env.HDC_BIN || '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc';
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

function command(name, payload) {
  const args = [cli, '--device', device, '--command', name, '--json', '--timeout', '12000'];
  if (payload !== undefined) args.push('--payload', String(payload));
  const result = JSON.parse(execFileSync(process.execPath, args, { encoding: 'utf8', timeout: 30000 }));
  assert.equal(result.ok, true, JSON.stringify(result));
  return result;
}

const report = [];
function layoutNodes() {
  const remote = '/data/local/tmp/polar-hit-layout.json';
  const local = '/tmp/polar-hit-layout.json';
  execFileSync(hdc, ['-t', device, 'shell', 'uitest', 'dumpLayout', '-p', remote]);
  execFileSync(hdc, ['-t', device, 'file', 'recv', remote, local]);
  const nodes = [];
  function visit(node) {
    if (node.attributes) nodes.push(node.attributes);
    for (const child of node.children || []) visit(child);
  }
  visit(JSON.parse(readFileSync(local, 'utf8')));
  return nodes;
}

function clickControl(id) {
  const node = layoutNodes().find(item => item.id === id);
  assert.ok(node, `${id} is present`);
  const bounds = node.bounds.match(/-?\d+/g).map(Number);
  if (!id.includes('-flip-')) {
    assert.ok(bounds[1] >= 0 && bounds[3] < 300, `${id} remains in the safe top control strip`);
  }
  const centerX = Math.round((bounds[0] + bounds[2]) / 2);
  const centerY = Math.round((bounds[1] + bounds[3]) / 2);
  execFileSync(hdc, ['-t', device, 'shell', 'uitest', 'uiInput', 'click', String(centerX), String(centerY)]);
}

async function capture(name) {
  await pause(800);
  const result = command('getPolarScopeData').polarScope;
  assert.ok(result);
  assert.ok(Math.abs(result.scopeRadiusPixels - result.poleStarRadiusPixels) < 0.01);
  const path = `/tmp/polar-regression-${name}.jpeg`;
  const remote = `/data/local/tmp/polar-regression-${name}.jpeg`;
  execFileSync(hdc, ['-t', device, 'shell', 'snapshot_display', '-f', remote]);
  execFileSync(hdc, ['-t', device, 'file', 'recv', remote, path]);
  report.push({ name, radius: result.scopeRadiusPixels, poleX: result.poleScreenXRatio,
    poleY: result.poleScreenYRatio, image: path });
  return result;
}

command('closeUiPanel');
await pause(1500);
const original = command('getSessionState');
assert.ok(original.viewJ2000 && original.flags);
try {
  command('openUiPanel', 'polarScope');
  await pause(1800);
  command('setAtmosphereFlag', 'atmosphere|0');
  const base = await capture('base');
  command('setFOV', 1.5);
  const zoom = await capture('zoom');
  assert.ok(zoom.scopeRadiusPixels > base.scopeRadiusPixels * 2);
  command('dragView', '1280|800|1680|940');
  const moved = await capture('pan');
  assert.ok(Math.hypot(moved.poleScreenXRatio - zoom.poleScreenXRatio,
    moved.poleScreenYRatio - zoom.poleScreenYRatio) > 0.02);
  execFileSync(hdc, ['-t', device, 'shell', 'uitest', 'uiInput', 'swipe', '420', '440', '620', '500', '600']);
  const touched = await capture('touch-pan');
  assert.ok(Math.hypot(touched.poleScreenXRatio - moved.poleScreenXRatio,
    touched.poleScreenYRatio - moved.poleScreenYRatio) > 0.01, 'the exposed sky accepts a real drag');
  const beforeFlip = command('getSessionState').flags;
  clickControl('polar-scope-flip-horizontal');
  clickControl('polar-scope-flip-vertical');
  await capture('flips');
  const afterFlip = command('getSessionState').flags;
  assert.equal(afterFlip.flipHorz, !beforeFlip.flipHorz);
  assert.equal(afterFlip.flipVert, !beforeFlip.flipVert);
  clickControl('polar-scope-center');
  await pause(1500);
  const centered = command('getPolarScopeData').polarScope;
  assert.ok(Math.abs(centered.poleScreenXRatio - 0.5) < 0.05);
  assert.ok(Math.abs(centered.poleScreenYRatio - 0.5) < 0.05);
  command('setFOV', 8);
  const wide = await capture('wide');
  assert.ok(wide.scopeRadiusPixels < base.scopeRadiusPixels);
  clickControl('polar-scope-close');
  await pause(1500);
  assert.ok(!layoutNodes().some(node => node.id === 'polar-scope-close'), 'touch closes the overlay');
  writeFileSync('/tmp/polar-regression-report.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ passed: true, touchClose: true, touchCenter: true, touchFlips: true, scenarios: report }));
} finally {
  command('closeUiPanel');
  await pause(1500);
  command('applySessionState', JSON.stringify(original));
}
