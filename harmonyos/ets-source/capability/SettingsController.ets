// 设置「配置回读」控制器：设置面板打开 / 保存视角后从引擎回读配置，8 连发 requestInteractive
// （日期格式 / 时间格式 / 距离单位 / 抖动模式 / 导航 / 星历 / 信息 / 时间设置）。
//
// 依赖 CommandPort、TimeSettingsStore（本域 configDateFormat / configTimeFormat）与
// TimeSettingsHostHooks 具名 setter（其余跨域字段；控制器不持有他域 store）。
//
// 边界：本控制器仅为「配置回读」IO 加载器，不承载跨域设置动作分派 —— 跨域动作仍留各 store / 宿主。
// 不 import UI/NAPI，桥经 CommandPort。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { TimeSettingsStore } from '../state/TimeSettingsStore'

// 宿主 → SettingsController 回注（控制器不持有他域 store，跨域写入经具名 setter）。
export interface TimeSettingsHostHooks {
  // ViewSettingsStore
  setUseMetricUnits(value: boolean): void
  setConfigDitheringMode(mode: string): void
  setAutoZoomResets(value: boolean): void
  // NavigationSettingsStore
  setNavigationMouseEnabled(value: boolean): void
  setNavigationMouseZoomEnabled(value: boolean): void
  setNavigationMoveKeysEnabled(value: boolean): void
  setNavigationZoomKeysEnabled(value: boolean): void
  setNavigationGravityLabelsEnabled(value: boolean): void
  setNavigationStartupFov(value: number): void
  setNavigationStartupAzimuth(value: number): void
  setNavigationStartupAltitude(value: number): void
  setNavigationMaxFov(value: number): void
  // EphemerisStore
  setEphemerisAvailability(de430Available: boolean, de431Available: boolean, de440Available: boolean, de441Available: boolean): void
  setEphemerisActive(de430Active: boolean, de431Active: boolean, de440Active: boolean, de441Active: boolean): void
  // InfoWindowStore
  informationMode(): string
  setInformationMode(mode: string): void
  setInformationCustomMask(mask: number): void
  // 与宿主动作共享的助手（经注入调用）
  applySelectedInfoMode(mode: string): void
  applyTimeSettings(response: StellariumBridgeResponse): void
}

export class SettingsController {
  private port: CommandPort | null = null
  private store: TimeSettingsStore
  private hooks: TimeSettingsHostHooks | null = null

  constructor(port: CommandPort, store: TimeSettingsStore, hooks: TimeSettingsHostHooks) {
    this.port = port
    this.store = store
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  // 设置面板配置回读：时间格式字段写本域 store，其余 store 字段经 hooks 具名 setter 写入。
  loadConfigurationSettings(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const hooks = this.hooks
    if (hooks === null) {
      return
    }
    port.requestInteractive('getDateFormat', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.format !== undefined) { this.store.configDateFormat = r.format as string }
    })
    port.requestInteractive('getTimeFormat', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.format !== undefined) { this.store.configTimeFormat = r.format as string }
    })
    port.requestInteractive('getConfigString', 'astronomy/flag_use_km_for_distance', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.value !== undefined) {
        hooks.setUseMetricUnits((r.value as string).toLowerCase() === 'true' || r.value === '1')
      }
    })
    port.requestInteractive('getDitheringMode', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.mode !== undefined) { hooks.setConfigDitheringMode(r.mode as string) }
    })
    port.requestInteractive('getNavigationSettings', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) return
      if (r.mouseNavigation !== undefined) hooks.setNavigationMouseEnabled(r.mouseNavigation === true)
      if (r.mouseZooming !== undefined) hooks.setNavigationMouseZoomEnabled(r.mouseZooming === true)
      if (r.moveKeys !== undefined) hooks.setNavigationMoveKeysEnabled(r.moveKeys === true)
      if (r.zoomKeys !== undefined) hooks.setNavigationZoomKeysEnabled(r.zoomKeys === true)
      if (r.gravityLabels !== undefined) hooks.setNavigationGravityLabelsEnabled(r.gravityLabels === true)
      if (r.autoZoomResets !== undefined) hooks.setAutoZoomResets(r.autoZoomResets === true)
      if (r.startupFov !== undefined) hooks.setNavigationStartupFov(Number(r.startupFov))
      if (r.startupAzimuth !== undefined) hooks.setNavigationStartupAzimuth(Number(r.startupAzimuth))
      if (r.startupAltitude !== undefined) hooks.setNavigationStartupAltitude(Number(r.startupAltitude))
      if (r.maxFov !== undefined) hooks.setNavigationMaxFov(Number(r.maxFov))
    })
    port.requestInteractive('getEphemerisSettings', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) return
      hooks.setEphemerisAvailability(r.de430Available === true, r.de431Available === true, r.de440Available === true, r.de441Available === true)
      hooks.setEphemerisActive(r.de430Active === true, r.de431Active === true, r.de440Active === true, r.de441Active === true)
    })
    port.requestInteractive('getInformationSettings', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) return
      hooks.setInformationMode(r.infoMode ?? hooks.informationMode())
      if (r.customInfoMask !== undefined) hooks.setInformationCustomMask(Number(r.customInfoMask))
      hooks.applySelectedInfoMode(hooks.informationMode())
    })
    port.requestInteractive('getTimeSettings', '', (r: StellariumBridgeResponse) => {
      hooks.applyTimeSettings(r)
    })
  }
}
