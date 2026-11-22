import { bundleManager } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

// 「查看地点」应用目录。
//
// 路线规划已统一交给系统 startAbilityByType('navigation', sceneType: 1)，
// 不再需要应用目录。查看地点没有系统统一接口，因此保留：
//   - 花瓣：MapKit openMapPoiDetail（WGS84）
//   - 百度：baidumap://map/marker（GCJ-02）
//   - 其他支持 geo: 的应用：交给系统“选择打开方式”面板
//
// HarmonyOS 普通第三方应用无法读取其他应用的 BundleInfo/图标：GET_BUNDLE_INFO
// 即使已授予，getBundleInfoSync 仍返回 201。因此用 canOpenLink 探测安装状态，
// 图标使用品牌色 + 系统符号绘制。
export interface MapAppEntry {
  id: string
  labelKey: string
  installed: boolean
  iconColor: string
  iconSymbol: Resource
}

interface MapAppSpec {
  id: string
  labelKey: string
  iconColor: string
  iconSymbol: Resource
  probeLink: string
}

const MAP_APP_SPECS: MapAppSpec[] = [
  {
    id: 'petal',
    labelKey: 'map_app_petal',
    iconColor: '#E05A54',
    iconSymbol: $r('sys.symbol.pin_fill'),
    probeLink: 'petalmaps://poidetail'
  },
  {
    id: 'baidu',
    labelKey: 'map_app_baidu',
    iconColor: '#2E9E7A',
    iconSymbol: $r('sys.symbol.pin_fill'),
    probeLink: 'baidumap://map/marker'
  },
  {
    id: 'other',
    labelKey: 'loc_map_other_apps',
    iconColor: '#5C6B7A',
    iconSymbol: $r('sys.symbol.map'),
    probeLink: 'geo://maps'
  }
]

function canOpen(link: string): boolean {
  try {
    return bundleManager.canOpenLink(link)
  } catch (error) {
    hilog.info(0x0000, 'StellariumArkUI',
      `[map-apps] probe ${link} unavailable: ${(error as Error).message}`)
    return false
  }
}

export function loadMapApps(): MapAppEntry[] {
  const entries: MapAppEntry[] = []
  for (const spec of MAP_APP_SPECS) {
    entries.push({
      id: spec.id,
      labelKey: spec.labelKey,
      installed: canOpen(spec.probeLink),
      iconColor: spec.iconColor,
      iconSymbol: spec.iconSymbol
    })
  }
  return entries
}
