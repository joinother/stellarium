// 地点分享解析：把外部地图应用分享的文本 / 深链解析成观测点。
//
// 支持四类输入（都按 WGS84 处理）：
//   1. 自定义深链 `skyinstrument://location?lat=..&lon=..&name=..`；
//   2. 标准 `geo:LAT,LON?q=LAT,LON(NAME)`（Android / 花瓣地图等分享的通用格式）；
//   3. 地图网页链接中的 `?ll=` / `?q=` / `@lat,lon` / `!3d..!4d..` 坐标；
//   4. 纯文本里的“纬度 39.9 经度 116.4”、`N39.9 E116.4` 或 `39.9042,116.4074`。
//
// 纯函数，不依赖 UI / NAPI / 网络，宿主与单测共用；名称解析不出来时返回空串，
// 由调用方回退到本地化“分享位置”。坐标范围非法或没有坐标时返回 null。
export interface SharedLocationPoint {
  name: string
  latitude: number
  longitude: number
  altitude: number
  planet: string
  source: string
}

const LAT_KEYS: string[] = ['lat', 'latitude', 'wgs84lat', 'destinationlatitude', 'poilat']
const LON_KEYS: string[] = ['lon', 'lng', 'long', 'longitude', 'wgs84lon', 'destinationlongitude', 'poilon']
const NAME_KEYS: string[] = ['name', 'title', 'label', 'placename', 'poiname', 'destinationname']
const ALT_KEYS: string[] = ['alt', 'altitude', 'elevation', 'height']
const PAIR_KEYS: string[] = ['ll', 'center', 'q', 'location', 'daddr', 'destination', 'coordinate', 'coords', 'marker', 'position']

function safeDecode(value: string): string {
  const plus = value.replace(/\+/g, ' ')
  try {
    return decodeURIComponent(plus)
  } catch (_error) {
    return plus
  }
}

function queryValue(query: string, keys: string[]): string {
  const parts = query.split('&')
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i]
    const eq = part.indexOf('=')
    if (eq <= 0) continue
    const key = part.substring(0, eq).trim().toLowerCase()
    if (keys.indexOf(key) >= 0) return safeDecode(part.substring(eq + 1))
  }
  return ''
}

// 返回 [去掉 query / fragment 的主体, query]。
function splitUri(uri: string): string[] {
  const hash = uri.indexOf('#')
  const noHash = hash >= 0 ? uri.substring(0, hash) : uri
  const question = noHash.indexOf('?')
  if (question < 0) return [noHash, '']
  return [noHash.substring(0, question), noHash.substring(question + 1)]
}

// 允许 N/S/E/W 前缀或后缀；没有方位字母时保留数值自身的正负号。
function parseCoordinate(raw: string): number {
  if (raw.length === 0) return NaN
  let text = raw.trim().toUpperCase()
  let sign = 1
  if (text.startsWith('N') || text.startsWith('E')) {
    text = text.substring(1)
  } else if (text.startsWith('S') || text.startsWith('W')) {
    text = text.substring(1)
    sign = -1
  } else if (text.endsWith('N') || text.endsWith('E')) {
    text = text.substring(0, text.length - 1)
  } else if (text.endsWith('S') || text.endsWith('W')) {
    text = text.substring(0, text.length - 1)
    sign = -1
  }
  text = text.replace(/[°度\s]/g, '')
  if (text.length === 0) return NaN
  const value = Number(text)
  if (!Number.isFinite(value)) return NaN
  return sign < 0 ? -Math.abs(value) : value
}

function parsePair(raw: string): number[] | null {
  const match = /^([-+]?\d{1,3}(?:\.\d+)?)\s*[,，]\s*([-+]?\d{1,3}(?:\.\d+)?)\s*$/.exec(raw.trim())
  if (match === null) return null
  const lat = parseCoordinate(match[1])
  const lon = parseCoordinate(match[2])
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null
  return [lat, lon]
}

function cleanName(raw: string): string {
  let text = raw.trim()
  if (text.length >= 2) {
    const first = text.charAt(0)
    const last = text.charAt(text.length - 1)
    if ((first === '"' && last === '"') || (first === '\'' && last === '\'') ||
      (first === '“' && last === '”') || (first === '《' && last === '》')) {
      text = text.substring(1, text.length - 1).trim()
    }
  }
  const newline = text.indexOf('\n')
  if (newline >= 0) text = text.substring(0, newline).trim()
  if (text.length > 80) text = text.substring(0, 80).trim()
  return text
}

