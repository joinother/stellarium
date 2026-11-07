import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// A compact label + slider + value row. Kept as a component instead of a
// parameterized @Builder because @Builder parameters are captured by value
// and the right-hand value text would not refresh while dragging.
@Component
export struct DsoSliderRow {
  @Prop label: ResourceStr
  @Prop value: number
  @Prop minValue: number
  @Prop maxValue: number
  @Prop stepValue: number
  @Prop valueWidth: number = 38
  @Prop sliderEnabled: boolean = true
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onValueChange: (value: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private displayValue(): string {
    return this.stepValue < 1 ? this.value.toFixed(1) : Math.round(this.value).toString()
  }

  build() {
    Row() {
      Text(this.label).fontSize(11).fontColor(this.c.sub).width(82)
      Slider({ value: this.value, min: this.minValue, max: this.maxValue, step: this.stepValue, style: SliderStyle.OutSet })
        .trackColor(this.c.bg).showSteps(false).layoutWeight(1)
        .onChange((next: number) => { this.onValueChange(next) })
      Text(this.displayValue()).fontSize(11).fontColor(this.c.text).width(this.valueWidth).textAlign(TextAlign.End)
    }.width('100%').height(34).padding({ left: 10, right: 10 })
    .enabled(this.sliderEnabled)
    .opacity(this.sliderEnabled ? 1 : 0.45)
  }
}
