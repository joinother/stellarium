// 天文计算面板（astro）域纯数据 store：面板子标签/分组、各计算页回包数据与请求态、日期起始模型等。
// 面板 AstroPanel.ets 以 @ObjectLink 观察本 store；本 store 只保留数据与纯派生，桥加载与请求序号在
// AstroCalcController；跨 store（Wut）与宿主格式化助手经 AstroHostHooks 注入。
// 高频/逐帧或跨域字段（夜视三色、objectDetailStore、wutStore、Scroller）不入本 store。
import { TonightEvents, EphemerisRow, AstroCalcContext, RtsCalendarDay, AltAzPoint, AnnualElevationPoint, ObservabilityDay, LunarElongationPoint, PlanetTimeSeriesPoint, PlanetPairDistancePoint, PlanetCalcItem, PhenomenonItem, EclipseItem, PlanetaryTransitItem, MoonPhaseItem, SeasonEvent, PlanetPosition, HeliocentricPosition, CelestialPosition, WutTarget } from '../pages/StellariumTypes'
import { AstroCsvExport } from '../pages/MainWindowModels'
import { graphModeLabel, graphStartOptionLabel, hourOffsetLabel, planetPairBodyName, planetMetricLabel } from '../common/derive/astro'
import { zhNameOf, planetZh, celestialTitle } from '../common/derive/labels'
import { csvCell } from '../common/derive/skycult'
import { AstroColors } from './StellariumTheme'

// 本域 hooks 接口：store 不 import NAPI/UI，跨 store 与宿主逻辑经具名回调注入。
export interface AstroHostHooks {
  // 跨域读取（objectDetailStore：选中天体）
  hasSelectedObject(): boolean
  selectedObjectName(): string
  // 跨 store 读取（WutStore：astro tab5 摘要 / 今晚观测联动）
  wutCategory(): string
  wutObservationTime(): string
  // 宿主格式化助手
  fmtDateTime(s: string | undefined): string
}

