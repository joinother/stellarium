import { Theme } from '@kit.ArkUI'
import { panelFontSize, uiChipPaddingV, uiControlHeight } from './UiTypography'
import { UI_RADIUS_CONTROL, UI_OPTION_ANIMATION_MS } from './UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 带开关行的设置项（原参数化 @Builder timeSettingSwitchRow 的替代）。
//
// 原实现把 `enabled` 形参收下却忽略、直接读宿主字段，且整行由参数化 @Builder 构建
// （参数按值捕获 → 首帧后冻结）。改为组件后用 @Prop 传 isOn/可点状态，实时刷新。
@Component
export struct SettingsSwitchRow {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @Prop label: string
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
        .fontSize(Math.round(panelFontSize(11, this.readableUi) * this.uiFontScale))
        .fontColor(this.c.text)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Toggle({ type: ToggleType.Switch, isOn: this.isOn }).width(42).height(24)
        .enabled(this.canToggle)
        .onChange((value: boolean) => { this.onToggle(value) })
    }.width('100%')
      .constraintSize({ minHeight: uiControlHeight(38, this.readableUi, this.controlScale) })
      .padding({
        left: 10,
        right: 8,
        top: uiChipPaddingV(this.readableUi ? 8 : 6, this.controlScale),
        bottom: uiChipPaddingV(this.readableUi ? 8 : 6, this.controlScale)
      })
      .backgroundColor(this.isOn ? this.c.bg : Color.Transparent).border({ width: 1, color: this.c.border })
      .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
      .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 5 })
  }
}
