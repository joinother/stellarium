import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { uiFontSize } from '../../common/ui/UiTypography'
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

function parseHoursFromText(raw: string): number {
  const m = raw.match(/(\d{1,2}):(\d{2})/)
  if (m === null) return -1
  const h = Number(m[1])
  const min = Number(m[2])
  if (!Number.isFinite(h) || !Number.isFinite(min) || h < 0 || h > 23 || min < 0 || min > 59) return -1
  return h + min / 60.0
}

function shortClock(raw: string): string {
  const m = raw.match(/(\d{1,2}:\d{2})/)
  return m === null ? '—' : m[1]
}

// 24-hour Solar Diurnal Elevation & Twilight Path diagram for AstroCalc Almanac & Tonight tabs.
@Component
export struct SolarPathDiagramView {
  @Prop @Watch('redraw') sunRiseText: string = ''
  @Prop @Watch('redraw') sunTransitText: string = ''
  @Prop @Watch('redraw') sunSetText: string = ''
  @Prop @Watch('redraw') astroEndText: string = ''
  @Prop @Watch('redraw') astroStartText: string = ''
  @Prop daylightLabel: string = ''
  @Prop @Watch('redraw') nightMode: boolean = false
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0

  @State c: ThemeSlots = DEFAULT_SLOTS
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings)
  private canvasReady: boolean = false

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private fs(base: number): number {
    return uiFontSize(base, this.readableUi, this.uiFontScale)
  }

  private redraw(): void {
    if (!this.canvasReady) return
    const w = this.ctx.width > 0 ? this.ctx.width : 300
    const h = this.ctx.height > 0 ? this.ctx.height : 138
    this.ctx.clearRect(0, 0, w, h)

    const padL = 28
    const padR = 34
    const padT = 14
    const padB = 22
    const plotW = Math.max(80, w - padL - padR)
    const plotH = Math.max(50, h - padT - padB)

    // Parse sunrise / transit / sunset hours with clean analytical fallback
    let riseH = parseHoursFromText(this.sunRiseText)
    let setH = parseHoursFromText(this.sunSetText)
    let transitH = parseHoursFromText(this.sunTransitText)
    if (riseH < 0) riseH = 6.5
    if (setH < 0) setH = 17.5
    if (setH <= riseH) setH += 24.0
    if (transitH < 0) transitH = ((riseH + setH) * 0.5) % 24.0
    const halfDay = Math.max(1.5, Math.min(10.8, (setH - riseH) * 0.5))

    // Construct smooth diurnal solar elevation curve: alt(t) = mean + amp * cos((t - transitH) * pi / 12)
    const cosZero = Math.cos((halfDay / 12.0) * Math.PI)
    const amp = 44.0
    const meanAlt = -0.83 - amp * cosZero
    const evalAlt = (hr: number): number => meanAlt + amp * Math.cos(((hr - transitH) / 12.0) * Math.PI)

    // Dynamic vertical range so low winter/polar troughs never clip flat at bottom
    const lowestAlt = meanAlt - amp
    const highestAlt = meanAlt + amp
    const minAlt = Math.min(-42.0, lowestAlt - 5.0)
    const maxAlt = Math.max(66.0, highestAlt + 10.0)
    const altToY = (alt: number): number => {
      const clamped = Math.max(minAlt, Math.min(maxAlt, alt))
      return padT + ((maxAlt - clamped) / (maxAlt - minAlt)) * plotH
    }
    const hourToX = (hr: number): number => padL + (Math.max(0, Math.min(24, hr)) / 24.0) * plotW

    const y0 = altToY(0)
    const y6 = altToY(-6)
    const y12 = altToY(-12)
    const y18 = altToY(-18)

    // 1. Twilight & dark-night atmospheric bands
    this.ctx.fillStyle = this.nightMode ? '#14200606' : '#184478B8'
    this.ctx.fillRect(padL, padT, plotW, Math.max(0, y0 - padT))
    this.ctx.fillStyle = this.nightMode ? '#18360A0A' : '#26345292'
    this.ctx.fillRect(padL, y0, plotW, Math.max(0, y6 - y0))
    this.ctx.fillStyle = this.nightMode ? '#22280808' : '#321E3266'
    this.ctx.fillRect(padL, y6, plotW, Math.max(0, y12 - y6))
    this.ctx.fillStyle = this.nightMode ? '#2A1A0606' : '#3A111D42'
    this.ctx.fillRect(padL, y12, plotW, Math.max(0, y18 - y12))
    this.ctx.fillStyle = this.nightMode ? '#360F0404' : '#4A060B1E'
    this.ctx.fillRect(padL, y18, plotW, Math.max(0, (padT + plotH) - y18))

    // 2. Horizontal elevation guidelines (0°, -6°, -12°, -18°)
    const drawGuide = (alt: number, label: string, solid: boolean): void => {
      const y = altToY(alt)
      this.ctx.save()
      this.ctx.strokeStyle = solid
        ? (this.nightMode ? '#88E06060' : '#88CFE4FF')
        : (this.nightMode ? '#30C84848' : '#2C90B8E8')
      this.ctx.lineWidth = solid ? 1.0 : 0.65
      if (!solid) this.ctx.setLineDash([3, 3])
      this.ctx.beginPath()
      this.ctx.moveTo(padL, y)
      this.ctx.lineTo(padL + plotW, y)
      this.ctx.stroke()
      this.ctx.setLineDash([])
      this.ctx.font = '8.5vp sans-serif'
      this.ctx.fillStyle = this.nightMode ? '#B86464' : '#8AA8CC'
      this.ctx.textAlign = 'left'
      this.ctx.fillText(label, padL + plotW + 4, y + 3)
      this.ctx.restore()
    }
    drawGuide(0, '地平', true)
    drawGuide(-6, '', false)
    drawGuide(-12, '', false)
    drawGuide(-18, '暗夜', false)

    // Left vertical axis labels
    this.ctx.save()
    this.ctx.font = '8.5vp sans-serif'
    this.ctx.fillStyle = this.nightMode ? '#A85858' : '#7E9BC0'
    this.ctx.textAlign = 'right'
    this.ctx.fillText('+60°', padL - 4, altToY(60) + 3)
    this.ctx.fillText('0°', padL - 4, y0 + 3)
    this.ctx.fillText('-30°', padL - 4, altToY(-30) + 3)
    this.ctx.restore()

    // 3. Daylight golden dome fill above horizon
    const steps = 96
    this.ctx.save()
    this.ctx.beginPath()
    let started = false
    for (let i = 0; i <= steps; i++) {
      const hr = (i / steps) * 24.0
      const alt = evalAlt(hr)
      const x = hourToX(hr)
      const y = alt > 0 ? altToY(alt) : y0
      if (!started) {
        this.ctx.moveTo(x, y0)
        started = true
      }
      this.ctx.lineTo(x, y)
    }
    this.ctx.lineTo(hourToX(24), y0)
    this.ctx.closePath()
    const domeGrad = this.ctx.createLinearGradient(0, altToY(Math.max(10, evalAlt(transitH))), 0, y0)
    if (this.nightMode) {
      domeGrad.addColorStop(0.0, '#55FF6644')
      domeGrad.addColorStop(1.0, '#08FF6644')
    } else {
      domeGrad.addColorStop(0.0, '#62FFD166')
      domeGrad.addColorStop(1.0, '#08FFD166')
    }
    this.ctx.fillStyle = domeGrad
    this.ctx.fill()
    this.ctx.restore()

    // 4. Full 24h solar elevation stroke (gold above horizon, cool blue below)
    this.ctx.save()
    this.ctx.lineWidth = 2.0
    this.ctx.lineCap = 'round'
    for (let i = 0; i < steps; i++) {
      const h1 = (i / steps) * 24.0
      const h2 = ((i + 1) / steps) * 24.0
      const a1 = evalAlt(h1)
      const a2 = evalAlt(h2)
      const above = (a1 + a2) * 0.5 >= 0
      this.ctx.strokeStyle = above
        ? (this.nightMode ? '#FF7858' : '#FFD166')
        : (this.nightMode ? '#904040' : '#6498D8')
      this.ctx.beginPath()
      this.ctx.moveTo(hourToX(h1), altToY(a1))
      this.ctx.lineTo(hourToX(h2), altToY(a2))
      this.ctx.stroke()
    }
    this.ctx.restore()

    // 5. Sunrise / Transit / Sunset key nodes
    const drawKeyNode = (hr: number, alt: number, color: string): void => {
      const x = hourToX(hr)
      const y = altToY(alt)
      this.ctx.save()
      this.ctx.beginPath()
      this.ctx.arc(x, y, 3.2, 0, Math.PI * 2)
      this.ctx.fillStyle = color
      this.ctx.fill()
      this.ctx.restore()
    }
    drawKeyNode(riseH % 24, 0, this.nightMode ? '#FF8866' : '#FFB84D')
    drawKeyNode(transitH % 24, evalAlt(transitH % 24), this.nightMode ? '#FFA07A' : '#FFE488')
    drawKeyNode(setH % 24, 0, this.nightMode ? '#FF7058' : '#FF9654')

    // 6. Live current-time glowing Sun marker
    const now = new Date()
    const nowH = now.getHours() + now.getMinutes() / 60.0
    const nowAlt = evalAlt(nowH)
    const nx = hourToX(nowH)
    const ny = altToY(nowAlt)
    this.ctx.save()
    this.ctx.strokeStyle = this.nightMode ? '#44FF8870' : '#44FFE082'
    this.ctx.lineWidth = 0.8
    this.ctx.setLineDash([2, 2])
    this.ctx.beginPath()
    this.ctx.moveTo(nx, padT)
    this.ctx.lineTo(nx, padT + plotH)
    this.ctx.stroke()
    this.ctx.setLineDash([])
    this.ctx.beginPath()
    this.ctx.arc(nx, ny, 7.5, 0, Math.PI * 2)
    this.ctx.fillStyle = this.nightMode ? '#44FF6644' : '#44FFD166'
    this.ctx.fill()
    this.ctx.beginPath()
    this.ctx.arc(nx, ny, 4.0, 0, Math.PI * 2)
    this.ctx.fillStyle = '#FFFFFF'
    this.ctx.fill()
    this.ctx.restore()

    // 7. Bottom 24h time ticks (00, 06, 12, 18, 24)
    this.ctx.save()
    this.ctx.font = '8.5vp sans-serif'
    this.ctx.fillStyle = this.nightMode ? '#A85858' : '#89A6C8'
    this.ctx.textAlign = 'center'
    const ticks: number[] = [0, 6, 12, 18, 24]
    for (let i = 0; i < ticks.length; i++) {
      const t = ticks[i]
      this.ctx.fillText(String(t).padStart(2, '0') + ':00', hourToX(t), h - 6)
    }
    this.ctx.restore()
  }

  build() {
    Column({ space: 5 }) {
      Row() {
        Text('☉ 太阳周日轨迹与晨昏暗夜带')
          .fontSize(this.fs(11))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.text)
          .layoutWeight(1)
        if (this.daylightLabel.length > 0 && this.daylightLabel !== '--') {
          Text('昼长 ' + this.daylightLabel)
            .fontSize(this.fs(10))
            .fontColor(this.c.accent)
        }
      }
      .width('100%')

      Canvas(this.ctx)
        .width('100%')
        .height(138)
        .backgroundColor(this.nightMode ? '#140606' : '#081022')
        .borderRadius(UI_RADIUS_CONTROL)
        .border({ width: 0.8, color: this.c.border })
        .onReady(() => {
          this.canvasReady = true
          this.redraw()
        })

      Row({ space: 6 }) {
        Text('升 ' + shortClock(this.sunRiseText))
          .fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1)
        Text('中天 ' + shortClock(this.sunTransitText))
          .fontSize(this.fs(10)).fontColor(this.c.text).textAlign(TextAlign.Center).layoutWeight(1)
        Text('落 ' + shortClock(this.sunSetText))
          .fontSize(this.fs(10)).fontColor(this.c.sub).textAlign(TextAlign.End).layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 2, right: 2 })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.c.bg)
    .border({ width: 0.6, color: this.c.border })
    .borderRadius(UI_RADIUS_CONTROL)
    .margin({ top: 4, bottom: 6 })
  }
}
