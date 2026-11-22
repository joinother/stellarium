// 太阳系小天体管理（SolarSystemEditor 离线目录 + 统一境内镜像 MirrorManifestClient 实时 MPC 同步）域 store。
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import hilog from '@ohos.hilog'
import { CommandPort } from '../bridge/CommandPort'
import { MinorBodyItem, StellariumBridgeResponse } from '../common/types/StellariumTypes'
import { OFFLINE_APPGALLERY_BUILD } from '../common/types/MainWindowModels'
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent'
import {
  MirrorManifestClient,
  findManifestSource
} from '../capability/MirrorManifestClient'

const COMET_AUTO_SYNC_FILE: string = 'minor_bodies_auto_sync_v1.json'
const COMET_AUTO_SYNC_INTERVAL_MS: number = 7 * 24 * 3600 * 1000

export interface MpcMirrorPackSpec {
  key: string
  sourceId: string
  kind: string
  maxItems: number
  label: string
}

export const MPC_MIRROR_PACKS: Array<MpcMirrorPackSpec> = [
  { key: 'comets', sourceId: 'catalog.mpc.comets', kind: 'comet', maxItems: 1000, label: '最新可观测彗星' },
  { key: 'bright', sourceId: 'catalog.mpc.bright-asteroids', kind: 'asteroid', maxItems: 350, label: '年度冲日亮小行星' },
  { key: 'critlist', sourceId: 'catalog.mpc.critlist-asteroids', kind: 'asteroid', maxItems: 350, label: '近地与关键小行星' },
  { key: 'distant', sourceId: 'catalog.mpc.distant', kind: 'asteroid', maxItems: 350, label: '外海王星与半人马' }
]

interface PersistedCometSyncMeta {
  version: number
  lastCheckedAt: number
  lastSyncedAt: number
  cometsSha256: string
}

@Observed
export class MinorBodiesStore {
  items: Array<MinorBodyItem> = []
  loading: boolean = false
  busy: boolean = false
  error: string = ''
  category: string = 'all'
  query: string = ''
  totalCount: number = 0
  matchedCount: number = 0
  countComet: number = 0
  countAsteroid: number = 0
  countDwarf: number = 0
  countTno: number = 0
  bundledCometsAvailable: boolean = false
  precisionAsteroidsAvailable: boolean = false
  mirrorSyncingPack: string = ''
  mirrorStatusText: string = ''

  private port: CommandPort | null = null
  private seq: number = 0
  private onFlashHint: (msg: string) => void = () => {}
  private syncMetaPath: string = ''
  private syncMetaHydrated: boolean = false
  private autoCometSyncing: boolean = false
  private lastCometCheckedAt: number = 0
  private lastCometSyncedAt: number = 0
  private lastCometSha256: string = ''

  bind(port: CommandPort, onFlashHint: (msg: string) => void): void {
    this.port = port
    this.onFlashHint = onFlashHint
  }

  initDir(filesDir: string): void {
    const trimmed = filesDir.trim()
    if (trimmed.length === 0) return
    const nextPath = `${trimmed}/${COMET_AUTO_SYNC_FILE}`
    if (this.syncMetaHydrated && this.syncMetaPath === nextPath) return
    this.syncMetaPath = nextPath
    this.syncMetaHydrated = true
    this.loadCometSyncMetaSync()
  }

