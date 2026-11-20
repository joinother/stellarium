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

// High-craft 3D textured celestial globe with optional dynamic phase terminator shadow
// (real earthshine transparency so lunar maria / planetary oceans remain faintly visible).
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

  private diskDiameter(): number {
    // Textures are rendered at radius_ratio = 0.43 (diameter = 0.86 of PNG box)
    return Math.round(this.orbSize * 0.86)
  }

  private shadowShiftX(): number {
    const frac = Math.max(0, Math.min(100, this.illumination)) / 100
    const d = this.diskDiameter()
    const waxing = this.phaseAge <= 14.765
    // At 0% illum: shadow centered (0); at 50%: shifted by 0.5*d; at 100%: shifted completely off disk
    const shift = frac * d * 1.04
    return waxing ? -shift : shift
  }

  private shouldRenderShadow(): boolean {
    if (!this.showPhase || this.isRinged()) return false
    if (!Number.isFinite(this.illumination) || this.illumination < 0) return false
    return this.illumination < 96
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // Soft atmospheric outer glow
      if (this.glowIntensity > 0) {
        Circle()
          .width(this.orbSize * 1.24)
          .height(this.orbSize * 1.24)
          .fill(Color.Transparent)
          .radialGradient({
            center: ['50%', '50%'],
            radius: this.orbSize * 0.62,
            colors: [
              [orbGlowColor(this.orbBody), 0.0],
              ['#00000000', 1.0]
            ]
          })
          .opacity(this.glowIntensity)
      }

      // Real orthographically-rendered 3D planet / moon texture
      Image(orbResource(this.orbBody))
        .width(this.orbSize)
        .height(this.orbSize)
        .objectFit(ImageFit.Contain)
        .draggable(false)

      // Dynamic phase terminator shadow clipped tightly to the sphere disk
      if (this.shouldRenderShadow()) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(this.diskDiameter() * 1.04)
            .height(this.diskDiameter() * 1.04)
            .fill('#C8050A18')
            .translate({ x: this.shadowShiftX(), y: 0 })
        }
        .width(this.diskDiameter())
        .height(this.diskDiameter())
        .borderRadius(this.diskDiameter() / 2)
        .clip(true)
      }
    }
    .width(this.orbSize)
    .height(this.orbSize)
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

// Luminous semi-circular horizon & companion altitude arc (100% vp-native, DPI-independent)
@Component
export struct HorizonArcView {
  @Prop arcWidth: number = 128
  @Prop arcHeight: number = 42
  @Prop altitudeDeg: number = 32
  @Prop riseText: string = '—'
  @Prop setText: string = '—'
  @Prop accentColor: string = '#9EC5FF'

  private dotProgress(): number {
    // Map altitude (-20..90 deg) onto arc progress (0.08..0.92), peaking near 0.5
    const clamped = Math.max(-15, Math.min(90, this.altitudeDeg))
    if (clamped <= 0) return 0.12
    return 0.16 + (clamped / 90) * 0.34
  }

  private arcDiameterX(): number {
    return this.arcWidth * 0.84
  }

  private arcRadiusY(): number {
    return this.arcHeight - 10
  }

  private dotX(): number {
    const theta = Math.PI * (1 - this.dotProgress())
    const rx = this.arcDiameterX() * 0.5
    return this.arcWidth * 0.5 + rx * Math.cos(theta) - 4
  }

  private dotY(): number {
    const theta = Math.PI * (1 - this.dotProgress())
    const ry = this.arcRadiusY()
    const baseY = this.arcHeight - 5
    return baseY - ry * Math.sin(theta) - 4
  }

  build() {
    Column({ space: 3 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        // Upper semi-elliptical dashed orbital arc (100% vp units, clipped cleanly at horizon)
        Stack({ alignContent: Alignment.Top }) {
          Column()
            .width(this.arcDiameterX())
            .height(this.arcRadiusY() * 2)
            .borderRadius(this.arcDiameterX() * 0.5)
            .border({
              width: 1.4,
              color: this.accentColor,
              style: BorderStyle.Dashed
            })
            .opacity(0.55)
        }
        .width(this.arcWidth)
        .height(this.arcHeight - 5)
        .clip(true)
        .position({ x: 0, y: 0 })

        // Horizon baseline
        Rect()
          .width(this.arcWidth)
          .height(1)
          .fill('#42FFFFFF')
          .position({ x: 0, y: this.arcHeight - 5 })

        // Current body marker dot on the orbital arc
        Circle()
          .width(8)
          .height(8)
          .fill(this.altitudeDeg > 0 ? this.accentColor : '#8899B0C8')
          .shadow({ radius: 6, color: this.accentColor, offsetX: 0, offsetY: 0 })
          .position({ x: this.dotX(), y: this.dotY() })
      }
      .width(this.arcWidth)
      .height(this.arcHeight)

      Row() {
        Text('升 ' + this.riseText)
          .fontSize(10)
          .fontWeight(FontWeight.Regular)
          .fontColor('#B8D0E8FF')
          .maxLines(1)
        Blank()
        Text('落 ' + this.setText)
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

// Compact 5-day lunar/companion phase progression strip (for 2*4 CompanionArcCard)
@Component
export struct MiniPhaseStripView {
  @Prop phaseAge: number = 10
  @Prop nowMs: number = 0

  private days(): MiniPhaseDay[] {
    return buildMiniPhaseStrip(this.phaseAge, this.nowMs > 0 ? this.nowMs : Date.now())
  }

  private miniShadowShift(illum: number, age: number): number {
    const frac = Math.max(0, Math.min(100, illum)) / 100
    const waxing = age <= 14.765
    return (waxing ? -1 : 1) * frac * 17
  }

  build() {
    Row({ space: 6 }) {
      ForEach(this.days(), (day: MiniPhaseDay) => {
        Column({ space: 3 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle()
              .width(16)
              .height(16)
              .fill('#E6EEFF')
            if (day.illumination < 96) {
              Stack({ alignContent: Alignment.Center }) {
                Circle()
                  .width(16)
                  .height(16)
                  .fill('#DD0A1226')
                  .translate({ x: this.miniShadowShift(day.illumination, day.age), y: 0 })
              }
              .width(16)
              .height(16)
              .borderRadius(8)
              .clip(true)
            }
          }
          .width(20)
          .height(20)
          .borderRadius(10)
          .border({
            width: day.isToday ? 1 : 0,
            color: day.isToday ? '#99C7E0FF' : Color.Transparent
          })

          Text(day.label)
            .fontSize(10)
            .fontWeight(day.isToday ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(day.isToday ? '#F2F7FF' : '#88C8DCFF')
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Center)
      }, (day: MiniPhaseDay, index: number) => day.label + '_' + String(index))
    }
    .justifyContent(FlexAlign.SpaceBetween)
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
