import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const host = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const controller = readFileSync(
  new URL('../harmonyos/ets-source/capability/LocationController.ets', import.meta.url), 'utf8');
const picker = readFileSync(
  new URL('../harmonyos/ets-source/panels/location/LocationPickerPanel.ets', import.meta.url), 'utf8');
const actions = readFileSync(
  new URL('../harmonyos/ets-source/common/derive/actions.ets', import.meta.url), 'utf8');
const store = readFileSync(
  new URL('../harmonyos/ets-source/state/LocationStore.ets', import.meta.url), 'utf8');
const pickerStore = readFileSync(
  new URL('../harmonyos/ets-source/state/LocationPickerStore.ets', import.meta.url), 'utf8');
const searchPanel = readFileSync(
  new URL('../harmonyos/ets-source/panels/location/LocationSearchPanel.ets', import.meta.url), 'utf8');

test('GPS asks for a precise single fix so altitude is available', () => {
  assert.match(host, /locatingPriority: geoLocationManager\.LocatingPriority\.PRIORITY_ACCURACY/);
  assert.match(host, /locatingTimeoutMs:\s*10000/);
  assert.match(host, /results\[1\] === 0/);
  assert.match(host, /return 'precise'/);
  assert.match(host, /\[gps\] fix lat=/);
  assert.match(controller, /permission !== 'precise'/);
  assert.match(controller, /m_gps_precise_required/);
});

test('panel dragging and scrolling disable the expensive backdrop blur and shadow', () => {
  assert.match(host, /@State private panelDragging: boolean = false/);
  assert.match(host, /@State private panelScrolling: boolean = false/);
  assert.match(host, /@State private panelTouching: boolean = false/);
  assert.match(host, /private panelChromeBusy\(\): boolean \{\s*return this\.panelDragging \|\| this\.panelScrolling\s*\}/);
  assert.match(host, /backdropBlur\(this\.panelChromeBusy\(\) \? 0 : 30\)/);
  assert.match(host, /shadow\(\{ radius: this\.panelChromeBusy\(\) \? 0 : 30/);
  assert.match(host, /shadow\(\{ radius: this\.panelChromeBusy\(\) \? 0 : 34/);
  assert.match(host, /animation\(\{ duration: \(this\.panelChromeBusy\(\) \|\| this\.panelTouching\) \? 0 : 320/);
  assert.match(host, /this\.panelTouching = true[\s\S]{0,160}this\.resetPanelIdle\(\)/);
  assert.match(host, /if \(!this\.panelDragging\) this\.panelDragging = true/);
  assert.match(host, /onFinish: \(\) => \{ this\.panelDragging = false \}/);
  assert.match(host, /\.onScrollStart\(\(\) => \{ if \(!this\.panelScrolling\) this\.panelScrolling = true \}\)/);
  assert.match(host, /\.onScrollStop\(\(\) => \{ this\.panelScrolling = false \}\)/);
  assert.match(host, /this\.panelScrolling = false\s*\n\s*this\.panelTouching = false\s*\n\s*\/\/ 时间面板首帧/);
});

test('location search folding avoids ICU-backed locale lowercasing', () => {
  assert.match(actions, /export function normalizeLocationSearchText\(value: string\): string \{\s*\/\/[\s\S]*?const lowered = value\.toLowerCase\(\)/);
  assert.doesNotMatch(actions, /toLocaleLowerCase/);
});

test('location search scans on demand instead of warming an index', () => {
  assert.doesNotMatch(store, /warmLocationSearchIndex/);
  assert.doesNotMatch(store, /buildLocationSearchIndex/);
  assert.doesNotMatch(store, /LocationSearchEntry/);
  assert.doesNotMatch(searchPanel, /warmLocationSearchIndex/);
  assert.match(actions, /export function foldLocationSearchText\(value: string\): string/);
  assert.match(actions, /const LOCATION_FOLD_CACHE: Map<string, string>/);
  assert.match(actions, /export function locationFieldScore\(folded: string, query: string, best: number\)/);
  assert.match(store, /foldLocationSearchText\(q\)/);
  assert.match(store, /locationFieldScore\(foldLocationSearchText\(city\.n\)/);
  assert.match(store, /locationSearchScanChinese/);
  assert.match(pickerStore, /locationDisplayNameForSearch/);
  assert.match(pickerStore, /locationSearchCountryNameForSearch/);
});

test('location translations cache per-language maps and country names', () => {
  assert.match(pickerStore, /let regionMapCache: Record<string, string> \| null = null/);
  assert.match(pickerStore, /private regionNameMap\(\): Record<string, string>/);
  assert.match(pickerStore, /const COUNTRY_DISPLAY_CACHE: Map<string, string>/);
  assert.doesNotMatch(pickerStore, /const regionMap: Record<string, string> = \{/);
});

test('map picking uses a click instead of raw touch moves', () => {
  assert.match(picker, /\.onClick\(\(event: ClickEvent\) => this\.handleLocationMapClick\(event\)\)/);
  assert.doesNotMatch(picker, /handleLocationMapTouch/);
  assert.doesNotMatch(picker, /mapTouchMoved/);
  // Scroll only changes the map's position; writing the same @Observed values
  // every frame forces pointless panel rerenders.
  assert.match(picker, /if \(width !== this\.pickerStore\.mapRenderWidth\) this\.pickerStore\.mapRenderWidth = width/);
  assert.match(picker, /if \(height !== this\.pickerStore\.mapRenderHeight\) this\.pickerStore\.mapRenderHeight = height/);
});
