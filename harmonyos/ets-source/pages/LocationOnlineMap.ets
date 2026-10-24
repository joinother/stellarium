import { map, mapCommon, MapComponent } from '@kit.MapKit'
import { AsyncCallback, BusinessError } from '@ohos.base'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { Theme } from '@kit.ArkUI'
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent'
import { I18n } from './I18n'
import { inverseMapPoint, MapPoint, validMapPoint } from './MapCoordinate'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../state/StellariumTheme'

@Component
export struct LocationOnlineMap {
  @Prop @Watch('observerChanged') latitude: number = 0
  @Prop @Watch('observerChanged') longitude: number = 0
  onPick: (latitude: number, longitude: number) => void = () => {}
  onFallback: () => void = () => {}
  @State private prepared: boolean = false
  @State private phase: string = 'loading'
  @State private errorCode: string = ''
  @State private c: ThemeSlots = DEFAULT_SLOTS
  private alive: boolean = false
  private generation: number = 0
  private timeoutId: number = -1
  private controller?: map.MapComponentController
  private options: mapCommon.MapOptions = {
    position: { target: { latitude: 0, longitude: 0 }, zoom: 5 },
    rotateGesturesEnabled: false, tiltGesturesEnabled: false,
    myLocationControlsEnabled: false, zoomControlsEnabled: true
  }
  private callback: AsyncCallback<map.MapComponentController> = (error: BusinessError, controller: map.MapComponentController): void => {
    if (!this.allowed()) return
    if (error) { this.fail(String(error.code), 'map-create'); return }
    this.controller = controller
    const events = controller.getEventManager()
    events.on('mapLoad', () => {
      if (!this.allowed()) return
      this.clearTimeout()
      this.publish('ready')
    })
    events.on('mapClick', (position: mapCommon.LatLng) => { this.pickMapPosition(position) })
    events.on('error', (error: BusinessError) => { this.fail(String(error.code), 'map-load') })
  }

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private allowed(): boolean {
    return this.alive && hasCurrentPrivacyConsent()
  }

  private publish(phase: string, error: string = '', operation: string = ''): void {
    this.phase = phase
    this.errorCode = error
    AppStorage.setOrCreate('stellariumLocationMapState', JSON.stringify({
      ok: true, provider: 'huawei', phase: phase, error: error, operation: operation,
      observerCoordinateSystem: 'WGS84'
    }))
    hilog.info(0x0000, 'StellariumMap', 'phase=%{public}s operation=%{public}s code=%{public}s', phase, operation, error)
  }

  private clearTimeout(): void {
    if (this.timeoutId >= 0) clearTimeout(this.timeoutId)
    this.timeoutId = -1
  }

  private fail(code: string, operation: string = ''): void {
    if (!this.alive) return
    this.clearTimeout()
    this.generation++
    this.prepared = false
    this.controller = undefined
    this.publish('error', code, operation)
  }

  private failRequest(error: BusinessError, operation: string): void {
    const code = Number(error.code)
    this.fail(Number.isFinite(code) ? code.toString() : 'unknown', operation)
  }

  aboutToAppear(): void {
    this.alive = true
    this.publish('loading')
    this.timeoutId = setTimeout(() => { this.fail('timeout') }, 15000)
    this.prepare()
  }

  aboutToDisappear(): void {
    this.alive = false
    this.generation++
    this.clearTimeout()
    this.controller = undefined
    this.publish('closed')
  }

  private async rectify(point: MapPoint, type: mapCommon.CoordinateType): Promise<mapCommon.CoordinateLatLng> {
    if (!this.allowed() || !validMapPoint(point)) throw new Error('Map unavailable')
    const context = this.getUIContext().getHostContext()
    if (!context) throw new Error('No context')
    const points = await map.rectifyCoordinate(context, [{ coordinateType: type, location: point }])
    if (!points || points.length !== 1 || !validMapPoint(points[0].location)) throw new Error('Invalid conversion')
    return points[0]
  }

  private async prepare(): Promise<void> {
    const generation = ++this.generation
    try {
      const corrected = await this.rectify({ latitude: this.latitude, longitude: this.longitude }, mapCommon.CoordinateType.WGS84)
      if (!this.allowed() || generation !== this.generation) return
      this.options.position.target = corrected.location
      this.prepared = true
    } catch (error) { if (generation === this.generation) this.failRequest(error as BusinessError, 'initialization') }
  }

