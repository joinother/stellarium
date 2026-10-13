import { HierCity, LocSearchItem, SavedLocation } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { LOCATION_HIERARCHY } from '../common/location/hierarchy'
import { LOCATION_COUNTRY_NAMES } from '../common/location/countries'
import { LOCATION_ZH_NAMES } from '../common/location/names_zh'
import { locationSearchScoreNormalized, normalizeLocationSearchText, officialLocationAliases } from '../common/derive/actions'
import { CommandPort } from '../bridge/CommandPort'
import hilog from '@ohos.hilog'

// 分块预算：工作 12ms / 歇 4ms（原先 5ms/16ms 的占空比只有 24%，把总时长放大约 4 倍）。
const LOCATION_SEARCH_CHUNK_MS: number = 12
const LOCATION_SEARCH_CHUNK_DELAY_MS: number = 4
const LOCATION_SEARCH_PUBLISH_MS: number = 120

// 一个候选的预归一化搜索数据：primary 供精确/前缀/包含匹配，text 为兜底串。
interface LocationSearchEntry {
  item: LocSearchItem
  dedupeKey: string
  primary: Array<string>
  text: string
}

// 位置域（「位置」面板）状态：离线地点搜索簇 + 已保存位置簇。
//
// 持有搜索框字段（locSearchQuery/Results/Searching/Debounce）与 savedLocations，以及离线分块
// 搜索的私有草稿；被位置面板的 cityChipsRow / locationSearchPanel 以 @ObjectLink 观察。
// 加载器 loadSavedLocations 与搜索/保存点为 store 方法，跨域读与跨 store 动作经
// LocationStoreHostHooks 具名回注（store 不 import 他 store）。
//
// 只放数据与纯计算，不 import UI / NAPI。
@Observed
export class LocationStore {
  locSearchQuery: string = ''
  locSearchResults: LocSearchItem[] = []
  locSearching: boolean = false
  locSearchDebounce: number = 0
  savedLocations: SavedLocation[] = []
  // 在线地图提供方：'offline' 使用内建坐标输入，'huawei' 使用 MapKit 在线选点。
  locationMapProvider: string = 'offline'

  // —— 离线分块搜索草稿（不对 UI 直接暴露）——
  private locSearchRequestId: number = 0
  private locationSearchScanQuery: string = ''
  private locationSearchScanIndex: number = 0
  private locationSearchScanResults: Array<LocSearchItem> = []
  private locationSearchScanKeys: Set<string> = new Set<string>()
  private locationSearchScanTimer: number = -1
  private locationSearchLastPublishMs: number = 0

  // —— 预归一化搜索索引（每 星球+语言 一份，分块构建）——
  // 归一化（大小写 + 去变音符号 + 去分隔符）是搜索里最贵的一步，而地点表是静态的，
  // 故每个候选只算一次、之后每次按键只做 includes 比较。
  private locSearchIndex: Array<LocationSearchEntry> = []
  private locSearchIndexKey: string = ''
  private locSearchIndexReady: boolean = false
  private locSearchIndexContinent: number = 0
  private locSearchIndexRegions: Array<string> = []
  private locSearchIndexRegion: number = 0
  private locSearchIndexCity: number = 0
  private locSearchIndexTimer: number = -1

  // 经纬度格式化为「绝对值°方向」（N/S、E/W），位置域共用。
  formatDegrees(value: number, positive: string, negative: string): string {
    const direction = value >= 0 ? positive : negative
    return Math.abs(value).toFixed(2) + '°' + direction
  }

