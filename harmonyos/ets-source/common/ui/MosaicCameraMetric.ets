import { I18n } from '../../pages/I18n'

// 镶嵌相机角度指标（赤经 / 赤纬 / 旋转）：标签 + 角度读数。
@Component
export struct MosaicCameraMetric {
  @Prop labelKey: string
  @Prop value: number
  @Prop subColor: string
  @Prop textColor: string

  build() {
    Column({ space: 4 }) {
      Text(I18n.t(this.labelKey)).fontSize(11).fontColor(this.subColor)
      Text(this.value.toFixed(2) + '°').fontSize(14).fontColor(this.textColor)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }
}
