// 启动桥接服务。
//
// 负责冷启动阶段的引擎查询与界面恢复：拉取天文化 / 脚本 / 投影列表，恢复 AppStorage 中的界面设置与
// 观测点，并把当前视角存为启动视角。
//
// 不 import NAPI/UI：桥命令经 CommandPort；Preferences 样式设置读的是 AppStorage（全局，不是 NAPI）；
// 跨域 store 以构造注入的实例引用持有；宿主生命周期/UI 动作（dismissSplash / setLanguage / 两个定时器
// sync / currentProjection / selfTest / bridgeSyncStarted 标志）经 StartupHooks 具名回注。
//
// 隐私授权与启动序列中其余 ArkUI 生命周期回调（onPrivacyNativeStartupAllowedChanged /
// registerFoldListeners / subscribeApplicationLifecycle / confirmPrivacyRevocation / selfTestAllActions 等）
// 涉及 UI 上下文，仍由宿主持有。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { LimitMagnitudeResponse } from '../pages/MainWindowModels'
import { I18n } from '../pages/I18n'
import { AudioEngine } from './AudioEngine'
import { astroGroupForTab, clamp } from '../common/derive/astro'
import { CommandPort } from '../bridge/CommandPort'
import { SkyCultureViewStore } from '../state/SkyCultureViewStore'
import { PluginStore } from '../state/PluginStore'
import { NightModeStore } from '../state/NightModeStore'
import { TelescopeStore } from '../state/TelescopeStore'
import { GyroStore } from '../state/GyroStore'
import { LanguageStore } from '../state/LanguageStore'
import { AudioStore } from '../state/AudioStore'
import { ViewSettingsStore } from '../state/ViewSettingsStore'
import { OverlayStore } from '../state/OverlayStore'
import { AstroStore } from '../state/AstroStore'
import { LayerViewStore } from '../state/LayerViewStore'
import { ScriptStore } from '../state/ScriptStore'
import { LayerStore } from '../state/LayerStore'

// 宿主生命周期 / UI 动作注入（启动桥服务不触碰 UI 与宿主私有标志）。
export interface StartupHooks {
  flashHint(text: ResourceStr): void
  dismissSplash(): void
  setLanguage(language: string): void
  syncViewCoordinateTimer(): void
  syncDockClockTimer(): void
  setCurrentProjection(value: string): void
  bridgeSyncStarted(): boolean
  setBridgeSyncStarted(value: boolean): void
  selftestEnabled(): boolean
  runSelftest(): void
  // 启动恢复上次观测点（宿主侧读 preferences + setLocation；本服务不触碰 NAPI/UI）。
  // 放在启动任务里执行，确保晚于引擎 config 的默认位置（否则会被引擎默认覆盖回北京）。
  restoreObserverLocation(): void
  // 脚本资源元数据表写入（ScriptPlaybackController 持有；启动桥 getScriptList 回包后回注）。
  setScriptMetadata(raw: Object | undefined): void
  // 配置回读加载由 capability/SettingsController 提供；本服务不持有该控制器，经此 hook 触发。
  reloadConfigurationSettings(): void
}

export class StartupBridge {
  private port: CommandPort
  private hooks: StartupHooks
  private skyCultureViewStore: SkyCultureViewStore
  private pluginStore: PluginStore
  private nightModeStore: NightModeStore
  private telescopeStore: TelescopeStore
  private gyroStore: GyroStore
  private languageStore: LanguageStore
  private audioStore: AudioStore
  private viewSettingsStore: ViewSettingsStore
  private overlayStore: OverlayStore
  private astroStore: AstroStore
  private layerViewStore: LayerViewStore
  private scriptStore: ScriptStore
  private layerStore: LayerStore

  constructor(
    port: CommandPort,
    hooks: StartupHooks,
    skyCultureViewStore: SkyCultureViewStore,
    pluginStore: PluginStore,
    nightModeStore: NightModeStore,
    telescopeStore: TelescopeStore,
    gyroStore: GyroStore,
    languageStore: LanguageStore,
    audioStore: AudioStore,
    viewSettingsStore: ViewSettingsStore,
    overlayStore: OverlayStore,
    astroStore: AstroStore,
    layerViewStore: LayerViewStore,
    scriptStore: ScriptStore,
    layerStore: LayerStore,
  ) {
    this.port = port
    this.hooks = hooks
    this.skyCultureViewStore = skyCultureViewStore
    this.pluginStore = pluginStore
    this.nightModeStore = nightModeStore
    this.telescopeStore = telescopeStore
    this.gyroStore = gyroStore
    this.languageStore = languageStore
    this.audioStore = audioStore
    this.viewSettingsStore = viewSettingsStore
    this.overlayStore = overlayStore
    this.astroStore = astroStore
    this.layerViewStore = layerViewStore
    this.scriptStore = scriptStore
    this.layerStore = layerStore
  }

