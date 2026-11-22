import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { objectDetailFontSize } from '../../common/ui/UiTypography'
import { zhNameOf } from '../../common/derive/labels'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { SatellitePass, StationComplexMember } from '../../pages/StellariumTypes'
import { ObjectDataTile, ObjectMetric, ObjectScheduleTile } from './DetailTiles'
import { ObjectDataRow } from './DetailRows'
import { ObjectDistanceNotice, SelectedCoordinateRows } from './DetailLiveRows'
import { SatellitePassDetails, StationComplexSection, StationCrewSection } from './SatellitePassDetails'
import { ConstellationCultureView } from './ConstellationCultureView'
import { StructuredDetailRows } from './StructuredDetailRows'
import { TabletInspectorMediaGroup } from './TabletInspectorMediaGroup'
import { ObjectMediaStore } from '../../state/ObjectMediaStore'
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 详情主卡片的"观测""坐标""资料"三页。
//
// 三页均以 `@ObjectLink` 观察 `ObjectDetailStore`；动态查值 `selectedDisplayValue(key)` 由宿主的
// `resolve` 回调注入（该逻辑被多处共用）。资料页内嵌媒体组、过境段、星座文化段与结构化资料子组件。

@Component
export struct ObjectDetailObserveTab {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumSimDateLabel') simDateLabel: string = ''
  @ObjectLink store: ObjectDetailStore
  @Prop distanceText: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  resolve: (key: string) => string = () => ''
  onJumpToCometTail: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  // 所有动态指标必须直接读 `@ObjectLink store` 属性，ArkUI 才会记录细粒度依赖并在时间轴拖动/推进时实时刷新。
  build() {
    Column({ space: 8 }) {
      if (this.store.selectedCometTailBestJD > 0 && this.store.selectedCometTailBestDate.length > 0) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('最佳彗尾时机 · ' + this.store.selectedCometTailBestDate)
              .fontSize(objectDetailFontSize(12, this.readableUi))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.textStrong)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('一键跳转至近日点附近高亮度彗尾窗口')
              .fontSize(objectDetailFontSize(11, this.readableUi))
              .fontColor(this.c.sub)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button('前往观赏')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.textStrong)
            .backgroundColor(this.c.chipActiveBg)
            .borderRadius(UI_RADIUS_CONTROL)
            .height(32)
            .padding({ left: 12, right: 12 })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
            .onClick(() => { this.onJumpToCometTail() })
        }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor(this.c.soft)
          .borderRadius(UI_RADIUS_CONTROL)
          .alignItems(VerticalAlign.Center)
      }
      Text(this.simDateLabel.length > 0 ? ('当日观测窗口 · ' + this.simDateLabel) : '今晚观测窗口')
        .fontSize(objectDetailFontSize(12, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.fourth).width('100%')
      Row({ space: 6 }) {
        ObjectScheduleTile({ label: I18n.t('s0700'), value: this.store.selectedRise })
        ObjectScheduleTile({ label: I18n.t('s0701'), value: this.store.selectedTransit })
        ObjectScheduleTile({ label: I18n.t('s0702'), value: this.store.selectedSet })
      }.width('100%')
      if (this.store.selectedApparentMagnitude.length > 0 || this.store.selectedAirmass.length > 0 || this.store.selectedExtinction.length > 0) {
        Text('大气影响').fontSize(objectDetailFontSize(12, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.fourth).width('100%').margin({ top: 3 })
        Row({ space: 8 }) {
          if (this.store.selectedApparentMagnitude.length > 0) { ObjectMetric({ label: '大气后星等', value: this.store.selectedApparentMagnitude }) }
          if (this.store.selectedExtinction.length > 0) { ObjectMetric({ label: '大气衰减', value: this.store.selectedExtinction + ' 等' }) }
          if (this.store.selectedAirmass.length > 0) { ObjectMetric({ label: '气团质量', value: this.store.selectedAirmass }) }
        }.width('100%')
      }
      if (this.store.selectedPhase.length > 0 || this.store.selectedElongation.length > 0 || this.store.selectedSize.length > 0) {
        Row({ space: 8 }) {
          if (this.store.selectedPhase.length > 0) { ObjectMetric({ label: I18n.t('i0291'), value: this.store.selectedPhase }) }
          if (this.store.selectedElongation.length > 0) { ObjectMetric({ label: I18n.t('i0255'), value: this.store.selectedElongation }) }
          if (this.store.selectedSize.length > 0) { ObjectMetric({ label: I18n.t('i0290'), value: this.store.selectedSize }) }
        }.width('100%').margin({ top: 2 })
      }
      if (this.store.selectedDistanceStatus === 'invalid_orbit' || this.store.selectedTleOutdated) {
        ObjectDistanceNotice({ text: this.distanceText })
      }
      StationCrewSection({ store: this.store, tablet: false })
      if (this.store.selectedInfo.length > 0) {
        Text(this.store.selectedInfo).fontSize(12).fontColor(this.c.detailSub).lineHeight(18).width('100%')
          .padding({ top: 8, bottom: 2 })
      }
    }
  }
}

