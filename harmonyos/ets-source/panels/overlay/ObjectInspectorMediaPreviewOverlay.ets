import { ObjectMediaStore } from '../../state/ObjectMediaStore'
import { getIcon } from '../../common/ui/ShellIcons'
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
@Component
export struct ObjectInspectorMediaPreviewOverlay {
  @ObjectLink objectMediaStore: ObjectMediaStore
  @Prop titleText: string
  @Prop topInset: number
  closeObjectInspectorMediaPreview: () => void = () => {}
  onObjectInspectorMediaPreviewLoaded: () => void = () => {}
  onObjectInspectorMediaPreviewError: () => void = () => {}
  retryObjectInspectorMediaPreview: () => void = () => {}

  build() {
    Stack() {
      Stack() { }
        .width('100%').height('100%')
        .backgroundColor('rgba(2,6,12,0.99)')
        .hitTestBehavior(HitTestMode.Block)
      Column({ space: 0 }) {
        Row() {
          Column({ space: 3 }) {
            Text(this.titleText).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#F0FAFF')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            Text(this.objectMediaStore.objectInspectorMediaLabel).fontSize(11).fontColor('#9CC7DB').width('100%')
          }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button() {
            Image(getIcon('close', false)).width(20).height(20).fillColor('#E4F5FC')
          }
            .width(44).height(44).borderRadius(UI_RADIUS_PILL)
            .backgroundColor('rgba(255,255,255,0.10)')
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
              LoadingProgress().width(36).height(36).color('#8EC9E9')
              Text('正在打开本地图像').fontSize(12).fontColor('#B8D7E6')
            }
          } else if (this.objectMediaStore.objectInspectorMediaPreviewFailed ||
            (!this.objectMediaStore.objectInspectorMediaPreviewLoading && this.objectMediaStore.objectInspectorMediaPreviewPath.length === 0)) {
            Column({ space: 12 }) {
              Image(getIcon('catalog_galaxy', false)).width(42).height(42).fillColor('#8EC9E9')
              Text('图像暂时无法显示').fontSize(14).fontColor('#E4F5FC')
              Button('重新加载')
                .height(36).fontSize(12).fontColor('#E4F5FC')
                .backgroundColor('rgba(91,147,191,0.28)').borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.retryObjectInspectorMediaPreview() })
            }
          }
        }
          .width('100%').layoutWeight(1)
          .backgroundColor('#02060C').borderRadius(UI_RADIUS_CONTROL)

        Text('图像来自本地随应用分发的 Stellarium 资源；未在此页面联网下载。')
          .fontSize(11).fontColor('#9CC7DB').lineHeight(17).width('100%').height(41)
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
