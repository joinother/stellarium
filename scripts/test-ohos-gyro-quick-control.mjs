import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

// The gyro quick-control now spans three files after the refactor:
// optimistic state in state/GyroStore.ets, the debounced toggle in
// capability/SensorController.ets and the dock/quick entry points in
// pages/MainWindowNativeNode.ets.
const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const source = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
const gyroStore = read('harmonyos/ets-source/state/GyroStore.ets');
const sensorCtl = read('harmonyos/ets-source/capability/SensorController.ets');

for (const token of ['gyroscopePending: boolean = false', 'gyroscopePendingTarget: boolean = false']) {
  assert.ok(gyroStore.includes(token), `${token} missing from GyroStore`);
}
for (const token of ['gyroscopeVisualEnabled(): boolean', 'gyroIndicatorColor(): string']) {
  assert.ok(gyroStore.includes(token), `${token} missing from GyroStore`);
}
for (const token of [
  'requestGyroscopeToggle(enabled: boolean): void',
  "this.hooks.flashHint(enabled ? I18n.t('m_gyro_listening') : I18n.t('m_gyro_off'))",
  "hilog.info(0x0000, 'StellariumArkUI', '[gyro-ui] duplicate tap ignored')",
  'this.gyroStore.gyroscopePending = false'
]) {
  assert.ok(sensorCtl.includes(token), `${token} missing from SensorController`);
}
for (const token of [
  'this.gyroCtl().requestGyroscopeToggle(!this.gyroStore.gyroscopeVisualEnabled())',
  "if (quickId === 'gyro')"
]) {
  assert.ok(source.includes(token), `${token} missing from the gyro quick-control path`);
}

assert.ok(
  source.indexOf('this.gyroCtl().requestGyroscopeToggle(!this.gyroStore.gyroscopeVisualEnabled())') <
    source.indexOf('private handleCompactTopQuickTouch'),
  'compact quick control must route through the guarded toggle helper'
);

console.log('HarmonyOS gyro quick-control feedback contract passed.');
