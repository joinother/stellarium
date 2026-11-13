import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { OFFLINE_APPGALLERY_BUILD } from '../../pages/MainWindowModels'
import { LocSearchItem } from '../../pages/StellariumTypes'
import { LocationStore } from '../../state/LocationStore'
import { LocationPickerStore } from '../../state/LocationPickerStore'
import { SessionToolStore } from '../../state/SessionToolStore'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { CityChipsRow } from '../location/CityChipsRow'
import { LocationPickerPanel } from '../location/LocationPickerPanel'
import { ObserverPlanetSection, TonightEventsSection } from '../astro/SessionToolSections'

// 位置面板，对应 `activePanel === 'place'`：当前观测点卡 + 观测星球 + 位置选择器 +
// 已保存/最近位置 +（非 appgallery 构建下的）今晚天象。指星笔、手表陀螺仪与
// 会话延续分别位于「更多功能 → 开发与诊断」和天文面板「今晚」标签页。
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
  @Prop expandedLayout: boolean
  // 地图几何由 LocationPickerPanel 自算，这里只传它依赖的布局态
  @Prop skyWidth: number
  @Prop fixedObserverPoint: boolean = false
  // Privacy/foreground gate for the online terrain preview. The card still
  // falls back to the offline overview when this is false or the network is down.
  @Prop previewMapAllowed: boolean = false
  // True while the full-screen map is open; the mini-map is unmounted.
  @Prop mapSuspended: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private fixedMapFailed: boolean = false
  planetLabel: (en: string) => string = (en: string) => en
  onOpenFullMap: () => void = () => {}
  contextOf: (item: LocSearchItem) => string = () => ''
  onSearchLocations: (query: string) => void = () => {}
  onPickSearchItem: (item: LocSearchItem) => void = () => {}
  onApply: () => void = () => {}
  onInputFocus: () => void = () => {}
  onInputBlur: () => void = () => {}
  onSelectContinent: (c: string) => void = () => {}
  onSelectCountry: (c: string) => void = () => {}
  onSelectRegion: (r: string) => void = () => {}
  onSelectCity: (c: string) => void = () => {}
  onSaveCurrent: () => void = () => {}
  onApplyLocation: (name: string, lat: number, lon: number, alt: number, planet: string) => void = () => {}
  onDeleteLocation: (key: string) => void = () => {}
  onSelectPlanet: (name: string) => void = () => {}
  onRefreshTonight: () => void = () => {}
  onJump: (jd: number, lock: string, title: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  aboutToAppear(): void {
    // The location panel always opens on the map tab; a search/region tab
    // selected during the previous visit must not become the new default.
    if (this.locationPickerStore.locationPickMode !== 'map') {
      this.locationPickerStore.locationPickMode = 'map'
    }
  }

  private fixedPreviewWidth(): number {
    if (this.expandedLayout) return 292
    return Math.max(276, Math.min(620, this.skyWidth * 0.92 - 32))
  }

  // Fixed observer points ("Earth Observer" etc.) keep the overview image
  // (`obs_earth.jpg`, `obs_mars.jpg`, ...) but disable every picking
  // interaction: the preview is inert and the full-screen entry is not mounted.
  @Builder
  fixedObserverPreview() {
    Stack() {
      if (this.sessionToolStore.observerPlanetMapTexture().length > 0) {
        Image($rawfile('stellarium/textures/' + this.sessionToolStore.observerPlanetMapTexture()))
          .width('100%').height('100%').objectFit(ImageFit.Fill)
          .sourceSize({ width: 1240, height: 620 })
          .onError(() => { this.fixedMapFailed = true })
          .onComplete(() => { this.fixedMapFailed = false })
      }
      if (this.sessionToolStore.observerPlanetMapTexture().length === 0 || this.fixedMapFailed) {
        Text(I18n.t('m_planet_map_unavailable')).fontSize(12).fontColor(this.c.sub)
          .width('76%').textAlign(TextAlign.Center)
      }
      Row()
        .width('100%').height('100%')
        .backgroundColor(this.c.nightMask)
        .hitTestBehavior(HitTestMode.None)
      Text(I18n.t('map_fixed_overview_badge')).fontSize(10).fontColor(this.c.text)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.c.panelGlassStrong)
        .borderRadius(UI_RADIUS_PILL)
        .position({ x: 8, y: 8 })
    }
      .width(this.fixedPreviewWidth())
      .height(this.fixedPreviewWidth() / 2)
      .alignSelf(ItemAlign.Center)
      .clip(true)
      .backgroundColor(this.c.mediaCard)
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 6 })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column() {
      // Two label/value rows: the old three-row layout with altitude folded
      // into the coordinate line. GPS lives in the panel title bar.
      Row() {
        Text(I18n.t('i0014')).fontSize(12).fontColor(this.c.sub).width(72)
        Text(this.locationText).fontSize(14).fontColor(this.c.text).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text(I18n.t('i0015')).fontSize(12).fontColor(this.c.sub).width(72)
        Text(this.coordinateText + (this.altitudeText.length > 0 ? ' · ' + this.altitudeText : ''))
          .fontSize(14).fontColor(this.c.text).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.height(28).width('100%').padding({ left: 10, right: 10 })
      ObserverPlanetSection({ store: this.sessionToolStore, planetLabel: (en: string) => this.planetLabel(en), onSelectPlanet: (name: string) => { this.onSelectPlanet(name) } })
      if (this.fixedObserverPoint) {
        this.fixedObserverPreview()
        Text(I18n.t('map_fixed_overview_point')).fontSize(11).fontColor(this.c.sub)
          .width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 })
      } else {
      LocationPickerPanel({
        pickerStore: this.locationPickerStore,
        locationStore: this.locationStore,
        observerPlanet: this.sessionToolStore.observerPlanet,
        mapTexture: this.sessionToolStore.observerPlanetMapTexture(),
        onlineAllowed: this.previewMapAllowed,
        mapSuspended: this.mapSuspended,
        expandedLayout: this.expandedLayout,
        skyWidth: this.skyWidth,
        onSearchLocations: (query: string) => { this.onSearchLocations(query) },
        onInputFocus: () => { this.onInputFocus() },
        onInputBlur: () => { this.onInputBlur() },
        contextOf: (item: LocSearchItem) => this.contextOf(item),
        onPickSearchItem: (item: LocSearchItem) => { this.onPickSearchItem(item) },
        onApply: () => { this.onApply() },
        onSelectContinent: (c: string) => { this.onSelectContinent(c) },
        onSelectCountry: (c: string) => { this.onSelectCountry(c) },
        onSelectRegion: (r: string) => { this.onSelectRegion(r) },
        onSelectCity: (c: string) => { this.onSelectCity(c) },
        onOpenFullMap: () => { this.onOpenFullMap() }
      })

      CityChipsRow({
        store: this.locationStore,
        observerPlanet: this.sessionToolStore.observerPlanet,
        onSaveCurrent: () => { this.onSaveCurrent() },
        onApplyLocation: (name: string, lat: number, lon: number, alt: number, planet: string) => { this.onApplyLocation(name, lat, lon, alt, planet) },
        onDeleteLocation: (key: string) => { this.onDeleteLocation(key) }
      })
      }
      // Tonight's events stay here; the virtual pointer test and watch gyro
      // simulator moved to More → Development & diagnostics. Session
      // continuation lives in the astro panel's "tonight" tab.
      if (!OFFLINE_APPGALLERY_BUILD) {
        TonightEventsSection({ store: this.sessionToolStore, onRefresh: () => { this.onRefreshTonight() }, onJump: (jd: number, lock: string, title: string) => { this.onJump(jd, lock, title) } })
      }
    }.width('100%')
  }
}
