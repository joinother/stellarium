import { UI_RADIUS_CONTROL } from './UiTokens'

// 考古线设置开关行（标签 + 开关，选中态带底色/描边强调）。
@Component
export struct ArchaeoToggleRow {
  @Prop label: ResourceStr
  @Prop isOn: boolean
  @Prop canToggle: boolean
  @Prop textColor: string
  @Prop panelColor: string
  @Prop borderColorValue: string
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Text(this.label).fontSize(12).fontColor(this.textColor).layoutWeight(1).maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .enabled(this.canToggle)
        .onChange((v: boolean) => { this.onToggle(v) })
    }.width('100%').padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.isOn ? 'rgba(107,163,214,0.12)' : this.panelColor)
      .border({ width: 1, color: this.isOn ? 'rgba(107,163,214,0.18)' : this.borderColorValue })
      .borderRadius(UI_RADIUS_CONTROL)
  }
}
