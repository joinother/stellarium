// 音频（audio）域状态：背景音乐开关 musicEnabled、天体与交互音效开关 sfxEnabled、主音量 audioVolume、
// 以及 Aetheris 千人千面程序化音景 DNA（audioMood / audioMaterial / audioSeed）。
// 播放 / 静音 / 音量 / DNA 副作用经 AudioStoreHooks 具名回注，store 不 import NAPI。

import {
  AetherisMaterialPreset,
  AetherisMoodId,
  normalizeAetherisMaterial,
  normalizeAetherisMood
} from '../capability/AudioCatalog'

export interface AudioStoreHooks {
  setMusicPlaying(enabled: boolean): void
  setSfxEnabled(enabled: boolean): void
  setAudioVolume(volume: number): void
  setAetherisMood(mood: AetherisMoodId): void
  setAetherisMaterial(preset: AetherisMaterialPreset): void
  randomizeAetherisSeed(): void
  skipNextAct(): void
  playAudioLogo(): void
  persistAudioSettings(): void
  flashHint(text: ResourceStr): void
}

@Observed
export class AudioStore {
  musicEnabled: boolean = false
  sfxEnabled: boolean = true
  audioVolume: number = 0.7
  audioMood: AetherisMoodId = 'newmoon'
  audioMaterial: AetherisMaterialPreset = 'jade'
  audioSeed: string = 'SkyInstrument-01'

  private hooks: AudioStoreHooks | null = null
  private lastMusicToggle: number = 0

  attachHooks(hooks: AudioStoreHooks): void {
    this.hooks = hooks
  }

  toggleMusic(): void {
    const now = Date.now()
    if (now - this.lastMusicToggle < 350) { return }
    this.lastMusicToggle = now
    this.setMusicEnabled(!this.musicEnabled, true)
  }

  setMusicEnabled(enabled: boolean, notifyHint: boolean = false): void {
    this.musicEnabled = enabled
    const hooks = this.hooks
    if (hooks !== null) { hooks.setMusicPlaying(enabled) }
    this.persistAudioSettings()
    if (notifyHint && hooks !== null) {
      hooks.flashHint(this.musicEnabled ? '音乐：开 ♪' : '音乐：静音')
    }
  }

  setSfxEnabled(enabled: boolean): void {
    this.sfxEnabled = enabled
    const hooks = this.hooks
    if (hooks !== null) { hooks.setSfxEnabled(enabled) }
    this.persistAudioSettings()
  }

  setAudioVolume(value: number): void {
    const clamped = Number.isFinite(value) ? Math.max(0.0, Math.min(1.0, value)) : 0.7
    this.audioVolume = clamped
    const hooks = this.hooks
    if (hooks !== null) { hooks.setAudioVolume(clamped) }
    this.persistAudioSettings()
  }

  setAudioMood(mood: AetherisMoodId): void {
    const norm = normalizeAetherisMood(mood)
    this.audioMood = norm
    const hooks = this.hooks
    if (hooks !== null) { hooks.setAetherisMood(norm) }
    this.persistAudioSettings()
  }

  setAudioMaterial(preset: AetherisMaterialPreset): void {
    const norm = normalizeAetherisMaterial(preset)
    this.audioMaterial = norm
    const hooks = this.hooks
    if (hooks !== null) { hooks.setAetherisMaterial(norm) }
    this.persistAudioSettings()
  }

  syncGeneratedSeed(seed: string, mood: AetherisMoodId, material: AetherisMaterialPreset): void {
    this.audioSeed = seed
    this.audioMood = normalizeAetherisMood(mood)
    this.audioMaterial = normalizeAetherisMaterial(material)
    this.persistAudioSettings()
  }

  randomizeDna(): void {
    const hooks = this.hooks
    if (hooks !== null) { hooks.randomizeAetherisSeed() }
  }

  skipNextAct(): void {
    const hooks = this.hooks
    if (hooks !== null) { hooks.skipNextAct() }
  }

  playAudioLogo(): void {
    const hooks = this.hooks
    if (hooks !== null) { hooks.playAudioLogo() }
  }

  persistMusicEnabled(): void {
    this.persistAudioSettings()
  }

  persistAudioSettings(): void {
    let obj: Record<string, boolean | string | number> = {}
    const cur = AppStorage.get<string>('stellariumSettings')
    if (cur) {
      try { obj = JSON.parse(cur) as Record<string, boolean | string | number> } catch (_e) { }
    }
    obj['musicEnabled'] = this.musicEnabled
    obj['sfxEnabled'] = this.sfxEnabled
    obj['audioVolume'] = this.audioVolume
    obj['audioMood'] = this.audioMood
    obj['audioMaterial'] = this.audioMaterial
    obj['audioSeed'] = this.audioSeed
    AppStorage.setOrCreate('stellariumSettings', JSON.stringify(obj))
    const hooks = this.hooks
    if (hooks !== null) {
      hooks.persistAudioSettings()
    }
  }
}
