export interface CardMoonData {
  phaseName?: string
  illumination?: number
  age?: number
  rise?: string
  set?: string
}

export interface CardPlanetData {
  name?: string
  englishName?: string
  visible?: boolean
  rise?: string
  transit?: string
  set?: string
  altitude?: number
  magnitude?: number
}

export interface CardShowerData {
  name?: string
  zhr?: number
}

export interface CardObserverData {
  planet?: string
  planetZh?: string
  planetLocalized?: string
  hasAtmosphere?: boolean
  atmosphereProfile?: string
  solarDayHours?: number
  latitude?: number
  longitude?: number
  isEarth?: boolean
}

export interface CardCompanionData {
  name?: string
  englishName?: string
  role?: string
  phaseName?: string
  illumination?: number
  age?: number
  altitude?: number
  rise?: string
  transit?: string
  set?: string
}

export interface CardSunCycleData {
  sunAltitude?: number
  isDaytime?: boolean
  solarDayHours?: number
  nextSunEventType?: string
  nextSunEventAt?: number
  nextSunEventText?: string
  darkWindowHours?: number
}

export interface CardTimelineSample {
  at: number
  sunAlt: number
  skyHexTop: string
  skyHexHorizon: string
  companionAlt: number
  companionIllum: number
}

export interface CardUpcomingEvent {
  id?: string
  title?: string
  kind?: string
  target?: string
  jd?: number
  at?: number
  detail?: string
}

export interface CardTonightData {
  date?: string
  observer?: CardObserverData
  companion?: CardCompanionData
  sunCycle?: CardSunCycleData
  timeline48h?: CardTimelineSample[]
  upcomingEvents?: CardUpcomingEvent[]
  moon?: CardMoonData
  sun?: CardSunData
  planets?: CardPlanetData[]
  meteorShowers?: CardShowerData[]
  satellites?: CardSatelliteData
}

export interface CardSunData {
  rise?: string
  set?: string
  astroTwilightEnd?: string
  astroTwilightStart?: string
  darkWindowHours?: number
}

export interface CardSatelliteData {
  count?: number
  enabled?: boolean
}

export interface CardInstanceConfig {
  planetMode: string
  themeStyle: string
  labelStyle: string
  overflowMode: string
}

export interface CompactPlanetItem {
  n: string
  e: string
  s: string
  v: boolean
  r: string
  t: string
  a: number
  m: number
}

export interface CompactEventItem {
  id: string
  title: string
  kind: string
  target: string
  at: number
  jd: number
}

export interface MiniPhaseDay {
  label: string
  illumination: number
  age: number
  isToday: boolean
}

export interface OverflowAreaSpec {
  left: number
  top: number
  width: number
  height: number
  duration: number
  dimensionClass: string
}

export interface EstimatedMoonPhase {
  age: number
  illumination: number
  phaseName: string
}

export interface Timeline48hSnapshot {
  version: number
  generatedAt: number
  observerPlanet: string
  samples: CardTimelineSample[]
}

export interface InterpolatedTimelineState {
  valid: boolean
  sunAlt: number
  skyHexTop: string
  skyHexHorizon: string
  companionAlt: number
  companionIllum: number
}

export const SUPPORTED_EDIT_PLANETS: string[] = [
  'follow', 'Earth', 'Mars', 'Moon', 'Titan', 'Jupiter', 'Saturn', 'Neptune'
]

export const QUICK_CYCLE_PLANETS: string[] = [
  'Earth', 'Mars', 'Moon', 'Titan', 'Saturn', 'Jupiter', 'Neptune'
]

export function nextCyclePlanet(currentPlanet: string): string {
  const key = currentPlanet.trim().toLowerCase()
  let idx = -1
  for (let i = 0; i < QUICK_CYCLE_PLANETS.length; i++) {
    if (QUICK_CYCLE_PLANETS[i].toLowerCase() === key) {
      idx = i
      break
    }
  }
  return QUICK_CYCLE_PLANETS[(idx + 1) % QUICK_CYCLE_PLANETS.length]
}

export function clampTimeOffsetHours(hours: number): number {
  if (!Number.isFinite(hours)) return 0
  const rounded = Math.round(hours)
  if (rounded < 0) return 0
  if (rounded > 44) return 44
  return rounded
}

export function formatPreviewTimeBadge(offsetHours: number, targetMs: number): string {
  if (offsetHours <= 0) return ''
  const d = new Date(targetMs)
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return '+' + String(offsetHours) + 'h · ' + hh + ':' + mm
}

export function computePreviewPhaseForDay(baseAge: number, dayOffset: number, earthHost: boolean): EstimatedMoonPhase {
  const synodic = 29.530588853
  const safeAge = Number.isFinite(baseAge) && baseAge >= 0 ? baseAge : estimateMoonPhaseAt(Date.now()).age
  const age = (((safeAge + dayOffset) % synodic) + synodic) % synodic
  const illum = Math.round(((1 - Math.cos((age / synodic) * 2 * Math.PI)) * 50) * 10) / 10
  const clamped = Math.max(0, Math.min(100, illum))
  const moonName = moonPhaseNameFromAge(age)
  const phaseName = earthHost ? moonName.replace('月', '地') : moonName
  return {
    age: Math.round(age * 10) / 10,
    illumination: clamped,
    phaseName: phaseName
  }
}

export function parseRemindedEventIds(raw: string): string[] {
  if (typeof raw !== 'string' || raw.length === 0) return []
  try {
    const parsed = JSON.parse(raw) as Array<string>
    if (!Array.isArray(parsed)) return []
    const out: string[] = []
    for (let i = 0; i < parsed.length; i++) {
      if (typeof parsed[i] === 'string' && parsed[i].length > 0) out.push(parsed[i])
    }
    return out
  } catch (_) {
    return []
  }
}

export function defaultCardConfig(): CardInstanceConfig {
  return {
    planetMode: 'follow',
    themeStyle: 'sky',
    labelStyle: 'name',
    overflowMode: 'auto'
  }
}

