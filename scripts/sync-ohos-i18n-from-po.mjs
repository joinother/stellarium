#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const languages = [
  'ar', 'bn', 'cs', 'da', 'de', 'el', 'es', 'fa', 'fi', 'fr', 'gu', 'he',
  'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'ml', 'mr', 'ms', 'nb', 'ne',
  'nl', 'pl', 'pt', 'pt_BR', 'ro', 'ru', 'si', 'sk', 'sl', 'sv', 'ta', 'te',
  'th', 'uk', 'vi', 'zh_CN', 'zh_HK', 'zh_TW'
]

const domains = [
  'stellarium-desktop',
  'stellarium',
  'stellarium-remotecontrol',
  'stellarium-scripts',
  'stellarium-planetary-features',
  'stellarium-landscapes-descriptions',
  'stellarium-scenery3d-descriptions',
  'stellarium-sky',
  'stellarium-skycultures',
  'stellarium-skycultures-descriptions',
  'stellarium-scenery3d-descriptions',
]

function poUnescape(value) {
  return JSON.parse(`"${value}"`)
}

function readPo(file) {
  const entries = []
  let entry = null
  let field = ''
  const finish = () => {
    if (entry && entry.msgid && entry.msgstr) entries.push(entry)
    entry = null
    field = ''
  }
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    if (line === '') {
      finish()
      continue
    }
    let match = line.match(/^msgid\s+"(.*)"$/)
    if (match) {
      entry ??= { msgid: '', msgstr: '' }
      entry.msgid = poUnescape(match[1])
      field = 'msgid'
      continue
    }
    match = line.match(/^msgstr\s+"(.*)"$/)
    if (match) {
      entry ??= { msgid: '', msgstr: '' }
      entry.msgstr = poUnescape(match[1])
      field = 'msgstr'
      continue
    }
    if (line.startsWith('"') && entry && field) entry[field] += poUnescape(line.slice(1, -1))
  }
  finish()
  return entries
}

function canonicalSource(value) {
  return value
    .normalize('NFKC')
    .replace(/[‘’]/g, "'")
    .replace(/…/g, '...')
    .replace(/\s+/g, ' ')
    .replace(/[.!?]+$/g, '')
    .trim()
    .toLocaleLowerCase('en')
}

function loadTranslations() {
  const translations = new Map()
  const canonicalTranslations = new Map()
  for (const domain of domains) {
    const directory = path.join(root, 'po', domain)
    if (!fs.existsSync(directory)) continue
    for (const language of languages) {
      const file = path.join(directory, `${language}.po`)
      if (!fs.existsSync(file)) continue
      for (const entry of readPo(file)) {
        if (!entry.msgid || !entry.msgstr || entry.msgstr === entry.msgid) continue
        if (!translations.has(entry.msgid)) translations.set(entry.msgid, {})
        translations.get(entry.msgid)[language] ??= entry.msgstr
        const canonical = canonicalSource(entry.msgid)
        if (!canonicalTranslations.has(canonical)) canonicalTranslations.set(canonical, {})
        canonicalTranslations.get(canonical)[language] ??= entry.msgstr
      }
    }
  }
  return { translations, canonicalTranslations }
}

function quote(value) {
  return value.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\r?\n/g, '\\n')
}

function syncFile(file, translationCatalogs) {
  let source = fs.readFileSync(file, 'utf8')
  let updated = 0
  const objectPattern = /(['"])([^'"\n]+)\1\s*:\s*\{([^{}]*)\}/g
  source = source.replace(objectPattern, (whole, keyQuote, key, body) => {
    const values = {}
    const valuePattern = /(['"])([A-Za-z_]+)\1\s*:\s*(['"])((?:\\.|(?!\3)[^\n])*)\3/g
    for (const match of body.matchAll(valuePattern)) values[match[2]] = match[4].replace(/\\'/g, "'")
    const english = values.en
    if (!english) return whole
    const officialTranslations = translationCatalogs.translations.get(english)
      ?? translationCatalogs.canonicalTranslations.get(canonicalSource(english))
    let nextBody = body
    const additions = []
    for (const language of languages) {
      const translated = officialTranslations?.[language]
      if (!translated || translated === english || translated.includes('\u0000')) continue
      const escaped = quote(translated)
      if (values[language] === undefined) {
        additions.push(`'${language}': '${escaped}'`)
        updated += 1
        continue
      }
      if (values[language] === english) {
        const languagePattern = new RegExp(`(['"])${language}\\1\\s*:\\s*(['"])((?:\\\\.|(?!\\2)[^\\n])*)\\2`)
        if (languagePattern.test(nextBody)) {
          nextBody = nextBody.replace(languagePattern, `$1${language}$1: '${escaped}'`)
          updated += 1
        }
      }
    }
    if (additions.length > 0) {
      const closingWhitespace = nextBody.match(/\s*$/)?.[0] ?? ''
      const content = nextBody.slice(0, nextBody.length - closingWhitespace.length).replace(/\s+$/, '')
      nextBody = `${content}, ${additions.join(', ')}${closingWhitespace}`
    }
    return whole.replace(body, nextBody)
  })
  fs.writeFileSync(file, source)
  return updated
}

function main() {
  const translationCatalogs = loadTranslations()
  const files = [
    path.join(root, 'harmonyos/ets-source/pages/I18n.ets'),
    path.join(root, 'build/libstellarium-harmonyos/entry/src/main/ets/pages/I18n.ets'),
  ]
  let updated = 0
  for (const file of files) updated += syncFile(file, translationCatalogs)
  console.log(`已从官方 PO 资源补齐 ${updated} 个鸿蒙 UI 翻译项`)
  console.log(`未匹配的英文回退不会被强行翻译；官方天体名称仍由 Qt QM 资源负责`)
}

main()
