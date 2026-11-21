import { curves, LengthMetrics, Theme } from '@kit.ArkUI'
import { LandscapeItem } from '../../pages/StellariumTypes'
import { I18n } from '../../pages/I18n'
import { LayerStore } from '../../state/LayerStore'
import { LayerViewStore } from '../../state/LayerViewStore'
import { OverlayStore } from '../../state/OverlayStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_MEDIA, UI_RADIUS_TAG } from '../../common/ui/UiTokens'
import { panelFontSize } from '../../common/ui/UiTypography'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { getLandscapeStoryZh, LandscapeStoryZh } from '../../common/derive/LandscapeStoriesZh'
import { absoluteScaleToStarBrightness, starBrightnessToAbsoluteScale } from '../../capability/SkyInputController'
import { LayerSwitchRow } from './LayerSwitchRow'
import { ObservationAidBlock } from './ObservationAidBlock'
import { AtmosphereGroundSection } from './AtmosphereGroundSection'
import { LayerSpectralSection } from './LayerSpectralSection'
import { DsoSettingsSection } from './DsoSettingsSection'
import { SurveyStore } from '../../state/SurveyStore'
import { ViewCoordinateSettings } from '../view/ViewCoordinateSettings'

// 流星 ZHR 对数滑块映射（0..100 -> 0..maxZhr），让静谧夜空 (10) 到流星暴 (24万) 都有舒适手感和清晰分辨率。
export function meteorZhrToSliderPos(zhr: number, maxZhr: number): number {
  const cap = Math.max(1000, maxZhr)
  const clamped = Math.max(0, Math.min(cap, Math.round(zhr)))
  if (clamped <= 0) return 0
  if (clamped <= 5) return 1
  const ratio = Math.log(clamped / 5) / Math.log(cap / 5)
  return Math.max(1, Math.min(100, Math.round(1 + ratio * 99)))
}

export function meteorZhrFromSliderPos(pos: number, maxZhr: number): number {
  const cap = Math.max(1000, maxZhr)
  const clamped = Math.max(0, Math.min(100, pos))
  if (clamped < 0.5) return 0
  if (clamped <= 1.5) return 5
  const raw = 5 * Math.pow(cap / 5, (clamped - 1) / 99)
  if (raw < 20) return Math.round(raw)
  if (raw < 100) return Math.round(raw / 5) * 5
  if (raw < 1000) return Math.round(raw / 10) * 10
  if (raw < 10000) return Math.round(raw / 100) * 100
  return Math.min(cap, Math.round(raw / 1000) * 1000)
}

export function formatMeteorZhrLabel(zhr: number): string {
  const v = Math.max(0, Math.round(zhr))
  if (v >= 10000) {
    const wan = v / 10000
    return (wan >= 10 ? wan.toFixed(0) : wan.toFixed(1).replace(/\.0$/, '')) + '万 /时'
  }
  if (v >= 1000) {
    const k = v / 1000
    return k.toFixed(1).replace(/\.0$/, '') + '千 /时'
  }
  return v.toString() + ' /时'
}

// 儒略日（UTC 0时为 .5）转 YYYY-MM-DD（Fliegel-Van Flandern 算法）
export function julianDayToIsoDate(jd: number): string {
  const z = Math.floor(jd + 0.5)
  const l0 = z + 68569
  const n = Math.floor((4 * l0) / 146097)
  const l1 = l0 - Math.floor((146097 * n + 3) / 4)
  const i = Math.floor((4000 * (l1 + 1)) / 1461001)
  const l2 = l1 - Math.floor((1461 * i) / 4) + 31
  const j = Math.floor((80 * l2) / 2447)
  const day = l2 - Math.floor((2447 * j) / 80)
  const l3 = Math.floor(j / 11)
  const month = j + 2 - 12 * l3
  const year = 100 * (n - 49) + i + l3
  const pad = (num: number): string => (num < 10 ? '0' + num.toString() : num.toString())
  return year.toString() + '-' + pad(month) + '-' + pad(day)
}

export function currentUtcMidnightJd(): number {
  return Math.floor(Date.now() / 86400000) + 2440587.5
}

interface MeteorPresetOption {
  label: string
  zhr: number
}

interface TonePresetOption {
  label: string
  lda: number
  maxdL: number
  gamma: number
}

const METEOR_ZHR_PRESETS: Array<MeteorPresetOption> = [
  { label: '静谧 10', zhr: 10 },
  { label: '活跃 120', zhr: 120 },
  { label: '流星雨 1500', zhr: 1500 },
  { label: '流星暴 1.5万', zhr: 15000 },
  { label: '极盛 10万', zhr: 100000 }
]

const TONE_MAPPING_PRESETS: Array<TonePresetOption> = [
  { label: '标准默认', lda: 50, maxdL: 100, gamma: 2.22 },
  { label: '深空暗夜', lda: 28, maxdL: 120, gamma: 2.05 },
  { label: '高对比', lda: 68, maxdL: 90, gamma: 2.45 },
  { label: '柔和护眼', lda: 42, maxdL: 150, gamma: 1.95 }
]

// 本组件文件：「图层」面板六个视图标签页（天空 / 太阳系天体 / 深空天体 /
// 标记与网格 / 地景 / 巡天）。
//
// 「天空」页按 恒星 / 天空 / 观测条件 三节排布，观测条件节内嵌大气折射块（ObservationAidBlock）。
// 纯展示值经 @ObjectLink 实时读，一切 native 桥动作经回调回注宿主：
// 开关布尔值走 LayerStore，数值 / 展开态走 LayerViewStore。
// 本文件不含 `@BuilderParam`，也不含参数化 `@Builder`（组件若承载宿主 `@Builder`，会渲染即退出）。
//
// 第七个标签页「天文化」由独立组件另行承载。

// 天空：恒星 / 天空 / 观测条件三节。
@Component
export struct LayerSkyTab {
  @ObjectLink layerStore: LayerStore
  @ObjectLink layerViewStore: LayerViewStore
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop nightModeOn: boolean
  @Prop observerAltitude: number = 0
  @Prop earthObserver: boolean = true
  @Prop refractionOn: boolean
  @Prop atmoPressure: number
  @Prop atmoTemperature: number
  @Prop atmoExtinction: number
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private meteorDragging: boolean = false
  @State private meteorDragPos: number = 8
  private lastMeteorCommitMs: number = 0
  private lastToneCommitMs: number = 0
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onSetSkyDisplay: (setting: string, value: boolean | number) => void = () => {}
  onStarMagLimit: (value: number) => void = () => {}
  onMilkyWayBright: (value: number) => void = () => {}
  onAtmosphere: (pressure: number, temperature: number, extinction: number) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private currentMeteorPos(): number {
    return this.meteorDragging
      ? this.meteorDragPos
      : meteorZhrToSliderPos(this.layerViewStore.meteorZhr, this.layerViewStore.meteorZhrMax)
  }

  private currentMeteorDisplayZhr(): number {
    return this.meteorDragging
      ? meteorZhrFromSliderPos(this.meteorDragPos, this.layerViewStore.meteorZhrMax)
      : this.layerViewStore.meteorZhr
  }

