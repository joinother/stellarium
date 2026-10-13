// 「视图导航」设置页（设置 > 视图导航，configTab 7）的状态簇。
//
// 持有鼠标/键盘导航与缩放开关、重力标签，以及启动视场、启动朝向与最大视场角；均为持久化设置，
// 被 SettingsPanel 以 @ObjectLink 观察。setNavigationBoolean / setNavigationMaxFov 两个桥动作
// 在本 store：桥经 CommandPort，autoZoomResets 分支写 ViewSettingsStore、UI 提示经
// NavigationSettingsHostHooks 具名回注（store 不 import 他 store / UI）。
//
// 字段均为标量、只做整体赋值，无原地变更。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → NavigationSettingsStore 回注。
export interface NavigationSettingsHostHooks {
  flashHint(text: ResourceStr): void
  // ViewSettingsStore.autoZoomResets（setNavigationBoolean 的 autoZoomResets 分支）。
  setAutoZoomResets(value: boolean): void
}

@Observed
export class NavigationSettingsStore {
  navigationMouseEnabled: boolean = true
  navigationMouseZoomEnabled: boolean = true
  navigationMoveKeysEnabled: boolean = true
  navigationZoomKeysEnabled: boolean = true
  navigationGravityLabelsEnabled: boolean = false
  navigationStartupFov: number = 60
  navigationStartupAzimuth: number = 0
  navigationStartupAltitude: number = 45
  navigationMaxFov: number = 180

  // —— 桥 / 宿主回注 ——
  private port: CommandPort | null = null
  private hooks: NavigationSettingsHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口；字段赋值即驱动宿主重绘（store 无 publish* 发布点）。
  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachHooks(hooks: NavigationSettingsHostHooks): void {
    this.hooks = hooks
  }

  private ensurePort(): CommandPort | null {
    return this.port
  }

  // 导航布尔设置写回（autoZoomResets 经 hooks 写 ViewSettingsStore，提示经 hooks.flashHint，桥经 port）。
  setNavigationBoolean(setting: string, enabled: boolean): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    port.requestInteractive('setNavigationSetting', setting + '|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        hooks.flashHint(I18n.t('msg_apply_failed'))
        return
      }
      if (setting === 'mouseNavigation') this.navigationMouseEnabled = enabled
      else if (setting === 'mouseZooming') this.navigationMouseZoomEnabled = enabled
      else if (setting === 'moveKeys') this.navigationMoveKeysEnabled = enabled
      else if (setting === 'zoomKeys') this.navigationZoomKeysEnabled = enabled
      else if (setting === 'gravityLabels') this.navigationGravityLabelsEnabled = enabled
      else if (setting === 'autoZoomResets') hooks.setAutoZoomResets(enabled)
    })
  }

  // 最大视场角（钳制到 1..360 后写回）。
  setNavigationMaxFov(value: number): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    const maxFov = Math.max(1, Math.min(360, Math.round(value)))
    port.requestInteractive('setNavigationSetting', 'maxFov|' + maxFov.toString(), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.navigationMaxFov = maxFov
        hooks.flashHint(I18n.t('settings_view_max_fov_updated'))
      } else {
        hooks.flashHint(I18n.t('msg_apply_failed'))
      }
    })
  }
}
