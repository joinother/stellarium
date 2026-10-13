import { I18n } from '../../pages/I18n'
import { SettingsChoiceButton } from '../../common/ui/SettingsChoiceButton'
import { UI_RADIUS_CONTROL, UI_OPTION_ANIMATION_MS } from '../../common/ui/UiTokens'

// 本组件文件：设置面板（"更多 > 设置"）里的各类行 / 按钮 —— 设置域专用。
//
// 这些行都读宿主状态（信息模式、掩码、导航开关、行星历表启用），
// 因此把"当前值/是否可点/夜视三色"由宿主算好后以 @Prop 传入、把写回动作以回调注入，
// 点按即可实时刷新。
// 命名说明：`EphemerisRow` 已是 `pages/StellariumTypes` 里的数据接口名，故组件取名 `EphemerisToggleRow`。

// 行星历表一行（标签 + 已安装状态 + 启用开关）。
@Component
export struct EphemerisToggleRow {
  @Prop label: string
  @Prop available: boolean
  @Prop isEnabled: boolean
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop borderColorValue: string
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Column({ space: 1 }) {
        Text(this.label).fontSize(11).fontColor(this.available ? this.textColor : this.subColor).width('100%')
        Text(this.available ? (this.isEnabled ? '已安装 · 使用中' : '已安装 · 未启用') : '未安装').fontSize(10).fontColor(this.subColor).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.isEnabled }).width(42).height(24).enabled(this.available)
        .selectedColor(this.accentColor).onChange((value: boolean) => { this.onToggle(value) })
    }.width('100%').padding({ left: 10, right: 8, top: 6, bottom: 6 })
      .backgroundColor(this.available && this.isEnabled ? this.panelColor : Color.Transparent)
      .border({ width: 1, color: this.available ? this.borderColorValue : 'rgba(255,255,255,0.03)' })
      .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
  }
}

// 信息显示模式选择按钮（all / default / short / none / custom）。
@Component
export struct InformationModeButton {
  @Prop labelKey: string
  @Prop active: boolean
  @Prop canPick: boolean
  @Prop textColor: string
  @Prop subColor: string
  @Prop activeColor: string
  @Prop panelColor: string
  onPick: () => void = () => {}

  build() {
    SettingsChoiceButton({
      label: I18n.t(this.labelKey),
      active: this.active,
      canPick: this.canPick,
      textColor: this.textColor,
      subColor: this.subColor,
      activeColor: this.activeColor,
      panelColor: this.panelColor,
      onPick: () => { this.onPick() }
    })
  }
}

// 自定义信息字段开关行。`inCustomMode` 用于背景高亮，
// `canToggle` 额外要求 !informationSettingPending。
@Component
export struct InformationSwitchRow {
  @Prop label: string
  @Prop isOn: boolean
  @Prop inCustomMode: boolean
  @Prop canToggle: boolean
  @Prop textColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop borderColorValue: string
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Text(this.label).fontSize(11).fontColor(this.textColor).layoutWeight(1).maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn }).width(42).height(24).selectedColor(this.accentColor)
        .enabled(this.canToggle)
        .onChange((value: boolean) => { this.onToggle(value) })
    }.width('100%').padding({ left: 10, right: 8, top: 5, bottom: 5 })
      .backgroundColor(this.inCustomMode && this.isOn ? this.panelColor : Color.Transparent)
      .border({ width: 1, color: this.borderColorValue })
      .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
      .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
  }
}

// 视口/导航开关行（鼠标、键盘、重力标签、自动缩放复位等）。
@Component
export struct NavigationSwitchRow {
  @Prop label: ResourceStr
  @Prop isOn: boolean
  @Prop textColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop borderColorValue: string
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Text(this.label).fontSize(13).fontColor(this.textColor).layoutWeight(1).maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .width(46).height(28).selectedColor(this.accentColor)
        .onChange((value: boolean) => { this.onToggle(value) })
    }
      .width('100%').padding({ left: 10, right: 8, top: 7, bottom: 7 })
      .backgroundColor(this.isOn ? 'rgba(107,163,214,0.12)' : this.panelColor)
      .border({ width: 1, color: this.isOn ? 'rgba(107,163,214,0.18)' : this.borderColorValue })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ bottom: 6 })
      .animation({ duration: 180, curve: Curve.EaseOut })
  }
}

