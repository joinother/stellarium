import {
  computeGoldenHourClock,
  computePreviewPhaseForDay,
  computeSolarArcProgress,
  focusTargetForCard,
  formatPreviewDayCaptionZh,
  lunarNextMilestoneZh,
  offsetDaysToJd,
  routePlanetForCard
} from './AstronomyCardData'
import {
  CelestialOrbView,
  HorizonArcView,
  MiniPhaseStripView,
  StarfieldLayer
} from './WidgetVisuals'
import { WIDGET_RADIUS_CHIP, WIDGET_RADIUS_PILL } from './WidgetTokens'

const companionArcStorage: LocalStorage = new LocalStorage()

@Entry(companionArcStorage)
@Component
struct CompanionArcCard {
  @LocalStorageProp('observerPlanet') observerPlanet: string = 'Earth'
  @LocalStorageProp('observerPlanetName') observerPlanetName: string = '地球'
  @LocalStorageProp('companionName') companionName: string = '月球'
  @LocalStorageProp('companionEnglish') companionEnglish: string = 'Moon'
  @LocalStorageProp('companionRole') companionRole: string = 'moon'
  @LocalStorageProp('orbBody') orbBody: string = 'moon'
  @LocalStorageProp('moonPhase') moonPhase: string = '今夜月相'
  @LocalStorageProp('moonIllumination') moonIllumination: string = '72'
  @LocalStorageProp('moonAge') moonAge: string = '10'
  @LocalStorageProp('moonSummary') moonSummary: string = '72% 照明'
  @LocalStorageProp('moonRise') moonRise: string = '—'
  @LocalStorageProp('moonSet') moonSet: string = '—'
  @LocalStorageProp('sunRise') sunRise: string = '—'
  @LocalStorageProp('sunTransit') sunTransit: string = '—'
  @LocalStorageProp('sunSet') sunSet: string = '—'
  @LocalStorageProp('sunAlt') sunAlt: string = '-18.0'
  @LocalStorageProp('darkStart') darkStart: string = '—'
  @LocalStorageProp('goldenHourText') goldenHourText: string = '—'
  @LocalStorageProp('companionAlt') companionAlt: string = '28.0'
  @LocalStorageProp('skyHexHorizon') skyHexHorizon: string = '#142442'
  @LocalStorageProp('dataStatus') dataStatus: string = '本地快照'
  @LocalStorageProp('cardThemeStyle') cardThemeStyle: string = 'sky'
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'

  @State cardWidth: number = 160
  @State cardHeight: number = 160
  @State selectedDayOffset: number = 0

  private isWide(): boolean { return this.cardWidth >= 230 }

  private baseIllum(): number {
    const v = Number(this.moonIllumination)
    return Number.isFinite(v) ? v : -1
  }

  private baseAge(): number {
    const v = Number(this.moonAge)
    return Number.isFinite(v) ? v : 10
  }

  private displayIllum(): number {
    if (this.selectedDayOffset === 0) return this.baseIllum()
    const preview = computePreviewPhaseForDay(this.baseAge(), this.selectedDayOffset, this.observerPlanet === 'Moon')
    return preview.illumination
  }

  private displayAge(): number {
    if (this.selectedDayOffset === 0) return this.baseAge()
    const preview = computePreviewPhaseForDay(this.baseAge(), this.selectedDayOffset, this.observerPlanet === 'Moon')
    return preview.age
  }

  private displayPhaseName(): string {
    if (this.selectedDayOffset === 0) return this.moonPhase
    const preview = computePreviewPhaseForDay(this.baseAge(), this.selectedDayOffset, this.observerPlanet === 'Moon')
    return preview.phaseName
  }

  private numericAlt(): number {
    const v = Number(this.companionAlt)
    return Number.isFinite(v) ? v : 28
  }

  private isSunMode(): boolean {
    return this.orbBody.trim().toLowerCase() === 'sun'
  }

  private accentColor(): string {
    const body = this.orbBody.trim().toLowerCase()
    if (body === 'sun') return '#FFD166'
    if (body === 'earth') return '#74BFFF'
    if (body === 'saturn' || body === 'titan') return '#F6CE88'
    if (body === 'mars') return '#F09B6B'
    return '#C8DCFF'
  }

  private arcProgressOverride(): number {
    if (!this.isSunMode()) return -1
    const alt = Number(this.sunAlt)
    return computeSolarArcProgress(this.sunRise, this.sunSet, Date.now(), Number.isFinite(alt) ? alt : 0)
  }

