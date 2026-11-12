import { Theme } from '@kit.ArkUI'
import { map, mapCommon, MapComponent } from '@kit.MapKit'
import { connection } from '@kit.NetworkKit'
import { AsyncCallback, BusinessError } from '@ohos.base'
import { I18n } from '../../pages/I18n'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// Read-only terrain preview of the point currently staged in the picker.
//
// The panel's map is deliberately NOT interactive: a native MapComponent that
// consumes drags inside the scrollable glass sheet would make the panel hard to
// scroll, and panning away from the pin would fight the card's purpose (showing
// where the selected point is). The full-screen Map Kit picker remains the only
// interactive map. The preview uses the free online terrain basemap, so it is
// not part of the metered Map Kit switch; privacy/network gates and the offline
// world map / planet texture fallback still apply.
const PREVIEW_ZOOM: number = 12
const PREVIEW_MIN_ZOOM: number = 5
const PREVIEW_MAX_ZOOM: number = 14
const MAP_LOAD_TIMEOUT_MS: number = 12000

@Component
export struct LocationOverviewCard {
  @Prop @Watch('onInputChanged') planet: string = 'Earth'
  @Prop @Watch('onInputChanged') latitude: number = 0
  @Prop @Watch('onInputChanged') longitude: number = 0
  @Prop @Watch('onInputChanged') texture: string = ''
  @Prop @Watch('onInputChanged') onlineAllowed: boolean = false
  // True while the full-screen picker is open: unmount the panel map so two
  // native map surfaces are never alive at the same time.
  @Prop @Watch('onInputChanged') suspended: boolean = false
  @Prop source: string = 'named'
  @Prop previewWidth: number = 276
  @Prop previewHeight: number = 138
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private mapStarted: boolean = false
  @State private mapReady: boolean = false
  @State private mapFailed: boolean = false
  onOpen: () => void = () => {}

  private controller?: map.MapComponentController
  private marker?: map.Marker
  private themeNight: boolean = false
  private lastModeKey: string = ''
  private timeoutId: number = -1

  private options: mapCommon.MapOptions = {
    position: { target: { latitude: 0, longitude: 0 }, zoom: PREVIEW_ZOOM },
    mapType: mapCommon.MapType.TERRAIN,
    minZoom: PREVIEW_MIN_ZOOM,
    maxZoom: PREVIEW_MAX_ZOOM,
    // Static preview: every gesture and control is disabled. The transparent
    // click layer above the map opens the full-screen picker instead.
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
    this.options.dayNightMode = next.isNight ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.AUTO
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
    this.marker = undefined
  }

