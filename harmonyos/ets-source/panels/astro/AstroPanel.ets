// 天文计算面板。
//
// 状态：astro 域数据在 AstroStore（@ObjectLink）；objectDetailStore / wutStore 亦 @ObjectLink；
// 夜视三色由宿主算好以 @Prop 传入；天文面板 Scroller 由宿主以普通成员传入（宿主仍需它做滚动复位与状态上报）。
// 宿主私有动作（加载器 load*、跳转 jumpTo*、目标选择器 open*Picker、导出、状态上报、以及占位的纯
// 标签/几何助手）全部通过注入的 AstroPanelHost 回调驱动，避免把桥接依赖搬进组件。
// 本文件不含 @BuilderParam，不含参数化 @Builder。

import { TonightPlanet, TonightShower, WutTarget, EphemerisRow, RtsCalendarDay, AltAzPoint, AnnualElevationPoint, ObservabilityDay, LunarElongationPoint, PlanetTimeSeriesPoint, PlanetPairDistancePoint, PlanetCalcItem, PhenomenonItem, EclipseItem, PlanetaryTransitItem, MoonPhaseItem, SeasonEvent, TabItem, PlanetPosition, HeliocentricPosition, CelestialPosition } from '../../pages/StellariumTypes'
import { HELIOCENTRIC_PLANET_ORBITS, CELESTIAL_POSITION_CATEGORIES, PHENOMENA_START_OPTIONS, HeliocentricOrbit, CelestialPositionCategory, PhenomenaStartOption } from '../../pages/MainWindowModels'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL, UI_OPTION_ANIMATION_MS } from '../../common/ui/UiTokens'
import { uiFadeUpTransition } from '../../common/ui/UiMotion'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { uiChipPaddingV, uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { AstroStore } from '../../state/AstroStore'
import { WutStore } from '../../state/WutStore'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { SessionToolStore } from '../../state/SessionToolStore'
import { ContinuationSection } from './ContinuationSection'
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme, AstroColors } from '../../state/StellariumTheme'
import { InfoRow } from '../../common/ui/InfoRow'
import { AstroSelectionGuide, PhenomenonRelationMark } from './AstroGuides'
import { RtsSelectionGuide, GraphSelectionGuide } from './GraphGuides'
import { GraphLoadingRow } from '../../common/ui/GraphLoadingRow'
import { WutTargetCard } from './WutTargetCard'
import { SolarSystemOrreryView } from './SolarSystemOrreryView'
import { SolarPathDiagramView } from './SolarPathDiagramView'
import { TargetTransitArcView } from './TargetTransitArcView'
import { getIcon } from '../../common/ui/ShellIcons'
import { astroGroupItems, astroTabItemsForGroup, rtsCalendarDurationLabel, graphStartOptionLabel, planetMetricLabel, planetMetricUnit, planetPairBodyName, planetPairLinearLabel, hecPointSize, hecDistanceLabel, lunarElongationBarHeight, planetTimeSeriesBarHeight, planetPairBarHeight, phenomenonCaption } from '../../common/derive/astro'
import { planetZh, zhNameOf, zhType } from '../../common/derive/labels'
import { azBarHeight } from '../../common/derive/geometry'
import { wutCategoryOptions, wutCategoryKey, wutDirectionLabel } from '../../common/derive/catalog'

export interface AstroPanelHost {
  almanacHoursLabel: (key: string) => string
  altAzMaxLabel: () => string
  altAzMidpointLabel: () => string
  altAzNowLabel: () => string
  altAzRangeLabel: () => string
  altAzVisibleHours: () => string
  altBarHeight: (alt: number | undefined) => number
  altBarWidth: () => number
  altCurveSegmentWidth: () => number
  altitudeCurveColor: (altitude: number | undefined, color: ResourceColor) => ResourceColor
  annualBarHeight: (altitude: number | undefined) => number
  annualBarWidth: () => number
  annualMaxLabel: () => string
  astroNeedsSelectedObject: () => boolean
  azimuthNowLabel: () => string
  callNative: (name: string, payload?: string) => void
  celestialPositionSubtitle: (position: CelestialPosition) => string
  celestialPositionTitle: (position: CelestialPosition) => string
  chooseEclipseStartDate: () => void
  chooseEphemerisStartDate: () => void
  chooseGraphStartDate: () => void
  chooseRtsCalendarStartDate: () => void
  eclipseStartOptionLabel: (offsetDays: number) => string
  ephemerisStartOptionLabel: (offsetDays: number) => string
  exportCurrentAstroCsv: () => Promise<void>
  filteredEclipses: () => Array<EclipseItem>
  fmtClock: (s: string | undefined) => string
  fmtDateTime: (s: string | undefined) => string
  fmtEphemerisDate: (s: string | undefined) => string
  fmtNum: (v: number | undefined, digits: number, suffix: string) => string
  graphCustomStartLabel: () => string
  graphTargetLabel: () => string
  hasSelectedObject: () => boolean
  hecPointColor: (position: HeliocentricPosition) => string
  hecPointLeft: (position: HeliocentricPosition) => number
  hecPointTop: (position: HeliocentricPosition) => number
  hecTitle: (position: HeliocentricPosition) => string
  jdToDateStr: (jd: string) => string
  jumpToAlmanacSeason: (event: SeasonEvent) => void
  jumpToEphemerisRow: (row: EphemerisRow) => void
  jumpToJdSmooth: (jd: number, label: string) => void
  jumpToMoonPhase: (item: MoonPhaseItem) => void
  jumpToObservabilityDay: (day: ObservabilityDay) => void
  jumpToPhenomenon: (item: PhenomenonItem) => void
  jumpToRts: (key: string) => void
  jumpToRtsCalendar: (day: RtsCalendarDay) => void
  jumpToWutTarget: (target: WutTarget) => void
  loadAlmanac: () => void
  loadAltAzCurve: () => void
  loadAnnualElevation: () => void
  loadCelestialPositions: () => void
  loadEclipses: () => void
  loadEphemeris: () => void
  loadHeliocentricPositions: () => void
  loadLunarElongation: () => void
  loadMoonPhases: () => void
  loadObservabilityCalendar: () => void
  loadPhenomena: () => void
  loadPlanetCalc: () => void
  loadPlanetPairDistance: () => void
  loadPlanetPositions: () => void
  loadPlanetTimeSeries: () => void
  loadPlanetaryTransits: () => void
  loadRTS: () => void
  loadRtsCalendar: () => void
  loadTonightAstro: () => void
  loadWutTargets: () => void
  lunarElongationBarWidth: () => number
  lunarElongationClosestLabel: () => string
  lunarElongationLineTop: () => number
  lunarElongationNowLabel: () => string
  markRtsCalendarForRegeneration: () => void
  onScrollY: (offsetY: number) => void
  openAstroTargetPicker: () => void
  openEphemerisTargetPicker: () => void
  openGraphTargetPicker: () => void
  openRtsTargetPicker: () => void
  phenomenaBodyName: (body: string) => string
  planetPairBarWidth: () => number
  planetPairCurrentIndex: () => number
  planetPairSegmentWidth: () => number
  planetTimeSeriesBarWidth: () => number
  planetTimeSeriesSegmentWidth: () => number
  planetTimeSeriesValueLabel: (value: number | undefined, metric: string) => string
  publishAstroPanelState: () => void
  reloadCurrentGraph: () => void
  reloadEclipses: () => void
  rtsCalendarStartOptionLabel: (offsetDays: number) => string
  searchObject: (name: string, catalogModuleId?: string, exactSelectionPayload?: string, placement?: string) => void
  // Session continuation lives in the tonight tab, not the location panel.
  sessionExport: () => void
  sessionApply: () => void
  sessionHandoff: () => void
  selectAstroFilter: (key: string, value: string) => void
  selectAstroGroup: (group: number) => void
  selectAstroTab: (tab: number) => void
  switchObserverPlanet: (planetEn: string) => void
  openCalendarsPanel: () => void
  wutCategoryTitle: () => string
  wutTargetSubtitle: (target: WutTarget) => string
  wutTargetTitle: (target: WutTarget) => string
}

function noopAstroPanelHost(): AstroPanelHost {
  return {
    almanacHoursLabel: () => '',
    altAzMaxLabel: () => '',
    altAzMidpointLabel: () => '',
    altAzNowLabel: () => '',
    altAzRangeLabel: () => '',
    altAzVisibleHours: () => '',
    altBarHeight: () => 0,
    altBarWidth: () => 0,
    altCurveSegmentWidth: () => 0,
    altitudeCurveColor: () => '',
    annualBarHeight: () => 0,
    annualBarWidth: () => 0,
    annualMaxLabel: () => '',
    astroNeedsSelectedObject: () => false,
    azimuthNowLabel: () => '',
    callNative: () => {},
    celestialPositionSubtitle: () => '',
    celestialPositionTitle: () => '',
    chooseEclipseStartDate: () => {},
    chooseEphemerisStartDate: () => {},
    chooseGraphStartDate: () => {},
    chooseRtsCalendarStartDate: () => {},
    eclipseStartOptionLabel: () => '',
    ephemerisStartOptionLabel: () => '',
    exportCurrentAstroCsv: () => Promise.resolve(),
    filteredEclipses: () => [],
    fmtClock: () => '',
    fmtDateTime: () => '',
    fmtEphemerisDate: () => '',
    fmtNum: () => '',
    graphCustomStartLabel: () => '',
    graphTargetLabel: () => '',
    hasSelectedObject: () => false,
    hecPointColor: () => '',
    hecPointLeft: () => 0,
    hecPointTop: () => 0,
    hecTitle: () => '',
    jdToDateStr: () => '',
    jumpToAlmanacSeason: () => {},
    jumpToEphemerisRow: () => {},
    jumpToJdSmooth: () => {},
    jumpToMoonPhase: () => {},
    jumpToObservabilityDay: () => {},
    jumpToPhenomenon: () => {},
    jumpToRts: () => {},
    jumpToRtsCalendar: () => {},
    jumpToWutTarget: () => {},
    loadAlmanac: () => {},
    loadAltAzCurve: () => {},
    loadAnnualElevation: () => {},
    loadCelestialPositions: () => {},
    loadEclipses: () => {},
    loadEphemeris: () => {},
    loadHeliocentricPositions: () => {},
    loadLunarElongation: () => {},
    loadMoonPhases: () => {},
    loadObservabilityCalendar: () => {},
    loadPhenomena: () => {},
    loadPlanetCalc: () => {},
    loadPlanetPairDistance: () => {},
    loadPlanetPositions: () => {},
    loadPlanetTimeSeries: () => {},
    loadPlanetaryTransits: () => {},
    loadRTS: () => {},
    loadRtsCalendar: () => {},
    loadTonightAstro: () => {},
    loadWutTargets: () => {},
    lunarElongationBarWidth: () => 0,
    lunarElongationClosestLabel: () => '',
    lunarElongationLineTop: () => 0,
    lunarElongationNowLabel: () => '',
    markRtsCalendarForRegeneration: () => {},
    onScrollY: () => {},
    openAstroTargetPicker: () => {},
    openEphemerisTargetPicker: () => {},
    openGraphTargetPicker: () => {},
    openRtsTargetPicker: () => {},
    phenomenaBodyName: () => '',
    planetPairBarWidth: () => 0,
    planetPairCurrentIndex: () => 0,
    planetPairSegmentWidth: () => 0,
    planetTimeSeriesBarWidth: () => 0,
    planetTimeSeriesSegmentWidth: () => 0,
    planetTimeSeriesValueLabel: () => '',
    publishAstroPanelState: () => {},
    reloadCurrentGraph: () => {},
    reloadEclipses: () => {},
    rtsCalendarStartOptionLabel: () => '',
    searchObject: () => {},
    sessionExport: () => {},
    sessionApply: () => {},
    sessionHandoff: () => {},
    selectAstroFilter: () => {},
    selectAstroGroup: () => {},
    selectAstroTab: () => {},
    switchObserverPlanet: () => {},
    openCalendarsPanel: () => {},
    wutCategoryTitle: () => '',
    wutTargetSubtitle: () => '',
    wutTargetTitle: () => ''
  }
}

