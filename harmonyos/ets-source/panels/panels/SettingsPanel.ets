import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { curves } from '@kit.ArkUI'
import { I18n, PROJECTION_KEYS } from '../../pages/I18n'
import { DEFAULT_HAPTIC_INTENSITY } from '../../capability/HapticFeedback'
import { TabItem, PluginItem } from '../../pages/StellariumTypes'
import { ConfigurationOption } from '../../pages/MainWindowModels'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { panelFontSize, uiControlHeight } from '../../common/ui/UiTypography'
import { GyroStore } from '../../state/GyroStore'
import { OverlayStore } from '../../state/OverlayStore'
import { DeltaTStore } from '../../state/DeltaTStore'
import { TimeSettingsStore } from '../../state/TimeSettingsStore'
import { EphemerisStore } from '../../state/EphemerisStore'
import { PluginStore } from '../../state/PluginStore'
import { NavigationSettingsStore } from '../../state/NavigationSettingsStore'
import { ViewSettingsStore } from '../../state/ViewSettingsStore'
import { NotificationStore } from '../../state/NotificationStore'
import { ToolsStore } from '../../state/ToolsStore'
import { EphemerisToggleRow, InformationModeButton, InformationSwitchRow, NavigationSwitchRow } from '../settings/SettingsRows'
import { SettingsChoiceButton } from '../../common/ui/SettingsChoiceButton'
import { LanguageRow, DeviceSection } from '../settings/DeviceAndLanguageRows'
import { AboutSection } from '../settings/AboutSection'
import { NotificationSection } from '../settings/NotificationSection'
import { AstronomyReminderItem } from '../../qability/AstronomyReminderService'
import { HapticSection } from '../settings/HapticSection'
import { KeyboardShortcutSection } from '../settings/KeyboardShortcutSection'
import { KeyboardShortcutStore } from '../../state/KeyboardShortcutStore'
import { KeyboardShortcutItem } from '../../common/types/StellariumTypes'
import { TimeSettingsSection } from '../settings/TimeSettingsSection'
import { PluginCenterSection } from '../settings/PluginCenterSection'
import { DeltaTSettingsBlock } from '../time/DeltaTSettingsBlock'
import { sensZh, scriptZh, scriptDesc } from '../../common/derive/labels'
import { configDitheringLabel } from '../../common/derive/skycult'

// 「设置」面板，对应 activePanel === 'settings'：设备与隐私 / 主设置 / 信息 / 天空 /
// 时间 / 数据 / 插件管理 / 视图导航 / 关于 9 个子标签页。
//
// 实时状态集中在九个 @Observed store（gyro / overlay / deltaT / timeSettings / ephemeris /
// plugin / navigation / viewSettings / tools，均 @ObjectLink），其余标量与主题色走 @Prop；
// 标签/文案纯函数多数直连 common/derive/labels，宿主私有助手与全部动作经回调注入。
// 最大视场用本地草稿 maxFovDraft（aboutToAppear 与 store 同步）：拖动只改草稿，
// 点"应用"才经 setNavigationMaxFov 下发生效。
// 所有标签共用宿主面板 Scroll；切换标签只请求宿主把当前面板滚回顶部。

interface FontScaleChoice {
  mode: string
  label: string
}

const FONT_SCALE_CHOICES: FontScaleChoice[] = [
  { mode: 'system', label: '系统' },
  { mode: 'standard', label: '标准' },
  { mode: 'large', label: '偏大' },
  { mode: 'xlarge', label: '大号' }
]

