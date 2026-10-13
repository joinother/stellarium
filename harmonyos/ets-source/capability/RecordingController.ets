// 录制 / 回放 / 录屏控制器。
//
// 负责脚本录制与回放状态机、录制视图检查点，以及视频帧序列与系统屏幕录制（MP4）。
// 状态（recordings / video* / screenVideo* / replaying / replayPaused / replayRate…）在
// state/ScriptStore.ets，本控制器只管理行为与定时器，不重复保存状态；追加型录制缓冲 recordBuffer
// 属保留字段，经 RecordingHostHooks 读写；本类自持 replayTimer / recordViewCheckpointTimer，
// 由宿主生命周期 stop() 收口。
//
// 依赖：CommandPort（saveRecording / loadRecording / getSessionState / startVideoRecording…）；
// ScreenCapturePort 封装系统录屏（fileIo / display / media / photoAccessHelper），本类不 import 这些
// 设备能力模块；ScriptStore / ToolsStore 以实例引用持有；RecordingHostHooks 回注 UI 提示、会话忙判定、
// 面板动作、脚本速率回退、recordBuffer 读写。
import hilog from '@ohos.hilog'
import { I18n } from '../pages/I18n'
import { ScriptStore } from '../state/ScriptStore'
import { ToolsStore } from '../state/ToolsStore'
import { CommandPort } from '../bridge/CommandPort'
import { ScreenCapturePort, ScreenCaptureState } from '../bridge/MediaPort'
import { StellariumBridgeResponse, SessionSnapshot } from '../pages/StellariumTypes'
import { RecordCmd, RecordingDetailResponse } from '../pages/MainWindowModels'
import { isRecordable } from '../common/derive/skycult'

// 宿主 → 控制器回注：
//   - recordBuffer 属保留字段，仍留宿主 @State，经长度/快照/追加/清空四个 hook 读写；
//   - UI 提示 / 面板动作 / 脚本速率回退 / 会话忙判定均不触碰 NAPI 之外的宿主私有逻辑。
export interface RecordingHostHooks {
  flashHint(text: ResourceStr): void
  // 会话忙判定（录制 / 引导 / 回放任一活动）。
  sessionBusy(): boolean
  // 开始录制时隐藏面板与信息窗。
  hidePanelAndInfo(): void
  // 停止录制后打开脚本面板。
  openScriptsPanel(): void
  // 非回放时切换脚本速率。
  changeScriptRate(direction: number): void
  // 脚本录制列表 / 视频状态轮询的桥加载（ScriptPlaybackController 持有）。
  loadRecordings(): void
  startVideoStatePolling(): void
  stopVideoStatePolling(): void
  recordBufferLength(): number
  recordBufferSnapshot(): Array<RecordCmd>
  recordBufferPush(cmd: RecordCmd): void
  recordBufferClear(): void
}

export class RecordingController {
  private scriptStore: ScriptStore
  private tools: ToolsStore
  private port: CommandPort
  private mediaPort: ScreenCapturePort
  private hooks: RecordingHostHooks

  // ── 录制引擎计时 / 去重（逐帧草稿，留控制器）──
  private lastRecordKey: string = ''
  private lastRecordTime: number = 0
  private recordStartedAt: number = 0
  private recordPausedAt: number = 0
  private recordPausedTotal: number = 0
  private recordViewCheckpointTimer: number = -1

  // ── 回放引擎（逐帧草稿，留控制器）──
  private replayTimer: number = -1
  private replayStartedAt: number = 0
  private replayPauseStartedAt: number = 0
  private replayPausedTotal: number = 0
  private replayIndex: number = 0
  private replayCommands: Array<RecordCmd> = []

  constructor(
    scriptStore: ScriptStore,
    tools: ToolsStore,
    port: CommandPort,
    mediaPort: ScreenCapturePort,
    hooks: RecordingHostHooks
  ) {
    this.scriptStore = scriptStore
    this.tools = tools
    this.port = port
    this.mediaPort = mediaPort
    this.hooks = hooks
  }

