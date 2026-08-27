#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const sourceDirectory = path.join(root, 'po', 'stellarium-sky')
const outputFile = path.join(root, 'data', 'search', 'multilingual-sky-aliases.tsv')

function unescapePo(value) {
  return JSON.parse(`"${value}"`)
}

function readPo(file) {
  const entries = []
  let entry = null
  let field = ''
  const finish = () => {
    if (entry && !entry.fuzzy && entry.msgid && entry.msgstr) entries.push(entry)
    entry = null
    field = ''
  }

  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    if (line === '') {
      finish()
      continue
    }
    if (line.startsWith('#,') && line.includes('fuzzy')) {
      entry ??= { msgid: '', msgstr: '', fuzzy: false }
      entry.fuzzy = true
      continue
    }
    let match = line.match(/^msgid\s+"(.*)"$/)
    if (match) {
      entry ??= { msgid: '', msgstr: '', fuzzy: false }
      entry.msgid = unescapePo(match[1])
      field = 'msgid'
      continue
    }
    match = line.match(/^msgstr\s+"(.*)"$/)
    if (match) {
      entry ??= { msgid: '', msgstr: '', fuzzy: false }
      entry.msgstr = unescapePo(match[1])
      field = 'msgstr'
      continue
    }
    if (line.startsWith('"') && entry && field) entry[field] += unescapePo(line.slice(1, -1))
  }
  finish()
  return entries
}

function normalise(value) {
  return value.toLocaleLowerCase().replace(/[\s_-]+/gu, '')
}

if (!fs.existsSync(sourceDirectory)) {
  console.error(`找不到官方天体翻译目录：${sourceDirectory}`)
  process.exit(1)
}

const aliases = new Map()
for (const file of fs.readdirSync(sourceDirectory).filter((name) => name.endsWith('.po')).sort()) {
  const language = file.slice(0, -3)
  if (language === 'en') continue
  for (const entry of readPo(path.join(sourceDirectory, file))) {
    const alias = entry.msgstr.trim()
    const englishName = entry.msgid.trim()
    if (!alias || !englishName || alias === englishName || /[\t\r\n]/u.test(alias) || /[\t\r\n]/u.test(englishName)) continue
    const key = `${normalise(alias)}\t${englishName}\t${language}`
    aliases.set(key, `${alias}\t${englishName}\t${language}`)
  }
}

fs.mkdirSync(path.dirname(outputFile), { recursive: true })
const header = '# Official Stellarium sky-name aliases. Generated; do not edit.\n# alias<TAB>englishName<TAB>language\n'
const rows = [...aliases.values()].sort((left, right) => left.localeCompare(right, 'en'))
fs.writeFileSync(outputFile, header + rows.join('\n') + '\n')
console.log(`已生成 ${rows.length} 条官方跨语言天体搜索别名：${path.relative(root, outputFile)}`)
