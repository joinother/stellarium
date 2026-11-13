import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { LocSearchItem } from '../../pages/StellariumTypes'
import { clamp } from '../../common/derive/astro'
import { LocationStore } from '../../state/LocationStore'
import { LocationPickerStore } from '../../state/LocationPickerStore'
import { LocationSearchPanel } from './LocationSearchPanel'
import { HierColumn } from '../../common/ui/HierColumn'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { LocationOverviewCard } from './LocationOverviewCard'

// 本组件职责：「位置」面板的位置选择器。
//
// 三个 tab 只呈现一种选点方式：搜索 / 地图 / 地区；已保存与最近使用在下方
// CityChipsRow 中。应用观测点仍是即时模型，海拔字段在失焦/提交时应用。
//   - 选择器状态（picker 坐标/名称/状态、层级选择、地图渲染尺寸、时区、选点方式）与
//     层级翻译/过滤全部走 @ObjectLink pickerStore（LocationPickerStore），实时刷新；
//   - 离线/在线搜索框复用 LocationSearchPanel，其 store 走 locationStore；
//   - native 桥 / 定时器（使用设备位置、应用、地图点按、层级落地）由宿主完成，以回调注入；
//   - 地图尺寸由宿主按布局算好；地图几何由 LocationPickerPanel 自算。
//   - 非地球海拔只读：由离线地点提供（通常 0）；地球输入夹在 -500..9000 m。

