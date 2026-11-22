// 高德短链解析：只对用户主动分享的 `surl.amap.com` 链接做一次受限 HTTP 请求。
//
// 本地解析优先；只有文本中没有坐标、但包含高德短链时才联网。请求关闭自动重定向，
// 只读取 3xx 的 Location 头，并校验目标必须是高德域名；不下载 wb 页面、不携带
// Cookie / 账号 / 设备标识。失败时返回 null，由宿主沿用“未找到可用坐标”提示。

import { http } from '@kit.NetworkKit'
import hilog from '@ohos.hilog'
import { LOG_DOMAIN, LOG_TAG } from '../QtAppConstants'
import {
  findAmapShortLink,
  isAllowedAmapRedirect,
  parseSharedLocationText,
  SharedLocationPoint
} from './LocationShareLink'

const AMAP_SHORT_LINK_TIMEOUT_MS: number = 5000
const AMAP_SHORT_LINK_MAX_BODY_BYTES: number = 64 * 1024

// header 的类型是 Object，键名大小写不保证；只接受字符串形式的 Location。
export function locationHeaderValue(header: Object): string {
  const record = header as Record<string, Object>
  const keys = Object.keys(record)
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() !== 'location') continue
    const value = record[keys[i]]
    return typeof value === 'string' ? value : ''
  }
  return ''
}

export async function resolveSharedLocationText(raw: string): Promise<SharedLocationPoint | null> {
  const direct = parseSharedLocationText(raw)
  if (direct !== null) return direct
  const shortLink = findAmapShortLink(raw)
  if (shortLink === null) return null
  hilog.info(LOG_DOMAIN, LOG_TAG, '[location-share] resolving amap short link');
  const request = http.createHttp()
  // maxRedirects: 0 makes the client abort a 3xx with error 2300047 instead of
  // returning the response. The headersReceive callback still carries the
  // redirect Location; validate it before using, and never follow the hop.
  let redirectLocation = ''
  request.once('headersReceive', (header: Object) => {
    const value = locationHeaderValue(header)
    hilog.info(LOG_DOMAIN, LOG_TAG, `[location-share] amap header length ${value.length}`);
    if (value.length > 0 && isAllowedAmapRedirect(value)) redirectLocation = value
  })
  try {
    const response = await request.request(shortLink, {
      method: http.RequestMethod.GET,
      connectTimeout: AMAP_SHORT_LINK_TIMEOUT_MS,
      readTimeout: AMAP_SHORT_LINK_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING,
      maxLimit: AMAP_SHORT_LINK_MAX_BODY_BYTES,
      usingCache: false,
      // 短链只允许一跳：Location 由本模块校验后再本地解析，不跟随任意重定向。
      maxRedirects: 0,
      header: {
        'Accept': 'text/html,application/xhtml+xml'
      }
    })
    const code = response.responseCode
    hilog.info(LOG_DOMAIN, LOG_TAG, `[location-share] amap short link status ${code}`);
    if (redirectLocation.length > 0) return parseSharedLocationText(redirectLocation)
    if (code !== 301 && code !== 302 && code !== 303 && code !== 307 && code !== 308) return null
    const location = locationHeaderValue(response.header)
    const allowed = location.length > 0 && isAllowedAmapRedirect(location)
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[location-share] amap redirect header length ${location.length}, allowed ${allowed}`);
    if (!allowed) return null
    return parseSharedLocationText(location)
  } catch (error) {
    // maxRedirects: 0 的预期异常：Location 已在上面的回调中拿到，不算失败。
    if (redirectLocation.length > 0) return parseSharedLocationText(redirectLocation)
    hilog.warn(LOG_DOMAIN, LOG_TAG, `[location-share] amap short link failed: ${(error as Error).message}`);
    return null
  } finally {
    request.destroy()
  }
}
