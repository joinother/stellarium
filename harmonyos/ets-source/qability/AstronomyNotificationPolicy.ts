export type AstronomyReminderKind = 'timer' | 'calendar' | 'alarm'

export interface AstronomyRoute {
  subscription?: string
  panel?: string
  tab?: number
  eventId?: string
  kind?: string
  eventAt?: string
  jd?: number
  target?: string
}

export interface AstronomyQuietHours {
  enabled: boolean
  startMinutes: number
  endMinutes: number
}

export interface AstronomyReminderPreferences {
  astronomyEventsEnabled?: boolean
  satellitePassEnabled?: boolean
  digestEnabled?: boolean
  dndEnabled?: boolean
  dndStartMinutes?: number
  dndEndMinutes?: number
}

export interface NotificationPreferenceSnapshot {
  astronomyEventsEnabled: boolean
  satellitePassEnabled?: boolean
  digestEnabled?: boolean
  subscriptionsVersion?: number
  dndEnabled: boolean
  dndStartMinutes: number
  dndEndMinutes: number
  passLeadMinutes: number
}

export function validNotificationPreferences(value: unknown): value is NotificationPreferenceSnapshot {
  return record(value) && typeof value.astronomyEventsEnabled === 'boolean' && typeof value.dndEnabled === 'boolean' &&
    (value.satellitePassEnabled === undefined || typeof value.satellitePassEnabled === 'boolean') &&
    (value.digestEnabled === undefined || typeof value.digestEnabled === 'boolean') &&
    (value.subscriptionsVersion === undefined || value.subscriptionsVersion === 1) &&
    integer(value.dndStartMinutes, 0, 1439) && integer(value.dndEndMinutes, 0, 1439) && integer(value.passLeadMinutes, 0, 60)
}

export interface ReminderPolicyInput extends AstronomyRoute {
  at?: string
  title: string
  content: string
  reminderType?: AstronomyReminderKind
  triggerSeconds?: number
  hour?: number
  minute?: number
  daysOfWeek?: number[]
  leadMinutes?: number
  quietHours?: AstronomyQuietHours
}

export interface NotificationPolicyInput {
  id: number
  title: string
  text: string
  additionalText?: string
  lines?: string[]
  route?: AstronomyRoute
}

export interface AstronomyServiceResult {
  ok: boolean
  error?: string
  code?: number
  reason?: string
  notificationEnabled?: boolean
}

export interface NormalizedReminder {
  title: string
  content: string
  reminderType: AstronomyReminderKind
  fireAt: number
  triggerSeconds: number
  hour: number
  minute: number
  daysOfWeek: number[]
  leadMinutes: number
  route: AstronomyRoute
  eventKey: string
}

export interface ReminderValidation extends AstronomyServiceResult {
  value?: NormalizedReminder
}

export interface NotificationValidation extends AstronomyServiceResult {
  value?: NotificationPolicyInput
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export function validServiceId(value: unknown): boolean {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 2147483647
}

function integer(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= minimum && value <= maximum
}

function text(value: unknown, maximum: number, empty: boolean = false): value is string {
  return typeof value === 'string' && (empty || value.trim().length > 0) &&
    utf8Length(value) <= maximum && !/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value)
}

function utf8Length(value: string): number {
  let length = 0
  for (const character of value) {
    const code = character.codePointAt(0) ?? 0
    length += code <= 0x7f ? 1 : code <= 0x7ff ? 2 : code <= 0xffff ? 3 : 4
  }
  return length
}

export function parseEventTime(value: unknown): number {
  if (typeof value !== 'string') return NaN
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?(Z|[+-]\d{2}:\d{2})?$/.exec(value)
  if (!match) return NaN
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const hour = Number(match[4])
  const minute = Number(match[5])
  const second = Number(match[6] ?? 0)
  const monthDays = new Date(Date.UTC(year, month, 0)).getUTCDate()
  if (year < 100 || month < 1 || month > 12 || day < 1 || day > monthDays ||
    hour > 23 || minute > 59 || second > 59) return NaN
  const date = new Date(value)
  if (!match[8] && (date.getHours() !== hour || date.getMinutes() !== minute)) return NaN
  return date.getTime()
}

function jdTime(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? (value - 2440587.5) * 86400000 : NaN
}

export function routeError(value: unknown): string {
  if (!record(value)) return 'route must be an object'
  if (value.subscription !== undefined && value.subscription !== 'astronomy' && value.subscription !== 'satellite') return 'invalid subscription category'
  for (const key of ['panel', 'eventId', 'kind', 'target']) {
    if (value[key] !== undefined && !text(value[key], 512, key !== 'panel')) return `${key} must be text (at most 512 UTF-8 bytes)`
  }
  if (value.tab !== undefined && !integer(value.tab, 0, 100)) return 'tab must be an integer from 0 to 100'
  if (value.eventAt !== undefined && !Number.isFinite(parseEventTime(value.eventAt))) return 'eventAt must be an ISO date-time'
  if (value.jd !== undefined && (!Number.isFinite(jdTime(value.jd)) || !Number.isFinite(new Date(jdTime(value.jd)).getTime()))) return 'jd must be a finite representable Julian date'
  if (value.eventAt !== undefined && value.jd !== undefined && Math.abs(parseEventTime(value.eventAt) - jdTime(value.jd)) > 1000) return 'eventAt and jd disagree'
  return ''
}

