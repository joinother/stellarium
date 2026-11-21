// Unified astronomical notification timing engine, subscription presets, and topic mapping.
// Shared across in-app subscriptions, manual calendar reminders, and desktop widget reminders so
// every entry point calculates identical, astronomically appropriate fire times and copy.

import {
  FOLLOW_REGION_ID,
  deviceUtcOffsetMinutes,
  epochFromWallClockInOffset,
  findObserverRegionPreset,
  formatRegionClock,
  formatRegionDateTime,
  normalizeObserverRegionId,
  wallClockInOffset
} from '../state/ObserverRegionScope'
import { isQuietMinute } from './AstronomyNotificationPolicy'

export type NotificationTimingMode = 'smart' | 'day_before' | 'just_in_time'

export type NotificationTopicId = 'meteor' | 'planet' | 'moon' | 'solar_term' | 'satellite'

export type SubscriptionPresetId = 'recommended' | 'stations' | 'dark_sky' | 'paused'

export interface SubscriptionTopicFlags {
  meteor: boolean
  planet: boolean
  moon: boolean
  solarTerm: boolean
  satellite: boolean
  highlightOnly: boolean
}

export interface SubscriptionPresetDefinition {
  id: SubscriptionPresetId
  labelZh: string
  labelEn: string
  summaryZh: string
  summaryEn: string
  flags: SubscriptionTopicFlags
  passLeadMinutes: number
  timingMode: NotificationTimingMode
  dndEnabled: boolean
  dndSatelliteOnly: boolean
}

export const SUBSCRIPTION_PRESETS: SubscriptionPresetDefinition[] = [
  {
    id: 'recommended',
    labelZh: '观星推荐',
    labelEn: 'Recommended',
    summaryZh: '流星雨、行星冲合、超级满月与空间站，自动按最佳窗口提醒',
    summaryEn: 'Meteors, planets, supermoons & space stations at optimal windows',
    flags: { meteor: true, planet: true, moon: true, solarTerm: false, satellite: true, highlightOnly: true },
    passLeadMinutes: 10,
    timingMode: 'smart',
    dndEnabled: true,
    dndSatelliteOnly: true
  },
  {
    id: 'stations',
    labelZh: '追空间站',
    labelEn: 'Space Stations',
    summaryZh: '专注国际空间站与天宫可见过境，提前 10 分钟提醒且避开深夜',
    summaryEn: 'ISS & Tiangong visible passes, 10 min lead with quiet hours',
    flags: { meteor: false, planet: false, moon: false, solarTerm: false, satellite: true, highlightOnly: false },
    passLeadMinutes: 10,
    timingMode: 'smart',
    dndEnabled: true,
    dndSatelliteOnly: true
  },
  {
    id: 'dark_sky',
    labelZh: '暗夜深空',
    labelEn: 'Dark Sky',
    summaryZh: '新月暗夜、流星雨极大与行星冲日，前一日傍晚提前规划',
    summaryEn: 'New moon dark nights, meteor peaks & oppositions planned a day ahead',
    flags: { meteor: true, planet: true, moon: true, solarTerm: false, satellite: false, highlightOnly: false },
    passLeadMinutes: 10,
    timingMode: 'day_before',
    dndEnabled: true,
    dndSatelliteOnly: false
  },
  {
    id: 'paused',
    labelZh: '全部暂停',
    labelEn: 'Pause All',
    summaryZh: '关闭所有自动订阅，仅保留你手动预约的单场提醒',
    summaryEn: 'Disable automatic subscriptions while keeping manual reminders',
    flags: { meteor: false, planet: false, moon: false, solarTerm: false, satellite: false, highlightOnly: false },
    passLeadMinutes: 10,
    timingMode: 'smart',
    dndEnabled: true,
    dndSatelliteOnly: true
  }
]

export interface TimingEventInput {
  id: string
  kind: string
  title: string
  at: number
  jd?: number
  target?: string
  subtype?: string
  direction?: string
  primary?: string
  secondary?: string
  phaseIndex?: number
  distanceKm?: number
  isSupermoon?: boolean
  separationDegrees?: number
  observerPlanet?: string
  satMaxAlt?: number
}

export interface TimingOptions {
  nowMs?: number
  timingMode?: NotificationTimingMode
  passLeadMinutes?: number
  regionId?: string
  observerLatitude?: number
  bortleScale?: number
  dndEnabled?: boolean
  dndSatelliteOnly?: boolean
  dndStartMinutes?: number
  dndEndMinutes?: number
  language?: string
}

