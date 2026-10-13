// 时间平滑过渡控制器。
//
// 把天文计算结果（升中天落、星历、天象、节气、指定时间…）从「瞬移」改为「平滑推进」：
// 短距离（<3 天）逐帧 ease 计算 JD 并节流 setTimeToJD；长距离让引擎按原生速率连续推进，
// 结束时提交精确 JD。结束后恢复原时间速率。本类不 import NAPI/UI：桥调用走 CommandPort，
// UI 提示 / 时间轴与滚轮同步 / 时间速率回写经 TimeTransitionHostHooks 回注。
import { CommandPort } from '../bridge/CommandPort'
import { StellariumBridgeResponse } from '../common/types/StellariumTypes'

// 宿主 → 控制器回注：提示、速率回写、UI 同步收口。
export interface TimeTransitionHostHooks {
  flashHint(text: ResourceStr): void
  getSimulationTime(onOk: (jd: number, timeRate: number) => void, onFailure: () => void): void
  setTimeRate(rate: number): void
  syncTimeRateState(rate: number): void
  syncWheelFromSimulation(jd: number): void
  refreshTimeNow(): void
  refreshState(): void
}

export class TimeTransitionController {
  private port: CommandPort
  private hooks: TimeTransitionHostHooks
  private timer: number = 0
  private serial: number = 0
  private restoreRate: number = 0
  private lastPushMs: number = 0
  private usesNativeRate: boolean = false
  private targetJd: number = 0
  // 时间导航（指定时间 / 时间标记）进行中：抑制选中详情等刷新，避免与过渡打架。
  private navigationRequestActive: boolean = false

  constructor(port: CommandPort, hooks: TimeTransitionHostHooks) {
    this.port = port
    this.hooks = hooks
  }

  // 距离越远过渡越久，对数尺度，900ms ~ 7000ms。
  private durationMs(distanceDays: number): number {
    const normalized = Math.max(0, Math.log10(Math.max(0, distanceDays) + 1))
    const raw = 900 + Math.pow(normalized, 1.45) * 1200
    return Math.round(Math.max(900, Math.min(7000, raw)))
  }

  reset(): void {
    this.navigationRequestActive = false
    this.stop(false)
  }

  // 停过渡并（可选）恢复原速率。
  stop(restoreRate: boolean = false): void {
    this.serial++
    if (this.timer !== 0) {
      clearInterval(this.timer)
      this.timer = 0
    }
    if (this.usesNativeRate) {
      this.hooks.setTimeRate(0)
    }
    this.usesNativeRate = false
    this.targetJd = 0
    const restore = this.restoreRate
    this.restoreRate = 0
    if (restoreRate && Number.isFinite(restore) && Math.abs(restore) > 1e-12) {
      this.hooks.setTimeRate(restore)
      this.hooks.syncTimeRateState(restore)
    }
  }

  // 平滑前往 targetJd；完成后回调 onFinished。
  animate(targetJd: number, label: string, onFinished?: () => void): void {
    if (!Number.isFinite(targetJd) || targetJd <= 0) {
      this.hooks.flashHint('没有可用的目标时刻。')
      return
    }
    this.stop(false)
    const serial = this.serial
    this.hooks.getSimulationTime((startJd: number, currentRate: number) => {
      if (serial !== this.serial) return
      if (!Number.isFinite(startJd) || startJd <= 0) {
        this.hooks.flashHint('读取当前模拟时间失败，请重试。')
        return
      }
      this.restoreRate = Number.isFinite(currentRate) ? currentRate : 0
      const distanceSeconds = Math.abs(targetJd - startJd) * 86400.0
      if (distanceSeconds < 1.0) {
        this.port.fire('setTimeToJD', targetJd.toFixed(8))
        this.hooks.refreshTimeNow()
        if (onFinished !== undefined) onFinished()
        return
      }
      this.hooks.setTimeRate(0)
      this.hooks.syncTimeRateState(0)
      const distanceDays = distanceSeconds / 86400.0
      const durationMs = this.durationMs(distanceDays)
      const useNativeRate = distanceDays >= 3.0
      if (useNativeRate) {
        const travelRate = (targetJd - startJd) / (durationMs / 1000.0)
        this.usesNativeRate = true
        this.targetJd = targetJd
        this.hooks.setTimeRate(travelRate)
      }
      const pushIntervalMs = distanceDays >= 30 ? 32 : 48
      const startedAt = Date.now()
      this.lastPushMs = 0
      this.hooks.flashHint('正在平滑前往' + label + '…')
      this.timer = setInterval(() => {
        if (serial !== this.serial) return
        const elapsed = Date.now() - startedAt
        const progress = Math.max(0, Math.min(1, elapsed / durationMs))
        if (useNativeRate) {
          if (progress < 1) return
          this.finish(targetJd, label, onFinished)
          return
        }
        const eased = progress * progress * (3 - 2 * progress)
        const jd = startJd + (targetJd - startJd) * eased
        const now = Date.now()
        if (progress >= 1 || now - this.lastPushMs >= pushIntervalMs) {
          this.lastPushMs = now
          this.port.fire('setTimeToJD', jd.toFixed(8))
        }
        if (progress >= 1) {
          this.finish(targetJd, label, onFinished)
        }
      }, 16) as number
    }, () => {
      if (serial === this.serial) this.hooks.flashHint('读取当前模拟时间失败，请重试。')
    })
  }

  private finish(targetJd: number, label: string, onFinished?: () => void): void {
    const rateToRestore = this.restoreRate
    this.stop(false)
    this.port.fire('setTimeToJD', targetJd.toFixed(8))
    if (Number.isFinite(rateToRestore) && Math.abs(rateToRestore) > 1e-12) {
      this.hooks.setTimeRate(rateToRestore)
      this.hooks.syncTimeRateState(rateToRestore)
    }
    this.hooks.syncWheelFromSimulation(targetJd)
    this.hooks.refreshTimeNow()
    this.hooks.refreshState()
    this.hooks.flashHint('已到达' + label + '。')
    if (onFinished !== undefined) onFinished()
  }

  // 过渡是否进行中（供选中详情等刷新守卫使用）。
  isBusy(): boolean {
    return this.navigationRequestActive || this.timer !== 0
  }

  setNavigationRequestActive(value: boolean): void {
    this.navigationRequestActive = value
  }
}
