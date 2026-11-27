import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyCalendarStore } from '../../state/AstronomyCalendarStore'
import { AstronomyCalendarEvent } from '../../state/AstronomyCalendarEvent'
import { getIcon } from '../../common/ui/ShellIcons'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { UI_RADIUS_CARD } from '../../common/ui/UiTokens'

// 搜索面板内嵌的「日历 ›」近期天象横滑卡片条：
// 支持轻柔自动轮播（触摸/手动拖动时立即让位并暂停），点击标题进入完整天文日历，点击单张卡片直达对应天象详情。
@Component
export struct SearchCalendarStrip {
  @ObjectLink calendarStore: AstronomyCalendarStore
  @Prop language: string = 'zh'
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onOpenCalendar: () => void = () => {}
  onSelectEvent: (id: string) => void = () => {}
  private stripScroller: Scroller = new Scroller()
  private autoScrollTimer: number = -1
  private autoScrollPausedUntil: number = 0
  private static readonly CARD_STEP_VP: number = 122
  private static readonly AUTO_SCROLL_INTERVAL_MS: number = 3600
  private static readonly USER_PAUSE_MS: number = 6000

  aboutToAppear(): void {
    this.startAutoScroll()
  }

  aboutToDisappear(): void {
    this.stopAutoScroll()
  }

  private pauseAutoScroll(durationMs: number = SearchCalendarStrip.USER_PAUSE_MS): void {
    this.autoScrollPausedUntil = Date.now() + durationMs
  }

  private startAutoScroll(): void {
    if (this.autoScrollTimer >= 0) return
    this.autoScrollTimer = setInterval(() => {
      if (Date.now() < this.autoScrollPausedUntil) return
      if (this.previewEvents().length <= 2) return
      try {
        if (this.stripScroller.isAtEnd()) {
          this.stripScroller.scrollTo({
            xOffset: 0,
            yOffset: 0,
            animation: { duration: 600, curve: Curve.EaseInOut }
          })
        } else {
          const curX = this.stripScroller.currentOffset().xOffset
          this.stripScroller.scrollTo({
            xOffset: Math.max(0, curX) + SearchCalendarStrip.CARD_STEP_VP,
            yOffset: 0,
            animation: { duration: 520, curve: Curve.EaseInOut }
          })
        }
      } catch (_err) {
        // Scroller may not yet be attached to a mounted Scroll view.
      }
    }, SearchCalendarStrip.AUTO_SCROLL_INTERVAL_MS) as number
  }

  private stopAutoScroll(): void {
    if (this.autoScrollTimer >= 0) {
      clearInterval(this.autoScrollTimer)
      this.autoScrollTimer = -1
    }
  }

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private isZh(): boolean {
    return this.language.toLowerCase().startsWith('zh')
  }

  private previewEvents(): AstronomyCalendarEvent[] {
    const all = this.calendarStore.events
    if (all.length === 0) return []
    const cutoff = Date.now() - 3600000
    const upcoming = all.filter((ev: AstronomyCalendarEvent) => ev.at >= cutoff)
    const pool = upcoming.length > 0 ? upcoming : all
    // 优先展示自然天象（月相、行星冲合大距、流星雨、节气、伴星食）与至多 1 条空间站/望远镜过境，
    // 避免高频普通卫星过境挤占搜索页的近期天象精选位。
    const celestial = pool.filter((ev: AstronomyCalendarEvent) => ev.kind !== 'satellite-pass')
    const featuredSat = pool.find((ev: AstronomyCalendarEvent) =>
      ev.kind === 'satellite-pass' && (ev.satArchetype === 'iss' || ev.satArchetype === 'tiangong' || ev.satArchetype === 'telescope'))
    const picked = featuredSat !== undefined ? celestial.concat([featuredSat]) : celestial
    const source = picked.length > 0 ? picked : pool
    return source
      .slice()
      .sort((a: AstronomyCalendarEvent, b: AstronomyCalendarEvent) => a.at - b.at)
      .slice(0, 8)
  }