  private rightStatLabel(): string {
    if (this.isSunMode()) {
      const alt = Math.round(this.numericAlt())
      return (alt >= 0 ? '+' : '') + String(alt) + '°'
    }
    return this.displayIllum() >= 0 ? (String(Math.round(this.displayIllum())) + '%') : '—'
  }

  private bottomTint(): string {
    if (this.cardThemeStyle === 'deep') return '#0B1224'
    return /^#[0-9A-Fa-f]{6}$/.test(this.skyHexHorizon) ? this.skyHexHorizon : '#12203B'
  }

  private showPhaseShadow(): boolean {
    const body = this.orbBody.trim().toLowerCase()
    return body === 'moon' || body === 'earth'
  }

  private worldSwitcherLabel(): string {
    if (this.isSunMode()) return '☀ 太阳 · 日轨 ↻'
    if (this.observerPlanet === 'Earth') return '月球 · 月相 ↻'
    if (this.observerPlanet === 'Moon') return '月球 · 地相 ↻'
    return this.observerPlanetName + ' · ' + this.companionName + ' ↻'
  }

  private milestoneCaption(): string {
    if (this.isSunMode()) return '今日太阳轨迹'
    if (this.showPhaseShadow()) {
      return lunarNextMilestoneZh(this.displayAge(), this.observerPlanet === 'Moon')
    }
    if (this.companionRole === 'parent-planet' || this.companionRole === 'host') {
      return '宿主 · ' + this.companionName
    }
    return this.displayPhaseName()
  }

  private previewHeaderHint(): string {
    const noun = this.observerPlanet === 'Moon' ? '地相' : '月相'
    if (this.selectedDayOffset === 0) {
      return '未来 5 日' + noun + '预览 · 点日期查看'
    }
    return formatPreviewDayCaptionZh(this.selectedDayOffset, Date.now()) + ' · 点回今日'
  }

