import { I18n } from '../pages/I18n'
import {
  CONTENT_LAYER_ACTION_IDS, LAYER_PRESET_CUSTOM_LIMIT, MARKING_LAYER_ACTION_IDS,
  LayerPresetDefinition, LayerPresetDiffItem, LayerPresetSnapshot
} from '../common/types/MainWindowModels'

// 「图层预设」域状态：5 个内置预设 + 最多 3 个自定义预设。
//
// 快照覆盖所有图层 action 与预设涉及的跨面板状态（大气/银河/夜间/观测模式/赤道仪/
// 寻星镜/CCD/深空标签/3D 星座）。本 store 不直接访问 NAPI/UI：读取、应用与
// Preferences 持久化均经 LayerPresetHostHooks 回注宿主。
//
// “保持”语义：keepSelected 为 true 时，手动修改后仍保留所选预设高亮，并把当前
// 预设标成 dirty（星号）；关闭后，任何手动修改立即清除所选预设。

export interface LayerPresetHostHooks {
  loadPresetJson(done: (json: string) => void): void
  persistPresetJson(json: string): void
  captureSnapshot(done: (snapshot: LayerPresetSnapshot) => void): void
  applySnapshot(snapshot: LayerPresetSnapshot, done: () => void): void
  flashHint(text: string): void
  refreshState(): void
}

interface PersistedLayerPreset {
  id: string
  kind: string
  nameKey: string
  customName: string
  enabled: boolean
  snapshot: LayerPresetSnapshot
}

interface PersistedLayerPresetDocument {
  version: number
  selectedId: string
  selectedDirty: boolean
  presets: Array<PersistedLayerPreset>
}

const ALL_ACTION_IDS: string[] = MARKING_LAYER_ACTION_IDS.concat(CONTENT_LAYER_ACTION_IDS)

const CLEAN_ACTIONS: string[] = [
  'actionShow_Stars', 'actionShow_Planets', 'actionShow_Nebulas', 'actionShow_MilkyWay',
  'actionShow_Atmosphere', 'actionShow_Ground'
]

const OBSERVE_ACTIONS: string[] = [
  'actionShow_Stars', 'actionShow_Stars_Labels',
  'actionShow_Planets', 'actionShow_Planets_Labels', 'actionShow_Planets_Hints', 'actionShow_Planets_Orbits',
  'actionShow_Nebulas', 'actionShow_DSO_Textures', 'actionShow_MilkyWay',
  'actionShow_Constellation_Lines', 'actionShow_Constellation_Labels',
  'actionShow_Atmosphere', 'actionShow_Ground',
  'actionShow_Cardinal_Points', 'actionShow_Gridlines', 'actionShow_Equatorial_Grid',
  'actionShow_Ecliptic_Line', 'actionShow_Meridian_Line', 'actionShow_Horizon_Line',
  'actionShow_FOV_Center_Marker'
]

const PHOTO_ACTIONS: string[] = [
  'actionShow_Stars', 'actionShow_Nebulas', 'actionShow_DSO_Textures', 'actionShow_MilkyWay',
  'actionShow_Constellation_Lines', 'actionShow_Asterism_Labels',
  'actionShow_Atmosphere', 'actionShow_Ground',
  'actionShow_Gridlines', 'actionShow_Equatorial_Grid'
]

const STUDY_ACTIONS: string[] = [
  'actionShow_Stars', 'actionShow_Planets', 'actionShow_Nebulas', 'actionShow_MilkyWay',
  'actionShow_Constellation_Lines', 'actionShow_Constellation_Labels'
]

const VIVID_ACTIONS: string[] = [
  'actionShow_Stars', 'actionShow_Planets', 'actionShow_Nebulas', 'actionShow_MilkyWay',
  'actionShow_Atmosphere', 'actionShow_MistHorizon', 'actionShow_Constellation_Art',
  'actionShow_Constellation_Lines', 'actionShow_Constellation_Labels'
]

function emptyActions(): Record<string, boolean> {
  const actions: Record<string, boolean> = {}
  for (const id of ALL_ACTION_IDS) actions[id] = false
  return actions
}

// 星等限制滑块 / 原生 setLimitMagnitude 的上限。
const MAX_STAR_MAG_LIMIT: number = 21

function buildSnapshot(onActions: string[], vividAtmosphere: boolean, milkyWayBright: number,
  realisticStarVisibility: boolean, nightMode: boolean, observeMode: boolean,
  equatorialMount: boolean, telrad: boolean, ccd: boolean, dsoLabels: boolean,
  constellationArt3d: boolean, starMagLimit?: number): LayerPresetSnapshot {
  const actions = emptyActions()
  for (const id of onActions) actions[id] = true
  return {
    actions: actions,
    vividAtmosphere: vividAtmosphere,
    milkyWayBright: milkyWayBright,
    realisticStarVisibility: realisticStarVisibility,
    nightMode: nightMode,
    observeMode: observeMode,
    equatorialMount: equatorialMount,
    telrad: telrad,
    ccd: ccd,
    dsoLabels: dsoLabels,
    constellationArt3d: constellationArt3d,
    starMagLimit: starMagLimit
  }
}

