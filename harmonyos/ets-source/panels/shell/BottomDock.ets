import { curves, Theme } from '@kit.ArkUI'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { ShellAction } from '../../pages/StellariumTypes'
import { DockButton } from './DockButton'
import { DockStore } from '../../state/DockStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

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
  @State c: ThemeSlots = DEFAULT_SLOTS
  onDockTouch: (event: TouchEvent) => void = () => {}
  onDockTap: (item: ShellAction) => void = () => {}
  onPanelTouch: (event: TouchEvent) => void = () => {}

  @State private activeState: DockStore = new DockStore()
  // 触点高光：模拟系统沉浸光感的按压/滑动高亮（第三方普通组件拿不到系统 lightEffect）。
  @State private glowX: number = 0
  @State private glowY: number = 0
  @State private glowOpacity: number = 0

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToAppear(): void {
    this.syncActiveState()
  }

  private syncActiveState(): void {
    this.activeState.activePanel = this.activePanel
    this.activeState.panelVisible = this.panelVisible
  }

  private updateGlow(event: TouchEvent): void {
    const touch: TouchObject | undefined = event.touches.length > 0 ? event.touches[0] : undefined
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      if (touch !== undefined) {
        this.glowX = touch.x
        this.glowY = touch.y
      }
      this.glowOpacity = 1
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
        this.glowOpacity = 0
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
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
        .width('100%')
        .height('100%')
        // 两端全胶囊：首末图标与圆弧之间留足内边距。
        .padding({ left: this.isExpanded ? 8 : 12, right: this.isExpanded ? 8 : 12 })
        .justifyContent(FlexAlign.SpaceBetween)

      // 触点高光：跟随手指在 Dock 内滑动，松手淡出。
      Row()
        .width(180)
        .height(180)
        .radialGradient({
          center: [90, 90],
          radius: 90,
          colors: [[this.c.dockActive, 0], [this.c.dockActive, 0.28], [Color.Transparent, 1]]
        })
        .position({ x: this.glowX - 90, y: this.glowY - 90 })
        .opacity(this.glowOpacity)
        .hitTestBehavior(HitTestMode.None)
    }
      .height(this.isExpanded ? 48 : 66)
      .width(this.isExpanded ? '100%' : this.widthPercent + '%')
      .backgroundEffect({
        radius: this.isGlass ? 30 : 24,
        saturation: 1.3,
        brightness: 1.02,
        color: this.isGlass ? this.c.bgStrong : this.c.overlayPanel
      })
      .border({ width: 0.5, color: this.isGlass ? this.c.border : this.c.dividerSoft })
      .borderRadius(UI_RADIUS_PILL)
      .clip(true)
      .shadow({ radius: this.isExpanded ? 18 : 28, color: this.c.shadowSoft, offsetX: 0, offsetY: this.isExpanded ? 8 : 14 })
      .alignSelf(ItemAlign.Center)
      .opacity(this.chromeOpacity * (this.panelVisible ? 1.0 : 0.985))
      .scale({ x: this.chromeOpacity < 1 ? 0.98 : (this.panelVisible ? 1.0 : 0.985), y: this.chromeOpacity < 1 ? 0.98 : (this.panelVisible ? 1.0 : 0.985) })
      .translate({ y: this.panelVisible ? 0 : 2 })
      .animation({ duration: 300, curve: curves.springMotion(0.46, 0.86) })
      .onTouch((event: TouchEvent) => {
        this.updateGlow(event)
        this.onPanelTouch(event)
        this.onDockTouch(event)
      })
  }
}
