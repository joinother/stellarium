// 统一境内只读静态镜像客户端（https://skyinstrument.cn）：
// 供动态天象日历（RemoteCalendarFeedService）与太阳系小天体（MinorBodiesStore）共用，
// 集中提供 HTTP 只读拉取、SHA-256 哈希核验、/v1/manifest.json 内存短期缓存与并发请求去重，
// 杜绝多模块重复拉取同一份清单与重复实现哈希校验逻辑。

import { http } from '@kit.NetworkKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'

export const MIRROR_ORIGIN: string = 'https://skyinstrument.cn'
export const MIRROR_ROOT_MANIFEST_URL: string = MIRROR_ORIGIN + '/v1/manifest.json'
const ROOT_MANIFEST_CACHE_TTL_MS: number = 5 * 60 * 1000
const MAX_ROOT_MANIFEST_BYTES: number = 2 * 1024 * 1024

export interface MirrorHttpBufferResult {
  code: number
  bytes: Uint8Array
}

export interface RootMirrorSourceEntry {
  id?: string
  path?: string
  bytes?: number
  sha256?: string
  available?: boolean
  status?: string
  lastSuccessAt?: string | null
}

export interface RootMirrorManifest {
  generatedAt?: string
  sources?: Array<RootMirrorSourceEntry>
}

export interface VerifiedMirrorArtifactResult {
  ok: boolean
  code: number
  bytes: Uint8Array
  actualSha256: string
  errorKind: 'none' | 'invalid-path' | 'http' | 'size-mismatch' | 'sha256-mismatch' | 'network'
}

export function bytesToHex(bytes: Uint8Array): string {
  const hexChars = '0123456789abcdef'
  let out = ''
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i]
    out += hexChars[(b >> 4) & 0x0f] + hexChars[b & 0x0f]
  }
  return out
}

export async function computeSha256Hex(data: Uint8Array): Promise<string> {
  const md = cryptoFramework.createMd('SHA256')
  await md.update({ data: data })
  const digest = await md.digest()
  return bytesToHex(digest.data)
}

export function isSafeMirrorRelativePath(path: string, requiredPrefix: string = '/v1/'): boolean {
  if (typeof path !== 'string' || !path.startsWith(requiredPrefix)) return false
  if (path.includes('..') || path.includes('\\') || path.includes('?') || path.includes('#')) return false
  return true
}

export function findManifestSource(
  manifest: RootMirrorManifest | undefined,
  sourceId: string
): RootMirrorSourceEntry | undefined {
  if (manifest === undefined || !Array.isArray(manifest.sources)) return undefined
  for (let i = 0; i < manifest.sources.length; i++) {
    const entry = manifest.sources[i]
    if (entry !== undefined && entry.id === sourceId) {
      return entry
    }
  }
  return undefined
}

export class MirrorManifestClient {
  private static instance: MirrorManifestClient | null = null
  private cachedManifest: RootMirrorManifest | undefined = undefined
  private cachedManifestAt: number = 0
  private inflightManifest: Promise<RootMirrorManifest | undefined> | undefined = undefined

  static getInstance(): MirrorManifestClient {
    if (MirrorManifestClient.instance === null) {
      MirrorManifestClient.instance = new MirrorManifestClient()
    }
    return MirrorManifestClient.instance
  }

  async httpGetBuffer(url: string, maxLimitBytes: number, readTimeoutMs: number = 15000): Promise<MirrorHttpBufferResult> {
    const req = http.createHttp()
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: readTimeoutMs,
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

  async fetchRootManifest(force: boolean = false): Promise<RootMirrorManifest | undefined> {
    const now = Date.now()
    if (!force && this.cachedManifest !== undefined && (now - this.cachedManifestAt) < ROOT_MANIFEST_CACHE_TTL_MS) {
      return this.cachedManifest
    }
    if (this.inflightManifest !== undefined) {
      return this.inflightManifest
    }
    this.inflightManifest = (async (): Promise<RootMirrorManifest | undefined> => {
      try {
        const res = await this.httpGetBuffer(MIRROR_ROOT_MANIFEST_URL, MAX_ROOT_MANIFEST_BYTES)
        if (res.code !== 200 || res.bytes.byteLength <= 0) {
          return this.cachedManifest
        }
        const decoder = util.TextDecoder.create('utf-8')
        const parsed = JSON.parse(decoder.decodeToString(res.bytes)) as RootMirrorManifest
        if (parsed !== null && typeof parsed === 'object' && Array.isArray(parsed.sources)) {
          this.cachedManifest = parsed
          this.cachedManifestAt = Date.now()
          return parsed
        }
        return this.cachedManifest
      } catch (_err) {
        return this.cachedManifest
      } finally {
        this.inflightManifest = undefined
      }
    })()
    return this.inflightManifest
  }

  async fetchVerifiedArtifact(
    relativePath: string,
    expectedSha256: string,
    expectedBytes: number | undefined,
    maxLimitBytes: number,
    requiredPrefix: string = '/v1/'
  ): Promise<VerifiedMirrorArtifactResult> {
    const expectedHashLower = expectedSha256.trim().toLowerCase()
    if (!isSafeMirrorRelativePath(relativePath, requiredPrefix) || !/^[0-9a-f]{64}$/.test(expectedHashLower)) {
      return { ok: false, code: 0, bytes: new Uint8Array(0), actualSha256: '', errorKind: 'invalid-path' }
    }
    try {
      const resp = await this.httpGetBuffer(MIRROR_ORIGIN + relativePath, maxLimitBytes, 20000)
      if (resp.code !== 200 || resp.bytes.byteLength <= 0) {
        return { ok: false, code: resp.code, bytes: new Uint8Array(0), actualSha256: '', errorKind: 'http' }
      }
      if (expectedBytes !== undefined && expectedBytes > 0 && resp.bytes.byteLength !== expectedBytes) {
        return { ok: false, code: resp.code, bytes: new Uint8Array(0), actualSha256: '', errorKind: 'size-mismatch' }
      }
      const actualSha256 = await computeSha256Hex(resp.bytes)
      if (actualSha256 !== expectedHashLower) {
        return { ok: false, code: resp.code, bytes: new Uint8Array(0), actualSha256: actualSha256, errorKind: 'sha256-mismatch' }
      }
      return { ok: true, code: resp.code, bytes: resp.bytes, actualSha256: actualSha256, errorKind: 'none' }
    } catch (_err) {
      return { ok: false, code: 0, bytes: new Uint8Array(0), actualSha256: '', errorKind: 'network' }
    }
  }
}
