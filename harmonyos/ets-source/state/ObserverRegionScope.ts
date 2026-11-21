// Shared geographic region scope model for Astronomy Calendar, Notifications, and Desktop Widgets.
// Pure TypeScript without ArkUI imports so both ArkTS panels/widgets and Node unit tests can use it directly.

export type ObserverHemisphere = 'north' | 'south' | 'equator'

export interface ObserverRegionPreset {
  id: string
  labelZh: string
  labelEn: string
  groupZh: string
  groupEn: string
  latitude: number
  longitude: number
  altitude: number
  utcOffsetMinutes: number
  tzLabelZh: string
  tzLabelEn: string
  hemisphere: ObserverHemisphere
  bortleHint: number
}

export interface ResolvedObserverRegion {
  isFollow: boolean
  id: string
  labelZh: string
  labelEn: string
  latitude: number
  longitude: number
  altitude: number
  utcOffsetMinutes: number
  tzLabelZh: string
  tzLabelEn: string
  hemisphere: ObserverHemisphere
  bortleScale: number
}

export const FOLLOW_REGION_ID: string = 'follow'

export const OBSERVER_REGION_PRESETS: ObserverRegionPreset[] = [
  {
    id: 'beijing', labelZh: '北京 · 华北', labelEn: 'Beijing',
    groupZh: '国内', groupEn: 'China',
    latitude: 39.9042, longitude: 116.4074, altitude: 44,
    utcOffsetMinutes: 480, tzLabelZh: 'UTC+8', tzLabelEn: 'UTC+8',
    hemisphere: 'north', bortleHint: 7
  },
  {
    id: 'shanghai', labelZh: '上海 · 华东', labelEn: 'Shanghai',
    groupZh: '国内', groupEn: 'China',
    latitude: 31.2304, longitude: 121.4737, altitude: 4,
    utcOffsetMinutes: 480, tzLabelZh: 'UTC+8', tzLabelEn: 'UTC+8',
    hemisphere: 'north', bortleHint: 8
  },
  {
    id: 'guangzhou', labelZh: '广州 · 华南', labelEn: 'Guangzhou',
    groupZh: '国内', groupEn: 'China',
    latitude: 23.1291, longitude: 113.2644, altitude: 21,
    utcOffsetMinutes: 480, tzLabelZh: 'UTC+8', tzLabelEn: 'UTC+8',
    hemisphere: 'north', bortleHint: 8
  },
  {
    id: 'chengdu', labelZh: '成都 · 西南', labelEn: 'Chengdu',
    groupZh: '国内', groupEn: 'China',
    latitude: 30.5728, longitude: 104.0668, altitude: 500,
    utcOffsetMinutes: 480, tzLabelZh: 'UTC+8', tzLabelEn: 'UTC+8',
    hemisphere: 'north', bortleHint: 7
  },
  {
    id: 'lhasa', labelZh: '拉萨 · 高原暗夜', labelEn: 'Lhasa',
    groupZh: '国内', groupEn: 'China',
    latitude: 29.6500, longitude: 91.1000, altitude: 3650,
    utcOffsetMinutes: 480, tzLabelZh: 'UTC+8', tzLabelEn: 'UTC+8',
    hemisphere: 'north', bortleHint: 3
  },
  {
    id: 'urumqi', labelZh: '乌鲁木齐 · 西北', labelEn: 'Urumqi',
    groupZh: '国内', groupEn: 'China',
    latitude: 43.8256, longitude: 87.6168, altitude: 800,
    utcOffsetMinutes: 480, tzLabelZh: 'UTC+8', tzLabelEn: 'UTC+8',
    hemisphere: 'north', bortleHint: 5
  },
  {
    id: 'harbin', labelZh: '哈尔滨 · 东北', labelEn: 'Harbin',
    groupZh: '国内', groupEn: 'China',
    latitude: 45.7500, longitude: 126.6500, altitude: 132,
    utcOffsetMinutes: 480, tzLabelZh: 'UTC+8', tzLabelEn: 'UTC+8',
    hemisphere: 'north', bortleHint: 6
  },
  {
    id: 'tokyo', labelZh: '东京 · 东亚', labelEn: 'Tokyo',
    groupZh: '国际', groupEn: 'Global',
    latitude: 35.6762, longitude: 139.6503, altitude: 40,
    utcOffsetMinutes: 540, tzLabelZh: 'UTC+9', tzLabelEn: 'UTC+9',
    hemisphere: 'north', bortleHint: 8
  },
  {
    id: 'singapore', labelZh: '新加坡 · 赤道', labelEn: 'Singapore',
    groupZh: '国际', groupEn: 'Global',
    latitude: 1.3521, longitude: 103.8198, altitude: 15,
    utcOffsetMinutes: 480, tzLabelZh: 'UTC+8', tzLabelEn: 'UTC+8',
    hemisphere: 'equator', bortleHint: 8
  },
  {
    id: 'london', labelZh: '伦敦 · 西欧', labelEn: 'London',
    groupZh: '国际', groupEn: 'Global',
    latitude: 51.5074, longitude: -0.1278, altitude: 25,
    utcOffsetMinutes: 0, tzLabelZh: 'UTC+0', tzLabelEn: 'UTC+0',
    hemisphere: 'north', bortleHint: 8
  },
  {
    id: 'newyork', labelZh: '纽约 · 北美', labelEn: 'New York',
    groupZh: '国际', groupEn: 'Global',
    latitude: 40.7128, longitude: -74.0060, altitude: 10,
    utcOffsetMinutes: -300, tzLabelZh: 'UTC-5', tzLabelEn: 'UTC-5',
    hemisphere: 'north', bortleHint: 8
  },
  {
    id: 'sydney', labelZh: '悉尼 · 南半球', labelEn: 'Sydney',
    groupZh: '南半球', groupEn: 'South',
    latitude: -33.8688, longitude: 151.2093, altitude: 58,
    utcOffsetMinutes: 600, tzLabelZh: 'UTC+10', tzLabelEn: 'UTC+10',
    hemisphere: 'south', bortleHint: 7
  },
  {
    id: 'auckland', labelZh: '奥克兰 · 南半球暗空', labelEn: 'Auckland',
    groupZh: '南半球', groupEn: 'South',
    latitude: -36.8485, longitude: 174.7633, altitude: 30,
    utcOffsetMinutes: 720, tzLabelZh: 'UTC+12', tzLabelEn: 'UTC+12',
    hemisphere: 'south', bortleHint: 5
  },
  {
    id: 'santiago', labelZh: '圣地亚哥 · 阿塔卡马', labelEn: 'Santiago',
    groupZh: '南半球', groupEn: 'South',
    latitude: -33.4489, longitude: -70.6693, altitude: 570,
    utcOffsetMinutes: -240, tzLabelZh: 'UTC-4', tzLabelEn: 'UTC-4',
    hemisphere: 'south', bortleHint: 4
  }
]

