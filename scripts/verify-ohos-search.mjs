#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const cliPath = join(scriptDirectory, 'stellarium-cli.mjs');
const deviceIndex = process.argv.indexOf('--device');
const deviceArgs = deviceIndex >= 0 && process.argv[deviceIndex + 1]
  ? ['--device', process.argv[deviceIndex + 1]]
  : [];

const supportedLanguages = new Set([
  'ar', 'bn', 'cs', 'da', 'de', 'el', 'en', 'es', 'fa', 'fi', 'fr', 'gu',
  'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'ml', 'mr', 'ms', 'nb',
  'ne', 'nl', 'pl', 'pt', 'pt_BR', 'ro', 'ru', 'si', 'sk', 'sl', 'sv', 'ta',
  'te', 'th', 'uk', 'vi', 'zh_CN', 'zh_HK', 'zh_TW',
]);

function officialLanguageCases() {
  const aliasFile = join(scriptDirectory, '..', 'data', 'search', 'multilingual-sky-aliases.tsv');
  const casesByLanguage = new Map();
  for (const line of fs.readFileSync(aliasFile, 'utf8').split(/\r?\n/u)) {
    if (!line || line.startsWith('#')) continue;
    const [alias, englishName, language] = line.split('\t');
    if (!supportedLanguages.has(language)) continue;
    const isPreferredObject = englishName === 'Andromeda Galaxy';
    const existing = casesByLanguage.get(language);
    if (!existing || isPreferredObject) {
      casesByLanguage.set(language, {
        query: alias,
        expectKey: englishName,
        crossLanguage: true,
        language,
      });
    }
  }
  const missing = [...supportedLanguages].filter((language) => language !== 'en' && !casesByLanguage.has(language));
  if (missing.length > 0) throw new Error(`官方别名索引缺少界面语言：${missing.join(', ')}`);
  return [...casesByLanguage.values()].sort((left, right) => left.language.localeCompare(right.language));
}

const cases = [
  { query: 'M31', expect: 'M31' },
  { query: 'Andromeda Galaxy', expectKey: 'Andromeda Galaxy' },
  { query: 'NGC 224', expect: 'NGC' },
  { query: 'HIP 32349', expect: 'HIP' },
  { query: '仙女座星系', expect: '仙女' },
  { query: '仙女星系', expect: '仙女', fuzzy: true },
  { query: 'alpha Cen', expect: 'Cen' },
  { query: "Galaxie d'Andromède", expect: '仙女', crossLanguage: true },
  { query: 'Andromedagalaxie', expect: '仙女', crossLanguage: true },
  { query: 'アンドロメダ銀河', expect: '仙女', crossLanguage: true },
  { query: '안드로메다 은하', expect: '仙女', crossLanguage: true },
  { query: 'Галактика Андромеды', expect: '仙女', crossLanguage: true },
  { query: 'مجرة أندروميدا', expect: '仙女', crossLanguage: true },
  { query: 'অ্যান্ড্রোমিডা নক্ষত্রলোক', expect: '仙女', crossLanguage: true },
  { query: 'Androméda galaxie', expect: '仙女', fuzzy: true, crossLanguage: true },
  { query: 'Ｍ３１', expect: 'M31' },
  ...officialLanguageCases(),
];

if (process.argv.includes('--index-only')) {
  const languageCases = cases.filter((searchCase) => searchCase.language);
  console.log(`OK: official cross-language search coverage includes ${languageCases.length} UI languages`);
  process.exit(0);
}

function runQuery(searchCase) {
  const output = execFileSync(process.execPath, [cliPath, ...deviceArgs,
    '--command', 'listMatchingObjects', '--payload', `${searchCase.query}|30`, '--json'],
  { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] }).trim();
  const response = JSON.parse(output);
  const items = Array.isArray(response.items) ? response.items : [];
  const fuzzy = Array.isArray(response.fuzzy) ? response.fuzzy : [];
  const crossLanguage = Array.isArray(response.crossLanguage) ? response.crossLanguage : [];
  const keys = Array.isArray(response.keys) ? response.keys : [];
  const expected = String(searchCase.expect ?? '').toLocaleLowerCase();
  const expectedKey = String(searchCase.expectKey ?? '').toLocaleLowerCase();
  const itemIndex = expectedKey.length > 0
    ? keys.findIndex((key) => String(key).toLocaleLowerCase() === expectedKey)
    : items.findIndex((item) => String(item).toLocaleLowerCase().includes(expected));
  const found = itemIndex >= 0;
  const fuzzyOk = !searchCase.fuzzy || fuzzy[itemIndex] === true;
  const crossLanguageOk = !searchCase.crossLanguage || crossLanguage[itemIndex] === true;
  return { ...searchCase, found, fuzzyOk, crossLanguageOk, items, keys };
}

let failures = 0;
for (const searchCase of cases) {
  const result = runQuery(searchCase);
  const passed = result.found && result.fuzzyOk && result.crossLanguageOk;
  const prefix = result.language ? `[${result.language}] ` : '';
  console.log(`${passed ? 'PASS' : 'FAIL'} ${prefix}${result.query}: ${result.items.join(' | ') || '无候选'}`);
  if (!passed) {
    failures += 1;
    if (result.found && !result.fuzzyOk) console.error('  期望候选标记为近似匹配');
    if (result.found && !result.crossLanguageOk) console.error('  期望候选标记为跨语言匹配');
  }
}

if (failures > 0) process.exit(1);
