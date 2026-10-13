// Astronomy display/derivation helpers.
// Migrated verbatim from pages/MainWindowNativeNode.ets (plan §14.2, track A1-2).
// These are pure, stateless file-level functions: no host-field access, no IO,
// no store/UI imports. They only depend on their arguments, the shared
// HeliocentricPosition type, and the static HELIOCENTRIC_PLANET_ORBITS table.

import { TabItem, HeliocentricPosition } from '../../pages/StellariumTypes'
import { HELIOCENTRIC_PLANET_ORBITS } from '../../pages/MainWindowModels'
import { I18n } from '../../pages/I18n'

// Julian day from a calendar date/time. Pure Gregorian/Julian conversion;
// no timezone handling (callers pass the values they want).
export function dateToJD(year: number, month: number, day: number, hour: number, minute: number): number {
  if (month <= 2) {
    year -= 1
    month += 12
  }
  const A = Math.floor(year / 100)
  const B = 2 - A + Math.floor(A / 4)
  const jdDay = Math.floor(365.25 * (year + 4716)) + Math.floor(30.6001 * (month + 1)) + day + B - 1524.5
  return jdDay + hour / 24.0 + minute / 1440.0
}

/** 儒略日 -> 'YYYY-MM-DD HH:mm:ss' 本地显示文本（入参需已含 UTC 偏移）。 */
export function jdToLocalTimeText(jd: number): string {
  // 用 UTC 取值避免设备时区二次偏移（jd 已带观测地偏移）
  const d = new Date((jd - 2440587.5) * 86400000)
  const p2 = (n: number): string => n < 10 ? '0' + n : n.toString()
  return d.getUTCFullYear() + '-' + p2(d.getUTCMonth() + 1) + '-' + p2(d.getUTCDate()) + ' ' +
    p2(d.getUTCHours()) + ':' + p2(d.getUTCMinutes()) + ':' + p2(d.getUTCSeconds())
}

export function astroGroupForTab(tab: number): number {
  if (tab === 0 || tab === 1 || tab === 6) return 1
  if (tab === 3 || tab === 7 || tab === 8) return 2
  return 0
}

export function graphModeLabel(mode: number): string {
  if (mode === 0) return '高度曲线'
  if (mode === 1) return '方位角曲线'
  if (mode === 2) return '全年高度'
  if (mode === 3) return '月度可观测性'
  if (mode === 4) return '月距曲线'
  return '双变量时间曲线'
}

export function hourOffsetLabel(t: number): string {
  const h: number = Math.floor(t)
  const mi: number = Math.round((t - h) * 60)
  if (h === 0 && mi === 0) return '此刻'
  let s: string = ''
  if (h > 0) s += h.toString() + ' 小时'
  if (mi > 0) s += mi.toString() + ' 分'
  return s + '后'
}

export function hecPointAngle(position: HeliocentricPosition): number {
  return position.displayLongitude ?? position.longitude
}

// 日心点颜色。原宿主 hecPointColor 读 nightModeStore.nightMode（末行的 nmAccent()），
// 按 §14.8 规则 6 改为显式入参 accentColor（调用点传 nmAccent()），其余逐字不变。
export function hecPointColor(position: HeliocentricPosition, accentColor: string): string {
  if (position.isComet) return '#7CC8E8'
  if (position.isSelectedMinor) return '#C2A36B'
  if (position.englishName === 'Mercury') return '#AAB5C5'
  if (position.englishName === 'Venus') return '#DEC18A'
  if (position.englishName === 'Earth') return '#6BAED6'
  if (position.englishName === 'Mars') return '#D18467'
  if (position.englishName === 'Jupiter') return '#D6A06D'
  if (position.englishName === 'Saturn') return '#D7BF76'
  if (position.englishName === 'Uranus') return '#82C9D2'
  if (position.englishName === 'Neptune') return '#6F9EDD'
  return accentColor
}

export function hecPlanetOrbitRadius(englishName: string): number {
  for (const orbit of HELIOCENTRIC_PLANET_ORBITS) {
    if (orbit.englishName === englishName) return orbit.visualRadius
  }
  return 0
}

export function messierNumberOf(raw: string): string {
  const compact = raw.trim().replace(/\s+/g, '')
  if (!/^M\d+$/i.test(compact)) { return '' }
  const number = Number(compact.substring(1))
  return number >= 1 && number <= 110 ? number.toString() : ''
}

export function minorPlanetNumberOf(raw: string): string {
  const match = raw.trim().match(/^\(?(\d{1,7})\)?(?:\s|$)/)
  return match !== null ? match[1] : ''
}

// 精确到角秒：地球自转约 15″/秒，300ms 刷新时用户能直接看到坐标连续变化。
export function fmtDegMin(deg: number): string {
  const sign = deg < 0 ? '-' : ''
  let totalSeconds = Math.round(Math.abs(deg) * 3600)
  const d = Math.floor(totalSeconds / 3600)
  totalSeconds -= d * 3600
  const m = Math.floor(totalSeconds / 60)
  const s = totalSeconds - m * 60
  return sign + d.toString() + '°' + (m < 10 ? '0' + m : m.toString()) + '\'' + (s < 10 ? '0' + s : s.toString()) + '″'
}

