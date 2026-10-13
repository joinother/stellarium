// 目录图标 / “今晚可见”（WUT）分类纯函数。
// 依据计划 §14.2 轨道 A1-7，逐字从 pages/MainWindowNativeNode.ets 的私有方法迁出。
// 这些函数零 this、零 IO、零桥、零 store 依赖，只依赖入参、静态查表与 TabItem 类型；
// 宿主与 panels 直连本模块（§14.8 规则 6：不 import store）。

import { TabItem } from '../../pages/StellariumTypes'

// 目录模块 id → 图标资源 key。
export function catalogIconForModule(moduleId: string): string {
  const module = moduleId.toLowerCase()
  if (module.indexOf('planes') >= 0 || module.indexOf('aircraft') >= 0) return 'catalog_aircraft'
  if (module.indexOf('satellite') >= 0 || module.indexOf('artificial') >= 0) return 'catalog_satellite'
  if (module.indexOf('exoplanet') >= 0) return 'catalog_exoplanet'
  if (module.indexOf('pulsar') >= 0) return 'catalog_pulsar'
  if (module.indexOf('quasar') >= 0) return 'catalog_quasar'
  if (module.indexOf('supernova') >= 0) return 'catalog_supernova'
  if (module.indexOf('nova') >= 0) return 'catalog_nova'
  if (module.indexOf('meteor') >= 0) return 'meteor'
  if (module.indexOf('telescope') >= 0) return 'telescope'
  if (module.indexOf('solarsystem:moon') >= 0) return 'catalog_moon'
  if (module.indexOf('solarsystem:planet') >= 0 || module.indexOf('dwarf planet') >= 0) return 'catalog_planet'
  if (module.indexOf('solarsystem:comet') >= 0) return 'catalog_comet'
  if (module.indexOf('solarsystem:') >= 0) return 'catalog_asteroid'
  if (module.indexOf('nebulamgr:0') >= 0 || module.indexOf('nebulamgr:1') >= 0 || module.indexOf('nebulamgr:2') >= 0 || module.indexOf('nebulamgr:3') >= 0) return 'catalog_galaxy'
  if (module.indexOf('nebulamgr:4') >= 0) return 'catalog_quasar'
  if (module.indexOf('nebulamgr:5') >= 0 || module.indexOf('nebulamgr:6') >= 0 || module.indexOf('nebulamgr:7') >= 0 || module.indexOf('nebulamgr:8') >= 0) return 'catalog_cluster'
  if (module.indexOf('nebulamgr:') >= 0) return 'catalog_nebula'
  if (module.indexOf('constellation') >= 0 || module.indexOf('asterism') >= 0) return 'catalog_constellation'
  return 'catalog_plugin'
}

// 对象类型文本（含中文/英文）→ 图标资源 key，未命中回退 fallback。
export function catalogIconForObjectType(rawType: string, fallback: string): string {
  const type = rawType.toLowerCase()
  if (type.indexOf('aircraft') >= 0 || type.indexOf('flight') >= 0 || type.indexOf('飞机') >= 0) return 'catalog_aircraft'
  if (type.indexOf('supernova') >= 0 || type.indexOf('超新星') >= 0) return 'catalog_supernova'
  if (type.indexOf('nova') >= 0 || type.indexOf('新星') >= 0) return 'catalog_nova'
  if (type.indexOf('pulsar') >= 0 || type.indexOf('脉冲星') >= 0) return 'catalog_pulsar'
  if (type.indexOf('quasar') >= 0 || type.indexOf('类星体') >= 0) return 'catalog_quasar'
  if (type.indexOf('exoplanet') >= 0 || type.indexOf('系外行星') >= 0) return 'catalog_exoplanet'
  if (type.indexOf('satellite') >= 0 || type.indexOf('artificial') >= 0 || type.indexOf('人造') >= 0) return 'catalog_satellite'
  if (type.indexOf('meteor shower') >= 0 || type.indexOf('流星雨') >= 0) return 'meteor'
  if (type.indexOf('galaxy') >= 0 || type.indexOf('星系') >= 0) return 'catalog_galaxy'
  if (type.indexOf('nebula') >= 0 || type.indexOf('星云') >= 0) return 'catalog_nebula'
  if (type.indexOf('cluster') >= 0 || type.indexOf('星团') >= 0) return 'catalog_cluster'
  if (type.indexOf('comet') >= 0 || type.indexOf('彗') >= 0) return 'catalog_comet'
  if (type.indexOf('asteroid') >= 0 || type.indexOf('小行星') >= 0) return 'catalog_asteroid'
  if (type.indexOf('planet') >= 0 || type.indexOf('行星') >= 0) return 'catalog_planet'
  if (type.indexOf('moon') >= 0 || type.indexOf('卫星') >= 0) return 'catalog_moon'
  if (type.indexOf('constellation') >= 0 || type.indexOf('星座') >= 0) return 'catalog_constellation'
  return fallback
}

