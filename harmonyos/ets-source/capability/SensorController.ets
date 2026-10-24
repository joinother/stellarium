// 传感器 / 陀螺仪控制器。
//
// 把陀螺仪 / 旋转矢量 / 重力 / 磁力订阅折算为引擎 setGyroView 姿态，并驱动目标引导与罗盘读数。
// 可观测数据（使能 / 状态 / 罗盘读数 / 目标引导）留在 @Observed GyroStore；手势采样 / 逐帧草稿量
// （事件计数、姿态四元数、滤波向量、订阅回调、显示旋转快照…）留在本普通类，避免每帧触发刷新。
//
// 依赖：SensorPort 提供 probe / subscribe / unsubscribe（本类不碰 sensor.on/off）；CommandPort 提供
// 桥调用与 requestWhenReady；GyroStore / SessionToolStore 以实例引用持有；SensorHostHooks 回注宿主的
// 隐私/前后台判定、UI 提示、布局快照、显示旋转、native 投影查询，以及保留字段 watchLastSend 的读写。
//
// 不 import NAPI/UI：传感器调用走 SensorPort，桥调用走 CommandPort，布局/UI/投影动作经 hooks 回注。
// hilog 与状态查询日志沿用既有 store 先例（如 BookmarkStore）。
import hilog from '@ohos.hilog'
import { I18n } from '../pages/I18n'
import { GyroStore } from '../state/GyroStore'
import { SessionToolStore } from '../state/SessionToolStore'
import { CommandPort } from '../bridge/CommandPort'
import { SensorPort, SensorProbeInfo, RotationVectorSample, OrientationSample, GravitySample, MagneticFieldSample } from '../bridge/SensorPort'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { GyroGuideProjection } from '../pages/MainWindowModels'
import { clamp } from '../common/derive/astro'
import { expandedMainPanelLeft } from '../common/derive/geometry'
import {
  gyroRotateAboutAxis,
  gyroMultiplyQuaternions,
  gyroFilterDeviceVector,
  gyroRotateAboutVertical,
  gyroScreenAxisForDisplay,
  shortestGyroAzimuthDelta,
  wrapGyroAzimuth,
  gyroNormalizeVector,
  gyroNormalizeQuaternion,
  gyroConjugateQuaternion,
  gyroDot,
  gyroMagneticHeadingFromDeviceVectors
} from '../common/derive/gyro'

// 目标引导所需的宿主布局快照（全是数值/布尔，无 UI 类型；宿主在每次调用时实时取）。
export interface GyroGuideLayout {
  isExpandedLayout: boolean
  panelVisible: boolean
  panelOffsetX: number
  panelWidth: number
  edgeMargin: number
  skyWidth: number
  skyHeight: number
  isFoldHoverLayout: boolean
  fovSliderValue: number
}

// 宿主 → 控制器回注：不触碰 UI/宿主私有标志以外的任何 NAPI。
export interface SensorHostHooks {
  // 隐私同意 + 前台 + 启动允许三者合一。
  canUseSensors(): boolean
  // 宿主 UI 提示。
  flashHint(text: ResourceStr): void
  // 当前显示旋转（对应 display.getDefaultDisplaySync().rotation）；不可用返回 -1。
  displayRotation(): number
  // 当前是否有选中天体。
  objectSelected(): boolean
  // 目标引导布局快照。
  guideLayout(): GyroGuideLayout
  // native 投影查询（getGyroGuidePosition → GyroGuideProjection）。
  guideProjection(): GyroGuideProjection | undefined
  // 保留字段 watchLastSend（引擎自用）：经 hooks 读写。
  watchLastSend(): number
  setWatchLastSend(value: number): void
}

export class SensorController {
  private gyroStore: GyroStore
  private sensorPort: SensorPort
  private port: CommandPort
  private sessionToolStore: SessionToolStore
  private hooks: SensorHostHooks

  // ── 订阅状态 / 事件计数（逐帧草稿，留控制器）──
  private gyroPausedForBackground: boolean = false
  private gyroLastTimeMs: number = 0
  private lastGyroUiRequestMs: number = 0
  private gyroGuideTargetAz: number = Number.NaN
  private gyroGuideTargetAlt: number = Number.NaN
  private gyroGuideLastUpdateMs: number = 0
  private gyroGuideReachedAtMs: number = 0
  private gyroLastCompassUiUpdateMs: number = 0
  private gyroMagneticHeading: number = Number.NaN
  private gyroRawAzimuth: number = Number.NaN
  private gyroRawAltitude: number = Number.NaN
  private gyroAbsolutePoseReady: boolean = false
  private gyroAbsoluteUp: number[] = [0, 1, 0]
  private gyroDisplayRotation: number = 0
  private gyroLastDisplayRotationCheckMs: number = 0
  private gyroHeadingReferenceReady: boolean = false
  private gyroHeadingSensorAz: number = 0
  private gyroHeadingViewAz: number = 0
  private gyroEventCount: number = 0
  private gyroRawEventCount: number = 0
  private gyroCallbackCount: number = 0
  private gyroInvalidEventCount: number = 0
  private gyroDispatchCount: number = 0
  private gyroGravityEventCount: number = 0
  private gyroMagneticEventCount: number = 0
  private gyroStartMs: number = 0
  private gyroLastProbeMs: number = 0
  private gyroLastProbeSensor: string = ''
  private gyroRotationSubscribed: boolean = false
  private gyroOrientationSubscribed: boolean = false
  private gyroGravitySubscribed: boolean = false
  private gyroMagneticSubscribed: boolean = false
  private gyroCallback: ((data: OrientationSample) => void) | undefined = undefined
  private gyroRotationCallback: ((data: RotationVectorSample) => void) | undefined = undefined
  private gyroGravityCallback: ((data: GravitySample) => void) | undefined = undefined
  private gyroMagneticCallback: ((data: MagneticFieldSample) => void) | undefined = undefined
  private gyroUsingRotationVector: boolean = false
  private gyroGravityDevice: number[] = []
  private gyroMagneticDevice: number[] = []
  private gyroFilteredGravityDevice: number[] = []
  private gyroFilteredMagneticDevice: number[] = []

