import { notificationText } from './NotificationText'
import { common } from '@kit.AbilityKit'
import preferences from '@ohos.data.preferences'
import { AstronomyNotificationService } from '../qability/AstronomyNotificationService'
import { AstronomyReminderService, AstronomyReminderRequest, AstronomyReminderResult } from '../qability/AstronomyReminderService'
import { AstronomyQuietHours, AstronomyReminderPreferences, NotificationPreferenceSnapshot, validNotificationPreferences, validServiceId } from '../qability/AstronomyNotificationPolicy'
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent'
import { NotificationStore } from '../state/NotificationStore'
import { AstronomyCalendarEvent } from '../state/AstronomyCalendarEvent'
import { AstronomyCalendarReminderResult } from './AstronomyCalendarController'
import { AstronomySubscriptionCategory, AstronomySubscriptionFeed, subscriptionCandidates } from '../qability/AstronomySubscriptionPolicy'
import { MoonPhaseItem, SeasonEvent } from '../common/types/StellariumTypes'
import { MeteorShowerItem } from '../common/types/MainWindowModels'

export interface NotificationHostHooks {
  loadSubscriptionEvents?(category: AstronomySubscriptionCategory, from: number, until: number): Promise<AstronomySubscriptionFeed>
  canInteract?(): boolean
  openCalendar?(): void
  flashHint(text: ResourceStr): void
  hostContext(): common.UIAbilityContext
  almanacSolarTerms(): SeasonEvent[]
  loadAlmanac(): void
  moonPhases(): MoonPhaseItem[]
  loadMoonPhases(): void
  meteorShowers(): MeteorShowerItem[]
  loadMeteorShowers(): void
}

export class NotificationController {
  private store: NotificationStore
  private hooks: NotificationHostHooks
  private preferenceQueue: Promise<void> = Promise.resolve()
  private preferenceLoad: Promise<void> | undefined = undefined
  private preferenceWrites: number = 0
  private savedPreferences: NotificationPreferenceSnapshot | undefined = undefined
  private subscriptionRun: Promise<void> | undefined = undefined
  private subscriptionRevision: number = 0
  private subscriptionRequested: boolean = false

  private canInteract(): boolean {
    try { return this.hooks.canInteract?.() ?? true } catch (error) { return false }
  }

  constructor(store: NotificationStore, hooks: NotificationHostHooks) {
    this.store = store
    this.hooks = hooks
    AstronomyReminderService.configure(hooks.hostContext())
    this.savedPreferences = this.snapshot()
  }

  private snapshot(): NotificationPreferenceSnapshot {
    return {
      astronomyEventsEnabled: this.store.astronomyEventsEnabled, dndEnabled: this.store.dndEnabled,
      satellitePassEnabled: this.store.satellitePassEnabled, digestEnabled: this.store.digestEnabled,
      subscriptionsVersion: 1,
      dndStartMinutes: this.store.dndStartMinutes, dndEndMinutes: this.store.dndEndMinutes,
      passLeadMinutes: this.store.passLeadMinutes
    }
  }

  private applyPreferences(value: NotificationPreferenceSnapshot): void {
    this.store.astronomyEventsEnabled = value.astronomyEventsEnabled
    this.store.satellitePassEnabled = value.satellitePassEnabled === true
    this.store.digestEnabled = value.digestEnabled === true
    this.store.dndEnabled = value.dndEnabled
    this.store.dndStartMinutes = value.dndStartMinutes
    this.store.dndEndMinutes = value.dndEndMinutes
    this.store.passLeadMinutes = value.passLeadMinutes
  }

  public loadPreferences(): Promise<void> {
    if (this.preferenceLoad !== undefined) return this.preferenceLoad
    this.preferenceLoad = this.readPreferences().finally(() => { this.preferenceLoad = undefined })
    return this.preferenceLoad
  }

