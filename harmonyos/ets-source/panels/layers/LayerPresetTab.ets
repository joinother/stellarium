import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { LayerPresetDefinition, LayerPresetDiffItem, LAYER_PRESET_CUSTOM_LIMIT } from '../../common/types/MainWindowModels'
import { LayerPresetStore } from '../../state/LayerPresetStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { panelFontSize } from '../../common/ui/UiTypography'

// 「图层预设」管理页：保存/更新、复制为自定义、改名、排序、启停、详情与还原。
// 预设条本身仍固定在面板顶部；本页只负责管理，不改变当前图层设置。
//
// 每行保持标准功能行高度，只常驻“拖动/名称/启停/更多”四项；
// 点击行名称即应用该预设，高亮行就是当前生效的预设（不再提供独立“应用”按钮）；
// 详情、改名、还原、删除默认折叠在行内展开区，顺序用长按 ≡ 拖动调整。
@Component
export struct LayerPresetTab {
  @ObjectLink presetStore: LayerPresetStore
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private expandedId: string = ''
  @State private renameId: string = ''
  @State private renameDraft: string = ''
  @State private dragId: string = ''
  @State private dragOffset: number = 0
  private dragFrom: number = -1

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private rowHeight(): number {
    return this.readableUi ? 50 : 42
  }

  private rowStride(): number {
    return this.rowHeight() + 6
  }

  private canAddCustom(): boolean {
    return this.presetStore.presets.filter((preset: LayerPresetDefinition) => preset.kind === 'custom').length
      < LAYER_PRESET_CUSTOM_LIMIT
  }

  private isExpanded(preset: LayerPresetDefinition): boolean {
    return this.expandedId === preset.id || this.presetStore.detailsId === preset.id || this.renameId === preset.id
  }

  // 参数化 @Builder 按值捕获；把选中/修改/展开/改名状态纳入 ForEach key，
  // 预设保存、还原、启停后强制重建该行，避免显示旧名称或旧星号。
  // 注意：拖拽状态不能进入 key，否则拖动开始时行被重建，手势会中断。
  private rowKey(preset: LayerPresetDefinition, index: number): string {
    const selected = this.presetStore.selectedId === preset.id ? 'sel' : ''
    const details = this.presetStore.detailsId === preset.id
      ? 'det' + this.presetStore.detailsVersion.toString() : ''
    const expanded = this.expandedId === preset.id ? 'exp' : ''
    const rename = this.renameId === preset.id ? 'ren' : ''
    return preset.id + '|' + index.toString() + '|' + (preset.enabled ? '1' : '0') + '|'
      + (this.presetStore.isMarked(preset) ? 'mark' : '') + '|' + selected + '|' + details + '|'
      + expanded + '|' + rename + '|' + preset.customName
  }

  private toggleExpanded(preset: LayerPresetDefinition): void {
    if (this.isExpanded(preset)) {
      this.closeRow()
      return
    }
    this.expandedId = preset.id
    this.renameId = ''
    this.renameDraft = ''
    this.presetStore.clearDetails()
  }

  private closeRow(): void {
    this.expandedId = ''
    this.renameId = ''
    this.renameDraft = ''
    this.presetStore.clearDetails()
  }

  private beginRename(preset: LayerPresetDefinition): void {
    this.expandedId = preset.id
    this.renameId = preset.id
    this.renameDraft = preset.customName
  }

  private commitRename(): void {
    if (this.renameId.length === 0) return
    this.presetStore.renameCustom(this.renameId, this.renameDraft)
    this.renameId = ''
    this.renameDraft = ''
  }

  private beginDrag(preset: LayerPresetDefinition, index: number): void {
    if (this.presetStore.busy || this.renameId === preset.id) return
    // 行展开后高度不同；拖拽期间只允许标准高度行，先收起其他行。
    if (this.isExpanded(preset)) return
    if (this.expandedId.length > 0 || this.presetStore.detailsId.length > 0) this.closeRow()
    this.dragFrom = index
    this.dragId = preset.id
    this.dragOffset = 0
  }

  private finishDrag(): void {
    if (this.dragId.length > 0 && this.dragFrom >= 0) {
      const delta = Math.round(this.dragOffset / this.rowStride())
      if (delta !== 0) {
        let target = this.dragFrom + delta
        if (target < 0) target = 0
        const last = this.presetStore.presets.length - 1
        if (target > last) target = last
        this.presetStore.movePresetTo(this.dragFrom, target)
      }
    }
    this.cancelDrag()
  }

