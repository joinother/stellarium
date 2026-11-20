import {
  OrreryPlanetState,
  clampOrreryDayOffset,
  formatOrreryOffsetBadge,
  offsetDaysToJd,
  parseHeliocentricPlanets,
  projectSolarSystemOrrery,
  routePlanetForCard
} from './AstronomyCardData'
import {
  SolarSystemOrreryStage,
  StarfieldLayer
} from './WidgetVisuals'

const solarSystemStorage: LocalStorage = new LocalStorage()

@Entry(solarSystemStorage)
@Component
struct SolarSystemCard {
  @LocalStorageProp('observerPlanet') observerPlanet: string = 'Earth'
  @LocalStorageProp('heliocentricPlanetsJson') heliocentricPlanetsJson: string = '[]'
  @LocalStorageProp('orreryDayOffset') orreryDayOffset: string = '0'
  @LocalStorageProp('orreryInnerOnly') orreryInnerOnly: string = '0'
  @LocalStorageProp('cardThemeStyle') cardThemeStyle: string = 'sky'
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'

  @State cardWidth: number = 320
  @State cardHeight: number = 160

  private isWide(): boolean { return this.cardWidth >= 230 }
  private isTall(): boolean { return this.cardHeight >= 230 }
  private isInnerOnly(): boolean { return this.orreryInnerOnly === '1' }

  private numericDayOffset(): number {
    return clampOrreryDayOffset(Number(this.orreryDayOffset))
  }

  private evalMs(): number {
    return Date.now() + this.numericDayOffset() * 86400000
  }

  private epochLabel(): string {
    return formatOrreryOffsetBadge(this.numericDayOffset(), this.evalMs())
  }

  private planets(): OrreryPlanetState[] {
    return parseHeliocentricPlanets(this.heliocentricPlanetsJson, Date.now(), this.numericDayOffset())
  }

  private summaryText(): string {
    const plan = projectSolarSystemOrrery(this.planets(), 220, 110, this.isInnerOnly(), 55)
    return plan.summaryLine
  }

  private featuredTelemetry(): OrreryPlanetState[] {
    const all = this.planets()
    if (this.isInnerOnly()) return all.filter((p: OrreryPlanetState) => p.isInner).slice(0, 4)
    const keys: string[] = ['Earth', 'Mars', 'Jupiter', 'Saturn']
    const out: OrreryPlanetState[] = []
    for (let i = 0; i < all.length; i++) {
      if (keys.includes(all[i].id)) out.push(all[i])
    }
    return out.slice(0, 4)
  }

  private topGradient(): string {
    return this.cardThemeStyle === 'deep' ? '#04060E' : '#060C1E'
  }

  private bottomGradient(): string {
    return this.cardThemeStyle === 'deep' ? '#0B1120' : '#102042'
  }

