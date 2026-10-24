import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { OverlayStore } from '../../state/OverlayStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 本组件职责：「视图中心坐标」设置区。
//
// 组件收一个 store 与三个写回回调：
//   - 开关与档位的当前值读 @ObjectLink store（`I18n` 文案经 store 的两个纯查表方法）；
//   - `setViewCoordinatesVisible` / `setViewCoordinateFamily` / `setViewEquatorialEpoch` 由宿主提供
//     （它们要同步定时器与 saveAppSettings），以回调注入。
@Component
export struct ViewCoordinateSettings {
  @ObjectLink store: OverlayStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggleVisible: (visible: boolean) => void = () => {}
  onSelectFamily: (family: string) => void = () => {}
  onSelectEpoch: (epoch: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 7 }) {
      Text(I18n.t('view_coord_center_title'))
        .fontSize(13)
        .fontColor(this.c.text)
        .width('100%')
      Row() {
        Column({ space: 2 }) {
          Text(I18n.t('view_coord_show_on_screen')).fontSize(13).fontColor(this.c.text).width('100%')
          Text(I18n.t('view_coord_show_hint')).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.store.viewCoordinatesVisible })
          .width(46)
          .height(28)
          .onChange((value: boolean) => { this.onToggleVisible(value) })
      }
        .width('100%')
        .padding({ left: 10, right: 8, top: 7, bottom: 7 })
        .backgroundColor(this.store.viewCoordinatesVisible ? this.c.soft : this.c.bg)
        .border({ width: 1, color: this.store.viewCoordinatesVisible ? this.c.soft : this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)

      Text(I18n.t('view_coord_system')).fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 2 })
      Row({ space: 6 }) {
        ForEach(['equatorial', 'horizontal', 'galactic'], (family: string) => {
          Text(this.store.viewCoordinateFamilyLabel(family))
            .fontSize(11)
            .fontColor(this.store.viewCoordinateFamily === family ? this.c.onAccent : this.c.sub)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(30)
            .padding({ top: 6 })
            .backgroundColor(this.store.viewCoordinateFamily === family ? this.c.accent : this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL)
            .animation({ duration: 180, curve: Curve.EaseOut })
            .onClick(() => { this.onSelectFamily(family) })
        }, (family: string) => family)
      }.width('100%')

      if (this.store.viewCoordinateFamily === 'equatorial') {
        Row({ space: 6 }) {
          ForEach(['j2000', 'ofDate'], (epoch: string) => {
            Text(I18n.t(epoch === 'j2000' ? 'view_coord_j2000' : 'view_coord_of_date'))
              .fontSize(11)
              .fontColor(this.store.viewEquatorialEpoch === epoch ? this.c.onAccent : this.c.sub)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(30)
              .padding({ top: 6 })
              .backgroundColor(this.store.viewEquatorialEpoch === epoch ? this.c.accent : this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL)
              .animation({ duration: 180, curve: Curve.EaseOut })
              .onClick(() => { this.onSelectEpoch(epoch) })
          }, (epoch: string) => epoch)
        }.width('100%')
      }
    }.width('100%').margin({ bottom: 8 })
  }
}
