// Pure dynamic calendar feed contract, schema validator, and local overlay merge engine.
// Zero ArkUI imports so both HarmonyOS ArkTS and Node host tests execute the exact same logic.

import type { AstronomyCalendarEvent } from './AstronomyCalendarEvent'

export type RemoteCalendarAction = 'upsert' | 'enrich' | 'retract'

export interface RemoteCalendarRegionFilter {
  minLat?: number
  maxLat?: number
  minLon?: number
  maxLon?: number
  regionIds?: string[]
}

export interface RemoteCalendarEntry {
  id: string
  revision: number
  action: RemoteCalendarAction
  targetEventId?: string
  kind: string
  title: string
  titleEn?: string
  body: string
  bodyEn?: string
  at: number
  endAt?: number
  target?: string
  panel?: string
  observerPlanet?: string
  badge?: string
  badgeEn?: string
  highlight?: boolean
  regionFilter?: RemoteCalendarRegionFilter
  expiresAt?: number
}

export interface RemoteCalendarFeedDocument {
  schemaVersion: number
  generation: number
  updatedAt: number
  entries: RemoteCalendarEntry[]
}

export interface RemoteCalendarManifest {
  schemaVersion: number
  generation: number
  updatedAt: number
  feedPath: string
  bytes: number
  sha256: string
}

export interface RemoteCalendarMergeOptions {
  rangeStart: number
  rangeEnd: number
  observerPlanet: string
  observerLatitude?: number
  observerLongitude?: number
  regionId?: string
  language: string
  nowMs?: number
}

const VALID_ID_RE = /^[a-zA-Z0-9][a-zA-Z0-9:._-]{1,127}$/
const VALID_SHA256_RE = /^[a-f0-9]{64}$/
const MAX_FEED_ENTRIES = 200
const MAX_TITLE_LEN = 120
const MAX_BODY_LEN = 1600
const MAX_BADGE_LEN = 24

export const REMOTE_DYNAMIC_KINDS: string[] = [
  'aurora-alert',
  'comet-event',
  'spaceflight',
  'transient',
  'editorial'
]

export function isRemoteDynamicKind(kind: string): boolean {
  return REMOTE_DYNAMIC_KINDS.includes(kind)
}

export function normalizeRemoteEventId(rawId: string): string {
  const trimmed = rawId.trim()
  if (trimmed.startsWith('remote:')) return trimmed
  return 'remote:' + trimmed
}

function isPlainRecord(value: Object | null | undefined): boolean {
  return value !== null && value !== undefined && typeof value === 'object' && !Array.isArray(value)
}

function cleanText(raw: Object | undefined, maxLen: number): string {
  if (typeof raw !== 'string') return ''
  return raw.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '').trim().slice(0, maxLen)
}

export function validateRemoteCalendarManifest(raw: Object | null | undefined): RemoteCalendarManifest | undefined {
  if (!isPlainRecord(raw)) return undefined
  const obj = raw as Record<string, Object>
  const schemaVersion = Number(obj['schemaVersion'])
  const generation = Number(obj['generation'])
  const updatedAt = Number(obj['updatedAt'])
  const feedPath = typeof obj['feedPath'] === 'string' ? obj['feedPath'].trim() : ''
  const bytes = Number(obj['bytes'])
  const sha256 = typeof obj['sha256'] === 'string' ? obj['sha256'].trim().toLowerCase() : ''
  if (schemaVersion !== 1) return undefined
  if (!Number.isSafeInteger(generation) || generation < 1) return undefined
  if (!Number.isFinite(updatedAt) || updatedAt <= 0) return undefined
  if (!feedPath.startsWith('/v1/calendar/') || feedPath.includes('..') || !feedPath.endsWith('.json')) return undefined
  if (!Number.isSafeInteger(bytes) || bytes < 2 || bytes > 1024 * 1024) return undefined
  if (!VALID_SHA256_RE.test(sha256)) return undefined
  return {
    schemaVersion: 1,
    generation: generation,
    updatedAt: updatedAt,
    feedPath: feedPath,
    bytes: bytes,
    sha256: sha256
  }
}

