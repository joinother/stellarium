// Rocket launch 3-DOF trajectory & twilight plume simulation data contracts.
// Mirrors JSON emitted by C++ RocketLaunchMgr (getRocketLaunchCatalog / simulateRocketLaunch).

export interface RocketLaunchSiteInfo {
  id: string
  nameZh: string
  nameEn: string
  code: string
  country: string
  latDeg: number
  lonDeg: number
  altM: number
  defaultAzimuthDeg: number
  isSeaLaunch?: boolean
}

export interface RocketVehicleInfo {
  id: string
  nameZh: string
  nameEn: string
  family: string
  propellantClass: string // solid | kerolox | methalox | hydrolox | hypergolic | hybrid_solid_liquid
  plumeTypeZh: string
  plumeTypeEn: string
  summaryZh: string
  summaryEn: string
  hasBoosters?: boolean
  boosterCount?: number
}

export interface RocketLaunchPresetInfo {
  id: string
  titleZh: string
  titleEn: string
  badgeZh: string
  badgeEn: string
  siteId: string
  vehicleId: string
  launchTimeUtc: string
  azimuthDeg: number
  targetOrbit: string
  descriptionZh: string
  descriptionEn: string
  hasNotam?: boolean
}

export interface RocketCatalogData {
  ok: boolean
  sites: RocketLaunchSiteInfo[]
  vehicles: RocketVehicleInfo[]
  presets: RocketLaunchPresetInfo[]
}

export interface RocketObserverInfo {
  latDeg: number
  lonDeg: number
  altM: number
  sunAltDeg: number
  sunAzDeg: number
  twilightStage: string
  distanceToPadKm: number
}

export interface RocketSimulationSummary {
  visibleFromObserver: boolean
  firstVisibleSec: number
  lastVisibleSec: number
  maxAltDeg: number
  maxAltSec: number
  maxAltAzDeg: number
  sunlitEntrySec: number
  sunlitEntryAltKm: number
  plumeScore: number
  plumeGrade: string // excellent | good | fair | flame_only | invisible
  plumeGradeZh: string
  plumeGradeEn: string
  plumeAdviceZh: string
  plumeAdviceEn: string
  plumeWindowStartSec: number
  plumeWindowEndSec: number
  peakPlumeSec: number
  peakPlumeBrightness: number
  peakPlumeAzDeg: number
  peakPlumeAltDeg: number
  recommendedFocalMm: number
}

export interface RocketNotamInfo {
  valid: boolean
  notamId: string
  validFromUtc: string
  validToUtc: string
  hasCircle: boolean
  circleLatDeg: number
  circleLonDeg: number
  circleRadiusKm: number
  centerLatDeg: number
  centerLonDeg: number
  invertedAzimuthDeg: number
  downrangeKm: number
  polygon: number[][] // [lat, lon]
}

export interface RocketFlightEventInfo {
  code: string
  labelZh: string
  labelEn: string
  tSec: number
  latDeg: number
  lonDeg: number
  altKm: number
  speedKmS: number
  azDeg: number
  altDeg: number
  rangeKm: number
}

export interface RocketDebrisInfo {
  kind: string // booster | fairing | stage1
  labelZh: string
  labelEn: string
  sepTimeSec: number
  impactTimeSec: number
  impactTimeUtc: string
  impactLatDeg: number
  impactLonDeg: number
  downrangeKm: number
  maxAltKm: number
  insideNotam: boolean
  distanceToNotamKm: number
  arc?: number[][] // [tSec, latDeg, lonDeg, altKm]
}

export interface RocketTrajectoryPoint {
  t: number
  ph: number
  prop: string
  lat: number
  lon: number
  altKm: number
  v: number
  dr: number
  az: number
  alt: number
  rng: number
  hor: number
  vis: boolean
  hEff: number
  sun: string // umbra | red_twilight | sunlit | daylit
  pW: number
  pAng: number
  pB: number
  pVis: boolean
}

export interface RocketSimulationData {
  ok: boolean
  error?: string
  simulationId: string
  titleZh: string
  titleEn: string
  launchTimeUtc: string
  launchJd: number
  timeOffsetMin: number
  launchAzimuthDeg: number
  computeMs: number
  site: RocketLaunchSiteInfo
  vehicle: RocketVehicleInfo
  observer: RocketObserverInfo
  summary: RocketSimulationSummary
  notam?: RocketNotamInfo
  events: RocketFlightEventInfo[]
  debris: RocketDebrisInfo[]
  dispersion?: number[][] // [latDeg, lonDeg, insideFlag(0|1)]
  trajectory: RocketTrajectoryPoint[]
  horizonProfile: number[][] // [azDeg, horizonAltDeg]
}

export interface RocketSimulationRequest {
  presetId?: string
  siteId?: string
  vehicleId?: string
  launchTimeUtc?: string
  azimuthDeg?: number
  timeOffsetMin?: number
  notamText?: string
  dispersionSamples?: number
  includeFullTrack?: boolean
  activatePreview?: boolean
  autoPlay?: boolean
  speed?: number
}

export function formatPropellantTag(propClass: string, isZh: boolean): string {
  switch (propClass) {
    case 'solid': return isZh ? '固体 · 扭曲彩带' : 'Solid · Ribbon'
    case 'kerolox': return isZh ? '液氧煤油 · 太空水母' : 'Kerolox · Jellyfish'
    case 'methalox': return isZh ? '液氧甲烷 · 冰蓝水母' : 'Methalox · Ice-Blue'
    case 'hydrolox': return isZh ? '液氢液氧 · 银白薄纱' : 'Hydrolox · Veil'
    case 'hypergolic': return isZh ? '常规液体 · 热分离水母' : 'Hypergolic · Plume'
    case 'hybrid_solid_liquid': return isZh ? '固液混合 · 双形态云' : 'Hybrid · Dual Plume'
    default: return propClass
  }
}

export function formatTwilightTag(stage: string, sunAltDeg: number, isZh: boolean): string {
  const degStr = `${sunAltDeg.toFixed(1)}°`
  if (stage === 'daylight') return isZh ? `白昼 (${degStr})` : `Daylight (${degStr})`
  if (stage === 'civil') return isZh ? `民用暮光 (${degStr})` : `Civil Twilight (${degStr})`
  if (stage === 'nautical') return isZh ? `航海暮光 (${degStr})` : `Nautical Twilight (${degStr})`
  if (stage === 'astronomical') return isZh ? `天文暮光 (${degStr})` : `Astro Twilight (${degStr})`
  return isZh ? `暗夜 (${degStr})` : `Night (${degStr})`
}

export function formatBeijingTimeFromIso(isoUtc: string): string {
  const ms = Date.parse(isoUtc)
  if (!Number.isFinite(ms)) return isoUtc
  const d = new Date(ms + 8 * 3600 * 1000)
  const yyyy = d.getUTCFullYear()
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0')
  const dd = String(d.getUTCDate()).padStart(2, '0')
  const hh = String(d.getUTCHours()).padStart(2, '0')
  const mm = String(d.getUTCMinutes()).padStart(2, '0')
  const ss = String(d.getUTCSeconds()).padStart(2, '0')
  return `${yyyy}-${mo}-${dd} ${hh}:${mm}:${ss} 北京时`
}
