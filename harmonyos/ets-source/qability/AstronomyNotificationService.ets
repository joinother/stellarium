import { notificationManager } from '@kit.NotificationKit'
import { common, wantAgent } from '@kit.AbilityKit'
import { hasCurrentPrivacyConsent } from './PrivacyConsent'
import { NotificationPolicyInput, AstronomyServiceResult, validateNotification, validServiceId, serviceFailure } from './AstronomyNotificationPolicy'

export { AstronomyRoute } from './AstronomyNotificationPolicy'

export interface AstronomyNotificationPayload extends NotificationPolicyInput {}

export class AstronomyNotificationService {
  private static queue: Promise<void> = Promise.resolve()

  private static serial<T>(operation: () => Promise<T>): Promise<T> {
    const result = AstronomyNotificationService.queue.then(operation)
    AstronomyNotificationService.queue = result.then(() => {}, () => {})
    return result
  }

  public static async status(): Promise<AstronomyServiceResult> {
    try {
      return { ok: true, notificationEnabled: await notificationManager.isNotificationEnabled() }
    } catch (error) {
      return serviceFailure(error, '无法读取通知状态')
    }
  }

  public static async isEnabled(): Promise<boolean> {
    return (await AstronomyNotificationService.status()).notificationEnabled === true
  }

  public static async requestAuthorization(context: common.UIAbilityContext): Promise<boolean> {
    try {
      if (!hasCurrentPrivacyConsent()) return false
      await notificationManager.requestEnableNotification(context)
      return await AstronomyNotificationService.isEnabled()
    } catch (error) {
      return false
    }
  }

  public static async publish(payload: AstronomyNotificationPayload, bundleName: string = ''): Promise<boolean> {
    const validation = validateNotification(payload)
    if (!validation.ok || validation.value === undefined) return false
    const value = validation.value
    if (value.route !== undefined && (typeof bundleName !== 'string' || !/^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/.test(bundleName))) return false
    return AstronomyNotificationService.serial(async (): Promise<boolean> => {
      try {
        if (!hasCurrentPrivacyConsent()) return false
        if (!await AstronomyNotificationService.isEnabled()) return false
        const request: notificationManager.NotificationRequest = value.lines !== undefined
          ? {
              id: value.id,
              content: {
                notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_MULTILINE,
                multiLine: {
                  title: value.title, text: value.text, briefText: value.title,
                  longTitle: value.title, lines: value.lines, additionalText: value.additionalText ?? ''
                }
              }
            } : {
              id: value.id,
              content: {
                notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
                normal: { title: value.title, text: value.text, additionalText: value.additionalText ?? '' }
              }
            }
        if (value.route !== undefined) {
          const route = value.route
          const parameters: Record<string, Object> = {}
          parameters['panel'] = route.panel ?? 'astro'
          parameters['tab'] = route.tab ?? 8
          parameters['eventId'] = route.eventId ?? ''
          parameters['kind'] = route.kind ?? 'astronomy'
          parameters['target'] = route.target ?? ''
          if (route.eventAt !== undefined) parameters['eventAt'] = route.eventAt
          if (route.jd !== undefined) parameters['jd'] = route.jd
          const info: wantAgent.WantAgentInfo = {
            wants: [{ bundleName: bundleName, abilityName: 'QAbility',
              uri: 'skyinstrument://astronomy/notification/' + value.id.toString(), parameters: parameters }],
            actionType: wantAgent.OperationType.START_ABILITY, requestCode: value.id,
            actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
          }
          request.wantAgent = await wantAgent.getWantAgent(info)
          if (request.wantAgent === undefined || request.wantAgent === null) return false
        }
        if (!hasCurrentPrivacyConsent()) return false
        await notificationManager.publish(request)
        return true
      } catch (error) {
        return false
      }
    })
  }

  public static async cancel(id: number): Promise<boolean> {
    if (!validServiceId(id)) return false
    return AstronomyNotificationService.serial(async (): Promise<boolean> => {
      try {
        await notificationManager.cancel(id)
        return true
      } catch (error) {
        return false
      }
    })
  }
}
