import { curves } from '@kit.ArkUI'
import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'
import { ShellAction } from '../../pages/StellariumTypes'
import { DockButton } from './DockButton'
import { DockStore } from '../../state/DockStore'

// 主界面底部 Dock 栏。
//
// 入口集合、展开/紧凑两档的尺寸、玻璃态与透明度由宿主以 @Prop 传入；
// 触摸、点按与面板触摸回注宿主。
//
// 激活态为什么经 @ObjectLink 而不是 @Prop：
//  - ForEach 对**键值未变**的数组项不会重新执行 itemGenerator，把 active 作为 @Prop
//    直接传入会在复用后冻结（高亮不跟随）。
//  - 把激活态并入 ForEach 键值虽能让高亮跟随，却让激活项**销毁重建**
//    （开/关面板时入口元素重建、过渡不流畅）。
//  - 正解：键值保持稳定（item.panel + languageRevision），激活态放进 @Observed 的
//    DockStore、以 @ObjectLink 注入每个入口；宿主经 @Prop 传入的 activePanel /
//    panelVisible 用 @Watch 同步进 store，入口只重渲染、不重建（V1 深观察）。

@Component
export struct BottomDock {
  @Prop actions: ShellAction[]
  @Prop isExpanded: boolean
  @Prop @Watch('syncActiveState') panelVisible: boolean
  @Prop @Watch('syncActiveState') activePanel: string
  @Prop chromeOpacity: number
  @Prop isGlass: boolean
  @Prop widthPercent: number
  @Prop languageRevision: number
  @Prop iconSize: number
  @Prop labelFontSize: number
  @Prop itemHeight: number
  onDockTouch: (event: TouchEvent) => void = () => {}
  onDockTap: (item: ShellAction) => void = () => {}
  onPanelTouch: (event: TouchEvent) => void = () => {}

  @State private activeState: DockStore = new DockStore()

  aboutToAppear(): void {
    this.syncActiveState()
  }

  private syncActiveState(): void {
    this.activeState.activePanel = this.activePanel
    this.activeState.panelVisible = this.panelVisible
  }

  build() {
    Row() {
      // 所有屏幕统一使用五个入口；手机仅改变面板的呈现方式，不改变动作集合。
      ForEach(this.actions, (item: ShellAction) => {
        DockButton({
          icon: item.icon, label: item.label, panelId: item.panel, activeState: this.activeState,
          iconSize: this.iconSize, labelFontSize: this.labelFontSize, itemHeight: this.itemHeight,
          onTouchEvent: (event: TouchEvent) => { this.onDockTouch(event) },
          onTap: () => { this.onDockTap(item) }
        })
      }, (item: ShellAction) => item.panel + '/' + this.languageRevision.toString())
    }
      .height(this.isExpanded ? 48 : 66)
      .width(this.isExpanded ? '100%' : this.widthPercent + '%')
      .padding({ left: this.isExpanded ? 4 : 6, right: this.isExpanded ? 4 : 6 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor(this.isGlass ? 'rgba(10, 14, 26, 0.42)' : 'rgba(25, 26, 28, 0.64)')
      .backdropBlur(this.isGlass ? 40 : 26)
      .border({ width: 0.5, color: this.isGlass ? 'rgba(147, 215, 255, 0.10)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(UI_RADIUS_PANEL)
      .shadow({ radius: this.isExpanded ? 18 : 28, color: 'rgba(0, 0, 0, 0.30)', offsetX: 0, offsetY: this.isExpanded ? 8 : 14 })
      .alignSelf(ItemAlign.Center)
      .onTouch((event: TouchEvent) => { this.onPanelTouch(event) })
      .opacity(this.chromeOpacity * (this.panelVisible ? 1.0 : 0.985))
      .scale({ x: this.chromeOpacity < 1 ? 0.98 : (this.panelVisible ? 1.0 : 0.985), y: this.chromeOpacity < 1 ? 0.98 : (this.panelVisible ? 1.0 : 0.985) })
      .translate({ y: this.panelVisible ? 0 : 2 })
      .animation({ duration: 300, curve: curves.springMotion(0.46, 0.86) })
      .onTouch((event: TouchEvent) => { this.onDockTouch(event) })
  }
}
