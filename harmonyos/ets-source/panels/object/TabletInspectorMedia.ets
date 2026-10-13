import hilog from '@ohos.hilog'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { ObjectMediaStore } from '../../state/ObjectMediaStore'

// 天体检查器媒体区的分支组件：图像卡、提示行、模型块、进度行与示意图。
//
// 判定条件由宿主（`TabletInspectorMediaGroup`）给出，每个分支用 `@ObjectLink`
// 直接观察 `ObjectMediaStore`；少量派生值由 `@Prop` 传入，交互用回调注入。

// 分支一：已解码出图像（image / constellation）。
@Component
export struct TabletInspectorMediaCard {
  @ObjectLink store: ObjectMediaStore
  @Prop imageHeight: number
  @Prop isPlannedModel: boolean
  onOpen: () => void = () => {}

  build() {
    Column({ space: 0 }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(this.store.objectInspectorMediaPixelMap)
          .width('100%').height(this.imageHeight).objectFit(ImageFit.Contain)
          .onComplete(() => {
            this.store.objectInspectorMediaDecoding = false
            this.store.objectInspectorMediaLoadFailed = false
            hilog.info(0x0000, 'StellariumArkUI', '[detail-media-card] image loaded uri=%{public}s', this.store.objectInspectorMediaPath)
          })
          .onError((err: ImageError) => {
            this.store.objectInspectorMediaDecoding = false
            this.store.objectInspectorMediaLoadFailed = true
            const code: string = err.error !== undefined ? err.error.code.toString() : ''
            hilog.error(0x0000, 'StellariumArkUI',
              '[detail-media-card] image failed uri=%{public}s code=%{public}s message=%{public}s',
              this.store.objectInspectorMediaPath, code, err.message)
          })
        if (this.store.objectInspectorMediaDecoding) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color('#8EC9E9')
            Text('正在解码本地资料').fontSize(10).fontColor('#E4F5FC')
          }
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .backgroundColor('rgba(2,6,12,0.72)')
            .borderRadius(UI_RADIUS_CONTROL)
        }
      }.width('100%').height(this.imageHeight)
      Row({ space: 6 }) {
        Text(this.store.objectInspectorMediaLabel + (this.store.objectInspectorMediaKind === 'constellation' &&
          this.isPlannedModel ? ' · ' + I18n.t('detail_model_planned') : ''))
          .fontSize(10).fontColor('#E4F5FC').layoutWeight(1)
        Text('点按查看').fontSize(10).fontColor('#A4D8EF')
      }
        .width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor('rgba(0,0,0,0.50)')
    }
      .width('100%').clip(true).borderRadius(UI_RADIUS_CONTROL)
      .backgroundColor('#07101B').clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onOpen() })
  }
}

// 分支二三四：无匹配资源 / 资源准备失败 / 解码失败，三者版式一致，仅图标配色、文案与底色不同。
@Component
export struct TabletInspectorNoticeRow {
  @Prop iconName: string
  @Prop iconFill: string
  @Prop title: string
  @Prop subtitle: string
  @Prop cardBackground: string
  onRetry: () => void = () => {}

  build() {
    Row({ space: 10 }) {
      Image(getIcon(this.iconName, false)).width(24).height(24).fillColor(this.iconFill)
      Column({ space: 3 }) {
        Text(this.title).fontSize(11).fontColor('#E4F5FC').width('100%')
        Text(this.subtitle).fontSize(10).fontColor('#9EC8DC').width('100%').maxLines(2)
        Row({ space: 6 }) {
          Button('重试').fontSize(10).fontColor('#E4F5FC').backgroundColor('rgba(91,147,191,0.32)')
            .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 })
            .onClick(() => { this.onRetry() })
        }
      }.layoutWeight(1)
    }
      .width('100%').height(76).padding({ left: 12, right: 12 })
      .backgroundColor(this.cardBackground).borderRadius(UI_RADIUS_CONTROL)
  }
}

