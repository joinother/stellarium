import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// Equirectangular fallback map. Works without Map Kit, network, AGC or Petal
// Maps: the image is a rawfile texture, the marker is projected with the same
// lat/lon -> pixel mapping used by the desktop LocationDialog. Pan/zoom keeps
// the pixel <-> coordinate transform in sync, so direct picking stays accurate.
@Component
export struct LocationRasterMap {
  @Prop imagePath: string = ''
  @Prop latitude: number = 0
  @Prop longitude: number = 0
  @Prop interactive: boolean = false
  @Prop preserveAspect: boolean = true
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private mapWidth: number = 0
  @State private mapHeight: number = 0
  @State private zoom: number = 1
  @State private panX: number = 0
  @State private panY: number = 0
  @State private startPanX: number = 0
  @State private startPanY: number = 0
  @State private startZoom: number = 1
  onPick: (latitude: number, longitude: number) => void = () => {}
  onOpenFull: () => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private baseWidth(): number {
    if (!this.preserveAspect) return this.mapWidth
    return Math.min(this.mapWidth, this.mapHeight * 2)
  }

  private baseHeight(): number {
    if (!this.preserveAspect) return this.mapHeight
    return this.baseWidth() / 2
  }

  private imageWidth(): number {
    return this.baseWidth() * this.zoom
  }

  private imageHeight(): number {
    return this.baseHeight() * this.zoom
  }

  private imageLeft(): number {
    return (this.mapWidth - this.imageWidth()) / 2 + this.panX
  }

  private imageTop(): number {
    return (this.mapHeight - this.imageHeight()) / 2 + this.panY
  }

  private markerX(): number {
    return this.imageLeft() + (this.longitude + 180) / 360 * this.imageWidth()
  }

  private markerY(): number {
    return this.imageTop() + (90 - this.latitude) / 180 * this.imageHeight()
  }

  private setZoom(next: number): void {
    this.zoom = Math.max(1, Math.min(8, next))
    if (this.zoom === 1) {
      this.panX = 0
      this.panY = 0
    }
  }

  private handleClick(event: ClickEvent): void {
    if (!this.interactive) {
      this.onOpenFull()
      return
    }
    const width = this.imageWidth()
    const height = this.imageHeight()
    if (width <= 0 || height <= 0) return
    const x = event.x - this.imageLeft()
    const y = event.y - this.imageTop()
    if (x < 0 || y < 0 || x > width || y > height) return
    const lon = Math.max(-180, Math.min(180, x / width * 360 - 180))
    const lat = Math.max(-90, Math.min(90, 90 - y / height * 180))
    this.onPick(lat, lon)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.imagePath.length > 0) {
        Image($rawfile(this.imagePath))
          .width(this.imageWidth()).height(this.imageHeight())
          .position({ x: this.imageLeft(), y: this.imageTop() })
          .objectFit(ImageFit.Fill)
          .interpolation(ImageInterpolation.High)
          .hitTestBehavior(HitTestMode.None)
      } else {
        Column() {
          Text(I18n.t('m_planet_map_unavailable')).fontSize(11).fontColor(this.c.tertiary)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      }
      if (this.mapWidth > 0 && this.mapHeight > 0) {
        Text('●')
          .fontSize(16)
          .fontColor(this.c.accent)
          .position({ x: this.markerX() - 8, y: this.markerY() - 8 })
          .hitTestBehavior(HitTestMode.None)
      }
      if (!this.interactive) {
        Text(I18n.t('map_open_fullscreen')).fontSize(10).fontColor(this.c.onAccent)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.c.accent)
          .borderRadius(4)
          .position({ x: 8, y: 8 })
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.interactive) {
        Column({ space: 8 }) {
          Text('+').fontSize(22).fontColor(this.c.text).width(40).height(40)
            .textAlign(TextAlign.Center).backgroundColor(this.c.panelGlassStrong)
            .borderRadius(20)
            .onClick(() => { this.setZoom(this.zoom * 1.5) })
          Text('−').fontSize(24).fontColor(this.c.text).width(40).height(40)
            .textAlign(TextAlign.Center).backgroundColor(this.c.panelGlassStrong)
            .borderRadius(20)
            .onClick(() => { this.setZoom(this.zoom / 1.5) })
        }
          .position({ x: 12, y: 150 })
          .zIndex(2)
      }
    }
      .width('100%').height('100%')
      .backgroundColor('#FF0B0F14')
      .clip(true)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const width = Number(newArea.width)
        const height = Number(newArea.height)
        if (width !== this.mapWidth) this.mapWidth = width
        if (height !== this.mapHeight) this.mapHeight = height
      })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PanGesture({ direction: PanDirection.All })
            .onActionStart(() => {
              this.startPanX = this.panX
              this.startPanY = this.panY
            })
            .onActionUpdate((event: GestureEvent) => {
              this.panX = this.startPanX + event.offsetX
              this.panY = this.startPanY + event.offsetY
            }),
          PinchGesture({ fingers: 2 })
            .onActionStart(() => { this.startZoom = this.zoom })
            .onActionUpdate((event: GestureEvent) => {
              this.setZoom(this.startZoom * event.scale)
            })
        )
      )
      .onClick((event: ClickEvent) => { this.handleClick(event) })
  }
}
