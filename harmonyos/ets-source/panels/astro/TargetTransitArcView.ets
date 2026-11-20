import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

function extractClock(raw: string): string {
  const m = raw.match(/(\d{1,2}:\d{2})/)
  return m === null ? '—' : m[1]
}

function clockToMinutes(clock: string): number {
  const m = clock.match(/(\d{1,2}):(\d{2})/)
  if (m === null) return -1
  const h = Number(m[1])
  const min = Number(m[2])
  if (!Number.isFinite(h) || !Number.isFinite(min)) return -1
  return h * 60 + min
}

// Horizon Rise -> Meridian Transit -> Set visual arc for AstroCalc RTS tab.
@Component
export struct TargetTransitArcView {
  @Prop objectName: string = ''
  @Prop @Watch('redraw') riseText: string = ''
  @Prop @Watch('redraw') transitText: string = ''
  @Prop @Watch('redraw') setText: string = ''
  @Prop @Watch('redraw') nightMode: boolean = false
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  onJumpRise: () => void = (): void => {}
  onJumpTransit: () => void = (): void => {}
  onJumpSet: () => void = (): void => {}

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

  private ch(base: number): number {
    return uiControlHeight(base, this.readableUi, this.controlScale)
  }

  private currentProgress(): number {
    const rMin = clockToMinutes(this.riseText)
    const sMin = clockToMinutes(this.setText)
    if (rMin < 0 || sMin < 0) return 0.5
    const now = new Date()
    const curMin = now.getHours() * 60 + now.getMinutes()
    let span = sMin - rMin
    let elapsed = curMin - rMin
    if (span <= 0) {
      span += 1440
      if (elapsed < 0) elapsed += 1440
    }
    if (elapsed < 0 || elapsed > span) return -1
    return Math.max(0.05, Math.min(0.95, elapsed / Math.max(1, span)))
  }