export function normalizeCardConfig(raw: string): CardInstanceConfig {
  const def = defaultCardConfig()
  if (typeof raw !== 'string' || raw.length === 0) return def
  try {
    const parsed = JSON.parse(raw) as Record<string, string>
    if (parsed === null || typeof parsed !== 'object') return def
    const pm = typeof parsed['planetMode'] === 'string' ? parsed['planetMode'].trim() : 'follow'
    if (SUPPORTED_EDIT_PLANETS.includes(pm)) def.planetMode = pm
    const ts = parsed['themeStyle']
    if (ts === 'sky' || ts === 'deep') def.themeStyle = ts
    const ls = parsed['labelStyle']
    if (ls === 'name' || ls === 'symbol') def.labelStyle = ls
    const om = parsed['overflowMode']
    if (om === 'auto' || om === 'tap' || om === 'off') def.overflowMode = om
    return def
  } catch (_) {
    return def
  }
}

export function cardClock(value: string | undefined): string {
  const match = (value ?? '').match(/T(\d{2}:\d{2})/)
  return match === null ? '—' : match[1]
}

export function planetSymbol(body: string): string {
  const key = body.trim().toLowerCase()
  if (key === 'mercury' || key === '水星') return '☿'
  if (key === 'venus' || key === '金星') return '♀'
  if (key === 'earth' || key === '地球') return '⊕'
  if (key === 'mars' || key === '火星') return '♂'
  if (key === 'jupiter' || key === '木星') return '♃'
  if (key === 'saturn' || key === '土星') return '♄'
  if (key === 'uranus' || key === '天王星') return '⛢'
  if (key === 'neptune' || key === '海王星') return '♆'
  if (key === 'pluto' || key === '冥王星') return '♇'
  if (key === 'moon' || key === '月球') return '☾'
  if (key === 'titan' || key === '土卫六') return '♄'
  return '✦'
}

export function planetZhName(planetId: string): string {
  const key = planetId.trim().toLowerCase()
  if (key === 'follow' || key === '') return '跟随星图'
  if (key === 'earth') return '地球'
  if (key === 'mars') return '火星'
  if (key === 'moon') return '月球'
  if (key === 'titan') return '土卫六'
  if (key === 'jupiter') return '木星'
  if (key === 'saturn') return '土星'
  if (key === 'neptune') return '海王星'
  if (key === 'uranus') return '天王星'
  if (key === 'venus') return '金星'
  if (key === 'mercury') return '水星'
  if (key === 'pluto') return '冥王星'
  return planetId
}

export function orbKeyForBody(body: string): string {
  const key = body.trim().toLowerCase()
  if (key === 'moon' || key === '月球') return 'moon'
  if (key === 'earth' || key === '地球') return 'earth'
  if (key === 'mars' || key === '火星' || key === 'phobos' || key === '火卫一') return 'mars'
  if (key === 'saturn' || key === '土星') return 'saturn'
  if (key === 'jupiter' || key === '木星' || key === 'ganymede' || key === 'io' || key === 'europa') return 'jupiter'
  if (key === 'titan' || key === '土卫六') return 'titan'
  if (key === 'venus' || key === '金星') return 'venus'
  if (key === 'neptune' || key === '海王星' || key === 'triton') return 'neptune'
  if (key === 'uranus' || key === '天王星') return 'uranus'
  if (key === 'mercury' || key === '水星') return 'mercury'
  if (key === 'pluto' || key === '冥王星') return 'pluto'
  return 'moon'
}

export function moonPhaseNameFromAge(age: number): string {
  const a = ((age % 29.530588853) + 29.530588853) % 29.530588853
  if (a < 1.0 || a > 28.5) return '新月'
  if (a < 6.4) return '蛾眉月'
  if (a < 8.4) return '上弦月'
  if (a < 13.9) return '盈凸月'
  if (a < 15.9) return '满月'
  if (a < 21.4) return '亏凸月'
  if (a < 23.4) return '下弦月'
  return '残月'
}

// Pure-TS synodic lunar phase estimate (epoch: 2000-01-06T18:14:00Z new moon).
export function estimateMoonPhaseAt(nowMs: number): EstimatedMoonPhase {
  const synodic = 29.530588853
  const epochMs = Date.UTC(2000, 0, 6, 18, 14, 0)
  const days = (nowMs - epochMs) / 86400000
  const age = ((days % synodic) + synodic) % synodic
  const angle = (age / synodic) * 2 * Math.PI
  const illumination = Math.round(((1 - Math.cos(angle)) * 50) * 10) / 10
  return {
    age: Math.round(age * 10) / 10,
    illumination: Math.max(0, Math.min(100, illumination)),
    phaseName: moonPhaseNameFromAge(age)
  }
}

export function formatCountdownZh(eventAtMs: number, nowMs: number): string {
  if (!Number.isFinite(eventAtMs) || eventAtMs <= 0) return '待同步'
  const diffMin = Math.round((eventAtMs - nowMs) / 60000)
  if (diffMin <= 0 && diffMin >= -90) return '正在发生'
  if (diffMin < -90) return '已过境'
  if (diffMin < 60) return String(Math.max(1, diffMin)) + ' 分钟后'
  const diffHours = Math.round(diffMin / 60)
  if (diffHours < 48) return String(diffHours) + ' 小时后'
  const diffDays = Math.round(diffHours / 24)
  return String(diffDays) + ' 天后'
}

export function formatShortDateZh(eventAtMs: number): string {
  if (!Number.isFinite(eventAtMs) || eventAtMs <= 0) return '—'
  const d = new Date(eventAtMs)
  const m = d.getMonth() + 1
  const day = d.getDate()
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return String(m) + '月' + String(day) + '日 ' + hh + ':' + mm
}

