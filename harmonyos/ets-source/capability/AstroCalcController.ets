// 天文计算（astro）行为控制器：负责 RTS/星历/高度曲线/可观测日历/食相/月相/季节等
// 全部桥加载（load* / reload* / mark* / cancel* / loadAstroTab）、
// 计算面板的日期与行跳转、目标选择器路由、标签切换动画编排、上下文轮询、行星位置刷新、
// 大气参数写回与当前页 CSV 导出。
// 依赖 CommandPort、FileExportPort（picker/fileIo）、AstroStore / EphemerisStore / WutStore /
// SearchStore；DatePicker、animateTo、Scroller、壳层路由与保留宿主方法经 AstroCalcHostHooks 回注。
// 定时器 astroContextTimer 由控制器自持；纯格式化工具（fmtDateTime/fmtClock/fmtEphemerisDate/fmtNum）
// 留此供本控制器与 AstroHostHooks.fmtDateTime 复用同一实现。
import { StellariumBridgeResponse, EphemerisRow, RtsCalendarDay, ObservabilityDay, PhenomenonItem, WutTarget, MoonPhaseItem, SeasonEvent, PlanetPosition, TabItem, TonightEvents, AstroCalcContext, AltAzPoint, AnnualElevationPoint, LunarElongationPoint, PlanetTimeSeriesPoint, PlanetPairDistancePoint, PlanetCalcItem, EclipseItem, PlanetaryTransitItem, HeliocentricPosition, CelestialPosition } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { FileExportPort, MediaSaveResult } from '../bridge/MediaPort'
import { EphemerisOptions, RtsCalendarOptions, EclipseOptions, PhenomenaOptions, HeliocentricPositionOptions, CelestialPositionOptions } from '../pages/MainWindowModels'
import { AstroStore } from '../state/AstroStore'
import { EphemerisStore } from '../state/EphemerisStore'
import { WutStore } from '../state/WutStore'
import { SearchStore } from '../state/SearchStore'
import { astroTabItemsForGroup, astroGroupForTab, dateToJD, planetPairBodyName } from '../common/derive/astro'
import { BehaviorHostHooks } from './ControllerHooks'

// 宿主 → 控制器回注：UI（DatePicker / animateTo / Scroller）、壳层路由与保留宿主方法。
export interface AstroCalcHostHooks extends BehaviorHostHooks {
  // 保留的 CLI 发布点（宿主 publishAstroPanelState，写 AppStorage）。
  publishAstroPanelState(): void
  // 天文面板是否处于前台上下文（applicationInForeground && activePanel==='astro' && panelVisible）。
  astroPanelContextActive(): boolean
  // 天文面板是否在屏（panelVisible && activePanel==='astro'，供 tab 过渡判定）。
  astroPanelOnScreen(): boolean
  // 标签切换后把天文面板滚回顶部（宿主 astroPanelScroller.scrollTo）。
  scrollAstroPanelToTop(): void
  // tab 切换完成后的持久化（宿主 saveAppSettings）。
  saveAppSettings(): void
  // 标签切换两段动画（宿主 getUIContext().animateTo；curve 由宿主按原调用点固定）。
  animateAstroIn(durationMs: number, onFinish: () => void, action: () => void): void
  animateAstroOut(durationMs: number, onFinish: () => void, action: () => void): void
  // 「指定日期」DatePickerDialog（宿主 getUIContext().showDatePickerDialog；控制器不触碰 UI）。
  showDatePicker(selected: Date, onAccept: (year: number | undefined, month: number | undefined, day: number | undefined) => void): void
  // WUT 目标跳转的选中放置（宿主保留方法 applySelectedObject，SelectionService 族）。
  applySelectedObject(result: StellariumBridgeResponse, fromRefresh: boolean, placement: string, userReselect: boolean): void
  // 目标选择器路由到搜索面板（壳层路由，保留宿主）。
  setPanel(panel: string): void
  // 大气参数回包写入 AtmosphereStore（保留宿主实现，与 TimeStore 共用）。
  applyAtmosphereResponse(result: StellariumBridgeResponse): void
  // 桥加载器不能直接读取的宿主量：选中天体与日心位置几何布局。
  hasSelectedObject(): boolean
  selectedObjectName(): string
  hecLayoutPositions(positions: Array<HeliocentricPosition>): Array<HeliocentricPosition>
  // 平滑前往目标时刻（宿主 TimeTransitionController）；onFinished 在到达后回调。
  animateTimeToJd(targetJd: number, label: string, onFinished?: () => void): void
  // 年历加载完成后刷新桌面卡片快照（宿主 AstronomyCardService.publishAstronomyCard）。
  persistAlmanacCardSnapshot(): void
}

export class AstroCalcController {
  private port: CommandPort
  private media: FileExportPort
  private astroStore: AstroStore
  private ephemerisStore: EphemerisStore
  private wutStore: WutStore
  private searchStore: SearchStore
  private hooks: AstroCalcHostHooks
  // 草稿/瞬时字段随控制器，不入 @Observed store。
  private astroTransitionId: number = 0
  private astroRequestedTab: number = -1
  private planetPositionsRequestSequence: number = 0
  private graphTargetPickerActive: boolean = false
  private rtsTargetPickerActive: boolean = false
  private ephemerisTargetPickerActive: boolean = false
  private astroContextTimer: number = 0
  // —— 桥加载器的请求序号 / 代际 ——
  private rtsRequestSequence: number = 0
  private rtsCalendarLoadSequence: number = 0
  private ephemerisLoadSequence: number = 0
  private planetCalcRequestSequence: number = 0
  private planetPairDistanceRequestSequence: number = 0
  private graphLoadSequence: number = 0
  private eclipseLoadSequence: number = 0
  private planetaryTransitRequestSequence: number = 0
  private phenomenaRequestSequence: number = 0
  private almanacRequestSequence: number = 0
  private hecPositionsRequestSequence: number = 0
  private celestialPositionsRequestSequence: number = 0
  private moonPhaseRequestSequence: number = 0
  private moonPhaseLoadingDays: number = 0
  private astroContextRequestSequence: number = 0
  private astroContextRequestPending: boolean = false

  constructor(
    port: CommandPort,
    media: FileExportPort,
    astroStore: AstroStore,
    ephemerisStore: EphemerisStore,
    wutStore: WutStore,
    searchStore: SearchStore,
    hooks: AstroCalcHostHooks
  ) {
    this.port = port
    this.media = media
    this.astroStore = astroStore
    this.ephemerisStore = ephemerisStore
    this.wutStore = wutStore
    this.searchStore = searchStore
    this.hooks = hooks
  }

  // —— 宿主读取的控制器状态：astroRequestedTab / astroTransitionId 随控制器 ——
  requestedAstroTab(): number {
    return this.astroRequestedTab
  }

  astroTransitionSerial(): number {
    return this.astroTransitionId
  }

  graphPickerActive(): boolean {
    return this.graphTargetPickerActive
  }

  rtsPickerActive(): boolean {
    return this.rtsTargetPickerActive
  }

  ephemerisPickerActive(): boolean {
    return this.ephemerisTargetPickerActive
  }

  // 搜索面板回跳后清除三个目标选择器标志（同一时刻至多一真）。
  clearTargetPickerFlags(): void {
    this.graphTargetPickerActive = false
    this.rtsTargetPickerActive = false
    this.ephemerisTargetPickerActive = false
  }

  // RTS 事件跳转到对应 JD。
  jumpToRts(key: string): void {
    const jd = this.astroStore.rtsData.get(key) ?? '0'
    if (parseFloat(jd) <= 0) {
      this.hooks.flashHint('该天体在当前位置没有这个事件。')
      return
    }
    this.port.requestInteractive('setJD', jd, (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.hooks.refreshState()
    })
  }

  // RTS 日历行跳转（取 transit/rise/set 中首个有效 JD）。
  jumpToRtsCalendar(day: RtsCalendarDay): void {
    const jd = day.transitJD ?? day.riseJD ?? day.setJD ?? 0
    if (jd <= 0) return
    this.hooks.animateTimeToJd(jd, '升中天落时刻', () => { this.hooks.refreshState() })
  }

