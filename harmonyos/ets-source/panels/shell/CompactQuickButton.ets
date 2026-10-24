import { Theme } from '@kit.ArkUI'
import { getIcon } from '../../common/ui/ShellIcons'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 手机端右上快捷区的单个圆形按钮。
//
// 图标名、激活态、按下态由宿主以 @Prop 传入；点按语义（receiveTap 门控 +
// action）在组件内保留，动作本体由宿主回注。

@Component
export struct CompactQuickButton {
  @Prop iconName: string
  @Prop active: boolean
  @Prop receiveTap: boolean
  @Prop pressedState: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onAction: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row() {
      Image(getIcon(this.iconName, this.active))
        .width(22)
        .height(22)
        .supportSvg2(true)
        .colorFilter(tintMatrixFor(this.active ? this.c.dockActive : this.c.idleIcon))
    }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.pressedState ? this.c.chipActiveBg : (this.active ? this.c.chipActiveBg : this.c.bgStrong))
      .backdropBlur(this.active ? 28 : 36)
      .border({ width: 1, color: this.active ? this.c.chipActiveBorder : this.c.chipInactiveBorder })
      .borderRadius(UI_RADIUS_PANEL)
      .shadow({ radius: 18, color: this.c.shadowSoft, offsetX: 0, offsetY: 8 })
      .scale({ x: this.pressedState ? 0.90 : (this.active ? 1.05 : 1.0), y: this.pressedState ? 0.90 : (this.active ? 1.05 : 1.0) })
      .animation({ duration: this.pressedState ? 70 : 180, curve: Curve.EaseOut })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        // 手机端右上快捷区在 Qt 之上另有一层触摸目标；同一次点按处理两次会立即翻回原状态。
        if (this.receiveTap) { this.onAction() }
      })
  }
}
