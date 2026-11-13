import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { LayerViewStore } from '../../state/LayerViewStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { SettingsChoiceButton } from '../../common/ui/SettingsChoiceButton'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { LayerSwitchRow } from './LayerSwitchRow'
import { DsoSliderRow } from './DsoSliderRow'

interface CatalogOption {
  label: string
  bit: number
}

interface TypeOption {
  labelKey: string
  bit: number
}

const DSO_CATALOGS: Array<CatalogOption> = [
  { label: 'M', bit: 0x00000004 },
  { label: 'NGC', bit: 0x00000001 },
  { label: 'IC', bit: 0x00000002 },
  { label: 'C', bit: 0x00000008 },
  { label: 'B', bit: 0x00000010 },
  { label: 'Sh2', bit: 0x00000020 },
  { label: 'LBN', bit: 0x00000040 },
  { label: 'LDN', bit: 0x00000080 },
  { label: 'RCW', bit: 0x00000100 },
  { label: 'vdB', bit: 0x00000200 },
  { label: 'Cr', bit: 0x00000400 },
  { label: 'Mel', bit: 0x00000800 },
  { label: 'PGC', bit: 0x00001000 },
  { label: 'UGC', bit: 0x00002000 },
  { label: 'Ced', bit: 0x00004000 },
  { label: 'Arp', bit: 0x00008000 },
  { label: 'VV', bit: 0x00010000 },
  { label: 'PK', bit: 0x00020000 },
  { label: 'PN G', bit: 0x00040000 },
  { label: 'SNR G', bit: 0x00080000 },
  { label: 'ACO', bit: 0x00100000 },
  { label: 'HCG', bit: 0x00200000 },
  { label: 'ESO', bit: 0x00400000 },
  { label: 'vdBH', bit: 0x00800000 },
  { label: 'DWB', bit: 0x01000000 },
  { label: 'Tr', bit: 0x02000000 },
  { label: 'St', bit: 0x04000000 },
  { label: 'Ru', bit: 0x08000000 },
  { label: 'vdB-Ha', bit: 0x10000000 },
  { label: 'Other', bit: 0x20000000 }
]

const DSO_TYPES: Array<TypeOption> = [
  { labelKey: 'dso_type_galaxies', bit: 0x0001 },
  { labelKey: 'dso_type_active_galaxies', bit: 0x0002 },
  { labelKey: 'dso_type_interacting_galaxies', bit: 0x0004 },
  { labelKey: 'dso_type_open_clusters', bit: 0x0008 },
  { labelKey: 'dso_type_globular_clusters', bit: 0x0010 },
  { labelKey: 'dso_type_hydrogen_regions', bit: 0x0020 },
  { labelKey: 'dso_type_bright_nebulae', bit: 0x0040 },
  { labelKey: 'dso_type_dark_nebulae', bit: 0x0080 },
  { labelKey: 'dso_type_planetary_nebulae', bit: 0x0100 },
  { labelKey: 'dso_type_supernova_remnants', bit: 0x0200 },
  { labelKey: 'dso_type_galaxy_clusters', bit: 0x0400 },
  { labelKey: 'dso_type_other', bit: 0x0800 }
]

