// Pure Astronomy Calendar filter logic, planet-aware categories, and TLE satellite-pass adapter.
// Kept free of ArkUI imports so both ArkTS panels/stores and Node host test suites can run it directly.

export type CalendarFilterCategory =
  'moon' | 'planet' | 'meteor' | 'solar' | 'satellite' | 'companion' | 'eclipse' | 'season'

export type CalendarSatelliteSubFilter = 'all' | 'stations' | 'visible' | 'high_alt'

export interface CalendarFilterableEvent {
  id: string
  kind: string
  title: string
  at: number
  jd: number
  body: string
  target: string
  panel: string
  tab: number
  isSupermoon?: boolean
  subtype?: string
  observerPlanet?: string
  satCatalogId?: string
  satArchetype?: string
  satMaxAlt?: number
  satVisible?: boolean
  satDurationSec?: number
  satAzimuthSummary?: string
}

export interface CalendarFilterState {
  selectedCategories: string[]
  satelliteSubFilter: string
  highlightOnly: boolean
}

export interface CalendarFilterCategoryMeta {
  id: CalendarFilterCategory
  labelZh: string
  labelEn: string
  dotHex: string
}

export interface NativeSatellitePassRecord {
  id?: string
  name?: string
  englishName?: string
  startAt?: number
  peakAt?: number
  endAt?: number
  peakJd?: number
  maxAlt?: number
  startAz?: number
  peakAz?: number
  endAz?: number
  mag?: number
  rangeKm?: number
  durationSec?: number
  visible?: boolean
}

export const EARTH_CALENDAR_CATEGORIES: CalendarFilterCategoryMeta[] = [
  { id: 'moon', labelZh: '月相', labelEn: 'Moon', dotHex: '#E0E6F2' },
  { id: 'planet', labelZh: '行星', labelEn: 'Planets', dotHex: '#FFB74D' },
  { id: 'meteor', labelZh: '流星雨', labelEn: 'Meteors', dotHex: '#64B5F6' },
  { id: 'solar', labelZh: '节气', labelEn: 'Solar Terms', dotHex: '#81C784' },
  { id: 'satellite', labelZh: '卫星过境', labelEn: 'Satellites', dotHex: '#4DD0E1' }
]

export const OFF_EARTH_CALENDAR_CATEGORIES: CalendarFilterCategoryMeta[] = [
  { id: 'planet', labelZh: '行星', labelEn: 'Planets', dotHex: '#FFB74D' },
  { id: 'companion', labelZh: '伴星相位', labelEn: 'Companion', dotHex: '#E0E6F2' },
  { id: 'eclipse', labelZh: '伴星食', labelEn: 'Eclipses', dotHex: '#FF8A65' },
  { id: 'season', labelZh: '季节', labelEn: 'Seasons', dotHex: '#81C784' }
]

export function isEarthCalendarPlanet(observerPlanet: string): boolean {
  const trimmed = observerPlanet.trim().toLowerCase()
  return trimmed.length === 0 || trimmed === 'earth'
}

export function calendarCategoriesForPlanet(observerPlanet: string): CalendarFilterCategoryMeta[] {
  return isEarthCalendarPlanet(observerPlanet) ? EARTH_CALENDAR_CATEGORIES : OFF_EARTH_CALENDAR_CATEGORIES
}

export function calendarCategoryOfKind(kind: string): CalendarFilterCategory {
  if (kind === 'moon-phase') return 'moon'
  if (kind === 'meteor-peak') return 'meteor'
  if (kind === 'solar-term') return 'solar'
  if (kind === 'satellite-pass') return 'satellite'
  if (kind === 'companion-phase') return 'companion'
  if (kind === 'companion-eclipse') return 'eclipse'
  if (kind === 'planetary-season') return 'season'
  return 'planet'
}

export function isHighlightCalendarEvent(event: CalendarFilterableEvent): boolean {
  if (event.kind === 'meteor-peak' || event.kind === 'companion-eclipse') return true
  if (event.kind === 'moon-phase' || event.kind === 'companion-phase') return event.isSupermoon === true
  if (event.kind === 'planetary-event') {
    const sub = (event.subtype ?? '').toLowerCase()
    if (sub === 'opposition' || sub === 'greatest-elongation' || sub === 'conjunction') return true
    return event.title.includes('冲日') || event.title.includes('大距') || event.title.includes('合')
  }
  if (event.kind === 'satellite-pass') {
    const arch = event.satArchetype ?? ''
    if (arch === 'iss' || arch === 'tiangong') return true
    return event.satVisible === true && (event.satMaxAlt ?? 0) >= 30
  }
  return false
}

export function isSpaceStationPass(event: CalendarFilterableEvent): boolean {
  const cid = (event.satCatalogId ?? '').trim()
  const arch = (event.satArchetype ?? '').trim()
  if (arch === 'iss' || arch === 'tiangong') return true
  if (cid === '25544' || cid === '48274') return true
  const hay = (event.title + ' ' + event.target).toLowerCase()
  return hay.includes('iss') || hay.includes('天宫') || hay.includes('空间站') || hay.includes('tianhe') || hay.includes('css')
}

