// 实况窗（Live View）接入：计时（TIMER）场景。
//
// 能力说明（2026-11-09 AGC 已开通，属"调试权限"）：
//  - 只有在 AGC「白名单设备管理」里登记过的设备才能看到效果；
//  - 正式上线前还要提交现网效果截图走"正式权限"评审；
//  - Profile 需重新生成并打包，否则能力不生效。
//
// 设计规范（计时场景）要点：
//  - 只有「计时中」一个节点；
//  - 卡片辅助区必须明确显示"计时中"，不能让用户误判状态；
//  - 用户主动终止计时 → 立即结束实况窗；
//  - 计时仅端侧创建与更新，不经过服务端。
import { liveViewManager } from '@kit.LiveViewKit'
import { wantAgent, WantAgent } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'

export interface LiveViewStartResult {
  ok: boolean
  error?: string
  code?: number
}

export class LiveViewController {
  // 固定 id：倒计时是单实例业务，重复 start 会覆盖而不是叠加。
  private static readonly LIVE_VIEW_ID = 1001
  private sequence: number = 1
  private running: boolean = false
  private bundleName: string = 'com.joinother.skyinstrument'
  private abilityName: string = 'QAbility'

  constructor(private context: common.UIAbilityContext | undefined) {}

  // AGC 的「实况窗」总开关 + 设备白名单，任一不满足都会创建失败。
  public async isEnabled(): Promise<boolean> {
    try {
      return await liveViewManager.isLiveViewEnabled()
    } catch (error) {
      const err = error as BusinessError
      console.error('[LiveView] isLiveViewEnabled failed: ' + err.code + ' ' + err.message)
      return false
    }
  }

  // 开始计时：用户在卫星面板点「开始」时调用。
  public async start(targetLabel: string, totalSeconds: number): Promise<LiveViewStartResult> {
    if (!(await this.isEnabled())) {
      return { ok: false, error: 'live view disabled' }
    }
    try {
      const view = await this.buildView(targetLabel, totalSeconds)
      await liveViewManager.startLiveView(view)
      this.running = true
      this.sequence = 2
      return { ok: true }
    } catch (error) {
      const err = error as BusinessError
      console.error('[LiveView] startLiveView failed: ' + err.code + ' ' + err.message)
      return { ok: false, error: err.message, code: err.code }
    }
  }

  // 每秒更新剩余时间：胶囊用计时器模板，由系统自行走秒，这里只同步卡片文案。
  public async update(targetLabel: string, remainingSeconds: number): Promise<void> {
    if (!this.running) return
    try {
      await liveViewManager.updateLiveView(await this.buildView(targetLabel, remainingSeconds))
      this.sequence += 1
    } catch (error) {
      const err = error as BusinessError
      console.error('[LiveView] updateLiveView failed: ' + err.code + ' ' + err.message)
    }
  }

  // 用户点「停止」或切换目标 → 立即结束（设计规范硬要求）。
  public async stop(): Promise<void> {
    if (!this.running) return
    this.running = false
    try {
      await liveViewManager.stopLiveView(LiveViewController.LIVE_VIEW_ID)
    } catch (error) {
      const err = error as BusinessError
      console.error('[LiveView] stopLiveView failed: ' + err.code + ' ' + err.message)
    }
  }

  public isRunning(): boolean {
    return this.running
  }

  private async buildView(targetLabel: string, seconds: number): Promise<liveViewManager.LiveView> {
    const mm = Math.floor(Math.max(0, seconds) / 60)
    const ss = Math.max(0, seconds) % 60
    const text = mm.toString().padStart(2, '0') + ':' + ss.toString().padStart(2, '0')
    const view: liveViewManager.LiveView = {
      id: LiveViewController.LIVE_VIEW_ID,
      event: 'TIMER',            // 计时场景（AGC 已开通）
      isMute: true,              // 每秒更新不应反复提醒
      liveViewData: {
        primary: {
          title: targetLabel + ' 倒计时',
          content: [
            { text: '计时中' },
            { text: ' · 剩余 ' + text }
          ],
          keepTime: 0,
          clickAction: await this.buildClickAction()
        },
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_CAPSULE_TIMER,
          status: 1,
          backgroundColor: '#FF0A59F7',
          title: targetLabel
        }
      }
    }
    return view
  }

  // 点击胶囊/卡片回到应用。
  private async buildClickAction(): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: this.bundleName,
          abilityName: this.abilityName
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    return await wantAgent.getWantAgent(info)
  }
}
