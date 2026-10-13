import { curves } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { CatOption } from '../../pages/StellariumTypes'
import { SearchStore } from '../../state/SearchStore'
import { CatalogFilterRow } from './CatalogFilterRow'
import { getIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 搜索筛选菜单：返回行 + 四个页面（根 / 分类 / 可视度 / 器材）。
//
// 页面与分类状态经 SearchStore（@ObjectLink）订阅；标签文本由宿主计算后以 @Prop 传入
// （`searchVisibilityLabel()` / `searchInstrumentLabel()` 在筛选 chips 与搜索结果里也用到，故由宿主提供）。
@Component
export struct SearchFilterMenu {
  @ObjectLink store: SearchStore
  @Prop visibilityLabel: string
  @Prop instrumentLabel: string
  @Prop categories: CatOption[]
  @Prop languageRevision: number
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  onSetPage: (page: string) => void = () => {}
  onSelectCategory: (code: string) => void = () => {}
  onSelectVisibility: (filter: string) => void = () => {}
  onSelectInstrument: (filter: string) => void = () => {}

  private menuTitle(): string {
    if (this.store.searchFilterPage === 'categories') return I18n.t('search_browse_categories')
    if (this.store.searchFilterPage === 'root') return I18n.t('search_filter')
    if (this.store.searchFilterPage === 'visibility') return I18n.t('search_visibility')
    return I18n.t('search_instrument')
  }

  build() {
    Column({ space: 2 }) {
      Row({ space: 10 }) {
        Image(getIcon('chevron_right', false)).width(18).height(18).fillColor(this.textColor).rotate({ angle: 180 })
        Text(this.menuTitle())
          .fontSize(16).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
        .width('100%').height(48).padding({ left: 8, right: 8 }).id('search-browser-back')
        .onClick(() => {
          if (this.store.searchFilterPage === 'root' || this.store.searchFilterPage === 'categories') this.onSetPage('')
          else this.onSetPage('root')
        })
      if (this.store.searchFilterPage === 'root') {
        Row() {
          Text(I18n.t('search_visibility')).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.visibilityLabel.length > 0 ? this.visibilityLabel : I18n.t('search_unlimited'))
            .fontSize(11).fontColor(this.subColor).layoutWeight(0.7).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ right: 8 })
          Image(getIcon('chevron_right', false)).width(16).height(16).fillColor(this.subColor)
        }.width('100%').height(48).padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onSetPage('visibility') })
        Row() {
          Text(I18n.t('search_instrument')).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.instrumentLabel.length > 0 ? this.instrumentLabel : I18n.t('search_unlimited'))
            .fontSize(11).fontColor(this.subColor).layoutWeight(0.7).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ right: 8 })
          Image(getIcon('chevron_right', false)).width(16).height(16).fillColor(this.subColor)
        }.width('100%').height(48).padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onSetPage('instrument') })
      } else if (this.store.searchFilterPage === 'categories') {
        ForEach(this.categories, (cat: CatOption) => {
          CatalogFilterRow({
            cat: cat,
            isSelected: this.store.searchCategory === cat.code,
            textColor: this.textColor,
            subColor: this.subColor,
            panelColor: this.panelColor,
            onSelect: (code: string) => { this.onSelectCategory(code) }
          })
        }, (cat: CatOption) => cat.code + '/' + this.languageRevision.toString())
      } else if (this.store.searchFilterPage === 'visibility') {
        Row() { Text(I18n.t('search_unlimited')).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }) }.width('100%').height(48).padding({ left: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSelectVisibility('all') })
        Row() { Text(I18n.t('search_above_horizon')).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }) }.width('100%').height(48).padding({ left: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSelectVisibility('above') })
        Row() { Text(I18n.t('search_good_observing')).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }) }.width('100%').height(48).padding({ left: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSelectVisibility('good') })
      } else {
        Row() { Text(I18n.t('search_unlimited')).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }) }.width('100%').height(48).padding({ left: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSelectInstrument('all') })
        Row() { Text(I18n.t('search_naked_eye')).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }) }.width('100%').height(48).padding({ left: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSelectInstrument('naked') })
        Row() { Text(I18n.t('search_binoculars')).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }) }.width('100%').height(48).padding({ left: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSelectInstrument('binocular') })
        Row() { Text(I18n.t('search_telescope')).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }) }.width('100%').height(48).padding({ left: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSelectInstrument('telescope') })
      }
    }.width('100%').padding({ left: 4, right: 4, top: 4 })
      .animation({ duration: 220, curve: curves.springMotion(0.42, 0.86) })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 0, y: -8 }).animation({ duration: 220, curve: curves.springMotion(0.48, 0.86) })),
        TransitionEffect.OPACITY.animation({ duration: 130, curve: Curve.EaseIn })
          .combine(TransitionEffect.translate({ x: 0, y: -4 }).animation({ duration: 150, curve: Curve.EaseIn }))
      ))
  }
}
