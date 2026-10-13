import { I18n } from '../../pages/I18n'
import { OverlayStore } from '../../state/OverlayStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { PointerCoordinateToggle } from './PointerCoordinateToggle'

// 本组件职责：「指针坐标」插件面板主体。
//
// 组件收一个 store、五个夜视色与一个写回回调：
//   - 全部 pointerCoordinates* 展示态走 @ObjectLink store（实时刷新）；
//   - 六个开关行走 `PointerCoordinateToggle` 组件（@Prop isOn 保证开关态实时刷新）；
//   - 两个单选列表（坐标系 / 显示位置）的选中态直接读 store；
//   - native 桥 `setPointerCoordinates(setting|value)` 由宿主提供，以 `onSetSetting(setting, value)` 注入。
@Component
export struct PointerCoordinatesPanel {
  @ObjectLink store: OverlayStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop lineColor: string
  onSetSetting: (setting: string, value: string) => void = () => {}

  build() {
    Scroll() {
      Column({ space: 8 }) {
        if (this.store.pointerCoordinatesLoading) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(this.accentColor)
            Text(I18n.t('pointer_coord_loading')).fontSize(11).fontColor(this.subColor)
          }.width('100%').height(42).justifyContent(FlexAlign.Center)
        }
        if (this.store.pointerCoordinatesStatus.length > 0) {
          Text(this.store.pointerCoordinatesStatus).fontSize(11).fontColor('#FFD59A').width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor('rgba(194,128,36,0.14)').borderRadius(UI_RADIUS_CONTROL)
        }
        Text(I18n.t('pointer_coord_description')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(3)
        PointerCoordinateToggle({
          label: I18n.t('pointer_coord_enabled'), isOn: this.store.pointerCoordinatesEnabled,
          textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, lineColor: this.lineColor,
          onToggle: (value: boolean) => { this.onSetSetting('enabled', value ? '1' : '0') }
        })
        PointerCoordinateToggle({
          label: I18n.t('pointer_coord_startup'), isOn: this.store.pointerCoordinatesStartup,
          textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, lineColor: this.lineColor,
          onToggle: (value: boolean) => { this.onSetSetting('enableAtStartup', value ? '1' : '0') }
        })
        PointerCoordinateToggle({
          label: I18n.t('pointer_coord_toolbar'), isOn: this.store.pointerCoordinatesButton,
          textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, lineColor: this.lineColor,
          onToggle: (value: boolean) => { this.onSetSetting('showCoordinatesButton', value ? '1' : '0') }
        })
        Text(I18n.t('pointer_coord_system')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 3 })
        ForEach(['RaDecJ2000', 'RaDec', 'HourAngle', 'Ecliptic', 'EclipticJ2000', 'AltAzi', 'Galactic', 'Supergalactic'], (key: string) => {
          Row() {
            Text(this.store.pointerCoordinateSystemLabel(key)).fontSize(12).fontColor(this.textColor).layoutWeight(1).maxLines(2)
            if (this.store.pointerCoordinatesSystem === key) {
              Text('✓').fontSize(15).fontColor(this.accentColor).width(24).textAlign(TextAlign.Center)
            }
          }
            .width('100%').padding({ left: 10, right: 8, top: 7, bottom: 7 })
            .backgroundColor(this.store.pointerCoordinatesSystem === key ? 'rgba(107,163,214,0.16)' : this.panelColor)
            .border({ width: 1, color: this.store.pointerCoordinatesSystem === key ? 'rgba(107,163,214,0.28)' : this.lineColor })
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onSetSetting('coordinateSystem', key) })
        }, (key: string) => key)
        Text(I18n.t('pointer_coord_display_place')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 3 })
        ForEach(['TopCenter', 'TopRight', 'RightBottomCorner', 'NearMouseCursor', 'Custom'], (key: string) => {
          Row() {
            Text(this.store.pointerCoordinatesPlaceLabel(key)).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            if (this.store.pointerCoordinatesPlace === key) {
              Text('✓').fontSize(15).fontColor(this.accentColor).width(24).textAlign(TextAlign.Center)
            }
          }
            .width('100%').padding({ left: 10, right: 8, top: 7, bottom: 7 })
            .backgroundColor(this.store.pointerCoordinatesPlace === key ? 'rgba(107,163,214,0.16)' : this.panelColor)
            .border({ width: 1, color: this.store.pointerCoordinatesPlace === key ? 'rgba(107,163,214,0.28)' : this.lineColor })
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onSetSetting('coordinatesPlace', key) })
        }, (key: string) => key)
        Text(I18n.t('pointer_coord_details')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 3 })
        PointerCoordinateToggle({
          label: I18n.t('pointer_coord_constellation'), isOn: this.store.pointerCoordinatesConstellation,
          textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, lineColor: this.lineColor,
          onToggle: (value: boolean) => { this.onSetSetting('showConstellation', value ? '1' : '0') }
        })
        PointerCoordinateToggle({
          label: I18n.t('pointer_coord_crossed_lines'), isOn: this.store.pointerCoordinatesCrossedLines,
          textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, lineColor: this.lineColor,
          onToggle: (value: boolean) => { this.onSetSetting('showCrossedLines', value ? '1' : '0') }
        })
        PointerCoordinateToggle({
          label: I18n.t('pointer_coord_elongation'), isOn: this.store.pointerCoordinatesElongation,
          textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, lineColor: this.lineColor,
          onToggle: (value: boolean) => { this.onSetSetting('showElongation', value ? '1' : '0') }
        })
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 12 })
    }
      .width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }
}
