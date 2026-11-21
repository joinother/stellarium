import { Theme } from '@kit.ArkUI'
import { map, mapCommon, MapComponent } from '@kit.MapKit'
import { connection } from '@kit.NetworkKit'
import { AsyncCallback, BusinessError } from '@ohos.base'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL, UI_RADIUS_TAG } from '../../common/ui/UiTokens'
import { InfoTipButton } from '../../common/ui/InfoTipButton'

// 星空文化渊源参考坐标地图卡（华为花瓣地图官方审图底图）。
//
// 合规原则：
// 1. 仅使用华为花瓣地图（Map Kit）官方合规底图，绝不使用未经审图的第三方离线世界地图栅格；
// 2. 仅标注单点历史天文渊源坐标（代表观星纬度），绝不绘制任何疆域多边形、政区轮廓或争议边界；
// 3. 全球通用现代 88 星座标准直接呈现「全天通用」说明卡，不以单一国家代表全球标准；
// 4. 离线或未授权联网时优雅降级为纯坐标纬度卡，保证零合规风险且不影响面板垂直滑动。

const MAP_LOAD_TIMEOUT_MS: number = 12000

@Component
export struct SkyCulturePetalMapCard {
  @Prop @Watch('onTargetChanged') cultureId: string = ''
  @Prop @Watch('onTargetChanged') originLabelZh: string = ''
  @Prop @Watch('onTargetChanged') regionZh: string = ''
  @Prop @Watch('onTargetChanged') hemisphereZh: string = ''
  @Prop @Watch('onTargetChanged') latitude: number = 0
  @Prop @Watch('onTargetChanged') longitude: number = 0
  @Prop @Watch('onTargetChanged') zoomLevel: number = 5
  @Prop @Watch('onTargetChanged') isGlobal: boolean = false
  @Prop @Watch('onTargetChanged') onlineAllowed: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private mapStarted: boolean = false
  @State private mapReady: boolean = false
  @State private mapFailed: boolean = false

  private controller?: map.MapComponentController
  private themeNight: boolean = false
  private lastModeKey: string = ''
  private timeoutId: number = -1

  private options: mapCommon.MapOptions = {
    position: { target: { latitude: 34.43, longitude: 113.14 }, zoom: 5 },
    mapType: mapCommon.MapType.TERRAIN,
    dayNightMode: mapCommon.DayNightMode.NIGHT,
    minZoom: 3,
    maxZoom: 12,
    scrollGesturesEnabled: false,
    zoomGesturesEnabled: false,
    rotateGesturesEnabled: false,
    tiltGesturesEnabled: false,
    zoomControlsEnabled: false,
    compassControlsEnabled: false,
    myLocationControlsEnabled: false,
    scaleControlsEnabled: false
  }

  private callback: AsyncCallback<map.MapComponentController> = (error: BusinessError,
    controller: map.MapComponentController): void => {
    if (error) {
      this.onMapError()
      return
    }
    if (!this.mapStarted) return
    this.controller = controller
    const events = controller.getEventManager()
    events.on('mapLoad', () => { this.onMapLoad() })
    events.on('error', (_error: BusinessError) => { this.onMapError() })
  }

  onWillApplyTheme(theme: Theme): void {
    const next = slotsFromTheme(theme)
    const nightChanged = next.isNight !== this.c.isNight
    this.c = next
    this.themeNight = next.isNight
    this.options.dayNightMode = mapCommon.DayNightMode.NIGHT
    if (nightChanged) this.applyMapNightMode()
  }

  aboutToAppear(): void {
    this.lastModeKey = this.modeKey()
    this.prepareMap()
  }

  aboutToDisappear(): void {
    this.clearTimeout()
    this.mapStarted = false
    this.controller = undefined
  }

  private onTargetChanged(): void {
    const key = this.modeKey()
    if (key !== this.lastModeKey) {
      this.lastModeKey = key
      this.prepareMap()
      return
    }
    if (this.mapFailed) {
      this.prepareMap()
      return
    }
    if (this.mapReady) {
      this.syncPoint()
    }
  }