  // ── 姿态解算 / 目标引导（逐帧草稿，留控制器）──
  private gyroLastAz: number = 0
  private gyroLastAlt: number = 0
  private gyroFirstReading: boolean = true
  private gyroCalibrated: boolean = false
  private gyroRawAz: number = 0
  private gyroRawAlt: number = 0
  private gyroFwd: number[] = []
  private gyroUp: number[] = []
  private gyroSentFwd: number[] = []
  private gyroLastSampleMs: number = 0
  private gyroLastDispatchMs: number = 0
  private gyroLastRawQ: number[] = [0, 0, 0, 1]

  constructor(
    gyroStore: GyroStore,
    sensorPort: SensorPort,
    port: CommandPort,
    sessionToolStore: SessionToolStore,
    hooks: SensorHostHooks
  ) {
    this.gyroStore = gyroStore
    this.sensorPort = sensorPort
    this.port = port
    this.sessionToolStore = sessionToolStore
    this.hooks = hooks
  }

  // ── 生命周期收口（宿主 aboutToDisappear / 后台收口）──

  // 组件销毁 / 隐私撤销：停订阅并清后台暂停标志。
  stop(): void {
    this.gyroPausedForBackground = false
    this.stopGyroscope(false)
  }

  // 应用切后台：若已开启则暂停订阅，前台再恢复。
  pauseForBackground(): void {
    if (this.gyroStore.gyroscopeEnabled) {
      this.gyroPausedForBackground = true
      this.stopGyroscope(false)
      hilog.info(0x0000, 'StellariumArkUI', 'background: gyroscope subscriptions released')
    }
  }

  // 应用回前台：恢复后台暂停的订阅。
  resumeAfterForeground(): void {
    if (this.gyroPausedForBackground) {
      this.gyroPausedForBackground = false
      this.startGyroscope()
      hilog.info(0x0000, 'StellariumArkUI', 'foreground: gyroscope subscriptions restored')
    }
  }

  // 目标引导目标坐标。
  setGuideTarget(az: number, alt: number): void {
    this.gyroGuideTargetAz = az
    this.gyroGuideTargetAlt = alt
  }

  clearGuideTarget(): void {
    this.gyroGuideTargetAz = Number.NaN
    this.gyroGuideTargetAlt = Number.NaN
  }

  toggleGyroscope(enabled: boolean): void {
    hilog.info(0x0000, 'StellariumArkUI', 'toggleGyroscope enabled=%{public}s current=%{public}s', enabled.toString(), this.gyroStore.gyroscopeEnabled.toString())
    if (enabled) {
      this.startGyroscope()
    } else {
      this.stopGyroscope(true)
    }
  }

  // UI 入口的统一切换：280ms 去抖 + pending 抑制，避免快速连点造成订阅竞态。
  requestGyroscopeToggle(enabled: boolean): void {
    const now = Date.now()
    if (now - this.lastGyroUiRequestMs < 280) {
      hilog.info(0x0000, 'StellariumArkUI', '[gyro-ui] duplicate tap ignored')
      return
    }
    if (this.gyroStore.gyroscopePending) {
      this.hooks.flashHint(this.gyroStore.gyroscopeStatus)
      return
    }
    this.lastGyroUiRequestMs = now
    this.gyroStore.gyroscopePending = true
    this.gyroStore.gyroscopePendingTarget = enabled
    // Safety net: a failed/permission-denied sensor start used to leave the
    // pending flag set forever, making every later tap a no-op.
    setTimeout(() => {
      if (this.gyroStore.gyroscopePending) {
        this.gyroStore.gyroscopePending = false
        this.gyroStore.gyroscopePendingTarget = this.gyroStore.gyroscopeEnabled
      }
    }, 2500)
    this.toggleGyroscope(enabled)
    this.hooks.flashHint(enabled ? I18n.t('m_gyro_listening') : I18n.t('m_gyro_off'))
  }

  private refreshGyroDisplayRotation(source: string): void {
    const rotation = this.hooks.displayRotation()
    if (!Number.isInteger(rotation) || rotation < 0 || rotation > 3) {
      return
    }
    if (rotation !== this.gyroDisplayRotation) {
      this.gyroDisplayRotation = rotation
      this.gyroFwd = []
      this.gyroUp = []
      this.gyroSentFwd = []
      this.gyroLastDispatchMs = 0
      hilog.info(0x0000, 'StellariumArkUI', '[gyro-probe] displayRotation source=%{public}s value=%{public}s', source, rotation.toString())
    }
    this.gyroLastDisplayRotationCheckMs = Date.now()
  }

