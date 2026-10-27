// 位置域控制器：负责设备定位、层级城市选点、观测星球切换与观测点持久化/启动恢复。
//
// 不 import NAPI/UI：权限 / 定位 / preferences 经 LocationPort；桥命令经 CommandPort；
// 跨域 store 写（SessionToolStore 的 observerPlanet、位置头部三 @State）经
// LocationHostHooks 具名回注；观测点草稿与请求中标志由控制器自持。
import hilog from '@ohos.hilog'
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse, HierCity } from '../pages/StellariumTypes'
import { ObserverLocationRecord } from '../pages/MainWindowModels'
import { approximateTimeZoneDisplay, planetZh, quickLocationLabel } from '../common/derive/labels'
import { CommandPort } from '../bridge/CommandPort'
import { LocationPort } from '../bridge/LocationPort'
import { LocationPickerStore } from '../state/LocationPickerStore'
import { LocationStore } from '../state/LocationStore'
import { SessionToolStore } from '../state/SessionToolStore'

// 宿主生命周期 / UI / 跨域写注入（控制器不触碰 UI 与宿主私有 @State / 他 store 写）。
export interface LocationHostHooks {
  flashHint(text: ResourceStr): void
  refreshState(): void
  // 观测点信息回读（宿主侧 this.locationPickerStore.loadObserverInfo(true)）。
  loadObserverInfo(): void
  // 观测星球写 SessionToolStore.observerPlanet（跨域共享；控制器只读该 store，写经 hooks）。
  setObserverPlanetCrossStore(name: string): void
  // 位置头部三 @State（locationText / coordinateText / altitudeText）回注。
  setLocationTexts(location: string, coordinate: string, altitude: string): void
  // GPS 门禁（宿主保留：privacyNativeStartupAllowed / applicationInForeground / hasCurrentPrivacyConsent）。
  privacyAllowed(): boolean
  inForeground(): boolean
  hasPrivacyConsent(): boolean
}

export class LocationController {
  private port: CommandPort
  private locationPort: LocationPort
  private pickerStore: LocationPickerStore
  private locationStore: LocationStore
  private sessionToolStore: SessionToolStore
  private hooks: LocationHostHooks
  // 请求中标志：草稿字段随控制器走（不入 @Observed store）。
  private deviceLocationRequestInProgress: boolean = false

  constructor(
    port: CommandPort,
    locationPort: LocationPort,
    pickerStore: LocationPickerStore,
    locationStore: LocationStore,
    sessionToolStore: SessionToolStore,
    hooks: LocationHostHooks
  ) {
    this.port = port
    this.locationPort = locationPort
    this.pickerStore = pickerStore
    this.locationStore = locationStore
    this.sessionToolStore = sessionToolStore
    this.hooks = hooks
  }

  // 切换在线地图提供方：'offline' 用内建坐标输入，'huawei' 用 MapKit 在线选点。
  // 切到在线需隐私同意 + 前台；状态经 AppStorage 发布给 getLocationMapState 命令。
  setLocationMapProvider(provider: string): void {
    if (provider !== 'offline' && provider !== 'huawei') return
    if (provider === 'huawei' && (this.sessionToolStore.observerPlanet !== 'Earth' || !this.hooks.privacyAllowed() || !this.hooks.inForeground() || !this.hooks.hasPrivacyConsent())) return
    this.locationStore.locationMapProvider = provider
    AppStorage.setOrCreate('stellariumLocationMapState', JSON.stringify({
      ok: true, provider: provider, phase: provider === 'offline' ? 'ready' : 'requested',
      error: '', operation: '', observerCoordinateSystem: 'WGS84'
    }))
  }

  // 大洲选择（清空下级层级，纯 store 写）。
  selectContinent(c: string): void {    this.pickerStore.hierContinent = c
    this.pickerStore.hierCountry = ''
    this.pickerStore.hierRegion = ''
    this.pickerStore.hierCity = ''
  }

  // 国家选择（清空下级层级，纯 store 写）。
  selectCountry(country: string): void {
    this.pickerStore.hierCountry = country
    this.pickerStore.hierRegion = ''
    this.pickerStore.hierCity = ''
  }

  // 地区选择（清空城市，纯 store 写）。
  selectRegion(r: string): void {
    this.pickerStore.hierRegion = r
    this.pickerStore.hierCity = ''
  }

