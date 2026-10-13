import { I18n } from '../../pages/I18n'
import { OFFLINE_APPGALLERY_BUILD } from '../../pages/MainWindowModels'
import { LocSearchItem } from '../../pages/StellariumTypes'
import { LocationStore } from '../../state/LocationStore'
import { LocationPickerStore } from '../../state/LocationPickerStore'
import { SessionToolStore } from '../../state/SessionToolStore'
import { CityChipsRow } from '../location/CityChipsRow'
import { LocationPickerPanel } from '../location/LocationPickerPanel'
import { LocationMapSection } from '../location/LocationMapSection'
import { ContinuationSection } from '../astro/ContinuationSection'
import { ObserverPlanetSection, PointingTestSection, WatchGyroSection, TonightEventsSection } from '../astro/SessionToolSections'

// 位置面板，对应 `activePanel === 'place'`：三个顶部信息行 + 位置选择器 + 已保存城市行 +
// 观测星球 +（非 appgallery 构建下的）指星笔 / 手表陀螺仪 / 会话延续 / 今晚天象。
//
// 三个 store 走 @ObjectLink，文本与颜色走 @Prop，native 桥/定时器/快捷键动作回调注入宿主。

@Component
export struct PlacePanel {
  @ObjectLink locationPickerStore: LocationPickerStore
  @ObjectLink locationStore: LocationStore
  @ObjectLink sessionToolStore: SessionToolStore
  @Prop locationText: string
  @Prop coordinateText: string
  @Prop altitudeText: string
  // 地图几何由 LocationPickerPanel 自算，这里只传它依赖的布局态
  @Prop expandedLayout: boolean
  @Prop skyWidth: number
  @Prop textColor: string
  @Prop subColor: string
  @Prop inputColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop borderTint: string
  @Prop mapAllowed: boolean
  planetLabel: (en: string) => string = (en: string) => en
  contextOf: (item: LocSearchItem) => string = () => ''
  onUseDeviceLocation: () => void = () => {}
  onSearchLocations: (query: string) => void = () => {}
  onPickSearchItem: (item: LocSearchItem) => void = () => {}
  onApply: () => void = () => {}
  onSelectMapProvider: (provider: string) => void = () => {}
  onInputFocus: () => void = () => {}
  onInputBlur: () => void = () => {}
  onPickMap: (latitude: number, longitude: number) => void = () => {}
  onMapFallback: () => void = () => {}
  onSelectContinent: (c: string) => void = () => {}
  onSelectCountry: (c: string) => void = () => {}
  onSelectRegion: (r: string) => void = () => {}
  onSelectCity: (c: string) => void = () => {}
  onSaveCurrent: () => void = () => {}
  onApplyLocation: (name: string, lat: number, lon: number, alt: number, planet: string) => void = () => {}
  onDeleteLocation: (name: string) => void = () => {}
  onChip: (id: string) => void = () => {}
  onSelectPlanet: (name: string) => void = () => {}
  onPoint: () => void = () => {}
  onSend: () => void = () => {}
  onStart: () => void = () => {}
  onStop: () => void = () => {}
  onExport: () => void = () => {}
  onSessionApply: () => void = () => {}
  onHandoff: () => void = () => {}
  onRefreshTonight: () => void = () => {}
  onJump: (jd: number, lock: string, title: string) => void = () => {}

  build() {
    Column() {
      Row() {
        Text(I18n.t('i0014')).fontSize(12).fontColor('#99FFFFFF').width(72)
        Text(this.locationText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text(I18n.t('i0015')).fontSize(12).fontColor('#99FFFFFF').width(72)
        Text(this.coordinateText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text(I18n.t('i0016')).fontSize(12).fontColor('#99FFFFFF').width(72)
        Text(this.altitudeText).fontSize(14).fontColor('#E5FFFFFF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      LocationPickerPanel({
        pickerStore: this.locationPickerStore,
        locationStore: this.locationStore,
        observerPlanet: this.sessionToolStore.observerPlanet,
        expandedLayout: this.expandedLayout,
        skyWidth: this.skyWidth,
        subColor: this.subColor,
        inputColor: this.inputColor,
        textColor: this.textColor,
        accentColor: this.accentColor,
        panelColor: this.panelColor,
        onUseDeviceLocation: () => { this.onUseDeviceLocation() },
        onSearchLocations: (query: string) => { this.onSearchLocations(query) },
        onInputFocus: () => { this.onInputFocus() },
        onInputBlur: () => { this.onInputBlur() },
        contextOf: (item: LocSearchItem) => this.contextOf(item),
        onPickSearchItem: (item: LocSearchItem) => { this.onPickSearchItem(item) },
        onApply: () => { this.onApply() },
        onSelectContinent: (c: string) => { this.onSelectContinent(c) },
        onSelectCountry: (c: string) => { this.onSelectCountry(c) },
        onSelectRegion: (r: string) => { this.onSelectRegion(r) },
        onSelectCity: (c: string) => { this.onSelectCity(c) }
      })
      LocationMapSection({
        provider: this.locationStore.locationMapProvider,
        latitude: this.locationPickerStore.locationPickerLatitude,
        longitude: this.locationPickerStore.locationPickerLongitude,
        mapAllowed: this.mapAllowed,
        textColor: this.textColor,
        subColor: this.subColor,
        accentColor: this.accentColor,
        panelColor: this.panelColor,
        onSelectProvider: (provider: string) => { this.onSelectMapProvider(provider) },
        onPick: (latitude: number, longitude: number) => { this.onPickMap(latitude, longitude) },
        onFallback: () => { this.onMapFallback() }
      })
      CityChipsRow({
        store: this.locationStore,
        onSaveCurrent: () => { this.onSaveCurrent() },
        onApplyLocation: (name: string, lat: number, lon: number, alt: number, planet: string) => { this.onApplyLocation(name, lat, lon, alt, planet) },
        onDeleteLocation: (name: string) => { this.onDeleteLocation(name) },
        onChip: (id: string) => { this.onChip(id) }
      })
      ObserverPlanetSection({ store: this.sessionToolStore, textColor: this.textColor, borderTint: this.borderTint, planetLabel: (en: string) => this.planetLabel(en), onSelectPlanet: (name: string) => { this.onSelectPlanet(name) } })
      // These are developer scaffolding screens, not release-ready features.
      if (!OFFLINE_APPGALLERY_BUILD) {
        PointingTestSection({ store: this.sessionToolStore, textColor: this.textColor, borderTint: this.borderTint, onPoint: () => { this.onPoint() } })
        WatchGyroSection({ store: this.sessionToolStore, textColor: this.textColor, onSend: () => { this.onSend() }, onStart: () => { this.onStart() }, onStop: () => { this.onStop() } })
        ContinuationSection({ hint: this.sessionToolStore.sessionHint, json: this.sessionToolStore.sessionJson, textColor: this.textColor, panelColor: this.borderTint, onExport: () => { this.onExport() }, onApply: () => { this.onSessionApply() }, onHandoff: () => { this.onHandoff() } })
        TonightEventsSection({ store: this.sessionToolStore, textColor: this.textColor, onRefresh: () => { this.onRefreshTonight() }, onJump: (jd: number, lock: string, title: string) => { this.onJump(jd, lock, title) } })
      }
    }.width('100%')
  }
}
