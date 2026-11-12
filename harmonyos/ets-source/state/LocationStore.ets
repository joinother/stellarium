import { HierCity, LocSearchItem, SavedLocation } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { LOCATION_HIERARCHY } from '../common/location/hierarchy'
import { LOCATION_COUNTRY_NAMES } from '../common/location/countries'
import { LOCATION_ZH_NAMES } from '../common/location/names_zh'
import { foldLocationSearchText, locationFieldScore, locationFoldCacheSize, officialLocationAliases } from '../common/derive/actions'
import { CommandPort } from '../bridge/CommandPort'
import hilog from '@ohos.hilog'

// 分块预算：工作 32ms / 不额外等待。整表热扫描约 214ms、冷扫描约 384ms
// （真机 SGT-AL00 实测）；6ms/2ms 的旧预算会产生约 60 个 chunk，HarmonyOS
// 的 timer 调度把 0.2-0.4s 的工作拉长到 2.5-3.1s。增大 chunk 并让出 0ms
// 可以把墙钟压到 0.4-0.8s；搜索只发生在 260ms 防抖之后，不和滚动重叠。
const LOCATION_SEARCH_CHUNK_MS: number = 32
const LOCATION_SEARCH_CHUNK_DELAY_MS: number = 0
const LOCATION_SEARCH_PUBLISH_MS: number = 120

// 离线地点反查结果：全屏地图在在线底图上点选时，用城市离线表补海拔。
export interface OfflinePlaceAltitude {
  found: boolean
  altitude: number
  name: string
}

// 反查距离上限（约 150 km）：避免把大洋/无人区点选匹配到很远的内陆城市。
const OFFLINE_ALTITUDE_MAX_DISTANCE_DEG: number = 1.5

