import { Theme } from '@kit.ArkUI'
import { panelFontSize, uiControlHeight } from './UiTypography'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CONTROL } from './UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 导航星插件设置开关行（标签 + 开关，可禁用，与全局开关行统一规范）。
@Component
export struct NavStarsToggleRow {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @Prop label: ResourceStr
  @Prop isOn: boolean
  @Prop canToggle: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row({ space: 8 }) {
      Text(this.label)
        .fontSize(panelFontSize(13, this.readableUi))
        .fontColor(this.c.text)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .width(44)
        .height(26)
        .selectedColor(this.c.accent)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .enabled(this.canToggle)
        .onChange((value: boolean) => { this.onToggle(value) })
    }
      .width('100%')
      .constraintSize({ minHeight: uiControlHeight(40, this.readableUi, this.controlScale) })
      .padding({ left: 10, right: 8, top: 6, bottom: 6 })
      .backgroundColor(this.isOn ? this.c.soft : this.c.bg)
      .border({ width: 1, color: this.isOn ? this.c.soft : this.c.dividerSoft })
      .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
      .borderRadius(UI_RADIUS_CONTROL)
  }
}
