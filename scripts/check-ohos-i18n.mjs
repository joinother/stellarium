#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(new URL('..', import.meta.url).pathname)
const languages = [
  'ar', 'bn', 'cs', 'da', 'de', 'el', 'en', 'es', 'fa', 'fi', 'fr', 'gu',
  'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'ml', 'mr', 'ms', 'nb',
  'ne', 'nl', 'pl', 'pt', 'pt_BR', 'ro', 'ru', 'si', 'sk', 'sl', 'sv', 'ta',
  'te', 'th', 'uk', 'vi', 'zh_CN', 'zh_HK', 'zh_TW'
]

const errors = []
const strictUiCoverage = process.argv.includes('--strict-ui')
const source = path.join(root, 'harmonyos/ets-source/pages/I18n.ets')
const mirror = path.join(root, 'build/libstellarium-harmonyos/entry/src/main/ets/pages/I18n.ets')
const sourceText = fs.readFileSync(source, 'utf8')
const mirrorText = fs.readFileSync(mirror, 'utf8')
if (sourceText !== mirrorText) errors.push('I18n.ets source and build mirror differ')

const multilingualIndex = path.join(root, 'data', 'search', 'multilingual-sky-aliases.tsv')
if (!fs.existsSync(multilingualIndex) || fs.statSync(multilingualIndex).size < 1024) {
  errors.push('official multilingual sky-name search index is missing or empty')
} else {
  const indexText = fs.readFileSync(multilingualIndex, 'utf8')
  if (!indexText.includes("Galaxie d'Andromède\tAndromeda Galaxy\tfr") ||
      !indexText.includes('仙女座星系\tAndromeda Galaxy\tzh_CN')) {
    errors.push('official multilingual sky-name search index is incomplete')
  }
}

for (const domain of ['stellarium', 'stellarium-sky']) {
  for (const language of languages) {
    const file = path.join(root, 'translations', domain, `${language}.qm`)
    if (!fs.existsSync(file) || fs.statSync(file).size === 0) {
      errors.push(`missing official translation: translations/${domain}/${language}.qm`)
    }
  }
}

// Every upstream PO catalog selected for this HarmonyOS build needs a matching
// QM file. This avoids silent English fallback in supplementary content areas.
const upstreamDomains = [
  'stellarium',
  'stellarium-sky',
  'stellarium-skycultures',
  'stellarium-skycultures-descriptions',
  'stellarium-scripts',
  'stellarium-planetary-features',
  'stellarium-landscapes-descriptions',
  'stellarium-scenery3d-descriptions',
  'stellarium-remotecontrol',
]
for (const domain of upstreamDomains) {
  const poDirectory = path.join(root, 'po', domain)
  if (!fs.existsSync(poDirectory)) continue
  for (const language of languages) {
    if (!fs.existsSync(path.join(poDirectory, `${language}.po`))) continue
    const qmFile = path.join(root, 'translations', domain, `${language}.qm`)
    if (!fs.existsSync(qmFile) || fs.statSync(qmFile).size === 0) {
      errors.push(`missing compiled official translation: translations/${domain}/${language}.qm`)
    }
  }
}

const countryNames = fs.readFileSync(path.join(root, 'harmonyos/ets-source/pages/location_countries.ts'), 'utf8')
for (const [code, name] of [['TW', '中国台湾地区'], ['HK', '中国香港特别行政区'], ['MO', '中国澳门特别行政区']]) {
  if (!countryNames.includes(`"${code}": {\n  "zh": "${name}"`)) {
    errors.push(`Chinese location catalog must name ${code} as ${name}`)
  }
}
if (!sourceText.includes('static isChineseLanguage(): boolean')) {
  errors.push('Chinese locale variants must share the official geographic terminology path')
}

// Ignore explanatory documentation comments, but fail if a legacy name table
// is reintroduced as executable ArkTS.
const executable = sourceText
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/\/\/.*$/gm, '')
for (const token of ['PLANET_NAMES', 'STAR_NAMES', 'CONSTELLATION_ABBR', 'ALIAS_LIST']) {
  if (new RegExp(`\\b${token}\\b`).test(executable)) {
    errors.push(`legacy celestial translation table is active: ${token}`)
  }
}

