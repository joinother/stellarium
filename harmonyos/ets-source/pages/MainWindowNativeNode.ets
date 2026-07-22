import { command } from 'libentry.so'
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { geoLocationManager } from '@kit.LocationKit'
import { sensor } from '@kit.SensorServiceKit'
import hilog from '@ohos.hilog'
import { LOCATION_HIERARCHY } from './location_hierarchy'

import { ALIAS_LIST, StellariumBridgeResponse, LangOption, HierCity, CatOption, NameItem, AliasEntry, SearchSug, AliasHit, WindowNativeNodeCreateInfo, TabItem, LandscapeItem, PlanetPosition, ObjectInfo, SkyCultureItem, PluginItem, ShellAction } from './StellariumTypes'

@Entry
@Component
struct WindowNativeNode {
  @State private createInfo: WindowNativeNodeCreateInfo | undefined = undefined
  @State private isExpandedLayout: boolean = true
  @State private activePanel: string = 'object'
  @State private panelVisible: boolean = true
  @State private searchText: string = ''
  @State private selectedName: string = 'Not selected'
  @State private searchSuggestions: SearchSug[] = []
  @State private searchHistory: string[] = []
  @State private searchCategory: string = 'planet'
  @State private categoryObjects: NameItem[] = []
  @State private selectedType: string = 'Tap sky or search'
  @State private selectedStatus: string = 'Waiting'
  @State private selectedInfo: string = 'Tap a celestial object in the sky, or enter a name in search.'
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
  @State private locationPickerName: string = 'Custom location'
  @State private locationPickerLatitude: number = 39.9042
  @State private locationPickerLongitude: number = 116.4074
  @State private locationPickerAltitude: number = 44
  @State private locationPickerStatus: string = 'Drag map or use auto location'
  @State private locationPickMode: string = 'map'
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
  @State private observingList: string[] = []
  @State private stars: boolean = true
  @State private skyCultures: string[] = []
  @State private isLoading: boolean = true
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
  @State private eclipticGrid: boolean = false
  @State private meridianLine: boolean = false
  @State private horizonLine: boolean = false
  @State private planetLabels: boolean = false
  @State private starLabels: boolean = false
  @State private gyroscopeEnabled: boolean = false
  @State private gyroscopeStatus: string = 'Off'
  @State private gyroscopeSensitivityText: string = 'Standard'
  @State private liveMode: boolean = true
  @State private timeScale: string = '1x'
  @State private currentFovText: string = '--'
  @State private uiLocked: boolean = true
  @State private panelOffsetX: number = 0
  @State private panelOffsetY: number = 0
  @State private skyTouchFeedback: boolean = false
  @State private lx200Host: string = '127.0.0.1'
  @State private lx200Port: string = '4030'
  @State private lx200Status: string = 'Disconnected'
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
      { icon: 'layers', label: $r('app.string.i0273'), panel: 'config' },
      { icon: 'clock', label: $r('app.string.i0274'), panel: 'astro' },
      { icon: 'info', label: $r('app.string.i0217'), panel: 'help' }
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
    this.dsoLabels = result.actionShow_DSO_Labels === true
    this.dsoTextures = result.actionShow_DSO_Textures === true
    this.enlargePlanets = result.actionShow_Planets_EnlargePlanets === true
    this.enlargeSun = result.actionShow_Planets_EnlargeSun === true
    this.minorBodyMarkers = result.actionShow_Planets_ShowMinorBodyMarkers === true
    this.planetNomenclature = result.actionShow_Planets_Nomenclature === true
    this.fogEffect = result.actionShow_Fog === true
    this.meteors = result.actionShow_Meteors === true
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
    }
    if (result.fov !== undefined) {
      this.fovText = result.fov.toFixed(1) + '°'
    }
    if (result.tracking !== undefined) {
      this.trackingText = result.tracking ? 'On' : 'Off'
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
      }
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

  private changeLandscapeTransparency(val: number): void {
    const v = (val / 100).toFixed(2)
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
    this.flashHint((hours > 0 ? $r('app.string.i0044') : '') + hours.toString() + ' h')
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
        this.flashHint(lang === 'zh_CN' ? 'Switched to Chinese' : 'Switched to English')
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
      const target = result.target && result.target.length > 0 ? result.target : 'Selected target'
      const mode = result.mode === 'sync' ? 'Sync' : $r('app.string.i0049')
      const coord = result.ra && result.dec ? ' · ' + result.ra + ' / ' + result.dec : ''
      this.lx200Status = mode + ' sent: ' + target + coord
    } else {
      const message = result.error === 'no selected object' ? 'Please select or search a target first' : result.error
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
      this.lx200Status = result.ok === true ? 'Stop command sent' : (result.error ? result.error : 'Stop failed')
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
      this.gyroscopeStatus = 'Listening'
    } catch (error) {
      this.gyroscopeEnabled = false
      this.gyroscopeStatus = 'Unavailable'
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
      this.gyroscopeStatus = (result.ok === true || result.pending === true) ? 'Working' : (result.error ? result.error : 'Core not ready')
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
      if (this.activePanel === 'object' && this.panelVisible && this.selectedStatus === 'Selected') {
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
      'Asteroid': 'Asteroid', 'Comet': 'Comet', 'Satellite': 'Satellite', 'Moon': 'Satellite/Moon',
      'Sun': 'Star (Sun)', 'Quasar': 'Quasar', 'Pulsar': 'Pulsar', 'Cluster': $r('app.string.i0106'),
      'Open cluster': 'Open cluster', 'Globular cluster': 'Globular cluster', 'Planetary nebula': 'Planetary nebula',
      'Interstellar object': 'Interstellar object', 'Minor planet': 'Asteroid',
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
      this.selectedStatus = result.error ? result.error : 'Core not ready'
      return
    }
    if (result.found === true) {
      this.selectedName = result.name && result.name.length > 0 ? result.name : (result.englishName ? result.englishName : '已选择')
      this.selectedType = result.type && result.type.length > 0 ? result.type : 'Object'
      this.selectedStatus = 'Selected'
      this.selectedMagnitude = (typeof result.magnitude === 'number') ? (result.magnitude as number).toFixed(2) : ''
      const ra: string = result.ra ? result.ra : ''
      const dec: string = result.dec ? result.dec : ''
      this.selectedCoordEq = (ra.length > 0 || dec.length > 0) ? (ra + '  ' + dec).trim() : ''
      const hasAlt: boolean = typeof result.altitude === 'number'
      const hasAz: boolean = typeof result.azimuth === 'number'
      this.selectedCoordAlt = (hasAlt || hasAz)
        ? ('Alt ' + (hasAlt ? this.fmtDegMin(result.altitude as number) : '--') + '   Az ' + (hasAz ? this.fmtDegMin(result.azimuth as number) : '--'))
        : ''
      this.selectedConstellation = result.constellation && result.constellation.length > 0 ? result.constellation : ''
      this.selectedDistance = result.distance && result.distance.length > 0 ? result.distance : ''
      // 尝试从本地别名表补充中文简介
      const dispName = this.selectedName
      const alias = ALIAS_LIST.find(a => a.en === dispName || a.zh === dispName)
      this.selectedInfo = alias ? alias.zh + ' (' + alias.en + ')' : ''
      this.startDetailAutoRefresh()
    } else {
      this.selectedName = 'Not found'
      this.selectedType = result.query && result.query.length > 0 ? result.query : 'No selection'
      this.selectedStatus = result.query && result.query.length > 0 ? 'Try English name' : 'No match'
      this.selectedMagnitude = ''
      this.selectedCoordEq = ''
      this.selectedCoordAlt = ''
      this.selectedConstellation = ''
      this.selectedDistance = ''
      this.selectedInfo = 'No selectable object at tap position. Zoom in or use search.'
    }
  }

  private formatRate(rate: number): string {
    if (rate === 0) {
      return 'Paused'
    }
    if (Math.abs(rate - 0.000011574074074074073) < 0.0000001) {
      return '1x'
    }
    if (rate > 0) {
      return rate.toFixed(6)
    }
    return 'Paused'
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
    this.setPickerLocation('Map select', latitude, longitude, this.locationPickerAltitude, 'Map position selected, tap apply to sync')
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
    this.locationPickerStatus = 'Requesting location permission'
    try {
      const context = getContext(this) as common.UIAbilityContext
      const atManager = abilityAccessCtrl.createAtManager()
      const permissions: Array<Permissions> = [
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION'
      ]
      await atManager.requestPermissionsFromUser(context, permissions)
      this.locationPickerStatus = 'Getting current location'
      const current = await geoLocationManager.getCurrentLocation({
        priority: geoLocationManager.LocationRequestPriority.ACCURACY,
        scenario: geoLocationManager.LocationRequestScenario.DAILY_LIFE_SERVICE,
        maxAccuracy: 2000,
        timeoutMs: 5000
      })
      const altitude = Number.isFinite(current.altitude) ? current.altitude : 0
      this.setPickerLocation('Current location', current.latitude, current.longitude, altitude, 'Device location obtained, auto-synced')
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
        this.setPickerLocation('Beijing', 39.9, 116.4, 43, 'No GPS in simulator, using default (Beijing)')
        this.applyPickerLocation()
      } else {
        this.locationPickerStatus = 'GPS unavailable, keeping current position'
        this.applyPickerLocation()
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
    // Try direct C++ bridge first for known cities
    this.callInteractive('setLocationByName', name, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        // C++ resolved the location
        this.setPickerLocation(name, latitude, longitude, altitude, 'Synced to sky')
        this.locationText = name + ' · Earth'
        this.coordinateText = this.formatDegrees(latitude, 'N', 'S') + ' / ' + this.formatDegrees(longitude, 'E', 'W')
        this.altitudeText = altitude.toFixed(0) + ' m'
        this.refreshState()
        this.flashHint($r('app.string.i0073', name))
      } else {
        // Fallback to triggerAction for custom coordinates
        this.triggerAction('actionSet_Location_Country_Code')
        this.triggerAction('actionSet_Location_' + name.replace(/ /g, '_'))
        this.setPickerLocation(name, latitude, longitude, altitude, 'Synced to sky')
        this.locationText = name + ' · Earth'
        this.coordinateText = this.formatDegrees(latitude, 'N', 'S') + ' / ' + this.formatDegrees(longitude, 'E', 'W')
        this.altitudeText = altitude.toFixed(0) + ' m'
        this.refreshState()
      }
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
    // Rail always starts near top of screen (fixed position)
    return 28
  }

  private railHeight(): number {
    return this.actions.length * 58 + 20
  }

  private isUiPoint(x: number, y: number): boolean {
    if (this.isExpandedLayout) {
      // 左侧工具栏按钮区域（宽屏布局，从顶部开始排列）
      if (x >= 0 && x <= 58) {
        const railTop = 28
        const step = 58
        for (let i = 0; i < this.actions.length; i++) {
          const bTop = railTop + i * step
          if (y >= bTop && y <= bTop + 44) {
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
	    if (this.isExpandedLayout && x >= 0 && x <= 58) {
      const railTop = 28
      const step = 58
      const index = Math.floor((y - railTop) / step)
      const withinButton = index >= 0 && index < this.actions.length && y >= railTop + index * step && y <= railTop + index * step + 44
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
      this.flashHint('Touch: x=' + downX + ' y=' + downY + ' sky=' + this.skyWidth + 'x' + this.skyHeight + ' rail=' + this.railTop())
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
        // Handle sidebar button clicks since XComponent swallows onClick events
        if (downX >= 0 && downX <= 58) {
          const railTop = 28
          const step = 58
          for (let i = 0; i < this.actions.length; i++) {
            const bTop = railTop + i * step
            if (downY >= bTop && downY <= bTop + 44) {
              this.setPanel(this.actions[i].panel)
              return
            }
          }
        }
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

      // Panel drag handling
      if (this.panelDragging) {
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
      // End panel drag
      if (this.panelDragging) {
        this.panelDragging = false
        return
      }
      // If touch started on a UI element (sidebar/panel), do not trigger selectAt
      if (this.isUiPoint(x, y)) {
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
        .hitTestBehavior(HitTestMode.Block)
      Stack() { this.zoomButton('zoom_in') }
        .hitTestBehavior(HitTestMode.Block)
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
          .hitTestBehavior(HitTestMode.Block)
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
        Stack() { this.zoomButton('zoom_in') }
          .onClick(() => { this.triggerAction('actionZoom_In_Auto') })
        Stack() { this.zoomButton('zoom_out') }
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
          Text($r('app.string.i0109')).fontSize(14).fontColor('#66FFFFFF').margin({ top: 20 })
          Text($r('app.string.i0110')).fontSize(12).fontColor('#446688FF').margin({ top: 6 })
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
        Text(this.selectedStatus === 'Selected' ? this.trackingText : this.selectedStatus)
          .fontSize(11).fontColor('#66FFFFFF')
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
        Button(this.observingList.includes(this.selectedName) ? "In list" : "Add to list")
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
	      this.quickChips(['Refresh', 'Center', 'Untrack'])
      Row({ space: 6 }) {
        Button($r('app.string.i0134')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionGoto_ReSelect_Last_Selected_Object') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 4, bottom: 4 })
	      this.lx200ObjectControls()
      } // end object selectedName else
    } else if (this.activePanel === 'time') {
      this.infoRow($r('app.string.i0054'), this.observationTimeText)
      this.infoRow($r('app.string.i0055'), this.timeRateText)
      this.infoRow($r('app.string.i0056'), this.timeRateText === 'Paused' ? 'Paused' : 'Running')
      this.quickChips(['Now', 'Back', 'Pause', 'Forward'])
      this.quickChips(['+12h', '-12h'])
      // 天文事件快捷跳转
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text($r('app.string.i0111')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row({ space: 6 }) {
        Button($r('app.string.i0146')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_Rising') })
        Button($r('app.string.i0147')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_Setting') })
        Button($r('app.string.i0148')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_Transit') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button($r('app.string.i0149')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionToday_Rising') })
        Button($r('app.string.i0150')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionToday_Setting') })
        Button($r('app.string.i0151')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionToday_Transit') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button($r('app.string.i0152')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_Rising') })
        Button($r('app.string.i0153')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_Setting') })
        Button($r('app.string.i0154')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_Transit') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button($r('app.string.i0155')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_MorningTwilight') })
        Button($r('app.string.i0156')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_EveningTwilight') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button($r('app.string.i0157')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_MorningTwilight') })
        Button($r('app.string.i0158')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_EveningTwilight') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 二分二至快捷跳转
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 6, bottom: 4 })
      Row() {
        Text($r('app.string.i0112')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row({ space: 6 }) {
        Button($r('app.string.i0159')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_March_Equinox') })
        Button($r('app.string.i0160')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_June_Solstice') })
        Button($r('app.string.i0161')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_September_Equinox') })
        Button($r('app.string.i0162')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionNext_December_Solstice') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 6 }) {
        Button($r('app.string.i0163')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_March_Equinox') })
        Button($r('app.string.i0164')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_June_Solstice') })
        Button($r('app.string.i0165')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_September_Equinox') })
        Button($r('app.string.i0166')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(16).height(30).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionPrevious_December_Solstice') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 天文时间单位跳转
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.nmBorder())
        .margin({ top: 6, bottom: 4 })
      Row() {
        Text($r('app.string.i0113')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      // 恒星时间
      Row({ space: 4 }) {
        Button($r('app.string.i0173')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Sidereal_Day') })
        Button($r('app.string.i0174')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Sidereal_Day') })
        Button($r('app.string.i0175')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Sidereal_Year') })
        Button($r('app.string.i0176')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Sidereal_Year') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 月周期
      Row({ space: 4 }) {
        Button($r('app.string.i0177')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Synodic_Month') })
        Button($r('app.string.i0178')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Synodic_Month') })
        Button($r('app.string.i0179')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Saros') })
        Button($r('app.string.i0180')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Saros') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 回归年/儒略年
      Row({ space: 4 }) {
        Button($r('app.string.i0181')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Tropical_Year') })
        Button($r('app.string.i0182')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Tropical_Year') })
        Button($r('app.string.i0183')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Julian_Year') })
        Button($r('app.string.i0184')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Julian_Year') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 日历月/年
      Row({ space: 4 }) {
        Button($r('app.string.i0185')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Month') })
        Button($r('app.string.i0186')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Calendar_Month') })
        Button($r('app.string.i0187')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Year') })
        Button($r('app.string.i0188')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionSubtract_Calendar_Year') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      // 更多周期
      Row({ space: 4 }) {
        Button($r('app.string.i0189')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Anomalistic_Month') })
        Button($r('app.string.i0190')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Draconic_Month') })
        Button($r('app.string.i0191')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Metonic_Cycle') })
        Button($r('app.string.i0192')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Inex') })
      }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
      Row({ space: 4 }) {
        Button($r('app.string.i0193')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Gaussian_Year') })
        Button($r('app.string.i0194')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Decade') })
        Button($r('app.string.i0195')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
          .borderRadius(14).height(26).padding({ left: 8, right: 8 })
          .onClick(() => { this.triggerAction('actionAdd_Calendar_Century') })
        Button($r('app.string.i0196')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
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
      this.quickChips(['Beijing', '上海', '深圳'])
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
    } else if (this.activePanel === 'settings') {
      // 快捷设置面板
      Scroll() {
        Column({ space: 0 }) {
          Text($r('app.string.i0114')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          this.switchRow($r('app.string.s0300'), this.nightMode, 'actionShow_Night_Mode')
          this.switchRow($r('app.string.s0301'), this.equatorialMount, 'actionSwitch_Equatorial_Mount')
          this.switchRow($r('app.string.s0302'), this.ground, 'actionSet_Auto_zoom_out_resets_direction')
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text($r('app.string.i0115')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          this.switchRow($r('app.string.s0303'), this.gyroscopeEnabled, '')
          Row() {
            Text($r('app.string.i0230')).fontSize(12).fontColor(this.nmSub()).width(72)
            Text(this.gyroscopeSensitivityText).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Text($r('app.string.i0116')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
          this.switchRow($r('app.string.s0304'), this.liveMode, '')
          Row() {
            Text($r('app.string.i0231')).fontSize(12).fontColor(this.nmSub()).width(72)
            Text(this.timeScale).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          Row({ space: 6 }) {
            Button($r('app.string.i0142')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(14).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.triggerAction('actionDecrease_Time_Speed') })
            Button($r('app.string.i0245')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmAccent())
              .borderRadius(14).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.setTimeRate(1) })
            Button($r('app.string.i0246')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(14).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.triggerAction('actionIncrease_Time_Speed') })
          }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 6, bottom: 4 })
          Row() {
            Text('FOV').fontSize(12).fontColor(this.nmSub()).width(72)
            Text(this.currentFovText).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
            Button('Refresh').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(8).height(24).padding({ left: 8, right: 8 })
              .onClick(() => { this.loadFov() })
          }.height(34).width('100%').padding({ left: 10, right: 10 })
        }.width('100%')
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
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
      // 快选行星
      if (this.searchText.length === 0) {
        Row() {
          Text('Planets').fontSize(10).fontColor(this.nmSub()).width(52)
          Scroll() {
            Row({ space: 4 }) {
              ForEach(['Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune'], (p: string) => {
                Text(p).fontSize(11).fontColor(this.nmText()).padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(this.nmBg()).borderRadius(12)
                  .onClick(() => { this.searchText = p; this.searchObject(p) })
              })
            }.padding({ left: 2 })
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
        }.width('100%').padding({ left: 10, right: 10 }).margin({ top: 6 })
        Row() {
          Text('Stars').fontSize(10).fontColor(this.nmSub()).width(52)
          Scroll() {
            Row({ space: 4 }) {
              ForEach(['Sirius', 'Canopus', 'Arcturus', 'Vega', 'Rigel', 'Betelgeuse', 'Polaris'], (s: string) => {
                Text(s).fontSize(11).fontColor(this.nmText()).padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(this.nmBg()).borderRadius(12)
                  .onClick(() => { this.searchText = s; this.searchObject(s) })
              })
            }.padding({ left: 2 })
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
        }.width('100%').padding({ left: 10, right: 10 }).margin({ top: 4 })
      }
      // 搜索历史（无输入时显示，可点击复用）
      if (this.searchText.length === 0 && this.searchHistory.length > 0) {
        Row() {
          Text($r('app.string.i0117')).fontSize(11).fontColor(this.nmSub()).margin({ right: 8 })
          Text($r('app.string.i0118')).fontSize(11).fontColor('#4488FF').onClick(() => {
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
          { label: $r('app.string.c0000'), id: 0 },
          { label: $r('app.string.c0001'), id: 1 },
          { label: $r('app.string.c0002'), id: 2 },
          { label: $r('app.string.c0003'), id: 3 },
          { label: $r('app.string.c0004'), id: 4 },
          { label: $r('app.string.c0005'), id: 5 },
          { label: $r('app.string.c0006'), id: 6 },
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
              Text($r('app.string.i0119')).fontSize(12).fontColor(this.nmSub()).width(72)
              Text(this.currentSkyCultureId !== '' ? this.currentSkyCultureId : '加载中...').fontSize(11).fontColor(this.nmText()).layoutWeight(1)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            this.lockRow()
            this.infoRow($r('app.string.s0350'), 'Stellarium 26.2 for HarmonyOS')
          } else if (this.configTab === 1) {
            // Information
            Row() {
              Text($r('app.string.i0120')).fontSize(12).fontColor(this.nmSub()).width(72)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Row({ space: 6 }) {
              Button($r('app.string.i0247')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 0 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 0; this.triggerAction('actionDisplayInfo_All') })
              Button($r('app.string.i0248')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 1 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 1; this.triggerAction('actionDisplayInfo_Default') })
              Button($r('app.string.i0249')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 2 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 2; this.triggerAction('actionDisplayInfo_Short') })
              Button($r('app.string.i0250')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.infoLevel === 3 ? this.nmAccent() : this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.infoLevel = 3; this.triggerAction('actionDisplayInfo_None') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
          } else if (this.configTab === 2) {
            // Extras
            this.infoRow($r('app.string.s0351'), 'Stellarium for HarmonyOS')
            this.infoRow($r('app.string.s0352'), 'OpenHarmony / HarmonyOS NEXT')
          } else if (this.configTab === 3) {
            // Time
            this.infoRow($r('app.string.s0353'), '24 小时制')
            this.infoRow($r('app.string.s0354'), 'YYYY-MM-DD')
            this.infoRow($r('app.string.s0355'), '格里高利历')
            Row() {
              Text($r('app.string.i0223')).fontSize(10).fontColor('#446688FF').width('100%').padding({ left: 2 })
            }.height(18).width('100%').margin({ top: 4 })
          } else if (this.configTab === 4) {
            // Tools
            Row() {
              Text($r('app.string.i0121')).fontSize(12).fontColor(this.nmSub()).width(72)
              Button($r('app.string.i0251')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionSave_Screenshot_Global') })
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            this.infoRow($r('app.string.s0356'), 'PNG')
            this.infoRow($r('app.string.s0357'), '由 OpenGL ES 核心渲染')
          } else if (this.configTab === 5) {
            // Scripts
            Row() {
              Text($r('app.string.i0122')).fontSize(12).fontColor(this.nmSub()).width(72)
              Button($r('app.string.i0252')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(8).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionStop_Script') })
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Row() {
              Text($r('app.string.i0123')).fontSize(11).fontColor(this.nmSub()).width('100%').margin({ top: 4 })
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
            Text($r('app.string.i0124')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Button($r('app.string.i0244')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadPluginList() })
            Scroll() {
              Column({ space: 2 }) {
                ForEach(this.pluginList, (pl: PluginItem) => {
                  Row() {
                    Text(pl.name).fontSize(11).fontColor(this.nmText()).layoutWeight(1)
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
          { label: $r('app.string.a0000'), id: 0 },
          { label: $r('app.string.a0001'), id: 1 },
          { label: $r('app.string.a0002'), id: 2 },
          { label: $r('app.string.a0003'), id: 3 },
          { label: $r('app.string.a0004'), id: 4 },
          { label: $r('app.string.a0005'), id: 5 },
          { label: $r('app.string.a0006'), id: 6 },
          { label: $r('app.string.a0007'), id: 7 },
          { label: $r('app.string.a0008'), id: 8 },
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
            Text($r('app.string.i0125')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Button($r('app.string.i0241')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadPlanetPositions() })
            Row() {
              Text($r('app.string.s0374')).fontSize(10).fontColor(this.nmSub()).width(60)
              Text($r('app.string.s0375')).fontSize(10).fontColor(this.nmSub()).width(50)
              Text($r('app.string.s0376')).fontSize(10).fontColor(this.nmSub()).width(50)
              Text($r('app.string.s0377')).fontSize(10).fontColor(this.nmSub()).width(40)
            }.height(20).width('100%').padding({ left: 8, right: 8 }).margin({ top: 4, bottom: 2 })
            Scroll() {
              Column({ space: 2 }) {
                ForEach(this.planetPositions, (p: PlanetPosition) => {
                  Row() {
                    Text(p.name).fontSize(11).fontColor(this.nmText()).width(60)
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
            Text($r('app.string.i0126')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text($r('app.string.i0167')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Row({ space: 6 }) {
              Button($r('app.string.i0152')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionPrevious_Rising') })
              Button($r('app.string.i0154')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionPrevious_Transit') })
              Button($r('app.string.i0153')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionPrevious_Setting') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
            Row({ space: 6 }) {
              Button($r('app.string.i0146')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmAccent())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionNext_Rising') })
              Button($r('app.string.i0148')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmAccent())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionNext_Transit') })
              Button($r('app.string.i0147')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmAccent())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionNext_Setting') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 4 })
          } else if (this.astroTab === 2) {
            Text($r('app.string.i0127')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Button($r('app.string.i0239')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadRTS() })
            if (this.rtsData.size > 0) {
              this.infoRow($r('app.string.s0358'), this.rtsData.get('name') ?? 'N/A')
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.nmBorder())
                .margin({ top: 4, bottom: 4 })
              Text($r('app.string.s0370')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow($r('app.string.s0700'), this.jdToDateStr(this.rtsData.get('nextRiseJD') ?? '0'))
              this.infoRow($r('app.string.s0701'), this.jdToDateStr(this.rtsData.get('nextTransitJD') ?? '0'))
              this.infoRow($r('app.string.s0702'), this.jdToDateStr(this.rtsData.get('nextSetJD') ?? '0'))
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.nmBorder())
                .margin({ top: 4, bottom: 4 })
              Text($r('app.string.s0371')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow($r('app.string.s0700'), this.jdToDateStr(this.rtsData.get('prevRiseJD') ?? '0'))
              this.infoRow($r('app.string.s0701'), this.jdToDateStr(this.rtsData.get('prevTransitJD') ?? '0'))
              this.infoRow($r('app.string.s0702'), this.jdToDateStr(this.rtsData.get('prevSetJD') ?? '0'))
            }
            Row({ space: 6 }) {
              Button($r('app.string.i0146')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionNext_Rising') })
              Button($r('app.string.i0148')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionNext_Transit') })
              Button($r('app.string.i0147')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(16).height(30).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionNext_Setting') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          } else if (this.astroTab === 3) {
            Text($r('app.string.i0128')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text($r('app.string.i0168')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Row({ space: 6 }) {
              Button($r('app.string.i0253')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Next_Conjunction') })
              Button($r('app.string.i0254')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Next_Opposition') })
              Button($r('app.string.i0255')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Next_Elongation') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
            Text('Tonight').fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ top: 6, bottom: 2 })
            Row({ space: 6 }) {
              Button('Sunset+1h').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionSet_Time_1_Hour_Forward') })
              Button('Midnight').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionSet_Time_Now') })
              Button('Sunrise-1h').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionSet_Time_1_Hour_Backward') })
            }.width('100%').padding({ left: 4, right: 4 })
          } else if (this.astroTab === 4) {
            Text($r('app.string.i0129')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text($r('app.string.i0169')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Row({ space: 6 }) {
              Button($r('app.string.i0256')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_AlitudeVsTime_Graph') })
              Button($r('app.string.i0257')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_AzimuthVsTime_Graph') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          } else if (this.astroTab === 5) {
            Text($r('app.string.i0130')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text($r('app.string.i0170')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Button($r('app.string.i0242')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.triggerAction('actionShow_WUT') })
          } else if (this.astroTab === 6) {
            Text($r('app.string.i0131')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text($r('app.string.i0171')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Button($r('app.string.i0243')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
          } else if (this.astroTab === 7) {
            Text($r('app.string.i0132')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Text($r('app.string.i0172')).fontSize(10).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
            Row({ space: 6 }) {
              Button($r('app.string.i0258')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
              Button($r('app.string.i0259')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
              Button($r('app.string.i0260')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
                .borderRadius(14).height(28).padding({ left: 8, right: 8 })
                .onClick(() => { this.triggerAction('actionShow_AstroCalc_Window_Global') })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          } else {
            Text($r('app.string.i0133')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4, bottom: 8 })
            Button($r('app.string.i0240')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
              .borderRadius(16).height(30).padding({ left: 10, right: 10 })
              .onClick(() => { this.loadAlmanac() })
            if (this.almanacData.size > 0) {
              Text($r('app.string.s0372')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow($r('app.string.s0365'), this.jdToDateStr(this.almanacData.get('sunNextRise') ?? '0'))
              this.infoRow($r('app.string.s0366'), this.jdToDateStr(this.almanacData.get('sunNextSet') ?? '0'))
              this.infoRow($r('app.string.s0701'), this.jdToDateStr(this.almanacData.get('sunNextTransit') ?? '0'))
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.nmBorder())
                .margin({ top: 4, bottom: 4 })
              Text($r('app.string.s0373')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
              this.infoRow($r('app.string.s0367'), this.jdToDateStr(this.almanacData.get('moonNextRise') ?? '0'))
              this.infoRow($r('app.string.s0368'), this.jdToDateStr(this.almanacData.get('moonNextSet') ?? '0'))
              this.infoRow($r('app.string.s0701'), this.jdToDateStr(this.almanacData.get('moonNextTransit') ?? '0'))
              this.infoRow($r('app.string.s0369'), (parseFloat(this.almanacData.get('moonPhase') ?? '0') * 100).toFixed(1) + '%')
            }
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else if (this.activePanel === 'help') {
      // Help 面板
      Scroll() {
        Column({ space: 8 }) {
          Text($r('app.string.i0216')).fontSize(13).fontColor(this.nmText()).width('100%').margin({ top: 4 })
          Text($r('app.string.i0261')).fontSize(11).fontColor(this.nmSub()).width('100%')
          Text($r('app.string.i0262')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0263')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0264')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Text($r('app.string.i0217')).fontSize(13).fontColor(this.nmText()).width('100%')
          Text($r('app.string.i0265')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0266')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0267')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0268')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.nmBorder())
            .margin({ top: 8, bottom: 4 })
          Text($r('app.string.i0218')).fontSize(13).fontColor(this.nmText()).width('100%')
          Text($r('app.string.i0269')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0270')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0271')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0272')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0273')).fontSize(10).fontColor('#66FFFFFF').width('100%')
          Text($r('app.string.i0274')).fontSize(10).fontColor('#66FFFFFF').width('100%')
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
    } else {
      this.infoRow($r('app.string.i0057'), this.isExpandedLayout ? $r('app.string.s0703') : $r('app.string.s0704'))
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
          Text(this.observingList.length + ' objects').fontSize(14).fontColor("#E5FFFFFF").layoutWeight(1)
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
      this.infoRow($r('app.string.i0062'), $r('app.string.s0706'))
      // 分区：方向
      Row()
        .width('100%').height(0.5)
        .backgroundColor('rgba(255,255,255,0.06)')
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text($r('app.string.i0275')).fontSize(11).fontColor('#66FFFFFF').width('100%').padding({ left: 2 })
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
        Text($r('app.string.i0276')).fontSize(11).fontColor('#66FFFFFF').width('100%').padding({ left: 2 })
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
            Text(this.nightMode ? $r('app.string.s0707') : $r('app.string.s0708')).fontSize(12).fontColor('#E5FFFFFF').margin({ left: 4 })
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
        Text($r('app.string.i0277')).fontSize(12).fontColor('#66FFFFFF').width(72)
        Row() {
              Image($r('app.media.ic_layers')).width(14).height(14).fillColor('#E5FFFFFF')
              Text(this.flipVert ? $r('app.string.s0709') : $r('app.string.s0710')).fontSize(11).fontColor('#E5FFFFFF').margin({ left: 3 })
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
              Text(this.flipHoriz ? $r('app.string.s0711') : $r('app.string.s0712')).fontSize(11).fontColor('#E5FFFFFF').margin({ left: 3 })
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
             this.selectedLanguage === 'zh_TW' ? $r('app.string.s0713') :
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
        this.locationModeChip('map', $r('app.string.s0715'))
        this.locationModeChip('hierarchy', $r('app.string.s0716'))
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
            this.locationPickerName = value.length > 0 ? value : 'Custom'
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
          this.flashHint(value ? $r('app.string.s0717') : $r('app.string.s0718'))
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
          this.flashHint(value ? $r('app.string.s0719') : $r('app.string.s0720'))
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
    } else if (label === 'Beijing') {
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
  infoRow(label: ResourceStr, value: ResourceStr) {
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
      return $r('app.string.i0273')
    }
    if (this.activePanel === 'astro') {
      return $r('app.string.i0274')
    }
    if (this.activePanel === 'help') {
      return $r('app.string.i0217')
    }
    if (this.activePanel === 'settings') {
      return $r('app.string.i0102')
    }
    return $r('app.string.i0101')
  }

  private panelSubtitle(): string {
    return this.timeRateText
  }

  // View 面板标签页选择器
  @Builder viewTabs() {
    Row({ space: 2 }) {
      ForEach([
        { label: $r('app.string.v0000'), id: 0 },
        { label: $r('app.string.v0001'), id: 1 },
        { label: $r('app.string.v0002'), id: 2 },
        { label: $r('app.string.v0003'), id: 3 },
        { label: $r('app.string.v0004'), id: 4 },
        { label: $r('app.string.v0005'), id: 5 },
        { label: $r('app.string.v0006'), id: 6 },
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
    this.switchRow($r('app.string.s0530'), this.stars, 'actionShow_Stars')
    this.switchRow($r('app.string.s0531'), this.milkyWay, 'actionShow_MilkyWay')
    this.switchRow($r('app.string.s0532'), this.starLabels, 'actionShow_Stars_Labels')
    this.switchRow($r('app.string.s0305'), this.atmosphere, 'actionShow_Atmosphere')
    this.switchRow($r('app.string.s0306'), this.ground, 'actionShow_Ground')
    this.switchRow($r('app.string.s0307'), this.fogEffect, 'actionShow_Fog')
    this.switchRow($r('app.string.s0308'), this.meteors, 'actionShow_Meteors')
    // 银河亮度
    Row() {
      Text($r('app.string.i0212')).fontSize(12).fontColor(this.nmSub()).width(72)
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
      Text($r('app.string.i0280')).fontSize(12).fontColor(this.nmSub()).width(72)
      Button($r('app.string.i0278')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(26).padding({ left: 8, right: 8 })
        .onClick(() => { this.triggerAction('actionShow_LightPollutionReduce') })
      Button($r('app.string.i0279')).fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(26).padding({ left: 8, right: 8 })
        .onClick(() => { this.triggerAction('actionShow_LightPollutionIncrease') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    this.switchRow($r('app.string.s0300'), this.nightMode, 'actionShow_Night_Mode')
    this.switchRow($r('app.string.s0309'), this.flipHoriz, 'actionHorizontal_Flip')
    this.switchRow($r('app.string.s0310'), this.flipVert, 'actionVertical_Flip')
  }

  // View 面板 SSO 标签页内容
  @Builder viewSSOTab() {
    this.switchRow($r('app.string.s0311'), this.planets, 'actionShow_Planets')
    this.switchRow($r('app.string.s0312'), this.planetOrbits, 'actionShow_Planets_Orbits')
    this.switchRow($r('app.string.s0313'), this.planetTrails, 'actionShow_Planets_Trails')
    this.switchRow($r('app.string.s0314'), this.planetHints, 'actionShow_Planets_Hints')
    this.switchRow($r('app.string.s0315'), this.enlargeMoon, 'actionShow_Planets_EnlargeMoon')
    this.switchRow($r('app.string.s0316'), this.enlargePlanets, 'actionShow_Planets_EnlargePlanets')
    this.switchRow($r('app.string.s0317'), this.enlargeSun, 'actionShow_Planets_EnlargeSun')
    this.switchRow($r('app.string.s0318'), this.minorBodyMarkers, 'actionShow_Planets_ShowMinorBodyMarkers')
    this.switchRow($r('app.string.s0319'), this.planetNomenclature, 'actionShow_Planets_Nomenclature')
    Row() {
      Text($r('app.string.i0281')).fontSize(12).fontColor(this.nmSub()).width(72)
      Button($r('app.string.i0282')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.triggerAction('actionShow_Planets_Trails_Reset') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
  }

  // View 面板 DSO 标签页内容
  @Builder viewDSOTab() {
    this.switchRow($r('app.string.s0320'), this.nebulae, 'actionShow_Nebulas')
    this.switchRow($r('app.string.s0321'), this.dsoLabels, 'actionShow_DSO_Labels')
    this.switchRow($r('app.string.s0322'), this.dsoTextures, 'actionShow_DSO_Textures')
    Row() {
      Text($r('app.string.i0220')).fontSize(12).fontColor(this.nmSub()).width(72)
      Button($r('app.string.i0283')).fontSize(11).fontColor(this.nmText()).backgroundColor(this.nmBg())
        .borderRadius(8).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.triggerAction('actionShow_DSO_Textures_Reload') })
    }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    Row()
      .width('100%').height(0.5)
      .backgroundColor(this.nmBorder())
      .margin({ top: 6, bottom: 4 })
    Row() {
            Text($r('app.string.i0214')).fontSize(10).fontColor('#446688FF').width('100%').padding({ left: 2 })
    }
    .height(18).width('100%')
    Row({ space: 12 }) {
      Text('Total: ' + this.dsoTotalCount).fontSize(10).fontColor(this.nmSub())
      Text('G: ' + this.dsoGalaxies).fontSize(10).fontColor(this.nmSub())
      Text('C: ' + this.dsoClusters).fontSize(10).fontColor(this.nmSub())
      Text('N: ' + this.dsoNebulae).fontSize(10).fontColor(this.nmSub())
    }.height(22).width('100%').padding({ left: 10, right: 10 }).margin({ top: 4 })
    Button('Refresh counts').fontSize(10).fontColor(this.nmText()).backgroundColor(this.nmBg())
      .borderRadius(8).height(26).padding({ left: 10, right: 10 })
      .onClick(() => { this.loadDSOCounts() })
  }

  // View 面板 Markings 标签页内容
  @Builder viewMarkingsTab() {
    Scroll() {
      Column({ space: 0 }) {
        // 基础网格
        Text($r('app.string.i0197')).fontSize(11).fontColor(this.nmSub()).width('100%').margin({ top: 4, bottom: 2 }).padding({ left: 2 })
        this.switchRow($r('app.string.s0323'), this.equatorialGrid, 'actionShow_Equatorial_Grid')
        this.switchRow($r('app.string.s0324'), this.azimuthGrid, 'actionShow_Azimuthal_Grid')
        // 特殊线
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text($r('app.string.i0198')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow($r('app.string.s0325'), this.equatorLine, 'actionShow_Equator_Line')
        this.switchRow($r('app.string.s0326'), this.eclipticLine, 'actionShow_Ecliptic_Line')
        this.switchRow($r('app.string.s0327'), this.meridianLine, 'actionShow_Meridian_Line')
        this.switchRow($r('app.string.s0328'), this.horizonLine, 'actionShow_Horizon_Line')
        this.switchRow($r('app.string.s0329'), this.galacticEquator, 'actionShow_Galactic_Equator_Line')
        this.switchRow($r('app.string.s0330'), this.supergalacticEq, 'actionShow_Supergalactic_Equator_Line')
        this.switchRow($r('app.string.s0331'), this.galacticGrid, 'actionShow_Galactic_Grid')
        // J2000 线
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text($r('app.string.i0199')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow($r('app.string.s0332'), this.equJ2000Line, 'actionShow_Equator_J2000_Line')
        this.switchRow($r('app.string.s0333'), this.eclJ2000Line, 'actionShow_Ecliptic_J2000_Line')
        // 点标记
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text($r('app.string.i0200')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow($r('app.string.s0334'), this.celestialPoles, 'actionShow_Celestial_Poles')
        this.switchRow($r('app.string.s0335'), this.eclipticPoles, 'actionShow_Ecliptic_Poles')
        this.switchRow($r('app.string.s0336'), this.galacticPoles, 'actionShow_Galactic_Poles')
        this.switchRow($r('app.string.s0337'), this.equinoxPoints, 'actionShow_Equinox_Points')
        this.switchRow($r('app.string.s0338'), this.solsticePoints, 'actionShow_Solstice_Points')
        this.switchRow($r('app.string.s0339'), this.antisolarPoint, 'actionShow_Antisolar_Point')
        this.switchRow($r('app.string.s0340'), this.umbraCircle, 'actionShow_Umbra_Circle')
        this.switchRow($r('app.string.s0341'), this.penumbraCircle, 'actionShow_Penumbra_Circle')
        // 辅助标记
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text($r('app.string.i0284')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow($r('app.string.s0342'), this.compassMarks, 'actionShow_Compass_Marks')
        this.switchRow($r('app.string.s0343'), this.fovMarker, 'actionShow_FOV_Center_Marker')
        this.switchRow($r('app.string.s0344'), this.intercardinalPts, 'actionShow_Intercardinal_Points')
        // 更多标记线
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text($r('app.string.i0285')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow($r('app.string.s0345'), this.primeVerticalLine, 'actionShow_Prime_Vertical_Line')
        this.switchRow($r('app.string.s0346'), this.currentVerticalLine, 'actionShow_Current_Vertical_Line')
        this.switchRow($r('app.string.s0347'), this.colureLines, 'actionShow_Colure_Lines')
        this.switchRow($r('app.string.s0348'), this.precessionCircles, 'actionShow_Precession_Circles')
        this.switchRow($r('app.string.s0500'), this.circumpolarCircles, 'actionShow_Circumpolar_Circles')
        this.switchRow($r('app.string.s0501'), this.invariantPlaneLine, 'actionShow_Invariable_Plane_Line')
        this.switchRow($r('app.string.s0502'), this.solarEquatorLine, 'actionShow_Solar_Equator_Line')
        // 更多网格
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text($r('app.string.i0286')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow($r('app.string.s0503'), this.equatorialJ2000Grid, 'actionShow_Equatorial_J2000_Grid')
        this.switchRow($r('app.string.s0504'), this.eclipticJ2000Grid, 'actionShow_Ecliptic_J2000_Grid')
        this.switchRow($r('app.string.s0505'), this.eclipticGrid, 'actionShow_Ecliptic_Grid')
        this.switchRow($r('app.string.s0506'), this.supergalacticGrid, 'actionShow_Supergalactic_Grid')
        this.switchRow($r('app.string.s0507'), this.fixedEquatorialGrid, 'actionShow_Fixed_Equatorial_Grid')
        this.switchRow($r('app.string.s0508'), this.fixedEquatorLine, 'actionShow_Fixed_Equator_Line')
        // 更多点标记
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.nmBorder())
          .margin({ top: 6, bottom: 4 })
        Text($r('app.string.i0287')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
          .height(18).width('100%')
        this.switchRow($r('app.string.s0509'), this.zenithNadir, 'actionShow_Zenith_Nadir')
        this.switchRow($r('app.string.s0510'), this.eclipticJ2000Poles, 'actionShow_Celestial_J2000_Poles')
        this.switchRow($r('app.string.s0511'), this.eclipticJ2000Poles, 'actionShow_Ecliptic_J2000_Poles')
        this.switchRow($r('app.string.s0512'), this.equinoxJ2000Pts, 'actionShow_Equinox_J2000_Points')
        this.switchRow($r('app.string.s0513'), this.solsticeJ2000Pts, 'actionShow_Solstice_J2000_Points')
        this.switchRow($r('app.string.s0514'), this.galacticCenter, 'actionShow_Galactic_Center')
        this.switchRow($r('app.string.s0515'), this.supergalacticPoles, 'actionShow_Supergalactic_Poles')
        this.switchRow($r('app.string.s0516'), this.apexPoints, 'actionShow_Apex_Points')
        this.switchRow($r('app.string.s0517'), this.umbraCenter, 'actionShow_Umbra_Center_Point')
        this.switchRow($r('app.string.s0518'), this.longitudeLine, 'actionShow_Longitude_Line')
        this.switchRow($r('app.string.s0519'), this.quadratureLine, 'actionShow_Quadrature_Line')

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
    this.switchRow($r('app.string.s0306'), this.ground, 'actionShow_Ground')
    this.switchRow($r('app.string.s0520'), this.landscapeIllum, 'actionShow_LandscapeIllumination')
    this.switchRow($r('app.string.s0521'), this.landscapeLabels, 'actionShow_LandscapeLabels')
    this.switchRow($r('app.string.s0307'), this.fogEffect, 'actionShow_Fog')
    Row() {
      Text($r('app.string.i0288')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
    }.height(18).width('100%').margin({ top: 6 })
    Scroll() {
      Column({ space: 2 }) {
        ForEach(this.landscapeList, (item: LandscapeItem) => {
          Row() {
            Text(item.name).fontSize(11)
              .fontColor(this.currentLandscapeId === item.id ? this.nmAccent() : this.nmText())
              .layoutWeight(1)
            if (this.currentLandscapeId === item.id) {
              Text($r('app.string.s0602')).fontSize(9).fontColor(this.nmAccent()).margin({ right: 8 })
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
      Text($r('app.string.i0289')).fontSize(12).fontColor(this.nmSub()).width(72)
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
    this.switchRow($r('app.string.s0522'), this.constellationLines, 'actionShow_Constellation_Lines')
    this.switchRow($r('app.string.s0523'), this.constellationLabels, 'actionShow_Constellation_Labels')
    this.switchRow($r('app.string.s0524'), this.constellationBoundaries, 'actionShow_Constellation_Boundaries')
    this.switchRow($r('app.string.s0525'), this.constellationArt, 'actionShow_Constellation_Art')
    this.switchRow($r('app.string.s0526'), this.zodiac, 'actionShow_Zodiac')
    this.switchRow($r('app.string.s0527'), this.lunarSystem, 'actionShow_LunarSystem')
    this.switchRow($r('app.string.s0528'), this.asterismLines, 'actionShow_Asterism_Lines')
    this.switchRow($r('app.string.s0529'), this.asterismLabels, 'actionShow_Asterism_Labels')
    Row()
      .width('100%').height(0.5)
      .backgroundColor(this.nmBorder())
      .margin({ top: 6, bottom: 4 })
    Row() {
      Text($r('app.string.i0213')).fontSize(11).fontColor(this.nmSub()).width('100%').padding({ left: 2 })
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
    this.switchRow($r('app.string.s0600'), this.hipsSurveys, 'actionShow_Hips_Surveys')
    this.switchRow($r('app.string.s0601'), this.toastSurvey, 'actionShow_Toast_Survey')
    Row() {
      Text($r('app.string.i0215')).fontSize(10).fontColor('#446688FF').width('100%').padding({ left: 2 })
    }.height(18).width('100%').margin({ top: 8 })
  }

}
