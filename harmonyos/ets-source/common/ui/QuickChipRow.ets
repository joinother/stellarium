import { curves } from '@kit.ArkUI'
import { ChipItem } from '../../pages/StellariumTypes'
import { UI_RADIUS_PILL } from './UiTokens'

// 快捷 chips 行，多处调用共用。
//
// items 经 `@Prop` 承载（参数化 `@Builder` 的数组参数会按值捕获、子树首帧后冻结）；
// 点击经 `onChip` 回调交回宿主决定处理方式。
@Component
export struct QuickChipRow {
  @Prop items: ChipItem[]
  onChip: (id: string) => void = () => {}

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.items, (item: ChipItem) => {
          Button(item.label)
            .fontSize(12)
            .fontColor('#7FB3DC')
            .fontWeight(FontWeight.Medium)
            .height(32)
            .padding({ left: 14, right: 14 })
            .backgroundColor('rgba(107, 163, 214, 0.20)')
            .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
            .borderRadius(UI_RADIUS_PILL)
            .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.18)', offsetX: 0, offsetY: 5 })
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
