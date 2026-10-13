// Dock / Hub 动作表与动作相关纯文案助手。
// 依据计划 §14.2 轨道 A1-5，逐字从 pages/MainWindowNativeNode.ets 的私有方法迁出。
// 这些是纯、无状态的**文件级函数**：零 this、零宿主字段读取、零 IO、零桥、零 store/UI 依赖，
// 只读取静态 I18n 表与入参；宿主与面板按名 import（§14.8 规则 6：不得 import store）。

import { I18n } from '../../pages/I18n'
import { ShellAction, StellariumBridgeResponse } from '../../pages/StellariumTypes'
import { CityPreset, SkyCultureMakerValidation, TelescopeControlResponse } from '../../pages/MainWindowModels'

// 所有设备共享同一动作模型。布局只决定面板如何呈现，不改变入口和语义。
export function primaryDockActions(): ShellAction[] {
  return [
    { label: I18n.t('dock_search'), icon: 'search', panel: 'search' },
    { label: I18n.t('dock_time'), icon: 'clock', panel: 'time' },
    { label: I18n.t('dock_quick'), icon: 'quick_actions', panel: 'quick' },
    { label: I18n.t('dock_layers'), icon: 'layers', panel: 'layers' }
  ]
}

export function moreActions(): ShellAction[] {
  return [
    { label: I18n.t('more_workspace_observing'), icon: 'observe', panel: 'observeHub', section: I18n.t('more_section_workspace') },
    // 「位置」自从 Dock 中间让位给快捷操作面板后，入口落在工作区组第 2 行（正值天体数据组标题之前）。
    { label: I18n.t('dock_place'), icon: 'location', panel: 'place', section: I18n.t('more_section_workspace') },
    { label: I18n.t('more_sky_data'), icon: 'satellite', panel: 'dataHub', section: I18n.t('more_section_data') },
    { label: I18n.t('more_automation'), icon: 'script', panel: 'automationHub', section: I18n.t('more_section_automation') },
    { label: I18n.t('panel_tools_data'), icon: 'tools', panel: 'tools', section: I18n.t('more_section_system') },
    { label: I18n.t('dock_settings'), icon: 'settings', panel: 'settings', section: I18n.t('more_section_system') },
    { icon: 'help', label: I18n.t('i0217'), panel: 'help', section: I18n.t('more_section_system') }
  ]
}

export function observingHubActions(): ShellAction[] {
  return [
    { label: I18n.t('more_observe_list'), icon: 'observe', panel: 'observing' },
    { label: I18n.t('panel_bookmarks'), icon: 'bookmarks', panel: 'bookmarks' },
    { label: I18n.t('panel_oculars'), icon: 'oculars', panel: 'oculars' },
    { label: I18n.t('panel_angle_measure'), icon: 'angle', panel: 'angleMeasure' },
    { label: I18n.t('panel_nav_stars'), icon: 'nav_stars', panel: 'navStars' },
    { label: I18n.t('polar_scope_title'), icon: 'polar_scope', panel: 'polarScope' },
    { label: I18n.t('panel_telescope_control'), icon: 'telescope', panel: 'telescope' }
  ]
}

export function skyDataHubActions(): ShellAction[] {
  return [
    { label: I18n.t('i0274'), icon: 'orbit', panel: 'astro' },
    { label: I18n.t('panel_satellites'), icon: 'satellite', panel: 'satellites' },
    { label: I18n.t('panel_meteorshowers'), icon: 'meteor', panel: 'meteorshowers' },
    { label: I18n.pluginName('Scenery3d'), icon: 'scenery3d', panel: 'scenery3d' },
    { label: 'AR 预研', icon: 'gyro', panel: 'ar' },
    { label: I18n.t('panel_catalogs'), icon: 'catalogs', panel: 'catalogs' },
    { label: I18n.t('more_plugins_manage'), icon: 'settings', panel: 'pluginManager' }
  ]
}

export function automationHubActions(): ShellAction[] {
  return [
    { icon: 'script', label: I18n.t('panel_scripts'), panel: 'scripts' },
    { icon: 'code', label: I18n.t('panel_commands'), panel: 'commands' },
    { icon: 'audio', label: I18n.t('panel_audio_ctrl'), panel: 'audio' }
  ]
}

