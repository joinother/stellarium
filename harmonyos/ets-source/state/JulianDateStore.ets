// 儒略日输入域状态 store：持有输入文本与校验态（julianDayInput / modifiedJulianDayInput /
// julianDateEditing / julianDateError / julianCalendarSystem），并自持 julianDateApplyInFlight
// 请求在途标志；面板组件以 @ObjectLink 订阅。
//
// 行为：syncJulianDateFields / applyJulianDateInput / adjustJulianDate 在本 store；桥经
// CommandPort（attachPort 注入）；跨域/UI 两个动作（时间转轴同步、轻量时间读数刷新）经
// JulianDateHostHooks 具名回注（store 不 import UI / 控制器）。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → store 回注：时间转轴同步与时间读数刷新（二者都触碰 UI/控制器，归宿主）。
export interface JulianDateHostHooks {
  // 时间转轴按给定 jd 同步。
  syncWheelFromSimulation(jd: number): void
  // 刷新轻量时间读数。
  refreshSimTimeLight(): void
}

@Observed
export class JulianDateStore {
  julianDayInput: string = ''
  modifiedJulianDayInput: string = ''
  julianDateEditing: boolean = false
  julianDateError: string = ''
  julianCalendarSystem: string = 'gregorian'

  // 请求在途标志：私有，不入可观测语义（防重复提交）。
  private julianDateApplyInFlight: boolean = false
  private port: CommandPort | null = null
  private hooks: JulianDateHostHooks | null = null

  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachHooks(hooks: JulianDateHostHooks): void {
    this.hooks = hooks
  }

  // 按桥回包同步输入字段：编辑中不覆盖用户输入。
  syncJulianDateFields(response: StellariumBridgeResponse, jd: number): void {
    const mjd = response.mjd !== undefined ? Number(response.mjd) : jd - 2400000.5
    this.julianCalendarSystem = response.calendarSystem === 'julian' ? 'julian' : 'gregorian'
    if (!this.julianDateEditing) {
      this.julianDayInput = jd.toFixed(5)
      this.modifiedJulianDayInput = mjd.toFixed(5)
    }
  }

  // 提交输入：校验有限性后经桥写入，失败回填错误；成功同步转轴与时间读数。
  applyJulianDateInput(scale: string): void {
    if (this.julianDateApplyInFlight) { return }
    const port = this.port
    if (port === null) { return }
    const text = (scale === 'mjd' ? this.modifiedJulianDayInput : this.julianDayInput).trim()
    const value = Number(text)
    if (!Number.isFinite(value)) {
      this.julianDateError = I18n.t('julian_date_invalid')
      return
    }
    this.julianDateError = ''
    this.julianDateApplyInFlight = true
    port.requestInteractive('setJulianDate', scale + '|' + value.toString(), (r: StellariumBridgeResponse) => {
      this.julianDateApplyInFlight = false
      if (r.ok !== true || r.jd === undefined) {
        this.julianDateError = r.error ?? I18n.t('julian_date_invalid')
        return
      }
      this.julianDateEditing = false
      this.syncJulianDateFields(r, Number(r.jd))
      const hooks = this.hooks
      if (hooks !== null) {
        hooks.syncWheelFromSimulation(Number(r.jd))
        hooks.refreshSimTimeLight()
      }
    }, (r: StellariumBridgeResponse) => {
      this.julianDateApplyInFlight = false
      this.julianDateError = r.error ?? I18n.t('julian_date_invalid')
    })
  }

  // 翻档：按方向步进 0.00001 后复用 applyJulianDateInput。
  adjustJulianDate(scale: string, direction: number): void {
    const text = scale === 'mjd' ? this.modifiedJulianDayInput : this.julianDayInput
    const value = Number(text)
    if (!Number.isFinite(value)) {
      this.julianDateError = I18n.t('julian_date_invalid')
      return
    }
    const adjusted = value + direction * 0.00001
    if (scale === 'mjd') this.modifiedJulianDayInput = adjusted.toFixed(5)
    else this.julianDayInput = adjusted.toFixed(5)
    this.applyJulianDateInput(scale)
  }
}
