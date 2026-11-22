// AR 实景观星与预研控制器。
//
// 一期真实 AR 链路：Camera Kit（后置相机预览）→ OH_NativeImage → OpenGL ES 外部纹理
// → hello.cpp 单通 GPU 亮度感知融合 + 复用现有 SensorController 姿态与罗盘偏置微调。
// 隐私边界：仅在用户主动点击开启 AR 实景时才申请相机权限；退后台或关闭时立即释放相机。
import { common } from '@kit.AbilityKit'
import { CommandPort } from '../bridge/CommandPort'
import { ARStore } from '../state/ARStore'
import { GyroStore } from '../state/GyroStore'
import { StellariumBridgeResponse } from '../common/types/StellariumTypes'
import { ArCameraService } from './ArCameraService'

// AR 能力探测 / 模式切换回包。
export interface ArPreviewBridgeResponse extends StellariumBridgeResponse {
  previewShell?: boolean
  previewOnly?: boolean
}

// 宿主 → 控制器回注：UI 提示、隐私/前后台门控、陀螺仪开关与星图状态读写。
export interface ARHostHooks {
  flashHint(text: ResourceStr): void
  canStartCamera(): boolean
  abilityContext(): common.UIAbilityContext | undefined
  isGyroEnabled(): boolean
  enableGyroForAr(): void
  setArLowLatencyGyro(enabled: boolean): void
  readSkyRestoreState(): ArSkyRestoreSnapshot
  applySkyRestoreState(snapshot: ArSkyRestoreSnapshot): void
  onArCameraActiveChanged(active: boolean): void
}

export interface ArSkyRestoreSnapshot {
  atmosphere: boolean
  landscape: boolean
  mistHorizon: boolean
  fogEffect: boolean
  auroraEnabled: boolean
  fovDeg: number
}

export class ARController {
  private store: ARStore
  private gyroStore: GyroStore
  private port: CommandPort
  private hooks: ARHostHooks
  private savedSkyState: ArSkyRestoreSnapshot | null = null
  private resumeAfterForeground: boolean = false

  constructor(store: ARStore, gyroStore: GyroStore, port: CommandPort, hooks: ARHostHooks) {
    this.store = store
    this.gyroStore = gyroStore
    this.port = port
    this.hooks = hooks
  }

  // 探测本机真实相机与华为 AR Engine 硬件能力，并保留 native 桥预研状态查询。
  loadCapabilities(): void {
    const hw = ArCameraService.getInstance().probeHardware(this.hooks.abilityContext())
    this.store.arCameraSupported = hw.cameraCoreSupported
    this.store.arEngineSlamSupported = hw.arEngineSlam
    this.store.arEngineDepthSupported = hw.arEngineDepth
    this.store.arEngineMeshSupported = hw.arEngineMesh
    this.store.arHardwareSummary = hw.summaryZh

    this.port.requestInteractive('getARCapabilities', '', (r: StellariumBridgeResponse) => {
      const data = r as ArPreviewBridgeResponse
      if (!this.store.arCameraActive) {
        this.store.arPreviewStatus = data.previewShell === true
          ? '实景相机通道已就绪；点击上方「开启 AR 实景观星」即可实时融合真实天空与星图。'
          : 'AR 实景通道就绪。'
      }
    }, () => {
      if (!this.store.arCameraActive) {
        this.store.arPreviewStatus = '实景相机通道已就绪。'
      }
    })
  }

  async toggleArCamera(): Promise<void> {
    if (this.store.arCameraActive) {
      await this.disableArCamera(true)
    } else {
      await this.enableArCamera()
    }
  }

  async enableArCamera(): Promise<void> {
    if (this.store.arCameraActive || this.store.arCameraStarting) return
    if (!this.hooks.canStartCamera()) {
      this.hooks.flashHint('请先完成隐私同意并在前台使用 AR 实景观星')
      return
    }
    const ctx = this.hooks.abilityContext()
    if (ctx === undefined) {
      this.hooks.flashHint('无法获取应用上下文，暂不可开启相机')
      return
    }

    this.store.arCameraStarting = true
    this.store.arPreviewStatus = '正在启动后置相机与 GPU 实景融合…'
    const res = await ArCameraService.getInstance().start(ctx, this.store.arSkyBlend)
    this.store.arCameraStarting = false

    if (!res.ok) {
      this.store.arCameraActive = false
      this.store.arPreviewStatus = res.reason
      this.hooks.flashHint(res.reason)
      return
    }

    // 保存进入 AR 前的地景/大气/视场状态，退出时无损还原
    if (this.savedSkyState === null) {
      this.savedSkyState = this.hooks.readSkyRestoreState()
    }
    // 彻底隐藏虚拟地景、雾山地平线、明亮大气、雾气与高开销极光层，拉高 AR 帧率并消除虚拟山影
    this.port.fire('setAtmosphereFlag', 'landscape|0')
    this.port.fire('setActionChecked', 'actionShow_MistHorizon|0')
    this.port.fire('setAtmosphereFlag', 'atmosphere|0')
    this.port.fire('setAtmosphereFlag', 'fog|0')
    this.port.fire('setSkyDisplaySetting', 'auroraEnabled|0')
    this.port.fire('setFOV', this.store.arCameraFovDeg.toFixed(1))

    // 开启 AR 超低延迟姿态通道（120Hz + 36ms 前瞻预测），并在未开陀螺仪时自动启用
    this.hooks.setArLowLatencyGyro(true)
    if (!this.hooks.isGyroEnabled()) {
      this.hooks.enableGyroForAr()
    }

    this.store.arCameraActive = true
    this.store.arPreviewMode = 'overlay'
    this.store.arPreviewStatus = res.reason
    this.port.fire('setARMode', 'overlay')
    this.hooks.onArCameraActiveChanged(true)
    this.hooks.flashHint('AR 实景已开启 · 双指上下滑可调地景抠像')
  }

