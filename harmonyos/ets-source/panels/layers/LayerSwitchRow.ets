import { curves, Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 本组件职责：「图层」面板的开关行。
//
// `@Prop isOn` 承载当前开关值，实时刷新行底色与边框色；
// onChange 的写回（setLayer / setBridgeFlag / setSkyDisplaySetting）与 flashHint 提示
// 经 onToggle 回调由宿主完成；与当前值相同的重复触发在此拦掉。
// 写回由 onToggle 回调交回宿主（宿主按 setting 名分派到 native 桥）；
@Component
export struct LayerSwitchRow {
  @Prop label: ResourceStr
  @Prop isOn: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor(this.c.text)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .width(46)
        .height(28)
        .selectedColor(this.c.accent)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onChange((value: boolean) => {
          if (value === this.isOn) return
          this.onToggle(value)
        })
    }
      .height(42)
      .width('100%')
      .padding({ left: 10, right: 8 })
      .backgroundColor(this.isOn ? this.c.soft : this.c.bg)
      .border({ width: 1, color: this.isOn ? this.c.soft : this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ bottom: 6 })
      .animation({ duration: 200, curve: curves.springMotion(0.45, 0.9) })
  }
}
