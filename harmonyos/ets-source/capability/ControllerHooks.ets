// 行为控制器共享的宿主 hook 契约。
//
// 控制器经此回调宿主，**不 import 宿主**；本文件是纯接口，不 import NAPI / UI / 宿主。
// 后续控制器接口可 `extends BehaviorHostHooks`，例如 capability/DetailConnectorController.ets
// 的 `DetailConnectorHostHooks`。
export interface BehaviorHostHooks {
  // 宿主 refreshState()：生命周期收口。
  refreshState(): void
  // 宿主 flashHint()（UI 提示）。
  flashHint(text: ResourceStr): void
  // 面板路由：宿主 activePanel / panelVisible 写入 + Dock 时钟收口
  //（宿主传 `() => { this.activePanel = panel; this.panelVisible = visible; this.syncDockClockTimer() }`）。
  panelChange(panel: string, visible: boolean): void
}