  startGyroscope(): void {
    if (!this.hooks.canUseSensors()) {
      this.gyroStore.gyroscopePending = false
      this.gyroStore.gyroscopePendingTarget = false
      return
    }
    if (this.gyroStore.gyroscopeEnabled) {
      hilog.info(0x0000, 'StellariumArkUI', 'startGyroscope ignored already enabled')
      this.gyroStore.gyroscopePending = false
      this.gyroStore.gyroscopePendingTarget = true
      return
    }
    if (this.gyroCallback === undefined) {
      this.gyroCallback = (data: OrientationSample) => {
        this.onOrientationData(data)
      }
    }
    if (this.gyroRotationCallback === undefined) {
      this.gyroRotationCallback = (data: RotationVectorSample) => {
        this.onRotationVectorDirect(data)
      }
    }
    if (this.gyroGravityCallback === undefined) {
      this.gyroGravityCallback = (data: GravitySample) => {
        this.onGravityData(data)
      }
    }
    if (this.gyroMagneticCallback === undefined) {
      this.gyroMagneticCallback = (data: MagneticFieldSample) => {
        this.onMagneticFieldData(data)
      }
    }
    this.gyroLastTimeMs = 0
    this.gyroEventCount = 0
    this.gyroRawEventCount = 0
    this.gyroCallbackCount = 0
    this.gyroInvalidEventCount = 0
    this.gyroDispatchCount = 0
    this.gyroGravityEventCount = 0
    this.gyroMagneticEventCount = 0
    this.gyroStartMs = Date.now()
    this.gyroLastProbeMs = 0
    this.gyroLastProbeSensor = ''
    this.gyroRotationSubscribed = false
    this.gyroOrientationSubscribed = false
    this.gyroGravitySubscribed = false
    this.gyroMagneticSubscribed = false
    this.gyroFirstReading = true
    this.gyroCalibrated = false
    this.gyroLastDispatchMs = 0
    this.gyroDisplayRotation = 0
    this.gyroLastDisplayRotationCheckMs = 0
    this.gyroAbsolutePoseReady = false
    this.gyroHeadingReferenceReady = false
    this.gyroFwd = []
    this.gyroUp = []
    this.gyroSentFwd = []
    this.gyroGravityDevice = []
    this.gyroMagneticDevice = []
    this.gyroFilteredGravityDevice = []
    this.gyroFilteredMagneticDevice = []
    this.gyroMagneticHeading = Number.NaN
    this.gyroStore.gyroCompassAzAlignment = 0
    this.gyroStore.gyroCompassText = '罗盘 --'
    this.gyroStore.gyroCompassAngle = 0
    this.gyroUsingRotationVector = false
    this.gyroStore.gyroscopeEnabled = true
    this.gyroStore.gyroscopePending = false
    this.gyroStore.gyroscopePendingTarget = true
    this.refreshGyroDisplayRotation('start')
    this.gyroStore.gyroscopeStatus = '正在校准'
    this.port.fire('beginGyroViewTransition')

    const rotationSupported = this.sensorPort.probeSensor('rotation-vector') !== undefined
    const rotationCallback = this.gyroRotationCallback
    if (rotationSupported && rotationCallback !== undefined) {
      try {
        this.sensorPort.subscribeRotationVector(rotationCallback, 16666667)
        this.gyroRotationSubscribed = true
        this.gyroUsingRotationVector = true
        hilog.info(0x0000, 'StellariumArkUI', '[gyro-probe] subscribed sensor=rotation-vector intervalNs=16666667')
      } catch (error) {
        hilog.error(0x0000, 'StellariumArkUI', '[gyro-probe] subscribe failed sensor=rotation-vector error=%{public}s', JSON.stringify(error))
      }
    }

    if (this.gyroRotationSubscribed) {
      const gravityCallback = this.gyroGravityCallback
      if (this.sensorPort.probeSensor('gravity') !== undefined && gravityCallback !== undefined) {
        try {
          this.sensorPort.subscribeGravity(gravityCallback, 16666667)
          this.gyroGravitySubscribed = true
          hilog.info(0x0000, 'StellariumArkUI', '[gyro-probe] subscribed sensor=gravity intervalNs=16666667')
        } catch (error) {
          hilog.warn(0x0000, 'StellariumArkUI', '[gyro-probe] subscribe failed sensor=gravity error=%{public}s', JSON.stringify(error))
        }
      }
      const magneticCallback = this.gyroMagneticCallback
      if (this.sensorPort.probeSensor('magnetic-field') !== undefined && magneticCallback !== undefined) {
        try {
          this.sensorPort.subscribeMagneticField(magneticCallback, 33333333)
          this.gyroMagneticSubscribed = true
          hilog.info(0x0000, 'StellariumArkUI', '[gyro-probe] subscribed sensor=magnetic-field intervalNs=33333333')
        } catch (error) {
          hilog.warn(0x0000, 'StellariumArkUI', '[gyro-probe] subscribe failed sensor=magnetic-field error=%{public}s', JSON.stringify(error))
        }
      }
      hilog.info(0x0000, 'StellariumArkUI', '[gyro-probe] start mode=rotation-vector gravity=%{public}s magnetic=%{public}s',
        this.gyroGravitySubscribed.toString(), this.gyroMagneticSubscribed.toString())
      return
    }

    const orientationCallback = this.gyroCallback
    if (this.sensorPort.probeSensor('orientation-fallback') !== undefined && orientationCallback !== undefined) {
      try {
        this.sensorPort.subscribeOrientation(orientationCallback, 16666667)
        this.gyroOrientationSubscribed = true
        this.gyroStore.gyroscopeStatus = '正在校准'
        hilog.warn(0x0000, 'StellariumArkUI', '[gyro-probe] start mode=orientation-fallback')
        return
      } catch (error) {
        hilog.error(0x0000, 'StellariumArkUI', '[gyro-probe] subscribe failed sensor=orientation-fallback error=%{public}s', JSON.stringify(error))
      }
    }

    this.gyroStore.gyroscopeEnabled = false
    this.port.fire('cancelGyroViewTransition')
    this.gyroStore.gyroscopeStatus = I18n.t('m_gyro_unavailable')
    this.hooks.flashHint(I18n.t('m_gyro_unavailable'))
    hilog.error(0x0000, 'StellariumArkUI', '[gyro-probe] start failed no supported orientation sensor')
  }

  stopGyroscope(updateStatus: boolean): void {
    this.port.fire('cancelGyroViewTransition')
    const mode = this.gyroUsingRotationVector ? 'rotation-vector' : (this.gyroOrientationSubscribed ? 'orientation-fallback' : 'none')
    const elapsedMs = this.gyroStartMs > 0 ? Math.max(1, Date.now() - this.gyroStartMs) : 1
    hilog.info(0x0000, 'StellariumArkUI', '[gyro-probe] stop mode=%{public}s callbacks=%{public}s valid=%{public}s dispatch=%{public}s invalid=%{public}s gravity=%{public}s magnetic=%{public}s elapsedMs=%{public}s',
      mode, this.gyroCallbackCount.toString(), this.gyroRawEventCount.toString(), this.gyroDispatchCount.toString(),
      this.gyroInvalidEventCount.toString(), this.gyroGravityEventCount.toString(), this.gyroMagneticEventCount.toString(), elapsedMs.toString())
    if (this.gyroOrientationSubscribed && this.gyroCallback !== undefined) {
      try {
        this.sensorPort.unsubscribeOrientation(this.gyroCallback)
      } catch (error) {
      }
    }
    if (this.gyroRotationSubscribed && this.gyroRotationCallback !== undefined) {
      try {
        this.sensorPort.unsubscribeRotationVector(this.gyroRotationCallback)
      } catch (error) {
      }
    }
    if (this.gyroGravitySubscribed && this.gyroGravityCallback !== undefined) {
      try {
        this.sensorPort.unsubscribeGravity(this.gyroGravityCallback)
      } catch (error) {
      }
    }
    if (this.gyroMagneticSubscribed && this.gyroMagneticCallback !== undefined) {
      try {
        this.sensorPort.unsubscribeMagneticField(this.gyroMagneticCallback)
      } catch (error) {
      }
    }
    this.gyroOrientationSubscribed = false
    this.gyroRotationSubscribed = false
    this.gyroGravitySubscribed = false
    this.gyroMagneticSubscribed = false
    this.gyroLastTimeMs = 0
    this.gyroCalibrated = false
    this.gyroFirstReading = true
    this.gyroLastDispatchMs = 0
    this.gyroAbsolutePoseReady = false
    this.gyroHeadingReferenceReady = false
    this.gyroUsingRotationVector = false
    this.gyroGravityDevice = []
    this.gyroMagneticDevice = []
    this.gyroFilteredGravityDevice = []
    this.gyroFilteredMagneticDevice = []
    this.gyroMagneticHeading = Number.NaN
    this.gyroStore.gyroCompassAzAlignment = 0
    this.gyroStore.gyroCompassText = '罗盘 --'
    this.gyroStore.gyroCompassAngle = 0
    this.gyroStore.gyroGuideVisible = false
    this.gyroStore.gyroscopeEnabled = false
    this.gyroStore.gyroscopePending = false
    this.gyroStore.gyroscopePendingTarget = false
    if (updateStatus) {
      this.gyroStore.gyroscopeStatus = I18n.t('m_gyro_off')
    }
  }