  // ── 生命周期收口（宿主 aboutToDisappear 调用）──
  stop(): void {
    this.cancelRecordingViewCheckpoint()
    if (this.scriptStore.replaying) {
      this.finishRecordingReplay('回放已结束')
    }
    this.tools.recording = false
    this.tools.recordingPaused = false
  }

  // ── 录制记录（宿主 callNative / callNativeFire / callNativeWhenReady 每条回包调用）──
  recordAcceptedCommand(name: string, payload: string): void {
    if (!this.tools.recording || this.tools.recordingPaused || this.scriptStore.replaying || !isRecordable(name)) { return }
    const key = name + '|' + payload
    const now = Date.now()
    if (key === this.lastRecordKey && now - this.lastRecordTime <= 400) { return }
    this.hooks.recordBufferPush({ c: name, p: payload,
      t: Math.max(0, now - this.recordStartedAt - this.recordPausedTotal) })
    this.scriptStore.recordCount = this.hooks.recordBufferLength()
    this.lastRecordKey = key
    this.lastRecordTime = now
  }

  private cancelRecordingViewCheckpoint(): void {
    if (this.recordViewCheckpointTimer >= 0) {
      clearTimeout(this.recordViewCheckpointTimer)
      this.recordViewCheckpointTimer = -1
    }
  }

  scheduleRecordingViewCheckpoint(delayMs: number = 900, fullSession: boolean = false): void {
    this.cancelRecordingViewCheckpoint()
    if (!this.tools.recording || this.tools.recordingPaused || this.scriptStore.replaying) { return }
    this.recordViewCheckpointTimer = setTimeout(() => {
      this.recordViewCheckpointTimer = -1
      this.port.requestInteractive('getSessionState', '', (response: StellariumBridgeResponse) => {
        if (!this.tools.recording || this.tools.recordingPaused || this.scriptStore.replaying || response.ok !== true) { return }
        const state = response as SessionSnapshot
        const checkpoint: SessionSnapshot = fullSession ? {
          schemaVersion: 1,
          viewJ2000: state.viewJ2000,
          fovDeg: state.fovDeg,
          jd: state.jd,
          location: state.location,
          selected: state.selected,
          flags: state.flags
        } : {
          schemaVersion: 1,
          viewJ2000: state.viewJ2000,
          fovDeg: state.fovDeg
        }
        this.recordAcceptedCommand('applySessionState', JSON.stringify(checkpoint))
      })
    }, delayMs) as number
  }

  // ===== 脚本录制 / 回放 =====
  startRecording(): void {
    if (this.hooks.sessionBusy()) {
      this.hooks.flashHint('脚本或回放进行中，结束后再开始录制')
      return
    }
    this.tools.recording = true
    this.tools.recordingPaused = false
    this.hooks.recordBufferClear()
    this.scriptStore.recordCount = 0
    this.scriptStore.recordMsg = '录制中…'
    this.lastRecordKey = ''
    this.lastRecordTime = 0
    this.recordStartedAt = Date.now()
    this.recordPausedAt = 0
    this.recordPausedTotal = 0
    this.tools.recordingUiExpanded = false
    this.hooks.hidePanelAndInfo()
    this.scheduleRecordingViewCheckpoint(80, true)
    this.hooks.flashHint('开始录制：接下来的操作会被记录')
  }

  toggleRecordingPause(): void {
    if (!this.tools.recording) { return }
    const now = Date.now()
    this.tools.recordingPaused = !this.tools.recordingPaused
    if (this.tools.recordingPaused) {
      this.cancelRecordingViewCheckpoint()
      this.recordPausedAt = now
    } else if (this.recordPausedAt > 0) {
      this.recordPausedTotal += now - this.recordPausedAt
      this.recordPausedAt = 0
    }
    this.scriptStore.recordMsg = this.tools.recordingPaused ? '已暂停录制' : '录制中…'
    this.lastRecordKey = ''
    this.lastRecordTime = 0
    this.hooks.flashHint(this.scriptStore.recordMsg)
  }

