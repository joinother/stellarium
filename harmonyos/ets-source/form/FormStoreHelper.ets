import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { hilog } from '@kit.PerformanceAnalysisKit'
import {
  CardInstanceConfig,
  applyAnalyticalTimePreview,
  applyCardConfigToSnapshot,
  applySolarShowcaseProjection,
  applyTimeline48hToCard,
  buildFallbackCardForPlanet,
  clampTimeOffsetHours,
  defaultAstronomyCard,
  defaultCardConfig,
  formatPreviewTimeBadge,
  normalizeAstronomyCard,
  normalizeCardConfig
} from './AstronomyCardData'

export const CARD_STORE: string = 'sky_instrument_card'
export const CARD_SNAPSHOT_KEY: string = 'almanacSnapshot'
export const CARD_TIMELINE_KEY: string = 'timeline48hSnapshot'
const FORM_CONFIG_PREFIX: string = 'formConfig_'
const FORM_KIND_PREFIX: string = 'formKind_'
const FORM_TEXT_COLOR_PREFIX: string = 'formTextColor_'
const FORM_TIME_OFFSET_PREFIX: string = 'formOffset_'
const REMINDED_EVENTS_KEY: string = 'widgetRemindedEvents'
const DOMAIN: number = 0xD003
const TAG: string = 'SkyFormStore'

export interface WidgetRemindedEntry {
  eventId: string
  reminderId: number
}

function planetSnapshotKey(planet: string): string {
  return CARD_SNAPSHOT_KEY + '_' + planet.trim().toLowerCase()
}

function planetTimelineKey(planet: string): string {
  return CARD_TIMELINE_KEY + '_' + planet.trim().toLowerCase()
}

export function openFreshCardStore(context: common.Context): preferences.Preferences | undefined {
  try {
    preferences.removePreferencesFromCacheSync(context, CARD_STORE)
  } catch (_) {
    // Ignore cache miss on first open
  }
  try {
    return preferences.getPreferencesSync(context, { name: CARD_STORE })
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'openFreshCardStore failed: %{public}s', String(error))
    return undefined
  }
}

export function readFormConfig(context: common.Context, formId: string): CardInstanceConfig {
  if (formId.length === 0) return defaultCardConfig()
  const store = openFreshCardStore(context)
  if (store === undefined) return defaultCardConfig()
  try {
    const raw = store.getSync(FORM_CONFIG_PREFIX + formId, '')
    return normalizeCardConfig(typeof raw === 'string' ? raw : '')
  } catch (_) {
    return defaultCardConfig()
  }
}

export function writeFormConfig(context: common.Context, formId: string, config: CardInstanceConfig): void {
  if (formId.length === 0) return
  const store = openFreshCardStore(context)
  if (store === undefined) return
  try {
    store.putSync(FORM_CONFIG_PREFIX + formId, JSON.stringify(config))
    store.flushSync()
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'writeFormConfig failed: %{public}s', String(error))
  }
}

export function removeFormMetadata(context: common.Context, formId: string): void {
  if (formId.length === 0) return
  const store = openFreshCardStore(context)
  if (store === undefined) return
  try {
    if (store.hasSync(FORM_CONFIG_PREFIX + formId)) store.deleteSync(FORM_CONFIG_PREFIX + formId)
    if (store.hasSync(FORM_KIND_PREFIX + formId)) store.deleteSync(FORM_KIND_PREFIX + formId)
    if (store.hasSync(FORM_TEXT_COLOR_PREFIX + formId)) store.deleteSync(FORM_TEXT_COLOR_PREFIX + formId)
    if (store.hasSync(FORM_TIME_OFFSET_PREFIX + formId)) store.deleteSync(FORM_TIME_OFFSET_PREFIX + formId)
    store.flushSync()
  } catch (_) {
  }
}

export function writeFormTextColor(context: common.Context, formId: string, color: string): void {
  if (formId.length === 0 || color.length === 0) return
  const store = openFreshCardStore(context)
  if (store === undefined) return
  try {
    store.putSync(FORM_TEXT_COLOR_PREFIX + formId, color)
    store.flushSync()
  } catch (_) {
  }
}

export function readFormTextColor(context: common.Context, formId: string): string {
  if (formId.length === 0) return ''
  const store = openFreshCardStore(context)
  if (store === undefined) return ''
  try {
    const raw = store.getSync(FORM_TEXT_COLOR_PREFIX + formId, '')
    return typeof raw === 'string' ? raw : ''
  } catch (_) {
    return ''
  }
}