  // Keep the guide's heading continuous. Native projection supplies angles in
  // [-180, 180], but animating that value directly can make a one-degree turn
  // across the boundary look like a full-circle spin.
  private setGyroGuidePose(x: number, y: number, targetAngle: number): void {
    let angle = targetAngle
    if (this.gyroStore.gyroGuideVisible) {
      let delta = (targetAngle - this.gyroStore.gyroGuideAngle) % 360
      if (delta > 180) { delta -= 360 }
      if (delta < -180) { delta += 360 }
      angle = this.gyroStore.gyroGuideAngle + delta
    }
    this.gyroStore.gyroGuideX = x
    this.gyroStore.gyroGuideY = y
    this.gyroStore.gyroGuideAngle = angle
    this.gyroStore.gyroGuideVisible = true
  }

  updateGyroTargetGuide(force: boolean = false): void {
    if (!this.gyroStore.gyroscopeEnabled || !this.hooks.objectSelected() ||
      !Number.isFinite(this.gyroGuideTargetAz) || !Number.isFinite(this.gyroGuideTargetAlt) ||
      !Number.isFinite(this.gyroLastAz) || !Number.isFinite(this.gyroLastAlt)) {
      this.gyroStore.gyroGuideVisible = false
      this.gyroGuideReachedAtMs = 0
      return
    }
    const now = Date.now()
    // The guide is an informational ArkUI overlay, not part of the camera
    // feedback loop. Updating it at 20 Hz keeps it responsive without making
    // every 60 Hz sensor sample perform a synchronous native projection query.
    if (!force && now - this.gyroGuideLastUpdateMs < 50) { return }
    this.gyroGuideLastUpdateMs = now

    const layout = this.hooks.guideLayout()
    const left = layout.isExpandedLayout && layout.panelVisible
      ? expandedMainPanelLeft(layout.edgeMargin, layout.panelOffsetX) + layout.panelWidth + 18
      : (layout.isExpandedLayout ? layout.edgeMargin + 24 : 18)
    const right = layout.isExpandedLayout ? layout.skyWidth - layout.edgeMargin : layout.skyWidth - 18
    const top = layout.isFoldHoverLayout ? 46 : 64
    const bottom = layout.skyHeight - (layout.isFoldHoverLayout ? 104 : 96)
    const centerX = Math.max(left + 24, (left + right) / 2)
    const centerY = Math.max(top + 24, (top + bottom) / 2)

    // The C++ render loop projects the selected object with the active
    // Stellarium projector. This remains correct for every FOV and projection
    // type, unlike deriving a screen vector from separate alt/az deltas.
    const projection = this.hooks.guideProjection()
    if (projection !== undefined && projection.ok === true && projection.valid === true &&
      typeof projection.xRatio === 'number' && typeof projection.yRatio === 'number') {
      const targetX = projection.xRatio * layout.skyWidth
      const targetY = projection.yRatio * layout.skyHeight
      const targetInClearSky = projection.visible === true &&
        targetX >= left + 24 && targetX <= right - 24 && targetY >= top + 24 && targetY <= bottom - 24
      if (targetInClearSky) {
        if (this.gyroGuideReachedAtMs === 0) {
          this.gyroGuideReachedAtMs = now
        }
        // The arrow confirms that the target has arrived, then gets out of
        // the way. It reappears only after the object leaves the clear sky.
        if (now - this.gyroGuideReachedAtMs >= 1800) {
          this.gyroStore.gyroGuideVisible = false
          return
        }
        // The guide sits above its target and points down. At the very top,
        // place it below instead so it stays fully reachable and visible.
        const placeAbove = targetY - 58 >= top
        this.setGyroGuidePose(
          clamp(targetX - 22, left, Math.max(left, right - 44)),
          clamp(targetY + (placeAbove ? -58 : 14) - 22, top, Math.max(top, bottom - 44)),
          placeAbove ? 90 : -90
        )
        return
      }
      this.gyroGuideReachedAtMs = 0
      // If the native projection is outside the usable sky area, its true
      // screen-space vector still gives an accurate edge direction.
      const dx = targetX - centerX
      const dy = targetY - centerY
      if (Number.isFinite(dx) && Number.isFinite(dy) && Math.abs(dx) + Math.abs(dy) > 0.5) {
        const angle = Math.atan2(dy, dx) * 180 / Math.PI
        const radians = angle * Math.PI / 180
        const halfW = Math.max(1, (right - left) / 2 - 24)
        const halfH = Math.max(1, (bottom - top) / 2 - 24)
        const edgeScaleX = Math.abs(Math.cos(radians)) > 0.0001 ? halfW / Math.abs(Math.cos(radians)) : Number.POSITIVE_INFINITY
        const edgeScaleY = Math.abs(Math.sin(radians)) > 0.0001 ? halfH / Math.abs(Math.sin(radians)) : Number.POSITIVE_INFINITY
        const edgeScale = Math.min(edgeScaleX, edgeScaleY)
        this.setGyroGuidePose(
          clamp(centerX + Math.cos(radians) * edgeScale - 22, left, Math.max(left, right - 44)),
          clamp(centerY + Math.sin(radians) * edgeScale - 22, top, Math.max(top, bottom - 44)),
          angle
        )
        return
      }
    }

    // Project the target's local tangent-plane direction around the current
    // view. Cos(altitude) prevents a small azimuth change near zenith from
    // looking like an enormous horizontal turn.
    const horizontal = shortestGyroAzimuthDelta(this.gyroGuideTargetAz, this.gyroLastAz) *
      Math.cos(this.gyroLastAlt * Math.PI / 180)
    const vertical = this.gyroGuideTargetAlt - this.gyroLastAlt
    const separation = Math.sqrt(horizontal * horizontal + vertical * vertical)
    const fov = Math.max(5, layout.fovSliderValue > 0 ? layout.fovSliderValue : 60)
    if (separation <= fov * 0.48) {
      this.gyroStore.gyroGuideVisible = false
      this.gyroGuideReachedAtMs = 0
      return
    }

    // The forward icon points right at 0 degrees. Negative vertical is up on
    // screen, so a target above the view produces a -90 degree arrow.
    const angle = Math.atan2(-vertical, horizontal) * 180 / Math.PI
    const radians = angle * Math.PI / 180
    const dx = Math.cos(radians)
    const dy = Math.sin(radians)
    // Intersect the direction vector with the usable viewport rectangle.
    // This puts the guide on its edge rather than on an arbitrary inner ring.
    const halfW = Math.max(1, (right - left) / 2 - 24)
    const halfH = Math.max(1, (bottom - top) / 2 - 24)
    const edgeScaleX = Math.abs(dx) > 0.0001 ? halfW / Math.abs(dx) : Number.POSITIVE_INFINITY
    const edgeScaleY = Math.abs(dy) > 0.0001 ? halfH / Math.abs(dy) : Number.POSITIVE_INFINITY
    const edgeScale = Math.min(edgeScaleX, edgeScaleY)
    this.setGyroGuidePose(
      clamp(centerX + dx * edgeScale - 22, left, Math.max(left, right - 44)),
      clamp(centerY + dy * edgeScale - 22, top, Math.max(top, bottom - 44)),
      angle
    )
  }

