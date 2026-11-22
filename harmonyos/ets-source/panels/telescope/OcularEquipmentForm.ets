import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import {
  OCULAR_EQUIPMENT_ERROR_NAME,
  OcularEquipmentDraft,
  equipmentKindCode,
  validateEquipmentDraft
} from '../../common/derive/ocularEquipment'

// 目镜面板的器材编辑浮层（新增 / 修改共用）。
// 字段按器材类别裁剪；字符串草稿与校验在 common/derive/ocularEquipment.ets，
// 本组件只负责表单布局、错误文案与提交。
@Component
export struct OcularEquipmentForm {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink draft: OcularEquipmentDraft
  @Prop kind: string
  @Prop editing: boolean
  @Prop index: number
  @Prop busy: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private error: string = ''

  onCancel: () => void = () => {}
  onSubmit: (kind: string, index: number, draft: OcularEquipmentDraft) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private errorText(code: string): string {
    if (code === OCULAR_EQUIPMENT_ERROR_NAME) return I18n.t('ocular_equipment_error_name')
    return I18n.t('ocular_equipment_error_value')
  }

  private submit(): void {
    const code = validateEquipmentDraft(equipmentKindCode(this.kind), this.draft)
    if (code.length > 0) {
      this.error = this.errorText(code)
      return
    }
    this.error = ''
    this.onSubmit(this.kind, this.editing ? this.index : -1, this.draft)
  }

  @Builder
  private sectionTitle(text: string) {
    Text(text).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
      .width('100%').padding({ left: 2 }).margin({ top: 2 })
  }