  private async readPreferences(): Promise<void> {
    if (this.store.notificationPreferencesLoaded) return
    try {
      const settings = await preferences.getPreferences(this.hooks.hostContext(), { name: 'stellarium_astronomy_reminders' })
      const stored = await settings.get('manual_preferences_v1', '')
      let value = this.savedPreferences ?? this.snapshot()
      if (typeof stored === 'string' && stored.length > 0) {
        const parsed: NotificationPreferenceSnapshot = JSON.parse(stored) as NotificationPreferenceSnapshot
        if (!validNotificationPreferences(parsed)) throw new Error('invalid notification preferences')
        value = parsed
        if (value.subscriptionsVersion !== 1) {
          value.astronomyEventsEnabled = false
          value.satellitePassEnabled = false
          value.digestEnabled = false
        }
      }
      this.savedPreferences = value
      if (this.preferenceWrites === 0) this.applyPreferences(value)
      this.store.notificationPreferencesLoaded = true
      this.store.notificationPreferencesError = ''
    } catch (error) {
      this.store.notificationPreferencesError = notificationText('提醒偏好读取失败，请重试后再添加提醒。')
    }
  }

  public persistPreferences(reconcile: boolean = true): void {
    this.subscriptionRevision += 1
    const value = this.snapshot()
    if (!validNotificationPreferences(value)) {
      this.store.notificationPreferencesError = notificationText('静默时段或提前量无效。')
      if (this.savedPreferences !== undefined) this.applyPreferences(this.savedPreferences)
      return
    }
    this.preferenceWrites += 1
    this.store.notificationPreferencesBusy = true
    this.preferenceQueue = this.preferenceQueue.then(async (): Promise<void> => {
      await this.loadPreferences()
      if (!this.store.notificationPreferencesLoaded) return
      const previous = this.savedPreferences ?? value
      let settings: preferences.Preferences | undefined = undefined
      try {
        settings = await preferences.getPreferences(this.hooks.hostContext(), { name: 'stellarium_astronomy_reminders' })
        await settings.put('manual_preferences_v1', JSON.stringify(value))
        await settings.flush()
        this.savedPreferences = value
        this.store.notificationPreferencesError = ''
      } catch (error) {
        if (settings !== undefined) {
          try { await settings.put('manual_preferences_v1', JSON.stringify(previous)) } catch (rollbackError) {}
        }
        if (this.preferenceWrites === 1) this.applyPreferences(previous)
        this.store.notificationPreferencesError = notificationText('提醒偏好保存失败，未确认的更改已撤回。')
        this.report(this.store.notificationPreferencesError)
      }
    }).catch(() => {
      this.store.notificationPreferencesError = notificationText('提醒偏好保存失败。')
    }).finally(() => {
      this.preferenceWrites -= 1
      this.store.notificationPreferencesBusy = this.preferenceWrites > 0
      if (reconcile && this.preferenceWrites === 0 && this.hooks.loadSubscriptionEvents !== undefined) {
        void this.refreshSubscriptions()
      }
    })
  }

  setAstronomyEventsEnabled(enabled: boolean): void {
    this.store.astronomyEventsEnabled = enabled
    this.persistPreferences()
  }

  setSatellitePassEnabled(enabled: boolean): void {
    this.store.satellitePassEnabled = enabled
    this.persistPreferences()
  }

  public refreshSubscriptions(): Promise<void> {
    this.subscriptionRevision += 1
    this.subscriptionRequested = true
    if (this.subscriptionRun !== undefined) return this.subscriptionRun
    this.subscriptionRun = this.drainSubscriptions().catch(() => {
      this.report(notificationText('订阅更新失败，已有提醒可能仍有效，请重试。'))
    }).finally(() => {
      this.subscriptionRun = undefined
      this.resumePendingSubscriptions()
    })
    return this.subscriptionRun
  }

  private resumePendingSubscriptions(): void {
    if (this.subscriptionRequested && this.subscriptionRun === undefined && !this.store.astronomyNotificationBusy &&
      this.store.notificationPreferencesLoaded && !this.store.notificationPreferencesError && this.canInteract()) {
      void this.refreshSubscriptions()
    }
  }

