import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyCalendarEvent, CalendarEclipseMapData } from '../../state/AstronomyCalendarEvent'
import { calendarText } from '../../state/AstronomyCalendarText'
import { UI_RADIUS_CARD, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 日食 / 月食全球可见区域地图卡片（基于真实贝塞尔食带网格与月下点球面几何绘制，
// 叠加离线世界底图、当前定位蓝点，支持点击全屏双指缩放查看）。
@Component
export struct CalendarEclipseMapCard {
  @Prop event: AstronomyCalendarEvent | undefined = undefined
  @Prop mapData: CalendarEclipseMapData | undefined = undefined
  @Prop language: string = 'zh'
  @Prop observerLat: number = 39.9
  @Prop observerLon: number = 116.4
  @Prop earthMapUri: string = ''
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private zoomOpen: boolean = false
  @State private zoomScale: number = 1.0
  @State private baseZoomScale: number = 1.0
  @State private panX: number = 0
  @State private panY: number = 0
  @State private basePanX: number = 0
  @State private basePanY: number = 0

  private inlineSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private inlineCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.inlineSettings)
  private modalSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private modalCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.modalSettings)

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private t(zh: string, en: string): string {
    return calendarText(this.language, zh, en)
  }

  private drawOverlay(ctx: CanvasRenderingContext2D): void {
    const w = ctx.width
    const h = ctx.height
    if (w <= 2 || h <= 2) return
    ctx.clearRect(0, 0, w, h)
    const data = this.mapData
    if (data === undefined) return

    // 柔和的海洋与经纬格网润色层，使底图呈干净的制图质感
    ctx.fillStyle = this.c.isNight ? 'rgba(22, 8, 8, 0.34)' : 'rgba(130, 152, 182, 0.24)'
    ctx.fillRect(0, 0, w, h)

    if (data.kind === 'lunar' && Array.isArray(data.subLunarPoints) && data.subLunarPoints.length > 0) {
      this.drawLunarVisibility(ctx, w, h, data.subLunarPoints)
    } else if (data.kind === 'solar') {
      this.drawSolarVisibility(ctx, w, h, data)
    }

    // 经纬参考细线
    ctx.strokeStyle = this.c.isNight ? 'rgba(255,140,120,0.10)' : 'rgba(255,255,255,0.14)'
    ctx.lineWidth = 0.6
    ctx.beginPath()
    ctx.moveTo(0, h * 0.5)
    ctx.lineTo(w, h * 0.5)
    ctx.moveTo(w * 0.5, 0)
    ctx.lineTo(w * 0.5, h)
    ctx.stroke()

    // 当前观测位置蓝点（带白色外圈）
    if (Number.isFinite(this.observerLat) && Number.isFinite(this.observerLon)) {
      const px = ((this.observerLon + 180) / 360) * w
      const py = ((90 - this.observerLat) / 180) * h
      ctx.beginPath()
      ctx.arc(px, py, Math.max(4.8, w * 0.015), 0, Math.PI * 2)
      ctx.fillStyle = 'rgba(255, 255, 255, 0.92)'
      ctx.fill()
      ctx.beginPath()
      ctx.arc(px, py, Math.max(3.4, w * 0.011), 0, Math.PI * 2)
      ctx.fillStyle = this.c.isNight ? '#FF6B4A' : '#2979FF'
      ctx.fill()
    }
  }

  private drawLunarVisibility(ctx: CanvasRenderingContext2D, w: number, h: number, subPts: number[][]): void {
    const cols = 144
    const rows = 72
    const deg2rad = Math.PI / 180
    const n = subPts.length
    const sinSLat: number[] = []
    const cosSLat: number[] = []
    const sLonRad: number[] = []
    for (let i = 0; i < n; i++) {
      const pt = subPts[i]
      const latR = (pt[0] ?? 0) * deg2rad
      sinSLat.push(Math.sin(latR))
      cosSLat.push(Math.cos(latR))
      sLonRad.push((pt[1] ?? 0) * deg2rad)
    }
    const uStart = n >= 5 ? 1 : 0
    const uEnd = n >= 5 ? 3 : (n - 1)
    const midIdx = Math.floor(n / 2)

    for (let r = 0; r < rows; r++) {
      const y0 = Math.floor((r * h) / rows)
      const y1 = Math.floor(((r + 1) * h) / rows)
      const cellH = Math.max(1, y1 - y0)
      const latR = (90 - ((r + 0.5) / rows) * 180) * deg2rad
      const sinLat = Math.sin(latR)
      const cosLat = Math.cos(latR)
      for (let c = 0; c < cols; c++) {
        const lonR = (-180 + ((c + 0.5) / cols) * 360) * deg2rad
        let visCount = 0
        let mainVisCount = 0
        let midVis = false
        for (let k = 0; k < n; k++) {
          const sinAlt = sinLat * sinSLat[k] + cosLat * cosSLat[k] * Math.cos(lonR - sLonRad[k])
          if (sinAlt >= -0.008) {
            visCount++
            if (k >= uStart && k <= uEnd) mainVisCount++
            if (k === midIdx) midVis = true
          }
        }
        const mainTotal = uEnd - uStart + 1
        if (mainVisCount === mainTotal) {
          ctx.fillStyle = this.c.isNight ? 'rgba(220, 62, 42, 0.72)' : 'rgba(205, 86, 54, 0.70)'
        } else if (midVis || mainVisCount > 0) {
          ctx.fillStyle = this.c.isNight ? 'rgba(200, 74, 52, 0.44)' : 'rgba(218, 122, 88, 0.44)'
        } else if (visCount > 0) {
          ctx.fillStyle = this.c.isNight ? 'rgba(180, 82, 60, 0.24)' : 'rgba(224, 152, 124, 0.26)'
        } else {
          ctx.fillStyle = this.c.isNight ? 'rgba(20, 10, 12, 0.36)' : 'rgba(78, 104, 140, 0.34)'
        }
        const x0 = Math.floor((c * w) / cols)
        const x1 = Math.floor(((c + 1) * w) / cols)
        ctx.fillRect(x0, y0, Math.max(1, x1 - x0), cellH)
      }
    }
  }

  private drawSolarVisibility(ctx: CanvasRenderingContext2D, w: number, h: number, data: CalendarEclipseMapData): void {
    const cols = data.cols ?? 72
    const rows = data.rows ?? 36
    const grid = data.grid ?? ''
    if (grid.length === cols * rows) {
      for (let r = 0; r < rows; r++) {
        const y0 = Math.floor((r * h) / rows)
        const y1 = Math.floor(((r + 1) * h) / rows)
        const cellH = Math.max(1, y1 - y0)
        for (let c = 0; c < cols; c++) {
          const chCode = grid.charAt(r * cols + c)
          if (chCode === '0') continue
          if (chCode === '3') {
            ctx.fillStyle = this.c.isNight ? 'rgba(220, 72, 52, 0.68)' : 'rgba(30, 38, 52, 0.66)'
          } else if (chCode === '2') {
            ctx.fillStyle = this.c.isNight ? 'rgba(180, 60, 44, 0.48)' : 'rgba(54, 66, 86, 0.50)'
          } else {
            ctx.fillStyle = this.c.isNight ? 'rgba(150, 52, 38, 0.32)' : 'rgba(72, 86, 108, 0.36)'
          }
          const x0 = Math.floor((c * w) / cols)
          const x1 = Math.floor(((c + 1) * w) / cols)
          ctx.fillRect(x0, y0, Math.max(1, x1 - x0), cellH)
        }
      }
    }

    // 中心食带（全食带 / 环食带）平滑曲线，跨 180° 日界线自动断开
    const path = data.centralPath ?? []
    if (path.length >= 2) {
      const drawPath = (strokeColor: string, widthPx: number): void => {
        ctx.strokeStyle = strokeColor
        ctx.lineWidth = widthPx
        ctx.lineCap = 'round'
        ctx.lineJoin = 'round'
        ctx.beginPath()
        let started = false
        let prevLon = 0
        for (let i = 0; i < path.length; i++) {
          const pt = path[i]
          const lat = pt[0] ?? 0
          const lon = pt[1] ?? 0
          const x = ((lon + 180) / 360) * w
          const y = ((90 - lat) / 180) * h
          if (!started || Math.abs(lon - prevLon) > 90) {
            ctx.moveTo(x, y)
            started = true
          } else {
            ctx.lineTo(x, y)
          }
          prevLon = lon
        }
        ctx.stroke()
      }
      drawPath(this.c.isNight ? 'rgba(255, 160, 130, 0.55)' : 'rgba(255, 255, 255, 0.42)', Math.max(4.0, w * 0.012))
      drawPath(this.c.isNight ? '#FF7043' : '#18202E', Math.max(2.2, w * 0.007))
    }
  }

  @Builder
  mapCanvasLayer(isModal: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.earthMapUri.length > 0) {
        Image(this.earthMapUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .saturate(this.c.isNight ? 0.15 : 0.35)
          .brightness(this.c.isNight ? 0.45 : 1.18)
          .contrast(0.88)
          .accessibilityLevel('no')
      } else {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.c.isNight ? '#1A0808' : '#7D93AE')
      }
      Canvas(isModal ? this.modalCtx : this.inlineCtx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.drawOverlay(isModal ? this.modalCtx : this.inlineCtx)
        })
    }
      .width('100%')
      .aspectRatio(2.0)
      .clip(true)
  }

  @Builder
  zoomModalBuilder() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 14 }) {
        Blank()
        Stack({ alignContent: Alignment.Center }) {
          this.mapCanvasLayer(true)
        }
          .width('100%')
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .translate({ x: this.panX, y: this.panY })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart(() => { this.baseZoomScale = this.zoomScale })
                .onActionUpdate((ev: GestureEvent) => {
                  this.zoomScale = Math.max(1.0, Math.min(4.0, this.baseZoomScale * ev.scale))
                  if (this.zoomScale <= 1.02) { this.panX = 0; this.panY = 0 }
                }),
              PanGesture({ fingers: 1 })
                .onActionStart(() => { this.basePanX = this.panX; this.basePanY = this.panY })
                .onActionUpdate((ev: GestureEvent) => {
                  if (this.zoomScale <= 1.02) return
                  const maxPan = 220 * (this.zoomScale - 1)
                  this.panX = Math.max(-maxPan, Math.min(maxPan, this.basePanX + ev.offsetX))
                  this.panY = Math.max(-maxPan * 0.6, Math.min(maxPan * 0.6, this.basePanY + ev.offsetY))
                })
            )
          )
          .onClick(() => {
            if (this.zoomScale > 1.2) {
              this.zoomScale = 1.0; this.panX = 0; this.panY = 0
            } else {
              this.zoomScale = 2.2
            }
          })
        Text(this.t('双指缩放或轻点放大 · 蓝点为当前观测位置', 'Pinch or tap to zoom · Blue dot marks your location'))
          .fontSize(12)
          .fontColor('#B8C4DA')
        Blank()
      }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 48, bottom: 32 })
        .backgroundColor('rgba(6, 9, 16, 0.96)')

      Button('✕', { type: ButtonType.Circle })
        .width(40)
        .height(40)
        .fontSize(16)
        .fontColor('#F3F5FA')
        .backgroundColor('rgba(255, 255, 255, 0.14)')
        .margin({ top: 44, right: 20 })
        .onClick(() => {
          this.zoomOpen = false
          this.zoomScale = 1.0
          this.panX = 0
          this.panY = 0
        })
    }
      .width('100%')
      .height('100%')
  }

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.mapCanvasLayer(false)
        Text(this.t('点击放大', 'Tap to zoom'))
          .fontSize(10)
          .fontColor('#EEF3FC')
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor('rgba(10, 14, 24, 0.68)')
          .borderRadius(UI_RADIUS_PILL)
          .margin({ right: 8, bottom: 8 })
          .hitTestBehavior(HitTestMode.None)
      }
        .width('100%')
        .borderRadius(UI_RADIUS_CARD)
        .border({ width: 0.8, color: this.c.border })
        .clip(true)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => { this.zoomOpen = true })
        .bindContentCover(this.zoomOpen, this.zoomModalBuilder(), {
          modalTransition: ModalTransition.DEFAULT,
          onDisappear: () => { this.zoomOpen = false }
        })

      Row({ space: 12 }) {
        if (this.mapData?.kind === 'lunar') {
          Row({ space: 5 }) {
            Row().width(10).height(10).borderRadius(2).backgroundColor(this.c.isNight ? '#DC3E2A' : '#CD5636')
            Text(this.t('全程可见', 'Full eclipse')).fontSize(11).fontColor(this.c.sub)
          }
          Row({ space: 5 }) {
            Row().width(10).height(10).borderRadius(2).backgroundColor(this.c.isNight ? '#C84A34' : '#DA7A58')
            Text(this.t('月出/月落带食', 'Rise/set')).fontSize(11).fontColor(this.c.sub)
          }
        } else {
          Row({ space: 5 }) {
            Row().width(12).height(3).borderRadius(2).backgroundColor(this.c.isNight ? '#FF7043' : '#18202E')
            Text(this.t('中心食带', 'Central path')).fontSize(11).fontColor(this.c.sub)
          }
          Row({ space: 5 }) {
            Row().width(10).height(10).borderRadius(2).backgroundColor(this.c.isNight ? '#963426' : '#48566C')
            Text(this.t('日偏食区', 'Partial')).fontSize(11).fontColor(this.c.sub)
          }
        }
        Row({ space: 5 }) {
          Row().width(9).height(9).borderRadius(5).backgroundColor(this.c.isNight ? '#FF6B4A' : '#2979FF')
            .border({ width: 1.5, color: '#FFFFFF' })
          Text(this.t('当前位置', 'You')).fontSize(11).fontColor(this.c.sub)
        }
      }
        .width('100%')
        .padding({ left: 2, right: 2 })
    }
      .width('100%')
  }
}