  // 启动期只用一个轻量查询确认 Qt 核心就绪；成功后拉取天文化列表并放行后续启动任务。
  startupBridgeSync(): void {
    if (this.hooks.bridgeSyncStarted()) { return }
    this.hooks.setBridgeSyncStarted(true)
    this.port.requestWhenReady("getSkyCultures", "", (r: StellariumBridgeResponse) => {
      if (r.ok !== true || !Array.isArray(r.items)) { return }
      this.skyCultureViewStore.skyCultures = r.items as string[]
      this.skyCultureViewStore.currentSkyCulture = r.current as string
      this.hooks.dismissSplash()
      this.runStartupBridgeTasks()
    })
  }

  // 分批执行其余启动查询。
  runStartupBridgeTasks(): void {
    const tasks: Array<() => void> = [
      () => this.port.requestWhenReady('setLanguage', this.languageStore.selectedLanguage, () => {}),
      () => this.layerViewStore.loadLandscapeList(),
      () => this.port.requestWhenReady("getScriptList", "", (r: StellariumBridgeResponse) => {
        if (r.ok === true && Array.isArray(r.items)) { this.scriptStore.scriptList = r.items as string[]; this.hooks.setScriptMetadata(r.details) }
      }),
      () => this.port.requestWhenReady('getProjectionList', '', (r: StellariumBridgeResponse) => {
        if (r.ok === true && r.current !== undefined) { this.hooks.setCurrentProjection(r.current as string) }
      }),
      () => this.port.requestWhenReady('getConfigString', 'astronomy/flag_use_km_for_distance', (r: StellariumBridgeResponse) => {
        if (r.ok) { this.viewSettingsStore.useMetricUnits = r.value === 'true' }
      }),
      () => this.port.requestWhenReady('getLimitMagnitude', '', (r: StellariumBridgeResponse) => {
        const response = r as LimitMagnitudeResponse
        if (response.ok && response.customStarMagLimit !== undefined) {
          const value = Number(response.customStarMagLimit)
          if (!isNaN(value)) { this.layerViewStore.starMagLimit = Math.round(value * 10) / 10 }
        }
      }),
      () => this.restoreStartupSettings(),
      // 观测点恢复放在启动任务里：此时 Qt 核心已就绪、引擎 config 默认位置已加载，
      // 再推持久化位置才能稳定覆盖（放 aboutToAppear 会早于引擎 config 而被覆盖）。
      () => this.hooks.restoreObserverLocation(),
      () => this.port.requestWhenReady("setFlatHorizon", "1", (r: StellariumBridgeResponse) => {
        if (r.ok === true) { this.viewSettingsStore.flatHorizon = true }
      }),
      () => this.port.requestWhenReady("setActionChecked", "actionShow_Zenith_Nadir|1", (r: StellariumBridgeResponse) => {
        if (r.ok === true) { this.layerStore.zenithNadir = true }
      }),
      () => { if (this.hooks.selftestEnabled()) { this.hooks.runSelftest() } },
    ]
    let taskIndex = 0
    const runNext = (): void => {
      if (taskIndex >= tasks.length) { return }
      tasks[taskIndex++]()
      setTimeout(runNext, 48)
    }
    runNext()
  }

