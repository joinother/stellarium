import { Theme } from '@kit.ArkUI'
import { getIcon } from '../../common/ui/ShellIcons'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { UI_MOTION_FAST_MS, UI_OPTION_ANIMATION_MS, UI_RADIUS_PANEL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
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
  @Prop tooltip: string = ''
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private hovered: boolean = false
  @State private tipOpen: boolean = false
  private hoverTimer: number = -1
  private touchTipTimer: number = -1
  onAction: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToDisappear(): void {
    this.clearTimers()
  }

  private clearTimers(): void {
    if (this.hoverTimer >= 0) {
      clearTimeout(this.hoverTimer)
      this.hoverTimer = -1
    }
    if (this.touchTipTimer >= 0) {
      clearTimeout(this.touchTipTimer)
      this.touchTipTimer = -1
    }
  }

  private popupBg(): ResourceColor {
    return this.c.isNight ? '#F4220908' : '#F4132234'
  }

  @Builder
  private tooltipContent() {
    Row({ space: 6 }) {
      Text(this.tooltip)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textStrong)
        .maxLines(1)
      Text(this.active ? '已开' : '已关')
        .fontSize(11)
        .fontColor(this.active ? this.c.accent : this.c.sub)
        .maxLines(1)
    }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PILL)
      .alignItems(VerticalAlign.Center)
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
      .border({ width: 1, color: this.active ? this.c.chipActiveBorder : (this.hovered ? this.c.border : this.c.chipInactiveBorder) })
      .borderRadius(UI_RADIUS_PANEL)
      .shadow({ radius: 18, color: this.c.shadowSoft, offsetX: 0, offsetY: 8 })
      .scale({ x: this.pressedState ? 0.90 : (this.active ? 1.05 : 1.0), y: this.pressedState ? 0.90 : (this.active ? 1.05 : 1.0) })
      .animation({ duration: this.pressedState ? 70 : 180, curve: Curve.EaseOut })
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .stateStyles({
        pressed: {
          .scale({ x: 0.90, y: 0.90 })
        }
      })
      .accessibilityText(this.tooltip)
      .onHover((isHover: boolean) => {
        this.hovered = isHover
        this.clearTimers()
        if (isHover && this.tooltip.length > 0) {
          this.hoverTimer = setTimeout(() => {
            this.hoverTimer = -1
            if (this.hovered) this.tipOpen = true
          }, 260) as number
        } else {
          this.tipOpen = false
        }
      })
      .gesture(LongPressGesture({ repeat: false, duration: 480 }).onAction(() => {
        if (this.tooltip.length === 0) return
        this.clearTimers()
        this.tipOpen = true
        this.touchTipTimer = setTimeout(() => {
          this.touchTipTimer = -1
          if (!this.hovered) this.tipOpen = false
        }, 1800) as number
      }))
      .bindPopup(this.tipOpen && this.tooltip.length > 0, {
        builder: this.tooltipContent,
        placement: Placement.Left,
        enableArrow: true,
        autoCancel: true,
        mask: false,
        radius: UI_RADIUS_PILL,
        popupColor: this.popupBg(),
        backgroundBlurStyle: BlurStyle.NONE,
        transition: TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }),
          TransitionEffect.OPACITY.animation({ duration: UI_MOTION_FAST_MS, curve: Curve.EaseIn })
        ),
        onStateChange: (event) => {
          if (!event.isVisible && this.tipOpen) {
            this.tipOpen = false
          }
        }
      })
      .onClick(() => {
        this.clearTimers()
        this.tipOpen = false
        // 手机端右上快捷区在 Qt 之上另有一层触摸目标；同一次点按处理两次会立即翻回原状态。
        if (this.receiveTap) { this.onAction() }
      })
  }
}
