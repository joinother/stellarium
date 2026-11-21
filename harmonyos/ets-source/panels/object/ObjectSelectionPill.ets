import { Theme } from '@kit.ArkUI'
import { getCatalogIcon } from '../../common/ui/ShellIcons'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 轻点星体后的「一阶段轻量浮标」：
// 紧凑磨砂胶囊悬浮在底部 Dock 上方，仅占极小视野，保留 95% 以上纯粹星空；
// 展示天体名称 + 类型 / 星等 / 星座或距离摘要；轻点浮标任意位置平滑展开完整详情卡，
// 点右侧 ✕ 或空白星空即刻取消选中。
@Component
export struct ObjectSelectionPill {
  @ObjectLink store: ObjectDetailStore
  @Prop iconName: string
  @Prop pillWidth: number
  @Prop pillHeight: number
  @Prop distanceSummaryText: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  nameOf: (name: string) => string = () => ''
  typeOf: (type: string) => string = () => ''
  onExpand: () => void = () => {}
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
    if (this.isCompactTwoRow()) {
      // 窄宽度自适应双行紧凑卡片（竖屏平板打开左侧菜单、或窄屏手机顶部）：
      // 首行完整展示图标 + 天体名称 + 关闭键，次行完整展示类型/星等/星座摘要 + 「详情 ›」，
      // 避免把 4 列硬挤进一行导致标题和星等被截断。
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
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.onExpand() })

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

        Row({ space: 8 }) {
          Text(this.subtitleText(this.store.selectedType, this.store.selectedMagnitude, this.store.selectedConstellation, this.store.selectedDistance, this.store.selectedDistanceCompact))
            .fontSize(11).fontColor(this.c.detailSub)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Row({ space: 2 }) {
            Text('详情')
              .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.accent)
            Text('›')
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.c.accent)
              .margin({ bottom: 1 })
          }
            .padding({ left: 9, right: 7, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(this.c.soft)
        }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onExpand() })
      }
        .width(this.pillWidth)
        .height(this.pillHeight)
        .padding({ left: 12, right: 10, top: 8, bottom: 8 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.c.overlayPanel)
        .backdropBlur(28)
        .border({ width: 0.5, color: this.c.softStrong })
        .borderRadius(20)
        .shadow({ radius: 18, color: this.c.shadowSoft, offsetX: 0, offsetY: 6 })
    } else {
      Row({ space: 8 }) {
        // 主体点击区：点击浮标平滑展开完整详情卡
        Row({ space: 9 }) {
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

          Row({ space: 2 }) {
            Text('详情')
              .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.accent)
            Text('›')
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.c.accent)
              .margin({ bottom: 1 })
          }
            .padding({ left: 9, right: 7, top: 5, bottom: 5 })
            .borderRadius(14)
            .backgroundColor(this.c.soft)
        }
          .layoutWeight(1)
          .height('100%')
          .alignItems(VerticalAlign.Center)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onExpand() })

        // 独立关闭按钮：不触发展开，直接取消选中
        Stack({ alignContent: Alignment.Center }) {
          Text('✕')
            .fontSize(13).fontColor(this.c.detailSub)
        }
          .width(32).height(32)
          .borderRadius(16)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onDismiss() })
      }
        .width(this.pillWidth)
        .height(this.pillHeight)
        .padding({ left: 12, right: 8 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.c.overlayPanel)
        .backdropBlur(28)
        .border({ width: 0.5, color: this.c.softStrong })
        .borderRadius(29)
        .shadow({ radius: 18, color: this.c.shadowSoft, offsetX: 0, offsetY: 6 })
    }
  }
}
