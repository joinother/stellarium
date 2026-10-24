import { Theme } from '@kit.ArkUI'
import { ASTRONOMY_GUIDES, AstronomyGuide } from '../../common/derive/AstronomyGuide'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 脚本面板顶部的天文导览库。
//
// 启动某条导览回注 executeGuideRequest。

@Component
export struct GuideLibrary {
  @Prop sessionActive: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onStartGuide: (id: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 10 }) {
      Text(I18n.t('guide_library')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.c.text).width('100%')
      Text(I18n.t('guide_library_hint')).fontSize(13).fontColor(this.c.sub).width('100%')
      ForEach(ASTRONOMY_GUIDES, (guide: AstronomyGuide) => {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 6 }) {
            Text(I18n.t(guide.title)).fontSize(15).fontColor(this.c.text).width('100%')
            Text(guide.steps.length.toString() + ' · ' + I18n.t('guide_stations')).fontSize(12).fontColor(this.c.sub).width('100%')
          }.width('100%').padding(14)
        }.id('guide-start-' + guide.id).width('100%').backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
          .enabled(!this.sessionActive).onClick(() => { this.onStartGuide(guide.id) })
      }, (guide: AstronomyGuide) => guide.id)
      Text(I18n.t('guide_legacy')).fontSize(15).fontColor(this.c.text).width('100%').margin({ top: 12 })
    }
      .width('100%')
  }
}