export function buildMiniPhaseStrip(age: number, nowMs: number): MiniPhaseDay[] {
  const out: MiniPhaseDay[] = []
  const weekdays = ['日', '一', '二', '三', '四', '五', '六']
  const synodic = 29.530588853
  const baseAge = Number.isFinite(age) && age >= 0 ? age : estimateMoonPhaseAt(nowMs).age
  for (let i = 0; i < 5; i++) {
    const dayMs = nowMs + i * 86400000
    const d = new Date(dayMs)
    const a = ((baseAge + i) % synodic + synodic) % synodic
    const illum = Math.round((1 - Math.cos((a / synodic) * 2 * Math.PI)) * 50)
    out.push({
      label: i === 0 ? '今' : '周' + weekdays[d.getDay()],
      illumination: Math.max(0, Math.min(100, illum)),
      age: Math.round(a * 10) / 10,
      isToday: i === 0
    })
  }
  return out
}

export function parseVisiblePlanets(rawJson: string): CompactPlanetItem[] {
  if (typeof rawJson !== 'string' || rawJson.length === 0) return []
  try {
    const arr = JSON.parse(rawJson) as Array<CompactPlanetItem>
    if (!Array.isArray(arr)) return []
    return arr.slice(0, 5)
  } catch (_) {
    return []
  }
}

export function parseUpcomingEvents(rawJson: string): CompactEventItem[] {
  if (typeof rawJson !== 'string' || rawJson.length === 0) return []
  try {
    const arr = JSON.parse(rawJson) as Array<CompactEventItem>
    if (!Array.isArray(arr)) return []
    return arr.slice(0, 4)
  } catch (_) {
    return []
  }
}

export function formatPlanetDisplayList(rawJson: string, fallbackNames: string, labelStyle: string): string {
  const items = parseVisiblePlanets(rawJson)
  const visible = items.filter((item: CompactPlanetItem) => item.v)
  if (visible.length === 0) {
    return fallbackNames.length > 0 ? fallbackNames : '当前无亮行星升起'
  }
  if (labelStyle === 'symbol') {
    return visible.map((item: CompactPlanetItem) => item.s || planetSymbol(item.e || item.n)).join('  ')
  }
  return visible.map((item: CompactPlanetItem) => item.n || item.e).join(' · ')
}

// Compute a HarmonyOS API 20 compliant centered overflow rect from formProvider.getFormRect().
// Official max ratios centered on card rect (width x height — each side expands by at most +1 grid cell):
//   1*2 -> 150% x 200%, 2*2 -> 150% x 150%, 2*4 -> 125% x 150%,
//   4*4 -> 125% x 125%, 6*4 -> 125% x 110%. Duration <= 3500ms.
export function computeOverflowArea(formWidth: number, formHeight: number): OverflowAreaSpec {
  const safeW = Number.isFinite(formWidth) && formWidth > 20 ? formWidth : 160
  const safeH = Number.isFinite(formHeight) && formHeight > 20 ? formHeight : 160
  const aspect = safeW / safeH
  let widthRatio = 1.44
  let heightRatio = 1.46
  let dimensionClass = '2x2'
  if (aspect >= 1.75 && safeH < 120) {
    widthRatio = 1.44
    heightRatio = 1.80
    dimensionClass = '1x2'
  } else if (aspect >= 1.35) {
    widthRatio = 1.22
    heightRatio = 1.46
    dimensionClass = '2x4'
  } else if (aspect <= 0.78) {
    widthRatio = 1.22
    heightRatio = 1.08
    dimensionClass = '6x4'
  } else if (safeW >= 260 && safeH >= 260) {
    widthRatio = 1.22
    heightRatio = 1.22
    dimensionClass = '4x4'
  }
  const width = Math.round(safeW * widthRatio)
  const height = Math.round(safeH * heightRatio)
  const left = -Math.round((width - safeW) / 2)
  // Center vertically within the official IJKL box so top & bottom overflow margins are maximized cleanly
  const maxTopExtra = Math.floor((height - safeH) / 2)
  const top = -maxTopExtra
  return {
    left: left,
    top: top,
    width: width,
    height: height,
    duration: 3500,
    dimensionClass: dimensionClass
  }
}

export function extractInverseTextColor(rawParam: Object | undefined): string {
  if (rawParam === undefined || rawParam === null) return ''
  let candidate = ''
  if (typeof rawParam === 'string') {
    const trimmed = rawParam.trim()
    if (trimmed.startsWith('{')) {
      try {
        const parsed = JSON.parse(trimmed) as Record<string, Object>
        if (typeof parsed['mTextColor'] === 'string') candidate = String(parsed['mTextColor']).trim()
      } catch (_) {
        return ''
      }
    } else {
      candidate = trimmed
    }
  } else if (typeof rawParam === 'object') {
    const obj = rawParam as Record<string, Object>
    if (typeof obj['mTextColor'] === 'string') candidate = String(obj['mTextColor']).trim()
  }
  if (/^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(candidate)) return candidate
  return ''
}

export function isLightTextColor(hexColor: string): boolean {
  const cleaned = hexColor.replace('#', '')
  if (cleaned.length !== 6 && cleaned.length !== 8) return true
  const offset = cleaned.length === 8 ? 2 : 0
  const r = parseInt(cleaned.slice(offset, offset + 2), 16)
  const g = parseInt(cleaned.slice(offset + 2, offset + 4), 16)
  const b = parseInt(cleaned.slice(offset + 4, offset + 6), 16)
  if (!Number.isFinite(r) || !Number.isFinite(g) || !Number.isFinite(b)) return true
  return (0.299 * r + 0.587 * g + 0.114 * b) >= 140
}

