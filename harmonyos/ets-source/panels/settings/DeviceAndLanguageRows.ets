import { I18n, LANGUAGE_DISPLAY, SUPPORTED_LANGUAGES } from '../../pages/I18n'
import { LangOption } from '../../pages/StellariumTypes'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { AppFilingInfo } from '../../common/ui/AppFilingInfo'

// 本组件文件：设置面板的「语言」「陀螺仪」「设备与隐私」三块。
//
// `DevicePrivacySection` 内部直接渲染 `GyroscopeRow`，宿主只注入陀螺仪开关值与写回回调；
// 语言行只用 `selectedLanguage` 与选中回调（其余颜色为内联常量）。

// 语言选择行（横向可滚动 chip）。
@Component
export struct LanguageRow {
  @Prop selectedLanguage: string
  onSelect: (code: string) => void = () => {}

  build() {
    Row() {
      Text(I18n.t('i0029'))
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .width(72)
      Scroll() {
        Row({ space: 6 }) {
          ForEach(SUPPORTED_LANGUAGES.map((code: string): LangOption => ({
            code: code,
            name: LANGUAGE_DISPLAY[code] ?? code
          })), (lang: LangOption) => {
            Text(lang.name)
              .fontSize(12)
              .fontColor(this.selectedLanguage === lang.code ? '#F4FAFF' : '#C8D4E2')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.selectedLanguage === lang.code ? '#5B93BF' : 'rgba(255,255,255,0.06)')
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onSelect(lang.code) })
          }, (lang: LangOption) => lang.code)
        }
        .padding({ left: 4, right: 4 })
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .height(40)
    .width('100%')
  }
}

// 陀螺仪开关行。
@Component
export struct GyroscopeRow {
  @Prop isOn: boolean
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Text(I18n.t('i0043'))
        .fontSize(14)
        .fontColor('#E5FFFFFF')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .width(46)
        .height(28)
        .selectedColor('#5B93BF')
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
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  onToggleGyroscope: (value: boolean) => void = () => {}
  onRevoke: () => void = () => {}

  build() {
    Column({ space: 0 }) {
      Text(I18n.t('settings_device_privacy')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4, bottom: 8 })
      AppFilingInfo({ subColor: this.subColor, panelColor: this.panelColor })
      GyroscopeRow({ isOn: this.gyroscopeEnabled, onToggle: (value: boolean) => { this.onToggleGyroscope(value) } })
      Row() {
        Text(I18n.t('i0230')).fontSize(12).fontColor(this.subColor).width(86)
        Text(this.sensitivityText).fontSize(11).fontColor(this.textColor).layoutWeight(1)
      }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      Text(I18n.t('settings_gyro_desc'))
        .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 8 })
      Button(I18n.t('privacy_revoke'))
        .fontSize(13).fontColor('#FFD9D9').backgroundColor('rgba(255, 121, 121, 0.12)')
        .border({ width: 1, color: 'rgba(255, 121, 121, 0.24)' })
        .borderRadius(UI_RADIUS_CONTROL).height(38).width('100%')
        .onClick(() => { this.onRevoke() })
      Text(I18n.t('privacy_revoke_message'))
        .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 10, right: 10 }).margin({ top: 6 })
    }.width('100%')
  }
}
