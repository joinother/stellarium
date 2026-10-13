import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'
import { GyroStore } from '../../state/GyroStore'

// 陀螺仪目标指引箭头。
// 只读 gyroStore.gyroGuideAngle：宿主随传感器事件写 store，组件以 @ObjectLink 实时跟转。
@Component
export struct GyroTargetGuide {
  @ObjectLink store: GyroStore

  build() {
    Stack() {
      Text('↑')
        .fontSize(29)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E5FAFF')
        .rotate({ angle: this.store.gyroGuideAngle + 90 })
        .animation({ duration: 130, curve: Curve.Linear })
    }
      .width(44)
      .height(44)
      .alignContent(Alignment.Center)
      .backgroundColor('rgba(8, 21, 36, 0.76)')
      .backdropBlur(22)
      .border({ width: 1, color: 'rgba(169, 232, 255, 0.72)' })
      .borderRadius(UI_RADIUS_PANEL)
      .clip(true)
      .shadow({ radius: 14, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: 4 })
  }
}
