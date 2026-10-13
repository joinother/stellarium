import { curves } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 本组件职责：「图层」面板的开关行。
//
// `@Prop isOn` 承载当前开关值，实时刷新行底色与边框色；
// onChange 的写回（setLayer / setBridgeFlag / setSkyDisplaySetting）与 flashHint 提示
// 经 onToggle 回调由宿主完成；
// 与当前值相同的重复触发在此拦掉。
@Component
export struct LayerSwitchRow {
  @Prop label: ResourceStr
  @Prop isOn: boolean
  @Prop labelColor: string = '#E5FFFFFF'
  @Prop selectedColor: string = '#5B93BF'
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor(this.labelColor)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .width(46)
        .height(28)
        .selectedColor(this.selectedColor)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onChange((value: boolean) => {
          if (value === this.isOn) return
          this.onToggle(value)
        })
    }
      .height(42)
      .width('100%')
      .padding({ left: 10, right: 8 })
      .backgroundColor(this.isOn ? 'rgba(107, 163, 214, 0.12)' : 'rgba(255, 255, 255, 0.04)')
      .border({ width: 1, color: this.isOn ? 'rgba(107, 163, 214, 0.18)' : 'rgba(255, 255, 255, 0.05)' })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ bottom: 6 })
      .animation({ duration: 200, curve: curves.springMotion(0.45, 0.9) })
  }
}
