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
import { METERED_MAP_APIS_ENABLED } from '../common/config/OhosFeatureFlags'
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
  // 本次 GPS 定位没有可用的垂直分量；commitLocation 用它替换“已同步”状态。
  private gpsAltitudeUnavailable: boolean = false
  // GPS 定位后异步反查的最小行政区名称，追加在 “GPS” 标签后；过期请求序号。
  private gpsNameRequestId: number = 0
  // 旧持久化记录没有 GPS 行政区名称；待观测点恢复提交后补查一次，避免启动时反查与提交竞态。
  private restoreDetailPending: boolean = false
  private restoreDetailLatitude: number = 0
  private restoreDetailLongitude: number = 0
  // Earth altitude bounds; non-Earth sites keep the offline place value (often 0).
  private static readonly EARTH_ALTITUDE_MIN: number = -500
  private static readonly EARTH_ALTITUDE_MAX: number = 9000

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
    // GPS fixes and GNSS altitude are Earth-only. Other bodies must use the
    // offline place altitude (usually 0).
    if (this.sessionToolStore.observerPlanet !== 'Earth') return
    if (this.deviceLocationRequestInProgress || !this.hooks.privacyAllowed() ||
      !this.hooks.inForeground() || !this.hooks.hasPrivacyConsent()) return
    this.deviceLocationRequestInProgress = true
    hilog.info(0x0000, 'StellariumArkUI', 'useDeviceLocation() called')
    this.pickerStore.locationPickerStatus = I18n.t('m_req_location_perm')
    try {
      const permission = await this.locationPort.requestLocationPermissions()
      if (!this.hooks.privacyAllowed() || !this.hooks.inForeground() || !this.hooks.hasPrivacyConsent()) return
      if (permission !== 'precise') {
        this.pickerStore.locationPickerStatus = I18n.t(permission === 'approximate'
          ? 'm_gps_precise_required' : 'm_gps_unavailable')
        // There is no public API to open the app's permission page; show the
        // system-settings instruction without adding a snackbar action.
        this.hooks.flashHint(I18n.t('loc_gps_denied_settings'))
        return
      }
      this.pickerStore.locationPickerStatus = I18n.t('m_getting_location')
      const current = await this.locationPort.getCurrentLocation()
      if (!this.hooks.privacyAllowed() || !this.hooks.inForeground() || !this.hooks.hasPrivacyConsent()) return
      const altitude = Number.isFinite(current.altitude) ? current.altitude : 0
      // Wireless/indoor fixes often report altitude 0 with altitudeAccuracy 0.
      // Keep the position but tell the user that the vertical component is absent.
      // Undefined accuracy (older location stacks) is treated as usable.
      this.gpsAltitudeUnavailable = current.altitudeAccuracy !== undefined && current.altitudeAccuracy <= 0
      let status: string = this.gpsAltitudeUnavailable
        ? I18n.t('m_gps_altitude_unavailable') : I18n.t('m_device_loc_synced')
      if (current.accuracy !== undefined && current.accuracy > 0) {
        status += ' · ' + I18n.t('loc_gps_accuracy').replace('%s', Math.round(current.accuracy).toString())
      }
      if (current.altitudeAccuracy !== undefined && current.altitudeAccuracy > 0) {
        status += ' · ' + I18n.t('loc_gps_altitude_accuracy').replace('%s', Math.round(current.altitudeAccuracy).toString())
      }
      this.pickerStore.setPickerLocation(I18n.t('m_current_location'), current.latitude, current.longitude,
        altitude, status)
      this.pickerStore.locationSource = 'gps'
      // Name enrichment runs in parallel with the observer update; a slow or
      // failed reverse-geocode must not delay the GPS fix.
      const nameRequestId = ++this.gpsNameRequestId
      this.pickerStore.gpsPlaceDetail = ''
      this.setLocation(this.pickerStore.locationPickerName, current.latitude, current.longitude, altitude, 'Earth', false, 'gps')
      void this.resolveGpsPlaceName(current.latitude, current.longitude, nameRequestId)
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

  // GPS label enrichment: reverse-geocode the fix and append the smallest
  // administrative division after "GPS". Runs asynchronously after the fix is
  // applied; stale requests are dropped by gpsNameRequestId.
  private async resolveGpsPlaceName(latitude: number, longitude: number, requestId: number): Promise<void> {
    if (!METERED_MAP_APIS_ENABLED) return
    if (!this.hooks.privacyAllowed() || !this.hooks.inForeground() || !this.hooks.hasPrivacyConsent()) return
    try {
      const detail = await this.locationPort.reverseGeocodePlaceName(latitude, longitude)
      if (requestId !== this.gpsNameRequestId) return
      if (detail.length === 0 || this.pickerStore.locationSource !== 'gps') return
      // Only label/save when the picker still points at the fix that was queried;
      // restoring old records resolves after the observer commit.
      if (!this.pickerAtLocation(latitude, longitude)) return
      this.pickerStore.gpsPlaceDetail = detail
      // Persist the name with the observer record so restart keeps
      // `GPS · <admin division>` without another metered reverse-geocode.
      void this.saveObserverLocationToStorage()
      this.hooks.setLocationTexts(
        quickLocationLabel('gps',
          this.pickerStore.locationDisplayName(this.pickerStore.locationPickerName), 'Earth', detail) + ' · ' + planetZh('Earth'),
        this.locationStore.formatDegrees(this.pickerStore.locationPickerLatitude, 'N', 'S') + ' / ' +
          this.locationStore.formatDegrees(this.pickerStore.locationPickerLongitude, 'E', 'W'),
        this.pickerStore.locationPickerAltitude.toFixed(0) + ' m')
    } catch (_error) {
      // Keep the GPS-only label if the reverse geocoder is unavailable.
    }
  }

  private pickerAtLocation(latitude: number, longitude: number): boolean {
    return Math.abs(this.pickerStore.locationPickerLatitude - latitude) < 1e-6 &&
      Math.abs(this.pickerStore.locationPickerLongitude - longitude) < 1e-6
  }

  applyPickerLocation(): void {
    // 来源沿用 picker 暂存值（GPS / 地图点选各自设过）；其余经本路径应用的场景默认 named。
    this.setLocation(this.pickerStore.locationPickerName, this.pickerStore.locationPickerLatitude, this.pickerStore.locationPickerLongitude, this.pickerStore.locationPickerAltitude, this.sessionToolStore.observerPlanet, false, this.pickerStore.locationSource)
  }

  setLocation(name: string, latitude: number, longitude: number, altitude: number,
    planet: string = 'Earth', silent: boolean = false, source: string = 'named'): void {
    if (this.sessionToolStore.observerPlanetPending) return
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || !Number.isFinite(altitude) ||
      latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return
    const targetPlanet = planet.length > 0 ? planet : 'Earth'
    if (source !== 'gps') {
      // A non-GPS apply invalidates any in-flight GPS name enrichment.
      this.gpsNameRequestId += 1
      this.pickerStore.gpsPlaceDetail = ''
    }
    // Earth altitude is editable in the panel; keep it in a sane range. Other
    // bodies keep the offline place altitude (often 0).
    const normalizedAltitude = targetPlanet === 'Earth'
      ? Math.max(LocationController.EARTH_ALTITUDE_MIN,
        Math.min(LocationController.EARTH_ALTITUDE_MAX, Math.round(altitude)))
      : altitude
    this.sessionToolStore.observerPlanetPending = true
    const complete = (response: StellariumBridgeResponse): void => {
      this.sessionToolStore.observerPlanetPending = false
      if (response.ok !== true) {
        this.hooks.flashHint(I18n.t('loc_apply_failed'))
        this.hooks.loadObserverInfo()
        return
      }
      const appliedName = response.locationName ?? name
      const appliedLat = response.latitude ?? latitude
      const appliedLon = response.longitude ?? longitude
      const appliedAlt = response.altitude ?? normalizedAltitude
      const appliedPlanet = response.planetName ?? targetPlanet
      this.commitLocation(appliedName, appliedLat, appliedLon, appliedAlt, appliedPlanet, source)
      this.hooks.refreshState()
      this.hooks.loadObserverInfo()
      if (!silent) {
        this.locationStore.recordRecentLocation(appliedName, appliedLat, appliedLon, appliedAlt, appliedPlanet)
        this.hooks.flashHint(I18n.t('i0073').replace('%s', this.pickerStore.locationDisplayName(appliedName)))
      }
    }
    this.port.requestWhenReady('setObserverPlanet',
      `${targetPlanet}|${latitude}|${longitude}|${Math.round(normalizedAltitude)}|${name.replace(/\|/g, ' ')}`,
      complete, complete, 0, 100, 10)
  }

  private commitLocation(name: string, latitude: number, longitude: number, altitude: number, targetPlanet: string, source: string): void {
    const planetChanged = targetPlanet !== this.sessionToolStore.observerPlanet
    const status = source === 'gps' && this.gpsAltitudeUnavailable
      ? I18n.t('m_gps_altitude_unavailable') : I18n.t('m_synced_to_sky')
    this.pickerStore.setPickerLocation(name, latitude, longitude, altitude, status)
    this.gpsAltitudeUnavailable = false
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
        quickLocationLabel(source, this.pickerStore.locationDisplayName(name), targetPlanet,
          source === 'gps' ? this.pickerStore.gpsPlaceDetail : '') + ' · ' + planetZh(targetPlanet),
      this.locationStore.formatDegrees(latitude, 'N', 'S') + ' / ' + this.locationStore.formatDegrees(longitude, 'E', 'W'),
      altitude.toFixed(0) + ' m')
    this.pickerStore.observerTimeZone = targetPlanet === 'Earth' ? approximateTimeZoneDisplay(longitude) : I18n.t('tz_system')
    // Legacy records have no persisted GPS admin name: after the observer is
    // actually committed, query it once. Doing it here avoids saving/updating
    // the label against the picker's pre-restore default coordinates.
    if (this.restoreDetailPending) {
      const matches = source === 'gps' && targetPlanet === 'Earth' &&
        this.pickerAtLocation(this.restoreDetailLatitude, this.restoreDetailLongitude)
      this.restoreDetailPending = false
      if (matches) {
        const requestId = ++this.gpsNameRequestId
        void this.resolveGpsPlaceName(latitude, longitude, requestId)
      }
    }
  }

  // 切换观测星球（本 store 只读 observerPlanet，写经 hooks）。
  // GPS/海拔只在地球有效；切到其他天体时不沿用地球海拔，默认 0。
  // 若用户随后选择带海拔的离线地点，selectSearchLocation 会写入该地点的 alt。
  setObserverPlanet(name: string): void {
    if (name === this.sessionToolStore.observerPlanet) return
    const altitude = name === 'Earth' ? this.pickerStore.locationPickerAltitude : 0
    this.setLocation(I18n.t('custom_location'), this.pickerStore.locationPickerLatitude,
      this.pickerStore.locationPickerLongitude, altitude, name, false, 'map')
  }

  syncObserverFromNative(): void {
    this.port.requestInteractive('getObserverInfo', '', (response: StellariumBridgeResponse) => {
      if (response.ok !== true || response.latitude === undefined || response.longitude === undefined) return
      const planet: string = response.planet ?? 'Earth'
      const source: string = planet === 'Earth' ? this.pickerStore.locationSource : 'map'
      const name: string = response.name ?? I18n.t('custom_location')
      const altitude: number = response.altitude ?? 0
      this.commitLocation(name, response.latitude, response.longitude, altitude, planet, source)
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
      source: this.pickerStore.locationSource,
      detail: this.pickerStore.locationSource === 'gps' ? this.pickerStore.gpsPlaceDetail : ''
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
    // GPS altitude is Earth-only; discard old non-Earth GPS records.
    const restoredAltitude = planet !== 'Earth' && source === 'gps' ? 0 : altitude
    // GPS admin name is persisted with the record. Older records lack it, so
    // resolve it once after the commit instead of at every startup.
    const detail = typeof rec.detail === 'string' ? rec.detail : ''
    this.pickerStore.gpsPlaceDetail = source === 'gps' ? detail : ''
    this.restoreDetailPending = source === 'gps' && planet === 'Earth' && detail.length === 0
    this.restoreDetailLatitude = rec.latitude
    this.restoreDetailLongitude = rec.longitude
    hilog.info(0x0000, 'StellariumArkUI', '[location] restoring persisted observer location')
    this.setLocation(name, rec.latitude, rec.longitude, restoredAltitude, planet, true, source)
  }
}
