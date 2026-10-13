// 时间轮（转轴）域状态 + 纯取值计算。
//
// 只在 store 里放「数据 + 纯计算」：日期/字段取值、tick 标签生成与刻度量值。
// 交互（拖动 / 惯性 / 轨道重基准 / 引擎同步）在 TimeWheelController，视图在 TimeWheelScrubber；
// 宿主以 @State 持有本 store，视图以 @ObjectLink 订阅。
@Observed
export class TimeWheelStore {
  timeWheelUnit: string = 'hour'
  timeWheelYear: number = 2026
  timeWheelMonth: number = 8
  timeWheelDay: number = 11
  timeWheelHour: number = 20
  timeWheelMinute: number = 0
  timeWheelSecond: number = 0
  timeWheelTickLabels: string[] = []
  timeWheelVisualOffset: number = 0
  timeWheelDragging: boolean = false
  timeWheelAppliedSteps: number = 0
  timeWheelTrackBaseMs: number = 0

  readonly tickSpacing: number = 42
  readonly centerTick: number = 20

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
    if (this.timeWheelUnit === 'hour') { return local.getUTCHours().toString().padStart(2, '0') + '时' }
    if (this.timeWheelUnit === 'minute') { return local.getUTCMinutes().toString().padStart(2, '0') + '分' }
    return local.getUTCSeconds().toString().padStart(2, '0') + '秒'
  }

  tickLabel(offset: number): string {
    if (offset % this.majorInterval() !== 0) { return '' }
    return this.tickValue(offset)
  }

  refreshTicks(): void {
    const labels: string[] = []
    for (let index = 0; index <= this.centerTick * 2; index++) {
      labels.push(this.tickLabel(index - this.centerTick))
    }
    this.timeWheelTickLabels = labels
  }

  visibleTickOffset(index: number): number {
    return index - this.centerTick + this.timeWheelAppliedSteps
  }

  isVisibleMajorTick(index: number): boolean {
    return this.visibleTickOffset(index) % this.majorInterval() === 0
  }
}
