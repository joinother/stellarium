import { TimeStore } from '../../state/TimeStore'

// 恒星时行：标签 + 数值 + 一行说明。
// 数值由宿主经引擎同步写入 store，这里直接读，保证随时间实时刷新。
@Component
export struct SiderealTimeRow {
  @ObjectLink store: TimeStore
  @Prop subColor: string

  build() {
    Column() {
      Row() {
        Text('恒星时').fontSize(11).fontColor('#99FFFFFF').width(64).textAlign(TextAlign.Start)
        Text(this.store.siderealTimeText)
          .fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ left: 10, right: 10, top: 3, bottom: 3 })
      Text('恒星时 = 此刻正好在你头顶中天的那条赤经线，用来判断某个天体现在转到哪儿了。')
        .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 2 })
    }.width('100%')
  }
}
