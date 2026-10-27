import { I18n } from '../pages/I18n'
import { HierCity, LocSearchItem, StellariumBridgeResponse } from '../pages/StellariumTypes'
import { LOCATION_HIERARCHY } from '../common/location/hierarchy'
import { LOCATION_COUNTRY_NAMES } from '../common/location/countries'
import { LOCATION_ZH_NAMES } from '../common/location/names_zh'
import { timezoneDisplayName, approximateTimeZoneDisplay } from '../common/derive/labels'
import { clamp } from '../common/derive/astro'
import { getCityPreset, matchesLocationSearch, locationSearchMatchScore } from '../common/derive/actions'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → LocationPickerStore 的观测点助手。
export interface LocationPickerHostHooks {
  // 观测纬度写 SkyCultureSettingsStore.skyCultureObserverLatitude（领地地图旋转用）。
  setSkyCultureObserverLatitude(value: number): void
  // 观测星球写 SessionToolStore.observerPlanet（跨域共享，位置面板/今晚天象消费）。
  setObserverPlanet(value: string): void
}

// 位置选择器（「位置」面板的层级列 + 地图选点）状态与纯计算。
//
// 持有 picker 坐标/名称/状态、选点方式、观测地时区、地图渲染尺寸与层级选择
// （hierContinent/Country/Region/City）；层级列的名称/翻译/过滤为纯计算，
// 被位置面板组件与 LocationController 以 @ObjectLink 观察。
//
// 需要观测星球参与过滤与翻译的方法以**参数**传入 observerPlanet（该值是宿主跨域状态，
// 切换星球 / 设置面板多处共用）；参数化避免 store 依赖宿主状态。
//
// 持有 CommandPort 与观测点助手 hooks；native 桥与定时器、面板自持的 Scroller 不在本 store。
//
// 只放数据与纯计算，不 import UI / NAPI。
//
// 省名翻译缓存刻意做成模块级常量而非 store 字段：translateProvince() 会在**渲染期**被调用
// （层级列标签 / 选择摘要），若写进 @Observed store 的字段会在 build 中改被观察状态，有重渲染风险。
const PROVINCE_TRANSLATION_CACHE: Record<string, string> = {}

@Observed
export class LocationPickerStore {
  locationPickerName: string = I18n.t('custom_location')
  locationPickerLatitude: number = 39.9042
  locationPickerLongitude: number = 116.4074
  locationPickerAltitude: number = 44
  locationPickerStatus: ResourceStr = I18n.t('m_drag_map_hint')
  // 位置来源：'gps' 设备定位 / 'map' 地图点选 / 'named' 城市·搜索·预设。快捷操作面板标题按它取值，
  // 并随 ObserverLocationRecord.source 持久化（见 capability/LocationController.ets）。
  locationSource: string = 'named'
  locationPickMode: string = 'map'
  observerTimeZone: string = ''
  mapRenderWidth: number = 280
  mapRenderHeight: number = 150
  hierContinent: string = ''
  hierCountry: string = ''
  hierRegion: string = ''
  hierCity: string = ''