  private cancelDrag(): void {
    this.dragId = ''
    this.dragFrom = -1
    this.dragOffset = 0
  }

  private confirmDelete(preset: LayerPresetDefinition): void {
    this.getUIContext().showAlertDialog({
      title: I18n.t('preset_delete'),
      message: this.presetStore.displayName(preset),
      primaryButton: { value: I18n.t('loc_cancel'), action: () => {} },
      secondaryButton: {
        value: I18n.t('preset_delete'),
        fontColor: this.c.errorText,
        action: () => {
          this.closeRow()
          this.presetStore.deleteCustom(preset.id)
        }
      }
    })
  }

  @Builder
  private actionChips(preset: LayerPresetDefinition) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
      if (preset.factory !== undefined) {
        Text(I18n.t('preset_details'))
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
          .height(28).padding({ left: 10, right: 10 }).margin({ right: 6, bottom: 4 })
          .onClick(() => { this.presetStore.showDetails(preset.id) })
      }
      if (preset.kind === 'custom') {
        Text(I18n.t('preset_rename'))
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
          .height(28).padding({ left: 10, right: 10 }).margin({ right: 6, bottom: 4 })
          .onClick(() => { this.beginRename(preset) })
      }
      if (preset.factory !== undefined && this.presetStore.isModified(preset)) {
        Text(I18n.t('preset_restore'))
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.errorText)
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
          .height(28).padding({ left: 10, right: 10 }).margin({ right: 6, bottom: 4 })
          .onClick(() => { this.presetStore.restorePreset(preset.id) })
      }
      if (preset.kind === 'custom') {
        Text(I18n.t('preset_delete'))
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.errorText)
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
          .height(28).padding({ left: 10, right: 10 }).margin({ right: 6, bottom: 4 })
          .onClick(() => { this.confirmDelete(preset) })
      }
    }
  }

  // 改名用全屏浮层而不是行内输入框：预设行位于面板底部时，行内编辑器和
  // 确定/取消会被面板边界与键盘挡住。浮层始终居中，键盘弹出后也不会丢按钮。
  private cancelRename(): void {
    this.renameId = ''
    this.renameDraft = ''
  }

  @Builder
  private renameCover() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.55)')
        .onClick(() => { this.cancelRename() })
      Column({ space: 12 }) {
        Text(I18n.t('preset_rename')).fontSize(16).fontColor(this.c.text).width('100%')
        TextInput({ text: this.renameDraft, placeholder: I18n.t('preset_name_placeholder') })
          .width('100%').height(40)
          .fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text)
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
          .maxLength(24)
          .onChange((value: string) => { this.renameDraft = value })
          .onSubmit(() => { this.commitRename() })
        Row({ space: 10 }) {
          Button(I18n.t('loc_cancel'))
            .fontSize(13).fontColor(this.c.text)
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
            .height(38).layoutWeight(1)
            .onClick(() => { this.cancelRename() })
          Button(I18n.t('loc_confirm'))
            .fontSize(13).fontColor(this.c.onAccent)
            .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL)
            .height(38).layoutWeight(1)
            .onClick(() => { this.commitRename() })
        }.width('100%')
      }
      .width('86%').padding(16)
      .backgroundColor(this.c.isNight ? '#150505' : '#101E2C')
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)' })
    }
    .width('100%').height('100%')
  }

  @Builder
  private detailsList() {
    Column({ space: 4 }) {
      if (this.presetStore.detailsItems.length === 0) {
        Text(I18n.t('preset_no_changes')).fontSize(10).fontColor(this.c.sub).width('100%')
      } else {
        ForEach(this.presetStore.detailsItems, (item: LayerPresetDiffItem) => {
          Row({ space: 8 }) {
            Text(item.label).fontSize(10).fontColor(this.c.text).layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(item.before + ' → ' + item.after).fontSize(10).fontColor(this.c.sub)
          }.width('100%')
        }, (item: LayerPresetDiffItem, index: number) => item.label + item.before + item.after + index.toString())
      }
    }
    .width('100%').padding(8).backgroundColor(this.c.bg)
    .border({ width: 1, color: this.c.dividerSoft }).borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  private expandedPanel(preset: LayerPresetDefinition) {
    Column({ space: 8 }) {
      this.actionChips(preset)
      if (this.presetStore.detailsId === preset.id) this.detailsList()
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 2, bottom: 10 })
  }

  @Builder
  private presetRow(preset: LayerPresetDefinition, index: number) {
    Column({ space: 0 }) {
      Row({ space: 6 }) {
        Text('≡')
          .fontSize(16).fontColor(this.c.sub)
          .width(30).height(this.rowHeight()).textAlign(TextAlign.Center)
          .gesture(GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false, duration: 350 })
              .onAction(() => { this.beginDrag(preset, index) }),
            PanGesture({ direction: PanDirection.Vertical, distance: 1 })
              .onActionUpdate((event: GestureEvent) => { this.dragOffset = event.offsetY })
              .onActionEnd(() => { this.finishDrag() })
          ).onCancel(() => { this.cancelDrag() }))
        Text(this.presetStore.labelWithMarker(preset))
          .fontSize(panelFontSize(13, this.readableUi))
          .fontColor(preset.id === this.presetStore.selectedId ? this.c.accent : this.c.text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .onClick(() => { this.presetStore.applyPreset(preset.id) })
        Toggle({ type: ToggleType.Switch, isOn: preset.enabled })
          .width(38).height(22).selectedColor(this.c.accent)
          .onChange((value: boolean) => { this.presetStore.setEnabled(preset.id, value) })
        Text('⋯')
          .fontSize(16).fontColor(this.isExpanded(preset) ? this.c.onAccent : this.c.sub)
          .width(28).height(28).textAlign(TextAlign.Center)
          .backgroundColor(this.isExpanded(preset) ? this.c.accent : this.c.softStrong)
          .borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.toggleExpanded(preset) })
      }
      .width('100%')
      .height(this.rowHeight())
      .padding({ left: 4, right: 8 })
      if (this.isExpanded(preset)) {
        this.expandedPanel(preset)
      }
    }
    .width('100%')
    .backgroundColor(preset.id === this.presetStore.selectedId ? this.c.accentSoft : this.c.bg)
    .border({ width: 1, color: preset.id === this.presetStore.selectedId ? this.c.accent : this.c.dividerSoft })
    .borderRadius(UI_RADIUS_CONTROL)
    .margin({ bottom: 6 })
    .opacity(preset.enabled ? 1 : 0.6)
    .translate({ y: this.dragId === preset.id ? this.dragOffset : 0 })
    .zIndex(this.dragId === preset.id ? 2 : 0)
    .shadow(this.dragId === preset.id
      ? { radius: 14, color: this.c.shadowSoft, offsetX: 0, offsetY: 6 }
      : { radius: 0, color: this.c.shadowSoft, offsetX: 0, offsetY: 0 })
  }

  build() {
    Column({ space: 8 }) {
      // 保存类操作放在顶部，管理列表保持紧凑。
      Row({ space: 8 }) {
        Button(I18n.t('preset_save_current'))
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).height(34)
          .layoutWeight(1).padding({ left: 8, right: 8 })
          .enabled(this.presetStore.selectedId.length > 0)
          .onClick(() => { this.presetStore.saveCurrentToSelected() })
        Button(I18n.t('preset_save_custom'))
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.text)
          .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).height(34)
          .layoutWeight(1).padding({ left: 8, right: 8 })
          .enabled(this.presetStore.selectedId.length > 0 && this.canAddCustom())
          .onClick(() => { this.presetStore.saveSelectedAsCustom() })
      }.width('100%')
      Row({ space: 6 }) {
        Text(I18n.t('preset_keep_hint'))
          .fontSize(10).fontColor(this.c.sub).layoutWeight(1)
        if (!this.canAddCustom()) {
          Text(I18n.t('preset_custom_limit')).fontSize(9).fontColor(this.c.sub)
        }
      }.width('100%').padding({ left: 2, right: 2 })
      ForEach(this.presetStore.presets, (preset: LayerPresetDefinition, index: number) => {
        this.presetRow(preset, index)
      }, (preset: LayerPresetDefinition, index: number) => this.rowKey(preset, index))
    }
    .width('100%').padding({ bottom: 8 })
    .bindContentCover(this.renameId.length > 0, this.renameCover)
  }
}
