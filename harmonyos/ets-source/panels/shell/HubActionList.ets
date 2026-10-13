import { curves } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { ShellAction } from '../../pages/StellariumTypes'

// "更多"面板的三类入口列表（观测 / 天空数据 / 自动化）。
//
// 三类列表结构完全一致，只有入口集合与说明文字不同：``@Prop actions``
// 承载入口数组、``@Prop description`` 承载说明，点按回注 ``openSubPanel``。
// 键生成里的 ``languageRevision`` 由宿主传入，以便切语言后重建 ForEach。

@Component
export struct HubActionList {
  @Prop actions: ShellAction[]
  @Prop description: ResourceStr
  @Prop subColor: string
  @Prop languageRevision: number
  onOpenPanel: (panel: string) => void = () => {}

  build() {
    Column({ space: 7 }) {
      Text(this.description)
        .fontSize(11)
        .lineHeight(16)
        .fontColor(this.subColor)
        .width('100%')
        .padding({ left: 4, right: 4, bottom: 4 })
      ForEach(this.actions, (item: ShellAction) => {
        Button() {
          Row({ space: 12 }) {
            Stack() {
              Circle().width(38).height(38).fill('rgba(91, 147, 191, 0.20)')
              Image(getIcon(item.icon, false)).width(21).height(21).fillColor('#B8E4FF')
            }.width(38).height(38)
            Text(item.label)
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#EAF7FF')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Image(getIcon('chevron_right', false)).width(19).height(19).fillColor('rgba(184, 228, 255, 0.72)')
          }
            .width('100%').height('100%').padding({ left: 12, right: 12 })
        }
          .id('hub-action-' + item.panel)
          .width('100%').height(58).padding(0)
          .backgroundColor('rgba(255, 255, 255, 0.045)')
          .border({ width: 0.5, color: 'rgba(147, 215, 255, 0.10)' })
          .borderRadius(UI_RADIUS_CONTROL)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .stateStyles({ pressed: { .scale({ x: 0.98, y: 0.98 }).backgroundColor('rgba(91, 147, 191, 0.20)') } })
          .animation({ duration: 180, curve: Curve.EaseOut })
          .onClick(() => { this.onOpenPanel(item.panel) })
      }, (item: ShellAction) => item.icon + '/' + item.panel + '/' + this.languageRevision.toString())
    }
      .width('100%')
      .padding({ bottom: 12 })
      .hitTestBehavior(HitTestMode.Default)
  }
}
