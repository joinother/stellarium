// 通知 / 后台提醒域状态 store：持有通知授权、忙碌标志、已注册提醒数与状态文案。
// 消费方以 @ObjectLink 订阅；字段随用户操作与系统回调更新，宿主与组件的刷新语义不变。
@Observed
export class NotificationStore {
  astronomyNotificationEnabled: boolean = false
  astronomyNotificationBusy: boolean = false
  astronomyReminderCount: number = 0
  astronomyNotificationStatus: string = '尚未检查通知权限'
}
