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
  label: string
}

interface NameItem {
  name: string
}

interface WindowNativeNodeCreateInfo {
  xComponentId: string
  onAppear: () => void
  onAttach: () => void
  onDisAppear: () => void
}

interface ShellAction {
  label: string
  icon: string
  panel: string
}

interface StellariumBridgeResponse {
  ok?: boolean
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
  @State private searchSuggestions: string[] = []
  @State private searchCategory: string = 'planet'
  @State private categoryObjects: NameItem[] = []
  @State private selectedType: string = '轻点天体或搜索'
  @State private selectedStatus: string = '等待选择'
  @State private selectedInfo: string = '轻点星图中的天体，或在搜索里输入名称。'
  @State private timeRateText: string = '1x'
  @State private manualYear: number = 2026
  @State private manualMonth: number = 7
  @State private manualDay: number = 20
  @State private manualHour: number = 23
  @State private manualMinute: number = 0
  @State private selectedLanguage: string = 'zh_CN'
  @State private equatorialMount: boolean = false
  @State private nightMode: boolean = false
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
  @State private currentSkyCulture: string = ""
  @State private planets: boolean = true
  @State private planetOrbits: boolean = false
  @State private planetHints: boolean = false
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
  @State private actionHint: string = ''

  private hintTimer: number = 0
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
    { label: '搜索', icon: '搜', panel: 'search' },
    { label: '时间', icon: '时', panel: 'time' },
    { label: '位置', icon: '位', panel: 'place' },
    { label: '图层', icon: '层', panel: 'layers' },
    { label: '详情', icon: '详', panel: 'object' },
    { label: '设置', icon: '设', panel: 'settings' }
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
    const cultureResult = this.callNative("getSkyCultures", "")
    if (cultureResult.ok === true && Array.isArray(cultureResult.items)) {
      this.skyCultures = cultureResult.items as string[]
      this.currentSkyCulture = cultureResult.current as string
    }
  }

  aboutToDisappear(): void {
    this.stopGyroscope(false)
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

  private refreshState(): void {
    const result = this.callNative('getState')
    if (result.ok !== true) {
      return
    }
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
  }

  private setLayer(actionId: string, enabled: boolean): void {
    const result = this.callNative('setActionChecked', actionId + '|' + (enabled ? '1' : '0'))
    if (result.ok === true) {
      this.refreshState()
    }
  }

  private triggerAction(actionId: string): void {
    const result = this.callNative('triggerAction', actionId)
    if (result.ok === true) {
      this.refreshState()
    }
  }

  private fetchSuggestions(prefix: string): void {
    if (prefix.length < 1) { this.searchSuggestions = []; return }
    const result = this.callNative('listMatchingObjects', prefix + '|10')
    if (result.ok === true && Array.isArray(result.items)) {
      this.searchSuggestions = result.items as string[]
    }
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
    const result = this.callNative('listObjects', moduleId)
    if (result.ok === true && Array.isArray(result.items)) {
      const items = result.items as string[]
      this.categoryObjects = []
      for (let i = 0; i < Math.min(items.length, 20); i++) {
        this.categoryObjects.push({ name: items[i] })
      }
    }
  }

  private stopTracking(): void {
    const result = this.callNative('setTracking', '0')
    if (result.ok === true) { this.trackingText = '关闭' }
  }

  private setSkyCulture(name: string): void {
    const result = this.callNative("setSkyCulture", name)
    if (result.ok === true) {
      this.currentSkyCulture = name
      this.flashHint("星图文化: " + name)
    }
  }

  private setTimeRate(rate: number): void {
    const result = this.callNative('setTimeRate', rate.toString())
    if (result.ok === true && result.timeRate !== undefined) {
      this.timeRateText = this.formatRate(result.timeRate)
    }
  }

  private zoomStep(factor: number): void {
    const result = this.callNative('zoomStep', factor.toString())
    if (result.ok === true) {
      this.refreshState()
    }
  }

  private advanceTime(hours: number): void {
    const result = this.callNative('advanceTime', hours.toString())
    if (result.ok === true) {
      this.refreshState()
    }
    this.flashHint((hours > 0 ? '+' : '') + hours.toString() + ' 小时')
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
    const result = this.callNative('setJD', jd.toFixed(6))
    if (result.ok === true) {
      this.refreshState()
      this.flashHint('已设定为 ' + this.manualYear + '-' + String(this.manualMonth).padStart(2, '0') + '-' + String(this.manualDay).padStart(2, '0') + ' ' + String(this.manualHour).padStart(2, '0') + ':' + String(this.manualMinute).padStart(2, '0'))
    }
  }

  private setLanguage(lang: string): void {
    const result = this.callNative('setLanguage', lang)
    if (result.ok === true) {
      this.selectedLanguage = lang
      this.flashHint(lang === 'zh_CN' ? '已切换为中文' : 'Switched to English')
      this.refreshState()
    }
  }

  private syncManualTimeFromState(): void {
    const result = this.callNative('getState', '')
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
  }

  private flashHint(text: string): void {
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
      const mode = result.mode === 'sync' ? '同步' : 'GoTo'
      const coord = result.ra && result.dec ? ' · ' + result.ra + ' / ' + result.dec : ''
      this.lx200Status = mode + ' 已发送：' + target + coord
    } else {
      const message = result.error === 'no selected object' ? '请先点选或搜索一个目标' : result.error
      this.lx200Status = message ? message : 'LX200 命令失败'
    }
  }

  private lx200GotoSelected(): void {
    this.applyLx200Result(this.callNative('telescopeLx200GotoSelected', this.lx200Payload()))
  }

  private lx200SyncSelected(): void {
    this.applyLx200Result(this.callNative('telescopeLx200SyncSelected', this.lx200Payload()))
  }

  private lx200Abort(): void {
    const result = this.callNative('telescopeLx200Abort', this.lx200Payload())
    this.lx200Status = result.ok === true ? '已发送停止指令' : (result.error ? result.error : '停止失败')
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
    const result = this.callNative('panBy', clampedDx.toString() + '|' + clampedDy.toString() + '|' + this.skyWidth.toString() + '|' + this.skyHeight.toString())
    this.gyroEventCount += 1
    if (this.gyroEventCount % 12 === 0) {
      this.gyroscopeStatus = result.ok === true ? '工作中' : (result.error ? result.error : 'Core 未就绪')
    }
  }

  private searchObject(name: string): void {
    const query = name.trim()
    if (query.length === 0) {
      return
    }
    const result = this.callNative('searchObject', query)
    this.applySelectedObject(result)
    this.activePanel = 'object'
    this.panelVisible = true
    if (result.ok === true) {
      this.flashHint('已找到: ' + query)
    } else {
      this.flashHint('搜索: ' + query)
    }
  }

  private refreshSelectedObject(): void {
    this.applySelectedObject(this.callNative('getSelectedObjectInfo'))
  }

  private moveToSelectedObject(): void {
    this.applySelectedObject(this.callNative('moveToSelected'))
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
      this.selectedInfo = result.info && result.info.length > 0 ? result.info : '已选中目标，Core 暂未返回更多说明。'
    } else {
      this.selectedName = '未找到'
      this.selectedType = result.query && result.query.length > 0 ? result.query : '无选中对象'
      this.selectedStatus = result.query && result.query.length > 0 ? '可尝试英文名' : '未命中'
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
      this.locationPickerStatus = '定位不可用，可拖动地图手动选择'
      hilog.warn(0x0000, 'StellariumArkUI', 'device location failed')
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
    const result = this.callNative('setLocation', name + '|' + latitude.toString() + '|' + longitude.toString() + '|' + altitude.toString())
    if (result.ok === true) {
      this.setPickerLocation(name, latitude, longitude, altitude, '已同步到星图')
      this.locationText = name + ' · Earth'
      this.coordinateText = this.formatDegrees(latitude, 'N', 'S') + ' / ' + this.formatDegrees(longitude, 'E', 'W')
      this.altitudeText = altitude.toFixed(0) + ' m'
      this.refreshState()
      this.flashHint('位置：' + name)
    }
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
      .fontColor(this.locationPickMode === mode ? '#FFFFFFFF' : '#99FFFFFF')
      .backgroundColor(this.locationPickMode === mode ? '#5B93BF' : 'rgba(255, 255, 255, 0.06)')
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
                .fontColor(selected === item ? '#FFFFFFFF' : '#99FFFFFF')
                .backgroundColor(selected === item ? '#5B93BF' : '#16223C')
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

    if (this.activePanel === 'layers') {
      const actions: string[] = [
        'actionShow_Stars',
        'actionShow_Planets',
        'actionShow_Nebulas',
        'actionShow_MilkyWay',
        'actionShow_Ground',
        'actionShow_Constellation_Lines',
        'actionShow_Constellation_Labels',
        'actionShow_Constellation_Boundaries',
        'actionShow_Constellation_Art',
        'actionShow_Atmosphere',
        'actionShow_Cardinal_Points',
        'actionShow_Azimuthal_Grid',
        'actionShow_Equatorial_Grid',
        'actionShow_Equatorial_J2000_Grid',
        'actionShow_Ecliptic_Grid',
        'actionShow_Meridian_Line',
        'actionShow_Horizon_Line',
        'actionShow_Planets_Labels',
        'actionShow_Planets_Orbits',
        'actionShow_Planets_Hints',
        'actionShow_Stars_Labels'
      ]
      const values: boolean[] = [
        this.stars,
        this.planets,
        this.nebulae,
        this.milkyWay,
        this.ground,
        this.constellationLines,
        this.constellationLabels,
        this.constellationBoundaries,
        this.constellationArt,
        this.atmosphere,
        this.cardinalPoints,
        this.azimuthGrid,
        this.equatorialGrid,
        this.equatorialJ2000Grid,
        this.eclipticGrid,
        this.meridianLine,
        this.horizonLine,
        this.planetLabels,
        this.planetOrbits,
        this.planetHints,
        this.starLabels
      ]
      // 实测每行中心 y(vp)=356+i*48, 行高约 48vp
      const row = Math.floor((y - 332) / 48)
      if (row >= 0 && row < actions.length && y >= 332 + row * 48 && y <= 380 + row * 48) {
        this.setLayer(actions[row], !values[row])
        return true
      }
    }

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
        if (x >= 1225 && x <= 1310) { const result = this.callNative('setTracking', '0'); if (result.ok === true) { this.refreshState() } return true }
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
        const result = this.callNative('selectAt', payload)
        hilog.info(0x0000, 'StellariumArkUI', 'selectAt result: ' + JSON.stringify(result))
        this.applySelectedObject(result)
        if (result.found === true) {
          this.flashHint('已选中 ' + this.selectedName)
        } else {
          this.flashHint('这里没有天体')
        }
        this.activePanel = 'object'
        this.panelVisible = true
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
          .backgroundColor('rgba(107, 163, 214, 0.12)')
          .border({ width: 1, color: 'rgba(107, 163, 214, 0.10)' })
          .shadow({ radius: 42, color: 'rgba(107, 163, 214, 0.18)', offsetX: 0, offsetY: 0 })
          .align(Alignment.Center)
          .hitTestBehavior(HitTestMode.None)
          .zIndex(4)
          .animation({ duration: 180, curve: Curve.EaseOut })
      }

        this.expandedShell()
    }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .onAreaChange((oldArea: Area, newArea: Area) => {
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
      Stack() { this.zoomButton('+') }
        .position({ x: 92, y: this.skyHeight - 220 })
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.zoomStep(0.5)
          this.flashHint('放大视野')
        })
      Stack() { this.zoomButton('\u2212') }
        .position({ x: 92, y: this.skyHeight - 150 })
        .onClick(() => {
          this.zoomStep(2.0)
          this.flashHint('缩小视野')
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
      .onTouch((event: TouchEvent) => {
        this.handleSkyTouch(event)
      })
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
      Text('LIVE')
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
  zoomButton(label: string) {
    Stack() {
      Text(label)
        .fontSize(30)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E5FFFFFF')
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
          .position({ x: 7, y: idx * 104 })
          .onClick(() => {
            this.setPanel(item.panel)
            this.flashHint('打开' + item.label + '面板')
          })
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

  @Builder
  iconButton(item: ShellAction) {
    Column() {
      Text(item.icon)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.activePanel === item.panel && this.panelVisible ? '#5B93BF' : '#E5FFFFFF')
        .lineHeight(44)
        .textAlign(TextAlign.Center)
        .width('100%')
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
        this.flashHint('打开' + item.label + '面板')
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
  smallRoundButton(label: string, action: () => void) {
    Row() {
      Text(label)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#99FFFFFF')
    }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('rgba(255, 255, 255, 0.06)')
      .border({ width: 1, color: 'rgba(255, 255, 255, 0.06)' })
      .borderRadius(18)
      .onClick(action)
  }

  @Builder
  panelContent() {
    if (this.activePanel === 'object') {
      // 名称/类型/状态/追踪需要直接绑定 @State，避免 @Builder 参数按值捕获导致不刷新
      Row() {
        Text('名称').fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.selectedName).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).backgroundColor('rgba(255, 255, 255, 0.04)').borderRadius(12).margin({ bottom: 4 })
      Row() {
        Text('类型').fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.selectedType).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).backgroundColor('rgba(255, 255, 255, 0.04)').borderRadius(12).margin({ bottom: 4 })
      Row() {
        Text('状态').fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.selectedStatus).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).backgroundColor('rgba(255, 255, 255, 0.04)').borderRadius(12).margin({ bottom: 4 })
      Row() {
        Text('追踪').fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.trackingText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).backgroundColor('rgba(255, 255, 255, 0.04)').borderRadius(12).margin({ bottom: 4 })
      Text(this.selectedInfo)
        .fontSize(12)
        .fontColor('#99FFFFFF')
        .lineHeight(18)
        .width('100%')
        .maxLines(8)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 10, right: 10, top: 9, bottom: 9 })
        .backgroundColor('rgba(107, 163, 214, 0.12)')
        .border({ width: 1, color: 'rgba(107, 163, 214, 0.20)' })
        .borderRadius(14)
        .margin({ top: 8, bottom: 8 })
      Row() {
        Button(this.observingList.includes(this.selectedName) ? "已从列表" : "加入观测列表")
          .fontSize(13).fontColor("#E5FFFFFF").backgroundColor("rgba(107,163,214,0.25)")
          .borderRadius(12).height(36).layoutWeight(1)
          .onClick(() => {
            const idx = this.observingList.indexOf(this.selectedName)
            if (idx >= 0) {
              this.observingList.splice(idx, 1)
              this.flashHint("已从观测列表移除")
            } else {
              this.observingList.push(this.selectedName)
              this.flashHint("已加入观测列表")
            }
            AppStorage.setOrCreate("observingList", JSON.stringify(this.observingList))
          })
      }
      .width("100%").margin({ top: 4, bottom: 4 })
	      this.quickChips(['刷新', '居中', '取消追踪'])
	      this.lx200ObjectControls()
    } else if (this.activePanel === 'time') {
      this.infoRow('时间', this.observationTimeText)
      this.infoRow('速度', this.timeRateText)
      this.infoRow('模式', this.timeRateText === '暂停' ? '暂停' : '运行')
      this.quickChips(['现在', '后退', '暂停', '前进'])
      this.quickChips(['+12h', '-12h'])
      // 滚动选择日期
      Row() {
        Text('选择日期').fontSize(13).fontColor('#66FFFFFF').width(72)
        Button(this.manualYear + '年' + this.manualMonth + '月' + this.manualDay + '日')
          .fontSize(14).fontColor('#E5FFFFFF').backgroundColor('rgba(255,255,255,0.08)')
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
        Text('选择时间').fontSize(13).fontColor('#66FFFFFF').width(72)
        Button(String(this.manualHour).padStart(2, '0') + ':' + String(this.manualMinute).padStart(2, '0'))
          .fontSize(14).fontColor('#E5FFFFFF').backgroundColor('rgba(255,255,255,0.08)')
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
      Button('应用设定时间')
        .fontSize(14).fontColor('#FFFFFFFF').backgroundColor('#5B93BF')
        .borderRadius(12).height(40).width('100%').margin({ top: 4 })
        .onClick(() => { this.applyManualTime() })
      Button('同步星图当前时间')
        .fontSize(13).fontColor('#66FFFFFF').backgroundColor('rgba(255,255,255,0.06)')
        .borderRadius(8).height(36).width('100%').margin({ top: 2 })
        .onClick(() => {
          this.syncManualTimeFromState()
          this.flashHint('已从星图同步时间')
        })

	    } else if (this.activePanel === 'place') {
      Row() {
        Text('位置').fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.locationText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).backgroundColor('rgba(255, 255, 255, 0.04)').borderRadius(12).margin({ bottom: 4 })
      Row() {
        Text('坐标').fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.coordinateText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).backgroundColor('rgba(255, 255, 255, 0.04)').borderRadius(12).margin({ bottom: 4 })
      Row() {
        Text('海拔').fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.altitudeText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).backgroundColor('rgba(255, 255, 255, 0.04)').borderRadius(12).margin({ bottom: 4 })
      this.locationPickerPanel()
      this.quickChips(['北京', '上海', '深圳'])
	    } else if (this.activePanel === 'layers') {
      this.switchRow('恒星', this.stars, 'actionShow_Stars')
      this.switchRow('行星', this.planets, 'actionShow_Planets')
      this.switchRow('星云', this.nebulae, 'actionShow_Nebulas')
      this.switchRow('银河', this.milkyWay, 'actionShow_MilkyWay')
      this.switchRow('地面', this.ground, 'actionShow_Ground')
      this.switchRow('星座线', this.constellationLines, 'actionShow_Constellation_Lines')
      // 搜索建议列表（输入时自动补全）
      if (this.searchSuggestions.length > 0) {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.searchSuggestions, (name: string) => {
              Text(name)
                .fontSize(12).fontColor('#E5FFFFFF')
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor('rgba(107,163,214,0.20)')
                .borderRadius(8)
                .onClick(() => {
                  this.searchObject(name)
                  this.searchSuggestions = []
                })
            }, (name: string) => name)
          }.padding({ left: 4, right: 4 })
        }.width('100%').height(36).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      this.switchRow('子午线', this.meridianLine, 'actionShow_Meridian_Line')
      this.switchRow('地平线', this.horizonLine, 'actionShow_Horizon_Line')
      this.switchRow('行星名', this.planetLabels, 'actionShow_Planets_Labels')
      this.switchRow('行星轨道', this.planetOrbits, 'actionShow_Planets_Orbits')
      this.switchRow('行星标记', this.planetHints, 'actionShow_Planets_Hints')
      this.switchRow('恒星名', this.starLabels, 'actionShow_Stars_Labels')
    } else if (this.activePanel === 'search') {
      TextInput({ text: this.searchText, placeholder: '搜索天体名称' })
        .height(44)
        .fontSize(15)
        .fontColor('#E5FFFFFF')
        .placeholderColor('#8EA0BD')
        .backgroundColor('rgba(255, 255, 255, 0.12)')
        .border({ width: 1, color: 'rgba(214, 238, 255, 0.16)' })
        .borderRadius(22)
        .onChange((value: string) => {
          this.searchText = value
          this.fetchSuggestions(value)
        })
        .onSubmit(() => {
          this.searchObject(this.searchText)
        })
      // 搜索建议列表（输入时自动补全）
      if (this.searchSuggestions.length > 0) {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.searchSuggestions, (name: string) => {
              Text(name)
                .fontSize(12).fontColor('#E5FFFFFF')
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor('rgba(107,163,214,0.20)')
                .borderRadius(8)
                .onClick(() => {
                  this.searchObject(name)
                  this.searchSuggestions = []
                })
            }, (name: string) => name)
          }.padding({ left: 4, right: 4 })
        }.width('100%').height(36).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      // 天体分类浏览（按分类 tab 切换，点击加载该分类天体列表）
      Row() {
        Text('天体分类').fontSize(12).fontColor('#66FFFFFF').width(72)
        Row({ space: 4 }) {
          ForEach([
            { code: 'planet', label: '行星' },
            { code: 'star', label: '恒星' },
            { code: 'galaxy', label: '星系' },
            { code: 'cluster', label: '星团' },
            { code: 'nebula', label: '星云' },
            { code: 'messier', label: 'M天体' },
          ] as CatOption[], (cat: CatOption) => {
            Text(cat.label)
              .fontSize(11).fontColor(this.searchCategory === cat.code ? '#FFFFFFFF' : '#99FFFFFF')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.searchCategory === cat.code ? 'rgba(107,163,214,0.35)' : 'rgba(255,255,255,0.05)')
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
            { name: 'Moon' } as NameItem, { name: 'Mars' } as NameItem, { name: 'Jupiter' } as NameItem, { name: 'Saturn' } as NameItem,
            { name: 'Sirius' } as NameItem, { name: 'Vega' } as NameItem, { name: 'Betelgeuse' } as NameItem, { name: 'Polaris' } as NameItem,
            { name: 'M31' } as NameItem, { name: 'M42' } as NameItem, { name: 'M45' } as NameItem, { name: 'M13' } as NameItem,
            { name: 'M8' } as NameItem, { name: 'NGC 7000' } as NameItem, { name: 'Double Cluster' } as NameItem,
          ] as NameItem[], (item: NameItem) => {
            Text(item.name ?? '')
              .fontSize(11).fontColor('#E5FFFFFF')
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor('rgba(107,163,214,0.20)')
              .borderRadius(8)
              .onClick(() => this.searchObject(item.name ?? ''))
          }, (item: NameItem) => item.name)
        }.padding({ left: 4, right: 4 })
      }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    } else {
      this.infoRow('显示', this.isExpandedLayout ? '宽屏布局' : '触屏布局')
      this.infoRow('渲染', 'Stellarium Core')
      this.infoRow('视场', this.fovText)
      this.infoRow('陀螺仪', this.gyroscopeStatus)
      this.infoRow('灵敏度', this.gyroscopeSensitivityText)
      this.gyroscopeRow()
      this.lx200Panel()
      this.languageRow()
      this.lockRow()
      // 观测列表
      if (this.observingList.length > 0) {
        Row() {
          Text("观测列表").fontSize(12).fontColor("#66FFFFFF").width(72)
          Text(this.observingList.length + " 个天体").fontSize(14).fontColor("#E5FFFFFF").layoutWeight(1)
        }
        .height(34).width("100%").padding({ left: 10, right: 10 }).backgroundColor("rgba(255, 255, 255, 0.04)").borderRadius(12).margin({ bottom: 4 })
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.observingList, (name: string) => {
              Text(name)
                .fontSize(11).fontColor("#E5FFFFFF")
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor("rgba(107,163,214,0.20)")
                .borderRadius(8)
                .onClick(() => {
                  this.searchObject(name)
                  this.flashHint("正在导航到 " + name)
                })
            }, (name: string) => name)
          }.padding({ left: 4, right: 4 })
        }.width("100%").height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      this.infoRow('封装', '单 HAP')
      // 方向快捷查看
      Row() {
        Text('方向查看').fontSize(12).fontColor('#66FFFFFF').width(72)
      }
      .height(6).width('100%').margin({ top: 2 })
      Row() {
        this.quickChips(['东', '南', '西', '北', '天顶', '北天极'])
      }
      .width('100%')
      // FOV 快捷切换
      Row() {
        Text('视场角').fontSize(12).fontColor('#66FFFFFF').width(72)
      }
      .height(6).width('100%').margin({ top: 2 })
      Row() {
        this.quickChips(['1°', '2°', '5°', '10°', '20°', '45°', '60°', '90°', '180°'])
      }
      .width('100%')
      // 天球投影切换
      Row() {
        Text('坐标模式').fontSize(12).fontColor('#66FFFFFF').width(72)
        Text(this.equatorialMount ? '赤道坐标' : '地平坐标')
          .fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.equatorialMount })
          .onChange((isOn: boolean) => {
            this.equatorialMount = isOn
            this.triggerAction('actionSwitch_Equatorial_Mount')
            this.refreshState()
            this.flashHint(isOn ? '赤道坐标' : '地平坐标')
          })
      }
      .height(40).width('100%').padding({ left: 10, right: 10 }).backgroundColor('rgba(255, 255, 255, 0.04)').borderRadius(12).margin({ top: 4, bottom: 4 })
      // 截图+夜间模式
      Row() {
        Button('截图保存')
          .fontSize(13).fontColor('#E5FFFFFF').backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(12).height(36).layoutWeight(1)
          .onClick(() => {
            const result = this.callNative('saveScreenShot', '')
            if (result.ok === true) { this.flashHint('截图已保存') }
          })
        Button(this.nightMode ? '🌙 夜间模式' : '☀️ 日间模式')
          .fontSize(13).fontColor('#E5FFFFFF').backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(12).height(36).layoutWeight(1).margin({ left: 8 })
          .onClick(() => {
            this.nightMode = !this.nightMode
            this.triggerAction('actionShow_Night_Mode')
            this.flashHint(this.nightMode ? '夜间模式' : '日间模式')
          })
      }
      .width('100%').margin({ top: 4, bottom: 4 })
      this.quickChips(['刷新', '现在'])
      // 帮助说明
      Row() {
        Text("手势操作").fontSize(12).fontColor("#66FFFFFF").width(72)
      }
      .height(6).width("100%").margin({ top: 2 })
      Text("单指拖动: 旋转星空  双指捏合: 缩放视场  单击: 选星  长按: 连续拖动")
        .fontSize(11).fontColor("#99FFFFFF").width("100%").padding({ left: 4, right: 4 })
      Text("左栏按钮: 搜/时/位/层/详/设  底栏: 方向/视场/模式切换")
        .fontSize(11).fontColor("#99FFFFFF").width("100%").padding({ left: 4, right: 4 }).margin({ top: 2 })
      // 星图文化选择
      if (this.skyCultures.length > 0) {
        Row() {
          Text("星图文化").fontSize(12).fontColor("#66FFFFFF").width(72)
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
      Text('LX200 GoTo')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E5FFFFFF')
        .width('100%')
      TextInput({ text: this.lx200Host, placeholder: '主机，例如 192.168.1.50' })
        .height(38)
        .fontSize(13)
        .fontColor('#E5FFFFFF')
        .placeholderColor('#8EA0BD')
        .backgroundColor('rgba(255, 255, 255, 0.06)')
        .border({ width: 1, color: 'rgba(214, 238, 255, 0.14)' })
        .borderRadius(12)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.lx200Host = value
        })
      TextInput({ text: this.lx200Port, placeholder: '端口，例如 4030' })
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
        Button('GoTo')
          .height(32)
          .fontSize(12)
          .fontColor('#FFFFFFFF')
          .backgroundColor('#5B93BF')
          .borderRadius(16)
          .margin({ right: 8 })
          .onClick(() => {
            this.lx200GotoSelected()
          })
        Button('Sync')
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
        Button('停止')
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
        Text('观测位置')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E5FFFFFF')
          .layoutWeight(1)
        Button('自动定位')
          .height(30)
          .fontSize(11)
          .fontColor('#FFFFFFFF')
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
        TextInput({ text: this.locationPickerName, placeholder: '位置名称' })
          .height(36)
          .fontSize(13)
          .fontColor('#E5FFFFFF')
          .placeholderColor('#8EA0BD')
          .backgroundColor('rgba(255, 255, 255, 0.06)')
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
          Text('N')
            .fontSize(10)
            .fontColor('#99FFFFFF')
            .position({ x: 8, y: 6 })
          Text('S')
            .fontSize(10)
            .fontColor('#99FFFFFF')
            .position({ x: 8, y: this.mapRenderHeight - 20 })
          Text('⌖')
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

      TextInput({ text: this.locationPickerAltitude.toFixed(0), placeholder: '海拔 m' })
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
        Button('应用')
          .height(32)
          .fontSize(12)
          .fontColor('#FFFFFFFF')
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
	        Text('望远镜')
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
	        Button('GoTo')
	          .height(32)
	          .fontSize(12)
	          .fontColor('#FFFFFFFF')
	          .backgroundColor('#5B93BF')
	          .borderRadius(16)
	          .margin({ right: 8 })
	          .onClick(() => {
	            this.lx200GotoSelected()
	          })
	        Button('Sync')
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
	        Button('停止')
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
      Text('锁定界面位置')
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
      Text('界面语言')
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .width(72)
      Scroll() {
        Row({ space: 6 }) {
          ForEach([
            { code: 'zh_CN', name: '简体中文' },
            { code: 'zh_HK', name: '繁體(港)' },
            { code: 'zh_TW', name: '繁體(台)' },
            { code: 'ja', name: '日本語' },
            { code: 'ko', name: '한국어' },
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
            { code: 'en', name: 'English' },
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
      Text('转动设备浏览星空')
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
  quickChips(labels: string[]) {
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
    if (label === '刷新') {
      this.refreshSelectedObject()
      this.refreshState()
    } else if (label === '居中' || label === '追踪') {
      this.moveToSelectedObject()
    } else if (label === '取消追踪') {
      const result = this.callNative('setTracking', '0')
      if (result.ok === true) {
        this.refreshState()
      }
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
    } else if (label === 'Moon') {
      this.searchObject('Moon')
    } else if (label === 'Mars') {
      this.searchObject('Mars')
    } else if (label === 'Jupiter') {
      this.searchObject('Jupiter')
    } else if (label === '北京') {
      this.setLocation('Beijing', 39.9042, 116.4074, 44)
    } else if (label === '上海') {
      this.setLocation('Shanghai', 31.2304, 121.4737, 4)
    } else if (label === '深圳') {
      this.setLocation('Shenzhen', 22.5431, 114.0579, 40)
    // 搜索面板天体快捷搜索
    } else if (['Sun', 'Mercury', 'Venus', 'Saturn', 'Sirius', 'Vega', 'Betelgeuse', 'Polaris', 'M31', 'M42', 'M45', 'NGC 2244'].includes(label)) {
      this.searchObject(label)
    // 方向快捷查看
    } else if (label === '东') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_East'); this.refreshState(); this.flashHint('朝东')
    } else if (label === '南') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_South'); this.refreshState(); this.flashHint('朝南')
    } else if (label === '西') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_West'); this.refreshState(); this.flashHint('朝西')
    } else if (label === '北') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_North'); this.refreshState(); this.flashHint('朝北')
    } else if (label === '天顶') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_Zenith'); this.refreshState(); this.flashHint('天顶')
    } else if (label === '北天极') {
      this.stopTracking(); this.triggerAction('actionLook_Towards_NCP'); this.refreshState(); this.flashHint('北天极')
    // FOV 快捷切换（actionSet_FOV 索引: 0=0.5°, 1=180°, 2=90°, 3=60°, 4=45°, 5=20°, 6=10°, 7=5°, 8=2°, 9=1°）
    } else if (label === '1°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_9'); this.refreshState(); this.flashHint('FOV 1°')
    } else if (label === '2°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_8'); this.refreshState(); this.flashHint('FOV 2°')
    } else if (label === '5°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_7'); this.refreshState(); this.flashHint('FOV 5°')
    } else if (label === '10°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_6'); this.refreshState(); this.flashHint('FOV 10°')
    } else if (label === '20°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_5'); this.refreshState(); this.flashHint('FOV 20°')
    } else if (label === '45°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_4'); this.refreshState(); this.flashHint('FOV 45°')
    } else if (label === '60°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_3'); this.refreshState(); this.flashHint('FOV 60°')
    } else if (label === '90°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_2'); this.refreshState(); this.flashHint('FOV 90°')
    } else if (label === '180°') {
      this.stopTracking(); this.triggerAction('actionSet_FOV_1'); this.refreshState(); this.flashHint('FOV 180°')
    }
  }

  @Builder
  infoRow(label: string, value: string) {
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
      .backgroundColor('rgba(255, 255, 255, 0.04)')
      .borderRadius(12)
      .margin({ bottom: 4 })
  }

  @Builder
  switchRow(label: string, enabled: boolean, actionId: string) {
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

  private panelTitle(): string {
    if (this.activePanel === 'search') {
      return '搜索'
    }
    if (this.activePanel === 'time') {
      return '时间'
    }
    if (this.activePanel === 'place') {
      return '位置'
    }
    if (this.activePanel === 'layers') {
      return '图层'
    }
    if (this.activePanel === 'settings') {
      return '设置'
    }
    return '目标详情'
  }

  private panelSubtitle(): string {
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
    if (this.activePanel === 'settings') {
      return '显示与控制'
    }
    return '点击星空后显示'
  }
}
