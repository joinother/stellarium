import { Theme } from '@kit.ArkUI'
import { I18n, LANGUAGE_DISPLAY, SUPPORTED_LANGUAGES } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { AppFilingInfo } from '../../common/ui/AppFilingInfo'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 本组件文件：设置面板的「语言」「陀螺仪」「设备与隐私」三块。
//
// `DevicePrivacySection` 内部直接渲染 `GyroscopeRow`，宿主只注入陀螺仪开关值与写回回调；
// 语言行只用 `selectedLanguage` 与选中回调（其余颜色为内联常量）。

// 语言选择行：单 row，点击右侧当前值展开上下滚动的下拉选框。
@Component
export struct LanguageRow {
  @Prop selectedLanguage: string
  @State c: ThemeSlots = DEFAULT_SLOTS
  // 主题槽位 bg 是半透明色，Select 菜单默认还叠了一层 COMPONENT_ULTRA_THICK
  // 模糊材质（浅色），夜间会变成白底红字。菜单必须用不透明夜间底色并关掉模糊。
  @StorageLink('stellariumNightMode') private nightMode: boolean = false
  onSelect: (code: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private menuBackground(): ResourceColor {
    // 日间主题的文字是白色（#E5FFFFFF），弹层必须用不透明的深色面板底，
    // 否则白字落在近白菜单上完全不可读。夜间沿用深红黑。
    return this.nightMode ? '#150505' : '#101E2C'
  }

  private currentIndex(): number {
    const index = SUPPORTED_LANGUAGES.indexOf(this.selectedLanguage)
    return index < 0 ? 0 : index
  }

  private languageOptions(): SelectOption[] {
    const options: SelectOption[] = []
    for (let index = 0; index < SUPPORTED_LANGUAGES.length; index += 1) {
      const code = SUPPORTED_LANGUAGES[index]
      const option: SelectOption = { value: LANGUAGE_DISPLAY[code] ?? code }
      options.push(option)
    }
    return options
  }

  build() {
    Row() {
      Text(I18n.t('i0029'))
        .fontSize(14)
        .fontColor(this.c.text)
        .layoutWeight(1)
      Select(this.languageOptions())
        .selected(this.currentIndex())
        .value(LANGUAGE_DISPLAY[this.selectedLanguage] ?? this.selectedLanguage)
        .font({ size: 12 })
        .fontColor(this.c.text)
        .selectedOptionFontColor(this.c.onAccent)
        .optionFontColor(this.c.text)
        .backgroundColor(this.c.bg)
        .selectedOptionBgColor(this.c.accent)
        .optionBgColor(this.menuBackground())
        .menuBackgroundColor(this.menuBackground())
        // 默认 COMPONENT_ULTRA_THICK 会在不透明底色上再叠一层浅色材质。
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .width(170)
        .onSelect((index: number, value: string) => {
          const code = SUPPORTED_LANGUAGES[index]
          if (code !== undefined) {
            this.onSelect(code)
          }
        })
    }
    .height(40)
    .width('100%')
    .padding({ left: 10, right: 10 })
  }
}

// 陀螺仪开关行。
@Component
export struct GyroscopeRow {
  @Prop isOn: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row() {
      Text(I18n.t('i0043'))
        .fontSize(14)
        .fontColor(this.c.text)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .width(46)
        .height(28)
        .onChange((value: boolean) => { this.onToggle(value) })
    }
      .height(40)
      .width('100%')
  }
}

// 设备与隐私设置块：陀螺仪开关 + 灵敏度 + 隐私撤销。
@Component
export struct DevicePrivacySection {
  @Prop gyroscopeEnabled: boolean
  @Prop sensitivityText: string
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggleGyroscope: (value: boolean) => void = () => {}
  onRevoke: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 0 }) {
      Text(I18n.t('settings_device_privacy')).fontSize(13).fontColor(this.c.text).width('100%').margin({ top: 4, bottom: 8 })
      AppFilingInfo()
      GyroscopeRow({ isOn: this.gyroscopeEnabled, onToggle: (value: boolean) => { this.onToggleGyroscope(value) } })
      Row() {
        Text(I18n.t('i0230')).fontSize(12).fontColor(this.c.sub).width(86)
        Text(this.sensitivityText).fontSize(11).fontColor(this.c.text).layoutWeight(1)
      }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      Text(I18n.t('settings_gyro_desc'))
        .fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 8 })
      Button(I18n.t('privacy_revoke'))
        .fontSize(13).fontColor(this.c.errorText).backgroundColor(this.c.errorBg)
        .border({ width: 1, color: this.c.errorBg })
        .borderRadius(UI_RADIUS_CONTROL).height(38).width('100%')
        .onClick(() => { this.onRevoke() })
      Text(I18n.t('privacy_revoke_message'))
        .fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 10, right: 10 }).margin({ top: 6 })
    }.width('100%')
  }
}