  private monthBadge(at: number): string {
    const d = new Date(at)
    const m = d.getMonth() + 1
    if (this.isZh()) return `${m}月`
    const shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    return shortMonths[Math.max(0, Math.min(11, m - 1))]
  }

  private dayBadge(at: number): string {
    return String(new Date(at).getDate())
  }

  private eventArt(event: AstronomyCalendarEvent): Resource {
    if (event.kind === 'solar-eclipse') return $r('app.media.calendar_solar_eclipse_detail')
    if (event.kind === 'lunar-eclipse') return $r('app.media.calendar_lunar_eclipse_detail')
    if (event.kind === 'moon-phase') {
      if (event.phaseIndex === 0) return $r('app.media.calendar_moon_0_detail')
      if (event.phaseIndex === 1) return $r('app.media.calendar_moon_1_detail')
      if (event.phaseIndex === 3) return $r('app.media.calendar_moon_3_detail')
      return $r('app.media.calendar_moon_2_detail')
    }
    if (event.kind === 'meteor-peak') return $r('app.media.calendar_meteor_detail')
    if (event.kind === 'solar-term' || event.kind === 'planetary-season' || event.kind === 'companion-eclipse') {
      return $r('app.media.calendar_solar_detail')
    }
    if (event.target === 'Mercury') return $r('app.media.calendar_mercury_detail')
    if (event.target === 'Venus') return $r('app.media.calendar_venus_detail')
    if (event.target === 'Mars') return $r('app.media.calendar_mars_detail')
    if (event.target === 'Saturn') return $r('app.media.calendar_saturn_detail')
    if (event.target === 'Uranus') return $r('app.media.calendar_uranus_detail')
    if (event.target === 'Neptune') return $r('app.media.calendar_neptune_detail')
    return $r('app.media.calendar_planet_detail')
  }

  private satelliteIcon(archetype: string | undefined): Resource {
    if (archetype === 'iss') return $r('app.media.sat_icon_iss')
    if (archetype === 'tiangong') return $r('app.media.sat_icon_tiangong')
    if (archetype === 'telescope') return $r('app.media.sat_icon_telescope')
    if (archetype === 'comms') return $r('app.media.sat_icon_comms')
    if (archetype === 'earth_obs') return $r('app.media.sat_icon_earth_obs')
    return $r('app.media.sat_icon_constellation')
  }