function cloneSnapshot(source: LayerPresetSnapshot): LayerPresetSnapshot {
  const actions: Record<string, boolean> = {}
  for (const id of ALL_ACTION_IDS) actions[id] = source.actions[id] === true
  return {
    actions: actions,
    vividAtmosphere: source.vividAtmosphere,
    milkyWayBright: source.milkyWayBright,
    realisticStarVisibility: source.realisticStarVisibility,
    nightMode: source.nightMode,
    observeMode: source.observeMode,
    equatorialMount: source.equatorialMount,
    telrad: source.telrad,
    ccd: source.ccd,
    dsoLabels: source.dsoLabels,
    constellationArt3d: source.constellationArt3d,
    starMagLimit: source.starMagLimit
  }
}

function neutralSnapshot(): LayerPresetSnapshot {
  return buildSnapshot([], false, 3, true, false, false, false, false, false, true, false)
}

function factoryDefinitions(): Array<LayerPresetDefinition> {
  const clean = buildSnapshot(CLEAN_ACTIONS, false, 6, true, false, false, false, false, false, true, false)
  const observe = buildSnapshot(OBSERVE_ACTIONS, false, 3, true, true, true, true, true, false, true, false, MAX_STAR_MAG_LIMIT)
  const photo = buildSnapshot(PHOTO_ACTIONS, false, 3, true, false, false, false, false, true, false, false, MAX_STAR_MAG_LIMIT)
  const study = buildSnapshot(STUDY_ACTIONS, false, 4, true, false, false, false, false, false, true, false)
  const vivid = buildSnapshot(VIVID_ACTIONS, true, 6, false, false, false, false, false, false, true, true)
  return [
    { id: 'clean', kind: 'builtin', nameKey: 'preset_clean', customName: '', enabled: true, snapshot: clean, factory: cloneSnapshot(clean) },
    { id: 'observe', kind: 'builtin', nameKey: 'preset_observe', customName: '', enabled: true, snapshot: observe, factory: cloneSnapshot(observe) },
    { id: 'photo', kind: 'builtin', nameKey: 'preset_photo', customName: '', enabled: true, snapshot: photo, factory: cloneSnapshot(photo) },
    { id: 'study', kind: 'builtin', nameKey: 'preset_study', customName: '', enabled: true, snapshot: study, factory: cloneSnapshot(study) },
    { id: 'vivid', kind: 'builtin', nameKey: 'preset_vivid', customName: '', enabled: true, snapshot: vivid, factory: cloneSnapshot(vivid) }
  ]
}

function readBool(source: Record<string, Object>, key: string, fallback: boolean): boolean {
  const value = source[key]
  return value === undefined ? fallback : value === true
}

function readNumber(source: Record<string, Object>, key: string, fallback: number): number {
  const value = source[key]
  if (typeof value === 'number') return value
  if (typeof value === 'string') {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : fallback
  }
  return fallback
}

function readString(source: Record<string, Object>, key: string, fallback: string): string {
  const value = source[key]
  return typeof value === 'string' ? value : fallback
}

function readOptionalNumber(source: Record<string, Object>, key: string): number | undefined {
  const value = source[key]
  if (typeof value === 'number') return value
  if (typeof value === 'string') {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : undefined
  }
  return undefined
}

function normalizeSnapshot(raw: Object | undefined): LayerPresetSnapshot | undefined {
  if (raw === undefined) return undefined
  const source = raw as Record<string, Object>
  const rawActions = source['actions']
  if (rawActions === undefined) return undefined
  const actionMap = rawActions as Record<string, boolean>
  const actions = emptyActions()
  for (const id of ALL_ACTION_IDS) actions[id] = actionMap[id] === true
  return {
    actions: actions,
    vividAtmosphere: readBool(source, 'vividAtmosphere', false),
    milkyWayBright: Math.max(0, Math.min(6, Math.round(readNumber(source, 'milkyWayBright', 3)))),
    realisticStarVisibility: readBool(source, 'realisticStarVisibility', true),
    nightMode: readBool(source, 'nightMode', false),
    observeMode: readBool(source, 'observeMode', false),
    equatorialMount: readBool(source, 'equatorialMount', false),
    telrad: readBool(source, 'telrad', false),
    ccd: readBool(source, 'ccd', false),
    dsoLabels: readBool(source, 'dsoLabels', true),
    constellationArt3d: readBool(source, 'constellationArt3d', false),
    starMagLimit: readOptionalNumber(source, 'starMagLimit')
  }
}

