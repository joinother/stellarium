import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { panelFontSize } from '../../common/ui/UiTypography'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../capability/I18n'

@Component
export struct HapticSection {
  @Prop @Watch('syncEnabled') hapticEnabled: boolean = false
  @Prop available: boolean = false
  @Prop failed: boolean = false
  @Prop busy: boolean = false
  @Prop @Watch('syncIntensity') intensity: number = 40
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  // Toggle 的 isOn 不能直接绑 @Prop：父层写回 @Prop 时会再触发一次
  // onChange（真机上观察到 true 后 67ms 又收到 false），导致开关自己弹回。
  // 用本地状态承接用户操作，并用值相等判断忽略这次程序化回声。
  @State private toggleOn: boolean = false
  @State private intensityValue: number = 40
  @State private intensityExpanded: boolean = false
  @State private previewing: boolean = false
  @State c: ThemeSlots = DEFAULT_SLOTS
  onChange: (enabled: boolean) => void = () => {}
  onIntensityChange: (value: number, commit: boolean) => void = () => {}
  onPreview: () => void = () => {}

  aboutToAppear(): void {
    this.toggleOn = this.hapticEnabled
    this.intensityValue = this.intensity
  }

  private syncEnabled(): void {
    this.toggleOn = this.hapticEnabled
  }

  private syncIntensity(): void {
    this.intensityValue = this.intensity
  }

  private userChanged(value: boolean): void {
    if (value === this.toggleOn) return
    this.toggleOn = value
    this.onChange(value)
  }

  private changeIntensity(value: number, commit: boolean): void {
    const next = Math.round(value)
    if (next === this.intensityValue) {
      if (commit) this.onIntensityChange(next, true)
      return
    }
    this.intensityValue = next
    this.onIntensityChange(next, commit)
  }

  private preview(): void {
    if (this.previewing) return
    this.previewing = true
    this.onPreview()
    // The service throttles confirmation pulses for 300ms. Keep the button
    // unavailable for the same window instead of treating the skip as failure.
    setTimeout(() => { this.previewing = false }, 360)
  }

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private text(zh: string, en: string): string {
    return I18n.getLanguage().startsWith('zh') ? zh : en
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 12 }) {
        Text(this.text('触觉反馈', 'Haptic feedback'))
          .fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.toggleOn })
          .selectedColor(this.c.accent).enabled(!this.busy && (this.available || this.toggleOn))
          .onChange((value: boolean) => this.userChanged(value))
      }
        .width('100%')
        .height(this.readableUi ? 50 : 42)
        .padding({ left: 10, right: 8 })
      Text(this.failed
        ? this.text('系统未能播放触觉效果，请检查系统触感设置与设备支持情况。', 'The system could not play haptics. Check system haptics and device support.')
        : this.available
        ? this.text('选中天体、切换面板与时间刻度时，给予轻微反馈。', 'Gentle feedback for object selection, panels and time steps.')
        : this.text('此设备不支持应用使用的轻触振动效果。', 'This device does not support these gentle haptic effects.'))
        .fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 8 }).margin({ bottom: 4 })
      Row({ space: 8 }) {
        Text(this.text('震动力度', 'Vibration strength'))
          .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        Text(this.intensityValue.toString() + '%')
          .fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).maxLines(1)
        Text(this.intensityExpanded ? this.text('收起', 'Hide') : this.text('调整', 'Adjust'))
          .fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.accent)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.c.input).borderRadius(8)
      }
        .width('100%')
        .height(34)
        .padding({ left: 10, right: 8 })
        .margin({ bottom: 8 })
        .onClick(() => { this.intensityExpanded = !this.intensityExpanded })
      if (this.intensityExpanded) {
        Row() {
          Column({ space: 6 }) {
            Row() {
              Text(this.text('震动力度', 'Strength'))
                .fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).layoutWeight(1)
              Text(this.intensityValue.toString() + '%')
                .fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.text)
            }.width('100%')
            Slider({ value: this.intensityValue, min: 10, max: 100, step: 5, style: SliderStyle.OutSet })
              .width('100%')
              .enabled(this.available && this.toggleOn && !this.busy)
              .trackColor(this.c.input).selectedColor(this.c.accent).blockColor(this.c.accent)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.changeIntensity(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click)
              })
            Row() {
              Text(this.text('轻', 'Light')).fontSize(panelFontSize(9, this.readableUi)).fontColor(this.c.tertiary)
              Blank()
              Text(this.text('强', 'Strong')).fontSize(panelFontSize(9, this.readableUi)).fontColor(this.c.tertiary)
            }.width('100%')
            Text(this.text('实际手感受系统触感设置与设备马达支持影响。',
              'Actual feel depends on system haptics and device support.'))
              .fontSize(panelFontSize(9, this.readableUi)).fontColor(this.c.sub).width('100%').maxLines(2)
            Button(this.text('试一下', 'Try feedback'), { type: ButtonType.Normal })
              .height(36).width('100%').borderRadius(UI_RADIUS_CONTROL)
              .backgroundColor(this.c.input).fontColor(this.c.text)
              .enabled(this.available && this.toggleOn && !this.busy && !this.previewing)
              .onClick(() => { this.preview() })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(this.c.bg)
          .border({ width: 1, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL)
        }
        .width('100%')
        .padding({ left: 10, right: 8, bottom: 8 })
      }
    }
    .width('100%')
    .backgroundColor(this.toggleOn ? this.c.soft : this.c.bg)
    .border({ width: 1, color: this.toggleOn ? this.c.soft : this.c.dividerSoft })
    .borderRadius(UI_RADIUS_CONTROL)
    .margin({ bottom: 6 })
  }
}
