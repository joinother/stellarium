// 剪贴板服务（PLAN §15.3 P4-2 / §15.10 M1-4，本片 M1-A 子组②）。
//
// 原宿主 MainWindowNativeNode 的 copyTextToClipboard(13) 私有方法逐字下沉。
// 本模块**不 import NAPI/UI**（§15.7 规则 1）：底层 pasteboard 写入经 PlatformPort
//（bridge/PlatformPort.ets，宿主适配器转发 qability/ClipboardService.writeClipboardText）；
// UI 提示经 ClipboardHints.flashHint 具名注入（§13.1 规则 6）。
import { I18n } from '../../pages/I18n'
import { PlatformPort } from '../../bridge/PlatformPort'

export interface ClipboardHints {
  flashHint(text: ResourceStr): void
}

// 写剪贴板并给出成功/失败/空文本提示（原宿主 copyTextToClipboard，逐字搬入）。
// 差异仅：writeClipboardText(text) → port.writeClipboardText(text)。
export async function copyTextToClipboard(
  port: PlatformPort,
  text: string,
  successHint: ResourceStr,
  hints: ClipboardHints,
): Promise<boolean> {
  if (text.length === 0) {
    hints.flashHint(I18n.t('clipboard_copy_empty'))
    return false
  }
  const ok = await port.writeClipboardText(text)
  if (ok) {
    hints.flashHint(successHint)
    return true
  }
  hints.flashHint(I18n.t('clipboard_copy_failed'))
  return false
}