export function defaultAstronomyCard(): Record<string, string> {
  const phase = estimateMoonPhaseAt(Date.now())
  const card: Record<string, string> = {}
  card['schemaVersion'] = '4'
  card['title'] = '星象仪'
  card['subtitle'] = '实时天穹'
  card['summary'] = '轻触天体预览破框 · 进入星图'
  card['moonSummary'] = String(Math.round(phase.illumination)) + '% 照明'
  card['moonPhase'] = phase.phaseName
  card['moonIllumination'] = String(phase.illumination)
  card['moonAge'] = String(phase.age)
  card['planetSummary'] = '今晚行星'
  card['planetNames'] = '打开星图同步实时星历'
  card['meteorSummary'] = '流星雨活动'
  card['meteorRate'] = '—'
  card['satelliteSummary'] = '卫星目录已就绪'
  card['observationSummary'] = '暗夜观测'
  card['darkStart'] = '—'
  card['darkEnd'] = '—'
  card['moonRise'] = '—'
  card['moonSet'] = '—'
  card['sunRise'] = '—'
  card['sunSet'] = '—'
  card['updatedAt'] = '离线推演'
  card['calculatedAt'] = '0'
  card['dataDate'] = ''
  card['dataStatus'] = '本地快照'
  card['observerPlanet'] = 'Earth'
  card['observerPlanetName'] = '地球'
  card['atmosphereProfile'] = 'earth'
  card['companionName'] = '月球'
  card['companionEnglish'] = 'Moon'
  card['companionRole'] = 'moon'
  card['companionAlt'] = '28.0'
  card['orbBody'] = 'moon'
  card['skyHexTop'] = '#070E22'
  card['skyHexHorizon'] = '#172C52'
  card['sunAlt'] = '-18.0'
  card['nextSunEventType'] = ''
  card['nextSunEventText'] = '—'
  card['visiblePlanetsJson'] = '[]'
  card['upcomingEventsJson'] = '[]'
  card['nextEventTitle'] = '等待星历同步'
  card['nextEventKind'] = 'sky'
  card['nextEventAt'] = '0'
  card['nextEventJd'] = '0'
  card['nextEventTarget'] = 'Moon'
  card['nextEventCountdown'] = '打开星图'
  card['cardPlanetMode'] = 'follow'
  card['cardThemeStyle'] = 'sky'
  card['cardLabelStyle'] = 'name'
  card['cardOverflowMode'] = 'auto'
  card['textColor'] = '#F5F9FF'
  card['timeOffsetHours'] = '0'
  card['timePreviewLabel'] = ''
  card['remindedEventIds'] = '[]'
  card['reminderToast'] = ''
  return card
}