  // RTS 日历「指定日期」DatePickerDialog。
  chooseRtsCalendarStartDate(): void {
    this.hooks.showDatePicker(
      new Date(this.astroStore.rtsCalendarStartYear, this.astroStore.rtsCalendarStartMonth - 1, this.astroStore.rtsCalendarStartDay),
      (year: number | undefined, month: number | undefined, day: number | undefined): void => {
        if (year !== undefined) this.astroStore.rtsCalendarStartYear = year
        if (month !== undefined) this.astroStore.rtsCalendarStartMonth = month + 1
        if (day !== undefined) this.astroStore.rtsCalendarStartDay = day
        this.astroStore.rtsCalendarStartOffsetDays = -1
        this.markRtsCalendarForRegeneration()
      })
  }

  // 星历「指定日期」DatePickerDialog。
  chooseEphemerisStartDate(): void {
    this.hooks.showDatePicker(
      new Date(this.ephemerisStore.ephemerisStartYear, this.ephemerisStore.ephemerisStartMonth - 1, this.ephemerisStore.ephemerisStartDay),
      (year: number | undefined, month: number | undefined, day: number | undefined): void => {
        if (year !== undefined) this.ephemerisStore.ephemerisStartYear = year
        if (month !== undefined) this.ephemerisStore.ephemerisStartMonth = month + 1
        if (day !== undefined) this.ephemerisStore.ephemerisStartDay = day
        this.astroStore.ephemerisStartOffsetDays = -1
        this.loadEphemeris()
      })
  }

  // 星历行跳转并重载星历。
  jumpToEphemerisRow(row: EphemerisRow): void {
    if (row.jd === undefined || row.jd <= 0) return
    this.hooks.animateTimeToJd(row.jd, '星历时刻', () => {
      this.hooks.refreshState()
      this.loadEphemeris()
    })
  }

  // 高度曲线「指定日期」DatePickerDialog。
  chooseGraphStartDate(): void {
    this.hooks.showDatePicker(
      new Date(this.astroStore.graphStartYear, this.astroStore.graphStartMonth - 1, this.astroStore.graphStartDay),
      (year: number | undefined, month: number | undefined, day: number | undefined): void => {
        if (year !== undefined) this.astroStore.graphStartYear = year
        if (month !== undefined) this.astroStore.graphStartMonth = month + 1
        if (day !== undefined) this.astroStore.graphStartDay = day
        this.astroStore.graphStartOffsetDays = -1
        this.reloadCurrentGraph()
      })
  }

  // 按当前图形模式重载对应曲线。
  reloadCurrentGraph(): void {
    if (this.astroStore.graphMode === 2) this.loadAnnualElevation()
    else if (this.astroStore.graphMode === 3) this.loadObservabilityCalendar()
    else if (this.astroStore.graphMode === 4) this.loadLunarElongation()
    else if (this.astroStore.graphMode === 5) this.loadPlanetTimeSeries()
    else this.loadAltAzCurve()
  }

  // 进入搜索面板选择高度曲线目标。
  openGraphTargetPicker(): void {
    this.graphTargetPickerActive = true
    this.searchStore.searchText = ''
    this.searchStore.searchSuggestions = []
    this.searchStore.loadCategoryObjects('planet')
    this.hooks.setPanel('search')
  }

  // 进入搜索面板选择 RTS 目标。
  openRtsTargetPicker(): void {
    this.rtsTargetPickerActive = true
    this.searchStore.searchText = ''
    this.searchStore.searchSuggestions = []
    this.searchStore.loadCategoryObjects('planet')
    this.hooks.setPanel('search')
  }

  // 进入搜索面板选择星历目标。
  openEphemerisTargetPicker(): void {
    this.ephemerisTargetPickerActive = true
    this.searchStore.searchText = ''
    this.searchStore.searchSuggestions = []
    this.searchStore.loadCategoryObjects('planet')
    this.hooks.setPanel('search')
  }

  // 可观测日历最佳日跳转。
  jumpToObservabilityDay(day: ObservabilityDay): void {
    if (day.bestJD === undefined || day.bestJD <= 0) return
    this.hooks.animateTimeToJd(day.bestJD, '最佳观测时刻', () => { this.hooks.refreshState() })
  }

  // 食相「指定日期」DatePickerDialog。
  chooseEclipseStartDate(): void {
    this.hooks.showDatePicker(
      new Date(this.astroStore.eclipseStartYear, this.astroStore.eclipseStartMonth - 1, this.astroStore.eclipseStartDay),
      (year: number | undefined, month: number | undefined, day: number | undefined): void => {
        if (year !== undefined) this.astroStore.eclipseStartYear = year
        if (month !== undefined) this.astroStore.eclipseStartMonth = month + 1
        if (day !== undefined) this.astroStore.eclipseStartDay = day
        this.astroStore.eclipseStartOffsetDays = -1
        this.reloadEclipses()
      })
  }

  // 天象行跳转。
  jumpToPhenomenon(item: PhenomenonItem): void {
    if (item.jd === undefined || item.jd <= 0) return
    this.hooks.animateTimeToJd(item.jd, '天象时刻', () => { this.hooks.refreshState() })
  }

  // 今晚观测目标行跳转 + 选中并居中。
  jumpToWutTarget(target: WutTarget): void {
    if (target.jd === undefined || target.jd <= 0 || target.englishName === undefined) return
    const targetName = target.englishName
    this.hooks.animateTimeToJd(target.jd, '最佳观测时刻', () => {
      // Selecting is not centring. searchObject only marks the target; the
      // engine's own handler never moves the view, so this row button looked
      // dead. Run the same post-selection placement the global search uses -
      // applySelectedObject with placement 'center' - so the row centres like
      // every other entry point.
      this.port.requestInteractive('searchObject', targetName, (selectResult: StellariumBridgeResponse) => {
        if (selectResult.found !== true) { return }
        this.hooks.applySelectedObject(selectResult, false, 'center', true)
      })
    })
  }

  // 大气参数写回（回包交给保留宿主实现 applyAtmosphereResponse）。
  applyAtmosphere(pressure: number, temperature: number, extinction: number): void {
    this.hooks.applyAtmosphereResponse(this.port.request('setAtmosphereParams',
      JSON.stringify({ pressure: pressure, temperature: temperature, extinction: extinction })))
  }

  // ---- 通用格式化：把 ISO 时间截成 "MM-DD HH:MM" / "HH:MM" ----
  fmtDateTime(s: string | undefined): string {
    if (s === undefined || s.length === 0) return '--'
    return s.replace('T', ' ').slice(0, 16)
  }

  fmtClock(s: string | undefined): string {
    if (s === undefined || s.length < 16) return '--:--'
    return s.slice(11, 16)
  }

  fmtEphemerisDate(s: string | undefined): string {
    if (s === undefined || s.length < 16) return '--'
    return s.slice(5, 16).replace('T', ' ')
  }

  fmtNum(v: number | undefined, digits: number, suffix: string): string {
    if (v === undefined) return '--'
    return v.toFixed(digits) + suffix
  }

  // 今晚观测目标筛选写回 + 重新加载 + CLI 发布。
  selectAstroFilter(key: string, value: string): void {
    if (key === 'period' && ['evening', 'midnight', 'morning', 'night'].includes(value)) {
      if (this.wutStore.wutPeriod === value) return
      this.wutStore.wutPeriod = value
    } else if (key === 'altitude' && ['0', '10', '20', '30', '45'].includes(value)) {
      if (this.wutStore.wutMinAltitude === Number(value)) return
      this.wutStore.wutMinAltitude = Number(value)
    } else if (key === 'magnitude' && ['4', '6', '8', '10'].includes(value)) {
      if (this.wutStore.wutMaxMagnitude === Number(value)) return
      this.wutStore.wutMaxMagnitude = Number(value)
    } else if (key === 'direction' && ['all', 'north', 'east', 'south', 'west'].includes(value)) {
      if (this.wutStore.wutDirection === value) return
      this.wutStore.wutDirection = value
    } else return
    this.hooks.publishAstroPanelState()
    this.wutStore.loadWutTargets()
  }

  // 一级分组切换（转对应默认标签）。
  selectAstroGroup(group: number): void {
    if (group < 0 || group > 2) return
    const tabs = astroTabItemsForGroup(group)
    const currentTab = tabs.find((item: TabItem) => item.id === this.astroStore.astroTab)
    this.selectAstroTab(currentTab !== undefined ? currentTab.id : tabs[0].id)
  }

