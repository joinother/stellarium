import { curves, Theme } from '@kit.ArkUI'
import { ChipItem } from '../../pages/StellariumTypes'
import { UI_RADIUS_PILL } from './UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 快捷 chips 行，多处调用共用。
//
// items 经 `@Prop` 承载（参数化 `@Builder` 的数组参数会按值捕获、子树首帧后冻结）；
// 点击经 `onChip` 回调交回宿主决定处理方式。
@Component
export struct QuickChipRow {
  @Prop items: ChipItem[]
  @State c: ThemeSlots = DEFAULT_SLOTS
  onChip: (id: string) => void = () => {}

  onWillApplyTheme(theme: Theme) {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.items, (item: ChipItem) => {
          Button(item.label)
            .fontSize(12)
            .fontColor(this.c.accent)
            .fontWeight(FontWeight.Medium)
            .height(32)
            .padding({ left: 14, right: 14 })
            .backgroundColor(this.c.softStrong)
            .border({ width: 1, color: this.c.softStrong })
            .borderRadius(UI_RADIUS_PILL)
            .shadow({ radius: 12, color: this.c.shadowSoft, offsetX: 0, offsetY: 5 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
            .onClick(() => { this.onChip(item.id) })
        }, (item: ChipItem) => item.id)
      }
      .padding({ left: 2, right: 2 })
    }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .margin({ top: 8 })
  }
}