export function readFormTimeOffset(context: common.Context, formId: string): number {
  if (formId.length === 0) return 0
  const store = openFreshCardStore(context)
  if (store === undefined) return 0
  try {
    const raw = store.getSync(FORM_TIME_OFFSET_PREFIX + formId, '0')
    return clampTimeOffsetHours(Number(raw))
  } catch (_) {
    return 0
  }
}

export function writeFormTimeOffset(context: common.Context, formId: string, offsetHours: number): void {
  if (formId.length === 0) return
  const store = openFreshCardStore(context)
  if (store === undefined) return
  try {
    store.putSync(FORM_TIME_OFFSET_PREFIX + formId, String(clampTimeOffsetHours(offsetHours)))
    store.flushSync()
  } catch (_) {
  }
}

export function readRemindedEntries(context: common.Context): WidgetRemindedEntry[] {
  const store = openFreshCardStore(context)
  if (store === undefined) return []
  try {
    const raw = store.getSync(REMINDED_EVENTS_KEY, '[]')
    if (typeof raw !== 'string' || raw.length === 0) return []
    const parsed = JSON.parse(raw) as Array<WidgetRemindedEntry>
    return Array.isArray(parsed) ? parsed : []
  } catch (_) {
    return []
  }
}

export function writeRemindedEntries(context: common.Context, entries: WidgetRemindedEntry[]): void {
  const store = openFreshCardStore(context)
  if (store === undefined) return
  try {
    store.putSync(REMINDED_EVENTS_KEY, JSON.stringify(entries.slice(-30)))
    store.flushSync()
  } catch (_) {
  }
}

export function readRemindedEventIds(context: common.Context): string[] {
  const entries = readRemindedEntries(context)
  const out: string[] = []
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].eventId.length > 0) out.push(entries[i].eventId)
  }
  return out
}

export function writeFormKind(context: common.Context, formId: string, formName: string): void {
  if (formId.length === 0 || formName.length === 0) return
  const store = openFreshCardStore(context)
  if (store === undefined) return
  try {
    store.putSync(FORM_KIND_PREFIX + formId, formName)
    store.flushSync()
  } catch (_) {
  }
}

export function readFormKind(context: common.Context, formId: string): string {
  if (formId.length === 0) return 'sky_window_card'
  const store = openFreshCardStore(context)
  if (store === undefined) return 'sky_window_card'
  try {
    const raw = store.getSync(FORM_KIND_PREFIX + formId, 'sky_window_card')
    return typeof raw === 'string' && raw.length > 0 ? raw : 'sky_window_card'
  } catch (_) {
    return 'sky_window_card'
  }
}

export function writePlanetSnapshot(
  context: common.Context,
  snapshot: Record<string, string>,
  timelineRaw: string
): void {
  const store = openFreshCardStore(context)
  if (store === undefined) return
  try {
    const serialized = JSON.stringify(snapshot)
    store.putSync(CARD_SNAPSHOT_KEY, serialized)
    if (timelineRaw.length > 0) {
      store.putSync(CARD_TIMELINE_KEY, timelineRaw)
    }
    const planet = snapshot['observerPlanet'] ?? 'Earth'
    if (planet.length > 0) {
      store.putSync(planetSnapshotKey(planet), serialized)
      if (timelineRaw.length > 0) {
        store.putSync(planetTimelineKey(planet), timelineRaw)
      }
    }
    store.flushSync()
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'writePlanetSnapshot failed: %{public}s', String(error))
  }
}