// 城市快速定位预设数据: id -> "lat|lon|alt"
export function getCityPreset(id: string): CityPreset | undefined {
  const m: Record<string, string> = {
    'Beijing': '39.9042|116.4074|44', 'Shanghai': '31.2304|121.4737|4',
    'Guangzhou': '23.1291|113.2644|21', 'Shenzhen': '22.5431|114.0579|7',
    'Chengdu': '30.5728|104.0668|500', 'Hangzhou': '30.2741|120.1551|11',
    'Wuhan': '30.5928|114.3055|23', 'Xian': '34.3416|108.9398|405',
    'Nanjing': '32.0603|118.7969|20', 'Chongqing': '29.5630|106.5516|259',
    'Harbin': '45.7500|126.6500|132', 'Lhasa': '29.6500|91.1000|3650',
    'Urumqi': '43.8256|87.6168|800', 'HongKong': '22.3193|114.1694|32',
    'Tokyo': '35.6762|139.6503|40', 'Seoul': '37.5665|126.9780|38',
    'Singapore': '1.3521|103.8198|15', 'NewYork': '40.7128|-74.0060|10',
    'London': '51.5074|-0.1278|25', 'Sydney': '-33.8688|151.2093|58',
    'Paris': '48.8566|2.3522|35', 'Berlin': '52.5200|13.4050|34',
    'Moscow': '55.7558|37.6173|156', 'Dubai': '25.2048|55.2708|16',
    'Mumbai': '19.0760|72.8777|14', 'Cairo': '30.0444|31.2357|23',
    'Rio': '-22.9068|-43.1729|5', 'LosAngeles': '34.0522|-118.2437|89',
    'Toronto': '43.6532|-79.3832|76', 'Mexico': '19.4326|-99.1332|2240',
    'Bangkok': '13.7563|100.5018|2', 'Istanbul': '41.0082|28.9784|39',
    'Amsterdam': '52.3676|4.9041|2', 'Stockholm': '59.3293|18.0686|28',
    'Reykjavik': '64.1466|-21.9426|61', 'CapeTown': '-33.9249|18.4241|25',
    'BuenosAires': '-34.6037|-58.3816|25', 'Honolulu': '21.3099|-157.8581|4',
  }
  const v = m[id]
  if (v === undefined) { return undefined }
  const p = v.split('|')
  const result: CityPreset = { lat: parseFloat(p[0]), lon: parseFloat(p[1]), alt: parseFloat(p[2]) }
  return result
}

export function telescopeUpdateTime(): string {
  const now = new Date()
  const hours = now.getHours().toString().padStart(2, '0')
  const minutes = now.getMinutes().toString().padStart(2, '0')
  const seconds = now.getSeconds().toString().padStart(2, '0')
  return hours + ':' + minutes + ':' + seconds
}

export function telescopeErrorText(result: TelescopeControlResponse, fallback: ResourceStr): ResourceStr {
  if (result.errorCode === 'no_selected_object') return I18n.t('m_telescope_select_target')
  if (result.errorCode === 'endpoint_blocked') return I18n.t('m_telescope_error_endpoint_blocked')
  if (result.errorCode === 'connect_failed') return I18n.t('m_telescope_error_connect_failed')
  if (result.errorCode === 'protocol_probe_failed') return I18n.t('m_telescope_error_protocol_probe')
  if (result.errorCode === 'command_timeout') return I18n.t('m_telescope_error_timeout')
  if (result.errorCode === 'ra_rejected' || result.errorCode === 'dec_rejected') return I18n.t('m_telescope_error_target_rejected')
  if (result.errorCode === 'slew_rejected') return I18n.t('m_telescope_error_slew_rejected')
  if (result.errorCode === 'coordinate_response_invalid') return I18n.t('m_telescope_error_position_invalid')
  return result.error ?? fallback
}

export function validationFromResponse(response: StellariumBridgeResponse): SkyCultureMakerValidation | undefined {
  const values = response as Record<string, Object>
  const source = values['validation'] !== undefined ? values['validation'] : response
  try {
    const validation = JSON.parse(JSON.stringify(source)) as SkyCultureMakerValidation
    return validation.errorCount !== undefined ? validation : undefined
  } catch (_error) {
    return undefined
  }
}

// Decomposing is only needed to strip Latin diacritics. Most location names are
// CJK or plain ASCII, where NFD is a no-op that still costs a full string pass,
// and this runs once per name per location on the search hot path.
const LOCATION_DECOMPOSE_RE = /[\u00c0-\u024f\u0300-\u036f]/

