import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { ToolsStore } from '../../state/ToolsStore'
import { I18n } from '../../pages/I18n'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'

// 角度测量面板，对应 `activePanel === 'angleMeasure'`。
// 角度起止点与结果文本来自 ToolsStore（@ObjectLink）；开/关与重置动作回调注入宿主。

@Component
export struct AngleMeasurePanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink store: ToolsStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (enabled: boolean) => void = () => {}
  onReset: () => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private fs(base: number): number { return uiFontSize(base, this.readableUi, this.uiFontScale) }
  private ch(base: number): number { return uiControlHeight(base, this.readableUi, this.controlScale) }

  build() {
      Column({ space: 10 }) {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Row({ space: 6 }) {
              Text(I18n.t('panel_angle_measure'))
                .fontSize(this.fs(15)).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
              InfoTipButton({
                title: I18n.t('panel_angle_measure'),
                tip: I18n.t('angle_measure_hint') + '\n' + I18n.t('angle_measure_touch_hint')
              })
            }.layoutWeight(1).alignItems(VerticalAlign.Center)
            Toggle({ type: ToggleType.Switch, isOn: this.store.angleMeasureEnabled })
              .selectedColor(this.c.accent)
              .enabled(!this.store.angleMeasurePending)
              .onChange((isOn: boolean) => { this.onToggle(isOn) })
          }.width('100%').constraintSize({ minHeight: this.ch(40) }).alignItems(VerticalAlign.Center)

          if (this.store.angleMeasureEnabled) {
            Row({ space: 8 }) {
              Button(I18n.t('angle_measure_reset')).fontSize(this.fs(12)).fontColor(this.c.text)
                .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: this.ch(38) }).layoutWeight(1)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.onReset() })
              Button(I18n.t('angle_measure_finish')).fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.onAccent)
                .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: this.ch(38) }).layoutWeight(1)
                .enabled(!this.store.angleMeasurePending)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.onToggle(false) })
            }.width('100%')
          }
        }
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)

        if (this.store.angleMeasureHasStart && !this.store.angleMeasureHasEnd) {
          Text(I18n.t('angle_measure_second_point')).fontSize(this.fs(12.5)).fontColor(this.c.warning).width('100%')
            .padding(12).backgroundColor(this.c.warningBg).borderRadius(UI_RADIUS_CARD)
        }
        if (this.store.angleMeasureHasEnd && this.store.angleMeasureText.length > 0) {
          Column({ space: 4 }) {
            Text(I18n.t('angle_measure_result')).fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%')
            Text(this.store.angleMeasureText).fontSize(this.fs(24)).fontWeight(FontWeight.Medium).fontColor(this.c.accent).width('100%')
          }
            .width('100%').padding(14).backgroundColor(this.c.soft)
            .border({ width: 0.6, color: this.c.accent }).borderRadius(UI_RADIUS_CARD)
        }
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
  }
}