  stopRecording(): void {
    if (this.tools.recordingPaused && this.recordPausedAt > 0) {
      this.recordPausedTotal += Date.now() - this.recordPausedAt
      this.recordPausedAt = 0
    }
    this.tools.recording = false
    this.cancelRecordingViewCheckpoint()
    this.tools.recordingPaused = false
    this.tools.recordingUiExpanded = true
    this.scriptStore.recordCount = this.hooks.recordBufferLength()
    this.scriptStore.recordMsg = this.scriptStore.recordCount > 0 ? '已停止，可保存' : '已停止（没有可保存的操作）'
    this.hooks.flashHint(this.scriptStore.recordMsg)
    this.hooks.openScriptsPanel()
  }

  saveCurrentRecording(): void {
    if (this.hooks.recordBufferLength() === 0) {
      this.scriptStore.recordMsg = '没有可保存的操作，请先开始录制'
      this.hooks.flashHint(this.scriptStore.recordMsg)
      return
    }
    const safeName = this.scriptStore.recordName.trim().replace(/\|/g, '_').replace(/\n/g, ' ')
    const payload = safeName + '|' + JSON.stringify(this.hooks.recordBufferSnapshot())
    this.port.requestInteractive('saveRecording', payload, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.scriptStore.recordMsg = '已保存：' + (r.name ?? this.scriptStore.recordName)
        this.hooks.flashHint(this.scriptStore.recordMsg)
        this.hooks.recordBufferClear()
        this.scriptStore.recordCount = 0
        this.scriptStore.recordName = ''
        this.hooks.loadRecordings()
      } else {
        this.scriptStore.recordMsg = '保存失败：' + (r.error ?? '未知错误')
        this.hooks.flashHint(this.scriptStore.recordMsg)
      }
    })
  }

  playRecording(file: string): void {
    if (this.hooks.sessionBusy()) {
      this.hooks.flashHint('已有脚本或回放正在运行')
      return
    }
    this.port.requestInteractive('loadRecording', file, (r: StellariumBridgeResponse) => {
      const resp = r as RecordingDetailResponse
      const cmds = resp.commands ?? []
      if (cmds.length === 0) {
        this.hooks.flashHint(I18n.t('msg_recording_empty'))
        return
      }
      this.scriptStore.replaying = true
      this.scriptStore.replayPaused = false
      this.scriptStore.replayRate = 1
      this.scriptStore.replayName = resp.name ?? file
      this.replayCommands = cmds
      this.replayIndex = 0
      this.replayStartedAt = Date.now()
      this.replayPauseStartedAt = 0
      this.replayPausedTotal = 0
      this.hooks.flashHint('正在回放 ' + cmds.length + ' 条命令…')
      this.replayNextCommand()
    })
  }

  private replayNextCommand(): void {
    if (!this.scriptStore.replaying || this.scriptStore.replayPaused) { return }
    if (this.replayIndex >= this.replayCommands.length) {
      this.finishRecordingReplay('回放完成')
      return
    }
    const commandItem = this.replayCommands[this.replayIndex]
    const fallbackTime = this.replayIndex * 40
    const targetTime = typeof commandItem.t === 'number' && Number.isFinite(commandItem.t)
      ? Math.max(0, commandItem.t) : fallbackTime
    const timelineElapsed = this.scriptStore.replayTimelineMs(this.replayPauseStartedAt, this.replayStartedAt, this.replayPausedTotal)
    const delay = Math.max(0, (targetTime - timelineElapsed) / Math.max(0.25, this.scriptStore.replayRate))
    this.replayTimer = setTimeout(() => {
      if (!this.scriptStore.replaying) { return }
      this.replayIndex++
      this.port.requestWhenReady(commandItem.c, commandItem.p, () => {
        this.replayNextCommand()
      }, () => {
        this.finishRecordingReplay('回放中断：命令执行失败')
      }, 0, 100, 15)
    }, delay) as number
  }

  finishRecordingReplay(message: string): void {
    if (this.replayTimer >= 0) {
      clearTimeout(this.replayTimer)
      this.replayTimer = -1
    }
    this.scriptStore.replaying = false
    this.scriptStore.replayPaused = false
    this.scriptStore.replayRate = 1
    this.scriptStore.replayName = ''
    this.replayCommands = []
    this.replayIndex = 0
    this.replayPauseStartedAt = 0
    this.replayPausedTotal = 0
    this.hooks.flashHint(message)
  }

  toggleReplayPause(): void {
    if (!this.scriptStore.replaying) { return }
    if (this.scriptStore.replayPaused) {
      if (this.replayPauseStartedAt > 0) {
        this.replayPausedTotal += Date.now() - this.replayPauseStartedAt
      }
      this.replayPauseStartedAt = 0
      this.scriptStore.replayPaused = false
      this.hooks.flashHint('回放继续')
      this.replayNextCommand()
      return
    }
    if (this.replayTimer >= 0) {
      clearTimeout(this.replayTimer)
      this.replayTimer = -1
    }
    this.replayPauseStartedAt = Date.now()
    this.scriptStore.replayPaused = true
    this.hooks.flashHint('回放已暂停')
  }

  changePlaybackRate(direction: number): void {
    if (this.scriptStore.replaying) {
      const next = Math.max(0.25, Math.min(16, this.scriptStore.replayRate * (direction > 0 ? 2 : 0.5)))
      const timeline = this.scriptStore.replayTimelineMs(this.replayPauseStartedAt, this.replayStartedAt, this.replayPausedTotal)
      const anchor = this.scriptStore.replayPaused && this.replayPauseStartedAt > 0
        ? this.replayPauseStartedAt : Date.now()
      this.scriptStore.replayRate = next
      this.replayStartedAt = anchor - this.replayPausedTotal - timeline / next
      if (this.replayTimer >= 0) {
        clearTimeout(this.replayTimer)
        this.replayTimer = -1
      }
      this.replayNextCommand()
      return
    }
    this.hooks.changeScriptRate(direction)
  }

  deleteRecording(file: string): void {
    this.port.requestInteractive('deleteRecording', file, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.hooks.flashHint(I18n.t('msg_recording_deleted'))
        this.hooks.loadRecordings()
      } else {
        this.hooks.flashHint(I18n.t('msg_delete_failed'))
      }
    })
  }

  // ===== 视频帧序列录制（纯星图高质量导出）=====
  startVideoRecording(): void {
    const fps = parseInt(this.scriptStore.videoFps, 10) || 1
    const duration = parseInt(this.scriptStore.videoDuration, 10) || 5
    this.port.requestInteractive('startVideoRecording', fps + '|' + duration, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.scriptStore.videoRecording = true
        this.scriptStore.videoDir = r.dir !== undefined ? r.dir : ''
        this.scriptStore.videoFrameCount = 0
        this.scriptStore.videoFailedFrames = 0
        this.scriptStore.videoMaxFrames = r.maxFrames !== undefined ? r.maxFrames : 0
        this.scriptStore.videoArchivePath = ''
        this.scriptStore.videoArchiveFileName = ''
        this.hooks.startVideoStatePolling()
        this.hooks.flashHint('开始录制视频帧序列：' + fps + ' fps × ' + duration + ' s')
      } else {
        this.hooks.flashHint('开始录制失败：' + (r.error ?? '未知错误'))
      }
    })
  }

  stopVideoRecording(): void {
    this.port.requestInteractive('stopVideoRecording', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.scriptStore.videoRecording = false
        this.hooks.stopVideoStatePolling()
        const diskFrames = r.diskFrames
        const frameCount = r.frameCount
        this.scriptStore.videoFrameCount = diskFrames !== undefined ? diskFrames : (frameCount !== undefined ? frameCount : 0)
        this.scriptStore.videoFailedFrames = r.failedFrames !== undefined ? r.failedFrames : 0
        this.scriptStore.videoDir = r.dir !== undefined ? r.dir : ''
        this.scriptStore.videoArchivePath = r.archivePath !== undefined ? r.archivePath : ''
        this.scriptStore.videoArchiveFileName = r.archiveFileName !== undefined ? r.archiveFileName : ''
        this.hooks.flashHint(this.scriptStore.videoArchivePath.length > 0 ?
          '已停止，共 ' + this.scriptStore.videoFrameCount + ' 帧，ZIP 已生成' :
          '已停止，共 ' + this.scriptStore.videoFrameCount + ' 帧，但 ZIP 生成失败')
      } else {
        this.hooks.flashHint('停止录制失败')
      }
    })
  }

  // ===== 系统屏幕录制（MP4）=====
  async startScreenVideoRecording(): Promise<void> {
    if (this.scriptStore.screenVideoRecording || this.scriptStore.screenCaptureFinalizing) { return }
    try {
      const dir = this.mediaPort.screenVideoDir()
      this.mediaPort.makeDir(dir)
      this.scriptStore.screenVideoFileName = 'stellarium-screen-' + Date.now().toString() + '.mp4'
      this.scriptStore.screenVideoPath = dir + '/' + this.scriptStore.screenVideoFileName
      this.scriptStore.screenVideoBytes = 0
      this.scriptStore.screenVideoStatus = '等待系统录屏授权…'
      await this.mediaPort.beginScreenCapture(this.scriptStore.screenVideoPath,
        (state: ScreenCaptureState): void => { this.onScreenCaptureState(state) },
        (message: string): void => { void this.finalizeScreenVideo(message) })
    } catch (error) {
      hilog.error(0x0000, 'StellariumArkUI', 'Start screen capture failed: %{public}s', String(error))
      await this.finalizeScreenVideo('无法开始录屏')
    }
  }

  private onScreenCaptureState(state: ScreenCaptureState): void {
    if (state === ScreenCaptureState.Started) {
      this.scriptStore.screenVideoRecording = true
      this.scriptStore.screenVideoStatus = '正在录制 MP4'
    } else if (state === ScreenCaptureState.Canceled) {
      void this.finalizeScreenVideo('用户取消了录屏授权')
    } else if (state === ScreenCaptureState.StoppedByUser) {
      void this.finalizeScreenVideo('MP4 已生成，可保存到相册或分享')
    } else {
      void this.finalizeScreenVideo('录屏已被系统中断，已保留现有视频')
    }
  }

  private async finalizeScreenVideo(message: string): Promise<void> {
    if (this.scriptStore.screenCaptureFinalizing) { return }
    this.scriptStore.screenCaptureFinalizing = true
    await this.mediaPort.releaseScreenCapture()
    this.scriptStore.screenVideoRecording = false
    this.scriptStore.screenVideoBytes = this.scriptStore.screenVideoPath.length > 0 ? this.mediaPort.fileSize(this.scriptStore.screenVideoPath) : 0
    this.scriptStore.screenVideoStatus = this.scriptStore.screenVideoBytes > 0 ? message : '录屏没有生成有效视频'
    this.scriptStore.screenCaptureFinalizing = false
    this.hooks.flashHint(this.scriptStore.screenVideoStatus)
  }

  async stopScreenVideoRecording(): Promise<void> {
    if (!this.mediaPort.hasActiveScreenCapture() || this.scriptStore.screenCaptureFinalizing) { return }
    this.scriptStore.screenCaptureFinalizing = true
    await this.mediaPort.stopScreenCapture()
    this.scriptStore.screenVideoRecording = false
    this.scriptStore.screenVideoBytes = this.mediaPort.fileSize(this.scriptStore.screenVideoPath)
    this.scriptStore.screenVideoStatus = this.scriptStore.screenVideoBytes > 0 ? 'MP4 已生成，可保存到相册或分享' : '录屏没有生成有效视频'
    this.scriptStore.screenCaptureFinalizing = false
    this.hooks.flashHint(this.scriptStore.screenVideoStatus)
  }

  // authorized = 用户在 SaveButton 上授予了临时相册写权限（宿主侧 SaveButtonOnClickResult.SUCCESS）。
  async saveScreenVideoToGallery(authorized: boolean): Promise<void> {
    if (!authorized || this.scriptStore.screenVideoPath.length === 0) {
      this.hooks.flashHint('未获得保存到相册的临时授权')
      return
    }
    const saved = await this.mediaPort.saveVideoToGallery(this.scriptStore.screenVideoPath)
    this.hooks.flashHint(saved ? '视频已保存到相册' : '保存到相册失败')
  }
}
