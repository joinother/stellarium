// 星空文化 / 杂项纯函数。
// 依据计划 §14.2 轨道 A1-4，逐字从 pages/MainWindowNativeNode.ets 的私有方法迁出。
// 这些函数零 this、零 IO、零桥、零 store 依赖，只依赖入参、静态 I18n 查表与纯计算；
// 宿主与 panels 直连本模块（§14.8 规则 6：不 import store）。

import { I18n } from '../../pages/I18n'

// CLI 允许的面板名白名单（openUiPanel 命令用）。
export function isCliPanelName(panel: string): boolean {
  return [
    'search', 'time', 'quick', 'place', 'layers', 'more', 'observeHub', 'dataHub', 'automationHub',
    'observing', 'bookmarks', 'oculars', 'angleMeasure', 'navStars', 'polarScope', 'telescope',
    'astro', 'satellites', 'meteorshowers', 'scenery3d', 'catalogs', 'settings', 'tools',
    'scripts', 'commands', 'audio', 'skyCultureMaker', 'mosaicCamera', 'nebulaTextures', 'help',
    'settingsInformation', 'settingsTime', 'settingsPrivacy', 'ar'
  ].includes(panel)
}

// 解析持久化的观测清单 JSON 字符串：只保留非空字符串、去重。
export function parseObservingList(value: string): string[] {
  try {
    const parsed: string[] = JSON.parse(value) as string[]
    if (!Array.isArray(parsed)) return []
    return parsed.filter((item: string) => typeof item === 'string' && item.trim().length > 0)
      .map((item: string) => item.trim())
      .filter((item: string, index: number, items: string[]) => items.indexOf(item) === index)
  } catch (e) {
    return []
  }
}

// 过滤掉只读查询与连续视图命令，以及录制自身的管理命令。
export function isRecordable(name: string): boolean {
  if (name.startsWith('get') || name.startsWith('list') || name.startsWith('is') || name.startsWith('selftest'))
    return false
  const skip = ['dragView', 'panBy', 'zoomBy', 'setGyroView', 'gyroDiagnostic',
    'beginGyroViewTransition', 'cancelGyroViewTransition', 'saveRecording',
    'loadRecording', 'listRecordings', 'deleteRecording', 'startRecording', 'stopRecording']
  return !skip.includes(name)
}

// 信息窗自定义掩码：字段键 → 位。
export function informationMaskBit(key: string): number {
  switch (key) {
    case 'name': return 1
    case 'catalog': return 2
    case 'magnitude': return 4
    case 'raJ2000': return 8
    case 'raOfDate': return 16
    case 'altAz': return 32
    case 'distance': return 64
    case 'elongation': return 128
    case 'size': return 256
    case 'velocity': return 512
    case 'properMotion': return 1024
    case 'extra': return 2048
    case 'hourAngle': return 4096
    case 'absoluteMagnitude': return 8192
    case 'galactic': return 16384
    case 'supergalactic': return 32768
    case 'otherCoordinates': return 65536
    case 'objectType': return 131072
    case 'eclipticJ2000': return 262144
    case 'eclipticOfDate': return 524288
    case 'constellation': return 1048576
    case 'culturalConstellation': return 2097152
    case 'siderealTime': return 4194304
    case 'riseTransitSet': return 8388608
    case 'solarLunar': return 16777216
    default: return 0
  }
}

// 抖动（dithering）模式值 → 界面标签。
export function configDitheringLabel(value: string): string {
  if (value.toLowerCase() === 'disabled') return '关闭'
  if (value.toLowerCase() === 'color565') return '5/6/5 位'
  if (value.toLowerCase() === 'color666') return '6/6/6 位'
  return '8/8/8 位'
}

// CSV 单元格转义：整体加双引号，内部双引号翻倍。
export function csvCell(value: string | number | boolean | undefined): string {
  const text = value === undefined ? '' : String(value)
  return '"' + text.replace(/"/g, '""') + '"'
}

// 星空文化解说文本清洗：去 BOM/替换字符、把省略号行归一为换行、压缩多余空行。
export function cleanSkyCultureNarration(text: string): string {
  return text.replace(/[\uFEFF\uFFFD\uFFFC]/g, '').replace(/\s*\.\s*\.\s*\.\s*/g, '\n').replace(/\n{3,}/g, '\n\n').trim()
}

// 星空文化描述文本清洗：去 BOM/替换字符、去行尾空白、压缩多余空行。
export function cleanSkyCultureDescription(text: string): string {
  return text.replace(/[\uFEFF\uFFFD\uFFFC]/g, '').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim()
}

// 星空文化插图相对路径安全校验（防目录穿越、限定图片扩展名）。
export function isSafeSkyCultureArtPath(rawPath: string): boolean {
  if (!rawPath.startsWith('skycultures/')) return false
  const parts = rawPath.split('/')
  if (parts.length < 4 || parts[0] !== 'skycultures' || parts[2] !== 'illustrations') return false
  for (const part of parts) {
    if (part.length === 0 || part === '.' || part === '..' || part.indexOf('\\') >= 0) return false
  }
  return /\.(?:png|jpe?g|webp)$/i.test(parts[parts.length - 1])
}

// 时间速率 → 人类可读标签（暂停 / Nx / 分每秒 等）。
export function formatRate(rate: number): string {
  if (rate === 0 || Math.abs(rate) < 1e-18) {
    return I18n.t('msg_paused')
  }
  const secPerDay = 86400.0
  const absRate = Math.abs(rate)
  const sign = rate > 0 ? '' : '-'
  // Map common speeds to human-readable labels
  interface SpeedLabel { limit: number; label: string }
  const thresholds: SpeedLabel[] = [
    { limit: 2.0 / secPerDay,     label: '2x' } as SpeedLabel,
    { limit: 10.0 / secPerDay,    label: '10x' } as SpeedLabel,
    { limit: 60.0 / secPerDay,    label: '1分/秒' } as SpeedLabel,
    { limit: 360.0 / secPerDay,   label: '1时/秒' } as SpeedLabel,
    { limit: 1.0,                label: '1天/秒' } as SpeedLabel,
    { limit: 10.0,               label: '10天/秒' } as SpeedLabel,
  ] as SpeedLabel[]
  if (Math.abs(absRate - 1.0 / secPerDay) < 0.0000001) { return sign + '1x' }
  let speedLabel: string = ''
  for (const t of thresholds) {
    if (absRate <= t.limit * 1.01) { speedLabel = t.label; break }
  }
  if (speedLabel.length > 0) { return sign + speedLabel }
  const mult: number = absRate * secPerDay
  return sign + mult.toFixed(0) + 'x'
}