@Observed
export class AstroStore {
  astroTab: number = 5   // 天文计算面板子标签索引
  astroGroup: number = 0 // 天文计算一级导航分组
  astroContentOpacity: number = 1
  astroContentOffsetX: number = 0
  rtsData: Map<string, string> = new Map()
  rtsError: string = ''
  rtsLoading: boolean = false
  rtsCalendarData: Array<RtsCalendarDay> = []
  rtsCalendarName: string = ''
  rtsCalendarError: string = ''
  rtsCalendarDays: number = 14
  rtsCalendarStartOffsetDays: number = 0
  // RTS 日历「指定日期」起始模型。
  rtsCalendarStartYear: number = new Date().getFullYear()
  rtsCalendarStartMonth: number = new Date().getMonth() + 1
  rtsCalendarStartDay: number = new Date().getDate()
  rtsCalendarLoading: boolean = false
  rtsCalendarNeedsGeneration: boolean = false
  rtsCalendarProgress: number = 0
  rtsCalendarTotalDays: number = 0
  almanacData: Map<string, string> = new Map()
  almanacLoading: boolean = false
  almanacError: string = ''
  almanacSeasons: Array<SeasonEvent> = []
  almanacSolarTerms: Array<SeasonEvent> = []
  almanacSeasonYear: string = ''
  planetPositions: Array<PlanetPosition> = []
  planetPositionsLoading: boolean = false
  planetPositionsError: string = ''
  positionMode: number = 0
  hecPositions: Array<HeliocentricPosition> = []
  hecPositionsLoading: boolean = false
  hecPositionsError: string = ''
  hecTime: string = ''
  hecIncludeSelectedMinor: boolean = false
  hecIncludeBrightComets: boolean = false
  hecCometMagnitudeLimit: number = 9
  celestialPositions: Array<CelestialPosition> = []
  celestialPositionsLoading: boolean = false
  celestialPositionsError: string = ''
  celestialPositionCategory: string = 'planets'
  celestialPositionMagnitude: number = 6
  celestialPositionHorizontal: boolean = true
  celestialPositionTime: string = ''
  ephemerisData: Array<EphemerisRow> = []
  ephemerisName: string = ''
  ephemerisMeta: string = ''
  ephemerisError: string = ''
  ephemerisDays: number = 14
  ephemerisStepHours: number = 24
  ephemerisStartOffsetDays: number = 0
  ephemerisMode: number = 0
  ephemerisPrimary: string = 'Moon'
  ephemerisSecondary: string = 'Sun'
  ephemerisLoading: boolean = false
  planetCalcData: Array<PlanetCalcItem> = []
  planetCalcLoading: boolean = false
  planetCalcError: string = ''
  planetCalcMode: number = 0
  planetPairDistanceData: Array<PlanetPairDistancePoint> = []
  planetPairDistanceError: string = ''
  planetPairDistanceLoading: boolean = false
  planetPairFirst: string = 'Sun'
  planetPairSecond: string = 'Moon'
  planetPairFirstName: string = '太阳'
  planetPairSecondName: string = '月亮'
  planetPairDays: number = 40
  planetPairStepDays: number = 4
  planetPairAngularAvailable: boolean = true
  planetPairLinearMin: number = 0
  planetPairLinearMax: number = 1
  planetPairAngularMin: number = 0
  planetPairAngularMax: number = 180
  altAzCurve: Array<AltAzPoint> = []
  altAzName: string = ''
  altAzError: string = ''
  altAzHours: number = 24
  altAzStepMin: number = 30
  altAzShowSun: boolean = false
  altAzShowMoon: boolean = false
  altAzMinimum: number = -90
  graphStartOffsetDays: number = 0
  // 年度高度图「指定日期」起始模型。
  graphStartYear: number = new Date().getFullYear()
  graphStartMonth: number = new Date().getMonth() + 1
  graphStartDay: number = new Date().getDate()
  graphMode: number = 0
  graphLoading: boolean = false
  annualElevationData: Array<AnnualElevationPoint> = []
  annualElevationName: string = ''
  annualElevationError: string = ''
  annualElevationHour: number = 0
  annualElevationMinimum: number = -90
  observabilityData: Array<ObservabilityDay> = []
  observabilityName: string = ''
  observabilityError: string = ''
  observabilityProgress: string = ''
  observabilityDays: number = 30
  observabilityMinAltitude: number = 20
  lunarElongationData: Array<LunarElongationPoint> = []
  lunarElongationName: string = ''
  lunarElongationError: string = ''
  lunarElongationDays: number = 30
  lunarElongationStepHours: number = 12
  lunarElongationLimit: number = 40
  planetTimeSeriesData: Array<PlanetTimeSeriesPoint> = []
  planetTimeSeriesName: string = ''
  planetTimeSeriesError: string = ''
  planetTimeSeriesDays: number = 30
  planetTimeSeriesStepHours: number = 24
  planetTimeSeriesLeftMetric: string = 'angularSize'
  planetTimeSeriesRightMetric: string = 'magnitude'
  planetTimeSeriesLeftMin: number = 0
  planetTimeSeriesLeftMax: number = 1
  planetTimeSeriesRightMin: number = 0
  planetTimeSeriesRightMax: number = 1
  eclipseData: Array<EclipseItem> = []
  eclipseMonths: number = 36
  eclipseStartOffsetDays: number = 0
  eclipseStartYear: number = new Date().getFullYear()
  eclipseStartMonth: number = new Date().getMonth() + 1
  eclipseStartDay: number = new Date().getDate()
  eclipseLoading: boolean = false
  eclipseError: string = ''
  eclipseKindFilter: number = 0
  eclipseTypeFilter: number = 0
  eclipseMode: number = 0
  planetaryTransitData: Array<PlanetaryTransitItem> = []
  planetaryTransitYears: number = 20
  planetaryTransitLoaded: boolean = false
  planetaryTransitLoading: boolean = false
  planetaryTransitError: string = ''
  moonPhaseData: Array<MoonPhaseItem> = []
  moonPhaseDays: number = 30
  moonPhaseLoading: boolean = false
  moonPhaseError: string = ''
  phenomenaData: Array<PhenomenonItem> = []
  phenomenaHint: string = ''
  phenomenaLoading: boolean = false
  phenomenaPrimary: string = 'all'
  phenomenaTarget: string = 'all'
  phenomenaDays: number = 400
  phenomenaStartOffsetMonths: number = 0
  phenomenaMaxSeparation: number = 4
  phenomenaIncludeOppositions: boolean = true
  phenomenaIncludePerihelionAphelion: boolean = true
  phenomenaIncludeElongationsQuadratures: boolean = true
  phenomenaIncludeStations: boolean = true
  astroExporting: boolean = false
  astroContext: AstroCalcContext | undefined = undefined
  astroCalcSnapshot: string = ''
  tonightAstro: TonightEvents | null = null

