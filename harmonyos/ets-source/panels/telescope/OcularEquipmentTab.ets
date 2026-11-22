import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { TelescopeStore } from '../../state/TelescopeStore'
import { OcularInstrumentItem } from '../../pages/MainWindowModels'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 目镜面板的单个器材页（目镜 / 望远镜 / 增倍镜 / 传感器）。
// 列表即选择器：点行切换当前器材；行内「编辑」与底部删除/上移/下移操作当前器材。
// 传感器页附带实时旋转 / OAG 棱镜角，目镜页附带十字丝旋转。
@Component
export struct OcularEquipmentTab {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink store: TelescopeStore
  @Prop kind: string
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onSelectInstrument: (kind: string, index: number) => void = () => {}
  onAddEquipment: (kind: string) => void = () => {}
  onEditEquipment: (kind: string, index: number) => void = () => {}
  onDeleteEquipment: (kind: string, index: number) => void = () => {}
  onMoveEquipment: (kind: string, index: number, delta: number) => void = () => {}
  onChangeCcdRotation: (value: number, mode: SliderChangeMode) => void = () => {}
  onChangePrismRotation: (value: number, mode: SliderChangeMode) => void = () => {}
  onResetInstrument: (target: string) => void = () => {}
  onRotateReticle: (dir: string) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private selectedItem(): OcularInstrumentItem | undefined {
    const index = this.store.ocularInstrumentIndex(this.kind)
    if (index < 0) return undefined
    return this.store.ocularInstrumentItem(this.kind, index)
  }

  private selectedPosition(): number {
    const selected = this.store.ocularInstrumentIndex(this.kind)
    const items = this.store.ocularInstrumentItems(this.kind)
    for (let i = 0; i < items.length; i++) {
      if (items[i].index === selected) return i
    }
    return -1
  }

  private items(): OcularInstrumentItem[] {
    return this.store.ocularInstrumentItems(this.kind)
  }

  private canMove(delta: number): boolean {
    const position = this.selectedPosition()
    const count = this.items().length
    if (position < 0 || count < 2) return false
    const target = position + delta
    return target >= 0 && target < count
  }

  @Builder
  private sectionTitle(text: string) {
    Text(text).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
      .width('100%').padding({ left: 2 }).margin({ top: 2, bottom: 2 })
  }

