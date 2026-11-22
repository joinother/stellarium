import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { TabItem } from '../../pages/StellariumTypes'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 目镜面板的器材页签选择器（通用 / 目镜 / 镜头 / 传感器 / 望远镜 / 关于）。
// 与图层面板共用同一 chip 视觉：横向滚动、选中 accent、未选中 bg。
@Component
export struct OcularsTabs {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop tabs: TabItem[]
  @Prop activeTab: number
  @State private c: ThemeSlots = DEFAULT_SLOTS
  private tabsScroller: Scroller = new Scroller()
  onSelectTab: (id: number) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Scroll(this.tabsScroller) {
      Row({ space: 6 }) {
        ForEach(this.tabs, (tab: TabItem) => {
          Text(tab.label)
            .id('oculars-tab-' + tab.id.toString())
            .fontSize(panelFontSize(12, this.readableUi))
            .fontColor(this.activeTab === tab.id ? this.c.onAccent : this.c.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .constraintSize({ minWidth: this.readableUi ? 72 : 58, minHeight: this.readableUi ? 40 : 36 })
            .padding({ left: this.readableUi ? 13 : 10, right: this.readableUi ? 13 : 10, top: 6, bottom: 6 })
            .backgroundColor(this.activeTab === tab.id ? this.c.accent : this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .animation({ duration: 180, curve: Curve.EaseInOut })
            .onClick(() => { this.onSelectTab(tab.id) })
        }, (tab: TabItem) => tab.id.toString())
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