@Component
export struct ObjectDetailCoordinateTab {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink store: ObjectDetailStore
  @Prop distanceText: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  resolve: (key: string) => string = () => ''

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 8 }) {
      Text('当前天球位置').fontSize(objectDetailFontSize(12, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.fourth).width('100%')
      ObjectDistanceNotice({ text: this.distanceText })
      SelectedCoordinateRows({ store: this.store, tablet: false })
      ObjectDataRow({ label: I18n.t('i0010'), value: zhNameOf(this.store.selectedConstellation) })
      Text('坐标会跟随时间、位置与视角更新。').fontSize(11).fontColor(this.c.tertiary).lineHeight(16).width('100%').margin({ top: 4 })
    }
  }
}

@Component
export struct ObjectDetailDataTab {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
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
  @Prop satelliteVisible: boolean
  @Prop tleEpoch: string
  @Prop cultureVisible: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  resolve: (key: string) => string = () => ''
  onLoadPasses: () => void = () => {}
  onJumpToPass: (pass: SatellitePass) => void = () => {}
  onJumpToCometTail: () => void = () => {}
  onSelectComplexMember: (member: StationComplexMember) => void = () => {}
  onMediaOpen: () => void = () => {}
  onMediaRetry: () => void = () => {}
  onModelExpand: () => void = () => {}
  onModelTouch: (event: TouchEvent) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 8 }) {
            if (this.store.selectedCometTailBestJD > 0 && this.store.selectedCometTailBestDate.length > 0) {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text('最佳彗尾时机 · ' + this.store.selectedCometTailBestDate)
                    .fontSize(objectDetailFontSize(12, this.readableUi))
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.c.textStrong)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text('一键跳转至近日点附近高亮度彗尾窗口')
                    .fontSize(objectDetailFontSize(11, this.readableUi))
                    .fontColor(this.c.sub)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Button('前往观赏')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c.textStrong)
                  .backgroundColor(this.c.chipActiveBg)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .height(32)
                  .padding({ left: 12, right: 12 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
                  .onClick(() => { this.onJumpToCometTail() })
              }
                .width('100%')
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL)
                .alignItems(VerticalAlign.Center)
            }
            Text('完整资料').fontSize(objectDetailFontSize(12, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.fourth).width('100%')
            ObjectDistanceNotice({ text: this.distanceText })
            StationCrewSection({
              store: this.store, tablet: this.tablet
            })
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
  onOpen: () => { this.onMediaOpen() },
  onRetry: () => { this.onMediaRetry() },
  onModelExpand: () => { this.onModelExpand() },
  onModelTouch: (event: TouchEvent) => { this.onModelTouch(event) }
})
            StationComplexSection({
              store: this.store, tablet: this.tablet,
              onSelectMember: (member: StationComplexMember) => { this.onSelectComplexMember(member) }
            })
            SatellitePassDetails({
              store: this.store, tablet: false, visible: this.satelliteVisible, tleEpoch: this.tleEpoch,
              onLoad: () => { this.onLoadPasses() },
              onJumpToPass: (pass: SatellitePass) => { this.onJumpToPass(pass) }
            })
            ConstellationCultureView({ store: this.store, tablet: false, visible: this.cultureVisible })
            Row({ space: 8 }) {
              Column({ space: 7 }) {
                if (this.store.selectedCoordAlt.length > 0) { ObjectDataTile({ label: '实时高度 / 方位', value: this.store.selectedCoordAlt }) }
                if (this.store.selectedMagnitude.length > 0) { ObjectDataTile({ label: I18n.t('i0007'), value: this.store.selectedMagnitude }) }
                if (this.store.selectedSize.length > 0) { ObjectDataTile({ label: I18n.t('i0290'), value: this.store.selectedSize }) }
                if (this.store.selectedApparentMagnitude.length > 0) { ObjectDataTile({ label: '大气后星等', value: this.store.selectedApparentMagnitude }) }
                if (this.store.selectedRise.length > 0) { ObjectDataTile({ label: I18n.t('s0700'), value: this.store.selectedRise }) }
                if (this.store.selectedSet.length > 0) { ObjectDataTile({ label: I18n.t('s0702'), value: this.store.selectedSet }) }
              }.layoutWeight(1)
              Column({ space: 7 }) {
                if (this.store.selectedCoordEq.length > 0) { ObjectDataTile({ label: '赤经 / 赤纬', value: this.store.selectedCoordEq.trim() }) }
                if (this.store.selectedDistance.length > 0) { ObjectDataTile({ label: I18n.t('i0011'), value: this.store.selectedDistance }) }
                if (this.store.selectedExtinction.length > 0) { ObjectDataTile({ label: '大气衰减', value: this.store.selectedExtinction + ' 等' }) }
                if (this.store.selectedAirmass.length > 0) { ObjectDataTile({ label: '气团质量', value: this.store.selectedAirmass }) }
                if (this.store.selectedTransit.length > 0) { ObjectDataTile({ label: I18n.t('s0701'), value: this.store.selectedTransit }) }
                if (this.store.selectedConstellation.length > 0) { ObjectDataTile({ label: I18n.t('i0010'), value: zhNameOf(this.store.selectedConstellation) }) }
              }.layoutWeight(1)
            }.width('100%').alignItems(VerticalAlign.Top)
            StructuredDetailRows({ store: this.store, tablet: false })
    }
  }
}
