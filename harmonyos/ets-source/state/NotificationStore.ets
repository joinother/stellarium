// 通知 / 后台提醒域状态 store：持有通知授权、忙碌标志、已注册提醒数与状态文案。
// 消费方以 @ObjectLink 订阅；字段随用户操作与系统回调更新，宿主与组件的刷新语义不变。
@Observed
export class NotificationStore {
  astronomyNotificationEnabled: boolean = false
  astronomyNotificationBusy: boolean = false
  astronomyReminderCount: number = 0
  astronomyNotificationStatus: string = '尚未检查通知权限'
  // 通知类别与偏好（对应设置页「通知」卡片）。目前只有「天文事件」类别会真正注册提醒，
  // 「卫星通过」「观测建议」先持久化用户选择，等对应调度实现后再消费。
  astronomyEventsEnabled: boolean = true
  satellitePassEnabled: boolean = true
  digestEnabled: boolean = true
  dndEnabled: boolean = true
  dndStartMinutes: number = 22 * 60 + 30
  dndEndMinutes: number = 6 * 60 + 35
  passLeadMinutes: number = 5
}