function actionLabel(id: string): string {
  const zh = I18n.getLanguage().toLowerCase().startsWith('zh')
  const labels = new Map<string, string>()
  if (zh) {
    labels.set('actionShow_Stars', '恒星')
    labels.set('actionShow_Stars_Labels', '恒星标签')
    labels.set('actionShow_Planets', '行星')
    labels.set('actionShow_Planets_Labels', '行星标签')
    labels.set('actionShow_Planets_Orbits', '行星轨道')
    labels.set('actionShow_Planets_Hints', '行星提示')
    labels.set('actionShow_Planets_Trails', '行星轨迹')
    labels.set('actionShow_Planets_EnlargeMoon', '放大月球')
    labels.set('actionShow_Planets_EnlargePlanets', '放大行星')
    labels.set('actionShow_Planets_EnlargeSun', '放大太阳')
    labels.set('actionShow_Planets_ShowMinorBodyMarkers', '小天体标记')
    labels.set('actionShow_Planets_Nomenclature', '行星地貌名称')
    labels.set('actionShow_Nebulas', '深空天体')
    labels.set('actionShow_DSO_Textures', '深空纹理')
    labels.set('actionShow_MilkyWay', '银河')
    labels.set('actionShow_Fog', '雾效果')
    labels.set('actionShow_Ground', '地面')
    labels.set('actionShow_MistHorizon', '动态雾山')
    labels.set('actionShow_LandscapeIllumination', '地景照明')
    labels.set('actionShow_LandscapeLabels', '地景标签')
    labels.set('actionShow_Constellation_Lines', '星座连线')
    labels.set('actionShow_Constellation_Labels', '星座标签')
    labels.set('actionShow_Constellation_Boundaries', '星座边界')
    labels.set('actionShow_Constellation_Art', '星座艺术')
    labels.set('actionShow_Constellation_Hulls', '星座区域')
    labels.set('actionShow_Zodiac', '黄道')
    labels.set('actionShow_LunarSystem', '月宿')
    labels.set('actionShow_Asterism_Lines', '星群连线')
    labels.set('actionShow_Asterism_Labels', '星群标签')
    labels.set('actionShow_Atmosphere', '大气层')
    labels.set('actionShow_Cardinal_Points', '方位点')
    labels.set('actionShow_Azimuthal_Grid', '地平网格')
    labels.set('actionShow_Equatorial_Grid', '赤道坐标网格')
    labels.set('actionShow_Equatorial_J2000_Grid', 'J2000 赤道网格')
    labels.set('actionShow_Ecliptic_Grid', '黄道网格')
    labels.set('actionShow_Galactic_Grid', '银河网格')
    labels.set('actionShow_Ecliptic_Line', '黄道线')
    labels.set('actionShow_Equator_Line', '赤道线')
    labels.set('actionShow_Meridian_Line', '子午线')
    labels.set('actionShow_Horizon_Line', '地平线')
    labels.set('actionShow_Gridlines', '网格总闸')
    labels.set('actionShow_FOV_Center_Marker', '视场中心标记')
    labels.set('actionShow_FOV_Circular_Marker', '圆形视场标记')
    labels.set('actionShow_FOV_Rectangular_Marker', '矩形视场标记')
    labels.set('actionShow_Hips_Surveys', 'HiPS 巡天')
    labels.set('actionShow_Toast_Survey', 'TOAST 巡天')
    labels.set('actionShow_Ecliptic_J2000_Grid', 'J2000 黄道网格')
    labels.set('actionShow_Supergalactic_Grid', '超银河网格')
    labels.set('actionShow_Fixed_Equatorial_Grid', '固定赤道网格')
    labels.set('actionShow_Fixed_Equator_Line', '固定赤道线')
    labels.set('actionShow_Galactic_Equator_Line', '银道线')
    labels.set('actionShow_Supergalactic_Equator_Line', '超银道线')
    labels.set('actionShow_Equator_J2000_Line', 'J2000 赤道线')
    labels.set('actionShow_Ecliptic_J2000_Line', 'J2000 黄道线')
    labels.set('actionShow_Celestial_Poles', '天极')
    labels.set('actionShow_Ecliptic_Poles', '黄极')
    labels.set('actionShow_Galactic_Poles', '银极')
    labels.set('actionShow_Equinox_Points', '二分点')
    labels.set('actionShow_Solstice_Points', '二至点')
    labels.set('actionShow_Antisolar_Point', '反日点')
    labels.set('actionShow_Umbra_Circle', '本影圆')
    labels.set('actionShow_Penumbra_Circle', '半影圆')
    labels.set('actionShow_Compass_Marks', '罗盘刻度')
    labels.set('actionShow_Intercardinal_Points', '四隅点')
    labels.set('actionShow_Secondary_Intercardinal_Points', '次级四隅点')
    labels.set('actionShow_Tertiary_Intercardinal_Points', '三级四隅点')
    labels.set('actionShow_Prime_Vertical_Line', '卯酉圈')
    labels.set('actionShow_Current_Vertical_Line', '当前垂直圈')
    labels.set('actionShow_Colure_Lines', '二分二至圈')
    labels.set('actionShow_Precession_Circles', '岁差圈')
    labels.set('actionShow_Circumpolar_Circles', '拱极圈')
    labels.set('actionShow_Invariable_Plane_Line', '不变平面')
    labels.set('actionShow_Ray_Helpers', '光线辅助线')
    labels.set('actionShow_Solar_Equator_Line', '太阳赤道')
    labels.set('actionShow_Zenith_Nadir', '天顶天底')
    labels.set('actionShow_Celestial_J2000_Poles', 'J2000 天极')
    labels.set('actionShow_Ecliptic_J2000_Poles', 'J2000 黄极')
    labels.set('actionShow_Equinox_J2000_Points', 'J2000 二分点')
    labels.set('actionShow_Solstice_J2000_Points', 'J2000 二至点')
    labels.set('actionShow_Galactic_Center', '银心')
    labels.set('actionShow_Supergalactic_Poles', '超银极')
    labels.set('actionShow_Apex_Points', '奔赴点')
    labels.set('actionShow_Umbra_Center_Point', '本影中心')
    labels.set('actionShow_Longitude_Line', '黄经线')
    labels.set('actionShow_Quadrature_Line', '方照线')
  } else {
    labels.set('actionShow_Stars', 'Stars')
    labels.set('actionShow_Stars_Labels', 'Star labels')
    labels.set('actionShow_Planets', 'Planets')
    labels.set('actionShow_Planets_Labels', 'Planet labels')
    labels.set('actionShow_Planets_Orbits', 'Planet orbits')
    labels.set('actionShow_Planets_Hints', 'Planet hints')
    labels.set('actionShow_Nebulas', 'Deep-sky objects')
    labels.set('actionShow_DSO_Textures', 'DSO textures')
    labels.set('actionShow_MilkyWay', 'Milky Way')
    labels.set('actionShow_Fog', 'Fog')
    labels.set('actionShow_Ground', 'Ground')
    labels.set('actionShow_MistHorizon', 'Animated mist horizon')
    labels.set('actionShow_Atmosphere', 'Atmosphere')
    labels.set('actionShow_Constellation_Lines', 'Constellation lines')
    labels.set('actionShow_Constellation_Labels', 'Constellation labels')
    labels.set('actionShow_Constellation_Boundaries', 'Constellation boundaries')
    labels.set('actionShow_Constellation_Art', 'Constellation art')
    labels.set('actionShow_Asterism_Labels', 'Asterism labels')
    labels.set('actionShow_Cardinal_Points', 'Cardinal points')
    labels.set('actionShow_Equatorial_Grid', 'Equatorial grid')
    labels.set('actionShow_Equator_Line', 'Celestial equator')
    labels.set('actionShow_Ecliptic_Line', 'Ecliptic line')
    labels.set('actionShow_Meridian_Line', 'Meridian')
    labels.set('actionShow_Horizon_Line', 'Horizon')
    labels.set('actionShow_Gridlines', 'Grid master')
    labels.set('actionShow_FOV_Center_Marker', 'FOV centre marker')
    labels.set('actionShow_Planets_Trails', 'Planet trails')
    labels.set('actionShow_Planets_EnlargeMoon', 'Enlarged Moon')
    labels.set('actionShow_Planets_EnlargePlanets', 'Enlarged planets')
    labels.set('actionShow_Planets_EnlargeSun', 'Enlarged Sun')
    labels.set('actionShow_Planets_ShowMinorBodyMarkers', 'Minor-body markers')
    labels.set('actionShow_Planets_Nomenclature', 'Planet nomenclature')
    labels.set('actionShow_LandscapeIllumination', 'Landscape illumination')
    labels.set('actionShow_LandscapeLabels', 'Landscape labels')
    labels.set('actionShow_Constellation_Hulls', 'Constellation hulls')
    labels.set('actionShow_Zodiac', 'Zodiac')
    labels.set('actionShow_LunarSystem', 'Lunar mansions')
    labels.set('actionShow_Asterism_Lines', 'Asterism lines')
    labels.set('actionShow_Hips_Surveys', 'HiPS surveys')
    labels.set('actionShow_Toast_Survey', 'TOAST survey')
    labels.set('actionShow_Azimuthal_Grid', 'Azimuthal grid')
    labels.set('actionShow_Equatorial_J2000_Grid', 'Equatorial J2000 grid')
    labels.set('actionShow_Ecliptic_Grid', 'Ecliptic grid')
    labels.set('actionShow_Ecliptic_J2000_Grid', 'Ecliptic J2000 grid')
    labels.set('actionShow_Galactic_Grid', 'Galactic grid')
    labels.set('actionShow_Supergalactic_Grid', 'Supergalactic grid')
    labels.set('actionShow_Fixed_Equatorial_Grid', 'Fixed equatorial grid')
    labels.set('actionShow_Fixed_Equator_Line', 'Fixed equator line')
    labels.set('actionShow_Galactic_Equator_Line', 'Galactic equator')
    labels.set('actionShow_Supergalactic_Equator_Line', 'Supergalactic equator')
    labels.set('actionShow_Equator_J2000_Line', 'Equator J2000')
    labels.set('actionShow_Ecliptic_J2000_Line', 'Ecliptic J2000')
    labels.set('actionShow_Celestial_Poles', 'Celestial poles')
    labels.set('actionShow_Ecliptic_Poles', 'Ecliptic poles')
    labels.set('actionShow_Galactic_Poles', 'Galactic poles')
    labels.set('actionShow_Equinox_Points', 'Equinox points')
    labels.set('actionShow_Solstice_Points', 'Solstice points')
    labels.set('actionShow_Antisolar_Point', 'Antisolar point')
    labels.set('actionShow_Umbra_Circle', 'Umbra circle')
    labels.set('actionShow_Penumbra_Circle', 'Penumbra circle')
    labels.set('actionShow_Compass_Marks', 'Compass marks')
    labels.set('actionShow_Intercardinal_Points', 'Intercardinal points')
    labels.set('actionShow_Secondary_Intercardinal_Points', 'Secondary intercardinal points')
    labels.set('actionShow_Tertiary_Intercardinal_Points', 'Tertiary intercardinal points')
    labels.set('actionShow_Prime_Vertical_Line', 'Prime vertical')
    labels.set('actionShow_Current_Vertical_Line', 'Current vertical')
    labels.set('actionShow_Colure_Lines', 'Colure lines')
    labels.set('actionShow_Precession_Circles', 'Precession circles')
    labels.set('actionShow_Circumpolar_Circles', 'Circumpolar circles')
    labels.set('actionShow_Invariable_Plane_Line', 'Invariable plane')
    labels.set('actionShow_Ray_Helpers', 'Ray helpers')
    labels.set('actionShow_Solar_Equator_Line', 'Solar equator')
    labels.set('actionShow_Zenith_Nadir', 'Zenith/nadir')
    labels.set('actionShow_Celestial_J2000_Poles', 'Celestial poles J2000')
    labels.set('actionShow_Ecliptic_J2000_Poles', 'Ecliptic poles J2000')
    labels.set('actionShow_Equinox_J2000_Points', 'Equinox points J2000')
    labels.set('actionShow_Solstice_J2000_Points', 'Solstice points J2000')
    labels.set('actionShow_Galactic_Center', 'Galactic centre')
    labels.set('actionShow_Supergalactic_Poles', 'Supergalactic poles')
    labels.set('actionShow_Apex_Points', 'Apex points')
    labels.set('actionShow_Umbra_Center_Point', 'Umbra centre')
    labels.set('actionShow_Longitude_Line', 'Longitude line')
    labels.set('actionShow_Quadrature_Line', 'Quadrature line')
    labels.set('actionShow_FOV_Circular_Marker', 'Circular FOV marker')
    labels.set('actionShow_FOV_Rectangular_Marker', 'Rectangular FOV marker')
  }
  const mapped = labels.get(id)
  if (mapped !== undefined) return mapped
  return id.replace('actionShow_', '').replace(/_/g, ' ')
}

