// 极轴镜（PolarScope）行为控制器。
//
// 负责极轴镜叠层的开合、定时刷新、翻转切换与回中，并保存 / 恢复进入前的会话状态快照。
// 控制器不 import NAPI/UI：桥命令经 CommandPort 发出，极轴镜状态写入 PolarScopeStore
//（叠层经 @ObjectLink 消费）；面板路由（activePanel / panelVisible）、refreshState / flashHint 经
// BehaviorHostHooks 回调宿主；叠层几何（topInset / footerHeight / skyHeight / safeTopPixels）与
// 桥回包 flags 的 `as Record<...>` 抽取经 PolarScopeHostHooks 回注宿主（控制器禁用 `as`，
// 宿主侧 getUIContext().px2vp 亦收口于几何 hook）。
//
// 定时器 polarScopeTimer 由控制器自持：stopPolarScopeTimer / syncPolarScopeTimer 即 stop()/start()，
// 宿主生命周期（aboutToDisappear / 面板收口）与面板开合改调这两个入口；极轴镜数据加载器
// loadPolarScopeData 仍在 PolarScopeStore（其「是否应刷新」谓词经 hooks 回指本控制器）。
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse, SessionSnapshot } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { PolarScopeStore } from '../state/PolarScopeStore'
import { BehaviorHostHooks } from './ControllerHooks'

// 桥回包 flags / 观测星球名（宿主从 `response.flags` / `response.location` 的
// `as Record<string, Object>` 抽取后具名回注；控制器禁 as）。
export interface PolarScopeSessionFlags {
  horizontalFlip: boolean
  verticalFlip: boolean
  planetName: string
}

export interface PolarScopeHostHooks extends BehaviorHostHooks {
  applicationInForeground(): boolean
  skyHeight(): number
  screenSafeTopPixels(): number
  polarScopeTopInset(): number
  polarScopeFooterHeight(): number
  polarScopeSessionFlags(response: StellariumBridgeResponse): PolarScopeSessionFlags
}

export class PolarScopeController {
  private port: CommandPort
  private polarScopeStore: PolarScopeStore
  private hooks: PolarScopeHostHooks
  // 引擎/定时器草稿字段：不入 @Observed store。
  private polarScopeRestoreState: string = ''
  private polarScopeTransitionPending: boolean = false
  private polarScopeTransitionId: number = 0
  private polarScopeTimer: number = 0

  constructor(port: CommandPort, polarScopeStore: PolarScopeStore, hooks: PolarScopeHostHooks) {
    this.port = port
    this.polarScopeStore = polarScopeStore
    this.hooks = hooks
  }

  // 是否应刷新极轴镜：仅前台且叠层可见时为真。
  shouldRefreshPolarScope(): boolean {
    return this.hooks.applicationInForeground() && this.polarScopeStore.polarScopeVisible
  }

  // 停止轮询：清定时器并作废在途请求（store 语义）。
  stopPolarScopeTimer(): void {
    if (this.polarScopeTimer !== 0) {
      clearInterval(this.polarScopeTimer)
      this.polarScopeTimer = 0
    }
    this.polarScopeStore.cancelPolarScopeRequest()
  }

  // 同步轮询：可见且前台时启动 1s 轮询，否则停止。
  syncPolarScopeTimer(): void {
    if (!this.shouldRefreshPolarScope()) {
      this.stopPolarScopeTimer()
      return
    }
    this.polarScopeStore.loadPolarScopeData()
    if (this.polarScopeTimer === 0) {
      this.polarScopeTimer = setInterval(() => { this.polarScopeStore.loadPolarScopeData(false) }, 1000)
    }
  }

  // 打开极轴镜叠层：会话快照 → centerPolarScope → setFOV 4；重复调用则关闭。
  enterPolarScope(): void {
    if (this.polarScopeStore.polarScopeVisible) {
      this.closePolarScope()
      return
    }
    if (this.polarScopeTransitionPending) return
    const transitionId = ++this.polarScopeTransitionId
    this.polarScopeTransitionPending = true
    this.polarScopeStore.polarScopeLoading = true
    this.polarScopeStore.polarScopeError = ''
    this.polarScopeStore.polarScopeData = undefined
    this.hooks.panelChange('polarScope', false)
    this.polarScopeStore.polarScopeVisible = true
    this.syncNativePolarScopeOverlay(false)
    this.port.requestWhenReady('getSessionState', '', (response: StellariumBridgeResponse) => {
      if (transitionId !== this.polarScopeTransitionId) return
      const snapshot: SessionSnapshot = {
        viewJ2000: response.viewJ2000,
        fovDeg: response.fovDeg,
        jd: response.jd,
        location: response.location,
        selected: response.selected,
        flags: response.flags
      }
      this.polarScopeRestoreState = JSON.stringify(snapshot)
      const sessionFlags = this.hooks.polarScopeSessionFlags(response)
      this.polarScopeStore.polarScopeHorizontalFlip = sessionFlags.horizontalFlip
      this.polarScopeStore.polarScopeVerticalFlip = sessionFlags.verticalFlip
      if (sessionFlags.planetName !== 'Earth') {
        this.polarScopeTransitionPending = false
        this.polarScopeStore.polarScopeLoading = false
        this.polarScopeStore.polarScopeError = I18n.t('polar_scope_earth_only')
        return
      }
      this.port.requestWhenReady('centerPolarScope', '', () => {
        if (transitionId !== this.polarScopeTransitionId) return
        this.port.requestWhenReady('setFOV', '4', () => {
          if (transitionId !== this.polarScopeTransitionId) return
          this.polarScopeTransitionPending = false
          this.syncNativePolarScopeOverlay(true)
          this.syncPolarScopeTimer()
        }, () => {
          if (transitionId !== this.polarScopeTransitionId) return
          this.polarScopeTransitionPending = false
          this.polarScopeStore.polarScopeLoading = false
          this.polarScopeStore.polarScopeError = I18n.t('polar_scope_open_failed')
        }, 0, 100, 15)
      }, () => {
        if (transitionId !== this.polarScopeTransitionId) return
        this.polarScopeTransitionPending = false
        this.polarScopeStore.polarScopeLoading = false
        this.polarScopeStore.polarScopeError = I18n.t('polar_scope_open_failed')
      }, 0, 100, 15)
    }, () => {
      if (transitionId !== this.polarScopeTransitionId) return
      this.polarScopeTransitionPending = false
      this.polarScopeStore.polarScopeLoading = false
      this.polarScopeStore.polarScopeError = I18n.t('polar_scope_open_failed')
      this.syncNativePolarScopeOverlay(false)
    }, 0, 120, 20)
  }

