// 静态云端动态天象日历拉取与本地叠加层持久化服务（一期）。
// 仅从自有境内镜像 https://skyinstrument.cn 执行只读静态 GET + SHA-256 校验，
// 不上传经纬度、设备标识、Push Token 或搜索词；所有地理纬度/区域过滤均在端侧完成。

import { http } from '@kit.NetworkKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import hilog from '@ohos.hilog'
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent'
import { OFFLINE_APPGALLERY_BUILD } from '../common/types/MainWindowModels'
import {
  RemoteCalendarEntry,
  RemoteCalendarFeedDocument,
  RemoteCalendarManifest,
  validateRemoteCalendarFeed,
  validateRemoteCalendarManifest
} from '../state/RemoteCalendarFeed'

const FEED_ORIGIN: string = 'https://skyinstrument.cn'
const CALENDAR_MANIFEST_URL: string = FEED_ORIGIN + '/v1/calendar/manifest.json'
const ROOT_MANIFEST_URL: string = FEED_ORIGIN + '/v1/manifest.json'
const ROOT_MANIFEST_SOURCE_ID: string = 'calendar.dynamic-feed'
const OVERLAY_FILE_NAME: string = 'astronomy_remote_calendar_v1.json'
const AUTO_SYNC_INTERVAL_MS: number = 30 * 60 * 1000
const MAX_MANIFEST_BYTES: number = 2 * 1024 * 1024
const MAX_FEED_BYTES: number = 1024 * 1024

interface PersistedRemoteOverlay {
  version: number
  generation: number
  sha256: string
  updatedAt: number
  lastCheckedAt: number
  lastSyncedAt: number
  entries: RemoteCalendarEntry[]
}

interface RootMirrorSourceEntry {
  id?: string
  path?: string
  bytes?: number
  sha256?: string
  available?: boolean
  lastSuccessAt?: string | null
}

interface RootMirrorManifest {
  generatedAt?: string
  sources?: Array<RootMirrorSourceEntry>
}

interface HttpBufferResult {
  code: number
  bytes: Uint8Array
}

export interface RemoteCalendarSyncResult {
  ok: boolean
  changed: boolean
  skipped: boolean
  entryCount: number
  generation: number
  statusZh: string
  statusEn: string
  reason?: string
}

function bytesToHex(bytes: Uint8Array): string {
  const hexChars = '0123456789abcdef'
  let out = ''
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i]
    out += hexChars[(b >> 4) & 0x0f] + hexChars[b & 0x0f]
  }
  return out
}

async function computeSha256Hex(data: Uint8Array): Promise<string> {
  const md = cryptoFramework.createMd('SHA256')
  await md.update({ data: data })
  const digest = await md.digest()
  return bytesToHex(digest.data)
}

export class RemoteCalendarFeedService {
  private static instance: RemoteCalendarFeedService | null = null
  private overlayFilePath: string = ''
  private hydrated: boolean = false
  private syncing: boolean = false
  private generation: number = 0
  private sha256: string = ''
  private updatedAt: number = 0
  private lastCheckedAt: number = 0
  private lastSyncedAt: number = 0
  private entries: RemoteCalendarEntry[] = []

  static getInstance(): RemoteCalendarFeedService {
    if (RemoteCalendarFeedService.instance === null) {
      RemoteCalendarFeedService.instance = new RemoteCalendarFeedService()
    }
    return RemoteCalendarFeedService.instance
  }

  initDir(filesDir: string): void {
    const trimmed = filesDir.trim()
    if (trimmed.length === 0) return
    const nextPath = `${trimmed}/${OVERLAY_FILE_NAME}`
    if (this.hydrated && this.overlayFilePath === nextPath) return
    this.overlayFilePath = nextPath
    this.hydrated = true
    this.loadFromDiskSync()
  }

  getEntries(): RemoteCalendarEntry[] {
    return this.entries.slice()
  }

  getGeneration(): number {
    return this.generation
  }

  isSyncing(): boolean {
    return this.syncing
  }

