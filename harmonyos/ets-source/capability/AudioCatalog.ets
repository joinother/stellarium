// AudioCatalog.ets
// 观星音景语义映射、dBFS 增益分级表与热插拔素材路径规范（纯逻辑模块，无 NAPI/MediaKit 依赖）。
//
// 资产目录约定（均位于 rawfile/stellarium/audio/ 或沙箱热更新目录 filesDir/audio/）：
//   theme_deep_space.m4a               默认无缝循环背景主题
//   stars/{O,B,A,F,G,K,M}.m4a          恒星 7 光谱型和弦
//   solar/sun.m4a, moon.m4a, comet.m4a, minor_body.m4a
//   solar/terrestrial_1..5.m4a         岩质行星专属变体
//   solar/gas_giant_1..5.m4a           气态/冰巨星专属变体
//   dso/{diffuse_nebula,planetary_nebula,dark_nebula,supernova,open_cluster,globular_cluster,galaxy}.m4a
//   constellations/constellation_0..14.m4a   星座反疲劳轮转池
//   satellites/station_tiangong.m4a, station_iss.m4a, satellite_0..2.m4a
//   bands/{xray,radio,infrared}.m4a    多波段切换音景
//   ui/{wheel_tick,panel_open,panel_close,target_lock,toggle,confirm}.m4a

import type { StellariumBridgeResponse } from '../pages/StellariumTypes'

export const AUDIO_RAW_ROOT: string = 'stellarium/audio'
export const DEFAULT_AMBIENT_THEME_PATH: string = 'stellarium/audio/theme_deep_space.m4a'
export const DEFAULT_AMBIENT_GAIN_DB: number = -4.0
export const AMBIENT_DUCK_OFFSET_DB: number = -10.0
export const AMBIENT_CROSSFADE_MS: number = 1200
export const AMBIENT_FADE_MS: number = 900

export type UiAudioCueKind =
  'wheel_tick' |
  'panel_open' |
  'panel_close' |
  'target_lock' |
  'toggle' |
  'confirm' |
  'deselect' |
  'loupe_open' |
  'loupe_close' |
  'loupe_fullscreen' |
  'loupe_blip' |
  'shatter' |
  'multiselect'

export type AetherisMoodId = 'newmoon' | 'fullmoon' | 'aurora' | 'twilight' | 'oriental'
export type AetherisMaterialPreset = 'jade' | 'felt' | 'tape' | 'bowl'

export interface AetherisMaterialWeights {
  jade: number
  felt: number
  tape: number
  bowl: number
}

export function materialWeightsForPreset(preset: AetherisMaterialPreset): AetherisMaterialWeights {
  switch (preset) {
    case 'felt':
      return { jade: 0.12, felt: 0.86, tape: 0.32, bowl: 0.20 }
    case 'tape':
      return { jade: 0.08, felt: 0.25, tape: 0.90, bowl: 0.24 }
    case 'bowl':
      return { jade: 0.28, felt: 0.12, tape: 0.20, bowl: 0.88 }
    case 'jade':
    default:
      return { jade: 0.68, felt: 0.44, tape: 0.16, bowl: 0.26 }
  }
}

export function normalizeAetherisMood(raw: string): AetherisMoodId {
  if (raw === 'fullmoon' || raw === 'aurora' || raw === 'twilight' || raw === 'oriental') {
    return raw
  }
  return 'newmoon'
}

export function normalizeAetherisMaterial(raw: string): AetherisMaterialPreset {
  if (raw === 'felt' || raw === 'tape' || raw === 'bowl') {
    return raw
  }
  return 'jade'
}

export type CelestialAudioCategory =
  'star' |
  'sun' |
  'moon' |
  'terrestrial' |
  'gas_giant' |
  'comet' |
  'minor_body' |
  'nebula' |
  'cluster' |
  'galaxy' |
  'constellation' |
  'station' |
  'satellite' |
  'band' |
  'default'

export interface ResolvedCelestialCue {
  cueId: string
  assetPath: string
  fallbackAssetPath: string
  gainDb: number
  category: CelestialAudioCategory
}

