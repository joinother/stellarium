import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const device = process.argv[2];
assert.ok(device, 'Pass an explicitly selected test device; this test overwrites its clipboard with test text');
const cli = fileURLToPath(new URL('./stellarium-cli.mjs', import.meta.url));
const results = [];
function command(name, payload) {
  const args = [cli, '--device', device, '--command', name, '--json'];
  if (payload !== undefined) args.push('--payload', String(payload));
  const started = performance.now();
  const response = JSON.parse(execFileSync(process.execPath, args, { encoding: 'utf8', timeout: 45000 }));
  assert.equal(response.ok, true, JSON.stringify(response));
  results.push({ command: name, elapsedMs: Math.round(performance.now() - started), ok: response.ok });
  return response;
}

assert.equal(command('getPresentationState').ready, true);
command('openUiPanel', 'layers');
try {
  for (let attempt = 0; attempt < 20; attempt++) {
    command('setLayerTab', attempt % 5);
    const text = `SkyInstrument clipboard regression ${attempt}`;
    const copied = command('copyTextToClipboard', text);
    assert.deepEqual(copied, { ok: true, characters: text.length });
    command('getTimeInfo');
    assert.equal(command('getPresentationState').ready, true);
  }
} finally {
  command('closeUiPanel');
  writeFileSync('/tmp/review-clipboard-pad.json', JSON.stringify(results, null, 2) + '\n');
}
console.log(JSON.stringify({ copies: 20, responses: results.length,
  maxTransportElapsedMs: Math.max(...results.map(result => result.elapsedMs)) }));