function boolText(value: boolean): string {
  const zh = I18n.getLanguage().toLowerCase().startsWith('zh')
  return value ? (zh ? '开' : 'On') : (zh ? '关' : 'Off')
}

function crossLabel(key: string): string {
  const zh = I18n.getLanguage().toLowerCase().startsWith('zh')
  const labels = new Map<string, string>()
  if (zh) {
    labels.set('vividAtmosphere', '绚丽大气')
    labels.set('milkyWayBright', '银河亮度')
    labels.set('realisticStarVisibility', '现实星等')
    labels.set('nightMode', '夜间模式')
    labels.set('observeMode', '详情观测模式')
    labels.set('equatorialMount', '赤道仪模式')
    labels.set('telrad', '寻星镜')
    labels.set('ccd', 'CCD 取景框')
    labels.set('dsoLabels', '深空标签')
    labels.set('constellationArt3d', '3D 星座')
    labels.set('starMagLimit', '星等限制')
  } else {
    labels.set('vividAtmosphere', 'Vivid atmosphere')
    labels.set('milkyWayBright', 'Milky Way brightness')
    labels.set('realisticStarVisibility', 'Realistic star visibility')
    labels.set('nightMode', 'Night mode')
    labels.set('observeMode', 'Object-detail observe mode')
    labels.set('equatorialMount', 'Equatorial mount')
    labels.set('telrad', 'Finder scope')
    labels.set('ccd', 'CCD frame')
    labels.set('dsoLabels', 'DSO labels')
    labels.set('constellationArt3d', '3D constellations')
    labels.set('starMagLimit', 'Star magnitude limit')
  }
  return labels.get(key) ?? key
}