@Component
export struct SettingsPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @StorageProp('stellariumSystemFontScale') systemFontScale: number = 1.0
  @Prop uiFontScaleMode: string = 'system'
  setUiFontScaleMode: (mode: string) => void = () => {}
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
  // 无线控制（内网设备用浏览器/脚本/API 操作星图，含密钥鉴权与 CORS）
  @Prop remoteControlEnabled: boolean
  @Prop @Watch('onRemoteStatusChanged') remoteControlStatus: string
  @Prop remoteControlPort: string
  @Prop remoteControlUrl: string
  @Prop remoteControlPassword: string
  @Prop remoteControlCors: boolean
  onToggleRemoteControl: (enabled: boolean, port: string) => void = () => {}
  onRemotePortInput: (port: string) => void = () => {}
  onRemotePasswordInput: (password: string) => void = () => {}
  onToggleRemoteCors: (enabled: boolean) => void = () => {}
  onRegenerateRemotePassword: () => void = () => {}
  onApplyRemoteControl: () => void = () => {}
  onCopyRemoteText: (text: string, hint: string) => void = () => {}
  @ObjectLink toolsStore: ToolsStore
  @Prop @Watch('onConfigTabChanged') configTab: number
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
  @State private c: ThemeSlots = DEFAULT_SLOTS
  // 最大视场用本地草稿 maxFovDraft（aboutToAppear 与 store 同步）：拖动只改草稿，
  // 点"应用"才经 setNavigationMaxFov 下发生效。
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
  // 设置页不再持有内嵌 Scroll，切换标签时由宿主把当前面板滚回顶部。
  onRequestScrollTop: () => void = () => {}
  setLanguage: (lang: string) => void = () => {}
  setEphemerisEnabled: (key: string, available: boolean, enabled: boolean) => void = () => {}
  setDistanceUnit: (useMetric: boolean) => void = () => {}
  setConfigurationDithering: (value: string) => void = () => {}
  setDecimalDegreesCoords: (enabled: boolean) => void = () => {}
  setDecimalDegreesOther: (enabled: boolean) => void = () => {}
  setProjection: (name: string) => void = () => {}
  saveAppSettings: () => void = () => {}
  flashHint: (text: ResourceStr) => void = () => {}
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
  openAstronomyCalendar: () => void = () => {}
  refreshReminders: () => void = () => {}
  previewReminder: (item: AstronomyReminderItem) => void = () => {}
  cancelReminder: (id: number) => void = () => {}
  @Prop hapticEnabled: boolean = false
  @Prop hapticAvailable: boolean = false
  @Prop hapticFailed: boolean = false
  @Prop hapticBusy: boolean = false
  @Prop hapticErrorCode: number = 0
  @Prop hapticSystemFeedback: number = -1
  @Prop hapticIntensity: number = DEFAULT_HAPTIC_INTENSITY
  setHapticEnabled: (enabled: boolean) => void = () => {}
  setHapticIntensity: (value: number, commit: boolean) => void = () => {}
  openSystemHapticSettings: () => void = () => {}
  previewHaptic: () => void = () => {}
  scheduleNextSolarTermReminder: () => void = () => {}
  scheduleNextMoonPhaseReminder: () => void = () => {}
  scheduleNextMeteorReminder: () => void = () => {}
  scheduleCountdownReminder: (minutes: number) => void = () => {}
  scheduleCalendarReminder: (timestamp: number) => void = () => {}
  scheduleDailyAlarmReminder: (hour: number, minute: number) => void = () => {}
  toggleAstronomyEvents: (enabled: boolean) => void = () => {}
  toggleSatellitePass: (enabled: boolean) => void = () => {}
  toggleDigest: (enabled: boolean) => void = () => {}
  toggleNotificationDnd: (enabled: boolean) => void = () => {}
  toggleNotificationDndSatelliteOnly: (enabled: boolean) => void = () => {}
  setNotificationDndStart: (minutes: number) => void = () => {}
  setNotificationDndEnd: (minutes: number) => void = () => {}
  changePassLead: (delta: number) => void = () => {}
  fetchPushToken: () => void = () => {}
  @Prop pushTokenText: string
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
  openExternalUrl: (url: string) => void = () => {}

  aboutToAppear(): void {
    this.maxFovDraft = this.navigationStore.navigationMaxFov
  }

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private onRemoteStatusChanged(): void {}

  // 切换设置页时回到顶部；所有标签共用宿主面板 Scroll。
  private onConfigTabChanged(): void {
    this.onRequestScrollTop()
  }

  private confirmRestoreDefaults(): void {
    AlertDialog.show({
      title: '恢复默认设置',
      message: '将重置引擎配置与界面偏好；收藏、观测列表等用户数据会保留。需要重启应用生效。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '恢复',
        action: () => { this.restoreCoreDefaults() }
      }
    })
  }

  // 脚本页：头部固定，列表占满面板剩余高度并自行滚动。
  @Builder
  scriptTabContent() {
    Column({ space: 0 }) {
      Row() {
        Text(I18n.t('i0122')).fontSize(12).fontColor(this.c.sub).width(72)
        Button(I18n.t('i0252')).fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
          .onClick(() => { this.triggerAction('actionStop_Script') })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      Row() {
        Text(I18n.t('i0123')).fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 4 })
      }.height(18).width('100%')
      if (this.scriptLaunching) {
        Row({ space: 6 }) {
          LoadingProgress().width(16).height(16).color(this.c.accent)
          Text(I18n.format('script_starting_named', [scriptZh(this.scriptLaunchingName)])).fontSize(10).fontColor(this.c.sub)
        }.width('100%').padding({ left: 8, right: 8, bottom: 4 })
      }
      Column({ space: 2 }) {
          ForEach(this.scriptList, (s: string) => {
            Column({ space: 0 }) {
              Row() {
                Text(scriptZh(s)).fontSize(11).fontColor(this.c.text)
                  .fontWeight(FontWeight.Medium).layoutWeight(1)
                Text('▶').fontSize(10).fontColor(this.c.iconSecondary)
              }
              .height(28).width('100%').padding({ left: 10, right: 10 })
              if (scriptDesc(s)) {
                Text(scriptDesc(s))
                  .fontSize(10).fontColor(this.c.sub).width('100%')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 10, right: 10, bottom: 3 })
              }
              if (this.scriptMetaLine(s).length > 0) {
                Text(this.scriptMetaLine(s))
                  .fontSize(10).fontColor(this.c.tertiary).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 10, right: 10, bottom: 3 })
              }
              if (this.scriptSourceLine(s).length > 0) {
                Text(this.scriptSourceLine(s)).fontSize(10).fontColor(this.c.tertiary).width('100%').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 10, right: 10, bottom: 3 })
              }
            }
            .width('100%')
            .backgroundColor(this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL)
            .opacity(this.scriptLaunching && this.scriptLaunchingName !== s ? 0.55 : 1)
              .hitTestBehavior(HitTestMode.Default)
            .onClick(() => { this.playScriptByName(s) })
          }, (s: string, index: number) => s)
      }
        .width('100%')
    }
    .width('100%')
    .padding({ bottom: 16 })
  }


  build() {

      Column() {
        // 与「图层」面板的 LayerTabs 保持同一套标签尺寸与字号：
        // 12/14sp、最小 60/76×36/40vp、左右 10/13vp、上下 6vp。
        Scroll() {
          Row({ space: 6 }) {
          ForEach([
            { label: I18n.t('settings_device_privacy'), id: -1 },
            { label: I18n.t('c0000'), id: 0 },
            { label: I18n.t('c0001'), id: 1 },
            { label: I18n.t('c0002'), id: 2 },
            { label: I18n.t('c0003'), id: 3 },
            { label: I18n.t('c0005'), id: 5 },
            { label: I18n.t('more_plugins_manage'), id: 6 },
            { label: I18n.t('settings_view_navigation'), id: 7 },
            { label: I18n.t('c_about'), id: 8 },
          ] as TabItem[], (tab: TabItem) => {
            Text(tab.label)
              .fontSize(panelFontSize(12, this.readableUi))
              .fontWeight(this.configTab === tab.id ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.configTab === tab.id ? this.c.onAccent : this.c.sub)
              .textAlign(TextAlign.Center)
              .constraintSize({ minHeight: uiControlHeight(34, this.readableUi, this.controlScale) })
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.configTab === tab.id ? this.c.accent : this.c.input)
              .borderRadius(UI_RADIUS_CONTROL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .animation({ duration: 180, curve: Curve.EaseInOut })
              .onClick(() => { this.selectConfigTab(tab.id) })
          }, (tab: TabItem, index: number) => tab.id.toString() + '-' + this.i18nLang)
          }.padding({ left: 2, right: 8 })
        }.width('100%').height(uiControlHeight(42, this.readableUi, this.controlScale)).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .margin({ top: 4, bottom: 10 }).id('config-tabs-' + this.i18nLang)
        Column({ space: 0 }) {
          if (this.configTab === 5) {
            this.scriptTabContent()
          } else {
            Column({ space: 0 }) {
                if (this.configTab === -1) {
            Text(I18n.t('i0060'))
              .fontSize(11).fontColor(this.c.sub).width('100%')
              .margin({ top: 2, bottom: 6 }).padding({ left: 2 })
            DeviceSection({
              gyroscopeEnabled: this.gyroStore.gyroscopeEnabled,
              sensitivityText: sensZh(this.gyroStore.gyroscopeSensitivityText),
              onToggleGyroscope: (v: boolean) => {
                this.toggleGyroscope(v)
                this.flashHint(v ? I18n.t('s0719') : I18n.t('s0720'))
              }
            })
            Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 5, bottom: 8 })
            Text(I18n.t('settings_section_feedback'))
              .fontSize(11).fontColor(this.c.sub).width('100%')
              .margin({ top: 2, bottom: 6 }).padding({ left: 2 })
            HapticSection({
              hapticEnabled: this.hapticEnabled, available: this.hapticAvailable, failed: this.hapticFailed, busy: this.hapticBusy,
              errorCode: this.hapticErrorCode, systemFeedback: this.hapticSystemFeedback,
              intensity: this.hapticIntensity,
              onChange: (enabled: boolean) => this.setHapticEnabled(enabled),
              onIntensityChange: (value: number, commit: boolean) => this.setHapticIntensity(value, commit),
              onOpenSystemSettings: () => this.openSystemHapticSettings(),
              onPreview: () => this.previewHaptic()
            })
            Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 5, bottom: 8 })
            Text(I18n.t('settings_section_notifications'))
              .fontSize(11).fontColor(this.c.sub).width('100%')
              .margin({ top: 2, bottom: 6 }).padding({ left: 2 })
            NotificationSection({
              notificationEnabled: this.notificationStore.astronomyNotificationEnabled,
              notificationBusy: this.notificationStore.astronomyNotificationBusy,
              reminderCount: this.notificationStore.astronomyReminderCount,
              statusText: this.notificationStore.astronomyNotificationStatus,
              reminders: this.notificationStore.astronomyReminders,
              reminderListLoaded: this.notificationStore.astronomyReminderListLoaded,
              reminderListError: this.notificationStore.astronomyReminderListError,
              preferencesBusy: this.notificationStore.notificationPreferencesBusy,
              preferencesError: this.notificationStore.notificationPreferencesError,
              astronomySubscriptionStatus: this.notificationStore.astronomySubscriptionStatus,
              satelliteSubscriptionStatus: this.notificationStore.satelliteSubscriptionStatus,
              onOpenCalendar: () => this.openAstronomyCalendar(),
              onRefreshReminders: () => this.refreshReminders(),
              onPreviewReminder: (item: AstronomyReminderItem) => this.previewReminder(item),
              onCancelReminder: (id: number) => this.cancelReminder(id),
              onRequestAccess: () => { this.requestNotificationAccess() },
              onScheduleNextSolarTerm: () => { this.scheduleNextSolarTermReminder() },
              onScheduleNextMoonPhase: () => { this.scheduleNextMoonPhaseReminder() },
              onScheduleNextMeteor: () => { this.scheduleNextMeteorReminder() },
              onScheduleCountdown: (minutes: number) => { this.scheduleCountdownReminder(minutes) },
              onScheduleCalendarAt: (timestamp: number) => { this.scheduleCalendarReminder(timestamp) },
              onScheduleAlarm: (hour: number, minute: number) => { this.scheduleDailyAlarmReminder(hour, minute) },
              astronomyEventsEnabled: this.notificationStore.astronomyEventsEnabled,
              satellitePassEnabled: this.notificationStore.satellitePassEnabled,
              digestEnabled: this.notificationStore.digestEnabled,
              dndEnabled: this.notificationStore.dndEnabled,
              dndSatelliteOnly: this.notificationStore.dndSatelliteOnly,
              dndStartMinutes: this.notificationStore.dndStartMinutes,
              dndEndMinutes: this.notificationStore.dndEndMinutes,
              passLeadMinutes: this.notificationStore.passLeadMinutes,
              onToggleAstronomyEvents: (v: boolean) => { this.toggleAstronomyEvents(v) },
              onToggleSatellitePass: (v: boolean) => { this.toggleSatellitePass(v) },
              onToggleDigest: (v: boolean) => { this.toggleDigest(v) },
              onToggleDnd: (v: boolean) => { this.toggleNotificationDnd(v) },
              onToggleDndSatelliteOnly: (v: boolean) => { this.toggleNotificationDndSatelliteOnly(v) },
              onDndStartChange: (m: number) => { this.setNotificationDndStart(m) },
              onDndEndChange: (m: number) => { this.setNotificationDndEnd(m) },
              onLeadChange: (d: number) => { this.changePassLead(d) },
              pushTokenText: this.pushTokenText,
              onFetchPushToken: () => { this.fetchPushToken() },
              onClearReminders: () => { this.clearAstronomyReminders() }
            })
            Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 5, bottom: 8 })
            Text(I18n.t('settings_section_privacy'))
              .fontSize(11).fontColor(this.c.sub).width('100%')
              .margin({ top: 2, bottom: 6 }).padding({ left: 2 })
            Button(I18n.t('privacy_revoke'))
              .fontSize(13).fontColor(this.c.errorText).backgroundColor(this.c.errorBg)
              .border({ width: 1, color: this.c.errorBg })
              .borderRadius(UI_RADIUS_CONTROL).height(38).width('100%')
              .margin({ bottom: 12 })
              .onClick(() => { this.confirmPrivacyRevocation() })
          } else if (this.configTab === 0) {
            Row({ space: 6 }) {
              Row({ space: 2 }) {
                Text('恢复默认设置')
                  .fontSize(Math.round(panelFontSize(14, this.readableUi) * this.uiFontScale))
                  .fontColor(this.c.text)
                InfoTipButton({
                  title: '恢复默认设置',
                  tip: '重置引擎配置与界面偏好；收藏、观测列表等用户数据会保留。需要重启应用生效。'
                })
              }
              .layoutWeight(1)
              .alignItems(VerticalAlign.Center)
              .padding({ left: 10 })
              Button('重置', { type: ButtonType.Capsule })
                .fontSize(Math.round(panelFontSize(13, this.readableUi) * this.uiFontScale))
                .fontColor(this.c.errorText)
                .backgroundColor(this.c.errorBg)
                .constraintSize({ minHeight: uiControlHeight(36, this.readableUi, this.controlScale) })
                .padding({ left: 18, right: 18, top: 6, bottom: 6 })
                .margin({ right: 8 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.confirmRestoreDefaults() })
            }
            .constraintSize({ minHeight: uiControlHeight(48, this.readableUi, this.controlScale) })
            .padding({ top: 6, bottom: 6 })
            .width('100%')
            .backgroundColor(this.c.bg)
            .border({ width: 1, color: this.c.dividerSoft })
            .borderRadius(UI_RADIUS_CARD)
            .margin({ bottom: 6 })
            LanguageRow({ selectedLanguage: this.selectedLanguage, onSelect: (code: string) => { this.setLanguage(code) } })
            // 统一界面字体与按钮尺寸分级控制（跟随系统或手动 3 档，统筹管理按钮行高与字号）
            Column({ space: 8 }) {
              Row() {
                Row({ space: 2 }) {
                  Text('界面字体与按钮大小')
                    .fontSize(Math.round(panelFontSize(13, this.readableUi) * this.uiFontScale))
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.c.text)
                  InfoTipButton({
                    title: '界面字体与按钮大小',
                    tip: '已适配系统字体缩放（上限 145%），按钮与行高随字号同步调整，避免截断或重叠。'
                  })
                }.layoutWeight(1).alignItems(VerticalAlign.Center)
                Text(this.uiFontScaleMode === 'system'
                  ? ('跟随系统 · ' + Math.round(this.systemFontScale * 100).toString() + '%')
                  : (this.uiFontScaleMode === 'standard' ? '标准 100%' : (this.uiFontScaleMode === 'large' ? '偏大 115%' : '大号 130%')))
                  .fontSize(Math.round(panelFontSize(11, this.readableUi) * this.uiFontScale))
                  .fontColor(this.c.accent)
              }.width('100%').alignItems(VerticalAlign.Center)
              Row({ space: 6 }) {
                ForEach(FONT_SCALE_CHOICES, (opt: FontScaleChoice) => {
                  Row() {
                    Text(opt.label)
                      .fontSize(Math.round(panelFontSize(12, this.readableUi) * this.uiFontScale))
                      .maxFontScale(1.25)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .fontWeight(this.uiFontScaleMode === opt.mode ? FontWeight.Medium : FontWeight.Regular)
                      .fontColor(this.uiFontScaleMode === opt.mode ? this.c.onAccent : this.c.sub)
                  }
                  .layoutWeight(1)
                  .constraintSize({ minHeight: uiControlHeight(34, this.readableUi, this.controlScale) })
                  .padding({ left: 4, right: 4, top: 6, bottom: 6 })
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                  .backgroundColor(this.uiFontScaleMode === opt.mode ? this.c.accent : this.c.input)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
                  .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .onClick(() => { this.setUiFontScaleMode(opt.mode) })
                }, (opt: FontScaleChoice) => opt.mode)
              }.width('100%')
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.c.soft)
            .border({ width: 1, color: this.c.border })
            .borderRadius(UI_RADIUS_CARD)
            .margin({ top: 6, bottom: 6 })
            Row({ space: 2 }) {
              Text('行星历表').fontSize(12).fontColor(this.c.sub)
              InfoTipButton({
                title: '行星历表',
                tip: '用于行星位置计算的 JPL 数值星历。仅显示设备中已安装的文件。'
              })
            }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 2 }).alignItems(VerticalAlign.Center)
            EphemerisToggleRow({ label: 'DE430', available: this.ephemerisStore.ephemerisDe430Available, isEnabled: this.ephemerisStore.ephemerisDe430Active, onToggle: (v: boolean) => { this.setEphemerisEnabled('de430', this.ephemerisStore.ephemerisDe430Available, v) } })
            EphemerisToggleRow({ label: 'DE431', available: this.ephemerisStore.ephemerisDe431Available, isEnabled: this.ephemerisStore.ephemerisDe431Active, onToggle: (v: boolean) => { this.setEphemerisEnabled('de431', this.ephemerisStore.ephemerisDe431Available, v) } })
            EphemerisToggleRow({ label: 'DE440', available: this.ephemerisStore.ephemerisDe440Available, isEnabled: this.ephemerisStore.ephemerisDe440Active, onToggle: (v: boolean) => { this.setEphemerisEnabled('de440', this.ephemerisStore.ephemerisDe440Available, v) } })
            EphemerisToggleRow({ label: 'DE441', available: this.ephemerisStore.ephemerisDe441Available, isEnabled: this.ephemerisStore.ephemerisDe441Active, onToggle: (v: boolean) => { this.setEphemerisEnabled('de441', this.ephemerisStore.ephemerisDe441Available, v) } })
            Row() {
              Text(I18n.t('set_distance_units')).fontSize(12).fontColor(this.c.sub).layoutWeight(1)
              Row({ space: 6 }) {
                Text(I18n.t('unit_km'))
                  .fontSize(12).fontColor(this.viewSettingsStore.useMetricUnits ? this.c.onAccent : this.c.tertiary)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.viewSettingsStore.useMetricUnits ? this.c.accent : this.c.input)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => {
                    this.setDistanceUnit(true)
                  })
                Text(I18n.t('unit_mile'))
                  .fontSize(12).fontColor(!this.viewSettingsStore.useMetricUnits ? this.c.onAccent : this.c.tertiary)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(!this.viewSettingsStore.useMetricUnits ? this.c.accent : this.c.input)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => {
                    this.setDistanceUnit(false)
                  })
              }
            }.constraintSize({ minHeight: 42 }).width('100%').padding({ left: 12, right: 10 }).margin({ top: 4, bottom: 4 })
              .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft }).borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Button(I18n.t('i0251') + '设置')
                .fontSize(Math.round(panelFontSize(12, this.readableUi) * this.uiFontScale))
                .fontColor(this.c.text).backgroundColor(this.c.bg)
                .border({ width: 1, color: this.c.dividerSoft })
                .borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: uiControlHeight(36, this.readableUi, this.controlScale) })
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.saveAppSettings(); this.flashHint('设置已保存') })
            }.width('100%').padding({ left: 2, right: 2 }).margin({ top: 4 })
            Row({ space: 2 }) {
              Text('无线控制（HTTP API / 网页遥控）').fontSize(12).fontColor(this.c.sub)
              InfoTipButton({
                title: '无线控制',
                tip: '开启后，同一 Wi-Fi 下的电脑、手机或脚本可凭访问密钥通过网页或标准 Stellarium /api/* 接口控制星图（支持 Basic 认证、Bearer 令牌与 X-API-Key）。'
              })
            }.width('100%').padding({ left: 8 }).margin({ top: 10, bottom: 4 }).alignItems(VerticalAlign.Center)
            Column({ space: 8 }) {
              Row() {
                Column({ space: 2 }) {
                  Text('允许内网设备控制').fontSize(13).fontColor(this.c.text).width('100%')
                  Text(this.remoteControlEnabled ? '服务运行中 · 已启用密钥鉴权' : '服务已关闭').fontSize(10).fontColor(this.remoteControlEnabled ? this.c.accent : this.c.sub).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.remoteControlEnabled }).width(44).height(26)
                  .selectedColor(this.c.accent)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onChange((value: boolean) => {
                    if (value !== this.remoteControlEnabled) {
                      this.onToggleRemoteControl(value, this.remoteControlPort)
                    }
                  })
              }.width('100%')
              if (this.remoteControlEnabled && this.remoteControlUrl.length > 0) {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text('访问地址').fontSize(10).fontColor(this.c.sub).width('100%')
                    Text(this.remoteControlUrl).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.accent).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Button('复制地址').fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 10, right: 10 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT })
                    .onClick(() => { this.onCopyRemoteText(this.remoteControlUrl, '已复制无线控制地址') })
                }.width('100%')
              }
              Row({ space: 8 }) {
                Text('端口').fontSize(12).fontColor(this.c.sub).width(56)
                TextInput({ text: this.remoteControlPort, placeholder: '8090' }).height(36).fontSize(12)
                  .fontColor(this.c.text).backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).layoutWeight(1)
                  .type(InputType.Number)
                  .onChange((value: string) => { this.onRemotePortInput(value) })
              }.width('100%')
              Row({ space: 8 }) {
                Text('访问密钥').fontSize(12).fontColor(this.c.sub).width(56)
                TextInput({ text: this.remoteControlPassword, placeholder: '开启时自动生成' }).height(36).fontSize(12)
                  .fontColor(this.c.text).backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).layoutWeight(1)
                  .type(InputType.Password)
                  .showPasswordIcon(true)
                  .onChange((value: string) => { this.onRemotePasswordInput(value) })
              }.width('100%')
              Row({ space: 6 }) {
                Button('换新密钥').fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.onRegenerateRemotePassword() })
                if (this.remoteControlPassword.length > 0) {
                  Button('复制密钥').fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 10, right: 10 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT })
                    .onClick(() => { this.onCopyRemoteText(this.remoteControlPassword, '已复制访问密钥') })
                }
                if (this.remoteControlEnabled && this.remoteControlUrl.length > 0 && this.remoteControlPassword.length > 0) {
                  Button('复制 curl').fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
                    .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 10, right: 10 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT })
                    .onClick(() => {
                      const cmd = 'curl -H "Authorization: Bearer ' + this.remoteControlPassword + '" "' + this.remoteControlUrl + '/api/main/status"'
                      this.onCopyRemoteText(cmd, '已复制 API 调试 curl 命令')
                    })
                }
              }.width('100%')
              Row() {
                Row({ space: 2 }) {
                  Text('允许跨域调用（CORS）').fontSize(12).fontColor(this.c.text)
                  InfoTipButton({
                    title: '允许跨域调用（CORS）',
                    tip: '允许局域网网页工具或第三方前端直接调用 /api/* 接口。'
                  })
                }.layoutWeight(1).alignItems(VerticalAlign.Center)
                Toggle({ type: ToggleType.Switch, isOn: this.remoteControlCors }).width(42).height(24)
                  .selectedColor(this.c.accent)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onChange((value: boolean) => {
                    if (value !== this.remoteControlCors) {
                      this.onToggleRemoteCors(value)
                    }
                  })
              }.width('100%')
              if (this.remoteControlEnabled) {
                Row({ space: 8 }) {
                  Button('应用端口/密钥并重启服务').fontSize(12).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                    .borderRadius(UI_RADIUS_CONTROL).height(36).padding({ left: 14, right: 14 })
                    .clickEffect({ level: ClickEffectLevel.LIGHT })
                    .onClick(() => { this.onApplyRemoteControl() })
                }.width('100%')
              }
              if (this.remoteControlStatus.length > 0) {
                Text(this.remoteControlStatus).fontSize(10).fontColor(this.c.sub).width('100%')
              }
            }.width('100%').padding(12).backgroundColor(this.c.rowBg)
              .border({ width: 1, color: this.c.border }).borderRadius(UI_RADIUS_CARD).margin({ bottom: 8 })
          } else if (this.configTab === 1) {
            Row() {
              Text(I18n.t('i0120')).fontSize(12).fontColor(this.c.sub).width(72)
            }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              InformationModeButton({ labelKey: 'i0247', active: this.informationMode === 'all', canPick: !this.informationSettingPending, onPick: () => { this.selectSettingsChoice('information', 'all') } })
              InformationModeButton({ labelKey: 'i0248', active: this.informationMode === 'default', canPick: !this.informationSettingPending, onPick: () => { this.selectSettingsChoice('information', 'default') } })
              InformationModeButton({ labelKey: 'i0249', active: this.informationMode === 'short', canPick: !this.informationSettingPending, onPick: () => { this.selectSettingsChoice('information', 'short') } })
              InformationModeButton({ labelKey: 'i0250', active: this.informationMode === 'none', canPick: !this.informationSettingPending, onPick: () => { this.selectSettingsChoice('information', 'none') } })
              InformationModeButton({ labelKey: 'information_custom_mode', active: this.informationMode === 'custom', canPick: !this.informationSettingPending, onPick: () => { this.selectSettingsChoice('information', 'custom') } })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
            Row({ space: 6 }) {
              Row({ space: 2 }) {
                Text(I18n.t('detail_observe_toggle')).fontSize(13).fontColor(this.c.text)
                InfoTipButton({
                  title: I18n.t('detail_observe_toggle'),
                  tip: I18n.t('detail_observe_hint')
                })
              }.layoutWeight(1).alignItems(VerticalAlign.Center)
              Toggle({ type: ToggleType.Switch, isOn: this.observeMode })
                .width(44).height(26).selectedColor(this.c.accent)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onChange((value: boolean) => { this.onToggleObserveMode(value) })
            }.width('100%').constraintSize({ minHeight: 42 }).padding({ left: 12, right: 10 })
              .backgroundColor(this.observeMode ? this.c.soft : this.c.bg)
              .border({ width: 1, color: this.observeMode ? this.c.soft : this.c.dividerSoft })
              .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
              .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
            Row({ space: 6 }) {
              Row({ space: 2 }) {
                Text('详情卡指向线').fontSize(13).fontColor(this.c.text)
                InfoTipButton({
                  title: '详情卡指向线',
                  tip: '在可见天体与详情卡之间显示细连接线，方便在密集星区一眼确认选中目标。'
                })
              }.layoutWeight(1).alignItems(VerticalAlign.Center)
              Toggle({ type: ToggleType.Switch, isOn: this.overlayStore.objectDetailConnectorVisible })
                .width(44).height(26).selectedColor(this.c.accent)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onChange((value: boolean) => { this.setObjectDetailConnector(value) })
            }.width('100%').constraintSize({ minHeight: 42 }).padding({ left: 12, right: 10 })
              .backgroundColor(this.overlayStore.objectDetailConnectorVisible ? this.c.soft : this.c.bg)
              .border({ width: 1, color: this.overlayStore.objectDetailConnectorVisible ? this.c.soft : this.c.dividerSoft })
              .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
              .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
            Row({ space: 2 }) {
              Text('自定义信息字段').fontSize(12).fontColor(this.c.sub)
              InfoTipButton({
                title: '自定义信息字段',
                tip: '选择「自定义」模式后，详情卡和星体信息栏只显示下面勾选的字段。'
              })
            }.width('100%').padding({ left: 8 }).margin({ top: 6, bottom: 4 }).alignItems(VerticalAlign.Center)
            InformationSwitchRow({ label: '名称', isOn: this.informationMaskHas('name'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('name', v) } })
            InformationSwitchRow({ label: '目录编号', isOn: this.informationMaskHas('catalog'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('catalog', v) } })
            InformationSwitchRow({ label: '视星等', isOn: this.informationMaskHas('magnitude'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('magnitude', v) } })
            InformationSwitchRow({ label: '赤经、赤纬（J2000）', isOn: this.informationMaskHas('raJ2000'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('raJ2000', v) } })
            InformationSwitchRow({ label: '赤经、赤纬（历元）', isOn: this.informationMaskHas('raOfDate'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('raOfDate', v) } })
            InformationSwitchRow({ label: '方位角、高度角', isOn: this.informationMaskHas('altAz'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('altAz', v) } })
            InformationSwitchRow({ label: '距离', isOn: this.informationMaskHas('distance'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('distance', v) } })
            InformationSwitchRow({ label: '时角', isOn: this.informationMaskHas('hourAngle'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('hourAngle', v) } })
            InformationSwitchRow({ label: '升起、中天、落下时间', isOn: this.informationMaskHas('riseTransitSet'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('riseTransitSet', v) } })
            InformationSwitchRow({ label: '大小或角直径', isOn: this.informationMaskHas('size'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('size', v) } })
            InformationSwitchRow({ label: '轨道与光照信息', isOn: this.informationMaskHas('elongation'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('elongation', v) } })
            InformationSwitchRow({ label: '银河坐标', isOn: this.informationMaskHas('galactic'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('galactic', v) } })
            InformationSwitchRow({ label: '星座信息', isOn: this.informationMaskHas('constellation'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('constellation', v) } })
            InformationSwitchRow({ label: '恒星时', isOn: this.informationMaskHas('siderealTime'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('siderealTime', v) } })
            InformationSwitchRow({ label: '附加资料', isOn: this.informationMaskHas('extra'), inCustomMode: this.informationMode === 'custom', canToggle: this.informationMode === 'custom' && !this.informationSettingPending, onToggle: (v: boolean) => { this.setInformationField('extra', v) } })
          } else if (this.configTab === 2) {
            Row({ space: 8 }) {
              Text('天空显示设置已统一到「图层 > 天空」').fontSize(12).fontColor(this.c.sub).layoutWeight(1).maxLines(2)
              Button('前往').fontSize(12).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                .borderRadius(UI_RADIUS_CONTROL).height(34).padding({ left: 14, right: 14 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.onOpenLayersSky() })
            }.width('100%').padding({ left: 12, right: 10, top: 10, bottom: 10 })
              .backgroundColor(this.c.soft).border({ width: 1, color: this.c.border }).borderRadius(UI_RADIUS_CARD)
            Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 10, bottom: 8 })
            Row({ space: 6 }) {
              Row({ space: 2 }) {
                Text(I18n.t('set_projection')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.text)
                InfoTipButton({
                  title: I18n.projectionName(this.currentProjection),
                  tip: I18n.projectionDesc(this.currentProjection)
                })
              }.layoutWeight(1).alignItems(VerticalAlign.Center)
              Text(I18n.projectionName(this.currentProjection)).fontSize(12).fontColor(this.c.accent).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
            Scroll() {
              Row({ space: 6 }) {
                ForEach(PROJECTION_KEYS, (name: string) => {
                  Text(I18n.projectionName(name)).fontSize(12)
                    .fontColor(this.currentProjection === name ? this.c.onAccent : this.c.sub)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.currentProjection === name ? this.c.accent : this.c.bg)
                    .border({ width: 1, color: this.currentProjection === name ? this.c.accent : this.c.dividerSoft })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT })
                    .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .onClick(() => { this.setProjection(name) })
                }, (name: string) => name)
              }.padding({ left: 2, right: 8 })
            }.width('100%').height(38).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 6 })
            Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 6, bottom: 8 })
            Row({ space: 6 }) {
              Row({ space: 2 }) {
                Text('色彩抖动').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.text)
                InfoTipButton({
                  title: '色彩抖动',
                  tip: '抖动用于低色深屏幕的颜色平滑过渡，可减少暗夜渐变色带；通常保持 8/8/8 位。'
                })
              }.layoutWeight(1).alignItems(VerticalAlign.Center)
              Text(configDitheringLabel(this.configDitheringMode)).fontSize(12).fontColor(this.c.accent)
            }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 6 })
            Scroll() {
              Row({ space: 6 }) {
                ForEach([
                  { id: 'Disabled', label: '关闭' }, { id: 'Color565', label: '5/6/5 位' },
                  { id: 'Color666', label: '6/6/6 位' }, { id: 'Color888', label: '8/8/8 位' },
                ] as ConfigurationOption[], (option: ConfigurationOption) => {
                  Text(option.label).fontSize(12)
                    .fontColor(this.configDitheringMode === option.id ? this.c.onAccent : this.c.sub)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.configDitheringMode === option.id ? this.c.accent : this.c.bg)
                    .border({ width: 1, color: this.configDitheringMode === option.id ? this.c.accent : this.c.dividerSoft })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .clickEffect({ level: ClickEffectLevel.LIGHT })
                    .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                    .onClick(() => { this.setConfigurationDithering(option.id) })
                }, (option: ConfigurationOption) => option.id)
              }.padding({ left: 2, right: 8 })
            }.width('100%').height(38).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ bottom: 6 })
            Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 4, bottom: 8 })
            Row({ space: 2 }) {
              Text(I18n.t('settings_decimal_degrees_title')).fontSize(12).fontColor(this.c.sub)
              InfoTipButton({
                title: I18n.t('settings_decimal_degrees_title'),
                tip: I18n.t('settings_decimal_degrees_hint')
              })
            }.width('100%').padding({ left: 4 }).margin({ top: 2, bottom: 5 }).alignItems(VerticalAlign.Center)
            NavigationSwitchRow({
              label: I18n.t('settings_decimal_degrees_coords'),
              isOn: this.viewSettingsStore.decimalDegreesCoords,
              onToggle: (v: boolean) => { this.setDecimalDegreesCoords(v) }
            })
            NavigationSwitchRow({
              label: I18n.t('settings_decimal_degrees_other'),
              isOn: this.viewSettingsStore.decimalDegreesOther,
              onToggle: (v: boolean) => { this.setDecimalDegreesOther(v) }
            })
          } else if (this.configTab === 3) {
            TimeSettingsSection({
              store: this.timeSettingsStore,
              pending: this.timeSettingsPending,
              observationTimeText: this.observationTimeText,
              onSelectFormat: (group: string, value: string) => { this.selectSettingsChoice(group, value) },
              onSetStartup: (key: string, value: string) => { this.setStartupTimeSetting(key, value) }
            })
            DeltaTSettingsBlock({
              store: this.deltaTStore,
              pending: this.timeSettingsPending,
              onSelect: (key: string) => { this.setStartupTimeSetting('deltaT', key) },
              onSaveCustom: (text: string) => { this.setStartupTimeSetting('deltaCustom', text) }
            })
          } else if (this.configTab === 6) {
            PluginCenterSection({
              pluginStore: this.pluginStore,
              pluginMetaLine: (pl: PluginItem) => this.pluginMetaLine(pl),
              pluginFeatureDestination: (id: string) => this.pluginFeatureDestination(id),
              pluginFeatureIsActionable: (id: string) => this.pluginFeatureIsActionable(id),
              pluginFeatureActionLabel: (id: string) => this.pluginFeatureActionLabel(id),
              onRefresh: () => { this.loadPluginList() },
              onOpenFeature: (id: string) => { this.openPluginFeature(id) }
            })
          } else if (this.configTab === 7) {
            Row({ space: 2 }) {
              Text(I18n.t('settings_view_navigation')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.c.text)
              InfoTipButton({
                title: I18n.t('settings_view_navigation'),
                tip: I18n.t('settings_view_navigation_hint')
              })
            }.width('100%').margin({ top: 2, bottom: 6 }).alignItems(VerticalAlign.Center)
            Text(I18n.t('settings_view_current')).fontSize(12).fontColor(this.c.sub).width('100%').margin({ bottom: 5 })
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(I18n.t('settings_view_current_fov')).fontSize(10).fontColor(this.c.sub)
                Text(this.fovText).fontSize(16).fontColor(this.c.text)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button(I18n.t('settings_view_center')).fontSize(12).fontColor(this.c.text).backgroundColor(this.c.softStrong)
                .borderRadius(UI_RADIUS_CONTROL).height(34).padding({ left: 12, right: 12 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .opacity(this.hasSelectedObject() && !this.gyroStore.gyroscopeEnabled ? 1 : 0.58)
                .onClick(() => { this.moveToSelectedObject() })
            }.width('100%').padding({ left: 12, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
              .borderRadius(UI_RADIUS_CARD).margin({ bottom: 8 })

            Row({ space: 6 }) {
              Row({ space: 2 }) {
                Text(I18n.t('set_lock_view')).fontSize(13).fontColor(this.c.text)
                InfoTipButton({
                  title: I18n.t('set_lock_view'),
                  tip: this.viewSettingsStore.viewLock ? I18n.t('view_lock_enabled') : I18n.t('settings_view_lock_hint')
                })
              }.layoutWeight(1).alignItems(VerticalAlign.Center)
              Toggle({ type: ToggleType.Switch, isOn: this.viewSettingsStore.viewLock })
                .width(44).height(26).selectedColor(this.c.accent)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onChange((enabled: boolean) => { this.setViewLockState(enabled) })
            }.width('100%').constraintSize({ minHeight: 44 }).padding({ left: 12, right: 10 })
              .backgroundColor(this.viewSettingsStore.viewLock ? this.c.soft : this.c.bg)
              .border({ width: 1, color: this.viewSettingsStore.viewLock ? this.c.soft : this.c.dividerSoft })
              .borderRadius(UI_RADIUS_CARD).margin({ bottom: 8 })
              .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })

            Text(I18n.t('settings_view_startup')).fontSize(12).fontColor(this.c.sub).width('100%').margin({ bottom: 5 })
            Column({ space: 8 }) {
              Column({ space: 2 }) {
                Text(I18n.format('settings_view_startup_fov', [this.navigationStore.navigationStartupFov.toFixed(1)])).fontSize(12).fontColor(this.c.text).width('100%')
                Text(I18n.format('settings_view_startup_direction', [this.navigationStore.navigationStartupAzimuth.toFixed(1), this.navigationStore.navigationStartupAltitude.toFixed(1)])).fontSize(11).fontColor(this.c.sub).width('100%')
              }.width('100%')
              Button(I18n.t('settings_view_save_current')).fontSize(12).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                .borderRadius(UI_RADIUS_CONTROL).height(36).width('100%')
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.saveCurrentViewAsStartup() })
            }.width('100%').padding(12)
              .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
              .borderRadius(UI_RADIUS_CARD).margin({ bottom: 8 })

            Text(I18n.t('settings_view_max_fov')).fontSize(12).fontColor(this.c.sub).width('100%').margin({ top: 2, bottom: 4 })
            Row({ space: 8 }) {
              Text(this.maxFovDraft.toFixed(0) + '°').fontSize(14).fontColor(this.c.text).width(46)
              Slider({ value: this.maxFovDraft, min: 30, max: 360, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .layoutWeight(1).trackColor(this.c.input).selectedColor(this.c.accent).blockColor(this.c.accent)
                .showSteps(false).onChange((value: number) => { this.maxFovDraft = Math.round(value) })
              Button(I18n.t('settings_view_apply')).fontSize(12).fontColor(this.c.text).backgroundColor(this.c.softStrong)
                .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 12, right: 12 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.setNavigationMaxFov(this.maxFovDraft) })
            }.width('100%').padding({ left: 12, right: 10, top: 6, bottom: 6 }).backgroundColor(this.c.bg)
              .border({ width: 1, color: this.c.dividerSoft }).borderRadius(UI_RADIUS_CARD).margin({ bottom: 8 })

            Text(I18n.t('settings_view_navigation_controls')).fontSize(12).fontColor(this.c.sub).width('100%').margin({ bottom: 5 })
            NavigationSwitchRow({ label: I18n.t('settings_view_mouse_navigation'), isOn: this.navigationStore.navigationMouseEnabled, onToggle: (v: boolean) => { this.setNavigationBoolean('mouseNavigation', v) } })
            NavigationSwitchRow({ label: I18n.t('settings_view_mouse_zoom'), isOn: this.navigationStore.navigationMouseZoomEnabled, onToggle: (v: boolean) => { this.setNavigationBoolean('mouseZooming', v) } })
            NavigationSwitchRow({ label: I18n.t('settings_view_keyboard_navigation'), isOn: this.navigationStore.navigationMoveKeysEnabled, onToggle: (v: boolean) => { this.setNavigationBoolean('moveKeys', v) } })
            NavigationSwitchRow({ label: I18n.t('settings_view_keyboard_zoom'), isOn: this.navigationStore.navigationZoomKeysEnabled, onToggle: (v: boolean) => { this.setNavigationBoolean('zoomKeys', v) } })
            NavigationSwitchRow({ label: I18n.t('settings_view_gravity_labels'), isOn: this.navigationStore.navigationGravityLabelsEnabled, onToggle: (v: boolean) => { this.setNavigationBoolean('gravityLabels', v) } })
            NavigationSwitchRow({ label: I18n.t('s0302'), isOn: this.viewSettingsStore.autoZoomResets, onToggle: (v: boolean) => { this.setNavigationBoolean('autoZoomResets', v) } })

            KeyboardShortcutSection({
              store: this.keyboardShortcutStore,
              onQuery: (value: string) => { this.keyboardShortcutQueryChange(value) },
              onSelect: (item: KeyboardShortcutItem) => { this.keyboardShortcutSelectChange(item) },
              onPrimary: (value: string) => { this.keyboardShortcutPrimaryChange(value) },
              onAlternate: (value: string) => { this.keyboardShortcutAlternateChange(value) },
              onSave: () => { this.keyboardShortcutSaveChange() },
              onResetSelected: () => { this.keyboardShortcutResetSelectedChange() },
              onResetAll: () => { this.keyboardShortcutResetAllChange() }
            })

            Button(I18n.t('settings_restore_defaults')).fontSize(12).fontColor(this.c.errorText).backgroundColor(this.c.errorBg)
              .border({ width: 1, color: this.c.errorBg })
              .borderRadius(UI_RADIUS_CONTROL).height(38).width('100%')
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.confirmRestoreDefaults() })
              .margin({ top: 4, bottom: 8 })
          } else if (this.configTab === 8) {
            AboutSection({
              tools: this.toolsStore,
              onOpenUrl: (url: string) => { this.openExternalUrl(url) }
            })
          }
              }.width('100%').padding({ bottom: 24 })
          }
        }
          .width('100%')
          .layoutWeight(0)
          .opacity(this.configTabContentOpacity)
          .translate({ x: this.configTabContentOffsetX, y: 0 })
          .id('config-content-' + this.i18nLang)
      }.width('100%').height('auto')
  }
}
