#!/usr/bin/env node
// Merge Stellarium's non-Earth locations (Moon, Mars, Venus, Titan, Bennu)
// into the HarmonyOS offline hierarchy and Chinese display-name table.
//
// The earlier mobile hierarchy filtered p=0 rows, dropping 26 Moon sites
// (including Chang'e 3/4/5, Yutu, Longjiang-2) and every Mars/Venus/Titan/Bennu
// entry. This script is idempotent and keeps the source order.

import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const locationsPath = path.join(root, 'data/base_locations.txt')
const hierarchyPath = path.join(root, 'harmonyos/ets-source/common/location/hierarchy.ts')
const namesPath = path.join(root, 'harmonyos/ets-source/common/location/names_zh.ts')

const manualNames = {
  'Surveyor 7': '勘测者7号',
  'Lunar Orbiter 1': '月球轨道器1号',
  'Lunar Orbiter 2': '月球轨道器2号',
  'Lunar Orbiter 3': '月球轨道器3号',
  'Lunar Orbiter 5': '月球轨道器5号',
  'Lunar Prospector': '月球勘探者号',
  "Chang'e 1": '嫦娥一号',
  "Chang'e 3": '嫦娥三号',
  'Yutu': '玉兔号',
  "Chang'e 4": '嫦娥四号',
  'Yutu-2': '玉兔二号',
  "Chang'e 5": '嫦娥五号',
  'Kaguya': '辉夜号',
  'Hiten': '飞天号',
  'Chandrayaan-1': '月船一号',
  'Chandrayaan-2': '月船二号',
  'Chandrayaan-3': '月船三号',
  'Beresheet': '创世纪号',
  'SMART-1': '智能1号',
  'LCROSS Shepherding Spacecraft': 'LCROSS 牧羊航天器',
  'LCROSS Centaur': 'LCROSS 半人马座上面级',
  'GRAIL': '圣杯号',
  'LADEE': '月球大气与粉尘环境探测器',
  'Longjiang-2': '龙江二号',
  'Hakuto-R': '白兔-R',
  'SLIM': '小型落月探测器',
  'Mars 2': '火星2号',
  'Mars 3': '火星3号',
  'Mars 6': '火星6号',
  'Viking 1': '海盗1号',
  'Viking 2': '海盗2号',
  'Mars Pathfinder': '火星探路者号',
  'Mars Polar Lander': '火星极地着陆者号',
  'Beagle 2': '小猎犬2号',
  'Spirit': '勇气号',
  'Opportunity': '机遇号',
  'Curiosity': '好奇号',
  'Schiaparelli EDM lander': '斯基亚帕雷利EDM着陆器',
  'InSight': '洞察号',
  'Zhurong': '祝融号',
  'Perseverance': '毅力号',
  'Venera 3': '金星3号',
  'Venera 4': '金星4号',
  'Venera 5': '金星5号',
  'Venera 6': '金星6号',
  'Venera 7': '金星7号',
  'Venera 8': '金星8号',
  'Venera 9': '金星9号',
  'Venera 10': '金星10号',
  'Venera 11': '金星11号',
  'Venera 12': '金星12号',
  'Venera 13': '金星13号',
  'Venera 14': '金星14号',
  'Vega 1': '维加1号',
  'Vega 2': '维加2号',
  'Huygens': '惠更斯号',
  'OSIRIS-REx': '奥西里斯-雷克斯号',
}

function parseAngle(value) {
  const direction = value.slice(-1)
  const number = Number.parseFloat(value.slice(0, -1))
  return direction === 'S' || direction === 'W' ? -number : number
}

function normalizeLongitude(value) {
  let lon = value
  while (lon < -180) lon += 360
  while (lon >= 180) lon -= 360
  return lon
}

function nonEarthGroup(planet) {
  const groups = {
    Moon: ['月球', '月面任务地点'],
    Mars: ['火星', '火星表面地点'],
    Venus: ['金星', '金星表面地点'],
    Titan: ['土卫六', '土卫六表面地点'],
    Bennu: ['小行星贝努', '贝努表面地点'],
  }
  return groups[planet] ?? [planet + '表面', planet + '表面地点']
}

function loadLiteral(source) {
  const start = source.indexOf('=')
  if (start < 0) throw new Error('Unable to find object literal')
  return Function(`"use strict"; return (${source.slice(start + 1).replace(/;\s*$/, '')})`)()
}

async function main() {
  const source = await readFile(locationsPath, 'utf8')
  const rows = []
  for (const line of source.split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue
    const fields = line.split('\t')
    if (fields.length < 11) continue
    const planet = fields[10].trim()
    if (!planet || planet === 'Earth') continue
    rows.push({
      name: fields[0].trim(),
      state: fields[1].trim(),
      latitude: parseAngle(fields[5].trim()),
      longitude: normalizeLongitude(parseAngle(fields[6].trim())),
      altitude: Math.round(Number.parseFloat(fields[7].trim()) || 0),
      planet,
    })
  }

  const hierarchySource = await readFile(hierarchyPath, 'utf8')
  const hierarchy = loadLiteral(hierarchySource)
  const existing = new Set()
  for (const regions of Object.values(hierarchy)) {
    for (const cities of Object.values(regions)) {
      for (const city of cities) {
        existing.add(`${city.planet ?? 'Earth'}|${city.n}|${city.la}|${city.lo}`)
      }
    }
  }

  let added = 0
  for (const row of rows) {
    const key = `${row.planet}|${row.name}|${row.latitude}|${row.longitude}`
    if (existing.has(key)) continue
    const [continent, region] = nonEarthGroup(row.planet)
    if (!hierarchy[continent]) hierarchy[continent] = {}
    if (!hierarchy[continent][region]) hierarchy[continent][region] = []
    hierarchy[continent][region].push({
      n: row.name,
      la: row.latitude,
      lo: row.longitude,
      al: row.altitude,
      p: 0,
      country: 'ZZ',
      province: row.state,
      planet: row.planet,
    })
    existing.add(key)
    added++
  }

  const hierarchyLines = [
    '// Auto-generated from Stellarium base_locations.txt (continent -> country -> region -> cities)',
    'export const LOCATION_HIERARCHY: Record<string, Record<string, Array<{n:string;la:number;lo:number;al:number;p:number;country:string;province?:string;planet?:string}>>> =',
    JSON.stringify(hierarchy, null, 1),
    ';',
    '',
  ]
  await writeFile(hierarchyPath, hierarchyLines.join('\n'))

  const namesSource = await readFile(namesPath, 'utf8')
  const names = loadLiteral(namesSource)
  let named = 0
  for (const row of rows) {
    if (!names[row.name] && manualNames[row.name]) {
      names[row.name] = manualNames[row.name]
      named++
    }
  }
  const nameLines = [
    '// Generated by scripts/generate-ohos-location-zh.mjs. Do not edit manually.',
    '// Upstream Latin names are retained as keys for native Stellarium lookups.',
    'export const LOCATION_ZH_NAMES: Record<string, string> = {',
    ...Object.entries(names).map(([name, value]) => `  ${JSON.stringify(name)}: ${JSON.stringify(value)},`),
    '}',
    '',
  ]
  await writeFile(namesPath, nameLines.join('\n'))

  console.log(`non-Earth source rows=${rows.length}, hierarchy added=${added}, names added=${named}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