export interface UiAudioCueSpec {
  cue: UiAudioCueKind
  assetPath: string
  gainDb: number
  minIntervalMs: number
}

export class AudioRotationState {
  constellationIndex: number = 0
  satelliteIndex: number = 0

  nextConstellationSlot(poolSize: number = 15): number {
    const size = Math.max(1, poolSize)
    const slot = this.constellationIndex % size
    this.constellationIndex = (slot + 1) % size
    return slot
  }

  nextSatelliteSlot(poolSize: number = 3): number {
    const size = Math.max(1, poolSize)
    const slot = this.satelliteIndex % size
    this.satelliteIndex = (slot + 1) % size
    return slot
  }
}

export function dbToLinear(db: number): number {
  if (!Number.isFinite(db)) {
    return 0.0
  }
  if (db <= -80.0) {
    return 0.0
  }
  const linear = Math.pow(10.0, db / 20.0)
  return Math.max(0.0, Math.min(1.0, linear))
}

export function clampVolume(value: number): number {
  if (!Number.isFinite(value)) {
    return 0.7
  }
  return Math.max(0.0, Math.min(1.0, value))
}

export function hashStableName(name: string): number {
  let h: number = 0
  for (let i = 0; i < name.length; i++) {
    h = (h * 31 + name.charCodeAt(i)) | 0
  }
  return Math.abs(h)
}

export function spectralClassFromTemperature(tempK: number): string {
  if (tempK >= 28000) { return 'O' }
  if (tempK >= 10000) { return 'B' }
  if (tempK >= 7500) { return 'A' }
  if (tempK >= 6000) { return 'F' }
  if (tempK >= 5200) { return 'G' }
  if (tempK >= 3700) { return 'K' }
  if (tempK > 0) { return 'M' }
  return 'G'
}

export function computeStarGainDb(magnitude: number): number {
  if (!Number.isFinite(magnitude) || magnitude > 50) {
    return -7.0
  }
  // 亮星饱满（约 -3.5 dB），暗星轻柔遥远（约 -13.5 dB）
  const clampedMag = Math.max(-1.5, Math.min(8.5, magnitude))
  const norm = (clampedMag + 1.5) / 10.0
  return -3.5 - norm * 10.0
}

function terrestrialVariantForName(lowerName: string): number {
  if (lowerName.includes('mercury')) { return 1 }
  if (lowerName.includes('venus')) { return 2 }
  if (lowerName.includes('mars')) { return 3 }
  if (lowerName.includes('earth')) { return 4 }
  return 5
}

function gasGiantVariantForName(lowerName: string): number {
  if (lowerName.includes('jupiter')) { return 1 }
  if (lowerName.includes('saturn')) { return 2 }
  if (lowerName.includes('uranus')) { return 3 }
  if (lowerName.includes('neptune')) { return 4 }
  return 5
}

function isGasGiantName(lowerName: string): boolean {
  return lowerName.includes('jupiter') ||
    lowerName.includes('saturn') ||
    lowerName.includes('uranus') ||
    lowerName.includes('neptune')
}

function isTiangongStation(lowerName: string): boolean {
  return lowerName.includes('css') ||
    lowerName.includes('tiangong') ||
    lowerName.includes('tianhe') ||
    lowerName.includes('天宫') ||
    lowerName.includes('天和')
}

function isIssStation(lowerName: string): boolean {
  return lowerName === 'iss' ||
    lowerName.includes('iss (zarya)') ||
    lowerName.includes('international space station') ||
    lowerName.includes('zarya') ||
    lowerName.includes('国际空间站')
}

