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
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL, UI_OPTION_ANIMATION_MS } from '../../common/ui/UiTokens'
import { AstroStore } from '../../state/AstroStore'
import { WutStore } from '../../state/WutStore'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { InfoRow } from '../../common/ui/InfoRow'
import { AstroSelectionGuide, PhenomenonRelationMark } from './AstroGuides'
import { RtsSelectionGuide, GraphSelectionGuide } from './GraphGuides'
import { GraphLoadingRow } from '../../common/ui/GraphLoadingRow'
import { WutTargetCard } from './WutTargetCard'
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
  altitudeCurveColor: (altitude: number | undefined, color: string) => string
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
  selectAstroFilter: (key: string, value: string) => void
  selectAstroGroup: (group: number) => void
  selectAstroTab: (tab: number) => void
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
    selectAstroFilter: () => {},
    selectAstroGroup: () => {},
    selectAstroTab: () => {},
    wutCategoryTitle: () => '',
    wutTargetSubtitle: () => '',
    wutTargetTitle: () => ''
  }
}

@Component
export struct AstroPanel {
  @ObjectLink store: AstroStore
  @ObjectLink wutStore: WutStore
  @ObjectLink objectDetailStore: ObjectDetailStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  @Prop accentColor: string
  @Prop lineColor: string
  scroller: Scroller = new Scroller()
  host: AstroPanelHost = noopAstroPanelHost()

