import { NebulaTextureStatus } from '../pages/MainWindowModels'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 星云贴图（nebulaTextures）面板域状态：持有状态对象 nebulaTextureStatus、加载态
// nebulaTextureLoading、待确认 nebulaTexturePending、导入中 nebulaTextureImporting、
// 动作提示 nebulaTextureActionStatus；宿主持有实例，NebulaTexturesPanel 以 @ObjectLink 观察。
// 自持 CommandPort 与发布回调，并自持加载器 loadNebulaTextureStatus。
// 约束：所有更新必须是"字段整体赋值"（nebulaTextureStatus 只被整体赋值，其余为标量）。
@Observed
export class NebulaTextureStore {
  nebulaTextureStatus: NebulaTextureStatus | undefined = undefined
  nebulaTextureLoading: boolean = false
  nebulaTexturePending: boolean = false
  nebulaTextureImporting: boolean = false
  nebulaTextureActionStatus: string = ''

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（无并发抑制需求）；保留字段以统一各 store 的加载器约定。
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

  // 星云贴图面板：桥查询贴图加载状态。
  loadNebulaTextureStatus(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    if (this.nebulaTextureLoading) return
    this.nebulaTextureLoading = true
    port.requestInteractive('getNebulaTextureStatus', '', (r: StellariumBridgeResponse) => {
      this.nebulaTextureLoading = false
      if (r.ok !== true) {
        this.nebulaTextureActionStatus = r.error ?? I18n.t('nebula_texture_status_failed')
        this.notifyChanged()
        return
      }
      this.nebulaTextureStatus = r as NebulaTextureStatus
      this.notifyChanged()
    }, () => {
      this.nebulaTextureLoading = false
      this.nebulaTextureActionStatus = I18n.t('nebula_texture_status_failed')
      this.notifyChanged()
    })
  }
}
