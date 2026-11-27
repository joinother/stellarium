import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { panelFontSize, uiControlHeight } from '../../common/ui/UiTypography'
import { UI_MOTION_FAST_MS, UI_OPTION_ANIMATION_MS, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiSpringSnappy } from '../../common/ui/UiMotion'
import { getIcon } from '../../common/ui/ShellIcons'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 面板头部 chrome：返回按钮 + 标题/副标题 + 关闭按钮。
//
// 标题与副标题文本、返回可用性、路由过渡的透明度/位移都由宿主算好后传入；
// 返回与关闭动作以回调注入。
// 长按/点按后的实时刷新仍由宿主状态驱动（``panelTitle()`` 会随 ``observationTimeText`` /
// ``timeStore.timeRateText`` 变化重新求值，再经 ``@Prop`` 刷新本组件）。
// 可选的标题栏动作按钮由 ``headerActionLabel`` 驱动（空串即不渲染），目前供「图层」面板
// 放置「清除坐标与标记」；动作用 ``onHeaderAction`` 注入。
// ``panel-back`` / ``panel-close`` / ``panel-header-action`` 为跨会话静态 id 锚点。

// ``titleAsButton`` 为真时标题本身渲染为按钮（快捷操作面板用它显示当前位置并跳「位置」面板），
// 动作经 ``onTitleTap`` 注入。
// ``panel-back`` / ``panel-close`` / ``panel-header-action`` / ``panel-title-action`` 为跨会话静态 id 锚点。

@Component
export struct PanelHeader {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @Prop title: ResourceStr
  @Prop subtitle: string
  @Prop canGoBack: boolean
  @Prop routeOpacity: number
  @Prop routeOffsetX: number
  @Prop headerActionLabel: string = ''
  // 非空时动作按钮渲染为图标（走 getIcon 名称注册表），此时 ``headerActionLabel`` 只作无障碍文案。
  // 快捷操作面板要求「自定义=铅笔 / 完成=勾」不出现文字；图层面板仍用文字。
  @Prop headerActionIcon: string = ''
  // Accent styling for primary actions (the location panel's Auto-locate).
  @Prop headerActionAccent: boolean = false
  // 标题栏动作加载态（如「自动定位」进行中展示原生鸿蒙 LoadingProgress）。
  @Prop headerActionLoading: boolean = false
  @Prop titleAsButton: boolean = false
  @Prop compactMargin: boolean = false
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private hoveredBack: boolean = false
  @State private hoveredAction: boolean = false
  @State private hoveredClose: boolean = false
  @State private tipBackOpen: boolean = false
  @State private tipActionOpen: boolean = false
  @State private tipCloseOpen: boolean = false
  private hoverBackTimer: number = -1
  private hoverActionTimer: number = -1
  private hoverCloseTimer: number = -1
  onBack: () => void = () => {}
  onClose: () => void = () => {}
  onHeaderAction: () => void = () => {}
  onTitleTap: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToDisappear(): void {
    this.clearBackTimer()
    this.clearActionTimer()
    this.clearCloseTimer()
  }

  private clearBackTimer(): void {
    if (this.hoverBackTimer >= 0) {
      clearTimeout(this.hoverBackTimer)
      this.hoverBackTimer = -1
    }
  }

  private clearActionTimer(): void {
    if (this.hoverActionTimer >= 0) {
      clearTimeout(this.hoverActionTimer)
      this.hoverActionTimer = -1
    }
  }

  private clearCloseTimer(): void {
    if (this.hoverCloseTimer >= 0) {
      clearTimeout(this.hoverCloseTimer)
      this.hoverCloseTimer = -1
    }
  }

  private popupBg(): ResourceColor {
    return this.c.isNight ? '#F4220908' : '#F4132234'
  }