function parseRegionFilter(raw: Object | undefined): RemoteCalendarRegionFilter | undefined {
  if (!isPlainRecord(raw)) return undefined
  const obj = raw as Record<string, Object>
  const out: RemoteCalendarRegionFilter = {}
  let hasAny = false
  const minLat = obj['minLat'] !== undefined ? Number(obj['minLat']) : NaN
  const maxLat = obj['maxLat'] !== undefined ? Number(obj['maxLat']) : NaN
  const minLon = obj['minLon'] !== undefined ? Number(obj['minLon']) : NaN
  const maxLon = obj['maxLon'] !== undefined ? Number(obj['maxLon']) : NaN
  if (Number.isFinite(minLat) && minLat >= -90 && minLat <= 90) { out.minLat = minLat; hasAny = true }
  if (Number.isFinite(maxLat) && maxLat >= -90 && maxLat <= 90) { out.maxLat = maxLat; hasAny = true }
  if (Number.isFinite(minLon) && minLon >= -180 && minLon <= 180) { out.minLon = minLon; hasAny = true }
  if (Number.isFinite(maxLon) && maxLon >= -180 && maxLon <= 180) { out.maxLon = maxLon; hasAny = true }
  if (Array.isArray(obj['regionIds'])) {
    const ids: string[] = []
    for (const item of (obj['regionIds'] as Object[])) {
      if (typeof item === 'string' && /^[a-zA-Z0-9_-]{1,40}$/.test(item.trim())) {
        ids.push(item.trim().toLowerCase())
      }
    }
    if (ids.length > 0) {
      out.regionIds = ids
      hasAny = true
    }
  }
  return hasAny ? out : undefined
}

