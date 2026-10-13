// 「设置」面板，对应 `activePanel === 'settings'`：设备与隐私 / 主设置 / 信息 / 天空 /
// 时间 / 数据 / 插件管理 / 视图导航 8 个子标签页。
//
// 实时状态集中在八个 @Observed store（gyro / overlay / deltaT / timeSettings / ephemeris /
// plugin / navigation / viewSettings，均 @ObjectLink），其余标量与主题色走 @Prop；
// 标签/文案纯函数多数直连 common/derive/labels，宿主私有助手与全部动作经回调注入。
// 边框色命名为 lineColor：成员名须避开 CustomComponent 基类的属性方法。
// 最大视场用本地草稿 maxFovDraft（aboutToAppear 与 store 同步）：拖动只改草稿，
// 点“应用”才经 setNavigationMaxFov 下发生效。
// Scroller（scriptListScroller）以普通成员传入：宿主仍持同一实例。

import { curves } from '@kit.ArkUI'
import { I18n, PROJECTION_KEYS } from '../../pages/I18n'
import { TabItem, PluginItem } from '../../pages/StellariumTypes'
import { ConfigurationOption } from '../../pages/MainWindowModels'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL, UI_RADIUS_PANEL } from '../../common/ui/UiTokens'
import { GyroStore } from '../../state/GyroStore'
import { OverlayStore } from '../../state/OverlayStore'
import { DeltaTStore } from '../../state/DeltaTStore'
import { TimeSettingsStore } from '../../state/TimeSettingsStore'
import { EphemerisStore } from '../../state/EphemerisStore'
import { PluginStore } from '../../state/PluginStore'
import { NavigationSettingsStore } from '../../state/NavigationSettingsStore'
import { ViewSettingsStore } from '../../state/ViewSettingsStore'
import { NotificationStore } from '../../state/NotificationStore'
import { InfoRow } from '../../common/ui/InfoRow'
import { EphemerisToggleRow, InformationModeButton, InformationSwitchRow, NavigationSwitchRow } from '../settings/SettingsRows'
import { LanguageRow, DevicePrivacySection } from '../settings/DeviceAndLanguageRows'
import { NotificationSection } from '../settings/NotificationSection'
import { KeyboardShortcutSection } from '../settings/KeyboardShortcutSection'
import { KeyboardShortcutStore } from '../../state/KeyboardShortcutStore'
import { KeyboardShortcutItem } from '../../common/types/StellariumTypes'
import { TimeSettingsSection } from '../settings/TimeSettingsSection'
import { DeltaTSettingsBlock } from '../time/DeltaTSettingsBlock'
import { sensZh, pluginZh, pluginDesc, pluginFeatureRoute, resourceText, scriptZh, scriptDesc } from '../../common/derive/labels'
import { configDitheringLabel } from '../../common/derive/skycult'

