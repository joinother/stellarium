import { Theme } from '@kit.ArkUI'
import { I18n, LANGUAGE_DISPLAY, SUPPORTED_LANGUAGES } from '../../pages/I18n'
import { panelFontSize } from '../../common/ui/UiTypography'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { LayerSwitchRow } from '../layers/LayerSwitchRow'

// 本组件文件：设置面板的「语言」「陀螺仪」两块。
//
// `DeviceSection` 内直接渲染陀螺仪开关与灵敏度两个条目；两者沿用图层开关行的
// 卡片样式。隐私撤回按钮已移到设置页末尾，由 `SettingsPanel` 直接渲染。
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

// 陀螺仪灵敏度条目：不改变现有只读行为，只把展示行改成与图层条目一致的卡片样式。
@Component
export struct GyroSensitivityRow {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop sensitivityText: string
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row() {
      Text(I18n.t('i0061'))
        .fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
      Text(this.sensitivityText)
        .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub)
    }
      .height(this.readableUi ? 50 : 42)
      .width('100%')
      .padding({ left: 10, right: 8 })
      .backgroundColor(this.c.bg)
      .border({ width: 1, color: this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ bottom: 6 })
  }
}

// 设备设置块：陀螺仪开关 + 灵敏度，两个条目与图层开关行同宽同高。
@Component
export struct DeviceSection {
  @Prop gyroscopeEnabled: boolean
  @Prop sensitivityText: string
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggleGyroscope: (value: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 0 }) {
      LayerSwitchRow({
        label: I18n.t('i0043'),
        isOn: this.gyroscopeEnabled,
        onToggle: (value: boolean) => { this.onToggleGyroscope(value) }
      })
      GyroSensitivityRow({ sensitivityText: this.sensitivityText })
      Text(I18n.t('settings_gyro_desc'))
        .fontSize(10).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 10 }).margin({ top: 2, bottom: 6 })
    }.width('100%')
  }
}
