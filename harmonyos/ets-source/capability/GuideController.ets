// 「交互导览 / 语音播报」行为控制器：导览播放器（GuidePlayer）会话、导览状态回包、请求序号
// 与 250ms tick 定时器、面板/陀螺仪/星图惯性等跨域收口动作。
//
// 依赖 GuideStore（纯状态：guideState / speechStatus，控制器只整体赋值）、CommandPort（导览桥经
// requestInteractive）与 GuideControllerHooks
// 回注的宿主行为（flashHint / publishGuideState / 会话忙判定 / 面板与陀螺仪控制 / 后台任务互斥 /
// 刷新与重载 / animateTo）。控制器不 import UI 上下文，animateTo 由 hooks 注入。
//
// tick 定时器（250ms）自持 startGuideTimer/stopGuideTimer，由宿主生命周期收口
// （aboutToAppear 构造 / 导览结束回包 / aboutToDisappear）。
import { GuidePlayer, GuideState, GuideResult, AstronomyGuide, ASTRONOMY_GUIDES } from '../common/derive/AstronomyGuide'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'
import { GuideStore } from '../state/GuideStore'

// 宿主 → 控制器回注（store 不 import UI / 他 store）。
export interface GuideControllerHooks {
  flashHint(text: ResourceStr): void
  publishGuideState(): void
  // 是否已有脚本/录制裁会话（宿主聚合 tools.recording 与 guideState.active）。
  sessionBusy(): boolean
  polarScopeVisible(): boolean
  panelVisible(): boolean
  setPanelVisible(value: boolean): void
  hideInfoWindow(): void
  applicationInForeground(): boolean
  gyroscopeEnabled(): boolean
  setGyroscopeEnabled(value: boolean): void
  startGyroscope(): void
  stopGyroscope(updateStatus: boolean): void
  stopSkyInertia(): void
  // 停止与导览互斥的宿主后台任务（详情自动刷新 / 时间面板 / 星空文化时间跟随 / 天文计算上下文 / 望远镜实时位置）。
  stopCompetingTasks(): void
  refreshState(): void
  reloadObserverInfo(): void
  // 在 animateTo 动画中应用导览状态（控制器不触碰 UI 上下文）。
  animateTo(action: () => void): void
}

export class GuideController {
  private store: GuideStore
  private port: CommandPort
  private hooks: GuideControllerHooks

  // —— 导览引擎 / 请求 / 定时器（私有，不入被观察语义） ——
  private guidePlayer: GuidePlayer | undefined = undefined
  private guideTimer: number = -1
  private guideGyroWasEnabled: boolean = false
  private guidePanelWasVisible: boolean = false
  private guideLastRequest: string = ''
  private guideLastResult: GuideResult = { ok: true }

  constructor(port: CommandPort, store: GuideStore, hooks: GuideControllerHooks) {
    this.port = port
    this.store = store
    this.hooks = hooks
  }

  // CLI 状态读取（宿主 publishGuideState 用）：最近一次导览请求序号与结果。
  lastRequestId(): string { return this.guideLastRequest }
  lastResult(): GuideResult { return this.guideLastResult }

  // 宿主生命周期收口：清空进入导览前保存的陀螺仪/面板可见性快照。
  resetJourneyFlags(): void {
    this.guideGyroWasEnabled = false
    this.guidePanelWasVisible = false
  }

  // 导览 tick 定时器：每 250ms 在前台时推进播放器 0.25；由本控制器自持 start/stop。
  startGuideTimer(): void {
    const hooks = this.hooks
    this.stopGuideTimer()
    this.guideTimer = setInterval(() => {
      if (hooks !== null && hooks.applicationInForeground()) this.guidePlayer?.tick(0.25)
    }, 250) as number
  }

  stopGuideTimer(): void {
    if (this.guideTimer >= 0) {
      clearInterval(this.guideTimer)
      this.guideTimer = -1
    }
  }

  // 宿主生命周期收口：停止播放器与定时器（aboutToDisappear / 后台切换时调用）。
  stopPlayer(): void {
    this.guidePlayer?.stop()
  }

  pausePlayer(): void {
    this.guidePlayer?.action('pause')
  }

  // 执行导览请求：桥经 port.requestInteractive，导览状态回包经 hooks.animateTo（不触碰 UI 上下文），
  // 面板/陀螺仪等动作经 hooks 具名回注，tick 定时器由本控制器自持。
  async executeGuideRequest(commandName: string, payload: string, requestId: string = ''): Promise<void> {
    const hooks = this.hooks
    const port = this.port
    if (hooks === null || port === null) {
      return
    }
    if (!this.guidePlayer) {
      this.guidePlayer = new GuidePlayer((name: string, value: string): Promise<GuideResult> => {
        return new Promise<GuideResult>((resolve) => {
          port.requestInteractive(name, value,
            (response: StellariumBridgeResponse) => resolve({ ok: response.ok === true, error: response.error }),
            () => resolve({ ok: false, error: 'bridge_timeout' }))
        })
      }, (state: GuideState) => {
        const ended = this.store.guideState.active && !state.active
        if (this.store.guideState.phase !== state.phase || this.store.guideState.index !== state.index) {
          hooks.animateTo(() => { this.store.guideState = state })
        } else {
          this.store.guideState = state
        }
        hooks.publishGuideState()
        if (ended) {
          this.stopGuideTimer()
          hooks.setPanelVisible(this.guidePanelWasVisible)
          if (this.guideGyroWasEnabled && hooks.applicationInForeground()) {
            hooks.setGyroscopeEnabled(true)
            hooks.startGyroscope()
          }
          this.guideGyroWasEnabled = false
          hooks.refreshState()
          hooks.reloadObserverInfo()
        }
      })
    }
    let result: GuideResult
    if (commandName === 'startGuide') {
      if (hooks.sessionBusy() || hooks.polarScopeVisible() || !ASTRONOMY_GUIDES.some((guide: AstronomyGuide): boolean => guide.id === payload)) {
        result = { ok: false, error: 'session_busy_or_unknown_guide' }
      } else {
        this.guidePanelWasVisible = hooks.panelVisible()
        this.guideGyroWasEnabled = hooks.gyroscopeEnabled()
        hooks.stopGyroscope(false)
        hooks.setGyroscopeEnabled(false)
        hooks.stopSkyInertia()
        hooks.setPanelVisible(false)
        hooks.hideInfoWindow()
        hooks.stopCompetingTasks()
        this.startGuideTimer()
        result = await this.guidePlayer.start(payload)
      }
    } else {
      if (['return', 'next', 'previous', 'stop', 'retry', 'center', 'closer', 'wider'].includes(payload)) {
        hooks.stopSkyInertia()
      }
      result = await this.guidePlayer.action(payload)
    }
    this.guideLastRequest = requestId
    this.guideLastResult = result
    hooks.publishGuideState()
    if (!result.ok) hooks.flashHint(I18n.t('guide_error'))
  }
}