  private loadCometSyncMetaSync(): void {
    if (this.syncMetaPath.length === 0) return
    try {
      if (!fileIo.accessSync(this.syncMetaPath)) return
      const stat = fileIo.statSync(this.syncMetaPath)
      if (stat.size <= 0 || stat.size > 16384) return
      const file = fileIo.openSync(this.syncMetaPath, fileIo.OpenMode.READ_ONLY)
      try {
        const buf = new ArrayBuffer(stat.size)
        const n = fileIo.readSync(file.fd, buf)
        if (n <= 0) return
        const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf, 0, n))
        const parsed = JSON.parse(text) as PersistedCometSyncMeta
        if (parsed !== null && typeof parsed === 'object' && parsed.version === 1) {
          this.lastCometCheckedAt = Number.isFinite(parsed.lastCheckedAt) ? parsed.lastCheckedAt : 0
          this.lastCometSyncedAt = Number.isFinite(parsed.lastSyncedAt) ? parsed.lastSyncedAt : 0
          this.lastCometSha256 = typeof parsed.cometsSha256 === 'string' ? parsed.cometsSha256.toLowerCase() : ''
        }
      } finally {
        fileIo.closeSync(file.fd)
      }
    } catch (_err) {
      // Ignore corrupt/missing cache metadata
    }
  }

  private persistCometSyncMetaSync(): void {
    if (this.syncMetaPath.length === 0) return
    try {
      const payload: PersistedCometSyncMeta = {
        version: 1,
        lastCheckedAt: this.lastCometCheckedAt,
        lastSyncedAt: this.lastCometSyncedAt,
        cometsSha256: this.lastCometSha256
      }
      const encoded = new util.TextEncoder().encodeInto(JSON.stringify(payload))
      const file = fileIo.openSync(this.syncMetaPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        fileIo.writeSync(file.fd, encoded.buffer)
      } finally {
        fileIo.closeSync(file.fd)
      }
    } catch (_err) {
      // Non-fatal
    }
  }

  load(): void {
    if (this.port === null) return
    const reqId = ++this.seq
    this.loading = true
    this.error = ''
    const payload = JSON.stringify({
      category: this.category,
      query: this.query.trim(),
      limit: 80
    })
    this.port.requestInteractive('getMinorBodies', payload, (r: StellariumBridgeResponse) => {
      if (reqId !== this.seq) return
      this.loading = false
      if (r.ok === true && Array.isArray(r.items)) {
        this.items = r.items as Array<MinorBodyItem>
        this.totalCount = Number(r.totalCount ?? this.items.length)
        this.matchedCount = Number(r.matchedCount ?? this.items.length)
        this.bundledCometsAvailable = r.bundledCometsAvailable === true
        this.precisionAsteroidsAvailable = r.precisionAsteroidsAvailable === true
        const counts = r.counts as Record<string, number> | undefined
        if (counts !== undefined) {
          this.countComet = Number(counts['comet'] ?? 0)
          this.countAsteroid = Number(counts['asteroid'] ?? 0)
          this.countDwarf = Number(counts['dwarf'] ?? 0)
          this.countTno = Number(counts['tno'] ?? 0)
        }
      } else {
        this.error = r.error ?? '读取太阳系小天体目录失败，请重试。'
      }
    }, () => {
      if (reqId !== this.seq) return
      this.loading = false
      this.error = '读取小天体目录超时，请重试。'
    })
  }

  importBundledComets(): void {
    if (this.port === null || this.busy) return
    this.busy = true
    this.port.requestWhenReady('importMinorBodies', JSON.stringify({ action: 'importBundledComets' }), (r: StellariumBridgeResponse) => {
      this.busy = false
      if (r.ok === true) {
        this.onFlashHint('已导入内置千颗彗星目录')
        this.load()
      } else {
        this.onFlashHint(r.error ?? '导入内置彗星库失败')
      }
    }, () => {
      this.busy = false
      this.onFlashHint('导入彗星库耗时较长，请稍后点刷新查看')
    }, 0, 100, 300)
  }

  // 静默自动同步最新可观测彗星（默认 7 天节流，或当云端日历下发新彗星预警时立即触发）：
  // 复用 MirrorManifestClient 共享的 /v1/manifest.json 缓存 + SHA-256 哈希短路，无更新时零流量下载。
  async syncCometsIfDue(onlineAllowed: boolean, forceForCalendarComet: boolean = false): Promise<boolean> {
    if (OFFLINE_APPGALLERY_BUILD || !onlineAllowed || !hasCurrentPrivacyConsent()) return false
    if (this.port === null || this.busy || this.autoCometSyncing) return false
    const now = Date.now()
    if (!forceForCalendarComet && this.lastCometCheckedAt > 0 &&
      (now - this.lastCometCheckedAt) < COMET_AUTO_SYNC_INTERVAL_MS) {
      return false
    }
    this.autoCometSyncing = true
    try {
      const client = MirrorManifestClient.getInstance()
      const manifest = await client.fetchRootManifest(false)
      this.lastCometCheckedAt = Date.now()
      const entry = findManifestSource(manifest, 'catalog.mpc.comets')
      if (entry === undefined || entry.available !== true || typeof entry.path !== 'string' ||
        typeof entry.sha256 !== 'string' || entry.sha256.length !== 64) {
        this.persistCometSyncMetaSync()
        return false
      }
      const remoteHash = entry.sha256.toLowerCase()
      if (remoteHash === this.lastCometSha256) {
        this.persistCometSyncMetaSync()
        return false
      }
      const artifact = await client.fetchVerifiedArtifact(
        entry.path,
        remoteHash,
        entry.bytes,
        8 * 1024 * 1024,
        '/v1/catalogs/mpc/'
      )
      if (!artifact.ok) {
        this.persistCometSyncMetaSync()
        return false
      }
      const mpcText = util.TextDecoder.create('utf-8').decodeToString(artifact.bytes)
      const port = this.port
      if (port === null) return false
      return await new Promise<boolean>((resolve) => {
        port.requestWhenReady('importMinorBodies', JSON.stringify({
          action: 'importMpcText',
          kind: 'comet',
          text: mpcText,
          maxItems: 1000
        }), (r: StellariumBridgeResponse) => {
          if (r.ok === true) {
            const importedCount = Number(r.importedCount ?? 0)
            this.lastCometSha256 = artifact.actualSha256
            this.lastCometSyncedAt = Date.now()
            this.persistCometSyncMetaSync()
            this.mirrorStatusText = 'skyinstrument.cn · 已自动同步最新彗星（' + String(importedCount) + ' 颗）'
            hilog.info(0x0000, 'StellariumArkUI', '[minor-bodies] auto-synced comets count=%{public}d trigger=%{public}s',
              importedCount, forceForCalendarComet ? 'calendar-comet' : '7d-schedule')
            resolve(true)
          } else {
            this.persistCometSyncMetaSync()
            resolve(false)
          }
        }, () => {
          this.persistCometSyncMetaSync()
          resolve(false)
        }, 0, 200, 60)
      })
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[minor-bodies] auto comet sync skipped: %{public}s', String(err))
      return false
    } finally {
      this.autoCometSyncing = false
    }
  }

  async syncMirrorPack(packKey: string, onlineAllowed: boolean): Promise<void> {
    if (this.port === null || this.busy) return
    if (OFFLINE_APPGALLERY_BUILD || !onlineAllowed) {
      this.onFlashHint('当前未开启联网权限，可使用内置离线千颗彗星库或手动 MPC 导入')
      return
    }
    let spec: MpcMirrorPackSpec | undefined = undefined
    for (const p of MPC_MIRROR_PACKS) {
      if (p.key === packKey) {
        spec = p
        break
      }
    }
    if (spec === undefined) return

    this.busy = true
    this.mirrorSyncingPack = packKey
    this.mirrorStatusText = '正在向国内镜像 skyinstrument.cn 校验清单…'
    try {
      const client = MirrorManifestClient.getInstance()
      const manifest = await client.fetchRootManifest(true)
      const entry = findManifestSource(manifest, spec.sourceId)
      if (entry === undefined || entry.available !== true || typeof entry.path !== 'string' ||
        !entry.path.startsWith('/v1/catalogs/mpc/') || typeof entry.sha256 !== 'string' || entry.sha256.length !== 64) {
        this.busy = false
        this.mirrorSyncingPack = ''
        this.mirrorStatusText = '镜像清单中该目录暂不可用，已保留本地数据'
        this.onFlashHint('国内镜像中该小天体目录暂不可用')
        return
      }

      this.mirrorStatusText = '正在下载并校验 SHA-256（' + spec.label + '）…'
      const artifact = await client.fetchVerifiedArtifact(
        entry.path,
        entry.sha256,
        entry.bytes,
        8 * 1024 * 1024,
        '/v1/catalogs/mpc/'
      )
      if (!artifact.ok) {
        this.busy = false
        this.mirrorSyncingPack = ''
        if (artifact.errorKind === 'size-mismatch') {
          this.mirrorStatusText = '文件大小与清单不符，已拒绝写入'
          this.onFlashHint('国内镜像校验未通过，已保留本地数据')
        } else if (artifact.errorKind === 'sha256-mismatch') {
          this.mirrorStatusText = 'SHA-256 校验未通过，已拒绝写入'
          this.onFlashHint('国内镜像哈希校验失败，已拒绝写入')
        } else {
          this.mirrorStatusText = '镜像同步失败（' + (artifact.code > 0 ? 'HTTP ' + String(artifact.code) : artifact.errorKind) + '），已保留本地离线目录'
          this.onFlashHint('国内镜像同步失败，请稍后重试')
        }
        return
      }

      const mpcText = util.TextDecoder.create('utf-8').decodeToString(artifact.bytes)
      this.mirrorStatusText = 'SHA-256 校验通过，正在导入星图…'
      const currentSpec = spec
      const verifiedHash = artifact.actualSha256
      const updatedStamp = typeof entry.lastSuccessAt === 'string' && entry.lastSuccessAt.length >= 16
        ? entry.lastSuccessAt.slice(0, 16).replace('T', ' ') + ' UTC'
        : ''
      this.port.requestWhenReady('importMinorBodies', JSON.stringify({
        action: 'importMpcText',
        kind: currentSpec.kind,
        text: mpcText,
        maxItems: currentSpec.maxItems
      }), (r: StellariumBridgeResponse) => {
        this.busy = false
        this.mirrorSyncingPack = ''
        if (r.ok === true) {
          const importedCount = Number(r.importedCount ?? 0)
          const totalParsed = Number(r.totalParsed ?? importedCount)
          if (currentSpec.key === 'comets') {
            this.lastCometSha256 = verifiedHash
            this.lastCometCheckedAt = Date.now()
            this.lastCometSyncedAt = Date.now()
            this.persistCometSyncMetaSync()
          }
          this.mirrorStatusText = 'skyinstrument.cn · SHA-256 已校验 · ' + currentSpec.label + '（导入 ' + String(importedCount) + ' 颗）' +
            (updatedStamp.length > 0 ? ' · ' + updatedStamp : '')
          this.onFlashHint('国内镜像同步完成：' + currentSpec.label + '（导入 ' + String(importedCount) + '/' + String(totalParsed) + ' 颗）')
          this.load()
        } else {
          this.mirrorStatusText = r.error ?? '导入星图失败'
          this.onFlashHint(r.error ?? '同步小天体目录失败')
        }
      }, () => {
        this.busy = false
        this.mirrorSyncingPack = ''
        this.mirrorStatusText = '写入星图耗时较长或失败，请稍后点刷新查看'
        this.onFlashHint('写入星图耗时较长，请稍后点刷新')
      }, 0, 200, 60)
    } catch (err) {
      this.busy = false
      this.mirrorSyncingPack = ''
      const msg = err instanceof Error ? err.message : '网络异常'
      this.mirrorStatusText = '镜像同步失败（' + msg + '），已保留本地离线目录'
      this.onFlashHint('国内镜像同步失败，请稍后重试')
    }
  }

  importMpcLine(kind: string, line: string, onSuccess?: () => void): void {
    if (this.port === null || this.busy) return
    const trimmed = line.trim()
    if (trimmed.length === 0) {
      this.onFlashHint('请先粘贴完整的 MPC 单行轨道根数')
      return
    }
    this.busy = true
    this.port.requestInteractive('importMinorBodies', JSON.stringify({
      action: 'importMpcLine',
      kind: kind,
      line: trimmed
    }), (r: StellariumBridgeResponse) => {
      this.busy = false
      if (r.ok === true) {
        const name = typeof r.importedName === 'string' && r.importedName.length > 0 ? r.importedName : '新小天体'
        this.onFlashHint('已添加：' + name)
        if (onSuccess !== undefined) onSuccess()
        this.load()
      } else {
        this.onFlashHint(r.error ?? 'MPC 轨道根数解析失败')
      }
    }, () => {
      this.busy = false
      this.onFlashHint('导入失败，请重试')
    })
  }

  removeBody(englishName: string): void {
    if (this.port === null || this.busy) return
    this.busy = true
    this.port.requestInteractive('importMinorBodies', JSON.stringify({
      action: 'remove',
      name: englishName
    }), (r: StellariumBridgeResponse) => {
      this.busy = false
      if (r.ok === true) {
        this.onFlashHint('已移除：' + englishName)
        this.load()
      } else {
        this.onFlashHint(r.error ?? '移除失败')
      }
    }, () => {
      this.busy = false
    })
  }

  resetDefault(): void {
    if (this.port === null || this.busy) return
    this.busy = true
    this.port.requestInteractive('importMinorBodies', JSON.stringify({
      action: 'resetDefault'
    }), (r: StellariumBridgeResponse) => {
      this.busy = false
      if (r.ok === true) {
        this.mirrorStatusText = ''
        this.onFlashHint('已恢复默认太阳系小天体目录')
        this.load()
      } else {
        this.onFlashHint(r.error ?? '恢复默认目录失败')
      }
    }, () => {
      this.busy = false
    })
  }
}
