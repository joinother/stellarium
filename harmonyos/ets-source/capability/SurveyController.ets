// HiPS / TOAST 巡天 + 多波段图层控制器。
//
// 读取 HiPS 巡天开关与目录加载状态，管理首批真实多波段数据集的列出、打开与关闭。本类不 import
// NAPI/UI：桥调用走 CommandPort，UI 提示与巡天开关写回（LayerStore）经 SurveyHostHooks 回注。
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'
import { SurveyStore } from '../state/SurveyStore'
import { SpectralDataset, SpectralState, SurveyStateResponse, StellariumBridgeResponse } from '../common/types/StellariumTypes'

// 宿主 → 控制器回注：巡天开关回写 LayerStore、UI 提示。
export interface SurveyHostHooks {
  applySurveyFlags(hipsEnabled: boolean, toastEnabled: boolean): void
  flashHint(text: ResourceStr): void
}

export class SurveyController {
  private store: SurveyStore
  private port: CommandPort
  private hooks: SurveyHostHooks
  private lastToastEnabled: boolean = false
  private refreshTimers: Array<number> = []

  constructor(store: SurveyStore, port: CommandPort, hooks: SurveyHostHooks) {
    this.store = store
    this.port = port
    this.hooks = hooks
  }

  private clearRefreshTimers(): void {
    for (const timerId of this.refreshTimers) {
      clearTimeout(timerId)
    }
    this.refreshTimers = []
  }

  private scheduleStatusRefresh(): void {
    this.clearRefreshTimers()
    const t1: number = setTimeout(() => { this.loadSpectralDatasets() }, 900)
    const t2: number = setTimeout(() => { this.loadSpectralDatasets() }, 2800)
    this.refreshTimers.push(t1, t2)
  }

  private buildStateText(datasets: Array<SpectralDataset>, active: SpectralDataset | undefined): string {
    if (datasets.length === 0) return '多光谱目录暂不可用。'
    if (active !== undefined) {
      if (active.hdReady === true) {
        return '已开启「' + active.title + '」· 在线高清瓦片就绪，放大自动加载细节。'
      }
      if (active.loading === true) {
        return active.offlineReady === true
          ? '已显示「' + active.title + '」内置全天视图，正在连接高清巡天瓦片…'
          : '正在加载「' + active.title + '」可见天区瓦片…'
      }
      if (active.offlineReady === true) {
        return '已显示「' + active.title + '」内置全天视图（离线可用，联网后可加载高清瓦片）。'
      }
      if ((active.error ?? '').length > 0) {
        return '数据源暂不可用：' + (active.error ?? '')
      }
      return '已开启「' + active.title + '」。'
    }
    return '内置 9 波段全天全景可离线秒切；联网放大时自动从 China-VO / ESA / MPE 加载高清瓦片。'
  }

  // 读取巡天状态，写回 store，并继续加载多波段数据集列表。
  loadSurveyState(): void {
    this.port.requestInteractive('getSurveyState', '', (r: StellariumBridgeResponse) => {
      const state = r as SurveyStateResponse
      if (r.ok !== true) {
        this.store.surveyStateText = I18n.t('plugin_status_unavailable')
        return
      }
      this.lastToastEnabled = state.toastEnabled === true
      this.hooks.applySurveyFlags(state.hipsEnabled === true, this.lastToastEnabled)
      this.store.surveyStateText = state.hipsLoading === true ? I18n.t('c_loading') :
        ((state.hipsVisibleCount ?? 0) > 0 ? I18n.t('survey_selected') + ': ' + (state.hipsVisibleCount ?? 0).toString() : I18n.t('survey_no_selection'))
      this.loadSpectralDatasets()
    })
  }

  // 列出多波段数据集及其加载状态。
  loadSpectralDatasets(): void {
    this.port.requestInteractive('getSpectralDatasets', '', (r: StellariumBridgeResponse) => {
      const datasets = r.datasets
      this.store.spectralDatasets = datasets ?? []
      const active = this.store.spectralDatasets.find((dataset: SpectralDataset): boolean => dataset.enabled === true)
      this.store.spectralActiveId = active?.id ?? ''
      this.store.spectralStateText = this.buildStateText(this.store.spectralDatasets, active)
    })
  }

  // 用户主动打开或再次点按关闭一个多波段 HiPS 图层。
  setSpectralDataset(id: string): void {
    if (this.store.spectralActiveId === id) {
      this.closeSpectralView()
      return
    }
    this.store.spectralStateText = '正在切换多光谱图层…'
    this.port.requestInteractive('setSpectralView', JSON.stringify({ id: id, enabled: true }), (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.store.spectralStateText = r.error ?? '多光谱图层加载失败。'
        return
      }
      const state = r.spectral as SpectralState | undefined
      this.store.spectralActiveId = state?.datasetId ?? id
      this.hooks.applySurveyFlags(true, this.lastToastEnabled)
      this.store.surveyStateText = I18n.t('survey_selected') + ': 1'
      if (state?.hdReady === true) {
        this.store.spectralStateText = '多光谱图层已打开（高清瓦片就绪）。'
      } else if (state?.offlineReady === true) {
        this.store.spectralStateText = state?.loading === true
          ? '已显示内置全天视图，正在连接高清巡天瓦片…'
          : '已显示内置全天视图（离线可用）。'
      } else {
        this.store.spectralStateText = state?.loading === true ? '正在加载可见天区瓦片…' : '多光谱图层已打开。'
      }
      this.loadSpectralDatasets()
      if (state?.loading === true || state?.hdReady !== true) {
        this.scheduleStatusRefresh()
      }
    })
  }

  // 关闭多波段图层（保留缓存）。
  closeSpectralView(): void {
    this.clearRefreshTimers()
    this.port.requestInteractive('closeSpectralView', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.store.spectralActiveId = ''
        this.hooks.applySurveyFlags(false, this.lastToastEnabled)
        this.store.surveyStateText = I18n.t('survey_no_selection')
        this.store.spectralStateText = '多光谱图层已关闭，缓存保留。'
        this.loadSpectralDatasets()
      } else {
        this.store.spectralStateText = r.error ?? '关闭多光谱图层失败。'
      }
    })
  }
}
