// Unified Satellite Archetype, Iconography, Palette & Future 3D Model Registry.
// Shared across Desktop Cards (SatellitePassCard), API 20 Overflow (SkyLiveFormPage),
// and in-app Satellite Panels / Object Inspector.

export type SatelliteArchetype =
  'iss' | 'tiangong' | 'telescope' | 'comms' | 'earth_obs' | 'constellation'

// Pre-architected contract for future 3D satellite .glb / procedural mesh rendering
// inside DetailModelRenderClient & ObjectInspectorModelOverlay.
export interface SatelliteModel3DSpec {
  modelId: string
  assetPath: string
  ready: boolean
  defaultYawDeg: number
  defaultPitchDeg: number
  solarPanelAxis: string
  supportsSunGlint: boolean
}

export interface SatelliteVisualProfile {
  archetype: SatelliteArchetype
  categoryLabelZh: string
  iconKey: string
  accentHex: string
  secondaryHex: string
  glowHex: string
  model3d: SatelliteModel3DSpec
}

export interface CompactSatellitePass {
  id: string
  name: string
  englishName: string
  archetype: SatelliteArchetype
  startAt: number
  peakAt: number
  endAt: number
  peakJd: number
  maxAlt: number
  startAz: number
  peakAz: number
  endAz: number
  mag: number
  rangeKm: number
  durationSec: number
  visible: boolean
}

export function classifySatelliteArchetype(
  name: string,
  catalogId: string = '',
  groups: string = ''
): SatelliteArchetype {
  const cid = catalogId.trim()
  const hay = (name + ' ' + groups).toLowerCase()

  // Iconic crewed space stations by NORAD ID or name
  if (cid === '25544' || hay.includes('iss') || hay.includes('zarya') || hay.includes('国际空间站')) {
    return 'iss'
  }
  if (cid === '48274' || hay.includes('css') || hay.includes('tianhe') || hay.includes('tiangong') ||
    hay.includes('天宫') || hay.includes('中国空间站') || hay.includes('天和')) {
    return 'tiangong'
  }
  // Space telescopes & observatories
  if (cid === '20580' || hay.includes('hst') || hay.includes('hubble') || hay.includes('哈勃') ||
    hay.includes('jwst') || hay.includes('webb') || hay.includes('xuntian') || hay.includes('巡天') ||
    hay.includes('chandra') || hay.includes('telescope') || hay.includes('observatory')) {
    return 'telescope'
  }
  // Earth observation, weather & remote sensing
  if (hay.includes('noaa') || hay.includes('fengyun') || hay.includes('fy-') || hay.includes('风云') ||
    hay.includes('landsat') || hay.includes('sentinel') || hay.includes('terra') || hay.includes('aqua') ||
    hay.includes('metop') || hay.includes('goes') || hay.includes('himawari') || hay.includes('weather') ||
    hay.includes('earth') || hay.includes('gaofen') || hay.includes('高分') || hay.includes('气象')) {
    return 'earth_obs'
  }
  // Comms, broadcast & relay
  if (hay.includes('intelsat') || hay.includes('ses') || hay.includes('eutelsat') || hay.includes('inmarsat') ||
    hay.includes('iridium') || hay.includes('铱星') || hay.includes('tianlian') || hay.includes('天链') ||
    hay.includes('amateur') || hay.includes('oscar') || hay.includes('comms') || hay.includes('通信') ||
    hay.includes('chinasat') || hay.includes('中星')) {
    return 'comms'
  }
  // LEO constellations, navigation (GPS / BeiDou / Galileo / Starlink) & bright rocket bodies
  return 'constellation'
}

