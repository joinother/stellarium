import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 脚本回放的功能键。
// 宽度随脚本控制条尺寸变化，因此以 @Prop 传入。
@Component
export struct ScriptKeyButton {
  @Prop label: string
  @Prop keyName: string
  @Prop btnWidth: number
  @Prop isEnabled: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onKey: (key: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Button(this.label)
      .fontSize(11)
      .fontColor(this.c.text)
      .backgroundColor(this.c.overlayButton)
      .borderRadius(UI_RADIUS_CONTROL)
      .height(34)
      .width(this.btnWidth)
      .enabled(this.isEnabled)
      .stateEffect(true)
      .onClick(() => { this.onKey(this.keyName) })
  }
}
