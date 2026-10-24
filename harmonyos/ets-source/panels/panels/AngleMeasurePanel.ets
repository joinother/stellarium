import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { ToolsStore } from '../../state/ToolsStore'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 角度测量面板，对应 `activePanel === 'angleMeasure'`。
//
// 角度起止点与结果文本来自 ToolsStore（@ObjectLink）；开/关与重置动作回调注入宿主。

@Component
export struct AngleMeasurePanel {
  @ObjectLink store: ToolsStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (enabled: boolean) => void = () => {}
  onReset: () => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Row() {
          Column({ space: 3 }) {
            Text(I18n.t('panel_angle_measure')).fontSize(15).fontColor(this.c.text).width('100%')
            Text(I18n.t('angle_measure_hint')).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.store.angleMeasureEnabled })
            .enabled(!this.store.angleMeasurePending)
            .onChange((isOn: boolean) => { this.onToggle(isOn) })
        }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        if (this.store.angleMeasureEnabled) {
          Row({ space: 8 }) {
            Button(I18n.t('angle_measure_reset')).fontSize(11).fontColor(this.c.text)
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
              .onClick(() => { this.onReset() })
            Button(I18n.t('angle_measure_finish')).fontSize(11).fontColor(this.c.textStrong)
              .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
              .enabled(!this.store.angleMeasurePending)
              .onClick(() => { this.onToggle(false) })
          }.width('100%')
        }
        if (this.store.angleMeasureHasStart && !this.store.angleMeasureHasEnd) {
          Text(I18n.t('angle_measure_second_point')).fontSize(12).fontColor(this.c.warning).width('100%')
            .padding({ left: 10, right: 10, top: 10, bottom: 10 })
            .backgroundColor(this.c.warningBg).borderRadius(UI_RADIUS_CONTROL)
        }
        if (this.store.angleMeasureHasEnd && this.store.angleMeasureText.length > 0) {
          Column({ space: 4 }) {
            Text(I18n.t('angle_measure_result')).fontSize(11).fontColor(this.c.sub).width('100%')
            Text(this.store.angleMeasureText).fontSize(24).fontColor(this.c.accent).width('100%')
          }.width('100%').padding(12).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
        }
        Text(I18n.t('angle_measure_touch_hint')).fontSize(11).fontColor(this.c.sub).width('100%').maxLines(3)
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 12 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
  }
}