@Component
export struct SettingsPanel {
  @ObjectLink gyroStore: GyroStore
  @ObjectLink overlayStore: OverlayStore
  @ObjectLink deltaTStore: DeltaTStore
  @ObjectLink timeSettingsStore: TimeSettingsStore
  @ObjectLink ephemerisStore: EphemerisStore
  @ObjectLink pluginStore: PluginStore
  @ObjectLink navigationStore: NavigationSettingsStore
  @ObjectLink viewSettingsStore: ViewSettingsStore
  @ObjectLink notificationStore: NotificationStore
  @ObjectLink keyboardShortcutStore: KeyboardShortcutStore
  @Prop configTab: number
  @Prop configTabContentOpacity: number
  @Prop configTabContentOffsetX: number
  @Prop i18nLang: string
  @Prop selectedLanguage: string
  @Prop isExpandedLayout: boolean
  @Prop informationMode: string
  @Prop informationSettingPending: boolean
  // 呈现轴（与上面的信息级别正交）：详情卡默认形态开关，见 OBJECT-DETAIL-OBSERVE-MODE.md §6。
  @Prop observeMode: boolean
  @Prop currentProjection: string
  @Prop configDitheringMode: string
  @Prop timeSettingsPending: boolean
  @Prop observationTimeText: string
  @Prop scriptLaunching: boolean
  @Prop scriptLaunchingName: string
  @Prop scriptList: string[]
  @Prop fovText: string
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop lineColor: string
  @Prop inputColor: string
  scroller: Scroller = new Scroller()
  @State private maxFovDraft: number = 180
  informationMaskHas: (key: string) => boolean = () => false
  pluginMetaLine: (plugin: PluginItem) => string = () => ''
  pluginFeatureDestination: (id: string) => string = () => ''
  pluginFeatureIsActionable: (id: string) => boolean = () => false
  pluginFeatureActionLabel: (id: string) => string = () => ''
  scriptMetaLine: (filename: string) => string = () => ''
  scriptSourceLine: (filename: string) => string = () => ''
  hasSelectedObject: () => boolean = () => false
  selectConfigTab: (tabId: number) => void = () => {}
  setLanguage: (lang: string) => void = () => {}
  setEphemerisEnabled: (key: string, available: boolean, enabled: boolean) => void = () => {}
  setDistanceUnit: (useMetric: boolean) => void = () => {}
  setConfigurationDithering: (value: string) => void = () => {}
  setProjection: (name: string) => void = () => {}
  saveAppSettings: () => void = () => {}
  flashHint: (text: ResourceStr) => void = () => {}
  saveAllCoreSettings: () => void = () => {}
  restoreCoreDefaults: () => void = () => {}
  saveCurrentViewAsStartup: () => void = () => {}
  setViewLockState: (enabled: boolean) => void = () => {}
  setNavigationBoolean: (setting: string, enabled: boolean) => void = () => {}
  setNavigationMaxFov: (value: number) => void = () => {}
  selectSettingsChoice: (group: string, value: string) => void = () => {}
  setStartupTimeSetting: (key: string, value: string) => void = () => {}
  setInformationField: (key: string, enabled: boolean) => void = () => {}
  onToggleObserveMode: (enabled: boolean) => void = () => {}
  setObjectDetailConnector: (enabled: boolean) => void = () => {}
  toggleGyroscope: (enabled: boolean) => void = () => {}
  confirmPrivacyRevocation: () => void = () => {}
  requestNotificationAccess: () => void = () => {}
  scheduleNextSolarTermReminder: () => void = () => {}
  clearAstronomyReminders: () => void = () => {}
  keyboardShortcutQueryChange: (value: string) => void = () => {}
  keyboardShortcutSelectChange: (item: KeyboardShortcutItem) => void = () => {}
  keyboardShortcutPrimaryChange: (value: string) => void = () => {}
  keyboardShortcutAlternateChange: (value: string) => void = () => {}
  keyboardShortcutSaveChange: () => void = () => {}
  keyboardShortcutResetSelectedChange: () => void = () => {}
  keyboardShortcutResetAllChange: () => void = () => {}
  loadPluginList: () => void = () => {}
  openPluginFeature: (id: string) => void = () => {}
  playScriptByName: (filename: string) => void = () => {}
  triggerAction: (actionId: string) => void = () => {}
  moveToSelectedObject: () => void = () => {}
  onOpenLayersSky: () => void = () => {}
  onOpenTools: () => void = () => {}

  aboutToAppear(): void {
    this.maxFovDraft = this.navigationStore.navigationMaxFov
  }

