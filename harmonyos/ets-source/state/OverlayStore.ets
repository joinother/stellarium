import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { PointerCoordinatesResponse } from '../pages/MainWindowModels'
import { CommandPort } from '../bridge/CommandPort'

// 「视图中心坐标」叠层、「指针坐标」插件面板与「天体详情指向线」开关的状态簇：持有开关与
// 档位（字符串枚举选项）等设置类字段。宿主持有实例，相关面板 / 叠层以 @ObjectLink 观察。
//
// 刻意不入本 store：视图中心坐标的实时读数与拖拽瞬时量、天体详情指向线的几何量等逐帧/
// 触摸级字段（放进被观察 store 会造成重渲染风暴），一律留在宿主由组件以 @Prop 接收；
// 天体检查器的模型叠层字段属渲染管线，同样留在宿主。
// store 只放数据与纯查表/纯计算，不 import UI / NAPI。
@Observed
export class OverlayStore {
  // —— 视图中心坐标叠层（设置） ——
  viewCoordinatesVisible: boolean = false
  viewCoordinateFamily: string = 'equatorial'
  viewEquatorialEpoch: string = 'j2000'

  // —— 指针坐标插件（设置 + 请求态） ——
  pointerCoordinatesLoading: boolean = false
  pointerCoordinatesStatus: string = ''
  pointerCoordinatesEnabled: boolean = false
  pointerCoordinatesStartup: boolean = false
  pointerCoordinatesButton: boolean = false
  pointerCoordinatesConstellation: boolean = false
  pointerCoordinatesCrossedLines: boolean = false
  pointerCoordinatesElongation: boolean = false
  pointerCoordinatesSystem: string = 'RaDecJ2000'
  pointerCoordinatesPlace: string = 'TopCenter'

  // —— 天体详情指向线（设置） ——
  objectDetailConnectorVisible: boolean = true

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（无并发抑制需求）；保留字段以统一各 store 的加载器约定。
  private seq: number = 0
  private onChanged: (() => void) | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // 叠层标题：赤道坐标会带历元后缀。
  viewCoordinateTitle(): string {
    if (this.viewCoordinateFamily === 'horizontal') { return I18n.t('view_coord_horizontal') }
    if (this.viewCoordinateFamily === 'galactic') { return I18n.t('view_coord_galactic') }
    return I18n.t('view_coord_equatorial') + ' · ' +
      I18n.t(this.viewEquatorialEpoch === 'ofDate' ? 'view_coord_of_date' : 'view_coord_j2000')
  }

  viewCoordinateFamilyLabel(family: string): string {
    if (family === 'horizontal') { return I18n.t('view_coord_horizontal') }
    if (family === 'galactic') { return I18n.t('view_coord_galactic') }
    return I18n.t('view_coord_equatorial')
  }

  viewCoordinatePrimaryLabel(): string {
    if (this.viewCoordinateFamily === 'horizontal') { return I18n.t('view_coord_azimuth') }
    if (this.viewCoordinateFamily === 'galactic') { return I18n.t('view_coord_galactic_longitude') }
    return I18n.t('view_coord_ra')
  }

  viewCoordinateSecondaryLabel(): string {
    if (this.viewCoordinateFamily === 'horizontal') { return I18n.t('view_coord_altitude') }
    if (this.viewCoordinateFamily === 'galactic') { return I18n.t('view_coord_galactic_latitude') }
    return I18n.t('view_coord_dec')
  }

  pointerCoordinateSystemLabel(key: string): string {
    switch (key) {
      case 'RaDecJ2000': return I18n.t('pointer_coord_radec_j2000')
      case 'RaDec': return I18n.t('pointer_coord_radec_date')
      case 'HourAngle': return I18n.t('pointer_coord_hour_angle')
      case 'Ecliptic': return I18n.t('pointer_coord_ecliptic')
      case 'EclipticJ2000': return I18n.t('pointer_coord_ecliptic_j2000')
      case 'AltAzi': return I18n.t('pointer_coord_altaz')
      case 'Galactic': return I18n.t('pointer_coord_galactic')
      case 'Supergalactic': return I18n.t('pointer_coord_supergalactic')
      default: return key
    }
  }

  pointerCoordinatesPlaceLabel(key: string): string {
    switch (key) {
      case 'TopCenter': return I18n.t('pointer_coord_place_top_center')
      case 'TopRight': return I18n.t('pointer_coord_place_top_right')
      case 'RightBottomCorner': return I18n.t('pointer_coord_place_bottom_right')
      case 'NearMouseCursor': return I18n.t('pointer_coord_place_near_pointer')
      case 'Custom': return I18n.t('pointer_coord_place_custom')
      default: return key
    }
  }

  // 指针坐标插件：桥读全部设置项与请求态（启动期重试档 0/100/15 保留）。
  // 本域无 publish* 发布点，onChanged 为空实现。
  loadPointerCoordinates(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    this.pointerCoordinatesLoading = true
    port.requestWhenReady('getPointerCoordinates', '', (r: StellariumBridgeResponse) => {
      this.pointerCoordinatesLoading = false
      const data = (r as PointerCoordinatesResponse).pointerCoordinates
      if (r.ok !== true || data === undefined) {
        this.pointerCoordinatesStatus = I18n.t('plugin_status_unavailable')
        this.notifyChanged()
        return
      }
      this.pointerCoordinatesEnabled = data.enabled
      this.pointerCoordinatesStartup = data.enableAtStartup
      this.pointerCoordinatesButton = data.showCoordinatesButton
      this.pointerCoordinatesConstellation = data.showConstellation
      this.pointerCoordinatesCrossedLines = data.showCrossedLines
      this.pointerCoordinatesElongation = data.showElongation
      this.pointerCoordinatesSystem = data.coordinateSystem
      this.pointerCoordinatesPlace = data.coordinatesPlace
      this.pointerCoordinatesStatus = ''
      this.notifyChanged()
    }, () => {
      this.pointerCoordinatesLoading = false
      this.pointerCoordinatesStatus = I18n.t('plugin_status_unavailable')
      this.notifyChanged()
    }, 0, 100, 15)
  }
}
