import {
  CompactPlanetItem,
  MiniPhaseDay,
  OrreryOrbitRing,
  OrreryProjectedNode,
  OrreryRenderPlan,
  buildMiniPhaseStrip,
  parseHeliocentricPlanets,
  projectSolarSystemOrrery
} from './AstronomyCardData'
import {
  SatelliteArchetype,
  compassDirectionZh,
  satelliteVisualProfile
} from './SatelliteVisualRegistry'

export function satelliteIconResource(archetype: SatelliteArchetype | string): Resource {
  const key = String(archetype).trim().toLowerCase()
  if (key === 'iss') return $r('app.media.sat_icon_iss')
  if (key === 'tiangong') return $r('app.media.sat_icon_tiangong')
  if (key === 'telescope') return $r('app.media.sat_icon_telescope')
  if (key === 'comms') return $r('app.media.sat_icon_comms')
  if (key === 'earth_obs') return $r('app.media.sat_icon_earth_obs')
  return $r('app.media.sat_icon_constellation')
}

export function orbResource(orbBody: string): Resource {
  const key = orbBody.trim().toLowerCase()
  if (key === 'sun') return $r('app.media.widget_orb_sun')
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

export function phaseMaskByIndex(idx: number): Resource {
  const safe = ((Math.round(idx) % 16) + 16) % 16
  if (safe === 0) return $r('app.media.widget_phase_00')
  if (safe === 1) return $r('app.media.widget_phase_01')
  if (safe === 2) return $r('app.media.widget_phase_02')
  if (safe === 3) return $r('app.media.widget_phase_03')
  if (safe === 4) return $r('app.media.widget_phase_04')
  if (safe === 5) return $r('app.media.widget_phase_05')
  if (safe === 6) return $r('app.media.widget_phase_06')
  if (safe === 7) return $r('app.media.widget_phase_07')
  if (safe === 8) return $r('app.media.widget_phase_08')
  if (safe === 9) return $r('app.media.widget_phase_09')
  if (safe === 10) return $r('app.media.widget_phase_10')
  if (safe === 11) return $r('app.media.widget_phase_11')
  if (safe === 12) return $r('app.media.widget_phase_12')
  if (safe === 13) return $r('app.media.widget_phase_13')
  if (safe === 14) return $r('app.media.widget_phase_14')
  return $r('app.media.widget_phase_15')
}

export function phaseMaskResource(illumination: number, phaseAge: number): Resource {
  return phaseMaskByIndex(phaseMaskIndex(illumination, phaseAge))
}

export function orbGlowColor(orbBody: string): string {
  const key = orbBody.trim().toLowerCase()
  if (key === 'sun') return '#77FFB84D'
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
// AND dual-slot ping-pong crossfade + intermediate phase stepping so EVERY shadow transition
// (Full -> Shadowed, Shadowed -> Full, and Shadowed A -> Shadowed B) glides smoothly with zero snap.
@Component
export struct CelestialOrbView {
  @Prop @Watch('onPhaseInputChanged') orbBody: string = 'moon'
  @Prop orbSize: number = 68
  @Prop @Watch('onPhaseInputChanged') showPhase: boolean = true
  @Prop @Watch('onPhaseInputChanged') illumination: number = 78
  @Prop @Watch('onPhaseInputChanged') phaseAge: number = 11
  @Prop glowIntensity: number = 1.0

  @State private slotAIdx: number = 8
  @State private slotBIdx: number = 8
  @State private slotAOpacity: number = 0
  @State private slotBOpacity: number = 0
  private activeSlot: number = 0
  private currentIdx: number = 8
  private pendingTargetIdx: number = 8
  private stepping: boolean = false

  private isRinged(): boolean {
    return this.orbBody.trim().toLowerCase() === 'saturn'
  }

  private targetMaskIdx(): number {
    if (!this.showPhase || this.isRinged()) return 8
    if (!Number.isFinite(this.illumination) || this.illumination < 0) return 8
    return phaseMaskIndex(this.illumination, this.phaseAge)
  }

  aboutToAppear(): void {
    const idx = this.targetMaskIdx()
    this.currentIdx = idx
    this.pendingTargetIdx = idx
    this.stepping = false
    this.activeSlot = 0
    this.slotAIdx = idx
    this.slotBIdx = idx
    this.slotAOpacity = idx === 8 ? 0 : 1
    this.slotBOpacity = 0
  }

  aboutToDisappear(): void {
    this.stepping = false
    this.pendingTargetIdx = this.currentIdx
  }

  private stepTowardTarget(): void {
    const target = this.pendingTargetIdx
    if (target === this.currentIdx) {
      this.stepping = false
      return
    }
    this.stepping = true
    const cw = ((target - this.currentIdx) % 16 + 16) % 16
    const ccw = ((this.currentIdx - target) % 16 + 16) % 16
    const dist = Math.min(cw, ccw)
    const dir = cw <= ccw ? 1 : -1
    const isFinal = dist <= 1
    const nextIdx = isFinal ? target : ((this.currentIdx + dir) % 16 + 16) % 16
    const durationMs = isFinal ? 340 : 145
    const curve = isFinal ? Curve.EaseInOut : Curve.Linear
    this.currentIdx = nextIdx

    const onStepDone = (): void => {
      if (this.currentIdx !== this.pendingTargetIdx) {
        this.stepTowardTarget()
      } else {
        this.stepping = false
      }
    }

    if (nextIdx === 8) {
      animateTo({ duration: durationMs, curve: curve, onFinish: onStepDone }, () => {
        this.slotAOpacity = 0
        this.slotBOpacity = 0
      })
      return
    }
    if (this.activeSlot === 0) {
      this.slotBIdx = nextIdx
      this.activeSlot = 1
      animateTo({ duration: durationMs, curve: curve, onFinish: onStepDone }, () => {
        this.slotAOpacity = 0
        this.slotBOpacity = 1
      })
    } else {
      this.slotAIdx = nextIdx
      this.activeSlot = 0
      animateTo({ duration: durationMs, curve: curve, onFinish: onStepDone }, () => {
        this.slotBOpacity = 0
        this.slotAOpacity = 1
      })
    }
  }

  private onPhaseInputChanged(): void {
    const target = this.targetMaskIdx()
    this.pendingTargetIdx = target
    if (target === this.currentIdx) return
    if (!this.stepping) {
      this.stepTowardTarget()
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // Real orthographically-rendered 3D planet / moon texture (with baked C1-tapered atmospheric rim)
      Image(orbResource(this.orbBody))
        .width(this.orbSize)
        .height(this.orbSize)
        .objectFit(ImageFit.Contain)
        .draggable(false)

      // Dual ping-pong 3D spherical phase shadow slots for seamless crossfade across all shadowed phases
      if (this.showPhase && !this.isRinged()) {
        Image(phaseMaskByIndex(this.slotAIdx))
          .width(this.orbSize)
          .height(this.orbSize)
          .objectFit(ImageFit.Contain)
          .opacity(this.slotAOpacity)
          .draggable(false)

        Image(phaseMaskByIndex(this.slotBIdx))
          .width(this.orbSize)
          .height(this.orbSize)
          .objectFit(ImageFit.Contain)
          .opacity(this.slotBOpacity)
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
  @Prop midFooterText: string = ''
  @Prop @Watch('redraw') customProgress: number = -1
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
    if (Number.isFinite(this.customProgress) && this.customProgress >= 0.0 && this.customProgress <= 1.0) {
      return Math.max(0.05, Math.min(0.95, this.customProgress))
    }
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
        if (this.midFooterText.length > 0) {
          Text(this.midFooterText)
            .fontSize(10)
            .fontWeight(FontWeight.Regular)
            .fontColor('#D6E8FAFF')
            .maxLines(1)
          Blank()
        }
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

// High-craft 3D perspective Solar System Orrery stage shared 1:1 between SolarSystemCard & SkyLiveFormPage.
// Anti-aliased Canvas renders ultra-delicate silk orbits, radial solar corona, counterclockwise orbital motion trails,
// and Earth's reference ring — eliminating dense clutter while making orbital direction and depth instantly intuitive.
@Component
export struct SolarSystemOrreryStage {
  @Prop @Watch('redraw') stageWidth: number = 220
  @Prop @Watch('redraw') stageHeight: number = 112
  @Prop @Watch('redraw') heliocentricPlanetsJson: string = '[]'
  @Prop @Watch('redraw') dayOffset: number = 0
  @Prop @Watch('redraw') innerOnly: boolean = false
  @Prop @Watch('redraw') tiltDeg: number = 56
  @Prop showLabels: boolean = false
  @Prop @Watch('redraw') selectedId: string = ''

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings)
  private canvasReady: boolean = false

  private renderPlan(): OrreryRenderPlan {
    const planets = parseHeliocentricPlanets(this.heliocentricPlanetsJson, Date.now(), this.dayOffset)
    return projectSolarSystemOrrery(planets, this.stageWidth, this.stageHeight, this.innerOnly, this.tiltDeg, this.selectedId)
  }

  private renderSizeFor(node: OrreryProjectedNode): number {
    return node.isSaturn ? Math.round(node.size * 1.54 * 10) / 10 : node.size
  }

  private redraw(): void {
    if (!this.canvasReady) return
    const plan = this.renderPlan()
    const w = this.ctx.width > 0 ? this.ctx.width : this.stageWidth
    const h = this.ctx.height > 0 ? this.ctx.height : this.stageHeight
    this.ctx.clearRect(0, 0, w, h)

    // 1. Soft ecliptic nebula + radial solar corona glow (zero hard concentric circle borders!)
    const maxGlowR = Math.max(w, h) * 0.52
    const spaceGlow = this.ctx.createRadialGradient(plan.centerX, plan.centerY, 2, plan.centerX, plan.centerY, maxGlowR)
    spaceGlow.addColorStop(0.0, '#66FFD26A')
    spaceGlow.addColorStop(0.16, '#30FFA63A')
    spaceGlow.addColorStop(0.45, '#182A5CA8')
    spaceGlow.addColorStop(1.0, '#00050A18')
    this.ctx.fillStyle = spaceGlow
    this.ctx.fillRect(0, 0, w, h)

    // 2. Ultra-delicate silk elliptical orbits (low visual noise; highlight Earth & selected only)
    for (let i = 0; i < plan.orbits.length; i++) {
      const orbit: OrreryOrbitRing = plan.orbits[i]
      const isEarth = orbit.id === 'Earth'
      const isSel = this.selectedId.length > 0 && orbit.id.toLowerCase() === this.selectedId.toLowerCase()
      this.ctx.save()
      this.ctx.beginPath()
      this.ctx.ellipse(plan.centerX, plan.centerY, orbit.rx, orbit.ry, 0, 0, Math.PI * 2)
      if (isSel) {
        this.ctx.strokeStyle = '#88FFD166'
        this.ctx.lineWidth = 1.25
      } else if (isEarth) {
        this.ctx.strokeStyle = '#566BC4FF'
        this.ctx.lineWidth = 1.0
      } else {
        this.ctx.strokeStyle = '#24B4D4FA'
        this.ctx.lineWidth = 0.65
      }
      this.ctx.stroke()
      this.ctx.restore()
    }

    // 3. Luminous counterclockwise orbital motion trails behind each planet (instant motion & depth cue!)
    for (let i = 0; i < plan.allNodes.length; i++) {
      const node: OrreryProjectedNode = plan.allNodes[i]
      let orbitRing: OrreryOrbitRing | undefined = undefined
      for (let k = 0; k < plan.orbits.length; k++) {
        if (plan.orbits[k].id === node.id) {
          orbitRing = plan.orbits[k]
          break
        }
      }
      if (orbitRing === undefined) continue
      const hex = /^#[0-9A-Fa-f]{6}$/.test(node.color) ? node.color.slice(1) : '8AD4FF'
      const trailDeg = node.isInner ? 44 : 28
      const segs = 10
      this.ctx.save()
      this.ctx.lineCap = 'round'
      for (let s = 0; s < segs; s++) {
        const f0 = s / segs
        const f1 = (s + 1) / segs
        const deg0 = node.lonDeg - trailDeg * (1.0 - f0)
        const deg1 = node.lonDeg - trailDeg * (1.0 - f1)
        const r0 = deg0 * Math.PI / 180.0
        const r1 = deg1 * Math.PI / 180.0
        const x0 = plan.centerX + orbitRing.rx * Math.cos(r0)
        const y0 = plan.centerY - orbitRing.ry * Math.sin(r0)
        const x1 = plan.centerX + orbitRing.rx * Math.cos(r1)
        const y1 = plan.centerY - orbitRing.ry * Math.sin(r1)
        const alphaByte = Math.max(8, Math.min(185, Math.round((0.06 + f1 * f1 * 0.62) * 255)))
        const alphaHex = alphaByte.toString(16).padStart(2, '0')
        this.ctx.strokeStyle = '#' + alphaHex + hex
        this.ctx.lineWidth = 0.6 + f1 * (node.isEarth ? 1.5 : 1.15)
        this.ctx.beginPath()
        this.ctx.moveTo(x0, y0)
        this.ctx.lineTo(x1, y1)
        this.ctx.stroke()
      }
      this.ctx.restore()
    }

    // 4. Subtle Sun -> Earth reference ray so Earth's position in the solar system is unmistakable
    this.ctx.save()
    this.ctx.strokeStyle = '#4278C8FF'
    this.ctx.lineWidth = 0.85
    this.ctx.setLineDash([2.5, 3.5])
    this.ctx.beginPath()
    this.ctx.moveTo(plan.centerX, plan.centerY)
    this.ctx.lineTo(plan.earthX, plan.earthY)
    this.ctx.stroke()
    this.ctx.setLineDash([])
    this.ctx.restore()

    // 5. Soft Earth beacon ring painted anti-aliased on Canvas (tightly hugging Earth's limb)
    const earthNode = plan.allNodes.find((n: OrreryProjectedNode) => n.isEarth)
    if (earthNode !== undefined) {
      const haloR = this.renderSizeFor(earthNode) * 0.52 + 1.5
      this.ctx.save()
      this.ctx.strokeStyle = '#787AD4FF'
      this.ctx.lineWidth = 0.95
      this.ctx.beginPath()
      this.ctx.arc(earthNode.x, earthNode.y, haloR, 0, Math.PI * 2)
      this.ctx.stroke()
      this.ctx.restore()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. Anti-aliased Canvas backdrop (corona + silk orbits + motion trails + Earth reference)
      Canvas(this.ctx)
        .width(this.stageWidth)
        .height(this.stageHeight)
        .onReady(() => {
          this.canvasReady = true
          this.redraw()
        })
        .hitTestBehavior(HitTestMode.None)

      // 2. Back-hemisphere planets (behind Sun)
      ForEach(this.renderPlan().backNodes, (node: OrreryProjectedNode) => {
        Image(orbResource(node.orbKey))
          .width(this.renderSizeFor(node))
          .height(this.renderSizeFor(node))
          .objectFit(ImageFit.Contain)
          .opacity(node.opacity)
          .draggable(false)
          .position({
            x: node.x - this.renderSizeFor(node) * 0.5,
            y: node.y - this.renderSizeFor(node) * 0.5
          })
          .hitTestBehavior(HitTestMode.None)
      }, (node: OrreryProjectedNode) => 'b_' + node.id + '_' + String(Math.round(node.lonDeg)))

      // 3. Central Sun (soft corona already painted seamlessly on Canvas behind it!)
      Image($r('app.media.widget_orb_sun'))
        .width(this.renderPlan().sunSize)
        .height(this.renderPlan().sunSize)
        .objectFit(ImageFit.Contain)
        .draggable(false)
        .position({
          x: this.renderPlan().centerX - this.renderPlan().sunSize * 0.5,
          y: this.renderPlan().centerY - this.renderPlan().sunSize * 0.5
        })
        .hitTestBehavior(HitTestMode.None)

      // 4. Front-hemisphere planets (in front of Sun)
      ForEach(this.renderPlan().frontNodes, (node: OrreryProjectedNode) => {
        Image(orbResource(node.orbKey))
          .width(this.renderSizeFor(node))
          .height(this.renderSizeFor(node))
          .objectFit(ImageFit.Contain)
          .opacity(node.opacity)
          .draggable(false)
          .position({
            x: node.x - this.renderSizeFor(node) * 0.5,
            y: node.y - this.renderSizeFor(node) * 0.5
          })
          .hitTestBehavior(HitTestMode.None)
      }, (node: OrreryProjectedNode) => 'f_' + node.id + '_' + String(Math.round(node.lonDeg)))

      // 5. Optional crisp labels (Earth always accented in ice-blue; others clean & legible)
      if (this.showLabels) {
        ForEach(this.renderPlan().allNodes, (node: OrreryProjectedNode) => {
          Text(node.nameZh)
            .fontSize(9.5)
            .fontWeight(node.isEarth ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(node.isEarth ? '#8DD4FF' : '#DCEAFF')
            .textShadow({ radius: 3, color: '#DD030712', offsetX: 0, offsetY: 1 })
            .position({
              x: Math.max(2, Math.min(this.stageWidth - 28, node.x - 11)),
              y: Math.max(2, Math.min(this.stageHeight - 13, node.y + this.renderSizeFor(node) * 0.48 + 2))
            })
            .hitTestBehavior(HitTestMode.None)
        }, (node: OrreryProjectedNode) => 'lbl_' + node.id + '_' + String(Math.round(node.lonDeg)))
      }
    }
    .width(this.stageWidth)
    .height(this.stageHeight)
    .backgroundColor(Color.Transparent)
  }
}

// Curved Earth-Limb Orbital Pass Trajectory visual shared between SatellitePassCard & SkyLiveFormPage.
// Inspired by glowing cyan-blue Earth atmospheric limb + sunlit pass arc + custom archetype spacecraft silhouette.
@Component
export struct SatellitePassArcView {
  @Prop stageWidth: number = 148
  @Prop stageHeight: number = 96
  @Prop @Watch('redraw') maxAlt: number = 68
  @Prop @Watch('redraw') startAz: number = 238
  @Prop @Watch('redraw') endAz: number = 52
  @Prop @Watch('redraw') archetype: SatelliteArchetype = 'iss'
  @Prop @Watch('redraw') visible: boolean = true
  @Prop showCraft: boolean = true
  @Prop craftSize: number = 42

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings)
  private canvasReady: boolean = false

  private accentColor(): string {
    return satelliteVisualProfile(this.archetype).accentHex
  }

  private secondaryColor(): string {
    return satelliteVisualProfile(this.archetype).secondaryHex
  }

  private apexY(h: number): number {
    const clampedAlt = Math.max(15, Math.min(90, Number.isFinite(this.maxAlt) ? this.maxAlt : 50))
    const norm = (clampedAlt - 10) / 80.0
    const horizonY = h - 22
    const topMargin = Math.max(16, Math.round(this.craftSize * 0.48))
    const maxAmp = Math.max(18, horizonY - topMargin)
    return horizonY - maxAmp * (0.42 + norm * 0.58)
  }

  private redraw(): void {
    if (!this.canvasReady) return
    const w = this.ctx.width > 0 ? this.ctx.width : this.stageWidth
    const h = this.ctx.height > 0 ? this.ctx.height : this.stageHeight
    this.ctx.clearRect(0, 0, w, h)

    const padX = 12
    const spanX = Math.max(40, w - padX * 2)
    const horizonY = h - 20
    const peakY = this.apexY(h)
    const ampY = Math.max(14, horizonY - peakY)
    const accent = this.accentColor()
    const secondary = this.secondaryColor()

    const ptX = (t: number): number => padX + spanX * t
    const ptY = (t: number): number => horizonY - ampY * Math.sin(Math.PI * t)

    // 1. Curved glowing Earth atmospheric limb across bottom
    this.ctx.save()
    this.ctx.beginPath()
    this.ctx.moveTo(0, h)
    this.ctx.lineTo(0, horizonY + 5)
    this.ctx.quadraticCurveTo(w * 0.5, horizonY - 9, w, horizonY + 5)
    this.ctx.lineTo(w, h)
    this.ctx.closePath()
    const earthGrad = this.ctx.createLinearGradient(0, horizonY - 8, 0, h)
    earthGrad.addColorStop(0.0, '#442A8BFF')
    earthGrad.addColorStop(0.45, '#26143E7A')
    earthGrad.addColorStop(1.0, '#08061428')
    this.ctx.fillStyle = earthGrad
    this.ctx.fill()

    // Crisp luminous cyan-blue Earth limb arc stroke
    const limbGrad = this.ctx.createLinearGradient(0, horizonY, w, horizonY)
    limbGrad.addColorStop(0.0, '#10266BFF')
    limbGrad.addColorStop(0.28, '#AA38B6FF')
    limbGrad.addColorStop(0.5, '#E86DF5F5')
    limbGrad.addColorStop(0.72, '#AA38B6FF')
    limbGrad.addColorStop(1.0, '#10266BFF')
    this.ctx.strokeStyle = limbGrad
    this.ctx.lineWidth = 1.6
    this.ctx.beginPath()
    this.ctx.moveTo(4, horizonY + 4)
    this.ctx.quadraticCurveTo(w * 0.5, horizonY - 9, w - 4, horizonY + 4)
    this.ctx.stroke()
    this.ctx.restore()

    // 2. Soft translucent orbital sweep dome under the pass trajectory
    const steps = 44
    this.ctx.save()
    this.ctx.beginPath()
    this.ctx.moveTo(ptX(0), horizonY)
    for (let i = 0; i <= steps; i++) {
      const t = i / steps
      this.ctx.lineTo(ptX(t), ptY(t))
    }
    this.ctx.lineTo(ptX(1), horizonY)
    this.ctx.closePath()
    const domeGrad = this.ctx.createLinearGradient(0, peakY, 0, horizonY)
    domeGrad.addColorStop(0.0, '#2C' + accent.slice(1))
    domeGrad.addColorStop(1.0, '#02' + secondary.slice(1))
    this.ctx.fillStyle = domeGrad
    this.ctx.fill()
    this.ctx.restore()

    // 3. Ascending solid sunlit pass track (0 -> 0.52) + descending dashed track (0.52 -> 1.0)
    this.ctx.save()
    this.ctx.lineCap = 'round'
    const trackGrad = this.ctx.createLinearGradient(ptX(0), horizonY, ptX(0.55), peakY)
    trackGrad.addColorStop(0.0, '#55' + secondary.slice(1))
    trackGrad.addColorStop(1.0, '#FF' + accent.slice(1))
    this.ctx.strokeStyle = trackGrad
    this.ctx.lineWidth = 2.0
    this.ctx.beginPath()
    for (let i = 0; i <= 24; i++) {
      const t = (i / 24) * 0.52
      if (i === 0) this.ctx.moveTo(ptX(t), ptY(t))
      else this.ctx.lineTo(ptX(t), ptY(t))
    }
    this.ctx.stroke()

    this.ctx.strokeStyle = '#99' + secondary.slice(1)
    this.ctx.lineWidth = 1.4
    this.ctx.setLineDash([3, 3.5])
    this.ctx.beginPath()
    for (let i = 0; i <= 20; i++) {
      const t = 0.52 + (i / 20) * 0.48
      if (i === 0) this.ctx.moveTo(ptX(t), ptY(t))
      else this.ctx.lineTo(ptX(t), ptY(t))
    }
    this.ctx.stroke()
    this.ctx.setLineDash([])

    // Rise & set horizon endpoint ticks
    this.ctx.fillStyle = secondary
    this.ctx.beginPath()
    this.ctx.arc(ptX(0), horizonY, 2.5, 0, Math.PI * 2)
    this.ctx.arc(ptX(1), horizonY, 2.5, 0, Math.PI * 2)
    this.ctx.fill()
    this.ctx.restore()

    // 4. Compass direction footer labels along Earth limb
    this.ctx.save()
    this.ctx.font = '8.5vp sans-serif'
    this.ctx.fillStyle = '#B8D8F8'
    this.ctx.textAlign = 'left'
    this.ctx.fillText(compassDirectionZh(this.startAz) + '升', 6, h - 5)
    this.ctx.textAlign = 'center'
    this.ctx.fillStyle = this.visible ? accent : '#98B4D4'
    this.ctx.fillText('最高 ' + String(Math.round(this.maxAlt)) + '°', w * 0.5, h - 5)
    this.ctx.textAlign = 'right'
    this.ctx.fillStyle = '#B8D8F8'
    this.ctx.fillText(compassDirectionZh(this.endAz) + '落', w - 6, h - 5)
    this.ctx.restore()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.ctx)
        .width(this.stageWidth)
        .height(this.stageHeight)
        .onReady(() => {
          this.canvasReady = true
          this.redraw()
        })
        .hitTestBehavior(HitTestMode.None)

      if (this.showCraft) {
        Stack({ alignContent: Alignment.Center }) {
          Image(satelliteIconResource(this.archetype))
            .width(this.craftSize)
            .height(this.craftSize)
            .objectFit(ImageFit.Contain)
            .draggable(false)
        }
        .width(this.craftSize)
        .height(this.craftSize)
        .position({
          x: this.stageWidth * 0.5 - this.craftSize * 0.5,
          y: Math.max(0, this.apexY(this.stageHeight) - this.craftSize * 0.52)
        })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.stageWidth)
    .height(this.stageHeight)
    .backgroundColor(Color.Transparent)
  }
}
