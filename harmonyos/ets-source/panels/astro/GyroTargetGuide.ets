import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'
import { GyroStore } from '../../state/GyroStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 陀螺仪目标指引箭头。
// 只读 gyroStore.gyroGuideAngle：宿主随传感器事件写 store，组件以 @ObjectLink 实时跟转。
@Component
export struct GyroTargetGuide {
  @ObjectLink store: GyroStore
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Stack() {
      Text('↑')
        .fontSize(29)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.fourth)
        .rotate({ angle: this.store.gyroGuideAngle + 90 })
        .animation({ duration: 130, curve: Curve.Linear })
    }
      .width(44)
      .height(44)
      .alignContent(Alignment.Center)
      .backgroundColor(this.c.overlayPanel)
      .backdropBlur(22)
      .border({ width: 1, color: this.c.chipActiveBorder })
      .borderRadius(UI_RADIUS_PANEL)
      .clip(true)
      .shadow({ radius: 14, color: this.c.shadowSoft, offsetX: 0, offsetY: 4 })
  }
}