export function eventMatchesCalendarFilter(
  event: CalendarFilterableEvent,
  filter: CalendarFilterState,
  observerPlanet: string = 'Earth'
): boolean {
  const validCategories = calendarCategoriesForPlanet(observerPlanet).map((c: CalendarFilterCategoryMeta) => c.id)
  const activeSelected = filter.selectedCategories.filter((cat: string) => validCategories.includes(cat as CalendarFilterCategory))
  const eventCat = calendarCategoryOfKind(event.kind)

  if (activeSelected.length > 0 && !activeSelected.includes(eventCat)) {
    return false
  }
  if (filter.highlightOnly && !isHighlightCalendarEvent(event)) {
    return false
  }
  if (event.kind === 'satellite-pass' && filter.satelliteSubFilter !== 'all') {
    if (filter.satelliteSubFilter === 'stations' && !isSpaceStationPass(event)) return false
    if (filter.satelliteSubFilter === 'visible' && event.satVisible !== true) return false
    if (filter.satelliteSubFilter === 'high_alt' && (event.satMaxAlt ?? 0) < 30) return false
  }
  return true
}

export function filterCalendarEvents<T extends CalendarFilterableEvent>(
  events: T[],
  filter: CalendarFilterState,
  observerPlanet: string = 'Earth'
): T[] {
  return events.filter((event: T) => eventMatchesCalendarFilter(event, filter, observerPlanet))
}

export function countCalendarEventsByCategory(events: CalendarFilterableEvent[]): Record<string, number> {
  const counts: Record<string, number> = {}
  for (const event of events) {
    const cat = calendarCategoryOfKind(event.kind)
    counts[cat] = (counts[cat] ?? 0) + 1
  }
  return counts
}

export function hasActiveCalendarFilter(filter: CalendarFilterState, observerPlanet: string = 'Earth'): boolean {
  const validIds = calendarCategoriesForPlanet(observerPlanet).map((c: CalendarFilterCategoryMeta) => c.id)
  const hasCat = filter.selectedCategories.some((cat: string) => validIds.includes(cat as CalendarFilterCategory))
  const hasSatSub = isEarthCalendarPlanet(observerPlanet) && filter.satelliteSubFilter !== 'all'
  return hasCat || filter.highlightOnly || hasSatSub
}

export function monthOverlapsSatelliteWindow(year: number, month: number, nowMs: number = Date.now()): boolean {
  const start = new Date(0)
  start.setFullYear(year, month - 1, 1)
  start.setHours(0, 0, 0, 0)
  const end = new Date(0)
  end.setFullYear(year, month, 1)
  end.setHours(0, 0, 0, 0)
  const windowEnd = nowMs + 48 * 3600000
  return windowEnd >= start.getTime() && nowMs < end.getTime()
}

function compassLabel(azDeg: number, zh: boolean): string {
  const norm = ((azDeg % 360) + 360) % 360
  const idx = Math.round(norm / 45) % 8
  const labelsZh = ['北', '东北', '东', '东南', '南', '西南', '西', '西北']
  const labelsEn = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
  return zh ? labelsZh[idx] : labelsEn[idx]
}

function formatPassClock(atMs: number): string {
  const d = new Date(atMs)
  return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')
}

function classifySatellitePassArchetype(name: string, catalogId: string): string {
  const cid = catalogId.trim()
  const hay = name.toLowerCase()
  if (cid === '25544' || hay.includes('iss') || hay.includes('zarya') || hay.includes('国际空间站')) return 'iss'
  if (cid === '48274' || hay.includes('css') || hay.includes('tianhe') || hay.includes('tiangong') || hay.includes('天宫') || hay.includes('中国空间站')) return 'tiangong'
  if (cid === '20580' || hay.includes('hst') || hay.includes('hubble') || hay.includes('哈勃')) return 'telescope'
  if (hay.includes('noaa') || hay.includes('landsat') || hay.includes('aqua') || hay.includes('terra') || hay.includes('sentinel') || hay.includes('风云')) return 'earth_obs'
  if (hay.includes('iridium') || hay.includes('intelsat') || hay.includes('天链') || hay.includes('中星')) return 'comms'
  return 'constellation'
}

function localizedSatellitePassName(rawName: string, englishName: string, catalogId: string, zh: boolean): string {
  if (!zh) return englishName || rawName || catalogId
  const cid = catalogId.trim()
  if (cid === '25544') return '国际空间站 ISS'
  if (cid === '48274') return '中国空间站 天宫'
  if (cid === '20580') return '哈勃空间望远镜'
  if (rawName.trim().length > 0 && rawName !== englishName) return rawName.trim()
  const upper = (englishName || rawName).toUpperCase()
  if (upper.includes('NOAA 19')) return 'NOAA 19 气象卫星'
  if (upper.includes('NOAA 20')) return 'NOAA 20 气象卫星'
  if (upper.includes('LANDSAT 8')) return '陆地卫星 8 号'
  if (upper.includes('SENTINEL-2A')) return '哨兵-2A 观测卫星'
  if (upper === 'AQUA') return 'Aqua 地球观测卫星'
  if (upper === 'TERRA') return 'Terra 地球观测卫星'
  return rawName.trim() || englishName.trim() || ('卫星 ' + cid)
}