export function satelliteVisualProfile(archetype: SatelliteArchetype): SatelliteVisualProfile {
  if (archetype === 'iss') {
    return {
      archetype: 'iss',
      categoryLabelZh: '国际空间站',
      iconKey: 'iss',
      accentHex: '#FFD166',
      secondaryHex: '#68D8FF',
      glowHex: '#55FFD166',
      model3d: {
        modelId: 'iss_v1',
        assetPath: 'rawfile://models/satellites/iss_v1.glb',
        ready: false,
        defaultYawDeg: -28,
        defaultPitchDeg: 18,
        solarPanelAxis: 'Y',
        supportsSunGlint: true
      }
    }
  }
  if (archetype === 'tiangong') {
    return {
      archetype: 'tiangong',
      categoryLabelZh: '中国空间站',
      iconKey: 'tiangong',
      accentHex: '#FFC857',
      secondaryHex: '#6DF5F5',
      glowHex: '#55FFC857',
      model3d: {
        modelId: 'css_tiangong_v1',
        assetPath: 'rawfile://models/satellites/css_tiangong_v1.glb',
        ready: false,
        defaultYawDeg: -24,
        defaultPitchDeg: 20,
        solarPanelAxis: 'X',
        supportsSunGlint: true
      }
    }
  }
  if (archetype === 'telescope') {
    return {
      archetype: 'telescope',
      categoryLabelZh: '空间望远镜',
      iconKey: 'telescope',
      accentHex: '#C4A8FF',
      secondaryHex: '#6CE5FF',
      glowHex: '#55B99BFF',
      model3d: {
        modelId: 'hst_v1',
        assetPath: 'rawfile://models/satellites/hst_v1.glb',
        ready: false,
        defaultYawDeg: -34,
        defaultPitchDeg: 16,
        solarPanelAxis: 'Y',
        supportsSunGlint: true
      }
    }
  }
  if (archetype === 'comms') {
    return {
      archetype: 'comms',
      categoryLabelZh: '通信卫星',
      iconKey: 'comms',
      accentHex: '#FF8696',
      secondaryHex: '#5E9EFF',
      glowHex: '#55FF7A8C',
      model3d: {
        modelId: 'comms_dish_v1',
        assetPath: 'rawfile://models/satellites/comms_dish_v1.glb',
        ready: false,
        defaultYawDeg: -42,
        defaultPitchDeg: 22,
        solarPanelAxis: 'X',
        supportsSunGlint: true
      }
    }
  }
  if (archetype === 'earth_obs') {
    return {
      archetype: 'earth_obs',
      categoryLabelZh: '对地观测',
      iconKey: 'earth_obs',
      accentHex: '#6DF5F5',
      secondaryHex: '#2E7BFF',
      glowHex: '#556DF5F5',
      model3d: {
        modelId: 'earth_obs_v1',
        assetPath: 'rawfile://models/satellites/earth_obs_v1.glb',
        ready: false,
        defaultYawDeg: 40,
        defaultPitchDeg: 24,
        solarPanelAxis: 'Y',
        supportsSunGlint: true
      }
    }
  }
  return {
    archetype: 'constellation',
    categoryLabelZh: '低轨亮星',
    iconKey: 'constellation',
    accentHex: '#8CD8FF',
    secondaryHex: '#4B7CFF',
    glowHex: '#557AC8FF',
    model3d: {
      modelId: 'leo_bus_v1',
      assetPath: 'rawfile://models/satellites/leo_bus_v1.glb',
      ready: false,
      defaultYawDeg: -32,
      defaultPitchDeg: 18,
      solarPanelAxis: 'X',
      supportsSunGlint: true
    }
  }
}

export function compassDirectionZh(azDeg: number): string {
  const norm = (((Number.isFinite(azDeg) ? azDeg : 0) % 360) + 360) % 360
  const labels: string[] = ['北', '东北', '东', '东南', '南', '西南', '西', '西北']
  const idx = Math.round(norm / 45) % 8
  return labels[idx]
}

export function satelliteBrightnessGradeZh(mag: number, visible: boolean): string {
  if (!visible) return '地影过境'
  if (!Number.isFinite(mag) || mag > 15) return '日照可见'
  if (mag <= -2.0) return '肉眼极亮'
  if (mag <= 0.5) return '肉眼明亮'
  if (mag <= 3.0) return '暗夜肉眼'
  return '双筒观测'
}

export function formatSatelliteDisplayNameZh(rawName: string, catalogId: string = ''): string {
  const cid = catalogId.trim()
  const lower = rawName.trim().toLowerCase()
  if (cid === '25544' || lower.startsWith('iss')) return '国际空间站 ISS'
  if (cid === '48274' || lower.includes('tianhe') || lower.startsWith('css')) return '中国空间站 天宫'
  if (cid === '20580' || lower === 'hst' || lower.includes('hubble')) return '哈勃望远镜 HST'
  return rawName.trim().length > 0 ? rawName.trim() : ('卫星 #' + cid)
}

export function formatPassDurationZh(durationSec: number): string {
  if (!Number.isFinite(durationSec) || durationSec <= 0) return '—'
  const mins = Math.max(1, Math.round(durationSec / 60))
  return String(mins) + ' 分钟'
}