  // 宿主在 aboutToAppear 注入纯跨域读取 / 格式化 hooks；桥与请求序号在 AstroCalcController。
  private hooks: AstroHostHooks | null = null

  attachHooks(hooks: AstroHostHooks): void {
    this.hooks = hooks
  }

  private hasSelected(): boolean {
    const hooks = this.hooks
    return hooks !== null && hooks.hasSelectedObject()
  }

  graphTargetLabel(): string {
    const hooks = this.hooks
    if (hooks === null) {
      return '尚未选择天体'
    }
    const name = hooks.selectedObjectName()
    if (name.length === 0) {
      return '尚未选择天体'
    }
    return zhNameOf(name)
  }

  phenomenaBodyName(body: string): string {
    return body === 'all' ? '全部行星' : planetPairBodyName(body)
  }

  updateAstroCalcSnapshot(): void {
    if (this.astroTab === 0) {
      const mode = this.positionMode === 0 ? '地平位置' : (this.positionMode === 1 ? '日心黄道' : '目录天体')
      this.astroCalcSnapshot = mode + (this.positionMode === 2 ? ' · 星等 ≤ ' + this.celestialPositionMagnitude.toFixed(1) : '')
      return
    }
    if (this.astroTab === 1) {
      const target = this.ephemerisMode === 0 ? '当前选中天体' : (this.ephemerisMode === 1 ? '两个天体' : '全部肉眼行星')
      this.astroCalcSnapshot = target + ' · ' + this.ephemerisDays.toString() + ' 天 · 每 ' + this.ephemerisStepHours.toString() + ' 小时'
      return
    }
    if (this.astroTab === 2) {
      this.astroCalcSnapshot = '升中天落 · ' + this.rtsCalendarDays.toString() + ' 天 · ' + (this.hasSelected() ? this.graphTargetLabel() : '未选择天体')
      return
    }
    if (this.astroTab === 3) {
      this.astroCalcSnapshot = this.phenomenaBodyName(this.phenomenaPrimary) + ' / ' + this.phenomenaBodyName(this.phenomenaTarget) + ' · ' + this.phenomenaDays.toString() + ' 天'
      return
    }
    if (this.astroTab === 4) {
      let detail = ''
      if (this.graphMode === 0 || this.graphMode === 1) {
        detail = this.altAzHours.toString() + ' 小时 · 每 ' + this.altAzStepMin.toString() + ' 分钟'
      } else if (this.graphMode === 2) {
        detail = '每日 ' + this.annualElevationHour.toString().padStart(2, '0') + ':00'
      } else if (this.graphMode === 3) {
        detail = this.observabilityDays.toString() + ' 天 · 最低 ' + this.observabilityMinAltitude.toString() + '°'
      } else if (this.graphMode === 4) {
        detail = this.lunarElongationDays.toString() + ' 天 · 每 ' + this.lunarElongationStepHours.toString() + ' 小时'
      } else {
        detail = this.planetTimeSeriesDays.toString() + ' 天 · 每 ' + this.planetTimeSeriesStepHours.toString() + ' 小时'
      }
      this.astroCalcSnapshot = graphModeLabel(this.graphMode) + ' · ' + this.graphTargetLabel() + ' · '
        + graphStartOptionLabel(this.graphStartOffsetDays) + ' · ' + detail
      return
    }
    if (this.astroTab === 5) {
      const hooks = this.hooks
      this.astroCalcSnapshot = '今晚可观测 · ' + (hooks !== null ? hooks.wutCategory() : '') + ' · ' + (hooks !== null ? hooks.wutObservationTime() : '')
      return
    }
    if (this.astroTab === 6) {
      this.astroCalcSnapshot = this.planetCalcMode === 0 ? '行星实时位置' : planetPairBodyName(this.planetPairFirst)
        + ' / ' + planetPairBodyName(this.planetPairSecond) + ' · ' + this.planetPairDays.toString() + ' 天'
      return
    }
    if (this.astroTab === 7) {
      this.astroCalcSnapshot = (this.eclipseMode === 0 ? '日月食' : '行星凌日') + ' · ' + (this.eclipseMode === 0 ? this.eclipseMonths.toString() + ' 个月' : this.planetaryTransitYears.toString() + ' 年')
      return
    }
    if (this.astroTab === 9) {
      this.astroCalcSnapshot = '月相 · 未来 ' + this.moonPhaseDays.toString() + ' 天'
      return
    }
    if (this.astroTab === 8) {
      this.astroCalcSnapshot = '年历 · 当前模拟日期 · 当前观测地点'
      return
    }
    this.astroCalcSnapshot = ''
  }

