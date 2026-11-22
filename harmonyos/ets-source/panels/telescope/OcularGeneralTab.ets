import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { TelescopeStore } from '../../state/TelescopeStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { OcularMetric } from './OcularMetric'

// 目镜面板「通用」页：模式、结果、画面、传感器、Telrad、行为与配置管理。
// 所有开关沿用原有的桥回调；本组件只负责分组呈现。
@Component
export struct OcularGeneralTab {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink store: TelescopeStore
  @Prop @Watch('syncTelradDraft') telradFov: number[] = [0.5, 2, 4, 0]
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private telradDraft: string[] = ['0.5', '2', '4', '0']
  @State private telradError: string = ''

  onOpenSubPanel: (name: string) => void = () => {}
  onSetOcularMode: (isOn: boolean) => void = () => {}
  onSetTelrad: (isOn: boolean) => void = () => {}
  onSetCrosshairs: (isOn: boolean) => void = () => {}
  onSetCcd: (isOn: boolean) => void = () => {}
  onSetOcularSetting: (setting: string, isOn: boolean) => void = () => {}
  onChangeMaskOpacity: (value: number, mode: SliderChangeMode) => void = () => {}
  onChangeCropSize: (setting: string, value: number, mode: SliderChangeMode) => void = () => {}
  onSetTelradFov: (values: number[]) => void = () => {}
  onExportEquipment: () => void = () => {}
  onImportEquipment: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  aboutToAppear(): void {
    this.syncTelradDraft()
  }

  private syncTelradDraft(): void {
    const values: number[] = this.telradFov.length >= 4 ? this.telradFov : [0.5, 2, 4, 0]
    this.telradDraft = [values[0].toString(), values[1].toString(), values[2].toString(), values[3].toString()]
  }

  private applyTelradDraft(): void {
    const values: number[] = []
    for (let i = 0; i < 4; i++) {
      const parsed = Number(this.telradDraft[i])
      if (!Number.isFinite(parsed) || parsed < 0 || parsed > 30) {
        this.telradError = I18n.t('ocular_equipment_error_value')
        return
      }
      values.push(parsed)
    }
    this.telradError = ''
    this.onSetTelradFov(values)
  }

  private resetTelradFov(): void {
    this.telradDraft = ['0.5', '2', '4', '0']
    this.telradError = ''
    this.onSetTelradFov([0.5, 2, 4, 0])
  }

  @Builder
  private sectionTitle(text: string) {
    Text(text).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
      .width('100%').padding({ left: 2 }).margin({ top: 2, bottom: 2 })
  }

