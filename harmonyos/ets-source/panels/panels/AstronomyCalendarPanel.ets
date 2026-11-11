import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyCalendarStore } from '../../state/AstronomyCalendarStore'
import { AstronomyCalendarEvent, calendarEventTime } from '../../state/AstronomyCalendarEvent'
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

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private t(chinese: string, english: string): string {
    return calendarText(this.language, chinese, english)
  }

  private art(event: AstronomyCalendarEvent, detail: boolean): Resource {
    if (event.kind === 'moon-phase') {
      if (event.phaseIndex === 0) return detail ? $r('app.media.calendar_moon_0_detail') : $r('app.media.calendar_moon_0')
      if (event.phaseIndex === 1) return detail ? $r('app.media.calendar_moon_1_detail') : $r('app.media.calendar_moon_1')
      if (event.phaseIndex === 3) return detail ? $r('app.media.calendar_moon_3_detail') : $r('app.media.calendar_moon_3')
      return detail ? $r('app.media.calendar_moon_2_detail') : $r('app.media.calendar_moon_2')
    }
    if (event.kind === 'meteor-peak') return detail ? $r('app.media.calendar_meteor_detail') : $r('app.media.calendar_meteor')
    if (event.kind === 'solar-term') return detail ? $r('app.media.calendar_solar_detail') : $r('app.media.calendar_solar')
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
        Row({ space: 12 }) {
          Button('‹', { type: ButtonType.Circle }).width(40).height(40).fontSize(25)
            .backgroundColor(this.c.softStrong).fontColor(this.c.text)
            .accessibilityText(this.t('上个月', 'Previous month'))
            .enabled(!(this.calendarStore.year === 1 && this.calendarStore.month === 1))
            .onClick(() => this.host.previousMonth())
          Text(calendarMonthTitle(this.language, this.calendarStore.year, this.calendarStore.month))
            .layoutWeight(1).fontSize(this.panelFontSize + 2).fontColor(this.c.text).textAlign(TextAlign.Center)
          Button('›', { type: ButtonType.Circle }).width(40).height(40).fontSize(25)
            .backgroundColor(this.c.softStrong).fontColor(this.c.text)
            .accessibilityText(this.t('下个月', 'Next month'))
            .enabled(!(this.calendarStore.year === 3000 && this.calendarStore.month === 12))
            .onClick(() => this.host.nextMonth())
        }.width('100%')
        ForEach(this.calendarStore.visibleEvents(), (event: AstronomyCalendarEvent) => {
          Button({ type: ButtonType.Normal }) {
            this.eventCard(event, false)
          }.width('100%').padding(0).borderRadius(18).backgroundColor(Color.Transparent)
            .accessibilityText(`${this.date(event)} ${event.title}`)
            .onClick(() => this.host.selectEvent(event.id))
        }, (event: AstronomyCalendarEvent) => `${event.id}:${event.title}`)
        if (this.calendarStore.loading || this.calendarStore.loadingMore) {
          LoadingProgress().width(28).height(28).color(this.c.sub)
            .accessibilityText(this.t('正在载入天象', 'Loading events'))
        } else if (this.calendarStore.loaded) {
          if (this.calendarStore.visibleEvents().length === 0) {
            Text(this.t('本月暂无已收录的天象。', 'No listed events this month.'))
              .fontSize(this.panelFontSize).fontColor(this.c.sub)
          }
          Button(this.t('更多天象', 'More events'), { type: ButtonType.Normal })
            .height(44).width('100%').fontSize(this.panelFontSize).fontColor(this.c.text)
            .backgroundColor(this.c.softStrong).borderRadius(14)
            .enabled(!(this.calendarStore.throughYear === 3000 && this.calendarStore.throughMonth === 12))
            .onClick(() => this.host.loadMore())
        }
      } else {
        Button(this.t('‹  所有天象', '‹  All events'), { type: ButtonType.Normal })
          .height(40).fontSize(this.panelFontSize).fontColor(this.c.text).backgroundColor(this.c.softStrong)
          .borderRadius(14).alignSelf(ItemAlign.Start).onClick(() => this.host.showMonthEvents())
        ForEach(this.calendarStore.selectedEvents(), (event: AstronomyCalendarEvent) => {
          this.eventCard(event, true)
          Row({ space: 12 }) {
            Text(calendarEventTime(event)).fontSize(this.panelFontSize - 1).fontColor(this.c.sub).layoutWeight(1)
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
