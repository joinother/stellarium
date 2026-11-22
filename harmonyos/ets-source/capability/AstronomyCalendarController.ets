import { CommandPort } from '../bridge/CommandPort'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { AstronomyCalendarStore } from '../state/AstronomyCalendarStore'
import { AstronomyCalendarCache } from '../state/AstronomyCalendarCache'
import { AstronomyCalendarEvent, CalendarNativeResponse, calendarMonth, calendarDays, calendarQuery, calendarNativeEvents } from '../state/AstronomyCalendarEvent'
import { CalendarObserverContext, calendarPlanetName, calendarText } from '../state/AstronomyCalendarText'
import {
  CALENDAR_QUICK_PRESETS,
  NativeSatellitePassRecord,
  isEarthCalendarPlanet,
  monthOverlapsSatelliteWindow,
  parseTonightSatellitePassesToCalendarEvents
} from '../state/AstronomyCalendarFilter'
import { findObserverRegionPreset, normalizeObserverRegionId } from '../state/ObserverRegionScope'
import { AstronomyReminderResult } from '../qability/AstronomyReminderService'
import {
  RemoteCalendarEntry,
  countRemoteDynamicEvents,
  mergeRemoteCalendarEvents
} from '../state/RemoteCalendarFeed'

export interface AstronomyCalendarReminderResult extends AstronomyReminderResult {
  message?: string
}

export interface AstronomyCalendarHostHooks {
  viewSky(event: AstronomyCalendarEvent): void
  remind(event: AstronomyCalendarEvent): Promise<AstronomyCalendarReminderResult>
  feedChanged(events: AstronomyCalendarEvent[]): void
  observerContext?(): CalendarObserverContext
  onFilterChanged?(): void
  remoteEntries?(): RemoteCalendarEntry[]
}

export class AstronomyCalendarController {
  private port: CommandPort
  private store: AstronomyCalendarStore
  private hooks: AstronomyCalendarHostHooks
  private sequence: number = 0
  private disposed: boolean = false
  private language: string = 'zh'
  private response: CalendarNativeResponse | undefined = undefined
  private extraResponses: CalendarNativeResponse[] = []
  private rawSatellitePasses: NativeSatellitePassRecord[] = []

  constructor(port: CommandPort, store: AstronomyCalendarStore, hooks: AstronomyCalendarHostHooks) {
    this.port = port
    this.store = store
    this.hooks = hooks
  }

  private currentObserverPlanet(): string {
    const raw = this.hooks.observerContext?.()?.observerPlanet?.trim() ?? ''
    return raw.length > 0 ? raw : 'Earth'
  }

  private effectiveObserverContext(): CalendarObserverContext | undefined {
    const base = this.hooks.observerContext?.()
    const preset = findObserverRegionPreset(this.store.regionId)
    if (preset !== undefined && isEarthCalendarPlanet(this.store.observerPlanet)) {
      return {
        latitude: preset.latitude,
        bortleScale: preset.bortleHint,
        observerPlanet: base?.observerPlanet ?? 'Earth'
      }
    }
    return base
  }

  private recomputeMonthDays(): void {
    const range = calendarMonth(this.store.year, this.store.month)
    const filteredMonth = this.store.filteredEvents().filter((event: AstronomyCalendarEvent) => {
      return event.at >= range.start && event.at < range.end
    })
    this.store.days = calendarDays(range, filteredMonth)
  }

  private mergeEventsWithSatellites(baseEvents: AstronomyCalendarEvent[]): AstronomyCalendarEvent[] {
    let working = baseEvents
    const startRange = calendarMonth(this.store.year, this.store.month)
    const endRange = calendarMonth(this.store.throughYear, this.store.throughMonth)
    if (isEarthCalendarPlanet(this.store.observerPlanet) && this.rawSatellitePasses.length > 0) {
      const satEvents = parseTonightSatellitePassesToCalendarEvents(
        this.rawSatellitePasses,
        startRange.start,
        endRange.end,
        this.language
      ) as AstronomyCalendarEvent[]
      if (satEvents.length > 0) {
        working = working.concat(satEvents)
      }
    }
    const remoteEntries = this.hooks.remoteEntries !== undefined ? this.hooks.remoteEntries() : []
    if (remoteEntries.length > 0) {
      const ctx = this.effectiveObserverContext()
      working = mergeRemoteCalendarEvents(working, remoteEntries, {
        rangeStart: startRange.start,
        rangeEnd: endRange.end,
        observerPlanet: this.store.observerPlanet,
        observerLatitude: ctx?.latitude,
        observerLongitude: ctx?.longitude,
        regionId: this.store.regionId,
        language: this.language
      })
    } else {
      working.sort((left: AstronomyCalendarEvent, right: AstronomyCalendarEvent) => left.at - right.at || left.id.localeCompare(right.id))
    }
    return working
  }

