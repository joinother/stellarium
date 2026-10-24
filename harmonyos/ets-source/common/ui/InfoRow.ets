import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 详情/设置面板的「标签 : 值」两列行（原宿主参数化 `@Builder infoRow(label, value)`）。
//
// 纯展示：字号、尺寸内联，颜色经机制四从 ThemeSlots 取；不读宿主任何状态，故只收两个 @Prop。
// 迁移原因：参数化 @Builder 的简单类型参数按值捕获，其子树首帧后冻结；改组件后
// 标签/数值变化由 @Prop 驱动实时刷新（设置面板、历表、观测曲线、年鉴、今晚天象等共用本行）。
@Component
export struct InfoRow {
  @Prop label: ResourceStr
  @Prop value: ResourceStr
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(11)
        .fontColor(this.c.sub)
        .width(64)
        .textAlign(TextAlign.Start)
      Text(this.value)
        .fontSize(13)
        .fontColor(this.c.text)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
    }
      .height(24)
      .width('100%')
      .padding({ left: 8, right: 8 })
      .backgroundColor(Color.Transparent)
      .margin({ bottom: 2 })
  }
}