export function resolveCardDataForConfig(
  context: common.Context,
  config: CardInstanceConfig,
  now: number,
  offsetHours: number = 0
): Record<string, string> {
  const safeOffset = clampTimeOffsetHours(offsetHours)
  const evalMs = now + safeOffset * 3600000
  const store = openFreshCardStore(context)
  const remindedIds = readRemindedEventIds(context)

  if (store === undefined) {
    const fallback = config.planetMode !== 'follow'
      ? buildFallbackCardForPlanet(config.planetMode, evalMs)
      : defaultAstronomyCard()
    const styled = applyCardConfigToSnapshot(fallback, config, now)
    styled['timeOffsetHours'] = String(safeOffset)
    styled['timePreviewLabel'] = formatPreviewTimeBadge(safeOffset, evalMs)
    styled['remindedEventIds'] = JSON.stringify(remindedIds)
    return styled
  }
  try {
    let raw: string = ''
    let timelineRaw: string = ''
    const isSunMode = config.planetMode.trim().toLowerCase() === 'sun'
    const lookupPlanet = isSunMode ? 'Earth' : config.planetMode
    if (config.planetMode !== 'follow') {
      const pRaw = store.getSync(planetSnapshotKey(lookupPlanet), '')
      const pTl = store.getSync(planetTimelineKey(lookupPlanet), '')
      raw = typeof pRaw === 'string' ? pRaw : ''
      timelineRaw = typeof pTl === 'string' ? pTl : ''
      if (raw.length === 0) {
        const latestRaw = store.getSync(CARD_SNAPSHOT_KEY, '')
        if (typeof latestRaw === 'string' && latestRaw.length > 0) {
          const probe = normalizeAstronomyCard(latestRaw, now)
          if ((probe['observerPlanet'] ?? '').toLowerCase() === lookupPlanet.toLowerCase()) {
            raw = latestRaw
            const latestTl = store.getSync(CARD_TIMELINE_KEY, '')
            timelineRaw = typeof latestTl === 'string' ? latestTl : ''
          }
        }
      }
      if (raw.length === 0) {
        const fb = applyCardConfigToSnapshot(buildFallbackCardForPlanet(config.planetMode, evalMs), config, now)
        if (safeOffset > 0) {
          applyAnalyticalTimePreview(fb, config.planetMode, evalMs, safeOffset)
          if (isSunMode) applySolarShowcaseProjection(fb, evalMs)
        }
        fb['timeOffsetHours'] = String(safeOffset)
        fb['timePreviewLabel'] = formatPreviewTimeBadge(safeOffset, evalMs)
        fb['remindedEventIds'] = JSON.stringify(remindedIds)
        return fb
      }
    } else {
      const lRaw = store.getSync(CARD_SNAPSHOT_KEY, '')
      const lTl = store.getSync(CARD_TIMELINE_KEY, '')
      raw = typeof lRaw === 'string' ? lRaw : ''
      timelineRaw = typeof lTl === 'string' ? lTl : ''
      if (raw.length === 0) {
        const fb = applyCardConfigToSnapshot(defaultAstronomyCard(), config, now)
        if (safeOffset > 0) {
          applyAnalyticalTimePreview(fb, 'Earth', evalMs, safeOffset)
        }
        fb['timeOffsetHours'] = String(safeOffset)
        fb['timePreviewLabel'] = formatPreviewTimeBadge(safeOffset, evalMs)
        fb['remindedEventIds'] = JSON.stringify(remindedIds)
        return fb
      }
    }
    const card = normalizeAstronomyCard(raw, now)
    const liveCard = applyTimeline48hToCard(card, timelineRaw, evalMs)
    const styled = applyCardConfigToSnapshot(liveCard, config, now)
    if (safeOffset > 0 && liveCard['dataStatus'] !== '48h 离线星历') {
      applyAnalyticalTimePreview(styled, styled['observerPlanet'] ?? config.planetMode, evalMs, safeOffset)
    }
    if (isSunMode) {
      applySolarShowcaseProjection(styled, evalMs)
    }
    styled['timeOffsetHours'] = String(safeOffset)
    styled['timePreviewLabel'] = formatPreviewTimeBadge(safeOffset, evalMs)
    styled['remindedEventIds'] = JSON.stringify(remindedIds)
    return styled
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'resolveCardDataForConfig failed: %{public}s', String(error))
    const fallback = config.planetMode !== 'follow'
      ? buildFallbackCardForPlanet(config.planetMode, evalMs)
      : defaultAstronomyCard()
    const styled = applyCardConfigToSnapshot(fallback, config, now)
    styled['timeOffsetHours'] = String(safeOffset)
    styled['timePreviewLabel'] = formatPreviewTimeBadge(safeOffset, evalMs)
    styled['remindedEventIds'] = JSON.stringify(remindedIds)
    return styled
  }
}

export function resolveCardDataForForm(context: common.Context, formId: string, now: number = Date.now()): Record<string, string> {
  const config = readFormConfig(context, formId)
  const offsetHours = readFormTimeOffset(context, formId)
  const card = resolveCardDataForConfig(context, config, now, offsetHours)
  const savedColor = readFormTextColor(context, formId)
  if (savedColor.length > 0) {
    card['textColor'] = savedColor
  }
  return card
}