export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value))
}

export function distance(x0: number, y0: number, x1: number, y1: number): number {
  const dx = x1 - x0
  const dy = y1 - y0
  return Math.sqrt(dx * dx + dy * dy)
}

export function astroTabItemsForGroup(group: number): Array<TabItem> {
  if (group === 1) {
    return [
      { label: I18n.t('a0000'), id: 0 },
      { label: I18n.t('a0001'), id: 1 },
      { label: I18n.t('a0006'), id: 6 }
    ]
  }
  if (group === 2) {
    return [
      { label: I18n.t('a0003'), id: 3 },
      { label: I18n.t('a0007'), id: 7 },
      { label: I18n.t('a0008'), id: 8 }
    ]
  }
  return [
    { label: I18n.t('a0005'), id: 5 },
    { label: I18n.t('a0002'), id: 2 },
    { label: I18n.t('a0004'), id: 4 },
    { label: I18n.t('a0009'), id: 9 }
  ]
}

export function astroGroupItems(): Array<TabItem> {
  return [
    { label: I18n.t('astro_group_observation'), id: 0 },
    { label: I18n.t('astro_group_position'), id: 1 },
    { label: I18n.t('astro_group_events'), id: 2 }
  ]
}

export function rtsCalendarDurationLabel(days: number): string {
  if (days === 31) return '1 个月'
  if (days === 62) return '2 个月'
  if (days === 92) return '3 个月'
  if (days === 183) return '6 个月'
  if (days === 365) return '12 个月'
  return days.toString() + ' 天'
}

export function graphStartOptionLabel(offsetDays: number): string {
  if (offsetDays === 0) return '当前'
  return '+' + offsetDays.toString() + ' 天'
}

export function planetMetricLabel(metric: string): string {
  if (metric === 'magnitude') return '星等'
  if (metric === 'phase') return '照亮比例'
  if (metric === 'distance') return '距离'
  if (metric === 'elongation') return '距日角'
  if (metric === 'angularSize') return '视直径'
  if (metric === 'phaseAngle') return '相角'
  if (metric === 'heliocentricDistance') return '日心距'
  if (metric === 'transitAltitude') return '过中天高度'
  if (metric === 'rightAscension') return '赤经'
  return '赤纬'
}

export function planetMetricUnit(metric: string): string {
  if (metric === 'phase') return ' %'
  if (metric === 'distance' || metric === 'heliocentricDistance') return ' AU'
  if (metric === 'angularSize') return '″'
  if (metric === 'rightAscension') return ' h'
  if (metric === 'magnitude') return ' 等'
  return '°'
}

export function planetPairBodyName(body: string): string {
  if (body === 'Sun') return '太阳'
  if (body === 'Earth') return '地球'
  if (body === 'Moon') return '月亮'
  if (body === 'Mercury') return '水星'
  if (body === 'Venus') return '金星'
  if (body === 'Mars') return '火星'
  if (body === 'Jupiter') return '木星'
  if (body === 'Saturn') return '土星'
  if (body === 'Uranus') return '天王星'
  if (body === 'Neptune') return '海王星'
  return '冥王星'
}

export function planetPairLinearLabel(value: number | undefined): string {
  const distance: number = value ?? 0
  if (distance < 0.1) return (distance * 149597871).toFixed(0) + ' km'
  return distance.toFixed(3) + ' AU'
}

export function hecPointSize(position: HeliocentricPosition): number {
  if (position.isComet) return 9
  if (position.isSelectedMinor) return 10
  if (position.englishName === 'Mercury') return 9
  if (position.englishName === 'Venus' || position.englishName === 'Earth') return 11
  if (position.englishName === 'Mars') return 10
  if (position.englishName === 'Jupiter') return 17
  if (position.englishName === 'Saturn') return 15
  if (position.englishName === 'Uranus' || position.englishName === 'Neptune') return 13
  return 11
}

export function hecDistanceLabel(position: HeliocentricPosition): string {
  return position.distanceAU < 10 ? position.distanceAU.toFixed(3) : position.distanceAU.toFixed(2)
}

export function lunarElongationBarHeight(separation: number | undefined): number {
  return Math.max(1, Math.min(96, (separation ?? 0) / 180 * 96))
}

export function planetTimeSeriesBarHeight(value: number | undefined, min: number, max: number): number {
  return Math.max(1, Math.min(96, ((value ?? min) - min) / (max - min) * 96))
}

export function planetPairBarHeight(value: number | undefined, min: number, max: number): number {
  return Math.max(1, Math.min(96, ((value ?? min) - min) / (max - min) * 96))
}

// ---- 日心黄道位置点的几何簇（计划 §14.3 A2-5 逐字迁出；零宿主状态，仅依赖入参与模块内助手）----

