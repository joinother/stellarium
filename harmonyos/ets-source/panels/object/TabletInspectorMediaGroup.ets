import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { ObjectMediaStore } from '../../state/ObjectMediaStore'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { TabletInspectorMediaCard, TabletInspectorNoticeRow, TabletInspectorModelBlock, TabletInspectorProgressRow, TabletInspectorFallbackVisual } from './TabletInspectorMedia'

// 天体检查器媒体区：按媒体状态分派图像卡、提示行、模型块与示意图，并处理加载 / 解码等中间态。
//
// 媒体状态以 `@ObjectLink` 观察 `ObjectMediaStore`；派生值（图像高度、模型尺寸、文案、示意图种类）
// 与交互（打开预览 / 重试 / 展开模型 / 模型手势）由宿主注入。
// 分派条件不能经 `@BuilderParam` 交由子组件渲染——真机上宿主 builder 传入子组件会让应用在渲染时退出。

@Component
export struct TabletInspectorMediaGroup {
  @ObjectLink store: ObjectMediaStore
  @ObjectLink detailStore: ObjectDetailStore
  @Prop isPlannedModel: boolean
  @Prop imageHeight: number
  @Prop iconName: string
  @Prop inlineModelSize: number
  @Prop modelReady: boolean
  @Prop modelRendering: boolean
  @Prop hasModelTexture: boolean
  @Prop modelNotice: string
  @Prop warmupText: string
  @Prop fallbackKind: string
  @Prop starColor: string
  onOpen: () => void = () => {}
  onRetry: () => void = () => {}
  onModelExpand: () => void = () => {}
  onModelTouch: (event: TouchEvent) => void = () => {}

  build() {
    if ((this.store.objectInspectorMediaKind === 'image' || this.store.objectInspectorMediaKind === 'constellation') &&
      this.store.objectInspectorMediaPixelMap !== undefined && !this.store.objectInspectorMediaLoadFailed) {
      TabletInspectorMediaCard({
        store: this.store,
        imageHeight: this.imageHeight,
        isPlannedModel: this.detailStore.selectedDetailModel !== undefined &&
          this.detailStore.selectedDetailModel.state === 'planned',
        onOpen: () => { this.onOpen() }
      })
    } else if (this.store.objectInspectorMediaNoMatch) {
      TabletInspectorNoticeRow({
        iconName: this.iconName, iconFill: '#8EC9E9',
        title: '没有匹配的离线资源', subtitle: '当前天体没有随应用分发的对应图像或纹理',
        cardBackground: 'rgba(91,147,191,0.08)',
        onRetry: () => { this.onRetry() }
      })
    } else if (this.store.objectInspectorMediaPreparationFailed) {
      TabletInspectorNoticeRow({
        iconName: this.iconName, iconFill: '#F1C27D',
        title: '离线资源准备失败', subtitle: '文件未能完整复制到本地缓存，请重试',
        cardBackground: 'rgba(241,194,125,0.08)',
        onRetry: () => { this.onRetry() }
      })
    } else if ((this.store.objectInspectorMediaKind === 'image' || this.store.objectInspectorMediaKind === 'constellation' ||
      this.store.objectInspectorMediaKind === 'model') && this.store.objectInspectorMediaLoadFailed) {
      TabletInspectorNoticeRow({
        iconName: this.iconName, iconFill: '#8EC9E9',
        title: '本地资源解码失败', subtitle: '资源已找到，但当前设备无法显示此文件',
        cardBackground: 'rgba(91,147,191,0.08)',
        onRetry: () => { this.onRetry() }
      })
    } else if (this.store.objectInspectorMediaKind === 'model' &&
      (this.modelReady || this.store.objectInspectorModelPixelMap !== undefined)) {
      TabletInspectorModelBlock({
        store: this.store,
        inlineModelSize: this.inlineModelSize,
        modelRendering: this.modelRendering,
        hasModelTexture: this.hasModelTexture,
        modelNotice: this.modelNotice,
        onExpand: () => { this.onModelExpand() },
        onModelTouch: (event: TouchEvent) => { this.onModelTouch(event) }
      })
    } else if (this.store.objectInspectorMediaDecoding) {
      TabletInspectorProgressRow({ title: '正在解码本地图像', subtitle: '资源已找到，正在交给鸿蒙图像框架处理' })
    } else if (this.store.objectInspectorMediaLoading) {
      TabletInspectorProgressRow({
        title: this.store.objectInspectorMediaKind === 'image' ? '正在优先准备当前天体图像' : '正在准备本地表面纹理',
        subtitle: this.store.objectInspectorMediaKind === 'image'
          ? this.warmupText : '资源准备完成后将自动显示'
      })
    } else if (this.store.objectInspectorMediaKind === 'visual') {
      TabletInspectorFallbackVisual({
        store: this.store,
        kind: this.fallbackKind,
        starColor: this.starColor,
        iconName: this.iconName
      })
    } else {
      Row({ space: 10 }) {
        Image(getIcon(this.iconName, false)).width(24).height(24).fillColor('#8EC9E9')
        Text('暂无与当前天体准确匹配的本地资料图像').fontSize(11).fontColor('#9EC8DC').layoutWeight(1).maxLines(2)
      }
        .width('100%').height(54).padding({ left: 12, right: 12 })
        .backgroundColor('rgba(91,147,191,0.08)').borderRadius(UI_RADIUS_CONTROL)
    }
  }
}
