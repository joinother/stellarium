// 统一 UI 偏好持久化层。
//
// 只持久化「纯 UI 偏好」：不影响引擎计算与天文呈现，只影响界面组织与显示方式。
// 引擎行为设置（夜间模式、赤道仪/地平仪、语言等）的权威位置是 config.ini，
// 不进入本仓库；本仓库也不得反向覆盖引擎值。
//
// 本文件不 import NAPI：Preferences 读写由宿主通过 SettingsPersistencePort 注入。

export const UI_SETTINGS_STORE: string = 'stellarium_ui'
export const UI_SETTINGS_KEY: string = 'uiSettings'
export const SETTINGS_SCHEMA_VERSION: number = 2

export interface UiSettings {
  schemaVersion: number
  musicEnabled: boolean
  useMetricUnits: boolean
  viewCoordinatesVisible: boolean
  viewCoordinateFamily: string
  viewEquatorialEpoch: string
  objectDetailConnectorVisible: boolean
  astroTab: number
  astroGroup: number
  positionMode: number
  celestialPositionCategory: string
  celestialPositionMagnitude: number
  celestialPositionHorizontal: boolean
  ephemerisMode: number
  ephemerisDays: number
  ephemerisStepHours: number
  rtsCalendarDays: number
  graphMode: number
  eclipseMonths: number
  moonPhaseDays: number
}

export function defaultUiSettings(): UiSettings {
  return {
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    musicEnabled: false,
    useMetricUnits: true,
    viewCoordinatesVisible: false,
    viewCoordinateFamily: 'equatorial',
    viewEquatorialEpoch: 'j2000',
    objectDetailConnectorVisible: true,
    astroTab: 5,
    astroGroup: 0,
    positionMode: 0,
    celestialPositionCategory: 'planets',
    celestialPositionMagnitude: 6,
    celestialPositionHorizontal: true,
    ephemerisMode: 0,
    ephemerisDays: 14,
    ephemerisStepHours: 24,
    rtsCalendarDays: 14,
    graphMode: 0,
    eclipseMonths: 36,
    moonPhaseDays: 30
  }
}

// Preferences 读写的宿主注入点（实现见 MainWindowNativeNode 的 HostSettingsPort）。
export interface SettingsPersistencePort {
  read(): Promise<string | null>
  write(json: string): Promise<boolean>
  clear(): Promise<boolean>
}

function boolOf(value: Object | undefined, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback
}

function numOf(value: Object | undefined, fallback: number): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value
  }
  if (typeof value === 'string') {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) {
      return parsed
    }
  }
  return fallback
}

function strOf(value: Object | undefined, fallback: string): string {
  return typeof value === 'string' ? value : fallback
}

function clampInt(value: number, min: number, max: number, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback
  }
  const rounded = Math.round(value)
  if (rounded < min) {
    return min
  }
  if (rounded > max) {
    return max
  }
  return rounded
}