  private commitMeteorSlider(position: number, mode: SliderChangeMode): void {
    const pos = Math.max(0, Math.min(100, Math.round(position)))
    const zhr = meteorZhrFromSliderPos(pos, this.layerViewStore.meteorZhrMax)
    const now = Date.now()
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.meteorDragging = true
      this.meteorDragPos = pos
      if (now - this.lastMeteorCommitMs >= 120) {
        this.lastMeteorCommitMs = now
        this.onSetSkyDisplay('meteorZhr', zhr)
      }
      return
    }
    this.meteorDragging = false
    this.meteorDragPos = pos
    this.lastMeteorCommitMs = now
    this.onSetSkyDisplay('meteorZhr', zhr)
  }

  private commitToneSlider(setting: string, value: number, mode: SliderChangeMode): void {
    const now = Date.now()
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      if (setting === 'toneDisplayAdaptation') this.layerViewStore.toneDisplayAdaptationLuminance = Math.round(value)
      else if (setting === 'toneMaxLuminance') this.layerViewStore.toneMaxDisplayLuminance = Math.round(value)
      else if (setting === 'toneGamma') this.layerViewStore.toneDisplayGamma = Math.round(value * 100) / 100
      else if (setting === 'absoluteStarScale') this.layerViewStore.starBrightnessScale = value
      if (now - this.lastToneCommitMs >= 90) {
        this.lastToneCommitMs = now
        this.onSetSkyDisplay(setting, value)
      }
      return
    }
    this.lastToneCommitMs = now
    this.onSetSkyDisplay(setting, value)
  }

  private applyTonePreset(preset: TonePresetOption): void {
    this.onSetSkyDisplay('toneDisplayAdaptation', preset.lda)
    this.onSetSkyDisplay('toneMaxLuminance', preset.maxdL)
    this.onSetSkyDisplay('toneGamma', preset.gamma)
    this.onSetSkyDisplay('toneUseTmGamma', true)
  }

  private isTonePresetActive(preset: TonePresetOption): boolean {
    return Math.abs(this.layerViewStore.toneDisplayAdaptationLuminance - preset.lda) <= 1 &&
      Math.abs(this.layerViewStore.toneMaxDisplayLuminance - preset.maxdL) <= 2 &&
      Math.abs(this.layerViewStore.toneDisplayGamma - preset.gamma) <= 0.03
  }

  private meteorHintText(): string {
    if (this.layerViewStore.meteorDrawSuppression === 'daylight-too-bright') {
      return '当前为白天，偶发流星被天光淹没；可调至夜间或点击「试看流星」立即体验效果'
    }
    if (this.layerViewStore.meteorGenSuppression === 'real-time-speed-required') {
      return '当前时间暂停或变速中，恢复 1× 实时流速后将按频率出现偶发流星'
    }
    return '含镁绿、钠金、冰蓝紫与火流星余迹；实际可见数受夜空暗度与地平高度影响'
  }

  private starBrightnessPercent(): number {
    return Math.round(absoluteScaleToStarBrightness(this.layerViewStore.starBrightnessScale) * 100)
  }

  private isStarBrightnessOffset(): boolean {
    return Math.abs(this.layerViewStore.starBrightnessScale - 1.0) > 0.06
  }

  build() {
    Column({ space: 0 }) {
      AtmosphereGroundSection({
        layerStore: this.layerStore,
        onSetSkyDisplay: (setting: string, value: boolean | number) => { this.onSetSkyDisplay(setting, value) }
      })
      // ── 恒星：恒星本体与其渲染特征 ──
      Text('恒星').fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 2, bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0530'), isOn: this.layerStore.stars, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Stars', '', value) } })
      // 星等限制
      Row() {
        Text(I18n.t('i0300')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
        Slider({
          value: this.layerViewStore.starMagLimit,
          min: 2.0,
          max: this.layerViewStore.starMagLimitMax,
          step: 0.5,
          style: SliderStyle.OutSet
        })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .trackColor(this.c.softStrong)
          .showSteps(false)
          .showTips(false)
          .layoutWeight(1)
          .onChange((value: number) => {
            this.onStarMagLimit(Math.round(value * 10) / 10)
          })
        Text(this.layerViewStore.starMagLimit.toFixed(1))
          .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).width(40).textAlign(TextAlign.End)
      }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
        .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
      LayerSwitchRow({ label: '亮星光晕', isOn: this.layerStore.bigStarHalo, onToggle: (value: boolean) => { this.onToggleLayer('bigStarHalo', 'setSkyDisplayBigStarHalo', value) } })
      LayerSwitchRow({ label: '星芒效果', isOn: this.layerStore.starSpiky, onToggle: (value: boolean) => { this.onToggleLayer('starSpiky', 'setSkyDisplayStarSpiky', value) } })
      LayerSwitchRow({ label: '星星闪烁', isOn: this.layerStore.starTwinkle, onToggle: (value: boolean) => { this.onToggleLayer('starTwinkle', 'setSkyDisplayStarTwinkle', value) } })
      if (this.layerStore.starTwinkle) {
        LayerSwitchRow({ label: '无大气时保持闪烁', isOn: this.layerStore.forcedStarTwinkle, onToggle: (value: boolean) => { this.onToggleLayer('forcedStarTwinkle', 'setSkyDisplayForcedTwinkle', value) } })
      }
      // ── 天空：天空背景与天象 ──
      Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 5, bottom: 8 })
      Text('天空').fontSize(11).fontColor(this.c.sub).width('100%').margin({ bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0531'), isOn: this.layerStore.milkyWay, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_MilkyWay', '', value) } })
      // 银河亮度
      Row() {
        Text(I18n.t('i0212')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
        // 与光污染等级行同版式：标题在左，中间留白，步进控件整体靠右。
        Row({ space: 6 }) {
          Button('−').fontSize(15).fontColor(this.c.text).backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_CONTROL).width(40).height(30).padding({ left: 0, right: 0 })
            .enabled(this.layerViewStore.milkyWayBright > 0)
            .onClick(() => {
              if (this.layerViewStore.milkyWayBright > 0) {
                this.onMilkyWayBright(this.layerViewStore.milkyWayBright - 1)
              }
            })
          Text(this.layerViewStore.milkyWayBright.toString())
            .fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text)
            .width(40).textAlign(TextAlign.Center)
          Button('+').fontSize(15).fontColor(this.c.text).backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_CONTROL).width(40).height(30).padding({ left: 0, right: 0 })
            .enabled(this.layerViewStore.milkyWayBright < 6)
            .onClick(() => {
              if (this.layerViewStore.milkyWayBright < 6) {
                this.onMilkyWayBright(this.layerViewStore.milkyWayBright + 1)
              }
            })
        }.layoutWeight(1).justifyContent(FlexAlign.End)
      }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
        .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
      LayerSwitchRow({ label: I18n.t('s0532'), isOn: this.layerStore.starLabels, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Stars_Labels', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0308'), isOn: this.layerStore.meteors, onToggle: (value: boolean) => { this.onToggleLayer('setMeteors', 'setMeteors', value) } })
      if (this.layerStore.meteors) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text('理论流星率')
              .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text)
            Text(formatMeteorZhrLabel(this.currentMeteorDisplayZhr()))
              .fontSize(panelFontSize(12, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.accent)
              .layoutWeight(1)
            Button('✦ 试看流星')
              .fontSize(11).fontColor(this.c.accent).height(26)
              .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
              .padding({ left: 9, right: 9 })
              .onClick(() => { this.onSetSkyDisplay('meteorPreview', 1) })
          }.width('100%').alignItems(VerticalAlign.Center)
          Slider({
            value: this.currentMeteorPos(),
            min: 0,
            max: 100,
            step: 1,
            style: SliderStyle.OutSet
          })
            .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
            .width('100%')
            .trackColor(this.c.softStrong)
            .selectedColor(this.c.accent)
            .showSteps(false)
            .showTips(false)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.commitMeteorSlider(value, mode)
            })
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
            ForEach(METEOR_ZHR_PRESETS, (preset: MeteorPresetOption) => {
              Text(preset.label)
                .fontSize(11)
                .fontWeight(this.layerViewStore.meteorZhr === preset.zhr ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.layerViewStore.meteorZhr === preset.zhr ? this.c.text : this.c.chipInactiveText)
                .backgroundColor(this.layerViewStore.meteorZhr === preset.zhr ? this.c.chipActiveBg : this.c.chipInactiveBg)
                .border({
                  width: 1,
                  color: this.layerViewStore.meteorZhr === preset.zhr ? this.c.chipActiveBorder : this.c.chipInactiveBorder
                })
                .borderRadius(UI_RADIUS_TAG)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .onClick(() => {
                  this.meteorDragging = false
                  this.onSetSkyDisplay('meteorZhr', preset.zhr)
                })
            }, (preset: MeteorPresetOption) => preset.label)
          }.width('100%')
          Text(this.meteorHintText())
            .fontSize(10)
            .fontColor(this.layerViewStore.meteorDrawSuppression === 'daylight-too-bright' ||
              this.layerViewStore.meteorGenSuppression === 'real-time-speed-required'
              ? this.c.accent : this.c.sub)
            .width('100%')
        }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
      }
      LayerSwitchRow({ label: '黄道光', isOn: this.layerStore.zodiacalLight, onToggle: (value: boolean) => { this.onToggleLayer('zodiacalLight', 'setSkyDisplayZodiacalLight', value) } })
      if (this.layerStore.zodiacalLight) {
        Row() {
          Text('黄道光亮度').fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
          Slider({ value: this.layerViewStore.zodiacalIntensity, min: 0, max: 5, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.softStrong).showSteps(false)
            .onChange((value: number) => { this.onSetSkyDisplay('zodiacalIntensity', Math.round(value * 10) / 10) })
          Text(this.layerViewStore.zodiacalIntensity.toFixed(1))
            .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).width(38).textAlign(TextAlign.End)
        }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
          .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
      }
      LayerSwitchRow({ label: I18n.t('s0300'), isOn: this.nightModeOn, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Night_Mode', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0309'), isOn: this.layerStore.flipHoriz, onToggle: (value: boolean) => { this.onToggleLayer('actionHorizontal_Flip', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0310'), isOn: this.layerStore.flipVert, onToggle: (value: boolean) => { this.onToggleLayer('actionVertical_Flip', '', value) } })
      // ── 观测条件：大气、地景与观测几何 ──
      Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 5, bottom: 8 })
      Text('观测条件').fontSize(11).fontColor(this.c.sub).width('100%').margin({ bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0305'), isOn: this.layerStore.atmosphere, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Atmosphere', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0306'), isOn: this.layerStore.ground, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ground', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0307'), isOn: this.layerStore.fogEffect, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Fog', '', value) } })
      Row({ space: 8 }) {
        Text('光污染等级').fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
        // 标题在左，中间留白，步进控件整体靠右（与银河亮度行一致）。
        Row({ space: 6 }) {
          Button('−').fontSize(15).fontColor(this.c.text).backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_CONTROL).width(40).height(30).padding({ left: 0, right: 0 })
            .enabled(this.layerViewStore.bortleScale > 1)
            .onClick(() => { this.onSetSkyDisplay('bortleScale', Math.max(1, this.layerViewStore.bortleScale - 1)) })
          Text('Bortle ' + this.layerViewStore.bortleScale)
            .fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text)
            .width(72).textAlign(TextAlign.Center)
          Button('+').fontSize(15).fontColor(this.c.text).backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_CONTROL).width(40).height(30).padding({ left: 0, right: 0 })
            .enabled(this.layerViewStore.bortleScale < 9)
            .onClick(() => { this.onSetSkyDisplay('bortleScale', Math.min(9, this.layerViewStore.bortleScale + 1)) })
        }.layoutWeight(1).justifyContent(FlexAlign.End)
      }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
        .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
      LayerSwitchRow({ label: '人眼动态视觉调适', isOn: this.layerStore.luminanceAdaptation, onToggle: (value: boolean) => { this.onToggleLayer('luminanceAdaptation', 'setSkyDisplayLuminanceAdaptation', value) } })
      // ── 色调映射与星点亮度调和（折叠高级抽屉） ──
      Row() {
        Column({ space: 2 }) {
          Row({ space: 4 }) {
            Text('色调映射与亮度调和')
              .fontSize(panelFontSize(13, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.text)
            InfoTipButton({
              title: '色调映射与亮度调和',
              tip: '三层互不冲突：①「现实星等」决定白天/光污染下哪些暗星可见；②「双指星点亮度」仅调节已见恒星的显示倍率（重开现实星等自动归位 1.0×）；③「色调映射」控制整体天穹的暗部细节、对比度与屏幕伽马曲线。'
            })
          }.alignItems(VerticalAlign.Center)
          Text('Lda ' + this.layerViewStore.toneDisplayAdaptationLuminance.toFixed(0) +
            ' · γ ' + this.layerViewStore.toneDisplayGamma.toFixed(2) +
            ' · 星点 ' + this.layerViewStore.starBrightnessScale.toFixed(2) + '×')
            .fontSize(10).fontColor(this.c.sub).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.layerViewStore.toneMappingExpanded ? '收起' : '微调')
          .fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.c.accent)
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      }.width('100%').padding({ left: 10, right: 8, top: 8, bottom: 8 })
        .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerViewStore.toneMappingExpanded ? 4 : 6 })
        .onClick(() => {
          this.layerViewStore.toneMappingExpanded = !this.layerViewStore.toneMappingExpanded
        })
      if (this.layerViewStore.toneMappingExpanded) {
        Column({ space: 6 }) {
          // 星点亮度与现实星等调和条（与天穹双指上下滑双向同步）
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text('星点亮度（双指同步）')
                .fontSize(11).fontColor(this.c.text).layoutWeight(1)
              Text(this.starBrightnessPercent().toString() + '% · ' + this.layerViewStore.starBrightnessScale.toFixed(2) + '×')
                .fontSize(11).fontColor(this.isStarBrightnessOffset() ? this.c.accent : this.c.sub)
              if (this.isStarBrightnessOffset()) {
                Button('归位 1.0×')
                  .fontSize(10).fontColor(this.c.accent).height(22)
                  .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).padding({ left: 7, right: 7 })
                  .onClick(() => { this.onSetSkyDisplay('starBrightnessReset', 1) })
              }
            }.width('100%').alignItems(VerticalAlign.Center)
            Slider({
              value: this.starBrightnessPercent(),
              min: 0,
              max: 100,
              step: 1,
              style: SliderStyle.OutSet
            })
              .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
              .width('100%').trackColor(this.c.softStrong).selectedColor(this.c.accent)
              .showSteps(false).showTips(false)
              .onChange((value: number, mode: SliderChangeMode) => {
                const scale = Math.round(starBrightnessToAbsoluteScale(value / 100) * 1000) / 1000
                this.commitToneSlider('absoluteStarScale', scale, mode)
              })
            Text(this.layerStore.realisticStarVisibility
              ? (this.isStarBrightnessOffset()
                ? '现实星等开启中，当前星点已手动偏移；重新开启现实星等或点「归位 1.0×」可恢复物理基准'
                : '现实星等物理基准（1.0×）生效中：双指上下滑可临时微调视觉亮度')
              : '教学常亮模式：白天也可自由调亮恒星与深空，与双指上下滑实时联动')
              .fontSize(10)
              .fontColor(this.layerStore.realisticStarVisibility && this.isStarBrightnessOffset() ? this.c.accent : this.c.sub)
              .width('100%')
          }.width('100%').padding(8).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)

          // 一键色调预设
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
            ForEach(TONE_MAPPING_PRESETS, (preset: TonePresetOption) => {
              Text(preset.label)
                .fontSize(11)
                .fontWeight(this.isTonePresetActive(preset) ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.isTonePresetActive(preset) ? this.c.text : this.c.chipInactiveText)
                .backgroundColor(this.isTonePresetActive(preset) ? this.c.chipActiveBg : this.c.chipInactiveBg)
                .border({
                  width: 1,
                  color: this.isTonePresetActive(preset) ? this.c.chipActiveBorder : this.c.chipInactiveBorder
                })
                .borderRadius(UI_RADIUS_TAG)
                .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                .onClick(() => { this.applyTonePreset(preset) })
            }, (preset: TonePresetOption) => preset.label)
          }.width('100%')

          // 显示适应亮度 Lda (10..100 cd/m²)
          Column({ space: 2 }) {
            Row({ space: 4 }) {
              Text('显示适应亮度 Lda').fontSize(11).fontColor(this.c.text)
              InfoTipButton({
                title: '显示适应亮度 Lda',
                tip: '模拟观看屏幕时的环境亮度（单位 cd/m²）。调低可提亮暗弱银河与星云细节；调高则压暗天穹背景、突出亮星。默认 50。'
              })
              Blank()
              Text(this.layerViewStore.toneDisplayAdaptationLuminance.toFixed(0) + ' cd/m²')
                .fontSize(11).fontColor(this.c.sub)
            }.width('100%').alignItems(VerticalAlign.Center)
            Slider({
              value: this.layerViewStore.toneDisplayAdaptationLuminance,
              min: 10,
              max: 100,
              step: 1,
              style: SliderStyle.OutSet
            })
              .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
              .width('100%').trackColor(this.c.softStrong).selectedColor(this.c.accent)
              .showSteps(false).showTips(false)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.commitToneSlider('toneDisplayAdaptation', Math.round(value), mode)
              })
          }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 4 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)

          // 屏幕峰值亮度 maxdL (40..300 cd/m²)
          Column({ space: 2 }) {
            Row({ space: 4 }) {
              Text('屏幕峰值亮度 maxdL').fontSize(11).fontColor(this.c.text)
              InfoTipButton({
                title: '屏幕峰值亮度 maxdL',
                tip: '色调度量对应的参考屏幕最大亮度。调低整体更明亮饱和；调高则保留更多高光层次，减少亮星与银河核心过曝。默认 100。'
              })
              Blank()
              Text(this.layerViewStore.toneMaxDisplayLuminance.toFixed(0) + ' cd/m²')
                .fontSize(11).fontColor(this.c.sub)
            }.width('100%').alignItems(VerticalAlign.Center)
            Slider({
              value: this.layerViewStore.toneMaxDisplayLuminance,
              min: 40,
              max: 300,
              step: 5,
              style: SliderStyle.OutSet
            })
              .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
              .width('100%').trackColor(this.c.softStrong).selectedColor(this.c.accent)
              .showSteps(false).showTips(false)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.commitToneSlider('toneMaxLuminance', Math.round(value), mode)
              })
          }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 4 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)

          // 色调伽马 γ (1.40..3.00)
          Column({ space: 2 }) {
            Row({ space: 4 }) {
              Text('色调伽马 γ').fontSize(11).fontColor(this.c.text)
              InfoTipButton({
                title: '色调伽马 γ',
                tip: '控制天穹中间调与暗部反差。数值越小暗部越柔和通透，数值越大背景越深邃、亮暗对比越强。默认 2.22。'
              })
              Blank()
              Text(this.layerViewStore.toneDisplayGamma.toFixed(2))
                .fontSize(11).fontColor(this.c.sub)
            }.width('100%').alignItems(VerticalAlign.Center)
            Slider({
              value: this.layerViewStore.toneDisplayGamma,
              min: 1.4,
              max: 3.0,
              step: 0.05,
              style: SliderStyle.OutSet
            })
              .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
              .width('100%').trackColor(this.c.softStrong).selectedColor(this.c.accent)
              .showSteps(false).showTips(false)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.commitToneSlider('toneGamma', Math.round(value * 100) / 100, mode)
              })
          }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 4 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)

          // 伽马曲线开关 + 恢复默认
          Row({ space: 8 }) {
            Text('启用色调伽马曲线').fontSize(11).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.toneUseTmGamma }).width(40).height(22)
              .onChange((enabled: boolean) => { this.onSetSkyDisplay('toneUseTmGamma', enabled) })
          }.height(36).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)

          Row({ space: 8 }) {
            Button('恢复默认色调')
              .fontSize(11).fontColor(this.c.text).height(30).layoutWeight(1)
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onSetSkyDisplay('toneReset', 1) })
            Button('同时重置星点 1.0×')
              .fontSize(11).fontColor(this.c.accent).height(30).layoutWeight(1)
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => {
                this.onSetSkyDisplay('toneReset', 1)
                this.onSetSkyDisplay('starBrightnessReset', 1)
              })
          }.width('100%')
        }.width('100%').padding(8).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      }
      // 大气折射（气压 / 气温 / 消光）自时间面板迁入
      ObservationAidBlock({
        refractionOn: this.refractionOn,
        atmoPressure: this.atmoPressure,
        atmoTemperature: this.atmoTemperature,
        atmoExtinction: this.atmoExtinction,
        altitude: this.observerAltitude,
        earthObserver: this.earthObserver,
        onAtmosphere: (pressure: number, temperature: number, extinction: number) => { this.onAtmosphere(pressure, temperature, extinction) }
      })
    }.width('100%')
  }
}

