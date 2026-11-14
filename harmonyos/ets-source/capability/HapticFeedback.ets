export type HapticKind = 'selection' | 'menu' | 'confirmation' | 'error' | 'ruler'

export interface HapticDriver {
  supports(effectId: string): Promise<boolean>
  start(effectId: string, intensity: number): Promise<void>
  stop(): Promise<void>
}

export interface HapticPreferences {
  readEnabled(): Promise<boolean>
  writeEnabled(enabled: boolean): Promise<void>
  readIntensity(): Promise<number>
  writeIntensity(intensity: number): Promise<void>
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
  intensity: number
  consent: boolean
  lastOutcome: string
}

const SOFT: string = 'haptic.effect.soft'
const SUCCESS: string = 'haptic.notice.success'
const FAILURE: string = 'haptic.notice.fail'
const CLOCK_TIMER: string = 'haptic.clock.timer'
export const DEFAULT_HAPTIC_INTENSITY: number = 40
export const MIN_HAPTIC_INTENSITY: number = 10
export const MAX_HAPTIC_INTENSITY: number = 100

export class HapticFeedback {
  private driver: HapticDriver
  private preferences: HapticPreferences
  private guard: HapticGuard
  private enabled: boolean = false
  private intensity: number = DEFAULT_HAPTIC_INTENSITY
  private loaded: boolean = false
  private foreground: boolean = false
  // Privacy consent is lifecycle-scoped. privacyManager.getAppPrivacyMgmtInfo()
  // and getAppPrivacyResult() are synchronous system calls that cost tens of
  // milliseconds together; querying them per pulse blocked the UI thread for
  // ~140 ms on every wheel tick. Haptics is local and low-risk, so the cache is
  // refreshed only at explicit boundaries: foreground entry / initialize(),
  // privacy flows via refreshConsent(), and an unknown-state enable.
  private consentOk: boolean = false
  private consentDirty: boolean = true
  private saving: boolean = false
  private saveCount: number = 0
  private probing: boolean = false
  private supported: string[] = []
  private lastFailure: string = ''
  private lastErrorCode: number = 0
  private lastOutcome: string = ''
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
      lastErrorCode: this.lastErrorCode, intensity: this.intensity,
      consent: this.consentOk, lastOutcome: this.lastOutcome
    }
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground
    if (foreground) {
      // Do not query here: this callback can run during a lifecycle transition.
      // initialize() performs one low-frequency refresh when it resumes.
      this.consentDirty = true
    } else {
      this.suspend()
    }
  }

  suspend(): void {
    this.epoch++
    this.rulerIndex = undefined
    this.selectionId = ''
    this.stopActive()
  }

  private queryConsent(): boolean {
    try {
      return this.guard.hasConsent()
    } catch (_) {
      return false
    }
  }

  // Public low-frequency refresh point for privacy flows. Never call this from
  // emit()/rulerTick(): the privacy manager query costs ~70 ms on device.
  refreshConsent(): boolean {
    if (!this.foreground) {
      this.consentDirty = true
      return false
    }
    this.consentDirty = false
    this.consentOk = this.queryConsent()
    if (!this.consentOk) this.suspend()
    return this.consentOk
  }

  initialize(): Promise<void> {
    if (!this.foreground) return Promise.resolve()
    if (this.consentDirty || !this.consentOk) {
      if (!this.refreshConsent()) return Promise.resolve()
    }
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
    if (!this.foreground || !this.consentOk) return
    const epoch = this.epoch
    const revision = this.settingRevision
    if (!this.loaded) {
      try {
        const enabled = await this.preferences.readEnabled()
        let storedIntensity = DEFAULT_HAPTIC_INTENSITY
        try {
          storedIntensity = this.normalizeIntensity(await this.preferences.readIntensity())
        } catch (_) {
          storedIntensity = DEFAULT_HAPTIC_INTENSITY
        }
        if (revision === this.settingRevision) {
          this.enabled = enabled === true
          this.intensity = storedIntensity
        }
        this.loaded = true
      } catch (_) {
        this.lastFailure = 'preferences-read'
        return
      }
    }
    if (epoch !== this.epoch || !this.foreground || !this.consentOk) return
    this.probing = true
    const supported: string[] = []
    for (const effect of [SOFT, SUCCESS, FAILURE, CLOCK_TIMER]) {
      if (epoch !== this.epoch || !this.foreground || !this.consentOk) break
      try {
        if (await this.driver.supports(effect)) supported.push(effect)
      } catch (_) {
        this.lastFailure = 'capability-query'
      }
    }
    if (epoch === this.epoch && this.foreground && this.consentOk) this.supported = supported
    this.probing = false
  }

  async setEnabled(enabled: boolean): Promise<boolean> {
    if (enabled) {
      if (!this.foreground) return false
      // Unknown/expired cache: this is an explicit user action, so one
      // synchronous privacy query here is acceptable (and happens at most once
      // until the next refresh point).
      if (!this.consentOk && !this.refreshConsent()) return false
    }
    const revision = ++this.settingRevision
    const previous = this.enabled
    // The switch itself is app-local: reflect the user's choice immediately and
    // flush the preferences write in the background. Waiting for the write
    // before updating `enabled` made the controlled Toggle snap back.
    this.enabled = enabled
    this.loaded = true
    this.beginSave()
    this.suspend()
    const write = this.writes.then(async () => { await this.preferences.writeEnabled(enabled) })
    this.writes = write.catch(() => {})
    try {
      await write
      if (revision === this.settingRevision) this.lastFailure = ''
      return true
    } catch (_) {
      if (revision === this.settingRevision) {
        this.enabled = previous
        this.lastFailure = 'preferences-write'
      }
      return false
    } finally {
      this.endSave()
    }
  }

  private beginSave(): void {
    this.saveCount += 1
    this.saving = true
  }

  private endSave(): void {
    this.saveCount = Math.max(0, this.saveCount - 1)
    this.saving = this.saveCount > 0
  }

  private normalizeIntensity(value: number): number {
    if (!Number.isFinite(value)) return DEFAULT_HAPTIC_INTENSITY
    return Math.max(MIN_HAPTIC_INTENSITY, Math.min(MAX_HAPTIC_INTENSITY, Math.round(value)))
  }

  async setIntensity(value: number, persist: boolean = true): Promise<boolean> {
    const next = this.normalizeIntensity(value)
    if (!persist && next === this.intensity) return true
    const revision = ++this.settingRevision
    const previous = this.intensity
    this.intensity = next
    this.loaded = true
    if (!persist) return true
    this.beginSave()
    this.suspend()
    const write = this.writes.then(async () => { await this.preferences.writeIntensity(next) })
    this.writes = write.catch(() => {})
    try {
      await write
      if (revision === this.settingRevision) this.lastFailure = ''
      return true
    } catch (_) {
      if (revision === this.settingRevision) {
        this.intensity = previous
        this.lastFailure = 'preferences-write'
      }
      return false
    } finally {
      this.endSave()
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
    // Each wheel gesture starts with a fresh ruler cadence; the global pulse
    // guard still prevents overlapping platform calls.
    this.lastByKind.delete('ruler')
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
    if (!this.foreground || !this.consentOk) {
      this.suspend()
      return false
    }
    return this.loaded && this.enabled && !this.saving
  }

  private effectiveIntensity(kind: HapticKind): number {
    const factor = kind === 'ruler' ? 0.5 : (kind === 'selection' || kind === 'menu' ? 0.75 : 1.0)
    return Math.max(1, Math.min(MAX_HAPTIC_INTENSITY, Math.round(this.intensity * factor)))
  }

  private skip(outcome: string): boolean {
    this.lastOutcome = outcome
    return false
  }

  private async emit(kind: HapticKind): Promise<boolean> {
    // Consent is a cached boolean here on purpose: time-wheel drags call this
    // on every touch sample, and querying privacyManager would block the UI
    // thread for ~70 ms per pulse. The cache is refreshed only on foreground
    // entry, initialize(), privacy flows, and an unknown-state enable.
    if (!this.foreground) {
      this.suspend()
      return this.skip('skipped-consent')
    }
    if (!this.consentOk) return this.skip('skipped-consent')
    if (!this.loaded || !this.enabled || this.saving) return this.skip('skipped-disabled')
    if (this.probing || this.inFlight || this.stopPending !== undefined) return this.skip('skipped-busy')
    let effect = kind === 'confirmation' ? SUCCESS
      : (kind === 'error' ? FAILURE : (kind === 'ruler' && this.supported.includes(CLOCK_TIMER) ? CLOCK_TIMER : SOFT))
    if (!this.supported.includes(effect)) effect = SOFT
    if (!this.supported.includes(effect)) return this.skip('skipped-unsupported')
    let now: number
    try {
      now = this.guard.now()
    } catch (_) {
      return this.skip('skipped-clock')
    }
    const interval = kind === 'error' ? 600 : (kind === 'confirmation' ? 300 : (kind === 'ruler' ? 80 : 120))
    const pulseGap = kind === 'ruler' ? 60 : 90
    const previous = this.lastByKind.get(kind) ?? -Infinity
    if (!Number.isFinite(now) || now < this.lastPulse || now - this.lastPulse < pulseGap || now - previous < interval) {
      return this.skip('skipped-throttled')
    }
    this.lastPulse = now
    this.lastByKind.set(kind, now)
    const epoch = this.epoch
    const intensity = this.effectiveIntensity(kind)
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
        return this.skip('skipped-interrupted')
      }
      this.lastOutcome = 'played'
      return true
    } catch (error) {
      this.lastOutcome = 'failed'
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
