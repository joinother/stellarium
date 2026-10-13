import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const page = readFileSync(new URL('../harmonyos/ets-source/common/derive/labels.ets', import.meta.url), 'utf8');
const panel = readFileSync(new URL('../harmonyos/ets-source/panels/panels/SatellitesPanel.ets', import.meta.url), 'utf8');
const manager = readFileSync(new URL('../plugins/Satellites/src/Satellites.cpp', import.meta.url), 'utf8');

const families = [
  ['STARLINK', '星链'], ['BEIDOU', '北斗'], ['TIANLIAN', '天链'], ['TIANTONG', '天通'],
  ['FENGYUN', '风云'], ['YAOGAN', '遥感'], ['GAOFEN', '高分'], ['SHIJIAN', '实践'],
  ['SHIYAN', '实验'], ['ZIYUAN', '资源'], ['GLONASS', '格洛纳斯'], ['GALILEO', '伽利略'],
  ['IRIDIUM', '铱星'], ['GLOBALSTAR', '全球星'], ['INTELSAT', '国际通信卫星'], ['QZSS', '准天顶']
];

test('Chinese satellite display names cover common pinyin and constellation families', () => {
  for (const [source, localized] of families) {
    assert.match(page, new RegExp(`token: '${source}'`));
    assert.match(page, new RegExp(`label: .*${localized}`));
  }
  assert.match(page, /const suffix = value\.substring\(item\.token\.length\)/);
  assert.match(page, /satelliteLocalizedName\(value\)/);
});

test('Chinese satellite search aliases resolve to the original TLE family', () => {
  for (const [source, localized] of families) {
    assert.match(manager, new RegExp(`QStringLiteral\\("${source}"\\), QStringLiteral\\("${localized}"\\)`));
  }
  assert.match(manager, /normalizedEnglishName\.contains\(normalizedQuery\.mid\(normalizedAlias\.size\(\)\)\)/);
});

test('official identifiers remain available as secondary satellite metadata', () => {
  assert.match(panel, /Text\(item\.englishName\)/);
  assert.match(panel, /Text\('NORAD ' \+ item\.id/);
});