  private redraw(): void {
    if (!this.canvasReady) return
    const w = this.ctx.width > 0 ? this.ctx.width : 300
    const h = this.ctx.height > 0 ? this.ctx.height : 112
    this.ctx.clearRect(0, 0, w, h)

    const padX = 24
    const spanX = Math.max(80, w - padX * 2)
    const horizonY = h - 22
    const peakY = 26
    const ampY = Math.max(24, horizonY - peakY)
    const steps = 64

    const ptX = (t: number): number => padX + spanX * t
    const ptY = (t: number): number => horizonY - ampY * Math.sin(Math.PI * t)

    // 1. Subtle meridian axis at t=0.5
    this.ctx.save()
    this.ctx.strokeStyle = this.nightMode ? '#33C04848' : '#2C8CC4FF'
    this.ctx.lineWidth = 0.8
    this.ctx.setLineDash([3, 3])
    this.ctx.beginPath()
    this.ctx.moveTo(ptX(0.5), peakY - 4)
    this.ctx.lineTo(ptX(0.5), horizonY)
    this.ctx.stroke()
    this.ctx.setLineDash([])
    this.ctx.restore()

    // 2. Gradient dome fill under transit curve
    this.ctx.save()
    this.ctx.beginPath()
    this.ctx.moveTo(ptX(0), horizonY)
    for (let i = 0; i <= steps; i++) {
      const t = i / steps
      this.ctx.lineTo(ptX(t), ptY(t))
    }
    this.ctx.lineTo(ptX(1), horizonY)
    this.ctx.closePath()
    const grad = this.ctx.createLinearGradient(0, peakY, 0, horizonY)
    if (this.nightMode) {
      grad.addColorStop(0.0, '#44FF6060')
      grad.addColorStop(1.0, '#04FF6060')
    } else {
      grad.addColorStop(0.0, '#4876C4FF')
      grad.addColorStop(1.0, '#0476C4FF')
    }
    this.ctx.fillStyle = grad
    this.ctx.fill()
    this.ctx.restore()

    // 3. Horizon baseline
    this.ctx.save()
    this.ctx.strokeStyle = this.nightMode ? '#77D05050' : '#77B8D8FF'
    this.ctx.lineWidth = 1.0
    this.ctx.beginPath()
    this.ctx.moveTo(10, horizonY)
    this.ctx.lineTo(w - 10, horizonY)
    this.ctx.stroke()
    this.ctx.restore()

    // 4. Transit curve stroke
    const prog = this.currentProgress()
    this.ctx.save()
    this.ctx.lineWidth = 2.1
    this.ctx.lineCap = 'round'
    this.ctx.strokeStyle = this.nightMode ? '#FF7068' : '#8AD4FF'
    this.ctx.beginPath()
    for (let i = 0; i <= steps; i++) {
      const t = i / steps
      if (i === 0) this.ctx.moveTo(ptX(t), ptY(t))
      else this.ctx.lineTo(ptX(t), ptY(t))
    }
    this.ctx.stroke()
    this.ctx.restore()

    // 5. Key nodes: Rise (0), Transit (0.5), Set (1)
    const drawDot = (t: number, fill: string, r: number): void => {
      this.ctx.save()
      this.ctx.beginPath()
      this.ctx.arc(ptX(t), ptY(t), r, 0, Math.PI * 2)
      this.ctx.fillStyle = fill
      this.ctx.fill()
      this.ctx.restore()
    }
    drawDot(0, this.nightMode ? '#FF8866' : '#7AD7FF', 3.5)
    drawDot(0.5, this.nightMode ? '#FFAA80' : '#FFD166', 4.0)
    drawDot(1, this.nightMode ? '#E86860' : '#9EB8E8', 3.5)

    // Live position glow if currently above horizon
    if (prog > 0) {
      const gx = ptX(prog)
      const gy = ptY(prog)
      this.ctx.save()
      this.ctx.beginPath()
      this.ctx.arc(gx, gy, 7.5, 0, Math.PI * 2)
      this.ctx.fillStyle = this.nightMode ? '#44FF7060' : '#448AD4FF'
      this.ctx.fill()
      this.ctx.beginPath()
      this.ctx.arc(gx, gy, 3.8, 0, Math.PI * 2)
      this.ctx.fillStyle = '#FFFFFF'
      this.ctx.fill()
      this.ctx.restore()
    }

    // 6. Labels on canvas
    this.ctx.save()
    this.ctx.font = '9vp sans-serif'
    this.ctx.fillStyle = this.nightMode ? '#C87878' : '#B8D4F4'
    this.ctx.textAlign = 'left'
    this.ctx.fillText('东升 ' + extractClock(this.riseText), padX - 8, h - 7)
    this.ctx.textAlign = 'center'
    this.ctx.fillStyle = this.nightMode ? '#FFA890' : '#FFE29A'
    this.ctx.fillText('中天 ' + extractClock(this.transitText), ptX(0.5), peakY - 9)
    this.ctx.fillStyle = this.nightMode ? '#C87878' : '#B8D4F4'
    this.ctx.textAlign = 'right'
    this.ctx.fillText('西落 ' + extractClock(this.setText), padX + spanX + 8, h - 7)
    this.ctx.restore()
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text('✦ ' + (this.objectName.length > 0 ? this.objectName : '目标天体') + ' · 升落中天轨弧')
          .fontSize(this.fs(11))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.text)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.currentProgress() > 0 ? '当前地平线上' : '当前地平线下')
          .fontSize(this.fs(9))
          .fontColor(this.currentProgress() > 0 ? this.c.accent : this.c.sub)
      }
      .width('100%')

      Canvas(this.ctx)
        .width('100%')
        .height(112)
        .backgroundColor(this.nightMode ? '#140606' : '#081022')
        .borderRadius(UI_RADIUS_CONTROL)
        .border({ width: 0.8, color: this.c.border })
        .onReady(() => {
          this.canvasReady = true
          this.redraw()
        })

      Row({ space: 6 }) {
        Button('跳至升起')
          .fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.soft)
          .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(26) }).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .onClick(() => this.onJumpRise())
        Button('跳至中天')
          .fontSize(this.fs(10)).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
          .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(26) }).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .onClick(() => this.onJumpTransit())
        Button('跳至落下')
          .fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.soft)
          .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(26) }).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .onClick(() => this.onJumpSet())
      }
      .width('100%')
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.c.bg)
    .border({ width: 0.6, color: this.c.border })
    .borderRadius(UI_RADIUS_CONTROL)
    .margin({ top: 6, bottom: 6 })
  }
}
