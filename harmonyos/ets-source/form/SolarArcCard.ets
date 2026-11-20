import {
  clockToTodayJd,
  computeDaylightDuration,
  computeGoldenHourClock,
  computeSolarArcProgress,
  estimateSolarTermZh,
  routePlanetForCard,
  solarStageFromAltitude
} from './AstronomyCardData'
import {
  CelestialOrbView,
  HorizonArcView,
  StarfieldLayer
} from './WidgetVisuals'

const solarArcStorage: LocalStorage = new LocalStorage()

interface SolarLightMilestone {
  label: string
  clock: string
  hint: string
}

@Entry(solarArcStorage)
@Component
struct SolarArcCard {
  @LocalStorageProp('observerPlanet') observerPlanet: string = 'Earth'
  @LocalStorageProp('observerPlanetName') observerPlanetName: string = '地球'
  @LocalStorageProp('sunRise') sunRise: string = '06:58'
  @LocalStorageProp('sunTransit') sunTransit: string = '11:58'
  @LocalStorageProp('sunSet') sunSet: string = '16:59'
  @LocalStorageProp('darkStart') darkStart: string = '18:32'
  @LocalStorageProp('sunAlt') sunAlt: string = '24.0'
  @LocalStorageProp('solarStage') solarStage: string = '白昼晴光'
  @LocalStorageProp('daylightDuration') daylightDuration: string = '10h 01m'
  @LocalStorageProp('goldenHourText') goldenHourText: string = '16:21'
  @LocalStorageProp('solarTermText') solarTermText: string = ''
  @LocalStorageProp('skyHexTop') skyHexTop: string = '#17488E'
  @LocalStorageProp('skyHexHorizon') skyHexHorizon: string = '#5B9AD6'
  @LocalStorageProp('cardThemeStyle') cardThemeStyle: string = 'sky'
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'

  @State cardWidth: number = 320
  @State cardHeight: number = 160
  @State selectedStageIndex: number = -1

  private isWide(): boolean { return this.cardWidth >= 230 }

  private numericSunAlt(): number {
    const v = Number(this.sunAlt)
    return Number.isFinite(v) ? v : 0
  }

  private altLabel(): string {
    const alt = Math.round(this.numericSunAlt())
    return (alt >= 0 ? '+' : '') + String(alt) + '°'
  }

  private stageLabel(): string {
    if (this.solarStage.trim().length > 0) return this.solarStage
    return solarStageFromAltitude(this.numericSunAlt())
  }

  private daylightLabel(): string {
    if (this.daylightDuration.trim().length > 0 && this.daylightDuration !== '—') return this.daylightDuration
    return computeDaylightDuration(this.sunRise, this.sunSet)
  }

  private goldenClock(): string {
    if (this.goldenHourText.trim().length > 0 && this.goldenHourText !== '—') return this.goldenHourText
    return computeGoldenHourClock(this.sunSet)
  }

  private solarTerm(): string {
    if (this.solarTermText.trim().length > 0) return this.solarTermText
    return estimateSolarTermZh(Date.now())
  }

  private solarProgress(): number {
    return computeSolarArcProgress(this.sunRise, this.sunSet, Date.now(), this.numericSunAlt())
  }

  private worldBadgeText(): string {
    if (this.observerPlanet.trim().toLowerCase() === 'sun' || this.observerPlanet.trim().toLowerCase() === 'earth') {
      return '☀ 太阳 · 地球 ↻'
    }
    return '☀ ' + this.observerPlanetName + ' ↻'
  }

  private milestones(): SolarLightMilestone[] {
    return [
      { label: '日出', clock: this.sunRise, hint: '日出时刻 · ' + this.sunRise },
      { label: '中天', clock: this.sunTransit, hint: '正午中天 · ' + this.sunTransit },
      { label: '黄金', clock: this.goldenClock(), hint: '傍晚黄金时刻 · ' + this.goldenClock() },
      { label: '暗夜', clock: this.darkStart, hint: '天文暗夜开启 · ' + this.darkStart }
    ]
  }

  private topGradient(): string {
    if (this.cardThemeStyle === 'deep') return '#0B0912'
    return /^#[0-9A-Fa-f]{6}$/.test(this.skyHexTop) ? this.skyHexTop : '#17488E'
  }

  private bottomGradient(): string {
    if (this.cardThemeStyle === 'deep') return '#221710'
    return /^#[0-9A-Fa-f]{6}$/.test(this.skyHexHorizon) ? this.skyHexHorizon : '#5B9AD6'
  }

