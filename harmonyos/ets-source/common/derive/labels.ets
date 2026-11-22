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
    return traditional ? '天宮空間站（天和核心艙）' : '天宫空间站（天和核心舱）'
  }
  if (key === 'CSSWENTIAN' || key === 'WENTIAN') {
    return traditional ? '天宮空間站（問天實驗艙）' : '天宫空间站（问天实验舱）'
  }
  if (key === 'CSSMENGTIAN' || key === 'MENGTIAN') {
    return traditional ? '天宮空間站（夢天實驗艙）' : '天宫空间站（梦天实验舱）'
  }
  if (key === 'CSS' || key === 'TIANGONG') {
    return traditional ? '天宮空間站' : '天宫空间站'
  }
  if (/^JILIN[-_ ]*1/i.test(value)) {
    const suffix = value.replace(/^JILIN[-_ ]*1/i, '').trim()
    const label = traditional ? '吉林一號' : '吉林一号'
    return suffix.length > 0 ? label + ' ' + suffix : label
  }
  const prefixes: SatelliteNamePrefix[] = [
    { token: 'STARLINK', label: traditional ? '星鏈' : '星链' },
    { token: 'BEIDOU', label: '北斗' },
    { token: 'QIANFAN', label: '千帆' },
    { token: 'HULIANWANG DIGUI', label: traditional ? '互聯低軌' : '互联低轨' },
    { token: 'HULIANWANG', label: traditional ? '互聯衛星' : '互联卫星' },
    { token: 'TIANLIAN', label: traditional ? '天鏈' : '天链' },
    { token: 'TIANTONG', label: '天通' },
    { token: 'TIANHUI', label: traditional ? '天繪' : '天绘' },
    { token: 'TIANQI', label: traditional ? '天啟' : '天启' },
    { token: 'FENGYUN', label: traditional ? '風雲' : '风云' },
    { token: 'YAOGAN', label: traditional ? '遙感' : '遥感' },
    { token: 'GAOFEN', label: '高分' },
    { token: 'SHIJIAN', label: traditional ? '實踐' : '实践' },
    { token: 'SHIYAN', label: traditional ? '試驗' : '试验' },
    { token: 'ZIYUAN', label: traditional ? '資源' : '资源' },
    { token: 'HAIYANG', label: '海洋' },
    { token: 'YUNHAI', label: traditional ? '雲海' : '云海' },
    { token: 'CHUANGXIN', label: traditional ? '創新' : '创新' },
    { token: 'JILIN', label: '吉林' },
    { token: 'ONEWEB', label: traditional ? '一網' : '一网' },
    { token: 'GLONASS', label: traditional ? '格洛納斯' : '格洛纳斯' },
    { token: 'GALILEO', label: '伽利略' },
    { token: 'IRIDIUM', label: traditional ? '銥星' : '铱星' },
    { token: 'GLOBALSTAR', label: '全球星' },
    { token: 'INTELSAT', label: traditional ? '國際通信' : '国际通信' },
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
  if (panel === 'mosaicCamera') return I18n.t('p_mosaic_camera')
  if (panel === 'archaeoLines') return I18n.t('p_archaeo_lines')
  if (panel === 'navStars') return I18n.t('panel_nav_stars')
  if (panel === 'pointerCoordinates') return I18n.t('p_pointer_coordinates')
  if (panel === 'scenery3d') return I18n.pluginName('Scenery3d')
  if (panel === 'telescope') return I18n.t('panel_telescope_control')
  if (panel === 'settings') return I18n.t('dock_settings')
  if (panel === 'satellites') return I18n.t('panel_satellites')
  if (panel === 'meteorshowers') return I18n.t('plugin_meteor_showers')
  if (panel === 'angleMeasure') return I18n.t('panel_angle_measure')
  if (panel === 'nebulaTextures') return I18n.t('nebula_texture_title')
  if (panel === 'skyCultureMaker') return I18n.t('sky_culture_maker_title')
  if (panel === 'calendars') return I18n.getLanguage().startsWith('zh') ? '世界多历法' : 'World Calendars'
  if (panel === 'minorBodies') return I18n.getLanguage().startsWith('zh') ? '太阳系小天体' : 'Minor Bodies'
  if (panel === 'nomenclature') return I18n.getLanguage().startsWith('zh') ? '行星地貌图集' : 'Planetary Nomenclature'
  if (panel === 'widgets') return I18n.getLanguage().startsWith('zh') ? '桌面小组件' : 'Desktop Widgets'
  return panel
}

