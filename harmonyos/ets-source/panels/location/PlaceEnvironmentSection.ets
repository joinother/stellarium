import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { pressureAtAltitudeHpa, temperatureAtAltitudeC } from '../../common/derive/atmosphere'
import { BarometerReader } from '../../capability/BarometerReader'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { panelFontSize } from '../../common/ui/UiTypography'

// 共享的观测环境模块（仅地球观测点）：按海拔推算站点气压与基准气温，
// 或直接用设备气压计测量站点气压。位置面板和「图层 → 天空 → 观测条件」
// 都嵌入本组件，保证两处的交互与视觉一致。结果需显式应用，避免编辑海拔时
// 反复触发 native 命令。外星观测点不套用地球标准大气，由调用方隐藏。
@Component
export struct PlaceEnvironmentSection {
  @Prop altitude: number = 0
  // 当前已应用的大气参数，用于显示“已应用”状态。
  @Prop currentPressure: number = 1013
  @Prop currentTemperature: number = 10
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private mode: string = 'estimate'
  @State private barometerAvailable: boolean = false
  @State private barometerState: string = 'idle'
  @State private measuredPressure: number = 0
  @State private status: string = ''
  // 点击应用后立刻反馈，不依赖宿主回包的异步刷新。
  @State private lastAppliedPressure: number = -1
  @State private lastAppliedTemperature: number = -999
  onApply: (pressure: number, temperature: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  aboutToAppear(): void {
    this.barometerAvailable = BarometerReader.available()
  }

  private estimatedPressure(): number {
    return pressureAtAltitudeHpa(this.altitude)
  }

  private estimatedTemperature(): number {
    return temperatureAtAltitudeC(this.altitude)
  }

  private barometerValueActive(): boolean {
    // Keep showing the last sample while a re-read is in flight.
    return this.mode === 'barometer' && this.measuredPressure > 0 &&
      (this.barometerState === 'ok' || this.barometerState === 'reading')
  }

  private activePressure(): number {
    // Match the native clamp (0..1500 hPa) so "applied" never stays false
    // because a bad sensor sample was silently bounded.
    if (this.barometerValueActive()) {
      return Math.max(1, Math.min(1500, this.measuredPressure))
    }
    return this.estimatedPressure()
  }

  private activeTemperature(): number {
    return this.estimatedTemperature()
  }

  private shownPressure(): number {
    return this.lastAppliedPressure >= 0 ? this.lastAppliedPressure : this.currentPressure
  }

  private shownTemperature(): number {
    return this.lastAppliedTemperature > -900 ? this.lastAppliedTemperature : this.currentTemperature
  }

  private applied(): boolean {
    return Math.abs(this.shownPressure() - this.activePressure()) < 0.6 &&
      Math.abs(this.shownTemperature() - this.activeTemperature()) < 0.6
  }

  private selectMode(mode: string): void {
    // 每次进入“气压计测量”（含再次点按）都重新读数，避免展示过期气压。
    if (mode === this.mode) {
      if (mode === 'barometer') this.measure()
      return
    }
    this.mode = mode
    this.status = ''
    if (mode === 'barometer') this.measure()
  }

  private measure(): void {
    if (!this.barometerAvailable || this.barometerState === 'reading') return
    this.barometerState = 'reading'
    this.status = ''
    BarometerReader.read().then((pressure: number) => {
      if (!Number.isFinite(pressure) || pressure <= 0) {
        this.failMeasurement()
        return
      }
      this.measuredPressure = Math.round(pressure * 10) / 10
      this.barometerState = 'ok'
      this.status = I18n.t('place_env_barometer_done')
    }).catch(() => {
      this.failMeasurement()
    })
  }

  private failMeasurement(): void {
    this.barometerState = 'error'
    this.mode = 'estimate'
    this.status = I18n.t('place_env_barometer_failed')
  }

  private sourceLabel(): string {
    if (this.barometerValueActive()) return I18n.t('place_env_source_barometer')
    return I18n.t('place_env_source_estimate')
  }

  private hintText(): string {
    if (this.barometerState === 'reading') return I18n.t('place_env_barometer_reading')
    if (this.status.length > 0) return this.status
    if (!this.barometerAvailable) return I18n.t('place_env_barometer_unavailable')
    return ''
  }

  @Builder
  modeChip(mode: string, label: string, enabled: boolean) {
    Button(label)
      .height(30)
      .fontSize(panelFontSize(12, this.readableUi))
      .fontColor(this.mode === mode ? this.c.onAccent : this.c.sub)
      .backgroundColor(this.mode === mode ? this.c.accent : this.c.bg)
      .border({ width: 1, color: this.mode === mode ? this.c.softStrong : this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .layoutWeight(1)
      .enabled(enabled)
      .opacity(enabled ? 1 : 0.55)
      .onClick(() => { this.selectMode(mode) })
  }

  build() {
    Column({ space: 6 }) {
      Text(I18n.t('place_env_title')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width('100%')
      Text(I18n.t('place_env_hint')).fontSize(10).fontColor(this.c.sub).width('100%')
      Row({ space: 6 }) {
        this.modeChip('estimate', I18n.t('place_env_mode_estimate'), true)
        this.modeChip('barometer', I18n.t('place_env_mode_barometer'), this.barometerAvailable)
      }
        .width('100%')
        .margin({ top: 2 })
      Row() {
        Text(I18n.t('place_env_pressure')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
        Text(this.activePressure().toFixed(1) + ' hPa')
          .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        Text(this.sourceLabel()).fontSize(10).fontColor(this.c.sub)
      }
        .height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
        .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL)
      Row() {
        Text(I18n.t('place_env_temperature')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
        Text(this.activeTemperature().toFixed(1) + ' °C')
          .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        Text(I18n.t('place_env_source_estimate')).fontSize(10).fontColor(this.c.sub)
      }
        .height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
        .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL)
      Text(I18n.format('place_env_current_model',
        [this.shownPressure().toFixed(1), this.shownTemperature().toFixed(1)]))
        .fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 2 })
      if (this.hintText().length > 0) {
        Text(this.hintText()).fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 2 })
      }
      Button(this.applied() ? I18n.t('place_env_applied') : I18n.t('place_env_apply'))
        .height(this.readableUi ? 40 : 36).fontSize(panelFontSize(12, this.readableUi))
        .fontColor(this.c.onAccent)
        .backgroundColor(this.applied() ? this.c.softStrong : this.c.accent)
        .borderRadius(UI_RADIUS_CONTROL)
        .width('100%')
        .enabled(this.barometerState !== 'reading')
        .id('place-environment-apply')
        .onClick(() => {
          const pressure = this.activePressure()
          const temperature = this.activeTemperature()
          this.lastAppliedPressure = pressure
          this.lastAppliedTemperature = temperature
          this.status = ''
          this.onApply(pressure, temperature)
        })
    }
      .width('100%')
      .padding(10)
      .backgroundColor(this.c.soft)
      .border({ width: 1, color: this.c.softStrong })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ bottom: 8 })
      .id('place-environment')
  }
}
