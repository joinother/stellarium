import { SkyCultureViewStore } from '../../state/SkyCultureViewStore'
import { getIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 「星空文化·离线绘图」全屏预览叠层。
//
// 分工：
//   - 可见性判定 `skyCultureViewStore.artPreviewOpen` 留在宿主调用点，组件根即那个全屏 `Stack`
//     （zIndex 101 / Transparent）；
//   - 标题/加载/失败三态、`artPreviewName` 与解码结果 `artPreviewPixelMap` 全部经 @ObjectLink
//     `skyCultureViewStore` 实时读取。PixelMap 必须走 @ObjectLink 的**引用语义**：若以 @Prop 传入
//     PixelMap，组件拿到的是被拷贝过的对象，`Image` 立即 `onError` 显示「绘图资源无法显示」；
//     收进 store 后渲染正常；
//   - 主题色 `nmText/nmSub/nmAccent/nmBg` 与顶部安全区 `mediaPreviewTopInset()` 由宿主算好后以
//     @Prop（textColor/subColor/accentColor/bgColor/topInset）传入，随夜间模式实时刷新；
//   - 关闭/加载完成/解码失败/重新加载四个动作全部回注宿主
//     （`closeSkyCultureArtPreview` / `onSkyCultureArtLoaded` / `onSkyCultureArtError` /
//     `onRetrySkyCultureArtPreview`）。
//
// 组件根即全屏 `Stack`（并列双根包于 Stack）。
@Component
export struct SkyCultureArtPreviewOverlay {
  @ObjectLink skyCultureViewStore: SkyCultureViewStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop bgColor: string
  @Prop topInset: number
  closeSkyCultureArtPreview: () => void = () => {}
  onSkyCultureArtLoaded: () => void = () => {}
  onSkyCultureArtError: () => void = () => {}
  onRetrySkyCultureArtPreview: () => void = () => {}

  build() {
    Stack() {
      Stack() { }
        .width('100%').height('100%')
        .backgroundColor('rgba(3,7,15,0.94)')
        .hitTestBehavior(HitTestMode.Block)
      Column({ space: 10 }) {
        Row() {
          Text(this.skyCultureViewStore.artPreviewName.length > 0 ? this.skyCultureViewStore.artPreviewName : '星座绘图')
            .fontSize(15).fontColor(this.textColor).fontWeight(FontWeight.Medium)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button() {
            Image(getIcon('close', false)).width(20).height(20).fillColor(this.textColor)
          }
            .width(44).height(44).borderRadius(UI_RADIUS_PILL).backgroundColor('rgba(255,255,255,0.10)')
            .padding(0)
            .zIndex(10).hitTestBehavior(HitTestMode.Block)
            .onClick(() => { this.closeSkyCultureArtPreview() })
        }.width('100%').height(54)
        Stack({ alignContent: Alignment.Center }) {
          if (this.skyCultureViewStore.artPreviewPixelMap !== undefined) {
            Image(this.skyCultureViewStore.artPreviewPixelMap).width('100%').height('100%').objectFit(ImageFit.Contain)
              .backgroundColor('rgba(0,0,0,0.28)').borderRadius(UI_RADIUS_CONTROL)
              .onComplete(() => { this.onSkyCultureArtLoaded() })
              .onError(() => { this.onSkyCultureArtError() })
          }
          if (this.skyCultureViewStore.artPreviewLoading) {
            Column({ space: 10 }) {
              LoadingProgress().width(34).height(34).color(this.accentColor)
              Text('正在打开离线绘图').fontSize(12).fontColor(this.subColor)
            }
          } else if (this.skyCultureViewStore.artPreviewFailed) {
            Column({ space: 10 }) {
              Text('绘图资源无法显示').fontSize(13).fontColor(this.textColor)
              Text('资源缺失或设备解码失败').fontSize(11).fontColor(this.subColor)
              Button('重新加载').fontSize(11).fontColor(this.textColor).backgroundColor(this.bgColor)
                .borderRadius(UI_RADIUS_CONTROL).height(32)
                .onClick(() => { this.onRetrySkyCultureArtPreview() })
            }
          }
        }.width('100%').layoutWeight(1)
        Text('离线文化绘图').fontSize(10).fontColor(this.subColor)
      }
      .width('100%').height('100%')
      .padding({ left: 24, right: 24, top: this.topInset, bottom: 18 })
      .zIndex(1)
    }
    .width('100%').height('100%').backgroundColor('rgba(3,7,15,0.94)')
    // 必须 Default（默认值）：Transparent 不阻塞兄弟节点，点关闭按钮会穿透打到下层（手机端会误触
    // 右上角陀螺仪按钮）。Default 只阻塞兄弟节点，子节点（关闭按钮等）照常响应。
    .zIndex(101).hitTestBehavior(HitTestMode.Default)
  }
}
