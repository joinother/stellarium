import {
  CalendarObserverContext,
  calendarText,
  calendarSolarTermTitle,
  calendarMoonPhaseTitle,
  calendarSolarTermBody,
  calendarMoonPhaseBody,
  calendarMeteorShowerBody,
  calendarPlanetaryBody,
  calendarEclipseBody
} from './AstronomyCalendarText'

export interface CalendarEclipseMapData {
  kind: 'solar' | 'lunar'
  cols?: number
  rows?: number
  grid?: string
  centralPath?: number[][]
  subLunarPoints?: number[][]
}

export interface AstronomyCalendarEvent {
  id: string
  kind: string
  title: string
  at: number
  jd: number
  body: string
  target: string
  panel: string
  tab: number
  timeScale?: string
  phaseIndex?: number
  distanceKm?: number
  isSupermoon?: boolean
  subtype?: string
  direction?: string
  primary?: string
  secondary?: string
  alignment?: string
  separationDegrees?: number
  observerPlanet?: string
  showerCode?: string
  satCatalogId?: string
  satArchetype?: string
  satMaxAlt?: number
  satVisible?: boolean
  satDurationSec?: number
  satAzimuthSummary?: string
  satStartAt?: number
  satEndAt?: number
  satStartAz?: number
  satEndAz?: number
  satMag?: number
  // Eclipse & greatest-elongation enrichment
  eclipseMagnitude?: number
  umbralMagnitude?: number
  penumbralMagnitude?: number
  localVisible?: boolean
  localFullVisible?: boolean
  localDaytime?: boolean
  localMagnitude?: number
  localMaxAlt?: number
  eclipseStartAt?: number
  eclipseEndAt?: number
  eclipseMap?: CalendarEclipseMapData
  magnitude?: number
  twilightAltDeg?: number
  twilightAt?: number
  planetSetRiseAt?: number
  twilightOffsetMin?: number
  earthHelioLonDeg?: number
  planetHelioLonDeg?: number
  orbitRatio?: number
  // Dynamic remote calendar overlay metadata (static skyinstrument.cn feed)
  isRemote?: boolean
  remoteBadge?: string
  remoteRevision?: number
  remoteHighlight?: boolean
  remoteEndAt?: number
  remoteEnriched?: boolean
  // Rocket launch trajectory & twilight plume simulation metadata
  rocketPresetId?: string
  rocketSiteId?: string
  rocketVehicleId?: string
  rocketLaunchTimeUtc?: string
  rocketAzimuthDeg?: number
  rocketTargetOrbit?: string
  rocketBadge?: string
}

export interface CalendarNativeEvent {
  id: string
  kind: string
  index: number
  jd: number
  title?: string
  titleEn?: string
  body?: string
  target?: string
  showerCode?: string
  primary?: string
  secondary?: string
  subtype?: string
  direction?: string
  alignment?: string
  separationDegrees?: number
  distanceKm?: number
  isSupermoon?: boolean
  observerPlanet?: string
  eclipseMagnitude?: number
  umbralMagnitude?: number
  penumbralMagnitude?: number
  localVisible?: boolean
  localFullVisible?: boolean
  localDaytime?: boolean
  localMagnitude?: number
  localMaxAlt?: number
  eclipseStartAt?: number
  eclipseEndAt?: number
  eclipseMap?: CalendarEclipseMapData
  magnitude?: number
  twilightAltDeg?: number
  twilightAt?: number
  planetSetRiseAt?: number
  twilightOffsetMin?: number
  earthHelioLonDeg?: number
  planetHelioLonDeg?: number
  orbitRatio?: number
  // Dynamic remote calendar overlay metadata (static skyinstrument.cn feed)
  isRemote?: boolean
  remoteBadge?: string
  remoteRevision?: number
  remoteHighlight?: boolean
  remoteEndAt?: number
  remoteEnriched?: boolean
  // Rocket launch trajectory & twilight plume simulation metadata
  rocketPresetId?: string
  rocketSiteId?: string
  rocketVehicleId?: string
  rocketLaunchTimeUtc?: string
  rocketAzimuthDeg?: number
  rocketTargetOrbit?: string
  rocketBadge?: string
}

