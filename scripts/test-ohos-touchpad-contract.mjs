import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const input = read('harmonyos/ets-source/capability/SkyInputController.ets');
const keyboard = read('harmonyos/ets-source/capability/KeyboardShortcutController.ets');
const host = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
const native = read('src/StelMainView.cpp');
const catalog = read('src/StelOhosCommandCatalog.hpp');
const i18n = read('harmonyos/ets-source/capability/I18n.ets');
const guide = read('docs/harmonyos/specs/PC-TOUCHPAD-AND-KEYBOARD-GUIDE.md');

for (const token of [
  'event.getPinchAxisScaleValue()',
  'event.scrollStep',
  'SourceTool.TOUCHPAD',
  'MouseAction.Press',
  'MouseButton.Left',
  'AxisAction.END',
  "commandPort.fire('zoomBy'",
  "commandPort.fire('endPinch'",
  "commandPort.fire('startPanInertia'",
  "commandPort.fire('panBy'"
]) {
  assert.ok(input.includes(token), `${token} missing from the pointer input path`);
}

for (const token of [
  'KeyCode.KEYCODE_SPACE',
  'KeyCode.KEYCODE_ESCAPE',
  'keyboardToken(event, shift)',
  'event.getModifierKeyState',
  'this.store.skyKeyboardFocused',
  "requestInteractive('sendKey'",
  'fallbackKeyboardToken(token, hooks)'
]) {
  assert.ok(keyboard.includes(token), `${token} missing from the connected keyboard controller`);
}
assert.doesNotMatch(input, /handleSkyKey\(|keyboardToken\(|fallbackKeyboardToken\(/);
assert.doesNotMatch(host, /this\.skyInputCtl\(\)\.handleSkyKey\(/);
assert.match(host, /this\.keyboardShortcutCtl\(\)\.handleSkyKey\(event,/);
assert.match(host, /this\.keyboardShortcutCtl\(\)\.handlePanelKey\(event,/);
assert.match(host, /\.onKeyEvent\(\(event: KeyEvent\): boolean => this\.handleSkyKeyboard\(event\)\)/);
assert.match(host, /\.onFocus\(\(\) => \{ this\.keyboardShortcutCtl\(\)\.setSkyFocused\(true\)/);
assert.match(host, /\.onBlur\(\(\) => \{ this\.keyboardShortcutCtl\(\)\.setSkyFocused\(false\)/);

for (const token of ['zoomBy', 'endPinch', 'zoomStep', 'startPanInertia']) {
  assert.match(native, new RegExp(`commandName == "${token}"`), `${token} missing from native bridge`);
  assert.match(catalog, new RegExp(`\\b${token}\\b`), `${token} missing from command catalog`);
}

for (const token of ['getKeyboardShortcuts', 'setKeyboardShortcut', 'resetKeyboardShortcuts']) {
  assert.match(native, new RegExp(`commandName == "${token}"`), `${token} missing from native bridge`);
  assert.match(catalog, new RegExp(`\\b${token}\\b`), `${token} missing from command catalog`);
}

for (const token of ['getDefaultShortcut', 'getDefaultAltShortcut']) {
  assert.match(read('src/core/StelActionMgr.hpp'), new RegExp(token), `${token} missing from action manager`);
}

for (const token of [
  'settings_view_input_guide_title',
  'settings_view_input_guide_touchpad',
  'settings_view_input_guide_mouse',
  'settings_view_input_guide_keyboard'
]) {
  assert.match(i18n, new RegExp(`['"]${token}['"]`), `${token} missing from localized guide`);
}

for (const token of [
  'settings_shortcuts_title',
  'settings_shortcuts_search',
  'settings_shortcuts_primary',
  'settings_shortcuts_alternate',
  'settings_shortcuts_save'
]) {
  assert.match(i18n, new RegExp(`['"]${token}['"]`), `${token} missing from shortcut editor`);
}

for (const token of ['双指滑动', '双指捏合', '不额外启动平移惯性', '快捷键编辑器', 'zoomBy', 'endPinch', 'SourceTool.TOUCHPAD', 'Ctrl+N', 'uinput', '物理触控板']) {
  assert.ok(guide.includes(token), `${token} missing from touchpad guide`);
}

await import('./test-ohos-sky-input.mjs');
await import('./test-ohos-sky-surface-bindings.mjs');
await import('./test-ohos-keyboard-routing.mjs');
console.log('HarmonyOS touchpad and keyboard contract passed.');
