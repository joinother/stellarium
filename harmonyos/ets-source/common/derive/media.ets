import { ObjectInspectorRingSpec } from '../../pages/MainWindowModels'
import { proceduralModelKind } from './ProceduralDetailModel'

// A2-1：objectInspector 媒体族的纯派生函数（原宿主 MainWindowNativeNode 的 private 方法，
// 函数体逐字搬入）。按 §14.3 A2-M「随媒体管线（ObjectMediaStore / 媒体助手）」落到媒体助手模块。
// 读取的宿主 store 字段改为显式入参（§14.8 规则 6：pure derive 模块无状态、无 store/NAPI 依赖）。

// 七大行星 / 月球 / 太阳及主要卫星的打包纹理路径查找表（原 objectInspectorPlanetTexturePath）。
export function objectInspectorPlanetTexturePath(selectedEnglishName: string): string {
  const objectKey = selectedEnglishName.toLowerCase().replace(/[^a-z0-9]/g, '')
  const textures: Array<[string, string]> = [
    ['sun', 'textures/sun.png'], ['mercury', 'textures/mercury.png'], ['venus', 'textures/venus.png'],
    ['earth', 'textures/earth_cmap.png'], ['moon', 'textures/moon.png'], ['mars', 'textures/mars.png'],
    ['jupiter', 'textures/jupiter.png'], ['saturn', 'textures/saturn.png'], ['uranus', 'textures/uranus.png'],
    ['neptune', 'textures/neptune.png'], ['pluto', 'textures/pluto.png'], ['charon', 'textures/charon.png'],
    ['ceres', 'textures/ceres.png'], ['vesta', 'textures/vesta.png'], ['eros', 'textures/eros.png'],
    ['bennu', 'textures/bennu.png'], ['gaspra', 'textures/gaspra.png'], ['ida', 'textures/ida.png'],
    ['sedna', 'textures/sedna.png'], ['eris', 'textures/eris.png'], ['haumea', 'textures/haumea.png'],
    ['dysnomia', 'textures/dysnomia.png'], ['2007or10', 'textures/2007OR10.png'],
    ['phobos', 'textures/phobos.png'], ['deimos', 'textures/deimos.png'], ['io', 'textures/io.png'],
    ['europa', 'textures/europa.png'], ['ganymede', 'textures/ganymede.png'], ['callisto', 'textures/callisto.png'],
    ['amalthea', 'textures/amalthea.png'], ['mimas', 'textures/mimas.png'], ['enceladus', 'textures/enceladus.png'],
    ['tethys', 'textures/tethys.png'], ['dione', 'textures/dione.png'], ['rhea', 'textures/rhea.png'],
    ['titan', 'textures/titan.png'], ['hyperion', 'textures/hyperion.png'], ['iapetus', 'textures/iapetus.png'],
    ['phoebe', 'textures/phoebe.png'], ['janus', 'textures/janus.png'], ['epimetheus', 'textures/epimetheus.png'],
    ['prometheus', 'textures/prometheus.png'], ['ariel', 'textures/ariel.png'], ['umbriel', 'textures/umbriel.png'],
    ['titania', 'textures/titania.png'], ['oberon', 'textures/oberon.png'], ['miranda', 'textures/miranda.png'],
    ['triton', 'textures/triton.png'], ['nereid', 'textures/nereid.png'], ['proteus', 'textures/proteus.png']
  ]
  for (const pair of textures) {
    if (objectKey === pair[0] || objectKey.startsWith(pair[0] + 'observer')) {
      return pair[1]
    }
  }
  return ''
}

// 土星 / 天王星 / 海王星的行星环几何（原 objectInspectorPlanetRingSpec）。
export function objectInspectorPlanetRingSpec(selectedEnglishName: string): ObjectInspectorRingSpec | undefined {
  const objectKey = selectedEnglishName.toLowerCase().replace(/[^a-z0-9]/g, '')
  const specs: Array<[string, ObjectInspectorRingSpec]> = [
    ['saturn', { texturePath: 'textures/saturn_rings_radial.png', innerRadius: 1.24, outerRadius: 2.33, tilt: 0.35, opacity: 0.94 }],
    ['uranus', { texturePath: 'textures/uranus_rings.png', innerRadius: 1.05, outerRadius: 3.82, tilt: 0.55, opacity: 1.0 }],
    ['neptune', { texturePath: 'textures/neptune_rings.png', innerRadius: 1.65, outerRadius: 2.54, tilt: 0.42, opacity: 0.9 }]
  ]
  for (const pair of specs) {
    if (objectKey === pair[0] || objectKey.startsWith(pair[0] + 'observer')) {
      return pair[1]
    }
  }
  return undefined
}

