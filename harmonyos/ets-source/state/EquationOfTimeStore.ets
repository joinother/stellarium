import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 时间方程（均时差）域状态 store：面板组件以 @ObjectLink 订阅。
// 本 store 自持 CommandPort 与加载器 loadEquationOfTime；写回动作 setEquationOfTime
// （含 equationOfTimeMutationId 乐观回滚）仍在宿主，由宿主负责与引擎同步。
@Observed
export class EquationOfTimeStore {
  equationOfTimeEnabled: boolean = false
  equationOfTimeMsFormat: boolean = false
  equationOfTimeInverted: boolean = false
  equationOfTimeStartup: boolean = false
  equationOfTimeMinutes: number = 0
  equationOfTimeLoading: boolean = false
  equationOfTimeStatus: string = ''

  // —— 桥注入（本 store 自持 loadEquationOfTime） ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（无并发抑制需求）；预留以统一加载器约定。
  private seq: number = 0
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

  // 均时差面板：桥查询当前开关与显示值，按重试档 0 / 100 / 15 调用并处理 onFailure。
  loadEquationOfTime(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    this.equationOfTimeLoading = true
    port.requestWhenReady('getEquationOfTime', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.equationOfTimeStatus = I18n.t('plugin_status_unavailable')
      } else {
        this.equationOfTimeEnabled = r.enabled === true
        this.equationOfTimeMsFormat = r.msFormat === true
        this.equationOfTimeInverted = r.inverted === true
        this.equationOfTimeStartup = r.enableAtStartup === true
        this.equationOfTimeMinutes = typeof r.minutes === 'number' ? r.minutes : 0
        this.equationOfTimeStatus = ''
      }
      this.equationOfTimeLoading = false
      this.notifyChanged()
    }, () => {
      this.equationOfTimeLoading = false
      this.equationOfTimeStatus = I18n.t('plugin_status_unavailable')
      this.notifyChanged()
    }, 0, 100, 15)
  }
}
