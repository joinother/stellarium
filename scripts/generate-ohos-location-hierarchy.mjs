#!/usr/bin/env node
// Add an offline country level to the HarmonyOS location hierarchy.
// Stellarium's base_locations.txt has no country column. Its IANA timezone,
// together with the system zone table, is the most reliable offline source.

import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const hierarchyPath = path.join(root, 'harmonyos/ets-source/pages/location_hierarchy.ts')
const locationsPath = path.join(root, 'data/base_locations.txt')
const countriesPath = path.join(root, 'data/iso3166.tab')
const outputCountriesPath = path.join(root, 'harmonyos/ets-source/pages/location_countries.ts')

const zoneTableCandidates = [
  '/usr/share/zoneinfo/zone1970.tab',
  '/usr/share/zoneinfo/zone.tab',
  '/usr/share/zoneinfo.default/zone1970.tab',
  '/usr/share/zoneinfo.default/zone.tab',
]

function parseAngle(value) {
  const direction = value.slice(-1)
  const number = Number.parseFloat(value.slice(0, -1))
  return direction === 'S' || direction === 'W' ? -number : number
}

function parseSourceLocations(source) {
  const rows = []
  for (const line of source.split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue
    const fields = line.split('\t')
    if (fields.length < 10) continue
    rows.push({
      name: fields[0].trim(),
      state: fields[1].trim(),
      lat: parseAngle(fields[5].trim()),
      lon: parseAngle(fields[6].trim()),
      timezone: fields[9].trim(),
      planet: fields[10]?.trim() || 'Earth',
    })
  }
  return rows
}

function parseZoneCountries(source) {
  const zones = new Map()
  for (const line of source.split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue
    const fields = line.split('\t')
    if (fields.length < 3) continue
    zones.set(fields[2], fields[0].split(','))
  }
  return zones
}

function parseCountryNames(source) {
  const names = new Map()
  for (const line of source.split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue
    const fields = line.split('\t')
    if (fields.length >= 2) names.set(fields[0], fields[1])
  }
  return names
}

function loadLiteral(source) {
  const objectStart = source.indexOf('=')
  if (objectStart < 0) throw new Error('Unable to find LOCATION_HIERARCHY object')
  const literal = source.slice(objectStart + 1).replace(/;\s*$/, '')
  return Function(`"use strict"; return (${literal})`)()
}

function nearestSourceCity(city, candidates) {
  let best
  let bestDistance = Number.POSITIVE_INFINITY
  for (const candidate of candidates) {
    const distance = Math.abs(candidate.lat - city.la) + Math.abs(candidate.lon - city.lo)
    if (distance < bestDistance) {
      best = candidate
      bestDistance = distance
    }
  }
  return bestDistance < 0.05 ? best : undefined
}

async function readZoneTable() {
  for (const candidate of zoneTableCandidates) {
    try {
      return await readFile(candidate, 'utf8')
    } catch {
      // Try the next platform path.
    }
  }
  throw new Error('No IANA zone table was found on this build machine')
}

async function main() {
  const sourceHierarchy = loadLiteral(await readFile(hierarchyPath, 'utf8'))
  const hierarchy = {}
  const sourceCities = parseSourceLocations(await readFile(locationsPath, 'utf8'))
  const sourceByName = new Map()
  for (const city of sourceCities) {
    if (!sourceByName.has(city.name)) sourceByName.set(city.name, [])
    sourceByName.get(city.name).push(city)
  }
  const zoneCountries = parseZoneCountries(await readZoneTable())
  const countryEnglish = parseCountryNames(await readFile(countriesPath, 'utf8'))
  const countryCodes = new Set()
  let unmatched = 0

  function addCity(continent, region, city) {
    if (!hierarchy[continent]) hierarchy[continent] = {}
    if (!hierarchy[continent][region]) hierarchy[continent][region] = []
    hierarchy[continent][region].push(city)
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

  for (const [sourceContinent, regions] of Object.entries(sourceHierarchy)) {
    for (const [sourceRegion, cities] of Object.entries(regions)) {
      for (const city of cities) {
        const source = nearestSourceCity(city, sourceByName.get(city.n) ?? [])
        const codes = source ? (zoneCountries.get(source.timezone) ?? []) : []
        city.country = codes[0] ?? 'ZZ'
        city.province = source?.state ?? ''
        city.planet = source?.planet ?? 'Earth'
        if (city.planet === 'Earth' && city.country === 'ZZ') {
          if (city.province === 'Canary Islands') city.country = 'ES'
          else if (city.province === 'South Pole' || city.n === 'Dome C') city.country = 'AQ'
        }
        countryCodes.add(city.country)
        if (city.country === 'ZZ') unmatched += 1

        let targetContinent = sourceContinent
        let targetRegion = sourceRegion
        if (city.planet !== 'Earth') {
          [targetContinent, targetRegion] = nonEarthGroup(city.planet)
        } else if (city.country === 'AQ') {
          targetContinent = '南极洲'
          targetRegion = '南极科考站'
        } else if (city.province === 'Canary Islands') {
          targetContinent = '非洲'
          targetRegion = '加那利群岛'
        } else if (city.country === 'SJ') {
          targetContinent = '欧洲'
          targetRegion = '斯瓦尔巴群岛'
        }
        addCity(targetContinent, targetRegion, city)
      }
    }
  }

  const countryNames = {}
  for (const code of [...countryCodes].sort()) {
    const english = countryEnglish.get(code) ?? 'Unknown region'
    let chinese = code
    try {
      chinese = new Intl.DisplayNames(['zh-CN'], { type: 'region' }).of(code) ?? code
    } catch {
      // Keep the ISO code if the build host has no Intl region data.
    }
    countryNames[code] = { zh: chinese, en: english }
  }

  const hierarchyLines = [
    '// Auto-generated from Stellarium base_locations.txt (continent -> country -> region -> cities)',
    'export const LOCATION_HIERARCHY: Record<string, Record<string, Array<{n:string;la:number;lo:number;al:number;p:number;country:string;province?:string;planet?:string}>>> =',
    JSON.stringify(hierarchy, null, 1),
    ';',
    '',
  ]
  await writeFile(hierarchyPath, hierarchyLines.join('\n'))

  const countryLines = [
    '// Generated by scripts/generate-ohos-location-hierarchy.mjs.',
    'export interface LocationCountryName { zh: string; en: string }',
    'export const LOCATION_COUNTRY_NAMES: Record<string, LocationCountryName> = ',
    JSON.stringify(countryNames, null, 1),
    ';',
    '',
  ]
  await writeFile(outputCountriesPath, countryLines.join('\n'))
  process.stdout.write(`Wrote ${sourceCities.length} source cities, ${countryCodes.size} countries, ${unmatched} fallback entries\n`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
