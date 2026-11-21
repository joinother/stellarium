import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = rel => readFileSync(root + rel, 'utf8');

// 1. Phase 3: New dedicated plugin panels (Calendars + MinorBodies) & native commands
const cpp = read('src/StelMainView.cpp');
const catalog = read('src/StelOhosCommandCatalog.hpp');
for (const cmd of ['getCalendarsData', 'setCalendarSetting', 'getMinorBodies', 'importMinorBodies']) {
  assert.ok(cpp.includes(`commandName == "${cmd}"`), `Missing C++ handler for ${cmd}`);
  assert.ok(catalog.includes(cmd), `Missing catalog entry for ${cmd}`);
}

const calendarsPanel = read('harmonyos/ets-source/panels/panels/CalendarsPanel.ets');
assert.match(calendarsPanel, /InfoTipButton/);
assert.match(calendarsPanel, /UI_RADIUS_CARD/);
assert.match(calendarsPanel, /calendars-overlay-toggle/);
assert.match(calendarsPanel, /calendars-cat-/);

const minorPanel = read('harmonyos/ets-source/panels/panels/MinorBodiesPanel.ets');
assert.match(minorPanel, /InfoTipButton/);
assert.match(minorPanel, /UI_RADIUS_CARD/);
assert.match(minorPanel, /minor-bodies-import-comets-btn/);
assert.match(minorPanel, /minor-bodies-mpc-toggle-btn/);
assert.match(minorPanel, /showAlertDialog/);

// Plugin routes activate both Calendars and SolarSystemEditor as first-class control panels
const labels = read('harmonyos/ets-source/common/derive/labels.ets');
assert.match(labels, /if \(id === 'Calendars'\) return \{ panel: 'calendars', kind: 'control' \}/);
assert.match(labels, /if \(id === 'SolarSystemEditor'\) return \{ panel: 'minorBodies', kind: 'control' \}/);

const actions = read('harmonyos/ets-source/common/derive/actions.ets');
assert.match(actions, /panel: 'calendars'/);
assert.match(actions, /panel: 'minorBodies'/);

// 2. Phase 2: All 9 polished plugin panels use InfoTipButton, UI_RADIUS_CARD, and zero duration+springMotion anti-patterns
const phase2Panels = [
  'harmonyos/ets-source/panels/panels/ArchaeoLinesPanel.ets',
  'harmonyos/ets-source/panels/panels/MeteorShowersPanel.ets',
  'harmonyos/ets-source/panels/panels/Scenery3dPanel.ets',
  'harmonyos/ets-source/panels/panels/NebulaTexturesPanel.ets',
  'harmonyos/ets-source/panels/panels/NavStarsPanel.ets',
  'harmonyos/ets-source/panels/panels/MosaicCameraPanel.ets',
  'harmonyos/ets-source/panels/panels/AngleMeasurePanel.ets',
  'harmonyos/ets-source/panels/view/PointerCoordinatesPanel.ets',
  'harmonyos/ets-source/panels/panels/TelescopePanel.ets',
];

for (const file of phase2Panels) {
  const src = read(file);
  assert.match(src, /InfoTipButton/, `${file} should use InfoTipButton for explanatory text`);
  assert.match(src, /UI_RADIUS_CARD/, `${file} should use HarmonyOS UI_RADIUS_CARD token`);
  assert.doesNotMatch(src, /duration:\s*\d+\s*,\s*curve:\s*curves\.springMotion/, `${file} must not mix duration with physical springMotion`);
}

console.log(`Plugin remediation Phases 2 & 3 checks OK (${phase2Panels.length} polished panels + 2 new plugin panels).`);