  // ===== 派生取值方法（读本 store 字段生成展示文本）=====

  makeAstroCsv(exportData: AstroCsvExport): string {
    const lines: Array<string> = []
    lines.push('# ' + exportData.title)
    const hooks = this.hooks
    if (this.astroContext !== undefined) {
      const location = this.astroContext.observerLocation !== undefined && this.astroContext.observerLocation.length > 0
        ? this.astroContext.observerLocation : '当前观测位置'
      lines.push('# 观测地点: ' + location)
      lines.push('# 本地时间: ' + (hooks !== null ? hooks.fmtDateTime(this.astroContext.localTime) : '--'))
      lines.push('# 时区: ' + (this.astroContext.timeZone ?? '--'))
      lines.push('# 平恒星时: ' + (this.astroContext.meanSiderealTime ?? '--'))
      lines.push('# 视恒星时: ' + (this.astroContext.apparentSiderealTime ?? '--'))
    }
    if (this.astroCalcSnapshot.length > 0) lines.push('# 参数: ' + this.astroCalcSnapshot)
    lines.push(exportData.headers.map((header: string) => csvCell(header)).join(','))
    for (const row of exportData.rows) {
      lines.push(row.map((cell: string | number | boolean | undefined) => csvCell(cell)).join(','))
    }
    return lines.join('\r\n') + '\r\n'
  }

  filteredEclipses(): Array<EclipseItem> {
    const filtered: Array<EclipseItem> = []
    for (const eclipse of this.eclipseData) {
      if (this.eclipseKindFilter === 1 && eclipse.kind !== 'solar') continue
      if (this.eclipseKindFilter === 2 && eclipse.kind !== 'lunar') continue
      const type = eclipse.type ?? ''
      if (this.eclipseTypeFilter === 1 && type !== '全食') continue
      if (this.eclipseTypeFilter === 2 && type !== '环食') continue
      if (this.eclipseTypeFilter === 3 && type !== '偏食') continue
      if (this.eclipseTypeFilter === 4 && type !== '半影食') continue
      filtered.push(eclipse)
    }
    return filtered
  }

  altAzMaxLabel(): string {
    let m: number = -999
    let t: number = 0
    for (let i = 0; i < this.altAzCurve.length; i++) {
      const p: AltAzPoint = this.altAzCurve[i]
      const v: number = p.altitude !== undefined ? p.altitude : -999
      if (v > m) { m = v; t = p.t !== undefined ? p.t : 0 }
    }
    if (m < -90) return '--'
    return m.toFixed(1) + '°（' + hourOffsetLabel(t) + '）'
  }