export function normalizeLocationSearchText(value: string): string {
  const lowered = value.toLocaleLowerCase()
  const plain = LOCATION_DECOMPOSE_RE.test(lowered)
    ? lowered.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    : lowered
  return plain.replace(/[\s._'’`-]+/g, '')
}

export function officialLocationAliases(countryCode: string): string {
  if (countryCode === 'TW') return ' 中国台湾地区 台湾 China Taiwan'
  if (countryCode === 'HK') return ' 中国香港特别行政区 香港 China Hong Kong'
  if (countryCode === 'MO') return ' 中国澳门特别行政区 澳门 China Macao Macau'
  return ''
}

export function sessionSignature(r: StellariumBridgeResponse): string {
  const v = r.viewJ2000
  const vr: number[] = (v && v.length === 3) ? v.map((x: number) => Math.round(x * 1e4) / 1e4) : [0, 0, 0]
  const locObj = r.location as Record<string, Object>
  const locName = (r.location && locObj['name'] !== undefined) ? String(locObj['name']) : ''
  return [vr.join(','), Math.round((r.fovDeg ?? 0) * 100) / 100, r.selected ?? '', locName].join('|')
}

// 面板路由查表（原宿主 panelRouteRoot / panelRouteParent，A2-6）：零宿主状态读取，纯查表，
// 与上方 *HubActions 同源，故并入本模块。函数体逐字搬入，仅去 this.。
export function panelRouteRoot(panel: string): string {
  const mainPanels = ['search', 'time', 'quick', 'layers', 'more']
  if (mainPanels.indexOf(panel) >= 0) return panel
  return 'more'
}

export function panelRouteParent(panel: string): string {
  if (panel === 'observeHub' || panel === 'dataHub' || panel === 'automationHub') return 'more'
  if (panel === 'pluginManager') return 'dataHub'
  if (observingHubActions().some((item: ShellAction) => item.panel === panel)) return 'observeHub'
  if (skyDataHubActions().some((item: ShellAction) => item.panel === panel)) return 'dataHub'
  if (automationHubActions().some((item: ShellAction) => item.panel === panel)) return 'automationHub'
  return ''
}

// 面板切换方向（原宿主 inferredPanelRouteDirection，A2-6 热路径 #6）。实测零宿主字段读取
// （仅调用上面两个纯函数），属 A1 残留而非 A2，故下沉本模块，语义逐字不变。
export function inferredPanelRouteDirection(fromPanel: string, toPanel: string): number {
  if (fromPanel === toPanel) return 1
  const routeOrder = ['search', 'time', 'quick', 'layers', 'more']
  const fromRoot = panelRouteRoot(fromPanel)
  const toRoot = panelRouteRoot(toPanel)
  const fromIndex = routeOrder.indexOf(fromRoot)
  const toIndex = routeOrder.indexOf(toRoot)
  if (fromIndex >= 0 && toIndex >= 0 && fromIndex !== toIndex) {
    return toIndex > fromIndex ? 1 : -1
  }
  if (panelRouteParent(toPanel) === fromPanel) return 1
  if (panelRouteParent(fromPanel) === toPanel) return -1
  if (panelRouteParent(fromPanel).length > 0 &&
    panelRouteParent(fromPanel) === panelRouteParent(toPanel)) return 1
  return 1
}

// 位置搜索文本匹配（原宿主 matchesLocationSearch / locationSearchMatchScore，A2-6）：零宿主读取，
// 只依赖入参与 normalizeLocationSearchText，属 A1 残留，故并入本模块。函数体逐字搬入。
export function matchesLocationSearch(text: string, query: string): boolean {
  const rawQuery = query.trim().toLocaleLowerCase()
  if (!rawQuery) return false
  const rawText = text.toLocaleLowerCase()
  return rawText.includes(rawQuery) ||
    normalizeLocationSearchText(rawText).includes(normalizeLocationSearchText(rawQuery))
}

// Scoring over text that is already normalised, so a caller that keeps a
// prepared index does no per-candidate string work at all.
export function locationSearchScoreNormalized(normalizedQuery: string, normalizedNames: Array<string>,
  normalizedText: string): number {
  if (!normalizedQuery) return 0
  let best = 0
  for (const normalizedName of normalizedNames) {
    if (!normalizedName) continue
    if (normalizedName === normalizedQuery) best = Math.max(best, 100)
    else if (normalizedName.startsWith(normalizedQuery)) best = Math.max(best, 85)
    else if (normalizedName.includes(normalizedQuery)) best = Math.max(best, 70)
  }
  if (best > 0) return best
  return normalizedText.includes(normalizedQuery) ? 40 : 0
}

export function locationSearchMatchScore(query: string, primaryNames: Array<string>, text: string): number {
  const names: Array<string> = primaryNames.map((name: string) => normalizeLocationSearchText(name))
  return locationSearchScoreNormalized(normalizeLocationSearchText(query), names, normalizeLocationSearchText(text))
}