function diffSnapshots(before: LayerPresetSnapshot, after: LayerPresetSnapshot): Array<LayerPresetDiffItem> {
  const items: Array<LayerPresetDiffItem> = []
  for (const id of ALL_ACTION_IDS) {
    const oldValue = before.actions[id] === true
    const newValue = after.actions[id] === true
    if (oldValue !== newValue) {
      items.push({ label: actionLabel(id), before: boolText(oldValue), after: boolText(newValue) })
    }
  }
  if (before.vividAtmosphere !== after.vividAtmosphere) {
    items.push({ label: crossLabel('vividAtmosphere'), before: boolText(before.vividAtmosphere), after: boolText(after.vividAtmosphere) })
  }
  if (before.milkyWayBright !== after.milkyWayBright) {
    items.push({ label: crossLabel('milkyWayBright'), before: before.milkyWayBright.toString(), after: after.milkyWayBright.toString() })
  }
  if (before.realisticStarVisibility !== after.realisticStarVisibility) {
    items.push({ label: crossLabel('realisticStarVisibility'), before: boolText(before.realisticStarVisibility), after: boolText(after.realisticStarVisibility) })
  }
  if (before.nightMode !== after.nightMode) {
    items.push({ label: crossLabel('nightMode'), before: boolText(before.nightMode), after: boolText(after.nightMode) })
  }
  if (before.observeMode !== after.observeMode) {
    items.push({ label: crossLabel('observeMode'), before: boolText(before.observeMode), after: boolText(after.observeMode) })
  }
  if (before.equatorialMount !== after.equatorialMount) {
    items.push({ label: crossLabel('equatorialMount'), before: boolText(before.equatorialMount), after: boolText(after.equatorialMount) })
  }
  if (before.telrad !== after.telrad) {
    items.push({ label: crossLabel('telrad'), before: boolText(before.telrad), after: boolText(after.telrad) })
  }
  if (before.ccd !== after.ccd) {
    items.push({ label: crossLabel('ccd'), before: boolText(before.ccd), after: boolText(after.ccd) })
  }
  if (before.dsoLabels !== after.dsoLabels) {
    items.push({ label: crossLabel('dsoLabels'), before: boolText(before.dsoLabels), after: boolText(after.dsoLabels) })
  }
  if (before.constellationArt3d !== after.constellationArt3d) {
    items.push({ label: crossLabel('constellationArt3d'), before: boolText(before.constellationArt3d), after: boolText(after.constellationArt3d) })
  }
  // undefined 表示“应用时不改变”，只有预设明确带值时才算差异。
  if (after.starMagLimit !== undefined &&
    (before.starMagLimit === undefined || before.starMagLimit !== after.starMagLimit)) {
    items.push({
      label: crossLabel('starMagLimit'),
      before: before.starMagLimit === undefined ? '—' : before.starMagLimit.toFixed(1),
      after: after.starMagLimit.toFixed(1)
    })
  }
  return items
}