  build() {
    Column({ space: 0 }) {
        // 天文计算窗口
        Scroll() {
          Row({ space: 4 }) {
          ForEach(astroGroupItems(), (tab: TabItem) => {
            Text(tab.label)
              .fontSize(10)
              .fontColor(this.store.astroGroup === tab.id ? this.textColor : this.subColor)
              .fontWeight(this.store.astroGroup === tab.id ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(this.store.astroGroup === tab.id ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
              .borderRadius(UI_RADIUS_CONTROL)

              .id('astro-group-' + tab.id.toString()).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
              .onClick(() => { this.host.selectAstroGroup(tab.id) })
          }, (tab: TabItem) => tab.id.toString())
          }.padding({ left: 2, right: 2 })
        }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .margin({ top: 4, bottom: 3 })
        Scroll() {
          Row({ space: 4 }) {
            ForEach(astroTabItemsForGroup(this.store.astroGroup), (tab: TabItem) => {
              Text(tab.label)
                .fontSize(10)
                .fontColor(this.store.astroTab === tab.id ? this.textColor : this.subColor)
                .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                .backgroundColor(this.store.astroTab === tab.id ? 'rgba(91,147,191,0.20)' : 'rgba(255,255,255,0.035)').animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                .border({ width: { bottom: 2 }, color: this.store.astroTab === tab.id ? this.accentColor : Color.Transparent })
                .borderRadius(UI_RADIUS_CONTROL)

                .id('astro-tab-' + tab.id.toString()).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.selectAstroTab(tab.id) })
            }, (tab: TabItem) => tab.id.toString())
          }.padding({ left: 2, right: 2 })
        }.width('100%').height(31).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .margin({ bottom: 6 })
        Row({ space: 8 }) {
          Button(this.store.astroExporting ? '正在保存…' : '导出当前数据')
            .fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
            .enabled(!this.store.astroExporting)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
            .onClick(() => { this.host.exportCurrentAstroCsv() })
          if (this.store.astroExporting) {
            LoadingProgress().width(16).height(16).color(this.accentColor)
          }
          Text('CSV').fontSize(10).fontColor(this.subColor)
        }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 }).alignItems(VerticalAlign.Center)
        if (this.store.astroContext !== undefined) {
          Column({ space: 2 }) {
            Row({ space: 6 }) {
              Text(this.store.astroContext.observerLocation !== undefined && this.store.astroContext.observerLocation.length > 0 ? this.store.astroContext.observerLocation : '当前观测位置')
                .fontSize(10).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.store.astroContext.offline === true ? '离线计算' : '本地计算').fontSize(10).fontColor(this.accentColor)
            }.width('100%')
            Text('时间 ' + this.host.fmtDateTime(this.store.astroContext.localTime) + ' · 时区 ' + (this.store.astroContext.timeZone ?? '--'))
              .fontSize(10).fontColor(this.subColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('平恒星时 ' + (this.store.astroContext.meanSiderealTime ?? '--') + ' · 视恒星时 ' + (this.store.astroContext.apparentSiderealTime ?? '--') + ' · 时间方程 ' + this.host.fmtNum(this.store.astroContext.equationOfTimeMinutes, 2, ' 分钟'))
              .fontSize(10).fontColor(this.subColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('太阳 ' + this.host.fmtNum(this.store.astroContext.sunAltitude, 1, '°') + ' / ' + this.host.fmtNum(this.store.astroContext.sunAzimuth, 1, '°')
              + ' · 月亮 ' + this.host.fmtNum(this.store.astroContext.moonAltitude, 1, '°') + ' / ' + this.host.fmtNum(this.store.astroContext.moonAzimuth, 1, '°')
              + ' · 月面 ' + this.host.fmtNum(this.store.astroContext.moonIllumination, 1, '%'))
              .fontSize(10).fontColor(this.subColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.store.astroCalcSnapshot.length > 0) {
              Text('参数快照 · ' + this.store.astroCalcSnapshot)
                .fontSize(10).fontColor('#A8FFFFFF').width('100%').maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .backgroundColor('rgba(255, 255, 255, 0.035)').borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
        }
        AstroSelectionGuide({ visible: this.host.astroNeedsSelectedObject() && !this.host.hasSelectedObject(), textColor: this.textColor, subColor: this.subColor, accentColor: this.accentColor, onOpenPicker: () => { this.host.openAstroTargetPicker() } })
        Scroll(this.scroller) {
          Column({ space: 0 }) {
            if (this.store.astroTab === 0) {
              Text(I18n.t('i0125')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 8 })
              Row({ space: 4 }) {
                ForEach(['地平位置', '日心黄道', '目录天体'], (mode: string, index: number) => {
                  Text(mode).fontSize(10)
                    .fontColor(this.store.positionMode === index ? this.textColor : this.subColor)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.store.positionMode === index ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Button(I18n.t('i0241')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadPlanetPositions() })
                Column({ space: 1 }) {
                  Row() {
                    Text(I18n.t('s0374')).fontSize(10).fontColor(this.subColor).width(60)
                    Text(I18n.t('s0375')).fontSize(10).fontColor(this.subColor).width(50)
                    Text(I18n.t('s0376')).fontSize(10).fontColor(this.subColor).width(50)
                    Text(I18n.t('s0377')).fontSize(10).fontColor(this.subColor).width(40)
                  }.width('100%')
                  Text('赤经/赤纬（当日） · 距离 · 视直径 · 中天').fontSize(10).fontColor(this.subColor).width('100%')
                }.width('100%').padding({ left: 8, right: 8 }).margin({ top: 4, bottom: 2 })
                if (this.store.planetPositionsLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.accentColor)
                    Text('正在计算行星位置…').fontSize(11).fontColor(this.subColor)
                  }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
                } else if (this.store.planetPositionsError.length > 0) {
                  Text(this.store.planetPositionsError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
                } else if (this.store.planetPositions.length === 0) {
                  Text('当前没有可显示的行星位置。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
                }
                Scroll() {
                  Column({ space: 2 }) {
                    ForEach(this.store.planetPositions, (p: PlanetPosition) => {
                      Column({ space: 1 }) {
                        Row() {
                          Text(planetZh(p.name)).fontSize(11).fontColor(this.textColor).width(60)
                          Text(p.altitude.toFixed(1) + '°').fontSize(10).fontColor(this.subColor).width(50)
                          Text(p.azimuth.toFixed(1) + '°').fontSize(10).fontColor(this.subColor).width(50)
                          Text(p.magnitude.toFixed(1)).fontSize(10).fontColor(this.subColor).width(40)
                        }.width('100%')
                        Text((p.rightAscension ?? '--') + ' / ' + (p.declination ?? '--')
                          + ' · ' + (p.distanceAU !== undefined ? p.distanceAU.toFixed(3) + ' AU' : '--')
                          + ' · 中天 ' + (p.transit !== undefined ? this.host.fmtDateTime(p.transit) : '--'))
                          .fontSize(10).fontColor(this.subColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      }.height(40).width('100%').padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .backgroundColor(this.panelColor)
                      .borderRadius(UI_RADIUS_CONTROL)
                    }, (p: PlanetPosition, index: number) => p.name)
                  }
                }
                .width('100%').height(220).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
              } else if (this.store.positionMode === 1) {
                Text('以太阳为中心显示实时日心位置；每条细椭圆对应一颗行星的轨道。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 5 })
                Row({ space: 8 }) {
                  Text('已选小天体').fontSize(10).fontColor(this.textColor).layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.store.hecIncludeSelectedMinor })
                    .width(38).height(22)
                    .onChange((value: boolean) => { this.store.hecIncludeSelectedMinor = value; this.host.loadHeliocentricPositions() })
                }.width('100%').height(30).padding({ left: 4, right: 4 })
                Row({ space: 8 }) {
                  Text('显示明亮彗星').fontSize(10).fontColor(this.textColor).layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.store.hecIncludeBrightComets })
                    .width(38).height(22)
                    .onChange((value: boolean) => { this.store.hecIncludeBrightComets = value; this.host.loadHeliocentricPositions() })
                }.width('100%').height(30).padding({ left: 4, right: 4 })
                if (this.store.hecIncludeBrightComets) {
                  Row({ space: 4 }) {
                    Text('彗星星等上限').fontSize(10).fontColor(this.subColor).width(76)
                    ForEach([6, 9, 12], (limit: number) => {
                      Text(limit.toString()).fontSize(10)
                        .fontColor(this.store.hecCometMagnitudeLimit === limit ? this.textColor : this.subColor)
                        .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                        .backgroundColor(this.store.hecCometMagnitudeLimit === limit ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                        .borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => { this.store.hecCometMagnitudeLimit = limit; this.host.loadHeliocentricPositions() })
                    }, (limit: number) => limit.toString())
                  }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 5 })
                }
                Row({ space: 8 }) {
                  Button('刷新坐标').fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                    .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadHeliocentricPositions() })
                  Text(this.store.hecTime.length > 0 ? this.host.fmtDateTime(this.store.hecTime) : '正在计算…').fontSize(10).fontColor(this.subColor).layoutWeight(1)
                }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 5 })
                if (this.store.hecPositionsLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.accentColor)
                    Text('正在计算日心黄道位置…').fontSize(11).fontColor(this.subColor)
                  }.width('100%').padding({ left: 8 }).margin({ top: 4, bottom: 6 })
                } else if (this.store.hecPositionsError.length > 0) {
                  Text(this.store.hecPositionsError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 4, bottom: 6 })
                } else if (this.store.hecPositions.length === 0) {
                  Text('当前没有可显示的日心位置。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 4, bottom: 6 })
                }
                Stack({ alignContent: Alignment.Center }) {
                  ForEach(HELIOCENTRIC_PLANET_ORBITS, (orbit: HeliocentricOrbit) => {
                    Circle()
                      .width(orbit.visualRadius * 2)
                      .height(orbit.visualRadius * 0.86 * 2)
                      .fill('transparent')
                      .stroke(orbit.color)
                      .strokeWidth(0.65)
                      .opacity(0.48)
                  }, (orbit: HeliocentricOrbit) => orbit.name)
                  Circle().width(34).height(34).fill('#F4C454').opacity(0.12)
                  Circle().width(22).height(22).fill('#F4C454')
                  Text('太阳').fontSize(10).fontColor('#30240D')
                  ForEach(this.store.hecPositions, (position: HeliocentricPosition) => {
                    Circle().width(hecPointSize(position) + 4).height(hecPointSize(position) + 4).fill(this.panelColor)
                      .position({ x: this.host.hecPointLeft(position) - 2, y: this.host.hecPointTop(position) - 2 })
                    Circle().width(hecPointSize(position)).height(hecPointSize(position)).fill(this.host.hecPointColor(position))
                      .position({ x: this.host.hecPointLeft(position), y: this.host.hecPointTop(position) })
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.host.searchObject(position.englishName) })
                  }, (position: HeliocentricPosition) => position.englishName)
                }.width(292).height(292).margin({ top: 2, bottom: 7 }).backgroundColor(this.panelColor).border({ width: 1, color: this.lineColor }).borderRadius(UI_RADIUS_CONTROL)
                Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
                  ForEach(HELIOCENTRIC_PLANET_ORBITS, (orbit: HeliocentricOrbit) => {
                    Row({ space: 4 }) {
                      Circle().width(6).height(6).fill(orbit.color)
                      Text(orbit.name).fontSize(10).fontColor(this.subColor)
                    }.margin({ right: 9, bottom: 4 })
                  }, (orbit: HeliocentricOrbit) => orbit.name)
                }.width(292).margin({ bottom: 5 })
                Row() {
                  Text('天体').fontSize(10).fontColor(this.subColor).width(70)
                  Text('黄纬').fontSize(10).fontColor(this.subColor).width(47)
                  Text('黄经').fontSize(10).fontColor(this.subColor).width(47)
                  Text('距日').fontSize(10).fontColor(this.subColor).layoutWeight(1)
                }.height(20).width('100%').padding({ left: 8, right: 8 })
                Scroll() {
                  Column({ space: 2 }) {
                    ForEach(this.store.hecPositions, (position: HeliocentricPosition) => {
                      Row() {
                        Text(this.host.hecTitle(position)).fontSize(11).fontColor(this.textColor).width(70).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(position.latitude.toFixed(1) + '°').fontSize(10).fontColor(this.subColor).width(47)
                        Text(position.longitude.toFixed(1) + '°').fontSize(10).fontColor(this.subColor).width(47)
                        Text(hecDistanceLabel(position) + ' AU').fontSize(10).fontColor(this.subColor).layoutWeight(1).maxLines(1)
                      }
                      .height(28).width('100%').padding({ left: 8, right: 8 })
                      .backgroundColor(this.panelColor)
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.host.searchObject(position.englishName) })
                    }, (position: HeliocentricPosition) => position.englishName)
                  }
                }
                .width('100%').height(220).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
              } else {
                Text('列出当前地平线以上、满足星等条件的目录天体；按高度由高到低排列。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 5 })
                Scroll() {
                  Row({ space: 4 }) {
                    ForEach(CELESTIAL_POSITION_CATEGORIES, (category: CelestialPositionCategory) => {
                      Text(category.label).fontSize(10)
                        .fontColor(this.store.celestialPositionCategory === category.id ? this.textColor : this.subColor)
                        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                        .backgroundColor(this.store.celestialPositionCategory === category.id ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                        .borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => { this.store.celestialPositionCategory = category.id; this.host.loadCelestialPositions() })
                    }, (category: CelestialPositionCategory) => category.id)
                  }.padding({ left: 2, right: 2 })
                }.width('100%').height(31).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
                Row({ space: 4 }) {
                  Text('星等上限').fontSize(10).fontColor(this.subColor).width(56)
                  ForEach([3, 6, 9, 12], (magnitude: number) => {
                    Text(magnitude.toString()).fontSize(10)
                      .fontColor(this.store.celestialPositionMagnitude === magnitude ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.celestialPositionMagnitude === magnitude ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.celestialPositionMagnitude = magnitude; this.host.loadCelestialPositions() })
                  }, (magnitude: number) => magnitude.toString())
                }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
                Row({ space: 8 }) {
                  Text('使用地平坐标').fontSize(10).fontColor(this.textColor).layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.store.celestialPositionHorizontal })
                    .width(38).height(22)
                    .onChange((value: boolean) => { this.store.celestialPositionHorizontal = value; this.host.loadCelestialPositions() })
                  Button('刷新').fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                    .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadCelestialPositions() })
                }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 5 })
                Text(this.store.celestialPositionTime.length > 0 ? this.host.fmtDateTime(this.store.celestialPositionTime) : '正在计算…').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 4 }).margin({ bottom: 4 })
                if (this.store.celestialPositionsLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.accentColor)
                    Text('正在计算目录天体位置…').fontSize(11).fontColor(this.subColor)
                  }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
                } else if (this.store.celestialPositionsError.length > 0) {
                  Text(this.store.celestialPositionsError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8 })
                } else if (this.store.celestialPositions.length === 0) {
                  Text('当前筛选条件下没有地平线以上的天体。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8 })
                } else {
                  Scroll() {
                    Column({ space: 2 }) {
                      ForEach(this.store.celestialPositions, (position: CelestialPosition) => {
                        Column({ space: 1 }) {
                          Row() {
                            Text(this.host.celestialPositionTitle(position)).fontSize(11).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                            Text('星等 ' + position.magnitude.toFixed(1)).fontSize(10).fontColor(this.subColor).width(60).textAlign(TextAlign.End)
                          }.width('100%')
                          if (this.host.celestialPositionSubtitle(position).length > 0) {
                            Text(this.host.celestialPositionSubtitle(position)).fontSize(10).fontColor(this.subColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                          }
                          Text((this.store.celestialPositionHorizontal ? '方位 ' : '赤经 ') + position.firstCoordinate + '   ' + (this.store.celestialPositionHorizontal ? '高度 ' : '赤纬 ') + position.secondCoordinate)
                            .fontSize(10).fontColor('#B8FFFFFF').width('100%').maxLines(1)
                          Text('地平高度 ' + position.altitude.toFixed(1) + '°   距日 ' + (position.elongation ?? 0).toFixed(1) + '°')
                            .fontSize(10).fontColor('#88FFFFFF').width('100%').maxLines(1)
                          Text('视直径 ' + (position.angularSizeArcmin !== undefined ? position.angularSizeArcmin.toFixed(2) + '′' : '--')
                            + (position.distanceAU !== undefined ? '   距离 ' + position.distanceAU.toFixed(3) + ' AU' : '')
                            + (position.transit !== undefined ? '   中天 ' + this.host.fmtClock(position.transit) : ''))
                            .fontSize(10).fontColor('#70FFFFFF').width('100%').maxLines(1)
                        }
                        .width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
                        .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => { this.host.searchObject(position.englishName) })
                      }, (position: CelestialPosition) => position.englishName + position.catalogId)
                    }
                  }.width('100%').height(310).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
                }
              }
            } else if (this.store.astroTab === 1) {
              Text(I18n.t('i0126')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 8 })
              Text('计算对象').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach(['当前选中天体', '两个天体', '全部肉眼行星'], (label: string, mode: number) => {
                  Text(label).fontSize(10)
                    .fontColor(this.store.ephemerisMode === mode ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                    .backgroundColor(this.store.ephemerisMode === mode ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.ephemerisMode = mode })
                }, (label: string) => label)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
              if (this.store.ephemerisMode === 0) {
                Row({ space: 8 }) {
                  Column({ space: 1 }) {
                    Text('星历目标').fontSize(10).fontColor(this.subColor)
                    Text(this.objectDetailStore.selectedName.length > 0 ? zhNameOf(this.objectDetailStore.selectedName) : '尚未选择天体')
                      .fontSize(11).fontColor(this.objectDetailStore.selectedName.length > 0 ? this.textColor : this.subColor)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Button(this.objectDetailStore.selectedName.length > 0 ? '更换天体' : '选择天体')
                    .fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                    .borderRadius(UI_RADIUS_PILL).height(28).padding({ left: 10, right: 10 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.openEphemerisTargetPicker() })
                }.width('100%').padding({ left: 4, right: 4, top: 4, bottom: 5 })
                  .backgroundColor('rgba(255, 255, 255, 0.035)').borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 5 })
              }
              if (this.store.ephemerisMode === 1) {
                Text('第一个天体').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Scroll() {
                  Row({ space: 4 }) {
                    ForEach(['Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                      Text(planetPairBodyName(body)).fontSize(10)
                        .fontColor(this.store.ephemerisPrimary === body ? this.textColor : this.subColor)
                        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                        .backgroundColor(this.store.ephemerisPrimary === body ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                        .onClick(() => {
                          this.store.ephemerisPrimary = body
                          if (this.store.ephemerisSecondary === body) this.store.ephemerisSecondary = 'Sun'
                        })
                    }, (body: string) => body)
                  }.padding({ left: 2, right: 2 })
                }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 4 })
                Text('第二个天体').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Scroll() {
                  Row({ space: 4 }) {
                    ForEach(['Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                      if (body !== this.store.ephemerisPrimary) {
                        Text(planetPairBodyName(body)).fontSize(10)
                          .fontColor(this.store.ephemerisSecondary === body ? this.textColor : this.subColor)
                          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                          .backgroundColor(this.store.ephemerisSecondary === body ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => { this.store.ephemerisSecondary = body })
                      }
                    }, (body: string) => body)
                  }.padding({ left: 2, right: 2 })
                }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
              }
              Text('时间范围').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([7, 14, 31], (days: number) => {
                  Text(days.toString() + ' 天')
                    .fontSize(10)
                    .fontColor(this.store.ephemerisDays === days ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.ephemerisDays === days ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
              Text('开始日期').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([0, 1, 7, 30], (offsetDays: number) => {
                  Text(this.host.ephemerisStartOptionLabel(offsetDays)).fontSize(10)
                    .fontColor(this.store.ephemerisStartOffsetDays === offsetDays ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.ephemerisStartOffsetDays === offsetDays ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.ephemerisStartOffsetDays !== offsetDays) {
                        this.store.ephemerisStartOffsetDays = offsetDays
                        this.host.loadEphemeris()
                      }
                    })
                }, (offsetDays: number) => offsetDays.toString())
                Button(this.store.ephemerisStartOffsetDays < 0 ? this.host.ephemerisStartOptionLabel(-1) : '指定日期').fontSize(10)
                  .fontColor(this.store.ephemerisStartOffsetDays < 0 ? this.textColor : this.subColor)
                  .height(26).padding({ left: 9, right: 9 })
                  .backgroundColor(this.store.ephemerisStartOffsetDays < 0 ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.chooseEphemerisStartDate() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('采样间隔').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([1, 3, 6, 12, 24], (hours: number) => {
                  Text(hours.toString() + ' 小时')
                    .fontSize(10)
                    .fontColor(this.store.ephemerisStepHours === hours ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.ephemerisStepHours === hours ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Button('刷新星历').fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadEphemeris() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              Text(this.store.ephemerisMode === 0 ? '选择天体后将自动生成星历；点任一行可跳到对应时刻。' : (this.store.ephemerisMode === 1 ? '两个天体共用同一时间轴，便于直接比较位置和星等。' : '肉眼行星模式在地球上显示水星、金星、火星、木星和土星。')).fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              if (this.store.ephemerisLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.accentColor)
                  Text('正在生成星历…').fontSize(11).fontColor(this.subColor)
                }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
              } else if (this.store.ephemerisError.length > 0) {
                Text(this.store.ephemerisError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else if (this.store.ephemerisData.length === 0) {
                Text('尚未生成星历。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else {
                Text(this.store.ephemerisName + ' · 从' + this.host.ephemerisStartOptionLabel(this.store.ephemerisStartOffsetDays) + '开始，持续 ' + this.store.ephemerisDays.toString() + ' 天（每 ' + this.store.ephemerisStepHours.toString() + ' 小时）').fontSize(11).fontColor(this.textColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                if (this.store.ephemerisMeta.length > 0) {
                  Text(this.store.ephemerisMeta).fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                }
              }
              ForEach(this.store.ephemerisData, (row: EphemerisRow) => {
                Column({ space: 1 }) {
                  Row({ space: 8 }) {
                    Text(this.host.fmtEphemerisDate(row.date)).fontSize(10).fontColor(this.textColor).width(96)
                    Text((row.bodyName !== undefined ? row.bodyName + '  ' : '') + '赤经 ' + (row.ra ?? '--')).fontSize(10).fontColor(this.subColor).layoutWeight(1).maxLines(1)
                  }.width('100%')
                  Text('赤纬 ' + (row.dec ?? '--')).fontSize(10).fontColor('#B8FFFFFF').width('100%').maxLines(1)
                  if (row.raOfDate !== undefined || row.decOfDate !== undefined) {
                    Text('当日坐标 ' + (row.raOfDate ?? '--') + '  ' + (row.decOfDate ?? '--')).fontSize(10).fontColor('#A0FFFFFF').width('100%').maxLines(1)
                  }
                  Text('高度 ' + this.host.fmtNum(row.altitude, 1, '°')
                    + '   方位 ' + this.host.fmtNum(row.azimuth, 0, '°')
                    + '   星等 ' + this.host.fmtNum(row.magnitude, 1, ''))
                    .fontSize(10).fontColor('#88FFFFFF').width('100%').maxLines(1)
                  if (row.hourAngle !== undefined || row.polarDistanceDegrees !== undefined) {
                    Text('时角 ' + (row.hourAngle ?? '--') + '   极距 ' + this.host.fmtNum(row.polarDistanceDegrees, 2, '°')
                      + (row.airmass !== undefined ? '   气团 ' + row.airmass.toFixed(2) : ''))
                      .fontSize(10).fontColor('#80FFFFFF').width('100%').maxLines(1)
                  }
                  if (row.phase !== undefined || row.distanceAU !== undefined || row.elongationDegrees !== undefined) {
                    Text((row.phase !== undefined ? '相位 ' + (row.phase * 100).toFixed(1) + '%' : '')
                      + (row.distanceAU !== undefined ? '   距离 ' + row.distanceAU.toFixed(3) + ' AU' : '')
                      + (row.elongationDegrees !== undefined ? '   距日 ' + row.elongationDegrees.toFixed(1) + '°' : ''))
                      .fontSize(10).fontColor('#70FFFFFF').width('100%').maxLines(1)
                  }
                  if (row.angularSizeArcmin !== undefined) {
                    Text('视直径 ' + row.angularSizeArcmin.toFixed(2) + '′').fontSize(10).fontColor('#70FFFFFF').width('100%').maxLines(1)
                  }
                }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
                .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.jumpToEphemerisRow(row) })
              }, (row: EphemerisRow, index: number) => index.toString())
            } else if (this.store.astroTab === 2) {
              Text(I18n.t('i0127')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 8 })
              Button(I18n.t('i0239')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.loadRTS() })
              if (!this.host.hasSelectedObject()) {
                RtsSelectionGuide({ textColor: this.textColor, subColor: this.subColor, panelColor: this.panelColor, onPick: () => { this.host.openRtsTargetPicker() } })
              } else if (this.store.rtsLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(20).height(20).color(this.accentColor)
                  Text('正在计算升起、中天和落下时间…').fontSize(11).fontColor(this.subColor)
                }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
              } else if (this.store.rtsError.length > 0) {
                Text(this.store.rtsError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.store.rtsData.size > 0) {
                InfoRow({ label: I18n.t('s0358'), value: this.store.rtsData.get('name') ?? 'N/A' })
                Row()
                  .width('100%').height(0.5)
                  .backgroundColor(this.lineColor)
                  .margin({ top: 4, bottom: 4 })
                Text(I18n.t('s0370')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                InfoRow({ label: I18n.t('s0700'), value: this.host.jdToDateStr(this.store.rtsData.get('nextRiseText') ?? '0') })
                InfoRow({ label: I18n.t('s0701'), value: this.host.jdToDateStr(this.store.rtsData.get('nextTransitText') ?? '0') })
                InfoRow({ label: I18n.t('s0702'), value: this.host.jdToDateStr(this.store.rtsData.get('nextSetText') ?? '0') })
                Row()
                  .width('100%').height(0.5)
                  .backgroundColor(this.lineColor)
                  .margin({ top: 4, bottom: 4 })
                Text(I18n.t('s0371')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                InfoRow({ label: I18n.t('s0700'), value: this.host.jdToDateStr(this.store.rtsData.get('prevRiseText') ?? '0') })
                InfoRow({ label: I18n.t('s0701'), value: this.host.jdToDateStr(this.store.rtsData.get('prevTransitText') ?? '0') })
                InfoRow({ label: I18n.t('s0702'), value: this.host.jdToDateStr(this.store.rtsData.get('prevSetText') ?? '0') })
              }
              if (this.host.hasSelectedObject()) {
              Row({ space: 6 }) {
                Button(I18n.t('i0146')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.jumpToRts('nextRiseJD') })
                Button(I18n.t('i0148')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.jumpToRts('nextTransitJD') })
                Button(I18n.t('i0147')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.jumpToRts('nextSetJD') })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
              Row()
                .width('100%').height(0.5)
                .backgroundColor(this.lineColor)
                .margin({ top: 10, bottom: 8 })
              Text('升中天落日期表').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Text('持续时长').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Scroll() {
                Row({ space: 4 }) {
                  ForEach([7, 14, 31, 62, 92, 183, 365], (days: number) => {
                    Text(rtsCalendarDurationLabel(days)).fontSize(10)
                    .fontColor(this.store.rtsCalendarDays === days ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.rtsCalendarDays === days ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
              }.width('100%').height(30).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
              Text('开始日期').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([0, 1, 7, 30], (offsetDays: number) => {
                  Text(this.host.rtsCalendarStartOptionLabel(offsetDays)).fontSize(10)
                    .fontColor(this.store.rtsCalendarStartOffsetDays === offsetDays ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.rtsCalendarStartOffsetDays === offsetDays ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.rtsCalendarStartOffsetDays !== offsetDays) {
                        this.store.rtsCalendarStartOffsetDays = offsetDays
                        this.host.markRtsCalendarForRegeneration()
                      }
                    })
                }, (offsetDays: number) => offsetDays.toString())
                Button(this.store.rtsCalendarStartOffsetDays < 0 ? this.host.rtsCalendarStartOptionLabel(-1) : '指定日期').fontSize(10)
                  .fontColor(this.store.rtsCalendarStartOffsetDays < 0 ? this.textColor : this.subColor)
                  .height(26).padding({ left: 9, right: 9 })
                  .backgroundColor(this.store.rtsCalendarStartOffsetDays < 0 ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.chooseRtsCalendarStartDate() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
              Row({ space: 6 }) {
                Button('生成日期表').fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadRtsCalendar() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
              if (this.store.rtsCalendarLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.accentColor)
                  Text('正在生成升中天落日期表… ' + this.store.rtsCalendarProgress.toString() + '/' + this.store.rtsCalendarTotalDays.toString() + ' 天').fontSize(11).fontColor(this.subColor)
                }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
              } else if (this.store.rtsCalendarNeedsGeneration) {
                Text('参数已更新，请点击生成日期表开始计算。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 4 })
              } else if (this.store.rtsCalendarError.length > 0) {
                Text(this.store.rtsCalendarError).fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 4 })
              } else if (this.store.rtsCalendarData.length > 0) {
                Text(this.store.rtsCalendarName + ' · 从' + this.host.rtsCalendarStartOptionLabel(this.store.rtsCalendarStartOffsetDays) + '开始，持续 ' + rtsCalendarDurationLabel(this.store.rtsCalendarDays) + '；每项按本地日期计算，点击可跳到该日中天。')
                  .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                ForEach(this.store.rtsCalendarData, (day: RtsCalendarDay) => {
                  Column({ space: 1 }) {
                    Row() {
                      Text(this.host.fmtDateTime(day.date)).fontSize(10).fontColor(this.textColor).width(94)
                      if (day.status !== undefined) {
                        Text(day.status ?? '').fontSize(10).fontColor(this.accentColor).layoutWeight(1)
                      } else {
                        Text('升 ' + this.host.fmtClock(day.rise) + '  中天 ' + this.host.fmtClock(day.transit) + '  落 ' + this.host.fmtClock(day.set))
                          .fontSize(10).fontColor(this.textColor).layoutWeight(1).maxLines(1)
                      }
                    }.width('100%').padding({ left: 8, right: 8 })
                    if (day.status === undefined) {
                      Text('中天高度 ' + (day.transitAltitude ?? 0).toFixed(1) + '°   星等 ' + (day.magnitude ?? 0).toFixed(1)
                        + '   距日 ' + (day.solarElongation ?? 0).toFixed(1) + '°   距月 ' + (day.lunarElongation ?? 0).toFixed(1) + '°')
                        .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 }).maxLines(1)
                    }
                  }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.jumpToRtsCalendar(day) })
                }, (day: RtsCalendarDay, index: number) => day.date ?? index.toString())
              }
              }
            } else if (this.store.astroTab === 3) {
              Text(I18n.t('i0128')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 8 })
              Text('计算对象').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Scroll() {
                Row({ space: 4 }) {
                  ForEach(['all', 'Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                    Text(this.host.phenomenaBodyName(body)).fontSize(10)
                      .fontColor(this.store.phenomenaPrimary === body ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                      .backgroundColor(this.store.phenomenaPrimary === body ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        this.store.phenomenaPrimary = body
                        if (this.store.phenomenaTarget === body) this.store.phenomenaTarget = 'all'
                      })
                  }, (body: string) => body)
                }.padding({ left: 2, right: 2 })
              }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
              if (this.store.phenomenaPrimary !== 'all') {
                Text('比较对象').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Scroll() {
                  Row({ space: 4 }) {
                    ForEach(['all', 'Sun', 'Moon', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto'], (body: string) => {
                      if (body !== this.store.phenomenaPrimary) {
                        Text(this.host.phenomenaBodyName(body)).fontSize(10)
                          .fontColor(this.store.phenomenaTarget === body ? this.textColor : this.subColor)
                          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                          .backgroundColor(this.store.phenomenaTarget === body ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                          .borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => { this.store.phenomenaTarget = body })
                      }
                    }, (body: string) => body)
                  }.padding({ left: 2, right: 2 })
                }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 5 })
              }
              Text('起始时段').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach(PHENOMENA_START_OPTIONS, (item: PhenomenaStartOption) => {
                  Text(item.label).fontSize(10)
                    .fontColor(this.store.phenomenaStartOffsetMonths === item.value ? this.textColor : this.subColor)
                    .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                    .backgroundColor(this.store.phenomenaStartOffsetMonths === item.value ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.phenomenaStartOffsetMonths = item.value })
                }, (item: PhenomenaStartOption) => item.value.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 5 })
              Column({ space: 5 }) {
                Text('预测范围').fontSize(10).fontColor(this.subColor).width('100%')
                Row({ space: 4 }) {
                  ForEach([30, 90, 180, 400, 730], (days: number) => {
                    Text(days < 365 ? days.toString() + ' 天' : (days / 365).toFixed(1) + ' 年').fontSize(10)
                      .fontColor(this.store.phenomenaDays === days ? this.textColor : this.subColor)
                      .padding({ left: 7, right: 7, top: 5, bottom: 5 })
                      .backgroundColor(this.store.phenomenaDays === days ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.phenomenaDays = days })
                  }, (days: number) => days.toString())
                }
                Text('最大角距').fontSize(10).fontColor(this.subColor).width('100%')
                Row({ space: 4 }) {
                  ForEach([1, 4, 10, 20], (degrees: number) => {
                    Text(degrees.toString() + '°').fontSize(10)
                      .fontColor(this.store.phenomenaMaxSeparation === degrees ? this.textColor : this.subColor)
                      .padding({ left: 7, right: 7, top: 5, bottom: 5 })
                      .backgroundColor(this.store.phenomenaMaxSeparation === degrees ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.phenomenaMaxSeparation = degrees })
                  }, (degrees: number) => degrees.toString())
                }
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('附加天象').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                Text('冲').fontSize(10).fontColor(this.store.phenomenaIncludeOppositions ? this.textColor : this.subColor)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor(this.store.phenomenaIncludeOppositions ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.store.phenomenaIncludeOppositions = !this.store.phenomenaIncludeOppositions })
                Text('近日点/远日点').fontSize(10).fontColor(this.store.phenomenaIncludePerihelionAphelion ? this.textColor : this.subColor)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor(this.store.phenomenaIncludePerihelionAphelion ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.store.phenomenaIncludePerihelionAphelion = !this.store.phenomenaIncludePerihelionAphelion })
                Text('大距/方照').fontSize(10).fontColor(this.store.phenomenaIncludeElongationsQuadratures ? this.textColor : this.subColor)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor(this.store.phenomenaIncludeElongationsQuadratures ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.store.phenomenaIncludeElongationsQuadratures = !this.store.phenomenaIncludeElongationsQuadratures })
                Text('留点').fontSize(10).fontColor(this.store.phenomenaIncludeStations ? this.textColor : this.subColor)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor(this.store.phenomenaIncludeStations ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.store.phenomenaIncludeStations = !this.store.phenomenaIncludeStations })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 7 })
              Row({ space: 6 }) {
                Button('计算天象').fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadPhenomena() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              Text('合相按最大角距筛选；点任一结果可跳到发生时刻。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              if (this.store.phenomenaLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.accentColor)
                  Text('正在计算天象…').fontSize(11).fontColor(this.subColor)
                }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
              } else if (this.store.phenomenaHint.length > 0) {
                Text(this.store.phenomenaHint).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else if (this.store.phenomenaData.length === 0) {
                Text('尚未计算天象。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8 })
              }
              ForEach(this.store.phenomenaData, (p: PhenomenonItem) => {
                Row({ space: 8 }) {
                  Stack({ alignContent: Alignment.Center }) {
                    PhenomenonRelationMark({ type: p.type ?? '' })
                  }.width(52).height(44).backgroundColor(this.panelColor).border({ width: 1, color: this.lineColor }).borderRadius(UI_RADIUS_CONTROL)
                  Column({ space: 3 }) {
                    Text(phenomenonCaption(p.type ?? '')).fontSize(10).fontColor(this.subColor).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text((p.bodyA ?? '天体') + ' 与 ' + (p.bodyB ?? '太阳'))
                      .fontSize(12).fontColor(this.textColor).fontWeight(FontWeight.Medium).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.host.fmtDateTime(p.date)).fontSize(10).fontColor(this.subColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Column({ space: 3 }) {
                    Text(p.metricLabel ?? '角距').fontSize(10).fontColor(this.subColor).width('100%').textAlign(TextAlign.End)
                    Text(this.host.fmtNum(p.separation, 2, p.metricUnit ?? '°')).fontSize(11).fontColor(this.textColor).fontWeight(FontWeight.Medium)
                      .width('100%').textAlign(TextAlign.End).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.width(84).alignItems(HorizontalAlign.End)
                }.width('100%').height(64).padding({ left: 8, right: 8, top: 5, bottom: 5 })
                  .backgroundColor(this.panelColor).border({ width: 1, color: this.lineColor }).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.jumpToPhenomenon(p) })
              }, (p: PhenomenonItem, index: number) => index.toString())
            } else if (this.store.astroTab === 4) {
              Text(I18n.t('i0129')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 8 })
              Row({ space: 8 }) {
                Column({ space: 1 }) {
                  Text('曲线目标').fontSize(10).fontColor(this.subColor)
                  Text(this.host.graphTargetLabel()).fontSize(12).fontColor(this.objectDetailStore.selectedName.length > 0 ? this.textColor : this.subColor)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button(this.objectDetailStore.selectedName.length > 0 ? '更换天体' : '选择天体')
                  .fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(28).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.openGraphTargetPicker() })
              }.width('100%').padding({ left: 4, right: 4, top: 5, bottom: 5 })
                .backgroundColor(this.panelColor).border({ width: 1, color: this.lineColor }).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
              if (this.store.graphMode !== 2) {
                Text('起始日期').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([0, 1, 7, 30], (offsetDays: number) => {
                    Text(graphStartOptionLabel(offsetDays)).fontSize(10)
                      .fontColor(this.store.graphStartOffsetDays === offsetDays ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.graphStartOffsetDays === offsetDays ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.graphStartOffsetDays !== offsetDays) {
                          this.store.graphStartOffsetDays = offsetDays
                          this.host.reloadCurrentGraph()
                        }
                      })
                  }, (offsetDays: number) => offsetDays.toString())
                  Button(this.host.graphCustomStartLabel()).fontSize(10)
                    .fontColor(this.store.graphStartOffsetDays < 0 ? this.textColor : this.subColor)
                    .height(26).padding({ left: 9, right: 9 })
                    .backgroundColor(this.store.graphStartOffsetDays < 0 ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.chooseGraphStartDate() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
              }
              Row({ space: 4 }) {
                ForEach(['高度', '方位', '全年', '月度', '月距', '双曲线'], (mode: string, index: number) => {
                  Text(mode).fontSize(10)
                    .fontColor(this.store.graphMode === index ? this.textColor : this.subColor)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.store.graphMode === index ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
              Text('时间范围').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([12, 24, 48, 72], (hours: number) => {
                  Text(hours.toString() + 'h')
                    .fontSize(10)
                    .fontColor(this.store.altAzHours === hours ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.altAzHours === hours ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
              Text('采样间隔').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([15, 30, 60], (stepMin: number) => {
                  Text(stepMin.toString() + ' 分')
                    .fontSize(10)
                    .fontColor(this.store.altAzStepMin === stepMin ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.altAzStepMin === stepMin ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Text('叠加曲线').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  Text('太阳').fontSize(10)
                    .fontColor(this.store.altAzShowSun ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.altAzShowSun ? '#9C6A24' : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.altAzShowSun = !this.store.altAzShowSun; this.host.loadAltAzCurve() })
                  Text('月亮').fontSize(10)
                    .fontColor(this.store.altAzShowMoon ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.altAzShowMoon ? '#657384' : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.altAzShowMoon = !this.store.altAzShowMoon; this.host.loadAltAzCurve() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('显示高度不低于').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([-90, 0, 15, 30], (minimum: number) => {
                    Text(minimum === -90 ? '全部' : minimum.toString() + '°').fontSize(10)
                      .fontColor(this.store.altAzMinimum === minimum ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.altAzMinimum === minimum ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.altAzMinimum = minimum })
                  }, (minimum: number) => minimum.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              }
              Row({ space: 6 }) {
                Button(this.store.graphMode === 0 ? '刷新高度' : '刷新方位').fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.store.altAzCurve = []; this.store.altAzError = ''; this.host.loadAltAzCurve() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              if (this.store.graphLoading) {
                GraphLoadingRow({ label: '正在计算' + this.host.altAzRangeLabel() + '的' + (this.store.graphMode === 0 ? '高度' : '方位角') + '变化…', accentColor: this.accentColor, subColor: this.subColor })
              } else if (this.store.altAzError.length > 0) {
                Text(this.store.altAzError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                GraphSelectionGuide({ error: this.store.altAzError, textColor: this.textColor, subColor: this.subColor, panelColor: this.panelColor, onPick: () => { this.host.openGraphTargetPicker() } })
              } else if (this.store.altAzCurve.length === 0) {
                Text('没有可绘制的数据。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else {
                Text(this.store.altAzName + ' · ' + this.host.altAzRangeLabel() + (this.store.graphMode === 0 ? '高度变化' : '方位角变化') + '（每 ' + this.store.altAzStepMin.toString() + ' 分）').fontSize(11).fontColor(this.textColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                Stack({ alignContent: Alignment.Center }) {
                  Row() {
                    ForEach(this.store.altAzCurve, (r: AltAzPoint) => {
                      if (this.store.graphMode === 0) {
                        Row({ space: 1 }) {
                          Column().width(this.host.altCurveSegmentWidth()).height(this.host.altBarHeight(r.altitude))
                            .backgroundColor(this.host.altitudeCurveColor(r.altitude, this.accentColor)).borderRadius(1)
                          if (this.store.altAzShowSun) {
                            Column().width(this.host.altCurveSegmentWidth()).height(this.host.altBarHeight(r.sunAltitude))
                              .backgroundColor(this.host.altitudeCurveColor(r.sunAltitude, '#E8B24B')).borderRadius(1)
                          }
                          if (this.store.altAzShowMoon) {
                            Column().width(this.host.altCurveSegmentWidth()).height(this.host.altBarHeight(r.moonAltitude))
                              .backgroundColor(this.host.altitudeCurveColor(r.moonAltitude, '#CCD7E5')).borderRadius(1)
                          }
                        }.width(this.host.altBarWidth()).height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                      } else {
                        Column().width(this.host.altBarWidth()).height(azBarHeight(r.azimuth))
                          .backgroundColor(this.accentColor).borderRadius(1)
                      }
                    }, (r: AltAzPoint, index: number) => index.toString())
                  }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                  if (this.store.graphMode === 0 && this.store.altAzMinimum <= 0) {
                    Divider().color('#66FFFFFF').strokeWidth(1).width('100%').align(this.store.altAzMinimum === 0 ? Alignment.Bottom : Alignment.Center)
                  }
                }.width('100%').height(96).padding({ left: 6, right: 6 })
                Row() {
                  Text(this.store.graphMode === 0 ? '现在' : '0°').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Start)
                  Text(this.store.graphMode === 0 ? this.host.altAzMidpointLabel() : '180°').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Center)
                  Text(this.store.graphMode === 0 ? '+' + this.store.altAzHours.toString() + 'h' : '360°').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.End)
                }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                Text(this.store.graphMode === 0 ? (this.store.altAzMinimum <= 0 ? '横线是地平线；主曲线为目标，金色为太阳，银灰色为月亮。' : '曲线仅显示不低于 ' + this.store.altAzMinimum.toString() + '° 的部分；主曲线为目标，金色为太阳，银灰色为月亮。') : '方位角从北方 0° 起顺时针增加：东 90°、南 180°、西 270°。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
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
                  .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Row({ space: 8 }) {
                  Text('本地时刻 ' + this.store.annualElevationHour.toString().padStart(2, '0') + ':00').fontSize(10).fontColor(this.subColor).width(100)
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
                Text('显示高度不低于').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([-90, 0, 15, 30], (minimum: number) => {
                    Text(minimum === -90 ? '全部' : minimum.toString() + '°').fontSize(10)
                      .fontColor(this.store.annualElevationMinimum === minimum ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.annualElevationMinimum === minimum ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.annualElevationMinimum = minimum })
                  }, (minimum: number) => minimum.toString())
                  Button('刷新').fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                    .borderRadius(UI_RADIUS_PILL).height(28).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadAnnualElevation() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.graphLoading) {
                  GraphLoadingRow({ label: '正在生成全年高度曲线…', accentColor: this.accentColor, subColor: this.subColor })
                } else if (this.store.annualElevationError.length > 0) {
                  Text(this.store.annualElevationError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                  GraphSelectionGuide({ error: this.store.annualElevationError, textColor: this.textColor, subColor: this.subColor, panelColor: this.panelColor, onPick: () => { this.host.openGraphTargetPicker() } })
                } else if (this.store.annualElevationData.length === 0) {
                  Text('没有可绘制的数据。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.annualElevationName + ' · ' + this.store.annualElevationHour.toString().padStart(2, '0') + ':00 全年高度').fontSize(11).fontColor(this.textColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  Stack({ alignContent: Alignment.Center }) {
                    Row() {
                      ForEach(this.store.annualElevationData, (point: AnnualElevationPoint) => {
                        Column().width(this.host.annualBarWidth()).height(this.host.annualBarHeight(point.altitude))
                          .backgroundColor((point.altitude ?? -90) >= this.store.annualElevationMinimum ? this.accentColor : '#33FFFFFF').animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(1)
                      }, (point: AnnualElevationPoint, index: number) => index.toString())
                    }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                    if (this.store.annualElevationMinimum <= 0) {
                      Divider().color('#66FFFFFF').strokeWidth(1).width('100%')
                    }
                  }.width('100%').height(96).padding({ left: 6, right: 6 })
                  Row() {
                    Text('1月').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Start)
                    Text('4月').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Center)
                    Text('7月').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Center)
                    Text('10月').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.End)
                  }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                  InfoRow({ label: '全年最高', value: this.host.annualMaxLabel() })
                  InfoRow({ label: '显示下限', value: this.store.annualElevationMinimum === -90 ? '不限制' : this.store.annualElevationMinimum.toString() + '°' })
                }
              } else if (this.store.graphMode === 3) {
                Text('按天文暗夜（太阳低于地平线 18°）统计；点任一晚可跳到目标最高的时刻。')
                  .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Text('计划范围').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([30, 90], (days: number) => {
                    Text('未来 ' + days.toString() + ' 天').fontSize(10)
                      .fontColor(this.store.observabilityDays === days ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.observabilityDays === days ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Text('最低高度').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([15, 20, 30], (altitude: number) => {
                    Text(altitude.toString() + '°').fontSize(10)
                      .fontColor(this.store.observabilityMinAltitude === altitude ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.observabilityMinAltitude === altitude ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.observabilityMinAltitude !== altitude) {
                          this.store.observabilityMinAltitude = altitude
                          this.host.loadObservabilityCalendar()
                        }
                      })
                  }, (altitude: number) => altitude.toString())
                  Button('刷新').fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                    .borderRadius(UI_RADIUS_PILL).height(28).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadObservabilityCalendar() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.graphLoading) {
                  GraphLoadingRow({ label: this.store.observabilityProgress.length > 0 ? this.store.observabilityProgress : '正在计算未来多晚的观测窗口…', accentColor: this.accentColor, subColor: this.subColor })
                } else if (this.store.observabilityError.length > 0) {
                  Text(this.store.observabilityError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                  GraphSelectionGuide({ error: this.store.observabilityError, textColor: this.textColor, subColor: this.subColor, panelColor: this.panelColor, onPick: () => { this.host.openGraphTargetPicker() } })
                } else if (this.store.observabilityData.length === 0) {
                  Text('所选时段没有可用观测窗口。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.observabilityName + ' · 高于 ' + this.store.observabilityMinAltitude.toString() + '° 的暗夜可见时间')
                    .fontSize(11).fontColor(this.textColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  ForEach(this.store.observabilityData, (day: ObservabilityDay) => {
                    Column({ space: 2 }) {
                      Row() {
                        Text(day.date ?? '--').fontSize(11).fontColor(this.textColor).layoutWeight(1)
                        Text((day.visibleHours ?? 0).toFixed(1) + ' 小时').fontSize(11)
                          .fontColor((day.visibleHours ?? 0) > 0 ? this.accentColor : this.subColor)
                      }.width('100%').padding({ left: 8, right: 8 })
                      if ((day.darkHours ?? 0) > 0) {
                        Text('最佳 ' + this.host.fmtClock(day.peakTime) + ' · 最高 ' + this.host.fmtNum(day.maxAltitude, 1, '°') + ' · 暗夜 ' + this.host.fmtNum(day.darkHours, 1, ' 小时'))
                          .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 12, right: 8 })
                        Text('月亮：照亮 ' + this.host.fmtNum(day.moonIllumination, 0, ' %') + '，高度 ' + this.host.fmtNum(day.moonAltitude, 0, '°'))
                          .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12, right: 8 })
                      } else {
                        Text('当地没有完整的天文暗夜。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 12, right: 8 })
                      }
                    }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.jumpToObservabilityDay(day) })
                  }, (day: ObservabilityDay, index: number) => index.toString())
                }
              } else if (this.store.graphMode === 4) {
                Text('显示选中目标与月亮的角距；金色柱表示距离小于参考线，通常意味着月光干扰更明显。')
                  .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Text('时间范围').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([14, 30, 60], (days: number) => {
                    Text('未来 ' + days.toString() + ' 天').fontSize(10)
                      .fontColor(this.store.lunarElongationDays === days ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.lunarElongationDays === days ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Text('采样间隔').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([6, 12, 24], (hours: number) => {
                    Text(hours.toString() + ' 小时').fontSize(10)
                      .fontColor(this.store.lunarElongationStepHours === hours ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.lunarElongationStepHours === hours ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Text('月距参考线').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([10, 20, 40, 60], (limit: number) => {
                    Text(limit.toString() + '°').fontSize(10)
                      .fontColor(this.store.lunarElongationLimit === limit ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.lunarElongationLimit === limit ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => { this.store.lunarElongationLimit = limit })
                  }, (limit: number) => limit.toString())
                  Button('刷新').fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                    .borderRadius(UI_RADIUS_PILL).height(28).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadLunarElongation() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.graphLoading) {
                  GraphLoadingRow({ label: '正在计算目标与月亮的角距…', accentColor: this.accentColor, subColor: this.subColor })
                } else if (this.store.lunarElongationError.length > 0) {
                  Text(this.store.lunarElongationError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                  GraphSelectionGuide({ error: this.store.lunarElongationError, textColor: this.textColor, subColor: this.subColor, panelColor: this.panelColor, onPick: () => { this.host.openGraphTargetPicker() } })
                } else if (this.store.lunarElongationData.length === 0) {
                  Text('没有可绘制的数据。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.lunarElongationName + ' · 未来 ' + this.store.lunarElongationDays.toString() + ' 天月距（每 ' + this.store.lunarElongationStepHours.toString() + ' 小时）')
                    .fontSize(11).fontColor(this.textColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  Stack({ alignContent: Alignment.Center }) {
                    Row() {
                      ForEach(this.store.lunarElongationData, (point: LunarElongationPoint) => {
                        Column().width(this.host.lunarElongationBarWidth()).height(lunarElongationBarHeight(point.separation))
                          .backgroundColor((point.separation ?? 180) < this.store.lunarElongationLimit ? '#E8B24B' : this.accentColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(1)
                      }, (point: LunarElongationPoint, index: number) => index.toString())
                    }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                    Divider().color('#E8B24B').strokeWidth(1).width('100%').position({ x: 0, y: this.host.lunarElongationLineTop() })
                  }.width('100%').height(96).padding({ left: 6, right: 6 })
                  Row() {
                    Text('现在').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Start)
                    Text('+' + Math.round(this.store.lunarElongationDays / 2).toString() + '天').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Center)
                    Text('+' + this.store.lunarElongationDays.toString() + '天').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.End)
                  }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                  Text('纵轴 0°-180°；金色横线是 ' + this.store.lunarElongationLimit.toString() + '° 参考线。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                  InfoRow({ label: '当前月距', value: this.host.lunarElongationNowLabel() })
                  InfoRow({ label: '最接近月亮', value: this.host.lunarElongationClosestLabel() })
                  InfoRow({ label: '参考线', value: this.store.lunarElongationLimit.toString() + '°' })
                }
              } else {
                Text('桌面版“Graphs”双变量时间曲线：左右两条曲线各自缩放，适合比较不同量纲的变化趋势。')
                  .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Text('时间范围').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([30, 90, 365], (days: number) => {
                    Text(days === 365 ? '未来 1 年' : '未来 ' + days.toString() + ' 天').fontSize(10)
                      .fontColor(this.store.planetTimeSeriesDays === days ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.planetTimeSeriesDays === days ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Text('采样间隔').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach(this.store.planetTimeSeriesDays === 365 ? [24, 72] : [6, 24, 72], (hours: number) => {
                    Text(hours.toString() + ' 小时').fontSize(10)
                      .fontColor(this.store.planetTimeSeriesStepHours === hours ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.planetTimeSeriesStepHours === hours ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Text('左轴：' + planetMetricLabel(this.store.planetTimeSeriesLeftMetric)).fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Column({ space: 3 }) {
                  ForEach([['magnitude', 'phase', 'distance', 'elongation', 'angularSize'], ['phaseAngle', 'heliocentricDistance', 'transitAltitude', 'rightAscension', 'declination']], (metrics: Array<string>, row: number) => {
                    Row({ space: 3 }) {
                      ForEach(metrics, (metric: string) => {
                        Text(planetMetricLabel(metric)).fontSize(10).maxLines(1)
                          .fontColor(this.store.planetTimeSeriesLeftMetric === metric ? this.textColor : this.subColor)
                          .padding({ left: 5, right: 5, top: 4, bottom: 4 })
                          .backgroundColor(this.store.planetTimeSeriesLeftMetric === metric ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                          .borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => { this.store.planetTimeSeriesLeftMetric = metric; this.host.loadPlanetTimeSeries() })
                      }, (metric: string) => metric)
                    }.width('100%')
                  }, (metrics: Array<string>, row: number) => row.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('右轴：' + planetMetricLabel(this.store.planetTimeSeriesRightMetric)).fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Column({ space: 3 }) {
                  ForEach([['magnitude', 'phase', 'distance', 'elongation', 'angularSize'], ['phaseAngle', 'heliocentricDistance', 'transitAltitude', 'rightAscension', 'declination']], (metrics: Array<string>, row: number) => {
                    Row({ space: 3 }) {
                      ForEach(metrics, (metric: string) => {
                        Text(planetMetricLabel(metric)).fontSize(10).maxLines(1)
                          .fontColor(this.store.planetTimeSeriesRightMetric === metric ? this.textColor : this.subColor)
                          .padding({ left: 5, right: 5, top: 4, bottom: 4 })
                          .backgroundColor(this.store.planetTimeSeriesRightMetric === metric ? '#9C6A24' : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                          .borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .onClick(() => { this.store.planetTimeSeriesRightMetric = metric; this.host.loadPlanetTimeSeries() })
                      }, (metric: string) => metric)
                    }.width('100%')
                  }, (metrics: Array<string>, row: number) => row.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Row({ space: 6 }) {
                  Button('刷新').fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                    .borderRadius(UI_RADIUS_PILL).height(28).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadPlanetTimeSeries() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.graphLoading) {
                  GraphLoadingRow({ label: '正在计算双变量时间曲线…', accentColor: this.accentColor, subColor: this.subColor })
                } else if (this.store.planetTimeSeriesError.length > 0) {
                  Text(this.store.planetTimeSeriesError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                  GraphSelectionGuide({ error: this.store.planetTimeSeriesError, textColor: this.textColor, subColor: this.subColor, panelColor: this.panelColor, onPick: () => { this.host.openGraphTargetPicker() } })
                } else if (this.store.planetTimeSeriesData.length === 0) {
                  Text('没有可绘制的数据。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.planetTimeSeriesName + ' · ' + planetMetricLabel(this.store.planetTimeSeriesLeftMetric) + ' / ' + planetMetricLabel(this.store.planetTimeSeriesRightMetric))
                    .fontSize(11).fontColor(this.textColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  Stack({ alignContent: Alignment.Center }) {
                    Row() {
                      ForEach(this.store.planetTimeSeriesData, (point: PlanetTimeSeriesPoint) => {
                        Row({ space: 1 }) {
                          Column().width(this.host.planetTimeSeriesSegmentWidth())
                            .height(planetTimeSeriesBarHeight(point.left, this.store.planetTimeSeriesLeftMin, this.store.planetTimeSeriesLeftMax))
                            .backgroundColor(this.accentColor).borderRadius(1)
                          Column().width(this.host.planetTimeSeriesSegmentWidth())
                            .height(planetTimeSeriesBarHeight(point.right, this.store.planetTimeSeriesRightMin, this.store.planetTimeSeriesRightMax))
                            .backgroundColor('#E8B24B').borderRadius(1)
                        }.width(this.host.planetTimeSeriesBarWidth()).height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                      }, (point: PlanetTimeSeriesPoint, index: number) => index.toString())
                    }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                  }.width('100%').height(96).padding({ left: 6, right: 6 })
                  Row() {
                    Text('现在').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Start)
                    Text('+' + Math.round(this.store.planetTimeSeriesDays / 2).toString() + '天').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Center)
                    Text(this.store.planetTimeSeriesDays === 365 ? '+1年' : '+' + this.store.planetTimeSeriesDays.toString() + '天').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.End)
                  }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                  Text('蓝色左轴：' + this.store.planetTimeSeriesLeftMin.toFixed(1) + ' - ' + this.store.planetTimeSeriesLeftMax.toFixed(1) + planetMetricUnit(this.store.planetTimeSeriesLeftMetric)
                    + '；金色右轴：' + this.store.planetTimeSeriesRightMin.toFixed(1) + ' - ' + this.store.planetTimeSeriesRightMax.toFixed(1) + planetMetricUnit(this.store.planetTimeSeriesRightMetric))
                    .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                  InfoRow({ label: '当前 ' + planetMetricLabel(this.store.planetTimeSeriesLeftMetric), value: this.host.planetTimeSeriesValueLabel(this.store.planetTimeSeriesData[0].left, this.store.planetTimeSeriesLeftMetric) })
                  InfoRow({ label: '当前 ' + planetMetricLabel(this.store.planetTimeSeriesRightMetric), value: this.host.planetTimeSeriesValueLabel(this.store.planetTimeSeriesData[0].right, this.store.planetTimeSeriesRightMetric) })
                }
              }
            } else if (this.store.astroTab === 5) {
              Text('今晚可观测目标').fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 2 })
              Text('按时段、最低高度和星等筛选适合观测的天体。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              Row({ space: 6 }) {
                Button('刷新可观测目标').fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.store.tonightAstro = null; this.host.loadTonightAstro() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              if (this.store.tonightAstro === null) {
                Text('（正在汇总今晚的观测条件…）').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else {
                Text('太阳与暗夜窗口').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                InfoRow({ label: '日落', value: this.host.fmtDateTime(this.store.tonightAstro!.sun?.set) })
                InfoRow({ label: '天文暮光结束', value: this.host.fmtDateTime(this.store.tonightAstro!.sun?.astroTwilightEnd) })
                InfoRow({ label: '天文暮光开始', value: this.host.fmtDateTime(this.store.tonightAstro!.sun?.astroTwilightStart) })
                InfoRow({ label: '日出', value: this.host.fmtDateTime(this.store.tonightAstro!.sun?.rise) })
                InfoRow({ label: '可用暗夜时长', value: this.host.fmtNum(this.store.tonightAstro!.sun?.darkWindowHours, 1, ' 小时') })
                Text('月亮').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                InfoRow({ label: '月相', value: this.store.tonightAstro!.moon?.phaseName ?? '--' })
                InfoRow({ label: '照亮比例', value: this.host.fmtNum(this.store.tonightAstro!.moon?.illumination, 1, ' %') })
                InfoRow({ label: '月龄', value: this.host.fmtNum(this.store.tonightAstro!.moon?.age, 1, ' 天') })
                InfoRow({ label: '月出', value: this.host.fmtDateTime(this.store.tonightAstro!.moon?.rise) })
                InfoRow({ label: '月落', value: this.host.fmtDateTime(this.store.tonightAstro!.moon?.set) })
                Text('今晚可观测目标').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 8 }) {
                    Column({ space: 4 }) {
                      Text('选择类别').fontSize(12).fontColor(this.subColor).width('100%')
                      Text(this.host.wutCategoryTitle()).fontSize(14).fontColor(this.textColor).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Image(getIcon('chevron_right', false)).width(18).height(18).fillColor(this.subColor)
                      .rotate({ angle: this.wutStore.wutCategoriesExpanded ? 90 : 0 })
                  }.width('100%')
                }.width('100%').padding(12).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => {
                    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                      this.wutStore.wutCategoriesExpanded = !this.wutStore.wutCategoriesExpanded
                    })
                  })
                if (this.wutStore.wutCategoriesExpanded) {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(wutCategoryOptions(), (option: TabItem) => {
                      Text(option.label).fontSize(12).width('48%')
                        .fontColor(this.wutStore.wutCategory === wutCategoryKey(option.id) ? this.textColor : this.subColor)
                        .padding(10).margin({ right: '2%', bottom: 6 })
                        .backgroundColor(this.wutStore.wutCategory === wutCategoryKey(option.id) ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                      Text('观测时段').fontSize(12).fontColor(this.subColor).width('100%').margin({ bottom: 6 })
                      ForEach(['evening', 'midnight', 'morning', 'night'], (period: string) => {
                        Text(period === 'evening' ? '傍晚' : (period === 'morning' ? '清晨' : (period === 'night' ? '整夜' : '午夜')))
                          .fontSize(12).fontColor(this.wutStore.wutPeriod === period ? this.textColor : this.subColor)
                          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                          .backgroundColor(this.wutStore.wutPeriod === period ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .id('astro-filter-period-' + period)
                          .onClick(() => { this.host.selectAstroFilter('period', period) })
                      }, (period: string) => period)
                    }.width('100%')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      Text('地平高度高于').fontSize(12).fontColor(this.subColor).width('100%').margin({ bottom: 6 })
                      ForEach([0, 10, 20, 30, 45], (altitude: number) => {
                        Text(altitude.toString() + '°').fontSize(12)
                          .fontColor(this.wutStore.wutMinAltitude === altitude ? this.textColor : this.subColor)
                          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                          .backgroundColor(this.wutStore.wutMinAltitude === altitude ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .id('astro-filter-altitude-' + altitude.toString())
                          .onClick(() => { this.host.selectAstroFilter('altitude', altitude.toString()) })
                      }, (altitude: number) => altitude.toString())
                    }.width('100%')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      Text('星等不超过').fontSize(12).fontColor(this.subColor).width('100%').margin({ bottom: 6 })
                      ForEach([4, 6, 8, 10], (magnitude: number) => {
                        Text(magnitude.toString()).fontSize(12)
                          .fontColor(this.wutStore.wutMaxMagnitude === magnitude ? this.textColor : this.subColor)
                          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                          .backgroundColor(this.wutStore.wutMaxMagnitude === magnitude ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .id('astro-filter-magnitude-' + magnitude.toString())
                          .onClick(() => { this.host.selectAstroFilter('magnitude', magnitude.toString()) })
                      }, (magnitude: number) => magnitude.toString())
                    }.width('100%')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      Text('方向').fontSize(12).fontColor(this.subColor).width('100%').margin({ bottom: 6 })
                      ForEach(['all', 'north', 'east', 'south', 'west'], (direction: string) => {
                        Text(wutDirectionLabel(direction)).fontSize(12).fontColor(this.wutStore.wutDirection === direction ? this.textColor : this.subColor)
                          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                          .backgroundColor(this.wutStore.wutDirection === direction ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                          .id('astro-filter-direction-' + direction)
                          .onClick(() => { this.host.selectAstroFilter('direction', direction) })
                      }, (direction: string) => direction)
                    }.width('100%')
                    Row({ space: 8 }) {
                      Text('限制角大小').fontSize(12).fontColor(this.subColor).layoutWeight(1)
                      Toggle({ type: ToggleType.Switch, isOn: this.wutStore.wutLimitAngularSize }).width(44).height(28)
                        .enabled(this.wutStore.wutAngularSizeAvailable)
                        .onChange((value: boolean) => { this.wutStore.wutLimitAngularSize = value; this.host.loadWutTargets() })
                    }.width('100%')
                    if (this.wutStore.wutLimitAngularSize && this.wutStore.wutAngularSizeAvailable) {
                      Flex({ wrap: FlexWrap.Wrap }) {
                        ForEach(['10角分–1度', '1度–10度'], (label: string, index: number) => {
                          Text(label).fontSize(12).fontColor((index === 0 ? this.wutStore.wutMinAngularSizeArcmin === 10 : this.wutStore.wutMinAngularSizeArcmin === 60) ? this.textColor : this.subColor)
                            .padding({ left: 12, right: 12, top: 9, bottom: 9 }).margin({ right: 6, bottom: 6 })
                            .backgroundColor((index === 0 ? this.wutStore.wutMinAngularSizeArcmin === 10 : this.wutStore.wutMinAngularSizeArcmin === 60) ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }).borderRadius(UI_RADIUS_CONTROL)
                            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                            .onClick(() => { this.wutStore.wutMinAngularSizeArcmin = index === 0 ? 10 : 60; this.wutStore.wutMaxAngularSizeArcmin = index === 0 ? 60 : 600; this.host.loadWutTargets() })
                        }, (label: string) => label)
                      }.width('100%')
                    }

                }.width('100%').padding(12).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ top: 8, bottom: 12 })
                if (this.wutStore.wutLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.accentColor)
                    Text(this.wutStore.wutProgress.length > 0 ? this.wutStore.wutProgress : '正在筛选可观测目标…').fontSize(11).fontColor(this.subColor)
                  }.width('100%').padding({ left: 8, top: 5, bottom: 7 })
                }
                if (this.wutStore.wutHint.length > 0) {
                  Text(this.wutStore.wutHint).fontSize(12).fontColor(this.subColor).width('100%').margin({ bottom: 8 })
                } else {
                  Text('筛选结果 ' + this.wutStore.wutTargets.length.toString() + ' 个 · ' + this.host.fmtClock(this.wutStore.wutObservationTime))
                    .fontSize(12).fontColor(this.subColor).width('100%').margin({ bottom: 8 })
                }
                Text(I18n.t('wut_card_action_hint')).fontSize(11).fontColor(this.subColor).width('100%').margin({ bottom: 8 })
                ForEach(this.wutStore.wutTargets, (target: WutTarget, index: number) => {
                  WutTargetCard({
                target: target, textColor: this.textColor, subColor: this.subColor, panelColor: this.panelColor,
                titleOf: (item: WutTarget) => this.host.wutTargetTitle(item), subtitleOf: (item: WutTarget) => this.host.wutTargetSubtitle(item),
                typeOf: (type: string) => zhType(type), numberText: (value: number | undefined, digits: number, unit: string) => this.host.fmtNum(value, digits, unit),
                clockText: (value: string | undefined) => this.host.fmtClock(value), onJump: (item: WutTarget) => { this.host.jumpToWutTarget(item) }
              })
                }, (target: WutTarget, index: number) => (target.englishName ?? index.toString()))
                Text('行星（点击跳到中天时刻）').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                ForEach(this.store.tonightAstro!.planets ?? [], (p: TonightPlanet) => {
                  Column({ space: 1 }) {
                    Row() {
                      Text(p.name ?? '').fontSize(11).fontColor(this.textColor).layoutWeight(1)
                      Text((p.visible === true ? '现在可见' : '在地平线下')).fontSize(10)
                        .fontColor((p.visible === true) ? this.accentColor : this.subColor).width(64)
                      Text((p.magnitude ?? 0).toFixed(1) + ' 等').fontSize(10).fontColor(this.subColor).width(52)
                    }.width('100%').padding({ left: 8, right: 8 })
                    Text('升 ' + this.host.fmtClock(p.rise)
                      + '  中天 ' + this.host.fmtClock(p.transit)
                      + '  落 ' + this.host.fmtClock(p.set))
                      .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { if (p.transitJd !== undefined) this.host.callNative('setJD', String(p.transitJd)) })
                }, (p: TonightPlanet, index: number) => index.toString())
                if ((this.store.tonightAstro!.meteorShowers ?? []).length > 0) {
                  Text('活跃流星雨（点击跳到最佳观测时刻）').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                  ForEach(this.store.tonightAstro!.meteorShowers ?? [], (s: TonightShower) => {
                    Row() {
                      Text(s.name ?? '').fontSize(11).fontColor(this.textColor).layoutWeight(1)
                      Text('每小时约 ' + String(s.zhr ?? '?') + ' 颗').fontSize(10).fontColor(this.subColor).width(96)
                    }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
                    .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { if (s.primeJd !== undefined) this.host.callNative('setJD', String(s.primeJd)) })
                  }, (s: TonightShower, index: number) => index.toString())
                }
              }
            } else if (this.store.astroTab === 6) {
              Text(I18n.t('i0131')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 8 })
              Row({ space: 4 }) {
                ForEach(['实时数据', '距离曲线'], (mode: string, index: number) => {
                  Text(mode).fontSize(10)
                    .fontColor(this.store.planetCalcMode === index ? this.textColor : this.subColor)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.store.planetCalcMode === index ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Button(I18n.t('i0243')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadPlanetCalc() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              if (this.store.planetCalcLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(20).height(20).color(this.accentColor)
                  Text('正在计算各行星的实时数据…').fontSize(11).fontColor(this.subColor)
                }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
              } else if (this.store.planetCalcError.length > 0) {
                Text(this.store.planetCalcError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.store.planetCalcData.length === 0) {
                Text('当前没有可显示的行星实时数据。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              }
              ForEach(this.store.planetCalcData, (p: PlanetCalcItem) => {
                Column({ space: 2 }) {
                  Row() {
                    Text(p.name ?? '').fontSize(12).fontColor(this.textColor).layoutWeight(1)
                    Text((p.magnitude ?? 0).toFixed(1) + ' 等').fontSize(10).fontColor(this.subColor).width(52)
                  }.width('100%').padding({ left: 8, right: 8 })
                  Text('赤经 ' + String(p.ra ?? '--') + '   赤纬 ' + String(p.dec ?? '--'))
                    .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  Text('高度 ' + (p.altitude ?? 0).toFixed(1) + '°   方位 ' + (p.azimuth ?? 0).toFixed(1) + '°'
                    + (p.distanceAU !== undefined ? ('   距离 ' + (p.distanceAU ?? 0).toFixed(3) + ' AU') : ''))
                    .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  if (p.elongation !== undefined) {
                    Text('距角 ' + ((p.elongation ?? 0) * 180 / Math.PI).toFixed(1) + '°'
                      + '   相位 ' + ((p.phase ?? 0) * 100).toFixed(0) + '%')
                      .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }
                  if (p.phaseAngleDegrees !== undefined || p.heliocentricDistanceAU !== undefined) {
                    Text((p.phaseAngleDegrees !== undefined ? '相位角 ' + p.phaseAngleDegrees.toFixed(1) + '°' : '')
                      + (p.heliocentricDistanceAU !== undefined ? '   日心距 ' + p.heliocentricDistanceAU.toFixed(3) + ' AU' : ''))
                      .fontSize(10).fontColor('#70FFFFFF').width('100%').padding({ left: 12 })
                  }
                  if (p.illumination !== undefined) {
                    Text('照亮 ' + (p.illumination ?? 0).toFixed(1) + '%   月龄 ' + (p.age ?? 0).toFixed(1) + ' 天')
                      .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }
                  if (p.rise !== undefined) {
                    Text('升 ' + this.host.fmtClock(p.rise)
                      + '  中天 ' + this.host.fmtClock(p.transit)
                      + '  落 ' + this.host.fmtClock(p.set))
                      .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }
                }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.callNative('searchObject', String(p.englishName ?? '')) })
              }, (p: PlanetCalcItem, index: number) => index.toString())
              } else {
                Text('对应桌面版行星计算器的“图表”：蓝色为线性距离，金色为表观角距离；两轴独立缩放。')
                  .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                Text('第一个天体').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Column({ space: 3 }) {
                  ForEach([['Sun', 'Earth', 'Moon', 'Mercury', 'Venus', 'Mars'], ['Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto']], (bodies: Array<string>, row: number) => {
                    Row({ space: 3 }) {
                      ForEach(bodies, (body: string) => {
                        Text(planetPairBodyName(body)).fontSize(10)
                          .fontColor(this.store.planetPairFirst === body ? this.textColor : this.subColor)
                          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                          .backgroundColor(this.store.planetPairFirst === body ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Text('第二个天体').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Column({ space: 3 }) {
                  ForEach([['Sun', 'Earth', 'Moon', 'Mercury', 'Venus', 'Mars'], ['Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Pluto']], (bodies: Array<string>, row: number) => {
                    Row({ space: 3 }) {
                      ForEach(bodies, (body: string) => {
                        Text(planetPairBodyName(body)).fontSize(10)
                          .fontColor(this.store.planetPairSecond === body ? this.textColor : this.subColor)
                          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                          .backgroundColor(this.store.planetPairSecond === body ? '#9C6A24' : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Text('前后范围').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([40, 80, 180], (days: number) => {
                    Text('前后 ' + days.toString() + ' 天').fontSize(10)
                      .fontColor(this.store.planetPairDays === days ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.planetPairDays === days ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
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
                Text('采样步长').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach(this.store.planetPairDays === 40 ? [1, 2, 4, 7] : (this.store.planetPairDays === 80 ? [2, 4, 7] : [4, 7]), (step: number) => {
                    Text(step.toString() + ' 天').fontSize(10)
                      .fontColor(this.store.planetPairStepDays === step ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.planetPairStepDays === step ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.planetPairStepDays !== step) {
                          this.store.planetPairStepDays = step
                          this.host.loadPlanetPairDistance()
                        }
                      })
                  }, (step: number) => step.toString())
                  Button('刷新').fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                    .borderRadius(UI_RADIUS_PILL).height(28).padding({ left: 9, right: 9 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.loadPlanetPairDistance() })
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                if (this.store.planetPairDistanceLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20).color(this.accentColor)
                    Text('正在计算两天体之间的距离变化…').fontSize(11).fontColor(this.subColor)
                  }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
                } else if (this.store.planetPairDistanceError.length > 0) {
                  Text(this.store.planetPairDistanceError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else if (this.store.planetPairDistanceData.length === 0) {
                  Text('尚未生成距离曲线。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else {
                  Text(this.store.planetPairFirstName + ' ↔ ' + this.store.planetPairSecondName + ' · 前后 ' + this.store.planetPairDays.toString() + ' 天')
                    .fontSize(11).fontColor(this.textColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                  Stack({ alignContent: Alignment.Center }) {
                    Row() {
                      ForEach(this.store.planetPairDistanceData, (point: PlanetPairDistancePoint) => {
                        Row({ space: 1 }) {
                          Column().width(this.host.planetPairSegmentWidth())
                            .height(planetPairBarHeight(point.linearDistance, this.store.planetPairLinearMin, this.store.planetPairLinearMax))
                            .backgroundColor(this.accentColor).borderRadius(1)
                          if (this.store.planetPairAngularAvailable) {
                            Column().width(this.host.planetPairSegmentWidth())
                              .height(planetPairBarHeight(point.angularDistance, this.store.planetPairAngularMin, this.store.planetPairAngularMax))
                              .backgroundColor('#E8B24B').borderRadius(1)
                          }
                        }.width(this.host.planetPairBarWidth()).height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                      }, (point: PlanetPairDistancePoint, index: number) => index.toString())
                    }.width('100%').height(96).alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.SpaceBetween)
                  }.width('100%').height(96).padding({ left: 6, right: 6 })
                  Row() {
                    Text('-' + this.store.planetPairDays.toString() + '天').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Start)
                    Text('现在').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.Center)
                    Text('+' + this.store.planetPairDays.toString() + '天').fontSize(10).fontColor(this.subColor).layoutWeight(1).textAlign(TextAlign.End)
                  }.width('100%').padding({ left: 6, right: 6 }).margin({ bottom: 6 })
                  Text(this.store.planetPairAngularAvailable ? '蓝色线性距离：' + this.store.planetPairLinearMin.toFixed(3) + ' - ' + this.store.planetPairLinearMax.toFixed(3) + ' AU；金色角距离：' + this.store.planetPairAngularMin.toFixed(1) + ' - ' + this.store.planetPairAngularMax.toFixed(1) + '°' : '蓝色为线性距离；与观测地球比较时，表观角距离不适用。')
                    .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
                  InfoRow({ label: '当前线性距离', value: planetPairLinearLabel(this.store.planetPairDistanceData[this.host.planetPairCurrentIndex()].linearDistance) })
                  if (this.store.planetPairAngularAvailable) {
                    InfoRow({ label: '当前角距离', value: (this.store.planetPairDistanceData[this.host.planetPairCurrentIndex()].angularDistance ?? 0).toFixed(1) + '°' })
                  }
                }
              }
            } else if (this.store.astroTab === 7) {
              Text(I18n.t('i0132')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 8 })
              Row({ space: 4 }) {
                ForEach(['日月食', '行星凌日'], (label: string, index: number) => {
                  Text(label).fontSize(10).fontColor(this.store.eclipseMode === index ? this.textColor : this.subColor)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.store.eclipseMode === index ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.eclipseMode !== index) {
                        this.store.eclipseMode = index
                        if (index === 0) this.host.loadEclipses()
                        else this.host.loadPlanetaryTransits()
                      }
                    })
                }, (label: string) => label)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 8 })
              if (this.store.eclipseMode === 0) {
              Row({ space: 6 }) {
                Button('计算日月食').fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.reloadEclipses() })
              }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
              Text('预测范围').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach([12, 36, 60], (months: number) => {
                  Text(months === 12 ? '未来 1 年' : '未来 ' + (months / 12).toString() + ' 年').fontSize(10)
                    .fontColor(this.store.eclipseMonths === months ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.eclipseMonths === months ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.eclipseMonths !== months) {
                        this.store.eclipseMonths = months
                        this.host.reloadEclipses()
                      }
                    })
                }, (months: number) => months.toString())
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('开始日期').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Scroll() {
                Row({ space: 4 }) {
                  ForEach([0, 1, 7, 30], (offsetDays: number) => {
                    Text(this.host.eclipseStartOptionLabel(offsetDays)).fontSize(10)
                      .fontColor(this.store.eclipseStartOffsetDays === offsetDays ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.eclipseStartOffsetDays === offsetDays ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.eclipseStartOffsetDays !== offsetDays) {
                          this.store.eclipseStartOffsetDays = offsetDays
                          this.host.reloadEclipses()
                        }
                      })
                  }, (offsetDays: number) => offsetDays.toString())
                  Button(this.store.eclipseStartOffsetDays < 0 ? this.host.eclipseStartOptionLabel(-1) : '指定日期').fontSize(10)
                    .fontColor(this.store.eclipseStartOffsetDays < 0 ? this.textColor : this.subColor)
                    .height(26).padding({ left: 9, right: 9 })
                    .backgroundColor(this.store.eclipseStartOffsetDays < 0 ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.chooseEclipseStartDate() })
                }.padding({ left: 2, right: 2 })
              }.width('100%').height(30).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 6 })
              Text('事件类别').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 4 }) {
                ForEach(['全部', '日食', '月食'], (label: string, index: number) => {
                  Text(label).fontSize(10).fontColor(this.store.eclipseKindFilter === index ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.eclipseKindFilter === index ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.eclipseKindFilter = index })
                }, (label: string) => label)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('食的类型').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
              Row({ space: 3 }) {
                ForEach(['全部', '全食', '环食', '偏食', '半影食'], (label: string, index: number) => {
                  Text(label).fontSize(10).fontColor(this.store.eclipseTypeFilter === index ? this.textColor : this.subColor)
                    .padding({ left: 7, right: 7, top: 4, bottom: 4 })
                    .backgroundColor(this.store.eclipseTypeFilter === index ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.store.eclipseTypeFilter = index })
                }, (label: string) => label)
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              Text('从' + this.host.eclipseStartOptionLabel(this.store.eclipseStartOffsetDays) + '开始的未来 ' + (this.store.eclipseMonths / 12).toString() + ' 年日食与月食（点击可把时间跳到食甚时刻）。')
                .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
              if (this.store.eclipseLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.accentColor)
                  Text('正在推算日月食…').fontSize(11).fontColor(this.subColor)
                }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
              } else if (this.store.eclipseError.length > 0) {
                Text(this.store.eclipseError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.store.eclipseData.length === 0) {
                Text('点击“计算日月食”生成预测。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.host.filteredEclipses().length === 0) {
                Text('当前筛选条件下没有日月食。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              }
              ForEach(this.host.filteredEclipses(), (e: EclipseItem) => {
                Column({ space: 1 }) {
                  Row() {
                    Text(((e.kind === 'solar') ? '日' : '月') + (e.type ?? ''))
                      .fontSize(11).fontColor(this.accentColor).width(56)
                    Text(this.host.fmtDateTime(e.date)).fontSize(11).fontColor(this.textColor).layoutWeight(1)
                    Text('食分 ' + (e.magnitude ?? 0).toFixed(2)).fontSize(10).fontColor(this.subColor).width(62)
                  }.width('100%').padding({ left: 8, right: 8 })
                  if (e.kind === 'solar' && e.saros !== undefined) {
                    Text('沙罗周期 ' + (e.saros ?? 0).toString() + '   ' + (Math.abs(e.pathWidthKm ?? 0) > 0.1
                      ? '中心路径宽 ' + Math.abs(e.pathWidthKm ?? 0).toFixed(0) + ' 千米' : '非中心食'))
                      .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 }).maxLines(1)
                  }
                  if (e.durationMin !== undefined && Math.abs(e.durationMin ?? 0) > 0.001) {
                    Text('中心食持续 ' + Math.abs(e.durationMin ?? 0).toFixed(1) + ' 分钟   中心点 '
                      + (e.centralLat ?? 0).toFixed(1) + '°, ' + (e.centralLng ?? 0).toFixed(1) + '°   路径偏离 ' + (e.gamma ?? 0).toFixed(3))
                      .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }
                  if (e.kind === 'lunar') {
                    Text('沙罗周期 ' + (e.saros ?? 0).toString() + '   路径偏离 ' + (e.gamma ?? 0).toFixed(3)
                      + '   半影食分 ' + (e.penumbralMagnitude ?? 0).toFixed(2)
                      + '   本影食分 ' + (e.umbralMagnitude ?? 0).toFixed(2))
                      .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 }).maxLines(1)
                    Text((e.visibility ?? '本地条件未知') + '   月亮高度 ' + (e.localMoonAltitude ?? 0).toFixed(1) + '°')
                      .fontSize(10).fontColor(this.accentColor).width('100%').padding({ left: 12 })
                  }
                  if (e.kind === 'solar' && e.localVisible === true) {
                    Text('本地食甚 ' + this.host.fmtClock(e.localMax) + '   食分 ' + (e.localMagnitude ?? 0).toFixed(2)
                      + '   太阳高度 ' + (e.localSunAltitude ?? 0).toFixed(1) + '°')
                      .fontSize(10).fontColor(this.accentColor).width('100%').padding({ left: 12 })
                    Text((e.localFirstContactLabel ?? '初亏') + ' ' + this.host.fmtClock(e.localFirstContact)
                      + '   ' + (e.localLastContactLabel ?? '复圆') + ' ' + this.host.fmtClock(e.localLastContact))
                      .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                    if (e.localCentralType !== undefined) {
                      Text('本地' + e.localCentralType + '：' + this.host.fmtClock(e.localCentralStart)
                        + ' - ' + this.host.fmtClock(e.localCentralEnd))
                        .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                    }
                  } else if (e.kind === 'solar' && e.localVisible === false) {
                    Text('本地不可见').fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }
                  if (e.note !== undefined) {
                    Text(e.note ?? '').fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  }
                }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 2 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { if (e.jd !== undefined) this.host.callNative('setJD', String(e.jd)) })
              }, (e: EclipseItem, index: number) => e.jd !== undefined ? e.jd.toFixed(6) : index.toString())
              } else {
                Row({ space: 6 }) {
                  Button('计算行星凌日').fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                    .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      this.store.planetaryTransitData = []
                      this.store.planetaryTransitError = ''
                      this.store.planetaryTransitLoaded = false
                      this.host.loadPlanetaryTransits()
                    })
                }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
                Text('预测范围').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 3 })
                Row({ space: 4 }) {
                  ForEach([5, 20, 50], (years: number) => {
                    Text('未来 ' + years.toString() + ' 年').fontSize(10)
                      .fontColor(this.store.planetaryTransitYears === years ? this.textColor : this.subColor)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                      .backgroundColor(this.store.planetaryTransitYears === years ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                      .borderRadius(UI_RADIUS_CONTROL)
                      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                      .onClick(() => {
                        if (this.store.planetaryTransitYears !== years) {
                          this.store.planetaryTransitYears = years
                          this.store.planetaryTransitData = []
                          this.store.planetaryTransitError = ''
                          this.store.planetaryTransitLoaded = false
                          this.host.loadPlanetaryTransits()
                        }
                      })
                  }, (years: number) => years.toString())
                }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
                Text('水星或金星从太阳圆面前通过。接触时刻和可见时长均按当前观测地点计算。')
                  .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
                if (this.store.planetaryTransitLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(22).height(22).color(this.accentColor)
                    Text('正在推算行星凌日…').fontSize(11).fontColor(this.subColor)
                  }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
                } else if (!this.store.planetaryTransitLoaded) {
                  Text('点击“计算行星凌日”开始推算。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else if (this.store.planetaryTransitError.length > 0) {
                  Text(this.store.planetaryTransitError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                } else if (this.store.planetaryTransitData.length === 0) {
                  Text('未来 ' + this.store.planetaryTransitYears.toString() + ' 年内没有水星或金星凌日。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
                }
                ForEach(this.store.planetaryTransitData, (transit: PlanetaryTransitItem) => {
                  Column({ space: 2 }) {
                    Row() {
                      Text((transit.planet ?? '行星') + '凌日').fontSize(11).fontColor(this.accentColor).width(60)
                      Text(this.host.fmtDateTime(transit.date)).fontSize(11).fontColor(this.textColor).layoutWeight(1)
                      Text('食分 ' + (transit.magnitude ?? 0).toFixed(3)).fontSize(10).fontColor(this.subColor).width(68)
                    }.width('100%').padding({ left: 8, right: 8 })
                    Text('C1 ' + this.host.fmtClock(transit.firstContact) + '   C2 ' + this.host.fmtClock(transit.secondContact)
                      + '   食甚 ' + this.host.fmtClock(transit.middle) + '   C3 ' + this.host.fmtClock(transit.thirdContact) + '   C4 ' + this.host.fmtClock(transit.lastContact))
                      .fontSize(10).fontColor('#CCFFFFFF').width('100%').padding({ left: 12, right: 8 }).maxLines(2)
                    Text('最小距日中心 ' + (transit.minimumSeparation ?? 0).toFixed(3) + '°   全程 ' + (transit.durationMin ?? 0).toFixed(1) + ' 分钟')
                      .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                    if (transit.localVisible === true) {
                      Text('本地可见 ' + (transit.observableDurationMin ?? 0).toFixed(1) + ' 分钟   食甚太阳高度 ' + (transit.sunAltitude ?? 0).toFixed(1) + '°')
                        .fontSize(10).fontColor(this.accentColor).width('100%').padding({ left: 12 })
                    } else {
                      Text('本地不可见（食甚太阳高度 ' + (transit.sunAltitude ?? 0).toFixed(1) + '°）')
                        .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                    }
                  }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { if (transit.jd !== undefined) this.host.callNative('setJD', String(transit.jd)) })
                }, (transit: PlanetaryTransitItem, index: number) => transit.jd !== undefined ? transit.jd.toFixed(6) : index.toString())
              }
            } else if (this.store.astroTab === 8) {
              Text(I18n.t('i0133')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 8 })
              Button(I18n.t('i0240')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.loadAlmanac() })
              if (this.store.almanacLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(20).height(20).color(this.accentColor)
                  Text('正在计算年历…').fontSize(11).fontColor(this.subColor)
                }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
              } else if (this.store.almanacError.length > 0) {
                Text(this.store.almanacError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else if (this.store.almanacData.size === 0) {
                Text('尚未生成年历。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8 })
              } else if (this.store.almanacData.size > 0) {
                if (this.store.almanacSeasons.length > 0) {
                  Text((this.store.almanacSeasonYear.length > 0 ? this.store.almanacSeasonYear + ' 年' : '本年') + '四季节点')
                    .fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                  ForEach(this.store.almanacSeasons, (event: SeasonEvent) => {
                    Row() {
                      Text(event.label ?? '').fontSize(11).fontColor(this.accentColor).width(42)
                      Text(this.host.fmtDateTime(event.date)).fontSize(11).fontColor(this.textColor).layoutWeight(1)
                      Text('持续 ' + (event.durationDays ?? 0).toFixed(1) + ' 天').fontSize(10).fontColor(this.subColor).width(88)
                    }.width('100%').height(28).padding({ left: 8, right: 8 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.jumpToAlmanacSeason(event) })
                  }, (event: SeasonEvent, index: number) => (event.jd ?? index).toString())
                  Row()
                    .width('100%').height(0.5)
                    .backgroundColor(this.lineColor)
                    .margin({ top: 4, bottom: 4 })
                }
                if (this.store.almanacSolarTerms.length > 0) {
                  Text('二十四节气').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                  ForEach(this.store.almanacSolarTerms, (term: SeasonEvent) => {
                    Row() {
                      Text(term.label ?? '').fontSize(11).fontColor(this.accentColor).width(48)
                      Text(this.host.fmtDateTime(term.date)).fontSize(11).fontColor(this.textColor).layoutWeight(1)
                    }.width('100%').height(28).padding({ left: 8, right: 8 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => { this.host.jumpToAlmanacSeason(term) })
                  }, (term: SeasonEvent, index: number) => (term.key ?? (term.jd ?? index)).toString())
                  Row()
                    .width('100%').height(0.5)
                    .backgroundColor(this.lineColor)
                    .margin({ top: 4, bottom: 4 })
                }
                Text(I18n.t('s0372')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                InfoRow({ label: I18n.t('s0365'), value: this.host.jdToDateStr(this.store.almanacData.get('sunRise') ?? '0') })
                InfoRow({ label: I18n.t('s0366'), value: this.host.jdToDateStr(this.store.almanacData.get('sunSet') ?? '0') })
                InfoRow({ label: I18n.t('s0701'), value: this.host.jdToDateStr(this.store.almanacData.get('sunTransit') ?? '0') })
                InfoRow({ label: '昼长', value: this.host.almanacHoursLabel('daylightHours') })
                InfoRow({ label: '夜长', value: this.host.almanacHoursLabel('nightHours') })
                Text('晨昏蒙影').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 8, bottom: 2 })
                InfoRow({ label: '民用晨光', value: this.host.jdToDateStr(this.store.almanacData.get('civilRise') ?? '0') })
                InfoRow({ label: '民用昏影', value: this.host.jdToDateStr(this.store.almanacData.get('civilSet') ?? '0') })
                InfoRow({ label: '航海晨光', value: this.host.jdToDateStr(this.store.almanacData.get('nauticalRise') ?? '0') })
                InfoRow({ label: '航海昏影', value: this.host.jdToDateStr(this.store.almanacData.get('nauticalSet') ?? '0') })
                InfoRow({ label: '天文晨光', value: this.host.jdToDateStr(this.store.almanacData.get('astronomicalRise') ?? '0') })
                InfoRow({ label: '天文昏影', value: this.host.jdToDateStr(this.store.almanacData.get('astronomicalSet') ?? '0') })
                Row()
                  .width('100%').height(0.5)
                  .backgroundColor(this.lineColor)
                  .margin({ top: 4, bottom: 4 })
                Text(I18n.t('s0373')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 2 })
                InfoRow({ label: I18n.t('s0367'), value: this.host.jdToDateStr(this.store.almanacData.get('moonRise') ?? '0') })
                InfoRow({ label: I18n.t('s0368'), value: this.host.jdToDateStr(this.store.almanacData.get('moonSet') ?? '0') })
                InfoRow({ label: I18n.t('s0701'), value: this.host.jdToDateStr(this.store.almanacData.get('moonTransit') ?? '0') })
                InfoRow({ label: I18n.t('s0369'), value: parseFloat(this.store.almanacData.get('moonPhase') ?? '0').toFixed(1) + '%' })
              }
            } else {
              Text('月相预报').fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 2 })
              Text('按月球相对太阳的地心黄经差计算新月、上弦、满月和下弦。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ bottom: 6 })
              Row({ space: 6 }) {
                ForEach([30, 90], (days: number) => {
                  Text('未来 ' + days.toString() + ' 天').fontSize(10)
                    .fontColor(this.store.moonPhaseDays === days ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.store.moonPhaseDays === days ? this.accentColor : this.panelColor).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                    .onClick(() => {
                      if (this.store.moonPhaseDays !== days) {
                        this.store.moonPhaseDays = days
                        this.host.loadMoonPhases()
                      }
                    })
                }, (days: number) => days.toString())
                Button('刷新月相').fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .onClick(() => { this.host.loadMoonPhases() })
              }.width('100%').padding({ left: 2, right: 2 }).margin({ bottom: 6 })
              if (this.store.moonPhaseLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color(this.accentColor)
                  Text('正在计算月相…').fontSize(11).fontColor(this.subColor)
                }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 6 })
              } else if (this.store.moonPhaseError.length > 0) {
                Text(this.store.moonPhaseError).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              } else if (this.store.moonPhaseData.length === 0) {
                Text('点击“刷新月相”生成预报。').fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6 })
              }
              ForEach(this.store.moonPhaseData, (item: MoonPhaseItem) => {
                Column({ space: 2 }) {
                  Row() {
                    Text(item.phase ?? '').fontSize(11).fontColor(this.accentColor).width(56)
                    Text(this.host.fmtDateTime(item.date)).fontSize(11).fontColor(this.textColor).layoutWeight(1)
                    Text('照亮 ' + (item.illumination ?? 0).toFixed(0) + '%').fontSize(10).fontColor(this.subColor).width(70)
                  }.width('100%').padding({ left: 8, right: 8 })
                  Text('高度 ' + (item.altitude ?? 0).toFixed(1) + '°   方位 ' + (item.azimuth ?? 0).toFixed(1) + '°')
                    .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                  Text('升 ' + this.host.fmtClock(item.rise) + '  中天 ' + this.host.fmtClock(item.transit) + '  落 ' + this.host.fmtClock(item.set))
                    .fontSize(10).fontColor('#88FFFFFF').width('100%').padding({ left: 12 })
                }.width('100%').padding({ top: 5, bottom: 5 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                .onClick(() => { this.host.jumpToMoonPhase(item) })
              }, (item: MoonPhaseItem, index: number) => (item.jd ?? index).toString())
            }
          }.width('100%')
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
          .id('astro-content').opacity(this.store.astroContentOpacity).translate({ x: this.store.astroContentOffsetX })
          .onScroll(() => { this.host.publishAstroPanelState() })
    }.width('100%')
  }
}
