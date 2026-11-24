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
const host = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const i18n = readFileSync(new URL('../harmonyos/ets-source/capability/I18n.ets', import.meta.url), 'utf8');
const sourceLogic = controller.slice(controller.indexOf('setSatelliteSourceEnabled'), controller.indexOf('restoreSatelliteSources'));

test('satellite sources preserve the original enabled-source behavior', () => {
  assert.match(sourceLogic, /addNew: sourceIndex === index \? enabled : source\.addNew/);
  assert.match(panel, /onToggleSourceEnabled\(sourceIndex, !source\.addNew\)/);
});

test('source rows are single-line with an expandable address and actions', () => {
  assert.match(panel, /sourceTitle\(source: SatelliteSource\)/);
  assert.match(panel, /satelliteSourceLabel\(source\.url\)/);
  assert.match(panel, /satelliteSourceHost\(source\.url\)/);
  assert.match(panel, /Text\('⋯'\)/);
  assert.match(panel, /sat_source_more/);
  assert.match(panel, /expandedSourceIndex === sourceIndex/);
  const detailStart = panel.indexOf('if (this.expandedSourceIndex === sourceIndex)');
  assert.ok(detailStart > 0);
  const detail = panel.slice(detailStart, panel.indexOf('}, (source: SatelliteSource) =>', detailStart));
  assert.match(detail, /sat_source_detail_address/);
  assert.match(detail, /Text\(source\.url\)/);
  assert.match(detail, /maxLines\(4\)\.wordBreak\(WordBreak\.BREAK_ALL\)/);
  assert.match(detail, /sat_source_edit/);
  assert.match(detail, /sat_source_delete/);
  assert.doesNotMatch(panel, /satelliteSourceTail/);
  assert.doesNotMatch(store, /satelliteSourcePreview/);
});

test('custom source titles override the derived title and are persisted', () => {
  assert.match(panel, /satelliteStore\.satelliteSourceTitle\(source\.url\)/);
  assert.match(panel, /isCustomSatelliteSource\(this\.satelliteStore\.satSourceInput\)/);
  assert.match(panel, /satellite-source-editor-title/);
  assert.match(panel, /satSourceTitleInput/);
  assert.match(store, /satSourceTitles: Record<string, string>/);
  assert.match(store, /applySatelliteSourceTitlesJson/);
  assert.match(controller, /applyCustomSourceTitle/);
  assert.match(controller, /persistSatelliteSourceTitles/);
  assert.match(host, /SATELLITE_SOURCE_TITLE_STORE/);
  assert.match(host, /loadSatelliteSourceTitles/);
});

test('source rows use the selected preset styling instead of per-row switches', () => {
  const sourceList = panel.slice(
    panel.indexOf('ForEach(this.satelliteStore.satSources'),
    panel.indexOf('}, (source: SatelliteSource) =>'));
  assert.ok(sourceList.length > 0);
  assert.doesNotMatch(sourceList, /Toggle\(/);
  assert.match(sourceList, /\.fontSize\(13\)\.fontWeight\(FontWeight\.Medium\)/);
  assert.match(sourceList, /backgroundColor\(source\.addNew \? this\.c\.accentSoft : this\.c\.bg\)/);
  assert.match(sourceList, /border\(\{ width: 1, color: source\.addNew \? this\.c\.accent : this\.c\.dividerSoft \}\)/);
  assert.match(sourceList, /fontColor\(!source\.valid \? this\.c\.warning : \(source\.addNew \? this\.c\.accent : this\.c\.text\)\)/);
  assert.doesNotMatch(sourceList, /opacity\(source\./);
  assert.match(sourceList, /onToggleSourceEnabled\(sourceIndex, !source\.addNew\)/);
});

test('satellite panel uses the host panel scroll instead of an inner scroll', () => {
  assert.doesNotMatch(panel, /Scroll\(this\.panelScroller\)/);
  assert.doesNotMatch(panel, /panelScroller: Scroller/);
  assert.match(panel, /onRequestScrollTop: \(\) => void/);
  assert.match(host, /onRequestScrollTop: \(\) => \{ this\.resetActivePanelScroll\(\) \}/);
  assert.doesNotMatch(host, /satellitePanelScroller/);
  assert.match(host, /scrollY: this\.activePanelScroller\(\)\.currentOffset\(\)\?\.yOffset/);
});

test('source editor is a modal with a wrapped TextArea', () => {
  assert.match(panel, /bindContentCover\(this\.sourceEditorOpen, this\.sourceEditorCover/);
  assert.match(panel, /onDisappear: \(\) => \{[\s\S]{0,160}sourceEditorOpen = false/);
  assert.match(panel, /TextArea\(\{ text: this\.satelliteStore\.satSourceInput/);
  assert.match(panel, /wordBreak\(WordBreak\.BREAK_ALL\)/);
  const sourceContent = panel.slice(panel.indexOf('sourceContent()'), panel.indexOf('sourceEditorCover()'));
  assert.doesNotMatch(sourceContent, /TextInput\(\{ text: this\.satelliteStore\.satSourceInput/);
  assert.match(controller, /beginAddSatelliteSource\(\)/);
  assert.match(controller, /cancelSatelliteSourceEdit\(\)/);
});

test('source management labels are localized', () => {
  for (const key of ['sat_source_enabled', 'sat_source_disabled', 'sat_source_local_file', 'sat_source_edit', 'sat_source_save', 'sat_source_restore', 'sat_source_restore_title', 'sat_source_restore_message', 'sat_source_cancel', 'sat_source_enabled_hint', 'sat_source_editor_edit', 'sat_source_editor_add', 'sat_source_url_label', 'sat_source_more', 'sat_source_detail_address', 'sat_source_title_label', 'sat_source_title_placeholder', 'sat_next_update', 'sat_updates_disabled', 'sat_updating', 'sat_update_error']) {
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