function snapshotsEqual(left: LayerPresetSnapshot, right: LayerPresetSnapshot): boolean {
  return diffSnapshots(left, right).length === 0
}

@Observed
export class LayerPresetStore {
  presets: Array<LayerPresetDefinition> = []
  selectedId: string = ''
  selectedDirty: boolean = false
  detailsId: string = ''
  detailsItems: Array<LayerPresetDiffItem> = []
  detailsVersion: number = 0
  detailsLoading: boolean = false
  busy: boolean = false
  loaded: boolean = false

  private applying: boolean = false
  private hooks: LayerPresetHostHooks | null = null
  private detailsRequestSerial: number = 0

  attachHooks(hooks: LayerPresetHostHooks): void {
    this.hooks = hooks
    if (this.presets.length === 0) this.presets = factoryDefinitions()
  }

  load(): void {
    const hooks = this.hooks
    if (hooks === null || this.loaded) return
    hooks.loadPresetJson((json: string) => { this.applyPersisted(json) })
    this.loaded = true
  }

  enabledPresets(): Array<LayerPresetDefinition> {
    return this.presets.filter((preset: LayerPresetDefinition) => preset.enabled)
  }

  selectedPreset(): LayerPresetDefinition | undefined {
    return this.presets.find((preset: LayerPresetDefinition) => preset.id === this.selectedId)
  }

  displayName(preset: LayerPresetDefinition): string {
    if (preset.kind === 'custom' && preset.customName.length > 0) return preset.customName
    return I18n.t(preset.nameKey)
  }

  isModified(preset: LayerPresetDefinition): boolean {
    if (preset.factory === undefined) return false
    return !snapshotsEqual(preset.snapshot, preset.factory)
  }

  isMarked(preset: LayerPresetDefinition): boolean {
    return this.isModified(preset) || (preset.id === this.selectedId && this.selectedDirty)
  }

  labelWithMarker(preset: LayerPresetDefinition): string {
    return this.displayName(preset) + (this.isMarked(preset) ? ' *' : '')
  }

  selectOnly(id: string): void {
    const preset = this.presets.find((item: LayerPresetDefinition) => item.id === id)
    if (preset === undefined || !preset.enabled) return
    this.selectedId = id
    this.selectedDirty = false
    this.detailsId = ''
    this.setDetails([])
    this.persist()
  }

  applyPreset(id: string): void {
    const preset = this.presets.find((item: LayerPresetDefinition) => item.id === id)
    const hooks = this.hooks
    if (preset === undefined || !preset.enabled || hooks === null || this.busy) return
    this.selectedId = id
    this.selectedDirty = false
    this.busy = true
    this.applying = true
    hooks.applySnapshot(cloneSnapshot(preset.snapshot), (): void => {
      this.applying = false
      this.busy = false
      this.selectedDirty = false
      this.persist()
      if (this.detailsId === id) this.refreshDetails()
      hooks.refreshState()
      hooks.flashHint(I18n.t('preset_applied'))
    })
  }

  // 手动修改图层后预设仍保持选中（这是预设的固定语义，不再提供独立开关），
  // 只把当前预设标记为“已修改”，名称末尾显示 *。
  noteManualChange(): void {
    if (this.applying || this.busy || this.selectedId.length === 0) return
    if (!this.selectedDirty) {
      this.selectedDirty = true
      this.persist()
      // 详情已打开时立即刷新为“当前场景与预设的差异”，避免星号出现但列表仍为空。
      if (this.detailsId === this.selectedId) this.refreshDetails()
    }
  }

  // 仅自定义预设允许改名；空白名称回退为本地化的“自定义预设”。
  renameCustom(id: string, name: string): void {
    const preset = this.presets.find((item: LayerPresetDefinition) => item.id === id)
    if (preset === undefined || preset.kind !== 'custom') return
    const trimmed = name.trim()
    const nextName = trimmed.length > 0 ? trimmed : I18n.t('preset_custom')
    if (nextName === preset.customName) return
    this.presets = this.presets.map((item: LayerPresetDefinition): LayerPresetDefinition => {
      if (item.id !== id) return item
      return {
        id: item.id, kind: item.kind, nameKey: item.nameKey, customName: nextName,
        enabled: item.enabled, snapshot: item.snapshot, factory: item.factory
      }
    })
    this.persist()
  }

