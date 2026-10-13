import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

// Pointer coordinates and the survey tab now live in the refactored files.
const controller = readFileSync(new URL('../harmonyos/ets-source/capability/ViewCoordinateController.ets', import.meta.url), 'utf8');
const layerCtl = readFileSync(new URL('../harmonyos/ets-source/capability/SurveyController.ets', import.meta.url), 'utf8');
const i18n = readFileSync(new URL('../harmonyos/ets-source/capability/I18n.ets', import.meta.url), 'utf8');
const layersPanel = readFileSync(new URL('../harmonyos/ets-source/panels/panels/LayersPanel.ets', import.meta.url), 'utf8');
const layerTabs = readFileSync(new URL('../harmonyos/ets-source/panels/layers/LayerTabs.ets', import.meta.url), 'utf8');
const surveys = readFileSync(new URL('../harmonyos/ets-source/panels/layers/LayerSpectralSection.ets', import.meta.url), 'utf8');
const cpp = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
const catalog = readFileSync(new URL('../src/StelOhosCommandCatalog.hpp', import.meta.url), 'utf8');

test('pointer coordinate changes do not reload the whole panel on success', () => {
  const setter = controller.slice(controller.indexOf('setPointerCoordinates(setting'), controller.indexOf('private applyPointerCoordinatesSetting'));
  assert.match(setter, /this\.applyPointerCoordinatesSetting\(setting, value\)/);
  assert.match(setter, /if \(r\.ok !== true\)[\s\S]*?this\.overlayStore\.loadPointerCoordinates\(\)/);
  assert.doesNotMatch(setter, /if \(r\.ok === true\)[\s\S]*?loadPointerCoordinates/);
});

test('layer tabs keep a stable top row and readable type', () => {
  assert.match(layersPanel, /LayerTabs\(/);
  assert.match(layerTabs, /\.fontSize\(/);
  assert.match(layersPanel, /LayerPresetBar\([\s\S]*LayerTabs\(/);
});

test('survey tab explains the two original layers and reports native state', () => {
  assert.match(surveys, /survey_usage/);
  assert.match(surveys, /survey_alignment_hint/);
  assert.match(layerCtl, /'getSurveyState'/);
  assert.match(cpp, /commandName == "getSurveyState"/);
  assert.match(catalog, /getSurveyState/);
});

test('pointer toolbar wording explains its independent quick-switch role', () => {
  assert.match(i18n, /'pointer_coord_toolbar_hint':/);
  assert.match(i18n, /'zh_CN': '[^']*快速开关/);
});

test('pointer position bridge is wired end to end', () => {
  assert.match(cpp, /commandName == "setPointerPosition"/);
  assert.match(cpp, /setOhosMousePos\(x2, y2\)/);
  assert.match(cpp, /state\["screenX"\]/);
  assert.match(catalog, /selectAt,setPointerPosition,selftestActions/);
});
