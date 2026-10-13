import { LandscapeItem } from '../../pages/StellariumTypes'
import { I18n } from '../../pages/I18n'
import { LayerStore } from '../../state/LayerStore'
import { LayerViewStore } from '../../state/LayerViewStore'
import { OverlayStore } from '../../state/OverlayStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { LayerSwitchRow } from './LayerSwitchRow'
import { ObservationAidBlock } from './ObservationAidBlock'
import { LayerSpectralSection } from './LayerSpectralSection'
import { SurveyStore } from '../../state/SurveyStore'
import { ViewCoordinateSettings } from '../view/ViewCoordinateSettings'

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
  @Prop nightModeOn: boolean
  @Prop refractionOn: boolean
  @Prop atmoPressure: number
  @Prop atmoTemperature: number
  @Prop atmoExtinction: number
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop cardBorder: string
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onSetSkyDisplay: (setting: string, value: boolean | number) => void = () => {}
  onStarMagLimit: (value: number) => void = () => {}
  onMilkyWayBright: (value: number) => void = () => {}
  onAtmosphere: (pressure: number, temperature: number, extinction: number) => void = () => {}

  private meteorZhrSliderPosition(): number {
    const value = Math.max(0, Math.min(this.layerViewStore.meteorZhrMax, this.layerViewStore.meteorZhr))
    if (value <= 1000) return value * 0.75
    const upperRange = Math.max(1, this.layerViewStore.meteorZhrMax / 1000)
    return 750 + Math.log(value / 1000) / Math.log(upperRange) * 250
  }

  private meteorZhrFromSliderPosition(position: number): number {
    const clamped = Math.max(0, Math.min(1000, position))
    if (clamped <= 750) return Math.round(clamped / 0.75)
    const upperRange = Math.max(1, this.layerViewStore.meteorZhrMax / 1000)
    return Math.round(1000 * Math.pow(upperRange, (clamped - 750) / 250))
  }

  build() {
    Column({ space: 0 }) {
      // ── 恒星：恒星本体与其渲染特征 ──
      Text('恒星').fontSize(11).fontColor(this.subColor).width('100%').margin({ top: 2, bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0530'), isOn: this.layerStore.stars, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Stars', '', value) } })
      // 星等限制
      Row() {
        Text(I18n.t('i0300')).fontSize(12).fontColor(this.subColor).width(72)
        Slider({
          value: this.layerViewStore.starMagLimit,
          min: 2.0,
          max: 9.0,
          step: 0.5,
          style: SliderStyle.OutSet
        })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .blockColor('#5B93BF')
          .trackColor('rgba(255,255,255,0.08)')
          .selectedColor('#5B93BF')
          .showSteps(false)
          .showTips(false)
          .layoutWeight(1)
          .onChange((value: number) => {
            this.onStarMagLimit(Math.round(value * 10) / 10)
          })
        Text(this.layerViewStore.starMagLimit.toFixed(1)).fontSize(12).fontColor(this.textColor).width(28).textAlign(TextAlign.End)
      }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      LayerSwitchRow({ label: '亮星光晕', isOn: this.layerStore.bigStarHalo, onToggle: (value: boolean) => { this.onToggleLayer('bigStarHalo', 'setSkyDisplayBigStarHalo', value) } })
      LayerSwitchRow({ label: '星芒效果', isOn: this.layerStore.starSpiky, onToggle: (value: boolean) => { this.onToggleLayer('starSpiky', 'setSkyDisplayStarSpiky', value) } })
      LayerSwitchRow({ label: '星星闪烁', isOn: this.layerStore.starTwinkle, onToggle: (value: boolean) => { this.onToggleLayer('starTwinkle', 'setSkyDisplayStarTwinkle', value) } })
      if (this.layerStore.starTwinkle) {
        LayerSwitchRow({ label: '无大气时保持闪烁', isOn: this.layerStore.forcedStarTwinkle, onToggle: (value: boolean) => { this.onToggleLayer('forcedStarTwinkle', 'setSkyDisplayForcedTwinkle', value) } })
      }
      // ── 天空：天空背景与天象 ──
      Row().width('100%').height(0.5).backgroundColor(this.cardBorder).margin({ top: 5, bottom: 8 })
      Text('天空').fontSize(11).fontColor(this.subColor).width('100%').margin({ bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0531'), isOn: this.layerStore.milkyWay, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_MilkyWay', '', value) } })
      // 银河亮度
      Row() {
        Text(I18n.t('i0212')).fontSize(12).fontColor(this.subColor).width(72)
        Row({ space: 6 }) {
          Button('-').fontSize(12).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).width(36).height(28)
            .padding({ left: 0, right: 0 })
            .onClick(() => {
              if (this.layerViewStore.milkyWayBright > 0) {
                this.onMilkyWayBright(this.layerViewStore.milkyWayBright - 1)
              }
            })
          Text(this.layerViewStore.milkyWayBright.toString()).fontSize(14).fontColor(this.textColor).width(24).textAlign(TextAlign.Center)
          Button('+').fontSize(12).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).width(36).height(28)
            .padding({ left: 0, right: 0 })
            .onClick(() => {
              if (this.layerViewStore.milkyWayBright < 6) {
                this.onMilkyWayBright(this.layerViewStore.milkyWayBright + 1)
              }
            })
        }
      }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      LayerSwitchRow({ label: I18n.t('s0532'), isOn: this.layerStore.starLabels, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Stars_Labels', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0308'), isOn: this.layerStore.meteors, onToggle: (value: boolean) => { this.onToggleLayer('setMeteors', 'setMeteors', value) } })
      if (this.layerStore.meteors) {
        Row() {
          Text('理论流星率').fontSize(12).fontColor(this.subColor).width(76)
          Slider({ value: this.meteorZhrSliderPosition(), min: 0, max: 1000, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false)
            .onChange((value: number) => { this.onSetSkyDisplay('meteorZhr', this.meteorZhrFromSliderPosition(value)) })
          Text(this.layerViewStore.meteorZhr + ' / 小时').fontSize(11).fontColor(this.textColor).width(66).textAlign(TextAlign.End)
        }.height(36).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 2 })
        Text('实际可见数量还会受夜间、地景亮度和地平高度影响')
          .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 86, right: 10 }).margin({ bottom: 4 })
      }
      LayerSwitchRow({ label: '黄道光', isOn: this.layerStore.zodiacalLight, onToggle: (value: boolean) => { this.onToggleLayer('zodiacalLight', 'setSkyDisplayZodiacalLight', value) } })
      if (this.layerStore.zodiacalLight) {
        Row() {
          Text('黄道光亮度').fontSize(12).fontColor(this.subColor).width(76)
          Slider({ value: this.layerViewStore.zodiacalIntensity, min: 0, max: 5, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false)
            .onChange((value: number) => { this.onSetSkyDisplay('zodiacalIntensity', Math.round(value * 10) / 10) })
          Text(this.layerViewStore.zodiacalIntensity.toFixed(1)).fontSize(11).fontColor(this.textColor).width(34).textAlign(TextAlign.End)
        }.height(36).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      }
      LayerSwitchRow({ label: I18n.t('s0300'), isOn: this.nightModeOn, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Night_Mode', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0309'), isOn: this.layerStore.flipHoriz, onToggle: (value: boolean) => { this.onToggleLayer('actionHorizontal_Flip', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0310'), isOn: this.layerStore.flipVert, onToggle: (value: boolean) => { this.onToggleLayer('actionVertical_Flip', '', value) } })
      // ── 观测条件：大气、地景与观测几何 ──
      Row().width('100%').height(0.5).backgroundColor(this.cardBorder).margin({ top: 5, bottom: 8 })
      Text('观测条件').fontSize(11).fontColor(this.subColor).width('100%').margin({ bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0305'), isOn: this.layerStore.atmosphere, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Atmosphere', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0306'), isOn: this.layerStore.ground, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ground', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0307'), isOn: this.layerStore.fogEffect, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Fog', '', value) } })
      Row() {
        Text('光污染等级').fontSize(12).fontColor(this.subColor).width(76)
        Slider({ value: this.layerViewStore.bortleScale, min: 1, max: 9, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false)
          .onChange((value: number) => { this.onSetSkyDisplay('bortleScale', Math.round(value)) })
        Text('Bortle ' + this.layerViewStore.bortleScale).fontSize(11).fontColor(this.textColor).width(58).textAlign(TextAlign.End)
      }.height(36).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      LayerSwitchRow({ label: '人眼动态视觉调适', isOn: this.layerStore.luminanceAdaptation, onToggle: (value: boolean) => { this.onToggleLayer('luminanceAdaptation', 'setSkyDisplayLuminanceAdaptation', value) } })
      // 大气折射（气压 / 气温 / 消光）自时间面板迁入
      ObservationAidBlock({
        refractionOn: this.refractionOn,
        atmoPressure: this.atmoPressure,
        atmoTemperature: this.atmoTemperature,
        atmoExtinction: this.atmoExtinction,
        textColor: this.textColor,
        subColor: this.subColor,
        borderColorValue: this.cardBorder,
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
  @Prop expandedLayout: boolean
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onSetOrbitFlag: (setting: string, enabled: boolean) => void = () => {}
  onSetOrbitThickness: (value: number) => void = () => {}
  onSetOrbitColorStyle: (index: number) => void = () => {}
  onLoadOrbitSettings: () => void = () => {}
  onSetTrailFlag: (setting: string, enabled: boolean) => void = () => {}
  onSetTrailNumber: (setting: string, value: number) => void = () => {}
  onLoadTrailSettings: () => void = () => {}
  onApplyTrailColor: () => void = () => {}
  onTriggerAction: (actionId: string) => void = () => {}

  private orbitColorStyleIndex(): number {
    const style = this.layerViewStore.orbitColorStyle
    if (style === 'groups') return 1
    if (style === 'major_planets') return 2
    if (style === 'major_planets_minor_types') return 3
    return 0
  }

  build() {
    Column({ space: 0 }) {
      Text('基础显示').fontSize(11).fontColor(this.subColor).width('100%').margin({ top: 2, bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0311'), isOn: this.layerStore.planets, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0312'), isOn: this.layerStore.planetOrbits, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_Orbits', '', value) } })
      if (this.layerStore.planetOrbits) {
        Row() {
          Column({ space: 1 }) {
            Text('轨道显示方式').fontSize(12).fontColor(this.subColor).width('100%')
            Text('控制轨道显示对象、线条和配色分类').fontSize(10).fontColor(this.subColor).width('100%')
          }.layoutWeight(1)
          Button(this.layerViewStore.orbitSettingsExpanded ? '收起' : '设置').fontSize(10).fontColor(this.accentColor).height(28)
            .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).padding({ left: 9, right: 9 })
            .onClick(() => {
              this.layerViewStore.orbitSettingsExpanded = !this.layerViewStore.orbitSettingsExpanded
              if (this.layerViewStore.orbitSettingsExpanded) this.onLoadOrbitSettings()
            })
        }.width('100%').padding({ left: 2, right: 2, top: 3, bottom: 4 }).margin({ bottom: this.layerViewStore.orbitSettingsExpanded ? 4 : 8 })
        if (this.layerViewStore.orbitSettingsExpanded) {
          Column({ space: 4 }) {
            Row() {
              Column({ space: 1 }) {
                Text('只显示当前选中天体').fontSize(11).fontColor(this.textColor).width('100%')
                Text('关闭后显示所有符合条件的轨道').fontSize(10).fontColor(this.subColor).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitIsolated }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('isolated', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Column({ space: 1 }) {
                Text('始终显示八大行星轨道').fontSize(11).fontColor(this.textColor).width('100%')
                Text('可与当前选中的小天体轨道同时显示').fontSize(10).fontColor(this.subColor).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitMajorPlanets }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('majorPlanets', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Column({ space: 1 }) {
                Text('仅显示行星轨道').fontSize(11).fontColor(this.textColor).width('100%')
                Text('隐藏小行星、彗星等其他天体轨道').fontSize(10).fontColor(this.subColor).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitPlanetsOnly }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('planetsOnly', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Column({ space: 1 }) {
                Text('包含卫星轨道').fontSize(11).fontColor(this.textColor).width('100%')
                Text('显示行星周围卫星的轨道').fontSize(10).fontColor(this.subColor).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitWithMoons }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('withMoons', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Column({ space: 1 }) {
                Text('轨道保持显示').fontSize(11).fontColor(this.textColor).width('100%')
                Text('天体移出屏幕后仍持续绘制轨道').fontSize(10).fontColor(this.subColor).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.orbitPermanent }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetOrbitFlag('permanent', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Text('轨道线宽').fontSize(11).fontColor(this.textColor).width(64)
              Text(this.layerViewStore.orbitThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.subColor).width(34).textAlign(TextAlign.End)
              Slider({ value: this.layerViewStore.orbitThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false).showTips(false)
                .onChange((value: number) => { this.onSetOrbitThickness(value) })
            }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            Row({ space: 8 }) {
              Text('轨道配色').fontSize(11).fontColor(this.textColor).width(64)
              Select([{ value: '统一颜色' }, { value: '按天体分组' }, { value: '按八大行星' }, { value: '行星与小天体分类' }])
                .selected(this.orbitColorStyleIndex()).value('轨道配色').height(30).layoutWeight(1)
                .onSelect((index: number) => { this.onSetOrbitColorStyle(index) })
            }.height(34).width('100%').padding({ left: 8, right: 8 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
          }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor('rgba(91,147,191,0.08)').borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
        }
      }
      LayerSwitchRow({ label: I18n.t('s0314'), isOn: this.layerStore.planetHints, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_Hints', '', value) } })
      Text('高级标记').fontSize(11).fontColor(this.subColor).width('100%').margin({ top: 8, bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0313'), isOn: this.layerStore.planetTrails, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_Trails', '', value) } })
      if (this.layerStore.planetTrails) {
        Row() {
          Column({ space: 1 }) {
            Text('轨迹显示方式').fontSize(12).fontColor(this.subColor).width('100%')
            Text('控制保留对象、历史跨度、线宽与颜色').fontSize(10).fontColor(this.subColor).width('100%')
          }.layoutWeight(1)
          Button(this.layerViewStore.trailSettingsExpanded ? '收起' : '设置').fontSize(10).fontColor(this.accentColor).height(28)
            .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).padding({ left: 9, right: 9 })
            .onClick(() => {
              this.layerViewStore.trailSettingsExpanded = !this.layerViewStore.trailSettingsExpanded
              if (this.layerViewStore.trailSettingsExpanded) this.onLoadTrailSettings()
            })
        }.width('100%').padding({ left: 2, right: 2, top: 3, bottom: 4 }).margin({ bottom: this.layerViewStore.trailSettingsExpanded ? 4 : 8 })
        if (this.layerViewStore.trailSettingsExpanded) {
          Column({ space: 4 }) {
            Row() {
              Column({ space: 1 }) {
                Text('仅保留最近选中天体').fontSize(11).fontColor(this.textColor).width('100%')
                Text('关闭后显示当前可见的全部太阳系天体轨迹').fontSize(10).fontColor(this.subColor).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.trailIsolated }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetTrailFlag('isolated', enabled) })
            }.height(44).width('100%').padding({ left: 8, right: 8 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            if (this.layerViewStore.trailIsolated) {
              Row() {
                Text('保留选中对象').fontSize(11).fontColor(this.textColor).width(84)
                Text(this.layerViewStore.trailSelectionCount.toFixed(0) + ' 个').fontSize(11).fontColor(this.subColor).width(34).textAlign(TextAlign.End)
                Slider({ value: this.layerViewStore.trailSelectionCount, min: 1, max: 5, step: 1, style: SliderStyle.OutSet })
                  .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                  .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false).showTips(false)
                  .onChange((value: number) => { this.onSetTrailNumber('selectionCount', value) })
              }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            }
            Row() {
              Text('历史跨度').fontSize(11).fontColor(this.textColor).width(72)
              Text(this.layerViewStore.trailYears.toFixed(0) + ' 年').fontSize(11).fontColor(this.subColor).width(42).textAlign(TextAlign.End)
              Slider({ value: this.layerViewStore.trailYears, min: 1, max: 250, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false).showTips(false)
                .onChange((value: number) => { this.onSetTrailNumber('years', value) })
            }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Text('轨迹线宽').fontSize(11).fontColor(this.textColor).width(72)
              Text(this.layerViewStore.trailThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.subColor).width(42).textAlign(TextAlign.End)
              Slider({ value: this.layerViewStore.trailThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false).showTips(false)
                .onChange((value: number) => { this.onSetTrailNumber('thickness', value) })
            }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
            Row({ space: 8 }) {
              Text('轨迹颜色').fontSize(11).fontColor(this.textColor).width(64)
              TextInput({ text: this.layerViewStore.trailColorInput, placeholder: '#RRGGBB' })
                .fontSize(11).fontColor(this.textColor).placeholderColor(this.subColor).height(30).layoutWeight(1)
                .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).padding({ left: 8, right: 8 })
                .onChange((value: string) => { this.layerViewStore.trailColorInput = value })
              Button('应用').fontSize(10).fontColor(this.accentColor).height(28).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
                .padding({ left: 9, right: 9 }).onClick(() => { this.onApplyTrailColor() })
            }.height(34).width('100%').padding({ left: 8, right: 8 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
          }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor('rgba(91,147,191,0.08)').borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
        }
      }
      LayerSwitchRow({ label: I18n.t('s0318'), isOn: this.layerStore.minorBodyMarkers, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_ShowMinorBodyMarkers', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0319'), isOn: this.layerStore.planetNomenclature, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_Nomenclature', '', value) } })
      if (this.expandedLayout) {
        Text('视直径增强').fontSize(11).fontColor(this.subColor).width('100%').margin({ top: 8, bottom: 6 }).padding({ left: 2 })
        LayerSwitchRow({ label: I18n.t('s0315'), isOn: this.layerStore.enlargeMoon, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_EnlargeMoon', '', value) } })
        LayerSwitchRow({ label: I18n.t('s0316'), isOn: this.layerStore.enlargePlanets, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_EnlargePlanets', '', value) } })
        LayerSwitchRow({ label: I18n.t('s0317'), isOn: this.layerStore.enlargeSun, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Planets_EnlargeSun', '', value) } })
      }
      Row() {
        Text(I18n.t('i0281')).fontSize(12).fontColor(this.subColor).width(72)
        Button(I18n.t('i0282')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
          .onClick(() => { this.onTriggerAction('actionShow_Planets_Trails_Reset') })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    }.width('100%')
  }
}

// 深空天体。
@Component
export struct LayerDsoTab {
  @ObjectLink layerStore: LayerStore
  @Prop subColor: string
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}

  build() {
    Column({ space: 0 }) {
      Text('显示内容').fontSize(11).fontColor(this.subColor).width('100%').margin({ top: 2, bottom: 6 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0320'), isOn: this.layerStore.nebulae, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Nebulas', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0321'), isOn: this.layerStore.dsoLabels, onToggle: (value: boolean) => { this.onToggleLayer('setDsoLabels', 'setDsoLabels', value) } })
      LayerSwitchRow({ label: I18n.t('s0322'), isOn: this.layerStore.dsoTextures, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_DSO_Textures', '', value) } })
    }.width('100%')
  }
}

// 标记与网格。
@Component
export struct LayerMarkingsTab {
  @ObjectLink layerStore: LayerStore
  @ObjectLink layerViewStore: LayerViewStore
  @ObjectLink overlayStore: OverlayStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop cardBorder: string
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onSetFovMarker: (setting: string, value: number) => void = () => {}
  onToggleViewCoordinates: (visible: boolean) => void = () => {}
  onSelectViewCoordinateFamily: (family: string) => void = () => {}
  onSelectViewEquatorialEpoch: (epoch: string) => void = () => {}

  build() {
    Column({ space: 0 }) {
      Text(I18n.t('view_orientation_marks')).fontSize(11).fontColor(this.subColor).width('100%').margin({ top: 4, bottom: 2 }).padding({ left: 2 })
      Text(I18n.t('view_orientation_marks_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(2)
        .padding({ left: 2, right: 2 }).margin({ bottom: 5 })
      LayerSwitchRow({ label: I18n.t('s0533'), isOn: this.layerStore.cardinalPoints, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Cardinal_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0342'), isOn: this.layerStore.compassMarks, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Compass_Marks', '', value) } })
      // 基础网格
      Text(I18n.t('i0197')).fontSize(11).fontColor(this.subColor).width('100%').margin({ top: 4, bottom: 2 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0538'), isOn: this.layerStore.gridlinesMaster, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Gridlines', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0323'), isOn: this.layerStore.equatorialGrid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Equatorial_Grid', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0324'), isOn: this.layerStore.azimuthGrid, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Azimuthal_Grid', '', value) } })
      // 特殊线
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.cardBorder)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0198')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
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
        .backgroundColor(this.cardBorder)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0199')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
        .height(18).width('100%')
      LayerSwitchRow({ label: I18n.t('s0332'), isOn: this.layerStore.equJ2000Line, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Equator_J2000_Line', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0333'), isOn: this.layerStore.eclJ2000Line, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ecliptic_J2000_Line', '', value) } })
      // 点标记
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.cardBorder)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0200')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
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
        .backgroundColor(this.cardBorder)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0284')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
        .height(18).width('100%')
      LayerSwitchRow({ label: I18n.t('s0343'), isOn: this.layerStore.fovMarker, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_FOV_Center_Marker', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0534'), isOn: this.layerStore.fovCircularMarker, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_FOV_Circular_Marker', '', value) } })
      if (this.layerStore.fovCircularMarker) {
        Row() {
          Text('圆形直径').fontSize(11).fontColor(this.subColor).width(72)
          Text(this.layerViewStore.fovCircularMarkerSize.toFixed(1) + '°').fontSize(11).fontColor(this.textColor).width(42).textAlign(TextAlign.End)
          Slider({ value: this.layerViewStore.fovCircularMarkerSize, min: 0.1, max: 180, step: 0.1, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false).showTips(false)
            .onChange((value: number) => { this.layerViewStore.fovCircularMarkerSize = value; this.onSetFovMarker('circleSize', value) })
        }.height(34).width('100%').padding({ left: 14, right: 10 }).margin({ bottom: 3 })
      }
      LayerSwitchRow({ label: I18n.t('s0535'), isOn: this.layerStore.fovRectangularMarker, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_FOV_Rectangular_Marker', '', value) } })
      if (this.layerStore.fovRectangularMarker) {
        Row() {
          Text('矩形宽度').fontSize(11).fontColor(this.subColor).width(72)
          Text(this.layerViewStore.fovRectangularMarkerWidth.toFixed(1) + '°').fontSize(11).fontColor(this.textColor).width(42).textAlign(TextAlign.End)
          Slider({ value: this.layerViewStore.fovRectangularMarkerWidth, min: 0.1, max: 180, step: 0.1, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false).showTips(false)
            .onChange((value: number) => { this.layerViewStore.fovRectangularMarkerWidth = value; this.onSetFovMarker('rectWidth', value) })
        }.height(34).width('100%').padding({ left: 14, right: 10 })
        Row() {
          Text('矩形高度').fontSize(11).fontColor(this.subColor).width(72)
          Text(this.layerViewStore.fovRectangularMarkerHeight.toFixed(1) + '°').fontSize(11).fontColor(this.textColor).width(42).textAlign(TextAlign.End)
          Slider({ value: this.layerViewStore.fovRectangularMarkerHeight, min: 0.1, max: 180, step: 0.1, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false).showTips(false)
            .onChange((value: number) => { this.layerViewStore.fovRectangularMarkerHeight = value; this.onSetFovMarker('rectHeight', value) })
        }.height(34).width('100%').padding({ left: 14, right: 10 })
        Row() {
          Text('旋转角度').fontSize(11).fontColor(this.subColor).width(72)
          Text(this.layerViewStore.fovRectangularMarkerRotation.toFixed(0) + '°').fontSize(11).fontColor(this.textColor).width(42).textAlign(TextAlign.End)
          Slider({ value: this.layerViewStore.fovRectangularMarkerRotation, min: -180, max: 180, step: 1, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).blockColor(this.accentColor).trackColor(this.panelColor).selectedColor(this.accentColor).showSteps(false).showTips(false)
            .onChange((value: number) => { this.layerViewStore.fovRectangularMarkerRotation = value; this.onSetFovMarker('rectRotation', value) })
        }.height(34).width('100%').padding({ left: 14, right: 10 }).margin({ bottom: 3 })
      }
      LayerSwitchRow({ label: I18n.t('s0344'), isOn: this.layerStore.intercardinalPts, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Intercardinal_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0536'), isOn: this.layerStore.secondaryIntercardinalPts, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Secondary_Intercardinal_Points', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0537'), isOn: this.layerStore.tertiaryIntercardinalPts, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Tertiary_Intercardinal_Points', '', value) } })
      // 更多标记线
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.cardBorder)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0285')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
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
        .backgroundColor(this.cardBorder)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0286')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
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
        .backgroundColor(this.cardBorder)
        .margin({ top: 6, bottom: 4 })
      Text(I18n.t('i0287')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
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
        .backgroundColor(this.cardBorder)
        .margin({ top: 6, bottom: 4 })
      ViewCoordinateSettings({
        store: this.overlayStore,
        textColor: this.textColor,
        subColor: this.subColor,
        accentColor: this.accentColor,
        panelColor: this.panelColor,
        lineColor: this.cardBorder,
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
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onSetLandscapeFadeWithZoom: (isOn: boolean) => void = () => {}
  onImportLandscape: () => void = () => {}
  onSelectLandscape: (id: string, name: string) => void = () => {}
  onChangeLandscapeTransparency: (val: number) => void = () => {}

  private resourceText(value: string | undefined, fallback: string): string {
    return value !== undefined && value.trim().length > 0 ? value.trim() : fallback
  }

  build() {
    Column({ space: 0 }) {
      LayerSwitchRow({ label: I18n.t('s0306'), isOn: this.layerStore.ground, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ground', '', value) } })
      LayerSwitchRow({ label: I18n.t('mist_horizon'), isOn: this.layerStore.mistHorizon, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_MistHorizon', '', value) } })
      Text(I18n.t('mist_horizon_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 10, right: 10, bottom: 8 })
      if (!this.layerStore.ground) {
        Text(I18n.t('landscape_preselect_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 10, right: 10, bottom: 8 })
      }
      LayerSwitchRow({ label: I18n.t('s0520'), isOn: this.layerStore.landscapeIllum, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_LandscapeIllumination', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0521'), isOn: this.layerStore.landscapeLabels, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_LandscapeLabels', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0307'), isOn: this.layerStore.fogEffect, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Fog', '', value) } })
      Row() {
        Column() {
          Text('俯视时地景淡出').fontSize(13).fontColor('#E5FFFFFF')
          Text('视角压低看地面时地面渐隐，露出地平线下的星空（仍可见）').fontSize(11).fontColor('#99FFFFFF').margin({ top: 2 })
        }.layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.landscapeFadeWithZoom })
          .onChange((isOn: boolean) => { this.onSetLandscapeFadeWithZoom(isOn) })
      }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ top: 6 })
      Row() {
        Text(I18n.t('i0288')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
      }.height(18).width('100%').margin({ top: 6 })
      Row({ space: 8 }) {
        Text(I18n.t('btn_import_landscape')).fontSize(11).fontColor(this.textColor).layoutWeight(1)
        if (this.layerViewStore.landscapeImporting) LoadingProgress().width(16).height(16).color(this.accentColor)
        Button(I18n.t('btn_import_landscape')).fontSize(10).fontColor(this.accentColor).backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 }).enabled(!this.layerViewStore.landscapeImporting)
          .onClick(() => { this.onImportLandscape() })
      }.width('100%').height(38).padding({ left: 8, right: 8 }).backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 5 })
      if (this.layerViewStore.landscapeLoading && this.layerViewStore.landscapeList.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress().width(16).height(16).color(this.accentColor)
          Text('正在加载地景列表').fontSize(11).fontColor(this.subColor)
        }
          .width('100%').height(42).justifyContent(FlexAlign.Center)
      } else if (!this.layerViewStore.landscapeLoading && this.layerViewStore.landscapeList.length === 0) {
        Text('暂无可用地景').fontSize(11).fontColor(this.subColor).width('100%')
          .textAlign(TextAlign.Center).padding({ top: 14, bottom: 14 })
      }
      Column({ space: 2 }) {
        ForEach(this.layerViewStore.landscapeList, (item: LandscapeItem) => {
          Column({ space: 2 }) {
            Row() {
              Text(I18n.landscapeName(item.name)).fontSize(11)
                .fontColor(this.layerViewStore.currentLandscapeId === item.id ? this.accentColor : this.textColor)
                .layoutWeight(1)
              if (this.layerViewStore.currentLandscapeId === item.id) {
                Text(I18n.t('s0602')).fontSize(10).fontColor(this.accentColor).margin({ right: 8 })
              }
            }
            if (item.author || item.description) {
              Text(this.resourceText(item.description, I18n.t('resource_not_provided')))
                .fontSize(10).fontColor(this.subColor).width('100%').maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(I18n.t('resource_author') + ': ' + this.resourceText(item.author, I18n.t('resource_not_provided')))
                .fontSize(10).fontColor('#66FFFFFF').width('100%').maxLines(1)
            }
            if (item.hasLocation === true) {
              Text(this.resourceText(item.planet, 'Earth') + ' · ' + this.resourceText(item.timezone, '时区未提供'))
                .fontSize(10).fontColor('#66FFFFFF').width('100%').maxLines(1)
            }
            if (item.source) {
              Text(I18n.t('resource_source') + ': ' + item.source).fontSize(10).fontColor('#55FFFFFF')
                .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .height(item.description !== undefined || item.author !== undefined ? (item.hasLocation === true ? 102 : 86) : 48)
          .width('100%').padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor(this.layerViewStore.currentLandscapeId === item.id ? 'rgba(80,140,200,0.18)' : 'rgba(0,0,0,0)')
          .borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onSelectLandscape(item.id, item.name) })
        }, (item: LandscapeItem, index: number) => item.id)
      }
      .width('100%')
      Row() {
        Text(I18n.t('i0289')).fontSize(12).fontColor(this.subColor).width(72)
        Text(this.layerViewStore.landscapeTransp + '%').fontSize(14).fontColor(this.textColor).margin({ right: 8 })
        Slider({ value: this.layerViewStore.landscapeTransp, min: 0, max: 100, step: 5, style: SliderStyle.OutSet })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1)
          .blockColor(this.accentColor)
          .trackColor(this.panelColor)
          .selectedColor(this.accentColor)
          .showSteps(false)
          .onChange((val: number) => { this.layerViewStore.landscapeTransp = Math.round(val); this.onChangeLandscapeTransparency(val) })
      }.height(34).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    }.width('100%')
  }
}

// 巡天（离线 AppGallery 构建下不渲染）。
@Component
export struct LayerSurveysTab {
  @ObjectLink layerStore: LayerStore
  @ObjectLink surveyStore: SurveyStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop lineColor: string
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onRefreshSurvey: () => void = () => {}
  onSelectSpectral: (id: string) => void = () => {}
  onCloseSpectral: () => void = () => {}

  build() {
    Column({ space: 0 }) {
      LayerSwitchRow({ label: I18n.t('s0600'), isOn: this.layerStore.hipsSurveys, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Hips_Surveys', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0601'), isOn: this.layerStore.toastSurvey, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Toast_Survey', '', value) } })
      Row() {
        Text(I18n.t('i0215')).fontSize(10).fontColor('#CC8FB6FF').width('100%').padding({ left: 2 })
      }.height(18).width('100%').margin({ top: 8 })
      LayerSpectralSection({
        surveyStore: this.surveyStore,
        textColor: this.textColor,
        subColor: this.subColor,
        accentColor: this.accentColor,
        panelColor: this.panelColor,
        lineColor: this.lineColor,
        onRefreshSurvey: () => { this.onRefreshSurvey() },
        onSelectSpectral: (id: string) => { this.onSelectSpectral(id) },
        onCloseSpectral: () => { this.onCloseSpectral() }
      })
    }.width('100%')
  }
}
