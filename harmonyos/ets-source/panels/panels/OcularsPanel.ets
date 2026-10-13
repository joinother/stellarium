// 「目镜（Oculars）」面板，对应 `activePanel === 'oculars'`。
//
// 望远镜设备状态来自 TelescopeStore（@ObjectLink），主题色走 @Prop；
// 设备选择 / 开关 / 滑块 / 旋转 / 复位等动作回调注入宿主。
import { I18n } from '../../pages/I18n'
import { TelescopeStore } from '../../state/TelescopeStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { OcularMetric } from '../telescope/OcularMetric'
import { OcularSelector } from '../telescope/OcularSelector'

@Component
export struct OcularsPanel {
  @ObjectLink store: TelescopeStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop lineColor: string
  onOpenSubPanel: (name: string) => void = () => {}
  onSetOcularMode: (isOn: boolean) => void = () => {}
  onSetTelrad: (isOn: boolean) => void = () => {}
  onSetCrosshairs: (isOn: boolean) => void = () => {}
  onSetCcd: (isOn: boolean) => void = () => {}
  onSelectInstrument: (kind: string, index: number) => void = () => {}
  onChangeCcdRotation: (value: number, mode: SliderChangeMode) => void = () => {}
  onChangePrismRotation: (value: number, mode: SliderChangeMode) => void = () => {}
  onResetInstrument: (target: string) => void = () => {}
  onRotateReticle: (dir: string) => void = () => {}
  onSetOcularSetting: (setting: string, isOn: boolean) => void = () => {}
  onChangeMaskOpacity: (value: number, mode: SliderChangeMode) => void = () => {}
  onChangeCropSize: (setting: string, value: number, mode: SliderChangeMode) => void = () => {}

