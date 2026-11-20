import {
  CompactPlanetItem,
  formatPlanetDisplayList,
  parseVisiblePlanets
} from './AstronomyCardData'
import {
  CelestialOrbView,
  PlanetVisibilityRow,
  StarfieldLayer,
  fallbackPlanetRows
} from './WidgetVisuals'

const skyWindowStorage: LocalStorage = new LocalStorage()

@Entry(skyWindowStorage)
@Component
struct SkyWindowCard {
  @LocalStorageProp('observerPlanet') observerPlanet: string = 'Earth'
  @LocalStorageProp('observerPlanetName') observerPlanetName: string = '地球'
  @LocalStorageProp('companionName') companionName: string = '月球'
  @LocalStorageProp('companionRole') companionRole: string = 'moon'
  @LocalStorageProp('orbBody') orbBody: string = 'moon'
  @LocalStorageProp('moonPhase') moonPhase: string = '今夜月相'
  @LocalStorageProp('moonIllumination') moonIllumination: string = '72'
  @LocalStorageProp('moonAge') moonAge: string = '10'
  @LocalStorageProp('moonSummary') moonSummary: string = '72% 照明'
  @LocalStorageProp('observationSummary') observationSummary: string = '暗夜观测'
  @LocalStorageProp('darkStart') darkStart: string = '—'
  @LocalStorageProp('darkEnd') darkEnd: string = '—'
  @LocalStorageProp('planetNames') planetNames: string = '打开星图同步星历'
  @LocalStorageProp('visiblePlanetsJson') visiblePlanetsJson: string = '[]'
  @LocalStorageProp('skyHexTop') skyHexTop: string = '#070E22'
  @LocalStorageProp('skyHexHorizon') skyHexHorizon: string = '#172C52'
  @LocalStorageProp('sunAlt') sunAlt: string = '-18.0'
  @LocalStorageProp('companionAlt') companionAlt: string = '28.0'
  @LocalStorageProp('nextEventTitle') nextEventTitle: string = '等待星历同步'
  @LocalStorageProp('nextEventCountdown') nextEventCountdown: string = '查看日历'
  @LocalStorageProp('nextEventJd') nextEventJd: string = '0'
  @LocalStorageProp('nextEventTarget') nextEventTarget: string = ''
  @LocalStorageProp('dataStatus') dataStatus: string = '本地快照'
  @LocalStorageProp('updatedAt') updatedAt: string = '离线推演'
  @LocalStorageProp('cardThemeStyle') cardThemeStyle: string = 'sky'
  @LocalStorageProp('cardLabelStyle') cardLabelStyle: string = 'name'
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'

  @State cardWidth: number = 160
  @State cardHeight: number = 160

  private isWide(): boolean { return this.cardWidth >= 230 }
  private isTall(): boolean { return this.cardHeight >= 230 }

  private safeHex(hex: string, fallback: string): string {
    return /^#[0-9A-Fa-f]{6}$/.test(hex) ? hex : fallback
  }

  private topGradient(): string {
    if (this.cardThemeStyle === 'deep') return '#050811'
    return this.safeHex(this.skyHexTop, '#070E22')
  }

  private bottomGradient(): string {
    if (this.cardThemeStyle === 'deep') return '#0D162B'
    return this.safeHex(this.skyHexHorizon, '#172C52')
  }

  private numericIllum(): number {
    const v = Number(this.moonIllumination)
    return Number.isFinite(v) ? v : -1
  }

  private numericAge(): number {
    const v = Number(this.moonAge)
    return Number.isFinite(v) ? v : 10
  }

  private numericSunAlt(): number {
    const v = Number(this.sunAlt)
    return Number.isFinite(v) ? v : -18
  }

  private shouldShowPhaseShadow(): boolean {
    const body = this.orbBody.trim().toLowerCase()
    return body === 'moon' || body === 'earth'
  }

  private planetStrip(): string {
    return formatPlanetDisplayList(this.visiblePlanetsJson, this.planetNames, this.cardLabelStyle)
  }

  private planetRows(): CompactPlanetItem[] {
    return fallbackPlanetRows(parseVisiblePlanets(this.visiblePlanetsJson))
  }

  private isStale(): boolean {
    return this.dataStatus === '旧快照'
  }

