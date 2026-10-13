import { ObjectMediaStore } from '../../state/ObjectMediaStore'
import { I18n } from '../../pages/I18n'
import { getIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 「天体详情·三维模型」全屏沉浸叠层。
//
// 分工：
//   - 可见性判定 `objectMediaStore.objectInspectorModelImmersive` 留在宿主调用点，组件根即那个全屏
//     `Stack`（zIndex 1100 / BLOCK_HIERARCHY）；
//   - 模型数据（`objectInspectorModelPixelMap` / `objectInspectorProceduralKind` /
//     `objectInspectorModelOverlayOpacity`）经 @ObjectLink `objectMediaStore` 引用语义读取 —— 跨组件
//     传 `image.PixelMap` 必须走 @ObjectLink（@Prop 深拷贝 PixelMap 会使 `Image` 立即 `onError`）；
//   - 标题 `objectDetailStore.selectedName`、模式提示 `objectInspectorModelNotice()`、顶部安全区
//     `mediaPreviewTopInset()` 由宿主算好后以 @Prop（titleText/noticeText/topInset）传入；
//   - 关闭/重置/舞台手势三个动作回注宿主：`setObjectInspectorModelImmersive(false)` /
//     `resetObjectInspectorModelView()` / `handleObjectInspectorModelTouch(event)`（旋转与双指缩放的
//     算法、触摸计数等内部状态仍留宿主）。
//
// 组件根即全屏 `Stack`（`object-model-close` / `object-model-stage` 为跨会话 id 锚点）。
@Component
export struct ObjectInspectorModelOverlay {
  @ObjectLink objectMediaStore: ObjectMediaStore
  @Prop titleText: string
  @Prop noticeText: string
  @Prop topInset: number
  onCloseOverlay: () => void = () => {}
  onResetView: () => void = () => {}
  onStageTouch: (event: TouchEvent) => void = () => {}

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack() { }.width('100%').height('100%').backgroundColor('#020408')
        .hitTestBehavior(HitTestMode.Block)
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(this.titleText).fontSize(20).fontColor('#F2F4F8').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            Text(this.objectMediaStore.objectInspectorProceduralKind.length > 0 ? I18n.t('model_schematic') : I18n.t('model_offline'))
              .fontSize(12).fontColor('#B8BDC8').width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button() {
            Image(getIcon('close', false)).width(20).height(20).fillColor('#F2F4F8')
          }.width(44).height(44).padding(0).borderRadius(UI_RADIUS_PILL)
            .backgroundColor('rgba(255,255,255,0.10)').zIndex(2)
            .accessibilityText(I18n.t('model_close'))
            .id('object-model-close')
            .onClick(() => { this.onCloseOverlay() })
        }.width('100%')
        Stack({ alignContent: Alignment.Center }) {
          if (this.objectMediaStore.objectInspectorModelPixelMap !== undefined) {
            Image(this.objectMediaStore.objectInspectorModelPixelMap).width('100%').height('100%').objectFit(ImageFit.Contain)
              .hitTestBehavior(HitTestMode.None)
          }
        }.width('100%').layoutWeight(1).clip(true)
          .id('object-model-stage')
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => { this.onStageTouch(event) })
        Text(this.noticeText).fontSize(12).fontColor('#B8BDC8').lineHeight(19)
          .width('100%').textAlign(TextAlign.Center)
        Row({ space: 12 }) {
          Text(I18n.t('model_gesture_hint')).fontSize(12).fontColor('#B8BDC8').layoutWeight(1).maxLines(2)
          Button(I18n.t('model_reset')).height(44).fontSize(13).fontColor('#F2F4F8')
            .padding({ left: 18, right: 18 }).backgroundColor('rgba(255,255,255,0.10)').borderRadius(UI_RADIUS_PILL)
            .onClick(() => { this.onResetView() })
        }.width('100%')
      }.width('100%').height('100%')
        .padding({ left: 24, right: 24, top: this.topInset, bottom: 32 })
    }.width('100%').height('100%').zIndex(1100)
      .opacity(this.objectMediaStore.objectInspectorModelOverlayOpacity)
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }
}
