import { I18n } from '../../pages/I18n'
import { OFFLINE_APPGALLERY_BUILD } from '../../pages/MainWindowModels'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { ObjectMediaStore } from '../../state/ObjectMediaStore'
import { TelescopeStore } from '../../state/TelescopeStore'
import { ObservingListStore } from '../../state/ObservingListStore'
import { ObjectDataRow, DetailSectionTitle } from '../object/DetailRows'
import { StructuredDetailRows } from '../object/StructuredDetailRows'
import { SelectedCoordinateRows } from '../object/DetailLiveRows'
import { TabletInspectorMediaGroup } from '../object/TabletInspectorMediaGroup'
import { SatellitePassDetails } from '../object/SatellitePassDetails'
import { Lx200ObjectControls } from '../telescope/Lx200ObjectControls'
import { QuickChipRow } from '../../common/ui/QuickChipRow'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 天体详情面板，对应 `activePanel === 'object'`。
//
// 详情/媒体/望远镜/观测列表四个 store 走 @ObjectLink；`viewLock`/`speechStatus` 与渲染管线
// 逐帧写入的 modelRendering/modelTexturePixels 仍由宿主持有并以 @Prop 传入
// （逐帧字段不入被观察 store）。原生桥动作与文案助手读宿主状态，均以回调返回。
// 分支根为并列多根，故包一层 Column()（无 space，保持原间距）。

@Component
export struct ObjectPanel {
  @ObjectLink objectDetailStore: ObjectDetailStore
  @ObjectLink objectMediaStore: ObjectMediaStore
  @ObjectLink telescopeStore: TelescopeStore
  @ObjectLink observingListStore: ObservingListStore
  @Prop fullInspectorRequested: boolean
  @Prop viewLock: boolean
  @Prop speechStatus: string
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
  @Prop satVisible: boolean
  @Prop tleEpoch: string
  @Prop textColor: string
  @Prop panelColor: string
  @Prop borderTint: string
  @Prop accentColor: string
  nameOf: (raw: string) => string = (raw: string) => raw
  typeOf: (type: string) => string = (type: string) => type
  statusOf: (en: string) => string = (en: string) => en
  displayValue: (key: string) => string = () => ''
  onChip: (id: string) => void = () => {}
  onToggleObserving: () => void = () => {}
  onGotoReselect: () => void = () => {}
  onSpeak: () => void = () => {}
  onOpenMedia: () => void = () => {}
  onRetryMedia: () => void = () => {}
  onModelExpand: () => void = () => {}
  onModelTouch: (event: TouchEvent) => void = () => {}
  onLoadSatPasses: () => void = () => {}
  onGoto: () => void = () => {}
  onSync: () => void = () => {}
  onAbort: () => void = () => {}

