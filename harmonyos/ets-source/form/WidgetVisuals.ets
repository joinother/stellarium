import {
  CompactPlanetItem,
  MiniPhaseDay,
  buildMiniPhaseStrip
} from './AstronomyCardData'

export function orbResource(orbBody: string): Resource {
  const key = orbBody.trim().toLowerCase()
  if (key === 'earth') return $r('app.media.widget_orb_earth')
  if (key === 'mars') return $r('app.media.widget_orb_mars')
  if (key === 'saturn') return $r('app.media.widget_orb_saturn')
  if (key === 'jupiter') return $r('app.media.widget_orb_jupiter')
  if (key === 'titan') return $r('app.media.widget_orb_titan')
  if (key === 'venus') return $r('app.media.widget_orb_venus')
  if (key === 'neptune') return $r('app.media.widget_orb_neptune')
  if (key === 'uranus') return $r('app.media.widget_orb_uranus')
  if (key === 'mercury') return $r('app.media.widget_orb_mercury')
  if (key === 'pluto') return $r('app.media.widget_orb_pluto')
  return $r('app.media.widget_orb_moon')
}

// Map (illumination 0..100, synodic age 0..29.53) to one of 16 ray-traced 3D spherical phase masks.
// Index 0 = New (0%), 4 = First Quarter (50% waxing), 8 = Full (100%), 12 = Last Quarter (50% waning).
export function phaseMaskIndex(illumination: number, phaseAge: number): number {
  const clamped = Math.max(0, Math.min(100, Number.isFinite(illumination) ? illumination : 100))
  const cosPhi = 1.0 - (clamped / 50.0) // +1 at 0% (new), 0 at 50%, -1 at 100% (full)
  const angleRad = Math.acos(Math.max(-1.0, Math.min(1.0, cosPhi))) // [0, pi]
  const synodic = 29.530588853
  const normAge = (((Number.isFinite(phaseAge) ? phaseAge : 10) % synodic) + synodic) % synodic
  const waxing = normAge <= synodic * 0.5
  const fullAngle = waxing ? angleRad : (2.0 * Math.PI - angleRad)
  return Math.round((fullAngle / (2.0 * Math.PI)) * 16.0) % 16
}

export function phaseMaskResource(illumination: number, phaseAge: number): Resource {
  const idx = phaseMaskIndex(illumination, phaseAge)
  if (idx === 0) return $r('app.media.widget_phase_00')
  if (idx === 1) return $r('app.media.widget_phase_01')
  if (idx === 2) return $r('app.media.widget_phase_02')
  if (idx === 3) return $r('app.media.widget_phase_03')
  if (idx === 4) return $r('app.media.widget_phase_04')
  if (idx === 5) return $r('app.media.widget_phase_05')
  if (idx === 6) return $r('app.media.widget_phase_06')
  if (idx === 7) return $r('app.media.widget_phase_07')
  if (idx === 8) return $r('app.media.widget_phase_08')
  if (idx === 9) return $r('app.media.widget_phase_09')
  if (idx === 10) return $r('app.media.widget_phase_10')
  if (idx === 11) return $r('app.media.widget_phase_11')
  if (idx === 12) return $r('app.media.widget_phase_12')
  if (idx === 13) return $r('app.media.widget_phase_13')
  if (idx === 14) return $r('app.media.widget_phase_14')
  return $r('app.media.widget_phase_15')
}

export function orbGlowColor(orbBody: string): string {
  const key = orbBody.trim().toLowerCase()
  if (key === 'earth') return '#6650A8FF'
  if (key === 'mars') return '#66E88854'
  if (key === 'saturn') return '#55F0CC88'
  if (key === 'jupiter') return '#55E0B07D'
  if (key === 'titan') return '#66F5A242'
  if (key === 'venus') return '#55FFE29A'
  if (key === 'neptune') return '#664EA4FF'
  if (key === 'uranus') return '#558CE2EC'
  if (key === 'pluto') return '#557DBBFF'
  return '#4D9AB8FF'
}

export function eventAccentColor(kind: string): string {
  const key = kind.trim().toLowerCase()
  if (key.includes('eclipse')) return '#FF9F43'
  if (key.includes('meteor')) return '#7AD7FF'
  if (key.includes('moon') || key.includes('phase')) return '#DCE8FF'
  if (key.includes('season') || key.includes('term') || key.includes('solar')) return '#FFD166'
  return '#9FC3FF'
}

export function eventBadgeText(kind: string): string {
  const key = kind.trim().toLowerCase()
  if (key.includes('eclipse')) return '食相'
  if (key.includes('meteor')) return '流星'
  if (key.includes('moon') || key.includes('phase')) return '相位'
  if (key.includes('season') || key.includes('term')) return '节令'
  if (key.includes('planet') || key.includes('elong') || key.includes('oppos') || key.includes('conj')) return '行星'
  return '天象'
}

