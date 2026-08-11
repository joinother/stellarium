import { command } from 'libentry.so'
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { geoLocationManager } from '@kit.LocationKit'
import { sensor } from '@kit.SensorServiceKit'
import { curves } from '@kit.ArkUI'
import { privacyManager } from '@kit.AppGalleryKit'
import hilog from '@ohos.hilog'
import display from '@ohos.display'
import preferences from '@ohos.data.preferences'
import { LOCATION_HIERARCHY } from './location_hierarchy'
import { LOCATION_ZH_NAMES } from './location_names_zh'

import { ALIAS_LIST, StellariumBridgeResponse, SessionSnapshot, TonightEvents, TonightPlanet, TonightShower, WutTarget, EphemerisRow, RtsCalendarDay, AltAzPoint, AnnualElevationPoint, ObservabilityDay, LunarElongationPoint, PlanetTimeSeriesPoint, PlanetPairDistancePoint, PlanetCalcItem, PhenomenonItem, EclipseItem, PlanetaryTransitItem, MoonPhaseItem, SeasonEvent, LangOption, HierCity, CatOption, NameItem, AliasEntry, SearchSug, AliasHit, WindowNativeNodeCreateInfo, TabItem, ChipItem, LandscapeItem, PlanetPosition, HeliocentricPosition, CelestialPosition, ObjectInfo, SkyCultureItem, PluginItem, ShellAction, LocSearchItem, SavedLocation } from './StellariumTypes'
import { setLifecycleListener } from '../common/StellariumLifecycle'
import { AudioEngine } from './StellariumAudio'
import { I18n, LANGUAGE_DISPLAY, SUPPORTED_LANGUAGES, BRIGHT_STARS, PROJECTION_KEYS } from './I18n'

interface CityPreset {
  lat: number
  lon: number
  alt: number
}

interface HeliocentricPositionOptions {
  includeSelectedMinor: boolean
  includeBrightComets: boolean
  cometMagnitudeLimit: number
}

interface CelestialPositionOptions {
  category: string
  horizontal: boolean
  magnitudeLimit: number
  maximumRows: number
}

interface CelestialPositionCategory {
  id: string
  label: string
}

interface PhenomenaOptions {
  bodyA: string
  bodyB: string
  days: number
  startOffsetMonths: number
  maxSeparation: number
  includeOppositions: boolean
  includePerihelionAphelion: boolean
  includeElongationsQuadratures: boolean
  includeStations: boolean
}

interface PhenomenaStartOption {
  label: string
  value: number
}

interface EphemerisOptions {
  days: number
  stepHours: number
  jd?: number
  names?: string[]
  allNakedEye?: boolean
}

interface RtsCalendarOptions {
  days: number
  jd?: number
}

interface EclipseOptions {
  months: number
  jd?: number
}

const CELESTIAL_POSITION_CATEGORIES: CelestialPositionCategory[] = [
  { id: 'planets', label: '行星' },
  { id: 'stars', label: '亮星' },
  { id: 'deepSky', label: '深空' },
  { id: 'galaxies', label: '星系' },
  { id: 'nebulae', label: '星云' },
  { id: 'clusters', label: '星团' },
  { id: 'comets', label: '彗星' },
  { id: 'minorBodies', label: '小行星' },
]

const PHENOMENA_START_OPTIONS: PhenomenaStartOption[] = [
  { label: '现在', value: 0 },
  { label: '3 个月后', value: 3 },
  { label: '6 个月后', value: 6 },
  { label: '1 年后', value: 12 },
]

// 时间轴刻度：value=偏移天数（-365~+365），major=主刻度
interface TimeTick {
  label: string
  value: number
  major: boolean
}

interface TonightPlanetRow {
  name: string
  line: string
  jd: number
  lock: string
}

// 启动动画里的星点（百分比坐标 + 半径vp + 是否亮星，用于交错闪烁）
interface StarDot {
  xPct: number
  yPct: number
  r: number
  bright: boolean
}

// 星表下载（C++ 桥 getStarCatalogs / downloadStarCatalog / getStarCatalogStatus）
interface StarCatalogItem {
  id: string
  name: string
  size: string
  key: string
  fileName: string
  url: string
  html: string
  checked: boolean
}
interface StarCatalogRaw {
  id?: string
  name?: string
  size?: string
  key?: string
  fileName?: string
  url?: string
  html?: string
  checked?: boolean | string | number
}
interface StarCatalogsResponse extends StellariumBridgeResponse {
  catalogs?: StarCatalogRaw[]
}
interface StarCatalogStatusResponse extends StellariumBridgeResponse {
  id?: string
  state?: string
  bytes?: number
  error?: string
  md5ok?: boolean
}
interface LimitMagnitudeResponse extends StellariumBridgeResponse {
  limitMagnitude?: number
  customStarMagLimit?: number
  starMagnitudeLimitEnabled?: boolean
}
interface GyroGuideProjection extends StellariumBridgeResponse {
  valid?: boolean
  visible?: boolean
  xRatio?: number
  yRatio?: number
}
interface SkyUiObstacle {
  label: string
  left: number
  top: number
  right: number
  bottom: number
}

// 书签（C++ 桥 addBookmark / getBookmarks / deleteBookmark / gotoBookmark）
interface BookmarkItem {
  id: string
  name: string
  fov: number
  object: string
}
interface BookmarkRaw {
  id?: string
  name?: string
  fov?: number
  object?: string
}
interface BookmarksResponse extends StellariumBridgeResponse {
  items?: BookmarkRaw[]
  count?: number
}

const BOOKMARK_STORE: string = 'stellarium_bookmarks'
const SEARCH_HISTORY_STORE: string = 'stellarium_search_history'
const OFFLINE_APPGALLERY_BUILD: boolean = true


// 望远镜/目镜配置（Oculars 插件桥）
interface OcularsData {
  ocularMode: boolean
  telrad: boolean
  crosshairs: boolean
  ccd: boolean
  ocularIndex: number
  telescopeIndex: number
  lensIndex: number
  ccdIndex: number
  ocularNames: string[]
  telescopeNames: string[]
  lensNames: string[]
  ccdNames: string[]
}
interface OcularsResponse extends StellariumBridgeResponse {
  oculars?: OcularsData
}

// 卫星（Satellites 插件桥）
interface SatellitesData {
  groups: string[]
  labels: boolean
  orbitLines: boolean
  hints: boolean
  iconicMode: boolean
  hideInvisible: boolean
  count: number
}
interface SatellitesResponse extends StellariumBridgeResponse {
  satellites?: SatellitesData
}

// 流星雨（MeteorShowers 插件桥）
interface MeteorShowersData {
  enabled: boolean
  labels: boolean
  activeOnly: boolean
  marker: boolean
}
interface MeteorShowerItem {
  name: string
  englishName: string
  zhr: number
  status: string
  speed: number
  popIdx: number
  parent: string
  peakDate: string
  activeStart: string
  activeEnd: string
}
interface MeteorShowersResponse extends StellariumBridgeResponse {
  meteorShowers?: MeteorShowersData
  showerList?: MeteorShowerItem[]
}
interface LogResponse extends StellariumBridgeResponse {
  log?: string
  totalChars?: number
  logFile?: string
}
interface AboutResponse extends StellariumBridgeResponse {
  version?: string
  qtVersion?: string
  userDir?: string
  configFile?: string
  logFile?: string
}
interface ExportConfigResponse extends StellariumBridgeResponse {
  content?: string
  configFile?: string
}
interface ImportConfigResponse extends StellariumBridgeResponse {
  applied?: number
}
interface SpokenTextResponse extends StellariumBridgeResponse {
  text?: string
}
interface RecordCmd {
  c: string
  p: string
}
interface RecordingEntry {
  file: string
  name: string
  created: string
  count: number
}
interface RecordingsResponse extends StellariumBridgeResponse {
  items?: Array<RecordingEntry>
}
interface RecordingDetailResponse extends StellariumBridgeResponse {
  name?: string
  commands?: Array<RecordCmd>
}

// 望远镜配置选择器的展示数据（非响应式，@Builder 内实时读取 @State）
class OcularSelInfo {
  name: string = ''
  countText: string = ''
}

@Entry
@Component
struct WindowNativeNode {
  @State private createInfo: WindowNativeNodeCreateInfo | undefined = undefined
  @Watch('onPrivacyNativeStartupAllowedChanged')
  @StorageLink('stellariumPrivacyNativeStartupAllowed')
  private privacyNativeStartupAllowed: boolean = false
  private privacyPageStartupStarted: boolean = false
  @State private isExpandedLayout: boolean = false
  @State private isFoldHoverLayout: boolean = false
  @State private isFoldableDevice: boolean = false
  @State private isFoldTabletLayout: boolean = false
  @State private foldStatusValue: number = 0
  @State private foldDisplayModeValue: number = 0
  @State private foldAngleValue: number = 180
  // Some emulator and device transitions report a fold status before the first
  // usable angle sample. Keep that stale 180-degree startup value from forcing
  // a half-folded device back into the tablet shell.
  @State private hasUsableFoldAngle: boolean = false
  @State private responsiveLayoutMode: string = 'compact'
  @State private activePanel: string = 'object'
  @State private panelVisible: boolean = false
  @State private searchText: string = ''
  @State private selectedName: string = ''
  @State private searchSuggestions: SearchSug[] = []
  @State private searchHistory: string[] = []
  @State private searchCategory: string = 'planet'
  @State private categoryObjects: NameItem[] = []
  @State private categoryObjectCount: number = 0
  @State private categoryLoadedCount: number = 0
  @State private categoryLoading: boolean = false
  @State private categoryLoadFailed: boolean = false
  @State private categoryHasMore: boolean = false
  @State private categoryModuleId: string = 'SolarSystem:planet'
  @State private selectedType: string = ''
  @State private selectedStatus: string = ''
  @State private selectedInfo: string = ''
  @State private selectedMagnitude: string = ''
  @State private selectedApparentMagnitude: string = ''
  @State private selectedAirmass: string = ''
  @State private selectedExtinction: string = ''
  @State private selectedFullInfo: string = ''
  @State private selectedCoordEq: string = ''
  @State private selectedCoordAlt: string = ''
  @State private selectedConstellation: string = ''
  @State private selectedDistance: string = ''
  // 陀螺仪观测时，若已选目标落在视场外，在安全边缘给出方向提示。
  // 坐标本身不参与渲染，只有这三个 @State 会驱动提示箭头刷新。
  @State private gyroGuideVisible: boolean = false
  @State private gyroGuideAngle: number = 0
  @State private gyroGuideX: number = 0
  @State private gyroGuideY: number = 0
  // The compact phone quick controls are tapped through a transparent layer
  // above Qt, so keep their pressed appearance in explicit ArkUI state.
  @State private compactQuickPressed: string = ''
  @State private visibleConstellations: string = ''
  // 富化的天体详情（独立浮动窗口，不切换当前菜单；默认收起，可展开）
  @State private infoWinVisible: boolean = false
  @State private infoWinExpanded: boolean = false
  @State private bottomCardIndex: number = 0
  @State private compactPanelSnapRatio: number = 0.6
  @State private compactPanelDragOffsetY: number = 0
  private lastInfoWinCloseMs: number = 0
  private dismissedObjectName: string = ''
  @State private infoTextExpanded: boolean = false
  @State private panelContentKey: number = 0
  @State private cardOffsetX: number = 0
  @State private cardOffsetY: number = 0
  @State private centerSearchText: string = ''
  @State private selectedSize: string = ''
  @State private selectedRise: string = ''
  @State private selectedSet: string = ''
  @State private selectedTransit: string = ''
  @State private selectedPhase: string = ''
  @State private selectedElongation: string = ''
  @State private selectedRich: string = ''
  @State private audioVolume: number = 0.7
  @State private sessionExportText: string = ''
  @State private sessionImportText: string = ''
  @State private sessionImportMsg: string = ''
  // 程序化音乐：默认开（打开应用即播放），可静音并持久化
  @State private musicEnabled: boolean = false
  @State private fpsDisplay: number = 0
  @State private fpsVisible: boolean = false
  private fpsFrameCount: number = 0
  private fpsLastTime: number = 0
  private fpsTimer: number = 0
  private lastMusicToggle: number = 0
  @State private timeRateText: string = '1x'
  /** Current speed-step index into TIME_SPEED_STEPS. */
  @State private timeSpeedIndex: number = 7  // 7=1x realtime (default, new index)
  // 原生命令在下一渲染帧才生效。此窗口内忽略轮询到的旧速率，避免按钮
  // 刚显示“-2x”又被上一帧的“-10x”短暂盖回去而产生闪烁。
  private pendingTimeRate: number = Number.NaN
  private pendingTimeRateUntilMs: number = 0
  /** 时间轴相对真实当前时刻的偏移秒数（0=此刻，负=过去，正=未来）*/
  @State private scrubberValue: number = 0
  @State private scrubberLabel: string = '此刻'
  // 时间轴的中心 JD。它不是系统时间的固定快照：模拟时间接近边界时会
  // 重新定锚到当前模拟时间，避免快进后游标永远卡在两端。
  private scrubberReferenceJd: number = 0
  private scrubberPendingOffset: number = 0
  private scrubberAnchorPending: boolean = false
  private scrubberLastSendMs: number = 0
  private scrubberInteracting: boolean = false
  // 时间转轴：顶部选择要调整的字段，底部同一条刻度轴只控制该字段。
  @State private timeWheelUnit: string = 'hour'
  @State private timeWheelYear: number = 2026
  @State private timeWheelMonth: number = 8
  @State private timeWheelDay: number = 11
  @State private timeWheelHour: number = 20
  @State private timeWheelMinute: number = 0
  @State private timeWheelSecond: number = 0
  @State private timeWheelTickLabels: string[] = []
  @State private timeWheelVisualOffset: number = 0
  @State private timeWheelDragging: boolean = false
  private timeWheelLastInputMs: number = 0
  private timeWheelLastTouchX: number = 0
  private timeWheelLastTouchMs: number = 0
  private timeWheelDragCarry: number = 0
  @State private timeWheelAppliedSteps: number = 0
  private timeWheelTransitionTimer: number = 0
  private timeWheelTargetMs: number = 0
  private timeWheelLastNativePushMs: number = 0
  private timeWheelGestureBaseMs: number = 0
  private timeWheelGestureSteps: number = 0
  private timeWheelGestureTickOffset: number = 0
  private timeWheelTrackBaseMs: number = 0
  private readonly timeWheelTickSpacing: number = 42
  private readonly timeWheelCenterTick: number = 20
  @State private manualYear: number = 2026
  @State private manualMonth: number = 7
  @State private manualDay: number = 20
  @State private manualHour: number = 23
  @State private manualMinute: number = 0
  @State private selectedLanguage: string = I18n.systemLanguage()
  @StorageLink('i18nLang') private i18nLang: string = I18n.systemLanguage()
  @State private bridgeSyncStarted: boolean = false
  private autoLocateStarted: boolean = false
  @State private equatorialMount: boolean = false
  @State private nightMode: boolean = false
  @State private flipVert: boolean = false
  @State private flipHoriz: boolean = false
  @State private pickedDate: Date = new Date()
  @State private pickedTime: Date = new Date()
  @State private observationTimeText: string = '--'
  @State private locationText: string = '--'
  @State private coordinateText: string = '--'
  @State private altitudeText: string = '--'
  @State private locationPickerName: string = I18n.t('custom_location')
  @State private locationPickerLatitude: number = 39.9042
  @State private locationPickerLongitude: number = 116.4074
  @State private locationPickerAltitude: number = 44
  @State private locationPickerStatus: ResourceStr = I18n.t('m_drag_map_hint')
  @State private mapGestureActive: boolean = false
  @State private observerPlanet: string = 'Earth'
  @State private planetList: string[] = []
  @State private pointAlt: string = '45'
  @State private pointAz: string = '180'
  @State private pointResult: string = ''
  @State private coordInputRA: string = ''
  @State private coordInputDec: string = ''
  @State private watchAlt: number = 45
  @State private watchAz: number = 180
  @State private watchTracking: boolean = false
  @State private watchResult: string = ''
  @State private watchLastSend: number = 0
  @State private sessionJson: string = ''
  @State private sessionExportSig: string = ''
  @State private sessionHint: string = ''
  @State private canUseDistributed: boolean = false
  @State private tonightDate: string = ''
  @State private tonightMoon: string = ''
  @State private tonightSun: string = ''
  @State private tonightDark: string = ''
  @State private tonightPlanets: string[] = []
  @State private tonightShowers: string[] = []
  @State private tonightSats: string = ''
  @State private tonightHint: string = ''
  // 今晚天象点击跳转用：各卡片对应的事件时刻(JD)与锁定对象
  @State private tonightMoonJd: number = 0
  @State private tonightSunJd: number = 0
  @State private tonightShowerJd: number = 0
  @State private tonightPlanetRows: TonightPlanetRow[] = []
  @State private locationPickMode: string = 'map'
  @State private locSearchQuery: string = ''
  @State private locSearchResults: LocSearchItem[] = []
  @State private locSearching: boolean = false
  @State private observerTimeZone: string = ''
  @State private savedLocations: SavedLocation[] = []
  @State private locSearchDebounce: number = 0
  @State private hierContinent: string = ''
  @State private hierRegion: string = ''
  @State private hierCity: string = ''
  @State private mapRenderWidth: number = 280
  @State private mapRenderHeight: number = 150
  @State private fovText: string = '--'
  @State private trackingText: string = 'Off'
  @State private skyWidth: number = 1
  @State private skyHeight: number = 1
  @State private panelWidth: number = 336
  @State private panelMaxHeight: number = 660
  // 离屏幕边框的安全留白(vp)：约 0.7cm，避免 UI 贴边
  private readonly EDGE_MARGIN: number = 44
  // 启动动画星空（百分比坐标，自适应各种屏幕尺寸）
  private readonly splashStars: StarDot[] = [
    { xPct: 8, yPct: 12, r: 1.5, bright: true }, { xPct: 17, yPct: 28, r: 1, bright: false },
    { xPct: 26, yPct: 9, r: 2, bright: true }, { xPct: 33, yPct: 22, r: 1, bright: false },
    { xPct: 41, yPct: 14, r: 1.5, bright: true }, { xPct: 49, yPct: 30, r: 1, bright: false },
    { xPct: 57, yPct: 11, r: 2, bright: true }, { xPct: 64, yPct: 25, r: 1, bright: false },
    { xPct: 72, yPct: 16, r: 1.5, bright: true }, { xPct: 80, yPct: 9, r: 1, bright: false },
    { xPct: 88, yPct: 23, r: 2, bright: true }, { xPct: 93, yPct: 14, r: 1, bright: false },
    { xPct: 12, yPct: 42, r: 1, bright: false }, { xPct: 23, yPct: 55, r: 1.5, bright: true },
    { xPct: 35, yPct: 48, r: 1, bright: false }, { xPct: 46, yPct: 60, r: 2, bright: true },
    { xPct: 54, yPct: 44, r: 1, bright: false }, { xPct: 63, yPct: 53, r: 1.5, bright: true },
    { xPct: 73, yPct: 47, r: 1, bright: false }, { xPct: 84, yPct: 58, r: 2, bright: true },
    { xPct: 91, yPct: 49, r: 1, bright: false }, { xPct: 15, yPct: 70, r: 1.5, bright: true },
    { xPct: 28, yPct: 82, r: 1, bright: false }, { xPct: 38, yPct: 73, r: 2, bright: true },
    { xPct: 50, yPct: 86, r: 1, bright: false }, { xPct: 60, yPct: 76, r: 1.5, bright: true },
    { xPct: 70, yPct: 84, r: 1, bright: false }, { xPct: 82, yPct: 72, r: 2, bright: true },
    { xPct: 90, yPct: 83, r: 1, bright: false }, { xPct: 6, yPct: 64, r: 1, bright: false },
  ]
  @State private observingList: string[] = []
  @State private stars: boolean = true
  @State private skyCultures: string[] = []
  @State private isLoading: boolean = true
  // 启动动画：星空淡入 + 核心就绪后整体淡出
  @State private splashGone: boolean = false
  @State private splashOpacity: number = 0
  @State private splashIn: boolean = false
  @State private twPhase: boolean = false
  private twTimer: number = 0
  @State private currentSkyCulture: string = ""
  @State private planets: boolean = true
  @State private enlargePlanets: boolean = false
  @State private enlargeSun: boolean = false
  @State private minorBodyMarkers: boolean = false
  @State private planetNomenclature: boolean = false
  @State private planetOrbits: boolean = false
  @State private planetHints: boolean = false
  @State private planetTrails: boolean = false
  @State private enlargeMoon: boolean = false
  @State private eclipticLine: boolean = true
  @State private galacticGrid: boolean = false
  @State private galacticEquator: boolean = false
  @State private lightPollution: boolean = false
  @State private dsoTextures: boolean = true
  @State private asteroidLines: boolean = false
  @State private asteroidLabels: boolean = false
  @State private zodiacalLight: boolean = false
  @State private viewTab: number = 0  // View面板子标签索引
  @State private configTab: number = 0  // Configuration面板子标签索引
  // Open AstroCalc on the observation-first view: it needs no selected object
  // and immediately gives a useful answer for the current location and date.
  @State private astroTab: number = 5   // 天文计算面板子标签索引
  @State private nightViewTab: number = 0
  @State private meteors: boolean = false
  @State private dsoLabels: boolean = true
  @State private autoZoomResets: boolean = false
  @State private equatorLine: boolean = false
  @State private supergalacticEq: boolean = false
  @State private eclJ2000Line: boolean = false
  @State private equJ2000Line: boolean = false
  @State private celestialPoles: boolean = false
  @State private eclipticPoles: boolean = false
  @State private galacticPoles: boolean = false
  @State private equinoxPoints: boolean = false
  @State private solsticePoints: boolean = false
  @State private antisolarPoint: boolean = false
  @State private umbraCircle: boolean = false
  @State private penumbraCircle: boolean = false
  @State private compassMarks: boolean = false
  @State private primeVerticalLine: boolean = false
  @State private currentVerticalLine: boolean = false
  @State private colureLines: boolean = false
  @State private circumpolarCircles: boolean = false
  @State private eclipticJ2000Grid: boolean = false
  @State private equatorialJ2000Grid: boolean = false
  @State private supergalacticGrid: boolean = false
  @State private longitudeLine: boolean = false
  @State private quadratureLine: boolean = false
  @State private precessionCircles: boolean = false
  @State private eclipticJ2000Poles: boolean = false
  @State private equinoxJ2000Pts: boolean = false
  @State private solsticeJ2000Pts: boolean = false
  @State private galacticCenter: boolean = false
  @State private supergalacticPoles: boolean = false
  @State private apexPoints: boolean = false
  @State private umbraCenter: boolean = false
  @State private zenithNadir: boolean = false
  // 竖直视角限位：默认开。开启后手动上下拖只会在 天顶(+90°)↔天底(-90°) 之间，不会翻过头把天倒过来。
  // 卡在天顶↔天底：默认开。开启后上下滑只改高度角（到天顶/天底就停，不翻转），
  // 左右滑只改方位角——即使手指在屏幕偏左/偏右处竖直滑，画面也绝不会旋转。
  @State private verticalClamp: boolean = true
  // 固定目标位置：开启后仍可自由拖动，松手时记录当前目标位置供后续缩放保持。
  @State private viewLock: boolean = false
  // 画面防弯曲：限制最大视场角(100°)，不能缩到"整个天空变成一个球"，地平线保持基本平直。
  @State private flatHorizon: boolean = true
  @State private invariantPlaneLine: boolean = false
  @State private solarEquatorLine: boolean = false
  @State private fixedEquatorLine: boolean = false
  @State private fixedEquatorialGrid: boolean = false
  @State private fovMarker: boolean = false
  @State private intercardinalPts: boolean = false
  @State private landscapeIllum: boolean = false
  @State private landscapeLabels: boolean = false
  @State private zodiac: boolean = false
  @State private lunarSystem: boolean = false
  @State private asterismLines: boolean = false
  @State private asterismLabels: boolean = false
  @State private hipsSurveys: boolean = false
  @State private toastSurvey: boolean = false
  // 桥接数据
  @State private landscapeList: Array<LandscapeItem> = []
  @State private currentLandscapeId: string = ''
  @State private scriptList: string[] = []
  @State private moduleList: string[] = []
  @State private rtsData: Map<string, string> = new Map()
  @State private rtsError: string = ''
  @State private rtsCalendarData: Array<RtsCalendarDay> = []
  @State private rtsCalendarName: string = ''
  @State private rtsCalendarError: string = ''
  @State private rtsCalendarDays: number = 14
  @State private rtsCalendarStartOffsetDays: number = 0
  @State private rtsCalendarStartYear: number = new Date().getFullYear()
  @State private rtsCalendarStartMonth: number = new Date().getMonth() + 1
  @State private rtsCalendarStartDay: number = new Date().getDate()
  @State private rtsCalendarLoading: boolean = false
  @State private rtsCalendarNeedsGeneration: boolean = false
  @State private rtsCalendarProgress: number = 0
  @State private rtsCalendarTotalDays: number = 0
  @State private almanacData: Map<string, string> = new Map()
  @State private almanacSeasons: Array<SeasonEvent> = []
  @State private almanacSeasonYear: string = ''
  @State private objectInfo: Map<string, string> = new Map()
  @State private dsoTotalCount: number = 0
  @State private dsoGalaxies: number = 0
  @State private dsoClusters: number = 0
  @State private dsoNebulae: number = 0
  @State private planetPositions: Array<PlanetPosition> = []
  @State private positionMode: number = 0
  @State private hecPositions: Array<HeliocentricPosition> = []
  @State private hecTime: string = ''
  @State private hecIncludeSelectedMinor: boolean = false
  @State private hecIncludeBrightComets: boolean = false
  @State private hecCometMagnitudeLimit: number = 9
  @State private celestialPositions: Array<CelestialPosition> = []
  @State private celestialPositionCategory: string = 'planets'
  @State private celestialPositionMagnitude: number = 6
  @State private celestialPositionHorizontal: boolean = true
  @State private celestialPositionTime: string = ''
  @State private ephemerisData: Array<EphemerisRow> = []
  @State private ephemerisName: string = ''
  @State private ephemerisError: string = ''
  @State private ephemerisDays: number = 14
  @State private ephemerisStepHours: number = 24
  @State private ephemerisStartOffsetDays: number = 0
  @State private ephemerisStartYear: number = new Date().getFullYear()
  @State private ephemerisStartMonth: number = new Date().getMonth() + 1
  @State private ephemerisStartDay: number = new Date().getDate()
  @State private ephemerisMode: number = 0
  @State private ephemerisPrimary: string = 'Moon'
  @State private ephemerisSecondary: string = 'Sun'
  @State private ephemerisLoading: boolean = false
  @State private planetCalcData: Array<PlanetCalcItem> = []
  @State private planetCalcMode: number = 0
  @State private planetPairDistanceData: Array<PlanetPairDistancePoint> = []
  @State private planetPairDistanceError: string = ''
  @State private planetPairFirst: string = 'Sun'
  @State private planetPairSecond: string = 'Moon'
  @State private planetPairFirstName: string = '太阳'
  @State private planetPairSecondName: string = '月亮'
  @State private planetPairDays: number = 40
  @State private planetPairStepDays: number = 4
  @State private planetPairAngularAvailable: boolean = true
  @State private planetPairLinearMin: number = 0
  @State private planetPairLinearMax: number = 1
  @State private planetPairAngularMin: number = 0
  @State private planetPairAngularMax: number = 180
  @State private altAzCurve: Array<AltAzPoint> = []
  @State private altAzName: string = ''
  @State private altAzError: string = ''
  @State private altAzHours: number = 24
  @State private altAzStepMin: number = 30
  @State private altAzShowSun: boolean = false
  @State private altAzShowMoon: boolean = false
  @State private altAzMinimum: number = -90
  @State private graphStartOffsetDays: number = 0
  @State private graphStartYear: number = new Date().getFullYear()
  @State private graphStartMonth: number = new Date().getMonth() + 1
  @State private graphStartDay: number = new Date().getDate()
  @State private graphMode: number = 0
  @State private graphLoading: boolean = false
  private graphTargetPickerActive: boolean = false
  private rtsTargetPickerActive: boolean = false
  private ephemerisTargetPickerActive: boolean = false
  @State private annualElevationData: Array<AnnualElevationPoint> = []
  @State private annualElevationName: string = ''
  @State private annualElevationError: string = ''
  @State private annualElevationHour: number = 0
  @State private annualElevationMinimum: number = -90
  @State private observabilityData: Array<ObservabilityDay> = []
  @State private observabilityName: string = ''
  @State private observabilityError: string = ''
  @State private observabilityDays: number = 30
  @State private observabilityMinAltitude: number = 20
  @State private lunarElongationData: Array<LunarElongationPoint> = []
  @State private lunarElongationName: string = ''
  @State private lunarElongationError: string = ''
  @State private lunarElongationDays: number = 30
  @State private lunarElongationStepHours: number = 12
  @State private lunarElongationLimit: number = 40
  @State private planetTimeSeriesData: Array<PlanetTimeSeriesPoint> = []
  @State private planetTimeSeriesName: string = ''
  @State private planetTimeSeriesError: string = ''
  @State private planetTimeSeriesDays: number = 30
  @State private planetTimeSeriesStepHours: number = 24
  @State private planetTimeSeriesLeftMetric: string = 'angularSize'
  @State private planetTimeSeriesRightMetric: string = 'magnitude'
  @State private planetTimeSeriesLeftMin: number = 0
  @State private planetTimeSeriesLeftMax: number = 1
  @State private planetTimeSeriesRightMin: number = 0
  @State private planetTimeSeriesRightMax: number = 1
  @State private eclipseData: Array<EclipseItem> = []
  @State private eclipseMonths: number = 36
  @State private eclipseStartOffsetDays: number = 0
  @State private eclipseStartYear: number = new Date().getFullYear()
  @State private eclipseStartMonth: number = new Date().getMonth() + 1
  @State private eclipseStartDay: number = new Date().getDate()
  @State private eclipseLoading: boolean = false
  @State private eclipseError: string = ''
  @State private eclipseKindFilter: number = 0
  @State private eclipseTypeFilter: number = 0
  @State private eclipseMode: number = 0
  @State private planetaryTransitData: Array<PlanetaryTransitItem> = []
  @State private planetaryTransitYears: number = 20
  @State private planetaryTransitLoaded: boolean = false
  @State private planetaryTransitError: string = ''
  @State private moonPhaseData: Array<MoonPhaseItem> = []
  @State private moonPhaseDays: number = 30
  @State private phenomenaData: Array<PhenomenonItem> = []
  @State private phenomenaHint: string = ''
  @State private phenomenaLoading: boolean = false
  @State private phenomenaPrimary: string = 'all'
  @State private phenomenaTarget: string = 'all'
  @State private phenomenaDays: number = 400
  @State private phenomenaStartOffsetMonths: number = 0
  @State private phenomenaMaxSeparation: number = 4
  @State private phenomenaIncludeOppositions: boolean = true
  @State private phenomenaIncludePerihelionAphelion: boolean = true
  @State private phenomenaIncludeElongationsQuadratures: boolean = true
  @State private phenomenaIncludeStations: boolean = true
  @State private tonightAstro: TonightEvents | null = null
  @State private wutTargets: Array<WutTarget> = []
  @State private wutCategory: string = 'planets'
  @State private wutPeriod: string = 'midnight'
  @State private wutMinAltitude: number = 20
  @State private wutMaxMagnitude: number = 6
  @State private wutLimitAngularSize: boolean = false
  @State private wutMinAngularSizeArcmin: number = 10
  @State private wutMaxAngularSizeArcmin: number = 600
  @State private wutAngularSizeAvailable: boolean = true
  @State private wutObservationTime: string = ''
  @State private wutHint: string = ''
  @State private siderealTimeText: string = '--'
  @State private nightModeOn: boolean = false
  @State private atmoPressure: number = 1013
  @State private atmoTemperature: number = 10
  @State private atmoExtinction: number = 0.13
  @State private refractionOn: boolean = true
  @State private skyCultureList: Array<SkyCultureItem> = []
  @State private currentSkyCultureId: string = ''
  @State private pluginList: Array<PluginItem> = []
  @State private landscapeDetailOpen: boolean = false
  @State private selectedLandscapeName: string = ''
  @State private landscapeTransp: number = 0
  @State private landscapeFadeWithZoom: boolean = true
  @State private bortleScale: number = 3
  @State private milkyWayBright: number = 3
  @State private starMagLimit: number = 6.0
  @State private infoLevel: number = 1
  @State private useMetricUnits: boolean = true
  // 新增面板控制
  @State private showConfigPanel: boolean = false
  @State private showAstroPanel: boolean = false
  @State private showHelpPanel: boolean = false
  @State private fogEffect: boolean = false
  @State private nebulae: boolean = false
  @State private milkyWay: boolean = true
  @State private ground: boolean = true
  @State private constellationLines: boolean = false
  @State private constellationLabels: boolean = false
  @State private constellationBoundaries: boolean = false
  @State private constellationArt: boolean = false
  @State private atmosphere: boolean = true
  @State private cardinalPoints: boolean = true
  @State private azimuthGrid: boolean = false
  @State private equatorialGrid: boolean = false
  @State private eclipticGrid: boolean = false
  @State private meridianLine: boolean = false
  @State private horizonLine: boolean = false
  @State private planetLabels: boolean = false
  @State private starLabels: boolean = false
  @State private gyroscopeEnabled: boolean = false
  @State private gyroscopeStatus: ResourceStr = I18n.t('m_gyro_off')
  @State private gyroscopeSensitivityText: string = 'Standard'
  @State private gyroCalibPanelOpen: boolean = false
  private applicationInForeground: boolean = true
  private gyroPausedForBackground: boolean = false
  // The gyro control itself becomes a live compass while it is enabled.
  @State private gyroCompassText: string = '罗盘 --'
  @State private gyroCompassAngle: number = 0
  @State private gyroOffsetAz: number = 0    // 方位角校准偏移（度）
  @State private gyroOffsetAlt: number = 0   // 高度角校准偏移（度）
  @State private liveMode: boolean = true
  @State private timeScale: string = '1x'
  @State private currentFovText: string = '--'
  /** 观测地 UTC 偏移（小时），由 getState 的 timeText-jd 差值校准，供轻量时间刷新使用 */
  private utcOffsetHours: number = 8
  @State private fovSliderValue: number = 60
  @State private currentProjection: string = 'ProjectionPerspective'
  @State private uiLocked: boolean = false
  @State private panelIdleOpacity: number = 1.0
  @State private panelIdleGlass: boolean = false
  @State private railPinned: boolean = true
  @State private railCollapsed: boolean = false
  @State private panelOffsetX: number = 0
  @State private panelOffsetY: number = 0
  @State private catalogList: StarCatalogItem[] = []
  @State private catalogLoading: boolean = false
  @State private catalogBusy: boolean = false
  @State private catalogDownloadingId: string = ''
  @State private catalogMsg: string = ''
  @State private bookmarkList: BookmarkItem[] = []
  @State private bookmarkLoading: boolean = false
  @State private newBookmarkName: string = ''
  // 望远镜/目镜配置（Oculars）
  @State private ocularMode: boolean = false
  @State private telradOn: boolean = false
  @State private crosshairsOn: boolean = false
  @State private ccdOn: boolean = false
  @State private ocularNames: string[] = []
  @State private telescopeNames: string[] = []
  @State private lensNames: string[] = []
  @State private ccdNames: string[] = []
  @State private ocularIndex: number = -1
  @State private telescopeIndex: number = -1
  @State private lensIndex: number = -1
  @State private ccdIndex: number = -1
  // 卫星（Satellites）
  @State private satGroups: string[] = []
  @State private activeSatGroup: string = ''
  @State private satLabels: boolean = false
  @State private satOrbitLines: boolean = false
  @State private satHints: boolean = false
  @State private satIconicMode: boolean = false
  @State private satHideInvisible: boolean = false
  @State private satCount: number = 0
  // 流星雨（MeteorShowers）
  @State private msEnabled: boolean = false
  @State private msLabels: boolean = false
  @State private msActiveOnly: boolean = false
  @State private msMarker: boolean = false
  @State private msShowerList: MeteorShowerItem[] = []
  // 帮助面板：关于/日志/配置导入导出
  @State private aboutVersion: string = ''
  @State private aboutQt: string = ''
  @State private aboutUserDir: string = ''
  @State private aboutConfigFile: string = ''
  @State private logText: string = ''
  @State private logVisible: boolean = false
  @State private configExportText: string = ''
  @State private configExportVisible: boolean = false
  @State private configImportText: string = ''
  @State private configImportMsg: string = ''
  @State private skyTouchFeedback: boolean = false
  @State private skyTouchX: number = 0   // 触摸点窗口坐标(px)，供反馈圈跟随手指
  @State private skyTouchY: number = 0
  @State private lx200Host: string = '127.0.0.1'
  @State private lx200Port: string = '4030'
  @State private lx200Status: ResourceStr = I18n.t('m_telescope_idle')
  @State private actionHint: ResourceStr = ''
  @State private speechStatus: string = ''
  // ===== 脚本录制 / 回放（#39）=====
  @State private recording: boolean = false
  @State private recordBuffer: Array<RecordCmd> = []
  @State private recordCount: number = 0
  @State private recordName: string = ''
  @State private recordMsg: string = ''
  @State private recordings: Array<RecordingEntry> = []
  @State private replaying: boolean = false
  // ===== 视频帧序列录制（#40）=====
  @State private videoRecording: boolean = false
  @State private videoDir: string = ''
  @State private videoFrameCount: number = 0
  @State private videoMaxFrames: number = 0
  @State private videoFps: string = '1'
  @State private videoDuration: string = '5'
  private lastRecordKey: string = ''
  private lastRecordTime: number = 0

  private hintTimer: number = 0
  private panelIdleTimer: number = -1

  private resetPanelIdle(): void {
    if (this.panelIdleTimer >= 0) {
      clearTimeout(this.panelIdleTimer)
    }
    this.panelIdleOpacity = 1.0
    this.panelIdleGlass = false
    this.panelIdleTimer = setTimeout(() => {
      if (!this.uiLocked) {
        this.panelIdleOpacity = 0.88
        this.panelIdleGlass = true
      }
      this.panelIdleTimer = -1
    }, 5000)
  }

  private sidebarAutoCollapseTimer: number = -1

  private resetSidebarAutoCollapse(): void {
    if (this.sidebarAutoCollapseTimer >= 0) {
      clearTimeout(this.sidebarAutoCollapseTimer)
    }
    // 空闲→左侧栏向左收起（仅留把手）；钉住(railPinned)时不收起
    this.railCollapsed = false
    if (!this.railPinned) {
      this.sidebarAutoCollapseTimer = setTimeout(() => {
        this.railCollapsed = true
        this.sidebarAutoCollapseTimer = -1
      }, 5000)
    }
  }
  // 目标详情自动刷新：选中天体后每 300ms 重新拉一次坐标，让“地平坐标”随地球自转实时变化。
  // detailTimer 为 setInterval 句柄；detailRefreshing 防重入；detailRefreshGuard 是兜底定时器，
  // 因为 callNativeWhenReady 在放弃轮询时【不】回调 onOk，必须靠它复位，否则会卡死不再刷新。
  private detailTimer: number = 0
  private detailRefreshing: boolean = false
  private detailRefreshGuard: number = 0
  private foregroundRefreshPaused: boolean = false
  // FullInfo is intentionally loaded after a new target is drawn. Keeping its
  // timer separate from the live-value poll prevents it from delaying panning.
  private selectedFullInfoTimer: number = 0
  private expandedTargetPlacementTimer: number = 0
  private selectedUiLayoutTimer: number = 0
  private lastSafeNavigationPayload: string = ''
  private lastSafeNavigationAt: number = 0
  private categoryOffset: number = 0
  private categoryRequestSerial: number = 0
  private readonly CATEGORY_PAGE_SIZE: number = 60
  // 时间面板打开时，每 1s 拉一次 getState，让"时间"字段像走动的钟一样实时更新
  // （否则只在打开瞬间刷新一次，点按钮/时间流逝都不会再更新，永远显示 --）
  private timePanelTimer: number = 0
  /** 时间面板低频全量状态兜底定时器（3s），与高频轻量时间刷新配合使用 */
  private timePanelFullTimer: number = 0
  private touchStartX: number = 0
  private touchStartY: number = 0
  private touchLastX: number = 0
  private touchLastY: number = 0
  private touchMoved: boolean = false
  private skyTouchActive: boolean = false
  private pinchStartDistance: number = 0
  /** 缩放 FOV 胶囊提示的节流时间戳 */
  private lastFovHintMs: number = 0
  private pinchActive: boolean = false
  private nativeDragActive: boolean = false
  private lastDragCommandMs: number = 0
  private dragFilteredX: number = 0
  private dragFilteredY: number = 0
  private dragLastRawX: number = 0
  private dragLastRawY: number = 0
  private dragLastSampleMs: number = 0
  private dragVelocityX: number = 0
  private dragVelocityY: number = 0
  private skyInertiaTimer: number = 0
  // Momentum runs in the Qt render loop. ArkTS only supplies the release
  // velocity, avoiding a stream of cross-thread drag commands after lift-off.
  private nativeSkyInertiaActive: boolean = false
  private skyDragging: boolean = false
  private gyroLastTimeMs: number = 0
  private gyroGuideTargetAz: number = Number.NaN
  private gyroGuideTargetAlt: number = Number.NaN
  private gyroGuideLastUpdateMs: number = 0
  private gyroGuideReachedAtMs: number = 0
  private gyroLastDiagnosticMs: number = 0
  private gyroLastCompassUiUpdateMs: number = 0
  private gyroMagneticHeading: number = Number.NaN
  private gyroRawAzimuth: number = Number.NaN
  private gyroRawAltitude: number = Number.NaN
  // Automatic, session-local alignment from the physical magnetic compass to
  // Stellarium's Alt/Az frame. The visible slider remains a separate manual
  // fine adjustment, so it stays predictable for the user.
  private gyroCompassAzAlignment: number = 0
  private gyroAbsolutePoseReady: boolean = false
  private gyroAbsoluteUp: number[] = [0, 1, 0]
  // alpha is not a stable world heading while a tablet lies flat. Establish
  // this reference only after the display normal has a usable horizontal part.
  private gyroHeadingReferenceReady: boolean = false
  private gyroHeadingSensorAz: number = 0
  private gyroHeadingViewAz: number = 0
  private gyroEventCount: number = 0
  private gyroRawEventCount: number = 0
  private readonly gyroSensitivity: number = 180
  private gyroCallback: ((data: sensor.OrientationResponse) => void) | undefined = undefined
  private gyroRotationCallback: ((data: sensor.RotationVectorResponse) => void) | undefined = undefined
  private gyroGravityCallback: ((data: sensor.GravityResponse) => void) | undefined = undefined
  private gyroMagneticCallback: ((data: sensor.MagneticFieldResponse) => void) | undefined = undefined
  private gyroUsingRotationVector: boolean = false
  // These are intentionally kept in device coordinates. Combining gravity
  // and magnetic field here produces a stable ENU basis; rotating magnetic
  // data with the rotation-vector pose was the source of the prior drift.
  private gyroGravityDevice: number[] = []
  private gyroMagneticDevice: number[] = []
  private gyroFilteredGravityDevice: number[] = []
  private gyroFilteredMagneticDevice: number[] = []
  private dragLogCount: number = 0
  private touchStartedOnUi: boolean = false
  private panelDragging: boolean = false
  private panelDragStartX: number = 0
  private panelDragStartY: number = 0
  private panelDragStartOffsetX: number = 0
  private panelDragStartOffsetY: number = 0

  // 左侧栏布局常量
  private readonly RAIL_TOP_PAD: number = 10
  private readonly RAIL_ITEM_STEP: number = 58
  private readonly RAIL_MORE_OFFSET: number = 8
  private readonly RAIL_MUSIC_OFFSET: number = 60
  private readonly RAIL_GYRO_OFFSET: number = 116
  // 平板缩放组与左侧轨道对齐，固定放在轨道下方，避免与底部目标详情卡抢位置。
  private readonly EXPANDED_ZOOM_GAP: number = 8
  private readonly EXPANDED_ZOOM_SIZE: number = 48

  // 常用入口：直接固定在左侧栏（观星高频操作）
  private readonly pinnedActions: ShellAction[] = [
    { label: I18n.t('dock_search'), icon: 'search', panel: 'search' },
    { label: I18n.t('dock_time'), icon: 'clock', panel: 'time' },
    { label: I18n.t('dock_place'), icon: 'location', panel: 'place' },
    { label: I18n.t('dock_layers'), icon: 'layers', panel: 'layers' },
    { label: I18n.t('dock_observe'), icon: 'observe', panel: 'observing' },
    { label: I18n.t('dock_settings'), icon: 'settings', panel: 'settings' }
  ]
  // 低频入口：收进抽屉（点侧栏底部九宫格按钮展开），图标全部专属不重复
  private readonly drawerActions: ShellAction[] = [
    { label: I18n.t('panel_bookmarks'), icon: 'bookmarks', panel: 'bookmarks' },
    { label: I18n.t('panel_oculars'), icon: 'telescope', panel: 'oculars' },
    { label: I18n.t('panel_satellites'), icon: 'satellite', panel: 'satellites' },
    { label: I18n.t('panel_meteorshowers'), icon: 'meteor', panel: 'meteorshowers' },
    { label: I18n.t('i0274'), icon: 'orbit', panel: 'astro' },
    { icon: 'tune', label: I18n.t('i0273'), panel: 'config' },
    { icon: 'help', label: I18n.t('i0217'), panel: 'help' },
    { icon: 'audio', label: I18n.t('panel_audio_ctrl'), panel: 'audio' }
  ]
  // 手机端抽屉：陀螺仪与音频控制已提到右上角常驻快捷区，此处不再重复列出
  private readonly compactDrawerActions: ShellAction[] = [
    { label: I18n.t('dock_observe'), icon: 'observe', panel: 'observing' },
    { label: I18n.t('panel_bookmarks'), icon: 'bookmarks', panel: 'bookmarks' },
    { label: I18n.t('panel_oculars'), icon: 'telescope', panel: 'oculars' },
    { label: I18n.t('panel_satellites'), icon: 'satellite', panel: 'satellites' },
    { label: I18n.t('panel_meteorshowers'), icon: 'meteor', panel: 'meteorshowers' },
    { label: I18n.t('i0274'), icon: 'orbit', panel: 'astro' },
    { icon: 'tune', label: I18n.t('i0273'), panel: 'config' },
    { label: I18n.t('dock_settings'), icon: 'settings', panel: 'settings' },
    { icon: 'help', label: I18n.t('i0217'), panel: 'help' }
  ]
  // 全量列表：面板渲染等处仍按老逻辑遍历（顺序 = 固定项 + 抽屉项）
  private readonly actions: ShellAction[] = [
    { label: I18n.t('i0104'), icon: 'search', panel: 'search' },
    { label: I18n.t('i0054'), icon: 'clock', panel: 'time' },
    { label: I18n.t('i0014'), icon: 'location', panel: 'place' },
    { label: I18n.t('i0100'), icon: 'layers', panel: 'layers' },
    { label: I18n.t('i0102'), icon: 'settings', panel: 'settings' },
    { label: I18n.t('panel_bookmarks'), icon: 'bookmarks', panel: 'bookmarks' },
    { label: I18n.t('panel_oculars'), icon: 'telescope', panel: 'oculars' },
    { label: I18n.t('panel_satellites'), icon: 'satellite', panel: 'satellites' },
    { label: I18n.t('panel_meteorshowers'), icon: 'meteor', panel: 'meteorshowers' },
    { icon: 'tune', label: I18n.t('i0273'), panel: 'config' },
    { icon: 'help', label: I18n.t('i0217'), panel: 'help' },
    { icon: 'audio', label: I18n.t('panel_audio_ctrl'), panel: 'audio' }
  ]
  @State private drawerOpen: boolean = false

  private SELFTEST: boolean = false  // 开发自检：启动即对全部开关跑一次 findAction，验证无死开关。发布前改 false。

  // 城市快速定位预设数据: id -> "lat|lon|alt"
  private getCityPreset(id: string): CityPreset | undefined {
    const m: Record<string, string> = {
      'Beijing': '39.9042|116.4074|44', 'Shanghai': '31.2304|121.4737|4',
      'Guangzhou': '23.1291|113.2644|21', 'Shenzhen': '22.5431|114.0579|7',
      'Chengdu': '30.5728|104.0668|500', 'Hangzhou': '30.2741|120.1551|11',
      'Wuhan': '30.5928|114.3055|23', 'Xian': '34.3416|108.9398|405',
      'Nanjing': '32.0603|118.7969|20', 'Chongqing': '29.5630|106.5516|259',
      'Harbin': '45.7500|126.6500|132', 'Lhasa': '29.6500|91.1000|3650',
      'Urumqi': '43.8256|87.6168|800', 'HongKong': '22.3193|114.1694|32',
      'Tokyo': '35.6762|139.6503|40', 'Seoul': '37.5665|126.9780|38',
      'Singapore': '1.3521|103.8198|15', 'NewYork': '40.7128|-74.0060|10',
      'London': '51.5074|-0.1278|25', 'Sydney': '-33.8688|151.2093|58',
      'Paris': '48.8566|2.3522|35', 'Berlin': '52.5200|13.4050|34',
      'Moscow': '55.7558|37.6173|156', 'Dubai': '25.2048|55.2708|16',
      'Mumbai': '19.0760|72.8777|14', 'Cairo': '30.0444|31.2357|23',
      'Rio': '-22.9068|-43.1729|5', 'LosAngeles': '34.0522|-118.2437|89',
      'Toronto': '43.6532|-79.3832|76', 'Mexico': '19.4326|-99.1332|2240',
      'Bangkok': '13.7563|100.5018|2', 'Istanbul': '41.0082|28.9784|39',
      'Amsterdam': '52.3676|4.9041|2', 'Stockholm': '59.3293|18.0686|28',
      'Reykjavik': '64.1466|-21.9426|61', 'CapeTown': '-33.9249|18.4241|25',
      'BuenosAires': '-34.6037|-58.3816|25', 'Honolulu': '21.3099|-157.8581|4',
    }
    const v = m[id]
    if (v === undefined) { return undefined }
    const p = v.split('|')
    const result: CityPreset = { lat: parseFloat(p[0]), lon: parseFloat(p[1]), alt: parseFloat(p[2]) }
    return result
  }

  private readonly SELFTEST_ACTION_IDS: string[] = [
    "actionHorizontal_Flip",
    "actionShow_Antisolar_Point",
    "actionShow_Apex_Points",
    "actionShow_Asterism_Labels",
    "actionShow_Asterism_Lines",
    "actionShow_Atmosphere",
    "actionShow_Azimuthal_Grid",
    "actionShow_Celestial_J2000_Poles",
    "actionShow_Celestial_Poles",
    "actionShow_Circumpolar_Circles",
    "actionShow_Colure_Lines",
    "actionShow_Compass_Marks",
    "actionShow_Constellation_Art",
    "actionShow_Constellation_Boundaries",
    "actionShow_Constellation_Labels",
    "actionShow_Constellation_Lines",
    "actionShow_Current_Vertical_Line",
    "actionShow_DSO_Textures",
    "actionShow_Ecliptic_Grid",
    "actionShow_Ecliptic_J2000_Grid",
    "actionShow_Ecliptic_J2000_Line",
    "actionShow_Ecliptic_J2000_Poles",
    "actionShow_Ecliptic_Line",
    "actionShow_Ecliptic_Poles",
    "actionShow_Equator_J2000_Line",
    "actionShow_Equator_Line",
    "actionShow_Equatorial_Grid",
    "actionShow_Equatorial_J2000_Grid",
    "actionShow_Equinox_J2000_Points",
    "actionShow_Equinox_Points",
    "actionShow_FOV_Center_Marker",
    "actionShow_Fixed_Equator_Line",
    "actionShow_Fixed_Equatorial_Grid",
    "actionShow_Fog",
    "actionShow_Galactic_Center",
    "actionShow_Galactic_Equator_Line",
    "actionShow_Galactic_Grid",
    "actionShow_Galactic_Poles",
    "actionShow_Ground",
    "actionShow_Hips_Surveys",
    "actionShow_Horizon_Line",
    "actionShow_Intercardinal_Points",
    "actionShow_Invariable_Plane_Line",
    "actionShow_LandscapeIllumination",
    "actionShow_LandscapeLabels",
    "actionShow_Longitude_Line",
    "actionShow_LunarSystem",
    "actionShow_Meridian_Line",
    "actionShow_MilkyWay",
    "actionShow_Nebulas",
    "actionShow_Night_Mode",
    "actionShow_Penumbra_Circle",
    "actionShow_Planets",
    "actionShow_Planets_EnlargeMoon",
    "actionShow_Planets_EnlargePlanets",
    "actionShow_Planets_EnlargeSun",
    "actionShow_Planets_Hints",
    "actionShow_Planets_Nomenclature",
    "actionShow_Planets_Orbits",
    "actionShow_Planets_ShowMinorBodyMarkers",
    "actionShow_Planets_Trails",
    "actionShow_Precession_Circles",
    "actionShow_Prime_Vertical_Line",
    "actionShow_Quadrature_Line",
    "actionShow_Solar_Equator_Line",
    "actionShow_Solstice_J2000_Points",
    "actionShow_Solstice_Points",
    "actionShow_Stars",
    "actionShow_Stars_Labels",
    "actionShow_Supergalactic_Equator_Line",
    "actionShow_Supergalactic_Grid",
    "actionShow_Supergalactic_Poles",
    "actionShow_Toast_Survey",
    "actionShow_Umbra_Center_Point",
    "actionShow_Umbra_Circle",
    "actionShow_Zenith_Nadir",
    "actionShow_Zodiac",
    "actionSwitch_Equatorial_Mount",
    "actionVertical_Flip"
  ]

  // 启动动画：星空淡出并卸载（核心就绪或用户点击跳过时调用）
  private dismissSplash(): void {
    if (this.splashGone) { return }
    this.isLoading = false
    this.getUIContext().animateTo({ duration: 650, curve: Curve.EaseInOut, onFinish: () => { this.splashGone = true; this.stopTwinkle() } }, () => {
      this.splashOpacity = 0
    })
  }

  // 星空交错闪烁：每 1 秒翻转一次相位，让亮星/暗星交替明暗
  private startTwinkle(): void {
    if (this.twTimer !== 0) { return }
    this.twTimer = setInterval(() => { this.twPhase = !this.twPhase }, 2000)
    // FPS monitor: poll C++ getFPS every 1s for real render frame rate
    this.fpsTimer = setInterval(() => {
      try {
        const r = this.callNative('getFPS', '')
        if (r && r.ok && typeof r.fps === 'number' && r.fps > 0) {
          this.fpsDisplay = Math.round(r.fps)
          // A positive native FPS means Qt has rendered a real frame.  This is
          // an independent readiness signal for devices where the optional
          // sky-culture query does not return during startup.
          this.dismissSplash()
        } else if (r && r.pending) {
          // If pending, try again after a short delay
          setTimeout(() => {
            const r2 = this.callNative('getFPS', '')
            if (r2 && r2.ok && typeof r2.fps === 'number' && r2.fps > 0) {
              this.fpsDisplay = Math.round(r2.fps)
              this.dismissSplash()
            }
          }, 100)
        }
      } catch (e) {
        // Silent error to avoid log spam
      }
    }, 500) as number
  }

  private stopTwinkle(): void {
    if (this.twTimer !== 0) { clearInterval(this.twTimer); this.twTimer = 0 }
    if (this.fpsTimer !== 0) { clearInterval(this.fpsTimer); this.fpsTimer = 0 }
  }

  private foldStatusChanged = (status: display.FoldStatus): void => {
    this.foldStatusValue = status as number
    const halfFolded = this.foldStatusValue === 3 || this.foldStatusValue === 13 || this.foldStatusValue === 21 || this.foldStatusValue === 22 || this.foldStatusValue === 23
    if (halfFolded && (this.foldAngleValue >= 155 || this.foldAngleValue <= 0)) {
      this.hasUsableFoldAngle = false
    }
    this.updateResponsiveLayout('foldStatusChange')
  }

  private foldDisplayModeChanged = (mode: display.FoldDisplayMode): void => {
    this.foldDisplayModeValue = mode as number
    this.updateResponsiveLayout('foldDisplayModeChange')
  }

  private foldAngleChanged = (angles: Array<number>): void => {
    if (angles.length > 0 && Number.isFinite(angles[0])) {
      this.foldAngleValue = this.clamp(angles[0], 0, 180)
      this.hasUsableFoldAngle = this.foldAngleValue > 0 && this.foldAngleValue < 180
      this.updateResponsiveLayout('foldAngleChange')
    }
  }

  private isHalfFoldedStatus(): boolean {
    return this.foldStatusValue === 3 || this.foldStatusValue === 13 || this.foldStatusValue === 21 || this.foldStatusValue === 22 || this.foldStatusValue === 23
  }

  private responsiveFoldAngle(): number {
    if (this.isFoldableDevice && this.isHalfFoldedStatus() && !this.hasUsableFoldAngle) {
      // HALF_FOLD is sufficient to select the observatory layout. 110 degrees
      // is a neutral visual split until the sensor delivers a live value.
      return 110
    }
    return this.clamp(this.foldAngleValue, 0, 180)
  }

  private refreshFoldState(source: string): void {
    try {
      this.isFoldableDevice = display.isFoldable()
      if (this.isFoldableDevice) {
        this.foldStatusValue = display.getFoldStatus() as number
        this.foldDisplayModeValue = display.getFoldDisplayMode() as number
      }
      hilog.info(0x0000, 'StellariumArkUI', 'foldState source=%{public}s foldable=%{public}s status=%{public}s mode=%{public}s angle=%{public}s', source, this.isFoldableDevice.toString(), this.foldStatusValue.toString(), this.foldDisplayModeValue.toString(), this.foldAngleValue.toString())
    } catch (e) {
      this.isFoldableDevice = false
      hilog.warn(0x0000, 'StellariumArkUI', 'foldState unavailable source=%{public}s', source)
    }
  }

  private registerFoldListeners(): void {
    this.refreshFoldState('aboutToAppear')
    try {
      display.on('foldStatusChange', this.foldStatusChanged)
      display.on('foldDisplayModeChange', this.foldDisplayModeChanged)
      display.on('foldAngleChange', this.foldAngleChanged)
    } catch (e) {
      hilog.warn(0x0000, 'StellariumArkUI', 'fold listeners unavailable')
    }
  }

  private unregisterFoldListeners(): void {
    try {
      display.off('foldStatusChange', this.foldStatusChanged)
      display.off('foldDisplayModeChange', this.foldDisplayModeChanged)
      display.off('foldAngleChange', this.foldAngleChanged)
    } catch (e) { }
  }

  private updateResponsiveLayout(source: string): void {
    const width = this.skyWidth > 1 ? this.skyWidth : 1
    const height = this.skyHeight > 1 ? this.skyHeight : 1
    const shortSide = Math.min(width, height)
    const longSide = Math.max(width, height)
    const aspect = shortSide > 0 ? longSide / shortSide : 1
    const halfFolded = this.isHalfFoldedStatus()
    const folded = this.foldStatusValue === 2
    const explicitlyExpanded = this.foldStatusValue === 1 || this.foldStatusValue === 11 || this.foldDisplayModeValue === 1
    // Fold state describes the physical device, not this window. In floating
    // mode API 22 can still report an expanded fold state after the app window
    // has become phone-sized, so the actual content bounds take precedence.
    const compactWindow = shortSide < 520
    const largeFoldCanvas = this.isFoldableDevice && shortSide >= 620 && aspect <= 1.55
    const tabletCanvas = shortSide >= 700 || (shortSide >= 620 && longSide >= 1000 && aspect <= 1.75)
    const angle = this.responsiveFoldAngle()
    const prevMode = this.responsiveLayoutMode
    let nextMode = prevMode

    if (compactWindow) {
      nextMode = 'compact'
    } else if (this.isFoldableDevice && folded && !halfFolded) {
      nextMode = 'compact'
    } else if (this.isFoldableDevice && halfFolded) {
      if (prevMode === 'expanded') {
        nextMode = angle <= 140 ? 'hover' : 'expanded'
      } else if (prevMode === 'hover') {
        if (angle >= 158 && (explicitlyExpanded || largeFoldCanvas || tabletCanvas)) {
          nextMode = 'expanded'
        } else if (angle <= 55) {
          nextMode = 'compact'
        } else {
          nextMode = 'hover'
        }
      } else {
        if (angle >= 158 && (explicitlyExpanded || largeFoldCanvas || tabletCanvas)) {
          nextMode = 'expanded'
        } else if (angle >= 68) {
          nextMode = 'hover'
        } else {
          nextMode = 'compact'
        }
      }
    } else if (!folded && (explicitlyExpanded || largeFoldCanvas || tabletCanvas)) {
      nextMode = 'expanded'
    } else {
      nextMode = 'compact'
    }

    const applyLayout = (): void => {
      this.responsiveLayoutMode = nextMode
      this.isFoldHoverLayout = nextMode === 'hover'
      this.isFoldTabletLayout = this.isFoldableDevice && nextMode === 'expanded' && shortSide < 760
      this.isExpandedLayout = nextMode === 'expanded'
    }
    if (nextMode !== prevMode) {
      try {
        this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, applyLayout)
      } catch (e) {
        applyLayout()
      }
    } else {
      applyLayout()
    }
    hilog.info(0x0000, 'StellariumArkUI', 'layout source=%{public}s w=%{public}s h=%{public}s foldable=%{public}s status=%{public}s displayMode=%{public}s angle=%{public}s uiMode=%{public}s hover=%{public}s foldTablet=%{public}s expanded=%{public}s', source, width.toString(), height.toString(), this.isFoldableDevice.toString(), this.foldStatusValue.toString(), this.foldDisplayModeValue.toString(), angle.toString(), nextMode, this.isFoldHoverLayout.toString(), this.isFoldTabletLayout.toString(), this.isExpandedLayout.toString())
  }

  aboutToAppear(): void {
    const localStorage = this.getUIContext().getSharedLocalStorage()
    if (localStorage) {
      this.createInfo = localStorage.get<WindowNativeNodeCreateInfo>('createInfo')
    }
    this.startPageAfterPrivacyIfNeeded()
  }

  private onPrivacyNativeStartupAllowedChanged(): void {
    this.startPageAfterPrivacyIfNeeded()
  }

  private startPageAfterPrivacyIfNeeded(): void {
    if (!this.privacyNativeStartupAllowed || this.privacyPageStartupStarted) {
      return
    }
    this.privacyPageStartupStarted = true
    const stored = AppStorage.get<string>("observingList")
    if (stored) {
      try {
        this.observingList = JSON.parse(stored) as string[]
      } catch (e) {
        this.observingList = []
      }
    }
    this.loadSearchHistoryFromStorage()
    this.loadBookmarksFromStorage()
    this.registerFoldListeners()
    this.subscribeApplicationLifecycle()
    this.startupBridgeSync()
  }

  // 启动期的命令桥同步（取星文化列表 + 设中文 + 套用保存设置）。
  // 关键：ArkUI 的 setTimeout 重试链在冷启动期对本线程不可靠地不 fire，
  // 所以这里只“发一次”请求，真正重试交给 onAreaChange（布局硬回调，稳定触发）。
  private startupBridgeSync(): void {
    if (this.bridgeSyncStarted) { return }
    this.bridgeSyncStarted = true
    this.callNativeWhenReady("getSkyCultures", "", (r) => {
      if (r.ok === true && Array.isArray(r.items)) {
        this.skyCultures = r.items as string[]
        this.currentSkyCulture = r.current as string
        // On API 22 the early startup retry can be lost before Qt is ready.
        // A successful culture query proves the core is initialized, so apply
        // the persisted app language at this stable point.
        this.callNativeWhenReady('setLanguage', this.selectedLanguage, () => {})
        // Qt 初始化成功，自动关闭启动画面（星空淡出）
        this.dismissSplash()
      }
    })
    this.callNativeWhenReady("getLandscapeList", "", (r) => {
      if (r.ok === true && Array.isArray(r.items)) {
        this.landscapeList = r.items as Array<LandscapeItem>
        this.currentLandscapeId = r.current as string
      }
    })
    this.callNativeWhenReady("getScriptList", "", (r) => {
      if (r.ok === true && Array.isArray(r.items)) {
        this.scriptList = r.items as string[]
      }
    })
    this.callNativeWhenReady("getLoadedModuleNames", "", (r) => {
      if (r.ok === true && Array.isArray(r.items)) {
        this.moduleList = r.items as string[]
      }
    })
    // Sky cultures are fully packaged application content. Plugin management
    // remains developer-only, so it stays hidden in the offline release.
    this.loadSkyCultureList()
    if (!OFFLINE_APPGALLERY_BUILD) {
      this.loadPluginList()
    }
    // 读回引擎当前投影，否则设置页里没有任何一项是高亮的，看起来像“全都没生效”
    this.callNativeWhenReady('getProjectionList', '', (r) => {
      if (r.ok === true && r.current !== undefined) {
        this.currentProjection = r.current as string
      }
    })
    // 初始化距离单位设置
    this.callNativeWhenReady('getConfigString', 'astronomy/flag_use_km_for_distance', (r) => {
      if (r.ok) {
        this.useMetricUnits = r.value === 'true'
      }
    })
    // 初始化星等限制：控制项应显示用户保存的上限，而不是会随缩放变化的动态渲染上限。
    this.callNativeWhenReady('getLimitMagnitude', '', (r) => {
      const resp = r as LimitMagnitudeResponse
      if (resp.ok && resp.customStarMagLimit !== undefined) {
        const v = Number(resp.customStarMagLimit)
        if (!isNaN(v)) { this.starMagLimit = Math.round(v * 10) / 10 }
      }
    })
    // 加载保存的设置
    const settings = AppStorage.get<string>("stellariumSettings")
    if (settings) {
      try {
        const s = JSON.parse(settings) as Record<string, boolean | string>
        if (s.nightMode !== undefined) { this.nightMode = s.nightMode as boolean; this.triggerAction("actionShow_Night_Mode") }
        if (s.equatorialMount !== undefined) { this.equatorialMount = s.equatorialMount as boolean; this.triggerAction("actionSwitch_Equatorial_Mount") }
        // Sensor subscriptions do not survive an Ability restart. Restoring a
        // saved "on" flag here left the UI lit while no listener existed.
        if (s.gyroscopeEnabled !== undefined) {
          this.gyroscopeEnabled = false
          this.gyroscopeStatus = I18n.t('m_gyro_off')
        }
        if (s.gyroscopeSensitivityText !== undefined) { this.gyroscopeSensitivityText = s.gyroscopeSensitivityText as string }
        if (s.selectedLanguage !== undefined) {
          const lang = s.selectedLanguage as string
          if (lang !== this.selectedLanguage) {
            I18n.setLanguage(I18n.fromStellariumCode(lang))
            this.setLanguage(lang)
          }
        }
        if (s.musicEnabled !== undefined) { this.musicEnabled = s.musicEnabled as boolean }
        if (s.useMetricUnits !== undefined) { this.useMetricUnits = s.useMetricUnits as boolean }
      } catch (e) { }
    }
    // 打开应用即播放程序化音乐（用户没关过的前提下）
    if (this.musicEnabled) {
      AudioEngine.getInstance().start()
    }
    I18n.setLanguage(I18n.fromStellariumCode(this.selectedLanguage))
    // 卡在天顶↔天底 默认开启：上下滑到天顶/天底就停（不翻转），且竖直滑动绝不会引起旋转
    this.callNativeWhenReady("setVerticalClamp", "1", (r: StellariumBridgeResponse) => {
      if (r.ok === true) { this.verticalClamp = true }
    })
    // 画面防弯曲 默认开启：最大视场角限制在 100°，不会缩成"一个球"，地平线基本平直
    this.callNativeWhenReady("setFlatHorizon", "1", (r: StellariumBridgeResponse) => {
      if (r.ok === true) { this.flatHorizon = true }
    })
    // 默认显示天顶/天底参考圈（满足“加载时就能看到天顶和天底两个圈”）
    this.callNativeWhenReady("setActionChecked", "actionShow_Zenith_Nadir|1", (r: StellariumBridgeResponse) => {
      if (r.ok === true) { this.zenithNadir = true }
    })
    // 启动时不再自动获取位置（避免首次启动弹出系统定位权限弹窗）
    // 用户点击"自动定位"按钮时才触发定位请求
    // this.callNativeWhenReady("getState", "", () => {
    //   this.triggerAutoLocate()
    // })
    if (this.SELFTEST) { this.selfTestAllActions() }
  }

  // 启动期自动定位（只触发一次）。GPS 可用时更新为真实位置，不可用时回退到已保存/默认位置。
  private triggerAutoLocate(): void {
    if (this.autoLocateStarted) { return }
    this.autoLocateStarted = true
    hilog.info(0x0000, 'StellariumArkUI', 'auto-locate on startup -> useDeviceLocation()')
    this.useDeviceLocation()
  }

  aboutToDisappear(): void {
    // 保存设置
    AppStorage.setOrCreate("stellariumSettings", JSON.stringify({
      nightMode: this.nightMode,
      equatorialMount: this.equatorialMount,
      gyroscopeEnabled: this.gyroscopeEnabled,
      gyroscopeSensitivityText: this.gyroscopeSensitivityText,
      selectedLanguage: this.selectedLanguage,
      useMetricUnits: this.useMetricUnits,
      musicEnabled: this.musicEnabled
    }))
    this.stopSkyInertia()
    this.stopGyroscope(false)
    this.stopDetailAutoRefresh()
    this.stopTimePanelTimers()
    this.unregisterFoldListeners()
    this.unsubscribeApplicationLifecycle()
  }

  private handleApplicationLifecycle = (foreground: boolean): void => {
    this.applicationInForeground = foreground
    if (foreground) {
      if (this.foregroundRefreshPaused) {
        this.foregroundRefreshPaused = false
        if (this.activePanel === 'time' && this.panelVisible) {
          this.loadTimeExtras()
          this.timePanelTimer = setInterval(() => { this.refreshSimTimeLight() }, 125)
          this.timePanelFullTimer = setInterval(() => {
            this.refreshState()
            this.loadTimeExtras()
          }, 3000)
        }
        if (this.selectedStatus === 'Selected' && ((this.activePanel === 'object' && this.panelVisible) || this.infoWinVisible)) {
          this.startDetailAutoRefresh()
        }
      }
      if (this.musicEnabled) {
        void AudioEngine.getInstance().start()
      }
      if (this.gyroPausedForBackground) {
        this.gyroPausedForBackground = false
        this.startGyroscope()
        hilog.info(0x0000, 'StellariumArkUI', 'foreground: gyroscope subscriptions restored')
      }
      return
    }

    // This app declares no background task. Stop ArkUI polling and audio
    // rendering as soon as the Ability leaves the foreground.
    this.foregroundRefreshPaused = this.timePanelTimer !== 0 || this.detailTimer !== 0
    this.stopTimePanelTimers()
    this.stopDetailAutoRefresh()
    this.stopSkyInertia()
    void AudioEngine.getInstance().stop()
    if (this.gyroscopeEnabled) {
      this.gyroPausedForBackground = true
      this.stopGyroscope(false)
      hilog.info(0x0000, 'StellariumArkUI', 'background: gyroscope subscriptions released')
    }
  }

  private subscribeApplicationLifecycle(): void {
    setLifecycleListener(this.handleApplicationLifecycle)
  }

  private unsubscribeApplicationLifecycle(): void {
    setLifecycleListener(undefined)
  }

  /** 停掉时间面板的高频/低频两个刷新定时器 */
  private stopTimePanelTimers(): void {
    if (this.timePanelTimer !== 0) {
      clearInterval(this.timePanelTimer)
      this.timePanelTimer = 0
    }
    if (this.timePanelFullTimer !== 0) {
      clearInterval(this.timePanelFullTimer)
      this.timePanelFullTimer = 0
    }
  }

  private setPanel(panel: string): void {
    // Script playback remains hidden in the offline candidate until its
    // resource lifecycle is ready. AstroCalc is self-contained and offline.
    if (OFFLINE_APPGALLERY_BUILD && panel === 'scripts') {
      return
    }
    hilog.info(0x0000, 'StellariumArkUI', 'setPanel ' + panel)
    const nextVisible = this.activePanel === panel ? !this.panelVisible : true
    // The selected-target navigator owns the projection centre while a card is
    // visible. Do not reset it from this animation: that command races the
    // target navigator and used to pull a locked object straight back below
    // the panel.
    this.getUIContext().animateTo({ duration: 320, curve: curves.springMotion(0.45, 0.88) }, () => {
      this.activePanel = panel
      this.panelVisible = nextVisible
      this.panelContentKey++
    })
    // 打开「位置」面板时自动刷新今晚天象（用户要求每次进入都自动刷新）
    if (panel === 'place' && nextVisible) {
      this.refreshTonight()
    }
    if (nextVisible) {
      this.resetPanelIdle()
      this.resetSidebarAutoCollapse()
      if (panel === 'search' && this.categoryObjects.length === 0) {
        this.loadCategoryObjects(this.searchCategory)
      }
    }
    this.scheduleSelectedObjectForUiChange(380)
    // 时间面板：打开时启动每秒刷新（让"时间"字段实时走动），关闭或切到别的面板时停掉
    if (panel === 'time' && nextVisible) {
      // 恒星时 / 夜视 / 折射：打开面板时取一次真实值
      this.loadTimeExtras()
      if (this.timePanelTimer === 0) {
        // 高频（125ms）只刷时间/速率这两个字段，读秒才会像水一样连续流动；
        // 早期用 1000ms + refreshState 全量刷新，导致加速时 2s→11s 跳跃，
        // 且每秒一次几十个 @State 的全量重排会打断星图拖动手势（表现为"打开面板后拖动变生硬"）。
        this.timePanelTimer = setInterval(() => { this.refreshSimTimeLight() }, 125)
        // 全量状态低频兜底（3s 一次），同步图层开关/坐标/FOV 等其余字段
        if (this.timePanelFullTimer === 0) {
          this.timePanelFullTimer = setInterval(() => {
            this.refreshState()
            this.loadTimeExtras()
          }, 3000)
        }
      }
    } else {
      this.stopTimePanelTimers()
    }
    if (panel === 'object') {
      this.refreshSelectedObject()
    } else if (panel === 'astro') {
      this.loadAstroTab(this.astroTab)
    } else if (panel === 'layers' || panel === 'time' || panel === 'settings') {
      this.refreshState()
    } else if (panel === 'place') {
      this.refreshState()
      this.loadPlanetList()
      this.loadObserverInfo()
      this.loadSavedLocations()
    } else if (panel === 'catalogs' && !OFFLINE_APPGALLERY_BUILD) {
      if (this.catalogList.length === 0) this.loadStarCatalogs()
    } else if (panel === 'bookmarks') {
      this.loadBookmarks()
    } else if (panel === 'oculars') {
      this.loadOculars()
    } else if (panel === 'satellites') {
      this.ensurePluginLoaded('Satellites', () => { this.loadSatellites() })
    } else if (panel === 'meteorshowers') {
      this.ensurePluginLoaded('MeteorShowers', () => { this.loadMeteorShowers() })
    } else if (panel === 'observing') {
      // observing list is state-driven, no async load needed
    } else if (panel === 'audio') {
      // audio panel is state-driven
    } else if (panel === 'help') {
      this.loadAboutInfo()
    } else if (panel === 'scripts') {
      this.loadScriptList()
      this.loadRecordings()
      this.loadVideoRecordingState()
    }
  }

  private closePanel(force: boolean = false): void {
    if (this.uiLocked && !force) {
      return
    }
    // 关面板时停掉时间面板定时器，避免后台空转
    this.stopTimePanelTimers()
    if (this.activePanel === 'search') {
      this.graphTargetPickerActive = false
      this.rtsTargetPickerActive = false
      this.ephemerisTargetPickerActive = false
    }
    this.getUIContext().animateTo({ duration: 300, curve: curves.springMotion(0.45, 0.9) }, () => {
      this.panelVisible = false
    })
    this.scheduleSelectedObjectForUiChange(360)
  }

  private runOnTouchUp(event: TouchEvent, action: () => void): void {
    if (event.type === TouchType.Up) {
      action()
    }
  }

  private callNative(name: string, payload: string = ''): StellariumBridgeResponse {
    try {
      const r = JSON.parse(command(name, payload)) as StellariumBridgeResponse
      // 录制：仅在录制开启、非回放、且命令可录制时记录，并对短时重试用去重窗口避免重复。
      if (this.recording && !this.replaying && this.isRecordable(name)) {
        const key = name + '|' + payload
        const now = Date.now()
        if (key !== this.lastRecordKey || (now - this.lastRecordTime) > 400) {
          this.recordBuffer.push({ c: name, p: payload })
          this.recordCount = this.recordBuffer.length
          this.lastRecordKey = key
          this.lastRecordTime = now
        }
      }
      return r
    } catch (err) {
      return { ok: false, error: 'bridge parse failed' }
    }
  }

  // Fire-and-forget: 调用 C++ 桥但不解析返回的 JSON，减少拖动时的 GC 压力。
  // 用于 dragView / zoomBy / panBy 等不需要返回值的连续命令。
  private callNativeFire(name: string, payload: string = ''): void {
    try {
      command(name, payload)
    } catch (err) {
      // 忽略：拖动期间不需要错误处理
    }
  }

  // 过滤掉只读查询与连续视图命令，以及录制自身的管理命令。
  private isRecordable(name: string): boolean {
    if (name.startsWith('get') || name.startsWith('list') || name.startsWith('is') || name.startsWith('selftest'))
      return false
    const skip = ['dragView', 'panBy', 'zoomBy', 'saveRecording', 'loadRecording', 'listRecordings', 'deleteRecording', 'startRecording', 'stopRecording']
    return !skip.includes(name)
  }

  // Retry a native command until the Stellarium core is initialized.
  // At startup the ArkUI thread may call the bridge before Qt has finished
  // bootstrapping; those calls return ok:false and are retried on a short
  // backoff instead of crashing the process.
  private callNativeWhenReady(name: string, payload: string = '', onOk?: (r: StellariumBridgeResponse) => void, attempt: number = 0, intervalMs: number = 200, maxAttempts: number = 60, onFailure?: (r: StellariumBridgeResponse) => void): void {
    const r = this.callNative(name, payload)
    if (r.ok === true) {
      if (onOk) onOk(r)
      return
    }
    if (attempt < maxAttempts) {
      setTimeout(() => this.callNativeWhenReady(name, payload, onOk, attempt + 1, intervalMs, maxAttempts, onFailure), intervalMs)
    } else if (onFailure) {
      onFailure(r)
    }
  }

  // Interactive commands (tap-select, search, get-info, move-to) run on the
  // OHOS render pump one frame later and are delivered via a consume-on-read
  // store on the C++ side, so the first call returns {pending}. Poll fast
  // (50ms x 40 = 2s) so a single tap/search resolves without a visible delay
  // and WITHOUT blocking the render thread. onOk receives the FRESH result.
  private callInteractive(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void): void {
    this.callNativeWhenReady(name, payload, onOk, 0, 100, 15, onFailure)
  }

  private callLongRunningInteractive(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, onProgress?: (r: StellariumBridgeResponse) => void, maxAttempts: number = 240): void {
    let attempt = 0
    const poll = (): void => {
      const response = this.callNative(name, payload)
      if (response.ok === true) {
        onOk(response)
        return
      }
      if (response.pending === true && attempt < maxAttempts) {
        if (onProgress) onProgress(response)
        ++attempt
        setTimeout(poll, 100)
        return
      }
      if (onFailure) onFailure(response)
    }
    poll()
  }

  // ===== 星表下载（C++ 桥：getStarCatalogs / downloadStarCatalog / getStarCatalogStatus）=====
  private loadStarCatalogs(): void {
    this.catalogLoading = true
    this.callNativeWhenReady('getStarCatalogs', '', (r: StellariumBridgeResponse) => {
      const resp = r as StarCatalogsResponse
      const list = resp.catalogs ?? []
      this.catalogList = list.map((c: StarCatalogRaw) => ({
        id: c.id ?? '',
        name: c.name ?? (c.id ?? I18n.t('catalog_fallback')),
        size: c.size ?? '',
        key: c.key ?? '',
        fileName: c.fileName ?? '',
        url: c.url ?? '',
        html: c.html ?? '',
        checked: c.checked === true || c.checked === 'true' || c.checked === 1,
      }))
      this.catalogLoading = false
    })
  }

  private startCatalogDownload(id: string): void {
    if (this.catalogBusy) {
      this.flashHint(I18n.t('msg_catalog_downloading'))
      return
    }
    this.catalogBusy = true
    this.catalogDownloadingId = id
    this.catalogMsg = '开始下载 ' + id + ' …'
    this.flashHint('开始下载 ' + id)
    const r = this.callNative('downloadStarCatalog', id)
    if (!r || !r.ok) {
      this.catalogBusy = false
      this.catalogDownloadingId = ''
      this.catalogMsg = '下载启动失败'
      this.flashHint(I18n.t('msg_download_failed'))
      return
    }
    this.pollCatalogStatus(id)
  }

  private pollCatalogStatus(id: string): void {
    const timer = setInterval(() => {
      const r = this.callNative('getStarCatalogStatus', '') as StarCatalogStatusResponse
      if (!r || !r.ok) {
        clearInterval(timer)
        this.catalogBusy = false
        this.catalogDownloadingId = ''
        return
      }
      const state = r.state ?? 'downloading'
      const bytes = r.bytes ?? 0
      if (state === 'done') {
        clearInterval(timer)
        const md5ok = r.md5ok === true
        this.catalogMsg = md5ok ? ('「' + id + '」下载完成并已加载') : ('「' + id + '」下载完成，校验未通过')
        this.flashHint(this.catalogMsg)
        this.catalogBusy = false
        this.catalogDownloadingId = ''
        this.loadStarCatalogs()
      } else if (state === 'error') {
        clearInterval(timer)
        const err = r.error ?? '未知错误'
        this.catalogMsg = '下载失败：' + err
        this.flashHint('下载失败：' + err)
        this.catalogBusy = false
        this.catalogDownloadingId = ''
      } else {
        const mb = (bytes / (1024 * 1024)).toFixed(1)
        this.catalogMsg = '下载中 ' + id + '：' + mb + ' MB'
      }
    }, 600)
  }

  // ===== 书签本地持久化（@ohos.data.preferences）=====
  private async saveBookmarksToStorage(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, BOOKMARK_STORE)
      const jsonStr: string = JSON.stringify(this.bookmarkList)
      await store.put('bookmarks', jsonStr)
      await store.flush()
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'save bookmarks failed: %{public}s', String(e))
    }
  }

  private async loadBookmarksFromStorage(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, BOOKMARK_STORE)
      const jsonStr: string = (await store.get('bookmarks', '[]')) as string
      const parsed: BookmarkItem[] = JSON.parse(jsonStr)
      if (parsed.length > 0) {
        this.bookmarkList = parsed
      }
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'load bookmarks failed: %{public}s', String(e))
    }
  }

  private async saveSearchHistoryToStorage(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, SEARCH_HISTORY_STORE)
      const jsonStr: string = JSON.stringify(this.searchHistory)
      await store.put('history', jsonStr)
      await store.flush()
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'save search history failed: %{public}s', String(e))
    }
  }

  private async loadSearchHistoryFromStorage(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, SEARCH_HISTORY_STORE)
      const jsonStr: string = (await store.get('history', '[]')) as string
      const parsed: string[] = JSON.parse(jsonStr)
      if (parsed.length > 0) {
        this.searchHistory = parsed.slice(0, 20)
      }
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'load search history failed: %{public}s', String(e))
    }
  }

  // ===== 书签（C++ 桥：addBookmark / getBookmarks / deleteBookmark / gotoBookmark）=====
  private loadBookmarks(): void {
    this.bookmarkLoading = true
    this.callNativeWhenReady('getBookmarks', '', (r: StellariumBridgeResponse) => {
      const resp = r as BookmarksResponse
      const list = resp.items ?? []
      this.bookmarkList = list.map((b: BookmarkRaw) => ({
        id: b.id ?? '',
        name: b.name ?? I18n.t('bookmark_fallback'),
        fov: b.fov ?? 60,
        object: b.object ?? '',
      }))
      this.bookmarkLoading = false
      this.saveBookmarksToStorage()
    })
  }

  // 保存当前视图为书签。C++ 端读取当前 J2000 视方向 + 视场 + 选中天体，名称由 payload 传入。
  private addCurrentBookmark(): void {
    const name = this.newBookmarkName.trim()
    this.callNativeWhenReady('addBookmark', name, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.newBookmarkName = ''
        this.flashHint(I18n.t('msg_bookmark_saved'))
        this.loadBookmarks()
      } else {
        this.flashHint(I18n.t('msg_bookmark_save_failed'))
      }
    })
  }

  private gotoBookmark(id: string): void {
    this.callInteractive('gotoBookmark', id, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.flashHint(I18n.t('msg_navigated'))
      } else {
        this.flashHint(I18n.t('msg_navigation_failed'))
      }
    })
  }

  private deleteBookmark(id: string): void {
    this.callNativeWhenReady('deleteBookmark', id, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.flashHint(I18n.t('msg_bookmark_deleted'))
        this.loadBookmarks()
      }
    })
  }

  // ===== 脚本录制 / 回放（#39）=====
  private startRecording(): void {
    this.recording = true
    this.recordBuffer = []
    this.recordCount = 0
    this.recordMsg = '录制中…'
    this.lastRecordKey = ''
    this.lastRecordTime = 0
    this.flashHint('开始录制：接下来的操作会被记录')
  }

  private stopRecording(): void {
    this.recording = false
    this.recordCount = this.recordBuffer.length
    this.recordMsg = this.recordCount > 0 ? '已停止，可保存' : '已停止（没有可保存的操作）'
    this.flashHint(this.recordMsg)
  }

  private saveCurrentRecording(): void {
    if (this.recordBuffer.length === 0) {
      this.recordMsg = '没有可保存的操作，请先开始录制'
      this.flashHint(this.recordMsg)
      return
    }
    const safeName = this.recordName.trim().replace(/\|/g, '_').replace(/\n/g, ' ')
    const payload = safeName + '|' + JSON.stringify(this.recordBuffer)
    this.callInteractive('saveRecording', payload, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.recordMsg = '已保存：' + (r.name ?? this.recordName)
        this.flashHint(this.recordMsg)
        this.recordBuffer = []
        this.recordCount = 0
        this.recordName = ''
        this.loadRecordings()
      } else {
        this.recordMsg = '保存失败：' + (r.error ?? '未知错误')
        this.flashHint(this.recordMsg)
      }
    })
  }

  private loadRecordings(): void {
    this.callInteractive('listRecordings', '', (r: StellariumBridgeResponse) => {
      const resp = r as RecordingsResponse
      this.recordings = resp.items ?? []
    })
  }

  private playRecording(file: string): void {
    this.callInteractive('loadRecording', file, (r: StellariumBridgeResponse) => {
      const resp = r as RecordingDetailResponse
      const cmds = resp.commands ?? []
      if (cmds.length === 0) {
        this.flashHint(I18n.t('msg_recording_empty'))
        return
      }
      this.replaying = true
      this.flashHint('正在回放 ' + cmds.length + ' 条命令…')
      // 逐条重发命令；callNativeWhenReady 会等核心就绪后执行，避免启动时序问题。
      for (const cmd of cmds) {
        this.callNativeWhenReady(cmd.c, cmd.p)
      }
      // 短暂延时后解除回放标记，避免误录回放命令。
      setTimeout(() => { this.replaying = false }, 600 + cmds.length * 30)
    })
  }

  private deleteRecording(file: string): void {
    this.callInteractive('deleteRecording', file, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.flashHint(I18n.t('msg_recording_deleted'))
        this.loadRecordings()
      } else {
        this.flashHint(I18n.t('msg_delete_failed'))
      }
    })
  }

  private pauseScript(): void {
    this.callInteractive('pauseScript', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.flashHint('脚本已暂停')
      } else {
        this.flashHint('暂停脚本失败')
      }
    })
  }

  private resumeScript(): void {
    this.callInteractive('resumeScript', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.flashHint('脚本已继续')
      } else {
        this.flashHint('继续脚本失败')
      }
    })
  }

  private loadScriptList(): void {
    this.callInteractive('getScriptList', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && Array.isArray(r.items)) {
        this.scriptList = r.items as string[]
      }
    })
  }

  private loadRecordingByName(file: string, name: string): void {
    this.callInteractive('loadRecording', file, (r: StellariumBridgeResponse) => {
      const resp = r as RecordingDetailResponse
      const cmds = resp.commands ?? []
      if (r.ok === true) {
        this.flashHint('已加载录制：' + name + '（' + cmds.length + ' 条命令）')
      } else {
        this.flashHint('加载录制失败')
      }
    })
  }

  // ===== 视频帧序列录制（#40，基础 SDK 缺视频编码器，先输出帧图）=====
  private startVideoRecording(): void {
    const fps = parseInt(this.videoFps, 10) || 1
    const duration = parseInt(this.videoDuration, 10) || 5
    this.callInteractive('startVideoRecording', fps + '|' + duration, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.videoRecording = true
        this.videoDir = r.dir as string ?? ''
        this.videoFrameCount = 0
        this.videoMaxFrames = r.maxFrames as number ?? 0
        this.flashHint('开始录制视频帧序列：' + fps + ' fps × ' + duration + ' s')
      } else {
        this.flashHint('开始录制失败：' + (r.error ?? '未知错误'))
      }
    })
  }

  private stopVideoRecording(): void {
    this.callInteractive('stopVideoRecording', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.videoRecording = false
        this.videoFrameCount = (r.diskFrames as number) ?? (r.frameCount as number) ?? 0
        this.videoDir = r.dir as string ?? ''
        this.flashHint('已停止，共 ' + this.videoFrameCount + ' 帧已保存')
      } else {
        this.flashHint('停止录制失败')
      }
    })
  }

  private loadVideoRecordingState(): void {
    this.callInteractive('getVideoRecordingState', '', (r: StellariumBridgeResponse) => {
      this.videoRecording = r.recording === true
      this.videoDir = r.dir as string ?? ''
      this.videoFrameCount = r.frameCount as number ?? 0
      this.videoMaxFrames = r.maxFrames as number ?? 0
    })
  }

  // ===== 望远镜/目镜配置（Oculars 插件桥）=====
  private loadOculars(): void {
    this.callNativeWhenReady('getOculars', '', (r: StellariumBridgeResponse) => {
      const resp = r as OcularsResponse
      const o = resp.oculars
      if (!o) { return }
      this.ocularMode = o.ocularMode
      this.telradOn = o.telrad
      this.crosshairsOn = o.crosshairs
      this.ccdOn = o.ccd
      this.ocularNames = o.ocularNames
      this.telescopeNames = o.telescopeNames
      this.lensNames = o.lensNames
      this.ccdNames = o.ccdNames
      this.ocularIndex = o.ocularIndex
      this.telescopeIndex = o.telescopeIndex
      this.lensIndex = o.lensIndex
      this.ccdIndex = o.ccdIndex
    })
  }

  private setOcularMode(v: boolean): void {
    this.ocularMode = v
    this.callNativeWhenReady('setOcularMode', v ? '1' : '0', () => { this.loadOculars() })
  }
  private setTelrad(v: boolean): void {
    this.telradOn = v
    this.callNativeWhenReady('setTelrad', v ? '1' : '0', () => { this.loadOculars() })
  }
  private setCrosshairs(v: boolean): void {
    this.crosshairsOn = v
    this.callNativeWhenReady('setCrosshairs', v ? '1' : '0', () => { this.loadOculars() })
  }
  private setCCD(v: boolean): void {
    this.ccdOn = v
    this.callNativeWhenReady('setCCD', v ? '1' : '0', () => { this.loadOculars() })
  }
  private cycleOcular(kind: string, dir: string): void {
    this.callNativeWhenReady('cycle' + kind, dir, () => { this.loadOculars() })
  }
  private ocularSelInfo(kind: string): OcularSelInfo {
    const info = new OcularSelInfo()
    let names: string[] = []
    let idx: number = -1
    if (kind == 'Ocular') { names = this.ocularNames; idx = this.ocularIndex }
    else if (kind == 'Telescope') { names = this.telescopeNames; idx = this.telescopeIndex }
    else if (kind == 'Lens') { names = this.lensNames; idx = this.lensIndex }
    else { names = this.ccdNames; idx = this.ccdIndex }
    if (idx >= 0 && idx < names.length) { info.name = names[idx] }
    else { info.name = '（无）' }
    info.countText = (idx < 0 ? '—' : (idx + 1).toString()) + ' / ' + names.length.toString()
    return info
  }

  // ===== 卫星（Satellites 插件桥）=====
  private loadSatellites(): void {
    this.callNativeWhenReady('getSatellites', '', (r: StellariumBridgeResponse) => {
      const resp = r as SatellitesResponse
      const s = resp.satellites
      if (!s) { return }
      this.satGroups = s.groups
      this.satLabels = s.labels
      this.satOrbitLines = s.orbitLines
      this.satHints = s.hints
      this.satIconicMode = s.iconicMode
      this.satHideInvisible = s.hideInvisible
      this.satCount = s.count
    })
  }
  private setSatelliteFlag(name: string, v: boolean): void {
    if (name == 'labels') { this.satLabels = v }
    else if (name == 'orbitLines') { this.satOrbitLines = v }
    else if (name == 'hints') { this.satHints = v }
    else if (name == 'iconicMode') { this.satIconicMode = v }
    else if (name == 'hideInvisible') { this.satHideInvisible = v }
    this.callNativeWhenReady('setSatellitesFlag', name + ':' + (v ? '1' : '0'), () => { this.loadSatellites() })
  }

  // 确保插件已加载，未加载时先 loadPlugin 再回调
  private ensurePluginLoaded(pluginName: string, callback: () => void): void {
    this.callNativeWhenReady('getPluginList', '', (r: StellariumBridgeResponse) => {
      const items = r.items as string[] | undefined
      if (items && items.indexOf(pluginName) >= 0) {
        callback()
      } else {
        hilog.info(0x0000, 'StellariumArkUI', 'Auto-loading plugin: ' + pluginName)
        this.callNativeWhenReady('loadPlugin', pluginName, () => {
          callback()
        })
      }
    })
  }

  // ===== 流星雨（MeteorShowers 插件桥）=====
  private loadMeteorShowers(): void {
    this.callNativeWhenReady('getMeteorShowers', '', (r: StellariumBridgeResponse) => {
      const resp = r as MeteorShowersResponse
      const m = resp.meteorShowers
      if (!m) { return }
      this.msEnabled = m.enabled
      this.msLabels = m.labels
      this.msActiveOnly = m.activeOnly
      this.msMarker = m.marker
      // Parse active shower list
      if (resp.showerList && resp.showerList.length > 0) {
        this.msShowerList = resp.showerList.map((s) => ({
          name: s.name ?? '',
          englishName: s.englishName ?? '',
          zhr: s.zhr ?? 0,
          status: s.status ?? '',
          speed: s.speed ?? 0,
          popIdx: s.popIdx ?? 0,
          parent: s.parent ?? '',
          peakDate: s.peakDate ?? '',
          activeStart: s.activeStart ?? '',
          activeEnd: s.activeEnd ?? ''
        }))
      } else {
        this.msShowerList = []
      }
    })
  }
  private setMeteorShowersFlag(name: string, v: boolean): void {
    if (name == 'enabled') { this.msEnabled = v }
    else if (name == 'labels') { this.msLabels = v }
    else if (name == 'activeOnly') { this.msActiveOnly = v }
    else if (name == 'marker') { this.msMarker = v }
    this.callNativeWhenReady('setMeteorShowersFlag', name + ':' + (v ? '1' : '0'), () => { this.loadMeteorShowers() })
  }

  // ===== 帮助面板：关于 / 日志 / 配置导入导出 =====
  private loadAboutInfo(): void {
    this.callNativeWhenReady('getAboutInfo', '', (r: StellariumBridgeResponse) => {
      const resp = r as AboutResponse
      this.aboutVersion = resp.version ?? ''
      this.aboutQt = resp.qtVersion ?? ''
      this.aboutUserDir = resp.userDir ?? ''
      this.aboutConfigFile = resp.configFile ?? ''
    })
  }

  private loadLog(): void {
    this.callNativeWhenReady('getLog', '6000', (r: StellariumBridgeResponse) => {
      const resp = r as LogResponse
      this.logText = resp.log ?? ''
      this.logVisible = true
    })
  }

  private exportConfig(): void {
    this.callNativeWhenReady('exportConfig', '', (r: StellariumBridgeResponse) => {
      const resp = r as ExportConfigResponse
      this.configExportText = resp.content ?? ''
      this.configExportVisible = true
      this.flashHint('已导出配置（' + this.configExportText.length + ' 字符）')
    })
  }

  private importConfig(): void {
    const text = this.configImportText.trim()
    if (text.length === 0) {
      this.flashHint(I18n.t('msg_paste_config_first'))
      return
    }
    this.configImportMsg = '正在导入…'
    this.callNativeWhenReady('importConfig', text, (r: StellariumBridgeResponse) => {
      const resp = r as ImportConfigResponse
      if (resp.ok === true) {
        this.configImportText = ''
        this.configImportMsg = '已导入 ' + (resp.applied ?? 0) + ' 项配置'
        this.flashHint(this.configImportMsg)
      } else {
        this.configImportMsg = '导入失败：' + (resp.error ?? '未知错误')
      }
    })
  }

  // ===== 朗读 / 语音播报 =====
  // 说明：当前构建基于 OpenHarmony 基础 SDK（API 24），其 kit 列表不含
  // @kit.CoreSpeechKit（语音合成仅存在于华为 HarmonyOS 的 HMS SDK），因此
  // 无法在此环境做真正的 TTS 音频播报。这里保留 C++ 侧生成的"可读中文描述"
  // （getObjectSpokenText 命令），点按按钮即在面板中显示该文本，验证命令通道，
  // 待切换到含 CoreSpeechKit 的 SDK 后即可接真实语音合成。
  private speakSelectedObject(): void {
    this.callNativeWhenReady('getObjectSpokenText', '', (r: StellariumBridgeResponse) => {
      const resp = r as SpokenTextResponse
      if (resp.ok !== true || !resp.text) {
        this.flashHint(I18n.t('msg_no_selection_for_tts'))
        return
      }
      this.speechStatus = resp.text
      this.flashHint('已生成朗读文本（当前 SDK 未集成语音合成）')
    })
  }

  private refreshState(): void {
    this.callInteractive('getState', '', (result) => {
    this.stars = result.actionShow_Stars === true
    this.planets = result.actionShow_Planets === true
    this.planetOrbits = result.actionShow_Planets_Orbits === true
    this.planetHints = result.actionShow_Planets_Hints === true
    this.nebulae = result.actionShow_Nebulas === true
    this.milkyWay = result.actionShow_MilkyWay === true
    this.ground = result.actionShow_Ground === true
    this.constellationLines = result.actionShow_Constellation_Lines === true
    this.constellationLabels = result.actionShow_Constellation_Labels === true
    this.constellationBoundaries = result.actionShow_Constellation_Boundaries === true
    this.constellationArt = result.actionShow_Constellation_Art === true
    this.atmosphere = result.actionShow_Atmosphere === true
    this.cardinalPoints = result.actionShow_Cardinal_Points === true
    this.azimuthGrid = result.actionShow_Azimuthal_Grid === true
    this.equatorialGrid = result.actionShow_Equatorial_Grid === true
    this.equatorialJ2000Grid = result.actionShow_Equatorial_J2000_Grid === true
    this.eclipticGrid = result.actionShow_Ecliptic_Grid === true
    this.meridianLine = result.actionShow_Meridian_Line === true
    this.horizonLine = result.actionShow_Horizon_Line === true
    this.planetLabels = result.actionShow_Planets_Labels === true
    this.starLabels = result.actionShow_Stars_Labels === true
    this.dsoLabels = result.dsoLabels === true
    this.dsoTextures = result.actionShow_DSO_Textures === true
    this.enlargePlanets = result.actionShow_Planets_EnlargePlanets === true
    this.enlargeSun = result.actionShow_Planets_EnlargeSun === true
    this.minorBodyMarkers = result.actionShow_Planets_ShowMinorBodyMarkers === true
    this.planetNomenclature = result.actionShow_Planets_Nomenclature === true
    this.fogEffect = result.actionShow_Fog === true
    this.meteors = result.meteors === true
    this.autoZoomResets = result.autoZoomResets === true
    // The native Stellarium property is authoritative. The QAction is not
    // guaranteed to update when the time-panel uses the direct bridge command.
    if (result.nightMode !== undefined) {
      this.nightMode = result.nightMode === true
      this.nightModeOn = this.nightMode
    } else if (result.actionShow_Night_Mode !== undefined) {
      this.nightMode = result.actionShow_Night_Mode === true
      this.nightModeOn = this.nightMode
    }
    this.flipHoriz = result.actionHorizontal_Flip === true
    this.flipVert = result.actionVertical_Flip === true
    if (result.timeRate !== undefined) {
      this.syncTimeRateState(result.timeRate as number)
    }
    if (result.timeText !== undefined) {
      this.observationTimeText = this.formatObservationTime(result.timeText)
      // 顺便校准 UTC 偏移（timeText 已含观测地偏移，jd 是纯 UTC；差值即偏移小时数）
      // 供轻量刷新 refreshSimTimeLight 使用，避免每次都跑全量 getState
      if (result.jd !== undefined) {
        const localMs = Date.parse(result.timeText.endsWith('Z') ? result.timeText : result.timeText + 'Z')
        const utcMs = ((result.jd as number) - 2440587.5) * 86400000
        if (!Number.isNaN(localMs)) {
          this.utcOffsetHours = Math.round((localMs - utcMs) / 3600000 * 4) / 4 // 取到一刻钟精度
        }
      }
    }
    // 只有当原生确实返回了观测者经纬度时，才用原生值刷新头部位置字段，
    // 否则保留 setLocation 已应用到头部的值（避免被 planetName 等字段清成“未命名”或空值）。
    if (result.latitude !== undefined && result.longitude !== undefined) {
      this.coordinateText = this.formatDegrees(result.latitude, 'N', 'S') + ' / ' + this.formatDegrees(result.longitude, 'E', 'W')
      if (result.locationName !== undefined && result.locationName.length > 0) {
        const planetName = result.planetName && result.planetName.length > 0 ? result.planetName : 'Earth'
        this.locationText = this.locationDisplayName(result.locationName) + ' · ' + this.planetZh(planetName)
      }
      if (result.altitude !== undefined) {
        this.altitudeText = result.altitude.toFixed(0) + ' m'
      }
      if (result.planetName !== undefined && result.planetName.length > 0) {
        this.observerPlanet = result.planetName
      }
    }
    if (result.fov !== undefined) {
      this.fovText = result.fov.toFixed(1) + '°'
      this.fovSliderValue = Math.round(result.fov)
      this.currentFovText = result.fov.toFixed(1) + '°'
    }
    if (result.tracking !== undefined) {
      this.trackingText = result.tracking ? 'On' : 'Off'
    }
    })
  }

  private setLayer(actionId: string, enabled: boolean): void {
    hilog.info(0x0000, 'StellariumArkUI', 'setLayer send %{public}s|%{public}s', actionId, enabled ? '1' : '0')
    this.callInteractive('setActionChecked', actionId + '|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'setLayer %{public}s ok=%{public}s err=%{public}s', actionId, r.ok === true ? '1' : '0', r.error ?? '')
      this.refreshState()
      // 夜间模式和赤道仪模式切换时立即持久化，避免应用被杀死后丢失
      if (actionId === 'actionShow_Night_Mode') { this.persistNightMode() }
      if (actionId === 'actionSwitch_Equatorial_Mount') { this.persistEquatorialMount() }
    })
  }

  // Routed bridge flag: calls a named bridge command (e.g. setMeteors) with "1"/"0"
  private setBridgeFlag(cmd: string, enabled: boolean): void {
    hilog.info(0x0000, 'StellariumArkUI', 'setBridgeFlag send %{public}s|%{public}s', cmd, enabled ? '1' : '0')
    // 同步本地 @State：否则面板关闭重开后 Toggle 会显示旧值，再点一次就把状态发反了
    this.syncBridgeFlagState(cmd, enabled)
    this.callInteractive(cmd, enabled ? '1' : '0', (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'setBridgeFlag %{public}s ok=%{public}s err=%{public}s', cmd, r.ok === true ? '1' : '0', r.error ?? '')
      this.refreshState()
    })
  }

  // 把 cmd 型开关的最新值写回对应的本地 @State，保证 Toggle 重建时显示正确
  private syncBridgeFlagState(cmd: string, enabled: boolean): void {
    if (cmd === 'setViewLock') { this.viewLock = enabled }
    else if (cmd === 'setVerticalClamp') { this.verticalClamp = enabled }
    else if (cmd === 'setFlatHorizon') { this.flatHorizon = enabled }
    else if (cmd === 'setMeteors') { this.meteors = enabled }
    else if (cmd === 'setDsoLabels') { this.dsoLabels = enabled }
    else if (cmd === 'setAutoZoomResets') { this.autoZoomResets = enabled }
  }

  private adjustTime(hours: number): void {
    this.callInteractive('advanceTime', hours.toString(), (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'adjustTime %{public}d ok=%{public}s', hours, r.ok === true ? '1' : '0')
      this.refreshState()
    })
  }

  private setTimeNow(): void {
    const jd = Date.now() / 86400000.0 + 2440587.5
    this.observationTimeText = this.formatLocalDateTime(new Date())
    this.callInteractive('setJD', jd.toString(), (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'setTimeNow ok=%{public}s', r.ok === true ? '1' : '0')
      this.refreshState()
    })
  }

  private setFovPreset(deg: number): void {
    this.callInteractive('setFOV', deg.toString(), (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'setFovPreset %{public}d ok=%{public}s', deg, r.ok === true ? '1' : '0')
      this.flashHint('视场 ' + deg.toFixed(1) + '°')
      this.refreshState()
    })
  }


  private setProjection(name: string): void {
    this.callInteractive('setProjectionType', name, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.currentProjection = name
        this.flashHint(I18n.projectionName(name))
      } else {
        hilog.error(0x0000, 'StellariumArkUI', 'setProjectionType rejected %{public}s err=%{public}s', name, r.error ?? '')
        this.flashHint(I18n.t('msg_apply_failed'))
      }
    })
  }
  private triggerAction(actionId: string): void {
    hilog.info(0x0000, 'StellariumArkUI', 'triggerAction send %{public}s', actionId)
    this.flashHint(I18n.t('msg_command_sent'))
    this.callInteractive('triggerAction', actionId, (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'triggerAction %{public}s ok=%{public}s err=%{public}s', actionId, r.ok === true ? '1' : '0', r.error ?? '')
      this.refreshState()
    })
  }

  private saveScreenshot(): void {
    this.callInteractive('saveScreenShot', '', (r: StellariumBridgeResponse) => {
      this.flashHint(r.ok === true ? I18n.t('screenshot_saved') : '截图保存失败')
    })
  }

  private jdToDateStr(jd: string): string {
    if (jd.indexOf('T') >= 0) {
      const match = jd.match(/^(?:\d{4}-)?(\d{2})-(\d{2})T(\d{2}):(\d{2})/)
      if (match !== null) return parseInt(match[1]).toString() + '/' + parseInt(match[2]).toString() + ' ' + match[3] + ':' + match[4]
    }
    const numJd = parseFloat(jd);
    if (numJd <= 0) return '--'
    const date = new Date((numJd - 2440587.5) * 86400000)
    return (date.getMonth() + 1).toString() + '/' + date.getDate().toString()
      + ' ' + date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0')
  }

  private loadRTS(): void {
    this.rtsError = ''
    if (!this.hasSelectedObject()) {
      this.clearRtsSelectionResults()
      return
    }
    this.callInteractive('getRTS', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.rts !== undefined) {
        const rv: Object = r.rts as Object
        const data = new Map<string, string>()
        data.set('name', rv['name'] !== undefined ? rv['name'] as string : 'N/A')
        data.set('nextRiseJD', rv['nextRiseJD'] !== undefined ? String(rv['nextRiseJD']) : '0')
        data.set('nextTransitJD', rv['nextTransitJD'] !== undefined ? String(rv['nextTransitJD']) : '0')
        data.set('nextSetJD', rv['nextSetJD'] !== undefined ? String(rv['nextSetJD']) : '0')
        data.set('prevRiseJD', rv['prevRiseJD'] !== undefined ? String(rv['prevRiseJD']) : '0')
        data.set('prevTransitJD', rv['prevTransitJD'] !== undefined ? String(rv['prevTransitJD']) : '0')
        data.set('prevSetJD', rv['prevSetJD'] !== undefined ? String(rv['prevSetJD']) : '0')
        data.set('nextRiseText', rv['nextRiseText'] !== undefined ? String(rv['nextRiseText']) : (rv['nextRiseJD'] !== undefined ? String(rv['nextRiseJD']) : '0'))
        data.set('nextTransitText', rv['nextTransitText'] !== undefined ? String(rv['nextTransitText']) : (rv['nextTransitJD'] !== undefined ? String(rv['nextTransitJD']) : '0'))
        data.set('nextSetText', rv['nextSetText'] !== undefined ? String(rv['nextSetText']) : (rv['nextSetJD'] !== undefined ? String(rv['nextSetJD']) : '0'))
        data.set('prevRiseText', rv['prevRiseText'] !== undefined ? String(rv['prevRiseText']) : (rv['prevRiseJD'] !== undefined ? String(rv['prevRiseJD']) : '0'))
        data.set('prevTransitText', rv['prevTransitText'] !== undefined ? String(rv['prevTransitText']) : (rv['prevTransitJD'] !== undefined ? String(rv['prevTransitJD']) : '0'))
        data.set('prevSetText', rv['prevSetText'] !== undefined ? String(rv['prevSetText']) : (rv['prevSetJD'] !== undefined ? String(rv['prevSetJD']) : '0'))
        this.rtsData = data
      } else {
        this.rtsData = new Map()
        this.rtsError = '请先在星图上选中一个天体，再计算升中天落。'
      }
    })
  }

  private jumpToRts(key: string): void {
    const jd = this.rtsData.get(key) ?? '0'
    if (parseFloat(jd) <= 0) {
      this.flashHint('该天体在当前位置没有这个事件。')
      return
    }
    this.callInteractive('setJD', jd, (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.refreshState()
    })
  }

  private loadRtsCalendar(): void {
    const requestId = ++this.rtsCalendarLoadSequence
    this.rtsCalendarData = []
    this.rtsCalendarError = ''
    this.rtsCalendarNeedsGeneration = false
    if (!this.hasSelectedObject()) {
      this.clearRtsSelectionResults()
      return
    }
    this.rtsCalendarLoading = true
    this.rtsCalendarProgress = 0
    this.rtsCalendarTotalDays = this.rtsCalendarDays
    this.resolveRtsCalendarStartJD(requestId, (startJD: number) => {
      const options: RtsCalendarOptions = { days: this.rtsCalendarDays }
      if (startJD > 0) options.jd = startJD
      this.callLongRunningInteractive('getRTSCalendar', JSON.stringify(options), (r: StellariumBridgeResponse) => {
        if (requestId !== this.rtsCalendarLoadSequence) return
        this.rtsCalendarLoading = false
        if (r.ok === true && r.rtsCalendar !== undefined) {
          this.rtsCalendarData = r.rtsCalendar as Array<RtsCalendarDay>
          this.rtsCalendarName = r.name ?? ''
          this.rtsCalendarProgress = this.rtsCalendarDays
        } else {
          this.rtsCalendarError = '请先在星图上选中一个天体，再生成升中天落日期表。'
        }
      }, () => {
        if (requestId !== this.rtsCalendarLoadSequence) return
        this.rtsCalendarLoading = false
        this.rtsCalendarError = '日期表计算时间较长，请缩短时长后重试。'
      }, (progress: StellariumBridgeResponse) => {
        if (requestId !== this.rtsCalendarLoadSequence) return
        const completed = Number(progress.progress)
        const total = Number(progress.totalDays)
        if (Number.isFinite(completed) && completed > 0) this.rtsCalendarProgress = completed
        if (Number.isFinite(total) && total > 0) this.rtsCalendarTotalDays = total
      }, 480)
    }, () => {
      if (requestId !== this.rtsCalendarLoadSequence) return
      this.rtsCalendarLoading = false
      this.rtsCalendarError = '无法读取当前模拟时间，请点生成日期表后重试。'
    })
  }

  private rtsCalendarLoadSequence: number = 0

  private markRtsCalendarForRegeneration(): void {
    ++this.rtsCalendarLoadSequence
    this.rtsCalendarLoading = false
    this.rtsCalendarData = []
    this.rtsCalendarError = ''
    this.rtsCalendarNeedsGeneration = true
    this.rtsCalendarProgress = 0
    this.rtsCalendarTotalDays = 0
  }

  private resolveRtsCalendarStartJD(requestId: number, onReady: (startJD: number) => void, onFailure: () => void): void {
    if (this.rtsCalendarStartOffsetDays < 0) {
      onReady(this.dateToJD(this.rtsCalendarStartYear, this.rtsCalendarStartMonth, this.rtsCalendarStartDay, 0, 0))
      return
    }
    if (this.rtsCalendarStartOffsetDays === 0) {
      onReady(0)
      return
    }
    this.callInteractive('getState', '', (state: StellariumBridgeResponse) => {
      if (requestId !== this.rtsCalendarLoadSequence) return
      const currentJD = Number(state.jd)
      if (state.ok === true && Number.isFinite(currentJD) && currentJD > 0) {
        onReady(currentJD + this.rtsCalendarStartOffsetDays)
        return
      }
      onFailure()
    }, () => {
      if (requestId !== this.rtsCalendarLoadSequence) return
      onFailure()
    })
  }

  private rtsCalendarStartOptionLabel(offsetDays: number): string {
    if (offsetDays < 0) {
      return this.rtsCalendarStartYear.toString() + '-' + this.rtsCalendarStartMonth.toString().padStart(2, '0') + '-' + this.rtsCalendarStartDay.toString().padStart(2, '0')
    }
    if (offsetDays === 0) return '当前'
    return '+' + offsetDays.toString() + ' 天'
  }

  private rtsCalendarDurationLabel(days: number): string {
    if (days === 31) return '1 个月'
    if (days === 62) return '2 个月'
    if (days === 92) return '3 个月'
    if (days === 183) return '6 个月'
    if (days === 365) return '12 个月'
    return days.toString() + ' 天'
  }

  private chooseRtsCalendarStartDate(): void {
    this.pickedDate = new Date(this.rtsCalendarStartYear, this.rtsCalendarStartMonth - 1, this.rtsCalendarStartDay)
    this.getUIContext().showDatePickerDialog({
      start: new Date('1900-01-01'),
      end: new Date('2100-12-31'),
      selected: this.pickedDate,
      onAccept: (value: DatePickerResult) => {
        this.rtsCalendarStartYear = value.year ?? this.rtsCalendarStartYear
        this.rtsCalendarStartMonth = (value.month ?? (this.rtsCalendarStartMonth - 1)) + 1
        this.rtsCalendarStartDay = value.day ?? this.rtsCalendarStartDay
        this.rtsCalendarStartOffsetDays = -1
        this.markRtsCalendarForRegeneration()
      },
      onCancel: () => {}
    })
  }

  private jumpToRtsCalendar(day: RtsCalendarDay): void {
    const jd = day.transitJD ?? day.riseJD ?? day.setJD ?? 0
    if (jd <= 0) return
    this.callInteractive('setJD', jd.toString(), (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.refreshState()
    })
  }

  private loadEphemeris(): void {
    const requestId = ++this.ephemerisLoadSequence
    this.ephemerisData = []
    this.ephemerisName = ''
    this.ephemerisError = ''
    this.ephemerisLoading = true
    this.resolveEphemerisStartJD(requestId, (startJD: number) => {
      const options: EphemerisOptions = { days: this.ephemerisDays, stepHours: this.ephemerisStepHours }
      if (startJD > 0) options.jd = startJD
      if (this.ephemerisMode === 1) options.names = [this.ephemerisPrimary, this.ephemerisSecondary]
      if (this.ephemerisMode === 2) options.allNakedEye = true
      this.callNativeWhenReady('getEphemeris', JSON.stringify(options), (r: StellariumBridgeResponse) => {
        if (requestId !== this.ephemerisLoadSequence) return
        this.ephemerisLoading = false
        if (r.ok === true && r.ephemeris !== undefined) {
          this.ephemerisData = r.ephemeris as Array<EphemerisRow>
          this.ephemerisName = r.name !== undefined ? String(r.name) : ''
        } else {
          this.ephemerisError = r.error ?? '请先在星图上选中一个天体，再生成它的星历。'
        }
      }, 0, 100, 80, () => {
        if (requestId !== this.ephemerisLoadSequence) return
        this.ephemerisLoading = false
        this.ephemerisError = '星历计算时间较长，请缩短时间范围或增大采样间隔后重试。'
      })
    }, () => {
      if (requestId !== this.ephemerisLoadSequence) return
      this.ephemerisLoading = false
      this.ephemerisError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  private ephemerisLoadSequence: number = 0

  private resolveEphemerisStartJD(requestId: number, onReady: (startJD: number) => void, onFailure: () => void): void {
    if (this.ephemerisStartOffsetDays < 0) {
      onReady(this.dateToJD(this.ephemerisStartYear, this.ephemerisStartMonth, this.ephemerisStartDay, 0, 0))
      return
    }
    if (this.ephemerisStartOffsetDays === 0) {
      onReady(0)
      return
    }
    this.callInteractive('getState', '', (state: StellariumBridgeResponse) => {
      if (requestId !== this.ephemerisLoadSequence) return
      const currentJD = Number(state.jd)
      if (state.ok === true && Number.isFinite(currentJD) && currentJD > 0) {
        onReady(currentJD + this.ephemerisStartOffsetDays)
        return
      }
      onFailure()
    }, () => {
      if (requestId !== this.ephemerisLoadSequence) return
      onFailure()
    })
  }

  private ephemerisStartOptionLabel(offsetDays: number): string {
    if (offsetDays < 0) {
      return this.ephemerisStartYear.toString() + '-' + this.ephemerisStartMonth.toString().padStart(2, '0') + '-' + this.ephemerisStartDay.toString().padStart(2, '0')
    }
    if (offsetDays === 0) return '当前'
    return '+' + offsetDays.toString() + ' 天'
  }

  private chooseEphemerisStartDate(): void {
    this.pickedDate = new Date(this.ephemerisStartYear, this.ephemerisStartMonth - 1, this.ephemerisStartDay)
    this.getUIContext().showDatePickerDialog({
      start: new Date('1900-01-01'),
      end: new Date('2100-12-31'),
      selected: this.pickedDate,
      onAccept: (value: DatePickerResult) => {
        this.ephemerisStartYear = value.year ?? this.ephemerisStartYear
        this.ephemerisStartMonth = (value.month ?? (this.ephemerisStartMonth - 1)) + 1
        this.ephemerisStartDay = value.day ?? this.ephemerisStartDay
        this.ephemerisStartOffsetDays = -1
        this.loadEphemeris()
      },
      onCancel: () => {}
    })
  }

  private jumpToEphemerisRow(row: EphemerisRow): void {
    if (row.jd === undefined || row.jd <= 0) return
    this.callInteractive('setJD', String(row.jd), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.refreshState()
        this.loadEphemeris()
      }
    })
  }

  private loadPlanetCalc(): void {
    this.callInteractive('getPlanetCalc', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.planetCalc !== undefined) this.planetCalcData = r.planetCalc as Array<PlanetCalcItem>
    })
  }

  private loadPlanetPairDistance(): void {
    this.planetPairDistanceData = []
    this.planetPairDistanceError = ''
    const options = JSON.stringify({
      first: this.planetPairFirst,
      second: this.planetPairSecond,
      days: this.planetPairDays,
      stepDays: this.planetPairStepDays
    })
    this.callInteractive('getPlanetPairDistanceCurve', options, (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.planetPairDistance !== undefined) {
        const data = r.planetPairDistance as Array<PlanetPairDistancePoint>
        this.planetPairDistanceData = data
        this.planetPairFirstName = this.planetPairBodyName(this.planetPairFirst)
        this.planetPairSecondName = this.planetPairBodyName(this.planetPairSecond)
        this.planetPairAngularAvailable = r.angularAvailable === true
        this.updatePlanetPairDistanceRanges(data)
      } else {
        this.planetPairDistanceData = []
        this.planetPairDistanceError = '请选择两个不同的太阳系天体。'
      }
    })
  }

  private updatePlanetPairDistanceRanges(data: Array<PlanetPairDistancePoint>): void {
    let linearMin: number = Number.MAX_VALUE
    let linearMax: number = -Number.MAX_VALUE
    let angularMin: number = Number.MAX_VALUE
    let angularMax: number = -Number.MAX_VALUE
    for (const point of data) {
      const linear: number = point.linearDistance ?? 0
      linearMin = Math.min(linearMin, linear)
      linearMax = Math.max(linearMax, linear)
      if (point.angularDistance !== undefined) {
        angularMin = Math.min(angularMin, point.angularDistance)
        angularMax = Math.max(angularMax, point.angularDistance)
      }
    }
    this.planetPairLinearMin = linearMin === Number.MAX_VALUE ? 0 : linearMin
    this.planetPairLinearMax = linearMax <= linearMin ? linearMin + 1 : linearMax
    this.planetPairAngularMin = angularMin === Number.MAX_VALUE ? 0 : angularMin
    this.planetPairAngularMax = angularMax <= angularMin ? angularMin + 1 : angularMax
  }

  private loadAltAzCurve(): void {
    const requestId = this.beginGraphLoad()
    this.altAzCurve = []
    this.altAzError = ''
    this.resolveGraphStartJD(requestId, (startJD: number) => {
      this.callInteractive('getAltAzCurve', JSON.stringify({
        jd: startJD,
        hours: this.altAzHours,
        stepMin: this.altAzStepMin,
        includeSun: this.graphMode === 0 && this.altAzShowSun,
        includeMoon: this.graphMode === 0 && this.altAzShowMoon
      }), (r: StellariumBridgeResponse) => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        if (r.ok === true && r.curve !== undefined) {
          this.altAzCurve = r.curve as Array<AltAzPoint>
          this.altAzName = r.name !== undefined ? r.name : ''
          this.altAzError = ''
        } else {
          this.altAzCurve = []
          this.altAzError = '请先在星图上选中一个天体，再来看它的' + (this.graphMode === 0 ? '高度' : '方位角') + '曲线。'
        }
      }, () => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        this.altAzError = '计算等待超时，请点刷新后重试。'
      })
    }, () => {
      this.altAzError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  private loadObservabilityCalendar(): void {
    const requestId = this.beginGraphLoad()
    this.observabilityData = []
    this.observabilityError = ''
    this.resolveGraphStartJD(requestId, (startJD: number) => {
      const options = JSON.stringify({ jd: startJD, days: this.observabilityDays, minAltitude: this.observabilityMinAltitude })
      this.callNativeWhenReady('getObservabilityCalendar', options, (r: StellariumBridgeResponse) => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        if (r.ok === true && r.observability !== undefined) {
          this.observabilityData = r.observability as Array<ObservabilityDay>
          this.observabilityName = r.name ?? ''
        } else {
          this.observabilityData = []
          this.observabilityError = '请先在星图上选中一个天体，再查看它未来多晚的可见性。'
        }
      }, 0, 100, 200, () => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        this.observabilityError = '计算等待超时，请稍后重试。'
      })
    }, () => {
      this.observabilityError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  private loadAnnualElevation(): void {
    const requestId = this.beginGraphLoad()
    this.annualElevationData = []
    this.annualElevationError = ''
    this.callInteractive('getAnnualElevation', JSON.stringify({ hour: this.annualElevationHour }), (r: StellariumBridgeResponse) => {
      if (requestId !== this.graphLoadSequence) return
      this.finishGraphLoad(requestId)
      if (r.ok === true && r.annualElevation !== undefined) {
        this.annualElevationData = r.annualElevation as Array<AnnualElevationPoint>
        this.annualElevationName = r.name ?? ''
      } else {
        this.annualElevationData = []
        this.annualElevationError = '请先在星图上选中一个天体，再生成全年高度曲线。'
      }
    }, () => {
      if (requestId !== this.graphLoadSequence) return
      this.finishGraphLoad(requestId)
      this.annualElevationError = '计算等待超时，请点刷新后重试。'
    })
  }

  private loadLunarElongation(): void {
    const requestId = this.beginGraphLoad()
    this.lunarElongationData = []
    this.lunarElongationError = ''
    this.resolveGraphStartJD(requestId, (startJD: number) => {
      const options = JSON.stringify({ jd: startJD, days: this.lunarElongationDays, stepHours: this.lunarElongationStepHours })
      this.callInteractive('getLunarElongationCurve', options, (r: StellariumBridgeResponse) => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        if (r.ok === true && r.lunarElongation !== undefined) {
          this.lunarElongationData = r.lunarElongation as Array<LunarElongationPoint>
          this.lunarElongationName = r.name ?? ''
        } else {
          this.lunarElongationData = []
          this.lunarElongationError = '请先选中除月亮和人造卫星之外的天体，再生成月距曲线。'
        }
      }, () => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        this.lunarElongationError = '计算等待超时，请点刷新后重试。'
      })
    }, () => {
      this.lunarElongationError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  private loadPlanetTimeSeries(): void {
    const requestId = this.beginGraphLoad()
    this.planetTimeSeriesData = []
    this.planetTimeSeriesError = ''
    this.resolveGraphStartJD(requestId, (startJD: number) => {
      const options = JSON.stringify({
        jd: startJD,
        days: this.planetTimeSeriesDays,
        stepHours: this.planetTimeSeriesStepHours,
        leftMetric: this.planetTimeSeriesLeftMetric,
        rightMetric: this.planetTimeSeriesRightMetric
      })
      this.callInteractive('getPlanetTimeSeries', options, (r: StellariumBridgeResponse) => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        if (r.ok === true && r.timeSeries !== undefined) {
          const data = r.timeSeries as Array<PlanetTimeSeriesPoint>
          this.planetTimeSeriesData = data
          this.planetTimeSeriesName = r.name ?? ''
          this.updatePlanetTimeSeriesRanges(data)
        } else {
          this.planetTimeSeriesData = []
          this.planetTimeSeriesError = '请先选中一个太阳系天体（行星、太阳或月亮），再生成双曲线。'
        }
      }, () => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        this.planetTimeSeriesError = '计算等待超时，请点刷新后重试。'
      })
    }, () => {
      this.planetTimeSeriesError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  private graphLoadSequence: number = 0

  private beginGraphLoad(): number {
    this.graphLoadSequence += 1
    this.graphLoading = true
    return this.graphLoadSequence
  }

  private finishGraphLoad(requestId: number): void {
    if (requestId === this.graphLoadSequence) this.graphLoading = false
  }

  private resolveGraphStartJD(requestId: number, onReady: (startJD: number) => void, onFailure: () => void): void {
    if (this.graphStartOffsetDays < 0) {
      onReady(this.dateToJD(this.graphStartYear, this.graphStartMonth, this.graphStartDay, 0, 0))
      return
    }
    if (this.graphStartOffsetDays === 0) {
      onReady(0)
      return
    }
    this.callInteractive('getState', '', (state: StellariumBridgeResponse) => {
      if (requestId !== this.graphLoadSequence) return
      const currentJD = Number(state.jd)
      if (state.ok === true && Number.isFinite(currentJD) && currentJD > 0) {
        onReady(currentJD + this.graphStartOffsetDays)
        return
      }
      this.finishGraphLoad(requestId)
      onFailure()
    }, () => {
      if (requestId !== this.graphLoadSequence) return
      this.finishGraphLoad(requestId)
      onFailure()
    })
  }

  private graphStartOptionLabel(offsetDays: number): string {
    if (offsetDays === 0) return '当前'
    return '+' + offsetDays.toString() + ' 天'
  }

  private graphCustomStartLabel(): string {
    if (this.graphStartOffsetDays >= 0) return '指定日期'
    return this.graphStartYear.toString() + '-' + this.graphStartMonth.toString().padStart(2, '0') + '-' + this.graphStartDay.toString().padStart(2, '0')
  }

  private chooseGraphStartDate(): void {
    this.pickedDate = new Date(this.graphStartYear, this.graphStartMonth - 1, this.graphStartDay)
    this.getUIContext().showDatePickerDialog({
      start: new Date('1900-01-01'),
      end: new Date('2100-12-31'),
      selected: this.pickedDate,
      onAccept: (value: DatePickerResult) => {
        this.graphStartYear = value.year ?? this.graphStartYear
        this.graphStartMonth = (value.month ?? (this.graphStartMonth - 1)) + 1
        this.graphStartDay = value.day ?? this.graphStartDay
        this.graphStartOffsetDays = -1
        this.reloadCurrentGraph()
      },
      onCancel: () => {}
    })
  }

  private reloadCurrentGraph(): void {
    if (this.graphMode === 2) this.loadAnnualElevation()
    else if (this.graphMode === 3) this.loadObservabilityCalendar()
    else if (this.graphMode === 4) this.loadLunarElongation()
    else if (this.graphMode === 5) this.loadPlanetTimeSeries()
    else this.loadAltAzCurve()
  }

  @Builder
  graphLoadingRow(label: string) {
    Row({ space: 8 }) {
      LoadingProgress().width(22).height(22).color(this.nmAccent())
      Text(label).fontSize(11).fontColor(this.nmSub())
    }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
  }

  private openGraphTargetPicker(): void {
    this.graphTargetPickerActive = true
    this.searchText = ''
    this.searchSuggestions = []
    this.loadCategoryObjects('planet')
    this.setPanel('search')
  }

  private openRtsTargetPicker(): void {
    this.rtsTargetPickerActive = true
    this.searchText = ''
    this.searchSuggestions = []
    this.loadCategoryObjects('planet')
    this.setPanel('search')
  }

  private openEphemerisTargetPicker(): void {
    this.ephemerisTargetPickerActive = true
    this.searchText = ''
    this.searchSuggestions = []
    this.loadCategoryObjects('planet')
    this.setPanel('search')
  }

  private hasSelectedObject(): boolean {
    return this.selectedStatus === 'Selected' && this.selectedName.length > 0
  }

  private clearRtsSelectionResults(): void {
    this.rtsData = new Map()
    this.rtsError = '升起、中天和落下时间需要先选择一个天体。'
    this.rtsCalendarData = []
    this.rtsCalendarName = ''
    this.rtsCalendarLoading = false
    this.rtsCalendarError = '请先选择一个天体，再生成升中天落日期表。'
    this.rtsCalendarNeedsGeneration = false
    this.rtsCalendarProgress = 0
    ++this.rtsCalendarLoadSequence
  }

  @Builder
  rtsSelectionGuide() {
    Column({ space: 5 }) {
      Text('先选择一个天体，才能按当前观测地点计算它的升起、中天和落下时间。')
        .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 8 })
      Button('选择天体').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(16).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.openRtsTargetPicker() })
    }.width('100%').padding({ left: 4 }).margin({ top: 5, bottom: 6 }).alignItems(HorizontalAlign.Start)
  }

  private graphTargetLabel(): string {
    if (this.selectedName.length === 0) return '尚未选择天体'
    return this.zhNameOf(this.selectedName)
  }

  @Builder
  graphSelectionGuide(error: string) {
    Column({ space: 5 }) {
      Text(error.indexOf('超时') >= 0 ? '若尚未选择天体，先选择一个；已选择时可点刷新重试。' : '先选择一个天体，才能按当前观测地点生成曲线。')
        .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 8 })
      Button('去选择天体').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(16).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.openGraphTargetPicker() })
    }.width('100%').padding({ left: 4 }).margin({ top: 5, bottom: 6 }).alignItems(HorizontalAlign.Start)
  }

  private updatePlanetTimeSeriesRanges(data: Array<PlanetTimeSeriesPoint>): void {
    let leftMin: number = Number.MAX_VALUE
    let leftMax: number = -Number.MAX_VALUE
    let rightMin: number = Number.MAX_VALUE
    let rightMax: number = -Number.MAX_VALUE
    for (const point of data) {
      const left: number = point.left ?? 0
      const right: number = point.right ?? 0
      leftMin = Math.min(leftMin, left)
      leftMax = Math.max(leftMax, left)
      rightMin = Math.min(rightMin, right)
      rightMax = Math.max(rightMax, right)
    }
    this.planetTimeSeriesLeftMin = leftMin === Number.MAX_VALUE ? 0 : leftMin
    this.planetTimeSeriesLeftMax = leftMax <= leftMin ? leftMin + 1 : leftMax
    this.planetTimeSeriesRightMin = rightMin === Number.MAX_VALUE ? 0 : rightMin
    this.planetTimeSeriesRightMax = rightMax <= rightMin ? rightMin + 1 : rightMax
  }

  private jumpToObservabilityDay(day: ObservabilityDay): void {
    if (day.bestJD === undefined || day.bestJD <= 0) return
    this.callInteractive('setJD', String(day.bestJD), (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.refreshState()
    })
  }

  private loadEclipses(): void {
    if (this.eclipseData.length > 0 || this.eclipseLoading) return
    const requestId = ++this.eclipseLoadSequence
    this.eclipseLoading = true
    this.eclipseError = ''
    this.resolveEclipseStartJD(requestId, (startJD: number) => {
      const options: EclipseOptions = { months: this.eclipseMonths }
      if (startJD > 0) options.jd = startJD
      this.callNativeWhenReady('getEclipses', JSON.stringify(options), (r: StellariumBridgeResponse) => {
        if (requestId !== this.eclipseLoadSequence) return
        this.eclipseLoading = false
        if (r.ok === true && r.eclipses !== undefined) {
          this.eclipseData = r.eclipses as Array<EclipseItem>
          return
        }
        this.eclipseError = r.error ?? '日月食计算未能完成，请重试。'
      }, 0, 100, 200, () => {
        if (requestId !== this.eclipseLoadSequence) return
        this.eclipseLoading = false
        this.eclipseError = '日月食计算时间较长，请缩短预测范围后重试。'
      })
    }, () => {
      if (requestId !== this.eclipseLoadSequence) return
      this.eclipseLoading = false
      this.eclipseError = '无法读取当前模拟时间，请重试。'
    })
  }

  private eclipseLoadSequence: number = 0

  private reloadEclipses(): void {
    ++this.eclipseLoadSequence
    this.eclipseLoading = false
    this.eclipseData = []
    this.eclipseError = ''
    this.loadEclipses()
  }

  private resolveEclipseStartJD(requestId: number, onReady: (startJD: number) => void, onFailure: () => void): void {
    if (this.eclipseStartOffsetDays < 0) {
      onReady(this.dateToJD(this.eclipseStartYear, this.eclipseStartMonth, this.eclipseStartDay, 0, 0))
      return
    }
    if (this.eclipseStartOffsetDays === 0) {
      onReady(0)
      return
    }
    this.callInteractive('getState', '', (state: StellariumBridgeResponse) => {
      if (requestId !== this.eclipseLoadSequence) return
      const currentJD = Number(state.jd)
      if (state.ok === true && Number.isFinite(currentJD) && currentJD > 0) {
        onReady(currentJD + this.eclipseStartOffsetDays)
        return
      }
      onFailure()
    }, () => {
      if (requestId !== this.eclipseLoadSequence) return
      onFailure()
    })
  }

  private eclipseStartOptionLabel(offsetDays: number): string {
    if (offsetDays < 0) {
      return this.eclipseStartYear.toString() + '-' + this.eclipseStartMonth.toString().padStart(2, '0') + '-' + this.eclipseStartDay.toString().padStart(2, '0')
    }
    if (offsetDays === 0) return '当前'
    return '+' + offsetDays.toString() + ' 天'
  }

  private chooseEclipseStartDate(): void {
    this.pickedDate = new Date(this.eclipseStartYear, this.eclipseStartMonth - 1, this.eclipseStartDay)
    this.getUIContext().showDatePickerDialog({
      start: new Date('1900-01-01'),
      end: new Date('2100-12-31'),
      selected: this.pickedDate,
      onAccept: (value: DatePickerResult) => {
        this.eclipseStartYear = value.year ?? this.eclipseStartYear
        this.eclipseStartMonth = (value.month ?? (this.eclipseStartMonth - 1)) + 1
        this.eclipseStartDay = value.day ?? this.eclipseStartDay
        this.eclipseStartOffsetDays = -1
        this.reloadEclipses()
      },
      onCancel: () => {}
    })
  }

  private filteredEclipses(): Array<EclipseItem> {
    const filtered: Array<EclipseItem> = []
    for (const eclipse of this.eclipseData) {
      if (this.eclipseKindFilter === 1 && eclipse.kind !== 'solar') continue
      if (this.eclipseKindFilter === 2 && eclipse.kind !== 'lunar') continue
      const type = eclipse.type ?? ''
      if (this.eclipseTypeFilter === 1 && type !== '全食') continue
      if (this.eclipseTypeFilter === 2 && type !== '环食') continue
      if (this.eclipseTypeFilter === 3 && type !== '偏食') continue
      if (this.eclipseTypeFilter === 4 && type !== '半影食') continue
      filtered.push(eclipse)
    }
    return filtered
  }

  private loadPlanetaryTransits(): void {
    if (!this.planetaryTransitLoaded) {
      this.callNativeWhenReady('getPlanetaryTransits', JSON.stringify({ years: this.planetaryTransitYears }), (r: StellariumBridgeResponse) => {
        if (r.ok === true && r.planetaryTransits !== undefined) {
          this.planetaryTransitData = r.planetaryTransits as Array<PlanetaryTransitItem>
          this.planetaryTransitError = ''
        } else {
          this.planetaryTransitError = '行星凌日只能按地球上的当前观测地点计算。'
        }
        this.planetaryTransitLoaded = true
      }, 0, 100, 200)
    }
  }

  private loadPhenomena(): void {
    this.phenomenaData = []
    this.phenomenaHint = ''
    this.phenomenaLoading = true
    const options: PhenomenaOptions = {
      bodyA: this.phenomenaPrimary,
      bodyB: this.phenomenaTarget,
      days: this.phenomenaDays,
      startOffsetMonths: this.phenomenaStartOffsetMonths,
      maxSeparation: this.phenomenaMaxSeparation,
      includeOppositions: this.phenomenaIncludeOppositions,
      includePerihelionAphelion: this.phenomenaIncludePerihelionAphelion,
      includeElongationsQuadratures: this.phenomenaIncludeElongationsQuadratures,
      includeStations: this.phenomenaIncludeStations,
    }
    this.callNativeWhenReady('getPhenomena', JSON.stringify(options), (r: StellariumBridgeResponse) => {
      this.phenomenaLoading = false
      if (r.ok === true && r.phenomena !== undefined) {
        this.phenomenaData = r.phenomena as Array<PhenomenonItem>
        if (this.phenomenaData.length === 0) this.phenomenaHint = '所选时段内没有符合角距条件的天象。'
      } else {
        this.phenomenaHint = r.error ?? '暂时无法完成天象计算，请稍后重试。'
      }
    }, 0, 100, 300, () => {
      this.phenomenaLoading = false
      this.phenomenaHint = '计算时间较长，请缩短预测范围或减少比较对象后重试。'
    })
  }

  private phenomenaBodyName(body: string): string {
    return body === 'all' ? '全部行星' : this.planetPairBodyName(body)
  }

  private phenomenonCaption(type: string): string {
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

  @Builder
  phenomenonRelationMark(type: string) {
    if (type === '合') {
      Image($r('app.media.ic_phenomenon_conjunction'))
    } else if (type === '冲') {
      Image($r('app.media.ic_phenomenon_opposition'))
    } else if (type.indexOf('方照') >= 0) {
      if (type.indexOf('东') >= 0) {
        Image($r('app.media.ic_phenomenon_quadrature_east'))
      } else {
        Image($r('app.media.ic_phenomenon_quadrature_west'))
      }
    } else if (type.indexOf('大距') >= 0) {
      if (type.indexOf('东') >= 0) {
        Image($r('app.media.ic_phenomenon_elongation_east'))
      } else {
        Image($r('app.media.ic_phenomenon_elongation_west'))
      }
    } else if (type.indexOf('近日点') >= 0) {
      Image($r('app.media.ic_phenomenon_perihelion'))
    } else if (type.indexOf('远日点') >= 0) {
      Image($r('app.media.ic_phenomenon_aphelion'))
    } else if (type.indexOf('顺行') >= 0) {
      Image($r('app.media.ic_phenomenon_station_direct'))
    } else if (type.indexOf('逆行') >= 0) {
      Image($r('app.media.ic_phenomenon_station_retrograde'))
    } else {
      Image($r('app.media.ic_phenomenon_station'))
    }
  }

  private jumpToPhenomenon(item: PhenomenonItem): void {
    if (item.jd === undefined || item.jd <= 0) return
    this.callInteractive('setJD', String(item.jd), (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.refreshState()
    })
  }

  private loadTonightAstro(): void {
    if (this.tonightAstro === null) {
      this.callInteractive('getTonightEvents', '', (r: StellariumBridgeResponse) => {
        if (r.ok === true && r.tonight !== undefined) this.tonightAstro = r.tonight as TonightEvents
      })
    }
    this.loadWutTargets()
  }

  private loadWutTargets(): void {
    this.wutHint = ''
    const options = JSON.stringify({
      category: this.wutCategory,
      period: this.wutPeriod,
      minAltitude: this.wutMinAltitude,
      maxMagnitude: this.wutMaxMagnitude,
      limitAngularSize: this.wutLimitAngularSize,
      minAngularSizeArcmin: this.wutMinAngularSizeArcmin,
      maxAngularSizeArcmin: this.wutMaxAngularSizeArcmin
    })
    this.callInteractive('getWutTargets', options, (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.wutTargets !== undefined) {
        this.wutTargets = r.wutTargets as Array<WutTarget>
        this.wutObservationTime = r.observationTime ?? ''
        this.wutAngularSizeAvailable = r.angularSizeAvailable !== false
        if (!this.wutAngularSizeAvailable) this.wutLimitAngularSize = false
        if (this.wutTargets.length === 0) this.wutHint = '当前条件下没有符合要求的' + this.wutCategoryTitle() + '。'
      } else {
        this.wutTargets = []
        this.wutHint = '当前地点没有可用的民用暮光观测窗口。'
      }
    })
  }

  private jumpToWutTarget(target: WutTarget): void {
    if (target.jd === undefined || target.jd <= 0 || target.englishName === undefined) return
    this.callInteractive('setJD', String(target.jd), (timeResult: StellariumBridgeResponse) => {
      if (timeResult.ok === true) {
        this.callNative('searchObject', target.englishName ?? '')
        this.refreshState()
      }
    })
  }

  // ---- 时间面板扩展：恒星时 / 夜视 / 大气折射 ----
  private loadTimeExtras(): void {
    const st: StellariumBridgeResponse = this.callNative('getSiderealTime', '')
    if (st.ok === true && st.text !== undefined) this.siderealTimeText = st.text

    const nm: StellariumBridgeResponse = this.callNative('getNightMode', '')
    if (nm.ok === true) this.nightModeOn = (nm.night === true)

    this.applyAtmosphereResponse(this.callNative('getAtmosphereParams', ''))
  }

  private applyAtmosphereResponse(r: StellariumBridgeResponse): void {
    if (r.ok !== true) return
    if (r.pressure !== undefined) this.atmoPressure = r.pressure
    if (r.temperature !== undefined) this.atmoTemperature = r.temperature
    if (r.extinction !== undefined) this.atmoExtinction = r.extinction
    this.refractionOn = (r.refractionOn === true)
  }

  private applyAtmosphere(pressure: number, temperature: number, extinction: number): void {
    this.applyAtmosphereResponse(this.callNative('setAtmosphereParams',
      JSON.stringify({ pressure: pressure, temperature: temperature, extinction: extinction })))
  }

  // ---- 天文计算辅助：高度曲线 ----
  private hourOffsetLabel(t: number): string {
    const h: number = Math.floor(t)
    const mi: number = Math.round((t - h) * 60)
    if (h === 0 && mi === 0) return '此刻'
    let s: string = ''
    if (h > 0) s += h.toString() + ' 小时'
    if (mi > 0) s += mi.toString() + ' 分'
    return s + '后'
  }

  private altAzMaxLabel(): string {
    let m: number = -999
    let t: number = 0
    for (let i = 0; i < this.altAzCurve.length; i++) {
      const p: AltAzPoint = this.altAzCurve[i]
      const v: number = p.altitude !== undefined ? p.altitude : -999
      if (v > m) { m = v; t = p.t !== undefined ? p.t : 0 }
    }
    if (m < -90) return '--'
    return m.toFixed(1) + '°（' + this.hourOffsetLabel(t) + '）'
  }

  private altAzNowLabel(): string {
    if (this.altAzCurve.length === 0) return '--'
    const p: AltAzPoint = this.altAzCurve[0]
    const alt: number = p.altitude !== undefined ? p.altitude : 0
    const az: number = p.azimuth !== undefined ? p.azimuth : 0
    return '高度 ' + alt.toFixed(1) + '° / 方位 ' + az.toFixed(1) + '°'
  }

  private altAzVisibleHours(): string {
    let hours: number = 0
    for (let i = 0; i + 1 < this.altAzCurve.length; i++) {
      const p: AltAzPoint = this.altAzCurve[i]
      const next: AltAzPoint = this.altAzCurve[i + 1]
      if (p.altitude !== undefined && p.altitude > 0 && p.t !== undefined && next.t !== undefined) {
        hours += next.t - p.t
      }
    }
    return hours.toFixed(1) + ' 小时'
  }

  private altAzRangeLabel(): string {
    return '未来 ' + this.altAzHours.toString() + ' 小时'
  }

  private altAzMidpointLabel(): string {
    return '+' + (this.altAzHours / 2).toString() + 'h'
  }

  private altBarWidth(): number {
    if (this.altAzCurve.length === 0) return 4
    return Math.max(1, Math.min(4, 292 / this.altAzCurve.length))
  }

  private altBarHeight(alt: number | undefined): number {
    const a: number = alt !== undefined ? alt : -90
    if (a < this.altAzMinimum) return 1
    const range: number = 90 - this.altAzMinimum
    return Math.max(1, Math.min(96, (a - this.altAzMinimum) / range * 96))
  }

  private altitudeCurveColor(altitude: number | undefined, color: string): string {
    return (altitude ?? -90) >= this.altAzMinimum ? color : '#33FFFFFF'
  }

  private altCurveSegmentWidth(): number {
    let count: number = 1
    if (this.altAzShowSun) count++
    if (this.altAzShowMoon) count++
    return Math.max(1, (this.altBarWidth() - Math.max(0, count - 1)) / count)
  }

  private azBarHeight(azimuth: number | undefined): number {
    const value: number = azimuth !== undefined ? azimuth : 0
    return Math.max(1, Math.min(96, value / 360 * 96))
  }

  private annualBarHeight(altitude: number | undefined): number {
    const value: number = altitude !== undefined ? altitude : -90
    if (value < this.annualElevationMinimum) return 1
    const range: number = 90 - this.annualElevationMinimum
    return Math.max(1, Math.min(96, (value - this.annualElevationMinimum) / range * 96))
  }

  private annualBarWidth(): number {
    if (this.annualElevationData.length === 0) return 3
    return Math.max(1, Math.min(6, 292 / this.annualElevationData.length))
  }

  private annualMaxLabel(): string {
    let maximum: number = -91
    let date: string = ''
    for (const point of this.annualElevationData) {
      const altitude: number = point.altitude ?? -91
      if (altitude > maximum) {
        maximum = altitude
        date = point.date ?? ''
      }
    }
    return maximum < -90 ? '--' : maximum.toFixed(1) + '°（' + (date.length >= 10 ? date.slice(5) : date) + '）'
  }

  private azimuthNowLabel(): string {
    if (this.altAzCurve.length === 0) return '--'
    return (this.altAzCurve[0].azimuth ?? 0).toFixed(1) + '°'
  }

  private lunarElongationBarWidth(): number {
    if (this.lunarElongationData.length === 0) return 4
    return Math.max(1, Math.min(4, 292 / this.lunarElongationData.length))
  }

  private lunarElongationBarHeight(separation: number | undefined): number {
    return Math.max(1, Math.min(96, (separation ?? 0) / 180 * 96))
  }

  private lunarElongationLineTop(): number {
    return Math.max(0, Math.min(95, (1 - this.lunarElongationLimit / 180) * 96))
  }

  private lunarElongationNowLabel(): string {
    if (this.lunarElongationData.length === 0) return '--'
    return (this.lunarElongationData[0].separation ?? 0).toFixed(1) + '°'
  }

  private lunarElongationClosestLabel(): string {
    let closest: number = 181
    let time: number = 0
    for (const point of this.lunarElongationData) {
      const separation: number = point.separation ?? 181
      if (separation < closest) {
        closest = separation
        time = point.t ?? 0
      }
    }
    return closest > 180 ? '--' : closest.toFixed(1) + '°（' + this.hourOffsetLabel(time) + '）'
  }

  private planetMetricLabel(metric: string): string {
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

  private planetMetricUnit(metric: string): string {
    if (metric === 'phase') return ' %'
    if (metric === 'distance' || metric === 'heliocentricDistance') return ' AU'
    if (metric === 'angularSize') return '″'
    if (metric === 'rightAscension') return ' h'
    if (metric === 'magnitude') return ' 等'
    return '°'
  }

  private planetTimeSeriesBarWidth(): number {
    if (this.planetTimeSeriesData.length === 0) return 4
    return Math.max(2, Math.min(6, 292 / this.planetTimeSeriesData.length))
  }

  private planetTimeSeriesSegmentWidth(): number {
    return Math.max(1, (this.planetTimeSeriesBarWidth() - 1) / 2)
  }

  private planetTimeSeriesBarHeight(value: number | undefined, min: number, max: number): number {
    return Math.max(1, Math.min(96, ((value ?? min) - min) / (max - min) * 96))
  }

  private planetTimeSeriesValueLabel(value: number | undefined, metric: string): string {
    return (value ?? 0).toFixed(metric === 'angularSize' ? 0 : 1) + this.planetMetricUnit(metric)
  }

  private planetPairBodyName(body: string): string {
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

  private planetPairBarWidth(): number {
    if (this.planetPairDistanceData.length === 0) return 4
    return Math.max(2, Math.min(6, 292 / this.planetPairDistanceData.length))
  }

  private planetPairSegmentWidth(): number {
    return Math.max(1, (this.planetPairBarWidth() - 1) / 2)
  }

  private planetPairBarHeight(value: number | undefined, min: number, max: number): number {
    return Math.max(1, Math.min(96, ((value ?? min) - min) / (max - min) * 96))
  }

  private planetPairLinearLabel(value: number | undefined): string {
    const distance: number = value ?? 0
    if (distance < 0.1) return (distance * 149597871).toFixed(0) + ' km'
    return distance.toFixed(3) + ' AU'
  }

  private planetPairCurrentIndex(): number {
    return Math.floor(this.planetPairDistanceData.length / 2)
  }

  private hecPointDistance(position: HeliocentricPosition): number {
    return this.clamp(20 + Math.log(position.distanceAU + 1) * 37, 20, 84)
  }

  private hecPointLeft(position: HeliocentricPosition): number {
    const angle = (360 - position.longitude) * Math.PI / 180
    return 100 + this.hecPointDistance(position) * Math.sin(angle) - 7
  }

  private hecPointTop(position: HeliocentricPosition): number {
    const angle = (360 - position.longitude) * Math.PI / 180
    return 100 - this.hecPointDistance(position) * Math.cos(angle) - 7
  }

  private hecPointColor(position: HeliocentricPosition): string {
    if (position.isComet) return '#7CC8E8'
    if (position.isSelectedMinor) return '#C2A36B'
    return this.nmAccent()
  }

  private hecTitle(position: HeliocentricPosition): string {
    return this.celestialTitle(position.name, position.englishName)
  }

  private hecDistanceLabel(position: HeliocentricPosition): string {
    return position.distanceAU < 10 ? position.distanceAU.toFixed(3) : position.distanceAU.toFixed(2)
  }

  private celestialPositionTitle(position: CelestialPosition): string {
    return this.celestialTitle(position.name, position.englishName)
  }

  private celestialPositionSubtitle(position: CelestialPosition): string {
    if (position.catalogId.length > 0 && position.catalogId !== this.celestialPositionTitle(position)) return position.catalogId
    return position.type
  }

  // ---- 通用格式化：把 ISO 时间截成 "MM-DD HH:MM" / "HH:MM" ----
  private fmtDateTime(s: string | undefined): string {
    if (s === undefined || s.length === 0) return '--'
    return s.replace('T', ' ').slice(0, 16)
  }

  private fmtClock(s: string | undefined): string {
    if (s === undefined || s.length < 16) return '--:--'
    return s.slice(11, 16)
  }

  private fmtEphemerisDate(s: string | undefined): string {
    if (s === undefined || s.length < 16) return '--'
    return s.slice(5, 16).replace('T', ' ')
  }

  private fmtNum(v: number | undefined, digits: number, suffix: string): string {
    if (v === undefined) return '--'
    return v.toFixed(digits) + suffix
  }

  private almanacHoursLabel(key: string): string {
    const value = this.almanacData.get(key) ?? ''
    return value.length > 0 ? parseFloat(value).toFixed(1) + ' 小时' : '--'
  }

  private loadAstroTab(id: number): void {
    if (id === 0) {
      if (this.positionMode === 0) this.loadPlanetPositions()
      else if (this.positionMode === 1) this.loadHeliocentricPositions()
      else this.loadCelestialPositions()
    }
    else if (id === 1) this.loadEphemeris()
    else if (id === 2) this.loadRTS()
    else if (id === 3) this.loadPhenomena()
    else if (id === 4) {
      if (this.graphMode === 2) this.loadAnnualElevation()
      else if (this.graphMode === 3) this.loadObservabilityCalendar()
      else if (this.graphMode === 4) this.loadLunarElongation()
      else if (this.graphMode === 5) this.loadPlanetTimeSeries()
      else this.loadAltAzCurve()
    }
    else if (id === 5) this.loadTonightAstro()
    else if (id === 6) {
      if (this.planetCalcMode === 1) this.loadPlanetPairDistance()
      else this.loadPlanetCalc()
    }
    else if (id === 7) {
      if (this.eclipseMode === 0) this.loadEclipses()
      else this.loadPlanetaryTransits()
    }
    else if (id === 8) this.loadAlmanac()
    else if (id === 9) this.loadMoonPhases()
  }

  private loadMoonPhases(): void {
    this.moonPhaseData = []
    this.callInteractive('getMoonPhases', JSON.stringify({ days: this.moonPhaseDays }), (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.moonPhases !== undefined) {
        this.moonPhaseData = r.moonPhases as Array<MoonPhaseItem>
      }
    })
  }

  private jumpToMoonPhase(item: MoonPhaseItem): void {
    if (item.jd === undefined || item.jd <= 0) return
    this.callInteractive('setJD', String(item.jd), () => { this.refreshState() })
  }

  private loadAlmanac(): void {
    this.almanacSeasons = []
    this.almanacSeasonYear = ''
    this.callInteractive('getAlmanac', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.almanac !== undefined) {
        const av: Object = r.almanac as Object
        const textValue = (name: string): string => av[name + 'Text'] !== undefined ? String(av[name + 'Text']) : (av[name] !== undefined ? String(av[name]) : '0')
        const data = new Map<string, string>()
        data.set('sunRise', textValue('sunRise'))
        data.set('sunTransit', textValue('sunTransit'))
        data.set('sunSet', textValue('sunSet'))
        data.set('moonRise', textValue('moonRise'))
        data.set('moonTransit', textValue('moonTransit'))
        data.set('moonSet', textValue('moonSet'))
        data.set('civilRise', textValue('civilRise'))
        data.set('civilSet', textValue('civilSet'))
        data.set('nauticalRise', textValue('nauticalRise'))
        data.set('nauticalSet', textValue('nauticalSet'))
        data.set('astronomicalRise', textValue('astronomicalRise'))
        data.set('astronomicalSet', textValue('astronomicalSet'))
        data.set('daylightHours', av['daylightHours'] !== undefined ? String(av['daylightHours']) : '')
        data.set('nightHours', av['nightHours'] !== undefined ? String(av['nightHours']) : '')
        data.set('moonPhase', av['moonPhase'] !== undefined ? String(av['moonPhase']) : '0')
        this.almanacData = data
        if (Array.isArray(av['seasonEvents'])) this.almanacSeasons = av['seasonEvents'] as Array<SeasonEvent>
        if (av['seasonYear'] !== undefined) this.almanacSeasonYear = String(av['seasonYear'])
      }
    })
  }

  private jumpToAlmanacSeason(event: SeasonEvent): void {
    if (event.jd === undefined || event.jd <= 0) return
    this.callInteractive('setJD', String(event.jd), (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.refreshState()
    })
  }

  private loadSkyCultureList(): void {
    this.callInteractive('getSkyCultureList', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.items !== undefined && Array.isArray(r.items)) {
        const arr = r.items as Array<Object>;
        const list: Array<SkyCultureItem> = [];
        for (let i = 0; i < arr.length; i++) {
          const obj = arr[i];
          const id = obj['id'] !== undefined ? obj['id'] as string : '';
          const name = obj['name'] !== undefined ? obj['name'] as string : id;
          list.push({ id: id, name: name });
        }
        this.skyCultureList = list;
        if (r.current !== undefined) {
          this.currentSkyCultureId = r.current as string;
        }
      }
    })
  }

  private selectSkyCulture(id: string): void {
    this.callInteractive('setSkyCulture', id, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.currentSkyCultureId = id;
      }
    })
  }

  private loadPluginList(): void {
    this.callInteractive('getPluginList', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.items !== undefined && Array.isArray(r.items)) {
        const arr = r.items as Array<Object>;
        const list: Array<PluginItem> = [];
        for (let i = 0; i < arr.length; i++) {
          const obj = arr[i];
          const id = obj['id'] !== undefined ? obj['id'] as string : '';
          const name = obj['name'] !== undefined ? obj['name'] as string : id;
          const loaded = obj['loaded'] !== undefined ? obj['loaded'] as boolean : false;
          const startup = obj['loadAtStartup'] !== undefined ? obj['loadAtStartup'] as boolean : false;
          list.push({ id: id, name: name, loaded: loaded, loadAtStartup: startup });
        }
        this.pluginList = list;
      }
    })
  }

  private togglePlugin(id: string, currentlyLoaded: boolean): void {
    if (currentlyLoaded) {
      this.callInteractive('unloadPlugin', id, (_r: StellariumBridgeResponse) => {
        this.loadPluginList();
      })
    } else {
      this.callInteractive('loadPlugin', id, (_r: StellariumBridgeResponse) => {
        this.loadPluginList();
      })
    }
  }

  
  
    private loadFov(): void {
    this.callInteractive('getFieldOfView', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && typeof r.fov === 'number') {
        this.currentFovText = (r.fov as number).toFixed(1) + '°'
        this.fovSliderValue = Math.round(r.fov as number)
      }
    })
  }

  private changeFovBySlider(val: number): void {
    this.callInteractive('setFOV', Math.round(val).toString(), (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'changeFovBySlider %{public}d ok=%{public}s', Math.round(val), r.ok === true ? '1' : '0')
    })
  }

private loadDSOCounts(): void {
    this.callInteractive('getDSOCounts', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.dsoCounts !== undefined) {
        const d = r.dsoCounts as Object;
        this.dsoTotalCount = (d['total'] as number) ?? 0;
        this.dsoGalaxies = (d['galaxies'] as number) ?? 0;
        this.dsoClusters = (d['clusters'] as number) ?? 0;
        this.dsoNebulae = (d['nebulae'] as number) ?? 0;
      }
    })
  }

private loadObjectInfo(): void {
    this.callInteractive('getObjectInfo', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.objectInfoData !== undefined) {
        const obj = r.objectInfoData as Object;
        const m = new Map<string, string>();
        if (obj['name'] !== undefined) m.set('name', obj['name'] as string);
        if (obj['nameI18'] !== undefined) m.set('nameI18', obj['nameI18'] as string);
        if (obj['type'] !== undefined) m.set('type', obj['type'] as string);
        if (obj['ra'] !== undefined) m.set('ra', (obj['ra'] as number).toFixed(4));
        if (obj['dec'] !== undefined) m.set('dec', (obj['dec'] as number).toFixed(4));
        if (obj['alt'] !== undefined) m.set('alt', (obj['alt'] as number).toFixed(2));
        if (obj['az'] !== undefined) m.set('az', (obj['az'] as number).toFixed(2));
        if (obj['magnitude'] !== undefined) m.set('magnitude', (obj['magnitude'] as number).toFixed(2));
        this.objectInfo = m;
      }
    })
  }
private loadPlanetPositions(): void {
    this.callInteractive('getObjectPositions', '', (r) => {
      if (r.ok === true && Array.isArray(r.items)) {
        this.planetPositions = (r.items as Array<PlanetPosition>).map((p: PlanetPosition) => ({
          name: p.name,
          altitude: Math.round(p.altitude * 10) / 10,
          azimuth: Math.round(p.azimuth * 10) / 10,
          magnitude: Math.round(p.magnitude * 100) / 100,
        }))
      }
    })
  }

  private loadHeliocentricPositions(): void {
    const options: HeliocentricPositionOptions = {
      includeSelectedMinor: this.hecIncludeSelectedMinor,
      includeBrightComets: this.hecIncludeBrightComets,
      cometMagnitudeLimit: this.hecCometMagnitudeLimit,
    }
    this.callInteractive('getHeliocentricEclipticPositions', JSON.stringify(options), (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.hecPositions !== undefined) {
        this.hecPositions = (r.hecPositions as Array<HeliocentricPosition>).map((p: HeliocentricPosition) => ({
          name: p.name,
          englishName: p.englishName,
          latitude: p.latitude,
          longitude: p.longitude,
          distanceAU: p.distanceAU,
          isComet: p.isComet === true,
          isSelectedMinor: p.isSelectedMinor === true,
        }))
        this.hecTime = r.hecTime ?? ''
      }
    })
  }

  private loadCelestialPositions(): void {
    const options: CelestialPositionOptions = {
      category: this.celestialPositionCategory,
      horizontal: this.celestialPositionHorizontal,
      magnitudeLimit: this.celestialPositionMagnitude,
      maximumRows: 80,
    }
    this.callInteractive('getCelestialPositions', JSON.stringify(options), (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.celestialPositions !== undefined) {
        this.celestialPositions = r.celestialPositions as Array<CelestialPosition>
        this.celestialPositionTime = r.positionTime ?? ''
      }
    })
  }

  private selectLandscape(id: string, name: string): void {
    this.callInteractive('setLandscape', id, () => {
      this.currentLandscapeId = id
      this.selectedLandscapeName = name
      this.landscapeDetailOpen = false
      this.refreshState()
    })
  }

  private setLandscapeFadeWithZoom(isOn: boolean): void {
    this.landscapeFadeWithZoom = isOn
    this.callInteractive('setLandscapeFadeWithZoom', isOn ? '1' : '0', () => {})
  }

  private changeLandscapeTransparency(val: number): void {
    const v = (val / 100).toFixed(2)
    // 手动透明度接管地景显示；不要再调用 setLandscapeFadeWithZoom(0)，
    // C++ 里该命令会重置透明度，导致滑条看起来“没反应”。
    this.landscapeFadeWithZoom = false
    this.callInteractive('setLandscapeUseTransparency', '1', () => {})
    this.callInteractive('setLandscapeTransparency', v, () => {})
  }

  private playScriptByName(filename: string): void {
    this.callInteractive('playScript', filename, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.flashHint(I18n.t('msg_script_running'))
      } else {
        hilog.error(0x0000, 'StellariumArkUI', 'playScript failed %{public}s err=%{public}s', filename, r.error ?? '')
        this.flashHint(I18n.t('msg_apply_failed'))
      }
    })
  }

  private fetchSuggestions(prefix: string): void {
    if (prefix.length < 1) { this.searchSuggestions = []; return }
    // 核心最多取 30 条（核心允许 1..50）；同时把中文/拼音别名命中的天体合并进建议。
    this.callInteractive('listMatchingObjects', prefix + '|30', (result) => {
      // Only apply if the query prefix is still current (user may have typed more).
      if (this.searchText.trim() !== prefix) { return }
      const map: Record<string, SearchSug> = {}
      if (Array.isArray(result.items)) {
        const keys = Array.isArray(result.keys) ? result.keys as string[] : []
        const items = result.items as string[]
        for (let i = 0; i < items.length; i++) {
          const display = items[i]
          const key = (keys[i] && keys[i].length > 0) ? keys[i] : display
          if (!map[key]) { map[key] = { zh: this.celestialTitle(display, key), en: key } }
        }
      }
      // 别名模糊命中（中文/拼音/英文子串），补足核心只做“词首前缀”的不足。
      for (const a of this.aliasHits(prefix)) {
        if (!map[a.en]) { map[a.en] = { zh: a.zh, en: a.en } }
      }
      const arr = Object.keys(map).map((k) => map[k])
      arr.sort((x, y) => x.zh.localeCompare(y.zh, 'zh'))
      this.searchSuggestions = arr.slice(0, 30)
    })
  }

  // 搜索建议的显示名可能是当前语言的译名；en 始终是 C++ 桥返回的稳定检索键。
  // 只有核心确认选中成功时 searchObject() 才会收起手机面板。
  private selectSearchSuggestion(suggestion: SearchSug): void {
    this.searchObject(suggestion.en)
  }

  // Keep constellation navigation clear and light: labels and lines, no global boundaries.
  private openConstellationGuide(name: string, moduleId: string = 'ConstellationMgr'): void {
    this.flashHint('已开启星座名称和连线，正在定位' + this.zhNameOf(name))
    this.callInteractive('setActionChecked', 'actionShow_Constellation_Boundaries|0', () => {
      this.constellationBoundaries = false
      this.callInteractive('setActionChecked', 'actionShow_Constellation_Lines|1', () => {
        this.constellationLines = true
        this.callInteractive('setActionChecked', 'actionShow_Constellation_Labels|1', () => {
          this.constellationLabels = true
          this.searchObject(name, moduleId)
        })
      })
    })
  }

  private loadCategoryObjects(category: string): void {
    this.searchCategory = category
    const moduleIdMap: Record<string, string> = {
      'planet': 'SolarSystem:planet',
      'moon': 'SolarSystem:moon',
      'star': 'StarMgr',
      'variable': 'StarMgr:1',
      'comet': 'SolarSystem:comet',
      'asteroid': 'SolarSystem:asteroid',
      'constellation': 'ConstellationMgr',
      'galaxy': 'NebulaMgr:0',
      'cluster': 'NebulaMgr:5',
      'nebula': 'NebulaMgr:200',
      'messier': 'NebulaMgr:100',
    }
    const moduleId = moduleIdMap[category] || ''
    this.categoryModuleId = moduleId
    this.categoryObjects = []
    this.categoryObjectCount = 0
    this.categoryLoadedCount = 0
    this.categoryLoading = false
    this.categoryLoadFailed = false
    this.categoryHasMore = false
    this.categoryOffset = 0
    this.categoryRequestSerial += 1
    this.loadMoreCategoryObjects()
  }

  // Catalogs may contain many thousands of entries. Request small pages so the
  // first page is usable immediately and append more only when the user scrolls.
  private loadMoreCategoryObjects(): void {
    if (this.categoryLoading || !this.categoryModuleId.length || (!this.categoryHasMore && this.categoryOffset > 0)) {
      return
    }
    const serial = this.categoryRequestSerial
    const offset = this.categoryOffset
    const category = this.searchCategory
    this.categoryLoading = true
    this.categoryLoadFailed = false
    this.callNativeWhenReady('listObjects', this.categoryModuleId + '|' + this.CATEGORY_PAGE_SIZE + '|' + offset, (result) => {
      if (serial !== this.categoryRequestSerial) { return }
      const items = Array.isArray(result.items) ? result.items as string[] : []
      const keys = Array.isArray(result.keys) ? result.keys as string[] : []
      const seen: Record<string, boolean> = {}
      for (const existing of this.categoryObjects) {
        if (existing.name.length > 0) { seen[existing.name] = true }
      }
      const browse: NameItem[] = []
      for (let i = 0; i < items.length; i++) {
        const key = (keys[i] && keys[i].length > 0) ? keys[i] : items[i]
        if (key.length === 0 || seen[key]) { continue }
        seen[key] = true
        // Keep the stable catalog ID for native selection, while translating
        // familiar names through the same alias table used by normal search.
        const title = this.celestialTitle(items[i], key)
        browse.push({ name: key, zh: title, subtitle: this.celestialSubtitle(title, key) })
      }
      if (browse.length === 0 && offset === 0) {
        for (const item of ALIAS_LIST) {
          let includeItem = false
          if (category === 'planet') {
            includeItem = item.type === 'planet' || item.type === 'moon'
          } else if (category === 'moon') {
            includeItem = item.type === 'moon'
          } else if (category === 'star') {
            includeItem = item.type === 'star'
          } else if (category === 'constellation') {
            includeItem = item.type === category
          }
          if (includeItem) { browse.push({ name: item.en, zh: item.zh }) }
        }
      }
      const combined = this.categoryObjects.concat(browse)
      this.categoryObjects = combined
      this.categoryLoadedCount = combined.length
      this.categoryObjectCount = typeof result.count === 'number' && result.count > 0 ? result.count : combined.length
      this.categoryOffset = offset + items.length
      this.categoryHasMore = result.hasMore === true && items.length > 0
      this.categoryLoading = false
      this.categoryLoadFailed = false
    }, 0, 100, 60, (_failure) => {
      if (serial !== this.categoryRequestSerial) { return }
      this.categoryLoading = false
      this.categoryLoadFailed = true
      this.categoryHasMore = false
    })
  }

  private stopTracking(): void {
    this.callInteractive('setTracking', '0', () => { this.trackingText = 'Off' })
  }

  private setSkyCulture(name: string): void {
    this.callInteractive('setSkyCulture', name, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.flashHint(I18n.t('msg_apply_failed'))
        return
      }
      const culture = r.culture && r.culture.length > 0 ? r.culture : name
      this.currentSkyCulture = culture
      this.flashHint(I18n.t('i0068').replace('%s', culture))
    })
  }

  private setTimeRate(rate: number): void {
    // 速率命令本身不需要结果。此前这里紧跟一次 getState，旧的异步状态会
    // 短暂覆盖刚刚更新的文本，造成“倒带/快进按钮闪一下”的错觉。
    this.callNativeFire('setTimeRate', rate.toString())
  }

  // ===== 时间速率档位系统 =====
  // Stellarium 内部单位：Julian days per second (JD/s)
  // 1 JD = 86400 ��，所以 1x 实时 = 1/86400 ≈ 1.1574e-5 JD/s
  // 档位表：索引 0=暂停, 1=1x, 2=2x, 3=10x, 4=1分/秒, 5=1时/秒, 6=1天/秒, 7=10天/秒
  // 负索引 = 倒带：-1=-1x, -2=-1时/秒, -3=-1天/秒
  private readonly SPEED_STEPS: number[] = [
    -864000.0 / 86400.0,   // -10: 倒带 极速(1天/秒反向)
    -360.0 / 86400.0,      // -9:  倒带 快进(1时/秒反向)
    -60.0 / 86400.0,       // -8:  倒带(1分/秒反向)
    -10.0 / 86400.0,       // -7:  倒带 10x
    -2.0 / 86400.0,        // -6:  倒带 2x
    -1.0 / 86400.0,        // -5:  倒带 1x
    0,                      //  0:  停止
    1.0 / 86400.0,         //  1:  实时 1x
    2.0 / 86400.0,         //  2:  2x
    10.0 / 86400.0,        //  3:  10x
    60.0 / 86400.0,        //  4:  1分/秒
    360.0 / 86400.0,       //  5:  1时/秒
    86400.0 / 86400.0,     //  6:  1天/秒
    864000.0 / 86400.0,    //  7:  10天/秒
  ]
  // SPEED_STEPS 的"零点"索引（停止）和"实时"索引
  private static readonly SPEED_IDX_STOP = 6
  private static readonly SPEED_IDX_REALTIME = 7

  // 连续时间轴：拖动范围为前后 12 小时且精确到秒。跨天跳转由
  // 面板下方的 +/-12h 快捷操作承担，避免小滑块退化成“按天跳”。
  private readonly timeTicks: TimeTick[] = [
    { label: '12小时前', value: -43200, major: true },
    { label: '6小时前', value: -21600, major: false },
    { label: '1小时前', value: -3600, major: false },
    { label: '此刻', value: 0, major: true },
    { label: '1小时后', value: 3600, major: false },
    { label: '6小时后', value: 21600, major: false },
    { label: '12小时后', value: 43200, major: true }
  ]
  private tickPercent(value: number): number {
    return ((value + 43200) / 86400) * 100
  }

  /** Apply speed at given step index. Clamps to valid range. */
  private applySpeedStep(index: number): void {
    const len: number = this.SPEED_STEPS.length
    // 映射到有效范围（含负索引倒带）
    const idx: number = Math.max(0, Math.min(len - 1, index))
    const rate: number = this.SPEED_STEPS[idx]
    this.timeSpeedIndex = idx
    this.pendingTimeRate = rate
    this.pendingTimeRateUntilMs = Date.now() + 500
    this.setTimeRate(rate)
    this.timeRateText = this.formatRate(rate)
  }

  /** 将原生返回的速率映射回时间档位，保证面板重建后按钮状态不会丢失。 */
  private syncTimeRateState(rate: number): void {
    const now = Date.now()
    if (!Number.isNaN(this.pendingTimeRate)) {
      const rateMatchesPending = Math.abs(rate - this.pendingTimeRate) < 1e-9
      if (!rateMatchesPending && now < this.pendingTimeRateUntilMs) {
        return
      }
      this.pendingTimeRate = Number.NaN
      this.pendingTimeRateUntilMs = 0
    }
    this.timeRateText = this.formatRate(rate)
    let nearestIndex = 0
    let nearestDistance = Number.MAX_VALUE
    for (let i = 0; i < this.SPEED_STEPS.length; i++) {
      const candidate = this.SPEED_STEPS[i]
      const distance = Math.abs(candidate - rate)
      if (distance < nearestDistance) {
        nearestDistance = distance
        nearestIndex = i
      }
    }
    this.timeSpeedIndex = nearestIndex
  }

  /** Speed up one step. */
  private speedUp(): void {
    this.applySpeedStep(this.timeSpeedIndex + 1)
  }

  /** Slow down one step (can go into reverse). */
  private speedDown(): void {
    this.applySpeedStep(this.timeSpeedIndex - 1)
  }

  /** Toggle pause: remember current non-zero speed, restore on unpause. */
  private togglePause(): void {
    if (this.timeSpeedIndex === 6) { // SPEED_IDX_STOP
      // Resume: restore last speed or default to 1x
      const resumeIdx = this._lastNonZeroSpeedIndex > 0 && this._lastNonZeroSpeedIndex !== 6 ? this._lastNonZeroSpeedIndex : 7
      this.applySpeedStep(resumeIdx)
    } else {
      // Pause: remember current speed
      this._lastNonZeroSpeedIndex = this.timeSpeedIndex
      this.applySpeedStep(6) // SPEED_IDX_STOP
    }
  }
  private _lastNonZeroSpeedIndex: number = 7

  /** 更新时间轴当前位置的自然语言标签。 */
  private updateScrubberLabel(secondOffset: number): void {
    const seconds = Math.round(secondOffset)
    if (seconds === 0) {
      this.scrubberLabel = '此刻'
      return
    }
    const sign = seconds > 0 ? '+' : '-'
    const abs = Math.abs(seconds)
    if (abs < 60) {
      this.scrubberLabel = sign + abs.toString() + '秒'
    } else if (abs < 3600) {
      const minutes = Math.floor(abs / 60)
      const remainSeconds = abs % 60
      this.scrubberLabel = sign + minutes.toString() + '分' + (remainSeconds > 0 ? remainSeconds.toString() + '秒' : '')
    } else {
      const hours = Math.floor(abs / 3600)
      const minutes = Math.floor((abs % 3600) / 60)
      this.scrubberLabel = sign + hours.toString() + '时' + (minutes > 0 ? minutes.toString() + '分' : '')
    }
  }

  /** 开始一次时间轴交互，并固定这次交互的时间基准。 */
  private beginScrubberInteraction(secondOffset: number): void {
    this.scrubberPendingOffset = Math.round(secondOffset)
    this.updateScrubberLabel(this.scrubberPendingOffset)
    if (this.scrubberReferenceJd > 0) {
      this.sendScrubberTime(true)
      return
    }
    if (this.scrubberAnchorPending) {
      return
    }
    this.scrubberAnchorPending = true
    this.callInteractive('getSimulationTime', '', (r: StellariumBridgeResponse) => {
      this.scrubberAnchorPending = false
      if (r.ok === true && r.jd !== undefined) {
        // Keep the current slider position stable while establishing its centre.
        this.scrubberReferenceJd = Number(r.jd) - this.scrubberPendingOffset / 86400.0
        this.sendScrubberTime(true)
      }
    })
  }

  /** 把当前偏移应用到固定基准；移动中限流，松手时强制发送最终值。 */
  private sendScrubberTime(force: boolean = false): void {
    if (this.scrubberReferenceJd <= 0) {
      return
    }
    const now = Date.now()
    if (!force && now - this.scrubberLastSendMs < 90) {
      return
    }
    this.scrubberLastSendMs = now
    const targetJd = this.scrubberReferenceJd + this.scrubberPendingOffset / 86400.0
    // setTimeToJD 会把原生模拟速率设为 0，避免用户拖动时星图仍继续走时。
    this.callNativeFire('setTimeToJD', targetJd.toFixed(6))
    this.timeSpeedIndex = WindowNativeNode.SPEED_IDX_STOP
    this.pendingTimeRate = 0
    this.pendingTimeRateUntilMs = Date.now() + 500
    this.timeRateText = this.formatRate(0)
    if (force) {
      setTimeout(() => { this.refreshSimTimeLight() }, 140)
    }
  }

  /** 时间轴值变化：所有值都相对同一个按下瞬间，绝不累加到前一个结果。 */
  private applyScrubber(secondOffset: number, mode: SliderChangeMode): void {
    const offset = Math.round(secondOffset)
    this.scrubberValue = offset
    this.scrubberPendingOffset = offset
    this.updateScrubberLabel(offset)
    if (mode === SliderChangeMode.Begin) {
      this.scrubberInteracting = true
    }
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Click || this.scrubberReferenceJd <= 0) {
      this.beginScrubberInteraction(offset)
      return
    }
    const finished = mode === SliderChangeMode.End
    this.sendScrubberTime(finished)
    if (finished || mode === SliderChangeMode.Click) {
      this.scrubberInteracting = false
    }
  }

  private syncScrubberToSimulation(jd: number): void {
    if (this.scrubberReferenceJd <= 0) {
      this.scrubberReferenceJd = Date.now() / 86400000.0 + 2440587.5
    }
    let offset = Math.round((jd - this.scrubberReferenceJd) * 86400.0)
    // A timeline is a local control surface, not a calendar with a hard wall.
    // Re-centre before the thumb reaches the end so pause and reverse dragging
    // continue from the visible simulated time instead of snapping back to 12h.
    if (Math.abs(offset) > 38880) {
      this.scrubberReferenceJd = jd
      offset = 0
    }
    this.scrubberValue = offset
    this.updateScrubberLabel(offset)
  }

  private resetScrubberToRealtime(): void {
    this.scrubberInteracting = false
    this.scrubberAnchorPending = false
    this.scrubberReferenceJd = 0
    this.scrubberPendingOffset = 0
    this.scrubberValue = 0
    this.updateScrubberLabel(0)
  }

  private timeWheelDateAtOffset(offset: number): Date {
    const baseMs = this.timeWheelTrackBaseMs > 0
      ? this.timeWheelTrackBaseMs
      : Date.UTC(this.timeWheelYear, this.timeWheelMonth - 1, this.timeWheelDay,
        this.timeWheelHour, this.timeWheelMinute, this.timeWheelSecond)
    const local = new Date(baseMs)
    this.shiftTimeWheelDate(local, offset)
    return local
  }

  private shiftTimeWheelDate(local: Date, steps: number): void {
    if (this.timeWheelUnit === 'year') { local.setUTCFullYear(local.getUTCFullYear() + steps) }
    else if (this.timeWheelUnit === 'month') { local.setUTCMonth(local.getUTCMonth() + steps) }
    else if (this.timeWheelUnit === 'day') { local.setUTCDate(local.getUTCDate() + steps) }
    else if (this.timeWheelUnit === 'hour') { local.setUTCHours(local.getUTCHours() + steps) }
    else if (this.timeWheelUnit === 'minute') { local.setUTCMinutes(local.getUTCMinutes() + steps) }
    else { local.setUTCSeconds(local.getUTCSeconds() + steps) }
  }

  private timeWheelDateAtFraction(baseMs: number, steps: number): Date {
    const wholeSteps = steps >= 0 ? Math.floor(steps) : Math.ceil(steps)
    const fractionalSteps = steps - wholeSteps
    const local = new Date(baseMs)
    this.shiftTimeWheelDate(local, wholeSteps)
    if (fractionalSteps === 0) { return local }
    const next = new Date(local.getTime())
    this.shiftTimeWheelDate(next, fractionalSteps > 0 ? 1 : -1)
    if (this.isCalendarTimeWheel()) {
      const localDateMs = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate())
      const nextDateMs = Date.UTC(next.getUTCFullYear(), next.getUTCMonth(), next.getUTCDate())
      const dayOffset = Math.round((nextDateMs - localDateMs) * Math.abs(fractionalSteps) / 86400000.0)
      local.setUTCDate(local.getUTCDate() + dayOffset)
      return local
    }
    return new Date(local.getTime() + (next.getTime() - local.getTime()) * Math.abs(fractionalSteps))
  }

  private isCalendarTimeWheel(): boolean {
    return this.timeWheelUnit === 'year' || this.timeWheelUnit === 'month' || this.timeWheelUnit === 'day'
  }

  private timeWheelMajorInterval(): number {
    if (this.timeWheelUnit === 'year') { return 5 }
    if (this.timeWheelUnit === 'month') { return 3 }
    return 5
  }

  private timeWheelTickValue(offset: number): string {
    const local = this.timeWheelDateAtOffset(offset)
    if (this.timeWheelUnit === 'year') { return local.getUTCFullYear().toString() }
    if (this.timeWheelUnit === 'month') { return (local.getUTCMonth() + 1).toString().padStart(2, '0') + '月' }
    if (this.timeWheelUnit === 'day') { return local.getUTCDate().toString().padStart(2, '0') + '日' }
    if (this.timeWheelUnit === 'hour') { return local.getUTCHours().toString().padStart(2, '0') + '时' }
    if (this.timeWheelUnit === 'minute') { return local.getUTCMinutes().toString().padStart(2, '0') + '分' }
    return local.getUTCSeconds().toString().padStart(2, '0') + '秒'
  }

  private timeWheelTickLabel(offset: number): string {
    if (offset % this.timeWheelMajorInterval() !== 0) { return '' }
    return this.timeWheelTickValue(offset)
  }

  private timeWheelCurrentLabel(): string {
    if (this.timeWheelUnit === 'year') { return this.timeWheelYear.toString() }
    if (this.timeWheelUnit === 'month') { return this.timeWheelMonth.toString().padStart(2, '0') + '月' }
    if (this.timeWheelUnit === 'day') { return this.timeWheelDay.toString().padStart(2, '0') + '日' }
    if (this.timeWheelUnit === 'hour') { return this.timeWheelHour.toString().padStart(2, '0') + '时' }
    if (this.timeWheelUnit === 'minute') { return this.timeWheelMinute.toString().padStart(2, '0') + '分' }
    return this.timeWheelSecond.toString().padStart(2, '0') + '秒'
  }

  private refreshTimeWheelTicks(): void {
    const labels: string[] = []
    for (let index = 0; index <= this.timeWheelCenterTick * 2; index++) {
      labels.push(this.timeWheelTickLabel(index - this.timeWheelCenterTick))
    }
    this.timeWheelTickLabels = labels
  }

  private isTimeWheelMajorTick(index: number): boolean {
    return (index - this.timeWheelCenterTick) % this.timeWheelMajorInterval() === 0
  }

  private timeWheelVisibleTickOffset(index: number): number {
    return index - this.timeWheelCenterTick + this.timeWheelAppliedSteps
  }

  private timeWheelVisibleTickLabel(index: number): string {
    const offset = this.timeWheelVisibleTickOffset(index)
    if (!this.isTimeWheelVisibleMajorTick(index) &&
      this.timeWheelTickDistance(index) > this.timeWheelTickSpacing * 4.5) {
      return ''
    }
    return this.timeWheelTickValue(offset)
  }

  private isTimeWheelVisibleMajorTick(index: number): boolean {
    return this.timeWheelVisibleTickOffset(index) % this.timeWheelMajorInterval() === 0
  }

  private timeWheelTickDistance(index: number): number {
    return Math.abs((index - this.timeWheelCenterTick) * this.timeWheelTickSpacing + this.timeWheelVisualOffset)
  }

  private isTimeWheelTickCentered(index: number): boolean {
    const closestIndex = this.timeWheelCenterTick - Math.round(this.timeWheelVisualOffset / this.timeWheelTickSpacing)
    return index === closestIndex
  }

  private timeWheelTickScale(index: number): number {
    const focus = Math.max(0, 1 - this.timeWheelTickDistance(index) / (this.timeWheelTickSpacing * 3))
    return 1 + focus * 0.22
  }

  private timeWheelTickOpacity(index: number): number {
    const focus = Math.max(0, 1 - this.timeWheelTickDistance(index) / (this.timeWheelTickSpacing * 4.5))
    const baseOpacity = this.isTimeWheelVisibleMajorTick(index) ? 0.12 : 0.04
    return focus * (baseOpacity + (1 - baseOpacity) * focus)
  }

  private timeWheelTickBlur(index: number): number {
    const distance = this.timeWheelTickDistance(index)
    if (distance <= this.timeWheelTickSpacing / 2) { return 0 }
    return Math.min(1.2, (distance / this.timeWheelTickSpacing - 0.5) * 0.42)
  }

  private timeWheelTickHeight(index: number): number {
    const focus = Math.max(0, 1 - this.timeWheelTickDistance(index) / (this.timeWheelTickSpacing * 3))
    const baseHeight = this.isTimeWheelVisibleMajorTick(index) ? 17 : 8
    return baseHeight + (31 - baseHeight) * focus
  }

  private selectTimeWheelUnit(unit: string): void {
    this.finishTimeWheelTransition()
    this.timeWheelUnit = unit
    this.timeWheelDragging = false
    this.rebaseTimeWheelTrack()
  }

  private applyTimeWheelDate(local: Date, refreshTicks: boolean, sendNative: boolean): void {
    this.timeWheelLastInputMs = Date.now()
    this.timeWheelYear = local.getUTCFullYear()
    this.timeWheelMonth = local.getUTCMonth() + 1
    this.timeWheelDay = local.getUTCDate()
    this.timeWheelHour = local.getUTCHours()
    this.timeWheelMinute = local.getUTCMinutes()
    this.timeWheelSecond = local.getUTCSeconds()
    if (refreshTicks) { this.refreshTimeWheelTicks() }
    if (sendNative) {
      const targetJd = local.getTime() / 86400000.0 + 2440587.5 - this.utcOffsetHours / 24.0
      this.callNativeFire('setTimeToJD', targetJd.toFixed(8))
      this.timeWheelLastNativePushMs = Date.now()
    }
  }

  private setTimeWheelStopped(): void {
    this.timeSpeedIndex = WindowNativeNode.SPEED_IDX_STOP
    this.pendingTimeRate = 0
    this.pendingTimeRateUntilMs = Date.now() + 500
    this.timeRateText = this.formatRate(0)
  }

  private startTimeWheelTransition(refreshTicks: boolean): void {
    if (this.timeWheelTransitionTimer !== 0) { return }
    this.timeWheelTransitionTimer = setInterval(() => {
      const current = new Date(Date.UTC(this.timeWheelYear, this.timeWheelMonth - 1, this.timeWheelDay,
        this.timeWheelHour, this.timeWheelMinute, this.timeWheelSecond))
      const target = new Date(this.timeWheelTargetMs)
      const deltaMs = target.getTime() - current.getTime()
      if (Math.abs(deltaMs) <= 1000) {
        this.applyTimeWheelDate(target, refreshTicks, true)
        clearInterval(this.timeWheelTransitionTimer)
        this.timeWheelTransitionTimer = 0
        this.timeWheelTargetMs = 0
        return
      }
      const next = new Date(current.getTime())
      if (this.isCalendarTimeWheel()) {
        const days = Math.ceil(Math.abs(deltaMs) / 86400000.0 / 3.0)
        next.setUTCDate(next.getUTCDate() + (deltaMs > 0 ? days : -days))
      } else {
        const seconds = Math.ceil(Math.abs(deltaMs) / 1000.0 / 3.0)
        next.setUTCSeconds(next.getUTCSeconds() + (deltaMs > 0 ? seconds : -seconds))
      }
      const sendNative = Date.now() - this.timeWheelLastNativePushMs >= 96
      this.applyTimeWheelDate(next, refreshTicks, sendNative)
    }, 12)
  }

  private finishTimeWheelTransition(): void {
    if (this.timeWheelTransitionTimer === 0) { return }
    clearInterval(this.timeWheelTransitionTimer)
    this.timeWheelTransitionTimer = 0
    this.applyTimeWheelDate(new Date(this.timeWheelTargetMs), true, true)
    this.timeWheelTargetMs = 0
  }

  private advanceTimeWheel(steps: number, refreshTicks: boolean = true): void {
    if (steps === 0) { return }
    const local = this.timeWheelTargetMs > 0
      ? new Date(this.timeWheelTargetMs)
      : new Date(Date.UTC(this.timeWheelYear, this.timeWheelMonth - 1, this.timeWheelDay,
      this.timeWheelHour, this.timeWheelMinute, this.timeWheelSecond))
    if (this.timeWheelUnit === 'year') { local.setUTCFullYear(local.getUTCFullYear() + steps) }
    else if (this.timeWheelUnit === 'month') { local.setUTCMonth(local.getUTCMonth() + steps) }
    else if (this.timeWheelUnit === 'day') { local.setUTCDate(local.getUTCDate() + steps) }
    else if (this.timeWheelUnit === 'hour') { local.setUTCHours(local.getUTCHours() + steps) }
    else if (this.timeWheelUnit === 'minute') { local.setUTCMinutes(local.getUTCMinutes() + steps) }
    else { local.setUTCSeconds(local.getUTCSeconds() + steps) }
    this.setTimeWheelStopped()
    if (this.timeWheelUnit === 'year' || this.timeWheelUnit === 'month' ||
      this.timeWheelUnit === 'hour' || this.timeWheelUnit === 'minute') {
      this.timeWheelTargetMs = local.getTime()
      this.startTimeWheelTransition(refreshTicks)
      return
    }
    this.applyTimeWheelDate(local, refreshTicks, true)
  }

  private timeWheelVelocityMultiplier(speed: number): number {
    let baseMultiplier = 1.0
    if (this.timeWheelUnit === 'year') { baseMultiplier = 0.07 }
    else if (this.timeWheelUnit === 'month') { baseMultiplier = 0.08 }
    else if (this.timeWheelUnit === 'day') { baseMultiplier = 0.2 }
    else if (this.timeWheelUnit === 'hour') { baseMultiplier = 0.06 }
    else if (this.timeWheelUnit === 'minute') { baseMultiplier = 0.25 }
    if (speed < 0.35) { return baseMultiplier }
    if (speed < 0.8) { return baseMultiplier * 2.0 }
    if (speed < 1.4) { return baseMultiplier * 4.0 }
    return baseMultiplier * 8.0
  }

  private rebaseTimeWheelTrack(): void {
    this.timeWheelDragCarry = 0
    this.timeWheelAppliedSteps = 0
    this.timeWheelGestureTickOffset = 0
    this.timeWheelVisualOffset = 0
    this.timeWheelTrackBaseMs = Date.UTC(this.timeWheelYear, this.timeWheelMonth - 1,
      this.timeWheelDay, this.timeWheelHour, this.timeWheelMinute, this.timeWheelSecond)
    this.refreshTimeWheelTicks()
  }

  private rebaseTimeWheelTrackAtCenter(): void {
    const tickShift = Math.round(this.timeWheelVisualOffset / this.timeWheelTickSpacing)
    if (tickShift === 0) { return }
    this.timeWheelVisualOffset -= tickShift * this.timeWheelTickSpacing
    this.timeWheelDragCarry = this.timeWheelVisualOffset
    this.timeWheelAppliedSteps -= tickShift
    this.timeWheelGestureTickOffset -= tickShift
  }

  private handleTimeWheelTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) { return }
    const point = points[0]
    if (event.type === TouchType.Down) {
      this.finishTimeWheelTransition()
      this.timeWheelDragging = true
      this.timeWheelLastTouchX = point.x
      this.timeWheelLastTouchMs = Date.now()
      this.timeWheelLastInputMs = Date.now()
      this.timeWheelGestureBaseMs = Date.UTC(this.timeWheelYear, this.timeWheelMonth - 1,
        this.timeWheelDay, this.timeWheelHour, this.timeWheelMinute, this.timeWheelSecond)
      this.timeWheelGestureSteps = 0
      this.timeWheelGestureTickOffset = this.timeWheelAppliedSteps
      this.timeWheelDragCarry = this.timeWheelVisualOffset
      this.rebaseTimeWheelTrackAtCenter()
      this.setTimeWheelStopped()
      return
    }
    if (event.type === TouchType.Move && this.timeWheelDragging) {
      const now = Date.now()
      const delta = point.x - this.timeWheelLastTouchX
      const elapsedMs = Math.max(1, now - this.timeWheelLastTouchMs)
      this.timeWheelLastTouchX = point.x
      this.timeWheelLastTouchMs = now
      const speed = Math.abs(delta) / elapsedMs
      const requestedStepDelta = -delta * this.timeWheelVelocityMultiplier(speed) / this.timeWheelTickSpacing
      const stepDelta = requestedStepDelta
      const effectiveDelta = -stepDelta * this.timeWheelTickSpacing
      this.timeWheelDragCarry += effectiveDelta
      this.timeWheelGestureSteps += stepDelta
      this.timeWheelVisualOffset = this.timeWheelDragCarry
      const local = this.timeWheelDateAtFraction(this.timeWheelGestureBaseMs, this.timeWheelGestureSteps)
      const sendNative = now - this.timeWheelLastNativePushMs >= 64
      this.applyTimeWheelDate(local, false, sendNative)
      if (Math.abs(this.timeWheelVisualOffset) >= this.timeWheelTickSpacing * 8) {
        this.rebaseTimeWheelTrackAtCenter()
      }
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.timeWheelDragging = false
      if (this.timeWheelGestureBaseMs > 0) {
        this.applyTimeWheelDate(this.timeWheelDateAtFraction(this.timeWheelGestureBaseMs,
          this.timeWheelGestureSteps), false, true)
      }
    }
  }

  private syncTimeWheelFromSimulation(jd: number): void {
    // ArkUI may emit Begin without a matching End while the panel is built.
    // Guard only a short interval after actual user input so the display never
    // becomes permanently detached from the simulated clock.
    if (this.timeWheelDragging || Date.now() - this.timeWheelLastInputMs < 800) { return }
    const local = new Date((jd + this.utcOffsetHours / 24.0 - 2440587.5) * 86400000.0)
    this.timeWheelYear = local.getUTCFullYear()
    this.timeWheelMonth = local.getUTCMonth() + 1
    this.timeWheelDay = local.getUTCDate()
    this.timeWheelHour = local.getUTCHours()
    this.timeWheelMinute = local.getUTCMinutes()
    this.timeWheelSecond = local.getUTCSeconds()
    if (Math.abs(this.timeWheelVisualOffset) < 0.1) {
      this.timeWheelTrackBaseMs = local.getTime()
      this.refreshTimeWheelTicks()
    }
  }

  private zoomStep(factor: number): void {
    hilog.info(0x0000, 'StellariumArkUI', 'zoomStep factor=%{public}s', factor.toString())
    // Discrete zoom is a direct view command. Do not route it through the
    // result-polling cache, which can make a tap appear to do nothing.
    this.callNativeFire('zoomStep', factor.toString())
    setTimeout(() => {
      this.refreshState()
      this.callInteractive('getFieldOfView', '', (r: StellariumBridgeResponse) => {
        if (r.ok === true && r.fov !== undefined) {
          const fovDeg = r.fov as number
          this.currentFovText = fovDeg.toFixed(1) + '°'
          this.flashHint('视场 ' + this.currentFovText)
        }
      })
    }, 450)
  }

  private advanceTime(hours: number): void {
    this.callInteractive('advanceTime', hours.toString(), () => { this.refreshTimeNow() })
    this.flashHint((hours > 0 ? I18n.t('i0044') : '') + hours.toString() + ' h')
  }

  private dateToJD(year: number, month: number, day: number, hour: number, minute: number): number {
    if (month <= 2) {
      year -= 1
      month += 12
    }
    const A = Math.floor(year / 100)
    const B = 2 - A + Math.floor(A / 4)
    const jdDay = Math.floor(365.25 * (year + 4716)) + Math.floor(30.6001 * (month + 1)) + day + B - 1524.5
    return jdDay + hour / 24.0 + minute / 1440.0
  }

  private applyManualTime(): void {
    const jd = this.dateToJD(this.manualYear, this.manualMonth, this.manualDay, this.manualHour, this.manualMinute)
    this.callInteractive('setJD', jd.toFixed(6), (r: StellariumBridgeResponse) => {
      this.refreshState()
      this.flashHint(String(this.manualMonth).padStart(2, '0') + '-' + String(this.manualDay).padStart(2, '0') + ' ' + String(this.manualHour).padStart(2, '0') + ':' + String(this.manualMinute).padStart(2, '0'))
    })
  }

  private setLanguage(lang: string): void {
    // Map to I18n code (handle codes like pt_BR, zh_HK that C++ may not support)
    const i18nCode = I18n.fromStellariumCode(lang)
    // 同步 I18n 模块（触发 AppStorage 变更 → UI 重渲染）
    I18n.setLanguage(i18nCode)
    // The panel contains many static text nodes. Updating this local storage
    // link and the panel identity makes the open panel rebuild immediately,
    // rather than waiting for it to be closed and opened again.
    this.i18nLang = i18nCode
    this.selectedLanguage = lang
    this.panelContentKey++
    // 持久化语言选择
    try {
      const settings = AppStorage.get<string>('stellariumSettings')
      const s: Record<string, Object> = settings ? JSON.parse(settings) as Record<string, Object> : {} as Record<string, Object>
      s.selectedLanguage = lang
      AppStorage.setOrCreate('stellariumSettings', JSON.stringify(s))
    } catch (e) { }
    // 立即提示，不等 C++ 确认（避免阻塞触摸和星图交互）
    this.flashHint(I18n.t('msg_lang_switched_done') + ': ' + (LANGUAGE_DISPLAY[lang] ?? LANGUAGE_DISPLAY[i18nCode] ?? lang))
    // 延迟同步 C++ 侧语言，避免同步 N-API 调用阻塞 UI 线程导致星图无响应。
    // 这里不能 refreshState：该全量状态刷新会与选中对象的安全居中动画竞争，
    // 表现为星图先上移又下移。
    setTimeout(() => {
      this.callNativeWhenReady('setLanguage', lang, () => {}, 0, 300, 3)
    }, 50)
  }

  private syncManualTimeFromState(): void {
    this.callInteractive('getState', '', (result) => {
    if (result.jd !== undefined) {
      const jd = result.jd as number
      const z = Math.floor(jd + 0.5)
      const f = jd + 0.5 - z
      let A = z
      if (z >= 2299161) {
        const alpha = Math.floor((z - 1867216.25) / 36524.25)
        A = z + 1 + alpha - Math.floor(alpha / 4)
      }
      const B = A + 1524
      const C = Math.floor((B - 122.1) / 365.25)
      const D = Math.floor(365.25 * C)
      const E = Math.floor((B - D) / 30.6001)
      const day = B - D - Math.floor(30.6001 * E)
      const month = E < 14 ? E - 1 : E - 13
      const year = month > 2 ? C - 4716 : C - 4715
      const dayFraction = f * 24
      const hour = Math.floor(dayFraction)
      const minute = Math.floor((dayFraction - hour) * 60)
      this.manualYear = year
      this.manualMonth = month
      this.manualDay = day
      this.manualHour = hour
      this.manualMinute = minute
    }
    })
  }

  private flashHint(text: ResourceStr): void {
    this.actionHint = text
    if (this.hintTimer !== 0) {
      clearTimeout(this.hintTimer)
    }
    this.hintTimer = setTimeout(() => {
      this.actionHint = ''
    }, 1600) as number
  }

  private lx200Payload(): string {
    return this.lx200Host.trim() + '|' + this.lx200Port.trim()
  }

  private applyLx200Result(result: StellariumBridgeResponse): void {
    if (result.ok === true) {
      const target = result.target && result.target.length > 0 ? result.target : I18n.t('m_telescope_target_default')
      const mode = result.mode === 'sync' ? I18n.t('m_telescope_mode_sync') : I18n.t('m_telescope_mode_goto')
      const coord = result.ra && result.dec ? ' · ' + result.ra + ' / ' + result.dec : ''
      this.lx200Status = (mode as ResourceStr) + ' 已发送：' + (target as ResourceStr) + coord
    } else {
      this.lx200Status = result.error === 'no selected object' ? I18n.t('m_telescope_select_target') : (result.error ? result.error : I18n.t('m_telescope_disconnected'))
    }
  }

  private lx200GotoSelected(): void {
    this.callInteractive('telescopeLx200GotoSelected', this.lx200Payload(), (r) => this.applyLx200Result(r))
  }

  private lx200SyncSelected(): void {
    this.callInteractive('telescopeLx200SyncSelected', this.lx200Payload(), (r) => this.applyLx200Result(r))
  }

  private lx200Abort(): void {
    this.callInteractive('telescopeLx200Abort', this.lx200Payload(), (result) => {
      this.lx200Status = result.ok === true ? I18n.t('m_telescope_stop_sent') : (result.error ? result.error : I18n.t('m_telescope_stop_failed'))
    })
  }

  private toggleGyroscope(enabled: boolean): void {
    hilog.info(0x0000, 'StellariumArkUI', 'toggleGyroscope enabled=%{public}s current=%{public}s', enabled.toString(), this.gyroscopeEnabled.toString())
    if (enabled) {
      this.startGyroscope()
    } else {
      this.stopGyroscope(true)
    }
  }

  private startGyroscope(): void {
    if (!this.applicationInForeground) {
      return
    }
    if (this.gyroscopeEnabled) {
      hilog.info(0x0000, 'StellariumArkUI', 'startGyroscope ignored already enabled')
      return
    }
    if (this.gyroCallback === undefined) {
      this.gyroCallback = (data: sensor.OrientationResponse) => {
        this.onOrientationData(data)
      }
    }
    if (this.gyroRotationCallback === undefined) {
      this.gyroRotationCallback = (data: sensor.RotationVectorResponse) => {
        this.onRotationVectorDirect(data)
      }
    }
    if (this.gyroGravityCallback === undefined) {
      this.gyroGravityCallback = (data: sensor.GravityResponse) => {
        this.onGravityData(data)
      }
    }
    if (this.gyroMagneticCallback === undefined) {
      this.gyroMagneticCallback = (data: sensor.MagneticFieldResponse) => {
        this.onMagneticFieldData(data)
      }
    }
    try {
      // Native code blends the first live pose from the current sky view.
      this.callNativeFire('beginGyroViewTransition')
      // Rotation vector is a complete fused pose, so it remains continuous
      // while a tablet crosses the horizon. ORIENTATION is Euler based and is
      // retained only as a fallback for devices without this sensor.
      sensor.on(sensor.SensorId.ROTATION_VECTOR, this.gyroRotationCallback, { interval: 16666667 })
      try {
        sensor.on(sensor.SensorId.GRAVITY, this.gyroGravityCallback, { interval: 16666667 })
        sensor.on(sensor.SensorId.MAGNETIC_FIELD, this.gyroMagneticCallback, { interval: 33333333 })
      } catch (compassError) {
        // A device without either auxiliary sensor can still use its fused
        // rotation vector; the readout simply remains unavailable.
        hilog.warn(0x0000, 'StellariumArkUI', 'gyro compass sensors unavailable: %{public}s', JSON.stringify(compassError))
      }
      this.gyroUsingRotationVector = true
      this.gyroLastTimeMs = 0
      this.gyroEventCount = 0
      this.gyroFirstReading = true
      this.gyroCalibrated = false
      this.gyroLastDispatchMs = 0
      this.gyroAbsolutePoseReady = false
      this.gyroHeadingReferenceReady = false
      this.gyroFwd = []
      this.gyroUp = []
      this.gyroSentFwd = []
      this.gyroGravityDevice = []
      this.gyroMagneticDevice = []
      this.gyroFilteredGravityDevice = []
      this.gyroFilteredMagneticDevice = []
      this.gyroMagneticHeading = Number.NaN
      this.gyroCompassAzAlignment = 0
      this.gyroCompassText = '罗盘 --'
      this.gyroCompassAngle = 0
      this.gyroscopeEnabled = true
      // 方向传感器不是麦克风；避免把普通启用反馈写成“正在监听”。
      this.gyroscopeStatus = '正在校准'
      hilog.info(0x0000, 'StellariumArkUI', 'startGyroscope rotation-vector sensor.on success')
    } catch (error) {
      try {
        sensor.on(sensor.SensorId.ORIENTATION, this.gyroCallback, { interval: 16666667 })
        this.gyroUsingRotationVector = false
        this.gyroscopeEnabled = true
        this.gyroscopeStatus = '正在校准'
        hilog.warn(0x0000, 'StellariumArkUI', 'rotation-vector unavailable; using orientation fallback')
      } catch (fallbackError) {
        this.gyroscopeEnabled = false
        this.gyroscopeStatus = I18n.t('m_gyro_unavailable')
        this.flashHint(I18n.t('m_gyro_unavailable'))
        hilog.error(0x0000, 'StellariumArkUI', 'startGyroscope sensors failed: %{public}s', JSON.stringify(fallbackError))
      }
    }
  }

  private stopGyroscope(updateStatus: boolean): void {
    this.callNativeFire('cancelGyroViewTransition')
    if (this.gyroCallback !== undefined) {
      try {
        sensor.off(sensor.SensorId.ORIENTATION, this.gyroCallback)
      } catch (error) {
      }
    }
    if (this.gyroRotationCallback !== undefined) {
      try {
        sensor.off(sensor.SensorId.ROTATION_VECTOR, this.gyroRotationCallback)
      } catch (error) {
      }
    }
    if (this.gyroGravityCallback !== undefined) {
      try {
        sensor.off(sensor.SensorId.GRAVITY, this.gyroGravityCallback)
      } catch (error) {
      }
    }
    if (this.gyroMagneticCallback !== undefined) {
      try {
        sensor.off(sensor.SensorId.MAGNETIC_FIELD, this.gyroMagneticCallback)
      } catch (error) {
      }
    }
    this.gyroLastTimeMs = 0
    this.gyroCalibrated = false
    this.gyroFirstReading = true
    this.gyroLastDispatchMs = 0
    this.gyroAbsolutePoseReady = false
    this.gyroHeadingReferenceReady = false
    this.gyroUsingRotationVector = false
    this.gyroGravityDevice = []
    this.gyroMagneticDevice = []
    this.gyroFilteredGravityDevice = []
    this.gyroFilteredMagneticDevice = []
    this.gyroMagneticHeading = Number.NaN
    this.gyroCompassAzAlignment = 0
    this.gyroCompassText = '罗盘 --'
    this.gyroCompassAngle = 0
    this.gyroGuideVisible = false
    this.gyroscopeEnabled = false
    if (updateStatus) {
      this.gyroscopeStatus = I18n.t('m_gyro_off')
    }
  }

  // Device-pose tracking.
  //
  // Only the *heading* is calibrated against the current sky view. Pitch and
  // roll come from gravity and are already absolute, so re-basing them would
  // tilt the horizon. The heading, by contrast, depends on the magnetometer
  // and is either arbitrary or drifting, which is what made the sky jump
  // sideways when the fusion filter re-converged.
  private gyroLastAz: number = 0
  private gyroLastAlt: number = 0
  private gyroFirstReading: boolean = true
  private gyroCalibrated: boolean = false
  private gyroRawAz: number = 0
  private gyroRawAlt: number = 0
  private gyroReferenceAz: number = 0
  private gyroReferenceAlt: number = 0
  private gyroReferenceViewAz: number = 0
  private gyroReferenceViewAlt: number = 0
  private gyroHeadingSyncInFlight: boolean = false
  // Smoothed pose, expressed in the bridge's alt-az frame.
  private gyroFwd: number[] = []
  private gyroUp: number[] = []
  private gyroSentFwd: number[] = []
  private gyroLastSampleMs: number = 0
  private gyroLastDispatchMs: number = 0
  // Last raw sensor quaternion (x,y,z,w) — kept for the diagnostic log so the
  // exact mapping can be reconstructed and verified offline.
  private gyroLastRawQ: number[] = [0, 0, 0, 1]
  // Anchored-pose model: we capture the device orientation and the engine's
  // current sky view once, then track only the *relative* tablet rotation from
  // that anchor. This is immune to landscape/portrait screen rotation and to
  // Stellarium's internal azimuth-sign convention (we read the live view back
  // from the engine instead of guessing an ENU->alt-az mapping).
  private gyroAnchorQuat: number[] = []
  private gyroAnchorFwd: number[] = []
  private gyroAnchorUp: number[] = []
  private gyroAnchorValid: boolean = false

  private wrapGyroAzimuth(angle: number): number {
    let wrapped = angle % 360
    if (wrapped < 0) { wrapped += 360 }
    return wrapped
  }

  private shortestGyroAzimuthDelta(from: number, to: number): number {
    let delta = to - from
    if (delta > 180) { delta -= 360 }
    if (delta < -180) { delta += 360 }
    return delta
  }

  // Keep the guide's heading continuous. Native projection supplies angles in
  // [-180, 180], but animating that value directly can make a one-degree turn
  // across the boundary look like a full-circle spin.
  private setGyroGuidePose(x: number, y: number, targetAngle: number): void {
    let angle = targetAngle
    if (this.gyroGuideVisible) {
      let delta = (targetAngle - this.gyroGuideAngle) % 360
      if (delta > 180) { delta -= 360 }
      if (delta < -180) { delta += 360 }
      angle = this.gyroGuideAngle + delta
    }
    this.gyroGuideX = x
    this.gyroGuideY = y
    this.gyroGuideAngle = angle
    this.gyroGuideVisible = true
  }

  private updateGyroTargetGuide(force: boolean = false): void {
    if (!this.gyroscopeEnabled || this.selectedStatus !== 'Selected' ||
      !Number.isFinite(this.gyroGuideTargetAz) || !Number.isFinite(this.gyroGuideTargetAlt) ||
      !Number.isFinite(this.gyroLastAz) || !Number.isFinite(this.gyroLastAlt)) {
      this.gyroGuideVisible = false
      this.gyroGuideReachedAtMs = 0
      return
    }
    const now = Date.now()
    if (!force && now - this.gyroGuideLastUpdateMs < 16) { return }
    this.gyroGuideLastUpdateMs = now

    const left = this.isExpandedLayout ? (this.railCollapsed ? 54 : this.EDGE_MARGIN + 82) : 18
    const right = this.skyWidth - (this.isExpandedLayout && this.panelVisible
      ? this.panelWidth + this.EDGE_MARGIN + 18 : 18)
    const top = this.isFoldHoverLayout ? 46 : 64
    const bottom = this.skyHeight - (this.isFoldHoverLayout ? 104 : 96)
    const centerX = Math.max(left + 24, (left + right) / 2)
    const centerY = Math.max(top + 24, (top + bottom) / 2)

    // The C++ render loop projects the selected object with the active
    // Stellarium projector. This remains correct for every FOV and projection
    // type, unlike deriving a screen vector from separate alt/az deltas.
    const projection = this.callNative('getGyroGuidePosition') as GyroGuideProjection
    if (projection.ok === true && projection.valid === true &&
      typeof projection.xRatio === 'number' && typeof projection.yRatio === 'number') {
      const targetX = (projection.xRatio as number) * this.skyWidth
      const targetY = (projection.yRatio as number) * this.skyHeight
      const targetInClearSky = projection.visible === true &&
        targetX >= left + 24 && targetX <= right - 24 && targetY >= top + 24 && targetY <= bottom - 24
      if (targetInClearSky) {
        if (this.gyroGuideReachedAtMs === 0) {
          this.gyroGuideReachedAtMs = now
        }
        // The arrow confirms that the target has arrived, then gets out of
        // the way. It reappears only after the object leaves the clear sky.
        if (now - this.gyroGuideReachedAtMs >= 1800) {
          this.gyroGuideVisible = false
          return
        }
        // The guide sits above its target and points down. At the very top,
        // place it below instead so it stays fully reachable and visible.
        const placeAbove = targetY - 58 >= top
        this.setGyroGuidePose(
          this.clamp(targetX - 22, left, Math.max(left, right - 44)),
          this.clamp(targetY + (placeAbove ? -58 : 14) - 22, top, Math.max(top, bottom - 44)),
          placeAbove ? 90 : -90
        )
        return
      }
      this.gyroGuideReachedAtMs = 0
      // If the native projection is outside the usable sky area, its true
      // screen-space vector still gives an accurate edge direction.
      const dx = targetX - centerX
      const dy = targetY - centerY
      if (Number.isFinite(dx) && Number.isFinite(dy) && Math.abs(dx) + Math.abs(dy) > 0.5) {
        const angle = Math.atan2(dy, dx) * 180 / Math.PI
        const radians = angle * Math.PI / 180
        const halfW = Math.max(1, (right - left) / 2 - 24)
        const halfH = Math.max(1, (bottom - top) / 2 - 24)
        const edgeScaleX = Math.abs(Math.cos(radians)) > 0.0001 ? halfW / Math.abs(Math.cos(radians)) : Number.POSITIVE_INFINITY
        const edgeScaleY = Math.abs(Math.sin(radians)) > 0.0001 ? halfH / Math.abs(Math.sin(radians)) : Number.POSITIVE_INFINITY
        const edgeScale = Math.min(edgeScaleX, edgeScaleY)
        this.setGyroGuidePose(
          this.clamp(centerX + Math.cos(radians) * edgeScale - 22, left, Math.max(left, right - 44)),
          this.clamp(centerY + Math.sin(radians) * edgeScale - 22, top, Math.max(top, bottom - 44)),
          angle
        )
        return
      }
    }

    // Project the target's local tangent-plane direction around the current
    // view. Cos(altitude) prevents a small azimuth change near zenith from
    // looking like an enormous horizontal turn.
    const horizontal = this.shortestGyroAzimuthDelta(this.gyroGuideTargetAz, this.gyroLastAz) *
      Math.cos(this.gyroLastAlt * Math.PI / 180)
    const vertical = this.gyroGuideTargetAlt - this.gyroLastAlt
    const separation = Math.sqrt(horizontal * horizontal + vertical * vertical)
    const fov = Math.max(5, this.fovSliderValue > 0 ? this.fovSliderValue : 60)
    if (separation <= fov * 0.48) {
      this.gyroGuideVisible = false
      this.gyroGuideReachedAtMs = 0
      return
    }

    // The forward icon points right at 0 degrees. Negative vertical is up on
    // screen, so a target above the view produces a -90 degree arrow.
    const angle = Math.atan2(-vertical, horizontal) * 180 / Math.PI
    const radians = angle * Math.PI / 180
    const dx = Math.cos(radians)
    const dy = Math.sin(radians)
    // Intersect the direction vector with the usable viewport rectangle.
    // This puts the guide on its edge rather than on an arbitrary inner ring.
    const halfW = Math.max(1, (right - left) / 2 - 24)
    const halfH = Math.max(1, (bottom - top) / 2 - 24)
    const edgeScaleX = Math.abs(dx) > 0.0001 ? halfW / Math.abs(dx) : Number.POSITIVE_INFINITY
    const edgeScaleY = Math.abs(dy) > 0.0001 ? halfH / Math.abs(dy) : Number.POSITIVE_INFINITY
    const edgeScale = Math.min(edgeScaleX, edgeScaleY)
    this.setGyroGuidePose(
      this.clamp(centerX + dx * edgeScale - 22, left, Math.max(left, right - 44)),
      this.clamp(centerY + dy * edgeScale - 22, top, Math.max(top, bottom - 44)),
      angle
    )
  }

  // The Orientation sensor already reports a world-referenced pose. Do not
  // anchor it to the existing sky view: doing so makes "flat" retain an
  // arbitrary altitude instead of consistently looking at the nadir.
  private calibrateGyroscope(): void {
    if (!this.gyroscopeEnabled || this.gyroFirstReading) { return }
    this.gyroAbsolutePoseReady = false
    this.gyroHeadingReferenceReady = false
    this.gyroLastDispatchMs = 0
    this.gyroCalibrated = true
    this.gyroscopeStatus = '已校准'
  }

  private onOrientationData(data: sensor.OrientationResponse): void {
    let smoothFactor: number = 0.18
    if (this.gyroscopeSensitivityText === 'Low') { smoothFactor = 0.10 }
    else if (this.gyroscopeSensitivityText === 'High') { smoothFactor = 0.28 }

    if (!Number.isFinite(data.alpha) || !Number.isFinite(data.beta) || !Number.isFinite(data.gamma)) { return }
    const alpha = data.alpha * Math.PI / 180
    const beta = data.beta * Math.PI / 180
    const gamma = data.gamma * Math.PI / 180
    const cosAlpha = Math.cos(alpha)
    const sinAlpha = Math.sin(alpha)
    const cosBeta = Math.cos(beta)
    const sinBeta = Math.sin(beta)
    const cosGamma = Math.cos(gamma)
    const sinGamma = Math.sin(gamma)
    // World-space normal of the display front. The observer looks through the
    // back of the device, hence the sky-forward vector is its inverse.
    const normalX = cosAlpha * sinGamma + sinAlpha * sinBeta * cosGamma
    const normalY = sinAlpha * sinGamma - cosAlpha * sinBeta * cosGamma
    const normalZ = cosBeta * cosGamma
    const forwardX = -normalX
    const forwardY = -normalY
    const forwardZ = -normalZ
    const targetAlt = this.clamp(Math.asin(this.clamp(forwardZ, -1, 1)) * 180 / Math.PI + this.gyroOffsetAlt, -90, 90)
    // A display pointing near the zenith or nadir has no meaningful heading:
    // tiny sensor noise can map to any azimuth and makes the horizon slide
    // sideways while lifting the Pad. alpha is the fused compass heading and
    // remains stable when the Pad is vertical, so use it for yaw; retain the
    // last heading in the polar dead zone and restore it progressively.
    const horizontalStrength = Math.sqrt(forwardX * forwardX + forwardY * forwardY)
    // In landscape, the reported alpha rotates in the opposite direction to
    // Stellarium's azimuth frame. More importantly, it becomes ambiguous when
    // the Pad is flat. Anchor only once the display has a real horizontal aim;
    // after that use its delta, not its changing Euler-angle zero point.
    const rawHeading = this.wrapGyroAzimuth(-data.alpha + this.gyroOffsetAz)
    let targetAz = rawHeading
    if (this.gyroAbsolutePoseReady) {
      if (!this.gyroHeadingReferenceReady && horizontalStrength >= 0.42) {
        this.gyroHeadingSensorAz = rawHeading
        this.gyroHeadingViewAz = this.gyroLastAz
        this.gyroHeadingReferenceReady = true
      }
      targetAz = this.gyroHeadingReferenceReady
        ? this.wrapGyroAzimuth(this.gyroHeadingViewAz + this.shortestGyroAzimuthDelta(this.gyroHeadingSensorAz, rawHeading))
        : this.gyroLastAz
    }
    // Device Y is the top edge of the screen. Keeping it as the camera up
    // basis removes the otherwise undefined roll at zenith and nadir.
    const rawUp: number[] = [-sinAlpha * cosBeta, cosAlpha * cosBeta, sinBeta]

    this.gyroRawAz = targetAz
    this.gyroRawAlt = targetAlt
    const diagnosticNow = Date.now()
    if (diagnosticNow - this.gyroLastDiagnosticMs >= 750) {
      this.gyroLastDiagnosticMs = diagnosticNow
      hilog.info(0x0000, 'StellariumArkUI', '[GYRO_ORIENTATION] alpha=' + data.alpha.toFixed(2) +
        ' beta=' + data.beta.toFixed(2) + ' gamma=' + data.gamma.toFixed(2) +
        ' absAz=' + targetAz.toFixed(2) + ' absAlt=' + targetAlt.toFixed(2))
    }
    if (this.gyroFirstReading) {
      this.gyroFirstReading = false
      this.calibrateGyroscope()
      return
    }
    if (!this.gyroCalibrated) { return }

    let initialPose = false
    if (!this.gyroAbsolutePoseReady) {
      this.gyroLastAz = targetAz
      this.gyroLastAlt = targetAlt
      this.gyroAbsoluteUp = rawUp
      this.gyroAbsolutePoseReady = true
      initialPose = true
    }
    const headingFactor = this.gyroHeadingReferenceReady ? smoothFactor : 0
    const smoothAz = this.wrapGyroAzimuth(this.gyroLastAz +
      this.shortestGyroAzimuthDelta(this.gyroLastAz, targetAz) * headingFactor)
    const smoothAlt = this.gyroLastAlt + (targetAlt - this.gyroLastAlt) * smoothFactor

    const azDelta = this.shortestGyroAzimuthDelta(this.gyroLastAz, smoothAz)
    const altDelta = smoothAlt - this.gyroLastAlt
    // The first valid pose must always reach the native view. Without this,
    // enabling the sensor while the Pad is held still leaves Stellarium at
    // the old horizon because the normal dead-zone returns before dispatch.
    if (!initialPose && Math.abs(azDelta) < 0.25 && Math.abs(altDelta) < 0.25) { return }

    this.gyroLastAz = smoothAz
    this.gyroLastAlt = smoothAlt
    const aimX = Math.cos(smoothAlt * Math.PI / 180) * Math.cos(smoothAz * Math.PI / 180)
    const aimY = Math.cos(smoothAlt * Math.PI / 180) * Math.sin(smoothAz * Math.PI / 180)
    const aimZ = Math.sin(smoothAlt * Math.PI / 180)
    let upX = this.gyroAbsoluteUp[0] + (rawUp[0] - this.gyroAbsoluteUp[0]) * smoothFactor
    let upY = this.gyroAbsoluteUp[1] + (rawUp[1] - this.gyroAbsoluteUp[1]) * smoothFactor
    let upZ = this.gyroAbsoluteUp[2] + (rawUp[2] - this.gyroAbsoluteUp[2]) * smoothFactor
    const upDotAim = upX * aimX + upY * aimY + upZ * aimZ
    upX -= aimX * upDotAim
    upY -= aimY * upDotAim
    upZ -= aimZ * upDotAim
    const upLength = Math.sqrt(upX * upX + upY * upY + upZ * upZ)
    this.gyroAbsoluteUp = upLength > 0.0001 ? [upX / upLength, upY / upLength, upZ / upLength] : rawUp
    const now = Date.now()
    this.updateGyroTargetGuide()
    if (now - this.gyroLastDispatchMs < 20) { return }
    this.gyroLastDispatchMs = now
    this.callNativeFire('setGyroView', smoothAz.toFixed(3) + '|' + smoothAlt.toFixed(3) + '|'
      + this.gyroAbsoluteUp[0].toFixed(5) + '|' + this.gyroAbsoluteUp[1].toFixed(5) + '|' + this.gyroAbsoluteUp[2].toFixed(5))
    this.gyroEventCount += 1
    if (this.gyroEventCount % 20 === 0) {
      this.gyroscopeStatus = I18n.t('m_gyro_working')
    }
  }

  private gyroNormalizeQuaternion(q: number[]): number[] {
    const length = Math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
    if (length < 0.000001) { return [0, 0, 0, 1] }
    return [q[0] / length, q[1] / length, q[2] / length, q[3] / length]
  }

  private gyroConjugateQuaternion(q: number[]): number[] {
    return [-q[0], -q[1], -q[2], q[3]]
  }

  private gyroMultiplyQuaternions(a: number[], b: number[]): number[] {
    return [
      a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
      a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
      a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
      a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]
    ]
  }

  private gyroRotateVector(q: number[], v: number[]): number[] {
    const vectorQuaternion = [v[0], v[1], v[2], 0]
    const rotated = this.gyroMultiplyQuaternions(this.gyroMultiplyQuaternions(q, vectorQuaternion), this.gyroConjugateQuaternion(q))
    return [rotated[0], rotated[1], rotated[2]]
  }

  private gyroNormalizeVector(v: number[]): number[] {
    const length = Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if (length < 0.000001) { return [1, 0, 0] }
    return [v[0] / length, v[1] / length, v[2] / length]
  }

  private gyroAltAzVector(azimuth: number, altitude: number): number[] {
    const az = azimuth * Math.PI / 180
    const alt = altitude * Math.PI / 180
    return [Math.cos(alt) * Math.cos(az), Math.cos(alt) * Math.sin(az), Math.sin(alt)]
  }

  private gyroVectorAltAz(v: number[]): number[] {
    const n = this.gyroNormalizeVector(v)
    let azimuth = Math.atan2(n[1], n[0]) * 180 / Math.PI
    if (azimuth < 0) { azimuth += 360 }
    return [azimuth, Math.asin(n[2]) * 180 / Math.PI]
  }

  // Rotate about the local vertical. Azimuth in the bridge frame is
  // atan2(y, x), so this adds `deg` to the azimuth of any vector.
  private gyroRotateAboutVertical(v: number[], deg: number): number[] {
    if (deg === 0) { return v }
    const r = deg * Math.PI / 180
    const c = Math.cos(r)
    const s = Math.sin(r)
    return [v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2]]
  }

  private gyroRotateAboutAxis(v: number[], axis: number[], deg: number): number[] {
    if (deg === 0) { return v }
    const r = deg * Math.PI / 180
    const c = Math.cos(r)
    const s = Math.sin(r)
    const d = axis[0] * v[0] + axis[1] * v[1] + axis[2] * v[2]
    const cx = axis[1] * v[2] - axis[2] * v[1]
    const cy = axis[2] * v[0] - axis[0] * v[2]
    const cz = axis[0] * v[1] - axis[1] * v[0]
    return [
      v[0] * c + cx * s + axis[0] * d * (1 - c),
      v[1] * c + cy * s + axis[1] * d * (1 - c),
      v[2] * c + cz * s + axis[2] * d * (1 - c)
    ]
  }

  // Keep the up vector perpendicular to the view direction. Without this the
  // two drift apart after repeated smoothing and the roll becomes unstable
  // near the zenith.
  private gyroOrthonormalizeUp(fwd: number[], up: number[]): number[] {
    const d = fwd[0] * up[0] + fwd[1] * up[1] + fwd[2] * up[2]
    let o: number[] = [up[0] - fwd[0] * d, up[1] - fwd[1] * d, up[2] - fwd[2] * d]
    if (o[0] * o[0] + o[1] * o[1] + o[2] * o[2] < 0.000001) {
      const dz = fwd[2]
      o = [-fwd[0] * dz, -fwd[1] * dz, 1 - fwd[2] * dz]
      if (o[0] * o[0] + o[1] * o[1] + o[2] * o[2] < 0.000001) { return [1, 0, 0] }
    }
    return this.gyroNormalizeVector(o)
  }

  // Interpolate directly on the unit sphere. Linear interpolation of the
  // forward and screen-up vectors independently makes a non-rigid camera and
  // is the source of the apparent jump when the view crosses the zenith.
  private gyroSlerpUnitVector(from: number[], to: number[], amount: number): number[] {
    const a = this.gyroNormalizeVector(from)
    const b = this.gyroNormalizeVector(to)
    const dot = this.clamp(this.gyroDot(a, b), -1, 1)
    if (dot > 0.9995) {
      return this.gyroNormalizeVector([
        a[0] + (b[0] - a[0]) * amount,
        a[1] + (b[1] - a[1]) * amount,
        a[2] + (b[2] - a[2]) * amount
      ])
    }
    const angle = Math.acos(dot)
    const sinAngle = Math.sin(angle)
    const fromWeight = Math.sin((1 - amount) * angle) / sinAngle
    const toWeight = Math.sin(amount * angle) / sinAngle
    return this.gyroNormalizeVector([
      a[0] * fromWeight + b[0] * toWeight,
      a[1] * fromWeight + b[1] * toWeight,
      a[2] * fromWeight + b[2] * toWeight
    ])
  }

  // Parallel-transport the screen's up axis along the celestial sphere from
  // one look direction to the next. This provides a continuous tangent-plane
  // basis at zenith and nadir instead of rebuilding one from an Euler angle.
  private gyroParallelTransportUp(oldForward: number[], newForward: number[], oldUp: number[]): number[] {
    const axis = this.gyroCross(oldForward, newForward)
    const axisLength = Math.sqrt(this.gyroDot(axis, axis))
    if (axisLength < 0.000001) {
      return this.gyroOrthonormalizeUp(newForward, oldUp)
    }
    const normalizedAxis = [axis[0] / axisLength, axis[1] / axisLength, axis[2] / axisLength]
    const angle = Math.atan2(axisLength, this.clamp(this.gyroDot(oldForward, newForward), -1, 1)) * 180 / Math.PI
    return this.gyroOrthonormalizeUp(newForward, this.gyroRotateAboutAxis(oldUp, normalizedAxis, angle))
  }

  // The rotation-vector sensor reports in the ENU (east/north/up) world frame,
  // while the engine view direction and setGyroView use the bridge alt-az frame
  // (azimuth = atan2(y, x), x points south). The two frames differ only by a
  // 90 deg rotation about the vertical, but applying an ENU-frame relative
  // rotation directly to a bridge-frame vector silently swaps pitch and roll.
  // These helpers keep the math in one frame at a time.
  private gyroEnuFromBridge(v: number[]): number[] { // bridge (x=-north,y=east,z=up) -> ENU
    return [v[1], -v[0], v[2]]
  }
  private gyroBridgeFromEnu(v: number[]): number[] { // ENU -> bridge
    return [-v[1], v[0], v[2]]
  }

  // Legacy quaternion implementation retained temporarily only to keep this
  // restoration narrowly scoped. It is not subscribed or called.
  private calibrateGyroscopeQuaternionUnused(): void {
    if (!this.gyroscopeEnabled) { return }
    this.gyroCalibrated = false
    this.gyroAnchorValid = false
    this.gyroAnchorQuat = []
    this.gyroAnchorFwd = []
    this.gyroAnchorUp = []
    this.gyroHeadingSyncInFlight = false
    this.gyroscopeStatus = '正在校准'
  }

  // Capture the engine's current sky view plus the device pose as the anchor.
  // After this, the gyro tracks only the *relative* tablet rotation from the
  // anchor, which is independent of landscape/portrait and of the engine's
  // internal azimuth convention. `q` is the device->world quaternion.
  private syncGyroAnchor(q: number[]): void {
    if (this.gyroHeadingSyncInFlight) { return }
    this.gyroHeadingSyncInFlight = true
    this.callInteractive('getViewDirection', '', (result: StellariumBridgeResponse) => {
      this.gyroHeadingSyncInFlight = false
      if (!this.gyroscopeEnabled) { return }
      if (result.ok === true && typeof result.azimuth === 'number' && typeof result.altitude === 'number') {
        // Current view direction, read back from the engine in the bridge
        // alt-az frame, then converted to ENU where the sensor quaternion lives.
        const f0Bridge = this.gyroAltAzVector(result.azimuth as number, result.altitude as number)
        // Preserve a complete, non-degenerate camera basis at calibration.
        // Projecting the world zenith every frame becomes undefined at the
        // zenith/nadir and was the source of the 180-degree flip. The tablet's
        // screen-up vector is a stable fallback through both poles.
        const f0Enu = this.gyroEnuFromBridge(f0Bridge)
        const screenUpEnu = this.gyroRotateVector(q, [0, 1, 0])
        this.gyroAnchorQuat = q
        this.gyroAnchorFwd = this.gyroNormalizeVector(f0Enu)
        this.gyroAnchorUp = this.gyroOrthonormalizeUp(this.gyroAnchorFwd, screenUpEnu)
        this.gyroAnchorValid = true
        this.gyroCalibrated = true
        // Force the smoothing filter to re-seed from the next sample.
        this.gyroFwd = []
        this.gyroUp = []
        this.gyroSentFwd = []
        this.gyroLastSampleMs = 0
        this.gyroLastDispatchMs = 0
        this.gyroscopeStatus = '已校准'
        const raw = this.gyroLastRawQ
        const anchorMsg = '[GYROANCHOR] engAz=' + (result.azimuth as number).toFixed(2) +
          ' engAlt=' + (result.altitude as number).toFixed(2) +
          ' rawQ=' + raw[0].toFixed(4) + ',' + raw[1].toFixed(4) + ',' + raw[2].toFixed(4) + ',' + raw[3].toFixed(4) +
          ' calibratedConj=' + q[0].toFixed(4) + ',' + q[1].toFixed(4) + ',' + q[2].toFixed(4) + ',' + q[3].toFixed(4)
        hilog.info(0x0000, 'StellariumArkUI', '%{public}s', anchorMsg)
      } else {
        this.gyroscopeStatus = I18n.t('m_gyro_core_not_ready')
      }
    })
  }

  // Direct rotation-vector path. The system fusion already combines gravity,
  // gyroscope and magnetometer into a complete pose, which avoids the Euler
  // alpha/beta/gamma discontinuity at the horizon.
  private onGravityData(data: sensor.GravityResponse): void {
    if (Number.isFinite(data.x) && Number.isFinite(data.y) && Number.isFinite(data.z)) {
      this.gyroGravityDevice = [data.x, data.y, data.z]
    }
  }

  private onMagneticFieldData(data: sensor.MagneticFieldResponse): void {
    if (Number.isFinite(data.x) && Number.isFinite(data.y) && Number.isFinite(data.z)) {
      this.gyroMagneticDevice = [data.x, data.y, data.z]
    }
  }

  private gyroFilterDeviceVector(previous: number[], sample: number[], alpha: number): number[] {
    if (previous.length !== 3) { return sample }
    return [
      previous[0] + (sample[0] - previous[0]) * alpha,
      previous[1] + (sample[1] - previous[1]) * alpha,
      previous[2] + (sample[2] - previous[2]) * alpha
    ]
  }

  private gyroCross(a: number[], b: number[]): number[] {
    return [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0]
    ]
  }

  private gyroDot(a: number[], b: number[]): number {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
  }

  // Derive the world basis directly from the two physical references. On this
  // HarmonyOS device the gravity response is the support vector pointing up.
  // Magnetic x up points east; up x east points north.
  // This gives a true device pose without applying a second correction to an
  // already fused rotation quaternion.
  private gyroForwardFromGravityAndMagnetic(): number[] {
    if (this.gyroGravityDevice.length !== 3 || this.gyroMagneticDevice.length !== 3) { return [] }
    const up = this.gyroNormalizeVector(this.gyroGravityDevice)
    const magnetic = this.gyroNormalizeVector(this.gyroMagneticDevice)
    const eastRaw = this.gyroCross(magnetic, up)
    const eastLength = Math.sqrt(eastRaw[0] * eastRaw[0] + eastRaw[1] * eastRaw[1] + eastRaw[2] * eastRaw[2])
    if (eastLength < 0.12) { return [] }
    const east = [eastRaw[0] / eastLength, eastRaw[1] / eastLength, eastRaw[2] / eastLength]
    const north = this.gyroNormalizeVector(this.gyroCross(up, east))
    // The observer looks through the rear of the display, i.e. device -Z.
    const rearNormal = [0, 0, -1]
    const enu = [
      rearNormal[0] * east[0] + rearNormal[1] * east[1] + rearNormal[2] * east[2],
      rearNormal[0] * north[0] + rearNormal[1] * north[1] + rearNormal[2] * north[2],
      rearNormal[0] * up[0] + rearNormal[1] * up[1] + rearNormal[2] * up[2]
    ]
    return this.gyroNormalizeVector(this.gyroBridgeFromEnu(enu))
  }

  // Heading from magnetic north with tilt compensation. `GRAVITY` supplies
  // the physical up axis and the horizontal component of the magnetic field
  // supplies magnetic north, so this remains meaningful while the tablet is
  // tilted toward the horizon. It is deliberately diagnostic/calibration-only
  // and never fed into the high-frequency camera loop.
  private gyroMagneticHeadingFromDeviceVectors(): number {
    if (this.gyroGravityDevice.length !== 3 || this.gyroMagneticDevice.length !== 3) {
      return Number.NaN
    }
    const up = this.gyroNormalizeVector(this.gyroGravityDevice)
    const magnetic = this.gyroNormalizeVector(this.gyroMagneticDevice)
    const northRaw = [
      magnetic[0] - up[0] * this.gyroDot(magnetic, up),
      magnetic[1] - up[1] * this.gyroDot(magnetic, up),
      magnetic[2] - up[2] * this.gyroDot(magnetic, up)
    ]
    const northLength = Math.sqrt(this.gyroDot(northRaw, northRaw))
    if (northLength < 0.12) { return Number.NaN }
    const north = [northRaw[0] / northLength, northRaw[1] / northLength, northRaw[2] / northLength]
    const east = this.gyroNormalizeVector(this.gyroCross(north, up))
    // The observer looks through the rear side of the display.
    const rearNormal = [0, 0, -1]
    const eastComponent = this.gyroDot(rearNormal, east)
    const northComponent = this.gyroDot(rearNormal, north)
    return this.wrapGyroAzimuth(Math.atan2(eastComponent, northComponent) * 180 / Math.PI)
  }

  private gyroCompassDirection(heading: number): string {
    const directions = ['北', '东北', '东', '东南', '南', '西南', '西', '西北']
    const index = Math.floor((this.wrapGyroAzimuth(heading) + 22.5) / 45) % directions.length
    return directions[index]
  }

  private updateGyroCompassReadout(): void {
    const heading = this.gyroMagneticHeadingFromDeviceVectors()
    if (!Number.isFinite(heading)) { return }
    this.gyroMagneticHeading = heading
    // Keep the needle continuous through 359 -> 0 rather than animating a
    // full revolution in the opposite direction.
    let delta = (heading - this.gyroCompassAngle) % 360
    if (delta > 180) { delta -= 360 }
    if (delta < -180) { delta += 360 }
    this.gyroCompassAngle += delta
    const now = Date.now()
    if (now - this.gyroLastCompassUiUpdateMs < 120) { return }
    this.gyroLastCompassUiUpdateMs = now
    this.gyroCompassText = '磁北 ' + this.gyroCompassDirection(heading) + ' ' + Math.round(heading).toString().padStart(3, '0') + '°'
  }

  private gyroEffectiveAzOffset(): number {
    return this.gyroOffsetAz + this.gyroCompassAzAlignment
  }

  private alignGyroToMagneticNorth(): void {
    if (!Number.isFinite(this.gyroMagneticHeading) || !Number.isFinite(this.gyroLastAz)) {
      this.flashHint('罗盘数据尚未就绪')
      return
    }
    // Bridge azimuth is measured from south; a conventional compass bearing
    // is measured clockwise from north, hence the fixed 180-degree conversion.
    const expectedBridgeAz = this.wrapGyroAzimuth(this.gyroMagneticHeading + 180)
    const correction = this.shortestGyroAzimuthDelta(this.gyroLastAz, expectedBridgeAz)
    this.gyroCompassAzAlignment += correction
    this.flashHint('已按' + this.gyroCompassText + '对齐')
  }

  private onRotationVectorDirect(data: sensor.RotationVectorResponse): void {
    if (!this.gyroscopeEnabled || !Number.isFinite(data.x) || !Number.isFinite(data.y) ||
      !Number.isFinite(data.z) || !Number.isFinite(data.w)) { return }
    const orientation = this.gyroConjugateQuaternion(
      this.gyroNormalizeQuaternion([data.x, data.y, data.z, data.w]))
    // The screen front is device +Z. The observer looks through the rear of
    // the tablet, therefore the sky-facing ray is the inverse normal.
    const normalEnu = this.gyroRotateVector(orientation, [0, 0, 1])
    const fusedForward = this.gyroForwardFromGravityAndMagnetic()
    let forward = fusedForward.length === 3
      ? fusedForward
      : this.gyroBridgeFromEnu([-normalEnu[0], -normalEnu[1], -normalEnu[2]])
    forward = this.gyroNormalizeVector(forward)

    if (this.gyroOffsetAz !== 0) {
      forward = this.gyroRotateAboutVertical(forward, this.gyroOffsetAz)
    }
    if (this.gyroOffsetAlt !== 0) {
      const horizontal = Math.sqrt(forward[0] * forward[0] + forward[1] * forward[1])
      if (horizontal > 0.001) {
        forward = this.gyroRotateAboutAxis(forward, [forward[1] / horizontal, -forward[0] / horizontal, 0], this.gyroOffsetAlt)
        forward = this.gyroNormalizeVector(forward)
      }
    }

    const now = Date.now()
    if (this.gyroFwd.length !== 3) {
      this.gyroFwd = forward
      this.gyroLastSampleMs = now
    } else {
      let dt = this.gyroLastSampleMs > 0 ? (now - this.gyroLastSampleMs) / 1000 : 1 / 60
      this.gyroLastSampleMs = now
      if (dt <= 0) { dt = 1 / 60 }
      if (dt > 0.25) { dt = 0.25 }
      let tau = 0.09
      if (this.gyroscopeSensitivityText === 'Low') { tau = 0.16 }
      else if (this.gyroscopeSensitivityText === 'High') { tau = 0.05 }
      const a = 1 - Math.exp(-dt / tau)
      this.gyroFwd = this.gyroNormalizeVector([
        this.gyroFwd[0] + (forward[0] - this.gyroFwd[0]) * a,
        this.gyroFwd[1] + (forward[1] - this.gyroFwd[1]) * a,
        this.gyroFwd[2] + (forward[2] - this.gyroFwd[2]) * a
      ])
    }

    if (now - this.gyroLastDispatchMs < 33) { return }
    this.gyroLastDispatchMs = now
    const altAz = this.gyroVectorAltAz(this.gyroFwd)
    this.gyroLastAz = altAz[0]
    this.gyroLastAlt = altAz[1]
    this.updateGyroTargetGuide()
    this.callNativeFire('setGyroView', this.gyroLastAz.toFixed(3) + '|' + this.gyroLastAlt.toFixed(3))
    this.gyroEventCount += 1
    if (this.gyroEventCount % 4 === 0) {
      this.gyroscopeStatus = I18n.t('m_gyro_working')
    }
  }

  // Retained as a reference implementation for diagnosing sensor-fusion
  // differences. The active implementation above intentionally does not
  // anchor the sky view to an arbitrary startup pose.
  private onRotationVectorData(data: sensor.RotationVectorResponse): void {
    if (!Number.isFinite(data.x) || !Number.isFinite(data.y) || !Number.isFinite(data.z) || !Number.isFinite(data.w)) { return }
    this.gyroLastRawQ = [data.x, data.y, data.z, data.w]
    // This probe is intentionally independent of calibration and view-motion
    // thresholds. It proves whether the device delivers rotation samples.
    this.gyroRawEventCount += 1
    if (this.gyroRawEventCount % 120 === 0) {
      this.callNativeFire('gyroDiagnostic', data.x.toFixed(3) + '|' + data.y.toFixed(3) + '|' + data.z.toFixed(3) + '|' + this.gyroRawEventCount.toString())
    }
    // ROTATION_VECTOR reports a rotation quaternion. OpenHarmony follows the
    // Android sensor convention where the value represents world->device, so a
    // conjugation gives the device->world rotation. Skipping it inverts pitch
    // (you see ground instead of sky); we verified this empirically.
    const orientation = this.gyroConjugateQuaternion(
      this.gyroNormalizeQuaternion([data.x, data.y, data.z, data.w]))

    if (this.gyroFirstReading) {
      this.gyroFirstReading = false
    }

    // First valid reading: anchor the device pose to the live sky view.
    if (!this.gyroAnchorValid) {
      this.syncGyroAnchor(orientation)
      return
    }
    if (!this.gyroCalibrated) { return }

    // Relative rotation of the tablet from the anchor pose to now, in the
    // device->world (ENU) frame. The anchor vectors are stored in ENU too, so
    // rotating them by rel reproduces exactly how far the tablet has turned.
    const rel = this.gyroMultiplyQuaternions(orientation, this.gyroConjugateQuaternion(this.gyroAnchorQuat))
    const fwdEnu = this.gyroRotateVector(rel, this.gyroAnchorFwd)
    const upEnu = this.gyroRotateVector(rel, this.gyroAnchorUp)
    // Rotate the calibrated camera basis as one rigid pose. Do not rebuild the
    // up vector from world zenith here: that basis has no unique direction at
    // the zenith/nadir and makes the scene flip while crossing either pole.
    let fwd = this.gyroBridgeFromEnu(fwdEnu)
    let up = this.gyroBridgeFromEnu(upEnu)

    // Manual calibration nudges, applied to the whole pose so up stays
    // consistent with the view direction. These operate in the bridge frame.
    const yaw = this.gyroOffsetAz
    if (yaw !== 0) {
      fwd = this.gyroRotateAboutVertical(fwd, yaw)
      up = this.gyroRotateAboutVertical(up, yaw)
    }
    if (this.gyroOffsetAlt !== 0) {
      // Tilt around the horizontal axis at right angles to the current
      // heading, so the manual nudge raises the view instead of shearing it.
      const h = Math.sqrt(fwd[0] * fwd[0] + fwd[1] * fwd[1])
      if (h > 0.001) {
        const axis: number[] = [fwd[1] / h, -fwd[0] / h, 0]
        fwd = this.gyroRotateAboutAxis(fwd, axis, this.gyroOffsetAlt)
        up = this.gyroRotateAboutAxis(up, axis, this.gyroOffsetAlt)
      }
    }
    fwd = this.gyroNormalizeVector(fwd)
    up = this.gyroOrthonormalizeUp(fwd, up)

    const now = Date.now()
    if (this.gyroFwd.length !== 3 || this.gyroUp.length !== 3) {
      // First sample after (re)calibration: adopt the pose outright.
      this.gyroFwd = fwd
      this.gyroUp = up
      this.gyroLastSampleMs = now
    } else {
      let dt = this.gyroLastSampleMs > 0 ? (now - this.gyroLastSampleMs) / 1000 : 1 / 60
      this.gyroLastSampleMs = now
      if (!(dt > 0)) { dt = 1 / 60 }
      if (dt > 0.25) { dt = 0.25 }
      // Time-constant low pass, so the feel no longer depends on the sensor
      // delivery rate. The old filter used a fixed per-sample alpha *and* a
      // 0.18 degree dead zone that returned without storing the new pose:
      // during slow panning the stored pose froze until the error grew past
      // roughly a degree, then the view jumped. That was the stutter.
      let tau = 0.09
      if (this.gyroscopeSensitivityText === 'Low') { tau = 0.16 }
      else if (this.gyroscopeSensitivityText === 'High') { tau = 0.05 }
      const a = 1 - Math.exp(-dt / tau)
      const sFwd = this.gyroNormalizeVector([
        this.gyroFwd[0] + (fwd[0] - this.gyroFwd[0]) * a,
        this.gyroFwd[1] + (fwd[1] - this.gyroFwd[1]) * a,
        this.gyroFwd[2] + (fwd[2] - this.gyroFwd[2]) * a
      ])
      const sUp = [
        this.gyroUp[0] + (up[0] - this.gyroUp[0]) * a,
        this.gyroUp[1] + (up[1] - this.gyroUp[1]) * a,
        this.gyroUp[2] + (up[2] - this.gyroUp[2]) * a
      ]
      this.gyroFwd = sFwd
      this.gyroUp = this.gyroOrthonormalizeUp(sFwd, sUp)
    }

    // Sample at the device rate, but keep the ArkTS-to-Qt queue bounded. The
    // native renderer receives the latest complete pose about 30 times/sec.
    if (now - this.gyroLastDispatchMs < 33) { return }
    // Skip only the bridge call when nothing moved — never the state update.
    if (this.gyroSentFwd.length === 3) {
      const d = this.clamp(this.gyroSentFwd[0] * this.gyroFwd[0] + this.gyroSentFwd[1] * this.gyroFwd[1] + this.gyroSentFwd[2] * this.gyroFwd[2], -1, 1)
      if (Math.acos(d) * 180 / Math.PI < 0.01 && now - this.gyroLastDispatchMs < 250) { return }
    }
    this.gyroSentFwd = this.gyroFwd
    this.gyroLastDispatchMs = now

    const altAz = this.gyroVectorAltAz(this.gyroFwd)
    this.gyroLastAz = altAz[0]
    this.gyroLastAlt = altAz[1]
    // Dedicated direct-pose command: moveToAltAz would drop the up vector and
    // restart an interpolation on every sample.
    this.callNativeFire('setGyroView', this.gyroLastAz.toFixed(3) + '|' + this.gyroLastAlt.toFixed(3) + '|'
      + this.gyroUp[0].toFixed(5) + '|' + this.gyroUp[1].toFixed(5) + '|' + this.gyroUp[2].toFixed(5))
    this.gyroEventCount += 1
    if (this.gyroEventCount % 4 === 0) {
      this.gyroscopeStatus = I18n.t('m_gyro_working')
      const raw = this.gyroLastRawQ
      const diagMsg = '[GYROSAMP] rawQ=' + raw[0].toFixed(4) + ',' + raw[1].toFixed(4) + ',' + raw[2].toFixed(4) + ',' + raw[3].toFixed(4) +
        ' sentAz=' + this.gyroLastAz.toFixed(2) + ' sentAlt=' + this.gyroLastAlt.toFixed(2) +
        ' up=' + this.gyroUp[0].toFixed(3) + ',' + this.gyroUp[1].toFixed(3) + ',' + this.gyroUp[2].toFixed(3) +
        ' offAz=' + this.gyroOffsetAz + ' offAlt=' + this.gyroOffsetAlt
      hilog.info(0x0000, 'StellariumArkUI', '%{public}s', diagMsg)
    }
  }
  private searchObject(name: string, catalogModuleId: string = ''): void {
    const query = name.trim()
    if (query.length === 0) {
      return
    }
    this.flashHint(I18n.t('i0070').replace('%s', query))
    // 保存搜索历史（去重，最多保留 20 条）
    const hist = this.searchHistory.filter(h => h !== query)
    hist.unshift(query)
    this.searchHistory = hist.slice(0, 20)
    this.saveSearchHistoryToStorage()
    const gyroSelection = this.gyroscopeEnabled
    let payload = catalogModuleId.length > 0 ? 'catalog|' + catalogModuleId + '|' + query : query
    if (gyroSelection) { payload += '|selectOnly' }
    this.callInteractive('searchObject', payload, (result) => {
      if (result.found === true) {
        const returnToGraph = this.graphTargetPickerActive
        const returnToRts = this.rtsTargetPickerActive
        const returnToEphemeris = this.ephemerisTargetPickerActive
        const returnToAstroCalc = returnToGraph || returnToRts || returnToEphemeris
        // Close the search sheet before calculating the target's final safe
        // point. Otherwise the first navigation avoids the old 9/10 sheet,
        // then visibly performs a second correction for the top detail card.
        if (this.activePanel === 'search' && !returnToAstroCalc) {
          // Do this in-place instead of closePanel(): that generic helper
          // schedules a later recenter for the closing sheet, which can race
          // the newly opened object card and undo its safe target.
          this.stopTimePanelTimers()
          this.getUIContext().animateTo({ duration: 260, curve: curves.springMotion(0.45, 0.9) }, () => {
            this.panelVisible = false
          })
          this.drawerOpen = false
        }
        this.applySelectedObject(result)
        if (returnToGraph) {
          this.graphTargetPickerActive = false
          this.astroTab = 4
          this.setPanel('astro')
        } else if (returnToRts) {
          this.rtsTargetPickerActive = false
          this.astroTab = 2
          this.setPanel('astro')
        } else if (returnToEphemeris) {
          this.ephemerisTargetPickerActive = false
          this.astroTab = 1
          this.setPanel('astro')
          this.loadEphemeris()
        }
        // Under gyro control, a selected target is navigated by the edge guide,
        // not by moving the camera. Normal searches keep the explicit tracking
        // behavior requested for time-lapse observing.
        this.callInteractive('setTracking', gyroSelection ? '0' : '1', (trackingResult: StellariumBridgeResponse) => {
          if (trackingResult.ok === true) {
            this.trackingText = gyroSelection ? 'Off' : 'On'
          }
        })
        const displayName = this.zhNameOf(this.selectedName.length > 0 ? this.selectedName : query)
        this.flashHint(I18n.t('i0071').replace('%s', displayName))
      } else {
        this.applySelectedObject(result)
        this.flashHint(I18n.t('i0072').replace('%s', query))
      }
    })
  }

  // 拉取当前选中天体的信息并刷新详情面板。
  // 加防重入：避免自动刷新(1Hz)与手动“刷新”按钮重叠，导致 consume-on-read 结果被互相冲掉。
  // callNativeWhenReady 放弃轮询时不会回调，所以配 detailRefreshGuard 兜底复位，防止永久卡死。
  private refreshSelectedObject(): void {
    if (this.detailRefreshing) { return }
    this.detailRefreshing = true
    if (this.detailRefreshGuard !== 0) { clearTimeout(this.detailRefreshGuard) }
    this.detailRefreshGuard = setTimeout(() => { this.detailRefreshing = false }, 450) as number
    this.callInteractive('getSelectedObjectInfo', '', (r) => {
      this.detailRefreshing = false
      if (this.detailRefreshGuard !== 0) { clearTimeout(this.detailRefreshGuard); this.detailRefreshGuard = 0 }
      this.applySelectedObject(r, true)
    })
  }

  // 启动“详情自动刷新”：仅在【目标详情面板打开 + 有已选中天体 + 未在拖动星图】时才拉数据，避免无谓的桥调用。
  private startDetailAutoRefresh(): void {
    if (this.detailTimer !== 0) { return }
    this.detailTimer = setInterval(() => {
      if (this.skyDragging) { return }
      if (this.selectedStatus === 'Selected' && ((this.activePanel === 'object' && this.panelVisible) || this.infoWinVisible)) {
        this.refreshSelectedObject()
      }
    }, 300) as number
  }

  private pauseDetailRefreshForSkyDrag(): void {
    // Object-info polling uses the same ArkTS-to-Qt queue as panning. Stop it
    // for the duration of a gesture so an open detail card cannot make the sky
    // lag behind the finger.
    this.stopDetailAutoRefresh()
  }

  private resumeDetailRefreshAfterSkyDrag(): void {
    if (this.infoWinVisible && this.selectedStatus === 'Selected') {
      this.startDetailAutoRefresh()
    }
  }

  private stopDetailAutoRefresh(): void {
    if (this.detailTimer !== 0) { clearInterval(this.detailTimer); this.detailTimer = 0 }
    if (this.detailRefreshGuard !== 0) { clearTimeout(this.detailRefreshGuard); this.detailRefreshGuard = 0 }
    this.detailRefreshing = false
  }

  private requestSelectedFullInfo(expectedName: string): void {
    if (this.selectedFullInfoTimer !== 0) {
      clearTimeout(this.selectedFullInfoTimer)
    }
    // Let target selection, the card's first layout, and any navigation start
    // finish before asking Qt to generate the expensive AllInfo prose.
    this.selectedFullInfoTimer = setTimeout(() => {
      this.selectedFullInfoTimer = 0
      if (!this.infoWinVisible || this.skyDragging || this.selectedName !== expectedName) {
        return
      }
      this.callInteractive('getSelectedObjectInfo', 'full', (r) => {
        const returnedName = r.name && r.name.length > 0 ? r.name : r.englishName
        if (r.ok === true && r.found === true && returnedName === this.selectedName) {
          this.applySelectedObject(r, true)
        }
      })
    }, 550) as number
  }

  private moveToSelectedObject(fromLayoutChange: boolean = false): void {
    // Sensor pose is the camera owner while gyro mode is active. Starting a
    // second auto-move here creates a visible jump when the next pose sample
    // correctly takes control back, so center/track only refresh the guide.
    if (this.gyroscopeEnabled) {
      this.updateGyroTargetGuide(true)
      return
    }
    if (this.panelVisible || this.infoWinVisible) {
      this.placeSelectedObjectInSafeArea(fromLayoutChange ? 'layout' : 'focus')
      return
    }
    this.navigateSelectedObjectTo(this.skyWidth / 2, this.skyHeight / 2, fromLayoutChange ? 'layout' : 'focus')
  }

  private navigateSelectedObjectTo(x: number, y: number, mode: string = 'focus'): void {
    if (this.skyWidth <= 1 || this.skyHeight <= 1) { return }
    const payload = `${Math.round(x)}|${Math.round(y)}|${Math.round(this.skyWidth)}|${Math.round(this.skyHeight)}|${mode}`
    const navigationKey = this.selectedName + '|' + payload
    hilog.info(0x0000, 'StellariumArkUI', 'safe-target request mode=%{public}s compact=%{public}s panel=%{public}s drawer=%{public}s info=%{public}s target=%{public}s',
      mode, (!this.isExpandedLayout).toString(), this.panelVisible.toString(), this.drawerOpen.toString(), this.infoWinVisible.toString(), payload)
    const now = Date.now()
    // A layout callback can re-fire long after its animation has settled.
    // Repeating the same safe point would move a time-anchored target for no
    // visible UI change. Focus commands still pass through after the short
    // debounce so the explicit centre action remains available.
    if (mode === 'layout' && navigationKey === this.lastSafeNavigationPayload) {
      hilog.info(0x0000, 'StellariumArkUI', 'safe-target skipped unchanged layout')
      return
    }
    if (navigationKey === this.lastSafeNavigationPayload && now - this.lastSafeNavigationAt < 420) {
      return
    }
    this.lastSafeNavigationPayload = navigationKey
    this.lastSafeNavigationAt = now
    this.callInteractive('moveToSelectedAt', payload, (r) => this.applySelectedObject(r))
  }

  private placeSelectedObjectInSafeArea(mode: string = 'focus'): void {
    const fallback = this.isExpandedLayout ? this.expandedSafeTargetPoint() : this.compactSafeTargetPoint()
    if (mode === 'layout') {
      const localTarget = this.selectedObjectLayoutAvoidanceTarget(fallback)
      if (localTarget.length !== 2) {
        return
      }
      this.navigateSelectedObjectTo(localTarget[0], localTarget[1], mode)
      return
    }
    if (this.isExpandedLayout) {
      this.navigateSelectedObjectTo(fallback[0], fallback[1], mode)
    } else {
      this.navigateSelectedObjectTo(fallback[0], fallback[1], mode)
    }
  }

  private selectedObjectUiObstacles(): SkyUiObstacle[] {
    const obstacles: SkyUiObstacle[] = []
    if (this.isExpandedLayout) {
      if (this.drawerOpen) {
        obstacles.push({
          label: 'drawer', left: this.drawerLeft(), top: this.railTop(),
          right: this.drawerLeft() + this.drawerWidth(),
          bottom: this.railTop() + this.drawerActions.length * 46 + 58
        })
      }
      if (this.panelVisible) {
        obstacles.push({
          label: 'panel', left: this.expandedMainPanelLeft(), top: this.panelTop(),
          right: this.expandedMainPanelLeft() + this.panelWidth,
          bottom: this.panelTop() + this.panelMaxHeight
        })
      }
      if (this.infoWinVisible && !this.drawerOpen) {
        if (this.useExpandedDetailSummary() && this.canShowExpandedDetailSummary()) {
          obstacles.push({
            label: 'summary', left: this.expandedDetailSummaryX(), top: this.expandedDetailSummaryY(),
            right: this.expandedDetailSummaryX() + this.expandedDetailSummaryWidth(),
            bottom: this.expandedDetailSummaryY() + this.expandedDetailSummaryHeight()
          })
        } else {
          obstacles.push({
            label: 'object-card', left: this.bottomCardX(), top: this.bottomCardY(),
            right: this.bottomCardX() + this.bottomCardWidth(),
            bottom: this.bottomCardY() + this.bottomCardHeight()
          })
        }
      }
      return obstacles
    }

    if (this.panelVisible || this.drawerOpen) {
      const sheetTop = this.isFoldHoverLayout ? this.hoverPanelTop() : this.skyHeight - 90 - this.compactPanelHeight()
      obstacles.push({ label: this.drawerOpen ? 'drawer' : 'sheet', left: 0, top: sheetTop, right: this.skyWidth, bottom: this.skyHeight - 90 })
    }
    if (!this.isFoldHoverLayout) {
      obstacles.push({ label: 'bottom-dock', left: 0, top: this.skyHeight - 90, right: this.skyWidth, bottom: this.skyHeight })
    }
    if (!this.panelVisible && !this.drawerOpen && this.infoWinVisible) {
      if (this.isPhoneDetailPeek()) {
        obstacles.push({
          label: 'object-peek', left: this.compactObjectPeekX(), top: this.compactObjectPeekY(),
          right: this.compactObjectPeekX() + this.compactObjectPeekWidth(), bottom: this.compactObjectPeekY() + 64
        })
      } else {
        obstacles.push({
          label: 'object-card', left: this.bottomCardX(), top: this.bottomCardY(),
          right: this.bottomCardX() + this.bottomCardWidth(), bottom: this.bottomCardY() + this.bottomCardHeight()
        })
      }
    }
    return obstacles
  }

  private pointOverlapsUiObstacle(x: number, y: number, obstacle: SkyUiObstacle, margin: number = 10): boolean {
    return x >= obstacle.left - margin && x <= obstacle.right + margin &&
      y >= obstacle.top - margin && y <= obstacle.bottom + margin
  }

  private selectedObjectLayoutAvoidanceTarget(fallback: number[]): number[] {
    const projection = this.callNative('getGyroGuidePosition') as GyroGuideProjection
    if (projection.ok !== true || projection.valid !== true || projection.visible !== true ||
      typeof projection.xRatio !== 'number' || typeof projection.yRatio !== 'number') {
      hilog.info(0x0000, 'StellariumArkUI', 'safe-target skipped unavailable projection')
      return []
    }
    const currentX = (projection.xRatio as number) * this.skyWidth
    const currentY = (projection.yRatio as number) * this.skyHeight
    const obstacles = this.selectedObjectUiObstacles()
    let collision: SkyUiObstacle | undefined = undefined
    for (let index = 0; index < obstacles.length; index++) {
      if (this.pointOverlapsUiObstacle(currentX, currentY, obstacles[index])) {
        collision = obstacles[index]
        break
      }
    }
    if (collision === undefined) {
      hilog.info(0x0000, 'StellariumArkUI', 'safe-target skipped clear x=%{public}d y=%{public}d', Math.round(currentX), Math.round(currentY))
      return []
    }

    const edge = 18
    const gap = 30
    const minX = edge
    const maxX = this.skyWidth - edge
    const minY = edge
    const maxY = this.skyHeight - edge
    const candidates: number[][] = [
      [collision.left - gap, currentY], [collision.right + gap, currentY],
      [currentX, collision.top - gap], [currentX, collision.bottom + gap]
    ]
    let best: number[] = []
    let bestDistance = Number.MAX_VALUE
    for (let index = 0; index < candidates.length; index++) {
      const candidateX = this.clamp(candidates[index][0], minX, maxX)
      const candidateY = this.clamp(candidates[index][1], minY, maxY)
      let clear = true
      for (let obstacleIndex = 0; obstacleIndex < obstacles.length; obstacleIndex++) {
        if (this.pointOverlapsUiObstacle(candidateX, candidateY, obstacles[obstacleIndex], 12)) {
          clear = false
          break
        }
      }
      const distance = Math.pow(candidateX - currentX, 2) + Math.pow(candidateY - currentY, 2)
      if (clear && distance < bestDistance) {
        best = [candidateX, candidateY]
        bestDistance = distance
      }
    }
    if (best.length !== 2 || !Number.isFinite(best[0]) || !Number.isFinite(best[1])) {
      if (!Number.isFinite(fallback[0]) || !Number.isFinite(fallback[1])) {
        hilog.info(0x0000, 'StellariumArkUI', 'safe-target skipped no clear candidate')
        return []
      }
      best = fallback
    }
    hilog.info(0x0000, 'StellariumArkUI', 'safe-target collision %{public}s at=%{public}d|%{public}d target=%{public}d|%{public}d',
      collision.label, Math.round(currentX), Math.round(currentY), Math.round(best[0]), Math.round(best[1]))
    return best
  }

  // UI placement is not static: panels can open, close, snap between 6/10
  // and 9/10, or be dragged. Re-run the same navigation after those layout
  // changes. With no inspector/sheet remaining, moveToSelectedObject() uses
  // the native visual centre again.
  private scheduleSelectedObjectForUiChange(delay: number = 360): void {
    if (this.selectedUiLayoutTimer !== 0) {
      clearTimeout(this.selectedUiLayoutTimer)
      this.selectedUiLayoutTimer = 0
    }
    if (this.selectedStatus !== 'Selected') {
      return
    }
    this.selectedUiLayoutTimer = setTimeout(() => {
      this.selectedUiLayoutTimer = 0
      if (this.selectedStatus === 'Selected' && !this.gyroscopeEnabled) {
        this.moveToSelectedObject(true)
      }
    }, delay) as number
  }

  private compactSafeTargetPoint(): number[] {
    // Phone inspectors deliberately live at the top, not at the bottom.
    // Calculate the vertical gap from their real rendered bounds so a locked
    // target never lands inside either the inspector, the bottom dock, or an
    // open sheet. The centre x is clear of the left zoom controls and the
    // right quick controls.
    let top = 38
    let bottom = this.skyHeight - 100 // compact bottom dock plus breathing room

    // Compact panels replace the detailed object card. Reserving the hidden
    // card's area made a 9/10 sheet calculate a target underneath itself.
    if (this.infoWinVisible && !this.panelVisible && !this.drawerOpen) {
      if (this.isPhoneDetailPeek()) {
        top = Math.max(top, this.compactObjectPeekY() + 72 + 28)
      } else {
        top = Math.max(top, this.bottomCardY() + this.bottomCardHeight() + 28)
      }
    }
    let sheetTop = -1
    if (this.panelVisible || this.drawerOpen) {
      sheetTop = this.skyHeight - 90 - this.compactPanelHeight()
      bottom = Math.min(bottom, sheetTop - 32)
    }

    // On very short screens, preserve a reachable sky target even when the
    // detail card and a 9/10 sheet leave no conventional vertical gap.
    if (bottom - top < 96) {
      bottom = Math.max(bottom, top + 96)
    }
    const targetY = this.clamp((top + bottom) / 2, top + 20, bottom - 20)
    hilog.info(0x0000, 'StellariumArkUI', 'compact-safe h=%{public}d usable=%{public}d snap=%{public}s drag=%{public}s sheetTop=%{public}d top=%{public}d bottom=%{public}d targetY=%{public}d',
      Math.round(this.skyHeight), Math.round(this.compactPanelUsableHeight()), this.compactPanelSnapRatio.toString(), this.compactPanelDragOffsetY.toString(), Math.round(sheetTop), Math.round(top), Math.round(bottom), Math.round(targetY))
    return [this.skyWidth / 2, targetY]
  }

  private placeSelectedObjectInCompactSafeArea(mode: string = 'focus'): void {
    if (this.isExpandedLayout || (!this.panelVisible && !this.drawerOpen && !this.infoWinVisible) || this.selectedStatus !== 'Selected') {
      return
    }
    const target = this.compactSafeTargetPoint()
    this.navigateSelectedObjectTo(target[0], target[1], mode)
  }

  private expandedSafeTargetPoint(): number[] {
    const left = this.EDGE_MARGIN + 64
    const right = this.panelVisible ? this.expandedMainPanelLeft() - 18
      : (this.infoWinVisible ? this.bottomCardX() - 18 : this.skyWidth - this.EDGE_MARGIN)
    let top = this.EDGE_MARGIN + 24
    // With both cards open, the only generous uninterrupted sky region is
    // below the compact object summary and to the left of the main panel.
    if (this.panelVisible && this.infoWinVisible && this.useExpandedDetailSummary()) {
      top = this.expandedDetailSummaryY() + this.expandedDetailSummaryHeight() + 28
    }
    const bottom = this.skyHeight - this.EDGE_MARGIN
    if (right - left < 120 || bottom - top < 120) {
      return [this.skyWidth / 2, this.skyHeight / 2]
    }
    return [(left + right) / 2, (top + bottom) / 2]
  }

  private easeSelectedObjectTo(x: number, y: number): void {
    const centerX = this.skyWidth / 2
    const centerY = this.skyHeight / 2
    // Native panView moves the scene, so its x axis is the inverse of the
    // apparent object motion. A positive screen target must therefore pan
    // left, otherwise the selected body is pushed further under a right panel.
    const dx = centerX - x
    // Native panView moves the scene, not the selected marker. Both apparent
    // screen axes are inverse: sending the old y sign made a 9/10 bottom
    // sheet push the marker downward and a top inspector keep it under the
    // card instead of moving it into the remaining sky.
    const dy = y - centerY
    const steps = 9
    let step = 0
    let previousX = 0
    let previousY = 0
    const timer = setInterval(() => {
      if (!this.panelVisible && !this.infoWinVisible) {
        clearInterval(timer)
        if (this.expandedTargetPlacementTimer === timer) this.expandedTargetPlacementTimer = 0
        return
      }
      step++
      const p = (1 - Math.cos(Math.PI * step / steps)) / 2
      const nextX = Math.round(dx * p)
      const nextY = Math.round(dy * p)
      this.callNativeFire('dragView', `0|0|${nextX - previousX}|${nextY - previousY}`)
      previousX = nextX
      previousY = nextY
      if (step >= steps) {
        clearInterval(timer)
        if (this.expandedTargetPlacementTimer === timer) this.expandedTargetPlacementTimer = 0
      }
    }, 36) as number
    this.expandedTargetPlacementTimer = timer
  }

  private placeSelectedObjectInExpandedSafeArea(mode: string = 'focus'): void {
    if (!this.isExpandedLayout || (!this.panelVisible && !this.infoWinVisible) || this.selectedStatus !== 'Selected') {
      return
    }
    const target = this.expandedSafeTargetPoint()
    this.navigateSelectedObjectTo(target[0], target[1], mode)
  }

  // 精确到角秒：地球自转约 15″/秒，300ms 刷新时用户能直接看到坐标连续变化。
  private fmtDegMin(deg: number): string {
    const sign = deg < 0 ? '-' : ''
    let totalSeconds = Math.round(Math.abs(deg) * 3600)
    const d = Math.floor(totalSeconds / 3600)
    totalSeconds -= d * 3600
    const m = Math.floor(totalSeconds / 60)
    const s = totalSeconds - m * 60
    return sign + d.toString() + '°' + (m < 10 ? '0' + m : m.toString()) + '\'' + (s < 10 ? '0' + s : s.toString()) + '″'
  }

  // 把核心返回的英文名映射成当前语言显示；中文时用别名表，其他语言用行星名翻译或原样
  private zhNameOf(raw: string): string {
    if (!raw || raw.length === 0) { return raw }
    // 通用状态翻译
    const statusMap = I18n.objectType(raw)
    if (statusMap !== raw) { return statusMap }
    // 星座缩写翻译（Sco→天蝎座等）
    const constName = I18n.constellationAbbr(raw)
    if (constName !== raw) { return constName }
    // 星座全名翻译（Scorpius→天蝎座等，C++ 有时返回全名而非缩写）
    const constFullName = I18n.constellationFullName(raw)
    if (constFullName !== raw) { return constFullName }
    // 行星名翻译（所有语言）
    const planet = I18n.planetName(raw)
    if (planet !== raw) { return planet }
    // 仅中文语言使用别名表（ALIAS_LIST 只有中英对照）
    const curLang = I18n.getLanguage()
    if (curLang === 'zh_CN' || curLang === 'zh_TW') {
      if (/[一-鿿]/.test(raw)) { return raw }
      const q = raw.toLowerCase()
      for (let i = 0; i < ALIAS_LIST.length; i++) {
        if (ALIAS_LIST[i].en.toLowerCase() === q) { return ALIAS_LIST[i].zh }
      }
      const messier = this.messierNumberOf(raw)
      if (messier.length > 0) { return '梅西耶编号 ' + messier }
    }
    return raw
  }

  private messierNumberOf(raw: string): string {
    const compact = raw.trim().replace(/\s+/g, '')
    if (!/^M\d+$/i.test(compact)) { return '' }
    const number = Number(compact.substring(1))
    return number >= 1 && number <= 110 ? number.toString() : ''
  }

  private celestialTitle(nativeName: string, englishName: string): string {
    const localizedNative = this.zhNameOf(nativeName)
    if (localizedNative !== nativeName || /[一-鿿]/.test(localizedNative)) { return localizedNative }
    const localizedEnglish = this.zhNameOf(englishName)
    if (localizedEnglish !== englishName || /[一-鿿]/.test(localizedEnglish)) { return localizedEnglish }
    if (this.searchCategory === 'asteroid' && this.minorPlanetNumberOf(nativeName).length > 0) {
      const nameWithoutNumber = nativeName.replace(/^\(?\d{1,7}\)?\s*/, '').trim()
      if (nameWithoutNumber.length === 0) { return '未命名小行星' }
    }
    return localizedNative.length > 0 ? localizedNative : englishName
  }

  private minorPlanetNumberOf(raw: string): string {
    const match = raw.trim().match(/^\(?(\d{1,7})\)?(?:\s|$)/)
    return match !== null ? match[1] : ''
  }

  private celestialSubtitle(title: string, englishName: string): string {
    if (englishName.length === 0) { return '' }
    const messier = this.messierNumberOf(englishName)
    if (messier.length > 0) { return '目录号 M' + messier }
    if (this.searchCategory === 'asteroid') {
      const number = this.minorPlanetNumberOf(englishName)
      if (number.length > 0) { return '国际永久编号 ' + number }
    }
    return ''
  }

  private wutTargetTitle(target: WutTarget): string {
    return this.celestialTitle(target.name ?? '', target.englishName ?? '')
  }

  private wutCategoryTitle(): string {
    if (this.wutCategory === 'stars') { return '亮星' }
    if (this.wutCategory === 'messier') { return '梅西耶天体' }
    return '行星'
  }

  private wutTargetSubtitle(target: WutTarget): string {
    return this.celestialSubtitle(this.wutTargetTitle(target), target.englishName ?? '')
  }

  // 反向：把中文/英文标签翻回核心能识别的英文标识（供搜索/点击使用）。
  private enNameOf(label: string): string {
    if (!label || label.length === 0) { return label }
    for (let i = 0; i < ALIAS_LIST.length; i++) {
      if (ALIAS_LIST[i].zh === label) { return ALIAS_LIST[i].en }
    }
    return label
  }
  // 天体类型本地化（Planet→行星…）；支持复合类型如 "double star, pulsating variable star"。
  private zhType(type: string): string {
    return I18n.objectType(type)
  }

  // 中文/拼音/英文模糊匹配别名，返回可点的建议（zh 显示，en 检索）。
  private aliasHits(input: string): Array<SearchSug> {
    const q = (input || '').trim().toLowerCase()
    if (q.length === 0) { return [] }
    const out: Array<AliasHit> = []
    const seen: Record<string, boolean> = {}
    for (let i = 0; i < ALIAS_LIST.length; i++) {
      const a = ALIAS_LIST[i]
      let score = -1
      if (a.en.toLowerCase() === q) { score = 0 }
      else if (a.en.toLowerCase().startsWith(q)) { score = 1 }
      else if (a.zh.indexOf(input.trim()) >= 0) { score = 1 }
      else if (a.py && a.py.toLowerCase().indexOf(q) >= 0) { score = 2 }
      else if (a.en.toLowerCase().indexOf(q) >= 0) { score = 3 }
      if (score >= 0 && !seen[a.en]) {
        seen[a.en] = true
        out.push({ zh: a.zh, en: a.en, score: score })
      }
    }
    out.sort((x, y) => x.score - y.score)
    return out.slice(0, 12).map((o) => ({ zh: o.zh, en: o.en }))
  }

  // fromRefresh=true 时来自“详情自动刷新”等后台轮询：仅刷新数值，绝不重置展开态、也绝不因瞬时未命中而关窗。
  private applySelectedObject(result: StellariumBridgeResponse, fromRefresh: boolean = false): void {
    if (result.ok !== true) {
      this.selectedStatus = result.error ? result.error : 'Core not ready'
      return
    }
    if (result.found === true) {
      const incomingName = result.name && result.name.length > 0 ? result.name : (result.englishName ? result.englishName : '')
      // 优先使用 objectType（C++ 返回的英文原始类型），便于 I18n.objectType() 正确切分复合类型并翻译
      const incomingType = (result.objectType && (result.objectType as string).length > 0)
        ? (result.objectType as string)
        : ((result.type && result.type.length > 0) ? result.type : 'Object')
      // 只有真正换了目标才重开详情。用户手动关闭同一目标后，任何后续刷新/误触
      // 都只更新数值，不能把卡片重新弹回来。
      const targetChanged = (this.selectedName !== incomingName) || (this.selectedType !== incomingType)
      const preserveClosedDetail = !this.infoWinVisible && !targetChanged && this.dismissedObjectName === incomingName
      const isNewSelection = targetChanged
      this.selectedName = incomingName
      this.selectedType = incomingType
      this.selectedStatus = 'Selected'
      const mag = (typeof result.magnitude === 'number') ? (result.magnitude as number) : 99
      this.selectedMagnitude = (mag < 98) ? mag.toFixed(2) : ''
      const apparentMag = (typeof result.apparentMagnitude === 'number') ? (result.apparentMagnitude as number) : 99
      this.selectedApparentMagnitude = (apparentMag < 98) ? apparentMag.toFixed(2) : ''
      this.selectedAirmass = typeof result.airmass === 'number' ? (result.airmass as number).toFixed(2) : ''
      this.selectedExtinction = typeof result.extinction === 'number' ? (result.extinction as number).toFixed(2) : ''
      // Keep the initial full detail text during the lightweight live refresh.
      if (result.fullInfo && result.fullInfo.length > 0) {
        this.selectedFullInfo = result.fullInfo
      }
      const ra: string = result.ra ? result.ra : ''
      const dec: string = result.dec ? result.dec : ''
      this.selectedCoordEq = (ra.length > 0 || dec.length > 0) ? (ra + '  ' + dec).trim() : ''
      const hasAlt: boolean = typeof result.altitude === 'number'
      const hasAz: boolean = typeof result.azimuth === 'number'
      this.gyroGuideTargetAlt = hasAlt ? result.altitude as number : Number.NaN
      this.gyroGuideTargetAz = hasAz ? result.azimuth as number : Number.NaN
      // A stationary device may not pass the sensor movement threshold again
      // after a search. Recalculate the edge guide at selection time instead
      // of waiting for the next meaningful orientation delta.
      if (this.gyroscopeEnabled) {
        this.updateGyroTargetGuide(true)
      }
      this.selectedCoordAlt = (hasAlt || hasAz)
        ? (I18n.t('coord_alt') + ' ' + (hasAlt ? this.fmtDegMin(result.altitude as number) : '--') + '  ' + I18n.t('coord_az') + ' ' + (hasAz ? this.fmtDegMin(result.azimuth as number) : '--'))
        : ''
      this.selectedConstellation = result.constellation && result.constellation.length > 0 ? result.constellation : ''
      this.selectedDistance = result.distance && result.distance.length > 0 ? result.distance : ''
      // 过滤接近0的角直径（小行星等天体角直径极小，显示0无意义）
      const rawSize = result.size && result.size.length > 0 ? result.size : ''
      if (rawSize.length > 0) {
        const sizeMatch = rawSize.match(/([\d.]+)/)
        if (sizeMatch && parseFloat(sizeMatch[1]) === 0) {
          this.selectedSize = ''
        } else {
          this.selectedSize = rawSize
        }
      } else {
        this.selectedSize = ''
      }
      this.selectedRise = result.rise && result.rise.length > 0 ? result.rise : ''
      this.selectedSet = result.set && result.set.length > 0 ? result.set : ''
      this.selectedTransit = result.transit && result.transit.length > 0 ? result.transit : ''
      this.selectedPhase = (typeof result.phase === 'number') ? (result.phase as number).toFixed(0) + '%' : ''
      this.selectedElongation = (typeof result.elongation === 'number') ? (result.elongation as number).toFixed(1) + '°' : ''
      this.selectedRich = result.info && result.info.length > 0 ? result.info : ''
      // 选中成功后弹出独立浮动详情窗口（新目标默认收起，不打扰当前菜单；同一目标刷新时保留展开态）
      if (targetChanged) {
        this.dismissedObjectName = ''
      }
      if (!preserveClosedDetail) {
        this.infoWinVisible = true
      }
      // The legacy "object" panel duplicates the inspector introduced for
      // selected targets. Close only that obsolete surface; panels such as
      // time, location, and layers must remain available while inspecting.
      if (this.activePanel === 'object' && this.panelVisible) {
        this.closePanel(true)
      }
      if (isNewSelection) {
        this.infoWinExpanded = false
        this.cardOffsetX = 0
        this.cardOffsetY = 0
        // The lightweight tap/search response deliberately has no AllInfo.
        // Never leave the previous target's prose visible while it is loading.
        this.selectedFullInfo = ''
        // Sensor tracking owns the camera. A gyro-mode search selects the
        // target and opens its card, but never starts a safe-area fly-to.
        if (!this.gyroscopeEnabled && (this.panelVisible || this.infoWinVisible)) {
          this.placeSelectedObjectInSafeArea()
        }
      }
      this.updateGyroTargetGuide(true)
      // 尝试从本地别名表补充中文简介
      const dispName = this.selectedName
      const alias = ALIAS_LIST.find(a => a.en === dispName || a.zh === dispName)
      this.selectedInfo = alias ? alias.zh : ''
      // 换了新天体 → 按它的"性格"响一声（模仿 Sky Guide 的叮）
      if (isNewSelection) {
        AudioEngine.getInstance().chimeForSelection(result)
        this.requestSelectedFullInfo(this.selectedName)
      }
      this.startDetailAutoRefresh()
    } else {
      this.selectedName = ''
      this.selectedType = ''
      this.selectedStatus = result.query && result.query.length > 0 ? 'Try English name' : 'No match'
      this.selectedMagnitude = ''
      this.selectedApparentMagnitude = ''
      this.selectedAirmass = ''
      this.selectedExtinction = ''
      this.selectedFullInfo = ''
      this.selectedCoordEq = ''
      this.selectedCoordAlt = ''
      this.selectedConstellation = ''
      this.selectedDistance = ''
      this.gyroGuideTargetAz = Number.NaN
      this.gyroGuideTargetAlt = Number.NaN
      this.gyroGuideVisible = false
      this.selectedSize = ''
      this.selectedRise = ''
      this.selectedSet = ''
      this.selectedTransit = ''
      this.selectedPhase = ''
      this.selectedElongation = ''
      this.selectedRich = ''
      this.infoWinVisible = false
      this.selectedInfo = '当前位置没有可选天体，请放大或使用搜索'
      this.clearRtsSelectionResults()
    }
  }

  private formatRate(rate: number): string {
    if (rate === 0 || Math.abs(rate) < 1e-18) {
      return I18n.t('msg_paused')
    }
    const secPerDay = 86400.0
    const absRate = Math.abs(rate)
    const sign = rate > 0 ? '' : '-'
    // Map common speeds to human-readable labels
    interface SpeedLabel { limit: number; label: string }
    const thresholds: SpeedLabel[] = [
      { limit: 2.0 / secPerDay,     label: '2x' } as SpeedLabel,
      { limit: 10.0 / secPerDay,    label: '10x' } as SpeedLabel,
      { limit: 60.0 / secPerDay,    label: '1分/秒' } as SpeedLabel,
      { limit: 360.0 / secPerDay,   label: '1时/秒' } as SpeedLabel,
      { limit: 1.0,                label: '1天/秒' } as SpeedLabel,
      { limit: 10.0,               label: '10天/秒' } as SpeedLabel,
    ] as SpeedLabel[]
    if (Math.abs(absRate - 1.0 / secPerDay) < 0.0000001) { return sign + '1x' }
    let speedLabel: string = ''
    for (const t of thresholds) {
      if (absRate <= t.limit * 1.01) { speedLabel = t.label; break }
    }
    if (speedLabel.length > 0) { return sign + speedLabel }
    const mult: number = absRate * secPerDay
    return sign + mult.toFixed(0) + 'x'
  }

  private formatDegrees(value: number, positive: string, negative: string): string {
    const direction = value >= 0 ? positive : negative
    return Math.abs(value).toFixed(2) + '°' + direction
  }

  private pad2(value: number): string {
    return value.toString().padStart(2, '0')
  }

  private formatLocalDateTime(date: Date): string {
    return date.getFullYear().toString() + '-' + this.pad2(date.getMonth() + 1) + '-' + this.pad2(date.getDate()) +
      ' ' + this.pad2(date.getHours()) + ':' + this.pad2(date.getMinutes()) + ':' + this.pad2(date.getSeconds())
  }

  /**
   * 轻量时间刷新：只取 jd + timeRate（getSimulationTime 极轻），不做 getState 全量状态同步。
   * 用于时间面板的高频（~120ms）流式刷新，让读秒像水一样连续流动而不是每秒跳一大格。
   * 注意：不要在这里改动除时间/速率以外的任何 @State，否则会引发全局重排、拖动星图变卡。
   */
  private refreshSimTimeLight(): void {
    this.callInteractive('getSimulationTime', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true || r.jd === undefined) { return }
      const jd: number = r.jd as number
      // jd 是 UTC；加上观测地 UTC 偏移后再格式化，与 getState 的 timeText 口径保持一致
      const text: string = this.jdToLocalTimeText(jd + this.utcOffsetHours / 24.0)
      if (text !== this.observationTimeText) {
        this.observationTimeText = text
      }
      if (r.timeRate !== undefined) {
        this.syncTimeRateState(r.timeRate as number)
      }
      if (!this.scrubberInteracting) {
        this.syncScrubberToSimulation(jd)
      }
      this.syncTimeWheelFromSimulation(jd)
    })
  }

  /** 儒略日 -> 'YYYY-MM-DD HH:mm:ss' 本地显示文本（入参需已含 UTC 偏移）。 */
  private jdToLocalTimeText(jd: number): string {
    // 用 UTC 取值避免设备时区二次偏移（jd 已带观测地偏移）
    const d = new Date((jd - 2440587.5) * 86400000)
    const p2 = (n: number): string => n < 10 ? '0' + n : n.toString()
    return d.getUTCFullYear() + '-' + p2(d.getUTCMonth() + 1) + '-' + p2(d.getUTCDate()) + ' ' +
      p2(d.getUTCHours()) + ':' + p2(d.getUTCMinutes()) + ':' + p2(d.getUTCSeconds())
  }

  private formatObservationTime(raw: string): string {
    if (!raw || raw.length === 0) {
      return '--'
    }
    // C++ has already applied the observation location's UTC offset before it
    // serializes timeText. Parsing the ISO value as a device-local Date applied
    // a second timezone conversion every 3 seconds, racing the lightweight JD
    // refresh and making the digits visibly jump. Preserve that local clock.
    let text = raw.trim()
    if (text.endsWith('Z')) {
      text = text.slice(0, -1)
    } else {
      const plus = text.lastIndexOf('+')
      const minus = text.lastIndexOf('-')
      const zoneStart = Math.max(plus, minus)
      if (zoneStart > 10) {
        text = text.slice(0, zoneStart)
      }
    }
    return text.replace('T', ' ')
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value))
  }

  private locationMapWidth(): number {
    if (this.isExpandedLayout) {
      return 292
    }
    return this.clamp(this.skyWidth * 0.92 - 32, 276, 620)
  }

  private locationMapHeight(): number {
    return this.isExpandedLayout ? 146 : 156
  }

  private setPickerLocation(name: string, latitude: number, longitude: number, altitude: number, status: ResourceStr): void {
    this.locationPickerName = name
    this.locationPickerLatitude = this.clamp(latitude, -90, 90)
    this.locationPickerLongitude = this.clamp(longitude, -180, 180)
    this.locationPickerAltitude = Math.round(altitude)
    this.locationPickerStatus = status
  }

  private updatePickerFromMap(x: number, y: number): void {
    const width = this.mapRenderWidth
    const height = this.mapRenderHeight
    const latitude = 90 - this.clamp(y, 0, height) / height * 180
    const longitude = this.clamp(x, 0, width) / width * 360 - 180
    this.setPickerLocation(I18n.t('m_map_pick'), latitude, longitude, this.locationPickerAltitude, I18n.t('m_map_selected'))
  }

  private pickerCoordinateText(): string {
    return this.formatDegrees(this.locationPickerLatitude, 'N', 'S') + ' / ' +
      this.formatDegrees(this.locationPickerLongitude, 'E', 'W') + ' / ' +
      this.locationPickerAltitude.toFixed(0) + ' m'
  }

  private pickerPinX(): number {
    return (this.locationPickerLongitude + 180) / 360 * this.mapRenderWidth - 9
  }

  private pickerPinY(): number {
    return (90 - this.locationPickerLatitude) / 180 * this.mapRenderHeight - 9
  }

  private handleLocationMapTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length < 1) {
      return
    }
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.updatePickerFromMap(points[0].x, points[0].y)
    } else if (event.type === TouchType.Up) {
      this.applyPickerLocation()
    }
  }

  // 阻止地图触摸事件冒泡到父Scroll，防止拖动地图时面板也跟着滚动
  private stopMapTouchPropagation(event: TouchEvent): boolean {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length >= 1) {
      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        this.updatePickerFromMap(points[0].x, points[0].y)
      } else if (event.type === TouchType.Up) {
        this.applyPickerLocation()
      }
    }
    return true
  }

  // 地图选点专用：手势回调，用 priorityGesture 绑定
  private mapPanStart(): void {
    this.mapGestureActive = true
  }

  private mapPanUpdate(x: number, y: number): void {
    this.updatePickerFromMap(x, y)
  }

  private mapPanEnd(): void {
    this.mapGestureActive = false
    this.applyPickerLocation()
  }

  private async useDeviceLocation(): Promise<void> {
    hilog.info(0x0000, 'StellariumArkUI', 'useDeviceLocation() called')
    this.locationPickerStatus = I18n.t('m_req_location_perm')
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const atManager = abilityAccessCtrl.createAtManager()
      const permissions: Array<Permissions> = [
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION'
      ]
      await atManager.requestPermissionsFromUser(context, permissions)
      this.locationPickerStatus = I18n.t('m_getting_location')
      const current = await geoLocationManager.getCurrentLocation({
        priority: geoLocationManager.LocationRequestPriority.ACCURACY,
        scenario: geoLocationManager.LocationRequestScenario.DAILY_LIFE_SERVICE,
        maxAccuracy: 2000,
        timeoutMs: 5000
      })
      const altitude = Number.isFinite(current.altitude) ? current.altitude : 0
      this.setPickerLocation(I18n.t('m_current_location'), current.latitude, current.longitude, altitude, I18n.t('m_device_loc_synced'))
      this.applyPickerLocation()
      this.locationPickMode = 'map'
      this.hierContinent = ''
      this.hierRegion = ''
      this.hierCity = ''
    } catch (err) {
      const errMsg: string = err instanceof Error ? err.message : JSON.stringify(err)
      hilog.warn(0x0000, 'StellariumArkUI', 'device location failed: %{public}s', errMsg)
      if (this.locationPickerLatitude === 0 && this.locationPickerLongitude === 0) {
        this.setPickerLocation(I18n.t('city_beijing'), 39.9, 116.4, 43, I18n.t('m_gps_sim_default'))
        this.applyPickerLocation()
      } else {
        this.locationPickerStatus = I18n.t('m_gps_unavailable')
        this.applyPickerLocation()
      }
    }
  }

  private applyPickerLocation(): void {
    this.setLocation(this.locationPickerName, this.locationPickerLatitude, this.locationPickerLongitude, this.locationPickerAltitude)
    // 延迟刷新时区信息（等C++侧location切换完成）
    setTimeout(() => { this.loadObserverInfo(false) }, 500)
  }

  private distance(x0: number, y0: number, x1: number, y1: number): number {
    const dx = x1 - x0
    const dy = y1 - y0
    return Math.sqrt(dx * dx + dy * dy)
  }


  private touchWindowX(point: TouchObject): number {
    return point.x ?? point.windowX ?? 0
  }

  private touchWindowY(point: TouchObject): number {
    return point.y ?? point.windowY ?? 0
  }

  private setLocation(name: string, latitude: number, longitude: number, altitude: number): void {
    // Update picker UI immediately (non-blocking, gives instant feedback)
    this.setPickerLocation(name, latitude, longitude, altitude, I18n.t('m_synced_to_sky'))
    this.locationText = this.locationDisplayName(name) + ' · ' + this.planetZh('Earth')
    this.coordinateText = this.formatDegrees(latitude, 'N', 'S') + ' / ' + this.formatDegrees(longitude, 'E', 'W')
    this.altitudeText = altitude.toFixed(0) + ' m'
    this.observerTimeZone = this.approximateTimeZoneDisplay(longitude)
    this.flashHint(I18n.t('i0073').replace('%s', this.locationDisplayName(name)))
    // 经纬度是地图选点和层级城市的共同事实源，先写坐标，避免名称查库失败或读回旧位置。
    this.callNativeWhenReady('setLocation', `${name}|${latitude}|${longitude}|${altitude}`, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.refreshState()
        setTimeout(() => { this.loadObserverInfo(false) }, 300)
      } else {
        hilog.info(0x0000, 'StellariumArkUI', 'setLocation failed, fallback to setLocationCoords')
        this.callNativeWhenReady('setLocationCoords', `${latitude},${longitude},${altitude}`, (r2: StellariumBridgeResponse) => {
          if (r2.ok === true) {
            this.refreshState()
            setTimeout(() => { this.loadObserverInfo(false) }, 300)
          } else {
            hilog.info(0x0000, 'StellariumArkUI', 'setLocationCoords failed, fallback to setLocationByName')
            this.callNativeWhenReady('setLocationByName', name, (r3: StellariumBridgeResponse) => {
              if (r3.ok === true) {
                this.refreshState()
                setTimeout(() => { this.loadObserverInfo(false) }, 300)
              }
            })
          }
        })
      }
    }, 0, 100, 10)
  }

  // ===== 位置搜索（调用C++ getLocationList命令）=====
  private searchLocations(query: string): void {
    const q = query.trim()
    if (q.length < 1) {
      this.locSearchResults = []
      this.locSearching = false
      return
    }
    this.locSearching = true
    this.callInteractive('getLocationList', q, (r: StellariumBridgeResponse) => {
      this.locSearching = false
      if (r.ok === true && r.locations) {
        const rawList = r.locations as Object[]
        this.locSearchResults = rawList.map((item: Object): LocSearchItem => {
          const loc = item as Record<string, string | number>
          return {
            name: (loc['name'] as string) ?? '',
            lat: (loc['lat'] as number) ?? 0,
            lon: (loc['lon'] as number) ?? 0,
            alt: (loc['alt'] as number) ?? 0,
            planet: (loc['planet'] as string) ?? 'Earth',
          } as LocSearchItem
        })
      } else {
        this.locSearchResults = []
      }
    })
  }

  private selectSearchLocation(item: LocSearchItem): void {
    this.setLocation(item.name, item.lat, item.lon, item.alt)
    this.locSearchQuery = ''
    this.locSearchResults = []
    this.locationPickMode = 'map'
  }

  // ===== 时区获取 =====
  private timezoneDisplayName(ianaTz: string): string {
    if (!ianaTz || ianaTz === 'system_default') return I18n.t('tz_system')
    // Translate common IANA timezone names
    const tzMap: Record<string, string> = {
      'Asia/Shanghai': I18n.t('tz_asia_shanghai'),
      'Asia/Hong_Kong': I18n.t('tz_asia_hongkong'),
      'Asia/Tokyo': I18n.t('tz_asia_tokyo'),
      'Asia/Seoul': I18n.t('tz_asia_seoul'),
      'Asia/Singapore': I18n.t('tz_asia_singapore'),
      'Asia/Taipei': I18n.t('tz_asia_taipei'),
      'Asia/Bangkok': I18n.t('tz_asia_bangkok'),
      'Asia/Kolkata': I18n.t('tz_asia_kolkata'),
      'Asia/Dubai': I18n.t('tz_asia_dubai'),
      'Europe/London': I18n.t('tz_europe_london'),
      'Europe/Paris': I18n.t('tz_europe_paris'),
      'Europe/Berlin': I18n.t('tz_europe_berlin'),
      'Europe/Madrid': I18n.t('tz_europe_madrid'),
      'Europe/Moscow': I18n.t('tz_europe_moscow'),
      'America/New_York': I18n.t('tz_america_newyork'),
      'America/Chicago': I18n.t('tz_america_chicago'),
      'America/Los_Angeles': I18n.t('tz_america_losangeles'),
      'America/Sao_Paulo': I18n.t('tz_america_saopaulo'),
      'Australia/Sydney': I18n.t('tz_australia_sydney'),
      'Pacific/Auckland': I18n.t('tz_pacific_auckland'),
      'UTC': 'UTC',
      'GMT': 'GMT',
    }
    const mapped = tzMap[ianaTz]
    if (mapped) return mapped
    // For unmapped, try to translate the region/city names
    const parts = ianaTz.split('/')
    if (parts.length >= 2) {
      const regionMap: Record<string, string> = {
        'Asia': I18n.t('tz_region_asia'),
        'Europe': I18n.t('tz_region_europe'),
        'America': I18n.t('tz_region_america'),
        'Africa': I18n.t('tz_region_africa'),
        'Pacific': I18n.t('tz_region_pacific'),
        'Australia': I18n.t('tz_region_australia'),
        'Antarctica': I18n.t('tz_region_antarctica'),
        'Atlantic': I18n.t('tz_region_atlantic'),
        'Indian': I18n.t('tz_region_indian'),
        'Arctic': I18n.t('tz_region_arctic'),
      }
      const region = regionMap[parts[0]] ?? parts[0]
      const city = parts[parts.length - 1].replace(/_/g, ' ')
      return region + ' / ' + city
    }
    return ianaTz
  }

  private approximateTimeZoneDisplay(longitude: number): string {
    const offset = this.clamp(Math.round(longitude / 15), -12, 14)
    if (offset === 0) {
      return 'UTC'
    }
    return 'UTC' + (offset > 0 ? '+' : '') + offset.toString()
  }

  private loadObserverInfo(updateTimeZone: boolean = true): void {
    this.callInteractive('getObserverInfo', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        if (updateTimeZone) {
          this.observerTimeZone = this.timezoneDisplayName(r.timeZone ?? '')
        }
        if (r.planetName) {
          this.observerPlanet = r.planetName
        }
      }
    })
  }

  // ===== 已保存位置管理（持久化到 preferences）=====
  private loadSavedLocations(): void {
    try {
      const prefs = AppStorage.get<Record<string, Object>>('stellariumPrefs')
      if (prefs && prefs['savedLocations']) {
        const raw = prefs['savedLocations'] as Object[]
        this.savedLocations = raw.map((item: Object): SavedLocation => {
          const loc = item as Record<string, string | number>
          return {
            name: (loc['name'] as string) ?? '',
            lat: (loc['lat'] as number) ?? 0,
            lon: (loc['lon'] as number) ?? 0,
            alt: (loc['alt'] as number) ?? 0,
            planet: (loc['planet'] as string) ?? 'Earth',
          } as SavedLocation
        })
      }
    } catch (e) {
      hilog.info(0x0000, 'StellariumArkUI', 'loadSavedLocations error: %{public}s', (e as Error).message ?? '')
    }
  }

  private saveCurrentLocation(): void {
    const name = this.locationPickerName
    // 检查是否已存在
    const exists = this.savedLocations.some((s: SavedLocation) => s.name === name)
    if (exists) {
      this.flashHint(I18n.t('loc_already_saved'))
      return
    }
    const item: SavedLocation = {
      name: name,
      lat: this.locationPickerLatitude,
      lon: this.locationPickerLongitude,
      alt: this.locationPickerAltitude,
      planet: this.observerPlanet,
    }
    this.savedLocations = [...this.savedLocations, item]
    this.persistSavedLocations()
    this.flashHint(I18n.t('loc_saved_success'))
  }

  private deleteSavedLocation(name: string): void {
    this.savedLocations = this.savedLocations.filter((s: SavedLocation) => s.name !== name)
    this.persistSavedLocations()
  }

  private persistSavedLocations(): void {
    try {
      let prefs = AppStorage.get<Record<string, Object>>('stellariumPrefs')
      if (!prefs) {
        prefs = {} as Record<string, Object>
      }
      prefs['savedLocations'] = this.savedLocations
      AppStorage.setOrCreate<Record<string, Object>>('stellariumPrefs', prefs)
    } catch (e) {
      hilog.info(0x0000, 'StellariumArkUI', 'persistSavedLocations error: %{public}s', (e as Error).message ?? '')
    }
  }

  private loadPlanetList(): void {
    this.callInteractive('getObserverPlanetList', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.planets) {
        // 只保留"有专属地景、能站着看天+换地景"的星球；getAllPlanetEnglishNames
        // 还会返回大量彗星/矮行星，列出来既冗长又无对应地景，对切星球毫无意义。
        const standable = ['Earth', 'Moon', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Sun']
        const all = r.planets as string[]
        this.planetList = standable.filter((s) => all.indexOf(s) >= 0)
      }
    })
  }

  private setObserverPlanet(name: string): void {
    this.callInteractive('setObserverPlanet', name, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.observerPlanet = name
        this.refreshState()
        this.flashHint('已切换观测星球：' + name)
      } else {
        this.flashHint('切换失败：' + (r.error ?? 'unknown'))
      }
    })
  }

  @Builder
  observerPlanetSection() {
    Column({ space: 8 }) {
      Text(I18n.t('c_observing_planet')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_planet_switch_hint')).fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      Text(I18n.t('m_current_planet') + '：' + this.planetZh(this.observerPlanet)).fontSize(12).fontColor('#E5FFFFFF').width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.planetList, (p: string) => {
          Button(this.planetZh(p))
            .fontSize(12)
            .fontColor(this.observerPlanet === p ? '#FFFFFF' : '#CCFFFFFF')
            .backgroundColor(this.observerPlanet === p ? '#5B93BF' : this.nmBorder())
            .borderRadius(16)
            .height(32)
            .margin({ right: 8, bottom: 8 })
            .padding({ left: 14, right: 14 })
            .onClick(() => { this.setObserverPlanet(p) })
        }, (p: string) => p)
      }.width('100%')
      Button(I18n.t('btn_back_to_earth'))
        .fontSize(13).fontColor('#FFFFFF').backgroundColor('#2E7D32')
        .borderRadius(10).height(34).width('100%').margin({ top: 6 })
        .onClick(() => { this.setObserverPlanet('Earth') })
    }.width('100%').padding({ left: 10, right: 10 })
  }

  // 虚拟指星笔（多设备联动）目标端测试入口：输入高度角/方位角，调 pointAtSky
  // 把星图中心转到该方向并选中那颗星。手表/分布式未来只是另一种触发方式。
  @Builder
  pointingTestSection() {
    Column({ space: 8 }) {
      Text(I18n.t('c_pointing_test')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_pointing_test_desc')).fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      Row({ space: 8 }) {
        TextInput({ text: this.pointAlt, placeholder: I18n.t('c_altitude_deg') })
          .width('50%').height(36).backgroundColor(this.nmBorder()).fontSize(13)
          .onChange((v: string) => { this.pointAlt = v })
        TextInput({ text: this.pointAz, placeholder: I18n.t('c_azimuth_deg') })
          .width('50%').height(36).backgroundColor(this.nmBorder()).fontSize(13)
          .onChange((v: string) => { this.pointAz = v })
      }.width('100%')
      // 把结果放在按钮上方，避免被 Scroll 底部遮挡而看不到即时反馈
      if (this.pointResult !== '') {
        Text(this.pointResult).fontSize(12).fontColor('#CCFFCC').width('100%').margin({ top: 2 })
      }
      Row({ space: 8 }) {
        Button(I18n.t('btn_point_select'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#5B93BF')
          .borderRadius(10).height(34).layoutWeight(1)
          .onClick(() => { this.pointAtSkyTest() })
        Button(I18n.t('btn_example_zenith'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor(this.nmBorder())
          .borderRadius(10).height(34).layoutWeight(1)
          .onClick(() => { this.pointAlt = '89'; this.pointAz = '180'; this.pointAtSkyTest() })
      }.width('100%').margin({ top: 4 })
    }.width('100%').padding({ left: 10, right: 10 })
  }

  private pointAtSkyTest(): void {
    const alt = this.pointAlt.trim()
    const az = this.pointAz.trim()
    this.callNativeWhenReady('pointAtSky', alt + '|' + az, (r: StellariumBridgeResponse) => {
      if (!r.ok) {
        this.pointResult = '指星笔命令未响应'
        this.flashHint('指星笔命令未响应')
        return
      }
      this.pointResult = '已指向 高度角' + alt + '° 方位角' + az + '°（星图下一帧转过去并选中中心星）'
      this.flashHint('星图已转向 ' + alt + '°/' + az + '°')
      // 等一帧让 pointAtSky 完成中心选中，再读选中天体
      setTimeout(() => {
        this.callNativeWhenReady('getSelectedObjectInfo', '', (r2: StellariumBridgeResponse) => {
          if (!r2.ok) return
          if (r2.found) {
            const nm = (r2.name !== undefined && r2.name !== null) ? String(r2.name) : '未知'
            const tp = (r2.type !== undefined && r2.type !== null) ? String(r2.type) : ''
            this.pointResult = '指向命中：' + nm + '（' + tp + '）'
            this.flashHint('指向命中：' + nm)
          } else {
            this.pointResult = '指向方向：' + alt + '°/' + az + '° 该处暂无可选中天体'
            this.flashHint('该处暂无可选中天体')
          }
        })
      }, 400)
    })
  }

  // 虚拟指星笔 —— 手表当陀螺仪（发射端模拟）
  // 手表 IMU(加速度/陀螺仪/方向传感器) 实时算出 alt|az，通过软总线发给大屏；大屏用
  // pointAtSky track=1 每帧平滑跟随。这里用滑块模拟手腕转动当发射端，验证整条链路。
  @Builder
  watchGyroSection() {
    Column({ space: 8 }) {
      Text(I18n.t('c_watch_gyro_sim')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_watch_gyro_desc'))
        .fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      if (this.watchResult !== '') {
        Text(this.watchResult).fontSize(12).fontColor(this.watchTracking ? '#FFE08A' : '#CCFFCC').width('100%').margin({ top: 2, bottom: 2 })
      }
      Row({ space: 10 }) {
        Text(I18n.t('c_altitude')).fontSize(11).fontColor('#CCCCCC').width(48)
        Slider({ value: this.watchAlt, min: 0, max: 90, step: 1 })
          .layoutWeight(1)
          .onChange((v: number) => { this.watchAlt = v; this.watchGyroSend() })
      }.width('100%')
      Row({ space: 10 }) {
        Text(I18n.t('c_azimuth')).fontSize(11).fontColor('#CCCCCC').width(48)
        Slider({ value: this.watchAz, min: 0, max: 360, step: 1 })
          .layoutWeight(1)
          .onChange((v: number) => { this.watchAz = v; this.watchGyroSend() })
      }.width('100%')
      Row({ space: 8 }) {
        Button(this.watchTracking ? '指向中…' : '开始指向(跟踪)')
          .fontSize(13).fontColor('#FFFFFF').backgroundColor(this.watchTracking ? '#C08020' : '#5B93BF')
          .borderRadius(10).height(34).layoutWeight(1)
          .onClick(() => { this.watchGyroStart() })
        Button(I18n.t('btn_stop_lock'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#3A6EA5')
          .borderRadius(10).height(34).layoutWeight(1)
          .onClick(() => { this.watchGyroStop() })
      }.width('100%').margin({ top: 4 })
    }.width('100%').padding({ left: 10, right: 10 })
  }

  private watchGyroSend(): void {
    if (!this.watchTracking) return
    const now = Date.now()
    if (now - this.watchLastSend < 70) return // 节流，避免拖动时刷爆命令队列
    this.watchLastSend = now
    const alt = this.watchAlt
    const az = this.watchAz
    this.callNativeWhenReady('pointAtSky', alt + '|' + az + '|1', (r: StellariumBridgeResponse) => {
      if (!r.ok) { this.watchResult = '手表指向未响应'; return }
      // 跟踪模式只负责跟随，不刷文本，避免抖动
    })
  }

  private watchGyroStart(): void {
    this.watchTracking = true
    this.watchResult = '手表指向中：拖动滑块，大屏实时跟随（像陀螺仪追手）'
    this.flashHint(I18n.t('msg_watch_pointing_started'))
    this.watchGyroSend()
  }

  // Jump to specific RA/Dec coordinates (J2000 equatorial).
  private goToCoordinates(): void {
    const raStr: string = this.coordInputRA.trim()
    const decStr: string = this.coordInputDec.trim()
    if (raStr.length === 0 || decStr.length === 0) { return }
    // Parse RA: support formats like "5.5", "5h30m", "05:30:00"
    let raHours: number = 0
    if (raStr.includes('h')) {
      const parts: string[] = raStr.replace('m', '').split('h')
      raHours = parseFloat(parts[0]) + (parts.length > 1 ? parseFloat(parts[1]) / 60 : 0)
    } else if (raStr.includes(':')) {
      const parts: string[] = raStr.split(':')
      raHours = parseFloat(parts[0]) + (parts.length > 1 ? parseFloat(parts[1]) / 60 : 0) + (parts.length > 2 ? parseFloat(parts[2]) / 3600 : 0)
    } else {
      raHours = parseFloat(raStr)
    }
    // Parse Dec: support formats like "+45.5", "45:30:00", "-45d30m"
    let decDeg: number = 0
    const decClean: string = decStr.replace(/[d°′″'"]/g, '')
    if (decClean.includes(':')) {
      const parts: string[] = decClean.split(':')
      decDeg = parseFloat(parts[0]) + (parts.length > 1 ? parseFloat(parts[1]) / 60 : 0) + (parts.length > 2 ? parseFloat(parts[2]) / 3600 : 0)
    } else {
      decDeg = parseFloat(decClean)
    }
    if (isNaN(raHours) || isNaN(decDeg)) { return }
    this.callInteractive('gotoRADec', `${raHours}|${decDeg}`, (r: StellariumBridgeResponse) => {
      if (!r.ok) {
        this.flashHint(I18n.t('msg_navigation_failed'))
        return
      }
      this.flashHint(I18n.t('msg_goto_coord'))
    })
  }

  private watchGyroStop(): void {
    this.watchTracking = false
    this.callNativeWhenReady('pointAtSkyStop', '', (r: StellariumBridgeResponse) => {
      if (!r.ok) { this.watchResult = '锁定失败'; return }
      this.watchResult = '已停止指向，正在锁定中心星…'
      setTimeout(() => {
        this.callNativeWhenReady('getSelectedObjectInfo', '', (r2: StellariumBridgeResponse) => {
          if (!r2.ok) return
          if (r2.found) {
            const nm = (r2.name !== undefined && r2.name !== null) ? String(r2.name) : '未知'
            const tp = (r2.type !== undefined && r2.type !== null) ? String(r2.type) : ''
            this.watchResult = '🎯 锁定命中：' + nm + '（' + tp + '）'
            this.flashHint(I18n.t('m_lock_hit') + ': ' + nm)
          } else {
            this.watchResult = I18n.t('m_no_target_dir')
            this.flashHint(I18n.t('m_no_target_dir'))
          }
        })
      }, 400)
    })
  }

  // 多设备接续 / 无缝流转（能力 A 的"会话搬运"目标端 + 脚手架）
  // 把当前星图会话(视线/FOV/时间/位置/选中星)导出成 JSON，可在另一台鸿蒙设备导入接续；
  // 完整跨设备一键流转需华为分布式软总线(Distributed Hardware Kit)。当前基础 SDK 已把
  // "导出/导入"做成统一命令桥，切到含分布式能力的 SDK 后这里即可改为设备发现+拉起目标 Ability。
  @Builder
  continuationSection() {
    Column({ space: 8 }) {
      Text(I18n.t('c_continuation')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_continuation_desc'))
        .fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      if (this.sessionHint !== '') {
        Text(this.sessionHint).fontSize(12).fontColor('#CCFFCC').width('100%').margin({ top: 2, bottom: 2 })
      }
      Row({ space: 8 }) {
        Button(I18n.t('btn_export_session'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#5B93BF')
          .borderRadius(10).height(34).layoutWeight(1)
          .onClick(() => { this.sessionExport() })
        Button(I18n.t('btn_apply_local'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor(this.nmBorder())
          .borderRadius(10).height(34).layoutWeight(1)
          .onClick(() => { this.sessionApply() })
      }.width('100%').margin({ top: 4 })
      Button(I18n.t('btn_start_continuation'))
        .fontSize(13).fontColor('#FFFFFF').backgroundColor('#3A6EA5')
        .borderRadius(10).height(34).width('100%').margin({ top: 4 })
        .onClick(() => { this.sessionHandoff() })
      if (this.sessionJson !== '') {
        Scroll() {
          Text(this.sessionJson)
            .fontSize(10).fontColor('#BBBBBB').fontFamily('monospace')
            .width('100%').padding(6)
        }.height(160).width('100%').backgroundColor('#1A1A1A').borderRadius(8).margin({ top: 4 })
      }
    }.width('100%').padding({ left: 10, right: 10 })
  }

  @Builder tonightEventsSection() {
    Column({ space: 8 }) {
      Text(I18n.t('c_tonight_events')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_tonight_events_hint'))
        .fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      Button(I18n.t('btn_refresh_tonight'))
        .fontSize(13).fontColor('#FFFFFF').backgroundColor('#5B93BF')
        .borderRadius(10).height(34).width('100%')
        .onClick(() => { this.refreshTonight() })
      if (this.tonightHint !== '') {
        Text(this.tonightHint).fontSize(12).fontColor('#CCFFCC').width('100%').margin({ top: 2, bottom: 2 })
      }
      if (this.tonightDate !== '') {
        this.tonightCard(I18n.t('tn_moon_phase'), [this.tonightMoon], this.tonightMoonJd, 'Moon')
        this.tonightCard(I18n.t('tn_sun_dark_window'), [this.tonightSun, this.tonightDark], this.tonightSunJd, 'Moon')
        ForEach(this.tonightPlanetRows, (row: TonightPlanetRow) => {
          this.tonightCard(row.name, [row.line], row.jd, row.lock)
        }, (row: TonightPlanetRow) => row.name)
        if (this.tonightShowers.length > 0) this.tonightCard(I18n.t('tn_active_showers'), this.tonightShowers, this.tonightShowerJd, 'Moon')
        this.tonightCard(I18n.t('tn_satellites'), [this.tonightSats])
      }
    }.width('100%').padding({ left: 10, right: 10 })
  }

  @Builder tonightCard(title: string, lines: string[], jd?: number, lock?: string) {
    Column({ space: 4 }) {
      Text(title).fontSize(12).fontColor('#FFE9B0').width('100%')
      ForEach(lines, (ln: string) => {
        Text(ln).fontSize(11).fontColor('#DDDDDD').width('100%')
      }, (ln: string) => ln)
    }.width('100%').padding(8).backgroundColor('#1A2330').borderRadius(8).margin({ top: 4 })
      .stateStyles({
        pressed: { backgroundColor: '#27384A' }
      })
      .onClick(() => {
        if (jd !== undefined && jd > 0 && lock) {
          this.gotoTonightEvent(jd, lock, title)
        }
      })
  }

  private refreshTonight(): void {
    this.callNativeWhenReady('getTonightEvents', '', (r: StellariumBridgeResponse) => {
      if (!r.ok || !r.tonight) { this.flashHint(I18n.t('msg_fetch_failed')); return }
      const t = r.tonight as TonightEvents
      this.tonightDate = this.fmtIso(t.date ?? '')
      this.tonightMoon = I18n.t('tn_phase') + ': ' + (t.moon?.phaseName ?? I18n.t('m_unknown')) + ' (' + I18n.t('tn_illumination') + ' ' + Math.round(t.moon?.illumination ?? 0) + '% · ' + I18n.t('tn_moon_age') + ' ' + (t.moon?.age ?? 0).toFixed(1) + ' ' + I18n.t('tn_days') + ')\n'
        + '  ' + I18n.t('tn_rise') + ' ' + this.fmtIso(t.moon?.rise ?? '') + ' · ' + I18n.t('tn_transit') + ' ' + this.fmtIso(t.moon?.transit ?? '') + ' · ' + I18n.t('tn_set') + ' ' + this.fmtIso(t.moon?.set ?? '')
      this.tonightSun = I18n.t('tn_rise') + ' ' + this.fmtIso(t.sun?.rise ?? '') + ' · ' + I18n.t('tn_transit') + ' ' + this.fmtIso(t.sun?.transit ?? '') + ' · ' + I18n.t('tn_set') + ' ' + this.fmtIso(t.sun?.set ?? '')
      this.tonightDark = I18n.t('tn_astro_dusk') + ' ' + this.fmtIso(t.sun?.astroTwilightEnd ?? '') + ' → ' + I18n.t('tn_astro_dawn') + ' ' + this.fmtIso(t.sun?.astroTwilightStart ?? '')
        + (t.sun?.darkWindowHours !== undefined ? (' (' + I18n.t('tn_dark_hours') + ' ~' + t.sun.darkWindowHours.toFixed(1) + ' ' + I18n.t('tn_hours') + ')') : '')
      this.tonightPlanetRows = (t.planets ?? []).map((p) => {
        const vis = p.visible === true ? I18n.t('tn_visible') : I18n.t('tn_below_horizon')
        return {
          name: p.name ?? (p.englishName ?? ''),
          line: I18n.t('tn_rise') + ' ' + this.fmtIso(p.rise ?? '') + ' · ' + I18n.t('tn_transit') + ' ' + this.fmtIso(p.transit ?? '') + ' · ' + I18n.t('tn_set') + ' ' + this.fmtIso(p.set ?? '')
            + ' · ' + I18n.t('tn_magnitude') + ' ' + (p.magnitude ?? 0).toFixed(1) + ' · ' + vis,
          jd: p.transitJd ?? 0,
          lock: p.englishName ?? (p.name ?? '')
        }
      })
      this.tonightShowers = (t.meteorShowers ?? []).map((s) => (s.name ?? '') + ': ZHR~' + (s.zhr ?? 0) + (s.status === 'confirmed' ? ' (' + I18n.t('tn_confirmed') + ')' : ' (' + I18n.t('tn_generic') + ')'))
      this.tonightSats = ((t.satellites?.enabled ?? false) ? (I18n.t('tn_loaded') + ' ' + (t.satellites?.count ?? 0) + ' ' + I18n.t('tn_sats_count')) : I18n.t('tn_not_enabled')) + ' (' + I18n.t('tn_transit_needs_data') + ')'
      // 点击跳转的时间基准
      this.tonightMoonJd = t.moon?.transitJd ?? 0
      this.tonightSunJd = t.sun?.astroTwilightEndJd ?? 0
      this.tonightShowerJd = (t.meteorShowers && t.meteorShowers.length > 0) ? (t.meteorShowers[0].primeJd ?? this.tonightSunJd) : this.tonightSunJd
      this.tonightHint = I18n.t('tn_updated') + ' · ' + this.fmtIso(t.date ?? '')
      this.flashHint('已刷新今晚天象 · 点击卡片可跳转')
    })
  }

  // 点击今晚天象卡片：跳到事件发生时刻，并锁定主角(lock)、框入卫星(月球)
  private gotoTonightEvent(jd: number, lock: string, title: string): void {
    const label = title.replace(/[^0-9A-Za-z\u4e00-\u9fa5]/g, '')
    this.flashHint(I18n.t('msg_navigating'))
    this.callNativeWhenReady('setJD', jd.toString(), () => {
      this.callNativeWhenReady('searchObject', lock, (r2: StellariumBridgeResponse) => {
        this.frameSatellite()
        const found = r2.found === true
        this.flashHint(found
          ? ('已跳至『' + label + '』时刻，锁定『' + lock + '』并框入月球(卫星)')
          : ('已跳至『' + label + '』时刻，但未找到『' + lock + '』'))
      })
    })
  }

  // 跳转后若视角过窄，适当拉远以便把卫星(月球)一并收入视野
  private frameSatellite(): void {
    this.callNativeWhenReady('getSessionState', '', (r: StellariumBridgeResponse) => {
      const fov = (r.fovDeg ?? 0)
      if (fov > 0 && fov < 12) {
        const target = 16
        this.callNativeWhenReady('zoomBy', (target / fov).toFixed(3) + '|0')
      }
    })
  }

  private fmtIso(iso: string): string {
    if (!iso || iso.length < 16) return '--'
    const parts = iso.split('T')
    const d = parts[0] ?? ''
    const t = parts[1] ?? ''
    return (d.length >= 10 ? d.slice(5) : d) + ' ' + (t.length >= 8 ? t.slice(0, 5) : t)
  }

  private sessionSignature(r: StellariumBridgeResponse): string {
    const v = r.viewJ2000
    const vr: number[] = (v && v.length === 3) ? v.map((x: number) => Math.round(x * 1e4) / 1e4) : [0, 0, 0]
    const locObj = r.location as Record<string, Object>
    const locName = (r.location && locObj['name'] !== undefined) ? String(locObj['name']) : ''
    return [vr.join(','), Math.round((r.fovDeg ?? 0) * 100) / 100, r.selected ?? '', locName].join('|')
  }

  private sessionSummary(r: StellariumBridgeResponse): string {
    const locObj = r.location as Record<string, Object>
    const planet = (r.location && locObj['planetName'] !== undefined) ? String(locObj['planetName']) : 'Earth'
    return 'FOV ' + (r.fovDeg ?? 0).toFixed(1) + '° · ' + planet + ' · ' + (r.selected ? ('选中 ' + r.selected) : '未选中')
  }

  private sessionExport(): void {
    this.callNativeWhenReady('getSessionState', '', (r: StellariumBridgeResponse) => {
      if (!r.ok) { this.sessionHint = '导出失败'; return }
      const snap: SessionSnapshot = {
        viewJ2000: r.viewJ2000,
        fovDeg: r.fovDeg,
        jd: r.jd,
        location: r.location,
        selected: r.selected,
        flags: r.flags
      }
      this.sessionJson = JSON.stringify(snap, null, '  ')
      this.sessionExportSig = this.sessionSignature(r)
      this.sessionHint = '已导出：' + this.sessionSummary(r)
      this.flashHint('已导出当前会话')
    })
  }

  private sessionApply(): void {
    const json = this.sessionJson.trim()
    if (!json) { this.sessionHint = '请先点"导出当前会话"生成 JSON'; return }
    this.callNativeWhenReady('applySessionState', json, (r2: StellariumBridgeResponse) => {
      if (!r2.ok) { this.sessionHint = I18n.t('m_apply_failed') + ': ' + (r2.error ?? I18n.t('m_unknown')); this.flashHint(I18n.t('m_apply_failed')); return }
      this.sessionHint = I18n.t('m_session_applied_syncing')
      this.flashHint('正在接续远端会话…')
      // 等一帧让 applySessionState 生效，再导出比对，验证无缝还原
      setTimeout(() => {
        this.callNativeWhenReady('getSessionState', '', (r3: StellariumBridgeResponse) => {
          if (!r3.ok) return
          const sig = this.sessionSignature(r3)
          if (sig === this.sessionExportSig) {
            this.sessionHint = '✓ 无缝接续成功：本机已精确还原远端视角/位置/选中星'
            this.flashHint('✓ 无缝接续成功')
          } else {
            this.sessionHint = I18n.t('m_session_applied_done')
            this.flashHint('已接续远端会话')
          }
        })
      }, 500)
    })
  }

  private sessionHandoff(): void {
    // 完整形态需华为分布式软总线(Distributed Hardware Kit)：
    //   const dm = distributedHardware.createDeviceManager()
    //   const devs = dm.getAvailableDeviceListSync()          // 同账号设备
    //   continuationManager.startContinuation(...)            // 拉起目标 Ability 并带 want 参数
    // 当前基础 SDK 无这些 kit，故先给出可落地的本地能力说明。
    if (this.canUseDistributed) {
      this.flashHint(I18n.t('msg_continuation_initiated'))
      this.sessionHint = I18n.t('m_continuation_migrating')
    } else {
      this.flashHint(I18n.t('m_continuation_basic_sdk'))
      this.sessionHint = I18n.t('m_continuation_basic_desc')
    }
  }

  private hierContinents(): Array<string> {
    return Object.keys(LOCATION_HIERARCHY)
  }

  // Translate continent name from Chinese to current language
  private translateContinent(name: string): string {
    const map: Record<string, string> = {
      '亚洲': I18n.t('continent_asia'),
      '欧洲': I18n.t('continent_europe'),
      '北美洲': I18n.t('continent_north_america'),
      '南美洲': I18n.t('continent_south_america'),
      '非洲': I18n.t('continent_africa'),
      '大洋洲': I18n.t('continent_oceania'),
      '南极洲': I18n.t('continent_antarctica'),
    }
    return map[name] ?? name
  }

  // Translate region/city names to current language
  private translateRegion(name: string): string {
    if (!name || name === '未知地区') return I18n.t('region_unknown')
    if (I18n.getLanguage() === 'zh_CN') {
      // Keep the upstream name as the native lookup key; Chinese UI never
      // falls back to that key, so incomplete source data cannot leak Latin text.
      return LOCATION_ZH_NAMES[name] ?? '未收录地点'
    }
    // Region names are city/timezone names from Stellarium's base_locations
    // Use I18n for known regions, fallback to original name
    const regionMap: Record<string, string> = {
      'Tokyo': I18n.t('city_tokyo'),
      'Seoul': I18n.t('city_seoul'),
      'Shanghai': I18n.t('city_shanghai'),
      'Hong Kong': I18n.t('city_hongkong'),
      'Taipei': I18n.t('city_taipei'),
      'Singapore': I18n.t('city_singapore'),
      'Bangkok': I18n.t('city_bangkok'),
      'Jakarta': I18n.t('city_jakarta'),
      'Kuala Lumpur': I18n.t('city_kuala_lumpur'),
      'Manila': I18n.t('city_manila'),
      'Ho Chi Minh': I18n.t('city_ho_chi_minh'),
      'Hanoi': I18n.t('city_hanoi'),
      'Beijing': I18n.t('city_beijing'),
      'New York': I18n.t('city_new_york'),
      'Los Angeles': I18n.t('city_los_angeles'),
      'Chicago': I18n.t('city_chicago'),
      'Toronto': I18n.t('city_toronto'),
      'Vancouver': I18n.t('city_vancouver'),
      'London': I18n.t('city_london'),
      'Paris': I18n.t('city_paris'),
      'Berlin': I18n.t('city_berlin'),
      'Madrid': I18n.t('city_madrid'),
      'Rome': I18n.t('city_rome'),
      'Moscow': I18n.t('city_moscow'),
      'Istanbul': I18n.t('city_istanbul'),
      'Athens': I18n.t('city_athens'),
      'Dubai': I18n.t('city_dubai'),
      'Tehran': I18n.t('city_tehran'),
      'Riyadh': I18n.t('city_riyadh'),
      'Jerusalem': I18n.t('city_jerusalem'),
      'Cairo': I18n.t('city_cairo'),
      'Lagos': I18n.t('city_lagos'),
      'Nairobi': I18n.t('city_nairobi'),
      'Johannesburg': I18n.t('city_johannesburg'),
      'Sydney': I18n.t('city_sydney'),
      'Melbourne': I18n.t('city_melbourne'),
      'Auckland': I18n.t('city_auckland'),
      'Honolulu': I18n.t('city_honolulu'),
      'Mumbai': I18n.t('city_mumbai'),
      'Kolkata': I18n.t('city_kolkata'),
      'Delhi': I18n.t('city_delhi'),
      'Karachi': I18n.t('city_karachi'),
      'Dhaka': I18n.t('city_dhaka'),
      'Colombo': I18n.t('city_colombo'),
      'Kathmandu': I18n.t('city_kathmandu'),
      'Yangon': I18n.t('city_yangon'),
      'Phnom Penh': I18n.t('city_phnom_penh'),
      'Vientiane': I18n.t('city_vientiane'),
      'Brunei': I18n.t('city_brunei'),
      'Macau': I18n.t('city_macau'),
      'Pyongyang': I18n.t('city_pyongyang'),
      'Ulaanbaatar': I18n.t('city_ulaanbaatar'),
      'Almaty': I18n.t('city_almaty'),
      'Tashkent': I18n.t('city_tashkent'),
      'Baku': I18n.t('city_baku'),
      'Tbilisi': I18n.t('city_tbilisi'),
      'Yerevan': I18n.t('city_yerevan'),
      'Kabul': I18n.t('city_kabul'),
      'Amman': I18n.t('city_amman'),
      'Beirut': I18n.t('city_beirut'),
      'Damascus': I18n.t('city_damascus'),
      'Baghdad': I18n.t('city_baghdad'),
      'Kuwait': I18n.t('city_kuwait'),
      'Muscat': I18n.t('city_muscat'),
      'Doha': I18n.t('city_doha'),
      'Bahrain': I18n.t('city_bahrain'),
      'Aden': I18n.t('city_aden'),
      'Khartoum': I18n.t('city_khartoum'),
      'Tripoli': I18n.t('city_tripoli'),
      'Tunis': I18n.t('city_tunis'),
      'Algiers': I18n.t('city_algiers'),
      'Casablanca': I18n.t('city_casablanca'),
      'Accra': I18n.t('city_accra'),
      'Dakar': I18n.t('city_dakar'),
      'Abidjan': I18n.t('city_abidjan'),
      'Addis Ababa': I18n.t('city_addis_ababa'),
      'Dar es Salaam': I18n.t('city_dar_es_salaam'),
      'Lusaka': I18n.t('city_lusaka'),
      'Harare': I18n.t('city_harare'),
      'Kigali': I18n.t('city_kigali'),
      'Bujumbura': I18n.t('city_bujumbura'),
      'Maputo': I18n.t('city_maputo'),
      'Antananarivo': I18n.t('city_antananarivo'),
      'Vienna': I18n.t('city_vienna'),
      'Prague': I18n.t('city_prague'),
      'Warsaw': I18n.t('city_warsaw'),
      'Budapest': I18n.t('city_budapest'),
      'Bucharest': I18n.t('city_bucharest'),
      'Sofia': I18n.t('city_sofia'),
      'Belgrade': I18n.t('city_belgrade'),
      'Zagreb': I18n.t('city_zagreb'),
      'Ljubljana': I18n.t('city_ljubljana'),
      'Sarajevo': I18n.t('city_sarajevo'),
      'Skopje': I18n.t('city_skopje'),
      'Tirane': I18n.t('city_tirane'),
      'Kyiv': I18n.t('city_kyiv'),
      'Minsk': I18n.t('city_minsk'),
      'Vilnius': I18n.t('city_vilnius'),
      'Riga': I18n.t('city_riga'),
      'Tallinn': I18n.t('city_tallinn'),
      'Helsinki': I18n.t('city_helsinki'),
      'Stockholm': I18n.t('city_stockholm'),
      'Oslo': I18n.t('city_oslo'),
      'Copenhagen': I18n.t('city_copenhagen'),
      'Reykjavik': I18n.t('city_reykjavik'),
      'Dublin': I18n.t('city_dublin'),
      'Lisbon': I18n.t('city_lisbon'),
      'Amsterdam': I18n.t('city_amsterdam'),
      'Brussels': I18n.t('city_brussels'),
      'Luxembourg': I18n.t('city_luxembourg'),
      'Bern': I18n.t('city_bern'),
      'Zurich': I18n.t('city_zurich'),

      'Mexico City': I18n.t('city_mexico_city'),
      'Guatemala': I18n.t('city_guatemala'),
      'Havana': I18n.t('city_havana'),
      'Panama': I18n.t('city_panama'),
      'Bogota': I18n.t('city_bogota'),
      'Lima': I18n.t('city_lima'),
      'Santiago': I18n.t('city_santiago'),
      'Buenos Aires': I18n.t('city_buenos_aires'),
      'Montevideo': I18n.t('city_montevideo'),
      'Asuncion': I18n.t('city_asuncion'),
      'Caracas': I18n.t('city_caracas'),
      'Quito': I18n.t('city_quito'),
      'La Paz': I18n.t('city_la_paz'),
      'Sucre': I18n.t('city_sucre'),
      'Sao Paulo': I18n.t('city_sao_paulo'),
      'Rio de Janeiro': I18n.t('city_rio_de_janeiro'),
      'Brasilia': I18n.t('city_brasilia'),
      'Perth': I18n.t('city_perth'),
      'Brisbane': I18n.t('city_brisbane'),
      'Adelaide': I18n.t('city_adelaide'),
      'Hobart': I18n.t('city_hobart'),
      'Darwin': I18n.t('city_darwin'),
      'Suva': I18n.t('city_suva'),
      'Apia': I18n.t('city_apia'),
      "Nuku'alofa": I18n.t('city_nukualofa'),
      'Port Moresby': I18n.t('city_port_moresby'),

    }
    return regionMap[name] ?? name
  }

  private locationDisplayName(name: string): string {
    if (!name || name.length === 0) {
      return '--'
    }
    return this.translateRegion(name)
  }

  private locationColumnTitle(kind: string): string {
    if (kind === 'continent') {
      return I18n.t('h_continent')
    }
    if (kind === 'region') {
      return I18n.t('h_region')
    }
    return I18n.t('h_city')
  }

  private hierarchyItemLabel(kind: string, name: string): string {
    return kind === 'continent' ? this.translateContinent(name) : this.locationDisplayName(name)
  }

  private hierarchySelectionSummary(): string {
    const parts: Array<string> = []
    if (this.hierContinent) {
      parts.push(this.translateContinent(this.hierContinent))
    }
    if (this.hierRegion) {
      parts.push(this.locationDisplayName(this.hierRegion))
    }
    if (this.hierCity) {
      parts.push(this.locationDisplayName(this.hierCity))
    }
    return parts.length > 0 ? parts.join('  >  ') : '未选择'
  }

  private hierRegions(): Array<string> {
    if (this.hierContinent === '' || !LOCATION_HIERARCHY[this.hierContinent]) {
      return []
    }
    return Object.keys(LOCATION_HIERARCHY[this.hierContinent])
  }

  private hierCityList(): Array<HierCity> {
    if (this.hierContinent === '' || this.hierRegion === '' ||
      !LOCATION_HIERARCHY[this.hierContinent] || !LOCATION_HIERARCHY[this.hierContinent][this.hierRegion]) {
      return []
    }
    return LOCATION_HIERARCHY[this.hierContinent][this.hierRegion]
  }

  private hierCityNames(): Array<string> {
    return this.hierCityList().map((c: HierCity) => c.n)
  }

  private selectContinent(c: string): void {
    this.hierContinent = c
    this.hierRegion = ''
    this.hierCity = ''
  }

  private selectRegion(r: string): void {
    this.hierRegion = r
    this.hierCity = ''
  }

  private selectCityByName(name: string): void {
    this.hierCity = name
    const found = this.hierCityList().find((c: HierCity) => c.n === name)
    if (found) {
      // Auto-apply the selected city immediately
      this.setLocation(found.n, found.la, found.lo, found.al)
    }
  }

  @Builder
  locationModeChip(mode: string, label: ResourceStr) {
    Button(label)
      .height(28)
      .fontSize(11)
      .fontColor(this.locationPickMode === mode ? this.nmText() : this.nmSub())
      .backgroundColor(this.locationPickMode === mode ? this.nmAccent() : this.nmBg())
      .border({ width: 1, color: this.locationPickMode === mode ? 'rgba(107, 163, 214, 0.35)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(14)
      .margin({ right: 8 })
      .onClick(() => {
        this.locationPickMode = mode
      })
  }

  @Builder
  hierColumn(kind: string, selected: string, onSelect: (item: string) => void) {
    Column() {
      // Column header with localized title and icon
      Row({ space: 4 }) {
        Text(this.locationColumnTitle(kind))
          .fontSize(11)
          .fontColor('#8EC5E8')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .height(26)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('rgba(91, 147, 191, 0.12)')
      .borderRadius(8)
      .margin({ bottom: 5 })
      Scroll() {
        Column({ space: 4 }) {
          if (kind === 'continent') {
            ForEach(this.hierContinents(), (item: string) => {
              Button(selected === item ? `✓ ${this.hierarchyItemLabel(kind, item)}` : this.hierarchyItemLabel(kind, item), { type: ButtonType.Normal })
                .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .width('100%')
                .fontSize(11)
                .fontColor(selected === item ? '#FFFFFFFF' : '#A8C4E0')
                .fontWeight(selected === item ? FontWeight.Medium : FontWeight.Regular)
                .backgroundColor(selected === item ? '#2A6694' : 'rgba(255,255,255,0.03)')
                .border({ width: selected === item ? 1.5 : 1, color: selected === item ? '#9BD8FF' : 'rgba(107,163,214,0.10)' })
                .borderRadius(8)
                .shadow(selected === item ? { radius: 8, color: 'rgba(99, 185, 255, 0.35)', offsetX: 0, offsetY: 1 } : { radius: 0, color: 'transparent', offsetX: 0, offsetY: 0 })
                .stateEffect(true)
                .animation({ duration: 160, curve: curves.springMotion(0.42, 0.86) })
                .onClick(() => onSelect(item))
            }, (item: string) => item)
          } else if (kind === 'region') {
            ForEach(this.hierRegions(), (item: string) => {
              Button(selected === item ? `✓ ${this.hierarchyItemLabel(kind, item)}` : this.hierarchyItemLabel(kind, item), { type: ButtonType.Normal })
                .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .width('100%')
                .fontSize(11)
                .fontColor(selected === item ? '#FFFFFFFF' : '#A8C4E0')
                .fontWeight(selected === item ? FontWeight.Medium : FontWeight.Regular)
                .backgroundColor(selected === item ? '#2A6694' : 'rgba(255,255,255,0.03)')
                .border({ width: selected === item ? 1.5 : 1, color: selected === item ? '#9BD8FF' : 'rgba(107,163,214,0.10)' })
                .borderRadius(8)
                .shadow(selected === item ? { radius: 8, color: 'rgba(99, 185, 255, 0.35)', offsetX: 0, offsetY: 1 } : { radius: 0, color: 'transparent', offsetX: 0, offsetY: 0 })
                .stateEffect(true)
                .animation({ duration: 160, curve: curves.springMotion(0.42, 0.86) })
                .onClick(() => onSelect(item))
            }, (item: string) => item)
          } else {
            ForEach(this.hierCityNames(), (item: string) => {
              Button(selected === item ? `✓ ${this.hierarchyItemLabel(kind, item)}` : this.hierarchyItemLabel(kind, item), { type: ButtonType.Normal })
                .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .width('100%')
                .fontSize(11)
                .fontColor(selected === item ? '#FFFFFFFF' : '#A8C4E0')
                .fontWeight(selected === item ? FontWeight.Medium : FontWeight.Regular)
                .backgroundColor(selected === item ? '#2A6694' : 'rgba(255,255,255,0.03)')
                .border({ width: selected === item ? 1.5 : 1, color: selected === item ? '#9BD8FF' : 'rgba(107,163,214,0.10)' })
                .borderRadius(8)
                .shadow(selected === item ? { radius: 8, color: 'rgba(99, 185, 255, 0.35)', offsetX: 0, offsetY: 1 } : { radius: 0, color: 'transparent', offsetX: 0, offsetY: 0 })
                .stateEffect(true)
                .animation({ duration: 160, curve: curves.springMotion(0.42, 0.86) })
                .onClick(() => onSelect(item))
            }, (item: string) => item)
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .backgroundColor('rgba(8, 14, 28, 0.4)')
      .borderRadius(10)
      .scrollBarWidth(3)
    }
    .layoutWeight(1)
    .padding(6)
    .backgroundColor('rgba(10, 18, 36, 0.55)')
    .border({ width: 1, color: 'rgba(91, 147, 191, 0.20)' })
    .borderRadius(14)
    .margin({ right: 5 })
  }

  private panelLeft(): number {
    // 跟随面板真实位置（含拖动偏移），避免点面板却漏成星图拖拽。
    // 展开态直接复用渲染用的 expandedMainPanelLeft()，保证命中区与实际绘制位置永远一致
    // （历史上两者各算各的，右侧 EDGE_MARGIN 留边导致命中区整体偏移）。
    if (this.isExpandedLayout) {
      return this.expandedMainPanelLeft()
    }
    return this.skyWidth - this.panelWidth + this.panelOffsetX
  }

  private panelRight(): number {
    return this.panelLeft() + this.panelWidth
  }

  private panelTop(): number {
    return this.EDGE_MARGIN + this.panelOffsetY
  }

  private railTop(): number {
    // Rail always starts near top of screen with a safe edge margin
    return this.EDGE_MARGIN
  }

  private railHeight(): number {
    // 刚好包住最后一个陀螺仪按钮；此前按预留高度绘制，底部多出一大片空背景。
    return this.RAIL_TOP_PAD + this.pinnedActions.length * this.RAIL_ITEM_STEP + this.RAIL_GYRO_OFFSET + 44 + 10
  }

  private expandedZoomX(): number {
    return this.EDGE_MARGIN + 7
  }

  private expandedZoomInY(): number {
    const belowRail = this.railTop() + this.railHeight() + 18
    const bottomLimit = Math.max(this.EDGE_MARGIN + 96, this.skyHeight - 100)
    return Math.min(belowRail, bottomLimit)
  }

  private expandedZoomOutY(): number {
    return this.expandedZoomInY() + this.EXPANDED_ZOOM_SIZE + this.EXPANDED_ZOOM_GAP
  }

  private isExpandedZoomPoint(x: number, y: number): boolean {
    if (!this.isExpandedLayout) { return false }
    const zx = this.expandedZoomX()
    return x >= zx - 4 && x <= zx + this.EXPANDED_ZOOM_SIZE + 4
      && y >= this.expandedZoomInY() - 4 && y <= this.expandedZoomOutY() + this.EXPANDED_ZOOM_SIZE + 4
  }

  private drawerLeft(): number {
    return this.EDGE_MARGIN + (this.isFoldTabletLayout ? 82 : 78)
  }

  private drawerWidth(): number {
    return this.isFoldTabletLayout ? 214 : 206
  }

  // 点击侧栏入口：打开对应面板。来自“更多”抽屉时保持抽屉展开，方便连续切换。
  private lastRailTapTime: number = 0
  private lastRailTapPanel: string = ''
  private onRailTap(panel: string, keepDrawer: boolean = false): void {
    const now = Date.now()
    if (panel === this.lastRailTapPanel && now - this.lastRailTapTime < 400) { return }
    this.lastRailTapTime = now
    this.lastRailTapPanel = panel
    this.setPanel(panel)
    if (this.drawerOpen && !keepDrawer) {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.drawerOpen = false
      })
    }
  }

  private lastDrawerToggleTime: number = 0
  private toggleDrawer(): void {
    const now = Date.now()
    if (now - this.lastDrawerToggleTime < 400) { return }
    this.lastDrawerToggleTime = now
    const opening = !this.drawerOpen
    hilog.info(0x0000, 'StellariumArkUI', 'toggleDrawer next=%{public}s', opening.toString())
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => {
      this.drawerOpen = opening
      // 平板端一次只呈现一种主操作界面，避免抽屉和右侧面板并排抢空间。
      if (opening && this.isExpandedLayout) {
        this.closePanel(true)
      }
    })
    this.scheduleSelectedObjectForUiChange(320)
    this.resetPanelIdle()
    this.resetSidebarAutoCollapse()
  }

  private isUiPoint(x: number, y: number): boolean {
    // 顶部搜索栏：点击区域不穿透到星图
    if (this.isExpandedLayout) {
      const sbX = this.EDGE_MARGIN + 64
      const sbY = this.EDGE_MARGIN
      const sbW = 300
      const sbH = 44
      if (x >= sbX && x <= sbX + sbW && y >= sbY && y <= sbY + sbH) {
        return true
      }
    } else {
      if (this.isFoldHoverLayout && y >= this.hoverConsoleTop() - 8) {
        return true
      }
      if (x >= 16 && x <= 16 + 280 && y >= 50 && y <= 50 + 44) {
        return true
      }
      if (this.isCompactZoomPoint(x, y)) {
        return true
      }
      if (this.isCompactTopQuickPoint(x, y)) {
        return true
      }
      if (this.isCompactMorePoint(x, y)) {
        return true
      }
      if (this.isCompactDrawerPoint(x, y)) {
        return true
      }
    }
    // 左下角滑动详情卡片：标记为 UI 区域，防止 overlay 启动星图拖拽。
    // handleInfoWinTap 只处理头部关闭按钮，Swiper body 区域不拦截，
    // 让 Swiper 自身手势系统处理水平滑动。
    if (this.isExpandedDetailSummaryPoint(x, y)) {
      return true
    }
    if (this.infoWinVisible && this.selectedName.length > 0 && !this.drawerOpen && (!this.panelVisible || !this.useExpandedDetailSummary())) {
      if (this.isPhoneDetailPeek()) {
        const peekX = this.compactObjectPeekX()
        const peekY = this.compactObjectPeekY()
        const peekW = this.compactObjectPeekWidth()
        if (x >= peekX - 8 && x <= peekX + peekW + 8 && y >= peekY - 8 && y <= peekY + 72) {
          return true
        }
      } else if (this.isExpandedLayout) {
        const bcX = this.bottomCardX()
        const bcY = this.bottomCardY()
        const bcW = this.bottomCardWidth()
        const bcH = this.bottomCardHitHeight()
        if (x >= bcX && x <= bcX + bcW && y >= bcY && y <= bcY + bcH) {
          return true
        }
      } else {
        const bcX = this.bottomCardX()
        const bcY = this.bottomCardY()
        const bcW = this.bottomCardWidth()
        const bcH = this.bottomCardHitHeight()
        if (x >= bcX && x <= bcX + bcW && y >= bcY && y <= bcY + bcH) {
          return true
        }
      }
    }
    if (this.isExpandedLayout) {
      // 左侧工具栏：只拦截实际按钮区域（44x44），按钮间空隙穿透到星图
      if (!this.railCollapsed && x >= this.EDGE_MARGIN + 7 && x <= this.EDGE_MARGIN + 51) {
        const rt = this.railTop() + this.RAIL_TOP_PAD
        // 常用入口按钮（每个 44x44，间距由 RAIL_ITEM_STEP 统一控制）
        for (let i = 0; i < this.pinnedActions.length; i++) {
          if (y >= rt + i * this.RAIL_ITEM_STEP && y <= rt + i * this.RAIL_ITEM_STEP + 44) { return true }
        }
        // 更多按钮
        const moreTop = rt + this.pinnedActions.length * this.RAIL_ITEM_STEP + this.RAIL_MORE_OFFSET
        if (y >= moreTop && y <= moreTop + 44) { return true }
        // 音乐按钮
        const musicTop = rt + this.pinnedActions.length * this.RAIL_ITEM_STEP + this.RAIL_MUSIC_OFFSET
        if (y >= musicTop && y <= musicTop + 44) { return true }
        const gyroTop = rt + this.pinnedActions.length * this.RAIL_ITEM_STEP + this.RAIL_GYRO_OFFSET
        if (y >= gyroTop - 8 && y <= gyroTop + 92) { return true }
      } else if (!this.drawerOpen && this.isExpandedZoomPoint(x, y)) {
        return true
      }
      // 低频功能抽屉区域（展开时）
      if (this.drawerOpen && x >= this.drawerLeft() && x <= this.drawerLeft() + this.drawerWidth() && y >= this.railTop() && y <= this.railTop() + 40 + this.drawerActions.length * 46 + 14) {
        return true
      }
      // 浮动面板区域（含 30vp 余量，覆盖圆角/边距，杜绝点面板却拖星图）
      if (this.panelVisible) {
        const pl = this.panelLeft()
        const pr = this.panelRight()
        const pt = this.panelTop()
        if (x >= pl - 30 && x <= pr + 30 && y >= pt - 30 && y <= pt + this.panelMaxHeight + 30) {
          return true
        }
      }
      return false
    }
    if (this.panelVisible) {
      const panelW = this.isFoldHoverLayout ? this.skyWidth * 0.72 : this.skyWidth * 0.94
      const panelX = (this.skyWidth - panelW) / 2
      const panelBottom = this.skyHeight - 90
      const panelY = panelBottom - this.compactPanelHeight()
      if (x >= panelX - 12 && x <= panelX + panelW + 12 && y >= panelY - 18 && y <= panelBottom + 10) {
        return true
      }
    }
    if (!this.drawerOpen && this.isCompactTopQuickPoint(x, y)) {
      return true
    }
    return y >= this.skyHeight - 80
  }

  private handleUiTap(x: number, y: number): boolean {
    // 防闪退保护：确保所有数组和状态变量有效
    try {
	    if (!this.pinnedActions || this.pinnedActions.length === 0) { return false }
	    if (typeof x !== 'number' || typeof y !== 'number' || isNaN(x) || isNaN(y)) { return false }
	    if (this.handleCompactTopQuickTap(x, y)) { return true }
	    if (this.handleCompactZoomTap(x, y)) { return true }
      if (this.handleCompactMoreTap(x, y)) { return true }
	    // 顶部搜索栏已移除，搜索功能通过左侧图标进入分类面板
    // 浮动详情窗优先处理（其区域内已由 isUiPoint 拦截，不会落到星图选星）
      if (this.isExpandedLayout && this.handleExpandedDetailSummaryTap(x, y)) { return true }
      if (!this.drawerOpen && (!this.panelVisible || !this.useExpandedDetailSummary()) && this.handleInfoWinTap(x, y)) { return true }

    // 低频功能抽屉项（展开时）— 必须在缩放按钮之前检查，因为两者区域可能重叠
    if (this.isExpandedLayout && this.drawerOpen && x >= this.drawerLeft() && x <= this.drawerLeft() + this.drawerWidth()) {
      const itemsTop = this.railTop() + 38
      const dIdx = Math.floor((y - itemsTop) / 46)
      if (dIdx >= 0 && dIdx < this.drawerActions.length && this.drawerActions[dIdx]) {
        this.onRailTap(this.drawerActions[dIdx].panel)
        return true
      }
    }

    // zoom +/- buttons (expanded layout, bottom-left) — 抽屉打开时完全跳过
    if (this.isExpandedLayout && !this.drawerOpen && this.isExpandedZoomPoint(x, y)) {
      if (y >= this.expandedZoomInY() - 4 && y <= this.expandedZoomInY() + this.EXPANDED_ZOOM_SIZE + 4) {
        this.zoomStep(0.5)
        return true
      }
      if (y >= this.expandedZoomOutY() - 4 && y <= this.expandedZoomOutY() + this.EXPANDED_ZOOM_SIZE + 4) {
        this.zoomStep(2.0)
        return true
      }
    }
    if (this.isExpandedLayout && x >= this.EDGE_MARGIN + 7 && x <= this.EDGE_MARGIN + 51) {
      const railTop = this.railTop() + this.RAIL_TOP_PAD
      const step = this.RAIL_ITEM_STEP
      // 常用固定入口
      const index = Math.floor((y - railTop) / step)
      const withinButton = index >= 0 && index < this.pinnedActions.length && y >= railTop + index * step && y <= railTop + index * step + 44
      if (withinButton && this.pinnedActions[index]) {
        this.onRailTap(this.pinnedActions[index].panel)
        return true
      }
      // 「更多」抽屉按钮
      const moreTop = railTop + this.pinnedActions.length * step + this.RAIL_MORE_OFFSET
      if (y >= moreTop && y <= moreTop + 44) {
        this.toggleDrawer()
        return true
      }
      // 音乐开关按钮
      const musicTop = railTop + this.pinnedActions.length * step + this.RAIL_MUSIC_OFFSET
      if (y >= musicTop && y <= musicTop + 44) {
        this.toggleMusic()
        return true
      }
      const gyroTop = railTop + this.pinnedActions.length * step + this.RAIL_GYRO_OFFSET
      if (y >= gyroTop - 8 && y <= gyroTop + 92) {
        this.toggleGyroscope(!this.gyroscopeEnabled)
        return true
      }
	    }

		    if (!this.panelVisible) {
		      return false
		    }

    const left = this.panelLeft()
    const top = this.panelTop()
    const right = this.panelRight()
    if (x >= right - 60 && x <= right && y >= top && y <= top + 60) {
      if (!this.uiLocked) {
        this.closePanel(true)
      }
      return true
    }

    if (x < left || x > right || y < top || y > top + 900) {
      return false
    }
    this.resetSidebarAutoCollapse()
    this.resetPanelIdle()

    // Layer toggles are handled by Toggle.onChange in switchRow Builder
    // Hardcoded coordinates removed - layout changed with grouped sections

    if (this.activePanel === 'search') {
      if (y >= 505 && y <= 562) {
        if (x >= 1095 && x < 1165) { this.searchObject('Moon'); return true }
        if (x >= 1165 && x < 1230) { this.searchObject('Mars'); return true }
        if (x >= 1230 && x <= 1345) { this.searchObject('Jupiter'); return true }
      }
    } else if (this.activePanel === 'time') {
      if (y >= 545 && y <= 595) {
        // 循环升档按钮：倒带 | 停止 | 实时 | 减速 | 快进（快进/倒带可连点升档）
        if (x >= 1040 && x < 1110) { this.handleChip('rewind'); return true }
        if (x >= 1110 && x < 1180) { this.handleChip('stop'); return true }
        if (x >= 1180 && x < 1250) { this.handleChip('realtime'); return true }
        if (x >= 1250 && x < 1320) { this.handleChip('slower'); return true }
        if (x >= 1320 && x <= 1400) { this.handleChip('fast'); return true }
      }
      if (y >= 610 && y <= 660) {
        if (x >= 1095 && x < 1220) { this.advanceTime(12); return true }
        if (x >= 1220 && x <= 1345) { this.advanceTime(-12); return true }
      }
    } else if (this.activePanel === 'object') {
      if (y >= 560 && y <= 615) {
        if (x >= 1095 && x < 1160) { this.refreshSelectedObject(); this.refreshState(); return true }
        if (x >= 1160 && x < 1225) { this.moveToSelectedObject(); return true }
        if (x >= 1225 && x <= 1310) { this.callInteractive('setTracking', '0', () => { this.refreshState() }); return true }
      }
      if (!OFFLINE_APPGALLERY_BUILD && y >= 630 && y <= 690) {
        if (x >= 1095 && x < 1175) { this.lx200GotoSelected(); return true }
        if (x >= 1175 && x < 1245) { this.lx200SyncSelected(); return true }
        if (x >= 1245 && x <= 1320) { this.lx200Abort(); return true }
      }
    } else if (this.activePanel === 'place') {
      if (y >= 455 && y <= 505 && x >= 1300 && x <= right) { this.useDeviceLocation(); return true }
    }

    return true
    } catch (e) {
      hilog.error(0x0000, 'StellariumArkUI', 'handleUiTap crash: ' + (e instanceof Error ? e.message : String(e)))
      return false
    }
  }

  private handleOverlayTouch(event: TouchEvent): void {
    try {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) {
      return
    }
    const x = this.touchWindowX(points[0])
    const y = this.touchWindowY(points[0])
    // 任意触摸都算“正在使用”，重置空闲计时（停手 3.5s 后面板果冻淡出、5s 后左侧栏收起）
    this.resetPanelIdle()
    this.resetSidebarAutoCollapse()
    if (event.type === TouchType.Down) {
      this.touchStartedOnUi = this.isUiPoint(x, y)
      if (this.touchStartedOnUi) {
        this.skyTouchFeedback = false
        this.skyTouchActive = false
      }
      hilog.info(0x0000, 'StellariumArkUI', 'overlay touch down ' + Math.round(x).toString() + ',' + Math.round(y).toString() + ' ui=' + (this.touchStartedOnUi ? '1' : '0') + ' sky=' + this.skyWidth.toString() + 'x' + this.skyHeight.toString())
    }
    if (this.touchStartedOnUi) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.handleUiTap(x, y)
        this.touchStartedOnUi = false
      }
      return
    }
    this.handleSkyTouch(event)
    } catch (e) {
      hilog.error(0x0000, 'StellariumArkUI', 'handleOverlayTouch crash: ' + (e instanceof Error ? e.message : String(e)))
    }
  }

  // The floating panel sits above the sky touch surface.  Keep its gestures
  // owned by ArkUI so a Slider/Scroll drag can never become a sky pan.
  private handleFloatingPanelTouch(event: TouchEvent): void {
    this.resetPanelIdle()
    this.resetSidebarAutoCollapse()
    if (event.type === TouchType.Down) {
      this.stopSkyInertia()
      this.skyTouchFeedback = false
    }
  }

  private stopSkyInertia(resetVelocity: boolean = true): void {
    if (this.skyInertiaTimer !== 0) {
      clearInterval(this.skyInertiaTimer)
      this.skyInertiaTimer = 0
    }
    if (this.nativeSkyInertiaActive) {
      this.callNativeFire('stopPanInertia', '')
      this.nativeSkyInertiaActive = false
    }
    if (resetVelocity) {
      this.dragVelocityX = 0
      this.dragVelocityY = 0
    }
  }

  private dragFollowAlpha(dtMs: number): number {
    const base = this.isFoldTabletLayout ? 0.84 : (this.isExpandedLayout ? 0.86 : 0.82)
    return this.clamp(1 - Math.pow(1 - base, Math.max(1, dtMs) / 16.67), 0.60, 0.96)
  }

  private emitFluidDrag(targetX: number, targetY: number, now: number): void {
    const dt = this.dragLastSampleMs > 0 ? Math.max(1, now - this.dragLastSampleMs) : 16
    const rawDx = targetX - this.dragLastRawX
    const rawDy = targetY - this.dragLastRawY
    // Physical Pads have a large, high-density canvas. A small gain keeps the
    // sky responsive without changing the geometry of the native renderer.
    const gain = this.isExpandedLayout ? 1.35 : (this.isFoldHoverLayout ? 1.34 : 1.36)
    if (this.dragLastSampleMs > 0) {
      const vx = rawDx * gain / dt
      const vy = rawDy * gain / dt
      this.dragVelocityX = this.dragVelocityX * 0.35 + vx * 0.65
      this.dragVelocityY = this.dragVelocityY * 0.35 + vy * 0.65
    }
    this.dragLastRawX = targetX
    this.dragLastRawY = targetY
    this.dragLastSampleMs = now

    const alpha = this.dragFollowAlpha(dt)
    const desiredX = this.dragFilteredX + rawDx * gain
    const desiredY = this.dragFilteredY + rawDy * gain
    const nextX = this.dragFilteredX + (desiredX - this.dragFilteredX) * alpha
    const nextY = this.dragFilteredY + (desiredY - this.dragFilteredY) * alpha
    if (Math.abs(nextX - this.dragFilteredX) < 0.25 && Math.abs(nextY - this.dragFilteredY) < 0.25) {
      return
    }
    this.callNativeFire('dragView',
      Math.round(this.dragFilteredX).toString() + '|' +
      Math.round(this.dragFilteredY).toString() + '|' +
      Math.round(nextX).toString() + '|' +
      Math.round(nextY).toString())
    this.dragFilteredX = nextX
    this.dragFilteredY = nextY
    this.touchLastX = nextX
    this.touchLastY = nextY
  }

  private startSkyInertia(): void {
    // Do not discard the velocity sampled from the gesture that just ended.
    this.stopSkyInertia(false)
    const initialSpeed = Math.sqrt(this.dragVelocityX * this.dragVelocityX + this.dragVelocityY * this.dragVelocityY)
    if (initialSpeed < 0.05 || this.pinchActive || this.viewLock) {
      return
    }
    this.nativeSkyInertiaActive = true
    this.callNativeFire('startPanInertia',
      this.dragVelocityX.toFixed(4) + '|' + this.dragVelocityY.toFixed(4))
  }

  private handleSkyTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) {
      return
    }

    if (event.type === TouchType.Down) {
      this.stopSkyInertia()
      const downX = this.touchWindowX(points[0])
      const downY = this.touchWindowY(points[0])
      // Panel header drag detection (before isUiPoint sidebar check)
      if (this.panelVisible) {
        const pl = this.panelLeft()
        const pr = this.panelRight()
        const pt = this.panelTop()
        if (downX >= pl && downX <= pr && downY >= pt && downY <= pt + 48) {
          this.panelDragging = true
          this.panelDragStartX = downX
          this.panelDragStartY = downY
          this.panelDragStartOffsetX = this.panelOffsetX
          this.panelDragStartOffsetY = this.panelOffsetY
          return
        }
      }
      if (this.isUiPoint(downX, downY)) {
        this.touchStartedOnUi = true
        // 抽屉项点击（抽屉展开时）— 优先检查，避免与缩放按钮区域重叠
        if (this.drawerOpen && downX >= this.drawerLeft() && downX <= this.drawerLeft() + this.drawerWidth()) {
          const itemsTop = this.railTop() + 38
          const idx = Math.floor((downY - itemsTop) / 46)
          if (idx >= 0 && idx < this.drawerActions.length && this.drawerActions[idx]) {
            this.onRailTap(this.drawerActions[idx].panel, true)
            return
          }
        }
        if (this.isExpandedLayout && !this.drawerOpen && this.isExpandedZoomPoint(downX, downY)) {
          if (downY <= this.expandedZoomInY() + this.EXPANDED_ZOOM_SIZE + 4) {
            this.zoomStep(0.5)
            this.flashHint(I18n.t('i0076'))
          } else {
            this.zoomStep(2.0)
            this.flashHint(I18n.t('i0077'))
          }
          return
        }
        // Handle sidebar button clicks since XComponent swallows onClick events
        if (downX >= this.EDGE_MARGIN + 7 && downX <= this.EDGE_MARGIN + 51) {
          const railTop = this.railTop() + this.RAIL_TOP_PAD
          const step = this.RAIL_ITEM_STEP
          // 常用固定入口
          for (let i = 0; i < this.pinnedActions.length; i++) {
            const bTop = railTop + i * step
            if (downY >= bTop && downY <= bTop + 44 && this.pinnedActions[i]) {
              this.onRailTap(this.pinnedActions[i].panel)
              return
            }
          }
          // 「更多」抽屉按钮
          const moreTop = railTop + this.pinnedActions.length * step + this.RAIL_MORE_OFFSET
          if (downY >= moreTop && downY <= moreTop + 44) {
            this.toggleDrawer()
            return
          }
          // 音乐开关按钮
          const musicTop = railTop + this.pinnedActions.length * step + this.RAIL_MUSIC_OFFSET
          if (downY >= musicTop && downY <= musicTop + 44) {
            this.toggleMusic()
            return
          }
          const gyroTop = railTop + this.pinnedActions.length * step + this.RAIL_GYRO_OFFSET
          if (downY >= gyroTop - 8 && downY <= gyroTop + 92) {
            this.toggleGyroscope(!this.gyroscopeEnabled)
            return
          }
        }
        // 手机端右上角快捷按钮（陀螺仪/音频）：XComponent 同样吞掉了 onClick，
        // 需要坐标级分派，与上方 tablet rail workaround 同理。
        if (!this.isExpandedLayout && !this.drawerOpen && this.isCompactTopQuickPoint(downX, downY)) {
          const qx = this.compactTopQuickX()
          const qy = this.compactTopQuickY()
          // 陀螺仪按钮（上方的 44x44，圆心约 qx+22, qy+22）
          if (downX >= qx && downX <= qx + 44 && downY >= qy && downY <= qy + 44) {
            hilog.info(0x0000, 'StellariumArkUI', '[DIAG] gyro tap via handleSkyTouch')
            this.resetPanelIdle()
            this.toggleGyroscope(!this.gyroscopeEnabled)
            return
          }
          // 音频按钮（下方的 44x44，间距 10vp，圆心约 qx+22, qy+54+22）
          if (downX >= qx && downX <= qx + 44 && downY >= qy + 54 && downY <= qy + 54 + 44) {
            hilog.info(0x0000, 'StellariumArkUI', '[DIAG] audio tap via handleSkyTouch')
            this.resetPanelIdle()
            this.toggleMusic()
            this.flashHint(this.musicEnabled ? I18n.t('music_on_hint') : I18n.t('music_off_hint'))
            return
          }
        }
        return
      }
      this.skyTouchActive = true
      this.skyDragging = true
      this.pauseDetailRefreshForSkyDrag()
      this.touchStartX = downX
      this.touchStartY = downY
      this.touchLastX = this.touchStartX
      this.touchLastY = this.touchStartY
      this.touchMoved = false
      this.pinchActive = false
      this.nativeDragActive = false
      this.lastDragCommandMs = 0
      this.dragFilteredX = downX
      this.dragFilteredY = downY
      this.dragLastRawX = downX
      this.dragLastRawY = downY
      this.dragLastSampleMs = Date.now()
      this.dragVelocityX = 0
      this.dragVelocityY = 0
      this.dragLogCount = 0
      this.skyTouchFeedback = true
      this.skyTouchX = downX
      this.skyTouchY = downY
      hilog.info(0x0000, 'StellariumArkUI', 'sky touch down at ' + Math.round(this.touchStartX).toString() + ',' + Math.round(this.touchStartY).toString() + ' sky=' + this.skyWidth.toString() + 'x' + this.skyHeight.toString())
      if (points.length >= 2) {
        this.pinchStartDistance = this.distance(
          this.touchWindowX(points[0]), this.touchWindowY(points[0]),
          this.touchWindowX(points[1]), this.touchWindowY(points[1]))
        this.pinchActive = true
        this.callNativeFire('zoomBy', '1|1')
      }
      return
    }

    if (!this.skyTouchActive) {
      return
    }

    if (event.type === TouchType.Move) {
      const x = this.touchWindowX(points[0])
      const y = this.touchWindowY(points[0])
      if (this.skyTouchFeedback) {
        this.skyTouchX = x
        this.skyTouchY = y
      }
      if (points.length >= 2) {
        this.nativeDragActive = false
        this.stopSkyInertia()
        const currentDistance = this.distance(
          x, y, this.touchWindowX(points[1]), this.touchWindowY(points[1]))
        if (!this.pinchActive || this.pinchStartDistance <= 1) {
          this.pinchStartDistance = currentDistance
          this.pinchActive = true
          this.callNativeFire('zoomBy', '1|1')
        } else {
          const scale = currentDistance / this.pinchStartDistance
          this.callNativeFire('zoomBy', scale.toString() + '|0')
          // 缩放时弹小蓝胶囊实时显示 FOV（节流 150ms，避免桥接风暴）
          const nowMs = Date.now()
          if (nowMs - this.lastFovHintMs >= 150) {
            this.lastFovHintMs = nowMs
            this.callInteractive('getFieldOfView', '', (r: StellariumBridgeResponse) => {
              if (r.ok === true && r.fov !== undefined) {
                const fovDeg = r.fov as number
                this.currentFovText = fovDeg.toFixed(1) + '°'
                this.flashHint('视场 ' + fovDeg.toFixed(1) + '°')
              }
            })
          }
        }
        this.touchMoved = true
        return
      }

      // Panel drag handling
      if (this.panelDragging) {
        this.touchStartedOnUi = false
        this.panelOffsetX = this.panelDragStartOffsetX + (x - this.panelDragStartX)
        this.panelOffsetY = this.panelDragStartOffsetY + (y - this.panelDragStartY)
        return
      }

      const totalMove = this.distance(x, y, this.touchStartX, this.touchStartY)
      // 阈值放宽到 16vp:uitest/mock 注入的触摸常有几像素位移,
      // 4vp 会把"轻点"误判成"拖动",导致 selectAt 不触发。
      if (totalMove > 16) {
        // Manual panning and sensor tracking must never drive the native
        // camera together. Leave gyro mode on the first real sky drag, while
        // keeping taps and pinch zoom available without changing its state.
        if (!this.touchMoved && this.gyroscopeEnabled) {
          this.stopGyroscope(true)
          this.flashHint('已退出陀螺仪')
        }
        this.touchMoved = true
      }
      if (this.touchMoved) {
        this.nativeDragActive = true
        const now = Date.now()
        if (now - this.lastDragCommandMs >= 16) {
          if (this.dragLogCount < 5) {
            hilog.info(0x0000, 'StellariumArkUI', 'dragView dx=' + Math.round(x - this.touchLastX).toString() + ' dy=' + Math.round(y - this.touchLastY).toString() + ' throttle=' + (now - this.lastDragCommandMs).toString() + 'ms')
            this.dragLogCount += 1
          }
          this.emitFluidDrag(x, y, now)
          this.lastDragCommandMs = now
        }
      }
      return
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      const x = this.touchWindowX(points[0])
      const y = this.touchWindowY(points[0])
      const endedOnUi = this.isUiPoint(x, y)
      // End panel drag
      if (this.panelDragging) {
        this.panelDragging = false
        this.scheduleSelectedObjectForUiChange(160)
        return
      }
      // Gesture ownership is decided on Down. A drag that started on the sky
      // must still finish as a sky gesture even when the finger crosses the
      // floating object card before it lifts; otherwise the early return leaves
      // skyDragging set and permanently pauses detail refresh/inertia.
      if (this.touchStartedOnUi) {
        this.touchStartedOnUi = false
        return
      }
      if (this.nativeDragActive) {
        this.emitFluidDrag(x, y, Date.now())
        this.startSkyInertia()
      } else if (!this.touchMoved && !this.pinchActive && !endedOnUi && Date.now() - this.lastInfoWinCloseMs > 320) {
        const payload = Math.round(this.touchStartX).toString() + '|' + Math.round(this.touchStartY).toString() + '|' + Math.round(this.skyWidth).toString() + '|' + Math.round(this.skyHeight).toString()
        hilog.info(0x0000, 'StellariumArkUI', 'selectAt payload: ' + payload)
        this.callInteractive('selectAt', payload, (result) => {
          hilog.info(0x0000, 'StellariumArkUI', 'selectAt result: ' + JSON.stringify(result))
          this.applySelectedObject(result)
          if (result.found === true) {
            this.flashHint(I18n.t('i0074').replace('%s', this.zhNameOf(this.selectedName)))
          } else {
            this.flashHint(I18n.t('i0075'))
          }
        })
      }
      this.pinchActive = false
      this.nativeDragActive = false
      this.skyTouchActive = false
      this.skyTouchFeedback = false
      this.skyDragging = false
      this.resumeDetailRefreshAfterSkyDrag()
    }
  }

  build() {
    Stack() {
      // Language refresh anchor: reading i18nLang creates a reactive
      // dependency on AppStorage('i18nLang'). When language changes,
      // ArkUI re-executes build() and all I18n.t() calls re-evaluate.
      // Using a real (but invisible) element ensures the dependency is tracked.
      Text(this.i18nLang)
        .fontSize(0.1)
        .opacity(0)
        .width(0)
        .height(0)
        .zIndex(-1)
      XComponent({
        type: XComponentType.SURFACE,
        id: 'stellarium_entry_gl_probe',
        libraryname: 'entry'
      })
        .width('100%')
        .height('100%')
        .zIndex(0)
        .hitTestBehavior(HitTestMode.None)

      if (this.createInfo !== undefined && this.privacyNativeStartupAllowed) {
        XComponent({
          type: XComponentType.NODE,
          id: this.createInfo.xComponentId,
          libraryname: 'qohos'
        })
          .onAttach(this.createInfo.onAttach)
          .onAppear(this.createInfo.onAppear)
          .onDisAppear(this.createInfo.onDisAppear)
          .width('100%')
          .height('100%')
          .zIndex(-1)
          .opacity(0.01)
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.None)
          .enabled(false)
      }

      if (this.skyTouchFeedback) {
        Row()
          .width(120)
          .height(120)
          .borderRadius(60)
          .backgroundColor(this.nightMode ? 'rgba(180, 40, 20, 0.15)' : 'rgba(107, 163, 214, 0.12)')
          .border({ width: 1, color: 'rgba(107, 163, 214, 0.10)' })
          .shadow({ radius: 42, color: 'rgba(107, 163, 214, 0.18)', offsetX: 0, offsetY: 0 })
          .align(Alignment.Center)
          .offset({ x: this.skyTouchX - this.skyWidth / 2, y: this.skyTouchY - this.skyHeight / 2 })
          .hitTestBehavior(HitTestMode.None)
          .zIndex(0)
          .animation({ duration: 0, curve: Curve.Linear })
      }

        // 画布触摸层：与 toolbar/panel 平级（都是 1234 根 Stack 的子），
      // 承接 selectAt/onTouch。关键：不能挂在 1352 全屏 UI 父上，
      // 否则会抑制其子组件（toolbar/面板按钮）的 onClick。
      // 参考已验证的 compactShell：onTouch 挂在独立 Blank 上而非全屏 UI 父。
      Stack() { }
        .width('100%')
        .height('100%')
        // 星图触摸由各布局内部的专属触摸面处理，禁止全屏层穿透 UI。
        .hitTestBehavior(HitTestMode.None)
        .onTouch((event: TouchEvent) => {
          this.handleOverlayTouch(event)
        })

      this.harmonyShell()

      // 启动动画：星空淡入 + 核心就绪后整体淡出（不阻挡首帧交互太久）
      if (!this.splashGone) {
        Stack() {
          // 星空背景：亮星/暗星交错闪烁
          ForEach(this.splashStars, (s: StarDot) => {
            Circle({ width: s.r, height: s.r })
              .fill("#FFFFFFFF")
              .opacity(s.bright ? (this.twPhase ? 0.95 : 0.45) : (this.twPhase ? 0.4 : 0.18))
              .position({ x: s.xPct + '%', y: s.yPct + '%' })
              .animation({ duration: 1000, curve: Curve.EaseInOut })
          }, (s: StarDot, idx: number) => 'star' + idx)
          // 中央内容：标题 + 副标题 + 加载指示
          Column() {
            Text("Stellarium")
              .fontSize(34).fontWeight(FontWeight.Bold).fontColor("#E5FFFFFF").letterSpacing(2)
              .opacity(this.splashIn ? 1 : 0)
              .translate({ y: this.splashIn ? 0 : 16 })
              .animation({ duration: 600, curve: Curve.EaseOut })
              .margin({ bottom: 10 })
            LoadingProgress()
              .width(38).height(38)
              .color("#5B93BF")
              .opacity(this.splashIn ? 1 : 0)
              .animation({ duration: 600, curve: Curve.EaseOut, delay: 300 })
            Text("正在唤醒星空…")
              .fontSize(12).fontColor("#99FFFFFF")
              .margin({ top: 14 })
              .opacity(this.splashIn ? 1 : 0)
              .animation({ duration: 600, curve: Curve.EaseOut, delay: 400 })
          }
          .align(Alignment.Center)
        }
        .width("100%").height("100%")
        .backgroundColor("#05070F")
        .opacity(this.splashOpacity)
        .zIndex(100)

        .onAppear(() => {
          this.startTwinkle()
          this.getUIContext().animateTo({ duration: 700, curve: Curve.EaseOut }, () => {
            this.splashIn = true
            this.splashOpacity = 1
          })
        })
      }
      // Native night mode colors the Qt sky. These permanent, input-transparent
      // layers extend the same low-luminance red treatment to the ArkUI tree.
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor('#A00000')
        .blendMode(BlendMode.COLOR, BlendApplyType.OFFSCREEN)
        .opacity(this.nightMode ? 0.78 : 0)
        .animation({ duration: 450, curve: Curve.EaseInOut })
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(98)
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(this.nightMode ? 0.48 : 0)
        .animation({ duration: 450, curve: Curve.EaseInOut })
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(99)
    }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        // 布局硬回调：稳定触发。冷启动期 ArkUI setTimeout 重试不可靠，
        // 这里借 onAreaChange 反复尝试把启动命令送到 Qt 线程。
        this.startupBridgeSync()
        this.skyWidth = Number(newArea.width) > 1 ? Number(newArea.width) : 1
        this.skyHeight = Number(newArea.height) > 1 ? Number(newArea.height) : 1
        this.refreshFoldState('onAreaChange')
        this.updateResponsiveLayout('onAreaChange')
        if (this.isFoldTabletLayout) {
          this.panelWidth = Math.min(Math.max(this.skyWidth * 0.42, 300), 340)
          this.panelMaxHeight = Math.min(this.skyHeight * 0.70, 560)
        } else if (this.isExpandedLayout) {
          // 平板/大屏：详情面板占屏宽 6/10 的右半区，并与屏幕右缘保留 EDGE_MARGIN 距离；
          // 高度拉长到 88%，上下同样留边，视觉上更像一块完整的侧栏。
          this.panelWidth = Math.min(Math.max(this.skyWidth * 0.60 - this.EDGE_MARGIN, 320), 720)
          this.panelMaxHeight = Math.max(this.skyHeight - this.EDGE_MARGIN * 2, 320)
        } else {
          this.panelWidth = Math.min(Math.max(this.skyWidth * 0.28, 280), 400)
          this.panelMaxHeight = Math.min(this.skyHeight * 0.78, 700)
        }
      })
  }
  @Builder
  harmonyShell() {
      Stack() {
        if (this.isFoldHoverLayout) {
          Stack() { this.hoverObservatoryShell() }
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
              .combine(TransitionEffect.scale({ x: 0.985, y: 0.985 }).animation({ duration: 220, curve: curves.springMotion(0.55, 0.88) })))
        } else if (this.isExpandedLayout) {
          Stack() { this.expandedShell() }
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
              .combine(TransitionEffect.scale({ x: 1.015, y: 1.015 }).animation({ duration: 220, curve: curves.springMotion(0.55, 0.88) })))
      } else {
          Stack() { this.compactShell() }
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
              .combine(TransitionEffect.scale({ x: 0.985, y: 0.985 }).animation({ duration: 220, curve: curves.springMotion(0.55, 0.88) })))
      }

      // Gyroscope target guide: it is deliberately visual-only, so it never
      // steals a pan, pinch, or button press from the sky and chrome layers.
      if (this.gyroGuideVisible) {
        Stack() { this.gyroTargetGuide() }
          .position({ x: this.gyroGuideX, y: this.gyroGuideY })
          .width(44)
          .height(44)
          .zIndex(4)
          .hitTestBehavior(HitTestMode.None)
          .animation({ duration: 130, curve: Curve.Linear })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      // 点击反馈提示：置顶显示、不拦截触摸
      if (this.actionHint !== '') {
        Row() {
          Text(this.actionHint)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .padding({ left: 16, right: 16, top: 9, bottom: 9 })
            .backgroundColor('rgba(91, 147, 191, 0.92)')
            .borderRadius(18)
            .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: 8 })
        }
          .hitTestBehavior(HitTestMode.None)
          .position({ x: 0, y: (this.isExpandedLayout || this.isFoldHoverLayout) ? 16 : 58 })
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .zIndex(20)
          // 提示气泡：下滑淡入、上浮淡出
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: 0, y: -12 }).animation({ duration: 220, curve: Curve.Friction })),
            TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseIn })
              .combine(TransitionEffect.translate({ x: 0, y: -8 }).animation({ duration: 220, curve: Curve.EaseIn }))
          ))
      }
      }
      .width('100%')
      .height('100%')
      .zIndex(3)
      .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  gyroTargetGuide() {
    Stack() {
      Text('↑')
        .fontSize(29)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E5FAFF')
        .rotate({ angle: this.gyroGuideAngle + 90 })
        .animation({ duration: 130, curve: Curve.Linear })
    }
      .width(44)
      .height(44)
      .alignContent(Alignment.Center)
      .backgroundColor('rgba(8, 21, 36, 0.76)')
      .backdropBlur(22)
      .border({ width: 1, color: 'rgba(169, 232, 255, 0.72)' })
      .borderRadius(22)
      .clip(true)
      .shadow({ radius: 14, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: 4 })
  }

  @Builder
  expandedShell() {
    Stack() {
      Stack() { }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => {
          this.handleSkyTouch(event)
        })
      // 左上角 Stellarium 常驻标已移除，避免遮挡星图
      if (this.expandedUiAllowed()) {
        Stack() { this.railShell() }
          .position({ x: this.EDGE_MARGIN, y: this.railTop() })
          .hitTestBehavior(HitTestMode.Default)
      }
      // 低频功能抽屉：贴着侧栏右侧滑出
      if (this.expandedUiAllowed() && this.drawerOpen) {
        Stack() { this.actionDrawer() }
          .position({ x: this.drawerLeft(), y: this.railTop() })
          .width(this.drawerWidth())
          .height(this.drawerActions.length * 46 + 58)
          .hitTestBehavior(HitTestMode.Default)
          .zIndex(6)
      }
      if (this.expandedUiAllowed() && !this.drawerOpen) {
        Button({ type: ButtonType.Normal }) { this.expandedZoomButton('zoom_in') }
          .width(this.EXPANDED_ZOOM_SIZE)
          .height(this.EXPANDED_ZOOM_SIZE)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .borderRadius(this.EXPANDED_ZOOM_SIZE / 2)
          .hitTestBehavior(HitTestMode.Block)
          .position({ x: this.expandedZoomX(), y: this.expandedZoomInY() })
          .onClick(() => {
            this.zoomStep(0.5)
            this.flashHint(I18n.t('i0076'))
          })
      }
      if (this.expandedUiAllowed() && !this.drawerOpen) {
        Button({ type: ButtonType.Normal }) { this.expandedZoomButton('zoom_out') }
          .width(this.EXPANDED_ZOOM_SIZE)
          .height(this.EXPANDED_ZOOM_SIZE)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .borderRadius(this.EXPANDED_ZOOM_SIZE / 2)
          .hitTestBehavior(HitTestMode.Block)
          .position({ x: this.expandedZoomX(), y: this.expandedZoomOutY() })
          .onClick(() => {
            this.zoomStep(2.0)
            this.flashHint(I18n.t('i0077'))
          })
      }
      if (this.panelVisible) {
        Stack({ alignContent: Alignment.TopStart }) { this.floatingPanel() }
          .width(this.panelWidth)
          .height(this.panelMaxHeight)
          .position({ x: this.skyWidth - this.panelWidth - this.EDGE_MARGIN + this.panelOffsetX, y: this.EDGE_MARGIN + this.panelOffsetY })
          // Default keeps the panel above the sibling sky surface while still
          // letting its deepest child (Button, Slider, Scroll, TextInput) own
          // the gesture. Block would stop those controls at this outer shell.
          .hitTestBehavior(HitTestMode.Default)
          .onTouch((event: TouchEvent) => {
            this.handleFloatingPanelTouch(event)
          })
          // 面板滑入滑出动画：从右侧滑入 + 淡入（一镜到底的连续弹簧滑动）
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: 64, y: 0 }).animation({ duration: 460, curve: curves.springMotion(0.55, 0.85) })),
            TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
              .combine(TransitionEffect.translate({ x: 40, y: 0 }).animation({ duration: 200, curve: Curve.EaseIn }))
          ))
      }
      // 陀螺仪校准面板（开启陀螺仪时显示在侧栏右侧）
      if (this.gyroscopeEnabled && this.gyroCalibPanelOpen) {
        Stack() { this.gyroCalibPanel() }
          .position({ x: this.EDGE_MARGIN + 64, y: this.railTop() + 120 })
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(60)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: -20, y: 0 }).animation({ duration: 300, curve: curves.springMotion(0.5, 0.85) })),
            TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
          ))
      }
      // 大屏详情优先与右侧主面板并排；空间不足时保留不遮挡的目标摘要，而不是关闭。
      if (this.infoWinVisible && this.selectedName.length > 0 && !this.drawerOpen) {
        if (this.useExpandedDetailSummary()) {
          if (this.canShowExpandedDetailSummary()) {
            Stack() { this.expandedObjectSummary() }
              .position({ x: this.expandedDetailSummaryX(), y: this.expandedDetailSummaryY() })
              .width(this.expandedDetailSummaryWidth())
              .height(this.expandedDetailSummaryHeight())
              .zIndex(50)
              .hitTestBehavior(HitTestMode.Default)
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ x: -20, y: 0 }).animation({ duration: 440, curve: curves.springMotion(0.52, 0.86) })),
                TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
                  .combine(TransitionEffect.translate({ x: -12, y: 0 }).animation({ duration: 180, curve: Curve.EaseIn }))
              ))
          } else {
            // 极窄空间（<140vp）：隐藏摘要，避免与搜索面板重叠
          }
        } else {
          Stack() { this.bottomDetailCard() }
            .position({ x: this.bottomCardX(), y: this.bottomCardY() })
            .zIndex(50)
            .hitTestBehavior(HitTestMode.Default)
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseOut })
                .combine(TransitionEffect.translate({ x: 0, y: 40 }).animation({ duration: 420, curve: curves.springMotion(0.55, 0.85) })),
              TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
                .combine(TransitionEffect.translate({ x: 0, y: 20 }).animation({ duration: 200, curve: Curve.EaseIn }))
            ))
        }
      }
    }
      .width('100%')
      .height('100%')
      .zIndex(1)
      .hitTestBehavior(HitTestMode.Transparent)
    }

  @Builder
  hoverObservatoryShell() {
    Stack() {
      Stack()
        .width('100%')
        .height(this.hoverSkyPaneHeight())
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => {
          this.handleSkyTouch(event)
        })

      Row() {
        Text(this.observationTimeText)
          .fontSize(11)
          .fontColor('rgba(229,255,255,0.78)')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.currentFovText)
          .fontSize(11)
          .fontColor('rgba(229,255,255,0.78)')
          .margin({ left: 10 })
      }
        .height(34)
        .padding({ left: 16, right: 16 })
        .backgroundColor('rgba(10, 14, 26, 0.42)')
        .backdropBlur(22)
        .borderRadius(17)
        .position({ x: 16, y: 12 })
        .width(Math.max(220, this.skyWidth - 32))
        .hitTestBehavior(HitTestMode.None)

      Row()
        .width(Math.max(120, this.skyWidth - 72))
        .height(2)
        .backgroundColor('rgba(147, 215, 255, 0.20)')
        .borderRadius(1)
        .position({ x: 36, y: this.hoverSkyPaneHeight() + 1 })
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width(Math.max(240, this.skyWidth - 24))
        .height(Math.max(220, this.skyHeight - this.hoverConsoleTop() - 14))
        .backgroundColor(this.panelIdleGlass ? 'rgba(10, 14, 26, 0.46)' : 'rgba(14, 18, 32, 0.66)')
        .backdropBlur(this.panelIdleGlass ? 42 : 30)
        .border({ width: 0.5, color: 'rgba(147, 215, 255, 0.12)' })
        .borderRadius(28)
        .position({ x: 12, y: this.hoverConsoleTop() })
        .hitTestBehavior(HitTestMode.None)

      if (!this.drawerOpen && !(this.infoWinVisible && this.selectedName.length > 0 && !this.panelVisible)) {
        Stack() { this.compactZoomControls() }
          .position({ x: 22, y: this.hoverConsoleTop() + 22 })
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(20)
      }

      if (this.drawerOpen) {
        Stack() { this.compactMoreDrawer() }
          .position({ x: 0, y: this.hoverPanelTop() })
          .width('100%')
          .hitTestBehavior(HitTestMode.Default)
          .zIndex(30)
      } else if (this.panelVisible) {
        Stack() { this.compactPanel() }
          .position({ x: 0, y: this.hoverPanelTop() })
          .width('100%')
          .hitTestBehavior(HitTestMode.Default)
          .zIndex(30)
      }

      Row() { this.bottomDock() }
        .width('100%')
        .height(72)
        .justifyContent(FlexAlign.Center)
        .position({ x: 0, y: this.skyHeight - 82 })
        .hitTestBehavior(HitTestMode.Block)
        .zIndex(40)

      if (!this.panelVisible && !this.drawerOpen && this.infoWinVisible && this.selectedName.length > 0) {
        Stack() { this.bottomDetailCard() }
          .position({ x: this.bottomCardX(), y: Math.max(this.hoverConsoleTop() + 20, this.skyHeight - this.bottomCardHeight() - 92) })
          .zIndex(35)
          .hitTestBehavior(HitTestMode.Default)
      }
    }
      .width('100%')
      .height('100%')
      .zIndex(1)
      .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  compactShell() {
    Stack() {
      Column() {
        Blank()
          .width('100%')
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => {
            this.handleSkyTouch(event)
          })

        if (this.drawerOpen) {
          this.compactMoreDrawer()
        } else if (this.panelVisible) {
          this.compactPanel()
        }

        this.bottomDock()
      }
        .width('100%')
        .height('100%')
        .padding({ bottom: 14 })
        .zIndex(1)

      // 手机端右上角常驻快捷区：陀螺仪 + 音频（与平板左侧栏入口一致）
      if (!this.drawerOpen) {
        Stack() { this.compactTopQuickControls() }
          .position({ x: this.compactTopQuickX(), y: this.compactTopQuickY() })
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(30)
        // Keep a dedicated touch target above the Qt XComponent.  The native
        // surface otherwise intermittently captures the compact quick buttons.
        Stack() { }
          .width(44)
          .height(98)
          .position({ x: this.compactTopQuickX(), y: this.compactTopQuickY() })
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(31)
          .onTouch((event: TouchEvent) => {
            this.handleCompactTopQuickTouch(event)
          })
      }
      // 陀螺仪校准面板（紧凑布局）
      if (this.gyroscopeEnabled && this.gyroCalibPanelOpen) {
        Stack() { this.gyroCalibPanel() }
          .position({ x: 16, y: 80 })
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(60)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: -20, y: 0 }).animation({ duration: 300, curve: curves.springMotion(0.5, 0.85) })),
            TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
          ))
      }
      // 手机先显示紧凑的选中提示条；用户主动点开后才显示完整检查器。
      // 必须作为 Stack 的独立子层，Column 内的 position 会参与普通排版，导致卡片贴边。
      if (!this.panelVisible && this.infoWinVisible && this.selectedName.length > 0) {
        if (this.isPhoneDetailPeek()) {
          Stack() { this.compactObjectPeek() }
            .position({ x: this.compactObjectPeekX(), y: this.compactObjectPeekY() })
            .width(this.compactObjectPeekWidth())
            .zIndex(50)
            .hitTestBehavior(HitTestMode.Default)
        } else {
          Stack() { this.bottomDetailCard() }
            .position({ x: this.bottomCardX(), y: this.bottomCardY() })
            .zIndex(50)
            .hitTestBehavior(HitTestMode.Default)
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseOut })
                .combine(TransitionEffect.translate({ x: 0, y: 40 }).animation({ duration: 420, curve: curves.springMotion(0.55, 0.85) })),
              TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
                .combine(TransitionEffect.translate({ x: 0, y: 20 }).animation({ duration: 200, curve: Curve.EaseIn }))
            ))
        }
      }
    }
      .width('100%')
      .height('100%')
      .zIndex(1)
      .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  compactObjectPeek() {
    Row({ space: 8 }) {
      Image(this.getIcon('info', false)).width(18).height(18).fillColor('#73C8FF')
      Column() {
        Text(this.zhNameOf(this.selectedName)).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#F1FAFF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.selectedCoordAlt.length > 0 ? this.selectedCoordAlt : this.zhType(this.selectedType)).fontSize(10).fontColor('#9BCBE5').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 2 })
      }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button('详情')
        .height(32).fontSize(11).fontColor('#E8F8FF').backgroundColor('rgba(91,147,191,0.42)').borderRadius(10)
        .onClick(() => {
          this.resetPanelIdle()
          this.infoWinExpanded = true
        })
      Text('✕').fontSize(14).fontColor('#B8CAD7').padding({ left: 4, top: 8, bottom: 8 })
        .onClick(() => {
          this.resetPanelIdle()
          this.dismissObjectInspector()
        })
    }
      .width('100%').height(64).padding({ left: 13, right: 12 })
      .backgroundColor(this.phoneChromeIsGlass() ? 'rgba(10,14,26,0.48)' : 'rgba(12,16,28,0.84)').backdropBlur(this.phoneChromeIsGlass() ? 44 : 36)
      .border({ width: 0.5, color: this.phoneChromeIsGlass() ? 'rgba(147,215,255,0.11)' : 'rgba(147,215,255,0.16)' }).borderRadius(14)
      .shadow({ radius: 18, color: 'rgba(0,0,0,0.28)', offsetX: 0, offsetY: 8 })
      .opacity(this.phoneChromeOpacity())
      .scale({ x: this.phoneChromeOpacity() < 1 ? 0.98 : 1.0, y: this.phoneChromeOpacity() < 1 ? 0.98 : 1.0 })
      .animation({ duration: 420, curve: Curve.Friction })
  }

  @Builder
  compactZoomControls() {
    Column({ space: 10 }) {
      this.compactZoomControl('zoom_in', 0.5, 'i0076')
      this.compactZoomControl('zoom_out', 2.0, 'i0077')
    }
      .width(60)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Block)
  }

  @Builder
  compactZoomControl(icon: string, factor: number, hintKey: string) {
    Button({ type: ButtonType.Normal }) {
      this.zoomButton(icon)
    }
      .width(56)
      .height(56)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(28)
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
        this.resetPanelIdle()
        this.zoomStep(factor)
        this.flashHint(I18n.t(hintKey))
      })
  }

  @Builder
  compactQuickControls() {
    Column({ space: 8 }) {
      Stack() { this.moreButton() }
    }
      .width(54)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Block)
  }

  /**
   * 手机端右上角常驻快捷区：陀螺仪 + 音频控制。
   * 这两项是观星高频功能，此前被收进「更多」抽屉，需要两次点击才能用；
   * 现提到顶部与平板端左侧栏的入口保持一致（同图标、同激活配色）。
   */
  @Builder
  compactTopQuickControls() {
    Column({ space: 10 }) {
      this.compactQuickButton('gyro', this.gyroscopeEnabled, () => {
        hilog.info(0x0000, 'StellariumArkUI', '[DIAG] gyro button CLICKED gyroscopeEnabled=%{public}s', this.gyroscopeEnabled.toString())
        this.resetPanelIdle()
        this.toggleGyroscope(!this.gyroscopeEnabled)
      }, false, this.compactQuickPressed === 'gyro')
      this.compactQuickButton('audio', this.musicEnabled, () => {
        hilog.info(0x0000, 'StellariumArkUI', '[DIAG] audio button CLICKED musicEnabled=%{public}s', this.musicEnabled.toString())
        this.resetPanelIdle()
        this.toggleMusic()
        this.flashHint(this.musicEnabled ? I18n.t('music_on_hint') : I18n.t('music_off_hint'))
      }, false, this.compactQuickPressed === 'audio')
    }
      .width(44)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Block)
      .opacity(this.phoneChromeOpacity())
      .animation({ duration: 420, curve: Curve.EaseOut })
  }

  /** 手机端右上快捷区左上角坐标（与顶部搜索栏同高，靠右缘） */
  private compactTopQuickX(): number {
    return this.skyWidth - 18 - 44
  }

  private compactTopQuickY(): number {
    return 50
  }

  private isCompactTopQuickPoint(x: number, y: number): boolean {
    if (this.isExpandedLayout) { return false }
    const qx = this.compactTopQuickX()
    const qy = this.compactTopQuickY()
    return x >= qx - 8 && x <= qx + 52 && y >= qy - 8 && y <= qy + 108
  }

  private compactQuickIdAt(x: number, y: number): string {
    if (this.isExpandedLayout || this.drawerOpen) { return '' }
    const qx = this.compactTopQuickX()
    const qy = this.compactTopQuickY()
    if (x < qx || x > qx + 44) { return '' }
    if (y >= qy && y <= qy + 44) { return 'gyro' }
    if (y >= qy + 54 && y <= qy + 98) { return 'audio' }
    return ''
  }

  // The native sky XComponent can consume ArkUI Button.onClick on phones.
  // Route these two high-frequency controls through the same coordinate path
  // as the tablet rail so their visual and touch regions always agree.
  private handleCompactTopQuickTap(x: number, y: number): boolean {
    if (this.isExpandedLayout || this.drawerOpen || !this.isCompactTopQuickPoint(x, y)) {
      return false
    }
    const quickId = this.compactQuickIdAt(x, y)
    if (quickId === 'gyro') {
      this.resetPanelIdle()
      this.toggleGyroscope(!this.gyroscopeEnabled)
      this.flashHint(this.gyroscopeEnabled ? '陀螺仪已开启，正在校准' : '陀螺仪已关闭')
      return true
    }
    if (quickId === 'audio') {
      this.resetPanelIdle()
      this.toggleMusic()
      this.flashHint(this.musicEnabled ? I18n.t('music_on_hint') : I18n.t('music_off_hint'))
      return true
    }
    return false
  }

  private handleCompactTopQuickTouch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) {
      this.compactQuickPressed = ''
      return
    }
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) { return }
    const windowX = points[0].windowX
    const windowY = points[0].windowY
    const x = typeof windowX === 'number' ? windowX : this.compactTopQuickX() + (points[0].x ?? 0)
    const y = typeof windowY === 'number' ? windowY : this.compactTopQuickY() + (points[0].y ?? 0)
    if (event.type === TouchType.Down) {
      this.stopSkyInertia()
      this.skyTouchFeedback = false
      this.compactQuickPressed = this.compactQuickIdAt(x, y)
      return
    }
    if (event.type === TouchType.Up) {
      this.compactQuickPressed = ''
      this.handleCompactTopQuickTap(x, y)
    }
  }

  @Builder
  compactQuickButton(icon: string, active: boolean, action: () => void, receiveTap: boolean = true, pressed: boolean = false) {
    Row() {
      Image(this.getIcon(icon, active))
        .width(22)
        .height(22)
        .fillColor(active ? '#FFFFFF' : this.nmText())
    }
      .width(this.EXPANDED_ZOOM_SIZE)
      .height(this.EXPANDED_ZOOM_SIZE)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(pressed ? 'rgba(169, 232, 255, 0.24)' : (active ? 'rgba(91, 147, 191, 0.60)' : 'rgba(18, 22, 36, 0.50)'))
      .backdropBlur(active ? 28 : 36)
      .border({ width: 1, color: active ? 'rgba(107, 163, 214, 0.42)' : 'rgba(255, 255, 255, 0.10)' })
      .borderRadius(this.EXPANDED_ZOOM_SIZE / 2)
      .shadow({ radius: 18, color: 'rgba(0,0,0,0.30)', offsetX: 0, offsetY: 8 })
      .scale({ x: pressed ? 0.90 : (active ? 1.05 : 1.0), y: pressed ? 0.90 : (active ? 1.05 : 1.0) })
      .animation({ duration: pressed ? 70 : 180, curve: Curve.EaseOut })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        // The compact top controls have a separate touch target over Qt.
        // Handling the same tap twice immediately flips their state back.
        if (receiveTap) { action() }
      })
  }

  // ---- 选中天体的独立浮动详情窗口 ----
  // 默认收起（仅一行概要），点头部展开为可滚动的富详情卡（约半屏）。
  // 它独立于右侧菜单面板（activePanel），选中天体时不再强制切换菜单，
  // 因此不会打扰用户正在进行的操作。
  private infoWinLeft(): number {
    const availLeft = this.EDGE_MARGIN + 64
    const availRight = this.skyWidth - this.panelWidth - this.EDGE_MARGIN
    const band = availRight - availLeft
    const w = Math.min(band, 560)
    return availLeft + (band - w) / 2
  }
  private infoWinWidth(): number {
    const availLeft = this.EDGE_MARGIN + 64
    const availRight = this.skyWidth - this.panelWidth - this.EDGE_MARGIN
    const band = availRight - availLeft
    return Math.min(band, 560)
  }
  private infoWinDetailH(): number {
    return Math.min(this.skyHeight * 0.42, 400)
  }
  private toggleTracking(): void {
    if (this.gyroscopeEnabled) {
      this.updateGyroTargetGuide(true)
      return
    }
    const want = this.trackingText !== 'On'
    this.callInteractive('setTracking', want ? '1' : '0', () => {
      this.trackingText = want ? 'On' : 'Off'
      this.refreshState()
    })
  }


  // ── 顶部搜索栏（中等宽度，点击打开搜索面板） ──
  @Builder
  centerSearchBar() {
    Row({ space: 8 }) {
      Image(this.getIcon('search', false))
        .width(18).height(18).fillColor('#7FB3DC')
      TextInput({ text: this.searchText, placeholder: I18n.t('i0063') })
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .placeholderColor('#8099BBCC')
        .placeholderFont({ size: 14 })
        .layoutWeight(1)
        .maxLines(1)
        .caretStyle({ color: '#5B93BF' })
        .borderColor(Color.Transparent)
        .backgroundColor(Color.Transparent)
        .onChange((value: string) => {
          this.searchText = value
          this.fetchSuggestions(value.trim())
        })
        .onFocus(() => {
          // Keep result candidates above the software keyboard on phones.
          // The user can still drag the sheet back to the 6/10 snap point.
          if (!this.isExpandedLayout && !this.isFoldHoverLayout && this.compactPanelSnapRatio < 0.9) {
            this.getUIContext().animateTo({ duration: 260, curve: curves.springMotion(0.48, 0.90) }, () => {
              this.compactPanelSnapRatio = 0.9
              this.compactPanelDragOffsetY = 0
            })
            this.scheduleSelectedObjectForUiChange(300)
          }
        })
        .onSubmit(() => {
          if (this.searchText.length > 0) {
            this.searchObject(this.searchText)
            this.searchSuggestions = []
          }
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .backgroundColor('rgba(12, 16, 28, 0.72)')
    .backdropBlur(35)
    .border({ width: 0.5, color: 'rgba(91, 147, 191, 0.18)' })
    .borderRadius(22)
      .shadow({ radius: 16, color: 'rgba(0,0,0,0.25)', offsetX: 0, offsetY: 6 })
  }

  private bottomCardX(): number {
    if (!this.isExpandedLayout && !this.isFoldHoverLayout) { return 16 }
    if (!this.isExpandedLayout) { return Math.max(24, (this.skyWidth - this.bottomCardWidth()) / 2) }
    // Search recenters a target. Keep the tablet inspector on the far edge so
    // its rich data never sits over that visual centre. When another main
    // panel is open, retain the existing left-side coexistence layout.
    if (!this.panelVisible) {
      // 平板横屏：卡片靠右但留出足够边距，比之前再右移 16vp。
      return Math.max(this.EDGE_MARGIN + 92, this.skyWidth - this.bottomCardWidth() - this.EDGE_MARGIN + 16)
    }
    const minLeft = this.EDGE_MARGIN + 92
    const preferred = this.EDGE_MARGIN + 150
    const maxLeft = Math.max(minLeft, this.skyWidth - this.bottomCardWidth() - this.EDGE_MARGIN)
    return this.clamp(preferred, minLeft, maxLeft)
  }

  private bottomCardY(): number {
    // Keep the selected target in the visual centre. Full details live in the
    // upper safe area, leaving the lower half of the sky visible for the lock
    // marker and for direct sky interaction.
    if (this.isExpandedLayout) { return Math.max(this.EDGE_MARGIN + 76, 92) }
    return Math.max(86, Math.min(126, this.skyHeight * 0.12))
  }

  private bottomCardWidth(): number {
    // 手机详情卡保持左右对称留白，避免视觉上贴住右侧边框。
    if (!this.isExpandedLayout && !this.isFoldHoverLayout) { return Math.min(380, Math.max(286, this.skyWidth - 58)) }
    if (!this.isExpandedLayout) { return Math.min(318, Math.max(280, this.skyWidth - 52)) }
    if (this.panelVisible) {
      return Math.min(420, Math.max(360, this.expandedDetailAvailableWidth()))
    }
    // 平板横屏：加宽到 38%，确保"实时高度/方位"等字段不被截断。
    return this.clamp(this.skyWidth * 0.38, 340, 480)
  }

  private bottomCardHeight(): number {
    return this.isExpandedLayout ? 340 : (this.isFoldHoverLayout ? 318 : 292)
  }

  private bottomCardSwiperHeight(): number {
    return this.isExpandedLayout ? 170 : 156
  }

  private bottomCardHitHeight(): number {
    return this.bottomCardHeight()
  }

  private expandedMainPanelLeft(): number {
    return this.skyWidth - this.panelWidth - this.EDGE_MARGIN + this.panelOffsetX
  }

  private expandedDetailAvailableWidth(): number {
    const detailLeft = this.EDGE_MARGIN + 92
    return this.expandedMainPanelLeft() - detailLeft - 18
  }

  // 平板展开布局 + 搜索面板打开时，始终用紧凑摘要（不挤完整大卡片）。
  private useExpandedDetailSummary(): boolean {
    return this.isExpandedLayout && this.panelVisible
  }

  private expandedDetailSummaryWidth(): number {
    return this.clamp(this.expandedDetailAvailableWidth(), 140, 300)
  }

  private canShowExpandedDetailSummary(): boolean {
    return this.expandedDetailAvailableWidth() >= 140
  }

  private expandedDetailSummaryX(): number {
    return this.EDGE_MARGIN + 92
  }

  private expandedDetailSummaryY(): number {
    // 上移：原先 +84 使小详情卡偏中，遮挡视野中心；贴近顶部留出更多星空可视区
    return Math.max(this.EDGE_MARGIN + 16, 48)
  }

  private expandedDetailSummaryHeight(): number {
    return 230
  }

  private isExpandedDetailSummaryPoint(x: number, y: number): boolean {
    if (!this.useExpandedDetailSummary() || !this.canShowExpandedDetailSummary()) { return false }
    const sx = this.expandedDetailSummaryX()
    const sy = this.expandedDetailSummaryY()
    return x >= sx - 8 && x <= sx + this.expandedDetailSummaryWidth() + 8 && y >= sy - 8 && y <= sy + this.expandedDetailSummaryHeight() + 8
  }

  private handleExpandedDetailSummaryTap(x: number, y: number): boolean {
    if (!this.isExpandedDetailSummaryPoint(x, y)) { return false }
    const sx = this.expandedDetailSummaryX()
    const sy = this.expandedDetailSummaryY()
    const sw = this.expandedDetailSummaryWidth()
    if (y <= sy + 42 && x >= sx + sw - 40) {
      this.dismissObjectInspector()
      return true
    }
    if (y >= sy + this.expandedDetailSummaryHeight() - 42) {
      if (x < sx + sw / 2) {
        this.moveToSelectedObject()
      } else {
        this.toggleTracking()
      }
    }
    return true
  }

  private isPhoneDetailPeek(): boolean {
    return !this.isExpandedLayout && !this.isFoldHoverLayout && !this.infoWinExpanded
  }

  private compactObjectPeekWidth(): number {
    // Keep the selected-object peek entirely clear of the right-side gyro and
    // audio controls.  On narrow phones the old 250vp minimum overlapped them.
    const quickLeft = this.compactTopQuickX()
    return Math.min(Math.max(210, quickLeft - 34), 320)
  }

  private compactObjectPeekX(): number {
    const quickLeft = this.compactTopQuickX()
    const rightBound = quickLeft - 14
    const centered = (this.skyWidth - this.compactObjectPeekWidth()) / 2
    return Math.max(16, Math.min(centered, rightBound - this.compactObjectPeekWidth()))
  }

  private compactObjectPeekY(): number {
    return 92
  }

  private dismissObjectInspector(): void {
    this.infoWinVisible = false
    this.infoWinExpanded = false
    this.dismissedObjectName = this.selectedName
    this.lastInfoWinCloseMs = Date.now()
    this.skyTouchActive = false
    this.skyTouchFeedback = false
    this.skyDragging = false
    this.scheduleSelectedObjectForUiChange(280)
  }

  private showFullObjectInspector(): void {
    this.drawerOpen = false
    this.closePanel(true)
    this.infoWinVisible = true
    this.infoWinExpanded = true
    this.bottomCardIndex = 2
    this.dismissedObjectName = ''
    this.resetPanelIdle()
    this.scheduleSelectedObjectForUiChange(320)
  }

  private compactPanelUsableHeight(): number {
    if (this.isFoldHoverLayout) {
      return Math.max(Math.min(this.skyHeight * 0.46, 520), 320)
    }
    return Math.max(this.skyHeight - 318, 320)
  }

  private hoverSkyPaneHeight(): number {
    const angle = this.clamp(this.responsiveFoldAngle(), 55, 150)
    const ratio = this.clamp(0.43 + ((angle - 55) / 95) * 0.13, 0.43, 0.56)
    return this.clamp(this.skyHeight * ratio, 240, Math.max(280, this.skyHeight - 320))
  }

  private hoverConsoleTop(): number {
    return this.hoverSkyPaneHeight() + 10
  }

  private hoverPanelTop(): number {
    return Math.max(this.hoverConsoleTop() + 12, this.skyHeight - 90 - this.compactPanelHeight())
  }

  private compactPanelHeight(): number {
    const usable = this.compactPanelUsableHeight()
    const minH = usable * 0.6
    const maxH = usable * 0.9
    return this.clamp(usable * this.compactPanelSnapRatio - this.compactPanelDragOffsetY, minH - 28, maxH + 22)
  }

  private compactZoomTop(): number {
    if (this.panelVisible) {
      return Math.max(112, this.skyHeight - this.compactPanelHeight() - 168)
    }
    return Math.max(126, this.skyHeight - 212)
  }

  private isCompactZoomPoint(x: number, y: number): boolean {
    if (this.isExpandedLayout) {
      return false
    }
    const left = 18
    const top = this.compactZoomTop()
    return x >= left - 8 && x <= left + 68 && y >= top - 10 && y <= top + 132
  }

  private compactQuickTop(): number {
    return this.compactZoomTop()
  }

  private isCompactMorePoint(x: number, y: number): boolean {
    if (this.isExpandedLayout) {
      return false
    }
    return y >= this.skyHeight - 92 && x >= this.skyWidth * 0.72 && x <= this.skyWidth - 18
  }

  private isCompactDrawerPoint(x: number, y: number): boolean {
    if (this.isExpandedLayout || !this.drawerOpen) {
      return false
    }
    const drawerW = this.skyWidth * (this.isFoldHoverLayout ? 0.42 : 0.64)
    const rightMargin = this.isFoldHoverLayout ? 34 : 18
    const drawerX = this.skyWidth - rightMargin - drawerW
    const drawerBottom = this.skyHeight - 90
    const drawerY = drawerBottom - this.compactPanelHeight()
    return x >= drawerX - 12 && x <= this.skyWidth - rightMargin + 12 && y >= drawerY - 18 && y <= drawerBottom + 10
  }

  private handleCompactZoomTap(x: number, y: number): boolean {
    if (!this.isCompactZoomPoint(x, y)) {
      return false
    }
    const top = this.compactZoomTop()
    if (y <= top + 62) {
      this.zoomStep(0.5)
      this.flashHint(I18n.t('i0076'))
    } else {
      this.zoomStep(2.0)
      this.flashHint(I18n.t('i0077'))
    }
    return true
  }

  private handleCompactMoreTap(x: number, y: number): boolean {
    if (!this.isCompactMorePoint(x, y)) {
      return false
    }
    this.toggleDrawer()
    return true
  }

  private updateCompactPanelDrag(offsetY: number): void {
    const usable = this.compactPanelUsableHeight()
    this.compactPanelDragOffsetY = this.clamp(offsetY, -usable * 0.34, usable * 0.12)
  }

  private settleCompactPanelDrag(): void {
    const usable = this.compactPanelUsableHeight()
    const effectiveRatio = (usable * this.compactPanelSnapRatio - this.compactPanelDragOffsetY) / usable
    const nextRatio = this.compactPanelDragOffsetY > 32 ? 0.6 : (effectiveRatio >= 0.74 ? 0.9 : 0.6)
    this.getUIContext().animateTo({ duration: 360, curve: curves.springMotion(0.46, 0.86) }, () => {
      this.compactPanelSnapRatio = nextRatio
      this.compactPanelDragOffsetY = 0
    })
    this.scheduleSelectedObjectForUiChange(390)
  }

  private expandedUiAllowed(): boolean {
    // updateResponsiveLayout() has already classified this window as expanded.
    // Do not apply a second, stricter size threshold here: the physical Pad
    // reports a 673vp short side in landscape and otherwise loses its rail.
    return this.isExpandedLayout
  }

  private compactDockActions(): ShellAction[] {
    return [
      this.pinnedActions[0],
      this.pinnedActions[1],
      this.pinnedActions[2],
      this.pinnedActions[3],
      { label: '更多', icon: 'more', panel: 'more' }
    ] as ShellAction[]
  }

  private dockActionActive(item: ShellAction): boolean {
    if (this.drawerOpen) {
      return item.panel === 'more'
    }
    return item.panel === 'more' ? this.drawerOpen : (this.activePanel === item.panel && this.panelVisible)
  }

  // ── 天体检查器：把实时观测、坐标和完整资料分开呈现，避免字段堆成数据清单。 ──
  @Builder
  bottomDetailCard() {
    Column() {
      Row() {
        Image(this.getIcon('info', false))
          .width(18).height(18).fillColor('#73C8FF').margin({ right: 9 })
        Text(this.zhNameOf(this.selectedName))
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.zhType(this.selectedType))
          .fontSize(11).fontColor('#BDE8FF')
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .backgroundColor('rgba(91,147,191,0.18)').borderRadius(10)
        Text('✕')
          .fontSize(15).fontColor('#B8CAD7').padding({ left: 12, right: 4, top: 4, bottom: 4 })
          .onClick(() => {
            this.dismissObjectInspector()
          })
      }
      .width('100%').padding({ left: 16, right: 14, top: 10, bottom: 6 })

      Row({ space: 8 }) {
        this.objectCompactMetric(I18n.t('i0007'), this.selectedMagnitude.length > 0 ? this.selectedMagnitude : '--')
        this.objectCompactMetric(I18n.t('i0010'), this.selectedConstellation.length > 0 ? this.zhNameOf(this.selectedConstellation) : '--')
        this.objectCompactMetric(I18n.t('i0011'), this.selectedDistance.length > 0 ? this.selectedDistance : '--')
      }
        .width('100%').padding({ left: 16, right: 16, top: 3, bottom: 7 })

      Row() {
        Text('实时高度 / 方位').fontSize(10).fontColor('#8FBBD6').width(72)
        Text(this.selectedCoordAlt.length > 0 ? this.selectedCoordAlt : '--')
          .fontSize(11).fontColor('#E2F5FF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.selectedCoordAlt.length > 0 ? '已定位' : '等待定位')
          .fontSize(10).fontColor('#BDE8FF').margin({ left: 8 })
      }
        .height(24).width('100%').padding({ left: 16, right: 16, bottom: 4 })

      Row({ space: 4 }) {
        this.objectDetailTab('观测', 0)
        this.objectDetailTab('坐标', 1)
        this.objectDetailTab('资料', 2)
        this.objectDetailTab('操作', 3)
      }
        .width('100%').padding({ left: 16, right: 16, bottom: 8 })

      Divider().color('rgba(91,147,191,0.16)').margin({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 8 }) {
          if (this.bottomCardIndex === 0) {
            Text('今晚观测窗口').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%')
            Row({ space: 6 }) {
              this.objectScheduleTile(I18n.t('s0700'), this.selectedRise.length > 0 ? this.selectedRise : '--')
              this.objectScheduleTile(I18n.t('s0701'), this.selectedTransit.length > 0 ? this.selectedTransit : '--')
              this.objectScheduleTile(I18n.t('s0702'), this.selectedSet.length > 0 ? this.selectedSet : '--')
            }.width('100%')
            if (this.selectedApparentMagnitude.length > 0 || this.selectedAirmass.length > 0 || this.selectedExtinction.length > 0) {
              Text('大气影响').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%').margin({ top: 3 })
              Row({ space: 8 }) {
                if (this.selectedApparentMagnitude.length > 0) { this.objectMetric('大气后星等', this.selectedApparentMagnitude) }
                if (this.selectedExtinction.length > 0) { this.objectMetric('大气衰减', this.selectedExtinction + ' 等') }
                if (this.selectedAirmass.length > 0) { this.objectMetric('气团质量', this.selectedAirmass) }
              }.width('100%')
            }
            if (this.selectedPhase.length > 0 || this.selectedElongation.length > 0 || this.selectedSize.length > 0) {
              Row({ space: 8 }) {
                if (this.selectedPhase.length > 0) { this.objectMetric(I18n.t('i0291'), this.selectedPhase) }
                if (this.selectedElongation.length > 0) { this.objectMetric(I18n.t('i0255'), this.selectedElongation) }
                if (this.selectedSize.length > 0) { this.objectMetric(I18n.t('i0290'), this.selectedSize) }
              }.width('100%').margin({ top: 2 })
            }
            if (this.selectedInfo.length > 0) {
              Text(this.selectedInfo).fontSize(12).fontColor('#C3DDEB').lineHeight(18).width('100%')
                .padding({ top: 8, bottom: 2 })
            }
          } else if (this.bottomCardIndex === 1) {
            Text('当前天球位置').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%')
            this.objectDataRow(I18n.t('i0009'), this.selectedCoordAlt.length > 0 ? this.selectedCoordAlt : '--')
            this.objectDataRow(I18n.t('i0008'), this.selectedCoordEq.length > 0 ? this.selectedCoordEq : '--')
            this.objectDataRow(I18n.t('i0010'), this.selectedConstellation.length > 0 ? this.zhNameOf(this.selectedConstellation) : '--')
            Text('坐标会跟随时间、位置与视角更新。').fontSize(11).fontColor('#8FBBD6').lineHeight(16).width('100%').margin({ top: 4 })
          } else if (this.bottomCardIndex === 2) {
            Text('完整资料').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%')
            Row({ space: 8 }) {
              Column({ space: 7 }) {
                if (this.selectedCoordAlt.length > 0) { this.objectDataTile('实时高度 / 方位', this.selectedCoordAlt) }
                if (this.selectedMagnitude.length > 0) { this.objectDataTile(I18n.t('i0007'), this.selectedMagnitude) }
                if (this.selectedSize.length > 0) { this.objectDataTile(I18n.t('i0290'), this.selectedSize) }
                if (this.selectedApparentMagnitude.length > 0) { this.objectDataTile('大气后星等', this.selectedApparentMagnitude) }
                if (this.selectedRise.length > 0) { this.objectDataTile(I18n.t('s0700'), this.selectedRise) }
                if (this.selectedSet.length > 0) { this.objectDataTile(I18n.t('s0702'), this.selectedSet) }
              }.layoutWeight(1)
              Column({ space: 7 }) {
                if (this.selectedCoordEq.length > 0) { this.objectDataTile('赤经 / 赤纬', this.selectedCoordEq) }
                if (this.selectedDistance.length > 0) { this.objectDataTile(I18n.t('i0011'), this.selectedDistance) }
                if (this.selectedExtinction.length > 0) { this.objectDataTile('大气衰减', this.selectedExtinction + ' 等') }
                if (this.selectedAirmass.length > 0) { this.objectDataTile('气团质量', this.selectedAirmass) }
                if (this.selectedTransit.length > 0) { this.objectDataTile(I18n.t('s0701'), this.selectedTransit) }
                if (this.selectedConstellation.length > 0) { this.objectDataTile(I18n.t('i0010'), this.zhNameOf(this.selectedConstellation)) }
              }.layoutWeight(1)
            }.width('100%')
            if (this.selectedFullInfo.length > 0 || this.selectedRich.length > 0) {
              Column() {
                Text('补充观测资料').fontSize(11).fontColor('#8FBBD6').width('100%')
                ForEach(this.detailNarrativeLines(), (line: string) => {
                  Text(line).fontSize(12).fontColor('#D8EBF4').lineHeight(18).width('100%')
                    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                    .backgroundColor('rgba(147,215,255,0.045)').borderRadius(8)
                }, (line: string, index: number) => line + index.toString())
              }
                .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .backgroundColor('rgba(91,147,191,0.08)').borderRadius(12)
            }
          } else {
            Text('目标操作').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%')
            Button(this.observingList.includes(this.selectedName) ? I18n.t('s0739') : I18n.t('s0738'))
              .fontSize(12).fontColor('#E8F8FF').backgroundColor('rgba(91,147,191,0.28)').borderRadius(10).height(34).width('100%')
              .onClick(() => { this.toggleSelectedObservingList() })
            Row({ space: 8 }) {
              Button(I18n.t('s0721'))
                .fontSize(12).fontColor('#DDF4FF').backgroundColor('rgba(255,255,255,0.07)').borderRadius(10).height(34).layoutWeight(1)
                .onClick(() => { this.refreshSelectedObject(); this.refreshState() })
              Button(I18n.t('i0134'))
                .fontSize(12).fontColor('#DDF4FF').backgroundColor('rgba(255,255,255,0.07)').borderRadius(10).height(34).layoutWeight(1)
                .onClick(() => { this.triggerAction('actionGoto_ReSelect_Last_Selected_Object'); this.refreshSelectedObject() })
            }.width('100%')
            Button(I18n.t('s0760'))
              .fontSize(12).fontColor('#DDF4FF').backgroundColor('rgba(255,255,255,0.07)').borderRadius(10).height(34).width('100%')
              .onClick(() => { this.speakSelectedObject() })
            if (this.speechStatus.length > 0) {
              Text(this.speechStatus).fontSize(11).fontColor('#B9DBEB').lineHeight(16).width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor('rgba(91,147,191,0.08)').borderRadius(10)
            }
          }
        }
          .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
      }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .width('100%')
        .layoutWeight(1)

      Row({ space: 8 }) {
        Button(I18n.t('btn_center'))
          .fontSize(13).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(91,147,191,0.36)').borderRadius(12).height(36).layoutWeight(1)
          .onClick(() => { this.moveToSelectedObject() })
        Button(this.trackingText === 'On' ? I18n.t('btn_untrack') : I18n.t('btn_track'))
          .fontSize(13).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(91,147,191,0.36)').borderRadius(12).height(36).layoutWeight(1)
          .onClick(() => { this.toggleTracking() })
      }
      .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 })
    }
    .width(this.bottomCardWidth())
    .height(this.bottomCardHeight())
    .backgroundColor('rgba(12, 16, 28, 0.72)')
    .backdropBlur(28)
    .border({ width: 0.5, color: 'rgba(91, 147, 191, 0.18)' })
    .borderRadius(16)
    .shadow({ radius: 20, color: 'rgba(0,0,0,0.30)', offsetX: 0, offsetY: 8 })
  }

  @Builder
  expandedObjectSummary() {
    Column({ space: 7 }) {
      Row() {
        Image(this.getIcon('info', false)).width(16).height(16).fillColor('#73C8FF').margin({ right: 7 })
        Text(this.zhNameOf(this.selectedName)).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#F1FAFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('✕').fontSize(14).fontColor('#B8CAD7').padding({ left: 8, top: 4, bottom: 4 })
          .onClick(() => { this.dismissObjectInspector() })
      }.width('100%')
      Text(this.zhType(this.selectedType)).fontSize(10).fontColor('#9BCBE5').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.selectedMagnitude.length > 0 || this.selectedDistance.length > 0) {
        Row({ space: 8 }) {
          if (this.selectedMagnitude.length > 0) { this.expandedSummaryMetric(I18n.t('i0007'), this.selectedMagnitude) }
          if (this.selectedDistance.length > 0) { this.expandedSummaryMetric(I18n.t('i0011'), this.selectedDistance) }
        }.width('100%')
      }
      if (this.selectedCoordAlt.length > 0) {
        this.expandedSummaryLine('实时高度', this.selectedCoordAlt)
      }
      if (this.selectedCoordEq.length > 0) {
        this.expandedSummaryLine('赤经 / 赤纬', this.selectedCoordEq)
      }
      if (this.selectedApparentMagnitude.length > 0 || this.selectedAirmass.length > 0) {
        this.expandedSummaryLine('观测条件', this.expandedAtmosphereSummary())
      }
      Button('完整资料')
        .height(30).fontSize(11).fontColor('#DDF4FF').backgroundColor('rgba(255,255,255,0.07)').borderRadius(9).width('100%')
        .onClick(() => { this.showFullObjectInspector() })
      Row({ space: 6 }) {
        Button(I18n.t('btn_center'))
          .height(30).fontSize(11).fontColor('#E8F8FF').backgroundColor('rgba(91,147,191,0.34)').borderRadius(9).layoutWeight(1)
          .onClick(() => { this.moveToSelectedObject() })
        Button(this.trackingText === 'On' ? I18n.t('btn_untrack') : I18n.t('btn_track'))
          .height(30).fontSize(11).fontColor('#E8F8FF').backgroundColor('rgba(91,147,191,0.34)').borderRadius(9).layoutWeight(1)
          .onClick(() => { this.toggleTracking() })
      }.width('100%')
    }
      .width('100%').padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor('rgba(12,16,28,0.72)')
      .backdropBlur(28)
      .border({ width: 0.5, color: 'rgba(147,215,255,0.16)' }).borderRadius(14)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.30)', offsetX: 0, offsetY: 8 })
  }

  @Builder
  expandedSummaryMetric(label: string, value: string) {
    Column() {
      Text(label).fontSize(9).fontColor('#8FBBD6').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#E7F7FF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 2 })
    }
      .height(40).padding({ left: 8, right: 8, top: 5, bottom: 5 }).layoutWeight(1)
      .backgroundColor('rgba(91,147,191,0.10)').borderRadius(8)
  }

  @Builder
  expandedSummaryLine(label: string, value: string) {
    Row({ space: 6 }) {
      Text(label).fontSize(9).fontColor('#8FBBD6').width(48)
      Text(value).fontSize(10).fontColor('#D6EDF7').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%').height(20).padding({ left: 6, right: 6 })
      .backgroundColor('rgba(255,255,255,0.035)').borderRadius(6)
  }

  private expandedAtmosphereSummary(): string {
    const apparent = this.selectedApparentMagnitude.length > 0 ? '大气后 ' + this.selectedApparentMagnitude + ' 等' : ''
    const airmass = this.selectedAirmass.length > 0 ? '气团 ' + this.selectedAirmass : ''
    return (apparent + '  ' + airmass).trim()
  }

  @Builder
  objectMetric(label: string, value: string) {
    Column() {
      Text(label).fontSize(10).fontColor('#8FBBD6').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#E7F7FF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 3 })
    }
      .height(58).padding({ left: 10, right: 10, top: 8, bottom: 8 }).layoutWeight(1)
      .backgroundColor('rgba(91,147,191,0.10)').border({ width: 0.5, color: 'rgba(147,215,255,0.10)' }).borderRadius(10)
  }

  @Builder
  objectCompactMetric(label: string, value: string) {
    Column() {
      Text(label).fontSize(9).fontColor('#8FBBD6').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#E7F7FF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 1 })
    }
      .height(46).padding({ left: 8, right: 8, top: 6, bottom: 6 }).layoutWeight(1)
      .backgroundColor('rgba(91,147,191,0.10)').border({ width: 0.5, color: 'rgba(147,215,255,0.10)' }).borderRadius(10)
  }

  @Builder
  objectScheduleTile(label: string, value: string) {
    Column() {
      Text(label).fontSize(10).fontColor('#8FBBD6')
      Text(value).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#E7F7FF').margin({ top: 4 })
    }
      .height(62).layoutWeight(1).alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(91,147,191,0.12)').borderRadius(10)
  }

  @Builder
  objectDetailTab(label: string, index: number) {
    Text(label)
      .fontSize(12).fontWeight(this.bottomCardIndex === index ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.bottomCardIndex === index ? '#E8F8FF' : '#8FBBD6')
      .height(32).layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 8, bottom: 8 })
      .backgroundColor(this.bottomCardIndex === index ? 'rgba(91,147,191,0.30)' : 'rgba(255,255,255,0.03)')
      .borderRadius(8)
      .onClick(() => { this.bottomCardIndex = index })
  }

  @Builder
  objectDataRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label).fontSize(11).fontColor('#8FBBD6').width(68)
      Text(value).fontSize(12).fontColor('#E0F1F8').layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .backgroundColor('rgba(255,255,255,0.035)').borderRadius(8)
  }

  @Builder
  objectDataTile(label: string, value: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(9).fontColor('#8FBBD6').width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value).fontSize(11).fontColor('#E0F1F8').width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%').height(48).padding({ left: 9, right: 9, top: 6, bottom: 6 })
      .backgroundColor('rgba(255,255,255,0.045)').border({ width: 0.5, color: 'rgba(147,215,255,0.08)' }).borderRadius(8)
  }

  private toggleSelectedObservingList(): void {
    const idx = this.observingList.indexOf(this.selectedName)
    if (idx >= 0) {
      this.observingList.splice(idx, 1)
      this.flashHint(I18n.t('i0079'))
    } else {
      this.observingList.push(this.selectedName)
      this.flashHint(I18n.t('i0080'))
    }
    AppStorage.setOrCreate('observingList', JSON.stringify(this.observingList))
  }

  // 底部详情卡片触摸交互：只处理头部关闭按钮，
  // Swiper body 区域返回 false，让 Swiper 自身手势系统处理水平滑动。
  private handleInfoWinTap(x: number, y: number): boolean {
    if (!this.infoWinVisible || this.drawerOpen || (this.panelVisible && this.useExpandedDetailSummary())) { return false }
    if (this.isPhoneDetailPeek()) {
      const peekX = this.compactObjectPeekX()
      const peekY = this.compactObjectPeekY()
      const peekW = this.compactObjectPeekWidth()
      if (x < peekX - 8 || x > peekX + peekW + 8 || y < peekY - 8 || y > peekY + 72) { return false }
      if (x >= peekX + peekW - 44) {
        this.dismissObjectInspector()
      } else {
        this.infoWinExpanded = true
        this.resetPanelIdle()
      }
      return true
    }
    // bottomDetailCard 坐标（与 expandedShell/compactShell 中的 position 一致）
    let bcX: number = 0
    let bcY: number = 0
    const bcW = this.bottomCardWidth()
    if (this.isExpandedLayout) {
      bcX = this.bottomCardX()
      bcY = this.bottomCardY()
    } else {
      bcX = this.bottomCardX()
      bcY = this.bottomCardY()
    }
    if (x < bcX - 8 || x > bcX + bcW + 8 || y < bcY - 8) { return false }
    // 只处理头部区域（前 ~48px：名称 + 类型 + 关闭按钮）
    const headerH = 48
    if (y <= bcY + headerH) {
      const closeW = 40
      if (x >= bcX + bcW - closeW) {
        this.dismissObjectInspector()
        return true
      }
      // 头部其他区域点击不做任何操作
      return true
    }
    // Swiper body 区域也消费触摸，防止详情卡内点击穿透到星图选星。
    // Swiper 的水平滑动仍由 ArkUI 组件自身处理。
    return true
  }

  @Builder
  objInfoFloat() {
    Column() {
      // 头部：点名称/类型/箭头展开收起；✕ 关闭（不影响当前菜单）
      Row() {
        Image(this.getIcon('info', false))
          .width(18).height(18).fillColor('#5B93BF').margin({ right: 8 })
        Text(this.zhNameOf(this.selectedName))
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.zhType(this.selectedType))
          .fontSize(10).fontColor('#7FB3DC')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor('rgba(91,147,191,0.15)').borderRadius(6)
        Text(this.infoWinExpanded ? '▾' : '▸')
          .fontSize(14).fontColor('#99FFFFFF').padding({ left: 8, right: 4 })
        Text('✕')
          .fontSize(13).fontColor('#99FFFFFF').padding({ left: 6, right: 4 })
      }
      .width('100%').padding({ left: 12, right: 10, top: 10, bottom: 10 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })

      if (this.infoWinExpanded) {
        Divider().color(this.nmBorder()).margin({ left: 8, right: 8 })
        Scroll() {
          Column() {
            if (this.selectedMagnitude.length > 0) { this.infoRow(I18n.t('i0007'), this.selectedMagnitude) }
            if (this.selectedCoordEq.length > 0) { this.infoRow(I18n.t('i0008'), this.selectedCoordEq) }
            if (this.selectedCoordAlt.length > 0) { this.infoRow(I18n.t('i0009'), this.selectedCoordAlt) }
            if (this.selectedConstellation.length > 0) { this.infoRow(I18n.t('i0010'), this.zhNameOf(this.selectedConstellation)) }
            if (this.selectedDistance.length > 0) { this.infoRow(I18n.t('i0011'), this.selectedDistance) }
            if (this.selectedSize.length > 0) { this.infoRow(I18n.t('i0290'), this.selectedSize) }
            if (this.selectedRise.length > 0) { this.infoRow(I18n.t('s0700'), this.selectedRise) }
            if (this.selectedSet.length > 0) { this.infoRow(I18n.t('s0702'), this.selectedSet) }
            if (this.selectedTransit.length > 0) { this.infoRow(I18n.t('s0701'), this.selectedTransit) }
            if (this.selectedPhase.length > 0) { this.infoRow(I18n.t('i0291'), this.selectedPhase) }
            if (this.selectedElongation.length > 0) { this.infoRow(I18n.t('i0255'), this.selectedElongation) }
            if (this.selectedRich.length > 0) {
              Column() {
                Text(I18n.t('c_detail'))
                  .fontSize(11).fontColor('#99FFFFFF').width('100%')
                Text(this.richZh(this.selectedRich))
                  .fontSize(11).fontColor('#CCFFFFFF').lineHeight(16)
                  .width('100%').margin({ top: 4 })
              }
              .width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor('rgba(107,163,214,0.10)')
              .border({ width: 1, color: this.nmBorder() }).borderRadius(12)
              .margin({ top: 4, bottom: 4 })
            }
          }.width('100%')
        }
        .scrollable(ScrollDirection.Vertical)
        .width('100%')
        .height(this.infoWinDetailH())
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
            .combine(TransitionEffect.translate({ x: 0, y: -10 }).animation({ duration: 260, curve: curves.springMotion(0.5, 0.85) })),
          TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
        ))
        // 操作按钮常驻在滚动区下方，字段再多也不会被挤出可视区
        Row({ space: 8 }) {
          Button(I18n.t('btn_center'))
            .fontSize(12).fontColor('#E5FFFFFF')
            .backgroundColor('rgba(107,163,214,0.25)').borderRadius(12).height(34).layoutWeight(1)
          Button(this.trackingText === 'On' ? I18n.t('btn_untrack') : I18n.t('btn_track'))
            .fontSize(12).fontColor('#E5FFFFFF')
            .backgroundColor('rgba(107,163,214,0.25)').borderRadius(12).height(34).layoutWeight(1)
        }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 8 })
      }
    }
      .width('100%')
      .backgroundColor('rgba(18, 22, 36, 0.75)')
      .backdropBlur(34)
      .border({ width: 1, color: this.nmBorder() })
      .borderRadius(16)
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.35)', offsetX: 0, offsetY: 10 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 24, y: 0 }).animation({ duration: 420, curve: curves.springMotion(0.55, 0.85) })),
        TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
          .combine(TransitionEffect.translate({ x: 16, y: 0 }).animation({ duration: 200, curve: Curve.EaseIn }))
      ))
  }

  @Builder
  observerBadge() {
    Row() {
      Text('Stellarium')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E5FFFFFF')
        .maxLines(1)
      Text(I18n.t('i0002'))
        .fontSize(9)
        .fontColor('#7FB3DC')
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .backgroundColor('rgba(107, 163, 214, 0.10)')
        .borderRadius(12)
        .margin({ left: 8 })
    }
      .height(38)
      .padding({ left: 14, right: 12 })
      .backgroundColor('rgba(25, 26, 28, 0.72)')
      .backdropBlur(22)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(19)
      .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.24)', offsetX: 0, offsetY: 8 })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  zoomButton(icon: string) {
    Stack() {
      Image(this.getIcon(icon, false))
        .width(28).height(28)
        .fillColor(this.nmText())
    }
      .width(56)
      .height(56)
      .backgroundColor(this.phoneChromeIsGlass() ? 'rgba(10, 14, 26, 0.40)' : 'rgba(25, 26, 28, 0.64)')
      .backdropBlur(this.phoneChromeIsGlass() ? 38 : 26)
      .border({ width: 0.5, color: this.phoneChromeIsGlass() ? 'rgba(147, 215, 255, 0.10)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(28)
      .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: 8 })
      .opacity(this.phoneChromeOpacity())
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.9, y: 0.9 })
          .backgroundColor('rgba(255, 255, 255, 0.12)')
        }
      })
      .animation({ duration: 240, curve: curves.springMotion(0.42, 0.85) })
      // 手势由外层 Stack.onClick 统一处理
  }

  @Builder
  expandedZoomButton(icon: string) {
    Stack() {
      Image(this.getIcon(icon, false))
        .width(23).height(23)
        .fillColor(this.nmText())
    }
      .width(44)
      .height(44)
      .backgroundColor('rgba(25, 26, 28, 0.68)')
      .backdropBlur(24)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.10)' })
      .borderRadius(22)
      .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.28)', offsetX: 0, offsetY: 7 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.92, y: 0.92 })
          .backgroundColor('rgba(91, 147, 191, 0.46)')
        }
      })
      .animation({ duration: 220, curve: curves.springMotion(0.42, 0.85) })
  }

  @Builder
  verticalRail() {
  Stack() {
    // 常用入口（高频操作直接固定）
    ForEach(this.pinnedActions, (item: ShellAction, idx: number) => {
        Stack() { this.iconButton(item) }
          .width(44)
          .height(44)
          .position({ x: 7, y: this.RAIL_TOP_PAD + idx * 58 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.onRailTap(item.panel)
          })
    }, (item: ShellAction) => item.panel)
    // 分隔线：常用区与抽屉按钮之间
    Row()
      .width(26)
      .height(0.5)
      .backgroundColor('rgba(255,255,255,0.12)')
      .position({ x: 16, y: this.RAIL_TOP_PAD + this.pinnedActions.length * 58 + 1 })
      .hitTestBehavior(HitTestMode.None)
    // 更多（抽屉）按钮：展开/收起低频功能抽屉
    Stack() { this.moreButton() }
      .width(44)
      .height(44)
      .position({ x: 7, y: this.RAIL_TOP_PAD + this.pinnedActions.length * 58 + 8 })
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
        this.toggleDrawer()
      })
    // 音乐开关：打开应用即播空灵底噪，点新星体叮一声；可随时静音
    Stack() { this.musicButton() }
      .width(44)
      .height(44)
      .position({ x: 7, y: this.RAIL_TOP_PAD + this.pinnedActions.length * 58 + 60 })
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
        this.toggleMusic()
      })
    // 陀螺仪开关：开启后随设备转动平移星图，长按打开校准面板
    Stack() { this.gyroButton() }
      .width(44)
      .height(44)
      .position({ x: 7, y: this.RAIL_TOP_PAD + this.pinnedActions.length * this.RAIL_ITEM_STEP + this.RAIL_GYRO_OFFSET })
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
        this.toggleGyroscope(!this.gyroscopeEnabled)
        this.flashHint(this.gyroscopeEnabled ? '陀螺仪：开' : '陀螺仪：关')
      })
      .gesture(LongPressGesture({ repeat: false, duration: 600 })
        .onAction(() => {
          if (this.gyroscopeEnabled) {
            this.gyroCalibPanelOpen = !this.gyroCalibPanelOpen
          }
        }))
  }
    .width(58)
        .height(this.railHeight())
      .backgroundColor(this.panelIdleGlass ? 'rgba(10, 14, 26, 0.50)' : 'rgba(18, 22, 36, 0.78)')
      .backdropBlur(this.panelIdleGlass ? 40 : 26)
      .border({ width: 0.5, color: this.panelIdleGlass ? 'rgba(91, 147, 191, 0.15)' : 'rgba(91, 147, 191, 0.10)' })
      .borderRadius(29)
      .shadow({ radius: 28, color: 'rgba(0, 0, 0, 0.32)', offsetX: 0, offsetY: 14 })
      .opacity(this.railPinned ? 1.0 : this.panelIdleOpacity)
      .scale({ x: (!this.railPinned && this.panelIdleOpacity < 1) ? 0.94 : 1.0, y: (!this.railPinned && this.panelIdleOpacity < 1) ? 0.94 : 1.0 })
      .animation({ duration: 420, curve: Curve.Friction })
  }

  // 左侧栏外壳：承载收起动画与常驻把手
  @Builder
  railShell() {
    Stack() {
      // 轨道内容：空闲且未钉住时向左滑出，仅留把手
      Stack() { this.verticalRail() }
        .translate({ x: this.railCollapsed && !this.railPinned ? -64 : 0 })
        .animation({ duration: 360, curve: Curve.Friction })
      // 收起后的把手：点一下重新展开
      if (this.railCollapsed && !this.railPinned) {
        Stack() {
          Column() {
            Text("\u203A")
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#E5FFFFFF')
          }
            .width(26)
            .height(56)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor('rgba(25, 26, 28, 0.72)')
            .backdropBlur(20)
            .borderRadius(14)
            .shadow({ radius: 18, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: 8 })
        }
          .position({ x: 0, y: this.railHeight() / 2 })
          .onClick(() => {
            this.railCollapsed = false
            this.resetPanelIdle()
            this.flashHint(I18n.t('msg_panel_opened'))
          })
          .hitTestBehavior(HitTestMode.Block)
      }
    }
  }

  @Builder
  bottomDock() {
    Row() {
      // 紧凑底栏只保留四个最高频入口，观测/设置/插件等放进更多抽屉，避免手机折叠态挤爆。
      ForEach(this.compactDockActions(), (item: ShellAction) => {
        this.dockButton(item)
      }, (item: ShellAction) => item.panel)
    }
      .height(66)
      .width(this.isFoldHoverLayout ? '58%' : '92%')
      .padding({ left: 6, right: 6 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor(this.phoneChromeIsGlass() ? 'rgba(10, 14, 26, 0.42)' : 'rgba(25, 26, 28, 0.64)')
      .backdropBlur(this.phoneChromeIsGlass() ? 40 : 26)
      .border({ width: 0.5, color: this.phoneChromeIsGlass() ? 'rgba(147, 215, 255, 0.10)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(33)
      .shadow({ radius: 28, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: 14 })
      .alignSelf(ItemAlign.Center)
      .opacity(this.phoneChromeOpacity())
      .scale({ x: this.phoneChromeOpacity() < 1 ? 0.98 : 1.0, y: this.phoneChromeOpacity() < 1 ? 0.98 : 1.0 })
      .animation({ duration: 420, curve: Curve.Friction })
  }

  // 手机上的常驻控件随空闲状态变为轻透玻璃；展开和平板悬停布局保持各自的面板规则。
  private phoneChromeOpacity(): number {
    return (!this.isExpandedLayout && !this.isFoldHoverLayout) ? this.panelIdleOpacity : 1.0
  }

  private phoneChromeIsGlass(): boolean {
    return !this.isExpandedLayout && !this.isFoldHoverLayout && this.panelIdleGlass
  }

  // 夜间模式颜色方案
  private nm(): string {
    return this.nightMode ? 'rgba(180, 40, 20, 0.30)' : 'rgba(11, 17, 38, 0.85)'
  }
  private nmText(): string {
    return this.nightMode ? '#FF6644' : '#E5FFFFFF'
  }
  private nmSub(): string {
    return this.nightMode ? '#CC5533' : '#99FFFFFF'
  }
  private nmAccent(): string {
    return this.nightMode ? '#FF5533' : '#5B93BF'
  }
  private nmBg(): string {
    return this.nightMode ? 'rgba(180, 40, 20, 0.12)' : 'rgba(255,255,255,0.04)'
  }
  private nmBorder(): string {
    return this.nightMode ? 'rgba(200, 60, 30, 0.20)' : 'rgba(255,255,255,0.08)'
  }
  private nmInput(): string {
    return this.nightMode ? 'rgba(120, 30, 15, 0.50)' : 'rgba(255,255,255,0.06)'
  }
  private nmInputBorder(): string {
    return this.nightMode ? 'rgba(200, 60, 30, 0.25)' : 'rgba(214, 238, 255, 0.14)'
  }

  // ===== 中文映射（数据层英文名 → 界面中文） =====
  private planetZh(en: string): string {
    switch (en) {
      case 'Sun': return I18n.t('pl_sun')
      case 'Moon': return I18n.t('pl_moon')
      case 'Mercury': return I18n.t('pl_mercury')
      case 'Venus': return I18n.t('pl_venus')
      case 'Earth': return I18n.t('pl_earth')
      case 'Mars': return I18n.t('pl_mars')
      case 'Jupiter': return I18n.t('pl_jupiter')
      case 'Saturn': return I18n.t('pl_saturn')
      case 'Uranus': return I18n.t('pl_uranus')
      case 'Neptune': return I18n.t('pl_neptune')
      default: return en
    }
  }

  private sensZh(en: string): string {
    switch (en) {
      case 'Standard': return I18n.t('sens_standard')
      case 'Fast': return I18n.t('sens_fast')
      case 'Slow': return I18n.t('sens_slow')
      default: return en
    }
  }

  private trackStatusZh(en: string): string {
    return I18n.trackStatus(en)
  }

  private selectedStatusZh(en: string): string {
    return I18n.selectedStatus(en)
  }

  private richZh(text: string): string {
    if (!text || text.length === 0) return ''
    // 清理 HTML 标签（<span>, <br>, <i>, <b>, <a> 等）
    let out: string = text.replace(/<[^>]*>/g, '')
    // 清理多余空白和连接符
    out = out.replace(/\s*-\s*/g, ' · ').replace(/\s{2,}/g, ' ').trim()
    const phrases: [string, string][] = [
      ['eclipsing binary system', '食双星系统'],
      ['double star', '双星'],
      ['binary star', '双星'],
      ['variable star', '变星'],
      ['open cluster', '疏散星团'],
      ['globular cluster', '球状星团'],
      ['planetary nebula', '行星状星云'],
      ['supernova remnant', '超新星遗迹'],
      ['emission nebula', '发射星云'],
      ['reflection nebula', '反射星云'],
      ['spiral galaxy', '螺旋星系'],
      ['elliptical galaxy', '椭圆星系'],
      [' galaxy', '星系'],
      [' nebula', '星云'],
      [' cluster', '星团']
    ]
    for (let i = 0; i < phrases.length; i++) {
      const pair = phrases[i]
      out = out.replace(new RegExp(pair[0], 'gi'), pair[1])
    }
    return out
  }

  // AllInfo 是 Stellarium 的单行纯文本；按稳定的字段标题分段后再渲染，避免误标成“星等限制”。
  private detailNarrativeLines(): string[] {
    const source = this.selectedFullInfo.length > 0 ? this.selectedFullInfo : this.selectedRich
    let text = this.richZh(source)
    if (text.length === 0) { return [] }
    const markers: string[] = [
      '星等:', '赤经/赤纬', '方位角/地平高度', '与太阳距离:', '距离:',
      '光行时:', '视直径:', '赤道直径:', '相位:', '伸长角:', '日出:', '中天:', '日落:'
    ]
    for (let i = 0; i < markers.length; i++) {
      text = text.replace(markers[i], '\n' + markers[i])
    }
    const parts = text.split('\n')
    const lines: string[] = []
    for (let i = 0; i < parts.length; i++) {
      const line = parts[i].trim()
      if (line.length > 0) { lines.push(line) }
    }
    return lines
  }

  private pluginZh(en: string): ResourceStr {
    // 先查精确映射（保持已有 key 的一致性）
    switch (en) {
      case 'Angle Measure': return I18n.t('plugin_angle_measure')
      case 'ArchaeoLines': return I18n.t('plugin_archaeolines')
      case 'Calendars': return I18n.t('plugin_calendars')
      case 'Equation of Time': return I18n.t('plugin_equation_of_time')
      case 'Exoplanets': return I18n.t('plugin_exoplanets')
      case 'Lens distortion estimator': return I18n.t('plugin_lens_distortion')
      case 'Meteor Showers': return I18n.t('plugin_meteor_showers')
      case 'Novae': return I18n.t('plugin_novae')
      case 'Pulsars': return I18n.t('plugin_pulsars')
      case 'Quasars': return I18n.t('plugin_quasars')
      case 'Satellites': return I18n.t('plugin_satellites')
      case 'Solar System Editor': return I18n.t('plugin_solar_system_editor')
      case 'Supernovae': return I18n.t('plugin_supernovae')
      case 'Text User Interface': return I18n.t('plugin_text_user_interface')
      case 'Time Zone': return I18n.t('plugin_time_zone')
      case 'Voculars': return I18n.t('plugin_voculars')
      case 'Observability': return I18n.t('plugin_observability')
      case 'Remote Control': return I18n.t('plugin_remote_control')
      case 'Screenshots': return I18n.t('plugin_screenshots')
      case 'Sky Cultures': return I18n.t('plugin_skycultures')
    }
    // 回退到 PLUGIN_NAMES 字典（覆盖所有 40+ 插件）
    const dictName = I18n.pluginName(en)
    if (dictName !== en) return dictName
    // 最后兜底：尝试首字母大写等微调后再查一次
    const trimmed = en.trim()
    return I18n.pluginName(trimmed) !== trimmed ? I18n.pluginName(trimmed) : en
  }

  // ── 插件功能描述（副标题） ──
  private pluginDesc(en: string): string {
    switch (en) {
      case 'Angle Measure': return I18n.t('plugin_desc_angle_measure') as string
      case 'ArchaeoLines': return I18n.t('plugin_desc_archaeolines') as string
      case 'Calendars': return I18n.t('plugin_desc_calendars') as string
      case 'Equation of Time': return I18n.t('plugin_desc_equation_of_time') as string
      case 'Exoplanets': return I18n.t('plugin_desc_exoplanets') as string
      case 'Lens distortion estimator': return I18n.t('plugin_desc_lens_distortion') as string
      case 'Meteor Showers': return I18n.t('plugin_desc_meteor_showers') as string
      case 'Novae': return I18n.t('plugin_desc_novae') as string
      case 'Observability': return I18n.t('plugin_desc_observability') as string
      case 'Pulsars': return I18n.t('plugin_desc_pulsars') as string
      case 'Quasars': return I18n.t('plugin_desc_quasars') as string
      case 'Remote Control': return I18n.t('plugin_desc_remote_control') as string
      case 'Satellites': return I18n.t('plugin_desc_satellites') as string
      case 'Screenshots': return I18n.t('plugin_desc_screenshots') as string
      case 'Sky Cultures': return I18n.t('plugin_desc_skycultures') as string
      case 'Solar System Editor': return I18n.t('plugin_desc_solar_system_editor') as string
      case 'Supernovae': return I18n.t('plugin_desc_supernovae') as string
      case 'Text User Interface': return I18n.t('plugin_desc_text_user_interface') as string
      case 'Time Zone': return I18n.t('plugin_desc_time_zone') as string
      case 'Voculars': return I18n.t('plugin_desc_voculars') as string
    }
    return ''
  }

  // ── 脚本文件名 → 中文名 ──
  private scriptZh(filename: string): ResourceStr {
    // 去掉 .ssc 后缀
    const name = filename.replace(/\.ssc$/, '')
    switch (name) {
      case 'constellations_tour': return I18n.t('script_name_constellations_tour')
      case 'modern_constellations_tour': return I18n.t('script_name_modern_constellations_tour')
      case 'messier_marathon': return I18n.t('script_name_messier_marathon')
      case 'BAS_Messier_Tour': return I18n.t('script_name_BAS_Messier_Tour')
      case 'planets_tour': return I18n.t('script_name_planets_tour')
      case 'BAS_Jupiter_Moons': return I18n.t('script_name_BAS_Jupiter_Moons')
      case 'lunar_total': return I18n.t('script_name_lunar_total')
      case 'lunar_partial': return I18n.t('script_name_lunar_partial')
      case 'solar_eclipse': return I18n.t('script_name_solar_eclipse')
      case 'transit_of_venus': return I18n.t('script_name_transit_of_venus')
      case 'supernova': return I18n.t('script_name_supernova')
      case 'triple_sunrise_and_sunsets': return I18n.t('script_name_triple_sunrise_and_sunsets')
      case 'analemma': return I18n.t('script_name_analemma')
      case 'martian_analemma': return I18n.t('script_name_martian_analemma')
      case 'saturnian_analemma': return I18n.t('script_name_saturnian_analemma')
      case 'uranian_analemma': return I18n.t('script_name_uranian_analemma')
      case 'best_ngc': return I18n.t('script_name_best_ngc')
      case 'h400_tour': return I18n.t('script_name_h400_tour')
      case 'double_stars': return I18n.t('script_name_double_stars')
      case 'largest_known_stars': return I18n.t('script_name_largest_known_stars')
      case 'binocular_highlights': return I18n.t('script_name_binocular_highlights')
      case 'binosky': return I18n.t('script_name_binosky')
      case 'bennett': return I18n.t('script_name_bennett')
      case 'sky_cultures': return I18n.t('script_name_sky_cultures')
      case 'landscapes': return I18n.t('script_name_landscapes')
      case 'screensaver': return I18n.t('script_name_screensaver')
      case 'solar_system_screensaver': return I18n.t('script_name_solar_system_screensaver')
      case 'skybox': return I18n.t('script_name_skybox')
      case 'random_location': return I18n.t('script_name_random_location')
      case 'sun': return I18n.t('script_name_sun')
      case 'zodiac': return I18n.t('script_name_zodiac')
      case 'phobos_phun_1': return I18n.t('script_name_phobos_phun_1')
      case 'phobos_phun_2': return '火卫一趣闻（二）'
      case 'phobos_phun_3': return '火卫一趣闻（三）'
      case 'phobos_phun_4': return '火卫一趣闻（四）'
      case 'phobos_phun_5': return '火卫一趣闻（五）'
      case 'morsels_1': return '天体小点心（一）'
      case 'morsels_2': return '天体小点心（二）'
      case 'morsels_3': return '天体小点心（三）'
      case 'morsels_4': return '天体小点心（四）'
      case 'earth_1': return '地球一月天象'
      case 'earth_2': return '地球二月天象'
      case 'earth_3': return '地球三月天象'
      case 'earth_4': return '地球四月天象'
      case 'earth_5': return '地球五月天象'
      case 'earth_6': return '地球六月天象'
      case 'earth_7': return '地球七月天象'
      case 'startup': return '启动引导脚本'
      default: return filename
    }
  }

  // ── 脚本简短描述 ──
  private scriptDesc(filename: string): string {
    const name = filename.replace(/\.ssc$/, '')
    switch (name) {
      case 'constellations_tour': return I18n.t('script_desc_constellations_tour') as string
      case 'modern_constellations_tour': return I18n.t('script_desc_constellations_tour') as string
      case 'messier_marathon': return I18n.t('script_desc_messier_marathon') as string
      case 'BAS_Messier_Tour': return I18n.t('script_desc_messier_marathon') as string
      case 'planets_tour': return I18n.t('script_desc_planets_tour') as string
      case 'BAS_Jupiter_Moons': return I18n.t('script_desc_gral') as string
      case 'lunar_total': return I18n.t('script_desc_lunar_total') as string
      case 'lunar_partial': return I18n.t('script_desc_gral') as string
      case 'solar_eclipse': return I18n.t('script_desc_solar_eclipse') as string
      case 'transit_of_venus': return I18n.t('script_desc_gral') as string
      case 'supernova': return I18n.t('script_desc_gral') as string
      case 'triple_sunrise_and_sunsets': return I18n.t('script_desc_gral') as string
      case 'analemma': return I18n.t('script_desc_analemma') as string
      case 'martian_analemma': return I18n.t('script_desc_gral') as string
      case 'saturnian_analemma': return I18n.t('script_desc_gral') as string
      case 'uranian_analemma': return I18n.t('script_desc_gral') as string
      case 'best_ngc': return I18n.t('script_desc_best_ngc') as string
      case 'h400_tour': return I18n.t('script_desc_gral') as string
      case 'double_stars': return I18n.t('script_desc_double_stars') as string
      case 'largest_known_stars': return I18n.t('script_desc_gral') as string
      case 'binocular_highlights': return I18n.t('script_desc_binocular_highlights') as string
      case 'binosky': return I18n.t('script_desc_gral') as string
      case 'bennett': return I18n.t('script_desc_gral') as string
      case 'sky_cultures': return I18n.t('script_desc_sky_cultures') as string
      case 'landscapes': return I18n.t('script_desc_gral') as string
      case 'screensaver': return I18n.t('script_desc_screensaver') as string
      case 'solar_system_screensaver': return I18n.t('script_desc_gral') as string
      case 'skybox': return I18n.t('script_desc_gral') as string
      case 'random_location': return I18n.t('script_desc_random_location') as string
      case 'sun': return I18n.t('script_desc_gral') as string
      case 'zodiac': return I18n.t('script_desc_gral') as string
      default: return ''
    }
  }

  private landscapeZh(en: string): ResourceStr {
    switch (en) {
      case 'Garching': return I18n.t('land_garching')
      case 'Geneva': return I18n.t('land_geneva')
      case 'Guereins': return I18n.t('land_guereins')
      case 'Grossmugl': return I18n.t('land_grossmugl')
      case 'Hurricane': return I18n.t('land_hurricane')
      case 'Jupiter': return I18n.t('land_jupiter')
      case 'Mars': return I18n.t('land_mars')
      case 'Moon': return I18n.t('land_moon')
      case 'Armintxe Cave': return I18n.t('land_armintxe')
      case 'Zero': return I18n.t('land_zero')
      case 'Guereins 0 0': return I18n.t('land_guereins_0_0')
      case 'Ocean': return I18n.t('land_ocean')
      default: return en
    }
  }

  private satGroupZh(en: string): string {
    return I18n.satGroup(en)
  }

  private getIcon(icon: string, isActive: boolean): Resource {
    const map: Record<string, Resource> = {
      'search': $r('app.media.ic_search'),
      'clock': $r('app.media.ic_clock'),
      'location': $r('app.media.ic_location'),
      'layers': $r('app.media.ic_layers'),
      'info': $r('app.media.ic_info'),
      'settings': $r('app.media.ic_settings'),
      'catalogs': $r('app.media.ic_download'),
      'bookmarks': $r('app.media.ic_bookmark'),
      'telescope': $r('app.media.ic_telescope'),
      'satellite': $r('app.media.ic_satellite'),
      'meteor': $r('app.media.ic_meteor'),
      'script': $r('app.media.ic_code'),
      'tune': $r('app.media.ic_tune'),
      'orbit': $r('app.media.ic_orbit'),
      'help': $r('app.media.ic_help'),
      'grid': $r('app.media.ic_grid'),
      'more': $r('app.media.ic_more'),
      'close': $r('app.media.ic_close'),
      'gyro': $r('app.media.ic_gyro'),
      'zoom_in': $r('app.media.ic_zoom_in'),
      'zoom_out': $r('app.media.ic_zoom_out'),
      'lock': $r('app.media.ic_lock'),
      'unlock': $r('app.media.ic_unlock'),
      'projection': $r('app.media.ic_screenshot'),
      'observe': $r('app.media.ic_list'), 'audio': $r('app.media.ic_audio'), 'forward': $r('app.media.ic_forward'),
    }
    return map[icon] || $r('app.media.ic_search')
  }
  @Builder
  ocularSelector(kind: string, label: string) {
    Column({ space: 4 }) {
      Text(label).fontSize(12).fontColor('#99FFFFFF').width('100%').padding({ left: 2 })
      Row() {
        Button(I18n.t('btn_prev'))
          .fontSize(18).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(255,255,255,0.08)').borderRadius(12).width(40).height(36)
          .onClick(() => { this.cycleOcular(kind, 'prev') })
        Column() {
          Text(this.ocularSelInfo(kind).name)
            .fontSize(13).fontColor('#E5FFFFFF').fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.ocularSelInfo(kind).countText)
            .fontSize(11).fontColor('#99FFFFFF').margin({ top: 2 })
        }.alignItems(HorizontalAlign.Center).layoutWeight(1)
        Button(I18n.t('btn_next'))
          .fontSize(18).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(255,255,255,0.08)').borderRadius(12).width(40).height(36)
          .onClick(() => { this.cycleOcular(kind, 'next') })
      }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
    }.width('100%')
  }
  @Builder
  iconButton(item: ShellAction) {
    Column() {
      Image(this.getIcon(item.icon, this.activePanel === item.panel && this.panelVisible))
        .width(22).height(22)
        .fillColor(this.activePanel === item.panel && this.panelVisible ? '#FFFFFF' : this.nmText())
    }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.activePanel === item.panel && this.panelVisible ? '#5B93BF' : 'rgba(255, 255, 255, 0.06)')
      .border({ width: 1, color: this.activePanel === item.panel && this.panelVisible ? 'rgba(107, 163, 214, 0.35)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(22)
      .margin({ top: 4, bottom: 4 })
      .scale({ x: this.activePanel === item.panel && this.panelVisible ? 1.08 : 1.0, y: this.activePanel === item.panel && this.panelVisible ? 1.08 : 1.0 })
      .shadow({
        radius: this.activePanel === item.panel && this.panelVisible ? 18 : 0,
        color: this.activePanel === item.panel && this.panelVisible ? 'rgba(107, 163, 214, 0.25)' : 'rgba(0, 0, 0, 0)',
        offsetX: 0,
        offsetY: 6
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.9, y: 0.9 })
          .backgroundColor('rgba(255, 255, 255, 0.12)')
        }
      })
      .animation({ duration: 260, curve: curves.springMotion(0.42, 0.85) })
      // 手势由外层 Stack.onClick 统一处理
  }

  // 收起当前页面按钮：把右侧浮动面板收回到左侧栏
  @Builder
  collapseButton() {
    Column() {
      Image(this.getIcon('forward', false))
        .width(22)
        .height(22)
        .fillColor(this.panelVisible ? '#FFFFFF' : this.nmText())
        .rotate({ angle: 180 })
        .animation({ duration: 260, curve: curves.springMotion(0.42, 0.85) })
    }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.panelVisible ? '#5B93BF' : 'rgba(255, 255, 255, 0.06)')
      .border({ width: 1, color: this.panelVisible ? 'rgba(107, 163, 214, 0.35)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(22)
      .margin({ top: 4, bottom: 4 })
      .scale({ x: this.panelVisible ? 1.08 : 1.0, y: this.panelVisible ? 1.08 : 1.0 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.9, y: 0.9 })
          .backgroundColor('rgba(255, 255, 255, 0.12)')
        }
      })
      .animation({ duration: 260, curve: curves.springMotion(0.42, 0.85) })
  }

  // 「更多」九宫格按钮：展开低频功能抽屉
  @Builder
  moreButton() {
    Column() {
      // 三点菜单图标（替代原方格图标，更简洁优雅）
      Column({ space: 4 }) {
        Circle().width(4).height(4).fill(this.drawerOpen ? '#FFFFFF' : this.nmText())
        Circle().width(4).height(4).fill(this.drawerOpen ? '#FFFFFF' : this.nmText())
        Circle().width(4).height(4).fill(this.drawerOpen ? '#FFFFFF' : this.nmText())
      }
      .width(22).height(22)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .rotate({ angle: this.drawerOpen ? 90 : 0 })
      .animation({ duration: 360, curve: curves.springMotion(0.5, 0.8) })
    }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.drawerOpen ? '#5B93BF' : 'rgba(255, 255, 255, 0.06)')
      .border({ width: 1, color: this.drawerOpen ? 'rgba(107, 163, 214, 0.35)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(22)
      .margin({ top: 4, bottom: 4 })
      .scale({ x: this.drawerOpen ? 1.08 : 1.0, y: this.drawerOpen ? 1.08 : 1.0 })
      .onClick(() => { this.toggleDrawer() })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.9, y: 0.9 })
          .backgroundColor('rgba(255, 255, 255, 0.12)')
        }
      })
      .animation({ duration: 260, curve: curves.springMotion(0.42, 0.85) })
  }

  // 音乐开关按钮（左侧栏底部）：开着时音符亮起，静音时变暗
  @Builder
  musicButton() {
    Stack() {
      Image(this.getIcon('audio', this.musicEnabled))
        .width(22)
        .height(22)
        .fillColor(this.musicEnabled ? '#FFFFFF' : this.nmText())
    }
      .width(44)
      .height(44)
      .alignContent(Alignment.Center)
      .backgroundColor(this.musicEnabled ? 'rgba(91, 147, 191, 0.22)' : 'rgba(255, 255, 255, 0.06)')
      .border({ width: 1, color: this.musicEnabled ? 'rgba(107, 163, 214, 0.45)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(22)
      .margin({ top: 4, bottom: 4 })
      .scale({ x: this.musicEnabled ? 1.06 : 1.0, y: this.musicEnabled ? 1.06 : 1.0 })
      .onClick(() => { this.toggleMusic() })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.9, y: 0.9 })
          .backgroundColor('rgba(255, 255, 255, 0.12)')
        }
      })
      .animation({ duration: 260, curve: curves.springMotion(0.42, 0.85) })
  }

  // ── 陀螺仪按钮（平板左侧栏，与手机端 compactQuickButton 共用 ic_gyro.svg）──
  @Builder
  gyroButton() {
    Stack() {
      Image(this.getIcon('gyro', this.gyroscopeEnabled))
        .width(22)
        .height(22)
        .fillColor(this.gyroscopeEnabled ? '#FFFFFF' : this.nmText())
    }
      .width(44)
      .height(44)
      .alignContent(Alignment.Center)
      .backgroundColor(this.gyroscopeEnabled ? 'rgba(91, 147, 191, 0.22)' : 'rgba(255, 255, 255, 0.06)')
      .border({ width: 1, color: this.gyroscopeEnabled ? 'rgba(107, 163, 214, 0.45)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(22)
      .margin({ top: 4, bottom: 4 })
      .scale({ x: this.gyroscopeEnabled ? 1.06 : 1.0, y: this.gyroscopeEnabled ? 1.06 : 1.0 })
      .onClick(() => {
        this.toggleGyroscope(!this.gyroscopeEnabled)
        this.flashHint(this.gyroscopeEnabled ? '陀螺仪：开' : '陀螺仪：关')
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.9, y: 0.9 })
          .backgroundColor('rgba(255, 255, 255, 0.12)')
        }
      })
      .animation({ duration: 260, curve: curves.springMotion(0.42, 0.85) })
  }

  // ── 陀螺仪校准面板 ──
  @Builder
  gyroCalibPanel() {
    Column({ space: 12 }) {
      // 标题行
      Row() {
        Stack() {
          Circle().width(10).height(10)
            .fill(this.gyroscopeEnabled ? '#5BDF7F' : '#666')
            .opacity(0.9)
        }.width(16).height(16)
        Text(I18n.t('i0060'))
          .fontSize(14).fontWeight(FontWeight.Bold).fontColor('#E5FFFFFF').layoutWeight(1).margin({ left: 6 })
        Text('×')
          .fontSize(18).fontColor('#99FFFFFF')
          .onClick(() => { this.gyroCalibPanelOpen = false })
      }
      .width('100%')

      Text(I18n.t('i0043'))
        .fontSize(11).fontColor('#8099BBCC').width('100%')

      // 灵敏度选择
      Row({ space: 8 }) {
        Text(I18n.t('i0061')).fontSize(12).fontColor('#CCCCCC').width(44)
        Row({ space: 6 }) {
          ForEach(['Low', 'Standard', 'High'], (s: string, idx: number) => {
            Text(s)
              .fontSize(11)
              .fontColor(this.gyroscopeSensitivityText === s ? '#FFFFFF' : '#8099BBCC')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(10)
              .backgroundColor(this.gyroscopeSensitivityText === s ? 'rgba(91,147,191,0.35)' : 'rgba(255,255,255,0.06)')
              .onClick(() => {
                this.gyroscopeSensitivityText = s
                this.flashHint(s)
              })
          })
        }.layoutWeight(1).justifyContent(FlexAlign.End)
      }.width('100%')

      // 方位角校准
      Row({ space: 10 }) {
        Text(I18n.t('i0084') + '→' + I18n.t('i0086')).fontSize(11).fontColor('#CCCCCC').width(50)
        Slider({ value: this.gyroOffsetAz, min: -30, max: 30, step: 0.5 })
          .layoutWeight(1)
          .selectedColor('#5B93BF')
          .trackColor('rgba(255,255,255,0.12)')
          .onChange((v: number) => { this.gyroOffsetAz = v })
        Text(this.gyroOffsetAz.toFixed(1) + '°')
          .fontSize(11).fontColor('#7FB3DC').width(48).textAlign(TextAlign.End)
      }.width('100%')

      // 高度角校准
      Row({ space: 10 }) {
        Text(I18n.t('i0016')).fontSize(11).fontColor('#CCCCCC').width(50)
        Slider({ value: this.gyroOffsetAlt, min: -30, max: 30, step: 0.5 })
          .layoutWeight(1)
          .selectedColor('#5B93BF')
          .trackColor('rgba(255,255,255,0.12)')
          .onChange((v: number) => { this.gyroOffsetAlt = v })
        Text(this.gyroOffsetAlt.toFixed(1) + '°')
          .fontSize(11).fontColor('#7FB3DC').width(48).textAlign(TextAlign.End)
      }.width('100%')

      // 重置按钮
      Row({ space: 8 }) {
        Button(I18n.t('i0053'))
          .fontSize(12).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(91,147,191,0.25)').borderRadius(12).height(32).layoutWeight(1)
          .onClick(() => {
            this.gyroOffsetAz = 0
            this.gyroOffsetAlt = 0
            this.gyroCompassAzAlignment = 0
            this.calibrateGyroscope()
            this.flashHint('已重新校准')
          })
        Button(I18n.t('i0051'))
          .fontSize(12).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(200,80,60,0.25)').borderRadius(12).height(32).layoutWeight(1)
          .onClick(() => {
            this.toggleGyroscope(false)
            this.gyroCalibPanelOpen = false
          })
      }.width('100%').margin({ top: 4 })

      // 状态信息
      Row() {
        Text((this.gyroscopeStatus as string))
          .fontSize(10).fontColor('#8099BBCC')
      }.width('100%')
    }
    .width(280)
    .padding(16)
    .backgroundColor('rgba(12, 16, 28, 0.92)')
    .border({ width: 0.5, color: 'rgba(91, 147, 191, 0.18)' })
    .borderRadius(20)
    .shadow({ radius: 20, color: 'rgba(0,0,0,0.30)', offsetX: 0, offsetY: 8 })
  }

  // 切换音乐开关（带 350ms 防抖，避免坐标命中与 onClick 双触发导致来回跳）
  private toggleMusic(): void {
    const now = Date.now()
    if (now - this.lastMusicToggle < 350) { return }
    this.lastMusicToggle = now
    this.musicEnabled = !this.musicEnabled
    const engine = AudioEngine.getInstance()
    if (this.musicEnabled) {
      engine.start().then(() => { engine.setMuted(false) })
    } else {
      engine.setMuted(true)
    }
    this.persistMusicEnabled()
    this.flashHint(this.musicEnabled ? '音乐：开 ♪' : '音乐：静音')
  }

  private persistMusicEnabled(): void {
    let obj: Record<string, boolean | string> = {}
    const cur = AppStorage.get<string>('stellariumSettings')
    if (cur) {
      try { obj = JSON.parse(cur) as Record<string, boolean | string> } catch (e) { }
    }
    obj['musicEnabled'] = this.musicEnabled
    AppStorage.setOrCreate('stellariumSettings', JSON.stringify(obj))
  }

  private persistNightMode(): void {
    let obj: Record<string, boolean | string> = {}
    const cur = AppStorage.get<string>('stellariumSettings')
    if (cur) {
      try { obj = JSON.parse(cur) as Record<string, boolean | string> } catch (e) { }
    }
    obj['nightMode'] = this.nightMode
    AppStorage.setOrCreate('stellariumSettings', JSON.stringify(obj))
  }

  private persistEquatorialMount(): void {
    let obj: Record<string, boolean | string> = {}
    const cur = AppStorage.get<string>('stellariumSettings')
    if (cur) {
      try { obj = JSON.parse(cur) as Record<string, boolean | string> } catch (e) { }
    }
    obj['equatorialMount'] = this.equatorialMount
    AppStorage.setOrCreate('stellariumSettings', JSON.stringify(obj))
  }

  // 低频功能抽屉：从侧栏右侧滑出，图标(带背景圆) + 名称 + 激活态左边框
  @Builder
  actionDrawer() {
    Column({ space: 3 }) {
      Text(I18n.t('c_more_functions'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.panelIdleGlass ? 'rgba(229,255,255,0.58)' : this.nmSub())
        .width('100%')
        .padding({ left: 18, top: 10, bottom: 6 })
      ForEach(this.drawerActions, (item: ShellAction) => {
        Row({ space: 12 }) {
          // 图标背景圆
          Stack() {
            Circle()
              .width(32)
              .height(32)
              .fill(this.activePanel === item.panel && this.panelVisible ? 'rgba(91, 147, 191, 0.28)' : 'rgba(255, 255, 255, 0.06)')
            Image(this.getIcon(item.icon, this.activePanel === item.panel && this.panelVisible))
              .width(18)
              .height(18)
              .fillColor(this.activePanel === item.panel && this.panelVisible ? '#93D7FF' : this.nmText())
          }
            .width(32)
            .height(32)
          Text(item.label)
            .fontSize(14)
            .fontWeight(this.activePanel === item.panel && this.panelVisible ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.activePanel === item.panel && this.panelVisible ? '#E0F4FF' : this.nmText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 12 })
          .borderRadius(14)
          .backgroundColor(this.activePanel === item.panel && this.panelVisible ? 'rgba(91, 147, 191, 0.14)' : 'rgba(255,255,255,0.03)')
          .border({
            width: { left: this.activePanel === item.panel && this.panelVisible ? 3 : 0, right: 0, top: 0, bottom: 0 },
            color: this.activePanel === item.panel && this.panelVisible ? '#5B93BF' : 'transparent'
          })
          .borderRadius({ topLeft: 14, bottomLeft: 14, topRight: 14, bottomRight: 14 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .stateStyles({
            pressed: {
              .scale({ x: 0.97, y: 0.97 })
              .backgroundColor('rgba(255,255,255,0.08)')
            }
          })
          .animation({ duration: 200, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => {
            this.onRailTap(item.panel)
          })
      }, (item: ShellAction) => item.panel)
    }
      .width(this.drawerWidth())
      .padding({ top: 4, bottom: 10, left: 8, right: 8 })
      .backgroundColor(this.panelIdleGlass ? 'rgba(10, 14, 26, 0.52)' : 'rgba(18, 22, 36, 0.78)')
      .backdropBlur(this.panelIdleGlass ? 42 : 30)
      .border({ width: 0.5, color: this.panelIdleGlass ? 'rgba(91, 147, 191, 0.16)' : 'rgba(255, 255, 255, 0.10)' })
      .borderRadius(28)
      .shadow({ radius: 30, color: 'rgba(0, 0, 0, 0.34)', offsetX: 0, offsetY: 14 })
      .opacity(this.panelIdleOpacity)
      .scale({ x: this.panelIdleOpacity < 1 ? 0.98 : 1.0, y: this.panelIdleOpacity < 1 ? 0.98 : 1.0 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: -26, y: 0 }).animation({ duration: 420, curve: curves.springMotion(0.5, 0.82) })),
        TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
          .combine(TransitionEffect.translate({ x: -18, y: 0 }).animation({ duration: 200, curve: Curve.EaseIn }))
      ))
  }

  @Builder
  compactMoreDrawer() {
    Column() {
      Row() {
        Text(I18n.t('c_more_functions'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E5FFFFFF')
          .layoutWeight(1)
        this.compactQuickButton('close', true, () => {
          this.toggleDrawer()
        })
      }
        .width('100%')
        .padding({ left: 14, right: 2, top: 6, bottom: 6 })

      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.compactDrawerActions, (item: ShellAction) => {
            Row({ space: 10 }) {
              // 图标背景圆
              Stack() {
                Circle()
                  .width(30)
                  .height(30)
                  .fill(this.activePanel === item.panel && this.panelVisible ? 'rgba(91, 147, 191, 0.26)' : 'rgba(255, 255, 255, 0.06)')
                Image(this.getIcon(item.icon, this.activePanel === item.panel && this.panelVisible))
                  .width(17)
                  .height(17)
                  .fillColor(this.activePanel === item.panel && this.panelVisible ? '#7FB3DC' : this.nmText())
              }
                .width(30)
                .height(30)
              Text(item.label)
                .fontSize(14)
                .fontWeight(this.activePanel === item.panel && this.panelVisible ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.activePanel === item.panel && this.panelVisible ? '#B8E4FF' : this.nmText())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
              .height(42)
              .width('100%')
              .padding({ left: 10, right: 10 })
              .borderRadius(12)
              .backgroundColor(this.activePanel === item.panel && this.panelVisible ? 'rgba(91, 147, 191, 0.15)' : 'rgba(255,255,255,0.03)')
              .border({
                width: { left: this.activePanel === item.panel && this.panelVisible ? 2.5 : 0, right: 0, top: 0, bottom: 0 },
                color: this.activePanel === item.panel && this.panelVisible ? '#5B93BF' : 'transparent'
              })
              .borderRadius({ topLeft: 12, bottomLeft: 12, topRight: 12, bottomRight: 12 })
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .stateStyles({
                pressed: {
                  .scale({ x: 0.97, y: 0.97 })
                  .backgroundColor('rgba(255,255,255,0.08)')
                }
              })
              .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
              .onClick(() => {
                if (item.panel === 'gyro') {
                  this.toggleGyroscope(!this.gyroscopeEnabled)
                  this.flashHint(this.gyroscopeEnabled ? '陀螺仪：开' : '陀螺仪：关')
                  return
                }
                this.drawerOpen = false
                this.onRailTap(item.panel)
              })
          }, (item: ShellAction) => item.icon + '/' + item.panel)
        }
          .width('100%')
          .padding({ bottom: 14 })
      }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width(this.isFoldHoverLayout ? '42%' : '64%')
      .height(this.compactPanelHeight())
      .padding({ top: 8, left: 8, right: 8, bottom: 8 })
      .backgroundColor(this.panelIdleGlass ? 'rgba(10, 14, 26, 0.55)' : 'rgba(18, 22, 36, 0.82)')
      .backdropBlur(this.panelIdleGlass ? 45 : 34)
      .border({ width: 0.5, color: this.panelIdleGlass ? 'rgba(91, 147, 191, 0.18)' : 'rgba(255, 255, 255, 0.10)' })
      .borderRadius(28)
      .shadow({ radius: 28, color: 'rgba(0, 0, 0, 0.34)', offsetX: 0, offsetY: 14 })
      .margin({ right: this.isFoldHoverLayout ? 34 : 18, bottom: 10 })
      .alignSelf(ItemAlign.End)
      .hitTestBehavior(HitTestMode.Default)
      .opacity(this.panelIdleOpacity)
      .scale({ x: this.panelIdleOpacity < 1 ? 0.98 : 1.0, y: this.panelIdleOpacity < 1 ? 0.98 : 1.0 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 8, y: 0 }).animation({ duration: 240, curve: curves.springMotion(0.52, 0.86) })),
        TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
      ))
  }

  @Builder
  dockButton(item: ShellAction) {
    Column() {
      Image(this.getIcon(item.icon, this.dockActionActive(item)))
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)
        .fillColor(this.dockActionActive(item) ? '#70C8FF' : '#E5FFFFFF')
        .opacity(this.dockActionActive(item) ? 1 : 0.78)
      Text(item.label)
        .fontSize(10)
        .fontColor(this.dockActionActive(item) ? '#70C8FF' : '#99FFFFFF')
        .margin({ top: 2 })
    }
      .layoutWeight(1)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Color.Transparent)
      .borderRadius(8)
      .scale({ x: 1.0, y: 1.0 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.92, y: 0.92 })
          .backgroundColor('rgba(255, 255, 255, 0.10)')
        }
      })
      .animation({ duration: 260, curve: curves.springMotion(0.42, 0.85) })
      .onClick(() => {
        if (item.panel === 'more') {
          this.toggleDrawer()
          return
        }
        this.drawerOpen = false
        this.setPanel(item.panel)
        this.flashHint(I18n.t('msg_panel_opened'))
      })
      // 手势由原生组件处理，避免与天空触摸层冲突
  }

  @Builder
  floatingPanel() {
    Column() {
      this.panelHeader()
      Scroll() {
        Column() {
          this.panelContent()
        }
          .width('100%')
          .id('panel-content-' + this.i18nLang + '-' + this.panelContentKey.toString())
      }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
    }
      .width(this.panelWidth)
      .constraintSize({ maxHeight: this.panelMaxHeight })
      .padding({ top: 18, left: 18, right: 18, bottom: 18 })
      .backgroundColor(this.panelIdleGlass ? 'rgba(10, 14, 26, 0.55)' : 'rgba(18, 22, 36, 0.82)')
      .backdropBlur(this.panelIdleGlass ? 45 : 30)
      .border({ width: 0.5, color: this.panelIdleGlass ? 'rgba(91, 147, 191, 0.18)' : 'rgba(91, 147, 191, 0.12)' })
      .borderRadius(32)
      .shadow({ radius: 34, color: 'rgba(0, 0, 0, 0.34)', offsetX: 0, offsetY: 18 })
      .margin({ top: 28, bottom: 28 })
      .scale({ x: this.panelIdleOpacity < 1 ? 0.97 : 1.0, y: this.panelIdleOpacity < 1 ? 0.97 : 1.0 })
      .opacity(this.panelIdleOpacity)
      .animation({ duration: 480, curve: curves.springMotion(0.5, 0.92) })
  }

  @Builder
  compactPanel() {
    Column() {
      this.panelHandle()
      this.panelHeader()
      Scroll() {
        Column() {
          this.panelContent()
        }
          .width('100%')
          .padding({ bottom: 34 })
          .id('panel-content-' + this.i18nLang + '-' + this.panelContentKey.toString())
      }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
    }
      .width(this.isFoldHoverLayout ? '64%' : '94%')
      .height(this.compactPanelHeight())
      .padding({ top: 10, left: 16, right: 16, bottom: 14 })
      .backgroundColor(this.panelIdleGlass ? 'rgba(10, 14, 26, 0.55)' : 'rgba(18, 22, 36, 0.82)')
      .backdropBlur(this.panelIdleGlass ? 45 : 30)
      .border({ width: 0.5, color: this.panelIdleGlass ? 'rgba(91, 147, 191, 0.18)' : 'rgba(91, 147, 191, 0.12)' })
      .borderRadius(32)
      .shadow({ radius: 30, color: 'rgba(0, 0, 0, 0.32)', offsetX: 0, offsetY: 14 })
      .margin({ bottom: 10 })
      .hitTestBehavior(HitTestMode.Default)
      .alignSelf(ItemAlign.Center)
      .scale({ x: this.panelIdleOpacity < 1 ? 0.98 : 1.0, y: this.panelIdleOpacity < 1 ? 0.98 : 1.0 })
      .opacity(this.panelIdleOpacity)
      .animation({ duration: 480, curve: curves.springMotion(0.5, 0.92) })
  }

  @Builder
  panelHandle() {
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(58)
        .height(5)
        .backgroundColor('rgba(255, 255, 255, 0.30)')
        .borderRadius(3)
    }
      .width('100%')
      .height(28)
      .alignSelf(ItemAlign.Center)
      .margin({ bottom: 2 })
      .gesture(
        PanGesture()
          .onActionUpdate((event: GestureEvent) => {
            this.updateCompactPanelDrag(event.offsetY)
          })
          .onActionEnd(() => {
            this.settleCompactPanelDrag()
          })
      )
  }

  @Builder
  panelHeader() {
    Row() {
      Column() {
        Text(this.panelTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E5FFFFFF')
        if (this.panelSubtitle().length > 0) {
          Text(this.panelSubtitle())
            .fontSize(11)
            .fontColor('#99FFFFFF')
            .margin({ top: 3 })
        }
      }
      Blank()
      Row() {
        Image($r('app.media.ic_close'))
          .width(18)
          .height(18)
          .fillColor('#E5FFFFFF')
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor('rgba(255, 255, 255, 0.06)')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.closePanel(true)
        this.resetPanelIdle()
      })
      .margin({ right: 6 })
    }
      .width('100%')
      .margin({ bottom: 14 })
  }

  @Builder
  smallRoundButton(label: ResourceStr, action: () => void) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#99FFFFFF')
    }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('rgba(255, 255, 255, 0.06)')
      .borderRadius(16)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.9, y: 0.9 })
          .backgroundColor('rgba(255, 255, 255, 0.14)')
        }
      })
      .animation({ duration: 220, curve: curves.springMotion(0.4, 0.85) })
      .onClick(action)
  }

  @Builder
  panelContent() {
    if (this.activePanel === 'object') {
      if (this.selectedName.length === 0) {
        Column() {
          Text(I18n.t('i0109')).fontSize(14).fontColor('#99FFFFFF').margin({ top: 20 })
          Text(I18n.t('i0110')).fontSize(12).fontColor('#CC8FB6FF').margin({ top: 6 })
        }.width('100%').height(100).justifyContent(FlexAlign.Center)
      } else {
      // 天体名称突出显示
      Row() {
        Text(this.zhNameOf(this.selectedName))
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF').layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ left: 4, right: 4, top: 2, bottom: 4 }).margin({ bottom: 2 })
      // 类型标签
      Row() {
        Text(this.zhType(this.selectedType))
          .fontSize(11).fontColor('#7FB3DC')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor('rgba(91, 147, 191, 0.15)').borderRadius(6)
        Blank()
        Text(this.selectedStatus === 'Selected' ? this.trackStatusZh(this.trackingText) : this.selectedStatusZh(this.selectedStatus))
          .fontSize(11).fontColor('#99FFFFFF')
      }.width('100%').padding({ left: 4, right: 4 }).height(20).margin({ bottom: 8 })

      // 直接绑定 @State（不要经 infoRow 的 @Builder 参数，参数按值捕获会导致不刷新，详见上方注释）
      if (this.selectedMagnitude.length > 0) {
        Row() {
          Text(I18n.t('i0007')).fontSize(12).fontColor('#99FFFFFF').width(72)
          Text(this.selectedMagnitude).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(28).width('100%').padding({ left: 10, right: 10 })
      }
      if (this.selectedCoordEq.length > 0) {
        Row() {
          Text(I18n.t('i0008')).fontSize(12).fontColor('#99FFFFFF').width(72)
          Text(this.selectedCoordEq).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(28).width('100%').padding({ left: 10, right: 10 })
      }
      if (this.selectedCoordAlt.length > 0) {
        Row() {
          Text(I18n.t('i0009')).fontSize(12).fontColor('#99FFFFFF').width(72)
          Text(this.selectedCoordAlt).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(28).width('100%').padding({ left: 10, right: 10 })
      }
      if (this.selectedConstellation.length > 0) {
        Row() {
          Text(I18n.t('i0010')).fontSize(12).fontColor('#99FFFFFF').width(72)
          Text(this.zhNameOf(this.selectedConstellation)).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(28).width('100%').padding({ left: 10, right: 10 })
      }
      if (this.selectedDistance.length > 0) {
        Row() {
          Text(I18n.t('i0011')).fontSize(12).fontColor('#99FFFFFF').width(72)
          Text(this.selectedDistance).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(28).width('100%').padding({ left: 10, right: 10 })
      }
      if (this.selectedInfo.length > 0) {
        Text(this.selectedInfo)
          .fontSize(12)
          .fontColor('#99FFFFFF')
          .lineHeight(18)
          .width('100%')
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 10, right: 10, top: 9, bottom: 9 })
          .backgroundColor('rgba(107, 163, 214, 0.12)')
          .border({ width: 1, color: this.nmBorder() })
          .borderRadius(14)
          .margin({ top: 8, bottom: 8 })
      }
      Row() {
        Button(this.observingList.includes(this.selectedName) ? I18n.t('s0739') : I18n.t('s0738'))
          .fontSize(13).fontColor("#E5FFFFFF").backgroundColor("rgba(107,163,214,0.25)")
          .borderRadius(12).height(36).layoutWeight(1)
          .onClick(() => {
            const idx = this.observingList.indexOf(this.selectedName)
            if (idx >= 0) {
              this.observingList.splice(idx, 1)
              this.flashHint(I18n.t('i0079'))
            } else {
              this.observingList.push(this.selectedName)
              this.flashHint(I18n.t('i0080'))
            }
            AppStorage.setOrCreate("observingList", JSON.stringify(this.observingList))
          })
      }
      .width("100%").margin({ top: 4, bottom: 4 })
	      this.quickChips([{ id: 'refresh', label: I18n.t('s0721') }, { id: 'center', label: I18n.t('s0741') }, { id: 'untrack', label: I18n.t('s0742') }])
      Row({ space: 6 }) {
        Button(I18n.t('i0134')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionGoto_ReSelect_Last_Selected_Object') })
        Button(I18n.t('s0760')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.speakSelectedObject() })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 4, bottom: 4 })
      if (this.speechStatus.length > 0) {
        Text(this.speechStatus).fontSize(10).fontColor('#FFAA00').width('100%').padding({ left: 4, right: 4 })
      }
		      if (!OFFLINE_APPGALLERY_BUILD) {
		        this.lx200ObjectControls()
		      }
      } // end object selectedName else
    } else if (this.activePanel === 'time') {
      // 直接绑定 @State：不能走 infoRow(@Builder)，其简单类型参数按值捕获，
      // observationTimeText/timeRateText 变化不会触发 Builder 重建（表现为数值钉死不动）
      Row() {
        Text(I18n.t('i0054')).fontSize(11).fontColor('#99FFFFFF').width(64).textAlign(TextAlign.Start)
        Text(this.observationTimeText)
          .fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ left: 10, right: 10, top: 3, bottom: 3 })
      Row() {
        Text(I18n.t('i0055')).fontSize(11).fontColor('#99FFFFFF').width(64).textAlign(TextAlign.Start)
        Text(this.timeRateText)
          .fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ left: 10, right: 10, top: 3, bottom: 3 })
      Row() {
        Text('恒星时').fontSize(11).fontColor('#99FFFFFF').width(64).textAlign(TextAlign.Start)
        Text(this.siderealTimeText)
          .fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ left: 10, right: 10, top: 3, bottom: 3 })
      Text('恒星时 = 此刻正好在你头顶中天的那条赤经线，用来判断某个天体现在转到哪儿了。')
        .fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 2 })
      // 时间控制按钮：[倒带][现在][停止][实时][快进][超快]
      this.timeSpeedChips()
      // Sky Guide 风格时间拖动滑块（-365天 ~ +365天）
      this.timeScrubberSlider()
      this.quickChips([{ id: '+12h', label: '+12h' }, { id: '-12h', label: '-12h' }])
      // 观测辅助：夜视模式 / 大气折射
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 8, bottom: 4 })
      Row() {
        Column({ space: 1 }) {
          Text('夜视模式').fontSize(12).fontColor(this.nmText()).width('100%')
          Text('整个界面转成红光，夜里看不刺眼、也不影响眼睛适应黑暗').fontSize(9).fontColor(this.nmSub()).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.nightModeOn })
          .onChange((v: boolean) => {
            this.nightModeOn = v
            this.nightMode = v
            this.persistNightMode()
            this.callNative('setNightMode', v ? 'true' : 'false')
          })
      }.width('100%').padding({ left: 10, right: 10, top: 4, bottom: 4 })
      Row() {
        Column({ space: 1 }) {
          Text('大气折射').fontSize(12).fontColor(this.nmText()).width('100%')
          Text('空气会把贴近地平线的天体"抬高"一点，开启后显示的是肉眼实际看到的位置').fontSize(9).fontColor(this.nmSub()).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.refractionOn })
          .onChange((v: boolean) => {
            this.applyAtmosphere(v ? 1013 : 0, this.atmoTemperature, this.atmoExtinction)
          })
      }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 4 })
      Row() {
        Text('气压').fontSize(11).fontColor(this.nmSub()).width(56)
        Slider({ value: this.atmoPressure, min: 0, max: 1100, step: 5 })
          .layoutWeight(1)
          .onChange((v: number) => { this.applyAtmosphere(v, this.atmoTemperature, this.atmoExtinction) })
        Text(this.atmoPressure.toFixed(0) + ' mbar').fontSize(10).fontColor(this.nmSub()).width(72).textAlign(TextAlign.End)
      }.width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text('气温').fontSize(11).fontColor(this.nmSub()).width(56)
        Slider({ value: this.atmoTemperature, min: -40, max: 50, step: 1 })
          .layoutWeight(1)
          .onChange((v: number) => { this.applyAtmosphere(this.atmoPressure, v, this.atmoExtinction) })
        Text(this.atmoTemperature.toFixed(0) + ' °C').fontSize(10).fontColor(this.nmSub()).width(72).textAlign(TextAlign.End)
      }.width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text('消光').fontSize(11).fontColor(this.nmSub()).width(56)
        Slider({ value: this.atmoExtinction, min: 0, max: 1, step: 0.01 })
          .layoutWeight(1)
          .onChange((v: number) => { this.applyAtmosphere(this.atmoPressure, this.atmoTemperature, v) })
        Text(this.atmoExtinction.toFixed(2)).fontSize(10).fontColor(this.nmSub()).width(72).textAlign(TextAlign.End)
      }.width('100%').padding({ left: 10, right: 10 })
      Text('消光越大，越靠近地平线的星星被大气挡得越暗（城市雾霾天可调高）。')
        .fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      // 天文事件快捷跳转
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text(I18n.t('i0111')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row({ space: 6 }) {
        Button(I18n.t('i0146')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_Rising') })
        Button(I18n.t('i0147')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_Setting') })
        Button(I18n.t('i0148')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_Transit') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button(I18n.t('i0149')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionToday_Rising') })
        Button(I18n.t('i0150')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionToday_Setting') })
        Button(I18n.t('i0151')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionToday_Transit') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button(I18n.t('i0152')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_Rising') })
        Button(I18n.t('i0153')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_Setting') })
        Button(I18n.t('i0154')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_Transit') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button(I18n.t('i0155')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_MorningTwilight') })
        Button(I18n.t('i0156')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_EveningTwilight') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button(I18n.t('i0157')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_MorningTwilight') })
        Button(I18n.t('i0158')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_EveningTwilight') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 二分二至快捷跳转
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 6, bottom: 4 })
      Row() {
        Text(I18n.t('i0112')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row({ space: 6 }) {
        Button(I18n.t('i0159')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_March_Equinox') })
        Button(I18n.t('i0160')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_June_Solstice') })
        Button(I18n.t('i0161')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_September_Equinox') })
        Button(I18n.t('i0162')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_December_Solstice') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button(I18n.t('i0163')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_March_Equinox') })
        Button(I18n.t('i0164')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_June_Solstice') })
        Button(I18n.t('i0165')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_September_Equinox') })
        Button(I18n.t('i0166')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_December_Solstice') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 天文时间单位跳转
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 6, bottom: 4 })
      Row() {
        Text(I18n.t('i0113')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      // 恒星时间
      Row({ space: 4 }) {
        Button(I18n.t('i0173')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Sidereal_Day') })
        Button(I18n.t('i0174')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Sidereal_Day') })
        Button(I18n.t('i0175')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Sidereal_Year') })
        Button(I18n.t('i0176')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Sidereal_Year') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 月周期
      Row({ space: 4 }) {
        Button(I18n.t('i0177')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Synodic_Month') })
        Button(I18n.t('i0178')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Synodic_Month') })
        Button(I18n.t('i0179')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Saros') })
        Button(I18n.t('i0180')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Saros') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 回归年/儒略年
      Row({ space: 4 }) {
        Button(I18n.t('i0181')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Tropical_Year') })
        Button(I18n.t('i0182')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Tropical_Year') })
        Button(I18n.t('i0183')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Julian_Year') })
        Button(I18n.t('i0184')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Julian_Year') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 日历月/年
      Row({ space: 4 }) {
        Button(I18n.t('i0185')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Month') })
        Button(I18n.t('i0186')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Calendar_Month') })
        Button(I18n.t('i0187')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Year') })
        Button(I18n.t('i0188')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Calendar_Year') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 更多周期
      Row({ space: 4 }) {
        Button(I18n.t('i0189')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Anomalistic_Month') })
        Button(I18n.t('i0190')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Draconic_Month') })
        Button(I18n.t('i0191')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Metonic_Cycle') })
        Button(I18n.t('i0192')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Inex') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 4 }) {
        Button(I18n.t('i0193')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Gaussian_Year') })
        Button(I18n.t('i0194')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Decade') })
        Button(I18n.t('i0195')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Century') })
        Button(I18n.t('i0196')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Julian_Century') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 滚动选择日期
      Row() {
        Text(I18n.t('i0012')).fontSize(13).fontColor(this.nmSub()).width(72)
        Button(this.manualYear + '年' + this.manualMonth + '月' + this.manualDay + '日')
          .fontSize(14).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(8).height(36).layoutWeight(1)
          .onClick(() => {
            this.pickedDate = new Date(this.manualYear, this.manualMonth - 1, this.manualDay)
            this.getUIContext().showDatePickerDialog({
              start: new Date('1900-01-01'),
              end: new Date('2100-12-31'),
              selected: this.pickedDate,
              onAccept: (value: DatePickerResult) => {
                this.manualYear = value.year ?? this.manualYear
                this.manualMonth = (value.month ?? (this.manualMonth - 1)) + 1
                this.manualDay = value.day ?? this.manualDay
              },
              onCancel: () => {}
            })
          })
      }
      .height(40).width('100%').padding({ left: 10, right: 10 })
      .backgroundColor('rgba(255,255,255,0.045)').borderRadius(12).margin({ top: 4, bottom: 4 })
      // 滚动选择时间
      Row() {
        Text(I18n.t('i0013')).fontSize(13).fontColor(this.nmSub()).width(72)
        Button(String(this.manualHour).padStart(2, '0') + ':' + String(this.manualMinute).padStart(2, '0'))
          .fontSize(14).fontColor(this.nmText()).backgroundColor(this.nmInput())
          .borderRadius(8).height(36).layoutWeight(1)
          .onClick(() => {
            this.pickedTime = new Date(2000, 0, 1, this.manualHour, this.manualMinute)
            this.getUIContext().showTimePickerDialog({
              selected: this.pickedTime,
              onAccept: (value: TimePickerResult) => {
                this.manualHour = value.hour ?? this.manualHour
                this.manualMinute = value.minute ?? this.manualMinute
              },
              onCancel: () => {}
            })
          })
      }
      .height(40).width('100%').padding({ left: 10, right: 10 })
      .backgroundColor('rgba(255,255,255,0.045)').borderRadius(12).margin({ top: 4, bottom: 4 })
      // 应用按钮
      Button(I18n.t('i0046'))
        .fontSize(14).fontColor('#FFFFFFFF').backgroundColor('#5B93BF')
        .borderRadius(12).height(40).width('100%').margin({ top: 4 })
        .onClick(() => { this.applyManualTime() })
      Button(I18n.t('i0047'))
        .fontSize(13).fontColor('#99FFFFFF').backgroundColor(this.nmBorder())
        .borderRadius(8).height(36).width('100%').margin({ top: 2 })
        .onClick(() => {
          this.syncManualTimeFromState()
          this.flashHint(I18n.t('i0081'))
        })

	    } else if (this.activePanel === 'place') {
      Row() {
        Text(I18n.t('i0014')).fontSize(12).fontColor('#99FFFFFF').width(72)
        Text(this.locationText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text(I18n.t('i0015')).fontSize(12).fontColor('#99FFFFFF').width(72)
        Text(this.coordinateText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text(I18n.t('i0016')).fontSize(12).fontColor('#99FFFFFF').width(72)
        Text(this.altitudeText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      this.locationPickerPanel()
      this.cityChipsRow()
      this.observerPlanetSection()
      // These are developer scaffolding screens, not release-ready features.
      if (!OFFLINE_APPGALLERY_BUILD) {
        this.pointingTestSection()
        this.watchGyroSection()
        this.continuationSection()
        this.tonightEventsSection()
      }
    } else if (this.activePanel === 'layers') {
      this.viewTabs()
      Scroll() {
        Column({ space: 0 }) {
          if (this.viewTab === 0) {
            this.viewSkyTab()
          } else if (this.viewTab === 1) {
            this.viewSSOTab()
          } else if (this.viewTab === 2) {
            this.viewDSOTab()
          } else if (this.viewTab === 3) {
            this.viewMarkingsTab()
          } else if (this.viewTab === 4) {
            this.viewLandscapeTab()
          } else if (this.viewTab === 5) {
            this.viewSkyCultureTab()
          } else if (this.viewTab === 6 && !OFFLINE_APPGALLERY_BUILD) {
            this.viewSurveysTab()
          } else {
            this.viewSkyTab()
          }
        }
        .width('100%')
        .animation({ duration: 280, curve: curves.springMotion(0.42, 0.85) })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(4)
      .scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'settings') {
      // 快捷设置面板
      Scroll() {
        Column({ space: 0 }) {
          Text(I18n.t('i0114')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          this.switchRow(I18n.t('s0300'), this.nightMode, 'actionShow_Night_Mode')
          this.switchRow(I18n.t('s0301'), this.equatorialMount, 'actionSwitch_Equatorial_Mount')
          this.switchRow(I18n.t('s0302'), this.autoZoomResets, 'setAutoZoomResets', 'setAutoZoomResets')
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('i0115')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          // This must use the sensor-aware row. The generic layer switch has
          // no native action for gyroscope state and only changed its visual.
          this.gyroscopeRow()
          Row() {
            Text(I18n.t('i0230')).fontSize(12).fontColor(this.nmSub()).width(72)
            Text(this.sensZh(this.gyroscopeSensitivityText)).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('i0116')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          this.switchRow(I18n.t('s0304'), this.liveMode, '')
          this.switchRow(I18n.t('set_lock_view'), this.viewLock, '', 'setViewLock')
          this.switchRow(I18n.t('set_vert_clamp'), this.verticalClamp, '', 'setVerticalClamp')
          this.switchRow(I18n.t('set_flat_horizon'), this.flatHorizon, '', 'setFlatHorizon')
          Row({ space: 6 }) {
            Button(I18n.t('i0142')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(14).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.speedDown() })
            Button(I18n.t('i0245')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmAccent())
              .borderRadius(14).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.togglePause() })
            Button(I18n.t('i0246')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(14).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.speedUp() })
          }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_fov_slider')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('set_fov_slider')).fontSize(12).fontColor(this.nmSub()).width(72)
            Text(this.fovSliderValue + '°').fontSize(14).fontColor(this.nmText()).margin({ right: 8 })
            Slider({ value: this.fovSliderValue, min: 1, max: 180, step: 1, style: SliderStyle.OutSet })
              .width('40%')
              .blockColor(this.nmAccent())
              .trackColor(this.nmBg())
              .selectedColor(this.nmAccent())
              .showSteps(false)
              .onChange((val: number) => { this.fovSliderValue = Math.round(val); this.changeFovBySlider(val) })
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_projection')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('set_projection')).fontSize(12).fontColor(this.nmSub()).width(72)
            Text(I18n.projectionName(this.currentProjection)).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })

          // 投影方式选项（中文标签 + 点击后显示说明）
          Scroll() {
            Row({ space: 6 }) {
              ForEach(PROJECTION_KEYS, (name: string) => {
                Text(I18n.projectionName(name))
                  .fontSize(11).fontColor(this.currentProjection === name ? '#FFFFFFFF' : '#99FFFFFF')
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                  .backgroundColor(this.currentProjection === name ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.05)')
                  .borderRadius(8)
                  .onClick(() => { this.setProjection(name) })
              }, (name: string) => name)
            }.padding({ left: 4, right: 4 })
          }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

          // 当前投影的功能说明（一句话帮助用户理解）
          Text(I18n.projectionDesc(this.currentProjection))
            .fontSize(10).fontColor('rgba(180,210,235,0.55)')
            .width('100%')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_language')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('i0029')).fontSize(12).fontColor(this.nmSub()).width(72)
            Text(LANGUAGE_DISPLAY[this.selectedLanguage] ?? this.selectedLanguage).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          Scroll() {
            Row({ space: 6 }) {
              ForEach(SUPPORTED_LANGUAGES, (lang: string) => {
                Text(LANGUAGE_DISPLAY[lang] ?? lang)
                  .fontSize(11).fontColor(this.selectedLanguage === lang ? '#FFFFFFFF' : '#99FFFFFF')
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                  .backgroundColor(this.selectedLanguage === lang ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.05)')
                  .borderRadius(8)
                  .onClick(() => { this.setLanguage(lang) })
              }, (lang: string) => lang)
            }.padding({ left: 4, right: 4 })
          }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_sky_culture')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('i0035')).fontSize(12).fontColor(this.nmSub()).width(72)
            Text(this.currentSkyCulture).fontSize(11).fontColor(this.nmText()).layoutWeight(1).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          if (this.skyCultures.length > 0) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.skyCultures, (culture: string) => {
                  Text(culture)
                    .fontSize(11).fontColor(this.currentSkyCulture === culture ? '#FFFFFFFF' : '#99FFFFFF')
                    .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                    .backgroundColor(this.currentSkyCulture === culture ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.05)')
                    .borderRadius(8)
                    .onClick(() => { this.setSkyCulture(culture) })
                }, (culture: string) => culture)
              }.padding({ left: 4, right: 4 })
            }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          }
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_distance_units')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('i0029')).fontSize(12).fontColor(this.nmSub()).width(72)
            Row({ space: 6 }) {
              Text(I18n.t('unit_km'))
                .fontSize(11).fontColor(this.useMetricUnits ? '#FFFFFFFF' : '#99FFFFFF')
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.useMetricUnits ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.05)')
                .borderRadius(8)
                .onClick(() => {
                  this.useMetricUnits = true
                  this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=true', () => {})
                })
              Text(I18n.t('unit_mile'))
                .fontSize(11).fontColor(!this.useMetricUnits ? '#FFFFFFFF' : '#99FFFFFF')
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(!this.useMetricUnits ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.05)')
                .borderRadius(8)
                .onClick(() => {
                  this.useMetricUnits = false
                  this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=false', () => {})
                })
            }
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text('隐私').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          Button('撤回隐私同意')
            .fontSize(13).fontColor(this.nmText()).backgroundColor(this.nmBg())
            .borderRadius(8).height(38).width('100%')
            .onClick(() => {
              try {
                privacyManager.disableService()
                // Revocation must take effect immediately: end this Ability so the next
                // launch enters the official Privacy Manager flow before Qt is started.
                // Do not manually terminate Qt/native code here.
                const context = this.getUIContext().getHostContext() as common.UIAbilityContext
                void context.terminateSelf().catch((err: Error) => {
                  hilog.error(0x0000, 'StellariumArkUI', 'Failed to terminate after privacy revocation: %{public}s', JSON.stringify(err))
                })
              } catch (err) {
                hilog.error(0x0000, 'StellariumArkUI', 'Failed to revoke privacy consent: %{public}s', JSON.stringify(err))
                this.flashHint('撤回隐私同意失败')
              }
            })
        }.width('100%')
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'search') {
      // 搜索优先，分类与推荐均为可横向滚动的原生标签，避免窄屏挤压和截断。
      Column() { this.centerSearchBar() }
        .width('100%')
        .padding({ left: 2, right: 2 })
        .margin({ top: 2, bottom: 12 })
      if (this.searchText.trim().length > 0) {
        Column({ space: 4 }) {
          Row() {
            Text('搜索结果').fontSize(11).fontColor(this.nmSub()).layoutWeight(1)
            Text(this.searchSuggestions.length > 0 ? this.searchSuggestions.length.toString() + ' 个候选' : '无候选')
              .fontSize(10).fontColor(this.nmSub())
          }.width('100%').padding({ left: 4, right: 4 })
          Scroll() {
            Column({ space: 4 }) {
              ForEach(this.searchSuggestions, (item: SearchSug) => {
                Row() {
                  Image(this.getIcon('search', false)).width(16).height(16).fillColor('#7FB3DC').margin({ right: 10 })
                  Column({ space: 1 }) {
                    Text(item.zh).fontSize(14).fontColor(this.nmText()).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (this.celestialSubtitle(item.zh, item.en).length > 0) {
                      Text(this.celestialSubtitle(item.zh, item.en)).fontSize(10).fontColor(this.nmSub()).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }
                  .width('100%').height(52).padding({ left: 12, right: 12 })
                  .backgroundColor(this.nmBg()).borderRadius(10)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => this.selectSearchSuggestion(item))
              }, (item: SearchSug) => item.en)
              if (this.searchSuggestions.length === 0) {
                Text('没有匹配的天体，按回车可直接搜索。').fontSize(12).fontColor(this.nmSub()).width('100%').padding({ left: 4, top: 8, bottom: 8 })
              }
            }.width('100%')
          }.width('100%').height(this.searchSuggestions.length > 0 ? 216 : 48).scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto)
        }
          .width('100%').padding(8).backgroundColor(this.nmBg()).borderRadius(10)
      } else {
        Text('浏览分类').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
        Scroll() {
          Row({ space: 8 }) {
            ForEach([
              { code: 'planet', label: I18n.t('i0103') },
              { code: 'moon', label: '卫星' },
              { code: 'star', label: I18n.t('i0104') },
              { code: 'variable', label: '变星' },
              { code: 'comet', label: '彗星' },
              { code: 'asteroid', label: '小行星' },
              { code: 'constellation', label: '星座' },
              { code: 'galaxy', label: '星系' },
              { code: 'cluster', label: '星团' },
              { code: 'nebula', label: '星云' },
              { code: 'messier', label: '梅西耶天体' },
            ] as CatOption[], (cat: CatOption) => {
              Text(cat.label)
                .fontSize(13).fontColor(this.searchCategory === cat.code ? '#8FD3FF' : this.nmSub())
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .backgroundColor(Color.Transparent)
                .border({ width: { bottom: 2 }, color: this.searchCategory === cat.code ? '#5B93BF' : Color.Transparent })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => this.loadCategoryObjects(cat.code))
            }, (cat: CatOption) => cat.code)
          }.padding({ left: 2, right: 12 })
        }.width('100%').height(42).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        Row() {
          Text('目录天体').fontSize(11).fontColor(this.nmSub()).layoutWeight(1)
          Text(this.categoryLoadFailed ? '读取失败，点击重试' :
            (this.categoryLoading ? (this.categoryLoadedCount > 0 ? '已加载 ' + this.categoryLoadedCount + ' 个，继续读取' : '正在读取目录') :
              (this.categoryObjectCount > 0 ? '已加载 ' + this.categoryLoadedCount + ' / ' + this.categoryObjectCount + ' 个' : '目录为空')))
            .fontSize(10).fontColor(this.nmSub())
            .onClick(() => { if (this.categoryLoadFailed) { this.loadCategoryObjects(this.searchCategory) } })
        }.width('100%').padding({ left: 2, right: 2 }).margin({ top: 10, bottom: 6 })
        Scroll() {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.categoryObjects, (item: NameItem) => {
              Column({ space: 1 }) {
                Text(item.zh ?? item.name ?? '')
                  .fontSize(12).fontColor(this.nmText()).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (item.subtitle && item.subtitle.length > 0) {
                  Text(item.subtitle).fontSize(9).fontColor(this.nmSub()).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
                .width('49%').height(52).alignItems(HorizontalAlign.Start)
                .padding({ left: 10, right: 8, top: 6, bottom: 5 })
                .backgroundColor(this.nmBg()).borderRadius(6)
                .margin({ bottom: 6 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => {
                  if (this.searchCategory === 'constellation') {
                    this.openConstellationGuide(item.name ?? '', this.categoryModuleId)
                  } else {
                    this.searchObject(item.name ?? '', this.categoryModuleId)
                  }
                })
            }, (item: NameItem) => this.searchCategory + '/' + item.name)
            if (this.categoryLoading && this.categoryObjects.length > 0) {
              Text('正在加载更多').fontSize(11).fontColor(this.nmSub()).padding({ left: 12, right: 12, top: 8, bottom: 8 })
            } else if (this.categoryHasMore) {
              Text('继续向下浏览').fontSize(11).fontColor(this.nmSub()).padding({ left: 12, right: 12, top: 8, bottom: 8 })
            }
          }.width('100%').padding({ left: 2, right: 6 })
        }.width('100%').height(168).scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto)
          .onReachEnd(() => { this.loadMoreCategoryObjects() })
      }

      // 今夜星座快速导航（15 个常见星座，点击搜索定位）
      Row() {
        Text(I18n.t('constellation_chips_title')).fontSize(10).fontColor(this.nmSub()).width(52)
        Scroll() {
          Row({ space: 4 }) {
            ForEach([
              'Orion', 'Ursa Major', 'Cassiopeia', 'Scorpius', 'Leo',
              'Gemini', 'Taurus', 'Cygnus', 'Lyra', 'Aquila',
              'Sagittarius', 'Virgo', 'Canis Major', 'Andromeda', 'Pegasus'
            ] as string[], (c: string) => {
              Text(this.zhNameOf(c)).fontSize(11).fontColor(this.nmText()).padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(this.nmBg()).borderRadius(12)
                .onClick(() => this.openConstellationGuide(c))
            }, (c: string) => c)
          }.padding({ left: 2 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
      }.width('100%').padding({ left: 10, right: 10 }).margin({ top: 6 })

      // RA/Dec 坐标跳转
      Row() {
        Text(I18n.t('s_coord_input')).fontSize(12).fontColor(this.nmSub()).width(72)
        Text(I18n.t('s_coord_format_hint')).fontSize(10).fontColor('#66FFFFFF').layoutWeight(1).textAlign(TextAlign.End)
      }
      .height(24).width('100%').padding({ left: 10, right: 10 }).margin({ top: 8 })
      Row({ space: 6 }) {
        TextInput({ text: this.coordInputRA, placeholder: 'RA (5.5 / 5h30m)' })
          .height(36).layoutWeight(1).fontSize(13).fontColor('#E5FFFFFF')
          .placeholderColor(this.nmSub())
          .backgroundColor(this.nmInput())
          .border({ width: 1, color: 'rgba(214, 238, 255, 0.16)' })
          .borderRadius(8)
          .onChange((v: string) => { this.coordInputRA = v })
        TextInput({ text: this.coordInputDec, placeholder: 'Dec (+45.5 / -30d15m)' })
          .height(36).layoutWeight(1).fontSize(13).fontColor('#E5FFFFFF')
          .placeholderColor(this.nmSub())
          .backgroundColor(this.nmInput())
          .border({ width: 1, color: 'rgba(214, 238, 255, 0.16)' })
          .borderRadius(8)
          .onChange((v: string) => { this.coordInputDec = v })
        Button(I18n.t('s_coord_go'))
          .height(36).fontSize(13).fontColor('#FFFFFF').backgroundColor('#5B93BF')
          .borderRadius(8)
          .padding({ left: 14, right: 14 })
          .onClick(() => { this.goToCoordinates() })
      }
      .width('100%').padding({ left: 10, right: 10 })

    } else if (this.activePanel === 'config') {
      // Configuration 面板
      Row({ space: 2 }) {
        ForEach([
          { label: I18n.t('c0000'), id: 0 },
          { label: I18n.t('c0001'), id: 1 },
          { label: I18n.t('c0002'), id: 2 },
          { label: I18n.t('c0003'), id: 3 },
        ] as TabItem[], (tab: TabItem) => {
          Text(tab.label)
            .fontSize(10)
            .fontColor(this.configTab === tab.id ? '#F4FAFF' : '#C8D4E2')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.configTab === tab.id ? '#397EAE' : 'rgba(255,255,255,0.09)')
            .borderRadius(6)
            .scale({ x: this.configTab === tab.id ? 1.06 : 1.0, y: this.configTab === tab.id ? 1.06 : 1.0 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .animation({ duration: 220, curve: curves.springMotion(0.5, 1.0) })
            .onClick(() => { this.configTab = tab.id })
        }, (tab: TabItem, index: number) => tab.id.toString())
      }.width('100%').padding({ left: 2, right: 2 }).margin({ top: 4, bottom: 8 }).id('config-tabs-' + this.i18nLang)
      Scroll() {
        Column({ space: 0 }) {
          if (this.configTab === 0) {
            // Main
            this.languageRow()
            Row() {
              Text(I18n.t('set_distance_units')).fontSize(12).fontColor(this.nmSub()).width(72)
              Row({ space: 6 }) {
                Text(I18n.t('unit_km'))
                  .fontSize(11).fontColor(this.useMetricUnits ? '#F4FAFF' : '#C8D4E2')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(this.useMetricUnits ? '#5B93BF' : 'rgba(255,255,255,0.06)')
                  .borderRadius(8)
                  .onClick(() => {
                    this.useMetricUnits = true
                    this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=true', () => {})
                  })
                Text(I18n.t('unit_mile'))
                  .fontSize(11).fontColor(!this.useMetricUnits ? '#F4FAFF' : '#C8D4E2')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(!this.useMetricUnits ? '#5B93BF' : 'rgba(255,255,255,0.06)')
                  .borderRadius(8)
                  .onClick(() => {
                    this.useMetricUnits = false
                    this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=false', () => {})
                  })
              }
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            this.infoRow(I18n.t('s0350'), 'Stellarium 26.2 for HarmonyOS')
          } else if (this.configTab === 1) {
            // Information
            Row() {
              Text(I18n.t('i0120')).fontSize(12).fontColor(this.nmSub()).width(72)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Row({ space: 6 }) {
              Button(I18n.t('i0247')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 0 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 0; this.triggerAction('actionDisplayInfo_All') })
              Button(I18n.t('i0248')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 1 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 1; this.triggerAction('actionDisplayInfo_Default') })
              Button(I18n.t('i0249')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 2 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 2; this.triggerAction('actionDisplayInfo_Short') })
              Button(I18n.t('i0250')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 3 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 3; this.triggerAction('actionDisplayInfo_None') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
          } else if (this.configTab === 2) {
            // Extras
            this.infoRow(I18n.t('s0351'), 'Stellarium for HarmonyOS')
            this.infoRow(I18n.t('s0352'), 'OpenHarmony / HarmonyOS NEXT')
          } else if (this.configTab === 3) {
            // Time
            this.infoRow(I18n.t('s0353'), I18n.t('s0730'))
            this.infoRow(I18n.t('s0354'), 'YYYY-MM-DD')
            this.infoRow(I18n.t('s0355'), I18n.t('s0731'))
            Row() {
              Text(I18n.t('i0223')).fontSize(10).fontColor('#CC8FB6FF').width('100%').padding({ left: 2 })
            }.height(18).width('100%').margin({ top: 4 })
          } else if (this.configTab === 5) {
            // Scripts
            Row() {
              Text(I18n.t('i0122')).fontSize(12).fontColor(this.nmSub()).width(72)
              Button(I18n.t('i0252')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionStop_Script') })
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Row() {
              Text(I18n.t('i0123')).fontSize(11).fontColor(this.nmSub()).width('100%').margin({ top: 4 })
            }.height(18).width('100%')
            Scroll() {
              Column({ space: 2 }) {
                ForEach(this.scriptList, (s: string) => {
                  Column({ space: 0 }) {
                    // 第一行：中文名
                    Row() {
                      Text(this.scriptZh(s)).fontSize(11).fontColor(this.nmText())
                        .fontWeight(FontWeight.Medium).layoutWeight(1)
                      Text('▶').fontSize(9).fontColor('#7FD0FF')
                    }
                    .height(28).width('100%').padding({ left: 10, right: 10 })
                    // 第二行：简短描述
                    if (this.scriptDesc(s)) {
                      Text(this.scriptDesc(s))
                        .fontSize(8).fontColor('#77FFFFFF').width('100%')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        .padding({ left: 10, right: 10, bottom: 3 })
                    }
                  }
                  .width('100%')
                  .backgroundColor(this.nmBg())
                  .borderRadius(4)
                  .onClick(() => { this.playScriptByName(s) })
                }, (s: string, index: number) => s)
              }
            }
            .width('100%').height(200).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
          } else {
            // Plugins
            Text(I18n.t('i0124')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            // 离线应用：插件列表进页即自动加载，此按钮仅作手动刷新用
            Button(I18n.t('act_refresh')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadPluginList() })
            if (this.pluginList.length === 0) {
              Text(I18n.t('msg_loading')).fontSize(11).fontColor(this.nmSub())
                .width('100%').margin({ top: 10 })
            }
            Scroll() {
              Column({ space: 2 }) {
                ForEach(this.pluginList, (pl: PluginItem) => {
                  Column({ space: 0 }) {
                    // 第一行：中文名 + 开关
                    Row() {
                      Text(this.pluginZh(pl.name)).fontSize(12).fontColor(this.nmText())
                        .fontWeight(FontWeight.Medium).layoutWeight(1)
                      Toggle({ type: ToggleType.Switch, isOn: pl.loaded })
                        .width(40).height(22)
                        .onChange((val: boolean) => {
                          this.togglePlugin(pl.id, !val)
                        })
                    }
                    .height(36)
                    // 第二行：功能说明（副标题）
                    if (this.pluginDesc(pl.name)) {
                      Text(this.pluginDesc(pl.name))
                        .fontSize(9).fontColor('#88FFFFFF').width('100%')
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                        .padding({ bottom: 4 })
                    }
                  }
                  .width('100%').padding({ left: 10, right: 10, top: 6, bottom: 4 })
                  .backgroundColor(this.nmBg())
                  .borderRadius(6)
                }, (pl: PluginItem) => pl.id)
              }
            }
            .width('100%').height(260).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF').id('config-content-' + this.i18nLang)
    } else if (this.activePanel === 'astro') {
      // 天文计算窗口
      Scroll() {
        Row({ space: 2 }) {
        ForEach([
          { label: I18n.t('a0005'), id: 5 },
          { label: I18n.t('a0000'), id: 0 },
          { label: I18n.t('a0001'), id: 1 },
          { label: I18n.t('a0002'), id: 2 },
          { label: I18n.t('a0003'), id: 3 },
          { label: I18n.t('a0004'), id: 4 },
          { label: I18n.t('a0006'), id: 6 },
          { label: I18n.t('a0007'), id: 7 },
          { label: I18n.t('a0008'), id: 8 },
          { label: I18n.t('a0009'), id: 9 },
        ] as TabItem[], (tab: TabItem) => {
          Text(tab.label)
            .fontSize(10)
            .fontColor(this.astroTab === tab.id ? this.nmText() : this.nmSub())
            .padding({ left: 6, right: 6, top: 4, bottom: 4 })
            .backgroundColor(this.astroTab === tab.id ? this.nmAccent() : this.nmBg())
            .borderRadius(6)
            .onClick(() => { this.astroTab = tab.id; this.loadAstroTab(tab.id) })
        }, (tab: TabItem, index: number) => tab.id.toString())
        }.padding({ left: 2, right: 2 })
      }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .margin({ top: 4, bottom: 8 })
      Scroll() {
        Column({ space: 0 }) {
          if (this.astroTab === 0) {
            Text(I18n.t('i0125')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Row({ space: 4 }) {
              ForEach(['地平位置', '日心黄道', '目录天体'], (mode: string, index: number) => {
                Text(mode).fontSize(10)
                  .fontColor(this.positionMode === index ? this.nmText() : this.nmSub())
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor(this.positionMode === index ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.positionMode !== index) {
                      this.positionMode = index
                      if (index === 0) this.loadPlanetPositions()
                      else if (index === 1) this.loadHeliocentricPositions()
                      else this.loadCelestialPositions()
                    }
                  })
              }, (mode: string) => mode)
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            if (this.positionMode === 0) {
              Button(I18n.t('i0241')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.loadPlanetPositions() })
              Row() {
                Text(I18n.t('s0374')).fontSize(10).fontColor(this.nmSub()).width(60)
                Text(I18n.t('s0375')).fontSize(10).fontColor(this.nmSub()).width(50)
                Text(I18n.t('s0376')).fontSize(10).fontColor(this.nmSub()).width(50)
                Text(I18n.t('s0377')).fontSize(10).fontColor(this.nmSub()).width(40)
              }.height(20).width('100%').padding({ left: 8, right: 8 }).margin({ top: 4, bottom: 2 })
              Scroll() {
                Column({ space: 2 }) {
                  ForEach(this.planetPositions, (p: PlanetPosition) => {
                    Row() {
                      Text(this.planetZh(p.name)).fontSize(11).fontColor(this.nmText()).width(60)
                      Text(p.altitude.toFixed(1) + '°').fontSize(10).fontColor(this.nmSub()).width(50)
                      Text(p.azimuth.toFixed(1) + '°').fontSize(10).fontColor(this.nmSub()).width(50)
                      Text(p.magnitude.toFixed(1)).fontSize(10).fontColor(this.nmSub()).width(40)
                    }
                    .height(28).width('100%').padding({ left: 8, right: 8 })
                    .backgroundColor(this.nmBg())
                    .borderRadius(4)
                  }, (p: PlanetPosition, index: number) => p.name)
                }
              }
              .width('100%').height(220).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
            } else if (this.positionMode === 1) {
              Text('日心黄道坐标以太阳为中心；同心圆为距日距离的对数刻度。').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 5 })
              Row({ space: 8 }) {
                Text('已选小天体').fontSize(10).fontColor(this.nmText()).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.hecIncludeSelectedMinor })
                  .width(38).height(22)
                  .onChange((value: boolean) => { this.hecIncludeSelectedMinor = value; this.loadHeliocentricPositions() })
              }.width('100%').height(30).padding({ left: 4, right: 4 })
              Row({ space: 8 }) {
                Text('显示明亮彗星').fontSize(10).fontColor(this.nmText()).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.hecIncludeBrightComets })
                  .width(38).height(22)
                  .onChange((value: boolean) => { this.hecIncludeBrightComets = value; this.loadHeliocentricPositions() })
              }.width('100%').height(30).padding({ left: 4, right: 4 })
              if (this.hecIncludeBrightComets) {
                Row({ space: 4 }) {
                  Text('彗星星等上限').fontSize(10).fontColor(this.nmSub()).width(76)
                  ForEach([6, 9, 12], (limit: number) => {
                    Text(limit.toString()).fontSize(10)
                      .fontColor(this.hecCometMagnitudeLimit === limit ? this.nmText() : this.nmSub())
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.hecCometMagnitudeLimit === limit ? this.nmAccent() : this.nmBg())
                      .borderRadius(5)
                      .onClick(() => { this.hecCometMagnitudeLimit = limit; this.loadHeliocentricPositions() })
                  }, (limit: number) => limit.toString())
                }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 5 })
              }
              Row({ space: 8 }) {
                Button('刷新坐标').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                  .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                  .onClick(() => { this.loadHeliocentricPositions() })
                Text(this.hecTime.length > 0 ? this.fmtDateTime(this.hecTime) : '正在计算…').fontSize(9).fontColor(this.nmSub()).layoutWeight(1)
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 5 })
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(172).height(172).fill('transparent').stroke(this.nmBorder()).strokeWidth(1)
                Circle().width(112).height(112).fill('transparent').stroke(this.nmBorder()).strokeWidth(1)
                Circle().width(54).height(54).fill('transparent').stroke(this.nmBorder()).strokeWidth(1)
                Circle().width(20).height(20).fill('#E8B24B')
                Text('太阳').fontSize(8).fontColor('#201707')
                ForEach(this.hecPositions, (position: HeliocentricPosition) => {
                  Circle().width(14).height(14).fill(this.hecPointColor(position))
                    .position({ x: this.hecPointLeft(position), y: this.hecPointTop(position) })
                    .onClick(() => { this.searchObject(position.englishName) })
                }, (position: HeliocentricPosition) => position.englishName)
              }.width(200).height(200).margin({ top: 2, bottom: 7 }).backgroundColor(this.nmBg()).borderRadius(6)
              Row() {
                Text('天体').fontSize(10).fontColor(this.nmSub()).width(70)
                Text('黄纬').fontSize(10).fontColor(this.nmSub()).width(47)
                Text('黄经').fontSize(10).fontColor(this.nmSub()).width(47)
                Text('距日').fontSize(10).fontColor(this.nmSub()).layoutWeight(1)
              }.height(20).width('100%').padding({ left: 8, right: 8 })
              Scroll() {
                Column({ space: 2 }) {
                  ForEach(this.hecPositions, (position: HeliocentricPosition) => {
                    Row() {
                      Text(this.hecTitle(position)).fontSize(11).fontColor(this.nmText()).width(70).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(position.latitude.toFixed(1) + '°').fontSize(10).fontColor(this.nmSub()).width(47)
                      Text(position.longitude.toFixed(1) + '°').fontSize(10).fontColor(this.nmSub()).width(47)
                      Text(this.hecDistanceLabel(position) + ' AU').fontSize(10).fontColor(this.nmSub()).layoutWeight(1).maxLines(1)
                    }
                    .height(28).width('100%').padding({ left: 8, right: 8 })
                    .backgroundColor(this.nmBg())
                    .borderRadius(4)
                    .onClick(() => { this.searchObject(position.englishName) })
                  }, (position: HeliocentricPosition) => position.englishName)
                }
              }
              .width('100%').height(220).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
            } else {
              Text('列出当前地平线以上、满足星等条件的目录天体；按高度由高到低排列。').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 5 })
              Scroll() {
                Row({ space: 4 }) {
                  ForEach(CELESTIAL_POSITION_CATEGORIES, (category: CelestialPositionCategory) => {
                    Text(category.label).fontSize(10)
                      .fontColor(this.celestialPositionCategory === category.id ? this.nmText() : this.nmSub())
                      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                      .backgroundColor(this.celestialPositionCategory === category.id ? this.nmAccent() : this.nmBg())
                      .borderRadius(5)
                      .onClick(() => { this.celestialPositionCategory = category.id; this.loadCelestialPositions() })
                  }, (category: CelestialPositionCategory) => category.id)
                }.padding({ left: 2, right: 2 })
              }.width('100%').height(31).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
              Row({ space: 4 }) {
                Text('星等上限').fontSize(10).fontColor(this.nmSub()).width(56)
                ForEach([3, 6, 9, 12], (magnitude: number) => {
                  Text(magnitude.toString()).fontSize(10)
                    .fontColor(this.celestialPositionMagnitude === magnitude ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.celestialPositionMagnitude === magnitude ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => { this.celestialPositionMagnitude = magnitude; this.loadCelestialPositions() })
                }, (magnitude: number) => magnitude.toString())
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
              Row({ space: 8 }) {
                Text('使用地平坐标').fontSize(10).fontColor(this.nmText()).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.celestialPositionHorizontal })
                  .width(38).height(22)
                  .onChange((value: boolean) => { this.celestialPositionHorizontal = value; this.loadCelestialPositions() })
                Button('刷新').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                  .borderRadius(14).height(28).padding({ left: 9, right: 9 })
                  .onClick(() => { this.loadCelestialPositions() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 5 })
              Text(this.celestialPositionTime.length > 0 ? this.fmtDateTime(this.celestialPositionTime) : '正在计算…').fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 4 }).margin({ bottom: 4 })
              if (this.celestialPositions.length === 0) {
                Text('当前筛选条件下没有地平线以上的天体。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else {
                Scroll() {
                  Column({ space: 2 }) {
                    ForEach(this.celestialPositions, (position: CelestialPosition) => {
                      Column({ space: 1 }) {
                        Row() {
                          Text(this.celestialPositionTitle(position)).fontSize(11).fontColor(this.nmText()).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                          Text('星等 ' + position.magnitude.toFixed(1)).fontSize(10).fontColor(this.nmSub()).width(60).textAlign(TextAlign.End)
                        }.width('100%')
                        if (this.celestialPositionSubtitle(position).length > 0) {
                          Text(this.celestialPositionSubtitle(position)).fontSize(9).fontColor(this.nmSub()).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        Text((this.celestialPositionHorizontal ? '方位 ' : '赤经 ') + position.firstCoordinate + '   ' + (this.celestialPositionHorizontal ? '高度 ' : '赤纬 ') + position.secondCoordinate)
                          .fontSize(9).fontColor('#B8FFFFFF').width('100%').maxLines(1)
                        Text('地平高度 ' + position.altitude.toFixed(1) + '°   距日 ' + (position.elongation ?? 0).toFixed(1) + '°')
                          .fontSize(9).fontColor('#88FFFFFF').width('100%').maxLines(1)
                      }
                      .width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
                      .backgroundColor(this.nmBg()).borderRadius(4)
                      .onClick(() => { this.searchObject(position.englishName) })
                    }, (position: CelestialPosition) => position.englishName + position.catalogId)
                  }
                }.width('100%').height(310).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
              }
            }
          } else if (this.astroTab === 1) {
            Text(I18n.t('i0126')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text('计算对象').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach(['当前选中天体', '两个天体', '全部肉眼行星'], (label: string, mode: number) => {
                Text(label).fontSize(10)
                  .fontColor(this.ephemerisMode === mode ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                  .backgroundColor(this.ephemerisMode === mode ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => { this.ephemerisMode = mode })
              }, (label: string) => label)
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
            if (this.ephemerisMode === 0) {
              Row({ space: 8 }) {
                Column({ space: 1 }) {
                  Text('星历目标').fontSize(9).fontColor(this.nmSub())
                  Text(this.selectedName.length > 0 ? this.zhNameOf(this.selectedName) : '尚未选择天体')
                    .fontSize(11).fontColor(this.selectedName.length > 0 ? this.nmText() : this.nmSub())
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button(this.selectedName.length > 0 ? '更换天体' : '选择天体')
                  .fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                  .borderRadius(16).height(28).padding({ left: 10, right: 10 })
                  .onClick(() => { this.openEphemerisTargetPicker() })
              }.width('100%').padding({ left: 4, right: 4, top: 4, bottom: 5 })
                .backgroundColor('rgba(255, 255, 255, 0.035)').borderRadius(5).margin({ bottom: 5 })
            }
            if (this.ephemerisMode === 1) {
              Text('第一个天体').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Scroll() {
                Row({ space: 4 }) {
                  ForEach(['Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                    Text(this.planetPairBodyName(body)).fontSize(10)
                      .fontColor(this.ephemerisPrimary === body ? this.nmText() : this.nmSub())
                      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                      .backgroundColor(this.ephemerisPrimary === body ? this.nmAccent() : this.nmBg()).borderRadius(5)
                      .onClick(() => {
                        this.ephemerisPrimary = body
                        if (this.ephemerisSecondary === body) this.ephemerisSecondary = 'Sun'
                      })
                  }, (body: string) => body)
                }.padding({ left: 2, right: 2 })
              }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 4 })
              Text('第二个天体').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Scroll() {
                Row({ space: 4 }) {
                  ForEach(['Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                    if (body !== this.ephemerisPrimary) {
                      Text(this.planetPairBodyName(body)).fontSize(10)
                        .fontColor(this.ephemerisSecondary === body ? this.nmText() : this.nmSub())
                        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                        .backgroundColor(this.ephemerisSecondary === body ? this.nmAccent() : this.nmBg()).borderRadius(5)
                        .onClick(() => { this.ephemerisSecondary = body })
                    }
                  }, (body: string) => body)
                }.padding({ left: 2, right: 2 })
              }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
            }
            Text('时间范围').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach([7, 14, 31], (days: number) => {
                Text(days.toString() + ' 天')
                  .fontSize(10)
                  .fontColor(this.ephemerisDays === days ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.ephemerisDays === days ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.ephemerisDays !== days) {
                      this.ephemerisDays = days
                      this.loadEphemeris()
                    }
                  })
              }, (days: number) => days.toString())
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            Text('开始日期').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach([0, 1, 7, 30], (offsetDays: number) => {
                Text(this.ephemerisStartOptionLabel(offsetDays)).fontSize(10)
                  .fontColor(this.ephemerisStartOffsetDays === offsetDays ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.ephemerisStartOffsetDays === offsetDays ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.ephemerisStartOffsetDays !== offsetDays) {
                      this.ephemerisStartOffsetDays = offsetDays
                      this.loadEphemeris()
                    }
                  })
              }, (offsetDays: number) => offsetDays.toString())
              Button(this.ephemerisStartOffsetDays < 0 ? this.ephemerisStartOptionLabel(-1) : '指定日期').fontSize(10)
                .fontColor(this.ephemerisStartOffsetDays < 0 ? this.nmText() : this.nmSub())
                .height(26).padding({ left: 9, right: 9 })
                .backgroundColor(this.ephemerisStartOffsetDays < 0 ? this.nmAccent() : this.nmBg())
                .borderRadius(5)
                .onClick(() => { this.chooseEphemerisStartDate() })
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            Text('采样间隔').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach([1, 3, 6, 12, 24], (hours: number) => {
                Text(hours.toString() + ' 小时')
                  .fontSize(10)
                  .fontColor(this.ephemerisStepHours === hours ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.ephemerisStepHours === hours ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.ephemerisStepHours !== hours) {
                      this.ephemerisStepHours = hours
                      this.loadEphemeris()
                    }
                  })
              }, (hours: number) => hours.toString())
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            Row({ space: 6 }) {
              Button('刷新星历').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.loadEphemeris() })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
            Text(this.ephemerisMode === 0 ? '选择天体后将自动生成星历；点任一行可跳到对应时刻。' : (this.ephemerisMode === 1 ? '两个天体共用同一时间轴，便于直接比较位置和星等。' : '肉眼行星模式在地球上显示水星、金星、火星、木星和土星。')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
            if (this.ephemerisLoading) {
              Row({ space: 8 }) {
                LoadingProgress().width(22).height(22).color(this.nmAccent())
                Text('正在生成星历…').fontSize(11).fontColor(this.nmSub())
              }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
            } else if (this.ephemerisError.length > 0) {
              Text(this.ephemerisError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 8 })
            } else if (this.ephemerisData.length === 0) {
              Text('尚未生成星历。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 8 })
            } else {
              Text(this.ephemerisName + ' · 从' + this.ephemerisStartOptionLabel(this.ephemerisStartOffsetDays) + '开始，持续 ' + this.ephemerisDays.toString() + ' 天（每 ' + this.ephemerisStepHours.toString() + ' 小时）').fontSize(11).fontColor(this.nmText()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
            }
            ForEach(this.ephemerisData, (row: EphemerisRow) => {
              Column({ space: 1 }) {
                Row({ space: 8 }) {
                  Text(this.fmtEphemerisDate(row.date)).fontSize(10).fontColor(this.nmText()).width(96)
                  Text((row.bodyName !== undefined ? row.bodyName + '  ' : '') + '赤经 ' + (row.ra ?? '--')).fontSize(10).fontColor(this.nmSub()).layoutWeight(1).maxLines(1)
                }.width('100%')
                Text('赤纬 ' + (row.dec ?? '--')).fontSize(9).fontColor('#B8FFFFFF').width('100%').maxLines(1)
                Text('高度 ' + this.fmtNum(row.altitude, 1, '°')
                  + '   方位 ' + this.fmtNum(row.azimuth, 0, '°')
                  + '   星等 ' + this.fmtNum(row.magnitude, 1, ''))
                  .fontSize(9).fontColor('#88FFFFFF').width('100%').maxLines(1)
              }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 2 })
              .onClick(() => { this.jumpToEphemerisRow(row) })
            }, (row: EphemerisRow, index: number) => index.toString())
          } else if (this.astroTab === 2) {
            Text(I18n.t('i0127')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Button(I18n.t('i0239')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadRTS() })
            if (!this.hasSelectedObject()) {
              this.rtsSelectionGuide()
            } else if (this.rtsError.length > 0) {
              Text(this.rtsError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
            } else if (this.rtsData.size > 0) {
              this.infoRow(I18n.t('s0358'), this.rtsData.get('name') ?? 'N/A')
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.nmBorder())
                .margin({ top: 4, bottom: 4 })
              Text(I18n.t('s0370')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow(I18n.t('s0700'), this.jdToDateStr(this.rtsData.get('nextRiseText') ?? '0'))
              this.infoRow(I18n.t('s0701'), this.jdToDateStr(this.rtsData.get('nextTransitText') ?? '0'))
              this.infoRow(I18n.t('s0702'), this.jdToDateStr(this.rtsData.get('nextSetText') ?? '0'))
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.nmBorder())
                .margin({ top: 4, bottom: 4 })
              Text(I18n.t('s0371')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow(I18n.t('s0700'), this.jdToDateStr(this.rtsData.get('prevRiseText') ?? '0'))
              this.infoRow(I18n.t('s0701'), this.jdToDateStr(this.rtsData.get('prevTransitText') ?? '0'))
              this.infoRow(I18n.t('s0702'), this.jdToDateStr(this.rtsData.get('prevSetText') ?? '0'))
            }
            if (this.hasSelectedObject()) {
            Row({ space: 6 }) {
              Button(I18n.t('i0146')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.jumpToRts('nextRiseJD') })
              Button(I18n.t('i0148')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.jumpToRts('nextTransitJD') })
              Button(I18n.t('i0147')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.jumpToRts('nextSetJD') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
            Row()
              .width('100%').height(0.5)
              .backgroundColor(this.nmBorder())
              .margin({ top: 10, bottom: 8 })
            Text('升中天落日期表').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Text('持续时长').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Scroll() {
              Row({ space: 4 }) {
                ForEach([7, 14, 31, 62, 92, 183, 365], (days: number) => {
                  Text(this.rtsCalendarDurationLabel(days)).fontSize(10)
                  .fontColor(this.rtsCalendarDays === days ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.rtsCalendarDays === days ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.rtsCalendarDays !== days) {
                      this.rtsCalendarDays = days
                      this.markRtsCalendarForRegeneration()
                    }
                  })
                }, (days: number) => days.toString())
              }.padding({ left: 2, right: 2 })
            }.width('100%').height(30).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
            Text('开始日期').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach([0, 1, 7, 30], (offsetDays: number) => {
                Text(this.rtsCalendarStartOptionLabel(offsetDays)).fontSize(10)
                  .fontColor(this.rtsCalendarStartOffsetDays === offsetDays ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.rtsCalendarStartOffsetDays === offsetDays ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.rtsCalendarStartOffsetDays !== offsetDays) {
                      this.rtsCalendarStartOffsetDays = offsetDays
                      this.markRtsCalendarForRegeneration()
                    }
                  })
              }, (offsetDays: number) => offsetDays.toString())
              Button(this.rtsCalendarStartOffsetDays < 0 ? this.rtsCalendarStartOptionLabel(-1) : '指定日期').fontSize(10)
                .fontColor(this.rtsCalendarStartOffsetDays < 0 ? this.nmText() : this.nmSub())
                .height(26).padding({ left: 9, right: 9 })
                .backgroundColor(this.rtsCalendarStartOffsetDays < 0 ? this.nmAccent() : this.nmBg())
                .borderRadius(5)
                .onClick(() => { this.chooseRtsCalendarStartDate() })
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
            Row({ space: 6 }) {
              Button('生成日期表').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 9, right: 9 })
                .onClick(() => { this.loadRtsCalendar() })
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
            if (this.rtsCalendarLoading) {
              Row({ space: 8 }) {
                LoadingProgress().width(22).height(22).color(this.nmAccent())
                Text('正在生成升中天落日期表… ' + this.rtsCalendarProgress.toString() + '/' + this.rtsCalendarTotalDays.toString() + ' 天').fontSize(11).fontColor(this.nmSub())
              }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
            } else if (this.rtsCalendarNeedsGeneration) {
              Text('参数已更新，请点击生成日期表开始计算。').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 4 })
            } else if (this.rtsCalendarError.length > 0) {
              Text(this.rtsCalendarError).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 4 })
            } else if (this.rtsCalendarData.length > 0) {
              Text(this.rtsCalendarName + ' · 从' + this.rtsCalendarStartOptionLabel(this.rtsCalendarStartOffsetDays) + '开始，持续 ' + this.rtsCalendarDurationLabel(this.rtsCalendarDays) + '；每项按本地日期计算，点击可跳到该日中天。')
                .fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              ForEach(this.rtsCalendarData, (day: RtsCalendarDay) => {
                Column({ space: 1 }) {
                  Row() {
                    Text(this.fmtDateTime(day.date)).fontSize(10).fontColor(this.nmText()).width(94)
                    if (day.status !== undefined) {
                      Text(day.status ?? '').fontSize(10).fontColor(this.nmAccent()).layoutWeight(1)
                    } else {
                      Text('升 ' + this.fmtClock(day.rise) + '  中天 ' + this.fmtClock(day.transit) + '  落 ' + this.fmtClock(day.set))
                        .fontSize(10).fontColor(this.nmText()).layoutWeight(1).maxLines(1)
                    }
                  }.width('100%').padding({ left: 8, right: 8 })
                  if (day.status === undefined) {
                    Text('中天高度 ' + (day.transitAltitude ?? 0).toFixed(1) + '°   星等 ' + (day.magnitude ?? 0).toFixed(1)
                      + '   距日 ' + (day.solarElongation ?? 0).toFixed(1) + '°   距月 ' + (day.lunarElongation ?? 0).toFixed(1) + '°')
                      .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 }).maxLines(1)
                  }
                }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 2 })
                .onClick(() => { this.jumpToRtsCalendar(day) })
              }, (day: RtsCalendarDay, index: number) => day.date ?? index.toString())
            }
            }
          } else if (this.astroTab === 3) {
            Text(I18n.t('i0128')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text('计算对象').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Scroll() {
              Row({ space: 4 }) {
                ForEach(['all', 'Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                  Text(this.phenomenaBodyName(body)).fontSize(10)
                    .fontColor(this.phenomenaPrimary === body ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                    .backgroundColor(this.phenomenaPrimary === body ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      this.phenomenaPrimary = body
                      if (this.phenomenaTarget === body) this.phenomenaTarget = 'all'
                    })
                }, (body: string) => body)
              }.padding({ left: 2, right: 2 })
            }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
            if (this.phenomenaPrimary !== 'all') {
              Text('比较对象').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Scroll() {
                Row({ space: 4 }) {
                  ForEach(['all', 'Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                    if (body !== this.phenomenaPrimary) {
                      Text(this.phenomenaBodyName(body)).fontSize(10)
                        .fontColor(this.phenomenaTarget === body ? this.nmText() : this.nmSub())
                        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                        .backgroundColor(this.phenomenaTarget === body ? this.nmAccent() : this.nmBg())
                        .borderRadius(5)
                        .onClick(() => { this.phenomenaTarget = body })
                    }
                  }, (body: string) => body)
                }.padding({ left: 2, right: 2 })
              }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
            }
            Text('起始时段').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach(PHENOMENA_START_OPTIONS, (item: PhenomenaStartOption) => {
                Text(item.label).fontSize(10)
                  .fontColor(this.phenomenaStartOffsetMonths === item.value ? this.nmText() : this.nmSub())
                  .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                  .backgroundColor(this.phenomenaStartOffsetMonths === item.value ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => { this.phenomenaStartOffsetMonths = item.value })
              }, (item: PhenomenaStartOption) => item.value.toString())
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
            Column({ space: 5 }) {
              Text('预测范围').fontSize(10).fontColor(this.nmSub()).width('100%')
              Row({ space: 4 }) {
                ForEach([30, 90, 180, 400, 730], (days: number) => {
                  Text(days < 365 ? days.toString() + ' 天' : (days / 365).toFixed(1) + ' 年').fontSize(10)
                    .fontColor(this.phenomenaDays === days ? this.nmText() : this.nmSub())
                    .padding({ left: 7, right: 7, top: 5, bottom: 5 })
                    .backgroundColor(this.phenomenaDays === days ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => { this.phenomenaDays = days })
                }, (days: number) => days.toString())
              }
              Text('最大角距').fontSize(10).fontColor(this.nmSub()).width('100%')
              Row({ space: 4 }) {
                ForEach([1, 4, 10, 20], (degrees: number) => {
                  Text(degrees.toString() + '°').fontSize(10)
                    .fontColor(this.phenomenaMaxSeparation === degrees ? this.nmText() : this.nmSub())
                    .padding({ left: 7, right: 7, top: 5, bottom: 5 })
                    .backgroundColor(this.phenomenaMaxSeparation === degrees ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => { this.phenomenaMaxSeparation = degrees })
                }, (degrees: number) => degrees.toString())
              }
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            Text('附加天象').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              Text('冲').fontSize(10).fontColor(this.phenomenaIncludeOppositions ? this.nmText() : this.nmSub())
                .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor(this.phenomenaIncludeOppositions ? this.nmAccent() : this.nmBg()).borderRadius(5)
                .onClick(() => { this.phenomenaIncludeOppositions = !this.phenomenaIncludeOppositions })
              Text('近日点/远日点').fontSize(10).fontColor(this.phenomenaIncludePerihelionAphelion ? this.nmText() : this.nmSub())
                .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor(this.phenomenaIncludePerihelionAphelion ? this.nmAccent() : this.nmBg()).borderRadius(5)
                .onClick(() => { this.phenomenaIncludePerihelionAphelion = !this.phenomenaIncludePerihelionAphelion })
              Text('大距/方照').fontSize(10).fontColor(this.phenomenaIncludeElongationsQuadratures ? this.nmText() : this.nmSub())
                .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor(this.phenomenaIncludeElongationsQuadratures ? this.nmAccent() : this.nmBg()).borderRadius(5)
                .onClick(() => { this.phenomenaIncludeElongationsQuadratures = !this.phenomenaIncludeElongationsQuadratures })
              Text('留点').fontSize(10).fontColor(this.phenomenaIncludeStations ? this.nmText() : this.nmSub())
                .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor(this.phenomenaIncludeStations ? this.nmAccent() : this.nmBg()).borderRadius(5)
                .onClick(() => { this.phenomenaIncludeStations = !this.phenomenaIncludeStations })
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 7 })
            Row({ space: 6 }) {
              Button('计算天象').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.loadPhenomena() })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
            Text('合相按最大角距筛选；点任一结果可跳到发生时刻。').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
            if (this.phenomenaLoading) {
              Row({ space: 8 }) {
                LoadingProgress().width(22).height(22).color(this.nmAccent())
                Text('正在计算天象…').fontSize(11).fontColor(this.nmSub())
              }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
            } else if (this.phenomenaHint.length > 0) {
              Text(this.phenomenaHint).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 8 })
            } else if (this.phenomenaData.length === 0) {
              Text('尚未计算天象。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 8 })
            }
            ForEach(this.phenomenaData, (p: PhenomenonItem) => {
              Row({ space: 8 }) {
                Stack({ alignContent: Alignment.Center }) {
                  this.phenomenonRelationMark(p.type ?? '')
                }.width(52).height(44).backgroundColor(this.nmBg()).border({ width: 1, color: this.nmBorder() }).borderRadius(5)
                Column({ space: 3 }) {
                  Text(this.phenomenonCaption(p.type ?? '')).fontSize(9).fontColor(this.nmSub()).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text((p.bodyA ?? '天体') + ' 与 ' + (p.bodyB ?? '太阳'))
                    .fontSize(12).fontColor(this.nmText()).fontWeight(FontWeight.Medium).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.fmtDateTime(p.date)).fontSize(9).fontColor(this.nmSub()).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Column({ space: 3 }) {
                  Text(p.metricLabel ?? '角距').fontSize(9).fontColor(this.nmSub()).width('100%').textAlign(TextAlign.End)
                  Text(this.fmtNum(p.separation, 2, p.metricUnit ?? '°')).fontSize(11).fontColor(this.nmText()).fontWeight(FontWeight.Medium)
                    .width('100%').textAlign(TextAlign.End).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.width(84).alignItems(HorizontalAlign.End)
              }.width('100%').height(64).padding({ left: 8, right: 8, top: 5, bottom: 5 })
                .backgroundColor(this.nmBg()).border({ width: 1, color: this.nmBorder() }).borderRadius(5).margin({ bottom: 4 })
              .onClick(() => { this.jumpToPhenomenon(p) })
            }, (p: PhenomenonItem, index: number) => index.toString())
          } else if (this.astroTab === 4) {
            Text(I18n.t('i0129')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Row({ space: 8 }) {
              Column({ space: 1 }) {
                Text('曲线目标').fontSize(9).fontColor(this.nmSub())
                Text(this.graphTargetLabel()).fontSize(12).fontColor(this.selectedName.length > 0 ? this.nmText() : this.nmSub())
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button(this.selectedName.length > 0 ? '更换天体' : '选择天体')
                .fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.openGraphTargetPicker() })
            }.width('100%').padding({ left: 4, right: 4, top: 5, bottom: 5 })
              .backgroundColor(this.nmBg()).border({ width: 1, color: this.nmBorder() }).borderRadius(6).margin({ bottom: 8 })
            if (this.graphMode !== 2) {
              Text('起始日期').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([0, 1, 7, 30], (offsetDays: number) => {
                  Text(this.graphStartOptionLabel(offsetDays)).fontSize(10)
                    .fontColor(this.graphStartOffsetDays === offsetDays ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.graphStartOffsetDays === offsetDays ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.graphStartOffsetDays !== offsetDays) {
                        this.graphStartOffsetDays = offsetDays
                        this.reloadCurrentGraph()
                      }
                    })
                }, (offsetDays: number) => offsetDays.toString())
                Button(this.graphCustomStartLabel()).fontSize(10)
                  .fontColor(this.graphStartOffsetDays < 0 ? this.nmText() : this.nmSub())
                  .height(26).padding({ left: 9, right: 9 })
                  .backgroundColor(this.graphStartOffsetDays < 0 ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => { this.chooseGraphStartDate() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
            }
            Row({ space: 4 }) {
              ForEach(['高度', '方位', '全年', '月度', '月距', '双曲线'], (mode: string, index: number) => {
                Text(mode).fontSize(10)
                  .fontColor(this.graphMode === index ? this.nmText() : this.nmSub())
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor(this.graphMode === index ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.graphMode !== index) {
                      this.graphMode = index
                      if (index === 2) this.loadAnnualElevation()
                      else if (index === 3) this.loadObservabilityCalendar()
                      else if (index === 4) this.loadLunarElongation()
                      else if (index === 5) this.loadPlanetTimeSeries()
                      else this.loadAltAzCurve()
                    }
                  })
              }, (mode: string) => mode)
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
            if (this.graphMode === 0 || this.graphMode === 1) {
            Text('时间范围').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach([12, 24, 48, 72], (hours: number) => {
                Text(hours.toString() + 'h')
                  .fontSize(10)
                  .fontColor(this.altAzHours === hours ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.altAzHours === hours ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.altAzHours !== hours) {
                      this.altAzHours = hours
                      this.loadAltAzCurve()
                    }
                  })
              }, (hours: number) => hours.toString())
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            Text('采样间隔').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach([15, 30, 60], (stepMin: number) => {
                Text(stepMin.toString() + ' 分')
                  .fontSize(10)
                  .fontColor(this.altAzStepMin === stepMin ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.altAzStepMin === stepMin ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.altAzStepMin !== stepMin) {
                      this.altAzStepMin = stepMin
                      this.loadAltAzCurve()
                    }
                  })
              }, (stepMin: number) => stepMin.toString())
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            if (this.graphMode === 0) {
              Text('叠加曲线').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                Text('太阳').fontSize(10)
                  .fontColor(this.altAzShowSun ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.altAzShowSun ? '#9C6A24' : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => { this.altAzShowSun = !this.altAzShowSun; this.loadAltAzCurve() })
                Text('月亮').fontSize(10)
                  .fontColor(this.altAzShowMoon ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.altAzShowMoon ? '#657384' : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => { this.altAzShowMoon = !this.altAzShowMoon; this.loadAltAzCurve() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('显示高度不低于').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([-90, 0, 15, 30], (minimum: number) => {
                  Text(minimum === -90 ? '全部' : minimum.toString() + '°').fontSize(10)
                    .fontColor(this.altAzMinimum === minimum ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.altAzMinimum === minimum ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => { this.altAzMinimum = minimum })
                }, (minimum: number) => minimum.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            }
            Row({ space: 6 }) {
              Button(this.graphMode === 0 ? '刷新高度' : '刷新方位').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.altAzCurve = []; this.altAzError = ''; this.loadAltAzCurve() })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
            if (this.graphLoading) {
              this.graphLoadingRow('正在计算' + this.altAzRangeLabel() + '的' + (this.graphMode === 0 ? '高度' : '方位角') + '变化…')
            } else if (this.altAzError.length > 0) {
              Text(this.altAzError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              this.graphSelectionGuide(this.altAzError)
            } else if (this.altAzCurve.length === 0) {
              Text('没有可绘制的数据。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
            } else {
              Text(this.altAzName + ' · ' + this.altAzRangeLabel() + (this.graphMode === 0 ? '高度变化' : '方位角变化') + '（每 ' + this.altAzStepMin.toString() + ' 分）').fontSize(11).fontColor(this.nmText()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              Stack({ alignContent: Alignment.Center }) {
                Row() {
                  ForEach(this.altAzCurve, (r: AltAzPoint) => {
                    if (this.graphMode === 0) {
                      Row({ space: 1 }) {
                        Column().width(this.altCurveSegmentWidth()).height(this.altBarHeight(r.altitude))
                          .backgroundColor(this.altitudeCurveColor(r.altitude, this.nmAccent())).borderRadius(1)
                        if (this.altAzShowSun) {
                          Column().width(this.altCurveSegmentWidth()).height(this.altBarHeight(r.sunAltitude))
                            .backgroundColor(this.altitudeCurveColor(r.sunAltitude, '#E8B24B')).borderRadius(1)
                        }
                        if (this.altAzShowMoon) {
                          Column().width(this.altCurveSegmentWidth()).height(this.altBarHeight(r.moonAltitude))
                            .backgroundColor(this.altitudeCurveColor(r.moonAltitude, '#CCD7E5')).borderRadius(1)
                        }
                      }.width(this.altBarWidth()).height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                    } else {
                      Column().width(this.altBarWidth()).height(this.azBarHeight(r.azimuth))
                        .backgroundColor(this.nmAccent()).borderRadius(1)
                    }
                  }, (r: AltAzPoint, index: number) => index.toString())
                }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                if (this.graphMode === 0 && this.altAzMinimum <= 0) {
                  Divider().color('#66FFFFFF').strokeWidth(1).width('100%').align(this.altAzMinimum === 0 ? Alignment.Bottom : Alignment.Center)
                }
              }.width('100%').height(96).padding({ left: 6, right: 6 })
              Row() {
                Text(this.graphMode === 0 ? '现在' : '0°').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Start)
                Text(this.graphMode === 0 ? this.altAzMidpointLabel() : '180°').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Center)
                Text(this.graphMode === 0 ? '+' + this.altAzHours.toString() + 'h' : '360°').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.End)
              }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
              Text(this.graphMode === 0 ? (this.altAzMinimum <= 0 ? '横线是地平线；主曲线为目标，金色为太阳，银灰色为月亮。' : '曲线仅显示不低于 ' + this.altAzMinimum.toString() + '° 的部分；主曲线为目标，金色为太阳，银灰色为月亮。') : '方位角从北方 0° 起顺时针增加：东 90°、南 180°、西 270°。').fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              if (this.graphMode === 0) {
                this.infoRow('当前位置', this.altAzNowLabel())
                this.infoRow('最高高度', this.altAzMaxLabel())
                this.infoRow('地平线以上时长', this.altAzVisibleHours())
                this.infoRow('显示下限', this.altAzMinimum === -90 ? '不限制' : this.altAzMinimum.toString() + '°')
              } else {
                this.infoRow('当前方位', this.azimuthNowLabel())
              }
            }
            } else if (this.graphMode === 2) {
              Text('选定本地时刻后，按全年每 3 天采样一次；与桌面版“全年高度”计算方式一致。')
                .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              Row({ space: 8 }) {
                Text('本地时刻 ' + this.annualElevationHour.toString().padStart(2, '0') + ':00').fontSize(10).fontColor(this.nmSub()).width(100)
                Slider({ value: this.annualElevationHour, min: 0, max: 23, step: 1 })
                  .layoutWeight(1)
                  .onChange((value: number) => {
                    const hour = Math.round(value)
                    if (hour !== this.annualElevationHour) {
                      this.annualElevationHour = hour
                      this.loadAnnualElevation()
                    }
                  })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('显示高度不低于').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([-90, 0, 15, 30], (minimum: number) => {
                  Text(minimum === -90 ? '全部' : minimum.toString() + '°').fontSize(10)
                    .fontColor(this.annualElevationMinimum === minimum ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.annualElevationMinimum === minimum ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => { this.annualElevationMinimum = minimum })
                }, (minimum: number) => minimum.toString())
                Button('刷新').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                  .borderRadius(16).height(28).padding({ left: 9, right: 9 })
                  .onClick(() => { this.loadAnnualElevation() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.graphLoading) {
                this.graphLoadingRow('正在生成全年高度曲线…')
              } else if (this.annualElevationError.length > 0) {
                Text(this.annualElevationError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
                this.graphSelectionGuide(this.annualElevationError)
              } else if (this.annualElevationData.length === 0) {
                Text('没有可绘制的数据。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else {
                Text(this.annualElevationName + ' · ' + this.annualElevationHour.toString().padStart(2, '0') + ':00 全年高度').fontSize(11).fontColor(this.nmText()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                Stack({ alignContent: Alignment.Center }) {
                  Row() {
                    ForEach(this.annualElevationData, (point: AnnualElevationPoint) => {
                      Column().width(this.annualBarWidth()).height(this.annualBarHeight(point.altitude))
                        .backgroundColor((point.altitude ?? -90) >= this.annualElevationMinimum ? this.nmAccent() : '#33FFFFFF').borderRadius(1)
                    }, (point: AnnualElevationPoint, index: number) => index.toString())
                  }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                  if (this.annualElevationMinimum <= 0) {
                    Divider().color('#66FFFFFF').strokeWidth(1).width('100%')
                  }
                }.width('100%').height(96).padding({ left: 6, right: 6 })
                Row() {
                  Text('1月').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Start)
                  Text('4月').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Center)
                  Text('7月').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Center)
                  Text('10月').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.End)
                }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                this.infoRow('全年最高', this.annualMaxLabel())
                this.infoRow('显示下限', this.annualElevationMinimum === -90 ? '不限制' : this.annualElevationMinimum.toString() + '°')
              }
            } else if (this.graphMode === 3) {
              Text('按天文暗夜（太阳低于地平线 18°）统计；点任一晚可跳到目标最高的时刻。')
                .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              Text('计划范围').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([30, 90], (days: number) => {
                  Text('未来 ' + days.toString() + ' 天').fontSize(10)
                    .fontColor(this.observabilityDays === days ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.observabilityDays === days ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.observabilityDays !== days) {
                        this.observabilityDays = days
                        this.loadObservabilityCalendar()
                      }
                    })
                }, (days: number) => days.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('最低高度').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([15, 20, 30], (altitude: number) => {
                  Text(altitude.toString() + '°').fontSize(10)
                    .fontColor(this.observabilityMinAltitude === altitude ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.observabilityMinAltitude === altitude ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.observabilityMinAltitude !== altitude) {
                        this.observabilityMinAltitude = altitude
                        this.loadObservabilityCalendar()
                      }
                    })
                }, (altitude: number) => altitude.toString())
                Button('刷新').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                  .borderRadius(16).height(28).padding({ left: 9, right: 9 })
                  .onClick(() => { this.loadObservabilityCalendar() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.graphLoading) {
                this.graphLoadingRow('正在计算未来多晚的观测窗口…')
              } else if (this.observabilityError.length > 0) {
                Text(this.observabilityError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
                this.graphSelectionGuide(this.observabilityError)
              } else if (this.observabilityData.length === 0) {
                Text('所选时段没有可用观测窗口。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else {
                Text(this.observabilityName + ' · 高于 ' + this.observabilityMinAltitude.toString() + '° 的暗夜可见时间')
                  .fontSize(11).fontColor(this.nmText()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                ForEach(this.observabilityData, (day: ObservabilityDay) => {
                  Column({ space: 2 }) {
                    Row() {
                      Text(day.date ?? '--').fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                      Text((day.visibleHours ?? 0).toFixed(1) + ' 小时').fontSize(11)
                        .fontColor((day.visibleHours ?? 0) > 0 ? this.nmAccent() : this.nmSub())
                    }.width('100%').padding({ left: 8, right: 8 })
                    if ((day.darkHours ?? 0) > 0) {
                      Text('最佳 ' + this.fmtClock(day.peakTime) + ' · 最高 ' + this.fmtNum(day.maxAltitude, 1, '°') + ' · 暗夜 ' + this.fmtNum(day.darkHours, 1, ' 小时'))
                        .fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 12, right: 8 })
                      Text('月亮：照亮 ' + this.fmtNum(day.moonIllumination, 0, ' %') + '，高度 ' + this.fmtNum(day.moonAltitude, 0, '°'))
                        .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12, right: 8 })
                    } else {
                      Text('当地没有完整的天文暗夜。').fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 12, right: 8 })
                    }
                  }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 2 })
                  .onClick(() => { this.jumpToObservabilityDay(day) })
                }, (day: ObservabilityDay, index: number) => index.toString())
              }
            } else if (this.graphMode === 4) {
              Text('显示选中目标与月亮的角距；金色柱表示距离小于参考线，通常意味着月光干扰更明显。')
                .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              Text('时间范围').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([14, 30, 60], (days: number) => {
                  Text('未来 ' + days.toString() + ' 天').fontSize(10)
                    .fontColor(this.lunarElongationDays === days ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.lunarElongationDays === days ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.lunarElongationDays !== days) {
                        this.lunarElongationDays = days
                        this.loadLunarElongation()
                      }
                    })
                }, (days: number) => days.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('采样间隔').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([6, 12, 24], (hours: number) => {
                  Text(hours.toString() + ' 小时').fontSize(10)
                    .fontColor(this.lunarElongationStepHours === hours ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.lunarElongationStepHours === hours ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.lunarElongationStepHours !== hours) {
                        this.lunarElongationStepHours = hours
                        this.loadLunarElongation()
                      }
                    })
                }, (hours: number) => hours.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('月距参考线').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([10, 20, 40, 60], (limit: number) => {
                  Text(limit.toString() + '°').fontSize(10)
                    .fontColor(this.lunarElongationLimit === limit ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.lunarElongationLimit === limit ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => { this.lunarElongationLimit = limit })
                }, (limit: number) => limit.toString())
                Button('刷新').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                  .borderRadius(16).height(28).padding({ left: 9, right: 9 })
                  .onClick(() => { this.loadLunarElongation() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.graphLoading) {
                this.graphLoadingRow('正在计算目标与月亮的角距…')
              } else if (this.lunarElongationError.length > 0) {
                Text(this.lunarElongationError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
                this.graphSelectionGuide(this.lunarElongationError)
              } else if (this.lunarElongationData.length === 0) {
                Text('没有可绘制的数据。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else {
                Text(this.lunarElongationName + ' · 未来 ' + this.lunarElongationDays.toString() + ' 天月距（每 ' + this.lunarElongationStepHours.toString() + ' 小时）')
                  .fontSize(11).fontColor(this.nmText()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                Stack({ alignContent: Alignment.Center }) {
                  Row() {
                    ForEach(this.lunarElongationData, (point: LunarElongationPoint) => {
                      Column().width(this.lunarElongationBarWidth()).height(this.lunarElongationBarHeight(point.separation))
                        .backgroundColor((point.separation ?? 180) < this.lunarElongationLimit ? '#E8B24B' : this.nmAccent()).borderRadius(1)
                    }, (point: LunarElongationPoint, index: number) => index.toString())
                  }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                  Divider().color('#E8B24B').strokeWidth(1).width('100%').position({ x: 0, y: this.lunarElongationLineTop() })
                }.width('100%').height(96).padding({ left: 6, right: 6 })
                Row() {
                  Text('现在').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Start)
                  Text('+' + Math.round(this.lunarElongationDays / 2).toString() + '天').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Center)
                  Text('+' + this.lunarElongationDays.toString() + '天').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.End)
                }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                Text('纵轴 0°-180°；金色横线是 ' + this.lunarElongationLimit.toString() + '° 参考线。').fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                this.infoRow('当前月距', this.lunarElongationNowLabel())
                this.infoRow('最接近月亮', this.lunarElongationClosestLabel())
                this.infoRow('参考线', this.lunarElongationLimit.toString() + '°')
              }
            } else {
              Text('桌面版“Graphs”双变量时间曲线：左右两条曲线各自缩放，适合比较不同量纲的变化趋势。')
                .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              Text('时间范围').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([30, 90, 365], (days: number) => {
                  Text(days === 365 ? '未来 1 年' : '未来 ' + days.toString() + ' 天').fontSize(10)
                    .fontColor(this.planetTimeSeriesDays === days ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.planetTimeSeriesDays === days ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.planetTimeSeriesDays !== days) {
                        this.planetTimeSeriesDays = days
                        if (days === 365 && this.planetTimeSeriesStepHours < 24) this.planetTimeSeriesStepHours = 24
                        this.loadPlanetTimeSeries()
                      }
                    })
                }, (days: number) => days.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('采样间隔').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach(this.planetTimeSeriesDays === 365 ? [24, 72] : [6, 24, 72], (hours: number) => {
                  Text(hours.toString() + ' 小时').fontSize(10)
                    .fontColor(this.planetTimeSeriesStepHours === hours ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.planetTimeSeriesStepHours === hours ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.planetTimeSeriesStepHours !== hours) {
                        this.planetTimeSeriesStepHours = hours
                        this.loadPlanetTimeSeries()
                      }
                    })
                }, (hours: number) => hours.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('左轴：' + this.planetMetricLabel(this.planetTimeSeriesLeftMetric)).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Column({ space: 3 }) {
                ForEach([['magnitude', 'phase', 'distance', 'elongation', 'angularSize'], ['phaseAngle', 'heliocentricDistance', 'transitAltitude', 'rightAscension', 'declination']], (metrics: Array<string>, row: number) => {
                  Row({ space: 3 }) {
                    ForEach(metrics, (metric: string) => {
                      Text(this.planetMetricLabel(metric)).fontSize(9).maxLines(1)
                        .fontColor(this.planetTimeSeriesLeftMetric === metric ? this.nmText() : this.nmSub())
                        .padding({ left: 5, right: 5, top: 4, bottom: 4 })
                        .backgroundColor(this.planetTimeSeriesLeftMetric === metric ? this.nmAccent() : this.nmBg())
                        .borderRadius(4)
                        .onClick(() => { this.planetTimeSeriesLeftMetric = metric; this.loadPlanetTimeSeries() })
                    }, (metric: string) => metric)
                  }.width('100%')
                }, (metrics: Array<string>, row: number) => row.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('右轴：' + this.planetMetricLabel(this.planetTimeSeriesRightMetric)).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Column({ space: 3 }) {
                ForEach([['magnitude', 'phase', 'distance', 'elongation', 'angularSize'], ['phaseAngle', 'heliocentricDistance', 'transitAltitude', 'rightAscension', 'declination']], (metrics: Array<string>, row: number) => {
                  Row({ space: 3 }) {
                    ForEach(metrics, (metric: string) => {
                      Text(this.planetMetricLabel(metric)).fontSize(9).maxLines(1)
                        .fontColor(this.planetTimeSeriesRightMetric === metric ? this.nmText() : this.nmSub())
                        .padding({ left: 5, right: 5, top: 4, bottom: 4 })
                        .backgroundColor(this.planetTimeSeriesRightMetric === metric ? '#9C6A24' : this.nmBg())
                        .borderRadius(4)
                        .onClick(() => { this.planetTimeSeriesRightMetric = metric; this.loadPlanetTimeSeries() })
                    }, (metric: string) => metric)
                  }.width('100%')
                }, (metrics: Array<string>, row: number) => row.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Row({ space: 6 }) {
                Button('刷新').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                  .borderRadius(16).height(28).padding({ left: 9, right: 9 })
                  .onClick(() => { this.loadPlanetTimeSeries() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.graphLoading) {
                this.graphLoadingRow('正在计算双变量时间曲线…')
              } else if (this.planetTimeSeriesError.length > 0) {
                Text(this.planetTimeSeriesError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
                this.graphSelectionGuide(this.planetTimeSeriesError)
              } else if (this.planetTimeSeriesData.length === 0) {
                Text('没有可绘制的数据。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else {
                Text(this.planetTimeSeriesName + ' · ' + this.planetMetricLabel(this.planetTimeSeriesLeftMetric) + ' / ' + this.planetMetricLabel(this.planetTimeSeriesRightMetric))
                  .fontSize(11).fontColor(this.nmText()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                Stack({ alignContent: Alignment.Center }) {
                  Row() {
                    ForEach(this.planetTimeSeriesData, (point: PlanetTimeSeriesPoint) => {
                      Row({ space: 1 }) {
                        Column().width(this.planetTimeSeriesSegmentWidth())
                          .height(this.planetTimeSeriesBarHeight(point.left, this.planetTimeSeriesLeftMin, this.planetTimeSeriesLeftMax))
                          .backgroundColor(this.nmAccent()).borderRadius(1)
                        Column().width(this.planetTimeSeriesSegmentWidth())
                          .height(this.planetTimeSeriesBarHeight(point.right, this.planetTimeSeriesRightMin, this.planetTimeSeriesRightMax))
                          .backgroundColor('#E8B24B').borderRadius(1)
                      }.width(this.planetTimeSeriesBarWidth()).height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                    }, (point: PlanetTimeSeriesPoint, index: number) => index.toString())
                  }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                }.width('100%').height(96).padding({ left: 6, right: 6 })
                Row() {
                  Text('现在').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Start)
                  Text('+' + Math.round(this.planetTimeSeriesDays / 2).toString() + '天').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Center)
                  Text(this.planetTimeSeriesDays === 365 ? '+1年' : '+' + this.planetTimeSeriesDays.toString() + '天').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.End)
                }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                Text('蓝色左轴：' + this.planetTimeSeriesLeftMin.toFixed(1) + ' - ' + this.planetTimeSeriesLeftMax.toFixed(1) + this.planetMetricUnit(this.planetTimeSeriesLeftMetric)
                  + '；金色右轴：' + this.planetTimeSeriesRightMin.toFixed(1) + ' - ' + this.planetTimeSeriesRightMax.toFixed(1) + this.planetMetricUnit(this.planetTimeSeriesRightMetric))
                  .fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                this.infoRow('当前 ' + this.planetMetricLabel(this.planetTimeSeriesLeftMetric), this.planetTimeSeriesValueLabel(this.planetTimeSeriesData[0].left, this.planetTimeSeriesLeftMetric))
                this.infoRow('当前 ' + this.planetMetricLabel(this.planetTimeSeriesRightMetric), this.planetTimeSeriesValueLabel(this.planetTimeSeriesData[0].right, this.planetTimeSeriesRightMetric))
              }
            }
          } else if (this.astroTab === 5) {
            Text('今晚可观测目标').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 2 })
            Text('按时段、最低高度和星等筛选适合观测的天体。').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
            Row({ space: 6 }) {
              Button('刷新可观测目标').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.tonightAstro = null; this.loadTonightAstro() })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
            if (this.tonightAstro === null) {
              Text('（正在汇总今晚的观测条件…）').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
            } else {
              Text('太阳与暗夜窗口').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow('日落', this.fmtDateTime(this.tonightAstro!.sun?.set))
              this.infoRow('天文暮光结束', this.fmtDateTime(this.tonightAstro!.sun?.astroTwilightEnd))
              this.infoRow('天文暮光开始', this.fmtDateTime(this.tonightAstro!.sun?.astroTwilightStart))
              this.infoRow('日出', this.fmtDateTime(this.tonightAstro!.sun?.rise))
              this.infoRow('可用暗夜时长', this.fmtNum(this.tonightAstro!.sun?.darkWindowHours, 1, ' 小时'))
              Text('月亮').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
              this.infoRow('月相', this.tonightAstro!.moon?.phaseName ?? '--')
              this.infoRow('照亮比例', this.fmtNum(this.tonightAstro!.moon?.illumination, 1, ' %'))
              this.infoRow('月龄', this.fmtNum(this.tonightAstro!.moon?.age, 1, ' 天'))
              this.infoRow('月出', this.fmtDateTime(this.tonightAstro!.moon?.rise))
              this.infoRow('月落', this.fmtDateTime(this.tonightAstro!.moon?.set))
              Text('今晚可观测目标').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
              Text('目标类别').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach(['planets', 'stars', 'messier'], (category: string) => {
                  Text(category === 'planets' ? '行星' : (category === 'stars' ? '亮星' : '梅西耶天体'))
                    .fontSize(10)
                    .fontColor(this.wutCategory === category ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.wutCategory === category ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.wutCategory !== category) {
                        this.wutCategory = category
                        this.loadWutTargets()
                      }
                    })
                }, (category: string) => category)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('观测时段').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach(['evening', 'midnight', 'morning', 'night'], (period: string) => {
                  Text(period === 'evening' ? '傍晚' : (period === 'morning' ? '清晨' : (period === 'night' ? '整夜' : '午夜'))).fontSize(10)
                    .fontColor(this.wutPeriod === period ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.wutPeriod === period ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.wutPeriod !== period) {
                        this.wutPeriod = period
                        this.loadWutTargets()
                      }
                    })
                }, (period: string) => period)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.wutAngularSizeAvailable) {
                Row({ space: 8 }) {
                  Column({ space: 1 }) {
                    Text('限制视直径').fontSize(10).fontColor(this.nmText()).width('100%')
                    Text('仅显示落在指定范围内的目标').fontSize(9).fontColor(this.nmSub()).width('100%')
                  }.layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.wutLimitAngularSize })
                    .width(38).height(22)
                    .onChange((value: boolean) => {
                      this.wutLimitAngularSize = value
                      this.loadWutTargets()
                    })
                }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
                if (this.wutLimitAngularSize) {
                  Row({ space: 4 }) {
                    ForEach(['10角分-1度', '1度-10度'], (label: string, index: number) => {
                      Text(label).fontSize(10)
                        .fontColor((index === 0 ? this.wutMinAngularSizeArcmin === 10 : this.wutMinAngularSizeArcmin === 60) ? this.nmText() : this.nmSub())
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .backgroundColor((index === 0 ? this.wutMinAngularSizeArcmin === 10 : this.wutMinAngularSizeArcmin === 60) ? this.nmAccent() : this.nmBg())
                        .borderRadius(5)
                        .onClick(() => {
                          this.wutMinAngularSizeArcmin = index === 0 ? 10 : 60
                          this.wutMaxAngularSizeArcmin = index === 0 ? 60 : 600
                          this.loadWutTargets()
                        })
                    }, (label: string) => label)
                  }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
                }
              } else {
                Text('亮星没有可用于此处筛选的视直径。').fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 4 }).margin({ bottom: 5 })
              }
              Row({ space: 12 }) {
                Column({ space: 3 }) {
                  Text('最低高度').fontSize(10).fontColor(this.nmSub()).width('100%')
                  Row({ space: 4 }) {
                    ForEach([10, 20, 30], (altitude: number) => {
                      Text(altitude.toString() + '°').fontSize(10)
                        .fontColor(this.wutMinAltitude === altitude ? this.nmText() : this.nmSub())
                        .padding({ left: 7, right: 7, top: 4, bottom: 4 })
                        .backgroundColor(this.wutMinAltitude === altitude ? this.nmAccent() : this.nmBg())
                        .borderRadius(5)
                        .onClick(() => {
                          if (this.wutMinAltitude !== altitude) {
                            this.wutMinAltitude = altitude
                            this.loadWutTargets()
                          }
                        })
                    }, (altitude: number) => altitude.toString())
                  }
                }.layoutWeight(1)
                Column({ space: 3 }) {
                  Text('最暗星等').fontSize(10).fontColor(this.nmSub()).width('100%')
                  Row({ space: 4 }) {
                    ForEach([4, 6, 8], (magnitude: number) => {
                      Text(magnitude.toString() + ' 等').fontSize(10)
                        .fontColor(this.wutMaxMagnitude === magnitude ? this.nmText() : this.nmSub())
                        .padding({ left: 7, right: 7, top: 4, bottom: 4 })
                        .backgroundColor(this.wutMaxMagnitude === magnitude ? this.nmAccent() : this.nmBg())
                        .borderRadius(5)
                        .onClick(() => {
                          if (this.wutMaxMagnitude !== magnitude) {
                            this.wutMaxMagnitude = magnitude
                            this.loadWutTargets()
                          }
                        })
                    }, (magnitude: number) => magnitude.toString())
                  }
                }.layoutWeight(1)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
              if (this.wutHint.length > 0) {
                Text(this.wutHint).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 4 }).margin({ bottom: 4 })
              } else {
                Text('筛选结果 ' + this.wutTargets.length.toString() + ' 个 · ' + this.fmtClock(this.wutObservationTime))
                  .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              }
              ForEach(this.wutTargets, (target: WutTarget) => {
                Column({ space: 2 }) {
                  Row() {
                    Text(this.wutTargetTitle(target)).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                    Text(target.type ?? '').fontSize(9).fontColor(this.nmSub()).width(58)
                    Text((target.magnitude ?? 0).toFixed(1) + ' 等').fontSize(10).fontColor(this.nmSub()).width(52)
                    Text((target.altitude ?? 0).toFixed(0) + '°').fontSize(10).fontColor(this.nmAccent()).width(40)
                  }.width('100%').padding({ left: 8, right: 8 })
                  if (this.wutTargetSubtitle(target).length > 0) {
                    Text(this.wutTargetSubtitle(target)).fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 12 })
                  }
                  Text('方位 ' + (target.azimuth ?? 0).toFixed(0) + '°   升 ' + this.fmtClock(target.rise)
                    + '  中天 ' + this.fmtClock(target.transit) + '  落 ' + this.fmtClock(target.set))
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  if (target.angularSizeArcmin !== undefined) {
                    Text('视直径 ' + (target.angularSizeArcmin ?? 0).toFixed(1) + ' 角分')
                      .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }
                }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 2 })
                .onClick(() => { this.jumpToWutTarget(target) })
              }, (target: WutTarget, index: number) => (target.englishName ?? index.toString()))
              Text('行星（点击跳到中天时刻）').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
              ForEach(this.tonightAstro!.planets ?? [], (p: TonightPlanet) => {
                Column({ space: 1 }) {
                  Row() {
                    Text(p.name ?? '').fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                    Text((p.visible === true ? '现在可见' : '在地平线下')).fontSize(9)
                      .fontColor((p.visible === true) ? this.nmAccent() : this.nmSub()).width(64)
                    Text((p.magnitude ?? 0).toFixed(1) + ' 等').fontSize(10).fontColor(this.nmSub()).width(52)
                  }.width('100%').padding({ left: 8, right: 8 })
                  Text('升 ' + this.fmtClock(p.rise)
                    + '  中天 ' + this.fmtClock(p.transit)
                    + '  落 ' + this.fmtClock(p.set))
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 2 })
                .onClick(() => { if (p.transitJd !== undefined) this.callNative('setJD', String(p.transitJd)) })
              }, (p: TonightPlanet, index: number) => index.toString())
              if ((this.tonightAstro!.meteorShowers ?? []).length > 0) {
                Text('活跃流星雨（点击跳到最佳观测时刻）').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                ForEach(this.tonightAstro!.meteorShowers ?? [], (s: TonightShower) => {
                  Row() {
                    Text(s.name ?? '').fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                    Text('每小时约 ' + String(s.zhr ?? '?') + ' 颗').fontSize(10).fontColor(this.nmSub()).width(96)
                  }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
                  .backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 2 })
                  .onClick(() => { if (s.primeJd !== undefined) this.callNative('setJD', String(s.primeJd)) })
                }, (s: TonightShower, index: number) => index.toString())
              }
            }
          } else if (this.astroTab === 6) {
            Text(I18n.t('i0131')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Row({ space: 4 }) {
              ForEach(['实时数据', '距离曲线'], (mode: string, index: number) => {
                Text(mode).fontSize(10)
                  .fontColor(this.planetCalcMode === index ? this.nmText() : this.nmSub())
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor(this.planetCalcMode === index ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.planetCalcMode !== index) {
                      this.planetCalcMode = index
                      if (index === 1) this.loadPlanetPairDistance()
                      else this.loadPlanetCalc()
                    }
                  })
              }, (mode: string) => mode)
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
            if (this.planetCalcMode === 0) {
            Row({ space: 6 }) {
              Button(I18n.t('i0243')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.loadPlanetCalc() })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
            if (this.planetCalcData.length === 0) {
              Text('（正在计算各行星的实时数据…）').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
            }
            ForEach(this.planetCalcData, (p: PlanetCalcItem) => {
              Column({ space: 2 }) {
                Row() {
                  Text(p.name ?? '').fontSize(12).fontColor(this.nmText()).layoutWeight(1)
                  Text((p.magnitude ?? 0).toFixed(1) + ' 等').fontSize(10).fontColor(this.nmSub()).width(52)
                }.width('100%').padding({ left: 8, right: 8 })
                Text('赤经 ' + String(p.ra ?? '--') + '   赤纬 ' + String(p.dec ?? '--'))
                  .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                Text('高度 ' + (p.altitude ?? 0).toFixed(1) + '°   方位 ' + (p.azimuth ?? 0).toFixed(1) + '°'
                  + (p.distanceAU !== undefined ? ('   距离 ' + (p.distanceAU ?? 0).toFixed(3) + ' AU') : ''))
                  .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                if (p.elongation !== undefined) {
                  Text('距角 ' + ((p.elongation ?? 0) * 180 / Math.PI).toFixed(1) + '°'
                    + '   相位 ' + ((p.phase ?? 0) * 100).toFixed(0) + '%')
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                }
                if (p.illumination !== undefined) {
                  Text('照亮 ' + (p.illumination ?? 0).toFixed(1) + '%   月龄 ' + (p.age ?? 0).toFixed(1) + ' 天')
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                }
                if (p.rise !== undefined) {
                  Text('升 ' + this.fmtClock(p.rise)
                    + '  中天 ' + this.fmtClock(p.transit)
                    + '  落 ' + this.fmtClock(p.set))
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                }
              }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 3 })
              .onClick(() => { this.callNative('searchObject', String(p.englishName ?? '')) })
            }, (p: PlanetCalcItem, index: number) => index.toString())
            } else {
              Text('对应桌面版行星计算器的“图表”：蓝色为线性距离，金色为表观角距离；两轴独立缩放。')
                .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              Text('第一个天体').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Column({ space: 3 }) {
                ForEach([['Sun', 'Earth', 'Moon', 'Mercury', 'Venus', 'Mars'], ['Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto']], (bodies: Array<string>, row: number) => {
                  Row({ space: 3 }) {
                    ForEach(bodies, (body: string) => {
                      Text(this.planetPairBodyName(body)).fontSize(9)
                        .fontColor(this.planetPairFirst === body ? this.nmText() : this.nmSub())
                        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                        .backgroundColor(this.planetPairFirst === body ? this.nmAccent() : this.nmBg())
                        .borderRadius(4)
                        .onClick(() => {
                          if (body !== this.planetPairSecond) {
                            this.planetPairFirst = body
                            this.loadPlanetPairDistance()
                          }
                        })
                    }, (body: string) => body)
                  }.width('100%')
                }, (bodies: Array<string>, row: number) => row.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('第二个天体').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Column({ space: 3 }) {
                ForEach([['Sun', 'Earth', 'Moon', 'Mercury', 'Venus', 'Mars'], ['Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto']], (bodies: Array<string>, row: number) => {
                  Row({ space: 3 }) {
                    ForEach(bodies, (body: string) => {
                      Text(this.planetPairBodyName(body)).fontSize(9)
                        .fontColor(this.planetPairSecond === body ? this.nmText() : this.nmSub())
                        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                        .backgroundColor(this.planetPairSecond === body ? '#9C6A24' : this.nmBg())
                        .borderRadius(4)
                        .onClick(() => {
                          if (body !== this.planetPairFirst) {
                            this.planetPairSecond = body
                            this.loadPlanetPairDistance()
                          }
                        })
                    }, (body: string) => body)
                  }.width('100%')
                }, (bodies: Array<string>, row: number) => row.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('前后范围').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([40, 80, 180], (days: number) => {
                  Text('前后 ' + days.toString() + ' 天').fontSize(10)
                    .fontColor(this.planetPairDays === days ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.planetPairDays === days ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.planetPairDays !== days) {
                        this.planetPairDays = days
                        if (days === 80 && this.planetPairStepDays < 2) this.planetPairStepDays = 2
                        if (days === 180 && this.planetPairStepDays < 4) this.planetPairStepDays = 4
                        this.loadPlanetPairDistance()
                      }
                    })
                }, (days: number) => days.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('采样步长').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach(this.planetPairDays === 40 ? [1, 2, 4, 7] : (this.planetPairDays === 80 ? [2, 4, 7] : [4, 7]), (step: number) => {
                  Text(step.toString() + ' 天').fontSize(10)
                    .fontColor(this.planetPairStepDays === step ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.planetPairStepDays === step ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.planetPairStepDays !== step) {
                        this.planetPairStepDays = step
                        this.loadPlanetPairDistance()
                      }
                    })
                }, (step: number) => step.toString())
                Button('刷新').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                  .borderRadius(16).height(28).padding({ left: 9, right: 9 })
                  .onClick(() => { this.loadPlanetPairDistance() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.planetPairDistanceError.length > 0) {
                Text(this.planetPairDistanceError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.planetPairDistanceData.length === 0) {
                Text('（正在计算两天体之间的距离变化…）').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else {
                Text(this.planetPairFirstName + ' ↔ ' + this.planetPairSecondName + ' · 前后 ' + this.planetPairDays.toString() + ' 天')
                  .fontSize(11).fontColor(this.nmText()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                Stack({ alignContent: Alignment.Center }) {
                  Row() {
                    ForEach(this.planetPairDistanceData, (point: PlanetPairDistancePoint) => {
                      Row({ space: 1 }) {
                        Column().width(this.planetPairSegmentWidth())
                          .height(this.planetPairBarHeight(point.linearDistance, this.planetPairLinearMin, this.planetPairLinearMax))
                          .backgroundColor(this.nmAccent()).borderRadius(1)
                        if (this.planetPairAngularAvailable) {
                          Column().width(this.planetPairSegmentWidth())
                            .height(this.planetPairBarHeight(point.angularDistance, this.planetPairAngularMin, this.planetPairAngularMax))
                            .backgroundColor('#E8B24B').borderRadius(1)
                        }
                      }.width(this.planetPairBarWidth()).height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                    }, (point: PlanetPairDistancePoint, index: number) => index.toString())
                  }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                }.width('100%').height(96).padding({ left: 6, right: 6 })
                Row() {
                  Text('-' + this.planetPairDays.toString() + '天').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Start)
                  Text('现在').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.Center)
                  Text('+' + this.planetPairDays.toString() + '天').fontSize(9).fontColor(this.nmSub()).layoutWeight(1).textAlign(TextAlign.End)
                }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                Text(this.planetPairAngularAvailable ? '蓝色线性距离：' + this.planetPairLinearMin.toFixed(3) + ' - ' + this.planetPairLinearMax.toFixed(3) + ' AU；金色角距离：' + this.planetPairAngularMin.toFixed(1) + ' - ' + this.planetPairAngularMax.toFixed(1) + '°' : '蓝色为线性距离；与观测地球比较时，表观角距离不适用。')
                  .fontSize(9).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                this.infoRow('当前线性距离', this.planetPairLinearLabel(this.planetPairDistanceData[this.planetPairCurrentIndex()].linearDistance))
                if (this.planetPairAngularAvailable) {
                  this.infoRow('当前角距离', (this.planetPairDistanceData[this.planetPairCurrentIndex()].angularDistance ?? 0).toFixed(1) + '°')
                }
              }
            }
          } else if (this.astroTab === 7) {
            Text(I18n.t('i0132')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Row({ space: 4 }) {
              ForEach(['日月食', '行星凌日'], (label: string, index: number) => {
                Text(label).fontSize(10).fontColor(this.eclipseMode === index ? this.nmText() : this.nmSub())
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor(this.eclipseMode === index ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.eclipseMode !== index) {
                      this.eclipseMode = index
                      if (index === 0) this.loadEclipses()
                      else this.loadPlanetaryTransits()
                    }
                  })
              }, (label: string) => label)
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
            if (this.eclipseMode === 0) {
            Row({ space: 6 }) {
              Button('计算日月食').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.reloadEclipses() })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
            Text('预测范围').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach([12, 36, 60], (months: number) => {
                Text(months === 12 ? '未来 1 年' : '未来 ' + (months / 12).toString() + ' 年').fontSize(10)
                  .fontColor(this.eclipseMonths === months ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.eclipseMonths === months ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.eclipseMonths !== months) {
                      this.eclipseMonths = months
                      this.reloadEclipses()
                    }
                  })
              }, (months: number) => months.toString())
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            Text('开始日期').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Scroll() {
              Row({ space: 4 }) {
                ForEach([0, 1, 7, 30], (offsetDays: number) => {
                  Text(this.eclipseStartOptionLabel(offsetDays)).fontSize(10)
                    .fontColor(this.eclipseStartOffsetDays === offsetDays ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.eclipseStartOffsetDays === offsetDays ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.eclipseStartOffsetDays !== offsetDays) {
                        this.eclipseStartOffsetDays = offsetDays
                        this.reloadEclipses()
                      }
                    })
                }, (offsetDays: number) => offsetDays.toString())
                Button(this.eclipseStartOffsetDays < 0 ? this.eclipseStartOptionLabel(-1) : '指定日期').fontSize(10)
                  .fontColor(this.eclipseStartOffsetDays < 0 ? this.nmText() : this.nmSub())
                  .height(26).padding({ left: 9, right: 9 })
                  .backgroundColor(this.eclipseStartOffsetDays < 0 ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => { this.chooseEclipseStartDate() })
              }.padding({ left: 2, right: 2 })
            }.width('100%').height(30).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 6 })
            Text('事件类别').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 4 }) {
              ForEach(['全部', '日食', '月食'], (label: string, index: number) => {
                Text(label).fontSize(10).fontColor(this.eclipseKindFilter === index ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.eclipseKindFilter === index ? this.nmAccent() : this.nmBg())
                  .borderRadius(5).onClick(() => { this.eclipseKindFilter = index })
              }, (label: string) => label)
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            Text('食的类型').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
            Row({ space: 3 }) {
              ForEach(['全部', '全食', '环食', '偏食', '半影食'], (label: string, index: number) => {
                Text(label).fontSize(9).fontColor(this.eclipseTypeFilter === index ? this.nmText() : this.nmSub())
                  .padding({ left: 7, right: 7, top: 4, bottom: 4 })
                  .backgroundColor(this.eclipseTypeFilter === index ? this.nmAccent() : this.nmBg())
                  .borderRadius(4).onClick(() => { this.eclipseTypeFilter = index })
              }, (label: string) => label)
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            Text('从' + this.eclipseStartOptionLabel(this.eclipseStartOffsetDays) + '开始的未来 ' + (this.eclipseMonths / 12).toString() + ' 年日食与月食（点击可把时间跳到食甚时刻）。')
              .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
            if (this.eclipseLoading) {
              Row({ space: 8 }) {
                LoadingProgress().width(22).height(22).color(this.nmAccent())
                Text('正在推算日月食…').fontSize(11).fontColor(this.nmSub())
              }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
            } else if (this.eclipseError.length > 0) {
              Text(this.eclipseError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
            } else if (this.eclipseData.length === 0) {
              Text('点击“计算日月食”生成预测。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
            } else if (this.filteredEclipses().length === 0) {
              Text('当前筛选条件下没有日月食。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
            }
            ForEach(this.filteredEclipses(), (e: EclipseItem) => {
              Column({ space: 1 }) {
                Row() {
                  Text(((e.kind === 'solar') ? '日' : '月') + (e.type ?? ''))
                    .fontSize(11).fontColor(this.nmAccent()).width(56)
                  Text(this.fmtDateTime(e.date)).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                  Text('食分 ' + (e.magnitude ?? 0).toFixed(2)).fontSize(10).fontColor(this.nmSub()).width(62)
                }.width('100%').padding({ left: 8, right: 8 })
                if (e.kind === 'solar' && e.saros !== undefined) {
                  Text('沙罗周期 ' + (e.saros ?? 0).toString() + '   ' + (Math.abs(e.pathWidthKm ?? 0) > 0.1
                    ? '中心路径宽 ' + Math.abs(e.pathWidthKm ?? 0).toFixed(0) + ' 千米' : '非中心食'))
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 }).maxLines(1)
                }
                if (e.durationMin !== undefined && Math.abs(e.durationMin ?? 0) > 0.001) {
                  Text('中心食持续 ' + Math.abs(e.durationMin ?? 0).toFixed(1) + ' 分钟   中心点 '
                    + (e.centralLat ?? 0).toFixed(1) + '°, ' + (e.centralLng ?? 0).toFixed(1) + '°   路径偏离 ' + (e.gamma ?? 0).toFixed(3))
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                }
                if (e.kind === 'lunar') {
                  Text('沙罗周期 ' + (e.saros ?? 0).toString() + '   路径偏离 ' + (e.gamma ?? 0).toFixed(3)
                    + '   半影食分 ' + (e.penumbralMagnitude ?? 0).toFixed(2)
                    + '   本影食分 ' + (e.umbralMagnitude ?? 0).toFixed(2))
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 }).maxLines(1)
                  Text((e.visibility ?? '本地条件未知') + '   月亮高度 ' + (e.localMoonAltitude ?? 0).toFixed(1) + '°')
                    .fontSize(9).fontColor(this.nmAccent()).width('100%').padding({ left: 12 })
                }
                if (e.kind === 'solar' && e.localVisible === true) {
                  Text('本地食甚 ' + this.fmtClock(e.localMax) + '   食分 ' + (e.localMagnitude ?? 0).toFixed(2)
                    + '   太阳高度 ' + (e.localSunAltitude ?? 0).toFixed(1) + '°')
                    .fontSize(9).fontColor(this.nmAccent()).width('100%').padding({ left: 12 })
                  Text((e.localFirstContactLabel ?? '初亏') + ' ' + this.fmtClock(e.localFirstContact)
                    + '   ' + (e.localLastContactLabel ?? '复圆') + ' ' + this.fmtClock(e.localLastContact))
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  if (e.localCentralType !== undefined) {
                    Text('本地' + e.localCentralType + '：' + this.fmtClock(e.localCentralStart)
                      + ' - ' + this.fmtClock(e.localCentralEnd))
                      .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }
                } else if (e.kind === 'solar' && e.localVisible === false) {
                  Text('本地不可见').fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                }
                if (e.note !== undefined) {
                  Text(e.note ?? '').fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                }
              }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 2 })
              .onClick(() => { if (e.jd !== undefined) this.callNative('setJD', String(e.jd)) })
            }, (e: EclipseItem, index: number) => e.jd !== undefined ? e.jd.toFixed(6) : index.toString())
            } else {
              Row({ space: 6 }) {
                Button('计算行星凌日').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                  .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                  .onClick(() => {
                    this.planetaryTransitData = []
                    this.planetaryTransitError = ''
                    this.planetaryTransitLoaded = false
                    this.loadPlanetaryTransits()
                  })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              Text('预测范围').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([5, 20, 50], (years: number) => {
                  Text('未来 ' + years.toString() + ' 年').fontSize(10)
                    .fontColor(this.planetaryTransitYears === years ? this.nmText() : this.nmSub())
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.planetaryTransitYears === years ? this.nmAccent() : this.nmBg())
                    .borderRadius(5)
                    .onClick(() => {
                      if (this.planetaryTransitYears !== years) {
                        this.planetaryTransitYears = years
                        this.planetaryTransitData = []
                        this.planetaryTransitError = ''
                        this.planetaryTransitLoaded = false
                        this.loadPlanetaryTransits()
                      }
                    })
                }, (years: number) => years.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('水星或金星从太阳圆面前通过。接触时刻和可见时长均按当前观测地点计算。')
                .fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              if (!this.planetaryTransitLoaded) {
                Text('（正在推算行星凌日，需要几秒钟…）').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.planetaryTransitError.length > 0) {
                Text(this.planetaryTransitError).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.planetaryTransitData.length === 0) {
                Text('未来 ' + this.planetaryTransitYears.toString() + ' 年内没有水星或金星凌日。').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
              }
              ForEach(this.planetaryTransitData, (transit: PlanetaryTransitItem) => {
                Column({ space: 2 }) {
                  Row() {
                    Text((transit.planet ?? '行星') + '凌日').fontSize(11).fontColor(this.nmAccent()).width(60)
                    Text(this.fmtDateTime(transit.date)).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                    Text('食分 ' + (transit.magnitude ?? 0).toFixed(3)).fontSize(10).fontColor(this.nmSub()).width(68)
                  }.width('100%').padding({ left: 8, right: 8 })
                  Text('C1 ' + this.fmtClock(transit.firstContact) + '   C2 ' + this.fmtClock(transit.secondContact)
                    + '   食甚 ' + this.fmtClock(transit.middle) + '   C3 ' + this.fmtClock(transit.thirdContact) + '   C4 ' + this.fmtClock(transit.lastContact))
                    .fontSize(9).fontColor('#CCFFFFFF').width('100%').padding({ left: 12, right: 8 }).maxLines(2)
                  Text('最小距日中心 ' + (transit.minimumSeparation ?? 0).toFixed(3) + '°   全程 ' + (transit.durationMin ?? 0).toFixed(1) + ' 分钟')
                    .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  if (transit.localVisible === true) {
                    Text('本地可见 ' + (transit.observableDurationMin ?? 0).toFixed(1) + ' 分钟   食甚太阳高度 ' + (transit.sunAltitude ?? 0).toFixed(1) + '°')
                      .fontSize(9).fontColor(this.nmAccent()).width('100%').padding({ left: 12 })
                  } else {
                    Text('本地不可见（食甚太阳高度 ' + (transit.sunAltitude ?? 0).toFixed(1) + '°）')
                      .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }
                }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 3 })
                .onClick(() => { if (transit.jd !== undefined) this.callNative('setJD', String(transit.jd)) })
              }, (transit: PlanetaryTransitItem, index: number) => transit.jd !== undefined ? transit.jd.toFixed(6) : index.toString())
            }
          } else if (this.astroTab === 8) {
            Text(I18n.t('i0133')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Button(I18n.t('i0240')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadAlmanac() })
            if (this.almanacData.size > 0) {
              if (this.almanacSeasons.length > 0) {
                Text((this.almanacSeasonYear.length > 0 ? this.almanacSeasonYear + ' 年' : '本年') + '四季节点')
                  .fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                ForEach(this.almanacSeasons, (event: SeasonEvent) => {
                  Row() {
                    Text(event.label ?? '').fontSize(11).fontColor(this.nmAccent()).width(42)
                    Text(this.fmtDateTime(event.date)).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                    Text('持续 ' + (event.durationDays ?? 0).toFixed(1) + ' 天').fontSize(10).fontColor(this.nmSub()).width(88)
                  }.width('100%').height(28).padding({ left: 8, right: 8 }).backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 3 })
                  .onClick(() => { this.jumpToAlmanacSeason(event) })
                }, (event: SeasonEvent, index: number) => (event.jd ?? index).toString())
                Row()
                  .width('100%').height(0.5)
                  .backgroundColor(this.nmBorder())
                  .margin({ top: 4, bottom: 4 })
              }
              Text(I18n.t('s0372')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow(I18n.t('s0365'), this.jdToDateStr(this.almanacData.get('sunRise') ?? '0'))
              this.infoRow(I18n.t('s0366'), this.jdToDateStr(this.almanacData.get('sunSet') ?? '0'))
              this.infoRow(I18n.t('s0701'), this.jdToDateStr(this.almanacData.get('sunTransit') ?? '0'))
              this.infoRow('昼长', this.almanacHoursLabel('daylightHours'))
              this.infoRow('夜长', this.almanacHoursLabel('nightHours'))
              Text('晨昏蒙影').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
              this.infoRow('民用晨光', this.jdToDateStr(this.almanacData.get('civilRise') ?? '0'))
              this.infoRow('民用昏影', this.jdToDateStr(this.almanacData.get('civilSet') ?? '0'))
              this.infoRow('航海晨光', this.jdToDateStr(this.almanacData.get('nauticalRise') ?? '0'))
              this.infoRow('航海昏影', this.jdToDateStr(this.almanacData.get('nauticalSet') ?? '0'))
              this.infoRow('天文晨光', this.jdToDateStr(this.almanacData.get('astronomicalRise') ?? '0'))
              this.infoRow('天文昏影', this.jdToDateStr(this.almanacData.get('astronomicalSet') ?? '0'))
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.nmBorder())
                .margin({ top: 4, bottom: 4 })
              Text(I18n.t('s0373')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow(I18n.t('s0367'), this.jdToDateStr(this.almanacData.get('moonRise') ?? '0'))
              this.infoRow(I18n.t('s0368'), this.jdToDateStr(this.almanacData.get('moonSet') ?? '0'))
              this.infoRow(I18n.t('s0701'), this.jdToDateStr(this.almanacData.get('moonTransit') ?? '0'))
              this.infoRow(I18n.t('s0369'), parseFloat(this.almanacData.get('moonPhase') ?? '0').toFixed(1) + '%')
            }
          } else {
            Text('月相预报').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 2 })
            Text('按月球相对太阳的地心黄经差计算新月、上弦、满月和下弦。').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
            Row({ space: 6 }) {
              ForEach([30, 90], (days: number) => {
                Text('未来 ' + days.toString() + ' 天').fontSize(10)
                  .fontColor(this.moonPhaseDays === days ? this.nmText() : this.nmSub())
                  .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.moonPhaseDays === days ? this.nmAccent() : this.nmBg())
                  .borderRadius(5)
                  .onClick(() => {
                    if (this.moonPhaseDays !== days) {
                      this.moonPhaseDays = days
                      this.loadMoonPhases()
                    }
                  })
              }, (days: number) => days.toString())
              Button('刷新月相').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.loadMoonPhases() })
            }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
            if (this.moonPhaseData.length === 0) {
              Text('（正在计算月相…）').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 8 }).margin({ top: 6 })
            }
            ForEach(this.moonPhaseData, (item: MoonPhaseItem) => {
              Column({ space: 2 }) {
                Row() {
                  Text(item.phase ?? '').fontSize(11).fontColor(this.nmAccent()).width(56)
                  Text(this.fmtDateTime(item.date)).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                  Text('照亮 ' + (item.illumination ?? 0).toFixed(0) + '%').fontSize(10).fontColor(this.nmSub()).width(70)
                }.width('100%').padding({ left: 8, right: 8 })
                Text('高度 ' + (item.altitude ?? 0).toFixed(1) + '°   方位 ' + (item.azimuth ?? 0).toFixed(1) + '°')
                  .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                Text('升 ' + this.fmtClock(item.rise) + '  中天 ' + this.fmtClock(item.transit) + '  落 ' + this.fmtClock(item.set))
                  .fontSize(9).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
              }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.nmBg()).borderRadius(4).margin({ bottom: 3 })
              .onClick(() => { this.jumpToMoonPhase(item) })
            }, (item: MoonPhaseItem, index: number) => (item.jd ?? index).toString())
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'help') {
      // Help 面板
      Scroll() {
        Column({ space: 8 }) {
          Text(I18n.t('i0216')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4 })
          Text(I18n.t('i0261')).fontSize(11).fontColor(this.nmSub()).width('100%')
          Text(I18n.t('i0262')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0263')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0264')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          // ===== 手势指南 =====
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Text(I18n.t('i0310')).fontSize(13).fontColor(this.nmText()).width('100%')
          Row({ space: 10 }) {
            Text('DRAG').fontSize(8).fontColor(this.nmAccent()).fontWeight(FontWeight.Bold).width(36).height(20)
              .textAlign(TextAlign.Center).borderRadius(4).backgroundColor(this.nmBg())
            Text(I18n.t('i0311')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
          }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
          Row({ space: 10 }) {
            Text('PINCH').fontSize(8).fontColor(this.nmAccent()).fontWeight(FontWeight.Bold).width(36).height(20)
              .textAlign(TextAlign.Center).borderRadius(4).backgroundColor(this.nmBg())
            Text(I18n.t('i0312')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
          }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
          Row({ space: 10 }) {
            Text('TAP').fontSize(8).fontColor(this.nmAccent()).fontWeight(FontWeight.Bold).width(36).height(20)
              .textAlign(TextAlign.Center).borderRadius(4).backgroundColor(this.nmBg())
            Text(I18n.t('i0313')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
          }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
          Row({ space: 10 }) {
            Text('2FD').fontSize(8).fontColor(this.nmAccent()).fontWeight(FontWeight.Bold).width(36).height(20)
              .textAlign(TextAlign.Center).borderRadius(4).backgroundColor(this.nmBg())
            Text(I18n.t('i0314')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
          }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
          Row({ space: 10 }) {
            Text('HOLD').fontSize(8).fontColor(this.nmAccent()).fontWeight(FontWeight.Bold).width(36).height(20)
              .textAlign(TextAlign.Center).borderRadius(4).backgroundColor(this.nmBg())
            Text(I18n.t('i0315')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
          }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
          // ===== 快捷操作 =====
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Text(I18n.t('i0217')).fontSize(13).fontColor(this.nmText()).width('100%')
          Text(I18n.t('i0265')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0266')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0267')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0268')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Text(I18n.t('i0218')).fontSize(13).fontColor(this.nmText()).width('100%')
          Text(I18n.t('i0269')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0270')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0271')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0272')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0273')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('i0274')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          // ===== 关于 =====
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Text(I18n.t('c_about')).fontSize(13).fontColor(this.nmText()).width('100%')
          if (this.aboutVersion.length > 0) {
            Text('Stellarium ' + this.aboutVersion + ' · Qt ' + this.aboutQt).fontSize(10).fontColor('#99FFFFFF').width('100%')
            Text(I18n.t('c_user_dir') + ': ' + this.aboutUserDir).fontSize(9).fontColor('#99FFFFFF').width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(I18n.t('c_config_file') + ': ' + this.aboutConfigFile).fontSize(9).fontColor('#99FFFFFF').width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Text(I18n.t('c_loading')).fontSize(10).fontColor('#99FFFFFF').width('100%')
          }
          // ===== 日志 =====
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Row({ space: 8 }) {
            Text(I18n.t('c_runtime_logs')).fontSize(13).fontColor(this.nmText()).layoutWeight(1)
            Button(this.logVisible ? '刷新' : '查看日志')
              .fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(8).height(28).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadLog() })
            if (this.logVisible) {
              Button(I18n.t('btn_collapse'))
                .fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.logVisible = false })
            }
          }.width('100%')
          if (this.logVisible) {
            Scroll() {
              Text(this.logText.length > 0 ? this.logText : '（日志为空）')
                .fontSize(9).fontColor('#99FFFFFF').width('100%')
                .fontFamily('monospace')
            }
            .width('100%').height(180)
            .backgroundColor(this.nmBg()).borderRadius(8)
            .padding(8)
            .scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
          }
          // ===== 配置导入导出 =====
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Row({ space: 8 }) {
            Text(I18n.t('c_config_import_export')).fontSize(13).fontColor(this.nmText()).layoutWeight(1)
            Button(I18n.t('btn_import_config'))
              .fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(8).height(28).padding({ left: 10, right: 10 })
              .onClick(() => { this.importConfig() })
            Button(I18n.t('btn_export_view'))
              .fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(8).height(28).padding({ left: 10, right: 10 })
              .onClick(() => { this.exportConfig() })
            if (this.configExportVisible) {
              Button(I18n.t('btn_collapse'))
                .fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.configExportVisible = false })
            }
          }.width('100%')
          if (this.configExportVisible) {
            Scroll() {
              Text(this.configExportText.length > 0 ? this.configExportText : '（配置为空）')
                .fontSize(9).fontColor('#99FFFFFF').width('100%')
                .fontFamily('monospace')
            }
            .width('100%').height(160)
            .backgroundColor(this.nmBg()).borderRadius(8)
            .padding(8)
            .scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
          }
          TextArea({ placeholder: I18n.t('c_config_import_hint'), text: this.configImportText })
            .fontSize(10).fontColor(this.nmText())
            .placeholderFont({ size: 10 }).placeholderColor('#8CFFFFFF')
            .backgroundColor(this.nmBg()).borderRadius(8)
            .width('100%').height(72)
            .onChange((v: string) => { this.configImportText = v })
          Text(this.configImportMsg.length > 0 ? this.configImportMsg : ' ')
            .fontSize(10).fontColor('#FFAA00').width('100%').height(16)
          Text(I18n.t('m_config_import_tip'))
            .fontSize(9).fontColor('#8CFFFFFF').width('100%').margin({ bottom: 8 })
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
	    } else if (this.activePanel === 'catalogs') {
	      if (OFFLINE_APPGALLERY_BUILD) {
	        Column() {
	          Text(I18n.t('m_all_catalogs_included')).fontSize(14).fontColor('#E5FFFFFF').margin({ top: 8 })
	        }.width('100%').height(120).justifyContent(FlexAlign.Center)
	      } else {
	      // 星表下载面板
	      if (this.catalogLoading) {
        Column() {
          Text(I18n.t('c_loading_catalogs')).fontSize(13).fontColor('#99FFFFFF')
        }.width('100%').height(120).justifyContent(FlexAlign.Center)
      } else if (this.catalogList.length === 0) {
        Column() {
          Text(I18n.t('m_no_catalogs')).fontSize(14).fontColor('#E5FFFFFF').margin({ top: 8 })
          Text(I18n.t('m_all_catalogs_included')).fontSize(12).fontColor('#CC8FB6FF').margin({ top: 6 })
        }.width('100%').height(120).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.catalogList, (c: StarCatalogItem) => {
              Column({ space: 4 }) {
                Row() {
                  Column() {
                    Text(c.name)
                      .fontSize(14).fontColor('#E5FFFFFF').fontWeight(FontWeight.Medium)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                    if (c.size.length > 0) {
                      Text('大小 ' + c.size)
                        .fontSize(11).fontColor('#99FFFFFF').margin({ top: 2 })
                    }
                  }.layoutWeight(1)
                  if (c.checked) {
                    Text(I18n.t('c_installed'))
                      .fontSize(11).fontColor('#7FB3DC')
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .backgroundColor('rgba(91,147,191,0.15)').borderRadius(8)
                  } else {
                    Button(this.catalogBusy && this.catalogDownloadingId === c.id ? '下载中' : '下载')
                      .fontSize(12).fontColor('#E5FFFFFF')
                      .backgroundColor(this.catalogBusy ? 'rgba(255,255,255,0.10)' : 'rgba(107,163,214,0.35)')
                      .borderRadius(14).height(32).padding({ left: 14, right: 14 })
                      .enabled(!this.catalogBusy)
                      .onClick(() => { this.startCatalogDownload(c.id) })
                  }
                }.width('100%')
                if (this.catalogBusy && this.catalogDownloadingId === c.id && this.catalogMsg.length > 0) {
                  Text(this.catalogMsg).fontSize(11).fontColor('#99FFFFFF').width('100%')
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor('rgba(255,255,255,0.04)')
              .borderRadius(12)
              .border({ width: 1, color: this.nmBorder() })
            }, (c: StarCatalogItem) => c.id)
          }.width('100%').padding({ left: 2, right: 2 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
      }
      }
    } else if (this.activePanel === 'bookmarks') {
      // 书签面板：保存当前视图 + 已存书签列表（点击跳转 / 删除）
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          TextInput({ text: this.newBookmarkName, placeholder: I18n.t('c_bookmark_name_hint') })
            .fontSize(13).fontColor('#E5FFFFFF').placeholderColor('#99FFFFFF')
            .backgroundColor('rgba(255,255,255,0.06)').borderRadius(10)
            .height(36).layoutWeight(1).padding({ left: 10, right: 10 })
            .onChange((v: string) => { this.newBookmarkName = v })
          Button(I18n.t('btn_save_current_view'))
            .fontSize(12).fontColor('#E5FFFFFF')
            .backgroundColor('rgba(107,163,214,0.35)')
            .borderRadius(14).height(36).padding({ left: 14, right: 14 })
            .onClick(() => { this.addCurrentBookmark() })
        }.width('100%')
        if (this.selectedName.length > 0) {
          Row() {
            Text(I18n.t('bookmark_selected_object_hint') + ': ' + this.selectedName)
              .fontSize(12).fontColor('#99FFFFFF').layoutWeight(1)
            Button(I18n.t('btn_bookmark_object'))
              .fontSize(12).fontColor('#E5FFFFFF')
              .backgroundColor('rgba(91,147,191,0.35)')
              .borderRadius(14).height(36).padding({ left: 14, right: 14 })
              .onClick(() => { this.addCurrentBookmark() })
          }.width('100%').margin({ top: 4 })
        }
        if (this.bookmarkLoading) {
          Column() {
            Text(I18n.t('c_loading_bookmarks')).fontSize(13).fontColor('#99FFFFFF')
          }.width('100%').height(80).justifyContent(FlexAlign.Center)
        } else if (this.bookmarkList.length === 0) {
          Column() {
            Text(I18n.t('m_no_bookmarks')).fontSize(14).fontColor('#E5FFFFFF').margin({ top: 8 })
            Text(I18n.t('m_save_view_hint')).fontSize(12).fontColor('#CC8FB6FF').margin({ top: 6 })
          }.width('100%').height(100).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.bookmarkList, (b: BookmarkItem) => {
                Row() {
                  Column() {
                    Text(b.name)
                      .fontSize(14).fontColor('#E5FFFFFF').fontWeight(FontWeight.Medium)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text((b.object.length > 0 ? (b.object + ' · ') : '') + 'FOV ' + b.fov.toFixed(1) + '°')
                      .fontSize(11).fontColor('#99FFFFFF').margin({ top: 2 })
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                    .onClick(() => { this.gotoBookmark(b.id) })
                  Button(I18n.t('btn_delete'))
                    .fontSize(12).fontColor('#E5FFFFFF')
                    .backgroundColor('rgba(255,255,255,0.10)')
                    .borderRadius(14).height(32).padding({ left: 14, right: 14 })
                    .onClick(() => { this.deleteBookmark(b.id) })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .backgroundColor('rgba(255,255,255,0.04)')
                .borderRadius(12)
                .border({ width: 1, color: this.nmBorder() })
              }, (b: BookmarkItem) => b.id)
            }.width('100%').padding({ left: 2, right: 2 })
          }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
        }
      }.width('100%').layoutWeight(1)
    } else if (this.activePanel === 'oculars') {
      // 望远镜/目镜配置：目镜模式 + Telrad/十字丝/CCD 开关 + 配置选择器
      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Text(I18n.t('c_ocular_mode')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.ocularMode })
              .onChange((isOn: boolean) => { this.setOcularMode(isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_telrad')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.telradOn })
              .onChange((isOn: boolean) => { this.setTelrad(isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_crosshair')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.crosshairsOn })
              .onChange((isOn: boolean) => { this.setCrosshairs(isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_ccd_frame')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.ccdOn })
              .onChange((isOn: boolean) => { this.setCCD(isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          this.ocularSelector('Ocular', '目镜')
          this.ocularSelector('Telescope', '望远镜')
          this.ocularSelector('Lens', '镜片')
          this.ocularSelector('CCD', 'CCD')
        }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'satellites') {
      // 卫星：全局显示开关 + 分组列表
      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Text(I18n.t('c_total_count')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Text(this.satCount.toString()).fontSize(13).fontColor('#99FFFFFF')
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_show_labels')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.satLabels })
              .onChange((isOn: boolean) => { this.setSatelliteFlag('labels', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_show_orbits')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.satOrbitLines })
              .onChange((isOn: boolean) => { this.setSatelliteFlag('orbitLines', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_show_hints')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.satHints })
              .onChange((isOn: boolean) => { this.setSatelliteFlag('hints', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_icon_mode')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.satIconicMode })
              .onChange((isOn: boolean) => { this.setSatelliteFlag('iconicMode', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_hide_invisible')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.satHideInvisible })
              .onChange((isOn: boolean) => { this.setSatelliteFlag('hideInvisible', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          if (this.satGroups.length > 0) {
            Text(I18n.t('c_satellite_groups')).fontSize(12).fontColor('#99FFFFFF').width('100%').padding({ left: 2 }).margin({ top: 4 })
            ForEach(this.satGroups, (g: string) => {
              Row() {
                Text(this.satGroupZh(g)).fontSize(13).fontColor(this.activeSatGroup === g ? '#FF6644' : '#E5FFFFFF')
                if (this.activeSatGroup === g) {
                  Text(' ✓').fontSize(13).fontColor('#FF6644')
                }
              }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.activeSatGroup === g ? 'rgba(180, 40, 20, 0.25)' : this.nmBg()).borderRadius(12)
              .onClick(() => {
                if (this.activeSatGroup === g) {
                  this.activeSatGroup = ''
                  this.callNativeWhenReady('setSatellitesFlag', 'groupFilter:', () => { this.loadSatellites() })
                } else {
                  this.activeSatGroup = g
                  this.callNativeWhenReady('setSatellitesFlag', 'groupFilter:' + g, () => { this.loadSatellites() })
                }
              })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.animation({ duration: 300, curve: curves.springMotion(0.5, 1.0) })
                  .combine(TransitionEffect.translate({ y: 10 }).animation({ duration: 320, curve: curves.springMotion(0.5, 1.0) })),
                TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn })
                  .combine(TransitionEffect.translate({ y: 8 }).animation({ duration: 200, curve: Curve.EaseIn }))
              ))
            }, (g: string) => g)
          }
        }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'meteorshowers') {
      // 流星雨：插件总开关 + 标签/仅活跃/标记开关 + 活跃流星雨列表
      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Text(I18n.t('c_enable_meteor_plugin')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.msEnabled })
              .onChange((isOn: boolean) => { this.setMeteorShowersFlag('enabled', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_show_radiant_labels')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.msLabels })
              .onChange((isOn: boolean) => { this.setMeteorShowersFlag('labels', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_active_only')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.msActiveOnly })
              .onChange((isOn: boolean) => { this.setMeteorShowersFlag('activeOnly', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('c_show_radiant_markers')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.msMarker })
              .onChange((isOn: boolean) => { this.setMeteorShowersFlag('marker', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Text(I18n.t('meteor_radiant_desc'))
            .fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 4, right: 4 }).margin({ top: 4 })
          // 活跃流星雨列表
          Text(I18n.t('meteor_active_showers'))
            .fontSize(13).fontColor('#FFE9B0').width('100%').margin({ top: 8, bottom: 2 })
          if (this.msShowerList.length > 0) {
            ForEach(this.msShowerList, (s: MeteorShowerItem) => {
              Column({ space: 3 }) {
                Row({ space: 6 }) {
                  Text(s.name).fontSize(14).fontColor('#FFD54F').layoutWeight(1)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(s.zhr > 0 ? (I18n.t('meteor_zhr_label') + ' ' + s.zhr) : '').fontSize(12)
                    .fontColor('#BBDEFB').padding({ left: 6, right: 6 })
                    .backgroundColor('rgba(30, 60, 100, 0.5)').borderRadius(8)
                  Text(s.status === 'confirmed' ? 'Confirmed' : 'Generic').fontSize(10)
                    .fontColor(s.status === 'confirmed' ? '#81C784' : '#FFB74D')
                    .padding({ left: 4, right: 4 }).backgroundColor('rgba(255, 255, 255, 0.08)').borderRadius(6)
                }.width('100%')
                if (s.peakDate.length > 0) {
                  Row({ space: 8 }) {
                    Text(I18n.t('meteor_peak') + ': ' + this.fmtIso(s.peakDate)).fontSize(11).fontColor('#DDDDDD').layoutWeight(1)
                  }.width('100%')
                }
                if (s.activeStart.length > 0 && s.activeEnd.length > 0) {
                  Row({ space: 8 }) {
                    Text(I18n.t('meteor_active_range') + ': ' + this.fmtIso(s.activeStart) + ' ~ ' + this.fmtIso(s.activeEnd)).fontSize(11)
                      .fontColor('#AAAAAA').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.width('100%')
                }
                Row({ space: 12 }) {
                  if (s.speed > 0) {
                    Text(I18n.t('meteor_speed') + ': ' + s.speed + ' km/s').fontSize(11).fontColor('#999999')
                  }
                  if (s.parent.length > 0) {
                    Text(I18n.t('meteor_parent') + ': ' + s.parent).fontSize(11).fontColor('#999999')
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  }
                }.width('100%')
              }.width('100%').padding(10).backgroundColor('#1A2330').borderRadius(10).margin({ top: 2 })
                .stateStyles({ pressed: { backgroundColor: '#27384A' } })
                .onClick(() => {
                  if (s.englishName.length > 0) {
                    this.callNativeWhenReady('searchObject', s.englishName, () => {})
                  }
                })
                .transition(TransitionEffect.asymmetric(
                  TransitionEffect.OPACITY.animation({ duration: 300, curve: curves.springMotion(0.5, 1.0) })
                    .combine(TransitionEffect.translate({ y: 10 }).animation({ duration: 320, curve: curves.springMotion(0.5, 1.0) })),
                  TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn })
                    .combine(TransitionEffect.translate({ y: 8 }).animation({ duration: 200, curve: Curve.EaseIn }))
                ))
            }, (s: MeteorShowerItem) => s.englishName)
          } else {
            Text(I18n.t('meteor_no_active'))
              .fontSize(12).fontColor('#666666').width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
          }
        }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'scripts') {
      // 脚本面板：脚本列表 + 录制 / 回放（#39）
      Scroll() {
        Column({ space: 10 }) {
          // ===== 脚本播放列表 =====
          Text(I18n.t('i0123')).fontSize(15).fontColor(this.nmText()).width('100%').margin({ top: 4 })
          Row({ space: 8 }) {
            Button(I18n.t('i0252')).fontSize(11).fontColor('#FFFFFF').backgroundColor('#C0392B')
              .borderRadius(8).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.triggerAction('actionStop_Script') })
            Button(I18n.t('i0142')).fontSize(11).fontColor('#FFFFFF').backgroundColor('#E67E22')
              .borderRadius(8).height(30).padding({ left: 10, right: 10 })
              .enabled(false) // 引擎已移除 pause/resume 能力（上游 deprecated），按钮置灰禁用
              .opacity(0.4)
              .onClick(() => { this.pauseScript() })
            Button(I18n.t('btn_resume')).fontSize(11).fontColor('#FFFFFF').backgroundColor('#2E7D32')
              .borderRadius(8).height(30).padding({ left: 10, right: 10 })
              .enabled(false) // 同上，resume 亦不可用
              .opacity(0.4)
              .onClick(() => { this.resumeScript() })
          }.width('100%').padding({ left: 6, right: 6 })
          if (this.scriptList.length === 0) {
            Text(I18n.t('msg_no_scripts')).fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 6 })
          }
          Scroll() {
            Column({ space: 2 }) {
              ForEach(this.scriptList, (s: string) => {
                Column({ space: 0 }) {
                  // 第一行：中文名 + 播放图标
                  Row() {
                    Text(this.scriptZh(s)).fontSize(11).fontColor(this.nmText())
                      .fontWeight(FontWeight.Medium).layoutWeight(1)
                    Text('▶').fontSize(9).fontColor('#7FD0FF')
                  }
                  .height(28).width('100%').padding({ left: 10, right: 10 })
                  // 第二行：简短描述
                  if (this.scriptDesc(s)) {
                    Text(this.scriptDesc(s))
                      .fontSize(8).fontColor('#77FFFFFF').width('100%')
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .padding({ left: 10, right: 10, bottom: 3 })
                  }
                }
                .width('100%')
                .backgroundColor(this.nmBg())
                .borderRadius(6)
                .onClick(() => { this.playScriptByName(s) })
              }, (s: string, index: number) => s)
            }
          }.width('100%').height(160).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')

          Row().width('100%').height(0.5).backgroundColor(this.nmBorder()).margin({ top: 6, bottom: 6 })

          // ===== 录制操作 =====
          Text(I18n.t('c_script_record')).fontSize(15).fontColor(this.nmText()).width('100%').margin({ top: 4 })
          Text(I18n.t('m_script_record_desc'))
            .fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 4, right: 4 })

          Row({ space: 10 }) {
            Button(this.recording ? I18n.t('btn_stop_recording') : I18n.t('btn_start_recording'))
              .fontSize(13).fontColor('#FFFFFF').backgroundColor(this.recording ? '#C0392B' : '#2E7D32')
              .borderRadius(10).height(36).padding({ left: 16, right: 16 })
              .onClick(() => { this.recording ? this.stopRecording() : this.startRecording() })
            if (this.recording) {
              Text(I18n.t('c_recording')).fontSize(12).fontColor('#FF6B6B')
            }
          }.width('100%').padding({ left: 6, right: 6 })

          Text('已记录 ' + this.recordCount + ' 条命令' + (this.recordMsg.length > 0 ? ' · ' + this.recordMsg : ''))
            .fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 6, right: 6 })

          Row({ space: 8 }) {
            TextInput({ placeholder: I18n.t('c_record_name_hint'), text: this.recordName })
              .fontSize(12).fontColor(this.nmText())
              .backgroundColor(this.nmBg()).borderRadius(8).layoutWeight(1).height(36)
              .onChange((v: string) => { this.recordName = v })
            Button(I18n.t('btn_save_record'))
              .fontSize(12).fontColor('#FFFFFF').backgroundColor(this.recordCount > 0 ? '#5B93BF' : '#555555')
              .borderRadius(8).height(36).padding({ left: 12, right: 12 })
              .enabled(this.recordCount > 0)
              .onClick(() => { this.saveCurrentRecording() })
          }.width('100%').padding({ left: 6, right: 6 })

          Row().width('100%').height(0.5).backgroundColor(this.nmBorder()).margin({ top: 6, bottom: 6 })

          Text(I18n.t('c_saved_recordings')).fontSize(13).fontColor(this.nmText()).width('100%').padding({ left: 6 })
          if (this.recordings.length === 0) {
            Text(I18n.t('m_no_recordings')).fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 6 })
          }
          ForEach(this.recordings, (rec: RecordingEntry, idx: number) => {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Column() {
                  Text(rec.name).fontSize(13).fontColor(this.nmText()).width('100%')
                  Text((rec.created.length > 0 ? rec.created + ' · ' : '') + rec.count + ' 条命令')
                    .fontSize(10).fontColor('#99FFFFFF').width('100%')
                }.layoutWeight(1)
                Button(I18n.t('btn_playback'))
                  .fontSize(11).fontColor('#FFFFFF').backgroundColor('#5B93BF')
                  .borderRadius(8).height(30).padding({ left: 12, right: 12 })
                  .onClick(() => { this.playRecording(rec.file) })
                Button('加载')
                  .fontSize(11).fontColor('#FFFFFF').backgroundColor('#7D3C98')
                  .borderRadius(8).height(30).padding({ left: 12, right: 12 })
                  .onClick(() => { this.loadRecordingByName(rec.file, rec.name) })
                Button(I18n.t('btn_delete'))
                  .fontSize(11).fontColor('#FFFFFF').backgroundColor('#C0392B')
                  .borderRadius(8).height(30).padding({ left: 12, right: 12 })
                  .onClick(() => { this.deleteRecording(rec.file) })
              }.width('100%')
            }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 6 })
              .backgroundColor(this.nmBg()).borderRadius(12)
          }, (item: RecordingEntry, idx: number) => item.file)

          // ===== 视频录制（帧序列方案，#40）=====
          Row().width('100%').height(0.5).backgroundColor(this.nmBorder()).margin({ top: 6, bottom: 6 })
          Text(I18n.t('c_video_frames')).fontSize(13).fontColor(this.nmText()).width('100%').padding({ left: 6 })
          Text(I18n.t('m_video_frames_desc'))
            .fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 4, right: 4 })

          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(I18n.t('c_fps')).fontSize(10).fontColor('#99FFFFFF')
              TextInput({ placeholder: '1', text: this.videoFps })
                .fontSize(12).fontColor(this.nmText())
                .backgroundColor(this.nmBg()).borderRadius(8).width(72).height(34)
                .onChange((v: string) => { this.videoFps = v })
            }.width(72)
            Column({ space: 2 }) {
              Text(I18n.t('c_duration_sec')).fontSize(10).fontColor('#99FFFFFF')
              TextInput({ placeholder: '5', text: this.videoDuration })
                .fontSize(12).fontColor(this.nmText())
                .backgroundColor(this.nmBg()).borderRadius(8).width(72).height(34)
                .onChange((v: string) => { this.videoDuration = v })
            }.width(72)
            Button(this.videoRecording ? '停止录制' : '开始录制')
              .fontSize(13).fontColor('#FFFFFF').backgroundColor(this.videoRecording ? '#C0392B' : '#2E7D32')
              .borderRadius(10).height(36).layoutWeight(1).padding({ left: 16, right: 16 })
              .onClick(() => { this.videoRecording ? this.stopVideoRecording() : this.startVideoRecording() })
          }.width('100%').padding({ left: 6, right: 6 })

          if (this.videoRecording || this.videoFrameCount > 0) {
            Row({ space: 10 }) {
              if (this.videoRecording) {
                Text(I18n.t('c_recording')).fontSize(12).fontColor('#FF6B6B')
              }
              Text(I18n.t('c_captured') + ' ' + this.videoFrameCount + ' / ' + this.videoMaxFrames + ' ' + I18n.t('c_frames'))
                .fontSize(11).fontColor('#99FFFFFF')
            }.width('100%').padding({ left: 6, right: 6 })
          }
          if (this.videoDir.length > 0) {
            Text('存放目录：' + this.videoDir)
              .fontSize(10).fontColor('#99FFFFFF').width('100%').padding({ left: 6, right: 6 })
          }
        }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'observing') {
      // 观测列表独立面板
      Scroll() {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text(I18n.t('panel_observing_list')).fontSize(15).fontColor(this.nmText()).layoutWeight(1)
            if (this.observingList.length > 0) {
              Button(I18n.t('clear_all')).fontSize(11).fontColor('#FF6B6B').backgroundColor('rgba(255,107,107,0.12)')
                .borderRadius(16).height(26).padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.observingList = []
                  AppStorage.setOrCreate('observingList', JSON.stringify(this.observingList))
                  this.flashHint(I18n.t('i0302'))
                })
            }
          }.width('100%').padding({ left: 4, right: 4 })
          if (this.observingList.length === 0) {
            Column() {
              Text(I18n.t('obs_list_empty')).fontSize(13).fontColor('#99FFFFFF').margin({ top: 12 })
              Text(I18n.t('i0110')).fontSize(12).fontColor('#CC8FB6FF').margin({ top: 6 })
            }.width('100%').height(140).justifyContent(FlexAlign.Center)
          } else {
            ForEach(this.observingList, (name: string) => {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(this.zhNameOf(name)).fontSize(14).fontColor('#E5FFFFFF').fontWeight(FontWeight.Medium)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button(I18n.t('i0134')).fontSize(11).fontColor('#5B93BF').backgroundColor('rgba(91,147,191,0.18)')
                  .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                  .onClick(() => { this.searchObject(name) })
                Text('x').fontSize(13).fontColor('rgba(255,255,255,0.4)')
                  .width(28).height(28).textAlign(TextAlign.Center)
                  .onClick(() => {
                    const idx = this.observingList.indexOf(name)
                    if (idx >= 0) {
                      this.observingList.splice(idx, 1)
                      AppStorage.setOrCreate('observingList', JSON.stringify(this.observingList))
                    }
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor('rgba(255,255,255,0.04)')
              .borderRadius(12)
              .border({ width: 1, color: this.nmBorder() })
            }, (name: string) => name)
          }
        }.width('100%').padding({ left: 4, right: 4 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'audio') {
      // 音频控制面板
      Scroll() {
        Column({ space: 10 }) {
          Text(I18n.t('panel_audio_ctrl')).fontSize(15).fontColor(this.nmText()).width('100%').margin({ top: 4 })
          Row() {
            Text(I18n.t('audio_toggle')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.musicEnabled })
              .onChange((isOn: boolean) => {
                this.musicEnabled = isOn
                const engine = AudioEngine.getInstance()
                if (isOn) { engine.start().then(() => { engine.setMuted(false) }) } else { engine.setMuted(true) }
                this.persistMusicEnabled()
                this.flashHint(isOn ? I18n.t('music_on_hint') : I18n.t('music_off_hint'))
              })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row() {
            Text(I18n.t('audio_volume')).fontSize(13).fontColor('#E5FFFFFF').width(72)
            Text(Math.round(this.audioVolume * 100) + '%').fontSize(13).fontColor(this.nmText()).margin({ right: 8 })
            Slider({ value: this.audioVolume, min: 0, max: 1, step: 0.05, style: SliderStyle.OutSet })
              .width('40%')
              .blockColor(this.nmAccent())
              .trackColor(this.nmBg())
              .selectedColor(this.nmAccent())
              .showSteps(false)
              .onChange((val: number) => {
                this.audioVolume = val
                AudioEngine.getInstance().setVolume(val)
              })
          }.height(40).width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          if (!OFFLINE_APPGALLERY_BUILD) {
          Row() {
            Text(I18n.t('angle_measure')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Button(I18n.t('angle_measure'))
              .fontSize(12).fontColor('#FFFFFF').backgroundColor('#5B93BF')
              .borderRadius(14).height(32).padding({ left: 14, right: 14 })
              .onClick(() => { this.triggerAction('actionShow_Angle_Measure') })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Text(I18n.t('angle_measure_hint')).fontSize(10).fontColor('#99FFFFFF').width('100%').padding({ left: 10, right: 10 })
          Row() {
            Text(I18n.t('i0121')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Button(I18n.t('i0251'))
              .fontSize(12).fontColor('#FFFFFF').backgroundColor('#5B93BF')
              .borderRadius(14).height(32).padding({ left: 14, right: 14 })
              .onClick(() => { this.saveScreenshot() })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12)
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Text(I18n.t('session_export')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 4 })
          Button(I18n.t('session_export'))
            .fontSize(12).fontColor('#FFFFFF').backgroundColor('#5B93BF')
            .borderRadius(14).height(32).width('100%').padding({ left: 14, right: 14 })
            .onClick(() => { this.sessionExport() })
          Text(I18n.t('session_hint')).fontSize(10).fontColor('#99FFFFFF').width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
          if (this.sessionExportText.length > 0) {
            Scroll() {
              Text(this.sessionExportText).fontSize(9).fontColor('#99FFFFFF').width('100%').fontFamily('monospace')
            }.width('100%').height(100).backgroundColor(this.nmBg()).borderRadius(8).padding(8)
              .scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
          }
          Text(I18n.t('session_import')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 8, bottom: 4 })
          TextArea({ placeholder: 'Paste session JSON here', text: this.sessionImportText })
            .fontSize(10).fontColor(this.nmText())
            .placeholderColor('#8CFFFFFF')
            .backgroundColor(this.nmBg()).borderRadius(8)
            .width('100%').height(72)
            .onChange((v: string) => { this.sessionImportText = v })
          Button(I18n.t('session_import'))
            .fontSize(12).fontColor('#FFFFFF').backgroundColor('#5B93BF')
            .borderRadius(14).height(32).width('100%').padding({ left: 14, right: 14 })
            .onClick(() => { this.sessionApply() })
          if (this.sessionImportMsg.length > 0) {
            Text(this.sessionImportMsg).fontSize(10).fontColor('#FFAA00').width('100%')
          }
          }
        }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else {
      this.infoRow(I18n.t('i0057'), this.isExpandedLayout ? I18n.t('s0703') : I18n.t('s0704'))
      this.infoRow(I18n.t('i0058'), 'Stellarium Core')
      this.infoRow(I18n.t('i0059'), this.fovText)
      this.infoRow(I18n.t('i0060'), this.gyroscopeStatus)
      this.infoRow(I18n.t('i0061'), this.sensZh(this.gyroscopeSensitivityText))
      this.gyroscopeRow()
      if (!OFFLINE_APPGALLERY_BUILD) {
        this.lx200Panel()
      }
      this.languageRow()
      Row() {
        Text(I18n.t('set_distance_units'))
          .fontSize(14)
          .fontColor('#E5FFFFFF')
          .width(72)
        Row({ space: 6 }) {
          Text(I18n.t('unit_km'))
            .fontSize(12)
            .fontColor(this.useMetricUnits ? '#F4FAFF' : '#C8D4E2')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.useMetricUnits ? '#5B93BF' : 'rgba(255,255,255,0.06)')
            .borderRadius(8)
            .onClick(() => {
              this.useMetricUnits = true
              this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=true', () => {})
            })
          Text(I18n.t('unit_mile'))
            .fontSize(12)
            .fontColor(!this.useMetricUnits ? '#F4FAFF' : '#C8D4E2')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(!this.useMetricUnits ? '#5B93BF' : 'rgba(255,255,255,0.06)')
            .borderRadius(8)
            .onClick(() => {
              this.useMetricUnits = false
              this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=false', () => {})
            })
        }
      }
        .height(40)
        .width('100%')
      // 观测列表
      if (this.observingList.length > 0) {
        Row() {
          Text(I18n.t('i0022') + ' (' + this.observingList.length + ')')
            .fontSize(12).fontColor("#99FFFFFF")
          Text('').layoutWeight(1)
          Button(I18n.t('i0301'))
            .fontSize(11).fontColor("#FF6B6B").backgroundColor("rgba(255,107,107,0.12)")
            .borderRadius(16).height(26).padding({ left: 10, right: 10 })
            .onClick(() => {
              this.observingList = []
              AppStorage.setOrCreate("observingList", JSON.stringify(this.observingList))
              this.flashHint(I18n.t('i0302'))
            })
        }
        .height(34).width("100%").padding({ left: 10, right: 10 }).backgroundColor("rgba(255, 255, 255, 0.04)").borderRadius(12).margin({ bottom: 4 })
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.observingList, (name: string) => {
              Row({ space: 4 }) {
                Text(this.zhNameOf(name))
                  .fontSize(11).fontColor("#E5FFFFFF")
                Text('x')
                  .fontSize(9).fontColor("rgba(255,255,255,0.4)")
                  .onClick(() => {
                    const idx = this.observingList.indexOf(name)
                    if (idx >= 0) {
                      this.observingList.splice(idx, 1)
                      AppStorage.setOrCreate("observingList", JSON.stringify(this.observingList))
                    }
                  })
              }
              .padding({ left: 10, right: 6, top: 3, bottom: 3 })
              .backgroundColor("rgba(107,163,214,0.20)")
              .borderRadius(8)
              .onClick(() => {
                this.searchObject(name)
                this.flashHint(I18n.t('i0082'))
              })
            }, (name: string) => name)
          }.padding({ left: 4, right: 4 })
        }.width("100%").height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      this.infoRow(I18n.t('i0062'), I18n.t('s0706'))
      // 分区：方向
      Row()
        .width('100%').height(0.5)
        .backgroundColor('rgba(255,255,255,0.06)')
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text(I18n.t('i0275')).fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row() {
        this.quickChips([{ id: 'east', label: I18n.t('s0725') }, { id: 'south', label: I18n.t('s0726') }, { id: 'west', label: I18n.t('s0727') }, { id: 'north', label: I18n.t('s0728') }, { id: 'zenith', label: I18n.t('i0088') }, { id: 'ncp', label: I18n.t('i0089') }])
      }
      .width('100%')
      // 分区：视场
      Row()
        .width('100%').height(0.5)
        .backgroundColor('rgba(255,255,255,0.06)')
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text(I18n.t('i0276')).fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row() {
        this.quickChips([{ id: 'fov1', label: '1°' }, { id: 'fov2', label: '2°' }, { id: 'fov5', label: '5°' }, { id: 'fov10', label: '10°' }, { id: 'fov20', label: '20°' }, { id: 'fov45', label: '45°' }, { id: 'fov60', label: '60°' }, { id: 'fov90', label: '90°' }, { id: 'fov180', label: '180°' }])
      }
      .width('100%')
      // 天球投影切换
      Row() {
        Text(I18n.t('i0025')).fontSize(12).fontColor('#99FFFFFF').width(72)
        Text(this.equatorialMount ? I18n.t('i0008') : I18n.t('i0009'))
          .fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.equatorialMount })
          .onChange((isOn: boolean) => {
            this.equatorialMount = isOn
            this.triggerAction('actionSwitch_Equatorial_Mount')
            this.refreshState()
            this.flashHint(isOn ? I18n.t('i0008') : I18n.t('i0009'))
          })
      }
      .height(40).width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12).margin({ top: 4, bottom: 4 })
      // The offline release does not expose screenshots until the file is
      // written through a user-accessible media path.
      Row() {
        if (!OFFLINE_APPGALLERY_BUILD) {
          Button(I18n.t('i0048'))
            .fontSize(13).fontColor('#E5FFFFFF').backgroundColor('rgba(255,255,255,0.08)')
            .borderRadius(12).height(36).layoutWeight(1)
            .onClick(() => {
              this.saveScreenshot()
            })
        }
        Row() {
            Image($r(this.nightMode ? 'app.media.ic_moon' : 'app.media.ic_sun')).width(16).height(16).fillColor('#E5FFFFFF')
            Text(this.nightMode ? I18n.t('s0707') : I18n.t('s0708')).fontSize(12).fontColor('#E5FFFFFF').margin({ left: 4 })
          }
          .padding({ left: 10, right: 10 }).backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(12).height(36).layoutWeight(1).margin({ left: 8 })
          .onClick(() => {
            this.nightMode = !this.nightMode
            this.triggerAction('actionShow_Night_Mode')
            this.flashHint(this.nightMode ? I18n.t('s0707') : I18n.t('s0708'))
          })
      }
      .width('100%').margin({ top: 4, bottom: 4 })
      // 星空翻转
      Row() {
        Text(I18n.t('i0277')).fontSize(12).fontColor('#99FFFFFF').width(72)
        Row() {
              Image($r('app.media.ic_layers')).width(14).height(14).fillColor('#E5FFFFFF')
              Text(this.flipVert ? I18n.t('s0709') : I18n.t('s0710')).fontSize(11).fontColor('#E5FFFFFF').margin({ left: 3 })
            }
          .padding({ left: 8, right: 8 }).backgroundColor(this.flipVert ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.08)')
          .borderRadius(12).height(32).layoutWeight(1)
          .onClick(() => {
            this.flipVert = !this.flipVert
            this.triggerAction('actionVertical_Flip')
            this.flashHint(this.flipVert ? I18n.t('msg_flip_south_up') : I18n.t('msg_flip_north_up'))
          })
        Row() {
              Image($r('app.media.ic_refresh')).width(14).height(14).fillColor('#E5FFFFFF')
              Text(this.flipHoriz ? I18n.t('s0711') : I18n.t('s0712')).fontSize(11).fontColor('#E5FFFFFF').margin({ left: 3 })
            }
          .padding({ left: 8, right: 8 }).backgroundColor(this.flipHoriz ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.08)')
          .padding({ left: 8, right: 8 }).borderRadius(12).height(32).layoutWeight(1).margin({ left: 6 }).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.flipHoriz = !this.flipHoriz
            this.triggerAction('actionHorizontal_Flip')
            this.flashHint(this.flipHoriz ? I18n.t('s0711') : I18n.t('s0712'))
          })
      }
      .width('100%').padding({ left: 10, right: 10 }).margin({ top: 2, bottom: 4 })
      this.quickChips([{ id: 'refresh', label: I18n.t('s0721') }, { id: 'now', label: I18n.t('s0754') }])
      // 帮助说明
      Row() {
        Text(I18n.t('i0026')).fontSize(12).fontColor("#99FFFFFF").width(72)
      }
      .height(6).width("100%").margin({ top: 2 })
      Text(I18n.t('i0027'))
        .fontSize(11).fontColor("#99FFFFFF").width("100%").padding({ left: 4, right: 4 })
      Text(I18n.t('i0028'))
        .fontSize(11).fontColor("#99FFFFFF").width("100%").padding({ left: 4, right: 4 }).margin({ top: 2 })
      // 语言选择
      Row() {
        Text(I18n.t('i0029')).fontSize(12).fontColor("#99FFFFFF").width(72)
        Text(LANGUAGE_DISPLAY[this.selectedLanguage] ?? this.selectedLanguage)
          .fontSize(14).fontColor("#E5FFFFFF").layoutWeight(1)
      }
      .height(34).width("100%").padding({ left: 10, right: 10 }).backgroundColor("rgba(255, 255, 255, 0.04)").borderRadius(12).margin({ bottom: 4 })
      Scroll() {
        Row({ space: 6 }) {
          ForEach(SUPPORTED_LANGUAGES, (lang: string) => {
            Text(LANGUAGE_DISPLAY[lang] ?? lang)
              .fontSize(11).fontColor(this.selectedLanguage === lang ? "#F4FAFF" : "#C8D4E2")
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor(this.selectedLanguage === lang ? "rgba(107,163,214,0.35)" : "rgba(255,255,255,0.05)")
              .borderRadius(8)
              .onClick(() => this.setLanguage(lang))
          }, (lang: string) => lang)
        }.padding({ left: 4, right: 4 })
      }.width("100%").height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 8 })
      // Sky-culture selection is intentionally hidden in the offline release.
      if (!OFFLINE_APPGALLERY_BUILD && this.skyCultures.length > 0) {
        Row() {
          Text(I18n.t('i0035')).fontSize(12).fontColor("#99FFFFFF").width(72)
          Text(this.currentSkyCulture).fontSize(14).fontColor("#E5FFFFFF").layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .height(34).width("100%").padding({ left: 10, right: 10 }).backgroundColor("rgba(255, 255, 255, 0.04)").borderRadius(12).margin({ bottom: 4 })
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.skyCultures, (culture: string) => {
              Text(culture)
                .fontSize(11).fontColor(this.currentSkyCulture === culture ? "#FFFFFFFF" : "#99FFFFFF")
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.currentSkyCulture === culture ? "rgba(107,163,214,0.35)" : "rgba(255,255,255,0.05)")
                .borderRadius(8)
                .onClick(() => this.setSkyCulture(culture))
            }, (culture: string) => culture)
          }.padding({ left: 4, right: 4 })
        }.width("100%").height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
    }
  }

  @Builder
	  lx200Panel() {
	    Column() {
      Text(I18n.t('i0036'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E5FFFFFF')
        .width('100%')
      TextInput({ text: this.lx200Host, placeholder: I18n.t('i0064') })
        .height(38)
        .fontSize(13)
        .fontColor('#E5FFFFFF')
        .placeholderColor('#8EA0BD')
        .backgroundColor('rgba(255, 255, 255, 0.06)')
        .border({ width: 1, color: this.nmInputBorder() })
        .borderRadius(12)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.lx200Host = value
        })
      TextInput({ text: this.lx200Port, placeholder: I18n.t('i0065') })
        .height(38)
        .fontSize(13)
        .fontColor('#E5FFFFFF')
        .placeholderColor('#8EA0BD')
        .backgroundColor('rgba(255, 255, 255, 0.06)')
        .border({ width: 1, color: 'rgba(214, 238, 255, 0.14)' })
        .borderRadius(12)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.lx200Port = value
        })
      Row() {
        Button(I18n.t('i0049'))
          .height(32)
          .fontSize(12)
          .fontColor('#FFFFFFFF')
          .backgroundColor('#5B93BF')
          .borderRadius(16)
          .margin({ right: 8 })
          .onClick(() => {
            this.lx200GotoSelected()
          })
        Button(I18n.t('i0050'))
          .height(32)
          .fontSize(12)
          .fontColor('#7FB3DC')
          .backgroundColor('rgba(107, 163, 214, 0.20)')
          .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
          .borderRadius(16)
          .margin({ right: 8 })
          .onClick(() => {
            this.lx200SyncSelected()
          })
        Button(I18n.t('i0051'))
          .height(32)
          .fontSize(12)
          .fontColor('#FFD9D9')
          .backgroundColor('rgba(255, 121, 121, 0.14)')
          .border({ width: 1, color: 'rgba(255, 121, 121, 0.26)' })
          .borderRadius(16)
          .onClick(() => {
            this.lx200Abort()
          })
	      }
        .width('100%')
        .margin({ top: 10 })
      Text(this.lx200Status)
        .fontSize(11)
        .fontColor('#99FFFFFF')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })
    }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .backgroundColor('rgba(107, 163, 214, 0.12)')
      .border({ width: 1, color: 'rgba(107, 163, 214, 0.20)' })
	      .borderRadius(14)
	      .margin({ top: 8, bottom: 8 })
		  }

	  @Builder
  locationPickerPanel() {
    Column() {
      Row() {
        Text(I18n.t('i0037'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E5FFFFFF')
          .layoutWeight(1)
        Row() {
            Image($r('app.media.ic_location')).width(14).height(14).fillColor('#FFFFFFFF')
            Text(I18n.t('i0052')).fontSize(11).fontColor('#FFFFFFFF').margin({ left: 4 })
          }
          .height(30)
          .padding({ left: 12, right: 12 })
          .backgroundColor('#5B93BF')
          .borderRadius(15)
          .onClick(() => {
	            this.useDeviceLocation()
	          })
      }
        .width('100%')

      Row() {
        this.locationModeChip('map', I18n.t('s0715'))
        this.locationModeChip('hierarchy', I18n.t('s0716'))
      }
        .width('100%')
        .margin({ top: 10 })

      if (this.locationPickMode === 'map') {
        TextInput({ text: this.locationPickerName === I18n.t('custom_location') ? '' : this.locationPickerName, placeholder: I18n.t('i0066') })
          .height(36)
          .fontSize(13)
          .fontColor('#E5FFFFFF')
          .placeholderColor(this.nmSub())
          .backgroundColor(this.nmInput())
          .border({ width: 1, color: 'rgba(214, 238, 255, 0.14)' })
          .borderRadius(12)
          .margin({ top: 10 })
          .onChange((value: string) => {
            this.locationPickerName = value.length > 0 ? value : I18n.t('custom_location')
          })
        Stack() {
          Image($rawfile('worldmap.jpg'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
          // 经纬度刻度
          Text('N').fontSize(9).fontColor('#99FFFFFF').position({ x: 6, y: 4 })
          Text('S').fontSize(9).fontColor('#99FFFFFF').position({ x: 6, y: this.mapRenderHeight - 16 })
          Text('90°W').fontSize(8).fontColor('#CC8FB6FF').position({ x: 4, y: Math.round(this.mapRenderHeight / 2) - 4 })
          Text('90°E').fontSize(8).fontColor('#CC8FB6FF').position({ x: this.mapRenderWidth - 32, y: Math.round(this.mapRenderHeight / 2) - 4 })
          Text(I18n.t('i0040'))
            .fontSize(18)
            .fontColor('#7FB3DC')
            .textShadow({ radius: 8, color: 'rgba(159, 232, 255, 0.75)', offsetX: 0, offsetY: 0 })
            .position({ x: this.pickerPinX(), y: this.pickerPinY() })
        }
          .width(this.locationMapWidth())
          .height(this.locationMapHeight())
          .alignSelf(ItemAlign.Center)
          .clip(true)
          .hitTestBehavior(HitTestMode.Block)
          .backgroundColor('rgba(11, 24, 43, 0.46)')
          .border({ width: 1, color: 'rgba(159, 232, 255, 0.22)' })
          .borderRadius(14)
          .margin({ top: 10 })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            this.mapRenderWidth = Number(newArea.width)
            this.mapRenderHeight = Number(newArea.height)
          })
          .onTouch((event: TouchEvent) => {
            this.stopMapTouchPropagation(event)
          })
          .priorityGesture(
            PanGesture()
              .onActionStart((event: GestureEvent) => {
                this.mapPanStart()
              })
              .onActionUpdate((event: GestureEvent) => {
                this.mapPanUpdate(event.fingerList[0].localX, event.fingerList[0].localY)
              })
              .onActionEnd(() => {
                this.mapPanEnd()
              }),
            GestureMask.IgnoreInternal
          )
        Text(this.pickerCoordinateText())
          .fontSize(12)
          .fontColor('#99FFFFFF')
          .width('100%')
          .margin({ top: 8 })
      } else {
        Column() {
          Row() {
            this.hierColumn('continent', this.hierContinent, (c: string) => this.selectContinent(c))
            this.hierColumn('region', this.hierRegion, (r: string) => this.selectRegion(r))
            this.hierColumn('city', this.hierCity, (c: string) => this.selectCityByName(c))
          }
            .width('100%')
            .height(196)
          Text(this.hierarchySelectionSummary())
            .fontSize(11)
            .fontColor(this.hierContinent ? '#A9D9F5' : '#7F96AE')
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 7 })
          Text(this.pickerCoordinateText())
            .fontSize(12)
            .fontColor('#99FFFFFF')
            .width('100%')
            .margin({ top: 8 })
        }
          .width('100%')
          .margin({ top: 10 })
      }

      Row() {
        Text(I18n.t('i0016')).fontSize(12).fontColor('#8EA0BD').width(56)
        TextInput({ text: this.locationPickerAltitude.toFixed(0), placeholder: I18n.t('i0067') })
          .height(34)
          .fontSize(13)
          .fontColor('#E5FFFFFF')
          .placeholderColor('#8EA0BD')
          .backgroundColor('rgba(255, 255, 255, 0.06)')
          .border({ width: 1, color: 'rgba(214, 238, 255, 0.14)' })
          .borderRadius(12)
          .layoutWeight(1)
          .onChange((value: string) => {
            const altitude = Number(value)
            if (Number.isFinite(altitude)) {
              this.locationPickerAltitude = Math.round(altitude)
            }
          })
        Text('m').fontSize(11).fontColor('#8EA0BD').margin({ left: 6 })
      }
      .width('100%')
      .margin({ top: 8 })
      // 时区显示
      if (this.observerTimeZone.length > 0) {
        Row() {
          Text(I18n.t('loc_timezone')).fontSize(11).fontColor('#8EA0BD')
          Text(this.observerTimeZone).fontSize(11).fontColor('#7FB3DC').margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      Row() {
        Row() {
            Image($r('app.media.ic_globe')).width(14).height(14).fillColor('#FFFFFFFF')
            Text(I18n.t('i0053')).fontSize(12).fontColor('#FFFFFFFF').margin({ left: 4 })
          }
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor('#5B93BF')
          .borderRadius(16)
          .margin({ right: 8 })
          .onClick(() => {
            this.applyPickerLocation()
          })
        Text(this.locationPickerStatus)
          .fontSize(11)
          .fontColor('#99FFFFFF')
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
        .width('100%')
        .margin({ top: 9 })
    }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .backgroundColor('rgba(107, 163, 214, 0.12)')
      .border({ width: 1, color: 'rgba(107, 163, 214, 0.20)' })
      .borderRadius(14)
      .margin({ top: 8, bottom: 8 })
  }

  @Builder
  lx200ObjectControls() {
    Column() {
      Row() {
        Text(I18n.t('i0041'))
          .fontSize(12)
          .fontColor('#8EA0BD')
          .layoutWeight(1)
      }
        .width('100%')
      Row() {
	        Button(I18n.t('i0049'))
	          .height(32)
	          .fontSize(12)
	          .fontColor('#FFFFFFFF')
	          .backgroundColor('#5B93BF')
	          .borderRadius(16)
	          .margin({ right: 8 })
	          .onClick(() => {
	            this.lx200GotoSelected()
	          })
	        Button(I18n.t('i0050'))
	          .height(32)
	          .fontSize(12)
	          .fontColor('#7FB3DC')
	          .backgroundColor('rgba(107, 163, 214, 0.20)')
	          .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
	          .borderRadius(16)
	          .margin({ right: 8 })
	          .onClick(() => {
	            this.lx200SyncSelected()
	          })
	        Button(I18n.t('i0051'))
	          .height(32)
	          .fontSize(12)
	          .fontColor('#FFD9D9')
	          .backgroundColor('rgba(255, 121, 121, 0.14)')
	          .border({ width: 1, color: 'rgba(255, 121, 121, 0.26)' })
	          .borderRadius(16)
	          .onClick(() => {
	            this.lx200Abort()
	          })
	      }
	        .width('100%')
	        .margin({ top: 8 })
	      Text(this.lx200Status)
	        .fontSize(11)
	        .fontColor('#99FFFFFF')
	        .width('100%')
	        .maxLines(2)
	        .textOverflow({ overflow: TextOverflow.Ellipsis })
	        .margin({ top: 8 })
	    }
	      .width('100%')
	      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
	      .backgroundColor('rgba(107, 163, 214, 0.12)')
	      .border({ width: 1, color: 'rgba(107, 163, 214, 0.20)' })
	      .borderRadius(14)
	      .margin({ top: 8, bottom: 8 })
	  }

	  @Builder
  lockRow() {
    Row() {
      Text(I18n.t('i0042'))
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.uiLocked })
        .width(46)
        .height(28)
        .selectedColor('#5B93BF')
        .onChange((value: boolean) => {
          this.uiLocked = value
          this.flashHint(value ? I18n.t('s0717') : I18n.t('s0718'))
        })
    }
      .height(40)
      .width('100%')
  }

  @Builder
  languageRow() {
    Row() {
      Text(I18n.t('i0029'))
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .width(72)
      Scroll() {
        Row({ space: 6 }) {
          ForEach(SUPPORTED_LANGUAGES.map((code: string) => ({
            code: code,
            name: LANGUAGE_DISPLAY[code] ?? code
          })), (lang: LangOption) => {
            Text(lang.name)
              .fontSize(12)
              .fontColor(this.selectedLanguage === lang.code ? '#F4FAFF' : '#C8D4E2')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.selectedLanguage === lang.code ? '#5B93BF' : 'rgba(255,255,255,0.06)')
              .borderRadius(8)
              .onClick(() => { this.setLanguage(lang.code) })
          }, (lang: LangOption) => lang.code)
        }
        .padding({ left: 4, right: 4 })
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .height(40)
    .width('100%')
  }

  @Builder
	  gyroscopeRow() {
    Row() {
      Text(I18n.t('i0043'))
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.gyroscopeEnabled })
        .width(46)
        .height(28)
        .selectedColor('#5B93BF')
        .onChange((value: boolean) => {
          this.toggleGyroscope(value)
          this.flashHint(value ? I18n.t('s0719') : I18n.t('s0720'))
        })
    }
      .height(40)
      .width('100%')
  }

  @Builder
  quickChips(items: ChipItem[]) {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(items, (item: ChipItem) => {
          Button(item.label)
            .fontSize(12)
            .fontColor('#7FB3DC')
            .fontWeight(FontWeight.Medium)
            .height(32)
            .padding({ left: 14, right: 14 })
            .backgroundColor('rgba(107, 163, 214, 0.20)')
            .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
            .borderRadius(16)
            .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.18)', offsetX: 0, offsetY: 5 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
            .onClick(() => {
              this.handleChip(item.id)
            })
        }, (item: ChipItem) => item.id)
      }
      .padding({ left: 1, right: 12 })
    }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .margin({ top: 12 })
  }

  // 时间速度控制按钮 — 参考 Sky Guide 的交互范式
  // 布局：[倒带] [现在] [停止] [实时] [快进] [超快]
  // 当前档位高亮，点击立即更新速度显示
  @Builder
  timeSpeedChips() {
    Scroll() {
      Row({ space: 5 }) {
        // 倒带 — 单按钮循环升档：-1x → -2x → -10x → -1分/秒 → -1时/秒 → -10天/秒 → 回到-1x
        // 倒带与减速都显示当前反向倍率，避免用户无法判断“减速”是否已生效。
        this.speedChip('rewind',
          this.timeSpeedIndex < 6 ? I18n.t('s0763_rewind') + ' ' + this.timeRateText : I18n.t('s0763_rewind'),
          'ic_time_rewind.svg', this.timeSpeedIndex < 6)
        // 停止 — 冻结时间
        this.speedChip('stop', I18n.t('s0761_stop'), 'ic_time_stop.svg', this.timeSpeedIndex === 6)
        // 实时 — 回到当前时刻 + 1x
        this.speedChip('realtime', I18n.t('s0764_realtime'), 'ic_time_realtime.svg', this.timeSpeedIndex === 7)
        // 减速 — 每点降一档；降到1x再点=停止
        this.speedChip('slower',
          this.timeSpeedIndex < 6 ? I18n.t('s0759_slower') + ' ' + this.timeRateText : I18n.t('s0759_slower'),
          'ic_time_slower.svg', false)
        // 快进 — 单按钮循环升档：1x → 2x → 10x → 1分/秒 → 1时/秒 → 1天/秒 → 10天/秒 → 回到1x
        // 激活时标签直接显示当前档位速度
        this.speedChip('fast',
          this.timeSpeedIndex > 7 ? I18n.t('s0765_fast') + ' ' + this.timeRateText : I18n.t('s0765_fast'),
          'ic_time_fast.svg', this.timeSpeedIndex > 7)
      }
      .padding({ left: 2, right: 10 })
    }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .margin({ top: 8 })
  }

  // ===== Sky Guide 风格：按字段选择的时间转轴 =====
  @Builder
  timeScrubberSlider() {
    Column({ space: 8 }) {
      Row() {
        Text('时间转轴')
          .fontSize(11).fontColor('rgba(180, 210, 235, 0.7)')
      }
      .width('100%')

      // 顶部字段即视频中的日期时间条：先点字段，再用下方单一转轴调节。
      Row({ space: 1 }) {
        this.timeWheelYearField()
        this.timeWheelMonthField()
        this.timeWheelDayField()
        this.timeWheelHourField()
        this.timeWheelMinuteField()
        this.timeWheelSecondField()
      }
      .width('100%').height(40).justifyContent(FlexAlign.Center).padding({ left: 4, right: 4 })
      .backgroundColor('rgba(7, 12, 20, 0.74)')
      .border({ width: 1, color: 'rgba(190, 220, 240, 0.18)' })
      .borderRadius(20)

      Stack({ alignContent: Alignment.Center }) {
        Row() {
          ForEach(this.timeWheelTickLabels, (_label: string, index: number) => {
            Column({ space: 2 }) {
              Text(this.timeWheelVisibleTickLabel(index)).maxLines(1).minFontSize(8)
                .fontSize(this.timeWheelUnit === 'year' ? 10 : 12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#E7F3FC')
                .textAlign(TextAlign.Center).width(42).height(16)
                .opacity(this.timeWheelTickOpacity(index))
                .scale({ x: this.timeWheelTickScale(index), y: this.timeWheelTickScale(index) })
              Stack({ alignContent: Alignment.Bottom }) {
                Column()
                  .width(1)
                  .height(this.timeWheelTickHeight(index))
                  .backgroundColor('#D9EDFA')
                  .opacity(this.timeWheelTickOpacity(index))
              }
                .width(2)
                .height(31)
            }
              .width(this.timeWheelTickSpacing)
              .height(56)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .blur(this.timeWheelTickBlur(index))
          }, (_label: string, index: number) => 'time-wheel-tick-' + index.toString())
        }
        .width(this.timeWheelTickSpacing * (this.timeWheelCenterTick * 2 + 1))
        .translate({ x: this.timeWheelVisualOffset, y: 0 })
        .align(Alignment.Center)
        .hitTestBehavior(HitTestMode.None)

        Column()
          .width('100%')
          .height(56)
          .backgroundColor('rgba(0, 0, 0, 0)')
          .onTouch((event: TouchEvent) => { this.handleTimeWheelTouch(event) })
      }
      .width('100%')
      .height(56)
      .padding({ left: 10, right: 10 })
      .backgroundColor('rgba(12, 18, 29, 0.76)')
      .border({ width: 1, color: 'rgba(190, 220, 240, 0.24)' })
      .borderRadius(28)
      .clip(true)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 8 })
  }

  @Builder
  timeWheelYearField() {
    Button() {
      Row() {
        Text(this.timeWheelYear.toString()).maxLines(1).minFontSize(10).fontSize(this.timeWheelUnit === 'year' ? 14 : 12)
          .fontWeight(this.timeWheelUnit === 'year' ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.timeWheelUnit === 'year' ? '#FFFFFF' : '#BDD1E1')
      }.justifyContent(FlexAlign.Center).width('100%')
    }
      .width(47).height(32)
      .padding({ left: 1, right: 1 })
      .backgroundColor(this.timeWheelUnit === 'year' ? 'rgba(185, 204, 220, 0.34)' : 'rgba(0, 0, 0, 0)')
      .borderRadius(16)
      .onClick(() => { this.selectTimeWheelUnit('year') })
  }

  @Builder
  timeWheelMonthField() {
    Button() {
      Text(this.timeWheelMonth.toString().padStart(2, '0') + '月').maxLines(1).minFontSize(10).fontSize(this.timeWheelUnit === 'month' ? 14 : 12)
        .fontWeight(this.timeWheelUnit === 'month' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.timeWheelUnit === 'month' ? '#FFFFFF' : '#BDD1E1').textAlign(TextAlign.Center).width('100%')
    }
      .width(34).height(32).padding({ left: 1, right: 1 })
      .backgroundColor(this.timeWheelUnit === 'month' ? 'rgba(185, 204, 220, 0.34)' : 'rgba(0, 0, 0, 0)')
      .borderRadius(16).onClick(() => { this.selectTimeWheelUnit('month') })
  }

  @Builder
  timeWheelDayField() {
    Button() {
      Text(this.timeWheelDay.toString().padStart(2, '0') + '日').maxLines(1).minFontSize(10).fontSize(this.timeWheelUnit === 'day' ? 14 : 12)
        .fontWeight(this.timeWheelUnit === 'day' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.timeWheelUnit === 'day' ? '#FFFFFF' : '#BDD1E1').textAlign(TextAlign.Center).width('100%')
    }
      .width(34).height(32).padding({ left: 1, right: 1 })
      .backgroundColor(this.timeWheelUnit === 'day' ? 'rgba(185, 204, 220, 0.34)' : 'rgba(0, 0, 0, 0)')
      .borderRadius(16).onClick(() => { this.selectTimeWheelUnit('day') })
  }

  @Builder
  timeWheelHourField() {
    Button() {
      Text(this.timeWheelHour.toString().padStart(2, '0') + ':').maxLines(1).minFontSize(10).fontSize(this.timeWheelUnit === 'hour' ? 14 : 12)
        .fontWeight(this.timeWheelUnit === 'hour' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.timeWheelUnit === 'hour' ? '#FFFFFF' : '#BDD1E1').textAlign(TextAlign.Center).width('100%')
    }
      .width(30).height(32).padding({ left: 1, right: 1 })
      .backgroundColor(this.timeWheelUnit === 'hour' ? 'rgba(185, 204, 220, 0.34)' : 'rgba(0, 0, 0, 0)')
      .borderRadius(16).onClick(() => { this.selectTimeWheelUnit('hour') })
  }

  @Builder
  timeWheelMinuteField() {
    Button() {
      Text(this.timeWheelMinute.toString().padStart(2, '0') + ':').maxLines(1).minFontSize(10).fontSize(this.timeWheelUnit === 'minute' ? 14 : 12)
        .fontWeight(this.timeWheelUnit === 'minute' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.timeWheelUnit === 'minute' ? '#FFFFFF' : '#BDD1E1').textAlign(TextAlign.Center).width('100%')
    }
      .width(30).height(32).padding({ left: 1, right: 1 })
      .backgroundColor(this.timeWheelUnit === 'minute' ? 'rgba(185, 204, 220, 0.34)' : 'rgba(0, 0, 0, 0)')
      .borderRadius(16).onClick(() => { this.selectTimeWheelUnit('minute') })
  }

  @Builder
  timeWheelSecondField() {
    Button() {
      Text(this.timeWheelSecond.toString().padStart(2, '0')).maxLines(1).minFontSize(10).fontSize(this.timeWheelUnit === 'second' ? 14 : 12)
        .fontWeight(this.timeWheelUnit === 'second' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.timeWheelUnit === 'second' ? '#FFFFFF' : '#BDD1E1').textAlign(TextAlign.Center).width('100%')
    }
      .width(26).height(32).padding({ left: 1, right: 1 })
      .backgroundColor(this.timeWheelUnit === 'second' ? 'rgba(185, 204, 220, 0.34)' : 'rgba(0, 0, 0, 0)')
      .borderRadius(16).onClick(() => { this.selectTimeWheelUnit('second') })
  }

  @Builder
  speedChip(id: string, label: string, icon: string | null, active: boolean) {
    Row({ space: 4 }) {
      if (icon) {
        // 用 $r 引用 media 资源（$rawfile 读的是 rawfile/ 目录，不是 media/）
        Image($r('app.media.' + icon.replace('.svg', '')))
          .width(14)
          .height(14)
          .fillColor(active ? '#FFFFFF' : '#7FB3DC')
      }
      Text(label)
        .fontSize(11.5)
        .fontWeight(active ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(active ? '#FFFFFF' : '#B8D4EF')
    }
      .height(32)
      // 内边距收紧：保证 倒带/停止/实时/减速/快进 五个按钮在 360vp 宽屏上一屏排下，
      // 否则最右的「快进」会被挤出可视区，用户只能点到「减速」（曾导致误以为快进=暂停）
      .padding({ left: 7, right: 7 })
      .borderRadius(16)
      .backgroundColor(active ? 'rgba(79, 148, 211, 0.55)' : 'rgba(107, 163, 214, 0.15)')
      .border({ width: active ? 1.2 : 0.6, color: active ? 'rgba(127, 179, 220, 0.7)' : 'rgba(127, 179, 220, 0.22)' })
      .shadow(active ? { radius: 10, color: 'rgba(49, 120, 200, 0.25)', offsetX: 0, offsetY: 3 } : { radius: 8, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 4 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
      .onClick(() => { this.handleChip(id) })
  }  @Builder
  cityChipsRow() {
    Column({ space: 4 }) {
      // 城市搜索框
      Row() {
        TextInput({ text: this.locSearchQuery, placeholder: I18n.t('loc_search_placeholder') })
          .height(34)
          .fontSize(12)
          .fontColor('#E5FFFFFF')
          .placeholderColor('#8EA0BD')
          .backgroundColor('rgba(255, 255, 255, 0.06)')
          .border({ width: 1, color: 'rgba(214, 238, 255, 0.14)' })
          .borderRadius(12)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.locSearchQuery = value
            if (value.trim().length >= 1) {
              clearTimeout(this.locSearchDebounce)
              this.locSearchDebounce = setTimeout(() => {
                this.searchLocations(value)
              }, 300)
            } else {
              this.locSearchResults = []
            }
          })
        if (this.locSearching) {
          LoadingProgress()
            .width(18).height(18)
            .color('#7FB3DC')
            .margin({ left: 8 })
        }
      }
      .width('100%')

      // 搜索结果列表
      if (this.locSearchResults.length > 0) {
        Text(I18n.t('loc_search_results')).fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 2 }).margin({ top: 6 })
        Column({ space: 4 }) {
          ForEach(this.locSearchResults, (item: LocSearchItem) => {
            Row() {
              Column() {
                Text(item.name).fontSize(12).fontColor('#E5FFFFFF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.formatDegrees(item.lat, 'N', 'S') + ' / ' + this.formatDegrees(item.lon, 'E', 'W'))
                  .fontSize(10).fontColor('#8EA0BD')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Image($r('app.media.ic_location')).width(14).height(14).fillColor('#7FB3DC')
            }
            .width('100%')
            .height(44)
            .padding({ left: 10, right: 10 })
            .backgroundColor('rgba(107, 163, 214, 0.10)')
            .border({ width: 1, color: 'rgba(107, 163, 214, 0.15)' })
            .borderRadius(10)
            .onClick(() => { this.selectSearchLocation(item) })
          }, (item: LocSearchItem) => item.name + item.lat.toString())
        }
        .width('100%')
      } else if (this.locSearchQuery.trim().length > 0 && !this.locSearching) {
        Text(I18n.t('loc_no_results')).fontSize(11).fontColor('#8EA0BD').width('100%').padding({ left: 2, top: 6 })
      }

      // 已保存位置
      Row() {
        Text(I18n.t('loc_saved_locations')).fontSize(11).fontColor('#99FFFFFF').layoutWeight(1)
        Button(I18n.t('loc_save_current'))
          .fontSize(10).fontColor('#7FB3DC')
          .height(26).padding({ left: 8, right: 8 })
          .backgroundColor('rgba(107, 163, 214, 0.15)')
          .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
          .borderRadius(13)
          .onClick(() => { this.saveCurrentLocation() })
      }
      .width('100%')
      .margin({ top: 6 })

      if (this.savedLocations.length === 0) {
        Text(I18n.t('loc_no_saved')).fontSize(10).fontColor('#8EA0BD').width('100%').padding({ left: 2 })
      } else {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.savedLocations, (s: SavedLocation) => {
              Row() {
                Button(s.name)
                  .fontSize(10).fontColor('#7FB3DC')
                  .height(28).padding({ left: 8, right: 8 })
                  .backgroundColor('rgba(107, 163, 214, 0.20)')
                  .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
                  .borderRadius(14)
                  .onClick(() => { this.setLocation(s.name, s.lat, s.lon, s.alt) })
                Text('x')
                  .fontSize(10).fontColor('#FF9999')
                  .margin({ left: 2 })
                  .onClick(() => { this.deleteSavedLocation(s.name) })
              }
            }, (s: SavedLocation) => s.name)
          }
          .padding({ left: 2, right: 2 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }

      // 中国城市
      Text('中国城市').fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 2 }).margin({ top: 6 })
      Scroll() {
        Row({ space: 8 }) {
          ForEach([
            { label: '北京', id: 'city_Beijing' }, { label: '上海', id: 'city_Shanghai' },
            { label: '广州', id: 'city_Guangzhou' }, { label: '深圳', id: 'city_Shenzhen' },
            { label: '成都', id: 'city_Chengdu' }, { label: '杭州', id: 'city_Hangzhou' },
            { label: '武汉', id: 'city_Wuhan' }, { label: '西安', id: 'city_Xian' },
            { label: '南京', id: 'city_Nanjing' }, { label: '重庆', id: 'city_Chongqing' },
            { label: '哈尔滨', id: 'city_Harbin' }, { label: '拉萨', id: 'city_Lhasa' },
            { label: '乌鲁木齐', id: 'city_Urumqi' }, { label: '香港', id: 'city_HongKong' },
          ], (c: Record<string, string>) => {
            Button(c.label)
              .fontSize(11).fontColor('#7FB3DC').fontWeight(FontWeight.Medium)
              .height(30).padding({ left: 10, right: 10 })
              .backgroundColor('rgba(107, 163, 214, 0.20)')
              .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
              .borderRadius(16)
              .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.18)', offsetX: 0, offsetY: 4 })
              .onClick(() => { this.handleChip(c.id) })
          }, (c: Record<string, string>) => c.id)
        }
        .padding({ left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      // 世界城市
      Text('世界城市').fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 2 }).margin({ top: 4 })
      Scroll() {
        Row({ space: 8 }) {
          ForEach([
            { label: '东京', id: 'city_Tokyo' }, { label: '首尔', id: 'city_Seoul' },
            { label: '新加坡', id: 'city_Singapore' }, { label: '纽约', id: 'city_NewYork' },
            { label: '伦敦', id: 'city_London' }, { label: '悉尼', id: 'city_Sydney' },
            { label: '巴黎', id: 'city_Paris' }, { label: '柏林', id: 'city_Berlin' },
            { label: '莫斯科', id: 'city_Moscow' }, { label: '迪拜', id: 'city_Dubai' },
            { label: '孟买', id: 'city_Mumbai' }, { label: '开罗', id: 'city_Cairo' },
            { label: '里约', id: 'city_Rio' }, { label: '洛杉矶', id: 'city_LosAngeles' },
            { label: '多伦多', id: 'city_Toronto' }, { label: '墨西哥城', id: 'city_Mexico' },
            { label: '曼谷', id: 'city_Bangkok' }, { label: '伊斯坦布尔', id: 'city_Istanbul' },
            { label: '阿姆斯特丹', id: 'city_Amsterdam' }, { label: '斯德哥尔摩', id: 'city_Stockholm' },
            { label: '雷克雅未克', id: 'city_Reykjavik' }, { label: '开普敦', id: 'city_CapeTown' },
            { label: '布宜诺斯艾利斯', id: 'city_BuenosAires' }, { label: '檀香山', id: 'city_Honolulu' },
          ], (c: Record<string, string>) => {
            Button(c.label)
              .fontSize(11).fontColor('#7FB3DC').fontWeight(FontWeight.Medium)
              .height(30).padding({ left: 10, right: 10 })
              .backgroundColor('rgba(107, 163, 214, 0.20)')
              .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
              .borderRadius(16)
              .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.18)', offsetX: 0, offsetY: 4 })
              .onClick(() => { this.handleChip(c.id) })
          }, (c: Record<string, string>) => c.id)
        }
        .padding({ left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .margin({ top: 12 })
  }
  /**
   * 时间类操作后刷新「时间/速度」显示。
   * 立即刷一次（响应快），350ms 后再刷一次（引擎异步应用 JD/timeRate 需要时间窗口）。
   */
  private refreshTimeNow(): void {
    this.refreshState()
    // 注意：此处必须是 setTimeout(refreshState)，绝不能调 refreshTimeNow 自身（会无限递归栈溢出）
    setTimeout(() => { this.refreshState() }, 350)
  }

  private handleChip(id: string): void {
    if (id === 'refresh') {
      this.refreshSelectedObject()
      this.refreshState()
    } else if (id === 'center' || id === 'track') {
      this.moveToSelectedObject()
    } else if (id === 'untrack') {
      this.callInteractive('setTracking', '0', () => { this.refreshState() })
    } else if (id === 'now') {
      // 现在：回到当前时刻 + 重置为1x
      this.triggerAction('actionReturn_To_Current_Time')
      this.applySpeedStep(7) // SPEED_IDX_REALTIME
      this.timeRateText = '1x'
      this.resetScrubberToRealtime()
      this.refreshTimeNow()
    } else if (id === 'stop') {
      // 停止：冻结时间
      this._lastNonZeroSpeedIndex = this.timeSpeedIndex !== 6 ? this.timeSpeedIndex : 7
      this.applySpeedStep(6) // SPEED_IDX_STOP
      this.refreshTimeNow()
    } else if (id === 'realtime') {
      // 实时：回到当前时刻 + 恢复 1x 正常速度
      this.triggerAction('actionReturn_To_Current_Time')
      this.applySpeedStep(7) // SPEED_IDX_REALTIME
      this.timeRateText = '1x'
      this.resetScrubberToRealtime()
      this.refreshTimeNow()
    } else if (id === 'rewind') {
      // 倒带：单按钮循环升档 -1x → -2x → -10x → -1分/秒 → -1时/秒 → -1天/秒 → 回到-1x
      let rewIdx = 5 // 默认从 -1x 起步（非倒带状态按下时）
      if (this.timeSpeedIndex < 6) {
        // 已在倒带中：再点升一档（索引减小=更快反向）；到底(0)循环回 -1x
        rewIdx = this.timeSpeedIndex === 0 ? 5 : this.timeSpeedIndex - 1
      }
      this.applySpeedStep(rewIdx)
      this.flashHint(I18n.t('s0763_rewind') + ' ' + this.timeRateText)
      this.refreshTimeNow()
    } else if (id === 'faster' || id === 'fast' || id === 'warp') {
      // 快进：单按钮循环升档 1x → 2x → 10x → 1分/秒 → 1时/秒 → 1天/秒 → 10天/秒 → 回到1x
      let fwdIdx = 7 // 默认回 1x（停止/倒带状态按下时从 1x 起步）
      if (this.timeSpeedIndex >= 7) {
        // 已在正向：升一档；到顶(13)循环回 1x
        fwdIdx = this.timeSpeedIndex >= 13 ? 7 : this.timeSpeedIndex + 1
      }
      this.applySpeedStep(fwdIdx)
      this.flashHint(I18n.t('s0765_fast') + ' ' + this.timeRateText)
      this.refreshTimeNow()
    } else if (id === 'slower') {
      // 减速：向"停止"方向降一档（快进降档、倒带也降档），降到1x再点=停止，不会跨进反向
      let prevIdx = this.timeSpeedIndex
      if (this.timeSpeedIndex > 6) {
        prevIdx = this.timeSpeedIndex - 1
      } else if (this.timeSpeedIndex < 6) {
        prevIdx = this.timeSpeedIndex + 1
      }
      this.applySpeedStep(prevIdx)
      this.flashHint(prevIdx === 6 ? I18n.t('s0761_stop') : I18n.t('s0759_slower') + ' ' + this.timeRateText)
      this.refreshTimeNow()
    } else if (id === '+12h') {
      this.advanceTime(12)
    } else if (id === '-12h') {
      this.advanceTime(-12)
    } else if (id === 'Moon') {
      this.searchObject('Moon')
    } else if (id === 'Mars') {
      this.searchObject('Mars')
    } else if (id === 'Jupiter') {
      this.searchObject('Jupiter')
    } else if (id.startsWith('city_')) {
      const cityId = id.substring(5)
      const preset: CityPreset | null = this.getCityPreset(cityId) ?? null
      if (preset !== null) {
        this.setLocation(cityId, preset.lat, preset.lon, preset.alt)
      }
    } else if (id === 'Beijing') {
      this.setLocation('Beijing', 39.9042, 116.4074, 44)
    } else if (id === 'Sun' || id === 'Mercury' || id === 'Venus' || id === 'Saturn' || id === 'Sirius' || id === 'Vega' || id === 'Betelgeuse' || id === 'Polaris' || id === 'M31' || id === 'M42' || id === 'M45' || id === 'NGC 2244') {
      this.searchObject(id)
    // 方向快捷查看
    } else if (id === 'east') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_East'); this.refreshState(); this.flashHint(I18n.t('i0084'))
    } else if (id === 'south') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_South'); this.refreshState(); this.flashHint(I18n.t('i0085'))
    } else if (id === 'west') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_West'); this.refreshState(); this.flashHint(I18n.t('i0086'))
    } else if (id === 'north') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_North'); this.refreshState(); this.flashHint(I18n.t('i0087'))
    } else if (id === 'zenith') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_Zenith'); this.refreshState(); this.flashHint(I18n.t('i0088'))
    } else if (id === 'ncp') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_NCP'); this.refreshState(); this.flashHint(I18n.t('i0089'))
    // FOV 快捷切换（actionSet_FOV 索引: 0=0.5°, 1=180°, 2=90°, 3=60°, 4=45°, 5=20°, 6=10°, 7=5°, 8=2°, 9=1°）
    } else if (id === 'fov1') {
      this.stopTracking(); this.setFovPreset(1); this.refreshState(); this.flashHint(I18n.t('i0090'))
    } else if (id === 'fov2') {
      this.stopTracking(); this.setFovPreset(2); this.refreshState(); this.flashHint(I18n.t('i0091'))
    } else if (id === 'fov5') {
      this.stopTracking(); this.setFovPreset(5); this.refreshState(); this.flashHint(I18n.t('i0092'))
    } else if (id === 'fov10') {
      this.stopTracking(); this.setFovPreset(10); this.refreshState(); this.flashHint(I18n.t('i0093'))
    } else if (id === 'fov20') {
      this.stopTracking(); this.setFovPreset(20); this.refreshState(); this.flashHint(I18n.t('i0094'))
    } else if (id === 'fov45') {
      this.stopTracking(); this.setFovPreset(45); this.refreshState(); this.flashHint(I18n.t('i0095'))
    } else if (id === 'fov60') {
      this.stopTracking(); this.setFovPreset(60); this.refreshState(); this.flashHint(I18n.t('i0096'))
    } else if (id === 'fov90') {
      this.stopTracking(); this.setFovPreset(90); this.refreshState(); this.flashHint(I18n.t('i0097'))
    } else if (id === 'fov180') {
      this.stopTracking(); this.setFovPreset(180); this.refreshState(); this.flashHint(I18n.t('i0098'))
    }
  }

  @Builder
  infoRow(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label)
        .fontSize(11)
        .fontColor('#99FFFFFF')
        .width(64)
        .textAlign(TextAlign.Start)
      Text(value)
        .fontSize(13)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
    }
      .height(24)
      .width('100%')
      .padding({ left: 8, right: 8 })
      .backgroundColor(Color.Transparent)
      .margin({ bottom: 2 })
  }

  @Builder
  detailInfoRow(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label)
        .fontSize(10)
        .fontColor('#8099BBCC')
        .width(70)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value)
        .fontSize(12)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
    }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor('rgba(91,147,191,0.06)')
      .border({ width: 1, color: 'rgba(91,147,191,0.12)' })
      .borderRadius(10)
  }

  private selfTestAllActions(): void {
    hilog.info(0x0000, 'StellariumArkUI', 'selftest send %{public}d ids', this.SELFTEST_ACTION_IDS.length)
    // 引擎核心(StelApp)在启动早期尚未就绪，命令会先返回 pending 不入队；
    // 用更长重试窗口(100ms x 120 = 12s)撑过初始化，确保真正跑到 C++ 自检。
    this.callNativeWhenReady('selftestActions', this.SELFTEST_ACTION_IDS.join('|'), (r: StellariumBridgeResponse) => {
      // 把整包响应(含 total/missing)打在一行里，避免被启动期日志冲掉
      hilog.info(0x0000, 'StellariumArkUI', 'selftest done %{public}s', JSON.stringify(r))
    }, 0, 100, 120)
  }

  @Builder
  switchRow(label: ResourceStr, enabled: boolean, actionId: string, cmd?: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: enabled })
        .width(46)
        .height(28)
        .selectedColor('#5B93BF')
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onChange((value: boolean) => {
          if (cmd) {
            this.setBridgeFlag(cmd, value)
          } else {
            this.setLayer(actionId, value)
          }
          this.flashHint(I18n.t(value ? 'msg_shown' : 'msg_hidden'))
        })
    }
      .height(42)
      .width('100%')
      .padding({ left: 10, right: 8 })
      .backgroundColor(enabled ? 'rgba(107, 163, 214, 0.12)' : 'rgba(255, 255, 255, 0.04)')
      .border({ width: 1, color: enabled ? 'rgba(107, 163, 214, 0.18)' : 'rgba(255, 255, 255, 0.05)' })
      .borderRadius(12)
      .margin({ bottom: 6 })
      .animation({ duration: 200, curve: curves.springMotion(0.45, 0.9) })
  }

  private panelTitle(): ResourceStr {
    if (this.activePanel === 'search') {
      return I18n.t('i0021')
    }
    if (this.activePanel === 'time') {
      return I18n.t('i0054')
    }
    if (this.activePanel === 'place') {
      return I18n.t('i0014')
    }
    if (this.activePanel === 'layers') {
      return I18n.t('i0100')
    }
    if (this.activePanel === 'config') {
      return I18n.t('i0273')
    }
    if (this.activePanel === 'astro') {
      return I18n.t('i0274')
    }
    if (this.activePanel === 'help') {
      return I18n.t('i0217')
    }
    if (this.activePanel === 'settings') {
      return I18n.t('i0102')
    }
    if (this.activePanel === 'catalogs') {
      return I18n.t('p_catalogs')
    }
    if (this.activePanel === 'bookmarks') {
      return I18n.t('p_bookmarks')
    }
    if (this.activePanel === 'oculars') {
      return I18n.t('p_oculars')
    }
    if (this.activePanel === 'satellites') {
      return I18n.t('p_satellites')
    }
    if (this.activePanel === 'meteorshowers') {
      return I18n.t('p_meteors')
    }
    if (this.activePanel === 'scripts') {
      return I18n.t('p_scripts')
    }
    return I18n.t('i0101')
  }

  private panelSubtitle(): string {
    return ''
  }

  private layerTabItems(): TabItem[] {
    const tabs: TabItem[] = [
      { label: I18n.t('v0000'), id: 0 },
      { label: I18n.t('v0001'), id: 1 },
      { label: I18n.t('v0002'), id: 2 },
      { label: I18n.t('v0003'), id: 3 },
      { label: I18n.t('v0004'), id: 4 },
      { label: I18n.t('v0005'), id: 5 }
    ]
    if (!OFFLINE_APPGALLERY_BUILD) {
      tabs.push({ label: I18n.t('v0006'), id: 6 })
    }
    return tabs
  }

  // View 面板标签页选择器
  @Builder viewTabs() {
    Scroll() {
      Row({ space: this.isFoldTabletLayout ? 5 : 6 }) {
        ForEach(this.layerTabItems(), (tab: TabItem) => {
          Text(tab.label)
            .fontSize(this.isFoldTabletLayout ? 11 : 10)
            .fontColor(this.viewTab === tab.id ? this.nmText() : this.nmSub())
            .padding({ left: this.isFoldTabletLayout ? 10 : 8, right: this.isFoldTabletLayout ? 10 : 8, top: 5, bottom: 5 })
            .backgroundColor(this.viewTab === tab.id ? this.nmAccent() : this.nmBg())
            .borderRadius(8)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .animation({ duration: 220, curve: curves.springMotion(0.42, 0.86) })
            .onClick(() => {
              this.getUIContext().animateTo({ duration: 220, curve: curves.springMotion(0.42, 0.86) }, () => {
                this.viewTab = tab.id
              })
            })
        }, (tab: TabItem, index: number) => tab.id.toString())
      }
      .padding({ left: 2, right: 12 })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .margin({ top: 4, bottom: 10 })
  }

  // View 面板 Sky 标签页内容
  @Builder viewSkyTab() {
    this.switchRow(I18n.t('s0530'), this.stars, 'actionShow_Stars')
    this.switchRow(I18n.t('s0531'), this.milkyWay, 'actionShow_MilkyWay')
    this.switchRow(I18n.t('s0532'), this.starLabels, 'actionShow_Stars_Labels')
    // 星等限制
    Row() {
      Text(I18n.t('i0300')).fontSize(12).fontColor(this.nmSub()).width(72)
      Slider({
        value: this.starMagLimit,
        min: 2.0,
        max: 9.0,
        step: 0.5,
        style: SliderStyle.OutSet
      })
        .blockColor('#5B93BF')
        .trackColor('rgba(255,255,255,0.08)')
        .selectedColor('#5B93BF')
        .showSteps(false)
        .showTips(false)
        .layoutWeight(1)
        .onChange((value: number) => {
          this.starMagLimit = Math.round(value * 10) / 10
          // Native code enables the forced limit before applying this value.
          // A 2.0--9.0 range makes the visual effect apparent on mobile data.
          this.callInteractive('setLimitMagnitude', this.starMagLimit.toFixed(1), () => {})
        })
      Text(this.starMagLimit.toFixed(1)).fontSize(12).fontColor(this.nmText()).width(28).textAlign(TextAlign.End)
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    this.switchRow(I18n.t('s0305'), this.atmosphere, 'actionShow_Atmosphere')
    this.switchRow(I18n.t('s0306'), this.ground, 'actionShow_Ground')
    this.switchRow(I18n.t('s0307'), this.fogEffect, 'actionShow_Fog')
    this.switchRow(I18n.t('s0308'), this.meteors, 'setMeteors', 'setMeteors')
    // 银河亮度
    Row() {
      Text(I18n.t('i0212')).fontSize(12).fontColor(this.nmSub()).width(72)
      Row({ space: 6 }) {
        Button('-').fontSize(12).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(8).width(36).height(28)
          .onClick(() => {
            if (this.milkyWayBright > 0) {
              this.milkyWayBright--
              this.callInteractive('setMilkyWayIntensity', (this.milkyWayBright / 3).toFixed(2), () => {})
            }
          })
        Text(this.milkyWayBright.toString()).fontSize(14).fontColor(this.nmText()).width(24).textAlign(TextAlign.Center)
        Button('+').fontSize(12).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(8).width(36).height(28)
          .onClick(() => {
            if (this.milkyWayBright < 6) {
              this.milkyWayBright++
              this.callInteractive('setMilkyWayIntensity', (this.milkyWayBright / 3).toFixed(2), () => {})
            }
          })
      }
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    this.switchRow(I18n.t('s0300'), this.nightMode, 'actionShow_Night_Mode')
    this.switchRow(I18n.t('s0309'), this.flipHoriz, 'actionHorizontal_Flip')
    this.switchRow(I18n.t('s0310'), this.flipVert, 'actionVertical_Flip')
  }

  // View 面板 SSO 标签页内容
  @Builder viewSSOTab() {
    Text('基础显示').fontSize(11).fontColor(this.nmSub()).width('100%').margin({ top: 2, bottom: 6 }).padding({ left: 2 })
    this.switchRow(I18n.t('s0311'), this.planets, 'actionShow_Planets')
    this.switchRow(I18n.t('s0312'), this.planetOrbits, 'actionShow_Planets_Orbits')
    this.switchRow(I18n.t('s0314'), this.planetHints, 'actionShow_Planets_Hints')
    Text('高级标记').fontSize(11).fontColor(this.nmSub()).width('100%').margin({ top: 8, bottom: 6 }).padding({ left: 2 })
    this.switchRow(I18n.t('s0313'), this.planetTrails, 'actionShow_Planets_Trails')
    this.switchRow(I18n.t('s0318'), this.minorBodyMarkers, 'actionShow_Planets_ShowMinorBodyMarkers')
    this.switchRow(I18n.t('s0319'), this.planetNomenclature, 'actionShow_Planets_Nomenclature')
    if (this.isExpandedLayout) {
      Text('视直径增强').fontSize(11).fontColor(this.nmSub()).width('100%').margin({ top: 8, bottom: 6 }).padding({ left: 2 })
      this.switchRow(I18n.t('s0315'), this.enlargeMoon, 'actionShow_Planets_EnlargeMoon')
      this.switchRow(I18n.t('s0316'), this.enlargePlanets, 'actionShow_Planets_EnlargePlanets')
      this.switchRow(I18n.t('s0317'), this.enlargeSun, 'actionShow_Planets_EnlargeSun')
    }
    Row() {
      Text(I18n.t('i0281')).fontSize(12).fontColor(this.nmSub()).width(72)
      Button(I18n.t('i0282')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.triggerAction('actionShow_Planets_Trails_Reset') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
  }

  // View 面板 DSO 标签页内容
  @Builder viewDSOTab() {
    Text('显示内容').fontSize(11).fontColor(this.nmSub()).width('100%').margin({ top: 2, bottom: 6 }).padding({ left: 2 })
    this.switchRow(I18n.t('s0320'), this.nebulae, 'actionShow_Nebulas')
    this.switchRow(I18n.t('s0321'), this.dsoLabels, 'setDsoLabels', 'setDsoLabels')
    this.switchRow(I18n.t('s0322'), this.dsoTextures, 'actionShow_DSO_Textures')
  }

  // View 面板 Markings 标签页内容
  @Builder viewMarkingsTab() {
    Scroll() {
      Column({ space: 0 }) {
        // 基础网格
        Text(I18n.t('i0197')).fontSize(11).fontColor(this.nmSub()).width('100%').margin({ top: 4, bottom: 2 }).padding({ left: 2 })
        this.switchRow(I18n.t('s0323'), this.equatorialGrid, 'actionShow_Equatorial_Grid')
        this.switchRow(I18n.t('s0324'), this.azimuthGrid, 'actionShow_Azimuthal_Grid')
        // 特殊线
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text(I18n.t('i0198')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow(I18n.t('s0325'), this.equatorLine, 'actionShow_Equator_Line')
        this.switchRow(I18n.t('s0326'), this.eclipticLine, 'actionShow_Ecliptic_Line')
        this.switchRow(I18n.t('s0327'), this.meridianLine, 'actionShow_Meridian_Line')
        this.switchRow(I18n.t('s0328'), this.horizonLine, 'actionShow_Horizon_Line')
        this.switchRow(I18n.t('s0329'), this.galacticEquator, 'actionShow_Galactic_Equator_Line')
        this.switchRow(I18n.t('s0330'), this.supergalacticEq, 'actionShow_Supergalactic_Equator_Line')
        this.switchRow(I18n.t('s0331'), this.galacticGrid, 'actionShow_Galactic_Grid')
        // J2000 线
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text(I18n.t('i0199')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow(I18n.t('s0332'), this.equJ2000Line, 'actionShow_Equator_J2000_Line')
        this.switchRow(I18n.t('s0333'), this.eclJ2000Line, 'actionShow_Ecliptic_J2000_Line')
        // 点标记
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text(I18n.t('i0200')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow(I18n.t('s0334'), this.celestialPoles, 'actionShow_Celestial_Poles')
        this.switchRow(I18n.t('s0335'), this.eclipticPoles, 'actionShow_Ecliptic_Poles')
        this.switchRow(I18n.t('s0336'), this.galacticPoles, 'actionShow_Galactic_Poles')
        this.switchRow(I18n.t('s0337'), this.equinoxPoints, 'actionShow_Equinox_Points')
        this.switchRow(I18n.t('s0338'), this.solsticePoints, 'actionShow_Solstice_Points')
        this.switchRow(I18n.t('s0339'), this.antisolarPoint, 'actionShow_Antisolar_Point')
        this.switchRow(I18n.t('s0340'), this.umbraCircle, 'actionShow_Umbra_Circle')
        this.switchRow(I18n.t('s0341'), this.penumbraCircle, 'actionShow_Penumbra_Circle')
        // 辅助标记
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text(I18n.t('i0284')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow(I18n.t('s0342'), this.compassMarks, 'actionShow_Compass_Marks')
        this.switchRow(I18n.t('s0343'), this.fovMarker, 'actionShow_FOV_Center_Marker')
        this.switchRow(I18n.t('s0344'), this.intercardinalPts, 'actionShow_Intercardinal_Points')
        // 更多标记线
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text(I18n.t('i0285')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow(I18n.t('s0345'), this.primeVerticalLine, 'actionShow_Prime_Vertical_Line')
        this.switchRow(I18n.t('s0346'), this.currentVerticalLine, 'actionShow_Current_Vertical_Line')
        this.switchRow(I18n.t('s0347'), this.colureLines, 'actionShow_Colure_Lines')
        this.switchRow(I18n.t('s0348'), this.precessionCircles, 'actionShow_Precession_Circles')
        this.switchRow(I18n.t('s0500'), this.circumpolarCircles, 'actionShow_Circumpolar_Circles')
        this.switchRow(I18n.t('s0501'), this.invariantPlaneLine, 'actionShow_Invariable_Plane_Line')
        this.switchRow(I18n.t('s0502'), this.solarEquatorLine, 'actionShow_Solar_Equator_Line')
        // 更多网格
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text(I18n.t('i0286')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow(I18n.t('s0503'), this.equatorialJ2000Grid, 'actionShow_Equatorial_J2000_Grid')
        this.switchRow(I18n.t('s0504'), this.eclipticJ2000Grid, 'actionShow_Ecliptic_J2000_Grid')
        this.switchRow(I18n.t('s0505'), this.eclipticGrid, 'actionShow_Ecliptic_Grid')
        this.switchRow(I18n.t('s0506'), this.supergalacticGrid, 'actionShow_Supergalactic_Grid')
        this.switchRow(I18n.t('s0507'), this.fixedEquatorialGrid, 'actionShow_Fixed_Equatorial_Grid')
        this.switchRow(I18n.t('s0508'), this.fixedEquatorLine, 'actionShow_Fixed_Equator_Line')
        // 更多点标记
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text(I18n.t('i0287')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow(I18n.t('s0509'), this.zenithNadir, 'actionShow_Zenith_Nadir')
        this.switchRow(I18n.t('s0510'), this.eclipticJ2000Poles, 'actionShow_Celestial_J2000_Poles')
        this.switchRow(I18n.t('s0511'), this.eclipticJ2000Poles, 'actionShow_Ecliptic_J2000_Poles')
        this.switchRow(I18n.t('s0512'), this.equinoxJ2000Pts, 'actionShow_Equinox_J2000_Points')
        this.switchRow(I18n.t('s0513'), this.solsticeJ2000Pts, 'actionShow_Solstice_J2000_Points')
        this.switchRow(I18n.t('s0514'), this.galacticCenter, 'actionShow_Galactic_Center')
        this.switchRow(I18n.t('s0515'), this.supergalacticPoles, 'actionShow_Supergalactic_Poles')
        this.switchRow(I18n.t('s0516'), this.apexPoints, 'actionShow_Apex_Points')
        this.switchRow(I18n.t('s0517'), this.umbraCenter, 'actionShow_Umbra_Center_Point')
        this.switchRow(I18n.t('s0518'), this.longitudeLine, 'actionShow_Longitude_Line')
        this.switchRow(I18n.t('s0519'), this.quadratureLine, 'actionShow_Quadrature_Line')

      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(4)
    .scrollBarColor('#33FFFFFF')
  }

  // View 面板 Landscape 标签页内容
  @Builder viewLandscapeTab() {
    this.switchRow(I18n.t('s0306'), this.ground, 'actionShow_Ground')
    this.switchRow(I18n.t('s0520'), this.landscapeIllum, 'actionShow_LandscapeIllumination')
    this.switchRow(I18n.t('s0521'), this.landscapeLabels, 'actionShow_LandscapeLabels')
    this.switchRow(I18n.t('s0307'), this.fogEffect, 'actionShow_Fog')
    Row() {
      Column() {
        Text('俯视时地景淡出').fontSize(13).fontColor('#E5FFFFFF')
        Text('视角压低看地面时地面渐隐，露出地平线下的星空（仍可见）').fontSize(11).fontColor('#99FFFFFF').margin({ top: 2 })
      }.layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.landscapeFadeWithZoom })
        .onChange((isOn: boolean) => { this.setLandscapeFadeWithZoom(isOn) })
    }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12).margin({ top: 6 })
    Row() {
      Text(I18n.t('i0288')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
    }.height(18).width('100%').margin({ top: 6 })
    Scroll() {
      Column({ space: 2 }) {
        ForEach(this.landscapeList, (item: LandscapeItem) => {
          Row() {
            Text(this.landscapeZh(item.name)).fontSize(11)
              .fontColor(this.currentLandscapeId === item.id ? this.nmAccent() : this.nmText())
              .layoutWeight(1)
            if (this.currentLandscapeId === item.id) {
              Text(I18n.t('s0602')).fontSize(9).fontColor(this.nmAccent()).margin({ right: 8 })
            }
          }
          .height(32).width('100%').padding({ left: 12, right: 12 })
          .backgroundColor(this.currentLandscapeId === item.id ? 'rgba(80,140,200,0.18)' : 'rgba(0,0,0,0)')
          .borderRadius(4)
          .onClick(() => { this.selectLandscape(item.id, item.name) })
        }, (item: LandscapeItem, index: number) => item.id)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(4)
    .scrollBarColor('#33FFFFFF')
    Row() {
      Text(I18n.t('i0289')).fontSize(12).fontColor(this.nmSub()).width(72)
      Text(this.landscapeTransp + '%').fontSize(14).fontColor(this.nmText()).margin({ right: 8 })
      Slider({ value: this.landscapeTransp, min: 0, max: 100, step: 5, style: SliderStyle.OutSet })
        .layoutWeight(1)
        .blockColor(this.nmAccent())
        .trackColor(this.nmBg())
        .selectedColor(this.nmAccent())
        .showSteps(false)
        .onChange((val: number) => { this.landscapeTransp = Math.round(val); this.changeLandscapeTransparency(val) })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    Row() {
      Text(I18n.t('i0316')).fontSize(12).fontColor(this.nmSub()).width(72)
      Text('Bortle ' + this.bortleScale).fontSize(14).fontColor(this.nmText()).margin({ right: 8 })
      Slider({ value: this.bortleScale, min: 1, max: 9, step: 1, style: SliderStyle.OutSet })
        .layoutWeight(1)
        .blockColor(this.nmAccent())
        .trackColor(this.nmBg())
        .selectedColor(this.nmAccent())
        .showSteps(false)
        .onChange((val: number) => {
          this.bortleScale = Math.round(val)
          this.callInteractive('setBortleScale', this.bortleScale.toString(), () => {})
        })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
  }

  // View 面板 Sky Culture 标签页内容
  @Builder viewSkyCultureTab() {
    this.switchRow(I18n.t('s0522'), this.constellationLines, 'actionShow_Constellation_Lines')
    this.switchRow(I18n.t('s0523'), this.constellationLabels, 'actionShow_Constellation_Labels')
    this.switchRow(I18n.t('s0524'), this.constellationBoundaries, 'actionShow_Constellation_Boundaries')
    this.switchRow(I18n.t('s0525'), this.constellationArt, 'actionShow_Constellation_Art')
    this.switchRow(I18n.t('s0526'), this.zodiac, 'actionShow_Zodiac')
    this.switchRow(I18n.t('s0527'), this.lunarSystem, 'actionShow_LunarSystem')
    this.switchRow(I18n.t('s0528'), this.asterismLines, 'actionShow_Asterism_Lines')
    this.switchRow(I18n.t('s0529'), this.asterismLabels, 'actionShow_Asterism_Labels')
    Row()
      .width('100%').height(0.5)
      .backgroundColor(this.nmBorder())
      .margin({ top: 6, bottom: 4 })
    Row() {
      Text(I18n.t('i0213')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
    }.height(18).width('100%')
    Scroll() {
      Column({ space: 2 }) {
        ForEach(this.skyCultureList, (sc: SkyCultureItem) => {
          Row() {
            Text(sc.name).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
            if (sc.id === this.currentSkyCultureId) {
              Text('✓').fontSize(11).fontColor(this.nmAccent()).width(16)
            }
          }
          .height(30).width('100%').padding({ left: 10, right: 10 })
          .backgroundColor(sc.id === this.currentSkyCultureId ? 'rgba(80,140,200,0.18)' : 'rgba(0,0,0,0)')
          .borderRadius(4)
          .onClick(() => { this.selectSkyCulture(sc.id) })
        }, (sc: SkyCultureItem) => sc.id)
      }
    }
    .width('100%').height(200).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }

  // View 面板 Surveys 标签页内容
  @Builder viewSurveysTab() {
    this.switchRow(I18n.t('s0600'), this.hipsSurveys, 'actionShow_Hips_Surveys')
    this.switchRow(I18n.t('s0601'), this.toastSurvey, 'actionShow_Toast_Survey')
    Row() {
      Text(I18n.t('i0215')).fontSize(10).fontColor('#CC8FB6FF').width('100%').padding({ left: 2 })
    }.height(18).width('100%').margin({ top: 8 })
  }

}