// A localization key is an implementation detail, never valid user-facing
// copy. Catch accidental placeholder entries such as { en: 'm_unknown' }.
const placeholderEntries = []
const translationEntryPattern = /'([^']+)'\s*:\s*\{([^{}]*)\}/g
let translationEntry
while ((translationEntry = translationEntryPattern.exec(sourceText)) !== null) {
  const key = translationEntry[1]
  if (!(key.startsWith('m_') || key.startsWith('msg_') || key.startsWith('pinned_'))) continue
  const values = translationEntry[2]
  const placeholderLanguages = []
  for (const value of values.matchAll(/'([A-Za-z_]+)'\s*:\s*'((?:\\'|[^'])*)'/g)) {
    if (value[2] === key) placeholderLanguages.push(value[1])
  }
  if (placeholderLanguages.length > 0) {
    placeholderEntries.push(`${key}: ${placeholderLanguages.join(',')}`)
  }
}
if (placeholderEntries.length > 0) {
  errors.push(`localization keys used as visible text: ${placeholderEntries.join('; ')}`)
}

const uiStringsStart = sourceText.indexOf('const UI_STRINGS')
const uiStringsEnd = sourceText.indexOf('// ═══════════════════════════════════════════════════════════════', uiStringsStart)
const uiStringsSource = uiStringsStart >= 0 && uiStringsEnd > uiStringsStart
  ? sourceText.slice(uiStringsStart, uiStringsEnd)
  : ''
if (!uiStringsSource) {
  errors.push('could not locate UI_STRINGS localization catalog')
}

const missingUiTranslations = Object.fromEntries(languages.map((language) => [language, 0]))
let uiStringCount = 0
for (const uiEntry of uiStringsSource.matchAll(/'([^']+)'\s*:\s*\{([^{}]*)\}/g)) {
  const values = {}
  for (const value of uiEntry[2].matchAll(/'([A-Za-z_]+)'\s*:\s*'((?:\\'|[^'])*)'/g)) {
    values[value[1]] = value[2]
  }
  if (!values.en) continue
  uiStringCount += 1
  for (const language of languages) {
    if (values[language] === undefined) missingUiTranslations[language] += 1
  }
}
const missingUiTotal = Object.values(missingUiTranslations).reduce((sum, value) => sum + value, 0)
if (strictUiCoverage && missingUiTotal > 0) {
  const summary = Object.entries(missingUiTranslations)
    .filter(([, count]) => count > 0)
    .map(([language, count]) => `${language}:${count}`)
    .join(', ')
  errors.push(`ArkTS UI catalog has untranslated language fields: ${summary}`)
}

const searchKeys = [
  'search_approximate_match', 'search_browse_categories', 'search_candidate_count',
  'search_catalog_empty', 'search_catalog_loaded_count', 'search_catalog_loading',
  'search_catalog_loading_more', 'search_catalog_objects', 'search_cross_language_match',
  'search_load_failed_retry', 'search_load_more', 'search_loading_more',
  'search_no_candidates', 'search_no_match_hint', 'search_catalog_number',
  'search_permanent_number', 'loc_search_placeholder', 'loc_search_results', 'loc_search_hint',
]
for (const key of searchKeys) {
  const entry = new RegExp(`'${key}'\\s*:\\s*\\{([^{}]*)\\}`).exec(uiStringsSource)
  if (!entry) {
    errors.push(`missing search localization key: ${key}`)
    continue
  }
  const fields = new Set(Array.from(entry[1].matchAll(/'([A-Za-z_]+)'\s*:/g), (match) => match[1]))
  const missing = languages.filter((language) => !fields.has(language))
  if (missing.length > 0) errors.push(`search localization incomplete for ${key}: ${missing.join(',')}`)
}

if (errors.length > 0) {
  console.error(errors.map((error) => `ERROR: ${error}`).join('\n'))
  process.exit(1)
}
console.log(`OK: ${languages.length} official languages present in stellarium and stellarium-sky`)
console.log('OK: upstream PO catalogs have matching compiled QM catalogs')
console.log('OK: Chinese geographic terminology guardrails are present')
console.log('OK: I18n.ets source/build mirror match')
console.log('OK: official multilingual sky-name search index is present')
console.log('OK: no active legacy celestial translation table')
console.log(`INFO: ArkTS UI catalog: ${uiStringCount} entries, ${missingUiTotal} explicit language fields pending review`)
if (missingUiTotal > 0) {
  const summary = Object.entries(missingUiTranslations)
    .filter(([, count]) => count > 0)
    .map(([language, count]) => `${language}:${count}`)
    .join(', ')
  console.log(`INFO: pending by language: ${summary}`)
}

// The Qt catalog contains the official celestial names. ArkUI's own labels
// are a separate catalog, so report exact English fallbacks instead of
// pretending that the Qt language count covers the custom UI.
const fallbackKeys = []
const entryPattern = /'([^']+)'\s*:\s*\{([^{}]*)\}/g
let entry
while ((entry = entryPattern.exec(sourceText)) !== null) {
  const body = entry[2]
  const values = {}
  for (const value of body.matchAll(/'([A-Za-z_]+)'\s*:\s*'((?:\\'|[^'])*)'/g)) {
    values[value[1]] = value[2]
  }
  if (!values.en) continue
  const untranslated = languages.filter((language) => language !== 'en' && values[language] === values.en)
  if (untranslated.length > 0) fallbackKeys.push(`${entry[1]}: ${untranslated.join(',')}`)
}
console.log(`WARN: ${fallbackKeys.length} custom UI entries still equal English in at least one language`)
for (const item of fallbackKeys.slice(0, 30)) console.log(`  ${item}`)
if (fallbackKeys.length > 30) console.log(`  ... ${fallbackKeys.length - 30} more; see I18n.ets`)

const skyCultureDomains = ['stellarium-skycultures', 'stellarium-skycultures-descriptions']
for (const domain of skyCultureDomains) {
  const files = fs.existsSync(path.join(root, 'translations', domain))
    ? fs.readdirSync(path.join(root, 'translations', domain)).filter((name) => name.endsWith('.qm'))
    : []
  console.log(`INFO: ${domain} official language files: ${files.length} (${files.map((name) => name.slice(0, -3)).sort().join(', ')})`)
}
