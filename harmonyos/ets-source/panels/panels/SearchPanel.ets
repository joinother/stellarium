import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { CatOption, NameItem, SearchSug } from '../../pages/StellariumTypes'
import { ConstellationNavigationItem } from '../../pages/MainWindowModels'
import { SearchStore } from '../../state/SearchStore'
import { SearchBar } from '../search/SearchBar'
import { SearchSuggestions } from '../search/SearchSuggestions'
import { SearchFilterMenu } from '../search/SearchFilterMenu'
import { SearchCategoryBrowse } from '../search/SearchCategoryBrowse'
import { SearchConstellationChips } from '../search/SearchConstellationChips'
import { SearchCoordinateInput } from '../search/SearchCoordinateInput'

// 搜索面板，对应 `activePanel === 'search'`。
//
// 搜索状态来自 SearchStore（@ObjectLink）；派生标签、图标键与分类选项由宿主算好后 @Prop 传入。
// 防抖定时器、软键盘避让动画、订阅/点按动作、滚动位置回写与坐标跳转回调注入宿主。
// Scroller 以普通成员传入：宿主持有同一实例，其 scrollTo/currentOffset 须作用于本 Scroll。
// 两个标签回调 suggestionSubtitle / categorySubtitle 签名不同，故分开传。
@Component
export struct SearchPanel {
  @ObjectLink store: SearchStore
  @Prop languageRevision: number
  @Prop visibilityLabel: string
  @Prop instrumentLabel: string
  @Prop categories: CatOption[]
  @Prop categoryIconKey: string
  @Prop categoryLabel: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  scroller: Scroller = new Scroller()
  onInput: (value: string) => void = () => {}
  onSubmit: (text: string) => void = () => {}
  onInputFocus: () => void = () => {}
  onInputBlur: () => void = () => {}
  onSetPage: (page: string) => void = () => {}
  onSelectCategory: (code: string) => void = () => {}
  onSelectVisibility: (filter: string) => void = () => {}
  onSelectInstrument: (filter: string) => void = () => {}
  suggestionSubtitle: (title: string, englishName: string) => string = () => ''
  onSelectSuggestion: (item: SearchSug) => void = () => {}
  iconFor: (item: NameItem) => string = () => ''
  categorySubtitle: (item: NameItem) => string = () => ''
  onOpenCategories: () => void = () => {}
  onOpenFilters: () => void = () => {}
  onRetry: () => void = () => {}
  onLoadMore: () => void = () => {}
  onSelectCategoryObject: (item: NameItem) => void = () => {}
  onClearVisibility: () => void = () => {}
  onClearInstrument: () => void = () => {}
  onOpenConstellation: (item: ConstellationNavigationItem) => void = () => {}
  onGoCoordinates: () => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  build() {
    Scroll(this.scroller) {
      Column({ space: 0 }) {
        Column() {
          SearchBar({
            store: this.store,
            onInput: (value: string) => { this.onInput(value) },
            onSubmit: (text: string) => { this.onSubmit(text) },
            onInputFocus: () => { this.onInputFocus() },
        onInputBlur: () => { this.onInputBlur() }
          })
        }
        .width('100%')
        .padding({ left: 2, right: 2 })
        .margin({ top: 2, bottom: 12 })
        if (this.store.searchFilterPage.length > 0) {
          SearchFilterMenu({
            store: this.store,
            visibilityLabel: this.visibilityLabel,
            instrumentLabel: this.instrumentLabel,
            categories: this.categories,
            languageRevision: this.languageRevision,
            onSetPage: (page: string) => { this.onSetPage(page) },
            onSelectCategory: (code: string) => { this.onSelectCategory(code) },
            onSelectVisibility: (filter: string) => { this.onSelectVisibility(filter) },
            onSelectInstrument: (filter: string) => { this.onSelectInstrument(filter) }
          })
        } else if (this.store.searchText.trim().length > 0) {
          SearchSuggestions({
            store: this.store,
            subtitleFor: (title: string, englishName: string) => { return this.suggestionSubtitle(title, englishName) },
            onSelect: (item: SearchSug) => { this.onSelectSuggestion(item) }
          })
        } else {
          SearchCategoryBrowse({
            store: this.store,
            categoryIconKey: this.categoryIconKey,
            categoryLabel: this.categoryLabel,
            visibilityLabel: this.visibilityLabel,
            instrumentLabel: this.instrumentLabel,
            languageRevision: this.languageRevision,
            iconFor: (item: NameItem) => { return this.iconFor(item) },
            subtitleFor: (item: NameItem) => { return this.categorySubtitle(item) },
            onOpenCategories: () => { this.onOpenCategories() },
            onOpenFilters: () => { this.onOpenFilters() },
            onRetry: () => { this.onRetry() },
            onLoadMore: () => { this.onLoadMore() },
            onSelectObject: (item: NameItem) => { this.onSelectCategoryObject(item) },
            onClearVisibility: () => { this.onClearVisibility() },
            onClearInstrument: () => { this.onClearInstrument() }
          })
        }

        if (this.store.searchFilterPage.length === 0) {
          // 常见星座快速导航 + RA/Dec 坐标跳转（均为独立组件）
          SearchConstellationChips({
            store: this.store,
            languageRevision: this.languageRevision,
            onOpen: (item: ConstellationNavigationItem) => { this.onOpenConstellation(item) }
          })
          SearchCoordinateInput({
            store: this.store,
            onGo: () => { this.onGoCoordinates() }
          })
        }
      }.width('100%')
    }
    .width('100%').layoutWeight(1).scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
    .align(Alignment.TopStart)
    .id('search-browser-scroll').onScroll(() => {
      AppStorage.setOrCreate('stellariumSearchBrowserScrollY', this.scroller.currentOffset()?.yOffset ?? 0)
    })
  }
}
