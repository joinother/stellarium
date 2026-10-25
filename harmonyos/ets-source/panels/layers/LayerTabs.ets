import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { TabItem } from '../../pages/StellariumTypes'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 本组件职责：「图层」面板的视图标签页选择器。
//
// 标签数据（layerTabItems()，含离线构建过滤）与当前选中项（viewTab）由宿主以 @Prop 传入；
// 点选走 onSelectTab 回调，宿主在里面做 animateTo 过渡与
// loadLandscapeList / syncSkyCultureTimeFollowTimer 等副作用。
@Component
export struct LayerTabs {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop tabs: TabItem[]
  @Prop activeTab: number
  @Prop foldTablet: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSelectTab: (id: number) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Scroll() {
      Row({ space: this.foldTablet ? 5 : 6 }) {
        ForEach(this.tabs, (tab: TabItem) => {
          Text(tab.label)
            .fontSize(panelFontSize(12, this.readableUi))
            .fontColor(this.activeTab === tab.id ? this.c.onAccent : this.c.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ minWidth: this.readableUi ? 76 : 60, minHeight: this.readableUi ? 40 : 36 })
            .padding({ left: this.readableUi ? 13 : 10, right: this.readableUi ? 13 : 10, top: 6, bottom: 6 })
            .backgroundColor(this.activeTab === tab.id ? this.c.accent : this.c.bg)
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
    .height(this.readableUi ? 46 : 42)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .margin({ top: 4, bottom: 10 })
  }
}
