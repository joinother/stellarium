import { I18n } from '../../pages/I18n'
import { SearchSug } from '../../pages/StellariumTypes'
import { SearchStore } from '../../state/SearchStore'
import { getIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 搜索候选列表：结果计数 + 候选行（名称 + 副标题）。
//
// 候选数据经 SearchStore（@ObjectLink）订阅。副标题格式化方法 `celestialSubtitle` 被
// 搜索/浏览/今晚天象三处共用，故由宿主提供，以 `subtitleFor` 回调注入，避免复制实现。
@Component
export struct SearchSuggestions {
  @ObjectLink store: SearchStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  subtitleFor: (title: string, englishName: string) => string = () => ''
  onSelect: (item: SearchSug) => void = () => {}

  build() {
    Column({ space: 4 }) {
      Row() {
        Text(I18n.t('loc_search_results')).fontSize(11).fontColor(this.subColor).layoutWeight(1)
        Text(this.store.searchSuggestions.length > 0
          ? I18n.format('search_candidate_count', [this.store.searchSuggestions.length.toString()])
          : I18n.t('search_no_candidates'))
          .fontSize(10).fontColor(this.subColor)
      }.width('100%').padding({ left: 4, right: 4 })
      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.store.searchSuggestions, (item: SearchSug) => {
            Row() {
              Image(getIcon('search', false)).width(16).height(16).fillColor('#7FB3DC').margin({ right: 10 })
              Column({ space: 1 }) {
                Text(item.zh).fontSize(14).fontColor(this.textColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (item.fuzzy === true || item.crossLanguage === true || (item.type ?? '').length > 0 || this.subtitleFor(item.zh, item.en).length > 0) {
                  Text((item.crossLanguage === true ? I18n.t('search_cross_language_match') + ' · ' : '')
                    + (item.fuzzy === true ? I18n.t('search_approximate_match') + ' · ' : '')
                    + ((item.type ?? '').length > 0 ? item.type + ' · ' : '')
                    + this.subtitleFor(item.zh, item.en))
                    .fontSize(10).fontColor(this.subColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }
              .width('100%').height(52).padding({ left: 12, right: 12 })
              .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.onSelect(item) })
          }, (item: SearchSug) => item.selection ?? item.en)
          if (this.store.searchSuggestions.length === 0) {
            Text(I18n.t('search_no_match_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 4, top: 8, bottom: 8 })
          }
        }.width('100%')
      }.width('100%').height(this.store.searchSuggestions.length > 0 ? 216 : 48)
        .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto)
        // Scroll 设了高度后，子内容小于可视高度时默认居中（结果少时标题与首行之间出现大空档）；
        // 固定顶部对齐（同 SearchPanel 外层 Scroll 的做法）。
        .align(Alignment.TopStart)
    }
      .width('100%').padding(8).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
  }
}
