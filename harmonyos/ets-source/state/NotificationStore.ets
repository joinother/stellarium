import { notificationText } from '../capability/NotificationText'
import { AstronomyReminderItem } from '../qability/AstronomyReminderService'

@Observed
export class NotificationStore {
  astronomyNotificationEnabled: boolean = false
  astronomyNotificationBusy: boolean = false
  astronomyReminderCount: number = 0
  astronomyNotificationStatus: string = notificationText('尚未检查通知权限')
  astronomyReminders: AstronomyReminderItem[] = []
  astronomyReminderListLoaded: boolean = false
  astronomyReminderListError: string = ''
  notificationPreferencesLoaded: boolean = false
  notificationPreferencesBusy: boolean = false
  notificationPreferencesError: string = ''
  astronomyEventsEnabled: boolean = false
  satellitePassEnabled: boolean = false
  digestEnabled: boolean = false
  astronomySubscriptionStatus: string = ''
  satelliteSubscriptionStatus: string = ''
  subscriptionBusy: boolean = false
  astronomySubscriptionOk: boolean = false
  satelliteSubscriptionOk: boolean = false
  dndEnabled: boolean = true
  dndStartMinutes: number = 22 * 60 + 30
  dndEndMinutes: number = 6 * 60 + 35
  passLeadMinutes: number = 5
}
