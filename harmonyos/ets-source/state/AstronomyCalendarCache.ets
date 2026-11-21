import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import hilog from '@ohos.hilog'
import { CalendarNativeResponse } from './AstronomyCalendarEvent'

const CACHE_FILE_NAME = 'astronomy_calendar_cache_v3.json'
const CACHE_SCHEMA_VERSION = 3
const MAX_CACHED_MONTHS = 48

interface SerializedCalendarCache {
  version: number
  entries: Record<string, CalendarNativeResponse>
  order: string[]
}

// 天文日历本地磁盘缓存：按「观测星球 + 年月 + 1° 定位桶」落盘保存月度原生响应，
// 冷启动时同步水合，秒开「搜索 → 日历」与完整日历列表，不再每次重算。
export class AstronomyCalendarCache {
  private static instance: AstronomyCalendarCache | null = null
  private cacheFilePath: string = ''
  private hydrated: boolean = false
  private entries: Map<string, CalendarNativeResponse> = new Map<string, CalendarNativeResponse>()
  private order: string[] = []
  private saveTimer: number = 0

  static getInstance(): AstronomyCalendarCache {
    if (AstronomyCalendarCache.instance === null) {
      AstronomyCalendarCache.instance = new AstronomyCalendarCache()
    }
    return AstronomyCalendarCache.instance
  }

  static makeKey(planet: string, year: number, month: number, latDeg?: number, lonDeg?: number): string {
    const p = (planet.trim().length > 0 ? planet.trim() : 'Earth').toLowerCase()
    const latB = latDeg !== undefined && Number.isFinite(latDeg) ? Math.round(latDeg) : 0
    const lonB = lonDeg !== undefined && Number.isFinite(lonDeg) ? Math.round(lonDeg) : 0
    return `${p}|${year}-${String(month).padStart(2, '0')}|${latB}|${lonB}`
  }

  initDir(filesDir: string): void {
    if (filesDir.trim().length === 0) return
    const nextPath = `${filesDir}/${CACHE_FILE_NAME}`
    if (this.hydrated && this.cacheFilePath === nextPath) return
    this.cacheFilePath = nextPath
    this.hydrated = true
    this.loadFromDiskSync()
  }

  get(key: string): CalendarNativeResponse | undefined {
    const hit = this.entries.get(key)
    if (hit !== undefined) {
      const idx = this.order.indexOf(key)
      if (idx >= 0) {
        this.order.splice(idx, 1)
        this.order.push(key)
      }
    }
    return hit
  }

  put(key: string, response: CalendarNativeResponse): void {
    if (response.ok !== true || !Array.isArray(response.events)) return
    this.entries.set(key, response)
    const idx = this.order.indexOf(key)
    if (idx >= 0) this.order.splice(idx, 1)
    this.order.push(key)
    while (this.order.length > MAX_CACHED_MONTHS) {
      const oldest = this.order.shift()
      if (oldest !== undefined) this.entries.delete(oldest)
    }
    this.scheduleSave()
  }

  private loadFromDiskSync(): void {
    if (this.cacheFilePath.length === 0) return
    try {
      if (!fileIo.accessSync(this.cacheFilePath)) return
      const stat = fileIo.statSync(this.cacheFilePath)
      if (stat.size <= 0 || stat.size > 4 * 1024 * 1024) return
      const file = fileIo.openSync(this.cacheFilePath, fileIo.OpenMode.READ_ONLY)
      try {
        const buf = new ArrayBuffer(stat.size)
        const bytesRead = fileIo.readSync(file.fd, buf)
        if (bytesRead <= 0) return
        const decoder = util.TextDecoder.create('utf-8')
        const text = decoder.decodeToString(new Uint8Array(buf, 0, bytesRead))
        const parsed = JSON.parse(text) as SerializedCalendarCache
        if (parsed === null || typeof parsed !== 'object' || parsed.version !== CACHE_SCHEMA_VERSION) return
        const keys = Array.isArray(parsed.order) ? parsed.order : Object.keys(parsed.entries ?? {})
        for (const k of keys) {
          const item = parsed.entries[k]
          if (item !== undefined && item !== null && item.ok === true && Array.isArray(item.events)) {
            this.entries.set(k, item)
            this.order.push(k)
          }
        }
        hilog.info(0x0000, 'StellariumArkUI', '[calendar-cache] hydrated %{public}d months from disk', this.entries.size)
      } finally {
        fileIo.closeSync(file.fd)
      }
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[calendar-cache] load skipped: %{public}s', String(err))
    }
  }

  private scheduleSave(): void {
    if (this.cacheFilePath.length === 0) return
    if (this.saveTimer !== 0) {
      clearTimeout(this.saveTimer)
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = 0
      this.flushToDisk()
    }, 380) as number
  }

  private flushToDisk(): void {
    if (this.cacheFilePath.length === 0) return
    try {
      const entriesObj: Record<string, CalendarNativeResponse> = {}
      for (const k of this.order) {
        const val = this.entries.get(k)
        if (val !== undefined) entriesObj[k] = val
      }
      const payload: SerializedCalendarCache = {
        version: CACHE_SCHEMA_VERSION,
        entries: entriesObj,
        order: this.order.slice()
      }
      const json = JSON.stringify(payload)
      const encoder = new util.TextEncoder()
      const encoded = encoder.encodeInto(json)
      const file = fileIo.openSync(this.cacheFilePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        fileIo.writeSync(file.fd, encoded.buffer)
      } finally {
        fileIo.closeSync(file.fd)
      }
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[calendar-cache] save failed: %{public}s', String(err))
    }
  }
}