export function buildFallbackCardForPlanet(planetId: string, now: number): Record<string, string> {
  const card = defaultAstronomyCard()
  const key = planetId.trim().toLowerCase()
  const phase = estimateMoonPhaseAt(now)
  const dateObj = new Date(now)
  const dateStr = String(dateObj.getFullYear()) + '-' +
    String(dateObj.getMonth() + 1).padStart(2, '0') + '-' +
    String(dateObj.getDate()).padStart(2, '0')
  card['dataDate'] = dateStr
  card['dataStatus'] = '行星预设'
  card['updatedAt'] = '轻触同步实时星历'

  if (key === 'mars') {
    card['observerPlanet'] = 'Mars'
    card['observerPlanetName'] = '火星'
    card['atmosphereProfile'] = 'mars'
    card['companionName'] = '火卫一'
    card['companionEnglish'] = 'Phobos'
    card['companionRole'] = 'moon'
    card['orbBody'] = 'mars'
    card['skyHexTop'] = '#3A231D'
    card['skyHexHorizon'] = '#8F5638'
    card['sunAlt'] = '-4.0'
    card['observationSummary'] = '火星蓝日落 · Sol 24.7h'
    card['subtitle'] = '火星观测 · 尘埃大气'
    card['summary'] = '火星 · 24.7 小时太阳日'
    card['moonPhase'] = '火卫一 · 西升东落'
    card['moonIllumination'] = '68'
    card['moonSummary'] = '7.6h 周期'
    card['planetSummary'] = '地球 · 木星可见'
    card['planetNames'] = '地球 · 木星 · 土星'
    card['visiblePlanetsJson'] = JSON.stringify([
      { n: '地球', e: 'Earth', s: '⊕', v: true, r: '19:10', t: '04:20', a: 28, m: -1.6 },
      { n: '木星', e: 'Jupiter', s: '♃', v: true, r: '20:45', t: '06:10', a: 42, m: -2.2 },
      { n: '土星', e: 'Saturn', s: '♄', v: true, r: '22:15', t: '07:30', a: 18, m: 0.6 }
    ])
    card['nextEventTitle'] = '火星视角 · 地球大距与四季'
    card['nextEventKind'] = 'planet'
    card['nextEventTarget'] = 'Earth'
    card['nextEventCountdown'] = '同步日历'
    return card
  }
  if (key === 'moon') {
    // Earth's phase as seen from the Moon is complementary to lunar phase!
    const earthIllum = Math.max(0, Math.min(100, Math.round(100 - phase.illumination)))
    const earthAge = ((phase.age + 14.765) % 29.530588853)
    card['observerPlanet'] = 'Moon'
    card['observerPlanetName'] = '月球'
    card['atmosphereProfile'] = 'airless'
    card['companionName'] = '地球'
    card['companionEnglish'] = 'Earth'
    card['companionRole'] = 'host'
    card['orbBody'] = 'earth'
    card['skyHexTop'] = '#040710'
    card['skyHexHorizon'] = '#0B1326'
    card['sunAlt'] = '-12.0'
    card['observationSummary'] = '月昼/月夜 · 14.8 地球日'
    card['subtitle'] = '月球观测 · 真空星穹'
    card['summary'] = '地相 ' + String(earthIllum) + '% · 地球常悬天穹'
    card['moonPhase'] = earthIllum >= 95 ? '满地' : earthIllum <= 5 ? '新地' : (earthAge < 14.765 ? '盈凸地相' : '亏凸地相')
    card['moonIllumination'] = String(earthIllum)
    card['moonAge'] = String(Math.round(earthAge * 10) / 10)
    card['moonSummary'] = String(earthIllum) + '% 地相照明'
    card['companionAlt'] = '52.0'
    card['planetSummary'] = '母星地球常驻天空'
    card['planetNames'] = '地球 · 金星 · 木星'
    card['visiblePlanetsJson'] = JSON.stringify([
      { n: '地球', e: 'Earth', s: '⊕', v: true, r: '常悬', t: '常悬', a: 52, m: -16.2 },
      { n: '木星', e: 'Jupiter', s: '♃', v: true, r: '—', t: '—', a: 36, m: -2.4 }
    ])
    card['nextEventTitle'] = '月球视角 · 地相循环与地球食日'
    card['nextEventKind'] = 'eclipse'
    card['nextEventTarget'] = 'Earth'
    card['nextEventCountdown'] = '同步日历'
    return card
  }
  if (key === 'titan') {
    card['observerPlanet'] = 'Titan'
    card['observerPlanetName'] = '土卫六'
    card['atmosphereProfile'] = 'titan'
    card['companionName'] = '土星'
    card['companionEnglish'] = 'Saturn'
    card['companionRole'] = 'host'
    card['orbBody'] = 'saturn'
    card['skyHexTop'] = '#3C220A'
    card['skyHexHorizon'] = '#9E5C1B'
    card['sunAlt'] = '8.0'
    card['observationSummary'] = '橙雾大气 · 15.9 地球日周期'
    card['subtitle'] = '土卫六观测 · 托林烟霾'
    card['summary'] = '土卫六 · 仰望巨型土星光环'
    card['moonPhase'] = '土星巨盘 · 光环悬空'
    card['moonIllumination'] = '72'
    card['moonSummary'] = '72% 土星照明'
    card['companionAlt'] = '46.0'
    card['planetSummary'] = '宿主土星主导天穹'
    card['planetNames'] = '土星 · 木星'
    card['visiblePlanetsJson'] = JSON.stringify([
      { n: '土星', e: 'Saturn', s: '♄', v: true, r: '常悬', t: '常悬', a: 46, m: -13.0 },
      { n: '木星', e: 'Jupiter', s: '♃', v: true, r: '—', t: '—', a: 22, m: -1.1 }
    ])
    card['nextEventTitle'] = '土卫六视角 · 土星相位与同系合'
    card['nextEventKind'] = 'planet'
    card['nextEventTarget'] = 'Saturn'
    card['nextEventCountdown'] = '同步日历'
    return card
  }
  if (key === 'jupiter') {
    card['observerPlanet'] = 'Jupiter'
    card['observerPlanetName'] = '木星'
    card['atmosphereProfile'] = 'jupiter'
    card['companionName'] = '木卫三'
    card['companionEnglish'] = 'Ganymede'
    card['companionRole'] = 'moon'
    card['orbBody'] = 'jupiter'
    card['skyHexTop'] = '#231D2B'
    card['skyHexHorizon'] = '#6C5142'
    card['observationSummary'] = '极速自转 · 9.9h 昼夜'
    card['subtitle'] = '木星云顶 · 伽利略卫星'
    card['summary'] = '木星 · 9.9 小时一昼夜'
    card['moonPhase'] = '木卫三 · 凌木巡天'
    card['moonIllumination'] = '76'
    card['moonSummary'] = '伽利略卫星系'
    card['nextEventTitle'] = '木星视角 · 伽利略四卫与外行星'
    card['nextEventTarget'] = 'Saturn'
    card['nextEventCountdown'] = '同步日历'
    return card
  }
  if (key === 'saturn') {
    card['observerPlanet'] = 'Saturn'
    card['observerPlanetName'] = '土星'
    card['atmosphereProfile'] = 'saturn'
    card['companionName'] = '土卫六'
    card['companionEnglish'] = 'Titan'
    card['companionRole'] = 'moon'
    card['orbBody'] = 'saturn'
    card['skyHexTop'] = '#262119'
    card['skyHexHorizon'] = '#7A6744'
    card['observationSummary'] = '光环穹顶 · 10.7h 昼夜'
    card['subtitle'] = '土星观测 · 冰环天拱'
    card['summary'] = '土星 · 10.7 小时太阳日'
    card['moonPhase'] = '土卫六 · 15.9日公转'
    card['moonIllumination'] = '64'
    card['moonSummary'] = '土卫六相位'
    card['nextEventTitle'] = '土星视角 · 土卫六巡行'
    card['nextEventTarget'] = 'Titan'
    card['nextEventCountdown'] = '同步日历'
    return card
  }
  if (key === 'neptune') {
    card['observerPlanet'] = 'Neptune'
    card['observerPlanetName'] = '海王星'
    card['atmosphereProfile'] = 'neptune'
    card['companionName'] = '海卫一'
    card['companionEnglish'] = 'Triton'
    card['companionRole'] = 'moon'
    card['orbBody'] = 'neptune'
    card['skyHexTop'] = '#071436'
    card['skyHexHorizon'] = '#1B4B8A'
    card['observationSummary'] = '钴蓝甲烷穹 · 16.1h 昼夜'
    card['subtitle'] = '海王星观测 · 深蓝边界'
    card['summary'] = '海王星 · 16.1 小时太阳日'
    card['moonPhase'] = '海卫一 · 逆行伴星'
    card['moonIllumination'] = '58'
    card['moonSummary'] = '5.9日逆行轨道'
    card['nextEventTitle'] = '海王星视角 · 远日行星巡天'
    card['nextEventTarget'] = 'Uranus'
    card['nextEventCountdown'] = '同步日历'
    return card
  }
  // Earth fallback
  card['observerPlanet'] = 'Earth'
  card['observerPlanetName'] = '地球'
  card['orbBody'] = 'moon'
  card['observationSummary'] = phase.phaseName + ' · ' + String(Math.round(phase.illumination)) + '%'
  card['subtitle'] = '本地天穹 · ' + dateStr
  return card
}