  altAzVisibleHours(): string {
    let hours: number = 0
    for (let i = 0; i + 1 < this.altAzCurve.length; i++) {
      const p: AltAzPoint = this.altAzCurve[i]
      const next: AltAzPoint = this.altAzCurve[i + 1]
      if (p.altitude !== undefined && p.altitude > 0 && p.t !== undefined && next.t !== undefined) {
        hours += next.t - p.t
      }
    }
    return hours.toFixed(1) + ' 小时'
  }

  altAzNowLabel(): string {
    if (this.altAzCurve.length === 0) return '--'
    const p: AltAzPoint = this.altAzCurve[0]
    const alt: number = p.altitude !== undefined ? p.altitude : 0
    const az: number = p.azimuth !== undefined ? p.azimuth : 0
    return '高度 ' + alt.toFixed(1) + '° / 方位 ' + az.toFixed(1) + '°'
  }

  annualMaxLabel(): string {
    let maximum: number = -91
    let date: string = ''
    for (const point of this.annualElevationData) {
      const altitude: number = point.altitude ?? -91
      if (altitude > maximum) {
        maximum = altitude
        date = point.date ?? ''
      }
    }
    return maximum < -90 ? '--' : maximum.toFixed(1) + '°（' + (date.length >= 10 ? date.slice(5) : date) + '）'
  }

  lunarElongationClosestLabel(): string {
    let closest: number = 181
    let time: number = 0
    for (const point of this.lunarElongationData) {
      const separation: number = point.separation ?? 181
      if (separation < closest) {
        closest = separation
        time = point.t ?? 0
      }
    }
    return closest > 180 ? '--' : closest.toFixed(1) + '°（' + hourOffsetLabel(time) + '）'
  }

  rtsCalendarStartOptionLabel(offsetDays: number): string {
    if (offsetDays < 0) {
      return this.rtsCalendarStartYear.toString() + '-' + this.rtsCalendarStartMonth.toString().padStart(2, '0') + '-' + this.rtsCalendarStartDay.toString().padStart(2, '0')
    }
    if (offsetDays === 0) return '当前'
    return '+' + offsetDays.toString() + ' 天'
  }

  eclipseStartOptionLabel(offsetDays: number): string {
    if (offsetDays < 0) {
      return this.eclipseStartYear.toString() + '-' + this.eclipseStartMonth.toString().padStart(2, '0') + '-' + this.eclipseStartDay.toString().padStart(2, '0')
    }
    if (offsetDays === 0) return '当前'
    return '+' + offsetDays.toString() + ' 天'
  }

  graphCustomStartLabel(): string {
    if (this.graphStartOffsetDays >= 0) return '指定日期'
    return this.graphStartYear.toString() + '-' + this.graphStartMonth.toString().padStart(2, '0') + '-' + this.graphStartDay.toString().padStart(2, '0')
  }

  // 当前星历 / 日历页是否必须先选中天体。
  astroNeedsSelectedObject(): boolean {
    if (this.astroTab === 2 || this.astroTab === 4) return true
    if (this.astroTab === 1 && this.ephemerisMode < 2) return true
    if (this.astroTab === 6 && this.planetCalcMode === 1) return false
    return false
  }