// 44/44 全量流星雨标准中文译名（覆盖内置 MeteorShowers.json 全部流星群，杜绝任何英文残余）
export const METEOR_SHOWER_NAMES_ZH: Record<string, string> = {
  ANT: '反太阳源',
  ARI: '白昼白羊座',
  DSX: '白昼六分仪座',
  NOO: '十一月猎户座',
  ACE: '半人马座α',
  AMO: '麒麟座α',
  AND: '仙女座',
  AUR: '御夫座',
  CAP: '摩羯座α',
  COM: '后发座',
  DAU: '十月御夫座δ',
  DLM: '十二月小狮座',
  DRA: '天龙座',
  EGE: '双子座ε',
  ELY: '天琴座η',
  ETA: '宝瓶座η',
  GEM: '双子座',
  GNO: '矩尺座γ',
  HYD: '长蛇座σ',
  JBO: '六月牧夫座',
  KCG: '天鹅座κ',
  LEO: '狮子座',
  LMI: '小狮座',
  LYR: '四月天琴座',
  MON: '十二月麒麟座',
  NIA: '北宝瓶座ι',
  NTA: '金牛座北',
  ORI: '猎户座',
  PAU: '南鱼座',
  PER: '英仙座',
  PHO: '凤凰座',
  PPU: '船尾座π',
  PUP: '船尾-船帆座',
  QUA: '象限仪座',
  SDA: '宝瓶座δ南',
  SPE: '九月英仙座ε',
  STA: '金牛座南',
  TAH: '武仙座τ',
  URS: '小熊座',
  ERI: '波江座η',
  GUM: '小熊座γ',
  JPE: '七月飞马座',
  GDR: '七月天龙座γ',
  OCT: '十月鹿豹座'
}

export interface CalendarNativeResponse {
  ok?: boolean
  year?: number
  month?: number
  startJD?: number
  endJD?: number
  timeScale?: string
  observerPlanet?: string
  events?: CalendarNativeEvent[]
  error?: string
}

export interface CalendarQuery {
  year: number
  month: number
  startJD: number
  endJD: number
  planet?: string
}

export interface CalendarMonth {
  year: number
  month: number
  days: number
  firstWeekday: number
  start: number
  end: number
}

export interface CalendarDay {
  key: string
  day: number
  count: number
}

export const CALENDAR_MIN_YEAR: number = 1
export const CALENDAR_MAX_YEAR: number = 3000

export function calendarDate(year: number, month: number, day: number): Date {
  const date = new Date(0)
  date.setFullYear(year, month - 1, day)
  date.setHours(0, 0, 0, 0)
  return date
}

export function calendarMonth(year: number, month: number): CalendarMonth {
  if (!Number.isInteger(year) || !Number.isInteger(month) || year < CALENDAR_MIN_YEAR ||
    year > CALENDAR_MAX_YEAR || month < 1 || month > 12) {
    throw new Error('日历年月超出支持范围（1–3000 年）。')
  }
  const start = calendarDate(year, month, 1)
  const end = calendarDate(year, month + 1, 1)
  return {
    year: year, month: month, days: calendarDate(year, month + 1, 0).getDate(),
    firstWeekday: start.getDay(), start: start.getTime(), end: end.getTime()
  }
}

export function calendarJd(at: number): number {
  return at / 86400000 + 2440587.5
}

export function calendarAt(jd: number): number {
  return Math.round((jd - 2440587.5) * 86400000)
}

export function calendarMonthEvents(events: AstronomyCalendarEvent[], month: CalendarMonth): AstronomyCalendarEvent[] {
  return events.filter((event: AstronomyCalendarEvent) => event.at >= month.start && event.at < month.end)
    .sort((left: AstronomyCalendarEvent, right: AstronomyCalendarEvent) => left.at - right.at || left.id.localeCompare(right.id))
}

export function calendarDayEvents(events: AstronomyCalendarEvent[], day: number): AstronomyCalendarEvent[] {
  return day === 0 ? events.slice() : events.filter((event: AstronomyCalendarEvent) => new Date(event.at).getDate() === day)
}

export function calendarDays(month: CalendarMonth, events: AstronomyCalendarEvent[]): CalendarDay[] {
  const cells: CalendarDay[] = []
  const count = Math.ceil((month.firstWeekday + month.days) / 7) * 7
  for (let index = 0; index < count; index++) {
    const day = index - month.firstWeekday + 1
    const valid = day > 0 && day <= month.days
    cells.push({ key: `${month.year}-${month.month}-${index}`, day: valid ? day : 0,
      count: valid ? calendarDayEvents(events, day).length : 0 })
  }
  return cells
}