// 插件中心功能分类：观测工具 / 深空数据 / 高级创作 / 未启用与桌面专用。
export function pluginCategoryFor(id: string): string {
  const route = pluginFeatureRoute(id)
  if (route.kind === 'offline' || route.kind === 'network' || route.kind === 'unavailable') {
    return 'inactive'
  }
  if (id === 'Oculars' || id === 'MosaicCamera' || id === 'AngleMeasure' ||
    id === 'NavStars' || id === 'PointerCoordinates' || id === 'ArchaeoLines' ||
    id === 'TelescopeControl') {
    return 'observe'
  }
  if (id === 'Satellites' || id === 'MeteorShowers' || id === 'Scenery3d' ||
    id === 'Exoplanets' || id === 'Pulsars' || id === 'Quasars' ||
    id === 'Novae' || id === 'Supernovae' || id === 'Calendars' ||
    id === 'SolarSystemEditor' ||
    id === 'Observability' || id === 'ObjectVisibility') {
    return 'data'
  }
  return 'advanced'
}

// 插件中心一句话白话用途（避免大段英文或开发术语污染主卡片）。
export function pluginConciseSummary(id: string, fallbackDesc: string): string {
  const isZh = I18n.getLanguage().startsWith('zh')
  if (!isZh) return fallbackDesc
  switch (id) {
    case 'Oculars': return '模拟望远镜目镜、相机画幅与寻星镜视野，辅助器材选配与构图。'
    case 'MosaicCamera': return '叠加多片深空相机视场网格，规划大天区马赛克拼接拍摄。'
    case 'AngleMeasure': return '在星图上直接拉线测量任意两颗天体之间的角距离与方位角。'
    case 'NavStars': return '高亮全球经典天文航海定位星表，辅助认星与航海天文练习。'
    case 'PointerCoordinates': return '在屏幕叠加实时指针赤道/地平/黄道坐标读数。'
    case 'ArchaeoLines': return '绘制冬至/夏至日出、月球停滞点等古天文方位参考线。'
    case 'TelescopeControl': return '通过局域网 LX200 协议连接并控制实体赤道仪自动寻星。'
    case 'Satellites': return '实时追踪空间站与万颗人造卫星轨道，计算可见过境预报。'
    case 'MeteorShowers': return '标注全年活跃流星雨辐射点、极大时刻与天顶每时出现率。'
    case 'Scenery3d': return '加载三维建筑与地貌场景，在真实立体环境中预览日月星辰。'
    case 'Exoplanets': return '检索并定位已发现的系外行星母恒星，查看宜居带与轨道参数。'
    case 'Pulsars': return '浏览银河系脉冲星目录，查看自转周期、色散量与位置标记。'
    case 'Quasars': return '探索遥远高红移类星体星表，快速跳转至星图对应深空区域。'
    case 'Novae': return '查阅历史明亮新星记录与爆发位置，重现历史天象。'
    case 'Supernovae': return '定位历史上著名超新星爆发位置与星等演化信息。'
    case 'Calendars': return '实时换算公历、儒略历、中国农历干支、藏历、伊斯兰历、希伯来历、玛雅历等 18 种世界历法。'
    case 'Observability':
    case 'ObjectVisibility': return '分析目标全年的最佳观测窗口、中天高度与可观测时长曲线。'
    case 'SkyCultureMaker': return '绘制与导出自定义星座连线、边界与星官文化资源包。'
    case 'NebulaTextures': return '导入自定义深空星云贴图与角坐标，叠加呈现至星图背景。'
    case 'EquationOfTime': return '显示真太阳时与平太阳时的均时差数值，辅助日晷与太阳观测。'
    case 'TimeNavigator': return '通过时间转轴与快捷时刻快速穿梭日出、中天与历史星空。'
    case 'RemoteControl': return '开启局域网 Web 远程控制台，用电脑浏览器或脚本遥控星图。'
    case 'TextUserInterface':
    case 'Text User Interface': return '通过快捷命令列表一键触发高级星图开关与专业指令。'
    case 'SolarSystemEditor': return '离线浏览已加载彗星、小行星与矮行星，一键导入内置千颗彗星库或 MPC 单行轨道根数。'
    case 'RemoteSync': return '局域网多设备星图视角同步模块（当前离线模式未启用）。'
    case 'OnlineQueries': return '在线天文数据库检索模块（离线版为保护隐私已停用）。'
    case 'Planes': return '实时民航航班叠加模块（需在线航班源，离线版已停用）。'
    case 'LensDistortionEstimator': return '桌面端鱼眼/广角镜头畸变标定工具，移动端暂未开放界面。'
    default: return fallbackDesc
  }
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
  if (id === 'Calendars') return { panel: 'calendars', kind: 'control' }
  if (id === 'SolarSystemEditor') return { panel: 'minorBodies', kind: 'control' }
  if (id === 'Observability') return { panel: 'astro', kind: 'host', astroTab: 4, graphMode: 3 }
  if (id === 'ObjectVisibility') return { panel: 'astro', kind: 'host', astroTab: 4, graphMode: 3 }
  if (id === 'TextUserInterface' || id === 'Text User Interface') return { panel: 'commands', kind: 'host' }
  if (id === 'NebulaTextures') return { panel: 'nebulaTextures', kind: 'control' }
  if (id === 'SkyCultureMaker') return { panel: 'skyCultureMaker', kind: 'control' }
  if (id === 'Planes') return { panel: '', kind: 'network' }
  if (id === 'Exoplanets' || id === 'Pulsars' || id === 'Quasars' || id === 'Novae' || id === 'Supernovae') {
    return { panel: 'search', kind: 'catalog', catalogModuleId: id }
  }
  // 无线控制已经在「设置 → 主设置」里落地（开关 + 端口 + 访问地址），这里直接跳过去，
  // 别再报"离线构建不支持"。
  if (id === 'RemoteControl') return { panel: 'settings', kind: 'host' }
  if (id === 'OnlineQueries' || id === 'RemoteSync') {
    return { panel: '', kind: 'offline' }
  }
  if (id === 'LensDistortionEstimator' || id === 'Vts' ||
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
export function quickLocationLabel(source: string, displayName: string,
  planetName: string = 'Earth', detail: string = ''): string {
  if (source === 'gps' && planetName === 'Earth') {
    return detail.length > 0 ? I18n.t('loc_source_gps') + ' · ' + detail : I18n.t('loc_source_gps')
  }
  if (source === 'map') {
    // Map picks now carry a reverse-geocoded local name; keep the generic
    // label only when the name is empty or still the placeholder.
    return displayName.length > 0 && displayName !== I18n.t('custom_location')
      ? displayName : I18n.t('custom_location')
  }
  return displayName.length > 0 ? displayName : I18n.t('custom_location')
}

// 面板标题文本（计划 §14.3 A2-5；原宿主 private panelTitle 逐字迁出）。
// 读宿主控制器状态（activePanel / configTab / isExpandedLayout）与时间面板实时钟文本，
// 按 §14.8 规则 6 改为显式入参，其余逐字不变。
export function panelTitleFor(activePanel: string, configTab: number, isExpandedLayout: boolean, timeText: string, locationLabel: string = '', calendarDetailOpen: boolean = false): ResourceStr {
  if (activePanel === 'calendar') {
    if (calendarDetailOpen) {
      return I18n.getLanguage().startsWith('zh') ? '天象详情' : 'Event details'
    }
    return I18n.getLanguage().startsWith('zh') ? '天象日历' : 'Astronomy calendar'
  }
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
  if (activePanel === 'ar') {
    return I18n.getLanguage().startsWith('zh') ? 'AR 实景观星' : 'AR Sky View'
  }
  if (activePanel === 'devTools') {
    return I18n.t('panel_dev_tools')
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
    return I18n.t('c_help')
  }
  if (activePanel === 'settings') {
    if (configTab === 8) return I18n.t('c_about')
    if (configTab === 6) return I18n.t('more_plugins_manage')
    if (configTab === 7) return I18n.t('settings_view_navigation')
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
  if (activePanel === 'calendars') {
    return I18n.getLanguage().startsWith('zh') ? '世界多历法' : 'World Calendars'
  }
  if (activePanel === 'minorBodies') {
    return I18n.getLanguage().startsWith('zh') ? '太阳系小天体' : 'Minor Bodies'
  }
  if (activePanel === 'nomenclature') {
    return I18n.getLanguage().startsWith('zh') ? '行星地貌图集' : 'Planetary Nomenclature'
  }
  if (activePanel === 'widgets') {
    return I18n.getLanguage().startsWith('zh') ? '桌面小组件' : 'Desktop Widgets'
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
