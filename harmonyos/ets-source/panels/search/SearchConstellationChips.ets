import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { ConstellationNavigationItem } from '../../pages/MainWindowModels'
import { SearchStore } from '../../state/SearchStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 搜索面板底部的"常见星座快速导航"chips。
//
// 列表经 SearchStore（@ObjectLink）订阅；点击经 onOpen 交回宿主（打开星座资料卡）。
// 名称直接使用 Stellarium 当前语言的官方翻译。
@Component
export struct SearchConstellationChips {
  @ObjectLink store: SearchStore
  @Prop languageRevision: number
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onOpen: (item: ConstellationNavigationItem) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Row() {
      Text(I18n.t('constellation_chips_title')
        + (this.store.constellationNavigationItems.length > 0 ? ' ' + this.store.constellationNavigationItems.length.toString() : ''))
        .fontSize(10).fontColor(this.c.sub).width(68).alignSelf(ItemAlign.Start)
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.store.constellationNavigationItems, (item: ConstellationNavigationItem) => {
          Text(item.localizedName).fontSize(11).fontColor(this.c.text).padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ right: 4, bottom: 4 })
            .onClick(() => { this.onOpen(item) })
        }, (item: ConstellationNavigationItem) => item.englishName + '/' + this.languageRevision.toString())
        if (this.store.constellationNavigationItems.length === 0) {
          Text(I18n.t('search_catalog_loading')).fontSize(10).fontColor(this.c.sub).padding({ left: 8, right: 8 })
        }
      }.layoutWeight(1).padding({ left: 2 })
    }.width('100%').padding({ left: 10, right: 10 }).margin({ top: 6 })
  }
}