  private openSky(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'sky',
        observerPlanet: this.observerPlanet
      }
    })
  }

  private openCalendarEvent(): void {
    const jdVal = Number(this.nextEventJd)
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'calendar',
        observerPlanet: this.observerPlanet,
        target: this.nextEventTarget,
        jd: Number.isFinite(jdVal) && jdVal > 0 ? jdVal : 0
      }
    })
  }

  private triggerOverflowOrOpen(): void {
    if (this.cardOverflowMode === 'off') {
      this.openSky()
      return
    }
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'requestOverflow',
        formName: 'sky_window_card'
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Subtle starfield when sky is dark
      StarfieldLayer({ sunAlt: this.numericSunAlt(), themeStyle: this.cardThemeStyle })

      // Daytime legibility scrim so vivid blue/ochre daytime skies keep >=4.5:1 text contrast
      if (this.numericSunAlt() > -4 && this.cardThemeStyle !== 'deep') {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 170,
            colors: [
              ['#24061024', 0.0],
              ['#4E061024', 1.0]
            ]
          })
          .hitTestBehavior(HitTestMode.None)
      }

      // Delicate bottom horizon atmospheric glow
      Column()
        .width('100%')
        .height(this.isTall() ? 72 : 44)
        .position({ x: 0, y: '100%' })
        .translate({ y: this.isTall() ? -72 : -44 })
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            ['#00FFFFFF', 0.0],
            ['#18FFFFFF', 1.0]
          ]
        })
        .hitTestBehavior(HitTestMode.None)

      // Main adaptive layout
      if (!this.isWide() && !this.isTall()) {
        // 2x2 Compact Sky Window
        Column() {
          Row() {
            Row({ space: 4 }) {
              Circle()
                .width(5)
                .height(5)
                .fill(this.isStale() ? '#FFB74D' : '#8AD4FF')
              Text(this.observerPlanetName)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#EBF4FF')
                .maxLines(1)
            }
            .padding({ left: 7, right: 8, top: 3, bottom: 3 })
            .backgroundColor('#26081224')
            .borderRadius(10)

            Blank()

            Text(this.moonSummary)
              .fontSize(10)
              .fontWeight(FontWeight.Regular)
              .fontColor('#B8DCEEFF')
              .maxLines(1)
          }
          .width('100%')

          Row({ space: 6 }) {
            Column({ space: 2 }) {
              Text(this.observationSummary)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.moonPhase)
                .fontSize(11)
                .fontWeight(FontWeight.Regular)
                .fontColor('#CCE4F6FF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Stack() {
              CelestialOrbView({
                orbBody: this.orbBody,
                orbSize: 56,
                showPhase: this.shouldShowPhaseShadow(),
                illumination: this.numericIllum(),
                phaseAge: this.numericAge()
              })
            }
            .onClick(() => this.triggerOverflowOrOpen())
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)

          Row() {
            Text(this.planetStrip())
              .fontSize(10)
              .fontWeight(FontWeight.Regular)
              .fontColor('#A8D8ECFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding({ left: 13, right: 12, top: 11, bottom: 11 })
      } else {
        // 2x4 & 4x4 Observatory Window
        Column({ space: this.isTall() ? 10 : 6 }) {
          Row({ space: 10 }) {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Row({ space: 4 }) {
                  Circle()
                    .width(5)
                    .height(5)
                    .fill(this.isStale() ? '#FFB74D' : '#8AD4FF')
                  Text(this.observerPlanetName + ' · 天穹之窗')
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#F0F7FF')
                    .maxLines(1)
                }
                .padding({ left: 8, right: 9, top: 3, bottom: 3 })
                .backgroundColor('#2E071022')
                .borderRadius(10)

                if (this.isStale()) {
                  Text('待刷新')
                    .fontSize(10)
                    .fontColor('#FFD27F')
                }
              }

              Text(this.observationSummary)
                .fontSize(this.isTall() ? 20 : 18)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 2 })

              Text(this.observerPlanet === 'Earth'
                ? ('天文暗夜 ' + this.darkStart + ' – ' + this.darkEnd)
                : (this.companionName + ' · ' + this.moonPhase))
                .fontSize(11)
                .fontWeight(FontWeight.Regular)
                .fontColor('#CCE4F7FF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              if (!this.isTall()) {
                Row({ space: 6 }) {
                  Text('可见行星')
                    .fontSize(10)
                    .fontColor('#8CC2DEFF')
                  Text(this.planetStrip())
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#EBF5FF')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
                .margin({ top: 4 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // Hero 3D Textured Celestial Orb (tap triggers API 20 Overflow!)
            Column({ space: 2 }) {
              CelestialOrbView({
                orbBody: this.orbBody,
                orbSize: this.isTall() ? 82 : 72,
                showPhase: this.shouldShowPhaseShadow(),
                illumination: this.numericIllum(),
                phaseAge: this.numericAge()
              })
              Text(this.companionName + ' ' + this.moonSummary)
                .fontSize(10)
                .fontWeight(FontWeight.Regular)
                .fontColor('#C4DDF4FF')
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Center)
            .onClick(() => this.triggerOverflowOrOpen())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // 4x4 Expanded Planet Visibility Bars + Upcoming Event Ticker
          if (this.isTall()) {
            Column({ space: 9 }) {
              Row() {
                Text('今夜行星可见性')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#C6E2FFFF')
                Blank()
                Text(this.updatedAt)
                  .fontSize(10)
                  .fontColor('#8CC2DEFF')
              }
              .width('100%')

              if (this.planetRows().length > 0) {
                ForEach(this.planetRows(), (p: CompactPlanetItem) => {
                  PlanetVisibilityRow({
                    itemName: p.n,
                    itemSymbol: p.s,
                    labelStyle: this.cardLabelStyle,
                    visible: p.v,
                    altitude: p.a,
                    riseText: p.r,
                    setText: p.t
                  })
                }, (p: CompactPlanetItem, idx: number) => p.e + '_' + String(idx))
              } else {
                Text(this.planetNames)
                  .fontSize(12)
                  .fontColor('#A8C8E8FF')
                  .maxLines(1)
              }
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.SpaceEvenly)
            .padding({ left: 13, right: 13, top: 10, bottom: 10 })
            .backgroundColor('#2B060D1E')
            .borderRadius(15)

            // Independent hotspot for upcoming astronomical event
            Row({ space: 8 }) {
              Circle()
                .width(6)
                .height(6)
                .fill('#8AD4FF')
              Text(this.nextEventTitle)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#F4F9FF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(this.nextEventCountdown)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#9ED2FF')
                .maxLines(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor('#36050B1A')
            .borderRadius(13)
            .onClick(() => this.openCalendarEvent())
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: 15, right: 14, top: 13, bottom: 13 })
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 170,
      colors: [
        [this.topGradient(), 0.0],
        [this.bottomGradient(), 1.0]
      ]
    })
    .border({ width: 0.6, color: '#24FFFFFF' })
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      if (typeof newSize.width === 'number' && newSize.width > 0) this.cardWidth = newSize.width
      if (typeof newSize.height === 'number' && newSize.height > 0) this.cardHeight = newSize.height
    })
    .onClick(() => this.openSky())
  }
}
