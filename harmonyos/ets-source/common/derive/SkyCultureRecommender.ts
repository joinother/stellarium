import { SKY_CULTURE_STORIES_ZH, SkyCultureStoryZh } from './SkyCultureStoriesZh'

// 「此时此地」星空文化时空推荐引擎 + 文化阅读排版辅助函数。
// 遵循非打扰原则：仅推荐不强行自动切换，按观测地经纬度 + 模拟年份动态计算最贴合的 2~3 套文化。

export interface SkyCultureEpochItem {
  id: string
  name?: string
  beginTime?: number
  endTime?: number
}

export interface SkyCultureRecommendation {
  id: string
  reasonZh: string
  isEraMatch: boolean
  isLocalMatch: boolean
}

export interface SkyCultureRecommendInput {
  latitude: number
  longitude: number
  simulationYear: number
  earthObserver: boolean
  currentCultureId: string
  items: Array<SkyCultureEpochItem>
}

function angularDistanceDeg(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = Math.PI / 180
  const phi1 = lat1 * toRad
  const phi2 = lat2 * toRad
  const dPhi = (lat2 - lat1) * toRad
  const dLambda = (lon2 - lon1) * toRad
  const a = Math.sin(dPhi / 2) * Math.sin(dPhi / 2) +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) * Math.sin(dLambda / 2)
  const c = 2 * Math.atan2(Math.sqrt(Math.max(0, a)), Math.sqrt(Math.max(0, 1 - a)))
  return c / toRad
}

function formatYearShort(year: number): string {
  const rounded = Math.round(year)
  if (rounded < 0) return '前 ' + Math.abs(rounded) + ' 年'
  return rounded + ' 年'
}

export function formatShortEraRange(beginTime: number, endTime: number): string {
  const b = Math.round(beginTime)
  const e = Math.round(endTime)
  const curYear = new Date().getFullYear()
  if (b === 0 && e === 0) return '当代通用'
  if (b >= 1900 && (e === 0 || e >= curYear - 5 || e >= 9999)) return '现代标准'
  const bStr = b < 0 ? ('前' + Math.abs(b)) : b.toString()
  if (e === 0 || e >= curYear - 5 || e >= 9999) return bStr + ' 至今'
  const eStr = e < 0 ? ('前' + Math.abs(e)) : e.toString()
  return bStr + '~' + eStr
}

export function recommendedYearForCulture(beginTime: number, endTime: number, cultureId?: string): number {
  const curYear = new Date().getFullYear()
  // 为知名历史星图提供最具天文代表性的年份
  if (cultureId === 'chinese_song_dynasty') return 1100
  if (cultureId === 'chinese_yuan_dynasty') return 1280
  if (cultureId === 'chinese_chenzhuo') return 310
  if (cultureId === 'chinese') return 1054
  if (cultureId === 'chinese_manchu') return 1744
  if (cultureId === 'chinese_xianglin') return 1650
  if (cultureId === 'egyptian_dendera') return -50
  if (cultureId === 'babylonian_mulapin') return -700
  if (cultureId === 'babylonian_seleucid') return -200
  if (cultureId === 'greek_almagest') return 140
  if (cultureId === 'greek_farnese') return 150
  if (cultureId === 'greek_dante') return 1300
  if (cultureId === 'arabic_al-sufi') return 964
  if (cultureId === 'korean') return 1395
  if (cultureId === 'armintxe') return -12000

  const b = Math.round(beginTime)
  const e = (endTime === 0 || endTime >= 9999) ? curYear : Math.round(endTime)
  if (b === 0 && e === curYear) return curYear
  const mid = Math.round((b + Math.min(e, curYear)) / 2)
  return Math.max(-14000, Math.min(curYear, mid))
}

// 将天文年份（支持公元前负数年份）换算为该年夏至附近（6月21日 12:00 UTC）的儒略日 JD，用于 setTimeToJD。
export function yearToJulianDay(year: number): number {
  const y = Math.round(year)
  // Astronomical year numbering: 0 = 1 BCE, -1 = 2 BCE; June 21 12:00 UTC
  const m = 6
  const d = 21
  const a = Math.floor((14 - m) / 12)
  const yAdj = y + 4800 - a
  const mAdj = m + 12 * a - 3
  if (y >= 1583) {
    return d + Math.floor((153 * mAdj + 2) / 5) + 365 * yAdj +
      Math.floor(yAdj / 4) - Math.floor(yAdj / 100) + Math.floor(yAdj / 400) - 32045
  }
  return d + Math.floor((153 * mAdj + 2) / 5) + 365 * yAdj + Math.floor(yAdj / 4) - 32083
}

export function splitHighlightTags(highlightsZh: string): Array<string> {
  if (!highlightsZh || highlightsZh.trim().length === 0) return []
  return highlightsZh.split('·').map((s: string) => s.trim()).filter((s: string) => s.length > 0)
}

