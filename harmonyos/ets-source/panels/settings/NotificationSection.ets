import { I18n } from '../../capability/I18n'
import { notificationText } from '../../capability/NotificationText'
import { LengthMetrics, Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiFadeUpTransition } from '../../common/ui/UiMotion'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyReminderItem } from '../../qability/AstronomyReminderService'
import {
  NotificationTimingMode,
  NotificationTopicId,
  SUBSCRIPTION_PRESETS,
  SubscriptionPresetDefinition,
  SubscriptionPresetId,
  SubscriptionTopicFlags,
  activePresetIdForFlags,
  normalizeTimingMode
} from '../../qability/AstronomyNotificationTiming'

interface TimingChoiceItem {
  id: NotificationTimingMode
  labelZh: string
  labelEn: string
  descZh: string
  descEn: string
}

const TIMING_MODE_CHOICES: TimingChoiceItem[] = [
  {
    id: 'smart',
    labelZh: '智能最佳窗口',
    labelEn: 'Smart Window',
    descZh: '流星雨/西大距前一晚提醒，满月傍晚月升前，日食提前 1 天',
    descEn: 'Evening before peaks/pre-dawn events, before moonrise, 1d before eclipses'
  },
  {
    id: 'day_before',
    labelZh: '提前一天傍晚',
    labelEn: '1 Day Ahead',
    descZh: '所有天象均在前一日 19:00 提前预告，方便规划天气与器材',
    descEn: 'Preview all events at 19:00 the evening before'
  },
  {
    id: 'just_in_time',
    labelZh: '临场前 1 小时',
    labelEn: '1 Hour Before',
    descZh: '统一在天象精确发生前 1 小时发送临场提醒',
    descEn: 'Alert 1 hour before each event instant'
  }
]

const LEAD_QUICK_OPTIONS: number[] = [5, 10, 15, 30]

@Component
export struct NotificationSection {
  @StorageProp('i18nLang') language: string = I18n.getLanguage()

  private t(value: string): string { return notificationText(value, this.language) }
  private isZh(): boolean { return this.language.toLowerCase().startsWith('zh') }
  private tr(zh: string, en: string): string { return this.isZh() ? zh : en }

  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop notificationEnabled: boolean
  @Prop notificationBusy: boolean
  @Prop reminderCount: number
  @Prop statusText: string
  @Prop @Watch('syncToggles') astronomyEventsEnabled: boolean
  @Prop @Watch('syncToggles') satellitePassEnabled: boolean
  @Prop @Watch('syncToggles') digestEnabled: boolean
  @Prop @Watch('syncToggles') topicMeteor: boolean = false
  @Prop @Watch('syncToggles') topicPlanet: boolean = false
  @Prop @Watch('syncToggles') topicMoon: boolean = false
  @Prop @Watch('syncToggles') topicSolarTerm: boolean = false
  @Prop @Watch('syncToggles') subscriptionHighlightOnly: boolean = false
  @Prop timingMode: string = 'smart'
  @Prop regionId: string = 'follow'
  @Prop followLocationName: string = ''
  @Prop @Watch('syncToggles') dndEnabled: boolean
  @Prop @Watch('syncToggles') dndSatelliteOnly: boolean = true
  // 本地状态承接用户点击，避免 @Prop 回写导致 Toggle 弹回
  @State private meteorOn: boolean = false
  @State private planetOn: boolean = false
  @State private moonOn: boolean = false
  @State private solarTermOn: boolean = false
  @State private satelliteOn: boolean = false
  @State private highlightOnlyOn: boolean = false
  @State private dndOn: boolean = true
  @State private dndSatelliteOnlyOn: boolean = true
  @State private advancedOpen: boolean = false
  @Prop dndStartMinutes: number
  @Prop dndEndMinutes: number
  @Prop passLeadMinutes: number
  @Prop reminders: AstronomyReminderItem[] = []
  @Prop reminderListLoaded: boolean = false
  @Prop reminderListError: string = ''
  @Prop preferencesBusy: boolean = false
  @Prop preferencesError: string = ''
  @Prop astronomySubscriptionStatus: string = ''
  @Prop satelliteSubscriptionStatus: string = ''
  @Prop pushTokenText: string
  @Prop liveViewActiveTitle: string = ''
  @Prop liveViewStatusText: string = ''
  @State c: ThemeSlots = DEFAULT_SLOTS