export function buildAstronomyCard(tonight: CardTonightData, now: number): Record<string, string> {
  const data = defaultAstronomyCard()
  const observer = tonight.observer
  const isOffEarth = observer !== undefined && (observer.isEarth === false ||
    (typeof observer.planet === 'string' && observer.planet.trim().length > 0 && observer.planet.trim().toLowerCase() !== 'earth'))
  const obsPlanet = isOffEarth ? (observer?.planet?.trim() || 'Earth') : 'Earth'
  const obsPlanetName = isOffEarth ? (observer?.planetZh || observer?.planetLocalized || planetZhName(obsPlanet)) : '地球'
  const companion = tonight.companion
  const sunCycle = tonight.sunCycle
  const moon = tonight.moon
  const sun = tonight.sun
  const planets = tonight.planets ?? []
  const visible = planets.filter((planet: CardPlanetData) => planet.visible === true)
  const showers = (tonight.meteorShowers ?? []).slice().sort((first: CardShowerData, second: CardShowerData) =>
    (second.zhr ?? 0) - (first.zhr ?? 0))
  const illumination = companion?.illumination ?? moon?.illumination

  data['observerPlanet'] = obsPlanet
  data['observerPlanetName'] = obsPlanetName
  data['atmosphereProfile'] = observer?.atmosphereProfile ?? (isOffEarth ? obsPlanet.toLowerCase() : 'earth')
  data['companionName'] = companion?.name ?? (isOffEarth ? '当地伴星' : '月球')
  data['companionEnglish'] = companion?.englishName ?? (isOffEarth ? '' : 'Moon')
  data['companionRole'] = companion?.role ?? 'moon'
  if (companion?.altitude !== undefined && Number.isFinite(companion.altitude)) {
    data['companionAlt'] = (Math.round(companion.altitude * 10) / 10).toFixed(1)
  }

  // Pick the most iconic 3D orb for this world:
  // Earth -> Moon; Moon -> Earth; Titan -> Saturn; other moons -> parent planet; planets -> self orb
  if (!isOffEarth) {
    data['orbBody'] = 'moon'
  } else if ((companion?.role === 'parent-planet' || companion?.role === 'host') && (companion?.englishName ?? '').length > 0) {
    data['orbBody'] = orbKeyForBody(companion?.englishName ?? obsPlanet)
  } else {
    data['orbBody'] = orbKeyForBody(obsPlanet)
  }

  data['moonPhase'] = companion?.phaseName ?? moon?.phaseName ?? '月相待计算'
  data['moonIllumination'] = illumination !== undefined && Number.isFinite(illumination)
    ? String(Math.max(0, Math.min(100, Math.round(illumination * 10) / 10))) : '-1'
  data['moonAge'] = String(moon?.age ?? companion?.age ?? 0)
  data['moonSummary'] = illumination !== undefined && Number.isFinite(illumination)
    ? String(Math.round(Math.max(0, Math.min(100, illumination)))) + '% 照明' : '待计算'

  // Compact planet list sorted by visibility then brightness (magnitude)
  const sortedPlanets = planets.slice().sort((a: CardPlanetData, b: CardPlanetData) => {
    const va = a.visible === true ? 0 : 1
    const vb = b.visible === true ? 0 : 1
    if (va !== vb) return va - vb
    return (a.magnitude ?? 10) - (b.magnitude ?? 10)
  })
  const compactPlanets: CompactPlanetItem[] = []
  for (let i = 0; i < sortedPlanets.length && compactPlanets.length < 5; i++) {
    const p = sortedPlanets[i]
    const eng = p.englishName ?? ''
    const zh = p.name ?? planetZhName(eng)
    compactPlanets.push({
      n: zh,
      e: eng,
      s: planetSymbol(eng.length > 0 ? eng : zh),
      v: p.visible === true,
      r: cardClock(p.rise),
      t: cardClock(p.set),
      a: Number.isFinite(p.altitude) ? Math.round((p.altitude ?? 0) * 10) / 10 : -90,
      m: Number.isFinite(p.magnitude) ? Math.round((p.magnitude ?? 0) * 10) / 10 : 0
    })
  }
  data['visiblePlanetsJson'] = JSON.stringify(compactPlanets)

  data['planetSummary'] = planets.length > 0 ? String(visible.length) + ' 颗在地平线上' : '待计算'
  data['planetNames'] = visible.map((planet: CardPlanetData) => planet.name ?? '').filter((name: string) => name.length > 0).join(' · ') || '当前无行星在地平线上'
  data['meteorSummary'] = isOffEarth ? '仅地球适用' : (showers.length > 0 ? showers[0].name ?? '活动流星雨' : '无活动数据')
  data['meteorRate'] = isOffEarth ? '—' : (showers.length > 0 && showers[0].zhr !== undefined ? 'ZHR ' + String(showers[0].zhr) : '—')
  data['satelliteSummary'] = isOffEarth ? '仅地球适用' : (tonight.satellites?.enabled === true ? String(tonight.satellites.count ?? 0) + ' 颗本地卫星' : '目录未启用')

  const darkHours = sun?.darkWindowHours ?? sunCycle?.darkWindowHours
  data['darkStart'] = cardClock(sun?.astroTwilightEnd)
  data['darkEnd'] = cardClock(sun?.astroTwilightStart)
  data['sunRise'] = cardClock(sun?.rise)
  data['sunSet'] = cardClock(sun?.set)
  data['moonRise'] = cardClock(moon?.rise ?? companion?.rise)
  data['moonSet'] = cardClock(moon?.set ?? companion?.set)
  data['dataDate'] = (tonight.date ?? '').slice(0, 10)

  if (sunCycle !== undefined) {
    if (sunCycle.sunAltitude !== undefined && Number.isFinite(sunCycle.sunAltitude)) {
      data['sunAlt'] = (Math.round(sunCycle.sunAltitude * 10) / 10).toFixed(1)
    }
    data['nextSunEventType'] = sunCycle.nextSunEventType ?? ''
    data['nextSunEventText'] = cardClock(sunCycle.nextSunEventText)
  }

  const firstSample = tonight.timeline48h !== undefined && tonight.timeline48h.length > 0 ? tonight.timeline48h[0] : undefined
  if (firstSample !== undefined) {
    data['skyHexTop'] = firstSample.skyHexTop || data['skyHexTop']
    data['skyHexHorizon'] = firstSample.skyHexHorizon || data['skyHexHorizon']
  }

  // Upcoming astronomical events for CelestialEventsCard & SkyWindowCard ticker
  const compactEvents: CompactEventItem[] = []
  const rawEvents = tonight.upcomingEvents ?? []
  for (let i = 0; i < rawEvents.length && compactEvents.length < 4; i++) {
    const ev = rawEvents[i]
    const title = (ev.title ?? '').trim()
    if (title.length === 0) continue
    const atMs = Number.isFinite(ev.at) ? Math.round(ev.at ?? 0) : 0
    const jdVal = Number.isFinite(ev.jd) ? (ev.jd ?? 0) : 0
    compactEvents.push({
      id: (ev.id ?? '').slice(0, 80),
      title: title.slice(0, 48),
      kind: (ev.kind ?? 'sky').slice(0, 24),
      target: (ev.target ?? '').slice(0, 40),
      at: atMs,
      jd: Math.round(jdVal * 10000) / 10000
    })
  }
  data['upcomingEventsJson'] = JSON.stringify(compactEvents)
  if (compactEvents.length > 0) {
    const nextEv = compactEvents[0]
    data['nextEventTitle'] = nextEv.title
    data['nextEventKind'] = nextEv.kind
    data['nextEventAt'] = String(nextEv.at)
    data['nextEventJd'] = String(nextEv.jd)
    data['nextEventTarget'] = nextEv.target
    data['nextEventCountdown'] = formatCountdownZh(nextEv.at, now)
  } else if (!isOffEarth && showers.length > 0) {
    data['nextEventTitle'] = showers[0].name ?? '活动流星雨'
    data['nextEventKind'] = 'meteor'
    data['nextEventCountdown'] = data['meteorRate']
  } else {
    data['nextEventTitle'] = obsPlanetName + '实时星历已同步'
    data['nextEventKind'] = 'sky'
    data['nextEventCountdown'] = '查看日历'
  }

  if (isOffEarth) {
    const nextLabel = sunCycle?.nextSunEventType === 'sunset' ? ('日落 ' + data['nextSunEventText'])
      : sunCycle?.nextSunEventType === 'sunrise' ? ('日出 ' + data['nextSunEventText'])
      : sunCycle?.nextSunEventType === 'polar-day' ? '持续白昼'
      : '持续黑夜'
    data['observationSummary'] = nextLabel
    data['subtitle'] = obsPlanetName + '观测 · ' + data['dataDate']
    data['summary'] = obsPlanetName + ' · ' + nextLabel
  } else {
    data['observationSummary'] = darkHours !== undefined && Number.isFinite(darkHours) && darkHours > 0
      ? (Math.round(darkHours * 10) / 10).toFixed(1) + ' 小时暗夜' : '无完整天文暗夜'
    data['subtitle'] = '天穹手札 · ' + data['dataDate']
    data['summary'] = data['darkStart'] + ' – ' + data['darkEnd'] + '  天文暗夜'
  }

  data['calculatedAt'] = String(now)
  data['dataStatus'] = '本地星历'
  const updated = new Date(now)
  data['updatedAt'] = String(updated.getHours()).padStart(2, '0') + ':' + String(updated.getMinutes()).padStart(2, '0') + ' 更新'
  return data
}