  // The Orientation sensor already reports a world-referenced pose. Do not
  // anchor it to the existing sky view: doing so makes "flat" retain an
  // arbitrary altitude instead of consistently looking at the nadir.
  calibrateGyroscope(): void {
    if (!this.gyroStore.gyroscopeEnabled || this.gyroFirstReading) { return }
    this.gyroAbsolutePoseReady = false
    this.gyroHeadingReferenceReady = false
    this.gyroLastDispatchMs = 0
    this.gyroCalibrated = true
    this.gyroStore.gyroscopeStatus = '已校准'
  }

  private onOrientationData(data: OrientationSample): void {
    if (!this.gyroStore.gyroscopeEnabled) { return }
    this.gyroCallbackCount += 1
    let smoothFactor: number = 0.18
    if (this.gyroStore.gyroscopeSensitivityText === 'Low') { smoothFactor = 0.10 }
    else if (this.gyroStore.gyroscopeSensitivityText === 'High') { smoothFactor = 0.28 }

    if (!Number.isFinite(data.alpha) || !Number.isFinite(data.beta) || !Number.isFinite(data.gamma)) {
      this.gyroInvalidEventCount += 1
      this.emitGyroPoseProbe('invalid')
      return
    }
    this.gyroRawEventCount += 1
    const alpha = data.alpha * Math.PI / 180
    const beta = data.beta * Math.PI / 180
    const gamma = data.gamma * Math.PI / 180
    const cosAlpha = Math.cos(alpha)
    const sinAlpha = Math.sin(alpha)
    const cosBeta = Math.cos(beta)
    const sinBeta = Math.sin(beta)
    const cosGamma = Math.cos(gamma)
    const sinGamma = Math.sin(gamma)
    // World-space normal of the display front. The observer looks through the
    // back of the device, hence the sky-forward vector is its inverse.
    const normalX = cosAlpha * sinGamma + sinAlpha * sinBeta * cosGamma
    const normalY = sinAlpha * sinGamma - cosAlpha * sinBeta * cosGamma
    const normalZ = cosBeta * cosGamma
    const forwardX = -normalX
    const forwardY = -normalY
    const forwardZ = -normalZ
    const targetAlt = clamp(Math.asin(clamp(forwardZ, -1, 1)) * 180 / Math.PI + this.gyroStore.gyroOffsetAlt, -90, 90)
    // A display pointing near the zenith or nadir has no meaningful heading:
    // tiny sensor noise can map to any azimuth and makes the horizon slide
    // sideways while lifting the Pad. alpha is the fused compass heading and
    // remains stable when the Pad is vertical, so use it for yaw; retain the
    // last heading in the polar dead zone and restore it progressively.
    const horizontalStrength = Math.sqrt(forwardX * forwardX + forwardY * forwardY)
    // In landscape, the reported alpha rotates in the opposite direction to
    // Stellarium's azimuth frame. More importantly, it becomes ambiguous when
    // the Pad is flat. Anchor only once the display has a real horizontal aim;
    // after that use its delta, not its changing Euler-angle zero point.
    const rawHeading = wrapGyroAzimuth(-data.alpha + this.gyroStore.gyroOffsetAz)
    let targetAz = rawHeading
    if (this.gyroAbsolutePoseReady) {
      if (!this.gyroHeadingReferenceReady && horizontalStrength >= 0.42) {
        this.gyroHeadingSensorAz = rawHeading
        this.gyroHeadingViewAz = this.gyroLastAz
        this.gyroHeadingReferenceReady = true
      }
      targetAz = this.gyroHeadingReferenceReady
        ? wrapGyroAzimuth(this.gyroHeadingViewAz + shortestGyroAzimuthDelta(this.gyroHeadingSensorAz, rawHeading))
        : this.gyroLastAz
    }
    // Device Y is the top edge of the screen. Keeping it as the camera up
    // basis removes the otherwise undefined roll at zenith and nadir.
    const rawUp: number[] = [-sinAlpha * cosBeta, cosAlpha * cosBeta, sinBeta]

    this.gyroRawAz = targetAz
    this.gyroRawAlt = targetAlt
    this.emitGyroPoseProbe('sample', [forwardX, forwardY, forwardZ], rawUp, targetAz, targetAlt)
    if (this.gyroFirstReading) {
      this.gyroFirstReading = false
      this.calibrateGyroscope()
      return
    }
    if (!this.gyroCalibrated) { return }

    let initialPose = false
    if (!this.gyroAbsolutePoseReady) {
      this.gyroLastAz = targetAz
      this.gyroLastAlt = targetAlt
      this.gyroAbsoluteUp = rawUp
      this.gyroAbsolutePoseReady = true
      initialPose = true
    }
    const headingFactor = this.gyroHeadingReferenceReady ? smoothFactor : 0
    const smoothAz = wrapGyroAzimuth(this.gyroLastAz +
      shortestGyroAzimuthDelta(this.gyroLastAz, targetAz) * headingFactor)
    const smoothAlt = this.gyroLastAlt + (targetAlt - this.gyroLastAlt) * smoothFactor

    const azDelta = shortestGyroAzimuthDelta(this.gyroLastAz, smoothAz)
    const altDelta = smoothAlt - this.gyroLastAlt
    // The first valid pose must always reach the native view. Without this,
    // enabling the sensor while the Pad is held still leaves Stellarium at
    // the old horizon because the normal dead-zone returns before dispatch.
    if (!initialPose && Math.abs(azDelta) < 0.25 && Math.abs(altDelta) < 0.25) { return }

    this.gyroLastAz = smoothAz
    this.gyroLastAlt = smoothAlt
    const aimX = Math.cos(smoothAlt * Math.PI / 180) * Math.cos(smoothAz * Math.PI / 180)
    const aimY = Math.cos(smoothAlt * Math.PI / 180) * Math.sin(smoothAz * Math.PI / 180)
    const aimZ = Math.sin(smoothAlt * Math.PI / 180)
    let upX = this.gyroAbsoluteUp[0] + (rawUp[0] - this.gyroAbsoluteUp[0]) * smoothFactor
    let upY = this.gyroAbsoluteUp[1] + (rawUp[1] - this.gyroAbsoluteUp[1]) * smoothFactor
    let upZ = this.gyroAbsoluteUp[2] + (rawUp[2] - this.gyroAbsoluteUp[2]) * smoothFactor
    const upDotAim = upX * aimX + upY * aimY + upZ * aimZ
    upX -= aimX * upDotAim
    upY -= aimY * upDotAim
    upZ -= aimZ * upDotAim
    const upLength = Math.sqrt(upX * upX + upY * upY + upZ * upZ)
    this.gyroAbsoluteUp = upLength > 0.0001 ? [upX / upLength, upY / upLength, upZ / upLength] : rawUp
    const now = Date.now()
    this.updateGyroTargetGuide()
    if (now - this.gyroLastDispatchMs < 20) { return }
    this.gyroLastDispatchMs = now
    this.port.fire('setGyroView', smoothAz.toFixed(3) + '|' + smoothAlt.toFixed(3) + '|'
      + this.gyroAbsoluteUp[0].toFixed(5) + '|' + this.gyroAbsoluteUp[1].toFixed(5) + '|' + this.gyroAbsoluteUp[2].toFixed(5))
    this.gyroEventCount += 1
    this.gyroDispatchCount += 1
    if (this.gyroEventCount % 20 === 0) {
      this.gyroStore.gyroscopeStatus = I18n.t('m_gyro_working')
    }
  }

