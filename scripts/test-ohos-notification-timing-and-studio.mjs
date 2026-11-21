import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { stripTypeScriptTypes } from 'node:module'

const ROOT = process.cwd()

function loadTsModule(relPath, extraDeps = {}) {
  const fullPath = path.join(ROOT, relPath)
  const source = fs.readFileSync(fullPath, 'utf8')
  const stripped = stripTypeScriptTypes(source, { mode: 'transform' })
  // Convert ESM import/export syntax to CJS for lightweight Node execution without build tools.
  const cjs = stripped
    .replace(/^\s*import\s+\{([^}]+)\}\s+from\s+['"]([^'"]+)['"]\s*;?/gm, (_, names, spec) => {
      const cleaned = names.replace(/\btype\s+/g, '').replace(/\s+as\s+/g, ': ')
      return `const {${cleaned}} = require(${JSON.stringify(spec)});`
    })
    .replace(/^\s*export\s+(const|let|var|function|class)\s+([A-Za-z0-9_$]+)/gm, (_, kw, name) => {
      return `${kw} ${name}; exports.${name} = ${name};`
    })
    .replace(/^const ([A-Za-z0-9_$]+); exports\.\1 = \1;(\s*=\s*)/gm, 'const $1$2')
  // Better: collect exported names cleanly and assign at EOF.
  const exported = []
  const body = stripped
    .replace(/^\s*import\s+\{([^}]+)\}\s+from\s+['"]([^'"]+)['"]\s*;?/gm, (_, names, spec) => {
      const cleaned = names.replace(/\btype\s+/g, '').replace(/\s+as\s+/g, ': ')
      return `const {${cleaned}} = require(${JSON.stringify(spec)});`
    })
    .replace(/^\s*export\s+(?:default\s+)?(const|let|var|function|class)\s+([A-Za-z0-9_$]+)/gm, (_, kw, name) => {
      exported.push(name)
      return `${kw} ${name}`
    })
  const trailer = exported.map((n) => `exports.${n} = ${n};`).join('\n')
  const mod = { exports: {} }
  const req = (spec) => {
    if (extraDeps[spec]) return extraDeps[spec]
    if (spec.startsWith('.')) {
      const resolvedBase = path.resolve(path.dirname(fullPath), spec)
      for (const candidate of [resolvedBase + '.ts', resolvedBase + '.ets', resolvedBase]) {
        if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
          return loadTsModule(path.relative(ROOT, candidate), extraDeps)
        }
      }
    }
    throw new Error(`Unexpected require: ${spec} from ${relPath}`)
  }
  const fn = new Function('require', 'module', 'exports', body + '\n' + trailer)
  fn(req, mod, mod.exports)
  return mod.exports
}

const regionMod = loadTsModule('harmonyos/ets-source/state/ObserverRegionScope.ts')
const timingMod = loadTsModule('harmonyos/ets-source/qability/AstronomyNotificationTiming.ts')
const filterMod = loadTsModule('harmonyos/ets-source/state/AstronomyCalendarFilter.ts')
const policyMod = loadTsModule('harmonyos/ets-source/qability/AstronomyNotificationPolicy.ts')

test('ObserverRegionScope resolves follow vs independent North/South/Equator regions', () => {
  const follow = regionMod.resolveObserverRegion('follow', 39.9, 116.4, 44, '北京', 7)
  assert.equal(follow.isFollow, true)
  assert.equal(follow.hemisphere, 'north')
  assert.match(follow.labelZh, /北京/)

  const sydney = regionMod.resolveObserverRegion('sydney', 39.9, 116.4, 44, '北京', 7)
  assert.equal(sydney.isFollow, false)
  assert.equal(sydney.hemisphere, 'south')
  assert.equal(sydney.utcOffsetMinutes, 600)
  assert.equal(sydney.tzLabelZh, 'UTC+10')

  const sg = regionMod.resolveObserverRegion('singapore')
  assert.equal(sg.hemisphere, 'equator')

  assert.equal(regionMod.normalizeObserverRegionId('invalid_city'), 'follow')
})