export interface ReminderTimingPlan {
  fireAt: number
  leadMinutes: number
  windowType: 'pass_countdown' | 'day_before_preview' | 'evening_before' | 'sunset_window' | 'morning_node' | 'just_in_time'
  timingTagZh: string
  timingTagEn: string
  summaryZh: string
  summaryEn: string
  contentZh: string
  contentEn: string
  skippedByQuietHours: boolean
}

export function normalizeTimingMode(raw: string | undefined): NotificationTimingMode {
  if (raw === 'day_before' || raw === 'just_in_time') return raw
  return 'smart'
}

export function topicOfEventKind(kind: string): NotificationTopicId {
  if (kind === 'satellite-pass') return 'satellite'
  if (kind === 'meteor-peak') return 'meteor'
  if (kind === 'moon-phase' || kind === 'companion-phase') return 'moon'
  if (kind === 'solar-term' || kind === 'planetary-season') return 'solar_term'
  return 'planet'
}

export function isMajorAstronomyEvent(event: TimingEventInput): boolean {
  if (event.kind === 'meteor-peak' || event.kind === 'solar-eclipse' ||
    event.kind === 'lunar-eclipse' || event.kind === 'companion-eclipse') {
    return true
  }
  if (event.kind === 'moon-phase' || event.kind === 'companion-phase') {
    return event.isSupermoon === true || event.phaseIndex === 0 || event.phaseIndex === 2
  }
  if (event.kind === 'planetary-event') {
    const sub = (event.subtype ?? '').toLowerCase()
    return sub === 'opposition' || sub === 'greatest-elongation' || sub === 'conjunction' ||
      event.title.includes('冲日') || event.title.includes('大距') || event.title.includes('合')
  }
  if (event.kind === 'satellite-pass') {
    return true
  }
  return false
}

export function eventMatchesTopicFlags(event: TimingEventInput, flags: SubscriptionTopicFlags): boolean {
  const topic = topicOfEventKind(event.kind)
  if (topic === 'satellite') return flags.satellite
  if (topic === 'meteor' && !flags.meteor) return false
  if (topic === 'planet' && !flags.planet) return false
  if (topic === 'moon' && !flags.moon) return false
  if (topic === 'solar_term' && !flags.solarTerm) return false
  if (flags.highlightOnly && !isMajorAstronomyEvent(event)) return false
  return true
}

export function hasAnyAstronomyTopic(flags: SubscriptionTopicFlags): boolean {
  return flags.meteor || flags.planet || flags.moon || flags.solarTerm
}

export function activePresetIdForFlags(
  flags: SubscriptionTopicFlags,
  timingMode: NotificationTimingMode
): SubscriptionPresetId | 'custom' {
  if (!flags.meteor && !flags.planet && !flags.moon && !flags.solarTerm && !flags.satellite) {
    return 'paused'
  }
  for (let i = 0; i < SUBSCRIPTION_PRESETS.length; i++) {
    const p = SUBSCRIPTION_PRESETS[i]
    if (p.flags.meteor === flags.meteor &&
      p.flags.planet === flags.planet &&
      p.flags.moon === flags.moon &&
      p.flags.solarTerm === flags.solarTerm &&
      p.flags.satellite === flags.satellite &&
      p.flags.highlightOnly === flags.highlightOnly &&
      (p.id === 'stations' || p.timingMode === timingMode)) {
      return p.id
    }
  }
  return 'custom'
}

export function canonicalSatellitePassEventId(catalogId: string, peakAtMs: number): string {
  const cleanId = catalogId.trim()
  const minuteBucket = Math.round(peakAtMs / 60000)
  return 'satellite-pass-' + cleanId + '-' + String(minuteBucket)
}

export function normalizeCanonicalEventId(eventId: string): string {
  const trimmed = eventId.trim()
  if (trimmed.length === 0) return ''
  // Normalize legacy satellite pass formats (`pass:<id>:<obs>:<sec>` or `satellite-pass-<id>-<sec>`)
  // into minute-bucketed `satellite-pass-<id>-<minuteBucket>` so widgets, calendar, and subscriptions match.
  const satSecMatch = /^satellite-pass-([A-Za-z0-9_]+)-(\d{9,12})$/.exec(trimmed)
  if (satSecMatch !== null) {
    const sec = Number(satSecMatch[2])
    if (Number.isFinite(sec) && sec > 1000000000) {
      return canonicalSatellitePassEventId(satSecMatch[1], sec * 1000)
    }
  }
  const passSubMatch = /^pass:([A-Za-z0-9_]+):.*:(\d{9,12})$/.exec(trimmed)
  if (passSubMatch !== null) {
    const sec = Number(passSubMatch[2])
    if (Number.isFinite(sec) && sec > 1000000000) {
      return canonicalSatellitePassEventId(passSubMatch[1], sec * 1000)
    }
  }
  return trimmed
}