  private hasNetwork(): boolean {
    try {
      return connection.hasDefaultNetSync()
    } catch (_error) {
      return true
    }
  }

  private onlineMode(): boolean {
    return !this.isGlobal && this.onlineAllowed && this.hasNetwork()
  }

  private modeKey(): string {
    return (this.isGlobal ? 'G' : 'P') + '|' + (this.onlineAllowed ? '1' : '0')
  }

  private clearTimeout(): void {
    if (this.timeoutId >= 0) {
      clearTimeout(this.timeoutId)
      this.timeoutId = -1
    }
  }

  private prepareMap(): void {
    this.clearTimeout()
    this.mapReady = false
    this.mapFailed = false
    this.controller = undefined
    this.options.position = {
      target: { latitude: this.latitude, longitude: this.longitude },
      zoom: this.zoomLevel
    }
    this.options.dayNightMode = mapCommon.DayNightMode.NIGHT
    if (!this.onlineMode()) {
      this.mapStarted = false
      return
    }
    this.mapStarted = true
    this.timeoutId = setTimeout(() => {
      if (this.mapReady) return
      this.mapFailed = true
      this.mapStarted = false
      this.controller = undefined
    }, MAP_LOAD_TIMEOUT_MS)
  }

  private async onMapLoad(): Promise<void> {
    if (!this.mapStarted) return
    this.mapReady = true
    this.mapFailed = false
    this.clearTimeout()
    this.applyMapNightMode()
    await this.syncPoint()
  }

  private onMapError(): void {
    if (!this.mapStarted) return
    this.clearTimeout()
    this.mapReady = false
    this.mapFailed = true
    this.mapStarted = false
    this.controller = undefined
  }

  private applyMapNightMode(): void {
    const controller = this.controller
    if (!controller) return
    try {
      if (typeof controller.setDayNightMode !== 'function') return
      controller.setDayNightMode(mapCommon.DayNightMode.NIGHT)
    } catch (_error) {
      // Keep current map day/night mode.
    }
  }

  private async toMapCoordinate(latitude: number, longitude: number): Promise<mapCommon.LatLng> {
    const point: mapCommon.LatLng = { latitude: latitude, longitude: longitude }
    try {
      const context = this.getUIContext().getHostContext()
      if (!context) return point
      const points = await map.rectifyCoordinate(context, [{
        coordinateType: mapCommon.CoordinateType.WGS84,
        location: point
      }])
      if (points && points.length > 0) return points[0].location
    } catch (_error) {
      // Fall back to raw WGS84 outside mainland China or when unavailable.
    }
    return point
  }

  private async syncPoint(): Promise<void> {
    if (!this.mapStarted || !this.mapReady) return
    const controller = this.controller
    if (!controller) return
    const point = await this.toMapCoordinate(this.latitude, this.longitude)
    if (!this.mapStarted || this.controller !== controller) return
    try {
      controller.moveCamera(map.newCameraPosition({ target: point, zoom: this.zoomLevel }))
    } catch (_error) {
      // Keep current camera if SDK rejects update.
    }
    this.applyMapNightMode()
  }

  private formatLatLon(): string {
    const latStr = Math.abs(this.latitude).toFixed(1) + '°' + (this.latitude >= 0 ? 'N' : 'S')
    const lonStr = Math.abs(this.longitude).toFixed(1) + '°' + (this.longitude >= 0 ? 'E' : 'W')
    return latStr + ' · ' + lonStr
  }

