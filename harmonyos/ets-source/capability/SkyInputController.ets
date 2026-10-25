// 天空输入控制器。
//
// 统一处理天空区域的鼠标 / 滚轮轴 / 点按序列 / 惯性，以及触屏主路径
// （dragFollowAlpha / emitFluidDrag / handleSkyTouch）。
//
// 可观测状态（触摸反馈点 skyTouchFeedback / skyTouchX/Y 等）与跨 handler 共用的手势归属标志
// （touchStartedOnUi / skyTouchActive / skyDragging / dockTouchActive）仍是宿主裸 @State / 私有字段，
// 由 build() 与 handleOverlayTouch / handleDockTouch / 详情定时器消费、控制器只经 hooks 读写；
// 控制器内保留纯逐帧/草稿字段（触摸采样 / 捏合 / 滤波），不入被观察 store。
//
// 不 import NAPI/UI（仅 ArkUI 事件类型与纯几何/数学 derive 模块）：桥 fire（dragView / zoomBy /
// panBy / beginSkyGesture / endPinch / startPanInertia / stopPanInertia / setActionChecked）经 CommandPort；
// 热路径 isUiPoint / skyZoomButtonAt / dockActionAt 与全部宿主保留动作（路由 setPanel/closePanel、
// zoomStep / moveToSelectedObject / 选中入口 / 详情刷新收放 / Dock 动作 / 陀螺退出 / 音乐开关 /
// 面板拖动落盘等）一律经 SkyInputHostHooks 具名回注。
import hilog from '@ohos.hilog'
import { CommandPort } from '../bridge/CommandPort'
import { NightModeStore } from '../state/NightModeStore'
import { ShellAction } from '../pages/StellariumTypes'
import { clamp, distance } from '../common/derive/astro'
import { touchWindowX, touchWindowY, panelTop, panelLeft, panelRight, isDockPoint, compactTopQuickY } from '../common/derive/geometry'

// 宿主 → 控制器回注。第一项 isUiPoint 属热路径，宿主保留实现。
export interface SkyInputHostHooks {
  isUiPoint(x: number, y: number): boolean
  flashHint(text: string): void
  skyWidth(): number
  skyHeight(): number
  navigationMouseEnabled(): boolean
  navigationMouseZoomEnabled(): boolean
  gyroscopeEnabled(): boolean
  stopGyroscope(updateStatus: boolean): void
  angleMeasureEnabled(): boolean
  measureAngleAt(x: number, y: number): void
  requestSkySelection(x: number, y: number): void
  clearSkySelectionFromDoubleTap(x: number, y: number): void
  zoomStep(factor: number): void
  setPanel(panel: string): void
  closePanel(): void
  moveToSelectedObject(): void
  centerSelectedObjectFromKeyboard(): void
  persistNightMode(): void
  modelImmersive(): boolean
  setModelImmersive(value: boolean): void
  // ── 触屏主路径（handleSkyTouch / emitFluidDrag）依赖的宿主状态与动作 ──
  // 布局 / 面板几何（宿主 @State，控制器只读）
  isExpandedLayout(): boolean
  isFoldHoverLayout(): boolean
  isFoldTabletLayout(): boolean
  panelVisible(): boolean
  panelWidth(): number
  panelOffsetX(): number
  panelOffsetY(): number
  edgeMargin(): number
  fovSliderValue(): number
  setFovSliderValue(value: number): void
  polarScopeVisible(): boolean
  compactDockWidthPercent(): number
  dockTop(): number
  dockHeight(): number
  // 文本输入框聚焦时，天空键盘处理器必须让位给输入法。
  keyboardTextInputFocused(): boolean
  compactTopQuickX(): number
  isCompactTopQuickPoint(x: number, y: number): boolean
  lastInfoWinCloseMs(): number
  // 手势归属标志（宿主裸字段，跨 handleOverlayTouch / Dock / 详情定时器共用）
  touchStartedOnUi(): boolean
  setTouchStartedOnUi(value: boolean): void
  skyTouchActive(): boolean
  setSkyTouchActive(value: boolean): void
  setSkyDragging(value: boolean): void
  dockTouchActive(): boolean
  setDockTouchActive(value: boolean): void
  // 触摸反馈点（保留 @State，宿主 build() 消费，控制器只写）
  skyTouchFeedback(): boolean
  setSkyTouchFeedback(value: boolean): void
  setSkyTouchPoint(x: number, y: number): void
  setSkyTouchPoint2(x: number, y: number): void
  skyTouchX2(): number
  skyTouchY2(): number
  setSkyTouchFeedbackMulti(value: boolean): void
  setCurrentFovText(text: string): void
  setPanelOffset(offsetX: number, offsetY: number): void
  // 宿主保留动作（选中 UI / 详情刷新 / 缩放按钮命中 / 面板拖动收尾等）
  cancelSelectedObjectUiChange(): void
  pauseDetailRefreshForSkyDrag(): void
  resumeDetailRefreshAfterSkyDrag(): void
  scheduleSelectedObjectForUiChange(delay: number): void
  scheduleSkyTextureStatusCheck(): void
  scheduleRecordingViewCheckpoint(delay: number): void
  resetPanelIdle(): void
  toggleMusic(): void
  musicHintText(): string
  toggleGyroscope(value: boolean): void
  skyZoomButtonAt(x: number, y: number): string
  dockActionAt(x: number, y: number): ShellAction | null
  activateDockAction(item: ShellAction): void
  requestFieldOfView(onResult: (fov: number) => void): void
}

