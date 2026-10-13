import { I18n } from '../../pages/I18n'
import { JulianDateStore } from '../../state/JulianDateStore'
import { JulianDateInputRow } from './JulianDateInputRow'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 儒略日块：历法提示 + JD / MJD 两行输入 + 校验错误。
// 数值直接读 store，保证随时间/引擎同步实时更新。
@Component
export struct JulianDateControls {
  @ObjectLink store: JulianDateStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop inputColor: string
  onAdjust: (scale: string, direction: number) => void = () => {}
  onApply: (scale: string) => void = () => {}

  build() {
    Column({ space: 7 }) {
      Row() {
        Text(I18n.t('julian_date')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.textColor).layoutWeight(1)
        Text(this.store.julianCalendarSystem === 'julian' ? I18n.t('julian_calendar_active') : I18n.t('gregorian_calendar_active'))
          .fontSize(10).fontColor(this.subColor).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('58%')
      }.width('100%')
      JulianDateInputRow({
        store: this.store,
        label: I18n.t('julian_date'),
        scaleKey: 'jd',
        textColor: this.textColor,
        subColor: this.subColor,
        inputColor: this.inputColor,
        onAdjust: this.onAdjust,
        onApply: this.onApply
      })
      JulianDateInputRow({
        store: this.store,
        label: I18n.t('modified_julian_date'),
        scaleKey: 'mjd',
        textColor: this.textColor,
        subColor: this.subColor,
        inputColor: this.inputColor,
        onAdjust: this.onAdjust,
        onApply: this.onApply
      })
      Text(I18n.t('julian_date_hint')).fontSize(10).lineHeight(14).fontColor(this.subColor).width('100%')
      if (this.store.julianDateError.length > 0) {
        Text(this.store.julianDateError).fontSize(10).fontColor('#F59B9B').width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 9 })
    .backgroundColor('rgba(12, 18, 29, 0.62)')
    .border({ width: 1, color: 'rgba(190, 220, 240, 0.16)' })
    .borderRadius(UI_RADIUS_CONTROL)
    .margin({ left: 12, right: 12, top: 2, bottom: 4 })
  }
}
