import { CommandPort } from '../bridge/CommandPort'


// 夜间模式状态：布尔开关 + AppStorage 镜像 + 引擎/持久化桥。
// 颜色不再由本 store 提供；组件统一经 WithTheme → onWillApplyTheme → ThemeSlots 取色。

// 本地切换后等待引擎回执/回读一致的兜底窗口；覆盖两轮 requestInteractive
// （每轮 100ms × 15 ≈ 1.5s）再加余量。只作最后防线，新旧判断以 requestEpoch 为准；
// 终态失败会立即清空该窗口，不会拖慢纠正。
const NIGHT_MODE_PENDING_GUARD_MS: number = 4000

@Observed
export class NightModeStore {
  nightMode: boolean = false

  private port: CommandPort | null = null
  private pendingNightMode: boolean | undefined = undefined
  private pendingNightModeUntilMs: number = 0
  // 本地切换序号：每次 applyNightMode 递增。带旧序号的引擎快照（如面板打开触发的
  // getState / getNightMode 回包）一律丢弃，避免慢链路用切换前的值覆盖主题。
  private requestEpoch: number = 0
  private persistFn: ((nightMode: boolean) => void) | null = null

  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachPersistFn(fn: (nightMode: boolean) => void): void {
    this.persistFn = fn
  }

  nightModeEpoch(): number {
    return this.requestEpoch
  }

  // 唯一提交点：清待定窗口、写 store/AppStorage，值变化时同步首帧缓存。
  private commitNightMode(actual: boolean): void {
    this.pendingNightMode = undefined
    this.pendingNightModeUntilMs = 0
    const changed = this.nightMode !== actual
    this.nightMode = actual
    AppStorage.setOrCreate('stellariumNightMode', actual)
    if (changed) { this.persistNightMode() }
  }

  syncNightModeFromEngine(engineNight: boolean, requestEpoch: number): void {
    if (requestEpoch !== this.requestEpoch) { return }
    if (this.pendingNightMode !== undefined) {
      const matches = engineNight === this.pendingNightMode
      if (!matches && Date.now() < this.pendingNightModeUntilMs) { return }
    }
    this.commitNightMode(engineNight)
  }

  // 夜间模式写回：用带回执的交互请求，失败自动重试一次，避免首击命令丢失。
  private sendNightMode(enabled: boolean, allowRetry: boolean, epoch: number): void {
    const port = this.port
    if (port === null) return
    // 参数后缀让桥的 consume-on-read 缓存键带上本次切换序号：旧的同名回执
    // （如 ON→OFF→ON 中第一次 ON 的 true）不会再被后续请求消费。
    const payload = (enabled ? 'true' : 'false') + '|' + epoch.toString()
    port.requestInteractive('setNightMode', payload, (r) => {
      if (epoch !== this.requestEpoch) return
      this.commitNightMode(r.night === true)
    }, () => {
      if (epoch !== this.requestEpoch) return
      if (allowRetry) {
        this.sendNightMode(enabled, false, epoch)
      } else {
        // 终态失败：放开待定窗口，让引擎回报成为唯一权威值。
        this.pendingNightMode = undefined
        this.pendingNightModeUntilMs = 0
      }
    })
  }

  applyNightMode(enabled: boolean, persist: boolean): void {
    const epoch = ++this.requestEpoch
    this.pendingNightMode = enabled
    this.pendingNightModeUntilMs = Date.now() + NIGHT_MODE_PENDING_GUARD_MS
    this.nightMode = enabled
    AppStorage.setOrCreate('stellariumNightMode', enabled)
    if (persist) { this.persistNightMode() }
    this.sendNightMode(enabled, true, epoch)
  }

  persistNightMode(): void {
    // 夜间模式是引擎行为，权威值是 config.ini 的 viewing/flag_night（由 C++ setter 写入）。
    // 这里只更新首帧主题缓存，不写 UI 设置 JSON，避免形成第二个权威源。
    AppStorage.setOrCreate('stellariumNightMode', this.nightMode)
    if (this.persistFn) { this.persistFn(this.nightMode) }
  }

}
