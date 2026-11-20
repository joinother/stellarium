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
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF4FF')
              .maxLines(1)
            Blank()
            Text(this.isInnerOnly() ? '内系' : '全系')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#B8E0FF')
              .height(26)
              .padding({ left: 9, right: 9 })
              .backgroundColor('#364678C4')
              .borderRadius(13)
              .onClick(() => this.toggleZoom())
          }
          .width('100%')

          Stack({ alignContent: Alignment.Center }) {
            SolarSystemOrreryStage({
              stageWidth: Math.max(126, Math.round(this.cardWidth - 16)),
              stageHeight: Math.max(76, Math.round(this.cardHeight - 66)),
              heliocentricPlanetsJson: this.heliocentricPlanetsJson,
              dayOffset: this.numericDayOffset(),
              innerOnly: this.isInnerOnly(),
              tiltDeg: 54,
              showLabels: false
            })
          }
          .layoutWeight(1)
          .width('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Row({ space: 5 }) {
            Text('‹1月')
              .fontSize(10.5)
              .fontColor('#D4E8FF')
              .textAlign(TextAlign.Center)
              .height(28)
              .padding({ left: 7, right: 7 })
              .backgroundColor('#24FFFFFF')
              .borderRadius(14)
              .onClick(() => this.stepDays(-30))

            Text(this.numericDayOffset() === 0 ? '此刻' : (this.numericDayOffset() > 0 ? '+' + String(this.numericDayOffset()) + '天' : String(this.numericDayOffset()) + '天'))
              .fontSize(10.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.numericDayOffset() === 0 ? '#FFE29A' : '#8AD4FF')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(28)
              .backgroundColor('#2C4678C4')
              .borderRadius(14)
              .maxLines(1)
              .onClick(() => this.resetDays())

            Text('1月›')
              .fontSize(10.5)
              .fontColor('#D4E8FF')
              .textAlign(TextAlign.Center)
              .height(28)
              .padding({ left: 7, right: 7 })
              .backgroundColor('#24FFFFFF')
              .borderRadius(14)
              .onClick(() => this.stepDays(30))
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding({ left: 11, right: 11, top: 9, bottom: 9 })
      } else if (!this.isTall()) {
        // 2x4 Wide 3D Solar System Orrery: generous stage + clear 2-tier controls (zero cramped micro-buttons)
        Row({ space: 10 }) {
          Stack({ alignContent: Alignment.Center }) {
            SolarSystemOrreryStage({
              stageWidth: Math.max(176, Math.round(this.cardWidth - 134)),
              stageHeight: Math.max(118, Math.round(this.cardHeight - 16)),
              heliocentricPlanetsJson: this.heliocentricPlanetsJson,
              dayOffset: this.numericDayOffset(),
              innerOnly: this.isInnerOnly(),
              tiltDeg: 52,
              showLabels: this.isInnerOnly()
            })
          }
          .layoutWeight(1)
          .height('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Column({ space: 6 }) {
            // Tier 1: Identity + Epoch status + Scale toggle
            Row() {
              Text('太阳系仪')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(1)
              Blank()
              Text('↗')
                .fontSize(13)
                .fontColor('#9CD4FF')
            }
            .width('100%')
            .onClick(() => this.openOrreryInAstro())

            Text(this.epochLabel())
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.numericDayOffset() === 0 ? '#FFE29A' : '#8AD4FF')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => this.resetDays())

            Text(this.isInnerOnly() ? '内太阳系 · 切全系 ↻' : '全太阳系 · 切内系 ↻')
              .fontSize(10.5)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF4FF')
              .textAlign(TextAlign.Center)
              .width('100%')
              .height(30)
              .backgroundColor('#384678C4')
              .borderRadius(15)
              .maxLines(1)
              .onClick(() => this.toggleZoom())

            Blank()

            // Tier 2: Spacious 3-button time scrubber (32vp tall, easy thumb hit)
            Row({ space: 4 }) {
              Text('-1月')
                .fontSize(10.5)
                .fontWeight(FontWeight.Medium)
                .fontColor('#D8ECFF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(32)
                .backgroundColor('#24FFFFFF')
                .borderRadius(16)
                .onClick(() => this.stepDays(-30))

              Text('今')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFE29A')
                .textAlign(TextAlign.Center)
                .width(30)
                .height(32)
                .backgroundColor('#344678C4')
                .borderRadius(16)
                .onClick(() => this.resetDays())

              Text('+1月')
                .fontSize(10.5)
                .fontWeight(FontWeight.Medium)
                .fontColor('#D8ECFF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(32)
                .backgroundColor('#24FFFFFF')
                .borderRadius(16)
                .onClick(() => this.stepDays(30))
            }
            .width('100%')
          }
          .width(114)
          .height('100%')
          .padding({ top: 3, bottom: 2 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 10, right: 12, top: 9, bottom: 9 })
      } else {
        // 4x4 Flagship 3D Solar System Orrery + Telemetry + Clean 2-Group Action Bar
        Column({ space: 7 }) {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text('✦ 太阳系仪 · ' + this.epochLabel())
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.summaryText())
                .fontSize(10.5)
                .fontColor('#B8D3F2')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text(this.isInnerOnly() ? '切至全系' : '切至内系')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF4FF')
              .height(30)
              .padding({ left: 12, right: 12 })
              .backgroundColor('#384678C4')
              .borderRadius(15)
              .onClick(() => this.toggleZoom())
          }
          .width('100%')

          Stack({ alignContent: Alignment.Center }) {
            SolarSystemOrreryStage({
              stageWidth: Math.max(250, Math.round(this.cardWidth - 22)),
              stageHeight: Math.max(150, Math.round(this.cardHeight - 134)),
              heliocentricPlanetsJson: this.heliocentricPlanetsJson,
              dayOffset: this.numericDayOffset(),
              innerOnly: this.isInnerOnly(),
              tiltDeg: 48,
              showLabels: true
            })
          }
          .layoutWeight(1)
          .width('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Row({ space: 6 }) {
            ForEach(this.featuredTelemetry(), (p: OrreryPlanetState) => {
              Column({ space: 2 }) {
                Row({ space: 4 }) {
                  Circle().width(5.5).height(5.5).fill(p.color)
                  Text(p.nameZh)
                    .fontSize(10.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#EAF4FF')
                }
                Text(String(Math.round(p.lonDeg)) + '° · ' + p.distAU.toFixed(1) + 'AU')
                  .fontSize(9.5)
                  .fontColor('#A4C0E0')
                  .maxLines(1)
              }
              .layoutWeight(1)
              .padding({ top: 5, bottom: 5 })
              .backgroundColor('#1EFFFFFF')
              .borderRadius(10)
              .alignItems(HorizontalAlign.Center)
            }, (p: OrreryPlanetState) => p.id)
          }
          .width('100%')

          // Clean 2-group bottom bar: Time Scrubber group + Primary Enter CTA (34vp tall)
          Row({ space: 6 }) {
            Row({ space: 3 }) {
              Text('-1月')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#DCEBFF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(34)
                .backgroundColor('#22FFFFFF')
                .borderRadius(17)
                .onClick(() => this.stepDays(-30))

              Text('此刻')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFE29A')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(34)
                .backgroundColor('#324678C4')
                .borderRadius(17)
                .onClick(() => this.resetDays())

              Text('+1月')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#DCEBFF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(34)
                .backgroundColor('#22FFFFFF')
                .borderRadius(17)
                .onClick(() => this.stepDays(30))

              Text('+1年')
                .fontSize(11)
                .fontColor('#B8D4F4')
                .textAlign(TextAlign.Center)
                .layoutWeight(0.9)
                .height(34)
                .backgroundColor('#18FFFFFF')
                .borderRadius(17)
                .onClick(() => this.stepDays(365))
            }
            .layoutWeight(1)

            Text('轨盘 ↗')
              .fontSize(11.5)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .textAlign(TextAlign.Center)
              .width(68)
              .height(34)
              .backgroundColor('#D82B64B8')
              .borderRadius(17)
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