  // 城市选择并立即落地（层级城市经纬度取自 store）。
  selectCityByName(name: string): void {
    this.pickerStore.hierCity = name
    const found = this.pickerStore.hierCities(this.sessionToolStore.observerPlanet).find((c: HierCity) => c.n === name)
    if (found) {
      // Auto-apply the selected city immediately
      this.setLocation(found.n, found.la, found.lo, found.al, this.pickerStore.locationPlanet(found))
    }
  }

  // 设备定位（GPS：隐私门禁 → 权限 → 定位 → setPickerLocation → applyPickerLocation）。
  // 4 处门禁（初始 + 权限后 + 定位后）经 hooks；权限/定位经 LocationPort。
  async useDeviceLocation(): Promise<void> {
    if (this.deviceLocationRequestInProgress || !this.hooks.privacyAllowed() ||
      !this.hooks.inForeground() || !this.hooks.hasPrivacyConsent()) return
    this.deviceLocationRequestInProgress = true
    hilog.info(0x0000, 'StellariumArkUI', 'useDeviceLocation() called')
    this.pickerStore.locationPickerStatus = I18n.t('m_req_location_perm')
    try {
      const granted = await this.locationPort.requestLocationPermissions()
      if (!this.hooks.privacyAllowed() || !this.hooks.inForeground() || !this.hooks.hasPrivacyConsent()) return
      if (!granted) {
        this.pickerStore.locationPickerStatus = I18n.t('m_gps_unavailable')
        return
      }
      this.pickerStore.locationPickerStatus = I18n.t('m_getting_location')
      const current = await this.locationPort.getCurrentLocation()
      if (!this.hooks.privacyAllowed() || !this.hooks.inForeground() || !this.hooks.hasPrivacyConsent()) return
      const altitude = Number.isFinite(current.altitude) ? current.altitude : 0
      this.pickerStore.setPickerLocation(I18n.t('m_current_location'), current.latitude, current.longitude, altitude, I18n.t('m_device_loc_synced'))
      this.pickerStore.locationSource = 'gps'
      this.setLocation(this.pickerStore.locationPickerName, current.latitude, current.longitude, altitude, 'Earth', false, 'gps')
      this.pickerStore.locationPickMode = 'map'
      this.pickerStore.hierContinent = ''
      this.pickerStore.hierCountry = ''
      this.pickerStore.hierRegion = ''
      this.pickerStore.hierCity = ''
    } catch (err) {
      const errMsg: string = err instanceof Error ? err.message : JSON.stringify(err)
      hilog.warn(0x0000, 'StellariumArkUI', 'device location failed: %{public}s', errMsg)
      this.pickerStore.locationPickerStatus = I18n.t('m_gps_unavailable')
    } finally {
      this.deviceLocationRequestInProgress = false
    }
  }

  applyPickerLocation(): void {
    // 来源沿用 picker 暂存值（GPS / 地图点选各自设过）；其余经本路径应用的场景默认 named。
    this.setLocation(this.pickerStore.locationPickerName, this.pickerStore.locationPickerLatitude, this.pickerStore.locationPickerLongitude, this.pickerStore.locationPickerAltitude, this.sessionToolStore.observerPlanet, false, this.pickerStore.locationSource)
  }

  setLocation(name: string, latitude: number, longitude: number, altitude: number, planet: string = 'Earth', silent: boolean = false, source: string = 'named'): void {
    if (this.sessionToolStore.observerPlanetPending) return
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || !Number.isFinite(altitude) ||
      latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return
    const targetPlanet = planet.length > 0 ? planet : 'Earth'
    this.sessionToolStore.observerPlanetPending = true
    const complete = (response: StellariumBridgeResponse): void => {
      this.sessionToolStore.observerPlanetPending = false
      if (response.ok !== true) {
        this.hooks.flashHint(I18n.t('m_observer_switch_failed'))
        this.hooks.loadObserverInfo()
        return
      }
      this.commitLocation(response.locationName ?? name, response.latitude ?? latitude,
        response.longitude ?? longitude, response.altitude ?? Math.round(altitude), response.planetName ?? targetPlanet, source)
      this.hooks.refreshState()
      this.hooks.loadObserverInfo()
      if (!silent) this.hooks.flashHint(I18n.t('i0073').replace('%s', this.pickerStore.locationDisplayName(name)))
    }
    this.port.requestWhenReady('setObserverPlanet', `${targetPlanet}|${latitude}|${longitude}|${Math.round(altitude)}|${name.replace(/\|/g, ' ')}`, complete, complete, 0, 100, 10)
  }