  summaryText(language: string): string {
    const isZh = language.toLowerCase().startsWith('zh')
    if (this.entries.length > 0) {
      const count = this.entries.length
      if (this.lastSyncedAt > 0) {
        const d = new Date(this.lastSyncedAt)
        const hh = String(d.getHours()).padStart(2, '0')
        const mm = String(d.getMinutes()).padStart(2, '0')
        return isZh
          ? `已同步 ${count} 条动态 · ${hh}:${mm}`
          : `${count} live alert(s) · ${hh}:${mm}`
      }
      return isZh ? `已缓存 ${count} 条动态天象` : `${count} cached live alert(s)`
    }
    if (this.lastCheckedAt > 0) {
      const d = new Date(this.lastCheckedAt)
      const hh = String(d.getHours()).padStart(2, '0')
      const mm = String(d.getMinutes()).padStart(2, '0')
      return isZh ? `云端动态最新 · ${hh}:${mm}` : `Live feed fresh · ${hh}:${mm}`
    }
    return isZh ? '云端动态 · 极光与彗星' : 'Live aurora & comet alerts'
  }

  private loadFromDiskSync(): void {
    if (this.overlayFilePath.length === 0) return
    try {
      if (!fileIo.accessSync(this.overlayFilePath)) return
      const stat = fileIo.statSync(this.overlayFilePath)
      if (stat.size <= 0 || stat.size > MAX_FEED_BYTES * 2) return
      const file = fileIo.openSync(this.overlayFilePath, fileIo.OpenMode.READ_ONLY)
      try {
        const buf = new ArrayBuffer(stat.size)
        const bytesRead = fileIo.readSync(file.fd, buf)
        if (bytesRead <= 0) return
        const decoder = util.TextDecoder.create('utf-8')
        const text = decoder.decodeToString(new Uint8Array(buf, 0, bytesRead))
        const parsed = JSON.parse(text) as PersistedRemoteOverlay
        if (parsed === null || typeof parsed !== 'object' || parsed.version !== 1) return
        const validated = validateRemoteCalendarFeed({
          schemaVersion: 1,
          generation: parsed.generation > 0 ? parsed.generation : 1,
          updatedAt: parsed.updatedAt > 0 ? parsed.updatedAt : Date.now(),
          entries: parsed.entries ?? []
        }, Date.now())
        if (validated === undefined) return
        this.generation = validated.generation
        this.sha256 = typeof parsed.sha256 === 'string' ? parsed.sha256 : ''
        this.updatedAt = validated.updatedAt
        this.lastCheckedAt = Number.isFinite(parsed.lastCheckedAt) ? parsed.lastCheckedAt : 0
        this.lastSyncedAt = Number.isFinite(parsed.lastSyncedAt) ? parsed.lastSyncedAt : 0
        this.entries = validated.entries
        hilog.info(0x0000, 'StellariumArkUI', '[remote-calendar] hydrated %{public}d entries gen=%{public}d',
          this.entries.length, this.generation)
      } finally {
        fileIo.closeSync(file.fd)
      }
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[remote-calendar] load skipped: %{public}s', String(err))
    }
  }

  private persistToDiskSync(): void {
    if (this.overlayFilePath.length === 0) return
    try {
      const payload: PersistedRemoteOverlay = {
        version: 1,
        generation: this.generation,
        sha256: this.sha256,
        updatedAt: this.updatedAt,
        lastCheckedAt: this.lastCheckedAt,
        lastSyncedAt: this.lastSyncedAt,
        entries: this.entries
      }
      const json = JSON.stringify(payload)
      const encoder = new util.TextEncoder()
      const encoded = encoder.encodeInto(json)
      const file = fileIo.openSync(this.overlayFilePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        fileIo.writeSync(file.fd, encoded.buffer)
      } finally {
        fileIo.closeSync(file.fd)
      }
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[remote-calendar] persist failed: %{public}s', String(err))
    }
  }