// WUT 分类索引 id → 稳定分类 key。
export function wutCategoryKey(id: number): string {
  const keys = ['planets', 'stars', 'brightNebulae', 'darkNebulae', 'galaxies', 'openClusters', 'asteroids', 'comets', 'plutinos', 'dwarfPlanets', 'cubewanos', 'scatteredDisc', 'oortCloud', 'sednoids', 'planetaryNebulae', 'doubleStars', 'variableStars', 'highProperMotion', 'symbioticStars', 'emissionLineStars', 'supernovaCandidates', 'snrCandidates', 'supernovaRemnants', 'galaxyClusters', 'interstellar', 'globularClusters', 'skyRegions', 'activeGalaxies', 'pulsars', 'exoplanets', 'novae', 'supernovae', 'interactingGalaxies', 'deepSky', 'messier', 'ngcic', 'caldwell', 'herschel400', 'algolVariables', 'cepheidVariables', 'carbonStars', 'bariumStars']
  return id >= 0 && id < keys.length ? keys[id] : 'planets'
}

// WUT 方向 key → 中文标签（未知方向回退“全部”）。
export function wutDirectionLabel(direction: string): string {
  if (direction === 'north') return '北'
  if (direction === 'east') return '东'
  if (direction === 'south') return '南'
  if (direction === 'west') return '西'
  return '全部'
}

// WUT 分类选项表（静态）。
export function wutCategoryOptions(): Array<TabItem> {
  return [
    { id: 0, label: '行星' }, { id: 1, label: '亮星' }, { id: 2, label: '亮星云' },
    { id: 3, label: '暗星云' }, { id: 4, label: '星系' }, { id: 5, label: '疏散星团' },
    { id: 6, label: '小行星' }, { id: 7, label: '彗星' }, { id: 8, label: '冥族小天体' },
    { id: 9, label: '矮行星' }, { id: 10, label: '经典柯伊伯带天体' }, { id: 11, label: '散射盘天体' },
    { id: 12, label: '奥尔特云天体' }, { id: 13, label: '塞德娜类天体' }, { id: 14, label: '行星状星云' },
    { id: 15, label: '亮双星' }, { id: 16, label: '亮变星' }, { id: 17, label: '高自行亮星' },
    { id: 18, label: '共生星' }, { id: 19, label: '发射线星' }, { id: 20, label: '超新星候选体' },
    { id: 21, label: '超新星遗迹候选体' }, { id: 22, label: '超新星遗迹' }, { id: 23, label: '星系团' },
    { id: 25, label: '球状星团' }, { id: 26, label: '天区' }, { id: 27, label: '活动星系' },
    { id: 32, label: '交互星系' }, { id: 33, label: '深空天体' }, { id: 34, label: '梅西耶天体' },
    { id: 35, label: 'NGC/IC 天体' }, { id: 36, label: 'Caldwell 天体' }, { id: 37, label: 'Herschel 400 天体' },
    { id: 38, label: 'Algol 型食变星' }, { id: 39, label: '经典造父变星' }, { id: 40, label: '碳星' },
    { id: 41, label: '钡星' }
  ]
}
