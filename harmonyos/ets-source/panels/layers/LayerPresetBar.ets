import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 本组件职责：「图层」面板顶部的图层预设条。
//
// 预设的应用逻辑（applyLayerPreset）走原生桥与 flashHint，由宿主提供、以回调注入。
// 「清除坐标与标记」按钮已上移到面板标题栏（见 PanelHeader 的 headerActionLabel / onHeaderAction）。
@Component
export struct LayerPresetBar {
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onPreset: (preset: string) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 6 }) {
      Text('快捷场景预设').fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.c.sub).width('100%').padding({ left: 2 })
      Row({ space: 8 }) {
        Button('纯净星空')
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.text).backgroundColor(this.c.bg)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .onClick(() => { this.onPreset('clean') })
        Button('观测辅助')
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.text).backgroundColor(this.c.bg)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .onClick(() => { this.onPreset('observe') })
        Button('摄影构图')
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.text).backgroundColor(this.c.bg)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .onClick(() => { this.onPreset('photo') })
      }.width('100%').padding({ left: 2, right: 2 })
    }.width('100%').margin({ bottom: 6 })
  }
}
