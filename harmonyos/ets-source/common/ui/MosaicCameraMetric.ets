import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 镶嵌相机角度指标（赤经 / 赤纬 / 旋转）：标签 + 角度读数。
@Component
export struct MosaicCameraMetric {
  @Prop labelKey: string
  @Prop value: number
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 4 }) {
      Text(I18n.t(this.labelKey)).fontSize(11).fontColor(this.c.sub)
      Text(this.value.toFixed(2) + '°').fontSize(14).fontColor(this.c.text)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }
}
