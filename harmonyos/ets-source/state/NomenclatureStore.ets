// 行星表面地貌图集（NomenclatureMgr 3.8 MB IAU 地貌库离线检索与一键飞抵）域 store。
import { CommandPort } from '../bridge/CommandPort'
import {
  PlanetaryNomenclatureBody,
  PlanetaryNomenclatureItem,
  StellariumBridgeResponse
} from '../common/types/StellariumTypes'

@Observed
export class NomenclatureStore {
  planet: string = 'Moon'
  category: string = 'all'
  query: string = ''
  bodies: Array<PlanetaryNomenclatureBody> = []
  featured: Array<PlanetaryNomenclatureItem> = []
  items: Array<PlanetaryNomenclatureItem> = []
  totalAllFeatures: number = 0
  planetFeatureTotal: number = 0
  matchedCount: number = 0
  countCrater: number = 0
  countMare: number = 0
  countMons: number = 0
  countVallis: number = 0
  countLanding: number = 0
  showLabels: boolean = false
  outlineCraters: boolean = false
  terminatorOnly: boolean = false
  hideLocal: boolean = true
  loading: boolean = false
  busy: boolean = false
  error: string = ''

  private port: CommandPort | null = null
  private seq: number = 0
  private onFlashHint: (msg: string) => void = () => {}
  private onAfterFlyTo: () => void = () => {}

  bind(port: CommandPort, onFlashHint: (msg: string) => void, onAfterFlyTo: () => void = () => {}): void {
    this.port = port
    this.onFlashHint = onFlashHint
    this.onAfterFlyTo = onAfterFlyTo
  }

  load(planetOverride?: string): void {
    if (this.port === null) return
    if (planetOverride !== undefined && planetOverride.trim().length > 0) {
      this.planet = planetOverride.trim()
      this.category = 'all'
      this.query = ''
    }
    const reqId = ++this.seq
    this.loading = true
    this.error = ''
    const payload = JSON.stringify({
      planet: this.planet,
      category: this.category,
      query: this.query.trim(),
      limit: 80
    })
    this.port.requestInteractive('getPlanetaryNomenclature', payload, (r: StellariumBridgeResponse) => {
      if (reqId !== this.seq) return
      this.loading = false
      if (r.ok === true) {
        this.totalAllFeatures = Number(r.totalAllFeatures ?? 0)
        this.planetFeatureTotal = Number(r.planetFeatureTotal ?? 0)
        this.matchedCount = Number(r.matchedCount ?? 0)
        this.showLabels = r.showLabels === true
        this.outlineCraters = r.outlineCraters === true
        this.terminatorOnly = r.terminatorOnly === true
        this.hideLocal = r.hideLocal === true
        this.bodies = Array.isArray(r.bodies) ? r.bodies as Array<PlanetaryNomenclatureBody> : []
        this.featured = Array.isArray(r.featured) ? r.featured as Array<PlanetaryNomenclatureItem> : []
        this.items = Array.isArray(r.items) ? r.items as Array<PlanetaryNomenclatureItem> : []
        const counts = r.counts as Record<string, number> | undefined
        if (counts !== undefined) {
          this.countCrater = Number(counts['crater'] ?? 0)
          this.countMare = Number(counts['mare'] ?? 0)
          this.countMons = Number(counts['mons'] ?? 0)
          this.countVallis = Number(counts['vallis'] ?? 0)
          this.countLanding = Number(counts['landing'] ?? 0)
        }
      } else {
        this.error = r.error ?? '读取行星地貌库失败，请重试。'
      }
    }, () => {
      if (reqId !== this.seq) return
      this.loading = false
      this.error = '读取行星地貌库超时，请重试。'
    })
  }

  selectPlanet(planet: string): void {
    if (this.planet === planet && this.items.length > 0) return
    this.planet = planet
    this.category = 'all'
    this.load()
  }

  selectCategory(cat: string): void {
    if (this.category === cat) return
    this.category = cat
    this.load()
  }

  setQuery(q: string): void {
    this.query = q
  }

  toggleSetting(setting: string, value: boolean): void {
    if (this.port === null) return
    const payload = JSON.stringify({ setting: setting, value: value })
    this.port.requestInteractive('setNomenclatureSetting', payload, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.showLabels = r.showLabels === true
        this.outlineCraters = r.outlineCraters === true
        this.terminatorOnly = r.terminatorOnly === true
        this.hideLocal = r.hideLocal === true
      }
    }, () => {})
  }

  flyTo(item: PlanetaryNomenclatureItem): void {
    if (this.port === null || this.busy) return
    this.busy = true
    const payload = JSON.stringify({
      planet: item.planet,
      id: item.id,
      englishName: item.englishName
    })
    this.port.requestInteractive('flyToNomenclature', payload, (r: StellariumBridgeResponse) => {
      this.busy = false
      if (r.ok === true) {
        this.showLabels = true
        this.outlineCraters = true
        const pName = r.planetName ?? item.planetName
        const fName = r.name ?? item.name
        if (r.belowHorizon === true) {
          this.onFlashHint('已飞抵 ' + pName + ' · ' + fName + '（当前位于地平线下，可关闭地面查看）')
        } else {
          this.onFlashHint('已飞抵 ' + pName + ' · ' + fName + '（已开启地貌标注与环形山轮廓）')
        }
        this.onAfterFlyTo()
      } else {
        this.onFlashHint(r.error ?? '飞抵行星地貌失败')
      }
    }, () => {
      this.busy = false
      this.onFlashHint('飞抵行星地貌超时，请重试')
    })
  }
}