  private rebuildFromLoadedResponses(): void {
    if (this.response === undefined) return
    const range = calendarMonth(this.store.year, this.store.month)
    const ctx = this.effectiveObserverContext()
    let rebuilt = calendarNativeEvents(this.response, range, this.language, ctx)
    for (const extra of this.extraResponses) {
      rebuilt = rebuilt.concat(calendarNativeEvents(extra,
        calendarMonth(extra.year as number, extra.month as number), this.language, ctx))
    }
    this.store.events = this.mergeEventsWithSatellites(rebuilt)
    this.recomputeMonthDays()
    this.updateCoverage()
    this.store.filterRevision += 1
    this.hooks.feedChanged(this.store.events.slice())
  }

  refreshRemoteOverlay(): void {
    if (this.disposed || this.response === undefined) return
    try {
      this.rebuildFromLoadedResponses()
    } catch (_) {}
  }

  private fetchSatellitePassesIfApplicable(sequence: number, year: number, month: number, planet: string): void {
    if (!isEarthCalendarPlanet(planet) || !monthOverlapsSatelliteWindow(year, month)) {
      this.store.satellitePassesLoading = false
      return
    }
    this.store.satellitePassesLoading = true
    try {
      this.port.requestInteractive('getTonightEvents', '', (response: StellariumBridgeResponse): void => {
        if (this.disposed || sequence !== this.sequence) return
        this.store.satellitePassesLoading = false
        const payload = response as Record<string, Object>
        const tonightObj = payload['tonight'] as Record<string, Object> | undefined
        const rawList = tonightObj !== undefined && Array.isArray(tonightObj['satellitePasses'])
          ? tonightObj['satellitePasses']
          : payload['satellitePasses']
        if (!Array.isArray(rawList) || rawList.length === 0) return
        this.rawSatellitePasses = rawList as NativeSatellitePassRecord[]
        if (this.response !== undefined) {
          this.rebuildFromLoadedResponses()
        } else {
          const nonSat = this.store.events.filter((ev: AstronomyCalendarEvent) => ev.kind !== 'satellite-pass' && ev.isRemote !== true)
          const merged = this.mergeEventsWithSatellites(nonSat)
          this.store.events = merged
          this.recomputeMonthDays()
          this.store.filterRevision += 1
          this.hooks.feedChanged(merged.slice())
        }
      })
    } catch (_) {
      this.store.satellitePassesLoading = false
    }
  }

  private cacheKeyFor(year: number, month: number, planet: string): string {
    const ctx = this.effectiveObserverContext()
    return AstronomyCalendarCache.makeKey(planet, year, month, ctx?.latitude, ctx?.longitude)
  }

  private prefetchAheadMonths(sequence: number, remaining: number): void {
    if (this.disposed || sequence !== this.sequence || remaining <= 0) return
    if (this.store.loading || this.store.loadingMore || !this.store.loaded) return
    if (this.store.throughYear === 3000 && this.store.throughMonth === 12) return
    this.loadMore(() => {
      if (!this.disposed && sequence === this.sequence && remaining > 1) {
        setTimeout(() => { this.prefetchAheadMonths(sequence, remaining - 1) }, 60)
      }
    })
  }