// 手势归属：Down 时由几何一次判定，Up/Cancel 时复位。取代会跨手势残留的
// touchStartedOnUi 全局标志与 `!skyTouchActive` 网关——归属不再依赖“上一手势是否漏清理”。
enum SkyGestureOwner { None, Sky, Ui, PanelDrag }

export class SkyInputController {
  private commandPort: CommandPort
  private hooks: SkyInputHostHooks

  // ── 逐帧/草稿字段（留控制器，不入被观察 store）──
  private skyInertiaTimer: number = 0
  private lastSkyTapAt: number = 0
  private lastSkyTapX: number = 0
  private lastSkyTapY: number = 0

  // ── 触屏主路径（handleSkyTouch / emitFluidDrag）的草稿/逐帧字段 ──
  // 5 个共享字段已收归本类私有。
  private nativeSkyInertiaActive: boolean = false
  private dragVelocityX: number = 0
  private dragVelocityY: number = 0
  private dragVelocitySampleValid: boolean = false
  private pinchActive: boolean = false
  // 本次手势归属：Down 时一次判定，Up/Cancel 复位。
  private gestureOwner: SkyGestureOwner = SkyGestureOwner.None
  // 触摸/拖拽/捏合草稿。
  private touchStartX: number = 0
  private touchStartY: number = 0
  private touchLastX: number = 0
  private touchLastY: number = 0
  private touchMoved: boolean = false
  private pinchStartDistance: number = 0
  private pinchLastScale: number = 1
  private pinchCenterX: number = 0
  private pinchCenterY: number = 0
  private pinchStartFov: number = 60
  private pinchLastNativePushMs: number = 0
  private pinchNativePushPending: boolean = false
  /** 缩放 FOV 胶囊提示的节流时间戳 */
  private lastFovHintMs: number = 0
  private nativeDragActive: boolean = false
  private lastDragCommandMs: number = 0
  private dragFilteredX: number = 0
  private dragFilteredY: number = 0
  private dragLastRawX: number = 0
  private dragLastRawY: number = 0
  private dragLastSampleMs: number = 0
  private dragLogCount: number = 0
  // 面板标题栏拖动（仅 handleSkyTouch 使用；panelOffsetX/Y 仍是宿主 @State，经 hooks 读写）
  private panelDragging: boolean = false
  private panelDragStartX: number = 0
  private panelDragStartY: number = 0
  private panelDragStartOffsetX: number = 0
  private panelDragStartOffsetY: number = 0

  private mouseSkyPressed: boolean = false
  private mouseSkyMoved: boolean = false
  private mouseSkyStartX: number = 0
  private mouseSkyStartY: number = 0
  private mouseSkyLastX: number = 0
  private mouseSkyLastY: number = 0
  private mouseSkyLastSampleMs: number = 0
  private lastPointerPositionMs: number = 0
  private axisOwner: SkyGestureOwner = SkyGestureOwner.None
  private axisPinchActive: boolean = false
  private axisChanged: boolean = false
  private axisPinchLastScale: number = 1
  private axisBoundaryLogCount: number = 0

  constructor(commandPort: CommandPort, _nightModeStore: NightModeStore, hooks: SkyInputHostHooks) {
    this.commandPort = commandPort
    this.hooks = hooks
  }

  // ── 宿主生命周期收口 ──
  // 唯一的定时器句柄 skyInertiaTimer 仅在 stopSkyInertia() 内被 clearInterval；
  stop(): void {
    this.finishSkyAxis(true)
    this.finishSkyMouse(true)
    this.stopSkyInertia()
  }

  resetSkyTapSequence(): void {
    this.lastSkyTapAt = 0
  }

  private isSkyDoubleTap(x: number, y: number): boolean {
    const now = Date.now()
    const tapInterval = this.lastSkyTapAt > 0 ? now - this.lastSkyTapAt : 0
    const withinTime = this.lastSkyTapAt > 0 && tapInterval <= 800
    const withinDistance = distance(x, y, this.lastSkyTapX, this.lastSkyTapY) <= 28
    if (this.lastSkyTapAt > 0) {
      hilog.info(0x0000, 'StellariumArkUI', 'sky tap interval=' + tapInterval.toString() +
        'ms distance=' + distance(x, y, this.lastSkyTapX, this.lastSkyTapY).toFixed(1) +
        ' double=' + (withinTime && withinDistance).toString())
    }
    if (withinTime && withinDistance) {
      this.resetSkyTapSequence()
      return true
    }
    this.lastSkyTapAt = now
    this.lastSkyTapX = x
    this.lastSkyTapY = y
    return false
  }

  handleSkyTap(x: number, y: number): void {
    if (this.hooks.angleMeasureEnabled()) {
      this.hooks.measureAngleAt(x, y)
      return
    }
    if (this.isSkyDoubleTap(x, y)) {
      this.hooks.clearSkySelectionFromDoubleTap(x, y)
      return
    }
    this.hooks.requestSkySelection(x, y)
  }

