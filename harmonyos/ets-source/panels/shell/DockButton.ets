import { curves, Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { DockStore } from '../../state/DockStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 底部 Dock 的单个入口按钮。
//
// 展开/紧凑两档只影响图标尺寸、标签字号与行高，宿主算好后以 ``@Prop`` 传入；
// 触摸与点按经回调回注宿主。
//
// 激活态经 @ObjectLink 共享 ``DockStore`` 就地求值：ForEach 复用子项时 @Prop 会被
// 冻结，而改变键值又会重建入口，故都不能用于高亮（详见 ``BottomDock`` 头注）。
@Component
export struct DockButton {
  @Prop icon: string
  @Prop label: ResourceStr
  @Prop panelId: string
  @ObjectLink activeState: DockStore
  @Prop iconSize: number
  @Prop labelFontSize: number
  @Prop itemHeight: number
  @State c: ThemeSlots = DEFAULT_SLOTS
  onTouchEvent: (event: TouchEvent) => void = () => {}
  onTap: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private isActive(): boolean {
    return this.activeState.panelVisible && this.activeState.activePanel === this.panelId
  }

  build() {
    Column() {
      Image(getIcon(this.icon, this.isActive()))
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .supportSvg2(true)
        .colorFilter(tintMatrixFor(this.isActive() ? this.c.dockActive : this.c.idleIcon))
      Text(this.label)
        .fontSize(this.labelFontSize)
        .fontColor(this.isActive() ? this.c.dockActive : this.c.idleIcon)
        .margin({ top: 2 })
    }
      .layoutWeight(1)
      .height(this.itemHeight)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Color.Transparent)
      .borderRadius(UI_RADIUS_CONTROL)
      .scale({ x: 1.0, y: 1.0 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onTouch((event: TouchEvent) => { this.onTouchEvent(event) })
      .stateStyles({
        pressed: {
          .scale({ x: 0.97, y: 0.97 })
          .backgroundColor(this.c.overlayButton)
        }
      })
      .animation({ duration: 300, curve: curves.springMotion(0.46, 0.86) })
      .onClick(() => { this.onTap() })
  }
}