export function normalizeAstronomyCard(raw: string, now: number): Record<string, string> {
  const fallback = defaultAstronomyCard()
  try {
    const parsed = JSON.parse(raw) as Record<string, string>
    if (parsed === null || (parsed['schemaVersion'] !== '4' && parsed['schemaVersion'] !== '3')) return fallback
    const longKeys = ['visiblePlanetsJson', 'upcomingEventsJson', 'remindedEventIds']
    const keys = Object.keys(fallback)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const val = parsed[key]
      if (typeof val === 'string') {
        const limit = longKeys.includes(key) ? 1600 : 200
        fallback[key] = val.slice(0, limit)
      }
    }
    fallback['schemaVersion'] = '4'
    const calculatedAt = Number(fallback['calculatedAt'])
    if (!Number.isFinite(calculatedAt) || calculatedAt <= 0 || now - calculatedAt > 6 * 60 * 60 * 1000 || calculatedAt > now + 60000) {
      fallback['dataStatus'] = '旧快照'
      fallback['updatedAt'] = '最近数据 · 待更新'
    }
    // Recompute live countdown string on normalize so event countdown stays accurate
    const nextAt = Number(fallback['nextEventAt'])
    if (Number.isFinite(nextAt) && nextAt > 0) {
      fallback['nextEventCountdown'] = formatCountdownZh(nextAt, now)
    }
    return fallback
  } catch (_) {
    return fallback
  }
}

export function applyCardConfigToSnapshot(
  card: Record<string, string>,
  config: CardInstanceConfig,
  now: number
): Record<string, string> {
  card['cardPlanetMode'] = config.planetMode
  card['cardThemeStyle'] = config.themeStyle
  card['cardLabelStyle'] = config.labelStyle
  card['cardOverflowMode'] = config.overflowMode
  if (config.themeStyle === 'deep') {
    card['skyHexTop'] = '#050811'
    card['skyHexHorizon'] = '#0D1528'
  }
  const nextAt = Number(card['nextEventAt'])
  if (Number.isFinite(nextAt) && nextAt > 0) {
    card['nextEventCountdown'] = formatCountdownZh(nextAt, now)
  }
  return card
}

export function moonSilhouette(size: number, illumination: number, age: number): string {
  const fraction = Math.max(0, Math.min(100, illumination)) / 100
  const radius = size * 0.39
  const center = size / 2
  const terminator = Math.max(0.02, Math.abs(2 * fraction - 1)) * radius
  const waxing = age <= 14.765
  const outerSweep = waxing ? 1 : 0
  const innerSweep = waxing ? 0 : 1
  const outerArc = 'A ' + radius + ' ' + radius + ' 0 0 ' + outerSweep + ' ' + center + ' ' + (center + radius)
  const innerArc = 'A ' + terminator + ' ' + radius + ' 0 0 ' + innerSweep + ' ' + center + ' ' + (center - radius)
  return 'M ' + center + ' ' + (center - radius) + ' ' + outerArc + ' ' + innerArc + ' Z'
}