export function validateRemoteCalendarFeed(raw: Object | null | undefined, nowMs: number = Date.now()): RemoteCalendarFeedDocument | undefined {
  if (!isPlainRecord(raw)) return undefined
  const obj = raw as Record<string, Object>
  const schemaVersion = Number(obj['schemaVersion'])
  const generation = Number(obj['generation'])
  const updatedAt = Number(obj['updatedAt'])
  if (schemaVersion !== 1 || !Number.isSafeInteger(generation) || generation < 1) return undefined
  if (!Number.isFinite(updatedAt) || updatedAt <= 0) return undefined
  if (!Array.isArray(obj['entries']) || (obj['entries'] as Object[]).length > MAX_FEED_ENTRIES) return undefined

  const rawEntries = obj['entries'] as Object[]
  const parsed: RemoteCalendarEntry[] = []
  for (const item of rawEntries) {
    if (!isPlainRecord(item)) continue
    const rec = item as Record<string, Object>
    const rawId = typeof rec['id'] === 'string' ? rec['id'].trim() : ''
    if (!VALID_ID_RE.test(rawId)) continue
    const revision = Number(rec['revision'])
    if (!Number.isSafeInteger(revision) || revision < 1) continue
    const action = typeof rec['action'] === 'string' ? rec['action'].trim() : ''
    if (action !== 'upsert' && action !== 'enrich' && action !== 'retract') continue

    const targetEventId = typeof rec['targetEventId'] === 'string' ? rec['targetEventId'].trim() : undefined
    if (targetEventId !== undefined && targetEventId.length > 0 && !VALID_ID_RE.test(targetEventId)) continue

    const expiresAt = rec['expiresAt'] !== undefined ? Number(rec['expiresAt']) : undefined
    if (expiresAt !== undefined && (!Number.isFinite(expiresAt) || expiresAt <= nowMs)) continue

    const kind = cleanText(rec['kind'], 40) || 'transient'
    const title = cleanText(rec['title'], MAX_TITLE_LEN)
    const titleEn = cleanText(rec['titleEn'], MAX_TITLE_LEN)
    const body = cleanText(rec['body'], MAX_BODY_LEN)
    const bodyEn = cleanText(rec['bodyEn'], MAX_BODY_LEN)
    const at = rec['at'] !== undefined ? Number(rec['at']) : 0
    const endAt = rec['endAt'] !== undefined ? Number(rec['endAt']) : undefined

    if (action === 'upsert') {
      if (title.length === 0 || !Number.isFinite(at) || at <= 0) continue
    } else if (action === 'enrich') {
      if ((targetEventId === undefined || targetEventId.length === 0) && rawId.length === 0) continue
      if (body.length === 0 && bodyEn.length === 0 && title.length === 0) continue
    }

    const observerPlanet = cleanText(rec['observerPlanet'], 40) || 'Earth'
    const target = cleanText(rec['target'], 80)
    const panel = cleanText(rec['panel'], 32) || 'calendar'
    const badge = cleanText(rec['badge'], MAX_BADGE_LEN)
    const badgeEn = cleanText(rec['badgeEn'], MAX_BADGE_LEN)
    const entry: RemoteCalendarEntry = {
      id: action === 'upsert' ? normalizeRemoteEventId(rawId) : rawId,
      revision: revision,
      action: action as RemoteCalendarAction,
      kind: kind,
      title: title,
      body: body,
      at: Number.isFinite(at) ? at : 0,
      observerPlanet: observerPlanet,
      panel: panel
    }
    if (targetEventId !== undefined && targetEventId.length > 0) entry.targetEventId = targetEventId
    if (titleEn.length > 0) entry.titleEn = titleEn
    if (bodyEn.length > 0) entry.bodyEn = bodyEn
    if (endAt !== undefined && Number.isFinite(endAt) && endAt > entry.at) entry.endAt = endAt
    if (target.length > 0) entry.target = target
    if (badge.length > 0) entry.badge = badge
    if (badgeEn.length > 0) entry.badgeEn = badgeEn
    if (rec['highlight'] === true) entry.highlight = true
    const regionFilter = parseRegionFilter(rec['regionFilter'])
    if (regionFilter !== undefined) entry.regionFilter = regionFilter
    if (expiresAt !== undefined && Number.isFinite(expiresAt)) entry.expiresAt = expiresAt
    parsed.push(entry)
  }

  return {
    schemaVersion: 1,
    generation: generation,
    updatedAt: updatedAt,
    entries: parsed
  }
}

export function matchesRemoteRegionFilter(
  filter: RemoteCalendarRegionFilter | undefined,
  latitude: number | undefined,
  longitude: number | undefined,
  regionId: string | undefined
): boolean {
  if (filter === undefined) return true
  const normRegion = (regionId ?? '').trim().toLowerCase()
  if (filter.regionIds !== undefined && filter.regionIds.length > 0 && normRegion.length > 0 && normRegion !== 'follow') {
    if (!filter.regionIds.includes(normRegion)) return false
  }
  if (latitude !== undefined && Number.isFinite(latitude)) {
    if (filter.minLat !== undefined && latitude < filter.minLat) return false
    if (filter.maxLat !== undefined && latitude > filter.maxLat) return false
  }
  if (longitude !== undefined && Number.isFinite(longitude)) {
    if (filter.minLon !== undefined && longitude < filter.minLon) return false
    if (filter.maxLon !== undefined && longitude > filter.maxLon) return false
  }
  return true
}

function deduplicateLatestEntries(entries: RemoteCalendarEntry[], nowMs: number): RemoteCalendarEntry[] {
  const latestByKey = new Map<string, RemoteCalendarEntry>()
  for (const entry of entries) {
    if (entry.expiresAt !== undefined && entry.expiresAt <= nowMs) continue
    const key = entry.action + '|' + (entry.targetEventId ?? entry.id)
    const prev = latestByKey.get(key)
    if (prev === undefined || entry.revision >= prev.revision) {
      latestByKey.set(key, entry)
    }
  }
  const out: RemoteCalendarEntry[] = []
  latestByKey.forEach((val: RemoteCalendarEntry) => { out.push(val) })
  return out
}

