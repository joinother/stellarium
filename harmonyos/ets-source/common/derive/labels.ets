// 标签 / 文案 / 命名纯函数。
// 依据计划 §14.2 轨道 A1-3，逐字从 pages/MainWindowNativeNode.ets 的私有方法迁出。
// 这些函数零 this、零 IO、零桥、零 store 依赖，只依赖入参、静态 I18n 查表与
// PluginFeatureRoute 类型；宿主与 panels 直连本模块（§14.8 规则 6：不 import store）。

import { I18n } from '../../pages/I18n'
import { PluginFeatureRoute } from '../../pages/MainWindowModels'
import { SatelliteNamePrefix } from '../../common/types/StellariumTypes'
import { clamp } from './astro'

// 资源文案：空值 / 全空白时回退到给定占位文本。
export function resourceText(value: string | undefined, fallback: string): string {
  return value !== undefined && value.trim().length > 0 ? value.trim() : fallback
}

// 解码错误 → "Name: message" 文本（媒体管线日志用）。
export function describeDecodeError(err: Error): string {
  const name = err.name !== undefined && err.name.length > 0 ? err.name : 'Error'
  const message = err.message !== undefined && err.message.length > 0 ? err.message : 'unknown failure'
  return name + ': ' + message
}

// 卫星名称本地化：把常见卫星罗马名 / 关键型号映射为中文（ISS→国际空间站、CSS→中国空间站…）。
// 仅中文语言下生效；无匹配返回空串，由调用方回落到通用名称。
export function satelliteLocalizedName(raw: string): string {
  const language = I18n.getLanguage()
  if (language !== 'zh_CN' && language !== 'zh_TW' && language !== 'zh_HK') return ''
  const value = raw.trim()
  const key = value.toUpperCase().replace(/[（）()\s_-]/g, '')
  const traditional = language !== 'zh_CN'
  if (key === 'ISS' || key === 'ISSZARYA') {
    return traditional ? '國際太空站（曙光號功能貨艙）' : '国际空间站（曙光号功能货舱）'
  }
  if (key === 'ISSNAUKA') {
    return traditional ? '國際太空站（科學號艙段）' : '国际空间站（科学号舱段）'
  }
  if (key === 'CSSTIANHE' || key === 'TIANGONGTIANHE' || key === 'TIANHE') {
    return traditional ? '中國空間站（天和核心艙）' : '中国空间站（天和核心舱）'
  }
  if (key === 'CSSWENTIAN' || key === 'WENTIAN') {
    return traditional ? '中國空間站（問天實驗艙）' : '中国空间站（问天实验舱）'
  }
  if (key === 'CSSMENGTIAN' || key === 'MENGTIAN') {
    return traditional ? '中國空間站（夢天實驗艙）' : '中国空间站（梦天实验舱）'
  }
  if (key === 'CSS' || key === 'TIANGONG') {
    return traditional ? '中國空間站' : '中国空间站'
  }
  if (/^JILIN[-_ ]*1/i.test(value)) {
    const suffix = value.replace(/^JILIN[-_ ]*1/i, '').trim()
    const label = traditional ? '吉林一號' : '吉林一号'
    return suffix.length > 0 ? label + ' ' + suffix : label
  }
  const prefixes: SatelliteNamePrefix[] = [
    { token: 'STARLINK', label: traditional ? '星鏈' : '星链' },
    { token: 'BEIDOU', label: '北斗' },
    { token: 'TIANLIAN', label: traditional ? '天鏈' : '天链' },
    { token: 'TIANTONG', label: '天通' },
    { token: 'FENGYUN', label: traditional ? '風雲' : '风云' },
    { token: 'YAOGAN', label: traditional ? '遙感' : '遥感' },
    { token: 'GAOFEN', label: '高分' },
    { token: 'SHIJIAN', label: traditional ? '實踐' : '实践' },
    { token: 'SHIYAN', label: traditional ? '實驗' : '实验' },
    { token: 'ZIYUAN', label: traditional ? '資源' : '资源' },
    { token: 'JILIN', label: '吉林' },
    { token: 'GLONASS', label: traditional ? '格洛納斯' : '格洛纳斯' },
    { token: 'GALILEO', label: '伽利略' },
    { token: 'IRIDIUM', label: traditional ? '銥星' : '铱星' },
    { token: 'GLOBALSTAR', label: '全球星' },
    { token: 'INTELSAT', label: traditional ? '國際通信衛星' : '国际通信卫星' },
    { token: 'GONETS', label: '戈涅斯' },
    { token: 'COSMOS', label: traditional ? '宇宙號' : '宇宙号' },
    { token: 'QZSS', label: traditional ? '準天頂' : '准天顶' }
  ]
  for (const item of prefixes) {
    const token = item.token.toUpperCase()
    if (!key.startsWith(token)) continue
    const suffix = value.substring(item.token.length).replace(/^[\s_-]+/, '').trim()
    return suffix.length > 0 ? item.label + ' ' + suffix : item.label
  }
  return ''
}

