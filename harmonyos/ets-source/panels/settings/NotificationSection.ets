import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 设置面板「通知与提醒」区块：通知授权状态 + 开启通知按钮 + 已注册提醒数 +
// 订阅下一节气提醒 / 清除全部提醒。宿主注入 store 快照值与四个回调。
@Component
export struct NotificationSection {
  @Prop notificationEnabled: boolean
  @Prop notificationBusy: boolean
  @Prop reminderCount: number
  @Prop statusText: string
  @State c: ThemeSlots = DEFAULT_SLOTS
  onRequestAccess: () => void = () => {}
  onScheduleNextSolarTerm: () => void = () => {}
  onClearReminders: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 0 }) {
      Text('通知与提醒').fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
      Row() {
        Text(this.statusText).fontSize(10).fontColor(this.c.sub).layoutWeight(1)
        Button(this.notificationEnabled ? '已开启' : '开启通知')
          .fontSize(11).fontColor(this.c.text).backgroundColor(this.c.dividerSoft)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 12, right: 12 })
          .enabled(!this.notificationBusy && !this.notificationEnabled)
          .onClick(() => { this.onRequestAccess() })
      }.width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 6 })
      Text('当前已注册 ' + this.reminderCount.toString() + ' 条；只在用户主动订阅后安排。')
        .fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 6 })
      Row({ space: 8 }) {
        Button('订阅下一节气提醒')
          .fontSize(11).fontColor(this.c.text).backgroundColor(this.c.dividerSoft)
          .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1)
          .enabled(!this.notificationBusy && this.notificationEnabled)
          .onClick(() => { this.onScheduleNextSolarTerm() })
        Button('清除全部提醒')
          .fontSize(11).fontColor(this.c.errorText).backgroundColor(this.c.errorBg)
          .border({ width: 1, color: this.c.errorBg })
          .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1)
          .enabled(!this.notificationBusy && this.reminderCount > 0)
          .onClick(() => { this.onClearReminders() })
      }.width('100%').padding({ left: 10, right: 10 })
    }.width('100%')
  }
}