  private commitLocation(name: string, latitude: number, longitude: number, altitude: number, targetPlanet: string, source: string): void {
    const planetChanged = targetPlanet !== this.sessionToolStore.observerPlanet
    this.pickerStore.setPickerLocation(name, latitude, longitude, altitude, I18n.t('m_synced_to_sky'))
    this.pickerStore.locationSource = source
    this.hooks.setObserverPlanetCrossStore(targetPlanet)
    if (planetChanged) {
      this.pickerStore.hierContinent = ''
      this.pickerStore.hierCountry = ''
      this.pickerStore.hierRegion = ''
      this.pickerStore.hierCity = ''
      this.locationStore.locSearchQuery = ''
      this.locationStore.searchLocations('')
      if (targetPlanet !== 'Earth') this.setLocationMapProvider('offline')
    }
    this.saveObserverLocationToStorage()
    this.hooks.setLocationTexts(
        quickLocationLabel(source, this.pickerStore.locationDisplayName(name), targetPlanet) + ' · ' + planetZh(targetPlanet),
      this.locationStore.formatDegrees(latitude, 'N', 'S') + ' / ' + this.locationStore.formatDegrees(longitude, 'E', 'W'),
      altitude.toFixed(0) + ' m')
    this.pickerStore.observerTimeZone = targetPlanet === 'Earth' ? approximateTimeZoneDisplay(longitude) : I18n.t('tz_system')
  }

  // 切换观测星球（本 store 只读 observerPlanet，写经 hooks）。
  setObserverPlanet(name: string): void {
    if (name === this.sessionToolStore.observerPlanet) return
    this.setLocation(I18n.t('custom_location'), this.pickerStore.locationPickerLatitude,
      this.pickerStore.locationPickerLongitude, this.pickerStore.locationPickerAltitude, name, false, 'map')
  }

  syncObserverFromNative(): void {
    this.port.requestInteractive('getObserverInfo', '', (response: StellariumBridgeResponse) => {
      if (response.ok !== true || response.latitude === undefined || response.longitude === undefined) return
      const planet = response.planetName ?? response.planet ?? 'Earth'
      this.commitLocation(response.name ?? I18n.t('custom_location'), response.latitude, response.longitude,
        response.altitude ?? 0, planet, planet === 'Earth' ? this.pickerStore.locationSource : 'map')
      this.hooks.refreshState()
      this.hooks.loadObserverInfo()
    })
  }

  // 构造记录后经 LocationPort 落盘（preferences 错误处理在适配器）。
  async saveObserverLocationToStorage(): Promise<void> {
    const rec: ObserverLocationRecord = {
      name: this.pickerStore.locationPickerName,
      latitude: this.pickerStore.locationPickerLatitude,
      longitude: this.pickerStore.locationPickerLongitude,
      altitude: this.pickerStore.locationPickerAltitude,
      planet: this.sessionToolStore.observerPlanet,
      source: this.pickerStore.locationSource
    }
    await this.locationPort.writeObserverLocation(JSON.stringify(rec))
  }

  // 经 LocationPort 读持久化 JSON（失败返回 ''）。
  async readObserverLocationStorage(): Promise<string> {
    return await this.locationPort.readObserverLocation()
  }

  // 启动恢复持久化观测点并静默重建。
  async restoreObserverLocation(): Promise<void> {
    const json = await this.readObserverLocationStorage()
    if (json.length === 0) {
      return
    }
    let rec: ObserverLocationRecord | undefined = undefined
    try {
      rec = JSON.parse(json) as ObserverLocationRecord
    } catch (e) {
      return
    }
    if (rec === undefined || !Number.isFinite(rec.latitude) || !Number.isFinite(rec.longitude)) {
      return
    }
    const planet = typeof rec.planet === 'string' && rec.planet.length > 0 ? rec.planet : 'Earth'
    const name = typeof rec.name === 'string' && rec.name.length > 0 ? rec.name : I18n.t('m_current_location')
    const altitude = Number.isFinite(rec.altitude) ? rec.altitude : 0
    // 来源随观测点持久化；旧记录没有该字段时回落 named（按名称显示）。
    const source = typeof rec.source === 'string' && rec.source.length > 0 ? rec.source : 'named'
    hilog.info(0x0000, 'StellariumArkUI', '[location] restoring persisted observer location')
    this.setLocation(name, rec.latitude, rec.longitude, altitude, planet, true, source)
  }
}