  build() {
    Column() {
      if (this.objectDetailStore.selectedName.length === 0) {
        Column() {
          Text(I18n.t('i0109')).fontSize(14).fontColor('#99FFFFFF').margin({ top: 20 })
          Text(I18n.t('i0110')).fontSize(12).fontColor('#CC8FB6FF').margin({ top: 6 })
        }.width('100%').height(100).justifyContent(FlexAlign.Center)
      } else {
        Row() {
          Text(this.nameOf(this.objectDetailStore.selectedName))
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF').layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').padding({ left: 4, right: 4, top: 2, bottom: 4 }).margin({ bottom: 2 })
        Row() {
          Text(this.typeOf(this.objectDetailStore.selectedType))
            .fontSize(11).fontColor('#7FB3DC')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('rgba(91, 147, 191, 0.15)').borderRadius(UI_RADIUS_CONTROL)
          Blank()
          Text(this.objectDetailStore.selectedStatus === 'Selected' && this.viewLock ? I18n.t('view_lock_status_on') : this.statusOf(this.objectDetailStore.selectedStatus))
            .fontSize(11).fontColor('#99FFFFFF')
        }.width('100%').padding({ left: 4, right: 4 }).height(20).margin({ bottom: 8 })

        // 直接绑定 store 字段：经 @Builder 参数传递会按值捕获，导致不刷新
        if (this.objectDetailStore.selectedMagnitude.length > 0) {
          Row() {
            Text(I18n.t('i0007')).fontSize(12).fontColor('#99FFFFFF').width(72)
            Text(this.objectDetailStore.selectedMagnitude).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.height(28).width('100%').padding({ left: 10, right: 10 })
        }
        if (this.objectDetailStore.selectedCoordEq.length > 0) {
          Row() {
            Text(I18n.t('i0008')).fontSize(12).fontColor('#99FFFFFF').width(72)
            Text(this.objectDetailStore.selectedCoordEq).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.height(28).width('100%').padding({ left: 10, right: 10 })
        }
        if (this.objectDetailStore.selectedCoordAlt.length > 0) {
          Row() {
            Text(I18n.t('i0009')).fontSize(12).fontColor('#99FFFFFF').width(72)
            Text(this.objectDetailStore.selectedCoordAlt).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.height(28).width('100%').padding({ left: 10, right: 10 })
        }
        if (this.objectDetailStore.selectedConstellation.length > 0) {
          Row() {
            Text(I18n.t('i0010')).fontSize(12).fontColor('#99FFFFFF').width(72)
            Text(this.nameOf(this.objectDetailStore.selectedConstellation)).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.height(28).width('100%').padding({ left: 10, right: 10 })
        }
        if (this.objectDetailStore.selectedDistance.length > 0) {
          Row() {
            Text(I18n.t('i0011')).fontSize(12).fontColor('#99FFFFFF').width(72)
            Text(this.objectDetailStore.selectedDistance).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.height(28).width('100%').padding({ left: 10, right: 10 })
        }
        if (this.objectDetailStore.selectedInfo.length > 0) {
          Text(this.objectDetailStore.selectedInfo)
            .fontSize(12)
            .fontColor('#99FFFFFF')
            .lineHeight(18)
            .width('100%')
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 10, right: 10, top: 9, bottom: 9 })
            .backgroundColor('rgba(107, 163, 214, 0.12)')
            .border({ width: 1, color: this.borderTint })
            .borderRadius(UI_RADIUS_CONTROL)
            .margin({ top: 8, bottom: 8 })
        }
        if (this.fullInspectorRequested) {
          Divider().color(this.borderTint).margin({ top: 8, bottom: 8 })
          TabletInspectorMediaGroup({
            store: this.objectMediaStore,
            detailStore: this.objectDetailStore,
            isPlannedModel: this.isPlannedModel,
            imageHeight: this.imageHeight,
            iconName: this.iconName,
            inlineModelSize: this.inlineModelSize,
            modelReady: this.modelReady,
            modelRendering: this.modelRendering,
            hasModelTexture: this.hasModelTexture,
            modelNotice: this.modelNotice,
            warmupText: this.warmupText,
            fallbackKind: this.fallbackKind,
            starColor: this.starColor,
            onOpen: () => { this.onOpenMedia() },
            onRetry: () => { this.onRetryMedia() },
            onModelExpand: () => { this.onModelExpand() },
            onModelTouch: (event: TouchEvent) => { this.onModelTouch(event) }
          })
          SatellitePassDetails({ store: this.objectDetailStore, tablet: true, visible: this.satVisible, tleEpoch: this.tleEpoch, accent: this.accentColor, onLoad: () => { this.onLoadSatPasses() } })
          DetailSectionTitle({ title: '坐标参考', tablet: true })
          SelectedCoordinateRows({ store: this.objectDetailStore, tablet: true })
          DetailSectionTitle({ title: '实时观测', tablet: true })
          ObjectDataRow({ label: '时角', value: this.displayValue('selectedHourAngle') })
          ObjectDataRow({ label: '平恒星时', value: this.displayValue('selectedMeanSiderealTime') })
          ObjectDataRow({ label: '视恒星时', value: this.displayValue('selectedApparentSiderealTime') })
          ObjectDataRow({ label: I18n.t('s0700'), value: this.displayValue('selectedRise') })
          ObjectDataRow({ label: I18n.t('s0701'), value: this.displayValue('selectedTransit') })
          ObjectDataRow({ label: I18n.t('s0702'), value: this.displayValue('selectedSet') })
          ObjectDataRow({ label: I18n.t('i0291'), value: this.displayValue('selectedPhase') })
          ObjectDataRow({ label: I18n.t('i0255'), value: this.displayValue('selectedElongation') })
          StructuredDetailRows({ store: this.objectDetailStore, tablet: false })
        }
        Row() {
          Button(this.observingListStore.observingList.includes(this.objectDetailStore.selectedName) ? I18n.t('s0739') : I18n.t('s0738'))
            .fontSize(13).fontColor("#E5FFFFFF").backgroundColor("rgba(107,163,214,0.25)")
            .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1)
            .onClick(() => { this.onToggleObserving() })
        }
        .width("100%").margin({ top: 4, bottom: 4 })
        QuickChipRow({ items: [
          { id: 'refresh', label: I18n.t('s0721') },
          { id: 'center', label: I18n.t('s0741') },
          { id: this.viewLock ? 'unlock-view' : 'lock-view', label: this.viewLock ? I18n.t('btn_unlock_view') : I18n.t('btn_lock_view') }
        ], onChip: (id: string) => { this.onChip(id) } })
        Row({ space: 6 }) {
          Button(I18n.t('i0134')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
            .onClick(() => { this.onGotoReselect() })
          Button(I18n.t('s0760')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 10, right: 10 })
            .onClick(() => { this.onSpeak() })
        }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 4, bottom: 4 })
        if (this.speechStatus.length > 0) {
          Text(this.speechStatus).fontSize(10).fontColor('#FFAA00').width('100%').padding({ left: 4, right: 4 })
        }
        if (!OFFLINE_APPGALLERY_BUILD) {
          Lx200ObjectControls({
            store: this.telescopeStore,
            onGoto: () => { this.onGoto() },
            onSync: () => { this.onSync() },
            onAbort: () => { this.onAbort() }
          })
        }
      }
    }.width('100%')
  }
}
