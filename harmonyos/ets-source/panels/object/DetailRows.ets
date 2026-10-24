import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 天体详情行族的三个纯展示组件：数据行、结构化资料行与段落标题。
//
// 标签与数值以 `@Prop` 传入（带值参数按值捕获后不会随状态刷新，故由父方解析后传入）；
// 组件内不含解析逻辑。
@Component
export struct ObjectDataRow {
  @Prop label: string
  @Prop value: string
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row({ space: 10 }) {
      Text(this.label).fontSize(11).fontColor(this.c.tertiary).width(68)
      Text(this.value.length > 0 ? this.value : '--')
        .fontSize(12).fontColor(this.c.fourth).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .backgroundColor(this.c.soft)
      .borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct StructuredDetailRow {
  @Prop label: string
  @Prop value: string
  @Prop tablet: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row({ space: 12 }) {
      Text(this.label)
        .fontSize(this.tablet ? 11 : 10).fontColor(this.c.tertiary).width(this.tablet ? 108 : 104)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value)
        .fontSize(this.tablet ? 12 : 11).fontColor(this.c.fourth).layoutWeight(1)
        .textAlign(TextAlign.Start).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.tablet ? 18 : 17)
    }
      .width('100%').height(this.tablet ? 46 : 44).alignItems(VerticalAlign.Center)
  }
}

// 完整名称行：与 StructuredDetailRow 同构，但不固定行高、允许 4 行换行，
// 用于「优化名称」场景（恒星名/目录编号拼起来可能很长），不做省略。
@Component
export struct DetailNameRow {
  @Prop label: string
  @Prop value: string
  @Prop tablet: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row({ space: 12 }) {
      Text(this.label)
        .fontSize(this.tablet ? 11 : 10).fontColor(this.c.tertiary).width(this.tablet ? 108 : 104)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value)
        .fontSize(this.tablet ? 12 : 11).fontColor(this.c.fourth).layoutWeight(1)
        .textAlign(TextAlign.Start).maxLines(4)
        .lineHeight(this.tablet ? 18 : 17)
    }
      .width('100%').padding({ top: 8, bottom: 8 }).alignItems(VerticalAlign.Top)
  }
}

@Component
export struct DetailSectionTitle {
  @Prop title: string
  @Prop tablet: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    if (this.tablet) {
      Text(this.title).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.tertiary).width('100%')
        .padding({ top: 4, bottom: 4 })
        .border({ width: { bottom: 0.5 }, color: { bottom: this.c.border } })
    } else {
      Text(this.title)
        .fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.c.tertiary).width('100%')
        .padding({ top: 7, bottom: 4 })
    }
  }
}
