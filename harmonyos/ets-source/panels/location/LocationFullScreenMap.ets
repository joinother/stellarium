import { Theme } from '@kit.ArkUI'
import { map, mapCommon, MapComponent, site } from '@kit.MapKit'
import { image } from '@kit.ImageKit'
import { AsyncCallback, BusinessError } from '@ohos.base'
import { I18n } from '../../pages/I18n'
import { LocationStore } from '../../state/LocationStore'
import { LocSearchItem } from '../../pages/StellariumTypes'
import { inverseMapPoint, MapPoint } from '../../pages/MapCoordinate'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { LocationRasterMap } from './LocationRasterMap'

interface MapApiSearchResult {
  name: string
  address: string
  latitude: number
  longitude: number
  source: string
}

function rawMapPath(planet: string, mapTexture: string, hires: boolean): string {
  if (planet === 'Earth') {
    return hires ? 'stellarium/data/gui/miscWorldMap.jpg' : 'worldmap.jpg'
  }
  if (planet === 'Moon') {
    return hires ? 'stellarium/textures/moon_4k.jpg' : 'stellarium/textures/moon.png'
  }
  // Mars and every other body use their tex_map PNG. Do not use obs_*.jpg here:
  // those are observer diagrams (planet plus moon orbits on a black background),
  // not equirectangular surface maps; wrapping one around the globe looks wrong.
  if (/^[a-zA-Z0-9_.-]+\.(png|jpg|jpeg)$/i.test(mapTexture)) {
    return 'stellarium/textures/' + mapTexture
  }
  return 'worldmap.jpg'
}

// The 3D globe consumes an equirectangular texture; a 2D ImageOverlay is
// stretched in Web Mercator. Use a pre-warped square texture for the 2D phase
// so features stay aligned when Map Kit switches to 2D at zoom >= 4.
function mercatorMapPath(planet: string, mapTexture: string): string {
  if (planet === 'Moon') return 'stellarium/textures/moon_4k_mercator.jpg'
  if (/^[a-zA-Z0-9_.-]+\.(png|jpg|jpeg)$/i.test(mapTexture)) {
    const base = mapTexture.replace(/\.(png|jpg|jpeg)$/i, '')
    return 'stellarium/textures/' + base + '_mercator.jpg'
  }
  return rawMapPath(planet, mapTexture, true)
}

// Bodies with a reliable global surface map. Minor bodies such as Eris have a
// texture that is not suitable for a detailed 2D picker; keep them on the 3D
// globe only instead of letting Map Kit switch to a distorted 2D overlay.
function supports2DMap(planet: string): boolean {
  return ['Earth', 'Moon', 'Mars', 'Venus', 'Mercury',
    'Jupiter', 'Saturn', 'Uranus', 'Neptune'].includes(planet)
}