  @Builder
  eventPreviewCard(event: AstronomyCalendarEvent) {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (event.kind === 'satellite-pass') {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 140,
              colors: this.c.isNight
                ? [['#250806', 0.0], ['#140404', 1.0]]
                : [['#123146', 0.0], ['#0B1B2E', 0.65], ['#081320', 1.0]]
            })
          Image(this.satelliteIcon(event.satArchetype))
            .width(46)
            .height(46)
            .objectFit(ImageFit.Contain)
            .margin({ bottom: 16 })
            .accessibilityLevel('no')
        }
          .width('100%')
          .height('100%')
      } else if (event.isRemote === true) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: this.c.isNight
              ? [['#250806', 0.0], ['#140404', 1.0]]
              : (event.kind === 'aurora-alert'
                ? [['#0F3B34', 0.0], ['#211D47', 0.6], ['#101326', 1.0]]
                : [['#1B254A', 0.0], ['#291C42', 0.6], ['#101324', 1.0]])
          })
      } else {
        // calendar_*_detail.svg 为 396×240（1.65:1），天体圆盘中心在 x≈64% 处；
        // 按高 124vp 展开（宽 205vp）并微移对齐，让日/月/行星圆盘恰好居中落在 114×124 卡片中央。
        Image(this.eventArt(event))
          .width(205)
          .height(124)
          .objectFit(ImageFit.Fill)
          .position({ x: -74, y: 0 })
          .accessibilityLevel('no')
        if (this.c.isNight) {
          Row()
            .width('100%')
            .height('100%')
            .backgroundColor(this.c.nightMask)
            .hitTestBehavior(HitTestMode.None)
            .accessibilityLevel('no')
        }
      }

      // 底部渐变暗角，保障白色标题在任意插画上清晰可读
      Column()
        .width('100%')
        .height('62%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            ['rgba(8,12,22,0.0)', 0.0],
            ['rgba(8,12,22,0.48)', 0.55],
            ['rgba(8,12,22,0.90)', 1.0]
          ]
        })
        .hitTestBehavior(HitTestMode.None)

      // 右上角日期角标
      Column({ space: 0 }) {
        Text(this.monthBadge(event.at))
          .fontSize(9)
          .fontColor(this.c.isNight ? this.c.sub : '#C6D1E4')
          .maxLines(1)
        Text(this.dayBadge(event.at))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.c.isNight ? this.c.text : '#F5F7FC')
          .maxLines(1)
      }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        .backgroundColor(this.c.isNight ? this.c.softStrong : 'rgba(18,24,38,0.72)')
        .borderRadius(9)
        .position({ right: 7, top: 7 })
        .hitTestBehavior(HitTestMode.None)

      // 左下角天象标题
      Text(event.title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.isNight ? this.c.text : '#F3F6FC')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 9, right: 9, bottom: 9 })
    }
      .width(114)
      .height(124)
      .borderRadius(UI_RADIUS_CARD)
      .border({ width: 0.7, color: this.c.border })
      .clip(true)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
      .accessibilityText(`${this.monthBadge(event.at)}${this.dayBadge(event.at)} ${event.title}`)
      .onClick(() => { this.onSelectEvent(event.id) })
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 4 }) {
        Text(this.isZh() ? '近期天象' : 'Upcoming')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.c.text)
        Image(getIcon('chevron_right', false))
          .width(14)
          .height(14)
          .supportSvg2(true)
          .colorFilter(tintMatrixFor(this.c.sub))
        Blank()
        Text(this.isZh() ? '全部日历' : 'All')
          .fontSize(11)
          .fontColor(this.c.sub)
      }
        .width('100%')
        .padding({ left: 2, right: 2, top: 2, bottom: 2 })
        .alignItems(VerticalAlign.Center)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => { this.onOpenCalendar() })

      if (this.previewEvents().length > 0) {
        Scroll(this.stripScroller) {
          Row({ space: 8 }) {
            ForEach(this.previewEvents(), (event: AstronomyCalendarEvent) => {
              this.eventPreviewCard(event)
            }, (event: AstronomyCalendarEvent) => `search-cal:${event.id}:${event.title}:${this.language}`)
          }
            .padding({ left: 1, right: 4 })
        }
          .width('100%')
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onTouch(() => { this.pauseAutoScroll() })
          .onScrollStart(() => { this.pauseAutoScroll() })
      } else {
        Row({ space: 10 }) {
          if (this.calendarStore.loading) {
            LoadingProgress().width(18).height(18).color(this.c.sub)
            Text(this.isZh() ? '正在载入近期天象…' : 'Loading upcoming events…')
              .fontSize(12)
              .fontColor(this.c.sub)
          } else {
            Text(this.isZh() ? '点击查看本月与未来天象日历' : 'Tap to browse upcoming astronomical events')
              .fontSize(12)
              .fontColor(this.c.sub)
              .layoutWeight(1)
            Image(getIcon('chevron_right', false))
              .width(14)
              .height(14)
              .supportSvg2(true)
              .colorFilter(tintMatrixFor(this.c.sub))
          }
        }
          .width('100%')
          .height(52)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.c.bg)
          .borderRadius(UI_RADIUS_CARD)
          .border({ width: 0.7, color: this.c.border })
          .alignItems(VerticalAlign.Center)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onOpenCalendar() })
      }
    }
      .width('100%')
      .margin({ bottom: 14 })
  }
}
