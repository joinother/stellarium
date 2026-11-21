import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { panelFontSize } from '../../common/ui/UiTypography'
import { LayerSwitchRow } from './LayerSwitchRow'
import { PlaceEnvironmentSection } from '../location/PlaceEnvironmentSection'

// 观测辅助块：大气折射（气压 / 气温 / 消光），嵌在「图层 → 天空 → 观测条件」节内。
//
// 海拔推算 / 气压计实测与位置面板共用同一个 PlaceEnvironmentSection；
// 手动微调不再用滑杆：点按「调整」弹出多列 TextPicker 滚轮，整数位与小数位分开，
// 温度额外提供正负号列，因此 -60.0..60.0 °C 都能精确设置。
//
// 状态由宿主持有、以 @Prop 下发，因为 `applyAtmosphere()` 是宿主的命令桥入口。
@Component
export struct ObservationAidBlock {
  @Prop refractionOn: boolean
  @Prop atmoPressure: number
  @Prop atmoTemperature: number
  @Prop atmoExtinction: number
  @Prop altitude: number = 0
  @Prop earthObserver: boolean = true
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  // 自定义滚轮弹层：系统 TextPickerDialog 在浅色系统主题下会变成白底白字，
  // 且不跟随应用夜间模式；这里改用应用自己的卡片 + TextPicker 列。
  @State private editorOpen: boolean = false
  @State private editorTarget: string = ''
  @State private pressureWholeIndex: number = 0
  @State private pressureFracIndex: number = 0
  @State private tempWholeIndex: number = 0
  @State private tempFracIndex: number = 0
  @State private extWholeIndex: number = 0
  @State private extFracIndex: number = 0
  private pressureWholeRange: string[] = []
  private tenRange: string[] = []
  // Temperature whole part includes negatives and a "-0" entry so negative
  // fractions such as -0.5 are selectable without a separate sign wheel.
  private tempWholeRange: string[] = []
  private extWholeRange: string[] = ['0', '1']
  private extFracRange: string[] = []
  onAtmosphere: (pressure: number, temperature: number, extinction: number) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  aboutToAppear(): void {
    this.pressureWholeRange = this.numberRange(0, 1100)
    this.tenRange = this.numberRange(0, 9)
    const temperatureRange: string[] = []
    for (let value = -60; value <= -1; value += 1) temperatureRange.push(value.toString())
    temperatureRange.push('-0')
    for (let value = 0; value <= 60; value += 1) temperatureRange.push(value.toString())
    this.tempWholeRange = temperatureRange
    this.extFracRange = this.paddedRange(0, 99, 2)
  }

  private temperatureWholeIndex(value: number): number {
    const absWhole = Math.floor(Math.abs(value))
    if (value < 0) return absWhole === 0 ? 60 : 60 - absWhole
    return 61 + absWhole
  }

  private temperatureFromWholeLabel(label: string, fraction: number): number {
    const negative = label.startsWith('-')
    const absWhole = Math.abs(parseInt(label, 10))
    let value = (negative ? -1 : 1) * (absWhole + fraction / 10)
    if (value === 0) value = 0
    return value
  }

  private numberRange(min: number, max: number): string[] {
    const values: string[] = []
    for (let value = min; value <= max; value += 1) values.push(value.toString())
    return values
  }

  private paddedRange(min: number, max: number, width: number): string[] {
    const values: string[] = []
    for (let value = min; value <= max; value += 1) {
      let text = value.toString()
      while (text.length < width) text = '0' + text
      values.push(text)
    }
    return values
  }

