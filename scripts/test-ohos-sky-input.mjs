import assert from 'node:assert/strict';
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync('harmonyos/ets-source/capability/SkyInputController.ets', 'utf8');
const executable = source.replace(/^import .*\r?\n/gm, '').replaceAll('export ', '')
  .replace(/enum SkyGestureOwner \{([^}]+)\}/, (_, names) =>
    `const SkyGestureOwner = { ${names.split(',').map((name, index) => `${name.trim()}: ${index}`).join(', ')} };`);
const plain = stripTypeScriptTypes(executable);
const MouseAction = { Press: 1, Release: 2, Move: 3, CANCEL: 13 };
const MouseButton = { None: 0, Left: 1, Right: 2 };
const AxisAction = { NONE: 0, BEGIN: 1, UPDATE: 2, END: 3, CANCEL: 4 };
const SourceTool = { Unknown: 0, Finger: 1, MOUSE: 7, TOUCHPAD: 9 };
const SourceType = { TouchScreen: 1, Mouse: 2 };
const logs = [];
const Controller = new Function('MouseAction', 'MouseButton', 'AxisAction', 'SourceTool', 'SourceType',
  'distance', 'hilog', plain + '\nreturn SkyInputController;')(
  MouseAction, MouseButton, AxisAction, SourceTool, SourceType,
  (firstX, firstY, secondX, secondY) => Math.hypot(firstX - secondX, firstY - secondY),
  { info: (...args) => logs.push(args) });

function fixture() {
  const commands = [];
  const taps = [];
  const wheels = [];
  const state = { fov: 60, startFov: 60, pinch: false, navigation: true, zoom: true, pauses: 0, resumes: 0, checkpoints: 0 };
  const port = { fire(name, payload = '') {
    commands.push({ name, payload });
    const parts = payload.split('|').map(Number);
    if (name === 'beginSkyGesture') state.pinch = false;
    if (name === 'zoomBy') {
      if (parts[1] === 1) {
        state.pinch = true;
        state.startFov = state.fov;
      }
      if (state.pinch) state.fov = state.startFov / parts[0];
    }
    if (name === 'endPinch') state.pinch = false;
  } };
  const hooks = {
    isUiPoint: (x, y) => x < 100 || y < 40,
    skyWidth: () => 1200, skyHeight: () => 800,
    navigationMouseEnabled: () => state.navigation,
    navigationMouseZoomEnabled: () => state.zoom,
    gyroscopeEnabled: () => false,
    keyboardTextInputFocused: () => true,
    cancelSelectedObjectUiChange() {},
    pauseDetailRefreshForSkyDrag: () => state.pauses++,
    resumeDetailRefreshAfterSkyDrag: () => state.resumes++,
    scheduleSkyTextureStatusCheck() {},
    scheduleRecordingViewCheckpoint: () => state.checkpoints++,
    requestFieldOfView: callback => callback(state.fov),
    setFovSliderValue() {}, setCurrentFovText() {},
    zoomStep: factor => { wheels.push(factor); state.fov *= factor; },
    angleMeasureEnabled: () => false,
    requestSkySelection: (x, y) => taps.push([x, y]),
    clearSkySelectionFromDoubleTap: (x, y) => taps.push(['double', x, y])
  };
  const controller = new Controller(port, {}, hooks);
  return { controller, commands, taps, wheels, state, hooks,
    calls: name => commands.filter(command => command.name === name) };
}

function axis(action, overrides = {}) {
  return {
    action, source: SourceType.Mouse, sourceTool: SourceTool.TOUCHPAD,
    x: 400, y: 200, windowX: 430, windowY: 248, scrollStep: 0,
    getHorizontalAxisValue: () => 0, getVerticalAxisValue: () => 0,
    getPinchAxisScaleValue: () => 0, ...overrides
  };
}

function mouse(action, overrides = {}) {
  return { action, button: MouseButton.Left, source: SourceType.Mouse, sourceTool: SourceTool.MOUSE,
    x: 400, y: 200, windowX: 430, windowY: 248, ...overrides };
}

