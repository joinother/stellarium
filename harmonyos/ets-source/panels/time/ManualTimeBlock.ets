import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 手动指定时间块：滚动选择日期 / 时间 + 应用与重置。
//
// 日期/时间的权威状态由宿主持有（`applyManualTime()` / `syncManualTimeFromState()` 与其它面板都要读），
// 本组件以 @Prop 接收 5 个字段、经回调交回修改；选择对话框的 `selected` 临时值由组件按 props 自身构造。
@Component
export struct ManualTimeBlock {
  @Prop manualYear: number
  @Prop manualMonth: number
  @Prop manualDay: number
  @Prop manualHour: number
  @Prop manualMinute: number
  @Prop textColor: string
  @Prop subColor: string
  @Prop inputColor: string
  @Prop panelColor: string
  @Prop borderColorValue: string
  @State private dialogDate: Date = new Date()
  @State private dialogTime: Date = new Date()
  onPickDate: (year: number, month: number, day: number) => void = () => {}
  onPickTime: (hour: number, minute: number) => void = () => {}
  onApply: () => void = () => {}
  onReset: () => void = () => {}

  build() {
    Column() {
      Row() {
        Text(I18n.t('i0012')).fontSize(13).fontColor(this.subColor).width(72)
        Button(this.manualYear + '年' + this.manualMonth + '月' + this.manualDay + '日')
          .fontSize(14).fontColor(this.textColor).backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1)
          .onClick(() => {
            this.dialogDate = new Date(this.manualYear, this.manualMonth - 1, this.manualDay)
            this.getUIContext().showDatePickerDialog({
              start: new Date('1900-01-01'),
              end: new Date('2100-12-31'),
              selected: this.dialogDate,
              onAccept: (value: DatePickerResult) => {
                this.onPickDate(
                  value.year ?? this.manualYear,
                  value.month ?? (this.manualMonth - 1),
                  value.day ?? this.manualDay
                )
              },
              onCancel: () => {}
            })
          })
      }
      .height(40).width('100%').padding({ left: 10, right: 10 })
      .backgroundColor('rgba(255,255,255,0.045)').borderRadius(UI_RADIUS_CONTROL).margin({ top: 4, bottom: 4 })
      Row() {
        Text(I18n.t('i0013')).fontSize(13).fontColor(this.subColor).width(72)
        Button(String(this.manualHour).padStart(2, '0') + ':' + String(this.manualMinute).padStart(2, '0'))
          .fontSize(14).fontColor(this.textColor).backgroundColor(this.inputColor)
          .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1)
          .onClick(() => {
            this.dialogTime = new Date(2000, 0, 1, this.manualHour, this.manualMinute)
            this.getUIContext().showTimePickerDialog({
              selected: this.dialogTime,
              onAccept: (value: TimePickerResult) => {
                this.onPickTime(value.hour ?? this.manualHour, value.minute ?? this.manualMinute)
              },
              onCancel: () => {}
            })
          })
      }
      .height(40).width('100%').padding({ left: 10, right: 10 })
      .backgroundColor('rgba(255,255,255,0.045)').borderRadius(UI_RADIUS_CONTROL).margin({ top: 4, bottom: 4 })
      Button(I18n.t('i0046'))
        .fontSize(14).fontColor('#FFFFFFFF').backgroundColor('#5B93BF')
        .borderRadius(UI_RADIUS_CONTROL).height(40).width('100%').margin({ top: 4, bottom: 4 })
        .onClick(() => { this.onApply() })
      Button(I18n.t('i0047'))
        .fontSize(13).fontColor('#99FFFFFF').backgroundColor(this.borderColorValue)
        .borderRadius(UI_RADIUS_CONTROL).height(36).width('100%').margin({ top: 4, bottom: 4 })
        .onClick(() => { this.onReset() })
    }.width('100%')
  }
}
