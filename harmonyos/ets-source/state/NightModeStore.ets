import { CommandPort } from '../bridge/CommandPort'


// 夜间模式状态：布尔开关 + AppStorage 镜像 + 引擎/持久化桥。
// 颜色不再由本 store 提供；组件统一经 WithTheme → onWillApplyTheme → ThemeSlots 取色。

@Observed
export class NightModeStore {
  nightMode: boolean = false

  private port: CommandPort | null = null
  private pendingNightMode: boolean | undefined = undefined
  private pendingNightModeUntilMs: number = 0
  private persistFn: ((nightMode: boolean) => void) | null = null

  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachPersistFn(fn: (nightMode: boolean) => void): void {
    this.persistFn = fn
  }

  syncNightModeFromEngine(engineNight: boolean): void {
    if (this.pendingNightMode !== undefined) {
      const matches = engineNight === this.pendingNightMode
      if (!matches && Date.now() < this.pendingNightModeUntilMs) { return }
      this.pendingNightMode = undefined
      this.pendingNightModeUntilMs = 0
    }
    const changed = this.nightMode !== engineNight
    this.nightMode = engineNight
    AppStorage.setOrCreate('stellariumNightMode', engineNight)
    // Keep the first-frame cache in step with the engine. It used to be written
    // only by ArkTS-initiated toggles, so a night mode restored from config.ini
    // (or changed through the CLI) left the next launch's splash/UI in day mode
    // until the engine sync arrived.
    if (changed) { this.persistNightMode() }
  }

  // 夜间模式写回：用带回执的交互请求，失败自动重试一次，避免首击命令丢失。
  private sendNightMode(enabled: boolean, allowRetry: boolean): void {
    const port = this.port
    if (port === null) return
    port.requestInteractive('setNightMode', enabled ? 'true' : 'false', (r) => {
      if (r.ok !== true) {
        if (allowRetry) this.sendNightMode(enabled, false)
        return
      }
      const actual = r.night === true
      this.pendingNightMode = undefined
      this.pendingNightModeUntilMs = 0
      this.nightMode = actual
      AppStorage.setOrCreate('stellariumNightMode', actual)
    }, () => {
      if (allowRetry) this.sendNightMode(enabled, false)
    })
  }

  applyNightMode(enabled: boolean, persist: boolean): void {
    this.pendingNightMode = enabled
    this.pendingNightModeUntilMs = Date.now() + 1000
    this.nightMode = enabled
    AppStorage.setOrCreate('stellariumNightMode', enabled)
    if (persist) { this.persistNightMode() }
    this.sendNightMode(enabled, true)
  }

  persistNightMode(): void {
    // 夜间模式是引擎行为，权威值是 config.ini 的 viewing/flag_night（由 C++ setter 写入）。
    // 这里只更新首帧主题缓存，不写 UI 设置 JSON，避免形成第二个权威源。
    AppStorage.setOrCreate('stellariumNightMode', this.nightMode)
    if (this.persistFn) { this.persistFn(this.nightMode) }
  }

}
