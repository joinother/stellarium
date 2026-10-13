import { MosaicCameraData } from '../pages/MainWindowModels'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 相机拼接视场（mosaicCamera）面板状态。
//
// 持有拼接相机开关、星表、当前相机与指向、加载/待处理/状态等字段，被 MosaicCameraPanel
// 以 @ObjectLink 观察。加载器 loadMosaicCamera 自持 CommandPort；写回动作仍在宿主，面板只读 + 回调。
//
// 字段均为整体赋值（无数组原地 push/splice、无对象原地改属性），适配被观察 store。
@Observed
export class MosaicStore {
  mosaicCameraEnabled: boolean = false
  mosaicCameraNames: string[] = []
  mosaicCameraCurrent: string = ''
  mosaicCameraRA: number = 0
  mosaicCameraDec: number = 0
  mosaicCameraRotation: number = 0
  mosaicCameraVisible: boolean = false
  mosaicCameraLoading: boolean = false
  mosaicCameraPending: boolean = false
  mosaicCameraStatus: string = ''

  // —— 桥注入：本 store 自持 loadMosaicCamera ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（无并发抑制需求），预留保持统一约定。
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

  // 相机拼接面板：桥查询拼接相机配置（重试档 0/100/15，onFailure 按端口签名前移）。
  loadMosaicCamera(initial: boolean = true): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    this.mosaicCameraLoading = initial
    port.requestWhenReady('getMosaicCamera', '', (r: StellariumBridgeResponse) => {
      const data = r.mosaicCamera as MosaicCameraData | undefined
      if (r.ok !== true || data === undefined) {
        this.mosaicCameraStatus = I18n.t('plugin_status_unavailable')
      } else {
        this.mosaicCameraEnabled = data.enabled
        this.mosaicCameraNames = data.names ?? []
        this.mosaicCameraCurrent = data.currentCamera
        this.mosaicCameraRA = data.ra
        this.mosaicCameraDec = data.dec
        this.mosaicCameraRotation = data.rotation
        this.mosaicCameraVisible = Boolean(data.visible)
        this.mosaicCameraStatus = ''
      }
      this.mosaicCameraLoading = false
      this.mosaicCameraPending = false
      this.notifyChanged()
    }, () => {
      this.mosaicCameraLoading = false
      this.mosaicCameraPending = false
      this.mosaicCameraStatus = I18n.t('plugin_status_unavailable')
      this.notifyChanged()
    }, 0, 100, 15)
  }
}
