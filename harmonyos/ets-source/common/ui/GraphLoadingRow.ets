import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 计算中：转圈 + 进度文案（通用加载行）。
@Component
export struct GraphLoadingRow {
  @Prop label: string
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row({ space: 8 }) {
      LoadingProgress().width(22).height(22).color(this.c.accent)
      Text(this.label).fontSize(11).fontColor(this.c.sub)
    }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
  }
}
