import { I18n } from '../../pages/I18n'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { ObjectDataTile, ObjectMetric, ObjectScheduleTile } from './DetailTiles'
import { ObjectDataRow } from './DetailRows'
import { ObjectDistanceNotice, SelectedCoordinateRows } from './DetailLiveRows'
import { SatellitePassDetails } from './SatellitePassDetails'
import { ConstellationCultureView } from './ConstellationCultureView'
import { StructuredDetailRows } from './StructuredDetailRows'
import { TabletInspectorMediaGroup } from './TabletInspectorMediaGroup'
import { ObjectMediaStore } from '../../state/ObjectMediaStore'

// 详情主卡片的"观测""坐标""资料"三页。
//
// 三页均以 `@ObjectLink` 观察 `ObjectDetailStore`；动态查值 `selectedDisplayValue(key)` 由宿主的
// `resolve` 回调注入（该逻辑被多处共用）。资料页内嵌媒体组、过境段、星座文化段与结构化资料子组件。

@Component
export struct ObjectDetailObserveTab {
  @ObjectLink store: ObjectDetailStore
  @Prop distanceText: string
  resolve: (key: string) => string = () => ''

  build() {
    Column({ space: 8 }) {
      Text('今晚观测窗口').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%')
      Row({ space: 6 }) {
        ObjectScheduleTile({ label: I18n.t('s0700'), value: this.resolve('selectedRise') })
        ObjectScheduleTile({ label: I18n.t('s0701'), value: this.resolve('selectedTransit') })
        ObjectScheduleTile({ label: I18n.t('s0702'), value: this.resolve('selectedSet') })
      }.width('100%')
      if (this.store.selectedApparentMagnitude.length > 0 || this.store.selectedAirmass.length > 0 || this.store.selectedExtinction.length > 0) {
        Text('大气影响').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%').margin({ top: 3 })
        Row({ space: 8 }) {
          if (this.store.selectedApparentMagnitude.length > 0) { ObjectMetric({ label: '大气后星等', value: this.resolve('selectedApparentMagnitude') }) }
          if (this.store.selectedExtinction.length > 0) { ObjectMetric({ label: '大气衰减', value: this.resolve('extinctionUnits') }) }
          if (this.store.selectedAirmass.length > 0) { ObjectMetric({ label: '气团质量', value: this.resolve('selectedAirmass') }) }
        }.width('100%')
      }
      if (this.store.selectedPhase.length > 0 || this.store.selectedElongation.length > 0 || this.store.selectedSize.length > 0) {
        Row({ space: 8 }) {
          if (this.store.selectedPhase.length > 0) { ObjectMetric({ label: I18n.t('i0291'), value: this.resolve('selectedPhase') }) }
          if (this.store.selectedElongation.length > 0) { ObjectMetric({ label: I18n.t('i0255'), value: this.resolve('selectedElongation') }) }
          if (this.store.selectedSize.length > 0) { ObjectMetric({ label: I18n.t('i0290'), value: this.resolve('selectedSize') }) }
        }.width('100%').margin({ top: 2 })
      }
      if (this.store.selectedDistanceStatus === 'invalid_orbit' || this.store.selectedTleOutdated) {
        ObjectDistanceNotice({ text: this.distanceText })
      }
      if (this.store.selectedInfo.length > 0) {
        Text(this.store.selectedInfo).fontSize(12).fontColor('#C3DDEB').lineHeight(18).width('100%')
          .padding({ top: 8, bottom: 2 })
      }
    }
  }
}

@Component
export struct ObjectDetailCoordinateTab {
  @ObjectLink store: ObjectDetailStore
  @Prop distanceText: string
  resolve: (key: string) => string = () => ''

  build() {
    Column({ space: 8 }) {
      Text('当前天球位置').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%')
      ObjectDistanceNotice({ text: this.distanceText })
      SelectedCoordinateRows({ store: this.store, tablet: false })
      ObjectDataRow({ label: I18n.t('i0010'), value: this.resolve('selectedConstellation') })
      Text('坐标会跟随时间、位置与视角更新。').fontSize(11).fontColor('#8FBBD6').lineHeight(16).width('100%').margin({ top: 4 })
    }
  }
}