function makePoint(name: string, latitude: number, longitude: number, altitude: number): SharedLocationPoint | null {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null
  const cleanAltitude = Number.isFinite(altitude) ? Math.round(Math.max(-500, Math.min(9000, altitude))) : 0
  return {
    name: cleanName(name),
    latitude: Math.round(latitude * 1000000) / 1000000,
    longitude: Math.round(longitude * 1000000) / 1000000,
    altitude: cleanAltitude,
    planet: 'Earth',
    source: 'share'
  }
}

function parseGeoUri(raw: string): SharedLocationPoint | null {
  const parts = splitUri(raw.substring(4))
  let base = parts[0]
  const semicolon = base.indexOf(';')
  if (semicolon >= 0) base = base.substring(0, semicolon)
  const query = parts[1]
  const basePair = parsePair(base)
  let latitude = NaN
  let longitude = NaN
  let hasPair = false
  if (basePair !== null && !(basePair[0] === 0 && basePair[1] === 0)) {
    latitude = basePair[0]
    longitude = basePair[1]
    hasPair = true
  }
  let name = ''
  const q = queryValue(query, ['q'])
  if (q.length > 0) {
    const qMatch = /^([-+]?\d{1,3}(?:\.\d+)?)\s*[,，]\s*([-+]?\d{1,3}(?:\.\d+)?)\s*(?:\((.*)\))?\s*$/.exec(q)
    if (qMatch !== null) {
      if (!hasPair) {
        latitude = parseCoordinate(qMatch[1])
        longitude = parseCoordinate(qMatch[2])
        hasPair = true
      }
      if (qMatch[3] !== undefined && qMatch[3].length > 0) name = qMatch[3]
    } else if (q.indexOf(',') < 0) {
      // `geo:0,0?q=天安门` 只有名称，没有可离线解析的坐标。
      name = q
    }
  }
  if (!hasPair) return null
  if (name.length === 0) name = queryValue(query, NAME_KEYS)
  return makePoint(name, latitude, longitude, parseCoordinate(queryValue(query, ALT_KEYS)))
}

function parseSkyinstrumentUri(raw: string): SharedLocationPoint | null {
  const parts = splitUri(raw)
  const query = parts[1]
  const name = queryValue(query, NAME_KEYS)
  const altitude = parseCoordinate(queryValue(query, ALT_KEYS))
  const latitude = parseCoordinate(queryValue(query, LAT_KEYS))
  const longitude = parseCoordinate(queryValue(query, LON_KEYS))
  if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
    return makePoint(name, latitude, longitude, altitude)
  }
  const path = parts[0]
  const slash = path.lastIndexOf('/')
  const pair = slash >= 0 ? parsePair(path.substring(slash + 1)) : null
  if (pair === null) return null
  return makePoint(name, pair[0], pair[1], altitude)
}

// —— 花瓣地图坐标系 ——
// 花瓣网页/深链的 marker/向心坐标默认是 GCJ02（coordinateType=1），
// 只有显式 coordinateType=0 才是 WGS84；星象仪内部统一 WGS84。
const GCJ_A: number = 6378245.0
const GCJ_EE: number = 0.00669342162296594323

function outOfChinaGcj(latitude: number, longitude: number): boolean {
  return longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271
}

function transformLatGcj(x: number, y: number): number {
  let ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x))
  ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0
  ret += (20.0 * Math.sin(y * Math.PI) + 40.0 * Math.sin(y / 3.0 * Math.PI)) * 2.0 / 3.0
  ret += (160.0 * Math.sin(y / 12.0 * Math.PI) + 320.0 * Math.sin(y * Math.PI / 30.0)) * 2.0 / 3.0
  return ret
}

function transformLonGcj(x: number, y: number): number {
  let ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x))
  ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0
  ret += (20.0 * Math.sin(x * Math.PI) + 40.0 * Math.sin(x / 3.0 * Math.PI)) * 2.0 / 3.0
  ret += (150.0 * Math.sin(x / 12.0 * Math.PI) + 300.0 * Math.sin(x / 30.0 * Math.PI)) * 2.0 / 3.0
  return ret
}

function wgs84ToGcj02(latitude: number, longitude: number): number[] {
  if (outOfChinaGcj(latitude, longitude)) return [latitude, longitude]
  let dLat = transformLatGcj(longitude - 105.0, latitude - 35.0)
  let dLon = transformLonGcj(longitude - 105.0, latitude - 35.0)
  const radLat = latitude / 180.0 * Math.PI
  let magic = Math.sin(radLat)
  magic = 1 - GCJ_EE * magic * magic
  const sqrtMagic = Math.sqrt(magic)
  dLat = (dLat * 180.0) / ((GCJ_A * (1 - GCJ_EE)) / (magic * sqrtMagic) * Math.PI)
  dLon = (dLon * 180.0) / (GCJ_A / sqrtMagic * Math.cos(radLat) * Math.PI)
  return [latitude + dLat, longitude + dLon]
}

