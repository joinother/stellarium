export interface CardMoonData {
  phaseName?: string
  illumination?: number
  age?: number
  rise?: string
  set?: string
}

export interface CardPlanetData {
  name?: string
  visible?: boolean
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

export interface CardTonightData {
  date?: string
  observer?: CardObserverData
  companion?: CardCompanionData
  sunCycle?: CardSunCycleData
  timeline48h?: CardTimelineSample[]
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

export function cardClock(value: string | undefined): string {
  const match = (value ?? '').match(/T(\d{2}:\d{2})/)
  return match === null ? '—' : match[1]
}

export function defaultAstronomyCard(): Record<string, string> {
  return {
    schemaVersion: '3', title: '星象仪', subtitle: '本地观测摘要', summary: '卡片已就绪 · 使用最近星历',
    moonSummary: '最近星历', moonPhase: '今夜月相', moonIllumination: '-1', moonAge: '0',
    planetSummary: '今晚行星', planetNames: '本地星体目录已就绪', meteorSummary: '流星雨活动',
    meteorRate: '—', satelliteSummary: '卫星目录已就绪', observationSummary: '暗夜观测',
    darkStart: '—', darkEnd: '—', moonRise: '—', moonSet: '—', sunRise: '—', sunSet: '—',
    updatedAt: '最近一次本地计算', calculatedAt: '0', dataDate: '', dataStatus: '本地快照',
    observerPlanet: 'Earth', observerPlanetName: '地球', atmosphereProfile: 'earth',
    companionName: '月球', companionRole: 'moon', companionAlt: '0',
    skyHexTop: '#070B16', skyHexHorizon: '#121D33', sunAlt: '-18',
    nextSunEventType: '', nextSunEventText: '—'
  }
}

export function buildAstronomyCard(tonight: CardTonightData, now: number): Record<string, string> {
  const data = defaultAstronomyCard()
  const observer = tonight.observer
  const isOffEarth = observer !== undefined && (observer.isEarth === false ||
    (typeof observer.planet === 'string' && observer.planet.trim().length > 0 && observer.planet.trim().toLowerCase() !== 'earth'))
  const obsPlanet = isOffEarth ? (observer?.planet?.trim() || 'Earth') : 'Earth'
  const obsPlanetName = isOffEarth ? (observer?.planetZh || observer?.planetLocalized || obsPlanet) : '地球'
  const companion = tonight.companion
  const sunCycle = tonight.sunCycle
  const moon = tonight.moon
  const sun = tonight.sun
  const planets = tonight.planets ?? []
  const visible = planets.filter((planet: CardPlanetData) => planet.visible === true)
  const showers = (tonight.meteorShowers ?? []).slice().sort((first: CardShowerData, second: CardShowerData) =>
    (second.zhr ?? 0) - (first.zhr ?? 0))
  const illumination = companion?.illumination ?? moon?.illumination
  data.observerPlanet = obsPlanet
  data.observerPlanetName = obsPlanetName
  data.atmosphereProfile = observer?.atmosphereProfile ?? (isOffEarth ? obsPlanet.toLowerCase() : 'earth')
  data.companionName = companion?.name ?? (isOffEarth ? '当地伴星' : '月球')
  data.companionRole = companion?.role ?? 'moon'
  if (companion?.altitude !== undefined && Number.isFinite(companion.altitude)) {
    data.companionAlt = (Math.round(companion.altitude * 10) / 10).toFixed(1)
  }
  data.moonPhase = companion?.phaseName ?? moon?.phaseName ?? '月相待计算'
  data.moonIllumination = illumination !== undefined && Number.isFinite(illumination)
    ? String(Math.max(0, Math.min(100, illumination))) : '-1'
  data.moonAge = String(moon?.age ?? companion?.age ?? 0)
  data.moonSummary = illumination !== undefined && Number.isFinite(illumination)
    ? String(Math.round(Math.max(0, Math.min(100, illumination)))) + '% 照明' : '待计算'
  data.planetSummary = planets.length > 0 ? String(visible.length) + ' 颗在地平线上' : '待计算'
  data.planetNames = visible.map((planet: CardPlanetData) => planet.name ?? '').filter((name: string) => name.length > 0).join(' · ') || '当前无行星在地平线上'
  data.meteorSummary = isOffEarth ? '仅地球适用' : (showers.length > 0 ? showers[0].name ?? '活动流星雨' : '无活动数据')
  data.meteorRate = isOffEarth ? '—' : (showers.length > 0 && showers[0].zhr !== undefined ? 'ZHR ' + String(showers[0].zhr) : '—')
  data.satelliteSummary = isOffEarth ? '仅地球适用' : (tonight.satellites?.enabled === true ? String(tonight.satellites.count ?? 0) + ' 颗本地卫星' : '目录未启用')
  const darkHours = sun?.darkWindowHours ?? sunCycle?.darkWindowHours
  data.darkStart = cardClock(sun?.astroTwilightEnd)
  data.darkEnd = cardClock(sun?.astroTwilightStart)
  data.sunRise = cardClock(sun?.rise)
  data.sunSet = cardClock(sun?.set)
  data.moonRise = cardClock(moon?.rise ?? companion?.rise)
  data.moonSet = cardClock(moon?.set ?? companion?.set)
  data.dataDate = (tonight.date ?? '').slice(0, 10)
  if (sunCycle !== undefined) {
    if (sunCycle.sunAltitude !== undefined && Number.isFinite(sunCycle.sunAltitude)) {
      data.sunAlt = (Math.round(sunCycle.sunAltitude * 10) / 10).toFixed(1)
    }
    data.nextSunEventType = sunCycle.nextSunEventType ?? ''
    data.nextSunEventText = cardClock(sunCycle.nextSunEventText)
  }
  const firstSample = tonight.timeline48h !== undefined && tonight.timeline48h.length > 0 ? tonight.timeline48h[0] : undefined
  if (firstSample !== undefined) {
    data.skyHexTop = firstSample.skyHexTop || data.skyHexTop
    data.skyHexHorizon = firstSample.skyHexHorizon || data.skyHexHorizon
  }
  if (isOffEarth) {
    const nextLabel = sunCycle?.nextSunEventType === 'sunset' ? ('日落 ' + data.nextSunEventText)
      : sunCycle?.nextSunEventType === 'sunrise' ? ('日出 ' + data.nextSunEventText)
      : sunCycle?.nextSunEventType === 'polar-day' ? '持续白昼'
      : '持续黑夜'
    data.observationSummary = nextLabel
    data.subtitle = obsPlanetName + '观测 · ' + data.dataDate
    data.summary = obsPlanetName + ' · ' + nextLabel
  } else {
    data.observationSummary = darkHours !== undefined && Number.isFinite(darkHours) && darkHours > 0
      ? (Math.round(darkHours * 10) / 10).toFixed(1) + ' 小时暗夜' : '无完整天文暗夜'
    data.subtitle = '观星手札 · ' + data.dataDate
    data.summary = data.darkStart + ' – ' + data.darkEnd + '  天文暗夜'
  }
  data.calculatedAt = String(now)
  data.dataStatus = '本地星历'
  const updated = new Date(now)
  data.updatedAt = String(updated.getHours()).padStart(2, '0') + ':' + String(updated.getMinutes()).padStart(2, '0') + ' 更新'
  return data
}

export function normalizeAstronomyCard(raw: string, now: number): Record<string, string> {
  const fallback = defaultAstronomyCard()
  try {
    const parsed = JSON.parse(raw) as Record<string, string>
    if (parsed === null || parsed.schemaVersion !== '3') return fallback
    for (const key of Object.keys(fallback)) {
      if (typeof parsed[key] === 'string') fallback[key] = parsed[key].slice(0, 200)
    }
    const calculatedAt = Number(fallback.calculatedAt)
    if (!Number.isFinite(calculatedAt) || calculatedAt <= 0 || now - calculatedAt > 6 * 60 * 60 * 1000 || calculatedAt > now + 60000) {
      fallback.dataStatus = '旧快照'
      fallback.updatedAt = '最近数据 · 待更新'
    }
    return fallback
  } catch (_) {
    return fallback
  }
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
  for (const item of raw) {
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
  card.sunAlt = live.sunAlt.toFixed(1)
  card.skyHexTop = live.skyHexTop
  card.skyHexHorizon = live.skyHexHorizon
  card.companionAlt = live.companionAlt.toFixed(1)
  if (live.companionIllum >= 0 && live.companionIllum <= 100) {
    card.moonIllumination = String(live.companionIllum)
    card.moonSummary = String(Math.round(live.companionIllum)) + '% 照明'
  }
  card.dataStatus = '48h 离线星历'
  const clock = new Date(now)
  card.updatedAt = String(clock.getHours()).padStart(2, '0') + ':' + String(clock.getMinutes()).padStart(2, '0') + ' 推演'
  return card
}