  private onInputChanged(): void {
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
      // Without the network-info permission, assume online and let Map Kit
      // fail into the offline overview.
      return true
    }
  }

  private onlineMode(): boolean {
    return this.planet === 'Earth' && this.onlineAllowed && !this.suspended && this.hasNetwork()
  }

  private modeKey(): string {
    return this.planet + '|' + (this.onlineAllowed ? '1' : '0') + '|' + (this.suspended ? '1' : '0')
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
    this.marker = undefined
    this.options.position = {
      target: { latitude: this.latitude, longitude: this.longitude },
      zoom: PREVIEW_ZOOM
    }
    this.options.dayNightMode = this.themeNight ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.AUTO
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
      this.marker = undefined
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
    this.marker = undefined
  }

  private applyMapNightMode(): void {
    const controller = this.controller
    if (!controller) return
    try {
      // Older HMS map services may not expose the setter; the red tint above
      // the map still protects dark adaptation.
      if (typeof controller.setDayNightMode !== 'function') return
      controller.setDayNightMode(this.themeNight ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.AUTO)
    } catch (_error) {
      // Keep the current style.
    }
  }

  // The online Petal map uses GCJ02 in mainland China. Markers and camera
  // targets use the rectified map coordinate, matching the full-screen picker.
  private async toMapCoordinate(latitude: number, longitude: number): Promise<mapCommon.LatLng> {
    const point: mapCommon.LatLng = { latitude: latitude, longitude: longitude }
    if (this.planet !== 'Earth') return point
    try {
      const context = this.getUIContext().getHostContext()
      if (!context) return point
      const points = await map.rectifyCoordinate(context, [{
        coordinateType: mapCommon.CoordinateType.WGS84,
        location: point
      }])
      if (points && points.length > 0) return points[0].location
    } catch (_error) {
      // Fall back to the raw point if the SDK cannot rectify it.
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
      controller.moveCamera(map.newCameraPosition({ target: point, zoom: PREVIEW_ZOOM }))
    } catch (_error) {
      // Keep the current camera if the SDK rejects the update.
    }
    await this.updateMarker(point)
    this.applyMapNightMode()
  }

  private async updateMarker(point: mapCommon.LatLng): Promise<void> {
    const controller = this.controller
    if (!controller) return
    const icon = this.source === 'gps' ? $r('app.media.ic_map_pin_blue') : $r('app.media.ic_map_pin_red')
    try {
      if (this.marker) {
        this.marker.setPosition(point)
        await this.marker.setIcon(icon)
      } else {
        this.marker = await controller.addMarker({ position: point, icon: icon })
      }
    } catch (_error) {
      // Keep the draft even if the marker layer is unavailable.
    }
  }

  private badgeText(): ResourceStr {
    if (this.mapReady) return I18n.t('map_preview_terrain')
    if (this.planet === 'Earth') return I18n.t('map_preview_offline')
    return I18n.t('map_preview_planet')
  }

  private pinLeft(): number {
    const x = (this.longitude + 180) / 360 * this.previewWidth - 12
    return Math.max(0, Math.min(this.previewWidth - 24, Math.round(x)))
  }

  private pinTop(): number {
    const y = (90 - this.latitude) / 180 * this.previewHeight - 32
    return Math.max(0, Math.min(this.previewHeight - 32, Math.round(y)))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Offline base stays underneath the live map so the card never flashes
      // empty while Map Kit is loading or when it falls back.
      if (this.planet === 'Earth') {
        Image($rawfile('worldmap.jpg'))
          .width('100%').height('100%').objectFit(ImageFit.Fill)
          .hitTestBehavior(HitTestMode.None)
      } else if (this.texture.length > 0) {
        Image($rawfile('stellarium/textures/' + this.texture))
          .width('100%').height('100%').objectFit(ImageFit.Fill)
          .sourceSize({ width: 1240, height: 620 })
          .hitTestBehavior(HitTestMode.None)
      } else {
        Text(I18n.t('m_planet_map_unavailable')).fontSize(12).fontColor(this.c.sub)
          .width('76%').textAlign(TextAlign.Center)
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.mapStarted && !this.mapFailed) {
        MapComponent({ mapOptions: this.options, mapCallback: this.callback })
          .width('100%').height('100%')
          // Static preview: never intercept the panel's scroll or taps.
          .hitTestBehavior(HitTestMode.None)
      }
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.mapReady ? this.c.mapNightTint : this.c.nightMask)
        .hitTestBehavior(HitTestMode.None)
      // Equirectangular graticule labels only make sense on the offline globe.
      if (!this.mapReady) {
        Text('N').fontSize(10).fontColor(this.c.sub).position({ x: 6, y: 4 })
          .hitTestBehavior(HitTestMode.None)
        Text('S').fontSize(10).fontColor(this.c.sub).position({ x: 6, y: this.previewHeight - 16 })
          .hitTestBehavior(HitTestMode.None)
        Text('90°W').fontSize(10).fontColor(this.c.tertiary)
          .position({ x: 4, y: Math.round(this.previewHeight / 2) - 4 })
          .hitTestBehavior(HitTestMode.None)
        Text('90°E').fontSize(10).fontColor(this.c.tertiary)
          .position({ x: this.previewWidth - 32, y: Math.round(this.previewHeight / 2) - 4 })
          .hitTestBehavior(HitTestMode.None)
        Image(this.source === 'gps' ? $r('app.media.ic_map_pin_blue') : $r('app.media.ic_map_pin_red'))
          .width(24).height(32)
          .position({ x: this.pinLeft(), y: this.pinTop() })
          .hitTestBehavior(HitTestMode.None)
      }
      Text(this.badgeText())
        .fontSize(10).fontColor(this.c.text)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.c.panelGlassStrong)
        .borderRadius(UI_RADIUS_PILL)
        .position({ x: 8, y: 8 })
        .hitTestBehavior(HitTestMode.None)
      if (this.mapStarted && !this.mapReady && !this.mapFailed) {
        Row() {
          LoadingProgress().width(14).height(14).color(this.c.sub)
        }
          .width(24).height(24).justifyContent(FlexAlign.Center)
          .backgroundColor(this.c.panelGlassStrong)
          .borderRadius(12)
          .position({ x: this.previewWidth - 32, y: this.previewHeight - 32 })
          .hitTestBehavior(HitTestMode.None)
      }
      // Transparent full-card tap layer. The map is inert, so this layer owns
      // the tap and opens the full-screen picker; a drag still scrolls the
      // surrounding panel.
      Row()
        .width('100%').height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.onOpen() })
      Row() {
        Image($r('app.media.ic_fullscreen')).width(15).height(15)
          .supportSvg2(true).colorFilter(tintMatrixFor(this.c.text))
      }
        .width(30).height(30)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.c.panelGlassStrong)
        .border({ width: 1, color: this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
        .position({ x: this.previewWidth - 38, y: 8 })
        .zIndex(3)
        .onClick(() => { this.onOpen() })
        .accessibilityText(I18n.t('map_open_fullscreen'))
    }
      .width(this.previewWidth)
      .height(this.previewHeight)
      .alignSelf(ItemAlign.Center)
      .clip(true)
      .backgroundColor(this.c.mediaCard)
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 10 })
      .onClick(() => { this.onOpen() })
      .id('observer-planet-map')
  }
}