{
  const test = fixture();
  test.controller.handleSkyAxis(axis(AxisAction.BEGIN));
  test.controller.handleSkyAxis(axis(AxisAction.UPDATE, {
    scrollStep: 3, getHorizontalAxisValue: () => 8, getVerticalAxisValue: () => -12
  }));
  test.controller.handleSkyAxis(axis(AxisAction.END));
  assert.deepEqual(test.calls('panBy'), [{ name: 'panBy', payload: '-8.00|12.00|1200|800' }]);
  assert.equal(test.wheels.length, 0);
  assert.equal(test.state.pauses, test.state.resumes);
  assert.equal(test.state.checkpoints, 1);
}

{
  const test = fixture();
  for (const [action, scale] of [[AxisAction.BEGIN, 1], [AxisAction.UPDATE, 1.5], [AxisAction.UPDATE, 2], [AxisAction.UPDATE, 1]]) {
    test.controller.handleSkyAxis(axis(action, { getPinchAxisScaleValue: () => scale }));
    assert.equal(test.state.fov, 60 / scale);
  }
  test.controller.handleSkyAxis(axis(AxisAction.END, { x: 20, y: 20 }));
  assert.equal(test.state.pinch, false);
  assert.equal(test.calls('endPinch').length, 1);
  assert.equal(test.calls('zoomBy')[0].payload, '1|1|400.00|200.00|1200|800');
  assert.equal(test.calls('panBy').length, 0);
  test.controller.handleSkyAxis(axis(AxisAction.BEGIN, { axisPinch: 1.5 }));
  assert.equal(test.state.fov, 40);
  test.controller.handleSkyAxis(axis(AxisAction.CANCEL, { x: NaN, y: NaN }));
  assert.equal(test.state.pinch, false);
  test.controller.handleSkyAxis(axis(AxisAction.BEGIN, { axisPinch: 2 }));
  assert.equal(test.state.fov, 20);
  test.controller.stop();
  assert.equal(test.state.pinch, false);
  assert.equal(test.state.pauses, test.state.resumes);
}

{
  const test = fixture();
  test.controller.handleSkyAxis(axis(AxisAction.BEGIN, { x: 20 }));
  test.controller.handleSkyAxis(axis(AxisAction.UPDATE, { axisPinch: 2, getHorizontalAxisValue: () => 10 }));
  test.controller.handleSkyAxis(axis(AxisAction.END));
  assert.equal(test.commands.length, 0);
  test.controller.handleSkyAxis(axis(AxisAction.UPDATE, { axisPinch: 2 }));
  assert.equal(test.state.fov, 30);
  test.controller.handleSkyAxis(axis(AxisAction.END, { x: NaN }));
  assert.equal(test.state.pinch, false);
}

{
  const test = fixture();
  const wheel = { sourceTool: SourceTool.MOUSE, scrollStep: undefined, getVerticalAxisValue: () => 1 };
  test.controller.handleSkyAxis(axis(AxisAction.BEGIN, wheel));
  test.controller.handleSkyAxis(axis(AxisAction.UPDATE, wheel));
  test.controller.handleSkyAxis(axis(AxisAction.END, wheel));
  assert.deepEqual(test.wheels, [1.12, 1.12]);
  assert.equal(test.calls('zoomBy').length, 0);
  assert.equal(test.calls('panBy').length, 0);
  test.controller.handleSkyAxis(axis(AxisAction.UPDATE, { ...wheel, x: 10 }));
  assert.equal(test.wheels.length, 2);
}

{
  const test = fixture();
  test.controller.handleSkyAxis(axis(AxisAction.BEGIN, { getPinchAxisScaleValue: undefined }));
  test.controller.handleSkyAxis(axis(AxisAction.UPDATE, { getPinchAxisScaleValue: undefined, getVerticalAxisValue: () => 2 }));
  assert.equal(test.calls('panBy').length, 1);
  test.controller.handleSkyAxis(axis(AxisAction.UPDATE, { getHorizontalAxisValue: () => NaN }));
  assert.equal(test.calls('panBy').length, 1);
  test.controller.handleSkyAxis(axis(AxisAction.END));
  test.controller.handleSkyAxis(axis(AxisAction.BEGIN, { axisPinch: 2, getPinchAxisScaleValue: undefined }));
  assert.equal(test.state.fov, 30);
  test.controller.stop();
}