@Component
export struct ObjectDetailDataTab {
  @ObjectLink store: ObjectDetailStore
  @ObjectLink mediaStore: ObjectMediaStore
  @Prop tablet: boolean
  @Prop distanceText: string
  @Prop iconName: string
  @Prop imageHeight: number
  @Prop inlineModelSize: number
  @Prop modelReady: boolean
  @Prop modelRendering: boolean
  @Prop hasModelTexture: boolean
  @Prop modelNotice: string
  @Prop warmupText: string
  @Prop fallbackKind: string
  @Prop starColor: string
  @Prop satelliteVisible: boolean
  @Prop tleEpoch: string
  @Prop accent: string
  @Prop cultureVisible: boolean
  @Prop textColor: string
  resolve: (key: string) => string = () => ''
  onLoadPasses: () => void = () => {}
  onMediaOpen: () => void = () => {}
  onMediaRetry: () => void = () => {}
  onModelExpand: () => void = () => {}
  onModelTouch: (event: TouchEvent) => void = () => {}

  build() {
    Column({ space: 8 }) {
            Text('完整资料').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%')
            ObjectDistanceNotice({ text: this.distanceText })
            TabletInspectorMediaGroup({
  store: this.mediaStore,
  detailStore: this.store,
  isPlannedModel: this.store.selectedDetailModel !== undefined && this.store.selectedDetailModel.state === 'planned',
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
  onOpen: () => { this.onMediaOpen() },
  onRetry: () => { this.onMediaRetry() },
  onModelExpand: () => { this.onModelExpand() },
  onModelTouch: (event: TouchEvent) => { this.onModelTouch(event) }
})
            SatellitePassDetails({ store: this.store, tablet: false, visible: this.satelliteVisible, tleEpoch: this.tleEpoch, accent: this.accent, onLoad: () => { this.onLoadPasses() } })
            ConstellationCultureView({ store: this.store, tablet: false, visible: this.cultureVisible, textColor: this.textColor })
            Row({ space: 8 }) {
              Column({ space: 7 }) {
                if (this.store.selectedCoordAlt.length > 0) { ObjectDataTile({ label: '实时高度 / 方位', value: this.resolve('selectedCoordAlt') }) }
                if (this.store.selectedMagnitude.length > 0) { ObjectDataTile({ label: I18n.t('i0007'), value: this.resolve('selectedMagnitude') }) }
                if (this.store.selectedSize.length > 0) { ObjectDataTile({ label: I18n.t('i0290'), value: this.resolve('selectedSize') }) }
                if (this.store.selectedApparentMagnitude.length > 0) { ObjectDataTile({ label: '大气后星等', value: this.resolve('selectedApparentMagnitude') }) }
                if (this.store.selectedRise.length > 0) { ObjectDataTile({ label: I18n.t('s0700'), value: this.resolve('selectedRise') }) }
                if (this.store.selectedSet.length > 0) { ObjectDataTile({ label: I18n.t('s0702'), value: this.resolve('selectedSet') }) }
              }.layoutWeight(1)
              Column({ space: 7 }) {
                if (this.store.selectedCoordEq.length > 0) { ObjectDataTile({ label: '赤经 / 赤纬', value: this.resolve('selectedCoordEq') }) }
                if (this.store.selectedDistance.length > 0) { ObjectDataTile({ label: I18n.t('i0011'), value: this.resolve('selectedDistance') }) }
                if (this.store.selectedExtinction.length > 0) { ObjectDataTile({ label: '大气衰减', value: this.resolve('extinctionUnits') }) }
                if (this.store.selectedAirmass.length > 0) { ObjectDataTile({ label: '气团质量', value: this.resolve('selectedAirmass') }) }
                if (this.store.selectedTransit.length > 0) { ObjectDataTile({ label: I18n.t('s0701'), value: this.resolve('selectedTransit') }) }
                if (this.store.selectedConstellation.length > 0) { ObjectDataTile({ label: I18n.t('i0010'), value: this.resolve('selectedConstellation') }) }
              }.layoutWeight(1)
            }.width('100%').alignItems(VerticalAlign.Top)
            StructuredDetailRows({ store: this.store, tablet: false })
    }
  }
}