  public async changeSubscription(category: AstronomySubscriptionCategory, enabled: boolean): Promise<AstronomyReminderResult> {
    if (!this.canInteract() || this.store.astronomyNotificationBusy || this.store.notificationPreferencesBusy) {
      return { ok: false, reason: 'busy', error: notificationText('正在处理提醒，请稍后重试。') }
    }
    await this.loadPreferences()
    if (!this.store.notificationPreferencesLoaded || this.store.notificationPreferencesError) {
      return { ok: false, reason: 'preferences-unavailable', error: this.store.notificationPreferencesError }
    }
    this.store.astronomySubscriptionOk = false
    this.store.satelliteSubscriptionOk = false
    if (category === 'astronomy') this.setAstronomyEventsEnabled(enabled)
    else this.setSatellitePassEnabled(enabled)
    await this.refreshSubscriptions()
    await this.preferenceQueue
    const actual = category === 'astronomy' ? this.store.astronomyEventsEnabled : this.store.satellitePassEnabled
    const confirmed = category === 'astronomy' ? this.store.astronomySubscriptionOk : this.store.satelliteSubscriptionOk
    const message = category === 'astronomy' ? this.store.astronomySubscriptionStatus : this.store.satelliteSubscriptionStatus
    if (!confirmed || actual !== enabled || this.store.notificationPreferencesError) return {
      ok: false, reason: actual !== enabled ? 'subscription-rolled-back' : 'subscription-update-failed',
      error: this.store.notificationPreferencesError || message || this.store.astronomyNotificationStatus
    }
    return { ok: true }
  }

  private async drainSubscriptions(): Promise<void> {
    while (this.subscriptionRequested) {
      await this.preferenceQueue
      await this.loadPreferences()
      if (!this.canInteract() || !this.store.notificationPreferencesLoaded ||
        this.store.notificationPreferencesError || this.store.astronomyNotificationBusy) return
      this.subscriptionRequested = false
      this.store.astronomyNotificationBusy = true
      this.store.subscriptionBusy = true
      try { await this.reconcileSubscriptions(this.subscriptionRevision) } finally {
        this.store.subscriptionBusy = false
        this.store.astronomyNotificationBusy = false
      }
    }
  }

  private subscriptionStatus(category: AstronomySubscriptionCategory, message: string, ok: boolean = false): void {
    if (category === 'astronomy') this.store.astronomySubscriptionOk = ok
    else this.store.satelliteSubscriptionOk = ok
    if (category === 'astronomy') this.store.astronomySubscriptionStatus = notificationText(message)
    else this.store.satelliteSubscriptionStatus = notificationText(message)
    this.store.astronomyNotificationStatus = notificationText(message)
  }

