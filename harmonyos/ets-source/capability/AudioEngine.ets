// AudioEngine.ets
// 鸿蒙原生双层观星音频引擎（背景氛围层 + 天体复音音效层 + UI 微交互层 + 音频会话治理）。
//
// 架构设计：
//   1. 音频会话与焦点治理（@kit.AudioKit AudioSessionManager）：
//      - 开启背景音乐时申领默认音频会话（CONCURRENCY_DEFAULT），并监听系统打断（来电/闹钟/外部播放）自动暂停。
//      - 仅开启天体/UI 音效（关闭背景音乐）时使用混音模式（CONCURRENCY_MIX_WITH_OTHERS），不打断用户外部音乐播放。
//      - 退入后台或全部静音/空闲时停用会话并释放播放器，零后台功耗。
//   2. 背景氛围层（Dual-Track Ping-Pong AVPlayer）：
//      - 双 AVPlayer 乒乓预排衔接，消除普通 loop 的首尾停顿；支持 900ms 平滑淡入淡出与导览自动压低（ducking）。
//      - 自动探测沙箱热更新目录（filesDir/audio/...）及 rawfile（stellarium/audio/...）中的原创 .m4a 主题。
//   3. 天体复音音效层（AVPlayer 复音池，最多 6 路并发）：
//      - 按 AudioCatalog 语义映射（恒星 7 光谱、行星、深空、星座 15 轮转、卫星/天宫/ISS、多波段）+ 统一 dBFS 增益分级播放。
//      - 播完自动归还复用，空闲 25 秒自动释放底层句柄。
//   4. UI 微交互层（@kit.MediaKit SoundPool）：
//      - 仅在存在 ui/*.m4a 资源时惰性初始化低延迟 SoundPool，按最小触发间隔节流，与触感反馈同步。
//   5. 零中断立体声内置回退（Built-in Stereo Fallback）：
//      - 当外部/内置 .m4a 音景包尚未放入时，自动回退至升级后的 48kHz 立体声内置合成器；
//      - 背景音乐与天体音效完全独立门控，且在无背景乐且和弦衰减完毕后自动停止释放 AudioRenderer，彻底消除空转耗电。

import { audio } from '@kit.AudioKit'
import { media } from '@kit.MediaKit'
import { common } from '@kit.AbilityKit'
import { resourceManager } from '@kit.LocalizationKit'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import hilog from '@ohos.hilog'
import nativeEntry from 'libentry.so'
import type { StellariumBridgeResponse } from '../pages/StellariumTypes'
import {
  AMBIENT_CROSSFADE_MS,
  AMBIENT_DUCK_OFFSET_DB,
  AMBIENT_FADE_MS,
  AUDIO_RAW_ROOT,
  AetherisMaterialPreset,
  AetherisMoodId,
  AudioRotationState,
  DEFAULT_AMBIENT_GAIN_DB,
  DEFAULT_AMBIENT_THEME_PATH,
  ResolvedCelestialCue,
  UiAudioCueKind,
  UiAudioCueSpec,
  allUiAudioCueSpecs,
  clampVolume,
  dbToLinear,
  getUiAudioCueSpec,
  hashStableName,
  materialWeightsForPreset,
  normalizeAetherisMaterial,
  normalizeAetherisMood,
  resolveBandAudioCue,
  resolveCelestialAudioCue
} from './AudioCatalog'

const TAG: string = 'SkyAudioEngine'
const DOMAIN: number = 0xD003
const SR: number = 48000
const MAX_CELESTIAL_VOICES: number = 4
const SFX_CROSSFADE_OUT_MS: number = 500
const SFX_VOICE_IDLE_GC_MS: number = 25000
const FALLBACK_IDLE_RELEASE_SAMPLES: number = SR * 3

const RANDOM_DNA_SEEDS: string[] = [
  'Tibet-Ali-DarkSky',
  'Dunhuang-StarMap',
  'Reykjavik-Aurora-64N',
  'Qinghai-MilkyWay',
  'Lijiang-Observatory',
  'Atacama-NewMoon',
  'Kyoto-Equinox',
  'Beijing-Solstice'
]

interface AetherisSeedResult {
  seed: string
  mood: AetherisMoodId
  rootPc: number
  jade: number
  felt: number
  tape: number
  bowl: number
}

interface AudioSourceLocation {
  kind: 'file' | 'rawfile'
  path: string
}

export interface AudioEngineStatusSnapshot {
  musicEnabled: boolean
  sfxEnabled: boolean
  volume: number
  foreground: boolean
  ducked: boolean
  interruptedBySystem: boolean
  bundledAssetCount: number
  musicBackend: 'avplayer' | 'fallback' | 'idle'
  sessionMode: 'none' | 'default' | 'mix'
}

// ───────────────────────── AVPlayer 封装：单路天体复音槽 ─────────────────────────

class CelestialVoiceSlot {
  readonly id: number
  player: media.AVPlayer | undefined = undefined
  busy: boolean = false
  fadingOut: boolean = false
  startedAt: number = 0
  lastUsedAt: number = 0
  activeRawFdPath: string = ''
  activeFileFd: number = -1
  private targetVolume: number = 0.5
  private fadeTimer: number = 0
  private disposed: boolean = false
  private onFinished: (slot: CelestialVoiceSlot) => void

  constructor(id: number, onFinished: (slot: CelestialVoiceSlot) => void) {
    this.id = id
    this.onFinished = onFinished
  }

