import { reminderAgentManager } from '@kit.BackgroundTasksKit'
import { notificationManager } from '@kit.NotificationKit'
import { BusinessError } from '@kit.BasicServicesKit'

// 代理提醒支持的三类：倒计时 / 日历 / 闹钟（对应 reminderAgentManager 的三种类型）。
export type AstronomyReminderKind = 'timer' | 'calendar' | 'alarm'

export interface AstronomyReminderRequest {
  // timer: 秒数；calendar: ISO 时间；alarm: 忽略（用 hour/minute）
  at: string
  title: string
  content: string
  reminderType?: AstronomyReminderKind
  triggerSeconds?: number
  hour?: number
  minute?: number
  daysOfWeek?: Array<number>
  eventId?: string
  kind?: string
  panel?: string
  tab?: number
}

export interface AstronomyReminderResult {
  ok: boolean
  reminderId?: number
  error?: string
  code?: number
  notificationEnabled?: boolean
  reminderCount?: number
}

interface AstronomyWantParameters extends Record<string, Object> {
  panel: string
  tab: number
  eventId: string
  kind: string
}

interface AstronomyReminderItem {
  reminderId: number
  title: string
  content: string
  eventId: string
  kind: string
  dateTime: reminderAgentManager.LocalDateTime | null
}

interface AstronomyReminderListResult {
  ok: boolean
  items?: Array<AstronomyReminderItem>
  error?: string
  code?: number
}

export class AstronomyReminderService {
  // 兜底常量：正常路径用运行时 getBundleName() 派生；这里只在调用方没拿到上下文时使用。
  // 当前 debug 与 release 共用同一 bundleName（见 AppScope/app.json5）。
  private static readonly BUNDLE_NAME = 'com.joinother.skyinstrument'
  private static readonly ABILITY_NAME = 'QAbility'
  private static readonly GROUP_ID = 'skyinstrument-astronomy'

  private static errorResult(error: BusinessError, fallback: string): AstronomyReminderResult {
    const failure = error as BusinessError
    const code = typeof failure?.code === 'number' ? failure.code : undefined
    if (code === 1700001) {
      return { ok: false, error: '尚未开启通知权限，请在系统设置中允许本应用发送通知。', code: code, notificationEnabled: false }
    }
    if (code === 1700002) {
      return { ok: false, error: '本应用未获得「代理提醒」使用权限（需在 AGC 申请该受限权限并使用对应签名），当前提醒上限为 0。', code: code }
    }
    return { ok: false, error: failure?.message ?? fallback, code: code }
  }

  private static localDateTime(date: Date): reminderAgentManager.LocalDateTime {
    return {
      year: date.getFullYear(),
      month: date.getMonth() + 1,
      day: date.getDate(),
      hour: date.getHours(),
      minute: date.getMinutes(),
      second: date.getSeconds()
    }
  }

  public static async status(): Promise<AstronomyReminderResult> {
    let notificationEnabled = false
    try {
      notificationEnabled = await notificationManager.isNotificationEnabled()
      const reminders = await reminderAgentManager.getAllValidReminders()
      return { ok: true, notificationEnabled: notificationEnabled, reminderCount: reminders.length }
    } catch (error) {
      const result = AstronomyReminderService.errorResult(error, '后台代理提醒不可用')
      result.notificationEnabled = notificationEnabled
      return result
    }
  }