// Full-screen location picker. It deliberately starts from a raster fallback
// and only replaces it with Map Kit once mapLoad fires; a missing AGC profile,
// airplane mode or an unsupported emulator therefore never leaves a blank map.
@Component
export struct LocationFullScreenMap {
  @ObjectLink locationStore: LocationStore
  @Prop observerPlanet: string = 'Earth'
  @Prop latitude: number = 0
  @Prop longitude: number = 0
  @Prop mapTexture: string = ''
  @Prop mapAllowed: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private rasterPath: string = 'worldmap.jpg'
  @State private mapStarted: boolean = false
  @State private mapReady: boolean = false
  @State private loading: boolean = false
  @State private draftLat: number = 0
  @State private draftLon: number = 0
  @State private hasDraft: boolean = false
  @State private searchQuery: string = ''
  @State private searchSource: string = 'none'
  @State private searchResults: Array<MapApiSearchResult> = []
  @State private searching: boolean = false
  @State private searchTimer: number = -1
  private controller?: map.MapComponentController
  private marker?: map.Marker
  private planetSurfaceOverlay?: map.ImageOverlay
  private timeoutId: number = -1
  private options: mapCommon.MapOptions = {
    position: { target: { latitude: 0, longitude: 0 }, zoom: 2 },
    mapType: mapCommon.MapType.STANDARD,
    sphereEnabled: true,
    minZoom: 2,
    maxZoom: 20,
    rotateGesturesEnabled: true,
    tiltGesturesEnabled: true,
    myLocationControlsEnabled: false,
    zoomControlsEnabled: false
  }
  private callback: AsyncCallback<map.MapComponentController> = (error: BusinessError,
    controller: map.MapComponentController): void => {
    if (error) {
      this.fallback()
      return
    }
    this.controller = controller
    const events = controller.getEventManager()
    events.on('mapLoad', () => {
      this.mapReady = true
      this.loading = false
      this.clearTimeout()
      if (this.observerPlanet !== 'Earth') this.applySphereTexture()
    })
    events.on('error', (_error: BusinessError) => { this.fallback() })
    events.on('cameraIdle', () => { this.syncPlanet2DOverlay() })
    events.on('mapClick', (position: mapCommon.LatLng) => { this.handleMapClick(position) })
  }
  onPick: (latitude: number, longitude: number) => void = () => {}
  onClose: () => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  aboutToAppear(): void {
    this.draftLat = this.latitude
    this.draftLon = this.longitude
    this.rasterPath = rawMapPath(this.observerPlanet, this.mapTexture, true)
    if (!this.mapAllowed) return
    // Reuse the Map Kit globe/camera/click pipeline for every body. Earth uses
    // the Petal base map; other bodies replace the globe surface with their
    // Stellarium texture through SphereParams.
    this.options.mapType = this.observerPlanet === 'Earth'
      ? mapCommon.MapType.STANDARD : mapCommon.MapType.NONE
    // Map Kit switches to 2D at zoom >= 4. Minor bodies without a reliable
    // global map stay on the 3D globe; they never enter the 2D renderer.
    this.options.maxZoom = supports2DMap(this.observerPlanet) ? 20 : 3
    this.options.position = {
      target: { latitude: this.latitude, longitude: this.longitude },
      zoom: 2
    }
    this.mapStarted = true
    this.loading = true
    this.timeoutId = setTimeout(() => {
      if (!this.mapReady) this.fallback()
    }, 15000)
  }

