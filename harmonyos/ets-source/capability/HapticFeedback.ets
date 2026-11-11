export type HapticKind = 'selection' | 'menu' | 'confirmation' | 'error' | 'ruler'

export interface HapticDriver {
  supports(effectId: string): Promise<boolean>
  start(effectId: string, intensity: number): Promise<void>
  stop(): Promise<void>
}

export interface HapticPreferences {
  readEnabled(): Promise<boolean>
  writeEnabled(enabled: boolean): Promise<void>
}

export interface HapticGuard {
  hasConsent(): boolean
  now(): number
}

export interface HapticStatus {
  enabled: boolean
  loaded: boolean
  saving: boolean
  foreground: boolean
  available: boolean
  probing: boolean
  supportedEffects: string[]
  lastFailure: string
  lastErrorCode: number
}

const SOFT: string = 'haptic.effect.soft'
const SUCCESS: string = 'haptic.notice.success'
const FAILURE: string = 'haptic.notice.fail'

export class HapticFeedback {
  private driver: HapticDriver
  private preferences: HapticPreferences
  private guard: HapticGuard
  private enabled: boolean = false
  private loaded: boolean = false
  private foreground: boolean = false
  private saving: boolean = false
  private probing: boolean = false
  private supported: string[] = []
  private lastFailure: string = ''
  private lastErrorCode: number = 0
  private epoch: number = 0
  private settingRevision: number = 0
  private lastPulse: number = -Infinity
  private lastByKind: Map<HapticKind, number> = new Map<HapticKind, number>()
  private selectionId: string = ''
  private rulerIndex: number | undefined = undefined
  private inFlight: boolean = false
  private mayBeActive: boolean = false
  private stopPending: Promise<void> | undefined = undefined
  private initialization: Promise<void> | undefined = undefined
  private initializationEpoch: number = 0
  private writes: Promise<void> = Promise.resolve()

  constructor(driver: HapticDriver, preferences: HapticPreferences, guard: HapticGuard) {
    this.driver = driver
    this.preferences = preferences
    this.guard = guard
  }

  status(): HapticStatus {
    return {
      enabled: this.enabled, loaded: this.loaded, saving: this.saving,
      foreground: this.foreground, available: this.supported.length > 0,
      probing: this.probing, supportedEffects: this.supported.slice(), lastFailure: this.lastFailure,
      lastErrorCode: this.lastErrorCode
    }
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground
    if (!foreground) this.suspend()
  }

  suspend(): void {
    this.epoch++
    this.rulerIndex = undefined
    this.selectionId = ''
    this.stopActive()
  }

  private hasConsent(): boolean {
    try {
      return this.guard.hasConsent()
    } catch (_) {
      return false
    }
  }

  initialize(): Promise<void> {
    if (!this.foreground || !this.hasConsent()) return Promise.resolve()
    if (this.initialization !== undefined) {
      if (this.initializationEpoch === this.epoch) return this.initialization
      return this.initialization.then(() => this.initialize())
    }
    this.initializationEpoch = this.epoch
    const pending = this.loadAndProbe()
    this.initialization = pending
    pending.then(() => { this.initialization = undefined })
    return pending
  }

  private async loadAndProbe(): Promise<void> {
    if (!this.foreground || !this.hasConsent()) return
    const epoch = this.epoch
    const revision = this.settingRevision
    if (!this.loaded) {
      try {
        const enabled = await this.preferences.readEnabled()
        if (revision === this.settingRevision) this.enabled = enabled === true
        this.loaded = true
      } catch (_) {
        this.lastFailure = 'preferences-read'
        return
      }
    }
    if (epoch !== this.epoch || !this.foreground || !this.hasConsent()) return
    this.probing = true
    const supported: string[] = []
    for (const effect of [SOFT, SUCCESS, FAILURE]) {
      if (epoch !== this.epoch || !this.foreground || !this.hasConsent()) break
      try {
        if (await this.driver.supports(effect)) supported.push(effect)
      } catch (_) {
        this.lastFailure = 'capability-query'
      }
    }
    if (epoch === this.epoch && this.foreground && this.hasConsent()) this.supported = supported
    this.probing = false
  }

