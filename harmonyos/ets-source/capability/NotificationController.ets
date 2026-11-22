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
import {
  NotificationTimingMode,
  NotificationTopicId,
  SUBSCRIPTION_PRESETS,
  SubscriptionPresetId,
  SubscriptionTopicFlags,
  hasAnyAstronomyTopic,
  normalizeCanonicalEventId,
  normalizeTimingMode,
  resolveReminderTimingPlan
} from '../qability/AstronomyNotificationTiming'
import { normalizeObserverRegionId } from '../state/ObserverRegionScope'
import { CalendarSubscriptionMapping } from '../state/AstronomyCalendarFilter'
import { MoonPhaseItem, SeasonEvent } from '../common/types/StellariumTypes'
import { MeteorShowerItem } from '../common/types/MainWindowModels'

export interface SyncedWidgetReminderEntry {
  eventId: string
  reminderId: number
  source?: string
}

export interface NotificationHostHooks {
  loadSubscriptionEvents?(category: AstronomySubscriptionCategory, from: number, until: number): Promise<AstronomySubscriptionFeed>
  canInteract?(): boolean
  openCalendar?(): void
  syncWidgetReminders?(activeEntries: SyncedWidgetReminderEntry[]): void
  readWidgetRemindedEntries?(): SyncedWidgetReminderEntry[]
  flashHint(text: ResourceStr): void
  hostContext(): common.UIAbilityContext
  almanacSolarTerms(): SeasonEvent[]
  loadAlmanac(): void
  moonPhases(): MoonPhaseItem[]
  loadMoonPhases(): void
  meteorShowers(): MeteorShowerItem[]
  loadMeteorShowers(): void
  observerLatitude?(): number
  bortleScale?(): number
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
      dndSatelliteOnly: this.store.dndSatelliteOnly,
      satellitePassEnabled: this.store.satellitePassEnabled, digestEnabled: this.store.digestEnabled,
      subscriptionsVersion: 1,
      dndStartMinutes: this.store.dndStartMinutes, dndEndMinutes: this.store.dndEndMinutes,
      passLeadMinutes: this.store.passLeadMinutes,
      topicMeteor: this.store.topicMeteor,
      topicPlanet: this.store.topicPlanet,
      topicMoon: this.store.topicMoon,
      topicSolarTerm: this.store.topicSolarTerm,
      highlightOnly: this.store.subscriptionHighlightOnly,
      timingMode: normalizeTimingMode(this.store.timingMode),
      regionId: normalizeObserverRegionId(this.store.regionId)
    }
  }

  private applyPreferences(value: NotificationPreferenceSnapshot): void {
    this.store.astronomyEventsEnabled = value.astronomyEventsEnabled
    this.store.satellitePassEnabled = value.satellitePassEnabled === true
    this.store.digestEnabled = value.digestEnabled === true
    this.store.topicMeteor = value.topicMeteor !== undefined ? value.topicMeteor : value.astronomyEventsEnabled
    this.store.topicPlanet = value.topicPlanet !== undefined ? value.topicPlanet : value.astronomyEventsEnabled
    this.store.topicMoon = value.topicMoon !== undefined ? value.topicMoon : value.astronomyEventsEnabled
    this.store.topicSolarTerm = value.topicSolarTerm !== undefined ? value.topicSolarTerm : value.astronomyEventsEnabled
    this.store.subscriptionHighlightOnly = value.highlightOnly === true
    this.store.timingMode = normalizeTimingMode(value.timingMode)
    // 通知暂时专注当前地球观测位置，统一跟随当前位置（避免旧自定义区域残留）
    this.store.regionId = 'follow'
    this.store.dndEnabled = value.dndEnabled
    this.store.dndSatelliteOnly = value.dndSatelliteOnly !== false
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
    if (enabled && !this.store.topicMeteor && !this.store.topicPlanet && !this.store.topicMoon && !this.store.topicSolarTerm) {
      this.store.topicMeteor = true
      this.store.topicPlanet = true
      this.store.topicMoon = true
      this.store.topicSolarTerm = true
    } else if (!enabled) {
      this.store.topicMeteor = false
      this.store.topicPlanet = false
      this.store.topicMoon = false
      this.store.topicSolarTerm = false
    }
    this.persistPreferences()
  }

  setSatellitePassEnabled(enabled: boolean): void {
    this.store.satellitePassEnabled = enabled
    this.persistPreferences()
  }

  setTopicEnabled(topic: NotificationTopicId, enabled: boolean): void {
    if (topic === 'satellite') {
      this.setSatellitePassEnabled(enabled)
      return
    }
    if (topic === 'meteor') this.store.topicMeteor = enabled
    else if (topic === 'planet') this.store.topicPlanet = enabled
    else if (topic === 'moon') this.store.topicMoon = enabled
    else if (topic === 'solar_term') this.store.topicSolarTerm = enabled
    const flags: SubscriptionTopicFlags = {
      meteor: this.store.topicMeteor,
      planet: this.store.topicPlanet,
      moon: this.store.topicMoon,
      solarTerm: this.store.topicSolarTerm,
      satellite: this.store.satellitePassEnabled,
      highlightOnly: this.store.subscriptionHighlightOnly
    }
    this.store.astronomyEventsEnabled = hasAnyAstronomyTopic(flags)
    this.persistPreferences()
  }

  setSubscriptionHighlightOnly(enabled: boolean): void {
    this.store.subscriptionHighlightOnly = enabled
    this.persistPreferences()
  }

  setTimingMode(mode: string): void {
    this.store.timingMode = normalizeTimingMode(mode)
    this.persistPreferences()
  }

  setRegionId(regionId: string): void {
    this.store.regionId = normalizeObserverRegionId(regionId)
    this.persistPreferences()
  }

  setPassLeadMinutes(minutes: number): void {
    this.store.passLeadMinutes = Math.min(60, Math.max(0, Math.round(minutes)))
    this.persistPreferences()
  }

  applySubscriptionPreset(presetId: SubscriptionPresetId): void {
    const preset = SUBSCRIPTION_PRESETS.find((item) => item.id === presetId)
    if (preset === undefined) return
    this.store.topicMeteor = preset.flags.meteor
    this.store.topicPlanet = preset.flags.planet
    this.store.topicMoon = preset.flags.moon
    this.store.topicSolarTerm = preset.flags.solarTerm
    this.store.satellitePassEnabled = preset.flags.satellite
    this.store.subscriptionHighlightOnly = preset.flags.highlightOnly
    this.store.astronomyEventsEnabled = hasAnyAstronomyTopic(preset.flags)
    this.store.timingMode = preset.timingMode
    this.store.passLeadMinutes = preset.passLeadMinutes
    this.store.dndEnabled = preset.dndEnabled
    this.store.dndSatelliteOnly = preset.dndSatelliteOnly
    this.persistPreferences()
    this.report(notificationText('已应用订阅方案：') + preset.labelZh)
  }

  subscribeFromCalendarFilter(mapping: CalendarSubscriptionMapping, regionId?: string): void {
    this.store.topicMeteor = mapping.meteor
    this.store.topicPlanet = mapping.planet
    this.store.topicMoon = mapping.moon
    this.store.topicSolarTerm = mapping.solarTerm
    this.store.satellitePassEnabled = mapping.satellite
    this.store.subscriptionHighlightOnly = mapping.highlightOnly
    this.store.astronomyEventsEnabled = mapping.meteor || mapping.planet || mapping.moon || mapping.solarTerm
    if (regionId !== undefined) {
      this.store.regionId = 'follow'
    }
    this.persistPreferences()
    this.report(notificationText('已按当前日历筛选同步通知订阅。'))
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
        const timingPlan = resolveReminderTimingPlan(event, {
          nowMs: Date.now(),
          timingMode: normalizeTimingMode(snapshot.timingMode),
          passLeadMinutes: snapshot.passLeadMinutes,
          regionId: snapshot.regionId,
          observerLatitude: this.hooks.observerLatitude ? this.hooks.observerLatitude() : undefined,
          bortleScale: this.hooks.bortleScale ? this.hooks.bortleScale() : undefined,
          dndEnabled: snapshot.dndEnabled,
          dndSatelliteOnly: snapshot.dndSatelliteOnly,
          dndStartMinutes: snapshot.dndStartMinutes,
          dndEndMinutes: snapshot.dndEndMinutes
        })
        const leadMinutes = timingPlan.leadMinutes
        const payload: AstronomyReminderRequest = {
          subscription: category, eventAt: new Date(event.at).toISOString(), jd: event.jd,
          title: notificationText('星象仪 · ') + event.title,
          content: timingPlan.contentZh,
          eventId: normalizeCanonicalEventId(event.id), kind: event.kind, target: event.target,
          panel: category === 'astronomy' ? 'calendar' : event.panel, tab: event.tab,
          leadMinutes: leadMinutes
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
  setDndSatelliteOnly(enabled: boolean): void { this.store.dndSatelliteOnly = enabled; this.persistPreferences() }

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
      dndEnabled: this.store.dndEnabled, dndSatelliteOnly: this.store.dndSatelliteOnly,
      dndStartMinutes: this.store.dndStartMinutes, dndEndMinutes: this.store.dndEndMinutes
    }
  }

  private async refreshReminders(): Promise<void> {
    const result = await AstronomyReminderService.list()
    if (result.ok && result.items !== undefined) {
      // Merge system reminders with widget-booked entries so desktop widget bookings appear seamlessly in-app
      const widgetEntries = this.hooks.readWidgetRemindedEntries ? this.hooks.readWidgetRemindedEntries() : []
      const widgetByReminderId = new Map<number, SyncedWidgetReminderEntry>()
      for (let i = 0; i < widgetEntries.length; i++) {
        widgetByReminderId.set(widgetEntries[i].reminderId, widgetEntries[i])
      }
      const enriched = result.items.map((item) => {
        if (item.eventId.length === 0 && widgetByReminderId.has(item.reminderId)) {
          const w = widgetByReminderId.get(item.reminderId)!
          item.eventId = normalizeCanonicalEventId(w.eventId)
          if (item.subscription === undefined) item.subscription = w.source ?? 'widget'
        } else if (item.eventId.length > 0) {
          item.eventId = normalizeCanonicalEventId(item.eventId)
        }
        return item
      })
      this.store.astronomyReminders = enriched
      this.store.astronomyReminderCount = enriched.length
      const ids: string[] = []
      const syncedForWidgets: SyncedWidgetReminderEntry[] = []
      for (let i = 0; i < enriched.length; i++) {
        const evId = normalizeCanonicalEventId(enriched[i].eventId)
        if (evId.length > 0) {
          if (!ids.includes(evId)) ids.push(evId)
          syncedForWidgets.push({
            eventId: evId,
            reminderId: enriched[i].reminderId,
            source: enriched[i].subscription ?? 'calendar'
          })
        }
      }
      this.store.remindedEventIds = ids
      if (this.hooks.syncWidgetReminders !== undefined) {
        try { this.hooks.syncWidgetReminders(syncedForWidgets) } catch (_) {}
      }
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

  private clockText(atMs: number): string {
    const date = new Date(atMs)
    return String(date.getHours()).padStart(2, '0') + ':' + String(date.getMinutes()).padStart(2, '0')
  }

  private moonElongationDeg(jd: number): number {
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

  private localizedPlanet(englishName: string | undefined): string {
    if (!englishName) return ''
    return notificationText(englishName)
  }

  private eventReminderContent(event: AstronomyCalendarEvent, category: string, leadMinutes: number): string {
    if (category === 'satellite' || event.kind === 'satellite-pass') {
      return leadMinutes > 0
        ? event.title + notificationText(' 将在 ') + String(leadMinutes) + notificationText(' 分钟后达到过境最高点，抬头观测！')
        : event.title + notificationText(' 即将达到过境最高点，抬头观测！')
    }
    if (event.kind === 'moon-phase') {
      if (event.isSupermoon === true) {
        return leadMinutes > 0
          ? notificationText('今晚迎来超级满月，将在 ') + String(leadMinutes) + notificationText(' 分钟后到达近地点满月时刻，抬头赏月！')
          : notificationText('今晚迎来超级满月，月球接近近地点，打开星象仪查看月相与观测时刻。')
      }
      if (event.phaseIndex === 0) {
        return notificationText('今晚迎来新月，整夜几乎无月光干扰，是观银河与深空天体的绝佳暗夜。')
      }
      if (event.phaseIndex === 2) {
        if (event.distanceKm !== undefined && event.distanceKm >= 404000) {
          return notificationText('今晚迎来微满月（月球临近远地点），日落后自东方升起。')
        }
        return leadMinutes > 0
          ? notificationText('满月将在 ') + String(leadMinutes) + notificationText(' 分钟后到达满月时刻，抬头赏月。')
          : notificationText('今晚迎来满月，日落后即可向东方地平线赏月。')
      }
      if (event.phaseIndex === 1 || event.phaseIndex === 3) {
        return event.title + notificationText(' 即将到来，月面晨昏线环形山立体清晰，适合举镜赏月。')
      }
      return event.title + notificationText(' 即将到来，打开星象仪查看月相与观测时刻。')
    }
    if (event.kind === 'solar-term') {
      const lat = this.hooks.observerLatitude ? this.hooks.observerLatitude() : 39.9
      const southern = Number.isFinite(lat) && lat < 0
      const clock = this.clockText(event.at)
      if (event.phaseIndex === 5) {
        return notificationText('今日 ') + clock + notificationText(southern ? ' 迎来二分点（南半球入秋），全球昼夜几乎等长，夜空窗口渐长。' : ' 迎来春分（北半球入春），全球昼夜几乎等长。')
      }
      if (event.phaseIndex === 11) {
        return notificationText('今日 ') + clock + notificationText(southern ? ' 迎来至点（南半球入冬），迎来全年最长观星暗夜。' : ' 迎来夏至（北半球入夏），白昼达到全年最长。')
      }
      if (event.phaseIndex === 17) {
        return notificationText('今日 ') + clock + notificationText(southern ? ' 迎来二分点（南半球入春），全球昼夜几乎等长。' : ' 迎来秋分（北半球入秋），全球昼夜几乎等长，秋季观星季开启。')
      }
      if (event.phaseIndex === 23) {
        return notificationText('今日 ') + clock + notificationText(southern ? ' 迎来至点（南半球入夏），白昼达到全年最长。' : ' 迎来冬至（北半球入冬），迎来全年最长观星暗夜。')
      }
      return notificationText('今日 ') + clock + notificationText(' 步入') + event.title + notificationText(' 节气，打开星象仪查看当季星空。')
    }
    if (event.kind === 'meteor-peak') {
      const elong = this.moonElongationDeg(event.jd)
      const bortle = this.hooks.bortleScale ? this.hooks.bortleScale() : undefined
      const urbanSky = bortle !== undefined && Number.isFinite(bortle) && bortle >= 6
      let moonTail = notificationText('：选择开阔暗空处，打开星象仪定位辐射点。')
      if (elong >= 0) {
        if (elong < 22 || elong >= 338) {
          moonTail = urbanSky
            ? notificationText('：无月干扰，建议远离城区灯火以捕捉更多暗弱流星。')
            : notificationText('：无月干扰，暗空通透，非常适合守候流星！')
        } else if (elong < 95) {
          moonTail = notificationText('：月光仅影响上半夜，午夜月落后迎来暗空窗口。')
        } else if (elong >= 275) {
          moonTail = notificationText('：残月黎明前才升起，深夜核心时段几乎不受月光干扰。')
        } else {
          moonTail = notificationText('：当晚月光较强，建议背向月亮重点守候明亮火流星。')
        }
      }
      return notificationText('今夜迎来') + event.title + moonTail
    }
    if (event.kind === 'planetary-event') {
      const pName = this.localizedPlanet(event.primary ?? event.target)
      if (event.subtype === 'opposition' && pName.length > 0) {
        return notificationText('今夜 ') + pName + notificationText(' 冲日，整夜可见且亮度与视直径均处全年高位！')
      }
      if (event.subtype === 'greatest-elongation' && pName.length > 0) {
        if (event.direction === 'east') {
          return notificationText('今夜日落后不久面向西方低空，即可寻觅 ') + pName + notificationText('（东大距，傍晚观测窗口）！')
        }
        if (event.direction === 'west') {
          return notificationText('明晨日出前的一小段时间面向东方低空，即可寻觅 ') + pName + notificationText('（西大距，清晨观测窗口）！')
        }
      }
      if (event.subtype === 'conjunction') {
        if (event.secondary && event.secondary !== 'Sun' && pName.length > 0) {
          const sName = this.localizedPlanet(event.secondary)
          const hour = new Date(event.at).getHours()
          const morning = hour >= 2 && hour < 10
          const sepText = event.separationDegrees !== undefined && Number.isFinite(event.separationDegrees)
            ? notificationText('（约 ') + event.separationDegrees.toFixed(1) + notificationText('°）')
            : ''
          return pName + notificationText(' 与 ') + sName + notificationText(' 近距离相合') + sepText +
            notificationText(morning ? '，留意明晨 ' : '，留意今晚 ') +
            this.clockText(event.at) + notificationText(' 前后同框观测。')
        }
        if (event.secondary === 'Sun') {
          return event.title + notificationText(' 即将合日（贴近太阳耀眼日光，严禁举镜直视）。')
        }
      }
      return event.title + notificationText(' 即将发生，打开星象仪查看行星位置与观测窗口。')
    }
    return event.title + notificationText(' 即将到来，打开星象仪查看事件与观测信息。')
  }

  async scheduleEvent(event: AstronomyCalendarEvent): Promise<AstronomyCalendarReminderResult> {
    if (event === undefined || event === null || typeof event.id !== 'string' || event.id.trim().length === 0 ||
      typeof event.title !== 'string' || event.title.trim().length === 0 ||
      typeof event.at !== 'number' || !Number.isFinite(event.at) || !Number.isFinite(new Date(event.at).getTime())) {
      return this.reportReminderResult({ ok: false, reason: 'validation', error: notificationText('天象事件数据无效。') })
    }
    const rawPlanet = typeof event.observerPlanet === 'string' ? event.observerPlanet.trim() : ''
    const isOffEarth = rawPlanet.length > 0 && rawPlanet.toLowerCase() !== 'earth'
    let planetLabel = rawPlanet
    if (rawPlanet === 'Moon') planetLabel = '月球'
    else if (rawPlanet === 'Mercury') planetLabel = '水星'
    else if (rawPlanet === 'Venus') planetLabel = '金星'
    else if (rawPlanet === 'Mars') planetLabel = '火星'
    else if (rawPlanet === 'Jupiter') planetLabel = '木星'
    else if (rawPlanet === 'Saturn') planetLabel = '土星'
    else if (rawPlanet === 'Titan') planetLabel = '土卫六'
    else if (rawPlanet === 'Uranus') planetLabel = '天王星'
    else if (rawPlanet === 'Neptune') planetLabel = '海王星'
    else if (rawPlanet === 'Pluto') planetLabel = '冥王星'
    const titlePrefix = isOffEarth
      ? notificationText('星象仪 · 【' + planetLabel + '】')
      : notificationText('星象仪 · ')
    const canonicalId = normalizeCanonicalEventId(event.id)
    const timingPlan = resolveReminderTimingPlan(event, {
      nowMs: Date.now(),
      timingMode: normalizeTimingMode(this.store.timingMode),
      passLeadMinutes: this.store.passLeadMinutes,
      regionId: this.store.regionId,
      observerLatitude: this.hooks.observerLatitude ? this.hooks.observerLatitude() : undefined,
      bortleScale: this.hooks.bortleScale ? this.hooks.bortleScale() : undefined,
      dndEnabled: this.store.dndEnabled,
      dndSatelliteOnly: this.store.dndSatelliteOnly,
      dndStartMinutes: this.store.dndStartMinutes,
      dndEndMinutes: this.store.dndEndMinutes
    })
    const req: AstronomyReminderRequest = {
      eventAt: new Date(event.at).toISOString(), title: titlePrefix + event.title,
      content: timingPlan.contentZh,
      eventId: canonicalId, kind: event.kind, jd: event.jd, target: event.target, panel: 'calendar', tab: event.tab,
      leadMinutes: timingPlan.leadMinutes
    }
    if (isOffEarth) req.observerPlanet = rawPlanet
    // Manual single-event booking should succeed even if bulk auto-subscriptions are off, while still honoring DND.
    return this.scheduleManualOne(req)
  }

  private async scheduleManualOne(payload: AstronomyReminderRequest): Promise<AstronomyCalendarReminderResult> {
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
      const manualPrefs: AstronomyReminderPreferences = {
        dndEnabled: this.store.dndEnabled,
        dndSatelliteOnly: this.store.dndSatelliteOnly,
        dndStartMinutes: this.store.dndStartMinutes,
        dndEndMinutes: this.store.dndEndMinutes
      }
      const result = await AstronomyReminderService.schedule(payload, this.hooks.hostContext().abilityInfo.bundleName,
        manualPrefs, (): boolean => this.canInteract())
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

  public isEventReminded(eventId: string): boolean {
    const norm = normalizeCanonicalEventId(eventId)
    return norm.length > 0 && this.store.remindedEventIds.includes(norm)
  }

  public async toggleEventReminder(event: AstronomyCalendarEvent): Promise<AstronomyCalendarReminderResult> {
    const norm = normalizeCanonicalEventId(event.id)
    const existing = this.store.astronomyReminders.find((item) => normalizeCanonicalEventId(item.eventId) === norm)
    if (existing !== undefined) {
      await this.cancelAction(existing.reminderId)
      return { ok: true, reminderId: existing.reminderId, message: notificationText('已取消该天象提醒。') }
    }
    return this.scheduleEvent(event)
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
