import { ASTRONOMY_GUIDES, AstronomyGuide } from '../../common/derive/AstronomyGuide'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 脚本面板顶部的天文导览库。
//
// 夜色配色由宿主以 @Prop 传入；启动某条导览回注 executeGuideRequest。

@Component
export struct GuideLibrary {
  @Prop textColor: string
  @Prop subColor: string
  @Prop cardBg: string
  @Prop sessionActive: boolean
  onStartGuide: (id: string) => void = () => {}

  build() {
    Column({ space: 10 }) {
      Text(I18n.t('guide_library')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.textColor).width('100%')
      Text(I18n.t('guide_library_hint')).fontSize(13).fontColor(this.subColor).width('100%')
      ForEach(ASTRONOMY_GUIDES, (guide: AstronomyGuide) => {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 6 }) {
            Text(I18n.t(guide.title)).fontSize(15).fontColor(this.textColor).width('100%')
            Text(guide.steps.length.toString() + ' · ' + I18n.t('guide_stations')).fontSize(12).fontColor(this.subColor).width('100%')
          }.width('100%').padding(14)
        }.id('guide-start-' + guide.id).width('100%').backgroundColor(this.cardBg).borderRadius(UI_RADIUS_CONTROL)
          .enabled(!this.sessionActive).onClick(() => { this.onStartGuide(guide.id) })
      }, (guide: AstronomyGuide) => guide.id)
      Text(I18n.t('guide_legacy')).fontSize(15).fontColor(this.textColor).width('100%').margin({ top: 12 })
    }
      .width('100%')
  }
}
