// 位置域控制器：负责设备定位、层级城市选点、观测星球切换与观测点持久化/启动恢复。
//
// 不 import NAPI/UI：权限 / 定位 / preferences 经 LocationPort；桥命令经 CommandPort；
// 跨域 store 写（SessionToolStore 的 observerPlanet、位置头部三 @State）经
// LocationHostHooks 具名回注；观测点草稿与请求中标志由控制器自持。
import hilog from '@ohos.hilog'
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse, HierCity } from '../pages/StellariumTypes'
import { ObserverLocationRecord } from '../pages/MainWindowModels'
import { approximateTimeZoneDisplay, quickLocationLabel } from '../common/derive/labels'
import { METERED_MAP_APIS_ENABLED } from '../common/config/OhosFeatureFlags'
import { CommandPort } from '../bridge/CommandPort'
import { LocationFix, LocationPort } from '../bridge/LocationPort'
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
  // 同步星象文化观测纬度（避免每次定位后额外发一次 getObserverInfo 往返）。
  setSkyCultureObserverLatitude?: (latitude: number) => void
  // 位置头部三 @State（locationText / coordinateText / altitudeText）回注。
  // coordsChanged=false 表示仅补充逆地理编码地名，不应重复触发桌面卡片与通知订阅重算。
  setLocationTexts(location: string, coordinate: string, altitude: string, coordsChanged?: boolean): void
  // 观测点变化后让今晚天象缓存失效，并在可见时按新坐标重算。
  refreshTonightData(): void
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
  // 静默自动定位检查进行中标志（启动 / 回前台），避免并发重复请求。
  private silentAutoRefreshInProgress: boolean = false
  // 上次静默位置校验时间戳（回前台 10 分钟冷却，避免频繁切 App 耗电）。
  private lastSilentRefreshAt: number = 0
  // 前台大位移监听是否已注册（Plan 3）。
  private foregroundWatchActive: boolean = false
  // 后台 GNSS 海拔精修序号：仅当快速定位无海拔时静默补一次，过时或用户改点后自动丢弃。
  private altitudeRefineRequestId: number = 0
  // 本次 GPS 定位没有可用的垂直分量；commitLocation 用它替换“已同步”状态。
  private gpsAltitudeUnavailable: boolean = false
  // GPS 定位后异步反查的最小行政区名称，追加在 “GPS” 标签后；过期请求序号。
  private gpsNameRequestId: number = 0
  // 旧持久化记录没有 GPS 行政区名称；待观测点恢复提交后补查一次，避免启动时反查与提交竞态。
  private restoreDetailPending: boolean = false
  private restoreDetailLatitude: number = 0
  private restoreDetailLongitude: number = 0
  // 启动恢复为地球 + GPS 自动跟随模式时，在首帧提交后静默检查一次位移（Plan 2）。
  private restoreAutoRefreshPending: boolean = false
  // 切去外星前记住地球的最后观测点（经纬度/海拔/名称/来源），切回地球时完整恢复，不再被外星 0 m 覆盖。
  private hasLastEarthLocation: boolean = false
  private lastEarthName: string = ''
  private lastEarthLatitude: number = 39.9042
  private lastEarthLongitude: number = 116.4074
  private lastEarthAltitude: number = 44
  private lastEarthSource: string = 'named'
  private lastEarthGpsDetail: string = ''
  // Earth altitude bounds; non-Earth sites keep the offline place value (often 0).
  private static readonly EARTH_ALTITUDE_MIN: number = -500
  private static readonly EARTH_ALTITUDE_MAX: number = 9000
  // 自动定位策略阈值（Plan 1/2/3）：位移 >= 3km 或海拔变化 >= 100m 才静默更新星图；
  // 回前台冷却 10 分钟；前台低功耗监听 5km / 300s。
  private static readonly AUTO_UPDATE_MIN_DISTANCE_M: number = 3000
  private static readonly AUTO_UPDATE_MIN_ALTITUDE_DELTA_M: number = 100
  private static readonly AUTO_REFRESH_COOLDOWN_MS: number = 10 * 60 * 1000
  private static readonly WATCH_DISTANCE_INTERVAL_M: number = 5000
  private static readonly WATCH_TIME_INTERVAL_S: number = 300

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

  // 设备定位（GPS：隐私门禁 → 权限 → 快速首帧定位 → setLocation → 若缺海拔再静默精修）。
  // 4 处门禁（初始 + 权限后 + 定位后）经 hooks；权限/定位经 LocationPort。
  async useDeviceLocation(): Promise<void> {
    // GPS fixes and GNSS altitude are Earth-only. Other bodies must use the
    // offline place altitude (usually 0).
    if (this.sessionToolStore.observerPlanet !== 'Earth') return
    if (this.deviceLocationRequestInProgress || !this.hooks.privacyAllowed() ||
      !this.hooks.inForeground() || !this.hooks.hasPrivacyConsent()) return
    this.deviceLocationRequestInProgress = true
    this.pickerStore.deviceLocating = true
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
      // 优先走快速融合定位（PRIORITY_LOCATING_SPEED，~0.4-1s 响应），避免室内在 PRIORITY_ACCURACY 下干等 10 秒。
      let current: LocationFix
      if (this.locationPort.getQuickCurrentLocation !== undefined) {
        try {
          current = await this.locationPort.getQuickCurrentLocation()
        } catch (_quickErr) {
          current = await this.locationPort.getCurrentLocation()
        }
      } else {
        current = await this.locationPort.getCurrentLocation()
      }
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
      this.pickerStore.locationPickerStatus = status
      this.pickerStore.locationSource = 'gps'
      this.lastSilentRefreshAt = Date.now()
      // Name enrichment runs in parallel with the observer update; a slow or
      // failed reverse-geocode must not delay the GPS fix.
      const nameRequestId = ++this.gpsNameRequestId
      this.pickerStore.gpsPlaceDetail = ''
      // Commit coordinates once via setLocation -> commitLocation (avoid double map move).
      this.setLocation(I18n.t('m_current_location'), current.latitude, current.longitude, altitude, 'Earth', false, 'gps')
      void this.resolveGpsPlaceName(current.latitude, current.longitude, nameRequestId)
      this.pickerStore.locationPickMode = 'map'
      this.pickerStore.hierContinent = ''
      this.pickerStore.hierCountry = ''
      this.pickerStore.hierRegion = ''
      this.pickerStore.hierCity = ''
      // 如果快速定位未返回有效 GNSS 海拔，静默在后台补一次高精度 GNSS 海拔精修（不阻塞 UI、不转圈）。
      if (this.gpsAltitudeUnavailable && this.locationPort.getQuickCurrentLocation !== undefined) {
        const refineId = ++this.altitudeRefineRequestId
        void this.refineGpsAltitudeInBackground(refineId)
      }
    } catch (err) {
      const errMsg: string = err instanceof Error ? err.message : JSON.stringify(err)
      hilog.warn(0x0000, 'StellariumArkUI', 'device location failed: %{public}s', errMsg)
      this.pickerStore.locationPickerStatus = I18n.t('m_gps_unavailable')
    } finally {
      this.deviceLocationRequestInProgress = false
      this.pickerStore.deviceLocating = false
    }
  }

  // 快速定位若缺少垂直海拔，后台静默做一次高精度 GNSS 补查；只有拿到有效海拔且仍在 GPS 自动跟随模式时才更新。
  private async refineGpsAltitudeInBackground(requestId: number): Promise<void> {
    try {
      const accurate = await this.locationPort.getCurrentLocation()
      if (requestId !== this.altitudeRefineRequestId) return
      if (!this.isGpsAutoTrackEligible()) return
      if (accurate.altitudeAccuracy === undefined || accurate.altitudeAccuracy <= 0 || !Number.isFinite(accurate.altitude)) return
      const dist = LocationController.distanceMeters(
        this.pickerStore.locationPickerLatitude, this.pickerStore.locationPickerLongitude,
        accurate.latitude, accurate.longitude)
      const altDelta = Math.abs(Math.round(accurate.altitude) - this.pickerStore.locationPickerAltitude)
      if (dist >= 50 || altDelta >= 5) {
        this.gpsAltitudeUnavailable = false
        this.setLocation(I18n.t('m_current_location'), accurate.latitude, accurate.longitude, accurate.altitude, 'Earth', true, 'gps')
      }
    } catch (_err) {
      // 室内无 GNSS 信号属正常现象，静默保留快速定位结果即可。
    }
  }

  // Plan 1 门禁：仅在「地球 + GPS 自动跟随模式 + 隐私已同意 + 前台」下允许自动位置更新。
  // 用户一旦手动选了城市/地图点或切离地球，自动跟踪立刻停止，绝不覆盖手动位置。
  private isGpsAutoTrackEligible(): boolean {
    return this.sessionToolStore.observerPlanet === 'Earth' &&
      this.pickerStore.locationSource === 'gps' &&
      this.hooks.privacyAllowed() &&
      this.hooks.inForeground() &&
      this.hooks.hasPrivacyConsent()
  }

  // 球面 Haversine 距离（米），用于判断位移是否超过 3 km 阈值。
  private static distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const toRad = Math.PI / 180
    const dLat = (lat2 - lat1) * toRad
    const dLon = (lon2 - lon1) * toRad
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2)
    return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)))
  }

  // Plan 2：冷启动恢复后 / 应用切回前台时静默检测位置变化。
  // 绝不弹权限框（先 checkAccessTokenSync）；10 分钟冷却；仅位移 >= 3km 或有效海拔差 >= 100m 时更新。
  async refreshLocationSilentlyIfMoved(reason: 'startup' | 'foreground'): Promise<void> {
    if (!this.isGpsAutoTrackEligible()) return
    if (this.deviceLocationRequestInProgress || this.silentAutoRefreshInProgress ||
      this.sessionToolStore.observerPlanetPending) return
    const now = Date.now()
    if (reason === 'foreground' && this.lastSilentRefreshAt > 0 &&
      now - this.lastSilentRefreshAt < LocationController.AUTO_REFRESH_COOLDOWN_MS) {
      this.syncForegroundLocationWatch()
      return
    }
    if (this.locationPort.hasPreciseLocationPermission === undefined ||
      !this.locationPort.hasPreciseLocationPermission()) {
      return
    }
    this.silentAutoRefreshInProgress = true
    this.lastSilentRefreshAt = now
    try {
      const fix = this.locationPort.getQuickCurrentLocation !== undefined
        ? await this.locationPort.getQuickCurrentLocation()
        : await this.locationPort.getCurrentLocation()
      if (!this.isGpsAutoTrackEligible() || this.sessionToolStore.observerPlanetPending) return
      this.applyAutoTrackedFixIfMoved(fix, reason)
    } catch (_err) {
      // 静默刷新失败不打扰用户，保留上次已持久化位置。
    } finally {
      this.silentAutoRefreshInProgress = false
      this.syncForegroundLocationWatch()
    }
  }

  // Plan 3：前台低功耗大位移监听（5km / 300s）。后台、离开地球或切手动位置时立刻注销，零后台耗电。
  syncForegroundLocationWatch(): void {
    if (this.locationPort.startLocationWatch === undefined || this.locationPort.stopLocationWatch === undefined) return
    const shouldWatch = this.isGpsAutoTrackEligible() &&
      this.locationPort.hasPreciseLocationPermission !== undefined &&
      this.locationPort.hasPreciseLocationPermission()
    if (!shouldWatch) {
      this.stopForegroundLocationWatch()
      return
    }
    if (this.foregroundWatchActive) return
    this.foregroundWatchActive = true
    this.locationPort.startLocationWatch(
      LocationController.WATCH_DISTANCE_INTERVAL_M,
      LocationController.WATCH_TIME_INTERVAL_S,
      (fix: LocationFix) => {
        if (!this.isGpsAutoTrackEligible() || this.sessionToolStore.observerPlanetPending) return
        this.applyAutoTrackedFixIfMoved(fix, 'watch')
      }
    )
    hilog.info(0x0000, 'StellariumArkUI', '[gps] foreground location watch started (5km/300s)')
  }

  stopForegroundLocationWatch(): void {
    if (!this.foregroundWatchActive) return
    this.foregroundWatchActive = false
    if (this.locationPort.stopLocationWatch !== undefined) {
      this.locationPort.stopLocationWatch()
    }
    hilog.info(0x0000, 'StellariumArkUI', '[gps] foreground location watch stopped')
  }

  // 宿主生命周期通知：切后台立即停监听；回前台时若处于地球 GPS 跟随模式则静默校验一次并恢复监听。
  onApplicationForegroundChanged(foreground: boolean): void {
    if (!foreground) {
      this.stopForegroundLocationWatch()
      return
    }
    if (this.isGpsAutoTrackEligible()) {
      void this.refreshLocationSilentlyIfMoved('foreground')
    }
  }

  private applyAutoTrackedFixIfMoved(fix: LocationFix, reason: string): void {
    if (!Number.isFinite(fix.latitude) || !Number.isFinite(fix.longitude)) return
    const distM = LocationController.distanceMeters(
      this.pickerStore.locationPickerLatitude, this.pickerStore.locationPickerLongitude,
      fix.latitude, fix.longitude)
    const hasValidAlt = fix.altitudeAccuracy !== undefined && fix.altitudeAccuracy > 0 && Number.isFinite(fix.altitude)
    const altDeltaM = hasValidAlt ? Math.abs(Math.round(fix.altitude) - this.pickerStore.locationPickerAltitude) : 0
    if (distM < LocationController.AUTO_UPDATE_MIN_DISTANCE_M &&
      altDeltaM < LocationController.AUTO_UPDATE_MIN_ALTITUDE_DELTA_M) {
      return
    }
    const nextAlt = hasValidAlt ? fix.altitude : this.pickerStore.locationPickerAltitude
    this.gpsAltitudeUnavailable = !hasValidAlt && this.pickerStore.locationPickerAltitude === 0
    hilog.info(0x0000, 'StellariumArkUI',
      '[gps] auto-update(%{public}s) moved %{public}dm altDelta=%{public}dm',
      reason, Math.round(distM), Math.round(altDeltaM))
    const nameRequestId = ++this.gpsNameRequestId
    this.pickerStore.gpsPlaceDetail = ''
    this.setLocation(I18n.t('m_current_location'), fix.latitude, fix.longitude, nextAlt, 'Earth', true, 'gps')
    void this.resolveGpsPlaceName(fix.latitude, fix.longitude, nameRequestId)
  }

  // 供全屏地图选完 GPS 蓝点后触发异步行政区反查，与标题栏 GPS 体验统一。
  enrichGpsPlaceName(latitude: number, longitude: number): void {
    const nameRequestId = ++this.gpsNameRequestId
    this.pickerStore.gpsPlaceDetail = ''
    void this.resolveGpsPlaceName(latitude, longitude, nameRequestId)
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
      // Persist the name with the observer record so restart keeps `GPS · <admin division>`.
      void this.saveObserverLocationToStorage()
      if (this.hasLastEarthLocation) {
        this.lastEarthGpsDetail = detail
      }
      // 仅补充行政区名称，坐标未变：coordsChanged=false，不重复触发桌面卡片重算与通知对账！
      this.hooks.setLocationTexts(
        quickLocationLabel('gps',
          this.pickerStore.locationDisplayName(this.pickerStore.locationPickerName), 'Earth', detail) + ' · ' + this.sessionToolStore.observerPlanetLabel('Earth'),
        this.locationStore.formatDegrees(this.pickerStore.locationPickerLatitude, 'N', 'S') + ' / ' +
          this.locationStore.formatDegrees(this.pickerStore.locationPickerLongitude, 'E', 'W'),
        this.pickerStore.locationPickerAltitude.toFixed(0) + ' m',
        false)
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
    const isPlanetChange = targetPlanet !== this.sessionToolStore.observerPlanet
    if (source !== 'gps') {
      // A non-GPS apply invalidates any in-flight GPS name enrichment or altitude refinement.
      this.gpsNameRequestId += 1
      this.altitudeRefineRequestId += 1
      this.pickerStore.gpsPlaceDetail = ''
      this.stopForegroundLocationWatch()
    }
    // Earth altitude is editable in the panel; keep it in a sane range. Other
    // bodies keep the offline place altitude (often 0).
    const normalizedAltitude = targetPlanet === 'Earth'
      ? Math.max(LocationController.EARTH_ALTITUDE_MIN,
        Math.min(LocationController.EARTH_ALTITUDE_MAX, Math.round(altitude)))
      : altitude
    this.sessionToolStore.observerPlanetPending = true
    if (isPlanetChange) {
      this.sessionToolStore.observerPlanetSwitching = true
      this.sessionToolStore.observerPlanetTarget = targetPlanet
    }
    const complete = (response: StellariumBridgeResponse): void => {
      this.sessionToolStore.observerPlanetPending = false
      this.sessionToolStore.observerPlanetSwitching = false
      this.sessionToolStore.observerPlanetTarget = ''
      if (response.ok !== true) {
        if (!silent) {
          this.hooks.flashHint(I18n.t('loc_apply_failed'))
        }
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
      // setObserverPlanet 回包已含最新坐标/星球/名称，无需再发一次多余的 getObserverInfo 触发二次地图跳动。
      if (this.hooks.setSkyCultureObserverLatitude !== undefined) {
        this.hooks.setSkyCultureObserverLatitude(appliedLat)
      }
      if (!silent) {
        this.locationStore.recordRecentLocation(appliedName, appliedLat, appliedLon, appliedAlt, appliedPlanet)
        this.hooks.flashHint(I18n.t('i0073').replace('%s', this.pickerStore.locationDisplayName(appliedName)))
      }
    }
    this.port.requestWhenReady('setObserverPlanet',
      `${targetPlanet}|${latitude}|${longitude}|${Math.round(normalizedAltitude)}|${name.replace(/\|/g, ' ')}`,
      complete, complete, 0, silent ? 120 : 24, 80)
  }

  private commitLocation(name: string, latitude: number, longitude: number, altitude: number, targetPlanet: string, source: string): void {
    const planetChanged = targetPlanet !== this.sessionToolStore.observerPlanet
    const status = source === 'gps' && this.gpsAltitudeUnavailable
      ? I18n.t('m_gps_altitude_unavailable') : I18n.t('m_synced_to_sky')
    this.pickerStore.setPickerLocation(name, latitude, longitude, altitude, status)
    this.gpsAltitudeUnavailable = false
    this.pickerStore.locationSource = source
    if (targetPlanet === 'Earth') {
      this.hasLastEarthLocation = true
      this.lastEarthName = name
      this.lastEarthLatitude = latitude
      this.lastEarthLongitude = longitude
      this.lastEarthAltitude = altitude
      this.lastEarthSource = source
      this.lastEarthGpsDetail = source === 'gps' ? this.pickerStore.gpsPlaceDetail : ''
    }
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
    const planetDisplay = this.sessionToolStore.observerPlanetLabel(targetPlanet)
    // 位置变了，位置面板的今晚天象（月出/日落/行星可见性）必须按新坐标重算。
    this.hooks.refreshTonightData()
    this.hooks.setLocationTexts(
        quickLocationLabel(source, this.pickerStore.locationDisplayName(name), targetPlanet,
          source === 'gps' ? this.pickerStore.gpsPlaceDetail : '') + ' · ' + planetDisplay,
      this.locationStore.formatDegrees(latitude, 'N', 'S') + ' / ' + this.locationStore.formatDegrees(longitude, 'E', 'W'),
      altitude.toFixed(0) + ' m',
      true)
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
    // Plan 1 & 3：仅在「地球 + GPS 模式」下维持前台低功耗大位移监听；切手动位置或离地立刻停止。
    if (targetPlanet === 'Earth' && source === 'gps') {
      if (this.restoreAutoRefreshPending) {
        this.restoreAutoRefreshPending = false
        void this.refreshLocationSilentlyIfMoved('startup')
      } else {
        this.syncForegroundLocationWatch()
      }
    } else {
      this.restoreAutoRefreshPending = false
      this.stopForegroundLocationWatch()
    }
  }

  // 切换观测星球（本 store 只读 observerPlanet，写经 hooks）。
  // 切离地球前记住地球坐标与海拔；切回地球时完整恢复，避免被外星 0 m 覆盖。
  setObserverPlanet(name: string): void {
    if (name === this.sessionToolStore.observerPlanet) return
    if (this.sessionToolStore.observerPlanet === 'Earth') {
      this.hasLastEarthLocation = true
      this.lastEarthName = this.pickerStore.locationPickerName
      this.lastEarthLatitude = this.pickerStore.locationPickerLatitude
      this.lastEarthLongitude = this.pickerStore.locationPickerLongitude
      this.lastEarthAltitude = this.pickerStore.locationPickerAltitude
      this.lastEarthSource = this.pickerStore.locationSource
      this.lastEarthGpsDetail = this.pickerStore.gpsPlaceDetail
    }
    if (name === 'Earth' && this.hasLastEarthLocation) {
      this.pickerStore.gpsPlaceDetail = this.lastEarthSource === 'gps' ? this.lastEarthGpsDetail : ''
      this.setLocation(this.lastEarthName, this.lastEarthLatitude, this.lastEarthLongitude,
        this.lastEarthAltitude, 'Earth', false, this.lastEarthSource)
      return
    }
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
      // 没有持久化观测点时引擎仍在地球；仍需把记住的地球地景应用到默认地景之后。
      this.requestSavedEarthLandscapeRestore()
      return
    }
    let rec: ObserverLocationRecord | undefined = undefined
    try {
      rec = JSON.parse(json) as ObserverLocationRecord
    } catch (e) {
      this.requestSavedEarthLandscapeRestore()
      return
    }
    if (rec === undefined || !Number.isFinite(rec.latitude) || !Number.isFinite(rec.longitude)) {
      this.requestSavedEarthLandscapeRestore()
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
    this.restoreAutoRefreshPending = source === 'gps' && planet === 'Earth'
    this.restoreDetailLatitude = rec.latitude
    this.restoreDetailLongitude = rec.longitude
    hilog.info(0x0000, 'StellariumArkUI', '[location] restoring persisted observer location')
    this.setLocation(name, rec.latitude, rec.longitude, restoredAltitude, planet, true, source)
    // 非地球记录会在随后的 setObserverPlanet 中由自动匹配覆盖，这里无需判断 planet。
    this.requestSavedEarthLandscapeRestore()
  }

  // 启动兜底：引擎已加载默认地景（盖兰）后，应用用户记住的地球地景。
  // 命令自身会判断当前是否在地球；无记录或记录损坏时也安全。
  private requestSavedEarthLandscapeRestore(): void {
    this.port.requestWhenReady('restoreSavedEarthLandscape', '', () => {})
  }
}
