import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = relative => readFileSync(root + relative, 'utf8');
const panel = relative => read('harmonyos/ets-source/panels/' + relative);
const baseline = execFileSync('git', ['show', 'aae34f085e:harmonyos/ets-source/pages/MainWindowNativeNode.ets'], {
  cwd: root, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024
});
const typography = read('harmonyos/ets-source/common/ui/UiTypography.ets');
const javascript = typography.replace(/export /g, '').replace(/: (?:number|boolean)/g, '');
const helpers = new Function(`${javascript}; return { panelFontSize, objectDetailFontSize };`)();

function baselineHelper(name) {
  const body = baseline.match(new RegExp(`private ${name}\\([^\\n]+\\) *: number \\{([\\s\\S]*?)\\n  \\}`))?.[1];
  assert.ok(body, `Missing baseline helper ${name}`);
  return new Function('base', 'readable', 'emphasis', body
    .replace('this.isLargeDesktopCanvas()', 'readable')
    .replace(/: number/g, ''));
}

for (const name of ['panelFontSize', 'objectDetailFontSize']) {
  const legacy = baselineHelper(name);
  for (const readable of [false, true]) {
    for (const emphasis of [false, true]) {
      for (const base of [8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 24]) {
        assert.equal(helpers[name](base, readable, emphasis), legacy(base, readable, emphasis),
          `${name}(${base}, ${readable}, ${emphasis}) must match the backup`);
      }
    }
  }
}
assert.equal(helpers.panelFontSize(12, true), 14);
assert.equal(helpers.objectDetailFontSize(12, true), 13);

const mappedPanels = [
  'panels/ObservingPanel.ets', 'panels/OcularsPanel.ets', 'panels/NavStarsPanel.ets',
  'panels/AudioPanel.ets', 'settings/TimeSettingsSection.ets',
  'view/PointerCoordinatesPanel.ets', 'layers/LayerSpectralSection.ets'
];
const legacyLabels = [...baseline.matchAll(/(?:Text|Button)\(I18n\.t\('([^']+)'\)\)\.fontSize\(this.panelFontSize\((\d+)\)\)/g)];
let restoredLabels = 0;
for (const relative of mappedPanels) {
  const source = panel(relative);
  for (const [, key, base] of legacyLabels) {
    if (!source.includes(`I18n.t('${key}')`)) continue;
    assert.ok(source.includes(`I18n.t('${key}')).fontSize(panelFontSize(${base}, this.readableUi))`),
      `${relative}: restore the confirmed baseline size of ${key}`);
    restoredLabels++;
  }
}
assert.ok(restoredLabels >= 60);

const observing = panel('panels/ObservingPanel.ets');
assert.match(observing, /targetTitleOf\(target\)\)\.fontSize\(panelFontSize\(14, this.readableUi\)\)/);
assert.match(observing, /displayNameOf\(name\)\)\.fontSize\(panelFontSize\(15, this.readableUi\)\)/);
assert.match(observing, /I18n\.t\('observing_list_saved'\)\)\.fontSize\(10\)/);
assert.match(observing, /I18n\.t\('observing_refresh'\)\)\.fontSize\(10\)/);
assert.match(panel('panels/OcularsPanel.ets'), /I18n\.t\('ocular_mask_opacity'\)\)\.fontSize\(12\)/);
assert.match(panel('telescope/OcularSelector.ets'), /I18n\.t\('ocular_no_devices'\)\)\.fontSize\(11\)/);
assert.match(panel('telescope/OcularMetric.ets'), /panelFontSize\(15, this.readableUi\)/);

const tabs = panel('layers/LayerTabs.ets');
assert.match(tabs, /minWidth: this.readableUi \? 76 : 60, minHeight: this.readableUi \? 40 : 36/);
assert.match(tabs, /\.height\(this.readableUi \? 46 : 42\)/);
assert.match(panel('layers/LayerSwitchRow.ets'), /\.height\(this.readableUi \? 50 : 42\)/);
assert.match(panel('shell/PanelHeader.ets'), /fontSize\(panelFontSize\(18, this.readableUi\)\)/);
assert.match(panel('settings/NotificationSection.ets'), /height\(this.readableUi \? 36 : 30\)/);
assert.match(panel('layers/LayerSpectralSection.ets'), /height\(this.readableUi \? 34 : 28\)/);
for (const name of ['InfoRow', 'NavStarsToggleRow', 'SettingsChoiceButton', 'SettingsSwitchRow']) {
  const source = read(`harmonyos/ets-source/common/ui/${name}.ets`);
  assert.match(source, /@StorageProp\('stellariumReadableUi'\) readableUi: boolean = false/);
  assert.match(source, /panelFontSize\(/);
}
const coordinates = panel('object/DetailLiveRows.ets').split('export struct SelectedCoordinateRow {')[1]
  .split('export struct SelectedCoordinateRows {')[0];
assert.match(coordinates, /\.maxLines\(2\).*\.lineHeight\(17\)/);
assert.match(coordinates, /constraintSize\(\{ minHeight: this.tablet \? 40 : 38 \}\)/);
assert.match(coordinates, /Math.max\(this.tablet \? 12 : 11, objectDetailFontSize\(11, this.readableUi\)\)/);
assert.doesNotMatch(coordinates, /\.height\(/);
const structured = panel('object/DetailRows.ets').split('export struct StructuredDetailRow {')[1]
  .split('export struct DetailNameRow {')[0];
assert.match(structured, /constraintSize\(\{ minHeight:/);
assert.match(panel('object/DetailTiles.ets'), /\.fontSize\(14\)\.fontWeight/);

function collect(directory) {
  return readdirSync(root + directory, { withFileTypes: true }).flatMap(entry => {
    if (entry.name === 'shell') return [];
    const relative = `${directory}/${entry.name}`;
    return entry.isDirectory() ? collect(relative) : entry.name.endsWith('.ets') ? [relative] : [];
  });
}

let consumers = 0;
for (const relative of collect('harmonyos/ets-source/panels')) {
  const source = read(relative);
  if (!source.includes("from '../../common/ui/UiTypography'")) continue;
  assert.doesNotMatch(source, /@(?:ComponentV2|Local|Param|Event|ObservedV2)\b/);
  for (const component of source.split('export struct ').slice(1)) {
    if (!/(?:panelFontSize|objectDetailFontSize)\(/.test(component)) continue;
    assert.match(component, /@StorageProp\('stellariumReadableUi'\) readableUi: boolean = false/,
      `${relative}: each consuming component must observe the host flag`);
    consumers++;
  }
}
console.log(`Readable typography OK: backup formulas, ${restoredLabels} mapped labels, ${consumers} V1 consumers, coordinate wrapping and unscaled controls.`);