  build() {
      Scroll() {
        Column({ space: 12 }) {
          if (this.store.ocularLoading) {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18).color(this.accentColor)
              Text(I18n.t('ocular_status_loading')).fontSize(11).fontColor(this.subColor)
            }.width('100%').height(44).justifyContent(FlexAlign.Center)
          }
          if (this.store.ocularStatusMessage.length > 0) {
            Text(this.store.ocularStatusMessage).fontSize(11).fontColor('#FFD59A').width('100%').maxLines(3)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor('rgba(194, 128, 36, 0.14)').borderRadius(UI_RADIUS_CONTROL)
          }
          if (this.store.ocularRequireSelection && !this.store.ocularHasSelection) {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(I18n.t('ocular_select_target_title')).fontSize(12).fontColor(this.textColor).fontWeight(FontWeight.Medium)
                Text(I18n.t('ocular_select_target_hint')).fontSize(10).fontColor(this.subColor).maxLines(2)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Button(I18n.t('ocular_choose_target')).fontSize(11).fontColor('#FFFFFF').height(32)
                .padding({ left: 12, right: 12 }).backgroundColor(this.accentColor).borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onOpenSubPanel('search') })
            }.width('100%').padding({ left: 12, right: 10, top: 10, bottom: 10 })
              .backgroundColor('rgba(91,147,191,0.16)').borderRadius(UI_RADIUS_CONTROL)
          }
          Text(I18n.t('ocular_section_modes')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
          Row() {
            Text(I18n.t('c_ocular_mode')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularMode })
              .enabled(this.store.ocularReady)
              .onChange((isOn: boolean) => { this.onSetOcularMode(isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('c_telrad')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.telradOn })
              .onChange((isOn: boolean) => { this.onSetTelrad(isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('c_crosshair')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.crosshairsOn })
              .onChange((isOn: boolean) => { this.onSetCrosshairs(isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('c_ccd_frame')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ccdOn })
              .enabled(this.store.ocularCcdReady)
              .onChange((isOn: boolean) => { this.onSetCcd(isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          if (this.store.ocularMagnification > 0 || this.store.ocularCcdFovX > 0) {
            Text(I18n.t('ocular_section_result')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 2 })
            Column({ space: 9 }) {
              if (this.store.ocularMagnification > 0) {
                Row({ space: 12 }) {
                  OcularMetric({ label: I18n.t('ocular_magnification'), value: this.store.ocularMagnification.toFixed(1) + '×', subColor: this.subColor, textColor: this.textColor })
                  OcularMetric({ label: I18n.t('ocular_actual_fov'), value: this.store.ocularActualFov.toFixed(3) + '°', subColor: this.subColor, textColor: this.textColor })
                }.width('100%')
                Row({ space: 12 }) {
                  OcularMetric({ label: I18n.t('ocular_exit_pupil'), value: this.store.ocularExitPupil.toFixed(2) + ' mm', subColor: this.subColor, textColor: this.textColor })
                  OcularMetric({ label: I18n.t('ocular_limit_magnitude'), value: this.store.ocularLimitMagnitude.toFixed(1) + ' mag', subColor: this.subColor, textColor: this.textColor })
                }.width('100%')
              }
              if (this.store.ocularCcdFovX > 0) {
                Row({ space: 12 }) {
                  OcularMetric({ label: I18n.t('ocular_ccd_fov'), value: this.store.ocularCcdFovX.toFixed(3) + '° × ' + this.store.ocularCcdFovY.toFixed(3) + '°', subColor: this.subColor, textColor: this.textColor })
                  OcularMetric({ label: I18n.t('ocular_pixel_scale'), value: this.store.ocularCcdPixelScaleX.toFixed(2) + '"/px', subColor: this.subColor, textColor: this.textColor })
                }.width('100%')
              }
            }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor('rgba(91,147,191,0.10)').borderRadius(UI_RADIUS_CONTROL)
          }
          Text(I18n.t('ocular_section_devices')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 2 })
          OcularSelector({ store: this.store, kind: 'Ocular', label: I18n.t('ocular_device_ocular'), subColor: this.subColor, textColor: this.textColor, panelColor: this.panelColor, accentColor: this.accentColor, lineColor: this.lineColor, onSelect: (kind: string, index: number) => { this.onSelectInstrument(kind, index) } })
          OcularSelector({ store: this.store, kind: 'Telescope', label: I18n.t('ocular_device_telescope'), subColor: this.subColor, textColor: this.textColor, panelColor: this.panelColor, accentColor: this.accentColor, lineColor: this.lineColor, onSelect: (kind: string, index: number) => { this.onSelectInstrument(kind, index) } })
          OcularSelector({ store: this.store, kind: 'Lens', label: I18n.t('ocular_device_lens'), subColor: this.subColor, textColor: this.textColor, panelColor: this.panelColor, accentColor: this.accentColor, lineColor: this.lineColor, onSelect: (kind: string, index: number) => { this.onSelectInstrument(kind, index) } })
          OcularSelector({ store: this.store, kind: 'CCD', label: 'CCD', subColor: this.subColor, textColor: this.textColor, panelColor: this.panelColor, accentColor: this.accentColor, lineColor: this.lineColor, onSelect: (kind: string, index: number) => { this.onSelectInstrument(kind, index) } })
          if (this.store.ocularCcdReady && this.store.ccdIndex >= 0) {
            Column({ space: 6 }) {
              Row() {
                Text(I18n.t('ocular_ccd_rotation')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
                Text(this.store.ocularCcdRotation.toFixed(0) + '°').fontSize(11).fontColor(this.subColor)
              }.width('100%')
              Slider({ value: this.store.ocularCcdRotation, min: -180, max: 180, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .width('100%').blockColor(this.accentColor).selectedColor(this.accentColor).trackColor(this.panelColor)
                .onChange((value: number, mode: SliderChangeMode) => { this.onChangeCcdRotation(value, mode) })
            }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          }
          if (this.store.ocularCcdReady && this.store.ccdIndex >= 0) {
            Column({ space: 6 }) {
              Row() {
                Text(I18n.t('ocular_prism_rotation')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
                Text(this.store.ocularCcdPrismRotation.toFixed(0) + '°').fontSize(11).fontColor(this.subColor)
              }.width('100%')
              Slider({ value: this.store.ocularCcdPrismRotation, min: -180, max: 180, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .width('100%').blockColor(this.accentColor).selectedColor(this.accentColor).trackColor(this.panelColor)
                .onChange((value: number, mode: SliderChangeMode) => { this.onChangePrismRotation(value, mode) })
              Button(I18n.t('ocular_reset_prism')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL).height(28).width('100%')
                .onClick(() => { this.onResetInstrument('prism') })
            }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          }
          Row({ space: 8 }) {
            Button(I18n.t('ocular_rotate_left')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1)
              .onClick(() => { this.onRotateReticle('counterclockwise') })
            Button(I18n.t('ocular_rotate_right')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1)
              .onClick(() => { this.onRotateReticle('clockwise') })
          }.width('100%')
          Text(I18n.t('ocular_section_advanced')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 2 })
          Row() {
            Text(I18n.t('ocular_semi_transparent_mask')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularSemiTransparentMask })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('semiTransparentMask', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          if (this.store.ocularSemiTransparentMask) {
            Column({ space: 6 }) {
              Row() {
                Text(I18n.t('ocular_mask_opacity')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
                Text(this.store.ocularMaskOpacity.toString() + '%').fontSize(11).fontColor(this.subColor)
              }.width('100%')
              Slider({ value: this.store.ocularMaskOpacity, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .width('100%').blockColor(this.accentColor).selectedColor(this.accentColor).trackColor(this.panelColor)
                .onChange((value: number, mode: SliderChangeMode) => { this.onChangeMaskOpacity(value, mode) })
            }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          }
          Row() {
            Text(I18n.t('ocular_resolution_criteria')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularShowResolutionCriteria })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('showResolutionCriteria', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_auto_mount')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularAutoSetMountForCcd })
              .enabled(this.store.ocularCcdReady)
              .onChange((isOn: boolean) => { this.onSetOcularSetting('autoSetMountForCcd', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_horizontal_coordinates')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularHorizontalCoordinates })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('horizontalCoordinates', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_sensor_crop')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularSensorCropOverlay })
              .enabled(this.store.ocularCcdReady)
              .onChange((isOn: boolean) => { this.onSetOcularSetting('sensorCropOverlay', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_sensor_pixel_grid')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularSensorPixelGrid })
              .enabled(this.store.ocularCcdReady && this.store.ocularSensorCropOverlay)
              .onChange((isOn: boolean) => { this.onSetOcularSetting('sensorPixelGrid', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          if (this.store.ocularCcdReady && this.store.ocularSensorCropOverlay) {
            Column({ space: 5 }) {
              Row() {
                Text(I18n.t('ocular_crop_horizontal')).fontSize(11).fontColor(this.textColor).layoutWeight(1)
                Text(this.store.ocularCcdCropHSize.toString() + ' px').fontSize(10).fontColor(this.subColor)
              }.width('100%')
              Slider({ value: this.store.ocularCcdCropHSize, min: 1, max: 1000, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .onChange((value: number, mode: SliderChangeMode) => { this.onChangeCropSize('ccdCropHSize', value, mode) })
              Row() {
                Text(I18n.t('ocular_crop_vertical')).fontSize(11).fontColor(this.textColor).layoutWeight(1)
                Text(this.store.ocularCcdCropVSize.toString() + ' px').fontSize(10).fontColor(this.subColor)
              }.width('100%')
              Slider({ value: this.store.ocularCcdCropVSize, min: 1, max: 1000, step: 1, style: SliderStyle.OutSet })
                .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .onChange((value: number, mode: SliderChangeMode) => { this.onChangeCropSize('ccdCropVSize', value, mode) })
            }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          }
          Row() {
            Text(I18n.t('ocular_focuser_overlay')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularFocuserOverlay })
              .enabled(this.store.ocularCcdReady)
              .onChange((isOn: boolean) => { this.onSetOcularSetting('focuserOverlay', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_scale_image_circle')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularScaleImageCircle })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('scaleImageCircle', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_show_contour')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularShowContour })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('showContour', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_show_cardinals')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularShowCardinals })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('showCardinals', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_align_crosshair')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularAlignCrosshair })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('alignCrosshair', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_oag_limits')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularOagLimits })
              .enabled(this.store.ocularCcdReady)
              .onChange((isOn: boolean) => { this.onSetOcularSetting('oagLimits', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_dms_degrees')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularDmsDegrees })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('dmsDegrees', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_init_fov')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularInitFov })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('initFov', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_init_direction')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularInitDirection })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('initDirection', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_max_exposure')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularMaxExposureTimeForCcd })
              .enabled(this.store.ocularCcdReady)
              .onChange((isOn: boolean) => { this.onSetOcularSetting('maxExposureTimeForCcd', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          if (this.store.ocularFocuserOverlay && this.store.ocularCcdReady) {
            Text(I18n.t('ocular_focuser_size')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 2 })
            Row() {
              Text(I18n.t('ocular_focuser_small')).fontSize(11).fontColor(this.textColor).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.store.ocularSmallFocuserOverlay })
                .onChange((isOn: boolean) => { this.onSetOcularSetting('smallFocuserOverlay', isOn) })
            }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Text(I18n.t('ocular_focuser_medium')).fontSize(11).fontColor(this.textColor).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.store.ocularMediumFocuserOverlay })
                .onChange((isOn: boolean) => { this.onSetOcularSetting('mediumFocuserOverlay', isOn) })
            }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
            Row() {
              Text(I18n.t('ocular_focuser_large')).fontSize(11).fontColor(this.textColor).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.store.ocularLargeFocuserOverlay })
                .onChange((isOn: boolean) => { this.onSetOcularSetting('largeFocuserOverlay', isOn) })
            }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          }
          Text(I18n.t('ocular_section_behavior')).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 }).margin({ top: 2 })
          Row() {
            Text(I18n.t('ocular_require_selection')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularRequireSelection })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('requireSelection', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_auto_limit')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularAutoLimitMagnitude })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('autoLimitMagnitude', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_hide_grids')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularHideGridsLines })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('hideGridsLines', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_auto_scale_telrad')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularAutoScaleTelrad })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('autoScaleTelrad', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          Row() {
            Text(I18n.t('ocular_auto_scale_ccd')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.ocularAutoScaleCcd })
              .onChange((isOn: boolean) => { this.onSetOcularSetting('autoScaleCcd', isOn) })
          }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }
}
