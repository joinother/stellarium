// 平台能力端口：以纯接口提供剪贴板写入、系统分享与语音合成语义，
// 使平台服务（common/platform/Clipboard、common/platform/Share、common/SpeechService）
// 无需 import systemShare / pasteboard / TTS 等设备能力模块。
// 宿主在 aboutToAppear 注入具名实现 HostPlatformPort（MainWindowNativeNode.ets）。
export interface PlatformPort {
  // 写系统剪贴板（@ohos.pasteboard）；返回是否写入成功。
  writeClipboardText(text: string): Promise<boolean>
  // 打开系统分享面板（对应 @kit.ShareKit systemShare）。onDone(ok) 表示分享面板是否成功弹出，
  // false = 打开失败，由调用方提示。anchorId 仅在有扩展布局时作为锚点生效（expanded 为真时）。
  shareFile(
    path: string,
    utd: string,
    title: string,
    description: string,
    anchorId: string,
    expanded: boolean,
    onDone: (ok: boolean) => void
  ): void
  // 语音合成（TTS）。当前基础 SDK（API 24）不含 @kit.CoreSpeechKit，宿主实现为「仅生成可读文本」，
  // 留待切换到含语音合成的 SDK 后接真实播报。
  speak(text: string): void
}
