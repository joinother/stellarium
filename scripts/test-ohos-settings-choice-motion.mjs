import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
function method(name) {
  const start = source.indexOf(name);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start));
}

test('all four settings groups read current state rather than a captured selection boolean', () => {
  const selected = method('private settingsChoiceSelected(');
  for (const state of ['informationMode', 'configDateFormat', 'configTimeFormat', 'startupTimeMode']) {
    assert.ok(selected.includes(`this.${state} === value`), state);
  }
  for (const group of ['information', 'date', 'time', 'startup']) {
    assert.ok(source.includes(`this.settingsChoiceButton('${group}',`), group);
  }
});

test('choice buttons have an explicit normal type and shared control radius', () => {
  const button = method('settingsChoiceButton(group:');
  assert.match(button, /Button\(\{ type: ButtonType.Normal \}\)/);
  assert.match(button, /borderRadius\(UI_RADIUS_CONTROL\)/);
  assert.doesNotMatch(button, /UI_RADIUS_PILL|maxLines|minFontSize/);
  assert.match(button, /minHeight: 40, maxWidth: '100%'/);
});

test('selection animation follows the background, but does not animate button layout', () => {
  const button = method('settingsChoiceButton(group:');
  assert.ok(button.indexOf('.backgroundColor(') < button.indexOf('.animation('));
  assert.ok(button.indexOf('.animation(') < button.indexOf('.padding('));
  assert.match(button, /duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut/);
  assert.match(button, /clickEffect\(\{ level: ClickEffectLevel.LIGHT \}\)/);
  assert.match(button, /informationSettingPending/);
  assert.match(button, /timeSettingsPending/);
});

test('CLI and touch share time response animations and semantic settings routes', () => {
  const apply = method('private applyTimeSettings(');
  assert.match(apply, /getUIContext\(\)\.animateTo/);
  assert.match(apply, /this.startupTimeMode = result.startupTimeMode/);
  assert.match(apply, /this.deltaTAlgorithm = result.deltaTAlgorithm/);
  const route = method('private openPanelFromCli(');
  assert.match(route, /settingsInformation/);
  assert.match(route, /settingsTime/);
  assert.match(route, /this.selectConfigTab\(panel === 'settingsInformation' \? 1 : 3\)/);
});
