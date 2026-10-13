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

  constructor(store: SurveyStore, port: CommandPort, hooks: SurveyHostHooks) {
    this.store = store
    this.port = port
    this.hooks = hooks
  }

  // 读取巡天状态，写回 store，并继续加载多波段数据集列表。
  loadSurveyState(): void {
    this.port.requestInteractive('getSurveyState', '', (r: StellariumBridgeResponse) => {
      const state = r as SurveyStateResponse
      if (r.ok !== true) {
        this.store.surveyStateText = I18n.t('plugin_status_unavailable')
        return
      }
      this.hooks.applySurveyFlags(state.hipsEnabled === true, state.toastEnabled === true)
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
      const failed = this.store.spectralDatasets.find((dataset: SpectralDataset): boolean => (dataset.error ?? '').length > 0)
      this.store.spectralStateText = failed !== undefined ? '数据源暂不可用：' + (failed.error ?? '') :
        (this.store.spectralDatasets.length > 0 ? '仅在选择后加载，覆盖范围以数据源说明为准；许可需逐产品核验。' : '多光谱目录暂不可用。')
    })
  }

  // 用户主动打开一个多波段 HiPS 图层。
  setSpectralDataset(id: string): void {
    this.store.spectralStateText = '正在准备多光谱图层…'
    this.port.requestInteractive('setSpectralView', JSON.stringify({ id: id, enabled: true }), (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.store.spectralStateText = r.error ?? '多光谱图层加载失败。'
        return
      }
      const state = r.spectral as SpectralState | undefined
      this.store.spectralActiveId = state?.datasetId ?? id
      this.store.spectralStateText = state?.loading === true ? '正在加载可见天区瓦片…' : '多光谱图层已打开。'
      this.loadSpectralDatasets()
    })
  }

  // 关闭多波段图层（保留缓存）。
  closeSpectralView(): void {
    this.port.requestInteractive('closeSpectralView', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.store.spectralActiveId = ''
        this.store.spectralStateText = '多光谱图层已关闭，缓存保留。'
      } else {
        this.store.spectralStateText = r.error ?? '关闭多光谱图层失败。'
      }
    })
  }
}
