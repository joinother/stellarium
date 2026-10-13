import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

// The satellite source editor now lives in the refactored layout:
// behaviour in capability/SatelliteController.ets, pure helpers in
// state/SatelliteStore.ets, UI in panels/panels/SatellitesPanel.ets and the
// localized labels in capability/I18n.ets.
const controller = readFileSync(new URL('../harmonyos/ets-source/capability/SatelliteController.ets', import.meta.url), 'utf8');
const store = readFileSync(new URL('../harmonyos/ets-source/state/SatelliteStore.ets', import.meta.url), 'utf8');
const panel = readFileSync(new URL('../harmonyos/ets-source/panels/panels/SatellitesPanel.ets', import.meta.url), 'utf8');
const i18n = readFileSync(new URL('../harmonyos/ets-source/capability/I18n.ets', import.meta.url), 'utf8');
const sourceLogic = controller.slice(controller.indexOf('setSatelliteSourceEnabled'), controller.indexOf('restoreSatelliteSources'));

test('satellite sources preserve the original enabled-source behavior', () => {
  assert.match(sourceLogic, /addNew: sourceIndex === index \? enabled : source\.addNew/);
  assert.match(panel, /Toggle\(\{ type: ToggleType\.Switch, isOn: source\.addNew \}\)/);
});

test('long URLs stay compact and remain inspectable', () => {
  assert.match(panel, /this\.satelliteStore\.satelliteSourcePreview\(source\.url\)/);
  assert.match(store, /satelliteSourcePreview\(url: string\)/);
});

test('source management labels are localized', () => {
  for (const key of ['sat_source_enabled', 'sat_source_disabled', 'sat_source_local_file', 'sat_source_edit', 'sat_source_save', 'sat_source_restore', 'sat_source_restore_title', 'sat_source_restore_message', 'sat_source_cancel', 'sat_source_enabled_hint', 'sat_next_update', 'sat_updates_disabled', 'sat_updating', 'sat_update_error']) {
    assert.match(i18n, new RegExp(`'${key}':`));
    assert.match(i18n, new RegExp(`'${key}': \\{[^\\n]*'zh_CN':`));
  }
});

test('source management exposes original edit and restore actions', () => {
  assert.match(controller, /editSatelliteSource\(index: number\)/);
  assert.match(controller, /restoreSatelliteSources\(\)/);
  assert.match(controller, /'restoreSatelliteSources'/);
  assert.match(store, /satelliteUpdateStatusText/);
});