  // —— 桥 / 宿主助手注入 ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（交互读，无并发抑制需求），预留保持统一约定。
  private seq: number = 0
  private onChanged: (() => void) | null = null
  private hooks: LocationPickerHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  attachHooks(hooks: LocationPickerHostHooks): void {
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // 观测点信息：读回纬度 / 时区 / 观测星球（时区助手用 derive/labels，跨域写经 hooks）。
  loadObserverInfo(updateTimeZone: boolean = true): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const hooks = this.hooks
    if (hooks === null) {
      return
    }
    port.requestInteractive('getObserverInfo', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        if (r.latitude !== undefined) {
          hooks.setSkyCultureObserverLatitude(Number(r.latitude))
        }
        if (updateTimeZone && r.timeZone !== undefined && r.timeZone.length > 0 && r.timeZone !== 'system_default') {
          this.observerTimeZone = timezoneDisplayName(r.timeZone)
        } else if (updateTimeZone && this.observerTimeZone.length === 0 && r.longitude !== undefined) {
          this.observerTimeZone = approximateTimeZoneDisplay(Number(r.longitude))
        }
        const planet = r.planetName ?? r.planet
        if (planet) hooks.setObserverPlanet(planet)
        if (r.latitude !== undefined && r.longitude !== undefined) {
          this.setPickerLocation(r.name ?? I18n.t('custom_location'), r.latitude, r.longitude, r.altitude ?? 0, this.locationPickerStatus)
        }
        if (planet !== 'Earth') this.observerTimeZone = ''
      }
    })
  }

  // 星球显示名：translateCountry('ZZ') 需要「月球表面地点」这类星球名。
  private planetZhName(en: string): string {
    switch (en) {
      case 'Sun': return I18n.t('pl_sun')
      case 'Moon': return I18n.t('pl_moon')
      case 'Mercury': return I18n.t('pl_mercury')
      case 'Venus': return I18n.t('pl_venus')
      case 'Earth': return I18n.t('pl_earth')
      case 'Mars': return I18n.t('pl_mars')
      case 'Jupiter': return I18n.t('pl_jupiter')
      case 'Saturn': return I18n.t('pl_saturn')
      case 'Uranus': return I18n.t('pl_uranus')
      case 'Neptune': return I18n.t('pl_neptune')
      default: return en
    }
  }

  private degree(value: number, positive: string, negative: string): string {
    const direction = value >= 0 ? positive : negative
    return Math.abs(value).toFixed(2) + '°' + direction
  }

  pickerCoordinateText(): string {
    return this.degree(this.locationPickerLatitude, 'N', 'S') + ' / ' +
      this.degree(this.locationPickerLongitude, 'E', 'W') + ' / ' +
      this.locationPickerAltitude.toFixed(0) + ' m'
  }

  pickerPinX(): number {
    return (this.locationPickerLongitude + 180) / 360 * this.mapRenderWidth - 9
  }

  pickerPinY(): number {
    return (90 - this.locationPickerLatitude) / 180 * this.mapRenderHeight - 9
  }

  // 纯 setter：应用一次选点。
  // 地图点选（LocationPickerPanel 内）与控制器（LocationController 的 GPS / 城市落地）共用本方法。
  setPickerLocation(name: string, latitude: number, longitude: number, altitude: number, status: ResourceStr): void {
    this.locationPickerName = name
    this.locationPickerLatitude = clamp(latitude, -90, 90)
    this.locationPickerLongitude = clamp(longitude, -180, 180)
    this.locationPickerAltitude = Math.round(altitude)
    this.locationPickerStatus = status
  }

  // 在线地图点选：只更新草稿坐标（名称 / 海拔由用户确认时补）。
  applyPickedCoordinates(latitude: number, longitude: number): void {
    this.locationPickerLatitude = clamp(latitude, -90, 90)
    this.locationPickerLongitude = clamp(longitude, -180, 180)
  }

  // Translate continent name from Chinese to current language
  translateContinent(name: string): string {    const map: Record<string, string> = {
      '亚洲': I18n.t('continent_asia'),
      '欧洲': I18n.t('continent_europe'),
      '北美洲': I18n.t('continent_north_america'),
      '南美洲': I18n.t('continent_south_america'),
      '非洲': I18n.t('continent_africa'),
      '大洋洲': I18n.t('continent_oceania'),
      '南极洲': I18n.t('continent_antarctica'),
      '月球': '月球',
      '火星': '火星',
      '金星': '金星',
      '土卫六': '土卫六',
      '小行星贝努': '小行星贝努',
    }
    return map[name] ?? name
  }

  // Translate region/city names to current language
  translateRegion(name: string): string {
    if (!name || name === '未知地区') return I18n.t('region_unknown')
    if (I18n.isChineseLanguage()) {
      // Keep the upstream name as the native lookup key; Chinese UI never
      // falls back to that key, so incomplete source data cannot leak Latin text.
      return LOCATION_ZH_NAMES[name] ?? '未收录地点'
    }
    // Region names are city/timezone names from Stellarium's base_locations
    // Use I18n for known regions, fallback to original name
    const regionMap: Record<string, string> = {
      'Tokyo': I18n.t('city_tokyo'),
      'Seoul': I18n.t('city_seoul'),
      'Shanghai': I18n.t('city_shanghai'),
      'Hong Kong': I18n.t('city_hongkong'),
      'Taipei': I18n.t('city_taipei'),
      'Singapore': I18n.t('city_singapore'),
      'Bangkok': I18n.t('city_bangkok'),
      'Jakarta': I18n.t('city_jakarta'),
      'Kuala Lumpur': I18n.t('city_kuala_lumpur'),
      'Manila': I18n.t('city_manila'),
      'Ho Chi Minh': I18n.t('city_ho_chi_minh'),
      'Hanoi': I18n.t('city_hanoi'),
      'Beijing': I18n.t('city_beijing'),
      'New York': I18n.t('city_new_york'),
      'Los Angeles': I18n.t('city_los_angeles'),
      'Chicago': I18n.t('city_chicago'),
      'Toronto': I18n.t('city_toronto'),
      'Vancouver': I18n.t('city_vancouver'),
      'London': I18n.t('city_london'),
      'Paris': I18n.t('city_paris'),
      'Berlin': I18n.t('city_berlin'),
      'Madrid': I18n.t('city_madrid'),
      'Rome': I18n.t('city_rome'),
      'Moscow': I18n.t('city_moscow'),
      'Istanbul': I18n.t('city_istanbul'),
      'Athens': I18n.t('city_athens'),
      'Dubai': I18n.t('city_dubai'),
      'Tehran': I18n.t('city_tehran'),
      'Riyadh': I18n.t('city_riyadh'),
      'Jerusalem': I18n.t('city_jerusalem'),
      'Cairo': I18n.t('city_cairo'),
      'Lagos': I18n.t('city_lagos'),
      'Nairobi': I18n.t('city_nairobi'),
      'Johannesburg': I18n.t('city_johannesburg'),
      'Sydney': I18n.t('city_sydney'),
      'Melbourne': I18n.t('city_melbourne'),
      'Auckland': I18n.t('city_auckland'),
      'Honolulu': I18n.t('city_honolulu'),
      'Mumbai': I18n.t('city_mumbai'),
      'Kolkata': I18n.t('city_kolkata'),
      'Delhi': I18n.t('city_delhi'),
      'Karachi': I18n.t('city_karachi'),
      'Dhaka': I18n.t('city_dhaka'),
      'Colombo': I18n.t('city_colombo'),
      'Kathmandu': I18n.t('city_kathmandu'),
      'Yangon': I18n.t('city_yangon'),
      'Phnom Penh': I18n.t('city_phnom_penh'),
      'Vientiane': I18n.t('city_vientiane'),
      'Brunei': I18n.t('city_brunei'),
      'Macau': I18n.t('city_macau'),
      'Pyongyang': I18n.t('city_pyongyang'),
      'Ulaanbaatar': I18n.t('city_ulaanbaatar'),
      'Almaty': I18n.t('city_almaty'),
      'Tashkent': I18n.t('city_tashkent'),
      'Baku': I18n.t('city_baku'),
      'Tbilisi': I18n.t('city_tbilisi'),
      'Yerevan': I18n.t('city_yerevan'),
      'Kabul': I18n.t('city_kabul'),
      'Amman': I18n.t('city_amman'),
      'Beirut': I18n.t('city_beirut'),
      'Damascus': I18n.t('city_damascus'),
      'Baghdad': I18n.t('city_baghdad'),
      'Kuwait': I18n.t('city_kuwait'),
      'Muscat': I18n.t('city_muscat'),
      'Doha': I18n.t('city_doha'),
      'Bahrain': I18n.t('city_bahrain'),
      'Aden': I18n.t('city_aden'),
      'Khartoum': I18n.t('city_khartoum'),
      'Tripoli': I18n.t('city_tripoli'),
      'Tunis': I18n.t('city_tunis'),
      'Algiers': I18n.t('city_algiers'),
      'Casablanca': I18n.t('city_casablanca'),
      'Accra': I18n.t('city_accra'),
      'Dakar': I18n.t('city_dakar'),
      'Abidjan': I18n.t('city_abidjan'),
      'Addis Ababa': I18n.t('city_addis_ababa'),
      'Dar es Salaam': I18n.t('city_dar_es_salaam'),
      'Lusaka': I18n.t('city_lusaka'),
      'Harare': I18n.t('city_harare'),
      'Kigali': I18n.t('city_kigali'),
      'Bujumbura': I18n.t('city_bujumbura'),
      'Maputo': I18n.t('city_maputo'),
      'Antananarivo': I18n.t('city_antananarivo'),
      'Vienna': I18n.t('city_vienna'),
      'Prague': I18n.t('city_prague'),
      'Warsaw': I18n.t('city_warsaw'),
      'Budapest': I18n.t('city_budapest'),
      'Bucharest': I18n.t('city_bucharest'),
      'Sofia': I18n.t('city_sofia'),
      'Belgrade': I18n.t('city_belgrade'),
      'Zagreb': I18n.t('city_zagreb'),
      'Ljubljana': I18n.t('city_ljubljana'),
      'Sarajevo': I18n.t('city_sarajevo'),
      'Skopje': I18n.t('city_skopje'),
      'Tirane': I18n.t('city_tirane'),
      'Kyiv': I18n.t('city_kyiv'),
      'Minsk': I18n.t('city_minsk'),
      'Vilnius': I18n.t('city_vilnius'),
      'Riga': I18n.t('city_riga'),
      'Tallinn': I18n.t('city_tallinn'),
      'Helsinki': I18n.t('city_helsinki'),
      'Stockholm': I18n.t('city_stockholm'),
      'Oslo': I18n.t('city_oslo'),
      'Copenhagen': I18n.t('city_copenhagen'),
      'Reykjavik': I18n.t('city_reykjavik'),
      'Dublin': I18n.t('city_dublin'),
      'Lisbon': I18n.t('city_lisbon'),
      'Amsterdam': I18n.t('city_amsterdam'),
      'Brussels': I18n.t('city_brussels'),
      'Luxembourg': I18n.t('city_luxembourg'),
      'Bern': I18n.t('city_bern'),
      'Zurich': I18n.t('city_zurich'),

      'Mexico City': I18n.t('city_mexico_city'),
      'Guatemala': I18n.t('city_guatemala'),
      'Havana': I18n.t('city_havana'),
      'Panama': I18n.t('city_panama'),
      'Bogota': I18n.t('city_bogota'),
      'Lima': I18n.t('city_lima'),
      'Santiago': I18n.t('city_santiago'),
      'Buenos Aires': I18n.t('city_buenos_aires'),
      'Montevideo': I18n.t('city_montevideo'),
      'Asuncion': I18n.t('city_asuncion'),
      'Caracas': I18n.t('city_caracas'),
      'Quito': I18n.t('city_quito'),
      'La Paz': I18n.t('city_la_paz'),
      'Sucre': I18n.t('city_sucre'),
      'Sao Paulo': I18n.t('city_sao_paulo'),
      'Rio de Janeiro': I18n.t('city_rio_de_janeiro'),
      'Brasilia': I18n.t('city_brasilia'),
      'Perth': I18n.t('city_perth'),
      'Brisbane': I18n.t('city_brisbane'),
      'Adelaide': I18n.t('city_adelaide'),
      'Hobart': I18n.t('city_hobart'),
      'Darwin': I18n.t('city_darwin'),
      'Suva': I18n.t('city_suva'),
      'Apia': I18n.t('city_apia'),
      "Nuku'alofa": I18n.t('city_nukualofa'),
      'Port Moresby': I18n.t('city_port_moresby'),

    }
    return regionMap[name] ?? name
  }

  locationDisplayName(name: string): string {
    if (!name || name.length === 0) {
      return '--'
    }
    if (name === I18n.t('custom_location') || name === I18n.t('m_map_pick') ||
      name === I18n.t('m_current_location') || name.startsWith('Custom ')) {
      return I18n.t('custom_location')
    }
    const surface = this.surfaceLocationName(name)
    if (surface.length > 0) {
      return surface
    }
    const translated = this.translateRegion(name)
    return translated === '未收录地点' ? name : translated
  }

  // 引擎对非地球观测点给 "Mars surface" 这类英文默认名；折到本地化：
  // 有既有 land_* 键的用键（火星表面 / 月球表面 / 木星表面），其余按星球名加「表面」。
  private surfaceLocationName(name: string): string {
    const suffix = ' surface'
    if (!name.endsWith(suffix)) {
      return ''
    }
    const planet = name.substring(0, name.length - suffix.length)
    if (planet === 'Mars') {
      return I18n.t('land_mars')
    }
    if (planet === 'Moon') {
      return I18n.t('land_moon')
    }
    if (planet === 'Jupiter') {
      return I18n.t('land_jupiter')
    }
    return ''
  }

  locationColumnTitle(kind: string): string {
    if (kind === 'continent') {
      return I18n.t('h_continent')
    }
    if (kind === 'region') {
      return I18n.t('h_region')
    }
    if (kind === 'country') {
      return I18n.t('h_country')
    }
    return I18n.t('h_city')
  }

  hierarchyItemLabel(kind: string, name: string, observerPlanet: string): string {
    if (kind === 'continent') return this.translateContinent(name)
    if (kind === 'country') return this.translateCountry(name, observerPlanet)
    if (kind === 'region' && name === '未知地区' && observerPlanet !== 'Earth') return '月球任务地点'
    if (kind === 'region') return this.translateProvince(name)
    return this.locationDisplayName(name)
  }

  chineseRegionKey(city: HierCity): string {
    if (city.country === 'HK') return 'Hong Kong'
    if (city.country === 'MO') return 'Macau'
    if (city.country === 'TW') return 'Taiwan'
    return city.province ?? ''
  }

  locationPlanet(city: HierCity): string {
    return city.planet ?? 'Earth'
  }

  isCurrentObserverPlanet(city: HierCity, observerPlanet: string): boolean {
    return this.locationPlanet(city).toLowerCase() === observerPlanet.toLowerCase()
  }

  translateProvince(name: string): string {
    if (!name) return I18n.t('region_unknown')
    if (!I18n.isChineseLanguage()) return name
    const cached = PROVINCE_TRANSLATION_CACHE[name]
    if (cached !== undefined) return cached
    const provinceMap: Record<string, string> = {
      'Beijing': '北京市', 'Tianjin': '天津市', 'Shanghai': '上海市', 'Chongqing': '重庆市',
      'Hebei': '河北省', 'Shanxi': '山西省', 'Liaoning': '辽宁省', 'Jilin': '吉林省',
      'Heilongjiang': '黑龙江省', 'Jiangsu': '江苏省', 'Zhejiang': '浙江省', 'Anhui': '安徽省',
      'Fujian': '福建省', 'Jiangxi': '江西省', 'Shandong': '山东省', 'Henan': '河南省',
      'Hubei': '湖北省', 'Hunan': '湖南省', 'Guangdong': '广东省', 'Hainan': '海南省',
      'Sichuan': '四川省', 'Guizhou': '贵州省', 'Yunnan': '云南省', 'Shaanxi': '陕西省',
      'Gansu': '甘肃省', 'Qinghai': '青海省', 'Taiwan': '中国台湾地区', 'Taipei': '中国台湾地区',
      'Xinjiang': '新疆维吾尔自治区', 'Tibet': '西藏自治区', 'Inner Mongolia': '内蒙古自治区',
      'Guangxi': '广西壮族自治区', 'Ningxia': '宁夏回族自治区', 'Hong Kong': '中国香港特别行政区',
      'Macau': '中国澳门特别行政区', 'Macao': '中国澳门特别行政区',
    }
    const translated = provinceMap[name] ?? LOCATION_ZH_NAMES[name] ?? name
    PROVINCE_TRANSLATION_CACHE[name] = translated
    return translated
  }

  translateCountry(code: string, observerPlanet: string): string {
    const normalizedCode = code === 'TW' ? 'CN' : code
    if (normalizedCode === 'ZZ') {
      return observerPlanet === 'Earth' ? I18n.t('region_unknown') : this.planetZhName(observerPlanet) + '表面地点'
    }
    const country = LOCATION_COUNTRY_NAMES[normalizedCode]
    if (!country) return normalizedCode
    if (I18n.isChineseLanguage()) return country.zh
    return I18n.displayCountry(normalizedCode, country.en)
  }

  normalizedLocationCountry(code: string): string {
    // Chinese UI presents Hong Kong, Macao and Taiwan as regions under China.
    return code === 'TW' || code === 'HK' || code === 'MO' ? 'CN' : code
  }

  hierarchySelectionSummary(observerPlanet: string): string {
    const parts: Array<string> = []
    if (this.hierContinent) {
      parts.push(this.translateContinent(this.hierContinent))
    }
    if (this.hierCountry) {
      parts.push(this.translateCountry(this.hierCountry, observerPlanet))
    }
    if (this.hierRegion) {
      parts.push(this.hierarchyItemLabel('region', this.hierRegion, observerPlanet))
    }
    if (this.hierCity) {
      parts.push(this.locationDisplayName(this.hierCity))
    }
    return parts.length > 0 ? parts.join('  >  ') : '未选择'
  }

  private hierContinents(observerPlanet: string): Array<string> {
    return Object.keys(LOCATION_HIERARCHY).filter((continent: string) =>
      Object.values(LOCATION_HIERARCHY[continent]).some((cities: Array<HierCity>) =>
        cities.some((city: HierCity) => this.isCurrentObserverPlanet(city, observerPlanet))))
  }

  private hierRegions(observerPlanet: string): Array<string> {
    if (this.hierContinent === '' || this.hierCountry === '' || !LOCATION_HIERARCHY[this.hierContinent]) {
      return []
    }
    if (this.hierCountry === 'CN') {
      const provinces = new Set<string>()
      for (const cities of Object.values(LOCATION_HIERARCHY[this.hierContinent])) {
        for (const city of cities) {
          if (!this.isCurrentObserverPlanet(city, observerPlanet)) continue
          if (this.normalizedLocationCountry(city.country) !== 'CN') continue
          const province = this.chineseRegionKey(city)
          if (province.length > 0) provinces.add(province)
        }
      }
      return Array.from(provinces).sort((a: string, b: string) =>
        this.translateProvince(a).localeCompare(this.translateProvince(b)))
    }
    return Object.keys(LOCATION_HIERARCHY[this.hierContinent]).filter((region: string) =>
      LOCATION_HIERARCHY[this.hierContinent][region].some((city: HierCity) =>
        this.isCurrentObserverPlanet(city, observerPlanet) && this.normalizedLocationCountry(city.country) === this.hierCountry))
  }

  private hierCountries(observerPlanet: string): Array<string> {
    if (this.hierContinent === '' || !LOCATION_HIERARCHY[this.hierContinent]) return []
    const countries = new Set<string>()
    for (const cities of Object.values(LOCATION_HIERARCHY[this.hierContinent])) {
      for (const city of cities) {
        if (this.isCurrentObserverPlanet(city, observerPlanet)) countries.add(this.normalizedLocationCountry(city.country))
      }
    }
    return Array.from(countries).sort((a: string, b: string) =>
      this.translateCountry(a, observerPlanet).localeCompare(this.translateCountry(b, observerPlanet)))
  }

  private hierCityList(observerPlanet: string): Array<HierCity> {
    if (this.hierContinent === '' || this.hierCountry === '' || this.hierRegion === '' ||
      !LOCATION_HIERARCHY[this.hierContinent]) {
      return []
    }
    if (this.hierCountry === 'CN') {
      const cities: Array<HierCity> = []
      for (const regionCities of Object.values(LOCATION_HIERARCHY[this.hierContinent])) {
        for (const city of regionCities) {
          if (!this.isCurrentObserverPlanet(city, observerPlanet)) continue
          if (this.normalizedLocationCountry(city.country) === 'CN' && this.chineseRegionKey(city) === this.hierRegion) {
            cities.push(city)
          }
        }
      }
      return cities
    }
    if (!LOCATION_HIERARCHY[this.hierContinent][this.hierRegion]) return []
    return LOCATION_HIERARCHY[this.hierContinent][this.hierRegion]
      .filter((city: HierCity) => this.isCurrentObserverPlanet(city, observerPlanet) && this.normalizedLocationCountry(city.country) === this.hierCountry)
  }

  hierCityNames(observerPlanet: string): Array<string> {
    return this.hierCityList(observerPlanet).map((c: HierCity) => c.n)
  }

  // 层级列的各项列表：供 HierColumn 组件按 kind 取值（continent/country/region/city）。
  hierColumnItems(kind: string, observerPlanet: string): Array<string> {
    if (kind === 'continent') return this.hierContinents(observerPlanet)
    if (kind === 'country') return this.hierCountries(observerPlanet)
    if (kind === 'region') return this.hierRegions(observerPlanet)
    return this.hierCityNames(observerPlanet)
  }

  // 层级城市列表（selectCityByName 需要拿到经纬度落地）。
  hierCities(observerPlanet: string): Array<HierCity> {
    return this.hierCityList(observerPlanet)
  }

  hierarchySelectionFor(kind: string): string {
    if (kind === 'continent') return this.hierContinent
    if (kind === 'country') return this.hierCountry
    if (kind === 'region') return this.hierRegion
    return this.hierCity
  }

  // 离线快速搜索候选（内置城市名 → 城市预设 + 本地化显示名）。
  quickLocationSearchItems(): Array<LocSearchItem> {
    const names: string[] = [
      'Beijing', 'Shanghai', 'Guangzhou', 'Shenzhen', 'Chengdu', 'Hangzhou', 'Wuhan',
      'Xian', 'Nanjing', 'Chongqing', 'Harbin', 'Lhasa', 'Urumqi', 'HongKong', 'Taipei',
      'Tokyo', 'Seoul', 'Singapore', 'NewYork', 'London', 'Sydney', 'Paris', 'Berlin',
      'Moscow', 'Dubai', 'Mumbai', 'Cairo', 'Rio', 'LosAngeles', 'Toronto', 'Mexico',
      'Bangkok', 'Istanbul', 'Amsterdam', 'Stockholm', 'Reykjavik', 'CapeTown',
      'BuenosAires', 'Honolulu'
    ]
    const items: Array<LocSearchItem> = []
    for (const name of names) {
      const preset = getCityPreset(name)
      if (preset === undefined) continue
      const displayName = this.locationDisplayName(name)
      items.push({ name: name, displayName: displayName, lat: preset.lat, lon: preset.lon, alt: preset.alt, planet: 'Earth', country: '', region: '' })
    }
    return items
  }

  // 位置搜索的国名显示：observerPlanet 属跨域状态，以显式入参传入；translateCountry 为本 store 方法。
  locationSearchCountryName(countryCode: string, observerPlanet: string): string {
    if (countryCode === 'TW' || countryCode === 'HK' || countryCode === 'MO') {
      return I18n.isChineseLanguage()
        ? (LOCATION_COUNTRY_NAMES[countryCode]?.zh ?? this.translateCountry(countryCode, observerPlanet))
        : this.translateCountry(countryCode, observerPlanet)
    }
    return this.translateCountry(countryCode, observerPlanet)
  }

  // 位置结果上下文（省 / 国）：读本 store 的 translateProvince 与 locationSearchCountryName；
  // observerPlanet 显式传入。
  locationResultContext(item: LocSearchItem, observerPlanet: string): string {
    const parts: Array<string> = []
    const append = (value: string): void => {
      if (value.length > 0 && !parts.includes(value)) parts.push(value)
    }
    if (item.province) append(this.translateProvince(item.province))
    else if (item.region) append(this.translateProvince(item.region))
    if (item.country) append(this.locationSearchCountryName(item.country, observerPlanet))
    return parts.join(' · ')
  }

  // 离线快速搜索：读本 store 的 quickLocationSearchItems，过滤/排序用纯函数
  // matchesLocationSearch / locationSearchMatchScore；observerPlanet 以显式入参传入。
  quickLocationSearch(query: string, observerPlanet: string): Array<LocSearchItem> {
    if (!query.trim()) return []
    return this.quickLocationSearchItems()
      .filter((item: LocSearchItem) => item.planet.toLowerCase() === observerPlanet.toLowerCase())
      .filter((item: LocSearchItem) => matchesLocationSearch(
        item.name + ' ' + (item.displayName ?? '') + ' ' + (LOCATION_ZH_NAMES[item.name] ?? ''), query))
      .sort((left: LocSearchItem, right: LocSearchItem) => {
        const leftText = left.name + ' ' + (left.displayName ?? '') + ' ' + (LOCATION_ZH_NAMES[left.name] ?? '')
        const rightText = right.name + ' ' + (right.displayName ?? '') + ' ' + (LOCATION_ZH_NAMES[right.name] ?? '')
        return locationSearchMatchScore(query, [right.name, right.displayName ?? '', LOCATION_ZH_NAMES[right.name] ?? ''], rightText) -
          locationSearchMatchScore(query, [left.name, left.displayName ?? '', LOCATION_ZH_NAMES[left.name] ?? ''], leftText)
      })
  }
}
