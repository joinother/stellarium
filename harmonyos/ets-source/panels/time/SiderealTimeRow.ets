import { Theme } from '@kit.ArkUI'
import { TimeStore } from '../../state/TimeStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { InfoTipButton } from '../../common/ui/InfoTipButton'

// 恒星时行：标签 + ⓘ 说明气泡 + 实时数值。
// 数值由宿主经引擎同步写入 store，这里直接读，保证随时间实时刷新。
@Component
export struct SiderealTimeRow {
  @ObjectLink store: TimeStore
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row({ space: 4 }) {
      Text('恒星时').fontSize(12).fontColor(this.c.sub).textAlign(TextAlign.Start)
      InfoTipButton({
        title: '恒星时',
        tip: '恒星时 = 此刻正好在你头顶中天的那条赤经线，用来判断某个天体现在转到哪儿了。'
      })
      Text(this.store.siderealTimeText)
        .fontSize(13).fontColor(this.c.text).layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').padding({ left: 10, right: 10, top: 4, bottom: 4 }).alignItems(VerticalAlign.Center)
  }
}
