import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const source = read('harmonyos/ets-source/pages/I18n.ets');
const tables = ['OBJECT_TYPES', 'RICH_PHRASES'].map(name => {
  const begin = source.indexOf('const ' + name + ':');
  return source.slice(begin, source.indexOf('\n}', begin) + 2);
}).join('\n');
const begin = source.indexOf('  static objectType(');
const method = source.slice(begin, source.indexOf('\n  }', begin) + 4);
const I18n = new Function(stripTypeScriptTypes(tables + '\nclass I18n { static lang = "zh_CN";\n' + method + '\n}\n') + 'return I18n;')();

function catalog(language, withContext = false) {
  const entries = new Map();
  for (const block of read('po/stellarium/' + language + '.po').split(/\n\s*\n/)) {
    if (/^#~|^#,.*fuzzy/m.test(block)) continue;
    const field = name => {
      const match = block.match(new RegExp('^' + name + ' (".*"(?:\\n".*")*)', 'm'));
      return match ? match[1].split('\n').map(line => JSON.parse(line)).join('') : undefined;
    };
    const context = field('msgctxt');
    if (context && !withContext) continue;
    const identifier = field('msgid');
    const value = field('msgstr');
    if (identifier && value !== undefined) {
      const key = (withContext ? (context ?? '') + '\u0004' : '') + identifier;
      assert.ok(!entries.has(key), 'duplicate PO key: ' + key);
      entries.set(key, value);
    }
  }
  return entries;
}

test('mixed and English compound types resolve without changing identifiers', () => {
  I18n.lang = 'zh_CN';
  for (const value of ['双星, pulsating variable star', 'double star, pulsating variable star', 'Double Star, Pulsating Variable Star']) {
    assert.equal(I18n.objectType(value), '双星, 脉动变星');
  }
  assert.equal(I18n.objectType('Eclipsing Binary System'), '食双星系统');
  assert.equal(I18n.objectType('ROTATING VARIABLE STAR'), '自转变星');
  assert.equal(I18n.objectType('HIP 27989'), 'HIP 27989');
  assert.equal(I18n.objectType('未知类型'), '未知类型');
  assert.equal(I18n.objectType(''), '');
});

test('language switches re-evaluate the type without stale Chinese state', () => {
  for (const [language, expected] of [['en', 'pulsating variable star'], ['zh_TW', '脈動變星'], ['zh_HK', '脈動變星'], ['ja', '脈動変光星'], ['zh_CN', '脉动变星']]) {
    I18n.lang = language;
    assert.equal(I18n.objectType('pulsating variable star'), expected);
  }
});

const types = new Set();
for (const [path, start, end] of [
  ['src/core/modules/StarWrapper.hpp', 'QString getObjectType()', 'QString getObjectTypeI18n()'],
  ['src/core/modules/StarWrapper.cpp', 'QString StarWrapper1::getObjectType()', 'QString StarWrapper1::getInfoString'],
  ['src/core/modules/Nebula.cpp', 'Nebula::typeEnglishStringMap =', 'Nebula::Nebula()'],
  ['src/core/modules/Planet.cpp', 'Planet::pTypeMap =', 'Planet::Planet('],
  ...['Pulsars/Pulsar', 'Quasars/Quasar', 'Exoplanets/Exoplanet', 'Novae/Nova', 'Supernovae/Supernova'].map(item => {
    const [plugin, name] = item.split('/');
    return ['plugins/' + plugin + '/src/' + name + '.hpp', 'QString getObjectType(void)', 'QString getObjectTypeI18n(void)'];
  }),
]) {
  const native = read(path);
  const from = native.indexOf(start);
  const to = native.indexOf(end, from);
  assert.ok(from >= 0 && to > from, path);
  for (const match of native.slice(from, to).matchAll(/N_\("([^"]+)"\)/g)) types.add(match[1]);
}

for (const language of ['zh_CN', 'zh_HK', 'zh_TW']) {
  test(language + ' native stellar/solar-system/deep-sky/plugin type coverage', () => {
    const entries = catalog(language);
    const missing = [...types].filter(type => !entries.get(type) || entries.get(type) === type);
    assert.deepEqual(missing, [], language + ' missing: ' + missing.join(', '));
  });
}

test('variable types are extracted and upgrades refresh native catalogs before core startup', () => {
  assert.match(read('po/stellarium/POTFILES.in'), /^src\/core\/modules\/StarWrapper\.hpp$/m);
  const template = read('po/stellarium/stellarium.pot');
  for (const type of ['eruptive variable star', 'pulsating variable star', 'rotating variable star', 'cataclysmic variable star', 'eclipsing binary system', 'variable star']) {
    assert.ok(template.includes('msgid ' + JSON.stringify(type)), type);
  }
  const bootstrap = read('harmonyos/ets-source/qability/StellariumResourceBootstrap.ets');
  assert.match(bootstrap, /refreshObjectTypeTranslations\(appContext, installRoot\)/);
  assert.match(bootstrap, /\.object_type_translations_20260906_v1/);
});

test('all literal stellar-header detail and narration terms have Chinese translations with intact placeholders', () => {
  const header = read('src/core/modules/StarWrapper.hpp');
  const phrases = [...header.matchAll(/\b(?:q_|qc_|N_)\("([^"\n]*)"(?:,\s*"([^"\n]*)")?/g)];
  for (const language of ['zh_CN', 'zh_HK', 'zh_TW']) {
    const entries = catalog(language, true);
    for (const [, identifier, context] of phrases) {
      const translated = entries.get((context ?? '') + '\u0004' + identifier);
      assert.ok(translated, language + ': ' + identifier);
      assert.deepEqual((translated.match(/%\d+/g) ?? []).sort(), (identifier.match(/%\d+/g) ?? []).sort(), identifier);
    }
  }
});

console.log('Audited native object types:', types.size);
