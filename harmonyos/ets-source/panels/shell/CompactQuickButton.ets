import { getIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'

// 手机端右上快捷区的单个圆形按钮。
//
// 图标名、激活态、按下态、文字色由宿主以 @Prop 传入；点按语义（receiveTap 门控 +
// action）在组件内保留，动作本体由宿主回注。

@Component
export struct CompactQuickButton {
  @Prop iconName: string
  @Prop active: boolean
  @Prop receiveTap: boolean
  @Prop pressedState: boolean
  @Prop textColor: string
  onAction: () => void = () => {}

  build() {
    Row() {
      Image(getIcon(this.iconName, this.active))
        .width(22)
        .height(22)
        .fillColor(this.active ? '#FFFFFF' : this.textColor)
    }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.pressedState ? 'rgba(169, 232, 255, 0.24)' : (this.active ? 'rgba(91, 147, 191, 0.60)' : 'rgba(18, 22, 36, 0.50)'))
      .backdropBlur(this.active ? 28 : 36)
      .border({ width: 1, color: this.active ? 'rgba(107, 163, 214, 0.42)' : 'rgba(255, 255, 255, 0.10)' })
      .borderRadius(UI_RADIUS_PANEL)
      .shadow({ radius: 18, color: 'rgba(0,0,0,0.30)', offsetX: 0, offsetY: 8 })
      .scale({ x: this.pressedState ? 0.90 : (this.active ? 1.05 : 1.0), y: this.pressedState ? 0.90 : (this.active ? 1.05 : 1.0) })
      .animation({ duration: this.pressedState ? 70 : 180, curve: Curve.EaseOut })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        // 手机端右上快捷区在 Qt 之上另有一层触摸目标；同一次点按处理两次会立即翻回原状态。
        if (this.receiveTap) { this.onAction() }
      })
  }
}
