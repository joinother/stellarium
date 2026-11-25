import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL, UI_RADIUS_TAG } from '../../common/ui/UiTokens'
import { SurveyStore } from '../../state/SurveyStore'
import { SpectralDataset } from '../../common/types/StellariumTypes'

// 「巡天」标签页内的多波段图层区块：巡天状态文案 + 刷新、全电磁波谱数据集列表（点击切换/关闭）、
// 状态文案与关闭。宿主持有 SurveyStore 与三个动作回调。
@Component
export struct LayerSpectralSection {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink surveyStore: SurveyStore
  @Prop @Watch('onHipsEnabledChanged') hipsEnabled: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onRefreshSurvey: () => void = () => {}
  onSelectSpectral: (id: string) => void = () => {}
  onCloseSpectral: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private onHipsEnabledChanged(): void {
    // 顶部预设切换、快捷键或 TOAST 互斥关闭 HiPS 开关时，自动同步下方多波段选中态。
    this.onRefreshSurvey()
  }

  private bandColor(id: string): string {
    if (this.c.isNight) return '#C44536'
    if (id === 'dss2-color') return '#8AB4F8'
    if (id === 'finkbeiner-ha') return '#F26B6B'
    if (id === '2mass-color') return '#F5A65B'
    if (id === 'allwise-color') return '#E08050'
    if (id === 'planck-lfi') return '#4CC3D9'
    if (id === 'haslam-radio') return '#7E9CE6'
    if (id === 'galex-nuv') return '#9B7CF7'
    if (id === 'rass-xray') return '#4FD18B'
    if (id === 'fermi-gamma') return '#F2C94C'
    return '#8AB4F8'
  }

  private statusLabel(dataset: SpectralDataset): string {
    const active = this.surveyStore.spectralActiveId === dataset.id
    if (active) {
      if (dataset.networkPolicy === 'offline-4k-complete') return '4K 全景'
      if (dataset.hdReady === true) return '4K·高清'
      if (dataset.loading === true) return dataset.offlineReady === true ? '4K·连高清' : '加载中'
      return dataset.offlineReady === true ? '4K 离线' : '已显示'
    }
    if (dataset.loading === true) return '加载中'
    return '打开'
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        Text(I18n.t('i0215')).fontSize(11).fontColor(this.c.sub).layoutWeight(1)
        Button('刷新').fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text).backgroundColor(this.c.bg)
          .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 34 : 28).padding({ left: 10, right: 10 })
          .onClick(() => { this.onRefreshSurvey() })
      }.width('100%').margin({ top: 10 })
      Text(I18n.t('survey_usage')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%').maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 6 })
      Text(this.surveyStore.surveyStateText).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%').margin({ top: 6 })
      Column({ space: 6 }) {
        ForEach(this.surveyStore.spectralDatasets, (dataset: SpectralDataset) => {
          Row({ space: 8 }) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.bandColor(dataset.id))
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(dataset.title)
                  .fontSize(panelFontSize(12, this.readableUi))
                  .fontWeight(this.surveyStore.spectralActiveId === dataset.id ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.surveyStore.spectralActiveId === dataset.id ? this.c.accent : this.c.text)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(dataset.band)
                  .fontSize(10)
                  .fontColor(this.c.sub)
                  .backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_TAG)
                  .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              }.alignItems(VerticalAlign.Center)
              Text(dataset.coverage.length > 0 ? dataset.coverage : dataset.source)
                .fontSize(panelFontSize(10, this.readableUi))
                .fontColor(this.c.sub)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text(this.statusLabel(dataset))
              .fontSize(panelFontSize(10, this.readableUi))
              .fontColor(this.surveyStore.spectralActiveId === dataset.id ? this.c.accent : this.c.text)
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .backgroundColor(this.surveyStore.spectralActiveId === dataset.id ? this.c.softStrong : this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 10, right: 8, top: 7, bottom: 7 })
          .backgroundColor(this.surveyStore.spectralActiveId === dataset.id ? this.c.accentSoft : this.c.soft)
          .border({ width: 1, color: this.surveyStore.spectralActiveId === dataset.id ? this.c.chipActiveBorder : this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
          .onClick(() => { this.onSelectSpectral(dataset.id) })
        }, (dataset: SpectralDataset) => dataset.id + '|' + (this.surveyStore.spectralActiveId === dataset.id ? '1' : '0') + '|' + (dataset.hdReady === true ? 'h' : '0') + '|' + (dataset.loading === true ? 'l' : '0'))
      }.width('100%').margin({ top: 8 })
      Text(this.surveyStore.spectralStateText).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 8 })
      Text(I18n.t('survey_alignment_hint')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%').maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 4 })
      if (this.surveyStore.spectralActiveId.length > 0) {
        Button('关闭多波段图层').fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text).backgroundColor(this.c.bg)
          .borderRadius(UI_RADIUS_CONTROL).height(this.readableUi ? 34 : 30).padding({ left: 12, right: 12 }).margin({ top: 8 })
          .onClick(() => { this.onCloseSpectral() })
      }
    }.width('100%')
  }
}