  @Builder
  private switchRow(label: string, isOn: boolean, enabled: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label).fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .enabled(enabled)
        .onChange((value: boolean) => { onChange(value) })
    }.width('100%').constraintSize({ minHeight: 44 }).padding({ left: 10, right: 10 })
      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  private sliderCard(label: string, valueText: string, value: number, min: number, max: number, step: number,
    onChange: (value: number, mode: SliderChangeMode) => void) {
    Column({ space: 6 }) {
      Row() {
        Text(label).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        Text(valueText).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
      }.width('100%')
      Slider({ value: value, min: min, max: max, step: step, style: SliderStyle.OutSet })
        .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
        .width('100%').trackColor(this.c.bg)
        .onChange((next: number, mode: SliderChangeMode) => { onChange(next, mode) })
    }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  private equipmentFileRow() {
    Row({ space: 8 }) {
      Button(I18n.t('ocular_equipment_export'))
        .id('ocular-equipment-export')
        .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
        .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(38).layoutWeight(1)
        .enabled(!this.store.ocularEquipmentBusy)
        .onClick(() => { this.onExportEquipment() })
      Button(I18n.t('ocular_equipment_import'))
        .id('ocular-equipment-import')
        .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
        .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(38).layoutWeight(1)
        .enabled(!this.store.ocularEquipmentBusy)
        .onClick(() => { this.onImportEquipment() })
    }.width('100%')
  }

  build() {
    Column({ space: 8 }) {
      if (this.store.ocularRequireSelection && !this.store.ocularHasSelection) {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(I18n.t('ocular_select_target_title')).fontSize(panelFontSize(12, this.readableUi))
              .fontColor(this.c.text).fontWeight(FontWeight.Medium)
            Text(I18n.t('ocular_select_target_hint')).fontSize(panelFontSize(10, this.readableUi))
              .fontColor(this.c.sub).maxLines(2)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button(I18n.t('ocular_choose_target')).fontSize(panelFontSize(11, this.readableUi))
            .fontColor(this.c.onAccent).height(32)
            .padding({ left: 12, right: 12 }).backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onOpenSubPanel('search') })
        }.width('100%').padding({ left: 12, right: 10, top: 10, bottom: 10 })
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
      }

      this.sectionTitle(I18n.t('ocular_section_modes'))
      this.switchRow(I18n.t('c_ocular_mode'), this.store.ocularMode, this.store.ocularReady,
        (value: boolean) => { this.onSetOcularMode(value) })
      this.switchRow(I18n.t('c_telrad'), this.store.telradOn, true,
        (value: boolean) => { this.onSetTelrad(value) })
      this.switchRow(I18n.t('c_crosshair'), this.store.crosshairsOn, true,
        (value: boolean) => { this.onSetCrosshairs(value) })
      this.switchRow(I18n.t('c_ccd_frame'), this.store.ccdOn, this.store.ocularCcdReady,
        (value: boolean) => { this.onSetCcd(value) })

      if (this.store.ocularMagnification > 0 || this.store.ocularCcdFovX > 0) {
        this.sectionTitle(I18n.t('ocular_section_result'))
        Column({ space: 9 }) {
          if (this.store.ocularMagnification > 0) {
            Row({ space: 12 }) {
              OcularMetric({ label: I18n.t('ocular_magnification'), value: this.store.ocularMagnification.toFixed(1) + '×' })
              OcularMetric({ label: I18n.t('ocular_actual_fov'), value: this.store.ocularActualFov.toFixed(3) + '°' })
            }.width('100%')
            Row({ space: 12 }) {
              OcularMetric({ label: I18n.t('ocular_exit_pupil'), value: this.store.ocularExitPupil.toFixed(2) + ' mm' })
              OcularMetric({ label: I18n.t('ocular_limit_magnitude'), value: this.store.ocularLimitMagnitude.toFixed(1) + ' mag' })
            }.width('100%')
          }
          if (this.store.ocularCcdFovX > 0) {
            Row({ space: 12 }) {
              OcularMetric({
                label: I18n.t('ocular_ccd_fov'),
                value: this.store.ocularCcdFovX.toFixed(3) + '° × ' + this.store.ocularCcdFovY.toFixed(3) + '°'
              })
              OcularMetric({ label: I18n.t('ocular_pixel_scale'), value: this.store.ocularCcdPixelScaleX.toFixed(2) + '"/px' })
            }.width('100%')
          }
        }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
      }

      this.sectionTitle(I18n.t('ocular_section_view'))
      this.switchRow(I18n.t('ocular_scale_image_circle'), this.store.ocularScaleImageCircle, true,
        (value: boolean) => { this.onSetOcularSetting('scaleImageCircle', value) })
      this.switchRow(I18n.t('ocular_semi_transparent_mask'), this.store.ocularSemiTransparentMask, true,
        (value: boolean) => { this.onSetOcularSetting('semiTransparentMask', value) })
      if (this.store.ocularSemiTransparentMask) {
        this.sliderCard(I18n.t('ocular_mask_opacity'), this.store.ocularMaskOpacity.toString() + '%',
          this.store.ocularMaskOpacity, 0, 100, 1,
          (value: number, mode: SliderChangeMode) => { this.onChangeMaskOpacity(value, mode) })
      }
      this.switchRow(I18n.t('ocular_show_contour'), this.store.ocularShowContour, true,
        (value: boolean) => { this.onSetOcularSetting('showContour', value) })
      this.switchRow(I18n.t('ocular_show_cardinals'), this.store.ocularShowCardinals, true,
        (value: boolean) => { this.onSetOcularSetting('showCardinals', value) })
      this.switchRow(I18n.t('ocular_align_crosshair'), this.store.ocularAlignCrosshair, true,
        (value: boolean) => { this.onSetOcularSetting('alignCrosshair', value) })
      this.switchRow(I18n.t('ocular_resolution_criteria'), this.store.ocularShowResolutionCriteria, true,
        (value: boolean) => { this.onSetOcularSetting('showResolutionCriteria', value) })
      this.switchRow(I18n.t('ocular_hide_grids'), this.store.ocularHideGridsLines, true,
        (value: boolean) => { this.onSetOcularSetting('hideGridsLines', value) })

      this.sectionTitle(I18n.t('ocular_section_sensor'))
      this.switchRow(I18n.t('ocular_auto_mount'), this.store.ocularAutoSetMountForCcd, this.store.ocularCcdReady,
        (value: boolean) => { this.onSetOcularSetting('autoSetMountForCcd', value) })
      this.switchRow(I18n.t('ocular_sensor_crop'), this.store.ocularSensorCropOverlay, this.store.ocularCcdReady,
        (value: boolean) => { this.onSetOcularSetting('sensorCropOverlay', value) })
      this.switchRow(I18n.t('ocular_sensor_pixel_grid'), this.store.ocularSensorPixelGrid,
        this.store.ocularCcdReady && this.store.ocularSensorCropOverlay,
        (value: boolean) => { this.onSetOcularSetting('sensorPixelGrid', value) })
      if (this.store.ocularCcdReady && this.store.ocularSensorCropOverlay) {
        Column({ space: 5 }) {
          this.sliderCard(I18n.t('ocular_crop_horizontal'), this.store.ocularCcdCropHSize.toString() + ' px',
            this.store.ocularCcdCropHSize, 1, 1000, 1,
            (value: number, mode: SliderChangeMode) => { this.onChangeCropSize('ccdCropHSize', value, mode) })
          this.sliderCard(I18n.t('ocular_crop_vertical'), this.store.ocularCcdCropVSize.toString() + ' px',
            this.store.ocularCcdCropVSize, 1, 1000, 1,
            (value: number, mode: SliderChangeMode) => { this.onChangeCropSize('ccdCropVSize', value, mode) })
        }.width('100%')
      }
      this.switchRow(I18n.t('ocular_focuser_overlay'), this.store.ocularFocuserOverlay, this.store.ocularCcdReady,
        (value: boolean) => { this.onSetOcularSetting('focuserOverlay', value) })
      if (this.store.ocularFocuserOverlay && this.store.ocularCcdReady) {
        this.switchRow(I18n.t('ocular_focuser_small'), this.store.ocularSmallFocuserOverlay, true,
          (value: boolean) => { this.onSetOcularSetting('smallFocuserOverlay', value) })
        this.switchRow(I18n.t('ocular_focuser_medium'), this.store.ocularMediumFocuserOverlay, true,
          (value: boolean) => { this.onSetOcularSetting('mediumFocuserOverlay', value) })
        this.switchRow(I18n.t('ocular_focuser_large'), this.store.ocularLargeFocuserOverlay, true,
          (value: boolean) => { this.onSetOcularSetting('largeFocuserOverlay', value) })
      }
      this.switchRow(I18n.t('ocular_max_exposure'), this.store.ocularMaxExposureTimeForCcd, this.store.ocularCcdReady,
        (value: boolean) => { this.onSetOcularSetting('maxExposureTimeForCcd', value) })
      this.switchRow(I18n.t('ocular_oag_limits'), this.store.ocularOagLimits, this.store.ocularCcdReady,
        (value: boolean) => { this.onSetOcularSetting('oagLimits', value) })
      this.switchRow(I18n.t('ocular_horizontal_coordinates'), this.store.ocularHorizontalCoordinates, true,
        (value: boolean) => { this.onSetOcularSetting('horizontalCoordinates', value) })
      this.switchRow(I18n.t('ocular_dms_degrees'), this.store.ocularDmsDegrees, true,
        (value: boolean) => { this.onSetOcularSetting('dmsDegrees', value) })
      this.switchRow(I18n.t('ocular_ccd_center'), this.store.ocularCcdCenter, true,
        (value: boolean) => { this.onSetOcularSetting('ccdCenter', value) })

      this.sectionTitle(I18n.t('ocular_section_telrad'))
      this.switchRow(I18n.t('ocular_auto_scale_telrad'), this.store.ocularAutoScaleTelrad, true,
        (value: boolean) => { this.onSetOcularSetting('autoScaleTelrad', value) })
      Row({ space: 6 }) {
        ForEach([0, 1, 2, 3], (index: number) => {
          Column({ space: 3 }) {
            Text((index + 1).toString()).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub)
            TextInput({ text: this.telradDraft[index] })
              .id('ocular-telrad-fov-' + index.toString())
              .type(InputType.NUMBER_DECIMAL)
              .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
              .height(34).width('100%').padding({ left: 4, right: 4 })
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              .onChange((value: string) => { this.telradDraft[index] = value })
          }.layoutWeight(1)
        }, (index: number) => 'telrad-' + index.toString())
      }.width('100%')
      if (this.telradError.length > 0) {
        Text(this.telradError).fontSize(10).fontColor(this.c.warning).width('100%')
      }
      Row({ space: 8 }) {
        Button(I18n.t('ocular_telrad_apply'))
          .id('ocular-telrad-apply')
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.onAccent)
          .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
          .onClick(() => { this.applyTelradDraft() })
        Button(I18n.t('ocular_telrad_reset'))
          .id('ocular-telrad-reset')
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
          .onClick(() => { this.resetTelradFov() })
      }.width('100%')

      this.sectionTitle(I18n.t('ocular_section_behavior'))
      this.switchRow(I18n.t('ocular_require_selection'), this.store.ocularRequireSelection, true,
        (value: boolean) => { this.onSetOcularSetting('requireSelection', value) })
      this.switchRow(I18n.t('ocular_auto_limit'), this.store.ocularAutoLimitMagnitude, true,
        (value: boolean) => { this.onSetOcularSetting('autoLimitMagnitude', value) })
      this.switchRow(I18n.t('ocular_auto_scale_ccd'), this.store.ocularAutoScaleCcd, true,
        (value: boolean) => { this.onSetOcularSetting('autoScaleCcd', value) })
      this.switchRow(I18n.t('ocular_init_fov'), this.store.ocularInitFov, true,
        (value: boolean) => { this.onSetOcularSetting('initFov', value) })
      this.switchRow(I18n.t('ocular_init_direction'), this.store.ocularInitDirection, true,
        (value: boolean) => { this.onSetOcularSetting('initDirection', value) })

      this.sectionTitle(I18n.t('ocular_section_config'))
      this.equipmentFileRow()
      if (this.store.ocularEquipmentError.length > 0) {
        Text(this.store.ocularEquipmentError).fontSize(10).fontColor(this.c.warning).width('100%').maxLines(3)
      }
    }
    .width('100%')
    .padding({ bottom: 8 })
  }
}