  async play(
    source: AudioSourceLocation,
    volume: number,
    resMgr: resourceManager.ResourceManager | undefined
  ): Promise<boolean> {
    this.clearFadeTimer()
    this.disposed = false
    this.fadingOut = false
    this.targetVolume = clampVolume(volume)
    this.busy = true
    this.startedAt = Date.now()
    this.lastUsedAt = this.startedAt

    try {
      await this.resetInternal(resMgr)
      if (!this.player) {
        const created = await media.createAVPlayer()
        this.player = created
        this.bindEvents(created, resMgr)
      }
      const p = this.player
      if (!p) {
        this.busy = false
        return false
      }
      if (source.kind === 'rawfile') {
        if (!resMgr) {
          this.busy = false
          return false
        }
        const rawFd: resourceManager.RawFileDescriptor = await resMgr.getRawFd(source.path)
        this.activeRawFdPath = source.path
        const fdSrc: media.AVFileDescriptor = {
          fd: rawFd.fd,
          offset: rawFd.offset,
          length: rawFd.length
        }
        p.fdSrc = fdSrc
      } else {
        const file = fileIo.openSync(source.path, fileIo.OpenMode.READ_ONLY)
        this.activeFileFd = file.fd
        p.url = `fd://${file.fd}`
      }
      return true
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'sfx slot %{public}d play failed: %{public}s', this.id, (e as Error).message ?? String(e))
      this.busy = false
      await this.closeOwnedFd(resMgr)
      return false
    }
  }

  updateVolume(volume: number): void {
    this.targetVolume = clampVolume(volume)
    const p = this.player
    if (!p || !this.busy || this.fadingOut) {
      return
    }
    const st = p.state
    if (st === 'prepared' || st === 'playing' || st === 'paused' || st === 'completed') {
      try {
        p.setVolume(this.targetVolume)
      } catch (_e) { }
    }
  }

  // 新天体声部入场时平滑淡出旧声部，防止快速连点导致低中频浑浊叠音（嗡嗡响）
  fadeOutAndStop(fadeMs: number, resMgr: resourceManager.ResourceManager | undefined): void {
    if (!this.busy || this.fadingOut) {
      return
    }
    this.fadingOut = true
    this.clearFadeTimer()
    const stepMs = 40
    const steps = Math.max(2, Math.round(fadeMs / stepMs))
    let curStep = 0
    const startVol = this.targetVolume
    this.fadeTimer = setInterval(() => {
      curStep++
      const ratio = Math.max(0.0, 1.0 - curStep / steps)
      const p = this.player
      if (p) {
        const st = p.state
        if (st === 'prepared' || st === 'playing' || st === 'paused' || st === 'completed') {
          try {
            p.setVolume(clampVolume(startVol * ratio * ratio))
          } catch (_e) { }
        }
      }
      if (curStep >= steps) {
        this.clearFadeTimer()
        this.fadingOut = false
        void this.stopAndReset(resMgr)
      }
    }, stepMs) as number
  }

  private clearFadeTimer(): void {
    if (this.fadeTimer !== 0) {
      clearInterval(this.fadeTimer)
      this.fadeTimer = 0
    }
  }

  async stopAndReset(resMgr: resourceManager.ResourceManager | undefined): Promise<void> {
    this.clearFadeTimer()
    this.fadingOut = false
    this.busy = false
    await this.resetInternal(resMgr)
    this.onFinished(this)
  }

  async release(resMgr: resourceManager.ResourceManager | undefined): Promise<void> {
    this.clearFadeTimer()
    this.fadingOut = false
    this.disposed = true
    this.busy = false
    const p = this.player
    this.player = undefined
    if (p) {
      try {
        p.off('stateChange')
        p.off('error')
        await p.release()
      } catch (_e) { }
    }
    await this.closeOwnedFd(resMgr)
  }

  private bindEvents(p: media.AVPlayer, resMgr: resourceManager.ResourceManager | undefined): void {
    p.on('stateChange', (state: string) => {
      if (this.disposed || this.player !== p) {
        return
      }
      if (state === 'initialized') {
        try {
          const info: audio.AudioRendererInfo = {
            usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
            rendererFlags: 0
          }
          p.audioRendererInfo = info
          void p.prepare()
        } catch (_e) {
          this.finishSlot(resMgr)
        }
      } else if (state === 'prepared') {
        try {
          p.setVolume(this.targetVolume)
          void p.play()
        } catch (_e) {
          this.finishSlot(resMgr)
        }
      } else if (state === 'completed' || state === 'stopped' || state === 'error') {
        this.finishSlot(resMgr)
      }
    })
    p.on('error', (err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'sfx slot %{public}d error %{public}d: %{public}s', this.id, err.code, err.message)
      this.finishSlot(resMgr)
    })
  }

  private finishSlot(resMgr: resourceManager.ResourceManager | undefined): void {
    if (!this.busy) {
      return
    }
    this.busy = false
    this.lastUsedAt = Date.now()
    void this.closeOwnedFd(resMgr)
    this.onFinished(this)
  }

  private async resetInternal(resMgr: resourceManager.ResourceManager | undefined): Promise<void> {
    const p = this.player
    if (p) {
      try {
        if (p.state !== 'idle' && p.state !== 'released') {
          await p.reset()
        }
      } catch (_e) {
        try {
          await p.release()
        } catch (_e2) { }
        this.player = undefined
      }
    }
    await this.closeOwnedFd(resMgr)
  }

  private async closeOwnedFd(resMgr: resourceManager.ResourceManager | undefined): Promise<void> {
    if (this.activeRawFdPath.length > 0 && resMgr) {
      const path = this.activeRawFdPath
      this.activeRawFdPath = ''
      try {
        await resMgr.closeRawFd(path)
      } catch (_e) { }
    }
    if (this.activeFileFd >= 0) {
      const fd = this.activeFileFd
      this.activeFileFd = -1
      try {
        fileIo.closeSync(fd)
      } catch (_e) { }
    }
  }
}

// ───────────────────────── AVPlayer 封装：双轨无缝乒乓背景音乐槽 ─────────────────────────

class AmbientTrackSlot {
  readonly label: string
  player: media.AVPlayer | undefined = undefined
  active: boolean = false
  durationMs: number = 0
  currentGain: number = 0
  targetGain: number = 0
  handoffTriggered: boolean = false
  private rawFdPath: string = ''
  private fileFd: number = -1
  private readyToPlay: boolean = false

  constructor(label: string) {
    this.label = label
  }

  async start(
    source: AudioSourceLocation,
    initialGain: number,
    resMgr: resourceManager.ResourceManager | undefined,
    onTimeUpdate: (slot: AmbientTrackSlot, timeMs: number) => void,
    onCompleted: (slot: AmbientTrackSlot) => void,
    onError: (slot: AmbientTrackSlot) => void
  ): Promise<boolean> {
    await this.stopAndRelease(resMgr)
    this.active = true
    this.durationMs = 0
    this.currentGain = clampVolume(initialGain)
    this.targetGain = this.currentGain
    this.handoffTriggered = false
    this.readyToPlay = false

    try {
      const p = await media.createAVPlayer()
      this.player = p

      p.on('durationUpdate', (dur: number) => {
        if (this.player === p && dur > 0) {
          this.durationMs = dur
        }
      })
      p.on('timeUpdate', (timeMs: number) => {
        if (this.player === p && this.active) {
          onTimeUpdate(this, timeMs)
        }
      })
      p.on('stateChange', (state: string) => {
        if (this.player !== p || !this.active) {
          return
        }
        if (state === 'initialized') {
          try {
            const info: audio.AudioRendererInfo = {
              usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
              rendererFlags: 0
            }
            p.audioRendererInfo = info
            void p.prepare()
          } catch (_e) {
            onError(this)
          }
        } else if (state === 'prepared') {
          this.readyToPlay = true
          try {
            p.loop = false
            p.setVolume(this.currentGain)
            void p.play()
          } catch (_e) {
            onError(this)
          }
        } else if (state === 'completed') {
          onCompleted(this)
        } else if (state === 'error') {
          onError(this)
        }
      })
      p.on('error', (err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'ambient %{public}s error %{public}d: %{public}s', this.label, err.code, err.message)
        onError(this)
      })

      if (source.kind === 'rawfile') {
        if (!resMgr) {
          await this.stopAndRelease(resMgr)
          return false
        }
        const rawFd = await resMgr.getRawFd(source.path)
        this.rawFdPath = source.path
        const fdSrc: media.AVFileDescriptor = {
          fd: rawFd.fd,
          offset: rawFd.offset,
          length: rawFd.length
        }
        p.fdSrc = fdSrc
      } else {
        const file = fileIo.openSync(source.path, fileIo.OpenMode.READ_ONLY)
        this.fileFd = file.fd
        p.url = `fd://${file.fd}`
      }
      return true
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'ambient %{public}s start failed: %{public}s', this.label, (e as Error).message ?? String(e))
      await this.stopAndRelease(resMgr)
      return false
    }
  }

  applyGain(gain: number): void {
    this.currentGain = clampVolume(gain)
    const p = this.player
    if (!p || !this.readyToPlay) {
      return
    }
    const st = p.state
    if (st === 'prepared' || st === 'playing' || st === 'paused' || st === 'completed') {
      try {
        p.setVolume(this.currentGain)
      } catch (_e) { }
    }
  }

  async stopAndRelease(resMgr: resourceManager.ResourceManager | undefined): Promise<void> {
    this.active = false
    this.readyToPlay = false
    this.handoffTriggered = false
    this.durationMs = 0
    this.currentGain = 0
    this.targetGain = 0
    const p = this.player
    this.player = undefined
    if (p) {
      try {
        p.off('stateChange')
        p.off('timeUpdate')
        p.off('durationUpdate')
        p.off('error')
        await p.release()
      } catch (_e) { }
    }
    if (this.rawFdPath.length > 0 && resMgr) {
      const path = this.rawFdPath
      this.rawFdPath = ''
      try {
        await resMgr.closeRawFd(path)
      } catch (_e) { }
    }
    if (this.fileFd >= 0) {
      const fd = this.fileFd
      this.fileFd = -1
      try {
        fileIo.closeSync(fd)
      } catch (_e) { }
    }
  }
}