  private async reconcileSubscriptions(revision: number): Promise<void> {
    this.store.astronomySubscriptionOk = false
    this.store.satelliteSubscriptionOk = false
    const current = (): boolean => revision === this.subscriptionRevision && this.canInteract()
    const snapshot = this.snapshot()
    const listed = await AstronomyReminderService.list()
    if (!listed.ok || listed.items === undefined) {
      this.report(listed.error ?? notificationText('提醒列表读取失败。'))
      return
    }
    if (!current()) return
    const items = listed.items
    const status = await AstronomyNotificationService.status()
    if (!current()) return
    if (status.notificationEnabled !== undefined) this.store.astronomyNotificationEnabled = status.notificationEnabled
    const categories: AstronomySubscriptionCategory[] = ['astronomy', 'satellite']
    let lastError = ''
    for (const category of categories) {
      if (!current()) return
      const enabled = category === 'astronomy' ? snapshot.astronomyEventsEnabled : snapshot.satellitePassEnabled === true
      const owned = items.filter((item) => item.subscription === category)
      if (!enabled) {
        for (const item of owned) {
          if (!current()) return
          const result = await AstronomyReminderService.cancelOwned(item)
          if (!result.ok) { this.subscriptionStatus(category, result.error ?? '订阅更新失败，已有提醒可能仍有效，请重试。'); return }
        }
        this.subscriptionStatus(category, '订阅已关闭。', true)
        continue
      }
      if (!status.ok || status.notificationEnabled !== true) {
        lastError = status.error ?? '请先开启系统通知，再启用订阅。'
        this.subscriptionStatus(category, status.error ?? '请先开启系统通知，再启用订阅。')
        if (category === 'astronomy') this.store.astronomyEventsEnabled = false
        else this.store.satellitePassEnabled = false
        continue
      }
      if (!hasCurrentPrivacyConsent()) {
        lastError = '请先同意当前隐私协议。'
        this.subscriptionStatus(category, lastError)
        continue
      }
      let candidates: AstronomyCalendarEvent[]
      try {
        if (this.hooks.loadSubscriptionEvents === undefined) throw new Error('missing subscription feed')
        const now = Date.now()
        const until = now + (category === 'satellite' ? 2 : 45) * 86400000
        const feed = await this.hooks.loadSubscriptionEvents(category, now, until)
        if (!current()) return
        candidates = subscriptionCandidates(feed, category, snapshot, Date.now(), until)
      } catch (error) {
        if (!current()) return
        if (category === 'satellite') {
          this.store.satellitePassEnabled = false
          lastError = '卫星订阅暂不可用，已关闭。'
          for (const item of owned) {
            if (!current()) return
            const cancelled = await AstronomyReminderService.cancelOwned(item)
            if (!current()) return
            if (!cancelled.ok) lastError = '卫星订阅已关闭，但已有提醒未能全部取消，请重试。'
          }
          this.subscriptionStatus(category, lastError)
          continue
        }
        lastError = '订阅数据不可用，请检查观测地点与本地数据。'
        this.subscriptionStatus(category, '订阅数据不可用，请检查观测地点与本地数据。')
        if (owned.length === 0) {
          if (category === 'astronomy') this.store.astronomyEventsEnabled = false
          else this.store.satellitePassEnabled = false
        }
        continue
      }
      for (const item of owned) {
        if (!current()) return
        const stillWanted = candidates.some((event: AstronomyCalendarEvent) => item.eventId === event.id &&
          item.kind === event.kind && item.eventAt !== undefined && Math.abs(Date.parse(item.eventAt) - event.at) < 1000)
        if (!stillWanted) {
          const result = await AstronomyReminderService.cancelOwned(item)
          if (!result.ok) { this.subscriptionStatus(category, result.error ?? '订阅更新失败，已有提醒可能仍有效，请重试。'); return }
        }
      }
      let failure = false
      let scheduled = 0
      for (const event of candidates) {
        if (!current()) return
        const payload: AstronomyReminderRequest = {
          subscription: category, eventAt: new Date(event.at).toISOString(), jd: event.jd,
          title: notificationText('星象仪 · ') + event.title, content: event.title + notificationText(' 即将到来，打开星象仪查看事件与观测信息。'),
          eventId: event.id, kind: event.kind, target: event.target,
          panel: category === 'astronomy' ? 'calendar' : event.panel, tab: event.tab,
          leadMinutes: category === 'satellite' ? snapshot.passLeadMinutes : 0
        }
        const result = await AstronomyReminderService.schedule(payload, this.hooks.hostContext().abilityInfo.bundleName,
          this.reminderPreferences(), current, 24)
        if (!current()) return
        if (!result.ok) {
          lastError = result.error ?? '订阅更新失败，已有提醒可能仍有效，请重试。'
          this.subscriptionStatus(category, result.error ?? '订阅更新失败，已有提醒可能仍有效，请重试。')
          if (owned.length === 0 && scheduled === 0 && result.reminderId === undefined) {
            if (category === 'astronomy') this.store.astronomyEventsEnabled = false
            else this.store.satellitePassEnabled = false
          }
          failure = true
          if (result.code === 1700002 || result.reason === 'permission-denied' || result.reason === 'notification-disabled') {
            const active = await AstronomyReminderService.list()
            if (!current()) return
            if (active.ok && active.items !== undefined) {
              if (!active.items.some((item) => item.subscription === 'astronomy')) this.store.astronomyEventsEnabled = false
              if (!active.items.some((item) => item.subscription === 'satellite')) this.store.satellitePassEnabled = false
            }
            this.persistPreferences(false)
            await this.refreshReminders()
            return
          }
          break
        }
        scheduled += 1
      }
      if (!failure) this.subscriptionStatus(category, candidates.length > 0 ? '订阅已更新，提醒由系统管理。' : '订阅已开启，当前时段暂无符合偏好的事件。', true)
    }
    if (snapshot.astronomyEventsEnabled !== this.store.astronomyEventsEnabled || snapshot.satellitePassEnabled !== this.store.satellitePassEnabled) {
      this.persistPreferences(false)
    }
    await this.refreshReminders()
    if (lastError.length > 0) this.store.astronomyNotificationStatus = notificationText(lastError)
  }

