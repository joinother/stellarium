import { reminderAgentManager } from '@kit.BackgroundTasksKit'
import { notificationManager } from '@kit.NotificationKit'
import { common } from '@kit.AbilityKit'
import preferences from '@ohos.data.preferences'
import { hasCurrentPrivacyConsent } from './PrivacyConsent'
import { notificationText } from '../capability/NotificationText'
import { AstronomyServiceResult, ReminderPolicyInput, AstronomyReminderPreferences, NormalizedReminder, validateReminder, validServiceId, serviceFailure } from './AstronomyNotificationPolicy'
import { ReminderReadback, ReminderReadbackWant, ReminderMetadataEntry, ReminderMetadataJournal, reminderRequestFingerprint, validReminderMetadata, reminderRouteUri, reminderRouteFromUri } from './AstronomyReminderMetadata'

export { AstronomyReminderKind, AstronomyReminderPreferences, AstronomyQuietHours } from './AstronomyNotificationPolicy'

export interface AstronomyReminderRequest extends ReminderPolicyInput {}

export interface AstronomyReminderResult extends AstronomyServiceResult {
  reminderId?: number
  reminderCount?: number
  unchanged?: boolean
  replaced?: boolean
  partial?: boolean
  activeReminderIds?: number[]
}

export interface AstronomyReminderItem {
  ownershipFingerprint?: string
  subscription?: string
  reminderId: number
  title: string
  content: string
  eventId: string
  kind: string
  dateTime: reminderAgentManager.LocalDateTime | null
  eventAt?: string
  jd?: number
  target?: string
  panel?: string
  tab?: number
  leadMinutes?: number
}

export interface AstronomyReminderListResult extends AstronomyServiceResult {
  items?: Array<AstronomyReminderItem>
  diagnostics?: AstronomyReminderDiagnostics
}

export interface AstronomyReminderDiagnosticEntry {
  reminderId: number
  request: ReminderReadback
  actualFingerprint: string
  expectedFingerprints: string[]
  owned: boolean
  wantAgentUriPresent: boolean
  wantAgentParametersPresent: boolean
}

export interface AstronomyReminderExpectedFingerprint {
  reminderId: number
  notificationId: number
  expectedFingerprint: string
}

export interface AstronomyReminderDiagnostics {
  entries: AstronomyReminderDiagnosticEntry[]
  journalEntries: AstronomyReminderExpectedFingerprint[]
  metadataError?: string
  metadataNeedsRepair: boolean
}

export class AstronomyReminderService {
  private static readonly BUNDLE_NAME = 'com.joinother.skyinstrument'
  private static readonly ABILITY_NAME = 'QAbility'
  private static queue: Promise<void> = Promise.resolve()
  private static context: common.UIAbilityContext | undefined = undefined
  private static settings: preferences.Preferences | undefined = undefined
  private static metadata: ReminderMetadataJournal | undefined = undefined
  private static metadataNeedsRepair: boolean = false

  public static configure(context: common.UIAbilityContext): void {
    AstronomyReminderService.context = context
  }

  public static routeFromUri(uri: string): Record<string, Object> | undefined {
    const value = reminderRouteFromUri(uri)
    if (value === undefined) return undefined
    const route: Record<string, Object> = {}
    if (value.panel !== undefined) route['panel'] = value.panel
    if (value.tab !== undefined) route['tab'] = value.tab
    if (value.eventId !== undefined) route['eventId'] = value.eventId
    if (value.eventAt !== undefined) route['eventAt'] = value.eventAt
    if (value.jd !== undefined) route['jd'] = value.jd
    if (value.kind !== undefined) route['kind'] = value.kind
    if (value.target !== undefined) route['target'] = value.target
    return route
  }

  private static async loadMetadata(repair: boolean = true): Promise<ReminderMetadataJournal> {
    if (AstronomyReminderService.context === undefined) throw new Error('reminder metadata context is not configured')
    if (AstronomyReminderService.settings === undefined) AstronomyReminderService.settings = await preferences.getPreferences(
      AstronomyReminderService.context, { name: 'stellarium_reminder_metadata_v1' })
    if (AstronomyReminderService.metadata === undefined) {
      const raw = await AstronomyReminderService.settings.get('journal', '')
      let journal: ReminderMetadataJournal = { version: 1, nextNotificationId: 1000000000, entries: [] }
      if (raw !== '') journal = JSON.parse(String(raw)) as ReminderMetadataJournal
      if (!validReminderMetadata(journal)) throw new Error('invalid reminder metadata journal')
      AstronomyReminderService.metadata = journal
    }
    if (repair && AstronomyReminderService.metadataNeedsRepair) {
      await AstronomyReminderService.settings.put('journal', JSON.stringify(AstronomyReminderService.metadata))
      await AstronomyReminderService.settings.flush()
      AstronomyReminderService.metadataNeedsRepair = false
    }
    return AstronomyReminderService.metadata
  }