  loadMonth(year: number, month: number): void {
    if (this.disposed) return
    const range = calendarMonth(year, month)
    const planet = this.currentObserverPlanet()
    const sequence = ++this.sequence
    this.store.year = year
    this.store.month = month
    this.store.throughYear = year
    this.store.throughMonth = month
    this.store.observerPlanet = planet
    this.store.loadingMore = false
    this.extraResponses = []
    this.rawSatellitePasses = []
    this.store.satellitePassesLoading = false
    this.store.selectedDay = 0
    this.store.selectedEventId = ''
    this.store.error = ''
    this.store.actionMessage = ''
    this.response = undefined

    const applyLoaded = (native: CalendarNativeResponse, fromCache: boolean): void => {
      const baseEvents = calendarNativeEvents(native, range, this.language, this.effectiveObserverContext())
      const events = this.mergeEventsWithSatellites(baseEvents)
      this.response = native
      this.store.sourceYear = year
      this.store.events = events
      this.recomputeMonthDays()
      this.store.loading = false
      this.store.loaded = true
      this.updateCoverage()
      this.hooks.feedChanged(events.slice())
      this.fetchSatellitePassesIfApplicable(sequence, year, month, planet)
      // 首月就绪后顺滑预载后续 2 个月（已缓存则 0ms 秒出），确保滚动与搜索卡片流持续连贯。
      setTimeout(() => { this.prefetchAheadMonths(sequence, fromCache ? 3 : 2) }, fromCache ? 16 : 90)
    }

    const cacheKey = this.cacheKeyFor(year, month, planet)
    const cached = AstronomyCalendarCache.getInstance().get(cacheKey)
    if (cached !== undefined) {
      try {
        applyLoaded(cached, true)
        return
      } catch (_) {}
    }

    this.store.events = []
    this.store.days = calendarDays(range, [])
    this.store.coverage = ''
    this.store.sourceYear = 0
    this.store.loading = true
    this.store.loaded = false
    this.hooks.feedChanged([])
    const fail = (): void => {
      if (this.disposed || sequence !== this.sequence) return
      this.store.loading = false
      this.store.error = calendarText(this.language, '本地天象数据读取失败，请重试。', 'Could not load local events. Please retry.')
    }
    try {
      this.port.requestLongRunning('getAstronomyCalendarEvents', JSON.stringify(calendarQuery(range, planet)), (response: StellariumBridgeResponse): void => {
        if (this.disposed || sequence !== this.sequence) return
        try {
          const native = response as CalendarNativeResponse
          AstronomyCalendarCache.getInstance().put(cacheKey, native)
          applyLoaded(native, false)
        } catch (_) {
          fail()
        }
      }, fail, undefined, 240, (): boolean => this.disposed || sequence !== this.sequence)
    } catch (_) {
      fail()
    }
  }

  private updateCoverage(): void {
    const planet = this.store.observerPlanet || 'Earth'
    const remoteCount = countRemoteDynamicEvents(this.store.events)
    if (planet.toLowerCase() !== 'earth') {
      const label = calendarPlanetName(this.language, planet)
      this.store.coverage = calendarText(this.language,
        `已按「${label}」视角载入当地行星冲合、大距、伴星相位与季节事件；按设备时区显示（不含地球流星雨与近地卫星）。`,
        `Loaded local planetary alignments, companion phases, and seasonal events from ${label}; times use the device time zone (Earth meteors & satellites excluded).`)
      return
    }
    const remoteSuffixZh = remoteCount > 0 ? `，另含 ${remoteCount} 条云端动态天象` : ''
    const remoteSuffixEn = remoteCount > 0 ? `, plus ${remoteCount} live alert(s)` : ''
    this.store.coverage = calendarText(this.language,
      `已载入日月食、节气、主要月相、流星雨极大、行星/亮星合相及近 48 小时卫星过境${remoteSuffixZh}；按设备时区显示。`,
      `Eclipses, solar terms, lunar phases, meteor peaks, planetary/star alignments and 48h satellite passes${remoteSuffixEn} loaded; times use the device time zone.`)
  }