  setDndEnabled(enabled: boolean): void { this.store.dndEnabled = enabled; this.persistPreferences() }

  public async setQuietHours(value: AstronomyQuietHours): Promise<AstronomyReminderResult> {
    if (value === null || typeof value !== 'object' || Array.isArray(value) || typeof value.enabled !== 'boolean' ||
      !Number.isInteger(value.startMinutes) || value.startMinutes < 0 || value.startMinutes > 1439 ||
      !Number.isInteger(value.endMinutes) || value.endMinutes < 0 || value.endMinutes > 1439) return {
      ok: false, reason: 'validation', error: notificationText('静默时段或提前量无效。')
    }
    try {
      await this.loadPreferences()
      if (!this.canInteract() || this.store.astronomyNotificationBusy || this.store.notificationPreferencesBusy) return {
        ok: false, reason: 'busy', error: notificationText('正在处理提醒，请稍后重试。')
      }
      if (!this.store.notificationPreferencesLoaded || this.store.notificationPreferencesError) return {
        ok: false, reason: 'preferences-unavailable', error: this.store.notificationPreferencesError
      }
      this.store.dndEnabled = value.enabled
      this.store.dndStartMinutes = value.startMinutes
      this.store.dndEndMinutes = value.endMinutes
      this.persistPreferences(false)
      await this.preferenceQueue
      const saved = this.savedPreferences
      if (this.store.notificationPreferencesError || saved?.dndEnabled !== value.enabled ||
        saved.dndStartMinutes !== value.startMinutes || saved.dndEndMinutes !== value.endMinutes) return {
        ok: false, reason: 'preferences-update-failed', error: this.store.notificationPreferencesError || notificationText('提醒偏好保存失败。')
      }
      if (this.canInteract()) void this.refreshSubscriptions()
      return { ok: true }
    } catch (_) {
      return { ok: false, reason: 'preferences-update-failed', error: notificationText('提醒偏好保存失败。') }
    }
  }

  setDndStartMinutes(minutes: number): void { this.store.dndStartMinutes = minutes; this.persistPreferences() }
  setDndEndMinutes(minutes: number): void { this.store.dndEndMinutes = minutes; this.persistPreferences() }
  changeLeadMinutes(delta: number): void {
    this.store.passLeadMinutes = Math.min(60, Math.max(0, this.store.passLeadMinutes + delta))
    this.persistPreferences()
  }

  private reminderPreferences(): AstronomyReminderPreferences {
    return {
      astronomyEventsEnabled: this.store.astronomyEventsEnabled,
      satellitePassEnabled: this.store.satellitePassEnabled, digestEnabled: this.store.digestEnabled,
      dndEnabled: this.store.dndEnabled, dndStartMinutes: this.store.dndStartMinutes, dndEndMinutes: this.store.dndEndMinutes
    }
  }

  private async refreshReminders(): Promise<void> {
    const result = await AstronomyReminderService.list()
    if (result.ok && result.items !== undefined) {
      this.store.astronomyReminders = result.items
      this.store.astronomyReminderCount = result.items.length
      this.store.astronomyReminderListLoaded = true
      this.store.astronomyReminderListError = ''
    } else {
      this.store.astronomyReminderListError = notificationText(result.error ?? '提醒列表读取失败。')
    }
  }