// 分支五：离线三维模型（程序化或贴图球体）。
@Component
export struct TabletInspectorModelBlock {
  @ObjectLink store: ObjectMediaStore
  @Prop inlineModelSize: number
  @Prop modelRendering: boolean
  @Prop hasModelTexture: boolean
  @Prop modelNotice: string
  onExpand: () => void = () => {}
  onModelTouch: (event: TouchEvent) => void = () => {}

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.store.objectInspectorProceduralKind.length > 0 ? I18n.t('model_schematic') : I18n.t('model_offline')).fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor('#E4F5FC').width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(I18n.t('model_inline_gesture_hint'))
            .fontSize(11).fontColor(this.store.objectInspectorModelInteracting ? '#BDE8FF' : '#87B7CE')
            .width('100%').maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(I18n.t('model_expand'))
          .fontSize(12).fontColor('#CBEAFF').height(44).padding({ left: 11, right: 11 })
          .backgroundColor('rgba(35,74,98,0.58)').borderRadius(UI_RADIUS_PILL)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          .hitTestBehavior(HitTestMode.Default)
          .id('object-model-expand')
          .onClick(() => { this.onExpand() })
      }
        .width('100%').height(54).padding({ left: 11, right: 8 })
        .backgroundColor(Color.Transparent)
      Stack({ alignContent: Alignment.Center }) {
        if (this.store.objectInspectorModelPixelMap !== undefined) {
          Image(this.store.objectInspectorModelPixelMap)
            .width(this.inlineModelSize).height(this.inlineModelSize).objectFit(ImageFit.Contain)
            .hitTestBehavior(HitTestMode.None)
            .onComplete(() => {
              this.store.objectInspectorMediaDecoding = false
              this.store.objectInspectorMediaLoadFailed = false
              hilog.info(0x0000, 'StellariumArkUI',
                '[detail-media-card] sphere loaded uri=%{public}s', this.store.objectInspectorMediaPath)
            })
            .onError((err: ImageError) => {
              this.store.objectInspectorMediaDecoding = false
              this.store.objectInspectorMediaLoadFailed = true
              const code: string = err.error !== undefined ? err.error.code.toString() : ''
              hilog.error(0x0000, 'StellariumArkUI',
                '[detail-media-card] sphere failed uri=%{public}s code=%{public}s message=%{public}s',
                this.store.objectInspectorMediaPath, code, err.message)
            })
        }
        if (this.store.objectInspectorMediaDecoding || (this.modelRendering && this.store.objectInspectorModelPixelMap === undefined)) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color('#8EC9E9')
            Text(this.hasModelTexture ? '正在生成三维球体' : '正在解码本地纹理')
              .fontSize(10).fontColor('#E4F5FC')
          }
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .backgroundColor('rgba(2,6,12,0.72)')
            .borderRadius(UI_RADIUS_CONTROL)
            .align(Alignment.Center)
        }
      }
        .width(this.inlineModelSize).height(this.inlineModelSize)
        .clip(true).backgroundColor(Color.Transparent)
        .id('object-model-inline-stage')
        .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
        .onTouch((event: TouchEvent) => { this.onModelTouch(event) })
      Text(this.modelNotice)
        .fontSize(10).fontColor('#769DB1').width('100%').textAlign(TextAlign.Center)
    }
      .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 2, bottom: 3 })
  }
}

// 分支六七八：解码中 / 预热中，两段文案由宿主算好传入。
@Component
export struct TabletInspectorProgressRow {
  @Prop title: string
  @Prop subtitle: string

  build() {
    Row({ space: 10 }) {
      LoadingProgress().width(20).height(20).color('#8EC9E9')
      Column({ space: 3 }) {
        Text(this.title).fontSize(11).fontColor('#E4F5FC').width('100%').maxLines(1)
        Text(this.subtitle).fontSize(10).fontColor('#9EC8DC').width('100%').maxLines(1)
      }.layoutWeight(1)
    }
      .width('100%').height(64).padding({ left: 12, right: 12 })
      .backgroundColor('rgba(91,147,191,0.08)').borderRadius(UI_RADIUS_CONTROL)
  }
}