export function retractedRemoteEventIds(entries: RemoteCalendarEntry[], nowMs: number = Date.now()): string[] {
  const deduped = deduplicateLatestEntries(entries, nowMs)
  const ids: string[] = []
  for (const entry of deduped) {
    if (entry.action !== 'retract') continue
    const id = entry.targetEventId ?? entry.id
    if (id.length > 0 && !ids.includes(id)) ids.push(id)
    const norm = normalizeRemoteEventId(id)
    if (!ids.includes(norm)) ids.push(norm)
  }
  return ids
}

function defaultRemoteBadge(kind: string, isZh: boolean): string {
  if (kind === 'aurora-alert') return isZh ? '极光预警' : 'Aurora Alert'
  if (kind === 'comet-event') return isZh ? '彗星动态' : 'Comet Watch'
  if (kind === 'spaceflight') return isZh ? '航天动态' : 'Spaceflight'
  if (kind === 'editorial') return isZh ? '观星攻略' : 'Sky Guide'
  return isZh ? '实时动态' : 'Live Alert'
}

export function mergeRemoteCalendarEvents(
  localEvents: AstronomyCalendarEvent[],
  entries: RemoteCalendarEntry[],
  options: RemoteCalendarMergeOptions
): AstronomyCalendarEvent[] {
  if (entries.length === 0) return localEvents
  const nowMs = options.nowMs ?? Date.now()
  const isZh = options.language.toLowerCase().startsWith('zh')
  const planet = (options.observerPlanet.trim().length > 0 ? options.observerPlanet.trim() : 'Earth').toLowerCase()
  const deduped = deduplicateLatestEntries(entries, nowMs)

  const retracted = new Set<string>()
  const enrichMap = new Map<string, RemoteCalendarEntry>()
  const upserts: RemoteCalendarEntry[] = []

  for (const entry of deduped) {
    const entryPlanet = (entry.observerPlanet ?? 'Earth').trim().toLowerCase()
    if (entryPlanet !== planet) continue
    if (entry.action === 'retract') {
      retracted.add(entry.id)
      if (entry.targetEventId !== undefined) retracted.add(entry.targetEventId)
      retracted.add(normalizeRemoteEventId(entry.targetEventId ?? entry.id))
      continue
    }
    if (!matchesRemoteRegionFilter(entry.regionFilter, options.observerLatitude, options.observerLongitude, options.regionId)) {
      continue
    }
    if (entry.action === 'enrich') {
      const targetKey = entry.targetEventId ?? entry.id
      enrichMap.set(targetKey, entry)
    } else if (entry.action === 'upsert') {
      upserts.push(entry)
    }
  }

  const merged: AstronomyCalendarEvent[] = []
  const existingIds = new Set<string>()

  for (const local of localEvents) {
    if (retracted.has(local.id)) continue
    const enrich = enrichMap.get(local.id)
    if (enrich !== undefined) {
      const extraBody = isZh ? (enrich.body || enrich.bodyEn || '') : (enrich.bodyEn || enrich.body || '')
      const badge = isZh ? (enrich.badge || defaultRemoteBadge('editorial', true)) : (enrich.badgeEn || enrich.badge || defaultRemoteBadge('editorial', false))
      const combinedBody = extraBody.length > 0
        ? (local.body.length > 0 ? `${local.body}\n\n【${badge}】${extraBody}` : extraBody)
        : local.body
      const cloned: AstronomyCalendarEvent = {
        id: local.id,
        kind: local.kind,
        title: local.title,
        at: local.at,
        jd: local.jd,
        body: combinedBody,
        target: local.target,
        panel: local.panel,
        tab: local.tab,
        timeScale: local.timeScale,
        phaseIndex: local.phaseIndex,
        distanceKm: local.distanceKm,
        isSupermoon: local.isSupermoon,
        subtype: local.subtype,
        direction: local.direction,
        primary: local.primary,
        secondary: local.secondary,
        alignment: local.alignment,
        separationDegrees: local.separationDegrees,
        observerPlanet: local.observerPlanet,
        showerCode: local.showerCode,
        satCatalogId: local.satCatalogId,
        satArchetype: local.satArchetype,
        satMaxAlt: local.satMaxAlt,
        satVisible: local.satVisible,
        satDurationSec: local.satDurationSec,
        satAzimuthSummary: local.satAzimuthSummary,
        satStartAt: local.satStartAt,
        satEndAt: local.satEndAt,
        satStartAz: local.satStartAz,
        satEndAz: local.satEndAz,
        satMag: local.satMag,
        eclipseMagnitude: local.eclipseMagnitude,
        umbralMagnitude: local.umbralMagnitude,
        penumbralMagnitude: local.penumbralMagnitude,
        localVisible: local.localVisible,
        localFullVisible: local.localFullVisible,
        localDaytime: local.localDaytime,
        localMagnitude: local.localMagnitude,
        localMaxAlt: local.localMaxAlt,
        eclipseStartAt: local.eclipseStartAt,
        eclipseEndAt: local.eclipseEndAt,
        eclipseMap: local.eclipseMap,
        magnitude: local.magnitude,
        twilightAltDeg: local.twilightAltDeg,
        twilightAt: local.twilightAt,
        planetSetRiseAt: local.planetSetRiseAt,
        twilightOffsetMin: local.twilightOffsetMin,
        earthHelioLonDeg: local.earthHelioLonDeg,
        planetHelioLonDeg: local.planetHelioLonDeg,
        orbitRatio: local.orbitRatio,
        rocketPresetId: local.rocketPresetId,
        rocketSiteId: local.rocketSiteId,
        rocketVehicleId: local.rocketVehicleId,
        rocketLaunchTimeUtc: local.rocketLaunchTimeUtc,
        rocketAzimuthDeg: local.rocketAzimuthDeg,
        rocketTargetOrbit: local.rocketTargetOrbit,
        rocketBadge: local.rocketBadge,
        isRemote: local.isRemote,
        remoteEnriched: true,
        remoteBadge: badge,
        remoteRevision: enrich.revision,
        remoteHighlight: enrich.highlight === true ? true : local.remoteHighlight
      }
      merged.push(cloned)
      existingIds.add(cloned.id)
    } else {
      merged.push(local)
      existingIds.add(local.id)
    }
  }

  for (const entry of upserts) {
    const id = normalizeRemoteEventId(entry.id)
    if (retracted.has(id) || existingIds.has(id)) continue
    if (entry.at < options.rangeStart || entry.at >= options.rangeEnd) continue
    const title = isZh ? (entry.title || entry.titleEn || '') : (entry.titleEn || entry.title || '')
    const body = isZh ? (entry.body || entry.bodyEn || '') : (entry.bodyEn || entry.body || '')
    const badge = isZh
      ? (entry.badge || defaultRemoteBadge(entry.kind, true))
      : (entry.badgeEn || entry.badge || defaultRemoteBadge(entry.kind, false))
    const ev: AstronomyCalendarEvent = {
      id: id,
      kind: entry.kind,
      title: title,
      at: entry.at,
      jd: entry.at / 86400000 + 2440587.5,
      body: body,
      target: entry.target ?? '',
      panel: entry.panel ?? 'calendar',
      tab: 0,
      observerPlanet: entry.observerPlanet ?? 'Earth',
      isRemote: true,
      remoteBadge: badge,
      remoteRevision: entry.revision,
      remoteHighlight: entry.highlight === true,
      remoteEndAt: entry.endAt
    }
    merged.push(ev)
    existingIds.add(id)
  }

  merged.sort((left: AstronomyCalendarEvent, right: AstronomyCalendarEvent) =>
    left.at - right.at || left.id.localeCompare(right.id))
  return merged
}

export function countRemoteDynamicEvents(events: AstronomyCalendarEvent[]): number {
  let count = 0
  for (const ev of events) {
    if (ev.isRemote === true) count++
  }
  return count
}
