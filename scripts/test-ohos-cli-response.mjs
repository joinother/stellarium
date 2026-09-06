import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('./stellarium-cli.mjs', import.meta.url), 'utf8');
const readerSource = source.slice(source.indexOf('function readResponse('), source.indexOf('function runCommand('));
const requestId = 'cli-regression';

test('encodes shell-active punctuation left untouched by encodeURIComponent', () => {
  const encoderSource = source.slice(source.indexOf('function encodePayload('), source.indexOf('function runCommand('));
  const encode = runInNewContext(`${encoderSource}; encodePayload`);
  for (const payload of ['catalog|Satellites|ISS (ZARYA)|selectOnly', "Barnard's star", '! * () 中文']) {
    const encoded = encode(payload);
    assert.doesNotMatch(encoded, /[!'()*\s|]/);
    assert.equal(decodeURIComponent(encoded.replace('__STEL_CLI_PAYLOAD_URI__', '')), payload);
  }
});

function receive(snapshots) {
  let poll = 0;
  const reader = runInNewContext(`${readerSource}; readResponse`, {
    RESPONSE_MARKER: '[cli-response]',
    shell: (_options, args) => {
      assert.deepEqual(Array.from(args), ['hilog', '-x', '-T', 'ohosQtTemplate', '-e', requestId]);
      assert.ok(poll < snapshots.length, 'Reader failed to assemble all supplied chunks');
      return snapshots[poll++];
    },
    sleep: () => {},
  });
  return JSON.parse(JSON.stringify(reader({}, requestId, Date.now() + 1000, () => {})));
}

function line(index, count, value) {
  return `[cli-response] requestId=${requestId} command=getSkyCultureDetails chunkIndex=${index} chunkCount=${count} responseChunk=${value}`;
}

test('preserves Unicode line separators inside multilingual JSON strings', () => {
  const response = { ok: true, description: '中国\u2028资料\u2029العربية' };
  assert.deepEqual(receive([line(0, 1, JSON.stringify(response))]), response);
});

test('preserves spaces at chunk boundaries', () => {
  assert.deepEqual(receive([[line(0, 2, '{"ok":true,"description":"first '),
    line(1, 2, ' second"}')].join('\n')]), { ok: true, description: 'first  second' });
});

test('assembles chunks across successive log snapshots without requiring earlier chunks again', () => {
  assert.deepEqual(receive([line(0, 2, '{"ok":true,'), line(1, 2, '"description":"完整"}')]),
    { ok: true, description: '完整' });
});
