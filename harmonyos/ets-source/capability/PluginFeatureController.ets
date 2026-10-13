// 插件功能行为控制器。
//
// 负责插件功能的加载、路由描述与打开：确保目标插件已加载后，按路由写 astro / search / 视图标签状态
// 并打开对应面板。控制器不 import NAPI/UI：桥经 CommandPort；跨域读（activePanel + 目录 / 语言 store）
// 与壳层路由经 PluginFeatureHostHooks 具名回注宿主。
// 纯函数 pluginMetaLine / pluginFeatureDestination / pluginFeatureIsActionable / pluginFeatureActionLabel
// 只读 I18n 与 derive labels，随控制器。
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse, PluginItem } from '../pages/StellariumTypes'
import { PluginFeatureRoute } from '../pages/MainWindowModels'
import { CommandPort } from '../bridge/CommandPort'
import { PluginStore } from '../state/PluginStore'
import { SearchStore } from '../state/SearchStore'
import { AstroStore } from '../state/AstroStore'
import { pluginZh, pluginHostName, pluginFeatureRoute } from '../common/derive/labels'
import { BehaviorHostHooks } from './ControllerHooks'

// 宿主 → 控制器回注：跨域读与壳层路由。
export interface PluginFeatureHostHooks extends BehaviorHostHooks {
  // 插件加载成功后，若搜索面板可见则刷新对象目录 chips（宿主读 activePanel + catalogStore + languageStore）。
  refreshCatalogCategoriesIfSearchVisible(): void
  // 视图标签页宿主 @State（组件 @Prop 消费，控制器经 hooks 写）。
  setViewTab(value: number): void
  // 壳层路由：打开路由 panel。
  openSubPanel(panel: string): void
}

export class PluginFeatureController {
  private port: CommandPort
  private pluginStore: PluginStore
  private searchStore: SearchStore
  private astroStore: AstroStore
  private hooks: PluginFeatureHostHooks
  // 瞬时动作串：正在加载的插件 id（不入 @Observed store）。
  private pluginFeatureLoading: string[] = []

  constructor(
    port: CommandPort,
    pluginStore: PluginStore,
    searchStore: SearchStore,
    astroStore: AstroStore,
    hooks: PluginFeatureHostHooks
  ) {
    this.port = port
    this.pluginStore = pluginStore
    this.searchStore = searchStore
    this.astroStore = astroStore
    this.hooks = hooks
  }

  // 确保插件已加载：已加载直接回调，否则先 loadPlugin；同一插件加载在途时去重。
  ensurePluginLoaded(pluginName: string, callback: () => void, failureCallback?: () => void): void {
    if (this.pluginFeatureLoading.indexOf(pluginName) >= 0) {
      return
    }
    this.pluginFeatureLoading = this.pluginFeatureLoading.concat([pluginName])
    const finish = (): void => {
      this.pluginFeatureLoading = this.pluginFeatureLoading.filter((id: string) => id !== pluginName)
    }
    this.port.requestWhenReady('getPluginList', '', (r: StellariumBridgeResponse) => {
      const items = r.items as Array<PluginItem> | undefined
      let loaded = false
      if (items) {
        for (let index = 0; index < items.length; index++) {
          if (items[index].id === pluginName && items[index].loaded) {
            loaded = true
            break
          }
        }
      }
      if (loaded) {
        finish()
        callback()
      } else {
        this.port.requestInteractive('loadPlugin', pluginName, (loadResult: StellariumBridgeResponse) => {
          finish()
          if (loadResult.ok === true) {
            this.updatePluginLoadedItem(pluginName, true)
            // Loading a feature plugin must not rebuild unrelated panels. The
            // catalog chips only need refreshing while the search panel is
            // visible; doing it for every plugin caused a full-shell flash.
            this.hooks.refreshCatalogCategoriesIfSearchVisible()
            callback()
          }
          else {
            this.hooks.flashHint(I18n.t('plugin_load_failed'))
            if (failureCallback !== undefined) failureCallback()
          }
        }, () => {
          finish()
          this.hooks.flashHint(I18n.t('plugin_load_failed'))
          if (failureCallback !== undefined) failureCallback()
        })
      }
    }, () => {
      finish()
      if (failureCallback !== undefined) failureCallback()
    }, 0, 100, 15)
  }