  saveCurrentToSelected(): void {
    const preset = this.selectedPreset()
    const hooks = this.hooks
    if (preset === undefined || hooks === null || this.busy) {
      if (hooks !== null) hooks.flashHint(I18n.t('msg_apply_failed'))
      return
    }
    this.busy = true
    hooks.captureSnapshot((snapshot: LayerPresetSnapshot): void => {
      const next = cloneSnapshot(snapshot)
      this.presets = this.presets.map((item: LayerPresetDefinition): LayerPresetDefinition =>
        item.id === preset.id ? this.withSnapshot(item, next) : item)
      this.busy = false
      this.selectedDirty = false
      this.persist()
      this.refreshDetails()
      hooks.flashHint(I18n.t('preset_saved_current'))
    })
  }

  saveSelectedAsCustom(): void {
    const source = this.selectedPreset()
    const hooks = this.hooks
    if (source === undefined || hooks === null) return
    const customCount = this.presets.filter((preset: LayerPresetDefinition) => preset.kind === 'custom').length
    if (customCount >= LAYER_PRESET_CUSTOM_LIMIT) {
      hooks.flashHint(I18n.t('preset_custom_limit'))
      return
    }
    const id = 'custom-' + Date.now().toString()
    const customName = I18n.t('preset_custom') + ' ' + (customCount + 1).toString()
    const custom: LayerPresetDefinition = {
      id: id,
      kind: 'custom',
      nameKey: 'preset_custom',
      customName: customName,
      enabled: true,
      snapshot: cloneSnapshot(source.snapshot)
    }
    this.presets = this.presets.concat([custom])
    this.selectedId = id
    this.selectedDirty = false
    this.persist()
    hooks.flashHint(I18n.t('preset_saved_custom'))
  }

  movePreset(id: string, delta: number): void {
    const index = this.presets.findIndex((preset: LayerPresetDefinition) => preset.id === id)
    this.movePresetTo(index, index + delta)
  }

