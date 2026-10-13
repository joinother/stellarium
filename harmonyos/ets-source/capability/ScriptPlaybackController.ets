// 脚本录制回放 UI 控制器：录制控制条的显隐与拖动落位、脚本列表/录制条目/视频状态桥加载、
// 原生脚本播放/继续/停止/按键、脚本状态/字幕轮询、速率调整与脚本文件导入。
//
// 依赖 ScriptStore / ToolsStore（状态）、CommandPort（getScriptList / listRecordings /
// loadRecording / getVideoRecordingState / playScript / stopScript / sendKey / continueScript /
// getScriptStatus / getScriptCaptions / setScriptRate）与 DocumentImportPort（脚本导入）；
// ScriptPlaybackHostHooks 回注宿主几何量、叠层关闭、跨域动作、会话忙判定与 UI 动画（animateTo）；
// 控制器不 import UI 上下文。脚本状态轮询（250ms）与视频状态轮询（450ms）定时器自持，
// 宿主生命周期调用收口。
import hilog from '@ohos.hilog'
import { I18n } from '../pages/I18n'
import { ScriptStatusResponse, ScriptCaptionsResponse, RecordingsResponse, RecordingDetailResponse } from '../pages/MainWindowModels'
import { StellariumBridgeResponse, ScriptMetadata } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { DocumentImportPort, MediaImportResult } from '../bridge/MediaPort'
import { ScriptStore } from '../state/ScriptStore'
import { ToolsStore } from '../state/ToolsStore'
import { BehaviorHostHooks } from './ControllerHooks'
import { touchScreenX, touchScreenY, scriptControlX, scriptControlY, guideCardX, guideCardY, guideCardHeight } from '../common/derive/geometry'

// 宿主 → 控制器回注：
//   - scriptControlSafeTop / isExpandedLayout / skyWidth / skyHeight / guideCardWidth：控制条拖动落位的
//     宿主几何量与 UI 上下文派生量；
//   - stopSkyInertia：拖动开始即停下星图惯性（skyInputCtl）；
//   - guideActive：交互导览是否进行中（guideStore.guideState.active）；
//   - dismissScriptOverlays：折叠录制 UI 时关闭脚本相关叠层（panelVisible / infoWindow / gyroCalib）；
//   - reloadObserverInfo / loadPlanetList：脚本收尾后 220ms 的跨域重载；
//   - sessionBusy / requestStopGuide / finishReplay / stopBackgroundTimers / logScriptError /
//     stopVideoRecording：原生脚本播放入口守卫、导览收口、回放收尾、互斥后台定时器收口、启动失败日志与
//     视频轮询结束收尾；
//   - animateWaiting / animateCaptions：refreshScriptStatus（180ms spring）/ refreshScriptCaptions（160ms）的
//     UI 动画（控制器不触碰 getUIContext）。
export interface ScriptPlaybackHostHooks extends BehaviorHostHooks {
  scriptControlSafeTop(): number
  isExpandedLayout(): boolean
  skyWidth(): number
  skyHeight(): number
  guideCardWidth(): number
  stopSkyInertia(): void
  guideActive(): boolean
  dismissScriptOverlays(): void
  reloadObserverInfo(): void
  loadPlanetList(): void
  // 是否已有脚本/录制/导览会话（playScriptByName 入口守卫）。
  sessionBusy(): boolean
  // 停止交互导览（stopScriptPlayback 中断导览）。
  requestStopGuide(): void
  // 回放收尾（stopScriptPlayback 停止回放）。
  finishReplay(message: string): void
  // 停止与脚本互斥的宿主后台定时器（时间面板 / 星空文化时间跟随 / 极轴镜）。
  stopBackgroundTimers(): void
  // 脚本启动失败诊断日志。
  logScriptError(filename: string, error: string): void
  // 视频轮询发现录制结束时回注，让宿主（RecordingController）收尾。
  stopVideoRecording(): void
  animateWaiting(action: () => void): void
  animateCaptions(action: () => void): void
}

export class ScriptPlaybackController {
  private scriptStore: ScriptStore
  private tools: ToolsStore
  private port: CommandPort
  private mediaPort: DocumentImportPort
  private hooks: ScriptPlaybackHostHooks

  // ── 草稿字段（留控制器，不入被观察 store）──
  private scriptControlDragging: boolean = false
  private scriptControlDragStartX: number = 0
  private scriptControlDragStartY: number = 0
  private scriptControlDragStartOffsetX: number = 0
  private scriptControlDragStartOffsetY: number = 0
  private scriptStatusTimer: number = -1
  // ── 视频状态轮询定时器（450ms）──
  private videoStateTimer: number = -1
  private scriptStatusRequestPending: boolean = false
  private scriptCaptionsRequestPending: boolean = false

