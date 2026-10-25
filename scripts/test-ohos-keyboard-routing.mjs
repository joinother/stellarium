import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const read = file => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
const plain = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/^@Observed\r?\n/gm, '').replaceAll('export ', ''));
const KeyCode = {
  KEYCODE_0: 2000, KEYCODE_9: 2009, KEYCODE_A: 2017, KEYCODE_Z: 2042,
  KEYCODE_DPAD_UP: 2012, KEYCODE_DPAD_DOWN: 2013, KEYCODE_DPAD_LEFT: 2014, KEYCODE_DPAD_RIGHT: 2015,
  KEYCODE_SPACE: 2050, KEYCODE_ENTER: 2054, KEYCODE_DEL: 2055,
  KEYCODE_MINUS: 2057, KEYCODE_EQUALS: 2058, KEYCODE_LEFT_BRACKET: 2059, KEYCODE_RIGHT_BRACKET: 2060,
  KEYCODE_PLUS: 2066, KEYCODE_PAGE_UP: 2068, KEYCODE_PAGE_DOWN: 2069,
  KEYCODE_ESCAPE: 2070, KEYCODE_FORWARD_DEL: 2071, KEYCODE_MOVE_HOME: 2081, KEYCODE_MOVE_END: 2082,
  KEYCODE_F1: 2090, KEYCODE_F12: 2101
};
const Store = new Function(`${plain(read('harmonyos/ets-source/state/KeyboardShortcutStore.ets'))}; return KeyboardShortcutStore;`)();
const Controller = new Function('KeyCode', 'KeyType', 'I18n', `${plain(read('harmonyos/ets-source/capability/KeyboardShortcutController.ets'))}; return KeyboardShortcutController;`)(KeyCode, { Down: 0, Up: 1 }, { t: key => key });
const event = (keyCode, modifiers = [], overrides = {}) => ({
  type: 0, keyCode, keyText: 'UNRELIABLE KEY NAME', metaKey: 0,
  getModifierKeyState: keys => keys.every(key => modifiers.includes(key)), ...overrides
});
function fixture() {
  const store = new Store();
  const requests = [];
  const effects = [];
  const controller = new Controller(store, {
    requestInteractive: (name, payload, success, failure) => requests.push({ name, payload, success, failure }),
    fire: (...args) => effects.push(args)
  }, { flashHint: text => effects.push(['hint', text]) });
  const hooks = {
    skyWidth: () => 1280, skyHeight: () => 800,
    zoomStep: factor => effects.push(['zoom', factor]),
    centerSelectedObjectFromKeyboard: () => effects.push(['center']),
    moveToSelectedObject: () => effects.push(['move']),
    closeKeyboardOverlay: () => effects.push(['close'])
  };
  return { store, controller, requests, effects, key: input => controller.handleSkyKey(input, hooks),
    panelKey: input => controller.handlePanelKey(input, hooks) };
}

test('unfocused sky never consumes typing, Delete, editing chords or IME keys', () => {
  const context = fixture();
  for (const code of [2030, 2055, 2071, 2014, 2050, 2054, 2070, 2049]) {
    assert.equal(context.key(event(code)), false);
    assert.equal(context.key(event(code, ['Ctrl'])), false);
  }
  assert.deepEqual(context.requests, []);
  assert.deepEqual(context.effects, []);
});

test('physical codes work without keyText and retain Backspace versus forward Delete', () => {
  const cases = [[2055, 'BACKSPACE'], [2071, 'DELETE'], [2081, 'HOME'], [2082, 'END'],
    [2059, '['], [2060, ']'], [2012, 'UP'], [2013, 'DOWN'], [2014, 'LEFT'], [2015, 'RIGHT'],
    [2068, 'PAGEUP'], [2069, 'PAGEDOWN'], [2050, 'SPACE'], [2054, 'ENTER'], [2057, 'MINUS'], [2066, 'PLUS']];
  for (let index = 0; index < 26; index++) cases.push([2017 + index, String.fromCharCode(65 + index)]);
  for (let index = 0; index < 10; index++) cases.push([2000 + index, String(index)]);
  for (let index = 0; index < 12; index++) cases.push([2090 + index, `F${index + 1}`]);
  const native = read('src/StelMainView.cpp');
  for (const [code, token] of cases) {
    const context = fixture();
    context.controller.setSkyFocused(true);
    assert.equal(context.key(event(code, [], { keyText: '' })), true);
    if (['UP', 'DOWN', 'LEFT', 'RIGHT', 'PAGEUP', 'PAGEDOWN', 'HOME', 'END'].includes(token)) {
      assert.deepEqual(context.effects, [['sendKey', `${token}|down`]]);
      assert.deepEqual(context.requests, []);
    } else {
      assert.equal(context.requests[0].payload, token);
    }
    if (token.length > 1) assert.ok(native.includes(`QStringLiteral("${token}")`), `${token} unsupported by sendKey`);
  }
});

