#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const root = process.cwd()
const lrelease = process.env.LRELEASE ?? '/Users/jiexuanyang/Qt/6.12.0/macos/bin/lrelease'
const languages = new Set([
  'ar', 'bn', 'cs', 'da', 'de', 'el', 'en', 'es', 'fa', 'fi', 'fr', 'gu',
  'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'ml', 'mr', 'ms', 'nb',
  'ne', 'nl', 'pl', 'pt', 'pt_BR', 'ro', 'ru', 'si', 'sk', 'sl', 'sv', 'ta',
  'te', 'th', 'uk', 'vi', 'zh_CN', 'zh_HK', 'zh_TW',
])
const domains = [
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

if (!fs.existsSync(lrelease)) {
  console.error(`找不到 lrelease：${lrelease}。可通过 LRELEASE 环境变量指定 Qt Linguist 路径。`)
  process.exit(1)
}

let generated = 0
for (const domain of domains) {
  const source = path.join(root, 'po', domain)
  if (!fs.existsSync(source)) continue
  const destination = path.join(root, 'translations', domain)
  fs.mkdirSync(destination, { recursive: true })
  for (const file of fs.readdirSync(source).filter(name => name.endsWith('.po'))) {
    const language = file.slice(0, -3)
    if (!languages.has(language)) continue
    const output = path.join(destination, `${language}.qm`)
    execFileSync(lrelease, [path.join(source, file), '-qm', output], { stdio: 'ignore' })
    generated += 1
  }
}

console.log(`已编译 ${generated} 个官方 QM 文件`)
