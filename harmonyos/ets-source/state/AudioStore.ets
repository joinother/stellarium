// 音频（audio）域状态：背景音乐开关 musicEnabled 与音量 audioVolume，同为 AudioPanel 入参，
// 由面板以 @ObjectLink 订阅，持久化于 AppStorage 的 'stellariumSettings' 键。
// 本 store 自持 toggleMusic / persistMusicEnabled；播放 / 静音副作用（AudioEngine 为原生桥）
// 经 AudioStoreHooks 具名回注，store 不 import NAPI。
//
// 约束：两字段均为布尔 / 数值整体赋值，无原地变更。
export interface AudioStoreHooks {
  // 背景音乐引擎开关（宿主 AudioEngine.start()/setMuted）。
  setMusicPlaying(enabled: boolean): void
  // UI 提示（宿主 flashHint）。
  flashHint(text: ResourceStr): void
}

@Observed
export class AudioStore {
  musicEnabled: boolean = false
  audioVolume: number = 0.7

  private hooks: AudioStoreHooks | null = null
  // 350ms 防抖时间戳：避免坐标命中与 onClick 双触发导致来回跳（不可观测，不入 store 数据面）。
  private lastMusicToggle: number = 0

  attachHooks(hooks: AudioStoreHooks): void {
    this.hooks = hooks
  }

  // 防抖后翻转开关、下发引擎、持久化并提示。
  toggleMusic(): void {
    const now = Date.now()
    if (now - this.lastMusicToggle < 350) { return }
    this.lastMusicToggle = now
    this.musicEnabled = !this.musicEnabled
    const hooks = this.hooks
    if (hooks !== null) { hooks.setMusicPlaying(this.musicEnabled) }
    this.persistMusicEnabled()
    if (hooks !== null) { hooks.flashHint(this.musicEnabled ? '音乐：开 ♪' : '音乐：静音') }
  }

  // 写 AppStorage 的 'stellariumSettings'（AppStorage 非 NAPI，可在 store 内直接使用）。
  persistMusicEnabled(): void {
    let obj: Record<string, boolean | string> = {}
    const cur = AppStorage.get<string>('stellariumSettings')
    if (cur) {
      try { obj = JSON.parse(cur) as Record<string, boolean | string> } catch (e) { }
    }
    obj['musicEnabled'] = this.musicEnabled
    AppStorage.setOrCreate('stellariumSettings', JSON.stringify(obj))
  }
}