export function resolveCelestialAudioCue(
  info: StellariumBridgeResponse,
  rotation: AudioRotationState
): ResolvedCelestialCue {
  const rawName: string = (info.englishName && info.englishName.length > 0)
    ? info.englishName
    : (info.name && info.name.length > 0 ? info.name : '')
  const lowerName: string = rawName.toLowerCase()
  const otype: string = (info.objectType ? info.objectType : (info.type ? info.type : '')).toLowerCase()
  const mag: number = (typeof info.magnitude === 'number') ? info.magnitude as number : 99
  const tempK: number = (typeof info.temperatureK === 'number') ? info.temperatureK as number : 0

  // 1. 太阳
  if (lowerName === 'sun' || (otype === 'star' && lowerName.includes('sun'))) {
    return {
      cueId: 'sun',
      assetPath: `${AUDIO_RAW_ROOT}/solar/sun.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/stars/G.m4a`,
      gainDb: -4.0,
      category: 'sun'
    }
  }

  // 2. 月球与行星卫星
  if (lowerName === 'moon' || otype.includes('moon')) {
    return {
      cueId: 'moon',
      assetPath: `${AUDIO_RAW_ROOT}/solar/moon.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/solar/terrestrial_4.m4a`,
      gainDb: -5.5,
      category: 'moon'
    }
  }

  // 3. 人造卫星与空间站（优先识别天宫 / ISS 专属轨道签名）
  if (otype.includes('artificial') || otype.includes('satellite')) {
    if (isTiangongStation(lowerName)) {
      return {
        cueId: 'station_tiangong',
        assetPath: `${AUDIO_RAW_ROOT}/satellites/station_tiangong.m4a`,
        fallbackAssetPath: `${AUDIO_RAW_ROOT}/satellites/satellite_0.m4a`,
        gainDb: -5.0,
        category: 'station'
      }
    }
    if (isIssStation(lowerName)) {
      return {
        cueId: 'station_iss',
        assetPath: `${AUDIO_RAW_ROOT}/satellites/station_iss.m4a`,
        fallbackAssetPath: `${AUDIO_RAW_ROOT}/satellites/satellite_0.m4a`,
        gainDb: -5.0,
        category: 'station'
      }
    }
    const slot = rotation.nextSatelliteSlot(3)
    return {
      cueId: `satellite_${slot}`,
      assetPath: `${AUDIO_RAW_ROOT}/satellites/satellite_${slot}.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/satellites/satellite_0.m4a`,
      gainDb: -7.5,
      category: 'satellite'
    }
  }

  // 4. 星座（15 变体防疲劳轮转）
  if (otype.includes('constellation')) {
    const slot = rotation.nextConstellationSlot(15)
    return {
      cueId: `constellation_${slot}`,
      assetPath: `${AUDIO_RAW_ROOT}/constellations/constellation_${slot}.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/constellations/constellation_0.m4a`,
      gainDb: -5.5,
      category: 'constellation'
    }
  }

  // 5. 彗星与小天体
  if (otype.includes('comet')) {
    return {
      cueId: 'comet',
      assetPath: `${AUDIO_RAW_ROOT}/solar/comet.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/stars/A.m4a`,
      gainDb: -5.5,
      category: 'comet'
    }
  }
  if (otype.includes('asteroid') || otype.includes('minor') || otype.includes('plut') || otype.includes('dwarf')) {
    return {
      cueId: 'minor_body',
      assetPath: `${AUDIO_RAW_ROOT}/solar/minor_body.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/solar/terrestrial_5.m4a`,
      gainDb: -6.5,
      category: 'minor_body'
    }
  }

  // 6. 行星（区分气态/冰巨星与岩质行星）
  if (otype.includes('planet')) {
    if (isGasGiantName(lowerName)) {
      const idx = gasGiantVariantForName(lowerName)
      return {
        cueId: `gas_giant_${idx}`,
        assetPath: `${AUDIO_RAW_ROOT}/solar/gas_giant_${idx}.m4a`,
        fallbackAssetPath: `${AUDIO_RAW_ROOT}/solar/gas_giant_1.m4a`,
        gainDb: -4.0,
        category: 'gas_giant'
      }
    }
    const idx = terrestrialVariantForName(lowerName)
    return {
      cueId: `terrestrial_${idx}`,
      assetPath: `${AUDIO_RAW_ROOT}/solar/terrestrial_${idx}.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/solar/terrestrial_1.m4a`,
      gainDb: -5.0,
      category: 'terrestrial'
    }
  }

  // 7. 深空天体（星系、星云、星团、超新星遗迹）
  if (otype.includes('galax') || otype.includes('quasar')) {
    return {
      cueId: 'dso_galaxy',
      assetPath: `${AUDIO_RAW_ROOT}/dso/galaxy.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/dso/diffuse_nebula.m4a`,
      gainDb: -4.5,
      category: 'galaxy'
    }
  }
  if (otype.includes('planetary nebula')) {
    return {
      cueId: 'dso_planetary_nebula',
      assetPath: `${AUDIO_RAW_ROOT}/dso/planetary_nebula.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/dso/diffuse_nebula.m4a`,
      gainDb: -5.0,
      category: 'nebula'
    }
  }
  if (otype.includes('dark nebula')) {
    return {
      cueId: 'dso_dark_nebula',
      assetPath: `${AUDIO_RAW_ROOT}/dso/dark_nebula.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/dso/diffuse_nebula.m4a`,
      gainDb: -6.0,
      category: 'nebula'
    }
  }
  if (otype.includes('supernova')) {
    return {
      cueId: 'dso_supernova',
      assetPath: `${AUDIO_RAW_ROOT}/dso/supernova.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/dso/diffuse_nebula.m4a`,
      gainDb: -4.5,
      category: 'nebula'
    }
  }
  if (otype.includes('nebula') || otype.includes('hii')) {
    return {
      cueId: 'dso_diffuse_nebula',
      assetPath: `${AUDIO_RAW_ROOT}/dso/diffuse_nebula.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/dso/diffuse_nebula.m4a`,
      gainDb: -4.5,
      category: 'nebula'
    }
  }
  if (otype.includes('globular')) {
    return {
      cueId: 'dso_globular_cluster',
      assetPath: `${AUDIO_RAW_ROOT}/dso/globular_cluster.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/dso/open_cluster.m4a`,
      gainDb: -5.0,
      category: 'cluster'
    }
  }
  if (otype.includes('open') || otype.includes('association') || otype.includes('cluster')) {
    return {
      cueId: 'dso_open_cluster',
      assetPath: `${AUDIO_RAW_ROOT}/dso/open_cluster.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/dso/open_cluster.m4a`,
      gainDb: -5.5,
      category: 'cluster'
    }
  }

  // 8. 恒星（按温度分 O/B/A/F/G/K/M 7 光谱型 + 视星等增益标定）
  if (otype.includes('star')) {
    const spectral = spectralClassFromTemperature(tempK)
    return {
      cueId: `star_${spectral}`,
      assetPath: `${AUDIO_RAW_ROOT}/stars/${spectral}.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/stars/G.m4a`,
      gainDb: computeStarGainDb(mag),
      category: 'star'
    }
  }

  // 9. 默认回退
  const fallbackSpectral = ['A', 'F', 'G', 'K'][hashStableName(rawName) % 4]
  return {
    cueId: `default_${fallbackSpectral}`,
    assetPath: `${AUDIO_RAW_ROOT}/stars/${fallbackSpectral}.m4a`,
    fallbackAssetPath: `${AUDIO_RAW_ROOT}/stars/G.m4a`,
    gainDb: -6.5,
    category: 'default'
  }
}

