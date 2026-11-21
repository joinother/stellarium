import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { ArchaeoPlanetOption } from '../../pages/MainWindowModels'
import { ArchaeoStore } from '../../state/ArchaeoStore'
import { ArchaeoToggleRow } from '../../common/ui/ArchaeoToggleRow'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'

// 考古学线条面板，对应 `activePanel === 'archaeoLines'`。
// 加载态与各开关/线宽来自 ArchaeoStore（@ObjectLink）；设置动作回调注入宿主。

@Component
export struct ArchaeoLinesPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink archaeoStore: ArchaeoStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSetSetting: (setting: string, value: string) => void = () => {}
  onLineWidthPreview: (value: number) => void = () => {}
  onSetLineWidth: (value: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private fs(base: number): number { return uiFontSize(base, this.readableUi, this.uiFontScale) }
  private ch(base: number): number { return uiControlHeight(base, this.readableUi, this.controlScale) }

  build() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            Text(I18n.t('archaeo_lines_title'))
              .fontSize(this.fs(15)).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
            InfoTipButton({
              title: I18n.t('archaeo_lines_title'),
              tip: I18n.t('archaeo_lines_hint')
            })
          }.layoutWeight(1).alignItems(VerticalAlign.Center)
          if (this.archaeoStore.archaeoLoading) { LoadingProgress().width(20).height(20).color(this.c.accent) }
          Toggle({ type: ToggleType.Switch, isOn: this.archaeoStore.archaeoLinesEnabled })
            .selectedColor(this.c.accent)
            .enabled(!this.archaeoStore.archaeoLoading)
            .onChange((v: boolean) => { this.onSetSetting('enabled', v ? '1' : '0') })
        }
          .width('100%')
          .constraintSize({ minHeight: this.ch(46) })
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)

        if (this.archaeoStore.archaeoStatus.length > 0) {
          Text(this.archaeoStore.archaeoStatus).fontSize(this.fs(11)).fontColor(this.c.warning).width('100%').padding({ left: 10, right: 10 })
        }

        Column({ space: 6 }) {
          Text('太阳与月球极值参考线').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 4 })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_equinox'), isOn: this.archaeoStore.archaeoEquinox, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('equinox', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_solstices'), isOn: this.archaeoStore.archaeoSolstices, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('solstices', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_crossquarters'), isOn: this.archaeoStore.archaeoCrossquarters, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('crossquarters', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_major'), isOn: this.archaeoStore.archaeoMajorStandstills, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('majorStandstills', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_minor'), isOn: this.archaeoStore.archaeoMinorStandstills, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('minorStandstills', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_polar'), isOn: this.archaeoStore.archaeoPolarCircles, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('polarCircles', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_zenith'), isOn: this.archaeoStore.archaeoZenithPassage, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('zenithPassage', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_nadir'), isOn: this.archaeoStore.archaeoNadirPassage, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('nadirPassage', v ? '1' : '0') } })
        }.width('100%')

        Column({ space: 6 }) {
          Text('实时天体与选中目标线').fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').padding({ left: 4 })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_selected'), isOn: this.archaeoStore.archaeoSelectedObject, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('selectedObject', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_azimuth'), isOn: this.archaeoStore.archaeoSelectedObjectAzimuth, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('selectedObjectAzimuth', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_hour_angle'), isOn: this.archaeoStore.archaeoSelectedObjectHourAngle, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('selectedObjectHourAngle', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_sun'), isOn: this.archaeoStore.archaeoCurrentSun, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('currentSun', v ? '1' : '0') } })
          ArchaeoToggleRow({ label: I18n.t('archaeo_lines_moon'), isOn: this.archaeoStore.archaeoCurrentMoon, canToggle: !this.archaeoStore.archaeoLoading, onToggle: (v: boolean) => { this.onSetSetting('currentMoon', v ? '1' : '0') } })
        }.width('100%')

        Column({ space: 8 }) {
          Text(I18n.t('archaeo_lines_planet')).fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%')
          Row({ space: 5 }) {
            ForEach([
              { id: 0, label: I18n.t('archaeo_planet_none'), value: 'none' },
              { id: 1, label: '水星', value: 'Mercury' }, { id: 2, label: '金星', value: 'Venus' },
              { id: 3, label: '火星', value: 'Mars' }, { id: 4, label: '木星', value: 'Jupiter' },
              { id: 5, label: '土星', value: 'Saturn' }
            ] as ArchaeoPlanetOption[], (planet: ArchaeoPlanetOption) => {
              Text(planet.label).fontSize(this.fs(11.5))
                .fontWeight(this.archaeoStore.archaeoCurrentPlanet === planet.id ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.archaeoStore.archaeoCurrentPlanet === planet.id ? this.c.onAccent : this.c.sub)
                .textAlign(TextAlign.Center).layoutWeight(1)
                .constraintSize({ minHeight: this.ch(36) })
                .padding({ top: 7, bottom: 7 })
                .backgroundColor(this.archaeoStore.archaeoCurrentPlanet === planet.id ? this.c.accent : this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL)
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
                .onClick(() => { this.onSetSetting('currentPlanet', planet.value) })
            }, (planet: ArchaeoPlanetOption) => planet.id.toString())
          }.width('100%')

          Row() {
            Text(I18n.t('archaeo_lines_width')).fontSize(this.fs(12.5)).fontColor(this.c.text).layoutWeight(1)
            Text(this.archaeoStore.archaeoLineWidth.toString() + ' px').fontSize(this.fs(12)).fontColor(this.c.accent)
          }.width('100%').padding({ top: 4 })
          Slider({ value: this.archaeoStore.archaeoLineWidth, min: 1, max: 8, step: 1, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .width('100%').trackColor(this.c.soft).selectedColor(this.c.accent)
            .onChange((v: number, mode: SliderChangeMode) => {
              const width = Math.round(v)
              this.onLineWidthPreview(width)
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.onSetLineWidth(width)
            })
        }
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
  }
}
