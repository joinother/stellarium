import { PolarScopeData, StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { I18n } from '../pages/I18n'

// 极轴镜（polarScope）屏幕叠层域状态：持有可见性 polarScopeVisible、请求态
// polarScopeLoading / polarScopeError、数据 polarScopeData 与翻转开关
// polarScopeHorizontalFlip / polarScopeVerticalFlip（随 saveAppSettings 持久化）。
// 叠层以 @ObjectLink 观察，读数由组件就地读 polarScopeData 派生。
//
// 自持 CommandPort、极轴镜数据加载器 loadPolarScopeData 与在途请求态
//（polarScopeRequestPending / 请求序号）；「是否应刷新」谓词
//（applicationInForeground && polarScopeVisible）归宿主，经具名 hooks 注入。
// 极轴镜几何与引擎/定时器字段不入 store，由宿主算好后以 @Prop 传入。
//
// 约束：所有更新必须是"字段整体赋值"（polarScopeData 只被整体赋值，无原地变更）。
export interface PolarScopeHostHooks {
  shouldRefreshPolarScope(): boolean
}

@Observed
export class PolarScopeStore {
  polarScopeData: PolarScopeData | undefined = undefined
  polarScopeVisible: boolean = false
  polarScopeLoading: boolean = false
  polarScopeError: string = ''
  polarScopeHorizontalFlip: boolean = false
  polarScopeVerticalFlip: boolean = false

  // —— 桥注入 ——
  private port: CommandPort | null = null
  private hooks: PolarScopeHostHooks | null = null
  private polarScopeRequestPending: boolean = false
  private polarScopeDataRequestSequence: number = 0

  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachHooks(hooks: PolarScopeHostHooks): void {
    this.hooks = hooks
  }

  private ensurePort(): CommandPort | null {
    return this.port
  }

  private shouldRefresh(): boolean {
    const hooks = this.hooks
    return hooks !== null && hooks.shouldRefreshPolarScope()
  }

  // 作废在途请求并清 pending（宿主停止计时器时调用）。
  cancelPolarScopeRequest(): void {
    this.polarScopeRequestPending = false
    ++this.polarScopeDataRequestSequence
  }

  // 极轴镜数据加载器：仅在允许刷新且无在途请求时发起；请求序号用于丢弃过期回包。
  loadPolarScopeData(showLoading: boolean = true): void {
    if (!this.shouldRefresh() || this.polarScopeRequestPending) return
    const port = this.ensurePort()
    if (port === null) return
    this.polarScopeRequestPending = true
    const requestId = this.polarScopeDataRequestSequence
    if (showLoading && this.polarScopeData === undefined) this.polarScopeLoading = true
    port.requestWhenReady('getPolarScopeData', '', (response: StellariumBridgeResponse) => {
      if (requestId !== this.polarScopeDataRequestSequence) return
      this.polarScopeRequestPending = false
      this.polarScopeLoading = false
      if (!this.shouldRefresh() || response.polarScope === undefined) return
      this.polarScopeData = response.polarScope
      this.polarScopeError = ''
    }, () => {
      if (requestId !== this.polarScopeDataRequestSequence) return
      this.polarScopeRequestPending = false
      this.polarScopeLoading = false
      this.polarScopeError = I18n.t('polar_scope_earth_only')
    }, 0, 34, 8)
  }
}
