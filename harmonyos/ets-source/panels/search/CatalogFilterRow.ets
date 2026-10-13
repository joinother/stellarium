import { CatOption } from '../../pages/StellariumTypes'
import { getIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 本组件职责：分类筛选的一行 —— 图标 + 名称 + 选中对勾。
//
// 选中态经 @Prop `isSelected` 由宿主 store 变化实时驱动。
// `.id('search-category-' + cat.code)` 是 uitest 契约锚点，必须保持。
@Component
export struct CatalogFilterRow {
  @Prop cat: CatOption
  @Prop isSelected: boolean
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  onSelect: (code: string) => void = () => {}

  build() {
    Row({ space: 12 }) {
      Image(getIcon(this.cat.iconKey ?? 'catalog_plugin', false))
        .width(24).height(24).objectFit(ImageFit.Contain).fillColor(this.subColor)
      Text(this.cat.label).fontSize(14).fontColor(this.textColor).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isSelected) {
        Text('✓').fontSize(18).fontColor('#8FD3FF').width(24).textAlign(TextAlign.Center)
      }
    }
      .width('100%').height(60).padding({ left: 14, right: 14 }).margin({ bottom: 8 })
      .backgroundColor(this.isSelected ? 'rgba(91,147,191,0.22)' : this.panelColor).borderRadius(UI_RADIUS_CONTROL)
      .id('search-category-' + this.cat.code).clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onSelect(this.cat.code) })
  }
}