// 天体名称本地化：仅中文语言下裁掉尾部英文 / 拉丁名（"天狼 Sirius" → "天狼"）。
export function zhNameOf(raw: string): string {
  if (!raw || raw.length === 0) { return raw }
  const value = raw.trim()
  if (I18n.getLanguage() !== 'zh_CN' && I18n.getLanguage() !== 'zh_TW') { return value }
  const satelliteName = satelliteLocalizedName(value)
  if (satelliteName.length > 0) return satelliteName
  // Stellarium 的官方中文星名有时保留英文/拉丁名，例如“天狼 Sirius”。
  // 主标题只显示中文部分，英文名和目录号由独立副标题承载。
  if (!/[一-鿿]/.test(value)) { return value }
  return value.replace(/\s+[A-Za-z][A-Za-z0-9 .-]*$/, '').trim()
}

// 天体类型本地化（Planet→行星…）；支持复合类型。
export function zhType(type: string): string {
  return I18n.objectType(type)
}

// ===== 中文映射（数据层英文名 → 界面中文） =====

export function planetZh(en: string): string {
  switch (en) {
    case 'Sun': return I18n.t('pl_sun')
    case 'Moon': return I18n.t('pl_moon')
    case 'Mercury': return I18n.t('pl_mercury')
    case 'Venus': return I18n.t('pl_venus')
    case 'Earth': return I18n.t('pl_earth')
    case 'Mars': return I18n.t('pl_mars')
    case 'Jupiter': return I18n.t('pl_jupiter')
    case 'Saturn': return I18n.t('pl_saturn')
    case 'Uranus': return I18n.t('pl_uranus')
    case 'Neptune': return I18n.t('pl_neptune')
    default: return en
  }
}

export function sensZh(en: string): string {
  switch (en) {
    case 'Standard': return I18n.t('sens_standard')
    case 'Fast': return I18n.t('sens_fast')
    case 'Slow': return I18n.t('sens_slow')
    default: return en
  }
}

export function pluginZh(en: string): string {
  // 先查精确映射（保持已有 key 的一致性）
  switch (en) {
    case 'Angle Measure': return I18n.t('panel_angle_measure')
    case 'ArchaeoLines': return I18n.t('plugin_archaeolines')
    case 'Calendars': return I18n.t('plugin_calendars')
    case 'Equation of Time': return I18n.t('plugin_equation_of_time')
    case 'EquationOfTime': return I18n.t('plugin_equation_of_time')
    case 'Exoplanets': return I18n.t('plugin_exoplanets')
    case 'Lens distortion estimator': return I18n.t('plugin_lens_distortion')
    case 'LensDistortionEstimator': return I18n.t('plugin_lens_distortion')
    case 'Meteor Showers': return I18n.t('plugin_meteor_showers')
    case 'Novae': return I18n.t('plugin_novae')
    case 'Pulsars': return I18n.t('plugin_pulsars')
    case 'Quasars': return I18n.t('plugin_quasars')
    case 'Satellites': return I18n.t('plugin_satellites')
    case 'Solar System Editor': return I18n.t('plugin_solar_system_editor')
    case 'SolarSystemEditor': return I18n.t('plugin_solar_system_editor')
    case 'Supernovae': return I18n.t('plugin_supernovae')
    case 'TextUserInterface':
    case 'Text User Interface': return I18n.t('plugin_text_user_interface')
    case 'TimeNavigator': return I18n.pluginName('Time Navigator')
    case 'Time Zone': return I18n.t('plugin_time_zone')
    case 'Oculars': return I18n.t('panel_oculars')
    case 'Voculars': return I18n.t('plugin_voculars')
    case 'Observability': return I18n.t('plugin_observability')
    case 'Remote Control': return I18n.t('plugin_remote_control')
    case 'Screenshots': return I18n.t('plugin_screenshots')
    case 'Sky Cultures': return I18n.t('plugin_skycultures')
    case 'SkyCultureMaker': return I18n.pluginName('Sky Culture Maker')
    case 'ObjectVisibility': return I18n.pluginName('Object Visibility')
  }
  // 回退到 PLUGIN_NAMES 字典（覆盖所有 40+ 插件）
  const dictName = I18n.pluginName(en)
  if (dictName !== en) return dictName
  // 最后兜底：尝试首字母大写等微调后再查一次
  const trimmed = en.trim()
  return I18n.pluginName(trimmed) !== trimmed ? I18n.pluginName(trimmed) : en
}