// 将完整中文故事按句号拆分成透气短段落（每段 1~2 句），杜绝窄屏大块密字墙。
export function splitAiryParagraphs(storyZh: string): Array<string> {
  const cleaned = storyZh.trim()
  if (cleaned.length === 0) return []
  const sentences: Array<string> = []
  let buf = ''
  for (let i = 0; i < cleaned.length; i++) {
    const ch = cleaned[i]
    buf += ch
    if (ch === '。' || ch === '！' || ch === '？') {
      const trimmed = buf.trim()
      if (trimmed.length > 0) sentences.push(trimmed)
      buf = ''
    }
  }
  if (buf.trim().length > 0) sentences.push(buf.trim())
  if (sentences.length <= 2) return [cleaned]
  const out: Array<string> = []
  let idx = 0
  while (idx < sentences.length) {
    const first = sentences[idx]
    if (idx + 1 < sentences.length && first.length + sentences[idx + 1].length <= 92) {
      out.push(first + sentences[idx + 1])
      idx += 2
    } else {
      out.push(first)
      idx += 1
    }
  }
  return out
}

interface ScoredCandidate {
  id: string
  score: number
  reasonZh: string
  isEraMatch: boolean
  isLocalMatch: boolean
}

export function recommendSkyCultures(input: SkyCultureRecommendInput): Array<SkyCultureRecommendation> {
  const curYear = new Date().getFullYear()
  const simYear = Math.round(input.simulationYear)
  const isHistorical = simYear < 1850
  const availableSet = new Set<string>()
  const itemById: Record<string, SkyCultureEpochItem> = {}
  for (const item of input.items) {
    availableSet.add(item.id)
    itemById[item.id] = item
  }

  // 外星观测点优先推荐全球现代 88 星座标准
  if (!input.earthObserver) {
    const fallbackIds = ['modern_chinese', 'modern', 'modern_iau']
    const out: Array<SkyCultureRecommendation> = []
    for (const id of fallbackIds) {
      if (id === input.currentCultureId) continue
      if (availableSet.size > 0 && !availableSet.has(id)) continue
      out.push({ id: id, reasonZh: '全天通用标准', isEraMatch: true, isLocalMatch: false })
      if (out.length >= 2) break
    }
    return out
  }

  const candidates: Array<ScoredCandidate> = []
  const ids = availableSet.size > 0 ? Array.from(availableSet) : Object.keys(SKY_CULTURE_STORIES_ZH)

  for (const id of ids) {
    if (id === input.currentCultureId) continue
    const story: SkyCultureStoryZh | undefined = SKY_CULTURE_STORIES_ZH[id]
    if (story === undefined) continue
    const meta: SkyCultureEpochItem | undefined = itemById[id]
    const beginT = meta !== undefined && meta.beginTime !== undefined ? meta.beginTime : 0
    const endRaw = meta !== undefined && meta.endTime !== undefined ? meta.endTime : 0
    const endT = (endRaw === 0 || endRaw >= 9999) ? curYear : endRaw
    const hasExplicitEpoch = !(beginT === 0 && endRaw === 0)
    const inEpoch = hasExplicitEpoch ? (simYear >= beginT && simYear <= endT) : !isHistorical

    let score = 0
    let isLocalMatch = false
    let isEraMatch = false
    let reasonZh = ''

    if (story.isGlobal === true) {
      if (!isHistorical) {
        if (id === 'modern_chinese') {
          score = 68
          reasonZh = '中文现代标准'
        } else if (id === 'modern') {
          score = 52
          reasonZh = '国际通用标准'
        } else {
          score = 20
          reasonZh = '现代连线方案'
        }
      } else {
        score = 5
        reasonZh = '现代参考标准'
      }
    } else {
      const distDeg = angularDistanceDeg(input.latitude, input.longitude, story.originLat, story.originLon)
      const proximityScore = Math.max(0, 100 - distDeg * 1.45)
      if (distDeg <= 22) isLocalMatch = true

      if (isHistorical) {
        if (inEpoch) {
          isEraMatch = true
          // 年代跨度越精准（如宋代/元代/丹达拉），在对应年份得分越高
          const span = Math.max(100, endT - beginT)
          const specificityBonus = Math.max(0, 35 - Math.log10(span) * 8)
          score = 90 + specificityBonus + proximityScore * 0.75
          reasonZh = isLocalMatch ? ('适配 ' + formatYearShort(simYear) + ' · 就近') : ('适配 ' + formatYearShort(simYear))
        } else {
          const gap = simYear < beginT ? (beginT - simYear) : (simYear - endT)
          score = Math.max(0, 30 - gap / 250) + proximityScore * 0.35
          reasonZh = isLocalMatch ? '当地历史传统' : '历史文化参考'
        }
      } else {
        // 当代年份：强烈优先就近的活态/传统星空文化
        score = proximityScore * (inEpoch ? 1.05 : 0.78)
        if (id === 'chinese' && distDeg <= 25) score += 16
        if (distDeg <= 12) {
          reasonZh = '当地传统星空'
        } else if (distDeg <= 26) {
          reasonZh = '就近区域传统'
        } else {
          reasonZh = story.hemisphereZh
        }
      }
    }

    if (score >= 30) {
      candidates.push({
        id: id,
        score: score,
        reasonZh: reasonZh,
        isEraMatch: isEraMatch,
        isLocalMatch: isLocalMatch
      })
    }
  }

  candidates.sort((a: ScoredCandidate, b: ScoredCandidate) => b.score - a.score)
  const out: Array<SkyCultureRecommendation> = []
  for (let i = 0; i < candidates.length && out.length < 3; i++) {
    const c = candidates[i]
    out.push({
      id: c.id,
      reasonZh: c.reasonZh,
      isEraMatch: c.isEraMatch,
      isLocalMatch: c.isLocalMatch
    })
  }
  return out
}
