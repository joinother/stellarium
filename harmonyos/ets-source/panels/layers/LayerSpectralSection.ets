import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { SurveyStore } from '../../state/SurveyStore'
import { SpectralDataset } from '../../common/types/StellariumTypes'

// 「巡天」标签页内的多波段图层区块：巡天状态文案 + 刷新、数据集列表（打开 / 已显示）、
// 状态文案与关闭。宿主持有 SurveyStore 与四个动作回调。
@Component
export struct LayerSpectralSection {
  @ObjectLink surveyStore: SurveyStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop lineColor: string
  onRefreshSurvey: () => void = () => {}
  onSelectSpectral: (id: string) => void = () => {}
  onCloseSpectral: () => void = () => {}

  build() {
    Column({ space: 0 }) {
      Row() {
        Text(I18n.t('i0215')).fontSize(10).fontColor('#CC8FB6FF').layoutWeight(1)
        Button('刷新').fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
          .onClick(() => { this.onRefreshSurvey() })
      }.width('100%').margin({ top: 10 })
      Text(I18n.t('survey_usage')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 6 })
      Text(this.surveyStore.surveyStateText).fontSize(11).fontColor(this.subColor).width('100%').margin({ top: 8 })
      Column({ space: 6 }) {
        ForEach(this.surveyStore.spectralDatasets, (dataset: SpectralDataset) => {
          Row() {
            Column({ space: 2 }) {
              Text(dataset.title).fontSize(11).fontColor(this.textColor)
              Text(dataset.band + ' · ' + dataset.source).fontSize(10).fontColor(this.subColor).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text(this.surveyStore.spectralActiveId === dataset.id ? '已显示' : (dataset.loading === true ? '加载中' : '打开'))
              .fontSize(10)
              .fontColor(this.surveyStore.spectralActiveId === dataset.id ? this.accentColor : this.textColor)
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .backgroundColor(this.surveyStore.spectralActiveId === dataset.id ? 'rgba(91,147,191,0.24)' : this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onSelectSpectral(dataset.id) })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.surveyStore.spectralActiveId === dataset.id ? 'rgba(91,147,191,0.12)' : 'rgba(255,255,255,0.035)')
          .border({ width: 1, color: this.surveyStore.spectralActiveId === dataset.id ? 'rgba(91,147,191,0.55)' : this.lineColor })
          .borderRadius(UI_RADIUS_CONTROL)
        }, (dataset: SpectralDataset) => dataset.id)
      }.width('100%').margin({ top: 8 })
      Text(this.surveyStore.spectralStateText).fontSize(10).fontColor(this.subColor).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(I18n.t('survey_alignment_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 4 })
      Button('关闭多波段图层').fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
        .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 }).margin({ top: 6 })
        .onClick(() => { this.onCloseSpectral() })
    }.width('100%')
  }
}
