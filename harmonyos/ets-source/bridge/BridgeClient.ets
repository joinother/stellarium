import { command } from 'libentry.so'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'

// 命令桥的唯一出口：ArkTS 侧只在这里触碰 libentry.so 导出的 command()。
// 录制（recordAcceptedCommand）与错误上报留在宿主，桥本身只负责收发与重试。
export class BridgeClient {
  // 发送命令并解析 JSON 回包；桥未就绪或解析失败统一返回 { ok: false }。
  static request(name: string, payload: string = ''): StellariumBridgeResponse {
    try {
      return JSON.parse(command(name, payload)) as StellariumBridgeResponse
    } catch (err) {
      return { ok: false, error: 'bridge parse failed' }
    }
  }

  // Fire-and-forget：只发不收原始回包，减少拖动时的 GC 压力。
  // 用于 dragView / zoomBy / panBy 等不需要返回值的连续命令。
  static send(name: string, payload: string = ''): string {
    try {
      return command(name, payload)
    } catch (err) {
      return ''
    }
  }

  // Retry a native command until the Stellarium core is initialized.
  // At startup the ArkUI thread may call the bridge before Qt has finished
  // bootstrapping; those calls return ok:false and are retried on a short
  // backoff instead of crashing the process.
  static requestWhenReady(name: string, payload: string = '', onOk?: (r: StellariumBridgeResponse) => void, attempt: number = 0, intervalMs: number = 200, maxAttempts: number = 60, onFailure?: (r: StellariumBridgeResponse) => void): void {
    const r = BridgeClient.request(name, payload)
    if (r.ok === true) {
      if (onOk) onOk(r)
      return
    }
    if (attempt < maxAttempts) {
      setTimeout(() => BridgeClient.requestWhenReady(name, payload, onOk, attempt + 1, intervalMs, maxAttempts, onFailure), intervalMs)
    } else if (onFailure) {
      onFailure(r)
    }
  }

  // Interactive commands (tap-select, search, get-info, move-to) run on the
  // OHOS render pump one frame later and are delivered via a consume-on-read
  // store on the C++ side, so the first call returns {pending}. Poll fast
  // (50ms x 40 = 2s) so a single tap/search resolves without a visible delay
  // and WITHOUT blocking the render thread. onOk receives the FRESH result.
  static requestInteractive(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void): void {
    BridgeClient.requestWhenReady(name, payload, onOk, 0, 100, 15, onFailure)
  }
}
