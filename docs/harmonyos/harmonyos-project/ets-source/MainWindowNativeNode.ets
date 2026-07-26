import { command } from 'libentry.so'
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { geoLocationManager } from '@kit.LocationKit'
import { sensor } from '@kit.SensorServiceKit'
import { curves } from '@kit.ArkUI'
import hilog from '@ohos.hilog'
import preferences from '@ohos.data.preferences'
import { LOCATION_HIERARCHY } from './location_hierarchy'

import { ALIAS_LIST, StellariumBridgeResponse, SessionSnapshot, TonightEvents, LangOption, HierCity, CatOption, NameItem, AliasEntry, SearchSug, AliasHit, WindowNativeNodeCreateInfo, TabItem, ChipItem, LandscapeItem, PlanetPosition, ObjectInfo, SkyCultureItem, PluginItem, ShellAction, LocSearchItem, SavedLocation } from './StellariumTypes'
import { AudioEngine } from './StellariumAudio'
import { I18n, LANGUAGE_DISPLAY, SUPPORTED_LANGUAGES, BRIGHT_STARS } from './I18n'

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
  @State private isExpandedLayout: boolean = true
  @State private activePanel: string = 'object'
  @State private panelVisible: boolean = true
  @State private sheetHeightPct: number = 70
  @State private sheetDragStartY: number = 0
  @State private sheetDragStartPct: number = 70
  @State private searchText: string = ''
  @State private selectedName: string = ''
  @State private searchSuggestions: SearchSug[] = []
  @State private searchHistory: string[] = []
  @State private searchCategory: string = 'planet'
  @State private categoryObjects: NameItem[] = []
  @State private selectedType: string = ''
  @State private selectedStatus: string = ''
  @State private selectedInfo: string = ''
  @State private selectedMagnitude: string = ''
  @State private selectedCoordEq: string = ''
  @State private selectedCoordAlt: string = ''
  @State private selectedConstellation: string = ''
  @State private selectedDistance: string = ''
  @State private visibleConstellations: string = ''
  // 富化的天体详情（独立浮动窗口，不切换当前菜单；默认收起，可展开）
  @State private infoWinVisible: boolean = false
  @State private infoWinExpanded: boolean = false
  @State private bottomCardIndex: number = 0
  @State private infoTextExpanded: boolean = false
  @State private panelContentKey: number = 0
  @State private cardOffsetX: number = 0
  @State private cardOffsetY: number = 0
  @State private cardDragStartX: number = 0
  @State private cardDragStartY: number = 0
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
  @State private manualYear: number = 2026
  @State private manualMonth: number = 7
  @State private manualDay: number = 20
  @State private manualHour: number = 23
  @State private manualMinute: number = 0
  @State private selectedLanguage: string = 'zh_CN'
  @StorageLink('i18nLang') private i18nLang: string = 'zh_CN'
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
  @State private astroTab: number = 0   // 天文计算面板子标签索引
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
  // 锁定视角：开启后上下左右都不能拖动，但捏合缩放仍然可用。
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
  @State private almanacData: Map<string, string> = new Map()
  @State private objectInfo: Map<string, string> = new Map()
  @State private dsoTotalCount: number = 0
  @State private dsoGalaxies: number = 0
  @State private dsoClusters: number = 0
  @State private dsoNebulae: number = 0
  @State private planetPositions: Array<PlanetPosition> = []
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
  @State private gyroOffsetAz: number = 0    // 方位角校准偏移（度）
  @State private gyroOffsetAlt: number = 0   // 高度角校准偏移（度）
  @State private liveMode: boolean = true
  @State private timeScale: string = '1x'
  @State private currentFovText: string = '--'
  @State private fovSliderValue: number = 60
  @State private currentProjection: string = 'Perspective'
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
  // 目标详情自动刷新：选中天体后每秒重新拉一次坐标，让“地平坐标”随地球自转实时变化。
  // detailTimer 为 setInterval 句柄；detailRefreshing 防重入；detailRefreshGuard 是兜底定时器，
  // 因为 callNativeWhenReady 在放弃轮询时【不】回调 onOk，必须靠它复位，否则会卡死不再刷新。
  private detailTimer: number = 0
  private detailRefreshing: boolean = false
  private detailRefreshGuard: number = 0
  private touchStartX: number = 0
  private touchStartY: number = 0
  private touchLastX: number = 0
  private touchLastY: number = 0
  private touchMoved: boolean = false
  private skyTouchActive: boolean = false
  private pinchStartDistance: number = 0
  private pinchActive: boolean = false
  private nativeDragActive: boolean = false
  private lastDragCommandMs: number = 0
  private skyDragging: boolean = false
  private gyroLastTimeMs: number = 0
  private gyroEventCount: number = 0
  private readonly gyroSensitivity: number = 180
  private gyroCallback: ((data: sensor.OrientationResponse) => void) | undefined = undefined
  private dragLogCount: number = 0
  private touchStartedOnUi: boolean = false
  private panelDragging: boolean = false
  private panelDragStartX: number = 0
  private panelDragStartY: number = 0
  private panelDragStartOffsetX: number = 0
  private panelDragStartOffsetY: number = 0

  // 左侧栏布局常量
  private readonly RAIL_TOP_PAD: number = 10

  // 常用入口：直接固定在左侧栏（观星高频操作）
  private readonly pinnedActions: ShellAction[] = [
    { label: I18n.t('i0021'), icon: 'search', panel: 'search' },
    { label: I18n.t('i0054'), icon: 'clock', panel: 'time' },
    { label: I18n.t('i0014'), icon: 'location', panel: 'place' },
    { label: I18n.t('i0100'), icon: 'layers', panel: 'layers' },
    { label: I18n.t('pinned_obs_list'), icon: 'observe', panel: 'observing' },
    { label: I18n.t('i0102'), icon: 'settings', panel: 'settings' }
  ]
  // 低频入口：收进抽屉（点侧栏底部九宫格按钮展开），图标全部专属不重复
  private readonly drawerActions: ShellAction[] = [
    { label: I18n.t('i0101'), icon: 'info', panel: 'object' },
    { label: I18n.t('panel_catalogs'), icon: 'catalogs', panel: 'catalogs' },
    { label: I18n.t('panel_bookmarks'), icon: 'bookmarks', panel: 'bookmarks' },
    { label: I18n.t('panel_oculars'), icon: 'telescope', panel: 'oculars' },
    { label: I18n.t('panel_satellites'), icon: 'satellite', panel: 'satellites' },
    { label: I18n.t('panel_meteorshowers'), icon: 'meteor', panel: 'meteorshowers' },
    { label: I18n.t('panel_scripts'), icon: 'script', panel: 'scripts' },
    { icon: 'tune', label: I18n.t('i0273'), panel: 'config' },
    { icon: 'orbit', label: I18n.t('i0274'), panel: 'astro' },
    { icon: 'help', label: I18n.t('i0217'), panel: 'help' },
    { icon: 'audio', label: I18n.t('panel_audio_ctrl'), panel: 'audio' }
  ]
  // 全量列表：面板渲染等处仍按老逻辑遍历（顺序 = 固定项 + 抽屉项）
  private readonly actions: ShellAction[] = [
    { label: I18n.t('i0104'), icon: 'search', panel: 'search' },
    { label: I18n.t('i0054'), icon: 'clock', panel: 'time' },
    { label: I18n.t('i0014'), icon: 'location', panel: 'place' },
    { label: I18n.t('i0100'), icon: 'layers', panel: 'layers' },
    { label: I18n.t('i0102'), icon: 'settings', panel: 'settings' },
    { label: I18n.t('i0101'), icon: 'info', panel: 'object' },
    { label: I18n.t('panel_catalogs'), icon: 'catalogs', panel: 'catalogs' },
    { label: I18n.t('panel_bookmarks'), icon: 'bookmarks', panel: 'bookmarks' },
    { label: I18n.t('panel_oculars'), icon: 'telescope', panel: 'oculars' },
    { label: I18n.t('panel_satellites'), icon: 'satellite', panel: 'satellites' },
    { label: I18n.t('panel_meteorshowers'), icon: 'meteor', panel: 'meteorshowers' },
    { label: I18n.t('panel_scripts'), icon: 'script', panel: 'scripts' },
    { icon: 'tune', label: I18n.t('i0273'), panel: 'config' },
    { icon: 'orbit', label: I18n.t('i0274'), panel: 'astro' },
    { icon: 'help', label: I18n.t('i0217'), panel: 'help' },
    { icon: 'audio', label: I18n.t('panel_audio_ctrl'), panel: 'audio' }
  ]
  @State private drawerOpen: boolean = false

  private SELFTEST: boolean = false  // 开发自检：启动即对全部开关跑一次 findAction，验证无死开关。发布前改 false。

  // 城市快速定位预设数据: id -> "lat|lon|alt"
  private getCityPreset(id: string): ESObject | undefined {
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
    const result: ESObject = { 'lat': parseFloat(p[0]), 'lon': parseFloat(p[1]), 'alt': parseFloat(p[2]) }
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
        } else if (r && r.pending) {
          // If pending, try again after a short delay
          setTimeout(() => {
            const r2 = this.callNative('getFPS', '')
            if (r2 && r2.ok && typeof r2.fps === 'number' && r2.fps > 0) {
              this.fpsDisplay = Math.round(r2.fps)
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

  aboutToAppear(): void {
    const localStorage = this.getUIContext().getSharedLocalStorage()
    if (localStorage) {
      this.createInfo = localStorage.get<WindowNativeNodeCreateInfo>('createInfo')
    }
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
    this.loadSkyCultureList()
    this.loadPluginList()
    // 初始化距离单位设置
    this.callNativeWhenReady('getConfigString', 'astronomy/flag_use_km_for_distance', (r) => {
      if (r.ok) {
        this.useMetricUnits = r.value === 'true'
      }
    })
    // 初始化星等限制
    this.callNativeWhenReady('getConfigString', 'astro/StarMagLimit', (r) => {
      if (r.ok && r.value) {
        const v = parseFloat(r.value)
        if (!isNaN(v)) { this.starMagLimit = v }
      }
    })
    // 加载保存的设置
    const settings = AppStorage.get<string>("stellariumSettings")
    if (settings) {
      try {
        const s = JSON.parse(settings) as Record<string, boolean | string>
        if (s.nightMode !== undefined) { this.nightMode = s.nightMode as boolean; this.triggerAction("actionShow_Night_Mode") }
        if (s.equatorialMount !== undefined) { this.equatorialMount = s.equatorialMount as boolean; this.triggerAction("actionSwitch_Equatorial_Mount") }
        if (s.gyroscopeEnabled !== undefined) { this.gyroscopeEnabled = s.gyroscopeEnabled as boolean }
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
    // 使用保存的语言设置（不强制覆盖为中文）
    if (this.selectedLanguage && this.selectedLanguage !== 'zh_CN') {
      I18n.setLanguage(I18n.fromStellariumCode(this.selectedLanguage))
    } else {
      I18n.setLanguage('zh_CN')
    }
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
    this.stopGyroscope(false)
    this.stopDetailAutoRefresh()
  }

  private setPanel(panel: string): void {
    hilog.info(0x0000, 'StellariumArkUI', 'setPanel ' + panel)
    const nextVisible = this.activePanel === panel ? !this.panelVisible : true
    if (nextVisible) {
      this.sheetHeightPct = 70
    }
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
    }
    if (panel === 'object') {
      this.refreshSelectedObject()
    } else if (panel === 'layers' || panel === 'time' || panel === 'settings') {
      this.refreshState()
    } else if (panel === 'place') {
      this.refreshState()
      this.loadPlanetList()
      this.loadObserverInfo()
      this.loadSavedLocations()
    } else if (panel === 'catalogs') {
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

  private closePanel(): void {
    if (this.uiLocked) {
      return
    }
    this.sheetHeightPct = 70
    this.getUIContext().animateTo({ duration: 300, curve: curves.springMotion(0.45, 0.9) }, () => {
      this.panelVisible = false
    })
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
  private callNativeWhenReady(name: string, payload: string = '', onOk?: (r: StellariumBridgeResponse) => void, attempt: number = 0, intervalMs: number = 200, maxAttempts: number = 60): void {
    const r = this.callNative(name, payload)
    if (r.ok === true) {
      if (onOk) onOk(r)
      return
    }
    if (attempt < maxAttempts) {
      setTimeout(() => this.callNativeWhenReady(name, payload, onOk, attempt + 1, intervalMs, maxAttempts), intervalMs)
    }
  }

  // Interactive commands (tap-select, search, get-info, move-to) run on the
  // OHOS render pump one frame later and are delivered via a consume-on-read
  // store on the C++ side, so the first call returns {pending}. Poll fast
  // (50ms x 40 = 2s) so a single tap/search resolves without a visible delay
  // and WITHOUT blocking the render thread. onOk receives the FRESH result.
  private callInteractive(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void): void {
    this.callNativeWhenReady(name, payload, onOk, 0, 100, 15)
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
      const ctx = getContext(this) as common.UIAbilityContext
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
      const ctx = getContext(this) as common.UIAbilityContext
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
      const ctx = getContext(this) as common.UIAbilityContext
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
      const ctx = getContext(this) as common.UIAbilityContext
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
    this.nightMode = result.actionShow_Night_Mode === true
    this.flipHoriz = result.actionHorizontal_Flip === true
    this.flipVert = result.actionVertical_Flip === true
    if (result.timeRate !== undefined) {
      this.timeRateText = this.formatRate(result.timeRate)
    }
    if (result.timeText !== undefined) {
      this.observationTimeText = result.timeText
    }
    // 只有当原生确实返回了观测者经纬度时，才用原生值刷新头部位置字段，
    // 否则保留 setLocation 已应用到头部的值（避免被 planetName 等字段清成“未命名”或空值）。
    if (result.latitude !== undefined && result.longitude !== undefined) {
      this.coordinateText = this.formatDegrees(result.latitude, 'N', 'S') + ' / ' + this.formatDegrees(result.longitude, 'E', 'W')
      if (result.locationName !== undefined && result.locationName.length > 0) {
        const planetName = result.planetName && result.planetName.length > 0 ? result.planetName : 'Earth'
        this.locationText = result.locationName + ' · ' + planetName
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
    this.callInteractive('setJD', jd.toString(), (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'setTimeNow ok=%{public}s', r.ok === true ? '1' : '0')
      this.refreshState()
    })
  }

  private setFovPreset(deg: number): void {
    this.callInteractive('setFOV', deg.toString(), (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'setFovPreset %{public}d ok=%{public}s', deg, r.ok === true ? '1' : '0')
      this.refreshState()
    })
  }


  private setProjection(name: string): void {
    this.callInteractive('setProjectionType', name, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.currentProjection = name
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

  private jdToDateStr(jd: string): string {
    const numJd = parseFloat(jd);
    if (numJd <= 0) return '--'
    const date = new Date((numJd - 2440587.5) * 86400000)
    const h = Math.floor((numJd - Math.floor(numJd)) * 24)
    const m = Math.floor(((numJd - Math.floor(numJd)) * 24 - h) * 60)
    return date.getMonth() + 1 + '/' + date.getDate() + ' ' + h.toString().padStart(2, '0') + ':' + m.toString().padStart(2, '0')
  }

  private loadRTS(): void {
    this.callInteractive('getRTS', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.rts !== undefined) {
        const rv: Object = r.rts as Object
        this.rtsData.set('name', rv['name'] !== undefined ? rv['name'] as string : 'N/A')
        this.rtsData.set('nextRiseJD', rv['nextRiseJD'] !== undefined ? String(rv['nextRiseJD']) : '0')
        this.rtsData.set('nextTransitJD', rv['nextTransitJD'] !== undefined ? String(rv['nextTransitJD']) : '0')
        this.rtsData.set('nextSetJD', rv['nextSetJD'] !== undefined ? String(rv['nextSetJD']) : '0')
      }
    })
  }

  private loadAlmanac(): void {
    this.callInteractive('getAlmanac', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.almanac !== undefined) {
        const av: Object = r.almanac as Object
        this.almanacData.set('sunNextRise', av['sunNextRise'] !== undefined ? String(av['sunNextRise']) : '0')
        this.almanacData.set('sunNextSet', av['sunNextSet'] !== undefined ? String(av['sunNextSet']) : '0')
        this.almanacData.set('moonNextRise', av['moonNextRise'] !== undefined ? String(av['moonNextRise']) : '0')
        this.almanacData.set('moonNextSet', av['moonNextSet'] !== undefined ? String(av['moonNextSet']) : '0')
        this.almanacData.set('moonPhase', av['moonPhase'] !== undefined ? String(av['moonPhase']) : '0')
      }
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
    // manual transparency takes over: enable transparency and disable the auto-fade
    this.callInteractive('setLandscapeUseTransparency', '1', () => {})
    this.callInteractive('setLandscapeFadeWithZoom', '0', () => {})
    this.callInteractive('setLandscapeTransparency', v, () => {})
  }

  private playScriptByName(filename: string): void {
    this.callInteractive('playScript', filename, () => {})
  }

  private fetchSuggestions(prefix: string): void {
    if (prefix.length < 1) { this.searchSuggestions = []; return }
    // 核心最多取 30 条（核心允许 1..50）；同时把中文/拼音别名命中的天体合并进建议。
    this.callInteractive('listMatchingObjects', prefix + '|30', (result) => {
      // Only apply if the query prefix is still current (user may have typed more).
      if (this.searchText.trim() !== prefix) { return }
      const map: Record<string, SearchSug> = {}
      if (Array.isArray(result.items)) {
        for (const it of result.items as string[]) {
          if (!map[it]) { map[it] = { zh: this.zhNameOf(it), en: it } }
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

  private loadCategoryObjects(category: string): void {
    this.searchCategory = category
    const moduleIdMap: Record<string, string> = {
      'planet': 'SolarSystem:planet',
      'moon': 'SolarSystem:moon',
      'star': 'StarMgr:0',
      'variable': 'StarMgr:3',
      'galaxy': 'NebulaMgr:0',
      'cluster': 'NebulaMgr:5',
      'nebula': 'NebulaMgr:10',
      'messier': 'NebulaMgr:100',
    }
    const moduleId = moduleIdMap[category] || ''
    this.callInteractive('listObjects', moduleId, (result) => {
      if (Array.isArray(result.items)) {
        const items = result.items as string[]
        this.categoryObjects = []
        for (let i = 0; i < Math.min(items.length, 20); i++) {
          this.categoryObjects.push({ name: items[i], zh: this.zhNameOf(items[i]) })
        }
      }
    })
  }

  private stopTracking(): void {
    this.callInteractive('setTracking', '0', () => { this.trackingText = 'Off' })
  }

  private setSkyCulture(name: string): void {
    this.callInteractive('setSkyCulture', name, () => {
      this.currentSkyCulture = name
      this.flashHint(I18n.t('i0068'))
    })
  }

  private setTimeRate(rate: number): void {
    this.callInteractive('setTimeRate', rate.toString(), (result) => {
      if (result.timeRate !== undefined) {
        this.timeRateText = this.formatRate(result.timeRate)
      }
    })
  }

  private zoomStep(factor: number): void {
    this.callInteractive('zoomStep', factor.toString(), () => { this.refreshState() })
  }

  private advanceTime(hours: number): void {
    this.callInteractive('advanceTime', hours.toString(), () => { this.refreshState() })
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
    this.selectedLanguage = lang
    // 持久化语言选择
    try {
      const settings = AppStorage.get<string>('stellariumSettings')
      const s: Record<string, Object> = settings ? JSON.parse(settings) as Record<string, Object> : {} as Record<string, Object>
      s.selectedLanguage = lang
      AppStorage.setOrCreate('stellariumSettings', JSON.stringify(s))
    } catch (e) { }
    // 立即提示，不等 C++ 确认（避免阻塞触摸和星图交互）
    this.flashHint(I18n.t('msg_lang_switched_done') + ': ' + (LANGUAGE_DISPLAY[lang] ?? LANGUAGE_DISPLAY[i18nCode] ?? lang))
    // 延迟同步 C++ 侧语言，避免同步 N-API 调用阻塞 UI 线程导致星图无响应
    setTimeout(() => {
      this.callNativeWhenReady('setLanguage', lang, (r: StellariumBridgeResponse) => {
        if (r.ok === true) {
          this.refreshState()
        }
      }, 0, 300, 3)
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
    if (enabled) {
      this.startGyroscope()
    } else {
      this.stopGyroscope(true)
    }
  }

  private startGyroscope(): void {
    if (this.gyroscopeEnabled) {
      return
    }
    if (this.gyroCallback === undefined) {
      this.gyroCallback = (data: sensor.OrientationResponse) => {
        this.onOrientationData(data)
      }
    }
    try {
      // ORIENTATION sensor returns absolute device orientation:
      //   data.alpha = azimuth (0-360, compass heading)
      //   data.beta  = pitch (-180 to 180, front-back tilt)
      //   data.gamma = roll (-90 to 90, left-right tilt)
      // This gives "point device at sky → star map follows" behavior.
      sensor.on(sensor.SensorId.ORIENTATION, this.gyroCallback, { interval: 50000000 })
      this.gyroLastTimeMs = 0
      this.gyroEventCount = 0
      this.gyroFirstReading = true
      this.gyroscopeEnabled = true
      this.gyroscopeStatus = I18n.t('m_gyro_listening')
    } catch (error) {
      this.gyroscopeEnabled = false
      this.gyroscopeStatus = I18n.t('m_gyro_unavailable')
    }
  }

  private stopGyroscope(updateStatus: boolean): void {
    if (this.gyroCallback !== undefined) {
      try {
        sensor.off(sensor.SensorId.ORIENTATION, this.gyroCallback)
      } catch (error) {
      }
    }
    this.gyroLastTimeMs = 0
    this.gyroscopeEnabled = false
    if (updateStatus) {
      this.gyroscopeStatus = I18n.t('m_gyro_off')
    }
  }

  // Absolute orientation tracking: device azimuth/altitude → sky view direction.
  // Uses ORIENTATION sensor (compass + tilt) for "point at sky" behavior.
  private gyroLastAz: number = 0
  private gyroLastAlt: number = 0
  private gyroFirstReading: boolean = true

  private onOrientationData(data: sensor.OrientationResponse): void {
    // ORIENTATION sensor (degrees):
    //   data.alpha = azimuth (0-360): 0=North, 90=East, 180=South, 270=West
    //   data.beta  = pitch (-180 to 180): positive = tilting forward (screen up)
    //   data.gamma = roll (-90 to 90): positive = tilting right
    //
    // ABSOLUTE ORIENTATION MODE (like Star Walk, SkyView, etc.):
    // Device azimuth → sky view azimuth
    // Device altitude (pitch) → sky view altitude
    // "Point device at sky → star map shows what's there"

    // Sensitivity controls how much the view moves relative to device rotation.
    // In absolute mode, sensitivity acts as a smoothing factor.
    let smoothFactor: number = 0.3  // Default (Standard): 30% new + 70% old
    if (this.gyroscopeSensitivityText === 'Low') { smoothFactor = 0.15 }
    else if (this.gyroscopeSensitivityText === 'High') { smoothFactor = 0.5 }

    // --- Compute target azimuth and altitude from device orientation ---
    // Alpha is compass heading: 0=N, 90=E, 180=S, 270=W
    // In Stellarium, azimuth is also measured from North, going East.
    // For landscape mode, the device is rotated 90° clockwise.
    // When holding device in landscape (left hand), screen faces user:
    //   - Rotating body clockwise → alpha increases → view moves East
    //   - Tilting top of device up → beta increases → view moves up
    //
    // For landscape mode with device rotated 90° CW:
    //   The "facing direction" of the device is alpha + 90° (roughly)
    //   But to keep it simple and match user expectation:
    //   We map alpha directly to azimuth, beta to altitude.

    let targetAz = data.alpha
    // Beta: positive when tilting forward (top of phone away from user)
    // For astronomy: when device is held up facing sky, beta ≈ 0-90 = looking up
    // We want: device flat (beta=0) = looking at horizon (alt=0)
    //          device upright (beta=90) = looking at zenith (alt=90)
    let targetAlt = data.beta

    // Clamp altitude to valid range [-90, 90]
    if (targetAlt > 90) targetAlt = 90
    if (targetAlt < -90) targetAlt = -90

    // First reading: initialize and set view immediately
    if (this.gyroFirstReading) {
      this.gyroFirstReading = false
      this.gyroLastAz = targetAz
      this.gyroLastAlt = targetAlt
      // Set view immediately on first reading
      this.callNative('moveToAltAz', targetAz.toFixed(2) + '|' + targetAlt.toFixed(2) + '|0')
      this.gyroscopeStatus = I18n.t('m_gyro_working')
      return
    }

    // Smooth interpolation: gradually move toward target
    let smoothAz = this.gyroLastAz + (targetAz - this.gyroLastAz) * smoothFactor
    let smoothAlt = this.gyroLastAlt + (targetAlt - this.gyroLastAlt) * smoothFactor

    // Handle azimuth wrap-around for smoothing
    let azDiff = targetAz - this.gyroLastAz
    if (azDiff > 180) azDiff -= 360
    if (azDiff < -180) azDiff += 360
    smoothAz = this.gyroLastAz + azDiff * smoothFactor
    if (smoothAz < 0) smoothAz += 360
    if (smoothAz >= 360) smoothAz -= 360

    // Apply calibration offset
    smoothAz += this.gyroOffsetAz
    smoothAlt += this.gyroOffsetAlt
    if (smoothAz < 0) smoothAz += 360
    if (smoothAz >= 360) smoothAz -= 360
    if (smoothAlt > 90) smoothAlt = 90
    if (smoothAlt < -90) smoothAlt = -90

    // Dead zone: skip if change is too small
    let finalAzDiff = smoothAz - this.gyroLastAz
    if (finalAzDiff > 180) finalAzDiff -= 360
    if (finalAzDiff < -180) finalAzDiff += 360
    let finalAltDiff = smoothAlt - this.gyroLastAlt
    if (Math.abs(finalAzDiff) < 0.5 && Math.abs(finalAltDiff) < 0.5) {
      return
    }

    this.gyroLastAz = smoothAz
    this.gyroLastAlt = smoothAlt

    // Use moveToAltAz with duration=0 for instant response (no animation delay)
    // This gives true "point at sky" behavior
    const result = this.callNative('moveToAltAz', smoothAz.toFixed(2) + '|' + smoothAlt.toFixed(2) + '|0')
    this.gyroEventCount += 1
    if (this.gyroEventCount % 20 === 0) {
      this.gyroscopeStatus = (result.ok === true || result.pending === true) ? I18n.t('m_gyro_working') : (result.error ? result.error : I18n.t('m_gyro_core_not_ready'))
    }
  }
  private searchObject(name: string): void {
    const query = name.trim()
    if (query.length === 0) {
      return
    }
    this.flashHint(I18n.t('i0070'))
    // 保存搜索历史（去重，最多保留 20 条）
    const hist = this.searchHistory.filter(h => h !== query)
    hist.unshift(query)
    this.searchHistory = hist.slice(0, 20)
    this.saveSearchHistoryToStorage()
    this.callInteractive('searchObject', query, (result) => {
      this.applySelectedObject(result)
      if (result.found === true) {
        this.flashHint(I18n.t('i0071'))
      } else {
        this.flashHint(I18n.t('i0072'))
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
    this.detailRefreshGuard = setTimeout(() => { this.detailRefreshing = false }, 2500) as number
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
    }, 5000) as number
  }

  private stopDetailAutoRefresh(): void {
    if (this.detailTimer !== 0) { clearInterval(this.detailTimer); this.detailTimer = 0 }
    if (this.detailRefreshGuard !== 0) { clearTimeout(this.detailRefreshGuard); this.detailRefreshGuard = 0 }
    this.detailRefreshing = false
  }

  private moveToSelectedObject(): void {
    this.callInteractive('moveToSelected', '', (r) => this.applySelectedObject(r))
  }

  // 把角度格式化为「度°分'」，提高地平坐标的可见变化粒度
  // （地球自转约 15′/分钟，用分作单位几秒即可看出目标在动）
  private fmtDegMin(deg: number): string {
    let d = Math.floor(deg)
    let m = Math.round((deg - d) * 60)
    if (m >= 60) { m -= 60; d += 1 }
    if (m < 0) { m += 60; d -= 1 }
    return d + '°' + (m < 10 ? '0' + m : m.toString()) + '\''
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
    }
    return raw
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
      // 仅在“换了一个新天体”时才收起详情（保留用户已展开的偏好）；同一目标的周期性刷新不重置展开态
      const isNewSelection = (this.selectedName !== incomingName) || (this.selectedType !== incomingType) || (!this.infoWinVisible)
      this.selectedName = incomingName
      this.selectedType = incomingType
      this.selectedStatus = 'Selected'
      this.selectedMagnitude = (typeof result.magnitude === 'number') ? (result.magnitude as number).toFixed(2) : ''
      const ra: string = result.ra ? result.ra : ''
      const dec: string = result.dec ? result.dec : ''
      this.selectedCoordEq = (ra.length > 0 || dec.length > 0) ? (ra + '  ' + dec).trim() : ''
      const hasAlt: boolean = typeof result.altitude === 'number'
      const hasAz: boolean = typeof result.azimuth === 'number'
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
      this.infoWinVisible = true
      if (isNewSelection) {
        this.infoWinExpanded = false
        this.cardOffsetX = 0
        this.cardOffsetY = 0
      }
      // 尝试从本地别名表补充中文简介
      const dispName = this.selectedName
      const alias = ALIAS_LIST.find(a => a.en === dispName || a.zh === dispName)
      this.selectedInfo = alias ? alias.zh : ''
      // 换了新天体 → 按它的"性格"响一声（模仿 Sky Guide 的叮）
      if (isNewSelection) {
        AudioEngine.getInstance().chimeForSelection(result)
      }
      this.startDetailAutoRefresh()
    } else {
      // 后台刷新瞬时未命中（天体临时不可见等）时不关窗、不清数据，避免闪退式收起
      if (fromRefresh) { return }
      this.selectedName = 'Not found'
      this.selectedType = result.query && result.query.length > 0 ? result.query : 'No selection'
      this.selectedStatus = result.query && result.query.length > 0 ? 'Try English name' : 'No match'
      this.selectedMagnitude = ''
      this.selectedCoordEq = ''
      this.selectedCoordAlt = ''
      this.selectedConstellation = ''
      this.selectedDistance = ''
      this.selectedSize = ''
      this.selectedRise = ''
      this.selectedSet = ''
      this.selectedTransit = ''
      this.selectedPhase = ''
      this.selectedElongation = ''
      this.selectedRich = ''
      this.infoWinVisible = false
      this.selectedInfo = '当前位置没有可选天体，请放大或使用搜索'
    }
  }

  private formatRate(rate: number): string {
    if (rate === 0) {
      return I18n.t('msg_paused')
    }
    if (Math.abs(rate - 0.000011574074074074073) < 0.0000001) {
      return '1x'
    }
    if (rate > 0) {
      return rate.toFixed(6)
    }
    return I18n.t('msg_paused')
  }

  private formatDegrees(value: number, positive: string, negative: string): string {
    const direction = value >= 0 ? positive : negative
    return Math.abs(value).toFixed(2) + '°' + direction
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
    if (event.touches.length < 1) {
      return
    }
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.updatePickerFromMap(event.touches[0].x, event.touches[0].y)
    }
  }

  // 阻止地图触摸事件冒泡到父Scroll，防止拖动地图时面板也跟着滚动
  private stopMapTouchPropagation(event: TouchEvent): boolean {
    if (event.touches.length >= 1) {
      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        this.updatePickerFromMap(event.touches[0].x, event.touches[0].y)
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
  }

  private async useDeviceLocation(): Promise<void> {
    hilog.info(0x0000, 'StellariumArkUI', 'useDeviceLocation() called')
    this.locationPickerStatus = I18n.t('m_req_location_perm')
    try {
      const context = getContext(this) as common.UIAbilityContext
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
      // Simulator usually has no GPS; fall back to saved or default location
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
    setTimeout(() => { this.loadObserverInfo() }, 500)
  }

  private distance(x0: number, y0: number, x1: number, y1: number): number {
    const dx = x1 - x0
    const dy = y1 - y0
    return Math.sqrt(dx * dx + dy * dy)
  }


  private touchWindowX(point: TouchObject): number {
    return point.windowX ?? point.x
  }

  private touchWindowY(point: TouchObject): number {
    return point.windowY ?? point.y
  }

  private setLocation(name: string, latitude: number, longitude: number, altitude: number): void {
    // Update picker UI immediately (non-blocking, gives instant feedback)
    this.setPickerLocation(name, latitude, longitude, altitude, I18n.t('m_synced_to_sky'))
    this.locationText = name + ' · ' + this.planetZh('Earth')
    this.coordinateText = this.formatDegrees(latitude, 'N', 'S') + ' / ' + this.formatDegrees(longitude, 'E', 'W')
    this.altitudeText = altitude.toFixed(0) + ' m'
    this.flashHint(I18n.t('i0073'))
    // Async: try setLocationByName first, fallback to setLocation, then setLocationCoords
    this.callNativeWhenReady('setLocationByName', name, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.refreshState()
        setTimeout(() => { this.loadObserverInfo() }, 300)
      } else {
        // Fallback 1: push coordinates via setLocation
        hilog.info(0x0000, 'StellariumArkUI', 'setLocationByName failed, fallback to setLocation')
        this.callNativeWhenReady('setLocation', `${name}|${latitude}|${longitude}|${altitude}`, (r2: StellariumBridgeResponse) => {
          if (r2.ok === true) {
            this.refreshState()
            setTimeout(() => { this.loadObserverInfo() }, 300)
          } else {
            // Fallback 2: setLocationCoords (lat,lon[,alt]) - most reliable
            hilog.info(0x0000, 'StellariumArkUI', 'setLocation failed, fallback to setLocationCoords')
            this.callNativeWhenReady('setLocationCoords', `${latitude},${longitude},${altitude}`, (r3: StellariumBridgeResponse) => {
              if (r3.ok === true) {
                this.refreshState()
                setTimeout(() => { this.loadObserverInfo() }, 300)
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
        this.locSearchResults = rawList.map((item: Object) => {
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

  private loadObserverInfo(): void {
    this.callInteractive('getObserverInfo', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.observerTimeZone = this.timezoneDisplayName(r.timeZone ?? '')
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
        this.savedLocations = raw.map((item: Object) => {
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
        Text(kind === 'continent' ? I18n.t('h_continent') : kind === 'region' ? I18n.t('h_region') : I18n.t('h_city'))
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
              Button(this.translateContinent(item), { type: ButtonType.Normal })
                .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .width('100%')
                .fontSize(11)
                .fontColor(selected === item ? '#FFFFFFFF' : '#A8C4E0')
                .backgroundColor(selected === item ? 'rgba(91, 147, 191, 0.65)' : 'rgba(255,255,255,0.03)')
                .border({ width: selected === item ? 0 : 1, color: 'rgba(107,163,214,0.10)' })
                .borderRadius(8)
                .stateEffect(false)
                .onClick(() => onSelect(item))
            }, (item: string) => item)
          } else if (kind === 'region') {
            ForEach(this.hierRegions(), (item: string) => {
              Button(this.translateRegion(item), { type: ButtonType.Normal })
                .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .width('100%')
                .fontSize(11)
                .fontColor(selected === item ? '#FFFFFFFF' : '#A8C4E0')
                .backgroundColor(selected === item ? 'rgba(91, 147, 191, 0.65)' : 'rgba(255,255,255,0.03)')
                .border({ width: selected === item ? 0 : 1, color: 'rgba(107,163,214,0.10)' })
                .borderRadius(8)
                .stateEffect(false)
                .onClick(() => onSelect(item))
            }, (item: string) => item)
          } else {
            ForEach(this.hierCityNames(), (item: string) => {
              Button(this.translateRegion(item), { type: ButtonType.Normal })
                .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .width('100%')
                .fontSize(11)
                .fontColor(selected === item ? '#FFFFFFFF' : '#A8C4E0')
                .backgroundColor(selected === item ? 'rgba(91, 147, 191, 0.65)' : 'rgba(255,255,255,0.03)')
                .border({ width: selected === item ? 0 : 1, color: 'rgba(107,163,214,0.10)' })
                .borderRadius(8)
                .stateEffect(false)
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
    // 跟随面板真实位置（含拖动偏移），避免点面板却漏成星图拖拽
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
    // 常用区 + 分隔线 + 抽屉按钮 + 音乐按钮 + 顶部内边距
    return this.pinnedActions.length * 58 + 60 + 44 + 52 + 14 + this.RAIL_TOP_PAD
  }

  // 点击侧栏入口：打开对应面板并收起抽屉（带 400ms 防抖，避免 onClick 与 handleUiTap 双触发）
  private lastRailTapTime: number = 0
  private lastRailTapPanel: string = ''
  private onRailTap(panel: string): void {
    const now = Date.now()
    if (panel === this.lastRailTapPanel && now - this.lastRailTapTime < 400) { return }
    this.lastRailTapTime = now
    this.lastRailTapPanel = panel
    this.setPanel(panel)
    if (this.drawerOpen) {
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
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => {
      this.drawerOpen = !this.drawerOpen
    })
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
      // 紧凑布局：顶部缩放按钮和徽章由组件自身 onClick 处理，不拦截
    }
    // 左下角滑动详情卡片：标记为 UI 区域，防止 overlay 启动星图拖拽。
    // handleInfoWinTap 只处理头部关闭按钮，Swiper body 区域不拦截，
    // 让 Swiper 自身手势系统处理水平滑动。
    if (this.infoWinVisible && this.selectedName.length > 0) {
      if (this.isExpandedLayout) {
        const bcX = this.EDGE_MARGIN + 200 + this.cardOffsetX
        const bcY = this.skyHeight - 230 + this.cardOffsetY
        const bcW = 340
        const bcH = 200
        if (x >= bcX && x <= bcX + bcW && y >= bcY && y <= bcY + bcH) {
          return true
        }
      } else {
        const bcX = 16 + this.cardOffsetX
        const bcY = 70 + this.cardOffsetY
        const bcW = this.skyWidth - 32
        const bcH = 200
        if (x >= bcX && x <= bcX + bcW && y >= bcY && y <= bcY + bcH) {
          return true
        }
      }
    }
    if (this.isExpandedLayout) {
      // 左侧工具栏：只拦截实际按钮区域（44x44），按钮间空隙穿透到星图
      if (!this.railCollapsed && x >= this.EDGE_MARGIN + 7 && x <= this.EDGE_MARGIN + 51) {
        const rt = this.railTop() + this.RAIL_TOP_PAD
        // 常用入口按钮（每个 44x44，间距 58）
        for (let i = 0; i < this.pinnedActions.length; i++) {
          if (y >= rt + i * 58 && y <= rt + i * 58 + 44) { return true }
        }
        // 更多按钮
        const moreTop = rt + this.pinnedActions.length * 58 + 8
        if (y >= moreTop && y <= moreTop + 44) { return true }
        // 音乐按钮
        const musicTop = rt + this.pinnedActions.length * 58 + 60
        if (y >= musicTop && y <= musicTop + 44) { return true }
      } else if (!this.drawerOpen && x >= this.EDGE_MARGIN + 92 && x <= this.EDGE_MARGIN + 148 && y >= this.skyHeight - 364 && y <= this.skyHeight - 90) {
        return true
      }
      // 低频功能抽屉区域（展开时）
      if (this.drawerOpen && x >= this.EDGE_MARGIN + 58 && x <= this.EDGE_MARGIN + 58 + 176 && y >= this.railTop() && y <= this.railTop() + 40 + this.drawerActions.length * 46 + 14) {
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
    if (this.isExpandedLayout) {
      if (this.panelVisible && y >= this.skyHeight - this.panelMaxHeight) {
        return true
      }
      return y >= this.skyHeight - 80
    }
    // 紧凑布局：底部 Dock 由组件自身 onClick 处理，不拦截
    if (this.panelVisible && y >= this.skyHeight - this.panelMaxHeight) {
      return true
    }
    return false
  }

  private handleUiTap(x: number, y: number): boolean {
    // 防闪退保护：确保所有数组和状态变量有效
    try {
    if (!this.pinnedActions || this.pinnedActions.length === 0) { return false }
    if (typeof x !== 'number' || typeof y !== 'number' || isNaN(x) || isNaN(y)) { return false }
    // 顶部搜索栏已移除，搜索功能通过左侧图标进入分类面板
    // 浮动详情窗优先处理（其区域内已由 isUiPoint 拦截，不会落到星图选星）
    if (this.handleInfoWinTap(x, y)) { return true }

    // 低频功能抽屉项（展开时）— 必须在缩放按钮之前检查，因为两者区域可能重叠
    if (this.isExpandedLayout && this.drawerOpen && x >= this.EDGE_MARGIN + 58 && x <= this.EDGE_MARGIN + 58 + 176) {
      const itemsTop = this.railTop() + 38
      const dIdx = Math.floor((y - itemsTop) / 46)
      if (dIdx >= 0 && dIdx < this.drawerActions.length && this.drawerActions[dIdx]) {
        this.onRailTap(this.drawerActions[dIdx].panel)
        return true
      }
    }

    // zoom +/- buttons (expanded layout, bottom-left) — 抽屉打开时完全跳过
    if (this.isExpandedLayout && !this.drawerOpen && x >= this.EDGE_MARGIN + 92 && x <= this.EDGE_MARGIN + 148) {
      if (y >= this.skyHeight - 364 && y <= this.skyHeight - 280) {
        this.zoomStep(0.5)
        return true
      }
      if (y >= this.skyHeight - 154 && y <= this.skyHeight - 90) {
        this.zoomStep(2.0)
        return true
      }
    }
    if (this.isExpandedLayout && x >= this.EDGE_MARGIN + 7 && x <= this.EDGE_MARGIN + 51) {
      const railTop = this.railTop() + this.RAIL_TOP_PAD
      const step = 58
      // 常用固定入口
      const index = Math.floor((y - railTop) / step)
      const withinButton = index >= 0 && index < this.pinnedActions.length && y >= railTop + index * step && y <= railTop + index * step + 44
      if (withinButton && this.pinnedActions[index]) {
        this.onRailTap(this.pinnedActions[index].panel)
        return true
      }
      // 「更多」抽屉按钮
      const moreTop = railTop + this.pinnedActions.length * step + 8
      if (y >= moreTop && y <= moreTop + 44) {
        this.toggleDrawer()
        return true
      }
      // 音乐开关按钮
      const musicTop = railTop + this.pinnedActions.length * step + 60
      if (y >= musicTop && y <= musicTop + 44) {
        this.toggleMusic()
        return true
      }
	    }

	    // 紧凑布局的 Dock 点击由 compactDock 组件自身 onClick 处理，不走 overlay 映射

	    if (!this.panelVisible) {
	      return false
	    }

    const left = this.panelLeft()
    const top = this.panelTop()
    const right = this.panelRight()
    if (x >= right - 60 && x <= right && y >= top && y <= top + 60) {
      if (!this.uiLocked) {
        this.panelVisible = false
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
        if (x >= 1095 && x < 1155) { this.triggerAction('actionReturn_To_Current_Time'); this.setTimeRate(0.000011574074074073); return true }
        if (x >= 1155 && x < 1220) { this.triggerAction('actionDecrease_Time_Speed'); return true }
        if (x >= 1220 && x < 1280) { this.setTimeRate(0); return true }
        if (x >= 1280 && x <= 1345) { this.triggerAction('actionIncrease_Time_Speed'); return true }
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
      if (y >= 630 && y <= 690) {
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

  private handleSkyTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) {
      return
    }

    if (event.type === TouchType.Down) {
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
        if (this.drawerOpen && downX >= this.EDGE_MARGIN + 58 && downX <= this.EDGE_MARGIN + 58 + 176) {
          const itemsTop = this.railTop() + 38
          const idx = Math.floor((downY - itemsTop) / 46)
          if (idx >= 0 && idx < this.drawerActions.length && this.drawerActions[idx]) {
            this.onRailTap(this.drawerActions[idx].panel)
            return
          }
        }
        // Handle sidebar button clicks since XComponent swallows onClick events
        if (downX >= this.EDGE_MARGIN + 7 && downX <= this.EDGE_MARGIN + 51) {
          const railTop = this.railTop() + this.RAIL_TOP_PAD
          const step = 58
          // 常用固定入口
          for (let i = 0; i < this.pinnedActions.length; i++) {
            const bTop = railTop + i * step
            if (downY >= bTop && downY <= bTop + 44 && this.pinnedActions[i]) {
              this.onRailTap(this.pinnedActions[i].panel)
              return
            }
          }
          // 「更多」抽屉按钮
          const moreTop = railTop + this.pinnedActions.length * step + 8
          if (downY >= moreTop && downY <= moreTop + 44) {
            this.toggleDrawer()
            return
          }
          // 音乐开关按钮
          const musicTop = railTop + this.pinnedActions.length * step + 60
          if (downY >= musicTop && downY <= musicTop + 44) {
            this.toggleMusic()
            return
          }
        }
        return
      }
      this.skyTouchActive = true
      this.skyDragging = true
      this.touchStartX = downX
      this.touchStartY = downY
      this.touchLastX = this.touchStartX
      this.touchLastY = this.touchStartY
      this.touchMoved = false
      this.pinchActive = false
      this.nativeDragActive = false
      this.lastDragCommandMs = 0
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
        const currentDistance = this.distance(
          x, y, this.touchWindowX(points[1]), this.touchWindowY(points[1]))
        if (!this.pinchActive || this.pinchStartDistance <= 1) {
          this.pinchStartDistance = currentDistance
          this.pinchActive = true
          this.callNativeFire('zoomBy', '1|1')
        } else {
          const scale = currentDistance / this.pinchStartDistance
          this.callNativeFire('zoomBy', scale.toString() + '|0')
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
          this.callNativeFire('dragView',
            Math.round(this.touchLastX).toString() + '|' +
            Math.round(this.touchLastY).toString() + '|' +
            Math.round(x).toString() + '|' +
            Math.round(y).toString())
          this.lastDragCommandMs = now
          this.touchLastX = x
          this.touchLastY = y
        }
      }
      return
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      const x = this.touchWindowX(points[0])
      const y = this.touchWindowY(points[0])
      // End panel drag
      if (this.panelDragging) {
        this.panelDragging = false
        return
      }
      // If touch started on a UI element (sidebar/panel), do not trigger selectAt
      if (this.touchStartedOnUi || this.isUiPoint(x, y)) {
        this.touchStartedOnUi = false
        return
      }
      if (this.panelVisible) {
        const pl = this.panelLeft()
        const pr = this.panelRight()
        const pt = this.panelTop()
        if (x >= pl && x <= pr && y >= pt && y <= pt + 900) {
          this.skyTouchActive = false
          this.skyTouchFeedback = false
          return
        }
      }
      if (this.nativeDragActive) {
        this.callNativeFire('dragView',
          Math.round(this.touchLastX).toString() + '|' +
          Math.round(this.touchLastY).toString() + '|' +
          Math.round(x).toString() + '|' +
          Math.round(y).toString())
      } else if (!this.touchMoved && !this.pinchActive) {
        const payload = Math.round(this.touchStartX).toString() + '|' + Math.round(this.touchStartY).toString() + '|' + Math.round(this.skyWidth).toString() + '|' + Math.round(this.skyHeight).toString()
        hilog.info(0x0000, 'StellariumArkUI', 'selectAt payload: ' + payload)
        this.callInteractive('selectAt', payload, (result) => {
          hilog.info(0x0000, 'StellariumArkUI', 'selectAt result: ' + JSON.stringify(result))
          this.applySelectedObject(result)
          if (result.found === true) {
            this.flashHint(I18n.t('i0074'))
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

      if (this.createInfo !== undefined) {
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
          .zIndex(100)
          .animation({ duration: 0, curve: Curve.Linear })
      }

        // 画布触摸层：与 toolbar/panel 平级（都是 1234 根 Stack 的子），
      // 承接 selectAt/onTouch。关键：不能挂在 1352 全屏 UI 父上，
      // 否则会抑制其子组件（toolbar/面板按钮）的 onClick。
      // 参考已验证的 compactShell：onTouch 挂在独立 Blank 上而非全屏 UI 父。
      Stack() { }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
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
            Text(I18n.t('i0001'))
              .fontSize(14).fontColor("#99FFFFFF")
              .opacity(this.splashIn ? 1 : 0)
              .animation({ duration: 600, curve: Curve.EaseOut, delay: 150 })
              .margin({ bottom: 26 })
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
        .onClick(() => { this.dismissSplash() })
        .onAppear(() => {
          this.startTwinkle()
          this.getUIContext().animateTo({ duration: 700, curve: Curve.EaseOut }, () => {
            this.splashIn = true
            this.splashOpacity = 1
          })
        })
      }
      // 夜间红滤镜覆盖层（Stellarium 经典功能：保护暗适应视力）
      if (this.nightMode) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(255, 20, 0, 0.22)')
          .hitTestBehavior(HitTestMode.Transparent)
          .zIndex(99)
      }
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
        const wasExpanded = this.isExpandedLayout
        this.isExpandedLayout = this.skyWidth >= 900
        this.panelWidth = Math.min(Math.max(this.skyWidth * 0.28, 280), 400)
        this.panelMaxHeight = Math.min(this.skyHeight * 0.78, 700)
        // Switched to compact layout: auto-close panel so user sees star map + dock
        if (wasExpanded && !this.isExpandedLayout) {
          this.panelVisible = false
        }
        hilog.info(0x0000, "StellariumArkUI", "onAreaChange w=%{public}s h=%{public}s expanded=%{public}s", this.skyWidth.toString(), this.skyHeight.toString(), this.isExpandedLayout.toString())
      })
  }
  @Builder
  harmonyShell() {
      Stack() {
        if (this.isExpandedLayout) {
        this.expandedShell()
      } else {
        this.compactShell()
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
          .position({ x: 0, y: this.isExpandedLayout ? 16 : 80 })
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
      .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  expandedShell() {
    Stack() {
      // 左上角 Stellarium 常驻标已移除，避免遮挡星图
      Stack() { this.railShell() }
        .position({ x: this.EDGE_MARGIN, y: this.railTop() })
        .hitTestBehavior(HitTestMode.Default)
      // 低频功能抽屉：贴着侧栏右侧滑出
      if (this.drawerOpen) {
        Stack() { this.actionDrawer() }
          .position({ x: this.EDGE_MARGIN + 58, y: this.railTop() })
          .width(176)
          .height(this.drawerActions.length * 46 + 58)
          .hitTestBehavior(HitTestMode.Default)
          .zIndex(6)
      }
      // FPS counter (always visible for debugging)
      Text(this.fpsDisplay.toString() + ' FPS')
        .fontSize(11)
        .fontColor(this.fpsDisplay >= 55 ? '#7FD0FF' : (this.fpsDisplay >= 30 ? '#FFD479' : '#FF6B6B'))
        .fontFamily('monospace')
        .fontWeight(FontWeight.Bold)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('rgba(0, 0, 0, 0.6)')
        .borderRadius(8)
        .position({ x: this.EDGE_MARGIN + 58, y: this.EDGE_MARGIN + 52 })
        .zIndex(80)
        .hitTestBehavior(HitTestMode.None)
      if (!this.drawerOpen) {
        Stack() { this.zoomButton('zoom_in') }
          .hitTestBehavior(HitTestMode.Block)
          .position({ x: this.EDGE_MARGIN + 92, y: this.skyHeight - 360 })
          .onClick(() => {
            this.zoomStep(0.5)
            this.flashHint(I18n.t('i0076'))
          })
      }
      if (!this.drawerOpen) {
        Stack() { this.zoomButton('zoom_out') }
          .hitTestBehavior(HitTestMode.Block)
          .position({ x: this.EDGE_MARGIN + 92, y: this.skyHeight - 260 })
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
          .hitTestBehavior(HitTestMode.Transparent)
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
      // 搜索功能通过左侧搜索图标 → 天体分类面板
      // 左下角滑动详情卡片（选中天体时显示，Swiper 自带左右滑动切换）
      if (this.infoWinVisible && this.selectedName.length > 0) {
        Stack() { this.bottomDetailCard() }
          .position({ x: this.EDGE_MARGIN + 200 + this.cardOffsetX, y: this.skyHeight - 230 + this.cardOffsetY })
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
      .width('100%')
      .height('100%')
      .zIndex(1)
      .hitTestBehavior(HitTestMode.Transparent)
    }

  @Builder
  compactShell() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 星图触摸层（全屏）
      Column()
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => {
          this.handleSkyTouch(event)
        })

      // 顶部信息栏：左侧缩放按钮（紧凑） + 右侧观测者徽章
      Row() {
        // 左侧：两个缩放按钮，紧凑但留缝隙
        Row({ space: 6 }) {
          Stack() {
            Image(this.getIcon('zoom_in', false))
              .width(18).height(18).fillColor(this.nmText())
          }
          .width(36).height(36)
          .backgroundColor('rgba(25, 26, 28, 0.72)')
          .backdropBlur(22)
          .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
          .borderRadius(18)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.triggerAction('actionZoom_In_Auto') })

          Stack() {
            Image(this.getIcon('zoom_out', false))
              .width(18).height(18).fillColor(this.nmText())
          }
          .width(36).height(36)
          .backgroundColor('rgba(25, 26, 28, 0.72)')
          .backdropBlur(22)
          .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
          .borderRadius(18)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.triggerAction('actionZoom_Out_Auto') })
        }

        Blank()

        this.observerBadge()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .position({ x: 0, y: 0 })
      .zIndex(3)

      // 陀螺仪校准面板
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

      // 选中天体详情卡片（显示在最上端，可拖动）
      if (this.infoWinVisible && this.selectedName.length > 0 && !this.panelVisible) {
        Stack() { this.bottomDetailCard() }
          .position({ x: 16 + this.cardOffsetX, y: 70 + this.cardOffsetY })
          .zIndex(50)
          .hitTestBehavior(HitTestMode.Default)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: 0, y: -40 }).animation({ duration: 420, curve: curves.springMotion(0.55, 0.85) })),
            TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
              .combine(TransitionEffect.translate({ x: 0, y: -20 }).animation({ duration: 200, curve: Curve.EaseIn }))
          ))
      }

      // 底部弹出半屏面板（带弹簧动画）
      if (this.panelVisible) {
        this.bottomSheetPanel()
      }

      // 紧凑底部 Dock（图标条）
      if (!this.panelVisible) {
        this.compactDock()
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(1)
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
          if (value.length > 0) {
            this.searchSuggestions = this.aliasHits(value)
          } else {
            this.searchSuggestions = []
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

  // ── 左下角滑动详情卡片（三栏水平滑动） ──
  @Builder
  bottomDetailCard() {
    Column() {
      // 拖拽手柄（可拖动整个卡片）
      Row()
        .width(28)
        .height(3)
        .backgroundColor('rgba(255, 255, 255, 0.25)')
        .borderRadius(1.5)
        .margin({ top: 8, bottom: 4 })
      // 头部：天体名称 + 类型 + 关闭（可拖动）
      Row() {
        Image(this.getIcon('info', false))
          .width(16).height(16).fillColor('#5B93BF').margin({ right: 8 })
        Text(this.zhNameOf(this.selectedName))
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.zhType(this.selectedType))
          .fontSize(10).fontColor('#7FB3DC')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor('rgba(91,147,191,0.15)').borderRadius(6)
        Text('\u2702')
          .fontSize(11).fontColor('#8099BBCC').padding({ left: 6, right: 4 })
        Text('\u2715')
          .fontSize(13).fontColor('#99FFFFFF').padding({ left: 4, right: 4 })
          .onClick(() => { this.infoWinVisible = false })
      }
      .width('100%').padding({ left: 14, right: 12, top: 6, bottom: 8 })
      .gesture(
        PanGesture({ fingers: 1, distance: 5 })
          .onActionStart((event: GestureEvent) => {
            this.cardDragStartX = this.cardOffsetX
            this.cardDragStartY = this.cardOffsetY
          })
          .onActionUpdate((event: GestureEvent) => {
            let newX: number = this.cardDragStartX + event.offsetX
            let newY: number = this.cardDragStartY + event.offsetY
            const cardW: number = this.isExpandedLayout ? 340 : (this.skyWidth - 32)
            const cardH: number = 200
            newX = Math.max(-cardW * 0.6, Math.min(newX, this.skyWidth - cardW * 0.4))
            newY = Math.max(-cardH * 0.5, Math.min(newY, this.skyHeight - 100))
            this.cardOffsetX = newX
            this.cardOffsetY = newY
          })
      )

      Divider().color('rgba(91,147,191,0.15)').margin({ left: 8, right: 8 })

      // 滑动分栏区域（三页：概览 / 时间 / 详情）
      Swiper() {
        // ── 第一页：概览（关键数据卡片 + 坐标） ──
        Column({ space: 0 }) {
          // 数据卡片行：视星等 + 距离
          Row({ space: 8 }) {
            if (this.selectedMagnitude.length > 0) {
              Column() {
                Text(I18n.t('i0007')).fontSize(9).fontColor('#8099BBCC')
                Text(this.selectedMagnitude).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#7FB3DC').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8, left: 10, right: 10 })
              .backgroundColor('rgba(91,147,191,0.08)')
              .borderRadius(10)
              .layoutWeight(1)
            }
            if (this.selectedDistance.length > 0) {
              Column() {
                Text(I18n.t('i0011')).fontSize(9).fontColor('#8099BBCC')
                Text(this.selectedDistance).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#7FB3DC').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8, left: 10, right: 10 })
              .backgroundColor('rgba(91,147,191,0.08)')
              .borderRadius(10)
              .layoutWeight(1)
            }
          }.width('100%').padding({ left: 14, right: 14, top: 10 })

          // 数据卡片行：大小 + 星座
          Row({ space: 8 }) {
            if (this.selectedSize.length > 0) {
              Column() {
                Text(I18n.t('i0290')).fontSize(9).fontColor('#8099BBCC')
                Text(this.selectedSize).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#7FB3DC').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8, left: 10, right: 10 })
              .backgroundColor('rgba(91,147,191,0.08)')
              .borderRadius(10)
              .layoutWeight(1)
            }
            if (this.selectedConstellation.length > 0) {
              Column() {
                Text(I18n.t('i0010')).fontSize(9).fontColor('#8099BBCC')
                Text(this.zhNameOf(this.selectedConstellation)).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#7FB3DC').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8, left: 10, right: 10 })
              .backgroundColor('rgba(91,147,191,0.08)')
              .borderRadius(10)
              .layoutWeight(1)
            }
          }.width('100%').padding({ left: 14, right: 14, top: 6 })

          // 坐标信息
          if (this.selectedCoordEq.length > 0) {
            Row() {
              Text(I18n.t('i0008')).fontSize(10).fontColor('#8099BBCC').width(56)
              Text(this.selectedCoordEq).fontSize(11).fontColor('#CCFFFFFF').layoutWeight(1)
            }.width('100%').padding({ left: 14, right: 14, top: 8, bottom: 2 })
          }
          if (this.selectedCoordAlt.length > 0) {
            Row() {
              Text(I18n.t('i0009')).fontSize(10).fontColor('#8099BBCC').width(56)
              Text(this.selectedCoordAlt).fontSize(11).fontColor('#CCFFFFFF').layoutWeight(1)
            }.width('100%').padding({ left: 14, right: 14, top: 2, bottom: 6 })
          }
        }
        .width('100%')
        .padding({ bottom: 14 })

        // ── 第二页：时间（升起/中天/落下 + 月相/距角） ──
        Column({ space: 0 }) {
          // 时间卡片行：升起 / 中天 / 落下
          Row({ space: 6 }) {
            if (this.selectedRise.length > 0) {
              Column() {
                Text(I18n.t('s0700')).fontSize(9).fontColor('#8099BBCC')
                Text(this.selectedRise).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#7FB3DC').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8, left: 8, right: 8 })
              .backgroundColor('rgba(91,147,191,0.08)')
              .borderRadius(10)
              .layoutWeight(1)
            }
            if (this.selectedTransit.length > 0) {
              Column() {
                Text(I18n.t('s0701')).fontSize(9).fontColor('#8099BBCC')
                Text(this.selectedTransit).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#7FB3DC').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8, left: 8, right: 8 })
              .backgroundColor('rgba(91,147,191,0.08)')
              .borderRadius(10)
              .layoutWeight(1)
            }
            if (this.selectedSet.length > 0) {
              Column() {
                Text(I18n.t('s0702')).fontSize(9).fontColor('#8099BBCC')
                Text(this.selectedSet).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#7FB3DC').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8, left: 8, right: 8 })
              .backgroundColor('rgba(91,147,191,0.08)')
              .borderRadius(10)
              .layoutWeight(1)
            }
          }.width('100%').padding({ left: 14, right: 14, top: 10 })

          // 月相 / 距角
          Row({ space: 8 }) {
            if (this.selectedPhase.length > 0) {
              Column() {
                Text(I18n.t('i0291')).fontSize(9).fontColor('#8099BBCC')
                Text(this.selectedPhase).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#7FB3DC').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8, left: 10, right: 10 })
              .backgroundColor('rgba(91,147,191,0.08)')
              .borderRadius(10)
              .layoutWeight(1)
            }
            if (this.selectedElongation.length > 0) {
              Column() {
                Text(I18n.t('i0255')).fontSize(9).fontColor('#8099BBCC')
                Text(this.selectedElongation).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#7FB3DC').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8, left: 10, right: 10 })
              .backgroundColor('rgba(91,147,191,0.08)')
              .borderRadius(10)
              .layoutWeight(1)
            }
          }.width('100%').padding({ left: 14, right: 14, top: 6 })

        }
        .width('100%')
        .padding({ bottom: 14 })

        // ── 第三页：天体标识（可展开/收起） ──
        Column({ space: 0 }) {
          if (this.selectedRich.length > 0) {
            // 标题行：点击可展开/收起
            Row() {
              Text(I18n.t('i0300')).fontSize(11).fontColor('#8099BBCC').layoutWeight(1)
              Text(this.infoTextExpanded ? '▲' : '▼').fontSize(10).fontColor('#8099BBCC')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 6 })
            .onClick(() => { this.infoTextExpanded = !this.infoTextExpanded })

            // 内容：展开时显示全部，收起时显示 2 行
            Column() {
              Text(this.richZh(this.selectedRich))
                .fontSize(10).fontColor('#AAFFFFFF').lineHeight(16)
                .maxLines(this.infoTextExpanded ? 20 : 2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 4, bottom: 8 })
            .backgroundColor('rgba(91,147,191,0.05)')
            .borderRadius(10)
            .margin({ left: 14, right: 14 })
          }

        }
        .width('100%')
        .padding({ bottom: 14 })
      }
      .index(this.bottomCardIndex)
      .indicator(true)
      .indicatorStyle({ selectedColor: '#5B93BF', color: 'rgba(255,255,255,0.3)', size: 6 })
      .duration(300)
      .curve(curves.springMotion(0.5, 0.85))
      .width('100%')
      .height(110)

      // 统一操作按钮行（在 Swiper 下方，三页共享）
      Row({ space: 8 }) {
        Button(I18n.t('btn_center'))
          .fontSize(12).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(91,147,191,0.25)').borderRadius(12).height(30).layoutWeight(1)
          .onClick(() => { this.moveToSelectedObject() })
        Button(this.trackingText === 'On' ? I18n.t('btn_untrack') : I18n.t('btn_track'))
          .fontSize(12).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(91,147,191,0.25)').borderRadius(12).height(30).layoutWeight(1)
          .onClick(() => { this.toggleTracking() })
      }
      .width('100%').padding({ left: 14, right: 14, top: 2, bottom: 8 })
    }
    .width(this.isExpandedLayout ? 340 : (this.skyWidth - 32))
    .backgroundColor('rgba(12, 16, 28, 0.78)')
    .backdropBlur(40)
    .border({ width: 0.5, color: 'rgba(91, 147, 191, 0.18)' })
    .borderRadius(20)
    .shadow({ radius: 20, color: 'rgba(0,0,0,0.30)', offsetX: 0, offsetY: 8 })
  }

  // 底部详情卡片触摸交互：只处理头部关闭按钮，
  // Swiper body 区域返回 false，让 Swiper 自身手势系统处理水平滑动。
  private handleInfoWinTap(x: number, y: number): boolean {
    if (!this.infoWinVisible) { return false }
    // bottomDetailCard 坐标（与 expandedShell/compactShell 中的 position 一致）
    let bcX: number = 0
    let bcY: number = 0
    const bcW = this.isExpandedLayout ? 340 : (this.skyWidth - 32)
    if (this.isExpandedLayout) {
      bcX = this.EDGE_MARGIN + 200 + this.cardOffsetX
      bcY = this.skyHeight - 230 + this.cardOffsetY
    } else {
      bcX = 16 + this.cardOffsetX
      bcY = 70 + this.cardOffsetY
    }
    if (x < bcX - 8 || x > bcX + bcW + 8 || y < bcY - 8) { return false }
    // 只处理头部区域（前 ~48px：名称 + 类型 + 关闭按钮）
    const headerH = 48
    if (y <= bcY + headerH) {
      const closeW = 40
      if (x >= bcX + bcW - closeW) {
        this.infoWinVisible = false
        return true
      }
      // 头部其他区域点击不做任何操作
      return true
    }
    // Swiper body 区域：返回 false，不消费触摸。
    // isUiPoint 已返回 true，所以 handleSkyTouch 不会被调用。
    // Swiper 自身手势系统可以正常处理水平滑动。
    return false
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
      .backgroundColor('rgba(20,21,23,0.92)')
      .backdropBlur(26)
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
      .backgroundColor('rgba(25, 26, 28, 0.72)')
      .backdropBlur(26)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(28)
      .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: 8 })
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
      .position({ x: 7, y: this.RAIL_TOP_PAD + this.pinnedActions.length * 58 + 116 })
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
            this.flashHint(I18n.t('i0078'))
          })
          .hitTestBehavior(HitTestMode.Block)
      }
    }
  }

  @Builder
  compactDock() {
    Row() {
      ForEach(this.pinnedActions, (item: ShellAction) => {
        Column() {
          Image(this.getIcon(item.icon, this.activePanel === item.panel && this.panelVisible))
            .width(20)
            .height(20)
            .fillColor(this.activePanel === item.panel && this.panelVisible ? '#5B93BF' : '#B0FFFFFF')
        }
          .width(40)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.activePanel === item.panel && this.panelVisible ? 'rgba(91, 147, 191, 0.18)' : Color.Transparent)
          .borderRadius(20)
          .scale({ x: this.activePanel === item.panel && this.panelVisible ? 1.12 : 1.0, y: this.activePanel === item.panel && this.panelVisible ? 1.12 : 1.0 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 300, curve: curves.springMotion(0.42, 0.82) })
          .onClick(() => {
            this.setPanel(item.panel)
          })
      }, (item: ShellAction) => item.panel)
      // 更多按钮：展开抽屉项
      Column() {
        Image(this.getIcon('grid', false))
          .width(20)
          .height(20)
          .fillColor(this.drawerOpen ? '#5B93BF' : '#B0FFFFFF')
      }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.drawerOpen ? 'rgba(91, 147, 191, 0.18)' : Color.Transparent)
        .borderRadius(20)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .animation({ duration: 300, curve: curves.springMotion(0.42, 0.82) })
        .onClick(() => {
          this.toggleDrawer()
        })
    }
      .height(52)
      .width('auto')
      .padding({ left: 10, right: 10 })
      .justifyContent(FlexAlign.SpaceEvenly)
      .backgroundColor('rgba(18, 22, 36, 0.78)')
      .backdropBlur(30)
      .border({ width: 0.5, color: 'rgba(91, 147, 191, 0.12)' })
      .borderRadius(26)
      .shadow({ radius: 24, color: 'rgba(0, 0, 0, 0.36)', offsetX: 0, offsetY: 10 })
      .margin({ bottom: 16 })
      .alignSelf(ItemAlign.Center)
      // 弹出动画
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 0, y: 60 }).animation({ duration: 400, curve: curves.springMotion(0.5, 0.85) })),
        TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseIn })
          .combine(TransitionEffect.translate({ x: 0, y: 30 }).animation({ duration: 180, curve: Curve.EaseIn }))
      ))
  }

  @Builder
  bottomDock() {
    Row() {
      // 窄屏底栏同样只放常用入口，其余入口在展开面板里可达
      ForEach(this.pinnedActions, (item: ShellAction) => {
        this.dockButton(item)
      }, (item: ShellAction) => item.panel)
    }
      .height(66)
      .width('92%')
      .padding({ left: 8, right: 8 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor('rgba(25, 26, 28, 0.78)')
      .backdropBlur(26)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(33)
      .shadow({ radius: 28, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: 14 })
      .alignSelf(ItemAlign.Center)
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

  private pluginZh(en: string): ResourceStr {
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
      default: return en
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
      'zoom_in': $r('app.media.ic_zoom_in'),
      'zoom_out': $r('app.media.ic_zoom_out'),
      'lock': $r('app.media.ic_lock'),
      'unlock': $r('app.media.ic_unlock'),
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
      Text('\u266A')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.musicEnabled ? '#7FD0FF' : '#5A6270')
        .opacity(this.musicEnabled ? 1.0 : 0.45)
        .textAlign(TextAlign.Center)
        .animation({ duration: 200, curve: curves.springMotion(0.42, 0.85) })
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

  // ── 陀螺仪按钮 ──
  @Builder
  gyroButton() {
    Stack() {
      // 外圈：旋转的轨道环
      Circle()
        .width(28)
        .height(28)
        .fill('none')
        .stroke(this.gyroscopeEnabled ? '#7FD0FF' : '#5A6270')
        .strokeWidth(1.5)
        .opacity(this.gyroscopeEnabled ? 0.8 : 0.4)
      // 中圈：十字准星
      Circle()
        .width(16)
        .height(16)
        .fill('none')
        .stroke(this.gyroscopeEnabled ? '#7FD0FF' : '#5A6270')
        .strokeWidth(1)
        .opacity(this.gyroscopeEnabled ? 0.6 : 0.3)
      // 中心点
      Circle()
        .width(5)
        .height(5)
        .fill(this.gyroscopeEnabled ? '#7FD0FF' : '#5A6270')
        .opacity(this.gyroscopeEnabled ? 1.0 : 0.5)
      // 十字线
      if (this.gyroscopeEnabled) {
        Line().width(2).height(10)
          .stroke('#7FD0FF').strokeWidth(1)
          .position({ x: 21, y: 6 })
        Line().width(2).height(10)
          .stroke('#7FD0FF').strokeWidth(1)
          .position({ x: 21, y: 28 })
        Line().width(10).height(2)
          .stroke('#7FD0FF').strokeWidth(1)
          .position({ x: 6, y: 21 })
        Line().width(10).height(2)
          .stroke('#7FD0FF').strokeWidth(1)
          .position({ x: 28, y: 21 })
      }
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
            this.flashHint(I18n.t('i0053'))
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
    .backgroundColor('rgba(12, 16, 28, 0.85)')
    .backdropBlur(40)
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

  // 低频功能抽屉：从侧栏右侧滑出，图标 + 名称，一行一项
  @Builder
  actionDrawer() {
    Column({ space: 2 }) {
      Text(I18n.t('c_more_functions'))
        .fontSize(12)
        .fontColor(this.nmSub())
        .width('100%')
        .padding({ left: 14, top: 10, bottom: 4 })
      ForEach(this.drawerActions, (item: ShellAction) => {
        Row({ space: 12 }) {
          Image(this.getIcon(item.icon, this.activePanel === item.panel && this.panelVisible))
            .width(20).height(20)
            .fillColor(this.activePanel === item.panel && this.panelVisible ? '#7FB3DC' : this.nmText())
          Text(item.label)
            .fontSize(14)
            .fontColor(this.activePanel === item.panel && this.panelVisible ? '#7FB3DC' : this.nmText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
          .width('100%')
          .height(44)
          .padding({ left: 14, right: 12 })
          .borderRadius(12)
          .backgroundColor(this.activePanel === item.panel && this.panelVisible ? 'rgba(91, 147, 191, 0.18)' : 'rgba(0,0,0,0)')
          .onClick(() => {
            this.onRailTap(item.panel)
          })
      }, (item: ShellAction) => item.panel)
    }
      .width(176)
      .padding({ top: 4, bottom: 10, left: 6, right: 6 })
      .backgroundColor('rgba(25, 26, 28, 0.86)')
      .backdropBlur(30)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.10)' })
      .borderRadius(20)
      .shadow({ radius: 30, color: 'rgba(0, 0, 0, 0.40)', offsetX: 6, offsetY: 10 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: -40, y: 0 }).animation({ duration: 420, curve: curves.springMotion(0.5, 0.82) })),
        TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
          .combine(TransitionEffect.translate({ x: -24, y: 0 }).animation({ duration: 200, curve: Curve.EaseIn }))
      ))
  }

  @Builder
  dockButton(item: ShellAction) {
    Column() {
      Text(item.icon)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.activePanel === item.panel && this.panelVisible ? '#FFFFFF' : '#E5FFFFFF')
        .lineHeight(18)
        .textAlign(TextAlign.Center)
        .width('100%')
      Text(item.label)
        .fontSize(10)
        .fontColor(this.activePanel === item.panel && this.panelVisible ? '#F0FFFFFF' : '#99FFFFFF')
        .margin({ top: 2 })
    }
      .width(54)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.activePanel === item.panel && this.panelVisible ? '#5B93BF' : Color.Transparent)
      .borderRadius(26)
      .scale({ x: this.activePanel === item.panel && this.panelVisible ? 1.06 : 1.0, y: this.activePanel === item.panel && this.panelVisible ? 1.06 : 1.0 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.92, y: 0.92 })
          .backgroundColor('rgba(255, 255, 255, 0.10)')
        }
      })
      .animation({ duration: 260, curve: curves.springMotion(0.42, 0.85) })
      .onClick(() => {
        this.setPanel(item.panel)
        this.flashHint(I18n.t('i0078'))
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
      }
        .width('100%')
        .layoutWeight(1)
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
  bottomSheetPanel() {
    Column() {
      // 拖拽手柄（可拖动调整面板高度）
      Row()
        .width(36)
        .height(4)
        .backgroundColor('rgba(255, 255, 255, 0.30)')
        .borderRadius(2)
        .margin({ top: 10, bottom: 8 })
        .gesture(
          PanGesture({ fingers: 1, distance: 5 })
            .onActionStart((event: GestureEvent) => {
              this.sheetDragStartY = event.fingerList[0].localY
              this.sheetDragStartPct = this.sheetHeightPct
            })
            .onActionUpdate((event: GestureEvent) => {
              const deltaY = event.offsetY
              const skyH = this.skyHeight > 1 ? this.skyHeight : 800
              const pctDelta = -deltaY / skyH * 100
              let newPct = this.sheetDragStartPct + pctDelta
              newPct = Math.max(50, Math.min(90, newPct))
              this.sheetHeightPct = newPct
            })
        )
      // 面板标题栏
      Row() {
        Text(this.panelTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E5FFFFFF')
          .layoutWeight(1)
        // 关闭按钮
        Text('\u00d7')
          .fontSize(22)
          .fontColor('#99FFFFFF')
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.closePanel() })
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 8 })
      // 面板内容（可滚动）
      Scroll() {
        Column() {
          this.panelContent()
        }
          .width('100%')
      }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .scrollBarWidth(4)
        .scrollBarColor('#33FFFFFF')
    }
      .width('100%')
      .height(this.sheetHeightPct + '%')
      .padding({ left: 18, right: 18, bottom: 20 })
      .backgroundColor(this.panelIdleGlass ? 'rgba(10, 14, 26, 0.72)' : 'rgba(18, 22, 36, 0.88)')
      .backdropBlur(this.panelIdleGlass ? 45 : 35)
      .border({ width: 0.5, color: this.panelIdleGlass ? 'rgba(91, 147, 191, 0.20)' : 'rgba(91, 147, 191, 0.14)' })
      .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 0, bottomRight: 0 })
      .shadow({ radius: 40, color: 'rgba(0, 0, 0, 0.50)', offsetX: 0, offsetY: -10 })
      // 从底部弹出弹簧动画
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 0, y: 400 }).animation({ duration: 520, curve: curves.springMotion(0.62, 0.88) })),
        TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
          .combine(TransitionEffect.translate({ x: 0, y: 200 }).animation({ duration: 320, curve: curves.springMotion(0.5, 0.85) }))
      ))
  }

  @Builder
  panelHandle() {
    Row()
      .width(36)
      .height(4)
      .backgroundColor('rgba(255, 255, 255, 0.30)')
      .borderRadius(2)
      .alignSelf(ItemAlign.Center)
      .margin({ bottom: 10 })
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
        Image(this.uiLocked ? $r('app.media.ic_lock') : $r('app.media.ic_unlock'))
          .width(18)
          .height(18)
          .fillColor(this.uiLocked ? '#FFD700' : '#99FFFFFF')
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.uiLocked ? 'rgba(255, 215, 0, 0.15)' : 'rgba(255, 255, 255, 0.06)')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.uiLocked = !this.uiLocked
        this.flashHint(this.uiLocked ? I18n.t('s0717') : I18n.t('s0718'))
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
	      this.lx200ObjectControls()
      } // end object selectedName else
    } else if (this.activePanel === 'time') {
      this.infoRow(I18n.t('i0054'), this.observationTimeText)
      this.infoRow(I18n.t('i0055'), this.timeRateText)
      this.infoRow(I18n.t('i0056'), this.timeRateText === I18n.t('msg_paused') ? I18n.t('s0756') : I18n.t('s0757'))
      this.quickChips([{ id: 'now', label: I18n.t('s0754') }, { id: 'back', label: I18n.t('s0755') }, { id: 'pause', label: I18n.t('s0756') }, { id: 'forward', label: I18n.t('s0757') }])
      this.quickChips([{ id: '+12h', label: '+12h' }, { id: '-12h', label: '-12h' }])
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
            DatePickerDialog.show({
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
            TimePickerDialog.show({
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
      this.pointingTestSection()
      this.watchGyroSection()
      this.continuationSection()
      this.tonightEventsSection()
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
          } else {
            this.viewSurveysTab()
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
          this.switchRow(I18n.t('s0303'), this.gyroscopeEnabled, '')
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
              .onClick(() => { this.triggerAction('actionDecrease_Time_Speed') })
            Button(I18n.t('i0245')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmAccent())
              .borderRadius(14).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.setTimeRate(1) })
            Button(I18n.t('i0246')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(14).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.triggerAction('actionIncrease_Time_Speed') })
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
            Text(this.currentProjection).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          Scroll() {
            Row({ space: 6 }) {
              ForEach(['Perspective', 'Stereographic', 'Fisheye', 'HammerAitoff', 'Mercator', 'Orthographic'], (name: string) => {
                Text(name)
                  .fontSize(11).fontColor(this.currentProjection === name ? '#FFFFFFFF' : '#99FFFFFF')
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                  .backgroundColor(this.currentProjection === name ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.05)')
                  .borderRadius(8)
                  .onClick(() => { this.setProjection(name) })
              }, (name: string) => name)
            }.padding({ left: 4, right: 4 })
          }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
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
              Text('km')
                .fontSize(11).fontColor(this.useMetricUnits ? '#FFFFFFFF' : '#99FFFFFF')
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.useMetricUnits ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.05)')
                .borderRadius(8)
                .onClick(() => {
                  this.useMetricUnits = true
                  this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=true', () => {})
                })
              Text('mi')
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
        }.width('100%')
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'search') {
      // ── 天体分类浏览面板 ──
      // 快选行星
      Row() {
        Text(I18n.t('s0743')).fontSize(10).fontColor(this.nmSub()).width(52)
        Scroll() {
          Row({ space: 4 }) {
            ForEach(['Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune'], (p: string) => {
              Text(this.planetZh(p)).fontSize(11).fontColor(this.nmText()).padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(this.nmBg()).borderRadius(12)
                .onClick(() => { this.searchObject(p) })
            })
          }.padding({ left: 2 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
      }.width('100%').padding({ left: 10, right: 10 }).margin({ top: 6 })
      // 快选恒星
      Row() {
        Text(I18n.t('s0744')).fontSize(10).fontColor(this.nmSub()).width(52)
        Scroll() {
          Row({ space: 4 }) {
            ForEach(['Sirius', 'Canopus', 'Arcturus', 'Vega', 'Rigel', 'Betelgeuse', 'Polaris'], (s: string) => {
              Text(this.zhNameOf(s)).fontSize(11).fontColor(this.nmText()).padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(this.nmBg()).borderRadius(12)
                .onClick(() => { this.searchObject(s) })
            })
          }.padding({ left: 2 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
      }.width('100%').padding({ left: 10, right: 10 }).margin({ top: 4 })
      // 天体分类浏览（按分类 tab 切换，点击加载该分类天体列表）
      Row() {
        Text(I18n.t('i0021')).fontSize(12).fontColor(this.nmSub()).width(72)
        Row({ space: 4 }) {
          ForEach([
            { code: 'planet', label: I18n.t('i0103') },
            { code: 'star', label: I18n.t('i0104') },
            { code: 'galaxy', label: I18n.t('i0105') },
            { code: 'cluster', label: I18n.t('i0106') },
            { code: 'nebula', label: I18n.t('i0107') },
            { code: 'messier', label: I18n.t('i0108') },
          ] as CatOption[], (cat: CatOption) => {
            Text(cat.label)
              .fontSize(11).fontColor(this.searchCategory === cat.code ? this.nmText() : this.nmSub())
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.searchCategory === cat.code ? this.nmAccent() : this.nmBg())
              .borderRadius(8)
              .scale({ x: this.searchCategory === cat.code ? 1.06 : 1.0, y: this.searchCategory === cat.code ? 1.06 : 1.0 })
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .animation({ duration: 220, curve: curves.springMotion(0.5, 1.0) })
              .onClick(() => this.loadCategoryObjects(cat.code))
          }, (cat: CatOption) => cat.code)
        }.layoutWeight(1)
      }
      .height(32).width('100%')
      // 分类天体列表（fallback: listObjects 不可用时显示预设常用天体）
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.categoryObjects.length > 0 ? this.categoryObjects : [
            { name: 'Moon', zh: '月球' } as NameItem, { name: 'Mars', zh: '火星' } as NameItem, { name: 'Jupiter', zh: '木星' } as NameItem, { name: 'Saturn', zh: '土星' } as NameItem,
            { name: 'Sirius', zh: '天狼星' } as NameItem, { name: 'Vega', zh: '织女星' } as NameItem, { name: 'Betelgeuse', zh: '参宿四' } as NameItem, { name: 'Polaris', zh: '北极星' } as NameItem,
            { name: 'M31', zh: '仙女座星系' } as NameItem, { name: 'M42', zh: '猎户座大星云' } as NameItem, { name: 'M45', zh: '昴星团' } as NameItem, { name: 'M13', zh: '武仙座球状星团' } as NameItem,
            { name: 'M8', zh: '礁湖星云' } as NameItem, { name: 'NGC 7000', zh: '北美洲星云' } as NameItem, { name: 'Double Cluster', zh: '双星团' } as NameItem,
          ] as NameItem[], (item: NameItem) => {
            Button(item.zh ?? item.name ?? '')
              .fontSize(11).fontColor(this.nmText())
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor(this.nmBg()).borderRadius(8)
              .height(24)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.animation({ duration: 260, curve: curves.springMotion(0.5, 1.0) })
                  .combine(TransitionEffect.translate({ x: -12 }).animation({ duration: 280, curve: curves.springMotion(0.5, 1.0) })),
                TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
                  .combine(TransitionEffect.translate({ x: 12 }).animation({ duration: 180, curve: Curve.EaseIn }))
              ))
              .onClick(() => this.searchObject(item.name ?? ''))
          }, (item: NameItem) => this.searchCategory + '/' + item.name)
        }.padding({ left: 4, right: 4 })
      }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

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
                .onClick(() => { this.searchObject(c) })
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
          { label: I18n.t('c0004'), id: 4 },
          { label: I18n.t('c0005'), id: 5 },
          { label: I18n.t('c0006'), id: 6 },
        ] as TabItem[], (tab: TabItem) => {
          Text(tab.label)
            .fontSize(10)
            .fontColor(this.configTab === tab.id ? this.nmText() : this.nmSub())
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.configTab === tab.id ? this.nmAccent() : this.nmBg())
            .borderRadius(6)
            .scale({ x: this.configTab === tab.id ? 1.06 : 1.0, y: this.configTab === tab.id ? 1.06 : 1.0 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .animation({ duration: 220, curve: curves.springMotion(0.5, 1.0) })
            .onClick(() => { this.configTab = tab.id })
        }, (tab: TabItem, index: number) => tab.id.toString())
      }.width('100%').padding({ left: 2, right: 2 }).margin({ top: 4, bottom: 8 })
      Scroll() {
        Column({ space: 0 }) {
          if (this.configTab === 0) {
            // Main
            this.languageRow()
            Row() {
              Text(I18n.t('i0119')).fontSize(12).fontColor(this.nmSub()).width(72)
              Text(this.currentSkyCultureId !== '' ? this.currentSkyCultureId : I18n.t('s0729')).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Row() {
              Text(I18n.t('set_distance_units')).fontSize(12).fontColor(this.nmSub()).width(72)
              Row({ space: 6 }) {
                Text('km')
                  .fontSize(11).fontColor(this.useMetricUnits ? '#5B93BF' : '#99FFFFFF')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(this.useMetricUnits ? '#5B93BF' : 'rgba(255,255,255,0.06)')
                  .borderRadius(8)
                  .onClick(() => {
                    this.useMetricUnits = true
                    this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=true', () => {})
                  })
                Text('mi')
                  .fontSize(11).fontColor(!this.useMetricUnits ? '#5B93BF' : '#99FFFFFF')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(!this.useMetricUnits ? '#5B93BF' : 'rgba(255,255,255,0.06)')
                  .borderRadius(8)
                  .onClick(() => {
                    this.useMetricUnits = false
                    this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=false', () => {})
                  })
              }
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            this.lockRow()
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
          } else if (this.configTab === 4) {
            // Tools
            Row() {
              Text(I18n.t('i0121')).fontSize(12).fontColor(this.nmSub()).width(72)
              Button(I18n.t('i0251')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionSave_Screenshot_Global') })
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            this.infoRow(I18n.t('s0356'), 'PNG')
            this.infoRow(I18n.t('s0357'), I18n.t('s0732'))
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
                  Row() {
                    Text(s).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                  }
                  .height(30).width('100%').padding({ left: 12, right: 12 })
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
            Button(I18n.t('i0244')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadPluginList() })
            Scroll() {
              Column({ space: 2 }) {
                ForEach(this.pluginList, (pl: PluginItem) => {
                  Row() {
                    Text(this.pluginZh(pl.name)).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                    Toggle({ type: ToggleType.Switch, isOn: pl.loaded })
                      .width(40).height(22)
                      .onChange((val: boolean) => {
                        this.togglePlugin(pl.id, !val)
                      })
                  }
                  .height(36).width('100%').padding({ left: 10, right: 10 })
                  .backgroundColor(this.nmBg())
                  .borderRadius(4)
                }, (pl: PluginItem) => pl.id)
              }
            }
            .width('100%').height(260).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'astro') {
      // 天文计算窗口
      Row({ space: 2 }) {
        ForEach([
          { label: I18n.t('a0000'), id: 0 },
          { label: I18n.t('a0001'), id: 1 },
          { label: I18n.t('a0002'), id: 2 },
          { label: I18n.t('a0003'), id: 3 },
          { label: I18n.t('a0004'), id: 4 },
          { label: I18n.t('a0005'), id: 5 },
          { label: I18n.t('a0006'), id: 6 },
          { label: I18n.t('a0007'), id: 7 },
          { label: I18n.t('a0008'), id: 8 },
        ] as TabItem[], (tab: TabItem) => {
          Text(tab.label)
            .fontSize(10)
            .fontColor(this.astroTab === tab.id ? this.nmText() : this.nmSub())
            .padding({ left: 6, right: 6, top: 4, bottom: 4 })
            .backgroundColor(this.astroTab === tab.id ? this.nmAccent() : this.nmBg())
            .borderRadius(6)
            .onClick(() => { this.astroTab = tab.id })
        }, (tab: TabItem, index: number) => tab.id.toString())
      }.width('100%').padding({ left: 2, right: 2 }).margin({ top: 4, bottom: 8 })
      Scroll() {
        Column({ space: 0 }) {
          if (this.astroTab === 0) {
            Text(I18n.t('i0125')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
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
          } else if (this.astroTab === 1) {
            Text(I18n.t('i0126')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text(I18n.t('i0167')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Row({ space: 6 }) {
              Button(I18n.t('i0152')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionPrevious_Rising') })
              Button(I18n.t('i0154')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionPrevious_Transit') })
              Button(I18n.t('i0153')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionPrevious_Setting') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
            Row({ space: 6 }) {
              Button(I18n.t('i0146')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmAccent())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionNext_Rising') })
              Button(I18n.t('i0148')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmAccent())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionNext_Transit') })
              Button(I18n.t('i0147')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmAccent())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionNext_Setting') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 4 })
          } else if (this.astroTab === 2) {
            Text(I18n.t('i0127')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Button(I18n.t('i0239')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadRTS() })
            if (this.rtsData.size > 0) {
              this.infoRow(I18n.t('s0358'), this.rtsData.get('name') ?? 'N/A')
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.nmBorder())
                .margin({ top: 4, bottom: 4 })
              Text(I18n.t('s0370')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow(I18n.t('s0700'), this.jdToDateStr(this.rtsData.get('nextRiseJD') ?? '0'))
              this.infoRow(I18n.t('s0701'), this.jdToDateStr(this.rtsData.get('nextTransitJD') ?? '0'))
              this.infoRow(I18n.t('s0702'), this.jdToDateStr(this.rtsData.get('nextSetJD') ?? '0'))
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.nmBorder())
                .margin({ top: 4, bottom: 4 })
              Text(I18n.t('s0371')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow(I18n.t('s0700'), this.jdToDateStr(this.rtsData.get('prevRiseJD') ?? '0'))
              this.infoRow(I18n.t('s0701'), this.jdToDateStr(this.rtsData.get('prevTransitJD') ?? '0'))
              this.infoRow(I18n.t('s0702'), this.jdToDateStr(this.rtsData.get('prevSetJD') ?? '0'))
            }
            Row({ space: 6 }) {
              Button(I18n.t('i0146')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionNext_Rising') })
              Button(I18n.t('i0148')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionNext_Transit') })
              Button(I18n.t('i0147')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionNext_Setting') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          } else if (this.astroTab === 3) {
            Text(I18n.t('i0128')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text(I18n.t('i0168')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Row({ space: 6 }) {
              Button(I18n.t('i0253')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
              Button(I18n.t('i0254')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
              Button(I18n.t('i0255')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
            Text(I18n.t('s0745')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ top: 6, bottom: 2 })
            Row({ space: 6 }) {
              Button(I18n.t('s0751')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.adjustTime(1) })
              Button(I18n.t('s0752')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.setTimeNow() })
              Button(I18n.t('s0753')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.adjustTime(-1) })
            }.width('100%').padding({ left: 4, right: 4 })
          } else if (this.astroTab === 4) {
            Text(I18n.t('i0129')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text(I18n.t('i0169')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Row({ space: 6 }) {
              Button(I18n.t('i0256')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
              Button(I18n.t('i0257')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          } else if (this.astroTab === 5) {
            Text(I18n.t('i0130')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text(I18n.t('i0170')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Button(I18n.t('i0242')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
          } else if (this.astroTab === 6) {
            Text(I18n.t('i0131')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text(I18n.t('i0171')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Button(I18n.t('i0243')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
          } else if (this.astroTab === 7) {
            Text(I18n.t('i0132')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text(I18n.t('i0172')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Row({ space: 6 }) {
              Button(I18n.t('i0258')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
              Button(I18n.t('i0259')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
              Button(I18n.t('i0260')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          } else {
            Text(I18n.t('i0133')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Button(I18n.t('i0240')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadAlmanac() })
            if (this.almanacData.size > 0) {
              Text(I18n.t('s0372')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow(I18n.t('s0365'), this.jdToDateStr(this.almanacData.get('sunNextRise') ?? '0'))
              this.infoRow(I18n.t('s0366'), this.jdToDateStr(this.almanacData.get('sunNextSet') ?? '0'))
              this.infoRow(I18n.t('s0701'), this.jdToDateStr(this.almanacData.get('sunNextTransit') ?? '0'))
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.nmBorder())
                .margin({ top: 4, bottom: 4 })
              Text(I18n.t('s0373')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow(I18n.t('s0367'), this.jdToDateStr(this.almanacData.get('moonNextRise') ?? '0'))
              this.infoRow(I18n.t('s0368'), this.jdToDateStr(this.almanacData.get('moonNextSet') ?? '0'))
              this.infoRow(I18n.t('s0701'), this.jdToDateStr(this.almanacData.get('moonNextTransit') ?? '0'))
              this.infoRow(I18n.t('s0369'), (parseFloat(this.almanacData.get('moonPhase') ?? '0') * 100).toFixed(1) + '%')
            }
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
            Button('暂停').fontSize(11).fontColor('#FFFFFF').backgroundColor('#E67E22')
              .borderRadius(8).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.pauseScript() })
            Button('继续').fontSize(11).fontColor('#FFFFFF').backgroundColor('#2E7D32')
              .borderRadius(8).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.resumeScript() })
          }.width('100%').padding({ left: 6, right: 6 })
          if (this.scriptList.length === 0) {
            Text('没有可用脚本').fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 6 })
          }
          Scroll() {
            Column({ space: 2 }) {
              ForEach(this.scriptList, (s: string) => {
                Row() {
                  Text(s).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
                }
                .height(30).width('100%').padding({ left: 12, right: 12 })
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
            Button(this.recording ? '停止录制' : '开始录制')
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
              .onClick(() => {
                this.triggerAction('actionSave_Screenshot_Global')
                this.flashHint(I18n.t('screenshot_saved'))
              })
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
        }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else {
      this.infoRow(I18n.t('i0057'), this.isExpandedLayout ? I18n.t('s0703') : I18n.t('s0704'))
      this.infoRow(I18n.t('i0058'), 'Stellarium Core')
      this.infoRow(I18n.t('i0059'), this.fovText)
      this.infoRow(I18n.t('i0060'), this.gyroscopeStatus)
      this.infoRow(I18n.t('i0061'), this.sensZh(this.gyroscopeSensitivityText))
      this.gyroscopeRow()
      this.lx200Panel()
      this.languageRow()
      Row() {
        Text(I18n.t('set_distance_units'))
          .fontSize(14)
          .fontColor('#E5FFFFFF')
          .width(72)
        Row({ space: 6 }) {
          Text('km')
            .fontSize(12)
            .fontColor(this.useMetricUnits ? '#5B93BF' : '#99FFFFFF')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.useMetricUnits ? '#5B93BF' : 'rgba(255,255,255,0.06)')
            .borderRadius(8)
            .onClick(() => {
              this.useMetricUnits = true
              this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=true', () => {})
            })
          Text('mi')
            .fontSize(12)
            .fontColor(!this.useMetricUnits ? '#5B93BF' : '#99FFFFFF')
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
      this.lockRow()
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
      // 截图+夜间模式
      Row() {
        Button(I18n.t('i0048'))
          .fontSize(13).fontColor('#E5FFFFFF').backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(12).height(36).layoutWeight(1)
          .onClick(() => {
            this.callInteractive('saveScreenShot', '', () => { this.flashHint(I18n.t('i0083')) })
          })
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
              .fontSize(11).fontColor(this.selectedLanguage === lang ? "#FFFFFFFF" : "#99FFFFFF")
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor(this.selectedLanguage === lang ? "rgba(107,163,214,0.35)" : "rgba(255,255,255,0.05)")
              .borderRadius(8)
              .onClick(() => this.setLanguage(lang))
          }, (lang: string) => lang)
        }.padding({ left: 4, right: 4 })
      }.width("100%").height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 8 })
      // 星图文化选择
      if (this.skyCultures.length > 0) {
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
            .objectFit(ImageFit.Fill)
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
          .width('100%')
          .height(this.locationMapHeight())
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
              .fontColor(this.selectedLanguage === lang.code ? '#5B93BF' : '#99FFFFFF')
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
    Row() {
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
          .margin({ right: 8 })
          .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.18)', offsetX: 0, offsetY: 5 })
          .animation({ duration: 160, curve: Curve.EaseOut })
          .onClick(() => {
            this.handleChip(item.id)
          })
      }, (item: ChipItem) => item.id)
    }
      .width('100%')
      .margin({ top: 12 })
  }


  @Builder
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
  private handleChip(id: string): void {
    if (id === 'refresh') {
      this.refreshSelectedObject()
      this.refreshState()
    } else if (id === 'center' || id === 'track') {
      this.moveToSelectedObject()
    } else if (id === 'untrack') {
      this.callInteractive('setTracking', '0', () => { this.refreshState() })
    } else if (id === 'now') {
      this.triggerAction('actionReturn_To_Current_Time')
      this.setTimeRate(0.000011574074074073)
    } else if (id === 'back') {
      this.triggerAction('actionDecrease_Time_Speed')
    } else if (id === 'pause') {
      this.setTimeRate(0)
    } else if (id === 'forward') {
      this.triggerAction('actionIncrease_Time_Speed')
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
      const preset: ESObject | null = this.getCityPreset(cityId) ?? null
      if (preset !== null) {
        this.setLocation(cityId, preset['lat'] as number, preset['lon'] as number, preset['alt'] as number)
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

  // View 面板标签页选择器
  @Builder viewTabs() {
    Row({ space: 2 }) {
      ForEach([
        { label: I18n.t('v0000'), id: 0 },
        { label: I18n.t('v0001'), id: 1 },
        { label: I18n.t('v0002'), id: 2 },
        { label: I18n.t('v0003'), id: 3 },
        { label: I18n.t('v0004'), id: 4 },
        { label: I18n.t('v0005'), id: 5 },
        { label: I18n.t('v0006'), id: 6 },
      ] as TabItem[], (tab: TabItem) => {
        Text(tab.label)
          .fontSize(10)
          .fontColor(this.viewTab === tab.id ? this.nmText() : this.nmSub())
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.viewTab === tab.id ? this.nmAccent() : this.nmBg())
          .borderRadius(6)
          .onClick(() => { this.viewTab = tab.id })
      }, (tab: TabItem, index: number) => tab.id.toString())
    }
    .width('100%')
    .padding({ left: 2, right: 2 })
    .margin({ top: 4, bottom: 8 })
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
        min: 1.0,
        max: 12.0,
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
          this.starMagLimit = value
          this.callInteractive('setConfigString', 'astro/StarMagLimit=' + value.toFixed(1), () => {})
          this.callInteractive('setConfigString', 'astro/flag_star_mag_limit=true', () => {})
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
          .onClick(() => { if (this.milkyWayBright > 0) this.milkyWayBright-- })
        Text(this.milkyWayBright.toString()).fontSize(14).fontColor(this.nmText()).width(24).textAlign(TextAlign.Center)
        Button('+').fontSize(12).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(8).width(36).height(28)
          .onClick(() => { if (this.milkyWayBright < 6) this.milkyWayBright++ })
      }
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    // 光污染
    Row() {
      Text(I18n.t('i0280')).fontSize(12).fontColor(this.nmSub()).width(72)
      Button(I18n.t('i0278')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(26).padding({ left: 8, right: 8 })
        .onClick(() => { this.triggerAction('actionShow_LightPollutionReduce') })
      Button(I18n.t('i0279')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(26).padding({ left: 8, right: 8 })
        .onClick(() => { this.triggerAction('actionShow_LightPollutionIncrease') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    this.switchRow(I18n.t('s0300'), this.nightMode, 'actionShow_Night_Mode')
    this.switchRow(I18n.t('s0309'), this.flipHoriz, 'actionHorizontal_Flip')
    this.switchRow(I18n.t('s0310'), this.flipVert, 'actionVertical_Flip')
  }

  // View 面板 SSO 标签页内容
  @Builder viewSSOTab() {
    this.switchRow(I18n.t('s0311'), this.planets, 'actionShow_Planets')
    this.switchRow(I18n.t('s0312'), this.planetOrbits, 'actionShow_Planets_Orbits')
    this.switchRow(I18n.t('s0313'), this.planetTrails, 'actionShow_Planets_Trails')
    this.switchRow(I18n.t('s0314'), this.planetHints, 'actionShow_Planets_Hints')
    this.switchRow(I18n.t('s0315'), this.enlargeMoon, 'actionShow_Planets_EnlargeMoon')
    this.switchRow(I18n.t('s0316'), this.enlargePlanets, 'actionShow_Planets_EnlargePlanets')
    this.switchRow(I18n.t('s0317'), this.enlargeSun, 'actionShow_Planets_EnlargeSun')
    this.switchRow(I18n.t('s0318'), this.minorBodyMarkers, 'actionShow_Planets_ShowMinorBodyMarkers')
    this.switchRow(I18n.t('s0319'), this.planetNomenclature, 'actionShow_Planets_Nomenclature')
    Row() {
      Text(I18n.t('i0281')).fontSize(12).fontColor(this.nmSub()).width(72)
      Button(I18n.t('i0282')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.triggerAction('actionShow_Planets_Trails_Reset') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
  }

  // View 面板 DSO 标签页内容
  @Builder viewDSOTab() {
    this.switchRow(I18n.t('s0320'), this.nebulae, 'actionShow_Nebulas')
    this.switchRow(I18n.t('s0321'), this.dsoLabels, 'setDsoLabels', 'setDsoLabels')
    this.switchRow(I18n.t('s0322'), this.dsoTextures, 'actionShow_DSO_Textures')
    Row() {
      Text(I18n.t('i0220')).fontSize(12).fontColor(this.nmSub()).width(72)
      Button(I18n.t('i0283')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.triggerAction('actionShow_DSO_Textures_Reload') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    Row()
      .width('100%').height(0.5)
      .backgroundColor(this.nmBorder())
      .margin({ top: 6, bottom: 4 })
    Row() {
            Text(I18n.t('i0214')).fontSize(10).fontColor('#CC8FB6FF').width('100%').padding({ left: 2 })
    }
    .height(18).width('100%')
    Row({ space: 12 }) {
      Text('Total: ' + this.dsoTotalCount).fontSize(10).fontColor(this.nmSub())
      Text('G: ' + this.dsoGalaxies).fontSize(10).fontColor(this.nmSub())
      Text('C: ' + this.dsoClusters).fontSize(10).fontColor(this.nmSub())
      Text('N: ' + this.dsoNebulae).fontSize(10).fontColor(this.nmSub())
    }.height(22).width('100%').padding({ left: 10, right: 10 }).margin({ top: 4 })
    Button(I18n.t('s0746')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
      .borderRadius(8).height(26).padding({ left: 10, right: 10 })
      .onClick(() => { this.loadDSOCounts() })
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
        .width('40%')
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
        .width('40%')
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