export function isValidObserverRegionId(id: string | undefined): boolean {
  if (typeof id !== 'string') return false
  const trimmed = id.trim()
  if (trimmed.length === 0 || trimmed === FOLLOW_REGION_ID) return true
  for (let i = 0; i < OBSERVER_REGION_PRESETS.length; i++) {
    if (OBSERVER_REGION_PRESETS[i].id === trimmed) return true
  }
  return false
}

export function normalizeObserverRegionId(id: string | undefined): string {
  if (typeof id !== 'string') return FOLLOW_REGION_ID
  const trimmed = id.trim()
  if (trimmed.length === 0 || trimmed === FOLLOW_REGION_ID) return FOLLOW_REGION_ID
  for (let i = 0; i < OBSERVER_REGION_PRESETS.length; i++) {
    if (OBSERVER_REGION_PRESETS[i].id === trimmed) return trimmed
  }
  return FOLLOW_REGION_ID
}

export function findObserverRegionPreset(id: string | undefined): ObserverRegionPreset | undefined {
  const safe = normalizeObserverRegionId(id)
  if (safe === FOLLOW_REGION_ID) return undefined
  for (let i = 0; i < OBSERVER_REGION_PRESETS.length; i++) {
    if (OBSERVER_REGION_PRESETS[i].id === safe) return OBSERVER_REGION_PRESETS[i]
  }
  return undefined
}

export function deviceUtcOffsetMinutes(atMs: number = Date.now()): number {
  return -new Date(atMs).getTimezoneOffset()
}

export function formatUtcOffsetLabel(offsetMinutes: number): string {
  const sign = offsetMinutes >= 0 ? '+' : '-'
  const abs = Math.abs(Math.round(offsetMinutes))
  const hours = Math.floor(abs / 60)
  const mins = abs % 60
  return mins === 0 ? `UTC${sign}${hours}` : `UTC${sign}${hours}:${String(mins).padStart(2, '0')}`
}

