import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { SkyCultureDescriptionBlock } from '../../pages/StellariumTypes'
import { SkyCultureDescriptionBlockView } from '../../common/ui/SkyCultureDescriptionBlockView'
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 天体详情卡"资料"页里的星座文化段。
//
// 段落由共享组件 `SkyCultureDescriptionBlockView` 渲染；"是否星座"由宿主以 `@Prop visible` 决定；
// 展开 / 收起直接改写 `@ObjectLink` 观察的 `ObjectDetailStore`，点击后本组件与卡片其余部分都会实时刷新。

@Component
export struct ConstellationCultureView {
  @ObjectLink store: ObjectDetailStore
  @Prop tablet: boolean
  @Prop visible: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    if (this.visible) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(I18n.t('culture_constellation_intro')).fontSize(this.tablet ? 13 : 12).fontWeight(FontWeight.Medium)
              .fontColor(this.c.textStrong).width('100%')
            Text(this.store.selectedConstellationCultureName.length > 0 ? this.store.selectedConstellationCultureName : I18n.t('culture_active_sky'))
              .fontSize(10).fontColor(this.c.tertiary).width('100%').maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1)
          Text(I18n.t('culture_source_material')).fontSize(10).fontColor(this.c.tertiary)
            .padding({ left: 7, right: 7, top: 4, bottom: 4 })
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
        }.width('100%')
        Divider().color(this.c.dividerSoft).margin({ top: 2, bottom: 2 })
        if (this.store.selectedConstellationCultureDescription.length > 0) {
          if (this.store.selectedConstellationCultureDescriptionBlocks.length > 0) {
            Column({ space: 4 }) {
              ForEach(
                this.store.selectedConstellationCultureDescriptionExpanded
                  ? this.store.selectedConstellationCultureDescriptionBlocks
                  : this.store.selectedConstellationCultureDescriptionBlocks.slice(0, 5),
                (block: SkyCultureDescriptionBlock) => {
                  SkyCultureDescriptionBlockView({
                    kind: block.kind,
                    headingLarge: block.level !== undefined && block.level <= 1,
                    text: block.text
                  })
                },
                (block: SkyCultureDescriptionBlock) => 'selected-culture-' + block.index
              )
            }.width('100%')
          } else {
            Text(this.store.selectedConstellationCultureDescription).fontSize(this.tablet ? 12 : 11)
              .fontColor(this.c.text).width('100%').lineHeight(this.tablet ? 19 : 18)
              .maxLines(this.store.selectedConstellationCultureDescriptionExpanded ? 999 : 7)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.store.selectedConstellationCultureDescriptionBlocks.length > 5 || this.store.selectedConstellationCultureDescription.length > 280) {
            Button(this.store.selectedConstellationCultureDescriptionExpanded ? I18n.t('culture_collapse_intro') : I18n.t('culture_expand_intro'))
              .fontSize(10).fontColor(this.c.accent).backgroundColor(Color.Transparent)
              .height(26).padding({ left: 0, right: 8 })
              .onClick(() => { this.store.selectedConstellationCultureDescriptionExpanded = !this.store.selectedConstellationCultureDescriptionExpanded })
          }
        } else {
          Text(I18n.t('culture_no_constellation_intro')).fontSize(this.tablet ? 11 : 10)
            .fontColor(this.c.tertiary).width('100%').lineHeight(17)
        }
        if (this.store.selectedConstellationCultureDescriptionSource.length > 0) {
          Text(this.store.selectedConstellationCultureDescriptionSource).fontSize(10).fontColor(this.c.tertiary)
            .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
        .width('100%').padding({ left: 10, right: 10, top: 10, bottom: 10 })
.backgroundColor(this.c.soft)
         .border({ width: 0.5, color: this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
    }
  }
}
