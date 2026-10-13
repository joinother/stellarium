import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 航海星（navStars）域的状态。
//
// 持有请求态（navStarsLoading / navStarsStatus）、总开关与星表选择、计数与各项显示开关，
// 被 NavStarsPanel 以 @ObjectLink 观察。加载器 loadNavStars 与写方 setNavStarsSetting
// （含助手 applyNavStarsSetting）自持 CommandPort 与两个请求序号，无 hooks；
// 星表名翻译助手 navStarsSetLabel 仍在组件内（纯函数）。
//
// 两个请求序号语义不同，故不合并：navStarsLoadRequestId 只护 loadNavStars 的并发回包，
// navStarsMutationId 护「动作 + 其后重新载入」的代际。
//
// 所有更新均为字段整体赋值（navStarsSetKeys 只整体赋值 `= r.setKeys ?? []`，无原地变更）。
@Observed
export class NavStarsStore {
  navStarsLoading: boolean = false
  navStarsStatus: string = ''
  navStarsEnabled: boolean = false
  navStarsSetKey: string = 'AngloAmerican'
  navStarsSetDescription: string = ''
  navStarsSetKeys: string[] = []
  navStarsCount: number = 0
  navStarsHighlight: boolean = false
  navStarsLimitInfo: boolean = false
  navStarsUpperLimb: boolean = false
  navStarsTabulated: boolean = false
  navStarsExtraDecimals: boolean = false
  navStarsUseUtc: boolean = false
  navStarsStartup: boolean = false

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 两个请求序号见文件头说明。
  private navStarsLoadRequestId: number = 0
  private navStarsMutationId: number = 0
  private onChanged: (() => void) | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
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

  // 航海星面板：桥查询当前设置与星表（重试档 0/100/15，onFailure 由第 4 参传入）。
  loadNavStars(showLoading: boolean = true): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const requestId = ++this.navStarsLoadRequestId
    const mutationId = this.navStarsMutationId
    if (showLoading) this.navStarsLoading = true
    port.requestWhenReady('getNavStars', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.navStarsLoadRequestId) return
      this.navStarsLoading = false
      if (mutationId !== this.navStarsMutationId) return
      if (r.ok !== true) {
        this.navStarsStatus = I18n.t('plugin_status_unavailable')
      } else {
        this.navStarsEnabled = r.enabled === true
        this.navStarsSetKey = r.setKey ?? 'AngloAmerican'
        this.navStarsSetDescription = r.setDescription ?? ''
        this.navStarsSetKeys = r.setKeys ?? []
        this.navStarsCount = r.starCount ?? 0
        this.navStarsHighlight = r.highlightWhenVisible === true
        this.navStarsLimitInfo = r.limitInfo === true
        this.navStarsUpperLimb = r.upperLimb === true
        this.navStarsTabulated = r.tabulatedDisplay === true
        this.navStarsExtraDecimals = r.extraDecimals === true
        this.navStarsUseUtc = r.useUtc === true
        this.navStarsStartup = r.enableAtStartup === true
        this.navStarsStatus = ''
      }
    }, () => {
      if (requestId !== this.navStarsLoadRequestId) return
      this.navStarsLoading = false
      this.navStarsStatus = I18n.t('plugin_status_unavailable')
    }, 0, 100, 15)
  }

  // 航海星设置项即时回填（先落本地字段，再等桥回包）。
  applyNavStarsSetting(setting: string, value: string): void {
    const enabled = value === '1' || value.toLowerCase() === 'true'
    if (setting === 'enabled') this.navStarsEnabled = enabled
    else if (setting === 'set') this.navStarsSetKey = value
    else if (setting === 'highlightWhenVisible') this.navStarsHighlight = enabled
    else if (setting === 'limitInfo') this.navStarsLimitInfo = enabled
    else if (setting === 'upperLimb') this.navStarsUpperLimb = enabled
    else if (setting === 'tabulatedDisplay') this.navStarsTabulated = enabled
    else if (setting === 'extraDecimals') this.navStarsExtraDecimals = enabled
    else if (setting === 'useUtc') this.navStarsUseUtc = enabled
    else if (setting === 'enableAtStartup') this.navStarsStartup = enabled
  }

  // 写航海星设置（自增 navStarsMutationId 作废旧代际；set 项成功后重载星表，失败回退重载）。
  setNavStarsSetting(setting: string, value: string): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const mutationId = ++this.navStarsMutationId
    this.applyNavStarsSetting(setting, value)
    port.requestInteractive('setNavStarsSetting', setting + '|' + value, (r: StellariumBridgeResponse) => {
      if (mutationId !== this.navStarsMutationId) return
      if (r.ok === true) {
        if (setting === 'set') this.loadNavStars(false)
      } else {
        this.navStarsStatus = I18n.t('plugin_action_failed')
        this.loadNavStars(false)
      }
    }, () => {
      if (mutationId !== this.navStarsMutationId) return
      this.navStarsStatus = I18n.t('plugin_action_failed')
      this.loadNavStars(false)
    })
  }
}
