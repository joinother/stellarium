// 基于 HarmonyOS Device Security Kit (safetyDetect.checkUrlThreat) 的外部网址安全检测。
// - 内置可信域名（镜像站/天文台/开源协议/应用市场等）直接放行，零网络延迟。
// - 用户自定义的外部 http/https 链接（如自定义 TLE 数据源、非白名单外链）异步走云端恶意 URL 检测；
//   命中 MALWARE / PHISHING / OTHERS 时返回 allowed=false 拦截并提示风险。
// - 离线、设备不支持、权限未开通（如旧 Release Profile）或超时（2.5s）时降级放行，不阻塞核心功能。
import { safetyDetect } from '@kit.DeviceSecurityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const LOG_DOMAIN = 0x0000
const LOG_TAG = 'StellariumSafety'
const URL_CHECK_TIMEOUT_MS = 2500

export type UrlSafetyThreat = 'normal' | 'malware' | 'phishing' | 'other' | 'unavailable'

export interface UrlSafetyCheckResult {
  allowed: boolean
  threat: UrlSafetyThreat
  code?: number
}

const TRUSTED_HOST_SUFFIXES: string[] = [
  'skyinstrument.cn',
  'celestrak.org',
  'celestrak.com',
  'stellarium.org',
  'github.com',
  'sourceforge.net',
  'beian.miit.gov.cn',
  'appgallery.huawei.com',
  'doi.org',
  'qt.io',
  'amsat.org',
  'mmccants.org',
  'db.satnogs.org'
]

function extractHostname(rawUrl: string): string {
  const trimmed = rawUrl.trim()
  const match = /^https?:\/\/([^/?#:]+)/i.exec(trimmed)
  if (!match || match.length < 2) {
    return ''
  }
  return match[1].toLowerCase()
}

export function isTrustedBuiltinUrl(rawUrl: string): boolean {
  const host = extractHostname(rawUrl)
  if (host.length === 0) {
    return true
  }
  for (let i = 0; i < TRUSTED_HOST_SUFFIXES.length; i++) {
    const suffix = TRUSTED_HOST_SUFFIXES[i]
    if (host === suffix || host.endsWith('.' + suffix)) {
      return true
    }
  }
  return false
}

export function urlThreatMessage(threat: UrlSafetyThreat, isZh: boolean): string {
  if (threat === 'phishing') {
    return isZh ? '安全检测拦截：该链接疑似钓鱼网站，已拒绝保存或打开。' : 'Blocked by Device Security: suspected phishing URL.'
  }
  if (threat === 'malware') {
    return isZh ? '安全检测拦截：该链接存在恶意风险，已拒绝保存或打开。' : 'Blocked by Device Security: suspected malware URL.'
  }
  return isZh ? '安全检测拦截：该链接存在安全风险，已拒绝保存或打开。' : 'Blocked by Device Security: unsafe URL detected.'
}

export async function checkExternalUrlSafety(rawUrl: string): Promise<UrlSafetyCheckResult> {
  const url = rawUrl.trim()
  if (!/^https?:\/\//i.test(url) || url.length > 4096) {
    return { allowed: true, threat: 'normal' }
  }
  if (isTrustedBuiltinUrl(url)) {
    return { allowed: true, threat: 'normal' }
  }
  if (!canIUse('SystemCapability.Security.SafetyDetect')) {
    return { allowed: true, threat: 'unavailable' }
  }
  const req: safetyDetect.UrlCheckRequest = { urls: [url] }
  let timerId: number = -1
  const timeoutPromise: Promise<UrlSafetyCheckResult> = new Promise<UrlSafetyCheckResult>((resolve) => {
    timerId = setTimeout(() => {
      resolve({ allowed: true, threat: 'unavailable' })
    }, URL_CHECK_TIMEOUT_MS)
  })
  const detectPromise: Promise<UrlSafetyCheckResult> = safetyDetect.checkUrlThreat(req)
    .then((response: safetyDetect.UrlCheckResponse): UrlSafetyCheckResult => {
      const first = response && response.results && response.results.length > 0 ? response.results[0] : undefined
      if (first === undefined) {
        return { allowed: true, threat: 'normal' }
      }
      if (first.threat === safetyDetect.UrlThreatType.MALWARE) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[url-check] blocked MALWARE host=%{public}s', extractHostname(url))
        return { allowed: false, threat: 'malware' }
      }
      if (first.threat === safetyDetect.UrlThreatType.PHISHING) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[url-check] blocked PHISHING host=%{public}s', extractHostname(url))
        return { allowed: false, threat: 'phishing' }
      }
      if (first.threat === safetyDetect.UrlThreatType.OTHERS) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[url-check] blocked OTHERS host=%{public}s', extractHostname(url))
        return { allowed: false, threat: 'other' }
      }
      return { allowed: true, threat: 'normal' }
    })
    .catch((err: BusinessError): UrlSafetyCheckResult => {
      const code = err && typeof err.code === 'number' ? err.code : -1
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[url-check] degraded unavailable code=%{public}d host=%{public}s',
        code, extractHostname(url))
      return { allowed: true, threat: 'unavailable', code: code }
    })
  const outcome: UrlSafetyCheckResult = await Promise.race([detectPromise, timeoutPromise])
  if (timerId !== -1) {
    clearTimeout(timerId)
  }
  return outcome
}
