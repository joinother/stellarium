// 通知 / 后台提醒控制器。
//
// 把 HarmonyOS 通知授权与后台代理提醒（reminderAgentManager）封装为 UI 可调用的四个动作，
// 并把结果写回 @Observed NotificationStore。本类不 import NAPI/UI：服务调用走
// AstronomyNotificationService / AstronomyReminderService（@kit.* 封装），UI 提示、宿主 UIAbility
// 上下文与年历节气数据经 NotificationHostHooks 回注。
import { common } from '@kit.AbilityKit'
import { AstronomyNotificationService } from '../qability/AstronomyNotificationService'
import { AstronomyReminderService, AstronomyReminderRequest } from '../qability/AstronomyReminderService'
import { NotificationStore } from '../state/NotificationStore'
import { MoonPhaseItem, SeasonEvent } from '../common/types/StellariumTypes'
import { MeteorShowerItem } from '../common/types/MainWindowModels'

// 宿主 → 控制器回注：UI 提示、UIAbility 上下文、年历节气快照与加载触发。
export interface NotificationHostHooks {
  flashHint(text: ResourceStr): void
  hostContext(): common.UIAbilityContext
  almanacSolarTerms(): SeasonEvent[]
  loadAlmanac(): void
  moonPhases(): MoonPhaseItem[]
  loadMoonPhases(): void
  meteorShowers(): MeteorShowerItem[]
  loadMeteorShowers(): void
}

export class NotificationController {
  private store: NotificationStore
  private hooks: NotificationHostHooks
  // 「订阅下一节气提醒」的年历就绪重试计数（0 表示未在重试）。
  private solarTermRetryCount: number = 0

  constructor(store: NotificationStore, hooks: NotificationHostHooks) {
    this.store = store
    this.hooks = hooks
  }

  // 查询系统通知授权状态与已注册提醒数，写回 store。
  refreshStatus(): void {
    if (this.store.astronomyNotificationBusy) return
    this.store.astronomyNotificationBusy = true
    AstronomyReminderService.status().then((status) => {
      this.store.astronomyNotificationBusy = false
      this.store.astronomyNotificationEnabled = status.notificationEnabled === true
      this.store.astronomyReminderCount = status.reminderCount ?? 0
      this.store.astronomyNotificationStatus = status.ok === true
        ? (this.store.astronomyNotificationEnabled ? '通知已开启' : '通知未授权')
        : (status.error ?? '通知状态暂时不可用')
    }).catch(() => {
      this.store.astronomyNotificationBusy = false
      this.store.astronomyNotificationStatus = '通知状态暂时不可用'
    })
  }

  // 请求系统通知授权（用户主动触发），完成后回读状态。
  requestAccess(): void {
    if (this.store.astronomyNotificationBusy) return
    this.store.astronomyNotificationBusy = true
    AstronomyNotificationService.requestAuthorization(this.hooks.hostContext()).then((enabled: boolean) => {
      this.store.astronomyNotificationBusy = false
      this.store.astronomyNotificationEnabled = enabled
      this.store.astronomyNotificationStatus = enabled ? '通知已开启' : '用户尚未开启通知'
      this.refreshStatus()
    }).catch(() => {
      this.store.astronomyNotificationBusy = false
      this.store.astronomyNotificationStatus = '通知授权未完成'
    })
  }

  // 从当前年历节气列表中选取下一节气，注册系统后台代理提醒。
  // 年历是异步计算的：首次点击若尚未就绪，会先触发计算并自动轮询重试，单击即可完成。
  scheduleNextSolarTerm(): void {
    const next = this.hooks.almanacSolarTerms().find((term: SeasonEvent): boolean => {
      const time = new Date(term.date ?? '').getTime()
      return Number.isFinite(time) && time > Date.now() + 30 * 1000
    })
    if (next === undefined) {
      if (this.solarTermRetryCount === 0) {
        this.hooks.flashHint('正在计算下一节气…')
        this.hooks.loadAlmanac()
      }
      if (this.solarTermRetryCount < 40) {
        this.solarTermRetryCount += 1
        setTimeout(() => { this.scheduleNextSolarTerm() }, 300)
        return
      }
      this.solarTermRetryCount = 0
      this.hooks.flashHint('暂未取到节气，请稍后在年历页刷新后重试。')
      return
    }
    this.solarTermRetryCount = 0
    this.store.astronomyNotificationBusy = true
    AstronomyReminderService.schedule({
      at: String(next.date),
      title: '星象仪 · 下一节气',
      content: `${next.label ?? '下一节气'} 即将到来，打开星象仪查看年历和观测信息。`,
      eventId: String(next.key ?? next.label ?? 'solar-term'),
      kind: 'solar-term',
      panel: 'astro',
      tab: 8
    }, this.hooks.hostContext().abilityInfo.bundleName).then((result) => {
      this.store.astronomyNotificationBusy = false
      if (result.ok === true) {
        this.hooks.flashHint('下一节气提醒已交给系统管理。')
        this.refreshStatus()
      } else {
        this.store.astronomyNotificationStatus = result.error ?? '提醒注册失败'
        this.hooks.flashHint(this.store.astronomyNotificationStatus)
      }
    }).catch(() => {
      this.store.astronomyNotificationBusy = false
      this.hooks.flashHint('提醒注册失败，请检查通知权限。')
    })
  }

