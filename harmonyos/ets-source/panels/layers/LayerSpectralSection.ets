import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { SurveyStore } from '../../state/SurveyStore'
import { SpectralDataset } from '../../common/types/StellariumTypes'

// 「巡天」标签页内的多波段图层区块：巡天状态文案 + 刷新、数据集列表（打开 / 已显示）、
// 状态文案与关闭。宿主持有 SurveyStore 与四个动作回调。
@Component
export struct LayerSpectralSection {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink surveyStore: SurveyStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onRefreshSurvey: () => void = () => {}
  onSelectSpectral: (id: string) => void = () => {}
  onCloseSpectral: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 0 }) {
      Row() {
        Text(I18n.t('i0215')).fontSize(10).fontColor(this.c.sub).layoutWeight(1)
        Button('刷新').fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text).backgroundColor(this.c.bg)
          .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 34 : 28).padding({ left: 10, right: 10 })
          .onClick(() => { this.onRefreshSurvey() })
      }.width('100%').margin({ top: 10 })
      Text(I18n.t('survey_usage')).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub).width('100%').maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 6 })
      Text(this.surveyStore.surveyStateText).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%').margin({ top: 8 })
      Column({ space: 6 }) {
        ForEach(this.surveyStore.spectralDatasets, (dataset: SpectralDataset) => {
          Row() {
            Column({ space: 2 }) {
              Text(dataset.title).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
              Text(dataset.band + ' · ' + dataset.source).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text(this.surveyStore.spectralActiveId === dataset.id ? '已显示' : (dataset.loading === true ? '加载中' : '打开'))
              .fontSize(panelFontSize(10, this.readableUi))
              .fontColor(this.surveyStore.spectralActiveId === dataset.id ? this.c.accent : this.c.text)
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
.backgroundColor(this.surveyStore.spectralActiveId === dataset.id ? this.c.softStrong : this.c.bg)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSelectSpectral(dataset.id) })
           }
           .width('100%')
           .padding({ left: 8, right: 8, top: 6, bottom: 6 })
           .backgroundColor(this.c.soft)
          .border({ width: 1, color: this.surveyStore.spectralActiveId === dataset.id ? this.c.chipActiveBorder : this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
        }, (dataset: SpectralDataset) => dataset.id)
      }.width('100%').margin({ top: 8 })
      Text(this.surveyStore.spectralStateText).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(I18n.t('survey_alignment_hint')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%').maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 4 })
      Button('关闭多波段图层').fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.text).backgroundColor(this.c.bg)
        .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 32 : 28).padding({ left: 10, right: 10 }).margin({ top: 6 })
        .onClick(() => { this.onCloseSpectral() })
    }.width('100%')
  }
}