  async refreshStatus(): Promise<void> {
    if (this.store.astronomyNotificationBusy) return
    this.store.astronomyNotificationBusy = true
    try {
      await this.loadPreferences()
      const status = await AstronomyNotificationService.status()
      if (status.notificationEnabled !== undefined) this.store.astronomyNotificationEnabled = status.notificationEnabled
      await this.refreshReminders()
      this.store.astronomyNotificationStatus = !status.ok ? notificationText(status.error ?? '通知状态暂时不可用') :
        this.store.astronomyReminderListError || (status.notificationEnabled ? notificationText('通知已开启') : notificationText('通知未授权'))
    } catch (error) {
      this.store.astronomyNotificationStatus = notificationText('通知状态暂时不可用')
    } finally {
      this.store.astronomyNotificationBusy = false
      this.resumePendingSubscriptions()
    }
  }

  async requestAccess(): Promise<void> {
    if (this.store.astronomyNotificationBusy) return
    if (!this.canInteract()) { this.report(notificationText('请回到前台后开启通知。')); return }
    this.store.astronomyNotificationBusy = true
    try {
      const enabled = await AstronomyNotificationService.requestAuthorization(this.hooks.hostContext())
      this.store.astronomyNotificationEnabled = enabled
      this.store.astronomyNotificationStatus = enabled ? notificationText('通知已开启') : notificationText('通知授权未完成')
      await this.refreshReminders()
    } catch (error) {
      this.report(notificationText('通知授权未完成'))
    } finally {
      this.store.astronomyNotificationBusy = false
      this.resumePendingSubscriptions()
    }
  }

  private async scheduleOne(payload: AstronomyReminderRequest, eventLead: boolean = false): Promise<AstronomyCalendarReminderResult> {
    if (this.store.astronomyNotificationBusy) return {
      ok: false, reason: 'busy', error: notificationText('正在处理提醒，请稍后重试。')
    }
    this.store.astronomyNotificationBusy = true
    try {
      await this.preferenceQueue
      await this.loadPreferences()
      if (!this.canInteract()) return this.reportReminderResult({
        ok: false, reason: 'interaction-unavailable', error: notificationText('请回到前台后重新添加提醒。')
      })
      if (!this.store.notificationPreferencesLoaded || this.store.notificationPreferencesError.length > 0) {
        return this.reportReminderResult({ ok: false, reason: 'preferences-unavailable',
          error: this.store.notificationPreferencesError || notificationText('提醒偏好尚未就绪。') })
      }
      if (!hasCurrentPrivacyConsent()) return this.reportReminderResult({
        ok: false, reason: 'privacy-required', error: notificationText('请先同意当前隐私协议。')
      })
      if (eventLead) payload.leadMinutes = this.store.passLeadMinutes
      const result = await AstronomyReminderService.schedule(payload, this.hooks.hostContext().abilityInfo.bundleName,
        this.reminderPreferences(), (): boolean => this.canInteract())
      try {
        await this.refreshReminders()
      } catch (error) {
        this.store.astronomyReminderListError = notificationText('提醒列表读取失败。')
      }
      return this.reportReminderResult(result)
    } catch (error) {
      return this.reportReminderResult({ ok: false, reason: 'scheduling-error',
        error: notificationText('提醒添加失败，请刷新列表后重试。') })
    } finally {
      this.store.astronomyNotificationBusy = false
      this.resumePendingSubscriptions()
    }
  }

  private reportReminderResult(result: AstronomyCalendarReminderResult): AstronomyCalendarReminderResult {
    result.message = this.report(result.ok
      ? (result.unchanged ? notificationText('此事件已添加提醒。') : notificationText('提醒已交给系统管理。'))
      : (result.error ?? notificationText('提醒添加失败。')))
    return result
  }

  private report(message: string): string {
    const localized = notificationText(message)
    this.store.astronomyNotificationStatus = localized
    try { this.hooks.flashHint(localized) } catch (error) {}
    return localized
  }

