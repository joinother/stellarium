import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'

// 卫星面板的卫星分组选择器。
//
// 组名本地化直接调用 I18n.satGroup。Scroller 以普通成员传入
// （宿主仍持有同一实例，`publishSatellitePanelState` 要读它的 currentOffset）。
// 事件标志读取与桥调用留在宿主，经 onGroupScroll / onSelect 注入。
@Component
export struct SatelliteGroupSelector {
  @Prop groups: string[]
  @Prop activeGroup: string
  @Prop loading: boolean
  @Prop subColor: string
  @Prop accentColor: string
  @Prop textColor: string
  @Prop bgColor: string
  scroller: Scroller = new Scroller()
  onGroupScroll: () => void = () => {}
  onSelect: (group: string) => void = () => {}

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(I18n.t('c_satellite_groups')).fontSize(12).fontColor(this.subColor).layoutWeight(1)
        LoadingProgress().width(18).height(18).color(this.accentColor)
          .opacity(this.loading ? 1 : 0)
      }.width('100%').height(24)
      Scroll(this.scroller) {
        Column({ space: 6 }) {
          ForEach(this.groups, (group: string) => {
            Row({ space: 8 }) {
              Text(I18n.satGroup(group)).fontSize(13).fontColor(this.activeGroup === group ? this.accentColor : this.textColor)
                .layoutWeight(1).maxLines(2)
              Text('✓').fontSize(14).fontColor(this.accentColor).width(20)
                .opacity(this.activeGroup === group ? 1 : 0)
            }.width('100%').height(44).padding({ left: 12, right: 12 })
              .backgroundColor(this.activeGroup === group ? 'rgba(107,163,214,0.18)' : this.bgColor)
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onSelect(this.activeGroup === group ? '' : group) })
          }, (group: string) => group)
        }.width('100%')
      }.width('100%').height(180).scrollBar(BarState.Auto)
        .onScroll(() => { this.onGroupScroll() })
    }.width('100%')
  }
}