  private latitudeInsight(): string {
    if (this.isGlobal) return '覆盖南北全天 88 星座，适合全球任意纬度观星使用'
    const absLat = Math.abs(this.latitude)
    if (absLat >= 60) return '高纬极地视野：大量拱极星座终年不落，极夜观星特征鲜明'
    if (absLat <= 23.5) return '低纬热带视野：南北两半球亮星交汇，天顶星与赤道星座清晰可见'
    return this.latitude >= 0
      ? '北半球中纬视野：北斗与北天极星象显著，四季星座轮转分明'
      : '南半球中纬视野：南十字座、银河中心与大麦哲伦云高悬夜空'
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text(this.isGlobal ? '全天覆盖与标准范围' : '观星渊源坐标 · 花瓣地图')
          .fontSize(12).fontColor(this.c.text).fontWeight(FontWeight.Medium).layoutWeight(1)
        InfoTipButton({
          title: '文化地理与花瓣地图说明',
          tip: '采用华为花瓣地图官方审图底图，仅以单点坐标标注该星空文化的历史天文渊源与观星参考纬度，不绘制任何疆域多边形或行政界线，领土与国界以官方地图为准。'
        })
      }.width('100%').alignItems(VerticalAlign.Center)

      if (this.isGlobal) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text('全天 88 星座通用标准')
              .fontSize(11).fontColor(this.c.accent).fontWeight(FontWeight.Medium)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.c.accentSoft).borderRadius(UI_RADIUS_TAG)
            Text(this.hemisphereZh)
              .fontSize(10).fontColor(this.c.sub)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_TAG)
          }.width('100%')
          Text(this.latitudeInsight())
            .fontSize(11).fontColor(this.c.sub).width('100%').lineHeight(17)
        }
        .width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
        .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          // 离线/加载中占位：纯深色经纬参考底纹，绝不加载未经审图的离线世界地图栅格。
          Column({ space: 4 }) {
            Text(this.originLabelZh)
              .fontSize(12).fontColor(this.c.text).fontWeight(FontWeight.Medium).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.formatLatLon() + ' · ' + this.regionZh)
              .fontSize(10).fontColor(this.c.sub).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.onlineAllowed ? '正在加载花瓣地图官方底图…' : '离线模式：显示观星渊源参考坐标')
              .fontSize(10).fontColor(this.c.tertiary)
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .padding({ left: 14, right: 14 }).backgroundColor(this.c.soft)

          if (this.mapStarted && !this.mapFailed) {
            MapComponent({ mapOptions: this.options, mapCallback: this.callback })
              .width('100%').height('100%')
              .hitTestBehavior(HitTestMode.None)
          }

          Row()
            .width('100%').height('100%')
            .backgroundColor(this.mapReady ? this.c.mapNightTint : Color.Transparent)
            .hitTestBehavior(HitTestMode.None)

          // 精巧居中单点坐标标靶（地图为只读且始终居中于渊源坐标），绝不绘制任何疆域多边形。
          if (this.mapReady) {
            Stack({ alignContent: Alignment.Center }) {
              Circle().width(26).height(26).fill(this.c.accent).fillOpacity(0.26)
              Circle().width(11).height(11).fill(this.c.accent).stroke('#FFFFFF').strokeWidth(2)
            }
            .width('100%').height('100%')
            .hitTestBehavior(HitTestMode.None)
          }

          Text(this.mapReady ? '花瓣地图 · 渊源坐标' : this.formatLatLon())
            .fontSize(10).fontColor(this.c.text)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.c.panelGlassStrong).borderRadius(UI_RADIUS_PILL)
            .position({ x: 8, y: 8 })
            .hitTestBehavior(HitTestMode.None)

          if (this.mapStarted && !this.mapReady && !this.mapFailed) {
            Row() {
              LoadingProgress().width(14).height(14).color(this.c.accent)
            }
            .width(24).height(24).justifyContent(FlexAlign.Center)
            .backgroundColor(this.c.panelGlassStrong).borderRadius(UI_RADIUS_PILL)
            .position({ x: 8, y: 108 })
            .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%').height(140).clip(true).borderRadius(UI_RADIUS_CONTROL)
        .border({ width: 0.5, color: this.c.border })

        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(this.originLabelZh).fontSize(11).fontColor(this.c.text).fontWeight(FontWeight.Medium).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.formatLatLon()).fontSize(10).fontColor(this.c.accent)
          }.width('100%')
          Text(this.latitudeInsight()).fontSize(10).fontColor(this.c.sub).width('100%').lineHeight(16)
        }.width('100%')
      }
    }
    .width('100%').padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .backgroundColor(this.c.bg).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)
  }
}
