import { curves, Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { NameItem } from '../../pages/StellariumTypes'
import { SearchStore } from '../../state/SearchStore'
import { SearchFilterChips } from './SearchFilterChips'
import { getCatalogIcon, getIcon } from '../../common/ui/ShellIcons'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 本组件职责：搜索面板的"分类浏览"块 —— 分类选择 + 筛选入口 + 已选条件 chips + 目录天体网格。
//
// 分类/加载状态经 SearchStore（@ObjectLink）订阅；图标键、标签与两个格式化方法
// （`categoryObjectIcon` / `categoryObservationSubtitle`）由宿主提供（其它面板也可能用到），
// 故以 @Prop / 回调注入。
@Component
export struct SearchCategoryBrowse {
  @ObjectLink store: SearchStore
  @Prop categoryIconKey: string
  @Prop languageRevision: number = 0
  @Prop categoryLabel: string
  @Prop visibilityLabel: string
  @Prop instrumentLabel: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  iconFor: (item: NameItem) => string = () => ''
  subtitleFor: (item: NameItem) => string = () => ''
  onOpenCategories: () => void = () => {}
  onOpenFilters: () => void = () => {}
  onRetry: () => void = () => {}
  onLoadMore: () => void = () => {}
  onSelectObject: (item: NameItem) => void = () => {}
  onClearVisibility: () => void = () => {}
  onClearInstrument: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private catalogStatusText(): string {
    if (this.store.categoryLoadFailed) { return I18n.t('search_load_failed_retry') }
    if (this.store.categoryLoading) {
      return this.store.categoryLoadedCount > 0
        ? I18n.format('search_catalog_loading_more', [this.store.categoryLoadedCount.toString()])
        : I18n.t('search_catalog_loading')
    }
    if (this.store.categoryCatalogMessage.length > 0) { return this.store.categoryCatalogMessage }
    if (this.store.categoryObjectCount > 0) {
      if (this.store.categoryListKind === 'named') {
        return I18n.t('search_all_stars') + ' ' + this.store.categoryObjectCount.toString() + ' · '
          + I18n.format('search_catalog_loaded_count', [this.store.categoryLoadedCount.toString(), this.store.categoryCatalogTotal.toString()])
      }
      return I18n.format('search_catalog_loaded_count', [this.store.categoryLoadedCount.toString(), this.store.categoryObjectCount.toString()])
    }
    return I18n.t('search_catalog_empty')
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Row({ space: 10 }) {
          Image(getCatalogIcon(this.categoryIconKey, this.c.isNight)).width(22).height(22).objectFit(ImageFit.Contain).fillColor(this.c.accent)
          Column({ space: 3 }) {
            Text(I18n.t('search_browse_categories')).fontSize(11).fontColor(this.c.sub).width('100%')
            Text(this.categoryLabel).fontSize(14).fontColor(this.c.text).width('100%').maxLines(2)
          }.layoutWeight(1)
          Image(getIcon('chevron_right', false)).width(16).height(16).supportSvg2(true).colorFilter(tintMatrixFor(this.c.sub))
        }
          .layoutWeight(1).height(66).padding({ left: 12, right: 12 })
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
          .id('search-category-picker').clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onOpenCategories() })
        Button(I18n.t('search_filter')).fontSize(13).height(48).padding({ left: 16, right: 16 })
          .backgroundColor(this.c.bg).fontColor(this.c.text).borderRadius(UI_RADIUS_CONTROL)
          .id('search-filter-picker').clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onOpenFilters() })
      }.width('100%').margin({ bottom: 8 })
      if (this.visibilityLabel.length > 0 || this.instrumentLabel.length > 0) {
        SearchFilterChips({
          visibilityLabel: this.visibilityLabel,
          instrumentLabel: this.instrumentLabel,
          onClearVisibility: this.onClearVisibility,
          onClearInstrument: this.onClearInstrument
        })
      }
      Row() {
        Text(I18n.t('search_catalog_objects')).fontSize(11).fontColor(this.c.sub).layoutWeight(1)
        Text(this.catalogStatusText()).fontSize(10).fontColor(this.c.sub)
          .onClick(() => { if (this.store.categoryLoadFailed) { this.onRetry() } })
      }.width('100%').padding({ left: 2, right: 2 }).margin({ top: 10, bottom: 6 })
      Scroll() {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.store.categoryObjects, (item: NameItem) => {
            Row({ space: 8 }) {
              Image(getCatalogIcon(this.iconFor(item), this.c.isNight)).width(22).height(22)
                .fillColor(this.c.iconSecondary)
                .opacity(item.visibleNow === false ? 0.55 : 1)
              Column({ space: 2 }) {
                Text(item.zh ?? item.name ?? '')
                  .fontSize(12).minFontSize(10).fontColor(this.c.text).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.subtitleFor(item).length > 0) {
                  Text(this.subtitleFor(item)).fontSize(10).minFontSize(10)
                    .fontColor(item.visibleNow === true ? this.c.iconTertiary : this.c.sub).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
            }
              .width('49%').height(78).alignItems(VerticalAlign.Center)
              .padding({ left: 10, right: 8, top: 7, bottom: 7 })
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              .margin({ bottom: 6 })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ x: 0, y: 8 }).animation({ duration: 220, curve: curves.springMotion(0.48, 0.86) })),
                TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseIn })
              ))
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.onSelectObject(item) })
          }, (item: NameItem) => this.store.searchCategory + '/' + item.name + '/' + this.languageRevision.toString())
          if (this.store.categoryLoading && this.store.categoryObjects.length > 0) {
            Text(I18n.t('search_loading_more')).fontSize(11).fontColor(this.c.sub).padding({ left: 12, right: 12, top: 8, bottom: 8 })
          } else if (this.store.categoryHasMore) {
            Text(I18n.t('search_load_more')).fontSize(11).fontColor(this.c.sub).padding({ left: 12, right: 12, top: 8, bottom: 8 })
          }
        }.width('100%').padding({ left: 2, right: 6 })
      }.width('100%').height(222).scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto)
        // 同 SearchSuggestions：设高后内容少时默认居中，固定顶部对齐。
        .align(Alignment.TopStart)
        .onReachEnd(() => { this.onLoadMore() })
    }.width('100%')
  }
}