interface RegionTimingContext {
  offsetMinutes: number
  southern: boolean
  regionSuffixZh: string
  regionSuffixEn: string
}

function resolveRegionOffsetAndHemisphere(options: TimingOptions): RegionTimingContext {
  const normId = normalizeObserverRegionId(options.regionId)
  const preset = normId === FOLLOW_REGION_ID ? undefined : findObserverRegionPreset(normId)
  if (preset !== undefined) {
    return {
      offsetMinutes: preset.utcOffsetMinutes,
      southern: preset.hemisphere === 'south',
      regionSuffixZh: `（${preset.labelZh.split(' · ')[0]} ${preset.tzLabelZh}）`,
      regionSuffixEn: ` (${preset.labelEn} ${preset.tzLabelEn})`
    }
  }
  const lat = options.observerLatitude
  return {
    offsetMinutes: deviceUtcOffsetMinutes(options.nowMs ?? Date.now()),
    southern: typeof lat === 'number' && Number.isFinite(lat) && lat < 0,
    regionSuffixZh: '',
    regionSuffixEn: ''
  }
}

function clampFireTimeToFuture(candidateMs: number, eventAtMs: number, nowMs: number): number {
  const minFuture = nowMs + 60000
  const capped = Math.min(candidateMs, eventAtMs)
  if (capped >= minFuture) return Math.floor(capped / 60000) * 60000
  // If the ideal advance window already passed, fall back to 30 min before event (or 90s from now if imminent)
  const fallback = eventAtMs - 30 * 60000
  if (fallback >= minFuture) return Math.floor(fallback / 60000) * 60000
  if (eventAtMs >= minFuture) return Math.floor(eventAtMs / 60000) * 60000
  return Math.floor((nowMs + 90000) / 60000) * 60000
}

function adjustOutOfQuietHours(
  fireAtMs: number,
  eventAtMs: number,
  nowMs: number,
  offsetMinutes: number,
  dndStart: number,
  dndEnd: number
): number {
  const wc = wallClockInOffset(fireAtMs, offsetMinutes)
  const minuteOfDay = wc.hour * 60 + wc.minute
  if (!isQuietMinute(minuteOfDay, dndStart, dndEnd)) return fireAtMs
  // Shift an advance astronomy preview to 19:30 on the evening before the quiet block rather than waking the user.
  const eveningSameDay = epochFromWallClockInOffset(wc.year, wc.month, wc.day, 19, 30, offsetMinutes)
  const eveningPrevDay = eveningSameDay - 86400000
  const target = (wc.hour < 12 ? eveningPrevDay : eveningSameDay)
  if (target >= nowMs + 60000 && target <= eventAtMs) {
    const twc = wallClockInOffset(target, offsetMinutes)
    if (!isQuietMinute(twc.hour * 60 + twc.minute, dndStart, dndEnd)) {
      return target
    }
  }
  return fireAtMs
}

function moonElongationDegApprox(jd: number): number {
  if (!Number.isFinite(jd) || jd <= 0) return -1
  const t = (jd - 2451545.0) / 36525.0
  const rad = Math.PI / 180.0
  const d = 297.8501921 + 445267.1114034 * t
  const m = 357.5291092 + 35999.0502909 * t
  const mp = 134.9633964 + 477198.8675055 * t
  const elong = d
    + 6.289 * Math.sin(mp * rad)
    - 1.274 * Math.sin((mp - 2 * d) * rad)
    + 0.658 * Math.sin(2 * d * rad)
    - 0.214 * Math.sin(2 * mp * rad)
    - 1.856 * Math.sin(m * rad)
  return ((elong % 360) + 360) % 360
}

function planetZhLabel(englishName: string | undefined): string {
  const map: Record<string, string> = {
    Mercury: '水星', Venus: '金星', Mars: '火星', Jupiter: '木星',
    Saturn: '土星', Uranus: '天王星', Neptune: '海王星', Moon: '月球', Sun: '太阳'
  }
  return englishName ? (map[englishName] ?? englishName) : ''
}

