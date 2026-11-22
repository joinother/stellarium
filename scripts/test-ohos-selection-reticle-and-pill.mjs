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

test('Detail card morphs between the compact big card and a time-panel light card without a connector line', () => {
  const pill = read('harmonyos/ets-source/panels/object/ObjectSelectionPill.ets');
  const card = read('harmonyos/ets-source/panels/object/UnifiedObjectDetailCard.ets');
  const host = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
  const expanded = read('harmonyos/ets-source/panels/shell/ExpandedShell.ets');
  const compact = read('harmonyos/ets-source/panels/shell/CompactShell.ets');
  const hover = read('harmonyos/ets-source/panels/shell/HoverObservatoryShell.ets');

  assert.match(pill, /export struct ObjectSelectionPill/);
  assert.match(pill, /private isCompactTwoRow\(\): boolean/);
  assert.match(pill, /this\.onDismiss\(\)/);
  assert.match(pill, /object-detail-time-light/);
  // The light card has no 详情 button and no expand action.
  assert.doesNotMatch(pill, /Text\('详情'\)/);
  assert.doesNotMatch(pill, /onExpand/);
  // Root container must NOT use HitTestMode.Block, otherwise the ✕ target is swallowed.
  assert.doesNotMatch(pill, /HitTestMode\.Block/, 'ObjectSelectionPill must not block child click targets');

  // One container, two contents: time panel open -> light card; otherwise compact/full big card.
  assert.match(card, /@Prop timeLight: boolean/);
  assert.match(card, /if \(this\.timeLight\)/);
  assert.match(card, /!this\.timeLight && this\.observeMode\(\)/);
  assert.match(card, /curves\.springMotion\(0\.52, 0\.9\)/);

  // Connector feature is removed entirely (layer, props, settings, native command, controller).
  for (const shell of [expanded, compact, hover]) {
    assert.match(shell, /@Prop detailTimeLight: boolean/);
    assert.match(shell, /timeLight: this\.detailTimeLight/);
    assert.match(shell, /this\.infoWinVisible && this\.objectDetailStore\.selectedName\.length > 0/);
    assert.doesNotMatch(shell, /ObjectDetailConnectorLayer/, 'connector layer must be removed from shells');
    assert.doesNotMatch(shell, /ObjectSelectionPill/, 'light card is rendered inside UnifiedObjectDetailCard only');
    assert.doesNotMatch(shell, /pillVisible/);
  }

  assert.match(host, /private isTimePanelActive\(\): boolean/);
  assert.match(host, /private syncDetailCardForPanel\(\): void/);
  assert.match(host, /infoWinExpanded = !timeLight/);
  assert.match(host, /private selectionPillWidth\(\): number/);
  assert.match(host, /private selectionPillHeight\(\): number/);
  assert.match(host, /this\.selectionPillX\(\)/);
  // Tablet menu panel avoidance via expandedDockOccupiedLeft / expandedDockLeft / expandedDockWidth
  assert.match(host, /expandedDockOccupiedLeft\(true, this\.panelWidth/);
  // Phone top-safe light-card placement avoiding bottom chrome & top-right quick buttons
  assert.match(host, /this\.compactTopQuickX\(\) - 16 - 10/);
  assert.match(host, /Math\.max\(compactTopQuickY\(\), this\.scriptControlSafeTop\(\)\)/);
  assert.doesNotMatch(host, /setObjectDetailConnector|objectDetailConnectorVisible/);

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

test('Tap-to-select prunes faint Gaia catalogs, uses 16ms adaptive polling, returns dynamic metrics immediately, and keeps 48h satellite pass scans lazy', () => {
  const picker = read('src/core/TouchPicker.cpp');
  const starMgr = read('src/core/modules/StarMgr.cpp');
  const zoneArray = read('src/core/modules/ZoneArray.cpp');
  const mainView = read('src/StelMainView.cpp');
  const satsCpp = read('plugins/Satellites/src/Satellites.cpp');
  const satCpp = read('plugins/Satellites/src/Satellite.cpp');
  const bridge = read('harmonyos/ets-source/bridge/BridgeClient.ets');
  const host = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');

  assert.match(picker, /starMgr->searchAround\(tapDirection,\s*fovRadiusDeg,\s*core,\s*starLimit \+ 0\.05f\)/);
  assert.match(starMgr, /if \(filterMag && z->mag_min > maxMilliMag\)\s*continue;/);
  assert.match(zoneArray, /if \(filterMag && s->getMag\(\) > maxMilliMag\)/);
  assert.match(mainView, /result = selectedObjectJson\(core,\s*false,\s*found\);/);
  assert.match(satsCpp, /dtSec \/ 0\.24/);
  assert.match(satCpp, /rawT \/ 0\.18f/);
  assert.match(bridge, /attempt < 10 \? 16 : 40/);
  assert.match(host, /private callInteractive[\s\S]{0,200}BridgeClient\.requestInteractive\(/);
  assert.doesNotMatch(host, /private callInteractive[\s\S]{0,120}callNativeWhenReady\(name,\s*payload,\s*onOk,\s*0,\s*100/);
  assert.match(host, /isNewSelection[\s\S]{0,800}infoWinExpanded = !timeLight/);
  assert.doesNotMatch(host, /private expandDetailPill/);
  assert.doesNotMatch(host, /selectedSatellitePassesRequested = false\s+if \(this\.objectDetailStore\.selectedObjectIsArtificialSatellite\(\)\)/);
});
