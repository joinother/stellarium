import { CommandPort } from '../bridge/CommandPort'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { AstronomyCalendarStore } from '../state/AstronomyCalendarStore'
import { AstronomyCalendarEvent, CalendarNativeResponse, calendarMonth, calendarDays, calendarQuery, calendarNativeEvents } from '../state/AstronomyCalendarEvent'
import { calendarText } from '../state/AstronomyCalendarText'
import { AstronomyReminderResult } from '../qability/AstronomyReminderService'

export interface AstronomyCalendarReminderResult extends AstronomyReminderResult {
  message?: string
}

export interface AstronomyCalendarHostHooks {
  viewSky(event: AstronomyCalendarEvent): void
  remind(event: AstronomyCalendarEvent): Promise<AstronomyCalendarReminderResult>
  feedChanged(events: AstronomyCalendarEvent[]): void
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

  constructor(port: CommandPort, store: AstronomyCalendarStore, hooks: AstronomyCalendarHostHooks) {
    this.port = port
    this.store = store
    this.hooks = hooks
  }

  loadMonth(year: number, month: number): void {
    if (this.disposed) return
    const range = calendarMonth(year, month)
    const sequence = ++this.sequence
    this.store.year = year
    this.store.month = month
    this.store.throughYear = year
    this.store.throughMonth = month
    this.store.loadingMore = false
    this.extraResponses = []
    this.store.selectedDay = 0
    this.store.selectedEventId = ''
    this.store.events = []
    this.store.days = calendarDays(range, [])
    this.store.error = ''
    this.store.coverage = ''
    this.store.actionMessage = ''
    this.store.sourceYear = 0
    this.store.loading = true
    this.store.loaded = false
    this.response = undefined
    this.hooks.feedChanged([])
    const fail = (): void => {
      if (this.disposed || sequence !== this.sequence) return
      this.store.loading = false
      this.store.error = calendarText(this.language, '本地天象数据读取失败，请重试。', 'Could not load local events. Please retry.')
    }
    try {
      this.port.requestLongRunning('getAstronomyCalendarEvents', JSON.stringify(calendarQuery(range)), (response: StellariumBridgeResponse): void => {
        if (this.disposed || sequence !== this.sequence) return
        try {
          const native = response as CalendarNativeResponse
          const events = calendarNativeEvents(native, range, this.language)
          this.response = native
          this.store.sourceYear = year
          this.store.events = events
          this.store.days = calendarDays(range, events)
          this.store.loading = false
          this.store.loaded = true
          this.updateCoverage()
          this.hooks.feedChanged(events.slice())
        } catch (_) {
          fail()
        }
      }, fail, undefined, 240, (): boolean => this.disposed || sequence !== this.sequence)
    } catch (_) {
      fail()
    }
  }

  private updateCoverage(): void {
    this.store.coverage = calendarText(this.language, '已载入节气、主要月相、流星雨预计极大及行星事件；按设备时区显示。',
      'Solar terms, principal lunar phases, estimated meteor peaks and planetary events loaded; times use the device time zone.')
  }

  loadMore(): void {
    if (this.disposed || this.store.loading || this.store.loadingMore || !this.store.loaded ||
      (this.store.throughYear === 3000 && this.store.throughMonth === 12)) return
    const year = this.store.throughMonth === 12 ? this.store.throughYear + 1 : this.store.throughYear
    const month = this.store.throughMonth === 12 ? 1 : this.store.throughMonth + 1
    const range = calendarMonth(year, month)
    const sequence = this.sequence
    this.store.loadingMore = true
    this.store.error = ''
    const fail = (): void => {
      if (this.disposed || sequence !== this.sequence) return
      this.store.loadingMore = false
      this.store.error = calendarText(this.language, '后续天象读取失败，已载入的内容仍可查看。', 'Could not load more events. Your loaded events are still available.')
    }
    try {
      this.port.requestLongRunning('getAstronomyCalendarEvents', JSON.stringify(calendarQuery(range)), (response: StellariumBridgeResponse): void => {
        if (this.disposed || sequence !== this.sequence) return
        try {
          const native = response as CalendarNativeResponse
          const events = calendarNativeEvents(native, range, this.language)
          this.extraResponses.push(native)
          this.store.events = this.store.events.concat(events)
          this.store.throughYear = year
          this.store.throughMonth = month
          this.store.loadingMore = false
          this.hooks.feedChanged(this.store.events.slice())
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
        this.store.events = calendarNativeEvents(this.response, range, language)
        for (const response of this.extraResponses) {
          this.store.events = this.store.events.concat(calendarNativeEvents(response,
            calendarMonth(response.year as number, response.month as number), language))
        }
        this.updateCoverage()
        this.hooks.feedChanged(this.store.events.slice())
      } catch (_) {
        this.reload()
      }
    }
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
    this.store.reminderPendingId = ''
  }
}
