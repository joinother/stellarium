import { I18n } from '../../pages/I18n'
import { LocSearchItem } from '../../pages/StellariumTypes'
import { clamp } from '../../common/derive/astro'
import { LocationStore } from '../../state/LocationStore'
import { LocationPickerStore } from '../../state/LocationPickerStore'
import { LocationSearchPanel } from './LocationSearchPanel'
import { HierColumn } from '../../common/ui/HierColumn'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 本组件职责：「位置」面板的位置选择器。
//
// 组件收两个 store（搜索簇 + 选择器簇）与一批回调：
//   - 选择器状态（picker 坐标/名称/状态、层级选择、地图渲染尺寸、时区、选点方式）与
//     层级翻译/过滤全部走 @ObjectLink pickerStore（LocationPickerStore），实时刷新；
//   - 离线搜索框复用 LocationSearchPanel，其 store 走 locationStore；
//   - native 桥 / 定时器（使用设备位置、应用、地图点按、层级落地）由宿主完成，以回调注入；
//   - 地图尺寸由宿主按布局算好（mapWidth/mapHeight），夜视三色与输入框底色按 @Prop 传入；
//   - 四列层级列的 Scroller 由本组件自持（columnScrollers）。
//
// 选点方式 chip（地图 / 层级），选中态由 selected 传入。
@Component
export struct LocationModeChip {
  @Prop mode: string
  @Prop label: ResourceStr
  @Prop selected: boolean
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  onSelect: (mode: string) => void = () => {}

  build() {
    Button(this.label)
      .height(28)
      .fontSize(11)
      .fontColor(this.selected ? this.textColor : this.subColor)
      .backgroundColor(this.selected ? this.accentColor : this.panelColor)
      .border({ width: 1, color: this.selected ? 'rgba(107, 163, 214, 0.35)' : 'rgba(255, 255, 255, 0.08)' })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ right: 8 })
      .onClick(() => { this.onSelect(this.mode) })
  }
}

@Component
export struct LocationPickerPanel {
  @ObjectLink pickerStore: LocationPickerStore
  @ObjectLink locationStore: LocationStore
  @Prop observerPlanet: string
  // 地图几何：是否展开由宿主布局态决定。
  @Prop expandedLayout: boolean
  @Prop skyWidth: number
  @Prop subColor: string
  @Prop inputColor: string
  @Prop textColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  onUseDeviceLocation: () => void = () => {}
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

  private columnScrollers: Array<Scroller> = [new Scroller(), new Scroller(), new Scroller(), new Scroller()]
  // 地图触摸草稿（非可观测，随组件持有）。
  private mapTouchStartX: number = 0
  private mapTouchStartY: number = 0
  private mapTouchMoved: boolean = false

  private columnScroller(kind: string): Scroller {
    const index = kind === 'continent' ? 0 : (kind === 'country' ? 1 : (kind === 'region' ? 2 : 3))
    return this.columnScrollers[index]
  }

  // 地图渲染宽度 / 高度。
  private locationMapWidth(): number {
    if (this.expandedLayout) {
      return 292
    }
    return clamp(this.skyWidth * 0.92 - 32, 276, 620)
  }

  private locationMapHeight(): number {
    return this.expandedLayout ? 146 : 156
  }

  // 地图点选 → 反算经纬度并写入 picker。
  private updatePickerFromMap(x: number, y: number): void {
    const width = this.pickerStore.mapRenderWidth
    const height = this.pickerStore.mapRenderHeight
    const latitude = 90 - clamp(y, 0, height) / height * 180
    const longitude = clamp(x, 0, width) / width * 360 - 180
    this.pickerStore.setPickerLocation(I18n.t('custom_location'), latitude, longitude, this.pickerStore.locationPickerAltitude, I18n.t('m_map_selected'))
    this.pickerStore.locationSource = 'map'
    this.locationStore.locSearchQuery = ''
  }