  onRequestAccess: () => void = () => {}
  onToggleAstronomyEvents: (enabled: boolean) => void = () => {}
  onToggleSatellitePass: (enabled: boolean) => void = () => {}
  onToggleDigest: (enabled: boolean) => void = () => {}
  onToggleTopic: (topic: NotificationTopicId, enabled: boolean) => void = () => {}
  onToggleHighlightOnly: (enabled: boolean) => void = () => {}
  onApplyPreset: (presetId: SubscriptionPresetId) => void = () => {}
  onTimingModeChange: (mode: string) => void = () => {}
  onRegionChange: (regionId: string) => void = () => {}
  onSetLeadMinutes: (minutes: number) => void = () => {}
  onToggleDnd: (enabled: boolean) => void = () => {}
  onToggleDndSatelliteOnly: (enabled: boolean) => void = () => {}
  onDndStartChange: (minutes: number) => void = () => {}
  onDndEndChange: (minutes: number) => void = () => {}
  onLeadChange: (delta: number) => void = () => {}
  onScheduleNextSolarTerm: () => void = () => {}
  onScheduleNextMoonPhase: () => void = () => {}
  onScheduleNextMeteor: () => void = () => {}
  onOpenCalendar: () => void = () => {}
  onOpenWidgetStudio: () => void = () => {}
  onRefreshReminders: () => void = () => {}
  onPreviewReminder: (item: AstronomyReminderItem) => void = () => {}
  onCancelReminder: (id: number) => void = () => {}
  onClearReminders: () => void = () => {}
  onScheduleCountdown: (minutes: number) => void = () => {}
  onScheduleCalendarAt: (timestamp: number) => void = () => {}
  onScheduleAlarm: (hour: number, minute: number) => void = () => {}
  onFetchPushToken: () => void = () => {}
  onStartSatLiveView: () => void = () => {}
  onStartDarkAdaptLiveView: () => void = () => {}
  onStopLiveView: () => void = () => {}
  onPreviewSatPassCard: () => void = () => {}

  aboutToAppear(): void { this.syncToggles() }

  private syncToggles(): void {
    this.meteorOn = this.topicMeteor
    this.planetOn = this.topicPlanet
    this.moonOn = this.topicMoon
    this.solarTermOn = this.topicSolarTerm
    this.satelliteOn = this.satellitePassEnabled
    this.highlightOnlyOn = this.subscriptionHighlightOnly
    this.dndOn = this.dndEnabled
    this.dndSatelliteOnlyOn = this.dndSatelliteOnly
  }

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private busy(): boolean { return this.notificationBusy || this.preferencesBusy }

  private currentFlags(): SubscriptionTopicFlags {
    return {
      meteor: this.meteorOn,
      planet: this.planetOn,
      moon: this.moonOn,
      solarTerm: this.solarTermOn,
      satellite: this.satelliteOn,
      highlightOnly: this.highlightOnlyOn
    }
  }

  private matchedPresetId(): string {
    return activePresetIdForFlags(this.currentFlags(), normalizeTimingMode(this.timingMode))
  }

  private hhmm(minutes: number): string {
    return String(Math.floor(minutes / 60)).padStart(2, '0') + ':' + String(minutes % 60).padStart(2, '0')
  }

  private reminderTimeText(item: AstronomyReminderItem): string {
    const dt = item.dateTime
    if (dt === null || dt === undefined) return this.t('倒计时或周期提醒 · 由系统管理')
    const pad = (v: number): string => String(v).padStart(2, '0')
    return `${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}`
  }

  private sourceBadgeText(item: AstronomyReminderItem): string {
    if (item.subscription === 'widget') return this.tr('小组件', 'Widget')
    if (item.subscription === 'astronomy' || item.subscription === 'satellite') return this.tr('自动订阅', 'Auto')
    return this.tr('日历预约', 'Booked')
  }

