import { Theme } from '@kit.ArkUI'
import { getCatalogIcon } from '../../common/ui/ShellIcons'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 时间面板打开时的「轻量详情卡」内容：
// 只展示天体名称 + 类型 / 星等 / 星座或距离摘要，右侧保留 ✕；不提供「详情」按钮，
// 因为时间面板与完整详情卡不应同时抢占空间。外层的磨砂背景、圆角与尺寸由
// UnifiedObjectDetailCard 的统一卡片容器提供，本组件只负责内容布局。
@Component
export struct ObjectSelectionPill {
  @ObjectLink store: ObjectDetailStore
  @Prop iconName: string
  @Prop pillWidth: number
  @Prop distanceSummaryText: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  nameOf: (name: string) => string = () => ''
  typeOf: (type: string) => string = () => ''
  onDismiss: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private subtitleText(typeStr: string, magStr: string, constStr: string, distStr: string, distCompact: string): string {
    const parts: string[] = []
    const t = this.typeOf(typeStr)
    if (t.length > 0) parts.push(t)
    if (magStr.length > 0) parts.push(magStr + '等')
    const cName = this.nameOf(constStr)
    const liveDist = this.distanceSummaryText === '--' ? '' : (distCompact.length > 0 ? distCompact : distStr)
    if (cName.length > 0) {
      parts.push(cName)
    } else if (liveDist.length > 0 && liveDist !== '--') {
      parts.push(liveDist)
    }
    return parts.join(' · ')
  }

  private isCompactTwoRow(): boolean {
    return this.pillWidth < 310
  }

  build() {
    Stack() {
      if (this.isCompactTwoRow()) {
        // 窄宽度自适应双行：首行图标 + 名称 + 关闭键，次行类型/星等/星座摘要。
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Row({ space: 8 }) {
              Stack({ alignContent: Alignment.Center }) {
                Image(getCatalogIcon(this.iconName, this.c.isNight))
                  .width(15).height(15).fillColor(this.c.dockActive)
              }
                .width(26).height(26)
                .borderRadius(13)
                .backgroundColor(this.c.soft)

              Text(this.nameOf(this.store.selectedName))
                .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.c.textStrong)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
              .layoutWeight(1)
              .alignItems(VerticalAlign.Center)

            Stack({ alignContent: Alignment.Center }) {
              Text('✕')
                .fontSize(13).fontColor(this.c.detailSub)
            }
              .width(28).height(28)
              .borderRadius(14)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.onDismiss() })
          }
            .width('100%')
            .alignItems(VerticalAlign.Center)

          Text(this.subtitleText(this.store.selectedType, this.store.selectedMagnitude, this.store.selectedConstellation, this.store.selectedDistance, this.store.selectedDistanceCompact))
            .fontSize(11).fontColor(this.c.detailSub)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
          .width('100%')
          .height('100%')
          .padding({ left: 12, right: 10, top: 8, bottom: 8 })
          .justifyContent(FlexAlign.Center)
      } else {
        Row({ space: 8 }) {
          Stack({ alignContent: Alignment.Center }) {
            Image(getCatalogIcon(this.iconName, this.c.isNight))
              .width(18).height(18).fillColor(this.c.dockActive)
          }
            .width(32).height(32)
            .borderRadius(16)
            .backgroundColor(this.c.soft)

          Column({ space: 2 }) {
            Text(this.nameOf(this.store.selectedName))
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.c.textStrong)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.subtitleText(this.store.selectedType, this.store.selectedMagnitude, this.store.selectedConstellation, this.store.selectedDistance, this.store.selectedDistanceCompact).length > 0) {
              Text(this.subtitleText(this.store.selectedType, this.store.selectedMagnitude, this.store.selectedConstellation, this.store.selectedDistance, this.store.selectedDistanceCompact))
                .fontSize(11).fontColor(this.c.detailSub)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

          Stack({ alignContent: Alignment.Center }) {
            Text('✕')
              .fontSize(13).fontColor(this.c.detailSub)
          }
            .width(32).height(32)
            .borderRadius(16)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.onDismiss() })
        }
          .width('100%')
          .height('100%')
          .padding({ left: 12, right: 8 })
          .alignItems(VerticalAlign.Center)
      }
    }
      .id('object-detail-time-light')
      .width('100%')
      .height('100%')
  }
}