// 兜底示意图类别（原 objectInspectorFallbackVisualKind）：先按程序化模型族判定，再按类型文案回退。
export function objectInspectorFallbackVisualKind(selectedObjectType: string, selectedType: string): string {
  const type = (selectedObjectType + ' ' + selectedType).toLowerCase()
  const procedural = proceduralModelKind(type)
  if (procedural.length > 0) return procedural
  if (type.indexOf('comet') >= 0 || type.indexOf('彗') >= 0) return 'comet'
  if (type.indexOf('asteroid') >= 0 || type.indexOf('minor planet') >= 0 || type.indexOf('小行星') >= 0) return 'asteroid'
  // 星云类在 Stellarium 目录里不都带 "nebula" 字样：HII 区（M42/M43）、
  // 超新星遗迹、恒星云、Herbig-Haro 天体、博克球状体都应按星云取离线图。
  if (type.indexOf('hii') >= 0 || type.indexOf('h ii') >= 0 || type.indexOf('电离氢') >= 0) return 'nebula'
  if (type.indexOf('supernova remnant') >= 0 || type.indexOf('超新星遗迹') >= 0) return 'nebula'
  if (type.indexOf('star cloud') >= 0 || type.indexOf('恒星云') >= 0) return 'nebula'
  if (type.indexOf('herbig') >= 0 || type.indexOf('bok globule') >= 0 || type.indexOf('球状体') >= 0) return 'nebula'
  if (type.indexOf('planetary nebula') >= 0 || type.indexOf('行星状星云') >= 0) return 'nebula'
  if (type.indexOf('galaxy') >= 0 || type.indexOf('星系') >= 0) return 'galaxy'
  if (type.indexOf('globular') >= 0 || type.indexOf('球状星团') >= 0) return 'globular-cluster'
  if (type.indexOf('cluster') >= 0 || type.indexOf('星团') >= 0) return 'open-cluster'
  if (type.indexOf('nebula') >= 0 || type.indexOf('星云') >= 0) return 'nebula'
  if (type.indexOf('constellation') >= 0 || type.indexOf('星座') >= 0) return 'constellation'
  if (type.indexOf('artificial') >= 0 || type.indexOf('人造') >= 0) return 'satellite'
  if (type.indexOf('moon') >= 0) return 'moon'
  if (type.indexOf('satellite') >= 0 || type.indexOf('卫星') >= 0) return 'satellite'
  if (type.indexOf('star') >= 0 || type.indexOf('恒星') >= 0 || type.indexOf('变星') >= 0) return 'star'
  return 'object'
}

// 深空离线图库文件名（原 objectInspectorDeepSkyImageName）。fallbackVisualKind 由调用点传入，
// searchText 为宿主 objectInspectorSearchText() 的实时结果（目录编号 + 英文名 + 名称小写）。
export function objectInspectorDeepSkyImageName(fallbackVisualKind: string, searchText: string): string {
  const visualKind = fallbackVisualKind
  if (visualKind !== 'galaxy' && visualKind !== 'nebula' && visualKind !== 'globular-cluster' && visualKind !== 'open-cluster') {
    return ''
  }
  const text = searchText
  // 名称型别名（不含目录编号，避免 'm 1' 误匹配 'm 10' 这类前缀）。
  const nameAliases: Record<string, string> = {
    // Horsehead Nebula (Barnard 33) is part of the same Orion molecular cloud.
    'horsehead': 'm42.png', '马头': 'm42.png', 'barnard 33': 'm42.png', 'barnard33': 'm42.png'
  }
  for (const key of Object.keys(nameAliases)) {
    if (text.indexOf(key) >= 0) {
      return nameAliases[key]
    }
  }
  const catalogMatch = text.match(/\b(m|ngc|ic|barnard|b|rcw|ced|vdb|lbn|ldn|abell)\s*-?\s*0*(\d+)\b/i)
  if (catalogMatch === null || catalogMatch.length < 3) { return '' }
  const prefix = catalogMatch[1].toLowerCase()
  const number = catalogMatch[2]
  const key = prefix === 'ngc' ? 'n' + number
    : ((prefix === 'b' || prefix === 'barnard') ? 'b' + number : prefix + number)
  // 打包图库里这些目录编号用的是变体文件名，必须按实际文件返回。
  const variants: Record<string, string> = {
    'n224': 'm31.png', 'n1952': 'm1dumont.png',
    'm1': 'm1dumont.png', 'm15': 'm15-vasey.png', 'm43': 'm42.png', 'm45': 'pleiades.png',
    'm51': 'm51-vasey.png', 'm57': 'm57dumont.png', 'm82': 'm82-vasey.png',
    'm101': 'm101-vasey.png', 'm105': 'm105-vasey.png', 'm106': 'm106-vasey.png',
    'b33': 'm42.png'
  }
  if (variants[key] !== undefined) { return variants[key] }
  if (key.charAt(0) === 'b') { return 'barnard' + number + '.png' }
  return key + '.png'
}

// 无精确图时的类别代表图：保证非 3D 深空天体至少有一张图片填充，
// 而不是落回空白/程序化视觉。
export function objectInspectorFallbackImageName(visualKind: string): string {
  if (visualKind === 'galaxy') { return 'm31.png' }
  if (visualKind === 'nebula') { return 'm42.png' }
  if (visualKind === 'globular-cluster') { return 'm13.png' }
  if (visualKind === 'open-cluster') { return 'm44.png' }
  return ''
}

// 恒星近似色（原 objectInspectorStarColor）：按色温档位返回十六进制颜色。
export function objectInspectorStarColor(temperatureK: number): string {
  const temperature = temperatureK
  if (temperature >= 11000) return '#A8C8FF'
  if (temperature >= 7500) return '#D6E5FF'
  if (temperature >= 6000) return '#FFF5D8'
  if (temperature >= 4500) return '#FFD3A3'
  if (temperature > 0) return '#FFAA86'
  return '#E8F4FF'
}
