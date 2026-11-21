import { AstronomyReminderItem } from '../qability/AstronomyReminderService'

// 通知授权、订阅偏好与提醒列表 UI 状态（设置页 NotificationSection 及日历/小组件共用）。
@Observed
export class NotificationStore {
  astronomyNotificationEnabled: boolean = false
  astronomyNotificationBusy: boolean = false
  astronomyReminderCount: number = 0
  astronomyNotificationStatus: string = ''
  astronomyEventsEnabled: boolean = false
  satellitePassEnabled: boolean = false
  digestEnabled: boolean = false
  // 细分主题开关（默认与天文事件主开关一致，支持懒人一键预设或按主题自由开关）
  topicMeteor: boolean = false
  topicPlanet: boolean = false
  topicMoon: boolean = false
  topicSolarTerm: boolean = false
  subscriptionHighlightOnly: boolean = false
  // 通知时机策略：'smart'（按天象最佳观测窗口）| 'day_before'（提前一天傍晚预告）| 'just_in_time'（临场前 1 小时）
  timingMode: string = 'smart'
  // 通知地理区域：'follow' 跟随当前星图位置，或独立区域 ID（如 'beijing', 'sydney'）
  regionId: string = 'follow'
  // 默认 22:30–06:30 仅拦截卫星过境（不拦截深夜/前瞻天文事件）
  dndEnabled: boolean = true
  dndSatelliteOnly: boolean = true
  dndStartMinutes: number = 22 * 60 + 30
  dndEndMinutes: number = 6 * 60 + 30
  passLeadMinutes: number = 10
  astronomyReminders: AstronomyReminderItem[] = []
  astronomyReminderListLoaded: boolean = false
  astronomyReminderListError: string = ''
  notificationPreferencesLoaded: boolean = false
  notificationPreferencesBusy: boolean = false
  notificationPreferencesError: string = ''
  subscriptionBusy: boolean = false
  astronomySubscriptionStatus: string = ''
  satelliteSubscriptionStatus: string = ''
  astronomySubscriptionOk: boolean = false
  satelliteSubscriptionOk: boolean = false
  // 统一已预约事件 ID 列表（涵盖订阅、日历单场预约、以及桌面小组件预约，规范化后用于双向状态同步）
  remindedEventIds: string[] = []
  pushTokenText: string = ''
}