  async scheduleEvent(event: AstronomyCalendarEvent): Promise<AstronomyCalendarReminderResult> {
    if (event === undefined || event === null || typeof event.id !== 'string' || event.id.trim().length === 0 ||
      typeof event.title !== 'string' || event.title.trim().length === 0 ||
      typeof event.at !== 'number' || !Number.isFinite(event.at) || !Number.isFinite(new Date(event.at).getTime())) {
      return this.reportReminderResult({ ok: false, reason: 'validation', error: notificationText('天象事件数据无效。') })
    }
    return this.scheduleOne({
      eventAt: new Date(event.at).toISOString(), title: notificationText('星象仪 · ') + event.title,
      content: event.title + notificationText(' 即将到来，打开星象仪查看事件与观测信息。'),
      eventId: event.id, kind: event.kind, jd: event.jd, target: event.target, panel: 'calendar', tab: event.tab
    }, true)
  }

  private openCalendarPicker(): void {
    if (!this.canInteract()) {
      this.report(notificationText('请回到前台后选择天象事件。'))
      return
    }
    try {
      if (this.hooks.openCalendar !== undefined) this.hooks.openCalendar()
      else this.report(notificationText('请打开天象日历，选择未来事件后添加提醒。'))
    } catch (error) {
      this.report(notificationText('请打开天象日历，选择未来事件后添加提醒。'))
    }
  }

  scheduleNextSolarTerm(): void { this.openCalendarPicker() }
  scheduleNextMoonPhase(): void { this.openCalendarPicker() }
  scheduleNextMeteorShower(): void { this.openCalendarPicker() }

  scheduleCountdown(minutes: number): void {
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 35791394) { this.report(notificationText('倒计时分钟数无效。')); return }
    this.scheduleOne({
      title: notificationText('星象仪 · 观测倒计时'), content: minutes + notificationText(' 分钟后提醒你回到观测。'),
      eventId: 'countdown-' + minutes, kind: 'countdown', panel: 'astro', tab: 0,
      reminderType: 'timer', triggerSeconds: minutes * 60
    })
  }

  scheduleAtDateTime(timestamp: number): void {
    if (!Number.isFinite(timestamp) || timestamp <= Date.now() + 30000 || !Number.isFinite(new Date(timestamp).getTime())) {
      this.report(notificationText('请选择至少 30 秒后的日期与时间。'))
      return
    }
    this.scheduleOne({
      at: new Date(timestamp).toISOString(), title: notificationText('星象仪 · 观测提醒'), content: notificationText('观测计划时间已到，打开星象仪开始。'),
      eventId: 'calendar-' + timestamp, kind: 'calendar', panel: 'astro', tab: 0, reminderType: 'calendar'
    })
  }

  scheduleDailyAlarm(hour: number, minute: number): void {
    this.scheduleOne({
      title: notificationText('星象仪 · 每日观星提醒'), content: notificationText('每天的观星时间到了，打开星象仪继续观测。'),
      eventId: 'alarm-daily', kind: 'alarm', panel: 'astro', tab: 0,
      reminderType: 'alarm', hour: hour, minute: minute, daysOfWeek: [1, 2, 3, 4, 5, 6, 7]
    })
  }

  private async cancelAction(id?: number): Promise<void> {
    if (this.store.astronomyNotificationBusy) return
    this.store.astronomyNotificationBusy = true
    try {
      const result: AstronomyReminderResult = id === undefined ? await AstronomyReminderService.cancelAll() : await AstronomyReminderService.cancel(id)
      await this.refreshReminders()
      this.report(result.ok ? notificationText('提醒已取消。') : (result.error ?? notificationText('取消失败，请重试。')))
    } catch (error) {
      this.report(notificationText('取消失败，请刷新列表后重试。'))
    } finally {
      this.store.astronomyNotificationBusy = false
      this.resumePendingSubscriptions()
    }
  }

  cancelReminder(id: number): void {
    if (!validServiceId(id)) { this.report(notificationText('提醒 ID 无效。')); return }
    this.cancelAction(id)
  }
  clearReminders(): void { this.cancelAction() }
}