  @Builder
  private textField(label: string, value: string, onChange: (value: string) => void, decimal: boolean,
    placeholder: string) {
    Column({ space: 4 }) {
      Text(label).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).maxLines(1)
      TextInput({ text: value, placeholder: placeholder })
        .type(decimal ? InputType.NUMBER_DECIMAL : InputType.Number)
        .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text)
        .height(38).width('100%').padding({ left: 10, right: 10 })
        .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
        .onChange((next: string) => { onChange(next) })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private nameField() {
    Column({ space: 4 }) {
      Text(I18n.t('ocular_equipment_name')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
      TextInput({ text: this.draft.name, placeholder: I18n.t('ocular_equipment_name_placeholder') })
        .id('ocular-equipment-form-name')
        .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text)
        .height(38).width('100%').padding({ left: 10, right: 10 })
        .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
        .maxLength(40)
        .onChange((value: string) => { this.draft.name = value })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private switchRow(label: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
        .maxLines(2)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .enabled(!this.busy)
        .onChange((value: boolean) => { onChange(value) })
    }.width('100%').constraintSize({ minHeight: 44 }).padding({ left: 10, right: 10 })
      .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  private fieldRow(left: string, leftValue: string, leftChange: (value: string) => void, leftDecimal: boolean,
    right: string, rightValue: string, rightChange: (value: string) => void, rightDecimal: boolean) {
    Row({ space: 8 }) {
      Column() {
        this.textField(left, leftValue, leftChange, leftDecimal, '')
      }.layoutWeight(1)
      Column() {
        this.textField(right, rightValue, rightChange, rightDecimal, '')
      }.layoutWeight(1)
    }.width('100%')
  }

  @Builder
  private ocularFields() {
    this.textField(I18n.t('ocular_equipment_apparent_fov'), this.draft.apparentFov,
      (value: string) => { this.draft.apparentFov = value }, true, '50')
    this.fieldRow(I18n.t('ocular_equipment_focal_length'), this.draft.focalLength,
      (value: string) => { this.draft.focalLength = value }, true,
      I18n.t('ocular_equipment_field_stop'), this.draft.fieldStop,
      (value: string) => { this.draft.fieldStop = value }, true)
    this.switchRow(I18n.t('ocular_equipment_binocular'), this.draft.binocular,
      (value: boolean) => { this.draft.binocular = value })
    this.switchRow(I18n.t('ocular_equipment_permanent_crosshair'), this.draft.permanentCrosshair,
      (value: boolean) => { this.draft.permanentCrosshair = value })
  }

  @Builder
  private lensFields() {
    this.textField(I18n.t('ocular_equipment_multiplier'), this.draft.multiplier,
      (value: string) => { this.draft.multiplier = value }, true, '2')
  }

  @Builder
  private telescopeFields() {
    this.fieldRow(I18n.t('ocular_equipment_diameter'), this.draft.diameter,
      (value: string) => { this.draft.diameter = value }, true,
      I18n.t('ocular_equipment_focal_length'), this.draft.focalLength,
      (value: string) => { this.draft.focalLength = value }, true)
    this.switchRow(I18n.t('ocular_equipment_horizontal_flipped'), this.draft.horizontalFlipped,
      (value: boolean) => { this.draft.horizontalFlipped = value })
    this.switchRow(I18n.t('ocular_equipment_vertical_flipped'), this.draft.verticalFlipped,
      (value: boolean) => { this.draft.verticalFlipped = value })
    this.switchRow(I18n.t('ocular_equipment_equatorial'), this.draft.equatorial,
      (value: boolean) => { this.draft.equatorial = value })
  }

  @Builder
  private ccdFields() {
    this.fieldRow(I18n.t('ocular_equipment_resolution_x'), this.draft.resolutionX,
      (value: string) => { this.draft.resolutionX = value }, false,
      I18n.t('ocular_equipment_resolution_y'), this.draft.resolutionY,
      (value: string) => { this.draft.resolutionY = value }, false)
    this.fieldRow(I18n.t('ocular_equipment_chip_width'), this.draft.chipWidth,
      (value: string) => { this.draft.chipWidth = value }, true,
      I18n.t('ocular_equipment_chip_height'), this.draft.chipHeight,
      (value: string) => { this.draft.chipHeight = value }, true)
    this.fieldRow(I18n.t('ocular_equipment_binning_x'), this.draft.binningX,
      (value: string) => { this.draft.binningX = value }, false,
      I18n.t('ocular_equipment_binning_y'), this.draft.binningY,
      (value: string) => { this.draft.binningY = value }, false)
    this.textField(I18n.t('ocular_equipment_rotation'), this.draft.rotation,
      (value: string) => { this.draft.rotation = value }, true, '0')
    this.switchRow(I18n.t('ocular_equipment_has_oag'), this.draft.hasOAG,
      (value: boolean) => { this.draft.hasOAG = value })
    if (this.draft.hasOAG) {
      this.fieldRow(I18n.t('ocular_equipment_prism_height'), this.draft.prismHeight,
        (value: string) => { this.draft.prismHeight = value }, true,
        I18n.t('ocular_equipment_prism_width'), this.draft.prismWidth,
        (value: string) => { this.draft.prismWidth = value }, true)
      this.fieldRow(I18n.t('ocular_equipment_prism_distance'), this.draft.prismDistance,
        (value: string) => { this.draft.prismDistance = value }, true,
        I18n.t('ocular_equipment_prism_pos_angle'), this.draft.prismPosAngle,
        (value: string) => { this.draft.prismPosAngle = value }, true)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.55)')
        .onClick(() => { if (!this.busy) this.onCancel() })
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(this.editing ? I18n.t('ocular_equipment_edit_title') : I18n.t('ocular_equipment_new_title'))
              .fontSize(panelFontSize(15, this.readableUi)).fontColor(this.c.text).fontWeight(FontWeight.Medium)
            Text(I18n.t(this.kind === 'Lens' ? 'ocular_device_lens' :
              (this.kind === 'CCD' ? 'ocular_device_sensor' :
                (this.kind === 'Telescope' ? 'ocular_device_telescope' : 'ocular_device_ocular'))))
              .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('✕')
            .fontSize(15).fontColor(this.c.sub).width(30).height(30).textAlign(TextAlign.Center)
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { if (!this.busy) this.onCancel() })
        }.width('100%')

        Scroll() {
          Column({ space: 8 }) {
            this.nameField()
            if (this.kind === 'Ocular') {
              this.ocularFields()
            } else if (this.kind === 'Lens') {
              this.lensFields()
            } else if (this.kind === 'Telescope') {
              this.telescopeFields()
            } else {
              this.ccdFields()
            }
            if (this.error.length > 0) {
              Text(this.error).fontSize(11).fontColor(this.c.errorText).width('100%')
            }
          }.width('100%').padding({ bottom: 4 })
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(3)

        Row({ space: 10 }) {
          Button(I18n.t('loc_cancel'))
            .id('ocular-equipment-form-cancel')
            .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text)
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).height(38).layoutWeight(1)
            .enabled(!this.busy)
            .onClick(() => { this.onCancel() })
          Button(I18n.t('ocular_equipment_form_save'))
            .id('ocular-equipment-form-save')
            .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.onAccent)
            .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL).height(38).layoutWeight(1)
            .enabled(!this.busy)
            .onClick(() => { this.submit() })
        }.width('100%')
      }
      .id('ocular-equipment-form')
      .width('90%')
      .height('76%')
      .padding(16)
      .backgroundColor(this.c.isNight ? '#150505' : '#101E2C')
      .border({ width: 1, color: this.c.border })
      .borderRadius(18)
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)' })
    }
    .width('100%').height('100%')
  }
}