// 太阳系天体。
@Component
export struct LayerSsoTab {
  @ObjectLink layerStore: LayerStore
  @ObjectLink layerViewStore: LayerViewStore
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop expandedLayout: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  private lastGrsCommitMs: number = 0
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onSetSkyDisplay: (setting: string, value: boolean | number) => void = () => {}
  onSetOrbitFlag: (setting: string, enabled: boolean) => void = () => {}
  onSetOrbitThickness: (value: number) => void = () => {}
  onSetOrbitColorStyle: (index: number) => void = () => {}
  onLoadOrbitSettings: () => void = () => {}
  onSetTrailFlag: (setting: string, enabled: boolean) => void = () => {}
  onSetTrailNumber: (setting: string, value: number) => void = () => {}
  onLoadTrailSettings: () => void = () => {}
  onApplyTrailColor: () => void = () => {}
  onTriggerAction: (actionId: string) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private orbitColorStyleIndex(): number {
    const style = this.layerViewStore.orbitColorStyle
    if (style === 'groups') return 1
    if (style === 'major_planets') return 2
    if (style === 'major_planets_minor_types') return 3
    return 0
  }

  build() {
    Column({ space: 0 }) {
      Text('基础显示').fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 2, bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0311'), isOn: this.layerStore.planets, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0312'), isOn: this.layerStore.planetOrbits, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_Orbits', '', value) } })
      if (this.layerStore.planetOrbits) {
        Row() {
          Column({ space: 1 }) {
            Text('轨道显示方式').fontSize(12).fontColor(this.c.sub).width('100%')
            Text('控制轨道显示对象、线条和配色分类').fontSize(10).fontColor(this.c.sub).width('100%')
          }.layoutWeight(1)
          Button(this.layerViewStore.orbitSettingsExpanded ? '收起' : '设置').fontSize(10).fontColor(this.c.accent).height(28)
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).padding({ left: 9, right: 9 })
            .onClick(() => {
              this.layerViewStore.orbitSettingsExpanded = !this.layerViewStore.orbitSettingsExpanded
              if (this.layerViewStore.orbitSettingsExpanded) this.onLoadOrbitSettings()
            })
        }.width('100%').padding({ left: 2, right: 2, top: 3, bottom: 4 }).margin({ bottom: this.layerViewStore.orbitSettingsExpanded ? 4 : 8 })
        if (this.layerViewStore.orbitSettingsExpanded) {
          Column({ space: 4 }) {
            Row() {
              Column({ space: 1 }) {
                Text('只显示当前选中天体').fontSize(11).fontColor(this.c.text).width('100%')
                Text('关闭后显示所有符合条件的轨道').fontSize(10).fontColor(this.c.sub).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitIsolated }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('isolated', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Column({ space: 1 }) {
                Text('始终显示八大行星轨道').fontSize(11).fontColor(this.c.text).width('100%')
                Text('可与当前选中的小天体轨道同时显示').fontSize(10).fontColor(this.c.sub).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitMajorPlanets }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('majorPlanets', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Column({ space: 1 }) {
                Text('仅显示行星轨道').fontSize(11).fontColor(this.c.text).width('100%')
                Text('隐藏小行星、彗星等其他天体轨道').fontSize(10).fontColor(this.c.sub).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitPlanetsOnly }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('planetsOnly', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Column({ space: 1 }) {
                Text('包含卫星轨道').fontSize(11).fontColor(this.c.text).width('100%')
                Text('显示行星周围卫星的轨道').fontSize(10).fontColor(this.c.sub).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitWithMoons }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('withMoons', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Column({ space: 1 }) {
                Text('轨道保持显示').fontSize(11).fontColor(this.c.text).width('100%')
                Text('天体移出屏幕后仍持续绘制轨道').fontSize(10).fontColor(this.c.sub).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitPermanent }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('permanent', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Text('轨道线宽').fontSize(11).fontColor(this.c.text).width(64)
              Text(this.layerViewStore.orbitThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(34).textAlign(TextAlign.End)
              Slider({ value: this.layerViewStore.orbitThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .layoutWeight(1).trackColor(this.c.softStrong).showSteps(false).showTips(false)
                .onChange((value: number) => { this.onSetOrbitThickness(value) })
            }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            Row({ space: 8 }) {
              Text('轨道配色').fontSize(11).fontColor(this.c.text).width(64)
              Select([{ value: '统一颜色' }, { value: '按天体分组' }, { value: '按八大行星' }, { value: '行星与小天体分类' }])
                .selected(this.orbitColorStyleIndex()).value('轨道配色').height(30).layoutWeight(1)
                .onSelect((index: number) => { this.onSetOrbitColorStyle(index) })
            }.height(34).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
          }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
        }
      }
      LayerSwitchRow({ label: I18n.t('s0314'), isOn: this.layerStore.planetHints, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_Hints', '', value) } })
      Text('高级标记').fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 8, bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0313'), isOn: this.layerStore.planetTrails, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_Trails', '', value) } })
      if (this.layerStore.planetTrails) {
        Row() {
          Column({ space: 1 }) {
            Text('轨迹显示方式').fontSize(12).fontColor(this.c.sub).width('100%')
            Text('控制保留对象、历史跨度、线宽与颜色').fontSize(10).fontColor(this.c.sub).width('100%')
          }.layoutWeight(1)
          Button(this.layerViewStore.trailSettingsExpanded ? '收起' : '设置').fontSize(10).fontColor(this.c.accent).height(28)
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).padding({ left: 9, right: 9 })
            .onClick(() => {
              this.layerViewStore.trailSettingsExpanded = !this.layerViewStore.trailSettingsExpanded
              if (this.layerViewStore.trailSettingsExpanded) this.onLoadTrailSettings()
            })
        }.width('100%').padding({ left: 2, right: 2, top: 3, bottom: 4 }).margin({ bottom: this.layerViewStore.trailSettingsExpanded ? 4 : 8 })
        if (this.layerViewStore.trailSettingsExpanded) {
          Column({ space: 4 }) {
            Row() {
              Column({ space: 1 }) {
                Text('仅保留最近选中天体').fontSize(11).fontColor(this.c.text).width('100%')
                Text('关闭后显示当前可见的全部太阳系天体轨迹').fontSize(10).fontColor(this.c.sub).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.trailIsolated }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetTrailFlag('isolated', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            if (this.layerViewStore.trailIsolated) {
              Row() {
                Text('保留选中对象').fontSize(11).fontColor(this.c.text).width(84)
                Text(this.layerViewStore.trailSelectionCount.toFixed(0) + ' 个').fontSize(11).fontColor(this.c.sub).width(34).textAlign(TextAlign.End)
                Slider({ value: this.layerViewStore.trailSelectionCount, min: 1, max: 5, step: 1, style: SliderStyle.OutSet })
                  .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                  .layoutWeight(1).trackColor(this.c.softStrong).showSteps(false).showTips(false)
                  .onChange((value: number) => { this.onSetTrailNumber('selectionCount', value) })
              }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            }
            Row() {
              Text('历史跨度').fontSize(11).fontColor(this.c.text).width(72)
              Text(this.layerViewStore.trailYears.toFixed(0) + ' 年').fontSize(11).fontColor(this.c.sub).width(42).textAlign(TextAlign.End)
              Slider({ value: this.layerViewStore.trailYears, min: 1, max: 250, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .layoutWeight(1).trackColor(this.c.softStrong).showSteps(false).showTips(false)
                .onChange((value: number) => { this.onSetTrailNumber('years', value) })
            }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Text('轨迹线宽').fontSize(11).fontColor(this.c.text).width(72)
              Text(this.layerViewStore.trailThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(42).textAlign(TextAlign.End)
              Slider({ value: this.layerViewStore.trailThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .layoutWeight(1).trackColor(this.c.softStrong).showSteps(false).showTips(false)
                .onChange((value: number) => { this.onSetTrailNumber('thickness', value) })
            }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
            Row({ space: 8 }) {
              Text('轨迹颜色').fontSize(11).fontColor(this.c.text).width(64)
              TextInput({ text: this.layerViewStore.trailColorInput, placeholder: '#RRGGBB' })
                .fontSize(11).fontColor(this.c.text).placeholderColor(this.c.sub).height(30).layoutWeight(1)
                .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).padding({ left: 8, right: 8 })
                .onChange((value: string) => { this.layerViewStore.trailColorInput = value })
              Button('应用').fontSize(10).fontColor(this.c.accent).height(28).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                .padding({ left: 9, right: 9 }).onClick(() => { this.onApplyTrailColor() })
            }.height(34).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)
          }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
        }
      }
      LayerSwitchRow({ label: I18n.t('s0318'), isOn: this.layerStore.minorBodyMarkers, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_ShowMinorBodyMarkers', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0319'), isOn: this.layerStore.planetNomenclature, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_Nomenclature', '', value) } })
      if (this.expandedLayout) {
        Text('视直径增强').fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 8, bottom: 6 }).padding({ left: 2 })
        LayerSwitchRow({ label: I18n.t('s0315'), isOn: this.layerStore.enlargeMoon, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_EnlargeMoon', '', value) } })
        LayerSwitchRow({ label: I18n.t('s0316'), isOn: this.layerStore.enlargePlanets, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_EnlargePlanets', '', value) } })
        LayerSwitchRow({ label: I18n.t('s0317'), isOn: this.layerStore.enlargeSun, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_EnlargeSun', '', value) } })
      }
      // ── 木星大红斑校准 (GRS) ──
      Text('观测校准').fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 8, bottom: 6 }).padding({ left: 2 })
      Row() {
        Column({ space: 2 }) {
          Row({ space: 4 }) {
            Text('木星大红斑校准 (GRS)')
              .fontSize(panelFontSize(13, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.text)
            InfoTipButton({
              title: '木星大红斑校准 (GRS)',
              tip: '木星大红斑在系统 II 经度上每年都在缓慢漂移。高倍望远镜观测大红斑中天前，可按最新观测公报输入参考经度、年漂移率与参考日期，以精确对齐实时盘面位置。'
            })
          }.alignItems(VerticalAlign.Center)
          Text('系统 II ' + this.layerViewStore.grsLongitude.toString() + '° · 漂移 ' +
            (this.layerViewStore.grsDrift >= 0 ? '+' : '') + this.layerViewStore.grsDrift.toFixed(1) + '°/年 · ' +
            julianDayToIsoDate(this.layerViewStore.grsJd))
            .fontSize(10).fontColor(this.c.sub).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.layerViewStore.grsSettingsExpanded ? '收起' : '校准')
          .fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.c.accent)
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      }.width('100%').padding({ left: 10, right: 8, top: 8, bottom: 8 })
        .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerViewStore.grsSettingsExpanded ? 4 : 8 })
        .onClick(() => {
          this.layerViewStore.grsSettingsExpanded = !this.layerViewStore.grsSettingsExpanded
        })
      if (this.layerViewStore.grsSettingsExpanded) {
        Column({ space: 6 }) {
          // 系统 II 参考经度 (0°..360°)
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text('系统 II 参考经度').fontSize(11).fontColor(this.c.text).layoutWeight(1)
              Button('−1°').fontSize(10).fontColor(this.c.text).height(24)
                .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).padding({ left: 7, right: 7 })
                .onClick(() => {
                  const next = ((this.layerViewStore.grsLongitude - 1) % 360 + 360) % 360
                  this.onSetSkyDisplay('grsLongitude', next)
                })
              Text(this.layerViewStore.grsLongitude.toString() + '°')
                .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.accent).width(38).textAlign(TextAlign.Center)
              Button('+1°').fontSize(10).fontColor(this.c.text).height(24)
                .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).padding({ left: 7, right: 7 })
                .onClick(() => {
                  const next = (this.layerViewStore.grsLongitude + 1) % 360
                  this.onSetSkyDisplay('grsLongitude', next)
                })
            }.width('100%').alignItems(VerticalAlign.Center)
            Slider({
              value: this.layerViewStore.grsLongitude,
              min: 0,
              max: 359,
              step: 1,
              style: SliderStyle.OutSet
            })
              .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
              .width('100%').trackColor(this.c.softStrong).selectedColor(this.c.accent)
              .showSteps(false).showTips(false)
              .onChange((value: number, mode: SliderChangeMode) => {
                const lon = ((Math.round(value) % 360) + 360) % 360
                const now = Date.now()
                this.layerViewStore.grsLongitude = lon
                if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                  if (now - this.lastGrsCommitMs >= 90) {
                    this.lastGrsCommitMs = now
                    this.onSetSkyDisplay('grsLongitude', lon)
                  }
                } else {
                  this.lastGrsCommitMs = now
                  this.onSetSkyDisplay('grsLongitude', lon)
                }
              })
          }.width('100%').padding(8).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)

          // 年漂移率 (°/年)
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text('年漂移率').fontSize(11).fontColor(this.c.text).layoutWeight(1)
              Button('−0.5').fontSize(10).fontColor(this.c.text).height(24)
                .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).padding({ left: 7, right: 7 })
                .onClick(() => {
                  const next = Math.max(-60, Math.round((this.layerViewStore.grsDrift - 0.5) * 10) / 10)
                  this.onSetSkyDisplay('grsDrift', next)
                })
              Text((this.layerViewStore.grsDrift >= 0 ? '+' : '') + this.layerViewStore.grsDrift.toFixed(1) + '°/年')
                .fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.c.accent).width(58).textAlign(TextAlign.Center)
              Button('+0.5').fontSize(10).fontColor(this.c.text).height(24)
                .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).padding({ left: 7, right: 7 })
                .onClick(() => {
                  const next = Math.min(60, Math.round((this.layerViewStore.grsDrift + 0.5) * 10) / 10)
                  this.onSetSkyDisplay('grsDrift', next)
                })
            }.width('100%').alignItems(VerticalAlign.Center)
            Slider({
              value: Math.max(-60, Math.min(60, this.layerViewStore.grsDrift)),
              min: -60,
              max: 60,
              step: 0.5,
              style: SliderStyle.OutSet
            })
              .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
              .width('100%').trackColor(this.c.softStrong).selectedColor(this.c.accent)
              .showSteps(false).showTips(false)
              .onChange((value: number, mode: SliderChangeMode) => {
                const drift = Math.round(value * 10) / 10
                const now = Date.now()
                this.layerViewStore.grsDrift = drift
                if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                  if (now - this.lastGrsCommitMs >= 90) {
                    this.lastGrsCommitMs = now
                    this.onSetSkyDisplay('grsDrift', drift)
                  }
                } else {
                  this.lastGrsCommitMs = now
                  this.onSetSkyDisplay('grsDrift', drift)
                }
              })
          }.width('100%').padding(8).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)

          // 参考历元日期 (JD)
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('参考历元日期').fontSize(11).fontColor(this.c.text)
              Blank()
              Text(julianDayToIsoDate(this.layerViewStore.grsJd) + ' (JD ' + this.layerViewStore.grsJd.toFixed(1) + ')')
                .fontSize(11).fontColor(this.c.sub)
            }.width('100%')
            Row({ space: 6 }) {
              Button('−30天').fontSize(10).fontColor(this.c.text).height(26).layoutWeight(1)
                .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSetSkyDisplay('grsJd', this.layerViewStore.grsJd - 30) })
              Button('+30天').fontSize(10).fontColor(this.c.text).height(26).layoutWeight(1)
                .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSetSkyDisplay('grsJd', this.layerViewStore.grsJd + 30) })
              Button('设为今日').fontSize(10).fontColor(this.c.accent).height(26).layoutWeight(1)
                .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSetSkyDisplay('grsJd', currentUtcMidnightJd()) })
            }.width('100%')
          }.width('100%').padding(8).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL)

          Button('恢复官方默认（46° · +15.0°/年 · 2023-10-01）')
            .fontSize(11).fontColor(this.c.text).height(30).width('100%')
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onSetSkyDisplay('grsReset', 1) })
        }.width('100%').padding(8).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      }
      Row() {
        Text(I18n.t('i0281')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
        Button(I18n.t('i0282')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .backgroundColor(this.c.softStrong)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
          .onClick(() => { this.onTriggerAction('actionShow_Planets_Trails_Reset') })
      }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
        .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
    }.width('100%')
  }
}