// High-craft 3D textured celestial globe with true 3D ray-traced spherical phase shading
// (smooth twilight terminator + natural earthshine; zero rectangular radialGradient boxes!).
@Component
export struct CelestialOrbView {
  @Prop orbBody: string = 'moon'
  @Prop orbSize: number = 68
  @Prop showPhase: boolean = true
  @Prop illumination: number = 78
  @Prop phaseAge: number = 11
  @Prop glowIntensity: number = 1.0

  private isRinged(): boolean {
    return this.orbBody.trim().toLowerCase() === 'saturn'
  }

  private shouldOverlayPhase(): boolean {
    if (!this.showPhase || this.isRinged()) return false
    if (!Number.isFinite(this.illumination) || this.illumination < 0) return false
    return phaseMaskIndex(this.illumination, this.phaseAge) !== 8
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // Real orthographically-rendered 3D planet / moon texture (with baked C1-tapered atmospheric rim)
      Image(orbResource(this.orbBody))
        .width(this.orbSize)
        .height(this.orbSize)
        .objectFit(ImageFit.Contain)
        .draggable(false)

      // True 3D Lambertian spherical phase mask pixel-aligned over the globe
      if (this.shouldOverlayPhase()) {
        Image(phaseMaskResource(this.illumination, this.phaseAge))
          .width(this.orbSize)
          .height(this.orbSize)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
    }
    .width(this.orbSize)
    .height(this.orbSize)
    .backgroundColor(Color.Transparent)
  }
}

// Subtle procedural starfield layer for dark skies (zero external bitmap needed)
@Component
export struct StarfieldLayer {
  @Prop sunAlt: number = -18
  @Prop themeStyle: string = 'sky'

  private starAlpha(): number {
    if (this.themeStyle === 'deep') return 0.9
    if (this.sunAlt <= -12) return 0.85
    if (this.sunAlt <= -4) return 0.45
    return 0.0
  }

  build() {
    if (this.starAlpha() > 0.05) {
      Stack() {
        Circle().width(2).height(2).fill('#E8F1FF').opacity(0.65).position({ x: '14%', y: '18%' })
        Circle().width(1.5).height(1.5).fill('#BCD6FF').opacity(0.45).position({ x: '32%', y: '11%' })
        Circle().width(2.5).height(2.5).fill('#FFF4D9').opacity(0.75).position({ x: '54%', y: '15%' })
        Circle().width(1.5).height(1.5).fill('#E8F1FF').opacity(0.38).position({ x: '72%', y: '24%' })
        Circle().width(2).height(2).fill('#D2E4FF').opacity(0.55).position({ x: '86%', y: '13%' })
        Circle().width(1.5).height(1.5).fill('#E8F1FF').opacity(0.32).position({ x: '24%', y: '38%' })
        Circle().width(1.8).height(1.8).fill('#FFE5BD').opacity(0.45).position({ x: '46%', y: '34%' })
        Circle().width(1.5).height(1.5).fill('#C7DCFF').opacity(0.35).position({ x: '63%', y: '42%' })
      }
      .width('100%')
      .height('100%')
      .opacity(this.starAlpha())
      .hitTestBehavior(HitTestMode.None)
    }
  }
}

