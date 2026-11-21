// 太阳系小天体管理（SolarSystemEditor 离线目录与导入）域 store。
import { CommandPort } from '../bridge/CommandPort'
import { MinorBodyItem, StellariumBridgeResponse } from '../common/types/StellariumTypes'

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