  loadMore(onDone?: () => void): void {
    if (this.disposed || this.store.loading || this.store.loadingMore || !this.store.loaded ||
      (this.store.throughYear === 3000 && this.store.throughMonth === 12)) return
    const year = this.store.throughMonth === 12 ? this.store.throughYear + 1 : this.store.throughYear
    const month = this.store.throughMonth === 12 ? 1 : this.store.throughMonth + 1
    const range = calendarMonth(year, month)
    const planet = this.store.observerPlanet || 'Earth'
    const sequence = this.sequence
    const appendNative = (native: CalendarNativeResponse): void => {
      this.extraResponses.push(native)
      this.store.throughYear = year
      this.store.throughMonth = month
      if (this.response !== undefined) {
        this.rebuildFromLoadedResponses()
      } else {
        const events = calendarNativeEvents(native, range, this.language, this.effectiveObserverContext())
        const nonSat = this.store.events.filter((ev: AstronomyCalendarEvent) => ev.kind !== 'satellite-pass' && ev.isRemote !== true).concat(events)
        this.store.events = this.mergeEventsWithSatellites(nonSat)
        this.hooks.feedChanged(this.store.events.slice())
      }
      this.store.loadingMore = false
      if (onDone !== undefined) onDone()
    }

    const cacheKey = this.cacheKeyFor(year, month, planet)
    const cached = AstronomyCalendarCache.getInstance().get(cacheKey)
    if (cached !== undefined) {
      try {
        appendNative(cached)
        return
      } catch (_) {}
    }

    this.store.loadingMore = true
    this.store.error = ''
    const fail = (): void => {
      if (this.disposed || sequence !== this.sequence) return
      this.store.loadingMore = false
      this.store.error = calendarText(this.language, '后续天象读取失败，已载入的内容仍可查看。', 'Could not load more events. Your loaded events are still available.')
    }
    try {
      this.port.requestLongRunning('getAstronomyCalendarEvents', JSON.stringify(calendarQuery(range, planet)), (response: StellariumBridgeResponse): void => {
        if (this.disposed || sequence !== this.sequence) return
        try {
          const native = response as CalendarNativeResponse
          AstronomyCalendarCache.getInstance().put(cacheKey, native)
          appendNative(native)
        } catch (_) { fail() }
      }, fail, undefined, 240, (): boolean => this.disposed || sequence !== this.sequence)
    } catch (_) { fail() }
  }

  setLanguage(language: string): void {
    if (this.disposed) return
    this.language = language
    this.store.actionMessage = ''
    if (this.store.error !== '') this.store.error = calendarText(language,
      '本地天象数据读取失败，请重试。', 'Could not load local events. Please retry.')
    if (this.response !== undefined) {
      try {
        const range = calendarMonth(this.store.year, this.store.month)
        const ctx = this.effectiveObserverContext()
        let rebuilt = calendarNativeEvents(this.response, range, language, ctx)
        for (const response of this.extraResponses) {
          rebuilt = rebuilt.concat(calendarNativeEvents(response,
            calendarMonth(response.year as number, response.month as number), language, ctx))
        }
        this.store.events = this.mergeEventsWithSatellites(rebuilt)
        this.recomputeMonthDays()
        this.updateCoverage()
        this.hooks.feedChanged(this.store.events.slice())
      } catch (_) {
        this.reload()
      }
    }
  }

  setRegionId(regionId: string): void {
    if (this.disposed) return
    const safe = normalizeObserverRegionId(regionId)
    if (this.store.regionId === safe) return
    this.store.regionId = safe
    this.store.filterRevision += 1
    if (this.response !== undefined) {
      this.setLanguage(this.language)
    }
    this.hooks.onFilterChanged?.()
  }

  setSearchQuery(query: string): void {
    if (this.disposed || this.store.searchQuery === query) return
    this.store.searchQuery = query
    this.store.selectedDay = 0
    this.store.filterRevision += 1
    this.recomputeMonthDays()
  }

  applyQuickPreset(presetId: string): void {
    if (this.disposed) return
    const preset = CALENDAR_QUICK_PRESETS.find((p) => p.id === presetId)
    if (preset === undefined) return
    this.store.selectedCategories = preset.categories.slice()
    this.store.satelliteSubFilter = preset.satelliteSubFilter
    this.store.highlightOnly = preset.highlightOnly
    this.store.selectedDay = 0
    this.store.filterRevision += 1
    this.recomputeMonthDays()
    this.hooks.onFilterChanged?.()
  }

  clearFilters(): void {
    if (this.disposed) return
    this.store.selectedCategories = []
    this.store.satelliteSubFilter = 'all'
    this.store.highlightOnly = false
    this.store.searchQuery = ''
    this.store.selectedDay = 0
    this.store.filterRevision += 1
    this.recomputeMonthDays()
    this.hooks.onFilterChanged?.()
  }

  toggleCategory(category: string): void {
    if (this.disposed) return
    const next = this.store.selectedCategories.slice()
    const idx = next.indexOf(category)
    if (idx >= 0) next.splice(idx, 1)
    else next.push(category)
    this.store.selectedCategories = next
    this.store.selectedDay = 0
    this.store.filterRevision += 1
    this.recomputeMonthDays()
    this.hooks.onFilterChanged?.()
  }

