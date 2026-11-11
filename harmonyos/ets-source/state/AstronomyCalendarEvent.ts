import { calendarText, calendarSolarTermTitle, calendarMoonPhaseTitle } from './AstronomyCalendarText'

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
}

export interface CalendarNativeResponse {
  ok?: boolean
  year?: number
  month?: number
  startJD?: number
  endJD?: number
  timeScale?: string
  events?: CalendarNativeEvent[]
  error?: string
}

export interface CalendarQuery {
  year: number
  month: number
  startJD: number
  endJD: number
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

export function calendarQuery(month: CalendarMonth): CalendarQuery {
  return { year: month.year, month: month.month, startJD: calendarJd(month.start), endJD: calendarJd(month.end) }
}

export function calendarNativeEvents(response: CalendarNativeResponse, month: CalendarMonth, language: string): AstronomyCalendarEvent[] {
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
    if (item.kind === 'meteor-peak' || item.kind === 'planetary-event') {
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
      const bodyZh = meteor ? '流星雨预计在这段时间达到活跃高峰。选择远离城市灯光、视野开阔的地点，给眼睛留出适应黑暗的时间。月光、天气和辐射点高度都会影响实际观测。这里的时刻由目录模型估算，不是精确的爆发预报。' :
        '这次天象由行星的地心视位置计算得到。合与冲按黄经差定义，大距按与太阳的角距极大定义；实际观测还要结合当地的升落时间。合日附近通常不适合观测，切勿用望远镜直接寻找太阳附近的目标。'
      const bodyEn = meteor ? 'A predicted period of peak meteor activity. Choose a dark, open site and allow your eyes to adapt. Moonlight, weather and radiant altitude affect what you can see. This is a catalog-model estimate, not a precise outburst forecast.' :
        'Computed from geocentric apparent planetary positions. Conjunction and opposition use ecliptic longitude; greatest elongation uses angular separation from the Sun. Check local rise and set times. Solar conjunction is generally unsuitable for observing; never point an unfiltered telescope near the Sun.'
      events.push({ id: item.id, kind: item.kind, title: calendarText(language, titleZh, item.titleEn),
        at: at, jd: item.jd, body: calendarText(language, bodyZh, bodyEn), target: item.target,
        panel: meteor ? 'meteorshowers' : 'astro', tab: 0, timeScale: 'UT' })
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
    const title = solar ? calendarSolarTermTitle(language, item.index) : calendarMoonPhaseTitle(language, item.index)
    const body = solar ? calendarText(language,
      '太阳到达该节气的黄经。本地 Stellarium 引擎计算；时刻按设备时区显示，不代表当地可见性。',
      'The Sun reaches this solar term’s longitude. Calculated locally by Stellarium; times use the device time zone and do not imply local visibility.') :
      calendarText(language, '月球到达主要月相。本地 Stellarium 引擎计算全球发生时刻；时刻按设备时区显示，不代表月球在当地已经升起。',
        'The Moon reaches a principal phase. Stellarium calculates the global instant locally; device-local times do not imply the Moon is above your horizon.')
    events.push({ id: item.id, kind: item.kind, title: title, at: at, jd: jd, body: body,
      target: solar ? 'Sun' : 'Moon', panel: 'astro', tab: solar ? 8 : 6, timeScale: 'UT', phaseIndex: item.index })
  }
  return calendarMonthEvents(events, month)
}

export function calendarEventTime(event: AstronomyCalendarEvent): string {
  const date = new Date(event.at)
  const hour = String(date.getHours()).padStart(2, '0')
  const minute = String(date.getMinutes()).padStart(2, '0')
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${hour}:${minute}`
}
