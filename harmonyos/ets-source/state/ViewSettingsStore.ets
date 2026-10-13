// 「视图交互偏好」状态簇：自动重置缩放、距离单位、锁定视角、竖直限位、地平线平直，
// 以及 configDitheringMode（抖动/渲染质量档）、liveMode（实时模式）、uiLocked（界面锁定）。
// 消费方（SettingsPanel / SettingsQuickLegacyPanel / UnifiedObjectDetailCard 等）以
// @ObjectLink / @Prop 观察。自持 CommandPort，跨 store 回滚与宿主 @State 写入经
// ViewSettingsHostHooks 注入。均为标量，只做整体赋值，无原地变更。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → ViewSettingsStore 回注（store 不触碰 UI 与 UI 状态）。
export interface ViewSettingsHostHooks {
  flashHint(text: ResourceStr): void
  // 宿主 @State currentProjection（setProjection 回包成功后写；StartupBridge 亦经宿主写）。
  setCurrentProjection(name: string): void
  // 跨 store 回滚：timeSettingsStore.loadConfigurationSettings()（抖动 / 距离单位失败分支）。
  reloadConfigurationSettings(): void
  // setProjectionType 被拒时的 hilog（store 不 import @ohos.hilog）。
  logProjectionError(name: string, error: string): void
}

@Observed
export class ViewSettingsStore {
  autoZoomResets: boolean = false
  useMetricUnits: boolean = true
  viewLock: boolean = false
  verticalClamp: boolean = true
  flatHorizon: boolean = true
  configDitheringMode: string = 'Color888'
  liveMode: boolean = true
  uiLocked: boolean = false

  // —— 桥 / 宿主回注 ——
  private port: CommandPort | null = null
  private hooks: ViewSettingsHostHooks | null = null

  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachHooks(hooks: ViewSettingsHostHooks): void {
    this.hooks = hooks
  }

  private ensurePort(): CommandPort | null {
    return this.port
  }

  // 抖动 / 渲染质量档写回：失败时经 hooks.reloadConfigurationSettings 回滚。
  setConfigurationDithering(value: string): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    port.requestInteractive('setDitheringMode', value.toLowerCase(), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.configDitheringMode = value
        hooks.flashHint('渲染质量已更新')
      } else {
        hooks.flashHint(r.error ?? I18n.t('msg_apply_failed'))
        hooks.reloadConfigurationSettings()
      }
    })
  }

  // 距离单位写回：失败时经 hooks.reloadConfigurationSettings 回滚。
  setDistanceUnit(useMetric: boolean): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    port.requestInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=' + (useMetric ? 'true' : 'false'), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.useMetricUnits = useMetric
      } else {
        hooks.flashHint(r.error ?? I18n.t('msg_apply_failed'))
        hooks.reloadConfigurationSettings()
      }
    })
  }

  // 视场标记设置（薄桥）。
  setFovMarkerSetting(setting: string, value: number): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    port.requestInteractive('setFovMarkerSetting', setting + '|' + value.toFixed(1), () => {})
  }

  // 投影方式写回：回包成功后写宿主 @State（经 hooks）并提示。
  setProjection(name: string): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    port.requestInteractive('setProjectionType', name, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        hooks.setCurrentProjection(name)
        hooks.flashHint(I18n.projectionName(name))
      } else {
        hooks.logProjectionError(name, r.error ?? '')
        hooks.flashHint(I18n.t('msg_apply_failed'))
      }
    })
  }
}