// Compute the astronomically appropriate notification fire time + aligned copy for any event.
export function resolveReminderTimingPlan(
  event: TimingEventInput,
  options: TimingOptions = {}
): ReminderTimingPlan {
  const nowMs = options.nowMs ?? Date.now()
  const timingMode = normalizeTimingMode(options.timingMode)
  const passLead = Number.isInteger(options.passLeadMinutes)
    ? Math.min(60, Math.max(0, options.passLeadMinutes as number))
    : 10
  const dndEnabled = options.dndEnabled === true
  const dndSatelliteOnly = options.dndSatelliteOnly !== false
  const dndStart = Number.isInteger(options.dndStartMinutes) ? (options.dndStartMinutes as number) : 1350
  const dndEnd = Number.isInteger(options.dndEndMinutes) ? (options.dndEndMinutes as number) : 390
  const region = resolveRegionOffsetAndHemisphere(options)
  const evClock = wallClockInOffset(event.at, region.offsetMinutes)
  const evTimeStr = formatRegionClock(event.at, region.offsetMinutes)

  // 1. Satellite Passes — short countdown (default 10 min, user-configurable 0..60 min), obeys quiet hours strictly.
  if (event.kind === 'satellite-pass') {
    const rawFire = event.at - passLead * 60000
    const fireAt = Math.floor(rawFire / 60000) * 60000
    const wc = wallClockInOffset(fireAt, region.offsetMinutes)
    const skipped = dndEnabled && isQuietMinute(wc.hour * 60 + wc.minute, dndStart, dndEnd)
    const altHintZh = typeof event.satMaxAlt === 'number' && event.satMaxAlt > 0
      ? `（最高仰角约 ${Math.round(event.satMaxAlt)}°）` : ''
    const altHintEn = typeof event.satMaxAlt === 'number' && event.satMaxAlt > 0
      ? ` (max alt ~${Math.round(event.satMaxAlt)}°)` : ''
    const contentZh = passLead > 0
      ? `${event.title} 将在 ${passLead} 分钟后过境${altHintZh}，抬头追踪飞行轨迹${region.regionSuffixZh}。`
      : `${event.title} 即将开始过境${altHintZh}，抬头观测${region.regionSuffixZh}！`
    const contentEn = passLead > 0
      ? `${event.title} passes in ${passLead} min${altHintEn}. Look up to track${region.regionSuffixEn}.`
      : `${event.title} is passing now${altHintEn}${region.regionSuffixEn}.`
    return {
      fireAt: fireAt,
      leadMinutes: passLead,
      windowType: 'pass_countdown',
      timingTagZh: passLead > 0 ? `过境前 ${passLead} 分钟` : '过境开始时',
      timingTagEn: passLead > 0 ? `${passLead}m before pass` : 'At pass start',
      summaryZh: `${formatRegionDateTime(fireAt, region.offsetMinutes, true)} 提醒（提前 ${passLead} 分钟）`,
      summaryEn: `Alert at ${formatRegionDateTime(fireAt, region.offsetMinutes, false)} (${passLead}m lead)`,
      contentZh: contentZh,
      contentEn: contentEn,
      skippedByQuietHours: skipped
    }
  }

  let idealFireMs = event.at
  let windowType: ReminderTimingPlan['windowType'] = 'just_in_time'
  let timingTagZh = '临近发生前'
  let timingTagEn = 'Shortly before'

  const isEclipse = event.kind === 'solar-eclipse' || event.kind === 'lunar-eclipse' || event.kind === 'companion-eclipse'
  const isMeteor = event.kind === 'meteor-peak'
  const isMoon = event.kind === 'moon-phase' || event.kind === 'companion-phase'
  const isSolarTerm = event.kind === 'solar-term' || event.kind === 'planetary-season'
  const isPlanet = event.kind === 'planetary-event'

  if (timingMode === 'just_in_time') {
    idealFireMs = event.at - 60 * 60000
    windowType = 'just_in_time'
    timingTagZh = '事件前 1 小时'
    timingTagEn = '1 hour before'
  } else if (timingMode === 'day_before') {
    // Advance planning mode: evening (19:00) on the day before the event so observers can plan weather & gear.
    idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 19, 0, region.offsetMinutes) - 86400000
    windowType = 'day_before_preview'
    timingTagZh = '提前 1 天傍晚预告'
    timingTagEn = 'Day-before evening preview'
  } else {
    // 'smart' astronomical window mode: align notification time to when an observer actually needs to know!
    if (isEclipse) {
      // Eclipses need gear/filter/weather preparation -> 1 day before at 18:30 local; if < 18h away, 30 min before.
      const prevEvening = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 18, 30, region.offsetMinutes) - 86400000
      if (prevEvening >= nowMs + 60000) {
        idealFireMs = prevEvening
        windowType = 'day_before_preview'
        timingTagZh = '提前 1 天傍晚预告'
        timingTagEn = 'Day-before preview'
      } else {
        idealFireMs = event.at - 30 * 60000
        windowType = 'just_in_time'
        timingTagZh = '食相前 30 分钟'
        timingTagEn = '30m before eclipse'
      }
    } else if (isMeteor) {
      // Meteor peaks are observed overnight: if peak is before 19:00 -> notify the evening BEFORE at 19:00!
      // If peak is >= 19:00 -> notify same day at 18:30 (before peak and before dark).
      const eveningOfDay = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 19, 0, region.offsetMinutes)
      if (evClock.hour < 19) {
        idealFireMs = eveningOfDay - 86400000
        windowType = 'evening_before'
        timingTagZh = '极大前一晚入夜前'
        timingTagEn = 'Evening before peak'
      } else {
        idealFireMs = Math.min(epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 18, 30, region.offsetMinutes), event.at - 30 * 60000)
        windowType = 'sunset_window'
        timingTagZh = '极大当晚入夜前'
        timingTagEn = 'Peak evening'
      }
    } else if (isPlanet) {
      const sub = (event.subtype ?? '').toLowerCase()
      const dir = (event.direction ?? '').toLowerCase()
      if (sub === 'greatest-elongation' && dir === 'west') {
        // Best seen before sunrise -> MUST alert the evening BEFORE (20:00) so user sets a morning alarm!
        idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 20, 0, region.offsetMinutes) - 86400000
        windowType = 'evening_before'
        timingTagZh = '前一晚预告明晨观测'
        timingTagEn = 'Evening before pre-dawn window'
      } else if (sub === 'greatest-elongation' && dir === 'east') {
        // Best seen shortly after sunset -> alert at 17:30 if event is evening, else 09:00 morning preview of same day.
        if (evClock.hour >= 18) {
          idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 17, 30, region.offsetMinutes)
          windowType = 'sunset_window'
          timingTagZh = '当日日落前预告'
          timingTagEn = 'Before sunset'
        } else if (evClock.hour >= 9) {
          idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 9, 0, region.offsetMinutes)
          windowType = 'morning_node'
          timingTagZh = '当日早间预告傍晚观测'
          timingTagEn = 'Morning preview for sunset'
        } else {
          idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 19, 0, region.offsetMinutes) - 86400000
          windowType = 'evening_before'
          timingTagZh = '前一晚预告次日观测'
          timingTagEn = 'Evening before'
        }
      } else if (sub === 'conjunction') {
        // Morning conjunctions (00:00-09:59) -> alert previous evening 20:00; daytime/evening -> before event.
        if (evClock.hour < 10) {
          idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 20, 0, region.offsetMinutes) - 86400000
          windowType = 'evening_before'
          timingTagZh = '前一晚预告明晨合相'
          timingTagEn = 'Evening before morning conjunction'
        } else if (evClock.hour >= 19) {
          idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 18, 30, region.offsetMinutes)
          windowType = 'sunset_window'
          timingTagZh = '当晚最佳观测前'
          timingTagEn = 'Before evening viewing'
        } else {
          idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 9, 0, region.offsetMinutes)
          windowType = 'morning_node'
          timingTagZh = '当日早间合相预告'
          timingTagEn = 'Morning conjunction preview'
        }
      } else {
        // Opposition or other planetary milestones -> evening before if <18:00, else 18:30 same evening.
        if (evClock.hour >= 19) {
          idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 18, 30, region.offsetMinutes)
          windowType = 'sunset_window'
          timingTagZh = '入夜前最佳时机'
          timingTagEn = 'Before nightfall'
        } else if (evClock.hour >= 9) {
          idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 9, 0, region.offsetMinutes)
          windowType = 'morning_node'
          timingTagZh = '当日早间预告今夜观测'
          timingTagEn = 'Morning preview for tonight'
        } else {
          idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 18, 30, region.offsetMinutes) - 86400000
          windowType = 'evening_before'
          timingTagZh = '前一晚预告'
          timingTagEn = 'Evening before'
        }
      }
    } else if (isMoon) {
      // Full moon / supermoon / new moon: guarantee fireAt <= eventAt so preview & OS schedule always match 100%.
      const isFull = event.phaseIndex === 2 || event.isSupermoon === true
      if (evClock.hour >= 18) {
        idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, isFull ? 17 : 18, isFull ? 30 : 0, region.offsetMinutes)
        windowType = 'sunset_window'
        timingTagZh = isFull ? '傍晚月升前预告' : '入夜暗空预告'
        timingTagEn = isFull ? 'Before moonrise' : 'Before dark'
      } else if (evClock.hour >= 9) {
        idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 9, 0, region.offsetMinutes)
        windowType = 'morning_node'
        timingTagZh = isFull ? '当日早间预告今晚赏月' : '当日早间月相预告'
        timingTagEn = isFull ? 'Morning full moon preview' : 'Morning moon phase preview'
      } else {
        idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, isFull ? 17 : 18, isFull ? 30 : 0, region.offsetMinutes) - 86400000
        windowType = 'evening_before'
        timingTagZh = isFull ? '前一晚傍晚预告' : '前一晚入夜预告'
        timingTagEn = 'Evening before'
      }
    } else if (isSolarTerm) {
      // Cultural / astronomical solar nodes: 09:00 on the day (or 30m before if the crossing happens before 09:00).
      const morningNode = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 9, 0, region.offsetMinutes)
      if (evClock.hour < 9) {
        idealFireMs = epochFromWallClockInOffset(evClock.year, evClock.month, evClock.day, 20, 0, region.offsetMinutes) - 86400000
        windowType = 'evening_before'
        timingTagZh = '交节前一晚预告'
        timingTagEn = 'Evening before solar node'
      } else {
        idealFireMs = morningNode
        windowType = 'morning_node'
        timingTagZh = '交节当日早间'
        timingTagEn = 'Morning of solar term'
      }
    } else {
      idealFireMs = event.at - 60 * 60000
      windowType = 'just_in_time'
      timingTagZh = '事件前 1 小时'
      timingTagEn = '1 hour before'
    }
  }

  let fireAt = clampFireTimeToFuture(idealFireMs, event.at, nowMs)
  let skippedByQuietHours = false
  if (dndEnabled && !dndSatelliteOnly) {
    const shifted = adjustOutOfQuietHours(fireAt, event.at, nowMs, region.offsetMinutes, dndStart, dndEnd)
    const swc = wallClockInOffset(shifted, region.offsetMinutes)
    if (isQuietMinute(swc.hour * 60 + swc.minute, dndStart, dndEnd)) {
      skippedByQuietHours = true
    } else {
      fireAt = shifted
    }
  }

  const leadMinutes = Math.max(0, Math.round((event.at - fireAt) / 60000))
  const fireClock = wallClockInOffset(fireAt, region.offsetMinutes)
  const isPrevDay = fireClock.year !== evClock.year || fireClock.month !== evClock.month || fireClock.day !== evClock.day

  // Build time-consistent copy so "今晚" vs "明日" NEVER contradicts the actual notification date!
  let contentZh = ''
  let contentEn = ''
  if (isEclipse) {
    if (isPrevDay) {
      contentZh = `明日 ${evTimeStr} 将迎来${event.title}，建议提前检查观测器材与天气${region.regionSuffixZh}。`
      contentEn = `${event.title} occurs tomorrow at ${evTimeStr}. Prepare gear and check skies${region.regionSuffixEn}.`
    } else {
      contentZh = `今日 ${evTimeStr} 迎来${event.title}，打开星象仪查看各食相阶段与可见高度${region.regionSuffixZh}。`
      contentEn = `${event.title} occurs today at ${evTimeStr}. Open Sky Instrument for local phases${region.regionSuffixEn}.`
    }
  } else if (isMeteor) {
    const elong = typeof event.jd === 'number' ? moonElongationDegApprox(event.jd) : -1
    const urban = typeof options.bortleScale === 'number' && options.bortleScale >= 6
    let moonNoteZh = '选择开阔暗空处，打开星象仪定位辐射点'
    let moonNoteEn = 'Find an open dark horizon and locate the radiant in Sky Instrument'
    if (elong >= 0) {
      if (elong < 22 || elong >= 338) {
        moonNoteZh = urban ? '无月光干扰，远离城区灯火可捕捉更多暗流星' : '无月光干扰，暗空条件极佳，适合通宵守候'
        moonNoteEn = urban ? 'Moonless skies; head away from city glare for fainter meteors' : 'Moonless dark skies provide ideal viewing'
      } else if (elong < 95) {
        moonNoteZh = '月光仅影响上半夜，午夜月落后迎来暗空窗口'
        moonNoteEn = 'Moon sets before midnight, leaving dark late-night skies'
      } else if (elong >= 275) {
        moonNoteZh = '残月黎明前才升起，深夜核心时段几乎无月光干扰'
        moonNoteEn = 'Waning crescent stays down until pre-dawn for dark peak hours'
      } else {
        moonNoteZh = '月光较强，建议背向月亮重点守候明亮火流星'
        moonNoteEn = 'Bright moonlight; face away from the Moon to catch fireballs'
      }
    }
    const leadWordZh = isPrevDay && evClock.hour >= 9 ? '明日将迎来' : (evClock.hour < 9 ? '今夜至明晨迎来' : '今夜迎来')
    const leadWordEn = isPrevDay && evClock.hour >= 9 ? 'Tomorrow brings ' : 'Tonight brings '
    contentZh = `${leadWordZh}${event.title}（预计极大 ${evTimeStr}）：${moonNoteZh}${region.regionSuffixZh}。`
    contentEn = `${leadWordEn}${event.title} (est. peak ${evTimeStr}): ${moonNoteEn}${region.regionSuffixEn}.`
  } else if (isPlanet) {
    const pZh = planetZhLabel(event.primary ?? event.target)
    const pEn = event.primary ?? event.target ?? event.title
    const sub = (event.subtype ?? '').toLowerCase()
    if (sub === 'opposition' && pZh.length > 0) {
      contentZh = `${isPrevDay && evClock.hour >= 6 ? '明晚' : '今夜'} ${pZh} 冲日，整夜可见且亮度与视直径处全年高位${region.regionSuffixZh}！`
      contentEn = `${pEn} reaches opposition ${isPrevDay && evClock.hour >= 6 ? 'tomorrow night' : 'tonight'} — visible all night at peak brightness${region.regionSuffixEn}!`
    } else if (sub === 'greatest-elongation' && pZh.length > 0) {
      if (event.direction === 'west') {
        contentZh = `明晨日出前东方低空可寻觅 ${pZh}（西大距清晨最佳窗口），记得早起观测${region.regionSuffixZh}！`
        contentEn = `Look east before sunrise tomorrow for ${pEn} at greatest western elongation${region.regionSuffixEn}!`
      } else {
        contentZh = `${isPrevDay ? '明日' : '今日'}日落后西方低空可寻觅 ${pZh}（东大距傍晚最佳窗口）${region.regionSuffixZh}！`
        contentEn = `Look west shortly after sunset ${isPrevDay ? 'tomorrow' : 'tonight'} for ${pEn} at greatest eastern elongation${region.regionSuffixEn}!`
      }
    } else if (sub === 'conjunction' && event.secondary && event.secondary !== 'Sun' && pZh.length > 0) {
      const sZh = planetZhLabel(event.secondary)
      const sepText = typeof event.separationDegrees === 'number' && Number.isFinite(event.separationDegrees)
        ? `（约 ${event.separationDegrees.toFixed(1)}°）` : ''
      const timeWordZh = evClock.hour < 10 ? `明晨 ${evTimeStr}` : (isPrevDay ? `明晚 ${evTimeStr}` : `今晚 ${evTimeStr}`)
      const timeWordEn = evClock.hour < 10 ? `early tomorrow at ${evTimeStr}` : (isPrevDay ? `tomorrow night at ${evTimeStr}` : `tonight at ${evTimeStr}`)
      contentZh = `${pZh} 与 ${sZh} 近距离相合${sepText}，留意 ${timeWordZh} 前后同框观测${region.regionSuffixZh}。`
      contentEn = `${pEn} and ${event.secondary} are in conjunction — best viewed ${timeWordEn}${region.regionSuffixEn}.`
    } else {
      contentZh = `${event.title}（${formatRegionDateTime(event.at, region.offsetMinutes, true)}），打开星象仪查看观测高度与方位${region.regionSuffixZh}。`
      contentEn = `${event.title} (${formatRegionDateTime(event.at, region.offsetMinutes, false)}). Open Sky Instrument for altitude & azimuth${region.regionSuffixEn}.`
    }
  } else if (isMoon) {
    const dayWordZh = isPrevDay && evClock.hour >= 6 ? '明晚' : '今晚'
    const dayWordEn = isPrevDay && evClock.hour >= 6 ? 'Tomorrow night' : 'Tonight'
    if (event.isSupermoon === true) {
      contentZh = `${dayWordZh}迎来超级满月，日落后自东方升起（精确望时刻 ${evTimeStr}），抬头赏月${region.regionSuffixZh}！`
      contentEn = `${dayWordEn} brings a supermoon rising after sunset (full at ${evTimeStr})${region.regionSuffixEn}!`
    } else if (event.phaseIndex === 0) {
      contentZh = `${dayWordZh}迎来新月，整夜几乎无月光干扰，是观银河与深空天体的绝佳暗夜${region.regionSuffixZh}。`
      contentEn = `${dayWordEn} is New Moon — dark, moonless skies ideal for the Milky Way and deep sky${region.regionSuffixEn}.`
    } else if (event.phaseIndex === 2) {
      contentZh = `${dayWordZh}迎来满月，日落后即可向东方地平线赏月（精确望时刻 ${evTimeStr}）${region.regionSuffixZh}。`
      contentEn = `${dayWordEn} is Full Moon (exact at ${evTimeStr}); watch it rise after sunset${region.regionSuffixEn}.`
    } else {
      contentZh = `${dayWordZh}迎来${event.title}，月面晨昏线环形山立体清晰，适合举镜赏月${region.regionSuffixZh}。`
      contentEn = `${event.title} ${dayWordEn.toLowerCase()} — crisp lunar terminator craters ideal for binoculars${region.regionSuffixEn}.`
    }
  } else if (isSolarTerm) {
    const dayWordZh = isPrevDay ? '明日' : '今日'
    const dayWordEn = isPrevDay ? 'Tomorrow' : 'Today'
    if (event.phaseIndex === 5) {
      contentZh = `${dayWordZh} ${evTimeStr} 迎来${region.southern ? '二分点（南半球入秋）' : '春分（北半球入春）'}，全球昼夜几乎等长${region.regionSuffixZh}。`
      contentEn = `${dayWordEn} at ${evTimeStr}: March equinox (${region.southern ? 'Southern autumn' : 'Northern spring'})${region.regionSuffixEn}.`
    } else if (event.phaseIndex === 11) {
      contentZh = `${dayWordZh} ${evTimeStr} 迎来${region.southern ? '至点（南半球入冬，最长暗夜）' : '夏至（北半球入夏）'}${region.regionSuffixZh}。`
      contentEn = `${dayWordEn} at ${evTimeStr}: June solstice (${region.southern ? 'Southern winter' : 'Northern summer'})${region.regionSuffixEn}.`
    } else if (event.phaseIndex === 17) {
      contentZh = `${dayWordZh} ${evTimeStr} 迎来${region.southern ? '二分点（南半球入春）' : '秋分（北半球入秋）'}，全球昼夜几乎等长${region.regionSuffixZh}。`
      contentEn = `${dayWordEn} at ${evTimeStr}: September equinox (${region.southern ? 'Southern spring' : 'Northern autumn'})${region.regionSuffixEn}.`
    } else if (event.phaseIndex === 23) {
      contentZh = `${dayWordZh} ${evTimeStr} 迎来${region.southern ? '至点（南半球入夏）' : '冬至（北半球入冬，最长暗夜）'}${region.regionSuffixZh}。`
      contentEn = `${dayWordEn} at ${evTimeStr}: December solstice (${region.southern ? 'Southern summer' : 'Northern winter'})${region.regionSuffixEn}.`
    } else {
      contentZh = `${dayWordZh} ${evTimeStr} 步入${event.title}节气，打开星象仪查看当季星空${region.regionSuffixZh}。`
      contentEn = `${dayWordEn} at ${evTimeStr}: ${event.title}. Explore tonight's seasonal sky${region.regionSuffixEn}.`
    }
  } else {
    contentZh = `${event.title}（${formatRegionDateTime(event.at, region.offsetMinutes, true)}），轻触打开星象仪直达观测视角${region.regionSuffixZh}。`
    contentEn = `${event.title} (${formatRegionDateTime(event.at, region.offsetMinutes, false)}). Tap to preview in Sky Instrument${region.regionSuffixEn}.`
  }

  return {
    fireAt: fireAt,
    leadMinutes: leadMinutes,
    windowType: windowType,
    timingTagZh: timingTagZh,
    timingTagEn: timingTagEn,
    summaryZh: `${formatRegionDateTime(fireAt, region.offsetMinutes, true)} 提醒（${timingTagZh}）`,
    summaryEn: `Alert ${formatRegionDateTime(fireAt, region.offsetMinutes, false)} (${timingTagEn})`,
    contentZh: contentZh,
    contentEn: contentEn,
    skippedByQuietHours: skippedByQuietHours
  }
}