test('Smart timing schedules pre-dawn meteor peak and west elongation on the evening BEFORE', () => {
  // Geminid peak at 2026-12-14 03:20 UTC+8 (= 2026-12-13 19:20 UTC)
  const peakMs = regionMod.epochFromWallClockInOffset(2026, 12, 14, 3, 20, 480)
  const nowMs = regionMod.epochFromWallClockInOffset(2026, 12, 10, 12, 0, 480)

  const meteorPlan = timingMod.resolveReminderTimingPlan({
    id: 'gem-2026', kind: 'meteor-peak', title: '双子座流星雨极大',
    at: peakMs, jd: peakMs / 86400000 + 2440587.5
  }, { nowMs, timingMode: 'smart', regionId: 'beijing', dndEnabled: true, dndSatelliteOnly: true })

  const fireWc = regionMod.wallClockInOffset(meteorPlan.fireAt, 480)
  assert.equal(fireWc.year, 2026)
  assert.equal(fireWc.month, 12)
  assert.equal(fireWc.day, 13)
  assert.equal(fireWc.hour, 19)
  assert.equal(fireWc.minute, 0)
  assert.equal(meteorPlan.skippedByQuietHours, false)
  assert.match(meteorPlan.contentZh, /今夜至明晨|双子座/)

  // Mercury greatest western elongation -> must alert evening BEFORE at 20:00
  const eloMs = regionMod.epochFromWallClockInOffset(2026, 12, 20, 10, 0, 480)
  const westPlan = timingMod.resolveReminderTimingPlan({
    id: 'merc-w', kind: 'planetary-event', subtype: 'greatest-elongation',
    direction: 'west', primary: 'Mercury', title: '水星西大距', at: eloMs
  }, { nowMs, timingMode: 'smart', regionId: 'beijing' })

  const westWc = regionMod.wallClockInOffset(westPlan.fireAt, 480)
  assert.equal(westWc.day, 19)
  assert.equal(westWc.hour, 20)
  assert.match(westPlan.contentZh, /明晨日出前.*水星/)
})

test('Solar/Lunar eclipses trigger 1 day before at 18:30 local; full moon triggers at 17:30 before moonrise', () => {
  const nowMs = regionMod.epochFromWallClockInOffset(2026, 12, 1, 12, 0, 480)
  const eclipseMs = regionMod.epochFromWallClockInOffset(2026, 12, 18, 21, 15, 480)
  const eclipsePlan = timingMod.resolveReminderTimingPlan({
    id: 'le-2026', kind: 'lunar-eclipse', title: '月全食', at: eclipseMs
  }, { nowMs, timingMode: 'smart', regionId: 'beijing' })
  const eWc = regionMod.wallClockInOffset(eclipsePlan.fireAt, 480)
  assert.equal(eWc.day, 17)
  assert.equal(eWc.hour, 18)
  assert.equal(eWc.minute, 30)
  assert.match(eclipsePlan.contentZh, /明日.*月全食/)

  // Full moon exact instant at 20:15 evening -> notify at 17:30 same evening before moonrise (strictly <= eventAt)
  const fullEveMs = regionMod.epochFromWallClockInOffset(2026, 12, 24, 20, 15, 480)
  const fullEvePlan = timingMod.resolveReminderTimingPlan({
    id: 'fm-eve', kind: 'moon-phase', phaseIndex: 2, isSupermoon: true, title: '超级满月', at: fullEveMs
  }, { nowMs, timingMode: 'smart', regionId: 'beijing' })
  const feWc = regionMod.wallClockInOffset(fullEvePlan.fireAt, 480)
  assert.equal(feWc.day, 24)
  assert.equal(feWc.hour, 17)
  assert.equal(feWc.minute, 30)
  assert.ok(fullEvePlan.fireAt <= fullEveMs)
  assert.match(fullEvePlan.contentZh, /超级满月/)

  // Midday phase instant (13:15) -> notify at 09:00 same morning so fireAt <= eventAt ALWAYS holds!
  const fullMidMs = regionMod.epochFromWallClockInOffset(2026, 12, 24, 13, 15, 480)
  const fullMidPlan = timingMod.resolveReminderTimingPlan({
    id: 'fm-mid', kind: 'moon-phase', phaseIndex: 2, isSupermoon: true, title: '超级满月', at: fullMidMs
  }, { nowMs, timingMode: 'smart', regionId: 'beijing' })
  const fmWc = regionMod.wallClockInOffset(fullMidPlan.fireAt, 480)
  assert.equal(fmWc.day, 24)
  assert.equal(fmWc.hour, 9)
  assert.equal(fmWc.minute, 0)
  assert.ok(fullMidPlan.fireAt <= fullMidMs)
})

test('Satellite pass obeys passLeadMinutes and quiet hours; canonical event IDs match across app and widgets', () => {
  const passMs = regionMod.epochFromWallClockInOffset(2026, 12, 5, 23, 30, 480)
  const nowMs = regionMod.epochFromWallClockInOffset(2026, 12, 5, 18, 0, 480)
  const quietPlan = timingMod.resolveReminderTimingPlan({
    id: 'satellite-pass-25544-29942000', kind: 'satellite-pass', title: '国际空间站 ISS', at: passMs, satMaxAlt: 62
  }, { nowMs, passLeadMinutes: 15, regionId: 'beijing', dndEnabled: true, dndSatelliteOnly: true, dndStartMinutes: 1350, dndEndMinutes: 390 })
  assert.equal(quietPlan.leadMinutes, 15)
  assert.equal(quietPlan.skippedByQuietHours, true)

  const eveningPassMs = regionMod.epochFromWallClockInOffset(2026, 12, 5, 19, 45, 480)
  const activePlan = timingMod.resolveReminderTimingPlan({
    id: 'satellite-pass-25544-29941785', kind: 'satellite-pass', title: '国际空间站 ISS', at: eveningPassMs, satMaxAlt: 71
  }, { nowMs, passLeadMinutes: 10, regionId: 'beijing', dndEnabled: true, dndSatelliteOnly: true, dndStartMinutes: 1350, dndEndMinutes: 390 })
  assert.equal(activePlan.skippedByQuietHours, false)
  assert.equal(activePlan.leadMinutes, 10)
  assert.match(activePlan.contentZh, /10 分钟后过境.*71°/)

  const peakSec = Math.floor(eveningPassMs / 1000)
  const expected = timingMod.canonicalSatellitePassEventId('25544', peakSec * 1000)
  assert.equal(timingMod.normalizeCanonicalEventId(`satellite-pass-25544-${peakSec}`), expected)
  assert.equal(timingMod.normalizeCanonicalEventId(`pass:25544:39.9:116.4:${peakSec}`), expected)
})