export function hemisphereFromLatitude(lat: number): ObserverHemisphere {
  if (!Number.isFinite(lat)) return 'north'
  if (Math.abs(lat) < 5) return 'equator'
  return lat < 0 ? 'south' : 'north'
}

export function resolveObserverRegion(
  regionId: string | undefined,
  followLat: number = 39.9042,
  followLon: number = 116.4074,
  followAlt: number = 44,
  followName: string = '',
  followBortle: number = 5,
  referenceMs: number = Date.now()
): ResolvedObserverRegion {
  const preset = findObserverRegionPreset(regionId)
  if (preset !== undefined) {
    return {
      isFollow: false,
      id: preset.id,
      labelZh: preset.labelZh,
      labelEn: preset.labelEn,
      latitude: preset.latitude,
      longitude: preset.longitude,
      altitude: preset.altitude,
      utcOffsetMinutes: preset.utcOffsetMinutes,
      tzLabelZh: preset.tzLabelZh,
      tzLabelEn: preset.tzLabelEn,
      hemisphere: preset.hemisphere,
      bortleScale: preset.bortleHint
    }
  }
  const safeLat = Number.isFinite(followLat) ? followLat : 39.9042
  const safeLon = Number.isFinite(followLon) ? followLon : 116.4074
  const safeAlt = Number.isFinite(followAlt) ? followAlt : 44
  const offset = deviceUtcOffsetMinutes(referenceMs)
  const tz = formatUtcOffsetLabel(offset)
  const cleanName = followName.trim()
  return {
    isFollow: true,
    id: FOLLOW_REGION_ID,
    labelZh: cleanName.length > 0 ? ('跟随位置 · ' + cleanName) : '跟随当前位置',
    labelEn: cleanName.length > 0 ? ('Follow · ' + cleanName) : 'Follow current location',
    latitude: safeLat,
    longitude: safeLon,
    altitude: safeAlt,
    utcOffsetMinutes: offset,
    tzLabelZh: tz,
    tzLabelEn: tz,
    hemisphere: hemisphereFromLatitude(safeLat),
    bortleScale: Number.isFinite(followBortle) ? followBortle : 5
  }
}

// Convert a UTC epoch ms into local wall-clock parts in the target UTC offset (minutes).
export interface RegionWallClock {
  year: number
  month: number
  day: number
  hour: number
  minute: number
}

export function wallClockInOffset(epochMs: number, utcOffsetMinutes: number): RegionWallClock {
  const shifted = new Date(epochMs + utcOffsetMinutes * 60000)
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes()
  }
}

// Build a UTC epoch ms from a wall-clock date/time in a given UTC offset (minutes).
export function epochFromWallClockInOffset(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  utcOffsetMinutes: number
): number {
  return Date.UTC(year, month - 1, day, hour, minute, 0, 0) - utcOffsetMinutes * 60000
}

export function formatRegionClock(epochMs: number, utcOffsetMinutes: number): string {
  const c = wallClockInOffset(epochMs, utcOffsetMinutes)
  return `${String(c.hour).padStart(2, '0')}:${String(c.minute).padStart(2, '0')}`
}

export function formatRegionDateTime(epochMs: number, utcOffsetMinutes: number, zh: boolean = true): string {
  const c = wallClockInOffset(epochMs, utcOffsetMinutes)
  const hh = String(c.hour).padStart(2, '0')
  const mm = String(c.minute).padStart(2, '0')
  if (zh) return `${c.month}月${c.day}日 ${hh}:${mm}`
  return `${c.year}-${String(c.month).padStart(2, '0')}-${String(c.day).padStart(2, '0')} ${hh}:${mm}`
}

export function regionShortLabel(regionId: string | undefined, language: string = 'zh', followName: string = ''): string {
  const zh = language.toLowerCase().startsWith('zh')
  const preset = findObserverRegionPreset(regionId)
  if (preset !== undefined) {
    return zh ? preset.labelZh : preset.labelEn
  }
  const clean = followName.trim()
  if (clean.length > 0) return zh ? ('跟随 · ' + clean) : ('Follow · ' + clean)
  return zh ? '跟随当前位置' : 'Follow location'
}
