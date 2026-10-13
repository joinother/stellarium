// 图层 / 视图标签行为控制器：负责图层开关写回与预设、视图/设置标签切换动画、
// 星空显示与图层设置写回、地景包导入与详情、三维地景场景切换、视图锁定。
// 依赖 CommandPort、MediaPort（地景导入）、LayerViewStore / LayerStore / SceneryStore /
// ObjectDetailStore / ViewSettingsStore / ScriptStore / PluginStore。
// 图层开关布尔值由宿主 refreshState 从引擎回填，控制器不写；viewTab / configTab 与两组过渡量
// 是宿主 @State（组件 @Prop 消费），经 hooks get/set；标签切换动画归宿主经 animateTabIn/Out 回注。
import hilog from '@ohos.hilog'
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse, TabItem } from '../pages/StellariumTypes'
import { LayerPresetState, MARKING_LAYER_ACTION_IDS, CONTENT_LAYER_ACTION_IDS, OFFLINE_APPGALLERY_BUILD } from '../pages/MainWindowModels'
import { CommandPort } from '../bridge/CommandPort'
import { DocumentImportPort, MediaImportResult } from '../bridge/MediaPort'
import { LayerViewStore } from '../state/LayerViewStore'
import { LayerStore } from '../state/LayerStore'
import { SceneryStore } from '../state/SceneryStore'
import { ObjectDetailStore } from '../state/ObjectDetailStore'
import { ViewSettingsStore } from '../state/ViewSettingsStore'
import { ScriptStore } from '../state/ScriptStore'
import { PluginStore } from '../state/PluginStore'
import { BehaviorHostHooks } from './ControllerHooks'

// 「全部网格与标记」总闸的 action id（= 引擎 GridLinesMgr::gridlinesDisplayed）。见 applyLayerSwitch 的联动。
const GRIDLINES_MASTER_ACTION = 'actionShow_Gridlines'

// 宿主 → 控制器回注：图层开关分派、持久化、标签切换动画与宿主 @State 读写。
export interface LayerHostHooks extends BehaviorHostHooks {
  // 视图锁定回读的跟踪状态文案（宿主 @State trackingText，组件 @Prop 消费）。
  setTrackingText(value: string): void
  // 地景详情浮层宿主 @State（selectLandscape 关闭浮层；组件 @Prop 消费）。
  setLandscapeDetailOpen(value: boolean): void
  // 持久化（跨 store / AppStorage：赤道仪开关归 TelescopeStore；夜视归 NightModeStore）。
  persistEquatorialMount(): void
  persistNightMode(): void
  // 星空文化「时间跟随」定时器收口（宿主保留）。
  syncSkyCultureTimeFollowTimer(): void
  // 脚本列表 / 录制列表 / 视频状态桥加载（ScriptPlaybackController 持有）。
  loadScriptList(): void
  loadRecordings(): void
  loadVideoRecordingState(): void
  // 通知/后台提醒状态回读（NotificationController 持有）；进入「设备与隐私」页时刷新。
  refreshNotificationStatus(): void
  // 巡天 / 多波段图层状态回读（SurveyController 持有）；进入「巡天」页时刷新。
  loadSurveyState(): void
  // 键盘快捷键列表回读（KeyboardShortcutController 持有）；进入「视图导航」页时刷新。
  loadKeyboardShortcuts(): void
  // 视图标签页宿主 @State（组件 @Prop 消费，控制器经 hooks 读写）。
  viewTab(): number
  setViewTab(value: number): void
  viewTabContentOpacity(): number
  setViewTabContentOpacity(value: number): void
  viewTabContentOffsetX(): number
  setViewTabContentOffsetX(value: number): void
  // 设置标签页宿主 @State。
  configTab(): number
  setConfigTab(value: number): void
  configTabContentOpacity(): number
  setConfigTabContentOpacity(value: number): void
  configTabContentOffsetX(): number
  setConfigTabContentOffsetX(value: number): void
  // 标签切换动画（宿主 getUIContext().animateTo 归宿主；curve 由宿主按原调用点固定）。
  animateTabIn(durationMs: number, onFinish: () => void, action: () => void): void
  animateTabOut(durationMs: number, action: () => void): void
}

