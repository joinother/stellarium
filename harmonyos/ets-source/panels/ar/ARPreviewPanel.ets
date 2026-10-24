import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL, UI_RADIUS_SHEET } from '../../common/ui/UiTokens'
import { ARStore } from '../../state/ARStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// AR 模式预研面板（`activePanel === 'ar'`）。
//
// 离线预览「只保留星空、逐步抠除地景」的视觉逻辑：模式切换（星空叠加 / 地景递进 /
// 深度遮挡 / 只保留星空）+ 地景抠除进度滑杆 + 状态文案。不打开摄像头。
// 状态走 @ObjectLink ARStore；主题色与三个动作回调解宿主注入。
interface ArPreviewModeOption {
  id: string
  label: string
}

@Component
export struct ARPreviewPanel {
  @ObjectLink arStore: ARStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onSetMode: (mode: string) => void = () => {}
  onSetRevealProgress: (value: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text('AR 模式预研').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.c.text).width('100%')
        Text('先验证"只保留星空、逐步抠除地景"的视觉逻辑。当前是离线预览，不会打开摄像头，也不会把真实地面当成星图地景。')
          .fontSize(11).fontColor(this.c.sub).width('100%')
        Row({ space: 6 }) {
          ForEach([
            { id: 'overlay', label: '星空叠加' },
            { id: 'portal', label: '地景递进' },
            { id: 'depth', label: '深度遮挡' },
            { id: 'sky-only', label: '只保留星空' }
          ] as ArPreviewModeOption[], (item: ArPreviewModeOption) => {
            Text(item.label)
              .fontSize(11)
              .fontColor(this.arStore.arPreviewMode === item.id ? this.c.onAccent : this.c.sub)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(32)
              .padding({ top: 8, bottom: 8 })
              .backgroundColor(this.arStore.arPreviewMode === item.id ? this.c.accent : this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onSetMode(item.id) })
          }, (item: ArPreviewModeOption) => item.id)
        }.width('100%')
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            Text('星空层').fontSize(15).fontColor(this.c.fourth).margin({ top: 28 })
            Text(this.arStore.arPreviewMode === 'depth' ? '等待深度/网格适配' : (this.arStore.arPreviewMode === 'sky-only' ? '地面遮罩已抠除，仅保留星空' : '星体与坐标叠加预览'))
              .fontSize(11).fontColor(this.c.spinner).margin({ top: 8 })
          }
            .width('100%').height(214).justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Center)
            .backgroundColor(this.c.mediaCard)
          Column() {
            Text('地面 / 墙面层').fontSize(14).fontColor(this.c.detailSub).margin({ top: 30 })
            Text(this.arStore.arPreviewMode === 'portal' ? '拖动进度，观察从地景到星空的递进' : (this.arStore.arPreviewMode === 'sky-only' ? '只保留星空层' : '遮挡层'))
              .fontSize(10).fontColor(this.c.iconTertiary).margin({ top: 8 })
          }
            .width(((1 - this.arStore.arRevealProgress) * 100).toFixed(2) + '%').height(214)
            .backgroundColor(this.c.overlayScrim)
            .alignItems(HorizontalAlign.Center)
            .clip(true)
          if (this.arStore.arPreviewMode === 'portal') {
            Column() {
              Text('门户边缘').fontSize(10).fontColor(this.c.iconSecondary)
            }
              .width(110).height(150).border({ width: 1.5, color: this.c.dockActive })
              .borderRadius(18).margin({ left: 18, top: 32 }).opacity(0.86)
          }
        }
          .width('100%').height(214).clip(true).borderRadius(UI_RADIUS_SHEET)
          .border({ width: 0.5, color: this.c.border })
        Row({ space: 8 }) {
          Text('地景抠除').fontSize(12).fontColor(this.c.text).width(62)
          Slider({ value: this.arStore.arRevealProgress, min: 0, max: 1, step: 0.01, style: SliderStyle.OutSet })
            .layoutWeight(1).blockColor(this.c.accent).trackColor(this.c.bg).selectedColor(this.c.accent)
            .onChange((value: number) => { this.onSetRevealProgress(value) })
          Text(Math.round(this.arStore.arRevealProgress * 100) + '%').fontSize(11).fontColor(this.c.sub).width(42).textAlign(TextAlign.End)
        }.width('100%').height(38)
        Text(this.arStore.arPreviewStatus).fontSize(10).fontColor(this.c.spinner).width('100%')
        Text('真实 AR 的推荐链路：相机背景 → AR Engine 运动跟踪 → 竖直平面/环境 Mesh → 深度遮挡 → 星空渲染层。所谓"打碎一面墙"应是门户或裂隙的视觉效果，不会真的删除现实墙体。')
          .fontSize(10).fontColor(this.c.sub).width('100%')
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 12 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
  }
}
