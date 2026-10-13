// 命令桥调用端口：以纯接口描述域 store / 控制器所需的桥请求语义，
// 使其无需 import libentry.so / NAPI / UI 即可发起命令并解析回包。
// 五种方法各对应一种桥调用策略：同步、启动期重试、短轮询、长任务进度、fire-and-forget。
// 宿主在 aboutToAppear 注入具名实现 HostCommandPort（MainWindowNativeNode.ets）。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'

export interface CommandPort {
  // 同步请求：立即返回回包；桥未就绪时为 { ok: false }。
  request(name: string, payload?: string): StellariumBridgeResponse
  // 启动期重试请求：桥未就绪时按固定退避重试（默认 200ms × 60）。
  // attempt / intervalMs / maxAttempts 可选，缺省由适配器填入；个别加载器可显式覆盖重试参数。
  requestWhenReady(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, attempt?: number, intervalMs?: number, maxAttempts?: number): void
  // 交互命令（tap-select / search / get-info / move-to）：快速轮询。
  requestInteractive(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void): void
  // 长任务：进度回调 + 最大尝试次数 + 取消判定。
  requestLongRunning(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, onProgress?: (r: StellariumBridgeResponse) => void, maxAttempts?: number, isCancelled?: () => boolean): void
  // Fire-and-forget：不解析回包，减少拖动时的 GC 压力。
  fire(name: string, payload?: string): void
}
