import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 本组件职责：「指针坐标」插件面板的开关行。
//
// `@Prop isOn` 承载开关态：若开关态用简单类型形参传入，会按值捕获、子树首帧后冻结，
// 插件回包刷新后开关不会跟着变；用 @Prop 即可实时刷新。
// 写回由 `onToggle` 回调交回宿主（宿主按 setting 名分派到 native 桥）。
@Component
export struct PointerCoordinateToggle {
  @Prop label: string
  @Prop isOn: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row() {
      Text(this.label).fontSize(12).fontColor(this.c.text).layoutWeight(1).maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .width(46).height(28)
        .onChange((value: boolean) => { this.onToggle(value) })
    }
      .width('100%').padding({ left: 10, right: 8, top: 7, bottom: 7 })
      .backgroundColor(this.isOn ? this.c.soft : this.c.bg)
      .border({ width: 1, color: this.isOn ? this.c.soft : this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .animation({ duration: 180, curve: Curve.EaseOut })
  }
}
