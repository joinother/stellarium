#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(new URL('..', import.meta.url).pathname)
const hierarchySource = fs.readFileSync(path.join(root, 'harmonyos/ets-source/pages/location_hierarchy.ts'), 'utf8')
const nameSource = fs.readFileSync(path.join(root, 'harmonyos/ets-source/pages/location_names_zh.ts'), 'utf8')
const mainSource = fs.readFileSync(path.join(root, 'harmonyos/ets-source/pages/MainWindowNativeNode.ets'), 'utf8')

function loadLiteral(source) {
  const index = source.indexOf('=')
  if (index < 0) throw new Error('location hierarchy literal was not found')
  return Function(`"use strict"; return (${source.slice(index + 1).replace(/;\s*$/, '')})`)()
}

function normalize(value) {
  return value.toLocaleLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[\s._'’`-]+/g, '')
}

function parseNameMap(source) {
  const start = source.indexOf('{')
  const end = source.lastIndexOf('}')
  return Function(`"use strict"; return (${source.slice(start, end + 1)})`)()
}

const hierarchy = loadLiteral(hierarchySource)
const names = parseNameMap(nameSource)
const cities = []
for (const regions of Object.values(hierarchy)) {
  for (const [region, rows] of Object.entries(regions)) {
    for (const city of rows) cities.push({ ...city, region })
  }
}

function find(query) {
  const needle = normalize(query)
  return cities.filter((city) => normalize([
    city.n, names[city.n] ?? '', city.province ?? '', city.region,
    city.country === 'TW' ? '中国台湾地区 台湾 China Taiwan' : '',
    city.country === 'HK' ? '中国香港特别行政区 香港 China Hong Kong' : '',
    city.country === 'MO' ? '中国澳门特别行政区 澳门 China Macao Macau' : '',
  ].join(' ')).includes(needle))
}

const checks = [
  ['北京', 'Beijing'],
  ['beijing', 'Beijing'],
  ['西安', "Xi'an"],
  ['xi an', "Xi'an"],
  ['xian', "Xi'an"],
  ['Hong Kong', 'Hong Kong'],
  ['hongkong', 'Hong Kong'],
  ['中国香港特别行政区', 'Hong Kong'],
  ['台北', 'Taipei'],
  ['中国台湾地区', 'Taipei'],
  ['Sao Paulo', 'Sao Paulo'],
  ['São Paulo', 'Sao Paulo'],
]

for (const [query, expected] of checks) {
  if (!find(query).some((city) => city.n === expected)) {
    throw new Error(`location search failed: ${query} did not match ${expected}`)
  }
}

const unresolved = cities.filter((city) => !names[city.n] || names[city.n] === '未收录地点')
if (unresolved.length > 0) {
  throw new Error(`Chinese location names unresolved: ${unresolved.slice(0, 10).map((city) => city.n).join(', ')}`)
}
for (const token of ['normalizeLocationSearchText', 'matchesLocationSearch', 'officialLocationAliases', 'locationResultContext', 'country.zh']) {
  if (!mainSource.includes(token)) throw new Error(`location search integration missing: ${token}`)
}

console.log(`OK: ${cities.length} offline locations have Chinese display entries`)
console.log(`OK: ${checks.length} localized and normalized location searches passed`)