  // ---- 当前页的 CSV 导出模型 ----
  astroCsvExport(wutTargets: WutTarget[], wutObservationTime: string): AstroCsvExport | undefined {
    if (this.astroTab === 0) {
      if (this.positionMode === 0 && this.planetPositions.length > 0) {
        return { title: '地平位置', headers: ['天体', '赤经(当日)', '赤纬(当日)', '高度(度)', '方位(度)', '星等', '距离(AU)', '视直径(角分)', '中天'],
          rows: this.planetPositions.map((item: PlanetPosition) => [planetZh(item.name), item.rightAscension, item.declination, item.altitude, item.azimuth, item.magnitude, item.distanceAU, item.angularSizeArcmin, item.transit]) }
      }
      if (this.positionMode === 1 && this.hecPositions.length > 0) {
        return { title: '日心黄道位置', headers: ['天体', '英文名', '黄纬(度)', '黄经(度)', '日心距离(AU)', '彗星', '已选小天体'],
          rows: this.hecPositions.map((item: HeliocentricPosition) => [celestialTitle(item.name, item.englishName), item.englishName, item.latitude, item.longitude, item.distanceAU, item.isComet, item.isSelectedMinor]) }
      }
      if (this.positionMode === 2 && this.celestialPositions.length > 0) {
        return { title: '目录天体位置', headers: ['天体', '英文名', '目录编号', '坐标一', '坐标二', '高度(度)', '方位(度)', '星等', '类型', '距日(度)', '视直径(角分)', '距离(AU)', '中天'],
          rows: this.celestialPositions.map((item: CelestialPosition) => [celestialTitle(item.name, item.englishName), item.englishName, item.catalogId, item.firstCoordinate, item.secondCoordinate, item.altitude, item.azimuth, item.magnitude, item.type, item.elongation, item.angularSizeArcmin, item.distanceAU, item.transit]) }
      }
    } else if (this.astroTab === 1 && this.ephemerisData.length > 0) {
      return { title: (this.ephemerisName.length > 0 ? this.ephemerisName : '天体') + '星历', headers: ['日期时间', '天体', '英文名', '赤经(J2000)', '赤纬(J2000)', '赤经(当日)', '赤纬(当日)', '高度(度)', '方位(度)', '时角(度)', '极距(度)', '星等', '相位(%)', '距离(AU)', '距日(度)', '视直径(角分)', '气团质量'],
        rows: this.ephemerisData.map((item: EphemerisRow) => [item.date, item.bodyName, item.bodyEnglishName, item.ra, item.dec, item.raOfDate, item.decOfDate, item.altitude, item.azimuth, item.hourAngleDegrees, item.polarDistanceDegrees, item.magnitude, item.phase !== undefined ? item.phase * 100 : undefined, item.distanceAU, item.elongationDegrees, item.angularSizeArcmin, item.airmass]) }
    } else if (this.astroTab === 2 && this.rtsCalendarData.length > 0) {
      return { title: (this.rtsCalendarName.length > 0 ? this.rtsCalendarName : '天体') + '升中天落日期表', headers: ['日期', '升起', '中天', '落下', '中天高度(度)', '星等', '距日(度)', '距月(度)', '状态'],
        rows: this.rtsCalendarData.map((item: RtsCalendarDay) => [item.date, item.rise, item.transit, item.set, item.transitAltitude, item.magnitude, item.solarElongation, item.lunarElongation, item.status]) }
    } else if (this.astroTab === 3 && this.phenomenaData.length > 0) {
      return { title: '天象预报', headers: ['日期时间', '事件', '天体一', '天体二', '数值', '指标', '单位'],
        rows: this.phenomenaData.map((item: PhenomenonItem) => [item.date, item.type, item.bodyA, item.bodyB, item.separation, item.metricLabel, item.metricUnit]) }
    } else if (this.astroTab === 4) {
      if ((this.graphMode === 0 || this.graphMode === 1) && this.altAzCurve.length > 0) {
        return { title: this.altAzName + (this.graphMode === 0 ? '地平高度曲线' : '方位角曲线'), headers: ['儒略日', '距起点(小时)', '高度(度)', '方位(度)', '太阳高度(度)', '月亮高度(度)'],
          rows: this.altAzCurve.map((item: AltAzPoint) => [item.jd, item.t, item.altitude, item.azimuth, item.sunAltitude, item.moonAltitude]) }
      }
      if (this.graphMode === 2 && this.annualElevationData.length > 0) {
        return { title: this.annualElevationName + '全年高度', headers: ['日期', '儒略日', '高度(度)', '方位(度)'],
          rows: this.annualElevationData.map((item: AnnualElevationPoint) => [item.date, item.jd, item.altitude, item.azimuth]) }
      }
      if (this.graphMode === 3 && this.observabilityData.length > 0) {
        return { title: this.observabilityName + '观测窗口', headers: ['日期', '最佳时刻', '最高高度(度)', '可观测时长(小时)', '暗夜时长(小时)', '月面照明(%)', '月亮高度(度)'],
          rows: this.observabilityData.map((item: ObservabilityDay) => [item.date, item.peakTime, item.maxAltitude, item.visibleHours, item.darkHours, item.moonIllumination, item.moonAltitude]) }
      }
      if (this.graphMode === 4 && this.lunarElongationData.length > 0) {
        return { title: this.lunarElongationName + '月距曲线', headers: ['日期时间', '儒略日', '距起点(小时)', '月距(度)'],
          rows: this.lunarElongationData.map((item: LunarElongationPoint) => [item.date, item.jd, item.t, item.separation]) }
      }
      if (this.graphMode === 5 && this.planetTimeSeriesData.length > 0) {
        return { title: this.planetTimeSeriesName + '双变量时间曲线', headers: ['日期时间', '儒略日', '距起点(小时)', planetMetricLabel(this.planetTimeSeriesLeftMetric), planetMetricLabel(this.planetTimeSeriesRightMetric)],
          rows: this.planetTimeSeriesData.map((item: PlanetTimeSeriesPoint) => [item.date, item.jd, item.t, item.left, item.right]) }
      }
    } else if (this.astroTab === 5 && wutTargets.length > 0) {
      return { title: '今晚可观测天体', headers: ['天体', '英文名', '类型', '观测时刻', '高度(度)', '方位(度)', '星等', '角尺寸(角分)', '升起', '中天', '落下'],
        rows: wutTargets.map((item: WutTarget) => [zhNameOf(item.name ?? ''), item.englishName, item.type, wutObservationTime, item.altitude, item.azimuth, item.magnitude, item.angularSizeArcmin, item.rise, item.transit, item.set]) }
    } else if (this.astroTab === 6) {
      if (this.planetCalcMode === 0 && this.planetCalcData.length > 0) {
        return { title: '行星计算', headers: ['天体', '英文名', '赤经', '赤纬', '高度(度)', '方位(度)', '星等', '距离(AU)', '距日(度)', '相位(%)', '升起', '中天', '落下'],
          rows: this.planetCalcData.map((item: PlanetCalcItem) => [item.name, item.englishName, item.ra, item.dec, item.altitude, item.azimuth, item.magnitude, item.distanceAU, item.elongation, item.phase !== undefined ? item.phase * 100 : undefined, item.rise, item.transit, item.set]) }
      }
      if (this.planetCalcMode === 1 && this.planetPairDistanceData.length > 0) {
        return { title: this.planetPairFirstName + '与' + this.planetPairSecondName + '距离曲线', headers: ['日期时间', '儒略日', '距起点(天)', '线性距离(AU)', '角距离(度)'],
          rows: this.planetPairDistanceData.map((item: PlanetPairDistancePoint) => [item.date, item.jd, item.t, item.linearDistance, item.angularDistance]) }
      }
    } else if (this.astroTab === 7) {
      if (this.eclipseMode === 0 && this.filteredEclipses().length > 0) {
        return { title: '日月食预报', headers: ['日期时间', '类别', '类型', '食分', '沙罗周期', '本地可见', '本地食甚', '太阳高度(度)', '月亮高度(度)', '备注'],
          rows: this.filteredEclipses().map((item: EclipseItem) => [item.date, item.kind, item.type, item.magnitude, item.saros, item.localVisible, item.localMax, item.localSunAltitude, item.localMoonAltitude, item.note]) }
      }
      if (this.eclipseMode === 1 && this.planetaryTransitData.length > 0) {
        return { title: '行星凌日预报', headers: ['日期时间', '行星', '初亏', '内切始', '食甚', '内切终', '复圆', '食分', '最小距日心(度)', '持续(分钟)', '本地可见'],
          rows: this.planetaryTransitData.map((item: PlanetaryTransitItem) => [item.date, item.planet, item.firstContact, item.secondContact, item.middle, item.thirdContact, item.lastContact, item.magnitude, item.minimumSeparation, item.durationMin, item.localVisible]) }
      }
    } else if (this.astroTab === 8 && this.almanacData.size > 0) {
      const rows: Array<Array<string | number | boolean | undefined>> = []
      this.almanacData.forEach((value: string, key: string) => { rows.push([key, value]) })
      for (const event of this.almanacSeasons) rows.push(['四季节点：' + (event.label ?? ''), event.date])
      return { title: '历法与月相', headers: ['项目', '数值'], rows: rows }
    } else if (this.astroTab === 9 && this.moonPhaseData.length > 0) {
      return { title: '月相预报', headers: ['日期时间', '月相', '照亮(%)', '高度(度)', '方位(度)', '升起', '中天', '落下'],
        rows: this.moonPhaseData.map((item: MoonPhaseItem) => [item.date, item.phase, item.illumination, item.altitude, item.azimuth, item.rise, item.transit, item.set]) }
    }
    return undefined
  }

