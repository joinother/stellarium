import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 古天文辅助线（archaeoLines）域状态：18 个字段（载入态与提示、总开关与线宽、13 个线条
// 开关、当前行星档位）均为 ArchaeoLinesPanel 的入参，由面板以 @ObjectLink 订阅。
// 写回动作仍由宿主 setArchaeoLineSetting / applyArchaeoLineSetting 驱动，面板只回注回调；
// 本 store 自持 loadArchaeoLines 加载器与 archaeoLineSettingValue 取值，并持有 CommandPort 注入。
//
// 约束：所有更新必须是"字段整体赋值"。本域无数组/对象字段，不存在原地 push/splice 或
// `this.<f>.<prop> =` 的写法（@ObjectLink 观测不到原地变更）。
@Observed
export class ArchaeoStore {
  archaeoLoading: boolean = false
  archaeoStatus: string = ''
  archaeoLinesEnabled: boolean = false
  archaeoEquinox: boolean = false
  archaeoSolstices: boolean = false
  archaeoCrossquarters: boolean = false
  archaeoMajorStandstills: boolean = false
  archaeoMinorStandstills: boolean = false
  archaeoPolarCircles: boolean = false
  archaeoZenithPassage: boolean = false
  archaeoNadirPassage: boolean = false
  archaeoSelectedObject: boolean = false
  archaeoSelectedObjectAzimuth: boolean = false
  archaeoSelectedObjectHourAngle: boolean = false
  archaeoCurrentSun: boolean = false
  archaeoCurrentMoon: boolean = false
  archaeoCurrentPlanet: number = 0
  archaeoLineWidth: number = 1

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（写回动作的 archaeoMutationId 属宿主）；seq 预留以统一约定。
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

  // 古天文辅助线面板：桥查询全部开关与线宽（重试档 0 / 100 / 15）。
  loadArchaeoLines(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    this.archaeoLoading = true
    port.requestWhenReady('getArchaeoLines', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.archaeoStatus = I18n.t('plugin_status_unavailable')
      } else {
        this.archaeoLinesEnabled = r.enabled === true
        this.archaeoLineWidth = typeof r.lineWidth === 'number' ? r.lineWidth : 1
        this.archaeoEquinox = r.equinox === true
        this.archaeoSolstices = r.solstices === true
        this.archaeoCrossquarters = r.crossquarters === true
        this.archaeoMajorStandstills = r.majorStandstills === true
        this.archaeoMinorStandstills = r.minorStandstills === true
        this.archaeoPolarCircles = r.polarCircles === true
        this.archaeoZenithPassage = r.zenithPassage === true
        this.archaeoNadirPassage = r.nadirPassage === true
        this.archaeoSelectedObject = r.selectedObject === true
        this.archaeoSelectedObjectAzimuth = r.selectedObjectAzimuth === true
        this.archaeoSelectedObjectHourAngle = r.selectedObjectHourAngle === true
        this.archaeoCurrentSun = r.currentSun === true
        this.archaeoCurrentMoon = r.currentMoon === true
        this.archaeoCurrentPlanet = typeof r.currentPlanet === 'number' ? r.currentPlanet : 0
        this.archaeoStatus = ''
      }
      this.archaeoLoading = false
      this.notifyChanged()
    }, () => {
      this.archaeoLoading = false
      this.archaeoStatus = I18n.t('plugin_status_unavailable')
      this.notifyChanged()
    }, 0, 100, 15)
  }

  // 古天文线设置项 → CLI 取值字符串。
  archaeoLineSettingValue(setting: string): string {
    switch (setting) {
      case 'enabled': return this.archaeoLinesEnabled ? '1' : '0'
      case 'equinox': return this.archaeoEquinox ? '1' : '0'
      case 'solstices': return this.archaeoSolstices ? '1' : '0'
      case 'crossquarters': return this.archaeoCrossquarters ? '1' : '0'
      case 'majorStandstills': return this.archaeoMajorStandstills ? '1' : '0'
      case 'minorStandstills': return this.archaeoMinorStandstills ? '1' : '0'
      case 'polarCircles': return this.archaeoPolarCircles ? '1' : '0'
      case 'zenithPassage': return this.archaeoZenithPassage ? '1' : '0'
      case 'nadirPassage': return this.archaeoNadirPassage ? '1' : '0'
      case 'selectedObject': return this.archaeoSelectedObject ? '1' : '0'
      case 'selectedObjectAzimuth': return this.archaeoSelectedObjectAzimuth ? '1' : '0'
      case 'selectedObjectHourAngle': return this.archaeoSelectedObjectHourAngle ? '1' : '0'
      case 'currentSun': return this.archaeoCurrentSun ? '1' : '0'
      case 'currentMoon': return this.archaeoCurrentMoon ? '1' : '0'
      case 'currentPlanet': return ['none', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn'][this.archaeoCurrentPlanet] ?? 'none'
      case 'lineWidth': return this.archaeoLineWidth.toString()
      default: return ''
    }
  }
}
