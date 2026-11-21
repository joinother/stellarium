import { CalendarObserverContext, calendarText, calendarSolarTermTitle, calendarMoonPhaseTitle, calendarSolarTermBody, calendarMoonPhaseBody, calendarMeteorShowerBody, calendarPlanetaryBody } from './AstronomyCalendarText'

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
  satCatalogId?: string
  satArchetype?: string
  satMaxAlt?: number
  satVisible?: boolean
  satDurationSec?: number
  satAzimuthSummary?: string
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
    if (item.kind === 'meteor-peak' || item.kind === 'planetary-event' ||
      item.kind === 'companion-phase' || item.kind === 'companion-eclipse' || item.kind === 'planetary-season') {
      if (!Number.isFinite(item.jd) || typeof item.id !== 'string' || !item.id.trim() ||
        typeof item.title !== 'string' || !item.title.trim() || typeof item.titleEn !== 'string' ||
        typeof item.target !== 'string') throw new Error('Invalid calendar event')
      const at = calendarAt(item.jd)
      if (seen.has(item.id) || at < month.start || at >= month.end) continue
      seen.add(item.id)
      const meteor = item.kind === 'meteor-peak'
      const meteorNames: Record<string, string> = { QUA: '象限仪座', LYR: '天琴座',
        ETA: '宝瓶座η', SDA: '宝瓶座δ南', PER: '英仙座', ORI: '猎户座', STA: '金牛座南', NTA: '金牛座北',
        LEO: '狮子座', GEM: '双子座', URS: '小熊座', DRA: '天龙座', AND: '仙女座',
        AMO: '麒麟座α', NOO: '十一月猎户座' }
      const titleZh = meteor && meteorNames[item.showerCode ?? ''] ?
        meteorNames[item.showerCode ?? ''] + '流星雨极大' : item.title
      const sepDeg = typeof item.separationDegrees === 'number' && Number.isFinite(item.separationDegrees) && item.separationDegrees >= 0
        ? item.separationDegrees : undefined
      const nativeBody = typeof item.body === 'string' && item.body.trim().length > 0 ? item.body.trim() : ''
      const body = meteor
        ? calendarMeteorShowerBody(language, titleZh, item.titleEn, item.jd, item.showerCode, context)
        : (isOffEarth || item.kind !== 'planetary-event')
          ? (language.toLowerCase().startsWith('zh') && nativeBody.length > 0
            ? nativeBody
            : calendarText(language, nativeBody || titleZh, `${item.titleEn} (observed from ${eventPlanet ?? 'Earth'}; times use device time zone).`))
          : calendarPlanetaryBody(language, item.primary, item.secondary, item.subtype, item.direction, item.alignment, sepDeg)
      const parsed: AstronomyCalendarEvent = { id: item.id, kind: item.kind, title: calendarText(language, titleZh, item.titleEn),
        at: at, jd: item.jd, body: body, target: item.target,
        panel: meteor ? 'meteorshowers' : 'astro', tab: 0, timeScale: 'UT',
        phaseIndex: item.kind === 'companion-phase' && Number.isInteger(item.index) ? item.index : undefined,
        subtype: item.subtype, direction: item.direction,
        primary: item.primary, secondary: item.secondary, alignment: item.alignment,
        separationDegrees: sepDeg }
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
