import { AstronomyRoute, routeError, validServiceId } from './AstronomyNotificationPolicy'

export interface ReminderReadbackDate {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second?: number
}

export interface ReminderReadbackWant {
  pkgName: string
  abilityName: string
}

export interface ReminderReadback {
  notificationId?: number
  reminderType: number
  title?: string
  content?: string
  wantAgent?: ReminderReadbackWant
  dateTime?: ReminderReadbackDate
  triggerTimeInSeconds?: number
  hour?: number
  minute?: number
  daysOfWeek?: number[]
  repeatMonths?: number[]
  repeatDays?: number[]
}

export interface ReminderMetadataEntry {
  reminderId: number
  notificationId: number
  fingerprint: string
  bundleName: string
  eventKey: string
  signature: string
  route: AstronomyRoute
  leadMinutes: number
}

export interface ReminderMetadataJournal {
  version: number
  nextNotificationId: number
  entries: ReminderMetadataEntry[]
}

export function reminderRequestFingerprint(request: ReminderReadback, includeNotificationId: boolean = true): string {
  if (!validServiceId(request.notificationId) || typeof request.title !== 'string' || typeof request.content !== 'string' ||
    !request.wantAgent?.pkgName || !request.wantAgent.abilityName) return ''
  let timing: number[] = []
  if (request.reminderType === 1) {
    const date = request.dateTime
    if (date === undefined) return ''
    timing = [date.year, date.month, date.day, date.hour, date.minute, date.second ?? 0]
  } else if (request.reminderType === 0) {
    timing = []
  } else if (request.reminderType === 2) {
    timing = [request.hour ?? NaN, request.minute ?? NaN]
  } else return ''
  if (timing.some(value => !Number.isInteger(value))) return ''
  return JSON.stringify([includeNotificationId ? request.notificationId : null, request.reminderType,
    request.title, request.content, request.wantAgent.pkgName, request.wantAgent.abilityName, timing,
    [...(request.daysOfWeek ?? [])].sort(), [...(request.repeatMonths ?? [])].sort(), [...(request.repeatDays ?? [])].sort()])
}

export function validReminderMetadata(value: ReminderMetadataJournal): boolean {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return false
  const journal = value
  if (journal.version !== 1 || !Number.isInteger(journal.nextNotificationId) || journal.nextNotificationId < 1000000000 ||
    journal.nextNotificationId > 2147483648 || !Array.isArray(journal.entries) || journal.entries.length > 128) return false
  const identifiers = new Set<number>()
  for (const entry of journal.entries) {
    if (typeof entry !== 'object' || entry === null || Array.isArray(entry) ||
      !(entry.reminderId === -1 || validServiceId(entry.reminderId)) || !validServiceId(entry.notificationId) ||
      entry.notificationId < 1000000000 || entry.notificationId >= journal.nextNotificationId || identifiers.has(entry.notificationId) ||
      typeof entry.fingerprint !== 'string' || !entry.fingerprint || typeof entry.eventKey !== 'string' ||
      typeof entry.signature !== 'string' || !entry.signature || typeof entry.bundleName !== 'string' || !entry.bundleName ||
      !Number.isFinite(entry.leadMinutes) || entry.leadMinutes < 0 || routeError(entry.route)) return false
    identifiers.add(entry.notificationId)
  }
  return true
}

export function reminderRouteUri(route: AstronomyRoute, notificationId: number): string {
  return 'skyinstrument://astronomy/reminder?notificationId=' + notificationId + '&route=' + encodeURIComponent(JSON.stringify(route))
}

export function reminderRouteFromUri(uri: string): AstronomyRoute | undefined {
  const prefix = 'skyinstrument://astronomy/reminder?notificationId='
  if (typeof uri !== 'string' || !uri.startsWith(prefix) || uri.length > 20000) return undefined
  const separator = uri.indexOf('&route=', prefix.length)
  if (separator < 0 || !/^\d+$/.test(uri.slice(prefix.length, separator)) || !validServiceId(Number(uri.slice(prefix.length, separator)))) return undefined
  try {
    const route: AstronomyRoute = JSON.parse(decodeURIComponent(uri.slice(separator + 7))) as AstronomyRoute
    if (routeError(route) || !['calendar', 'astro', 'satellites'].includes(route.panel ?? '')) return undefined
    return route
  } catch (_) { return undefined }
}
