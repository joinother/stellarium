// 搜索 / 筛选行为控制器：负责输入建议去抖与桥查询、选中分发，
// 以及分类 / 可见性 / 设备筛选与筛选页切换。
//
// 搜索文本与候选、筛选字段、分类浏览状态写 state/SearchStore.ets（单一持有者）。
// 不 import NAPI/UI：桥经 CommandPort；建议去抖定时器由控制器自持（`stop()`）；
// 面板滚动复位、`animateTo` 过渡动画（宿主 getUIContext）、CLI 发布点
// `publishSearchBrowserState` 与 `searchObject`（选中入口留宿主）经 SearchHostHooks 具名回注。
import { CatOption, SearchSug, StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { SearchStore } from '../state/SearchStore'
import { CatalogStore } from '../state/CatalogStore'
import { LanguageStore } from '../state/LanguageStore'
import { celestialTitle } from '../common/derive/labels'

// 宿主 → 控制器回注：UI 过渡 / 滚动复位 / CLI 发布点 / 选中入口留宿主。
export interface SearchHostHooks {
  // 宿主 getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut })。
  animateFilterChange(action: () => void): void
  // searchPanelScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })。
  resetSearchScroll(): void
  // CLI 发布点（宿主 publishSearchBrowserState(error)）。
  publishSearchBrowserState(error: string): void
  // 选中入口（SelectionService 族，留宿主）；selectSearchSuggestion 的调用点。
  searchObject(name: string, catalogModuleId: string, exactSelectionPayload: string): void
}

export class SearchController {
  private port: CommandPort
  private searchStore: SearchStore
  private catalogStore: CatalogStore
  private languageStore: LanguageStore
  private hooks: SearchHostHooks
  // 建议去抖定时器：控制器自持，宿主 aboutToDisappear 经 stop() 收口。
  private suggestionTimer: number = -1

  constructor(
    port: CommandPort,
    searchStore: SearchStore,
    catalogStore: CatalogStore,
    languageStore: LanguageStore,
    hooks: SearchHostHooks
  ) {
    this.port = port
    this.searchStore = searchStore
    this.catalogStore = catalogStore
    this.languageStore = languageStore
    this.hooks = hooks
  }

  // 定时器收口：清掉未到期的建议去抖。
  stop(): void {
    if (this.suggestionTimer >= 0) {
      clearTimeout(this.suggestionTimer)
      this.suggestionTimer = -1
    }
  }

  // 140ms 去抖后按当前前缀取建议。
  scheduleSuggestions(prefix: string): void {
    if (this.suggestionTimer >= 0) {
      clearTimeout(this.suggestionTimer)
      this.suggestionTimer = -1
    }
    if (prefix.length < 1) {
      this.searchStore.searchSuggestions = []
      return
    }
    this.suggestionTimer = setTimeout(() => {
      this.suggestionTimer = -1
      if (this.searchStore.searchText.trim() === prefix) this.fetchSuggestions(prefix)
    }, 140)
  }

  // 桥查询并本地化候选。语言代际缺省值由 -1 哨兵在体内解析
  //（serial 自 0 递增，-1 不可能是真实值）。
  fetchSuggestions(prefix: string, languageSerial: number = -1): void {
    const serial = languageSerial >= 0 ? languageSerial : this.languageStore.languageRefreshSerial
    if (prefix.length < 1) { this.searchStore.searchSuggestions = []; return }
    // Native matching covers localized names, English names, catalog IDs, and
    // spacing/hyphen variants across every currently loaded object module.
    this.port.requestInteractive('listMatchingObjects', prefix + '|30', (result) => {
      // Only apply if the query prefix is still current (user may have typed more).
      if (this.searchStore.searchText.trim() !== prefix || this.languageStore.languageRefreshSerial !== serial) { return }
      const suggestions: SearchSug[] = []
      const seen: Record<string, boolean> = {}
      if (Array.isArray(result.items)) {
        const keys = Array.isArray(result.keys) ? result.keys as string[] : []
        const ids = Array.isArray(result.ids) ? result.ids as string[] : []
        const typeIds = Array.isArray(result.typeIds) ? result.typeIds as string[] : []
        const types = Array.isArray(result.types) ? result.types as string[] : []
        const fuzzy = Array.isArray(result.fuzzy) ? result.fuzzy as boolean[] : []
        const crossLanguage = Array.isArray(result.crossLanguage) ? result.crossLanguage as boolean[] : []
        const items = result.items as string[]
        for (let i = 0; i < items.length; i++) {
          const display = items[i]
          const key = (keys[i] && keys[i].length > 0) ? keys[i] : display
          const id = ids[i] ?? ''
          const typeId = typeIds[i] ?? ''
          const selection = id.length > 0 && typeId.length > 0 ? 'object|' + typeId + '|' + id : ''
          const uniqueKey = selection.length > 0 ? selection : key
          if (!seen[uniqueKey]) {
            seen[uniqueKey] = true
            suggestions.push({
              zh: celestialTitle(display, key),
              en: key,
              type: types[i] ?? '',
              selection: selection.length > 0 ? selection : undefined,
              fuzzy: fuzzy[i] === true,
              crossLanguage: crossLanguage[i] === true,
            })
          }
        }
      }
      // C++ ranks exact, prefix, and substring matches. Keep that order instead
      // of re-sorting localized display labels in ArkUI.
      this.searchStore.searchSuggestions = suggestions.slice(0, 30)
    })
  }

  // 清去抖后交给宿主 searchObject（en 是稳定检索键）。
  selectSearchSuggestion(suggestion: SearchSug): void {
    this.stop()
    this.hooks.searchObject(suggestion.en, '', suggestion.selection ?? '')
  }

  // 重置分类结果并复位浏览器滚动。
  refreshSearchFilterResults(): void {
    this.searchStore.loadCategoryObjects(this.searchStore.searchCategory)
    this.hooks.resetSearchScroll()
  }

  // 校验目录 code 后清空筛选页并重载。
  selectSearchFilterCategory(category: string): void {
    if (!this.catalogStore.searchAllCategoryOptions().some((option: CatOption) => option.code === category)) {
      this.hooks.publishSearchBrowserState('unknown category')
      return
    }
    this.hooks.animateFilterChange(() => {
      this.searchStore.searchFilterPage = ''
      this.searchStore.loadCategoryObjects(category)
    })
    this.hooks.resetSearchScroll()
  }

  // 可见性筛选。
  selectSearchVisibilityFilter(filter: string): void {
    this.hooks.animateFilterChange(() => {
      this.searchStore.searchVisibilityFilter = filter
      this.searchStore.searchFilterPage = ''
      this.refreshSearchFilterResults()
    })
  }

  // 设备筛选。
  selectSearchInstrumentFilter(filter: string): void {
    this.hooks.animateFilterChange(() => {
      this.searchStore.searchInstrumentFilter = filter
      this.searchStore.searchFilterPage = ''
      this.refreshSearchFilterResults()
    })
  }

  // 切换筛选页并发布 CLI 状态。
  setSearchFilterPage(page: string): void {
    this.hooks.animateFilterChange(() => {
      this.searchStore.searchFilterPage = page
    })
    this.hooks.resetSearchScroll()
    this.hooks.publishSearchBrowserState('')
  }
}
