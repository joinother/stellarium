import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 设置面板「通知」区块：按通知类别分卡片（天文事件 / 卫星通过 / 观测建议）。
// 卫星卡片内嵌勿扰模式时段与提前提醒分钟数；自定义定时提醒收在最后一张卡片，
// 供需要精确时刻的用户使用（倒计时 / 指定时间 / 每日）。
@Component
export struct NotificationSection {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop notificationEnabled: boolean
  @Prop notificationBusy: boolean
  @Prop reminderCount: number
  @Prop statusText: string
  @Prop astronomyEventsEnabled: boolean
  @Prop satellitePassEnabled: boolean
  @Prop digestEnabled: boolean
  @Prop dndEnabled: boolean
  @Prop dndStartMinutes: number
  @Prop dndEndMinutes: number
  @Prop passLeadMinutes: number
  @State c: ThemeSlots = DEFAULT_SLOTS

  onRequestAccess: () => void = () => {}
  onToggleAstronomyEvents: (enabled: boolean) => void = () => {}
  onToggleSatellitePass: (enabled: boolean) => void = () => {}
  onToggleDigest: (enabled: boolean) => void = () => {}
  onToggleDnd: (enabled: boolean) => void = () => {}
  onDndStartChange: (minutes: number) => void = () => {}
  onDndEndChange: (minutes: number) => void = () => {}
  onLeadChange: (delta: number) => void = () => {}
  onScheduleNextSolarTerm: () => void = () => {}
  onScheduleNextMoonPhase: () => void = () => {}
  onScheduleNextMeteor: () => void = () => {}
  onClearReminders: () => void = () => {}
  onScheduleCountdown: (minutes: number) => void = () => {}
  onScheduleCalendarAt: (timestamp: number) => void = () => {}
  onScheduleAlarm: (hour: number, minute: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private hhmm(minutes: number): string {
    const h = Math.floor(minutes / 60)
    const m = minutes % 60
    return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0')
  }

  @Builder
  cardTitle(title: string, on: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(title).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).fontWeight(FontWeight.Medium)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: on })
        .width(44).height(24)
        .selectedColor(this.c.accent)
        .enabled(!this.notificationBusy)
        .onChange((value: boolean) => { onChange(value) })
    }.width('100%')
  }

  @Builder
  hint(text: string) {
    Text(text)
      .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
      .width('100%').margin({ top: 6 })
  }

  @Builder
  divider() {
    Divider().color(this.c.dividerSoft).strokeWidth(1).width('100%').margin({ top: 10, bottom: 10 })
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(this.statusText).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).layoutWeight(1)
        Button(this.notificationEnabled ? '已开启' : '开启通知')
          .fontSize(this.readableUi ? 12 : 11).fontColor(this.c.text).backgroundColor(this.c.dividerSoft)
          .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 36 : 28).padding({ left: 12, right: 12 })
          .enabled(!this.notificationBusy && !this.notificationEnabled)
          .onClick(() => { this.onRequestAccess() })
      }.width('100%').padding({ left: 10, right: 10 })

      // —— 天文事件 ——
      Column({ space: 0 }) {
        this.cardTitle('天文事件', this.astronomyEventsEnabled, (v: boolean) => { this.onToggleAstronomyEvents(v) })
        this.hint('绝不错过流星雨、日食或其它重要的天文奇观。')
        this.divider()
        Row({ space: 8 }) {
          Button('节气').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
            .backgroundColor(this.c.dividerSoft).borderRadius(UI_RADIUS_CONTROL)
            .height(this.readableUi ? 30 : 26).padding({ left: 10, right: 10 })
            .enabled(!this.notificationBusy && this.notificationEnabled && this.astronomyEventsEnabled)
            .onClick(() => { this.onScheduleNextSolarTerm() })
          Button('满月').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
            .backgroundColor(this.c.dividerSoft).borderRadius(UI_RADIUS_CONTROL)
            .height(this.readableUi ? 30 : 26).padding({ left: 10, right: 10 })
            .enabled(!this.notificationBusy && this.notificationEnabled && this.astronomyEventsEnabled)
            .onClick(() => { this.onScheduleNextMoonPhase() })
          Button('流星雨').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
            .backgroundColor(this.c.dividerSoft).borderRadius(UI_RADIUS_CONTROL)
            .height(this.readableUi ? 30 : 26).padding({ left: 10, right: 10 })
            .enabled(!this.notificationBusy && this.notificationEnabled && this.astronomyEventsEnabled)
            .onClick(() => { this.onScheduleNextMeteor() })
        }.width('100%')
      }
      .width('100%').padding(12)
      .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)

      // —— 卫星通过 ——
      Column({ space: 0 }) {
        this.cardTitle('卫星通过', this.satellitePassEnabled, (v: boolean) => { this.onToggleSatellitePass(v) })
        this.hint('当国际空间站或其它明亮的卫星即将在天空中可见时，及时获得提醒。')
        this.divider()

        Row() {
          Text('勿扰模式').fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.dndEnabled })
            .width(44).height(24).selectedColor(this.c.accent)
            .enabled(!this.notificationBusy && this.satellitePassEnabled)
            .onChange((value: boolean) => { this.onToggleDnd(value) })
        }.width('100%')
        this.hint('不显示 ' + this.hhmm(this.dndStartMinutes) + ' 到 ' + this.hhmm(this.dndEndMinutes) + ' 之间的卫星飞过事件通知。')

        Row({ space: 8 }) {
          Button(this.hhmm(this.dndStartMinutes))
            .fontSize(this.readableUi ? 12 : 11).fontColor(this.c.text).backgroundColor(this.c.input)
            .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 32 : 28).layoutWeight(1)
            .enabled(!this.notificationBusy && this.satellitePassEnabled && this.dndEnabled)
            .onClick(() => {
              TimePickerDialog.show({
                selected: new Date(2026, 0, 1, Math.floor(this.dndStartMinutes / 60), this.dndStartMinutes % 60),
                useMilitaryTime: true,
                onAccept: (value: TimePickerResult) => { this.onDndStartChange(value.hour * 60 + value.minute) }
              })
            })
          Text('到').fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
          Button(this.hhmm(this.dndEndMinutes))
            .fontSize(this.readableUi ? 12 : 11).fontColor(this.c.text).backgroundColor(this.c.input)
            .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 32 : 28).layoutWeight(1)
            .enabled(!this.notificationBusy && this.satellitePassEnabled && this.dndEnabled)
            .onClick(() => {
              TimePickerDialog.show({
                selected: new Date(2026, 0, 1, Math.floor(this.dndEndMinutes / 60), this.dndEndMinutes % 60),
                useMilitaryTime: true,
                onAccept: (value: TimePickerResult) => { this.onDndEndChange(value.hour * 60 + value.minute) }
              })
            })
        }.width('100%').margin({ top: 8 })
        .opacity(this.dndEnabled && this.satellitePassEnabled ? 1 : 0.45)

        this.divider()

        Row() {
          Text('提醒时间').fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
          Button('−').fontSize(16).fontColor(this.c.text).backgroundColor(this.c.input)
            .width(40).height(this.readableUi ? 34 : 30).borderRadius(UI_RADIUS_CONTROL)
            .enabled(!this.notificationBusy && this.satellitePassEnabled && this.passLeadMinutes > 1)
            .onClick(() => { this.onLeadChange(-1) })
          Text(this.passLeadMinutes + ' 分钟')
            .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
            .width(72).textAlign(TextAlign.Center)
          Button('＋').fontSize(16).fontColor(this.c.text).backgroundColor(this.c.input)
            .width(40).height(this.readableUi ? 34 : 30).borderRadius(UI_RADIUS_CONTROL)
            .enabled(!this.notificationBusy && this.satellitePassEnabled && this.passLeadMinutes < 60)
            .onClick(() => { this.onLeadChange(1) })
        }.width('100%')
        this.hint('过境前 ' + this.passLeadMinutes + ' 分钟提醒')
      }
      .width('100%').padding(12)
      .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)

      // —— 观测建议 ——
      Column({ space: 0 }) {
        this.cardTitle('观测建议', this.digestEnabled, (v: boolean) => { this.onToggleDigest(v) })
        this.hint('每月一次，汇总当月值得关注的天象与观测建议。')
      }
      .width('100%').padding(12)
      .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)

      // —— 自定义提醒 ——
      Column({ space: 0 }) {
        Text('自定义提醒').fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
          .width('100%').margin({ bottom: 8 })
        Row({ space: 8 }) {
          Button('15 分钟').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
            .backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 30 : 26)
            .layoutWeight(1)
            .enabled(!this.notificationBusy && this.notificationEnabled)
            .onClick(() => { this.onScheduleCountdown(15) })
          Button('30 分钟').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
            .backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 30 : 26)
            .layoutWeight(1)
            .enabled(!this.notificationBusy && this.notificationEnabled)
            .onClick(() => { this.onScheduleCountdown(30) })
          Button('选择时间').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
            .backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 30 : 26)
            .layoutWeight(1)
            .enabled(!this.notificationBusy && this.notificationEnabled)
            .onClick(() => {
              TimePickerDialog.show({
                selected: new Date(),
                useMilitaryTime: true,
                onAccept: (value: TimePickerResult) => {
                  const now = new Date()
                  this.onScheduleCalendarAt(new Date(now.getFullYear(), now.getMonth(), now.getDate(),
                    value.hour, value.minute).getTime())
                }
              })
            })
          Button('每日').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
            .backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 30 : 26)
            .layoutWeight(1)
            .enabled(!this.notificationBusy && this.notificationEnabled)
            .onClick(() => {
              TimePickerDialog.show({
                selected: new Date(),
                useMilitaryTime: true,
                onAccept: (value: TimePickerResult) => { this.onScheduleAlarm(value.hour, value.minute) }
              })
            })
        }.width('100%')
        Row() {
          Text('当前已注册 ' + this.reminderCount.toString() + ' 条')
            .fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).layoutWeight(1)
          Button('清除全部')
            .fontSize(this.readableUi ? 11 : 10).fontColor(this.c.errorText).backgroundColor(this.c.errorBg)
            .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 30 : 26).padding({ left: 12, right: 12 })
            .enabled(!this.notificationBusy && this.reminderCount > 0)
            .onClick(() => { this.onClearReminders() })
        }.width('100%').margin({ top: 10 })
      }
      .width('100%').padding(12)
      .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
    }.width('100%')
  }
}
