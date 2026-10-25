import assert from 'node:assert/strict';
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const names = ['CompactShell', 'ExpandedShell', 'HoverObservatoryShell', 'InteractiveGuideShell', 'ScriptFocusShell'];
for (const name of names) {
  const source = fs.readFileSync(`harmonyos/ets-source/panels/shell/${name}.ets`, 'utf8');
  const surface = source.slice(source.indexOf('  build() {')).match(
    /(?:Stack\(\)(?:\s*\{\s*\})?|Blank\(\))\s*\.width\('100%'\)[\s\S]*?\.onTouch\(\(event: TouchEvent\) => \{[^}]*\}\)\s*\.onMouse\(\(event: MouseEvent\) => \{([^}]*)\}\)\s*\.onAxisEvent\(\(event: AxisEvent\) => \{([^}]*)\}\)/);
  assert.ok(surface, `${name}: mouse/axis must bind directly beside sky touch on the same surface`);
  assert.match(surface[0], /\.hitTestBehavior\(HitTestMode.Block\)/);
  assert.match(surface[0], name === 'HoverObservatoryShell' ? /\.height\(this.hoverSkyPaneHeight\)/ : /\.height\('100%'\)/);
  for (const [index, callback, eventType, modifier] of [
    [1, 'onSkyMouse', 'MouseEvent', 'onMouse'],
    [2, 'onSkyAxis', 'AxisEvent', 'onAxisEvent']
  ]) {
    assert.match(source, new RegExp(`${callback}: \\(event: ${eventType}\\) => void = \\(\\) => \\{\\}`));
    assert.equal((source.match(new RegExp(`\\.${modifier}\\(`, 'g')) ?? []).length, 1,
      `${name}: no duplicate ancestor event binding`);
    const handler = new Function('event', stripTypeScriptTypes(surface[index]));
    for (const phase of ['exploring', 'playing', 'restoring']) {
      const received = [];
      const context = { guidePhase: phase, [callback]: event => received.push(event) };
      for (const action of [1, 2, 3, 4]) {
        const event = { action, sourceTool: 9, x: 400, y: 200, windowX: 430, windowY: 248 };
        handler.call(context, event);
        if (name !== 'InteractiveGuideShell' || phase === 'exploring') {
          assert.equal(received.at(-1), event, `${name}: forward the original local-coordinate event`);
        } else {
          assert.equal(received.length, 0, `${name}: scripted guide phase must retain control`);
        }
      }
    }
  }
}

console.log('HarmonyOS sky surface bindings passed: five direct surfaces, original events, guide gating and no duplicate bindings.');