// 深空天体。
@Component
export struct LayerDsoTab {
  @ObjectLink layerStore: LayerStore
  @ObjectLink layerViewStore: LayerViewStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onLoadDsoSettings: () => void = () => {}
  onSetDsoSetting: (setting: string, value: boolean | number) => void = () => {}
  onSetDsoCatalogMask: (mask: number) => void = () => {}
  onSetDsoTypeMask: (mask: number) => void = () => {}

  aboutToAppear(): void {
    this.onLoadDsoSettings()
  }

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 0 }) {
      Text('显示内容').fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 2, bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0320'), isOn: this.layerStore.nebulae, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Nebulas', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0322'), isOn: this.layerStore.dsoTextures, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_DSO_Textures', '', value) } })
      DsoSettingsSection({
        layerViewStore: this.layerViewStore,
        onSetSetting: (setting: string, value: boolean | number) => { this.onSetDsoSetting(setting, value) },
        onSetCatalogMask: (mask: number) => { this.onSetDsoCatalogMask(mask) },
        onSetTypeMask: (mask: number) => { this.onSetDsoTypeMask(mask) }
      })
    }.width('100%')
  }
}

// 标记与网格。
@Component
export struct LayerMarkingsTab {
  @ObjectLink layerStore: LayerStore
  @ObjectLink layerViewStore: LayerViewStore
  @ObjectLink overlayStore: OverlayStore
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onSetFovMarker: (setting: string, value: number) => void = () => {}
  onToggleViewCoordinates: (visible: boolean) => void = () => {}
  onSelectViewCoordinateFamily: (family: string) => void = () => {}
  onSelectViewEquatorialEpoch: (epoch: string) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 0 }) {
      Text(I18n.t('view_orientation_marks')).fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 4, bottom: 2 }).padding({ left: 2 })
      Text(I18n.t('view_orientation_marks_hint')).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2)
        .padding({ left: 2, right: 2 }).margin({ bottom: 5 })
      LayerSwitchRow({ label: I18n.t('s0533'), isOn: this.layerStore.cardinalPoints, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Cardinal_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0342'), isOn: this.layerStore.compassMarks, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Compass_Marks', '', value) } })
      // 基础网格
      Text(I18n.t('i0197')).fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 4, bottom: 2 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0538'), isOn: this.layerStore.gridlinesMaster, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Gridlines', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0323'), isOn: this.layerStore.equatorialGrid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Equatorial_Grid', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0324'), isOn: this.layerStore.azimuthGrid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Azimuthal_Grid', '', value) } })
      // 特殊线
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.border)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0198')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2 })
        .height(18).width('100%')
      LayerSwitchRow({ label: I18n.t('s0325'), isOn: this.layerStore.equatorLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Equator_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0326'), isOn: this.layerStore.eclipticLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ecliptic_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0327'), isOn: this.layerStore.meridianLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Meridian_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0328'), isOn: this.layerStore.horizonLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Horizon_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0329'), isOn: this.layerStore.galacticEquator, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Galactic_Equator_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0330'), isOn: this.layerStore.supergalacticEq, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Supergalactic_Equator_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0331'), isOn: this.layerStore.galacticGrid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Galactic_Grid', '', value) } })
      // J2000 线
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.border)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0199')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2 })
        .height(18).width('100%')
      LayerSwitchRow({ label: I18n.t('s0332'), isOn: this.layerStore.equJ2000Line, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Equator_J2000_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0333'), isOn: this.layerStore.eclJ2000Line, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ecliptic_J2000_Line', '', value) } })
      // 点标记
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.border)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0200')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2 })
        .height(18).width('100%')
      LayerSwitchRow({ label: I18n.t('s0334'), isOn: this.layerStore.celestialPoles, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Celestial_Poles', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0335'), isOn: this.layerStore.eclipticPoles, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ecliptic_Poles', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0336'), isOn: this.layerStore.galacticPoles, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Galactic_Poles', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0337'), isOn: this.layerStore.equinoxPoints, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Equinox_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0338'), isOn: this.layerStore.solsticePoints, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Solstice_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0339'), isOn: this.layerStore.antisolarPoint, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Antisolar_Point', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0340'), isOn: this.layerStore.umbraCircle, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Umbra_Circle', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0341'), isOn: this.layerStore.penumbraCircle, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Penumbra_Circle', '', value) } })
      // 辅助标记
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.border)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0284')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2 })
        .height(18).width('100%')
      LayerSwitchRow({ label: I18n.t('s0343'), isOn: this.layerStore.fovMarker, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_FOV_Center_Marker', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0534'), isOn: this.layerStore.fovCircularMarker, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_FOV_Circular_Marker', '', value) } })
      if (this.layerStore.fovCircularMarker) {
        Row() {
          Text('圆形直径').fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
          Text(this.layerViewStore.fovCircularMarkerSize.toFixed(1) + '°')
            .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).width(48).textAlign(TextAlign.End)
          Slider({ value: this.layerViewStore.fovCircularMarkerSize, min: 0.1, max: 180, step: 0.1, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.softStrong).showSteps(false).showTips(false)
            .onChange((value: number) => { this.layerViewStore.fovCircularMarkerSize = value; this.onSetFovMarker('circleSize', value) })
        }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
          .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
      }
      LayerSwitchRow({ label: I18n.t('s0535'), isOn: this.layerStore.fovRectangularMarker, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_FOV_Rectangular_Marker', '', value) } })
      if (this.layerStore.fovRectangularMarker) {
        Row() {
          Text('矩形宽度').fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
          Text(this.layerViewStore.fovRectangularMarkerWidth.toFixed(1) + '°')
            .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).width(48).textAlign(TextAlign.End)
          Slider({ value: this.layerViewStore.fovRectangularMarkerWidth, min: 0.1, max: 180, step: 0.1, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.softStrong).showSteps(false).showTips(false)
            .onChange((value: number) => { this.layerViewStore.fovRectangularMarkerWidth = value; this.onSetFovMarker('rectWidth', value) })
        }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
          .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
        Row() {
          Text('矩形高度').fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
          Text(this.layerViewStore.fovRectangularMarkerHeight.toFixed(1) + '°')
            .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).width(48).textAlign(TextAlign.End)
          Slider({ value: this.layerViewStore.fovRectangularMarkerHeight, min: 0.1, max: 180, step: 0.1, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.softStrong).showSteps(false).showTips(false)
            .onChange((value: number) => { this.layerViewStore.fovRectangularMarkerHeight = value; this.onSetFovMarker('rectHeight', value) })
        }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
          .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
        Row() {
          Text('旋转角度').fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
          Text(this.layerViewStore.fovRectangularMarkerRotation.toFixed(0) + '°')
            .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).width(48).textAlign(TextAlign.End)
          Slider({ value: this.layerViewStore.fovRectangularMarkerRotation, min: -180, max: 180, step: 1, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.softStrong).showSteps(false).showTips(false)
            .onChange((value: number) => { this.layerViewStore.fovRectangularMarkerRotation = value; this.onSetFovMarker('rectRotation', value) })
        }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
          .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
          .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
      }
      LayerSwitchRow({ label: I18n.t('s0344'), isOn: this.layerStore.intercardinalPts, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Intercardinal_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0536'), isOn: this.layerStore.secondaryIntercardinalPts, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Secondary_Intercardinal_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0537'), isOn: this.layerStore.tertiaryIntercardinalPts, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Tertiary_Intercardinal_Points', '', value) } })
      // 更多标记线
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.border)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0285')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2 })
        .height(18).width('100%')
      LayerSwitchRow({ label: I18n.t('s0345'), isOn: this.layerStore.primeVerticalLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Prime_Vertical_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0346'), isOn: this.layerStore.currentVerticalLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Current_Vertical_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0347'), isOn: this.layerStore.colureLines, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Colure_Lines', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0348'), isOn: this.layerStore.precessionCircles, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Precession_Circles', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0500'), isOn: this.layerStore.circumpolarCircles, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Circumpolar_Circles', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0501'), isOn: this.layerStore.invariantPlaneLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Invariable_Plane_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0502'), isOn: this.layerStore.solarEquatorLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Solar_Equator_Line', '', value) } })
      // 更多网格
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.border)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0286')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2 })
        .height(18).width('100%')
      LayerSwitchRow({ label: I18n.t('s0503'), isOn: this.layerStore.equatorialJ2000Grid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Equatorial_J2000_Grid', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0504'), isOn: this.layerStore.eclipticJ2000Grid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ecliptic_J2000_Grid', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0505'), isOn: this.layerStore.eclipticGrid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ecliptic_Grid', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0506'), isOn: this.layerStore.supergalacticGrid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Supergalactic_Grid', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0507'), isOn: this.layerStore.fixedEquatorialGrid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Fixed_Equatorial_Grid', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0508'), isOn: this.layerStore.fixedEquatorLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Fixed_Equator_Line', '', value) } })
      // 更多点标记
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.border)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0287')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2 })
        .height(18).width('100%')
      LayerSwitchRow({ label: I18n.t('s0509'), isOn: this.layerStore.zenithNadir, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Zenith_Nadir', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0510'), isOn: this.layerStore.celestialJ2000Poles, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Celestial_J2000_Poles', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0511'), isOn: this.layerStore.eclipticJ2000Poles, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ecliptic_J2000_Poles', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0512'), isOn: this.layerStore.equinoxJ2000Pts, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Equinox_J2000_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0513'), isOn: this.layerStore.solsticeJ2000Pts, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Solstice_J2000_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0514'), isOn: this.layerStore.galacticCenter, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Galactic_Center', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0515'), isOn: this.layerStore.supergalacticPoles, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Supergalactic_Poles', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0516'), isOn: this.layerStore.apexPoints, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Apex_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0517'), isOn: this.layerStore.umbraCenter, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Umbra_Center_Point', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0518'), isOn: this.layerStore.longitudeLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Longitude_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0519'), isOn: this.layerStore.quadratureLine, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Quadrature_Line', '', value) } })
      // 视场中心坐标（自「设置 > 设备」迁入，自带标题）。
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.c.border)
        .margin({ top: 6, bottom: 4 })
      ViewCoordinateSettings({
        store: this.overlayStore,
        onToggleVisible: (visible: boolean) => { this.onToggleViewCoordinates(visible) },
        onSelectFamily: (family: string) => { this.onSelectViewCoordinateFamily(family) },
        onSelectEpoch: (epoch: string) => { this.onSelectViewEquatorialEpoch(epoch) }
      })
    }.width('100%')
  }
}