function gcj02ToWgs84(latitude: number, longitude: number): number[] {
  if (outOfChinaGcj(latitude, longitude)) return [latitude, longitude]
  let wgsLat = latitude
  let wgsLon = longitude
  for (let i = 0; i < 6; i++) {
    const gcj = wgs84ToGcj02(wgsLat, wgsLon)
    wgsLat += latitude - gcj[0]
    wgsLon += longitude - gcj[1]
  }
  return [wgsLat, wgsLon]
}

function isPetalUri(rawLower: string): boolean {
  return rawLower.startsWith('petalmaps://') || rawLower.startsWith('maps://') ||
    rawLower.indexOf('petalmaps.com') >= 0
}

// 花瓣未写 coordinateType 时按 GCJ02，只有显式 0 才是 WGS84。
function petalUsesGcj(rawLower: string, query: string): boolean {
  if (!isPetalUri(rawLower)) return false
  return queryValue(query, ['coordinatetype']) !== '0'
}

function parseHttpUri(raw: string): SharedLocationPoint | null {
  const parts = splitUri(raw)
  const query = parts[1]
  let name = queryValue(query, NAME_KEYS)
  let latitude = parseCoordinate(queryValue(query, LAT_KEYS))
  let longitude = parseCoordinate(queryValue(query, LON_KEYS))
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    for (let i = 0; i < PAIR_KEYS.length; i++) {
      const value = queryValue(query, [PAIR_KEYS[i]])
      if (value.length === 0) continue
      const match = /^([-+]?\d{1,3}(?:\.\d+)?)\s*[,，]\s*([-+]?\d{1,3}(?:\.\d+)?)\s*(?:\((.*)\))?\s*$/.exec(value)
      if (match === null) continue
      // 高德 URI API 的 position 是“经度,纬度”；其余 marker/location 等按“纬度,经度”。
      if (PAIR_KEYS[i] === 'position') {
        longitude = parseCoordinate(match[1])
        latitude = parseCoordinate(match[2])
      } else {
        latitude = parseCoordinate(match[1])
        longitude = parseCoordinate(match[2])
      }
      if (match[3] !== undefined && match[3].length > 0 && name.length === 0) name = match[3]
      break
    }
  }
  if (name.length === 0) {
    const qText = queryValue(query, ['q'])
    if (qText.length > 0 && parsePair(qText) === null && qText.indexOf('(') < 0) name = qText
  }
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    // Google Maps: /@39.9042,116.4074,15z
    const at = /@([-+]?\d{1,3}(?:\.\d+)?),([-+]?\d{1,3}(?:\.\d+)?)/.exec(parts[0])
    if (at !== null) {
      latitude = parseCoordinate(at[1])
      longitude = parseCoordinate(at[2])
    }
  }
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    // Google place links: !3d39.9042!4d116.4074
    const place = /!3d([-+]?\d{1,3}(?:\.\d+)?)!4d([-+]?\d{1,3}(?:\.\d+)?)/.exec(parts[0])
    if (place !== null) {
      latitude = parseCoordinate(place[1])
      longitude = parseCoordinate(place[2])
    }
  }
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null
  if (petalUsesGcj(raw.toLowerCase(), query)) {
    const wgs = gcj02ToWgs84(latitude, longitude)
    latitude = wgs[0]
    longitude = wgs[1]
  }
  return makePoint(name, latitude, longitude, parseCoordinate(queryValue(query, ALT_KEYS)))
}