  private openDetail(): void {
    const focusTarget = focusTargetForCard(this.observerPlanet, this.companionEnglish, this.orbBody)
    const previewJd = this.isSunMode() ? 0 : offsetDaysToJd(Date.now(), this.selectedDayOffset)
    const landingTitle = this.selectedDayOffset > 0 && !this.isSunMode()
      ? (this.companionName + ' · +' + String(this.selectedDayOffset) + '日 ' + this.displayPhaseName())
      : (this.isSunMode()
        ? ('太阳 · ' + this.displayPhaseName() + ' ' + this.rightStatLabel())
        : (this.companionName + ' · ' + this.displayPhaseName()))
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'sky',
        observerPlanet: routePlanetForCard(this.observerPlanet),
        target: focusTarget,
        jd: previewJd,
        landingTitle: landingTitle,
        landingSource: 'card'
      }
    })
  }

  private cyclePlanet(): void {
    this.selectedDayOffset = 0
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'cyclePlanet',
        formName: 'companion_arc_card',
        currentPlanet: this.observerPlanet
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

  private selectPreviewDay(dayIdx: number): void {
    animateTo({ duration: 380, curve: Curve.FastOutSlowIn }, () => {
      this.selectedDayOffset = dayIdx
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      if (!this.isWide()) {
        // 2x2 Compact Celestial Arc Instrument
        Column() {
          Row() {
            Text((this.observerPlanet === 'Earth'
              ? '月球 ↻'
              : (this.isSunMode() ? '☀ 太阳 ↻' : (this.observerPlanetName + '·' + this.companionName + ' ↻'))))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EBF4FF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .height(28)
              .padding({ left: 9, right: 10 })
              .backgroundColor('#2CFFFFFF')
              .borderRadius(WIDGET_RADIUS_PILL)
              .onClick(() => this.cyclePlanet())
            Blank()
            Text(this.rightStatLabel())
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentColor())
          }
          .width('100%')

          Column({ space: 2 }) {
            CelestialOrbView({
              orbBody: this.orbBody,
              orbSize: 64,
              showPhase: this.showPhaseShadow(),
              illumination: this.displayIllum(),
              phaseAge: this.displayAge()
            })
            Text(this.displayPhaseName())
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
            riseText: this.isSunMode() ? this.sunRise : this.moonRise,
            setText: this.isSunMode() ? this.sunSet : this.moonSet,
            customProgress: this.arcProgressOverride(),
            accentColor: this.accentColor()
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 9 })
      } else {
        // 2x4 Wide Lunar/Companion Phase Card: crystal-clear hierarchy & interactive 5-day phase preview
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            CelestialOrbView({
              orbBody: this.orbBody,
              orbSize: 84,
              showPhase: this.showPhaseShadow(),
              illumination: this.displayIllum(),
              phaseAge: this.displayAge()
            })
            Text(this.milestoneCaption())
              .fontSize(10.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.selectedDayOffset > 0 ? '#FFE09A' : '#CFE6FF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width(96)
          .height('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Column({ space: 4 }) {
            // Top bar: clear world switcher + current/preview phase title + crisp percentage
            Row({ space: 6 }) {
              Column({ space: 2 }) {
                Text(this.worldSwitcherLabel())
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#E4F1FF')
                  .height(28)
                  .padding({ left: 10, right: 10 })
                  .backgroundColor('#2CFFFFFF')
                  .borderRadius(WIDGET_RADIUS_PILL)
                  .maxLines(1)
                  .onClick(() => this.cyclePlanet())
                Text(this.displayPhaseName())
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column({ space: 1 }) {
                Text(this.rightStatLabel())
                  .fontSize(19)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.accentColor())
                if (this.showPhaseShadow()) {
                  Text(this.selectedDayOffset > 0 ? ('+' + String(this.selectedDayOffset) + '日') : '照明度')
                    .fontSize(9.5)
                    .fontColor(this.selectedDayOffset > 0 ? '#FFE09A' : '#8FB6DC')
                }
              }
              .alignItems(HorizontalAlign.End)
            }
            .width('100%')

            // Middle: live horizon arc on Today, or clear future-day preview banner when scrubbing
            if (this.showPhaseShadow() && this.selectedDayOffset > 0) {
              Row({ space: 6 }) {
                Text('月龄 ' + this.displayAge().toFixed(1) + ' 天 · 轻触直飞当日星图 ↗')
                  .fontSize(10.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFE5A8')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .height(32)
              .padding({ left: 10, right: 10 })
              .backgroundColor('#2E221604')
              .borderRadius(WIDGET_RADIUS_CHIP)
              .border({ width: 0.6, color: '#44FFE09A' })
              .alignItems(VerticalAlign.Center)
            } else {
              HorizonArcView({
                arcWidth: 176,
                arcHeight: 28,
                altitudeDeg: this.numericAlt(),
                riseText: this.isSunMode() ? this.sunRise : this.moonRise,
                midFooterText: this.isSunMode() && this.sunTransit !== '—' ? ('中天 ' + this.sunTransit) : '',
                setText: this.isSunMode() ? this.sunSet : this.moonSet,
                customProgress: this.arcProgressOverride(),
                accentColor: this.accentColor()
              })
            }

            // Bottom: 5-day phase preview (ONLY for real phase worlds: Moon/Earth) or 4-milestone bar for Sun/Planets
            if (this.showPhaseShadow()) {
              Column({ space: 3 }) {
                Row() {
                  Text(this.previewHeaderHint())
                    .fontSize(9.5)
                    .fontWeight(this.selectedDayOffset > 0 ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.selectedDayOffset > 0 ? '#FFE09A' : '#96BBE0')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .onClick(() => {
                  if (this.selectedDayOffset > 0) this.selectPreviewDay(0)
                })

                MiniPhaseStripView({
                  phaseAge: this.baseAge(),
                  nowMs: Date.now(),
                  selectedIndex: this.selectedDayOffset,
                  onSelectDay: (idx: number) => this.selectPreviewDay(idx)
                })
              }
              .width('100%')
            } else {
              Row({ space: 5 }) {
                ForEach(this.isSunMode() ? [
                  ['日出', this.sunRise],
                  ['中天', this.sunTransit],
                  ['黄金', this.goldenHourText !== '—' ? this.goldenHourText : computeGoldenHourClock(this.sunSet)],
                  ['暗夜', this.darkStart]
                ] : [
                  ['升起', this.moonRise],
                  ['落下', this.moonSet],
                  ['仰角', (Math.round(this.numericAlt()) >= 0 ? '+' : '') + String(Math.round(this.numericAlt())) + '°'],
                  ['暗夜', this.darkStart]
                ], (pair: string[], idx: number) => {
                  Column({ space: 2 }) {
                    Text(pair[0]).fontSize(9.5).fontWeight(FontWeight.Medium).fontColor('#CFE2F8').maxLines(1)
                    Text(pair[1]).fontSize(10.5).fontWeight(FontWeight.Medium).fontColor('#FFE09A').maxLines(1)
                  }
                  .layoutWeight(1)
                  .height(40)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor('#32090F1E')
                  .borderRadius(WIDGET_RADIUS_CHIP)
                  .border({ width: 0.5, color: '#2AFFE09A' })
                }, (pair: string[], idx: number) => pair[0] + '_' + String(idx))
              }
              .width('100%')
            }
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 13, right: 14, top: 10, bottom: 9 })
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
