import { I18n } from '../../pages/I18n'
import { PolarScopeStore } from '../../state/PolarScopeStore'
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
  onRecenter: () => void = () => {}
  onClose: () => void = () => {}
  onHorizontalFlipChange: (value: boolean) => void = (value: boolean) => {}
  onVerticalFlipChange: (value: boolean) => void = (value: boolean) => {}

  build() {
    Stack() {
      Stack() { }
        .width('100%').height('100%')
        .hitTestBehavior(HitTestMode.Default)
        .onTouch((event: TouchEvent) => { this.onSkyTouch(event) })
      Row({ space: 8 }) {
        Text(I18n.t('polar_scope_title'))
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#F7F7F8')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1).margin({ left: 12 })
          .hitTestBehavior(HitTestMode.None)
        Button({ type: ButtonType.Circle }) {
          Image(getIcon('polar_scope', false)).width(22).height(22).fillColor('#F4A7A1')
        }.width(48).height(48).backgroundColor('rgba(244,111,107,0.12)')
          .accessibilityText(I18n.t('btn_center'))
          .id('polar-scope-center').onClick(() => { this.onRecenter() })
        Button({ type: ButtonType.Circle }) {
          Image(getIcon('close', false)).width(22).height(22).fillColor('#F4F4F5')
        }
          .width(48).height(48)
          .backgroundColor('rgba(255,255,255,0.12)')
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .hitTestBehavior(HitTestMode.Block)
          .id('polar-scope-close').accessibilityText(I18n.t('polar_scope_close'))
          .onClick(() => { this.onClose() })
      }
        .width(this.controlWidth).height(60)
        .padding({ left: 8, right: 6 })
        .position({ x: (this.skyWidth - this.controlWidth) / 2, y: this.topInset })
        .backgroundColor('rgba(15, 20, 30, 0.82)')
        .backdropBlur(16).borderRadius(UI_RADIUS_PANEL)
        .border({ width: 1, color: 'rgba(255,255,255,0.10)' })
        .hitTestBehavior(HitTestMode.Default)

      if (this.polarScopeStore.polarScopeLoading) {
        Column({ space: 10 }) {
          LoadingProgress().width(34).height(34).color('#F46F6B')
          Text(I18n.t('polar_scope_aligning')).fontSize(12).fontColor('#FFE1DF')
        }
          .padding(16)
          .backgroundColor('rgba(24, 6, 10, 0.68)')
          .backdropBlur(16)
          .borderRadius(UI_RADIUS_PANEL)
          .hitTestBehavior(HitTestMode.Block)
      } else if (this.polarScopeStore.polarScopeError.length > 0) {
        Text(this.polarScopeStore.polarScopeError)
          .fontSize(13).fontColor('#FFE1DF').textAlign(TextAlign.Center)
          .padding({ left: 18, right: 18, top: 14, bottom: 14 })
          .backgroundColor('rgba(56, 8, 12, 0.78)')
          .borderRadius(UI_RADIUS_PANEL)
          .hitTestBehavior(HitTestMode.Block)
      }

      Column({ space: this.isExpandedLayout ? 5 : 8 }) {
        Text(I18n.t(this.polarScopeStore.polarScopeData?.hemisphere === 'south' ? 'polar_scope_south_position' : 'polar_scope_north_position'))
          .fontSize(this.isExpandedLayout ? 13 : 16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F3F3F5')
          .width('100%')
        Row() {
          Text(I18n.t('polar_scope_hour_angle')).fontSize(11).fontColor('rgba(255, 255, 255, 0.60)')
            .width(this.isExpandedLayout ? 120 : 92)
          Text(this.polarScopeStore.polarScopeData?.hourAngleText ?? '--')
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#F7F7F8').fontFamily('monospace')
        }.width('100%')
        Row() {
          Text(I18n.t('polar_scope_view_angle')).fontSize(11).fontColor('rgba(255, 255, 255, 0.60)')
            .width(this.isExpandedLayout ? 120 : 92)
          Text(this.polarScopeStore.polarScopeData?.viewAngleText ?? '--')
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#F7F7F8').fontFamily('monospace')
        }.width('100%')
        Row({ space: 18 }) {
          Row({ space: 8 }) {
            Text(I18n.t('polar_scope_flip_horizontal')).fontSize(12).fontColor('rgba(255, 221, 219, 0.82)').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.polarScopeStore.polarScopeHorizontalFlip })
              .width(42).height(24).selectedColor('#C44949')
              .id('polar-scope-flip-horizontal')
              .onChange((value: boolean) => {
                this.onHorizontalFlipChange(value)
              })
          }.layoutWeight(1)
          Row({ space: 8 }) {
            Text(I18n.t('polar_scope_flip_vertical')).fontSize(12).fontColor('rgba(255, 221, 219, 0.82)').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.polarScopeStore.polarScopeVerticalFlip })
              .width(42).height(24).selectedColor('#C44949')
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
        .backgroundColor('rgba(15, 20, 30, 0.82)')
        .backdropBlur(16).borderRadius(UI_RADIUS_PANEL)
        .border({ width: 1, color: 'rgba(255,255,255,0.10)' })
        .hitTestBehavior(HitTestMode.Default)
    }
      .width('100%').height('100%')
      .backgroundColor('rgba(0,0,0,0)')
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      .zIndex(101)
  }
}
