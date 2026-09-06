import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
const panelStart = source.indexOf("Text('今晚可观测目标').fontSize(13)");
const panel = source.slice(panelStart, source.indexOf('} else if (this.astroTab === 6)', panelStart));
const cardStart = source.indexOf('  wutTargetCard(target: WutTarget)');
const card = source.slice(cardStart, source.indexOf('\n  }', cardStart));

test('tonight targets use the parent vertical scroll, not a fixed-width table', () => {
  assert.doesNotMatch(panel, /Scroll\(\)|ScrollDirection.Horizontal|\.height\(300\)|\.width\((130|190|132)\)/);
  assert.match(panel, /this\.wutTargetCard\(target\)/);
});

test('category selection can collapse and filter choices wrap within the panel', () => {
  assert.match(panel, /if \(this\.wutCategoriesExpanded\)/);
  assert.match(panel, /wutCategoriesExpanded = !this\.wutCategoriesExpanded/);
  assert.match(panel, /wutCategoriesExpanded = false/);
  assert.equal((panel.match(/Flex\(\{ wrap: FlexWrap.Wrap \}\)/g) ?? []).length, 6);
  assert.doesNotMatch(panel, /\.layoutWeight\(1\)[\s\S]*?Text\('观测时段'\)\.fontSize\(10\)/);
});

test('cards retain every table field and the existing observation-time selection action', () => {
  for (const field of ['magnitude', 'maxAltitude', 'altitude', 'rise', 'transit', 'set', 'constellation', 'type']) {
    assert.ok(card.includes('target.' + field), field);
  }
  assert.match(card, /this\.wutTargetTitle\(target\)/);
  assert.match(card, /this\.wutTargetSubtitle\(target\)/);
  assert.match(card, /this\.jumpToWutTarget\(target\)/);
  assert.doesNotMatch(card, /maxLines|minFontSize|\.height\(/);
  assert.match(card, /this\.fmtNum\(target.maxAltitude \?\? target.altitude, 1, '°'\)/);
});

test('paired metrics reserve space and wrap labels without truncation', () => {
  const start = source.indexOf('  wutMetric(label: string, value: string)');
  const metric = source.slice(start, source.indexOf('\n  }', start));
  assert.match(metric, /\.width\('48%'\)/);
  assert.match(metric, /Text\(label\).*\.width\('100%'\)/);
  assert.match(metric, /Text\(value\).*\.width\('100%'\)/);
  assert.doesNotMatch(metric, /maxLines|minFontSize|\.height\(/);
});
