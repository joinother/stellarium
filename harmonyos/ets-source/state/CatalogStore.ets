import { StarCatalogItem, CatalogHealthEntry, StarCatalogsResponse, StarCatalogRaw, CatalogHealthResponse, StarCatalogStatusResponse } from '../pages/MainWindowModels'
import { CatOption, NameItem, StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { catalogIconForModule, catalogIconForObjectType } from '../common/derive/catalog'
import { CommandPort } from '../bridge/CommandPort'
import hilog from '@ohos.hilog'

// —— 内置星表静态快照 ——
// 镜像 `stars/hip_gaia3/defaultStarsConfig.json` 的 9 级星表。引擎桥不可用时（UI-only 模拟器、
// 桥未就绪、或引擎未回包）用它渲染面板，保证始终能看到完整级表；桥回包到达后以引擎的
// `checked` 状态为准替换。`source` 由 url 派生，离线构建下用于标注下载渠道。
const STAR_SOURCEFORGE_BASE = 'https://sourceforge.net/projects/stellarium/files/Extra-data-files/stars-3.0/'
const STATIC_STAR_CATALOGS: StarCatalogRaw[] = [
  { id: 'stars0', fileName: 'stars_0_0v0_21.cat', count: 0.005, magRange: [-2, 6], sizeMb: 0.2, checked: true },
  { id: 'stars1', fileName: 'stars_1_0v0_16.cat', count: 0.022, magRange: [6, 7.5], sizeMb: 1.0, checked: true },
  { id: 'stars2', fileName: 'stars_2_0v0_17.cat', count: 0.14, magRange: [7.5, 9], sizeMb: 6.5, checked: true },
  { id: 'stars3', fileName: 'stars_3_0v0_10.cat', count: 0.42, magRange: [9, 10.5], sizeMb: 12.8, checked: true },
  { id: 'stars4', fileName: 'stars_4_1v0_6.cat', count: 1.7, magRange: [10.5, 12], sizeMb: 53.1, checked: true, url: STAR_SOURCEFORGE_BASE + 'stars_4_1v0_6.cat/download' },
  { id: 'stars5', fileName: 'stars_5_1v0_6.cat', count: 8.0, magRange: [12, 13.75], sizeMb: 245, checked: false, url: STAR_SOURCEFORGE_BASE + 'stars_5_1v0_6.cat/download' },
  { id: 'stars6', fileName: 'stars_6_1v0_4.cat', count: 29.8, magRange: [13.75, 15.5], sizeMb: 912, checked: false, url: STAR_SOURCEFORGE_BASE + 'stars_6_1v0_4.cat/download' },
  { id: 'stars7', fileName: 'stars_7_1v0_4.cat', count: 57.5, magRange: [15.5, 16.75], sizeMb: 1710, checked: false, url: STAR_SOURCEFORGE_BASE + 'stars_7_1v0_4.cat/download' },
  { id: 'stars8', fileName: 'stars_8_2v0_3.cat', count: 122.9, magRange: [16.75, 18], sizeMb: 1830, checked: false, url: STAR_SOURCEFORGE_BASE + 'stars_8_2v0_3.cat/download' }
]

// 星等整数补 ".0"（-2 -> -2.0），小数原样（13.75 -> 13.75）。
function catalogMagnitude(value: number): string {
  return Number.isInteger(value) ? value.toFixed(1) : value.toString()
}

function catalogMagRange(raw: number[] | undefined): string {
  if (raw === undefined || raw.length < 2) return ''
  return catalogMagnitude(raw[0]) + ' ~ ' + catalogMagnitude(raw[1])
}

function catalogSizeLabel(sizeMb: number | undefined): string {
  if (sizeMb === undefined || sizeMb <= 0) return ''
  return sizeMb >= 1024 ? (sizeMb / 1024).toFixed(1) + ' GB' : sizeMb.toString() + ' MB'
}

// count 以"百万"为单位；<1M 显示 K，>=1M 显示 M。
function catalogCountLabel(countMillions: number | undefined): string {
  if (countMillions === undefined || countMillions <= 0) return ''
  return countMillions < 1 ? Math.round(countMillions * 1000).toString() + 'K' : countMillions.toString() + 'M'
}

function catalogSourceLabel(url: string): string {
  const lower = url.toLowerCase()
  if (lower.indexOf('sourceforge') >= 0) return 'SourceForge'
  if (lower.indexOf('github') >= 0) return 'GitHub'
  return ''
}

// 从直链派生可浏览的"下载页面"（目录页）：去掉尾部 `/download` 与文件名，保留到目录。
// 例：.../stars-3.0/stars_5_1v0_6.cat/download -> .../stars-3.0/
function catalogSourcePage(url: string): string {
  if (url.length === 0) return ''
  let page = url
  const downloadSuffix = '/download'
  if (page.endsWith(downloadSuffix)) {
    page = page.substring(0, page.length - downloadSuffix.length)
  }
  const slash = page.lastIndexOf('/')
  return slash > 0 ? page.substring(0, slash + 1) : page
}

function mapCatalogRaw(raw: StarCatalogRaw): StarCatalogItem {
  const url = raw.url ?? ''
  return {
    id: raw.id ?? '',
    name: raw.name ?? (raw.id ?? I18n.t('catalog_fallback')),
    size: catalogSizeLabel(raw.sizeMb),
    key: raw.key ?? '',
    fileName: raw.fileName ?? '',
    url: url,
    html: raw.html ?? '',
    checked: raw.checked === true || raw.checked === 'true' || raw.checked === 1,
    magRange: catalogMagRange(raw.magRange),
    count: catalogCountLabel(raw.count),
    sizeMb: raw.sizeMb ?? 0,
    checksum: raw.checksum ?? '',
    source: catalogSourceLabel(url),
    sourcePage: catalogSourcePage(url)
  }
}

function buildStarCatalogFallback(): StarCatalogItem[] {
  return STATIC_STAR_CATALOGS.map((raw: StarCatalogRaw): StarCatalogItem => mapCatalogRaw(raw))
}

// 宿主 → CatalogStore 的检索域助手 / 跨 store setter。
// `loadObjectCatalogCategories` 写本 store 的 objectCatalogCategories，同时读 / 写 SearchStore
//（pendingPluginCatalogId / searchCategory / categoryModuleId），并复用宿主搜索域动作
//（loadCategoryObjects）与 CLI 发布点（publishSearchBrowserState）、读取宿主语言刷新代际。
// 这些跨 store / 宿主动作经 hooks 具名注入，store 不 import 他 store 或发布点。
export interface CatalogHostHooks {
  // 宿主语言刷新代际：回包返回时比对，丢弃过期请求。
  languageSerial(): number
  // 下载启动 / 轮询的 UI 提示经此回注（store 不触碰 UI）。
  flashHint(text: ResourceStr): void
  // SearchStore 的待定插件目录 id（读 + 清）。
  pendingPluginCatalogId(): string
  clearPendingPluginCatalogId(): void
  searchCategory(): string
  categoryModuleId(): string
  // 搜索域动作：loadCategoryObjects 由 SearchStore 承担（经宿主适配器转发），CLI 发布点留宿主。
  loadCategoryObjects(category: string, moduleIdOverride: string): void
  publishSearchBrowserState(): void
  // 目录健康相关的「跨域共用」标志（catalogHealthLoaded / catalogManifestPresent，
  // 供 SettingsQuickLegacyPanel / SatellitesPanel 经宿主闭包读取）与归属 SatelliteStore 的
  // satelliteCatalogHealth，均经此 setter 回注（store 不 import / 持有他 store）。
  setCatalogHealthLoaded(loaded: boolean): void
  setCatalogManifestPresent(present: boolean): void
  setSatelliteCatalogHealth(health: CatalogHealthEntry): void
}

// 星表下载域中"面板可见"的状态：面板别名 loading←catalogLoading、items←catalogList、
// busy←catalogBusy、downloadingId←catalogDownloadingId、msg←catalogMsg，store 沿用宿主字段名。
// 消费方为星表 / 设置面板（@ObjectLink）。`catalogHealthLoaded` / `catalogManifestPresent` 与
// `satelliteCatalogHealth` 属跨域共用字段，留宿主并经 CatalogHostHooks setter 回注；
// `starCatalogHealth`（设置快照面板）与 `objectCatalogCategories`（SearchPanel）由本 store 持有。
//
// —— 桥注入约定 ——
// 宿主在 aboutToAppear 调用 attachPort(port, onChanged) 注入 CommandPort，store 侧用 ensurePort() 守卫。
// 本域无 publish* 发布点、消费方均为 @ObjectLink（字段赋值即刷新），故 onChanged 为等价空实现。
@Observed
export class CatalogStore {
  // 启动即以静态 9 级快照填充，保证面板/模拟器立即可渲染；桥回包到达后替换为引擎状态。
  catalogList: StarCatalogItem[] = buildStarCatalogFallback()
  catalogLoading: boolean = false
  catalogBusy: boolean = false
  catalogDownloadingId: string = ''
  catalogMsg: string = ''
  // 手动导入进行中（按 MD5 识别，与下载态分开）。
  catalogImporting: boolean = false
  starCatalogHealth: CatalogHealthEntry = {}
  objectCatalogCategories: CatOption[] = []

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 请求序号；本加载器暂未用到，预留以保持统一约定。
  private seq: number = 0
  // 列表刷新序号：防止「打开面板时的旧回包」与「导入后重拉」竞争、把新状态覆盖成旧状态。
  private catalogLoadSequence: number = 0
  private onChanged: (() => void) | null = null
  // 宿主助手 / 跨 store setter。
  private hooks: CatalogHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  // 宿主在 aboutToAppear 注入搜索域助手 / 跨 store setter；重复注入会覆盖旧值（幂等）。
  attachHooks(hooks: CatalogHostHooks): void {
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // 星表下载面板：桥查询可用星表列表。**每次打开都重查**（各级的已加载/未加载由引擎的
  // checked 决定，不能缓存），引擎桥不可用 / 回包为空时保留静态 9 级快照；旧回包由序号丢弃。
  loadStarCatalogs(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    this.catalogLoading = true
    const loadSeq = ++this.catalogLoadSequence
    port.requestWhenReady('getStarCatalogs', '', (r: StellariumBridgeResponse) => {
      if (loadSeq !== this.catalogLoadSequence) return
      const resp = r as StarCatalogsResponse
      const list = resp.catalogs ?? []
      this.catalogList = list.length > 0
        ? list.map((c: StarCatalogRaw): StarCatalogItem => mapCatalogRaw(c))
        : buildStarCatalogFallback()
      this.catalogLoading = false
      this.notifyChanged()
    }, () => {
      if (loadSeq !== this.catalogLoadSequence) return
      this.catalogList = buildStarCatalogFallback()
      this.catalogLoading = false
      this.notifyChanged()
    })
  }

  // 手动导入本地星表：宿主把所选 / 被打开的文件落到沙箱后传来其路径；桥按 **MD5 识别**
  // 目标级（不看文件名）并热加载。重活由宿主 fileIo 异步完成，这里只轮询回包。
  importLocalCatalog(sourcePath: string): void {
    const port = this.ensurePort()
    if (port === null) {
      hilog.warn(0xD002, 'Stellarium', '[star-catalog] import skipped: bridge port not ready')
      return
    }
    if (this.catalogImporting) {
      hilog.warn(0xD002, 'Stellarium', '[star-catalog] import skipped: previous import still running')
      return
    }
    const hooks = this.hooks
    this.catalogImporting = true
    this.catalogMsg = I18n.t('catalog_importing')
    hilog.info(0xD002, 'Stellarium', '[star-catalog] import start path=%{public}s', sourcePath)
    port.requestLongRunning('importStarCatalog', sourcePath, (r: StellariumBridgeResponse) => {
      this.catalogImporting = false
      this.catalogMsg = ''
      const importedId = r.id ?? ''
      hilog.info(0xD002, 'Stellarium', '[star-catalog] import ok id=%{public}s', importedId)
      if (r.ok === true && importedId.length > 0) {
        this.markCatalogLoaded(importedId)
      }
      if (hooks !== null) {
        hooks.flashHint(this.importResultHint(r))
      }
      this.loadStarCatalogs()
    }, (r: StellariumBridgeResponse) => {
      // 失败回包同样带 reason（checksum_mismatch / prerequisite / io / format），必须走
      // importResultHint 才能显示精确原因；原先一律显示「版本不符或文件损坏」是误导。
      this.catalogImporting = false
      this.catalogMsg = ''
      hilog.warn(0xD002, 'Stellarium',
        '[star-catalog] import failed reason=%{public}s error=%{public}s',
        r.reason ?? '', r.error ?? '')
      const failedHooks = this.hooks
      if (failedHooks !== null) {
        failedHooks.flashHint(this.importResultHint(r))
      }
    }, (progress: StellariumBridgeResponse): void => {}, 1200)
  }

  // 导入结果提示：按桥返回的 reason 映射到本地化文案。
  private importResultHint(r: StellariumBridgeResponse): string {
    if (r.ok === true) {
      return I18n.t('catalog_import_success')
    }
    const reason = r.reason ?? ''
    if (reason === 'checksum_mismatch') {
      return I18n.t('catalog_import_no_match')
    }
    if (reason === 'prerequisite') {
      return I18n.t('catalog_prereq_missing')
    }
    return I18n.t('catalog_import_failed')
  }

  // 导入成功后立刻把对应级标记为已加载（乐观更新），避免面板在重拉回包前还显示「手动导入」。
  private markCatalogLoaded(id: string): void {
    this.catalogList = this.catalogList.map((item: StarCatalogItem): StarCatalogItem => {
      if (item.id !== id) {
        return item
      }
      return {
        id: item.id, name: item.name, size: item.size, key: item.key, fileName: item.fileName,
        url: item.url, html: item.html, checked: true, magRange: item.magRange, count: item.count,
        sizeMb: item.sizeMb, checksum: item.checksum, source: item.source, sourcePage: item.sourcePage
      }
    })
    this.notifyChanged()
  }

  // 星表下载启动：忙时提示，否则下发下载命令并轮询状态。
  startCatalogDownload(id: string): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    if (this.catalogBusy) {
      hooks.flashHint(I18n.t('msg_catalog_downloading'))
      return
    }
    this.catalogBusy = true
    this.catalogDownloadingId = id
    this.catalogMsg = '开始下载 ' + id + ' …'
    hooks.flashHint('开始下载 ' + id)
    const r = port.request('downloadStarCatalog', id)
    if (!r || !r.ok) {
      this.catalogBusy = false
      this.catalogDownloadingId = ''
      this.catalogMsg = '下载启动失败'
      hooks.flashHint(I18n.t('msg_download_failed'))
      return
    }
    this.pollCatalogStatus(id)
  }

  // 星表下载状态轮询：600ms setInterval 自我收口（done/error/回包失败即 clearInterval），非持续定时器。
  private pollCatalogStatus(id: string): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    const timer = setInterval(() => {
      const r = port.request('getStarCatalogStatus', '') as StarCatalogStatusResponse
      if (!r || !r.ok) {
        clearInterval(timer)
        this.catalogBusy = false
        this.catalogDownloadingId = ''
        return
      }
      const state = r.state ?? 'downloading'
      const bytes = r.bytes ?? 0
      if (state === 'done') {
        clearInterval(timer)
        const md5ok = r.md5ok === true
        this.catalogMsg = md5ok ? ('「' + id + '」下载完成并已加载') : ('「' + id + '」下载完成，校验未通过')
        hooks.flashHint(this.catalogMsg)
        this.catalogBusy = false
        this.catalogDownloadingId = ''
        this.loadStarCatalogs()
      } else if (state === 'error') {
        clearInterval(timer)
        const err = r.error ?? '未知错误'
        this.catalogMsg = '下载失败：' + err
        hooks.flashHint('下载失败：' + err)
        this.catalogBusy = false
        this.catalogDownloadingId = ''
      } else {
        const mb = (bytes / (1024 * 1024)).toFixed(1)
        this.catalogMsg = '下载中 ' + id + '：' + mb + ' MB'
      }
    }, 600)
  }

  // 对象目录分类 chips：桥查询分类目录，回包后更新本 store 分类并经 hooks 提交 SearchStore。
  // 回包比对 languageSerial 丢弃过期请求；catalogIconForModule 由本 store 直接 import（纯函数）。
  loadObjectCatalogCategories(languageSerial: number): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    port.requestWhenReady('getObjectCatalogCategories', '', (result: StellariumBridgeResponse) => {
      if (hooks.languageSerial() !== languageSerial) return
      if (result.ok !== true || !Array.isArray(result.items)) return
      const items = result.items as Array<Record<string, Object>>
      const categories: CatOption[] = []
      for (let index = 0; index < items.length; index++) {
        const item = items[index]
        const moduleId = item['moduleId'] !== undefined ? String(item['moduleId']) : ''
        const label = item['label'] !== undefined ? String(item['label']) : moduleId
        if (moduleId.length === 0) continue
        categories.push({
          code: 'module:' + moduleId,
          label: label,
          moduleId: moduleId,
          iconKey: catalogIconForModule(moduleId),
          group: item['group'] !== undefined ? String(item['group']) : moduleId.split(':')[0],
          isCoreSubset: item['isCoreSubset'] === true,
          isPluginCatalog: item['isPluginCatalog'] === true
        })
      }
      this.objectCatalogCategories = categories
      hooks.publishSearchBrowserState()
      const pendingModuleId = hooks.pendingPluginCatalogId()
      if (pendingModuleId.length > 0 && categories.some((item: CatOption) => item.moduleId === pendingModuleId)) {
        hooks.clearPendingPluginCatalogId()
        if (hooks.searchCategory() === 'module:' + pendingModuleId || hooks.categoryModuleId() === pendingModuleId) {
          hooks.loadCategoryObjects('module:' + pendingModuleId, pendingModuleId)
        }
      }
    })
  }

  // 目录健康：桥查询目录健康，跨域共用字段经 hooks setter 回注宿主 / 他 store。
  loadCatalogHealth(): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    port.requestWhenReady('getCatalogHealth', '', (r: StellariumBridgeResponse) => {
      const health = r as CatalogHealthResponse
      hooks.setCatalogHealthLoaded(true)
      hooks.setCatalogManifestPresent(health.manifestPresent === true)
      hooks.setSatelliteCatalogHealth(health.satellites ?? {})
      this.starCatalogHealth = health.stars ?? {}
    })
  }

  // ==== 搜索域分类 chips 的「取值 / 选项」助手 ====
  //
  // 读本 store 的 `objectCatalogCategories`；`searchCategoryLabel` / `categoryObjectIcon`
  // 另需搜索域当前分类，经显式入参传入，避免 store 相互 import。

  // 目录 moduleId → 本地化标签；查不到回退 fallback。
  private catalogLabelForModule(moduleId: string, fallback: ResourceStr): ResourceStr {
    for (const option of this.objectCatalogCategories) {
      if (option.moduleId === moduleId) return option.label
    }
    return fallback
  }

  // 搜索面板内置分类表。
  searchCategoryOptions(): Array<CatOption> {
    const core: CatOption[] = [
      { code: 'planet', label: this.catalogLabelForModule('SolarSystem:planet', I18n.t('i0103')), moduleId: 'SolarSystem:planet', iconKey: 'catalog_planet' },
      { code: 'moon', label: this.catalogLabelForModule('SolarSystem:moon', I18n.objectType('Moon')), moduleId: 'SolarSystem:moon', iconKey: 'catalog_moon' },
      { code: 'comet', label: this.catalogLabelForModule('SolarSystem:comet', I18n.objectType('Comet')), moduleId: 'SolarSystem:comet', iconKey: 'catalog_comet' },
      { code: 'asteroid', label: this.catalogLabelForModule('SolarSystem:asteroid', I18n.objectType('Asteroid')), moduleId: 'SolarSystem:asteroid', iconKey: 'catalog_asteroid' },
      { code: 'star', label: this.catalogLabelForModule('StarMgr', I18n.t('i0104')), moduleId: 'StarMgr', iconKey: 'catalog_star' },
      { code: 'variable', label: this.catalogLabelForModule('StarMgr:1', I18n.objectType('Variable star')), moduleId: 'StarMgr:1', iconKey: 'catalog_variable_star' },
      { code: 'constellation', label: this.catalogLabelForModule('ConstellationMgr', I18n.objectType('Constellation')), moduleId: 'ConstellationMgr', iconKey: 'catalog_constellation' },
      { code: 'galaxy', label: this.catalogLabelForModule('NebulaMgr:0', I18n.objectType('Galaxy')), moduleId: 'NebulaMgr:0', iconKey: 'catalog_galaxy' },
      { code: 'cluster', label: this.catalogLabelForModule('NebulaMgr:5', I18n.objectType('Cluster')), moduleId: 'NebulaMgr:5', iconKey: 'catalog_cluster' },
      { code: 'nebula', label: this.catalogLabelForModule('NebulaMgr:200', I18n.t('i0107')), moduleId: 'NebulaMgr:200', iconKey: 'catalog_nebula' },
      { code: 'messier', label: this.catalogLabelForModule('NebulaMgr:100', I18n.t('i0108')), moduleId: 'NebulaMgr:100', iconKey: 'catalog_messier' },
      { code: 'artificial', label: this.catalogLabelForModule('ArtificialObjects', I18n.t('search_artificial_objects')), moduleId: 'ArtificialObjects', iconKey: 'catalog_satellite' },
      { code: 'satellite', label: this.catalogLabelForModule('Satellites', I18n.objectType('Artificial satellite')), moduleId: 'Satellites', iconKey: 'catalog_satellite' }
    ]
    return core
  }

  // 插件目录动态追加的分类。
  searchDynamicCategoryOptions(): Array<CatOption> {
    const core = this.searchCategoryOptions()
    const knownModules: Record<string, boolean> = {}
    for (const option of core) knownModules[option.moduleId ?? ''] = true
    const dynamic: CatOption[] = []
    for (const option of this.objectCatalogCategories) {
      if (!knownModules[option.moduleId ?? ''] && option.isPluginCatalog === true) dynamic.push(option)
    }
    dynamic.sort((left: CatOption, right: CatOption) => String(left.label).localeCompare(String(right.label)))
    return dynamic
  }

  // 内置 + 动态分类去重合并。
  searchAllCategoryOptions(): Array<CatOption> {
    const result: CatOption[] = []
    const modules: Record<string, boolean> = {}
    for (const option of [...this.searchCategoryOptions(), ...this.searchDynamicCategoryOptions()]) {
      const key = option.moduleId || option.code
      if (!modules[key]) {
        modules[key] = true
        result.push(option)
      }
    }
    return result
  }

  // 分类 code → 图标键。
  searchCategoryIcon(category: string): string {
    for (const option of this.searchCategoryOptions()) {
      if (option.code === category) return option.iconKey ?? 'catalog_plugin'
    }
    for (const option of this.objectCatalogCategories) {
      if (option.code === category) return option.iconKey ?? 'catalog_plugin'
    }
    return 'catalog_plugin'
  }

  // 分类 code → 目录 moduleId。
  categoryModuleIdFor(category: string): string {
    for (const option of this.searchCategoryOptions()) {
      if (option.code === category) return option.moduleId ?? ''
    }
    for (const option of this.objectCatalogCategories) {
      if (option.code === category) return option.moduleId ?? ''
    }
    return ''
  }

  // 当前分类的显示标签（当前分类经显式入参传入）。
  searchCategoryLabel(category: string): string {
    for (const option of this.searchCategoryOptions()) {
      if (option.code === category) return String(option.label)
    }
    for (const option of this.objectCatalogCategories) {
      if (option.code === category) return String(option.label)
    }
    return I18n.t('search_browse_categories')
  }

  // 分类浏览条目的图标（当前分类经显式入参传入）。
  categoryObjectIcon(item: NameItem, category: string): string {
    return catalogIconForObjectType(item.type ?? '', this.searchCategoryIcon(category))
  }
}