  private gyroRotateVector(q: number[], v: number[]): number[] {
    const vectorQuaternion = [v[0], v[1], v[2], 0]
    const rotated = gyroMultiplyQuaternions(gyroMultiplyQuaternions(q, vectorQuaternion), gyroConjugateQuaternion(q))
    return [rotated[0], rotated[1], rotated[2]]
  }

  private gyroVectorAltAz(v: number[]): number[] {
    const n = gyroNormalizeVector(v)
    let azimuth = Math.atan2(n[1], n[0]) * 180 / Math.PI
    if (azimuth < 0) { azimuth += 360 }
    return [azimuth, Math.asin(n[2]) * 180 / Math.PI]
  }

  // Keep the up vector perpendicular to the view direction. Without this the
  // two drift apart after repeated smoothing and the roll becomes unstable
  // near the zenith.
  private gyroOrthonormalizeUp(fwd: number[], up: number[]): number[] {
    const d = fwd[0] * up[0] + fwd[1] * up[1] + fwd[2] * up[2]
    let o: number[] = [up[0] - fwd[0] * d, up[1] - fwd[1] * d, up[2] - fwd[2] * d]
    if (o[0] * o[0] + o[1] * o[1] + o[2] * o[2] < 0.000001) {
      const dz = fwd[2]
      o = [-fwd[0] * dz, -fwd[1] * dz, 1 - fwd[2] * dz]
      if (o[0] * o[0] + o[1] * o[1] + o[2] * o[2] < 0.000001) { return [1, 0, 0] }
    }
    return gyroNormalizeVector(o)
  }

  // Interpolate directly on the unit sphere. Linear interpolation of the
  // forward and screen-up vectors independently makes a non-rigid camera and
  // is the source of the apparent jump when the view crosses the zenith.
  // Parallel-transport the screen's up axis along the celestial sphere from
  // one look direction to the next. This provides a continuous tangent-plane
  // basis at zenith and nadir instead of rebuilding one from an Euler angle.
  // The rotation-vector sensor reports in the ENU (east/north/up) world frame,
  // while the engine view direction and setGyroView use the bridge alt-az frame
  // (azimuth = atan2(y, x), x points south). The two frames differ only by a
  // 90 deg rotation about the vertical, but applying an ENU-frame relative
  // rotation directly to a bridge-frame vector silently swaps pitch and roll.
  // These helpers keep the math in one frame at a time.
  private gyroBridgeFromEnu(v: number[]): number[] { // ENU -> bridge
    return [-v[1], v[0], v[2]]
  }

  // Direct rotation-vector path. The system fusion already combines gravity,
  // gyroscope and magnetometer into a complete pose, which avoids the Euler
  // alpha/beta/gamma discontinuity at the horizon. The separate gravity and
  // magnetic callbacks remain active for compass/calibration data, but never
  // replace only one axis of this high-frequency camera pose.
  private onGravityData(data: GravitySample): void {
    this.gyroGravityEventCount += 1
    if (Number.isFinite(data.x) && Number.isFinite(data.y) && Number.isFinite(data.z)) {
      const sample = [data.x, data.y, data.z]
      this.gyroGravityDevice = sample
      this.gyroFilteredGravityDevice = gyroFilterDeviceVector(this.gyroFilteredGravityDevice, sample, 0.22)
    }
  }

