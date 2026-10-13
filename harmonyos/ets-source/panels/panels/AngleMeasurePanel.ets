import { ToolsStore } from '../../state/ToolsStore'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 角度测量面板，对应 `activePanel === 'angleMeasure'`。
//
// 角度起止点与结果文本来自 ToolsStore（@ObjectLink）；开/关与重置动作回调注入宿主。

@Component
export struct AngleMeasurePanel {
  @ObjectLink store: ToolsStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  @Prop accentColor: string
  onToggle: (enabled: boolean) => void = () => {}
  onReset: () => void = () => {}

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Row() {
          Column({ space: 3 }) {
            Text(I18n.t('panel_angle_measure')).fontSize(15).fontColor(this.textColor).width('100%')
            Text(I18n.t('angle_measure_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.store.angleMeasureEnabled })
            .enabled(!this.store.angleMeasurePending)
            .onChange((isOn: boolean) => { this.onToggle(isOn) })
        }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
          .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        if (this.store.angleMeasureEnabled) {
          Row({ space: 8 }) {
            Button(I18n.t('angle_measure_reset')).fontSize(11).fontColor(this.textColor)
              .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
              .onClick(() => { this.onReset() })
            Button(I18n.t('angle_measure_finish')).fontSize(11).fontColor('#FFFFFF')
              .backgroundColor(this.accentColor).borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
              .enabled(!this.store.angleMeasurePending)
              .onClick(() => { this.onToggle(false) })
          }.width('100%')
        }
        if (this.store.angleMeasureHasStart && !this.store.angleMeasureHasEnd) {
          Text(I18n.t('angle_measure_second_point')).fontSize(12).fontColor('#FFD59A').width('100%')
            .padding({ left: 10, right: 10, top: 10, bottom: 10 })
            .backgroundColor('rgba(194, 128, 36, 0.14)').borderRadius(UI_RADIUS_CONTROL)
        }
        if (this.store.angleMeasureHasEnd && this.store.angleMeasureText.length > 0) {
          Column({ space: 4 }) {
            Text(I18n.t('angle_measure_result')).fontSize(11).fontColor(this.subColor).width('100%')
            Text(this.store.angleMeasureText).fontSize(24).fontColor(this.accentColor).width('100%')
          }.width('100%').padding(12).backgroundColor('rgba(91,147,191,0.12)').borderRadius(UI_RADIUS_CONTROL)
        }
        Text(I18n.t('angle_measure_touch_hint')).fontSize(11).fontColor(this.subColor).width('100%').maxLines(3)
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 12 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }
}
