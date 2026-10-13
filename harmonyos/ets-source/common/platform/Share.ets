// 系统分享服务（PLAN §15.3 P4-2 / §15.10 M1-4，本片 M1-A 子组②）。
//
// 原宿主 MainWindowNativeNode 的 shareFile(22) 私有方法逐字下沉。
// 本模块**不 import NAPI/UI**（§15.7 规则 1）：文件存在性经 MediaPort、系统分享面板经
// PlatformPort（宿主适配器转发 @kit.ShareKit systemShare + getHostContext + isExpandedLayout）；
// UI 提示经 ShareHints.flashHint 具名注入（§13.1 规则 6）。
import { ImagePort } from '../../bridge/MediaPort'
import { PlatformPort } from '../../bridge/PlatformPort'

export interface ShareHints {
  flashHint(text: ResourceStr): void
  // 是否处于扩展（Pad / 2-in-1）布局：决定分享面板是否以 anchorId 为锚点（对应宿主 isExpandedLayout）。
  isExpandedLayout(): boolean
}

// 分享一个本地文件（原宿主 shareFile，逐字搬入）。
// 差异仅：fileIo.accessSync → mediaPort.fileExists；systemShare.* + ShareController.show →
// platformPort.shareFile；catch 中的 hilog + 提示由适配器/onDone 承担。
export function shareFile(
  mediaPort: ImagePort,
  platformPort: PlatformPort,
  path: string,
  type: string,
  title: string,
  description: string,
  anchorId: string,
  hints: ShareHints,
): void {
  if (path.length === 0 || !mediaPort.fileExists(path)) {
    hints.flashHint('没有可分享的文件')
    return
  }
  platformPort.shareFile(path, type, title, description, anchorId, hints.isExpandedLayout(), (ok: boolean) => {
    if (!ok) {
      hints.flashHint('无法打开系统分享面板')
    }
  })
}