  // 关闭叠层并恢复会话快照（refreshState 经 hooks）。
  closePolarScope(): void {
    if (!this.polarScopeStore.polarScopeVisible && !this.polarScopeTransitionPending) return
    ++this.polarScopeTransitionId
    this.polarScopeStore.polarScopeVisible = false
    this.stopPolarScopeTimer()
    this.polarScopeStore.polarScopeLoading = false
    this.syncNativePolarScopeOverlay(false)
    this.polarScopeTransitionPending = false
    const restoreState = this.polarScopeRestoreState
    this.polarScopeRestoreState = ''
    if (restoreState.length === 0) return
    this.polarScopeTransitionPending = true
    const restoreTransitionId = this.polarScopeTransitionId
    this.port.requestWhenReady('applySessionState', restoreState, () => {
      if (restoreTransitionId !== this.polarScopeTransitionId) return
      this.polarScopeTransitionPending = false
      this.hooks.refreshState()
    }, () => {
      if (restoreTransitionId !== this.polarScopeTransitionId) return
      this.polarScopeTransitionPending = false
      this.hooks.flashHint(I18n.t('polar_scope_restore_failed'))
    }, 0, 120, 20)
  }

  // 把激活态 + 翻转 + 安全区比例下发引擎叠层。
  syncNativePolarScopeOverlay(active: boolean): void {
    const height = Math.max(1, this.hooks.skyHeight())
    const safeTopRatio = (this.hooks.polarScopeTopInset() + 68) / height
    const safeBottomRatio = (this.hooks.polarScopeFooterHeight() + 20) / height
    const payload = (active ? '1' : '0') + '|' + (this.polarScopeStore.polarScopeHorizontalFlip ? '1' : '0') + '|' +
      (this.polarScopeStore.polarScopeVerticalFlip ? '1' : '0') + '|' + safeTopRatio.toString() + '|' + safeBottomRatio.toString() +
      '|' + Math.max(0, Math.round(this.hooks.screenSafeTopPixels())).toString()
    this.port.requestWhenReady('setPolarScopeOverlay', payload, () => {})
  }

  // 回中 + 复位 FOV，随后刷新极轴镜数据。
  recenterPolarScope(): void {
    if (this.polarScopeTransitionPending) return
    this.port.requestInteractive('centerPolarScope', '', () => {
      this.port.requestInteractive('setFOV', '4', () => { this.polarScopeStore.loadPolarScopeData(false) })
    })
  }

  // 水平翻转：乐观写并下发叠层，失败回滚。
  setPolarScopeHorizontalFlip(value: boolean): void {
    if (value === this.polarScopeStore.polarScopeHorizontalFlip) return
    this.polarScopeStore.polarScopeHorizontalFlip = value
    this.syncNativePolarScopeOverlay(true)
    this.port.requestInteractive('setActionChecked', 'actionHorizontal_Flip|' + (value ? '1' : '0'), () => {
      this.polarScopeStore.loadPolarScopeData(false)
    }, () => {
      this.polarScopeStore.polarScopeHorizontalFlip = !value
    })
  }

  // 垂直翻转：乐观写并下发叠层，失败回滚。
  setPolarScopeVerticalFlip(value: boolean): void {
    if (value === this.polarScopeStore.polarScopeVerticalFlip) return
    this.polarScopeStore.polarScopeVerticalFlip = value
    this.syncNativePolarScopeOverlay(true)
    this.port.requestInteractive('setActionChecked', 'actionVertical_Flip|' + (value ? '1' : '0'), () => {
      this.polarScopeStore.loadPolarScopeData(false)
    }, () => {
      this.polarScopeStore.polarScopeVerticalFlip = !value
    })
  }
}
