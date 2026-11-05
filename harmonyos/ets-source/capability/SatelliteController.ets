// 卫星（Satellites）行为控制器：负责分组切换、更新设置、来源增删、TLE 导入、
// 目录刷新、显示开关与卫星取景。
//
// `requestSatellitePasses` 归选中/详情管线，不在本类。
// 不 import NAPI/UI：桥经 CommandPort；状态整体写 SatelliteStore
//（SatellitesPanel 经 @ObjectLink 消费）；`publishSatellitePanelState`（写 AppStorage）与
// `selectSatelliteGroup` 的 180ms 分组过渡动画经 SatelliteHostHooks 回注。
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { SatelliteSourceInput } from '../pages/MainWindowModels'
import { CommandPort } from '../bridge/CommandPort'
import { SatelliteStore } from '../state/SatelliteStore'

export interface SatelliteHostHooks {
  // CLI 发布点（宿主 publishSatellitePanelState，写 AppStorage）。
  publishSatellitePanelState(error: string): void
  // 分组切换的 180ms EaseOut 过渡（宿主 getUIContext().animateTo，控制器不 import UI）。
  animateSatelliteGroupChange(action: () => void): void
}

export class SatelliteController {
  private port: CommandPort
  private satelliteStore: SatelliteStore
  private hooks: SatelliteHostHooks

  constructor(port: CommandPort, satelliteStore: SatelliteStore, hooks: SatelliteHostHooks) {
    this.port = port
    this.satelliteStore = satelliteStore
    this.hooks = hooks
  }

  // —— 卫星倒计时（TIMER 语义：用户设置时长后由端侧每秒递减）——
  private countdownTimer: number = -1

  setCountdownTarget(target: string): void {
    this.satelliteStore.countdownTarget = target
    this.satelliteStore.countdownRunning = false
    this.stopCountdownTimer()
  }

  // 用户用 −/＋ 调整时长（分钟级，最少 1 分钟）
  adjustCountdown(deltaSeconds: number): void {
    const next = Math.max(60, Math.min(3600, this.satelliteStore.countdownTotalSeconds + deltaSeconds))
    this.satelliteStore.countdownTotalSeconds = next
    if (!this.satelliteStore.countdownRunning) {
      this.satelliteStore.countdownRemainingSeconds = next
    }
  }

  startCountdown(): void {
    this.satelliteStore.countdownRemainingSeconds = this.satelliteStore.countdownTotalSeconds
    this.satelliteStore.countdownRunning = true
    this.stopCountdownTimer()
    this.countdownTimer = setInterval(() => {
      if (!this.satelliteStore.countdownRunning) {
        this.stopCountdownTimer()
        return
      }
      const left = this.satelliteStore.countdownRemainingSeconds - 1
      this.satelliteStore.countdownRemainingSeconds = left > 0 ? left : 0
      if (left <= 0) {
        this.satelliteStore.countdownRunning = false
        this.stopCountdownTimer()
      }
    }, 1000)
  }

  stopCountdown(): void {
    this.satelliteStore.countdownRunning = false
    this.satelliteStore.countdownRemainingSeconds = this.satelliteStore.countdownTotalSeconds
    this.stopCountdownTimer()
  }

