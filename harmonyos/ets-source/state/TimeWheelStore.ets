// 时间轮（转轴）域状态 + 纯取值计算。
//
// 只在 store 里放「数据 + 纯计算」：日期/字段取值、tick 标签生成与刻度量值。
// 交互（拖动 / 惯性 / 轨道重基准 / 引擎同步）在 TimeWheelController，视图在 TimeWheelScrubber；
// 宿主以 @State 持有本 store，视图以 @ObjectLink 订阅。
// 时间轮构造初值：模块加载时的设备本地时间。引擎就绪后由
// TimeWheelController.seedFromSimulation() 用当前模拟 JD 覆盖；构造时即生成
// 刻度标签，避免面板第一次打开先显示硬编码旧日期、再等轮询到达才刷新。
const INITIAL_WHEEL_TIME: Date = new Date()

@Observed
export class TimeWheelStore {
  timeWheelUnit: string = 'hour'
  timeWheelYear: number = INITIAL_WHEEL_TIME.getFullYear()
  timeWheelMonth: number = INITIAL_WHEEL_TIME.getMonth() + 1
  timeWheelDay: number = INITIAL_WHEEL_TIME.getDate()
  timeWheelHour: number = INITIAL_WHEEL_TIME.getHours()
  timeWheelMinute: number = INITIAL_WHEEL_TIME.getMinutes()
  timeWheelSecond: number = INITIAL_WHEEL_TIME.getSeconds()
  timeWheelTickLabels: string[] = []
  // 每个刻度的完整数值（含非主刻度），供 Canvas 在中心附近绘制小号标签。
  timeWheelAllLabels: string[] = []
  timeWheelVisualOffset: number = 0
  timeWheelDragging: boolean = false
  timeWheelAppliedSteps: number = 0
  timeWheelTrackBaseMs: number = 0

  readonly tickSpacing: number = 42
  readonly centerTick: number = 20

  constructor() {
    this.timeWheelTrackBaseMs = Date.UTC(this.timeWheelYear, this.timeWheelMonth - 1,
      this.timeWheelDay, this.timeWheelHour, this.timeWheelMinute, this.timeWheelSecond)
    this.refreshTicks()
  }

  majorInterval(): number {
    if (this.timeWheelUnit === 'year') { return 5 }
    if (this.timeWheelUnit === 'month') { return 3 }
    return 5
  }

  isCalendar(): boolean {
    return this.timeWheelUnit === 'year' || this.timeWheelUnit === 'month' || this.timeWheelUnit === 'day'
  }

  shiftDate(local: Date, steps: number): void {
    if (this.timeWheelUnit === 'year') { local.setUTCFullYear(local.getUTCFullYear() + steps) }
    else if (this.timeWheelUnit === 'month') { local.setUTCMonth(local.getUTCMonth() + steps) }
    else if (this.timeWheelUnit === 'day') { local.setUTCDate(local.getUTCDate() + steps) }
    else if (this.timeWheelUnit === 'hour') { local.setUTCHours(local.getUTCHours() + steps) }
    else if (this.timeWheelUnit === 'minute') { local.setUTCMinutes(local.getUTCMinutes() + steps) }
    else { local.setUTCSeconds(local.getUTCSeconds() + steps) }
  }

  dateAtOffset(offset: number): Date {
    const baseMs = this.timeWheelTrackBaseMs > 0
      ? this.timeWheelTrackBaseMs
      : Date.UTC(this.timeWheelYear, this.timeWheelMonth - 1, this.timeWheelDay,
        this.timeWheelHour, this.timeWheelMinute, this.timeWheelSecond)
    const local = new Date(baseMs)
    this.shiftDate(local, offset)
    return local
  }

  dateAtFraction(baseMs: number, steps: number): Date {
    const wholeSteps = steps >= 0 ? Math.floor(steps) : Math.ceil(steps)
    const fractionalSteps = steps - wholeSteps
    const local = new Date(baseMs)
    this.shiftDate(local, wholeSteps)
    if (fractionalSteps === 0) { return local }
    const next = new Date(local.getTime())
    this.shiftDate(next, fractionalSteps > 0 ? 1 : -1)
    if (this.isCalendar()) {
      const localDateMs = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate())
      const nextDateMs = Date.UTC(next.getUTCFullYear(), next.getUTCMonth(), next.getUTCDate())
      const dayOffset = Math.round((nextDateMs - localDateMs) * Math.abs(fractionalSteps) / 86400000.0)
      local.setUTCDate(local.getUTCDate() + dayOffset)
      return local
    }
    return new Date(local.getTime() + (next.getTime() - local.getTime()) * Math.abs(fractionalSteps))
  }

  tickValue(offset: number): string {
    const local = this.dateAtOffset(offset)
    if (this.timeWheelUnit === 'year') { return local.getUTCFullYear().toString() }
    if (this.timeWheelUnit === 'month') { return (local.getUTCMonth() + 1).toString().padStart(2, '0') + '月' }
    if (this.timeWheelUnit === 'day') { return local.getUTCDate().toString().padStart(2, '0') + '日' }
    // 时分秒只显示数字：滚轮宽度固定，带单位会在部分语言/字号下撑破布局。
    if (this.timeWheelUnit === 'hour') { return local.getUTCHours().toString().padStart(2, '0') }
    if (this.timeWheelUnit === 'minute') { return local.getUTCMinutes().toString().padStart(2, '0') }
    return local.getUTCSeconds().toString().padStart(2, '0')
  }

  refreshTicks(): void {
    const labels: string[] = []
    const all: string[] = []
    const interval = this.majorInterval()
    for (let index = 0; index <= this.centerTick * 2; index++) {
      const offset = index - this.centerTick
      const value = this.tickValue(offset)
      all.push(value)
      labels.push(offset % interval === 0 ? value : '')
    }
    this.timeWheelTickLabels = labels
    this.timeWheelAllLabels = all
  }
}
