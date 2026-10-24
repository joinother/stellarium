import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { ShellAction } from '../../pages/StellariumTypes'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// "更多"面板的三类入口列表（观测 / 天空数据 / 自动化）。
//
// 三类列表结构完全一致，只有入口集合与说明文字不同：``@Prop actions``
// 承载入口数组、``@Prop description`` 承载说明，点按回注 ``openSubPanel``。
// 键生成里的 ``languageRevision`` 由宿主传入，以便切语言后重建 ForEach。

@Component
export struct HubActionList {
  @Prop actions: ShellAction[]
  @Prop description: ResourceStr
  @Prop languageRevision: number
  @State c: ThemeSlots = DEFAULT_SLOTS
  onOpenPanel: (panel: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 7 }) {
      Text(this.description)
        .fontSize(11)
        .lineHeight(16)
        .fontColor(this.c.sub)
        .width('100%')
        .padding({ left: 4, right: 4, bottom: 4 })
      ForEach(this.actions, (item: ShellAction) => {
        Button() {
          Row({ space: 12 }) {
            Stack() {
              Circle().width(38).height(38).fill(this.c.softStrong)
                Image(getIcon(item.icon, false)).width(21).height(21).supportSvg2(true).colorFilter(tintMatrixFor(this.c.iconSecondary))
             }.width(38).height(38)
             Text(item.label)
               .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
             Image(getIcon('chevron_right', false)).width(19).height(19).supportSvg2(true).colorFilter(tintMatrixFor(this.c.iconSecondary))
          }
            .width('100%').height('100%').padding({ left: 12, right: 12 })
        }
          .id('hub-action-' + item.panel)
          .width('100%').height(58).padding(0)
          .backgroundColor(this.c.rowBg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .stateStyles({ pressed: { .scale({ x: 0.98, y: 0.98 }).backgroundColor(this.c.softStrong) } })
          .animation({ duration: 180, curve: Curve.EaseOut })
          .onClick(() => { this.onOpenPanel(item.panel) })
      }, (item: ShellAction) => item.icon + '/' + item.panel + '/' + this.languageRevision.toString())
    }
      .width('100%')
      .padding({ bottom: 12 })
      .hitTestBehavior(HitTestMode.Default)
  }
}