  @Builder
  private addRow() {
    Row({ space: 8 }) {
      Text(this.store.ocularKindLabel(this.kind) + ' · ' + this.items().length.toString())
        .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub).layoutWeight(1)
      Button(I18n.t('ocular_equipment_add'))
        .id('ocular-equipment-add')
        .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.onAccent)
        .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL).height(34)
        .padding({ left: 12, right: 12 })
        .enabled(!this.store.ocularEquipmentBusy)
        .onClick(() => { this.onAddEquipment(this.kind) })
    }.width('100%').padding({ left: 2, right: 2 })
  }

  @Builder
  private lensNoneRow() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(I18n.t('ocular_no_lens')).fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text)
        Text(I18n.t('ocular_no_lens_hint')).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub)
          .maxLines(2)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (this.store.ocularInstrumentIndex(this.kind) < 0) {
        Text(I18n.t('ocular_equipment_current')).fontSize(10).fontColor(this.c.accent)
      }
    }.width('100%').constraintSize({ minHeight: 52 }).padding({ left: 12, right: 12 })
      .backgroundColor(this.store.ocularInstrumentIndex(this.kind) < 0 ? this.c.accentSoft : this.c.bg)
      .border({
        width: 1,
        color: this.store.ocularInstrumentIndex(this.kind) < 0 ? this.c.accent : this.c.dividerSoft
      })
      .borderRadius(UI_RADIUS_CONTROL)
      .onClick(() => { this.onSelectInstrument(this.kind, -1) })
  }

  @Builder
  private itemRow(item: OcularInstrumentItem) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(item.name.length > 0 ? item.name : this.store.ocularKindLabel(this.kind))
          .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.store.ocularInstrumentSummary(this.kind, item))
          .fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub).maxLines(1)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (this.store.ocularInstrumentIndex(this.kind) === item.index) {
        Text(I18n.t('ocular_equipment_current')).fontSize(10).fontColor(this.c.accent)
      }
      Text(I18n.t('ocular_equipment_edit'))
        .id('ocular-equipment-edit-' + item.index.toString())
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
        .height(30).padding({ left: 10, right: 10 })
        .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
        .onClick(() => { this.onEditEquipment(this.kind, item.index) })
    }
    .id('ocular-equipment-row-' + this.kind.toLowerCase() + '-' + item.index.toString())
    .width('100%').constraintSize({ minHeight: 54 }).padding({ left: 12, right: 8 })
    .backgroundColor(this.store.ocularInstrumentIndex(this.kind) === item.index ? this.c.accentSoft : this.c.bg)
    .border({
      width: 1,
      color: this.store.ocularInstrumentIndex(this.kind) === item.index ? this.c.accent : this.c.dividerSoft
    })
    .borderRadius(UI_RADIUS_CONTROL)
    .onClick(() => { this.onSelectInstrument(this.kind, item.index) })
  }

  @Builder
  private emptyState() {
    Column({ space: 6 }) {
      Text(I18n.t('ocular_no_devices')).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub)
      Text(I18n.t('ocular_equipment_empty_hint')).fontSize(panelFontSize(10, this.readableUi)).fontColor(this.c.sub)
        .maxLines(2).textAlign(TextAlign.Center)
    }.width('100%').padding({ top: 18, bottom: 18 })
      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  private actionRow() {
    Row({ space: 6 }) {
      Text(I18n.t('ocular_equipment_delete'))
        .id('ocular-equipment-delete')
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.errorText)
        .height(32).padding({ left: 10, right: 10 }).layoutWeight(1).textAlign(TextAlign.Center)
        .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
        .opacity(this.selectedItem() !== undefined ? 1 : 0.4)
        .onClick(() => {
          const index = this.store.ocularInstrumentIndex(this.kind)
          if (index >= 0) this.onDeleteEquipment(this.kind, index)
        })
      Text(I18n.t('ocular_equipment_move_up'))
        .id('ocular-equipment-move-up')
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
        .height(32).padding({ left: 10, right: 10 }).layoutWeight(1).textAlign(TextAlign.Center)
        .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
        .opacity(this.canMove(-1) ? 1 : 0.4)
        .onClick(() => {
          const index = this.store.ocularInstrumentIndex(this.kind)
          if (this.canMove(-1)) this.onMoveEquipment(this.kind, index, -1)
        })
      Text(I18n.t('ocular_equipment_move_down'))
        .id('ocular-equipment-move-down')
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
        .height(32).padding({ left: 10, right: 10 }).layoutWeight(1).textAlign(TextAlign.Center)
        .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
        .opacity(this.canMove(1) ? 1 : 0.4)
        .onClick(() => {
          const index = this.store.ocularInstrumentIndex(this.kind)
          if (this.canMove(1)) this.onMoveEquipment(this.kind, index, 1)
        })
    }.width('100%')
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
  private ccdAdjustments() {
    Column({ space: 6 }) {
      this.sliderCard(I18n.t('ocular_ccd_rotation'), this.store.ocularCcdRotation.toFixed(0) + '°',
        this.store.ocularCcdRotation, -180, 180, 1,
        (value: number, mode: SliderChangeMode) => { this.onChangeCcdRotation(value, mode) })
      if (this.selectedItem()?.hasOAG === true) {
        this.sliderCard(I18n.t('ocular_prism_rotation'), this.store.ocularCcdPrismRotation.toFixed(0) + '°',
          this.store.ocularCcdPrismRotation, -180, 180, 1,
          (value: number, mode: SliderChangeMode) => { this.onChangePrismRotation(value, mode) })
        Button(I18n.t('ocular_reset_prism'))
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(30).width('100%')
          .onClick(() => { this.onResetInstrument('prism') })
      }
    }.width('100%')
  }

  @Builder
  private ocularAdjustments() {
    Row({ space: 8 }) {
      Button(I18n.t('ocular_rotate_left'))
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
        .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
        .onClick(() => { this.onRotateReticle('counterclockwise') })
      Button(I18n.t('ocular_rotate_right'))
        .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
        .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
        .onClick(() => { this.onRotateReticle('clockwise') })
    }.width('100%')
  }

  build() {
    Column({ space: 8 }) {
      this.addRow()
      if (this.store.ocularEquipmentError.length > 0) {
        Text(this.store.ocularEquipmentError).fontSize(10).fontColor(this.c.warning).width('100%').maxLines(3)
      }
      if (this.items().length === 0 && this.kind !== 'Lens') {
        this.emptyState()
      } else {
        if (this.kind === 'Lens') {
          this.lensNoneRow()
        }
        ForEach(this.items(), (item: OcularInstrumentItem) => {
          this.itemRow(item)
        }, (item: OcularInstrumentItem) => this.kind + '-' + item.index.toString())
        this.actionRow()
      }
      if (this.selectedItem() !== undefined) {
        this.sectionTitle(I18n.t('ocular_equipment_current_settings'))
        if (this.kind === 'CCD') {
          this.ccdAdjustments()
        } else if (this.kind === 'Ocular') {
          this.ocularAdjustments()
        }
      }
    }
    .width('100%')
    .padding({ bottom: 8 })
  }
}
