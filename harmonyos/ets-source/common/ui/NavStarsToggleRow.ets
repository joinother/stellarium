import { Theme } from '@kit.ArkUI'
import { panelFontSize } from './UiTypography'
import { UI_RADIUS_CONTROL } from './UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 导航星插件设置开关行（标签 + 开关，可禁用）。
@Component
export struct NavStarsToggleRow {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop label: ResourceStr
  @Prop isOn: boolean
  @Prop canToggle: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row() {
      Text(this.label).fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1).maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .enabled(this.canToggle)
        .onChange((value: boolean) => { this.onToggle(value) })
    }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
  }
}
