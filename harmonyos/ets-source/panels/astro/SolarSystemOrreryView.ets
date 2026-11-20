import { HeliocentricPosition } from '../../pages/StellariumTypes'
import {
  OrreryOrbitRing,
  OrreryPlanetState,
  OrreryProjectedNode,
  OrreryRenderPlan,
  estimateHeliocentricLongitudes,
  projectSolarSystemOrrery
} from '../../form/AstronomyCardData'
import { orbResource } from '../../form/WidgetVisuals'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

interface MinorBodyDot {
  englishName: string
  name: string
  x: number
  y: number
  isComet: boolean
  longitude: number
  distanceAU: number
}

interface PlacedOrreryLabel {
  id: string
  nameZh: string
  x: number
  y: number
  isEarth: boolean
  isSelected: boolean
  lonDeg: number
}

@Component
export struct SolarSystemOrreryView {
  @Prop @Watch('onInputsChanged') positions: Array<HeliocentricPosition> = []
  @Prop timeLabel: string = ''
  @Prop nightMode: boolean = false
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  onFocusPlanet: (englishName: string) => void = (_name: string): void => {}

  @State c: ThemeSlots = DEFAULT_SLOTS
  @State is3DView: boolean = true
  @State innerOnly: boolean = false
  @State selectedId: string = 'Earth'
  @State stageWidth: number = 296

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

  private stageHeight(): number {
    return this.is3DView ? 216 : 264
  }

  private tiltDeg(): number {
    return this.is3DView ? 52 : 0
  }

  private onInputsChanged(): void {
    this.redrawBackdrop()
  }

  private mergedPlanets(): OrreryPlanetState[] {
    const base = estimateHeliocentricLongitudes(Date.now())
    if (this.positions.length === 0) return base
    const byName = new Map<string, HeliocentricPosition>()
    for (let i = 0; i < this.positions.length; i++) {
      const p = this.positions[i]
      if (p.englishName.length > 0) {
        byName.set(p.englishName.trim().toLowerCase(), p)
      }
    }
    const out: OrreryPlanetState[] = []
    for (let i = 0; i < base.length; i++) {
      const b = base[i]
      const live = byName.get(b.id.toLowerCase())
      if (live !== undefined && Number.isFinite(live.longitude)) {
        out.push({
          id: b.id,
          nameZh: b.nameZh,
          orbKey: b.orbKey,
          color: this.nightMode ? '#E06868' : b.color,
          lonDeg: Math.round((((live.longitude % 360) + 360) % 360) * 10) / 10,
          distAU: Number.isFinite(live.distanceAU) && live.distanceAU > 0 ? Math.round(live.distanceAU * 100) / 100 : b.distAU,
          isInner: b.isInner,
          periodDays: b.periodDays,
          baseSize: b.baseSize
        })
      } else {
        out.push(b)
      }
    }
    return out
  }

  private currentPlan(): OrreryRenderPlan {
    return projectSolarSystemOrrery(
      this.mergedPlanets(),
      this.stageWidth,
      this.stageHeight(),
      this.innerOnly,
      this.tiltDeg(),
      this.selectedId
    )
  }

  private minorBodies(plan: OrreryRenderPlan): MinorBodyDot[] {
    const out: MinorBodyDot[] = []
    const majorIds: string[] = ['mercury', 'venus', 'earth', 'mars', 'jupiter', 'saturn', 'uranus', 'neptune']
    const outerOrbit = plan.orbits.length > 0 ? plan.orbits[plan.orbits.length - 1] : undefined
    const maxRx = outerOrbit !== undefined ? outerOrbit.rx : (plan.width * 0.42)
    const cosTilt = Math.max(0.32, Math.cos(plan.tiltDeg * Math.PI / 180.0))
    for (let i = 0; i < this.positions.length; i++) {
      const p = this.positions[i]
      if (majorIds.includes(p.englishName.trim().toLowerCase())) continue
      if (this.innerOnly && p.distanceAU > 2.6) continue
      const normDist = this.innerOnly
        ? Math.max(0.18, Math.min(1.0, p.distanceAU / 1.8))
        : Math.max(0.22, Math.min(1.0, Math.log10(1 + p.distanceAU * 3.0) / Math.log10(1 + 32.0 * 3.0)))
      const rx = maxRx * normDist
      const ry = rx * cosTilt
      const rad = p.longitude * Math.PI / 180.0
      out.push({
        englishName: p.englishName,
        name: p.name.length > 0 ? p.name : p.englishName,
        x: Math.round((plan.centerX + rx * Math.cos(rad)) * 10) / 10,
        y: Math.round((plan.centerY - ry * Math.sin(rad)) * 10) / 10,
        isComet: p.isComet === true,
        longitude: p.longitude,
        distanceAU: p.distanceAU
      })
    }
    return out
  }

