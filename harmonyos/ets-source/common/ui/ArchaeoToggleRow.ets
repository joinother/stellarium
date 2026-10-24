import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from './UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 考古线设置开关行（标签 + 开关，选中态带底色/描边强调）。
@Component
export struct ArchaeoToggleRow {
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
      Text(this.label).fontSize(12).fontColor(this.c.text).layoutWeight(1).maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .enabled(this.canToggle)
        .onChange((v: boolean) => { this.onToggle(v) })
    }.width('100%').padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.isOn ? this.c.soft : this.c.bg)
      .border({ width: 1, color: this.isOn ? this.c.soft : this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
  }
}