export class LayerController {
  private port: CommandPort
  private mediaPort: DocumentImportPort
  private layerViewStore: LayerViewStore
  private layerStore: LayerStore
  private sceneryStore: SceneryStore
  private objectDetailStore: ObjectDetailStore
  private viewSettingsStore: ViewSettingsStore
  private scriptStore: ScriptStore
  private pluginStore: PluginStore
  private hooks: LayerHostHooks
  // 标签切换去重序号：草稿字段随控制器走，不入 @Observed store。
  private viewTabTransitionId: number = 0
  private configTabTransitionId: number = 0

  constructor(
    port: CommandPort,
    mediaPort: DocumentImportPort,
    layerViewStore: LayerViewStore,
    layerStore: LayerStore,
    sceneryStore: SceneryStore,
    objectDetailStore: ObjectDetailStore,
    viewSettingsStore: ViewSettingsStore,
    scriptStore: ScriptStore,
    pluginStore: PluginStore,
    hooks: LayerHostHooks
  ) {
    this.port = port
    this.mediaPort = mediaPort
    this.layerViewStore = layerViewStore
    this.layerStore = layerStore
    this.sceneryStore = sceneryStore
    this.objectDetailStore = objectDetailStore
    this.viewSettingsStore = viewSettingsStore
    this.scriptStore = scriptStore
    this.pluginStore = pluginStore
    this.hooks = hooks
  }

