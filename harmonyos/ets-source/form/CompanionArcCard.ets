import {
  CelestialOrbView,
  HorizonArcView,
  MiniPhaseStripView,
  StarfieldLayer
} from './WidgetVisuals'

const companionArcStorage: LocalStorage = new LocalStorage()

@Entry(companionArcStorage)
@Component
struct CompanionArcCard {
  @LocalStorageProp('observerPlanet') observerPlanet: string = 'Earth'
  @LocalStorageProp('observerPlanetName') observerPlanetName: string = '地球'
  @LocalStorageProp('companionName') companionName: string = '月球'
  @LocalStorageProp('companionRole') companionRole: string = 'moon'
  @LocalStorageProp('orbBody') orbBody: string = 'moon'
  @LocalStorageProp('moonPhase') moonPhase: string = '今夜月相'
  @LocalStorageProp('moonIllumination') moonIllumination: string = '72'
  @LocalStorageProp('moonAge') moonAge: string = '10'
  @LocalStorageProp('moonSummary') moonSummary: string = '72% 照明'
  @LocalStorageProp('moonRise') moonRise: string = '—'
  @LocalStorageProp('moonSet') moonSet: string = '—'
  @LocalStorageProp('companionAlt') companionAlt: string = '28.0'
  @LocalStorageProp('skyHexHorizon') skyHexHorizon: string = '#142442'
  @LocalStorageProp('dataStatus') dataStatus: string = '本地快照'
  @LocalStorageProp('cardThemeStyle') cardThemeStyle: string = 'sky'
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'

  @State cardWidth: number = 160
  @State cardHeight: number = 160

  private isWide(): boolean { return this.cardWidth >= 230 }

  private numericIllum(): number {
    const v = Number(this.moonIllumination)
    return Number.isFinite(v) ? v : -1
  }

  private numericAge(): number {
    const v = Number(this.moonAge)
    return Number.isFinite(v) ? v : 10
  }

  private numericAlt(): number {
    const v = Number(this.companionAlt)
    return Number.isFinite(v) ? v : 28
  }

  private accentColor(): string {
    const body = this.orbBody.trim().toLowerCase()
    if (body === 'earth') return '#74BFFF'
    if (body === 'saturn' || body === 'titan') return '#F6CE88'
    if (body === 'mars') return '#F09B6B'
    return '#C8DCFF'
  }

  private bottomTint(): string {
    if (this.cardThemeStyle === 'deep') return '#0B1224'
    return /^#[0-9A-Fa-f]{6}$/.test(this.skyHexHorizon) ? this.skyHexHorizon : '#12203B'
  }

  private showPhaseShadow(): boolean {
    const body = this.orbBody.trim().toLowerCase()
    return body === 'moon' || body === 'earth'
  }

  private openDetail(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'astro',
        observerPlanet: this.observerPlanet
      }
    })
  }

  private triggerOverflowOrOpen(): void {
    if (this.cardOverflowMode === 'off') {
      this.openDetail()
      return
    }
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'requestOverflow',
        formName: 'companion_arc_card'
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      if (!this.isWide()) {
        // 2x2 Compact Celestial Arc Instrument
        Column() {
          Row() {
            Text(this.observerPlanet === 'Earth' ? this.companionName : (this.observerPlanetName + '·' + this.companionName))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#D6E6FF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.numericIllum() >= 0 ? (String(Math.round(this.numericIllum())) + '%') : '—')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentColor())
          }
          .width('100%')

          Column({ space: 2 }) {
            CelestialOrbView({
              orbBody: this.orbBody,
              orbSize: 64,
              showPhase: this.showPhaseShadow(),
              illumination: this.numericIllum(),
              phaseAge: this.numericAge()
            })
            Text(this.moonPhase)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.triggerOverflowOrOpen())

          HorizonArcView({
            arcWidth: 122,
            arcHeight: 28,
            altitudeDeg: this.numericAlt(),
            riseText: this.moonRise,
            setText: this.moonSet,
            accentColor: this.accentColor()
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 13, right: 13, top: 10, bottom: 9 })
      } else {
        // 2x4 Wide Companion Arc + 5-Day Mini Phase Progression Strip
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            CelestialOrbView({
              orbBody: this.orbBody,
              orbSize: 86,
              showPhase: this.showPhaseShadow(),
              illumination: this.numericIllum(),
              phaseAge: this.numericAge()
            })
            Text((this.companionRole === 'parent-planet' || this.companionRole === 'host') ? ('宿主 · ' + this.companionName) : this.moonPhase)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#E8F2FF')
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width(100)
          .height('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Column({ space: 6 }) {
            Row() {
              Column({ space: 1 }) {
                Text(this.observerPlanetName + ' · 星历弧盘')
                  .fontSize(10)
                  .fontColor('#8FB6DDFF')
                  .maxLines(1)
                Text(this.moonPhase)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.numericIllum() >= 0 ? (String(Math.round(this.numericIllum())) + '%') : '—')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.accentColor())
            }
            .width('100%')

            HorizonArcView({
              arcWidth: 172,
              arcHeight: 34,
              altitudeDeg: this.numericAlt(),
              riseText: this.moonRise,
              setText: this.moonSet,
              accentColor: this.accentColor()
            })

            MiniPhaseStripView({
              phaseAge: this.numericAge(),
              nowMs: Date.now()
            })
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 14, right: 15, top: 12, bottom: 11 })
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 165,
      colors: [
        ['#050914', 0.0],
        [this.bottomTint(), 1.0]
      ]
    })
    .border({ width: 0.6, color: '#22FFFFFF' })
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      if (typeof newSize.width === 'number' && newSize.width > 0) this.cardWidth = newSize.width
      if (typeof newSize.height === 'number' && newSize.height > 0) this.cardHeight = newSize.height
    })
    .onClick(() => this.openDetail())
  }
}
