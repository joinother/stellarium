import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 交互式导览的底部动作键。
//
// 可用性完全由导览阶段/步序与动作名推导，因此以 @Prop phase/index/action 传入；
// 按钮禁用态随 guideState 实时刷新。
// id 前缀固定为 `guide-`。
@Component
export struct GuideButton {
  @Prop label: string
  @Prop action: string
  @Prop phase: string
  @Prop index: number
  @State c: ThemeSlots = DEFAULT_SLOTS
  onAction: (action: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Button(I18n.t(this.label), { type: ButtonType.Normal })
        .id('guide-' + this.action).fontSize(14).fontColor(this.action === 'next' || this.action === 'return' ? this.c.onAccent : this.c.fourth)
      .backgroundColor(this.action === 'next' || this.action === 'return' ? this.c.accent : this.c.bg)
      .borderRadius(UI_RADIUS_CONTROL).height(48).layoutWeight(1)
      .enabled(this.phase !== 'preparing' && this.phase !== 'restoring' &&
        (this.action !== 'previous' || this.index > 0) &&
        (this.action !== 'explore' || this.phase === 'observing'))
      .stateEffect(true).onClick(() => { this.onAction(this.action) })
  }
}