  private openSunInSky(): void {
    const list = this.milestones()
    const hasMilestone = this.selectedStageIndex >= 0 && this.selectedStageIndex < list.length
    const chosen = hasMilestone ? list[this.selectedStageIndex] : undefined
    const targetJd = chosen !== undefined ? clockToTodayJd(chosen.clock, Date.now()) : 0
    const focusTarget = hasMilestone && this.selectedStageIndex === 3 ? '' : 'Sun'
    const landingTitle = chosen !== undefined
      ? chosen.hint
      : ('太阳 · ' + this.stageLabel() + ' ' + this.altLabel())
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'sky',
        observerPlanet: routePlanetForCard(this.observerPlanet),
        target: focusTarget,
        jd: targetJd,
        landingTitle: landingTitle,
        landingSource: 'card'
      }
    })
  }

  private cyclePlanet(): void {
    this.selectedStageIndex = -1
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'cyclePlanet',
        formName: 'solar_arc_card',
        currentPlanet: this.observerPlanet
      }
    })
  }

  private triggerOverflowOrOpen(): void {
    if (this.cardOverflowMode === 'off') {
      this.openSunInSky()
      return
    }
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'requestOverflow',
        formName: 'solar_arc_card'
      }
    })
  }

  private toggleMilestone(idx: number): void {
    animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, () => {
      this.selectedStageIndex = this.selectedStageIndex === idx ? -1 : idx
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: this.numericSunAlt(), themeStyle: this.cardThemeStyle })

      // Warm readability scrim so golden solar data stays crisp across daytime blue & dusk skies
      if (this.numericSunAlt() > -6 && this.cardThemeStyle !== 'deep') {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 165,
            colors: [
              ['#34080E1E', 0.0],
              ['#66090E1D', 1.0]
            ]
          })
          .hitTestBehavior(HitTestMode.None)
      }

      if (!this.isWide()) {
        // 2x2 Compact Solar Instrument
        Column() {
          Row() {
            Text(this.observerPlanet === 'Earth' || this.observerPlanet === 'Sun' ? '☀ 太阳 ↻' : ('☀ ' + this.observerPlanetName + ' ↻'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFF4D6')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .height(26)
              .padding({ left: 8, right: 9 })
              .backgroundColor('#38140C04')
              .borderRadius(13)
              .onClick(() => this.cyclePlanet())
            Blank()
            Text(this.altLabel())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFD166')
          }
          .width('100%')

          Column({ space: 2 }) {
            CelestialOrbView({
              orbBody: 'sun',
              orbSize: 66,
              showPhase: false,
              illumination: 100,
              phaseAge: 14
            })
            Text(this.stageLabel())
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
            altitudeDeg: this.numericSunAlt(),
            riseText: this.sunRise,
            setText: this.sunSet,
            customProgress: this.solarProgress(),
            accentColor: '#FFD166'
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 13, right: 13, top: 10, bottom: 9 })
      } else {
        // 2x4 Wide Solar Instrument + Interactive 4-Stage Sunlight Bar
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            CelestialOrbView({
              orbBody: 'sun',
              orbSize: 86,
              showPhase: false,
              illumination: 100,
              phaseAge: 14
            })
            Text('昼长 ' + this.daylightLabel())
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFE8B0')
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width(96)
          .height('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Column({ space: 5 }) {
            Row() {
              Column({ space: 2 }) {
                Text(this.worldBadgeText())
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFF3D2')
                  .height(28)
                  .padding({ left: 10, right: 10 })
                  .backgroundColor('#38140C04')
                  .borderRadius(14)
                  .maxLines(1)
                  .onClick(() => this.cyclePlanet())
                Text(this.selectedStageIndex >= 0
                  ? this.milestones()[this.selectedStageIndex].hint
                  : (this.stageLabel() + ' · ' + this.solarTerm()))
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.altLabel())
                .fontSize(19)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFD166')
                .margin({ left: 4 })
            }
            .width('100%')

            HorizonArcView({
              arcWidth: 176,
              arcHeight: 32,
              altitudeDeg: this.numericSunAlt(),
              riseText: this.sunRise,
              midFooterText: this.sunTransit !== '—' ? ('中天 ' + this.sunTransit) : '',
              setText: this.sunSet,
              customProgress: this.solarProgress(),
              accentColor: '#FFD166'
            })

            // Interactive 4-stage daylight & twilight quick-peek bar (zero app launch!)
            Row({ space: 5 }) {
              ForEach(this.milestones(), (item: SolarLightMilestone, idx: number) => {
                Column({ space: 1 }) {
                  Text(item.label)
                    .fontSize(9)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.selectedStageIndex === idx ? '#1C1102' : '#DDE8F8')
                    .maxLines(1)
                  Text(item.clock)
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.selectedStageIndex === idx ? '#1C1102' : '#FFE09A')
                    .maxLines(1)
                }
                .layoutWeight(1)
                .height(39)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(this.selectedStageIndex === idx ? '#FFD166' : '#32090F1E')
                .borderRadius(11)
                .border({
                  width: this.selectedStageIndex === idx ? 0 : 0.5,
                  color: '#2AFFE09A'
                })
                .onClick(() => this.toggleMilestone(idx))
              }, (item: SolarLightMilestone, idx: number) => item.label + '_' + String(idx))
            }
            .width('100%')
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 13, right: 14, top: 11, bottom: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 165,
      colors: [
        [this.topGradient(), 0.0],
        [this.bottomGradient(), 1.0]
      ]
    })
    .border({ width: 0.6, color: '#30FFD166' })
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      if (typeof newSize.width === 'number' && newSize.width > 0) this.cardWidth = newSize.width
      if (typeof newSize.height === 'number' && newSize.height > 0) this.cardHeight = newSize.height
    })
    .onClick(() => this.openSunInSky())
  }
}