function parseHexChannel(hex: string, offset: number): number {
  const parsed = parseInt(hex.slice(offset, offset + 2), 16)
  return Number.isFinite(parsed) ? parsed : 0
}

function lerpHex(a: string, b: string, t: number): string {
  if (!/^#[0-9A-Fa-f]{6}$/.test(a) || !/^#[0-9A-Fa-f]{6}$/.test(b)) return a || '#070B16'
  const mix = (x: number, y: number): string => Math.max(0, Math.min(255, Math.round(x + (y - x) * t))).toString(16).padStart(2, '0').toUpperCase()
  return '#' + mix(parseHexChannel(a, 1), parseHexChannel(b, 1)) +
    mix(parseHexChannel(a, 3), parseHexChannel(b, 3)) +
    mix(parseHexChannel(a, 5), parseHexChannel(b, 5))
}

export function buildTimeline48hSnapshot(tonight: CardTonightData, now: number): string {
  const raw = tonight.timeline48h
  if (!Array.isArray(raw) || raw.length === 0) return ''
  const samples: CardTimelineSample[] = []
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i]
    if (item === null || typeof item !== 'object') continue
    if (!Number.isFinite(item.at) || !Number.isFinite(item.sunAlt)) continue
    samples.push({
      at: Math.round(item.at),
      sunAlt: Math.round(item.sunAlt * 10) / 10,
      skyHexTop: typeof item.skyHexTop === 'string' && /^#[0-9A-Fa-f]{6}$/.test(item.skyHexTop) ? item.skyHexTop : '#070B16',
      skyHexHorizon: typeof item.skyHexHorizon === 'string' && /^#[0-9A-Fa-f]{6}$/.test(item.skyHexHorizon) ? item.skyHexHorizon : '#121D33',
      companionAlt: Number.isFinite(item.companionAlt) ? Math.round(item.companionAlt * 10) / 10 : -90,
      companionIllum: Number.isFinite(item.companionIllum) ? Math.max(0, Math.min(100, Math.round(item.companionIllum * 10) / 10)) : 0
    })
  }
  if (samples.length < 2) return ''
  samples.sort((a: CardTimelineSample, b: CardTimelineSample) => a.at - b.at)
  const payload: Timeline48hSnapshot = {
    version: 1,
    generatedAt: now,
    observerPlanet: tonight.observer?.planet?.trim() || 'Earth',
    samples: samples.slice(0, 32)
  }
  return JSON.stringify(payload)
}

export function interpolateTimeline48h(raw: string, now: number): InterpolatedTimelineState | undefined {
  if (typeof raw !== 'string' || raw.length === 0) return undefined
  try {
    const parsed = JSON.parse(raw) as Timeline48hSnapshot
    if (parsed === null || parsed.version !== 1 || !Array.isArray(parsed.samples) || parsed.samples.length < 2) return undefined
    const samples = parsed.samples
    const first = samples[0]
    const last = samples[samples.length - 1]
    if (now < first.at - 15 * 60000 || now > last.at + 15 * 60000) return undefined
    if (now <= first.at) {
      return { valid: true, sunAlt: first.sunAlt, skyHexTop: first.skyHexTop, skyHexHorizon: first.skyHexHorizon,
        companionAlt: first.companionAlt, companionIllum: first.companionIllum }
    }
    if (now >= last.at) {
      return { valid: true, sunAlt: last.sunAlt, skyHexTop: last.skyHexTop, skyHexHorizon: last.skyHexHorizon,
        companionAlt: last.companionAlt, companionIllum: last.companionIllum }
    }
    for (let i = 0; i + 1 < samples.length; i++) {
      const lo = samples[i]
      const hi = samples[i + 1]
      if (now >= lo.at && now <= hi.at) {
        const span = Math.max(1, hi.at - lo.at)
        const t = Math.max(0, Math.min(1, (now - lo.at) / span))
        return {
          valid: true,
          sunAlt: Math.round((lo.sunAlt + (hi.sunAlt - lo.sunAlt) * t) * 10) / 10,
          skyHexTop: lerpHex(lo.skyHexTop, hi.skyHexTop, t),
          skyHexHorizon: lerpHex(lo.skyHexHorizon, hi.skyHexHorizon, t),
          companionAlt: Math.round((lo.companionAlt + (hi.companionAlt - lo.companionAlt) * t) * 10) / 10,
          companionIllum: Math.round((lo.companionIllum + (hi.companionIllum - lo.companionIllum) * t) * 10) / 10
        }
      }
    }
    return undefined
  } catch (_) {
    return undefined
  }
}

export function applyTimeline48hToCard(card: Record<string, string>, timelineRaw: string, now: number): Record<string, string> {
  const live = interpolateTimeline48h(timelineRaw, now)
  if (live === undefined || !live.valid) return card
  card['sunAlt'] = live.sunAlt.toFixed(1)
  card['skyHexTop'] = live.skyHexTop
  card['skyHexHorizon'] = live.skyHexHorizon
  card['companionAlt'] = live.companionAlt.toFixed(1)
  if (live.companionIllum >= 0 && live.companionIllum <= 100) {
    card['moonIllumination'] = String(live.companionIllum)
    card['moonSummary'] = String(Math.round(live.companionIllum)) + '% 照明'
  }
  card['dataStatus'] = '48h 离线星历'
  const clock = new Date(now)
  card['updatedAt'] = String(clock.getHours()).padStart(2, '0') + ':' + String(clock.getMinutes()).padStart(2, '0') + ' 推演'
  const nextAt = Number(card['nextEventAt'])
  if (Number.isFinite(nextAt) && nextAt > 0) {
    card['nextEventCountdown'] = formatCountdownZh(nextAt, now)
  }
  return card
}
