import { curves } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { ShellAction } from '../../pages/StellariumTypes'

// “更多”主菜单面板，对应 `activePanel === 'more'`。
//
// 入口集合 moreActions() 由宿主算好后以 @Prop 传入；是否为新分节依赖宿主状态，经回调判定。
// ForEach 键里的 languageRevision 由宿主传入，以便切语言后重建列表。

@Component
export struct MorePanel {
  @Prop actions: ShellAction[]
  @Prop languageRevision: number
  startsSection: (item: ShellAction, index: number) => boolean = () => false
  onOpenPanel: (panel: string) => void = () => {}

  build() {
    Column({ space: 6 }) {
      ForEach(this.actions, (item: ShellAction, index: number) => {
        if (this.startsSection(item, index)) {
          Text(item.section === undefined ? '' : item.section)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#8FBBD6')
            .width('100%')
            .margin({ top: index === 0 ? 0 : 10, bottom: 1 })
        }
        Button() {
          Row({ space: 12 }) {
            Stack() {
              Circle()
                .width(38)
                .height(38)
                .fill('rgba(91, 147, 191, 0.20)')
              Image(getIcon(item.icon, false))
                .width(21)
                .height(21)
                .fillColor('#B8E4FF')
            }
              .width(38)
              .height(38)
            Text(item.label)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF7FF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Image(getIcon('chevron_right', false))
              .width(19)
              .height(19)
              .fillColor('rgba(184, 228, 255, 0.72)')
          }
            .width('100%')
            .height('100%')
            .padding({ left: 12, right: 12 })
        }
          .id('more-action-' + item.panel)
          .width('100%')
          .height(58)
          .padding(0)
          .backgroundColor('rgba(255, 255, 255, 0.045)')
          .border({ width: 0.5, color: 'rgba(147, 215, 255, 0.10)' })
          .borderRadius(UI_RADIUS_CONTROL)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .stateStyles({
            pressed: {
              .scale({ x: 0.98, y: 0.98 })
              .backgroundColor('rgba(91, 147, 191, 0.20)')
            }
          })
          .animation({ duration: 220, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => {
            this.onOpenPanel(item.panel)
          })
      }, (item: ShellAction) => item.icon + '/' + item.panel + '/' + this.languageRevision.toString())
    }
      .width('100%')
      .padding({ bottom: 12 })
  }
}