test('modified chords never fall back to naked keys, including modified Escape', () => {
  for (const modifiers of [['Ctrl'], ['Alt'], ['Shift'], ['Ctrl', 'Alt', 'Shift']]) {
    for (const code of [2030, 2022, 2050, 2054, 2070]) {
      const context = fixture();
      context.controller.setSkyFocused(true);
      assert.equal(context.key(event(code, modifiers)), true);
      assert.ok(context.requests[0].payload.startsWith(modifiers.join('+').toUpperCase() + '+'));
      context.requests[0].success({ ok: true, accepted: false });
      assert.deepEqual(context.effects, []);
    }
  }
});

test('unsupported keys and modifier lookup failures fail closed; Tab remains focus navigation', () => {
  for (const input of [event(2049), event(2049, ['Shift']), event(2103), event(9999, [], { keyText: 'N' }),
    event(2030, [], { metaKey: 1 }), event(2030, [], { getModifierKeyState: undefined }),
    event(2030, [], { getModifierKeyState: () => { throw new Error('unavailable'); } }), event(2058, ['Ctrl'])]) {
    const context = fixture();
    context.controller.setSkyFocused(true);
    assert.equal(context.key(input), false);
    assert.deepEqual(context.requests, []);
    assert.deepEqual(context.effects, []);
  }
});

test('equals uses explicit compatibility zoom; Shift+equals sends actual plus with Shift', () => {
  const context = fixture();
  context.controller.setSkyFocused(true);
  assert.equal(context.key(event(2058)), true);
  assert.deepEqual(context.effects, [['zoom', 0.8]]);
  assert.deepEqual(context.requests, []);
  context.key(event(2058, [], { type: 1 }));
  context.key(event(2058, ['Shift']));
  assert.equal(context.requests[0].payload, 'SHIFT+PLUS');
});

test('toggle repeats are suppressed until release; focus loss clears held state', () => {
  const context = fixture();
  context.controller.setSkyFocused(true);
  context.key(event(2030));
  context.key(event(2030));
  assert.equal(context.requests.length, 1);
  assert.equal(context.key(event(2030, [], { type: 1 })), true);
  context.key(event(2030));
  assert.equal(context.requests.length, 2);
  context.controller.setSkyFocused(false);
  assert.equal(context.key(event(2030, [], { type: 1 })), false);
  context.controller.setSkyFocused(true);
  context.key(event(2030));
  assert.equal(context.requests.length, 3);
});

test('only explicit unaccepted success may fall back; stale focus and transport errors cannot', () => {
  for (const response of [{ ok: false, accepted: false }, { ok: true }, { ok: true, accepted: true }]) {
    const context = fixture();
    context.controller.setSkyFocused(true);
    context.key(event(2050));
    context.requests[0].success(response);
    assert.deepEqual(context.effects, []);
    assert.equal(context.requests[0].failure, undefined);
  }
  const context = fixture();
  context.controller.setSkyFocused(true);
  context.key(event(2050));
  context.controller.setSkyFocused(false);
  context.controller.setSkyFocused(true);
  context.requests[0].success({ ok: true, accepted: false });
  assert.deepEqual(context.effects, []);
  context.key(event(2050));
  context.requests[1].success({ ok: true, accepted: false });
  assert.deepEqual(context.effects, [['center']]);
});

test('cleared F/N shortcuts do not resurrect undocumented search/night actions', () => {
  const context = fixture();
  context.controller.setSkyFocused(true);
  for (const code of [2022, 2030]) {
    context.key(event(code));
    context.requests.at(-1).success({ ok: true, accepted: false });
  }
  assert.deepEqual(context.effects, []);
});

test('root panel handler consumes only bare Escape and never forwards editing keys', () => {
  const context = fixture();
  for (const code of [2030, 2055, 2071, 2014, 2050, 2054, 2049]) {
    assert.equal(context.panelKey(event(code)), false);
  }
  for (const modifiers of [['Ctrl'], ['Alt'], ['Shift']]) {
    assert.equal(context.panelKey(event(2070, modifiers)), false);
  }
  assert.equal(context.panelKey(event(2070)), true);
  assert.equal(context.panelKey(event(2070)), true);
  assert.deepEqual(context.effects, [['close']]);
  assert.equal(context.panelKey(event(2070, [], { type: 1 })), true);
  context.panelKey(event(2070));
  assert.deepEqual(context.effects, [['close'], ['close']]);
  assert.deepEqual(context.requests, []);
});