  private static async saveMetadata(journal: ReminderMetadataJournal): Promise<void> {
    const settings = AstronomyReminderService.settings
    if (settings === undefined || !validReminderMetadata(journal)) throw new Error('invalid reminder metadata journal')
    try {
      await settings.put('journal', JSON.stringify(journal))
      await settings.flush()
      AstronomyReminderService.metadata = journal
      AstronomyReminderService.metadataNeedsRepair = false
    } catch (error) {
      AstronomyReminderService.metadataNeedsRepair = true
      throw new Error(String(error))
    }
  }

  private static readbackFields(request: reminderAgentManager.ReminderRequest): ReminderReadback {
    const value: ReminderReadback = {
      notificationId: request.notificationId, reminderType: request.reminderType,
      title: request.title, content: request.content
    }
    if (request.wantAgent !== undefined && request.wantAgent !== null) {
      const target: ReminderReadbackWant = { pkgName: request.wantAgent.pkgName, abilityName: request.wantAgent.abilityName }
      value.wantAgent = target
    }
    if (request.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR) {
      const calendar = request as reminderAgentManager.ReminderRequestCalendar
      value.dateTime = calendar.dateTime
      value.repeatDays = calendar.repeatDays
      value.repeatMonths = calendar.repeatMonths
      value.daysOfWeek = calendar.daysOfWeek
    } else if (request.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER) {
      value.triggerTimeInSeconds = (request as reminderAgentManager.ReminderRequestTimer).triggerTimeInSeconds
    } else {
      const alarm = request as reminderAgentManager.ReminderRequestAlarm
      value.hour = alarm.hour
      value.minute = alarm.minute
      value.daysOfWeek = alarm.daysOfWeek
    }
    return value
  }

  private static fingerprint(request: reminderAgentManager.ReminderRequest, includeNotificationId: boolean = true): string {
    return reminderRequestFingerprint(AstronomyReminderService.readbackFields(request), includeNotificationId)
  }

  private static diagnosticSnapshot(reminders: reminderAgentManager.ReminderInfo[], journal?: ReminderMetadataJournal,
    metadataError?: string): AstronomyReminderDiagnostics {
    const expected = journal?.entries ?? []
    const entries = reminders.map((item): AstronomyReminderDiagnosticEntry => {
      return {
        reminderId: item.reminderId, request: AstronomyReminderService.readbackFields(item.reminderReq),
        actualFingerprint: AstronomyReminderService.fingerprint(item.reminderReq),
        expectedFingerprints: expected.filter((entry) => entry.reminderId === item.reminderId ||
          entry.notificationId === item.reminderReq.notificationId).map((entry) => entry.fingerprint),
        owned: journal !== undefined && AstronomyReminderService.owned(item, journal) !== undefined,
        wantAgentUriPresent: item.reminderReq.wantAgent?.uri !== undefined,
        wantAgentParametersPresent: item.reminderReq.wantAgent?.parameters !== undefined
      }
    })
    return {
      entries: entries,
      journalEntries: expected.map((entry): AstronomyReminderExpectedFingerprint => {
        return { reminderId: entry.reminderId, notificationId: entry.notificationId, expectedFingerprint: entry.fingerprint }
      }),
      metadataError: metadataError, metadataNeedsRepair: AstronomyReminderService.metadataNeedsRepair
    }
  }

  private static owned(item: reminderAgentManager.ReminderInfo, journal: ReminderMetadataJournal): ReminderMetadataEntry | undefined {
    const fingerprint = AstronomyReminderService.fingerprint(item.reminderReq)
    if (!fingerprint) return undefined
    return journal.entries.find((entry) => entry.reminderId === item.reminderId && entry.fingerprint === fingerprint &&
      entry.notificationId === item.reminderReq.notificationId)
  }

  private static bindReminderId(entry: ReminderMetadataEntry, reminderId: number): ReminderMetadataEntry {
    return {
      reminderId: reminderId, notificationId: entry.notificationId, fingerprint: entry.fingerprint,
      bundleName: entry.bundleName, eventKey: entry.eventKey, signature: entry.signature,
      route: entry.route, leadMinutes: entry.leadMinutes
    }
  }

