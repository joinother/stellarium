import { TimeWheelStore } from './TimeWheelStore'

// 飞轮（「抽陀螺」）参数：无自动阻尼、无时长上限，连续同向甩动逐次叠加速度；
// 反向甩动减速或反转；轻触/按住转轴即稳稳刹停。
const FLYWHEEL_VELOCITY_SCALE: number = 0.78
const FLYWHEEL_ACCUMULATE_GAIN: number = 0.92
const FLYWHEEL_MAX_VELOCITY: number = 14.0
const FLYWHEEL_START_VELOCITY: number = 0.06
const FLYWHEEL_BRAKE_VELOCITY: number = 0.04

// 时间轮只处理横向拖动。竖向滑动属于面板 Scroll（向下翻看时间设置），
// 不能在 Down 上抢走手势、暂停时间或在轻微 x 抖动时改时间。
const WHEEL_DIRECTION_SLOP: number = 6
const WHEEL_HORIZONTAL_RATIO: number = 1.2

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
  private onTick: (index: number) => void

  private lastInputMs: number = 0
  private lastTouchX: number = 0
  private lastTouchMs: number = 0
  private dragCarry: number = 0
  private touchPending: boolean = false
  private touchStartX: number = 0
  private touchStartY: number = 0
  private pendingGestureBaseMs: number = 0
  private pendingGestureTickOffset: number = 0
  private pendingDragCarry: number = 0
  private lastNativePushMs: number = 0
  private gestureBaseMs: number = 0
  private gestureSteps: number = 0
  private gestureTickOffset: number = 0
  private inertiaTimer: number = 0
  private inertiaVelocity: number = 0
  private inertiaLastMs: number = 0
  private inertiaStartedAt: number = 0
  private inertiaActive: boolean = false
  private preTouchSpinVelocity: number = 0
  private capturedSpinOnDown: boolean = false
  private lastSentLocalMs: number = Number.NaN
  private lastVisualVelocity: number = 0
  // Haptic cadence is intentionally based on drag motion, not time-unit steps:
  // hour/month dragging needs hundreds of pixels per unit, so step-based ticks
  // were effectively inaudible. The service still throttles by the user's
  // frequency setting.
  private hapticTickCounter: number = 0
  private lastDragHapticMs: number = 0
  private lastInertiaHapticMs: number = 0

  constructor(
    store: TimeWheelStore,
    onSeek: (jd: number) => void,
    onStopSpeed: () => void,
    getUtcOffsetHours: () => number,
    onTick: (index: number) => void = () => {}
  ) {
    this.store = store
    this.onSeek = onSeek
    this.onStopSpeed = onStopSpeed
    this.getUtcOffsetHours = getUtcOffsetHours
    this.onTick = onTick
  }

  // 生命周期收口：面板关闭 / 切后台 / 组件销毁时调用，确保惯性定时器不残留。
  stop(): void {
    this.stopInertia()
  }

  isInteracting(): boolean {
    return this.store.timeWheelDragging || this.inertiaActive
  }

  isSpinning(): boolean {
    return this.inertiaActive
  }

  // 轻触或起手落在正在旋转的时间轴上时，先暂存当前转速并暂停定时器：
  // 若随后抬手（轻点）则刹停；若同向快甩则把新甩速叠加到原转速上（「抽陀螺」）。
  captureSpinOnTouchDown(): boolean {
    if (!this.inertiaActive) {
      this.preTouchSpinVelocity = 0
      this.capturedSpinOnDown = false
      return false
    }
    this.preTouchSpinVelocity = this.inertiaVelocity
    this.capturedSpinOnDown = true
    this.pauseInertiaTimerOnly()
    return true
  }

  brakeFromTap(): void {
    if (!this.capturedSpinOnDown && !this.inertiaActive) { return }
    this.capturedSpinOnDown = false
    this.preTouchSpinVelocity = 0
    this.stopInertia(true)
  }

  resumeCapturedSpinIfVerticalScroll(): void {
    if (!this.capturedSpinOnDown || Math.abs(this.preTouchSpinVelocity) < FLYWHEEL_START_VELOCITY) {
      this.capturedSpinOnDown = false
      this.preTouchSpinVelocity = 0
      return
    }
    const resumeVel = this.preTouchSpinVelocity
    this.capturedSpinOnDown = false
    this.preTouchSpinVelocity = 0
    this.launchFlywheel(resumeVel)
  }

  selectUnit(unit: string): void {
    this.stopInertia(true)
    this.store.timeWheelUnit = unit
    this.store.timeWheelDragging = false
    if (this.store.isCalendar()) {
      // 选中日期（年 / 月 / 日）后立即冻结时钟走时，确保调整日期时时分秒完全静止。
      this.onStopSpeed()
    }
    this.rebaseTrack()
  }

  handleTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) { return }
    const point = points[0]
    if (event.type === TouchType.Down) {
      this.handleDown(point.x, point.y)
    } else if (event.type === TouchType.Move) {
      this.handleMove(point.x, point.y)
    } else if (event.type === TouchType.Up) {
      this.handleEnd(false)
    } else if (event.type === TouchType.Cancel) {
      this.handleEnd(true)
    }
  }

  // PanGesture 已确认横向意图后调用：直接进入拖动，不再做方向判定。
  beginPan(x: number, y: number): void {
    if (!this.capturedSpinOnDown) {
      this.preTouchSpinVelocity = this.inertiaActive ? this.inertiaVelocity : 0
    }
    this.capturedSpinOnDown = false
    this.pauseInertiaTimerOnly()
    this.touchPending = false
    this.pendingGestureBaseMs = Date.UTC(this.store.timeWheelYear, this.store.timeWheelMonth - 1,
      this.store.timeWheelDay, this.store.timeWheelHour, this.store.timeWheelMinute, this.store.timeWheelSecond)
    this.pendingGestureTickOffset = this.store.timeWheelAppliedSteps
    this.pendingDragCarry = this.store.timeWheelVisualOffset
    this.beginWheelDrag()
    this.lastTouchX = x
    this.lastTouchMs = Date.now()
  }

  updatePan(x: number): void {
    this.handleMove(x, 0)
  }

  endPan(cancelled: boolean): void {
    this.handleEnd(cancelled)
  }

  private handleDown(x: number, y: number): void {
    this.captureSpinOnTouchDown()
    // 先只记录起点，等 Move 判断方向。竖向手势必须留给面板 Scroll。
    this.touchPending = true
    this.touchStartX = x
    this.touchStartY = y
    this.lastTouchX = x
    this.lastTouchMs = Date.now()
    this.pendingGestureBaseMs = Date.UTC(this.store.timeWheelYear, this.store.timeWheelMonth - 1,
      this.store.timeWheelDay, this.store.timeWheelHour, this.store.timeWheelMinute, this.store.timeWheelSecond)
    this.pendingGestureTickOffset = this.store.timeWheelAppliedSteps
    this.pendingDragCarry = this.store.timeWheelVisualOffset
  }

  private handleMove(x: number, y: number): void {
    if (this.touchPending && !this.store.timeWheelDragging) {
      const totalDx = x - this.touchStartX
      const totalDy = y - this.touchStartY
      if (Math.abs(totalDx) < WHEEL_DIRECTION_SLOP && Math.abs(totalDy) < WHEEL_DIRECTION_SLOP) {
        return
      }
      if (Math.abs(totalDx) <= Math.abs(totalDy) * WHEEL_HORIZONTAL_RATIO) {
        // 竖向翻看：放弃时间轮手势，既不暂停时间也不改时间。
        this.touchPending = false
        this.resumeCapturedSpinIfVerticalScroll()
        return
      }
      this.touchPending = false
      this.capturedSpinOnDown = false
      this.beginWheelDrag()
      // 继续走下面的拖动分支，把本次 Move 的完整位移应用上去。
    }
    if (!this.store.timeWheelDragging) {
      return
    }
    const now = Date.now()
    const delta = x - this.lastTouchX
    const elapsedMs = Math.max(1, now - this.lastTouchMs)
    this.lastTouchX = x
    this.lastTouchMs = now
    const speed = Math.abs(delta) / elapsedMs
    const stepDelta = -delta * this.velocityMultiplier(speed) / this.store.tickSpacing
    const effectiveDelta = -stepDelta * this.store.tickSpacing
    this.dragCarry += effectiveDelta
    this.gestureSteps += stepDelta
    // Slower movement gives denser detent feedback; faster movement spreads
    // pulses out to avoid a continuous buzz and to keep the UI thread light.
    const hapticGap = speed < 0.35 ? 70 : (speed < 0.8 ? 100 : 140)
    if (delta !== 0 && now - this.lastDragHapticMs >= hapticGap) {
      this.lastDragHapticMs = now
      this.onTick(++this.hapticTickCounter)
    }
    this.store.timeWheelVisualOffset = this.dragCarry
    const instantVelocity = effectiveDelta / elapsedMs
    this.lastVisualVelocity = this.lastVisualVelocity * 0.45 + instantVelocity * 0.55
    const local = this.store.dateAtFraction(this.gestureBaseMs, this.gestureSteps)
    const sendNative = now - this.lastNativePushMs >= 16
    this.applyDate(local, false, sendNative)
    if (Math.abs(this.store.timeWheelVisualOffset) >= this.store.tickSpacing * 8) {
      this.rebaseTrackAtCenter()
    }
  }

  private handleEnd(cancelled: boolean): void {
    if (this.touchPending && !this.store.timeWheelDragging) {
      // 纯点击落在正在旋转的轴上：立刻刹停；未旋转则无副作用。
      this.touchPending = false
      this.brakeFromTap()
      return
    }
    this.touchPending = false
    this.store.timeWheelDragging = false
    if (this.gestureBaseMs > 0) {
      this.applyDate(this.store.dateAtFraction(this.gestureBaseMs, this.gestureSteps), false, true)
    }
    if (!cancelled) {
      this.startInertia()
    } else {
      this.preTouchSpinVelocity = 0
      this.stopInertia()
    }
  }

  // 横向意图确认后才真正接管：暂停时间、建立拖动基准并开启触感。
  private beginWheelDrag(): void {
    this.store.timeWheelDragging = true
    this.lastInputMs = Date.now()
    this.gestureBaseMs = this.pendingGestureBaseMs
    this.gestureSteps = 0
    this.gestureTickOffset = this.pendingGestureTickOffset
    this.dragCarry = this.pendingDragCarry
    this.lastVisualVelocity = 0
    this.hapticTickCounter = 0
    this.lastDragHapticMs = 0
    this.lastInertiaHapticMs = 0
    this.rebaseTrackAtCenter()
    this.onStopSpeed()
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

  // 面板打开前用宿主缓存的模拟 JD 立即对齐字段与刻度，避免首帧显示
  // 模块加载时的旧值、或等待 125ms 轮询后才出现刻度。
  seedFromSimulation(jd: number): void {
    this.stopInertia()
    this.store.timeWheelDragging = false
    this.store.timeWheelVisualOffset = 0
    this.store.timeWheelAppliedSteps = 0
    this.dragCarry = 0
    this.gestureTickOffset = 0
    this.gestureBaseMs = 0
    this.gestureSteps = 0
    this.lastInputMs = 0
    const local = new Date((jd + this.getUtcOffsetHours() / 24.0 - 2440587.5) * 86400000.0)
    this.store.timeWheelYear = local.getUTCFullYear()
    this.store.timeWheelMonth = local.getUTCMonth() + 1
    this.store.timeWheelDay = local.getUTCDate()
    this.store.timeWheelHour = local.getUTCHours()
    this.store.timeWheelMinute = local.getUTCMinutes()
    this.store.timeWheelSecond = local.getUTCSeconds()
    this.store.timeWheelTrackBaseMs = local.getTime()
    this.store.refreshTicks()
  }

  private applyDate(local: Date, refreshTicks: boolean, sendNative: boolean): void {
    this.lastInputMs = Date.now()
    const year = local.getUTCFullYear()
    const month = local.getUTCMonth() + 1
    const day = local.getUTCDate()
    const hour = local.getUTCHours()
    const minute = local.getUTCMinutes()
    const second = local.getUTCSeconds()
    if (this.store.timeWheelYear !== year) { this.store.timeWheelYear = year }
    if (this.store.timeWheelMonth !== month) { this.store.timeWheelMonth = month }
    if (this.store.timeWheelDay !== day) { this.store.timeWheelDay = day }
    if (this.store.timeWheelHour !== hour) { this.store.timeWheelHour = hour }
    if (this.store.timeWheelMinute !== minute) { this.store.timeWheelMinute = minute }
    if (this.store.timeWheelSecond !== second) { this.store.timeWheelSecond = second }
    if (refreshTicks) { this.store.refreshTicks() }
    if (sendNative) {
      const localMs = local.getTime()
      if (localMs !== this.lastSentLocalMs || !this.store.isCalendar()) {
        this.lastSentLocalMs = localMs
        const targetJd = localMs / 86400000.0 + 2440587.5 - this.getUtcOffsetHours() / 24.0
        this.onSeek(targetJd)
        this.lastNativePushMs = Date.now()
      }
    }
  }

  private pauseInertiaTimerOnly(): void {
    if (this.inertiaTimer !== 0) {
      clearInterval(this.inertiaTimer)
      this.inertiaTimer = 0
    }
    this.inertiaActive = false
  }

  private stopInertia(applyFinal: boolean = false): void {
    if (this.inertiaTimer !== 0) {
      clearInterval(this.inertiaTimer)
      this.inertiaTimer = 0
    }
    const shouldApply = applyFinal && this.inertiaActive && this.gestureBaseMs > 0
    this.inertiaActive = false
    this.inertiaVelocity = 0
    this.preTouchSpinVelocity = 0
    this.capturedSpinOnDown = false
    if (shouldApply) {
      this.applyDate(this.store.dateAtFraction(this.gestureBaseMs, this.gestureSteps), false, true)
    }
  }

  private startInertia(): void {
    const prevSpin = this.preTouchSpinVelocity
    this.preTouchSpinVelocity = 0
    this.capturedSpinOnDown = false
    this.pauseInertiaTimerOnly()

    const flickVelocity = this.lastVisualVelocity * FLYWHEEL_VELOCITY_SCALE
    // 若用户在松手前停住手指（慢拖/按住刹停），直接停止而不延续旧转速
    if (Math.abs(flickVelocity) < FLYWHEEL_BRAKE_VELOCITY || this.gestureBaseMs <= 0) {
      this.inertiaVelocity = 0
      return
    }

    let nextVelocity = 0
    if (prevSpin !== 0) {
      if ((flickVelocity > 0 && prevSpin > 0) || (flickVelocity < 0 && prevSpin < 0)) {
        // 同向连续甩动：像抽陀螺一样逐次叠加速度
        nextVelocity = prevSpin + flickVelocity * FLYWHEEL_ACCUMULATE_GAIN
      } else {
        // 反向甩动：抵消并可反向加速
        nextVelocity = prevSpin + flickVelocity * 1.15
      }
    } else {
      nextVelocity = flickVelocity
    }

    nextVelocity = Math.max(-FLYWHEEL_MAX_VELOCITY, Math.min(FLYWHEEL_MAX_VELOCITY, nextVelocity))
    if (Math.abs(nextVelocity) < FLYWHEEL_START_VELOCITY) {
      this.inertiaVelocity = 0
      return
    }
    this.launchFlywheel(nextVelocity)
  }

  private launchFlywheel(velocity: number): void {
    this.pauseInertiaTimerOnly()
    if (this.gestureBaseMs <= 0) {
      this.gestureBaseMs = Date.UTC(this.store.timeWheelYear, this.store.timeWheelMonth - 1,
        this.store.timeWheelDay, this.store.timeWheelHour, this.store.timeWheelMinute, this.store.timeWheelSecond)
      this.gestureSteps = 0
    }
    this.inertiaActive = true
    this.inertiaVelocity = velocity
    this.inertiaLastMs = Date.now()
    this.inertiaStartedAt = this.inertiaLastMs
    this.lastInertiaHapticMs = this.inertiaLastMs
    this.inertiaTimer = setInterval(() => {
      if (!this.inertiaActive || this.store.timeWheelDragging) {
        this.pauseInertiaTimerOnly()
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
      if (now - this.lastInertiaHapticMs >= 100) {
        this.lastInertiaHapticMs = now
        this.onTick(++this.hapticTickCounter)
      }
      const local = this.store.dateAtFraction(this.gestureBaseMs, this.gestureSteps)
      const sendNative = now - this.lastNativePushMs >= 16
      this.applyDate(local, false, sendNative)
      if (Math.abs(this.store.timeWheelVisualOffset) >= this.store.tickSpacing * 8) {
        this.rebaseTrackAtCenter()
      }
      // 无阻尼飞轮匀速持续旋转，直到用户再次拨动、点按刹停或切换单位/关闭面板。
    }, 16) as number
  }

  private velocityMultiplier(speed: number): number {
    let baseMultiplier = 1.0
    if (this.store.timeWheelUnit === 'year') { baseMultiplier = 0.55 }
    else if (this.store.timeWheelUnit === 'month') { baseMultiplier = 0.65 }
    else if (this.store.timeWheelUnit === 'day') { baseMultiplier = 0.85 }
    else if (this.store.timeWheelUnit === 'hour') { baseMultiplier = 0.85 }
    else if (this.store.timeWheelUnit === 'minute') { baseMultiplier = 0.95 }
    // 连续平滑加速曲线（取代 0.06x 极低阻尼与 2x/4x/8x 阶跃突变），保证慢拖跟手、快甩顺滑。
    const boost = 1.0 + Math.min(2.6, Math.max(0, speed - 0.35) * 1.8)
    return baseMultiplier * boost
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
    // 标签基准随轨道一起平移。旧实现只回写 appliedSteps，长距离拖动后
    // 预计算的标签（以及 Canvas）仍停在旧基准：字段已读 09:14，转轮中心
    // 却还是 09:04。
    const base = new Date(this.store.timeWheelTrackBaseMs)
    this.store.shiftDate(base, -tickShift)
    this.store.timeWheelTrackBaseMs = base.getTime()
    this.store.timeWheelVisualOffset -= tickShift * this.store.tickSpacing
    this.dragCarry = this.store.timeWheelVisualOffset
    this.store.timeWheelAppliedSteps = 0
    this.gestureTickOffset = 0
    this.store.refreshTicks()
  }
}
