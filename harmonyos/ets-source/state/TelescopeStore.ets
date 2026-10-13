import { I18n } from '../pages/I18n'
import { OcularInstrumentItem, OcularSelInfo, OcularsResponse, TelescopeProfile, TELESCOPE_SIMULATOR_MODEL } from '../pages/MainWindowModels'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'

// 「望远镜控制」/「目镜（Oculars）」两面板的状态簇：持有目镜插件配置簇、
// LX200 望远镜控制簇、「赤道仪」开关 equatorialMount。
// 消费方（望远镜控制面板 / 目镜面板 / OcularSelector 等）以 @ObjectLink 观察，
// 字段赋值即刷新。自持 CommandPort、请求序号 seq 供 loadOculars 使用；live-position 定时器链与
// loadTelescopeControlStatus 在 capability/TelescopeController。只放数据与纯查表计算，不 import UI / NAPI。
@Observed
export class TelescopeStore {
  // —— 目镜（Oculars）——
  ocularMode: boolean = false
  telradOn: boolean = false
  crosshairsOn: boolean = false
  ccdOn: boolean = false
  ocularNames: string[] = []
  telescopeNames: string[] = []
  lensNames: string[] = []
  ccdNames: string[] = []
  ocularIndex: number = -1
  telescopeIndex: number = -1
  lensIndex: number = -1
  ccdIndex: number = -1
  ocularItems: OcularInstrumentItem[] = []
  telescopeItems: OcularInstrumentItem[] = []
  lensItems: OcularInstrumentItem[] = []
  ccdItems: OcularInstrumentItem[] = []
  ocularLoading: boolean = false
  ocularStatusMessage: string = ''
  ocularReady: boolean = false
  ocularCcdReady: boolean = false
  ocularHasSelection: boolean = false
  ocularRequireSelection: boolean = true
  ocularAutoLimitMagnitude: boolean = true
  ocularHideGridsLines: boolean = true
  ocularAutoScaleTelrad: boolean = true
  ocularAutoScaleCcd: boolean = true
  ocularSemiTransparentMask: boolean = false
  ocularMaskOpacity: number = 85
  ocularShowResolutionCriteria: boolean = false
  ocularAutoSetMountForCcd: boolean = false
  ocularHorizontalCoordinates: boolean = false
  ocularSensorCropOverlay: boolean = false
  ocularSensorPixelGrid: boolean = false
  ocularFocuserOverlay: boolean = false
  ocularScaleImageCircle: boolean = true
  ocularMaxExposureTimeForCcd: boolean = false
  ocularShowContour: boolean = false
  ocularShowCardinals: boolean = false
  ocularAlignCrosshair: boolean = false
  ocularSmallFocuserOverlay: boolean = false
  ocularMediumFocuserOverlay: boolean = true
  ocularLargeFocuserOverlay: boolean = false
  ocularDmsDegrees: boolean = false
  ocularInitFov: boolean = false
  ocularInitDirection: boolean = false
  ocularOagLimits: boolean = true
  ocularCcdCropHSize: number = 250
  ocularCcdCropVSize: number = 250
  ocularCcdPrismRotation: number = 0
  ocularGuiPanelEnabled: boolean = true
  ocularMagnification: number = 0
  ocularActualFov: number = 0
  ocularExitPupil: number = 0
  ocularLimitMagnitude: number = 0
  ocularCcdFovX: number = 0
  ocularCcdFovY: number = 0
  ocularCcdPixelScaleX: number = 0
  ocularCcdPixelScaleY: number = 0
  ocularCcdRotation: number = 0