export function normalizeRoute(route: AstronomyRoute): AstronomyRoute {
  const eventTime = route.eventAt !== undefined ? parseEventTime(route.eventAt) : jdTime(route.jd)
  return {
    subscription: route.subscription,
    panel: route.panel ?? 'astro', tab: route.tab ?? 8,
    eventId: route.eventId?.trim() ?? '', kind: route.kind?.trim() || 'astronomy',
    target: route.target?.trim() ?? '',
    eventAt: Number.isFinite(eventTime) ? new Date(Math.round(eventTime)).toISOString() : undefined,
    jd: Number.isFinite(eventTime) ? eventTime / 86400000 + 2440587.5 : undefined
  }
}

export function reminderEventKey(type: string, kind: string, eventId: string, eventTime: number, target: string = ''): string {
  if (!eventId && type !== 'calendar') return ''
  return JSON.stringify([type, kind, eventId || target, type === 'calendar' ? Math.floor(eventTime / 1000) : 0])
}

export function isQuietMinute(minute: number, start: number, end: number): boolean {
  if (start === end) return true
  return start < end ? minute >= start && minute < end : minute >= start || minute < end
}

function invalid(error: string, reason: string = 'validation'): AstronomyServiceResult {
  return { ok: false, error: error, reason: reason }
}

export function validateReminder(input: unknown, now: number, preferences?: AstronomyReminderPreferences): ReminderValidation {
  if (!record(input)) return invalid('reminder payload must be an object')
  if (!text(input.title, 1024) || !text(input.content, 3072)) return invalid('title/content must be non-empty text within 1024/3072 UTF-8 bytes')
  const routeFailure = routeError(input)
  if (routeFailure) return invalid(routeFailure)
  const payload = input as unknown as ReminderPolicyInput
  const type = payload.reminderType ?? 'calendar'
  if (type !== 'calendar' && type !== 'timer' && type !== 'alarm') return invalid('unknown reminderType')
  if (payload.leadMinutes !== undefined && (!integer(payload.leadMinutes, 0, 525600) || type !== 'calendar')) return invalid('leadMinutes requires a calendar reminder and an integer from 0 to 525600')
  const route = normalizeRoute(payload)
  let eventTime = route.eventAt !== undefined ? parseEventTime(route.eventAt) : parseEventTime(payload.at)
  let fireAt = eventTime
  let leadMinutes = payload.leadMinutes ?? 0
  const seconds = payload.triggerSeconds ?? 1800
  const hour = payload.hour ?? 21
  const minute = payload.minute ?? 0
  const days = payload.daysOfWeek ?? [1, 2, 3, 4, 5, 6, 7]
  if (type === 'calendar') {
    if (!Number.isFinite(eventTime)) return invalid('at, eventAt or jd must specify an event time')
    if (payload.at !== undefined && !Number.isFinite(parseEventTime(payload.at))) return invalid('at must be an ISO date-time')
    if (route.eventAt !== undefined && payload.at !== undefined) {
      fireAt = parseEventTime(payload.at)
      if (payload.leadMinutes !== undefined && Math.abs(fireAt - (eventTime - leadMinutes * 60000)) > 1000) return invalid('at disagrees with eventAt minus leadMinutes')
      leadMinutes = (eventTime - fireAt) / 60000
      if (leadMinutes < 0) return invalid('at must not be later than eventAt')
    } else {
      fireAt = eventTime - leadMinutes * 60000
    }
    fireAt = Math.floor(fireAt / 60000) * 60000
    if (fireAt <= now + 30000) return invalid('reminder must be more than 30 seconds in the future', 'too-soon')
    route.eventAt = new Date(Math.round(eventTime)).toISOString()
    route.jd = eventTime / 86400000 + 2440587.5
  } else if (type === 'timer') {
    if (!integer(seconds, 1, 2147483647)) return invalid('triggerSeconds must be a positive integer')
    fireAt = now + seconds * 1000
  } else {
    if (!integer(hour, 0, 23) || !integer(minute, 0, 59)) return invalid('hour/minute are outside their valid ranges')
    if (!Array.isArray(days) || days.length > 7 || days.some(day => !integer(day, 1, 7)) || new Set(days).size !== days.length) return invalid('daysOfWeek must contain unique integers from 1 to 7')
  }
  if (preferences !== undefined) {
    if (!record(preferences)) return invalid('preferences must be an object')
    for (const key of ['astronomyEventsEnabled', 'satellitePassEnabled', 'digestEnabled', 'dndEnabled']) {
      if (preferences[key] !== undefined && typeof preferences[key] !== 'boolean') return invalid(`${key} must be boolean`)
    }
    const enabled = route.kind === 'satellite-pass' ? preferences.satellitePassEnabled :
      route.kind === 'digest' ? preferences.digestEnabled : preferences.astronomyEventsEnabled
    if (type === 'calendar' && route.kind !== 'calendar' && enabled === false) return invalid('此类提醒已在偏好中关闭。', 'category-disabled')
  }
  let quiet = payload.quietHours
  if (quiet !== undefined && (!record(quiet) || typeof quiet.enabled !== 'boolean' ||
    !integer(quiet.startMinutes, 0, 1439) || !integer(quiet.endMinutes, 0, 1439))) return invalid('quietHours requires enabled and minute values from 0 to 1439')
  if (preferences?.dndEnabled === true) {
    if (!integer(preferences.dndStartMinutes, 0, 1439) || !integer(preferences.dndEndMinutes, 0, 1439)) return invalid('enabled quiet hours require valid start/end minutes')
    const preferenceQuiet: AstronomyQuietHours = { enabled: true, startMinutes: preferences.dndStartMinutes, endMinutes: preferences.dndEndMinutes }
    const triggerMinute = type === 'alarm' ? hour * 60 + minute : new Date(fireAt).getHours() * 60 + new Date(fireAt).getMinutes()
    if (isQuietMinute(triggerMinute, preferenceQuiet.startMinutes, preferenceQuiet.endMinutes)) return invalid('提醒时间位于静默时段，请选择其它时间或调整偏好。', 'quiet-hours')
  }
  if (quiet?.enabled === true) {
    const triggerMinute = type === 'alarm' ? hour * 60 + minute : new Date(fireAt).getHours() * 60 + new Date(fireAt).getMinutes()
    if (isQuietMinute(triggerMinute, quiet.startMinutes, quiet.endMinutes)) return invalid('提醒时间位于静默时段，请选择其它时间或调整偏好。', 'quiet-hours')
  }
  return { ok: true, value: {
    title: payload.title.trim(), content: payload.content.trim(), reminderType: type,
    fireAt: fireAt, triggerSeconds: seconds, hour: hour, minute: minute,
    daysOfWeek: days.slice().sort((left, right) => left - right), leadMinutes: leadMinutes,
    route: route, eventKey: (route.subscription === undefined ? '' : 'subscription:' + route.subscription + ':') +
      reminderEventKey(type, route.kind ?? 'astronomy', route.eventId ?? '', eventTime, route.target)
  } }
}