test('held navigation sends exactly one down and one up, retaining initial modifiers', () => {
  for (const [code, token] of [[2012, 'UP'], [2013, 'DOWN'], [2014, 'LEFT'], [2015, 'RIGHT'],
    [2068, 'PAGEUP'], [2069, 'PAGEDOWN'], [2081, 'HOME'], [2082, 'END']]) {
    const context = fixture();
    context.controller.setSkyFocused(true);
    context.key(event(code, ['Ctrl', 'Shift']));
    context.key(event(code));
    context.key(event(code, ['Alt']));
    assert.deepEqual(context.effects, [['sendKey', `CTRL+SHIFT+${token}|down`]]);
    assert.equal(context.key(event(code, [], { type: 1, getModifierKeyState: undefined })), true);
    assert.deepEqual(context.effects, [['sendKey', `CTRL+SHIFT+${token}|down`], ['sendKey', `CTRL+SHIFT+${token}|up`]]);
    assert.equal(context.key(event(code, [], { type: 1 })), false);
    assert.deepEqual(context.requests, []);
  }
});

test('focus loss releases every native held key before next focus and does not release twice', () => {
  const context = fixture();
  context.controller.setSkyFocused(true);
  context.key(event(2012, ['Ctrl']));
  context.key(event(2014));
  context.key(event(2069, ['Alt']));
  context.key(event(2030));
  context.controller.setSkyFocused(false);
  assert.deepEqual(context.effects, [
    ['sendKey', 'CTRL+UP|down'], ['sendKey', 'LEFT|down'], ['sendKey', 'ALT+PAGEDOWN|down'],
    ['sendKey', 'CTRL+UP|up'], ['sendKey', 'LEFT|up'], ['sendKey', 'ALT+PAGEDOWN|up']
  ]);
  context.controller.setSkyFocused(false);
  assert.equal(context.key(event(2012, [], { type: 1 })), false);
  assert.equal(context.effects.length, 6);
  context.controller.setSkyFocused(true);
  context.key(event(2012));
  assert.deepEqual(context.effects.at(-1), ['sendKey', 'UP|down']);
  assert.equal(context.requests.length, 1);
});

test('rapid down/up/down keeps queue ordering and custom navigation toggles never autorepeat', () => {
  const context = fixture();
  context.controller.setSkyFocused(true);
  context.key(event(2014));
  context.key(event(2014));
  context.key(event(2014, [], { type: 1 }));
  context.key(event(2014));
  context.controller.setSkyFocused(false);
  assert.deepEqual(context.effects, [
    ['sendKey', 'LEFT|down'], ['sendKey', 'LEFT|up'], ['sendKey', 'LEFT|down'], ['sendKey', 'LEFT|up']
  ]);
  assert.deepEqual(context.requests, []);
});