@Component
export struct DsoSettingsSection {
  @ObjectLink layerViewStore: LayerViewStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSetSetting: (setting: string, value: boolean | number) => void = () => {}
  onSetCatalogMask: (mask: number) => void = () => {}
  onSetTypeMask: (mask: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private catalogActive(bit: number): boolean {
    return (this.layerViewStore.dsoCatalogFilters & bit) !== 0
  }

  private typeActive(bit: number): boolean {
    return (this.layerViewStore.dsoTypeFilters & bit) !== 0
  }

  private toggleCatalog(bit: number): void {
    const next = (this.layerViewStore.dsoCatalogFilters & bit) !== 0
      ? (this.layerViewStore.dsoCatalogFilters & ~bit)
      : (this.layerViewStore.dsoCatalogFilters | bit)
    this.layerViewStore.dsoCatalogFilters = next
    this.onSetCatalogMask(next)
  }

  private toggleType(bit: number): void {
    const next = (this.layerViewStore.dsoTypeFilters & bit) !== 0
      ? (this.layerViewStore.dsoTypeFilters & ~bit)
      : (this.layerViewStore.dsoTypeFilters | bit)
    this.layerViewStore.dsoTypeFilters = next
    this.onSetTypeMask(next)
  }

  private setCatalogQuick(mask: number): void {
    this.layerViewStore.dsoCatalogFilters = mask
    this.onSetCatalogMask(mask)
  }

  private catalogSummary(): string {
    if (this.layerViewStore.dsoCatalogFilters === -1) return I18n.t('dso_catalog_all')
    if (this.layerViewStore.dsoCatalogFilters === 0x20001007) return I18n.t('dso_catalog_standard')
    if (this.layerViewStore.dsoCatalogFilters === 0) return I18n.t('dso_catalog_none')
    return I18n.t('dso_catalog_custom')
  }

  build() {
    Column({ space: 0 }) {
      Text(I18n.t('dso_labels_title')).fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 2, bottom: 4 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('s0321'), isOn: this.layerViewStore.dsoHintsEnabled, onToggle: (v: boolean) => { this.layerViewStore.dsoHintsEnabled = v; this.onSetSetting('hints', v) } })
      LayerSwitchRow({ label: I18n.t('dso_designations'), isOn: this.layerViewStore.dsoDesignations, onToggle: (v: boolean) => { this.layerViewStore.dsoDesignations = v; this.onSetSetting('designations', v) } })
      LayerSwitchRow({ label: I18n.t('dso_additional_names'), isOn: this.layerViewStore.dsoAdditionalNames, onToggle: (v: boolean) => { this.layerViewStore.dsoAdditionalNames = v; this.onSetSetting('additionalNames', v) } })
      LayerSwitchRow({ label: I18n.t('dso_show_only_named'), isOn: this.layerViewStore.dsoShowOnlyNamed, onToggle: (v: boolean) => { this.layerViewStore.dsoShowOnlyNamed = v; this.onSetSetting('showOnlyNamed', v) } })
      LayerSwitchRow({ label: I18n.t('dso_outlines'), isOn: this.layerViewStore.dsoOutlines, onToggle: (v: boolean) => { this.layerViewStore.dsoOutlines = v; this.onSetSetting('outlines', v) } })
      LayerSwitchRow({ label: I18n.t('dso_proportional_hints'), isOn: this.layerViewStore.dsoHintsProportional, onToggle: (v: boolean) => { this.layerViewStore.dsoHintsProportional = v; this.onSetSetting('hintsProportional', v) } })
      LayerSwitchRow({ label: I18n.t('dso_surface_brightness'), isOn: this.layerViewStore.dsoSurfaceBrightness, onToggle: (v: boolean) => { this.layerViewStore.dsoSurfaceBrightness = v; this.onSetSetting('surfaceBrightness', v) } })
      Row() {
        Text(I18n.t('dso_labels_adjust_row')).fontSize(12).fontColor(this.c.text).layoutWeight(1)
        Button(this.layerViewStore.dsoLabelsExpanded ? I18n.t('btn_collapse') : I18n.t('dso_adjust'))
          .fontSize(10).fontColor(this.c.accent).height(28)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).padding({ left: 9, right: 9 })
          .onClick(() => { this.layerViewStore.dsoLabelsExpanded = !this.layerViewStore.dsoLabelsExpanded })
      }.height(42).width('100%').padding({ left: 10, right: 8 })
      .backgroundColor(this.c.bg)
      .border({ width: 1, color: this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 2, bottom: 6 })
      if (this.layerViewStore.dsoLabelsExpanded) {
        Column({ space: 0 }) {
          DsoSliderRow({ label: I18n.t('dso_labels_amount'), value: this.layerViewStore.dsoLabelsAmount, minValue: 0, maxValue: 10, stepValue: 1, onValueChange: (v: number) => { this.layerViewStore.dsoLabelsAmount = v; this.onSetSetting('labelsAmount', v) } })
          DsoSliderRow({ label: I18n.t('dso_hints_amount'), value: this.layerViewStore.dsoHintsAmount, minValue: 0, maxValue: 10, stepValue: 1, onValueChange: (v: number) => { this.layerViewStore.dsoHintsAmount = v; this.onSetSetting('hintsAmount', v) } })
          DsoSliderRow({ label: I18n.t('dso_labels_brightness'), value: this.layerViewStore.dsoLabelsBrightness, minValue: 0, maxValue: 1, stepValue: 0.1, onValueChange: (v: number) => { this.layerViewStore.dsoLabelsBrightness = v; this.onSetSetting('labelsBrightness', v) } })
          DsoSliderRow({ label: I18n.t('dso_hints_brightness'), value: this.layerViewStore.dsoHintsBrightness, minValue: 0, maxValue: 1, stepValue: 0.1, onValueChange: (v: number) => { this.layerViewStore.dsoHintsBrightness = v; this.onSetSetting('hintsBrightness', v) } })
        }.width('100%').padding({ top: 2, bottom: 4 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
      }

      Divider().color(this.c.border).margin({ top: 6, bottom: 2 })
      Text(I18n.t('dso_size_magnitude_title')).fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 2, bottom: 4 }).padding({ left: 2 })
      LayerSwitchRow({ label: I18n.t('dso_size_limits'), isOn: this.layerViewStore.dsoSizeLimits, onToggle: (v: boolean) => { this.layerViewStore.dsoSizeLimits = v; this.onSetSetting('sizeLimits', v) } })
      LayerSwitchRow({ label: I18n.t('dso_magnitude_limit'), isOn: this.layerViewStore.dsoNebulaMagnitudeLimit, onToggle: (v: boolean) => { this.layerViewStore.dsoNebulaMagnitudeLimit = v; this.onSetSetting('nebulaMagnitudeLimit', v) } })
      Row() {
        Text(I18n.t('dso_size_magnitude_adjust_row')).fontSize(12).fontColor(this.c.text).layoutWeight(1)
        Button(this.layerViewStore.dsoSizeMagnitudeExpanded ? I18n.t('btn_collapse') : I18n.t('dso_adjust'))
          .fontSize(10).fontColor(this.c.accent).height(28)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).padding({ left: 9, right: 9 })
          .onClick(() => { this.layerViewStore.dsoSizeMagnitudeExpanded = !this.layerViewStore.dsoSizeMagnitudeExpanded })
      }.height(42).width('100%').padding({ left: 10, right: 8 })
      .backgroundColor(this.c.bg)
      .border({ width: 1, color: this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 2, bottom: 6 })
      if (this.layerViewStore.dsoSizeMagnitudeExpanded) {
        Column({ space: 0 }) {
          DsoSliderRow({ label: I18n.t('dso_min_size'), value: this.layerViewStore.dsoMinSizeLimit, minValue: 0, maxValue: 600, stepValue: 1, sliderEnabled: this.layerViewStore.dsoSizeLimits, onValueChange: (v: number) => { this.layerViewStore.dsoMinSizeLimit = v; this.onSetSetting('minSizeLimit', v) } })
          DsoSliderRow({ label: I18n.t('dso_max_size'), value: this.layerViewStore.dsoMaxSizeLimit, minValue: 0, maxValue: 1200, stepValue: 1, sliderEnabled: this.layerViewStore.dsoSizeLimits, onValueChange: (v: number) => { this.layerViewStore.dsoMaxSizeLimit = v; this.onSetSetting('maxSizeLimit', v) } })
          DsoSliderRow({ label: I18n.t('dso_magnitude'), value: this.layerViewStore.dsoNebulaMagnitude, minValue: 3, maxValue: 21, stepValue: 0.25, sliderEnabled: this.layerViewStore.dsoNebulaMagnitudeLimit, onValueChange: (v: number) => { this.layerViewStore.dsoNebulaMagnitude = v; this.onSetSetting('nebulaMagnitude', v) } })
        }.width('100%').padding({ top: 2, bottom: 4 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
      }

      Divider().color(this.c.border).margin({ top: 8, bottom: 2 })
      Row() {
        Column({ space: 1 }) {
          Text(I18n.t('dso_catalogs_title')).fontSize(11).fontColor(this.c.sub).width('100%')
          Text(this.catalogSummary()).fontSize(10).fontColor(this.c.text).width('100%')
        }.layoutWeight(1).padding({ left: 2 })
        Button(this.layerViewStore.dsoCatalogExpanded ? I18n.t('btn_collapse') : I18n.t('dso_select'))
          .fontSize(10).fontColor(this.c.accent).height(28)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).padding({ left: 9, right: 9 })
          .onClick(() => { this.layerViewStore.dsoCatalogExpanded = !this.layerViewStore.dsoCatalogExpanded })
      }.width('100%').height(40).padding({ left: 2, right: 2 }).margin({ top: 2, bottom: 2 })
      if (this.layerViewStore.dsoCatalogExpanded) {
        Column({ space: 2 }) {
          Row({ space: 4 }) {
            SettingsChoiceButton({ label: I18n.t('dso_catalog_all'), active: this.layerViewStore.dsoCatalogFilters === -1, canPick: true, onPick: () => { this.setCatalogQuick(-1) } })
            SettingsChoiceButton({ label: I18n.t('dso_catalog_standard'), active: this.layerViewStore.dsoCatalogFilters === 0x20001007, canPick: true, onPick: () => { this.setCatalogQuick(0x20001007) } })
            SettingsChoiceButton({ label: I18n.t('dso_catalog_none'), active: this.layerViewStore.dsoCatalogFilters === 0, canPick: true, onPick: () => { this.setCatalogQuick(0) } })
          }.width('100%').padding({ left: 4 })
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(DSO_CATALOGS, (item: CatalogOption) => {
              SettingsChoiceButton({ label: item.label, active: this.catalogActive(item.bit), canPick: true, onPick: () => { this.toggleCatalog(item.bit) } })
            }, (item: CatalogOption) => item.label)
          }.width('100%').padding({ left: 4, top: 2 })
        }.width('100%').padding({ top: 2, bottom: 4 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
      }

      Divider().color(this.c.border).margin({ top: 4, bottom: 2 })
      Row() {
        Text(I18n.t('dso_types_title')).fontSize(11).fontColor(this.c.sub).layoutWeight(1).padding({ left: 2 })
        Toggle({ type: ToggleType.Switch, isOn: this.layerViewStore.dsoTypeFilterUsage })
          .width(42).height(24)
          .onChange((value: boolean) => {
            this.layerViewStore.dsoTypeFilterUsage = value
            this.onSetSetting('typeFilterUsage', value)
          })
        Button(this.layerViewStore.dsoTypeExpanded ? I18n.t('btn_collapse') : I18n.t('dso_select'))
          .fontSize(10).fontColor(this.c.accent).height(28)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).padding({ left: 9, right: 9 })
          .margin({ left: 6 })
          .onClick(() => { this.layerViewStore.dsoTypeExpanded = !this.layerViewStore.dsoTypeExpanded })
      }.width('100%').height(40).padding({ left: 2, right: 2 }).margin({ top: 2, bottom: 2 })
      if (this.layerViewStore.dsoTypeExpanded) {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(DSO_TYPES, (item: TypeOption) => {
            SettingsChoiceButton({ label: I18n.t(item.labelKey), active: this.typeActive(item.bit), canPick: this.layerViewStore.dsoTypeFilterUsage, onPick: () => { this.toggleType(item.bit) } })
          }, (item: TypeOption) => item.labelKey)
        }.width('100%').padding({ left: 4, top: 2, bottom: 4 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
      }
    }.width('100%')
  }
}
