import { I18n } from '../../capability/I18n'
import { notificationText } from '../../capability/NotificationText'
import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyReminderItem } from '../../qability/AstronomyReminderService'

@Component
export struct NotificationSection {
  @StorageProp('i18nLang') language: string = I18n.getLanguage()

  private t(value: string): string { return notificationText(value, this.language) }
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop notificationEnabled: boolean
  @Prop notificationBusy: boolean
  @Prop reminderCount: number
  @Prop statusText: string
  @Prop @Watch('syncToggles') astronomyEventsEnabled: boolean
  @Prop @Watch('syncToggles') satellitePassEnabled: boolean
  @Prop @Watch('syncToggles') digestEnabled: boolean
  @Prop @Watch('syncToggles') dndEnabled: boolean
  @Prop @Watch('syncToggles') dndSatelliteOnly: boolean = true
  // Toggle 的 isOn 直接绑 @Prop 时，父层写回会再触发一次 onChange 回声
  // （实测 true 后约 60ms 又收到 false），开关会自己弹回去。用本地状态
  // 承接用户操作，并用值相等判断忽略程序化回声。
  @State private astronomyOn: boolean = false
  @State private satelliteOn: boolean = false
  @State private digestOn: boolean = false
  @State private dndOn: boolean = false
  @State private dndSatelliteOnlyOn: boolean = true
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
  @State c: ThemeSlots = DEFAULT_SLOTS

  onRequestAccess: () => void = () => {}
  onToggleAstronomyEvents: (enabled: boolean) => void = () => {}
  onToggleSatellitePass: (enabled: boolean) => void = () => {}
  onToggleDigest: (enabled: boolean) => void = () => {}
  onToggleDnd: (enabled: boolean) => void = () => {}
  onToggleDndSatelliteOnly: (enabled: boolean) => void = () => {}
  onDndStartChange: (minutes: number) => void = () => {}
  onDndEndChange: (minutes: number) => void = () => {}
  onLeadChange: (delta: number) => void = () => {}
  onScheduleNextSolarTerm: () => void = () => {}
  onScheduleNextMoonPhase: () => void = () => {}
  onScheduleNextMeteor: () => void = () => {}
  onOpenCalendar: () => void = () => {}
  onRefreshReminders: () => void = () => {}
  onCancelReminder: (id: number) => void = () => {}
  onClearReminders: () => void = () => {}
  onScheduleCountdown: (minutes: number) => void = () => {}
  onScheduleCalendarAt: (timestamp: number) => void = () => {}
  onScheduleAlarm: (hour: number, minute: number) => void = () => {}
  onFetchPushToken: () => void = () => {}

  aboutToAppear(): void { this.syncToggles() }

  private syncToggles(): void {
    this.astronomyOn = this.astronomyEventsEnabled
    this.satelliteOn = this.satellitePassEnabled
    this.digestOn = this.digestEnabled
    this.dndOn = this.dndEnabled
    this.dndSatelliteOnlyOn = this.dndSatelliteOnly
  }

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private hhmm(minutes: number): string {
    return String(Math.floor(minutes / 60)).padStart(2, '0') + ':' + String(minutes % 60).padStart(2, '0')
  }

  private reminderTimeText(item: AstronomyReminderItem): string {
    const dt = item.dateTime
    if (dt === null || dt === undefined) return this.t('倒计时或周期提醒 · 由系统管理')
    const pad = (v: number): string => String(v).padStart(2, '0')
    return `${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}`
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
      .width('100%').padding({ left: 10, right: 8 }).margin({ bottom: 4 })
  }