// 解析并迁移。未知版本或损坏数据回退默认值，不抛异常。
export function migrateUiSettings(raw: string): UiSettings {
  const defaults = defaultUiSettings()
  let obj: Record<string, Object> = {}
  try {
    obj = JSON.parse(raw) as Record<string, Object>
  } catch (error) {
    return defaults
  }
  const version = numOf(obj['schemaVersion'], 0)
  if (version > SETTINGS_SCHEMA_VERSION) {
    return defaults
  }

  const out = defaultUiSettings()
  out.schemaVersion = SETTINGS_SCHEMA_VERSION
  out.musicEnabled = boolOf(obj['musicEnabled'], defaults.musicEnabled)
  out.useMetricUnits = boolOf(obj['useMetricUnits'], defaults.useMetricUnits)
  out.viewCoordinatesVisible = boolOf(obj['viewCoordinatesVisible'], defaults.viewCoordinatesVisible)
  out.viewCoordinateFamily = strOf(obj['viewCoordinateFamily'], defaults.viewCoordinateFamily)
  out.viewEquatorialEpoch = strOf(obj['viewEquatorialEpoch'], defaults.viewEquatorialEpoch)
  out.objectDetailConnectorVisible = boolOf(obj['objectDetailConnectorVisible'], defaults.objectDetailConnectorVisible)
  out.astroTab = clampInt(numOf(obj['astroTab'], defaults.astroTab), 0, 9, defaults.astroTab)
  out.astroGroup = clampInt(numOf(obj['astroGroup'], defaults.astroGroup), 0, 9, defaults.astroGroup)
  out.positionMode = clampInt(numOf(obj['positionMode'], defaults.positionMode), 0, 2, defaults.positionMode)
  out.celestialPositionCategory = strOf(obj['celestialPositionCategory'], defaults.celestialPositionCategory)
  out.celestialPositionMagnitude = numOf(obj['celestialPositionMagnitude'], defaults.celestialPositionMagnitude)
  out.celestialPositionHorizontal = boolOf(obj['celestialPositionHorizontal'], defaults.celestialPositionHorizontal)
  out.ephemerisMode = clampInt(numOf(obj['ephemerisMode'], defaults.ephemerisMode), 0, 2, defaults.ephemerisMode)
  out.ephemerisDays = clampInt(numOf(obj['ephemerisDays'], defaults.ephemerisDays), 1, 31, defaults.ephemerisDays)
  out.ephemerisStepHours = clampInt(numOf(obj['ephemerisStepHours'], defaults.ephemerisStepHours), 1, 24, defaults.ephemerisStepHours)
  out.rtsCalendarDays = clampInt(numOf(obj['rtsCalendarDays'], defaults.rtsCalendarDays), 1, 365, defaults.rtsCalendarDays)
  out.graphMode = clampInt(numOf(obj['graphMode'], defaults.graphMode), 0, 5, defaults.graphMode)
  out.eclipseMonths = numOf(obj['eclipseMonths'], defaults.eclipseMonths)
  out.moonPhaseDays = numOf(obj['moonPhaseDays'], defaults.moonPhaseDays)
  return out
}

export class SettingsRepository {
  private port: SettingsPersistencePort | null = null
  private current: UiSettings = defaultUiSettings()
  private loaded: boolean = false
  private lastError: string = ''

  attachPort(port: SettingsPersistencePort): void {
    this.port = port
  }

  isLoaded(): boolean {
    return this.loaded
  }

  snapshot(): UiSettings {
    return this.current
  }

  lastFailure(): string {
    return this.lastError
  }

  // 返回 true 表示存在可用的持久化数据；false 表示首次启动或无有效数据。
  // 调用方不得在 false 时用默认值覆盖各 store 的既有默认值。
  async load(): Promise<boolean> {
    const port = this.port
    if (port === null) {
      return false
    }
    try {
      const raw = await port.read()
      this.loaded = true
      if (raw === null || raw.length === 0) {
        return false
      }
      this.current = migrateUiSettings(raw)
      return true
    } catch (error) {
      this.lastError = 'read failed'
      this.loaded = true
      return false
    }
  }

  // 合并写入并异步落盘。调用方无需 await；失败记录在 lastFailure()。
  patch(next: UiSettings): void {
    this.current = next
    this.loaded = true
    const port = this.port
    if (port === null) {
      this.lastError = 'persistence port not attached'
      return
    }
    const payload = JSON.stringify(next)
    port.write(payload).then((ok: boolean) => {
      this.lastError = ok ? '' : 'write failed'
    }).catch(() => {
      this.lastError = 'write failed'
    })
  }

  async flush(next: UiSettings): Promise<boolean> {
    this.current = next
    this.loaded = true
    const port = this.port
    if (port === null) {
      this.lastError = 'persistence port not attached'
      return false
    }
    try {
      const ok = await port.write(JSON.stringify(next))
      this.lastError = ok ? '' : 'write failed'
      return ok
    } catch (error) {
      this.lastError = 'write failed'
      return false
    }
  }

  async resetToDefaults(): Promise<boolean> {
    this.current = defaultUiSettings()
    this.loaded = true
    const port = this.port
    if (port === null) {
      return false
    }
    try {
      return await port.clear()
    } catch (error) {
      this.lastError = 'clear failed'
      return false
    }
  }
}
