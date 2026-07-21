import { command } from 'libentry.so'
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { geoLocationManager } from '@kit.LocationKit'
import { sensor } from '@kit.SensorServiceKit'
import hilog from '@ohos.hilog'
import { LOCATION_HIERARCHY } from './location_hierarchy'

interface LangOption { code: string; name: string }

interface HierCity {
  n: string
  la: number
  lo: number
  al: number
  p: number
}

interface CatOption {
  code: string
  label: ResourceStr
}

interface NameItem {
  name: string
  zh?: string
}

// 天体中文别名表：用于把 Stellarium 核心返回的拉丁/英文名（Jupiter、M31、Orion…）
// 映射成中文显示，并支撑中文/拼音模糊搜索。py 为拼音（无声调），用于「muxing」「jup」这类输入命中。
interface AliasEntry {
  zh: string
  py: string
  en: string
  type: string
}

// 搜索建议项：zh 用于显示，en 用于真正发给核心检索（核心只认英文/标准标识）。
interface SearchSug {
  zh: string
  en: string
}

interface AliasHit {
  zh: string
  en: string
  score: number
}

interface WindowNativeNodeCreateInfo {
  xComponentId: string
  onAppear: () => void
  onAttach: () => void
  onDisAppear: () => void
}

interface TabItem {
  label: string
  id: number
}

interface ShellAction {
  label: ResourceStr
  icon: string
  panel: string
}

// 常用天体中文别名表（行星/太阳/月亮 + 亮星 + 著名深空 + 常见星座）。
// 核心默认返回拉丁/英文名，这里把它们翻成中文显示；同时用 en/py 做模糊匹配。
const ALIAS_LIST: AliasEntry[] = [
  // 行星 / 太阳 / 月亮
  { zh: '水星', py: 'shuixing', en: 'Mercury', type: 'planet' },
  { zh: '金星', py: 'jinxing', en: 'Venus', type: 'planet' },
  { zh: '地球', py: 'diqiu', en: 'Earth', type: 'planet' },
  { zh: '火星', py: 'huoxing', en: 'Mars', type: 'planet' },
  { zh: '木星', py: 'muxing', en: 'Jupiter', type: 'planet' },
  { zh: '土星', py: 'tuxing', en: 'Saturn', type: 'planet' },
  { zh: '天王星', py: 'tianwangxing', en: 'Uranus', type: 'planet' },
  { zh: '海王星', py: 'haiwangxing', en: 'Neptune', type: 'planet' },
  { zh: '冥王星', py: 'mingwangxing', en: 'Pluto', type: 'planet' },
  { zh: '太阳', py: 'taiyang', en: 'Sun', type: 'star' },
  { zh: '月球', py: 'yueqiu', en: 'Moon', type: 'moon' },
  // 亮星
  { zh: '天狼星', py: 'tianlangxing', en: 'Sirius', type: 'star' },
  { zh: '老人星', py: 'laorenxing', en: 'Canopus', type: 'star' },
  { zh: '大角星', py: 'dajiaoxing', en: 'Arcturus', type: 'star' },
  { zh: '织女星', py: 'zhinvxing', en: 'Vega', type: 'star' },
  { zh: '五车二', py: 'wucheer', en: 'Capella', type: 'star' },
  { zh: '参宿七', py: 'shenxiuqi', en: 'Rigel', type: 'star' },
  { zh: '南河三', py: 'nanhesan', en: 'Procyon', type: 'star' },
  { zh: '水委一', py: 'shuiweiyi', en: 'Achernar', type: 'star' },
  { zh: '参宿四', py: 'shenxiusi', en: 'Betelgeuse', type: 'star' },
  { zh: '马腹一', py: 'mafuyi', en: 'Hadar', type: 'star' },
  { zh: '牛郎星', py: 'niulangxing', en: 'Altair', type: 'star' },
  { zh: '十字架二', py: 'shizijiaer', en: 'Acrux', type: 'star' },
  { zh: '毕宿五', py: 'bixuwu', en: 'Aldebaran', type: 'star' },
  { zh: '心宿二', py: 'xinxuer', en: 'Antares', type: 'star' },
  { zh: '角宿一', py: 'jiaoxuyi', en: 'Spica', type: 'star' },
  { zh: '北河三', py: 'beihesan', en: 'Pollux', type: 'star' },
  { zh: '北落师门', py: 'beiluoshimen', en: 'Fomalhaut', type: 'star' },
  { zh: '天津四', py: 'tianjinsi', en: 'Deneb', type: 'star' },
  { zh: '轩辕十四', py: 'xuanyuanshisi', en: 'Regulus', type: 'star' },
  { zh: '北河二', py: 'beiheer', en: 'Castor', type: 'star' },
  { zh: '参宿五', py: 'shenxiuwu', en: 'Bellatrix', type: 'star' },
  { zh: '十字架三', py: 'shizijiasan', en: 'Mimosa', type: 'star' },
  { zh: '参宿一', py: 'shenxiuyi', en: 'Alnilam', type: 'star' },
  { zh: '参宿三', py: 'shenxiusan', en: 'Alnitak', type: 'star' },
  { zh: '天枢', py: 'tianshu', en: 'Dubhe', type: 'star' },
  { zh: '天璇', py: 'tianxuan', en: 'Merak', type: 'star' },
  { zh: '天玑', py: 'tianji', en: 'Phecda', type: 'star' },
  { zh: '天权', py: 'tianquan', en: 'Megrez', type: 'star' },
  { zh: '玉衡', py: 'yuheng', en: 'Alioth', type: 'star' },
  { zh: '开阳', py: 'kaiyang', en: 'Mizar', type: 'star' },
  { zh: '摇光', py: 'yaoguang', en: 'Alkaid', type: 'star' },
  { zh: '北极星', py: 'beijixing', en: 'Polaris', type: 'star' },
  { zh: '娄宿三', py: 'louxisan', en: 'Hamal', type: 'star' },
  { zh: '大陵五', py: 'dalingwu', en: 'Algol', type: 'star' },
  { zh: '五车三', py: 'wuchesan', en: 'Menkalinan', type: 'star' },
  { zh: '壁宿一', py: 'bixuyi', en: 'Algenib', type: 'star' },
  { zh: '奎宿九', py: 'kuixiujiu', en: 'Mirach', type: 'star' },
  { zh: '天船三', py: 'tianchuansan', en: 'Mirfak', type: 'star' },
  { zh: '北极二', py: 'beijier', en: 'Kochab', type: 'star' },
  // 著名深空
  { zh: '仙女座星系', py: 'xianvzuoyinxing', en: 'M31', type: 'galaxy' },
  { zh: 'M32', py: '', en: 'M32', type: 'galaxy' },
  { zh: 'M110', py: '', en: 'M110', type: 'galaxy' },
  { zh: '三角座星系', py: 'sanjiiaozuoyinxing', en: 'M33', type: 'galaxy' },
  { zh: '猎户座大星云', py: 'liehuzuodaxingyun', en: 'M42', type: 'nebula' },
  { zh: 'M43', py: '', en: 'M43', type: 'nebula' },
  { zh: '昴星团', py: 'maoxingtuan', en: 'M45', type: 'cluster' },
  { zh: '蟹状星云', py: 'xiezhuangxingyun', en: 'M1', type: 'nebula' },
  { zh: '礁湖星云', py: 'jiaohuxingyun', en: 'M8', type: 'nebula' },
  { zh: '武仙座球状星团', py: 'wuxianzuoqiuzhuangxingtuan', en: 'M13', type: 'cluster' },
  { zh: '哑铃星云', py: 'yalingxingyun', en: 'M27', type: 'nebula' },
  { zh: '涡状星系', py: 'wozhuangyinxing', en: 'M51', type: 'galaxy' },
  { zh: '指环星云', py: 'zhihuanxingyun', en: 'M57', type: 'nebula' },
  { zh: '波德星系', py: 'bodeyinxing', en: 'M81', type: 'galaxy' },
  { zh: '雪茄星系', py: 'xuejiayinxing', en: 'M82', type: 'galaxy' },
  { zh: '草帽星系', py: 'caomaoyinxing', en: 'M104', type: 'galaxy' },
  { zh: '北美洲星云', py: 'beimeizhouxingyun', en: 'NGC 7000', type: 'nebula' },
  { zh: '玫瑰星云', py: 'meiguixingyun', en: 'NGC 2244', type: 'nebula' },
  { zh: '双星团', py: 'shuangxingtuan', en: 'Double Cluster', type: 'cluster' },
  { zh: '蜂巢星团', py: 'fengchaoxingtuan', en: 'M44', type: 'cluster' },
  { zh: '野鸭星团', py: 'yeyaxingtuan', en: 'M11', type: 'cluster' },
  { zh: '马头星云', py: 'matouxingyun', en: 'IC 434', type: 'nebula' },
  { zh: '加州星云', py: 'jiazhouxingyun', en: 'NGC 1499', type: 'nebula' },
  // 常见星座
  { zh: '仙女座', py: '', en: 'Andromeda', type: 'constellation' },
  { zh: '宝瓶座', py: '', en: 'Aquarius', type: 'constellation' },
  { zh: '天鹰座', py: '', en: 'Aquila', type: 'constellation' },
  { zh: '白羊座', py: '', en: 'Aries', type: 'constellation' },
  { zh: '御夫座', py: '', en: 'Auriga', type: 'constellation' },
  { zh: '牧夫座', py: '', en: 'Boötes', type: 'constellation' },
  { zh: '巨蟹座', py: '', en: 'Cancer', type: 'constellation' },
  { zh: '猎犬座', py: '', en: 'Canes Venatici', type: 'constellation' },
  { zh: '大犬座', py: '', en: 'Canis Major', type: 'constellation' },
  { zh: '小犬座', py: '', en: 'Canis Minor', type: 'constellation' },
  { zh: '摩羯座', py: '', en: 'Capricornus', type: 'constellation' },
  { zh: '船底座', py: '', en: 'Carina', type: 'constellation' },
  { zh: '仙后座', py: '', en: 'Cassiopeia', type: 'constellation' },
  { zh: '半人马座', py: '', en: 'Centaurus', type: 'constellation' },
  { zh: '仙王座', py: '', en: 'Cepheus', type: 'constellation' },
  { zh: '鲸鱼座', py: '', en: 'Cetus', type: 'constellation' },
  { zh: '后发座', py: '', en: 'Coma Berenices', type: 'constellation' },
  { zh: '北冕座', py: '', en: 'Corona Borealis', type: 'constellation' },
  { zh: '乌鸦座', py: '', en: 'Corvus', type: 'constellation' },
  { zh: '巨爵座', py: '', en: 'Crater', type: 'constellation' },
  { zh: '天鹅座', py: '', en: 'Cygnus', type: 'constellation' },
  { zh: '海豚座', py: '', en: 'Delphinus', type: 'constellation' },
  { zh: '天龙座', py: '', en: 'Draco', type: 'constellation' },
  { zh: '波江座', py: '', en: 'Eridanus', type: 'constellation' },
  { zh: '双子座', py: '', en: 'Gemini', type: 'constellation' },
  { zh: '天鹤座', py: '', en: 'Grus', type: 'constellation' },
  { zh: '武仙座', py: '', en: 'Hercules', type: 'constellation' },
  { zh: '长蛇座', py: '', en: 'Hydra', type: 'constellation' },
  { zh: '狮子座', py: '', en: 'Leo', type: 'constellation' },
  { zh: '小狮座', py: '', en: 'Leo Minor', type: 'constellation' },
  { zh: '天兔座', py: '', en: 'Lepus', type: 'constellation' },
  { zh: '天秤座', py: '', en: 'Libra', type: 'constellation' },
  { zh: '天琴座', py: '', en: 'Lyra', type: 'constellation' },
  { zh: '麒麟座', py: '', en: 'Monoceros', type: 'constellation' },
  { zh: '蛇夫座', py: '', en: 'Ophiuchus', type: 'constellation' },
  { zh: '猎户座', py: '', en: 'Orion', type: 'constellation' },
  { zh: '飞马座', py: '', en: 'Pegasus', type: 'constellation' },
  { zh: '英仙座', py: '', en: 'Perseus', type: 'constellation' },
  { zh: '凤凰座', py: '', en: 'Phoenix', type: 'constellation' },
  { zh: '双鱼座', py: '', en: 'Pisces', type: 'constellation' },
  { zh: '南鱼座', py: '', en: 'Piscis Austrinus', type: 'constellation' },
  { zh: '人马座', py: '', en: 'Sagittarius', type: 'constellation' },
  { zh: '天蝎座', py: '', en: 'Scorpius', type: 'constellation' },
  { zh: '巨蛇座', py: '', en: 'Serpens', type: 'constellation' },
  { zh: '金牛座', py: '', en: 'Taurus', type: 'constellation' },
  { zh: '三角座', py: '', en: 'Triangulum', type: 'constellation' },
  { zh: '大熊座', py: '', en: 'Ursa Major', type: 'constellation' },
  { zh: '小熊座', py: '', en: 'Ursa Minor', type: 'constellation' },
  { zh: '室女座', py: '', en: 'Virgo', type: 'constellation' },
  { zh: '狐狸座', py: '', en: 'Vulpecula', type: 'constellation' },
]