  private selectedNode(plan: OrreryRenderPlan): OrreryProjectedNode | undefined {
    for (let i = 0; i < plan.allNodes.length; i++) {
      if (plan.allNodes[i].id.toLowerCase() === this.selectedId.toLowerCase()) {
        return plan.allNodes[i]
      }
    }
    return plan.allNodes.length > 0 ? plan.allNodes[0] : undefined
  }

  private liveLatitudeFor(id: string): number {
    for (let i = 0; i < this.positions.length; i++) {
      if (this.positions[i].englishName.toLowerCase() === id.toLowerCase()) {
        return this.positions[i].latitude
      }
    }
    return 0
  }

  private renderSizeFor(node: OrreryProjectedNode): number {
    const isSel = node.id.toLowerCase() === this.selectedId.toLowerCase()
    const base = node.isSaturn ? node.size * 1.52 : node.size
    return Math.round((isSel ? base * 1.18 : base) * 10) / 10
  }

  private placedLabels(plan: OrreryRenderPlan): PlacedOrreryLabel[] {
    const out: PlacedOrreryLabel[] = []
    const stageH = this.stageHeight()
    for (let i = 0; i < plan.allNodes.length; i++) {
      const node = plan.allNodes[i]
      const sz = this.renderSizeFor(node)
      const labelW = node.nameZh.length * 10 + 4
      const baseX = Math.max(4, Math.min(this.stageWidth - labelW - 2, node.x - labelW * 0.45))
      const belowY = Math.max(4, Math.min(stageH - 14, node.y + sz * 0.5 + 2))
      const aboveY = Math.max(4, node.y - sz * 0.5 - 13)
      const collides = (cx: number, cy: number): boolean => {
        for (let j = 0; j < out.length; j++) {
          const prev = out[j]
          if (Math.abs(cx - prev.x) < 26 && Math.abs(cy - prev.y) < 12) return true
        }
        return false
      }
      let finalX = baseX
      let finalY = belowY
      if (collides(finalX, finalY)) {
        if (!collides(baseX, aboveY)) {
          finalY = aboveY
        } else {
          finalX = Math.max(4, Math.min(this.stageWidth - labelW - 2, baseX + (node.x >= plan.centerX ? 18 : -18)))
          finalY = aboveY
        }
      }
      out.push({
        id: node.id,
        nameZh: node.nameZh,
        x: Math.round(finalX * 10) / 10,
        y: Math.round(finalY * 10) / 10,
        isEarth: node.isEarth,
        isSelected: node.id.toLowerCase() === this.selectedId.toLowerCase(),
        lonDeg: node.lonDeg
      })
    }
    return out
  }