  public static async schedule(payload: AstronomyReminderRequest, bundleName: string = ''): Promise<AstronomyReminderResult> {
    if (payload.title.trim().length === 0 || payload.content.trim().length === 0) {
      return { ok: false, error: 'title and content are required' }
    }
    const date = new Date(payload.at)
    if (!Number.isFinite(date.getTime())) return { ok: false, error: 'at must be an ISO date-time' }
    if ((payload.reminderType ?? 'calendar') === 'calendar' && date.getTime() <= Date.now() + 30 * 1000) {
      return { ok: false, error: 'reminder must be at least 30 seconds in the future' }
    }

    const status = await AstronomyReminderService.status()
    if (status.ok !== true) return status
    if (status.notificationEnabled !== true) {
      return { ok: false, error: 'notification authorization is required', notificationEnabled: false }
    }

    const parameters: AstronomyWantParameters = {
      panel: payload.panel ?? 'astro',
      tab: payload.tab ?? 8,
      eventId: payload.eventId ?? '',
      kind: payload.kind ?? 'astronomy'
    }
    const kind = payload.reminderType ?? 'calendar'
    // 用运行时派生的包名，保证与「当前安装的」包一致。
    // 现状：debug 与 release 共用 com.joinother.skyinstrument（AppScope/app.json5），
    // 常量本来也对得上；将来若引入 debug 后缀或渠道包，这里也不需要改。
    const wantAgent: reminderAgentManager.WantAgent = {
      pkgName: bundleName.length > 0 ? bundleName : AstronomyReminderService.BUNDLE_NAME,
      abilityName: AstronomyReminderService.ABILITY_NAME,
      uri: 'skyinstrument://astronomy/reminder',
      parameters: parameters
    }
    let request: reminderAgentManager.ReminderRequest
    if (kind === 'timer') {
      const seconds = Math.max(60, Math.round(payload.triggerSeconds ?? 1800))
      const timerRequest: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: seconds,
        title: payload.title.trim(),
        content: payload.content.trim(),
        expiredContent: '倒计时提醒已结束，可打开星象仪继续观测。',
        groupId: AstronomyReminderService.GROUP_ID,
        tapDismissed: true,
        wantAgent: wantAgent
      }
      request = timerRequest
    } else if (kind === 'alarm') {
      const alarmRequest: reminderAgentManager.ReminderRequestAlarm = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
        hour: payload.hour ?? 21,
        minute: payload.minute ?? 0,
        daysOfWeek: payload.daysOfWeek ?? [1, 2, 3, 4, 5, 6, 7],
        title: payload.title.trim(),
        content: payload.content.trim(),
        expiredContent: '每日提醒已过期，可打开星象仪重新设置。',
        groupId: AstronomyReminderService.GROUP_ID,
        tapDismissed: true,
        wantAgent: wantAgent
      }
      request = alarmRequest
    } else {
      const calendarRequest: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: AstronomyReminderService.localDateTime(date),
        title: payload.title.trim(),
        content: payload.content.trim(),
        expiredContent: '天象提醒已过期，可打开星象仪查看年历。',
        groupId: AstronomyReminderService.GROUP_ID,
        tapDismissed: true,
        wantAgent: wantAgent
      }
      request = calendarRequest
    }

    try {
      const reminderId = await reminderAgentManager.publishReminder(request)
      return { ok: true, reminderId: reminderId, notificationEnabled: true }
    } catch (error) {
      return AstronomyReminderService.errorResult(error, '后台代理提醒发布失败')
    }
  }

  public static async list(): Promise<AstronomyReminderListResult> {
    try {
      const reminders = await reminderAgentManager.getAllValidReminders()
      const items = reminders.map((item): AstronomyReminderItem => {
        const request = item.reminderReq
        const dateTime = request.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR
          ? (request as reminderAgentManager.ReminderRequestCalendar).dateTime
          : undefined
        const eventId = request.wantAgent?.parameters?.['eventId']
        const kind = request.wantAgent?.parameters?.['kind']
        return {
          reminderId: item.reminderId,
          title: request.title ?? '',
          content: request.content ?? '',
          eventId: eventId === undefined ? '' : String(eventId),
          kind: kind === undefined ? 'astronomy' : String(kind),
          dateTime: dateTime ?? null
        }
      })
      return { ok: true, items: items }
    } catch (error) {
      const failure = AstronomyReminderService.errorResult(error, '无法读取后台代理提醒')
      return { ok: false, error: failure.error ?? '无法读取后台代理提醒', code: failure.code ?? 0 }
    }
  }

  public static async cancel(reminderId: number): Promise<AstronomyReminderResult> {
    if (!Number.isInteger(reminderId) || reminderId <= 0) {
      return { ok: false, error: 'reminderId must be a positive integer' }
    }
    try {
      await reminderAgentManager.cancelReminder(reminderId)
      return { ok: true, reminderId: reminderId }
    } catch (error) {
      return AstronomyReminderService.errorResult(error, '后台代理提醒取消失败')
    }
  }

  public static async cancelAll(): Promise<AstronomyReminderResult> {
    try {
      await reminderAgentManager.cancelAllReminders()
      return { ok: true }
    } catch (error) {
      return AstronomyReminderService.errorResult(error, '后台代理提醒清理失败')
    }
  }
}
