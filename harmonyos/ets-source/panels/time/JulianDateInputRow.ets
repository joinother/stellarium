import { JulianDateStore } from '../../state/JulianDateStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 单行儒略日输入：标签 + 「-」/「+」微调 + 输入框。
//
// 独立成组件而不是参数化 @Builder：参数化 @Builder 的简单类型参数按值捕获，
// 其子树首帧后即冻结，儒略日数值不会随时间刷新。
// 输入框直接读 store，值随引擎同步实时更新。
@Component
export struct JulianDateInputRow {
  @ObjectLink store: JulianDateStore
  @Prop label: string
  @Prop scaleKey: string
  @Prop textColor: string
  @Prop subColor: string
  @Prop inputColor: string
  onAdjust: (scale: string, direction: number) => void = () => {}
  onApply: (scale: string) => void = () => {}

  build() {
    Row({ space: 7 }) {
      Text(this.label).fontSize(10).fontColor(this.subColor).width(72).maxLines(1)
      Button() {
        Text('-').fontSize(17).fontColor('#C9DDEA').textAlign(TextAlign.Center).width('100%')
      }
        .width(28).height(30).padding(0).backgroundColor('rgba(91, 147, 191, 0.16)').borderRadius(UI_RADIUS_CONTROL)
        .onClick(() => { this.onAdjust(this.scaleKey, -1) })
      TextInput({ text: this.scaleKey === 'mjd' ? this.store.modifiedJulianDayInput : this.store.julianDayInput, placeholder: '0.00000' })
        .layoutWeight(1).height(30).fontSize(12).fontColor(this.textColor).placeholderColor(this.subColor)
        .backgroundColor(this.inputColor).border({ width: 1, color: 'rgba(214, 238, 255, 0.14)' }).borderRadius(UI_RADIUS_CONTROL)
        .onFocus(() => { this.store.julianDateEditing = true; this.store.julianDateError = '' })
        .onChange((next: string) => {
          if (this.scaleKey === 'mjd') this.store.modifiedJulianDayInput = next
          else this.store.julianDayInput = next
        })
        .onSubmit(() => { this.onApply(this.scaleKey) })
        .onBlur(() => { this.onApply(this.scaleKey) })
      Button() {
        Text('+').fontSize(17).fontColor('#C9DDEA').textAlign(TextAlign.Center).width('100%')
      }
        .width(28).height(30).padding(0).backgroundColor('rgba(91, 147, 191, 0.16)').borderRadius(UI_RADIUS_CONTROL)
        .onClick(() => { this.onAdjust(this.scaleKey, 1) })
    }.width('100%')
  }
}