  private openEditor(target: string): void {
    if (target === 'pressure') {
      const bounded = Math.max(0, Math.min(1100, this.atmoPressure))
      const scaled = Math.round(bounded * 10)
      this.pressureWholeIndex = Math.floor(scaled / 10)
      this.pressureFracIndex = scaled % 10
      this.editorTarget = 'pressure'
    } else if (target === 'temperature') {
      const bounded = Math.max(-60, Math.min(60, this.atmoTemperature))
      const scaled = Math.round(Math.abs(bounded) * 10)
      this.tempWholeIndex = this.temperatureWholeIndex(bounded)
      this.tempFracIndex = scaled % 10
      this.editorTarget = 'temperature'
    } else if (target === 'extinction') {
      const bounded = Math.max(0, Math.min(1, this.atmoExtinction))
      const scaled = Math.round(bounded * 100)
      this.extWholeIndex = Math.floor(scaled / 100)
      this.extFracIndex = scaled % 100
      this.editorTarget = 'extinction'
    } else {
      return
    }
    this.editorOpen = true
  }

  private dialogBackground(): ResourceColor {
    return this.c.isNight ? '#150505' : '#101E2C'
  }

  private editorTitle(): string {
    if (this.editorTarget === 'pressure') return I18n.t('atmo_pressure')
    if (this.editorTarget === 'temperature') return I18n.t('atmo_temperature')
    return I18n.t('atmo_extinction')
  }

  private editorPreview(): string {
    if (this.editorTarget === 'pressure') {
      return (this.pressureWholeIndex + this.pressureFracIndex / 10).toFixed(1) + ' hPa'
    }
    if (this.editorTarget === 'temperature') {
      const label = this.tempWholeRange.length > this.tempWholeIndex
        ? this.tempWholeRange[this.tempWholeIndex] : '0'
      return this.temperatureFromWholeLabel(label, this.tempFracIndex).toFixed(1) + ' °C'
    }
    return (this.extWholeIndex + this.extFracIndex / 100).toFixed(2)
  }

  private confirmEditor(): void {
    if (this.editorTarget === 'pressure') {
      const pressure = this.pressureWholeIndex + this.pressureFracIndex / 10
      this.onAtmosphere(pressure, this.atmoTemperature, this.atmoExtinction)
    } else if (this.editorTarget === 'temperature') {
      const label = this.tempWholeRange.length > this.tempWholeIndex
        ? this.tempWholeRange[this.tempWholeIndex] : '0'
      const temperature = this.temperatureFromWholeLabel(label, this.tempFracIndex)
      this.onAtmosphere(this.atmoPressure, temperature, this.atmoExtinction)
    } else {
      const extinction = this.extWholeIndex + this.extFracIndex / 100
      this.onAtmosphere(this.atmoPressure, this.atmoTemperature, extinction)
    }
    this.editorOpen = false
  }

  @Builder
  wheelColumn(range: string[], selected: number, kind: string) {
    TextPicker({ range: range, selected: selected })
      .layoutWeight(1).height(180)
      .canLoop(false)
      .textStyle({ color: this.c.sub, font: { size: 14 } })
      .selectedTextStyle({ color: this.c.text, font: { size: 17, weight: FontWeight.Medium } })
      .disappearTextStyle({ color: this.c.tertiary, font: { size: 13 } })
      .onChange((value: string | string[], index: number | number[]) => {
        const selectedIndex = typeof index === 'number'
          ? index : (index.length > 0 ? index[0] : 0)
        if (kind === 'pressureWhole') this.pressureWholeIndex = selectedIndex
        else if (kind === 'pressureFrac') this.pressureFracIndex = selectedIndex
        else if (kind === 'tempWhole') this.tempWholeIndex = selectedIndex
        else if (kind === 'tempFrac') this.tempFracIndex = selectedIndex
        else if (kind === 'extWhole') this.extWholeIndex = selectedIndex
        else if (kind === 'extFrac') this.extFracIndex = selectedIndex
      })
  }

