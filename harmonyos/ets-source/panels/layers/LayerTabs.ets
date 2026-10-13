import { TabItem } from '../../pages/StellariumTypes'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 本组件职责：「图层」面板的视图标签页选择器。
//
// 标签数据（layerTabItems()，含离线构建过滤）与当前选中项（viewTab）由宿主以 @Prop 传入；
// 点选走 onSelectTab 回调，宿主在里面做 animateTo 过渡与
// loadLandscapeList / syncSkyCultureTimeFollowTimer 等副作用。
@Component
export struct LayerTabs {
  @Prop tabs: TabItem[]
  @Prop activeTab: number
  @Prop foldTablet: boolean
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  onSelectTab: (id: number) => void = () => {}

  build() {
    Scroll() {
      Row({ space: this.foldTablet ? 5 : 6 }) {
        ForEach(this.tabs, (tab: TabItem) => {
          Text(tab.label)
            .fontSize(this.foldTablet ? 11 : 10)
            .fontColor(this.activeTab === tab.id ? this.textColor : this.subColor)
            .padding({ left: this.foldTablet ? 10 : 8, right: this.foldTablet ? 10 : 8, top: 5, bottom: 5 })
            .backgroundColor(this.activeTab === tab.id ? this.accentColor : this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .animation({ duration: 180, curve: Curve.EaseInOut })
            .onClick(() => {
              this.onSelectTab(tab.id)
            })
        }, (tab: TabItem, index: number) => tab.id.toString())
      }
      .padding({ left: 2, right: 12 })
    }
    .width('100%')
    .height(38)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .margin({ top: 4, bottom: 10 })
  }
}
