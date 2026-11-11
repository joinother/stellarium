import { I18n } from './I18n'
import { AstronomyCalendarEvent, CalendarMonth, CalendarNativeResponse, calendarMonth, calendarNativeEvents, calendarQuery } from '../state/AstronomyCalendarEvent'
import { AstronomySubscriptionCategory, AstronomySubscriptionFeed } from '../qability/AstronomySubscriptionPolicy'

export interface SubscriptionObserver {
  key: string
  satelliteIds?: string[]
}

export interface SubscriptionSatellitePass {
  startJD: number
  visible: boolean
  ongoing: boolean
}

export interface SubscriptionSatelliteResponse {
  satelliteId: string
  englishName: string
  name: string
  calculatedAt: string
  dataStatus: string
  orbitValid: boolean
  passes: SubscriptionSatellitePass[]
}

export interface SubscriptionNativeResponse extends CalendarNativeResponse {
  reason?: string
  satellitePasses?: SubscriptionSatelliteResponse
  latitude?: number
  longitude?: number
  altitude?: number
  planet?: string
}

export function decodeSubscriptionNativeResponse(json: string): SubscriptionNativeResponse {
  const value = JSON.parse(json) as SubscriptionNativeResponse
  if (value === null || typeof value !== 'object' || Array.isArray(value) || typeof value.ok !== 'boolean') {
    throw new Error('Invalid native subscription response')
  }
  if (value.satellitePasses !== undefined) {
    const data = value.satellitePasses
    if (data === null || typeof data !== 'object' || Array.isArray(data) || !Array.isArray(data.passes) ||
      typeof data.satelliteId !== 'string' || typeof data.calculatedAt !== 'string' ||
      typeof data.orbitValid !== 'boolean' || typeof data.dataStatus !== 'string') {
      throw new Error('Expected native satellitePasses envelope with passes array')
    }
  }
  return value
}

export interface SubscriptionNativeHooks {
  request(command: string, payload: string): Promise<SubscriptionNativeResponse>
  observer(): Promise<SubscriptionObserver | undefined>
}

interface SubscriptionMonthCacheEntry {
  events: AstronomyCalendarEvent[]
  expiresAt: number
}

export class AstronomySubscriptionFeedLoader {
  private hooks: SubscriptionNativeHooks
  private monthCache: Map<string, SubscriptionMonthCacheEntry> = new Map()
  private monthRequests: Map<string, Promise<AstronomyCalendarEvent[]>> = new Map()
  private cacheGeneration: number = 0
  constructor(hooks: SubscriptionNativeHooks) { this.hooks = hooks }

  public invalidate(): void {
    this.cacheGeneration += 1
    this.monthCache.clear()
    this.monthRequests.clear()
  }

  private loadMonth(range: CalendarMonth, language: string): Promise<AstronomyCalendarEvent[]> {
    const key = JSON.stringify([range.year, range.month, range.start, range.end, language])
    const cached = this.monthCache.get(key)
    if (cached !== undefined && cached.expiresAt > Date.now()) {
      this.monthCache.delete(key)
      this.monthCache.set(key, cached)
      return Promise.resolve(cached.events.slice())
    }
    this.monthCache.delete(key)
    const existing = this.monthRequests.get(key)
    if (existing !== undefined) return existing
    const generation = this.cacheGeneration
    const request: Promise<AstronomyCalendarEvent[]> = this.fetchMonth(range, language, key, generation).finally(() => {
      if (this.monthRequests.get(key) === request) this.monthRequests.delete(key)
    })
    this.monthRequests.set(key, request)
    return request
  }

  private async fetchMonth(range: CalendarMonth, language: string, key: string, generation: number): Promise<AstronomyCalendarEvent[]> {
    const response = await this.hooks.request('getAstronomyCalendarEvents', JSON.stringify(calendarQuery(range)))
    const events = calendarNativeEvents(response, range, language)
    if (generation !== this.cacheGeneration) throw new Error('Subscription month cache invalidated')
    for (const entry of this.monthCache) {
      if (entry[1].expiresAt <= Date.now()) this.monthCache.delete(entry[0])
    }
    this.monthCache.set(key, { events: events.slice(), expiresAt: Date.now() + 6 * 3600000 })
    while (this.monthCache.size > 6) {
      for (const oldest of this.monthCache) {
        this.monthCache.delete(oldest[0])
        break
      }
    }
    return events
  }

  async load(category: AstronomySubscriptionCategory, from: number, until: number): Promise<AstronomySubscriptionFeed> {
    const events: AstronomyCalendarEvent[] = []
    if (category === 'astronomy') {
      const language = I18n.getLanguage()
      const generation = this.cacheGeneration
      const cursor = new Date(from)
      cursor.setDate(1)
      cursor.setHours(0, 0, 0, 0)
      for (let index = 0; index < 3 && cursor.getTime() < until; index++) {
        const range = calendarMonth(cursor.getFullYear(), cursor.getMonth() + 1)
        events.push(...await this.loadMonth(range, language))
        if (generation !== this.cacheGeneration) throw new Error('Subscription month cache invalidated')
        cursor.setMonth(cursor.getMonth() + 1)
      }
      return { events: events, generatedAt: Date.now() }
    }
    const observer = await this.hooks.observer()
    const satelliteIds = observer?.satelliteIds ?? ['25544', '48274']
    if (!observer || !observer.key.trim() || satelliteIds.length === 0 || satelliteIds.length > 8) {
      throw new Error('A chosen observer and one to eight satellite IDs are required')
    }
    for (const id of satelliteIds) {
      if (!/^\d{1,9}$/.test(id)) throw new Error('Invalid NORAD ID')
      const response = await this.hooks.request('getSatellitePasses', JSON.stringify({
        id: id, hours: 48, limit: 32, minElevation: 10, visibleOnly: true,
        startJD: from / 86400000 + 2440587.5
      }))
      if (response.reason === 'explicit_epoch_prediction_unsupported') {
        throw new Error('Satellite subscriptions unavailable: explicit_epoch_prediction_unsupported')
      }
      const data = response.satellitePasses
      if (!response.ok || !data || data.satelliteId !== id || !data.orbitValid || data.dataStatus !== 'local' ||
        typeof data.calculatedAt !== 'string' || !Array.isArray(data.passes)) throw new Error('Satellite predictions unavailable or stale')
      const timestamp = /(?:Z|[+-]\d{2}:\d{2})$/.test(data.calculatedAt) ? data.calculatedAt : data.calculatedAt + 'Z'
      const calculatedAt = Date.parse(timestamp)
      if (!Number.isFinite(calculatedAt) || Math.abs(calculatedAt - from) > 120000) throw new Error('Satellite prediction uses simulation time')
      if ((await this.hooks.observer())?.key !== observer.key) throw new Error('Observer changed during prediction')
      for (const pass of data.passes) {
        if (!pass || pass.visible !== true || pass.ongoing === true) continue
        if (!Number.isFinite(pass.startJD)) throw new Error('Invalid satellite pass time')
        const at = Math.round((pass.startJD - 2440587.5) * 86400000)
        if (at <= from || at >= until) continue
        events.push({
          id: 'pass:' + id + ':' + observer.key + ':' + Math.floor(at / 1000), kind: 'satellite-pass',
          title: data.name || data.englishName || id, body: '', at: at, jd: pass.startJD,
          target: data.englishName || id, panel: 'satellites', tab: 0
        })
      }
    }
    return { events: events, generatedAt: Date.now(), observerKey: observer.key }
  }
}
