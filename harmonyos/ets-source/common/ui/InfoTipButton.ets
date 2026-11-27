import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_MOTION_FAST_MS, UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_PILL } from './UiTokens'
import { panelFontSize } from './UiTypography'

// Unified HarmonyOS "ⓘ" contextual help trigger.
// Keeps panels clean and scannable by moving long explanatory paragraphs out of
// inline rows into a native bindPopup bubble anchored to a compact info-circle icon.
// NOTE: Uses BlurStyle.NONE + explicit app-themed popupColor so system light mode
// never paints a white blur plate behind light star-map text (matching ObservationAidBlock).
@Component
export struct InfoTipButton {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @Prop title: ResourceStr = ''
  @Prop tip: ResourceStr = ''
  @Prop iconSize: number = 15
  @State private open: boolean = false
  @State private hovered: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  private pinned: boolean = false
  private triggerHover: boolean = false
  private popupHover: boolean = false
  private openTimer: number = -1
  private closeTimer: number = -1

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToDisappear(): void {
    this.clearTimers()
  }

  private clearTimers(): void {
    if (this.openTimer >= 0) {
      clearTimeout(this.openTimer)
      this.openTimer = -1
    }
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer)
      this.closeTimer = -1
    }
  }

  private scheduleHoverOpen(): void {
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer)
      this.closeTimer = -1
    }
    if (this.open || this.openTimer >= 0) return
    this.openTimer = setTimeout(() => {
      this.openTimer = -1
      if (this.triggerHover && !this.open) {
        this.pinned = false
        this.open = true
      }
    }, 180) as number
  }

  private scheduleHoverClose(delayMs: number): void {
    if (this.openTimer >= 0) {
      clearTimeout(this.openTimer)
      this.openTimer = -1
    }
    if (!this.open || this.pinned) return
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer)
    }
    this.closeTimer = setTimeout(() => {
      this.closeTimer = -1
      if (!this.triggerHover && !this.popupHover && !this.pinned) {
        this.open = false
      }
    }, delayMs) as number
  }

  private hasTitle(): boolean {
    if (typeof this.title === 'string') return this.title.trim().length > 0
    return true
  }

  private popupBg(): ResourceColor {
    return this.c.isNight ? '#F6220908' : '#F6132234'
  }

  @Builder
  private popupContent() {
    Column({ space: 6 }) {
      if (this.hasTitle()) {
        Text(this.title)
          .fontSize(Math.round(panelFontSize(13, this.readableUi) * this.uiFontScale))
          .maxFontScale(1.3)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textStrong)
          .width('100%')
      }
      Text(this.tip)
        .fontSize(Math.round(panelFontSize(12, this.readableUi) * this.uiFontScale))
        .maxFontScale(1.3)
        .lineHeight(Math.round(panelFontSize(19, this.readableUi) * this.uiFontScale))
        .fontColor(this.c.text)
        .width('100%')
    }
    .width(256)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .border({ width: 1, color: this.c.border })
    .borderRadius(UI_RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
    .onHover((isHover: boolean) => {
      this.popupHover = isHover
      if (isHover) {
        if (this.closeTimer >= 0) {
          clearTimeout(this.closeTimer)
          this.closeTimer = -1
        }
      } else {
        this.scheduleHoverClose(160)
      }
    })
  }

  build() {
    Row() {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(this.iconSize)
        .fontColor([this.open || this.hovered ? this.c.accent : this.c.sub])
        .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(UI_RADIUS_PILL)
    .backgroundColor(this.open ? this.c.softStrong : (this.hovered ? this.c.soft : Color.Transparent))
    .hoverEffect(HoverEffect.Highlight)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .accessibilityText(typeof this.title === 'string' && this.title.trim().length > 0 ? this.title : '说明')
    .onHover((isHover: boolean) => {
      this.triggerHover = isHover
      this.hovered = isHover
      if (isHover) {
        this.scheduleHoverOpen()
      } else {
        this.scheduleHoverClose(200)
      }
    })
    .onClick(() => {
      this.clearTimers()
      if (!this.open) {
        this.pinned = true
        this.open = true
      } else if (!this.pinned) {
        // Clicking a hover-opened tip pins it open until clicked again or dismissed outside.
        this.pinned = true
      } else {
        this.pinned = false
        this.open = false
      }
    })
    .bindPopup(this.open, {
      builder: this.popupContent,
      width: 256,
      placement: Placement.Top,
      enableArrow: true,
      autoCancel: true,
      mask: false,
      radius: UI_RADIUS_CARD,
      popupColor: this.popupBg(),
      backgroundBlurStyle: BlurStyle.NONE,
      transition: TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
          .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }).animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })),
        TransitionEffect.OPACITY.animation({ duration: UI_MOTION_FAST_MS, curve: Curve.EaseIn })
      ),
      onStateChange: (event) => {
        if (!event.isVisible) {
          this.open = false
          this.pinned = false
          this.popupHover = false
        }
      }
    })
  }
}