// 分支九：visual 类天体的示意图（星点/彗星/小行星/星系/星团/星云/星座/卫星/月球/其他）。
@Component
export struct TabletInspectorFallbackVisual {
  @ObjectLink store: ObjectMediaStore
  @Prop kind: string
  @Prop starColor: string
  @Prop iconName: string

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.kind !== 'satellite') {
          Circle().width(182).height(182).fill('rgba(65,130,170,0.10)').stroke('rgba(151,215,248,0.22)').strokeWidth(1)
        }
        if (this.kind === 'star') {
          Circle().width(112).height(112).fill(this.starColor).opacity(0.10)
          Circle().width(68).height(68).fill(this.starColor).opacity(0.28)
          Image(getIcon('catalog_star', false)).width(66).height(66).fillColor(this.starColor)
        } else if (this.kind === 'comet') {
          Ellipse().width(150).height(35).fill('rgba(133,211,255,0.14)').rotate({ angle: -24 }).translate({ x: -22, y: 10 })
          Circle().width(44).height(44).fill('rgba(208,244,255,0.76)').translate({ x: 46, y: -14 })
          Image(getIcon('catalog_comet', false)).width(104).height(104).fillColor('#B7E8FF')
        } else if (this.kind === 'asteroid') {
          Circle().width(98).height(98).fill('rgba(159,178,191,0.26)').stroke('rgba(222,239,247,0.50)').strokeWidth(1)
          Circle().width(16).height(16).fill('rgba(7,16,25,0.36)').translate({ x: -18, y: -15 })
          Circle().width(12).height(12).fill('rgba(7,16,25,0.30)').translate({ x: 20, y: 18 })
          Image(getIcon('catalog_asteroid', false)).width(72).height(72).fillColor('#D6E5EB')
        } else if (this.kind === 'galaxy') {
          Ellipse().width(150).height(50).fill('rgba(158,181,255,0.12)').stroke('rgba(171,204,255,0.38)').strokeWidth(2).rotate({ angle: -18 })
          Ellipse().width(96).height(34).fill('rgba(135,190,255,0.14)').stroke('rgba(188,217,255,0.46)').strokeWidth(2).rotate({ angle: 16 })
          Circle().width(30).height(30).fill('rgba(240,250,255,0.75)')
          Image(getIcon('catalog_galaxy', false)).width(90).height(90).fillColor('#C5DEFF')
        } else if (this.kind === 'globular-cluster' || this.kind === 'open-cluster') {
          Circle().width(124).height(124).fill(this.kind === 'globular-cluster' ? 'rgba(244,224,177,0.12)' : 'rgba(160,212,255,0.08)')
          ForEach([[-32, -20], [18, -34], [35, -4], [-5, 12], [-34, 28], [27, 32], [5, -3]], (point: number[], index: number) => {
            Circle().width(index % 2 === 0 ? 10 : 7).height(index % 2 === 0 ? 10 : 7).fill('#EAF7FF').translate({ x: point[0], y: point[1] })
          }, (point: number[], index: number) => point[0].toString() + index.toString())
          Image(getIcon('catalog_cluster', false)).width(78).height(78).fillColor('#D8EEFF')
        } else if (this.kind === 'nebula') {
          Circle().width(128).height(128).fill('rgba(143,128,210,0.13)')
          Ellipse().width(146).height(78).fill('rgba(117,190,222,0.16)').rotate({ angle: -22 })
          Ellipse().width(92).height(116).fill('rgba(222,137,174,0.13)').rotate({ angle: 24 })
          Image(getIcon('catalog_nebula', false)).width(88).height(88).fillColor('#D7E8FF')
        } else if (this.kind === 'constellation') {
          ForEach([[-54, 22], [-26, -34], [8, -8], [42, -44], [54, 32]], (point: number[], index: number) => {
            Circle().width(9).height(9).fill('#DFF5FF').translate({ x: point[0], y: point[1] })
          }, (point: number[], index: number) => point[0].toString() + index.toString())
          Image(getIcon('catalog_constellation', false)).width(116).height(116).fillColor('#C5E8FA')
        } else if (this.kind === 'satellite') {
          Image(getIcon('catalog_satellite', false)).width(72).height(72)
            .objectFit(ImageFit.Contain).fillColor('#A9DAF3')
            .hitTestBehavior(HitTestMode.None).id('object-detail-satellite-icon')
        } else if (this.kind === 'moon') {
          Image(getIcon('catalog_moon', false)).width(76).height(76).fillColor('#D9EAF5')
        } else {
          Image(getIcon(this.iconName, false)).width(92).height(92).fillColor('#C5E8FA')
        }
      }
        .width('100%').height(this.kind === 'satellite' ? 104 : 194)
        .backgroundColor(this.kind === 'satellite' ? Color.Transparent : '#07101B')
        .borderRadius(UI_RADIUS_CONTROL)
      Text(this.kind === 'satellite' ? I18n.t('detail_category_icon_notice') : this.store.objectInspectorMediaLabel)
        .fontSize(10).fontColor('#9EC8DC').width('100%').textAlign(TextAlign.Center)
        .margin({ top: 5, bottom: 3 })
    }
  }
}