  // 拖拽排序落位：按索引移动，保证数据源顺序与拖拽结果一致。
  movePresetTo(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 || from >= this.presets.length || to >= this.presets.length) return
    const next = this.presets.slice()
    const moved = next.splice(from, 1)[0]
    next.splice(to, 0, moved)
    this.presets = next
    this.persist()
  }

  setEnabled(id: string, enabled: boolean): void {
    this.presets = this.presets.map((preset: LayerPresetDefinition): LayerPresetDefinition => {
      if (preset.id !== id) return preset
      return {
        id: preset.id, kind: preset.kind, nameKey: preset.nameKey, customName: preset.customName,
        enabled: enabled, snapshot: preset.snapshot, factory: preset.factory
      }
    })
    if (!enabled && this.selectedId === id) {
      this.selectedId = ''
      this.selectedDirty = false
      this.detailsId = ''
      this.setDetails([])
    }
    this.persist()
  }

  deleteCustom(id: string): void {
    const preset = this.presets.find((item: LayerPresetDefinition) => item.id === id)
    if (preset === undefined || preset.kind !== 'custom') return
    this.presets = this.presets.filter((item: LayerPresetDefinition) => item.id !== id)
    if (this.selectedId === id) {
      this.selectedId = ''
      this.selectedDirty = false
      this.detailsId = ''
      this.setDetails([])
    } else if (this.detailsId === id) {
      this.detailsId = ''
      this.setDetails([])
    }
    this.persist()
  }

  canRestoreSelected(): boolean {
    const preset = this.selectedPreset()
    return preset !== undefined && preset.factory !== undefined && this.isModified(preset)
  }

  restoreSelected(): void {
    if (this.selectedId.length > 0) this.restorePreset(this.selectedId)
  }

  // 每行都可还原自己的初始状态，不要求先选中该预设。
  restorePreset(id: string): void {
    const preset = this.presets.find((item: LayerPresetDefinition) => item.id === id)
    const hooks = this.hooks
    if (preset === undefined || preset.factory === undefined || hooks === null || this.busy) return
    const restored = cloneSnapshot(preset.factory)
    this.presets = this.presets.map((item: LayerPresetDefinition): LayerPresetDefinition =>
      item.id === preset.id ? this.withSnapshot(item, restored) : item)
    if (this.selectedId !== preset.id) {
      // 还原未被选中的预设只更新其定义，不改变当前星空画面。
      this.persist()
      this.refreshDetails()
      hooks.flashHint(I18n.t('preset_restored'))
      return
    }
    this.selectedDirty = false
    this.busy = true
    this.applying = true
    hooks.applySnapshot(cloneSnapshot(restored), (): void => {
      this.applying = false
      this.busy = false
      this.persist()
      this.refreshDetails()
      hooks.refreshState()
      hooks.flashHint(I18n.t('preset_restored'))
    })
  }

  showDetails(id: string): void {
    if (this.detailsId === id) {
      this.clearDetails()
      return
    }
    const preset = this.presets.find((item: LayerPresetDefinition) => item.id === id)
    if (preset === undefined) return
    this.detailsId = id
    this.setDetails([])
    this.loadDetails(preset)
  }

  // 星号可能来自两种修改：
  //   1) 预设定义本身被“保存当前设置”改过 → 对比出厂快照；
  //   2) 当前场景被手动改过但尚未保存（selectedDirty）→ 对比当前场景。
  // 第 2 种必须捕获实时快照，否则会出现“有星号但修改项为空”。
  private loadDetails(preset: LayerPresetDefinition): void {
    const serial = ++this.detailsRequestSerial
    if (preset.id === this.selectedId && this.selectedDirty && this.hooks !== null) {
      this.detailsLoading = true
      this.hooks.captureSnapshot((current: LayerPresetSnapshot): void => {
        if (serial !== this.detailsRequestSerial || this.detailsId !== preset.id) return
        this.detailsLoading = false
        const items = diffSnapshots(preset.snapshot, current)
        // 手动改回与预设完全一致时，星号也应消失。
        if (items.length === 0 && this.selectedDirty) {
          this.selectedDirty = false
          this.persist()
        }
        this.setDetails(items)
      })
      return
    }
    this.detailsLoading = false
    const baseline = preset.factory !== undefined ? preset.factory : neutralSnapshot()
    this.setDetails(diffSnapshots(baseline, preset.snapshot))
  }

  clearDetails(): void {
    this.detailsRequestSerial++
    this.detailsId = ''
    this.detailsLoading = false
    this.setDetails([])
  }

  private setDetails(items: Array<LayerPresetDiffItem>): void {
    this.detailsItems = items
    this.detailsVersion++
  }

  private withSnapshot(preset: LayerPresetDefinition, snapshot: LayerPresetSnapshot): LayerPresetDefinition {
    return {
      id: preset.id, kind: preset.kind, nameKey: preset.nameKey, customName: preset.customName,
      enabled: preset.enabled, snapshot: snapshot, factory: preset.factory
    }
  }

  private refreshDetails(): void {
    if (this.detailsId.length === 0) return
    const preset = this.presets.find((item: LayerPresetDefinition) => item.id === this.detailsId)
    if (preset === undefined) {
      this.clearDetails()
      return
    }
    this.loadDetails(preset)
  }

  private persist(): void {
    const hooks = this.hooks
    if (hooks === null) return
    const savedPresets: Array<PersistedLayerPreset> = this.presets.map(
      (preset: LayerPresetDefinition): PersistedLayerPreset => {
        const item: PersistedLayerPreset = {
          id: preset.id, kind: preset.kind, nameKey: preset.nameKey, customName: preset.customName,
          enabled: preset.enabled, snapshot: preset.snapshot
        }
        return item
      })
    const document: PersistedLayerPresetDocument = {
      version: 1,
      selectedId: this.selectedId,
      selectedDirty: this.selectedDirty,
      presets: savedPresets
    }
    hooks.persistPresetJson(JSON.stringify(document))
  }

  private applyPersisted(json: string): void {
    if (json.length === 0) {
      this.presets = factoryDefinitions()
      return
    }
    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const rawPresets = parsed['presets'] as Object[] | undefined
      if (rawPresets === undefined) {
        this.presets = factoryDefinitions()
        return
      }
      const builtins = factoryDefinitions()
      const byId = new Map<string, LayerPresetDefinition>()
      for (const builtin of builtins) byId.set(builtin.id, builtin)
      const order: Array<string> = []
      const customs: Array<LayerPresetDefinition> = []
      for (const raw of rawPresets) {
        const item = raw as Record<string, Object>
        const id = readString(item, 'id', '')
        if (id.length === 0) continue
        const snapshot = normalizeSnapshot(item['snapshot'])
        if (snapshot === undefined) continue
        const enabled = readBool(item, 'enabled', true)
        const builtin = byId.get(id)
        if (builtin !== undefined) {
          builtin.enabled = enabled
          builtin.snapshot = snapshot
          order.push(id)
        } else if (id.startsWith('custom-')) {
          customs.push({
            id: id,
            kind: 'custom',
            nameKey: 'preset_custom',
            customName: readString(item, 'customName', I18n.t('preset_custom')),
            enabled: enabled,
            snapshot: snapshot
          })
          order.push(id)
          if (customs.length >= LAYER_PRESET_CUSTOM_LIMIT) break
        }
      }
      const merged: Array<LayerPresetDefinition> = []
      for (const id of order) {
        const builtin = byId.get(id)
        if (builtin !== undefined) {
          merged.push(builtin)
        } else {
          const custom = customs.find((preset: LayerPresetDefinition) => preset.id === id)
          if (custom !== undefined) merged.push(custom)
        }
      }
      for (const builtin of builtins) {
        if (merged.find((preset: LayerPresetDefinition) => preset.id === builtin.id) === undefined) {
          merged.push(builtin)
        }
      }
      this.presets = merged
      const selectedId = readString(parsed, 'selectedId', '')
      const selected = this.presets.find((preset: LayerPresetDefinition) => preset.id === selectedId && preset.enabled)
      this.selectedId = selected !== undefined ? selected.id : ''
      this.selectedDirty = selected !== undefined && readBool(parsed, 'selectedDirty', false)
      this.detailsId = ''
      this.setDetails([])
    } catch (error) {
      this.presets = factoryDefinitions()
    }
  }
}