export function resolveBandAudioCue(bandId: string): ResolvedCelestialCue {
  const lower = bandId.toLowerCase()
  if (lower.includes('xray') || lower.includes('x-ray') || lower.includes('gamma')) {
    return {
      cueId: 'band_xray',
      assetPath: `${AUDIO_RAW_ROOT}/bands/xray.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/bands/xray.m4a`,
      gainDb: -8.0,
      category: 'band'
    }
  }
  if (lower.includes('radio') || lower.includes('micro') || lower.includes('cmb') || lower.includes('hi')) {
    return {
      cueId: 'band_radio',
      assetPath: `${AUDIO_RAW_ROOT}/bands/radio.m4a`,
      fallbackAssetPath: `${AUDIO_RAW_ROOT}/bands/radio.m4a`,
      gainDb: -8.0,
      category: 'band'
    }
  }
  return {
    cueId: 'band_infrared',
    assetPath: `${AUDIO_RAW_ROOT}/bands/infrared.m4a`,
    fallbackAssetPath: `${AUDIO_RAW_ROOT}/bands/infrared.m4a`,
    gainDb: -8.5,
    category: 'band'
  }
}

export function getUiAudioCueSpec(cue: UiAudioCueKind): UiAudioCueSpec {
  switch (cue) {
    case 'wheel_tick':
      return {
        cue: 'wheel_tick',
        assetPath: `${AUDIO_RAW_ROOT}/ui/wheel_tick.m4a`,
        gainDb: -22.0,
        minIntervalMs: 65
      }
    case 'panel_open':
      return {
        cue: 'panel_open',
        assetPath: `${AUDIO_RAW_ROOT}/ui/panel_open.m4a`,
        gainDb: -12.0,
        minIntervalMs: 120
      }
    case 'panel_close':
      return {
        cue: 'panel_close',
        assetPath: `${AUDIO_RAW_ROOT}/ui/panel_close.m4a`,
        gainDb: -16.0,
        minIntervalMs: 120
      }
    case 'target_lock':
      return {
        cue: 'target_lock',
        assetPath: `${AUDIO_RAW_ROOT}/ui/target_lock.m4a`,
        gainDb: -10.0,
        minIntervalMs: 140
      }
    case 'confirm':
      return {
        cue: 'confirm',
        assetPath: `${AUDIO_RAW_ROOT}/ui/confirm.m4a`,
        gainDb: -12.0,
        minIntervalMs: 140
      }
    case 'deselect':
      return {
        cue: 'deselect',
        assetPath: `${AUDIO_RAW_ROOT}/ui/deselect.m4a`,
        gainDb: -14.0,
        minIntervalMs: 110
      }
    case 'loupe_open':
      return {
        cue: 'loupe_open',
        assetPath: `${AUDIO_RAW_ROOT}/ui/loupe_open.m4a`,
        gainDb: -10.0,
        minIntervalMs: 140
      }
    case 'loupe_close':
      return {
        cue: 'loupe_close',
        assetPath: `${AUDIO_RAW_ROOT}/ui/loupe_close.m4a`,
        gainDb: -12.0,
        minIntervalMs: 140
      }
    case 'loupe_fullscreen':
      return {
        cue: 'loupe_fullscreen',
        assetPath: `${AUDIO_RAW_ROOT}/ui/loupe_fullscreen.m4a`,
        gainDb: -8.0,
        minIntervalMs: 180
      }
    case 'loupe_blip':
      return {
        cue: 'loupe_blip',
        assetPath: `${AUDIO_RAW_ROOT}/ui/wheel_tick.m4a`,
        gainDb: -18.0,
        minIntervalMs: 55
      }
    case 'shatter':
      return {
        cue: 'shatter',
        assetPath: `${AUDIO_RAW_ROOT}/ui/shatter.m4a`,
        gainDb: -8.0,
        minIntervalMs: 220
      }
    case 'multiselect':
      return {
        cue: 'multiselect',
        assetPath: `${AUDIO_RAW_ROOT}/ui/multiselect.m4a`,
        gainDb: -18.0,
        minIntervalMs: 70
      }
    case 'toggle':
    default:
      return {
        cue: 'toggle',
        assetPath: `${AUDIO_RAW_ROOT}/ui/toggle.m4a`,
        gainDb: -16.0,
        minIntervalMs: 90
      }
  }
}

export function allUiAudioCueSpecs(): UiAudioCueSpec[] {
  return [
    getUiAudioCueSpec('wheel_tick'),
    getUiAudioCueSpec('panel_open'),
    getUiAudioCueSpec('panel_close'),
    getUiAudioCueSpec('target_lock'),
    getUiAudioCueSpec('toggle'),
    getUiAudioCueSpec('confirm')
  ]
}
