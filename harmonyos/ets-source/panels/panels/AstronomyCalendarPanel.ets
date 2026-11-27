import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyCalendarStore } from '../../state/AstronomyCalendarStore'
import { AstronomyCalendarEvent, CalendarDay, calendarEventTime, calendarDayEvents } from '../../state/AstronomyCalendarEvent'
import { calendarText, calendarMonthTitle, calendarEclipseScienceNote, calendarSolarEclipseSafetyNote } from '../../state/AstronomyCalendarText'
import { CalendarEclipseMapCard, CalendarElongationOrbitCard } from '../calendar/CalendarEventVisuals'
import { RocketLaunchSimHost, RocketLaunchSimModal } from '../calendar/RocketLaunchSimModal'
import { CalendarRocketDetailCard } from '../calendar/CalendarRocketDetailCard'
import {
  CALENDAR_QUICK_PRESETS,
  CalendarFilterCategoryMeta,
  CalendarQuickPreset,
  calendarCategoriesForPlanet,
  calendarFilterToSubscriptionMapping,
  countCalendarEventsByCategory,
  hasActiveCalendarFilter,
  isEarthCalendarPlanet,
  monthOverlapsSatelliteWindow
} from '../../state/AstronomyCalendarFilter'
import { AstronomyCalendarReminderResult } from '../../capability/AstronomyCalendarController'
import { isEventEligibleForLiveView } from '../../capability/LiveViewController'
import {
  normalizeCanonicalEventId,
  normalizeTimingMode,
  resolveReminderTimingPlan
} from '../../qability/AstronomyNotificationTiming'
import {
  findObserverRegionPreset,
  formatRegionDateTime
} from '../../state/ObserverRegionScope'
import { UI_MOTION_STANDARD_MS, UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiFadeUpTransition, uiEnterSlideTransition } from '../../common/ui/UiMotion'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { getIcon } from '../../common/ui/ShellIcons'
import { tintMatrixFor } from '../../common/ui/IconTint'

export interface AstronomyCalendarPanelHost {
  previousMonth(): void
  nextMonth(): void
  selectDay(day: number): void
  selectEvent(id: string): void
  showMonthEvents(): void
  viewSky(id: string): void
  remind(id: string): Promise<AstronomyCalendarReminderResult>
  reload(): void
  loadMore(): void
  toggleCategory?(category: string): void
  setSatelliteSubFilter?(mode: string): void
  setHighlightOnly?(enabled: boolean): void
  setSearchQuery?(query: string): void
  applyQuickPreset?(presetId: string): void
  setRegionId?(regionId: string): void
  subscribeCurrentFilter?(): void
  clearFilters?(): void
  goToCurrentMonth?(): void
  startLiveView?(event: AstronomyCalendarEvent): void
  stopLiveView?(): void
  syncRemoteFeed?(): void
  rocketSimHost?: RocketLaunchSimHost
}

interface SatelliteSubOption {
  id: string
  labelZh: string
  labelEn: string
}

const SAT_SUB_OPTIONS: SatelliteSubOption[] = [
  { id: 'all', labelZh: '全部卫星', labelEn: 'All' },
  { id: 'stations', labelZh: '空间站', labelEn: 'Stations' },
  { id: 'visible', labelZh: '日照可见', labelEn: 'Visible' },
  { id: 'high_alt', labelZh: '≥30°高角', labelEn: '≥30° Alt' }
]

@Component
export struct AstronomyCalendarPanel {
  @ObjectLink calendarStore: AstronomyCalendarStore
  host: AstronomyCalendarPanelHost = {
    previousMonth: () => {}, nextMonth: () => {}, selectDay: () => {}, selectEvent: () => {},
    showMonthEvents: () => {}, viewSky: () => {}, remind: async () => ({ ok: false, reason: 'host-unavailable' }),
    reload: () => {}, loadMore: () => {},
    toggleCategory: () => {}, setSatelliteSubFilter: () => {}, setHighlightOnly: () => {},
    clearFilters: () => {}, goToCurrentMonth: () => {}
  }
  @Prop language: string = 'zh'
  @Prop panelFontSize: number = 14
  @Prop textColor: ResourceColor = '#F3F5FA'
  @Prop secondaryColor: ResourceColor = '#B7C3D9'
  @Prop accentColor: ResourceColor = '#344E79'
  @Prop cardColor: ResourceColor = '#182235'
  @Prop followLocationName: string = ''
  @Prop remindedEventIds: string[] = []
  @Prop notificationTimingMode: string = 'smart'
  @Prop notificationPassLeadMinutes: number = 10
  @Prop observerLatitude: number = 39.9
  @Prop observerLongitude: number = 116.4
  @Prop earthMapUri: string = ''
  @Prop onlineMapAllowed: boolean = false
  @Prop activeLiveViewEventId: string = ''
  @Prop liveViewStatusText: string = ''
  @Prop remoteFeedStatus: string = ''
  @Prop remoteFeedSyncing: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private viewMode: 'list' | 'grid' = 'list'
  @State private transitionDir: number = 1
  @State private filterDrawerOpen: boolean = false
  @State private showPastEvents: boolean = false
  @State private rocketSimOpen: boolean = false

  @Builder
  private rocketSimModalBuilder() {
    RocketLaunchSimModal({
      language: this.language,
      earthMapUri: this.earthMapUri,
      onlineMapAllowed: this.onlineMapAllowed,
      host: this.host.rocketSimHost ?? {
        loadCatalog: () => {},
        runSimulation: () => {},
        previewInSky: () => {}
      },
      onClose: () => { this.rocketSimOpen = false }
    })
  }

  private startOfTodayMs(): number {
    const now = new Date()
    return new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  }

  private isViewingCurrentMonth(): boolean {
    const now = new Date()
    return this.calendarStore.year === now.getFullYear() && this.calendarStore.month === (now.getMonth() + 1)
  }

  private shouldFoldPastEventsInList(): boolean {
    return this.viewMode === 'list' &&
      this.calendarStore.selectedDay === 0 &&
      !this.filterActive() &&
      this.isViewingCurrentMonth()
  }

  private pastEventsInList(): AstronomyCalendarEvent[] {
    if (!this.shouldFoldPastEventsInList()) return []
    const cutoff = this.startOfTodayMs()
    return this.calendarStore.visibleEvents().filter((ev: AstronomyCalendarEvent) => ev.at < cutoff)
  }

  private mainEventsInList(): AstronomyCalendarEvent[] {
    const all = this.calendarStore.visibleEvents()
    if (!this.shouldFoldPastEventsInList()) return all
    const cutoff = this.startOfTodayMs()
    const upcoming = all.filter((ev: AstronomyCalendarEvent) => ev.at >= cutoff)
    return upcoming.length > 0 ? upcoming : all
  }

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private t(chinese: string, english: string): string {
    return calendarText(this.language, chinese, english)
  }

