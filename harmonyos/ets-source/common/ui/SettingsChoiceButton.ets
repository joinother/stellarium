import { UI_RADIUS_CONTROL, UI_OPTION_ANIMATION_MS } from './UiTokens'
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 设置项选择按钮（原来的参数化 @Builder settingsChoiceButton 的替代）。
//
// 之所以改成组件：参数化 @Builder 的简单类型参数按值捕获，其子树首帧后冻结，
// 选中态（active）不会随设置变化刷新，必须重开面板才更新（真机实测确认）。
// 这里由调用方传入 `active`，组件经 @Prop 实时刷新。
@Component
export struct SettingsChoiceButton {
  @Prop label: ResourceStr
  @Prop active: boolean
  @Prop canPick: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onPick: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Text(this.label).fontSize(12).fontColor(this.active ? this.c.onAccent : this.c.sub)
    }
      .backgroundColor(this.active ? this.c.accent : this.c.bg)
      .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
      .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: 40, maxWidth: '100%' })
      .padding({ left: 12, right: 12, top: 10, bottom: 10 }).margin({ right: 6, bottom: 6 })
      .enabled(this.canPick)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onPick() })
  }
}