// ───────────────────────── 主音频引擎单例 ─────────────────────────

export class AudioEngine {
  private static inst: AudioEngine | null = null
  static getInstance(): AudioEngine {
    if (!AudioEngine.inst) {
      AudioEngine.inst = new AudioEngine()
    }
    return AudioEngine.inst
  }

  private context: common.UIAbilityContext | undefined = undefined
  private resMgr: resourceManager.ResourceManager | undefined = undefined
  private sandboxAudioDir: string = ''
  private bundledAssets: Set<string> = new Set<string>()
  private assetScanDone: boolean = false

  // 用户偏好与运行态
  private musicEnabled: boolean = false
  private sfxEnabled: boolean = true
  private volume: number = 0.7
  private foreground: boolean = true
  private ducked: boolean = false
  private interruptedBySystem: boolean = false
  private activeThemePath: string = DEFAULT_AMBIENT_THEME_PATH

  // 音频会话治理
  private sessionManager: audio.AudioSessionManager | undefined = undefined
  private sessionMode: 'none' | 'default' | 'mix' = 'none'
  private sessionListenerBound: boolean = false

  // 背景音乐层（双轨乒乓 AVPlayer）
  private trackA: AmbientTrackSlot = new AmbientTrackSlot('A')
  private trackB: AmbientTrackSlot = new AmbientTrackSlot('B')
  private activeTrack: AmbientTrackSlot | null = null
  private fadeTimer: number = 0
  private musicBackend: 'avplayer' | 'fallback' | 'idle' = 'idle'
  private ambientMasterFade: number = 0
  private ambientMasterTarget: number = 0

  // 天体音效复音池（AVPlayer Pool）
  private sfxSlots: CelestialVoiceSlot[] = []
  private sfxIdleTimer: number = 0
  private rotation: AudioRotationState = new AudioRotationState()

  // UI 微交互层（SoundPool）
  private soundPool: media.SoundPool | undefined = undefined
  private uiSoundIds: Map<UiAudioCueKind, number> = new Map<UiAudioCueKind, number>()
  private uiSoundLoaded: Set<number> = new Set<number>()
  private uiLastPlayedAt: Map<UiAudioCueKind, number> = new Map<UiAudioCueKind, number>()
  private soundPoolInitializing: boolean = false

  // Aetheris v4 原生 C++ 液态圣殿程序化合成器（48kHz Stereo S16LE，零分配，空闲自动释放）
  private fallbackRenderer: audio.AudioRenderer | undefined = undefined
  private fallbackRunning: boolean = false
  private fallbackStarting: boolean = false
  private fallbackSilentSamples: number = 0
  private lastNativeTriggerAt: number = 0
  private aetherisSeed: string = 'SkyInstrument-01'
  private aetherisMood: AetherisMoodId = 'newmoon'
  private aetherisMaterial: AetherisMaterialPreset = 'jade'
  private aetherisRootPc: number = 3 // Eb
  private speakerAdaptiveActive: boolean = false

  private constructor() {
    this.syncNativeDNA()
    this.syncNativeMaster()
    for (let i = 0; i < MAX_CELESTIAL_VOICES; i++) {
      this.sfxSlots.push(new CelestialVoiceSlot(i, () => {
        this.scheduleSfxIdleGc()
        void this.refreshAudioSession()
      }))
    }
  }

  // ───────────────────────── 上下文注入与资产探测 ─────────────────────────

  attachContext(context: common.UIAbilityContext): void {
    this.context = context
    this.resMgr = context.resourceManager
    this.sandboxAudioDir = `${context.filesDir}/audio`
    if (!this.assetScanDone) {
      this.assetScanDone = true
      this.scanBundledAssets()
    }
    this.ensureSessionManager()
    void this.initUiSoundPoolIfAvailable()
    if (this.foreground && this.musicEnabled) {
      void this.syncMusicPlayback()
    }
  }

  private scanBundledAssets(): void {
    const resMgr = this.resMgr
    if (!resMgr) {
      return
    }
    const subDirs: string[] = [
      '',
      'stars',
      'solar',
      'dso',
      'constellations',
      'satellites',
      'bands',
      'ui'
    ]
    for (let i = 0; i < subDirs.length; i++) {
      const sub = subDirs[i]
      const rawDir = sub.length > 0 ? `${AUDIO_RAW_ROOT}/${sub}` : AUDIO_RAW_ROOT
      try {
        const list = resMgr.getRawFileListSync(rawDir)
        for (let k = 0; k < list.length; k++) {
          const entry = list[k]
          if (entry.endsWith('.m4a') || entry.endsWith('.aac') || entry.endsWith('.wav') || entry.endsWith('.ogg')) {
            this.bundledAssets.add(`${rawDir}/${entry}`)
          }
        }
      } catch (_e) {
        // 目录尚未创建时静默跳过（零异常噪音）
      }
    }
    hilog.info(DOMAIN, TAG, 'audio asset scan finished: bundled=%{public}d', this.bundledAssets.size)
  }

  private resolveAssetSource(rawPath: string): AudioSourceLocation | null {
    // 1. 优先支持沙箱热更新音景包（filesDir/audio/...）
    if (this.sandboxAudioDir.length > 0 && rawPath.startsWith(`${AUDIO_RAW_ROOT}/`)) {
      const rel = rawPath.substring(AUDIO_RAW_ROOT.length + 1)
      const sandboxPath = `${this.sandboxAudioDir}/${rel}`
      try {
        if (fileIo.accessSync(sandboxPath)) {
          return { kind: 'file', path: sandboxPath }
        }
      } catch (_e) { }
    }
    // 2. 次选应用内置 rawfile/stellarium/audio/...
    if (this.bundledAssets.has(rawPath)) {
      return { kind: 'rawfile', path: rawPath }
    }
    return null
  }