  // 订阅下一次满月：用月相表里下一个 illumination 最大的“满月”条目。
  scheduleNextMoonPhase(): void {
    const list = this.hooks.moonPhases()
    const now = Date.now() + 30 * 1000
    const next = list.find((item: MoonPhaseItem): boolean => {
      const time = new Date(item.date ?? '').getTime()
      if (!Number.isFinite(time) || time <= now) return false
      const label = item.phase ?? ''
      return label.indexOf('满月') >= 0 || label.toLowerCase().indexOf('full') >= 0
    })
    if (next === undefined) {
      this.hooks.flashHint('正在计算月相…请在月相页加载后重试')
      this.hooks.loadMoonPhases()
      return
    }
    this.scheduleOne({
      at: String(next.date),
      title: '星象仪 · 满月',
      content: '今晚满月，打开星象仪查看月亮升起时间与方位。',
      eventId: 'moon-phase-' + String(next.date),
      kind: 'moon-phase',
      panel: 'astro',
      tab: 2
    })
  }

  // 订阅下一场流星雨：取峰值时间最近且尚未过期的一场。
  scheduleNextMeteorShower(): void {
    const list = this.hooks.meteorShowers()
    const now = Date.now() + 30 * 1000
    let best: MeteorShowerItem | undefined = undefined
    let bestTime = Number.MAX_VALUE
    for (let i = 0; i < list.length; i++) {
      const time = new Date(list[i].peakDate ?? '').getTime()
      if (!Number.isFinite(time) || time <= now) continue
      if (time < bestTime) { bestTime = time; best = list[i] }
    }
    if (best === undefined) {
      this.hooks.flashHint('正在加载流星雨目录…请稍后重试')
      this.hooks.loadMeteorShowers()
      return
    }
    this.scheduleOne({
      at: String(best.peakDate),
      title: '星象仪 · ' + best.name,
      content: best.name + ' 今夜达到峰值（ZHR 约 ' + best.zhr.toString() + '），打开星象仪查看辐射点方位。',
      eventId: 'meteor-' + best.name,
      kind: 'meteor-shower',
      panel: 'astro',
      tab: 4
    })
  }

  // 统一的单条代理提醒注册 + 结果回写。
  private scheduleOne(payload: AstronomyReminderRequest): void {
    if (this.store.astronomyNotificationBusy) return
    this.store.astronomyNotificationBusy = true
    AstronomyReminderService.schedule(payload, this.hooks.hostContext().abilityInfo.bundleName).then((result) => {
      this.store.astronomyNotificationBusy = false
      if (result.ok === true) {
        this.hooks.flashHint('已订阅，交给系统提醒。')
        this.refreshStatus()
      } else {
        this.store.astronomyNotificationStatus = result.error ?? '提醒注册失败'
        this.hooks.flashHint(this.store.astronomyNotificationStatus)
      }
    }).catch(() => {
      this.store.astronomyNotificationBusy = false
      this.hooks.flashHint('提醒注册失败，请检查通知权限。')
    })
  }

  // 清除全部已注册的天象提醒。
  clearReminders(): void {
    if (this.store.astronomyNotificationBusy) return
    this.store.astronomyNotificationBusy = true
    AstronomyReminderService.cancelAll().then((result) => {
      this.store.astronomyNotificationBusy = false
      this.hooks.flashHint(result.ok === true ? '已清除全部天象提醒。' : (result.error ?? '清除提醒失败'))
      this.refreshStatus()
    }).catch(() => {
      this.store.astronomyNotificationBusy = false
      this.hooks.flashHint('清除提醒失败。')
    })
  }
}
