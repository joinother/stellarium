import { RecordingEntry } from '../pages/MainWindowModels'
import { ScriptMetadata } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { resourceText } from '../common/derive/labels'
import { scriptControlWidth } from '../common/derive/geometry'

// 脚本 / 录制 / 视频导出域 store：持有面板可见的脚本列表、录制条目、视频与屏幕录制状态、
// 播放引擎/回放四态（scriptWaiting / scriptRunning / replaying / replayPaused）等，
// 由 ScriptsPanel / ScriptFocusShell 经 @ObjectLink 观察。
//
// 本 store 为纯数据 + 纯派生：脚本列表 / 录制条目 / 视频状态的桥调用、回放与原生脚本播放动作、
// 450ms 视频状态轮询定时器全部由 capability/ScriptPlaybackController 持有并读写本 store 字段。
//
// 所有字段更新都必须整体赋值：@ObjectLink 观测不到数组原地 push/splice 或对象改属性。
// 录制引擎的追加型工作缓冲 `recordBuffer`（每次命令 push、整体清空）不入被观察 store，留在宿主。
@Observed
export class ScriptStore {
  scriptList: string[] = []
  scriptLaunching: boolean = false
  scriptLaunchingName: string = ''
  scriptImporting: boolean = false
  recordCount: number = 0
  recordName: string = ''
  recordMsg: string = ''
  recordings: Array<RecordingEntry> = []
  videoRecording: boolean = false
  videoDir: string = ''
  videoFrameCount: number = 0
  videoMaxFrames: number = 0
  videoFailedFrames: number = 0
  videoArchivePath: string = ''
  videoFps: string = '1'
  videoDuration: string = '5'
  screenVideoRecording: boolean = false
  screenVideoPath: string = ''
  screenVideoBytes: number = 0
  screenVideoStatus: string = ''
  screenCaptureFinalizing: boolean = false

  // —— 脚本播放引擎 / 回放 / 视频导出 ——
  scriptMetadata: Record<string, ScriptMetadata> = {}
  scriptFocusActive: boolean = false
  scriptRunning: boolean = false
  scriptWaiting: boolean = false
  scriptWaitMessage: string = ''
  scriptCaptions: Array<string> = []
  scriptId: string = ''
  scriptRate: number = 1
  scriptControlOffsetX: number = 0
  scriptControlOffsetY: number = 0
  replaying: boolean = false
  replayPaused: boolean = false
  replayRate: number = 1
  replayName: string = ''
  videoArchiveFileName: string = ''
  screenVideoFileName: string = ''

  // —— 原生脚本启动后的宽限期 ——
  // ScriptPlaybackController.refreshScriptStatus 读它以免刚启动就被判为已结束；
  // 控制器的 playScriptByName 与 CLI 事件写它。
  scriptStartGraceUntil: number = 0

  // ==== 脚本元数据 / 字幕的取值与文案助手 ====
  //
  // 均读本 store 的 scriptMetadata / scriptCaptions / scriptWaitMessage；resourceText 为
  // 外部纯函数 import。

  // 按文件名取脚本元数据。
  scriptMeta(filename: string): ScriptMetadata | undefined {
    return this.scriptMetadata[filename]
  }

  // 脚本作者/许可/版本行。
  scriptMetaLine(filename: string): string {
    const metadata = this.scriptMeta(filename)
    if (metadata === undefined) { return I18n.t('resource_not_provided') }
    const values: string[] = []
    values.push(I18n.t('resource_author') + ': ' + resourceText(metadata.author, I18n.t('resource_not_provided')))
    values.push(I18n.t('resource_license') + ': ' + resourceText(metadata.license, I18n.t('resource_not_provided')))
    if (metadata.version && metadata.version.trim().length > 0) { values.push(I18n.t('resource_version') + ': ' + metadata.version.trim()) }
    return values.join(' · ')
  }

  // 脚本来源行。
  scriptSourceLine(filename: string): string {
    const metadata = this.scriptMeta(filename)
    return metadata !== undefined && metadata.source ? I18n.t('resource_source') + ': ' + metadata.source : ''
  }

  // 脚本等待提示。
  scriptWaitDisplayText(): string {
    const message = this.scriptWaitMessage.trim()
    if (message.length === 0 || /press\s+(any\s+)?key\s+to\s+continue/i.test(message)) {
      return I18n.t('script_wait_hint')
    }
    return message
  }

  // 最近三条脚本字幕。
  visibleScriptCaptions(): Array<string> {
    return this.scriptCaptions.slice(-3)
  }

  // 最近三条脚本字幕拼接文本。
  visibleScriptCaptionText(): string {
    return this.visibleScriptCaptions().join('\n')
  }

  // 脚本控制条高度：只读本 store 的 replaying。
  scriptControlHeight(): number {
    return this.replaying ? 176 : 224
  }

  // 脚本/导览播放可见性：读本 store 三标志 + 导览 active；后者跨 store 故以显式入参传入。
  scriptPlaybackVisible(guideActive: boolean): boolean {
    return guideActive || this.scriptFocusActive || this.scriptLaunching || this.replaying
  }

  // 是否有脚本会话：读录制标志 + 播放可见性；recording / guideActive 属他 store，以显式入参传入。
  scriptSessionActive(recording: boolean, guideActive: boolean): boolean {
    return recording || this.scriptPlaybackVisible(guideActive)
  }

  // 脚本控制条是否为紧凑档：skyWidth 由调用方传入。
  scriptControlCompact(skyWidth: number): boolean {
    return scriptControlWidth(skyWidth, this.replaying) < 390
  }

  // 脚本按键宽度：skyWidth 由调用方传入。
  scriptKeyButtonWidth(skyWidth: number): number {
    return Math.max(32, Math.min(44, (scriptControlWidth(skyWidth, this.replaying) - 49) / 6))
  }

  // 回放时间轴位置（ms）：开始/暂停/累计耗时由调用方传入；replayPaused/replayRate 读本 store。
  replayTimelineMs(pauseStartedAt: number, startedAt: number, pausedTotal: number): number {
    const now = this.replayPaused && pauseStartedAt > 0 ? pauseStartedAt : Date.now()
    return Math.max(0, now - startedAt - pausedTotal) * this.replayRate
  }
}
