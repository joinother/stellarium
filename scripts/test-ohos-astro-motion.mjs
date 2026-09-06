import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const ability = readFileSync(new URL('../harmonyos/ets-source/qability/QAbility.ets', import.meta.url), 'utf8');
const start = source.indexOf("    } else if (this.activePanel === 'astro') {");
const panel = source.slice(start, source.indexOf("    } else if (this.activePanel === 'help') {", start));
function method(name) {
  const begin = source.indexOf('  private ' + name + '(');
  assert.ok(begin >= 0, name);
  return source.slice(begin, source.indexOf('\n  }', begin) + 4);
}
function harness() {
  const code = 'class Controller {\n' + ['selectAstroTab', 'selectAstroGroup', 'selectAstroFilter', 'astroGroupForTab']
    .map(method).join('\n') + '\n}';
  const Controller = new Function('Curve', stripTypeScriptTypes(code) + '; return Controller;')({ EaseIn: 'in', EaseOut: 'out' });
  const controller = new Controller();
  const callbacks = [];
  const animations = [];
  const loads = [];
  Object.assign(controller, {
    astroTab: 5, astroGroup: 0, astroRequestedTab: -1, astroTransitionId: 0,
    astroContentOpacity: 1, astroContentOffsetX: 0, panelVisible: true, activePanel: 'astro',
    wutPeriod: 'evening', wutMinAltitude: 0, wutMaxMagnitude: 6, wutDirection: 'all',
    astroPanelScroller: { scrollTo: () => {} },
    publishAstroPanelState: () => {}, saveAppSettings: () => {},
    loadAstroTab: tab => loads.push(tab), loadWutTargets: () => loads.push('wut'),
    astroTabItemsForGroup: group => [[5, 2, 4, 9], [0, 1, 6], [3, 7, 8]][group].map(id => ({ id })),
    getUIContext: () => ({ animateTo: (options, update) => {
      animations.push(options);
      update();
      if (options.onFinish) callbacks.push(options.onFinish);
    } }),
  });
  return { controller, animations, loads, flush: () => { while (callbacks.length) callbacks.shift()(); } };
}

test('every astronomy click site has light press feedback; all 64 selected backgrounds animate', () => {
  assert.equal((panel.match(/\.onClick\(/g) ?? []).length, 102);
  assert.equal((panel.match(/\.clickEffect\(/g) ?? []).length, 102);
  assert.equal((panel.match(/duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut/g) ?? []).length, 64);
  assert.doesNotMatch(panel, /springMotion|geometryTransition/);
});

test('the scroll itself only translates/fades; no animated sizing or conditional scroll recreation', () => {
  assert.match(panel, /Scroll\(this.astroPanelScroller\)/);
  assert.match(panel, /id\('astro-content'\)\.opacity\(this.astroContentOpacity\)\.translate\(\{ x: this.astroContentOffsetX \}\)/);
  assert.doesNotMatch(panel, /\.height\(this.astroContent|if \(this.astroContentOpacity/);
});

test('tonight loading feedback follows filters so starting a calculation cannot push the controls', () => {
  const tonight = panel.slice(panel.indexOf('} else if (this.astroTab === 5)'), panel.indexOf('} else if (this.astroTab === 6)'));
  assert.ok(tonight.indexOf('if (this.wutLoading)') > tonight.indexOf("this.selectAstroFilter('direction',"));
  assert.ok(tonight.indexOf('if (this.wutLoading)') < tonight.indexOf('if (this.wutHint.length'));
});

test('switching follows displayed tab order rather than numeric IDs and uses detail timing', () => {
  const state = harness();
  state.controller.astroTab = 9;
  state.controller.selectAstroTab(0);
  assert.equal(state.controller.astroContentOffsetX, -8);
  assert.deepEqual(state.loads, []);
  state.flush();
  assert.deepEqual(state.loads, [0]);
  assert.equal(state.controller.astroGroup, 1);
  assert.equal(state.controller.astroContentOpacity, 1);
  assert.deepEqual(state.animations.map(item => [item.duration, item.curve]), [[100, 'in'], [170, 'out']]);
  state.controller.selectAstroTab(9);
  assert.equal(state.controller.astroContentOffsetX, 8);
  state.flush();
});

test('repeated active tab or group does not reload', () => {
  const state = harness();
  state.controller.selectAstroTab(5);
  state.controller.selectAstroGroup(0);
  state.flush();
  assert.deepEqual(state.loads, []);
  assert.equal(state.animations.length, 0);
});

test('rapid changes only commit and load the last target', () => {
  const state = harness();
  state.controller.selectAstroTab(2);
  state.controller.selectAstroTab(4);
  state.controller.selectAstroTab(0);
  state.flush();
  assert.equal(state.controller.astroTab, 0);
  assert.deepEqual(state.loads, [0]);
  assert.equal(state.controller.astroRequestedTab, -1);
});

test('returning to the original tab during fade cancels the earlier destination', () => {
  const state = harness();
  state.controller.selectAstroTab(2);
  state.controller.selectAstroTab(5);
  state.flush();
  assert.equal(state.controller.astroTab, 5);
  assert.deepEqual(state.loads, [5]);
  assert.equal(state.controller.astroContentOpacity, 1);
});

test('closing during a transition does not load a hidden computation', () => {
  const state = harness();
  state.controller.selectAstroTab(7);
  state.controller.panelVisible = false;
  state.flush();
  assert.deepEqual(state.loads, []);
  assert.equal(state.controller.astroRequestedTab, -1);
  assert.equal(state.controller.astroContentOpacity, 1);
});

test('filter commands and touch use one validated state path; repeated values do not recalculate', () => {
  const state = harness();
  for (const [key, value] of [['period', 'morning'], ['altitude', '20'], ['magnitude', '8'], ['direction', 'east']]) {
    state.controller.selectAstroFilter(key, value);
    state.controller.selectAstroFilter(key, value);
    assert.ok(panel.includes("this.selectAstroFilter('" + key + "',"));
  }
  state.controller.selectAstroFilter('period', 'nonsense');
  state.controller.selectAstroFilter('altitude', '-90');
  assert.equal(state.loads.length, 4);
  assert.equal(state.controller.wutPeriod, 'morning');
  for (const command of ['setAstroTab', 'setAstroGroup', 'setAstroFilter', 'getAstroPanelState']) {
    assert.ok(ability.includes("'" + command + "'"));
  }
});