export function calendarQuery(month: CalendarMonth, observerPlanet?: string): CalendarQuery {
  const query: CalendarQuery = {
    year: month.year, month: month.month, startJD: calendarJd(month.start), endJD: calendarJd(month.end)
  }
  const trimmed = observerPlanet?.trim() ?? ''
  if (trimmed.length > 0 && trimmed.toLowerCase() !== 'earth') {
    query.planet = trimmed
  }
  return query
}

export function calendarNativeEvents(
  response: CalendarNativeResponse,
  month: CalendarMonth,
  language: string,
  context?: CalendarObserverContext
): AstronomyCalendarEvent[] {
  const events: AstronomyCalendarEvent[] = []
  const seen = new Set<string>()
  if (response.ok !== true || response.year !== month.year || response.month !== month.month ||
    response.timeScale !== 'UT' || !Array.isArray(response.events) ||
    response.startJD === undefined || response.endJD === undefined ||
    !Number.isFinite(response.startJD) || !Number.isFinite(response.endJD) ||
    Math.abs(calendarAt(response.startJD) - month.start) > 1 || Math.abs(calendarAt(response.endJD) - month.end) > 1) {
    throw new Error('Invalid calendar response')
  }
  for (const item of response.events) {
    if (item === null || typeof item !== 'object') throw new Error('Invalid calendar event')
    const solar = item.kind === 'solar-term'
    const responsePlanet = typeof response.observerPlanet === 'string' && response.observerPlanet.trim().length > 0
      ? response.observerPlanet.trim() : undefined
    const eventPlanet = typeof item.observerPlanet === 'string' && item.observerPlanet.trim().length > 0
      ? item.observerPlanet.trim() : responsePlanet
    const isOffEarth = eventPlanet !== undefined && eventPlanet.toLowerCase() !== 'earth'
    if (item.kind === 'solar-eclipse' || item.kind === 'lunar-eclipse') {
      if (!Number.isFinite(item.jd) || typeof item.id !== 'string' || !item.id.trim() ||
        typeof item.title !== 'string' || !item.title.trim() || typeof item.titleEn !== 'string') {
        throw new Error('Invalid calendar event')
      }
      const at = calendarAt(item.jd)
      if (seen.has(item.id) || at < month.start || at >= month.end) continue
      seen.add(item.id)
      const isSolar = item.kind === 'solar-eclipse'
      const body = calendarEclipseBody(language, {
        kind: isSolar ? 'solar-eclipse' : 'lunar-eclipse',
        subtype: item.subtype,
        atMs: at,
        eclipseMagnitude: item.eclipseMagnitude,
        umbralMagnitude: item.umbralMagnitude,
        localVisible: item.localVisible,
        localFullVisible: item.localFullVisible,
        localDaytime: item.localDaytime,
        localMagnitude: item.localMagnitude,
        localMaxAlt: item.localMaxAlt,
        eclipseStartAt: item.eclipseStartAt,
        eclipseEndAt: item.eclipseEndAt
      })
      events.push({
        id: item.id,
        kind: item.kind,
        title: calendarText(language, item.title, item.titleEn),
        at: at,
        jd: item.jd,
        body: body,
        target: isSolar ? 'Sun' : 'Moon',
        panel: 'astro',
        tab: 7,
        timeScale: 'UT',
        subtype: item.subtype,
        eclipseMagnitude: item.eclipseMagnitude,
        umbralMagnitude: item.umbralMagnitude,
        penumbralMagnitude: item.penumbralMagnitude,
        localVisible: item.localVisible,
        localFullVisible: item.localFullVisible,
        localDaytime: item.localDaytime,
        localMagnitude: item.localMagnitude,
        localMaxAlt: item.localMaxAlt,
        eclipseStartAt: item.eclipseStartAt,
        eclipseEndAt: item.eclipseEndAt,
        eclipseMap: item.eclipseMap
      })
      continue
    }
    if (item.kind === 'meteor-peak' || item.kind === 'planetary-event' ||
      item.kind === 'companion-phase' || item.kind === 'companion-eclipse' || item.kind === 'planetary-season') {
      if (!Number.isFinite(item.jd) || typeof item.id !== 'string' || !item.id.trim() ||
        typeof item.title !== 'string' || !item.title.trim() || typeof item.titleEn !== 'string' ||
        typeof item.target !== 'string') throw new Error('Invalid calendar event')
      const at = calendarAt(item.jd)
      if (seen.has(item.id) || at < month.start || at >= month.end) continue
      seen.add(item.id)
      const meteor = item.kind === 'meteor-peak'
      const codeKey = item.showerCode ?? ''
      const titleZh = meteor && METEOR_SHOWER_NAMES_ZH[codeKey]
        ? (METEOR_SHOWER_NAMES_ZH[codeKey] + '流星雨极大')
        : item.title
      const sepDeg = typeof item.separationDegrees === 'number' && Number.isFinite(item.separationDegrees) && item.separationDegrees >= 0
        ? item.separationDegrees : undefined
      const nativeBody = typeof item.body === 'string' && item.body.trim().length > 0 ? item.body.trim() : ''
      const body = meteor
        ? calendarMeteorShowerBody(language, titleZh, item.titleEn, item.jd, item.showerCode, context)
        : (isOffEarth || item.kind !== 'planetary-event')
          ? (language.toLowerCase().startsWith('zh') && nativeBody.length > 0
            ? nativeBody
            : calendarText(language, nativeBody || titleZh, `${item.titleEn} (observed from ${eventPlanet ?? 'Earth'}; times use device time zone).`))
          : calendarPlanetaryBody(language, item.primary, item.secondary, item.subtype, item.direction, item.alignment, sepDeg, {
            magnitude: item.magnitude,
            twilightAltDeg: item.twilightAltDeg,
            planetSetRiseAt: item.planetSetRiseAt,
            twilightOffsetMin: item.twilightOffsetMin,
            eventAt: at
          })
      const parsed: AstronomyCalendarEvent = { id: item.id, kind: item.kind, title: calendarText(language, titleZh, item.titleEn),
        at: at, jd: item.jd, body: body, target: item.target,
        panel: meteor ? 'meteorshowers' : 'astro', tab: 0, timeScale: 'UT',
        phaseIndex: item.kind === 'companion-phase' && Number.isInteger(item.index) ? item.index : undefined,
        subtype: item.subtype, direction: item.direction,
        primary: item.primary, secondary: item.secondary, alignment: item.alignment,
        separationDegrees: sepDeg,
        showerCode: typeof item.showerCode === 'string' && item.showerCode.trim().length > 0 ? item.showerCode.trim() : undefined,
        magnitude: item.magnitude,
        twilightAltDeg: item.twilightAltDeg,
        twilightAt: item.twilightAt,
        planetSetRiseAt: item.planetSetRiseAt,
        twilightOffsetMin: item.twilightOffsetMin,
        earthHelioLonDeg: item.earthHelioLonDeg,
        planetHelioLonDeg: item.planetHelioLonDeg,
        orbitRatio: item.orbitRatio }
      if (isOffEarth) parsed.observerPlanet = eventPlanet
      events.push(parsed)
      continue
    }
    if (!solar && item.kind !== 'moon-phase') continue
    if (!Number.isInteger(item.index) || item.index < 0 || item.index >= (solar ? 24 : 4) ||
      !Number.isFinite(item.jd) || item.jd <= 0 || typeof item.id !== 'string' || item.id.trim() === '') {
      throw new Error('Invalid calendar event')
    }
    const jd = item.jd
    const at = calendarAt(jd)
    if (seen.has(item.id) || at < month.start || at >= month.end) continue
    seen.add(item.id)
    const distKm = typeof item.distanceKm === 'number' && Number.isFinite(item.distanceKm) && item.distanceKm > 0
      ? item.distanceKm : undefined
    const supermoon = !solar && item.index === 2 &&
      (item.isSupermoon === true || (distKm !== undefined && distKm <= 360000))
    const title = solar ? calendarSolarTermTitle(language, item.index) :
      (supermoon ? calendarText(language, '超级满月', 'Supermoon') : calendarMoonPhaseTitle(language, item.index))
    const body = solar
      ? calendarSolarTermBody(language, item.index, at, context)
      : calendarMoonPhaseBody(language, item.index, at, supermoon, distKm)
    events.push({ id: item.id, kind: item.kind, title: title, at: at, jd: jd, body: body,
      target: solar ? 'Sun' : 'Moon', panel: 'astro', tab: solar ? 8 : 6, timeScale: 'UT',
      phaseIndex: item.index, distanceKm: distKm, isSupermoon: supermoon || undefined })
  }
  return calendarMonthEvents(events, month)
}

export function calendarEventTime(event: AstronomyCalendarEvent): string {
  const date = new Date(event.at)
  const hour = String(date.getHours()).padStart(2, '0')
  const minute = String(date.getMinutes()).padStart(2, '0')
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${hour}:${minute}`
}
