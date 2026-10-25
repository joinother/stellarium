import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { I18n } from '../../pages/I18n'
import { SettingsChoiceButton } from '../../common/ui/SettingsChoiceButton'
import { UI_RADIUS_CONTROL, UI_OPTION_ANIMATION_MS } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 本组件文件：设置面板（"更多 > 设置"）里的各类行 / 按钮 —— 设置域专用。
//
// 这些行都读宿主状态（信息模式、掩码、导航开关、行星历表启用），
// 因此把"当前值/是否可点"由宿主算好后以 @Prop 传入、把写回动作以回调注入，
// 点按即可实时刷新。
// 命名说明：`EphemerisRow` 已是 `pages/StellariumTypes` 里的数据接口名，故组件取名 `EphemerisToggleRow`。

// 行星历表一行（标签 + 已安装状态 + 启用开关）。
@Component
export struct EphemerisToggleRow {
  @Prop label: string
  @Prop available: boolean
  @Prop isEnabled: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row() {
      Column({ space: 1 }) {
        Text(this.label).fontSize(11).fontColor(this.available ? this.c.text : this.c.sub).width('100%')
        Text(this.available ? (this.isEnabled ? '已安装 · 使用中' : '已安装 · 未启用') : '未安装').fontSize(10).fontColor(this.c.sub).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.isEnabled }).width(42).height(24).enabled(this.available)
        .onChange((value: boolean) => { this.onToggle(value) })
    }.width('100%').padding({ left: 10, right: 8, top: 6, bottom: 6 })
      .backgroundColor(this.available && this.isEnabled ? this.c.bg : Color.Transparent)
      .border({ width: 1, color: this.available ? this.c.border : this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
  }
}

// 信息显示模式选择按钮（all / default / short / none / custom）。
@Component
export struct InformationModeButton {
  @Prop labelKey: string
  @Prop active: boolean
  @Prop canPick: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onPick: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    SettingsChoiceButton({
      label: I18n.t(this.labelKey),
      active: this.active,
      canPick: this.canPick,
      onPick: () => { this.onPick() }
    })
  }
}

// 自定义信息字段开关行。`inCustomMode` 用于背景高亮，
// `canToggle` 额外要求 !informationSettingPending。
@Component
export struct InformationSwitchRow {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop label: string
  @Prop isOn: boolean
  @Prop inCustomMode: boolean
  @Prop canToggle: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row() {
      Text(this.label).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text).layoutWeight(1).maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn }).width(42).height(24)
        .enabled(this.canToggle)
        .onChange((value: boolean) => { this.onToggle(value) })
    }.width('100%').padding({ left: 10, right: 8, top: this.readableUi ? 8 : 5, bottom: this.readableUi ? 8 : 5 })
      .backgroundColor(this.inCustomMode && this.isOn ? this.c.bg : Color.Transparent)
      .border({ width: 1, color: this.c.border })
      .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
      .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
  }
}

// 视口/导航开关行（鼠标、键盘、重力标签、自动缩放复位等）。
@Component
export struct NavigationSwitchRow {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop label: ResourceStr
  @Prop isOn: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row() {
      Text(this.label).fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1).maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .width(46).height(28)
        .onChange((value: boolean) => { this.onToggle(value) })
    }
      .width('100%').padding({ left: 10, right: 8, top: this.readableUi ? 9 : 7, bottom: this.readableUi ? 9 : 7 })
      .backgroundColor(this.isOn ? this.c.soft : this.c.bg)
      .border({ width: 1, color: this.isOn ? this.c.softStrong : this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ bottom: 6 })
      .animation({ duration: 180, curve: Curve.EaseOut })
  }
}
