import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const source = read('harmonyos/ets-source/qability/ClipboardService.ets');

function fixture() {
  let accepted = true;
  let foreground = true;
  let writes = 0;
  let complete;
  const pasteboard = {
    MIMETYPE_TEXT_PLAIN: 'text/plain',
    createData: (type, text) => ({ type, text }),
    getSystemPasteboard: () => ({ setData() { writes++; return new Promise(resolve => { complete = resolve; }); } }),
  };
  const plain = stripTypeScriptTypes(source.replace(/^import .*\n/gm, '').replaceAll('export ', ''));
  const write = new Function('pasteboard', 'hasCurrentPrivacyConsent', 'AppStorage',
    plain + ';return writeClipboardText;')(pasteboard, () => accepted, { get: () => foreground });
  return { write, pasteboard, setAccepted(value) { accepted = value; }, setForeground(value) { foreground = value; },
    get writes() { return writes; }, finish() { complete(); } };
}

test('clipboard write is consent-gated, foreground-only and bounded', async () => {
  const state = fixture();
  state.setAccepted(false);
  assert.equal((await state.write('test')).ok, false);
  state.setAccepted(true);
  state.setForeground(false);
  assert.equal((await state.write('test')).ok, false);
  state.setForeground(true);
  for (const text of ['', 'x'.repeat(2097153)]) assert.equal((await state.write(text)).ok, false);
  assert.equal(state.writes, 0);
});

test('async copies are single-flight and do not return copied content', async () => {
  const state = fixture();
  const first = state.write('private test text');
  assert.equal(state.writes, 1);
  assert.equal((await state.write('another text')).ok, false);
  state.finish();
  assert.deepEqual(await first, { ok: true, characters: 17 });
  const second = state.write('test');
  state.finish();
  assert.equal((await second).ok, true);
});

test('write failure is reported without the platform error or clipboard data', async () => {
  const state = fixture();
  state.pasteboard.getSystemPasteboard = () => ({ setData: async () => { throw Error('sensitive platform data'); } });
  assert.deepEqual(await state.write('test'), { ok: false, error: 'clipboard write failed' });
  assert.doesNotMatch(source, /getData\(|getDataSync|hilog\./);
});

test('Qt notification patch invalidates cache without reading clipboard content', () => {
  const patch = read('harmonyos/qt-platform-patch/clipboard-notification.patch');
  const added = patch.split('\n').filter(line => line.startsWith('+') && !line.startsWith('+++')).join('\n');
  assert.doesNotMatch(added, /tryGetUdmfData|OH_Pasteboard_GetData|OH_Pasteboard_HasData/);
  assert.match(patch, /-\s+auto optPasteboardUdmfData = tryGetUdmfDataFromPasteboard/);
  assert.match(added, /makeEmptyQOhosOptional\(\)/);
  assert.match(added, /contentRead=false/);
  assert.match(added, /phase=sdk-device-info-read-start; valuesLogged=false/);
  assert.match(added, /phase=sdk-device-info-read-finish; valuesLogged=false/);
  assert.doesNotMatch(read('harmonyos/module.json5'), /READ_PASTEBOARD|ACCESS_UDID/);
});
