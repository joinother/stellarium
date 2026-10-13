// 星空纹理加载状态观察控制器：轮询 getDeepSkyImageStatus，把当前视野资料图的
// 加载中 / 失败 / 就绪状态写入 ToolsStore 的状态条字段。
//
// 自含状态机 + 定时器：start() 启动观察（延迟 180ms 后重置并轮询），stop() 为收口点，
// 宿主生命周期直接调用。桥经 CommandPort，控制器不 import NAPI/UI，只写 store。
import hilog from '@ohos.hilog'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { ToolsStore } from '../state/ToolsStore'
import { BehaviorHostHooks } from './ControllerHooks'

// 快轮询 24 次后转慢轮询，90 次仍未就绪则升级为可操作的错误态。
const SKY_TEXTURE_STATUS_FAST_POLLS: number = 24
const SKY_TEXTURE_STATUS_SLOW_INTERVAL_MS: number = 2000
const SKY_TEXTURE_STATUS_STALL_POLLS: number = 90

export interface SkyTextureStatusHostHooks extends BehaviorHostHooks {}

export class SkyTextureStatusController {
  private port: CommandPort
  private tools: ToolsStore
  private hooks: SkyTextureStatusHostHooks
  // 定时器句柄 / 轮询草稿字段（随控制器走）。
  private skyTextureStatusTimer: number = 0
  private skyTextureStatusDelayTimer: number = 0
  private skyTextureStatusPolls: number = 0
  private skyTextureStatusSlow: boolean = false

  constructor(port: CommandPort, tools: ToolsStore, hooks: SkyTextureStatusHostHooks) {
    this.port = port
    this.tools = tools
    this.hooks = hooks
  }

  // 定时器自持入口：延迟 180ms 后重置观察并开始轮询。
  start(): void {
    this.scheduleSkyTextureStatusCheck()
  }

  // 定时器自持收口：停止两个定时器并复位轮询计数。
  stop(): void {
    this.stopSkyTextureStatusObserver()
  }

  private stopSkyTextureStatusObserver(): void {
    if (this.skyTextureStatusTimer !== 0) {
      clearTimeout(this.skyTextureStatusTimer)
      this.skyTextureStatusTimer = 0
    }
    if (this.skyTextureStatusDelayTimer !== 0) {
      clearTimeout(this.skyTextureStatusDelayTimer)
      this.skyTextureStatusDelayTimer = 0
    }
    this.skyTextureStatusPolls = 0
    this.skyTextureStatusSlow = false
  }

  private hideSkyTextureStatus(): void {
    this.stopSkyTextureStatusObserver()
    this.tools.skyTextureStatusVisible = false
    this.tools.skyTextureStatusText = ''
    this.tools.skyTextureStatusError = false
  }

  private updateSkyTextureStatus(result: StellariumBridgeResponse): void {
    if (result.ok !== true) {
      this.hideSkyTextureStatus()
      return
    }
    const pending = typeof result.activeTexturePendingCount === 'number'
      ? result.activeTexturePendingCount as number : 0
    const errors = typeof result.activeTextureErrorCount === 'number'
      ? result.activeTextureErrorCount as number : 0
    const status = result.activeTextureStatus ?? ''
    if (errors > 0 || status === 'error' || status === 'partial-error') {
      hilog.warn(0x0000, 'StellariumArkUI', '[sky-banner] error count=%{public}d status=%{public}s',
        errors, status)
      this.tools.skyTextureStatusVisible = true
      this.tools.skyTextureStatusError = true
      this.tools.skyTextureStatusText = '当前视野有 ' + errors.toString() + ' 项资料图加载失败'
      return
    }
    if (pending > 0 || status === 'loading') {
      hilog.info(0x0000, 'StellariumArkUI', '[sky-banner] loading pending=%{public}d status=%{public}s',
        pending, status)
      this.tools.skyTextureStatusVisible = true
      this.tools.skyTextureStatusError = false
      this.tools.skyTextureStatusText = '正在载入当前视野资料图 · ' + pending.toString() + ' 项待完成'
      return
    }
    this.hideSkyTextureStatus()
  }

  private pollSkyTextureStatus(): void {
    this.skyTextureStatusPolls++
    if (this.skyTextureStatusPolls >= SKY_TEXTURE_STATUS_FAST_POLLS) {
      this.skyTextureStatusSlow = true
    }
    // A stall far past any plausible load is surfaced as an actionable error so
    // the banner can never sit on a loading state that will never finish. This
    // is an escalation, not a silent hide: the user keeps a retry affordance.
    if (this.skyTextureStatusSlow && this.skyTextureStatusPolls >= SKY_TEXTURE_STATUS_STALL_POLLS) {
      this.tools.skyTextureStatusVisible = true
      this.tools.skyTextureStatusError = true
      this.tools.skyTextureStatusText = '当前视野资料图仍在准备，可稍后重试'
      this.stopSkyTextureStatusObserver()
      return
    }
    this.port.requestInteractive('getDeepSkyImageStatus', '', (result: StellariumBridgeResponse) => {
      this.updateSkyTextureStatus(result)
      // updateSkyTextureStatus already retracts the banner and stops polling
      // when the bridge reports a failure.
      if (result.ok !== true) {
        return
      }
      const pending = typeof result.activeTexturePendingCount === 'number'
        ? result.activeTexturePendingCount as number : 0
      if (pending <= 0 || result.activeTextureStatus === 'error' || result.activeTextureStatus === 'partial-error') {
        this.stopSkyTextureStatusObserver()
        return
      }
      const delay = this.skyTextureStatusSlow ? SKY_TEXTURE_STATUS_SLOW_INTERVAL_MS
        : (this.skyTextureStatusPolls <= 8 ? 350 : 900)
      this.skyTextureStatusTimer = setTimeout(() => {
        this.skyTextureStatusTimer = 0
        this.pollSkyTextureStatus()
      }, delay) as number
    }, () => {
      // The bridge did not answer; sample again later without inventing a state.
      const delay = this.skyTextureStatusSlow ? SKY_TEXTURE_STATUS_SLOW_INTERVAL_MS : 900
      this.skyTextureStatusTimer = setTimeout(() => {
        this.skyTextureStatusTimer = 0
        this.pollSkyTextureStatus()
      }, delay) as number
    })
  }

  private scheduleSkyTextureStatusCheck(): void {
    if (this.skyTextureStatusDelayTimer !== 0) {
      clearTimeout(this.skyTextureStatusDelayTimer)
    }
    this.skyTextureStatusDelayTimer = setTimeout(() => {
      this.skyTextureStatusDelayTimer = 0
      this.stopSkyTextureStatusObserver()
      this.pollSkyTextureStatus()
    }, 180) as number
  }

  // 「重试」按钮入口（宿主状态条 UI onClick）。
  retrySkyTextureStatus(): void {
    this.tools.skyTextureStatusError = false
    this.tools.skyTextureStatusVisible = true
    this.tools.skyTextureStatusText = '正在重新载入当前视野资料图'
    this.port.requestInteractive('retryDeepSkyImages', '', () => {
      this.scheduleSkyTextureStatusCheck()
    }, () => { this.tools.skyTextureStatusError = true })
  }
}