  @Builder
  editorCover() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.55)')
        .onClick(() => { this.editorOpen = false })
      Column({ space: 12 }) {
        Text(this.editorTitle()).fontSize(16).fontColor(this.c.text).width('100%')
        Row({ space: 6 }) {
          if (this.editorTarget === 'pressure') {
            this.wheelColumn(this.pressureWholeRange, this.pressureWholeIndex, 'pressureWhole')
            this.wheelColumn(this.tenRange, this.pressureFracIndex, 'pressureFrac')
          } else if (this.editorTarget === 'temperature') {
            this.wheelColumn(this.tempWholeRange, this.tempWholeIndex, 'tempWhole')
            this.wheelColumn(this.tenRange, this.tempFracIndex, 'tempFrac')
          } else {
            this.wheelColumn(this.extWholeRange, this.extWholeIndex, 'extWhole')
            this.wheelColumn(this.extFracRange, this.extFracIndex, 'extFrac')
          }
        }
          .width('100%').height(180)
        Text(this.editorPreview()).fontSize(14).fontColor(this.c.text)
          .width('100%').textAlign(TextAlign.Center)
        Row({ space: 10 }) {
          Button(I18n.t('loc_cancel')).fontSize(14).fontColor(this.c.text)
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
            .height(38).layoutWeight(1)
            .onClick(() => { this.editorOpen = false })
          Button(I18n.t('loc_confirm')).fontSize(14).fontColor(this.c.onAccent)
            .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL)
            .height(38).layoutWeight(1)
            .onClick(() => { this.confirmEditor() })
        }.width('100%')
      }
        .width('86%').padding(16)
        .backgroundColor(this.dialogBackground())
        .border({ width: 1, color: this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
        .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)' })
    }
      .width('100%').height('100%')
  }

  // These rows read the @Prop values directly instead of taking a formatted
  // string through a parameterized @Builder: builder parameters are captured
  // by value, so the text stayed at the old pressure/temperature after a
  // native reply or wheel confirmation.
  @Builder
  pressureRow() {
    Row({ space: 6 }) {
      Text(I18n.t('atmo_pressure')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
      Text(this.atmoPressure.toFixed(1) + ' hPa')
        .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        .onClick(() => { this.openEditor('pressure') })
      Button(I18n.t('atmo_adjust')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
        .backgroundColor(this.c.softStrong)
        .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.openEditor('pressure') })
    }
      .height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
      .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  temperatureRow() {
    Row({ space: 6 }) {
      Text(I18n.t('atmo_temperature')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
      Text(this.atmoTemperature.toFixed(1) + ' °C')
        .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        .onClick(() => { this.openEditor('temperature') })
      Button(I18n.t('atmo_adjust')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
        .backgroundColor(this.c.softStrong)
        .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.openEditor('temperature') })
    }
      .height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
      .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  extinctionRow() {
    Row({ space: 6 }) {
      Text(I18n.t('atmo_extinction')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
      Text(this.atmoExtinction.toFixed(2))
        .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        .onClick(() => { this.openEditor('extinction') })
      Button(I18n.t('atmo_adjust')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
        .backgroundColor(this.c.softStrong)
        .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
        .onClick(() => { this.openEditor('extinction') })
    }
      .height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
      .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CONTROL)
  }

  build() {
    Column({ space: 6 }) {
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.border)
        .margin({ top: 8, bottom: 2 })
      LayerSwitchRow({
        label: I18n.t('atmo_refraction'),
        hint: I18n.t('atmo_refraction_hint'),
        isOn: this.refractionOn,
        onToggle: (v: boolean) => { this.onAtmosphere(v ? 1013 : 0, this.atmoTemperature, this.atmoExtinction) }
      })
      // 与位置面板完全相同的海拔推算 / 气压计模块。
      if (this.earthObserver) {
        PlaceEnvironmentSection({
          altitude: this.altitude,
          currentPressure: this.atmoPressure,
          currentTemperature: this.atmoTemperature,
          onApply: (pressure: number, temperature: number) => {
            this.onAtmosphere(pressure, temperature, this.atmoExtinction)
          }
        })
      }
      this.pressureRow()
      this.temperatureRow()
      this.extinctionRow()
      Text(I18n.t('atmo_extinction_hint'))
        .fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
      Text(I18n.t('atmo_value_hint'))
        .fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ bottom: 4 })
    }
      .width('100%')
      .bindContentCover(this.editorOpen, this.editorCover)
  }
}