  async setEnabled(enabled: boolean): Promise<boolean> {
    if (enabled && (!this.foreground || !this.hasConsent())) return false
    const revision = ++this.settingRevision
    this.enabled = false
    this.saving = true
    this.suspend()
    const write = this.writes.then(async () => { await this.preferences.writeEnabled(enabled) })
    this.writes = write.catch(() => {})
    try {
      await write
      if (revision === this.settingRevision) {
        this.enabled = enabled
        this.loaded = true
        this.saving = false
        this.lastFailure = ''
      }
      return true
    } catch (_) {
      if (revision === this.settingRevision) {
        this.saving = false
        this.lastFailure = 'preferences-write'
      }
      return false
    }
  }

  selection(id: string): Promise<boolean> {
    if (id.length === 0) {
      this.selectionId = ''
      return Promise.resolve(false)
    }
    if (id === this.selectionId) return Promise.resolve(false)
    this.selectionId = id
    return this.emit('selection')
  }

  menu(): Promise<boolean> { return this.emit('menu') }
  confirmation(): Promise<boolean> { return this.emit('confirmation') }
  error(): Promise<boolean> { return this.emit('error') }

  beginRuler(index: number): void {
    this.rulerIndex = Number.isInteger(index) ? index : undefined
  }

  rulerTick(index: number): Promise<boolean> {
    if (this.rulerIndex === undefined || !Number.isInteger(index) || index === this.rulerIndex) {
      return Promise.resolve(false)
    }
    this.rulerIndex = index
    return this.emit('ruler')
  }

  endRuler(): void { this.rulerIndex = undefined }

  private allowed(): boolean {
    if (!this.foreground || !this.hasConsent()) {
      this.suspend()
      return false
    }
    return this.loaded && this.enabled && !this.saving
  }

  private async emit(kind: HapticKind): Promise<boolean> {
    if (!this.allowed() || this.probing || this.inFlight || this.stopPending !== undefined) return false
    let effect = kind === 'confirmation' ? SUCCESS : (kind === 'error' ? FAILURE : SOFT)
    if (!this.supported.includes(effect)) effect = SOFT
    if (!this.supported.includes(effect)) return false
    let now: number
    try {
      now = this.guard.now()
    } catch (_) {
      return false
    }
    const interval = kind === 'error' ? 600 : (kind === 'confirmation' ? 300 : 120)
    const previous = this.lastByKind.get(kind) ?? -Infinity
    if (!Number.isFinite(now) || now < this.lastPulse || now - this.lastPulse < 90 || now - previous < interval) return false
    this.lastPulse = now
    this.lastByKind.set(kind, now)
    const epoch = this.epoch
    const intensity = kind === 'ruler' ? 20 : (kind === 'selection' || kind === 'menu' ? 30 : 40)
    this.inFlight = true
    this.mayBeActive = true
    try {
      await this.driver.start(effect, intensity)
      this.lastErrorCode = 0
      this.lastFailure = ''
      if (epoch !== this.epoch || !this.allowed()) {
        if (this.stopPending !== undefined) await this.stopPending
        this.mayBeActive = true
        await this.stopActive()
        return false
      }
      return true
    } catch (error) {
      this.lastFailure = 'vibration-start'
      const failure = error as HapticPlatformError
      this.lastErrorCode = typeof failure?.code === 'number' ? failure.code : 0
      this.supported = []
      await this.stopActive()
      return false
    } finally {
      this.inFlight = false
    }
  }

  private stopActive(): Promise<void> {
    if (this.stopPending !== undefined) return this.stopPending
    if (!this.mayBeActive) return Promise.resolve()
    this.mayBeActive = false
    const pending = this.stopDriver()
    this.stopPending = pending
    pending.then(() => { this.stopPending = undefined })
    return pending
  }

  private async stopDriver(): Promise<void> {
    try {
      await this.driver.stop()
    } catch (_) {
      this.lastFailure = 'vibration-stop'
    }
  }
}

interface HapticPlatformError {
  code?: number
}
