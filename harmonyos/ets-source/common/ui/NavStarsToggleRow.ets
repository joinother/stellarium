import { UI_RADIUS_CONTROL } from './UiTokens'

// 导航星插件设置开关行（标签 + 开关，可禁用）。
@Component
export struct NavStarsToggleRow {
  @Prop label: ResourceStr
  @Prop isOn: boolean
  @Prop canToggle: boolean
  @Prop textColor: string
  @Prop panelColor: string
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Text(this.label).fontSize(12).fontColor(this.textColor).layoutWeight(1).maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .enabled(this.canToggle)
        .onChange((value: boolean) => { this.onToggle(value) })
    }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
  }
}
