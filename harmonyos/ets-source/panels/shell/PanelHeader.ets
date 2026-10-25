import { curves, Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'
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
  @Prop title: ResourceStr
  @Prop subtitle: string
  @Prop canGoBack: boolean
  @Prop routeOpacity: number
  @Prop routeOffsetX: number
  @Prop headerActionLabel: string = ''
  // 非空时动作按钮渲染为图标（走 getIcon 名称注册表），此时 ``headerActionLabel`` 只作无障碍文案。
  // 快捷操作面板要求「自定义=铅笔 / 完成=勾」不出现文字；图层面板仍用文字。
  @Prop headerActionIcon: string = ''
  @Prop titleAsButton: boolean = false
  @State c: ThemeSlots = DEFAULT_SLOTS
  onBack: () => void = () => {}
  onClose: () => void = () => {}
  onHeaderAction: () => void = () => {}
  onTitleTap: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
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
          .borderRadius(0)
          .backgroundColor(Color.Transparent)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .zIndex(3)
          .stateStyles({ pressed: { .opacity(0.62) } })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 130, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: -10, y: 0 }).animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })),
            TransitionEffect.OPACITY.animation({ duration: 100, curve: Curve.EaseIn })
          ))
          .onClick(() => { this.onBack() })
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
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .stateStyles({ pressed: { .opacity(0.62) } })
            .onClick(() => { this.onTitleTap() })
        } else {
          Text(this.title)
            .fontSize(panelFontSize(18, this.readableUi))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.text)
        }
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(14)
            .fontColor(this.c.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
      }
        .height(this.subtitle.length > 0 ? 56 : 44)
        .justifyContent(FlexAlign.Center)
        .opacity(this.routeOpacity)
        .translate({ x: this.routeOffsetX, y: 0 })
      Blank()
      if (this.headerActionLabel.length > 0) {
        // 单一 Button + 条件子节点：``panel-header-action`` 锚点只出现一次（契约按出现次数校验）。
        Button() {
          if (this.headerActionIcon.length > 0) {
            // 图标态与右侧关闭按钮同尺寸（36×36 / 18px 图标），两个圆形按钮视觉齐平。
            Image(getIcon(this.headerActionIcon, false)).width(18).height(18).supportSvg2(true).colorFilter(tintMatrixFor(this.c.text))
           } else {
             Text(this.headerActionLabel).fontSize(11).fontColor(this.c.text)
          }
        }
          .id('panel-header-action')
          .constraintSize({ minWidth: 36 })
          .height(36)
          .padding(this.headerActionIcon.length > 0 ? 0 : { left: 10, right: 10 })
          .backgroundColor(this.c.input)
          .borderRadius(UI_RADIUS_PILL)
          .zIndex(10)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .accessibilityText(this.headerActionLabel)
          .stateStyles({ pressed: { .opacity(0.62) } })
          .onClick(() => { this.onHeaderAction() })
          .margin({ right: 8 })
      }
      Button() {
        Image($r('app.media.ic_close'))
          .width(18)
          .height(18)
          .supportSvg2(true)
          .colorFilter(tintMatrixFor(this.c.text))
      }
      .id('panel-close')
      .width(36)
      .height(36)
      .padding(0)
      .borderRadius(UI_RADIUS_PILL)
      .backgroundColor(this.c.input)
      .zIndex(10)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onClose() })
      .margin({ right: 6 })
    }
      .width('100%')
      .height(this.subtitle.length > 0 ? 56 : 44)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 14 })
      .zIndex(4)
      .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
  }
}