  private async httpGet(url: string, maxLimitBytes: number): Promise<HttpBufferResult> {
    const req = http.createHttp()
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxLimit: maxLimitBytes,
        usingCache: false
      })
      const code = Number(resp.responseCode)
      const buf = resp.result as ArrayBuffer
      const bytes = (buf !== undefined && buf !== null && buf.byteLength > 0)
        ? new Uint8Array(buf)
        : new Uint8Array(0)
      return { code: code, bytes: bytes }
    } finally {
      req.destroy()
    }
  }

  private async resolveRemoteManifest(): Promise<RemoteCalendarManifest | undefined> {
    const decoder = util.TextDecoder.create('utf-8')
    // 1. 优先读取独立动态日历清单 /v1/calendar/manifest.json
    const direct = await this.httpGet(CALENDAR_MANIFEST_URL, MAX_MANIFEST_BYTES)
    if (direct.code === 200 && direct.bytes.byteLength > 0) {
      try {
        const parsed = JSON.parse(decoder.decodeToString(direct.bytes)) as Object
        const valid = validateRemoteCalendarManifest(parsed)
        if (valid !== undefined) return valid
      } catch (_) {}
    }
    // 2. 兼容在全站 /v1/manifest.json 中登记的 calendar.dynamic-feed 静态源
    const root = await this.httpGet(ROOT_MANIFEST_URL, MAX_MANIFEST_BYTES)
    if (root.code !== 200 || root.bytes.byteLength === 0) return undefined
    try {
      const parsed = JSON.parse(decoder.decodeToString(root.bytes)) as RootMirrorManifest
      const sources = Array.isArray(parsed.sources) ? parsed.sources : []
      for (const s of sources) {
        if (s.id === ROOT_MANIFEST_SOURCE_ID && s.available === true &&
          typeof s.path === 'string' && typeof s.sha256 === 'string' && typeof s.bytes === 'number') {
          const updatedAt = typeof s.lastSuccessAt === 'string' && Number.isFinite(Date.parse(s.lastSuccessAt))
            ? Date.parse(s.lastSuccessAt)
            : (typeof parsed.generatedAt === 'string' && Number.isFinite(Date.parse(parsed.generatedAt))
              ? Date.parse(parsed.generatedAt) : Date.now())
          const gen = Math.max(1, Math.floor(updatedAt / 1000))
          return validateRemoteCalendarManifest({
            schemaVersion: 1,
            generation: gen,
            updatedAt: updatedAt,
            feedPath: s.path,
            bytes: s.bytes,
            sha256: s.sha256
          })
        }
      }
    } catch (_) {}
    return undefined
  }

  applyValidatedFeed(doc: RemoteCalendarFeedDocument, sha256: string = ''): boolean {
    const prevSerialized = JSON.stringify(this.entries)
    const nextSerialized = JSON.stringify(doc.entries)
    const changed = prevSerialized !== nextSerialized || doc.generation !== this.generation
    this.generation = doc.generation
    this.sha256 = sha256
    this.updatedAt = doc.updatedAt
    this.lastCheckedAt = Date.now()
    this.lastSyncedAt = Date.now()
    this.entries = doc.entries.slice()
    this.persistToDiskSync()
    return changed
  }

  async syncIfDue(onlineAllowed: boolean, force: boolean = false): Promise<RemoteCalendarSyncResult> {
    if (this.syncing) {
      return {
        ok: true, changed: false, skipped: true, entryCount: this.entries.length, generation: this.generation,
        statusZh: '正在检查云端动态天象…', statusEn: 'Checking live astronomy alerts…', reason: 'already-syncing'
      }
    }
    if (OFFLINE_APPGALLERY_BUILD || !onlineAllowed || !hasCurrentPrivacyConsent()) {
      return {
        ok: false, changed: false, skipped: true, entryCount: this.entries.length, generation: this.generation,
        statusZh: '离线模式 · 仅本地历表', statusEn: 'Offline · local ephemeris',
        reason: 'offline-or-no-consent'
      }
    }
    const now = Date.now()
    if (!force && this.lastCheckedAt > 0 && (now - this.lastCheckedAt) < AUTO_SYNC_INTERVAL_MS) {
      return {
        ok: true, changed: false, skipped: true, entryCount: this.entries.length, generation: this.generation,
        statusZh: this.summaryText('zh'), statusEn: this.summaryText('en'), reason: 'throttled'
      }
    }

    this.syncing = true
    try {
      const manifest = await this.resolveRemoteManifest()
      this.lastCheckedAt = Date.now()
      if (manifest === undefined) {
        this.persistToDiskSync()
        return {
          ok: true, changed: false, skipped: false, entryCount: this.entries.length, generation: this.generation,
          statusZh: this.entries.length > 0 ? this.summaryText('zh') : '云端动态 · 暂无新增',
          statusEn: this.entries.length > 0 ? this.summaryText('en') : 'Live feed · no new alerts',
          reason: 'no-remote-feed-published'
        }
      }

      if (!force && manifest.generation === this.generation && manifest.sha256 === this.sha256) {
        this.persistToDiskSync()
        return {
          ok: true, changed: false, skipped: false, entryCount: this.entries.length, generation: this.generation,
          statusZh: this.summaryText('zh'), statusEn: this.summaryText('en'), reason: 'up-to-date'
        }
      }

      const feedResp = await this.httpGet(FEED_ORIGIN + manifest.feedPath, MAX_FEED_BYTES)
      if (feedResp.code !== 200 || feedResp.bytes.byteLength <= 0) {
        return {
          ok: false, changed: false, skipped: false, entryCount: this.entries.length, generation: this.generation,
          statusZh: '拉取失败 · 保留本地缓存', statusEn: 'Fetch failed · kept cache',
          reason: 'http-' + String(feedResp.code)
        }
      }
      if (feedResp.bytes.byteLength !== manifest.bytes) {
        hilog.warn(0x0000, 'StellariumArkUI', '[remote-calendar] size mismatch got=%{public}d expected=%{public}d',
          feedResp.bytes.byteLength, manifest.bytes)
        return {
          ok: false, changed: false, skipped: false, entryCount: this.entries.length, generation: this.generation,
          statusZh: '大小校验未通过 · 已拒收', statusEn: 'Size check failed',
          reason: 'size-mismatch'
        }
      }
      const actualHash = await computeSha256Hex(feedResp.bytes)
      if (actualHash !== manifest.sha256) {
        hilog.warn(0x0000, 'StellariumArkUI', '[remote-calendar] sha256 mismatch')
        return {
          ok: false, changed: false, skipped: false, entryCount: this.entries.length, generation: this.generation,
          statusZh: 'SHA-256 校验失败 · 已拒收', statusEn: 'SHA-256 check failed',
          reason: 'sha256-mismatch'
        }
      }

      const decoder = util.TextDecoder.create('utf-8')
      const parsed = JSON.parse(decoder.decodeToString(feedResp.bytes)) as Object
      const validated = validateRemoteCalendarFeed(parsed, Date.now())
      if (validated === undefined) {
        return {
          ok: false, changed: false, skipped: false, entryCount: this.entries.length, generation: this.generation,
          statusZh: '格式校验未通过 · 保留缓存', statusEn: 'Invalid feed · kept cache',
          reason: 'invalid-schema'
        }
      }

      const changed = this.applyValidatedFeed(validated, actualHash)
      hilog.info(0x0000, 'StellariumArkUI', '[remote-calendar] synced gen=%{public}d entries=%{public}d changed=%{public}s',
        this.generation, this.entries.length, changed ? '1' : '0')
      return {
        ok: true, changed: changed, skipped: false, entryCount: this.entries.length, generation: this.generation,
        statusZh: this.summaryText('zh'), statusEn: this.summaryText('en')
      }
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[remote-calendar] sync error: %{public}s', String(err))
      return {
        ok: false, changed: false, skipped: false, entryCount: this.entries.length, generation: this.generation,
        statusZh: '网络不可用 · 本地历表', statusEn: 'Network unavailable · local',
        reason: 'network-error'
      }
    } finally {
      this.syncing = false
    }
  }
}
