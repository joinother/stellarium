import { Theme } from '@kit.ArkUI'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 卫星面板的卫星分组选择器（横向胶囊条，避免嵌套竖向滚动冲突）。
//
// 组名本地化直接调用 I18n.satGroup。Scroller 以普通成员传入
// （宿主仍持有同一实例，`publishSatellitePanelState` 要读它的 currentOffset）。
// 事件标志读取与桥调用留在宿主，经 onGroupScroll / onSelect 注入。
@Component
export struct SatelliteGroupSelector {
  @Prop groups: string[]
  @Prop activeGroup: string
  @Prop loading: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  scroller: Scroller = new Scroller()
  onGroupScroll: () => void = () => {}
  onSelect: (group: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row({ space: 6 }) {
      Scroll(this.scroller) {
        Row({ space: 6 }) {
          Text(I18n.getLanguage().startsWith('zh') ? '全部' : 'All')
            .fontSize(12)
            .fontWeight(this.activeGroup.length === 0 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.activeGroup.length === 0 ? this.c.onAccent : this.c.sub)
            .padding({ left: 11, right: 11, top: 6, bottom: 6 })
            .backgroundColor(this.activeGroup.length === 0 ? this.c.accent : this.c.softStrong)
            .borderRadius(UI_RADIUS_PILL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
            .onClick(() => {
              if (this.activeGroup.length > 0) this.onSelect('')
            })
          ForEach(this.groups, (group: string) => {
            Row({ space: 4 }) {
              Text(I18n.satGroup(group))
                .fontSize(12)
                .fontWeight(this.activeGroup === group ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.activeGroup === group ? this.c.onAccent : this.c.text)
                .maxLines(1)
              if (this.activeGroup === group) {
                Text('✓')
                  .fontSize(11)
                  .fontColor(this.c.onAccent)
                  .opacity(this.activeGroup === group ? 1 : 0)
              }
            }
              .padding({ left: 11, right: 11, top: 6, bottom: 6 })
              .backgroundColor(this.activeGroup === group ? this.c.accent : this.c.softStrong)
              .borderRadius(UI_RADIUS_PILL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
              .onClick(() => { this.onSelect(this.activeGroup === group ? '' : group) })
          }, (group: string) => group)
        }.padding({ right: 4 })
      }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .height(36)
        .layoutWeight(1)
        .onScroll(() => { this.onGroupScroll() })

      if (this.loading) {
        LoadingProgress().width(16).height(16).color(this.c.accent)
      }
    }
      .width('100%')
      .alignItems(VerticalAlign.Center)
  }
}
