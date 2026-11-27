import { Theme } from '@kit.ArkUI'
import { UI_MOTION_FAST_MS, UI_OPTION_ANIMATION_MS, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import {
  CHROME_ZOOM_EDGE_PADDING,
  chromeZoomLayerHeight,
  chromeZoomLayerTop
} from '../../common/ui/ChromeGeometry'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 面板/Dock 壳层的四个小组件。
//
// 都是无状态外观件：时钟文本、几何参数与拖拽回调由宿主以 @Prop / 回调解入。

// 主界面 Dock 右上常驻时钟（HH:mm）：点按直接打开时间面板；桌面端悬停滚轮可微调模拟时间（±10 分钟）。
@Component
export struct DockClockChip {
  @Prop clockText: string
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private hovered: boolean = false
  @State private tipOpen: boolean = false
  private hoverTimer: number = -1
  private lastScrubMs: number = 0
  onOpenTime: () => void = () => {}
  onScrubTime: (deltaMinutes: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToDisappear(): void {
    if (this.hoverTimer >= 0) {
      clearTimeout(this.hoverTimer)
      this.hoverTimer = -1
    }
  }

  private popupBg(): ResourceColor {
    return this.c.isNight ? '#F4220908' : '#F4132234'
  }

  @Builder
  private clockTipContent() {
    Row({ space: 6 }) {
      Text('时间与推演')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textStrong)
        .maxLines(1)
      Text('滚轮调时')
        .fontSize(10)
        .fontColor(this.c.sub)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        .backgroundColor(this.c.soft)
        .borderRadius(4)
        .maxLines(1)
    }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PILL)
      .alignItems(VerticalAlign.Center)
  }

  build() {
    Row() {
      Text(this.clockText)
        .fontSize(22)
        .fontColor(this.c.text)
    }
      .height(36)
      .padding({ left: 14, right: 14 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.c.bgStrong)
      .backdropBlur(20)
      .border({ width: 1, color: this.hovered ? this.c.border : Color.Transparent })
      .borderRadius(UI_RADIUS_PILL)
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onHover((isHover: boolean) => {
        this.hovered = isHover
        if (this.hoverTimer >= 0) {
          clearTimeout(this.hoverTimer)
          this.hoverTimer = -1
        }
        if (isHover) {
          this.hoverTimer = setTimeout(() => {
            this.hoverTimer = -1
            if (this.hovered) this.tipOpen = true
          }, 260) as number
        } else {
          this.tipOpen = false
        }
      })
      .onAxisEvent((event: AxisEvent) => {
        if (event.action !== AxisAction.BEGIN && event.action !== AxisAction.UPDATE) return
        const vertical = event.getVerticalAxisValue()
        if (!Number.isFinite(vertical) || Math.abs(vertical) < 0.001) return
        const now = Date.now()
        if (now - this.lastScrubMs < 45) return
        this.lastScrubMs = now
        this.tipOpen = false
        // 滚轮向上 = 前进 10 分钟，向下 = 回退 10 分钟。
        this.onScrubTime(vertical < 0 ? 10 : -10)
      })
      .bindPopup(this.tipOpen, {
        builder: this.clockTipContent,
        placement: Placement.Top,
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
        if (this.hoverTimer >= 0) {
          clearTimeout(this.hoverTimer)
          this.hoverTimer = -1
        }
        this.tipOpen = false
        this.onOpenTime()
      })
  }
}

// Dock 时钟定位层：右端与 dock 栏对齐；空白区触摸穿透回星图，仅时钟本体拦截点击与滚轮。
@Component
export struct DockClockLayer {
  @Prop clockText: string
  @Prop layerWidth: number
  @Prop posX: number
  @Prop posY: number
  @Prop chromeOpacity: number = 1.0
  onOpenTime: () => void = () => {}
  onScrubTime: (deltaMinutes: number) => void = () => {}

  build() {
    Row() {
      // 不能用 HitTestMode.Block：ArkUI 中 Block 会拦截子节点（吞掉 DockClockChip 的 onHover/onClick）。
      // Default 让时钟本体接管点击与悬停并自然阻断下方星图，外层 Transparent 放行空白区。
      Stack() { DockClockChip({ clockText: this.clockText, onOpenTime: this.onOpenTime, onScrubTime: this.onScrubTime }) }
    }
      .width(this.layerWidth)
      .height(36)
      .justifyContent(FlexAlign.End)
      .padding({ right: 4 })
      .position({ x: this.posX, y: this.posY })
      .opacity(this.chromeOpacity)
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(40)
  }
}

// Dock 上方的视场（FOV）读数胶囊：与常驻时钟同一行（posY = dockTop - 48）。
// 桌面端悬停浮现「视场角 · 滚轮微调」并支持直接滚轮精细缩放视场。
@Component
export struct DockFovChip {
  @Prop fovText: string
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private hovered: boolean = false
  @State private tipOpen: boolean = false
  private hoverTimer: number = -1
  private lastScrubMs: number = 0
  onScrubFov: (zoomIn: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToDisappear(): void {
    if (this.hoverTimer >= 0) {
      clearTimeout(this.hoverTimer)
      this.hoverTimer = -1
    }
  }

  private popupBg(): ResourceColor {
    return this.c.isNight ? '#F4220908' : '#F4132234'
  }

  @Builder
  private fovTipContent() {
    Row({ space: 6 }) {
      Text('视场角')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textStrong)
        .maxLines(1)
      Text('滚轮微调')
        .fontSize(10)
        .fontColor(this.c.sub)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        .backgroundColor(this.c.soft)
        .borderRadius(4)
        .maxLines(1)
    }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PILL)
      .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      Text('FOV')
        .fontSize(10)
        .height(12)
        .fontColor(this.c.sub)
      Text(this.fovText)
        .fontSize(16)
        .height(20)
        .fontColor(this.c.text)
    }
      .height(36)
      .padding({ left: 12, right: 12 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.c.bgStrong)
      .backdropBlur(20)
      .border({ width: 1, color: this.hovered ? this.c.border : Color.Transparent })
      .borderRadius(UI_RADIUS_PILL)
      .hoverEffect(HoverEffect.Highlight)
      .onHover((isHover: boolean) => {
        this.hovered = isHover
        if (this.hoverTimer >= 0) {
          clearTimeout(this.hoverTimer)
          this.hoverTimer = -1
        }
        if (isHover) {
          this.hoverTimer = setTimeout(() => {
            this.hoverTimer = -1
            if (this.hovered) this.tipOpen = true
          }, 260) as number
        } else {
          this.tipOpen = false
        }
      })
      .onAxisEvent((event: AxisEvent) => {
        if (event.action !== AxisAction.BEGIN && event.action !== AxisAction.UPDATE) return
        const vertical = event.getVerticalAxisValue()
        if (!Number.isFinite(vertical) || Math.abs(vertical) < 0.001) return
        const now = Date.now()
        if (now - this.lastScrubMs < 45) return
        this.lastScrubMs = now
        this.tipOpen = false
        this.onScrubFov(vertical < 0)
      })
      .bindPopup(this.tipOpen, {
        builder: this.fovTipContent,
        placement: Placement.Right,
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
  }
}

// Dock 视场显示定位层：与常驻时钟同一行，贴在左端；空白区透传回星图，胶囊本体响应悬停与滚轮微调。
@Component
export struct DockFovLayer {
  @Prop fovText: string
  @Prop layerWidth: number
  @Prop posX: number
  @Prop posY: number
  @Prop chromeOpacity: number = 1.0
  onScrubFov: (zoomIn: boolean) => void = () => {}

  build() {
    Row() {
      Stack() { DockFovChip({ fovText: this.fovText, onScrubFov: this.onScrubFov }) }
    }
      .width(this.layerWidth)
      .height(36)
      .justifyContent(FlexAlign.Start)
      .padding({ left: 4 })
      .position({ x: this.posX, y: this.posY })
      .opacity(this.chromeOpacity)
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(40)
  }
}

// 星图缩放按钮层：非手势缩放（直接走原生 zoomStep，与键盘快捷键同一命令族，factor<1 放大、>1 缩小）。
// 排列由形态决定：手机·半折竖排（44×2 + 8 间距 = 96 高），平板横排（一行 44 高 + 4 间隙）；
// 两种排列都紧贴读数行上沿 —— rowY 即读数行上沿，由宿主按形态给出，本组件自持几何，
// 避免 96/44/4 这些数字散落到两个壳里去重复。
// 空白区触摸穿透回星图，仅按钮本体拦截点击。视觉与 DockClockChip 同族。
@Component
export struct SkyZoomLayer {
  @Prop layerWidth: number
  @Prop posX: number
  @Prop rowY: number
  @Prop horizontal: boolean
  @Prop chromeOpacity: number = 1.0
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private hoveredIn: boolean = false
  @State private hoveredOut: boolean = false
  @State private tipInOpen: boolean = false
  @State private tipOutOpen: boolean = false
  private hoverInTimer: number = -1
  private hoverOutTimer: number = -1
  private touchInTimer: number = -1
  private touchOutTimer: number = -1
  onZoomIn: () => void = () => {}
  onZoomOut: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToDisappear(): void {
    this.clearInTimers()
    this.clearOutTimers()
  }

  private clearInTimers(): void {
    if (this.hoverInTimer >= 0) {
      clearTimeout(this.hoverInTimer)
      this.hoverInTimer = -1
    }
    if (this.touchInTimer >= 0) {
      clearTimeout(this.touchInTimer)
      this.touchInTimer = -1
    }
  }

  private clearOutTimers(): void {
    if (this.hoverOutTimer >= 0) {
      clearTimeout(this.hoverOutTimer)
      this.hoverOutTimer = -1
    }
    if (this.touchOutTimer >= 0) {
      clearTimeout(this.touchOutTimer)
      this.touchOutTimer = -1
    }
  }

  private popupBg(): ResourceColor {
    return this.c.isNight ? '#F4220908' : '#F4132234'
  }

  @Builder
  private zoomInTipContent() {
    Row({ space: 6 }) {
      Text('放大')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textStrong)
        .maxLines(1)
      Text('+')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.sub)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        .backgroundColor(this.c.soft)
        .borderRadius(4)
        .maxLines(1)
    }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PILL)
      .alignItems(VerticalAlign.Center)
  }

  @Builder
  private zoomOutTipContent() {
    Row({ space: 6 }) {
      Text('缩小')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textStrong)
        .maxLines(1)
      Text('−')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.sub)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        .backgroundColor(this.c.soft)
        .borderRadius(4)
        .maxLines(1)
    }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PILL)
      .alignItems(VerticalAlign.Center)
  }

  @Builder
  zoomButtonPair() {
    Stack({ alignContent: Alignment.Center }) {
      Text('+')
        .fontSize(24)
        .fontColor(this.c.text)
    }
      .width(44)
      .height(44)
      .backgroundColor(this.c.bgStrong)
      .backdropBlur(20)
      .border({ width: 1, color: this.hoveredIn ? this.c.border : Color.Transparent })
      .borderRadius(UI_RADIUS_PILL)
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .accessibilityText('放大')
      .onHover((isHover: boolean) => {
        this.hoveredIn = isHover
        this.clearInTimers()
        if (isHover) {
          this.hoverInTimer = setTimeout(() => {
            this.hoverInTimer = -1
            if (this.hoveredIn) this.tipInOpen = true
          }, 260) as number
        } else {
          this.tipInOpen = false
        }
      })
      .gesture(LongPressGesture({ repeat: false, duration: 480 }).onAction(() => {
        this.clearInTimers()
        this.tipInOpen = true
        this.touchInTimer = setTimeout(() => {
          this.touchInTimer = -1
          if (!this.hoveredIn) this.tipInOpen = false
        }, 1800) as number
      }))
      .bindPopup(this.tipInOpen, {
        builder: this.zoomInTipContent,
        placement: Placement.Top,
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
          if (!event.isVisible && this.tipInOpen) {
            this.tipInOpen = false
          }
        }
      })
      .onClick(() => {
        this.clearInTimers()
        this.tipInOpen = false
        this.onZoomIn()
      })
      .id('skyZoomInButton')
    Stack({ alignContent: Alignment.Center }) {
      Text('−')
        .fontSize(24)
        .fontColor(this.c.text)
    }
      .width(44)
      .height(44)
      .backgroundColor(this.c.bgStrong)
      .backdropBlur(20)
      .border({ width: 1, color: this.hoveredOut ? this.c.border : Color.Transparent })
      .borderRadius(UI_RADIUS_PILL)
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .accessibilityText('缩小')
      .onHover((isHover: boolean) => {
        this.hoveredOut = isHover
        this.clearOutTimers()
        if (isHover) {
          this.hoverOutTimer = setTimeout(() => {
            this.hoverOutTimer = -1
            if (this.hoveredOut) this.tipOutOpen = true
          }, 260) as number
        } else {
          this.tipOutOpen = false
        }
      })
      .gesture(LongPressGesture({ repeat: false, duration: 480 }).onAction(() => {
        this.clearOutTimers()
        this.tipOutOpen = true
        this.touchOutTimer = setTimeout(() => {
          this.touchOutTimer = -1
          if (!this.hoveredOut) this.tipOutOpen = false
        }, 1800) as number
      }))
      .bindPopup(this.tipOutOpen, {
        builder: this.zoomOutTipContent,
        placement: Placement.Top,
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
          if (!event.isVisible && this.tipOutOpen) {
            this.tipOutOpen = false
          }
        }
      })
      .onClick(() => {
        this.clearOutTimers()
        this.tipOutOpen = false
        this.onZoomOut()
      })
      .id('skyZoomOutButton')
  }

  build() {
    Row() {
      if (this.horizontal) {
        // 不用 HitTestMode.Block：Block 会阻断内部缩放按钮接收 onHover / LongPressGesture。
        Row({ space: 8 }) {
          this.zoomButtonPair()
        }
      } else {
        Column({ space: 8 }) {
          this.zoomButtonPair()
        }
      }
    }
      .width(this.layerWidth)
      .height(chromeZoomLayerHeight(this.horizontal))
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      .padding({ left: CHROME_ZOOM_EDGE_PADDING })
      .position({ x: this.posX, y: chromeZoomLayerTop(this.rowY, this.horizontal) })
      .opacity(this.chromeOpacity)
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(40)
  }
}

// 平板/折叠布局的面板抓手（纯装饰）。
@Component
export struct PadPanelHandle {
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row()
      .width(58)
      .height(5)
      .backgroundColor(this.c.dragHandle)
      .borderRadius(3)
      .alignSelf(ItemAlign.Center)
      .margin({ top: 2, bottom: 10 })
      .hitTestBehavior(HitTestMode.None)
  }
}

// 手机紧凑面板的抓手：垂直拖拽由宿主接管（更新/结算面板高度）。
@Component
export struct PanelHandle {
  @State c: ThemeSlots = DEFAULT_SLOTS
  onDrag: (offsetY: number) => void = () => {}
  onDragFinish: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(58)
        .height(5)
        .backgroundColor(this.c.dragHandle)
        .borderRadius(3)
    }
      .width('100%')
      .height(28)
      .alignSelf(ItemAlign.Center)
      .margin({ bottom: 2 })
      .gesture(
        PanGesture()
          .onActionUpdate((event: GestureEvent) => {
            this.onDrag(event.offsetY)
          })
          .onActionEnd(() => {
            this.onDragFinish()
          })
          .onActionCancel(() => {
            this.onDragFinish()
          })
      )
  }
}
