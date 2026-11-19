import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from './UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 星文化描述块：按 kind 渲染标题 / 项目 / 表头 / 表格行 / 正文。
//
// 天体详情卡的“星座文化”段与星文化查看器共用，因此做成共享组件；
// `level` 的可选判断由调用方解析成 `headingLarge` 布尔量传入，组件内不做可选值判断；
// 表格块携带 `cells`（2–4 列横向分列，5 列以上自动转为标题 + 详情卡片行）；
// 文字颜色（夜视）经机制四从 ThemeSlots 取。
@Component
export struct SkyCultureDescriptionBlockView {
  @Prop kind: string
  @Prop headingLarge: boolean
  @Prop text: string
  @Prop cells: string[] = []
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private nonEmptyTailText(): string {
    const rest: string[] = []
    for (let i = 1; i < this.cells.length; i++) {
      const value = this.cells[i].trim()
      if (value.length > 0) rest.push(value)
    }
    return rest.join(' · ')
  }

  build() {
    if (this.kind === 'heading') {
      Text(this.text).fontSize(this.headingLarge ? 15 : 13)
        .fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
        .margin({ top: 8, bottom: 3 })
    } else if (this.kind === 'bullet') {
      Text('• ' + this.text).fontSize(11).lineHeight(19).fontColor(this.c.text).width('100%')
        .padding({ left: 8, right: 4 })
    } else if (this.kind === 'tableHeader') {
      if (this.cells.length >= 2 && this.cells.length <= 4) {
        Row({ space: 6 }) {
          ForEach(this.cells, (cell: string, index: number) => {
            Text(cell.length > 0 ? cell : '—')
              .fontSize(10).lineHeight(16).fontColor(this.c.textStrong)
              .fontWeight(FontWeight.Medium).layoutWeight(1)
          }, (cell: string, index: number) => 'th-' + index.toString() + '-' + cell)
        }.width('100%').alignItems(VerticalAlign.Top)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
          .margin({ top: 4 })
      } else {
        Text(this.text).fontSize(10).lineHeight(17).fontColor(this.c.textStrong)
          .fontWeight(FontWeight.Medium).width('100%')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
          .margin({ top: 4 })
      }
    } else if (this.kind === 'tableRow') {
      if (this.cells.length >= 2 && this.cells.length <= 4) {
        Row({ space: 6 }) {
          ForEach(this.cells, (cell: string, index: number) => {
            Text(cell.length > 0 ? cell : '—')
              .fontSize(10).lineHeight(17)
              .fontColor(index === 0 ? this.c.textStrong : this.c.text)
              .fontWeight(index === 0 ? FontWeight.Medium : FontWeight.Normal)
              .layoutWeight(1)
          }, (cell: string, index: number) => 'td-' + index.toString() + '-' + cell)
        }.width('100%').alignItems(VerticalAlign.Top)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .backgroundColor(this.c.rowBg)
          .border({ width: 0.5, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL)
      } else if (this.cells.length > 4) {
        Column({ space: 2 }) {
          if (this.cells[0].trim().length > 0) {
            Text(this.cells[0].trim()).fontSize(11).lineHeight(17)
              .fontColor(this.c.textStrong).fontWeight(FontWeight.Medium).width('100%')
          }
          if (this.nonEmptyTailText().length > 0) {
            Text(this.nonEmptyTailText()).fontSize(10).lineHeight(17)
              .fontColor(this.c.text).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.c.rowBg)
          .border({ width: 0.5, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL)
      } else {
        Text(this.text).fontSize(10).lineHeight(17).fontColor(this.c.text).width('100%')
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
      }
    } else {
      Text(this.text).fontSize(11).lineHeight(19).fontColor(this.c.text).width('100%')
    }
  }
}