// ── 插件功能描述（副标题） ──
export function pluginDesc(en: string): string {
  switch (en) {
    case 'Angle Measure': return I18n.t('plugin_desc_angle_measure') as string
    case 'ArchaeoLines': return I18n.t('plugin_desc_archaeolines') as string
    case 'Calendars': return I18n.t('plugin_desc_calendars') as string
    case 'Equation of Time': return I18n.t('plugin_desc_equation_of_time') as string
    case 'Exoplanets': return I18n.t('plugin_desc_exoplanets') as string
    case 'Lens distortion estimator': return I18n.t('plugin_desc_lens_distortion') as string
    case 'Meteor Showers': return I18n.t('plugin_desc_meteor_showers') as string
    case 'Novae': return I18n.t('plugin_desc_novae') as string
    case 'Observability': return I18n.t('plugin_desc_observability') as string
    case 'Pulsars': return I18n.t('plugin_desc_pulsars') as string
    case 'Quasars': return I18n.t('plugin_desc_quasars') as string
    case 'Remote Control': return I18n.t('plugin_desc_remote_control') as string
    case 'Satellites': return I18n.t('plugin_desc_satellites') as string
    case 'Screenshots': return I18n.t('plugin_desc_screenshots') as string
    case 'Sky Cultures': return I18n.t('plugin_desc_skycultures') as string
    case 'Solar System Editor': return I18n.t('plugin_desc_solar_system_editor') as string
    case 'Supernovae': return I18n.t('plugin_desc_supernovae') as string
    case 'TextUserInterface':
    case 'Text User Interface': return I18n.t('plugin_desc_text_user_interface') as string
    case 'Time Zone': return I18n.t('plugin_desc_time_zone') as string
    case 'Oculars': return I18n.t('plugin_desc_voculars') as string
    case 'Voculars': return I18n.t('plugin_desc_voculars') as string
  }
  return ''
}

