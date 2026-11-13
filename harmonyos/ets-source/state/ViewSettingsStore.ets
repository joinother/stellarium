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
  // 角度显示切换后重取选中天体资料，让已打开的详情卡立即使用新的格式。
  refreshSelectedObject(): void
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
  // TouchPicker acceptance radius; UI offers 66/48 vp presets.
  touchPickRadiusVp: number = 66
  // 与 StelApp.flagUseDecDegreesCoords / flagUseDecDegreesOther 同步。
  // coords/other 采用乐观更新：点击后立即改本地镜像，桥回执再校准；
  // 失败时回退到最后一次确认值，避免 Toggle 视觉状态与引擎状态脱节。
  decimalDegreesCoords: boolean = false
  decimalDegreesOther: boolean = false
  private decimalDegreesConfirmedCoords: boolean = false
  private decimalDegreesConfirmedOther: boolean = false
  private decimalDegreesRequestSeq: number = 0
  private decimalDegreesPending: boolean = false
  // 成功后短暂忽略 getState 快照，避免请求前发出的旧快照把开关顶回去。
  private decimalDegreesAppliedAt: number = 0
  private static readonly DECIMAL_DEGREES_STATE_GUARD_MS: number = 1500

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

  // 引擎 / config.ini 是权威源；getState 回读也走这里，确保确认值同步。
  // 写入请求在途时忽略轮询快照，否则旧快照会把乐观更新顶回旧值。
  syncDecimalDegreesFromState(coords: boolean, other: boolean): void {
    if (this.decimalDegreesPending) return
    if (Date.now() - this.decimalDegreesAppliedAt < ViewSettingsStore.DECIMAL_DEGREES_STATE_GUARD_MS) return
    this.decimalDegreesCoords = coords
    this.decimalDegreesOther = other
    this.decimalDegreesConfirmedCoords = coords
    this.decimalDegreesConfirmedOther = other
  }

  private syncDecimalDegrees(coords: boolean, other: boolean): void {
    this.decimalDegreesCoords = coords
    this.decimalDegreesOther = other
    this.decimalDegreesConfirmedCoords = coords
    this.decimalDegreesConfirmedOther = other
  }

  // 坐标 / 其它角度值是否使用十进制度。乐观更新，回执后校准；只让最新一次
  // 请求的失败生效，避免快速连点时旧回执把两个开关互相覆盖。
  setDecimalDegrees(coords: boolean, other: boolean): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    const seq = ++this.decimalDegreesRequestSeq
    this.decimalDegreesPending = true
    this.decimalDegreesCoords = coords
    this.decimalDegreesOther = other
    const revert = (): void => {
      if (seq !== this.decimalDegreesRequestSeq) return
      this.decimalDegreesPending = false
      this.decimalDegreesCoords = this.decimalDegreesConfirmedCoords
      this.decimalDegreesOther = this.decimalDegreesConfirmedOther
    }
    const payload = (coords ? '1' : '0') + '|' + (other ? '1' : '0')
    port.requestInteractive('setDecimalDegrees', payload, (r: StellariumBridgeResponse) => {
      if (seq !== this.decimalDegreesRequestSeq) return
      if (r.ok !== true) {
        revert()
        hooks.flashHint(r.error ?? I18n.t('msg_apply_failed'))
        return
      }
      this.decimalDegreesPending = false
      this.decimalDegreesAppliedAt = Date.now()
      this.syncDecimalDegrees(r.decimalDegreesCoords === true, r.decimalDegreesOther === true)
      hooks.refreshSelectedObject()
    }, () => {
      revert()
      hooks.flashHint(I18n.t('msg_apply_failed'))
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