interface StellariumBridgeResponse {
  ok?: boolean
  pending?: boolean
  found?: boolean
  error?: string
  name?: string
  englishName?: string
  type?: string
  info?: string
  query?: string
  timeRate?: number
  jd?: number
  timeText?: string
  fov?: number
  tracking?: boolean
  locationName?: string
  locationRegion?: string
  planetName?: string
  latitude?: number
  longitude?: number
  altitude?: number
  target?: string
  ra?: string
  dec?: string
  magnitude?: number
  azimuth?: number
  constellation?: string
  distance?: string
  replies?: string
  sent?: string
  mode?: string
  actionShow_Stars?: boolean
  actionShow_Planets?: boolean
  actionShow_Planets_Orbits?: boolean
  actionShow_Planets_Hints?: boolean
  actionShow_Nebulas?: boolean
  actionShow_MilkyWay?: boolean
  actionShow_Ground?: boolean
  actionShow_Constellation_Lines?: boolean
  actionShow_Constellation_Labels?: boolean
  actionShow_Constellation_Boundaries?: boolean
  actionShow_Constellation_Art?: boolean
  actionShow_Atmosphere?: boolean
  actionShow_Cardinal_Points?: boolean
  actionShow_Azimuthal_Grid?: boolean
  actionShow_Equatorial_Grid?: boolean
  actionShow_Equatorial_J2000_Grid?: boolean
  actionShow_Ecliptic_Grid?: boolean
  actionShow_Meridian_Line?: boolean
  actionShow_Horizon_Line?: boolean
  actionShow_Planets_Labels?: boolean
  actionShow_Stars_Labels?: boolean
  items?: string[] | Object[]
  count?: number
  prefix?: string
  moduleId?: string
  current?: string
}

@Entry
@Component
struct WindowNativeNode {
  @State private createInfo: WindowNativeNodeCreateInfo | undefined = undefined
  @State private isExpandedLayout: boolean = true
  @State private activePanel: string = 'object'
  @State private panelVisible: boolean = true
  @State private searchText: string = ''
  @State private selectedName: string = '未选择'
  @State private searchSuggestions: SearchSug[] = []
  @State private searchHistory: string[] = []
  @State private searchCategory: string = 'planet'
  @State private categoryObjects: NameItem[] = []
  @State private selectedType: string = '轻点天体或搜索'
  @State private selectedStatus: string = '等待选择'
  @State private selectedInfo: string = '轻点星图中的天体，或在搜索里输入名称。'
  @State private selectedMagnitude: string = ''
  @State private selectedCoordEq: string = ''
  @State private selectedCoordAlt: string = ''
  @State private selectedConstellation: string = ''
  @State private selectedDistance: string = ''
  @State private timeRateText: string = '1x'
  @State private manualYear: number = 2026
  @State private manualMonth: number = 7
  @State private manualDay: number = 20
  @State private manualHour: number = 23
  @State private manualMinute: number = 0
  @State private selectedLanguage: string = 'zh_CN'
  @State private bridgeSyncStarted: boolean = false
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
  @State private locationPickerName: string = '自定义位置'
  @State private locationPickerLatitude: number = 39.9042
  @State private locationPickerLongitude: number = 116.4074
  @State private locationPickerAltitude: number = 44
  @State private locationPickerStatus: string = '拖动地图或使用自动定位'
  @State private locationPickMode: string = 'map'
  @State private hierContinent: string = ''
  @State private hierRegion: string = ''
  @State private hierCity: string = ''
  @State private mapRenderWidth: number = 280
  @State private mapRenderHeight: number = 150
  @State private fovText: string = '--'
  @State private trackingText: string = '关闭'
  @State private skyWidth: number = 1
  @State private skyHeight: number = 1
  @State private panelWidth: number = 336
  @State private panelMaxHeight: number = 660
  @State private observingList: string[] = []
  @State private stars: boolean = true
  @State private skyCultures: string[] = []
  @State private isLoading: boolean = true
  @State private currentSkyCulture: string = ""
  @State private planets: boolean = true
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
  @State private landscapeTransp: number = 0
  @State private milkyWayBright: number = 3
  @State private infoLevel: number = 1
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
  @State private equatorialJ2000Grid: boolean = false
  @State private eclipticGrid: boolean = false
  @State private meridianLine: boolean = false
  @State private horizonLine: boolean = false
  @State private planetLabels: boolean = false
  @State private starLabels: boolean = false
  @State private gyroscopeEnabled: boolean = false
  @State private gyroscopeStatus: string = '关闭'
  @State private gyroscopeSensitivityText: string = '标准'
  @State private uiLocked: boolean = true
  @State private panelOffsetX: number = 0
  @State private panelOffsetY: number = 0
  @State private skyTouchFeedback: boolean = false
  @State private lx200Host: string = '127.0.0.1'
  @State private lx200Port: string = '4030'
  @State private lx200Status: string = '未连接'
  @State private actionHint: ResourceStr = ''

  private hintTimer: number = 0
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
  private touchStartedOnUi: boolean = false
  private gyroLastTimeMs: number = 0
  private gyroEventCount: number = 0
  private readonly gyroSensitivity: number = 180
  private gyroCallback: ((data: sensor.GyroscopeResponse) => void) | undefined = undefined
  private dragLogCount: number = 0
  private panelDragging: boolean = false
  private panelDragStartX: number = 0
  private panelDragStartY: number = 0
  private panelDragStartOffsetX: number = 0
  private panelDragStartOffsetY: number = 0

