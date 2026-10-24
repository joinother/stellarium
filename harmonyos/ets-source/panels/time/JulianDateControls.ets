import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { JulianDateStore } from '../../state/JulianDateStore'
import { JulianDateInputRow } from './JulianDateInputRow'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 儒略日块：历法提示 + JD / MJD 两行输入 + 校验错误。
// 数值直接读 store，保证随时间/引擎同步实时更新。
// 主题色走「机制四」：@State c: ThemeSlots via onWillApplyTheme。
@Component
export struct JulianDateControls {
  @ObjectLink store: JulianDateStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onAdjust: (scale: string, direction: number) => void = () => {}
  onApply: (scale: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 7 }) {
      Row() {
        Text(I18n.t('julian_date')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1)
        Text(this.store.julianCalendarSystem === 'julian' ? I18n.t('julian_calendar_active') : I18n.t('gregorian_calendar_active'))
          .fontSize(10).fontColor(this.c.sub).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('58%')
      }.width('100%')
      JulianDateInputRow({
        store: this.store,
        label: I18n.t('julian_date'),
        scaleKey: 'jd',
        onAdjust: this.onAdjust,
        onApply: this.onApply
      })
      JulianDateInputRow({
        store: this.store,
        label: I18n.t('modified_julian_date'),
        scaleKey: 'mjd',
        onAdjust: this.onAdjust,
        onApply: this.onApply
      })
      Text(I18n.t('julian_date_hint')).fontSize(10).lineHeight(14).fontColor(this.c.sub).width('100%')
      if (this.store.julianDateError.length > 0) {
        Text(this.store.julianDateError).fontSize(10).fontColor(this.c.errorText).width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 9 })
    .backgroundColor(this.c.overlayScrim)
    .border({ width: 1, color: this.c.border })
    .borderRadius(UI_RADIUS_CONTROL)
    .margin({ left: 12, right: 12, top: 2, bottom: 4 })
  }
}
