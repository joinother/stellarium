import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = path => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

const tabsSrc = read('harmonyos/ets-source/panels/layers/LayerViewTabs.ets');
const controllerSrc = read('harmonyos/ets-source/capability/LayerController.ets');
const shellSrc = read('harmonyos/ets-source/panels/shell/HarmonyShell.ets');
const mainViewSrc = read('src/StelMainView.cpp');
const meteorSrc = read('src/core/modules/Meteor.cpp');
const sporadicSrc = read('src/core/modules/SporadicMeteor.cpp');
const sporadicMgrSrc = read('src/core/modules/SporadicMeteorMgr.cpp');

function extractExportedFunction(source, name) {
  const marker = `export function ${name}(`;
  const start = source.indexOf(marker);
  assert.notEqual(start, -1, `missing ${marker}`);
  const braceStart = source.indexOf('{', start);
  let depth = 0;
  let end = -1;
  for (let i = braceStart; i < source.length; i++) {
    if (source[i] === '{') depth++;
    if (source[i] === '}' && --depth === 0) {
      end = i + 1;
      break;
    }
  }
  assert.notEqual(end, -1, `unclosed ${marker}`);
  const raw = source.slice(start, end)
    .replace(/^export\s+/, '')
    .replace(/:\s*(?:number|string|boolean)\b/g, '');
  return new Function(`return (${raw});`)();
}

const meteorZhrToSliderPos = extractExportedFunction(tabsSrc, 'meteorZhrToSliderPos');
const meteorZhrFromSliderPos = extractExportedFunction(tabsSrc, 'meteorZhrFromSliderPos');
const formatMeteorZhrLabel = extractExportedFunction(tabsSrc, 'formatMeteorZhrLabel');
const julianDayToIsoDate = extractExportedFunction(tabsSrc, 'julianDayToIsoDate');

test('meteor ZHR log-slider mapping is monotonic and responsive across full range', () => {
  assert.equal(meteorZhrToSliderPos(0, 240000), 0);
  assert.equal(meteorZhrFromSliderPos(0, 240000), 0);
  assert.equal(meteorZhrFromSliderPos(1, 240000), 5);
  assert.equal(meteorZhrFromSliderPos(100, 240000), 240000);

  let prev = -1;
  for (let p = 0; p <= 100; p++) {
    const zhr = meteorZhrFromSliderPos(p, 240000);
    assert.ok(zhr >= prev, `non-monotonic at pos ${p}: ${zhr} < ${prev}`);
    prev = zhr;
  }

  // Default ZHR=10 sits clearly off the left edge (unlike old 7.5/1000 = 0.75%)
  const pos10 = meteorZhrToSliderPos(10, 240000);
  assert.ok(pos10 >= 5 && pos10 <= 12, `pos10=${pos10}`);
  const pos120 = meteorZhrToSliderPos(120, 240000);
  assert.ok(pos120 >= 25 && pos120 <= 38, `pos120=${pos120}`);
  const pos1500 = meteorZhrToSliderPos(1500, 240000);
  assert.ok(pos1500 >= 48 && pos1500 <= 62, `pos1500=${pos1500}`);

  assert.equal(formatMeteorZhrLabel(0), '0 /时');
  assert.equal(formatMeteorZhrLabel(10), '10 /时');
  assert.equal(formatMeteorZhrLabel(1500), '1.5千 /时');
  assert.equal(formatMeteorZhrLabel(15000), '1.5万 /时');
  assert.equal(formatMeteorZhrLabel(240000), '24万 /时');
});

test('julianDayToIsoDate converts Stellarium GRS reference epochs accurately', () => {
  assert.equal(julianDayToIsoDate(2460218.5), '2023-10-01');
  assert.equal(julianDayToIsoDate(2451544.5), '2000-01-01');
  assert.equal(julianDayToIsoDate(2460369.5), '2024-02-29');
});

test('meteor engine renders multi-spectral tapered ribbons with flare, afterglow and preview salvo', () => {
  assert.match(meteorSrc, /m_segments\(24\)/);
  assert.match(meteorSrc, /initInViewport\(/);
  assert.match(meteorSrc, /m_hasTerminalFlare/);
  assert.match(meteorSrc, /m_hasAfterglow/);
  assert.match(meteorSrc, /"emerald"/);
  assert.match(meteorSrc, /"amberGold"/);
  assert.match(meteorSrc, /"roseMagenta"/);
  assert.match(meteorSrc, /"iceBlue"/);
  assert.doesNotMatch(meteorSrc, /FOV > 100\.0/);
  assert.match(sporadicSrc, /roseMagenta/);
  assert.match(sporadicSrc, /emerald/);
  assert.match(sporadicSrc, /amberGold/);
  assert.match(sporadicMgrSrc, /void SporadicMeteorMgr::triggerPreviewSalvo\(/);
});

test('StelMainView exposes tone mapping, star brightness scale, GRS and meteor preview via setSkyDisplaySetting', () => {
  for (const key of [
    'absoluteStarScale',
    'toneDisplayAdaptationLuminance',
    'toneMaxDisplayLuminance',
    'toneDisplayGamma',
    'toneUseTmGamma',
    'grsLongitude',
    'grsDrift',
    'grsJd',
    'meteorDrawSuppression',
    'meteorGenSuppression'
  ]) {
    assert.ok(mainViewSrc.includes(`"${key}"`), `missing state field ${key}`);
  }
  for (const setting of [
    'toneDisplayAdaptation',
    'toneMaxLuminance',
    'toneGamma',
    'toneUseTmGamma',
    'toneReset',
    'starBrightnessReset',
    'grsLongitude',
    'grsDrift',
    'grsJd',
    'grsReset',
    'meteorPreview'
  ]) {
    assert.ok(mainViewSrc.includes(`setting == "${setting}"`), `missing setter ${setting}`);
  }
});

test('realistic star visibility harmonizes cleanly with two-finger star brightness and tone mapping', () => {
  assert.match(controllerSrc, /resetStarScaleForRealistic/);
  assert.match(controllerSrc, /starBrightnessReset\|1/);
  assert.match(shellSrc, /@Prop realisticStarVisibility: boolean = true/);
  assert.match(shellSrc, /现实星等基准/);
  assert.match(tabsSrc, /色调映射与亮度调和/);
  assert.match(tabsSrc, /木星大红斑校准 \(GRS\)/);
  assert.match(tabsSrc, /✦ 试看流星/);
  assert.match(tabsSrc, /SliderInteraction\.SLIDE_AND_CLICK/);
});
