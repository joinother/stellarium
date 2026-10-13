// 时间面板域状态：① 速度/速率（timeSpeedIndex + timeRateText + 换挡待定窗口）；
// ② 恒星时显示；③ 手工日期时间选择器模型（manualYear..manualMinute）。
// 消费方（TimePanel / ManualTimeBlock 等）以 @Prop / @ObjectLink 观察。
// 自持 CommandPort；loadTimeExtras 的跨域助手（夜视同步、大气回包）经 TimeHostHooks 注入，
// store 不持有他域 store。时间轮的交互草稿状态在 TimeWheelStore，交互行为在 TimeWheelController。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → TimeStore 的加载助手注入（store 不持有他域 store）。
export interface TimeHostHooks {
  // 夜视模式随引擎回报同步（写 NightModeStore + 消费宿主 pendingNightMode 待定窗口）。
  syncNightModeFromEngine(engineNight: boolean): void
  // 大气参数回包写入 AtmosphereStore（与宿主 applyAtmosphere 共用同一实现）。
  applyAtmosphereResponse(response: StellariumBridgeResponse): void
}

@Observed
export class TimeStore {
  timeSpeedIndex: number = 7  // 7 = 1x 实时（默认档位）
  siderealTimeText: string = '--'
  observationTimeText: string = '--'

  // ==== 速度/速率 ====
  timeRateText: string = '1x'
  pendingTimeRate: number = Number.NaN
  pendingTimeRateUntilMs: number = 0
  lastSyncedTimeRate: number = Number.NaN
  lastNonZeroSpeedIndex: number = 7

  // ==== 手工日期时间选择器模型 ====
  // 时间面板（TimePanel → ManualTimeBlock）经 @Prop 消费；宿主 applyManualTime /
  // syncManualTimeFromState 读写本簇。默认值为字面量，启动后由 syncManualTimeFromState
  // 用当前 JD 覆盖。
  manualYear: number = 2026
  manualMonth: number = 7
  manualDay: number = 20
  manualHour: number = 23
  manualMinute: number = 0

  // 记录一次"用户主动换挡"：待定窗口内忽略引擎回报的旧速率。
  // 与 syncTimeRateState 的既有 500 ms 窗口同源，集中在这里以免两处各写一遍。
  beginRateChange(rate: number, windowMs: number): void {
    this.pendingTimeRate = rate
    this.pendingTimeRateUntilMs = Date.now() + windowMs
  }

  // 引擎回报的速率是否应被忽略（陈旧或重复）。
  // 返回 true 表示调用方不要据此改写档位与文本。
  shouldIgnoreEngineRate(rate: number): boolean {
    const now = Date.now()
    if (!Number.isNaN(this.pendingTimeRate)) {
      const matchesPending = Math.abs(rate - this.pendingTimeRate) < 1e-9
      if (!matchesPending && now < this.pendingTimeRateUntilMs) {
        return true
      }
      this.pendingTimeRate = Number.NaN
      this.pendingTimeRateUntilMs = 0
    }
    // 换挡瞬间引擎仍会回报上一档速率：同一速率重复回报时不做任何反推，
    // 否则界面会先跳到旧档位再跳回新档位（真机实测到的「实时→倒带→实时」抖动）。
    return !Number.isNaN(this.lastSyncedTimeRate) && Math.abs(rate - this.lastSyncedTimeRate) < 1e-9
  }

  // —— 桥 / 宿主助手注入 ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（同步读取，无并发抑制需求）；预留以统一各 store 的桥注入约定。
  private seq: number = 0
  private onChanged: (() => void) | null = null
  private hooks: TimeHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  attachHooks(hooks: TimeHostHooks): void {
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // 恒星时 / 夜视 / 大气折射：时间面板打开与前台恢复时定时刷新；跨域助手经 hooks 注入。
  loadTimeExtras(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const hooks = this.hooks
    if (hooks === null) {
      return
    }
    const st: StellariumBridgeResponse = port.request('getSiderealTime', '')
    if (st.ok === true && st.text !== undefined) this.siderealTimeText = st.text

    const nm: StellariumBridgeResponse = port.request('getNightMode', '')
    if (nm.ok === true) hooks.syncNightModeFromEngine(nm.night === true)

    hooks.applyAtmosphereResponse(port.request('getAtmosphereParams', ''))
  }

  // ==== 时间面板标题的「取值/文案」助手（读本 store 的 observationTimeText / timeRateText）====

  // 面板副标题的时钟部分。
  timePanelClockText(): string {
    const text = this.observationTimeText
    const idx = text.indexOf(' ')
    return idx > 0 ? text.substring(idx + 1) : text
  }

  // 面板副标题的年月日 + 时间速率。
  timePanelDateText(): string {
    const text = this.observationTimeText
    const idx = text.indexOf(' ')
    const date = idx > 0 ? text.substring(0, idx) : ''
    return date.length > 0 ? date + ' · ' + this.timeRateText : this.timeRateText
  }

  // 面板副标题：仅当活动面板为时间面板时返回日期+速率，否则为空。
  // activePanel 属宿主路由保留字段，按显式入参传入。
  panelSubtitle(activePanel: string): string {
    if (activePanel === 'time') {
      return this.timePanelDateText()
    }
    return ''
  }
}