function parsePlainText(text: string): SharedLocationPoint | null {
  let latitude = NaN
  let longitude = NaN
  const latLabel = /(?:纬度|緯度|lat(?:itude)?)\s*[:：=]?\s*([-+]?\d{1,3}(?:\.\d+)?)\s*°?\s*([NSEW])?/i.exec(text)
  const lonLabel = /(?:经度|經度|lon(?:gitude)?|lng)\s*[:：=]?\s*([-+]?\d{1,3}(?:\.\d+)?)\s*°?\s*([NSEW])?/i.exec(text)
  if (latLabel !== null && lonLabel !== null) {
    latitude = parseCoordinate(latLabel[1] + (latLabel[2] !== undefined ? latLabel[2] : ''))
    longitude = parseCoordinate(lonLabel[1] + (lonLabel[2] !== undefined ? lonLabel[2] : ''))
  }
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    // N39.9 E116.4 / E116.4 N39.9
    const directional = /([NSEWnsew])\s*([-+]?\d{1,3}(?:\.\d+)?)\s*°?[\s,，]+([NSEWnsew])\s*([-+]?\d{1,3}(?:\.\d+)?)\s*°?/.exec(text)
    if (directional !== null) {
      const firstAxis = directional[1].toUpperCase()
      const firstValue = parseCoordinate(directional[1] + directional[2])
      const secondValue = parseCoordinate(directional[3] + directional[4])
      if (firstAxis === 'N' || firstAxis === 'S') {
        latitude = firstValue
        longitude = secondValue
      } else {
        latitude = secondValue
        longitude = firstValue
      }
    }
  }
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    // 39.9°N, 116.4°E
    const suffix = /([-+]?\d{1,3}(?:\.\d+)?)\s*°?\s*([NSEWnsew])\s*[,，\s]+\s*([-+]?\d{1,3}(?:\.\d+)?)\s*°?\s*([NSEWnsew])/.exec(text)
    if (suffix !== null) {
      const firstAxis = suffix[2].toUpperCase()
      const firstValue = parseCoordinate(suffix[1] + suffix[2])
      const secondValue = parseCoordinate(suffix[3] + suffix[4])
      if (firstAxis === 'N' || firstAxis === 'S') {
        latitude = firstValue
        longitude = secondValue
      } else {
        latitude = secondValue
        longitude = firstValue
      }
    }
  }
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    // 裸坐标对：两边都至少 3 位小数，避免把版本号 / 日期误认为坐标。
    const pair = /(-?\d{1,3}\.\d{3,})\s*[,，]\s*(-?\d{1,3}\.\d{3,})/.exec(text)
    if (pair !== null) {
      latitude = parseCoordinate(pair[1])
      longitude = parseCoordinate(pair[2])
    }
  }
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null
  let name = ''
  const nameLabel = /(?:地点|位置|名称|地名|location|place|name)\s*[:：]\s*([^\n\r]{1,80})/i.exec(text)
  if (nameLabel !== null) {
    const candidate = nameLabel[1].trim()
    if (parsePair(candidate) === null && !/^[\d\s.,，°+\-]+$/.test(candidate)) name = candidate
  }
  if (name.length === 0) {
    const lines = text.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.length === 0 || line.length > 60) continue
      if (line.indexOf('http') >= 0 || line.indexOf('://') >= 0) continue
      if (/[NSEWnsew]\s*\d|纬度|經度|经度|lat(?:itude)?|lon(?:gitude)?/.test(line)) continue
      if (parsePair(line) !== null) continue
      if (/^[\d\s.,，°+\-]+$/.test(line)) continue
      name = line
      break
    }
  }
  return makePoint(name, latitude, longitude, 0)
}

function embeddedUri(text: string, start: number): string {
  let end = text.length
  for (let i = start; i < text.length; i++) {
    const ch = text.charAt(i)
    if (ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t' || ch === '"' || ch === '<' || ch === '>') {
      end = i
      break
    }
  }
  return text.substring(start, end)
}

export function parseSharedLocationText(raw: string): SharedLocationPoint | null {
  // Shared content is untrusted input; cap it before running the regexes.
  let text = raw.trim()
  if (text.length > 4096) text = text.substring(0, 4096)
  if (text.length === 0) return null
  const lower = text.toLowerCase()
  if (lower.startsWith('skyinstrument://')) return parseSkyinstrumentUri(text)
  if (lower.startsWith('geo:')) return parseGeoUri(text)
  if (lower.startsWith('http://') || lower.startsWith('https://')) return parseHttpUri(text)
  // 地图应用自己的深链：Petal `maps://locationInfo`、Amap `amapuri://viewMap`、
  // Baidu `baidumap://map/marker`；查询参数与网页链接同构，复用 parseHttpUri。
  if (lower.startsWith('maps://') || lower.startsWith('petalmaps://') ||
    lower.startsWith('amapuri://') || lower.startsWith('baidumap://')) return parseHttpUri(text)
  // 分享面板常在链接前后附带说明文字，先找内嵌的 URI。
  const geoIndex = lower.indexOf('geo:')
  if (geoIndex >= 0) {
    const parsed = parseGeoUri(embeddedUri(text, geoIndex))
    if (parsed !== null) return parsed
  }
  const httpIndex = lower.indexOf('http://') >= 0 ? lower.indexOf('http://') : lower.indexOf('https://')
  if (httpIndex >= 0) {
    const parsed = parseHttpUri(embeddedUri(text, httpIndex))
    if (parsed !== null) return parsed
  }
  return parsePlainText(text)
}
