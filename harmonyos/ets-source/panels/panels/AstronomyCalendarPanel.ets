import { Theme, curves } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyCalendarStore } from '../../state/AstronomyCalendarStore'
import { AstronomyCalendarEvent, CalendarDay, calendarEventTime, calendarDayEvents } from '../../state/AstronomyCalendarEvent'
import { calendarText, calendarMonthTitle } from '../../state/AstronomyCalendarText'
import { AstronomyCalendarReminderResult } from '../../capability/AstronomyCalendarController'

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
}

@Component
export struct AstronomyCalendarPanel {
  @ObjectLink calendarStore: AstronomyCalendarStore
  host: AstronomyCalendarPanelHost = {
    previousMonth: () => {}, nextMonth: () => {}, selectDay: () => {}, selectEvent: () => {},
    showMonthEvents: () => {}, viewSky: () => {}, remind: async () => ({ ok: false, reason: 'host-unavailable' }),
    reload: () => {}, loadMore: () => {}
  }
  @Prop language: string = 'zh'
  @Prop panelFontSize: number = 14
  @Prop textColor: ResourceColor = '#F3F5FA'
  @Prop secondaryColor: ResourceColor = '#B7C3D9'
  @Prop accentColor: ResourceColor = '#344E79'
  @Prop cardColor: ResourceColor = '#182235'
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private viewMode: 'list' | 'grid' = 'list'
  @State private transitionDir: number = 1

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private t(chinese: string, english: string): string {
    return calendarText(this.language, chinese, english)
  }