  private stopCountdownTimer(): void {
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer)
      this.countdownTimer = -1
    }
  }

  // 把「还有多久」格式化成 mm:ss / h:mm:ss。
  countdownLabel(): string {
    const total = this.satelliteStore.countdownRemainingSeconds
    const h = Math.floor(total / 3600)
    const m = Math.floor((total % 3600) / 60)
    const sec = total % 60
    const mm = String(m).padStart(2, '0')
    const ss = String(sec).padStart(2, '0')
    return h > 0 ? h.toString() + ':' + mm + ':' + ss : mm + ':' + ss
  }

  // 校验分组 → 过渡动画切换 → 重载。
  selectSatelliteGroup(group: string): void {
    if (group.length > 0 && !this.satelliteStore.satGroups.includes(group)) {
      this.hooks.publishSatellitePanelState('unknown satellite group')
      return
    }
    if (this.satelliteStore.activeSatGroup === group) {
      this.hooks.publishSatellitePanelState('')
      return
    }
    this.hooks.animateSatelliteGroupChange(() => {
      this.satelliteStore.activeSatGroup = group
    })
    this.satelliteStore.loadSatellites()
  }

  // 单个更新设置写回 → 重载来源。
  setSatelliteUpdateSetting(key: string, value: boolean | number): void {
    const payload: Record<string, boolean | number> = {}
    payload[key] = value
    this.port.requestInteractive('setSatelliteUpdateSetting', JSON.stringify(payload), () => {
      this.satelliteStore.loadSatelliteSources()
    }, (failure: StellariumBridgeResponse) => { this.satelliteStore.satSourceStatus = failure.error ?? I18n.t('sat_source_invalid') })
  }

  // 把输入框 URL 追加为来源写回；编辑态下替换对应来源而非追加。
  addSatelliteSource(): void {
    const url = this.satelliteStore.satSourceInput.trim()
    if (url.length === 0) { this.satelliteStore.satSourceStatus = I18n.t('sat_source_empty'); return }
    const sources: SatelliteSourceInput[] = []
    for (let sourceIndex = 0; sourceIndex < this.satelliteStore.satSources.length; sourceIndex++) {
      const source = this.satelliteStore.satSources[sourceIndex]
      sources.push({
        url: sourceIndex === this.satelliteStore.editingSatelliteSourceIndex ? url : source.url,
        addNew: source.addNew
      })
    }
    if (this.satelliteStore.editingSatelliteSourceIndex < 0) sources.push({ url: url, addNew: this.satelliteStore.satSourceAddNew })
    this.port.requestInteractive('setSatelliteSources', JSON.stringify({ sources: sources }), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.satelliteStore.satSourceInput = ''
        this.satelliteStore.editingSatelliteSourceIndex = -1
        this.satelliteStore.satSourceStatus = I18n.t('sat_source_saved')
        this.satelliteStore.loadSatelliteSources()
      } else this.satelliteStore.satSourceStatus = r.error ?? I18n.t('sat_source_invalid')
    }, (failure: StellariumBridgeResponse) => { this.satelliteStore.satSourceStatus = failure.error ?? I18n.t('sat_source_invalid') })
  }

  // 按索引剔除来源后写回。
  deleteSatelliteSource(index: number): void {    const sources: SatelliteSourceInput[] = []
    for (let sourceIndex = 0; sourceIndex < this.satelliteStore.satSources.length; sourceIndex++) {
      if (sourceIndex !== index) {
        const source = this.satelliteStore.satSources[sourceIndex]
        sources.push({ url: source.url, addNew: source.addNew })
      }
    }
    this.port.requestInteractive('setSatelliteSources', JSON.stringify({ sources: sources }), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.satelliteStore.satSourceStatus = I18n.t('sat_source_deleted')
        this.satelliteStore.loadSatelliteSources()
      } else this.satelliteStore.satSourceStatus = r.error ?? I18n.t('sat_source_invalid')
    }, (failure: StellariumBridgeResponse) => { this.satelliteStore.satSourceStatus = failure.error ?? I18n.t('sat_source_invalid') })
  }

  // 进入编辑：把来源 URL 回填输入框并展开该行。
  editSatelliteSource(index: number): void {
    const source = this.satelliteStore.satSources[index]
    if (source === undefined) return
    this.satelliteStore.editingSatelliteSourceIndex = index
    this.satelliteStore.satSourceInput = source.url
    this.satelliteStore.expandedSatelliteSourceIndex = index
  }

  // 开关单个来源的自动加入标志后写回。
  setSatelliteSourceEnabled(index: number, enabled: boolean): void {
    const sources: SatelliteSourceInput[] = []
    for (let sourceIndex = 0; sourceIndex < this.satelliteStore.satSources.length; sourceIndex++) {
      const source = this.satelliteStore.satSources[sourceIndex]
      sources.push({ url: source.url, addNew: sourceIndex === index ? enabled : source.addNew })
    }
    this.port.requestInteractive('setSatelliteSources', JSON.stringify({ sources: sources }), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.satelliteStore.satSourceStatus = enabled ? I18n.t('sat_source_enabled') : I18n.t('sat_source_disabled')
        this.satelliteStore.loadSatelliteSources()
      } else this.satelliteStore.satSourceStatus = r.error ?? I18n.t('sat_source_invalid')
    }, (failure: StellariumBridgeResponse) => { this.satelliteStore.satSourceStatus = failure.error ?? I18n.t('sat_source_invalid') })
  }

  // 一键开/关全部来源（镜像分组一次到位，省得逐个点）。
  setAllSatelliteSourcesEnabled(enabled: boolean): void {
    const sources: SatelliteSourceInput[] = []
    for (let i = 0; i < this.satelliteStore.satSources.length; i++) {
      sources.push({ url: this.satelliteStore.satSources[i].url, addNew: enabled })
    }
    if (sources.length === 0) return
    this.port.requestInteractive('setSatelliteSources', JSON.stringify({ sources: sources }), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.satelliteStore.satSourceStatus = enabled
          ? '已全部开启（' + sources.length + ' 组）'
          : '已全部关闭'
        this.satelliteStore.loadSatelliteSources()
        this.satelliteStore.loadSatellites(true, true)
      } else this.satelliteStore.satSourceStatus = r.error ?? I18n.t('sat_source_invalid')
    }, (failure: StellariumBridgeResponse) => { this.satelliteStore.satSourceStatus = failure.error ?? I18n.t('sat_source_invalid') })
  }

  // 恢复默认 TLE 来源（清空编辑态后重载）。
  restoreSatelliteSources(): void {
    this.port.requestInteractive('restoreSatelliteSources', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.satelliteStore.editingSatelliteSourceIndex = -1
        this.satelliteStore.expandedSatelliteSourceIndex = -1
        this.satelliteStore.satSourceInput = ''
        this.satelliteStore.satSourceStatus = I18n.t('sat_source_restore')
        this.satelliteStore.loadSatelliteSources()
      } else this.satelliteStore.satSourceStatus = r.error ?? I18n.t('sat_source_invalid')
    }, (failure: StellariumBridgeResponse) => { this.satelliteStore.satSourceStatus = failure.error ?? I18n.t('sat_source_invalid') })
  }

  // 导入本地 TLE：pathOverride 优先（文件选择器落盘后的沙箱路径），否则用输入框里的路径。
  importSatelliteTleFile(pathOverride: string = ''): void {
    const path = (pathOverride.length > 0 ? pathOverride : this.satelliteStore.satTleFileInput).trim()
    if (path.length === 0) { this.satelliteStore.satSourceStatus = I18n.t('sat_tle_path_empty'); return }
    this.port.requestInteractive('importSatelliteTle', JSON.stringify({ paths: [path] }), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.satelliteStore.satTleFileInput = ''
        this.satelliteStore.satSourceStatus = I18n.t('sat_tle_imported')
        this.satelliteStore.loadSatellites(true, true)
      } else this.satelliteStore.satSourceStatus = r.error ?? I18n.t('sat_tle_import_failed')
    }, (failure: StellariumBridgeResponse) => { this.satelliteStore.satSourceStatus = failure.error ?? I18n.t('sat_tle_import_failed') })
  }

  // 刷新目录（离线构建回退提示）。
  refreshSatelliteCatalog(): void {
    this.port.requestInteractive('refreshSatelliteCatalog', '', (r: StellariumBridgeResponse) => {
      this.satelliteStore.satSourceStatus = r.ok === true ? I18n.t('sat_refresh_started') : (r.error ?? I18n.t('sat_refresh_offline'))
      this.satelliteStore.loadSatelliteSources()
    }, (failure: StellariumBridgeResponse) => { this.satelliteStore.satSourceStatus = failure.error ?? I18n.t('sat_refresh_offline') })
  }

  // 显示开关写回（同值短路 + mutationId 代际回滚）。
  setSatelliteFlag(name: string, v: boolean): void {
    if ((name === 'labels' && this.satelliteStore.satLabels === v) ||
      (name === 'orbitLines' && this.satelliteStore.satOrbitLines === v) ||
      (name === 'hints' && this.satelliteStore.satHints === v) ||
      (name === 'iconicMode' && this.satelliteStore.satIconicMode === v) ||
      (name === 'hideInvisible' && this.satelliteStore.satHideInvisible === v)) return
    const mutationId = ++this.satelliteStore.satelliteFlagMutationId
    let previous: boolean | undefined
    if (name == 'labels') { previous = this.satelliteStore.satLabels; this.satelliteStore.satLabels = v }
    else if (name == 'orbitLines') { previous = this.satelliteStore.satOrbitLines; this.satelliteStore.satOrbitLines = v }
    else if (name == 'hints') { previous = this.satelliteStore.satHints; this.satelliteStore.satHints = v }
    else if (name == 'iconicMode') { previous = this.satelliteStore.satIconicMode; this.satelliteStore.satIconicMode = v }
    else if (name == 'hideInvisible') { previous = this.satelliteStore.satHideInvisible; this.satelliteStore.satHideInvisible = v }
    this.port.requestWhenReady('setSatellitesFlag', name + ':' + (v ? '1' : '0'), () => {}, () => {
      if (mutationId !== this.satelliteStore.satelliteFlagMutationId || previous === undefined) return
      if (name == 'labels') this.satelliteStore.satLabels = previous
      else if (name == 'orbitLines') this.satelliteStore.satOrbitLines = previous
      else if (name == 'hints') this.satelliteStore.satHints = previous
      else if (name == 'iconicMode') this.satelliteStore.satIconicMode = previous
      else if (name == 'hideInvisible') this.satelliteStore.satHideInvisible = previous
    }, 0, 100, 15)
  }

  // 跳转后若视角过窄，拉远到 16° 以便框入月球(卫星)。
  frameSatellite(): void {
    this.port.requestWhenReady('getSessionState', '', (r: StellariumBridgeResponse) => {
      const fov = (r.fovDeg ?? 0)
      if (fov > 0 && fov < 12) {
        const target = 16
        this.port.requestWhenReady('zoomBy', (target / fov).toFixed(3) + '|0', () => {})
      }
    })
  }
}