  private isZh(): boolean {
    return this.language.toLowerCase().startsWith('zh')
  }

  private animateAction(direction: number, action: () => void): void {
    this.transitionDir = direction
    this.getUIContext().animateTo({ duration: UI_MOTION_STANDARD_MS, curve: Curve.EaseOut }, action)
  }

  private weekdayLabels(): string[] {
    return this.isZh()
      ? ['日', '一', '二', '三', '四', '五', '六']
      : ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
  }

  private fixedSixRowDays(): CalendarDay[] {
    const cells: CalendarDay[] = this.calendarStore.days.slice()
    while (cells.length < 42) {
      cells.push({
        key: `${this.calendarStore.year}-${this.calendarStore.month}-pad-${cells.length}`,
        day: 0,
        count: 0
      })
    }
    return cells.slice(0, 42)
  }

  private eventPriority(event: AstronomyCalendarEvent): number {
    if (event.isRemote === true) return 0
    if (event.kind === 'solar-eclipse' || event.kind === 'lunar-eclipse') return 0
    if (event.kind === 'meteor-peak' || event.kind === 'companion-eclipse') return 0
    if (event.kind === 'satellite-pass') return event.satVisible === true ? 0 : 1
    if (event.kind === 'planetary-event') return 1
    if (event.kind === 'moon-phase' || event.kind === 'companion-phase') return event.isSupermoon === true ? 0 : 2
    return 3
  }

  private dayEventsSorted(day: number): AstronomyCalendarEvent[] {
    if (day <= 0) return []
    const monthEvents = this.calendarStore.filteredEvents().filter((event: AstronomyCalendarEvent) => {
      const d = new Date(event.at)
      return d.getFullYear() === this.calendarStore.year && (d.getMonth() + 1) === this.calendarStore.month
    })
    return calendarDayEvents(monthEvents, day)
      .sort((a: AstronomyCalendarEvent, b: AstronomyCalendarEvent) => this.eventPriority(a) - this.eventPriority(b) || a.at - b.at)
  }

  private eventDotColor(event: AstronomyCalendarEvent): ResourceColor {
    if (this.c.isNight) return this.c.accent
    if (event.isRemote === true || event.kind === 'aurora-alert' || event.kind === 'comet-event' ||
      event.kind === 'spaceflight' || event.kind === 'transient' || event.kind === 'editorial') return '#CE93D8'
    if (event.kind === 'solar-eclipse' || event.kind === 'lunar-eclipse' || event.kind === 'companion-eclipse') return '#FF7043'
    if (event.kind === 'satellite-pass') return '#4DD0E1'
    if (event.kind === 'meteor-peak') return '#64B5F6'
    if (event.kind === 'planetary-event') return '#FFB74D'
    if (event.kind === 'moon-phase' || event.kind === 'companion-phase') return event.isSupermoon === true ? '#FFE082' : '#E0E6F2'
    return '#81C784'
  }

  private isCategorySelected(categoryId: string): boolean {
    return this.calendarStore.selectedCategories.includes(categoryId)
  }

  private filterActive(): boolean {
    return hasActiveCalendarFilter(this.calendarStore.filterState(), this.calendarStore.observerPlanet)
  }

  private advancedFilterActive(): boolean {
    return this.calendarStore.highlightOnly ||
      this.calendarStore.searchQuery.trim().length > 0 ||
      (isEarthCalendarPlanet(this.calendarStore.observerPlanet) && this.calendarStore.satelliteSubFilter !== 'all')
  }

  private isEventReminded(eventId: string): boolean {
    const norm = normalizeCanonicalEventId(eventId)
    return norm.length > 0 && this.remindedEventIds.includes(norm)
  }

  private eventDisplayTime(event: AstronomyCalendarEvent): string {
    const preset = isEarthCalendarPlanet(this.calendarStore.observerPlanet)
      ? findObserverRegionPreset(this.calendarStore.regionId) : undefined
    if (preset !== undefined) {
      const timeStr = formatRegionDateTime(event.at, preset.utcOffsetMinutes, this.isZh())
      return `${timeStr} (${this.isZh() ? preset.tzLabelZh : preset.tzLabelEn})`
    }
    return calendarEventTime(event)
  }

  private timingPreviewForEvent(event: AstronomyCalendarEvent): string {
    const plan = resolveReminderTimingPlan(event, {
      nowMs: Date.now(),
      timingMode: normalizeTimingMode(this.notificationTimingMode),
      passLeadMinutes: this.notificationPassLeadMinutes,
      regionId: this.calendarStore.regionId
    })
    return this.isZh() ? plan.summaryZh : plan.summaryEn
  }

  private satelliteFilterSelectedOutsideWindow(): boolean {
    return isEarthCalendarPlanet(this.calendarStore.observerPlanet) &&
      this.isCategorySelected('satellite') &&
      !monthOverlapsSatelliteWindow(this.calendarStore.year, this.calendarStore.month)
  }

  private showSatelliteSubRow(): boolean {
    if (!isEarthCalendarPlanet(this.calendarStore.observerPlanet)) return false
    return this.calendarStore.selectedCategories.length === 0 || this.isCategorySelected('satellite')
  }

  private satelliteIconResource(archetype: string | undefined): Resource {
    if (archetype === 'iss') return $r('app.media.sat_icon_iss')
    if (archetype === 'tiangong') return $r('app.media.sat_icon_tiangong')
    if (archetype === 'telescope') return $r('app.media.sat_icon_telescope')
    if (archetype === 'comms') return $r('app.media.sat_icon_comms')
    if (archetype === 'earth_obs') return $r('app.media.sat_icon_earth_obs')
    return $r('app.media.sat_icon_constellation')
  }

  private satelliteArchetypeLabel(archetype: string | undefined): string {
    if (archetype === 'iss') return this.t('国际空间站', 'ISS')
    if (archetype === 'tiangong') return this.t('中国空间站', 'Tiangong')
    if (archetype === 'telescope') return this.t('空间望远镜', 'Telescope')
    if (archetype === 'comms') return this.t('通信卫星', 'Comms')
    if (archetype === 'earth_obs') return this.t('对地观测', 'Earth Obs')
    return this.t('过境卫星', 'Satellite')
  }