// 地景。
@Component
export struct LayerLandscapeTab {
  @ObjectLink layerStore: LayerStore
  @ObjectLink layerViewStore: LayerViewStore
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop earthObserver: boolean = true
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private expandedLandscapeId: string = ''
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onToggleLandscapeAutoSelection: (enabled: boolean) => void = () => {}
  onSetLandscapeFadeWithZoom: (isOn: boolean) => void = () => {}
  onImportLandscape: () => void = () => {}
  onSelectLandscape: (id: string, name: string) => void = () => {}
  onChangeLandscapeTransparency: (val: number) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private resourceText(value: string | undefined, fallback: string): string {
    return value !== undefined && value.trim().length > 0 ? value.trim() : fallback
  }

  private landscapeStory(id: string): LandscapeStoryZh | undefined {
    return getLandscapeStoryZh(id)
  }

  private landscapeTitle(item: LandscapeItem): string {
    const story = this.landscapeStory(item.id)
    if (story !== undefined) return story.titleZh
    return I18n.landscapeName(item.name)
  }

  private landscapeLocation(item: LandscapeItem): string {
    const story = this.landscapeStory(item.id)
    if (story !== undefined) return story.locationZh
    if (item.hasLocation === true) {
      return this.resourceText(item.planet, 'Earth') + ' · ' + this.resourceText(item.timezone, '标准时区')
    }
    return this.resourceText(item.planet, '通用视野')
  }