export function buildFallbackSatellitePasses(nowMs: number): CompactSatellitePass[] {
  const h = 3600000
  const m = 60000
  const toJd = (ms: number): number => Math.round((ms / 86400000 + 2440587.5) * 100000) / 100000
  const p1Start = nowMs + 42 * m
  const p2Start = nowMs + 2 * h + 15 * m
  const p3Start = nowMs + 4 * h + 30 * m
  return [
    {
      id: '25544',
      name: '国际空间站 ISS',
      englishName: 'ISS (ZARYA)',
      archetype: 'iss',
      startAt: p1Start,
      peakAt: p1Start + 3 * m,
      endAt: p1Start + 6 * m,
      peakJd: toJd(p1Start + 3 * m),
      maxAlt: 68,
      startAz: 238,
      peakAz: 326,
      endAz: 52,
      mag: -3.4,
      rangeKm: 448,
      durationSec: 360,
      visible: true
    },
    {
      id: '48274',
      name: '中国空间站 天宫',
      englishName: 'CSS (TIANHE)',
      archetype: 'tiangong',
      startAt: p2Start,
      peakAt: p2Start + 3 * m,
      endAt: p2Start + 6 * m,
      peakJd: toJd(p2Start + 3 * m),
      maxAlt: 54,
      startAz: 256,
      peakAz: 176,
      endAz: 88,
      mag: -1.8,
      rangeKm: 482,
      durationSec: 340,
      visible: true
    },
    {
      id: '20580',
      name: '哈勃望远镜 HST',
      englishName: 'HST',
      archetype: 'telescope',
      startAt: p3Start,
      peakAt: p3Start + 2 * m,
      endAt: p3Start + 5 * m,
      peakJd: toJd(p3Start + 2 * m),
      maxAlt: 38,
      startAz: 215,
      peakAz: 148,
      endAz: 74,
      mag: 1.6,
      rangeKm: 675,
      durationSec: 290,
      visible: true
    }
  ]
}

export function parseSatellitePasses(rawJson: string, nowMs: number = Date.now()): CompactSatellitePass[] {
  if (typeof rawJson === 'string' && rawJson.length >= 4) {
    try {
      const parsed = JSON.parse(rawJson) as Array<CompactSatellitePass>
      if (Array.isArray(parsed) && parsed.length > 0) {
        const fresh: CompactSatellitePass[] = []
        for (let i = 0; i < parsed.length && fresh.length < 6; i++) {
          const item = parsed[i]
          if (item === null || typeof item !== 'object') continue
          if (typeof item.id !== 'string' || item.id.length === 0) continue
          const endMs = Number.isFinite(item.endAt) && item.endAt > 0 ? item.endAt : (item.startAt + 360000)
          if (endMs < nowMs - 10 * 60000) continue
          const arch: SatelliteArchetype = item.archetype || classifySatelliteArchetype(item.englishName + ' ' + item.name, item.id)
          fresh.push({
            id: item.id,
            name: formatSatelliteDisplayNameZh(item.name || item.englishName, item.id),
            englishName: item.englishName || item.name || item.id,
            archetype: arch,
            startAt: Math.round(item.startAt),
            peakAt: Number.isFinite(item.peakAt) && item.peakAt > 0 ? Math.round(item.peakAt) : Math.round(item.startAt + 180000),
            endAt: Math.round(endMs),
            peakJd: Number.isFinite(item.peakJd) ? item.peakJd : 0,
            maxAlt: Number.isFinite(item.maxAlt) ? Math.round(item.maxAlt * 10) / 10 : 30,
            startAz: Number.isFinite(item.startAz) ? Math.round(item.startAz) : 240,
            peakAz: Number.isFinite(item.peakAz) ? Math.round(item.peakAz) : 315,
            endAz: Number.isFinite(item.endAz) ? Math.round(item.endAz) : 50,
            mag: Number.isFinite(item.mag) ? Math.round(item.mag * 10) / 10 : 99,
            rangeKm: Number.isFinite(item.rangeKm) ? Math.round(item.rangeKm) : 500,
            durationSec: Number.isFinite(item.durationSec) ? Math.round(item.durationSec) : 300,
            visible: item.visible === true
          })
        }
        if (fresh.length > 0) return fresh
      }
    } catch (_) {
      // Fallback below
    }
  }
  return buildFallbackSatellitePasses(nowMs)
}

export function satellitePassReminderId(pass: CompactSatellitePass): string {
  const minuteBucket = Math.round(pass.peakAt / 60000)
  return 'satellite-pass-' + pass.id + '-' + String(minuteBucket)
}