export function parseTonightSatellitePassesToCalendarEvents(
  rawPasses: NativeSatellitePassRecord[],
  monthStartMs: number,
  monthEndMs: number,
  language: string
): CalendarFilterableEvent[] {
  const zh = language.toLowerCase().startsWith('zh')
  const out: CalendarFilterableEvent[] = []
  const seen = new Set<string>()
  for (const item of rawPasses) {
    if (item === null || typeof item !== 'object') continue
    const catalogId = typeof item.id === 'string' ? item.id.trim() : ''
    const peakAt = typeof item.peakAt === 'number' && Number.isFinite(item.peakAt)
      ? Math.round(item.peakAt)
      : (typeof item.startAt === 'number' && Number.isFinite(item.startAt) ? Math.round(item.startAt) : 0)
    if (catalogId.length === 0 || peakAt < monthStartMs || peakAt >= monthEndMs) continue
    const startAt = typeof item.startAt === 'number' && Number.isFinite(item.startAt) ? Math.round(item.startAt) : peakAt
    const endAt = typeof item.endAt === 'number' && Number.isFinite(item.endAt) ? Math.round(item.endAt) : peakAt
    const peakJd = typeof item.peakJd === 'number' && Number.isFinite(item.peakJd) && item.peakJd > 0
      ? item.peakJd : (peakAt / 86400000 + 2440587.5)
    const id = `satellite-pass-${catalogId}-${Math.floor(peakAt / 1000)}`
    if (seen.has(id)) continue
    seen.add(id)

    const rawName = typeof item.name === 'string' ? item.name : ''
    const englishName = typeof item.englishName === 'string' && item.englishName.trim().length > 0
      ? item.englishName.trim() : rawName
    const displayName = localizedSatellitePassName(rawName, englishName, catalogId, zh)
    const archetype = classifySatellitePassArchetype(englishName + ' ' + rawName, catalogId)
    const maxAlt = typeof item.maxAlt === 'number' && Number.isFinite(item.maxAlt) ? Math.round(item.maxAlt) : 20
    const startAz = typeof item.startAz === 'number' && Number.isFinite(item.startAz) ? item.startAz : 240
    const endAz = typeof item.endAz === 'number' && Number.isFinite(item.endAz) ? item.endAz : 60
    const visible = item.visible === true
    const durationSec = typeof item.durationSec === 'number' && Number.isFinite(item.durationSec) ? Math.round(item.durationSec) : 300
    const rangeKm = typeof item.rangeKm === 'number' && Number.isFinite(item.rangeKm) ? Math.round(item.rangeKm) : 0
    const mag = typeof item.mag === 'number' && Number.isFinite(item.mag) && item.mag < 30 ? item.mag : undefined
    const azSummary = compassLabel(startAz, zh) + ' → ' + compassLabel(endAz, zh)

    const title = zh
      ? `${displayName} 过境 · 最高 ${maxAlt}°`
      : `${displayName} Pass · Max ${maxAlt}°`
    const magTextZh = mag !== undefined ? `，峰值亮度约 ${mag.toFixed(1)} 等` : ''
    const magTextEn = mag !== undefined ? `, peak mag ${mag.toFixed(1)}` : ''
    const rangeTextZh = rangeKm > 0 ? `，最近距地约 ${rangeKm} km` : ''
    const rangeTextEn = rangeKm > 0 ? `, closest range ~${rangeKm} km` : ''
    const visTextZh = visible ? '卫星处于阳光照射且地面夜空较暗，适合肉眼寻找。' : '本次过境处于地影或较亮天光下，建议配合星图追踪。'
    const visTextEn = visible ? 'Sunlit against a darker sky — favorable for naked-eye spotting.' : 'Low optical contrast or in Earth shadow — best tracked on the star map.'
    const durMin = Math.max(1, Math.round(durationSec / 60))

    const body = zh
      ? `${displayName}（NORAD ${catalogId}）将于 ${formatPassClock(startAt)}–${formatPassClock(endAt)} 掠过当地上空（持续约 ${durMin} 分钟），航迹方向 ${azSummary}，最高仰角 ${maxAlt}°${magTextZh}${rangeTextZh}。${visTextZh}`
      : `${displayName} (NORAD ${catalogId}) passes overhead from ${formatPassClock(startAt)} to ${formatPassClock(endAt)} (~${durMin} min), traveling ${azSummary} with a peak elevation of ${maxAlt}°${magTextEn}${rangeTextEn}. ${visTextEn}`

    out.push({
      id: id,
      kind: 'satellite-pass',
      title: title,
      at: peakAt,
      jd: peakJd,
      body: body,
      target: englishName || catalogId,
      panel: 'satellites',
      tab: 0,
      satCatalogId: catalogId,
      satArchetype: archetype,
      satMaxAlt: maxAlt,
      satVisible: visible,
      satDurationSec: durationSec,
      satAzimuthSummary: azSummary
    })
  }
  return out.sort((a: CalendarFilterableEvent, b: CalendarFilterableEvent) => a.at - b.at)
}