  setSatelliteSubFilter(mode: string): void {
    if (this.disposed) return
    const safe = (mode === 'stations' || mode === 'visible' || mode === 'high_alt') ? mode : 'all'
    if (this.store.satelliteSubFilter === safe) return
    this.store.satelliteSubFilter = safe
    this.store.selectedDay = 0
    this.store.filterRevision += 1
    this.recomputeMonthDays()
    this.hooks.onFilterChanged?.()
  }

  setHighlightOnly(enabled: boolean): void {
    if (this.disposed || this.store.highlightOnly === enabled) return
    this.store.highlightOnly = enabled
    this.store.selectedDay = 0
    this.store.filterRevision += 1
    this.recomputeMonthDays()
    this.hooks.onFilterChanged?.()
  }

  goToCurrentMonth(): void {
    const now = new Date()
    this.loadMonth(now.getFullYear(), now.getMonth() + 1)
  }

  reload(): void {
    this.loadMonth(this.store.year, this.store.month)
  }

  previousMonth(): void {
    if (this.store.year === 1 && this.store.month === 1) return
    this.loadMonth(this.store.month === 1 ? this.store.year - 1 : this.store.year,
      this.store.month === 1 ? 12 : this.store.month - 1)
  }

  nextMonth(): void {
    if (this.store.year === 3000 && this.store.month === 12) return
    this.loadMonth(this.store.month === 12 ? this.store.year + 1 : this.store.year,
      this.store.month === 12 ? 1 : this.store.month + 1)
  }

  selectDay(day: number): void {
    if (this.disposed || !Number.isInteger(day) || day < 1 || day > calendarMonth(this.store.year, this.store.month).days) return
    this.store.selectedDay = day
    this.store.selectedEventId = ''
    this.store.actionMessage = ''
  }

  showMonthEvents(): void {
    if (this.disposed) return
    this.store.selectedDay = 0
    this.store.selectedEventId = ''
    this.store.actionMessage = ''
  }

  selectEvent(id: string): void {
    if (this.disposed || !this.store.events.some((event: AstronomyCalendarEvent) => event.id === id)) return
    this.store.selectedEventId = id
    this.store.actionMessage = ''
  }

  viewSky(id: string): void {
    const event = this.store.events.find((item: AstronomyCalendarEvent) => item.id === id)
    if (!this.disposed && event !== undefined) this.hooks.viewSky(event)
  }

  async remind(id: string): Promise<AstronomyCalendarReminderResult> {
    const event = this.store.events.find((item: AstronomyCalendarEvent) => item.id === id)
    if (this.disposed) return { ok: false, reason: 'disposed', error: calendarText(this.language,
      '日历已关闭，请重新打开后重试。', 'Calendar is closed. Reopen it and retry.') }
    if (event === undefined) return { ok: false, reason: 'unknown-event', error: calendarText(this.language,
      '未找到该天象事件。', 'Calendar event was not found.') }
    if (this.store.reminderPendingId !== '') return { ok: false, reason: 'busy', error: calendarText(this.language,
      '正在处理提醒，请稍后重试。', 'A reminder is being processed. Please retry shortly.') }
    if (event.at <= Date.now()) {
      this.store.actionMessage = calendarText(this.language, '该事件已发生，无法设置未来提醒。', 'This event is in the past and cannot be scheduled.')
      return { ok: false, reason: 'past-event', error: this.store.actionMessage }
    }
    const sequence = this.sequence
    this.store.reminderPendingId = id
    this.store.actionMessage = ''
    try {
      const result = await this.hooks.remind(event)
      const message = result.ok ? (result.message ?? calendarText(this.language, '提醒已交给系统管理。', 'Reminder scheduled.'))
        : (result.message ?? result.error ?? calendarText(this.language, '提醒添加失败。', 'Reminder could not be scheduled.'))
      if (!this.disposed && sequence === this.sequence && this.store.selectedEventId === id) this.store.actionMessage = message
      return result
    } catch (_) {
      const message = calendarText(this.language,
        '提醒未设置成功，请检查通知设置后重试。', 'Reminder was not scheduled. Check notification settings and retry.')
      if (!this.disposed && sequence === this.sequence && this.store.selectedEventId === id) this.store.actionMessage = message
      return { ok: false, reason: 'scheduling-error', error: message }
    } finally {
      if (!this.disposed) this.store.reminderPendingId = ''
    }
  }

  dispose(): void {
    this.disposed = true
    this.sequence++
    this.store.loading = false
    this.store.loadingMore = false
    this.store.satellitePassesLoading = false
    this.store.reminderPendingId = ''
  }
}