  handleSkyMouse(event: MouseEvent): void {
    if (event.action === MouseAction.CANCEL) {
      this.finishSkyMouse(true)
      return
    }
    const x = event.x
    const y = event.y
    if (!Number.isFinite(x) || !Number.isFinite(y)) { return }
    if (event.action === MouseAction.Move && !this.hooks.isUiPoint(x, y)) {
      const now = Date.now()
      if (now - this.lastPointerPositionMs >= 32) {
        this.lastPointerPositionMs = now
        this.commandPort.fire('setPointerPosition', Math.round(x).toString() + '|' + Math.round(y).toString())
      }
    }
    if (!this.hooks.navigationMouseEnabled()) {
      this.finishSkyMouse(true)
      return
    }
    if (event.action === MouseAction.Press && event.button === MouseButton.Left) {
      this.finishSkyAxis(true)
      this.finishSkyMouse(true)
      this.mouseSkyPressed = !this.hooks.isUiPoint(x, y)
      if (!this.mouseSkyPressed) { this.resetSkyTapSequence() }
      this.mouseSkyMoved = false
      this.mouseSkyStartX = x
      this.mouseSkyStartY = y
      this.mouseSkyLastX = x
      this.mouseSkyLastY = y
      this.mouseSkyLastSampleMs = Date.now()
      this.dragVelocitySampleValid = false
      if (this.mouseSkyPressed) {
        this.stopSkyInertia()
        this.hooks.cancelSelectedObjectUiChange()
        this.commandPort.fire('beginSkyGesture')
        this.hooks.pauseDetailRefreshForSkyDrag()
      }
      return
    }
    if (event.action === MouseAction.Move && this.mouseSkyPressed) {
      if (event.pressedButtons !== undefined && event.pressedButtons.indexOf(MouseButton.Left) < 0) {
        this.finishSkyMouse(true)
        return
      }
      const moveDistance = distance(x, y, this.mouseSkyStartX, this.mouseSkyStartY)
      if (moveDistance > 3) {
        this.resetSkyTapSequence()
        if (!this.mouseSkyMoved && this.hooks.gyroscopeEnabled()) {
          this.hooks.stopGyroscope(true)
          this.hooks.flashHint('已退出陀螺仪')
        }
        this.mouseSkyMoved = true
        const now = Date.now()
        const dt = Math.max(1, now - this.mouseSkyLastSampleMs)
        const vx = (x - this.mouseSkyLastX) / dt
        const vy = (y - this.mouseSkyLastY) / dt
        this.dragVelocityX = this.dragVelocityX * 0.35 + vx * 0.65
        this.dragVelocityY = this.dragVelocityY * 0.35 + vy * 0.65
        this.dragVelocitySampleValid = dt >= 8 && dt <= 220
        this.commandPort.fire('dragView', Math.round(this.mouseSkyLastX).toString() + '|' +
          Math.round(this.mouseSkyLastY).toString() + '|' + Math.round(x).toString() + '|' + Math.round(y).toString())
        this.mouseSkyLastX = x
        this.mouseSkyLastY = y
        this.mouseSkyLastSampleMs = now
      }
      return
    }
    if (event.action === MouseAction.Release && event.button === MouseButton.Left && this.mouseSkyPressed) {
      if (!this.mouseSkyMoved && !this.hooks.isUiPoint(x, y)) {
        this.handleSkyTap(x, y)
      } else if (this.mouseSkyMoved) {
        if (Date.now() - this.mouseSkyLastSampleMs > 90) {
          this.dragVelocityX *= 0.35
          this.dragVelocityY *= 0.35
        }
        this.startSkyInertia()
      }
      this.finishSkyMouse(false)
    }
  }

  private finishSkyMouse(cancelled: boolean): void {
    if (!this.mouseSkyPressed) { return }
    this.mouseSkyPressed = false
    if (cancelled) {
      this.stopSkyInertia()
      this.resetSkyTapSequence()
    } else if (this.mouseSkyMoved) {
      this.hooks.scheduleRecordingViewCheckpoint(this.nativeSkyInertiaActive ? 1100 : 180)
    }
    this.mouseSkyMoved = false
    this.hooks.resumeDetailRefreshAfterSkyDrag()
  }

  private finishSkyAxis(cancelled: boolean): void {
    if (this.axisPinchActive) {
      this.commandPort.fire('endPinch')
      this.hooks.scheduleSkyTextureStatusCheck()
      this.hooks.requestFieldOfView((fov: number): void => {
        this.hooks.setFovSliderValue(fov)
        this.hooks.setCurrentFovText(fov.toFixed(1) + '°')
      })
    }
    if (this.axisOwner === SkyGestureOwner.Sky) {
      this.hooks.resumeDetailRefreshAfterSkyDrag()
      if (!cancelled && this.axisChanged) { this.hooks.scheduleRecordingViewCheckpoint(180) }
    }
    this.axisOwner = SkyGestureOwner.None
    this.axisPinchActive = false
    this.axisPinchLastScale = 1
    this.axisChanged = false
  }

  private skyAxisPinchScale(event: AxisEvent): number {
    let scale = event.axisPinch ?? 0
    if (!Number.isFinite(scale) || scale <= 0) {
      try { scale = event.getPinchAxisScaleValue() } catch (_) { scale = 0 }
    }
    return Number.isFinite(scale) && scale > 0 ? scale : 0
  }