  private redrawBackdrop(): void {
    if (!this.canvasReady) return
    const plan = this.currentPlan()
    const w = this.ctx.width > 0 ? this.ctx.width : plan.width
    const h = this.ctx.height > 0 ? this.ctx.height : plan.height
    this.ctx.clearRect(0, 0, w, h)

    // 1. Subtle deep-space backdrop radial glow
    const bgGrad = this.ctx.createRadialGradient(plan.centerX, plan.centerY, 4, plan.centerX, plan.centerY, Math.max(w, h) * 0.56)
    if (this.nightMode) {
      bgGrad.addColorStop(0.0, '#364A1212')
      bgGrad.addColorStop(0.55, '#18240A0A')
      bgGrad.addColorStop(1.0, '#00000000')
    } else {
      bgGrad.addColorStop(0.0, '#2CFFB84D')
      bgGrad.addColorStop(0.35, '#162856A8')
      bgGrad.addColorStop(1.0, '#00050A18')
    }
    this.ctx.fillStyle = bgGrad
    this.ctx.fillRect(0, 0, w, h)

    // 2. Vernal Equinox 0° axis & subtle ecliptic crosshairs
    const outerRx = plan.orbits.length > 0 ? plan.orbits[plan.orbits.length - 1].rx : w * 0.42
    const outerRy = plan.orbits.length > 0 ? plan.orbits[plan.orbits.length - 1].ry : h * 0.40
    this.ctx.save()
    this.ctx.strokeStyle = this.nightMode ? '#33C04040' : '#2E8EC4FF'
    this.ctx.lineWidth = 0.8
    this.ctx.setLineDash([3, 4])
    this.ctx.beginPath()
    this.ctx.moveTo(plan.centerX - outerRx, plan.centerY)
    this.ctx.lineTo(plan.centerX + outerRx, plan.centerY)
    this.ctx.moveTo(plan.centerX, plan.centerY - outerRy)
    this.ctx.lineTo(plan.centerX, plan.centerY + outerRy)
    this.ctx.stroke()
    this.ctx.setLineDash([])

    // Vernal equinox direction label (monochrome text, no color emoji)
    this.ctx.font = '9vp sans-serif'
    this.ctx.fillStyle = this.nightMode ? '#B85050' : '#6E9AC8'
    this.ctx.textAlign = 'right'
    this.ctx.fillText('春分 0°', w - 6, 13)
    this.ctx.restore()

    // 3. Anti-aliased elliptical orbit tracks
    for (let i = 0; i < plan.orbits.length; i++) {
      const orbit: OrreryOrbitRing = plan.orbits[i]
      const isSel = orbit.id.toLowerCase() === this.selectedId.toLowerCase()
      this.ctx.save()
      this.ctx.beginPath()
      this.ctx.ellipse(plan.centerX, plan.centerY, orbit.rx, orbit.ry, 0, 0, Math.PI * 2)
      if (isSel) {
        this.ctx.strokeStyle = this.nightMode ? '#FF6B6B' : '#8AD4FF'
        this.ctx.lineWidth = 1.45
      } else if (orbit.id === 'Earth') {
        this.ctx.strokeStyle = this.nightMode ? '#99C84848' : '#785CB8FF'
        this.ctx.lineWidth = 1.05
      } else {
        this.ctx.strokeStyle = this.nightMode ? '#44B84040' : ('#48' + orbit.color.replace('#', ''))
        this.ctx.lineWidth = 0.8
      }
      this.ctx.stroke()
      this.ctx.restore()
    }

    // 4. Sun -> Earth reference sightline & Sun -> Selected Planet vector
    const sel = this.selectedNode(plan)
    this.ctx.save()
    this.ctx.strokeStyle = this.nightMode ? '#66D85050' : '#585CB8FF'
    this.ctx.lineWidth = 1.0
    this.ctx.setLineDash([2, 3])
    this.ctx.beginPath()
    this.ctx.moveTo(plan.centerX, plan.centerY)
    this.ctx.lineTo(plan.earthX, plan.earthY)
    this.ctx.stroke()

    if (sel !== undefined && !sel.isEarth) {
      this.ctx.strokeStyle = this.nightMode ? '#99FF7070' : '#78FFD166'
      this.ctx.lineWidth = 1.1
      this.ctx.beginPath()
      this.ctx.moveTo(plan.earthX, plan.earthY)
      this.ctx.lineTo(sel.x, sel.y)
      this.ctx.stroke()
    }
    this.ctx.restore()
  }