  private chooseQuietTime(start: boolean): void {
    const minutes = start ? this.dndStartMinutes : this.dndEndMinutes
    this.getUIContext().showTimePickerDialog({
      selected: new Date(2026, 0, 1, Math.floor(minutes / 60), minutes % 60),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        if (value.hour === undefined || value.minute === undefined) return
        if (start) this.onDndStartChange(value.hour * 60 + value.minute)
        else this.onDndEndChange(value.hour * 60 + value.minute)
      }
    })
  }

  @Builder
  hint(text: string) {
    Text(text).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub)
      .width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 2 })
  }

  @Builder
  action(label: string, enabled: boolean, callback: () => void) {
    Button(label, { type: ButtonType.Normal }).fontSize(panelFontSize(12, this.readableUi))
      .fontColor(this.c.text).backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL)
      .constraintSize({ minHeight: 34 }).padding({ left: 11, right: 11 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .enabled(enabled).onClick(() => { callback() })
  }

  @Builder
  topicSwitchRow(
    title: string,
    timingHint: string,
    isOn: boolean,
    onFlip: (v: boolean) => void
  ) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(panelFontSize(13, this.readableUi))
          .fontWeight(isOn ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.c.text)
        Text(timingHint)
          .fontSize(panelFontSize(10, this.readableUi))
          .fontColor(this.c.sub)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .width(44).height(24)
        .selectedColor(this.c.accent)
        .enabled(!this.busy())
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onChange((enabled: boolean) => {
          if (enabled === isOn) return
          onFlip(enabled)
        })
    }
      .width('100%')
      .padding({ left: 12, right: 10, top: 8, bottom: 8 })
      .backgroundColor(isOn ? this.c.soft : this.c.bg)
      .borderRadius(UI_RADIUS_CONTROL)
      .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
  }

  build() {
    Column({ space: 8 }) {
      // 0. 通知授权提示条
      if (!this.notificationEnabled) {
        Row({ space: 8 }) {
          Text(this.t('开启系统通知以接收订阅提醒。'))
            .fontSize(panelFontSize(12, this.readableUi))
            .fontColor(this.c.sub).layoutWeight(1)
          this.action(this.t('开启通知'), !this.notificationBusy, () => { this.onRequestAccess() })
        }
          .width('100%')
          .padding({ left: 12, right: 10, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg)
          .border({ width: 1, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CARD)
      }

      // 1. 一键订阅方案（懒人模式：点一个方案，全套开关和科学时机自动配好）
      Column({ space: 8 }) {
        Row({ space: 4 }) {
          Text(this.tr('一键订阅方案', 'Quick Presets'))
            .fontSize(panelFontSize(13, this.readableUi))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.text)
          InfoTipButton({
            title: this.tr('一键订阅说明', 'Quick Presets'),
            tip: this.tr('不想逐项调整？直接选择一个观星场景，系统会自动打开对应天象开关并按最佳观测窗口安排提醒时机。',
              'Pick one preset to configure all relevant switches and astronomically optimal alert timing automatically.')
          })
          Blank()
          Text(this.tr('去日历筛选 ↗', 'Calendar ↗'))
            .fontSize(panelFontSize(11, this.readableUi))
            .fontColor(this.c.accent)
            .onClick(() => this.onOpenCalendar())
        }.width('100%').alignItems(VerticalAlign.Center)

        Grid() {
          ForEach(SUBSCRIPTION_PRESETS, (preset: SubscriptionPresetDefinition) => {
            GridItem() {
              Column({ space: 2 }) {
                Text(this.isZh() ? preset.labelZh : preset.labelEn)
                  .fontSize(panelFontSize(12, this.readableUi))
                  .fontWeight(this.matchedPresetId() === preset.id ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.matchedPresetId() === preset.id ? this.c.onAccent : this.c.text)
                  .maxLines(1)
              }
                .width('100%')
                .height(34)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(this.matchedPresetId() === preset.id ? this.c.accent : this.c.softStrong)
                .borderRadius(UI_RADIUS_CONTROL)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => {
                  if (this.busy()) return
                  this.onApplyPreset(preset.id)
                })
            }
          }, (preset: SubscriptionPresetDefinition) => preset.id + ':' + (this.matchedPresetId() === preset.id ? '1' : '0'))
        }
          .columnsTemplate('1fr 1fr')
          .columnsGap(6)
          .rowsGap(6)
          .width('100%')
          .height(74)
      }
        .width('100%')
        .padding(10)
        .backgroundColor(this.c.bg)
        .border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CARD)

      // 2. 简洁主题开关（想开几个开几个，其他全自动）
      Column({ space: 4 }) {
        Row() {
          Text(this.tr('订阅主题开关', 'Topic Switches'))
            .fontSize(panelFontSize(12, this.readableUi))
            .fontColor(this.c.sub)
            .layoutWeight(1)
          Row({ space: 4 }) {
            Text(this.tr('仅重磅', 'Major only'))
              .fontSize(panelFontSize(11, this.readableUi))
              .fontColor(this.highlightOnlyOn ? this.c.onAccent : this.c.sub)
          }
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .backgroundColor(this.highlightOnlyOn ? this.c.accent : this.c.softStrong)
            .borderRadius(UI_RADIUS_PILL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              if (this.busy()) return
              this.highlightOnlyOn = !this.highlightOnlyOn
              this.onToggleHighlightOnly(this.highlightOnlyOn)
            })
        }.width('100%').padding({ left: 2, right: 2, bottom: 2 })

        this.topicSwitchRow(
          this.tr('流星雨极大', 'Meteor Shower Peaks'),
          this.tr('极大前一晚 19:00 入夜前预告（绝不凌晨吵醒）', 'Evening before peak at 19:00'),
          this.meteorOn,
          (v: boolean) => { this.meteorOn = v; this.onToggleTopic('meteor', v) }
        )
        this.topicSwitchRow(
          this.tr('行星冲日 / 大距 / 合月', 'Planets & Conjunctions'),
          this.tr('西大距与明晨合相前一晚 20:00；昏后天象日落前', 'Pre-dawn alerts night before; evening events before sunset'),
          this.planetOn,
          (v: boolean) => { this.planetOn = v; this.onToggleTopic('planet', v) }
        )
        this.topicSwitchRow(
          this.tr('满月、超级月亮与新月', 'Full Moon, Supermoon & New Moon'),
          this.tr('傍晚月升前 17:30 提醒赏月 / 入夜暗空提醒', 'Before moonrise (17:30) or dark-sky evening'),
          this.moonOn,
          (v: boolean) => { this.moonOn = v; this.onToggleTopic('moon', v) }
        )
        this.topicSwitchRow(
          this.tr('二十四节气与分至点', 'Solar Terms & Solstices'),
          this.tr('交节当日早间 09:00（按所选地理区域区分南北半球）', 'Morning of node (hemisphere-aware)'),
          this.solarTermOn,
          (v: boolean) => { this.solarTermOn = v; this.onToggleTopic('solar_term', v) }
        )
        this.topicSwitchRow(
          this.tr('空间站与亮卫星过境', 'Space Stations & Bright Passes'),
          this.tr(`过境前 ${this.passLeadMinutes} 分钟临场倒计时 · 自动避开静默时段`, `${this.passLeadMinutes}m before pass · respects quiet hours`),
          this.satelliteOn,
          (v: boolean) => { this.satelliteOn = v; this.onToggleTopic('satellite', v) }
        )

        if (this.astronomySubscriptionStatus.length > 0) { this.hint(this.t(this.astronomySubscriptionStatus)) }
        if (this.satelliteSubscriptionStatus.length > 0) { this.hint(this.t(this.satelliteSubscriptionStatus)) }
      }
        .width('100%')
        .padding(8)
        .backgroundColor(this.c.bg)
        .border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CARD)

      // 3. 折叠式「时机与静默高级设置」抽屉（通知固定跟随当前地球观测位置，不再单独选自定义区域）
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Column({ space: 2 }) {
            Text(this.tr('通知时机与静默设置', 'Timing & Quiet Hours'))
              .fontSize(panelFontSize(13, this.readableUi))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.text)
            Text(this.tr(
              `${this.timingMode === 'day_before' ? '提前一天傍晚' : (this.timingMode === 'just_in_time' ? '临场前 1 小时' : '智能最佳窗口')} · 卫星提前 ${this.passLeadMinutes} 分 · ${this.dndOn ? ('静默 ' + this.hhmm(this.dndStartMinutes) + '–' + this.hhmm(this.dndEndMinutes)) : '未开静默'}`,
              `${this.timingMode} · Sat ${this.passLeadMinutes}m · ${this.dndOn ? ('Quiet ' + this.hhmm(this.dndStartMinutes) + '–' + this.hhmm(this.dndEndMinutes)) : 'No quiet hours'}`))
              .fontSize(panelFontSize(10, this.readableUi))
              .fontColor(this.c.sub)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

          Text(this.advancedOpen ? this.tr('收起 ▴', 'Hide') : this.tr('展开 ▾', 'Adjust'))
            .fontSize(panelFontSize(11, this.readableUi))
            .fontColor(this.advancedOpen ? this.c.onAccent : this.c.text)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(this.advancedOpen ? this.c.accent : this.c.softStrong)
            .borderRadius(UI_RADIUS_PILL)
            .onClick(() => {
              this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
                this.advancedOpen = !this.advancedOpen
              })
            })
        }.width('100%').alignItems(VerticalAlign.Center)

        if (this.advancedOpen) {
          Column({ space: 10 }) {
            // 天文事件时机策略
            Column({ space: 6 }) {
              Text(this.tr('天文事件提醒时机', 'Astronomy Event Timing'))
                .fontSize(panelFontSize(11, this.readableUi))
                .fontColor(this.c.sub).width('100%')
              Row({ space: 6 }) {
                ForEach(TIMING_MODE_CHOICES, (opt: TimingChoiceItem) => {
                  Text(this.isZh() ? opt.labelZh : opt.labelEn)
                    .fontSize(panelFontSize(11, this.readableUi))
                    .fontWeight(normalizeTimingMode(this.timingMode) === opt.id ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(normalizeTimingMode(this.timingMode) === opt.id ? this.c.onAccent : this.c.text)
                    .textAlign(TextAlign.Center)
                    .layoutWeight(1)
                    .height(34)
                    .backgroundColor(normalizeTimingMode(this.timingMode) === opt.id ? this.c.accent : this.c.softStrong)
                    .borderRadius(UI_RADIUS_CONTROL)
                    .onClick(() => {
                      if (!this.busy()) this.onTimingModeChange(opt.id)
                    })
                }, (opt: TimingChoiceItem) => opt.id + ':' + (normalizeTimingMode(this.timingMode) === opt.id ? '1' : '0'))
              }.width('100%')
              Text(this.isZh()
                ? (TIMING_MODE_CHOICES.find((x) => x.id === normalizeTimingMode(this.timingMode))?.descZh ?? '')
                : (TIMING_MODE_CHOICES.find((x) => x.id === normalizeTimingMode(this.timingMode))?.descEn ?? ''))
                .fontSize(panelFontSize(10, this.readableUi))
                .fontColor(this.c.sub).width('100%')
            }.width('100%')

            // 卫星过境提前量快选 + 步进
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                Text(this.tr('卫星过境提前提醒', 'Satellite Pass Lead Time'))
                  .fontSize(panelFontSize(11, this.readableUi))
                  .fontColor(this.c.sub).layoutWeight(1)
                this.action('−', !this.busy() && this.passLeadMinutes > 0, () => { this.onLeadChange(-1) })
                Text(this.passLeadMinutes + this.t(' 分钟'))
                  .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
                this.action('＋', !this.busy() && this.passLeadMinutes < 60, () => { this.onLeadChange(1) })
              }.width('100%').alignItems(VerticalAlign.Center)

              Row({ space: 6 }) {
                ForEach(LEAD_QUICK_OPTIONS, (mins: number) => {
                  Text(String(mins) + this.tr(' 分钟', 'm'))
                    .fontSize(panelFontSize(11, this.readableUi))
                    .fontColor(this.passLeadMinutes === mins ? this.c.onAccent : this.c.text)
                    .textAlign(TextAlign.Center)
                    .layoutWeight(1)
                    .height(30)
                    .backgroundColor(this.passLeadMinutes === mins ? this.c.accent : this.c.softStrong)
                    .borderRadius(UI_RADIUS_CONTROL)
                    .onClick(() => {
                      if (!this.busy()) this.onSetLeadMinutes(mins)
                    })
                }, (mins: number) => String(mins) + ':' + (this.passLeadMinutes === mins ? '1' : '0'))
              }.width('100%')
            }.width('100%')

            // 静默时段
            Column({ space: 6 }) {
              Row() {
                Row({ space: 2 }) {
                  Text(this.t('静默时段')).fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text)
                  InfoTipButton({
                    title: this.t('静默时段'),
                    tip: this.dndSatelliteOnlyOn
                      ? this.tr('默认仅跳过夜间卫星过境；重要天文事件已通过智能窗口在傍晚提前通知。',
                        'Quiet hours skip overnight satellite passes; major sky events already alert in the evening.')
                      : this.tr('全类别静默开启时，夜间天文预告将自动提前至傍晚 19:30 安全窗口，不打扰睡眠。',
                        'Overnight astronomy previews shift safely to 19:30 evening window instead of waking you.')
                  })
                }.layoutWeight(1).alignItems(VerticalAlign.Center)
                Toggle({ type: ToggleType.Switch, isOn: this.dndOn }).width(44).height(24)
                  .selectedColor(this.c.accent).enabled(!this.busy())
                  .onChange((enabled: boolean) => {
                    if (enabled === this.dndOn) return
                    this.dndOn = enabled
                    this.onToggleDnd(enabled)
                  })
              }.width('100%')

              if (this.dndOn) {
                Row({ space: 8 }) {
                  this.action(this.hhmm(this.dndStartMinutes), !this.busy(), () => { this.chooseQuietTime(true) })
                  Text(this.t('至')).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub)
                  this.action(this.hhmm(this.dndEndMinutes), !this.busy(), () => { this.chooseQuietTime(false) })
                  Blank()
                  Text(this.t('仅限卫星')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
                  Toggle({ type: ToggleType.Switch, isOn: this.dndSatelliteOnlyOn }).width(40).height(22)
                    .selectedColor(this.c.accent).enabled(!this.busy())
                    .onChange((enabled: boolean) => {
                      if (enabled === this.dndSatelliteOnlyOn) return
                      this.dndSatelliteOnlyOn = enabled
                      this.onToggleDndSatelliteOnly(enabled)
                    })
                }.width('100%').alignItems(VerticalAlign.Center)
              }
            }.width('100%')
          }
            .width('100%')
            .padding({ top: 4 })
            .transition(uiFadeUpTransition())
        }
      }
        .width('100%')
        .padding(10)
        .backgroundColor(this.c.bg)
        .border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CARD)

      // 5. 统一「已预约提醒」列表（应用订阅 + 日历预约 + 桌面小组件预约全部聚合）
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Row({ space: 2 }) {
            Text(this.t('已注册提醒（') + String(this.reminderCount) + this.t('）'))
              .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text)
            InfoTipButton({
              title: this.t('已注册提醒'),
              tip: this.tr('聚合显示自动订阅、日历手动预约与桌面小组件预约的系统代理提醒；在任意位置取消都会同步更新。',
                'Shows all system agent reminders from subscriptions, calendar bookings, and desktop widgets in sync.')
            })
          }.layoutWeight(1).alignItems(VerticalAlign.Center)
          this.action(this.t('刷新'), !this.notificationBusy, () => { this.onRefreshReminders() })
          if (this.reminders.length > 0) {
            this.action(this.t('清除全部'), !this.notificationBusy, () => { this.onClearReminders() })
          }
        }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8 })
        if (!this.reminderListLoaded && this.reminders.length === 0) {
          this.hint(this.t('点击刷新读取系统提醒。'))
        } else if (this.reminders.length === 0) {
          this.hint(this.t('尚未注册提醒。'))
        } else {
          ForEach(this.reminders, (item: AstronomyReminderItem) => {
            Row({ space: 6 }) {
              Column({ space: 2 }) {
                Row({ space: 4 }) {
                  Text(this.sourceBadgeText(item))
                    .fontSize(panelFontSize(9, this.readableUi))
                    .fontColor(this.c.accent)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                    .backgroundColor(this.c.soft)
                    .borderRadius(UI_RADIUS_PILL)
                  Text(item.title).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }.width('100%').alignItems(VerticalAlign.Center)
                Text(this.reminderTimeText(item)).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              this.action(this.t('查看'), !this.notificationBusy, () => { this.onPreviewReminder(item) })
              this.action(this.t('取消'), !this.notificationBusy, () => { this.onCancelReminder(item.reminderId) })
            }
              .width('100%')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          }, (item: AstronomyReminderItem) => `${item.reminderId}:${item.title}:${item.subscription ?? ''}`)
        }
      }
        .width('100%')
        .padding({ bottom: 8 })
        .backgroundColor(this.c.bg)
        .border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CARD)

      // 5.5 实况窗倒计时（标准 TIMER 场景：状态栏胶囊 + 锁屏卡片）
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Row({ space: 2 }) {
            Text(this.tr('实况窗倒计时', 'Live View Countdown'))
              .fontSize(panelFontSize(13, this.readableUi))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.text)
            InfoTipButton({
              title: this.tr('实况窗倒计时', 'Live View Countdown'),
              tip: this.tr('采用鸿蒙系统原生计时（TIMER）实况窗：在状态栏胶囊与锁屏卡片同步展示过境升起/落下方位、最大仰角与实时倒计时，退后台零耗电。调测阶段需在 AGC 实况窗白名单登记测试设备并满 24 小时生效。',
                'Uses native HarmonyOS TIMER Live View for status-bar capsule and lock-screen countdown with rise/set azimuth and peak elevation.')
            })
          }.layoutWeight(1).alignItems(VerticalAlign.Center)
          if (this.liveViewActiveTitle.length > 0) {
            this.action(this.tr('停止实况窗', 'Stop'), true, () => { this.onStopLiveView() })
          }
        }.width('100%')
        if (this.liveViewActiveTitle.length > 0) {
          Text(this.tr('当前运行中：', 'Active: ') + this.liveViewActiveTitle)
            .fontSize(panelFontSize(11, this.readableUi))
            .fontColor(this.c.accent)
            .width('100%')
        } else {
          Text(this.tr('当卫星过境临近 30 分钟内，应用内会自动弹出 3D 地球轨道过境卡片并支持一键开启实况窗。',
            'A 3D Earth orbit pass card pops up automatically within 30 min of an upcoming pass.'))
            .fontSize(panelFontSize(10, this.readableUi))
            .fontColor(this.c.sub)
            .width('100%')
        }
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          this.action(this.tr('空间站过境实况窗', 'Station Pass Live View'), true, () => { this.onStartSatLiveView() })
          this.action(this.tr('暗适应 20 分钟', 'Dark Adapt 20m'), true, () => { this.onStartDarkAdaptLiveView() })
          this.action(this.tr('预览过境卡片', 'Preview Pass Card'), true, () => { this.onPreviewSatPassCard() })
        }.width('100%')
        if (this.liveViewStatusText.length > 0) {
          Text(this.liveViewStatusText)
            .fontSize(panelFontSize(10, this.readableUi))
            .fontColor(this.c.sub)
            .width('100%')
        }
      }
        .width('100%')
        .padding({ left: 12, right: 10, top: 9, bottom: 9 })
        .backgroundColor(this.c.bg)
        .border({ width: 1, color: this.liveViewActiveTitle.length > 0 ? this.c.accent : this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CARD)

      // 6. 桌面小组件工作台快捷入口
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.tr('桌面小组件工作台', 'Desktop Widget Studio'))
            .fontSize(panelFontSize(13, this.readableUi))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.text)
          Text(this.tr('逐张精细调整 8 款桌面卡片样式、地理区域与提醒同步', 'Fine-tune all 8 desktop widgets, regions & synced reminders'))
            .fontSize(panelFontSize(10, this.readableUi))
            .fontColor(this.c.sub)
        }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        this.action(this.tr('打开 ↗', 'Open ↗'), true, () => { this.onOpenWidgetStudio() })
      }
        .width('100%')
        .padding({ left: 12, right: 10, top: 9, bottom: 9 })
        .backgroundColor(this.c.soft)
        .border({ width: 1, color: this.c.border })
        .borderRadius(UI_RADIUS_CARD)
        .alignItems(VerticalAlign.Center)

      if (this.statusText.length > 0) { this.hint(this.t(this.statusText)) }
      if (this.preferencesError.length > 0) { this.hint(this.t(this.preferencesError)) }
      if (this.reminderListError.length > 0) { this.hint(this.t(this.reminderListError)) }
    }.width('100%')
  }
}
