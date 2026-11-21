import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyCalendarStore } from '../../state/AstronomyCalendarStore'
import { AstronomyCalendarEvent, CalendarDay, calendarEventTime, calendarDayEvents } from '../../state/AstronomyCalendarEvent'
import { calendarText, calendarMonthTitle } from '../../state/AstronomyCalendarText'
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
import { uiFadeUpTransition, uiSlideTransition } from '../../common/ui/UiMotion'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { RegionScopePicker } from '../../common/ui/RegionScopePicker'

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
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private viewMode: 'list' | 'grid' = 'list'
  @State private transitionDir: number = 1
  @State private filterDrawerOpen: boolean = false

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
    if (event.kind === 'satellite-pass') return '#4DD0E1'
    if (event.kind === 'companion-eclipse') return '#FF8A65'
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
    Column({ space: 6 }) {
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
    if (event.kind === 'moon-phase') {
      if (event.phaseIndex === 0) return detail ? $r('app.media.calendar_moon_0_detail') : $r('app.media.calendar_moon_0')
      if (event.phaseIndex === 1) return detail ? $r('app.media.calendar_moon_1_detail') : $r('app.media.calendar_moon_1')
      if (event.phaseIndex === 3) return detail ? $r('app.media.calendar_moon_3_detail') : $r('app.media.calendar_moon_3')
      return detail ? $r('app.media.calendar_moon_2_detail') : $r('app.media.calendar_moon_2')
    }
    if (event.kind === 'meteor-peak') return detail ? $r('app.media.calendar_meteor_detail') : $r('app.media.calendar_meteor')
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
    if (event.kind === 'satellite-pass') {
      const hh = String(date.getHours()).padStart(2, '0')
      const mm = String(date.getMinutes()).padStart(2, '0')
      return this.t(`${date.getMonth() + 1}月${date.getDate()}日 ${hh}:${mm}`,
        `${date.getMonth() + 1}/${date.getDate()} ${hh}:${mm}`)
    }
    return this.t(`${date.getMonth() + 1}月${date.getDate()}日`, `${date.getMonth() + 1}/${date.getDate()}`)
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

  @Builder
  eventCard(event: AstronomyCalendarEvent, detail: boolean) {
    if (event.kind === 'satellite-pass') {
      this.satellitePassCard(event, detail)
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
          Text(this.date(event)).fontSize(this.panelFontSize - 2).fontColor(this.c.isNight ? this.c.sub : '#C3CCDB')
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
          Row({ space: 10 }) {
            Button('‹', { type: ButtonType.Circle }).width(40).height(40).fontSize(25)
              .backgroundColor(this.c.softStrong).fontColor(this.c.text)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .accessibilityText(this.t('上个月', 'Previous month'))
              .enabled(!(this.calendarStore.year === 1 && this.calendarStore.month === 1))
              .onClick(() => { this.animateAction(-1, () => { this.host.previousMonth() }) })
            Text(calendarMonthTitle(this.language, this.calendarStore.year, this.calendarStore.month))
              .layoutWeight(1).fontSize(this.panelFontSize + 2).fontColor(this.c.text).textAlign(TextAlign.Center)
            Button('›', { type: ButtonType.Circle }).width(40).height(40).fontSize(25)
              .backgroundColor(this.c.softStrong).fontColor(this.c.text)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .accessibilityText(this.t('下个月', 'Next month'))
              .enabled(!(this.calendarStore.year === 3000 && this.calendarStore.month === 12))
              .onClick(() => { this.animateAction(1, () => { this.host.nextMonth() }) })
          }.width('100%')
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

          // 地理区域选择器（地球视角下支持跟随星图位置或独立选区）
          if (isEarthCalendarPlanet(this.calendarStore.observerPlanet)) {
            RegionScopePicker({
              title: this.t('日历地理区域', 'Calendar Region'),
              regionId: this.calendarStore.regionId,
              followLocationName: this.followLocationName,
              language: this.language,
              onSelectRegion: (rid: string) => { this.host.setRegionId?.(rid) }
            })
          }

          // 天象分类与条件筛选栏（自动适配地球 / 外星视角，实时同步列表与月历圆点）
          this.filterBar()

          if (this.viewMode === 'grid') {
            this.monthGrid()
          }
          ForEach(this.calendarStore.visibleEvents(), (event: AstronomyCalendarEvent) => {
            Button({ type: ButtonType.Normal }) {
              this.eventCard(event, false)
            }.width('100%').padding(0).borderRadius(UI_RADIUS_CARD).backgroundColor(Color.Transparent)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
              .accessibilityText(`${this.date(event)} ${event.title}`)
              .onClick(() => { this.animateAction(1, () => { this.host.selectEvent(event.id) }) })
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
              Button(this.t('更多天象', 'More events'), { type: ButtonType.Normal })
                .height(44).width('100%').fontSize(this.panelFontSize).fontColor(this.c.text)
                .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .enabled(!(this.calendarStore.throughYear === 3000 && this.calendarStore.throughMonth === 12))
                .onClick(() => { this.animateAction(1, () => { this.host.loadMore() }) })
            }
          }
        }.width('100%').transition(uiSlideTransition(-1))
      } else {
        Column({ space: 14 }) {
          Button(this.t('‹  所有天象', '‹  All events'), { type: ButtonType.Normal })
            .height(40).fontSize(this.panelFontSize).fontColor(this.c.text).backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_PILL).padding({ left: 14, right: 16 }).alignSelf(ItemAlign.Start)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.animateAction(-1, () => { this.host.showMonthEvents() }) })
          ForEach(this.calendarStore.selectedEvents(), (event: AstronomyCalendarEvent) => {
            this.eventCard(event, true)
            Row({ space: 8 }) {
              Row({ space: 2 }) {
                Text(this.eventDisplayTime(event)).fontSize(this.panelFontSize - 1).fontColor(this.c.sub)
                InfoTipButton({
                  title: this.t('观测说明', 'Observation Note'),
                  tip: this.t('时间按所选地理区域时区显示。点击「查看」，星图将前往事件时刻；是否可见取决于观测地点和天气。图案为示意。',
                    'Times follow the selected region timezone. View sky goes to the event instant; visibility depends on location and weather.')
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
            Text(event.body).fontSize(this.panelFontSize + 1).lineHeight(this.panelFontSize * 1.8)
              .fontColor(this.c.text).width('100%')
          }, (event: AstronomyCalendarEvent) => `${event.id}:${event.title}:${this.isEventReminded(event.id) ? 1 : 0}:${this.calendarStore.regionId}`)
        }.width('100%').alignItems(HorizontalAlign.Start).transition(uiSlideTransition(1))
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
  }
}
