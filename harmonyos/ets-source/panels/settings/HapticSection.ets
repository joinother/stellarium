import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { panelFontSize } from '../../common/ui/UiTypography'
import { I18n } from '../../capability/I18n'

@Component
export struct HapticSection {
  @Prop hapticEnabled: boolean = false
  @Prop available: boolean = false
  @Prop failed: boolean = false
  @Prop busy: boolean = false
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @State c: ThemeSlots = DEFAULT_SLOTS
  onChange: (enabled: boolean) => void = () => {}
  onPreview: () => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private text(zh: string, en: string): string {
    return I18n.getLanguage().startsWith('zh') ? zh : en
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Text(this.text('触觉反馈', 'Haptic feedback'))
          .fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.hapticEnabled })
          .selectedColor(this.c.accent).enabled(!this.busy && (this.available || this.hapticEnabled))
          .onChange((value: boolean) => this.onChange(value))
      }.width('100%')
      Text(this.failed
        ? this.text('系统未能播放触觉效果，请检查系统触感设置与设备支持情况。', 'The system could not play haptics. Check system haptics and device support.')
        : this.available
        ? this.text('选中天体、切换面板与时间刻度时，给予轻微反馈。', 'Gentle feedback for object selection, panels and time steps.')
        : this.text('此设备不支持应用使用的轻触振动效果。', 'This device does not support these gentle haptic effects.'))
        .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub).width('100%')
      Button(this.text('试一下', 'Try feedback'), { type: ButtonType.Normal })
        .height(40).borderRadius(14).backgroundColor(this.c.softStrong).fontColor(this.c.text)
        .enabled(this.available && this.hapticEnabled && !this.busy).onClick(() => this.onPreview())
    }.width('100%').padding(12).margin({ bottom: 12 }).backgroundColor(this.c.softStrong).borderRadius(14)
  }
}