  private openOrreryInAstro(): void {
    const days = this.numericDayOffset()
    const targetJd = days !== 0
      ? Math.round((this.evalMs() / 86400000.0 + 2440587.5) * 100000) / 100000
      : offsetDaysToJd(Date.now(), 0)
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'astro',
        tab: 0,
        positionMode: 1,
        observerPlanet: routePlanetForCard(this.observerPlanet),
        jd: targetJd,
        landingTitle: '太阳系日心轨盘 · ' + this.epochLabel(),
        landingSource: 'card'
      }
    })
  }

  private triggerOverflowOrOpen(): void {
    if (this.cardOverflowMode === 'off') {
      this.openOrreryInAstro()
      return
    }
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'requestOverflow',
        formName: 'solar_system_card'
      }
    })
  }

  private stepDays(deltaDays: number): void {
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'stepOrreryDays',
        formName: 'solar_system_card',
        deltaDays: deltaDays
      }
    })
  }

  private resetDays(): void {
    if (this.numericDayOffset() === 0) {
      this.openOrreryInAstro()
      return
    }
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'resetOrreryState',
        formName: 'solar_system_card'
      }
    })
  }

  private toggleZoom(): void {
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'toggleOrreryZoom',
        formName: 'solar_system_card'
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      if (!this.isWide() && !this.isTall()) {
        // 2x2 Compact 3D Orrery
        Column() {
          Row() {
            Text('✦ 太阳系')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF4FF')
              .maxLines(1)
            Blank()
            Text(this.isInnerOnly() ? '内系' : '全系')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#9CD4FF')
              .height(22)
              .padding({ left: 8, right: 8 })
              .backgroundColor('#2E4678C4')
              .borderRadius(11)
              .onClick(() => this.toggleZoom())
          }
          .width('100%')

          Stack({ alignContent: Alignment.Center }) {
            SolarSystemOrreryStage({
              stageWidth: Math.max(122, Math.round(this.cardWidth - 18)),
              stageHeight: Math.max(76, Math.round(this.cardHeight - 62)),
              heliocentricPlanetsJson: this.heliocentricPlanetsJson,
              dayOffset: this.numericDayOffset(),
              innerOnly: this.isInnerOnly(),
              tiltDeg: 56,
              showLabels: false
            })
          }
          .layoutWeight(1)
          .width('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Row({ space: 4 }) {
            Text('‹30天')
              .fontSize(10)
              .fontColor('#CFE4FF')
              .height(22)
              .padding({ left: 6, right: 6 })
              .backgroundColor('#22FFFFFF')
              .borderRadius(11)
              .onClick(() => this.stepDays(-30))

            Text(this.numericDayOffset() === 0 ? '此刻' : (this.numericDayOffset() > 0 ? '+' + String(this.numericDayOffset()) + 'd' : String(this.numericDayOffset()) + 'd'))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.numericDayOffset() === 0 ? '#FFE29A' : '#8AD4FF')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(22)
              .backgroundColor('#1EFFFFFF')
              .borderRadius(11)
              .maxLines(1)
              .onClick(() => this.resetDays())

            Text('30天›')
              .fontSize(10)
              .fontColor('#CFE4FF')
              .height(22)
              .padding({ left: 6, right: 6 })
              .backgroundColor('#22FFFFFF')
              .borderRadius(11)
              .onClick(() => this.stepDays(30))
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding({ left: 11, right: 11, top: 9, bottom: 9 })
      } else if (!this.isTall()) {
        // 2x4 Wide 3D Solar System Orrery + Telemetry/Time Rail
        Row({ space: 8 }) {
          Stack({ alignContent: Alignment.Center }) {
            SolarSystemOrreryStage({
              stageWidth: Math.max(176, Math.round(this.cardWidth - 128)),
              stageHeight: Math.max(118, Math.round(this.cardHeight - 18)),
              heliocentricPlanetsJson: this.heliocentricPlanetsJson,
              dayOffset: this.numericDayOffset(),
              innerOnly: this.isInnerOnly(),
              tiltDeg: 55,
              showLabels: this.isInnerOnly()
            })
          }
          .layoutWeight(1)
          .height('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Column({ space: 6 }) {
            Row() {
              Text('太阳系仪')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(1)
              Blank()
              Text('↗')
                .fontSize(12)
                .fontColor('#9CD4FF')
            }
            .width('100%')
            .onClick(() => this.openOrreryInAstro())

            Text(this.epochLabel())
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.numericDayOffset() === 0 ? '#FFE29A' : '#8AD4FF')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => this.resetDays())

            Row({ space: 4 }) {
              Text(this.isInnerOnly() ? '内太阳系' : '全太阳系')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#EAF4FF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(24)
                .backgroundColor('#344678C4')
                .borderRadius(12)
                .onClick(() => this.toggleZoom())

              Text('+1年')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#CFE4FF')
                .textAlign(TextAlign.Center)
                .width(38)
                .height(24)
                .backgroundColor('#22FFFFFF')
                .borderRadius(12)
                .onClick(() => this.stepDays(365))
            }
            .width('100%')

            Blank()

            Row({ space: 4 }) {
              Text('-30d')
                .fontSize(10)
                .fontColor('#CFE4FF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(26)
                .backgroundColor('#22FFFFFF')
                .borderRadius(13)
                .onClick(() => this.stepDays(-30))

              Text('今')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFE29A')
                .textAlign(TextAlign.Center)
                .width(26)
                .height(26)
                .backgroundColor('#2E4678C4')
                .borderRadius(13)
                .onClick(() => this.resetDays())

              Text('+30d')
                .fontSize(10)
                .fontColor('#CFE4FF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(26)
                .backgroundColor('#22FFFFFF')
                .borderRadius(13)
                .onClick(() => this.stepDays(30))
            }
            .width('100%')
          }
          .width(106)
          .height('100%')
          .padding({ top: 3, bottom: 2 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 10, right: 12, top: 9, bottom: 9 })
      } else {
        // 4x4 Flagship 3D Solar System Orrery + Telemetry + Time Scrubber
        Column({ space: 6 }) {
          Row() {
            Column({ space: 2 }) {
              Text('✦ 太阳系仪 · ' + this.epochLabel())
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.summaryText())
                .fontSize(10)
                .fontColor('#B8D3F2')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text(this.isInnerOnly() ? '切至全系' : '切至内系')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF4FF')
              .height(26)
              .padding({ left: 10, right: 10 })
              .backgroundColor('#364678C4')
              .borderRadius(13)
              .onClick(() => this.toggleZoom())
          }
          .width('100%')

          Stack({ alignContent: Alignment.Center }) {
            SolarSystemOrreryStage({
              stageWidth: Math.max(250, Math.round(this.cardWidth - 22)),
              stageHeight: Math.max(150, Math.round(this.cardHeight - 122)),
              heliocentricPlanetsJson: this.heliocentricPlanetsJson,
              dayOffset: this.numericDayOffset(),
              innerOnly: this.isInnerOnly(),
              tiltDeg: 50,
              showLabels: true
            })
          }
          .layoutWeight(1)
          .width('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Row({ space: 6 }) {
            ForEach(this.featuredTelemetry(), (p: OrreryPlanetState) => {
              Column({ space: 1 }) {
                Row({ space: 3 }) {
                  Circle().width(5).height(5).fill(p.color)
                  Text(p.nameZh)
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#EAF4FF')
                }
                Text(String(Math.round(p.lonDeg)) + '° · ' + p.distAU.toFixed(1) + 'AU')
                  .fontSize(9)
                  .fontColor('#9FBAD8')
                  .maxLines(1)
              }
              .layoutWeight(1)
              .padding({ top: 4, bottom: 4 })
              .backgroundColor('#1AFFFFFF')
              .borderRadius(9)
              .alignItems(HorizontalAlign.Center)
            }, (p: OrreryPlanetState) => p.id)
          }
          .width('100%')

          Row({ space: 6 }) {
            Text('-30天')
              .fontSize(10)
              .fontColor('#DCEBFF')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(28)
              .backgroundColor('#22FFFFFF')
              .borderRadius(14)
              .onClick(() => this.stepDays(-30))

            Text('此刻')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFE29A')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(28)
              .backgroundColor('#324678C4')
              .borderRadius(14)
              .onClick(() => this.resetDays())

            Text('+30天')
              .fontSize(10)
              .fontColor('#DCEBFF')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(28)
              .backgroundColor('#22FFFFFF')
              .borderRadius(14)
              .onClick(() => this.stepDays(30))

            Text('+1年')
              .fontSize(10)
              .fontColor('#DCEBFF')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(28)
              .backgroundColor('#22FFFFFF')
              .borderRadius(14)
              .onClick(() => this.stepDays(365))

            Text('轨盘 ↗')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#8AD4FF')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(28)
              .backgroundColor('#2C1C3C6E')
              .borderRadius(14)
              .onClick(() => this.openOrreryInAstro())
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding({ left: 13, right: 13, top: 11, bottom: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 162,
      colors: [
        [this.topGradient(), 0.0],
        [this.bottomGradient(), 1.0]
      ]
    })
    .border({ width: 0.6, color: '#2878B8FF' })
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      if (typeof newSize.width === 'number' && newSize.width > 0) this.cardWidth = newSize.width
      if (typeof newSize.height === 'number' && newSize.height > 0) this.cardHeight = newSize.height
    })
    .onClick(() => this.openOrreryInAstro())
  }
}
