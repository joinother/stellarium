import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { EquationOfTimeStore } from '../../state/EquationOfTimeStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 时间方程（均时差）块：标题开关 + 当前值 + 三个显示选项 + 失败提示。
// 开关状态直接读 store，避免参数化 @Builder 冻结导致的「要重开面板才更新」。
// 主题色走「机制四」：@State c: ThemeSlots via onWillApplyTheme。
@Component
export struct EquationOfTimeBlock {
  @ObjectLink store: EquationOfTimeStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (setting: string, enabled: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private displayText(): string {
    const signedMinutes = (this.store.equationOfTimeInverted ? -1 : 1) * this.store.equationOfTimeMinutes
    const sign = signedMinutes >= 0 ? '+' : '-'
    const absoluteMinutes = Math.abs(signedMinutes)
    if (!this.store.equationOfTimeMsFormat) return sign + absoluteMinutes.toFixed(1) + ' ' + I18n.t('equation_of_time_minutes')
    const wholeMinutes = Math.floor(absoluteMinutes)
    const seconds = Math.round((absoluteMinutes - wholeMinutes) * 60)
    const normalizedMinutes = seconds >= 60 ? wholeMinutes + 1 : wholeMinutes
    const normalizedSeconds = seconds >= 60 ? 0 : seconds
    return sign + normalizedMinutes.toString() + ':' + (normalizedSeconds < 10 ? '0' : '') + normalizedSeconds.toString()
  }

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text(I18n.t('equation_of_time_title')).fontSize(12).fontColor(this.c.text).width('100%')
          Text(I18n.t('equation_of_time_hint')).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.store.equationOfTimeLoading) {
          LoadingProgress().width(18).height(18).color(this.c.accent)
        }
        Toggle({ type: ToggleType.Switch, isOn: this.store.equationOfTimeEnabled })
          .enabled(!this.store.equationOfTimeLoading)
          .onChange((v: boolean) => { this.onToggle('enabled', v) })
      }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
      Row() {
        Text(I18n.t('equation_of_time_value')).fontSize(11).fontColor(this.c.sub).layoutWeight(1)
        Text(this.displayText()).fontSize(13).fontColor(this.c.text)
      }.width('100%').padding({ left: 10, right: 10, top: 4, bottom: 4 })
      Row() {
        Text(I18n.t('equation_of_time_ms_format')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.store.equationOfTimeMsFormat })
          .enabled(!this.store.equationOfTimeLoading)
          .onChange((v: boolean) => { this.onToggle('msFormat', v) })
      }.width('100%').padding({ left: 10, right: 10, top: 4, bottom: 4 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
      Row() {
        Text(I18n.t('equation_of_time_inverted')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.store.equationOfTimeInverted })
          .enabled(!this.store.equationOfTimeLoading)
          .onChange((v: boolean) => { this.onToggle('inverted', v) })
      }.width('100%').padding({ left: 10, right: 10, top: 4, bottom: 4 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
      Row() {
        Text(I18n.t('equation_of_time_startup')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.store.equationOfTimeStartup })
          .enabled(!this.store.equationOfTimeLoading)
          .onChange((v: boolean) => { this.onToggle('enableAtStartup', v) })
      }.width('100%').padding({ left: 10, right: 10, top: 4, bottom: 4 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
      if (this.store.equationOfTimeStatus.length > 0) {
        Text(this.store.equationOfTimeStatus).fontSize(10).fontColor(this.c.warning).width('100%').padding({ left: 10, right: 10 })
      }
    }.width('100%')
  }
}