  // 从 AppStorage 的 stellariumSettings 恢复界面设置。
  restoreStartupSettings(): void {
    this.skyCultureViewStore.loadSkyCultureList()
    this.pluginStore.loadPluginList()
    const settings = AppStorage.get<string>("stellariumSettings")
    if (settings) {
      try {
        const saved = JSON.parse(settings) as Record<string, boolean | string>
        if (saved.nightMode !== undefined) {
          this.nightModeStore.nightMode = saved.nightMode as boolean
          this.port.requestWhenReady('setNightMode', this.nightModeStore.nightMode ? 'true' : 'false', () => {})
        }
        if (saved.equatorialMount !== undefined) {
          this.telescopeStore.equatorialMount = saved.equatorialMount as boolean
          this.port.requestWhenReady('setActionChecked', 'actionSwitch_Equatorial_Mount|' + (this.telescopeStore.equatorialMount ? '1' : '0'), () => {})
        }
        if (saved.gyroscopeEnabled !== undefined) {
          this.gyroStore.gyroscopeEnabled = false
          this.gyroStore.gyroscopeStatus = I18n.t('m_gyro_off')
        }
        if (saved.gyroscopeSensitivityText !== undefined) { this.gyroStore.gyroscopeSensitivityText = saved.gyroscopeSensitivityText as string }
        if (saved.selectedLanguage !== undefined) {
          const language = saved.selectedLanguage as string
          if (language !== this.languageStore.selectedLanguage) {
            I18n.setLanguage(I18n.fromStellariumCode(language))
            this.hooks.setLanguage(language)
          }
        }
        if (saved.musicEnabled !== undefined) { this.audioStore.musicEnabled = saved.musicEnabled as boolean }
        if (saved.useMetricUnits !== undefined) { this.viewSettingsStore.useMetricUnits = saved.useMetricUnits as boolean }
        if (saved.viewCoordinatesVisible !== undefined) { this.overlayStore.viewCoordinatesVisible = saved.viewCoordinatesVisible as boolean }
        if (saved.viewCoordinateFamily !== undefined) { this.overlayStore.viewCoordinateFamily = saved.viewCoordinateFamily as string }
        if (saved.viewEquatorialEpoch !== undefined) { this.overlayStore.viewEquatorialEpoch = saved.viewEquatorialEpoch as string }
        if (saved.objectDetailConnectorVisible !== undefined) { this.overlayStore.objectDetailConnectorVisible = saved.objectDetailConnectorVisible as boolean }
        const savedAstroTab = Number(saved.astroTab)
        if (Number.isInteger(savedAstroTab) && savedAstroTab >= 0 && savedAstroTab <= 9) {
          this.astroStore.astroTab = savedAstroTab
          this.astroStore.astroGroup = astroGroupForTab(savedAstroTab)
        }
        const savedPositionMode = Number(saved.positionMode)
        if (Number.isInteger(savedPositionMode) && savedPositionMode >= 0 && savedPositionMode <= 2) this.astroStore.positionMode = savedPositionMode
        const savedCelestialMagnitude = Number(saved.celestialPositionMagnitude)
        if (Number.isFinite(savedCelestialMagnitude)) this.astroStore.celestialPositionMagnitude = clamp(savedCelestialMagnitude, -5, 25)
        if (saved.celestialPositionCategory !== undefined) this.astroStore.celestialPositionCategory = saved.celestialPositionCategory as string
        if (saved.celestialPositionHorizontal !== undefined) this.astroStore.celestialPositionHorizontal = saved.celestialPositionHorizontal === 'true'
        const savedEphemerisMode = Number(saved.ephemerisMode)
        if (Number.isInteger(savedEphemerisMode) && savedEphemerisMode >= 0 && savedEphemerisMode <= 2) this.astroStore.ephemerisMode = savedEphemerisMode
        const savedEphemerisDays = Number(saved.ephemerisDays)
        if (Number.isInteger(savedEphemerisDays) && savedEphemerisDays >= 1 && savedEphemerisDays <= 31) this.astroStore.ephemerisDays = savedEphemerisDays
        const savedEphemerisStep = Number(saved.ephemerisStepHours)
        if (Number.isInteger(savedEphemerisStep) && savedEphemerisStep >= 1 && savedEphemerisStep <= 24) this.astroStore.ephemerisStepHours = savedEphemerisStep
        const savedRtsDays = Number(saved.rtsCalendarDays)
        if (Number.isInteger(savedRtsDays) && savedRtsDays >= 1 && savedRtsDays <= 365) this.astroStore.rtsCalendarDays = savedRtsDays
        const savedGraphMode = Number(saved.graphMode)
        if (Number.isInteger(savedGraphMode) && savedGraphMode >= 0 && savedGraphMode <= 5) this.astroStore.graphMode = savedGraphMode
        const savedEclipseMonths = Number(saved.eclipseMonths)
        if (Number.isInteger(savedEclipseMonths) && savedEclipseMonths >= 1 && savedEclipseMonths <= 60) this.astroStore.eclipseMonths = savedEclipseMonths
        const savedMoonPhaseDays = Number(saved.moonPhaseDays)
        if (savedMoonPhaseDays === 30 || savedMoonPhaseDays === 90) this.astroStore.moonPhaseDays = savedMoonPhaseDays
      } catch (_err) { }
    }
    if (this.audioStore.musicEnabled) { AudioEngine.getInstance().start() }
    I18n.setLanguage(I18n.fromStellariumCode(this.languageStore.selectedLanguage))
    this.hooks.syncViewCoordinateTimer()
    this.hooks.syncDockClockTimer()
  }

  // 把当前视角存为启动视角。
  saveCurrentViewAsStartup(): void {
    this.port.requestInteractive('saveCurrentView', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.hooks.flashHint(I18n.t('msg_apply_failed'))
        return
      }
      this.hooks.flashHint(I18n.t('settings_view_saved'))
      this.hooks.reloadConfigurationSettings()
    })
  }
}