test('Hemisphere-aware solar term copy flips season between Beijing (North) and Sydney (South)', () => {
  const nowMs = regionMod.epochFromWallClockInOffset(2026, 6, 15, 10, 0, 480)
  const solsticeMs = regionMod.epochFromWallClockInOffset(2026, 6, 21, 16, 24, 480)
  const northPlan = timingMod.resolveReminderTimingPlan({
    id: 'st-11', kind: 'solar-term', phaseIndex: 11, title: '夏至', at: solsticeMs
  }, { nowMs, timingMode: 'smart', regionId: 'beijing' })
  const southPlan = timingMod.resolveReminderTimingPlan({
    id: 'st-11', kind: 'solar-term', phaseIndex: 11, title: '夏至', at: solsticeMs
  }, { nowMs, timingMode: 'smart', regionId: 'sydney' })
  assert.match(northPlan.contentZh, /北半球入夏/)
  assert.match(southPlan.contentZh, /南半球入冬/)
})

test('Calendar filter search, presets, and calendar-to-subscription mapping work end-to-end', () => {
  const sampleEvents = [
    { id: 'm1', kind: 'meteor-peak', title: '双子座流星雨极大', at: 1000, jd: 2461000, body: 'ZHR 120', target: 'Moon', panel: 'meteorshowers', tab: 0 },
    { id: 's1', kind: 'satellite-pass', title: '中国空间站 天宫 过境', at: 2000, jd: 2461000.1, body: '高仰角', target: 'CSS', panel: 'satellites', tab: 0, satCatalogId: '48274', satArchetype: 'tiangong', satVisible: true, satMaxAlt: 55 },
    { id: 't1', kind: 'solar-term', title: '小雪', at: 3000, jd: 2461000.2, body: '节气', target: 'Sun', panel: 'astro', tab: 8 }
  ]
  const searched = filterMod.filterCalendarEvents(sampleEvents, {
    selectedCategories: [], satelliteSubFilter: 'all', highlightOnly: false, searchQuery: '天宫'
  })
  assert.equal(searched.length, 1)
  assert.equal(searched[0].id, 's1')

  const mapped = filterMod.calendarFilterToSubscriptionMapping({
    selectedCategories: ['meteor', 'satellite'], satelliteSubFilter: 'stations', highlightOnly: true
  })
  assert.deepEqual(mapped, {
    meteor: true, planet: false, moon: false, solarTerm: false, satellite: true, highlightOnly: true
  })

  // Validate extended preferences snapshot passes AstronomyNotificationPolicy validator
  assert.equal(policyMod.validNotificationPreferences({
    astronomyEventsEnabled: true,
    satellitePassEnabled: true,
    digestEnabled: false,
    subscriptionsVersion: 1,
    dndEnabled: true,
    dndSatelliteOnly: true,
    dndStartMinutes: 1350,
    dndEndMinutes: 390,
    passLeadMinutes: 10,
    topicMeteor: true,
    topicPlanet: true,
    topicMoon: true,
    topicSolarTerm: false,
    highlightOnly: true,
    timingMode: 'smart',
    regionId: 'sydney'
  }), true)
})

test('WidgetStudioPanel and AstronomyCalendarCard wiring contracts exist', () => {
  const studioSrc = fs.readFileSync(path.join(ROOT, 'harmonyos/ets-source/panels/panels/WidgetStudioPanel.ets'), 'utf8')
  assert.match(studioSrc, /RegionScopePicker/)
  assert.match(studioSrc, /getPublishedRunningFormInfos/)
  assert.match(studioSrc, /openFormManager/)
  assert.match(studioSrc, /astronomy_calendar_card/)
  assert.doesNotMatch(studioSrc, /\.onAreaChange\(/)

  const calCardSrc = fs.readFileSync(path.join(ROOT, 'harmonyos/ets-source/form/AstronomyCalendarCard.ets'), 'utf8')
  assert.match(calCardSrc, /toggleEventReminder/)
  assert.doesNotMatch(calCardSrc, /\.onAreaChange\(/)

  const formAbilitySrc = fs.readFileSync(path.join(ROOT, 'harmonyos/ets-source/form/SkyInstrumentFormAbility.ets'), 'utf8')
  assert.match(formAbilitySrc, /resolveReminderTimingPlan/)
  assert.match(formAbilitySrc, /readNotificationPreferencesSync/)
})