  @Builder
  private backTipContent() {
    Row({ space: 6 }) {
      Text('返回')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textStrong)
        .maxLines(1)
    }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PILL)
      .alignItems(VerticalAlign.Center)
  }

  @Builder
  private actionTipContent() {
    Row({ space: 6 }) {
      Text(this.headerActionLabel)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textStrong)
        .maxLines(1)
    }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PILL)
      .alignItems(VerticalAlign.Center)
  }

  @Builder
  private closeTipContent() {
    Row({ space: 6 }) {
      Text('关闭')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textStrong)
        .maxLines(1)
      Text('Esc')
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

  build() {
    Row() {
      if (this.canGoBack) {
        Button() {
          Image(getIcon('back', false)).width(17).height(17).supportSvg2(true).colorFilter(tintMatrixFor(this.c.textStrong))
        }
          .id('panel-back')
          .width(44)
          .height(44)
          .padding(0)
          .borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.hoveredBack ? this.c.overlayButton : Color.Transparent)
          .hoverEffect(HoverEffect.Highlight)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .accessibilityText('返回')
          .zIndex(3)
          .stateStyles({ pressed: { .opacity(0.62) } })
          .onHover((isHover: boolean) => {
            this.hoveredBack = isHover
            this.clearBackTimer()
            if (isHover) {
              this.hoverBackTimer = setTimeout(() => {
                this.hoverBackTimer = -1
                if (this.hoveredBack) this.tipBackOpen = true
              }, 260) as number
            } else {
              this.tipBackOpen = false
            }
          })
          .bindPopup(this.tipBackOpen, {
            builder: this.backTipContent,
            placement: Placement.Bottom,
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
              if (!event.isVisible && this.tipBackOpen) {
                this.tipBackOpen = false
              }
            }
          })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: UI_MOTION_FAST_MS, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: -10, y: 0 }).animation({ curve: uiSpringSnappy() })),
            TransitionEffect.OPACITY.animation({ duration: 100, curve: Curve.EaseIn })
          ))
          .onClick(() => {
            this.clearBackTimer()
            this.tipBackOpen = false
            this.onBack()
          })
          .margin({ right: 8 })
      }
      Column() {
        if (this.titleAsButton) {
          Button() {
            Row({ space: 4 }) {
              Text(this.title)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c.text)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Image(getIcon('chevron_right', false))
                .width(15)
                .height(15)
                .supportSvg2(true)
                .colorFilter(tintMatrixFor(this.c.sub))
            }
              .alignItems(VerticalAlign.Center)
          }
            .id('panel-title-action')
            .height(32)
            .padding({ left: 12, right: 8 })
            .backgroundColor(this.c.input)
            .borderRadius(UI_RADIUS_PILL)
            .zIndex(3)
            .hoverEffect(HoverEffect.Highlight)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .stateStyles({ pressed: { .opacity(0.62) } })
            .onClick(() => { this.onTitleTap() })
        } else {
          Text(this.title)
            .fontSize(panelFontSize(18, this.readableUi))
            .maxFontScale(1.35)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(Math.round(13 * this.uiFontScale))
            .maxFontScale(1.3)
            .fontColor(this.c.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
      }
        .constraintSize({ minHeight: uiControlHeight(this.subtitle.length > 0 ? 54 : 44, this.readableUi, this.controlScale) })
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .opacity(this.routeOpacity)
        .translate({ x: this.routeOffsetX, y: 0 })
      if (this.headerActionLabel.length > 0) {
        // 单一 Button + 条件子节点：``panel-header-action`` 锚点只出现一次（契约按出现次数校验）。
        Button() {
          if (this.headerActionLoading) {
            Row({ space: 6 }) {
              LoadingProgress()
                .width(15)
                .height(15)
                .color(this.headerActionAccent ? this.c.onAccent : this.c.accent)
              Text(I18n.t('m_locating_short'))
                .fontSize(Math.round(12 * this.uiFontScale))
                .maxFontScale(1.25)
                .maxLines(1)
                .fontColor(this.headerActionAccent ? this.c.onAccent : this.c.text)
            }
            .alignItems(VerticalAlign.Center)
          } else if (this.headerActionIcon.length > 0) {
            // 图标态与右侧关闭按钮同尺寸（36×36 / 18px 图标），两个圆形按钮视觉齐平。
            Image(getIcon(this.headerActionIcon, false)).width(18).height(18).supportSvg2(true)
              .colorFilter(tintMatrixFor(this.headerActionAccent ? this.c.onAccent : this.c.text))
          } else {
            Text(this.headerActionLabel)
              .fontSize(Math.round(12 * this.uiFontScale))
              .maxFontScale(1.25)
              .maxLines(1)
              .fontColor(this.headerActionAccent ? this.c.onAccent : this.c.text)
          }
        }
          .id('panel-header-action')
          .constraintSize({ minWidth: 36, minHeight: uiControlHeight(36, this.readableUi, this.controlScale) })
          .padding(this.headerActionIcon.length > 0 && !this.headerActionLoading ? 0 : { left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.headerActionAccent ? this.c.accent : (this.hoveredAction ? this.c.overlayButton : this.c.input))
          .border({ width: 1, color: this.hoveredAction && !this.headerActionAccent ? this.c.border : Color.Transparent })
          .borderRadius(UI_RADIUS_PILL).zIndex(10)
          .hoverEffect(HoverEffect.Highlight)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .accessibilityText(this.headerActionLabel)
          .stateStyles({ pressed: { .opacity(0.62) } })
          .onHover((isHover: boolean) => {
            this.hoveredAction = isHover
            this.clearActionTimer()
            if (isHover && this.headerActionIcon.length > 0 && !this.headerActionLoading) {
              this.hoverActionTimer = setTimeout(() => {
                this.hoverActionTimer = -1
                if (this.hoveredAction && this.headerActionIcon.length > 0 && !this.headerActionLoading) {
                  this.tipActionOpen = true
                }
              }, 260) as number
            } else {
              this.tipActionOpen = false
            }
          })
          .bindPopup(this.tipActionOpen && this.headerActionIcon.length > 0 && !this.headerActionLoading, {
            builder: this.actionTipContent,
            placement: Placement.Bottom,
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
              if (!event.isVisible && this.tipActionOpen) {
                this.tipActionOpen = false
              }
            }
          })
          .onClick(() => {
            this.clearActionTimer()
            this.tipActionOpen = false
            if (!this.headerActionLoading) this.onHeaderAction()
          })
          .margin({ left: 8, right: 8 })
      }
      Button() {
        Image($r('app.media.ic_close')).width(18).height(18).supportSvg2(true).colorFilter(tintMatrixFor(this.c.text))
      }
      .id('panel-close')
      .width(36)
      .height(36)
      .padding(0)
      .borderRadius(UI_RADIUS_PILL)
      .backgroundColor(this.hoveredClose ? this.c.overlayButton : this.c.input)
      .border({ width: 1, color: this.hoveredClose ? this.c.border : Color.Transparent })
      .zIndex(10)
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .accessibilityText('关闭')
      .onHover((isHover: boolean) => {
        this.hoveredClose = isHover
        this.clearCloseTimer()
        if (isHover) {
          this.hoverCloseTimer = setTimeout(() => {
            this.hoverCloseTimer = -1
            if (this.hoveredClose) this.tipCloseOpen = true
          }, 260) as number
        } else {
          this.tipCloseOpen = false
        }
      })
      .bindPopup(this.tipCloseOpen, {
        builder: this.closeTipContent,
        placement: Placement.Bottom,
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
          if (!event.isVisible && this.tipCloseOpen) {
            this.tipCloseOpen = false
          }
        }
      })
      .onClick(() => {
        this.clearCloseTimer()
        this.tipCloseOpen = false
        this.onClose()
      })
      .margin({ left: this.headerActionLabel.length > 0 ? 0 : 8, right: 2 })
    }
      .width('100%')
      .constraintSize({ minHeight: uiControlHeight(this.subtitle.length > 0 ? 54 : 44, this.readableUi, this.controlScale) })
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: this.compactMargin ? 0 : 12 })
      .zIndex(4)
      .animation({ curve: uiSpringSnappy() })
  }
}