export function validateNotification(input: unknown): NotificationValidation {
  if (!record(input) || !validServiceId(input.id)) return invalid('id must be a non-negative 32-bit integer')
  if (!text(input.title, 1024) || !text(input.text, 3072)) return invalid('title/text must be non-empty text within 1024/3072 UTF-8 bytes')
  if (input.additionalText !== undefined && !text(input.additionalText, 3072, true)) return invalid('additionalText must be text within 3072 UTF-8 bytes')
  if (input.lines !== undefined && (!Array.isArray(input.lines) || input.lines.length < 1 || input.lines.length > 3 ||
    input.lines.some(line => !text(line, 1024)))) return invalid('lines must contain one to three non-empty strings within 1024 UTF-8 bytes each')
  if (input.route !== undefined) {
    const failure = routeError(input.route)
    if (failure) return invalid(failure)
  }
  const payload = input as unknown as NotificationPolicyInput
  return { ok: true, value: {
    id: payload.id, title: payload.title.trim(), text: payload.text.trim(),
    additionalText: payload.additionalText?.trim(), lines: payload.lines?.map(line => line.trim()),
    route: payload.route === undefined ? undefined : normalizeRoute(payload.route)
  } }
}

export function serviceFailure(error: unknown, fallback: string): AstronomyServiceResult {
  const code = record(error) && typeof error.code === 'number' ? error.code : undefined
  const message = record(error) && typeof error.message === 'string' && error.message.length > 0 ? error.message : fallback
  if (code === 1700001) return { ok: false, code: code, reason: 'notification-disabled', notificationEnabled: false, error: '尚未开启通知权限，请在系统设置中允许本应用发送通知。' }
  if (code === 1700002) return { ok: false, code: code, reason: 'quota-or-entitlement', error: '提醒数量已达系统上限，或当前签名未获代理提醒权益。已有提醒保持不变，请检查提醒列表与开放能力。' }
  if (code === 201) return { ok: false, code: code, reason: 'permission-denied', error: '系统拒绝代理提醒权限，请检查权限声明与签名权益。' }
  return { ok: false, code: code, reason: 'system-error', error: message }
}