  handleSkyAxis(event: AxisEvent): void {
    if (this.axisBoundaryLogCount < 32 &&
      (event.action === AxisAction.BEGIN || event.action === AxisAction.END || event.action === AxisAction.CANCEL)) {
      this.axisBoundaryLogCount += 1
      hilog.info(0x0000, 'StellariumArkUI',
        '[SKY_AXIS] sourceTool=%{public}d action=%{public}d pinch=%{public}s horizontal=%{public}s vertical=%{public}s x=%{public}s y=%{public}s owner=%{public}d ui=%{public}s',
        event.sourceTool, event.action, this.skyAxisPinchScale(event).toString(),
        event.getHorizontalAxisValue().toString(), event.getVerticalAxisValue().toString(),
        event.x.toString(), event.y.toString(), this.axisOwner, this.hooks.isUiPoint(event.x, event.y).toString())
    }
    if (event.action === AxisAction.CANCEL) {
      this.finishSkyAxis(true)
      return
    }
    const ending = event.action === AxisAction.END
    if (!ending && event.action !== AxisAction.BEGIN && event.action !== AxisAction.UPDATE) { return }
    if (event.action === AxisAction.BEGIN) { this.finishSkyAxis(true) }
    const x = event.x
    const y = event.y
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      if (ending) { this.finishSkyAxis(false) }
      return
    }
    const pinchScale = this.skyAxisPinchScale(event)
    const horizontal = event.getHorizontalAxisValue()
    const vertical = event.getVerticalAxisValue()
    const wheel = event.sourceTool === SourceTool.MOUSE ||
      (event.sourceTool === SourceTool.Unknown && Number.isFinite(event.scrollStep ?? 0) && (event.scrollStep ?? 0) > 0)
    if (wheel && pinchScale === 0 && !this.axisPinchActive) {
      if (ending) { this.finishSkyAxis(false); return }
      if (this.hooks.navigationMouseZoomEnabled() && !this.hooks.isUiPoint(x, y) &&
        Number.isFinite(vertical) && Math.abs(vertical) > 0.001) {
        this.stopSkyInertia()
        this.resetSkyTapSequence()
        this.hooks.cancelSelectedObjectUiChange()
        this.hooks.zoomStep(vertical > 0 ? 1.12 : 0.89)
      }
      return
    }
    if (event.sourceTool !== SourceTool.TOUCHPAD && event.sourceTool !== SourceTool.Unknown && !wheel) { return }
    if (this.axisOwner === SkyGestureOwner.None) {
      if (ending) { return }
      const disabled = !this.hooks.navigationMouseEnabled() && !this.hooks.navigationMouseZoomEnabled()
      this.axisOwner = disabled || this.hooks.isUiPoint(x, y) ? SkyGestureOwner.Ui : SkyGestureOwner.Sky
      if (this.axisOwner === SkyGestureOwner.Sky) {
        this.finishSkyMouse(true)
        this.stopSkyInertia()
        this.resetSkyTapSequence()
        this.hooks.cancelSelectedObjectUiChange()
        this.commandPort.fire('beginSkyGesture')
        this.hooks.pauseDetailRefreshForSkyDrag()
      }
    }
    if (this.axisOwner === SkyGestureOwner.Sky) {
      const dimensions = Math.max(1, Math.round(this.hooks.skyWidth())).toString() + '|' +
        Math.max(1, Math.round(this.hooks.skyHeight())).toString()
      if (pinchScale > 0 && this.hooks.navigationMouseZoomEnabled()) {
        const anchor = '|' + x.toFixed(2) + '|' + y.toFixed(2) + '|' + dimensions
        if (!this.axisPinchActive) {
          this.commandPort.fire('zoomBy', '1|1' + anchor)
          this.axisPinchActive = true
        }
        if (pinchScale !== this.axisPinchLastScale) {
          this.commandPort.fire('zoomBy', pinchScale.toString() + '|0' + anchor)
          this.axisPinchLastScale = pinchScale
          this.axisChanged = true
        }
      } else if (pinchScale === 0 && !this.axisPinchActive && this.hooks.navigationMouseEnabled() &&
        Number.isFinite(horizontal) && Number.isFinite(vertical) &&
        (Math.abs(horizontal) > 0.001 || Math.abs(vertical) > 0.001)) {
        if (this.hooks.gyroscopeEnabled()) {
          this.hooks.stopGyroscope(true)
          this.hooks.flashHint('已退出陀螺仪')
        }
        this.commandPort.fire('panBy', (-horizontal).toFixed(2) + '|' + (-vertical).toFixed(2) + '|' + dimensions)
        this.axisChanged = true
      }
    }
    if (ending) { this.finishSkyAxis(false) }
  }


  // The floating panel sits above the sky touch surface.  Keep its gestures
  // owned by ArkUI so a Slider/Scroll drag can never become a sky pan.
  stopSkyInertia(resetVelocity: boolean = true): void {
    if (this.skyInertiaTimer !== 0) {
      clearInterval(this.skyInertiaTimer)
      this.skyInertiaTimer = 0
    }
    if (this.nativeSkyInertiaActive) {
      this.commandPort.fire('stopPanInertia', '')
      this.nativeSkyInertiaActive = false
    }
    if (resetVelocity) {
      this.dragVelocityX = 0
      this.dragVelocityY = 0
    }
  }

  startSkyInertia(): void {
    // Do not discard the velocity sampled from the gesture that just ended.
    this.stopSkyInertia(false)
    const initialSpeed = Math.sqrt(this.dragVelocityX * this.dragVelocityX + this.dragVelocityY * this.dragVelocityY)
    if (initialSpeed < 0.05 || !this.dragVelocitySampleValid || this.pinchActive) {
      return
    }
    this.nativeSkyInertiaActive = true
    this.commandPort.fire('startPanInertia',
      this.dragVelocityX.toFixed(4) + '|' + this.dragVelocityY.toFixed(4))
  }

  // ── 触屏主路径（dragFollowAlpha / emitFluidDrag / handleSkyTouch）──
  // 宿主布局/几何/store 读数经 hooks 取，宿主保留动作经 hooks 调。

  private dragFollowAlpha(dtMs: number): number {
    // Keep only a light stabilizer. The previous low-pass values made the
    // camera visibly trail behind the finger, especially beside an open menu.
    const base = this.hooks.isFoldTabletLayout() ? 0.96 : (this.hooks.isExpandedLayout() ? 0.97 : 0.94)
    return clamp(1 - Math.pow(1 - base, Math.max(1, dtMs) / 16.67), 0.88, 0.995)
  }

  private emitFluidDrag(targetX: number, targetY: number, now: number, sampleVelocity: boolean = true): void {
    const dt = this.dragLastSampleMs > 0 ? Math.max(1, now - this.dragLastSampleMs) : 16
    const rawDx = targetX - this.dragLastRawX
    const rawDy = targetY - this.dragLastRawY
    // Physical Pads have a large, high-density canvas. A small gain keeps the
    // sky responsive without changing the geometry of the native renderer.
    const gain = this.hooks.isExpandedLayout() ? 1.35 : (this.hooks.isFoldHoverLayout() ? 1.34 : 1.36)
    if (sampleVelocity && this.dragLastSampleMs > 0 && dt >= 8 && dt <= 220) {
      const vx = rawDx * gain / dt
      const vy = rawDy * gain / dt
      this.dragVelocityX = this.dragVelocityX * 0.35 + vx * 0.65
      this.dragVelocityY = this.dragVelocityY * 0.35 + vy * 0.65
      this.dragVelocitySampleValid = true
    }
    this.dragLastRawX = targetX
    this.dragLastRawY = targetY
    this.dragLastSampleMs = now

    const alpha = this.dragFollowAlpha(dt)
    const desiredX = this.dragFilteredX + rawDx * gain
    const desiredY = this.dragFilteredY + rawDy * gain
    const nextX = this.dragFilteredX + (desiredX - this.dragFilteredX) * alpha
    const nextY = this.dragFilteredY + (desiredY - this.dragFilteredY) * alpha
    if (Math.abs(nextX - this.dragFilteredX) < 0.25 && Math.abs(nextY - this.dragFilteredY) < 0.25) {
      return
    }
    this.commandPort.fire('dragView',
      Math.round(this.dragFilteredX).toString() + '|' +
      Math.round(this.dragFilteredY).toString() + '|' +
      Math.round(nextX).toString() + '|' +
      Math.round(nextY).toString())
    this.dragFilteredX = nextX
    this.dragFilteredY = nextY
    this.touchLastX = nextX
    this.touchLastY = nextY
  }

  handleSkyTouch(event: TouchEvent): void {
    if (event.source === SourceType.Mouse) { return }
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) {
      return
    }

    if (event.type === TouchType.Down) {
      this.finishSkyAxis(true)
      this.finishSkyMouse(true)
      this.stopSkyInertia()
      const allowTouchFeedback = !this.hooks.panelVisible()
      const downX = touchWindowX(points[0])
      const downY = touchWindowY(points[0])
      // Panel header drag detection (before isUiPoint sidebar check).
      // Panels are bottom-anchored on tablet, so header drag only exists in compact layouts.
      if (this.hooks.panelVisible() && !this.hooks.isExpandedLayout()) {
        const pl = panelLeft(this.hooks.isExpandedLayout(), this.hooks.skyWidth(), this.hooks.panelWidth(), this.hooks.panelOffsetX(), this.hooks.edgeMargin())
        const pr = panelRight(this.hooks.isExpandedLayout(), this.hooks.skyWidth(), this.hooks.panelWidth(), this.hooks.panelOffsetX(), this.hooks.edgeMargin())
        const pt = panelTop(this.hooks.edgeMargin(), this.hooks.panelOffsetY())
        if (downX >= pl && downX <= pr && downY >= pt && downY <= pt + 48) {
          this.gestureOwner = SkyGestureOwner.PanelDrag
          this.panelDragging = true
          this.panelDragStartX = downX
          this.panelDragStartY = downY
          this.panelDragStartOffsetX = this.hooks.panelOffsetX()
          this.panelDragStartOffsetY = this.hooks.panelOffsetY()
          return
        }
      }
      // 左侧非手势缩放按钮（+放大 / −缩小）：与右上角快捷区同理，XComponent 吞掉
      // ArkUI onClick，必须在 Down 上按坐标分派，否则点击会穿到星图变成 selectAt。
      const zoomHit = this.hooks.skyZoomButtonAt(downX, downY)
      if (zoomHit.length > 0) {
        this.resetSkyTapSequence()
        this.gestureOwner = SkyGestureOwner.None
        this.hooks.setTouchStartedOnUi(true)
        this.hooks.setSkyTouchFeedback(false)
        this.hooks.setSkyTouchActive(false)
        if (zoomHit === 'in') {
          hilog.info(0x0000, 'StellariumArkUI', '[DIAG] sky zoom in via handleSkyTouch')
          this.hooks.zoomStep(0.8)
        } else {
          hilog.info(0x0000, 'StellariumArkUI', '[DIAG] sky zoom out via handleSkyTouch')
          this.hooks.zoomStep(1.25)
        }
        return
      }
      if (isDockPoint(downX, downY, this.hooks.polarScopeVisible(), this.hooks.isExpandedLayout(), this.hooks.skyWidth(), this.hooks.skyHeight(), this.hooks.panelVisible(), this.hooks.panelWidth(), this.hooks.panelOffsetX(), this.hooks.edgeMargin(), this.hooks.compactDockWidthPercent(), this.hooks.dockTop(), this.hooks.dockHeight())) {
        this.resetSkyTapSequence()
        this.gestureOwner = SkyGestureOwner.None
        this.hooks.setDockTouchActive(true)
        this.hooks.setTouchStartedOnUi(true)
        this.hooks.setSkyTouchFeedback(false)
        this.hooks.setSkyTouchActive(false)
        return
      }
      if (this.hooks.isUiPoint(downX, downY)) {
        this.resetSkyTapSequence()
        this.gestureOwner = SkyGestureOwner.Ui
        this.hooks.setTouchStartedOnUi(true)
        // A UI touch must never inherit sky-drag ownership. This branch used to
        // set only touchStartedOnUi, unlike the dock branch below which also
        // clears the drag state: a gesture that began on the sky and lifted over
        // a panel left skyTouchActive set, so every later swipe *inside the panel*
        // cleared the "!skyTouchActive" gate in the move handler and panned the
        // star map along with the list.
        this.hooks.setSkyTouchFeedback(false)
        this.hooks.setSkyTouchActive(false)
        this.hooks.setSkyDragging(false)
        this.nativeDragActive = false
        // 手机端右上角快捷按钮（陀螺仪/音频）：XComponent 同样吞掉了 onClick，
        // 需要坐标级分派，与上方 tablet rail workaround 同理。
        if (!this.hooks.isExpandedLayout() && this.hooks.isCompactTopQuickPoint(downX, downY)) {
          const qx = this.hooks.compactTopQuickX()
          const qy = compactTopQuickY()
          // 陀螺仪按钮（上方的 44x44，圆心约 qx+22, qy+22）
          if (downX >= qx && downX <= qx + 44 && downY >= qy && downY <= qy + 44) {
            hilog.info(0x0000, 'StellariumArkUI', '[DIAG] gyro tap via handleSkyTouch')
            this.hooks.resetPanelIdle()
            this.hooks.toggleGyroscope(!this.hooks.gyroscopeEnabled())
            return
          }
          // 音频按钮（下方的 44x44，间距 10vp，圆心约 qx+22, qy+54+22）
          if (downX >= qx && downX <= qx + 44 && downY >= qy + 54 && downY <= qy + 54 + 44) {
            hilog.info(0x0000, 'StellariumArkUI', '[DIAG] audio tap via handleSkyTouch')
            this.hooks.resetPanelIdle()
            this.hooks.toggleMusic()
            this.hooks.flashHint(this.hooks.musicHintText())
            return
          }
        }
        return
      }
      this.hooks.setSkyTouchActive(true)
      this.gestureOwner = SkyGestureOwner.Sky
      // 本次手势归属只由本次 Down 的几何决定。旧实现把 UI 归属存在全局的 touchStartedOnUi 里，
      // 而该手势的 Up 会被 `!skyTouchActive` 早退吞掉、来不及清理；残留的 true 会让下一次
      // 天空手势被误判为 UI——既不拖动也不点选。这里显式清零，禁止跨手势继承。
      this.hooks.setTouchStartedOnUi(false)
      this.hooks.setSkyDragging(true)
      this.hooks.cancelSelectedObjectUiChange()
      this.commandPort.fire('beginSkyGesture')
      this.hooks.pauseDetailRefreshForSkyDrag()
      this.touchStartX = downX
      this.touchStartY = downY
      this.touchLastX = this.touchStartX
      this.touchLastY = this.touchStartY
      this.touchMoved = false
        this.pinchActive = false
        this.commandPort.fire('endPinch')
        this.nativeDragActive = false
      this.lastDragCommandMs = 0
      this.dragFilteredX = downX
      this.dragFilteredY = downY
      this.dragLastRawX = downX
      this.dragLastRawY = downY
      this.dragLastSampleMs = Date.now()
      this.dragVelocityX = 0
      this.dragVelocityY = 0
      this.dragVelocitySampleValid = false
      this.dragLogCount = 0
      this.hooks.setSkyTouchFeedback(allowTouchFeedback)
      this.hooks.setSkyTouchPoint(downX, downY)
      this.hooks.setSkyTouchFeedbackMulti(allowTouchFeedback && points.length >= 2)
      hilog.info(0x0000, 'StellariumArkUI', 'sky touch down at ' + Math.round(this.touchStartX).toString() + ',' + Math.round(this.touchStartY).toString() + ' sky=' + this.hooks.skyWidth().toString() + 'x' + this.hooks.skyHeight().toString())
      if (points.length >= 2) {
        this.resetSkyTapSequence()
        this.hooks.setSkyTouchPoint2(touchWindowX(points[1]), touchWindowY(points[1]))
        this.pinchCenterX = (touchWindowX(points[0]) + this.hooks.skyTouchX2()) / 2
        this.pinchCenterY = (touchWindowY(points[0]) + this.hooks.skyTouchY2()) / 2
        this.pinchStartDistance = distance(
          touchWindowX(points[0]), touchWindowY(points[0]),
          touchWindowX(points[1]), touchWindowY(points[1]))
        this.pinchStartFov = clamp(this.hooks.fovSliderValue() > 0 ? this.hooks.fovSliderValue() : 60, 4, 180)
        this.pinchLastScale = 1
        this.pinchLastNativePushMs = Date.now()
        this.pinchNativePushPending = false
        this.pinchActive = true
        this.commandPort.fire('zoomBy', '1|1|' + this.pinchCenterX.toFixed(2) + '|' +
          this.pinchCenterY.toFixed(2) + '|' + Math.round(this.hooks.skyWidth()).toString() + '|' +
          Math.round(this.hooks.skyHeight()).toString())
      }
      return
    }

    if ((event.type === TouchType.Up || event.type === TouchType.Cancel) && this.hooks.dockTouchActive()) {
      const x = touchWindowX(points[0])
      const y = touchWindowY(points[0])
      this.hooks.setDockTouchActive(false)
      this.hooks.setTouchStartedOnUi(false)
      if (event.type === TouchType.Up) {
        const dockItem = this.hooks.dockActionAt(x, y)
        if (dockItem !== null) { this.hooks.activateDockAction(dockItem) }
      }
      return
    }
    if (this.gestureOwner !== SkyGestureOwner.Sky && this.gestureOwner !== SkyGestureOwner.PanelDrag) {
      // Ui / None 归属的手势：Move 忽略即可；Up/Cancel 清掉归属与拖动态，防跨手势残留。
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.gestureOwner = SkyGestureOwner.None
        this.nativeDragActive = false
        this.panelDragging = false
        this.hooks.setTouchStartedOnUi(false)
        this.hooks.setDockTouchActive(false)
        this.hooks.setSkyTouchFeedback(false)
        this.hooks.setSkyTouchFeedbackMulti(false)
        this.hooks.setSkyDragging(false)
        this.hooks.resumeDetailRefreshAfterSkyDrag()
      }
      return
    }

    if (event.type === TouchType.Move) {
      const x = touchWindowX(points[0])
      const y = touchWindowY(points[0])
      if (this.gestureOwner === SkyGestureOwner.PanelDrag) {
        this.hooks.setTouchStartedOnUi(false)
        this.hooks.setPanelOffset(this.panelDragStartOffsetX + (x - this.panelDragStartX),
          this.panelDragStartOffsetY + (y - this.panelDragStartY))
        return
      }
      if (this.hooks.skyTouchFeedback()) {
        this.hooks.setSkyTouchPoint(x, y)
      }
      if (points.length >= 2) {
        this.hooks.setSkyTouchFeedbackMulti(this.hooks.skyTouchFeedback())
        this.hooks.setSkyTouchPoint2(touchWindowX(points[1]), touchWindowY(points[1]))
        this.pinchCenterX = (x + this.hooks.skyTouchX2()) / 2
        this.pinchCenterY = (y + this.hooks.skyTouchY2()) / 2
        this.nativeDragActive = false
        this.stopSkyInertia()
        const currentDistance = distance(
          x, y, touchWindowX(points[1]), touchWindowY(points[1]))
        if (!this.pinchActive || this.pinchStartDistance <= 1) {
          this.pinchStartDistance = currentDistance
          this.pinchStartFov = clamp(this.hooks.fovSliderValue() > 0 ? this.hooks.fovSliderValue() : 60, 4, 180)
          this.pinchActive = true
          this.pinchLastScale = 1
          this.pinchLastNativePushMs = Date.now()
          this.pinchNativePushPending = false
          this.commandPort.fire('zoomBy', '1|1|' + this.pinchCenterX.toFixed(2) + '|' +
            this.pinchCenterY.toFixed(2) + '|' + Math.round(this.hooks.skyWidth()).toString() + '|' +
            Math.round(this.hooks.skyHeight()).toString())
        } else {
          const scale = currentDistance / this.pinchStartDistance
          this.pinchLastScale = scale
          const estimatedFov = clamp(this.pinchStartFov / Math.max(0.25, scale), 4, 180)
          this.hooks.setFovSliderValue(estimatedFov)
          this.hooks.setCurrentFovText(estimatedFov.toFixed(1) + '°')
          this.pinchNativePushPending = true
          const now = Date.now()
          if (now - this.pinchLastNativePushMs >= 16) {
            this.commandPort.fire('zoomBy', scale.toString() + '|0|' + this.pinchCenterX.toFixed(2) + '|' +
              this.pinchCenterY.toFixed(2) + '|' + Math.round(this.hooks.skyWidth()).toString() + '|' +
              Math.round(this.hooks.skyHeight()).toString())
            this.pinchLastNativePushMs = now
            this.pinchNativePushPending = false
          }
          // 缩放时弹小蓝胶囊实时显示 FOV（节流 150ms，避免桥接风暴）
          const nowMs = Date.now()
          if (nowMs - this.lastFovHintMs >= 150) {
            this.lastFovHintMs = nowMs
            this.hooks.requestFieldOfView((fovDeg: number): void => {
              this.hooks.setCurrentFovText(fovDeg.toFixed(1) + '°')
            })
          }
        }
        this.touchMoved = true
        return
      }
      this.hooks.setSkyTouchFeedbackMulti(false)

      const totalMove = distance(x, y, this.touchStartX, this.touchStartY)
      // 阈值放宽到 16vp:uitest/mock 注入的触摸常有几像素位移,
      // 4vp 会把"轻点"误判成"拖动",导致 selectAt 不触发。
      if (totalMove > 16) {
        this.resetSkyTapSequence()
        this.hooks.cancelSelectedObjectUiChange()
        // Manual panning and sensor tracking must never drive the native
        // camera together. Leave gyro mode on the first real sky drag, while
        // keeping taps and pinch zoom available without changing its state.
        if (!this.touchMoved && this.hooks.gyroscopeEnabled()) {
          this.hooks.stopGyroscope(true)
          this.hooks.flashHint('已退出陀螺仪')
        }
        this.touchMoved = true
      }
      // Ownership is decided on Down: only a gesture that actually started on the
      // sky may pan it. Relying on skyTouchActive alone let a stale flag drag the
      // sky from inside a panel, so the origin is now part of the condition.
      if (this.touchMoved && !this.hooks.touchStartedOnUi()) {
        this.nativeDragActive = true
        const now = Date.now()
        if (now - this.lastDragCommandMs >= 16) {
          if (this.dragLogCount < 5) {
            hilog.info(0x0000, 'StellariumArkUI', 'dragView dx=' + Math.round(x - this.touchLastX).toString() + ' dy=' + Math.round(y - this.touchLastY).toString() + ' throttle=' + (now - this.lastDragCommandMs).toString() + 'ms')
            this.dragLogCount += 1
          }
          this.emitFluidDrag(x, y, now)
          this.lastDragCommandMs = now
        }
      }
      return
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      const owner = this.gestureOwner
      this.gestureOwner = SkyGestureOwner.None
      const x = touchWindowX(points[0])
      const y = touchWindowY(points[0])
      const endedOnUi = this.hooks.isUiPoint(x, y)
      const recordingViewChanged = this.touchMoved || this.pinchActive
      if (owner === SkyGestureOwner.PanelDrag) {
        this.panelDragging = false
        this.hooks.scheduleSelectedObjectForUiChange(160)
        return
      }
      // owner === Sky：天空手势的抬起收尾（惯性 / 点选 / 结束捏合 / 尾部清理 / 检查点）。
      if (this.nativeDragActive && event.type === TouchType.Up) {
        this.emitFluidDrag(x, y, Date.now(), false)
        this.startSkyInertia()
      } else if (event.type === TouchType.Cancel) {
        this.stopSkyInertia()
      } else if (!this.touchMoved && !this.pinchActive && !endedOnUi && Date.now() - this.hooks.lastInfoWinCloseMs() > 320) {
        hilog.info(0x0000, 'StellariumArkUI', 'selectAt payload: ' +
          Math.round(this.touchStartX).toString() + '|' + Math.round(this.touchStartY).toString() + '|' +
          Math.round(this.hooks.skyWidth()).toString() + '|' + Math.round(this.hooks.skyHeight()).toString())
        this.handleSkyTap(this.touchStartX, this.touchStartY)
      }
      if (this.pinchActive) {
        if (this.pinchNativePushPending) {
          this.commandPort.fire('zoomBy', this.pinchLastScale.toString() + '|0|' +
            this.pinchCenterX.toFixed(2) + '|' + this.pinchCenterY.toFixed(2) + '|' +
            Math.round(this.hooks.skyWidth()).toString() + '|' + Math.round(this.hooks.skyHeight()).toString())
        }
        this.commandPort.fire('endPinch')
        this.hooks.scheduleSkyTextureStatusCheck()
      }
      this.pinchActive = false
      this.pinchNativePushPending = false
      this.nativeDragActive = false
      this.hooks.setSkyTouchActive(false)
      this.hooks.setSkyTouchFeedback(false)
      this.hooks.setSkyTouchFeedbackMulti(false)
      this.hooks.setSkyDragging(false)
      if (event.type === TouchType.Cancel) { this.resetSkyTapSequence() }
      this.hooks.resumeDetailRefreshAfterSkyDrag()
      if (event.type === TouchType.Up && recordingViewChanged) {
        this.hooks.scheduleRecordingViewCheckpoint(this.nativeSkyInertiaActive ? 1100 : 180)
      }
    }
  }
}