  private onMagneticFieldData(data: MagneticFieldSample): void {
    this.gyroMagneticEventCount += 1
    if (Number.isFinite(data.x) && Number.isFinite(data.y) && Number.isFinite(data.z)) {
      const sample = [data.x, data.y, data.z]
      this.gyroMagneticDevice = sample
      this.gyroFilteredMagneticDevice = gyroFilterDeviceVector(this.gyroFilteredMagneticDevice, sample, 0.16)
    }
  }

  // Derive the world basis directly from the two physical references. On this
  // HarmonyOS device the gravity response is the support vector pointing up.
  // Magnetic x up points east; up x east points north.
  // This gives a true device pose without applying a second correction to an
  // already fused rotation quaternion.
  private gyroCompassDirection(heading: number): string {
    const directions = ['北', '东北', '东', '东南', '南', '西南', '西', '西北']
    const index = Math.floor((wrapGyroAzimuth(heading) + 22.5) / 45) % directions.length
    return directions[index]
  }

  private updateGyroCompassReadout(): void {
    const heading = gyroMagneticHeadingFromDeviceVectors(this.gyroGravityDevice, this.gyroMagneticDevice, this.gyroFilteredGravityDevice, this.gyroFilteredMagneticDevice)
    if (!Number.isFinite(heading)) { return }
    this.gyroMagneticHeading = heading
    // Keep the needle continuous through 359 -> 0 rather than animating a
    // full revolution in the opposite direction.
    let delta = (heading - this.gyroStore.gyroCompassAngle) % 360
    if (delta > 180) { delta -= 360 }
    if (delta < -180) { delta += 360 }
    this.gyroStore.gyroCompassAngle += delta
    const now = Date.now()
    if (now - this.gyroLastCompassUiUpdateMs < 120) { return }
    this.gyroLastCompassUiUpdateMs = now
    this.gyroStore.gyroCompassText = '磁北 ' + this.gyroCompassDirection(heading) + ' ' + Math.round(heading).toString().padStart(3, '0') + '°'
  }

  private emitGyroPoseProbe(reason: string, rawForward: number[] = [], rawUp: number[] = [], rawAz: number = Number.NaN, rawAlt: number = Number.NaN): void {
    const now = Date.now()
    if (now - this.gyroLastProbeMs < 1000) { return }
    this.gyroLastProbeMs = now
    hilog.info(0x0000, 'StellariumArkUI',
      '[GYRO_PROBE] reason=%{public}s callbacks=%{public}d dispatch=%{public}d invalid=%{public}d',
      reason, this.gyroCallbackCount, this.gyroDispatchCount, this.gyroInvalidEventCount)
  }

