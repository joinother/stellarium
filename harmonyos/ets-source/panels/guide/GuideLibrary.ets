import { Theme } from '@kit.ArkUI'
import { ASTRONOMY_GUIDES, AstronomyGuide, guideUsesOverlayLines } from '../../common/derive/AstronomyGuide'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 脚本面板顶部的交互式天文导览库。
// 支持按主题分类筛选、展示路线简介与星桥指引标记，启动某条导览回注 executeGuideRequest。

interface GuideCategoryOption {
  id: string
  labelKey: string
}

const GUIDE_CATEGORIES: GuideCategoryOption[] = [
  { id: 'all', labelKey: 'guide_cat_all' },
  { id: 'stargazing', labelKey: 'guide_cat_stargazing' },
  { id: 'solar_system', labelKey: 'guide_cat_solar_system' },
  { id: 'deep_sky', labelKey: 'guide_cat_deep_sky' },
  { id: 'events', labelKey: 'guide_cat_events' },
  { id: 'sky_culture', labelKey: 'guide_cat_sky_culture' }
]

@Component
export struct GuideLibrary {
  @Prop sessionActive: boolean
  @State private selectedCategory: string = 'all'
  @State c: ThemeSlots = DEFAULT_SLOTS
  onStartGuide: (id: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private visibleGuides(): AstronomyGuide[] {
    if (this.selectedCategory === 'all') return ASTRONOMY_GUIDES
    return ASTRONOMY_GUIDES.filter((guide: AstronomyGuide) => guide.category === this.selectedCategory)
  }

  private metaLine(guide: AstronomyGuide): string {
    const base = guide.steps.length.toString() + ' · ' + I18n.t('guide_stations')
    if (guideUsesOverlayLines(guide)) return base + ' · ' + I18n.t('guide_tag_starhop')
    return base
  }

  build() {
    Column({ space: 10 }) {
      Text(I18n.t('guide_library')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.c.text).width('100%')
      Text(I18n.t('guide_library_hint')).fontSize(13).fontColor(this.c.sub).width('100%')
      Scroll() {
        Row({ space: 6 }) {
          ForEach(GUIDE_CATEGORIES, (cat: GuideCategoryOption) => {
            Button(I18n.t(cat.labelKey), { type: ButtonType.Normal })
              .fontSize(12)
              .fontColor(this.selectedCategory === cat.id ? this.c.onAccent : this.c.text)
              .backgroundColor(this.selectedCategory === cat.id ? this.c.accent : this.c.rowBg)
              .borderRadius(UI_RADIUS_CONTROL)
              .height(32)
              .padding({ left: 12, right: 12 })
              .onClick(() => { this.selectedCategory = cat.id })
          }, (cat: GuideCategoryOption) => cat.id)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      ForEach(this.visibleGuides(), (guide: AstronomyGuide) => {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 5 }) {
            Text(I18n.t(guide.title)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.c.text).width('100%')
            Text(I18n.t(guide.summary)).fontSize(12).lineHeight(18).fontColor(this.c.sub).width('100%')
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.metaLine(guide)).fontSize(11).fontColor(this.c.accent).width('100%')
          }.width('100%').padding(14)
        }.id('guide-start-' + guide.id).width('100%').backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
          .enabled(!this.sessionActive).onClick(() => { this.onStartGuide(guide.id) })
      }, (guide: AstronomyGuide) => guide.id)
      Text(I18n.t('guide_legacy')).fontSize(15).fontColor(this.c.text).width('100%').margin({ top: 12 })
    }
      .width('100%')
  }
}
