// Push Kit：获取设备 Push Token。
//
// 用途：实况窗的远程更新（Push Kit 通道）需要服务端持有 Push Token 才能下发；
// 本地更新（liveViewManager.updateLiveView）不需要 Token，但正式方案里
// 应用退后台后只能靠 Push 更新，所以先把 Token 通道打通。
//
// 前提：Profile 必须包含 push.base_service（调试 Profile 已有）。
import { pushService } from '@kit.PushKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent'

export interface PushTokenResult {
  ok: boolean
  token?: string
  error?: string
  code?: number
}

export class PushTokenFetcher {
  public static async getToken(): Promise<PushTokenResult> {
    if (!hasCurrentPrivacyConsent()) return { ok: false, error: 'privacy-consent-required' }
    try {
      const token: string = await pushService.getToken()
      if (!hasCurrentPrivacyConsent()) return { ok: false, error: 'privacy-consent-required' }
      return { ok: true, token: token }
    } catch (error) {
      const err = error as BusinessError
      console.error('[Push] getToken failed: ' + err.code + ' ' + err.message)
      return { ok: false, error: err.message, code: err.code }
    }
  }
}
