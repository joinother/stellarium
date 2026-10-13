// 截图导出服务（PLAN §15.3 P4-2 / §15.10 M1-4，本片 M1-A 子组②）。
//
// 原宿主 MainWindowNativeNode 的 saveScreenshot(17) / exportScreenshotToUserStorage(25) 私有方法逐字下沉。
// 本模块**不 import NAPI/UI**（§15.7 规则 1）：截图桥命令经 CommandPort、DocumentViewPicker.save +
// fileIo.copy/unlinkSync 经 MediaPort；`tools.screenshotSaving` 与 flashHint 经 ScreenshotHints 具名注入。
import { StellariumBridgeResponse } from '../../pages/StellariumTypes'
import { ScreenshotResponse } from '../../pages/MainWindowModels'
import { I18n } from '../../pages/I18n'
import { CommandPort } from '../../bridge/CommandPort'
import { FileExportPort, MediaSaveResult } from '../../bridge/MediaPort'

export interface ScreenshotHints {
  flashHint(text: ResourceStr): void
  screenshotSaving(): boolean
  setScreenshotSaving(saving: boolean): void
}

// 触发原生截图并导出到用户存储（原宿主 saveScreenshot，逐字搬入）。
// 差异仅：this.tools.screenshotSaving → hints.screenshotSaving()/setScreenshotSaving()；
// this.callInteractive → port.requestInteractive；this.exportScreenshotToUserStorage → 同模块函数。
export function saveScreenshot(port: CommandPort, mediaPort: FileExportPort, hints: ScreenshotHints): void {
  if (hints.screenshotSaving()) return
  hints.setScreenshotSaving(true)
  hints.flashHint(I18n.t('screenshot_preparing'))
  port.requestInteractive('saveScreenShot', '', (r: StellariumBridgeResponse) => {
    const response = r as ScreenshotResponse
    if (response.ok !== true || !response.path || !response.fileName) {
      hints.setScreenshotSaving(false)
      hints.flashHint(I18n.t('screenshot_failed'))
      return
    }
    exportScreenshotToUserStorage(mediaPort, response, hints)
  }, () => {
    hints.setScreenshotSaving(false)
    hints.flashHint(I18n.t('screenshot_failed'))
  })
}

// 用 DocumentViewPicker 把截图另存到用户目录，并在收尾时删除临时文件（原宿主 exportScreenshotToUserStorage，
// 逐字搬入）。差异仅：picker.DocumentViewOptions + fileIo.copy + fileIo.unlinkSync → mediaPort.saveFileAs/
// deleteFile；context/format 组装留在适配器与调用处。
export async function exportScreenshotToUserStorage(
  mediaPort: FileExportPort,
  response: ScreenshotResponse,
  hints: ScreenshotHints,
): Promise<void> {
  const sourcePath = response.path ?? ''
  const format = (response.format ?? 'png').toUpperCase()
  const fileName = response.fileName ?? ('stellarium-' + Date.now().toString() + '.png')
  const suffixLabel = format + ' image|.' + format.toLowerCase()
  mediaPort.saveFileAs(sourcePath, fileName, suffixLabel, (result: MediaSaveResult) => {
    if (result === MediaSaveResult.Saved) {
      hints.flashHint(I18n.t('screenshot_saved'))
    } else if (result === MediaSaveResult.Cancelled) {
      hints.flashHint(I18n.t('screenshot_cancelled'))
    } else {
      hints.flashHint(I18n.t('screenshot_failed'))
    }
    if (sourcePath.length > 0) {
      mediaPort.deleteFile(sourcePath)
    }
    hints.setScreenshotSaving(false)
  })
}