@Component
export struct LocationModeChip {
  @Prop mode: string
  @Prop label: ResourceStr
  @Prop selected: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onSelect: (mode: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Button(this.label)
      .height(30)
      .fontSize(12)
      .fontColor(this.selected ? this.c.onAccent : this.c.sub)
      .backgroundColor(this.selected ? this.c.accent : this.c.bg)
      .border({ width: 1, color: this.selected ? this.c.softStrong : this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .layoutWeight(1)
      .margin({ right: this.mode === 'hierarchy' ? 0 : 6 })
      .onClick(() => { this.onSelect(this.mode) })
  }
}

const EARTH_ALTITUDE_MIN: number = -500
const EARTH_ALTITUDE_MAX: number = 9000

@Component
export struct LocationPickerPanel {
  @ObjectLink pickerStore: LocationPickerStore
  @ObjectLink locationStore: LocationStore
  @Prop observerPlanet: string
  @Prop mapTexture: string = ''
  // 概览地图需要隐私/前台/联网门禁；由宿主算好传入。
  @Prop onlineAllowed: boolean = false
  // 全屏地图打开时挂起概览地图，避免两个 MapComponent 同时存活。
  @Prop mapSuspended: boolean = false
  // 地图几何：是否展开由宿主布局态决定。
  @Prop expandedLayout: boolean
  @Prop skyWidth: number
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private altitudeDirty: boolean = false
  onSearchLocations: (query: string) => void = () => {}
  onInputFocus: () => void = () => {}
  onInputBlur: () => void = () => {}
  contextOf: (item: LocSearchItem) => string = () => ''
  onPickSearchItem: (item: LocSearchItem) => void = () => {}
  onApply: () => void = () => {}
  onSelectContinent: (c: string) => void = () => {}
  onSelectCountry: (c: string) => void = () => {}
  onSelectRegion: (r: string) => void = () => {}
  onSelectCity: (c: string) => void = () => {}
  onOpenFullMap: () => void = () => {}

  private columnScrollers: Array<Scroller> = [new Scroller(), new Scroller(), new Scroller(), new Scroller()]

  private columnScroller(kind: string): Scroller {
    const index = kind === 'continent' ? 0 : (kind === 'country' ? 1 : (kind === 'region' ? 2 : 3))
    return this.columnScrollers[index]
  }

  private locationMapWidth(): number {
    if (this.expandedLayout) {
      return 292
    }
    return clamp(this.skyWidth * 0.92 - 32, 276, 620)
  }

  private locationMapHeight(): number {
    return this.locationMapWidth() / 2
  }

  private isEarth(): boolean {
    return this.observerPlanet === 'Earth'
  }

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private commitAltitude(): void {
    if (!this.altitudeDirty) return
    this.altitudeDirty = false
    this.onApply()
  }

  build() {
    Column() {
      // One selection method per tab. Saved/recent shortcuts stay below the
      // picker instead of being repeated inside each tab.
      Row() {
        LocationModeChip({
          mode: 'search', label: I18n.t('loc_tab_search'),
          selected: this.pickerStore.locationPickMode === 'search',
          onSelect: (mode: string) => { this.pickerStore.locationPickMode = mode }
        })
        LocationModeChip({
          mode: 'map', label: I18n.t('loc_tab_map'),
          selected: this.pickerStore.locationPickMode === 'map',
          onSelect: (mode: string) => { this.pickerStore.locationPickMode = mode }
        })
        LocationModeChip({
          mode: 'hierarchy', label: I18n.t('loc_tab_region'),
          selected: this.pickerStore.locationPickMode === 'hierarchy',
          onSelect: (mode: string) => { this.pickerStore.locationPickMode = mode }
        })
      }
        .width('100%')
        .margin({ top: 2 })

      if (this.pickerStore.locationPickMode === 'search') {
        LocationSearchPanel({
          store: this.locationStore,
          observerPlanet: this.observerPlanet,
          onlineAllowed: this.onlineAllowed,
          onSearch: (query: string) => { this.onSearchLocations(query) },
          onNameDraft: (name: string) => { this.pickerStore.locationPickerName = name },
          onInputFocus: () => { this.onInputFocus() },
          onInputBlur: () => { this.onInputBlur() },
          contextOf: (item: LocSearchItem) => this.contextOf(item),
          onPickItem: (item: LocSearchItem) => { this.onPickSearchItem(item) }
        })
      } else if (this.pickerStore.locationPickMode === 'map') {
        // The overview is read-only. Precision picking lives in the full-screen
        // Map Kit picker; tapping any part of this card opens it.
        LocationOverviewCard({
          planet: this.observerPlanet,
          latitude: this.pickerStore.locationPickerLatitude,
          longitude: this.pickerStore.locationPickerLongitude,
          texture: this.mapTexture,
          onlineAllowed: this.onlineAllowed,
          suspended: this.mapSuspended,
          source: this.pickerStore.locationSource,
          previewWidth: this.locationMapWidth(),
          previewHeight: this.locationMapHeight(),
          onOpen: () => { this.onOpenFullMap() }
        })
      } else {
        Column() {
          Row() {
            HierColumn({
              title: this.pickerStore.locationColumnTitle('continent'),
              items: this.pickerStore.hierColumnItems('continent', this.observerPlanet),
              selected: this.pickerStore.hierarchySelectionFor('continent'),
              scroller: this.columnScroller('continent'),
              labelOf: (item: string) => this.pickerStore.hierarchyItemLabel('continent', item, this.observerPlanet),
              onSelect: (c: string) => { this.onSelectContinent(c) }
            })
            HierColumn({
              title: this.pickerStore.locationColumnTitle('country'),
              items: this.pickerStore.hierColumnItems('country', this.observerPlanet),
              selected: this.pickerStore.hierarchySelectionFor('country'),
              scroller: this.columnScroller('country'),
              labelOf: (item: string) => this.pickerStore.hierarchyItemLabel('country', item, this.observerPlanet),
              onSelect: (c: string) => { this.onSelectCountry(c) }
            })
            HierColumn({
              title: this.pickerStore.locationColumnTitle('region'),
              items: this.pickerStore.hierColumnItems('region', this.observerPlanet),
              selected: this.pickerStore.hierarchySelectionFor('region'),
              scroller: this.columnScroller('region'),
              labelOf: (item: string) => this.pickerStore.hierarchyItemLabel('region', item, this.observerPlanet),
              onSelect: (r: string) => { this.onSelectRegion(r) }
            })
            HierColumn({
              title: this.pickerStore.locationColumnTitle('city'),
              items: this.pickerStore.hierColumnItems('city', this.observerPlanet),
              selected: this.pickerStore.hierarchySelectionFor('city'),
              scroller: this.columnScroller('city'),
              labelOf: (item: string) => this.pickerStore.hierarchyItemLabel('city', item, this.observerPlanet),
              onSelect: (c: string) => { this.onSelectCity(c) }
            })
          }
            .width('100%')
            .height(196)
          Text(this.pickerStore.hierarchySelectionSummary(this.observerPlanet))
            .fontSize(11)
            .fontColor(this.pickerStore.hierContinent ? this.c.tertiary : this.c.detailSub)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 7 })
        }
          .width('100%')
          .margin({ top: 8 })
      }

      // Altitude belongs to the staged point. Earth is editable and clamped;
      // non-Earth is read-only and comes from the offline place data.
      Row() {
        Text(I18n.t('i0016')).fontSize(12).fontColor(this.c.tertiary).width(56)
        TextInput({ text: this.pickerStore.locationPickerAltitude.toFixed(0), placeholder: I18n.t('i0067') })
          .height(34)
          .fontSize(13)
          .fontColor(this.isEarth() ? this.c.text : this.c.sub)
          .placeholderColor(this.c.tertiary)
          .backgroundColor(this.c.input)
          .border({ width: 1, color: this.c.inputBorder })
          .borderRadius(UI_RADIUS_CONTROL)
          .layoutWeight(1)
          .enabled(this.isEarth())
          .onChange((value: string) => {
            if (!this.isEarth()) return
            const altitude = Number(value)
            if (Number.isFinite(altitude)) {
              this.pickerStore.locationPickerAltitude = Math.round(clamp(altitude, EARTH_ALTITUDE_MIN, EARTH_ALTITUDE_MAX))
              this.altitudeDirty = true
            }
          })
          // The panel applies selections immediately; the altitude field is the
          // only draft edit, so commit it when the keyboard closes or submits.
          .onSubmit(() => { this.commitAltitude() })
          .onBlur(() => { this.commitAltitude() })
        Text('m').fontSize(11).fontColor(this.c.tertiary).margin({ left: 6 })
      }
      .width('100%')
      .margin({ top: 8 })
      if (!this.isEarth()) {
        Text(I18n.t('loc_altitude_non_earth'))
          .fontSize(10)
          .fontColor(this.c.tertiary)
          .width('100%')
          .margin({ top: 4 })
      }

      // 时区显示
      if (this.pickerStore.observerTimeZone.length > 0) {
        Row() {
          Text(I18n.t('loc_timezone')).fontSize(11).fontColor(this.c.tertiary)
          Text(this.pickerStore.observerTimeZone).fontSize(11).fontColor(this.c.tertiary).margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      Text(this.pickerStore.locationPickerStatus)
        .fontSize(11)
        .fontColor(this.c.sub)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 9 })
    }
       .width('100%')
       .padding({ left: 10, right: 10, top: 10, bottom: 10 })
       .backgroundColor(this.c.soft)
       .border({ width: 1, color: this.c.softStrong })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 8, bottom: 8 })
  }
}
