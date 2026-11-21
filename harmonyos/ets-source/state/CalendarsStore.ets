// 世界多历法（Calendars 插件）域 store：读取当前星图 JD 对应的 18 种世界历法对照，
// 控制屏幕历法叠加显示，以及按公历/儒略历日期跳转星图时刻。
import { CommandPort } from '../bridge/CommandPort'
import { CalendarRowItem, StellariumBridgeResponse } from '../common/types/StellariumTypes'

@Observed
export class CalendarsStore {
  items: Array<CalendarRowItem> = []
  loading: boolean = false
  error: string = ''
  jd: number = 0
  mjd: number = 0
  rataDie: number = 0
  localTime: string = ''
  overlayEnabled: boolean = false
  selectedCategory: string = 'all'
  private port: CommandPort | null = null
  private seq: number = 0
  private onFlashHint: (msg: string) => void = () => {}
  private onTimeChanged: () => void = () => {}

  bind(port: CommandPort, onFlashHint: (msg: string) => void, onTimeChanged: () => void): void {
    this.port = port
    this.onFlashHint = onFlashHint
    this.onTimeChanged = onTimeChanged
  }

  load(customJd?: number): void {
    if (this.port === null) return
    const reqId = ++this.seq
    this.loading = true
    this.error = ''
    const payload = customJd !== undefined && Number.isFinite(customJd) && customJd > 0
      ? JSON.stringify({ jd: customJd }) : ''
    this.port.requestInteractive('getCalendarsData', payload, (r: StellariumBridgeResponse) => {
      if (reqId !== this.seq) return
      this.loading = false
      if (r.ok === true && Array.isArray(r.calendars)) {
        this.items = r.calendars as Array<CalendarRowItem>
        this.jd = Number(r.jd ?? 0)
        this.mjd = Number(r.mjd ?? 0)
        this.rataDie = Number(r.rataDie ?? 0)
        this.localTime = typeof r.localTime === 'string' ? r.localTime : ''
        this.overlayEnabled = r.overlayEnabled === true
      } else {
        this.error = r.error ?? '世界多历法数据暂不可用，请点刷新重试。'
      }
    }, () => {
      if (reqId !== this.seq) return
      this.loading = false
      this.error = '读取世界多历法超时，请重试。'
    })
  }

  setOverlayEnabled(enabled: boolean): void {
    if (this.port === null) return
    const prev = this.overlayEnabled
    this.overlayEnabled = enabled
    this.port.requestInteractive('setCalendarSetting', 'enabled|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.overlayEnabled = r.overlayEnabled === true
      } else {
        this.overlayEnabled = prev
        this.onFlashHint(r.error ?? '切换历法叠加失败')
      }
    }, () => {
      this.overlayEnabled = prev
    })
  }

  jumpToCalendarDate(mode: string, year: number, month: number, day: number): void {
    if (this.port === null) return
    const yStr = String(year)
    const mStr = month < 10 ? '0' + String(month) : String(month)
    const dStr = day < 10 ? '0' + String(day) : String(day)
    const key = mode === 'julian' ? 'jumpJulian' : 'jumpGregorian'
    this.port.requestInteractive('setCalendarSetting', key + '|' + yStr + '-' + mStr + '-' + dStr, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.onFlashHint('已跳转至 ' + (mode === 'julian' ? '儒略历 ' : '公历 ') + yStr + '-' + mStr + '-' + dStr)
        this.onTimeChanged()
        this.load()
      } else {
        this.onFlashHint(r.error ?? '日期转换失败，请检查年月日范围')
      }
    })
  }

  jumpToNow(): void {
    if (this.port === null) return
    this.port.requestInteractive('triggerAction', 'actionReturn_To_Current_Time', () => {
      this.onTimeChanged()
      this.load()
      this.onFlashHint('已回到当前实时时间')
    })
  }
}
