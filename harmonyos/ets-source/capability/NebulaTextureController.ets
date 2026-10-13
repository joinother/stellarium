// 星云纹理行为控制器：贴图显隐 / 状态查询 / 视野跳转 / 删除 / 导入。
// 桥调用经 CommandPort，导入段的 picker + fileIo 经 DocumentImportPort，
// 状态整体写入 NebulaTextureStore（面板经 @ObjectLink 消费）；控制器不 import NAPI/UI。
import hilog from '@ohos.hilog'
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { NebulaTextureStatus, NebulaTextureRefreshResponse } from '../pages/MainWindowModels'
import { CommandPort } from '../bridge/CommandPort'
import { DocumentImportPort, MediaImportResult } from '../bridge/MediaPort'
import { NebulaTextureStore } from '../state/NebulaTextureStore'
import { BehaviorHostHooks } from './ControllerHooks'

export interface NebulaTextureHostHooks extends BehaviorHostHooks {}

export class NebulaTextureController {
  private port: CommandPort
  private mediaPort: DocumentImportPort
  private nebulaTextureStore: NebulaTextureStore
  private hooks: NebulaTextureHostHooks

  constructor(port: CommandPort, mediaPort: DocumentImportPort, nebulaTextureStore: NebulaTextureStore, hooks: NebulaTextureHostHooks) {
    this.port = port
    this.mediaPort = mediaPort
    this.nebulaTextureStore = nebulaTextureStore
    this.hooks = hooks
  }

  // 开关写回（当前值由 store 状态提供）。
  setNebulaTextureVisible(enabled: boolean): void {
    this.setNebulaTextureFlag('setNebulaTexturesVisible', enabled, this.nebulaTextureStore.nebulaTextureStatus?.enabled === true)
  }

  // 通用写回（防重入 + 等待权威状态；面板「冲突避让」也复用）。
  setNebulaTextureFlag(command: string, enabled: boolean, current: boolean): void {
    if (this.nebulaTextureStore.nebulaTexturePending || this.nebulaTextureStore.nebulaTextureLoading || this.nebulaTextureStore.nebulaTextureImporting || enabled === current) return
    this.nebulaTextureStore.nebulaTexturePending = true
    this.port.requestInteractive(command, enabled ? '1' : '0', (r: StellariumBridgeResponse) => {
      this.nebulaTextureStore.nebulaTexturePending = false
      if (r.ok === true) this.nebulaTextureStore.nebulaTextureStatus = r as NebulaTextureStatus
      else this.nebulaTextureStore.nebulaTextureActionStatus = r.error ?? I18n.t('nebula_texture_action_failed')
    }, () => {
      this.nebulaTextureStore.nebulaTexturePending = false
      this.nebulaTextureStore.nebulaTextureActionStatus = I18n.t('nebula_texture_action_failed')
    })
  }

  // 重新拉取贴图加载状态。
  refreshNebulaTextures(): void {
    if (this.nebulaTextureStore.nebulaTextureLoading || this.nebulaTextureStore.nebulaTexturePending || this.nebulaTextureStore.nebulaTextureImporting) return
    this.nebulaTextureStore.nebulaTextureLoading = true
    this.port.requestInteractive('refreshNebulaTextures', '', (r: StellariumBridgeResponse) => {
      this.nebulaTextureStore.nebulaTextureLoading = false
      const status = (r as NebulaTextureRefreshResponse).status
      if (status !== undefined) this.nebulaTextureStore.nebulaTextureStatus = status
      this.nebulaTextureStore.nebulaTextureActionStatus = r.ok === true ? I18n.t('nebula_texture_refreshed') : (r.error ?? I18n.t('nebula_texture_action_failed'))
    }, () => {
      this.nebulaTextureStore.nebulaTextureLoading = false
      this.nebulaTextureStore.nebulaTextureActionStatus = I18n.t('nebula_texture_action_failed')
    })
  }

  // 把视野移动到指定贴图。
  gotoNebulaTexture(imageUrl: string): void {
    this.port.requestInteractive('gotoNebulaTexture', imageUrl, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) this.nebulaTextureStore.nebulaTextureActionStatus = r.error ?? I18n.t('nebula_texture_action_failed')
    }, () => { this.nebulaTextureStore.nebulaTextureActionStatus = I18n.t('nebula_texture_action_failed') })
  }

  // 删除指定贴图并重载状态。
  removeNebulaTexture(imageUrl: string): void {
    this.port.requestInteractive('removeNebulaTexture', imageUrl, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.nebulaTextureStore.nebulaTextureActionStatus = I18n.t('nebula_texture_removed')
        this.nebulaTextureStore.loadNebulaTextureStatus()
      } else this.nebulaTextureStore.nebulaTextureActionStatus = r.error ?? I18n.t('nebula_texture_action_failed')
    }, () => { this.nebulaTextureStore.nebulaTextureActionStatus = I18n.t('nebula_texture_action_failed') })
  }

  // 导入：picker 选图 → 复制到应用导入目录 → 桥导入。
  // picker + fileIo 段经 DocumentImportPort.pickDocumentToDir（宿主适配器保留后缀过滤 / 单文件 / 名清洗）。
  async importNebulaTextureFile(): Promise<void> {
    if (this.nebulaTextureStore.nebulaTextureImporting) return
    this.nebulaTextureStore.nebulaTextureImporting = true
    try {
      const result: MediaImportResult = await this.mediaPort.pickDocumentToDir(
        'nebula-texture-imports', ['图像|.png|.jpg|.jpeg|.gif|.tif|.tiff'], 'texture-' + Date.now().toString() + '.png')
      if (result.cancelled) {
        this.nebulaTextureStore.nebulaTextureActionStatus = I18n.t('nebula_texture_import_cancelled')
        this.nebulaTextureStore.nebulaTextureImporting = false
        return
      }
      this.port.requestInteractive('importNebulaTexture', JSON.stringify({ sourcePath: result.path }), (r: StellariumBridgeResponse) => {
        this.nebulaTextureStore.nebulaTextureActionStatus = r.ok === true ? I18n.t('nebula_texture_imported') : (r.error ?? I18n.t('nebula_texture_import_failed'))
        if (r.ok === true) this.nebulaTextureStore.loadNebulaTextureStatus()
        this.nebulaTextureStore.nebulaTextureImporting = false
      }, () => {
        this.nebulaTextureStore.nebulaTextureActionStatus = I18n.t('nebula_texture_import_failed')
        this.nebulaTextureStore.nebulaTextureImporting = false
      })
    } catch (error) {
      hilog.error(0x0000, 'StellariumArkUI', 'Nebula texture import failed: %{public}s', String(error))
      this.nebulaTextureStore.nebulaTextureActionStatus = I18n.t('nebula_texture_import_failed')
      this.nebulaTextureStore.nebulaTextureImporting = false
    }
  }
}