// ── 脚本文件名 → 中文名 ──
export function scriptZh(filename: string): string {
  // 去掉 .ssc 后缀
  const name = filename.replace(/\.ssc$/, '')
  switch (name) {
    case 'constellations_tour': return I18n.t('script_name_constellations_tour')
    case 'modern_constellations_tour': return I18n.t('script_name_modern_constellations_tour')
    case 'messier_marathon': return I18n.t('script_name_messier_marathon')
    case 'BAS_Messier_Tour': return I18n.t('script_name_BAS_Messier_Tour')
    case 'planets_tour': return I18n.t('script_name_planets_tour')
    case 'BAS_Jupiter_Moons': return I18n.t('script_name_BAS_Jupiter_Moons')
    case 'lunar_total': return I18n.t('script_name_lunar_total')
    case 'lunar_partial': return I18n.t('script_name_lunar_partial')
    case 'solar_eclipse': return I18n.t('script_name_solar_eclipse')
    case 'transit_of_venus': return I18n.t('script_name_transit_of_venus')
    case 'supernova': return I18n.t('script_name_supernova')
    case 'triple_sunrise_and_sunsets': return I18n.t('script_name_triple_sunrise_and_sunsets')
    case 'analemma': return I18n.t('script_name_analemma')
    case 'martian_analemma': return I18n.t('script_name_martian_analemma')
    case 'saturnian_analemma': return I18n.t('script_name_saturnian_analemma')
    case 'uranian_analemma': return I18n.t('script_name_uranian_analemma')
    case 'best_ngc': return I18n.t('script_name_best_ngc')
    case 'h400_tour': return I18n.t('script_name_h400_tour')
    case 'double_stars': return I18n.t('script_name_double_stars')
    case 'largest_known_stars': return I18n.t('script_name_largest_known_stars')
    case 'binocular_highlights': return I18n.t('script_name_binocular_highlights')
    case 'binosky': return I18n.t('script_name_binosky')
    case 'bennett': return I18n.t('script_name_bennett')
    case 'sky_cultures': return I18n.t('script_name_sky_cultures')
    case 'landscapes': return I18n.t('script_name_landscapes')
    case 'screensaver': return I18n.t('script_name_screensaver')
    case 'solar_system_screensaver': return I18n.t('script_name_solar_system_screensaver')
    case 'skybox': return I18n.t('script_name_skybox')
    case 'random_location': return I18n.t('script_name_random_location')
    case 'sun': return I18n.t('script_name_sun')
    case 'zodiac': return I18n.t('script_name_zodiac')
    case 'phobos_phun_1': return I18n.t('script_name_phobos_phun_1')
    case 'phobos_phun_2': return I18n.t('script_name_phobos_phun_2')
    case 'phobos_phun_3': return I18n.t('script_name_phobos_phun_3')
    case 'phobos_phun_4': return I18n.t('script_name_phobos_phun_4')
    case 'phobos_phun_5': return I18n.t('script_name_phobos_phun_5')
    case 'morsels_1': return I18n.t('script_name_morsels_1')
    case 'morsels_2': return I18n.t('script_name_morsels_2')
    case 'morsels_3': return I18n.t('script_name_morsels_3')
    case 'morsels_4': return I18n.t('script_name_morsels_4')
    case 'earth_1': return I18n.t('script_name_earth_1')
    case 'earth_2': return I18n.t('script_name_earth_2')
    case 'earth_3': return I18n.t('script_name_earth_3')
    case 'earth_4': return I18n.t('script_name_earth_4')
    case 'earth_5': return I18n.t('script_name_earth_5')
    case 'earth_6': return I18n.t('script_name_earth_6')
    case 'earth_7': return I18n.t('script_name_earth_7')
    case 'startup': return I18n.t('script_name_startup')
    default: return filename
  }
}

// ── 脚本简短描述 ──
export function scriptDesc(filename: string): string {
  const name = filename.replace(/\.ssc$/, '')
  switch (name) {
    case 'constellations_tour': return I18n.t('script_desc_constellations_tour') as string
    case 'modern_constellations_tour': return I18n.t('script_desc_constellations_tour') as string
    case 'messier_marathon': return I18n.t('script_desc_messier_marathon') as string
    case 'BAS_Messier_Tour': return I18n.t('script_desc_messier_marathon') as string
    case 'planets_tour': return I18n.t('script_desc_planets_tour') as string
    case 'BAS_Jupiter_Moons': return I18n.t('script_desc_gral') as string
    case 'lunar_total': return I18n.t('script_desc_lunar_total') as string
    case 'lunar_partial': return I18n.t('script_desc_gral') as string
    case 'solar_eclipse': return I18n.t('script_desc_solar_eclipse') as string
    case 'transit_of_venus': return I18n.t('script_desc_gral') as string
    case 'supernova': return I18n.t('script_desc_gral') as string
    case 'triple_sunrise_and_sunsets': return I18n.t('script_desc_gral') as string
    case 'analemma': return I18n.t('script_desc_analemma') as string
    case 'martian_analemma': return I18n.t('script_desc_gral') as string
    case 'saturnian_analemma': return I18n.t('script_desc_gral') as string
    case 'uranian_analemma': return I18n.t('script_desc_gral') as string
    case 'best_ngc': return I18n.t('script_desc_best_ngc') as string
    case 'h400_tour': return I18n.t('script_desc_gral') as string
    case 'double_stars': return I18n.t('script_desc_double_stars') as string
    case 'largest_known_stars': return I18n.t('script_desc_gral') as string
    case 'binocular_highlights': return I18n.t('script_desc_binocular_highlights') as string
    case 'binosky': return I18n.t('script_desc_gral') as string
    case 'bennett': return I18n.t('script_desc_gral') as string
    case 'sky_cultures': return I18n.t('script_desc_sky_cultures') as string
    case 'landscapes': return I18n.t('script_desc_gral') as string
    case 'screensaver': return I18n.t('script_desc_screensaver') as string
    case 'solar_system_screensaver': return I18n.t('script_desc_gral') as string
    case 'skybox': return I18n.t('script_desc_gral') as string
    case 'random_location': return I18n.t('script_desc_random_location') as string
    case 'sun': return I18n.t('script_desc_gral') as string
    case 'zodiac': return I18n.t('script_desc_gral') as string
    default: return ''
  }
}