  private readonly actions: ShellAction[] = [
    { label: $r('app.string.i0099'), icon: 'search', panel: 'search' },
    { label: $r('app.string.i0054'), icon: 'clock', panel: 'time' },
    { label: $r('app.string.i0014'), icon: 'location', panel: 'place' },
    { label: $r('app.string.i0100'), icon: 'layers', panel: 'layers' },
    { label: $r('app.string.i0101'), icon: 'info', panel: 'object' },
    { label: $r('app.string.i0102'), icon: 'settings', panel: 'settings' },
      { icon: 'settings', label: '配置', panel: 'config' },
      { icon: 'search', label: '计算', panel: 'astro' },
      { icon: 'info', label: '帮助', panel: 'help' }
  ]

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
    const storedHistory = AppStorage.get<string>("searchHistory")
    if (storedHistory) {
      try {
        this.searchHistory = JSON.parse(storedHistory) as string[]
      } catch (e) {
        this.searchHistory = []
      }
    }
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
        // Qt 初始化成功，自动关闭启动画面
        if (this.isLoading) { this.isLoading = false }
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
          if (lang !== this.selectedLanguage) { this.setLanguage(lang) }
        }
      } catch (e) { }
    }
    // 默认语言设置为中文
    this.setLanguage('zh_CN')
  }

  aboutToDisappear(): void {
    // 保存设置
    AppStorage.setOrCreate("stellariumSettings", JSON.stringify({
      nightMode: this.nightMode,
      equatorialMount: this.equatorialMount,
      gyroscopeEnabled: this.gyroscopeEnabled,
      gyroscopeSensitivityText: this.gyroscopeSensitivityText,
      selectedLanguage: this.selectedLanguage
    }))
    this.stopGyroscope(false)
    this.stopDetailAutoRefresh()
  }

  private setPanel(panel: string): void {
    hilog.info(0x0000, 'StellariumArkUI', 'setPanel ' + panel)
    const nextVisible = this.activePanel === panel ? !this.panelVisible : true
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.activePanel = panel
      this.panelVisible = nextVisible
    })
    if (panel === 'object') {
      this.refreshSelectedObject()
    } else if (panel === 'layers' || panel === 'time' || panel === 'place' || panel === 'settings') {
      this.refreshState()
    }
  }

  private closePanel(): void {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
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
      return JSON.parse(command(name, payload)) as StellariumBridgeResponse
    } catch (err) {
      return { ok: false, error: 'bridge parse failed' }
    }
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
    this.callNativeWhenReady(name, payload, onOk, 0, 50, 40)
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
    }
    if (result.fov !== undefined) {
      this.fovText = result.fov.toFixed(1) + '°'
    }
    if (result.tracking !== undefined) {
      this.trackingText = result.tracking ? '开启' : '关闭'
    }
    })
  }

  private setLayer(actionId: string, enabled: boolean): void {
    this.callInteractive('setActionChecked', actionId + '|' + (enabled ? '1' : '0'), () => {
      this.refreshState()
    })
  }

  private triggerAction(actionId: string): void {
    this.callInteractive('triggerAction', actionId, () => {
      this.refreshState()
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
    this.callInteractive('setTracking', '0', () => { this.trackingText = '关闭' })
  }

  private setSkyCulture(name: string): void {
    this.callInteractive('setSkyCulture', name, () => {
      this.currentSkyCulture = name
      this.flashHint($r('app.string.i0068', name))
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
    this.flashHint((hours > 0 ? $r('app.string.i0044') : '') + hours.toString() + ' 小时')
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
    this.callInteractive('setJD', jd.toFixed(6), () => {
      this.refreshState()
      this.flashHint($r('app.string.i0069', this.manualYear + '-' + String(this.manualMonth).padStart(2, '0') + '-' + String(this.manualDay).padStart(2, '0') + ' ' + String(this.manualHour).padStart(2, '0') + ':' + String(this.manualMinute).padStart(2, '0')))
    })
  }

  private setLanguage(lang: string): void {
    const attemptSet = (attempt: number): void => {
      const result = this.callNative('setLanguage', lang)
      if (result.ok === true) {
        this.selectedLanguage = lang
        this.flashHint(lang === 'zh_CN' ? '已切换为中文' : 'Switched to English')
        this.refreshState()
      } else if (attempt < 60) {
        setTimeout(() => attemptSet(attempt + 1), 200)
      }
    }
    attemptSet(0)
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
      const target = result.target && result.target.length > 0 ? result.target : '选中目标'
      const mode = result.mode === 'sync' ? '同步' : $r('app.string.i0049')
      const coord = result.ra && result.dec ? ' · ' + result.ra + ' / ' + result.dec : ''
      this.lx200Status = mode + ' 已发送：' + target + coord
    } else {
      const message = result.error === 'no selected object' ? '请先点选或搜索一个目标' : result.error
      this.lx200Status = message ? message : 'LX200 命令失败'
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
      this.lx200Status = result.ok === true ? '已发送停止指令' : (result.error ? result.error : '停止失败')
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
      this.gyroCallback = (data: sensor.GyroscopeResponse) => {
        this.onGyroscopeData(data)
      }
    }
    try {
      sensor.on(sensor.SensorId.GYROSCOPE, this.gyroCallback, { interval: 60000000 })
      this.gyroLastTimeMs = 0
      this.gyroEventCount = 0
      this.gyroscopeEnabled = true
      this.gyroscopeStatus = '监听中'
    } catch (error) {
      this.gyroscopeEnabled = false
      this.gyroscopeStatus = '不可用'
    }
  }

  private stopGyroscope(updateStatus: boolean): void {
    if (this.gyroCallback !== undefined) {
      try {
        sensor.off(sensor.SensorId.GYROSCOPE, this.gyroCallback)
      } catch (error) {
      }
    }
    this.gyroLastTimeMs = 0
    this.gyroscopeEnabled = false
    if (updateStatus) {
      this.gyroscopeStatus = '关闭'
    }
  }

  private onGyroscopeData(data: sensor.GyroscopeResponse): void {
    const now = Date.now()
    if (this.gyroLastTimeMs === 0) {
      this.gyroLastTimeMs = now
      return
    }

    const dt = Math.min(0.08, Math.max(0.0, (now - this.gyroLastTimeMs) / 1000.0))
    this.gyroLastTimeMs = now
    if (dt <= 0.0) {
      return
    }

    const dx = -data.z * dt * this.gyroSensitivity
    const dy = data.x * dt * this.gyroSensitivity
    if (Math.abs(dx) < 0.08 && Math.abs(dy) < 0.08) {
      return
    }

    const clampedDx = Math.max(-18, Math.min(18, dx))
    const clampedDy = Math.max(-18, Math.min(18, dy))
    // panBy is high-frequency & fire-and-forget: it is drained on the next
    // render frame, so DON'T wrap it in a retry loop (would flood). A first
    // call returns {pending} which here simply means "enqueued/working".
    const result = this.callNative('panBy', clampedDx.toString() + '|' + clampedDy.toString() + '|' + this.skyWidth.toString() + '|' + this.skyHeight.toString())
    this.gyroEventCount += 1
    if (this.gyroEventCount % 12 === 0) {
      this.gyroscopeStatus = (result.ok === true || result.pending === true) ? '工作中' : (result.error ? result.error : 'Core 未就绪')
    }
  }

  private searchObject(name: string): void {
    const query = name.trim()
    if (query.length === 0) {
      return
    }
    this.activePanel = 'object'
    this.panelVisible = true
    this.flashHint($r('app.string.i0070', query))
    // 保存搜索历史（去重，最多保留 20 条）
    const hist = this.searchHistory.filter(h => h !== query)
    hist.unshift(query)
    this.searchHistory = hist.slice(0, 20)
    AppStorage.setOrCreate('searchHistory', JSON.stringify(this.searchHistory))
    this.callInteractive('searchObject', query, (result) => {
      this.applySelectedObject(result)
      if (result.found === true) {
        this.flashHint($r('app.string.i0071', query))
      } else {
        this.flashHint($r('app.string.i0072', query))
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
      this.applySelectedObject(r)
    })
  }

  // 启动“详情自动刷新”：仅在【目标详情面板打开 + 有已选中天体】时才拉数据，避免无谓的桥调用。
  private startDetailAutoRefresh(): void {
    if (this.detailTimer !== 0) { return }
    this.detailTimer = setInterval(() => {
      if (this.activePanel === 'object' && this.panelVisible && this.selectedStatus === '已选中') {
        this.refreshSelectedObject()
      }
    }, 1000) as number
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

  // 把核心返回的拉丁/英文名映射成中文显示；已是中文的保持；无别名则原样返回。
  private zhNameOf(raw: string): string {
    if (!raw || raw.length === 0) { return raw }
    if (/[一-鿿]/.test(raw)) { return raw }
    const q = raw.toLowerCase()
    for (let i = 0; i < ALIAS_LIST.length; i++) {
      if (ALIAS_LIST[i].en.toLowerCase() === q) { return ALIAS_LIST[i].zh }
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

  // 天体类型本地化（Planet→行星…）；未知则原样。
  private zhType(type: string): ResourceStr {
    const map: Record<string, ResourceStr> = {
      'Planet': $r('app.string.i0103'), 'Star': $r('app.string.i0104'), 'Nebula': $r('app.string.i0107'), 'Galaxy': $r('app.string.i0105'),
      'Asteroid': '小行星', 'Comet': '彗星', 'Satellite': '卫星', 'Moon': '卫星/月球',
      'Sun': '恒星(太阳)', 'Quasar': '类星体', 'Pulsar': '脉冲星', 'Cluster': $r('app.string.i0106'),
      'Open cluster': '疏散星团', 'Globular cluster': '球状星团', 'Planetary nebula': '行星状星云',
      'Interstellar object': '星际天体', 'Minor planet': '小行星',
    }
    return map[type] ?? type
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

  private applySelectedObject(result: StellariumBridgeResponse): void {
    if (result.ok !== true) {
      this.selectedStatus = result.error ? result.error : 'Core 未就绪'
      return
    }
    if (result.found === true) {
      this.selectedName = result.name && result.name.length > 0 ? result.name : (result.englishName ? result.englishName : '已选择')
      this.selectedType = result.type && result.type.length > 0 ? result.type : '天体'
      this.selectedStatus = '已选中'
      this.selectedMagnitude = (typeof result.magnitude === 'number') ? (result.magnitude as number).toFixed(2) : ''
      const ra: string = result.ra ? result.ra : ''
      const dec: string = result.dec ? result.dec : ''
      this.selectedCoordEq = (ra.length > 0 || dec.length > 0) ? (ra + '  ' + dec).trim() : ''
      const hasAlt: boolean = typeof result.altitude === 'number'
      const hasAz: boolean = typeof result.azimuth === 'number'
      this.selectedCoordAlt = (hasAlt || hasAz)
        ? ('高度 ' + (hasAlt ? this.fmtDegMin(result.altitude as number) : '--') + '   方位 ' + (hasAz ? this.fmtDegMin(result.azimuth as number) : '--'))
        : ''
      this.selectedConstellation = result.constellation && result.constellation.length > 0 ? result.constellation : ''
      this.selectedDistance = result.distance && result.distance.length > 0 ? result.distance : ''
      // 尝试从本地别名表补充中文简介
      const dispName = this.selectedName
      const alias = ALIAS_LIST.find(a => a.en === dispName || a.zh === dispName)
      this.selectedInfo = alias ? alias.zh + ' (' + alias.en + ')' : ''
      this.startDetailAutoRefresh()
    } else {
      this.selectedName = '未找到'
      this.selectedType = result.query && result.query.length > 0 ? result.query : '无选中对象'
      this.selectedStatus = result.query && result.query.length > 0 ? '可尝试英文名' : '未命中'
      this.selectedMagnitude = ''
      this.selectedCoordEq = ''
      this.selectedCoordAlt = ''
      this.selectedConstellation = ''
      this.selectedDistance = ''
      this.selectedInfo = '当前点击位置没有命中可选天体。可以放大后再点，或用搜索选择目标。'
    }
  }

  private formatRate(rate: number): string {
    if (rate === 0) {
      return '暂停'
    }
    if (Math.abs(rate - 0.000011574074074074073) < 0.0000001) {
      return '1x'
    }
    if (rate > 0) {
      return rate.toFixed(6)
    }
    return '反向'
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

  private setPickerLocation(name: string, latitude: number, longitude: number, altitude: number, status: string): void {
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
    this.setPickerLocation('地图选择', latitude, longitude, this.locationPickerAltitude, '已选择地图位置，点应用同步星图')
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

  private async useDeviceLocation(): Promise<void> {
    this.locationPickerStatus = '正在请求定位权限'
    try {
      const context = getContext(this) as common.UIAbilityContext
      const atManager = abilityAccessCtrl.createAtManager()
      const permissions: Array<Permissions> = [
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION'
      ]
      await atManager.requestPermissionsFromUser(context, permissions)
      this.locationPickerStatus = '正在获取当前位置'
      const current = await geoLocationManager.getCurrentLocation({
        priority: geoLocationManager.LocationRequestPriority.ACCURACY,
        scenario: geoLocationManager.LocationRequestScenario.DAILY_LIFE_SERVICE,
        maxAccuracy: 2000,
        timeoutMs: 5000
      })
      const altitude = Number.isFinite(current.altitude) ? current.altitude : 0
      this.setPickerLocation('当前位置', current.latitude, current.longitude, altitude, '已获取设备位置，自动同步到星图')
      this.applyPickerLocation()
      this.locationPickMode = 'map'
      this.hierContinent = ''
      this.hierRegion = ''
      this.hierCity = ''
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', 'device location failed: %{public}s', JSON.stringify(err))
      // 模拟器通常无 GPS，自动回退到上次保存的位置
      if (this.locationPickerLatitude === 0 && this.locationPickerLongitude === 0) {
        this.setPickerLocation('北京', 39.9, 116.4, 43, '模拟器无 GPS，已使用默认位置（北京）')
      } else {
        this.locationPickerStatus = 'GPS 不可用，已保留当前位置'
      }
    }
  }

  private applyPickerLocation(): void {
    this.setLocation(this.locationPickerName, this.locationPickerLatitude, this.locationPickerLongitude, this.locationPickerAltitude)
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
    this.callInteractive('setLocation', name + '|' + latitude.toString() + '|' + longitude.toString() + '|' + altitude.toString(), () => {
      this.setPickerLocation(name, latitude, longitude, altitude, '已同步到星图')
      this.locationText = name + ' · Earth'
      this.coordinateText = this.formatDegrees(latitude, 'N', 'S') + ' / ' + this.formatDegrees(longitude, 'E', 'W')
      this.altitudeText = altitude.toFixed(0) + ' m'
      this.refreshState()
      this.flashHint($r('app.string.i0073', name))
    })
  }

  private hierContinents(): Array<string> {
    return Object.keys(LOCATION_HIERARCHY)
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
      this.setPickerLocation(found.n, found.la, found.lo, found.al,
        '已选择：' + this.hierContinent + ' / ' + this.hierRegion + ' / ' + found.n + '，点应用同步星图')
    }
  }

  @Builder
  locationModeChip(mode: string, label: string) {
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
      Scroll() {
        Column() {
          if (kind === 'continent') {
            ForEach(this.hierContinents(), (item: string) => {
              Button(item, { type: ButtonType.Normal })
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .width('100%')
                .fontSize(12)
                .fontColor(selected === item ? this.nmText() : this.nmSub())
                .backgroundColor(selected === item ? this.nmAccent() : this.nightMode ? 'rgba(100, 30, 15, 0.40)' : '#16223C')
                .borderRadius(8)
                .stateEffect(false)
                .onClick(() => onSelect(item))
            }, (item: string) => item)
          } else if (kind === 'region') {
            ForEach(this.hierRegions(), (item: string) => {
              Button(item, { type: ButtonType.Normal })
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .width('100%')
                .fontSize(12)
                .fontColor(selected === item ? '#FFFFFFFF' : '#99FFFFFF')
                .backgroundColor(selected === item ? '#5B93BF' : '#16223C')
                .borderRadius(8)
                .stateEffect(false)
                .onClick(() => onSelect(item))
            }, (item: string) => item)
          } else {
            ForEach(this.hierCityNames(), (item: string) => {
              Button(item, { type: ButtonType.Normal })
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .width('100%')
                .fontSize(12)
                .fontColor(selected === item ? '#FFFFFFFF' : '#99FFFFFF')
                .backgroundColor(selected === item ? '#5B93BF' : '#16223C')
                .borderRadius(8)
                .stateEffect(false)
                .onClick(() => onSelect(item))
            }, (item: string) => item)
          }
        }
          .width('100%')
      }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
    }
      .width('33%')
      .height('100%')
      .backgroundColor('rgba(255, 255, 255, 0.05)')
      .borderRadius(8)
  }

  private panelLeft(): number {
    // 实测浮层面板左缘(vp)；面板宽 336, 右侧留 24
    return this.skyWidth - 360
  }

  private panelRight(): number {
    return this.skyWidth - 24
  }

  private panelTop(): number {
    // 实测浮层面板顶缘(标题区)约 270vp
    return 28
  }

  private railTop(): number {
    return Math.max(0, this.skyHeight - 724) + 30
  }

  private railHeight(): number {
    return this.actions.length * 104
  }

  private isUiPoint(x: number, y: number): boolean {
    if (this.isExpandedLayout) {
      // 左侧工具栏按钮区域（宽屏布局）
      if (x >= 0 && x <= 50) {
        const buttonTop = Math.max(0, this.skyHeight - 724) + 30
        const step = 104
        for (let i = 0; i < this.actions.length; i++) {
          const bTop = buttonTop + i * step
          if (y >= bTop && y <= bTop + 88) {
            return true
          }
        }
      } else if (x >= 92 && x <= 148 && y >= this.skyHeight - 224 && y <= this.skyHeight - 90) {
        return true
      }
      // 浮动面板区域
      if (this.panelVisible && x >= this.panelLeft() && x <= this.panelRight() && y >= this.panelTop() && y <= this.panelTop() + 900) {
        return true
      }
      return false
    }
    if (this.panelVisible && y >= this.skyHeight - this.panelMaxHeight) {
      return true
    }
    return y >= this.skyHeight - 80
  }

	  private handleUiTap(x: number, y: number): boolean {
	    // zoom +/- buttons (expanded layout, bottom-left)
	    if (this.isExpandedLayout && x >= 92 && x <= 148) {
	      if (y >= this.skyHeight - 224 && y <= this.skyHeight - 160) {
	        this.zoomStep(0.5)
	        return true
	      }
	      if (y >= this.skyHeight - 154 && y <= this.skyHeight - 90) {
	        this.zoomStep(2.0)
	        return true
	      }
	    }
	    if (this.isExpandedLayout && x >= 0 && x <= 50) {
      const buttonTop = Math.max(0, this.skyHeight - 724) + 30
      const step = 104
      const index = Math.floor((y - buttonTop) / step)
      const withinButton = index >= 0 && index < this.actions.length && y >= buttonTop + index * step && y <= buttonTop + index * step + 88
      if (withinButton) {
        this.setPanel(this.actions[index].panel)
        return true
      }
	    }

	    if (!this.isExpandedLayout && y >= this.skyHeight - 128) {
	      const start = this.skyWidth * 0.04
	      const itemWidth = this.skyWidth * 0.92 / (this.actions.length - 1)
	      const index = Math.floor((x - start) / itemWidth)
	      if (index >= 0 && index < this.actions.length) {
	        this.setPanel(this.actions[index].panel)
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
      this.panelVisible = false
      return true
    }

    if (x < left || x > right || y < top || y > top + 900) {
      return false
    }

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
  }

  private handleOverlayTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) {
      return
    }
    const x = this.touchWindowX(points[0])
    const y = this.touchWindowY(points[0])
    if (event.type === TouchType.Down) {
      this.touchStartedOnUi = this.isUiPoint(x, y)
      hilog.info(0x0000, 'StellariumArkUI', 'overlay touch down ' + Math.round(x).toString() + ',' + Math.round(y).toString() + ' ui=' + (this.touchStartedOnUi ? '1' : '0') + ' sky=' + this.skyWidth.toString() + 'x' + this.skyHeight.toString())
    }
    if (this.uiLocked && this.touchStartedOnUi) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.touchStartedOnUi = false
      }
      return
    }
    if (this.touchStartedOnUi) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.handleUiTap(x, y)
        this.touchStartedOnUi = false
      }
      return
    }
    this.handleSkyTouch(event)
  }

  private handleSkyTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) {
      return
    }

    if (event.type === TouchType.Down) {
      const downX = this.touchWindowX(points[0])
      const downY = this.touchWindowY(points[0])
      if (this.isUiPoint(downX, downY)) {
        return
      }
      this.skyTouchActive = true
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
      hilog.info(0x0000, 'StellariumArkUI', 'sky touch down at ' + Math.round(this.touchStartX).toString() + ',' + Math.round(this.touchStartY).toString() + ' sky=' + this.skyWidth.toString() + 'x' + this.skyHeight.toString())
      if (points.length >= 2) {
        this.pinchStartDistance = this.distance(
          this.touchWindowX(points[0]), this.touchWindowY(points[0]),
          this.touchWindowX(points[1]), this.touchWindowY(points[1]))
        this.pinchActive = true
        this.callNative('zoomBy', '1|1')
      }
      return
    }

    if (!this.skyTouchActive) {
      return
    }

    if (event.type === TouchType.Move) {
      const x = this.touchWindowX(points[0])
      const y = this.touchWindowY(points[0])
      if (points.length >= 2) {
        this.nativeDragActive = false
        const currentDistance = this.distance(
          x, y, this.touchWindowX(points[1]), this.touchWindowY(points[1]))
        if (!this.pinchActive || this.pinchStartDistance <= 1) {
          this.pinchStartDistance = currentDistance
          this.pinchActive = true
          this.callNative('zoomBy', '1|1')
        } else {
          const scale = currentDistance / this.pinchStartDistance
          this.callNative('zoomBy', scale.toString() + '|0')
        }
        this.touchMoved = true
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
        if (now - this.lastDragCommandMs >= 24) {
          if (this.dragLogCount < 3) {
            hilog.info(0x0000, 'StellariumArkUI', 'dragView from ArkUI')
            this.dragLogCount += 1
          }
          this.callNative('dragView',
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
        this.callNative('dragView',
          Math.round(this.touchLastX).toString() + '|' +
          Math.round(this.touchLastY).toString() + '|' +
          Math.round(x).toString() + '|' +
          Math.round(y).toString())
      } else if (!this.touchMoved && !this.pinchActive) {
        const payload = Math.round(this.touchStartX).toString() + '|' + Math.round(this.touchStartY).toString() + '|' + Math.round(this.skyWidth).toString() + '|' + Math.round(this.skyHeight).toString()
        hilog.info(0x0000, 'StellariumArkUI', 'selectAt payload: ' + payload)
        this.activePanel = 'object'
        this.panelVisible = true
        this.callInteractive('selectAt', payload, (result) => {
          hilog.info(0x0000, 'StellariumArkUI', 'selectAt result: ' + JSON.stringify(result))
          this.applySelectedObject(result)
          if (result.found === true) {
            this.flashHint($r('app.string.i0074', this.selectedName))
          } else {
            this.flashHint($r('app.string.i0075'))
          }
        })
      }
      this.pinchActive = false
      this.nativeDragActive = false
      this.skyTouchActive = false
      this.skyTouchFeedback = false
    }
  }

  build() {
    Stack() {
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
          .hitTestBehavior(HitTestMode.None)
          .zIndex(4)
          .animation({ duration: 180, curve: Curve.EaseOut })
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
          this.handleSkyTouch(event)
        })

      this.expandedShell()

      // 启动画面
      if (this.isLoading) {
        Column() {
          Text("Stellarium")
            .fontSize(32).fontWeight(FontWeight.Bold).fontColor("#E5FFFFFF")
            .margin({ bottom: 12 })
          Text($r('app.string.i0001'))
            .fontSize(14).fontColor("#99FFFFFF")
            .margin({ bottom: 24 })
          LoadingProgress()
            .width(36).height(36)
            .color("#5B93BF")
        }
        .width("100%").height("100%")
        .backgroundColor("#000000")
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .zIndex(100)
        .onClick(() => { this.isLoading = false })
        .animation({ duration: 400, curve: Curve.EaseOut })
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
        this.isExpandedLayout = this.skyWidth >= 900
        this.panelWidth = Math.min(Math.max(this.skyWidth * 0.28, 280), 400)
        this.panelMaxHeight = Math.min(this.skyHeight * 0.78, 700)
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
            .fontColor('#5B93BF')
        }
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          .backgroundColor('#5B93BF')
          .borderRadius(18)
          .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: 8 })
          .hitTestBehavior(HitTestMode.None)
          .position({ x: 0, y: 16 })
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .zIndex(20)
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
      Stack() { this.observerBadge() }
        .position({ x: 22, y: 28 })
        .hitTestBehavior(HitTestMode.None)
      Stack() { this.verticalRail() }
        .position({ x: 0, y: this.railTop() })
      Stack() { this.zoomButton('zoom_in') }
        .position({ x: 92, y: this.skyHeight - 220 })
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.zoomStep(0.5)
          this.flashHint($r('app.string.i0076'))
        })
      Stack() { this.zoomButton('zoom_out') }
        .position({ x: 92, y: this.skyHeight - 150 })
        .onClick(() => {
          this.zoomStep(2.0)
          this.flashHint($r('app.string.i0077'))
        })
      if (this.panelVisible) {
        Stack() { this.floatingPanel() }
          .position({ x: this.skyWidth - 392 + this.panelOffsetX, y: 28 + this.panelOffsetY })
      }
    }
      .width('100%')
      .height('100%')
      .zIndex(1)
      .hitTestBehavior(HitTestMode.Transparent)
    }

  @Builder
  compactShell() {
    Column() {
      Row() {
        this.observerBadge()
        Blank()
        this.smallRoundButton('×', () => {
          this.closePanel()
        })
      }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 })

      // 缩放按钮（右上角）
      Row() {
        Button('+').fontSize(18).fontColor(this.nmText()).backgroundColor('rgba(25, 26, 28, 0.72)')
          .backdropBlur(26).width(40).height(40).borderRadius(20)
          .border({ width: 0.5, color: 'rgba(255,255,255,0.08)' })
          .shadow({ radius: 16, color: 'rgba(0,0,0,0.30)', offsetY: 4 })
          .onClick(() => { this.triggerAction('actionZoom_In_Auto') })
        Button('-').fontSize(18).fontColor(this.nmText()).backgroundColor('rgba(25, 26, 28, 0.72)')
          .backdropBlur(26).width(40).height(40).borderRadius(20)
          .border({ width: 0.5, color: 'rgba(255,255,255,0.08)' })
          .shadow({ radius: 16, color: 'rgba(0,0,0,0.30)', offsetY: 4 })
          .onClick(() => { this.triggerAction('actionZoom_Out_Auto') })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 16 })
      .margin({ bottom: -20 })
      .zIndex(2)

      Blank()
        .width('100%')
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => {
          this.handleSkyTouch(event)
        })

      if (this.panelVisible) {
        this.compactPanel()
      }

      this.bottomDock()
    }
      .width('100%')
      .height('100%')
      .padding({ bottom: 14 })
      .zIndex(1)
  }

  @Builder
  observerBadge() {
    Row() {
      Text('Stellarium')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E5FFFFFF')
        .maxLines(1)
      Text($r('app.string.i0002'))
        .fontSize(9)
        .fontColor('#5B93BF')
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
      // 手势由外层 Stack.onClick 统一处理
  }

  @Builder
  verticalRail() {
  Stack() {
    ForEach(this.actions, (item: ShellAction, idx: number) => {
        Stack() { this.iconButton(item) }
          .width(44)
          .height(44)
          .position({ x: 7, y: idx * 58 })
          .onClick(() => {
            this.setPanel(item.panel)
            this.flashHint($r('app.string.i0078', item.label + '面板'))
          })
        // 分隔线（最后一个按钮不加）
        if (idx < this.actions.length - 1) {
          Row()
            .width(22)
            .height(0.5)
            .backgroundColor('rgba(255,255,255,0.08)')
            .position({ x: 18, y: idx * 58 + 50 })
            .hitTestBehavior(HitTestMode.None)
        }
    }, (item: ShellAction) => item.panel)
  }
    .width(58)
        .height(this.railHeight())
      .backgroundColor('rgba(25, 26, 28, 0.72)')
      .backdropBlur(26)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(29)
      .shadow({ radius: 28, color: 'rgba(0, 0, 0, 0.32)', offsetX: 0, offsetY: 14 })
  }

  @Builder
  bottomDock() {
    Row() {
      ForEach(this.actions, (item: ShellAction) => {
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
    return this.nightMode ? '#CC5533' : '#66FFFFFF'
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

  private getIcon(icon: string, isActive: boolean): Resource {
    const map: Record<string, Resource> = {
      'search': $r('app.media.ic_search'),
      'clock': $r('app.media.ic_clock'),
      'location': $r('app.media.ic_location'),
      'layers': $r('app.media.ic_layers'),
      'info': $r('app.media.ic_info'),
      'settings': $r('app.media.ic_settings'),
      'zoom_in': $r('app.media.ic_zoom_in'),
      'zoom_out': $r('app.media.ic_zoom_out'),
    }
    return map[icon] || $r('app.media.ic_search')
  }
  @Builder
  iconButton(item: ShellAction) {
    Column() {
      Image(this.getIcon(item.icon, this.activePanel === item.panel && this.panelVisible))
        .width(22).height(22)
        .fillColor(this.activePanel === item.panel && this.panelVisible ? this.nmAccent() : this.nmText())
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
      .animation({ duration: 180, curve: Curve.EaseOut })
      // 手势由外层 Stack.onClick 统一处理
  }

  @Builder
  dockButton(item: ShellAction) {
    Column() {
      Text(item.icon)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.activePanel === item.panel && this.panelVisible ? '#5B93BF' : '#E5FFFFFF')
        .lineHeight(18)
        .textAlign(TextAlign.Center)
        .width('100%')
      Text(item.label)
        .fontSize(10)
        .fontColor(this.activePanel === item.panel && this.panelVisible ? '#5B93BF' : '#99FFFFFF')
        .margin({ top: 2 })
    }
      .width(54)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.activePanel === item.panel && this.panelVisible ? '#5B93BF' : Color.Transparent)
      .borderRadius(26)
      .scale({ x: this.activePanel === item.panel && this.panelVisible ? 1.06 : 1.0, y: this.activePanel === item.panel && this.panelVisible ? 1.06 : 1.0 })
      .animation({ duration: 180, curve: Curve.EaseOut })
      .onClick(() => {
        this.setPanel(item.panel)
        this.flashHint($r('app.string.i0078', item.label + '面板'))
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
      .backgroundColor('rgba(25, 26, 28, 0.78)')
      .backdropBlur(30)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(32)
      .shadow({ radius: 34, color: 'rgba(0, 0, 0, 0.34)', offsetX: 0, offsetY: 18 })
      .margin({ top: 28, bottom: 28 })
      .animation({ duration: 220, curve: Curve.EaseOut })
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
      }
        .width('100%')
        .layoutWeight(1)
    }
      .width('92%')
      .constraintSize({ minHeight: 156, maxHeight: 560 })
      .padding({ top: 10, left: 16, right: 16, bottom: 14 })
      .backgroundColor('rgba(25, 26, 28, 0.78)')
      .backdropBlur(30)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(32)
      .shadow({ radius: 30, color: 'rgba(0, 0, 0, 0.32)', offsetX: 0, offsetY: 14 })
      .margin({ bottom: 10 })
      .alignSelf(ItemAlign.Center)
      .animation({ duration: 220, curve: Curve.EaseOut })
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
        Text(this.panelSubtitle())
          .fontSize(11)
          .fontColor('#66FFFFFF')
          .margin({ top: 3 })
      }
      Blank()
      this.smallRoundButton('×', () => {
        this.closePanel()
      })
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
      .onClick(action)
  }

  @Builder
  panelContent() {
    if (this.activePanel === 'object') {
      if (this.selectedName.length === 0) {
        Column() {
          Text('点击天空中的天体').fontSize(14).fontColor('#66FFFFFF').margin({ top: 20 })
          Text('或使用搜索功能查找').fontSize(12).fontColor('#446688FF').margin({ top: 6 })
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
          .fontSize(11).fontColor('#5B93BF')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor('rgba(91, 147, 191, 0.15)').borderRadius(6)
        Blank()
        Text(this.selectedStatus)
          .fontSize(11).fontColor('#66FFFFFF')
        if (this.trackingText.length > 0) {
          Text(this.trackingText)
            .fontSize(11).fontColor('#66BBFFAA')
        }
      }.width('100%').padding({ left: 4, right: 4 }).height(20).margin({ bottom: 8 })

      // 直接绑定 @State（不要经 infoRow 的 @Builder 参数，参数按值捕获会导致不刷新，详见上方注释）
      if (this.selectedMagnitude.length > 0) {
        Row() {
          Text($r('app.string.i0007')).fontSize(12).fontColor('#66FFFFFF').width(72)
          Text(this.selectedMagnitude).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(28).width('100%').padding({ left: 10, right: 10 })
      }
      if (this.selectedCoordEq.length > 0) {
        Row() {
          Text($r('app.string.i0008')).fontSize(12).fontColor('#66FFFFFF').width(72)
          Text(this.selectedCoordEq).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(28).width('100%').padding({ left: 10, right: 10 })
      }
      if (this.selectedCoordAlt.length > 0) {
        Row() {
          Text($r('app.string.i0009')).fontSize(12).fontColor('#66FFFFFF').width(72)
          Text(this.selectedCoordAlt).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(28).width('100%').padding({ left: 10, right: 10 })
      }
      if (this.selectedConstellation.length > 0) {
        Row() {
          Text($r('app.string.i0010')).fontSize(12).fontColor('#66FFFFFF').width(72)
          Text(this.zhNameOf(this.selectedConstellation)).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.height(28).width('100%').padding({ left: 10, right: 10 })
      }
      if (this.selectedDistance.length > 0) {
        Row() {
          Text($r('app.string.i0011')).fontSize(12).fontColor('#66FFFFFF').width(72)
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
        Button(this.observingList.includes(this.selectedName) ? "已从列表" : "加入观测列表")
          .fontSize(13).fontColor("#E5FFFFFF").backgroundColor("rgba(107,163,214,0.25)")
          .borderRadius(12).height(36).layoutWeight(1)
          .onClick(() => {
            const idx = this.observingList.indexOf(this.selectedName)
            if (idx >= 0) {
              this.observingList.splice(idx, 1)
              this.flashHint($r('app.string.i0079'))
            } else {
              this.observingList.push(this.selectedName)
              this.flashHint($r('app.string.i0080'))
            }
            AppStorage.setOrCreate("observingList", JSON.stringify(this.observingList))
          })
      }
      .width("100%").margin({ top: 4, bottom: 4 })
	      this.quickChips(['刷新', '居中', '取消追踪'])
      Row({ space: 6 }) {
        Button('上一选中').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionGoto_ReSelect_Last_Selected_Object') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 4, bottom: 4 })
	      this.lx200ObjectControls()
      } // end object selectedName else
    } else if (this.activePanel === 'time') {
      this.infoRow($r('app.string.i0054'), this.observationTimeText)
      this.infoRow($r('app.string.i0055'), this.timeRateText)
      this.infoRow($r('app.string.i0056'), this.timeRateText === '暂停' ? '暂停' : '运行')
      this.quickChips(['现在', '后退', '暂停', '前进'])
      this.quickChips(['+12h', '-12h'])
      // 天文事件快捷跳转
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text('天体事件').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row({ space: 6 }) {
        Button('下次升起').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_Rising') })
        Button('下次落下').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_Setting') })
        Button('下次中天').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_Transit') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button('今日升起').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionToday_Rising') })
        Button('今日落下').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionToday_Setting') })
        Button('今日中天').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionToday_Transit') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button('上次升起').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_Rising') })
        Button('上次落下').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_Setting') })
        Button('上次中天').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_Transit') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button('下次晨光').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_MorningTwilight') })
        Button('下次昏影').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_EveningTwilight') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button('上次晨光').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_MorningTwilight') })
        Button('上次昏影').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_EveningTwilight') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 二分二至快捷跳转
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 6, bottom: 4 })
      Row() {
        Text('节气').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row({ space: 6 }) {
        Button('春分').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_March_Equinox') })
        Button('夏至').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_June_Solstice') })
        Button('秋分').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_September_Equinox') })
        Button('冬至').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_December_Solstice') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button('上次春分').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_March_Equinox') })
        Button('上次夏至').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_June_Solstice') })
        Button('上次秋分').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_September_Equinox') })
        Button('上次冬至').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_December_Solstice') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 天文时间单位跳转
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 6, bottom: 4 })
      Row() {
        Text('天文时间').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      // 恒星时间
      Row({ space: 4 }) {
        Button('+恒星日').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Sidereal_Day') })
        Button('-恒星日').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Sidereal_Day') })
        Button('+恒星年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Sidereal_Year') })
        Button('-恒星年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Sidereal_Year') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 月周期
      Row({ space: 4 }) {
        Button('+朔望月').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Synodic_Month') })
        Button('-朔望月').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Synodic_Month') })
        Button('+沙罗周期').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Saros') })
        Button('-沙罗周期').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Saros') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 回归年/儒略年
      Row({ space: 4 }) {
        Button('+回归年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Tropical_Year') })
        Button('-回归年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Tropical_Year') })
        Button('+儒略年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Julian_Year') })
        Button('-儒略年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Julian_Year') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 日历月/年
      Row({ space: 4 }) {
        Button('+月').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Month') })
        Button('-月').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Calendar_Month') })
        Button('+年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Year') })
        Button('-年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Calendar_Year') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 更多周期
      Row({ space: 4 }) {
        Button('+近点月').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Anomalistic_Month') })
        Button('+交点月').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Draconic_Month') })
        Button('+默冬周期').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Metonic_Cycle') })
        Button('+不周期').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Inex') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 4 }) {
        Button('+高斯年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Gaussian_Year') })
        Button('+10年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Decade') })
        Button('+100年').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Century') })
        Button('+儒略世纪').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Julian_Century') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 滚动选择日期
      Row() {
        Text($r('app.string.i0012')).fontSize(13).fontColor(this.nmSub()).width(72)
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
        Text($r('app.string.i0013')).fontSize(13).fontColor(this.nmSub()).width(72)
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
      Button($r('app.string.i0046'))
        .fontSize(14).fontColor('#FFFFFFFF').backgroundColor('#5B93BF')
        .borderRadius(12).height(40).width('100%').margin({ top: 4 })
        .onClick(() => { this.applyManualTime() })
      Button($r('app.string.i0047'))
        .fontSize(13).fontColor('#66FFFFFF').backgroundColor(this.nmBorder())
        .borderRadius(8).height(36).width('100%').margin({ top: 2 })
        .onClick(() => {
          this.syncManualTimeFromState()
          this.flashHint($r('app.string.i0081'))
        })

	    } else if (this.activePanel === 'place') {
      Row() {
        Text($r('app.string.i0014')).fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.locationText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text($r('app.string.i0015')).fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.coordinateText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text($r('app.string.i0016')).fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.altitudeText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      this.locationPickerPanel()
      this.quickChips(['北京', '上海', '深圳'])
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
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(4)
      .scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'search') {
      TextInput({ text: this.searchText, placeholder: $r('app.string.i0063') })
        .height(44)
        .fontSize(15)
        .fontColor('#E5FFFFFF')
        .placeholderColor(this.nmSub())
        .backgroundColor(this.nmInput())
        .border({ width: 1, color: 'rgba(214, 238, 255, 0.16)' })
        .borderRadius(22)
        .onChange((value: string) => {
          this.searchText = value
          this.fetchSuggestions(value)
        })
        .onSubmit(() => {
          this.searchObject(this.searchText)
        })
      // 搜索历史（无输入时显示，可点击复用）
      if (this.searchText.length === 0 && this.searchHistory.length > 0) {
        Row() {
          Text('搜索历史').fontSize(11).fontColor(this.nmSub()).margin({ right: 8 })
          Text('清除').fontSize(11).fontColor('#4488FF').onClick(() => {
            this.searchHistory = []
            AppStorage.setOrCreate('searchHistory', JSON.stringify(this.searchHistory))
          })
        }.width('100%').padding({ left: 10, right: 10 }).margin({ top: 8, bottom: 4 })
        Scroll() {
          Row() {
            ForEach(this.searchHistory, (item: string) => {
              Text(item).fontSize(13).fontColor(this.nmText()).padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.nmBg()).borderRadius(16).margin({ right: 6, bottom: 6 })
                .onClick(() => {
                  this.searchText = item
                  this.searchObject(item)
                })
            })
          }.padding({ left: 10 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(42)
      }
      // 搜索建议列表（输入时自动补全）
      if (this.searchSuggestions.length > 0) {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.searchSuggestions, (s: SearchSug) => {
              Text(s.zh + (s.zh !== s.en ? '  ' + s.en : ''))
                .fontSize(12).fontColor(this.nmText())
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor(this.nmBg())
                .borderRadius(8)
                .onClick(() => {
                  this.searchObject(s.en)
                  this.searchSuggestions = []
                })
            }, (s: SearchSug) => s.en)
          }.padding({ left: 4, right: 4 })
        }.width('100%').height(36).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      // 天体分类浏览（按分类 tab 切换，点击加载该分类天体列表）
      Row() {
        Text(('app.string.i0021')).fontSize(12).fontColor(this.nmSub()).width(72)
        Row({ space: 4 }) {
          ForEach([
            { code: 'planet', label: $r('app.string.i0103') },
            { code: 'star', label: $r('app.string.i0104') },
            { code: 'galaxy', label: $r('app.string.i0105') },
            { code: 'cluster', label: $r('app.string.i0106') },
            { code: 'nebula', label: $r('app.string.i0107') },
            { code: 'messier', label: $r('app.string.i0108') },
          ] as CatOption[], (cat: CatOption) => {
            Text(cat.label)
              .fontSize(11).fontColor(this.searchCategory === cat.code ? this.nmText() : this.nmSub())
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.searchCategory === cat.code ? this.nmAccent() : this.nmBg())
              .borderRadius(8)
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
            Text(item.zh ?? item.name ?? '')
              .fontSize(11).fontColor(this.nmText())
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor(this.nmBg())
              .borderRadius(8)
              .onClick(() => this.searchObject(item.name ?? ''))
          }, (item: NameItem) => item.name)
        }.padding({ left: 4, right: 4 })
      }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    } else if (this.activePanel === 'config') {
      // Configuration 面板
      Row({ space: 2 }) {
        ForEach([
          { label: '主设置', id: 0 },
          { label: '信息', id: 1 },
          { label: '附加', id: 2 },
          { label: '时间', id: 3 },
          { label: '工具', id: 4 },
          { label: '脚本', id: 5 },
          { label: '插件', id: 6 },
        ] as TabItem[], (tab: TabItem) => {
          Text(tab.label)
            .fontSize(10)
            .fontColor(this.configTab === tab.id ? this.nmText() : this.nmSub())
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.configTab === tab.id ? this.nmAccent() : this.nmBg())
            .borderRadius(6)
            .onClick(() => { this.configTab = tab.id })
        }, (tab: TabItem, index: number) => tab.id.toString())
      }.width('100%').padding({ left: 2, right: 2 }).margin({ top: 4, bottom: 8 })
      Scroll() {
        Column({ space: 0 }) {
          if (this.configTab === 0) {
            // Main
            this.languageRow()
            Row() {
              Text('星空文化').fontSize(12).fontColor(this.nmSub()).width(72)
              Text('需C++桥接').fontSize(11).fontColor('#446688FF').layoutWeight(1)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            this.lockRow()
            this.infoRow('版本', 'Stellarium 26.2 for HarmonyOS')
          } else if (this.configTab === 1) {
            // Information
            Row() {
              Text('信息级别').fontSize(12).fontColor(this.nmSub()).width(72)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Row({ space: 6 }) {
              Button('全部').fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 0 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 0; this.triggerAction('actionDisplayInfo_All') })
              Button('默认').fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 1 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 1; this.triggerAction('actionDisplayInfo_Default') })
              Button('简短').fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 2 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 2; this.triggerAction('actionDisplayInfo_Short') })
              Button('无').fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 3 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 3; this.triggerAction('actionDisplayInfo_None') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
          } else if (this.configTab === 2) {
            // Extras
            this.infoRow('应用', 'Stellarium for HarmonyOS')
            this.infoRow('平台', 'OpenHarmony / HarmonyOS NEXT')
          } else if (this.configTab === 3) {
            // Time
            this.infoRow('时间格式', '24 小时制')
            this.infoRow('日期格式', 'YYYY-MM-DD')
            this.infoRow('历法', '格里高利历')
            Row() {
              Text('（需C++桥接切换）').fontSize(10).fontColor('#446688FF').width('100%').padding({ left: 2 })
            }.height(18).width('100%').margin({ top: 4 })
          } else if (this.configTab === 4) {
            // Tools
            Row() {
              Text('截图保存').fontSize(12).fontColor(this.nmSub()).width(72)
              Button('保存').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionSave_Screenshot_Global') })
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            this.infoRow('截图格式', 'PNG')
            this.infoRow('渲染帧率', '需C++桥接')
          } else if (this.configTab === 5) {
            // Scripts
            Row() {
              Text('脚本播放').fontSize(12).fontColor(this.nmSub()).width(72)
              Button('停止').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionStop_Script') })
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Row() {
              Text('脚本列表').fontSize(12).fontColor(this.nmSub()).width(72)
              Text('需C++桥接').fontSize(11).fontColor('#446688FF').layoutWeight(1)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          } else {
            // Plugins
            Row() {
              Text('插件管理').fontSize(12).fontColor(this.nmSub()).width(72)
              Text('需C++桥接').fontSize(11).fontColor('#446688FF').layoutWeight(1)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'astro') {
      // 天文计算窗口
      Row({ space: 2 }) {
        ForEach([
          { label: '位置', id: 0 },
          { label: '星历', id: 1 },
          { label: '升降', id: 2 },
          { label: '天象', id: 3 },
          { label: '图表', id: 4 },
          { label: '今晚', id: 5 },
          { label: '行星', id: 6 },
          { label: '日食', id: 7 },
          { label: '年历', id: 8 },
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
            Text('天体位置表').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            this.infoRow('状态', '需C++桥接 AstroCalcDialog')
            this.infoRow('数据', '选中天体的坐标、星等、角径等')
          } else if (this.astroTab === 1) {
            Text('星历表').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            this.infoRow('状态', '需C++桥接 AstroCalcDialog')
          } else if (this.astroTab === 2) {
            Text('升起/中天/落下').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            this.infoRow('状态', '需C++桥接 AstroCalcDialog')
            Row({ space: 6 }) {
              Button('下次升起').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionNext_Rising') })
              Button('下次中天').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionNext_Transit') })
              Button('下次落下').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionNext_Setting') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          } else if (this.astroTab === 3) {
            Text('天象计算').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            this.infoRow('状态', '需C++桥接（合/冲/距角等）')
          } else if (this.astroTab === 4) {
            Text('高度/方位角图表').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            this.infoRow('状态', '需C++桥接（折线图渲染）')
          } else if (this.astroTab === 5) {
            Text('今晚可见').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            this.infoRow('状态', '需C++桥接 WUT（30+分类）')
          } else if (this.astroTab === 6) {
            Text('行星计算器').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            this.infoRow('状态', '需C++桥接（距离/周期/速度）')
          } else if (this.astroTab === 7) {
            Text('日月食').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            this.infoRow('状态', '需C++桥接（日食/月食/凌日表）')
          } else {
            Text('年历').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            this.infoRow('状态', '需C++桥接（四季/日出日落/晨昏蒙影）')
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'help') {
      // Help 面板
      Scroll() {
        Column({ space: 8 }) {
          Text('关于').fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4 })
          Text('Stellarium for HarmonyOS').fontSize(11).fontColor(this.nmSub()).width('100%')
          Text('基于 Stellarium 26.2 C++ 核心的社区移植版').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('渲染引擎：OpenGL ES via XComponent').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('ArkTS-N-API-C-C++ 桥接架构').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Text('快捷操作').fontSize(13).fontColor(this.nmText()).width('100%')
          Text('单指拖动：平移视角').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('双指捏合：缩放').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('单击天体：选中并显示信息').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('长按天体：追踪').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Text('功能面板').fontSize(13).fontColor(this.nmText()).width('100%')
          Text('View：显示选项（天空/太阳系/深空/标记/地景/文化/巡天）').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('Search：搜索天体').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('Time：时间控制（天文事件/节气跳转）').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('Location：位置选择（GPS/地图/城市）').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('Config：应用配置').fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text('AstroCalc：天文计算').fontSize(10).fontColor('#66FFFFFF').width('100%')
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else {
      this.infoRow($r('app.string.i0057'), this.isExpandedLayout ? '宽屏布局' : '触屏布局')
      this.infoRow($r('app.string.i0058'), 'Stellarium Core')
      this.infoRow($r('app.string.i0059'), this.fovText)
      this.infoRow($r('app.string.i0060'), this.gyroscopeStatus)
      this.infoRow($r('app.string.i0061'), this.gyroscopeSensitivityText)
      this.gyroscopeRow()
      this.lx200Panel()
      this.languageRow()
      this.lockRow()
      // 观测列表
      if (this.observingList.length > 0) {
        Row() {
          Text($r('app.string.i0022')).fontSize(12).fontColor("#66FFFFFF").width(72)
          Text(this.observingList.length + " 个天体").fontSize(14).fontColor("#E5FFFFFF").layoutWeight(1)
        }
        .height(34).width("100%").padding({ left: 10, right: 10 }).backgroundColor("rgba(255, 255, 255, 0.04)").borderRadius(12).margin({ bottom: 4 })
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.observingList, (name: string) => {
              Text(this.zhNameOf(name))
                .fontSize(11).fontColor("#E5FFFFFF")
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor("rgba(107,163,214,0.20)")
                .borderRadius(8)
                .onClick(() => {
                  this.searchObject(name)
                  this.flashHint($r('app.string.i0082', name))
                })
            }, (name: string) => name)
          }.padding({ left: 4, right: 4 })
        }.width("100%").height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      this.infoRow($r('app.string.i0062'), '单 HAP')
      // 分区：方向
      Row()
        .width('100%').height(0.5)
        .backgroundColor('rgba(255,255,255,0.06)')
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text('方向控制').fontSize(11).fontColor('#66FFFFFF').width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row() {
        this.quickChips(['东', '南', '西', '北', $r('app.string.i0088'), $r('app.string.i0089')])
      }
      .width('100%')
      // 分区：视场
      Row()
        .width('100%').height(0.5)
        .backgroundColor('rgba(255,255,255,0.06)')
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text('视场角').fontSize(11).fontColor('#66FFFFFF').width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row() {
        this.quickChips(['1°', '2°', '5°', '10°', '20°', '45°', '60°', '90°', '180°'])
      }
      .width('100%')
      // 天球投影切换
      Row() {
        Text($r('app.string.i0025')).fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.equatorialMount ? $r('app.string.i0008') : $r('app.string.i0009'))
          .fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.equatorialMount })
          .onChange((isOn: boolean) => {
            this.equatorialMount = isOn
            this.triggerAction('actionSwitch_Equatorial_Mount')
            this.refreshState()
            this.flashHint(isOn ? $r('app.string.i0008') : $r('app.string.i0009'))
          })
      }
      .height(40).width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.nmBg()).borderRadius(12).margin({ top: 4, bottom: 4 })
      // 截图+夜间模式
      Row() {
        Button($r('app.string.i0048'))
          .fontSize(13).fontColor('#E5FFFFFF').backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(12).height(36).layoutWeight(1)
          .onClick(() => {
            this.callInteractive('saveScreenShot', '', () => { this.flashHint($r('app.string.i0083')) })
          })
        Row() {
            Image($r(this.nightMode ? 'app.media.ic_moon' : 'app.media.ic_sun')).width(16).height(16).fillColor('#E5FFFFFF')
            Text(this.nightMode ? '夜间模式' : '日间模式').fontSize(12).fontColor('#E5FFFFFF').margin({ left: 4 })
          }
          .padding({ left: 10, right: 10 }).backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(12).height(36).layoutWeight(1).margin({ left: 8 })
          .onClick(() => {
            this.nightMode = !this.nightMode
            this.triggerAction('actionShow_Night_Mode')
            this.flashHint(this.nightMode ? '夜间模式' : '日间模式')
          })
      }
      .width('100%').margin({ top: 4, bottom: 4 })
      // 星空翻转
      Row() {
        Text('星空翻转').fontSize(12).fontColor('#66FFFFFF').width(72)
        Row() {
              Image($r('app.media.ic_layers')).width(14).height(14).fillColor('#E5FFFFFF')
              Text(this.flipVert ? '南天在上' : '北天在上').fontSize(11).fontColor('#E5FFFFFF').margin({ left: 3 })
            }
          .padding({ left: 8, right: 8 }).backgroundColor(this.flipVert ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.08)')
          .borderRadius(12).height(32).layoutWeight(1)
          .onClick(() => {
            this.flipVert = !this.flipVert
            this.triggerAction('actionVertical_Flip')
            this.flashHint(this.flipVert ? '南天在上' : '北天在上')
          })
        Row() {
              Image($r('app.media.ic_refresh')).width(14).height(14).fillColor('#E5FFFFFF')
              Text(this.flipHoriz ? '已镜像' : '正常').fontSize(11).fontColor('#E5FFFFFF').margin({ left: 3 })
            }
          .padding({ left: 8, right: 8 }).backgroundColor(this.flipHoriz ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.08)')
          .padding({ left: 8, right: 8 }).borderRadius(12).height(32).layoutWeight(1).margin({ left: 6 }).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.flipHoriz = !this.flipHoriz
            this.triggerAction('actionHorizontal_Flip')
            this.flashHint(this.flipHoriz ? '已镜像' : '正常')
          })
      }
      .width('100%').padding({ left: 10, right: 10 }).margin({ top: 2, bottom: 4 })
      this.quickChips(['刷新', '现在'])
      // 帮助说明
      Row() {
        Text($r('app.string.i0026')).fontSize(12).fontColor("#66FFFFFF").width(72)
      }
      .height(6).width("100%").margin({ top: 2 })
      Text($r('app.string.i0027'))
        .fontSize(11).fontColor("#99FFFFFF").width("100%").padding({ left: 4, right: 4 })
      Text($r('app.string.i0028'))
        .fontSize(11).fontColor("#99FFFFFF").width("100%").padding({ left: 4, right: 4 }).margin({ top: 2 })
      // 语言选择
      Row() {
        Text($r('app.string.i0029')).fontSize(12).fontColor("#66FFFFFF").width(72)
        Text(this.selectedLanguage === 'zh_CN' ? $r('app.string.i0030') :
             this.selectedLanguage === 'zh_TW' ? '繁体中文' :
             this.selectedLanguage === 'en' ? $r('app.string.i0032') :
             this.selectedLanguage === 'ja' ? $r('app.string.i0033') :
             this.selectedLanguage === 'ko' ? $r('app.string.i0034') : this.selectedLanguage)
          .fontSize(14).fontColor("#E5FFFFFF").layoutWeight(1)
      }
      .height(34).width("100%").padding({ left: 10, right: 10 }).backgroundColor("rgba(255, 255, 255, 0.04)").borderRadius(12).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Text($r('app.string.i0030'))
          .fontSize(11).fontColor(this.selectedLanguage === 'zh_CN' ? "#FFFFFFFF" : "#99FFFFFF")
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor(this.selectedLanguage === 'zh_CN' ? "rgba(107,163,214,0.35)" : "rgba(255,255,255,0.05)")
          .borderRadius(8)
          .onClick(() => this.setLanguage('zh_CN'))
        Text($r('app.string.i0031'))
          .fontSize(11).fontColor(this.selectedLanguage === 'zh_TW' ? "#FFFFFFFF" : "#99FFFFFF")
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor(this.selectedLanguage === 'zh_TW' ? "rgba(107,163,214,0.35)" : "rgba(255,255,255,0.05)")
          .borderRadius(8)
          .onClick(() => this.setLanguage('zh_TW'))
        Text($r('app.string.i0032'))
          .fontSize(11).fontColor(this.selectedLanguage === 'en' ? "#FFFFFFFF" : "#99FFFFFF")
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor(this.selectedLanguage === 'en' ? "rgba(107,163,214,0.35)" : "rgba(255,255,255,0.05)")
          .borderRadius(8)
          .onClick(() => this.setLanguage('en'))
        Text($r('app.string.i0033'))
          .fontSize(11).fontColor(this.selectedLanguage === 'ja' ? "#FFFFFFFF" : "#99FFFFFF")
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor(this.selectedLanguage === 'ja' ? "rgba(107,163,214,0.35)" : "rgba(255,255,255,0.05)")
          .borderRadius(8)
          .onClick(() => this.setLanguage('ja'))
        Text($r('app.string.i0034'))
          .fontSize(11).fontColor(this.selectedLanguage === 'ko' ? "#FFFFFFFF" : "#99FFFFFF")
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor(this.selectedLanguage === 'ko' ? "rgba(107,163,214,0.35)" : "rgba(255,255,255,0.05)")
          .borderRadius(8)
          .onClick(() => this.setLanguage('ko'))
      }.padding({ left: 4, right: 4 }).margin({ bottom: 8 })
      // 星图文化选择
      if (this.skyCultures.length > 0) {
        Row() {
          Text($r('app.string.i0035')).fontSize(12).fontColor("#66FFFFFF").width(72)
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
      Text($r('app.string.i0036'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E5FFFFFF')
        .width('100%')
      TextInput({ text: this.lx200Host, placeholder: $r('app.string.i0064') })
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
      TextInput({ text: this.lx200Port, placeholder: $r('app.string.i0065') })
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
        Button($r('app.string.i0049'))
          .height(32)
          .fontSize(12)
          .fontColor('#FFFFFFFF')
          .backgroundColor('#5B93BF')
          .borderRadius(16)
          .margin({ right: 8 })
          .onClick(() => {
            this.lx200GotoSelected()
          })
        Button($r('app.string.i0050'))
          .height(32)
          .fontSize(12)
          .fontColor('#5B93BF')
          .backgroundColor('rgba(107, 163, 214, 0.20)')
          .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
          .borderRadius(16)
          .margin({ right: 8 })
          .onClick(() => {
            this.lx200SyncSelected()
          })
        Button($r('app.string.i0051'))
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
        .fontColor('#66FFFFFF')
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
        Text($r('app.string.i0037'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E5FFFFFF')
          .layoutWeight(1)
        Row() {
            Image($r('app.media.ic_location')).width(14).height(14).fillColor('#FFFFFFFF')
            Text($r('app.string.i0052')).fontSize(11).fontColor('#FFFFFFFF').margin({ left: 4 })
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
        this.locationModeChip('map', '地图选点')
        this.locationModeChip('hierarchy', '按地区选')
      }
        .width('100%')
        .margin({ top: 10 })

      if (this.locationPickMode === 'map') {
        TextInput({ text: this.locationPickerName, placeholder: $r('app.string.i0066') })
          .height(36)
          .fontSize(13)
          .fontColor('#E5FFFFFF')
          .placeholderColor(this.nmSub())
          .backgroundColor(this.nmInput())
          .border({ width: 1, color: 'rgba(214, 238, 255, 0.14)' })
          .borderRadius(12)
          .margin({ top: 10 })
          .onChange((value: string) => {
            this.locationPickerName = value.length > 0 ? value : '自定义位置'
          })
        Stack() {
          Image($rawfile('worldmap.jpg'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
          // 经纬度刻度
          Text('N').fontSize(9).fontColor('#66FFFFFF').position({ x: 6, y: 4 })
          Text('S').fontSize(9).fontColor('#66FFFFFF').position({ x: 6, y: this.mapRenderHeight - 16 })
          Text('90°W').fontSize(8).fontColor('#446688FF').position({ x: 4, y: Math.round(this.mapRenderHeight / 2) - 4 })
          Text('90°E').fontSize(8).fontColor('#446688FF').position({ x: this.mapRenderWidth - 32, y: Math.round(this.mapRenderHeight / 2) - 4 })
          Text($r('app.string.i0040'))
            .fontSize(18)
            .fontColor('#5B93BF')
            .textShadow({ radius: 8, color: 'rgba(159, 232, 255, 0.75)', offsetX: 0, offsetY: 0 })
            .position({ x: this.pickerPinX(), y: this.pickerPinY() })
        }
          .width('100%')
          .height(this.locationMapHeight())
          .clip(true)
          .backgroundColor('rgba(11, 24, 43, 0.46)')
          .border({ width: 1, color: 'rgba(159, 232, 255, 0.22)' })
          .borderRadius(14)
          .margin({ top: 10 })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            this.mapRenderWidth = Number(newArea.width)
            this.mapRenderHeight = Number(newArea.height)
          })
          .onTouch((event: TouchEvent) => {
            this.handleLocationMapTouch(event)
          })
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

      TextInput({ text: this.locationPickerAltitude.toFixed(0), placeholder: $r('app.string.i0067') })
        .height(34)
        .fontSize(12)
        .fontColor('#E5FFFFFF')
        .placeholderColor('#8EA0BD')
        .backgroundColor('rgba(255, 255, 255, 0.06)')
        .border({ width: 1, color: 'rgba(214, 238, 255, 0.14)' })
        .borderRadius(12)
        .margin({ top: 8 })
        .onChange((value: string) => {
          const altitude = Number(value)
          if (Number.isFinite(altitude)) {
            this.locationPickerAltitude = Math.round(altitude)
          }
        })
      Row() {
        Row() {
            Image($r('app.media.ic_globe')).width(14).height(14).fillColor('#FFFFFFFF')
            Text($r('app.string.i0053')).fontSize(12).fontColor('#FFFFFFFF').margin({ left: 4 })
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
          .fontColor('#66FFFFFF')
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
	        Text($r('app.string.i0041'))
	          .fontSize(12)
	          .fontColor('#8EA0BD')
	          .layoutWeight(1)
	        Text(this.lx200Host + ':' + this.lx200Port)
	          .fontSize(12)
	          .fontColor('#99FFFFFF')
	          .maxLines(1)
	          .textOverflow({ overflow: TextOverflow.Ellipsis })
	      }
	        .width('100%')
	      Row() {
	        Button($r('app.string.i0049'))
	          .height(32)
	          .fontSize(12)
	          .fontColor('#FFFFFFFF')
	          .backgroundColor('#5B93BF')
	          .borderRadius(16)
	          .margin({ right: 8 })
	          .onClick(() => {
	            this.lx200GotoSelected()
	          })
	        Button($r('app.string.i0050'))
	          .height(32)
	          .fontSize(12)
	          .fontColor('#5B93BF')
	          .backgroundColor('rgba(107, 163, 214, 0.20)')
	          .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
	          .borderRadius(16)
	          .margin({ right: 8 })
	          .onClick(() => {
	            this.lx200SyncSelected()
	          })
	        Button($r('app.string.i0051'))
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
	        .fontColor('#66FFFFFF')
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
      Text($r('app.string.i0042'))
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.uiLocked })
        .width(46)
        .height(28)
        .selectedColor('#5B93BF')
        .onChange((value: boolean) => {
          this.uiLocked = value
          this.flashHint(value ? '界面已锁定' : '可拖动面板')
        })
    }
      .height(40)
      .width('100%')
  }

  @Builder
  languageRow() {
    Row() {
      Text($r('app.string.i0029'))
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .width(72)
      Scroll() {
        Row({ space: 6 }) {
          ForEach([
            { code: 'zh_CN', name: '简体中文' },
            { code: 'zh_HK', name: '繁體(港)' },
            { code: 'zh_TW', name: '繁體(台)' },
            { code: 'ja', name: $r('app.string.i0033') },
            { code: 'ko', name: $r('app.string.i0034') },
            { code: 'de', name: 'Deutsch' },
            { code: 'fr', name: 'Français' },
            { code: 'es', name: 'Español' },
            { code: 'pt_BR', name: 'Português' },
            { code: 'ru', name: 'Русский' },
            { code: 'uk', name: 'Українська' },
            { code: 'it', name: 'Italiano' },
            { code: 'nl', name: 'Nederlands' },
            { code: 'pl', name: 'Polski' },
            { code: 'sv', name: 'Svenska' },
            { code: 'cs', name: 'Čeština' },
            { code: 'tr', name: 'Türkçe' },
            { code: 'ar', name: 'العربية' },
            { code: 'hi', name: 'हिन्दी' },
            { code: 'th', name: 'ไทย' },
            { code: 'vi', name: 'Tiếng Việt' },
            { code: 'en', name: $r('app.string.i0032') },
          ], (lang: LangOption) => {
            Text(lang.name)
              .fontSize(12)
              .fontColor(this.selectedLanguage === lang.code ? '#5B93BF' : '#66FFFFFF')
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
      Text($r('app.string.i0043'))
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.gyroscopeEnabled })
        .width(46)
        .height(28)
        .selectedColor('#5B93BF')
        .onChange((value: boolean) => {
          this.toggleGyroscope(value)
          this.flashHint(value ? '已开启陀螺仪' : '已关闭陀螺仪')
        })
    }
      .height(40)
      .width('100%')
  }

  @Builder
  quickChips(labels: ResourceStr[]) {
    Row() {
      ForEach(labels, (label: string) => {
        Button(label)
          .fontSize(12)
          .fontColor('#5B93BF')
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
            this.handleChip(label)
            this.flashHint(label)
          })
      }, (label: string) => label)
    }
      .width('100%')
      .margin({ top: 12 })
  }

  private handleChip(label: string): void {
    const en = this.enNameOf(label)
    if (label === '刷新') {
      this.refreshSelectedObject()
      this.refreshState()
    } else if (label === '居中' || label === '追踪') {
      this.moveToSelectedObject()
    } else if (label === '取消追踪') {
      this.callInteractive('setTracking', '0', () => { this.refreshState() })
    } else if (label === '现在') {
      this.triggerAction('actionReturn_To_Current_Time')
      this.setTimeRate(0.000011574074074073)
    } else if (label === '后退') {
      this.triggerAction('actionDecrease_Time_Speed')
    } else if (label === '暂停') {
      this.setTimeRate(0)
    } else if (label === '前进') {
      this.triggerAction('actionIncrease_Time_Speed')
    } else if (label === '+12h') {
      this.advanceTime(12)
    } else if (label === '-12h') {
      this.advanceTime(-12)
    } else if (en === 'Moon') {
      this.searchObject('Moon')
    } else if (en === 'Mars') {
      this.searchObject('Mars')
    } else if (en === 'Jupiter') {
      this.searchObject('Jupiter')
    } else if (label === '北京') {
      this.setLocation('Beijing', 39.9042, 116.4074, 44)
    } else if (label === '上海') {
      this.setLocation('Shanghai', 31.2304, 121.4737, 4)
    } else if (label === '深圳') {
      this.setLocation('Shenzhen', 22.5431, 114.0579, 40)
    // 搜索面板天体快捷搜索（中英文标签都认）
    } else if (['Sun', 'Mercury', 'Venus', 'Saturn', 'Sirius', 'Vega', 'Betelgeuse', 'Polaris', 'M31', 'M42', 'M45', 'NGC 2244'].includes(en)) {
      this.searchObject(en)
    // 方向快捷查看
    } else if (label === '东') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_East'); this.refreshState(); this.flashHint($r('app.string.i0084'))
    } else if (label === '南') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_South'); this.refreshState(); this.flashHint($r('app.string.i0085'))
    } else if (label === '西') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_West'); this.refreshState(); this.flashHint($r('app.string.i0086'))
    } else if (label === '北') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_North'); this.refreshState(); this.flashHint($r('app.string.i0087'))
    } else if (label === '天顶') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_Zenith'); this.refreshState(); this.flashHint($r('app.string.i0088'))
    } else if (label === '北天极') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_NCP'); this.refreshState(); this.flashHint($r('app.string.i0089'))
    // FOV 快捷切换（actionSet_FOV 索引: 0=0.5°, 1=180°, 2=90°, 3=60°, 4=45°, 5=20°, 6=10°, 7=5°, 8=2°, 9=1°）
    } else if (label === '1°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_9'); this.refreshState(); this.flashHint($r('app.string.i0090'))
    } else if (label === '2°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_8'); this.refreshState(); this.flashHint($r('app.string.i0091'))
    } else if (label === '5°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_7'); this.refreshState(); this.flashHint($r('app.string.i0092'))
    } else if (label === '10°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_6'); this.refreshState(); this.flashHint($r('app.string.i0093'))
    } else if (label === '20°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_5'); this.refreshState(); this.flashHint($r('app.string.i0094'))
    } else if (label === '45°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_4'); this.refreshState(); this.flashHint($r('app.string.i0095'))
    } else if (label === '60°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_3'); this.refreshState(); this.flashHint($r('app.string.i0096'))
    } else if (label === '90°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_2'); this.refreshState(); this.flashHint($r('app.string.i0097'))
    } else if (label === '180°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_1'); this.refreshState(); this.flashHint($r('app.string.i0098'))
    }
  }

  @Builder
  infoRow(label: ResourceStr, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor('#66FFFFFF')
        .width(72)
      Text(value)
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .height(34)
      .width('100%')
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.nmBg())
      .borderRadius(12)
      .margin({ bottom: 4 })
  }

  @Builder
  switchRow(label: ResourceStr, enabled: boolean, actionId: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: enabled })
        .width(46)
        .height(28)
        .selectedColor('#5B93BF')
        .onChange((value: boolean) => {
          this.setLayer(actionId, value)
          this.flashHint((value ? '已显示 ' : '已隐藏 ') + label)
        })
    }
      .height(42)
      .width('100%')
      .padding({ left: 10, right: 8 })
      .backgroundColor(enabled ? 'rgba(107, 163, 214, 0.12)' : 'rgba(255, 255, 255, 0.04)')
      .border({ width: 1, color: enabled ? 'rgba(107, 163, 214, 0.18)' : 'rgba(255, 255, 255, 0.05)' })
      .borderRadius(12)
      .margin({ bottom: 6 })
      .animation({ duration: 160, curve: Curve.EaseOut })
  }

  private panelTitle(): ResourceStr {
    if (this.activePanel === 'search') {
      return $r('app.string.i0099')
    }
    if (this.activePanel === 'time') {
      return $r('app.string.i0054')
    }
    if (this.activePanel === 'place') {
      return $r('app.string.i0014')
    }
    if (this.activePanel === 'layers') {
      return $r('app.string.i0100')
    }
    if (this.activePanel === 'config') {
      return '配置'
    }
    if (this.activePanel === 'astro') {
      return '天文计算'
    }
    if (this.activePanel === 'help') {
      return '帮助'
    }
    if (this.activePanel === 'settings') {
      return $r('app.string.i0102')
    }
    return '目标详情'
  }

  private panelSubtitle(): ResourceStr {
    if (this.activePanel === 'search') {
      return '快速定位天体'
    }
    if (this.activePanel === 'time') {
      return '调整观测时间'
    }
    if (this.activePanel === 'place') {
      return '观测点与定位'
    }
    if (this.activePanel === 'layers') {
      return '显示内容开关'
    }
    if (this.activePanel === 'config') {
      return '应用设置与配置'
    }
    if (this.activePanel === 'astro') {
      return '位置/星历/升降/天象/图表'
    }
    if (this.activePanel === 'help') {
      return '关于与操作说明'
    }
    if (this.activePanel === 'settings') {
      return '显示与控制'
    }
    return '点击星空后显示'
  }

  // View 面板标签页选择器
  @Builder viewTabs() {
    Row({ space: 2 }) {
      ForEach([
        { label: '天空', id: 0 },
        { label: '太阳系', id: 1 },
        { label: '深空', id: 2 },
        { label: '标记', id: 3 },
        { label: '地景', id: 4 },
        { label: '文化', id: 5 },
        { label: '巡天', id: 6 },
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
    this.switchRow('大气', this.atmosphere, 'actionShow_Atmosphere')
    this.switchRow('地面', this.ground, 'actionShow_Ground')
    this.switchRow('雾效果', this.fogEffect, 'actionShow_Fog')
    this.switchRow('流星', this.meteors, 'actionShow_Meteors')
    // 银河亮度
    Row() {
      Text('银河亮度').fontSize(12).fontColor(this.nmSub()).width(72)
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
      Text('光污染').fontSize(12).fontColor(this.nmSub()).width(72)
      Button('减少').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(26).padding({ left: 8, right: 8 })
        .onClick(() => { this.triggerAction('actionShow_LightPollutionReduce') })
      Button('增加').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(26).padding({ left: 8, right: 8 })
        .onClick(() => { this.triggerAction('actionShow_LightPollutionIncrease') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    this.switchRow('夜间模式', this.nightMode, 'actionShow_Night_Mode')
    this.switchRow('星空水平翻转', this.flipHoriz, 'actionHorizontal_Flip')
    this.switchRow('星空垂直翻转', this.flipVert, 'actionVertical_Flip')
  }

  // View 面板 SSO 标签页内容
  @Builder viewSSOTab() {
    this.switchRow('行星标签', this.planets, 'actionShow_Planets')
    this.switchRow('行星轨道', this.planetOrbits, 'actionShow_Planets_Orbits')
    this.switchRow('行星轨迹', this.planetTrails, 'actionShow_Planets_Trails')
    this.switchRow('行星标记', this.planetHints, 'actionShow_Planets_Hints')
    this.switchRow('放大月球', this.enlargeMoon, 'actionShow_Planets_EnlargeMoon')
    this.switchRow('放大行星', false, 'actionShow_Planets_EnlargePlanets')
    this.switchRow('放大太阳', false, 'actionShow_Planets_EnlargeSun')
    this.switchRow('小天体标记', false, 'actionShow_Planets_ShowMinorBodyMarkers')
    this.switchRow('命名标签', false, 'actionShow_Planets_Nomenclature')
    Row() {
      Text('轨迹重置').fontSize(12).fontColor(this.nmSub()).width(72)
      Button('重置').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.triggerAction('actionShow_Planets_Trails_Reset') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
  }

  // View 面板 DSO 标签页内容
  @Builder viewDSOTab() {
    this.switchRow('深空天体', this.nebulae, 'actionShow_Nebulas')
    this.switchRow('深空标签', this.dsoLabels, 'actionShow_Nebulas')
    this.switchRow('深空背景图', this.dsoTextures, 'actionShow_DSO_Textures')
    Row() {
      Text('重载背景').fontSize(12).fontColor(this.nmSub()).width(72)
      Button('重载').fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.triggerAction('actionShow_DSO_Textures_Reload') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    Row()
      .width('100%').height(0.5)
      .backgroundColor(this.nmBorder())
      .margin({ top: 6, bottom: 4 })
    Row() {
      Text('星表过滤（需C++桥接）').fontSize(10).fontColor('#446688FF').width('100%').padding({ left: 2 })
    }
    .height(18).width('100%')
  }

  // View 面板 Markings 标签页内容
  @Builder viewMarkingsTab() {
    Scroll() {
      Column({ space: 0 }) {
        // 基础网格
        Text('基础网格').fontSize(11).fontColor(this.nmSub()).width('100%').margin({ top: 4, bottom: 2 }).padding({ left: 2 })
        this.switchRow('赤道网格', this.equatorialGrid, 'actionShow_Equatorial_Grid')
        this.switchRow('方位网格', this.azimuthGrid, 'actionShow_Azimuthal_Grid')
        // 特殊线
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text('特殊线').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow('赤道线', this.equatorLine, 'actionShow_Equator_Line')
        this.switchRow('黄道线', this.eclipticLine, 'actionShow_Ecliptic_Line')
        this.switchRow('子午线', this.meridianLine, 'actionShow_Meridian_Line')
        this.switchRow('地平线', this.horizonLine, 'actionShow_Horizon_Line')
        this.switchRow('银道线', this.galacticEquator, 'actionShow_Galactic_Equator_Line')
        this.switchRow('超银道', this.supergalacticEq, 'actionShow_Supergalactic_Equator_Line')
        this.switchRow('银道网格', this.galacticGrid, 'actionShow_Galactic_Grid')
        // J2000 线
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text('J2000 基准').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow('J2000 赤道', this.equJ2000Line, 'actionShow_Equator_J2000_Line')
        this.switchRow('J2000 黄道', this.eclJ2000Line, 'actionShow_Ecliptic_J2000_Line')
        // 点标记
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text('点标记').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow('天极', this.celestialPoles, 'actionShow_Celestial_Poles')
        this.switchRow('黄极', this.eclipticPoles, 'actionShow_Ecliptic_Poles')
        this.switchRow('银极', this.galacticPoles, 'actionShow_Galactic_Poles')
        this.switchRow('分点', this.equinoxPoints, 'actionShow_Equinox_Points')
        this.switchRow('至点', this.solsticePoints, 'actionShow_Solstice_Points')
        this.switchRow('反日点', this.antisolarPoint, 'actionShow_Antisolar_Point')
        this.switchRow('本影圈', this.umbraCircle, 'actionShow_Umbra_Circle')
        this.switchRow('半影圈', this.penumbraCircle, 'actionShow_Penumbra_Circle')
        // 辅助标记
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text('辅助标记').fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow('罗盘标记', this.compassMarks, 'actionShow_Compass_Marks')
        this.switchRow('FOV标记', this.fovMarker, 'actionShow_FOV_Center_Marker')
        this.switchRow('中间方位', this.intercardinalPts, 'actionShow_Intercardinal_Points')
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
    this.switchRow('地面', this.ground, 'actionShow_Ground')
    this.switchRow('景观照明', this.landscapeIllum, 'actionShow_LandscapeIllumination')
    this.switchRow('景观标签', this.landscapeLabels, 'actionShow_LandscapeLabels')
    this.switchRow('雾效果', this.fogEffect, 'actionShow_Fog')
    Row() {
      Text('地景列表（需C++桥接）').fontSize(10).fontColor('#446688FF').width('100%').padding({ left: 2 })
    }.height(18).width('100%').margin({ top: 6 })
    Row() {
      Text('透明度').fontSize(12).fontColor(this.nmSub()).width(72)
      Text(this.landscapeTransp + '%').fontSize(14).fontColor(this.nmText()).margin({ right: 8 })
      Slider({ value: this.landscapeTransp, min: 0, max: 100, step: 5, style: SliderStyle.OutSet })
        .width('40%')
        .blockColor(this.nmAccent())
        .trackColor(this.nmBg())
        .selectedColor(this.nmAccent())
        .showSteps(false)
        .onChange((val: number) => { this.landscapeTransp = Math.round(val) })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
  }

  // View 面板 Sky Culture 标签页内容
  @Builder viewSkyCultureTab() {
    this.switchRow('星座线', this.constellationLines, 'actionShow_Constellation_Lines')
    this.switchRow('星座标签', this.constellationLabels, 'actionShow_Constellation_Labels')
    this.switchRow('星座边界', this.constellationBoundaries, 'actionShow_Constellation_Boundaries')
    this.switchRow('星座艺术', this.constellationArt, 'actionShow_Constellation_Art')
    this.switchRow('黄道十二宫', this.zodiac, 'actionShow_Zodiac')
    this.switchRow('月宿', this.lunarSystem, 'actionShow_LunarSystem')
    this.switchRow('星群线', this.asterismLines, 'actionShow_Asterism_Lines')
    this.switchRow('星群标签', this.asterismLabels, 'actionShow_Asterism_Labels')
    Row() {
      Text('天区文化列表（需C++桥接）').fontSize(10).fontColor('#446688FF').width('100%').padding({ left: 2 })
    }.height(18).width('100%').margin({ top: 6 })
  }

  // View 面板 Surveys 标签页内容
  @Builder viewSurveysTab() {
    this.switchRow('HiPS 巡天', this.hipsSurveys, 'actionShow_Hips_Surveys')
    this.switchRow('TOAST 巡天', this.toastSurvey, 'actionShow_Toast_Survey')
    Row() {
      Text('注意：在线巡天需要网络连接').fontSize(10).fontColor('#446688FF').width('100%').padding({ left: 2 })
    }.height(18).width('100%').margin({ top: 8 })
  }

}