  // —— LX200 望远镜控制 ——
  lx200Host: string = ''
  lx200Port: string = ''
  lx200Profiles: TelescopeProfile[] = []
  lx200SelectedSlot: number = 1
  lx200Name: string = 'Offline Telescope Simulator'
  lx200Protocol: string = 'simulated'
  lx200DeviceModel: string = TELESCOPE_SIMULATOR_MODEL
  lx200Equinox: string = 'J2000'
  lx200CommandDelayMs: number = 0
  lx200Circles: string = '1, 2, 4'
  lx200TargetSource: string = 'selected'
  lx200Busy: boolean = false
  lx200EditingNew: boolean = false
  lx200Status: ResourceStr = I18n.t('m_telescope_idle')
  lx200Scope: ResourceStr = I18n.t('m_telescope_scope_unknown')
  lx200Transport: ResourceStr = I18n.t('m_telescope_transport_simulated')
  lx200ConnectionState: string = 'not_tested'
  lx200Position: string = ''
  lx200LivePositionEnabled: boolean = false
  lx200PositionUpdatedAt: string = ''
  lx200PositionUpdateState: string = 'idle'

  // —— 赤道仪开关 ——
  equatorialMount: boolean = false

  // —— 目镜选择器的纯查表计算（只读本 store 字段） ——
  ocularInstrumentItems(kind: string): OcularInstrumentItem[] {
    if (kind === 'Ocular') return this.ocularItems
    if (kind === 'Telescope') return this.telescopeItems
    if (kind === 'Lens') return this.lensItems
    return this.ccdItems
  }

  ocularInstrumentIndex(kind: string): number {
    if (kind === 'Ocular') return this.ocularIndex
    if (kind === 'Telescope') return this.telescopeIndex
    if (kind === 'Lens') return this.lensIndex
    return this.ccdIndex
  }

  ocularInstrumentSummary(kind: string, item: OcularInstrumentItem): string {
    if (kind === 'Ocular') {
      if (item.binocular === true) return I18n.t('ocular_binocular') + ' · ' + (item.apparentFov ?? 0).toFixed(1) + '°'
      return (item.focalLength ?? 0).toFixed(1) + ' mm · ' + (item.apparentFov ?? 0).toFixed(1) + '°'
    }
    if (kind === 'Telescope') return 'D ' + (item.diameter ?? 0).toFixed(0) + ' mm · f/' + (item.focalRatio ?? 0).toFixed(1)
    if (kind === 'Lens') return (item.multiplier ?? 1).toFixed(2) + '×'
    return (item.resolutionX ?? 0).toString() + ' × ' + (item.resolutionY ?? 0).toString()
  }

