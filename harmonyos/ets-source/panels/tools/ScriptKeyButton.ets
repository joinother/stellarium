import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 脚本回放的功能键。
// 宽度随脚本控制条尺寸变化，因此以 @Prop 传入。
@Component
export struct ScriptKeyButton {
  @Prop label: string
  @Prop keyName: string
  @Prop btnWidth: number
  @Prop isEnabled: boolean
  onKey: (key: string) => void = () => {}

  build() {
    Button(this.label)
      .fontSize(11)
      .fontColor('#D9F1FF')
      .backgroundColor('rgba(255,255,255,0.10)')
      .borderRadius(UI_RADIUS_CONTROL)
      .height(34)
      .width(this.btnWidth)
      .enabled(this.isEnabled)
      .stateEffect(true)
      .onClick(() => { this.onKey(this.keyName) })
  }
}
