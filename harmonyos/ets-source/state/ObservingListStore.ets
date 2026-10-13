import hilog from '@ohos.hilog'
import { parseObservingList } from '../common/derive/skycult'

// 宿主注入的 Preferences 读写助手（store 不 import NAPI/UI 上下文，preferences + getUIContext
// 职责整体经 hooks 提供）；parseObservingList 是纯函数，store 直接 import。
export interface ObservingListHostHooks {
  // 读 Preferences 'observingList' 原始 JSON（无则 ''）；宿主用 @ohos.data.preferences 实现。
  readObservingListStorage(): Promise<string>
  // 首次读取时把内存值迁移写回 Preferences；宿主用 @ohos.data.preferences 实现。
  writeObservingListStorage(json: string): Promise<void>
  // 持久化当前观测列表到 Preferences（宿主用 @ohos.data.preferences 实现）。
  saveObservingListStorage(): void
}

// 观测列表（observing list）域状态：持有 observingList（用户收藏天体英文名，持久化于
// Preferences / AppStorage 的 'observingList' 键）与 observingListReady（首次加载完成标志）。
// 独立成 store 的原因：这是跨选中天体的独立用户数据，与选中状态无生命周期绑定，不同于
// ObjectDetailStore 的瞬时详情与 AstroStore 的派生计算。消费面板 ObservingPanel / ObjectPanel /
// ConfigFallbackPanel 以 @ObjectLink 观察。所有写入均为字段整体赋值（无 Array 原地变更）。
@Observed
export class ObservingListStore {
  observingList: string[] = []
  observingListReady: boolean = false

  // 宿主 Preferences / UI 上下文注入（供 loadObservingListFromStorage 使用）。
  private hooks: ObservingListHostHooks | null = null

  attachHooks(hooks: ObservingListHostHooks): void {
    this.hooks = hooks
  }

  // 持久化观测列表：写 AppStorage，并委托宿主写入 Preferences。
  persistObservingList(): void {
    AppStorage.setOrCreate('observingList', JSON.stringify(this.observingList))
    const hooks = this.hooks
    if (hooks !== null) {
      hooks.saveObservingListStorage()
    }
  }

  // 首次启动从 Preferences 载入观测列表；空库时把内存值迁移写回 Preferences。
  // Preferences I/O 经 hooks（store 不 import NAPI/UI）。
  async loadObservingListFromStorage(): Promise<void> {
    const hooks = this.hooks
    try {
      const jsonStr: string = hooks !== null ? await hooks.readObservingListStorage() : ''
      if (jsonStr.length > 0) {
        this.observingList = parseObservingList(jsonStr)
      } else if (this.observingList.length > 0 && hooks !== null) {
        // Migrate the pre-existing in-memory value on the first durable read.
        await hooks.writeObservingListStorage(JSON.stringify(this.observingList))
      }
      AppStorage.setOrCreate('observingList', JSON.stringify(this.observingList))
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'load observing list failed: %{public}s', String(e))
    } finally {
      this.observingListReady = true
    }
  }
}