  // 子标签切换（两段 animateTo 时序保留；动画本体归宿主）。
  selectAstroTab(tab: number): void {
    if (!Number.isInteger(tab) || tab < 0 || tab > 9 || tab === this.astroRequestedTab) return
    if (tab === this.astroStore.astroTab && this.astroRequestedTab < 0) return
    const order: number[] = [5, 2, 4, 9, 0, 1, 6, 3, 7, 8]
    const direction: number = order.indexOf(tab) >= order.indexOf(this.astroStore.astroTab) ? 1 : -1
    const transitionId = ++this.astroTransitionId
    this.astroRequestedTab = tab
    this.hooks.publishAstroPanelState()
    this.hooks.animateAstroIn(100, (): void => {
      if (transitionId !== this.astroTransitionId) return
      if (!this.hooks.astroPanelOnScreen()) {
        this.astroRequestedTab = -1
        this.astroStore.astroContentOpacity = 1
        this.astroStore.astroContentOffsetX = 0
        this.hooks.publishAstroPanelState()
        return
      }
      this.astroStore.astroTab = tab
      this.astroStore.astroGroup = astroGroupForTab(tab)
      this.hooks.scrollAstroPanelToTop()
      this.astroStore.astroContentOffsetX = direction * 10
      this.hooks.animateAstroOut(170, (): void => {
        if (transitionId !== this.astroTransitionId) return
        this.astroRequestedTab = -1
        this.hooks.publishAstroPanelState()
        if (!this.hooks.astroPanelOnScreen()) return
        this.hooks.saveAppSettings()
        this.loadAstroTab(tab)
      }, (): void => {
        this.astroStore.astroContentOpacity = 1
        this.astroStore.astroContentOffsetX = 0
      })
    }, (): void => {
      this.astroStore.astroContentOpacity = 0
      this.astroStore.astroContentOffsetX = (0 - direction) * 8
    })
  }

  // 按当前标签分派到对应目标选择器。
  openAstroTargetPicker(): void {
    if (this.astroStore.astroTab === 2) {
      this.openRtsTargetPicker()
    } else if (this.astroStore.astroTab === 4) {
      this.openGraphTargetPicker()
    } else {
      this.openEphemerisTargetPicker()
    }
  }

  // 月相行跳转。
  jumpToMoonPhase(item: MoonPhaseItem): void {
    if (item.jd === undefined || item.jd <= 0) return
    this.hooks.animateTimeToJd(item.jd, item.phase ?? '月相时刻', () => { this.hooks.refreshState() })
  }

  // 季节节点行跳转。
  jumpToAlmanacSeason(event: SeasonEvent): void {
    if (event.jd === undefined || event.jd <= 0) return
    this.hooks.animateTimeToJd(event.jd, event.label ?? '节气时刻', () => { this.hooks.refreshState() })
  }

  // 天文面板前台且可见。
  private shouldRefreshAstroCalcContext(): boolean {
    return this.hooks.astroPanelContextActive()
  }

  // 停上下文轮询并取消在途请求。
  stopAstroCalcContextTimer(): void {
    if (this.astroContextTimer !== 0) {
      clearInterval(this.astroContextTimer)
      this.astroContextTimer = 0
    }
    this.cancelAstroCalcContext()
  }

  // 按面板可见性启停 1s 上下文轮询（定时器自持）。
  syncAstroCalcContextTimer(): void {
    if (!this.shouldRefreshAstroCalcContext()) {
      this.stopAstroCalcContextTimer()
      return
    }
    if (this.astroContextTimer !== 0) return
    this.loadAstroCalcContext()
    this.astroContextTimer = setInterval(() => { this.loadAstroCalcContext() }, 1000)
  }

