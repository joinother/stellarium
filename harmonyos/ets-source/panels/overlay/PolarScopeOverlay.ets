import { I18n } from '../../pages/I18n'
import { PolarScopeStore } from '../../state/PolarScopeStore'
import { Theme } from '@kit.ArkUI'
import { ThemeSlots, DEFAULT_SLOTS, slotsFromTheme } from '../../state/StellariumTheme'
import { getIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'

// 「极轴镜」屏幕叠层。
//
// 分工（叠层几何不入被观察 store）：
//   - 极轴镜状态（polarScopeData / Loading / Error / HorizontalFlip / VerticalFlip / Visible）
//     收于 state/PolarScopeStore.ets，本组件以 @ObjectLink 订阅；可见性判定在宿主调用点
//     （`if (this.polarScopeStore.polarScopeVisible)`），
//     读数（isSouthHemisphere / hourAngleText / viewAngleText）由本组件就地读 store 的 polarScopeData 派生；
//   - 几何全部由宿主给出：`polarScopeControlWidth()` / `polarScopeTopInset()` / `polarScopeFooterHeight()`
//     与 `skyWidth` / `skyHeight` 以 @Prop（controlWidth / topInset / footerHeight /
//     skyWidth / skyHeight）传入 —— 手工命中路由（`isUiPoint` / `isDockPoint` / `handleSkyTouch`）与
//     `syncNativePolarScopeOverlay()` 复用同一批几何，必须保持单一口径；
//   - 全屏透明层的 `onTouch` 只做转发，注入 `onSkyTouch`（避开 `CustomComponent.onTouch`），
//     命中判定仍在宿主 `handleSkyTouch` 内；
//   - 翻转开关只回注 `onHorizontalFlipChange` / `onVerticalFlipChange`，由宿主负责
//     `syncNativePolarScopeOverlay()` 与 `callInteractive('setActionChecked', ...)`。
//
// 组件根即全屏 `Stack`（zIndex 101 / BLOCK_HIERARCHY）。
// 主题色走「机制四」：onWillApplyTheme 自取当前主题槽位，调用点不再注入颜色。
//
// 稳定 id：polar-scope-center / polar-scope-close / polar-scope-flip-horizontal /
// polar-scope-flip-vertical。
@Component
export struct PolarScopeOverlay {
  @ObjectLink polarScopeStore: PolarScopeStore
  @Prop controlWidth: number
  @Prop topInset: number
  @Prop footerHeight: number
  @Prop skyWidth: number
  @Prop skyHeight: number
  @Prop isExpandedLayout: boolean
  onSkyTouch: (event: TouchEvent) => void = (event: TouchEvent) => {}
  onSkyMouse: (event: MouseEvent) => void = () => {}
  onSkyAxis: (event: AxisEvent) => void = () => {}
  onRecenter: () => void = () => {}
  onClose: () => void = () => {}
  onHorizontalFlipChange: (value: boolean) => void = (value: boolean) => {}
  onVerticalFlipChange: (value: boolean) => void = (value: boolean) => {}
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Stack() {
      Stack() { }
        .width('100%').height('100%')
        .hitTestBehavior(HitTestMode.Default)
        .onTouch((event: TouchEvent) => { this.onSkyTouch(event) })
        .onMouse((event: MouseEvent) => { this.onSkyMouse(event) })
        .onAxisEvent((event: AxisEvent) => { this.onSkyAxis(event) })
      Row({ space: 8 }) {
        Text(I18n.t('polar_scope_title'))
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1).margin({ left: 12 })
          .hitTestBehavior(HitTestMode.None)
        Button({ type: ButtonType.Circle }) {
          Image(getIcon('polar_scope', false)).width(22).height(22).fillColor(this.c.icon)
        }.width(48).height(48).backgroundColor(this.c.accentSoft)
          .accessibilityText(I18n.t('btn_center'))
          .id('polar-scope-center').onClick(() => { this.onRecenter() })
        Button({ type: ButtonType.Circle }) {
          Image(getIcon('close', false)).width(22).height(22).fillColor(this.c.textStrong)
        }
          .width(48).height(48)
          .backgroundColor(this.c.overlayButton)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .hitTestBehavior(HitTestMode.Block)
          .id('polar-scope-close').accessibilityText(I18n.t('polar_scope_close'))
          .onClick(() => { this.onClose() })
      }
        .width(this.controlWidth).height(60)
        .padding({ left: 8, right: 6 })
        .position({ x: (this.skyWidth - this.controlWidth) / 2, y: this.topInset })
        .backgroundColor(this.c.overlayPanel)
        .backdropBlur(16).borderRadius(UI_RADIUS_PANEL)
        .border({ width: 1, color: this.c.border })
        .hitTestBehavior(HitTestMode.Default)

      if (this.polarScopeStore.polarScopeLoading) {
        Column({ space: 10 }) {
          LoadingProgress().width(34).height(34).color(this.c.icon)
          Text(I18n.t('polar_scope_aligning')).fontSize(12).fontColor(this.c.warning)
        }
          .padding(16)
          .backgroundColor(this.c.overlayPanel)
          .backdropBlur(16)
          .borderRadius(UI_RADIUS_PANEL)
          .hitTestBehavior(HitTestMode.Block)
      } else if (this.polarScopeStore.polarScopeError.length > 0) {
        Text(this.polarScopeStore.polarScopeError)
          .fontSize(13).fontColor(this.c.warning).textAlign(TextAlign.Center)
          .padding({ left: 18, right: 18, top: 14, bottom: 14 })
          .backgroundColor(this.c.overlayPanel)
          .borderRadius(UI_RADIUS_PANEL)
          .hitTestBehavior(HitTestMode.Block)
      }

      Column({ space: this.isExpandedLayout ? 5 : 8 }) {
        Text(I18n.t(this.polarScopeStore.polarScopeData?.hemisphere === 'south' ? 'polar_scope_south_position' : 'polar_scope_north_position'))
          .fontSize(this.isExpandedLayout ? 13 : 16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textStrong)
          .width('100%')
        Row() {
          Text(I18n.t('polar_scope_hour_angle')).fontSize(11).fontColor(this.c.icon)
            .width(this.isExpandedLayout ? 120 : 92)
          Text(this.polarScopeStore.polarScopeData?.hourAngleText ?? '--')
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong).fontFamily('monospace')
        }.width('100%')
        Row() {
          Text(I18n.t('polar_scope_view_angle')).fontSize(11).fontColor(this.c.icon)
            .width(this.isExpandedLayout ? 120 : 92)
          Text(this.polarScopeStore.polarScopeData?.viewAngleText ?? '--')
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong).fontFamily('monospace')
        }.width('100%')
        Row({ space: 18 }) {
          Row({ space: 8 }) {
            Text(I18n.t('polar_scope_flip_horizontal')).fontSize(12).fontColor(this.c.warning).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.polarScopeStore.polarScopeHorizontalFlip })
              .width(42).height(24)
              .id('polar-scope-flip-horizontal')
              .onChange((value: boolean) => {
                this.onHorizontalFlipChange(value)
              })
          }.layoutWeight(1)
          Row({ space: 8 }) {
            Text(I18n.t('polar_scope_flip_vertical')).fontSize(12).fontColor(this.c.warning).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.polarScopeStore.polarScopeVerticalFlip })
              .width(42).height(24)
              .id('polar-scope-flip-vertical')
              .onChange((value: boolean) => {
                this.onVerticalFlipChange(value)
              })
          }.layoutWeight(1)
        }.width('100%')
      }
        .width('100%')
        .height(this.footerHeight)
        .padding({ left: this.isExpandedLayout ? 28 : 18, right: this.isExpandedLayout ? 28 : 18,
          top: this.isExpandedLayout ? 10 : 14, bottom: this.isExpandedLayout ? 10 : 16 })
        .width(this.controlWidth)
        .position({ x: (this.skyWidth - this.controlWidth) / 2,
          y: this.skyHeight - this.footerHeight - 12 })
        .backgroundColor(this.c.overlayPanel)
        .backdropBlur(16).borderRadius(UI_RADIUS_PANEL)
        .border({ width: 1, color: this.c.border })
        .hitTestBehavior(HitTestMode.Default)
    }
      .width('100%').height('100%')
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      .zIndex(101)
  }
}
