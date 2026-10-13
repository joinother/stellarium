import { UI_RADIUS_CONTROL, UI_OPTION_ANIMATION_MS } from './UiTokens'

// 带开关行的设置项（原参数化 @Builder timeSettingSwitchRow 的替代）。
//
// 原实现把 `enabled` 形参收下却忽略、直接读宿主字段，且整行由参数化 @Builder 构建
// （参数按值捕获 → 首帧后冻结）。改为组件后用 @Prop 传 isOn/可点状态，实时刷新。
@Component
export struct SettingsSwitchRow {
  @Prop label: string
  @Prop isOn: boolean
  @Prop canToggle: boolean
  @Prop textColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop borderColorValue: string
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Text(this.label).fontSize(11).fontColor(this.textColor).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn }).width(42).height(24).selectedColor(this.accentColor)
        .enabled(this.canToggle)
        .onChange((value: boolean) => { this.onToggle(value) })
    }.width('100%').padding({ left: 10, right: 8, top: 5, bottom: 5 })
      .backgroundColor(this.isOn ? this.panelColor : Color.Transparent).border({ width: 1, color: this.borderColorValue })
      .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
      .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 5 })
  }
}
