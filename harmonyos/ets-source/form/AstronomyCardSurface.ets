import { Theme } from '@kit.ArkUI'
import { AstroColors, DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../state/StellariumTheme'

@ComponentV2
struct AstronomyFact {
  @Param label: string = ''
  @Param value: string = '—'
  @Local c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 3 }) {
      Text(this.label)
        .fontSize(10)
        .fontColor(this.c.tertiary)
        .maxLines(1)
      Text(this.value.length > 0 ? this.value : '—')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textStrong)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ left: 11, right: 11, top: 8, bottom: 8 })
    .backgroundColor(this.c.input)
    .borderRadius(14)
  }
}

@ComponentV2
export struct AstronomyCardSurface {
  @Param kind: string = 'overview'
  @Local cardHeight: number = 160
  @Local cardWidth: number = 320
  @Consumer() moonPhase: string = '今夜月相'
  @Consumer() moonIllumination: string = '-1'
  @Consumer() moonAge: string = '0'
  @Consumer() moonSummary: string = '最近星历'
  @Consumer() planetSummary: string = '今晚行星'
  @Consumer() planetNames: string = '本地星体目录已就绪'
  @Consumer() meteorSummary: string = '流星雨活动'
  @Consumer() meteorRate: string = '—'
  @Consumer() satelliteSummary: string = '卫星目录已就绪'
  @Consumer() observationSummary: string = '暗夜观测'
  @Consumer() darkStart: string = '—'
  @Consumer() darkEnd: string = '—'
  @Consumer() sunRise: string = '—'
  @Consumer() sunSet: string = '—'
  @Consumer() moonRise: string = '—'
  @Consumer() moonSet: string = '—'
  @Consumer() dataDate: string = ''
  @Consumer() dataStatus: string = '本地快照'
  @Consumer() updatedAt: string = '最近一次本地计算'
  @Local c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private compact(): boolean { return this.cardHeight < 220 }
  private tall(): boolean { return this.cardHeight >= 300 }
  private visualSize(): number {
    if (this.compact()) return 52
    if (this.cardWidth >= 520) return 126
    return 90
  }
  private accent(): string {
    if (this.kind === 'satellite') return AstroColors.cardSatelliteAccent
    if (this.kind === 'meteor') return AstroColors.cardMeteorAccent
    if (this.kind === 'moon') return AstroColors.cardMoonAccent
    return AstroColors.cardDefaultAccent
  }
  private surfaceStart(): string {
    if (this.kind === 'satellite') return AstroColors.cardSatelliteSurface
    if (this.kind === 'meteor') return AstroColors.cardMeteorSurface
    if (this.kind === 'moon') return AstroColors.cardMoonSurface
    return AstroColors.cardDefaultSurface
  }
  private heading(): string {
    if (this.kind === 'moon') return '月相与升落'
    if (this.kind === 'tonight') return '今晚天象'
    if (this.kind === 'satellite') return '卫星观测'
    if (this.kind === 'meteor') return '流星雨'
    if (this.kind === 'compact') return '今晚速览'
    return '观星手札'
  }
  private primaryValue(): string {
    if (this.kind === 'satellite') return this.satelliteSummary
    if (this.kind === 'meteor') return this.meteorSummary
    if (this.kind === 'tonight' || this.kind === 'compact') return this.observationSummary
    return this.moonPhase
  }
  private primaryCaption(): string {
    if (this.kind === 'satellite') return '本地 TLE 目录 · 按当前观测地计算'
    if (this.kind === 'meteor') return this.meteorRate + ' · 理论小时率'
    if (this.kind === 'tonight') return this.darkStart + ' – ' + this.darkEnd + ' · 天文暗夜'
    if (this.kind === 'compact') return this.moonPhase + ' · ' + this.moonSummary
    return this.moonSummary
  }
  private actionLabel(): string {
    if (this.kind === 'satellite') return '打开卫星观测'
    if (this.kind === 'meteor') return '打开流星雨'
    if (this.kind === 'compact') return '打开星图'
    if (this.kind === 'moon') return '查看月相详情'
    return '查看今晚天象'
  }
  private actionPanel(): string {
    if (this.kind === 'satellite') return 'satellites'
    if (this.kind === 'meteor') return 'meteors'
    return 'astro'
  }
  private moonMaskOffset(): number {
    const fraction = Math.max(0, Math.min(100, Number(this.moonIllumination))) / 100
    const radius = this.visualSize() * 0.40
    return (Number(this.moonAge) > 14.765 ? 1 : -1) * radius * 2 * fraction
  }

