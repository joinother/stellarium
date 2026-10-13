import { MeteorShowerItem, MeteorShowersResponse } from '../pages/MainWindowModels'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'

// 流星雨（meteor showers）域的面板状态。
//
// 持有面板开关、活跃流星雨列表与星表元信息，被流星雨面板以 @ObjectLink 观察。
// 加载器 loadMeteorShowers 与写方 setMeteorShowersFlag 自持 CommandPort 与请求序号，
// 写方自增 seq 以作废在途载入。无 hooks。
@Observed
export class MeteorStore {
  msEnabled: boolean = false
  msLabels: boolean = false
  msActiveOnly: boolean = false
  msMarker: boolean = false
  msShowerList: MeteorShowerItem[] = []
  msCatalogVersion: string = ''
  msCatalogName: string = ''
  msCatalogSource: string = ''

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 请求序号：作废在途载入（loadMeteorShowers 与 setMeteorShowersFlag 共用）。
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

  // 流星雨面板：桥查询当前设置与本月活跃流星雨。
  loadMeteorShowers(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const requestId = ++this.seq
    port.requestWhenReady('getMeteorShowers', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.seq) return
      const resp = r as MeteorShowersResponse
      const m = resp.meteorShowers
      if (!m) { return }
      this.msEnabled = m.enabled
      this.msLabels = m.labels
      this.msActiveOnly = m.activeOnly
      this.msMarker = m.marker
      this.msCatalogVersion = m.catalogVersion ?? ''
      this.msCatalogName = m.catalogName ?? ''
      this.msCatalogSource = m.catalogSource ?? ''
      // Parse active shower list
      if (resp.showerList && resp.showerList.length > 0) {
        this.msShowerList = resp.showerList.map((s): MeteorShowerItem => ({
          name: s.name ?? '',
          englishName: s.englishName ?? '',
          zhr: s.zhr ?? 0,
          status: s.status ?? '',
          speed: s.speed ?? 0,
          popIdx: s.popIdx ?? 0,
          parent: s.parent ?? '',
          peakDate: s.peakDate ?? '',
          activeStart: s.activeStart ?? '',
          activeEnd: s.activeEnd ?? ''
        }))
      } else {
        this.msShowerList = []
      }
    })
  }

  // 写流星雨开关（自增 seq 作废在途载入；重试档 0/100/15；失败回退重新加载）。
  setMeteorShowersFlag(name: string, v: boolean): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    this.seq++
    if (name == 'enabled') { this.msEnabled = v }
    else if (name == 'labels') { this.msLabels = v }
    else if (name == 'activeOnly') { this.msActiveOnly = v }
    else if (name == 'marker') { this.msMarker = v }
    port.requestWhenReady('setMeteorShowersFlag', name + ':' + (v ? '1' : '0'), (r: StellariumBridgeResponse) => {
      if (r.ok !== true) this.loadMeteorShowers()
    }, () => { this.loadMeteorShowers() }, 0, 100, 15)
  }
}