@Component
export struct AstroPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink store: AstroStore
  @ObjectLink wutStore: WutStore
  @ObjectLink objectDetailStore: ObjectDetailStore
  @ObjectLink sessionToolStore: SessionToolStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private contextExpanded: boolean = false
  @State private planetSwitcherExpanded: boolean = false
  scroller: Scroller = new Scroller()
  host: AstroPanelHost = noopAstroPanelHost()

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private fs(base: number): number {
    return uiFontSize(base, this.readableUi, this.uiFontScale)
  }

  private ch(base: number): number {
    return uiControlHeight(base, this.readableUi, this.controlScale)
  }

  private pv(base: number): number {
    return uiChipPaddingV(base, this.controlScale)
  }

  private quickObserverPlanets(): string[] {
    return ['Earth', 'Moon', 'Mars', 'Mercury', 'Venus', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto']
  }

  private phenomenaBodyChoices(): string[] {
    const obs = (this.store.observerPlanet || 'Earth').toLowerCase()
    const all: string[] = ['all', 'Sun', 'Moon', 'Mercury', 'Venus', 'Earth', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto']
    return all.filter((b: string) => b === 'all' || b.toLowerCase() !== obs)
  }

  private eclipseRowTitle(e: EclipseItem): string {
    if (e.occulter !== undefined && e.occulter.length > 0) {
      return e.kind === 'solar'
        ? (e.occulter + '日' + (e.type ?? '食'))
        : (e.occulter + '卫' + (e.type ?? '食'))
    }
    return ((e.kind === 'solar') ? '日' : '月') + (e.type ?? '')
  }

  private eclipseRowAccentLabel(e: EclipseItem): string {
    if (e.occulter !== undefined && e.occulter.length > 0) {
      return e.kind === 'solar' ? '遮日' : '卫食'
    }
    return e.kind === 'solar' ? '日食' : '月食'
  }

  build() {
    Column({ space: 0 }) {
        // 一级分组：三等宽鸿蒙分段控件（观测 / 位置与数据 / 事件与历法）
        Row({ space: 4 }) {
          ForEach(astroGroupItems(), (tab: TabItem) => {
            Row() {
              Text(tab.label)
                .fontSize(this.fs(12))
                .maxFontScale(1.25)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(this.store.astroGroup === tab.id ? this.c.onAccent : this.c.sub)
                .fontWeight(this.store.astroGroup === tab.id ? FontWeight.Medium : FontWeight.Normal)
            }
              .layoutWeight(1)
              .constraintSize({ minHeight: this.ch(32) })
              .padding({ left: 6, right: 6, top: this.pv(5), bottom: this.pv(5) })
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .backgroundColor(this.store.astroGroup === tab.id ? this.c.accent : Color.Transparent)
              .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
              .borderRadius(UI_RADIUS_CONTROL - 3)
              .id('astro-group-' + tab.id.toString())
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
              .onClick(() => { this.host.selectAstroGroup(tab.id) })
          }, (tab: TabItem) => tab.id.toString())
        }
          .width('100%')
          .padding(3)
          .backgroundColor(this.c.soft)
          .borderRadius(UI_RADIUS_CONTROL)
          .margin({ top: 2, bottom: 6 })

        // 二级子页签：等高胶囊条，自动适配字体缩放
        Scroll() {
          Row({ space: 6 }) {
            ForEach(astroTabItemsForGroup(this.store.astroGroup), (tab: TabItem) => {
              Row() {
                Text(tab.label)
                  .fontSize(this.fs(11))
                  .maxFontScale(1.25)
                  .maxLines(1)
                  .fontColor(this.store.astroTab === tab.id ? this.c.textStrong : this.c.sub)
                  .fontWeight(this.store.astroTab === tab.id ? FontWeight.Medium : FontWeight.Normal)
              }
                .constraintSize({ minHeight: this.ch(30), minWidth: 54 })
                .padding({ left: 12, right: 12, top: this.pv(5), bottom: this.pv(5) })
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .backgroundColor(this.store.astroTab === tab.id ? this.c.softStrong : this.c.soft)
                .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                .border({ width: { bottom: 2 }, color: this.store.astroTab === tab.id ? this.c.accent : Color.Transparent })
                .borderRadius(UI_RADIUS_CONTROL)
                .id('astro-tab-' + tab.id.toString())
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.selectAstroTab(tab.id) })
            }, (tab: TabItem) => tab.id.toString())
          }.padding({ left: 2, right: 2 })
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .margin({ bottom: 8 })

        // 紧凑可折叠观测上下文栏 + 顶栏一键切换星体观测点 + 内联导出 CSV
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            // 观测星体快切胶囊（无需离开天文计算即可直切 地球 / 月球 / 火星 / 木星 / 土星 等）
            Row({ space: 4 }) {
              Text(this.store.planetSwitching ? '切换中…' : (this.store.observerPlanetZh + (this.planetSwitcherExpanded ? ' ▴' : ' ▾')))
                .fontSize(this.fs(11))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.store.isEarthObserver() ? this.c.accent : this.c.onAccent)
                .maxLines(1)
            }
              .id('astro-planet-switcher')
              .constraintSize({ minHeight: this.ch(30) })
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(this.store.isEarthObserver() ? this.c.softStrong : this.c.accent)
              .border({ width: 0.6, color: this.c.accent })
              .borderRadius(UI_RADIUS_PILL)
              .alignItems(VerticalAlign.Center)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
              .onClick(() => {
                this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
                  this.planetSwitcherExpanded = !this.planetSwitcherExpanded
                })
              })

            Row({ space: 5 }) {
              Text(this.store.astroContext !== undefined
                ? ((this.store.astroContext.observerLocation !== undefined && this.store.astroContext.observerLocation.length > 0 ? this.store.astroContext.observerLocation : this.store.observerPlanetZh)
                  + ' · ' + this.host.fmtClock(this.store.astroContext.localTime)
                  + ' · ☉ ' + this.host.fmtNum(this.store.astroContext.sunAltitude, 0, '°'))
                : '离线天文计算')
                .fontSize(this.fs(11))
                .fontColor(this.c.text)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.contextExpanded ? '收起 ▴' : '详情 ▾')
                .fontSize(this.fs(10))
                .fontColor(this.c.accent)
                .maxLines(1)
            }
              .layoutWeight(1)
              .constraintSize({ minHeight: this.ch(30) })
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
                  this.contextExpanded = !this.contextExpanded
                })
              })

            Button(this.store.astroExporting ? '保存中…' : '导出')
              .fontSize(this.fs(10.5))
              .maxFontScale(1.2)
              .fontColor(this.c.text)
              .backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_PILL)
              .constraintSize({ minHeight: this.ch(30) })
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .enabled(!this.store.astroExporting)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
              .onClick(() => { this.host.exportCurrentAstroCsv() })
          }
            .width('100%')
            .alignItems(VerticalAlign.Center)

          if (this.planetSwitcherExpanded) {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Text('切换观测星体（自动按目标星体视角重算星食、凌日、天象与年历）')
                  .fontSize(this.fs(10))
                  .fontColor(this.c.sub)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }.width('100%')
              Scroll() {
                Row({ space: 6 }) {
                  ForEach(this.quickObserverPlanets(), (pEn: string) => {
                    Text(planetZh(pEn))
                      .id('astro-planet-' + pEn)
                      .fontSize(this.fs(11.5))
                      .fontWeight(this.store.observerPlanet.toLowerCase() === pEn.toLowerCase() ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(this.store.observerPlanet.toLowerCase() === pEn.toLowerCase() ? this.c.onAccent : this.c.text)
                      .padding({ left: 11, right: 11, top: this.pv(6), bottom: this.pv(6) })
                      .backgroundColor(this.store.observerPlanet.toLowerCase() === pEn.toLowerCase() ? this.c.accent : this.c.bg)
                      .border({ width: 0.5, color: this.store.observerPlanet.toLowerCase() === pEn.toLowerCase() ? this.c.accent : this.c.border })
                      .borderRadius(UI_RADIUS_PILL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
                      .onClick(() => {
                        this.host.switchObserverPlanet(pEn)
                        this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
                          this.planetSwitcherExpanded = false
                        })
                      })
                  }, (pEn: string) => pEn)
                }.padding({ left: 1, right: 2 })
              }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            }
              .width('100%')
              .padding({ top: 4, bottom: 2 })
              .transition(uiFadeUpTransition())
          }

          if (this.contextExpanded && this.store.astroContext !== undefined) {
            Column({ space: 3 }) {
              Row()
                .width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 2, bottom: 2 })
              Row({ space: 6 }) {
                Text('时间 ' + this.host.fmtDateTime(this.store.astroContext.localTime) + ' · 时区 ' + (this.store.astroContext.timeZone ?? '--'))
                  .fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.store.astroContext.offline === true ? '离线计算' : '本地计算').fontSize(this.fs(10)).fontColor(this.c.accent)
              }.width('100%')
              Text('平恒星时 ' + (this.store.astroContext.meanSiderealTime ?? '--') + ' · 视恒星时 ' + (this.store.astroContext.apparentSiderealTime ?? '--') + ' · 时间方程 ' + this.host.fmtNum(this.store.astroContext.equationOfTimeMinutes, 2, ' 分钟'))
                .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('太阳 ' + this.host.fmtNum(this.store.astroContext.sunAltitude, 1, '°') + ' / ' + this.host.fmtNum(this.store.astroContext.sunAzimuth, 1, '°')
                + ' · 月亮 ' + this.host.fmtNum(this.store.astroContext.moonAltitude, 1, '°') + ' / ' + this.host.fmtNum(this.store.astroContext.moonAzimuth, 1, '°')
                + ' · 月面 ' + this.host.fmtNum(this.store.astroContext.moonIllumination, 1, '%'))
                .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.store.astroCalcSnapshot.length > 0) {
                Text('当前参数 · ' + this.store.astroCalcSnapshot)
                  .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .transition(TransitionEffect.OPACITY)
          }
        }
          .width('100%')
          .padding({ left: 10, right: 8, top: 5, bottom: 5 })
          .backgroundColor(this.c.soft)
          .borderRadius(UI_RADIUS_CONTROL)
          .margin({ bottom: 8 })

        AstroSelectionGuide({
          visible: (this.store.astroTab === 2 || this.store.astroTab === 4 || (this.store.astroTab === 1 && this.store.ephemerisMode < 2)) && this.objectDetailStore.selectedName.length === 0,
          onOpenPicker: () => { this.host.openAstroTargetPicker() }
        })
        Scroll(this.scroller) {
          Column({ space: 0 }) {
            if (this.store.astroTab === 0) {
              Text(I18n.t('i0125')).fontSize(this.fs(13)).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
              Row({ space: 4 }) {
                ForEach(['地平位置', '日心黄道', '目录天体'], (mode: string, index: number) => {
                  Text(mode).fontSize(this.fs(10))
                    .fontColor(this.store.positionMode === index ? this.c.onAccent : this.c.sub)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.store.positionMode === index ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.positionMode !== index) {
                        this.store.positionMode = index
                        if (index === 0) this.host.loadPlanetPositions()
                        else if (index === 1) this.host.loadHeliocentricPositions()
                        else this.host.loadCelestialPositions()
                      }
                    })
                }, (mode: string) => mode)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.store.positionMode === 0) {
                Button(I18n.t('i0241')).fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadPlanetPositions() })
                Column({ space: 1 }) {
                  Row() {
                    Text(I18n.t('s0374')).fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1)
                    Text(I18n.t('s0375')).fontSize(this.fs(10)).fontColor(this.c.sub).width(58).textAlign(TextAlign.End)
                    Text(I18n.t('s0376')).fontSize(this.fs(10)).fontColor(this.c.sub).width(58).textAlign(TextAlign.End)
                    Text(I18n.t('s0377')).fontSize(this.fs(10)).fontColor(this.c.sub).width(44).textAlign(TextAlign.End)
                  }.width('100%')
                  Text('赤经/赤纬（当日） · 距离 · 视直径 · 中天').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%')
                }.width('100%').padding({ left: 8, right: 8 }).margin({ top: 4, bottom: 2 })
                if (this.store.planetPositionsLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.c.accent)
                    Text('正在计算行星位置…').fontSize(this.fs(11)).fontColor(this.c.sub)
                  }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
                } else if (this.store.planetPositionsError.length > 0) {
                  Text(this.store.planetPositionsError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
                } else if (this.store.planetPositions.length === 0) {
                  Text('当前没有可显示的行星位置。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
                }
                Column({ space: 4 }) {
                  ForEach(this.store.planetPositions, (p: PlanetPosition) => {
                    Column({ space: 2 }) {
                      Row() {
                        Text(planetZh(p.name)).fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1)
                        Text(p.altitude.toFixed(1) + '°').fontSize(this.fs(11)).fontColor(this.c.sub).width(58).textAlign(TextAlign.End)
                        Text(p.azimuth.toFixed(1) + '°').fontSize(this.fs(11)).fontColor(this.c.sub).width(58).textAlign(TextAlign.End)
                        Text(p.magnitude.toFixed(1)).fontSize(this.fs(11)).fontColor(this.c.sub).width(44).textAlign(TextAlign.End)
                      }.width('100%')
                      Text((p.rightAscension ?? '--') + ' / ' + (p.declination ?? '--')
                        + ' · ' + (p.distanceAU !== undefined ? p.distanceAU.toFixed(3) + ' AU' : '--')
                        + ' · 中天 ' + (p.transit !== undefined ? this.host.fmtDateTime(p.transit) : '--'))
                        .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .constraintSize({ minHeight: this.ch(46) })
                    .width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.searchObject(p.englishName ?? p.name) })
                  }, (p: PlanetPosition, index: number) => p.name)
                }.width('100%').margin({ top: 4, bottom: 8 })
              } else if (this.store.positionMode === 1) {
                Row({ space: 6 }) {
                  Row({ space: 2 }) {
                    Text('已选小天体').fontSize(this.fs(11)).fontColor(this.c.text)
                    InfoTipButton({
                      title: '日心黄道',
                      tip: '以太阳为中心显示实时日心位置；每条细椭圆对应一颗行星的轨道，可开启下方开关叠加当前选中的小天体或彗星。'
                    })
                  }.layoutWeight(1).alignItems(VerticalAlign.Center)
                   Toggle({ type: ToggleType.Switch, isOn: this.store.hecIncludeSelectedMinor })
                     .width(38).height(22).selectedColor(this.c.accent)
                     .clickEffect({ level: ClickEffectLevel.LIGHT })
                     .onChange((value: boolean) => { this.store.hecIncludeSelectedMinor = value; this.host.loadHeliocentricPositions() })
                }.width('100%').height(34).padding({ left: 4, right: 4 })
                Row({ space: 8 }) {
                  Text('显示明亮彗星').fontSize(this.fs(10)).fontColor(this.c.text).layoutWeight(1)
                   Toggle({ type: ToggleType.Switch, isOn: this.store.hecIncludeBrightComets })
                     .width(38).height(22)
                     .onChange((value: boolean) => { this.store.hecIncludeBrightComets = value; this.host.loadHeliocentricPositions() })
                }.width('100%').height(30).padding({ left: 4, right: 4 })
                if (this.store.hecIncludeBrightComets) {
                  Row({ space: 4 }) {
                    Text('彗星星等上限').fontSize(this.fs(10)).fontColor(this.c.sub).width(76)
                    ForEach([6, 9, 12], (limit: number) => {
                      Text(limit.toString()).fontSize(this.fs(10))
                        .fontColor(this.store.hecCometMagnitudeLimit === limit ? this.c.onAccent : this.c.sub)
                        .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                        .backgroundColor(this.store.hecCometMagnitudeLimit === limit ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                        .borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => { this.store.hecCometMagnitudeLimit = limit; this.host.loadHeliocentricPositions() })
                    }, (limit: number) => limit.toString())
                  }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 5 })
                }
                Row({ space: 8 }) {
                  Button('刷新坐标').fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadHeliocentricPositions() })
                  Text(this.store.hecTime.length > 0 ? this.host.fmtDateTime(this.store.hecTime) : '正在计算…').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1)
                }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 5 })
                if (this.store.hecPositionsLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.c.accent)
                    Text('正在计算日心黄道位置…').fontSize(this.fs(11)).fontColor(this.c.sub)
                  }.width('100%').padding({ left: 8 }).margin({ top: 4, bottom: 6 })
                } else if (this.store.hecPositionsError.length > 0) {
                  Text(this.store.hecPositionsError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 4, bottom: 6 })
                } else if (this.store.hecPositions.length === 0) {
                  Text('当前没有可显示的日心位置。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 4, bottom: 6 })
                }
                SolarSystemOrreryView({
                  positions: this.store.hecPositions,
                  timeLabel: this.store.hecTime.length > 0 ? this.host.fmtDateTime(this.store.hecTime) : '',
                  nightMode: String(this.c.accent) === '#F00000',
                  onFocusPlanet: (englishName: string): void => { this.host.searchObject(englishName) }
                })
                Row() {
                  Text('天体').fontSize(this.fs(10)).fontColor(this.c.sub).width(70)
                  Text('黄纬').fontSize(this.fs(10)).fontColor(this.c.sub).width(47)
                  Text('黄经').fontSize(this.fs(10)).fontColor(this.c.sub).width(47)
                  Text('距日').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1)
                }.height(20).width('100%').padding({ left: 8, right: 8 })
                Column({ space: 3 }) {
                  ForEach(this.store.hecPositions, (position: HeliocentricPosition) => {
                    Row() {
                      Text(this.host.hecTitle(position)).fontSize(this.fs(11)).fontColor(this.c.text).width(74).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(position.latitude.toFixed(1) + '°').fontSize(this.fs(10)).fontColor(this.c.sub).width(50)
                      Text(position.longitude.toFixed(1) + '°').fontSize(this.fs(10)).fontColor(this.c.sub).width(50)
                      Text(hecDistanceLabel(position) + ' AU').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.End).maxLines(1)
                    }
                    .constraintSize({ minHeight: this.ch(32) }).width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
                    .backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.searchObject(position.englishName) })
                  }, (position: HeliocentricPosition) => position.englishName)
                }.width('100%').margin({ bottom: 8 })
              } else {
                Row({ space: 6 }) {
                  Text('地平以上目录天体').fontSize(this.fs(11)).fontColor(this.c.sub)
                  InfoTipButton({
                    title: '天体位置表',
                    tip: '列出当前地平线以上、满足星等条件的目录天体；按高度由高到低排列，点击任意项可定位星图。'
                  })
                }.width('100%').padding({ left: 2 }).margin({ bottom: 4 }).alignItems(VerticalAlign.Center)
                Scroll() {
                  Row({ space: 4 }) {
                    ForEach(CELESTIAL_POSITION_CATEGORIES, (category: CelestialPositionCategory) => {
                      Text(category.label).fontSize(this.fs(10))
                        .fontColor(this.store.celestialPositionCategory === category.id ? this.c.onAccent : this.c.sub)
                        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                        .backgroundColor(this.store.celestialPositionCategory === category.id ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                        .borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => { this.store.celestialPositionCategory = category.id; this.host.loadCelestialPositions() })
                    }, (category: CelestialPositionCategory) => category.id)
                  }.padding({ left: 2, right: 2 })
                }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
                Row({ space: 4 }) {
                  Text('星等上限').fontSize(this.fs(10)).fontColor(this.c.sub).width(56)
                  ForEach([3, 6, 9, 12], (magnitude: number) => {
                    Text(magnitude.toString()).fontSize(this.fs(10))
                      .fontColor(this.store.celestialPositionMagnitude === magnitude ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.celestialPositionMagnitude === magnitude ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.celestialPositionMagnitude = magnitude; this.host.loadCelestialPositions() })
                  }, (magnitude: number) => magnitude.toString())
                }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
                Row({ space: 8 }) {
                  Text('使用地平坐标').fontSize(this.fs(10)).fontColor(this.c.text).layoutWeight(1)
                   Toggle({ type: ToggleType.Switch, isOn: this.store.celestialPositionHorizontal })
                     .width(38).height(22)
                     .onChange((value: boolean) => { this.store.celestialPositionHorizontal = value; this.host.loadCelestialPositions() })
                  Button('刷新').fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadCelestialPositions() })
                }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 5 })
                Text(this.store.celestialPositionTime.length > 0 ? this.host.fmtDateTime(this.store.celestialPositionTime) : '正在计算…').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 4 }).margin({ bottom: 4 })
                if (this.store.celestialPositionsLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.c.accent)
                    Text('正在计算目录天体位置…').fontSize(this.fs(11)).fontColor(this.c.sub)
                  }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
                } else if (this.store.celestialPositionsError.length > 0) {
                  Text(this.store.celestialPositionsError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8 })
                } else if (this.store.celestialPositions.length === 0) {
                  Text('当前筛选条件下没有地平线以上的天体。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8 })
                } else {
                  Column({ space: 4 }) {
                    ForEach(this.store.celestialPositions, (position: CelestialPosition) => {
                      Column({ space: 2 }) {
                        Row() {
                          Text(this.host.celestialPositionTitle(position)).fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                          Text('星等 ' + position.magnitude.toFixed(1)).fontSize(this.fs(10)).fontColor(this.c.sub).textAlign(TextAlign.End)
                        }.width('100%')
                        if (this.host.celestialPositionSubtitle(position).length > 0) {
                          Text(this.host.celestialPositionSubtitle(position)).fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        Text((this.store.celestialPositionHorizontal ? '方位 ' : '赤经 ') + position.firstCoordinate + '   ' + (this.store.celestialPositionHorizontal ? '高度 ' : '赤纬 ') + position.secondCoordinate)
                          .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(2)
                        Text('地平高度 ' + position.altitude.toFixed(1) + '°   距日 ' + (position.elongation ?? 0).toFixed(1) + '°')
                          .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(1)
                        Text('视直径 ' + (position.angularSizeArcmin !== undefined ? position.angularSizeArcmin.toFixed(2) + '′' : '--')
                          + (position.distanceAU !== undefined ? '   距离 ' + position.distanceAU.toFixed(3) + ' AU' : '')
                          + (position.transit !== undefined ? '   中天 ' + this.host.fmtClock(position.transit) : ''))
                          .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(2)
                      }
                      .width('100%').padding({ left: 10, right: 10, top: 7, bottom: 7 })
                      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.host.searchObject(position.englishName) })
                    }, (position: CelestialPosition) => position.englishName + position.catalogId)
                  }.width('100%').margin({ bottom: 8 })
                }
              }
            } else if (this.store.astroTab === 1) {
              Text(I18n.t('i0126')).fontSize(this.fs(13)).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
              Text('计算对象').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach(['当前选中天体', '两个天体', '全部肉眼行星'], (label: string, mode: number) => {
                  Text(label).fontSize(this.fs(10))
                    .fontColor(this.store.ephemerisMode === mode ? this.c.onAccent : this.c.sub)
                    .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                    .backgroundColor(this.store.ephemerisMode === mode ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.ephemerisMode = mode })
                }, (label: string) => label)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
              if (this.store.ephemerisMode === 0) {
                Row({ space: 8 }) {
                  Column({ space: 1 }) {
                    Text('星历目标').fontSize(this.fs(10)).fontColor(this.c.sub)
                    Text(this.objectDetailStore.selectedName.length > 0 ? zhNameOf(this.objectDetailStore.selectedName) : '尚未选择天体')
                      .fontSize(this.fs(11)).fontColor(this.objectDetailStore.selectedName.length > 0 ? this.c.textStrong : this.c.sub)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Button(this.objectDetailStore.selectedName.length > 0 ? '更换天体' : '选择天体')
                    .fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 10, right: 10 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.openEphemerisTargetPicker() })
                }.width('100%').padding({ left: 4, right: 4, top: 4, bottom: 5 })
                  .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 5 })
              }
              if (this.store.ephemerisMode === 1) {
                Text('第一个天体').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Scroll() {
                  Row({ space: 4 }) {
                    ForEach(['Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                      Text(planetPairBodyName(body)).fontSize(this.fs(10))
                        .fontColor(this.store.ephemerisPrimary === body ? this.c.onAccent : this.c.sub)
                        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                        .backgroundColor(this.store.ephemerisPrimary === body ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => {
                          this.store.ephemerisPrimary = body
                          if (this.store.ephemerisSecondary === body) this.store.ephemerisSecondary = 'Sun'
                        })
                    }, (body: string) => body)
                  }.padding({ left: 2, right: 2 })
                }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 4 })
                Text('第二个天体').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Scroll() {
                  Row({ space: 4 }) {
                    ForEach(['Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                      if (body !== this.store.ephemerisPrimary) {
                        Text(planetPairBodyName(body)).fontSize(this.fs(10))
                          .fontColor(this.store.ephemerisSecondary === body ? this.c.onAccent : this.c.sub)
                          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                          .backgroundColor(this.store.ephemerisSecondary === body ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => { this.store.ephemerisSecondary = body })
                      }
                    }, (body: string) => body)
                  }.padding({ left: 2, right: 2 })
                }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
              }
              Text('时间范围').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([7, 14, 31], (days: number) => {
                  Text(days.toString() + ' 天')
                    .fontSize(this.fs(10))
                    .fontColor(this.store.ephemerisDays === days ? this.c.onAccent : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.ephemerisDays === days ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.ephemerisDays !== days) {
                        this.store.ephemerisDays = days
                        this.host.loadEphemeris()
                      }
                    })
                }, (days: number) => days.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('开始日期').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([0, 1, 7, 30], (offsetDays: number) => {
                  Text(this.host.ephemerisStartOptionLabel(offsetDays)).fontSize(this.fs(10))
                    .fontColor(this.store.ephemerisStartOffsetDays === offsetDays ? this.c.onAccent : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.ephemerisStartOffsetDays === offsetDays ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.ephemerisStartOffsetDays !== offsetDays) {
                        this.store.ephemerisStartOffsetDays = offsetDays
                        this.host.loadEphemeris()
                      }
                    })
                }, (offsetDays: number) => offsetDays.toString())
                Button(this.store.ephemerisStartOffsetDays < 0 ? this.host.ephemerisStartOptionLabel(-1) : '指定日期').fontSize(this.fs(10))
                  .fontColor(this.store.ephemerisStartOffsetDays < 0 ? this.c.onAccent : this.c.sub)
                  .constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.store.ephemerisStartOffsetDays < 0 ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.chooseEphemerisStartDate() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('采样间隔').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([1, 3, 6, 12, 24], (hours: number) => {
                  Text(hours.toString() + ' 小时')
                    .fontSize(this.fs(10))
                    .fontColor(this.store.ephemerisStepHours === hours ? this.c.onAccent : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.ephemerisStepHours === hours ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.ephemerisStepHours !== hours) {
                        this.store.ephemerisStepHours = hours
                        this.host.loadEphemeris()
                      }
                    })
                }, (hours: number) => hours.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Row({ space: 6 }) {
                Button('刷新星历').fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadEphemeris() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              Text(this.store.ephemerisMode === 0 ? '选择天体后将自动生成星历；点任一行可跳到对应时刻。' : (this.store.ephemerisMode === 1 ? '两个天体共用同一时间轴，便于直接比较位置和星等。' : '肉眼行星模式在地球上显示水星、金星、火星、木星和土星。')).fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              if (this.store.ephemerisLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.c.accent)
                  Text('正在生成星历…').fontSize(this.fs(11)).fontColor(this.c.sub)
                }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
              } else if (this.store.ephemerisError.length > 0) {
                Text(this.store.ephemerisError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else if (this.store.ephemerisData.length === 0) {
                Text('尚未生成星历。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else {
                Text(this.store.ephemerisName + ' · 从' + this.host.ephemerisStartOptionLabel(this.store.ephemerisStartOffsetDays) + '开始，持续 ' + this.store.ephemerisDays.toString() + ' 天（每 ' + this.store.ephemerisStepHours.toString() + ' 小时）').fontSize(this.fs(11)).fontColor(this.c.text).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                if (this.store.ephemerisMeta.length > 0) {
                  Text(this.store.ephemerisMeta).fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                }
              }
              ForEach(this.store.ephemerisData, (row: EphemerisRow) => {
                Column({ space: 1 }) {
                  Row({ space: 8 }) {
                    Text(this.host.fmtEphemerisDate(row.date)).fontSize(this.fs(10)).fontColor(this.c.text).width(96)
                    Text((row.bodyName !== undefined ? row.bodyName + '  ' : '') + '赤经 ' + (row.ra ?? '--')).fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).maxLines(1)
                  }.width('100%')
                  Text('赤纬 ' + (row.dec ?? '--')).fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(1)
                  if (row.raOfDate !== undefined || row.decOfDate !== undefined) {
                    Text('当日坐标 ' + (row.raOfDate ?? '--') + '  ' + (row.decOfDate ?? '--')).fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(1)
                  }
                  Text('高度 ' + this.host.fmtNum(row.altitude, 1, '°')
                    + '   方位 ' + this.host.fmtNum(row.azimuth, 0, '°')
                    + '   星等 ' + this.host.fmtNum(row.magnitude, 1, ''))
                    .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(1)
                  if (row.hourAngle !== undefined || row.polarDistanceDegrees !== undefined) {
                    Text('时角 ' + (row.hourAngle ?? '--') + '   极距 ' + this.host.fmtNum(row.polarDistanceDegrees, 2, '°')
                      + (row.airmass !== undefined ? '   气团 ' + row.airmass.toFixed(2) : ''))
                      .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(1)
                  }
                  if (row.phase !== undefined || row.distanceAU !== undefined || row.elongationDegrees !== undefined) {
                    Text((row.phase !== undefined ? '相位 ' + (row.phase * 100).toFixed(1) + '%' : '')
                      + (row.distanceAU !== undefined ? '   距离 ' + row.distanceAU.toFixed(3) + ' AU' : '')
                      + (row.elongationDegrees !== undefined ? '   距日 ' + row.elongationDegrees.toFixed(1) + '°' : ''))
                      .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(1)
                  }
                  if (row.angularSizeArcmin !== undefined) {
                    Text('视直径 ' + row.angularSizeArcmin.toFixed(2) + '′').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(1)
                  }
                }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
                .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.jumpToEphemerisRow(row) })
              }, (row: EphemerisRow, index: number) => index.toString())
            } else if (this.store.astroTab === 2) {
              Text(I18n.t('i0127')).fontSize(this.fs(13)).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
              Button(I18n.t('i0239')).fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.loadRTS() })
              if (!this.host.hasSelectedObject()) {
                RtsSelectionGuide({ onPick: () => { this.host.openRtsTargetPicker() } })
              } else if (this.store.rtsLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(20).height(20).color(this.c.accent)
                  Text('正在计算升起、中天和落下时间…').fontSize(this.fs(11)).fontColor(this.c.sub)
                }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
              } else if (this.store.rtsError.length > 0) {
                Text(this.store.rtsError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.store.rtsData.size > 0) {
                TargetTransitArcView({
                  objectName: this.store.rtsData.get('name') ?? '目标天体',
                  riseText: this.host.jdToDateStr(this.store.rtsData.get('nextRiseText') ?? '0'),
                  transitText: this.host.jdToDateStr(this.store.rtsData.get('nextTransitText') ?? '0'),
                  setText: this.host.jdToDateStr(this.store.rtsData.get('nextSetText') ?? '0'),
                  nightMode: String(this.c.accent) === '#F00000',
                  onJumpRise: (): void => { this.host.jumpToRts('nextRiseJD') },
                  onJumpTransit: (): void => { this.host.jumpToRts('nextTransitJD') },
                  onJumpSet: (): void => { this.host.jumpToRts('nextSetJD') }
                })
                InfoRow({ label: I18n.t('s0358'), value: this.store.rtsData.get('name') ?? 'N/A' })
                Row()
                  .width('100%').height(0.5)
                  .backgroundColor(this.c.border)
                  .margin({ top: 4, bottom: 4 })
                Text(I18n.t('s0370')).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                InfoRow({ label: I18n.t('s0700'), value: this.host.jdToDateStr(this.store.rtsData.get('nextRiseText') ?? '0') })
                InfoRow({ label: I18n.t('s0701'), value: this.host.jdToDateStr(this.store.rtsData.get('nextTransitText') ?? '0') })
                InfoRow({ label: I18n.t('s0702'), value: this.host.jdToDateStr(this.store.rtsData.get('nextSetText') ?? '0') })
                Row()
                  .width('100%').height(0.5)
                  .backgroundColor(this.c.border)
                  .margin({ top: 4, bottom: 4 })
                Text(I18n.t('s0371')).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                InfoRow({ label: I18n.t('s0700'), value: this.host.jdToDateStr(this.store.rtsData.get('prevRiseText') ?? '0') })
                InfoRow({ label: I18n.t('s0701'), value: this.host.jdToDateStr(this.store.rtsData.get('prevTransitText') ?? '0') })
                InfoRow({ label: I18n.t('s0702'), value: this.host.jdToDateStr(this.store.rtsData.get('prevSetText') ?? '0') })
              }
              if (this.host.hasSelectedObject()) {
              Row({ space: 6 }) {
                Button(I18n.t('i0146')).fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.jumpToRts('nextRiseJD') })
                Button(I18n.t('i0148')).fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.jumpToRts('nextTransitJD') })
                Button(I18n.t('i0147')).fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.jumpToRts('nextSetJD') })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.c.border)
                .margin({ top: 10, bottom: 8 })
              Text('升中天落日期表').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Text('持续时长').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Scroll() {
                Row({ space: 4 }) {
                  ForEach([7, 14, 31, 62, 92, 183, 365], (days: number) => {
                    Text(rtsCalendarDurationLabel(days)).fontSize(this.fs(10))
                    .fontColor(this.store.rtsCalendarDays === days ? this.c.onAccent : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.rtsCalendarDays === days ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.rtsCalendarDays !== days) {
                        this.store.rtsCalendarDays = days
                        this.host.markRtsCalendarForRegeneration()
                      }
                    })
                  }, (days: number) => days.toString())
                }.padding({ left: 2, right: 2 })
              }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
              Text('开始日期').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([0, 1, 7, 30], (offsetDays: number) => {
                  Text(this.host.rtsCalendarStartOptionLabel(offsetDays)).fontSize(this.fs(10))
                    .fontColor(this.store.rtsCalendarStartOffsetDays === offsetDays ? this.c.onAccent : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.rtsCalendarStartOffsetDays === offsetDays ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.rtsCalendarStartOffsetDays !== offsetDays) {
                        this.store.rtsCalendarStartOffsetDays = offsetDays
                        this.host.markRtsCalendarForRegeneration()
                      }
                    })
                }, (offsetDays: number) => offsetDays.toString())
                Button(this.store.rtsCalendarStartOffsetDays < 0 ? this.host.rtsCalendarStartOptionLabel(-1) : '指定日期').fontSize(this.fs(10))
                  .fontColor(this.store.rtsCalendarStartOffsetDays < 0 ? this.c.onAccent : this.c.sub)
                  .constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9, top: 4, bottom: 4 })
                  .backgroundColor(this.store.rtsCalendarStartOffsetDays < 0 ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.chooseRtsCalendarStartDate() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
              Row({ space: 6 }) {
                Button('生成日期表').fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadRtsCalendar() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
              if (this.store.rtsCalendarLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.c.accent)
                  Text('正在生成升中天落日期表… ' + this.store.rtsCalendarProgress.toString() + '/' + this.store.rtsCalendarTotalDays.toString() + ' 天').fontSize(this.fs(11)).fontColor(this.c.sub)
                }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
              } else if (this.store.rtsCalendarNeedsGeneration) {
                Text('参数已更新，请点击生成日期表开始计算。').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 4 })
              } else if (this.store.rtsCalendarError.length > 0) {
                Text(this.store.rtsCalendarError).fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 4 })
              } else if (this.store.rtsCalendarData.length > 0) {
                Text(this.store.rtsCalendarName + ' · 从' + this.host.rtsCalendarStartOptionLabel(this.store.rtsCalendarStartOffsetDays) + '开始，持续 ' + rtsCalendarDurationLabel(this.store.rtsCalendarDays) + '；每项按本地日期计算，点击可跳到该日中天。')
                  .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                ForEach(this.store.rtsCalendarData, (day: RtsCalendarDay) => {
                  Column({ space: 1 }) {
                    Row() {
                      Text(this.host.fmtDateTime(day.date)).fontSize(this.fs(10)).fontColor(this.c.text).width(94)
                      if (day.status !== undefined) {
                        Text(day.status ?? '').fontSize(this.fs(10)).fontColor(this.c.accent).layoutWeight(1)
                      } else {
                        Text('升 ' + this.host.fmtClock(day.rise) + '  中天 ' + this.host.fmtClock(day.transit) + '  落 ' + this.host.fmtClock(day.set))
                          .fontSize(this.fs(10)).fontColor(this.c.text).layoutWeight(1).maxLines(1)
                      }
                    }.width('100%').padding({ left: 8, right: 8 })
                    if (day.status === undefined) {
                      Text('中天高度 ' + (day.transitAltitude ?? 0).toFixed(1) + '°   星等 ' + (day.magnitude ?? 0).toFixed(1)
                        + '   距日 ' + (day.solarElongation ?? 0).toFixed(1) + '°   距月 ' + (day.lunarElongation ?? 0).toFixed(1) + '°')
                        .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 }).maxLines(1)
                    }
                  }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.jumpToRtsCalendar(day) })
                }, (day: RtsCalendarDay, index: number) => day.date ?? index.toString())
              }
              }
            } else if (this.store.astroTab === 3) {
              Row({ space: 6 }) {
                Text(this.store.isEarthObserver() ? I18n.t('i0128') : (this.store.observerPlanetZh + '视角 · 天象预报'))
                  .fontSize(this.fs(14)).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1)
                InfoTipButton({
                  title: '多星体天象预报',
                  tip: '自动按当前观测星体视角计算合、冲、大距、方照、留点与近日/远日点；在火星、木星等外行星上可直接计算地球东/西大距与合日。'
                })
              }.width('100%').alignItems(VerticalAlign.Center).margin({ top: 2, bottom: 8 })
              Column({ space: 8 }) {
                Column({ space: 4 }) {
                  Text('计算对象').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%')
                  Scroll() {
                    Row({ space: 6 }) {
                      ForEach(this.phenomenaBodyChoices(), (body: string) => {
                        Text(body === 'Earth' ? '地球' : this.host.phenomenaBodyName(body)).fontSize(this.fs(11))
                          .fontColor(this.store.phenomenaPrimary === body ? this.c.onAccent : this.c.sub)
                          .padding({ left: 10, right: 10, top: this.pv(6), bottom: this.pv(6) })
                          .backgroundColor(this.store.phenomenaPrimary === body ? this.c.accent : this.c.bg)
                          .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                          .borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => {
                            this.store.phenomenaPrimary = body
                            if (this.store.phenomenaTarget === body) this.store.phenomenaTarget = 'all'
                          })
                      }, (body: string) => this.store.observerPlanet + ':' + body)
                    }
                  }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
                }.width('100%').alignItems(HorizontalAlign.Start)

                if (this.store.phenomenaPrimary !== 'all') {
                  Column({ space: 4 }) {
                    Text('比较对象').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%')
                    Scroll() {
                      Row({ space: 6 }) {
                        ForEach(this.phenomenaBodyChoices(), (body: string) => {
                          if (body !== this.store.phenomenaPrimary) {
                            Text(body === 'Earth' ? '地球' : this.host.phenomenaBodyName(body)).fontSize(this.fs(11))
                              .fontColor(this.store.phenomenaTarget === body ? this.c.onAccent : this.c.sub)
                              .padding({ left: 10, right: 10, top: this.pv(6), bottom: this.pv(6) })
                              .backgroundColor(this.store.phenomenaTarget === body ? this.c.accent : this.c.bg)
                              .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                              .borderRadius(UI_RADIUS_CONTROL)
                              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                              .onClick(() => { this.store.phenomenaTarget = body })
                          }
                        }, (body: string) => this.store.observerPlanet + ':tgt:' + body)
                      }
                    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
                  }.width('100%').alignItems(HorizontalAlign.Start)
                }

                Column({ space: 4 }) {
                  Text('起始时段').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%')
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(PHENOMENA_START_OPTIONS, (item: PhenomenaStartOption) => {
                      Text(item.label).fontSize(this.fs(11))
                        .fontColor(this.store.phenomenaStartOffsetMonths === item.value ? this.c.onAccent : this.c.sub)
                        .padding({ left: 10, right: 10, top: this.pv(6), bottom: this.pv(6) })
                        .margin({ right: 6, bottom: 4 })
                        .backgroundColor(this.store.phenomenaStartOffsetMonths === item.value ? this.c.accent : this.c.bg)
                        .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                        .borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => { this.store.phenomenaStartOffsetMonths = item.value })
                    }, (item: PhenomenaStartOption) => item.value.toString())
                  }.width('100%')
                }.width('100%').alignItems(HorizontalAlign.Start)

                Column({ space: 4 }) {
                  Text('预测范围').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%')
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach([30, 90, 180, 400, 730], (days: number) => {
                      Text(days < 365 ? days.toString() + ' 天' : (days / 365).toFixed(1) + ' 年').fontSize(this.fs(11))
                        .fontColor(this.store.phenomenaDays === days ? this.c.onAccent : this.c.sub)
                        .padding({ left: 10, right: 10, top: this.pv(6), bottom: this.pv(6) })
                        .margin({ right: 6, bottom: 4 })
                        .backgroundColor(this.store.phenomenaDays === days ? this.c.accent : this.c.bg)
                        .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                        .borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => { this.store.phenomenaDays = days })
                    }, (days: number) => days.toString())
                  }.width('100%')
                }.width('100%').alignItems(HorizontalAlign.Start)

                Column({ space: 4 }) {
                  Text('最大角距').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%')
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach([1, 4, 10, 20], (degrees: number) => {
                      Text(degrees.toString() + '°').fontSize(this.fs(11))
                        .fontColor(this.store.phenomenaMaxSeparation === degrees ? this.c.onAccent : this.c.sub)
                        .padding({ left: 12, right: 12, top: this.pv(6), bottom: this.pv(6) })
                        .margin({ right: 6, bottom: 4 })
                        .backgroundColor(this.store.phenomenaMaxSeparation === degrees ? this.c.accent : this.c.bg)
                        .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                        .borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => { this.store.phenomenaMaxSeparation = degrees })
                    }, (degrees: number) => degrees.toString())
                  }.width('100%')
                }.width('100%').alignItems(HorizontalAlign.Start)

                Column({ space: 4 }) {
                  Text('附加天象').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%')
                  Flex({ wrap: FlexWrap.Wrap }) {
                    Text('冲').fontSize(this.fs(11)).fontColor(this.store.phenomenaIncludeOppositions ? this.c.onAccent : this.c.sub)
                      .padding({ left: 10, right: 10, top: this.pv(6), bottom: this.pv(6) }).margin({ right: 6, bottom: 4 })
                      .backgroundColor(this.store.phenomenaIncludeOppositions ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.phenomenaIncludeOppositions = !this.store.phenomenaIncludeOppositions })
                    Text('近日点/远日点').fontSize(this.fs(11)).fontColor(this.store.phenomenaIncludePerihelionAphelion ? this.c.onAccent : this.c.sub)
                      .padding({ left: 10, right: 10, top: this.pv(6), bottom: this.pv(6) }).margin({ right: 6, bottom: 4 })
                      .backgroundColor(this.store.phenomenaIncludePerihelionAphelion ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.phenomenaIncludePerihelionAphelion = !this.store.phenomenaIncludePerihelionAphelion })
                    Text('大距/方照').fontSize(this.fs(11)).fontColor(this.store.phenomenaIncludeElongationsQuadratures ? this.c.onAccent : this.c.sub)
                      .padding({ left: 10, right: 10, top: this.pv(6), bottom: this.pv(6) }).margin({ right: 6, bottom: 4 })
                      .backgroundColor(this.store.phenomenaIncludeElongationsQuadratures ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.phenomenaIncludeElongationsQuadratures = !this.store.phenomenaIncludeElongationsQuadratures })
                    Text('留点').fontSize(this.fs(11)).fontColor(this.store.phenomenaIncludeStations ? this.c.onAccent : this.c.sub)
                      .padding({ left: 10, right: 10, top: this.pv(6), bottom: this.pv(6) }).margin({ right: 6, bottom: 4 })
                      .backgroundColor(this.store.phenomenaIncludeStations ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.phenomenaIncludeStations = !this.store.phenomenaIncludeStations })
                  }.width('100%')
                }.width('100%').alignItems(HorizontalAlign.Start)

                Button(this.store.phenomenaLoading ? '正在计算…' : '计算天象')
                  .fontSize(this.fs(12)).fontWeight(FontWeight.Medium)
                  .fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                  .borderRadius(UI_RADIUS_PILL).width('100%')
                  .constraintSize({ minHeight: this.ch(36) })
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .enabled(!this.store.phenomenaLoading)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadPhenomena() })
              }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(10)
                .backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CARD)
                .margin({ bottom: 8 })
              Row({ space: 4 }) {
                Text('天象列表').fontSize(this.fs(11)).fontColor(this.c.sub)
                InfoTipButton({
                  title: '天象计算',
                  tip: '合相按最大角距筛选，同时涵盖大距、冲日、留等主要行星天象；点任一结果可平滑跳到发生时刻。'
                })
              }.width('100%').padding({ left: 2 }).margin({ bottom: 4 }).alignItems(VerticalAlign.Center)
              if (this.store.phenomenaLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.c.accent)
                  Text('正在计算天象…').fontSize(this.fs(12)).fontColor(this.c.sub)
                }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
              } else if (this.store.phenomenaHint.length > 0) {
                Text(this.store.phenomenaHint).fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else if (this.store.phenomenaData.length === 0) {
                Text('尚未计算天象。').fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8 })
              }
              ForEach(this.store.phenomenaData, (p: PhenomenonItem) => {
                Row({ space: 8 }) {
                  Stack({ alignContent: Alignment.Center }) {
                    PhenomenonRelationMark({ type: p.type ?? '' })
                  }.width(52).height(44).backgroundColor(this.c.bg).border({ width: 1, color: this.c.border }).borderRadius(UI_RADIUS_CONTROL)
                  Column({ space: 3 }) {
                    Text(phenomenonCaption(p.type ?? '')).fontSize(this.fs(10)).fontColor(this.c.sub).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text((p.bodyA ?? '天体') + ' 与 ' + (p.bodyB ?? '太阳'))
                      .fontSize(this.fs(12)).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.host.fmtDateTime(p.date)).fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Column({ space: 3 }) {
                    Text(p.metricLabel ?? '角距').fontSize(this.fs(10)).fontColor(this.c.sub).textAlign(TextAlign.End).maxLines(1)
                    Text(this.host.fmtNum(p.separation, 2, p.metricUnit ?? '°')).fontSize(this.fs(11)).fontColor(this.c.text).fontWeight(FontWeight.Medium)
                      .textAlign(TextAlign.End).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.constraintSize({ minWidth: 68, maxWidth: 108 }).alignItems(HorizontalAlign.End)
                }.width('100%').constraintSize({ minHeight: this.ch(62) }).padding({ left: 8, right: 8, top: 7, bottom: 7 })
                  .backgroundColor(this.c.bg).border({ width: 1, color: this.c.border }).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 5 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.jumpToPhenomenon(p) })
              }, (p: PhenomenonItem, index: number) => index.toString())
            } else if (this.store.astroTab === 4) {
              Text(I18n.t('i0129')).fontSize(this.fs(13)).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
              Row({ space: 8 }) {
                Column({ space: 1 }) {
                  Text('曲线目标').fontSize(this.fs(10)).fontColor(this.c.sub)
                  Text(this.host.graphTargetLabel()).fontSize(this.fs(12)).fontColor(this.objectDetailStore.selectedName.length > 0 ? this.c.textStrong : this.c.sub)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button(this.objectDetailStore.selectedName.length > 0 ? '更换天体' : '选择天体')
                  .fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.openGraphTargetPicker() })
              }.width('100%').padding({ left: 4, right: 4, top: 5, bottom: 5 })
                .backgroundColor(this.c.bg).border({ width: 1, color: this.c.border }).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
              if (this.store.graphMode !== 2) {
                Text('起始日期').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([0, 1, 7, 30], (offsetDays: number) => {
                    Text(graphStartOptionLabel(offsetDays)).fontSize(this.fs(10))
                      .fontColor(this.store.graphStartOffsetDays === offsetDays ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.graphStartOffsetDays === offsetDays ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.graphStartOffsetDays !== offsetDays) {
                          this.store.graphStartOffsetDays = offsetDays
                          this.host.reloadCurrentGraph()
                        }
                      })
                  }, (offsetDays: number) => offsetDays.toString())
                  Button(this.host.graphCustomStartLabel()).fontSize(this.fs(10))
                    .fontColor(this.store.graphStartOffsetDays < 0 ? this.c.onAccent : this.c.sub)
                    .constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.graphStartOffsetDays < 0 ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.chooseGraphStartDate() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
              }
              Row({ space: 4 }) {
                ForEach(['高度', '方位', '全年', '月度', '月距', '双曲线'], (mode: string, index: number) => {
                  Text(mode).fontSize(this.fs(10))
                    .fontColor(this.store.graphMode === index ? this.c.onAccent : this.c.sub)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.store.graphMode === index ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.graphMode !== index) {
                        this.store.graphMode = index
                        if (index === 2) this.host.loadAnnualElevation()
                        else if (index === 3) this.host.loadObservabilityCalendar()
                        else if (index === 4) this.host.loadLunarElongation()
                        else if (index === 5) this.host.loadPlanetTimeSeries()
                        else this.host.loadAltAzCurve()
                      }
                    })
                }, (mode: string) => mode)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
              if (this.store.graphMode === 0 || this.store.graphMode === 1) {
              Text('时间范围').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([12, 24, 48, 72], (hours: number) => {
                  Text(hours.toString() + 'h')
                    .fontSize(this.fs(10))
                    .fontColor(this.store.altAzHours === hours ? this.c.onAccent : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.altAzHours === hours ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.altAzHours !== hours) {
                        this.store.altAzHours = hours
                        this.host.loadAltAzCurve()
                      }
                    })
                }, (hours: number) => hours.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('采样间隔').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([15, 30, 60], (stepMin: number) => {
                  Text(stepMin.toString() + ' 分')
                    .fontSize(this.fs(10))
                    .fontColor(this.store.altAzStepMin === stepMin ? this.c.onAccent : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.altAzStepMin === stepMin ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.altAzStepMin !== stepMin) {
                        this.store.altAzStepMin = stepMin
                        this.host.loadAltAzCurve()
                      }
                    })
                }, (stepMin: number) => stepMin.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.store.graphMode === 0) {
                Text('叠加曲线').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  Text('太阳').fontSize(this.fs(10))
                    .fontColor(this.store.altAzShowSun ? this.c.textStrong : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.altAzShowSun ? AstroColors.solarDim : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.altAzShowSun = !this.store.altAzShowSun; this.host.loadAltAzCurve() })
                  Text('月亮').fontSize(this.fs(10))
                    .fontColor(this.store.altAzShowMoon ? this.c.textStrong : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.altAzShowMoon ? this.c.detailSub : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.altAzShowMoon = !this.store.altAzShowMoon; this.host.loadAltAzCurve() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('显示高度不低于').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([-90, 0, 15, 30], (minimum: number) => {
                    Text(minimum === -90 ? '全部' : minimum.toString() + '°').fontSize(this.fs(10))
                      .fontColor(this.store.altAzMinimum === minimum ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.altAzMinimum === minimum ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.altAzMinimum = minimum })
                  }, (minimum: number) => minimum.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              }
              Row({ space: 6 }) {
                Button(this.store.graphMode === 0 ? '刷新高度' : '刷新方位').fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.store.altAzCurve = []; this.store.altAzError = ''; this.host.loadAltAzCurve() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              if (this.store.graphLoading) {
                GraphLoadingRow({ label: '正在计算' + this.host.altAzRangeLabel() + '的' + (this.store.graphMode === 0 ? '高度' : '方位角') + '变化…' })
              } else if (this.store.altAzError.length > 0) {
                Text(this.store.altAzError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                GraphSelectionGuide({ error: this.store.altAzError, onPick: () => { this.host.openGraphTargetPicker() } })
              } else if (this.store.altAzCurve.length === 0) {
                Text('没有可绘制的数据。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else {
                Text(this.store.altAzName + ' · ' + this.host.altAzRangeLabel() + (this.store.graphMode === 0 ? '高度变化' : '方位角变化') + '（每 ' + this.store.altAzStepMin.toString() + ' 分）').fontSize(this.fs(11)).fontColor(this.c.text).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                Stack({ alignContent: Alignment.Center }) {
                  Row() {
                    ForEach(this.store.altAzCurve, (r: AltAzPoint) => {
                      if (this.store.graphMode === 0) {
                        Row({ space: 1 }) {
                          Column().width(this.host.altCurveSegmentWidth()).height(this.host.altBarHeight(r.altitude))
                            .backgroundColor(this.host.altitudeCurveColor(r.altitude, this.c.accent)).borderRadius(1)
                          if (this.store.altAzShowSun) {
                            Column().width(this.host.altCurveSegmentWidth()).height(this.host.altBarHeight(r.sunAltitude))
                              .backgroundColor(this.host.altitudeCurveColor(r.sunAltitude, AstroColors.solar)).borderRadius(1)
                          }
                          if (this.store.altAzShowMoon) {
                            Column().width(this.host.altCurveSegmentWidth()).height(this.host.altBarHeight(r.moonAltitude))
                              .backgroundColor(this.host.altitudeCurveColor(r.moonAltitude, this.c.fourth)).borderRadius(1)
                          }
                        }.width(this.host.altBarWidth()).height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                      } else {
                        Column().width(this.host.altBarWidth()).height(azBarHeight(r.azimuth))
                          .backgroundColor(this.c.accent).borderRadius(1)
                      }
                    }, (r: AltAzPoint, index: number) => index.toString())
                  }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                  if (this.store.graphMode === 0 && this.store.altAzMinimum <= 0) {
                    Divider().color(this.c.sub).strokeWidth(1).width('100%').align(this.store.altAzMinimum === 0 ? Alignment.Bottom : Alignment.Center)
                  }
                }.width('100%').height(96).padding({ left: 6, right: 6 })
                Row() {
                  Text(this.store.graphMode === 0 ? '现在' : '0°').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Start)
                  Text(this.store.graphMode === 0 ? this.host.altAzMidpointLabel() : '180°').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Center)
                  Text(this.store.graphMode === 0 ? '+' + this.store.altAzHours.toString() + 'h' : '360°').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.End)
                }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                Text(this.store.graphMode === 0 ? (this.store.altAzMinimum <= 0 ? '横线是地平线；主曲线为目标，金色为太阳，银灰色为月亮。' : '曲线仅显示不低于 ' + this.store.altAzMinimum.toString() + '° 的部分；主曲线为目标，金色为太阳，银灰色为月亮。') : '方位角从北方 0° 起顺时针增加：东 90°、南 180°、西 270°。').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                if (this.store.graphMode === 0) {
                  InfoRow({ label: '当前位置', value: this.host.altAzNowLabel() })
                  InfoRow({ label: '最高高度', value: this.host.altAzMaxLabel() })
                  InfoRow({ label: '地平线以上时长', value: this.host.altAzVisibleHours() })
                  InfoRow({ label: '显示下限', value: this.store.altAzMinimum === -90 ? '不限制' : this.store.altAzMinimum.toString() + '°' })
                } else {
                  InfoRow({ label: '当前方位', value: this.host.azimuthNowLabel() })
                }
              }
              } else if (this.store.graphMode === 2) {
                Text('选定本地时刻后，按全年每 3 天采样一次；与桌面版“全年高度”计算方式一致。')
                  .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Row({ space: 8 }) {
                  Text('本地时刻 ' + this.store.annualElevationHour.toString().padStart(2, '0') + ':00').fontSize(this.fs(10)).fontColor(this.c.sub).width(100)
                  Slider({ value: this.store.annualElevationHour, min: 0, max: 23, step: 1 })
                    .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                    .layoutWeight(1)
                    .onChange((value: number) => {
                      const hour = Math.round(value)
                      if (hour !== this.store.annualElevationHour) {
                        this.store.annualElevationHour = hour
                        this.host.loadAnnualElevation()
                      }
                    })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('显示高度不低于').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([-90, 0, 15, 30], (minimum: number) => {
                    Text(minimum === -90 ? '全部' : minimum.toString() + '°').fontSize(this.fs(10))
                      .fontColor(this.store.annualElevationMinimum === minimum ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.annualElevationMinimum === minimum ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.annualElevationMinimum = minimum })
                  }, (minimum: number) => minimum.toString())
                  Button('刷新').fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadAnnualElevation() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.graphLoading) {
                  GraphLoadingRow({ label: '正在生成全年高度曲线…' })
                } else if (this.store.annualElevationError.length > 0) {
                  Text(this.store.annualElevationError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                  GraphSelectionGuide({ error: this.store.annualElevationError, onPick: () => { this.host.openGraphTargetPicker() } })
                } else if (this.store.annualElevationData.length === 0) {
                  Text('没有可绘制的数据。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.annualElevationName + ' · ' + this.store.annualElevationHour.toString().padStart(2, '0') + ':00 全年高度').fontSize(this.fs(11)).fontColor(this.c.text).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  Stack({ alignContent: Alignment.Center }) {
                    Row() {
                      ForEach(this.store.annualElevationData, (point: AnnualElevationPoint) => {
                        Column().width(this.host.annualBarWidth()).height(this.host.annualBarHeight(point.altitude))
                          .backgroundColor((point.altitude ?? -90) >= this.store.annualElevationMinimum ? this.c.accent : this.c.scrollbar).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(1)
                      }, (point: AnnualElevationPoint, index: number) => index.toString())
                    }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                    if (this.store.annualElevationMinimum <= 0) {
                      Divider().color(this.c.sub).strokeWidth(1).width('100%')
                    }
                  }.width('100%').height(96).padding({ left: 6, right: 6 })
                  Row() {
                    Text('1月').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Start)
                    Text('4月').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Center)
                    Text('7月').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Center)
                    Text('10月').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.End)
                  }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                  InfoRow({ label: '全年最高', value: this.host.annualMaxLabel() })
                  InfoRow({ label: '显示下限', value: this.store.annualElevationMinimum === -90 ? '不限制' : this.store.annualElevationMinimum.toString() + '°' })
                }
              } else if (this.store.graphMode === 3) {
                Text('按天文暗夜（太阳低于地平线 18°）统计；点任一晚可跳到目标最高的时刻。')
                  .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Text('计划范围').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([30, 90], (days: number) => {
                    Text('未来 ' + days.toString() + ' 天').fontSize(this.fs(10))
                      .fontColor(this.store.observabilityDays === days ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.observabilityDays === days ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.observabilityDays !== days) {
                          this.store.observabilityDays = days
                          this.host.loadObservabilityCalendar()
                        }
                      })
                  }, (days: number) => days.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('最低高度').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([15, 20, 30], (altitude: number) => {
                    Text(altitude.toString() + '°').fontSize(this.fs(10))
                      .fontColor(this.store.observabilityMinAltitude === altitude ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.observabilityMinAltitude === altitude ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.observabilityMinAltitude !== altitude) {
                          this.store.observabilityMinAltitude = altitude
                          this.host.loadObservabilityCalendar()
                        }
                      })
                  }, (altitude: number) => altitude.toString())
                  Button('刷新').fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadObservabilityCalendar() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.graphLoading) {
                  GraphLoadingRow({ label: this.store.observabilityProgress.length > 0 ? this.store.observabilityProgress : '正在计算未来多晚的观测窗口…' })
                } else if (this.store.observabilityError.length > 0) {
                  Text(this.store.observabilityError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                  GraphSelectionGuide({ error: this.store.observabilityError, onPick: () => { this.host.openGraphTargetPicker() } })
                } else if (this.store.observabilityData.length === 0) {
                  Text('所选时段没有可用观测窗口。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.observabilityName + ' · 高于 ' + this.store.observabilityMinAltitude.toString() + '° 的暗夜可见时间')
                    .fontSize(this.fs(11)).fontColor(this.c.text).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  ForEach(this.store.observabilityData, (day: ObservabilityDay) => {
                    Column({ space: 2 }) {
                      Row() {
                        Text(day.date ?? '--').fontSize(this.fs(11)).fontColor(this.c.text).layoutWeight(1)
                        Text((day.visibleHours ?? 0).toFixed(1) + ' 小时').fontSize(this.fs(11))
                          .fontColor((day.visibleHours ?? 0) > 0 ? this.c.accent : this.c.sub)
                      }.width('100%').padding({ left: 8, right: 8 })
                      if ((day.darkHours ?? 0) > 0) {
                        Text('最佳 ' + this.host.fmtClock(day.peakTime) + ' · 最高 ' + this.host.fmtNum(day.maxAltitude, 1, '°') + ' · 暗夜 ' + this.host.fmtNum(day.darkHours, 1, ' 小时'))
                          .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12, right: 8 })
                        Text('月亮：照亮 ' + this.host.fmtNum(day.moonIllumination, 0, ' %') + '，高度 ' + this.host.fmtNum(day.moonAltitude, 0, '°'))
                          .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12, right: 8 })
                      } else {
                        Text('当地没有完整的天文暗夜。').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12, right: 8 })
                      }
                    }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.jumpToObservabilityDay(day) })
                  }, (day: ObservabilityDay, index: number) => index.toString())
                }
              } else if (this.store.graphMode === 4) {
                Text('显示选中目标与月亮的角距；金色柱表示距离小于参考线，通常意味着月光干扰更明显。')
                  .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Text('时间范围').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([14, 30, 60], (days: number) => {
                    Text('未来 ' + days.toString() + ' 天').fontSize(this.fs(10))
                      .fontColor(this.store.lunarElongationDays === days ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.lunarElongationDays === days ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.lunarElongationDays !== days) {
                          this.store.lunarElongationDays = days
                          this.host.loadLunarElongation()
                        }
                      })
                  }, (days: number) => days.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('采样间隔').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([6, 12, 24], (hours: number) => {
                    Text(hours.toString() + ' 小时').fontSize(this.fs(10))
                      .fontColor(this.store.lunarElongationStepHours === hours ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.lunarElongationStepHours === hours ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.lunarElongationStepHours !== hours) {
                          this.store.lunarElongationStepHours = hours
                          this.host.loadLunarElongation()
                        }
                      })
                  }, (hours: number) => hours.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('月距参考线').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([10, 20, 40, 60], (limit: number) => {
                    Text(limit.toString() + '°').fontSize(this.fs(10))
                      .fontColor(this.store.lunarElongationLimit === limit ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.lunarElongationLimit === limit ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.lunarElongationLimit = limit })
                  }, (limit: number) => limit.toString())
                  Button('刷新').fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadLunarElongation() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.graphLoading) {
                  GraphLoadingRow({ label: '正在计算目标与月亮的角距…' })
                } else if (this.store.lunarElongationError.length > 0) {
                  Text(this.store.lunarElongationError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                  GraphSelectionGuide({ error: this.store.lunarElongationError, onPick: () => { this.host.openGraphTargetPicker() } })
                } else if (this.store.lunarElongationData.length === 0) {
                  Text('没有可绘制的数据。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.lunarElongationName + ' · 未来 ' + this.store.lunarElongationDays.toString() + ' 天月距（每 ' + this.store.lunarElongationStepHours.toString() + ' 小时）')
                    .fontSize(this.fs(11)).fontColor(this.c.text).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  Stack({ alignContent: Alignment.Center }) {
                    Row() {
                      ForEach(this.store.lunarElongationData, (point: LunarElongationPoint) => {
                        Column().width(this.host.lunarElongationBarWidth()).height(lunarElongationBarHeight(point.separation))
                          .backgroundColor((point.separation ?? 180) < this.store.lunarElongationLimit ? AstroColors.solar : this.c.accent).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(1)
                      }, (point: LunarElongationPoint, index: number) => index.toString())
                    }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                    Divider().color(AstroColors.solar).strokeWidth(1).width('100%').position({ x: 0, y: this.host.lunarElongationLineTop() })
                  }.width('100%').height(96).padding({ left: 6, right: 6 })
                  Row() {
                    Text('现在').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Start)
                    Text('+' + Math.round(this.store.lunarElongationDays / 2).toString() + '天').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Center)
                    Text('+' + this.store.lunarElongationDays.toString() + '天').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.End)
                  }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                  Text('纵轴 0°-180°；金色横线是 ' + this.store.lunarElongationLimit.toString() + '° 参考线。').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                  InfoRow({ label: '当前月距', value: this.host.lunarElongationNowLabel() })
                  InfoRow({ label: '最接近月亮', value: this.host.lunarElongationClosestLabel() })
                  InfoRow({ label: '参考线', value: this.store.lunarElongationLimit.toString() + '°' })
                }
              } else {
                Text('桌面版“Graphs”双变量时间曲线：左右两条曲线各自缩放，适合比较不同量纲的变化趋势。')
                  .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Text('时间范围').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([30, 90, 365], (days: number) => {
                    Text(days === 365 ? '未来 1 年' : '未来 ' + days.toString() + ' 天').fontSize(this.fs(10))
                      .fontColor(this.store.planetTimeSeriesDays === days ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.planetTimeSeriesDays === days ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.planetTimeSeriesDays !== days) {
                          this.store.planetTimeSeriesDays = days
                          if (days === 365 && this.store.planetTimeSeriesStepHours < 24) this.store.planetTimeSeriesStepHours = 24
                          this.host.loadPlanetTimeSeries()
                        }
                      })
                  }, (days: number) => days.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('采样间隔').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach(this.store.planetTimeSeriesDays === 365 ? [24, 72] : [6, 24, 72], (hours: number) => {
                    Text(hours.toString() + ' 小时').fontSize(this.fs(10))
                      .fontColor(this.store.planetTimeSeriesStepHours === hours ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.planetTimeSeriesStepHours === hours ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.planetTimeSeriesStepHours !== hours) {
                          this.store.planetTimeSeriesStepHours = hours
                          this.host.loadPlanetTimeSeries()
                        }
                      })
                  }, (hours: number) => hours.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('左轴：' + planetMetricLabel(this.store.planetTimeSeriesLeftMetric)).fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Column({ space: 3 }) {
                  ForEach([['magnitude', 'phase', 'distance', 'elongation', 'angularSize'], ['phaseAngle', 'heliocentricDistance', 'transitAltitude', 'rightAscension', 'declination']], (metrics: Array<string>, row: number) => {
                    Row({ space: 3 }) {
                      ForEach(metrics, (metric: string) => {
                        Text(planetMetricLabel(metric)).fontSize(this.fs(10)).maxLines(1)
                          .fontColor(this.store.planetTimeSeriesLeftMetric === metric ? this.c.onAccent : this.c.sub)
                          .padding({ left: 5, right: 5, top: 4, bottom: 4 })
                          .backgroundColor(this.store.planetTimeSeriesLeftMetric === metric ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                          .borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => { this.store.planetTimeSeriesLeftMetric = metric; this.host.loadPlanetTimeSeries() })
                      }, (metric: string) => metric)
                    }.width('100%')
                  }, (metrics: Array<string>, row: number) => row.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('右轴：' + planetMetricLabel(this.store.planetTimeSeriesRightMetric)).fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Column({ space: 3 }) {
                  ForEach([['magnitude', 'phase', 'distance', 'elongation', 'angularSize'], ['phaseAngle', 'heliocentricDistance', 'transitAltitude', 'rightAscension', 'declination']], (metrics: Array<string>, row: number) => {
                    Row({ space: 3 }) {
                      ForEach(metrics, (metric: string) => {
                        Text(planetMetricLabel(metric)).fontSize(this.fs(10)).maxLines(1)
                          .fontColor(this.store.planetTimeSeriesRightMetric === metric ? this.c.textStrong : this.c.sub)
                          .padding({ left: 5, right: 5, top: 4, bottom: 4 })
                          .backgroundColor(this.store.planetTimeSeriesRightMetric === metric ? AstroColors.solarDim : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                          .borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => { this.store.planetTimeSeriesRightMetric = metric; this.host.loadPlanetTimeSeries() })
                      }, (metric: string) => metric)
                    }.width('100%')
                  }, (metrics: Array<string>, row: number) => row.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Row({ space: 6 }) {
                  Button('刷新').fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadPlanetTimeSeries() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.graphLoading) {
                  GraphLoadingRow({ label: '正在计算双变量时间曲线…' })
                } else if (this.store.planetTimeSeriesError.length > 0) {
                  Text(this.store.planetTimeSeriesError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                  GraphSelectionGuide({ error: this.store.planetTimeSeriesError, onPick: () => { this.host.openGraphTargetPicker() } })
                } else if (this.store.planetTimeSeriesData.length === 0) {
                  Text('没有可绘制的数据。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.planetTimeSeriesName + ' · ' + planetMetricLabel(this.store.planetTimeSeriesLeftMetric) + ' / ' + planetMetricLabel(this.store.planetTimeSeriesRightMetric))
                    .fontSize(this.fs(11)).fontColor(this.c.text).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  Stack({ alignContent: Alignment.Center }) {
                    Row() {
                      ForEach(this.store.planetTimeSeriesData, (point: PlanetTimeSeriesPoint) => {
                        Row({ space: 1 }) {
                          Column().width(this.host.planetTimeSeriesSegmentWidth())
                            .height(planetTimeSeriesBarHeight(point.left, this.store.planetTimeSeriesLeftMin, this.store.planetTimeSeriesLeftMax))
                            .backgroundColor(this.c.accent).borderRadius(1)
                          Column().width(this.host.planetTimeSeriesSegmentWidth())
                            .height(planetTimeSeriesBarHeight(point.right, this.store.planetTimeSeriesRightMin, this.store.planetTimeSeriesRightMax))
                            .backgroundColor(AstroColors.solar).borderRadius(1)
                        }.width(this.host.planetTimeSeriesBarWidth()).height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                      }, (point: PlanetTimeSeriesPoint, index: number) => index.toString())
                    }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                  }.width('100%').height(96).padding({ left: 6, right: 6 })
                  Row() {
                    Text('现在').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Start)
                    Text('+' + Math.round(this.store.planetTimeSeriesDays / 2).toString() + '天').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Center)
                    Text(this.store.planetTimeSeriesDays === 365 ? '+1年' : '+' + this.store.planetTimeSeriesDays.toString() + '天').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.End)
                  }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                  Text('蓝色左轴：' + this.store.planetTimeSeriesLeftMin.toFixed(1) + ' - ' + this.store.planetTimeSeriesLeftMax.toFixed(1) + planetMetricUnit(this.store.planetTimeSeriesLeftMetric)
                    + '；金色右轴：' + this.store.planetTimeSeriesRightMin.toFixed(1) + ' - ' + this.store.planetTimeSeriesRightMax.toFixed(1) + planetMetricUnit(this.store.planetTimeSeriesRightMetric))
                    .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                  InfoRow({ label: '当前 ' + planetMetricLabel(this.store.planetTimeSeriesLeftMetric), value: this.host.planetTimeSeriesValueLabel(this.store.planetTimeSeriesData[0].left, this.store.planetTimeSeriesLeftMetric) })
                  InfoRow({ label: '当前 ' + planetMetricLabel(this.store.planetTimeSeriesRightMetric), value: this.host.planetTimeSeriesValueLabel(this.store.planetTimeSeriesData[0].right, this.store.planetTimeSeriesRightMetric) })
                }
              }
            } else if (this.store.astroTab === 5) {
              Text('今晚可观测目标').fontSize(this.fs(13)).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 2 })
              Text('按时段、最低高度和星等筛选适合观测的天体。').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              Row({ space: 6 }) {
                Button('刷新可观测目标').fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.store.tonightAstro = null; this.host.loadTonightAstro() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              if (this.store.tonightAstro === null) {
                Text('（正在汇总今晚的观测条件…）').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else {
                SolarPathDiagramView({
                  sunRiseText: this.host.fmtDateTime(this.store.tonightAstro!.sun?.rise),
                  sunTransitText: '',
                  sunSetText: this.host.fmtDateTime(this.store.tonightAstro!.sun?.set),
                  astroEndText: this.host.fmtDateTime(this.store.tonightAstro!.sun?.astroTwilightEnd),
                  astroStartText: this.host.fmtDateTime(this.store.tonightAstro!.sun?.astroTwilightStart),
                  daylightLabel: this.store.tonightAstro!.sun?.darkWindowHours !== undefined
                    ? (Math.max(0, 24 - (this.store.tonightAstro!.sun?.darkWindowHours ?? 0)).toFixed(1) + 'h') : '',
                  nightMode: String(this.c.accent) === '#F00000'
                })
                Text('太阳与暗夜窗口').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                InfoRow({ label: '日落', value: this.host.fmtDateTime(this.store.tonightAstro!.sun?.set) })
                InfoRow({ label: '天文暮光结束', value: this.host.fmtDateTime(this.store.tonightAstro!.sun?.astroTwilightEnd) })
                InfoRow({ label: '天文暮光开始', value: this.host.fmtDateTime(this.store.tonightAstro!.sun?.astroTwilightStart) })
                InfoRow({ label: '日出', value: this.host.fmtDateTime(this.store.tonightAstro!.sun?.rise) })
                InfoRow({ label: '可用暗夜时长', value: this.host.fmtNum(this.store.tonightAstro!.sun?.darkWindowHours, 1, ' 小时') })
                Text('月亮').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                InfoRow({ label: '月相', value: this.store.tonightAstro!.moon?.phaseName ?? '--' })
                InfoRow({ label: '照亮比例', value: this.host.fmtNum(this.store.tonightAstro!.moon?.illumination, 1, ' %') })
                InfoRow({ label: '月龄', value: this.host.fmtNum(this.store.tonightAstro!.moon?.age, 1, ' 天') })
                InfoRow({ label: '月出', value: this.host.fmtDateTime(this.store.tonightAstro!.moon?.rise) })
                InfoRow({ label: '月落', value: this.host.fmtDateTime(this.store.tonightAstro!.moon?.set) })
                Text('今晚可观测目标').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 8 }) {
                    Column({ space: 4 }) {
                      Text('选择类别').fontSize(this.fs(12)).fontColor(this.c.sub).width('100%')
                      Text(this.host.wutCategoryTitle()).fontSize(this.fs(14)).fontColor(this.c.text).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Image(getIcon('chevron_right', false)).width(18).height(18).supportSvg2(true).colorFilter(tintMatrixFor(this.c.sub))
                      .rotate({ angle: this.wutStore.wutCategoriesExpanded ? 90 : 0 })
                  }.width('100%')
                }.width('100%').padding(12).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => {
                    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                      this.wutStore.wutCategoriesExpanded = !this.wutStore.wutCategoriesExpanded
                    })
                  })
                if (this.wutStore.wutCategoriesExpanded) {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(wutCategoryOptions(), (option: TabItem) => {
                      Text(option.label).fontSize(this.fs(12)).width('48%')
                        .fontColor(this.wutStore.wutCategory === wutCategoryKey(option.id) ? this.c.onAccent : this.c.sub)
                        .padding(10).margin({ right: '2%', bottom: 6 })
                        .backgroundColor(this.wutStore.wutCategory === wutCategoryKey(option.id) ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                        .borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => {
                          const category = wutCategoryKey(option.id)
                          this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                            this.wutStore.wutCategoriesExpanded = false
                          })
                          if (this.wutStore.wutCategory !== category) {
                            this.wutStore.wutCategory = category
                            this.wutStore.wutAngularSizeAvailable = !['stars', 'variableStars', 'highProperMotion', 'carbonStars', 'bariumStars'].includes(category)
                            this.host.loadWutTargets()
                          }
                        })
                    }, (option: TabItem) => option.id.toString())
                  }.width('100%').margin({ top: 8 }).transition(TransitionEffect.OPACITY)
                }
                Column({ space: 10 }) {
                    Flex({ wrap: FlexWrap.Wrap }) {
                      Text('观测时段').fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').margin({ bottom: 6 })
                      ForEach(['evening', 'midnight', 'morning', 'night'], (period: string) => {
                        Text(period === 'evening' ? '傍晚' : (period === 'morning' ? '清晨' : (period === 'night' ? '整夜' : '午夜')))
                          .fontSize(this.fs(12)).fontColor(this.wutStore.wutPeriod === period ? this.c.onAccent : this.c.sub)
                          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                          .backgroundColor(this.wutStore.wutPeriod === period ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .id('astro-filter-period-' + period)
                          .onClick(() => { this.host.selectAstroFilter('period', period) })
                      }, (period: string) => period)
                    }.width('100%')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      Text('地平高度高于').fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').margin({ bottom: 6 })
                      ForEach([0, 10, 20, 30, 45], (altitude: number) => {
                        Text(altitude.toString() + '°').fontSize(this.fs(12))
                          .fontColor(this.wutStore.wutMinAltitude === altitude ? this.c.onAccent : this.c.sub)
                          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                          .backgroundColor(this.wutStore.wutMinAltitude === altitude ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .id('astro-filter-altitude-' + altitude.toString())
                          .onClick(() => { this.host.selectAstroFilter('altitude', altitude.toString()) })
                      }, (altitude: number) => altitude.toString())
                    }.width('100%')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      Text('星等不超过').fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').margin({ bottom: 6 })
                      ForEach([4, 6, 8, 10], (magnitude: number) => {
                        Text(magnitude.toString()).fontSize(this.fs(12))
                          .fontColor(this.wutStore.wutMaxMagnitude === magnitude ? this.c.onAccent : this.c.sub)
                          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                          .backgroundColor(this.wutStore.wutMaxMagnitude === magnitude ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .id('astro-filter-magnitude-' + magnitude.toString())
                          .onClick(() => { this.host.selectAstroFilter('magnitude', magnitude.toString()) })
                      }, (magnitude: number) => magnitude.toString())
                    }.width('100%')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      Text('方向').fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').margin({ bottom: 6 })
                      ForEach(['all', 'north', 'east', 'south', 'west'], (direction: string) => {
                        Text(wutDirectionLabel(direction)).fontSize(this.fs(12)).fontColor(this.wutStore.wutDirection === direction ? this.c.onAccent : this.c.sub)
                          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                          .backgroundColor(this.wutStore.wutDirection === direction ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .id('astro-filter-direction-' + direction)
                          .onClick(() => { this.host.selectAstroFilter('direction', direction) })
                      }, (direction: string) => direction)
                    }.width('100%')
                    Row({ space: 8 }) {
                      Text('限制角大小').fontSize(this.fs(12)).fontColor(this.c.sub).layoutWeight(1)
                      Toggle({ type: ToggleType.Switch, isOn: this.wutStore.wutLimitAngularSize }).width(44).height(28)
                        .enabled(this.wutStore.wutAngularSizeAvailable)
                        .onChange((value: boolean) => { this.wutStore.wutLimitAngularSize = value; this.host.loadWutTargets() })
                    }.width('100%')
                    if (this.wutStore.wutLimitAngularSize && this.wutStore.wutAngularSizeAvailable) {
                      Flex({ wrap: FlexWrap.Wrap }) {
                        ForEach(['10角分–1度', '1度–10度'], (label: string, index: number) => {
                          Text(label).fontSize(this.fs(12)).fontColor((index === 0 ? this.wutStore.wutMinAngularSizeArcmin === 10 : this.wutStore.wutMinAngularSizeArcmin === 60) ? this.c.onAccent : this.c.sub)
                            .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                            .backgroundColor((index === 0 ? this.wutStore.wutMinAngularSizeArcmin === 10 : this.wutStore.wutMinAngularSizeArcmin === 60) ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                            .onClick(() => { this.wutStore.wutMinAngularSizeArcmin = index === 0 ? 10 : 60; this.wutStore.wutMaxAngularSizeArcmin = index === 0 ? 60 : 600; this.host.loadWutTargets() })
                        }, (label: string) => label)
                      }.width('100%')
                    }

                }.width('100%').padding(12).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ top: 8, bottom: 12 })
                if (this.wutStore.wutLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.c.accent)
                    Text(this.wutStore.wutProgress.length > 0 ? this.wutStore.wutProgress : '正在筛选可观测目标…').fontSize(this.fs(11)).fontColor(this.c.sub)
                  }.width('100%').padding({ left: 8, top: 5, bottom: 7 })
                }
                if (this.wutStore.wutHint.length > 0) {
                  Text(this.wutStore.wutHint).fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').margin({ bottom: 8 })
                } else {
                  Text('筛选结果 ' + this.wutStore.wutTargets.length.toString() + ' 个 · ' + this.host.fmtClock(this.wutStore.wutObservationTime))
                    .fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').margin({ bottom: 8 })
                }
                Text(I18n.t('wut_card_action_hint')).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').margin({ bottom: 8 })
                ForEach(this.wutStore.wutTargets, (target: WutTarget, index: number) => {
                  WutTargetCard({
                target: target,
                titleOf: (item: WutTarget) => this.host.wutTargetTitle(item), subtitleOf: (item: WutTarget) => this.host.wutTargetSubtitle(item),
                typeOf: (type: string) => zhType(type), numberText: (value: number | undefined, digits: number, unit: string) => this.host.fmtNum(value, digits, unit),
                clockText: (value: string | undefined) => this.host.fmtClock(value), onJump: (item: WutTarget) => { this.host.jumpToWutTarget(item) }
              })
                }, (target: WutTarget, index: number) => (target.englishName ?? index.toString()))
                Text('行星（点击跳到中天时刻）').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                ForEach(this.store.tonightAstro!.planets ?? [], (p: TonightPlanet) => {
                  Column({ space: 1 }) {
                    Row() {
                      Text(p.name ?? '').fontSize(this.fs(11)).fontColor(this.c.text).layoutWeight(1)
                      Text((p.visible === true ? '现在可见' : '在地平线下')).fontSize(this.fs(10))
                        .fontColor((p.visible === true) ? this.c.accent : this.c.sub).width(64)
                      Text((p.magnitude ?? 0).toFixed(1) + ' 等').fontSize(this.fs(10)).fontColor(this.c.sub).width(52)
                    }.width('100%').padding({ left: 8, right: 8 })
                    Text('升 ' + this.host.fmtClock(p.rise)
                      + '  中天 ' + this.host.fmtClock(p.transit)
                      + '  落 ' + this.host.fmtClock(p.set))
                      .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 })
                  }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { if (p.transitJd !== undefined) this.host.jumpToJdSmooth(Number(p.transitJd), (p.name ?? '行星') + '中天') })
                }, (p: TonightPlanet, index: number) => index.toString())
                if ((this.store.tonightAstro!.meteorShowers ?? []).length > 0) {
                  Text('活跃流星雨（点击跳到最佳观测时刻）').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                  ForEach(this.store.tonightAstro!.meteorShowers ?? [], (s: TonightShower) => {
                    Row() {
                      Text(s.name ?? '').fontSize(this.fs(12)).fontColor(this.c.text).layoutWeight(1)
                      Text('每小时约 ' + String(s.zhr ?? '?') + ' 颗').fontSize(this.fs(10)).fontColor(this.c.sub).textAlign(TextAlign.End)
                    }.width('100%').constraintSize({ minHeight: this.ch(34) }).padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { if (s.primeJd !== undefined) this.host.jumpToJdSmooth(Number(s.primeJd), s.name ?? '流星雨') })
                  }, (s: TonightShower, index: number) => index.toString())
                }
              }
              ContinuationSection({
                hint: this.sessionToolStore.sessionHint,
                json: this.sessionToolStore.sessionJson,
                onExport: () => { this.host.sessionExport() },
                onApply: () => { this.host.sessionApply() },
                onHandoff: () => { this.host.sessionHandoff() }
              })
            } else if (this.store.astroTab === 6) {
              Text(I18n.t('i0131')).fontSize(this.fs(13)).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
              Row({ space: 4 }) {
                ForEach(['实时数据', '距离曲线'], (mode: string, index: number) => {
                  Text(mode).fontSize(this.fs(10))
                    .fontColor(this.store.planetCalcMode === index ? this.c.onAccent : this.c.sub)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.store.planetCalcMode === index ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.planetCalcMode !== index) {
                        this.store.planetCalcMode = index
                        if (index === 1) this.host.loadPlanetPairDistance()
                        else this.host.loadPlanetCalc()
                      }
                    })
                }, (mode: string) => mode)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
              if (this.store.planetCalcMode === 0) {
              Row({ space: 6 }) {
                Button(I18n.t('i0243')).fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(30) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadPlanetCalc() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              if (this.store.planetCalcLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(20).height(20).color(this.c.accent)
                  Text('正在计算各行星的实时数据…').fontSize(this.fs(11)).fontColor(this.c.sub)
                }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
              } else if (this.store.planetCalcError.length > 0) {
                Text(this.store.planetCalcError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.store.planetCalcData.length === 0) {
                Text('当前没有可显示的行星实时数据。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              }
              ForEach(this.store.planetCalcData, (p: PlanetCalcItem) => {
                Column({ space: 2 }) {
                  Row() {
                    Text(p.name ?? '').fontSize(this.fs(12)).fontColor(this.c.text).layoutWeight(1)
                    Text((p.magnitude ?? 0).toFixed(1) + ' 等').fontSize(this.fs(10)).fontColor(this.c.sub).width(52)
                  }.width('100%').padding({ left: 8, right: 8 })
                  Text('赤经 ' + String(p.ra ?? '--') + '   赤纬 ' + String(p.dec ?? '--'))
                    .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 })
                  Text('高度 ' + (p.altitude ?? 0).toFixed(1) + '°   方位 ' + (p.azimuth ?? 0).toFixed(1) + '°'
                    + (p.distanceAU !== undefined ? ('   距离 ' + (p.distanceAU ?? 0).toFixed(3) + ' AU') : ''))
                    .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 })
                  if (p.elongation !== undefined) {
                    Text('距角 ' + ((p.elongation ?? 0) * 180 / Math.PI).toFixed(1) + '°'
                      + '   相位 ' + ((p.phase ?? 0) * 100).toFixed(0) + '%')
                      .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 })
                  }
                  if (p.phaseAngleDegrees !== undefined || p.heliocentricDistanceAU !== undefined) {
                    Text((p.phaseAngleDegrees !== undefined ? '相位角 ' + p.phaseAngleDegrees.toFixed(1) + '°' : '')
                      + (p.heliocentricDistanceAU !== undefined ? '   日心距 ' + p.heliocentricDistanceAU.toFixed(3) + ' AU' : ''))
                      .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 })
                  }
                  if (p.illumination !== undefined) {
                    Text('照亮 ' + (p.illumination ?? 0).toFixed(1) + '%   月龄 ' + (p.age ?? 0).toFixed(1) + ' 天')
                      .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 })
                  }
                  if (p.rise !== undefined) {
                    Text('升 ' + this.host.fmtClock(p.rise)
                      + '  中天 ' + this.host.fmtClock(p.transit)
                      + '  落 ' + this.host.fmtClock(p.set))
                      .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 })
                  }
                }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.callNative('searchObject', String(p.englishName ?? '')) })
              }, (p: PlanetCalcItem, index: number) => index.toString())
              } else {
                Text('对应桌面版行星计算器的“图表”：蓝色为线性距离，金色为表观角距离；两轴独立缩放。')
                  .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Text('第一个天体').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Column({ space: 3 }) {
                  ForEach([['Sun', 'Earth', 'Moon', 'Mercury', 'Venus', 'Mars'], ['Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto']], (bodies: Array<string>, row: number) => {
                    Row({ space: 3 }) {
                      ForEach(bodies, (body: string) => {
                        Text(planetPairBodyName(body)).fontSize(this.fs(10))
                          .fontColor(this.store.planetPairFirst === body ? this.c.onAccent : this.c.sub)
                          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                          .backgroundColor(this.store.planetPairFirst === body ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                          .borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => {
                            if (body !== this.store.planetPairSecond) {
                              this.store.planetPairFirst = body
                              this.host.loadPlanetPairDistance()
                            }
                          })
                      }, (body: string) => body)
                    }.width('100%')
                  }, (bodies: Array<string>, row: number) => row.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('第二个天体').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Column({ space: 3 }) {
                  ForEach([['Sun', 'Earth', 'Moon', 'Mercury', 'Venus', 'Mars'], ['Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto']], (bodies: Array<string>, row: number) => {
                    Row({ space: 3 }) {
                      ForEach(bodies, (body: string) => {
                        Text(planetPairBodyName(body)).fontSize(this.fs(10))
                          .fontColor(this.store.planetPairSecond === body ? this.c.textStrong : this.c.sub)
                          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                          .backgroundColor(this.store.planetPairSecond === body ? AstroColors.solarDim : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                          .borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => {
                            if (body !== this.store.planetPairFirst) {
                              this.store.planetPairSecond = body
                              this.host.loadPlanetPairDistance()
                            }
                          })
                      }, (body: string) => body)
                    }.width('100%')
                  }, (bodies: Array<string>, row: number) => row.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('前后范围').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([40, 80, 180], (days: number) => {
                    Text('前后 ' + days.toString() + ' 天').fontSize(this.fs(10))
                      .fontColor(this.store.planetPairDays === days ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.planetPairDays === days ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.planetPairDays !== days) {
                          this.store.planetPairDays = days
                          if (days === 80 && this.store.planetPairStepDays < 2) this.store.planetPairStepDays = 2
                          if (days === 180 && this.store.planetPairStepDays < 4) this.store.planetPairStepDays = 4
                          this.host.loadPlanetPairDistance()
                        }
                      })
                  }, (days: number) => days.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('采样步长').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach(this.store.planetPairDays === 40 ? [1, 2, 4, 7] : (this.store.planetPairDays === 80 ? [2, 4, 7] : [4, 7]), (step: number) => {
                    Text(step.toString() + ' 天').fontSize(this.fs(10))
                      .fontColor(this.store.planetPairStepDays === step ? this.c.onAccent : this.c.sub)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.planetPairStepDays === step ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.planetPairStepDays !== step) {
                          this.store.planetPairStepDays = step
                          this.host.loadPlanetPairDistance()
                        }
                      })
                  }, (step: number) => step.toString())
                  Button('刷新').fontSize(this.fs(10)).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadPlanetPairDistance() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.planetPairDistanceLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.c.accent)
                    Text('正在计算两天体之间的距离变化…').fontSize(this.fs(11)).fontColor(this.c.sub)
                  }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
                } else if (this.store.planetPairDistanceError.length > 0) {
                  Text(this.store.planetPairDistanceError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else if (this.store.planetPairDistanceData.length === 0) {
                  Text('尚未生成距离曲线。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.planetPairFirstName + ' ↔ ' + this.store.planetPairSecondName + ' · 前后 ' + this.store.planetPairDays.toString() + ' 天')
                    .fontSize(this.fs(11)).fontColor(this.c.text).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  Stack({ alignContent: Alignment.Center }) {
                    Row() {
                      ForEach(this.store.planetPairDistanceData, (point: PlanetPairDistancePoint) => {
                        Row({ space: 1 }) {
                          Column().width(this.host.planetPairSegmentWidth())
                            .height(planetPairBarHeight(point.linearDistance, this.store.planetPairLinearMin, this.store.planetPairLinearMax))
                            .backgroundColor(this.c.accent).borderRadius(1)
                          if (this.store.planetPairAngularAvailable) {
                            Column().width(this.host.planetPairSegmentWidth())
                              .height(planetPairBarHeight(point.angularDistance, this.store.planetPairAngularMin, this.store.planetPairAngularMax))
                              .backgroundColor(AstroColors.solar).borderRadius(1)
                          }
                        }.width(this.host.planetPairBarWidth()).height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                      }, (point: PlanetPairDistancePoint, index: number) => index.toString())
                    }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                  }.width('100%').height(96).padding({ left: 6, right: 6 })
                  Row() {
                    Text('-' + this.store.planetPairDays.toString() + '天').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Start)
                    Text('现在').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.Center)
                    Text('+' + this.store.planetPairDays.toString() + '天').fontSize(this.fs(10)).fontColor(this.c.sub).layoutWeight(1).textAlign(TextAlign.End)
                  }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                  Text(this.store.planetPairAngularAvailable ? '蓝色线性距离：' + this.store.planetPairLinearMin.toFixed(3) + ' - ' + this.store.planetPairLinearMax.toFixed(3) + ' AU；金色角距离：' + this.store.planetPairAngularMin.toFixed(1) + ' - ' + this.store.planetPairAngularMax.toFixed(1) + '°' : '蓝色为线性距离；与观测地球比较时，表观角距离不适用。')
                    .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                  InfoRow({ label: '当前线性距离', value: planetPairLinearLabel(this.store.planetPairDistanceData[this.host.planetPairCurrentIndex()].linearDistance) })
                  if (this.store.planetPairAngularAvailable) {
                    InfoRow({ label: '当前角距离', value: (this.store.planetPairDistanceData[this.host.planetPairCurrentIndex()].angularDistance ?? 0).toFixed(1) + '°' })
                  }
                }
              }
            } else if (this.store.astroTab === 7) {
              Row({ space: 6 }) {
                Text(this.store.isEarthObserver() ? I18n.t('i0132') : (this.store.observerPlanetZh + ' · 星食与凌日'))
                  .fontSize(this.fs(14)).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1)
                InfoTipButton({
                  title: '多星体星食与凌日',
                  tip: '在地球计算高精度贝塞尔日食/月食与水金凌日；在月球推算地球食日；在火星、木星、土星等星体推算天然卫星遮日/卫食以及内行星（含地球）凌日。点顶栏星体胶囊可随时切换观测点。'
                })
              }.width('100%').alignItems(VerticalAlign.Center).margin({ top: 4, bottom: 8 })
              Row({ space: 6 }) {
                ForEach(this.store.isEarthObserver() ? ['日月食', '行星凌日'] : ['星食与卫食', '内行星凌日'], (label: string, index: number) => {
                  Text(label).fontSize(this.fs(11.5))
                    .fontWeight(this.store.eclipseMode === index ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(this.store.eclipseMode === index ? this.c.onAccent : this.c.sub)
                    .textAlign(TextAlign.Center)
                    .layoutWeight(1)
                    .constraintSize({ minHeight: this.ch(34) })
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .backgroundColor(this.store.eclipseMode === index ? this.c.accent : Color.Transparent)
                    .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL - 2)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.eclipseMode !== index) {
                        this.store.eclipseMode = index
                        if (index === 0) this.host.loadEclipses()
                        else this.host.loadPlanetaryTransits()
                      }
                    })
                }, (label: string, index: number) => this.store.observerPlanet + ':mode:' + index.toString() + ':' + label)
              }.width('100%').padding(3).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
              if (this.store.eclipseMode === 0) {
              Row({ space: 6 }) {
                Button(this.store.isEarthObserver() ? '计算日月食' : ('计算' + this.store.observerPlanetZh + '星食'))
                  .fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(36) }).padding({ left: 14, right: 14 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.reloadEclipses() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
              Text('预测范围').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              Row({ space: 6 }) {
                ForEach([12, 36, 60], (months: number) => {
                  Text(months === 12 ? '未来 1 年' : '未来 ' + (months / 12).toString() + ' 年').fontSize(this.fs(11))
                    .fontColor(this.store.eclipseMonths === months ? this.c.onAccent : this.c.sub)
                    .padding({ left: 11, right: 11, top: this.pv(6), bottom: this.pv(6) })
                    .backgroundColor(this.store.eclipseMonths === months ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.eclipseMonths !== months) {
                        this.store.eclipseMonths = months
                        this.host.reloadEclipses()
                      }
                    })
                }, (months: number) => months.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
              Text('开始日期').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              Scroll() {
                Row({ space: 6 }) {
                  ForEach([0, 1, 7, 30], (offsetDays: number) => {
                    Text(this.host.eclipseStartOptionLabel(offsetDays)).fontSize(this.fs(11))
                      .fontColor(this.store.eclipseStartOffsetDays === offsetDays ? this.c.onAccent : this.c.sub)
                      .padding({ left: 10, right: 10, top: this.pv(6), bottom: this.pv(6) })
                      .backgroundColor(this.store.eclipseStartOffsetDays === offsetDays ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.eclipseStartOffsetDays !== offsetDays) {
                          this.store.eclipseStartOffsetDays = offsetDays
                          this.host.reloadEclipses()
                        }
                      })
                  }, (offsetDays: number) => offsetDays.toString())
                  Button(this.store.eclipseStartOffsetDays < 0 ? this.host.eclipseStartOptionLabel(-1) : '指定日期').fontSize(this.fs(11))
                    .fontColor(this.store.eclipseStartOffsetDays < 0 ? this.c.onAccent : this.c.sub)
                    .constraintSize({ minHeight: this.ch(34) }).padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .backgroundColor(this.store.eclipseStartOffsetDays < 0 ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.chooseEclipseStartDate() })
                }.padding({ left: 2, right: 2 })
              }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 8 })
              Text('事件类别').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              Row({ space: 6 }) {
                ForEach(this.store.isEarthObserver() ? ['全部', '日食', '月食'] : ['全部', '遮日/凌日', '卫食'], (label: string, index: number) => {
                  Text(label).fontSize(this.fs(11)).fontColor(this.store.eclipseKindFilter === index ? this.c.onAccent : this.c.sub)
                    .padding({ left: 11, right: 11, top: this.pv(6), bottom: this.pv(6) })
                    .backgroundColor(this.store.eclipseKindFilter === index ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.eclipseKindFilter = index })
                }, (label: string, index: number) => this.store.observerPlanet + ':kind:' + index.toString() + ':' + label)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
              Text('食的类型').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              Row({ space: 5 }) {
                ForEach(['全部', '全食', '环食', '偏食', '半影食'], (label: string, index: number) => {
                  Text(label).fontSize(this.fs(10.5)).fontColor(this.store.eclipseTypeFilter === index ? this.c.onAccent : this.c.sub)
                    .padding({ left: 8, right: 8, top: this.pv(5), bottom: this.pv(5) })
                    .backgroundColor(this.store.eclipseTypeFilter === index ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.eclipseTypeFilter = index })
                }, (label: string) => label)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
              if (this.store.eclipseLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.c.accent)
                  Text('正在推算' + this.store.observerPlanetZh + '星食…').fontSize(this.fs(11.5)).fontColor(this.c.sub)
                }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
              } else if (this.store.eclipseError.length > 0) {
                Text(this.store.eclipseError).fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.store.eclipseNote.length > 0 && this.store.eclipseData.length === 0) {
                Text(this.store.eclipseNote).fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%').padding(10).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ top: 6 })
              } else if (this.store.eclipseData.length === 0) {
                Text('点击上方按钮生成星食预测（点任意结果可平滑前往食甚时刻）。').fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.host.filteredEclipses().length === 0) {
                Text('当前筛选条件下没有星食事件。').fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              }
              ForEach(this.host.filteredEclipses(), (e: EclipseItem) => {
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(this.eclipseRowTitle(e))
                      .fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.accent).constraintSize({ minWidth: 60 })
                    Text(this.host.fmtDateTime(e.date)).fontSize(this.fs(11.5)).fontColor(this.c.text).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('食分 ' + (e.magnitude ?? 0).toFixed(2)).fontSize(this.fs(10.5)).fontColor(this.c.sub)
                  }.width('100%')
                  if (e.kind === 'solar' && e.saros !== undefined) {
                    Text('沙罗周期 ' + (e.saros ?? 0).toString() + '   ' + (Math.abs(e.pathWidthKm ?? 0) > 0.1
                      ? '中心路径宽 ' + Math.abs(e.pathWidthKm ?? 0).toFixed(0) + ' 千米' : '非中心食'))
                      .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%').maxLines(1)
                  }
                  if (e.durationMin !== undefined && Math.abs(e.durationMin ?? 0) > 0.001 && e.centralLat !== undefined) {
                    Text('中心食持续 ' + Math.abs(e.durationMin ?? 0).toFixed(1) + ' 分钟   中心点 '
                      + (e.centralLat ?? 0).toFixed(1) + '°, ' + (e.centralLng ?? 0).toFixed(1) + '°   路径偏离 ' + (e.gamma ?? 0).toFixed(3))
                      .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                  } else if (e.durationMin !== undefined && Math.abs(e.durationMin ?? 0) > 0.001) {
                    Text('预计持续约 ' + Math.abs(e.durationMin ?? 0).toFixed(1) + ' 分钟')
                      .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                  }
                  if (e.kind === 'lunar') {
                    if (e.saros !== undefined) {
                      Text('沙罗周期 ' + (e.saros ?? 0).toString() + '   路径偏离 ' + (e.gamma ?? 0).toFixed(3)
                        + '   半影 ' + (e.penumbralMagnitude ?? 0).toFixed(2)
                        + '   本影 ' + (e.umbralMagnitude ?? 0).toFixed(2))
                        .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%').maxLines(1)
                    } else {
                      Text('本影食分 ' + (e.umbralMagnitude ?? 0).toFixed(2) + '   半影食分 ' + (e.penumbralMagnitude ?? 0).toFixed(2))
                        .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                    }
                    Text((e.visibility ?? '本地条件未知') + '   目标高度 ' + (e.localMoonAltitude ?? 0).toFixed(1) + '°')
                      .fontSize(this.fs(10.5)).fontColor(this.c.accent).width('100%')
                  }
                  if (e.kind === 'solar' && e.localVisible === true) {
                    Text('本地食甚 ' + this.host.fmtClock(e.localMax) + '   太阳高度 ' + (e.localSunAltitude ?? 0).toFixed(1) + '°')
                      .fontSize(this.fs(10.5)).fontColor(this.c.accent).width('100%')
                    if (e.localFirstContact !== undefined && e.localLastContact !== undefined) {
                      Text((e.localFirstContactLabel ?? '初亏') + ' ' + this.host.fmtClock(e.localFirstContact)
                        + '   ' + (e.localLastContactLabel ?? '复圆') + ' ' + this.host.fmtClock(e.localLastContact))
                        .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                    }
                    if (e.localCentralType !== undefined) {
                      Text('本地' + e.localCentralType + '：' + this.host.fmtClock(e.localCentralStart)
                        + ' - ' + this.host.fmtClock(e.localCentralEnd))
                        .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                    }
                  } else if (e.kind === 'solar' && e.localVisible === false) {
                    Text('当前地点地平线以下（全球其他经度可见）').fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                  }
                  if (e.note !== undefined && e.note.length > 0) {
                    Text(e.note ?? '').fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                  }
                }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { if (e.jd !== undefined) this.host.jumpToJdSmooth(e.jd, this.eclipseRowTitle(e)) })
              }, (e: EclipseItem, index: number) => (e.jd !== undefined ? e.jd.toFixed(6) : index.toString()) + ':' + (e.occulter ?? ''))
              } else {
                Row({ space: 6 }) {
                  Button('计算' + this.store.observerPlanetZh + '视角凌日').fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                    .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(36) }).padding({ left: 14, right: 14 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      this.store.planetaryTransitData = []
                      this.store.planetaryTransitError = ''
                      this.store.planetaryTransitNote = ''
                      this.store.planetaryTransitLoaded = false
                      this.host.loadPlanetaryTransits()
                    })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
                Text('预测范围').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                Row({ space: 6 }) {
                  ForEach([5, 20, 50], (years: number) => {
                    Text('未来 ' + years.toString() + ' 年').fontSize(this.fs(11))
                      .fontColor(this.store.planetaryTransitYears === years ? this.c.onAccent : this.c.sub)
                      .padding({ left: 11, right: 11, top: this.pv(6), bottom: this.pv(6) })
                      .backgroundColor(this.store.planetaryTransitYears === years ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.planetaryTransitYears !== years) {
                          this.store.planetaryTransitYears = years
                          this.store.planetaryTransitData = []
                          this.store.planetaryTransitError = ''
                          this.store.planetaryTransitNote = ''
                          this.store.planetaryTransitLoaded = false
                          this.host.loadPlanetaryTransits()
                        }
                      })
                  }, (years: number) => years.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
                if (this.store.planetaryTransitLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(22).height(22).color(this.c.accent)
                    Text('正在推算' + this.store.observerPlanetZh + '视角内行星凌日…').fontSize(this.fs(11.5)).fontColor(this.c.sub)
                  }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
                } else if (!this.store.planetaryTransitLoaded) {
                  Text('点击上方按钮推算内行星凌日（如在火星可推算水星、金星与地球凌日）。').fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else if (this.store.planetaryTransitError.length > 0) {
                  Text(this.store.planetaryTransitError).fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else if (this.store.planetaryTransitNote.length > 0 && this.store.planetaryTransitData.length === 0) {
                  Text(this.store.planetaryTransitNote).fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%').padding(10).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ top: 6 })
                } else if (this.store.planetaryTransitData.length === 0) {
                  Text('未来 ' + this.store.planetaryTransitYears.toString() + ' 年内未出现内行星凌日，可扩大至 50 年范围。').fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
                }
                ForEach(this.store.planetaryTransitData, (transit: PlanetaryTransitItem) => {
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text((transit.planet ?? '行星') + '凌日').fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.accent).constraintSize({ minWidth: 64 })
                      Text(this.host.fmtDateTime(transit.date)).fontSize(this.fs(11.5)).fontColor(this.c.text).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text('食分 ' + (transit.magnitude ?? 0).toFixed(3)).fontSize(this.fs(10.5)).fontColor(this.c.sub)
                    }.width('100%')
                    Text('C1 ' + this.host.fmtClock(transit.firstContact) + '   食甚 ' + this.host.fmtClock(transit.middle) + '   C4 ' + this.host.fmtClock(transit.lastContact))
                      .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%').maxLines(2)
                    Text('最小距日中心 ' + (transit.minimumSeparation ?? 0).toFixed(3) + '°   全程 ' + (transit.durationMin ?? 0).toFixed(1) + ' 分钟')
                      .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                    if (transit.localVisible === true) {
                      Text('本地可见 ' + (transit.observableDurationMin ?? 0).toFixed(1) + ' 分钟   食甚太阳高度 ' + (transit.sunAltitude ?? 0).toFixed(1) + '°')
                        .fontSize(this.fs(10.5)).fontColor(this.c.accent).width('100%')
                    } else {
                      Text('当前地点不可见（食甚太阳高度 ' + (transit.sunAltitude ?? 0).toFixed(1) + '°）')
                        .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                    }
                  }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { if (transit.jd !== undefined) this.host.jumpToJdSmooth(transit.jd, (transit.planet ?? '行星') + '凌日') })
                }, (transit: PlanetaryTransitItem, index: number) => transit.jd !== undefined ? transit.jd.toFixed(6) : index.toString())
              }
            } else if (this.store.astroTab === 8) {
              Row({ space: 6 }) {
                Text(this.store.isEarthObserver() ? I18n.t('i0133') : (this.store.observerPlanetZh + '年历与太阳日'))
                  .fontSize(this.fs(14)).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1)
                Button('世界多历法 →')
                  .id('astro-open-calendars-btn')
                  .fontSize(this.fs(11))
                  .fontColor(this.c.accent)
                  .backgroundColor(this.c.softStrong)
                  .borderRadius(UI_RADIUS_PILL)
                  .constraintSize({ minHeight: this.ch(32) })
                  .padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.openCalendarsPanel() })
              }.width('100%').alignItems(VerticalAlign.Center).margin({ top: 4, bottom: 8 })
              Row({ space: 8 }) {
                Button(I18n.t('i0240')).fontSize(this.fs(11.5)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_PILL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 12, right: 12 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadAlmanac() })
                if (!this.store.isEarthObserver()) {
                  Text('太阳日约 ' + this.store.almanacSolarDayHours.toFixed(1) + ' 小时 · 已隐藏地球节气')
                    .fontSize(this.fs(10.5)).fontColor(this.c.sub).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.width('100%').alignItems(VerticalAlign.Center).margin({ bottom: 6 })
              if (this.store.almanacLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(20).height(20).color(this.c.accent)
                  Text('正在计算年历…').fontSize(this.fs(11)).fontColor(this.c.sub)
                }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
              } else if (this.store.almanacError.length > 0) {
                Text(this.store.almanacError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else if (this.store.almanacData.size === 0) {
                Text('尚未生成年历。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else if (this.store.almanacData.size > 0) {
                if (this.store.almanacSeasons.length > 0) {
                  Text(this.store.isEarthObserver()
                    ? ((this.store.almanacSeasonYear.length > 0 ? this.store.almanacSeasonYear + ' 年' : '本年') + '四季节点')
                    : (this.store.observerPlanetZh + '四季节点（按日心黄经 Ls 推算）'))
                    .fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                  ForEach(this.store.almanacSeasons, (event: SeasonEvent) => {
                    Row({ space: 6 }) {
                      Text(event.label ?? '').fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.accent).constraintSize({ minWidth: 44 })
                      Text(this.host.fmtDateTime(event.date)).fontSize(this.fs(11)).fontColor(this.c.text).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text('持续 ' + (event.durationDays ?? 0).toFixed(1) + ' 天').fontSize(this.fs(10)).fontColor(this.c.sub).textAlign(TextAlign.End)
                    }.width('100%').constraintSize({ minHeight: this.ch(34) }).padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.jumpToAlmanacSeason(event) })
                  }, (event: SeasonEvent, index: number) => (event.jd ?? index).toString())
                  Row()
                    .width('100%').height(0.5)
                    .backgroundColor(this.c.border)
                    .margin({ top: 4, bottom: 4 })
                }
                if (this.store.almanacSolarTerms.length > 0) {
                  Text('二十四节气').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  ForEach(this.store.almanacSolarTerms, (term: SeasonEvent) => {
                    Row({ space: 6 }) {
                      Text(term.label ?? '').fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.accent).constraintSize({ minWidth: 50 })
                      Text(this.host.fmtDateTime(term.date)).fontSize(this.fs(11)).fontColor(this.c.text).layoutWeight(1)
                    }.width('100%').constraintSize({ minHeight: this.ch(34) }).padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.jumpToAlmanacSeason(term) })
                  }, (term: SeasonEvent, index: number) => (term.key ?? (term.jd ?? index)).toString())
                  Row()
                    .width('100%').height(0.5)
                    .backgroundColor(this.c.border)
                    .margin({ top: 4, bottom: 4 })
                }
                Text(I18n.t('s0372')).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                SolarPathDiagramView({
                  sunRiseText: this.host.jdToDateStr(this.store.almanacData.get('sunRise') ?? '0'),
                  sunTransitText: this.host.jdToDateStr(this.store.almanacData.get('sunTransit') ?? '0'),
                  sunSetText: this.host.jdToDateStr(this.store.almanacData.get('sunSet') ?? '0'),
                  astroEndText: this.host.jdToDateStr(this.store.almanacData.get('astronomicalSet') ?? '0'),
                  astroStartText: this.host.jdToDateStr(this.store.almanacData.get('astronomicalRise') ?? '0'),
                  daylightLabel: this.host.almanacHoursLabel('daylightHours'),
                  nightMode: String(this.c.accent) === '#F00000'
                })
                InfoRow({ label: I18n.t('s0365'), value: this.host.jdToDateStr(this.store.almanacData.get('sunRise') ?? '0') })
                InfoRow({ label: I18n.t('s0366'), value: this.host.jdToDateStr(this.store.almanacData.get('sunSet') ?? '0') })
                InfoRow({ label: I18n.t('s0701'), value: this.host.jdToDateStr(this.store.almanacData.get('sunTransit') ?? '0') })
                InfoRow({ label: '昼长', value: this.host.almanacHoursLabel('daylightHours') })
                InfoRow({ label: '夜长', value: this.host.almanacHoursLabel('nightHours') })
                Text('晨昏蒙影').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                InfoRow({ label: '民用晨光', value: this.host.jdToDateStr(this.store.almanacData.get('civilRise') ?? '0') })
                InfoRow({ label: '民用昏影', value: this.host.jdToDateStr(this.store.almanacData.get('civilSet') ?? '0') })
                InfoRow({ label: '航海晨光', value: this.host.jdToDateStr(this.store.almanacData.get('nauticalRise') ?? '0') })
                InfoRow({ label: '航海昏影', value: this.host.jdToDateStr(this.store.almanacData.get('nauticalSet') ?? '0') })
                InfoRow({ label: '天文晨光', value: this.host.jdToDateStr(this.store.almanacData.get('astronomicalRise') ?? '0') })
                InfoRow({ label: '天文昏影', value: this.host.jdToDateStr(this.store.almanacData.get('astronomicalSet') ?? '0') })
                Row()
                  .width('100%').height(0.5)
                  .backgroundColor(this.c.border)
                  .margin({ top: 4, bottom: 4 })
                Text(this.store.isEarthObserver() ? I18n.t('s0373') : (this.store.almanacCompanionNameZh + '升落与相位'))
                  .fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                InfoRow({ label: this.store.isEarthObserver() ? I18n.t('s0367') : (this.store.almanacCompanionNameZh + '升起'), value: this.host.jdToDateStr(this.store.almanacData.get('moonRise') ?? '0') })
                InfoRow({ label: this.store.isEarthObserver() ? I18n.t('s0368') : (this.store.almanacCompanionNameZh + '落下'), value: this.host.jdToDateStr(this.store.almanacData.get('moonSet') ?? '0') })
                InfoRow({ label: I18n.t('s0701'), value: this.host.jdToDateStr(this.store.almanacData.get('moonTransit') ?? '0') })
                InfoRow({ label: this.store.isEarthObserver() ? I18n.t('s0369') : '被照面比例', value: parseFloat(this.store.almanacData.get('moonPhase') ?? '0').toFixed(1) + '%' })
              }
            } else {
              Text('月相预报').fontSize(this.fs(13)).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 2 })
              Text('按月球相对太阳的地心黄经差计算新月、上弦、满月和下弦。').fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              Row({ space: 6 }) {
                ForEach([30, 90], (days: number) => {
                  Text('未来 ' + days.toString() + ' 天').fontSize(this.fs(10))
                    .fontColor(this.store.moonPhaseDays === days ? this.c.onAccent : this.c.sub)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.moonPhaseDays === days ? this.c.accent : this.c.bg).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.moonPhaseDays !== days) {
                        this.store.moonPhaseDays = days
                        this.host.loadMoonPhases()
                      }
                    })
                }, (days: number) => days.toString())
                Button('刷新月相').fontSize(this.fs(11)).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(34) }).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadMoonPhases() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.store.moonPhaseLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.c.accent)
                  Text('正在计算月相…').fontSize(this.fs(11)).fontColor(this.c.sub)
                }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
              } else if (this.store.moonPhaseError.length > 0) {
                Text(this.store.moonPhaseError).fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.store.moonPhaseData.length === 0) {
                Text('点击“刷新月相”生成预报。').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 8 }).margin({ top: 6 })
              }
              ForEach(this.store.moonPhaseData, (item: MoonPhaseItem) => {
                Column({ space: 2 }) {
                  Row() {
                    Text(item.phase ?? '').fontSize(this.fs(11)).fontColor(this.c.accent).width(56)
                    Text(this.host.fmtDateTime(item.date)).fontSize(this.fs(11)).fontColor(this.c.text).layoutWeight(1)
                    Text('照亮 ' + (item.illumination ?? 0).toFixed(0) + '%').fontSize(this.fs(10)).fontColor(this.c.sub).width(70)
                  }.width('100%').padding({ left: 8, right: 8 })
                  Text('高度 ' + (item.altitude ?? 0).toFixed(1) + '°   方位 ' + (item.azimuth ?? 0).toFixed(1) + '°')
                    .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 })
                  Text('升 ' + this.host.fmtClock(item.rise) + '  中天 ' + this.host.fmtClock(item.transit) + '  落 ' + this.host.fmtClock(item.set))
                    .fontSize(this.fs(10)).fontColor(this.c.sub).width('100%').padding({ left: 12 })
                }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.jumpToMoonPhase(item) })
              }, (item: MoonPhaseItem, index: number) => (item.jd ?? index).toString())
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').align(Alignment.TopStart).scrollable(ScrollDirection.None).scrollBar(BarState.Off)
          .id('astro-content').opacity(this.store.astroContentOpacity).translate({ x: this.store.astroContentOffsetX })
          .onScroll(() => {
            this.host.publishAstroPanelState()
            this.host.onScrollY(this.scroller.currentOffset().yOffset)
          })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