  // 把指定插件列表项的 loaded 标记整体重赋值。
  updatePluginLoadedItem(id: string, loaded: boolean): void {
    this.pluginStore.pluginList = this.pluginStore.pluginList.map((item: PluginItem) => {
      if (item.id !== id) return item
      return {
        id: item.id,
        name: item.name,
        loaded: loaded,
        loadAtStartup: item.loadAtStartup,
        description: item.description,
        authors: item.authors,
        contact: item.contact,
        version: item.version,
        license: item.license,
        acknowledgements: item.acknowledgements,
        hasPreviewImage: item.hasPreviewImage,
        source: item.source
      }
    })
  }

  // 插件列表的版本 / 联系人 / 致谢 / 来源摘要行。
  pluginMetaLine(plugin: PluginItem): string {
    const values: string[] = []
    if (plugin.version && plugin.version.trim().length > 0) { values.push(I18n.t('resource_version') + ': ' + plugin.version.trim()) }
    if (plugin.contact && plugin.contact.trim().length > 0) { values.push(I18n.t('resource_contact') + ': ' + plugin.contact.trim()) }
    if (plugin.acknowledgements && plugin.acknowledgements.trim().length > 0) { values.push(I18n.t('resource_acknowledgements') + ': ' + plugin.acknowledgements.trim()) }
    if (plugin.source && plugin.source.trim().length > 0) { values.push(I18n.t('resource_source') + ': ' + plugin.source.trim()) }
    return values.join(' · ')
  }

  // 插件功能的目标面板描述文案。
  pluginFeatureDestination(id: string): string {
    const route = pluginFeatureRoute(id)
    if (route.kind === 'control') return I18n.format('plugin_destination_control', [pluginHostName(route.panel)])
    if (route.kind === 'catalog') return I18n.format('plugin_destination_catalog', [pluginZh(id)])
    if (route.kind === 'host') {
      let destination = pluginHostName(route.panel)
      if (id === 'ObjectVisibility') destination += ' > ' + pluginZh('Observability')
      else destination += ' > ' + pluginZh(id)
      return I18n.format('plugin_destination_host', [destination])
    }
    if (route.kind === 'network') return I18n.t('plugin_network_disabled')
    if (route.kind === 'offline') return I18n.t('plugin_offline_disabled')
    return I18n.t('plugin_no_arkui_panel')
  }

  // 插件功能是否可点开（仅 control / catalog / host 路由）。
  pluginFeatureIsActionable(id: string): boolean {
    const kind = pluginFeatureRoute(id).kind
    return kind === 'control' || kind === 'catalog' || kind === 'host'
  }

  // 插件功能按钮文案。
  pluginFeatureActionLabel(id: string): string {
    return pluginFeatureRoute(id).kind === 'catalog'
      ? I18n.t('plugin_open_catalog')
      : I18n.t('plugin_open_feature')
  }

  // 插件功能入口：离线 / 无面板直接提示，TelescopeControl 免加载直接打开。
  openPluginFeature(id: string): void {
    const route = pluginFeatureRoute(id)
    if (route.kind === 'offline') {
      this.hooks.flashHint(I18n.t('plugin_offline_disabled'))
      return
    }
    if (route.kind === 'unavailable' || route.panel.length === 0) {
      this.hooks.flashHint(I18n.t('plugin_no_arkui_panel'))
      return
    }
    if (id === 'TelescopeControl') {
      this.openPluginFeatureAfterLoad(id, route)
      return
    }
    this.ensurePluginLoaded(id, () => { this.openPluginFeatureAfterLoad(id, route) }, () => {
      this.hooks.flashHint(I18n.t('plugin_load_failed'))
    })
  }

  // 插件已加载后按路由写 astro / search / 视图标签状态并打开面板。
  openPluginFeatureAfterLoad(id: string, route: PluginFeatureRoute): void {
    if (route.astroTab !== undefined) this.astroStore.astroTab = route.astroTab
    if (route.graphMode !== undefined) this.astroStore.graphMode = route.graphMode
    if (route.layerTab !== undefined) this.hooks.setViewTab(route.layerTab)
    if (route.catalogModuleId !== undefined) {
      this.searchStore.searchText = ''
      this.searchStore.searchCategory = 'module:' + route.catalogModuleId
      this.searchStore.loadCategoryObjects(this.searchStore.searchCategory, route.catalogModuleId)
      this.searchStore.pendingPluginCatalogId = route.catalogModuleId
    }
    this.hooks.openSubPanel(route.panel)
  }
}
