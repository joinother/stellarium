import { OverlayStore } from '../../state/OverlayStore'
import { Theme } from '@kit.ArkUI'
import { ThemeSlots, DEFAULT_SLOTS, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'

// 「视图中心坐标」屏幕叠层。
//
// 分工（叠层实时字段不入被观察 store）：
//   - 设置类（坐标系档位）读 @ObjectLink store，标题与两个标签由 store 的纯查表方法给出；
//   - 逐帧读数 `viewCoordinatePrimaryText` / `viewCoordinateSecondaryText` 由宿主（50ms 定时器回填）
//     以 @Prop 传入；
//   - 标签列宽（平板 78 / 手机 68）由宿主按 `isExpandedLayout` 算出后传入；
//   - 拖拽回调 `handleViewCoordinateTouch` 由宿主以 `onHandleTouch` 注入（避开 `CustomComponent.onTouch`）。
//
// 叠层的宽/高/定位（viewCoordinateOverlayWidth / Left / Top）由宿主外层 Stack 负责，不在此组件内。
// 主题色走「机制四」：onWillApplyTheme 自取当前主题槽位，调用点不再注入颜色。
@Component
export struct ViewCenterCoordinateOverlay {
  @ObjectLink store: OverlayStore
  @Prop primaryText: string
  @Prop secondaryText: string
  @Prop labelWidth: number
  onHandleTouch: (event: TouchEvent) => void = (event: TouchEvent) => {}
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 4 }) {
      Text(this.store.viewCoordinateTitle())
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.text)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        Text(this.store.viewCoordinatePrimaryLabel())
          .fontSize(11)
          .fontColor(this.c.text)
          .width(this.labelWidth)
        Text(this.primaryText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textStrong)
          .fontFamily('monospace')
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%')
      Row() {
        Text(this.store.viewCoordinateSecondaryLabel())
          .fontSize(11)
          .fontColor(this.c.text)
          .width(this.labelWidth)
        Text(this.secondaryText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textStrong)
          .fontFamily('monospace')
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%')
    }
      .width('100%')
      .padding({ left: 13, right: 13, top: 9, bottom: 9 })
      .backgroundColor(this.c.overlayScrim)
      .backdropBlur(20)
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PANEL)
      .shadow({ radius: 16, color: this.c.shadowSoft, offsetX: 0, offsetY: 5 })
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent) => { this.onHandleTouch(event) })
  }
}