  // —— 桥注入 ——
  // 本 store 的加载器读 AppStorage 持久化（`stellariumPrefs`）而非桥，故当前不调用 port；
  // port/seq/onChanged 按统一约定预留，供本域后续加载器复用。
  private port: CommandPort | null = null
  private seq: number = 0
  private onChanged: (() => void) | null = null
  // 离线搜索 / 保存点的跨域读写回注。
  private hooks: LocationStoreHostHooks | null = null

  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  attachHooks(hooks: LocationStoreHostHooks): void {
    this.hooks = hooks
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // 已保存位置（持久化在 AppStorage 的 `stellariumPrefs` 键）：把原始条目规整为 SavedLocation[]。
  loadSavedLocations(): void {
    try {
      const prefs = AppStorage.get<Record<string, Object>>('stellariumPrefs')
      if (prefs && prefs['savedLocations']) {
        const raw = prefs['savedLocations'] as Object[]
        this.savedLocations = raw.map((item: Object): SavedLocation => {
          const loc = item as Record<string, string | number>
          return {
            name: (loc['name'] as string) ?? '',
            lat: (loc['lat'] as number) ?? 0,
            lon: (loc['lon'] as number) ?? 0,
            alt: (loc['alt'] as number) ?? 0,
            planet: (loc['planet'] as string) ?? 'Earth',
          } as SavedLocation
        })
        this.notifyChanged()
      }
    } catch (e) {
      hilog.info(0x0000, 'StellariumArkUI', 'loadSavedLocations error: %{public}s', (e as Error).message ?? '')
    }
  }

  // 离线搜索入口；跨域助手经 hooks。
  searchLocations(query: string): void {
    const hooks = this.hooks
    if (hooks === null) return
    const q = query.trim()
    const requestId = ++this.locSearchRequestId
    if (this.locationSearchScanTimer >= 0) {
      clearTimeout(this.locationSearchScanTimer)
      this.locationSearchScanTimer = -1
    }
    if (q.length < 1) {
      this.locationSearchScanQuery = ''
      this.locSearchResults = []
      this.locSearching = false
      return
    }
    const quickResults = hooks.quickLocationSearch(q, hooks.observerPlanet())
    if (quickResults.length > 0) {
      this.locationSearchScanQuery = ''
      this.locSearchResults = quickResults.slice(0, 20)
      this.locSearching = false
      return
    }
    this.locSearching = true
    this.locationSearchScanQuery = q
    this.locationSearchScanIndex = 0
    this.locationSearchScanResults = []
    this.locationSearchScanKeys = new Set<string>()
    this.locationSearchLastPublishMs = 0
    this.locSearchResults = []
    this.ensureLocationSearchIndex(hooks.observerPlanet())
    if (this.locSearchIndexReady) {
      this.startLocationSearchScan(requestId)
    }
  }

  // 面板打开时预热索引，使首次输入即可命中缓存。
  warmLocationSearchIndex(): void {
    const hooks = this.hooks
    if (hooks === null) return
    this.ensureLocationSearchIndex(hooks.observerPlanet())
  }

  // 归一化索引按「星球 + 界面语言」失效；构建本身分块，不阻塞 UI 线程。
  private ensureLocationSearchIndex(observerPlanet: string): void {
    const key = observerPlanet + '|' + (I18n.isChineseLanguage() ? 'zh' : 'en')
    if (key !== this.locSearchIndexKey) {
      this.locSearchIndexKey = key
      this.locSearchIndex = []
      this.locSearchIndexReady = false
      this.locSearchIndexContinent = 0
      this.locSearchIndexRegions = []
      this.locSearchIndexRegion = 0
      this.locSearchIndexCity = 0
    }
    if (this.locSearchIndexReady || this.locSearchIndexTimer >= 0) return
    this.locSearchIndexTimer = setTimeout(() => { this.buildLocationSearchIndexChunk() }, 0)
  }

  private buildLocationSearchIndexChunk(): void {
    const hooks = this.hooks
    if (hooks === null) {
      this.locSearchIndexTimer = -1
      return
    }
    const continents = Object.keys(LOCATION_HIERARCHY)
    const planet = hooks.observerPlanet()
    const planetKey = planet.toLowerCase()
    const startedAt = Date.now()
    while (this.locSearchIndexContinent < continents.length && Date.now() - startedAt < LOCATION_SEARCH_CHUNK_MS) {
      const continent = continents[this.locSearchIndexContinent]
      if (this.locSearchIndexRegions.length === 0) {
        this.locSearchIndexRegions = Object.keys(LOCATION_HIERARCHY[continent])
      }
      if (this.locSearchIndexRegion >= this.locSearchIndexRegions.length) {
        this.locSearchIndexContinent++
        this.locSearchIndexRegions = []
        this.locSearchIndexRegion = 0
        this.locSearchIndexCity = 0
        continue
      }
      const region = this.locSearchIndexRegions[this.locSearchIndexRegion]
      const cities = LOCATION_HIERARCHY[continent][region]
      if (this.locSearchIndexCity >= cities.length) {
        this.locSearchIndexRegion++
        this.locSearchIndexCity = 0
        continue
      }
      const city = cities[this.locSearchIndexCity++]
      const locationPlanet = hooks.locationPlanet(city)
      if (locationPlanet.toLowerCase() !== planetKey) continue
      const chinese = LOCATION_ZH_NAMES[city.n] ?? ''
      const displayName = hooks.locationDisplayName(city.n)
      const countryCode = city.country
      const country = hooks.locationSearchCountryName(countryCode, planet)
      const province = hooks.translateProvince(city.province ?? '')
      // Search accepts the source name, official Chinese name, and the name
      // rendered for the active language. Display itself remains single-language.
      const sourceCountry = LOCATION_COUNTRY_NAMES[countryCode]
      const haystack = city.n + ' ' + chinese + ' ' + displayName + ' ' +
        (city.province ?? '') + ' ' + province + ' ' + region + ' ' + country + ' ' +
        (sourceCountry?.zh ?? '') + ' ' + (sourceCountry?.en ?? '') + officialLocationAliases(countryCode)
      const primary: Array<string> = [
        normalizeLocationSearchText(city.n),
        normalizeLocationSearchText(chinese),
        normalizeLocationSearchText(displayName),
        normalizeLocationSearchText(city.province ?? ''),
        normalizeLocationSearchText(province),
        normalizeLocationSearchText(region),
        normalizeLocationSearchText(country),
      ]
      this.locSearchIndex.push({
        item: {
          name: city.n,
          displayName: displayName,
          lat: city.la,
          lon: city.lo,
          alt: city.al,
          planet: locationPlanet,
          country: countryCode,
          region: region,
          province: city.province ?? '',
        },
        dedupeKey: city.n + '|' + city.la.toFixed(4) + '|' + city.lo.toFixed(4),
        primary: primary,
        text: normalizeLocationSearchText(haystack),
      })
    }
    if (this.locSearchIndexContinent < continents.length) {
      this.locSearchIndexTimer =
        setTimeout(() => { this.buildLocationSearchIndexChunk() }, LOCATION_SEARCH_CHUNK_DELAY_MS)
      return
    }
    this.locSearchIndexReady = true
    this.locSearchIndexTimer = -1
    if (this.locationSearchScanQuery.length > 0 && this.locSearching) {
      this.startLocationSearchScan(this.locSearchRequestId)
    }
  }

  private startLocationSearchScan(requestId: number): void {
    this.locationSearchScanIndex = 0
    this.locationSearchScanTimer = setTimeout(() => { this.scanLocationSearchChunk(requestId) }, 0)
  }

  // 离线搜索分块扫描：索引已预归一化，此处每个候选只做 includes 比较。
  scanLocationSearchChunk(requestId: number): void {
    if (requestId !== this.locSearchRequestId) return
    const startedAt = Date.now()
    const query = normalizeLocationSearchText(this.locationSearchScanQuery)
    const entries = this.locSearchIndex
    let changed = false
    while (this.locationSearchScanIndex < entries.length &&
      Date.now() - startedAt < LOCATION_SEARCH_CHUNK_MS) {
      const entry = entries[this.locationSearchScanIndex++]
      const matchScore = locationSearchScoreNormalized(query, entry.primary, entry.text)
      if (matchScore <= 0) continue
      if (this.locationSearchScanKeys.has(entry.dedupeKey)) continue
      this.locationSearchScanKeys.add(entry.dedupeKey)
      this.locationSearchScanResults.push({
        name: entry.item.name,
        displayName: entry.item.displayName,
        lat: entry.item.lat,
        lon: entry.item.lon,
        alt: entry.item.alt,
        planet: entry.item.planet,
        country: entry.item.country,
        region: entry.item.region,
        province: entry.item.province,
        searchScore: matchScore,
      })
      this.locationSearchScanResults.sort((left: LocSearchItem, right: LocSearchItem) =>
        (right.searchScore ?? 0) - (left.searchScore ?? 0))
      if (this.locationSearchScanResults.length > 20) this.locationSearchScanResults.pop()
      changed = true
    }
    if (requestId !== this.locSearchRequestId) return
    const finished = this.locationSearchScanIndex >= entries.length
    const now = Date.now()
    if (changed && (finished || now - this.locationSearchLastPublishMs >= LOCATION_SEARCH_PUBLISH_MS)) {
      this.locSearchResults = this.locationSearchScanResults.slice()
      this.locationSearchLastPublishMs = now
    }
    if (finished) {
      this.locSearching = false
      this.locationSearchScanTimer = -1
      return
    }
    this.locationSearchScanTimer = setTimeout(() => { this.scanLocationSearchChunk(requestId) }, LOCATION_SEARCH_CHUNK_DELAY_MS)
  }

  // 搜索选中落地；setLocation / pickerMode 经 hooks。
  selectSearchLocation(item: LocSearchItem): void {
    const hooks = this.hooks
    if (hooks === null) return
    hooks.applyLocation(item.name, item.lat, item.lon, item.alt, item.planet)
    this.locSearchQuery = ''
    this.locSearchResults = []
    hooks.setPickerMode('map')
  }

  // 保存当前 picker 位置；picker 草稿与 flashHint 经 hooks。
  saveCurrentLocation(): void {
    const hooks = this.hooks
    if (hooks === null) return
    const draft = hooks.currentDraft()
    const name = draft.name
    // 检查是否已存在
    const exists = this.savedLocations.some((s: SavedLocation) => s.name === name)
    if (exists) {
      hooks.flashHint(I18n.t('loc_already_saved'))
      return
    }
    const item: SavedLocation = {
      name: name,
      lat: draft.latitude,
      lon: draft.longitude,
      alt: draft.altitude,
      planet: draft.planet,
    }
    this.savedLocations = [...this.savedLocations, item]
    this.persistSavedLocations()
    hooks.flashHint(I18n.t('loc_saved_success'))
  }

  // 删除已保存位置。
  deleteSavedLocation(name: string): void {
    this.savedLocations = this.savedLocations.filter((s: SavedLocation) => s.name !== name)
    this.persistSavedLocations()
  }

  // 持久化已保存位置（存储方式保持 AppStorage 原样）。
  persistSavedLocations(): void {
    try {
      let prefs = AppStorage.get<Record<string, Object>>('stellariumPrefs')
      if (!prefs) {
        prefs = {} as Record<string, Object>
      }
      prefs['savedLocations'] = this.savedLocations
      AppStorage.setOrCreate<Record<string, Object>>('stellariumPrefs', prefs)
    } catch (e) {
      hilog.info(0x0000, 'StellariumArkUI', 'persistSavedLocations error: %{public}s', (e as Error).message ?? '')
    }
  }
}

// 宿主 → LocationStore 的回注。离线搜索 / 保存点的跨域读（LocationPickerStore 的
// 名称/坐标/层级过滤助手、SessionToolStore 的 observerPlanet）与跨 store 动作经此具名注入，
// store 不 import 他 store。
export interface LocationDraft {
  name: string
  latitude: number
  longitude: number
  altitude: number
  planet: string
}

export interface LocationStoreHostHooks {
  flashHint(text: ResourceStr): void
  // 当前 picker 草稿（LocationPickerStore 的名称/坐标 + SessionToolStore 的 observerPlanet）。
  currentDraft(): LocationDraft
  observerPlanet(): string
  quickLocationSearch(query: string, observerPlanet: string): Array<LocSearchItem>
  isCurrentObserverPlanet(city: HierCity, observerPlanet: string): boolean
  locationDisplayName(name: string): string
  locationSearchCountryName(countryCode: string, observerPlanet: string): string
  translateProvince(name: string): string
  locationPlanet(city: HierCity): string
  // selectSearchLocation 的落地（宿主 this.locationCtl().setLocation）与 picker 模式写。
  applyLocation(name: string, lat: number, lon: number, alt: number, planet: string): void
  setPickerMode(mode: string): void
}
