import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { CatOption } from '../../pages/StellariumTypes'
import { getCatalogIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 本组件职责：分类筛选的一行 —— 图标 + 名称 + 选中对勾。
//
// 选中态经 @Prop `isSelected` 由宿主 store 变化实时驱动。
// `.id('search-category-' + cat.code)` 是 uitest 契约锚点，必须保持。
@Component
export struct CatalogFilterRow {
  @Prop cat: CatOption
  @Prop isSelected: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSelect: (code: string) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Row({ space: 12 }) {
      Image(getCatalogIcon(this.cat.iconKey ?? 'catalog_plugin', this.c.isNight))
        .width(24).height(24).objectFit(ImageFit.Contain)
        .fillColor(this.isSelected ? this.c.accent : this.c.iconSecondary)
      Text(this.cat.label).fontSize(14).fontColor(this.c.text).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isSelected) {
        Text('✓').fontSize(18).fontColor(this.c.accent).width(24).textAlign(TextAlign.Center)
      }
    }
      .width('100%').height(60).padding({ left: 14, right: 14 }).margin({ bottom: 8 })
      .backgroundColor(this.isSelected ? this.c.softStrong : this.c.bg).borderRadius(UI_RADIUS_CONTROL)
      .id('search-category-' + this.cat.code).clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onSelect(this.cat.code) })
  }
}
