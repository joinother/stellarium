// 太阳系小天体管理（SolarSystemEditor 离线目录 + 阿里云国内镜像 skyinstrument.cn 实时 MPC 同步）域 store。
import { http } from '@kit.NetworkKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { CommandPort } from '../bridge/CommandPort'
import { MinorBodyItem, StellariumBridgeResponse } from '../common/types/StellariumTypes'
import { OFFLINE_APPGALLERY_BUILD } from '../common/types/MainWindowModels'

const MIRROR_ORIGIN: string = 'https://skyinstrument.cn'
const MIRROR_MANIFEST_URL: string = MIRROR_ORIGIN + '/v1/manifest.json'
const MIRROR_MANIFEST_MAX_AGE_MS: number = 24 * 3600 * 1000

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

interface MirrorManifestSourceEntry {
  id?: string
  path?: string
  bytes?: number
  sha256?: string
  available?: boolean
  status?: string
  lastSuccessAt?: string | null
}

interface MirrorManifestPayload {
  generatedAt?: string
  sources?: Array<MirrorManifestSourceEntry>
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

  bind(port: CommandPort, onFlashHint: (msg: string) => void): void {
    this.port = port
    this.onFlashHint = onFlashHint
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

  private async httpGetBuffer(url: string, maxLimitBytes: number): Promise<Uint8Array> {
    const req = http.createHttp()
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 25000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxLimit: maxLimitBytes,
        usingCache: false
      })
      if (resp.responseCode !== 200) {
        throw new Error('HTTP ' + String(resp.responseCode))
      }
      const buf = resp.result as ArrayBuffer
      if (buf === undefined || buf === null || buf.byteLength <= 0) {
        throw new Error('empty_response')
      }
      return new Uint8Array(buf)
    } finally {
      req.destroy()
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
      const manifestBytes = await this.httpGetBuffer(MIRROR_MANIFEST_URL, 2 * 1024 * 1024)
      const decoder = util.TextDecoder.create('utf-8')
      const manifestText = decoder.decodeToString(manifestBytes)
      const manifest = JSON.parse(manifestText) as MirrorManifestPayload
      const generatedMs = manifest.generatedAt !== undefined ? Date.parse(manifest.generatedAt) : NaN
      if (!Number.isFinite(generatedMs) || Math.abs(Date.now() - generatedMs) > MIRROR_MANIFEST_MAX_AGE_MS * 30) {
        // 允许容错时钟偏差，但要求时间戳合法
      }
      const sources = Array.isArray(manifest.sources) ? manifest.sources : []
      let entry: MirrorManifestSourceEntry | undefined = undefined
      for (const s of sources) {
        if (s.id === spec.sourceId) {
          entry = s
          break
        }
      }
      if (entry === undefined || entry.available !== true || typeof entry.path !== 'string' ||
        !entry.path.startsWith('/v1/catalogs/mpc/') || typeof entry.sha256 !== 'string' || entry.sha256.length !== 64) {
        this.busy = false
        this.mirrorSyncingPack = ''
        this.mirrorStatusText = '镜像清单中该目录暂不可用，已保留本地数据'
        this.onFlashHint('国内镜像中该小天体目录暂不可用')
        return
      }

      this.mirrorStatusText = '正在下载并校验 SHA-256（' + spec.label + '）…'
      const fileBytes = await this.httpGetBuffer(MIRROR_ORIGIN + entry.path, 8 * 1024 * 1024)
      if (typeof entry.bytes === 'number' && entry.bytes > 0 && fileBytes.byteLength !== entry.bytes) {
        this.busy = false
        this.mirrorSyncingPack = ''
        this.mirrorStatusText = '文件大小与清单不符，已拒绝写入'
        this.onFlashHint('国内镜像校验未通过，已保留本地数据')
        return
      }
      const actualHash = await computeSha256Hex(fileBytes)
      if (actualHash !== entry.sha256.toLowerCase()) {
        this.busy = false
        this.mirrorSyncingPack = ''
        this.mirrorStatusText = 'SHA-256 校验未通过，已拒绝写入'
        this.onFlashHint('国内镜像哈希校验失败，已拒绝写入')
        return
      }

      const mpcText = decoder.decodeToString(fileBytes)
      this.mirrorStatusText = 'SHA-256 校验通过，正在导入星图…'
      const currentSpec = spec
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