// 插件功能所属宿主面板 → 中文面板名。
export function pluginHostName(panel: string): string {
  if (panel === 'search') return I18n.t('dock_search')
  if (panel === 'time') return I18n.t('dock_time')
  if (panel === 'astro') return I18n.t('i0274')
  if (panel === 'layers') return I18n.t('i0100')
  if (panel === 'catalogs') return I18n.t('p_catalogs')
  if (panel === 'tools') return I18n.t('panel_tools_data')
  if (panel === 'commands') return I18n.t('panel_commands')
  if (panel === 'oculars') return I18n.t('panel_oculars')
  if (panel === 'satellites') return I18n.t('panel_satellites')
  if (panel === 'meteorshowers') return I18n.t('plugin_meteor_showers')
  if (panel === 'angleMeasure') return I18n.t('panel_angle_measure')
  if (panel === 'nebulaTextures') return I18n.t('nebula_texture_title')
  if (panel === 'skyCultureMaker') return I18n.t('sky_culture_maker_title')
  return panel
}

// 插件 id → 面板路由（panel / kind / 附带 tab）。
export function pluginFeatureRoute(id: string): PluginFeatureRoute {
  if (id === 'Oculars') return { panel: 'oculars', kind: 'control' }
  if (id === 'Satellites') return { panel: 'satellites', kind: 'control' }
  if (id === 'MeteorShowers') return { panel: 'meteorshowers', kind: 'control' }
  if (id === 'AngleMeasure') return { panel: 'angleMeasure', kind: 'control' }
  if (id === 'MosaicCamera') return { panel: 'mosaicCamera', kind: 'control' }
  if (id === 'ArchaeoLines') return { panel: 'archaeoLines', kind: 'control' }
  if (id === 'NavStars') return { panel: 'navStars', kind: 'control' }
  if (id === 'PointerCoordinates') return { panel: 'pointerCoordinates', kind: 'control' }
  if (id === 'Scenery3d') return { panel: 'scenery3d', kind: 'control' }
  if (id === 'TelescopeControl') return { panel: 'telescope', kind: 'control' }
  if (id === 'EquationOfTime') return { panel: 'time', kind: 'host' }
  if (id === 'TimeNavigator') return { panel: 'time', kind: 'host' }
  if (id === 'Calendars') return { panel: 'astro', kind: 'host', astroTab: 8 }
  if (id === 'Observability') return { panel: 'astro', kind: 'host', astroTab: 4, graphMode: 3 }
  if (id === 'ObjectVisibility') return { panel: 'astro', kind: 'host', astroTab: 4, graphMode: 3 }
  if (id === 'TextUserInterface' || id === 'Text User Interface') return { panel: 'commands', kind: 'host' }
  if (id === 'NebulaTextures') return { panel: 'nebulaTextures', kind: 'control' }
  if (id === 'SkyCultureMaker') return { panel: 'skyCultureMaker', kind: 'control' }
  if (id === 'Planes') return { panel: '', kind: 'network' }
  if (id === 'Exoplanets' || id === 'Pulsars' || id === 'Quasars' || id === 'Novae' || id === 'Supernovae') {
    return { panel: 'search', kind: 'catalog', catalogModuleId: id }
  }
  if (id === 'OnlineQueries' || id === 'RemoteControl' || id === 'RemoteSync') {
    return { panel: '', kind: 'offline' }
  }
  if (id === 'LensDistortionEstimator' || id === 'SolarSystemEditor' || id === 'Vts' ||
    id === 'Oculus' || id === 'SimpleDrawLine' || id === 'HelloStelModule') {
    return { panel: '', kind: 'unavailable' }
  }
  return { panel: '', kind: 'unavailable' }
}