  // ---- 天文图表尺寸 / 标签族 ----
  altAzRangeLabel(): string {
    return '未来 ' + this.altAzHours.toString() + ' 小时'
  }

  altAzMidpointLabel(): string {
    return '+' + (this.altAzHours / 2).toString() + 'h'
  }

  altBarWidth(): number {
    if (this.altAzCurve.length === 0) return 4
    return Math.max(1, Math.min(4, 292 / this.altAzCurve.length))
  }

  altBarHeight(alt: number | undefined): number {
    const a: number = alt !== undefined ? alt : -90
    if (a < this.altAzMinimum) return 1
    const range: number = 90 - this.altAzMinimum
    return Math.max(1, Math.min(96, (a - this.altAzMinimum) / range * 96))
  }

  altitudeCurveColor(altitude: number | undefined, color: ResourceColor): ResourceColor {
    return (altitude ?? -90) >= this.altAzMinimum ? color : AstroColors.altitudeFaded
  }

  altCurveSegmentWidth(): number {
    let count: number = 1
    if (this.altAzShowSun) count++
    if (this.altAzShowMoon) count++
    return Math.max(1, (this.altBarWidth() - Math.max(0, count - 1)) / count)
  }

  annualBarHeight(altitude: number | undefined): number {
    const value: number = altitude !== undefined ? altitude : -90
    if (value < this.annualElevationMinimum) return 1
    const range: number = 90 - this.annualElevationMinimum
    return Math.max(1, Math.min(96, (value - this.annualElevationMinimum) / range * 96))
  }