  @Builder
  action(label: string, enabled: boolean, callback: () => void) {
    Button(label, { type: ButtonType.Normal }).fontSize(panelFontSize(12, this.readableUi))
      .fontColor(this.c.text).backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL)
      .constraintSize({ minHeight: 40 }).padding({ left: 12, right: 12 })
      .enabled(enabled).onClick(() => { callback() })
  }

  build() {
    Column({ space: 6 }) {
      if (!this.notificationEnabled) {
        Row({ space: 8 }) {
          Text(this.t('开启系统通知以接收订阅提醒。')).fontSize(panelFontSize(12, this.readableUi))
            .fontColor(this.c.sub).layoutWeight(1)
          this.action(this.t('开启通知'), !this.notificationBusy, () => { this.onRequestAccess() })
        }
          .width('100%')
          .padding({ left: 10, right: 8, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg)
          .border({ width: 1, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL)
          .margin({ bottom: 6 })
      }
      Column({ space: 4 }) {
        Row() {
          Text(this.t('天象事件')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.astronomyOn }).width(44).height(24)
            .selectedColor(this.c.accent).enabled(!this.notificationBusy && !this.preferencesBusy)
            .onChange((enabled: boolean) => {
              if (enabled === this.astronomyOn) return
              this.astronomyOn = enabled
              this.onToggleAstronomyEvents(enabled)
            })
        }
          .width('100%')
          .height(this.readableUi ? 50 : 42)
          .padding({ left: 10, right: 8 })
        this.hint(this.t('订阅本地天象日历中的近期事件。'))
        if (this.astronomySubscriptionStatus.length > 0) { this.hint(this.t(this.astronomySubscriptionStatus)) }
      }
        .width('100%')
        .backgroundColor(this.astronomyOn ? this.c.soft : this.c.bg)
        .border({ width: 1, color: this.astronomyOn ? this.c.soft : this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL)
        .margin({ bottom: 6 })
      Column({ space: 4 }) {
        Row() {
          Text(this.t('卫星通过')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteOn }).width(44).height(24)
            .selectedColor(this.c.accent).enabled(!this.notificationBusy && !this.preferencesBusy)
            .onChange((enabled: boolean) => {
              if (enabled === this.satelliteOn) return
              this.satelliteOn = enabled
              this.onToggleSatellitePass(enabled)
            })
        }
          .width('100%')
          .height(this.readableUi ? 50 : 42)
          .padding({ left: 10, right: 8 })
        this.hint(this.t('按你选择的观测地点预测可见通过，无需定位权限。'))
        Row({ space: 8 }) {
          Text(this.t('提前提醒')).fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
          this.action('−', !this.notificationBusy && !this.preferencesBusy && this.passLeadMinutes > 0, () => { this.onLeadChange(-1) })
          Text(this.passLeadMinutes + this.t(' 分钟')).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
          this.action('＋', !this.notificationBusy && !this.preferencesBusy && this.passLeadMinutes < 60, () => { this.onLeadChange(1) })
        }
          .width('100%')
          .padding({ left: 10, right: 8 })
          .margin({ bottom: 4 })
        if (this.satelliteSubscriptionStatus.length > 0) { this.hint(this.t(this.satelliteSubscriptionStatus)) }
      }
        .width('100%')
        .backgroundColor(this.satelliteOn ? this.c.soft : this.c.bg)
        .border({ width: 1, color: this.satelliteOn ? this.c.soft : this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL)
        .margin({ bottom: 6 })
      Column({ space: 4 }) {
        Row() {
          Text(this.t('静默时段')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.dndOn }).width(44).height(24)
            .selectedColor(this.c.accent).enabled(!this.notificationBusy && !this.preferencesBusy)
            .onChange((enabled: boolean) => {
              if (enabled === this.dndOn) return
              this.dndOn = enabled
              this.onToggleDnd(enabled)
            })
        }
          .width('100%')
          .height(this.readableUi ? 50 : 42)
          .padding({ left: 10, right: 8 })
        if (this.dndOn) {
          Row({ space: 8 }) {
            this.action(this.hhmm(this.dndStartMinutes), !this.notificationBusy && !this.preferencesBusy, () => { this.chooseQuietTime(true) })
            Text(this.t('至')).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub)
            this.action(this.hhmm(this.dndEndMinutes), !this.notificationBusy && !this.preferencesBusy, () => { this.chooseQuietTime(false) })
          }
            .width('100%')
            .padding({ left: 10, right: 8 })
            .margin({ bottom: 4 })
          Row() {
            Text(this.t('仅限卫星通过')).fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.dndSatelliteOnlyOn }).width(44).height(24)
              .selectedColor(this.c.accent).enabled(!this.notificationBusy && !this.preferencesBusy)
              .onChange((enabled: boolean) => {
                if (enabled === this.dndSatelliteOnlyOn) return
                this.dndSatelliteOnlyOn = enabled
                this.onToggleDndSatelliteOnly(enabled)
              })
          }
            .width('100%')
            .height(this.readableUi ? 44 : 38)
            .padding({ left: 10, right: 8 })
          this.hint(this.dndStartMinutes === this.dndEndMinutes ? this.t('起止时间相同表示全天静默。') :
            (this.dndSatelliteOnlyOn ? this.t('静默时段仅跳过卫星通过，不拦截深夜天象事件。') :
              this.t('所有本地订阅跳过静默时段，不延迟事件。')))
        }
      }
        .width('100%')
        .backgroundColor(this.dndOn ? this.c.soft : this.c.bg)
        .border({ width: 1, color: this.dndOn ? this.c.soft : this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL)
        .margin({ bottom: 6 })
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(this.t('已注册提醒（') + String(this.reminderCount) + this.t('）'))
            .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
          this.action(this.t('刷新'), !this.notificationBusy, () => { this.onRefreshReminders() })
          if (this.reminders.length > 0) {
            this.action(this.t('清除全部'), !this.notificationBusy, () => { this.onClearReminders() })
          }
        }
          .width('100%')
          .padding({ left: 10, right: 8, top: 8 })
        if (!this.reminderListLoaded && this.reminders.length === 0) {
          this.hint(this.t('点击刷新读取系统提醒。'))
        } else if (this.reminders.length === 0) {
          this.hint(this.t('尚未注册提醒。'))
        } else {
          ForEach(this.reminders, (item: AstronomyReminderItem) => {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(item.title).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(this.reminderTimeText(item)).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              this.action(this.t('取消'), !this.notificationBusy, () => { this.onCancelReminder(item.reminderId) })
            }
              .width('100%')
              .padding({ left: 10, right: 8, top: 4, bottom: 4 })
          }, (item: AstronomyReminderItem) => `${item.reminderId}:${item.title}`)
          this.hint(this.t('系统可能保留已到时但尚未关闭的提醒；此列表不是送达记录。'))
        }
      }
        .width('100%')
        .padding({ bottom: 6 })
        .backgroundColor(this.c.bg)
        .border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL)
        .margin({ bottom: 6 })
      this.hint(this.t('打开应用时更新近期提醒；关闭分类会取消该分类的订阅提醒。'))
      if (this.statusText.length > 0) { this.hint(this.t(this.statusText)) }
      if (this.preferencesError.length > 0) { this.hint(this.t(this.preferencesError)) }
      if (this.reminderListError.length > 0) { this.hint(this.t(this.reminderListError)) }
    }.width('100%')
  }
}