export function hecDistanceToRadius(distanceAU: number): number {
  if (distanceAU <= 1) return clamp(24 + distanceAU * 33, 24, 57)
  if (distanceAU <= 5) return 57 + (distanceAU - 1) * 7.5
  if (distanceAU <= 15) return 87 + (distanceAU - 5) * 2.6
  return clamp(113 + (distanceAU - 15) * 1.35, 113, 133)
}

export function hecOrbitVerticalRadius(englishName: string): number {
  const radius = hecPlanetOrbitRadius(englishName)
  return radius > 0 ? radius * 0.86 : 0
}

export function hecPointDistance(position: HeliocentricPosition): number {
  if (position.displayRadius !== undefined) return position.displayRadius
  const planetRadius = hecPlanetOrbitRadius(position.englishName)
  return planetRadius > 0 ? planetRadius : hecDistanceToRadius(position.distanceAU)
}

export function hecPointHorizontalRadius(position: HeliocentricPosition): number {
  return hecPointDistance(position)
}

export function hecPointVerticalRadius(position: HeliocentricPosition): number {
  const orbitVerticalRadius = hecOrbitVerticalRadius(position.englishName)
  return orbitVerticalRadius > 0 ? orbitVerticalRadius : hecPointDistance(position)
}

export function hecPointX(position: HeliocentricPosition): number {
  const angle = (360 - hecPointAngle(position)) * Math.PI / 180
  return 146 + hecPointHorizontalRadius(position) * Math.sin(angle)
}

export function hecPointY(position: HeliocentricPosition): number {
  const angle = (360 - hecPointAngle(position)) * Math.PI / 180
  return 146 - hecPointVerticalRadius(position) * Math.cos(angle)
}

export function hecPointLeft(position: HeliocentricPosition): number {
  return hecPointX(position) - hecPointSize(position) / 2
}

export function hecPointTop(position: HeliocentricPosition): number {
  return hecPointY(position) - hecPointSize(position) / 2
}

export function hecLayoutPositions(positions: Array<HeliocentricPosition>): Array<HeliocentricPosition> {
  const placed: Array<HeliocentricPosition> = []
  for (const position of positions) {
    const baseRadius = hecPointDistance(position)
    const flexiblePosition = position.isComet || position.isSelectedMinor
    // 行星必须留在真实黄经对应的轨道位置。只有没有专属轨道的小天体
    // 才允许做很小的视觉避让，否则点会看起来偏离自己的轨道。
    const angularOffsets: Array<number> = flexiblePosition ? [0, 4, -4, 8, -8, 14, -14] : [0]
    const radialOffsets: Array<number> = flexiblePosition ? [0, 3, -3, 6, -6] : [0]
    let displayPosition: HeliocentricPosition = {
      name: position.name,
      englishName: position.englishName,
      latitude: position.latitude,
      longitude: position.longitude,
      distanceAU: position.distanceAU,
      isComet: position.isComet,
      isSelectedMinor: position.isSelectedMinor,
      displayLongitude: position.longitude,
      displayRadius: baseRadius,
    }
    let collisionFree: boolean = false
    for (const radialOffset of radialOffsets) {
      if (collisionFree) break
      for (const angularOffset of angularOffsets) {
        const candidate: HeliocentricPosition = {
          name: position.name,
          englishName: position.englishName,
          latitude: position.latitude,
          longitude: position.longitude,
          distanceAU: position.distanceAU,
          isComet: position.isComet,
          isSelectedMinor: position.isSelectedMinor,
          displayLongitude: position.longitude + angularOffset,
          displayRadius: clamp(baseRadius + radialOffset, 22, 136),
        }
        let collides: boolean = false
        for (const existing of placed) {
          const deltaX = hecPointX(candidate) - hecPointX(existing)
          const deltaY = hecPointY(candidate) - hecPointY(existing)
          const clearance = (hecPointSize(candidate) + hecPointSize(existing)) / 2 + 2
          if (deltaX * deltaX + deltaY * deltaY < clearance * clearance) {
            collides = true
            break
          }
        }
        if (!collides) {
          displayPosition = candidate
          collisionFree = true
          break
        }
      }
    }
    placed.push(displayPosition)
  }
  return placed
}

// 天象类型 → 说明性标题（计划 §14.2 A1-7 迁入）。
export function phenomenonCaption(type: string): string {
  if (type === '合') return '合 · 同向接近'
  if (type === '冲') return '冲 · 日地星共线'
  if (type.indexOf('方照') >= 0) return type + ' · 与太阳90°'
  if (type.indexOf('东大距') >= 0) return '东大距 · 傍晚最远离日'
  if (type.indexOf('西大距') >= 0) return '西大距 · 清晨最远离日'
  if (type.indexOf('近日点') >= 0) return '近日点 · 绕日最近'
  if (type.indexOf('远日点') >= 0) return '远日点 · 绕日最远'
  if (type.indexOf('逆行') >= 0) return '留 · 改为逆行'
  if (type.indexOf('顺行') >= 0) return '留 · 改为顺行'
  return type
}