  ocularSelInfo(kind: string): OcularSelInfo {
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

  // —— 桥注入 ——
  // 宿主在 aboutToAppear 以同一个 CommandPort 实例调用 attachPort(port, onChanged) 注入；
  // 请求序号 seq 由本 store 自持，用于作废在途回包。
  // 本域无 publish* 发布点、消费方均为 @ObjectLink（字段赋值即刷新），故 onChanged 为空实现。
  private port: CommandPort | null = null
  private seq: number = 0
  private onChanged: (() => void) | null = null

  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // 目镜插件加载：拉取目镜 / 望远镜 / 镜头 / CCD 配置与当前选择；回包按 seq 作废在途请求。
  loadOculars(showLoading: boolean = true): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const requestId = ++this.seq
    if (showLoading) this.ocularLoading = true
    port.requestWhenReady('getOculars', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.seq) return
      this.ocularLoading = false
      const resp = r as OcularsResponse
      const o = resp.oculars
      if (!o) {
        this.ocularStatusMessage = I18n.t('ocular_status_unavailable')
        return
      }
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
      this.ocularItems = o.ocularItems ?? []
      this.telescopeItems = o.telescopeItems ?? []
      this.lensItems = o.lensItems ?? []
      this.ccdItems = o.ccdItems ?? []
      this.ocularReady = o.ocularReady
      this.ocularCcdReady = o.ccdReady
      this.ocularHasSelection = o.hasSelection
      this.ocularRequireSelection = o.requireSelection
      this.ocularAutoLimitMagnitude = o.autoLimitMagnitude
      this.ocularHideGridsLines = o.hideGridsLines
      this.ocularAutoScaleTelrad = o.autoScaleTelrad
      this.ocularAutoScaleCcd = o.autoScaleCcd
      this.ocularSemiTransparentMask = o.semiTransparentMask
      this.ocularMaskOpacity = o.maskOpacity
      this.ocularShowResolutionCriteria = o.showResolutionCriteria
      this.ocularAutoSetMountForCcd = o.autoSetMountForCcd
      this.ocularHorizontalCoordinates = o.horizontalCoordinates
      this.ocularSensorCropOverlay = o.sensorCropOverlay
      this.ocularSensorPixelGrid = o.sensorPixelGrid
      this.ocularFocuserOverlay = o.focuserOverlay
      this.ocularScaleImageCircle = o.scaleImageCircle
      this.ocularMaxExposureTimeForCcd = o.maxExposureTimeForCcd
      this.ocularShowContour = o.showContour
      this.ocularShowCardinals = o.showCardinals
      this.ocularAlignCrosshair = o.alignCrosshair
      this.ocularSmallFocuserOverlay = o.smallFocuserOverlay
      this.ocularMediumFocuserOverlay = o.mediumFocuserOverlay
      this.ocularLargeFocuserOverlay = o.largeFocuserOverlay
      this.ocularDmsDegrees = o.dmsDegrees
      this.ocularInitFov = o.initFov
      this.ocularInitDirection = o.initDirection
      this.ocularOagLimits = o.oagLimits
      this.ocularCcdCropHSize = o.ccdCropHSize ?? 250
      this.ocularCcdCropVSize = o.ccdCropVSize ?? 250
      this.ocularCcdPrismRotation = o.ccdPrismRotation ?? 0
      this.ocularGuiPanelEnabled = o.guiPanelEnabled
      this.ocularMagnification = o.magnification ?? 0
      this.ocularActualFov = o.actualFov ?? 0
      this.ocularExitPupil = o.exitPupil ?? 0
      this.ocularLimitMagnitude = o.limitMagnitude ?? 0
      this.ocularCcdFovX = o.ccdFovX ?? 0
      this.ocularCcdFovY = o.ccdFovY ?? 0
      this.ocularCcdPixelScaleX = o.ccdPixelScaleX ?? 0
      this.ocularCcdPixelScaleY = o.ccdPixelScaleY ?? 0
      this.ocularCcdRotation = o.ccdRotation ?? 0
      this.ocularStatusMessage = this.ocularReady ? '' : I18n.t('ocular_status_no_config')
      this.notifyChanged()
    }, () => {
      if (requestId === this.seq) this.ocularLoading = false
      this.ocularStatusMessage = I18n.t('ocular_status_unavailable')
    }, 0, 100, 15)
  }

  // 从 lx200Circles 解析出赤道仪刻度环取值：仅取 1..180 的正数，去重、至多 10 个并升序。
  telescopeCircleValues(): number[] {
    const values: number[] = []
    const parts = this.lx200Circles.split(',')
    for (let index = 0; index < parts.length; index += 1) {
      const value = Number(parts[index].trim())
      if (Number.isFinite(value) && value > 0 && value <= 180 && !values.includes(value)) {
        values.push(value)
      }
      if (values.length >= 10) break
    }
    values.sort((left: number, right: number) => left - right)
    return values
  }

  // 赤道仪开关持久化：equatorialMount 即本 store 字段；AppStorage 读写不属 NAPI，
  // store 内直接完成。
  persistEquatorialMount(): void {
    let obj: Record<string, boolean | string> = {}
    const cur = AppStorage.get<string>('stellariumSettings')
    if (cur) {
      try { obj = JSON.parse(cur) as Record<string, boolean | string> } catch (e) { }
    }
    obj['equatorialMount'] = this.equatorialMount
    AppStorage.setOrCreate('stellariumSettings', JSON.stringify(obj))
  }
}