// 行星大距（水星 / 金星东大距 & 西大距）高架俯视轨道几何示意图：
// 展示太阳、地球与内行星轨道及相切距角几何关系。
@Component
export struct CalendarElongationOrbitCard {
  @Prop planetName: string = 'Mercury'
  @Prop elongationDirection: string = 'east'
  @Prop separationDegrees: number = 22
  @Prop orbitRatio: number = 0.387
  @Prop language: string = 'zh'
  @State private c: ThemeSlots = DEFAULT_SLOTS

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private drawOrbit(): void {
    const ctx = this.ctx
    const w = ctx.width
    const h = ctx.height
    if (w <= 2 || h <= 2) return
    ctx.clearRect(0, 0, w, h)

    // 深空紫红渐变背景
    const bg = ctx.createRadialGradient(w * 0.5, h * 0.5, 4, w * 0.5, h * 0.5, w * 0.65)
    if (this.c.isNight) {
      bg.addColorStop(0, '#380D0B')
      bg.addColorStop(1, '#120303')
    } else {
      bg.addColorStop(0, '#441236')
      bg.addColorStop(0.55, '#260A24')
      bg.addColorStop(1, '#100716')
    }
    ctx.fillStyle = bg
    ctx.fillRect(0, 0, w, h)

    const cx = w * 0.50
    const cy = h * 0.52
    const rxEarth = w * 0.39
    const ryEarth = h * 0.30
    const ratio = Math.max(0.32, Math.min(0.76, this.orbitRatio))
    const rxInner = rxEarth * ratio
    const ryInner = ryEarth * ratio

    // 轨道椭圆（外圈地球、内圈水星/金星）
    ctx.strokeStyle = this.c.isNight ? 'rgba(255,160,140,0.28)' : 'rgba(205, 198, 240, 0.32)'
    ctx.lineWidth = 1.2
    ctx.beginPath()
    ctx.ellipse(cx, cy, rxEarth, ryEarth, 0, 0, Math.PI * 2)
    ctx.stroke()

    ctx.strokeStyle = this.c.isNight ? 'rgba(255,190,160,0.42)' : 'rgba(218, 210, 250, 0.46)'
    ctx.beginPath()
    ctx.ellipse(cx, cy, rxInner, ryInner, 0, 0, Math.PI * 2)
    ctx.stroke()

    // 将地球固定在左前方视角，内行星按真实距角切点位于太阳左侧（东大距）或右侧（西大距）
    const earthAngle = Math.PI * 0.78
    const ex = cx + rxEarth * Math.cos(earthAngle)
    const ey = cy + ryEarth * Math.sin(earthAngle)
    const tangentOffset = Math.acos(ratio)
    const planetAngle = this.elongationDirection === 'west'
      ? (earthAngle - tangentOffset)
      : (earthAngle + tangentOffset)
    const px = cx + rxInner * Math.cos(planetAngle)
    const py = cy + ryInner * Math.sin(planetAngle)

    // 地球夜侧柔和影锥（背离太阳方向）
    const dxSun = ex - cx
    const dySun = ey - cy
    const dNorm = Math.max(1, Math.hypot(dxSun, dySun))
    const ux = dxSun / dNorm
    const uy = dySun / dNorm
    const nx = -uy
    const ny = ux
    const earthR = Math.max(10, Math.min(15, h * 0.088))
    const shadowGrad = ctx.createLinearGradient(ex, ey, ex + ux * w * 0.22, ey + uy * w * 0.22)
    shadowGrad.addColorStop(0, 'rgba(6, 5, 14, 0.72)')
    shadowGrad.addColorStop(1, 'rgba(6, 5, 14, 0.0)')
    ctx.fillStyle = shadowGrad
    ctx.beginPath()
    ctx.moveTo(ex + nx * earthR * 0.92, ey + ny * earthR * 0.92)
    ctx.lineTo(ex + ux * w * 0.24 + nx * earthR * 1.4, ey + uy * w * 0.24 + ny * earthR * 1.4)
    ctx.lineTo(ex + ux * w * 0.24 - nx * earthR * 1.4, ey + uy * w * 0.24 - ny * earthR * 1.4)
    ctx.lineTo(ex - nx * earthR * 0.92, ey - ny * earthR * 0.92)
    ctx.closePath()
    ctx.fill()

    // 地球→行星 与 地球→太阳 距角连线
    ctx.strokeStyle = this.c.isNight ? 'rgba(255, 196, 172, 0.36)' : 'rgba(186, 214, 255, 0.38)'
    ctx.lineWidth = 1.0
    ctx.setLineDash([4, 4])
    ctx.beginPath()
    ctx.moveTo(ex, ey)
    ctx.lineTo(px, py)
    ctx.moveTo(ex, ey)
    ctx.lineTo(cx, cy)
    ctx.stroke()
    ctx.setLineDash([])

    // 中心耀眼太阳
    const sunR = Math.max(14, Math.min(20, h * 0.115))
    const sunGlow = ctx.createRadialGradient(cx, cy, sunR * 0.2, cx, cy, sunR * 2.5)
    sunGlow.addColorStop(0, this.c.isNight ? '#FFE0C2' : '#FFFDF2')
    sunGlow.addColorStop(0.38, this.c.isNight ? '#FF7A45' : '#FFD36E')
    sunGlow.addColorStop(0.70, this.c.isNight ? 'rgba(220,68,36,0.28)' : 'rgba(255,156,56,0.26)')
    sunGlow.addColorStop(1, 'rgba(255,140,40,0.0)')
    ctx.fillStyle = sunGlow
    ctx.beginPath()
    ctx.arc(cx, cy, sunR * 2.5, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = this.c.isNight ? '#FFD8BA' : '#FFF8DC'
    ctx.beginPath()
    ctx.arc(cx, cy, sunR * 0.85, 0, Math.PI * 2)
    ctx.fill()

    // 地球（朝太阳侧亮蓝、背太阳侧暗影）
    const earthGrad = ctx.createRadialGradient(
      ex - ux * earthR * 0.45, ey - uy * earthR * 0.45, earthR * 0.15, ex, ey, earthR * 1.1)
    earthGrad.addColorStop(0, this.c.isNight ? '#D4806E' : '#85BEFF')
    earthGrad.addColorStop(0.55, this.c.isNight ? '#6E261E' : '#2E568D')
    earthGrad.addColorStop(1, '#0C1222')
    ctx.fillStyle = earthGrad
    ctx.beginPath()
    ctx.arc(ex, ey, earthR, 0, Math.PI * 2)
    ctx.fill()

    // 内行星（水星灰银 / 金星暖金，半亮相位）
    const pR = Math.max(6, Math.min(9, h * 0.052))
    const dpNorm = Math.max(1, Math.hypot(px - cx, py - cy))
    const pux = (px - cx) / dpNorm
    const puy = (py - cy) / dpNorm
    const pGrad = ctx.createRadialGradient(
      px - pux * pR * 0.45, py - puy * pR * 0.45, pR * 0.1, px, py, pR * 1.15)
    if (this.planetName === 'Venus') {
      pGrad.addColorStop(0, this.c.isNight ? '#FFD2B5' : '#FFF0C4')
      pGrad.addColorStop(0.6, this.c.isNight ? '#964632' : '#C9A462')
      pGrad.addColorStop(1, '#26181A')
    } else {
      pGrad.addColorStop(0, this.c.isNight ? '#E8B8AC' : '#DFE5EF')
      pGrad.addColorStop(0.6, this.c.isNight ? '#763A32' : '#828B9C')
      pGrad.addColorStop(1, '#1A1C28')
    }
    ctx.fillStyle = pGrad
    ctx.beginPath()
    ctx.arc(px, py, pR, 0, Math.PI * 2)
    ctx.fill()

    // 右上角距角角标
    const degLabel = `${Math.round(this.separationDegrees)}°`
    ctx.font = 'bold 12px sans-serif'
    ctx.fillStyle = this.c.isNight ? 'rgba(255,210,190,0.88)' : 'rgba(232,240,255,0.88)'
    ctx.fillText(degLabel, w - 42, 22)
  }

  build() {
    Column({ space: 6 }) {
      Canvas(this.ctx)
        .width('100%')
        .aspectRatio(1.72)
        .borderRadius(UI_RADIUS_CARD)
        .border({ width: 0.8, color: this.c.border })
        .clip(true)
        .onReady(() => { this.drawOrbit() })

      Text(calendarText(
        this.language,
        this.elongationDirection === 'west' ? '从高架轨道角度观察到的西大距' : '从高架轨道角度观察到的东大距',
        this.elongationDirection === 'west' ? 'Overhead orbital view of greatest western elongation' : 'Overhead orbital view of greatest eastern elongation'
      ))
        .fontSize(11)
        .fontColor(this.c.sub)
        .width('100%')
    }
      .width('100%')
  }
}