  constructor(
    scriptStore: ScriptStore,
    tools: ToolsStore,
    port: CommandPort,
    mediaPort: DocumentImportPort,
    hooks: ScriptPlaybackHostHooks
  ) {
    this.scriptStore = scriptStore
    this.tools = tools
    this.port = port
    this.mediaPort = mediaPort
    this.hooks = hooks
  }

  toggleRecordingUi(): void {
    this.tools.recordingUiExpanded = !this.tools.recordingUiExpanded
    if (!this.tools.recordingUiExpanded) {
      this.hooks.dismissScriptOverlays()
    }
  }

  handleScriptControlDragTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) return
    const x = touchScreenX(points[0])
    const y = touchScreenY(points[0])
    if (event.type === TouchType.Down) {
      this.scriptControlDragging = true
      this.scriptControlDragStartX = x
      this.scriptControlDragStartY = y
      this.scriptControlDragStartOffsetX = this.scriptStore.scriptControlOffsetX
      this.scriptControlDragStartOffsetY = this.scriptStore.scriptControlOffsetY
      this.hooks.stopSkyInertia()
      return
    }
    if (event.type === TouchType.Move && this.scriptControlDragging) {
      this.scriptStore.scriptControlOffsetX = this.scriptControlDragStartOffsetX + x - this.scriptControlDragStartX
      this.scriptStore.scriptControlOffsetY = this.scriptControlDragStartOffsetY + y - this.scriptControlDragStartY
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.scriptControlDragging = false
      if (this.hooks.guideActive()) {
        this.scriptStore.scriptControlOffsetX = guideCardX(this.hooks.isExpandedLayout(), this.hooks.skyWidth(), this.hooks.guideCardWidth(), this.scriptStore.scriptControlOffsetX) - (this.hooks.isExpandedLayout() ? 12 : (this.hooks.skyWidth() - this.hooks.guideCardWidth()) / 2)
        this.scriptStore.scriptControlOffsetY = guideCardY(this.hooks.skyHeight(), guideCardHeight(this.hooks.skyHeight(), this.hooks.scriptControlSafeTop()), this.hooks.scriptControlSafeTop(), this.scriptStore.scriptControlOffsetY) - (this.hooks.skyHeight() - guideCardHeight(this.hooks.skyHeight(), this.hooks.scriptControlSafeTop()) - 16)
      } else {
        this.scriptStore.scriptControlOffsetX = scriptControlX(this.hooks.skyWidth(), this.scriptStore.replaying, this.scriptStore.scriptControlOffsetX) - 12
        this.scriptStore.scriptControlOffsetY = scriptControlY(this.hooks.skyHeight(), this.hooks.scriptControlSafeTop(), this.scriptStore.scriptControlHeight(), this.scriptStore.scriptControlOffsetY) - this.hooks.scriptControlSafeTop()
      }
    }
  }

  startScriptStatusPolling(): void {
    if (this.scriptStatusTimer >= 0) { return }
    this.refreshScriptStatus()
    this.scriptStatusTimer = setInterval(() => {
      this.refreshScriptStatus()
    }, 250) as number
  }

  stopScriptStatusPolling(): void {
    if (this.scriptStatusTimer >= 0) {
      clearInterval(this.scriptStatusTimer)
      this.scriptStatusTimer = -1
    }
    this.scriptStatusRequestPending = false
    this.scriptCaptionsRequestPending = false
    this.scriptStore.scriptCaptions = []
  }

  finishNativeScriptUi(message: string): void {
    this.scriptStore.scriptRunning = false
    this.scriptStore.scriptWaiting = false
    this.scriptStore.scriptWaitMessage = ''
    this.scriptStore.scriptId = ''
    this.scriptStore.scriptFocusActive = false
    this.scriptStore.scriptLaunching = false
    this.scriptStore.scriptLaunchingName = ''
    this.scriptStore.scriptStartGraceUntil = 0
    this.tools.recordingUiExpanded = true
    this.stopScriptStatusPolling()
    this.hooks.flashHint(message)
    // Native restoration is applied immediately and again after the nested
    // script event loop drains. Refresh ArkTS after that second pass so the
    // location/time controls never retain the script's temporary state.
    setTimeout(() => {
      this.hooks.refreshState()
      this.hooks.reloadObserverInfo()
      this.hooks.loadPlanetList()
    }, 220)
  }

  refreshScriptStatus(): void {
    if (this.hooks.guideActive() || this.scriptStatusRequestPending || !this.scriptStore.scriptPlaybackVisible(this.hooks.guideActive())) { return }
    this.scriptStatusRequestPending = true
    this.port.requestInteractive('getScriptStatus', '', (r: StellariumBridgeResponse) => {
      this.scriptStatusRequestPending = false
      const status = r as ScriptStatusResponse
      if (status.ok !== true) { return }
      const running = status.running === true
      const waiting = running && status.waiting === true
      const waitMessage = waiting && typeof status.waitMessage === 'string' ? status.waitMessage : ''
      this.scriptStore.scriptRunning = running
      if (waiting !== this.scriptStore.scriptWaiting || waitMessage !== this.scriptStore.scriptWaitMessage) {
        this.hooks.animateWaiting(() => {
          this.scriptStore.scriptWaiting = waiting
          this.scriptStore.scriptWaitMessage = waitMessage
        })
      }
      this.scriptStore.scriptId = typeof status.scriptId === 'string' ? status.scriptId : ''
      this.refreshScriptCaptions()
      if (typeof status.scriptRate === 'number' && Number.isFinite(status.scriptRate)) {
        this.scriptStore.scriptRate = status.scriptRate
      }
      if (!running && !this.scriptStore.scriptLaunching && !this.scriptStore.replaying && Date.now() >= this.scriptStore.scriptStartGraceUntil) {
        this.finishNativeScriptUi(I18n.t('script_finished'))
      }
    }, () => {
      this.scriptStatusRequestPending = false
    })
  }

  refreshScriptCaptions(): void {
    if (this.scriptCaptionsRequestPending || !this.scriptStore.scriptPlaybackVisible(this.hooks.guideActive())) return
    this.scriptCaptionsRequestPending = true
    this.port.requestInteractive('getScriptCaptions', '', (r: StellariumBridgeResponse) => {
      this.scriptCaptionsRequestPending = false
      const response = r as ScriptCaptionsResponse
      if (response.ok !== true || !Array.isArray(response.captions)) {
        this.scriptStore.scriptCaptions = []
        return
      }
      const captions = response.captions
        .filter((item) => item.visible === true && typeof item.text === 'string' && item.text.length > 0)
        .map((item) => item.text)
        .slice(-3)
      if (captions.join('\n') !== this.scriptStore.scriptCaptions.join('\n')) {
        this.hooks.animateCaptions(() => {
          this.scriptStore.scriptCaptions = captions
        })
      }
    }, () => {
      this.scriptCaptionsRequestPending = false
    })
  }

  changeScriptRate(direction: number): void {
    const next = Math.max(0.25, Math.min(16, this.scriptStore.scriptRate * (direction > 0 ? 2 : 0.5)))
    this.port.requestInteractive('setScriptRate', next.toString(), (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.scriptStore.scriptRate = next
      } else {
        this.hooks.flashHint('调整脚本速度失败')
      }
    })
  }

  async importScriptFile(): Promise<void> {
    if (this.scriptStore.scriptImporting) return
    this.scriptStore.scriptImporting = true
    try {
      const result: MediaImportResult = await this.mediaPort.importScriptDocument()
      if (result.cancelled || result.path.length === 0) {
        this.hooks.flashHint(I18n.t('script_import_cancelled'))
        return
      }
      const fileName = result.path.substring(result.path.lastIndexOf('/') + 1)
      this.hooks.flashHint(I18n.format('script_import_success', [fileName]))
      hilog.info(0x0000, 'StellariumArkUI', 'Imported offline script %{public}s', fileName)
      this.loadScriptList()
    } catch (error) {
      hilog.error(0x0000, 'StellariumArkUI', 'Script import failed: %{public}s', String(error))
      this.hooks.flashHint(I18n.t('script_import_failed'))
    } finally {
      this.scriptStore.scriptImporting = false
    }
  }

  // ── 脚本 / 录制 / 视频状态桥加载与原生脚本播放 ──

  // 脚本面板「已保存录制」列表：桥拉取录制条目。
  loadRecordings(): void {
    this.port.requestInteractive('listRecordings', '', (r: StellariumBridgeResponse) => {
      const resp = r as RecordingsResponse
      this.scriptStore.recordings = resp.items ?? []
    })
  }

  // 脚本面板列表：桥拉取脚本名与资源元数据。
  loadScriptList(): void {
    this.port.requestInteractive('getScriptList', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && Array.isArray(r.items)) {
        this.scriptStore.scriptList = r.items as string[]
        this.setScriptMetadata(r.details)
      }
    })
  }

  // 脚本资源元数据表：按文件名索引（loadScriptList 回包；启动桥经 hooks 复用）。
  setScriptMetadata(raw: Object | undefined): void {
    if (!Array.isArray(raw)) { return }
    const next: Record<string, ScriptMetadata> = {}
    for (const item of raw as Array<ScriptMetadata>) {
      if (item.file) { next[item.file] = item }
    }
    this.scriptStore.scriptMetadata = next
  }

  // 按文件名载入录制并提示命令条数。
  loadRecordingByName(file: string, name: string): void {
    this.port.requestInteractive('loadRecording', file, (r: StellariumBridgeResponse) => {
      const resp = r as RecordingDetailResponse
      const cmds = resp.commands ?? []
      if (r.ok === true) {
        this.hooks.flashHint('已加载录制：' + name + '（' + cmds.length + ' 条命令）')
      } else {
        this.hooks.flashHint('加载录制失败')
      }
    })
  }

  // 视频帧序列录制状态轮询。
  loadVideoRecordingState(): void {
    this.port.requestInteractive('getVideoRecordingState', '', (r: StellariumBridgeResponse) => {
      const wasRecording = this.scriptStore.videoRecording
      this.scriptStore.videoRecording = r.recording === true
      this.scriptStore.videoDir = r.dir as string ?? ''
      this.scriptStore.videoFrameCount = r.frameCount as number ?? 0
      this.scriptStore.videoFailedFrames = r.failedFrames as number ?? 0
      this.scriptStore.videoMaxFrames = r.maxFrames as number ?? 0
      if (wasRecording && !this.scriptStore.videoRecording) {
        this.stopVideoStatePolling()
        setTimeout(() => {
          this.hooks.stopVideoRecording()
        }, 0)
      }
    })
  }

  // 视频状态轮询定时器开启。
  startVideoStatePolling(): void {
    this.stopVideoStatePolling()
    this.videoStateTimer = setInterval(() => { this.loadVideoRecordingState() }, 450) as number
  }

  // 视频状态轮询定时器收口。
  stopVideoStatePolling(): void {
    if (this.videoStateTimer >= 0) {
      clearInterval(this.videoStateTimer)
      this.videoStateTimer = -1
    }
  }

  // 按文件名启动原生脚本。
  playScriptByName(filename: string): void {
    if (this.hooks.sessionBusy()) {
      return
    }
    this.scriptStore.scriptLaunching = true
    this.scriptStore.scriptLaunchingName = filename
    this.scriptStore.scriptFocusActive = true
    this.scriptStore.scriptId = filename
    this.scriptStore.scriptRate = 1
    this.scriptStore.scriptWaiting = false
    this.scriptStore.scriptWaitMessage = ''
    this.scriptStore.scriptStartGraceUntil = Date.now() + 2500
    this.hooks.dismissScriptOverlays()
    this.hooks.stopBackgroundTimers()
    this.startScriptStatusPolling()
    this.hooks.flashHint('正在启动脚本…')
    this.port.requestInteractive('playScript', filename, (r: StellariumBridgeResponse) => {
      this.scriptStore.scriptLaunching = false
      this.scriptStore.scriptLaunchingName = ''
      if (r.ok === true) {
        this.hooks.flashHint(I18n.t('msg_script_running'))
        this.refreshScriptStatus()
      } else {
        this.scriptStore.scriptFocusActive = false
        this.scriptStore.scriptWaiting = false
        this.scriptStore.scriptWaitMessage = ''
        this.stopScriptStatusPolling()
        this.hooks.logScriptError(filename, r.error ?? '')
        this.hooks.flashHint(I18n.t('msg_apply_failed'))
      }
    }, () => {
      this.scriptStore.scriptLaunching = false
      this.scriptStore.scriptLaunchingName = ''
      this.scriptStore.scriptFocusActive = false
      this.scriptStore.scriptWaiting = false
      this.scriptStore.scriptWaitMessage = ''
      this.stopScriptStatusPolling()
      this.hooks.flashHint('脚本启动超时，请重试')
    })
  }

  // 继续原生脚本等待。
  continueNativeScript(): void {
    if (!this.scriptStore.scriptRunning || this.scriptStore.replaying) return
    this.port.requestInteractive('continueScript', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.hooks.animateWaiting(() => {
          this.scriptStore.scriptWaiting = false
          this.scriptStore.scriptWaitMessage = ''
        })
        this.hooks.flashHint(I18n.t('script_continue'))
      } else {
        this.hooks.flashHint(I18n.t('script_continue_failed'))
      }
    })
  }

  // 停止脚本播放 / 导览。
  stopScriptPlayback(): void {
    if (this.hooks.guideActive()) {
      this.hooks.requestStopGuide()
      return
    }
    if (this.scriptStore.replaying) {
      this.hooks.finishReplay('回放已停止')
    }
    this.port.requestInteractive('stopScript', '', (r: StellariumBridgeResponse) => {
      this.finishNativeScriptUi(r.ok === true ? I18n.t('script_stopped') : I18n.t('script_stop_failed'))
    })
  }

  // 向原生脚本发送按键。
  sendScriptKey(key: string): void {
    if (!this.scriptStore.scriptRunning || this.scriptStore.replaying) return
    this.port.requestInteractive('sendKey', key, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.hooks.flashHint('脚本按键不可用')
      }
    })
  }
}