  build() {

      Column() {
        Scroll() {
          Row({ space: 5 }) {
          ForEach([
            { label: I18n.t('settings_device_privacy'), id: -1 },
            { label: I18n.t('c0000'), id: 0 },
            { label: I18n.t('c0001'), id: 1 },
            { label: I18n.t('c0002'), id: 2 },
            { label: I18n.t('c0003'), id: 3 },
            { label: I18n.t('c0004'), id: 4 },
            { label: I18n.t('c0005'), id: 5 },
            { label: I18n.t('more_plugins_manage'), id: 6 },
            { label: I18n.t('settings_view_navigation'), id: 7 },
          ] as TabItem[], (tab: TabItem) => {
            Text(tab.label)
              .fontSize(10)
              .fontColor(this.configTab === tab.id ? '#F4FAFF' : '#C8D4E2')
              .padding({ left: 9, right: 9, top: 5, bottom: 5 })
              .backgroundColor(this.configTab === tab.id ? '#397EAE' : 'rgba(255,255,255,0.09)')
              .borderRadius(UI_RADIUS_CONTROL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .animation({ duration: 180, curve: curves.springMotion(0.5, 1.0) })
              .onClick(() => { this.selectConfigTab(tab.id) })
          }, (tab: TabItem, index: number) => tab.id.toString())
          }.padding({ left: 2, right: 2 })
        }.width('100%').height(34).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .margin({ top: 4, bottom: 8 }).id('config-tabs-' + this.i18nLang)
        Column({ space: 0 }) {
          if (this.configTab === -1) {
            DevicePrivacySection({ gyroscopeEnabled: this.gyroStore.gyroscopeEnabled, sensitivityText: sensZh(this.gyroStore.gyroscopeSensitivityText), textColor: this.textColor, subColor: this.subColor, panelColor: this.panelColor, onToggleGyroscope: (v: boolean) => { this.toggleGyroscope(v); this.flashHint(v ? I18n.t('s0719') : I18n.t('s0720')) }, onRevoke: () => { this.confirmPrivacyRevocation() } })
            NotificationSection({
              notificationEnabled: this.notificationStore.astronomyNotificationEnabled,
              notificationBusy: this.notificationStore.astronomyNotificationBusy,
              reminderCount: this.notificationStore.astronomyReminderCount,
              statusText: this.notificationStore.astronomyNotificationStatus,
              textColor: this.textColor,
              subColor: this.subColor,
              onRequestAccess: () => { this.requestNotificationAccess() },
              onScheduleNextSolarTerm: () => { this.scheduleNextSolarTermReminder() },
              onClearReminders: () => { this.clearAstronomyReminders() }
            })
          } else if (this.configTab === 0) {
            LanguageRow({ selectedLanguage: this.selectedLanguage, onSelect: (code: string) => { this.setLanguage(code) } })
            Text('行星历表').fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 4 })
            Text('用于行星位置计算的 JPL 数值星历。仅显示设备中已安装的文件。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 5 })
            EphemerisToggleRow({ label: 'DE430', available: this.ephemerisStore.ephemerisDe430Available, isEnabled: this.ephemerisStore.ephemerisDe430Active, textColor: this.textColor, subColor: this.subColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setEphemerisEnabled('de430', this.ephemerisStore.ephemerisDe430Available, v) } })
            EphemerisToggleRow({ label: 'DE431', available: this.ephemerisStore.ephemerisDe431Available, isEnabled: this.ephemerisStore.ephemerisDe431Active, textColor: this.textColor, subColor: this.subColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setEphemerisEnabled('de431', this.ephemerisStore.ephemerisDe431Available, v) } })
            EphemerisToggleRow({ label: 'DE440', available: this.ephemerisStore.ephemerisDe440Available, isEnabled: this.ephemerisStore.ephemerisDe440Active, textColor: this.textColor, subColor: this.subColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setEphemerisEnabled('de440', this.ephemerisStore.ephemerisDe440Available, v) } })
            EphemerisToggleRow({ label: 'DE441', available: this.ephemerisStore.ephemerisDe441Available, isEnabled: this.ephemerisStore.ephemerisDe441Active, textColor: this.textColor, subColor: this.subColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setEphemerisEnabled('de441', this.ephemerisStore.ephemerisDe441Available, v) } })
            Row() {
              Text(I18n.t('set_distance_units')).fontSize(12).fontColor(this.subColor).width(72)
              Row({ space: 6 }) {
                Text(I18n.t('unit_km'))
                  .fontSize(11).fontColor(this.viewSettingsStore.useMetricUnits ? '#F4FAFF' : '#C8D4E2')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(this.viewSettingsStore.useMetricUnits ? '#5B93BF' : 'rgba(255,255,255,0.06)')
                  .borderRadius(UI_RADIUS_CONTROL)
                  .onClick(() => {
                    this.setDistanceUnit(true)
                  })
                Text(I18n.t('unit_mile'))
                  .fontSize(11).fontColor(!this.viewSettingsStore.useMetricUnits ? '#F4FAFF' : '#C8D4E2')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(!this.viewSettingsStore.useMetricUnits ? '#5B93BF' : 'rgba(255,255,255,0.06)')
                  .borderRadius(UI_RADIUS_CONTROL)
                  .onClick(() => {
                    this.setDistanceUnit(false)
                  })
              }
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            InfoRow({ label: I18n.t('s0350'), value: 'Stellarium 26.2 for HarmonyOS' })
            Button(I18n.t('i0251') + '设置').fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 12, right: 12 }).margin({ top: 6, left: 8 })
              .onClick(() => { this.saveAppSettings(); this.flashHint('设置已保存') })
          } else if (this.configTab === 1) {
            Row() {
              Text(I18n.t('i0120')).fontSize(12).fontColor(this.subColor).width(72)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              InformationModeButton({ labelKey: 'i0247', active: this.informationMode === 'all', canPick: !this.informationSettingPending, textColor: this.textColor, subColor: this.subColor, activeColor: this.accentColor, panelColor: this.panelColor, onPick: () => { this.selectSettingsChoice('information', 'all') } })
              InformationModeButton({ labelKey: 'i0248', active: this.informationMode === 'default', canPick: !this.informationSettingPending, textColor: this.textColor, subColor: this.subColor, activeColor: this.accentColor, panelColor: this.panelColor, onPick: () => { this.selectSettingsChoice('information', 'default') } })
              InformationModeButton({ labelKey: 'i0249', active: this.informationMode === 'short', canPick: !this.informationSettingPending, textColor: this.textColor, subColor: this.subColor, activeColor: this.accentColor, panelColor: this.panelColor, onPick: () => { this.selectSettingsChoice('information', 'short') } })
              InformationModeButton({ labelKey: 'i0250', active: this.informationMode === 'none', canPick: !this.informationSettingPending, textColor: this.textColor, subColor: this.subColor, activeColor: this.accentColor, panelColor: this.panelColor, onPick: () => { this.selectSettingsChoice('information', 'none') } })
              InformationModeButton({ labelKey: 'information_custom_mode', active: this.informationMode === 'custom', canPick: !this.informationSettingPending, textColor: this.textColor, subColor: this.subColor, activeColor: this.accentColor, panelColor: this.panelColor, onPick: () => { this.selectSettingsChoice('information', 'custom') } })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
            Row() {
              Column() {
                Text(I18n.t('detail_observe_toggle')).fontSize(12).fontColor(this.textColor).width('100%')
                Text(I18n.t('detail_observe_hint')).fontSize(10).fontColor(this.subColor).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.observeMode })
                .width(42).height(24).selectedColor(this.accentColor)
                .onChange((value: boolean) => { this.onToggleObserveMode(value) })
            }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
            Row() {
              Column() {
                Text('详情卡指向线').fontSize(12).fontColor(this.textColor).width('100%')
                Text('在可见天体与详情卡之间显示细连接线').fontSize(10).fontColor(this.subColor).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.overlayStore.objectDetailConnectorVisible })
                .width(42).height(24).selectedColor(this.accentColor)
                .onChange((value: boolean) => { this.setObjectDetailConnector(value) })
            }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
            Text('自定义信息字段').fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 4 })
            Text('选择“自定义”后，详情卡和星体信息栏只显示下面勾选的字段。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 5 })
            InformationSwitchRow({ label: '名称', isOn: this.informationMaskHas('name'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('name', v) } })
            InformationSwitchRow({ label: '目录编号', isOn: this.informationMaskHas('catalog'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('catalog', v) } })
            InformationSwitchRow({ label: '视星等', isOn: this.informationMaskHas('magnitude'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('magnitude', v) } })
            InformationSwitchRow({ label: '赤经、赤纬（J2000）', isOn: this.informationMaskHas('raJ2000'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('raJ2000', v) } })
            InformationSwitchRow({ label: '赤经、赤纬（历元）', isOn: this.informationMaskHas('raOfDate'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('raOfDate', v) } })
            InformationSwitchRow({ label: '方位角、高度角', isOn: this.informationMaskHas('altAz'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('altAz', v) } })
            InformationSwitchRow({ label: '距离', isOn: this.informationMaskHas('distance'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('distance', v) } })
            InformationSwitchRow({ label: '时角', isOn: this.informationMaskHas('hourAngle'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('hourAngle', v) } })
            InformationSwitchRow({ label: '升起、中天、落下时间', isOn: this.informationMaskHas('riseTransitSet'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('riseTransitSet', v) } })
            InformationSwitchRow({ label: '大小或角直径', isOn: this.informationMaskHas('size'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('size', v) } })
            InformationSwitchRow({ label: '轨道与光照信息', isOn: this.informationMaskHas('elongation'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('elongation', v) } })
            InformationSwitchRow({ label: '银河坐标', isOn: this.informationMaskHas('galactic'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('galactic', v) } })
            InformationSwitchRow({ label: '星座信息', isOn: this.informationMaskHas('constellation'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('constellation', v) } })
            InformationSwitchRow({ label: '恒星时', isOn: this.informationMaskHas('siderealTime'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('siderealTime', v) } })
            InformationSwitchRow({ label: '附加资料', isOn: this.informationMaskHas('extra'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setInformationField('extra', v) } })
          } else if (this.configTab === 2) {
            Text('天空显示设置已统一到“图层 > 天空”').fontSize(11).fontColor(this.subColor)
              .width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).maxLines(2)
            Button('打开图层 > 天空').fontSize(11).fontColor(this.textColor).backgroundColor(this.accentColor)
              .borderRadius(UI_RADIUS_CONTROL).height(34).width('100%')
              .onClick(() => { this.onOpenLayersSky() })
            Row().width('100%').height(0.5).backgroundColor(this.lineColor).margin({ top: 8, bottom: 8 })
            Text(I18n.t('set_projection')).fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 2, bottom: 5 })
            Row() {
              Text(I18n.t('set_projection')).fontSize(11).fontColor(this.textColor).layoutWeight(1)
              Text(I18n.projectionName(this.currentProjection)).fontSize(10).fontColor(this.subColor).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%').padding({ left: 10, right: 8 }).margin({ bottom: 4 })
            Scroll() {
              Row({ space: 6 }) {
                ForEach(PROJECTION_KEYS, (name: string) => {
                  Text(I18n.projectionName(name)).fontSize(10)
                    .fontColor(this.currentProjection === name ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.currentProjection === name ? this.accentColor : this.panelColor)
                    .borderRadius(UI_RADIUS_CONTROL)
                    .animation({ duration: 180, curve: Curve.EaseOut })
                    .onClick(() => { this.setProjection(name) })
                }, (name: string) => name)
              }.padding({ left: 8, right: 8 })
            }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            Text(I18n.projectionDesc(this.currentProjection)).fontSize(10).fontColor(this.subColor).width('100%')
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 10, right: 10, top: 4, bottom: 4 })
            Row().width('100%').height(0.5).backgroundColor(this.lineColor).margin({ top: 8, bottom: 8 })
            Text('渲染输出').fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 2, bottom: 5 })
            Row() {
              Text('色彩抖动').fontSize(12).fontColor(this.subColor).width(72)
              Text(configDitheringLabel(this.configDitheringMode)).fontSize(12).fontColor(this.textColor).layoutWeight(1).textAlign(TextAlign.End)
            }.height(30).width('100%').padding({ left: 10, right: 10 })
            Scroll() {
              Row({ space: 6 }) {
                ForEach([
                  { id: 'Disabled', label: '关闭' }, { id: 'Color565', label: '5/6/5 位' },
                  { id: 'Color666', label: '6/6/6 位' }, { id: 'Color888', label: '8/8/8 位' },
                ] as ConfigurationOption[], (option: ConfigurationOption) => {
                  Text(option.label).fontSize(10)
                    .fontColor(this.configDitheringMode === option.id ? this.textColor : this.subColor)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.configDitheringMode === option.id ? this.accentColor : this.panelColor)
                    .borderRadius(UI_RADIUS_CONTROL)
                    .onClick(() => { this.setConfigurationDithering(option.id) })
                }, (option: ConfigurationOption) => option.id)
              }.padding({ left: 8, right: 8 })
            }.width('100%').height(31).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            Text('抖动用于低色深屏幕的颜色过渡；通常保持 8/8/8 位。').fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 10, right: 10 }).margin({ top: 4, bottom: 8 })
            InfoRow({ label: I18n.t('s0351'), value: 'Stellarium for HarmonyOS' })
            InfoRow({ label: I18n.t('s0352'), value: 'OpenHarmony / HarmonyOS NEXT' })
          } else if (this.configTab === 3) {
            TimeSettingsSection({
              store: this.timeSettingsStore,
              pending: this.timeSettingsPending,
              observationTimeText: this.observationTimeText,
              textColor: this.textColor,
              subColor: this.subColor,
              inputColor: this.inputColor,
              panelColor: this.panelColor,
              accentColor: this.accentColor,
              borderColorValue: this.lineColor,
              onSelectFormat: (group: string, value: string) => { this.selectSettingsChoice(group, value) },
              onSetStartup: (key: string, value: string) => { this.setStartupTimeSetting(key, value) }
            })
            DeltaTSettingsBlock({
              store: this.deltaTStore,
              pending: this.timeSettingsPending,
              textColor: this.textColor,
              subColor: this.subColor,
              panelColor: this.panelColor,
              inputColor: this.inputColor,
              accentColor: this.accentColor,
              onSelect: (key: string) => { this.setStartupTimeSetting('deltaT', key) },
              onSaveCustom: (text: string) => { this.setStartupTimeSetting('deltaCustom', text) }
            })
          } else if (this.configTab === 4) {
            Text(I18n.t('tools_data_hint')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8, right: 8 }).margin({ top: 4, bottom: 8 })
            Button(I18n.t('panel_tools_data')).fontSize(12).fontColor(this.textColor).backgroundColor(this.accentColor)
              .borderRadius(UI_RADIUS_CONTROL).height(34).width('100%').onClick(() => { this.onOpenTools() })
            Text(I18n.t('tools_single_entry_hint')).fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 8, right: 8 }).margin({ top: 8 })
          } else if (this.configTab === 5) {
            Row() {
              Text(I18n.t('i0122')).fontSize(12).fontColor(this.subColor).width(72)
              Button(I18n.t('i0252')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.triggerAction('actionStop_Script') })
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Row() {
              Text(I18n.t('i0123')).fontSize(11).fontColor(this.subColor).width('100%').margin({ top: 4 })
            }.height(18).width('100%')
            if (this.scriptLaunching) {
              Row({ space: 6 }) {
                LoadingProgress().width(16).height(16).color(this.accentColor)
                Text(I18n.format('script_starting_named', [scriptZh(this.scriptLaunchingName)])).fontSize(10).fontColor(this.subColor)
              }.width('100%').padding({ left: 8, right: 8, bottom: 4 })
            }
            Scroll(this.scroller) {
              Column({ space: 2 }) {
                ForEach(this.scriptList, (s: string) => {
                  Column({ space: 0 }) {
                    Row() {
                      Text(scriptZh(s)).fontSize(11).fontColor(this.textColor)
                        .fontWeight(FontWeight.Medium).layoutWeight(1)
                      Text('▶').fontSize(10).fontColor('#7FD0FF')
                    }
                    .height(28).width('100%').padding({ left: 10, right: 10 })
                    if (scriptDesc(s)) {
                      Text(scriptDesc(s))
                        .fontSize(10).fontColor('#77FFFFFF').width('100%')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        .padding({ left: 10, right: 10, bottom: 3 })
                    }
                    if (this.scriptMetaLine(s).length > 0) {
                      Text(this.scriptMetaLine(s))
                        .fontSize(10).fontColor('#66FFFFFF').width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        .padding({ left: 10, right: 10, bottom: 3 })
                    }
                    if (this.scriptSourceLine(s).length > 0) {
                      Text(this.scriptSourceLine(s)).fontSize(10).fontColor('#55FFFFFF').width('100%').maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 10, right: 10, bottom: 3 })
                    }
                  }
                  .width('100%')
                  .backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .opacity(this.scriptLaunching && this.scriptLaunchingName !== s ? 0.55 : 1)
                    .hitTestBehavior(HitTestMode.Default)
                  .onClick(() => { this.playScriptByName(s) })
                }, (s: string, index: number) => s)
              }
                .width('100%')
            }
              .width('100%')
              .height(this.isExpandedLayout ? 330 : 300)
              .scrollable(ScrollDirection.Vertical)
              .scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)
              .hitTestBehavior(HitTestMode.Default)
          } else if (this.configTab === 6) {
            Row() {
              Column({ space: 3 }) {
                Text(I18n.t('i0124')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.textColor).width('100%')
                Text(I18n.t('plugin_management_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(3)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button(I18n.t('act_refresh')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.loadPluginList() })
            }.width('100%').padding({ left: 8, right: 8, top: 4, bottom: 8 })
            if (this.pluginStore.pluginListLoading && this.pluginStore.pluginList.length === 0) {
              Row({ space: 8 }) {
                LoadingProgress().width(18).height(18).color(this.accentColor)
                Text(I18n.t('msg_loading')).fontSize(11).fontColor(this.subColor)
              }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 10 })
            }
            Scroll() {
              Column({ space: 6 }) {
                ForEach(this.pluginStore.pluginList, (pl: PluginItem) => {
                  Column({ space: 5 }) {
                    Row() {
                      Text(pluginZh(pl.name)).fontSize(12).fontColor(this.textColor)
                        .fontWeight(FontWeight.Medium).layoutWeight(1)
                      Text(pl.loaded ? I18n.t('plugin_runtime_loaded') : I18n.t('plugin_runtime_unloaded'))
                        .fontSize(10).fontColor(pl.loaded ? '#B9E6C4' : this.subColor)
                        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                        .backgroundColor(pl.loaded ? 'rgba(70, 150, 96, 0.18)' : this.panelColor)
                        .borderRadius(UI_RADIUS_PILL)
                    }
                    .height(28)
                    if (resourceText(pl.description, pluginDesc(pl.name)).length > 0) {
                      Text(resourceText(pl.description, pluginDesc(pl.name)))
                        .fontSize(10).fontColor(this.subColor).width('100%')
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    Text(I18n.t('resource_author') + ': ' + resourceText(pl.authors, I18n.t('resource_not_provided')) + ' · ' + I18n.t('resource_license') + ': ' + resourceText(pl.license, I18n.t('resource_not_provided')))
                      .fontSize(10).fontColor('#77FFFFFF').width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (this.pluginMetaLine(pl).length > 0) {
                      Text(this.pluginMetaLine(pl))
                        .fontSize(10).fontColor('#66FFFFFF').width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    Row({ space: 8 }) {
                      Text(I18n.t('plugin_all_loaded_policy')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(2)
                    }.width('100%').height(24)
                    Text(this.pluginFeatureDestination(pl.id)).fontSize(10).fontColor(this.subColor).width('100%')
                      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (this.pluginFeatureIsActionable(pl.id)) {
                      Button() {
                        Text(this.pluginFeatureActionLabel(pl.id))
                          .fontSize(11)
                          .fontColor(this.textColor)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                        .id('plugin-feature-' + pl.id)
                        .backgroundColor(this.accentColor)
                        .borderRadius(UI_RADIUS_CONTROL).height(30).width('100%')
                        .padding({ left: 10, right: 10 })
                        .hitTestBehavior(HitTestMode.Block)
                        .zIndex(2)
                        .onClick(() => { this.openPluginFeature(pl.id) })
                    } else {
                      Text(pluginFeatureRoute(pl.id).kind === 'offline' || pluginFeatureRoute(pl.id).kind === 'network'
                        ? pluginFeatureRoute(pl.id).kind === 'network'
                          ? I18n.t('plugin_network_disabled')
                          : I18n.t('plugin_offline_disabled')
                        : I18n.t('plugin_background_only'))
                        .fontSize(10).fontColor(this.subColor).width('100%').maxLines(2)
                    }
                  }
                  .width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .backgroundColor(this.panelColor)
                  .borderRadius(UI_RADIUS_PANEL)
                }, (pl: PluginItem) => pl.id)
              }
            }
            .width('100%').height(260).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
          } else if (this.configTab === 7) {
            Text(I18n.t('settings_view_navigation')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 3 })
            Text(I18n.t('settings_view_navigation_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(3).margin({ bottom: 8 })
            Text(I18n.t('settings_view_current')).fontSize(12).fontColor(this.subColor).width('100%').margin({ bottom: 5 })
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(I18n.t('settings_view_current_fov')).fontSize(10).fontColor(this.subColor)
                Text(this.fovText).fontSize(16).fontColor(this.textColor)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button(I18n.t('settings_view_center')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 })
                .opacity(this.hasSelectedObject() && !this.gyroStore.gyroscopeEnabled ? 1 : 0.58)
                .onClick(() => { this.moveToSelectedObject() })
            }.width('100%').padding({ left: 10, right: 8, top: 7, bottom: 7 })
              .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })

            Column({ space: 5 }) {
              Row({ space: 8 }) {
                Text(I18n.t('set_lock_view')).fontSize(11).fontColor(this.textColor).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.viewSettingsStore.viewLock })
                  .width(42).height(24).selectedColor(this.accentColor)
                  .onChange((enabled: boolean) => { this.setViewLockState(enabled) })
              }.width('100%')
              Text(this.viewSettingsStore.viewLock ? I18n.t('view_lock_enabled') : I18n.t('settings_view_lock_hint'))
                .fontSize(10).fontColor(this.subColor).width('100%').maxLines(3)
            }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })

            Text(I18n.t('settings_view_startup')).fontSize(12).fontColor(this.subColor).width('100%').margin({ bottom: 5 })
            Column({ space: 2 }) {
              Text(I18n.format('settings_view_startup_fov', [this.navigationStore.navigationStartupFov.toFixed(1)])).fontSize(11).fontColor(this.textColor).width('100%')
              Text(I18n.format('settings_view_startup_direction', [this.navigationStore.navigationStartupAzimuth.toFixed(1), this.navigationStore.navigationStartupAltitude.toFixed(1)])).fontSize(10).fontColor(this.subColor).width('100%')
            }.width('100%').padding({ left: 10, right: 10, top: 7, bottom: 7 })
              .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
            Button(I18n.t('settings_view_save_current')).fontSize(11).fontColor(this.textColor).backgroundColor(this.accentColor)
              .borderRadius(UI_RADIUS_CONTROL).height(34).width('100%').margin({ bottom: 8 })
              .onClick(() => { this.saveCurrentViewAsStartup() })

            Text(I18n.t('settings_view_navigation_controls')).fontSize(12).fontColor(this.subColor).width('100%').margin({ bottom: 5 })
            NavigationSwitchRow({ label: I18n.t('settings_view_mouse_navigation'), isOn: this.navigationStore.navigationMouseEnabled, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setNavigationBoolean('mouseNavigation', v) } })
            NavigationSwitchRow({ label: I18n.t('settings_view_mouse_zoom'), isOn: this.navigationStore.navigationMouseZoomEnabled, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setNavigationBoolean('mouseZooming', v) } })
            NavigationSwitchRow({ label: I18n.t('settings_view_keyboard_navigation'), isOn: this.navigationStore.navigationMoveKeysEnabled, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setNavigationBoolean('moveKeys', v) } })
            NavigationSwitchRow({ label: I18n.t('settings_view_keyboard_zoom'), isOn: this.navigationStore.navigationZoomKeysEnabled, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setNavigationBoolean('zoomKeys', v) } })
            NavigationSwitchRow({ label: I18n.t('settings_view_gravity_labels'), isOn: this.navigationStore.navigationGravityLabelsEnabled, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setNavigationBoolean('gravityLabels', v) } })
            NavigationSwitchRow({ label: I18n.t('s0302'), isOn: this.viewSettingsStore.autoZoomResets, textColor: this.textColor, accentColor: this.accentColor, panelColor: this.panelColor, borderColorValue: this.lineColor, onToggle: (v: boolean) => { this.setNavigationBoolean('autoZoomResets', v) } })

            KeyboardShortcutSection({
              store: this.keyboardShortcutStore,
              textColor: this.textColor,
              subColor: this.subColor,
              accentColor: this.accentColor,
              panelColor: this.panelColor,
              inputColor: this.inputColor,
              activeSoft: 'rgba(91,147,191,0.24)',
              onQuery: (value: string) => { this.keyboardShortcutQueryChange(value) },
              onSelect: (item: KeyboardShortcutItem) => { this.keyboardShortcutSelectChange(item) },
              onPrimary: (value: string) => { this.keyboardShortcutPrimaryChange(value) },
              onAlternate: (value: string) => { this.keyboardShortcutAlternateChange(value) },
              onSave: () => { this.keyboardShortcutSaveChange() },
              onResetSelected: () => { this.keyboardShortcutResetSelectedChange() },
              onResetAll: () => { this.keyboardShortcutResetAllChange() }
            })

            Text(I18n.t('settings_view_max_fov')).fontSize(12).fontColor(this.subColor).width('100%').margin({ top: 4, bottom: 4 })
            Row() {
              Text(this.maxFovDraft.toFixed(0) + '°').fontSize(14).fontColor(this.textColor).width(48)
              Slider({ value: this.maxFovDraft, min: 30, max: 360, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor)
                .showSteps(false).onChange((value: number) => { this.maxFovDraft = Math.round(value) })
              Button(I18n.t('settings_view_apply')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
                .onClick(() => { this.setNavigationMaxFov(this.maxFovDraft) })
            }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })

            Row({ space: 6 }) {
              Button(I18n.t('settings_save_all')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1).onClick(() => { this.saveAllCoreSettings() })
              Button(I18n.t('settings_restore_defaults')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1).onClick(() => { this.restoreCoreDefaults() })
            }.width('100%').margin({ top: 2, bottom: 8 })
          }
        }
          .width('100%')
          .opacity(this.configTabContentOpacity)
          .translate({ x: this.configTabContentOffsetX, y: 0 })
          .id('config-content-' + this.i18nLang)
      }.width('100%')
  }
}