  private onRotationVectorDirect(data: RotationVectorSample): void {
    if (!this.gyroStore.gyroscopeEnabled) { return }
    this.gyroCallbackCount += 1
    if (!Number.isFinite(data.x) || !Number.isFinite(data.y) ||
      !Number.isFinite(data.z) || !Number.isFinite(data.w)) {
      this.gyroInvalidEventCount += 1
      this.emitGyroPoseProbe('invalid')
      return
    }
    this.gyroLastRawQ = [data.x, data.y, data.z, data.w]
    const rawQuaternionNorm = Math.sqrt(data.x * data.x + data.y * data.y + data.z * data.z + data.w * data.w)
    if (!Number.isFinite(rawQuaternionNorm) || rawQuaternionNorm < 0.000001) {
      this.gyroInvalidEventCount += 1
      this.emitGyroPoseProbe('invalid')
      return
    }
    this.gyroRawEventCount += 1
    const sampleNow = Date.now()
    if (sampleNow - this.gyroLastDisplayRotationCheckMs >= 500) {
      this.refreshGyroDisplayRotation('sample')
    }
    if (this.gyroRawEventCount % 120 === 0) {
      this.port.fire('gyroDiagnostic', data.x.toFixed(3) + '|' + data.y.toFixed(3) + '|' +
        data.z.toFixed(3) + '|' + this.gyroRawEventCount.toString())
    }
    const orientation = gyroNormalizeQuaternion([data.x, data.y, data.z, data.w])
    const screenRight = gyroScreenAxisForDisplay([1, 0, 0], this.gyroDisplayRotation)
    const screenUp = gyroScreenAxisForDisplay([0, 1, 0], this.gyroDisplayRotation)
    const screenFrontWorld = this.gyroRotateVector(orientation, [0, 0, 1])
    const screenRightWorld = this.gyroRotateVector(orientation, screenRight)
    const screenUpWorld = this.gyroRotateVector(orientation, screenUp)
    // ROTATION_VECTOR is already a device-to-world orientation. The sky ray
    // goes opposite to the screen front normal; the screen basis stays rigid.
    let forward = this.gyroBridgeFromEnu([-screenFrontWorld[0], -screenFrontWorld[1], -screenFrontWorld[2]])
    forward = gyroNormalizeVector(forward)

    if (this.gyroStore.gyroOffsetAz !== 0) {
      forward = gyroRotateAboutVertical(forward, this.gyroStore.gyroOffsetAz)
    }
    if (this.gyroStore.gyroOffsetAlt !== 0) {
      const horizontal = Math.sqrt(forward[0] * forward[0] + forward[1] * forward[1])
      if (horizontal > 0.001) {
        forward = gyroRotateAboutAxis(forward, [forward[1] / horizontal, -forward[0] / horizontal, 0], this.gyroStore.gyroOffsetAlt)
        forward = gyroNormalizeVector(forward)
      }
    }

    let up = this.gyroBridgeFromEnu(screenUpWorld)
    const rightLength = Math.sqrt(gyroDot(screenRightWorld, screenRightWorld))
    if (rightLength < 0.5) {
      this.gyroInvalidEventCount += 1
      this.emitGyroPoseProbe('invalid-basis', forward, up)
      return
    }
    this.updateGyroCompassReadout()
    if (this.gyroStore.gyroOffsetAz !== 0) {
      up = gyroRotateAboutVertical(up, this.gyroStore.gyroOffsetAz)
    }
    if (this.gyroStore.gyroOffsetAlt !== 0) {
      const horizontal = Math.sqrt(forward[0] * forward[0] + forward[1] * forward[1])
      if (horizontal > 0.001) {
        up = gyroRotateAboutAxis(up, [forward[1] / horizontal, -forward[0] / horizontal, 0], this.gyroStore.gyroOffsetAlt)
      }
    }
    up = this.gyroOrthonormalizeUp(forward, up)
    const rawAltAz = this.gyroVectorAltAz(forward)
    this.gyroRawAzimuth = rawAltAz[0]
    this.gyroRawAltitude = rawAltAz[1]

    const now = Date.now()
    let poseSmoothingAmount = 1
    if (this.gyroFwd.length !== 3) {
      this.gyroFwd = forward
      this.gyroLastSampleMs = now
    } else {
      let dt = this.gyroLastSampleMs > 0 ? (now - this.gyroLastSampleMs) / 1000 : 1 / 60
      this.gyroLastSampleMs = now
      if (dt <= 0) { dt = 1 / 60 }
      if (dt > 0.25) { dt = 0.25 }
      // ROTATION_VECTOR is already sensor-fused. A long second low-pass filter
      // made the sky trail the Pad by roughly 100 ms, which felt like dropped
      // frames even when rendering was healthy. Keep only enough damping for
      // hand tremor and use the same time-based amount for forward and up.
      let tau = 0.045
      if (this.gyroStore.gyroscopeSensitivityText === 'Low') { tau = 0.08 }
      else if (this.gyroStore.gyroscopeSensitivityText === 'High') { tau = 0.025 }
      poseSmoothingAmount = 1 - Math.exp(-dt / tau)
      this.gyroFwd = gyroNormalizeVector([
        this.gyroFwd[0] + (forward[0] - this.gyroFwd[0]) * poseSmoothingAmount,
        this.gyroFwd[1] + (forward[1] - this.gyroFwd[1]) * poseSmoothingAmount,
        this.gyroFwd[2] + (forward[2] - this.gyroFwd[2]) * poseSmoothingAmount
      ])
    }

    if (this.gyroUp.length !== 3) {
      this.gyroUp = up
    } else {
      if (gyroDot(this.gyroUp, up) < 0) {
        up = [-up[0], -up[1], -up[2]]
      }
      this.gyroUp = this.gyroOrthonormalizeUp(this.gyroFwd, [
        this.gyroUp[0] + (up[0] - this.gyroUp[0]) * poseSmoothingAmount,
        this.gyroUp[1] + (up[1] - this.gyroUp[1]) * poseSmoothingAmount,
        this.gyroUp[2] + (up[2] - this.gyroUp[2]) * poseSmoothingAmount
      ])
    }
    this.emitGyroPoseProbe('sample', forward, up, rawAltAz[0], rawAltAz[1])

    if (now - this.gyroLastDispatchMs < 16) { return }
    this.gyroLastDispatchMs = now
    const altAz = this.gyroVectorAltAz(this.gyroFwd)
    this.gyroLastAz = altAz[0]
    this.gyroLastAlt = altAz[1]
    this.updateGyroTargetGuide()
    this.port.fire('setGyroView', this.gyroLastAz.toFixed(3) + '|' + this.gyroLastAlt.toFixed(3) + '|'
      + this.gyroUp[0].toFixed(5) + '|' + this.gyroUp[1].toFixed(5) + '|' + this.gyroUp[2].toFixed(5))
    this.gyroEventCount += 1
    this.gyroDispatchCount += 1
    if (this.gyroEventCount % 20 === 0 && this.gyroStore.gyroscopeStatus !== I18n.t('m_gyro_working')) {
      this.gyroStore.gyroscopeStatus = I18n.t('m_gyro_working')
    }
  }

  // 虚拟指星笔 —— 手表当陀螺仪（发射端模拟）。这条路径是**桥驱动**，
  // 走 pointAtSky / pointAtSkyStop 桥命令（CommandPort.requestWhenReady），不走 sensor.*。
  watchGyroSend(): void {
    if (!this.sessionToolStore.watchTracking) return
    const now = Date.now()
    if (now - this.hooks.watchLastSend() < 70) return // 节流，避免拖动时刷爆命令队列
    this.hooks.setWatchLastSend(now)
    const alt = this.sessionToolStore.watchAlt
    const az = this.sessionToolStore.watchAz
    this.port.requestWhenReady('pointAtSky', alt + '|' + az + '|1', (r: StellariumBridgeResponse) => {
      if (!r.ok) { this.sessionToolStore.watchResult = '手表指向未响应'; return }
      // 跟踪模式只负责跟随，不刷文本，避免抖动
    })
  }

  watchGyroStart(): void {
    this.sessionToolStore.watchTracking = true
    this.sessionToolStore.watchResult = '手表指向中：拖动滑块，大屏实时跟随（像陀螺仪追手）'
    this.hooks.flashHint(I18n.t('msg_watch_pointing_started'))
    this.watchGyroSend()
  }

  watchGyroStop(): void {
    this.sessionToolStore.watchTracking = false
    this.port.requestWhenReady('pointAtSkyStop', '', (r: StellariumBridgeResponse) => {
      if (!r.ok) { this.sessionToolStore.watchResult = I18n.t('m_lock_failed'); return }
      this.sessionToolStore.watchResult = I18n.t('m_locking_center')
      setTimeout(() => {
        this.port.requestWhenReady('getSelectedObjectInfo', '', (r2: StellariumBridgeResponse) => {
          if (!r2.ok) return
          if (r2.found) {
            const nm = (r2.name !== undefined && r2.name !== null) ? String(r2.name) : I18n.t('m_unknown')
            const tp = (r2.type !== undefined && r2.type !== null) ? String(r2.type) : ''
            this.sessionToolStore.watchResult = I18n.t('m_lock_hit') + ': ' + nm + (tp ? ' (' + I18n.objectType(tp) + ')' : '')
            this.hooks.flashHint(I18n.t('m_lock_hit') + ': ' + nm)
          } else {
            this.sessionToolStore.watchResult = I18n.t('m_no_target_dir')
            this.hooks.flashHint(I18n.t('m_no_target_dir'))
          }
        })
      }, 400)
    })
  }
}
