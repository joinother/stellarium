import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

// Phase 4l：astro 分支体已下沉到 panels/astro/AstroPanel.ets，tonight 区段改从组件文件切片。
const panelSource = readFileSync(new URL('../harmonyos/ets-source/panels/astro/AstroPanel.ets', import.meta.url), 'utf8');
const panelStart = panelSource.indexOf("Text('今晚可观测目标').fontSize(13)");
const panel = panelSource.slice(panelStart, panelSource.indexOf('} else if (this.store.astroTab === 6)', panelStart));
const astroComponents = readFileSync(new URL('../harmonyos/ets-source/panels/astro/WutTargetCard.ets', import.meta.url), 'utf8');
const card = astroComponents.slice(astroComponents.indexOf('export struct WutTargetCard {'));

test('tonight targets use the parent vertical scroll, not a fixed-width table', () => {
  assert.doesNotMatch(panel, /Scroll\(\)|ScrollDirection.Horizontal|\.height\(300\)|\.width\((130|190|132)\)/);
  assert.match(panel, /WutTargetCard\(\{/);
});

test('category selection can collapse and filter choices wrap within the panel', () => {
  assert.match(panel, /if \(this\.wutStore\.wutCategoriesExpanded\)/);
  assert.match(panel, /wutStore\.wutCategoriesExpanded = !this\.wutStore\.wutCategoriesExpanded/);
  assert.match(panel, /wutCategoriesExpanded = false/);
  assert.equal(((panel + card).match(/Flex\(\{ wrap: FlexWrap.Wrap \}\)/g) ?? []).length, 6);
  assert.doesNotMatch(panel, /\.layoutWeight\(1\)[\s\S]*?Text\('观测时段'\)\.fontSize\(10\)/);
});

test('cards retain every table field and the existing observation-time selection action', () => {
  for (const field of ['magnitude', 'maxAltitude', 'altitude', 'rise', 'transit', 'set', 'constellation', 'type']) {
    assert.ok(card.includes('target.' + field), field);
  }
  assert.match(card, /this\.titleOf\(this\.target\)/);
  assert.match(card, /this\.subtitleOf\(this\.target\)/);
  assert.match(card, /this\.onJump\(this\.target\)/);
  assert.doesNotMatch(card, /maxLines|minFontSize|\.height\(/);
  assert.match(card, /this\.numberText\(this\.target\.maxAltitude \?\? this\.target\.altitude, 1, '\\u00b0'\)/);
});

test('paired metrics reserve space and wrap labels without truncation', () => {
  const metric = astroComponents.slice(astroComponents.indexOf('export struct WutMetric {'));
  assert.match(metric, /\.width\('48%'\)/);
  assert.match(metric, /Text\(this\.label\).*\.width\('100%'\)/);
  assert.match(metric, /Text\(this\.value\).*\.width\('100%'\)/);
  assert.doesNotMatch(metric, /maxLines|minFontSize|\.height\(/);
});