  private static async recoverMetadata(reminders: reminderAgentManager.ReminderInfo[]): Promise<ReminderMetadataJournal> {
    const journal = await AstronomyReminderService.loadMetadata()
    let changed = false
    const entries: ReminderMetadataEntry[] = []
    for (const entry of journal.entries) {
      if (reminders.some((item) => (entry.reminderId === -1 ? entry.notificationId === item.reminderReq.notificationId : entry.reminderId === item.reminderId) &&
        !AstronomyReminderService.fingerprint(item.reminderReq))) throw new Error('system reminder fingerprint fields are unavailable')
      const matches = reminders.filter((item) => (entry.reminderId === -1 || entry.reminderId === item.reminderId) &&
        entry.notificationId === item.reminderReq.notificationId && entry.fingerprint === AstronomyReminderService.fingerprint(item.reminderReq))
      if (matches.length !== 1) {
        const stillPresent = reminders.some((item) => entry.reminderId === item.reminderId ||
          entry.notificationId === item.reminderReq.notificationId)
        if (stillPresent) entries.push(entry)
        else changed = true
        continue
      }
      if (entry.reminderId === -1) {
        const recovered = AstronomyReminderService.bindReminderId(entry, matches[0].reminderId)
        entries.push(recovered)
        changed = true
      } else entries.push(entry)
    }
    if (changed) {
      const recovered: ReminderMetadataJournal = { version: 1, nextNotificationId: journal.nextNotificationId, entries: entries }
      await AstronomyReminderService.saveMetadata(recovered)
      return recovered
    }
    return journal
  }

  private static serial<T>(operation: () => Promise<T>): Promise<T> {
    const result = AstronomyReminderService.queue.then(operation)
    AstronomyReminderService.queue = result.then(() => {}, () => {})
    return result
  }

  private static localDateTime(date: Date): reminderAgentManager.LocalDateTime {
    return {
      year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate(),
      hour: date.getHours(), minute: date.getMinutes(), second: date.getSeconds()
    }
  }