  private slideTransition(direction: number): TransitionEffect {
    const enterX = direction >= 0 ? 22 : -22
    const exitX = direction >= 0 ? -16 : 16
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ x: enterX, y: 0 }).animation({ duration: 260, curve: curves.springMotion(0.55, 0.88) })),
      TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
        .combine(TransitionEffect.translate({ x: exitX, y: 0 }).animation({ duration: 180, curve: Curve.EaseIn }))
    )
  }

  private fadeUpTransition(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ x: 0, y: 10 }).animation({ duration: 240, curve: curves.springMotion(0.55, 0.88) })),
      TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseIn })
    )
  }

  private animateAction(direction: number, action: () => void): void {
    this.transitionDir = direction
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, action)
  }

  private weekdayLabels(): string[] {
    return this.language.toLowerCase().startsWith('zh')
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
    if (event.kind === 'planetary-event') return 1
    if (event.kind === 'moon-phase' || event.kind === 'companion-phase') return event.isSupermoon === true ? 0 : 2
    return 3
  }

  private dayEventsSorted(day: number): AstronomyCalendarEvent[] {
    if (day <= 0) return []
    const monthEvents = this.calendarStore.events.filter((event: AstronomyCalendarEvent) => {
      const d = new Date(event.at)
      return d.getFullYear() === this.calendarStore.year && (d.getMonth() + 1) === this.calendarStore.month
    })
    return calendarDayEvents(monthEvents, day)
      .sort((a: AstronomyCalendarEvent, b: AstronomyCalendarEvent) => this.eventPriority(a) - this.eventPriority(b) || a.at - b.at)
  }

  private eventDotColor(event: AstronomyCalendarEvent): ResourceColor {
    if (this.c.isNight) return this.c.accent
    if (event.kind === 'companion-eclipse') return '#FF8A65'
    if (event.kind === 'meteor-peak') return '#64B5F6'
    if (event.kind === 'planetary-event') return '#FFB74D'
    if (event.kind === 'moon-phase' || event.kind === 'companion-phase') return event.isSupermoon === true ? '#FFE082' : '#E0E6F2'
    return '#81C784'
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
                .borderRadius(10)
                .backgroundColor(this.calendarStore.selectedDay === cell.day ? this.c.accent :
                  (cell.count > 0 ? this.c.softStrong : Color.Transparent))
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
        }, (cell: CalendarDay) => `${cell.key}:${cell.count}:${this.calendarStore.selectedDay === cell.day ? 1 : 0}`)
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
            .height(28).padding({ left: 10, right: 10 }).fontSize(this.panelFontSize - 3)
            .fontColor(this.c.text).backgroundColor(this.c.softStrong).borderRadius(10)
            .onClick(() => { this.animateAction(-1, () => { this.host.showMonthEvents() }) })
        }.width('100%').padding({ top: 4 })
      }
    }
      .width('100%').padding(10).backgroundColor(this.c.soft).borderRadius(14)
      .transition(this.fadeUpTransition())
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
    return this.t(`${date.getMonth() + 1}月${date.getDate()}日`, `${date.getMonth() + 1}/${date.getDate()}`)
  }

  @Builder
  eventCard(event: AstronomyCalendarEvent, detail: boolean) {
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
    }.width('100%').borderRadius(18).clip(true)
  }

  build() {
    Column({ space: 14 }) {
      if (this.calendarStore.selectedEventId === '') {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            Button('‹', { type: ButtonType.Circle }).width(40).height(40).fontSize(25)
              .backgroundColor(this.c.softStrong).fontColor(this.c.text)
              .accessibilityText(this.t('上个月', 'Previous month'))
              .enabled(!(this.calendarStore.year === 1 && this.calendarStore.month === 1))
              .onClick(() => { this.animateAction(-1, () => { this.host.previousMonth() }) })
            Text(calendarMonthTitle(this.language, this.calendarStore.year, this.calendarStore.month))
              .layoutWeight(1).fontSize(this.panelFontSize + 2).fontColor(this.c.text).textAlign(TextAlign.Center)
            Button('›', { type: ButtonType.Circle }).width(40).height(40).fontSize(25)
              .backgroundColor(this.c.softStrong).fontColor(this.c.text)
              .accessibilityText(this.t('下个月', 'Next month'))
              .enabled(!(this.calendarStore.year === 3000 && this.calendarStore.month === 12))
              .onClick(() => { this.animateAction(1, () => { this.host.nextMonth() }) })
          }.width('100%')
          Row({ space: 6 }) {
            Button(this.t('列表', 'List'), { type: ButtonType.Normal })
              .height(32).layoutWeight(1).fontSize(this.panelFontSize - 2).borderRadius(10)
              .backgroundColor(this.viewMode === 'list' ? this.c.accent : this.c.softStrong)
              .fontColor(this.viewMode === 'list' ? this.c.onAccent : this.c.text)
              .onClick(() => {
                if (this.viewMode === 'list') return
                this.animateAction(-1, () => {
                  this.viewMode = 'list'
                  if (this.calendarStore.selectedDay > 0) this.host.showMonthEvents()
                })
              })
            Button(this.t('月历', 'Month grid'), { type: ButtonType.Normal })
              .height(32).layoutWeight(1).fontSize(this.panelFontSize - 2).borderRadius(10)
              .backgroundColor(this.viewMode === 'grid' ? this.c.accent : this.c.softStrong)
              .fontColor(this.viewMode === 'grid' ? this.c.onAccent : this.c.text)
              .onClick(() => {
                if (this.viewMode === 'grid') return
                this.animateAction(1, () => { this.viewMode = 'grid' })
              })
          }.width('100%')
          if (this.viewMode === 'grid') {
            this.monthGrid()
          }
          ForEach(this.calendarStore.visibleEvents(), (event: AstronomyCalendarEvent) => {
            Button({ type: ButtonType.Normal }) {
              this.eventCard(event, false)
            }.width('100%').padding(0).borderRadius(18).backgroundColor(Color.Transparent)
              .accessibilityText(`${this.date(event)} ${event.title}`)
              .onClick(() => { this.animateAction(1, () => { this.host.selectEvent(event.id) }) })
          }, (event: AstronomyCalendarEvent) => `${event.id}:${event.title}`)
          if (this.calendarStore.loading || this.calendarStore.loadingMore) {
            LoadingProgress().width(28).height(28).color(this.c.sub)
              .accessibilityText(this.t('正在载入天象', 'Loading events'))
              .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
          } else if (this.calendarStore.loaded) {
            if (this.calendarStore.visibleEvents().length === 0) {
              Text(this.calendarStore.selectedDay > 0
                ? this.t('当日暂无已收录的天象。', 'No listed events on this day.')
                : this.t('本月暂无已收录的天象。', 'No listed events this month.'))
                .fontSize(this.panelFontSize).fontColor(this.c.sub)
            }
            if (this.calendarStore.selectedDay === 0) {
              Button(this.t('更多天象', 'More events'), { type: ButtonType.Normal })
                .height(44).width('100%').fontSize(this.panelFontSize).fontColor(this.c.text)
                .backgroundColor(this.c.softStrong).borderRadius(14)
                .enabled(!(this.calendarStore.throughYear === 3000 && this.calendarStore.throughMonth === 12))
                .onClick(() => { this.animateAction(1, () => { this.host.loadMore() }) })
            }
          }
        }.width('100%').transition(this.slideTransition(-1))
      } else {
        Column({ space: 14 }) {
          Button(this.t('‹  所有天象', '‹  All events'), { type: ButtonType.Normal })
            .height(40).fontSize(this.panelFontSize).fontColor(this.c.text).backgroundColor(this.c.softStrong)
            .borderRadius(14).alignSelf(ItemAlign.Start)
            .onClick(() => { this.animateAction(-1, () => { this.host.showMonthEvents() }) })
          ForEach(this.calendarStore.selectedEvents(), (event: AstronomyCalendarEvent) => {
            this.eventCard(event, true)
            Row({ space: 10 }) {
              Text(calendarEventTime(event)).fontSize(this.panelFontSize - 1).fontColor(this.c.sub).layoutWeight(1)
              Button(this.t('添加提醒', 'Remind'), { type: ButtonType.Capsule })
                .height(44).padding({ left: 16, right: 16 }).fontSize(this.panelFontSize)
                .backgroundColor(this.c.softStrong).fontColor(this.c.text)
                .enabled(this.calendarStore.reminderPendingId === '' && event.at > Date.now())
                .onClick(() => { void this.host.remind(event.id) })
              Button(this.t('查看', 'View sky'), { type: ButtonType.Capsule })
                .height(44).padding({ left: 20, right: 20 }).fontSize(this.panelFontSize)
                .backgroundColor(this.c.accent).fontColor(this.c.onAccent).onClick(() => this.host.viewSky(event.id))
            }.width('100%')
            Text(event.body).fontSize(this.panelFontSize + 1).lineHeight(this.panelFontSize * 1.8)
              .fontColor(this.c.text).width('100%')
            Text(this.t('时间为设备当地时间。点击查看，星图将前往事件时刻；是否可见取决于观测地点和天气。图案为示意。',
              'Times use your device time zone. View sky goes to the event time; visibility depends on your location and weather. Artwork is illustrative.'))
              .fontSize(this.panelFontSize - 2).lineHeight(this.panelFontSize * 1.5).fontColor(this.c.sub).width('100%')
          }, (event: AstronomyCalendarEvent) => `${event.id}:${event.title}`)
        }.width('100%').alignItems(HorizontalAlign.Start).transition(this.slideTransition(1))
      }
      if (this.calendarStore.error !== '') {
        Text(this.calendarStore.error).fontSize(this.panelFontSize).fontColor(this.c.sub)
        Button(this.t('重试', 'Retry')).height(44).backgroundColor(this.c.softStrong).fontColor(this.c.text)
          .onClick(() => this.calendarStore.loaded ? this.host.loadMore() : this.host.reload())
      }
      if (this.calendarStore.actionMessage !== '') {
        Text(this.calendarStore.actionMessage).fontSize(this.panelFontSize - 1).fontColor(this.c.sub)
          .width('100%')
      }
    }.width('100%').padding({ top: 4, bottom: 16 })
  }
}