  aboutToDisappear(): void {
    this.clearTimeout()
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer)
      this.searchTimer = -1
    }
    this.planetSurfaceOverlay?.remove()
    this.planetSurfaceOverlay = undefined
    this.controller = undefined
    this.marker = undefined
  }

  private clearTimeout(): void {
    if (this.timeoutId >= 0) {
      clearTimeout(this.timeoutId)
      this.timeoutId = -1
    }
  }

  private fallback(): void {
    this.clearTimeout()
    this.mapStarted = false
    this.mapReady = false
    this.loading = false
    this.planetSurfaceOverlay?.remove()
    this.planetSurfaceOverlay = undefined
    this.controller = undefined
    this.marker = undefined
    this.searchSource = 'local'
  }

  private async applySphereTexture(): Promise<void> {
    const controller = this.controller
    if (!controller || this.observerPlanet === 'Earth') return
    try {
      const context = this.getUIContext().getHostContext()
      if (!context) throw new Error('No context')
      const bytes = await context.resourceManager.getRawFileContent(this.rasterPath)
      const source = image.createImageSource(bytes.buffer as ArrayBuffer)
      const pixelMap = await source.createPixelMap()
      await controller.setSphereMapEnabled(true, {
        sunLightEnabled: false,
        cityLightEnabled: false,
        animateDuration: 0,
        coverageImage: pixelMap
      })
      pixelMap.release()
      source.release()
    } catch (_error) {
      this.fallback()
    }
  }

  // Map Kit switches from the 3D globe to the 2D Mercator map around zoom 4.
  // coverageImage only paints the globe; without a 2D overlay the empty
  // MapType.NONE map shows its green background. Add the same planet texture as
  // a 2D ImageOverlay at/after the transition and remove it when back on globe.
  private async syncPlanet2DOverlay(): Promise<void> {
    const controller = this.controller
    if (!controller || this.observerPlanet === 'Earth' || !this.mapReady) return
    if (!supports2DMap(this.observerPlanet)) {
      if (this.planetSurfaceOverlay) {
        this.planetSurfaceOverlay.remove()
        this.planetSurfaceOverlay = undefined
      }
      return
    }
    try {
      const zoom = controller.getCameraPosition().zoom
      if (zoom >= 4) {
        if (this.planetSurfaceOverlay) return
        this.planetSurfaceOverlay = await controller.addImageOverlay({
          bounds: {
            southwest: { latitude: -85.0511, longitude: -180 },
            northeast: { latitude: 85.0511, longitude: 180 }
          },
          image: mercatorMapPath(this.observerPlanet, this.mapTexture),
          transparency: 0,
          clickable: false
        })
      } else if (this.planetSurfaceOverlay) {
        this.planetSurfaceOverlay.remove()
        this.planetSurfaceOverlay = undefined
      }
    } catch (_error) {
      // Keep the globe surface; the user can still pick on the visible globe.
    }
  }

  private async toWgs84(position: mapCommon.LatLng): Promise<mapCommon.LatLng> {
    if (this.observerPlanet !== 'Earth') return position
    let candidate: MapPoint = position
    try {
      candidate = inverseMapPoint(position, (point: MapPoint): MapPoint =>
        map.convertCoordinateSync(mapCommon.CoordinateType.WGS84, mapCommon.CoordinateType.GCJ02, point))
    } catch (_error) {
      candidate = position
    }
    // rectifyCoordinate only supports WGS84 -> GCJ02. Feed the candidate as
    // WGS84 and verify that it comes back to the clicked map coordinate; this
    // distinguishes a mainland GCJ02 click from an overseas WGS84 click.
    try {
      const context = this.getUIContext().getHostContext()
      if (!context) return position
      const points = await map.rectifyCoordinate(context, [{
        coordinateType: mapCommon.CoordinateType.WGS84,
        location: candidate
      }])
      if (points && points.length > 0 &&
        points[0].coordinateType === mapCommon.CoordinateType.GCJ02 &&
        Math.abs(points[0].location.latitude - position.latitude) < 0.00002 &&
        Math.abs(points[0].location.longitude - position.longitude) < 0.00002) {
        return candidate
      }
    } catch (_error) {
      // Fall through to the original map coordinate.
    }
    return position
  }

  private async handleMapClick(position: mapCommon.LatLng): Promise<void> {
    const point = await this.toWgs84(position)
    this.setDraft(point.latitude, point.longitude)
  }

  private async setDraft(latitude: number, longitude: number): Promise<void> {
    this.draftLat = latitude
    this.draftLon = longitude
    this.hasDraft = true
    if (!this.controller) return
    const position: mapCommon.LatLng = { latitude: latitude, longitude: longitude }
    try {
      if (this.marker) {
        this.marker.setPosition(position)
      } else {
        this.marker = await this.controller.addMarker({ position: position })
      }
    } catch (_error) {
      // Keep the draft even if the marker layer is unavailable.
    }
  }

  private useDraft(): void {
    this.onPick(this.draftLat, this.draftLon)
    this.onClose()
  }

  private zoomBy(delta: number): void {
    const controller = this.controller
    if (!controller) return
    try {
      const camera = controller.getCameraPosition()
      const maxZoom = supports2DMap(this.observerPlanet) ? 20 : 3
      const zoom = Math.max(2, Math.min(maxZoom, camera.zoom + delta))
      controller.moveCamera(map.newCameraPosition({ target: camera.target, zoom: zoom }))
    } catch (_error) {
      // Keep the current camera if the SDK rejects the update.
    }
  }

  private scheduleSearch(): void {
    if (this.searchTimer >= 0) clearTimeout(this.searchTimer)
    const query = this.searchQuery.trim()
    if (query.length === 0) {
      this.searchResults = []
      this.searching = false
      this.searchSource = 'none'
      return
    }
    if (this.observerPlanet !== 'Earth') return
    this.searchTimer = setTimeout(() => { this.searchPetal(query) }, 300)
  }

  private async searchPetal(query: string): Promise<void> {
    if (query.length === 0) return
    this.searching = true
    this.searchSource = 'petal'
    this.searchResults = []
    try {
      const result = await site.searchByText({
        query: query,
        language: I18n.isChineseLanguage() ? 'zh' : 'en'
      })
      const sites = result.sites === undefined ? [] : result.sites
      const mapped: Array<MapApiSearchResult> = []
      for (const item of sites) {
        if (!item.location) continue
        const point = await this.toWgs84(item.location)
        mapped.push({
          name: item.name ?? item.formatAddress ?? query,
          address: item.formatAddress ?? '',
          latitude: point.latitude,
          longitude: point.longitude,
          source: 'petal'
        })
        if (mapped.length >= 20) break
      }
      if (mapped.length > 0) {
        this.searchResults = mapped
        this.searchSource = 'petal'
        this.searching = false
        return
      }
      this.searchLocal(query)
    } catch (_error) {
      this.searchLocal(query)
    }
  }

  private searchLocal(query: string): void {
    this.searchSource = 'local'
    this.searchResults = []
    this.searching = true
    this.locationStore.searchLocations(query)
  }

  private localResults(): Array<LocSearchItem> {
    return this.searchSource === 'local' ? this.locationStore.locSearchResults : []
  }

  private hideKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (_error) {
      // The IME may already be closed.
    }
  }

  private chooseApiResult(item: MapApiSearchResult): void {
    this.setDraft(item.latitude, item.longitude)
    if (this.controller) this.controller.moveCamera(map.newLatLng({
      latitude: item.latitude, longitude: item.longitude
    }))
    this.searchResults = []
    this.searchSource = 'none'
    this.hideKeyboard()
  }

  private chooseLocalResult(item: LocSearchItem): void {
    this.setDraft(item.lat, item.lon)
    if (this.controller) this.controller.moveCamera(map.newLatLng({
      latitude: item.lat, longitude: item.lon
    }))
    this.locationStore.locSearchResults = []
    this.searchSource = 'none'
    this.hideKeyboard()
  }

  private surfaceLabel(): string {
    if (this.mapReady) return I18n.t('map_surface_online')
    return I18n.t('map_surface_raster')
  }

  @Builder
  searchResultsView() {
    if (this.searchSource === 'petal' && this.searchResults.length > 0) {
      Column({ space: 2 }) {
        ForEach(this.searchResults, (item: MapApiSearchResult) => {
          Column() {
            Text(item.name).fontSize(12).fontColor(this.c.text).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            if (item.address.length > 0) {
              Text(item.address).fontSize(10).fontColor(this.c.sub).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }
          }
            .alignItems(HorizontalAlign.Start).width('100%').padding(8)
            .backgroundColor(this.c.soft).borderRadius(4)
            .onClick(() => { this.chooseApiResult(item) })
        }, (item: MapApiSearchResult) => item.latitude.toString() + item.longitude.toString() + item.name)
      }
        .width('100%').constraintSize({ maxHeight: 220 })
        .margin({ top: 4 }).padding(4)
        .backgroundColor(this.c.panelGlassStrong).borderRadius(6)
    } else if (this.searchSource === 'local' && this.localResults().length > 0) {
      Column({ space: 2 }) {
        ForEach(this.localResults(), (item: LocSearchItem) => {
          Column() {
            Text(item.displayName ?? item.name).fontSize(12).fontColor(this.c.text).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            Text(item.planet).fontSize(10).fontColor(this.c.sub).width('100%')
          }
            .alignItems(HorizontalAlign.Start).width('100%').padding(8)
            .backgroundColor(this.c.soft).borderRadius(4)
            .onClick(() => { this.chooseLocalResult(item) })
        }, (item: LocSearchItem) => item.name + item.lat.toString() + item.planet)
      }
        .width('100%').constraintSize({ maxHeight: 220 })
        .margin({ top: 4 }).padding(4)
        .backgroundColor(this.c.panelGlassStrong).borderRadius(6)
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.mapStarted) {
        MapComponent({ mapOptions: this.options, mapCallback: this.callback })
          .width('100%').height('100%')
        if (!this.mapReady) {
          LocationRasterMap({
            imagePath: this.rasterPath,
            latitude: this.draftLat,
            longitude: this.draftLon,
            interactive: false
          })
        }
      } else {
        LocationRasterMap({
          imagePath: this.rasterPath,
          latitude: this.draftLat,
          longitude: this.draftLon,
          interactive: true,
          onPick: (latitude: number, longitude: number) => { this.setDraft(latitude, longitude) }
        })
      }

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Button(I18n.t('map_close')).fontSize(11).height(30)
            .backgroundColor(this.c.soft).fontColor(this.c.text)
            .onClick(() => { this.onClose() })
          Column() {
            Text(I18n.t('map_tool_title')).fontSize(13).fontColor(this.c.text).width('100%')
            Text(this.observerPlanet + ' · ' + this.surfaceLabel()).fontSize(10).fontColor(this.c.sub).width('100%')
            if (this.observerPlanet !== 'Earth' && !supports2DMap(this.observerPlanet)) {
              Text(I18n.t('map_global_only')).fontSize(9).fontColor(this.c.tertiary).width('100%')
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding(10).backgroundColor(this.c.panelGlassStrong)

        if (this.observerPlanet === 'Earth') {
          Row({ space: 6 }) {
            TextInput({ text: this.searchQuery, placeholder: I18n.t('map_search_placeholder') })
              .height(36).fontSize(12).layoutWeight(1)
              .backgroundColor(this.c.input).fontColor(this.c.text).placeholderColor(this.c.sub)
              .borderRadius(4)
              .onChange((value: string) => {
                this.searchQuery = value
                this.scheduleSearch()
              })
              .onSubmit(() => {
                if (this.searchTimer >= 0) clearTimeout(this.searchTimer)
                this.searchPetal(this.searchQuery.trim())
              })
            if (this.searchSource === 'local' ? this.locationStore.locSearching : this.searching) {
              LoadingProgress().width(18).height(18).color(this.c.accent)
            }
          }.width('100%').padding({ left: 10, right: 10 })
          if (this.searchSource === 'local') {
            Text(I18n.t('map_search_local_hint')).fontSize(9).fontColor(this.c.sub)
              .width('100%').padding({ left: 10, right: 10 })
          }
          this.searchResultsView()
        } else {
          Text(I18n.t('map_search_disabled')).fontSize(10).fontColor(this.c.sub)
            .width('100%').padding({ left: 10, right: 10 })
        }
      }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

      if (this.loading) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color(this.c.sub)
          Text(I18n.t('map_online_loading')).fontSize(11).fontColor(this.c.sub)
        }.padding(10).backgroundColor(this.c.panelGlassStrong).borderRadius(6)
          .position({ x: 16, y: 120 })
      }

      Column({ space: 8 }) {
        Text('+').fontSize(22).fontColor(this.c.text).width(40).height(40)
          .textAlign(TextAlign.Center).backgroundColor(this.c.panelGlassStrong)
          .borderRadius(20)
          .onClick(() => { this.zoomBy(1) })
        Text('−').fontSize(24).fontColor(this.c.text).width(40).height(40)
          .textAlign(TextAlign.Center).backgroundColor(this.c.panelGlassStrong)
          .borderRadius(20)
          .onClick(() => { this.zoomBy(-1) })
      }
        .position({ x: 12, y: 260 })
        .zIndex(2)

      Column({ space: 4 }) {
        Text(this.draftLat.toFixed(4) + '° / ' + this.draftLon.toFixed(4) + '°')
          .fontSize(12).fontColor(this.c.text).width('100%')
        Row({ space: 8 }) {
          Button(I18n.t('map_use_point')).fontSize(12).layoutWeight(1)
            .enabled(this.hasDraft).onClick(() => { this.useDraft() })
          Button(I18n.t('map_close')).fontSize(12).layoutWeight(1)
            .backgroundColor(this.c.soft).fontColor(this.c.text)
            .onClick(() => { this.onClose() })
        }.width('100%')
      }
        .width('100%').padding(10).backgroundColor(this.c.panelGlassStrong)
        .position({ x: 0, y: '100%' })
        .translate({ y: -90 })
    }
      .width('100%').height('100%')
      .backgroundColor('#FF0B0F14')
  }
}
