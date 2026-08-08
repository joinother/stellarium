#!/usr/bin/env node
// Generate the offline Chinese display-name table for the HarmonyOS location picker.
// Raw upstream names stay untouched because Stellarium uses them as lookup keys.

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const hierarchyPath = path.join(root, 'harmonyos/ets-source/pages/location_hierarchy.ts')
const outputPath = path.join(root, 'harmonyos/ets-source/pages/location_names_zh.ts')
const cachePath = path.join(root, 'tmp/location-zh-cache.json')
const maxBatchChars = 1800
const concurrency = 6
const latin = /[A-Za-z]/
const manualNames = {
  'Apollo 13 S-IVB': '阿波罗十三号第四级火箭',
  'Budapest II. keruelet': '布达佩斯第二区',
  'Budapest IV. keruelet': '布达佩斯第四区',
  'Budapest XX. keruelet': '布达佩斯第二十区',
  'Amsterdam-Zuidoost': '阿姆斯特丹东南区',
  'Dhi as Sufal': '迪苏法尔',
  'Dome C': '圆顶角',
  'Crni Vrh Observatory': '茨尔尼弗尔赫天文台',
  'Janub as Surrah': '贾努布苏拉',
  'Jaxaay Parcelle Niakoul Rap': '雅克赛尼亚库尔拉普',
  'Khalifah A City': '哈利法一城区',
  'Khuraybat as Suq': '胡赖拜特苏克',
  'Joaquin V. Gonzalez': '华金五世冈萨雷斯',
  'Jose C. Paz': '何塞帕斯',
  'Kuliouou - Kalani Iki': '库利欧欧卡拉尼伊基',
  'Makakilo / Kapolei / Honokai Hale': '马卡基洛卡波莱霍诺凯哈勒',
  'Makiki / Lower Punchbowl / Tantalus': '马基基下潘奇博尔坦塔罗斯',
  'Miguel Aleman (La Doce)': '米格尔阿莱曼第十二区',
  'Nuuanu - Punchbowl': '努阿努潘奇博尔',
  "Paech'on-up": '帕琼上',
  'Paris 11e Arrondissement': '巴黎第十一区',
  'Paris 13e Arrondissement': '巴黎第十三区',
  'Phumi Veal Sre': '普米维尔斯雷',
  'Sabah as Salim': '萨巴赫萨利姆',
  'Umm as Summaq': '乌姆萨马克',
  "Unch'on-up": '翁琼上',
  'Yew Tee': '油池',
  'Zuerich (Kreis 10)': '苏黎世第十区',
  'Zuerich (Kreis 11)': '苏黎世第十一区',
  'Zuerich (Kreis 12)': '苏黎世第十二区',
  'Zuerich (Kreis 2)': '苏黎世第二区',
  'Zuerich (Kreis 3)': '苏黎世第三区',
  'Zuerich (Kreis 4)': '苏黎世第四区',
  'Zuerich (Kreis 6)': '苏黎世第六区',
  'Zuerich (Kreis 7)': '苏黎世第七区',
  'Zuerich (Kreis 9)': '苏黎世第九区',
  'Zuerich (Kreis 9) / Altstetten': '苏黎世第九区阿尔特斯泰滕',
  'Zuerich (Kreis 4) / Aussersihl': '苏黎世第四区奥瑟西尔',
  'Wadi as Sir': '瓦迪西尔',
}

function hierarchyNames(source) {
  const objectStart = source.indexOf('= {')
  if (objectStart < 0) throw new Error('Unable to find LOCATION_HIERARCHY object')
  const literal = source.slice(objectStart + 2).replace(/;\s*$/, '')
  const hierarchy = Function(`\"use strict\"; return (${literal})`)()
  const names = new Set()
  for (const regions of Object.values(hierarchy)) {
    for (const [region, cities] of Object.entries(regions)) {
      names.add(region)
      for (const city of cities) names.add(city.n)
    }
  }
  return [...names].sort((a, b) => a.localeCompare(b))
}

function splitBatches(names) {
  const batches = []
  let batch = []
  let size = 0
  for (const name of names) {
    const nextSize = size + name.length + (batch.length ? 1 : 0)
    if (batch.length && nextSize > maxBatchChars) {
      batches.push(batch)
      batch = []
      size = 0
    }
    batch.push(name)
    size += name.length + (batch.length > 1 ? 1 : 0)
  }
  if (batch.length) batches.push(batch)
  return batches
}

async function translateBatch(batch) {
  const query = new URLSearchParams({
    client: 'gtx',
    sl: 'en',
    tl: 'zh-CN',
    dt: 't',
    q: batch.join('\n'),
  })
  const response = await fetch(`https://translate.googleapis.com/translate_a/single?${query}`)
  if (!response.ok) throw new Error(`translation request failed: HTTP ${response.status}`)
  const body = await response.json()
  const translated = body[0].map((segment) => segment[0] ?? '').join('').split('\n')
  if (translated.length !== batch.length) {
    throw new Error(`translation boundary mismatch: expected ${batch.length}, received ${translated.length}`)
  }
  return translated.map((value) => value.trim())
}

async function readCache() {
  try {
    return JSON.parse(await readFile(cachePath, 'utf8'))
  } catch {
    return {}
  }
}

async function translateWithRetry(batch) {
  let lastError
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      return await translateBatch(batch)
    } catch (error) {
      lastError = error
      await new Promise((resolve) => setTimeout(resolve, attempt * 900))
    }
  }
  throw lastError
}

async function main() {
  const names = hierarchyNames(await readFile(hierarchyPath, 'utf8'))
  await mkdir(path.dirname(cachePath), { recursive: true })
  const cache = await readCache()
  const missing = names.filter((name) => !cache[name])
  const batches = splitBatches(missing)
  let cursor = 0
  let complete = 0

  async function worker() {
    while (cursor < batches.length) {
      const index = cursor++
      const batch = batches[index]
      const translated = await translateWithRetry(batch)
      for (let i = 0; i < batch.length; i += 1) cache[batch[i]] = translated[i]
      complete += 1
      await writeFile(cachePath, `${JSON.stringify(cache)}\n`)
      process.stdout.write(`Translated ${complete}/${batches.length} batches (${Object.keys(cache).length}/${names.length} names)\n`)
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, batches.length) }, worker))
  const map = {}
  const unresolved = []
  for (const name of names) {
    const value = manualNames[name] ?? cache[name] ?? ''
    map[name] = value && !latin.test(value) ? value : '未收录地点'
    if (map[name] === '未收录地点') unresolved.push(name)
  }
  const lines = [
    '// Generated by scripts/generate-ohos-location-zh.mjs. Do not edit manually.',
    '// Upstream Latin names are retained as keys for native Stellarium lookups.',
    'export const LOCATION_ZH_NAMES: Record<string, string> = {',
    ...Object.entries(map).map(([name, value]) => `  ${JSON.stringify(name)}: ${JSON.stringify(value)},`),
    '}',
    '',
  ]
  await writeFile(outputPath, lines.join('\n'))
  process.stdout.write(`Wrote ${names.length} Chinese names to ${outputPath}\n`)
  if (unresolved.length) {
    throw new Error(`Chinese name validation failed for ${unresolved.length} names: ${unresolved.join(', ')}`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
