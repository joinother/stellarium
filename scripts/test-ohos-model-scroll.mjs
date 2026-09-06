import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const stageStart = source.indexOf(".id('object-model-inline-stage')");
const stage = source.slice(stageStart, source.indexOf('Text(this.objectInspectorModelNotice())', stageStart));

test('only the bounded model captures touch; the outer card isolates the sky', () => {
  assert.match(stage, /HitTestMode.BLOCK_HIERARCHY/);
  assert.match(stage, /onTouch.*handleObjectInspectorModelTouch\(event\)/);
  assert.doesNotMatch(stage, /PanDirection|onGestureJudgeBegin|parallelGesture/);
  assert.match(source.slice(stageStart - 230, stageStart), /width\(this.objectInspectorInlineModelSize\(\)\).height\(this.objectInspectorInlineModelSize\(\)\)/);
  assert.equal((source.match(/height\(this.detailCardHeight\(\)\)\s*\.zIndex\(\d+\)\s*\.hitTestBehavior\(HitTestMode.BLOCK_HIERARCHY\)/g) ?? []).length, 3);
  assert.match(source, /Scroll\(this.objectDetailScroller\)/);
  assert.match(source, /stellariumObjectDetailScrollY.*currentOffset\(\)\?\.yOffset/);
});

test('compact and wide cards reserve at least 40vp per side', () => {
  const start = source.indexOf('  private objectInspectorInlineModelSize(');
  const method = source.slice(start, source.indexOf('\n  }', start) + 4);
  const Controller = new Function(stripTypeScriptTypes('class Controller {\n' + method + '\n}') + ';return Controller;')();
  for (const width of [280, 286, 318, 340, 380, 480]) {
    const controller = new Controller();
    controller.bottomCardWidth = () => width;
    const size = controller.objectInspectorInlineModelSize();
    assert.ok(size <= 200);
    assert.ok((width - 32 - size) / 2 >= 40);
  }
});

test('inline and full screen retain unrestricted rotation and pinch with cleanup', () => {
  const overlay = source.slice(source.indexOf('private objectInspectorModelOverlay()'), source.indexOf('private handleObjectInspectorModelTouch'));
  assert.match(overlay, /handleObjectInspectorModelTouch\(event\)/);
  assert.match(overlay, /HitTestMode.BLOCK_HIERARCHY/);
  assert.match(overlay, /object-model-close/);
  const handler = source.slice(source.indexOf('private handleObjectInspectorModelTouch'), source.indexOf('private objectInspectorInlineModelSize'));
  assert.match(handler, /rotateObjectInspectorModel\(deltaX, deltaY\)/);
  assert.match(handler, /objectInspectorModelScale \* scaleFactor/);
  assert.match(handler, /TouchType.Up.*TouchType.Cancel/);
  assert.match(handler, /objectInspectorModelInteracting = false/);
  assert.match(handler, /requestObjectInspectorModelRender\(true\)/);
});

function touchHarness() {
  const start = source.indexOf('  private handleObjectInspectorModelTouch(');
  const method = source.slice(start, source.indexOf('\n  }', start) + 4);
  const TouchType = { Down: 0, Move: 1, Up: 2, Cancel: 3 };
  const Controller = new Function('TouchType', stripTypeScriptTypes('class Controller {\n' + method + '\n}') + ';return Controller;')(TouchType);
  const controller = new Controller();
  const moves = [];
  const renders = [];
  Object.assign(controller, { objectInspectorModelScale: 1,
    touchScreenX: point => point.x, touchScreenY: point => point.y,
    rotateObjectInspectorModel: (...values) => moves.push(values),
    requestObjectInspectorModelRender: quality => renders.push(quality) });
  const touch = (type, points) => controller.handleObjectInspectorModelTouch({ type: TouchType[type],
    touches: points.map(([x, y]) => ({ x, y })), changedTouches: [], stopPropagation() {} });
  return { controller, moves, renders, touch };
}

test('touch handler preserves horizontal, vertical and diagonal movement', () => {
  const { moves, renders, controller, touch } = touchHarness();
  touch('Down', [[0, 0]]);
  touch('Move', [[20, 0]]);
  touch('Move', [[20, 30]]);
  touch('Move', [[10, 15]]);
  touch('Up', []);
  assert.deepEqual(moves, [[20, 0], [0, 30], [-10, -15]]);
  assert.deepEqual(renders, [true]);
  assert.equal(controller.objectInspectorModelInteracting, false);
});

test('two-finger pinch changes scale without orbit and cancellation resets interaction', () => {
  const { moves, controller, touch } = touchHarness();
  touch('Down', [[0, 0], [100, 0]]);
  touch('Move', [[0, 0], [110, 0]]);
  assert.ok(controller.objectInspectorModelScale > 1);
  touch('Move', [[0, 0], [90, 0]]);
  assert.ok(controller.objectInspectorModelScale < 1);
  assert.deepEqual(moves, []);
  touch('Cancel', []);
  assert.equal(controller.objectInspectorModelInteracting, false);
  assert.equal(controller.objectInspectorModelTouchCount, 0);
  assert.equal(controller.objectInspectorModelLastPinchDistance, 0);
});
