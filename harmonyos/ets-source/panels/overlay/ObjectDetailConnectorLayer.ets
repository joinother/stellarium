import { curves } from '@kit.ArkUI'
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 「天体详情指向线」叠层。
//
// 选中目标的精密单层准星已由 C++ 原生渲染层逐帧锁星绘制（零拖影、无双圈叠影），
// 本叠层仅在详情大卡展开态绘制一条极细 1vp 留白引线指向准星外缘；目标移出屏幕时
// 在屏幕边缘保留一枚 8vp 轻指示点。
@Component
export struct ObjectDetailConnectorLayer {
  @Prop visible: boolean
  @Prop beamLength: number
  @Prop beamX: number
  @Prop beamY: number
  @Prop beamAngle: number
  @Prop animateGeometry: boolean
  @Prop targetOnScreen: boolean
  @Prop targetX: number
  @Prop targetY: number
  @Prop endX: number
  @Prop endY: number
  @Prop markerSize: number
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Stack() {
      if (this.visible && this.beamLength > 0) {
        Row()
          .width(this.beamLength)
          .height(1)
          .backgroundColor(this.c.accent)
          .opacity(0.65)
          .borderRadius(0.5)
          .position({ x: this.beamX - this.beamLength / 2, y: this.beamY - 0.5 })
          .rotate({ angle: this.beamAngle })
          .animation({ duration: this.animateGeometry ? 180 : 0, curve: curves.springMotion(0.42, 0.86) })
          .hitTestBehavior(HitTestMode.None)
          .zIndex(20)
        if (!this.targetOnScreen) {
          Circle()
            .width(8).height(8)
            .fill(this.c.softStrong)
            .stroke(this.c.accent).strokeWidth(1)
            .position({ x: this.endX - 4, y: this.endY - 4 })
            .animation({ duration: this.animateGeometry ? 180 : 0, curve: curves.springMotion(0.42, 0.86) })
            .hitTestBehavior(HitTestMode.None)
            .zIndex(20)
        }
      }
    }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .zIndex(20)
  }
}