test('navigation has no fallback capable of bypassing native moveKeys or zoomKeys gating', () => {
  const source = read('harmonyos/ets-source/capability/KeyboardShortcutController.ets');
  const fallback = source.slice(source.indexOf('private fallbackKeyboardToken'), source.indexOf('handleSkyKey'));
  assert.doesNotMatch(fallback, /panBy|PAGEUP|PAGEDOWN|case 'UP'|case 'DOWN'|case 'LEFT'|case 'RIGHT'/);
  const movement = read('src/core/StelMovementMgr.cpp');
  assert.match(movement, /void StelMovementMgr::turnLeft\(bool s\)\s*\{\s*if \(s && flagEnableMoveKeys\)/);
  assert.match(movement, /void StelMovementMgr::zoomIn\(bool s\)\s*\{\s*if \(flagEnableZoomKeys\)/);
});

test('native phased dispatch bypasses result cache and keeps legacy single-shot dispatch', () => {
  const native = read('src/StelMainView.cpp');
  const queue = native.slice(native.indexOf('QString runOhosCommandOnQtThread'), native.indexOf('static int ohosTemperatureFromSpType'));
  const phasedQueue = queue.slice(queue.indexOf('if (cmdName == "sendKey"'), queue.indexOf('if (cmdName == "setGyroView"'));
  assert.match(phasedQueue, /key\.count\('\|'\) == 2/);
  assert.match(phasedQueue, /keyPhase == "down" \|\| keyPhase == "up"/);
  assert.match(phasedQueue, /s_ohosCmdQueue\.append/);
  assert.match(phasedQueue, /result\["queued"\] = true/);
  assert.doesNotMatch(phasedQueue, /s_ohosCmdCache|s_ohosCmdInflight|pending/);
  const dispatch = native.slice(native.indexOf('if (commandName == "sendKey")'), native.indexOf('if (commandName == "getKeyboardShortcuts")'));
  assert.match(dispatch, /keyArguments\.size\(\) > 2/);
  assert.match(dispatch, /pressedKeys\.insert\(keyCode, modifiers\)/);
  assert.match(dispatch, /result\["duplicate"\] = true/);
  assert.match(dispatch, /originalModifiers = pressed\.value\(\)/);
  assert.match(dispatch, /QKeyEvent release\(QEvent::KeyRelease, keyCode, originalModifiers\)/);
  assert.match(dispatch, /QKeyEvent press\(QEvent::KeyPress, keyCode, modifiers\);\s*StelApp::getInstance\(\)\.handleKeyEvent\(&press\);\s*QKeyEvent release\(QEvent::KeyRelease, keyCode, modifiers\)/);
  const disableZoom = native.slice(native.indexOf('else if (key == "zoomKeys")'), native.indexOf('else if (key == "gravityLabels")'));
  assert.ok(disableZoom.indexOf('zoomIn(false)') < disableZoom.indexOf('setFlagEnableZoomKeys(enabled)'));
  assert.match(dispatch, /action->matches\(sequence\) != QKeySequence::NoMatch/);
  assert.match(dispatch, /s_ohosKeyboardPanKeys\.insert\(keyCode\)/);
  assert.match(dispatch, /s_ohosKeyboardPanKeys\.remove\(keyCode\)/);
  assert.match(native, /app\.update\(dt\);\s*if \(!s_ohosKeyboardPanKeys\.isEmpty\(\)\)\s*ohosCaptureSelectedZoomAnchor\(\)/);
});

test('shortcut editor accepts only representable PortableText single chords', () => {
  for (const shortcut of ['Ctrl+N', 'Alt+Shift+F12', 'Ctrl++', '+', '-', '[', 'Ctrl+Del',
    'PgUp', 'PgDown', 'Return', 'Space', 'Backspace', 'Ctrl+Esc', '']) {
    const context = fixture();
    Object.assign(context.store, { keyboardShortcutSelectedId: 'actionShow_Night_Mode', keyboardShortcutPrimary: shortcut });
    context.controller.save();
    assert.equal(context.requests[0]?.name, 'setKeyboardShortcut', shortcut);
    assert.equal(context.requests[0].payload, `actionShow_Night_Mode|${shortcut}|`);
  }
  for (const shortcut of ['Tab', 'Shift+Tab', 'Esc', 'Meta+N', 'F13', '/', '=', 'Ctrl+K, Ctrl+C',
    'Ctrl+Ctrl+N', 'N|F', 'Enter', 'PLUS', 'Ctrl+', 'Num+1', '']) {
    const context = fixture();
    Object.assign(context.store, { keyboardShortcutSelectedId: 'actionShow_Night_Mode',
      keyboardShortcutPrimary: 'Ctrl+N', keyboardShortcutAlternate: shortcut || '/' });
    context.controller.save();
    assert.deepEqual(context.requests, [], shortcut);
    assert.equal(context.effects[0]?.[0], 'hint');
  }
});

if (process.argv.includes('--check-glue')) {
  test('host binds keyboard only to the childless sky focus leaf', () => {
    const page = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
    assert.doesNotMatch(page, /this\.skyInputCtl\(\)\.handleSkyKey\(event\)/);
    assert.match(page, /Stack\(\)\s*\{\s*\}\s*\.id\('sky-keyboard-target'\)/);
    assert.match(page, /\.onFocus\(\(\) => \{ this\.keyboardShortcutCtl\(\)\.setSkyFocused\(true\)/);
    assert.match(page, /\.onBlur\(\(\) => \{ this\.keyboardShortcutCtl\(\)\.setSkyFocused\(false\)/);
    assert.match(page, /this\.keyboardShortcutCtl\(\)\.handleSkyKey\(event, this\.keyboardInputHooks\(\)\)/);
    assert.match(page, /getFocusController\(\)\.requestFocus\('sky-keyboard-target'\)/);
    assert.match(page, /this\.keyboardShortcutCtl\(\)\.handlePanelKey\(event, this\.keyboardInputHooks\(\)\)/);
    assert.match(page, /onSkyTouch: \(event: TouchEvent\) => \{ this\.handleSkySurfaceTouch\(event\)/);
  });
}