  private route(panel: string, tab: string = ''): void {
    postCardAction(this, { action: 'router', bundleName: 'com.joinother.skyinstrument',
      moduleName: 'entry', abilityName: 'QAbility', params: { panel: panel, tab: tab } })
  }

  @Builder
  private celestialVisual() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(this.visualSize())
        .height(this.visualSize())
        .fill(AstroColors.cardVisualBg)
        .stroke(this.accent())
        .strokeWidth(1.2)
      Circle()
        .width(this.visualSize() - 12)
        .height(this.visualSize() - 12)
        .fill(this.surfaceStart())
        .opacity(0.92)
      if (this.kind === 'satellite') {
        Ellipse()
          .width(this.visualSize() * 0.92)
          .height(this.visualSize() * 0.36)
          .fill(Color.Transparent)
          .stroke(AstroColors.cardSatelliteOrbit)
          .strokeWidth(1.2)
          .rotate({ angle: -24 })
        Ellipse()
          .width(this.visualSize() * 0.68)
          .height(this.visualSize() * 0.24)
          .fill(Color.Transparent)
          .stroke(this.accent())
          .strokeWidth(1)
          .rotate({ angle: -24 })
          .opacity(0.72)
        Circle()
          .width(this.visualSize() * 0.27)
          .height(this.visualSize() * 0.27)
          .fill(AstroColors.cardSatelliteBody)
          .stroke(AstroColors.cardSatelliteOrbit)
          .strokeWidth(1)
        Circle()
          .width(6)
          .height(6)
          .fill(AstroColors.starPoint)
          .offset({ x: this.visualSize() * 0.36, y: -this.visualSize() * 0.18 })
      } else if (this.kind === 'meteor') {
        Path()
          .commands('M 12 48 L 48 12 M 8 36 L 30 14 M 26 54 L 48 32')
          .width(this.visualSize() * 0.72)
          .height(this.visualSize() * 0.72)
          .fill(Color.Transparent)
          .stroke(AstroColors.cardMeteorTrail)
          .strokeWidth(1.7)
        Circle()
          .width(7)
          .height(7)
          .fill(AstroColors.starPoint)
          .offset({ x: this.visualSize() * 0.25, y: -this.visualSize() * 0.26 })
      } else if (this.kind === 'moon' || this.kind === 'overview' || this.kind === 'compact') {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(this.visualSize() * 0.80)
            .height(this.visualSize() * 0.80)
            .fill(AstroColors.cardMoonShadow)
          if (Number(this.moonIllumination) >= 0) {
            Circle()
              .width(this.visualSize() * 0.80)
              .height(this.visualSize() * 0.80)
              .fill(AstroColors.cardMoonLit)
            Circle()
              .width(this.visualSize() * 0.80)
              .height(this.visualSize() * 0.80)
              .fill(AstroColors.cardMoonShadow)
              .offset({ x: this.moonMaskOffset() })
          } else {
            Text('☾').fontSize(this.visualSize() * 0.56).fontColor(AstroColors.cardMoonGlyph)
          }
        }
        .width(this.visualSize() * 0.80)
        .height(this.visualSize() * 0.80)
        .borderRadius(this.visualSize() * 0.40)
        .clip(true)
        .border({ width: 1, color: AstroColors.cardMoonBorder })
      } else {
        Circle()
          .width(this.visualSize() * 0.58)
          .height(this.visualSize() * 0.58)
          .fill(AstroColors.cardPlanetFill)
          .stroke(AstroColors.cardPlanetStroke)
          .strokeWidth(1)
        Circle().width(5).height(5).fill(AstroColors.starPoint)
          .offset({ x: this.visualSize() * 0.25, y: -this.visualSize() * 0.18 })
      }
    }
    .width(this.visualSize())
    .height(this.visualSize())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private factGrid() {
    if (this.kind === 'moon') {
      Row({ space: 8 }) {
        AstronomyFact({ label: '月出', value: this.moonRise })
        AstronomyFact({ label: '月落', value: this.moonSet })
      }.width('100%')
    } else if (this.kind === 'tonight') {
      Row({ space: 8 }) {
        AstronomyFact({ label: '日落', value: this.sunSet })
        AstronomyFact({ label: '日出', value: this.sunRise })
      }.width('100%')
    } else if (this.kind === 'satellite') {
      Row({ space: 8 }) {
        AstronomyFact({ label: '目录', value: this.satelliteSummary })
        AstronomyFact({ label: '快照', value: this.dataDate.length > 0 ? this.dataDate : this.dataStatus })
      }.width('100%')
    } else if (this.kind === 'meteor') {
      Row({ space: 8 }) {
        AstronomyFact({ label: '理论小时率', value: this.meteorRate })
        AstronomyFact({ label: '月相', value: this.moonSummary })
      }.width('100%')
    } else if (this.kind === 'compact') {
      Row({ space: 8 }) {
        AstronomyFact({ label: '月相', value: this.moonSummary })
        AstronomyFact({ label: '可见行星', value: this.planetSummary })
      }.width('100%')
    } else {
      Row({ space: 8 }) {
        AstronomyFact({ label: '可见行星', value: this.planetSummary })
        AstronomyFact({ label: '活动流星雨', value: this.meteorSummary })
      }.width('100%')
    }
  }

  @Builder
  private largeContext() {
    if (this.tall() && !this.compact()) {
      if (this.kind === 'overview' || this.kind === 'tonight') {
        Text(this.planetNames)
          .fontSize(11)
          .fontColor(this.c.sub)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      } else if (this.kind === 'meteor') {
        Text('可见程度还取决于辐射点高度、月光、光污染与天气。')
          .fontSize(11)
          .fontColor(this.c.sub)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      } else if (this.kind === 'moon') {
        Text('月相、月出和月落均按当前观测地计算。')
          .fontSize(11)
          .fontColor(this.c.sub)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      } else if (this.kind === 'satellite') {
        Stack({ alignContent: Alignment.Center }) {
          Ellipse()
            .width('92%')
            .height(142)
            .fill(Color.Transparent)
            .stroke(AstroColors.cardSatelliteOrbitSoft)
            .strokeWidth(1)
            .rotate({ angle: -12 })
          Ellipse()
            .width('70%')
            .height(100)
            .fill(Color.Transparent)
            .stroke(AstroColors.cardSatelliteOrbitStrong)
            .strokeWidth(1)
            .rotate({ angle: -12 })
          Column({ space: 4 }) {
            Text('本地轨道目录')
              .fontSize(12)
              .fontColor(AstroColors.cardSatelliteOrbit)
            Text(this.dataStatus + (this.dataDate.length > 0 ? ' · ' + this.dataDate : ''))
              .fontSize(11)
              .fontColor(this.c.sub)
          }
        }
        .width('100%')
        .height(142)
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 138, colors: [[this.surfaceStart(), 0], [AstroColors.cardGradientMid, 0.56], [AstroColors.cardGradientEnd, 1]] })
      Column({ space: this.compact() ? 7 : this.tall() ? 15 : 10 }) {
        Row({ space: 9 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle().width(24).height(24).fill(this.c.input).stroke(this.accent()).strokeWidth(1)
            Circle().width(6).height(6).fill(this.accent())
          }.width(24).height(24)
          Text(this.heading())
            .fontSize(this.compact() ? 14 : 16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.textStrong)
            .layoutWeight(1)
            .maxLines(1)
          Text(this.dataStatus)
            .fontSize(9)
            .fontColor(this.c.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%')

        Row({ space: this.compact() ? 10 : 16 }) {
          this.celestialVisual()
          Column({ space: 4 }) {
            Text(this.primaryValue())
              .fontSize(this.compact() ? 18 : this.tall() ? 27 : 21)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.textStrong)
              .maxLines(this.tall() ? 2 : 1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.primaryCaption())
              .fontSize(this.compact() ? 10 : 11)
              .fontColor(this.c.sub)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }.width('100%')

        this.factGrid()
        this.largeContext()

        if (!this.compact()) {
          Row({ space: 8 }) {
            Text(this.actionLabel() + '  →')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accent())
              .layoutWeight(1)
            Text(this.updatedAt)
              .fontSize(9)
              .fontColor(this.c.tertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.End)
          }.width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.compact() ? 13 : this.tall() ? 20 : 15)
    }
    .width('100%')
    .height('100%')
    .borderRadius(24)
    .clip(true)
    .border({ width: 1, color: this.c.border })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => { this.route(this.actionPanel(), this.kind === 'satellite' ? '' : this.kind === 'moon' ? '9' : this.kind === 'tonight' ? '8' : '5') })
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      this.cardWidth = Number(newSize.width)
      this.cardHeight = Number(newSize.height)
    })
  }
}
