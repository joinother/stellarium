import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 「目镜（Oculars）」面板的单个结果指标。
//
// 以 @Prop 驱动数值，换目镜/CCD 后放大率、视场、出瞳等结果数字实时刷新。
//
// 视觉：标签 10 号 subColor、值 14 号 Medium textColor、纵向 2 间距、左对齐、layoutWeight(1)。
@Component
export struct OcularMetric {
  @Prop label: string
  @Prop value: string
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 2 }) {
      Text(this.label).fontSize(10).fontColor(this.c.sub).maxLines(1)
      Text(this.value).fontSize(14).fontColor(this.c.text).fontWeight(FontWeight.Medium).maxLines(1)
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }
}