// IANA 时区名 → 本地化显示文本（计划 §14.2 A1-7 迁入；只依赖静态 I18n 查表）。
export function timezoneDisplayName(ianaTz: string): string {
  if (!ianaTz || ianaTz === 'system_default') return I18n.t('tz_system')
  // Translate common IANA timezone names
  const tzMap: Record<string, string> = {
    'Asia/Shanghai': I18n.t('tz_asia_shanghai'),
    'Asia/Hong_Kong': I18n.t('tz_asia_hongkong'),
    'Asia/Tokyo': I18n.t('tz_asia_tokyo'),
    'Asia/Seoul': I18n.t('tz_asia_seoul'),
    'Asia/Singapore': I18n.t('tz_asia_singapore'),
    'Asia/Taipei': I18n.t('tz_asia_taipei'),
    'Asia/Bangkok': I18n.t('tz_asia_bangkok'),
    'Asia/Kolkata': I18n.t('tz_asia_kolkata'),
    'Asia/Dubai': I18n.t('tz_asia_dubai'),
    'Europe/London': I18n.t('tz_europe_london'),
    'Europe/Paris': I18n.t('tz_europe_paris'),
    'Europe/Berlin': I18n.t('tz_europe_berlin'),
    'Europe/Madrid': I18n.t('tz_europe_madrid'),
    'Europe/Moscow': I18n.t('tz_europe_moscow'),
    'America/New_York': I18n.t('tz_america_newyork'),
    'America/Chicago': I18n.t('tz_america_chicago'),
    'America/Los_Angeles': I18n.t('tz_america_losangeles'),
    'America/Sao_Paulo': I18n.t('tz_america_saopaulo'),
    'Australia/Sydney': I18n.t('tz_australia_sydney'),
    'Pacific/Auckland': I18n.t('tz_pacific_auckland'),
    'UTC': 'UTC',
    'GMT': 'GMT',
  }
  const mapped = tzMap[ianaTz]
  if (mapped) return mapped
  // For unmapped, try to translate the region/city names
  const parts = ianaTz.split('/')
  if (parts.length >= 2) {
    const regionMap: Record<string, string> = {
      'Asia': I18n.t('tz_region_asia'),
      'Europe': I18n.t('tz_region_europe'),
      'America': I18n.t('tz_region_america'),
      'Africa': I18n.t('tz_region_africa'),
      'Pacific': I18n.t('tz_region_pacific'),
      'Australia': I18n.t('tz_region_australia'),
      'Antarctica': I18n.t('tz_region_antarctica'),
      'Atlantic': I18n.t('tz_region_atlantic'),
      'Indian': I18n.t('tz_region_indian'),
      'Arctic': I18n.t('tz_region_arctic'),
    }
    const region = regionMap[parts[0]] ?? parts[0]
    const city = parts[parts.length - 1].replace(/_/g, ' ')
    return region + ' / ' + city
  }
  return ianaTz
}

// 快捷操作面板标题栏的观测点文案（按来源取值，见 QUICK-ACTIONS-PANEL-PLAN.md §11.3）：
// gps → `GPS`；map → 「自定义位置」；其余 → 名称本身。
// 不能复用宿主的 locationText —— 它由引擎轮询覆写，会把 `GPS` 冲掉。
export function quickLocationLabel(source: string, displayName: string, planetName: string = 'Earth'): string {
  if (source === 'gps' && planetName === 'Earth') {
    return I18n.t('loc_source_gps')
  }
  if (source === 'map') {
    return I18n.t('custom_location')
  }
  return displayName.length > 0 ? displayName : I18n.t('custom_location')
}