  // ───────────────────────── 对外控制 API ─────────────────────────

  async setMusicEnabled(enabled: boolean): Promise<void> {
    this.musicEnabled = enabled
    if (enabled) {
      this.interruptedBySystem = false
    }
    this.syncNativeMaster()
    hilog.info(DOMAIN, TAG, 'setMusicEnabled=%{public}s', enabled ? 'true' : 'false')
    await this.syncMusicPlayback()
  }

  setSfxEnabled(enabled: boolean): void {
    this.sfxEnabled = enabled
    this.syncNativeMaster()
    hilog.info(DOMAIN, TAG, 'setSfxEnabled=%{public}s', enabled ? 'true' : 'false')
    if (!enabled) {
      void this.stopAllSfxVoices()
      this.clearFallbackChimes()
      void this.refreshAudioSession()
    } else {
      void this.initUiSoundPoolIfAvailable()
    }
  }

  setVolume(v: number): void {
    this.volume = clampVolume(v)
    this.syncNativeMaster()
    this.applyActiveAmbientVolume()
    for (let i = 0; i < this.sfxSlots.length; i++) {
      if (this.sfxSlots[i].busy) {
        this.sfxSlots[i].updateVolume(this.volume * dbToLinear(-5.0))
      }
    }
  }

  setDucked(ducked: boolean): void {
    if (this.ducked === ducked) {
      return
    }
    this.ducked = ducked
    this.syncNativeMaster()
    this.ensureFadeLoopRunning()
  }

  setAetherisMood(mood: AetherisMoodId): void {
    this.aetherisMood = normalizeAetherisMood(mood)
    this.syncNativeDNA()
    if (this.foreground && this.sfxEnabled && this.volume > 0.001) {
      this.triggerNativeCue('constellation_3', 0)
    }
  }

  setAetherisMaterialPreset(preset: AetherisMaterialPreset): void {
    this.aetherisMaterial = normalizeAetherisMaterial(preset)
    this.syncNativeDNA()
    if (this.foreground && this.sfxEnabled && this.volume > 0.001) {
      this.triggerNativeCue('constellation_10', 0)
    }
  }

  applyAetherisSettings(seed: string, mood: AetherisMoodId, preset: AetherisMaterialPreset): void {
    if (seed.length > 0) {
      this.aetherisSeed = seed
    }
    this.aetherisMood = normalizeAetherisMood(mood)
    this.aetherisMaterial = normalizeAetherisMaterial(preset)
    this.syncNativeDNA()
  }