  async disableArCamera(restoreSky: boolean): Promise<void> {
    const wasActive = this.store.arCameraActive || ArCameraService.getInstance().isRunning()
    this.resumeAfterForeground = false
    this.store.arCameraActive = false
    this.store.arCameraStarting = false
    this.hooks.setArLowLatencyGyro(false)
    await ArCameraService.getInstance().stop()

    if (restoreSky && this.savedSkyState !== null) {
      const snap = this.savedSkyState
      this.savedSkyState = null
      this.port.fire('setAtmosphereFlag', snap.landscape ? 'landscape|1' : 'landscape|0')
      this.port.fire('setActionChecked', snap.mistHorizon ? 'actionShow_MistHorizon|1' : 'actionShow_MistHorizon|0')
      this.port.fire('setAtmosphereFlag', snap.atmosphere ? 'atmosphere|1' : 'atmosphere|0')
      this.port.fire('setAtmosphereFlag', snap.fogEffect ? 'fog|1' : 'fog|0')
      this.port.fire('setSkyDisplaySetting', snap.auroraEnabled ? 'auroraEnabled|1' : 'auroraEnabled|0')
      this.port.fire('setFOV', snap.fovDeg.toFixed(1))
      this.hooks.applySkyRestoreState(snap)
    }

    if (wasActive) {
      this.port.fire('setARMode', 'off')
      this.store.arPreviewStatus = 'AR 实景已关闭，相机资源已释放。'
      this.hooks.onArCameraActiveChanged(false)
    }
  }

  setSkyBlend(value: number): void {
    if (!Number.isFinite(value)) return
    const clamped = Math.max(0, Math.min(1, value))
    this.store.arSkyBlend = clamped
    ArCameraService.getInstance().updateBlend(clamped)
  }

  setCameraFov(fovDeg: number): void {
    if (!Number.isFinite(fovDeg)) return
    const clamped = Math.max(35, Math.min(85, fovDeg))
    this.store.arCameraFovDeg = clamped
    if (this.store.arCameraActive) {
      this.port.fire('setFOV', clamped.toFixed(1))
    }
  }

  nudgeCompassOffset(deltaDeg: number): void {
    if (!Number.isFinite(deltaDeg)) return
    const next = Math.max(-45, Math.min(45, this.gyroStore.gyroOffsetAz + deltaDeg))
    this.gyroStore.gyroOffsetAz = Math.round(next * 10) / 10
  }

  resetCompassOffset(): void {
    this.gyroStore.gyroOffsetAz = 0
    this.gyroStore.gyroOffsetAlt = 0
    this.hooks.flashHint('罗盘微调已归零')
  }

  refreshDisplayRotation(): void {
    ArCameraService.getInstance().refreshRotation()
  }

  onApplicationForegroundChanged(foreground: boolean): void {
    if (!foreground) {
      if (this.store.arCameraActive) {
        this.resumeAfterForeground = true
        void this.disableArCamera(false)
      }
      return
    }
    if (this.resumeAfterForeground) {
      this.resumeAfterForeground = false
      void this.enableArCamera()
    }
  }

  // 切换 AR 预研模式；切到“只保留星空”时进度直接拉满。
  setMode(mode: string): void {
    if (mode !== 'off' && mode !== 'overlay' && mode !== 'portal' && mode !== 'depth' && mode !== 'sky-only') return
    this.store.arPreviewMode = mode
    if (mode === 'sky-only') this.store.arRevealProgress = 1
    this.port.requestInteractive('setARMode', mode, (r: StellariumBridgeResponse) => {
      const data = r as ArPreviewBridgeResponse
      if (!this.store.arCameraActive) {
        this.store.arPreviewStatus = data.previewOnly === true
          ? (mode === 'off' ? '预研预览已关闭。' : '当前显示离线 AR 遮罩预研预览。')
          : 'AR 模式已更新。'
      }
    }, () => {
      if (!this.store.arCameraActive) {
        this.store.arPreviewStatus = 'AR 模式切换失败。'
      }
    })
  }

  // 调整地景抠除进度（0..1）；逐帧只发 fire-and-forget，避免拖动时 GC 压力。
  setRevealProgress(value: number): void {
    if (!Number.isFinite(value)) return
    this.store.arRevealProgress = Math.max(0, Math.min(1, value))
    this.port.fire('setARRevealProgress', this.store.arRevealProgress.toFixed(3))
  }
}