  private async observerChanged(): Promise<void> {
    if (!this.controller || !this.allowed()) return
    const generation = ++this.generation
    try {
      const corrected = await this.rectify({ latitude: this.latitude, longitude: this.longitude }, mapCommon.CoordinateType.WGS84)
      if (!this.allowed() || generation !== this.generation) return
      this.controller?.moveCamera(map.newLatLng(corrected.location))
    } catch (error) { if (generation === this.generation) this.failRequest(error as BusinessError, 'observer-coordinate') }
  }

  private async pickMapPosition(position: mapCommon.LatLng): Promise<void> {
    if (!this.allowed() || this.phase !== 'ready' || !validMapPoint(position)) return
    const generation = ++this.generation
    this.publish('converting')
    this.timeoutId = setTimeout(() => { this.fail('coordinate-timeout') }, 10000)
    try {
      const routing = await this.rectify(position, mapCommon.CoordinateType.GCJ02)
      if (!this.allowed() || generation !== this.generation) return
      const result = routing.coordinateType === mapCommon.CoordinateType.WGS84 ? position :
        inverseMapPoint(position, (point: MapPoint): MapPoint =>
          map.convertCoordinateSync(mapCommon.CoordinateType.WGS84, mapCommon.CoordinateType.GCJ02, point))
      if (!validMapPoint(result)) throw new Error('Coordinate conversion failed')
      this.clearTimeout()
      this.publish('ready')
      this.onPick(result.latitude, result.longitude)
    } catch (error) { if (generation === this.generation) this.failRequest(error as BusinessError, 'pick-coordinate') }
  }

  private async chooseCenter(): Promise<void> {
    if (!this.allowed() || this.phase !== 'ready' || !this.controller) return
    const generation = ++this.generation
    this.publish('converting')
    this.timeoutId = setTimeout(() => { this.fail('coordinate-timeout') }, 10000)
    try {
      const target = this.controller.getCameraPosition().target
      const routing = await this.rectify(target, mapCommon.CoordinateType.GCJ02)
      if (!this.allowed() || generation !== this.generation) return
      const result = routing.coordinateType === mapCommon.CoordinateType.WGS84 ? target :
        inverseMapPoint(target, (point: MapPoint): MapPoint =>
          map.convertCoordinateSync(mapCommon.CoordinateType.WGS84, mapCommon.CoordinateType.GCJ02, point))
      const verified = await this.rectify(result, mapCommon.CoordinateType.WGS84)
      if (!this.allowed() || generation !== this.generation) return
      if (Math.max(Math.abs(verified.location.latitude - target.latitude),
        Math.abs(verified.location.longitude - target.longitude)) > 0.000002) throw new Error('Coordinate mismatch')
      this.clearTimeout()
      this.publish('ready')
      this.onPick(result.latitude, result.longitude)
    } catch (error) { if (generation === this.generation) this.failRequest(error as BusinessError, 'center-coordinate') }
  }

  build() {
    Column({ space: 8 }) {
      if (this.prepared) {
        Stack() {
          MapComponent({ mapOptions: this.options, mapCallback: this.callback })
            .width('100%').height('100%')
          Row()
            .width('100%')
            .height('100%')
            .backgroundColor(this.c.nightMask)
            .hitTestBehavior(HitTestMode.None)
          Text('+').fontSize(28).fontColor(this.c.tertiary).hitTestBehavior(HitTestMode.None)
        }.height(240).width('100%').clip(true).borderRadius(14)
      }
      if (this.phase === 'loading' || this.phase === 'converting') {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).color(this.c.sub)
          Text(I18n.t('map_online_loading')).fontSize(12).fontColor(this.c.sub)
        }.width('100%')
      } else if (this.phase === 'error') {
        Text(I18n.t('map_online_failed')).fontSize(12).fontColor(this.c.errorText).width('100%')
        Text(this.errorCode).fontSize(11).fontColor(this.c.sub).width('100%')
      }
      Row({ space: 8 }) {
        Button(I18n.t('map_online_choose')).layoutWeight(1).fontSize(12)
          .enabled(this.phase === 'ready').onClick(() => { this.chooseCenter() })
        Button(I18n.t('map_offline')).layoutWeight(1).fontSize(12)
          .onClick(() => { this.onFallback() })
      }.width('100%')
    }.width('100%').margin({ top: 10 })
  }
}