// Instrument-grade Canvas astronomical horizon arc:
// Smooth sine dome, translucent gradient fill under the horizon curve, active solid track + remaining dashed track,
// and the luminous celestial body mathematically locked ON the exact pixel of the curve (0.00px misalignment!).
@Component
export struct HorizonArcView {
  @Prop arcWidth: number = 128
  @Prop arcHeight: number = 34
  @Prop @Watch('redraw') altitudeDeg: number = 32
  @Prop riseText: string = '—'
  @Prop setText: string = '—'
  @Prop @Watch('redraw') accentColor: string = '#9EC5FF'

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings)
  private canvasReady: boolean = false

  private hasRiseSetTimes(): boolean {
    const r = this.riseText.trim()
    const s = this.setText.trim()
    return (r.length > 0 && r !== '—') || (s.length > 0 && s !== '—')
  }

  private leftFooter(): string {
    if (this.hasRiseSetTimes()) return '升 ' + this.riseText
    return '地平线'
  }

  private rightFooter(): string {
    if (this.hasRiseSetTimes()) return '落 ' + this.setText
    if (this.altitudeDeg >= 0) return '仰角 +' + String(Math.round(this.altitudeDeg)) + '°'
    return '地平线下'
  }

  private arcProgress(): number {
    // Map altitude (-15..90 deg) cleanly onto sine curve [0.06 .. 0.50] (ascending)
    const alt = Number.isFinite(this.altitudeDeg) ? this.altitudeDeg : 0
    if (alt <= 0) return 0.06
    const norm = Math.min(1.0, alt / 78.0)
    return 0.12 + norm * 0.38
  }

  private redraw(): void {
    if (!this.canvasReady) return
    const w = this.ctx.width > 0 ? this.ctx.width : this.arcWidth
    const h = this.ctx.height > 0 ? this.ctx.height : this.arcHeight
    this.ctx.clearRect(0, 0, w, h)

    const padX = 10
    const spanX = Math.max(20, w - padX * 2)
    const horizonY = h - 6
    const ampY = Math.max(10, horizonY - 7)
    const steps = 40
    const prog = this.arcProgress()
    const accent = /^#[0-9A-Fa-f]{6}$/.test(this.accentColor) ? this.accentColor : '#9EC5FF'

    const ptX = (t: number): number => padX + spanX * t
    const ptY = (t: number): number => horizonY - ampY * Math.sin(Math.PI * t)

    // 1. Soft translucent gradient dome fill under the horizon curve
    this.ctx.save()
    this.ctx.beginPath()
    this.ctx.moveTo(ptX(0), horizonY)
    for (let i = 0; i <= steps; i++) {
      const t = i / steps
      this.ctx.lineTo(ptX(t), ptY(t))
    }
    this.ctx.lineTo(ptX(1), horizonY)
    this.ctx.closePath()
    const fillGrad = this.ctx.createLinearGradient(0, horizonY - ampY, 0, horizonY)
    fillGrad.addColorStop(0.0, '#36' + accent.slice(1))
    fillGrad.addColorStop(1.0, '#04' + accent.slice(1))
    this.ctx.fillStyle = fillGrad
    this.ctx.fill()
    this.ctx.restore()

    // 2. Hairline horizon baseline with gentle fade at edges
    this.ctx.save()
    const baseGrad = this.ctx.createLinearGradient(0, horizonY, w, horizonY)
    baseGrad.addColorStop(0.0, '#00FFFFFF')
    baseGrad.addColorStop(0.12, '#48FFFFFF')
    baseGrad.addColorStop(0.88, '#48FFFFFF')
    baseGrad.addColorStop(1.0, '#00FFFFFF')
    this.ctx.strokeStyle = baseGrad
    this.ctx.lineWidth = 1
    this.ctx.beginPath()
    this.ctx.moveTo(2, horizonY)
    this.ctx.lineTo(w - 2, horizonY)
    this.ctx.stroke()
    this.ctx.restore()

    // 3. Remaining orbital arc (dashed, subtle) from prog -> 1.0
    this.ctx.save()
    this.ctx.strokeStyle = '#55FFFFFF'
    this.ctx.lineWidth = 1.2
    this.ctx.setLineDash([3, 3])
    this.ctx.beginPath()
    for (let i = 0; i <= steps; i++) {
      const t = prog + (1.0 - prog) * (i / steps)
      if (i === 0) this.ctx.moveTo(ptX(t), ptY(t))
      else this.ctx.lineTo(ptX(t), ptY(t))
    }
    this.ctx.stroke()
    this.ctx.restore()

    // 4. Traversed luminous solid arc from 0 -> prog
    if (this.altitudeDeg > 0) {
      this.ctx.save()
      this.ctx.strokeStyle = accent
      this.ctx.lineWidth = 2.0
      this.ctx.lineCap = 'round'
      this.ctx.beginPath()
      const activeSteps = Math.max(8, Math.round(steps * prog))
      for (let i = 0; i <= activeSteps; i++) {
        const t = prog * (i / activeSteps)
        if (i === 0) this.ctx.moveTo(ptX(t), ptY(t))
        else this.ctx.lineTo(ptX(t), ptY(t))
      }
      this.ctx.stroke()
      this.ctx.restore()
    }

    // 5. Small crisp rise/set anchor ticks on the horizon
    this.ctx.save()
    this.ctx.fillStyle = '#70FFFFFF'
    this.ctx.beginPath()
    this.ctx.arc(ptX(0), horizonY, 2, 0, Math.PI * 2)
    this.ctx.arc(ptX(1), horizonY, 2, 0, Math.PI * 2)
    this.ctx.fill()
    this.ctx.restore()

    // 6. Celestial body dot mathematically locked ON (ptX(prog), ptY(prog))!
    const bx = ptX(prog)
    const by = this.altitudeDeg > 0 ? ptY(prog) : horizonY + 2
    this.ctx.save()
    const glow = this.ctx.createRadialGradient(bx, by, 1, bx, by, 8)
    glow.addColorStop(0.0, this.altitudeDeg > 0 ? '#EE' + accent.slice(1) : '#8899B0CC')
    glow.addColorStop(1.0, '#00000000')
    this.ctx.fillStyle = glow
    this.ctx.beginPath()
    this.ctx.arc(bx, by, 8, 0, Math.PI * 2)
    this.ctx.fill()

    this.ctx.fillStyle = this.altitudeDeg > 0 ? '#FFFFFF' : '#99B4CCE0'
    this.ctx.beginPath()
    this.ctx.arc(bx, by, 3.2, 0, Math.PI * 2)
    this.ctx.fill()
    this.ctx.restore()
  }

  build() {
    Column({ space: 2 }) {
      Canvas(this.ctx)
        .width(this.arcWidth)
        .height(this.arcHeight)
        .onReady(() => {
          this.canvasReady = true
          this.redraw()
        })

      Row() {
        Text(this.leftFooter())
          .fontSize(10)
          .fontWeight(FontWeight.Regular)
          .fontColor('#B8D0E8FF')
          .maxLines(1)
        Blank()
        Text(this.rightFooter())
          .fontSize(10)
          .fontWeight(FontWeight.Regular)
          .fontColor('#B8D0E8FF')
          .maxLines(1)
      }
      .width(this.arcWidth)
    }
    .alignItems(HorizontalAlign.Center)
  }
}

