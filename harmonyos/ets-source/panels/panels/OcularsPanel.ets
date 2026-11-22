import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { TelescopeStore } from '../../state/TelescopeStore'
import { TabItem } from '../../pages/StellariumTypes'
import { OcularInstrumentItem } from '../../pages/MainWindowModels'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { MediaSaveResult } from '../../bridge/MediaPort'
import { OcularSummaryCard } from '../telescope/OcularSummaryCard'
import { OcularsTabs } from '../telescope/OcularsTabs'
import { OcularGeneralTab } from '../telescope/OcularGeneralTab'
import { OcularEquipmentTab } from '../telescope/OcularEquipmentTab'
import { OcularEquipmentForm } from '../telescope/OcularEquipmentForm'
import {
  OcularEquipmentDraft, emptyEquipmentDraft, equipmentDraftFromItem, equipmentIndexPayload,
  equipmentKindCode, equipmentMovePayload, equipmentMutationPayload
} from '../../common/derive/ocularEquipment'

// 「目镜（Oculars）」面板：当前组合摘要 + 页签（通用 / 目镜 / 增倍镜 / 传感器 / 望远镜 / 关于）。
// 通用页承载模式、叠加、传感器与 Telrad 设置；器材页承载列表 CRUD 与类别专属调整。
// 器材编辑、导入方式选择走 bindContentCover 居中浮层；文件读写由宿主回调完成。
@Component
export struct OcularsPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink store: TelescopeStore
  @Prop @Watch('onEditorRequestChanged') editorRequest: string = ''
  @Prop @Watch('onScrollRequestChanged') scrollRequest: string = ''
  @State private c: ThemeSlots = DEFAULT_SLOTS
  private panelScroller: Scroller = new Scroller()
  @State private showForm: boolean = false
  @State private formKind: string = 'Ocular'
  @State private formEditing: boolean = false
  @State private formIndex: number = -1
  @State private formDraft: OcularEquipmentDraft = emptyEquipmentDraft()
  @State private importChoiceOpen: boolean = false
  @State private pendingImportJson: string = ''
  @State private importValid: boolean = false
  @State private importSummaryText: string = ''

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
  onSetTelradFov: (values: number[]) => void = () => {}
  onAddEquipment: (kind: string, payload: string) => void = () => {}
  onUpdateEquipment: (kind: string, payload: string) => void = () => {}
  onDeleteEquipment: (kind: string, payload: string) => void = () => {}
  onMoveEquipment: (kind: string, payload: string) => void = () => {}
  onExportEquipment: (done: (json: string, ok: boolean) => void) => void = () => {}
  onImportEquipment: (json: string, append: boolean, done: (ok: boolean) => void) => void = () => {}
  onSaveEquipmentFile: (json: string, fileName: string, done: (result: MediaSaveResult) => void) => void = () => {}
  onPickEquipmentFile: (done: (text: string, cancelled: boolean, failed: boolean) => void) => void = () => {}
  onFlashHint: (text: ResourceStr) => void = () => {}
  onEditorRequestHandled: () => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  aboutToAppear(): void {
    this.onEditorRequestChanged()
    this.onScrollRequestChanged()
  }

  private onScrollRequestChanged(): void {
    if (this.scrollRequest.length === 0) return
    const value = Number(this.scrollRequest.split('|')[0])
    if (!Number.isFinite(value) || value < 0) return
    this.panelScroller.scrollTo({ xOffset: 0, yOffset: value, animation: false })
  }

  // 语义 CLI 的器材编辑器入口：kind|index|seq（index=-1 为新增）或 close|0|seq。
  private onEditorRequestChanged(): void {
    if (this.editorRequest.length === 0) return
    const parts = this.editorRequest.split('|')
    // 清空宿主请求，避免面板再次挂载时重复弹窗；延后一拍避免在 @Watch 渲染期改父状态。
    setTimeout(() => { this.onEditorRequestHandled() }, 0)
    if (parts.length < 2) return
    if (parts[0] === 'close') {
      this.showForm = false
      return
    }
    let kind = ''
    if (parts[0] === 'ocular') kind = 'Ocular'
    else if (parts[0] === 'lens') kind = 'Lens'
    else if (parts[0] === 'ccd') kind = 'CCD'
    else if (parts[0] === 'telescope') kind = 'Telescope'
    else return
    const index = Number(parts[1])
    if (!Number.isFinite(index)) return
    this.store.ocularPanelTab = this.tabForKind(kind)
    if (index < 0) this.openAdd(kind)
    else this.openEdit(kind, Math.round(index))
  }

  private tabForKind(kind: string): number {
    if (kind === 'Ocular') return 1
    if (kind === 'Lens') return 2
    if (kind === 'CCD') return 3
    if (kind === 'Telescope') return 4
    return 0
  }

  private tabs(): TabItem[] {
    const items: TabItem[] = [
      { id: 0, label: I18n.t('ocular_tab_general') },
      { id: 1, label: I18n.t('ocular_tab_oculars') },
      { id: 2, label: I18n.t('ocular_tab_lenses') },
      { id: 3, label: I18n.t('ocular_tab_sensors') },
      { id: 4, label: I18n.t('ocular_tab_telescopes') },
      { id: 5, label: I18n.t('ocular_tab_about') }
    ]
    return items
  }

  private openAdd(kind: string): void {
    if (this.store.ocularEquipmentBusy) return
    this.formDraft = emptyEquipmentDraft()
    this.formKind = kind
    this.formEditing = false
    this.formIndex = -1
    this.showForm = true
  }

  private openEdit(kind: string, index: number): void {
    if (this.store.ocularEquipmentBusy) return
    const item: OcularInstrumentItem | undefined = this.store.ocularInstrumentItem(kind, index)
    if (item === undefined) return
    this.formDraft = equipmentDraftFromItem(equipmentKindCode(kind), item)
    this.formKind = kind
    this.formEditing = true
    this.formIndex = index
    this.showForm = true
  }

  private submitEquipment(kind: string, index: number, draft: OcularEquipmentDraft): void {
    const code = equipmentKindCode(kind)
    if (index >= 0) {
      this.onUpdateEquipment(kind, equipmentMutationPayload('update', code, index, draft))
    } else {
      this.onAddEquipment(kind, equipmentMutationPayload('add', code, -1, draft))
    }
  }

  private moveEquipment(kind: string, index: number, delta: number): void {
    this.onMoveEquipment(kind, equipmentMovePayload(equipmentKindCode(kind), index, delta))
  }

  private confirmDelete(kind: string, index: number): void {
    const item = this.store.ocularInstrumentItem(kind, index)
    const name = item !== undefined && item.name.length > 0 ? item.name : this.store.ocularKindLabel(kind)
    AlertDialog.show({
      title: I18n.t('ocular_equipment_delete_title'),
      message: name + '\n' + I18n.t('ocular_equipment_delete_confirm'),
      primaryButton: {
        value: I18n.t('loc_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.t('ocular_equipment_delete'),
        fontColor: this.c.errorText,
        action: () => {
          this.onDeleteEquipment(kind, equipmentIndexPayload(equipmentKindCode(kind), index))
        }
      }
    })
  }

  private beginExport(): void {
    this.onExportEquipment((json: string, ok: boolean) => {
      if (!ok) return
      const fileName = 'stellarium-oculars-' + Date.now().toString() + '.json'
      this.onSaveEquipmentFile(json, fileName, (result: MediaSaveResult) => {
        if (result === MediaSaveResult.Saved) {
          this.onFlashHint(I18n.t('ocular_equipment_export_done'))
        } else if (result === MediaSaveResult.Failed) {
          this.onFlashHint(I18n.t('ocular_equipment_export_failed'))
        }
      })
    })
  }

  private beginImport(): void {
    this.onPickEquipmentFile((text: string, cancelled: boolean, failed: boolean) => {
      if (cancelled) return
      if (failed) {
        this.onFlashHint(I18n.t('ocular_equipment_import_failed'))
        return
      }
      this.pendingImportJson = text
      this.prepareImportSummary()
      this.importChoiceOpen = true
    })
  }

  private prepareImportSummary(): void {
    this.importValid = false
    this.importSummaryText = ''
    try {
      const doc = JSON.parse(this.pendingImportJson) as Record<string, Object>
      const oculars = doc['oculars'] as Object[] | undefined
      const lenses = doc['lenses'] as Object[] | undefined
      const telescopes = doc['telescopes'] as Object[] | undefined
      const ccds = doc['ccds'] as Object[] | undefined
      if (!Array.isArray(oculars) || !Array.isArray(lenses) || !Array.isArray(telescopes) || !Array.isArray(ccds)) {
        this.importSummaryText = I18n.t('ocular_equipment_import_invalid')
        return
      }
      const counts = I18n.t('ocular_tab_oculars') + ' ' + oculars.length.toString() + ' · ' +
        I18n.t('ocular_tab_lenses') + ' ' + lenses.length.toString() + ' · ' +
        I18n.t('ocular_tab_sensors') + ' ' + ccds.length.toString() + ' · ' +
        I18n.t('ocular_tab_telescopes') + ' ' + telescopes.length.toString()
      this.importSummaryText = counts
      this.importValid = true
    } catch (error) {
      this.importSummaryText = I18n.t('ocular_equipment_import_invalid')
    }
  }

  private applyImport(append: boolean): void {
    if (!this.importValid) return
    const json = this.pendingImportJson
    this.importChoiceOpen = false
    this.pendingImportJson = ''
    this.onImportEquipment(json, append, (ok: boolean) => {
      if (ok) this.store.ocularPanelTab = 1
    })
  }

  @Builder
  private generalTab() {
    OcularGeneralTab({
      store: this.store,
      telradFov: this.store.ocularTelradFov,
      onOpenSubPanel: (name: string) => { this.onOpenSubPanel(name) },
      onSetOcularMode: (isOn: boolean) => { this.onSetOcularMode(isOn) },
      onSetTelrad: (isOn: boolean) => { this.onSetTelrad(isOn) },
      onSetCrosshairs: (isOn: boolean) => { this.onSetCrosshairs(isOn) },
      onSetCcd: (isOn: boolean) => { this.onSetCcd(isOn) },
      onSetOcularSetting: (setting: string, isOn: boolean) => { this.onSetOcularSetting(setting, isOn) },
      onChangeMaskOpacity: (value: number, mode: SliderChangeMode) => { this.onChangeMaskOpacity(value, mode) },
      onChangeCropSize: (setting: string, value: number, mode: SliderChangeMode) => { this.onChangeCropSize(setting, value, mode) },
      onSetTelradFov: (values: number[]) => { this.onSetTelradFov(values) },
      onExportEquipment: () => { this.beginExport() },
      onImportEquipment: () => { this.beginImport() }
    })
  }

  @Builder
  private equipmentTab(kind: string) {
    OcularEquipmentTab({
      store: this.store,
      kind: kind,
      onSelectInstrument: (kindName: string, index: number) => { this.onSelectInstrument(kindName, index) },
      onAddEquipment: (kindName: string) => { this.openAdd(kindName) },
      onEditEquipment: (kindName: string, index: number) => { this.openEdit(kindName, index) },
      onDeleteEquipment: (kindName: string, index: number) => { this.confirmDelete(kindName, index) },
      onMoveEquipment: (kindName: string, index: number, delta: number) => { this.moveEquipment(kindName, index, delta) },
      onChangeCcdRotation: (value: number, mode: SliderChangeMode) => { this.onChangeCcdRotation(value, mode) },
      onChangePrismRotation: (value: number, mode: SliderChangeMode) => { this.onChangePrismRotation(value, mode) },
      onResetInstrument: (target: string) => { this.onResetInstrument(target) },
      onRotateReticle: (dir: string) => { this.onRotateReticle(dir) }
    })
  }

  @Builder
  private aboutTab() {
    Column({ space: 8 }) {
      Text(I18n.t('ocular_about_title')).fontSize(panelFontSize(15, this.readableUi))
        .fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
      Text(I18n.t('ocular_about_body')).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub)
        .width('100%')
      Column({ space: 6 }) {
        this.aboutCountRow(I18n.t('ocular_tab_oculars'), this.store.ocularNames.length)
        this.aboutCountRow(I18n.t('ocular_tab_lenses'), this.store.lensNames.length)
        this.aboutCountRow(I18n.t('ocular_tab_sensors'), this.store.ccdNames.length)
        this.aboutCountRow(I18n.t('ocular_tab_telescopes'), this.store.telescopeNames.length)
      }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
      Text(I18n.t('ocular_about_data_hint')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
        .width('100%')
    }.width('100%').padding({ bottom: 8 })
  }

  @Builder
  private aboutCountRow(label: string, count: number) {
    Row() {
      Text(label).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text).layoutWeight(1)
      Text(count.toString()).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub)
    }.width('100%')
  }

  @Builder
  private importSheet() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.55)')
        .onClick(() => { this.importChoiceOpen = false })
      Column({ space: 10 }) {
        Text(I18n.t('ocular_equipment_import_title')).fontSize(panelFontSize(15, this.readableUi))
          .fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
        Text(this.importSummaryText).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub)
          .width('100%').maxLines(3)
        Text(I18n.t('ocular_equipment_import_replace_warning')).fontSize(panelFontSize(11, this.readableUi))
          .fontColor(this.c.warning).width('100%').maxLines(2)
        Row({ space: 8 }) {
          Button(I18n.t('ocular_equipment_import_replace'))
            .id('ocular-equipment-import-replace')
            .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.errorText)
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).height(38).layoutWeight(1)
            .enabled(this.importValid)
            .onClick(() => { this.applyImport(false) })
          Button(I18n.t('ocular_equipment_import_append'))
            .id('ocular-equipment-import-append')
            .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.onAccent)
            .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL).height(38).layoutWeight(1)
            .enabled(this.importValid)
            .onClick(() => { this.applyImport(true) })
        }.width('100%')
        Button(I18n.t('loc_cancel'))
          .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.text)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(36).width('100%')
          .onClick(() => { this.importChoiceOpen = false })
      }
      .width('88%').padding(16)
      .backgroundColor(this.c.isNight ? '#150505' : '#101E2C')
      .border({ width: 1, color: this.c.border })
      .borderRadius(18)
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)' })
    }.width('100%').height('100%')
  }

  @Builder
  private modalCover() {
    if (this.showForm) {
      OcularEquipmentForm({
        draft: this.formDraft,
        kind: this.formKind,
        editing: this.formEditing,
        index: this.formIndex,
        busy: this.store.ocularEquipmentBusy,
        onCancel: () => { this.showForm = false },
        onSubmit: (kind: string, index: number, draft: OcularEquipmentDraft) => {
          this.showForm = false
          this.submitEquipment(kind, index, draft)
        }
      })
    } else if (this.importChoiceOpen) {
      this.importSheet()
    }
  }

  build() {
    Column() {
      OcularSummaryCard({ store: this.store })
      OcularsTabs({
        tabs: this.tabs(),
        activeTab: this.store.ocularPanelTab,
        onSelectTab: (id: number) => { this.store.ocularPanelTab = id }
      })
      Scroll(this.panelScroller) {
        Column({ space: 8 }) {
          if (this.store.ocularLoading) {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18).color(this.c.accent)
              Text(I18n.t('ocular_status_loading')).fontSize(11).fontColor(this.c.sub)
            }.width('100%').height(40).justifyContent(FlexAlign.Center)
          }
          if (this.store.ocularStatusMessage.length > 0) {
            Text(this.store.ocularStatusMessage).fontSize(11).fontColor(this.c.warning).width('100%').maxLines(3)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor(this.c.warningBg).borderRadius(UI_RADIUS_CONTROL)
          }
          if (this.store.ocularPanelTab === 0) {
            this.generalTab()
          } else if (this.store.ocularPanelTab === 1) {
            this.equipmentTab('Ocular')
          } else if (this.store.ocularPanelTab === 2) {
            this.equipmentTab('Lens')
          } else if (this.store.ocularPanelTab === 3) {
            this.equipmentTab('CCD')
          } else if (this.store.ocularPanelTab === 4) {
            this.equipmentTab('Telescope')
          } else {
            this.aboutTab()
          }
        }
        .width('100%')
        .padding({ bottom: 8 })
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
    }
    .width('100%').height('100%')
    .padding({ left: 8, right: 8, top: 8 })
    .bindContentCover(this.showForm || this.importChoiceOpen, this.modalCover)
  }
}