  build() {
    Column({ space: 6 }) {
      // View & Scale control strip
      Row({ space: 6 }) {
        Row({ space: 2 }) {
          Text('3D 立体')
            .fontSize(this.fs(10))
            .fontWeight(this.is3DView ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.is3DView ? this.c.onAccent : this.c.sub)
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .backgroundColor(this.is3DView ? this.c.accent : Color.Transparent)
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => {
              this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
                this.is3DView = true
              })
              setTimeout(() => this.redrawBackdrop(), 40)
            })
          Text('正俯视')
            .fontSize(this.fs(10))
            .fontWeight(!this.is3DView ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(!this.is3DView ? this.c.onAccent : this.c.sub)
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .backgroundColor(!this.is3DView ? this.c.accent : Color.Transparent)
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => {
              this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
                this.is3DView = false
              })
              setTimeout(() => this.redrawBackdrop(), 40)
            })
        }
        .padding(2)
        .backgroundColor(this.c.soft)
        .borderRadius(UI_RADIUS_CONTROL)

        Blank()

        Row({ space: 2 }) {
          Text('全太阳系')
            .fontSize(this.fs(10))
            .fontWeight(!this.innerOnly ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(!this.innerOnly ? this.c.onAccent : this.c.sub)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(!this.innerOnly ? this.c.accent : Color.Transparent)
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => {
              this.innerOnly = false
              setTimeout(() => this.redrawBackdrop(), 30)
            })
          Text('内太阳系')
            .fontSize(this.fs(10))
            .fontWeight(this.innerOnly ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.innerOnly ? this.c.onAccent : this.c.sub)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.innerOnly ? this.c.accent : Color.Transparent)
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => {
              this.innerOnly = true
              setTimeout(() => this.redrawBackdrop(), 30)
            })
        }
        .padding(2)
        .backgroundColor(this.c.soft)
        .borderRadius(UI_RADIUS_CONTROL)
      }
      .width('100%')

      // Interactive 3D Orrery Stage: anti-aliased Canvas orbits + Painter-ordered 3D planet PNGs
      Stack({ alignContent: Alignment.TopStart }) {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .onReady(() => {
            this.canvasReady = true
            this.redrawBackdrop()
          })
          .hitTestBehavior(HitTestMode.None)

        // Back-hemisphere planets (behind Sun corona)
        ForEach(this.currentPlan().backNodes, (node: OrreryProjectedNode) => {
          Stack({ alignContent: Alignment.Center }) {
            if (node.id.toLowerCase() === this.selectedId.toLowerCase() || node.isEarth) {
              Circle()
                .width(this.renderSizeFor(node) + 6)
                .height(this.renderSizeFor(node) + 6)
                .fill(Color.Transparent)
                .stroke(node.id.toLowerCase() === this.selectedId.toLowerCase() ? '#FFD166' : '#6BC4FF')
                .strokeWidth(node.id.toLowerCase() === this.selectedId.toLowerCase() ? 1.4 : 1.0)
            }
            Image(orbResource(node.orbKey))
              .width(this.renderSizeFor(node))
              .height(this.renderSizeFor(node))
              .objectFit(ImageFit.Contain)
              .draggable(false)
          }
          .width(this.renderSizeFor(node) + 10)
          .height(this.renderSizeFor(node) + 10)
          .opacity(node.opacity)
          .position({
            x: node.x - (this.renderSizeFor(node) + 10) * 0.5,
            y: node.y - (this.renderSizeFor(node) + 10) * 0.5
          })
          .onClick(() => {
            this.selectedId = node.id
            this.redrawBackdrop()
          })
        }, (node: OrreryProjectedNode) => 'ap_b_' + node.id + '_' + String(this.is3DView) + '_' + String(this.innerOnly) + '_' + String(Math.round(node.lonDeg)))

        // Central Sun with luminous corona
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(this.currentPlan().sunSize * 1.9)
            .height(this.currentPlan().sunSize * 1.9)
            .fill(this.nightMode ? '#28FF4040' : '#28FFA836')
          Circle()
            .width(this.currentPlan().sunSize * 1.36)
            .height(this.currentPlan().sunSize * 1.36)
            .fill(this.nightMode ? '#40FF5C5C' : '#44FFD066')
          Image($r('app.media.widget_orb_sun'))
            .width(this.currentPlan().sunSize)
            .height(this.currentPlan().sunSize)
            .objectFit(ImageFit.Contain)
            .draggable(false)
        }
        .width(this.currentPlan().sunSize * 2)
        .height(this.currentPlan().sunSize * 2)
        .position({
          x: this.currentPlan().centerX - this.currentPlan().sunSize,
          y: this.currentPlan().centerY - this.currentPlan().sunSize
        })
        .onClick(() => {
          this.onFocusPlanet('Sun')
        })

        // Front-hemisphere planets (in front of Sun corona)
        ForEach(this.currentPlan().frontNodes, (node: OrreryProjectedNode) => {
          Stack({ alignContent: Alignment.Center }) {
            if (node.id.toLowerCase() === this.selectedId.toLowerCase() || node.isEarth) {
              Circle()
                .width(this.renderSizeFor(node) + 6)
                .height(this.renderSizeFor(node) + 6)
                .fill(Color.Transparent)
                .stroke(node.id.toLowerCase() === this.selectedId.toLowerCase() ? '#FFD166' : '#6BC4FF')
                .strokeWidth(node.id.toLowerCase() === this.selectedId.toLowerCase() ? 1.4 : 1.0)
            }
            Image(orbResource(node.orbKey))
              .width(this.renderSizeFor(node))
              .height(this.renderSizeFor(node))
              .objectFit(ImageFit.Contain)
              .draggable(false)
          }
          .width(this.renderSizeFor(node) + 10)
          .height(this.renderSizeFor(node) + 10)
          .opacity(node.opacity)
          .position({
            x: node.x - (this.renderSizeFor(node) + 10) * 0.5,
            y: node.y - (this.renderSizeFor(node) + 10) * 0.5
          })
          .onClick(() => {
            this.selectedId = node.id
            this.redrawBackdrop()
          })
        }, (node: OrreryProjectedNode) => 'ap_f_' + node.id + '_' + String(this.is3DView) + '_' + String(this.innerOnly) + '_' + String(Math.round(node.lonDeg)))

        // Minor bodies / bright comets when toggled in AstroPanel
        ForEach(this.minorBodies(this.currentPlan()), (dot: MinorBodyDot) => {
          Circle()
            .width(dot.isComet ? 7 : 6)
            .height(dot.isComet ? 7 : 6)
            .fill(dot.isComet ? '#80F2FF' : '#C8A8FF')
            .position({ x: dot.x - 3.5, y: dot.y - 3.5 })
            .onClick(() => { this.onFocusPlanet(dot.englishName) })
        }, (dot: MinorBodyDot) => 'minor_' + dot.englishName)

        // Crisp collision-free planet labels
        ForEach(this.placedLabels(this.currentPlan()), (lbl: PlacedOrreryLabel) => {
          Text(lbl.nameZh)
            .fontSize(this.fs(9))
            .fontWeight(lbl.isSelected ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(lbl.isSelected ? '#FFD166' : (lbl.isEarth ? '#8CD4FF' : '#D8E7FA'))
            .textShadow({ radius: 3, color: '#CC030712', offsetX: 0, offsetY: 1 })
            .position({ x: lbl.x, y: lbl.y })
            .hitTestBehavior(HitTestMode.None)
        }, (lbl: PlacedOrreryLabel) => 'ap_lbl_' + lbl.id + '_' + String(this.is3DView) + '_' + String(this.innerOnly) + '_' + String(Math.round(lbl.lonDeg)))
      }
      .width('100%')
      .height(this.stageHeight())
      .backgroundColor(this.nightMode ? '#140606' : '#081024')
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .clip(true)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const w = Number(newArea.width)
        if (Number.isFinite(w) && w >= 180 && Math.abs(w - this.stageWidth) >= 2) {
          this.stageWidth = Math.round(w)
          setTimeout(() => this.redrawBackdrop(), 20)
        }
      })

      // Selected planet telemetry strip + one-tap focus in Star Map
      if (this.selectedNode(this.currentPlan()) !== undefined) {
        Row({ space: 8 }) {
          Image(orbResource(this.selectedNode(this.currentPlan())!.orbKey))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .draggable(false)
          Column({ space: 1 }) {
            Text(this.selectedNode(this.currentPlan())!.nameZh + ' · 日心黄经 ' + this.selectedNode(this.currentPlan())!.lonDeg.toFixed(1) + '°')
              .fontSize(this.fs(11))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('黄纬 ' + this.liveLatitudeFor(this.selectedNode(this.currentPlan())!.id).toFixed(1) + '° · 距日 ' + this.selectedNode(this.currentPlan())!.distAU.toFixed(2) + ' AU')
              .fontSize(this.fs(10))
              .fontColor(this.c.sub)
              .maxLines(1)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button('定位星图')
            .fontSize(this.fs(10))
            .fontColor(this.c.onAccent)
            .backgroundColor(this.c.accent)
            .borderRadius(UI_RADIUS_PILL)
            .constraintSize({ minHeight: this.ch(26) })
            .padding({ left: 10, right: 10 })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => {
              this.onFocusPlanet(this.selectedNode(this.currentPlan())!.id)
            })
        }
        .width('100%')
        .padding({ left: 9, right: 9, top: 6, bottom: 6 })
        .backgroundColor(this.c.bg)
        .border({ width: 0.6, color: this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
      }
    }
    .width('100%')
    .margin({ top: 2, bottom: 6 })
  }
}
