// 卫星 TLE 来源列表的显示文本。
//
// 默认来源共用
//   https://celestrak.org/NORAD/elements/gp.php?GROUP=<group>&FORMAT=CSV
// 真正区分条目的是 GROUP 取值。列表若只显示 URL 前缀，所有条目会完全相同；
// 本模块从 URL 中提取“差异标识”“域名”和“尾部”，只做纯字符串解析。

const GROUP_QUERY = /[?&]group=([^&#]*)/i
// 随包内置的 CelesTrak GP 来源；其余 URL 视为用户自定义条目，可编辑标题。
const DEFAULT_GP_SOURCE =
  /^https?:\/\/celestrak\.org\/NORAD\/elements\/gp\.php\?GROUP=[^&]+&FORMAT=CSV\/?$/i

function decodeSafe(value: string): string {
  try {
    return decodeURIComponent(value)
  } catch (error) {
    return value
  }
}

function lastPathSegment(value: string): string {
  const withoutQuery = value.replace(/[?#].*$/, '')
  let end = withoutQuery.length
  while (end > 0 && withoutQuery.charAt(end - 1) === '/') end--
  if (end === 0) return ''
  const slash = withoutQuery.lastIndexOf('/', end - 1)
  return slash >= 0 ? withoutQuery.substring(slash + 1, end) : withoutQuery.substring(0, end)
}

function groupQueryValue(url: string): string {
  const match = GROUP_QUERY.exec(url)
  if (match === null || match.length < 2) return ''
  const decoded = decodeSafe(match[1]).trim()
  return decoded.length > 0 ? decoded : ''
}

// 来源标识：优先 GROUP 取值；其次文件名；再退回查询串/域名/原 URL。
export function satelliteSourceLabel(url: string): string {
  const value = url.trim()
  if (value.length === 0) return ''
  const group = groupQueryValue(value)
  if (group.length > 0) return group
  const host = satelliteSourceHost(value)
  const segment = lastPathSegment(value)
  if (segment.length > 0 && segment !== host) return segment
  const queryStart = value.indexOf('?')
  if (queryStart >= 0 && queryStart < value.length - 1) {
    const query = value.substring(queryStart + 1).replace(/[#].*$/, '')
    if (query.length > 0) return query
  }
  if (host.length > 0) return host
  if (segment.length > 0) return segment
  return value
}

// 来源域名：file:// 或非层级 URL 返回空串，界面据此显示“本地文件”。
export function satelliteSourceHost(url: string): string {
  const value = url.trim()
  const match = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]*)/i.exec(value)
  if (match === null || match.length < 2) return ''
  let host = match[1]
  const userInfo = host.lastIndexOf('@')
  if (userInfo >= 0) host = host.substring(userInfo + 1)
  return host
}


// 用户自定义来源：标题行可在编辑弹窗中自定义。
export function isCustomSatelliteSource(url: string): boolean {
  return !DEFAULT_GP_SOURCE.test(url.trim())
}
