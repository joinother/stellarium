import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n, LANGUAGE_DISPLAY, SUPPORTED_LANGUAGES } from '../../pages/I18n'
import { OFFLINE_APPGALLERY_BUILD } from '../../pages/MainWindowModels'
import { GyroStore } from '../../state/GyroStore'
import { LayerStore } from '../../state/LayerStore'
import { NightModeStore } from '../../state/NightModeStore'
import { TelescopeStore } from '../../state/TelescopeStore'
import { ObservingListStore } from '../../state/ObservingListStore'
import { SkyCultureViewStore } from '../../state/SkyCultureViewStore'
import { ViewSettingsStore } from '../../state/ViewSettingsStore'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { InfoRow } from '../../common/ui/InfoRow'
import { GyroscopeRow, LanguageRow } from '../settings/DeviceAndLanguageRows'
import { QuickChipRow } from '../../common/ui/QuickChipRow'
import { sensZh } from '../../common/derive/labels'

// 「配置（旧版）」回退面板：panelContent 链未命中任何具名面板时的兜底页（历史"应用配置"页）；
// setPanel() 把 config / pluginManager 归一为 settings 后，正常导航不会走到这里，
// 仅当 CLI 用未知面板名打开时才可能渲染。
//
// 消费 gyro / layer / nightMode / telescope / observingList / skyCultureView / viewSettings
// 七个 store（@ObjectLink）与标量、主题色 @Prop；宿主私有动作经回调注入。
@Component
export struct ConfigFallbackPanel {
  @ObjectLink gyroStore: GyroStore
  @ObjectLink layerStore: LayerStore
  @ObjectLink nightModeStore: NightModeStore
  @ObjectLink telescopeStore: TelescopeStore
  @ObjectLink observingListStore: ObservingListStore
  @ObjectLink skyCultureViewStore: SkyCultureViewStore
  @ObjectLink viewSettingsStore: ViewSettingsStore
  @Prop isExpandedLayout: boolean
  @Prop fovText: string
  @Prop selectedLanguage: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  observingDisplayName: (name: string) => string = (name: string) => name
  selectObservingTarget: (name: string) => void = () => {}
  removeObservingTarget: (name: string) => void = () => {}
  clearObservingList: () => void = () => {}
  setLegacyDistanceUnit: (useMetric: boolean) => void = () => {}
  handleChip: (id: string) => void = () => {}
  toggleGyroscope: (enabled: boolean) => void = () => {}
  flashHint: (text: ResourceStr) => void = () => {}
  setLanguage: (lang: string) => void = () => {}
  setSkyCulture: (culture: string) => void = () => {}
  triggerAction: (actionId: string) => void = () => {}
  refreshState: () => void = () => {}
  saveScreenshot: () => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  build() {
    Column() {

      InfoRow({ label: I18n.t('i0057'), value: this.isExpandedLayout ? I18n.t('s0703') : I18n.t('s0704') })
      InfoRow({ label: I18n.t('i0058'), value: 'Stellarium Core' })
      InfoRow({ label: I18n.t('i0059'), value: this.fovText })
      InfoRow({ label: I18n.t('i0060'), value: this.gyroStore.gyroscopeStatus })
      InfoRow({ label: I18n.t('i0061'), value: sensZh(this.gyroStore.gyroscopeSensitivityText) })
      GyroscopeRow({ isOn: this.gyroStore.gyroscopeEnabled, onToggle: (v: boolean) => { this.toggleGyroscope(v); this.flashHint(v ? I18n.t('s0719') : I18n.t('s0720')) } })
      LanguageRow({ selectedLanguage: this.selectedLanguage, onSelect: (code: string) => { this.setLanguage(code) } })
      Row() {
        Text(I18n.t('set_distance_units'))
          .fontSize(14)
          .fontColor(this.c.text)
          .width(72)
        Row({ space: 6 }) {
          Text(I18n.t('unit_km'))
            .fontSize(12)
            .fontColor(this.viewSettingsStore.useMetricUnits ? this.c.onAccent : this.c.tertiary)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.viewSettingsStore.useMetricUnits ? this.c.accent : this.c.input)
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => {
              this.setLegacyDistanceUnit(true)
            })
          Text(I18n.t('unit_mile'))
            .fontSize(12)
            .fontColor(!this.viewSettingsStore.useMetricUnits ? this.c.onAccent : this.c.tertiary)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(!this.viewSettingsStore.useMetricUnits ? this.c.accent : this.c.input)
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => {
              this.setLegacyDistanceUnit(false)
            })
        }
      }
        .height(40)
        .width('100%')
      if (this.observingListStore.observingList.length > 0) {
        Row() {
          Text(I18n.t('i0022') + ' (' + this.observingListStore.observingList.length + ')')
            .fontSize(12).fontColor(this.c.sub)
          Text('').layoutWeight(1)
          Button(I18n.t('i0301'))
            .fontSize(11).fontColor(this.c.errorText).backgroundColor(this.c.errorBg)
            .borderRadius(UI_RADIUS_PILL).height(26).padding({ left: 10, right: 10 })
            .onClick(() => {
              this.clearObservingList()
            })
        }
        .height(34).width("100%").padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.observingListStore.observingList, (name: string) => {
              Row({ space: 4 }) {
                Text(this.observingDisplayName(name))
                  .fontSize(11).fontColor(this.c.text)
                Text('x')
                  .fontSize(10).fontColor(this.c.sub)
                  .onClick(() => {
                    this.removeObservingTarget(name)
                  })
              }
              .padding({ left: 10, right: 6, top: 3, bottom: 3 })
              .backgroundColor(this.c.softStrong)
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => {
                this.selectObservingTarget(name)
              })
            }, (name: string) => name)
          }.padding({ left: 4, right: 4 })
        }.width("100%").height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      InfoRow({ label: I18n.t('i0062'), value: I18n.t('s0706') })
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.dividerSoft)
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text(I18n.t('i0275')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row() {
        QuickChipRow({ items: [{ id: 'east', label: I18n.t('s0725') }, { id: 'south', label: I18n.t('s0726') }, { id: 'west', label: I18n.t('s0727') }, { id: 'north', label: I18n.t('s0728') }, { id: 'zenith', label: I18n.t('i0088') }, { id: 'ncp', label: I18n.t('i0089') }], onChip: (id: string) => { this.handleChip(id) } })
      }
      .width('100%')
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.dividerSoft)
        .margin({ top: 8, bottom: 4 })
      Row() {
        Text(I18n.t('i0276')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2 })
      }
      .height(18).width('100%')
      Row() {
        QuickChipRow({ items: [{ id: 'fov1', label: '1°' }, { id: 'fov2', label: '2°' }, { id: 'fov5', label: '5°' }, { id: 'fov10', label: '10°' }, { id: 'fov20', label: '20°' }, { id: 'fov45', label: '45°' }, { id: 'fov60', label: '60°' }, { id: 'fov90', label: '90°' }, { id: 'fov180', label: '180°' }], onChip: (id: string) => { this.handleChip(id) } })
      }
      .width('100%')
      Row() {
        Text(I18n.t('i0025')).fontSize(12).fontColor(this.c.sub).width(72)
        Text(this.telescopeStore.equatorialMount ? I18n.t('i0008') : I18n.t('i0009'))
          .fontSize(14).fontColor(this.c.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.telescopeStore.equatorialMount })
          .onChange((isOn: boolean) => {
            this.telescopeStore.equatorialMount = isOn
            this.triggerAction('actionSwitch_Equatorial_Mount')
            this.refreshState()
            this.flashHint(isOn ? I18n.t('i0008') : I18n.t('i0009'))
          })
      }
      .height(40).width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ top: 4, bottom: 4 })
      // The offline release does not expose screenshots until the file is
      // written through a user-accessible media path.
      Row() {
        if (!OFFLINE_APPGALLERY_BUILD) {
          Button(I18n.t('i0048'))
            .fontSize(13).fontColor(this.c.text).backgroundColor(this.c.input)
            .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1)
            .onClick(() => {
              this.saveScreenshot()
            })
        }
        Row() {
            Image($r(this.nightModeStore.nightMode ? 'app.media.ic_moon' : 'app.media.ic_sun')).width(16).height(16).fillColor(this.c.text)
            Text(this.nightModeStore.nightMode ? I18n.t('s0707') : I18n.t('s0708')).fontSize(12).fontColor(this.c.text).margin({ left: 4 })
          }
          .padding({ left: 10, right: 10 }).backgroundColor(this.c.input)
          .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1).margin({ left: 8 })
          .onClick(() => {
            const next = !this.nightModeStore.nightMode
            // 走统一写回路径：递增 requestEpoch、打开 pending 窗口并发送带回执的
            // setNightMode；直接改 store + triggerAction 会绕开过期回包守卫。
            this.nightModeStore.applyNightMode(next, true)
            this.flashHint(next ? I18n.t('s0707') : I18n.t('s0708'))
          })
      }
      .width('100%').margin({ top: 4, bottom: 4 })
      Row() {
        Text(I18n.t('i0277')).fontSize(12).fontColor(this.c.sub).width(72)
        Row() {
              Image($r('app.media.ic_layers')).width(14).height(14).fillColor(this.c.text)
              Text(this.layerStore.flipVert ? I18n.t('s0709') : I18n.t('s0710')).fontSize(11).fontColor(this.c.text).margin({ left: 3 })
            }
          .padding({ left: 8, right: 8 }).backgroundColor(this.layerStore.flipVert ? this.c.softStrong : this.c.input)
          .borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
          .onClick(() => {
            this.layerStore.flipVert = !this.layerStore.flipVert
            this.triggerAction('actionVertical_Flip')
            this.flashHint(this.layerStore.flipVert ? I18n.t('msg_flip_south_up') : I18n.t('msg_flip_north_up'))
          })
        Row() {
              Image($r('app.media.ic_refresh')).width(14).height(14).fillColor(this.c.text)
              Text(this.layerStore.flipHoriz ? I18n.t('s0711') : I18n.t('s0712')).fontSize(11).fontColor(this.c.text).margin({ left: 3 })
            }
          .padding({ left: 8, right: 8 }).backgroundColor(this.layerStore.flipHoriz ? this.c.softStrong : this.c.input)
          .padding({ left: 8, right: 8 }).borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1).margin({ left: 6 }).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.layerStore.flipHoriz = !this.layerStore.flipHoriz
            this.triggerAction('actionHorizontal_Flip')
            this.flashHint(this.layerStore.flipHoriz ? I18n.t('s0711') : I18n.t('s0712'))
          })
      }
      .width('100%').padding({ left: 10, right: 10 }).margin({ top: 2, bottom: 4 })
      QuickChipRow({ items: [{ id: 'refresh', label: I18n.t('s0721') }, { id: 'now', label: I18n.t('s0754') }], onChip: (id: string) => { this.handleChip(id) } })
      Row() {
        Text(I18n.t('i0026')).fontSize(12).fontColor(this.c.sub).width(72)
      }
      .height(6).width("100%").margin({ top: 2 })
      Text(I18n.t('i0027'))
        .fontSize(11).fontColor(this.c.sub).width("100%").padding({ left: 4, right: 4 })
      Text(I18n.t('i0028'))
        .fontSize(11).fontColor(this.c.sub).width("100%").padding({ left: 4, right: 4 }).margin({ top: 2 })
      Row() {
        Text(I18n.t('i0029')).fontSize(12).fontColor(this.c.sub).width(72)
        Text(LANGUAGE_DISPLAY[this.selectedLanguage] ?? this.selectedLanguage)
          .fontSize(14).fontColor(this.c.text).layoutWeight(1)
      }
      .height(34).width("100%").padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
      Scroll() {
        Row({ space: 6 }) {
          ForEach(SUPPORTED_LANGUAGES, (lang: string) => {
            Text(LANGUAGE_DISPLAY[lang] ?? lang)
              .fontSize(11).fontColor(this.selectedLanguage === lang ? this.c.textStrong : this.c.tertiary)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor(this.selectedLanguage === lang ? this.c.softStrong : this.c.input)
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => this.setLanguage(lang))
          }, (lang: string) => lang)
        }.padding({ left: 4, right: 4 })
      }.width("100%").height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 8 })
      // Sky-culture selection is intentionally hidden in the offline release.
      if (!OFFLINE_APPGALLERY_BUILD && this.skyCultureViewStore.skyCultures.length > 0) {
        Row() {
          Text(I18n.t('i0035')).fontSize(12).fontColor(this.c.sub).width(72)
          Text(this.skyCultureViewStore.currentSkyCulture).fontSize(14).fontColor(this.c.text).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .height(34).width("100%").padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.skyCultureViewStore.skyCultures, (culture: string) => {
              Text(culture)
                .fontSize(11).fontColor(this.skyCultureViewStore.currentSkyCulture === culture ? this.c.textStrong : this.c.sub)
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.skyCultureViewStore.currentSkyCulture === culture ? this.c.softStrong : this.c.input)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => this.setSkyCulture(culture))
            }, (culture: string) => culture)
          }.padding({ left: 4, right: 4 })
        }.width("100%").height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
    }.width('100%')
  }
}
