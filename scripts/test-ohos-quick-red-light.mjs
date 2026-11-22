import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const root = new URL('../', import.meta.url);
const read = (file) => readFileSync(new URL('harmonyos/ets-source/' + file, root), 'utf8');

async function sourceModule(relativePath) {
  const source = read(relativePath).replace(/^import .*$/gm, '');
  return import('data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source)));
}

const quick = await sourceModule('common/derive/quickActions.ets');

test('red light is a candidate-only quick action and keeps the 12-slot default grid', () => {
  const pool = quick.quickActionPool();
  const item = pool.find((entry) => entry.id === 'red_light');
  assert.ok(item);
  assert.equal(item.type, 'toggle');
  assert.equal(item.kind, 'vector');
  assert.equal(item.labelKey, 'quick_red_light');
  // 天文馆模式开关移除后，候选池为 17 项；原格子由卫星提示回到默认网格。
  assert.equal(pool.length, 17);

  const defaults = quick.quickActionDefaultOrder();
  assert.equal(defaults.length, 12);
  assert.ok(!defaults.includes('red_light'));
  assert.ok(defaults.includes('satellites'));

  const candidates = quick.quickActionCandidatesFor(defaults);
  assert.equal(candidates.length, 5);
  assert.ok(candidates.some((entry) => entry.id === 'red_light'));
  assert.equal(quick.quickCandidateRowsFor(defaults), 1);
  assert.equal(quick.quickCandidateSlotsFor(defaults).length, 6);
});

test('the quick cell resolves the new red-light and map-navigation icons', () => {
  const icons = read('common/ui/ShellIcons.ets');
  assert.match(icons, /'red_light': \$r\('app\.media\.ic_red_light'\)/);
  assert.match(icons, /'map_navigate': \$r\('app\.media\.ic_map_navigate'\)/);
  assert.ok(existsSync(new URL('harmonyos/ets-source/resources/base/media/ic_red_light.svg', root)));
  assert.ok(existsSync(new URL('harmonyos/ets-source/resources/base/media/ic_map_navigate.svg', root)));
});

test('the host owns red-light state, dispatches it and renders a full-screen overlay', () => {
  const host = read('pages/MainWindowNativeNode.ets');
  assert.match(host, /@State private redLightOn: boolean = false/);
  assert.match(host, /'red_light': this\.redLightOn/);
  assert.match(host, /if \(id === 'red_light'\) \{\s*this\.setRedLight\(value\)/);
  assert.match(host, /id !== 'red_light'\) this\.layerPresetStore\.noteManualChange\(\)/);
  assert.match(host, /id\('red-light-overlay'\)/);
  assert.match(host, /backgroundColor\('#FF0000'\)/);
  assert.match(host, /onClick\(\(\) => \{ this\.setRedLight\(false\) \}\)/);
  assert.match(host, /if \(this\.redLightOn\) \{ this\.setRedLight\(false\); return \}/);
  assert.match(host, /if \(!foreground && this\.redLightOn\) this\.setRedLight\(false\)/);
  assert.match(host, /aboutToDisappear\(\): void \{\s*if \(this\.redLightOn\)/);
});

test('red light applies the chosen brightness and keeps the screen on, then restores both', () => {
  const host = read('pages/MainWindowNativeNode.ets');
  assert.match(host, /window\.getLastWindow\(context\)/);
  assert.match(host, /setWindowBrightness\(enabled \? this\.redLightBrightness : -1\.0\)/);
  assert.match(host, /setWindowKeepScreenOn\(enabled\)/);
  assert.match(host, /redLightWindowChain/);
  assert.match(host, /@State private redLightBrightness: number = 1\.0/);
});

test('red light exposes a localized brightness slider with persisted value', () => {
  const host = read('pages/MainWindowNativeNode.ets');
  assert.match(host, /Slider\(\{ value: this\.redLightBrightness, min: 0\.05, max: 1, step: 0\.01/);
  assert.match(host, /this\.changeRedLightBrightness\(value, mode\)/);
  assert.match(host, /private changeRedLightBrightness\(value: number, mode: SliderChangeMode\): void/);
  assert.match(host, /scheduleRedLightBrightness/);
  assert.match(host, /applyRedLightBrightness/);
  assert.match(host, /store\.get\('redLightBrightness', 1\.0\)/);
  assert.match(host, /store\.put\('redLightBrightness', value\)/);
  assert.match(host, /quick_red_light_brightness[\s\S]{0,2400}id\('red-light-overlay'\)/);
});

test('localized red-light labels exist', () => {
  const i18n = read('capability/I18n.ets');
  assert.match(i18n, /'quick_red_light': \{[^}]*'zh_CN': '红光手电'/);
  assert.match(i18n, /'quick_red_light_hint': \{[^}]*'zh_CN': '轻触空白处关闭红光'/);
  assert.match(i18n, /'quick_red_light_brightness': \{[^}]*'zh_CN': '亮度'/);
});
