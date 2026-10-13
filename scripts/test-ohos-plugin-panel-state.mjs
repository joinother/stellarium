import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

// D12：setNebulaTextureFlag 已下沉 capability/NebulaTextureController.ets（桥经 CommandPort.requestInteractive）。
// D9：setMosaicCamera 已下沉 capability/OcularController.ets（桥经 CommandPort.requestInteractive）。
const nebulaSource = readFileSync(new URL('../harmonyos/ets-source/capability/NebulaTextureController.ets', import.meta.url), 'utf8');
const ocularSource = readFileSync(new URL('../harmonyos/ets-source/capability/OcularController.ets', import.meta.url), 'utf8');
const localization = { t: key => key };
function methodIn(src, name, args) {
  const match = src.match(new RegExp(`(?:private )?${name}\\([^\\n]*\\): void \\{([\\s\\S]*?)\\n  \\}`));
  assert.ok(match, name);
  return new Function(...args, 'I18n', match[1].replaceAll(': StellariumBridgeResponse', '').replaceAll(' as NebulaTextureStatus', ''));
}
const mosaic = methodIn(ocularSource, 'setMosaicCamera', ['setting', 'value']);
const texture = methodIn(nebulaSource, 'setNebulaTextureFlag', ['command', 'enabled', 'current']);

function state() {
  const reloads = [];
  const calls = [];
  return {
    mosaicStore: {
      mosaicCameraPending: false, mosaicCameraLoading: false, mosaicCameraEnabled: false,
      mosaicCameraVisible: false, mosaicCameraCurrent: 'LSSTCam',
      loadMosaicCamera(initial) { reloads.push(initial); }
    },
    nebulaTextureStore: {
      nebulaTexturePending: false, nebulaTextureLoading: false, nebulaTextureImporting: false,
      nebulaTextureActionStatus: '', nebulaTextureStatus: { enabled: false }
    },
    calls, reloads,
    callInteractive(name, payload, success, failure) { calls.push({ name, payload, success, failure }); },
    port: { requestInteractive(name, payload, success, failure) { calls.push({ name, payload, success, failure }); } }
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
  assert.equal(model.mosaicStore.mosaicCameraLoading, false);
});

test('camera failure releases the lock without pretending the action succeeded', () => {
  const model = state();
  mosaic.call(model, 'enabled', '1', localization);
  model.calls[0].success({ ok: false, error: 'test failure' });
  assert.equal(model.mosaicStore.mosaicCameraPending, false);
  assert.equal(model.mosaicStore.mosaicCameraEnabled, false);
  assert.equal(model.mosaicStore.mosaicCameraStatus, 'test failure');
});

test('texture toggles wait for authoritative state and ignore feedback', () => {
  const model = state();
  texture.call(model, 'setNebulaTexturesVisible', false, false, localization);
  texture.call(model, 'setNebulaTexturesVisible', true, false, localization);
  texture.call(model, 'setNebulaTexturesVisible', true, false, localization);
  assert.equal(model.calls.length, 1);
  assert.equal(model.nebulaTextureStore.nebulaTextureStatus.enabled, false);
  model.calls[0].success({ ok: true, enabled: true });
  assert.equal(model.nebulaTextureStore.nebulaTexturePending, false);
  texture.call(model, 'setNebulaTexturesVisible', true, model.nebulaTextureStore.nebulaTextureStatus.enabled, localization);
  assert.equal(model.calls.length, 1);
});

test('texture transport failure releases the lock and retains the saved state', () => {
  const model = state();
  texture.call(model, 'setNebulaTexturesVisible', true, false, localization);
  model.calls[0].failure();
  assert.equal(model.nebulaTextureStore.nebulaTexturePending, false);
  assert.equal(model.nebulaTextureStore.nebulaTextureStatus.enabled, false);
});