function normalizeOfflinePlaceName(value: string): string {
  return value.trim().toLowerCase()
    .replace(/特别行政区|自治区|自治州|地区|城市|市|县|区|盟|旗$/g, '')
    .replace(/\s+/g, '')
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
  // Online Petal POI results shown below the offline matches in the panel.
  // Kept separate so the offline scan can finish or fail independently.
  locSearchOnlineResults: LocSearchItem[] = []
  // idle | loading | ok | empty | error
  locSearchOnlineState: string = 'idle'
  savedLocations: SavedLocation[] = []
  // Last five applied locations (newest first); persisted with savedLocations.
  recentLocations: SavedLocation[] = []
  // 在线地图提供方：'offline' 使用内建坐标输入，'huawei' 使用 MapKit 在线选点。
  locationMapProvider: string = 'offline'

  // —— 离线分块搜索草稿（不对 UI 直接暴露）——
  // 不再持有预归一化索引：归一化结果由 actions.ets 的纯函数 memo 按“唯一字符串”
  // 缓存，扫描按需遍历静态地点表。这里只保存扫描游标与查询快照。
  private locSearchRequestId: number = 0
  private locationSearchScanQueryFolded: string = ''
  private locationSearchScanPlanet: string = ''
  private locationSearchScanPlanetKey: string = ''
  private locationSearchScanChinese: boolean = false
  private locationSearchScanLanguage: string = ''
  private locationSearchScanCountryNames: Map<string, string> = new Map<string, string>()
  private locationSearchScanProvinceNames: Map<string, string> = new Map<string, string>()
  private locationSearchScanContinents: Array<string> = []
  private locationSearchScanContinent: number = 0
  private locationSearchScanRegions: Array<string> = []
  private locationSearchScanRegion: number = 0
  private locationSearchScanCity: number = 0
  private locationSearchScanResults: Array<LocSearchItem> = []
  private locationSearchScanKeys: Set<string> = new Set<string>()
  private locationSearchScanTimer: number = -1
  private locationSearchLastPublishMs: number = 0
  private locationSearchScanStartedAt: number = 0
  private locationSearchScanWorkMs: number = 0

  // 经纬度格式化为「绝对值°方向」（N/S、E/W），位置域共用。
  formatDegrees(value: number, positive: string, negative: string): string {
    const direction = value >= 0 ? positive : negative
    return Math.abs(value).toFixed(2) + '°' + direction
  }

  // 按城市名反查离线海拔。在线地图 reverseGeocode 返回的 locality/adminLevel2
  // 可能是“拉萨市”“阿里地区”等行政区名，先去掉常见后缀再比对；同名城市取
  // 距离当前点最近的一个。
  altitudeForCityName(name: string, planet: string, latitude: number, longitude: number): OfflinePlaceAltitude {
    const hooks = this.hooks
    const query = normalizeOfflinePlaceName(name)
    if (hooks === null || query.length === 0) return { found: false, altitude: 0, name: '' }
    const cosLat = Math.cos(latitude * Math.PI / 180)
    let bestDistance = Number.MAX_VALUE
    let best: HierCity | null = null
    for (const continent of Object.keys(LOCATION_HIERARCHY)) {
      for (const region of Object.keys(LOCATION_HIERARCHY[continent])) {
        for (const city of LOCATION_HIERARCHY[continent][region]) {
          const cityPlanet = hooks.locationPlanet(city)
          if (cityPlanet !== planet && cityPlanet.toLowerCase() !== planet.toLowerCase()) continue
          const english = normalizeOfflinePlaceName(city.n)
          const chinese = normalizeOfflinePlaceName(LOCATION_ZH_NAMES[city.n] ?? '')
          if (english !== query && chinese !== query) continue
          const distance = this.offlineCityDistance(city, latitude, longitude, cosLat)
          if (distance < bestDistance) {
            bestDistance = distance
            best = city
          }
        }
      }
    }
    if (best === null) return { found: false, altitude: 0, name: '' }
    return { found: true, altitude: best.al, name: best.n }
  }

  // 按坐标反查最近离线地点。限制 1.5°（约 150 km），避免海洋/无人区
  // 点选被匹配到很远的内陆城市；超出范围返回 found=false。
  altitudeForPoint(latitude: number, longitude: number, planet: string): OfflinePlaceAltitude {
    const hooks = this.hooks
    if (hooks === null) return { found: false, altitude: 0, name: '' }
    const cosLat = Math.cos(latitude * Math.PI / 180)
    let bestDistance = OFFLINE_ALTITUDE_MAX_DISTANCE_DEG * OFFLINE_ALTITUDE_MAX_DISTANCE_DEG
    let best: HierCity | null = null
    for (const continent of Object.keys(LOCATION_HIERARCHY)) {
      for (const region of Object.keys(LOCATION_HIERARCHY[continent])) {
        for (const city of LOCATION_HIERARCHY[continent][region]) {
          const cityPlanet = hooks.locationPlanet(city)
          if (cityPlanet !== planet && cityPlanet.toLowerCase() !== planet.toLowerCase()) continue
          const distance = this.offlineCityDistance(city, latitude, longitude, cosLat)
          if (distance <= bestDistance) {
            bestDistance = distance
            best = city
          }
        }
      }
    }
    if (best === null) return { found: false, altitude: 0, name: '' }
    return { found: true, altitude: best.al, name: best.n }
  }

  private offlineCityDistance(city: HierCity, latitude: number, longitude: number, cosLat: number): number {
    let deltaLongitude = city.lo - longitude
    while (deltaLongitude > 180) deltaLongitude -= 360
    while (deltaLongitude < -180) deltaLongitude += 360
    const deltaLatitude = city.la - latitude
    return deltaLatitude * deltaLatitude + (deltaLongitude * cosLat) * (deltaLongitude * cosLat)
  }

  // —— 桥注入 ——
  // 本 store 的加载器读 AppStorage 持久化（`stellariumPrefs`）而非桥，故当前不调用 port；
  // port/seq/onChanged 按统一约定预留，供本域后续加载器复用。
  private port: CommandPort | null = null
  private seq: number = 0
  private onChanged: (() => void) | null = null
  // Load saved locations from disk only once per session; later panel opens
  // must not overwrite newer in-memory saves with a stale read.
  private savedLocationsLoaded: boolean = false
  private savedLocationsRevision: number = 0
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

  // 已保存位置：从 @ohos.data.preferences（经 LocationPort）读取 JSON，规整为 SavedLocation[]。
  // 旧实现只写 AppStorage，进程退出即丢失；现在必须走磁盘持久化。
  async loadSavedLocations(): Promise<void> {
    const hooks = this.hooks
    if (hooks === null || this.savedLocationsLoaded) return
    this.savedLocationsLoaded = true
    const revision = this.savedLocationsRevision
    try {
      const json = await hooks.readSavedLocations()
      if (revision !== this.savedLocationsRevision) return
      if (json.length === 0) return
      const parsed = JSON.parse(json) as Record<string, Object>
      const readList = (key: string): SavedLocation[] => {
        const raw = parsed[key] as Object[] | undefined
        if (!raw) return []
        return raw.map((item: Object): SavedLocation => {
          const loc = item as Record<string, string | number>
          return {
            name: (loc['name'] as string) ?? '',
            lat: (loc['lat'] as number) ?? 0,
            lon: (loc['lon'] as number) ?? 0,
            alt: (loc['alt'] as number) ?? 0,
            planet: (loc['planet'] as string) ?? 'Earth',
          } as SavedLocation
        })
      }
      this.savedLocations = readList('savedLocations')
      this.recentLocations = readList('recentLocations')
      this.notifyChanged()
    } catch (e) {
      hilog.info(0x0000, 'StellariumArkUI', 'loadSavedLocations error: %{public}s', (e as Error).message ?? '')
    }
  }

  // 离线搜索入口；跨域助手经 hooks。planetOverride 供全屏地图使用：
  // 地图的 observerPlanet prop 是当前选择，不依赖 hook 的更新时间。
  searchLocations(query: string, planetOverride?: string): void {
    const hooks = this.hooks
    if (hooks === null) return
    const q = query.trim()
    const requestId = ++this.locSearchRequestId
    if (this.locationSearchScanTimer >= 0) {
      clearTimeout(this.locationSearchScanTimer)
      this.locationSearchScanTimer = -1
    }
    if (q.length < 1) {
      this.locSearchResults = []
      this.locSearchOnlineResults = []
      this.locSearchOnlineState = 'idle'
      this.locSearching = false
      return
    }
    const planet = planetOverride !== undefined && planetOverride.length > 0
      ? planetOverride : hooks.observerPlanet()
    const quickResults = hooks.quickLocationSearch(q, planet)
    if (quickResults.length > 0) {
      this.locSearchResults = quickResults.slice(0, 20)
      this.locSearching = false
      return
    }
    const foldedQuery = foldLocationSearchText(q)
    if (foldedQuery.length === 0) {
      this.locSearchResults = []
      this.locSearching = false
      return
    }
    this.locSearching = true
    this.locationSearchScanQueryFolded = foldedQuery
    this.locationSearchScanPlanet = planet
    this.locationSearchScanPlanetKey = planet.toLowerCase()
    // Snapshot locale state once per scan: per-entry AppStorage reads were the
    // dominant cost of the first on-device scan (2.4-3.4s for 8k entries).
    this.locationSearchScanChinese = I18n.isChineseLanguage()
    this.locationSearchScanLanguage = I18n.getLanguage()
    this.locationSearchScanCountryNames = new Map<string, string>()
    this.locationSearchScanProvinceNames = new Map<string, string>()
    this.locationSearchScanContinents = Object.keys(LOCATION_HIERARCHY)
    this.locationSearchScanContinent = 0
    this.locationSearchScanRegions = []
    this.locationSearchScanRegion = 0
    this.locationSearchScanCity = 0
    this.locationSearchScanResults = []
    this.locationSearchScanKeys = new Set<string>()
    this.locationSearchLastPublishMs = 0
    this.locationSearchScanStartedAt = Date.now()
    this.locationSearchScanWorkMs = 0
    this.locSearchResults = []
    this.startLocationSearchScan(requestId)
  }

  private startLocationSearchScan(requestId: number): void {
    this.locationSearchScanTimer = setTimeout(() => { this.scanLocationSearchChunk(requestId) }, 0)
  }

  // 国名/省名在扫描内按唯一输入缓存：国家码约 250 个、省名约 100 个，
  // 避免 8k 条目重复走 I18n/系统 getDisplayCountry。
  private locationSearchScanCountryName(hooks: LocationStoreHostHooks, countryCode: string,
    planet: string, chinese: boolean, language: string): string {
    const key = (chinese ? 'zh' : language) + '|' + countryCode
    const cached = this.locationSearchScanCountryNames.get(key)
    if (cached !== undefined) return cached
    const name = hooks.locationSearchCountryName(countryCode, planet, chinese, language)
    this.locationSearchScanCountryNames.set(key, name)
    return name
  }

  private locationSearchScanProvinceName(hooks: LocationStoreHostHooks, name: string,
    chinese: boolean): string {
    if (name.length === 0) return ''
    const key = (chinese ? 'zh' : 'raw') + '|' + name
    const cached = this.locationSearchScanProvinceNames.get(key)
    if (cached !== undefined) return cached
    const translated = hooks.translateProvince(name, chinese)
    this.locationSearchScanProvinceNames.set(key, translated)
    return translated
  }

  // 离线搜索分块扫描：按需遍历静态地点表，没有预建索引。每个字段串的
  // 归一化结果由 foldLocationSearchText 按“唯一字符串”缓存；命中时才构造
  // LocSearchItem，未命中项不产生任何数组/对象分配。
  scanLocationSearchChunk(requestId: number): void {
    if (requestId !== this.locSearchRequestId) return
    const hooks = this.hooks
    if (hooks === null) {
      this.locSearching = false
      this.locationSearchScanTimer = -1
      return
    }
    const startedAt = Date.now()
    const query = this.locationSearchScanQueryFolded
    const planet = this.locationSearchScanPlanet
    const planetKey = this.locationSearchScanPlanetKey
    const chinese = this.locationSearchScanChinese
    const language = this.locationSearchScanLanguage
    let changed = false

    let iterations = 0
    while (this.locationSearchScanContinent < this.locationSearchScanContinents.length) {
      // Date.now() is a native call; checking every entry dominated short scans.
      if ((iterations & 31) === 0 && Date.now() - startedAt >= LOCATION_SEARCH_CHUNK_MS) break
      iterations++
      const continent = this.locationSearchScanContinents[this.locationSearchScanContinent]
      if (this.locationSearchScanRegions.length === 0) {
        this.locationSearchScanRegions = Object.keys(LOCATION_HIERARCHY[continent])
      }
      if (this.locationSearchScanRegion >= this.locationSearchScanRegions.length) {
        this.locationSearchScanContinent++
        this.locationSearchScanRegions = []
        this.locationSearchScanRegion = 0
        this.locationSearchScanCity = 0
        continue
      }
      const region = this.locationSearchScanRegions[this.locationSearchScanRegion]
      const cities = LOCATION_HIERARCHY[continent][region]
      if (this.locationSearchScanCity >= cities.length) {
        this.locationSearchScanRegion++
        this.locationSearchScanCity = 0
        continue
      }

      const city = cities[this.locationSearchScanCity++]
      const locationPlanet = hooks.locationPlanet(city)
      if (locationPlanet !== planet && locationPlanet.toLowerCase() !== planetKey) continue

      const cityChineseName = LOCATION_ZH_NAMES[city.n] ?? ''
      const displayName = hooks.locationDisplayName(city.n, chinese, language)
      const countryCode = city.country
      const country = this.locationSearchScanCountryName(hooks, countryCode, planet, chinese, language)
      const province = this.locationSearchScanProvinceName(hooks, city.province ?? '', chinese)

      let best = 0
      best = locationFieldScore(foldLocationSearchText(city.n), query, best)
      best = locationFieldScore(foldLocationSearchText(cityChineseName), query, best)
      best = locationFieldScore(foldLocationSearchText(displayName), query, best)
      best = locationFieldScore(foldLocationSearchText(city.province ?? ''), query, best)
      best = locationFieldScore(foldLocationSearchText(province), query, best)
      best = locationFieldScore(foldLocationSearchText(region), query, best)
      best = locationFieldScore(foldLocationSearchText(country), query, best)

      if (best === 0) {
        const sourceCountry = LOCATION_COUNTRY_NAMES[countryCode]
        const sourceZh = foldLocationSearchText(sourceCountry?.zh ?? '')
        const sourceEn = foldLocationSearchText(sourceCountry?.en ?? '')
        const aliases = foldLocationSearchText(officialLocationAliases(countryCode))
        if ((sourceZh.length > 0 && sourceZh.includes(query)) ||
          (sourceEn.length > 0 && sourceEn.includes(query)) ||
          (aliases.length > 0 && aliases.includes(query))) {
          best = 40
        }
      }
      if (best <= 0) continue

      const dedupeKey = city.n + '|' + city.la.toFixed(4) + '|' + city.lo.toFixed(4)
      if (this.locationSearchScanKeys.has(dedupeKey)) continue
      this.locationSearchScanKeys.add(dedupeKey)
      this.locationSearchScanResults.push({
        name: city.n,
        displayName: displayName,
        lat: city.la,
        lon: city.lo,
        alt: city.al,
        planet: locationPlanet,
        country: countryCode,
        region: region,
        province: city.province ?? '',
        searchScore: best
      })
      this.locationSearchScanResults.sort((left: LocSearchItem, right: LocSearchItem) =>
        (right.searchScore ?? 0) - (left.searchScore ?? 0))
      if (this.locationSearchScanResults.length > 20) this.locationSearchScanResults.pop()
      changed = true
    }

    this.locationSearchScanWorkMs += Date.now() - startedAt
    if (requestId !== this.locSearchRequestId) return
    const finished = this.locationSearchScanContinent >= this.locationSearchScanContinents.length
    const now = Date.now()
    if (changed && (finished || now - this.locationSearchLastPublishMs >= LOCATION_SEARCH_PUBLISH_MS)) {
      this.locSearchResults = this.locationSearchScanResults.slice()
      this.locationSearchLastPublishMs = now
    }
    if (finished) {
      this.locSearching = false
      this.locationSearchScanTimer = -1
      hilog.info(0x0000, 'StellariumArkUI',
        '[location-search] done ms=%{public}d work=%{public}d matches=%{public}d folds=%{public}d',
        Date.now() - this.locationSearchScanStartedAt, this.locationSearchScanWorkMs,
        this.locationSearchScanResults.length, locationFoldCacheSize())
      return
    }
    this.locationSearchScanTimer =
      setTimeout(() => { this.scanLocationSearchChunk(requestId) }, LOCATION_SEARCH_CHUNK_DELAY_MS)
  }

  // 搜索选中落地；setLocation / pickerMode 经 hooks。
  selectSearchLocation(item: LocSearchItem): void {
    const hooks = this.hooks
    if (hooks === null) return
    hooks.applyLocation(item.name, item.lat, item.lon, item.alt, item.planet)
    this.locSearchQuery = ''
    this.locSearchResults = []
    this.locSearchOnlineResults = []
    this.locSearchOnlineState = 'idle'
    hooks.setPickerMode('map')
  }

  // Identity for saved/recent entries: name alone is not unique across planets
  // or repeated city names, so include rounded coordinates and the body.
  savedLocationKey(item: SavedLocation): string {
    return item.name + '|' + item.lat.toFixed(4) + '|' + item.lon.toFixed(4) + '|' + item.planet
  }

  // 保存当前 picker 位置；picker 草稿与 flashHint 经 hooks。
  saveCurrentLocation(): void {
    const hooks = this.hooks
    if (hooks === null) return
    const draft = hooks.currentDraft()
    const item: SavedLocation = {
      name: draft.name,
      lat: draft.latitude,
      lon: draft.longitude,
      alt: draft.altitude,
      planet: draft.planet,
    }
    const key = this.savedLocationKey(item)
    if (this.savedLocations.some((s: SavedLocation) => this.savedLocationKey(s) === key)) {
      hooks.flashHint(I18n.t('loc_already_saved'))
      return
    }
    // Newest saved location first; persisted order carries across restarts.
    this.savedLocations = [item, ...this.savedLocations]
    this.persistSavedLocations()
    hooks.flashHint(I18n.t('loc_saved_success'))
  }

  // 最近使用：成功应用观测点后记录，最多 5 条，重复项前置。
  recordRecentLocation(name: string, latitude: number, longitude: number,
    altitude: number, planet: string): void {
    const item: SavedLocation = { name: name, lat: latitude, lon: longitude, alt: altitude, planet: planet }
    const key = this.savedLocationKey(item)
    this.recentLocations = [item,
      ...this.recentLocations.filter((s: SavedLocation) => this.savedLocationKey(s) !== key)
    ].slice(0, 5)
    this.persistSavedLocations()
  }

  // 删除已保存位置（按复合键，避免同名不同坐标误删）。
  deleteSavedLocation(key: string): void {
    this.savedLocations = this.savedLocations.filter((s: SavedLocation) => this.savedLocationKey(s) !== key)
    this.persistSavedLocations()
  }

  // 重命名已保存位置；空名称或与另一条重复时返回 false。
  renameSavedLocation(key: string, name: string): boolean {
    const next = name.trim()
    if (next.length === 0) return false
    const target = this.savedLocations.find((s: SavedLocation) => this.savedLocationKey(s) === key)
    if (target === undefined) return false
    const renamed: SavedLocation = {
      name: next, lat: target.lat, lon: target.lon, alt: target.alt, planet: target.planet
    }
    const nextKey = this.savedLocationKey(renamed)
    if (nextKey !== key && this.savedLocations.some((s: SavedLocation) => this.savedLocationKey(s) === nextKey)) {
      return false
    }
    this.savedLocations = this.savedLocations.map((s: SavedLocation) =>
      this.savedLocationKey(s) === key ? renamed : s)
    this.persistSavedLocations()
    return true
  }

  // 持久化已保存/最近位置到 @ohos.data.preferences（经 LocationPort）。
  // AppStorage 只在进程内有效，不能作为退出后的存储。
  persistSavedLocations(): void {
    const hooks = this.hooks
    if (hooks === null) return
    this.savedLocationsLoaded = true
    this.savedLocationsRevision += 1
    const json = JSON.stringify({
      savedLocations: this.savedLocations,
      recentLocations: this.recentLocations
    })
    void hooks.writeSavedLocations(json)
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
  readSavedLocations(): Promise<string>
  writeSavedLocations(json: string): Promise<void>
  // 当前 picker 草稿（LocationPickerStore 的名称/坐标 + SessionToolStore 的 observerPlanet）。
  currentDraft(): LocationDraft
  observerPlanet(): string
  quickLocationSearch(query: string, observerPlanet: string): Array<LocSearchItem>
  isCurrentObserverPlanet(city: HierCity, observerPlanet: string): boolean
  locationDisplayName(name: string, chinese: boolean, language: string): string
  locationSearchCountryName(countryCode: string, observerPlanet: string,
    chinese: boolean, language: string): string
  translateProvince(name: string, chinese: boolean): string
  locationPlanet(city: HierCity): string
  // selectSearchLocation 的落地（宿主 this.locationCtl().setLocation）与 picker 模式写。
  applyLocation(name: string, lat: number, lon: number, alt: number, planet: string): void
  setPickerMode(mode: string): void
}
