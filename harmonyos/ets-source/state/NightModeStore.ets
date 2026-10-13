// 夜视模式（红光）状态。
//
// 为什么单独一份 store：夜视模式是全局视觉模式，状态需被宿主之外的组件共享
//（时间面板与图层页共用的夜间模式开关行）。宿主以 @State 持有本 store，`nm*()` 系列配色
// 方法读 this.nightModeStore.nightMode，组件以 @ObjectLink 订阅同一实例。自持 CommandPort，
// 并在 store 内直接完成 AppStorage 持久化。
// 只 import 纯接口 CommandPort（不触碰 libentry.so / @ohos.*）。
import { CommandPort } from '../bridge/CommandPort'

@Observed
export class NightModeStore {
  nightMode: boolean = false

  // —— 桥注入（本 store 唯一桥调用是同步 request('setNightMode')） ——
  private port: CommandPort | null = null
  // 换挡瞬间 / 轮询（约每 3 s）可能回报旧值，故设"待定窗口"抑制陈旧回报。
  private pendingNightMode: boolean | undefined = undefined
  private pendingNightModeUntilMs: number = 0

  attachPort(port: CommandPort): void {
    this.port = port
  }

  // 引擎回报的夜视状态落库。换挡瞬间 / 轮询（约每 3 s）可能回报旧值，
  // 因此在"待定窗口"内忽略与待定值不一致的回报，避免刚打开又被旧值翻回去
  //（与 syncTimeRateState 的去重窗口同一套路）。
  syncNightModeFromEngine(engineNight: boolean): void {
    if (this.pendingNightMode !== undefined) {
      const matches = engineNight === this.pendingNightMode
      if (!matches && Date.now() < this.pendingNightModeUntilMs) { return }
      this.pendingNightMode = undefined
      this.pendingNightModeUntilMs = 0
    }
    this.nightMode = engineNight
  }

  // 夜视模式统一入口：写状态 + 可选持久化 + 下发原生命令。
  // 时间面板的夜视开关与主界面独立按钮都走这一个入口。
  applyNightMode(enabled: boolean, persist: boolean): void {
    this.pendingNightMode = enabled
    this.pendingNightModeUntilMs = Date.now() + 3500
    this.nightMode = enabled
    if (persist) { this.persistNightMode() }
    const port = this.port
    if (port !== null) {
      port.request('setNightMode', enabled ? 'true' : 'false')
    }
  }

  // AppStorage 读写不属 NAPI，故持久化在 store 内直接完成。
  persistNightMode(): void {
    let obj: Record<string, boolean | string> = {}
    const cur = AppStorage.get<string>('stellariumSettings')
    if (cur) {
      try { obj = JSON.parse(cur) as Record<string, boolean | string> } catch (e) { }
    }
    obj['nightMode'] = this.nightMode
    AppStorage.setOrCreate('stellariumSettings', JSON.stringify(obj))
  }

  // 夜视模式颜色方案：开/关两套色值，供面板与按钮读取。
  nmText(): string {
    return this.nightMode ? '#FF6644' : '#E5FFFFFF'
  }
  nmSub(): string {
    return this.nightMode ? '#CC5533' : '#99FFFFFF'
  }
  nmAccent(): string {
    return this.nightMode ? '#FF5533' : '#5B93BF'
  }
  nmBg(): string {
    return this.nightMode ? 'rgba(180, 40, 20, 0.12)' : 'rgba(255,255,255,0.04)'
  }
  nmBorder(): string {
    return this.nightMode ? 'rgba(200, 60, 30, 0.20)' : 'rgba(255,255,255,0.08)'
  }
  nmInput(): string {
    return this.nightMode ? 'rgba(120, 30, 15, 0.50)' : 'rgba(255,255,255,0.06)'
  }
  nmInputBorder(): string {
    return this.nightMode ? 'rgba(200, 60, 30, 0.25)' : 'rgba(214, 238, 255, 0.14)'
  }
  nmPickerSurface(): string {
    return this.nightMode ? '#32120D' : '#101A2B'
  }
  nmPickerHeader(): string {
    return this.nightMode ? '#48170F' : '#18263B'
  }
  nmPickerHeaderActive(): string {
    return this.nightMode ? '#5D1D12' : '#1E3A54'
  }
  nmPickerSelected(): string {
    return this.nightMode ? '#8A2B1B' : '#285F84'
  }
  nmPickerOption(): string {
    return this.nightMode ? '#41160F' : '#172338'
  }
}
