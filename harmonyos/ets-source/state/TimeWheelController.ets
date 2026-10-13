import { TimeWheelStore } from './TimeWheelStore'

// 时间轮的**交互控制器**：拖动 / 惯性 / 轨道重基准 / 引擎推送。
//
// 为什么是普通类而不是 @Observed store：这里的字段是**每个触摸采样都在变**的手势草稿量
// （拖拽累计、手势步进、惯性速度…）。可观测化会让每次采样都触发通知与重渲染。
// 因此职责划分为：`TimeWheelStore`（可观测数据 + 纯计算）、本控制器（不可观测行为 + 定时器）、
// `TimeWheelScrubber`（视图）。
//
// 三个跨域依赖通过构造注入消除，控制器本身不碰 NAPI、不碰速度域：
//   ① `onSeek(jd)`          —— 引擎推送 `setTimeToJD`（宿主调用命令桥）
//   ② `onStopSpeed()`       —— 拖动即暂停（写速度域，宿主负责）
//   ③ `getUtcOffsetHours()` —— UTC 偏移随地点变化，仍由宿主持有
export class TimeWheelController {
  private store: TimeWheelStore
  private onSeek: (jd: number) => void
  private onStopSpeed: () => void
  private getUtcOffsetHours: () => number

  private lastInputMs: number = 0
  private lastTouchX: number = 0
  private lastTouchMs: number = 0
  private dragCarry: number = 0
  private lastNativePushMs: number = 0
  private gestureBaseMs: number = 0
  private gestureSteps: number = 0
  private gestureTickOffset: number = 0
  private inertiaTimer: number = 0
  private inertiaVelocity: number = 0
  private inertiaLastMs: number = 0
  private inertiaStartedAt: number = 0
  private inertiaActive: boolean = false
  private lastVisualVelocity: number = 0

  constructor(
    store: TimeWheelStore,
    onSeek: (jd: number) => void,
    onStopSpeed: () => void,
    getUtcOffsetHours: () => number
  ) {
    this.store = store
    this.onSeek = onSeek
    this.onStopSpeed = onStopSpeed
    this.getUtcOffsetHours = getUtcOffsetHours
  }

  // 生命周期收口：面板关闭 / 切后台 / 组件销毁时调用，确保惯性定时器不残留。
  stop(): void {
    this.stopInertia()
  }

  selectUnit(unit: string): void {
    this.store.timeWheelUnit = unit
    this.store.timeWheelDragging = false
    this.rebaseTrack()
  }

  handleTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) { return }
    const point = points[0]
    if (event.type === TouchType.Down) {
      this.stopInertia()
      this.store.timeWheelDragging = true
      this.lastTouchX = point.x
      this.lastTouchMs = Date.now()
      this.lastInputMs = Date.now()
      this.gestureBaseMs = Date.UTC(this.store.timeWheelYear, this.store.timeWheelMonth - 1,
        this.store.timeWheelDay, this.store.timeWheelHour, this.store.timeWheelMinute, this.store.timeWheelSecond)
      this.gestureSteps = 0
      this.gestureTickOffset = this.store.timeWheelAppliedSteps
      this.dragCarry = this.store.timeWheelVisualOffset
      this.lastVisualVelocity = 0
      this.rebaseTrackAtCenter()
      this.onStopSpeed()
      return
    }
    if (event.type === TouchType.Move && this.store.timeWheelDragging) {
      const now = Date.now()
      const delta = point.x - this.lastTouchX
      const elapsedMs = Math.max(1, now - this.lastTouchMs)
      this.lastTouchX = point.x
      this.lastTouchMs = now
      const speed = Math.abs(delta) / elapsedMs
      const stepDelta = -delta * this.velocityMultiplier(speed) / this.store.tickSpacing
      const effectiveDelta = -stepDelta * this.store.tickSpacing
      this.dragCarry += effectiveDelta
      this.gestureSteps += stepDelta
      this.store.timeWheelVisualOffset = this.dragCarry
      this.lastVisualVelocity = effectiveDelta / elapsedMs
      const local = this.store.dateAtFraction(this.gestureBaseMs, this.gestureSteps)
      const sendNative = now - this.lastNativePushMs >= 64
      this.applyDate(local, false, sendNative)
      if (Math.abs(this.store.timeWheelVisualOffset) >= this.store.tickSpacing * 8) {
        this.rebaseTrackAtCenter()
      }
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.store.timeWheelDragging = false
      if (this.gestureBaseMs > 0) {
        this.applyDate(this.store.dateAtFraction(this.gestureBaseMs, this.gestureSteps), false, true)
      }
      if (event.type === TouchType.Up) {
        this.startInertia()
      } else {
        this.stopInertia()
      }
    }
  }

  syncFromSimulation(jd: number): void {
    // ArkUI may emit Begin without a matching End while the panel is built.
    // Guard only a short interval after actual user input so the display never
    // becomes permanently detached from the simulated clock.
    if (this.store.timeWheelDragging || this.inertiaActive || Date.now() - this.lastInputMs < 800) { return }
    const local = new Date((jd + this.getUtcOffsetHours() / 24.0 - 2440587.5) * 86400000.0)
    this.store.timeWheelYear = local.getUTCFullYear()
    this.store.timeWheelMonth = local.getUTCMonth() + 1
    this.store.timeWheelDay = local.getUTCDate()
    this.store.timeWheelHour = local.getUTCHours()
    this.store.timeWheelMinute = local.getUTCMinutes()
    this.store.timeWheelSecond = local.getUTCSeconds()
    if (Math.abs(this.store.timeWheelVisualOffset) < 0.1) {
      this.store.timeWheelTrackBaseMs = local.getTime()
      this.store.refreshTicks()
    }
  }

  private applyDate(local: Date, refreshTicks: boolean, sendNative: boolean): void {
    this.lastInputMs = Date.now()
    this.store.timeWheelYear = local.getUTCFullYear()
    this.store.timeWheelMonth = local.getUTCMonth() + 1
    this.store.timeWheelDay = local.getUTCDate()
    this.store.timeWheelHour = local.getUTCHours()
    this.store.timeWheelMinute = local.getUTCMinutes()
    this.store.timeWheelSecond = local.getUTCSeconds()
    if (refreshTicks) { this.store.refreshTicks() }
    if (sendNative) {
      const targetJd = local.getTime() / 86400000.0 + 2440587.5 - this.getUtcOffsetHours() / 24.0
      this.onSeek(targetJd)
      this.lastNativePushMs = Date.now()
    }
  }

  private stopInertia(applyFinal: boolean = false): void {
    if (this.inertiaTimer !== 0) {
      clearInterval(this.inertiaTimer)
      this.inertiaTimer = 0
    }
    const shouldApply = applyFinal && this.inertiaActive && this.gestureBaseMs > 0
    this.inertiaActive = false
    this.inertiaVelocity = 0
    if (shouldApply) {
      this.applyDate(this.store.dateAtFraction(this.gestureBaseMs, this.gestureSteps), false, true)
    }
  }

  private startInertia(): void {
    this.stopInertia()
    const rawVelocity = this.lastVisualVelocity * 0.58
    const initialVelocity = Math.max(-2.8, Math.min(2.8, rawVelocity))
    if (Math.abs(initialVelocity) < 0.06 || this.gestureBaseMs <= 0) { return }
    this.inertiaActive = true
    this.inertiaVelocity = initialVelocity
    this.inertiaLastMs = Date.now()
    this.inertiaStartedAt = this.inertiaLastMs
    this.inertiaTimer = setInterval(() => {
      if (!this.inertiaActive || this.store.timeWheelDragging) {
        this.stopInertia()
        return
      }
      const now = Date.now()
      const elapsed = Math.max(1, now - this.inertiaLastMs)
      this.inertiaLastMs = now
      const frameMs = Math.min(34, elapsed)
      const visualDelta = this.inertiaVelocity * frameMs
      this.store.timeWheelVisualOffset += visualDelta
      this.dragCarry = this.store.timeWheelVisualOffset
      this.gestureSteps -= visualDelta / this.store.tickSpacing
      const local = this.store.dateAtFraction(this.gestureBaseMs, this.gestureSteps)
      const sendNative = now - this.lastNativePushMs >= 64
      this.applyDate(local, false, sendNative)
      if (Math.abs(this.store.timeWheelVisualOffset) >= this.store.tickSpacing * 8) {
        this.rebaseTrackAtCenter()
      }
      this.inertiaVelocity *= Math.pow(0.90, frameMs / 16.0)
      if (now - this.inertiaStartedAt >= 900 || Math.abs(this.inertiaVelocity) < 0.025) {
        this.stopInertia(true)
      }
    }, 16) as number
  }

  private velocityMultiplier(speed: number): number {
    let baseMultiplier = 1.0
    if (this.store.timeWheelUnit === 'year') { baseMultiplier = 0.07 }
    else if (this.store.timeWheelUnit === 'month') { baseMultiplier = 0.08 }
    else if (this.store.timeWheelUnit === 'day') { baseMultiplier = 0.2 }
    else if (this.store.timeWheelUnit === 'hour') { baseMultiplier = 0.06 }
    else if (this.store.timeWheelUnit === 'minute') { baseMultiplier = 0.25 }
    if (speed < 0.35) { return baseMultiplier }
    if (speed < 0.8) { return baseMultiplier * 2.0 }
    if (speed < 1.4) { return baseMultiplier * 4.0 }
    return baseMultiplier * 8.0
  }

  private rebaseTrack(): void {
    this.dragCarry = 0
    this.store.timeWheelAppliedSteps = 0
    this.gestureTickOffset = 0
    this.store.timeWheelVisualOffset = 0
    this.store.timeWheelTrackBaseMs = Date.UTC(this.store.timeWheelYear, this.store.timeWheelMonth - 1,
      this.store.timeWheelDay, this.store.timeWheelHour, this.store.timeWheelMinute, this.store.timeWheelSecond)
    this.store.refreshTicks()
  }

  private rebaseTrackAtCenter(): void {
    const tickShift = Math.round(this.store.timeWheelVisualOffset / this.store.tickSpacing)
    if (tickShift === 0) { return }
    this.store.timeWheelVisualOffset -= tickShift * this.store.tickSpacing
    this.dragCarry = this.store.timeWheelVisualOffset
    this.store.timeWheelAppliedSteps -= tickShift
    this.gestureTickOffset -= tickShift
  }
}