  private landscapeSummary(item: LandscapeItem): string {
    const story = this.landscapeStory(item.id)
    if (story !== undefined) return story.summaryZh
    if (item.localizedDescription !== undefined && item.localizedDescription.trim().length > 0) {
      return item.localizedDescription.trim()
    }
    return this.resourceText(item.description, '自定义地景视野')
  }

  private landscapeFullStory(item: LandscapeItem): string {
    const story = this.landscapeStory(item.id)
    if (story !== undefined) return story.storyZh
    if (item.localizedDescription !== undefined && item.localizedDescription.trim().length > 0) {
      return item.localizedDescription.trim()
    }
    return this.resourceText(item.description, '')
  }

  private landscapeViewingTip(item: LandscapeItem): string {
    const story = this.landscapeStory(item.id)
    return story !== undefined ? story.viewingTipZh : ''
  }

  private landscapeAccent(item: LandscapeItem): string {
    const story = this.landscapeStory(item.id)
    return story !== undefined ? story.accentHex : '#4A5D7A'
  }

  private toggleLandscapeStory(id: string): void {
    this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion(0.46, 0.88) }, () => {
      this.expandedLandscapeId = this.expandedLandscapeId === id ? '' : id
    })
  }

  build() {
    Column({ space: 0 }) {
      LayerSwitchRow({ label: I18n.t('s0306'), isOn: this.layerStore.ground, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ground', '', value) } })
      LayerSwitchRow({
        label: I18n.t('landscape_auto_selection'),
        isOn: this.layerStore.landscapeAutoSelection,
        onToggle: (value: boolean) => { this.onToggleLandscapeAutoSelection(value) }
      })
      Text(I18n.t('landscape_auto_selection_hint'))
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })
      LayerSwitchRow({
        label: I18n.t('mist_horizon'),
        isOn: this.layerStore.mistHorizon,
        rowEnabled: this.earthObserver,
        onToggle: (value: boolean) => { this.onToggleLayer('actionShow_MistHorizon', '', value) }
      })
      Text(this.earthObserver ? I18n.t('mist_horizon_hint') : I18n.t('mist_horizon_earth_only'))
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })
      if (!this.layerStore.ground) {
        Text(I18n.t('landscape_preselect_hint'))
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%')
          .padding({ left: 10, right: 10, bottom: 8 })
      }
      LayerSwitchRow({ label: I18n.t('s0520'), isOn: this.layerStore.landscapeIllum, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_LandscapeIllumination', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0521'), isOn: this.layerStore.landscapeLabels, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_LandscapeLabels', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0307'), isOn: this.layerStore.fogEffect, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Fog', '', value) } })
      LayerSwitchRow({
        label: I18n.t('landscape_fade_with_zoom'),
        isOn: this.layerViewStore.landscapeFadeWithZoom,
        onToggle: (value: boolean) => { this.onSetLandscapeFadeWithZoom(value) }
      })
      Text(I18n.t('landscape_fade_with_zoom_hint'))
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })
      Row() {
        Text(I18n.t('i0289')).fontSize(panelFontSize(14, this.readableUi)).fontColor(this.c.text).width(86)
        Text(this.layerViewStore.landscapeTransp + '%')
          .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).width(44).textAlign(TextAlign.End)
        Slider({ value: this.layerViewStore.landscapeTransp, min: 0, max: 100, step: 5, style: SliderStyle.OutSet })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1)
          .trackColor(this.c.softStrong)
          .showSteps(false)
          .onChange((val: number) => { this.layerViewStore.landscapeTransp = Math.round(val); this.onChangeLandscapeTransparency(val) })
      }.height(this.readableUi ? 50 : 42).width('100%').padding({ left: 10, right: 8 })
        .backgroundColor(this.c.bg).border({ width: 1, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_CONTROL).margin({ top: 6, bottom: 6 })
      Row({ space: 6 }) {
        Text(I18n.t('i0288') + (this.layerViewStore.landscapeList.length > 0 ? ' · ' + this.layerViewStore.landscapeList.length + ' 套实景与地平线' : ''))
          .fontSize(11).fontColor(this.c.sub).layoutWeight(1).padding({ left: 2 })
        InfoTipButton({
          title: '内置地景与星空视野',
          tip: '收录 16 套地球暗夜观测点、洞穴遗迹及太阳系行星云顶与月面全景。点按卡片切换地景，点按「故事」可阅读各地景背后的天文与人文导览。'
        })
      }.width('100%').margin({ top: 6, bottom: 4 }).alignItems(VerticalAlign.Center)
      Row({ space: 8 }) {
        Text(I18n.t('btn_import_landscape')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
        if (this.layerViewStore.landscapeImporting) LoadingProgress().width(16).height(16).color(this.c.accent)
        Button(I18n.t('btn_import_landscape')).fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 }).enabled(!this.layerViewStore.landscapeImporting)
          .onClick(() => { this.onImportLandscape() })
      }.width('100%').height(38).padding({ left: 8, right: 8 }).backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 7 })
      if (this.layerViewStore.landscapeLoading && this.layerViewStore.landscapeList.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress().width(16).height(16).color(this.c.accent)
          Text('正在加载地景列表').fontSize(11).fontColor(this.c.sub)
        }
          .width('100%').height(42).justifyContent(FlexAlign.Center)
      } else if (!this.layerViewStore.landscapeLoading && this.layerViewStore.landscapeList.length === 0) {
        Text('暂无可用地景').fontSize(11).fontColor(this.c.sub).width('100%')
          .textAlign(TextAlign.Center).padding({ top: 14, bottom: 14 })
      }
      Column({ space: 8 }) {
        ForEach(this.layerViewStore.landscapeList, (item: LandscapeItem) => {
          Column({ space: 8 }) {
            Row({ space: 10 }) {
              if (item.previewPath !== undefined && item.previewPath.length > 0) {
                Stack({ alignContent: Alignment.Center }) {
                  Image($rawfile('stellarium/' + item.previewPath))
                    .width('100%').height('100%').objectFit(ImageFit.Cover)
                    .sourceSize({ width: 228, height: 168 })
                  Row().width('100%').height('100%').backgroundColor(this.c.nightMask)
                }
                .width(76).height(56).clip(true).borderRadius(UI_RADIUS_MEDIA)
                .backgroundColor(this.c.bg)
                .border({ width: 0.5, color: this.c.border })
              } else {
                Column({ space: 3 }) {
                  Row().width(44).height(2).backgroundColor('#FFFFFF').opacity(0.75).borderRadius(1)
                  Text(item.id === 'zero' ? '0°' : '山脊').fontSize(10).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
                }
                .width(76).height(56).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                .borderRadius(UI_RADIUS_MEDIA).backgroundColor(this.landscapeAccent(item))
                .border({ width: 0.5, color: this.c.border })
              }
              Column({ space: 3 }) {
                Row({ space: 6 }) {
                  Text(this.landscapeTitle(item))
                    .fontSize(panelFontSize(13, this.readableUi))
                    .fontWeight(this.layerViewStore.currentLandscapeId === item.id ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.layerViewStore.currentLandscapeId === item.id ? this.c.accent : this.c.text)
                    .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.layerViewStore.currentLandscapeId === item.id) {
                    Text('✓ ' + I18n.t('s0602')).fontSize(10).fontColor(this.c.accent)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(this.c.accentSoft).borderRadius(UI_RADIUS_TAG)
                  }
                }.width('100%').alignItems(VerticalAlign.Center)
                Text(this.landscapeLocation(item))
                  .fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.landscapeSummary(item))
                  .fontSize(11).fontColor(this.c.sub).width('100%').maxLines(2).lineHeight(16)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1)
            }.width('100%').alignItems(VerticalAlign.Top)
            Row({ space: 8 }) {
              Text(item.author !== undefined && item.author.trim().length > 0 ? '拍摄/制作：' + item.author.trim() : '内置天文地景')
                .fontSize(10).fontColor(this.c.tertiary).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.landscapeFullStory(item).length > 0) {
                Button(this.expandedLandscapeId === item.id ? '收起故事 ▴' : '展开故事 ▾')
                  .fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg)
                  .borderRadius(UI_RADIUS_CONTROL).height(26).padding({ left: 9, right: 9 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.toggleLandscapeStory(item.id) })
              }
            }.width('100%').alignItems(VerticalAlign.Center)
            if (this.expandedLandscapeId === item.id && this.landscapeFullStory(item).length > 0) {
              Column({ space: 6 }) {
                Text(this.landscapeFullStory(item))
                  .fontSize(11).fontColor(this.c.text).width('100%').lineHeight(19)
                if (this.landscapeViewingTip(item).length > 0) {
                  Text('观星提示：' + this.landscapeViewingTip(item))
                    .fontSize(10).fontColor(this.c.accent).width('100%').lineHeight(16)
                }
              }
              .width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              .border({ width: 0.5, color: this.c.border })
            }
          }
          .width('100%').padding({ left: 11, right: 11, top: 10, bottom: 10 })
          .backgroundColor(this.layerViewStore.currentLandscapeId === item.id ? this.c.chipInactiveBg : this.c.soft)
          .border({ width: 1, color: this.layerViewStore.currentLandscapeId === item.id ? this.c.chipActiveBorder : this.c.border })
          .borderRadius(UI_RADIUS_CARD)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
          .onClick(() => { this.onSelectLandscape(item.id, item.name) })
        }, (item: LandscapeItem) => item.id)
      }
      .width('100%')
    }.width('100%')
  }
}

// 巡天（离线 AppGallery 构建下不渲染）。
@Component
export struct LayerSurveysTab {
  @ObjectLink layerStore: LayerStore
  @ObjectLink surveyStore: SurveyStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onRefreshSurvey: () => void = () => {}
  onSelectSpectral: (id: string) => void = () => {}
  onCloseSpectral: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 0 }) {
      LayerSwitchRow({ label: I18n.t('s0600'), isOn: this.layerStore.hipsSurveys, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Hips_Surveys', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0601'), isOn: this.layerStore.toastSurvey, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Toast_Survey', '', value) } })
      Row() {
        Text(I18n.t('i0215')).fontSize(10).fontColor(this.c.iconSecondary).width('100%').padding({ left: 2 })
      }.height(18).width('100%').margin({ top: 8 })
      LayerSpectralSection({
        surveyStore: this.surveyStore,
        onRefreshSurvey: () => { this.onRefreshSurvey() },
        onSelectSpectral: (id: string) => { this.onSelectSpectral(id) },
        onCloseSpectral: () => { this.onCloseSpectral() }
      })
    }.width('100%')
  }
}
