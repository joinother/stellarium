import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const localization = { t: key => key };
function method(name, args) {
  const match = source.match(new RegExp(`private ${name}\\([^\\n]*\\): void \\{([\\s\\S]*?)\\n  \\}`));
  assert.ok(match, name);
  return new Function(...args, 'I18n', match[1].replaceAll(': StellariumBridgeResponse', '').replaceAll(' as NebulaTextureStatus', ''));
}
const mosaic = method('setMosaicCamera', ['setting', 'value']);
const texture = method('setNebulaTextureFlag', ['command', 'enabled', 'current']);

function state() {
  return {
    mosaicCameraPending: false, mosaicCameraLoading: false, mosaicCameraEnabled: false,
    mosaicCameraVisible: false, mosaicCameraCurrent: 'LSSTCam',
    nebulaTexturePending: false, nebulaTextureLoading: false, nebulaTextureImporting: false,
    nebulaTextureStatus: { enabled: false }, calls: [], reloads: [],
    callInteractive(name, payload, success, failure) { this.calls.push({ name, payload, success, failure }); },
    loadMosaicCamera(initial) { this.reloads.push(initial); }
  };
}

test('camera ignores same-value toggle feedback and duplicate in-flight writes', () => {
  const model = state();
  mosaic.call(model, 'enabled', '0', localization);
  mosaic.call(model, 'visible', '0', localization);
  mosaic.call(model, 'camera', 'LSSTCam', localization);
  assert.equal(model.calls.length, 0);
  mosaic.call(model, 'enabled', '1', localization);
  mosaic.call(model, 'enabled', '1', localization);
  assert.equal(model.calls.length, 1);
  model.calls[0].success({ ok: true });
  assert.deepEqual(model.reloads, [false]);
  assert.equal(model.mosaicCameraLoading, false);
});

test('camera failure releases the lock without pretending the action succeeded', () => {
  const model = state();
  mosaic.call(model, 'enabled', '1', localization);
  model.calls[0].success({ ok: false, error: 'test failure' });
  assert.equal(model.mosaicCameraPending, false);
  assert.equal(model.mosaicCameraEnabled, false);
  assert.equal(model.mosaicCameraStatus, 'test failure');
});

test('texture toggles wait for authoritative state and ignore feedback', () => {
  const model = state();
  texture.call(model, 'setNebulaTexturesVisible', false, false, localization);
  texture.call(model, 'setNebulaTexturesVisible', true, false, localization);
  texture.call(model, 'setNebulaTexturesVisible', true, false, localization);
  assert.equal(model.calls.length, 1);
  assert.equal(model.nebulaTextureStatus.enabled, false);
  model.calls[0].success({ ok: true, enabled: true });
  assert.equal(model.nebulaTexturePending, false);
  texture.call(model, 'setNebulaTexturesVisible', true, model.nebulaTextureStatus.enabled, localization);
  assert.equal(model.calls.length, 1);
});

test('texture transport failure releases the lock and retains the saved state', () => {
  const model = state();
  texture.call(model, 'setNebulaTexturesVisible', true, false, localization);
  model.calls[0].failure();
  assert.equal(model.nebulaTexturePending, false);
  assert.equal(model.nebulaTextureStatus.enabled, false);
});
