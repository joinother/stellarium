// 位置能力端口：以纯接口提供定位权限申请、当前位置获取与持久化观测点读写语义，
// 使位置域控制器（capability/LocationController）无需 import 定位/权限/preferences 模块。
// 宿主在 aboutToAppear 注入具名实现 HostLocationPort（MainWindowNativeNode.ets）。

// 一次定位结果（对应 geoLocationManager.getCurrentLocation 的 latitude/longitude/altitude；
// altitude 非有限值时由适配器映射为 0）。
export interface LocationFix {
  latitude: number
  longitude: number
  altitude: number
  // 水平精度（米），用于在状态行展示。
  accuracy?: number
  // 垂直精度（米）。0/缺省表示该次定位没有可用的海拔分量（室内/网络定位常见）。
  altitudeAccuracy?: number
}

export interface LocationPort {
  // 申请定位权限（abilityAccessCtrl.requestPermissionsFromUser +
  // APPROXIMATELY_LOCATION / LOCATION）。
  // 'precise' = 精确位置已授权；'approximate' = 仅模糊位置；'denied' = 均未授权。
  // 海拔来自 GNSS，只有精确位置权限可用。
  requestLocationPermissions(): Promise<string>
  // 取当前位置（geoLocationManager.getCurrentLocation：SingleLocationRequest、
  // PRIORITY_ACCURACY、10s 超时；需要精确位置权限才能拿到海拔）。
  getCurrentLocation(): Promise<LocationFix>
  // GPS 定位成功后反查最小行政区名称（Map Kit site.reverseGeocode；失败返回空串）。
  // 仅在 METERED_MAP_APIS_ENABLED 为真时由控制器调用。
  reverseGeocodePlaceName(latitude: number, longitude: number): Promise<string>
  // 读持久化观测点 JSON（@ohos.data.preferences，store 名 LOCATION_STORE，key 'location'；失败返回 ''）。
  readObserverLocation(): Promise<string>
  // 写持久化观测点 JSON（同上；失败只记一条 warn，不抛）。
  writeObserverLocation(json: string): Promise<void>
  // 读/写已保存位置与最近使用 JSON（同一 preferences store，key 'savedLocations'）。
  readSavedLocations(): Promise<string>
  writeSavedLocations(json: string): Promise<void>
}