  annualBarWidth(): number {
    if (this.annualElevationData.length === 0) return 3
    return Math.max(1, Math.min(6, 292 / this.annualElevationData.length))
  }

  azimuthNowLabel(): string {
    if (this.altAzCurve.length === 0) return '--'
    return (this.altAzCurve[0].azimuth ?? 0).toFixed(1) + '°'
  }

  lunarElongationBarWidth(): number {
    if (this.lunarElongationData.length === 0) return 4
    return Math.max(1, Math.min(4, 292 / this.lunarElongationData.length))
  }

  lunarElongationLineTop(): number {
    return Math.max(0, Math.min(95, (1 - this.lunarElongationLimit / 180) * 96))
  }

  lunarElongationNowLabel(): string {
    if (this.lunarElongationData.length === 0) return '--'
    return (this.lunarElongationData[0].separation ?? 0).toFixed(1) + '°'
  }

  planetTimeSeriesBarWidth(): number {
    if (this.planetTimeSeriesData.length === 0) return 4
    return Math.max(2, Math.min(6, 292 / this.planetTimeSeriesData.length))
  }

  planetTimeSeriesSegmentWidth(): number {
    return Math.max(1, (this.planetTimeSeriesBarWidth() - 1) / 2)
  }

  planetPairBarWidth(): number {
    if (this.planetPairDistanceData.length === 0) return 4
    return Math.max(2, Math.min(6, 292 / this.planetPairDistanceData.length))
  }

  planetPairSegmentWidth(): number {
    return Math.max(1, (this.planetPairBarWidth() - 1) / 2)
  }

  planetPairCurrentIndex(): number {
    return Math.floor(this.planetPairDistanceData.length / 2)
  }

  almanacHoursLabel(key: string): string {
    const value = this.almanacData.get(key) ?? ''
    return value.length > 0 ? parseFloat(value).toFixed(1) + ' 小时' : '--'
  }
}