  @Builder
  filterBar() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Scroll() {
          Row({ space: 6 }) {
            // 「全部」快选胶囊
            Text(this.t('全部', 'All'))
              .fontSize(this.panelFontSize - 2)
              .fontWeight(!this.filterActive() ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(!this.filterActive() ? this.c.onAccent : this.c.sub)
              .padding({ left: 11, right: 11, top: 6, bottom: 6 })
              .backgroundColor(!this.filterActive() ? this.c.accent : this.c.softStrong)
              .borderRadius(UI_RADIUS_PILL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
              .onClick(() => {
                if (this.filterActive()) {
                  this.animateAction(0, () => { this.host.clearFilters?.() })
                }
              })
            ForEach(calendarCategoriesForPlanet(this.calendarStore.observerPlanet), (cat: CalendarFilterCategoryMeta) => {
              Row({ space: 5 }) {
                Circle({ width: 6, height: 6 })
                  .fill(this.isCategorySelected(cat.id) ? this.c.onAccent : (this.c.isNight ? this.c.accent : cat.dotHex))
                Text((this.isZh() ? cat.labelZh : cat.labelEn) +
                  ((countCalendarEventsByCategory(this.calendarStore.events)[cat.id] ?? 0) > 0
                    ? (' ' + String(countCalendarEventsByCategory(this.calendarStore.events)[cat.id]))
                    : ''))
                  .fontSize(this.panelFontSize - 2)
                  .fontWeight(this.isCategorySelected(cat.id) ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.isCategorySelected(cat.id) ? this.c.onAccent : this.c.text)
                  .maxLines(1)
              }
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(this.isCategorySelected(cat.id) ? this.c.accent : this.c.softStrong)
                .borderRadius(UI_RADIUS_PILL)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                .onClick(() => {
                  this.animateAction(0, () => { this.host.toggleCategory?.(cat.id) })
                })
            }, (cat: CalendarFilterCategoryMeta) => `${cat.id}:${this.calendarStore.filterRevision}:${this.calendarStore.events.length}:${this.language}`)
          }.padding({ right: 4 })
        }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .layoutWeight(1)

        // 右侧高级筛选开关按钮（带激活小圆点）
        Row({ space: 4 }) {
          if (this.advancedFilterActive()) {
            Circle({ width: 6, height: 6 }).fill(this.filterDrawerOpen ? this.c.onAccent : this.c.accent)
          }
          Text(this.filterDrawerOpen ? this.t('收起 ▴', 'Hide') : this.t('筛选 ▾', 'Filter'))
            .fontSize(this.panelFontSize - 2)
            .fontWeight(this.advancedFilterActive() || this.filterDrawerOpen ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.filterDrawerOpen ? this.c.onAccent : this.c.text)
        }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.filterDrawerOpen ? this.c.accent : this.c.softStrong)
          .borderRadius(UI_RADIUS_PILL)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
          .onClick(() => {
            this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
              this.filterDrawerOpen = !this.filterDrawerOpen
            })
          })
      }.width('100%').alignItems(VerticalAlign.Center)

      if (this.filterDrawerOpen) {
        Column({ space: 10 }) {
          // 快速关键词搜索框
          Row({ space: 6 }) {
            TextInput({
              text: this.calendarStore.searchQuery,
              placeholder: this.t('搜索行星、流星雨、超级满月或空间站…', 'Search planet, meteor, supermoon or ISS…')
            })
              .height(34)
              .layoutWeight(1)
              .fontSize(this.panelFontSize - 2)
              .fontColor(this.c.text)
              .placeholderColor(this.c.sub)
              .backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL)
              .padding({ left: 10, right: 10 })
              .onChange((val: string) => {
                this.host.setSearchQuery?.(val)
              })
            if (this.calendarStore.searchQuery.length > 0) {
              Button(this.t('清空', 'Clear'), { type: ButtonType.Normal })
                .height(34).padding({ left: 10, right: 10 }).fontSize(this.panelFontSize - 3)
                .fontColor(this.c.sub).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => this.host.setSearchQuery?.(''))
            }
          }.width('100%')

          // 一键快捷筛选场景
          if (isEarthCalendarPlanet(this.calendarStore.observerPlanet)) {
            Row({ space: 6 }) {
              ForEach(CALENDAR_QUICK_PRESETS, (preset: CalendarQuickPreset) => {
                Text(this.isZh() ? preset.labelZh : preset.labelEn)
                  .fontSize(this.panelFontSize - 3)
                  .fontColor(this.c.text)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .padding({ left: 6, right: 6, top: 6, bottom: 6 })
                  .backgroundColor(this.c.bg)
                  .border({ width: 1, color: this.c.dividerSoft })
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => {
                    this.animateAction(0, () => { this.host.applyQuickPreset?.(preset.id) })
                  })
              }, (preset: CalendarQuickPreset) => preset.id + ':' + this.language)
            }.width('100%')
          }

          // 仅看重磅 / 高可见开关
          Row({ space: 6 }) {
            Row({ space: 2 }) {
              Text(this.t('仅看重磅 / 高可见天象', 'Highlights & bright passes only'))
                .fontSize(this.panelFontSize - 2)
                .fontColor(this.c.text)
              InfoTipButton({
                title: this.t('重磅天象筛选', 'Highlight Filter'),
                tip: this.t('保留流星雨极大、超级满月、行星冲日/大距/合相、伴星食，以及空间站和高仰角可见卫星过境。',
                  'Shows meteor peaks, supermoons, planetary oppositions/elongations/conjunctions, eclipses, space stations, and bright high-elevation satellite passes.')
              })
            }.layoutWeight(1).alignItems(VerticalAlign.Center)
            Toggle({ type: ToggleType.Switch, isOn: this.calendarStore.highlightOnly })
              .width(42).height(24).selectedColor(this.c.accent)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onChange((enabled: boolean) => {
                this.host.setHighlightOnly?.(enabled)
              })
          }.width('100%')

          // 卫星过境子筛选（仅地球且包含卫星类别时显示）
          if (this.showSatelliteSubRow()) {
            Column({ space: 6 }) {
              Row({ space: 4 }) {
                Text(this.t('卫星过境条件', 'Satellite pass filter'))
                  .fontSize(this.panelFontSize - 3)
                  .fontColor(this.c.sub)
                InfoTipButton({
                  title: this.t('卫星过境预报', 'Satellite Passes'),
                  tip: this.t('基于本地 TLE 轨道根数推演近 48 小时内的空间站与亮卫星过境（仰角 ≥15°）。超过 48 小时的远期月份不包含卫星过境。',
                    'Predicts space station & bright satellite passes (≥15° alt) over the next 48 hours from local TLE data.')
                })
              }.width('100%').alignItems(VerticalAlign.Center)
              Row({ space: 6 }) {
                ForEach(SAT_SUB_OPTIONS, (opt: SatelliteSubOption) => {
                  Text(this.isZh() ? opt.labelZh : opt.labelEn)
                    .fontSize(this.panelFontSize - 3)
                    .fontColor(this.calendarStore.satelliteSubFilter === opt.id ? this.c.onAccent : this.c.sub)
                    .textAlign(TextAlign.Center)
                    .layoutWeight(1)
                    .padding({ left: 4, right: 4, top: 6, bottom: 6 })
                    .backgroundColor(this.calendarStore.satelliteSubFilter === opt.id ? this.c.accent : this.c.bg)
                    .borderRadius(UI_RADIUS_CONTROL)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .clickEffect({ level: ClickEffectLevel.LIGHT })
                    .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .onClick(() => {
                      this.host.setSatelliteSubFilter?.(opt.id)
                    })
                }, (opt: SatelliteSubOption) => `${opt.id}:${this.calendarStore.satelliteSubFilter}:${this.language}`)
              }.width('100%')
            }.width('100%')
          }

          Row({ space: 8 }) {
            Button(this.t('按当前筛选订阅通知', 'Subscribe to Filter'), { type: ButtonType.Normal })
              .height(32).layoutWeight(1).fontSize(this.panelFontSize - 3)
              .fontColor(this.c.onAccent).backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.host.subscribeCurrentFilter?.() })
            if (this.filterActive()) {
              Button(this.t('重置筛选', 'Reset'), { type: ButtonType.Normal })
                .height(32).padding({ left: 12, right: 12 }).fontSize(this.panelFontSize - 3)
                .fontColor(this.c.text).backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => {
                  this.animateAction(0, () => { this.host.clearFilters?.() })
                })
            }
          }.width('100%').alignItems(VerticalAlign.Center)
        }
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.soft)
          .border({ width: 1, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)
          .transition(uiFadeUpTransition())
      }

      if (this.satelliteFilterSelectedOutsideWindow()) {
        Row({ space: 8 }) {
          Text(this.t('卫星过境预报仅覆盖近 48 小时，当前月份不在预报窗口内。',
            'Satellite passes cover the next 48 hours only.'))
            .fontSize(this.panelFontSize - 3)
            .fontColor(this.c.sub)
            .layoutWeight(1)
            .maxLines(2)
          Button(this.t('回到本月', 'This month'), { type: ButtonType.Normal })
            .height(30).padding({ left: 10, right: 10 }).fontSize(this.panelFontSize - 3)
            .fontColor(this.c.onAccent).backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              this.animateAction(-1, () => { this.host.goToCurrentMonth?.() })
            })
        }
          .width('100%')
          .padding({ left: 12, right: 10, top: 8, bottom: 8 })
          .backgroundColor(this.c.soft)
          .border({ width: 1, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)
          .transition(uiFadeUpTransition())
      }
    }.width('100%')
  }

  @Builder
  monthGrid() {
    Column({ space: 8 }) {
      // 月份切换仅在「月历」视图显示；左右箭头用居中 SVG 图标，彻底消除字符基线偏移。
      Row({ space: 8 }) {
        Row() {
          Image(getIcon('chevron_right', false))
            .width(16)
            .height(16)
            .rotate({ angle: 180 })
            .supportSvg2(true)
            .colorFilter(tintMatrixFor(this.c.text))
        }
          .width(34)
          .height(34)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.c.softStrong)
          .borderRadius(UI_RADIUS_PILL)
          .opacity((this.calendarStore.year === 1 && this.calendarStore.month === 1) ? 0.35 : 1)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .accessibilityText(this.t('上个月', 'Previous month'))
          .enabled(!(this.calendarStore.year === 1 && this.calendarStore.month === 1))
          .onClick(() => { this.animateAction(-1, () => { this.host.previousMonth() }) })

        Row({ space: 6 }) {
          Text(calendarMonthTitle(this.language, this.calendarStore.year, this.calendarStore.month))
            .fontSize(this.panelFontSize + 1)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.text)
            .maxLines(1)
          if (!this.isViewingCurrentMonth()) {
            Text(this.t('本月', 'Today'))
              .fontSize(this.panelFontSize - 4)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.accent)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.c.softStrong)
              .borderRadius(UI_RADIUS_PILL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.animateAction(0, () => { this.host.goToCurrentMonth?.() }) })
          }
        }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)

        Row() {
          Image(getIcon('chevron_right', false))
            .width(16)
            .height(16)
            .supportSvg2(true)
            .colorFilter(tintMatrixFor(this.c.text))
        }
          .width(34)
          .height(34)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.c.softStrong)
          .borderRadius(UI_RADIUS_PILL)
          .opacity((this.calendarStore.year === 3000 && this.calendarStore.month === 12) ? 0.35 : 1)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .accessibilityText(this.t('下个月', 'Next month'))
          .enabled(!(this.calendarStore.year === 3000 && this.calendarStore.month === 12))
          .onClick(() => { this.animateAction(1, () => { this.host.nextMonth() }) })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        ForEach(this.weekdayLabels(), (label: string) => {
          Text(label).fontSize(this.panelFontSize - 3).fontColor(this.c.sub)
            .textAlign(TextAlign.Center).layoutWeight(1)
        }, (label: string) => label)
      }.width('100%').padding({ top: 2, bottom: 2 })
      Grid() {
        ForEach(this.fixedSixRowDays(), (cell: CalendarDay) => {
          GridItem() {
            if (cell.day > 0) {
              Column({ space: 3 }) {
                Text(String(cell.day))
                  .fontSize(this.panelFontSize - 2)
                  .fontWeight(this.calendarStore.selectedDay === cell.day ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.calendarStore.selectedDay === cell.day ? this.c.onAccent : this.c.text)
                if (cell.count > 0) {
                  Row({ space: 3 }) {
                    ForEach(this.dayEventsSorted(cell.day).slice(0, 2), (ev: AstronomyCalendarEvent) => {
                      Circle({ width: 5, height: 5 }).fill(this.eventDotColor(ev))
                    }, (ev: AstronomyCalendarEvent) => ev.id)
                    if (cell.count > 2) {
                      Text('+' + String(cell.count - 2)).fontSize(9)
                        .fontColor(this.calendarStore.selectedDay === cell.day ? this.c.onAccent : this.c.sub)
                    }
                  }.justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
                }
              }
                .width('100%').height(44).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                .borderRadius(UI_RADIUS_CONTROL)
                .backgroundColor(this.calendarStore.selectedDay === cell.day ? this.c.accent :
                  (cell.count > 0 ? this.c.softStrong : Color.Transparent))
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => {
                  this.animateAction(1, () => {
                    if (this.calendarStore.selectedDay === cell.day) this.host.showMonthEvents()
                    else this.host.selectDay(cell.day)
                  })
                })
            } else {
              Column().width('100%').height(44)
            }
          }
        }, (cell: CalendarDay) => `${cell.key}:${cell.count}:${this.calendarStore.selectedDay === cell.day ? 1 : 0}:${this.calendarStore.filterRevision}`)
      }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
        .columnsGap(4).rowsGap(4)
        .width('100%').height(284)
      if (this.calendarStore.selectedDay > 0) {
        Row({ space: 8 }) {
          Text(this.t(`${this.calendarStore.month}月${this.calendarStore.selectedDay}日天象`,
            `Events on ${this.calendarStore.month}/${this.calendarStore.selectedDay}`))
            .fontSize(this.panelFontSize - 2).fontColor(this.c.sub).layoutWeight(1)
          Button(this.t('显示整月', 'Show full month'), { type: ButtonType.Normal })
            .height(30).padding({ left: 10, right: 10 }).fontSize(this.panelFontSize - 3)
            .fontColor(this.c.text).backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.animateAction(-1, () => { this.host.showMonthEvents() }) })
        }.width('100%').padding({ top: 4 })
      }
    }
      .width('100%').padding(10).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
      .border({ width: 1, color: this.c.border })
      .transition(uiFadeUpTransition())
  }

  private art(event: AstronomyCalendarEvent, detail: boolean): Resource {
    if (event.kind === 'solar-eclipse') {
      return detail ? $r('app.media.calendar_solar_eclipse_detail') : $r('app.media.calendar_solar_eclipse')
    }
    if (event.kind === 'lunar-eclipse') {
      return detail ? $r('app.media.calendar_lunar_eclipse_detail') : $r('app.media.calendar_lunar_eclipse')
    }
    if (event.kind === 'moon-phase') {
      if (event.phaseIndex === 0) return detail ? $r('app.media.calendar_moon_0_detail') : $r('app.media.calendar_moon_0')
      if (event.phaseIndex === 1) return detail ? $r('app.media.calendar_moon_1_detail') : $r('app.media.calendar_moon_1')
      if (event.phaseIndex === 3) return detail ? $r('app.media.calendar_moon_3_detail') : $r('app.media.calendar_moon_3')
      return detail ? $r('app.media.calendar_moon_2_detail') : $r('app.media.calendar_moon_2')
    }
    if (event.kind === 'meteor-peak' || event.kind === 'rocket-launch') return detail ? $r('app.media.calendar_meteor_detail') : $r('app.media.calendar_meteor')
    if (event.kind === 'solar-term' || event.kind === 'planetary-season' || event.kind === 'companion-eclipse') {
      return detail ? $r('app.media.calendar_solar_detail') : $r('app.media.calendar_solar')
    }
    if (event.target === 'Mercury') return detail ? $r('app.media.calendar_mercury_detail') : $r('app.media.calendar_mercury')
    if (event.target === 'Venus') return detail ? $r('app.media.calendar_venus_detail') : $r('app.media.calendar_venus')
    if (event.target === 'Mars') return detail ? $r('app.media.calendar_mars_detail') : $r('app.media.calendar_mars')
    if (event.target === 'Saturn') return detail ? $r('app.media.calendar_saturn_detail') : $r('app.media.calendar_saturn')
    if (event.target === 'Uranus') return detail ? $r('app.media.calendar_uranus_detail') : $r('app.media.calendar_uranus')
    if (event.target === 'Neptune') return detail ? $r('app.media.calendar_neptune_detail') : $r('app.media.calendar_neptune')
    return detail ? $r('app.media.calendar_planet_detail') : $r('app.media.calendar_planet')
  }

  private date(event: AstronomyCalendarEvent): string {
    const date = new Date(event.at)
    const y = date.getFullYear()
    const m = date.getMonth() + 1
    const d = date.getDate()
    const prefixZh = y !== this.calendarStore.year ? `${y}年` : ''
    const prefixEn = y !== this.calendarStore.year ? `${y}-` : ''
    if (event.kind === 'satellite-pass' || event.kind === 'rocket-launch') {
      const hh = String(date.getHours()).padStart(2, '0')
      const mm = String(date.getMinutes()).padStart(2, '0')
      return this.t(`${prefixZh}${m}月${d}日 ${hh}:${mm}`, `${prefixEn}${m}/${d} ${hh}:${mm}`)
    }
    return this.t(`${prefixZh}${m}月${d}日`, `${prefixEn}${m}/${d}`)
  }

  @Builder
  satellitePassCard(event: AstronomyCalendarEvent, detail: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      // 深空轨道底板
      Column()
        .width('100%')
        .height(detail ? 176 : 108)
        .linearGradient({
          angle: 135,
          colors: this.c.isNight
            ? [['#250806', 0.0], ['#140404', 1.0]]
            : [['#102B3D', 0.0], ['#0B1A2B', 0.6], ['#0A1522', 1.0]]
        })
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text(this.satelliteArchetypeLabel(event.satArchetype))
              .fontSize(this.panelFontSize - 4)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.isNight ? this.c.text : '#7CE7F5')
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.c.isNight ? this.c.softStrong : 'rgba(77,208,225,0.18)')
              .borderRadius(UI_RADIUS_PILL)
            Text(event.satVisible === true ? this.t('日照可见', 'Sunlit') : this.t('轨道过境', 'Pass'))
              .fontSize(this.panelFontSize - 4)
              .fontColor(this.c.isNight ? this.c.sub : (event.satVisible === true ? '#FFD978' : '#A8C4D8'))
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.c.isNight ? this.c.bg : 'rgba(255,255,255,0.08)')
              .borderRadius(UI_RADIUS_PILL)
          }
          Text(this.date(event) + (event.satAzimuthSummary ? (' · ' + event.satAzimuthSummary) : ''))
            .fontSize(this.panelFontSize - 3)
            .fontColor(this.c.isNight ? this.c.sub : '#B7D4E8')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(event.title)
            .fontSize(this.panelFontSize + (detail ? 4 : 1))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.isNight ? this.c.text : '#F3F7FC')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

        Image(this.satelliteIconResource(event.satArchetype))
          .width(detail ? 68 : 52)
          .height(detail ? 68 : 52)
          .objectFit(ImageFit.Contain)
          .accessibilityLevel('no')
      }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .alignItems(VerticalAlign.Center)
    }
      .width('100%')
      .borderRadius(UI_RADIUS_CARD)
      .border({ width: 1, color: this.c.isNight ? this.c.border : 'rgba(116,216,240,0.24)' })
      .clip(true)
  }

  private remoteGradientColors(kind: string): Array<[ResourceColor, number]> {
    if (this.c.isNight) {
      return [['#260908', 0.0], ['#140404', 1.0]]
    }
    if (kind === 'aurora-alert') {
      return [['#0F3530', 0.0], ['#1E1B42', 0.55], ['#0F1326', 1.0]]
    }
    if (kind === 'comet-event') {
      return [['#122B4A', 0.0], ['#162040', 0.58], ['#0C1428', 1.0]]
    }
    if (kind === 'spaceflight') {
      return [['#1B2748', 0.0], ['#2B1F3A', 0.58], ['#121324', 1.0]]
    }
    return [['#241C42', 0.0], ['#151C36', 0.6], ['#0E1426', 1.0]]
  }

  private remoteAccentHex(kind: string): ResourceColor {
    if (this.c.isNight) return this.c.text
    if (kind === 'aurora-alert') return '#7DF9C6'
    if (kind === 'comet-event') return '#8AD8FF'
    if (kind === 'spaceflight') return '#FFD180'
    return '#E1B7FF'
  }

  @Builder
  remoteDynamicCard(event: AstronomyCalendarEvent, detail: boolean) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column()
        .width('100%')
        .height(detail ? 172 : 108)
        .linearGradient({
          angle: 135,
          colors: this.remoteGradientColors(event.kind)
        })
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(event.remoteBadge && event.remoteBadge.length > 0
            ? event.remoteBadge
            : this.t('动态天象', 'Live Alert'))
            .fontSize(this.panelFontSize - 4)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.remoteAccentHex(event.kind))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor(this.c.isNight ? this.c.softStrong : 'rgba(255,255,255,0.12)')
            .borderRadius(UI_RADIUS_PILL)
          Text(this.t('云端实时', 'Live'))
            .fontSize(this.panelFontSize - 4)
            .fontColor(this.c.isNight ? this.c.sub : '#D8C9F2')
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor(this.c.isNight ? this.c.bg : 'rgba(206,147,216,0.18)')
            .borderRadius(UI_RADIUS_PILL)
        }
        Text(this.date(event))
          .fontSize(this.panelFontSize - 2)
          .fontColor(this.c.isNight ? this.c.sub : '#C8D2E8')
        Text(event.title)
          .fontSize(this.panelFontSize + (detail ? 6 : 2))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.isNight ? this.c.text : '#F4F7FC')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 14 })
    }
      .width('100%')
      .borderRadius(UI_RADIUS_CARD)
      .border({ width: 1, color: this.c.isNight ? this.c.border : 'rgba(206,147,216,0.32)' })
      .clip(true)
  }

  @Builder
  eventCard(event: AstronomyCalendarEvent, detail: boolean) {
    if (event.kind === 'satellite-pass') {
      this.satellitePassCard(event, detail)
    } else if (event.isRemote === true) {
      this.remoteDynamicCard(event, detail)
    } else {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (detail) {
          Image(this.art(event, true)).width('100%').aspectRatio(1.65).objectFit(ImageFit.Contain)
            .accessibilityLevel('no')
        } else {
          Image(this.art(event, false)).width('100%').height(108).objectFit(ImageFit.Cover)
            .accessibilityLevel('no')
        }
        if (this.c.isNight) {
          if (detail) {
            Row().width('100%').aspectRatio(1.65).backgroundColor(this.c.nightMask)
              .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
          } else {
            Row().width('100%').height(108).backgroundColor(this.c.nightMask)
              .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
          }
        }
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text(this.date(event)).fontSize(this.panelFontSize - 2).fontColor(this.c.isNight ? this.c.sub : '#C3CCDB')
            if (event.remoteEnriched === true) {
              Text(event.remoteBadge && event.remoteBadge.length > 0 ? event.remoteBadge : this.t('观星攻略', 'Guide'))
                .fontSize(this.panelFontSize - 4)
                .fontColor(this.c.isNight ? this.c.text : '#E1B7FF')
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .backgroundColor(this.c.isNight ? this.c.softStrong : 'rgba(206,147,216,0.22)')
                .borderRadius(UI_RADIUS_PILL)
            }
          }.alignItems(VerticalAlign.Center)
          Text(event.title).fontSize(this.panelFontSize + (detail ? 7 : 3)).fontWeight(FontWeight.Medium)
            .fontColor(this.c.isNight ? this.c.text : '#F1F3F7').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).width('72%').padding(18)
      }.width('100%').borderRadius(UI_RADIUS_CARD).clip(true)
    }
  }

  build() {
    Column({ space: 14 }) {
      if (this.calendarStore.selectedEventId === '') {
        Column({ space: 12 }) {
          Row({ space: 6 }) {
            Button(this.t('列表', 'List'), { type: ButtonType.Normal })
              .height(34).layoutWeight(1).fontSize(this.panelFontSize - 2).borderRadius(UI_RADIUS_CONTROL)
              .backgroundColor(this.viewMode === 'list' ? this.c.accent : this.c.softStrong)
              .fontColor(this.viewMode === 'list' ? this.c.onAccent : this.c.text)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                if (this.viewMode === 'list') return
                this.animateAction(-1, () => {
                  this.viewMode = 'list'
                  if (this.calendarStore.selectedDay > 0) this.host.showMonthEvents()
                })
              })
            Button(this.t('月历', 'Month grid'), { type: ButtonType.Normal })
              .height(34).layoutWeight(1).fontSize(this.panelFontSize - 2).borderRadius(UI_RADIUS_CONTROL)
              .backgroundColor(this.viewMode === 'grid' ? this.c.accent : this.c.softStrong)
              .fontColor(this.viewMode === 'grid' ? this.c.onAccent : this.c.text)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                if (this.viewMode === 'grid') return
                this.animateAction(1, () => { this.viewMode = 'grid' })
              })
          }.width('100%')

          // 地球视角下展示云端动态天象同步条（日历固定跟随当前地球观测位置，不再单独选自定义区域）
          if (isEarthCalendarPlanet(this.calendarStore.observerPlanet)) {
            Row({ space: 6 }) {
              Circle({ width: 6, height: 6 })
                .fill(this.c.isNight ? this.c.accent : '#CE93D8')
              Text(this.remoteFeedStatus.length > 0
                ? this.remoteFeedStatus
                : this.t('云端动态天象 · 自动静默同步', 'Live astronomy feed · auto sync'))
                .fontSize(this.panelFontSize - 3)
                .fontColor(this.c.sub)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              InfoTipButton({
                title: this.t('云端动态天象', 'Live Astronomy Feed'),
                tip: this.t('打开应用时从自有境内镜像 skyinstrument.cn 只读静态检查地磁极光预警、新彗星、航天发射与观星攻略，经 SHA-256 校验后自动合并入日历。地区筛选在设备本地完成，不上传经纬度或设备标识。',
                  'Checks skyinstrument.cn read-only static feed on launch for aurora alerts, comets, spaceflight & observing notes with SHA-256 verification. Region filtering runs locally with zero location upload.')
              })
              Button(this.remoteFeedSyncing ? this.t('同步中…', 'Syncing…') : this.t('同步', 'Sync'),
                { type: ButtonType.Normal })
                .height(28)
                .padding({ left: 10, right: 10 })
                .fontSize(this.panelFontSize - 3)
                .fontColor(this.c.text)
                .backgroundColor(this.c.softStrong)
                .borderRadius(UI_RADIUS_PILL)
                .enabled(!this.remoteFeedSyncing)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.host.syncRemoteFeed?.() })
            }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 10, right: 8, top: 6, bottom: 6 })
              .backgroundColor(this.c.soft)
              .border({ width: 0.6, color: this.c.border })
              .borderRadius(UI_RADIUS_CONTROL)

            // 自定义火箭弹道 / 粘贴 NOTAM 仿真快捷入口（具体发射任务已作为一等卡片直接融入下方日历流）
            if (this.host.rocketSimHost !== undefined) {
              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Row({ space: 6 }) {
                    Text(this.t('自定义火箭弹道 / 粘贴 NOTAM 仿真', 'Custom Rocket Trajectory / NOTAM Sim'))
                      .fontSize(this.panelFontSize - 2)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.c.textStrong)
                    Text(this.t('3D 地球', '3D Globe'))
                      .fontSize(9)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.c.onAccent)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(this.c.accent)
                      .borderRadius(UI_RADIUS_PILL)
                  }.alignItems(VerticalAlign.Center)
                  Text(this.t('支持 16 发射场 · 22 箭型 · 粘贴航警自动反演落区与火箭云', '16 Pads · 22 Vehicles · Paste NOTAM to Invert Drop Zone & Plume'))
                    .fontSize(this.panelFontSize - 3)
                    .fontColor(this.c.sub)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text('↗')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.c.accent)
              }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.c.soft)
                .border({ width: 0.8, color: this.c.border })
                .borderRadius(UI_RADIUS_CONTROL)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.rocketSimOpen = true })
            }
          }

          // 天象分类与条件筛选栏（自动适配地球 / 外星视角，实时同步列表与月历圆点）
          this.filterBar()

          if (this.viewMode === 'grid') {
            this.monthGrid()
          }
          // 列表默认与搜索「近期天象」保持一致，直接展示今天及之后的近期天象；
          // 本月已过天象折叠收纳在顶部一行，需要回看时点开即可，避免一进列表先看到十几天前的旧事件。
          if (this.pastEventsInList().length > 0) {
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Text(this.t(`本月已过天象（${this.pastEventsInList().length}）`,
                  `Earlier this month (${this.pastEventsInList().length})`))
                  .fontSize(this.panelFontSize - 3)
                  .fontColor(this.c.sub)
                  .layoutWeight(1)
                Text(this.showPastEvents ? this.t('收起', 'Hide') : this.t('展开', 'Show'))
                  .fontSize(this.panelFontSize - 3)
                  .fontColor(this.c.accent)
              }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.c.soft)
                .border({ width: 0.6, color: this.c.border })
                .borderRadius(UI_RADIUS_CONTROL)
                .alignItems(VerticalAlign.Center)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => {
                  this.animateAction(0, () => { this.showPastEvents = !this.showPastEvents })
                })
              if (this.showPastEvents) {
                ForEach(this.pastEventsInList(), (event: AstronomyCalendarEvent) => {
                  Button({ type: ButtonType.Normal }) {
                    this.eventCard(event, false)
                  }.width('100%').padding(0).borderRadius(UI_RADIUS_CARD).backgroundColor(Color.Transparent)
                    .opacity(0.76)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
                    .accessibilityText(`${this.date(event)} ${event.title}`)
                    .onClick(() => { this.host.selectEvent(event.id) })
                }, (event: AstronomyCalendarEvent) => `past:${event.id}:${event.title}:${this.calendarStore.filterRevision}`)
              }
            }.width('100%')
          }
          ForEach(this.mainEventsInList(), (event: AstronomyCalendarEvent) => {
            Button({ type: ButtonType.Normal }) {
              this.eventCard(event, false)
            }.width('100%').padding(0).borderRadius(UI_RADIUS_CARD).backgroundColor(Color.Transparent)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
              .accessibilityText(`${this.date(event)} ${event.title}`)
              .onClick(() => { this.host.selectEvent(event.id) })
          }, (event: AstronomyCalendarEvent) => `${event.id}:${event.title}:${this.calendarStore.filterRevision}`)
          if (this.calendarStore.loading || this.calendarStore.loadingMore) {
            LoadingProgress().width(28).height(28).color(this.c.sub)
              .accessibilityText(this.t('正在载入天象', 'Loading events'))
              .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
          } else if (this.calendarStore.loaded) {
            if (this.calendarStore.visibleEvents().length === 0) {
              Column({ space: 8 }) {
                Text(this.filterActive() && this.calendarStore.events.length > 0
                  ? this.t('当前筛选条件下暂无符合的天象。', 'No events match the current filter.')
                  : (this.calendarStore.selectedDay > 0
                    ? this.t('当日暂无已收录的天象。', 'No listed events on this day.')
                    : this.t('本月暂无已收录的天象。', 'No listed events this month.')))
                  .fontSize(this.panelFontSize - 1).fontColor(this.c.sub).width('100%')
                if (this.filterActive() && this.calendarStore.events.length > 0) {
                  Button(this.t('重置筛选', 'Reset filter'), { type: ButtonType.Normal })
                    .height(34).padding({ left: 14, right: 14 }).fontSize(this.panelFontSize - 2)
                    .fontColor(this.c.onAccent).backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL)
                    .alignSelf(ItemAlign.Start)
                    .clickEffect({ level: ClickEffectLevel.LIGHT })
                    .onClick(() => { this.animateAction(0, () => { this.host.clearFilters?.() }) })
                }
              }.width('100%').padding({ top: 4, bottom: 4 })
            }
            if (this.calendarStore.selectedDay === 0) {
              Row({ space: 8 }) {
                Text(this.t(
                  `已载入至 ${this.calendarStore.throughYear} 年 ${this.calendarStore.throughMonth} 月 · 下滑自动加载`,
                  `Loaded through ${this.calendarStore.throughYear}-${String(this.calendarStore.throughMonth).padStart(2, '0')} · Scroll for more`
                ))
                  .fontSize(this.panelFontSize - 2)
                  .fontColor(this.c.sub)
                  .layoutWeight(1)
                Button(this.t('加载更多', 'Load more'), { type: ButtonType.Normal })
                  .height(34).padding({ left: 12, right: 12 }).fontSize(this.panelFontSize - 2).fontColor(this.c.text)
                  .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .enabled(!(this.calendarStore.throughYear === 3000 && this.calendarStore.throughMonth === 12))
                  .onClick(() => { this.host.loadMore() })
              }.width('100%').alignItems(VerticalAlign.Center).padding({ top: 4, bottom: 4 })
            }
          }
        }.width('100%').transition(uiEnterSlideTransition(-1))
      } else {
        Column({ space: 14 }) {
          // 统一使用顶栏唯一的「< 天象详情」返回键退回列表，不再在内容区堆叠第二个返回按钮。
          ForEach(this.calendarStore.selectedEvents(), (event: AstronomyCalendarEvent) => {
            this.eventCard(event, true)
            Row({ space: 8 }) {
              Row({ space: 2 }) {
                Text(this.eventDisplayTime(event)).fontSize(this.panelFontSize - 1).fontColor(this.c.sub)
                InfoTipButton({
                  title: this.t('观测说明', 'Observation Note'),
                  tip: this.t('时间按当前地球观测位置与设备时区显示。点击「查看」，星图将前往事件时刻；是否可见取决于观测地点和天气。图案为示意。',
                    'Times follow your current Earth observer location and device timezone. View sky goes to the event instant; visibility depends on location and weather.')
                })
              }.layoutWeight(1).alignItems(VerticalAlign.Center)
              Button(this.isEventReminded(event.id) ? this.t('✓ 已预约', '✓ Booked') : this.t('预约提醒', 'Remind'),
                { type: ButtonType.Capsule })
                .height(42).padding({ left: 14, right: 14 }).fontSize(this.panelFontSize - 1)
                .backgroundColor(this.isEventReminded(event.id) ? this.c.accent : this.c.softStrong)
                .fontColor(this.isEventReminded(event.id) ? this.c.onAccent : this.c.text)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .enabled(this.calendarStore.reminderPendingId === '' && (event.at > Date.now() || this.isEventReminded(event.id)))
                .onClick(() => { void this.host.remind(event.id) })
              Button(this.t('查看', 'View sky'), { type: ButtonType.Capsule })
                .height(42).padding({ left: 18, right: 18 }).fontSize(this.panelFontSize - 1)
                .backgroundColor(this.c.accent).fontColor(this.c.onAccent)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => this.host.viewSky(event.id))
            }.width('100%')
            if (event.at > Date.now()) {
              Row({ space: 6 }) {
                Text(this.t('智能提醒时机：', 'Smart alert: ') + this.timingPreviewForEvent(event))
                  .fontSize(this.panelFontSize - 2)
                  .fontColor(this.c.sub)
                  .layoutWeight(1)
              }
                .width('100%')
                .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                .backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL)
            }
            if (this.activeLiveViewEventId === event.id || isEventEligibleForLiveView(event)) {
              Column({ space: 4 }) {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(this.activeLiveViewEventId === event.id
                      ? this.t('实况窗倒计时运行中', 'Live View Countdown Active')
                      : this.t('实况窗倒计时（锁屏 / 胶囊）', 'Live View Countdown'))
                      .fontSize(this.panelFontSize - 1)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.c.text)
                    Text(event.kind === 'satellite-pass'
                      ? this.t('在状态栏与锁屏持续显示升起方位、仰角与精准倒计时',
                        'Shows rise/set direction, peak elevation & countdown on lock screen')
                      : this.t('在状态栏与锁屏同步倒计时，点击直达星图',
                        'Live countdown on status bar & lock screen; tap to return'))
                      .fontSize(this.panelFontSize - 3)
                      .fontColor(this.c.sub)
                      .maxLines(2)
                  }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  Button(this.activeLiveViewEventId === event.id
                    ? this.t('停止实况窗', 'Stop')
                    : this.t('开启实况窗', 'Live View'), { type: ButtonType.Capsule })
                    .height(34)
                    .padding({ left: 12, right: 12 })
                    .fontSize(this.panelFontSize - 2)
                    .fontColor(this.activeLiveViewEventId === event.id ? this.c.text : this.c.onAccent)
                    .backgroundColor(this.activeLiveViewEventId === event.id ? this.c.softStrong : this.c.accent)
                    .clickEffect({ level: ClickEffectLevel.LIGHT })
                    .onClick(() => {
                      if (this.activeLiveViewEventId === event.id) {
                        this.host.stopLiveView?.()
                      } else {
                        this.host.startLiveView?.(event)
                      }
                    })
                }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                if (this.liveViewStatusText.length > 0) {
                  Text(this.liveViewStatusText)
                    .fontSize(this.panelFontSize - 3)
                    .fontColor(this.c.sub)
                    .width('100%')
                }
              }
                .width('100%')
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .backgroundColor(this.c.soft)
                .border({ width: 0.8, color: this.activeLiveViewEventId === event.id ? this.c.accent : this.c.border })
                .borderRadius(UI_RADIUS_CARD)
            }
            Text(event.body).fontSize(this.panelFontSize + 1).lineHeight(this.panelFontSize * 1.8)
              .fontColor(this.c.text).width('100%')
            if ((event.kind === 'solar-eclipse' || event.kind === 'lunar-eclipse') && event.eclipseMap !== undefined) {
              CalendarEclipseMapCard({
                event: event,
                mapData: event.eclipseMap,
                language: this.language,
                observerLat: this.observerLatitude,
                observerLon: this.observerLongitude,
                earthMapUri: this.earthMapUri,
                onlineMapAllowed: this.onlineMapAllowed
              })
              Text(calendarEclipseScienceNote(this.language, event.kind === 'solar-eclipse' ? 'solar-eclipse' : 'lunar-eclipse', event.subtype))
                .fontSize(this.panelFontSize - 1)
                .lineHeight(this.panelFontSize * 1.65)
                .fontColor(this.c.sub)
                .width('100%')
            }
            if (event.kind === 'solar-eclipse') {
              Column({ space: 6 }) {
                Text(this.t('安全观看提示', 'Safe Viewing Notice'))
                  .fontSize(this.panelFontSize)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.c.isNight ? this.c.text : '#FFD180')
                Text(calendarSolarEclipseSafetyNote(this.language))
                  .fontSize(this.panelFontSize - 1)
                  .lineHeight(this.panelFontSize * 1.65)
                  .fontColor(this.c.text)
                  .width('100%')
              }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(12)
                .backgroundColor(this.c.soft)
                .border({ width: 0.8, color: this.c.isNight ? this.c.border : 'rgba(255,209,128,0.28)' })
                .borderRadius(UI_RADIUS_CARD)
            }
            if (event.kind === 'planetary-event' && event.subtype === 'greatest-elongation') {
              CalendarElongationOrbitCard({
                planetName: event.primary ?? event.target,
                elongationDirection: event.direction ?? 'east',
                separationDegrees: event.separationDegrees ?? 22,
                orbitRatio: event.orbitRatio ?? (event.target === 'Venus' ? 0.723 : 0.387),
                language: this.language
              })
            }
            if (event.kind === 'rocket-launch' && this.host.rocketSimHost !== undefined) {
              CalendarRocketDetailCard({
                event: event,
                language: this.language,
                earthMapUri: this.earthMapUri,
                onlineMapAllowed: this.onlineMapAllowed,
                host: this.host.rocketSimHost
              })
            }
          }, (event: AstronomyCalendarEvent) => `${event.id}:${event.title}:${this.isEventReminded(event.id) ? 1 : 0}:${this.calendarStore.regionId}`)
        }.width('100%').alignItems(HorizontalAlign.Start).transition(uiEnterSlideTransition(1))
      }
      if (this.calendarStore.error !== '') {
        Text(this.calendarStore.error).fontSize(this.panelFontSize).fontColor(this.c.sub)
        Button(this.t('重试', 'Retry')).height(44).backgroundColor(this.c.softStrong).fontColor(this.c.text)
          .borderRadius(UI_RADIUS_CONTROL).clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => this.calendarStore.loaded ? this.host.loadMore() : this.host.reload())
      }
      if (this.calendarStore.actionMessage !== '') {
        Text(this.calendarStore.actionMessage).fontSize(this.panelFontSize - 1).fontColor(this.c.sub)
          .width('100%')
      }
    }.width('100%').padding({ top: 4, bottom: 16 })
      .bindContentCover($$this.rocketSimOpen, this.rocketSimModalBuilder(), {
        modalTransition: ModalTransition.DEFAULT
      })
  }
}