  randomizeAetherisSeed(): AetherisSeedResult {
    const base = RANDOM_DNA_SEEDS[Math.floor(Math.random() * RANDOM_DNA_SEEDS.length)]
    const seed = `${base}-${Math.floor(10 + Math.random() * 89)}`
    let parsed: AetherisSeedResult = {
      seed: seed,
      mood: this.aetherisMood,
      rootPc: this.aetherisRootPc,
      jade: 0.65,
      felt: 0.45,
      tape: 0.20,
      bowl: 0.25
    }
    try {
      const rawJson = nativeEntry.aetherisApplySeed(seed)
      const obj = JSON.parse(rawJson) as Record<string, Object>
      const moodVal = typeof obj['mood'] === 'string' ? normalizeAetherisMood(obj['mood'] as string) : this.aetherisMood
      const rootVal = typeof obj['rootPc'] === 'number' ? (obj['rootPc'] as number) : this.aetherisRootPc
      const j = typeof obj['jade'] === 'number' ? (obj['jade'] as number) : 0.65
      const f = typeof obj['felt'] === 'number' ? (obj['felt'] as number) : 0.45
      const t = typeof obj['tape'] === 'number' ? (obj['tape'] as number) : 0.20
      const b = typeof obj['bowl'] === 'number' ? (obj['bowl'] as number) : 0.25
      this.aetherisSeed = seed
      this.aetherisMood = moodVal
      this.aetherisRootPc = rootVal
      if (j >= f && j >= t && j >= b) { this.aetherisMaterial = 'jade' }
      else if (f >= j && f >= t && f >= b) { this.aetherisMaterial = 'felt' }
      else if (t >= j && t >= f && t >= b) { this.aetherisMaterial = 'tape' }
      else { this.aetherisMaterial = 'bowl' }
      parsed = { seed: seed, mood: moodVal, rootPc: rootVal, jade: j, felt: f, tape: t, bowl: b }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'randomizeAetherisSeed failed: %{public}s', (e as Error).message ?? String(e))
    }
    if (this.foreground && this.sfxEnabled && this.volume > 0.001) {
      this.triggerNativeCue('audio_logo', 0)
    }
    return parsed
  }

  skipNextAct(): void {
    try {
      nativeEntry.aetherisSkipNextAct()
    } catch (_e) { }
    if (this.foreground && !this.musicEnabled) {
      void this.setMusicEnabled(true)
    } else if (this.foreground && this.musicEnabled && !this.fallbackRunning && this.musicBackend === 'fallback') {
      void this.ensureFallbackRendererStarted()
    }
  }

  playFlyTo(isZoomOut: boolean = false): void {
    if (!this.foreground || !this.sfxEnabled || this.volume <= 0.001) {
      return
    }
    this.triggerNativeCue(isZoomOut ? 'fly_out' : 'fly_to', 0)
  }

  playAudioLogo(): void {
    if (!this.foreground || !this.sfxEnabled || this.volume <= 0.001) {
      return
    }
    this.triggerNativeCue('audio_logo', 0)
  }

  setHorizonAltitude(altDeg: number): void {
    try {
      nativeEntry.aetherisSetHorizonAltitude(altDeg)
    } catch (_e) { }
  }

  getAetherisPresetForState(): AetherisMaterialPreset {
    return this.aetherisMaterial
  }

  getAetherisMoodForState(): AetherisMoodId {
    return this.aetherisMood
  }

  getAetherisSeedForState(): string {
    return this.aetherisSeed
  }

  setThemeAssetPath(rawPath: string): void {
    const nextPath = rawPath.length > 0 ? rawPath : DEFAULT_AMBIENT_THEME_PATH
    if (this.activeThemePath === nextPath) {
      return
    }
    this.activeThemePath = nextPath
    if (this.foreground && this.musicEnabled) {
      void this.syncMusicPlayback()
    }
  }

  async setForeground(foreground: boolean): Promise<void> {
    if (this.foreground === foreground) {
      return
    }
    this.foreground = foreground
    this.syncNativeMaster()
    if (!foreground) {
      await this.suspendAllAudio()
    } else {
      if (this.musicEnabled && !this.interruptedBySystem) {
        await this.syncMusicPlayback()
      } else {
        await this.refreshAudioSession()
      }
    }
  }

  // 兼容旧调用点（StartupBridge / MainWindowNativeNode）
  async start(): Promise<void> {
    await this.setMusicEnabled(true)
  }

  async stop(): Promise<void> {
    await this.suspendAllAudio()
  }

  setMuted(muted: boolean): void {
    void this.setMusicEnabled(!muted)
  }

  isRunning(): boolean {
    return this.musicBackend !== 'idle' || this.fallbackRunning
  }

  getStatusSnapshot(): AudioEngineStatusSnapshot {
    return {
      musicEnabled: this.musicEnabled,
      sfxEnabled: this.sfxEnabled,
      volume: this.volume,
      foreground: this.foreground,
      ducked: this.ducked,
      interruptedBySystem: this.interruptedBySystem,
      bundledAssetCount: this.bundledAssets.size,
      musicBackend: this.musicBackend,
      sessionMode: this.sessionMode
    }
  }

  // ───────────────────────── 天体、多波段与 UI 微交互触发 ─────────────────────────

  chimeForSelection(info: StellariumBridgeResponse): void {
    if (!this.foreground || !this.sfxEnabled || this.volume <= 0.001) {
      return
    }
    const cue: ResolvedCelestialCue = resolveCelestialAudioCue(info, this.rotation)
    const source = this.resolveAssetSource(cue.assetPath) ?? this.resolveAssetSource(cue.fallbackAssetPath)
    if (source !== null) {
      void this.playCelestialStem(source, cue.gainDb)
      return
    }
    // 走 Aetheris v4 原生 C++ 物理直驱液态圣殿引擎
    this.triggerFallbackCelestialChime(info, cue)
  }

  playBandCue(bandId: string): void {
    if (!this.foreground || !this.sfxEnabled || this.volume <= 0.001) {
      return
    }
    const cue = resolveBandAudioCue(bandId)
    const source = this.resolveAssetSource(cue.assetPath)
    if (source !== null) {
      void this.playCelestialStem(source, cue.gainDb)
      return
    }
    this.triggerNativeCue(cue.cueId, 0)
  }

  playUiCue(cue: UiAudioCueKind): void {
    if (!this.foreground || !this.sfxEnabled || this.volume <= 0.001) {
      return
    }
    const spec: UiAudioCueSpec = getUiAudioCueSpec(cue)
    const now = Date.now()
    const prev = this.uiLastPlayedAt.get(cue) ?? 0
    if (now - prev < spec.minIntervalMs) {
      return
    }
    this.uiLastPlayedAt.set(cue, now)

    const pool = this.soundPool
    const soundId = this.uiSoundIds.get(cue)
    if (pool && soundId !== undefined && this.uiSoundLoaded.has(soundId)) {
      const gain = clampVolume(this.volume * dbToLinear(spec.gainDb))
      if (gain <= 0.0005) {
        return
      }
      void this.ensureAudioSessionForSfx()
      const params: media.PlayParameters = {
        loop: 0,
        leftVolume: gain,
        rightVolume: gain,
        priority: 0
      }
      try {
        pool.play(soundId, params, (err: BusinessError, _streamId: number) => {
          if (err) {
            hilog.warn(DOMAIN, TAG, 'soundPool play %{public}s failed: %{public}d', cue, err.code)
          }
        })
      } catch (_e) { }
      return
    }

    // 无外部 UI .m4a 时，直接由 Aetheris v4 C++ 引擎实时生成调内 UI 微音效（与当前 DNA 同步）
    this.triggerNativeCue(cue, 0)
  }

  // ───────────────────────── AudioSession 焦点与打断治理 ─────────────────────────

  private ensureSessionManager(): void {
    if (this.sessionManager) {
      return
    }
    try {
      this.sessionManager = audio.getAudioManager().getSessionManager()
      if (!this.sessionListenerBound && this.sessionManager) {
        this.sessionListenerBound = true
        this.sessionManager.on('audioSessionDeactivated', (event: audio.AudioSessionDeactivatedEvent) => {
          hilog.info(DOMAIN, TAG, 'audioSessionDeactivated reason=%{public}d', event.reason)
          this.sessionMode = 'none'
          if (this.musicEnabled && this.foreground) {
            this.interruptedBySystem = true
            void this.stopAmbientLayersOnly()
          }
        })
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'AudioSessionManager unavailable: %{public}s', (e as Error).message ?? String(e))
    }
  }

  private async refreshAudioSession(): Promise<void> {
    this.ensureSessionManager()
    const mgr = this.sessionManager
    if (!mgr) {
      return
    }
    const musicActive = this.foreground && this.musicEnabled && !this.interruptedBySystem
    const anySfxBusy = this.hasBusySfxVoice() || (this.fallbackRunning && this.hasActiveFallbackChime())
    const desired: 'none' | 'default' | 'mix' = musicActive
      ? 'default'
      : (this.foreground && this.sfxEnabled && anySfxBusy ? 'mix' : 'none')

    if (desired === this.sessionMode) {
      return
    }
    try {
      if (desired === 'none') {
        if (this.sessionMode !== 'none') {
          await mgr.deactivateAudioSession()
        }
        this.sessionMode = 'none'
      } else {
        const strategy: audio.AudioSessionStrategy = {
          concurrencyMode: desired === 'default'
            ? audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT
            : audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
        }
        await mgr.activateAudioSession(strategy)
        this.sessionMode = desired
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'audio session switch -> %{public}s failed: %{public}s', desired, (e as Error).message ?? String(e))
    }
  }

  private async ensureAudioSessionForSfx(): Promise<void> {
    if (this.sessionMode === 'default' || this.sessionMode === 'mix') {
      return
    }
    this.ensureSessionManager()
    const mgr = this.sessionManager
    if (!mgr) {
      return
    }
    try {
      const strategy: audio.AudioSessionStrategy = {
        concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
      }
      await mgr.activateAudioSession(strategy)
      this.sessionMode = 'mix'
    } catch (_e) { }
  }

  // ───────────────────────── 背景音乐层：双轨乒乓 AVPlayer + 回退 ─────────────────────────

  private async syncMusicPlayback(): Promise<void> {
    const shouldPlay = this.foreground && this.musicEnabled && !this.interruptedBySystem
    if (!shouldPlay) {
      this.ambientMasterTarget = 0
      if (this.musicBackend === 'avplayer') {
        this.ensureFadeLoopRunning()
      } else {
        await this.stopAmbientLayersOnly()
      }
      await this.refreshAudioSession()
      return
    }

    await this.refreshAudioSession()
    const themeSource = this.resolveAssetSource(this.activeThemePath)
    if (themeSource !== null) {
      this.musicBackend = 'avplayer'
      await this.startAvPlayerAmbient(themeSource)
      // 若此时回退合成器仅用于背景乐且无活跃和弦，则释放回退合成器节省电量
      if (this.fallbackRunning && !this.hasActiveFallbackChime()) {
        await this.stopFallbackRenderer()
      }
    } else {
      await this.stopAvPlayerAmbient()
      this.musicBackend = 'fallback'
      this.syncNativeMaster()
      await this.ensureFallbackRendererStarted()
    }
  }

  private async startAvPlayerAmbient(source: AudioSourceLocation): Promise<void> {
    this.ambientMasterTarget = 1.0
    if (this.activeTrack && this.activeTrack.active) {
      this.ensureFadeLoopRunning()
      return
    }
    this.ambientMasterFade = 0.0
    this.activeTrack = this.trackA
    const ok = await this.trackA.start(
      source,
      0.0,
      this.resMgr,
      (slot: AmbientTrackSlot, timeMs: number) => { this.handleAmbientTimeUpdate(slot, timeMs) },
      (slot: AmbientTrackSlot) => { this.handleAmbientCompleted(slot) },
      (slot: AmbientTrackSlot) => { void this.handleAmbientError(slot) }
    )
    if (ok) {
      this.trackA.targetGain = 1.0
      this.ensureFadeLoopRunning()
    } else {
      // 若 AVPlayer 意外失败，平滑回退至立体声合成器保证不静默失效
      this.musicBackend = 'fallback'
      await this.ensureFallbackRendererStarted()
    }
  }

  private handleAmbientTimeUpdate(slot: AmbientTrackSlot, timeMs: number): void {
    if (!this.foreground || !this.musicEnabled || this.interruptedBySystem) {
      return
    }
    if (slot !== this.activeTrack || slot.handoffTriggered) {
      return
    }
    if (slot.durationMs <= AMBIENT_CROSSFADE_MS * 2) {
      return
    }
    const remainingMs = slot.durationMs - timeMs
    if (remainingMs <= AMBIENT_CROSSFADE_MS) {
      slot.handoffTriggered = true
      void this.triggerAmbientPingPongHandoff(slot)
    }
  }

  private async triggerAmbientPingPongHandoff(outgoing: AmbientTrackSlot): Promise<void> {
    const source = this.resolveAssetSource(this.activeThemePath)
    if (!source) {
      return
    }
    const incoming = (outgoing === this.trackA) ? this.trackB : this.trackA
    this.activeTrack = incoming
    outgoing.targetGain = 0.0
    const ok = await incoming.start(
      source,
      0.0,
      this.resMgr,
      (slot: AmbientTrackSlot, timeMs: number) => { this.handleAmbientTimeUpdate(slot, timeMs) },
      (slot: AmbientTrackSlot) => { this.handleAmbientCompleted(slot) },
      (slot: AmbientTrackSlot) => { void this.handleAmbientError(slot) }
    )
    if (ok) {
      incoming.targetGain = 1.0
      this.ensureFadeLoopRunning()
    }
  }

  private handleAmbientCompleted(slot: AmbientTrackSlot): void {
    if (slot !== this.activeTrack) {
      void slot.stopAndRelease(this.resMgr)
      return
    }
    // 兜底：若短曲未触发提前接力，则在播完时无缝续播
    if (this.foreground && this.musicEnabled && !this.interruptedBySystem) {
      void this.triggerAmbientPingPongHandoff(slot)
    } else {
      void slot.stopAndRelease(this.resMgr)
    }
  }

  private async handleAmbientError(slot: AmbientTrackSlot): Promise<void> {
    await slot.stopAndRelease(this.resMgr)
    if (slot === this.activeTrack) {
      this.activeTrack = null
      if (this.foreground && this.musicEnabled && !this.interruptedBySystem) {
        this.musicBackend = 'fallback'
        await this.ensureFallbackRendererStarted()
      }
    }
  }

  private effectiveAmbientMaxGain(): number {
    const baseDb = DEFAULT_AMBIENT_GAIN_DB + (this.ducked ? AMBIENT_DUCK_OFFSET_DB : 0.0)
    return clampVolume(this.volume * dbToLinear(baseDb))
  }

  private applyActiveAmbientVolume(): void {
    const maxGain = this.effectiveAmbientMaxGain() * this.ambientMasterFade
    if (this.trackA.active) {
      this.trackA.applyGain(this.trackA.currentGain * maxGain)
    }
    if (this.trackB.active) {
      this.trackB.applyGain(this.trackB.currentGain * maxGain)
    }
  }

  private ensureFadeLoopRunning(): void {
    if (this.fadeTimer !== 0) {
      return
    }
    const stepMs = 50
    const masterStep = stepMs / Math.max(100, AMBIENT_FADE_MS)
    const crossStep = stepMs / Math.max(200, AMBIENT_CROSSFADE_MS)

    this.fadeTimer = setInterval(() => {
      let stillMoving = false

      if (Math.abs(this.ambientMasterTarget - this.ambientMasterFade) > 0.005) {
        const dir = this.ambientMasterTarget > this.ambientMasterFade ? 1 : -1
        this.ambientMasterFade = clampVolume(this.ambientMasterFade + dir * masterStep)
        stillMoving = true
      } else {
        this.ambientMasterFade = this.ambientMasterTarget
      }

      const maxGain = this.effectiveAmbientMaxGain() * this.ambientMasterFade
      const slots: AmbientTrackSlot[] = [this.trackA, this.trackB]
      for (let i = 0; i < slots.length; i++) {
        const s = slots[i]
        if (!s.active) {
          continue
        }
        if (Math.abs(s.targetGain - s.currentGain) > 0.005) {
          const dir = s.targetGain > s.currentGain ? 1 : -1
          s.currentGain = clampVolume(s.currentGain + dir * crossStep)
          stillMoving = true
        } else {
          s.currentGain = s.targetGain
        }
        s.applyGain(s.currentGain * maxGain)
        if (s.targetGain <= 0.001 && s.currentGain <= 0.005 && s !== this.activeTrack) {
          void s.stopAndRelease(this.resMgr)
        }
      }

      if (this.ambientMasterTarget <= 0.001 && this.ambientMasterFade <= 0.005) {
        this.stopFadeTimer()
        void this.stopAvPlayerAmbient()
        if (this.musicBackend === 'avplayer') {
          this.musicBackend = 'idle'
        }
        void this.refreshAudioSession()
        return
      }

      if (!stillMoving) {
        this.stopFadeTimer()
      }
    }, stepMs) as number
  }

  private stopFadeTimer(): void {
    if (this.fadeTimer !== 0) {
      clearInterval(this.fadeTimer)
      this.fadeTimer = 0
    }
  }

  private async stopAvPlayerAmbient(): Promise<void> {
    this.stopFadeTimer()
    this.activeTrack = null
    this.ambientMasterFade = 0
    await this.trackA.stopAndRelease(this.resMgr)
    await this.trackB.stopAndRelease(this.resMgr)
  }

  private async stopAmbientLayersOnly(): Promise<void> {
    await this.stopAvPlayerAmbient()
    this.musicBackend = 'idle'
    if (this.fallbackRunning && !this.hasActiveFallbackChime()) {
      await this.stopFallbackRenderer()
    }
  }

  // ───────────────────────── 天体复音音效池（AVPlayer Pool） ─────────────────────────

  private async playCelestialStem(source: AudioSourceLocation, gainDb: number): Promise<void> {
    await this.ensureAudioSessionForSfx()
    // 先把上一批仍在拖尾的旧天体声部在 500ms 内平滑淡出，既保留丝滑过渡又彻底杜绝狂点浑浊叠音
    for (let i = 0; i < this.sfxSlots.length; i++) {
      if (this.sfxSlots[i].busy && !this.sfxSlots[i].fadingOut) {
        this.sfxSlots[i].fadeOutAndStop(SFX_CROSSFADE_OUT_MS, this.resMgr)
      }
    }
    const slot = this.acquireSfxSlot()
    const linearGain = clampVolume(this.volume * dbToLinear(gainDb))
    await slot.play(source, linearGain, this.resMgr)
  }

  private acquireSfxSlot(): CelestialVoiceSlot {
    for (let i = 0; i < this.sfxSlots.length; i++) {
      if (!this.sfxSlots[i].busy) {
        return this.sfxSlots[i]
      }
    }
    // 复音满时礼貌回收最早触发的旧声部
    let oldest = this.sfxSlots[0]
    for (let i = 1; i < this.sfxSlots.length; i++) {
      if (this.sfxSlots[i].startedAt < oldest.startedAt) {
        oldest = this.sfxSlots[i]
      }
    }
    return oldest
  }

  private hasBusySfxVoice(): boolean {
    for (let i = 0; i < this.sfxSlots.length; i++) {
      if (this.sfxSlots[i].busy) {
        return true
      }
    }
    return false
  }

  private scheduleSfxIdleGc(): void {
    if (this.sfxIdleTimer !== 0) {
      clearTimeout(this.sfxIdleTimer)
    }
    this.sfxIdleTimer = setTimeout(() => {
      this.sfxIdleTimer = 0
      const now = Date.now()
      for (let i = 0; i < this.sfxSlots.length; i++) {
        const s = this.sfxSlots[i]
        if (!s.busy && s.player && (now - s.lastUsedAt >= SFX_VOICE_IDLE_GC_MS)) {
          void s.release(this.resMgr)
        }
      }
    }, SFX_VOICE_IDLE_GC_MS) as number
  }

  private async stopAllSfxVoices(): Promise<void> {
    if (this.sfxIdleTimer !== 0) {
      clearTimeout(this.sfxIdleTimer)
      this.sfxIdleTimer = 0
    }
    for (let i = 0; i < this.sfxSlots.length; i++) {
      await this.sfxSlots[i].release(this.resMgr)
    }
  }

  // ───────────────────────── UI 微交互层（SoundPool） ─────────────────────────

  private async initUiSoundPoolIfAvailable(): Promise<void> {
    if (this.soundPool || this.soundPoolInitializing || !this.sfxEnabled) {
      return
    }
    const specs = allUiAudioCueSpecs()
    const available: UiAudioCueSpec[] = []
    for (let i = 0; i < specs.length; i++) {
      if (this.resolveAssetSource(specs[i].assetPath) !== null) {
        available.push(specs[i])
      }
    }
    if (available.length === 0) {
      return
    }

    this.soundPoolInitializing = true
    try {
      const info: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      }
      const pool = await media.createSoundPool(4, info)
      this.soundPool = pool
      pool.on('loadComplete', (soundId: number) => {
        this.uiSoundLoaded.add(soundId)
      })
      pool.on('error', (err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'SoundPool error %{public}d: %{public}s', err.code, err.message)
      })

      for (let i = 0; i < available.length; i++) {
        const spec = available[i]
        const src = this.resolveAssetSource(spec.assetPath)
        if (!src) {
          continue
        }
        await this.loadUiCueIntoPool(pool, spec.cue, src)
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'SoundPool init failed: %{public}s', (e as Error).message ?? String(e))
    } finally {
      this.soundPoolInitializing = false
    }
  }

  private async loadUiCueIntoPool(
    pool: media.SoundPool,
    cue: UiAudioCueKind,
    source: AudioSourceLocation
  ): Promise<void> {
    try {
      if (source.kind === 'rawfile') {
        if (!this.resMgr) {
          return
        }
        const rawFd = await this.resMgr.getRawFd(source.path)
        const soundId = await new Promise<number>((resolve, reject) => {
          pool.load(rawFd.fd, rawFd.offset, rawFd.length, (err: BusinessError, id: number) => {
            if (err) { reject(err) } else { resolve(id) }
          })
        })
        this.uiSoundIds.set(cue, soundId)
        try {
          await this.resMgr.closeRawFd(source.path)
        } catch (_e) { }
      } else {
        const stat = fileIo.statSync(source.path)
        const file = fileIo.openSync(source.path, fileIo.OpenMode.READ_ONLY)
        const soundId = await new Promise<number>((resolve, reject) => {
          pool.load(file.fd, 0, stat.size, (err: BusinessError, id: number) => {
            if (err) { reject(err) } else { resolve(id) }
          })
        })
        this.uiSoundIds.set(cue, soundId)
        try {
          fileIo.closeSync(file.fd)
        } catch (_e) { }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'SoundPool load %{public}s failed: %{public}s', cue, (e as Error).message ?? String(e))
    }
  }

  private async releaseUiSoundPool(): Promise<void> {
    const pool = this.soundPool
    this.soundPool = undefined
    this.uiSoundIds.clear()
    this.uiSoundLoaded.clear()
    if (!pool) {
      return
    }
    try {
      await new Promise<void>((resolve) => {
        pool.release((_err: BusinessError) => { resolve() })
      })
    } catch (_e) { }
  }

  private async suspendAllAudio(): Promise<void> {
    await this.stopAvPlayerAmbient()
    this.musicBackend = 'idle'
    await this.stopAllSfxVoices()
    this.clearFallbackChimes()
    await this.stopFallbackRenderer()
    await this.releaseUiSoundPool()
    await this.refreshAudioSession()
  }

  // ───────────────────────── Aetheris v4 原生 C++ 液态圣殿合成器 ─────────────────────────

  private syncNativeMaster(): void {
    const wantNativeMusic = this.foreground && this.musicEnabled && !this.interruptedBySystem && this.musicBackend !== 'avplayer'
    try {
      nativeEntry.aetherisSetMaster(wantNativeMusic, this.sfxEnabled, this.volume, this.ducked)
    } catch (_e) { }
  }

  private syncNativeDNA(): void {
    const w = materialWeightsForPreset(this.aetherisMaterial)
    try {
      nativeEntry.aetherisSetDNA(
        this.aetherisSeed,
        this.aetherisMood,
        this.aetherisRootPc,
        w.jade,
        w.felt,
        w.tape,
        w.bowl,
        0.65
      )
    } catch (_e) { }
  }

  private detectAndApplyOutputDevice(renderer: audio.AudioRenderer): void {
    try {
      const devices: audio.AudioDeviceDescriptors = renderer.getCurrentOutputDevicesSync()
      this.applyOutputDeviceDescriptors(devices)
    } catch (_e) {
      // 默认保守适配手机扬声器虚拟低音保护，若插耳机立即由监听事件切换
      this.setSpeakerAdaptiveMode(true)
    }
  }

  private applyOutputDeviceDescriptors(devices: audio.AudioDeviceDescriptors | undefined): void {
    if (!devices || devices.length === 0) {
      return
    }
    let hasHeadphone = false
    let hasSpeaker = false
    for (let i = 0; i < devices.length; i++) {
      const dt = devices[i].deviceType
      if (dt === audio.DeviceType.WIRED_HEADSET ||
          dt === audio.DeviceType.WIRED_HEADPHONES ||
          dt === audio.DeviceType.BLUETOOTH_A2DP ||
          dt === audio.DeviceType.BLUETOOTH_SCO ||
          dt === audio.DeviceType.USB_HEADSET) {
        hasHeadphone = true
      } else if (dt === audio.DeviceType.SPEAKER || dt === audio.DeviceType.EARPIECE) {
        hasSpeaker = true
      }
    }
    const isSpeaker = hasSpeaker && !hasHeadphone
    this.setSpeakerAdaptiveMode(isSpeaker)
  }

  private setSpeakerAdaptiveMode(isSpeaker: boolean): void {
    this.speakerAdaptiveActive = isSpeaker
    try {
      nativeEntry.aetherisSetOutputMode(isSpeaker)
    } catch (_e) { }
    hilog.info(DOMAIN, TAG, 'Aetheris output adaptation -> %{public}s', isSpeaker ? 'phone-speaker (virtual-bass + mono-safe)' : 'headphones (full-range + antiphase)')
  }

  private async ensureFallbackRendererStarted(): Promise<void> {
    if (this.fallbackRunning || this.fallbackStarting || !this.foreground) {
      return
    }
    this.fallbackStarting = true
    try {
      this.syncNativeDNA()
      this.syncNativeMaster()

      const streamInfo: audio.AudioStreamInfo = {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
        channels: audio.AudioChannel.CHANNEL_2,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      }
      const rendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      }
      const options: audio.AudioRendererOptions = {
        streamInfo: streamInfo,
        rendererInfo: rendererInfo
      }
      const renderer = await audio.createAudioRenderer(options)
      this.fallbackRenderer = renderer
      this.fallbackSilentSamples = 0

      this.detectAndApplyOutputDevice(renderer)
      try {
        renderer.on('outputDeviceChangeWithInfo', (changeInfo: audio.AudioStreamDeviceChangeInfo) => {
          this.applyOutputDeviceDescriptors(changeInfo.devices)
        })
      } catch (_e) { }

      renderer.on('writeData', (buffer: ArrayBuffer): audio.AudioDataCallbackResult => {
        this.renderFallbackStereo(buffer)
        return audio.AudioDataCallbackResult.VALID
      })
      await renderer.start()
      this.fallbackRunning = true
      hilog.info(DOMAIN, TAG, 'Aetheris v4 native C++ AudioRenderer started (48kHz Stereo S16LE, speaker=%{public}s)',
        this.speakerAdaptiveActive ? 'true' : 'false')
    } catch (e) {
      this.fallbackRunning = false
      hilog.warn(DOMAIN, TAG, 'Aetheris AudioRenderer start failed: %{public}s', (e as Error).message ?? String(e))
    } finally {
      this.fallbackStarting = false
    }
  }

  private async stopFallbackRenderer(): Promise<void> {
    this.fallbackRunning = false
    const r = this.fallbackRenderer
    this.fallbackRenderer = undefined
    if (r) {
      try {
        r.off('outputDeviceChangeWithInfo')
      } catch (_e) { }
      try {
        await r.stop()
        await r.release()
      } catch (_e) { }
    }
    try {
      nativeEntry.aetherisReset()
    } catch (_e) { }
  }

  private hasActiveFallbackChime(): boolean {
    return (Date.now() - this.lastNativeTriggerAt) < 6000
  }

  private clearFallbackChimes(): void {
    this.lastNativeTriggerAt = 0
    this.syncNativeMaster()
  }

  private triggerNativeCue(cueId: string, pan: number): void {
    this.lastNativeTriggerAt = Date.now()
    this.fallbackSilentSamples = 0
    this.syncNativeMaster()
    try {
      nativeEntry.aetherisTriggerCue(cueId, pan)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'aetherisTriggerCue(%{public}s) failed: %{public}s', cueId, (e as Error).message ?? String(e))
    }
    void this.ensureAudioSessionForSfx()
    if (!this.fallbackRunning) {
      void this.ensureFallbackRendererStarted()
    }
  }

  private triggerFallbackCelestialChime(info: StellariumBridgeResponse, cue: ResolvedCelestialCue): void {
    const rawName: string = (info.englishName && info.englishName.length > 0)
      ? info.englishName
      : (info.name && info.name.length > 0 ? info.name : '')
    const hash = hashStableName(rawName)
    const pan = ((hash % 11) - 5) * 0.12
    const mag: number = (typeof info.magnitude === 'number') ? info.magnitude as number : 2.5
    const tk: number = (typeof info.temperatureK === 'number') ? info.temperatureK as number : 0

    this.lastNativeTriggerAt = Date.now()
    this.fallbackSilentSamples = 0
    this.syncNativeMaster()
    try {
      if (cue.category === 'star' && tk > 1000) {
        // 真实恒星物理直驱：有效温度 T_eff + 视星等 Mag + 方位声像
        const distEst = Math.max(8, Math.min(2500, 40 + (hash % 1200)))
        nativeEntry.aetherisTriggerStar(tk, mag, distEst, pan, 0.65)
      } else {
        nativeEntry.aetherisTriggerCue(cue.cueId, pan)
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Aetheris trigger failed: %{public}s', (e as Error).message ?? String(e))
    }
    void this.ensureAudioSessionForSfx()
    if (!this.fallbackRunning) {
      void this.ensureFallbackRendererStarted()
    }
  }

  private renderFallbackStereo(buffer: ArrayBuffer): void {
    const frames: number = (buffer.byteLength / 4) | 0
    if (!this.foreground || !this.fallbackRunning) {
      new Int16Array(buffer).fill(0)
      return
    }

    let peakEnergy: number = 0.0
    try {
      peakEnergy = nativeEntry.aetherisRender(buffer)
    } catch (_e) {
      new Int16Array(buffer).fill(0)
      return
    }

    const wantFallbackMusic = this.musicEnabled && !this.interruptedBySystem && this.musicBackend === 'fallback'
    // 节能自动释放：无背景音乐且 9.5s 圣殿混响尾音完全归零 3 秒后，自动停止并释放 AudioRenderer
    if (!wantFallbackMusic && !this.hasActiveFallbackChime() && peakEnergy < 0.0004) {
      this.fallbackSilentSamples += frames
      if (this.fallbackSilentSamples >= FALLBACK_IDLE_RELEASE_SAMPLES) {
        this.fallbackSilentSamples = 0
        void this.stopFallbackRenderer().then(() => this.refreshAudioSession())
      }
    } else {
      this.fallbackSilentSamples = 0
    }
  }
}

export default AudioEngine
