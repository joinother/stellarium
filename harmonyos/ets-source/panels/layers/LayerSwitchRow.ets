import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { uiSpringStandard } from '../../common/ui/UiMotion'
import { InfoTipButton } from '../../common/ui/InfoTipButton'

// 本组件职责：「图层」面板的开关行。
//
// `@Prop isOn` 承载当前开关值，实时刷新行底色与边框色；
// onChange 的写回（setLayer / setBridgeFlag / setSkyDisplaySetting）与 flashHint 提示
// 经 onToggle 回调由宿主完成；与当前值相同的重复触发在此拦掉。
// 可选 `infoTip` 在标签旁渲染统一的 ⓘ 气泡按钮，将冗长说明收入弹窗以保持列表清爽；
// `hint` 仅用于必须直出的短状态提示（如外星禁用原因）。
@Component
export struct LayerSwitchRow {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop label: ResourceStr
  // Optional secondary line for live status/disabled notes. When present the row grows to fit it.
  @Prop hint: ResourceStr = ''
  // Optional contextual explanation displayed in a native bindPopup on tapping ⓘ.
  @Prop infoTip: ResourceStr = ''
  @Prop isOn: boolean
  // Disabled rows keep their preference visible but cannot be changed (e.g.
  // the Earth-only mist horizon while observing another body).
  // Named rowEnabled because CustomComponent already exposes enabled().
  @Prop rowEnabled: boolean = true
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private hasHint(): boolean {
    if (typeof this.hint === 'string') return this.hint.length > 0
    return true
  }

  private hasInfoTip(): boolean {
    if (typeof this.infoTip === 'string') return this.infoTip.length > 0
    return true
  }

  build() {
    Row({ space: 4 }) {
      Column({ space: 1 }) {
        Row({ space: 2 }) {
          Text(this.label)
            .fontSize(panelFontSize(14, this.readableUi))
            .fontColor(this.c.text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(this.hasInfoTip() ? 0 : 1)
            .constraintSize(this.hasInfoTip() ? { maxWidth: '88%' } : {})
          if (this.hasInfoTip()) {
            InfoTipButton({ title: this.label, tip: this.infoTip })
          }
        }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        if (this.hasHint()) {
          Text(this.hint)
            .fontSize(10)
            .fontColor(this.c.sub)
            .width('100%')
            .maxLines(3)
        }
      }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .width(46)
        .height(28)
        .selectedColor(this.c.accent)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .enabled(this.rowEnabled)
        .onChange((value: boolean) => {
          if (!this.rowEnabled || value === this.isOn) return
          this.onToggle(value)
        })
    }
      .height(this.hasHint() ? (this.readableUi ? 64 : 56) : (this.readableUi ? 50 : 42))
      .width('100%')
      .padding({ left: 10, right: 8 })
      .backgroundColor(this.isOn ? this.c.soft : this.c.bg)
      .border({ width: 1, color: this.isOn ? this.c.soft : this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ bottom: 6 })
      .opacity(this.rowEnabled ? 1 : 0.55)
      .animation({ curve: uiSpringStandard() })
  }
}
