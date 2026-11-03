import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 设置面板「通知与提醒」区块：通知授权状态 + 开启通知按钮 + 已注册提醒数 +
// 订阅下一节气提醒 / 清除全部提醒。宿主注入 store 快照值与四个回调。
@Component
export struct NotificationSection {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop notificationEnabled: boolean
  @Prop notificationBusy: boolean
  @Prop reminderCount: number
  @Prop statusText: string
  @State c: ThemeSlots = DEFAULT_SLOTS
  onRequestAccess: () => void = () => {}
  onScheduleNextSolarTerm: () => void = () => {}
  onScheduleNextMoonPhase: () => void = () => {}
  onScheduleNextMeteor: () => void = () => {}
  // 用户主动设定的定时提醒（审核要求：必须能体现倒计时/日历/闹钟三类）
  onScheduleCountdown: (minutes: number) => void = () => {}
  onScheduleCalendarAt: (timestamp: number) => void = () => {}
  onScheduleAlarm: (hour: number, minute: number) => void = () => {}
  onClearReminders: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 0 }) {
      Text('通知与提醒').fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
      Row() {
        Text(this.statusText).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).layoutWeight(1)
        Button(this.notificationEnabled ? '已开启' : '开启通知')
          .fontSize(this.readableUi ? 12 : 11).fontColor(this.c.text).backgroundColor(this.c.dividerSoft)
          .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 36 : 28).padding({ left: 12, right: 12 })
          .enabled(!this.notificationBusy && !this.notificationEnabled)
          .onClick(() => { this.onRequestAccess() })
      }.width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 6 })
      Text('当前已注册 ' + this.reminderCount.toString() + ' 条；只在用户主动订阅后安排。')
        .fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 6 })
      // 可订阅的天象类别：每类都是一次用户主动点击，注册一条系统代理提醒。
      // —— 用户主动设定的定时提醒 ——
      // 代理提醒支持倒计时 / 日历 / 闹钟三类，这里各给一个入口，时间都由用户选择。
      Text('自定义定时提醒')
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 10 }).margin({ top: 4, bottom: 6 })
      Row({ space: 8 }) {
        Text('倒计时').fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .width(64).padding({ left: 10 })
        Button('15 分钟').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
          .backgroundColor(this.c.dividerSoft).borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 32 : 26)
          .enabled(!this.notificationBusy && this.notificationEnabled)
          .onClick(() => { this.onScheduleCountdown(15) })
        Button('30 分钟').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
          .backgroundColor(this.c.dividerSoft).borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 32 : 26)
          .enabled(!this.notificationBusy && this.notificationEnabled)
          .onClick(() => { this.onScheduleCountdown(30) })
        Button('60 分钟').fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
          .backgroundColor(this.c.dividerSoft).borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 32 : 26)
          .enabled(!this.notificationBusy && this.notificationEnabled)
          .onClick(() => { this.onScheduleCountdown(60) })
      }.width('100%').margin({ bottom: 8 })
      Row({ space: 8 }) {
        Text('指定时间').fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .width(64).padding({ left: 10 })
        Button('选择日期时间')
          .fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
          .backgroundColor(this.c.dividerSoft).borderRadius(UI_RADIUS_CONTROL)
          .height(this.readableUi ? 32 : 26).layoutWeight(1)
          .enabled(!this.notificationBusy && this.notificationEnabled)
          .onClick(() => {
            TimePickerDialog.show({
              selected: new Date(),
              useMilitaryTime: true,
              onAccept: (value: TimePickerResult) => {
                const now = new Date()
                const ts = new Date(now.getFullYear(), now.getMonth(), now.getDate(),
                  value.hour, value.minute).getTime()
                this.onScheduleCalendarAt(ts)
              }
            })
          })
      }.width('100%').margin({ bottom: 8 })
      Row({ space: 8 }) {
        Text('每日闹钟').fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .width(64).padding({ left: 10 })
        Button('选择每天提醒时刻')
          .fontSize(this.readableUi ? 11 : 10).fontColor(this.c.text)
          .backgroundColor(this.c.dividerSoft).borderRadius(UI_RADIUS_CONTROL)
          .height(this.readableUi ? 32 : 26).layoutWeight(1)
          .enabled(!this.notificationBusy && this.notificationEnabled)
          .onClick(() => {
            TimePickerDialog.show({
              selected: new Date(),
              useMilitaryTime: true,
              onAccept: (value: TimePickerResult) => {
                this.onScheduleAlarm(value.hour, value.minute)
              }
            })
          })
      }.width('100%').margin({ bottom: 10 })
      Row({ space: 8 }) {
        Button('下一节气')
          .fontSize(this.readableUi ? 12 : 11).fontColor(this.c.text).backgroundColor(this.c.dividerSoft)
          .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 36 : 30).layoutWeight(1)
          .enabled(!this.notificationBusy && this.notificationEnabled)
          .onClick(() => { this.onScheduleNextSolarTerm() })
        Button('下一次满月')
          .fontSize(this.readableUi ? 12 : 11).fontColor(this.c.text).backgroundColor(this.c.dividerSoft)
          .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 36 : 30).layoutWeight(1)
          .enabled(!this.notificationBusy && this.notificationEnabled)
          .onClick(() => { this.onScheduleNextMoonPhase() })
      }.width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 8 })
      Row({ space: 8 }) {
        Button('下一场流星雨')
          .fontSize(this.readableUi ? 12 : 11).fontColor(this.c.text).backgroundColor(this.c.dividerSoft)
          .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 36 : 30).layoutWeight(1)
          .enabled(!this.notificationBusy && this.notificationEnabled)
          .onClick(() => { this.onScheduleNextMeteor() })
        Button('清除全部提醒')
          .fontSize(this.readableUi ? 12 : 11).fontColor(this.c.errorText).backgroundColor(this.c.errorBg)
          .border({ width: 1, color: this.c.errorBg })
          .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 36 : 30).layoutWeight(1)
          .enabled(!this.notificationBusy && this.reminderCount > 0)
          .onClick(() => { this.onClearReminders() })
      }.width('100%').padding({ left: 10, right: 10 })
    }.width('100%')
  }
}