{
  const test = fixture();
  test.state.navigation = false;
  test.state.zoom = false;
  test.controller.handleSkyMouse(mouse(MouseAction.Press));
  test.controller.handleSkyMouse(mouse(MouseAction.Release));
  test.controller.handleSkyAxis(axis(AxisAction.BEGIN, { axisPinch: 2 }));
  test.controller.handleSkyAxis(axis(AxisAction.UPDATE, { getVerticalAxisValue: () => 10 }));
  test.controller.handleSkyAxis(axis(AxisAction.END));
  assert.equal(test.calls('panBy').length, 0);
  assert.equal(test.calls('zoomBy').length, 0);
  assert.equal(test.taps.length, 0);
}

{
  const test = fixture();
  test.controller.handleSkyMouse(mouse(MouseAction.Move, { button: MouseButton.None }));
  assert.equal(test.calls('setPointerPosition')[0].payload, '400|200');
  test.controller.handleSkyMouse(mouse(MouseAction.Press));
  test.controller.handleSkyMouse(mouse(MouseAction.Release));
  assert.deepEqual(test.taps, [[400, 200]]);
  test.controller.handleSkyMouse(mouse(MouseAction.Press, { button: MouseButton.Right }));
  test.controller.handleSkyMouse(mouse(MouseAction.Release, { button: MouseButton.Right }));
  assert.equal(test.taps.length, 1);
  test.controller.handleSkyMouse(mouse(MouseAction.Press));
  test.controller.handleSkyMouse(mouse(MouseAction.Move, { x: 420, y: 210, button: MouseButton.None, pressedButtons: [MouseButton.Left] }));
  assert.equal(test.calls('dragView')[0].payload, '400|200|420|210');
  test.controller.handleSkyMouse(mouse(MouseAction.Release, { button: MouseButton.Right }));
  test.controller.handleSkyMouse(mouse(MouseAction.CANCEL));
  test.controller.handleSkyMouse(mouse(MouseAction.Move, { x: 500 }));
  assert.equal(test.calls('dragView').length, 1);
  assert.equal(test.calls('startPanInertia').length, 0);
  assert.equal(test.state.pauses, test.state.resumes);
}

{
  const test = fixture();
  test.controller.handleSkyMouse(mouse(MouseAction.Press, { x: 20 }));
  test.controller.handleSkyMouse(mouse(MouseAction.Move));
  test.controller.handleSkyMouse(mouse(MouseAction.Release));
  assert.equal(test.taps.length, 0);
  assert.equal(test.calls('dragView').length, 0);
  test.controller.handleSkyMouse(mouse(MouseAction.Press));
  test.controller.handleSkyMouse(mouse(MouseAction.Move, { pressedButtons: [] }));
  test.controller.handleSkyMouse(mouse(MouseAction.Release));
  assert.equal(test.taps.length, 0);
  test.controller.handleSkyTouch({ source: SourceType.Mouse });
  assert.equal(test.taps.length, 0);
}

{
  const test = fixture();
  logs.length = 0;
  for (let index = 0; index < 30; index++) {
    test.controller.handleSkyAxis(axis(AxisAction.BEGIN));
    test.controller.handleSkyAxis(axis(AxisAction.UPDATE));
    test.controller.handleSkyAxis(axis(AxisAction.END));
  }
  assert.equal(logs.length, 32);
  assert.match(logs[0][2], /\[SKY_AXIS\].*sourceTool=.*action=.*pinch=.*horizontal=.*vertical=.*x=.*y=.*owner=/);
  assert.equal(logs[0][3], SourceTool.TOUCHPAD);
  assert.equal(logs[0][4], AxisAction.BEGIN);
}

console.log('HarmonyOS sky input behavior passed: official enums, source classification, local coordinates, pinch lifecycle, mouse ownership, cancellation and bounded diagnostics.');