  private static makeRequest(value: NormalizedReminder, bundleName: string, notificationId: number): reminderAgentManager.ReminderRequest {
    const route = value.route
    const parameters: Record<string, Object> = {}
    parameters['panel'] = route.panel ?? 'astro'
    parameters['tab'] = route.tab ?? 8
    parameters['eventId'] = route.eventId ?? ''
    parameters['kind'] = route.kind ?? 'astronomy'
    parameters['target'] = route.target ?? ''
    if (route.subscription !== undefined) parameters['subscription'] = route.subscription
    parameters['leadMinutes'] = value.leadMinutes
    parameters['astronomyEventKey'] = value.eventKey
    parameters['astronomySignature'] = JSON.stringify([value.reminderType, value.title, value.content, route,
      value.reminderType === 'calendar' ? value.fireAt : 0,
      value.reminderType === 'timer' ? value.triggerSeconds : 0,
      value.reminderType === 'alarm' ? [value.hour, value.minute, value.daysOfWeek] : [], bundleName])
    if (route.eventAt !== undefined) parameters['eventAt'] = route.eventAt
    if (route.jd !== undefined) parameters['jd'] = route.jd
    const wantAgent: reminderAgentManager.WantAgent = {
      pkgName: bundleName, abilityName: AstronomyReminderService.ABILITY_NAME,
      uri: reminderRouteUri(route, notificationId), parameters: parameters
    }
    let request: reminderAgentManager.ReminderRequest
    if (value.reminderType === 'timer') {
      const timer: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: value.triggerSeconds
      }
      request = timer
    } else if (value.reminderType === 'alarm') {
      const alarm: reminderAgentManager.ReminderRequestAlarm = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
        hour: value.hour, minute: value.minute, daysOfWeek: value.daysOfWeek
      }
      request = alarm
    } else {
      const calendar: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: AstronomyReminderService.localDateTime(new Date(value.fireAt))
      }
      request = calendar
    }
    request.title = value.title
    request.content = value.content
    request.expiredContent = value.content
    request.tapDismissed = true
    request.wantAgent = wantAgent
    request.notificationId = notificationId
    return request
  }

  public static status(): Promise<AstronomyReminderResult> {
    return AstronomyReminderService.serial(async (): Promise<AstronomyReminderResult> => {
      let notificationEnabled: boolean | undefined = undefined
      try {
        notificationEnabled = await notificationManager.isNotificationEnabled()
        const reminders = await reminderAgentManager.getAllValidReminders()
        return { ok: true, notificationEnabled: notificationEnabled, reminderCount: reminders.length }
      } catch (error) {
        const result: AstronomyReminderResult = serviceFailure(error, '后台代理提醒状态查询失败')
        if (notificationEnabled !== undefined && result.notificationEnabled === undefined) result.notificationEnabled = notificationEnabled
        return result
      }
    })
  }

  public static async schedule(payload: AstronomyReminderRequest, bundleName: string = '', preferences?: AstronomyReminderPreferences, canInteract?: () => boolean, maxActiveReminders?: number): Promise<AstronomyReminderResult> {
    if (maxActiveReminders !== undefined && (!Number.isInteger(maxActiveReminders) || maxActiveReminders < 1 || maxActiveReminders > 30)) {
      return { ok: false, reason: 'validation', error: 'invalid reminder budget' }
    }
    const validation = validateReminder(payload, Date.now(), preferences)
    if (!validation.ok || validation.value === undefined) return validation
    if (typeof bundleName !== 'string' || (bundleName.length > 0 && !/^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/.test(bundleName))) {
      return { ok: false, reason: 'validation', error: 'bundleName must be the runtime application bundle name' }
    }
    const value = validation.value
    const bundle = bundleName || AstronomyReminderService.BUNDLE_NAME
    return AstronomyReminderService.serial(async (): Promise<AstronomyReminderResult> => {
      try {
        if (canInteract !== undefined && !canInteract()) return { ok: false, reason: 'interaction-unavailable', error: '请回到前台后重新添加提醒。' }
        if (!hasCurrentPrivacyConsent()) return { ok: false, reason: 'privacy-required', error: '请先同意当前隐私协议。' }
        const enabled = await notificationManager.isNotificationEnabled()
        if (!enabled) return { ok: false, reason: 'notification-disabled', notificationEnabled: false, error: 'notification authorization is required' }
        const reminders = await reminderAgentManager.getAllValidReminders()
        let journal: ReminderMetadataJournal
        try { journal = await AstronomyReminderService.recoverMetadata(reminders) } catch (_) {
          return { ok: false, reason: 'metadata-unavailable', error: '提醒记录读取或保存失败，未发布或取消任何提醒。' }
        }
        const matches = value.eventKey.length === 0 ? [] : reminders.filter((item) => {
          const entry = AstronomyReminderService.owned(item, journal)
          return entry?.bundleName === bundle && entry.eventKey === value.eventKey
        })
        const unresolved = journal.entries.find((entry) => value.eventKey.length > 0 && entry.bundleName === bundle &&
          entry.eventKey === value.eventKey && !matches.some((item) => item.reminderId === entry.reminderId &&
            item.reminderReq.notificationId === entry.notificationId))
        if (unresolved !== undefined) return {
          ok: false, reason: 'metadata-unverified', error: '已有提醒记录尚未核验，未再次发布或取消，请先检查诊断。'
        }
        let notificationId = journal.nextNotificationId
        while (reminders.some((item) => item.reminderReq.notificationId === notificationId)) notificationId += 1
        if (!validServiceId(notificationId)) return { ok: false, reason: 'metadata-id-exhausted', error: '提醒标识已耗尽，未改变已有提醒。' }
        const request = AstronomyReminderService.makeRequest(value, bundle, notificationId)
        const signature = String(request.wantAgent?.parameters?.['astronomySignature'])
        const existing = matches.find((item) => AstronomyReminderService.owned(item, journal)?.signature === signature)
        let reminderId: number
        if (existing !== undefined) {
          reminderId = existing.reminderId
        } else {
          const equivalent = reminders.find((item) => value.reminderType === 'calendar' && AstronomyReminderService.owned(item, journal) === undefined &&
            (item.reminderReq.notificationId ?? -1) >= 1000000000 &&
            AstronomyReminderService.fingerprint(item.reminderReq, false) === AstronomyReminderService.fingerprint(request, false))
          if (equivalent !== undefined) return {
            ok: false, reason: 'legacy-reminder-unverified', reminderId: equivalent.reminderId,
            activeReminderIds: [equivalent.reminderId], unchanged: true,
            error: '已有相同提醒，但来源无法确认；未重复添加或取消，请先检查已有提醒。'
          }
          if (maxActiveReminders !== undefined && reminders.length >= maxActiveReminders) return {
            ok: false, reason: 'local-budget', error: '提醒名额暂满，已有提醒保持不变。'
          }
          if (value.reminderType === 'calendar' && value.fireAt <= Date.now() + 30000) return { ok: false, reason: 'too-soon', error: 'reminder must be more than 30 seconds in the future' }
          const entry: ReminderMetadataEntry = {
            reminderId: -1, notificationId: notificationId, fingerprint: AstronomyReminderService.fingerprint(request),
            bundleName: bundle, eventKey: value.eventKey, signature: signature, route: value.route, leadMinutes: value.leadMinutes
          }
          const prepared: ReminderMetadataJournal = {
            version: 1, nextNotificationId: notificationId + 1, entries: [...journal.entries, entry]
          }
          try { await AstronomyReminderService.saveMetadata(prepared) } catch (_) {
            return { ok: false, reason: 'metadata-unavailable', error: '提醒记录保存失败，未发布或取消任何提醒。' }
          }
          try {
            if (canInteract !== undefined && !canInteract()) return { ok: false, reason: 'interaction-unavailable', error: '请回到前台后重新添加提醒。' }
            if (!hasCurrentPrivacyConsent()) return { ok: false, reason: 'privacy-required', error: '请先同意当前隐私协议。' }
            if (value.reminderType === 'calendar' && value.fireAt <= Date.now() + 30000) return { ok: false, reason: 'too-soon', error: 'reminder must be more than 30 seconds in the future' }
            reminderId = await reminderAgentManager.publishReminder(request)
          } catch (error) {
            const failure: AstronomyReminderResult = serviceFailure(error, '后台代理提醒发布失败')
            failure.activeReminderIds = matches.map((item) => item.reminderId)
            return failure
          }
          try {
            const active = await reminderAgentManager.getAllValidReminders()
            const published = active.filter((item) => item.reminderId === reminderId &&
              item.reminderReq.notificationId === entry.notificationId && AstronomyReminderService.fingerprint(item.reminderReq) === entry.fingerprint)
            const bound = AstronomyReminderService.bindReminderId(entry, reminderId)
            const committed: ReminderMetadataJournal = {
              version: 1, nextNotificationId: prepared.nextNotificationId, entries: [...journal.entries, bound]
            }
            await AstronomyReminderService.saveMetadata(committed)
            journal = committed
            if (published.length !== 1) return {
              ok: false, partial: true, reminderId: reminderId, reason: 'metadata-unverified',
              activeReminderIds: [reminderId, ...matches.map((item) => item.reminderId)],
              error: '提醒已发布，但系统返回字段不足以核验；已有提醒未取消。'
            }
          } catch (_) {
            return {
              ok: false, partial: true, reminderId: reminderId, reason: 'metadata-commit-failed',
              activeReminderIds: [reminderId, ...matches.map((item) => item.reminderId)],
              error: '提醒已发布，但记录保存或核验失败；已有提醒未取消，请刷新后重试。'
            }
          }
        }
        const remaining: number[] = [reminderId]
        let cleanupFailure: AstronomyServiceResult | undefined = undefined
        for (const item of matches) {
          if (item.reminderId === reminderId) continue
          const cancelled = await AstronomyReminderService.cancelVerified(item.reminderId, AstronomyReminderService.fingerprint(item.reminderReq))
          if (!cancelled.ok) {
            remaining.push(item.reminderId)
            cleanupFailure = cancelled
          }
        }
        if (cleanupFailure !== undefined) return {
          ok: false, reminderId: reminderId, partial: true, activeReminderIds: remaining,
          reason: 'replacement-cleanup-failed', code: cleanupFailure.code,
          error: '新提醒已保留，但旧提醒未能全部取消；请刷新列表并重试。'
        }
        return {
          ok: true, reminderId: reminderId, notificationEnabled: true,
          unchanged: existing !== undefined, replaced: matches.some((item) => item.reminderId !== reminderId), activeReminderIds: remaining
        }
      } catch (error) {
        return serviceFailure(error, '后台代理提醒发布失败')
      }
    })
  }

  public static list(diagnostics: boolean = false, canInteract?: () => boolean): Promise<AstronomyReminderListResult> {
    return AstronomyReminderService.serial(async (): Promise<AstronomyReminderListResult> => {
      try {
        if (diagnostics && (!hasCurrentPrivacyConsent() || canInteract === undefined || !canInteract())) return {
          ok: false, reason: 'interaction-unavailable', error: 'privacy consent and foreground are required for reminder diagnostics'
        }
        const reminders = await reminderAgentManager.getAllValidReminders()
        let journal: ReminderMetadataJournal | undefined = undefined
        let metadataError: string | undefined = undefined
        try {
          journal = diagnostics ? await AstronomyReminderService.loadMetadata(false) : await AstronomyReminderService.recoverMetadata(reminders)
        } catch (_) {
          metadataError = '提醒记录读取或保存失败，请重试。'
          if (!diagnostics) return { ok: false, reason: 'metadata-unavailable', error: metadataError }
        }
        if (diagnostics && (!hasCurrentPrivacyConsent() || canInteract === undefined || !canInteract())) return {
          ok: false, reason: 'interaction-unavailable', error: 'privacy consent and foreground are required for reminder diagnostics'
        }
        const items = reminders.map((item): AstronomyReminderItem => {
          const request = item.reminderReq
          const entry = journal === undefined ? undefined : AstronomyReminderService.owned(item, journal)
          const route = entry?.route
          return {
            ownershipFingerprint: entry?.fingerprint,
            subscription: route?.subscription,
            reminderId: item.reminderId, title: request.title ?? '', content: request.content ?? '',
            eventId: route?.eventId ?? '', kind: route?.kind ?? 'unknown',
            dateTime: request.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR ? (request as reminderAgentManager.ReminderRequestCalendar).dateTime : null,
            eventAt: route?.eventAt, jd: route?.jd, target: route?.target, panel: route?.panel,
            tab: route?.tab, leadMinutes: entry?.leadMinutes
          }
        })
        const result: AstronomyReminderListResult = { ok: metadataError === undefined, items: items }
        if (metadataError !== undefined) {
          result.reason = 'metadata-unavailable'
          result.error = metadataError
        }
        if (diagnostics) result.diagnostics = AstronomyReminderService.diagnosticSnapshot(reminders, journal, metadataError)
        return result
      } catch (error) {
        return serviceFailure(error, '无法读取后台代理提醒')
      }
    })
  }

  private static async cancelOne(reminderId: number): Promise<AstronomyReminderResult> {
    try {
      await reminderAgentManager.cancelReminder(reminderId)
      return { ok: true, reminderId: reminderId }
    } catch (error) {
      const result: AstronomyReminderResult = serviceFailure(error, '后台代理提醒取消失败')
      if (result.code === 1700003) return { ok: true, reminderId: reminderId, unchanged: true }
      return result
    }
  }

  private static async cancelVerified(reminderId: number, fingerprint: string): Promise<AstronomyReminderResult> {
    try {
      const reminders = await reminderAgentManager.getAllValidReminders()
      const item = reminders.find((value) => value.reminderId === reminderId)
      if (item === undefined) return { ok: true, reminderId: reminderId, unchanged: true }
      const journal = await AstronomyReminderService.recoverMetadata(reminders)
      const entry = AstronomyReminderService.owned(item, journal)
      if (!fingerprint || entry === undefined || entry.fingerprint !== fingerprint) return {
        ok: false, reason: 'ownership-mismatch', error: '提醒来源已变化，未取消该提醒。'
      }
      return AstronomyReminderService.cancelOne(reminderId)
    } catch (error) { return serviceFailure(error, '提醒来源核验失败，未取消该提醒。') }
  }

  public static cancelOwned(item: AstronomyReminderItem): Promise<AstronomyReminderResult> {
    if (!validServiceId(item?.reminderId) || !item?.ownershipFingerprint) return Promise.resolve({
      ok: false, reason: 'ownership-mismatch', error: '提醒来源无法确认，未取消该提醒。'
    })
    return AstronomyReminderService.serial(() => AstronomyReminderService.cancelVerified(item.reminderId, item.ownershipFingerprint ?? ''))
  }

  public static async cancel(reminderId: number): Promise<AstronomyReminderResult> {
    if (!validServiceId(reminderId)) return { ok: false, reason: 'validation', error: 'reminderId must be a non-negative 32-bit integer' }
    return AstronomyReminderService.serial(() => AstronomyReminderService.cancelOne(reminderId))
  }

  public static cancelAll(): Promise<AstronomyReminderResult> {
    return AstronomyReminderService.serial(async (): Promise<AstronomyReminderResult> => {
      try {
        await reminderAgentManager.cancelAllReminders()
        return { ok: true }
      } catch (error) {
        return serviceFailure(error, '后台代理提醒清理失败')
      }
    })
  }
}
