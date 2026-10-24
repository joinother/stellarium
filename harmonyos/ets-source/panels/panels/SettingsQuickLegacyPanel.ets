import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n, LANGUAGE_DISPLAY, SUPPORTED_LANGUAGES, PROJECTION_KEYS } from '../../pages/I18n'
import { CatalogHealthEntry } from '../../pages/MainWindowModels'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { GyroStore } from '../../state/GyroStore'
import { NightModeStore } from '../../state/NightModeStore'
import { TelescopeStore } from '../../state/TelescopeStore'
import { SkyCultureViewStore } from '../../state/SkyCultureViewStore'
import { ViewSettingsStore } from '../../state/ViewSettingsStore'
import { DevicePrivacySection } from '../settings/DeviceAndLanguageRows'
import { LayerSwitchRow } from '../layers/LayerSwitchRow'

// 「快捷设置（旧版）」面板，对应 activePanel === 'settings_quick_legacy'。
//
// FOV/投影/语言/目录健康等标量走 @Prop；速度控制、切换投影/语言/星文化/单位、
// 陀螺仪开关、隐私撤销、目录健康查表等动作回调注入宿主。

@Component
export struct SettingsQuickLegacyPanel {
  @ObjectLink gyroStore: GyroStore
  @ObjectLink nightModeStore: NightModeStore
  @ObjectLink telescopeStore: TelescopeStore
  @ObjectLink skyCultureViewStore: SkyCultureViewStore
  @ObjectLink viewSettingsStore: ViewSettingsStore
  @Prop liveMode: boolean
  @Prop fovSliderValue: number
  @Prop currentProjection: string
  @Prop selectedLanguage: string
  @Prop satelliteCatalogHealth: CatalogHealthEntry = {}
  @Prop starCatalogHealth: CatalogHealthEntry = {}
  @Prop gyroSensitivityText: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggleGyroscope: (v: boolean) => void = () => {}
  onRevoke: () => void = () => {}
  onApplyLayerSwitch: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onSpeedDown: () => void = () => {}
  onTogglePause: () => void = () => {}
  onSpeedUp: () => void = () => {}
  onFovChange: (val: number) => void = () => {}
  onSetProjection: (name: string) => void = () => {}
  onSetLanguage: (lang: string) => void = () => {}
  onSetSkyCulture: (name: string) => void = () => {}
  onSetUnits: (metric: boolean) => void = () => {}
  catalogHealthTextOf: (title: string, health: CatalogHealthEntry) => string = () => ''
  catalogHealthColorOf: (health: CatalogHealthEntry) => ResourceColor = () => ''

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  build() {
      Scroll() {
        Column({ space: 0 }) {
          DevicePrivacySection({ gyroscopeEnabled: this.gyroStore.gyroscopeEnabled, sensitivityText: this.gyroSensitivityText, onToggleGyroscope: (v: boolean) => { this.onToggleGyroscope(v) }, onRevoke: () => { this.onRevoke() } })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.c.border)
            .margin({ top: 6, bottom: 8 })
          Text('内置数据目录').fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
          Column({ space: 4 }) {
            Text(this.catalogHealthTextOf('卫星目录', this.satelliteCatalogHealth)).fontSize(12).fontColor(this.catalogHealthColorOf(this.satelliteCatalogHealth)).maxLines(2)
            Text(this.catalogHealthTextOf('基础星表', this.starCatalogHealth)).fontSize(12).fontColor(this.catalogHealthColorOf(this.starCatalogHealth)).maxLines(2)
          }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.c.border)
            .margin({ top: 2, bottom: 8 })
          Text(I18n.t('i0114')).fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
          LayerSwitchRow({ label: I18n.t('s0300'), isOn: this.nightModeStore.nightMode, onToggle: (value: boolean) => { this.onApplyLayerSwitch('actionShow_Night_Mode', '', value) } })
          LayerSwitchRow({ label: I18n.t('s0301'), isOn: this.telescopeStore.equatorialMount, onToggle: (value: boolean) => { this.onApplyLayerSwitch('actionSwitch_Equatorial_Mount', '', value) } })
          LayerSwitchRow({ label: I18n.t('s0302'), isOn: this.viewSettingsStore.autoZoomResets, onToggle: (value: boolean) => { this.onApplyLayerSwitch('setAutoZoomResets', 'setAutoZoomResets', value) } })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.c.border)
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('i0116')).fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
          LayerSwitchRow({ label: I18n.t('s0304'), isOn: this.liveMode, onToggle: (value: boolean) => { this.onApplyLayerSwitch('', '', value) } })
          LayerSwitchRow({ label: I18n.t('set_vert_clamp'), isOn: this.viewSettingsStore.verticalClamp, onToggle: (value: boolean) => { this.onApplyLayerSwitch('', 'setVerticalClamp', value) } })
          LayerSwitchRow({ label: I18n.t('set_flat_horizon'), isOn: this.viewSettingsStore.flatHorizon, onToggle: (value: boolean) => { this.onApplyLayerSwitch('', 'setFlatHorizon', value) } })
          Row({ space: 6 }) {
            Button(I18n.t('i0142')).fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.onSpeedDown() })
            Button(I18n.t('i0245')).fontSize(10).fontColor(this.c.textStrong).backgroundColor(this.c.accent)
              .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.onTogglePause() })
            Button(I18n.t('i0246')).fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.onSpeedUp() })
          }.width('100%').padding({ left: 4, right: 4 }).margin({ top: 8 })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.c.border)
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_fov_slider')).fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('set_fov_slider')).fontSize(12).fontColor(this.c.sub).width(72)
            Text(this.fovSliderValue + '°').fontSize(14).fontColor(this.c.text).margin({ right: 8 })
            Slider({ value: this.fovSliderValue, min: 1, max: 180, step: 1, style: SliderStyle.OutSet })
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
              .width('40%')
              .trackColor(this.c.bg)
              .showSteps(false)
              .onChange((val: number) => { this.onFovChange(val) })
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.c.border)
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_projection')).fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('set_projection')).fontSize(12).fontColor(this.c.sub).width(72)
            Text(I18n.projectionName(this.currentProjection)).fontSize(11).fontColor(this.c.text).layoutWeight(1)
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })

          Scroll() {
            Row({ space: 6 }) {
              ForEach(PROJECTION_KEYS, (name: string) => {
                Text(I18n.projectionName(name))
                  .fontSize(11).fontColor(this.currentProjection === name ? this.c.textStrong : this.c.sub)
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                  .backgroundColor(this.currentProjection === name ? this.c.softStrong : this.c.input)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .onClick(() => { this.onSetProjection(name) })
              }, (name: string) => name)
            }.padding({ left: 4, right: 4 })
          }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

          Text(I18n.projectionDesc(this.currentProjection))
            .fontSize(10).fontColor(this.c.tertiary)
            .width('100%')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.c.border)
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_language')).fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('i0029')).fontSize(12).fontColor(this.c.sub).width(72)
            Text(LANGUAGE_DISPLAY[this.selectedLanguage] ?? this.selectedLanguage).fontSize(11).fontColor(this.c.text).layoutWeight(1)
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          Scroll() {
            Row({ space: 6 }) {
              ForEach(SUPPORTED_LANGUAGES, (lang: string) => {
                Text(LANGUAGE_DISPLAY[lang] ?? lang)
                  .fontSize(11).fontColor(this.selectedLanguage === lang ? this.c.textStrong : this.c.sub)
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                  .backgroundColor(this.selectedLanguage === lang ? this.c.softStrong : this.c.input)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .onClick(() => { this.onSetLanguage(lang) })
              }, (lang: string) => lang)
            }.padding({ left: 4, right: 4 })
          }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.c.border)
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_sky_culture')).fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('i0035')).fontSize(12).fontColor(this.c.sub).width(72)
            Text(this.skyCultureViewStore.currentSkyCulture).fontSize(11).fontColor(this.c.text).layoutWeight(1).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
          if (this.skyCultureViewStore.skyCultures.length > 0) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.skyCultureViewStore.skyCultures, (culture: string) => {
                  Text(culture)
                    .fontSize(11).fontColor(this.skyCultureViewStore.currentSkyCulture === culture ? this.c.textStrong : this.c.sub)
                    .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                    .backgroundColor(this.skyCultureViewStore.currentSkyCulture === culture ? this.c.softStrong : this.c.input)
                    .borderRadius(UI_RADIUS_CONTROL)
                    .onClick(() => { this.onSetSkyCulture(culture) })
                }, (culture: string) => culture)
              }.padding({ left: 4, right: 4 })
            }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          }
          Row()
            .width('100%').height(0.5)
            .backgroundColor(this.c.border)
            .margin({ top: 6, bottom: 4 })
          Text(I18n.t('set_distance_units')).fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
          Row() {
            Text(I18n.t('i0029')).fontSize(12).fontColor(this.c.sub).width(72)
            Row({ space: 6 }) {
              Text(I18n.t('unit_km'))
                .fontSize(11).fontColor(this.viewSettingsStore.useMetricUnits ? this.c.textStrong : this.c.sub)
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.viewSettingsStore.useMetricUnits ? this.c.softStrong : this.c.input)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSetUnits(true) })
              Text(I18n.t('unit_mile'))
                .fontSize(11).fontColor(!this.viewSettingsStore.useMetricUnits ? this.c.textStrong : this.c.sub)
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(!this.viewSettingsStore.useMetricUnits ? this.c.softStrong : this.c.input)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSetUnits(false) })
            }
          }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
        }.width('100%')
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
  }
}