// Interactive 5-day lunar/companion phase progression strip using real 3D miniature moons & phase masks
@Component
export struct MiniPhaseStripView {
  @Prop phaseAge: number = 10
  @Prop nowMs: number = 0
  @Prop selectedIndex: number = 0
  onSelectDay?: (index: number) => void

  private days(): MiniPhaseDay[] {
    return buildMiniPhaseStrip(this.phaseAge, this.nowMs > 0 ? this.nowMs : Date.now())
  }

  build() {
    Row({ space: 4 }) {
      ForEach(this.days(), (day: MiniPhaseDay, index: number) => {
        Column({ space: 3 }) {
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.widget_orb_moon'))
              .width(22)
              .height(22)
              .objectFit(ImageFit.Contain)
              .draggable(false)
            if (phaseMaskIndex(day.illumination, day.age) !== 8) {
              Image(phaseMaskResource(day.illumination, day.age))
                .width(22)
                .height(22)
                .objectFit(ImageFit.Contain)
                .draggable(false)
            }
          }
          .width(22)
          .height(22)

          Text(day.label)
            .fontSize(11)
            .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.selectedIndex === index ? '#FFFFFF' : '#96C8DCFF')
            .maxLines(1)
        }
        .layoutWeight(1)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.selectedIndex === index ? '#369EC5FF' : '#18FFFFFF')
        .borderRadius(10)
        .border({
          width: this.selectedIndex === index ? 1 : 0,
          color: this.selectedIndex === index ? '#B8DEFF' : Color.Transparent
        })
        .onClick(() => {
          if (this.onSelectDay !== undefined) {
            this.onSelectDay(index)
          }
        })
      }, (day: MiniPhaseDay, index: number) => day.label + '_' + String(index))
    }
    .width('100%')
  }
}

// Compact planet visibility row with rise-set bar (for 4*4 SkyWindowCard)
@Component
export struct PlanetVisibilityRow {
  @Prop itemName: string = '木星'
  @Prop itemSymbol: string = '♃'
  @Prop labelStyle: string = 'name'
  @Prop visible: boolean = true
  @Prop altitude: number = 32
  @Prop riseText: string = '—'
  @Prop setText: string = '—'

  private barFillRatio(): number {
    if (!this.visible) return 0.16
    return Math.max(0.28, Math.min(1.0, (this.altitude + 10) / 85))
  }

  private displayLabel(): string {
    return this.labelStyle === 'symbol' ? this.itemSymbol : this.itemName
  }

  private statusLabel(): string {
    if (this.visible) return '+' + String(Math.round(this.altitude)) + '°'
    if (this.riseText !== '—' && this.riseText.length > 0) return '升 ' + this.riseText
    return '地平下'
  }

  build() {
    Row({ space: 8 }) {
      Text(this.displayLabel())
        .fontSize(this.labelStyle === 'symbol' ? 13 : 11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.visible ? '#F4F8FF' : '#88B4CCE8')
        .width(this.labelStyle === 'symbol' ? 20 : 34)
        .maxLines(1)

      Stack({ alignContent: Alignment.Start }) {
        Rect()
          .width('100%')
          .height(4)
          .radius(2)
          .fill('#22FFFFFF')
        Rect()
          .width(String(Math.round(this.barFillRatio() * 100)) + '%')
          .height(4)
          .radius(2)
          .fill(this.visible ? '#88C8FF' : '#446A84AA')
      }
      .layoutWeight(1)
      .height(6)

      Text(this.statusLabel())
        .fontSize(10)
        .fontWeight(FontWeight.Regular)
        .fontColor(this.visible ? '#D8EBFF' : '#77A8C0DC')
        .width(42)
        .textAlign(TextAlign.End)
        .maxLines(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

export function fallbackPlanetRows(items: CompactPlanetItem[]): CompactPlanetItem[] {
  return items.slice(0, 5)
}
