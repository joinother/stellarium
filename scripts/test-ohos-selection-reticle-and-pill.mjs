import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = p => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

test('HarmonyOS draws a single unified C++ vector precision reticle and suppresses legacy double-stacked sprites', () => {
  const objMgr = read('src/core/StelObjectMgr.cpp');
  const mainView = read('src/StelMainView.cpp');
  assert.match(objMgr, /#if defined\(__OHOS__\)[\s\S]{0,240}setFlagSelectedObjectPointer\(false\)/);
  assert.match(mainView, /void drawOhosSelectionReticle\(StelCore\* core\)/);
  assert.match(mainView, /drawOhosSelectionReticle\(app\.getCore\(\)\);/);
  assert.match(mainView, /ohosSelectionReticleAnimating\(\)/);
});

test('ObjectDetailConnectorLayer removes outer bulky halo rings and renders only a clean 1vp hairline leader', () => {
  const connector = read('harmonyos/ets-source/panels/overlay/ObjectDetailConnectorLayer.ets');
  assert.doesNotMatch(connector, /strokeWidth\(5\)/, 'Outer bulky 5px stroke halo circle must be removed');
  assert.doesNotMatch(connector, /this\.markerSize \* 0\.72/, 'Duplicate inner ArkUI circle must be removed');
  assert.match(connector, /\.height\(1\)/);
  assert.match(connector, /if \(!this\.targetOnScreen\)/);
});

test('Two-stage selection starts as compact ObjectSelectionPill and expands smoothly to UnifiedObjectDetailCard', () => {
  const pill = read('harmonyos/ets-source/panels/object/ObjectSelectionPill.ets');
  const card = read('harmonyos/ets-source/panels/object/UnifiedObjectDetailCard.ets');
  const host = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
  const expanded = read('harmonyos/ets-source/panels/shell/ExpandedShell.ets');
  const compact = read('harmonyos/ets-source/panels/shell/CompactShell.ets');
  const hover = read('harmonyos/ets-source/panels/shell/HoverObservatoryShell.ets');
  const controller = read('harmonyos/ets-source/capability/DetailConnectorController.ets');

  assert.match(pill, /export struct ObjectSelectionPill/);
  assert.match(pill, /private isCompactTwoRow\(\): boolean/);
  assert.match(pill, /this\.onExpand\(\)/);
  assert.match(pill, /this\.onDismiss\(\)/);
  // Root container must NOT use HitTestMode.Block, otherwise child clicks (详情 / ✕) are swallowed
  assert.doesNotMatch(pill, /HitTestMode\.Block/, 'ObjectSelectionPill must not block child click targets');

  assert.match(host, /private selectionPillVisible\(\): boolean/);
  assert.match(host, /private selectionPillHeight\(\): number/);
  assert.match(host, /private expandDetailPill\(\): void/);
  // Opening a menu panel or expanding the detail card must NOT force-close the other
  assert.doesNotMatch(host, /if \(panel !== 'object'\)\s*\{\s*this\.fullInspectorRequested = false;\s*this\.infoWindowStore\.infoWinExpanded = false/);
  assert.match(host, /this\.infoWindowStore\.infoWinExpanded = false/);
  assert.match(host, /expandFromPillOnRetap/);
  assert.match(host, /this\.selectionPillX\(\)/);
  // Tablet menu panel avoidance via expandedDockOccupiedLeft / expandedDockLeft / expandedDockWidth
  assert.match(host, /expandedDockOccupiedLeft\(true, this\.panelWidth/);
  // Phone top-safe placement avoiding bottom chrome & top-right quick buttons
  assert.match(host, /this\.compactTopQuickX\(\) - 16 - 10/);
  assert.match(host, /Math\.max\(compactTopQuickY\(\), this\.scriptControlSafeTop\(\)\)/);
  assert.match(controller, /!this\.infoWindowStore\.infoWinExpanded/);

  for (const shell of [expanded, compact, hover]) {
    assert.match(shell, /import \{ ObjectSelectionPill \}/);
    assert.match(shell, /if \(this\.pillVisible\)/);
    assert.match(shell, /&& this\.infoWinExpanded/);
  }
  // Tablet pill animates smoothly in lockstep with BottomDock when menu panels open/close
  assert.match(expanded, /pillX[\s\S]{0,220}curves\.springMotion\(0\.46, 0\.86\)/);

  // Expanded Detail Card implements HarmonyOS dynamic top scroll blur (0 -> 20vp)
  assert.match(card, /scrollBlurProgress/);
  assert.match(card, /topChromeHeight/);
  assert.match(card, /backdropBlur\(this\.scrollBlurProgress > 0\.02/);
  assert.match(card, /linearGradient\(/);
  assert.match(card, /\.clip\(true\)/);
});

test('Detail card tabs and structured rows read @ObjectLink store directly and refresh immediately on time scrubbing', () => {
  const tabs = read('harmonyos/ets-source/panels/object/ObjectDetailTabs.ets');
  const structured = read('harmonyos/ets-source/panels/object/StructuredDetailRows.ets');
  const host = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');

  // Every metric tile must read @ObjectLink store directly (never via opaque this.resolve(...) closures)
  assert.doesNotMatch(tabs, /this\.resolve\(/, 'ObjectDetailTabs must read @ObjectLink store directly so ArkUI tracks live updates');
  assert.match(tabs, /value: this\.store\.selectedCoordAlt/);
  assert.match(tabs, /value: this\.store\.selectedCoordEq\.trim\(\)/);
  assert.match(tabs, /value: this\.store\.selectedMagnitude/);
  assert.match(tabs, /value: this\.store\.selectedDistance/);
  assert.match(tabs, /value: this\.store\.selectedApparentMagnitude/);
  assert.match(tabs, /value: this\.store\.selectedExtinction \+ ' 等'/);
  assert.match(tabs, /value: this\.store\.selectedAirmass/);
  assert.match(tabs, /value: this\.store\.selectedRise/);
  assert.match(tabs, /value: this\.store\.selectedTransit/);
  assert.match(tabs, /value: this\.store\.selectedSet/);
  assert.match(tabs, /value: zhNameOf\(this\.store\.selectedConstellation\)/);
  assert.match(tabs, /当日观测窗口 · /);

  // Live structured fields (orbit / surface / lunar / satellite) read through @ObjectLink wrapper
  assert.match(structured, /struct LiveStructuredDetailRow/);
  assert.match(structured, /LiveStructuredDetailRow\(\{ store: this\.store, fieldKey: field\.key/);

  // Time wheel scrubbing triggers immediate selected-object refresh and simulated date label sync
  assert.match(host, /setTimeToJD[\s\S]{0,260}this\.syncSimulatedDateLabel\(jd\)[\s\S]{0,260}this\.refreshSelectedObject\(\)/);
});

test('Satellite orbit polyline slides without drift on forward/backward time scrubs and locks solid/dashed seam on satellite', () => {
  const sat = read('plugins/Satellites/src/Satellite.cpp');
  // Forward & backward sliding advance lastEpochComp by whole diffSlots * effectiveSegSec (zero drift)
  assert.match(sat, /lastEpochComp \+= gTimeSpan\(0, 0, 0, diffSlots \* effectiveSegSec\)/);
  assert.match(sat, /lastEpochComp -= gTimeSpan\(0, 0, 0, diffSlots \* effectiveSegSec\)/);
  // Backward slide prepends directly from existing oldest sample (lastEpochComp - orbitSpan - computeInterval)
  assert.match(sat, /epochTm = lastEpochComp - orbitSpan - computeInterval;/);
  // drawOrbit falls back to full polyline scan if satellite sits outside local window
  assert.match(sat, /if \(bestDistSq > 1e-6\)[\s\S]{0,60}searchSpan\(0, size - 2, bestDistSq\)/);
});