  // 地图触摸处理；点选后的 apply 走 onApply 回调。
  private handleLocationMapTouch(event: TouchEvent): boolean {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length < 1) {
      return false
    }
    const point = points[0]
    if (event.type === TouchType.Down) {
      this.mapTouchStartX = point.x
      this.mapTouchStartY = point.y
      this.mapTouchMoved = false
    } else if (event.type === TouchType.Move) {
      const deltaX = point.x - this.mapTouchStartX
      const deltaY = point.y - this.mapTouchStartY
      if (Math.sqrt(deltaX * deltaX + deltaY * deltaY) > 10) this.mapTouchMoved = true
    } else if (event.type === TouchType.Up) {
      if (!this.mapTouchMoved) {
        this.updatePickerFromMap(point.x, point.y)
        this.onApply()
      }
      this.mapTouchMoved = false
    } else if (event.type === TouchType.Cancel) {
      this.mapTouchMoved = false
    }
    // Do not take ownership of a vertical panel scroll. A deliberate stationary
    // tap still chooses the map point, while swiping across the map scrolls the panel.
    return false
  }

  build() {
    Column() {
      Row() {
        Text(I18n.t('i0037'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E5FFFFFF')
          .layoutWeight(1)
        Row() {
            Image($r('app.media.ic_location')).width(14).height(14).fillColor('#FFFFFFFF')
            Text(I18n.t('i0052')).fontSize(11).fontColor('#FFFFFFFF').margin({ left: 4 })
          }
          .height(30)
          .padding({ left: 12, right: 12 })
          .backgroundColor('#5B93BF')
          .borderRadius(UI_RADIUS_PILL)
          .onClick(() => { this.onUseDeviceLocation() })
      }
        .width('100%')

      Row() {
        LocationModeChip({
          mode: 'map', label: I18n.t('s0715'), selected: this.pickerStore.locationPickMode === 'map',
          textColor: this.textColor, subColor: this.subColor, accentColor: this.accentColor, panelColor: this.panelColor,
          onSelect: (mode: string) => { this.pickerStore.locationPickMode = mode }
        })
        LocationModeChip({
          mode: 'hierarchy', label: I18n.t('s0716'), selected: this.pickerStore.locationPickMode === 'hierarchy',
          textColor: this.textColor, subColor: this.subColor, accentColor: this.accentColor, panelColor: this.panelColor,
          onSelect: (mode: string) => { this.pickerStore.locationPickMode = mode }
        })
      }
        .width('100%')
        .margin({ top: 10 })

      LocationSearchPanel({
        store: this.locationStore,
        subColor: this.subColor,
        inputColor: this.inputColor,
        onSearch: (query: string) => { this.onSearchLocations(query) },
        onNameDraft: (name: string) => { this.pickerStore.locationPickerName = name },
        onInputFocus: () => { this.onInputFocus() },
        onInputBlur: () => { this.onInputBlur() },
        contextOf: (item: LocSearchItem) => this.contextOf(item),
        onPickItem: (item: LocSearchItem) => { this.onPickSearchItem(item) }
      })

      if (this.pickerStore.locationPickMode === 'map') {
        Stack() {
          Image($rawfile('worldmap.jpg'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
          // 经纬度刻度
          Text('N').fontSize(10).fontColor('#99FFFFFF').position({ x: 6, y: 4 })
          Text('S').fontSize(10).fontColor('#99FFFFFF').position({ x: 6, y: this.pickerStore.mapRenderHeight - 16 })
          Text('90°W').fontSize(10).fontColor('#CC8FB6FF').position({ x: 4, y: Math.round(this.pickerStore.mapRenderHeight / 2) - 4 })
          Text('90°E').fontSize(10).fontColor('#CC8FB6FF').position({ x: this.pickerStore.mapRenderWidth - 32, y: Math.round(this.pickerStore.mapRenderHeight / 2) - 4 })
          Text(I18n.t('i0040'))
            .fontSize(18)
            .fontColor('#7FB3DC')
            .textShadow({ radius: 8, color: 'rgba(159, 232, 255, 0.75)', offsetX: 0, offsetY: 0 })
            .position({ x: this.pickerStore.pickerPinX(), y: this.pickerStore.pickerPinY() })
        }
          .width(this.locationMapWidth())
          .height(this.locationMapHeight())
          .alignSelf(ItemAlign.Center)
          .clip(true)
          .backgroundColor('rgba(11, 24, 43, 0.46)')
          .border({ width: 1, color: 'rgba(159, 232, 255, 0.22)' })
          .borderRadius(UI_RADIUS_CONTROL)
          .margin({ top: 10 })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            this.pickerStore.mapRenderWidth = Number(newArea.width)
            this.pickerStore.mapRenderHeight = Number(newArea.height)
          })
          .onTouch((event: TouchEvent) => this.handleLocationMapTouch(event))
        Text(this.pickerStore.pickerCoordinateText())
          .fontSize(12)
          .fontColor('#99FFFFFF')
          .width('100%')
          .margin({ top: 8 })
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
            .fontColor(this.pickerStore.hierContinent ? '#A9D9F5' : '#7F96AE')
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 7 })
          Text(this.pickerStore.pickerCoordinateText())
            .fontSize(12)
            .fontColor('#99FFFFFF')
            .width('100%')
            .margin({ top: 8 })
        }
          .width('100%')
          .margin({ top: 10 })
      }

      Row() {
        Text(I18n.t('i0016')).fontSize(12).fontColor('#8EA0BD').width(56)
        TextInput({ text: this.pickerStore.locationPickerAltitude.toFixed(0), placeholder: I18n.t('i0067') })
          .height(34)
          .fontSize(13)
          .fontColor('#E5FFFFFF')
          .placeholderColor('#8EA0BD')
          .backgroundColor('rgba(255, 255, 255, 0.06)')
          .border({ width: 1, color: 'rgba(214, 238, 255, 0.14)' })
          .borderRadius(UI_RADIUS_CONTROL)
          .layoutWeight(1)
          .onChange((value: string) => {
            const altitude = Number(value)
            if (Number.isFinite(altitude)) {
              this.pickerStore.locationPickerAltitude = Math.round(altitude)
            }
          })
        Text('m').fontSize(11).fontColor('#8EA0BD').margin({ left: 6 })
      }
      .width('100%')
      .margin({ top: 8 })
      // 时区显示
      if (this.pickerStore.observerTimeZone.length > 0) {
        Row() {
          Text(I18n.t('loc_timezone')).fontSize(11).fontColor('#8EA0BD')
          Text(this.pickerStore.observerTimeZone).fontSize(11).fontColor('#7FB3DC').margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      Row() {
        Row() {
            Image($r('app.media.ic_globe')).width(14).height(14).fillColor('#FFFFFFFF')
            Text(I18n.t('i0053')).fontSize(12).fontColor('#FFFFFF').margin({ left: 4 })
          }
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor('#5B93BF')
          .borderRadius(UI_RADIUS_PILL)
          .margin({ right: 8 })
          .onClick(() => { this.onApply() })
        Text(this.pickerStore.locationPickerStatus)
          .fontSize(11)
          .fontColor('#99FFFFFF')
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
        .width('100%')
        .margin({ top: 9 })
    }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .backgroundColor('rgba(107, 163, 214, 0.12)')
      .border({ width: 1, color: 'rgba(107, 163, 214, 0.20)' })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 8, bottom: 8 })
  }
}
