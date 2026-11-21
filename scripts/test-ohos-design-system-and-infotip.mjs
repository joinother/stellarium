import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = (rel) => readFileSync(new URL('../' + rel, import.meta.url), 'utf8');

test('HarmonyOS Design corner-radius ladder obeys hierarchy-proportional concentric tiers', () => {
  const tokens = read('harmonyos/ets-source/common/ui/UiTokens.ets');
  const getVal = (name) => {
    const m = tokens.match(new RegExp(`export const ${name}: number = (\\d+)`));
    assert.ok(m, `Missing token ${name}`);
    return Number(m[1]);
  };
  const micro = getVal('UI_RADIUS_MICRO');
  const tag = getVal('UI_RADIUS_TAG');
  const media = getVal('UI_RADIUS_MEDIA');
  const control = getVal('UI_RADIUS_CONTROL');
  const card = getVal('UI_RADIUS_CARD');
  const button = getVal('UI_RADIUS_BUTTON');
  const panel = getVal('UI_RADIUS_PANEL');
  const sheet = getVal('UI_RADIUS_SHEET');
  const pill = getVal('UI_RADIUS_PILL');

  assert.ok(micro < tag && tag < media && media < control && control < card && card < button && button < panel && panel < sheet && sheet < pill,
    'Corner radii must strictly increase with UI hierarchy');
  assert.equal(tag, 4);
  assert.equal(media, 8);
  assert.equal(card, 16);
  assert.equal(button, 20);
  assert.equal(panel, 24);
  assert.equal(sheet, 32);
});

test('Unified motion tokens use physical spring curves without conflicting fixed duration', () => {
  const motion = read('harmonyos/ets-source/common/ui/UiMotion.ets');
  assert.match(motion, /export function uiSpringSnappy\(\)/);
  assert.match(motion, /export function uiSpringStandard\(\)/);
  assert.match(motion, /export function uiSpringGentle\(\)/);
  assert.match(motion, /export function uiFadeUpTransition\(\)/);
  assert.match(motion, /export function uiSlideTransition\(/);
  assert.doesNotMatch(motion, /duration:\s*\d+,\s*curve:\s*curves\.springMotion/);
});

test('InfoTipButton renders native info_circle SymbolGlyph and theme-aware bindPopup', () => {
  const tip = read('harmonyos/ets-source/common/ui/InfoTipButton.ets');
  assert.match(tip, /SymbolGlyph\(\$r\('sys\.symbol\.info_circle'\)\)/);
  assert.match(tip, /\.bindPopup\(this\.open,/);
  assert.match(tip, /enableArrow:\s*true/);
  assert.match(tip, /autoCancel:\s*true/);
  assert.match(tip, /radius:\s*UI_RADIUS_CARD/);
  assert.match(tip, /backgroundBlurStyle:\s*BlurStyle\.NONE/);
  assert.match(tip, /width:\s*256/);
  assert.match(tip, /this\.c\.isNight/);
});

test('Key panels migrate verbose explanations into InfoTipButton and protect restore-defaults', () => {
  for (const rel of [
    'harmonyos/ets-source/panels/layers/LayerSwitchRow.ets',
    'harmonyos/ets-source/common/ui/SettingsSwitchRow.ets',
    'harmonyos/ets-source/panels/layers/AtmosphereGroundSection.ets',
    'harmonyos/ets-source/panels/layers/ObservationAidBlock.ets',
    'harmonyos/ets-source/panels/location/PlaceEnvironmentSection.ets',
    'harmonyos/ets-source/panels/settings/HapticSection.ets',
    'harmonyos/ets-source/panels/settings/NotificationSection.ets',
    'harmonyos/ets-source/panels/time/SiderealTimeRow.ets',
    'harmonyos/ets-source/panels/panels/SettingsPanel.ets',
    'harmonyos/ets-source/panels/panels/AstronomyCalendarPanel.ets',
    'harmonyos/ets-source/panels/astro/AstroPanel.ets',
    'harmonyos/ets-source/panels/ar/ARPreviewPanel.ets',
  ]) {
    const src = read(rel);
    assert.match(src, /InfoTipButton/, `${rel} should use InfoTipButton`);
  }

  // SettingsPanel: both Tab 0 and Tab 7 restore-defaults go through AlertDialog confirmation
  const settings = read('harmonyos/ets-source/panels/panels/SettingsPanel.ets');
  assert.match(settings, /private confirmRestoreDefaults\(\): void/);
  const restoreClicks = settings.match(/this\.confirmRestoreDefaults\(\)/g) || [];
  assert.ok(restoreClicks.length >= 2, 'Both restore-defaults entries must ask for confirmation');

  // AstronomyCalendarPanel: zero raw hardcoded borderRadius numbers
  const cal = read('harmonyos/ets-source/panels/panels/AstronomyCalendarPanel.ets');
  assert.doesNotMatch(cal, /\.borderRadius\(\d+\)/, 'AstronomyCalendarPanel must use UI_RADIUS tokens');
});

test('Desktop service cards (form/) use unified WidgetTokens with zero hardcoded numeric borderRadius', () => {
  const tokens = read('harmonyos/ets-source/form/WidgetTokens.ts');
  for (const name of ['WIDGET_RADIUS_BAR', 'WIDGET_RADIUS_BADGE', 'WIDGET_RADIUS_CHIP', 'WIDGET_RADIUS_ROW', 'WIDGET_RADIUS_SURFACE', 'WIDGET_RADIUS_PILL']) {
    assert.match(tokens, new RegExp(`export const ${name}: number = \\d+`), `Missing ${name}`);
  }
  for (const file of [
    'CelestialEventsCard.ets',
    'CompanionArcCard.ets',
    'SatellitePassCard.ets',
    'SkyFormEditPage.ets',
    'SkyLiveFormPage.ets',
    'SkyWindowCard.ets',
    'SolarArcCard.ets',
    'SolarSystemCard.ets',
    'WidgetVisuals.ets'
  ]) {
    const src = read('harmonyos/ets-source/form/' + file);
    assert.doesNotMatch(src, /\.borderRadius\(\d+(?:\.\d+)?\)/, `form/${file} must use WIDGET_RADIUS_* tokens`);
  }
});