  // 桥写单个 action 勾选态，回包后刷新状态；夜视 / 赤道仪开关立即持久化。
  private setLayer(actionId: string, enabled: boolean): void {
    hilog.info(0x0000, 'StellariumArkUI', 'setLayer send %{public}s|%{public}s', actionId, enabled ? '1' : '0')
    this.port.requestInteractive('setActionChecked', actionId + '|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'setLayer %{public}s ok=%{public}s err=%{public}s', actionId, r.ok === true ? '1' : '0', r.error ?? '')
      this.hooks.refreshState()
      // 夜间模式和赤道仪模式切换时立即持久化，避免应用被杀死后丢失
      if (actionId === 'actionShow_Night_Mode') { this.hooks.persistNightMode() }
      if (actionId === 'actionSwitch_Equatorial_Mount') { this.hooks.persistEquatorialMount() }
    })
  }

  // 图层开关的统一写回。
  applyLayerSwitch(actionId: string, cmd: string, value: boolean): void {
    if (cmd.length === 0 && value && actionId !== GRIDLINES_MASTER_ACTION &&
      MARKING_LAYER_ACTION_IDS.indexOf(actionId) >= 0) {
      // 网格/标记单项重新打开时先联动打开总闸：总闸是 GridLinesMgr 的 `gridlinesDisplayed`，
      // 引擎 draw() 里 `if (!gridlinesDisplayed) return;` 会拦掉整组，单项看着完全没反应。
      this.setLayer(GRIDLINES_MASTER_ACTION, true)
    }
    if (cmd.length > 0) {
      if (cmd.indexOf('setSkyDisplay') === 0) {
        this.setSkyDisplaySetting(actionId, value)
      } else {
        this.setBridgeFlag(cmd, value)
      }
    } else {
      this.setLayer(actionId, value)
    }
    this.hooks.flashHint(I18n.t(value ? 'msg_shown' : 'msg_hidden'))
  }

  // 视图标签页清单（离线 AppGallery 构建隐藏第 7 页）。
  layerTabItems(): TabItem[] {
    const tabs: TabItem[] = [
      { label: I18n.t('v0000'), id: 0 },
      { label: I18n.t('v0001'), id: 1 },
      { label: I18n.t('v0002'), id: 2 },
      { label: I18n.t('v0003'), id: 3 },
      { label: I18n.t('v0004'), id: 4 },
      { label: I18n.t('v0005'), id: 5 }
    ]
    if (!OFFLINE_APPGALLERY_BUILD) {
      tabs.push({ label: I18n.t('v0006'), id: 6 })
    }
    return tabs
  }

  private markingLayerStates(enabled: boolean): Array<LayerPresetState> {
    const states: Array<LayerPresetState> = []
    for (const actionId of MARKING_LAYER_ACTION_IDS) {
      states.push({ id: actionId, enabled: enabled })
    }
    return states
  }

  private layerPresetStates(enabled: boolean): Array<LayerPresetState> {
    const states = this.markingLayerStates(enabled)
    for (const actionId of CONTENT_LAYER_ACTION_IDS) {
      states.push({ id: actionId, enabled: enabled })
    }
    return states
  }

  private applyLayerStates(states: Array<LayerPresetState>, successMessage: string): void {
    this.port.requestInteractive('setActionStates', JSON.stringify(states), (response: StellariumBridgeResponse) => {
      if (response.ok === true) {
        this.hooks.refreshState()
        this.hooks.flashHint(successMessage)
      } else {
        this.hooks.flashHint('图层设置未能应用，请重试。')
      }
    })
  }

  // 清空全部坐标与标记图层。
  clearMarkingLayers(): void {
    this.applyLayerStates(this.markingLayerStates(false), '已清除全部坐标与标记。')
  }

  // 三种预设（纯净 / 观测 / 摄影）的图层组合。
  applyLayerPreset(preset: string): void {
    let states: Array<LayerPresetState> = this.layerPresetStates(false)
    if (preset === 'clean') {
      states.push(
        { id: 'actionShow_Stars', enabled: true }, { id: 'actionShow_Stars_Labels', enabled: false },
        { id: 'actionShow_Planets', enabled: true }, { id: 'actionShow_Planets_Labels', enabled: false },
        { id: 'actionShow_Planets_Hints', enabled: false },
        { id: 'actionShow_Nebulas', enabled: true }, { id: 'actionShow_MilkyWay', enabled: true },
        { id: 'actionShow_Constellation_Lines', enabled: false }, { id: 'actionShow_Constellation_Labels', enabled: false },
        { id: 'actionShow_Constellation_Boundaries', enabled: false }, { id: 'actionShow_Constellation_Art', enabled: false },
        { id: 'actionShow_Atmosphere', enabled: true }, { id: 'actionShow_Ground', enabled: true }
      )
    } else if (preset === 'observe') {
      states.push(
        { id: 'actionShow_Stars', enabled: true }, { id: 'actionShow_Stars_Labels', enabled: true },
        { id: 'actionShow_Planets', enabled: true }, { id: 'actionShow_Planets_Labels', enabled: true },
        { id: 'actionShow_Planets_Hints', enabled: true }, { id: 'actionShow_Planets_Orbits', enabled: true },
        { id: 'actionShow_Nebulas', enabled: true }, { id: 'actionShow_DSO_Textures', enabled: true },
        { id: 'actionShow_MilkyWay', enabled: true }, { id: 'actionShow_Constellation_Lines', enabled: true },
        { id: 'actionShow_Constellation_Labels', enabled: true }, { id: 'actionShow_Constellation_Boundaries', enabled: false },
        { id: 'actionShow_Constellation_Art', enabled: false }, { id: 'actionShow_Atmosphere', enabled: false },
        { id: 'actionShow_Ground', enabled: false }, { id: 'actionShow_Fog', enabled: false },
        // actionShow_Gridlines 对应 GridLinesMgr::gridlinesDisplayed，是网格与线的**总闸**
        // （引擎 draw() 里 `if (!gridlinesDisplayed)` 直接返回，单个网格开关全部失效）。
        // 预设基础表把它置 false，所以这里必须先打开总闸，下面几个网格/线开关才有效。
        { id: 'actionShow_Cardinal_Points', enabled: true }, { id: 'actionShow_Gridlines', enabled: true },
        { id: 'actionShow_Equatorial_Grid', enabled: true },
        { id: 'actionShow_Ecliptic_Line', enabled: true }, { id: 'actionShow_Meridian_Line', enabled: true },
        { id: 'actionShow_Horizon_Line', enabled: true }, { id: 'actionShow_FOV_Center_Marker', enabled: true }
      )
    } else {
      states.push(
        { id: 'actionShow_Stars', enabled: true }, { id: 'actionShow_Stars_Labels', enabled: false },
        { id: 'actionShow_Planets', enabled: false }, { id: 'actionShow_Planets_Labels', enabled: false },
        { id: 'actionShow_Planets_Hints', enabled: false },
        { id: 'actionShow_Nebulas', enabled: true }, { id: 'actionShow_MilkyWay', enabled: true },
        { id: 'actionShow_Constellation_Lines', enabled: false }, { id: 'actionShow_Constellation_Labels', enabled: false },
        { id: 'actionShow_Constellation_Boundaries', enabled: false }, { id: 'actionShow_Constellation_Art', enabled: false },
        { id: 'actionShow_Atmosphere', enabled: false }, { id: 'actionShow_Ground', enabled: false }
      )
    }
    this.applyLayerStates(states, preset === 'clean' ? '已应用纯净星空图层。' : (preset === 'observe' ? '已应用观测辅助图层。' : '已应用摄影构图图层。'))
  }

  // 视图标签切换（两段 animateTo 时序保留；动画本体归宿主）。
  selectViewTab(tabId: number): void {
    if (tabId === this.hooks.viewTab()) return
    const direction = tabId > this.hooks.viewTab() ? 1 : -1
    const transitionId = ++this.viewTabTransitionId
    hilog.info(0x0000, 'StellariumArkUI', '[layer-transition] begin id=%{public}d from=%{public}d to=%{public}d', transitionId, this.hooks.viewTab(), tabId)
    this.hooks.animateTabIn(100, (): void => {
      if (transitionId !== this.viewTabTransitionId) return
      this.hooks.setViewTab(tabId)
      if (tabId === 4) this.layerViewStore.loadLandscapeList()
      if (tabId === 6) this.hooks.loadSurveyState()
      this.hooks.setViewTabContentOffsetX(direction * 10)
      hilog.info(0x0000, 'StellariumArkUI', '[layer-transition] swap id=%{public}d tab=%{public}d', transitionId, tabId)
      this.hooks.animateTabOut(170, (): void => {
        if (transitionId !== this.viewTabTransitionId) return
        this.hooks.setViewTabContentOpacity(1)
        this.hooks.setViewTabContentOffsetX(0)
        this.hooks.syncSkyCultureTimeFollowTimer()
        hilog.info(0x0000, 'StellariumArkUI', '[layer-transition] finish id=%{public}d tab=%{public}d', transitionId, tabId)
      })
    }, (): void => {
      this.hooks.setViewTabContentOpacity(0)
      this.hooks.setViewTabContentOffsetX((0 - direction) * 8)
    })
  }

  // 设置标签切换（同上；第 6/7 页触发脚本 / 插件数据加载）。
  selectConfigTab(tabId: number): void {
    if (tabId === this.hooks.configTab()) return
    const direction = tabId > this.hooks.configTab() ? 1 : -1
    const transitionId = ++this.configTabTransitionId
    hilog.info(0x0000, 'StellariumArkUI', '[settings-transition] begin id=%{public}d from=%{public}d to=%{public}d', transitionId, this.hooks.configTab(), tabId)
    this.hooks.animateTabIn(90, (): void => {
      if (transitionId !== this.configTabTransitionId) return
      this.hooks.setConfigTab(tabId)
      this.hooks.setConfigTabContentOffsetX(direction * 8)
      if (tabId === 5) {
        this.hooks.loadScriptList()
        this.hooks.loadRecordings()
        this.hooks.loadVideoRecordingState()
      } else if (tabId === 6) {
        this.pluginStore.loadPluginList()
      } else if (tabId === -1) {
        this.hooks.refreshNotificationStatus()
      } else if (tabId === 7) {
        this.hooks.loadKeyboardShortcuts()
      }
      hilog.info(0x0000, 'StellariumArkUI', '[settings-transition] swap id=%{public}d tab=%{public}d', transitionId, tabId)
      this.hooks.animateTabOut(170, (): void => {
        if (transitionId !== this.configTabTransitionId) return
        this.hooks.setConfigTabContentOpacity(1)
        this.hooks.setConfigTabContentOffsetX(0)
        hilog.info(0x0000, 'StellariumArkUI', '[settings-transition] finish id=%{public}d tab=%{public}d', transitionId, tabId)
      })
    }, (): void => {
      if (transitionId !== this.configTabTransitionId) return
      this.hooks.setConfigTabContentOpacity(0)
      this.hooks.setConfigTabContentOffsetX((0 - direction) * 8)
    })
  }

  // ===== 显示 / 图层设置行为 =====

  // 星空显示设置写回（布尔项写 LayerStore，数值项写 LayerViewStore）。
  setSkyDisplaySetting(setting: string, value: boolean | number): void {
    if (setting === 'luminanceAdaptation') this.layerStore.luminanceAdaptation = value as boolean
    else if (setting === 'starTwinkle') this.layerStore.starTwinkle = value as boolean
    else if (setting === 'forcedStarTwinkle') this.layerStore.forcedStarTwinkle = value as boolean
    else if (setting === 'bigStarHalo') this.layerStore.bigStarHalo = value as boolean
    else if (setting === 'starSpiky') this.layerStore.starSpiky = value as boolean
    else if (setting === 'bortleScale') this.layerViewStore.bortleScale = Math.round(value as number)
    else if (setting === 'meteorZhr') this.layerViewStore.meteorZhr = Math.round(value as number)
    else if (setting === 'zodiacalLight') this.layerStore.zodiacalLight = value as boolean
    else if (setting === 'zodiacalIntensity') this.layerViewStore.zodiacalIntensity = value as number
    const payload = setting + '|' + (typeof value === 'boolean' ? (value ? '1' : '0') : value.toString())
    this.port.requestInteractive('setSkyDisplaySetting', payload, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        if (typeof value === 'boolean' || setting === 'bortleScale') this.hooks.refreshState()
      } else {
        this.hooks.flashHint(r.error ?? I18n.t('msg_apply_failed'))
        this.hooks.refreshState()
      }
    })
  }

  // 命名桥命令的通用写回（本地 @State 同步 + viewLock 分支）。
  setBridgeFlag(cmd: string, enabled: boolean): void {
    hilog.info(0x0000, 'StellariumArkUI', 'setBridgeFlag send %{public}s|%{public}s', cmd, enabled ? '1' : '0')
    if (cmd === 'setViewLock') {
      this.setViewLockState(enabled)
      return
    }
    // 同步本地 @State：否则面板关闭重开后 Toggle 会显示旧值，再点一次就把状态发反了
    this.syncBridgeFlagState(cmd, enabled)
    this.port.requestInteractive(cmd, enabled ? '1' : '0', (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'setBridgeFlag %{public}s ok=%{public}s err=%{public}s', cmd, r.ok === true ? '1' : '0', r.error ?? '')
      this.hooks.refreshState()
    })
  }

  // 把 cmd 型开关的最新值写回对应的本地 store。
  private syncBridgeFlagState(cmd: string, enabled: boolean): void {
    if (cmd === 'setViewLock') { this.viewSettingsStore.viewLock = enabled }
    else if (cmd === 'setVerticalClamp') { this.viewSettingsStore.verticalClamp = enabled }
    else if (cmd === 'setFlatHorizon') { this.viewSettingsStore.flatHorizon = enabled }
    else if (cmd === 'setMeteors') { this.layerStore.meteors = enabled }
    else if (cmd === 'setDsoLabels') { this.layerStore.dsoLabels = enabled }
    else if (cmd === 'setAutoZoomResets') { this.viewSettingsStore.autoZoomResets = enabled }
  }

  // 视图锁定（选中判定 + 桥写 + 成功回读 trackingText）。
  setViewLockState(enabled: boolean): void {
    if (enabled && !this.objectDetailStore.hasSelectedObject()) {
      this.viewSettingsStore.viewLock = false
      this.hooks.flashHint(I18n.t('view_lock_requires_selection'))
      return
    }
    const previous = this.viewSettingsStore.viewLock
    this.viewSettingsStore.viewLock = enabled
    this.port.requestInteractive('setViewLock', enabled ? '1' : '0', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.viewSettingsStore.viewLock = previous
        this.hooks.flashHint(r.selectionRequired === true ? I18n.t('view_lock_requires_selection') : I18n.t('msg_apply_failed'))
        return
      }
      if (r.viewLock !== undefined) this.viewSettingsStore.viewLock = r.viewLock === true
      if (r.tracking !== undefined) this.hooks.setTrackingText(r.tracking === true ? 'On' : 'Off')
      this.hooks.flashHint(this.viewSettingsStore.viewLock ? I18n.t('view_lock_enabled') : I18n.t('view_lock_disabled'))
    }, () => {
      this.viewSettingsStore.viewLock = previous
      this.hooks.flashHint(I18n.t('msg_apply_failed'))
    })
  }

  toggleViewLock(): void {
    this.setViewLockState(!this.viewSettingsStore.viewLock)
  }

  // 极限星等写 store 并写桥。
  applyStarMagLimit(value: number): void {
    this.layerViewStore.starMagLimit = value
    this.port.requestInteractive('setLimitMagnitude', value.toFixed(1), () => {})
  }

  // 银河亮度写 store 并写桥。
  applyMilkyWayBright(value: number): void {
    this.layerViewStore.milkyWayBright = value
    this.port.requestInteractive('setMilkyWayIntensity', (value / 3).toFixed(2), () => {})
  }

  // 轨道显示开关写回（回包成功后写 LayerViewStore）。
  setOrbitDisplayFlag(setting: string, enabled: boolean): void {
    this.port.requestInteractive('setOrbitDisplaySetting', setting + '|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      if (r.ok !== true) return
      if (setting === 'isolated') this.layerViewStore.orbitIsolated = enabled
      else if (setting === 'majorPlanets') this.layerViewStore.orbitMajorPlanets = enabled
      else if (setting === 'planetsOnly') this.layerViewStore.orbitPlanetsOnly = enabled
      else if (setting === 'withMoons') this.layerViewStore.orbitWithMoons = enabled
      else if (setting === 'permanent') this.layerViewStore.orbitPermanent = enabled
    })
  }

  // 轨道线宽写回。
  setOrbitDisplayThickness(value: number): void {
    const thickness = Math.round(value)
    this.port.requestInteractive('setOrbitDisplaySetting', 'thickness|' + thickness.toString(), (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.layerViewStore.orbitThickness = thickness
    })
  }

  // 轨道配色方案写回。
  setOrbitColorStyle(index: number): void {
    const values: string[] = ['one_color', 'groups', 'major_planets', 'major_planets_minor_types']
    const style = values[index] ?? 'one_color'
    this.port.requestInteractive('setOrbitDisplaySetting', 'colorStyle|' + style, (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.layerViewStore.orbitColorStyle = style
    })
  }

  // 轨迹显示开关写回。
  setTrailDisplayFlag(setting: string, enabled: boolean): void {
    this.port.requestInteractive('setTrailDisplaySetting', setting + '|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      if (r.ok === true && setting === 'isolated') this.layerViewStore.trailIsolated = enabled
    })
  }

  // 轨迹数量 / 年数 / 线宽写回。
  setTrailDisplayNumber(setting: string, value: number): void {
    const number = Math.round(value)
    this.port.requestInteractive('setTrailDisplaySetting', setting + '|' + number.toString(), (r: StellariumBridgeResponse) => {
      if (r.ok !== true) return
      if (setting === 'selectionCount') this.layerViewStore.trailSelectionCount = number
      else if (setting === 'years') this.layerViewStore.trailYears = number
      else if (setting === 'thickness') this.layerViewStore.trailThickness = number
    })
  }

  // 校验 #RRGGBB 后写桥并回写 store。
  applyTrailColor(): void {
    const normalized = this.layerViewStore.trailColorInput.trim().toUpperCase()
    if (!/^#[0-9A-F]{6}$/.test(normalized)) {
      this.hooks.flashHint('请输入 #RRGGBB 格式的颜色')
      return
    }
    this.port.requestInteractive('setTrailDisplaySetting', 'color|' + normalized, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) return
      this.layerViewStore.trailColor = r.trailColor !== undefined ? r.trailColor : normalized
      this.layerViewStore.trailColorInput = this.layerViewStore.trailColor
    })
  }

  // 应用地景包（成功写当前地景 / 关闭详情浮层 / 刷新状态）。
  selectLandscape(id: string, name: string): void {
    this.port.requestInteractive('setLandscape', id, (response: StellariumBridgeResponse) => {
      if (response.ok !== true) {
        this.hooks.flashHint(I18n.t('msg_apply_failed'))
        return
      }
      this.layerViewStore.currentLandscapeId = id
      this.objectDetailStore.selectedLandscapeName = name
      this.hooks.setLandscapeDetailOpen(false)
      this.hooks.refreshState()
    })
  }

  // 随缩放淡出地景开关写回。
  setLandscapeFadeWithZoom(isOn: boolean): void {
    this.layerViewStore.landscapeFadeWithZoom = isOn
    this.port.requestInteractive('setLandscapeFadeWithZoom', isOn ? '1' : '0', () => {})
  }

  // 手动透明度接管地景显示。
  changeLandscapeTransparency(val: number): void {
    const v = (val / 100).toFixed(2)
    // 手动透明度接管地景显示；不要再调用 setLandscapeFadeWithZoom(0)，
    // C++ 里该命令会重置透明度，导致滑条看起来“没反应”。
    this.layerViewStore.landscapeFadeWithZoom = false
    this.port.requestInteractive('setLandscapeUseTransparency', '1', () => {})
    this.port.requestInteractive('setLandscapeTransparency', v, () => {})
  }

  // picker 选 ZIP → 复制到应用导入目录 → 桥导入（picker/fileIo 经 MediaPort）。
  async importLandscapeFile(): Promise<void> {
    if (this.layerViewStore.landscapeImporting) return
    this.layerViewStore.landscapeImporting = true
    try {
      const result: MediaImportResult = await this.mediaPort.importLandscapeDocument()
      if (result.cancelled) {
        this.hooks.flashHint(I18n.t('landscape_import_cancelled'))
        this.layerViewStore.landscapeImporting = false
        return
      }
      const fileName = result.path.substring(result.path.lastIndexOf('/') + 1)
      this.port.requestInteractive('importLandscape', result.path, (r: StellariumBridgeResponse) => {
        if (r.ok === true) {
          this.hooks.flashHint(I18n.format('landscape_import_success', [String(r.id ?? fileName)]))
          this.layerViewStore.loadLandscapeList()
        } else {
          this.hooks.flashHint(I18n.t('landscape_import_failed'))
        }
        this.layerViewStore.landscapeImporting = false
      }, () => {
        this.hooks.flashHint(I18n.t('landscape_import_failed'))
        this.layerViewStore.landscapeImporting = false
      })
    } catch (error) {
      hilog.error(0x0000, 'StellariumArkUI', 'Landscape import failed: %{public}s', String(error))
      this.hooks.flashHint(I18n.t('landscape_import_failed'))
      this.layerViewStore.landscapeImporting = false
    }
  }

  // 三维地景场景切换。
  setScenery3dScene(id: string): void {
    this.sceneryStore.scenery3dLoadingId = id
    this.port.requestInteractive('setScenery3dScene', id, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.sceneryStore.scenery3dLoadingId = ''
        this.hooks.flashHint('三维地景加载失败')
        return
      }
      this.sceneryStore.loadScenery3d()
    }, () => { this.sceneryStore.scenery3dLoadingId = '' })
  }

  // 三维地景总开关（失败回滚 store 布尔）。
  setScenery3dEnabled(enabled: boolean): void {
    this.sceneryStore.scenery3dEnabled = enabled
    this.port.requestInteractive('setScenery3dEnabled', enabled ? '1' : '0', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) this.sceneryStore.scenery3dEnabled = !enabled
      this.sceneryStore.loadScenery3d()
    }, () => { this.sceneryStore.scenery3dEnabled = !enabled })
  }
}
