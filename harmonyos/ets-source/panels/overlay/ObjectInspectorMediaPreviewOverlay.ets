import { ObjectMediaStore } from '../../state/ObjectMediaStore'
import { Theme } from '@kit.ArkUI'
import { ThemeSlots, DEFAULT_SLOTS, slotsFromTheme } from '../../state/StellariumTheme'
import { getCatalogIcon, getIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 「天体详情·本地大图」全屏叠层。
//
// 分工：
//   - 可见性判定 `objectInspectorMediaFullscreen` 留在宿主调用点，组件根即那个全屏 `Stack`
//     （zIndex 1000 / Transparent）；
//   - 标题由宿主 `zhNameOf(objectDetailStore.selectedName)` 算好后以 @Prop `titleText` 传入；
//   - 顶部安全区 `mediaPreviewTopInset()` 由宿主算好后以 @Prop `topInset` 传入；
//   - 解码/重试/关闭动作全部回注宿主：`closeObjectInspectorMediaPreview` /
//     `onObjectInspectorMediaPreviewLoaded` / `onObjectInspectorMediaPreviewError` /
//     `retryObjectInspectorMediaPreview`；
//   - 媒体数据（PixelMap / 标签 / Loading / Failed / Path）经 @ObjectLink `objectMediaStore` 读取。
//
// 组件根即全屏 `Stack`，内含背景拦截层与内容 `Column`。
// 主题色走「机制四」：onWillApplyTheme 自取当前主题槽位，调用点不再注入颜色。
@Component
export struct ObjectInspectorMediaPreviewOverlay {
  @ObjectLink objectMediaStore: ObjectMediaStore
  @Prop titleText: string
  @Prop topInset: number
  closeObjectInspectorMediaPreview: () => void = () => {}
  onObjectInspectorMediaPreviewLoaded: () => void = () => {}
  onObjectInspectorMediaPreviewError: () => void = () => {}
  retryObjectInspectorMediaPreview: () => void = () => {}
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Stack() {
      Stack() { }
        .width('100%').height('100%')
        .backgroundColor(this.c.overlayScrim)
        .hitTestBehavior(HitTestMode.Block)
      Column({ space: 0 }) {
        Row() {
          Column({ space: 3 }) {
            Text(this.titleText).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            Text(this.objectMediaStore.objectInspectorMediaLabel).fontSize(11).fontColor(this.c.sub).width('100%')
          }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button() {
            Image(getIcon('close', false)).width(20).height(20).fillColor(this.c.textStrong)
          }
            .width(44).height(44).borderRadius(UI_RADIUS_PILL)
            .backgroundColor(this.c.overlayButton)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .padding(0)
            .zIndex(10).hitTestBehavior(HitTestMode.Block)
            .onClick(() => { this.closeObjectInspectorMediaPreview() })
        }
          .width('100%').height(54)

        Stack({ alignContent: Alignment.Center }) {
          if (this.objectMediaStore.objectInspectorMediaPixelMap !== undefined) {
            Image(this.objectMediaStore.objectInspectorMediaPixelMap)
              .width('100%').height('100%').objectFit(ImageFit.Contain)
              .onComplete(() => { this.onObjectInspectorMediaPreviewLoaded() })
              .onError(() => { this.onObjectInspectorMediaPreviewError() })
          }
          if (this.objectMediaStore.objectInspectorMediaPreviewLoading) {
            Column({ space: 12 }) {
              LoadingProgress().width(36).height(36).color(this.c.spinner)
              Text('正在打开本地图像').fontSize(12).fontColor(this.c.sub)
            }
          } else if (this.objectMediaStore.objectInspectorMediaPreviewFailed ||
            (!this.objectMediaStore.objectInspectorMediaPreviewLoading && this.objectMediaStore.objectInspectorMediaPreviewPath.length === 0)) {
            Column({ space: 12 }) {
              Image(getCatalogIcon('catalog_galaxy', this.c.isNight)).width(42).height(42).fillColor(this.c.spinner)
Text('图像暂时无法显示').fontSize(14).fontColor(this.c.textStrong)
               Button('重新加载')
                 .height(36).fontSize(12).fontColor(this.c.textStrong)
                 .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.retryObjectInspectorMediaPreview() })
            }
          }
        }
          .width('100%').layoutWeight(1)
          .backgroundColor(this.c.overlayPanel).borderRadius(UI_RADIUS_CONTROL)

        Text('图像来自本地随应用分发的 Stellarium 资源；未在此页面联网下载。')
          .fontSize(11).fontColor(this.c.sub).lineHeight(17).width('100%').height(41)
          .padding({ top: 12 })
      }
        .width('100%').height('100%')
        .padding({ left: 24, right: 24, top: this.topInset, bottom: 18 })
        .zIndex(1)
    }
      .width('100%').height('100%')
      // 同 SkyCultureArtPreviewOverlay：Transparent 会让点击穿透到下层按钮，改为 Default。
      .zIndex(1000).hitTestBehavior(HitTestMode.Default)
  }
}
