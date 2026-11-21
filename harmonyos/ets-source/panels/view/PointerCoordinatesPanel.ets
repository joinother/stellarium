import { Theme } from '@kit.ArkUI'
import { panelFontSize, uiControlHeight } from '../../common/ui/UiTypography'
import { I18n } from '../../pages/I18n'
import { OverlayStore } from '../../state/OverlayStore'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { PointerCoordinateToggle } from './PointerCoordinateToggle'

// 本组件职责：「指针坐标」插件面板主体。
// 全部 pointerCoordinates* 展示态走 @ObjectLink store；长说明收纳于 InfoTipButton ⓘ。
@Component
export struct PointerCoordinatesPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink store: OverlayStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onSetSetting: (setting: string, value: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private ch(base: number): number { return uiControlHeight(base, this.readableUi, this.controlScale) }

  private descTipText(): string {
    const key: string = 'pointer_coord_description'
    return I18n.t(key)
  }

  build() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            Text(I18n.t('p_pointer_coordinates'))
              .fontSize(panelFontSize(15, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
            InfoTipButton({
              title: I18n.t('p_pointer_coordinates'),
              tip: this.descTipText()
            })
          }.layoutWeight(1).alignItems(VerticalAlign.Center)
          if (this.store.pointerCoordinatesLoading) {
            Row({ space: 4 }) {
              LoadingProgress().width(16).height(16).color(this.c.accent)
              Text(I18n.t('pointer_coord_loading')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
            }.alignItems(VerticalAlign.Center)
          }
          Toggle({ type: ToggleType.Switch, isOn: this.store.pointerCoordinatesEnabled })
            .selectedColor(this.c.accent)
            .onChange((value: boolean) => { this.onSetSetting('enabled', value ? '1' : '0') })
        }
          .width('100%')
          .constraintSize({ minHeight: this.ch(46) })
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)

        if (this.store.pointerCoordinatesStatus.length > 0) {
          Text(this.store.pointerCoordinatesStatus).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.warning).width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(this.c.warningBg).borderRadius(UI_RADIUS_CONTROL)
        }
        PointerCoordinateToggle({
          label: I18n.t('pointer_coord_startup'), isOn: this.store.pointerCoordinatesStartup,
          onToggle: (value: boolean) => { this.onSetSetting('enableAtStartup', value ? '1' : '0') }
        })
        PointerCoordinateToggle({
          label: I18n.t('pointer_coord_toolbar'), isOn: this.store.pointerCoordinatesButton,
          onToggle: (value: boolean) => { this.onSetSetting('showCoordinatesButton', value ? '1' : '0') }
        })
        Column({ space: 6 }) {
          Text(I18n.t('pointer_coord_system')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%').padding({ left: 2 })
          ForEach(['RaDecJ2000', 'RaDec', 'HourAngle', 'Ecliptic', 'EclipticJ2000', 'AltAzi', 'Galactic', 'Supergalactic'], (key: string) => {
            Row() {
              Text(this.store.pointerCoordinateSystemLabel(key)).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text).layoutWeight(1).maxLines(2)
              if (this.store.pointerCoordinatesSystem === key) {
                Text('✓').fontSize(15).fontColor(this.c.accent).width(24).textAlign(TextAlign.Center)
              }
            }
              .width('100%')
              .constraintSize({ minHeight: this.ch(38) })
              .padding({ left: 12, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.store.pointerCoordinatesSystem === key ? this.c.soft : this.c.bg)
              .border({ width: 0.8, color: this.store.pointerCoordinatesSystem === key ? this.c.accent : this.c.border })
              .borderRadius(UI_RADIUS_CONTROL)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
              .onClick(() => { this.onSetSetting('coordinateSystem', key) })
          }, (key: string) => key)
        }.width('100%')

        Column({ space: 6 }) {
          Text(I18n.t('pointer_coord_display_place')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%').padding({ left: 2 })
          ForEach(['TopCenter', 'TopRight', 'RightBottomCorner', 'NearMouseCursor', 'Custom'], (key: string) => {
            Row() {
              Text(this.store.pointerCoordinatesPlaceLabel(key)).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
              if (this.store.pointerCoordinatesPlace === key) {
                Text('✓').fontSize(15).fontColor(this.c.accent).width(24).textAlign(TextAlign.Center)
              }
            }
              .width('100%')
              .constraintSize({ minHeight: this.ch(38) })
              .padding({ left: 12, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.store.pointerCoordinatesPlace === key ? this.c.soft : this.c.bg)
              .border({ width: 0.8, color: this.store.pointerCoordinatesPlace === key ? this.c.accent : this.c.border })
              .borderRadius(UI_RADIUS_CONTROL)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
              .onClick(() => { this.onSetSetting('coordinatesPlace', key) })
          }, (key: string) => key)
        }.width('100%')

        Column({ space: 6 }) {
          Text(I18n.t('pointer_coord_details')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%').padding({ left: 2 })
          PointerCoordinateToggle({
            label: I18n.t('pointer_coord_constellation'), isOn: this.store.pointerCoordinatesConstellation,
            onToggle: (value: boolean) => { this.onSetSetting('showConstellation', value ? '1' : '0') }
          })
          PointerCoordinateToggle({
            label: I18n.t('pointer_coord_crossed_lines'), isOn: this.store.pointerCoordinatesCrossedLines,
            onToggle: (value: boolean) => { this.onSetSetting('showCrossedLines', value ? '1' : '0') }
          })
          PointerCoordinateToggle({
            label: I18n.t('pointer_coord_elongation'), isOn: this.store.pointerCoordinatesElongation,
            onToggle: (value: boolean) => { this.onSetSetting('showElongation', value ? '1' : '0') }
          })
        }.width('100%')
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
  }
}
