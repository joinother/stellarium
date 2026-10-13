// AR 预研控制器。
//
// 管理离线 AR 预研的三种控制器动作：能力探测、模式切换、地景抠除进度。本类不 import NAPI/UI：
// 桥调用走 CommandPort（探测 / 切换）与 fire（逐帧进度不解析回包），UI 提示经 ARHostHooks 回注。
// 当前为无相机预研：不会打开摄像头，只验证「只保留星空、逐步抠除地景」的视觉逻辑。
import { CommandPort } from '../bridge/CommandPort'
import { ARStore } from '../state/ARStore'
import { StellariumBridgeResponse } from '../common/types/StellariumTypes'

// AR 能力探测 / 模式切换回包。
export interface ArPreviewBridgeResponse extends StellariumBridgeResponse {
  previewShell?: boolean
  previewOnly?: boolean
}

// 宿主 → 控制器回注：UI 提示。
export interface ARHostHooks {
  flashHint(text: ResourceStr): void
}

export class ARController {
  private store: ARStore
  private port: CommandPort
  private hooks: ARHostHooks

  constructor(store: ARStore, port: CommandPort, hooks: ARHostHooks) {
    this.store = store
    this.port = port
    this.hooks = hooks
  }

  // 探测 AR 预研能力（当前恒为无相机预研壳）。
  loadCapabilities(): void {
    this.port.requestInteractive('getARCapabilities', '', (r: StellariumBridgeResponse) => {
      const data = r as ArPreviewBridgeResponse
      this.store.arPreviewStatus = data.previewShell === true
        ? '当前为无相机预研预览；真正 AR 需要设备能力检测和用户授权。'
        : 'AR 能力尚未就绪。'
    }, () => {
      this.store.arPreviewStatus = 'AR 能力检测失败，仍可查看离线预研动效。'
    })
  }

  // 切换 AR 预研模式；切到“只保留星空”时进度直接拉满。
  setMode(mode: string): void {
    if (mode !== 'off' && mode !== 'overlay' && mode !== 'portal' && mode !== 'depth' && mode !== 'sky-only') return
    this.store.arPreviewMode = mode
    if (mode === 'sky-only') this.store.arRevealProgress = 1
    this.port.requestInteractive('setARMode', mode, (r: StellariumBridgeResponse) => {
      const data = r as ArPreviewBridgeResponse
      this.store.arPreviewStatus = data.previewOnly === true
        ? (mode === 'off' ? '预研预览已关闭。' : '当前显示无相机 AR 预研预览。')
        : 'AR 模式已更新。'
    }, () => {
      this.store.arPreviewStatus = 'AR 模式切换失败。'
    })
  }

  // 调整地景抠除进度（0..1）；逐帧只发 fire-and-forget，避免拖动时 GC 压力。
  setRevealProgress(value: number): void {
    if (!Number.isFinite(value)) return
    this.store.arRevealProgress = Math.max(0, Math.min(1, value))
    this.port.fire('setARRevealProgress', this.store.arRevealProgress.toFixed(3))
  }
}