// 面板标题文本（计划 §14.3 A2-5；原宿主 private panelTitle 逐字迁出）。
// 读宿主控制器状态（activePanel / configTab / isExpandedLayout）与时间面板实时钟文本，
// 按 §14.8 规则 6 改为显式入参，其余逐字不变。
export function panelTitleFor(activePanel: string, configTab: number, isExpandedLayout: boolean, timeText: string, locationLabel: string = ''): ResourceStr {
  if (activePanel === 'more') {
    return I18n.t('c_more_functions')
  }
  if (activePanel === 'observeHub') {
    return I18n.t('more_workspace_observing')
  }
  if (activePanel === 'dataHub') {
    return I18n.t('more_sky_data')
  }
  if (activePanel === 'automationHub') {
    return I18n.t('more_automation')
  }
  if (activePanel === 'search') {
    return isExpandedLayout ? '探索' : I18n.t('i0021')
  }
  if (activePanel === 'observing') {
    return I18n.t('panel_observing_list')
  }
  if (activePanel === 'time') {
    return I18n.t('i0054') + ' ' + timeText
  }
  if (activePanel === 'place') {
    return I18n.t('i0014')
  }
  if (activePanel === 'layers') {
    return I18n.t('i0100')
  }
  // 快捷操作面板：标题栏直接显示当前位置（该标题本身是按钮），文案由宿主按来源算好后传入。
  if (activePanel === 'quick') {
    return locationLabel.length > 0 ? locationLabel : I18n.t('dock_quick')
  }
  if (activePanel === 'config') {
    return I18n.t('i0273')
  }
  if (activePanel === 'astro') {
    return I18n.t('i0274')
  }
  if (activePanel === 'help') {
    return I18n.t('i0217')
  }
  if (activePanel === 'settings') {
    if (configTab === 6) return I18n.t('more_plugins_manage')
    if (configTab === 7) return I18n.t('settings_view_navigation')
    if (configTab === 4) return I18n.t('c0004')
    if (configTab === 5) return I18n.t('c0005')
    if (configTab === 3) return I18n.t('c0003')
    if (configTab === 2) return I18n.t('c0002')
    if (configTab === 1) return I18n.t('c0001')
    if (configTab === -1) return I18n.t('settings_device_privacy')
    return I18n.t('i0102')
  }
  if (activePanel === 'catalogs') {
    return I18n.t('p_catalogs')
  }
  if (activePanel === 'bookmarks') {
    return I18n.t('p_bookmarks')
  }
  if (activePanel === 'oculars') {
    return I18n.t('p_oculars')
  }
  if (activePanel === 'mosaicCamera') {
    return I18n.t('p_mosaic_camera')
  }
  if (activePanel === 'archaeoLines') {
    return I18n.t('p_archaeo_lines')
  }
  if (activePanel === 'angleMeasure') {
    return I18n.t('panel_angle_measure')
  }
  if (activePanel === 'navStars') {
    return I18n.t('panel_nav_stars')
  }
  if (activePanel === 'satellites') {
    return I18n.t('p_satellites')
  }
  if (activePanel === 'meteorshowers') {
    return I18n.t('p_meteors')
  }
  if (activePanel === 'scenery3d') {
    return I18n.pluginName('Scenery3d')
  }
  if (activePanel === 'nebulaTextures') {
    return I18n.t('nebula_texture_title')
  }
  if (activePanel === 'skyCultureMaker') {
    return I18n.t('sky_culture_maker_title')
  }
  if (activePanel === 'pointerCoordinates') {
    return I18n.t('p_pointer_coordinates')
  }
  if (activePanel === 'scripts') {
    return I18n.t('p_scripts')
  }
  if (activePanel === 'commands') {
    return I18n.t('panel_commands')
  }
  if (activePanel === 'telescope') {
    return I18n.t('panel_telescope_control')
  }
  if (activePanel === 'tools') {
    return I18n.t('panel_tools_data')
  }
  return I18n.t('i0101')
}

// 天体标题：本地化名非空时优先，否则回退英文名（原宿主 private celestialTitle，逐字迁出）。
export function celestialTitle(nativeName: string, englishName: string): string {
  const localizedNative = zhNameOf(nativeName)
  return localizedNative.length > 0 ? localizedNative : englishName
}

// 经度 → 粗略时区显示文本（计划 §14.5 B2R-2 时区助手；原宿主 private approximateTimeZoneDisplay，
// 逐字迁出）。纯函数：只用入参 + clamp，供 LocationPickerStore.loadObserverInfo 与宿主 setLocation 共用。
export function approximateTimeZoneDisplay(longitude: number): string {
  const offset = clamp(Math.round(longitude / 15), -12, 14)
  if (offset === 0) {
    return 'UTC'
  }
  return 'UTC' + (offset > 0 ? '+' : '') + offset.toString()
}