  // 行星位置刷新（请求序号防止旧回包覆盖）。
  loadPlanetPositions(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const requestId = ++this.planetPositionsRequestSequence
    this.astroStore.planetPositions = []
    this.astroStore.planetPositionsError = ''
    this.astroStore.planetPositionsLoading = true
    this.port.requestInteractive('getObjectPositions', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.planetPositionsRequestSequence) return
      this.astroStore.planetPositionsLoading = false
      if (r.ok === true && Array.isArray(r.items)) {
        const positioned = r.items as Array<PlanetPosition>
        this.astroStore.planetPositions = positioned.map((p: PlanetPosition): PlanetPosition => ({
          name: p.name,
          englishName: p.englishName,
          rightAscension: p.rightAscension,
          declination: p.declination,
          altitude: Math.round(p.altitude * 10) / 10,
          azimuth: Math.round(p.azimuth * 10) / 10,
          magnitude: Math.round(p.magnitude * 100) / 100,
          distanceAU: p.distanceAU,
          angularSizeArcmin: p.angularSizeArcmin,
          transit: p.transit,
        }))
        if (this.astroStore.planetPositions.length === 0) this.astroStore.planetPositionsError = '当前没有可显示的行星位置。'
      } else {
        this.astroStore.planetPositionsError = r.error ?? '行星位置计算失败，请点刷新后重试。'
      }
    }, () => {
      if (requestId !== this.planetPositionsRequestSequence) return
      this.astroStore.planetPositionsLoading = false
      this.astroStore.planetPositionsError = '行星位置计算失败，请点刷新后重试。'
    })
  }

  // 当前页 CSV 导出（picker/fileIo 经 MediaPort.saveTextFileAs）。
  async exportCurrentAstroCsv(): Promise<void> {
    this.astroStore.updateAstroCalcSnapshot()
    const exportData = this.astroStore.astroCsvExport(this.wutStore.wutTargets, this.wutStore.wutObservationTime)
    if (exportData === undefined || exportData.rows.length === 0) {
      this.hooks.flashHint('当前页没有可导出的计算结果，请先生成数据。')
      return
    }
    this.astroStore.astroExporting = true
    try {
      const csv = this.astroStore.makeAstroCsv(exportData)
      const title = exportData.title
      await new Promise<void>((resolve) => {
        this.media.saveTextFileAs(csv, 'astrocalc-' + Date.now().toString() + '.csv', 'CSV 表格|.csv', (result: MediaSaveResult) => {
          if (result === MediaSaveResult.Cancelled) this.hooks.flashHint('已取消保存。')
          else if (result === MediaSaveResult.Saved) this.hooks.flashHint('已保存 ' + title + ' CSV。')
          else this.hooks.flashHint('保存失败，请检查文件管理权限后重试。')
          resolve()
        })
      })
    } finally {
      this.astroStore.astroExporting = false
    }
  }

  // ===== 桥加载器 =====
  private hasSelected(): boolean {
    return this.hooks.hasSelectedObject()
  }

  // 升中天落（RTS）：桥查询选中天体的升起 / 中天 / 落下时刻。
  loadRTS(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const requestId = ++this.rtsRequestSequence
    this.astroStore.rtsError = ''
    this.astroStore.rtsLoading = true
    if (!this.hasSelected()) {
      this.astroStore.rtsLoading = false
      this.clearRtsSelectionResults()
      return
    }
    const port = this.port
    if (port === null) {
      this.astroStore.rtsLoading = false
      return
    }
    port.requestInteractive('getRTS', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.rtsRequestSequence) return
      this.astroStore.rtsLoading = false
      if (r.ok === true && r.rts !== undefined) {
        const rv = r.rts as Record<string, Object>
        const data = new Map<string, string>()
        data.set('name', rv['name'] !== undefined ? rv['name'] as string : 'N/A')
        data.set('nextRiseJD', rv['nextRiseJD'] !== undefined ? String(rv['nextRiseJD']) : '0')
        data.set('nextTransitJD', rv['nextTransitJD'] !== undefined ? String(rv['nextTransitJD']) : '0')
        data.set('nextSetJD', rv['nextSetJD'] !== undefined ? String(rv['nextSetJD']) : '0')
        data.set('prevRiseJD', rv['prevRiseJD'] !== undefined ? String(rv['prevRiseJD']) : '0')
        data.set('prevTransitJD', rv['prevTransitJD'] !== undefined ? String(rv['prevTransitJD']) : '0')
        data.set('prevSetJD', rv['prevSetJD'] !== undefined ? String(rv['prevSetJD']) : '0')
        data.set('nextRiseText', rv['nextRiseText'] !== undefined ? String(rv['nextRiseText']) : (rv['nextRiseJD'] !== undefined ? String(rv['nextRiseJD']) : '0'))
        data.set('nextTransitText', rv['nextTransitText'] !== undefined ? String(rv['nextTransitText']) : (rv['nextTransitJD'] !== undefined ? String(rv['nextTransitJD']) : '0'))
        data.set('nextSetText', rv['nextSetText'] !== undefined ? String(rv['nextSetText']) : (rv['nextSetJD'] !== undefined ? String(rv['nextSetJD']) : '0'))
        data.set('prevRiseText', rv['prevRiseText'] !== undefined ? String(rv['prevRiseText']) : (rv['prevRiseJD'] !== undefined ? String(rv['prevRiseJD']) : '0'))
        data.set('prevTransitText', rv['prevTransitText'] !== undefined ? String(rv['prevTransitText']) : (rv['prevTransitJD'] !== undefined ? String(rv['prevTransitJD']) : '0'))
        data.set('prevSetText', rv['prevSetText'] !== undefined ? String(rv['prevSetText']) : (rv['prevSetJD'] !== undefined ? String(rv['prevSetJD']) : '0'))
        this.astroStore.rtsData = data
      } else {
        this.astroStore.rtsData = new Map()
        this.astroStore.rtsError = r.error ?? '请先在星图上选中一个天体，再计算升中天落。'
      }
    }, () => {
      if (requestId !== this.rtsRequestSequence) return
      this.astroStore.rtsLoading = false
      this.astroStore.rtsData = new Map()
      this.astroStore.rtsError = '升中天落计算失败，请点刷新后重试。'
    })
  }

  clearRtsSelectionResults(): void {
    ++this.rtsRequestSequence
    this.astroStore.rtsLoading = false
    this.astroStore.rtsData = new Map()
    this.astroStore.rtsError = '升起、中天和落下时间需要先选择一个天体。'
    this.astroStore.rtsCalendarData = []
    this.astroStore.rtsCalendarName = ''
    this.astroStore.rtsCalendarLoading = false
    this.astroStore.rtsCalendarError = '请先选择一个天体，再生成升中天落日期表。'
    this.astroStore.rtsCalendarNeedsGeneration = false
    this.astroStore.rtsCalendarProgress = 0
    ++this.rtsCalendarLoadSequence
  }

  loadRtsCalendar(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const requestId = ++this.rtsCalendarLoadSequence
    this.astroStore.rtsCalendarData = []
    this.astroStore.rtsCalendarError = ''
    this.astroStore.rtsCalendarNeedsGeneration = false
    if (!this.hasSelected()) {
      this.clearRtsSelectionResults()
      return
    }
    const port = this.port
    if (port === null) {
      return
    }
    this.astroStore.rtsCalendarLoading = true
    this.astroStore.rtsCalendarProgress = 0
    this.astroStore.rtsCalendarTotalDays = this.astroStore.rtsCalendarDays
    this.resolveRtsCalendarStartJD(requestId, (startJD: number) => {
      const options: RtsCalendarOptions = { days: this.astroStore.rtsCalendarDays }
      if (startJD > 0) options.jd = startJD
      port.requestLongRunning('getRTSCalendar', JSON.stringify(options), (r: StellariumBridgeResponse) => {
        if (requestId !== this.rtsCalendarLoadSequence) return
        this.astroStore.rtsCalendarLoading = false
        if (r.ok === true && r.rtsCalendar !== undefined) {
          this.astroStore.rtsCalendarData = r.rtsCalendar as Array<RtsCalendarDay>
          this.astroStore.rtsCalendarName = r.name ?? ''
          this.astroStore.rtsCalendarProgress = this.astroStore.rtsCalendarDays
        } else {
          this.astroStore.rtsCalendarError = '请先在星图上选中一个天体，再生成升中天落日期表。'
        }
      }, () => {
        if (requestId !== this.rtsCalendarLoadSequence) return
        this.astroStore.rtsCalendarLoading = false
        this.astroStore.rtsCalendarError = '日期表计算时间较长，请缩短时长后重试。'
      }, (progress: StellariumBridgeResponse) => {
        if (requestId !== this.rtsCalendarLoadSequence) return
        const completed = Number(progress.progress)
        const total = Number(progress.totalDays)
        if (Number.isFinite(completed) && completed > 0) this.astroStore.rtsCalendarProgress = completed
        if (Number.isFinite(total) && total > 0) this.astroStore.rtsCalendarTotalDays = total
      }, 480)
    }, () => {
      if (requestId !== this.rtsCalendarLoadSequence) return
      this.astroStore.rtsCalendarLoading = false
      this.astroStore.rtsCalendarError = '无法读取当前模拟时间，请点生成日期表后重试。'
    })
  }

  markRtsCalendarForRegeneration(): void {
    ++this.rtsCalendarLoadSequence
    this.astroStore.rtsCalendarLoading = false
    this.astroStore.rtsCalendarData = []
    this.astroStore.rtsCalendarError = ''
    this.astroStore.rtsCalendarNeedsGeneration = true
    this.astroStore.rtsCalendarProgress = 0
    this.astroStore.rtsCalendarTotalDays = 0
  }

  private resolveRtsCalendarStartJD(requestId: number, onReady: (startJD: number) => void, onFailure: () => void): void {
    if (this.astroStore.rtsCalendarStartOffsetDays < 0) {
      onReady(dateToJD(this.astroStore.rtsCalendarStartYear, this.astroStore.rtsCalendarStartMonth, this.astroStore.rtsCalendarStartDay, 0, 0))
      return
    }
    if (this.astroStore.rtsCalendarStartOffsetDays === 0) {
      onReady(0)
      return
    }
    const port = this.port
    if (port === null) {
      onFailure()
      return
    }
    port.requestInteractive('getState', '', (state: StellariumBridgeResponse) => {
      if (requestId !== this.rtsCalendarLoadSequence) return
      const currentJD = Number(state.jd)
      if (state.ok === true && Number.isFinite(currentJD) && currentJD > 0) {
        onReady(currentJD + this.astroStore.rtsCalendarStartOffsetDays)
        return
      }
      onFailure()
    }, () => {
      if (requestId !== this.rtsCalendarLoadSequence) return
      onFailure()
    })
  }

  // 星历表：桥查询选中天体（或指定天体组）的星历序列（重试档 0/100/80）。
  loadEphemeris(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const requestId = ++this.ephemerisLoadSequence
    this.astroStore.ephemerisData = []
    this.astroStore.ephemerisName = ''
    this.astroStore.ephemerisError = ''
    this.astroStore.ephemerisLoading = true
    const port = this.port
    if (port === null) {
      this.astroStore.ephemerisLoading = false
      return
    }
    this.resolveEphemerisStartJD(requestId, (startJD: number) => {
      const options: EphemerisOptions = { days: this.astroStore.ephemerisDays, stepHours: this.astroStore.ephemerisStepHours }
      if (startJD > 0) options.jd = startJD
      if (this.astroStore.ephemerisMode === 1) options.names = [this.astroStore.ephemerisPrimary, this.astroStore.ephemerisSecondary]
      if (this.astroStore.ephemerisMode === 2) options.allNakedEye = true
      port.requestWhenReady('getEphemeris', JSON.stringify(options), (r: StellariumBridgeResponse) => {
        if (requestId !== this.ephemerisLoadSequence) return
        this.astroStore.ephemerisLoading = false
        if (r.ok === true && r.ephemeris !== undefined) {
          this.astroStore.ephemerisData = r.ephemeris as Array<EphemerisRow>
          this.astroStore.ephemerisName = r.name !== undefined ? String(r.name) : ''
          const location = r.observerLocation !== undefined ? String(r.observerLocation) : ''
          const timeZone = r.timeZone !== undefined ? String(r.timeZone) : ''
          const frame = r.coordinateFrame !== undefined ? String(r.coordinateFrame) : 'J2000'
          const calculatedAt = r.calculationTime !== undefined ? this.fmtDateTime(String(r.calculationTime)) : ''
          this.astroStore.ephemerisMeta = '坐标系 ' + frame + (location.length > 0 ? ' · 观测地 ' + location : '')
            + (timeZone.length > 0 ? ' · 时区 ' + timeZone : '')
            + (calculatedAt.length > 0 ? ' · 计算于 ' + calculatedAt : '')
        } else {
          this.astroStore.ephemerisMeta = ''
          this.astroStore.ephemerisError = r.error ?? '请先在星图上选中一个天体，再生成它的星历。'
        }
      }, () => {
        if (requestId !== this.ephemerisLoadSequence) return
        this.astroStore.ephemerisLoading = false
        this.astroStore.ephemerisMeta = ''
        this.astroStore.ephemerisError = '星历计算时间较长，请缩短时间范围或增大采样间隔后重试。'
      }, 0, 100, 80)
    }, () => {
      if (requestId !== this.ephemerisLoadSequence) return
      this.astroStore.ephemerisLoading = false
      this.astroStore.ephemerisMeta = ''
      this.astroStore.ephemerisError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  private resolveEphemerisStartJD(requestId: number, onReady: (startJD: number) => void, onFailure: () => void): void {
    if (this.astroStore.ephemerisStartOffsetDays < 0) {
      onReady(dateToJD(this.ephemerisStore.ephemerisStartYear, this.ephemerisStore.ephemerisStartMonth, this.ephemerisStore.ephemerisStartDay, 0, 0))
      return
    }
    if (this.astroStore.ephemerisStartOffsetDays === 0) {
      onReady(0)
      return
    }
    const port = this.port
    if (port === null) {
      onFailure()
      return
    }
    port.requestInteractive('getState', '', (state: StellariumBridgeResponse) => {
      if (requestId !== this.ephemerisLoadSequence) return
      const currentJD = Number(state.jd)
      if (state.ok === true && Number.isFinite(currentJD) && currentJD > 0) {
        onReady(currentJD + this.astroStore.ephemerisStartOffsetDays)
        return
      }
      onFailure()
    }, () => {
      if (requestId !== this.ephemerisLoadSequence) return
      onFailure()
    })
  }

  loadPlanetCalc(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = ++this.planetCalcRequestSequence
    this.astroStore.planetCalcData = []
    this.astroStore.planetCalcError = ''
    this.astroStore.planetCalcLoading = true
    port.requestInteractive('getPlanetCalc', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.planetCalcRequestSequence) return
      this.astroStore.planetCalcLoading = false
      if (r.ok === true && r.planetCalc !== undefined) {
        this.astroStore.planetCalcData = r.planetCalc as Array<PlanetCalcItem>
        if (this.astroStore.planetCalcData.length === 0) this.astroStore.planetCalcError = '当前没有可显示的行星数据。'
      } else {
        this.astroStore.planetCalcError = r.error ?? '行星实时数据计算失败，请点刷新后重试。'
      }
    }, () => {
      if (requestId !== this.planetCalcRequestSequence) return
      this.astroStore.planetCalcLoading = false
      this.astroStore.planetCalcError = '行星实时数据计算失败，请点刷新后重试。'
    })
  }

  loadPlanetPairDistance(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = ++this.planetPairDistanceRequestSequence
    this.astroStore.planetPairDistanceData = []
    this.astroStore.planetPairDistanceError = ''
    this.astroStore.planetPairDistanceLoading = true
    const options = JSON.stringify({
      first: this.astroStore.planetPairFirst,
      second: this.astroStore.planetPairSecond,
      days: this.astroStore.planetPairDays,
      stepDays: this.astroStore.planetPairStepDays
    })
    port.requestInteractive('getPlanetPairDistanceCurve', options, (r: StellariumBridgeResponse) => {
      if (requestId !== this.planetPairDistanceRequestSequence) return
      this.astroStore.planetPairDistanceLoading = false
      if (r.ok === true && r.planetPairDistance !== undefined) {
        const data = r.planetPairDistance as Array<PlanetPairDistancePoint>
        this.astroStore.planetPairDistanceData = data
        this.astroStore.planetPairFirstName = planetPairBodyName(this.astroStore.planetPairFirst)
        this.astroStore.planetPairSecondName = planetPairBodyName(this.astroStore.planetPairSecond)
        this.astroStore.planetPairAngularAvailable = r.angularAvailable === true
        this.updatePlanetPairDistanceRanges(data)
      } else {
        this.astroStore.planetPairDistanceData = []
        this.astroStore.planetPairDistanceError = r.error ?? '请选择两个不同的太阳系天体。'
      }
    }, () => {
      if (requestId !== this.planetPairDistanceRequestSequence) return
      this.astroStore.planetPairDistanceLoading = false
      this.astroStore.planetPairDistanceError = '距离曲线计算失败，请点刷新后重试。'
    })
  }

  private updatePlanetPairDistanceRanges(data: Array<PlanetPairDistancePoint>): void {
    let linearMin: number = Number.MAX_VALUE
    let linearMax: number = -Number.MAX_VALUE
    let angularMin: number = Number.MAX_VALUE
    let angularMax: number = -Number.MAX_VALUE
    for (const point of data) {
      const linear: number = point.linearDistance ?? 0
      linearMin = Math.min(linearMin, linear)
      linearMax = Math.max(linearMax, linear)
      if (point.angularDistance !== undefined) {
        angularMin = Math.min(angularMin, point.angularDistance)
        angularMax = Math.max(angularMax, point.angularDistance)
      }
    }
    this.astroStore.planetPairLinearMin = linearMin === Number.MAX_VALUE ? 0 : linearMin
    this.astroStore.planetPairLinearMax = linearMax <= linearMin ? linearMin + 1 : linearMax
    this.astroStore.planetPairAngularMin = angularMin === Number.MAX_VALUE ? 0 : angularMin
    this.astroStore.planetPairAngularMax = angularMax <= angularMin ? angularMin + 1 : angularMax
  }

  loadAltAzCurve(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = this.beginGraphLoad()
    this.astroStore.altAzCurve = []
    this.astroStore.altAzError = ''
    this.resolveGraphStartJD(requestId, (startJD: number) => {
      port.requestInteractive('getAltAzCurve', JSON.stringify({
        jd: startJD,
        hours: this.astroStore.altAzHours,
        stepMin: this.astroStore.altAzStepMin,
        includeSun: this.astroStore.graphMode === 0 && this.astroStore.altAzShowSun,
        includeMoon: this.astroStore.graphMode === 0 && this.astroStore.altAzShowMoon
      }), (r: StellariumBridgeResponse) => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        if (r.ok === true && r.curve !== undefined) {
          this.astroStore.altAzCurve = r.curve as Array<AltAzPoint>
          this.astroStore.altAzName = r.name !== undefined ? r.name : ''
          this.astroStore.altAzError = ''
        } else {
          this.astroStore.altAzCurve = []
          this.astroStore.altAzError = '请先在星图上选中一个天体，再来看它的' + (this.astroStore.graphMode === 0 ? '高度' : '方位角') + '曲线。'
        }
      }, () => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        this.astroStore.altAzError = '计算等待超时，请点刷新后重试。'
      })
    }, () => {
      this.astroStore.altAzError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  loadObservabilityCalendar(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = this.beginGraphLoad()
    this.astroStore.observabilityData = []
    this.astroStore.observabilityError = ''
    this.astroStore.observabilityProgress = '准备计算…'
    this.resolveGraphStartJD(requestId, (startJD: number) => {
      const options = JSON.stringify({ jd: startJD, days: this.astroStore.observabilityDays, minAltitude: this.astroStore.observabilityMinAltitude })
      port.requestLongRunning('getObservabilityCalendar', options, (r: StellariumBridgeResponse) => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        this.astroStore.observabilityProgress = ''
        if (r.ok === true && r.observability !== undefined) {
          this.astroStore.observabilityData = r.observability as Array<ObservabilityDay>
          this.astroStore.observabilityName = r.name ?? ''
        } else {
          this.astroStore.observabilityData = []
          this.astroStore.observabilityError = (r.error ?? '').toString().includes('no object')
            ? '请先在星图上选中一个天体，再查看它未来多晚的可见性。'
            : '观测窗口计算失败，请稍后重试。'
        }
      }, () => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        this.astroStore.observabilityProgress = ''
        this.astroStore.observabilityError = '计算等待超时，请稍后重试。'
      }, (progress: StellariumBridgeResponse) => {
        if (requestId !== this.graphLoadSequence) return
        const completed = Number(progress.progress ?? 0)
        const total = Number(progress.totalDays ?? this.astroStore.observabilityDays)
        this.astroStore.observabilityProgress = '正在计算：' + Math.min(completed, total).toFixed(0) + ' / ' + total.toFixed(0) + ' 天'
      })
    }, () => {
      this.astroStore.observabilityProgress = ''
      this.astroStore.observabilityError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  loadAnnualElevation(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = this.beginGraphLoad()
    this.astroStore.annualElevationData = []
    this.astroStore.annualElevationError = ''
    port.requestInteractive('getAnnualElevation', JSON.stringify({ hour: this.astroStore.annualElevationHour }), (r: StellariumBridgeResponse) => {
      if (requestId !== this.graphLoadSequence) return
      this.finishGraphLoad(requestId)
      if (r.ok === true && r.annualElevation !== undefined) {
        this.astroStore.annualElevationData = r.annualElevation as Array<AnnualElevationPoint>
        this.astroStore.annualElevationName = r.name ?? ''
      } else {
        this.astroStore.annualElevationData = []
        this.astroStore.annualElevationError = '请先在星图上选中一个天体，再生成全年高度曲线。'
      }
    }, () => {
      if (requestId !== this.graphLoadSequence) return
      this.finishGraphLoad(requestId)
      this.astroStore.annualElevationError = '计算等待超时，请点刷新后重试。'
    })
  }

  loadLunarElongation(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = this.beginGraphLoad()
    this.astroStore.lunarElongationData = []
    this.astroStore.lunarElongationError = ''
    this.resolveGraphStartJD(requestId, (startJD: number) => {
      const options = JSON.stringify({ jd: startJD, days: this.astroStore.lunarElongationDays, stepHours: this.astroStore.lunarElongationStepHours })
      port.requestInteractive('getLunarElongationCurve', options, (r: StellariumBridgeResponse) => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        if (r.ok === true && r.lunarElongation !== undefined) {
          this.astroStore.lunarElongationData = r.lunarElongation as Array<LunarElongationPoint>
          this.astroStore.lunarElongationName = r.name ?? ''
        } else {
          this.astroStore.lunarElongationData = []
          this.astroStore.lunarElongationError = '请先选中除月亮和人造卫星之外的天体，再生成月距曲线。'
        }
      }, () => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        this.astroStore.lunarElongationError = '计算等待超时，请点刷新后重试。'
      })
    }, () => {
      this.astroStore.lunarElongationError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  loadPlanetTimeSeries(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = this.beginGraphLoad()
    this.astroStore.planetTimeSeriesData = []
    this.astroStore.planetTimeSeriesError = ''
    this.resolveGraphStartJD(requestId, (startJD: number) => {
      const options = JSON.stringify({
        jd: startJD,
        days: this.astroStore.planetTimeSeriesDays,
        stepHours: this.astroStore.planetTimeSeriesStepHours,
        leftMetric: this.astroStore.planetTimeSeriesLeftMetric,
        rightMetric: this.astroStore.planetTimeSeriesRightMetric
      })
      port.requestInteractive('getPlanetTimeSeries', options, (r: StellariumBridgeResponse) => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        if (r.ok === true && r.timeSeries !== undefined) {
          const data = r.timeSeries as Array<PlanetTimeSeriesPoint>
          this.astroStore.planetTimeSeriesData = data
          this.astroStore.planetTimeSeriesName = r.name ?? ''
          this.updatePlanetTimeSeriesRanges(data)
        } else {
          this.astroStore.planetTimeSeriesData = []
          this.astroStore.planetTimeSeriesError = '请先选中一个太阳系天体（行星、太阳或月亮），再生成双曲线。'
        }
      }, () => {
        if (requestId !== this.graphLoadSequence) return
        this.finishGraphLoad(requestId)
        this.astroStore.planetTimeSeriesError = '计算等待超时，请点刷新后重试。'
      })
    }, () => {
      this.astroStore.planetTimeSeriesError = '无法读取当前模拟时间，请点刷新后重试。'
    })
  }

  private beginGraphLoad(): number {
    this.graphLoadSequence += 1
    this.astroStore.graphLoading = true
    return this.graphLoadSequence
  }

  private finishGraphLoad(requestId: number): void {
    if (requestId === this.graphLoadSequence) this.astroStore.graphLoading = false
  }

  private resolveGraphStartJD(requestId: number, onReady: (startJD: number) => void, onFailure: () => void): void {
    if (this.astroStore.graphStartOffsetDays < 0) {
      onReady(dateToJD(this.astroStore.graphStartYear, this.astroStore.graphStartMonth, this.astroStore.graphStartDay, 0, 0))
      return
    }
    if (this.astroStore.graphStartOffsetDays === 0) {
      onReady(0)
      return
    }
    const port = this.port
    if (port === null) {
      this.finishGraphLoad(requestId)
      onFailure()
      return
    }
    port.requestInteractive('getState', '', (state: StellariumBridgeResponse) => {
      if (requestId !== this.graphLoadSequence) return
      const currentJD = Number(state.jd)
      if (state.ok === true && Number.isFinite(currentJD) && currentJD > 0) {
        onReady(currentJD + this.astroStore.graphStartOffsetDays)
        return
      }
      this.finishGraphLoad(requestId)
      onFailure()
    }, () => {
      if (requestId !== this.graphLoadSequence) return
      this.finishGraphLoad(requestId)
      onFailure()
    })
  }

  private updatePlanetTimeSeriesRanges(data: Array<PlanetTimeSeriesPoint>): void {
    let leftMin: number = Number.MAX_VALUE
    let leftMax: number = -Number.MAX_VALUE
    let rightMin: number = Number.MAX_VALUE
    let rightMax: number = -Number.MAX_VALUE
    for (const point of data) {
      const left: number = point.left ?? 0
      const right: number = point.right ?? 0
      leftMin = Math.min(leftMin, left)
      leftMax = Math.max(leftMax, left)
      rightMin = Math.min(rightMin, right)
      rightMax = Math.max(rightMax, right)
    }
    this.astroStore.planetTimeSeriesLeftMin = leftMin === Number.MAX_VALUE ? 0 : leftMin
    this.astroStore.planetTimeSeriesLeftMax = leftMax <= leftMin ? leftMin + 1 : leftMax
    this.astroStore.planetTimeSeriesRightMin = rightMin === Number.MAX_VALUE ? 0 : rightMin
    this.astroStore.planetTimeSeriesRightMax = rightMax <= rightMin ? rightMin + 1 : rightMax
  }

  // 日月食：桥查询未来日食 / 月食（重试档 0/100/200）。
  loadEclipses(): void {
    this.astroStore.updateAstroCalcSnapshot()
    if (this.astroStore.eclipseData.length > 0 || this.astroStore.eclipseLoading) return
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = ++this.eclipseLoadSequence
    this.astroStore.eclipseLoading = true
    this.astroStore.eclipseError = ''
    this.resolveEclipseStartJD(requestId, (startJD: number) => {
      const options: EclipseOptions = { months: this.astroStore.eclipseMonths }
      if (startJD > 0) options.jd = startJD
      port.requestWhenReady('getEclipses', JSON.stringify(options), (r: StellariumBridgeResponse) => {
        if (requestId !== this.eclipseLoadSequence) return
        this.astroStore.eclipseLoading = false
        if (r.ok === true && r.eclipses !== undefined) {
          this.astroStore.eclipseData = r.eclipses as Array<EclipseItem>
          return
        }
        this.astroStore.eclipseError = r.error ?? '日月食计算未能完成，请重试。'
      }, () => {
        if (requestId !== this.eclipseLoadSequence) return
        this.astroStore.eclipseLoading = false
        this.astroStore.eclipseError = '日月食计算时间较长，请缩短预测范围后重试。'
      }, 0, 100, 200)
    }, () => {
      if (requestId !== this.eclipseLoadSequence) return
      this.astroStore.eclipseLoading = false
      this.astroStore.eclipseError = '无法读取当前模拟时间，请重试。'
    })
  }

  reloadEclipses(): void {
    ++this.eclipseLoadSequence
    this.astroStore.eclipseLoading = false
    this.astroStore.eclipseData = []
    this.astroStore.eclipseError = ''
    this.loadEclipses()
  }

  private resolveEclipseStartJD(requestId: number, onReady: (startJD: number) => void, onFailure: () => void): void {
    if (this.astroStore.eclipseStartOffsetDays < 0) {
      onReady(dateToJD(this.astroStore.eclipseStartYear, this.astroStore.eclipseStartMonth, this.astroStore.eclipseStartDay, 0, 0))
      return
    }
    if (this.astroStore.eclipseStartOffsetDays === 0) {
      onReady(0)
      return
    }
    const port = this.port
    if (port === null) {
      onFailure()
      return
    }
    port.requestInteractive('getState', '', (state: StellariumBridgeResponse) => {
      if (requestId !== this.eclipseLoadSequence) return
      const currentJD = Number(state.jd)
      if (state.ok === true && Number.isFinite(currentJD) && currentJD > 0) {
        onReady(currentJD + this.astroStore.eclipseStartOffsetDays)
        return
      }
      onFailure()
    }, () => {
      if (requestId !== this.eclipseLoadSequence) return
      onFailure()
    })
  }

  // 行星凌日：桥查询未来行星凌日（重试档 0/100/200）。
  loadPlanetaryTransits(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    if (!this.astroStore.planetaryTransitLoaded && !this.astroStore.planetaryTransitLoading) {
      const requestId = ++this.planetaryTransitRequestSequence
      this.astroStore.planetaryTransitLoading = true
      this.astroStore.planetaryTransitError = ''
      port.requestWhenReady('getPlanetaryTransits', JSON.stringify({ years: this.astroStore.planetaryTransitYears }), (r: StellariumBridgeResponse) => {
        if (requestId !== this.planetaryTransitRequestSequence) return
        this.astroStore.planetaryTransitLoading = false
        if (r.ok === true && r.planetaryTransits !== undefined) {
          this.astroStore.planetaryTransitData = r.planetaryTransits as Array<PlanetaryTransitItem>
          this.astroStore.planetaryTransitError = ''
        } else {
          this.astroStore.planetaryTransitError = '行星凌日只能按地球上的当前观测地点计算。'
        }
        this.astroStore.planetaryTransitLoaded = true
      }, () => {
        if (requestId !== this.planetaryTransitRequestSequence) return
        this.astroStore.planetaryTransitLoading = false
        this.astroStore.planetaryTransitLoaded = true
        this.astroStore.planetaryTransitError = '行星凌日计算时间较长，请缩短预测范围后重试。'
      }, 0, 100, 200)
    }
  }

  // 天象预报：桥查询两目标间的天象（合 / 冲 / 大距等；重试档 0/100/300）。
  loadPhenomena(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = ++this.phenomenaRequestSequence
    this.astroStore.phenomenaData = []
    this.astroStore.phenomenaHint = ''
    this.astroStore.phenomenaLoading = true
    const options: PhenomenaOptions = {
      bodyA: this.astroStore.phenomenaPrimary,
      bodyB: this.astroStore.phenomenaTarget,
      days: this.astroStore.phenomenaDays,
      startOffsetMonths: this.astroStore.phenomenaStartOffsetMonths,
      maxSeparation: this.astroStore.phenomenaMaxSeparation,
      includeOppositions: this.astroStore.phenomenaIncludeOppositions,
      includePerihelionAphelion: this.astroStore.phenomenaIncludePerihelionAphelion,
      includeElongationsQuadratures: this.astroStore.phenomenaIncludeElongationsQuadratures,
      includeStations: this.astroStore.phenomenaIncludeStations,
    }
    port.requestWhenReady('getPhenomena', JSON.stringify(options), (r: StellariumBridgeResponse) => {
      if (requestId !== this.phenomenaRequestSequence) return
      this.astroStore.phenomenaLoading = false
      if (r.ok === true && r.phenomena !== undefined) {
        this.astroStore.phenomenaData = r.phenomena as Array<PhenomenonItem>
        if (this.astroStore.phenomenaData.length === 0) this.astroStore.phenomenaHint = '所选时段内没有符合角距条件的天象。'
      } else {
        this.astroStore.phenomenaHint = r.error ?? '暂时无法完成天象计算，请稍后重试。'
      }
    }, () => {
      if (requestId !== this.phenomenaRequestSequence) return
      this.astroStore.phenomenaLoading = false
      this.astroStore.phenomenaHint = '计算时间较长，请缩短预测范围或减少比较对象后重试。'
    }, 0, 100, 300)
  }

  // 今晚观测：先取今晚事件（首段），再联动 Wut 目标加载。
  loadTonightAstro(): void {
    const port = this.port
    if (port === null) {
      return
    }
    if (this.astroStore.tonightAstro === null) {
      port.requestInteractive('getTonightEvents', '', (r: StellariumBridgeResponse) => {
        if (r.ok === true && r.tonight !== undefined) this.astroStore.tonightAstro = r.tonight as TonightEvents
      })
    }
    this.wutStore.loadWutTargets()
  }

  // 年历：桥查询当日天文历（日出日落、月相、四季节点等）。
  loadAlmanac(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = ++this.almanacRequestSequence
    this.astroStore.almanacSeasons = []
    this.astroStore.almanacSolarTerms = []
    this.astroStore.almanacSeasonYear = ''
    this.astroStore.almanacData = new Map()
    this.astroStore.almanacError = ''
    this.astroStore.almanacLoading = true
    port.requestInteractive('getAlmanac', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.almanacRequestSequence) return
      this.astroStore.almanacLoading = false
      if (r.ok === true && r.almanac !== undefined) {
        const av = r.almanac as Record<string, Object>
        const textValue = (name: string): string => av[name + 'Text'] !== undefined ? String(av[name + 'Text']) : (av[name] !== undefined ? String(av[name]) : '0')
        const data = new Map<string, string>()
        data.set('sunRise', textValue('sunRise'))
        data.set('sunTransit', textValue('sunTransit'))
        data.set('sunSet', textValue('sunSet'))
        data.set('moonRise', textValue('moonRise'))
        data.set('moonTransit', textValue('moonTransit'))
        data.set('moonSet', textValue('moonSet'))
        data.set('civilRise', textValue('civilRise'))
        data.set('civilSet', textValue('civilSet'))
        data.set('nauticalRise', textValue('nauticalRise'))
        data.set('nauticalSet', textValue('nauticalSet'))
        data.set('astronomicalRise', textValue('astronomicalRise'))
        data.set('astronomicalSet', textValue('astronomicalSet'))
        data.set('daylightHours', av['daylightHours'] !== undefined ? String(av['daylightHours']) : '')
        data.set('nightHours', av['nightHours'] !== undefined ? String(av['nightHours']) : '')
        data.set('moonPhase', av['moonPhase'] !== undefined ? String(av['moonPhase']) : '0')
        this.astroStore.almanacData = data
        if (Array.isArray(av['seasonEvents'])) this.astroStore.almanacSeasons = av['seasonEvents'] as Array<SeasonEvent>
        if (Array.isArray(av['solarTerms'])) this.astroStore.almanacSolarTerms = av['solarTerms'] as Array<SeasonEvent>
        if (av['seasonYear'] !== undefined) this.astroStore.almanacSeasonYear = String(av['seasonYear'])
        this.hooks.persistAlmanacCardSnapshot()
        if (this.astroStore.almanacData.size === 0) this.astroStore.almanacError = '当前没有可显示的年历数据。'
      } else {
        this.astroStore.almanacError = r.error ?? '年历计算失败，请点刷新后重试。'
      }
    }, () => {
      if (requestId !== this.almanacRequestSequence) return
      this.astroStore.almanacLoading = false
      this.astroStore.almanacError = '年历计算失败，请点刷新后重试。'
    })
  }

  // 日心黄道位置：桥查询各行星 / 彗星的日心黄道坐标（几何布局经 hooks 注入）。
  loadHeliocentricPositions(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = ++this.hecPositionsRequestSequence
    this.astroStore.hecPositions = []
    this.astroStore.hecPositionsError = ''
    this.astroStore.hecPositionsLoading = true
    const options: HeliocentricPositionOptions = {
      includeSelectedMinor: this.astroStore.hecIncludeSelectedMinor,
      includeBrightComets: this.astroStore.hecIncludeBrightComets,
      cometMagnitudeLimit: this.astroStore.hecCometMagnitudeLimit,
    }
    port.requestInteractive('getHeliocentricEclipticPositions', JSON.stringify(options), (r: StellariumBridgeResponse) => {
      if (requestId !== this.hecPositionsRequestSequence) return
      this.astroStore.hecPositionsLoading = false
      if (r.ok === true && r.hecPositions !== undefined) {
        const positions = (r.hecPositions as Array<HeliocentricPosition>).map((p: HeliocentricPosition): HeliocentricPosition => ({
          name: p.name,
          englishName: p.englishName,
          latitude: p.latitude,
          longitude: p.longitude,
          distanceAU: p.distanceAU,
          isComet: p.isComet === true,
          isSelectedMinor: p.isSelectedMinor === true,
        }))
        this.astroStore.hecPositions = this.hooks.hecLayoutPositions(positions)
        this.astroStore.hecTime = r.hecTime ?? ''
        if (this.astroStore.hecPositions.length === 0) this.astroStore.hecPositionsError = '当前没有可显示的日心位置。'
      } else {
        this.astroStore.hecPositionsError = r.error ?? '日心黄道位置计算失败，请点刷新后重试。'
      }
    }, () => {
      if (requestId !== this.hecPositionsRequestSequence) return
      this.astroStore.hecPositionsLoading = false
      this.astroStore.hecPositionsError = '日心黄道位置计算失败，请点刷新后重试。'
    })
  }

  // 目录天体位置：按分类 / 星等筛选查询目录天体位置。
  loadCelestialPositions(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const port = this.port
    if (port === null) {
      return
    }
    const requestId = ++this.celestialPositionsRequestSequence
    this.astroStore.celestialPositions = []
    this.astroStore.celestialPositionsError = ''
    this.astroStore.celestialPositionsLoading = true
    const options: CelestialPositionOptions = {
      category: this.astroStore.celestialPositionCategory,
      horizontal: this.astroStore.celestialPositionHorizontal,
      magnitudeLimit: this.astroStore.celestialPositionMagnitude,
      maximumRows: 80,
    }
    port.requestInteractive('getCelestialPositions', JSON.stringify(options), (r: StellariumBridgeResponse) => {
      if (requestId !== this.celestialPositionsRequestSequence) return
      this.astroStore.celestialPositionsLoading = false
      if (r.ok === true && r.celestialPositions !== undefined) {
        this.astroStore.celestialPositions = r.celestialPositions as Array<CelestialPosition>
        this.astroStore.celestialPositionTime = r.positionTime ?? ''
        if (this.astroStore.celestialPositions.length === 0) this.astroStore.celestialPositionsError = '当前筛选条件下没有可显示的目录天体。'
      } else {
        this.astroStore.celestialPositionsError = r.error ?? '目录天体位置计算失败，请点刷新后重试。'
      }
    }, () => {
      if (requestId !== this.celestialPositionsRequestSequence) return
      this.astroStore.celestialPositionsLoading = false
      this.astroStore.celestialPositionsError = '目录天体位置计算失败，请点刷新后重试。'
    })
  }

  // 月相加载器：桥查询未来月相序列（进行中且天数未变时跳过重复请求）。
  loadMoonPhases(): void {
    this.astroStore.updateAstroCalcSnapshot()
    const days = this.astroStore.moonPhaseDays
    if (this.astroStore.moonPhaseLoading && this.moonPhaseLoadingDays === days) return
    const port = this.port
    if (port === null) return
    const requestId = ++this.moonPhaseRequestSequence
    this.moonPhaseLoadingDays = days
    this.astroStore.moonPhaseData = []
    this.astroStore.moonPhaseError = ''
    this.astroStore.moonPhaseLoading = true
    const finish = (callback: () => void): void => {
      if (requestId !== this.moonPhaseRequestSequence) return
      callback()
    }
    // 90 天会在原生线程中逐日推进天体模型，不能使用普通交互命令的
    // 1.5 秒超时；长任务通道会持续读取异步结果，避免首次点击误报超时。
    port.requestLongRunning('getMoonPhases', JSON.stringify({ days: days }), (r: StellariumBridgeResponse) => {
      finish(() => {
        this.astroStore.moonPhaseLoading = false
        if (r.ok === true && r.moonPhases !== undefined) {
          this.astroStore.moonPhaseData = r.moonPhases as Array<MoonPhaseItem>
        } else {
          this.astroStore.moonPhaseError = r.error ?? '月相计算未能完成，请稍后重试。'
        }
      })
    }, (r: StellariumBridgeResponse) => {
      finish(() => {
        this.astroStore.moonPhaseLoading = false
        this.astroStore.moonPhaseError = r.error ?? '月相计算等待超时，请稍后重试。'
      })
    }, (r: StellariumBridgeResponse) => {
      finish(() => {
        this.astroStore.moonPhaseError = ''
      })
    }, days >= 90 ? 600 : 240)
  }

  // 天文计算上下文加载器：桥查询当前模拟时刻的观测地 / 恒星时 / 太阳月亮状态。
  loadAstroCalcContext(): void {
    if (this.astroContextRequestPending) return
    const port = this.port
    if (port === null) return
    this.astroContextRequestPending = true
    const requestId = ++this.astroContextRequestSequence
    port.requestInteractive('getAstroCalcContext', '', (r: StellariumBridgeResponse) => {
      this.astroContextRequestPending = false
      if (requestId !== this.astroContextRequestSequence) return
      if (r.ok !== true) {
        this.astroStore.astroContext = undefined
        return
      }
      this.astroStore.astroContext = {
        jd: r.jd as number,
        localTime: r.localTime as string,
        observerLocation: r.observerLocation as string,
        timeZone: r.timeZone as string,
        latitude: Number(r.latitude),
        longitude: Number(r.longitude),
        altitude: Number(r.altitude),
        meanSiderealTime: r.meanSiderealTime as string,
        apparentSiderealTime: r.apparentSiderealTime as string,
        meanSiderealHours: Number(r.meanSiderealHours),
        apparentSiderealHours: Number(r.apparentSiderealHours),
        equationOfTimeMinutes: Number(r.equationOfTimeMinutes),
        sunAltitude: Number(r.sunAltitude),
        sunAzimuth: Number(r.sunAzimuth),
        moonAltitude: Number(r.moonAltitude),
        moonAzimuth: Number(r.moonAzimuth),
        moonIllumination: Number(r.moonIllumination),
        offline: r.offline === true
      }
    }, () => {
      this.astroContextRequestPending = false
    })
  }

  // 宿主关闭天文面板时作废在途上下文请求：只递增序号、不复位 pending。
  cancelAstroCalcContext(): void {
    ++this.astroContextRequestSequence
  }

  // 标签页分发：按当前子标签 / 模式触发对应加载器。
  loadAstroTab(id: number): void {
    this.astroStore.updateAstroCalcSnapshot()
    this.loadAstroCalcContext()
    if (id === 0) {
      if (this.astroStore.positionMode === 0) {
        this.loadPlanetPositions()
      }
      else if (this.astroStore.positionMode === 1) this.loadHeliocentricPositions()
      else this.loadCelestialPositions()
    }
    else if (id === 1) this.loadEphemeris()
    else if (id === 2) this.loadRTS()
    else if (id === 3) this.loadPhenomena()
    else if (id === 4) {
      if (this.astroStore.graphMode === 2) this.loadAnnualElevation()
      else if (this.astroStore.graphMode === 3) this.loadObservabilityCalendar()
      else if (this.astroStore.graphMode === 4) this.loadLunarElongation()
      else if (this.astroStore.graphMode === 5) this.loadPlanetTimeSeries()
      else this.loadAltAzCurve()
    }
    else if (id === 5) this.loadTonightAstro()
    else if (id === 6) {
      if (this.astroStore.planetCalcMode === 1) this.loadPlanetPairDistance()
      else this.loadPlanetCalc()
    }
    else if (id === 7) {
      if (this.astroStore.eclipseMode === 0) this.loadEclipses()
      else this.loadPlanetaryTransits()
    }
    else if (id === 8) this.loadAlmanac()
    else if (id === 9) {
      this.loadMoonPhases()
    }
  }
}
