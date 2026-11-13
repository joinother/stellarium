import { Theme } from '@kit.ArkUI'
import { map, mapCommon, MapComponent, site } from '@kit.MapKit'
import { image } from '@kit.ImageKit'
import { connection } from '@kit.NetworkKit'
import { AsyncCallback, BusinessError } from '@ohos.base'
import hilog from '@ohos.hilog'
import { I18n } from '../../pages/I18n'
import { LocationStore, OfflinePlaceAltitude } from '../../state/LocationStore'
import { LocSearchItem } from '../../pages/StellariumTypes'
import { LocationPort } from '../../bridge/LocationPort'
import { inverseMapPoint, MapPoint } from '../../pages/MapCoordinate'
import { smallestAdminDivision } from '../../common/location/ReverseGeocodeName'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { METERED_MAP_APIS_ENABLED } from '../../common/config/OhosFeatureFlags'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { UI_RADIUS_CONTROL, UI_RADIUS_PANEL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

interface MapApiSearchResult {
  name: string
  address: string
  cityName: string
  latitude: number
  longitude: number
  mapLatitude: number
  mapLongitude: number
  source: string
}

function surfaceTexturePath(planet: string, mapTexture: string): string {
  // Earth's offline globe uses the colour surface map, not the flat political
  // world map. Non-Earth bodies use their tex_map PNG; obs_*.jpg are observer
  // diagrams (planet plus moon orbits), not equirectangular surface maps.
  if (planet === 'Earth') return 'stellarium/textures/earth_cmap.png'
  if (planet === 'Moon') return 'stellarium/textures/moon_4k.jpg'
  if (/^[a-zA-Z0-9_.-]+\.(png|jpg|jpeg)$/i.test(mapTexture)) {
    return 'stellarium/textures/' + mapTexture
  }
  return ''
}

// The 3D globe consumes an equirectangular texture; a 2D ImageOverlay is
// stretched in Web Mercator. Use a pre-warped square texture for the 2D phase
// so features stay aligned when Map Kit switches to 2D at zoom >= 4.
function mercatorMapPath(planet: string, mapTexture: string): string {
  if (planet === 'Earth') return 'stellarium/textures/earth_cmap_mercator.jpg'
  if (planet === 'Moon') return 'stellarium/textures/moon_4k_mercator.jpg'
  if (/^[a-zA-Z0-9_.-]+\.(png|jpg|jpeg)$/i.test(mapTexture)) {
    const base = mapTexture.replace(/\.(png|jpg|jpeg)$/i, '')
    return 'stellarium/textures/' + base + '_mercator.jpg'
  }
  return ''
}

// Bodies with a reliable global surface map. Minor bodies such as Eris have a
// texture that is not suitable for a detailed 2D picker; keep them on the 3D
// globe only instead of letting Map Kit switch to a distorted 2D overlay.
function supports2DMap(planet: string): boolean {
  return ['Earth', 'Moon', 'Mars', 'Venus', 'Mercury',
    'Jupiter', 'Saturn', 'Uranus', 'Neptune'].includes(planet)
}

// Full-screen location picker built directly on Map Kit. There is no raster
// fallback: when Map Kit cannot provide a usable surface (missing planet
// texture, an HMS Map service without setSphereMapEnabled, privacy or
// foreground gate), the picker shows a retryable error instead of silently
// switching to a flat image.
//
// The layout is map-first: the Map Kit globe stays full-bleed and the search /
// action UI is overlaid. Phones use a floating search bar and a bottom action
// card; tablets use a left side panel and pad the map camera away from it.
@Component
export struct LocationFullScreenMap {
  @ObjectLink locationStore: LocationStore
  @Prop observerPlanet: string = 'Earth'
  @Prop latitude: number = 0
  @Prop longitude: number = 0
  @Prop mapTexture: string = ''
  @Prop mapAllowed: boolean = false
  @Prop localGlobeAllowed: boolean = false
  @Prop expandedLayout: boolean = false
  @Prop skyWidth: number = 0
  @Prop skyHeight: number = 0
  @Prop altitude: number = 0
  @Prop altitudeSource: string = ''
  @Prop locationName: string = ''
  locationPort?: LocationPort
  @StorageLink('stellariumScreenSafeTopPixels') private screenSafeTopPixels: number = 0
  @StorageLink('stellariumScreenSafeBottomPixels') private screenSafeBottomPixels: number = 0
  @State private c: ThemeSlots = DEFAULT_SLOTS
  // Updated from onWillApplyTheme so the map style follows the same palette as
  // the surrounding chrome, including a cold start in night mode.
  private themeNight: boolean = false
  @State private mapStarted: boolean = false
  @State private mapReady: boolean = false
  @State private mapFailed: boolean = false
  @State private mapErrorText: string = ''
  @State private loading: boolean = false
  @State private localGlobe: boolean = false
  private localGlobePending: boolean = false
  @State private draftLat: number = 0
  @State private draftLon: number = 0
  @State private hasDraft: boolean = true
  @State private selectedName: string = ''
  @State private selectedAltitude: number = 0
  @State private selectedAltitudeSource: string = 'none'
  @State private altitudeResolving: boolean = false
  @State private gpsBusy: boolean = false
  @State private gpsMessage: string = ''
  @State private layerMenuOpen: boolean = false
  @State private mapLayerType: string = 'standard'
  @State private searchQuery: string = ''
  @State private petalResults: Array<MapApiSearchResult> = []
  @State private petalState: string = 'idle'
  @State private resultsOpen: boolean = false
  @State private mapLat: number = 0
  @State private mapLon: number = 0
  private globeTexturePath: string = ''
  private initialZoomValue: number = 4
  private selectedPointSource: string = 'map'
  private recenterZoomed: boolean = false
  private altitudeRequestId: number = 0
  private gpsHasFix: boolean = false
  private gpsLat: number = 0
  private gpsLon: number = 0
  private gpsAlt: number = 0
  private searchRequestId: number = 0
  private searchTimer: number = -1
  private lastMapPadding: string = ''
  private controller?: map.MapComponentController
  private marker?: map.Marker
  private gpsHitMarker?: map.Marker
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
      this.fallback(I18n.t('map_unavailable_hint'))
      return
    }
    this.controller = controller
    const events = controller.getEventManager()
    events.on('mapLoad', () => { this.onMapLoad() })
    events.on('error', (error: BusinessError) => { this.onMapError(error) })
    events.on('cameraIdle', () => { this.syncPlanet2DOverlay() })
    events.on('mapClick', (position: mapCommon.LatLng) => { this.handleMapClick(position) })
    events.on('myLocationClick', (position: mapCommon.LatLng) => { this.onGpsDotClick(position) })
    events.on('markerClick', (marker: map.Marker) => { this.onGpsHitMarkerClick(marker) })
  }
  onPick: (latitude: number, longitude: number, altitude: number, name: string, source: string) => void =
    () => {}
  onClose: () => void = () => {}
  planetLabel: (en: string) => string = (en: string) => en
  contextOf: (item: LocSearchItem) => string = () => ''

  onWillApplyTheme(theme: Theme): void {
    const next = slotsFromTheme(theme)
    const nightChanged = next.isNight !== this.c.isNight
    this.c = next
    this.themeNight = next.isNight
    // App day mode follows the system dark mode through DayNightMode.AUTO;
    // the app's red night mode forces NIGHT and adds the red wash.
    if (nightChanged) this.applyMapNightMode()
  }

  private effectiveDayNightMode(): mapCommon.DayNightMode {
    return this.themeNight ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.AUTO
  }

  private applyMapNightMode(): void {
    const mode = this.effectiveDayNightMode()
    this.options.dayNightMode = mode
    const controller = this.controller
    if (!controller) return
    try {
      // Older HMS map services in emulator images may not expose the setter.
      if (typeof controller.setDayNightMode !== 'function') return
      controller.setDayNightMode(mode)
    } catch (_error) {
      // Keep the current style; the red night wash still protects dark vision.
    }
  }

  aboutToAppear(): void {
    this.draftLat = this.latitude
    this.draftLon = this.longitude
    this.mapLat = this.latitude
    this.mapLon = this.longitude
    this.hasDraft = true
    this.selectedName = this.locationName
    // GPS altitude is Earth-only. On other bodies the picker starts at 0 and
    // only an offline place selected from search may supply another value.
    this.selectedAltitude = this.observerPlanet === 'Earth' ? this.altitude : 0
    this.selectedAltitudeSource = this.observerPlanet === 'Earth'
      ? (this.altitudeSource === 'gps' ? 'gps' : (this.altitudeSource === 'named' ? 'city' : 'none'))
      : 'none'
    this.selectedPointSource = this.altitudeSource === 'gps' ? 'gps'
      : (this.altitudeSource === 'named' ? 'named' : 'map')
    this.globeTexturePath = surfaceTexturePath(this.observerPlanet, this.mapTexture)
    this.clearSearchState()
    this.prepareMap()
  }

  // Set up the Map Kit surface. Retry re-enters this method after remounting
  // MapComponent, so network state and options are re-evaluated.
  private prepareMap(): void {
    const online = this.mapAllowed && this.hasOnlineNetwork()
    hilog.info(0x0000, 'StellariumArkUI',
      '[full-map] start allowed=%{public}s localAllowed=%{public}s online=%{public}s planet=%{public}s',
      this.mapAllowed.toString(), this.localGlobeAllowed.toString(),
      online.toString(), this.observerPlanet)
    if (!this.mapAllowed && !this.localGlobeAllowed) {
      this.fallback(I18n.t('map_unavailable_privacy'))
      return
    }
    // Reuse the Map Kit globe/camera/click pipeline for every body. Earth uses
    // Petal when the online map is allowed and a network exists; otherwise the
    // local Earth texture (the Moon path) keeps the picker usable offline. The
    // online search path is independent of the surface.
    this.localGlobe = this.observerPlanet === 'Earth' && !online
    this.options.mapType = (this.observerPlanet === 'Earth' && online)
      ? mapCommon.MapType.STANDARD : mapCommon.MapType.NONE
    this.options.dayNightMode = this.effectiveDayNightMode()
    // Map Kit switches to 2D at zoom >= 4. Minor bodies without a reliable
    // global map stay on the 3D globe; they never enter the 2D renderer.
    this.options.maxZoom = this.maxZoom()
    this.initialZoomValue = supports2DMap(this.observerPlanet) ? 4 : 3
    this.options.position = {
      target: { latitude: this.latitude, longitude: this.longitude },
      zoom: this.initialZoomValue
    }
    this.lastMapPadding = ''
    this.mapFailed = false
    this.mapErrorText = ''
    this.mapStarted = true
    this.loading = true
    this.timeoutId = setTimeout(() => { this.onMapTimeout() }, 15000)
  }

  private onMapTimeout(): void {
    hilog.info(0x0000, 'StellariumArkUI', '[full-map] timeout ready=%{public}s local=%{public}s',
      this.mapReady.toString(), this.localGlobe.toString())
    if (this.mapReady) return
    if (this.observerPlanet === 'Earth' && !this.localGlobe && this.controller) {
      this.enableLocalGlobe()
      return
    }
    this.fallback(I18n.t('map_unavailable_timeout'))
  }

  aboutToDisappear(): void {
    this.clearTimeout()
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer)
      this.searchTimer = -1
    }
    this.searchRequestId += 1
    try {
      this.planetSurfaceOverlay?.remove()
      this.gpsHitMarker?.remove()
    } catch (_error) {
      // The controller may already be torn down with the MapComponent.
    }
    this.planetSurfaceOverlay = undefined
    this.gpsHitMarker = undefined
    this.controller = undefined
    this.marker = undefined
    this.locationStore.searchLocations('')
  }

  private clearTimeout(): void {
    if (this.timeoutId >= 0) {
      clearTimeout(this.timeoutId)
      this.timeoutId = -1
    }
  }

  private fallback(reason: string): void {
    this.clearTimeout()
    this.mapStarted = false
    this.mapReady = false
    this.loading = false
    this.localGlobe = false
    this.localGlobePending = false
    this.mapFailed = true
    this.mapErrorText = reason
    try {
      this.planetSurfaceOverlay?.remove()
      this.gpsHitMarker?.remove()
    } catch (_error) {
      // The controller may already be torn down with the MapComponent.
    }
    this.planetSurfaceOverlay = undefined
    this.gpsHitMarker = undefined
    this.controller = undefined
    this.marker = undefined
    this.lastMapPadding = ''
  }

  // Remount MapComponent: ArkUI does not recreate it when mapStarted flips off
  // and on in the same state update, so defer the restart by one frame.
  private retryMap(): void {
    // Keep the error card visible while MapComponent unmounts; prepareMap
    // clears mapFailed and raises it again only if the retry also fails.
    this.clearTimeout()
    this.mapReady = false
    this.mapStarted = false
    this.localGlobe = false
    this.localGlobePending = false
    this.timeoutId = setTimeout(() => { this.prepareMap() }, 50)
  }

  private async onMapLoad(): Promise<void> {
    hilog.info(0x0000, 'StellariumArkUI', '[full-map] mapLoad local=%{public}s',
      this.localGlobe.toString())
    this.mapReady = true
    this.loading = false
    this.clearTimeout()
    this.applyMapNightMode()
    if (this.observerPlanet !== 'Earth' || this.localGlobe) {
      const error = await this.applySphereTexture()
      hilog.info(0x0000, 'StellariumArkUI',
        '[full-map] mapLoad texture error=%{public}s', error)
      if (error.length > 0) {
        this.fallback(I18n.t(error))
        return
      }
    }
    this.applyMapPadding()
    await this.placeInitialPoint()
  }

  private onMapError(error: BusinessError): void {
    hilog.info(0x0000, 'StellariumArkUI', '[full-map] error code=%{public}s local=%{public}s',
      error.code.toString(), this.localGlobe.toString())
    // The online Petal base map failed (airplane mode, no AGC profile, or an
    // emulator without a Map Kit surface). Keep Map Kit's camera/gesture/click
    // pipeline and paint the local Earth texture on its globe instead.
    if (this.observerPlanet === 'Earth' && !this.localGlobe) {
      this.enableLocalGlobe()
      return
    }
    this.fallback(I18n.t('map_unavailable_hint'))
  }

  // Offline Earth surface: the Moon path. MapType.NONE + coverageImage keeps
  // Map Kit's sphere/camera/mapClick pipeline and needs no network.
  private async enableLocalGlobe(): Promise<void> {
    if (this.localGlobe || this.localGlobePending) return
    const controller = this.controller
    if (!controller || this.observerPlanet !== 'Earth') {
      this.fallback(I18n.t('map_unavailable_hint'))
      return
    }
    this.localGlobePending = true
    this.clearTimeout()
    hilog.info(0x0000, 'StellariumArkUI', '[full-map] local globe start')
    try {
      controller.setMapType(mapCommon.MapType.NONE)
    } catch (_error) {
      hilog.info(0x0000, 'StellariumArkUI', '[full-map] setMapType(NONE) failed')
      this.localGlobePending = false
      this.fallback(I18n.t('map_unavailable_hint'))
      return
    }
    const error = await this.applySphereTexture()
    this.localGlobePending = false
    hilog.info(0x0000, 'StellariumArkUI', '[full-map] local globe error=%{public}s', error)
    if (error.length > 0) {
      this.fallback(I18n.t(error))
      return
    }
    this.localGlobe = true
    this.mapReady = true
    this.loading = false
    this.applyMapPadding()
    await this.placeInitialPoint()
  }

  // Returns an I18n key describing why the globe texture could not be applied,
  // or an empty string on success. This is the only surface for offline Earth
  // and non-Earth bodies; there is no flat-image fallback.
  private async applySphereTexture(): Promise<string> {
    const controller = this.controller
    if (!controller) return 'map_unavailable_hint'
    // setSphereMapEnabled arrived with Map Kit 26.0.0. Some emulator images
    // ship an older com.huawei.hms.mapservice even when the OS API level is 26,
    // so gate on the runtime method instead of the compile SDK.
    if (typeof controller.setSphereMapEnabled !== 'function') {
      hilog.info(0x0000, 'StellariumArkUI',
        '[full-map] setSphereMapEnabled unavailable in the installed Map service')
      return 'map_unavailable_sdk'
    }
    if (this.globeTexturePath.length === 0) return 'map_unavailable_texture'
    try {
      const context = this.getUIContext().getHostContext()
      if (!context) return 'map_unavailable_hint'
      const bytes = await context.resourceManager.getRawFileContent(this.globeTexturePath)
      const source = image.createImageSource(bytes.buffer as ArrayBuffer)
      const pixelMap = await source.createPixelMap()
      try {
        await controller.setSphereMapEnabled(true, {
          sunLightEnabled: false,
          cityLightEnabled: false,
          animateDuration: 0,
          coverageImage: pixelMap
        })
        return ''
      } finally {
        pixelMap.release()
        source.release()
      }
    } catch (error) {
      hilog.info(0x0000, 'StellariumArkUI',
        '[full-map] sphere texture failed: %{public}s', (error as Error).message ?? String(error))
      return 'map_unavailable_texture'
    }
  }

  // Map Kit switches from the 3D globe to the 2D Mercator map around zoom 4.
  // coverageImage only paints the globe; without a 2D overlay the empty
  // MapType.NONE map shows its green background. Add the same planet texture as
  // a 2D ImageOverlay at/after the transition and remove it when back on globe.
  private async syncPlanet2DOverlay(): Promise<void> {
    const controller = this.controller
    if (!controller || !this.mapReady) return
    // Online Earth uses Petal's own 2D base map; only the offline local globe
    // needs the generated Mercator overlay.
    if (this.observerPlanet === 'Earth' && !this.localGlobe) return
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
    // The local Earth globe is a WGS84 texture, so its clicks need no inverse
    // GCJ02 correction. Only the online Petal base map does.
    if (this.observerPlanet !== 'Earth' || this.localGlobe) return position
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

  // WGS84 -> the coordinate system the map data uses. In mainland China this
  // adds the GCJ02 offset; overseas it returns the original point. Marker and
  // camera positions must use this form, never the raw WGS84 draft.
  private async toMapCoordinate(latitude: number, longitude: number): Promise<mapCommon.LatLng> {
    const point: mapCommon.LatLng = { latitude: latitude, longitude: longitude }
    if (this.observerPlanet !== 'Earth' || this.localGlobe) return point
    try {
      const context = this.getUIContext().getHostContext()
      if (!context) return point
      const points = await map.rectifyCoordinate(context, [{
        coordinateType: mapCommon.CoordinateType.WGS84,
        location: point
      }])
      if (points && points.length > 0) return points[0].location
    } catch (_error) {
      // Fall back to the raw point if the SDK cannot rectify it.
    }
    return point
  }

  private async handleMapClick(position: mapCommon.LatLng): Promise<void> {
    if (!this.mapReady) return
    const point = await this.toWgs84(position)
    this.selectedPointSource = 'map'
    // Let the reverse geocoder name the picked point (street/community/town)
    // instead of leaving the generic "自定义位置" label.
    await this.setDraft(point.latitude, point.longitude, position, undefined,
      undefined, undefined, undefined, true)
  }

  private async setDraft(latitude: number, longitude: number,
    mapPoint?: mapCommon.LatLng, name?: string, altitude?: number,
    altitudeSource?: string, preferredCity?: string, resolveName: boolean = false): Promise<void> {
    this.recenterZoomed = false
    this.gpsMessage = ''
    this.draftLat = latitude
    this.draftLon = longitude
    this.hasDraft = true
    if (name !== undefined && name.length > 0) {
      this.selectedName = name
    } else if (resolveName) {
      // Shown only until the reverse geocoder returns a local place name.
      this.selectedName = I18n.t('custom_location')
    }
    if (altitude !== undefined) {
      this.altitudeRequestId += 1
      this.altitudeResolving = false
      this.selectedAltitude = Math.round(altitude)
      this.selectedAltitudeSource = altitudeSource ??
        (this.observerPlanet === 'Earth' ? 'city' : 'offline')
    } else if (this.observerPlanet === 'Earth') {
      const requestId = ++this.altitudeRequestId
      this.altitudeResolving = true
      this.resolveAltitude(latitude, longitude, requestId, preferredCity, resolveName)
    } else {
      // Other bodies always use 0 unless an offline place supplied a value.
      this.altitudeRequestId += 1
      this.altitudeResolving = false
      this.selectedAltitude = 0
      this.selectedAltitudeSource = 'none'
    }
    const point = mapPoint ?? await this.toMapCoordinate(latitude, longitude)
    this.mapLat = point.latitude
    this.mapLon = point.longitude
    const controller = this.controller
    if (!controller) return
    const icon = this.markerIcon()
    try {
      if (this.marker) {
        this.marker.setPosition(point)
        await this.marker.setIcon(icon)
      } else {
        this.marker = await controller.addMarker({ position: point, icon: icon })
      }
    } catch (_error) {
      // Keep the draft even if the marker layer is unavailable.
    }
  }

  // Earth map picks have no vertical component from Map Kit. Use the online
  // reverse-geocoded city name and the offline city altitude; fall back to the
  // nearest offline place. The map marker is updated immediately; altitude
  // arrives asynchronously and respects the latest pick via altitudeRequestId.
  private async resolveAltitude(latitude: number, longitude: number,
    requestId: number, preferredCity?: string, resolveName: boolean = false): Promise<void> {
    if (this.observerPlanet !== 'Earth') return
    let result: OfflinePlaceAltitude = { found: false, altitude: 0, name: '' }
    const cityName = preferredCity ?? ''
    if (cityName.length > 0) {
      result = this.locationStore.altitudeForCityName(cityName, 'Earth', latitude, longitude)
    }
    let resolvedName = ''
    // Reverse geocoding is a metered Map Kit API. When the build disables the
    // metered APIs, skip it and fall through to the nearest offline place.
    if (!result.found && !this.localGlobe && this.onlineSearchAllowed()) {
      try {
        const mapPoint = await this.toMapCoordinate(latitude, longitude)
        if (requestId !== this.altitudeRequestId) return
        if (this.onlineSearchAllowed()) {
          const reverse = await site.reverseGeocode({
            location: mapPoint,
            radius: 1000,
            language: I18n.isChineseLanguage() ? 'zh' : 'en'
          })
          if (this.onlineSearchAllowed()) {
            const component = reverse.addressComponent
            const name = component.locality ?? component.adminLevel2 ??
              component.adminLevel3 ?? component.adminLevel1 ?? ''
            if (name.length > 0) {
              result = this.locationStore.altitudeForCityName(name, 'Earth', latitude, longitude)
            }
            resolvedName = smallestAdminDivision(component)
          }
        }
      } catch (_error) {
        // Site Kit unavailable; fall through to the offline nearest place.
      }
    }
    if (!result.found) {
      result = this.locationStore.altitudeForPoint(latitude, longitude, 'Earth')
    }
    if (requestId !== this.altitudeRequestId) return
    this.altitudeResolving = false
    if (resolveName) {
      const fallback = result.found && result.name.length > 0 ? result.name : ''
      const nextName = resolvedName.length > 0 ? resolvedName : fallback
      if (nextName.length > 0) this.selectedName = nextName
    }
    if (result.found) {
      this.selectedAltitude = Math.round(result.altitude)
      this.selectedAltitudeSource = 'city'
    } else {
      this.selectedAltitude = 0
      this.selectedAltitudeSource = 'unknown'
    }
  }

  // GPS is Earth-only. The button requests precise location, centers the map on
  // the fix and enables Map Kit's my-location layer, whose blue dot rotates
  // with the device heading (TRACK_ROTATE). Tapping the dot selects the point.
  private async useGps(): Promise<void> {
    if (this.observerPlanet !== 'Earth' || this.gpsBusy) return
    const port = this.locationPort
    if (!port) {
      this.gpsMessage = I18n.t('m_gps_unavailable')
      return
    }
    this.gpsBusy = true
    this.gpsMessage = ''
    try {
      const permission = await port.requestLocationPermissions()
      if (permission !== 'precise') {
        this.gpsMessage = permission === 'approximate'
          ? I18n.t('m_gps_precise_required') : I18n.t('loc_gps_denied_settings')
        return
      }
      const fix = await port.getCurrentLocation()
      if (!Number.isFinite(fix.latitude) || !Number.isFinite(fix.longitude)) {
        this.gpsMessage = I18n.t('m_gps_unavailable')
        return
      }
      this.gpsHasFix = true
      this.gpsLat = fix.latitude
      this.gpsLon = fix.longitude
      this.gpsAlt = Number.isFinite(fix.altitude) ? fix.altitude : 0
      if (fix.accuracy !== undefined && fix.accuracy > 0) {
        this.gpsMessage = I18n.t('loc_gps_accuracy').replace('%s', Math.round(fix.accuracy).toString())
      }
      if (fix.altitudeAccuracy !== undefined && fix.altitudeAccuracy > 0) {
        this.gpsMessage += (this.gpsMessage.length > 0 ? ' · ' : '') +
          I18n.t('loc_gps_altitude_accuracy').replace('%s', Math.round(fix.altitudeAccuracy).toString())
      }
      await this.enableMyLocationLayer()
      const point = await this.toMapCoordinate(fix.latitude, fix.longitude)
      this.focusMap(point)
      await this.ensureGpsHitMarker()
      this.recenterZoomed = false
    } catch (_error) {
      this.gpsMessage = I18n.t('m_gps_unavailable')
    } finally {
      this.gpsBusy = false
    }
  }

  private async enableMyLocationLayer(): Promise<void> {
    const controller = this.controller
    if (!controller) return
    try {
      // TRACK_ROTATE: continuous location; the blue dot follows and rotates
      // with the device direction but does not move the camera by itself.
      await controller.setMyLocationStyle({
        displayType: mapCommon.MyLocationDisplayType.TRACK_ROTATE
      })
      controller.setMyLocationEnabled(true)
      // The app has its own GPS button; hide Map Kit's redundant lower-right
      // my-location control while keeping the blue heading dot layer.
      try {
        controller.setMyLocationControlsEnabled(false)
      } catch (_controlError) {
        // The control icon is optional.
      }
    } catch (_error) {
      try {
        controller.setMyLocationEnabled(true)
        controller.setMyLocationControlsEnabled(false)
      } catch (_fallbackError) {
        // Older Map services may not expose the my-location layer.
      }
    }
  }

  // The default my-location dot is small and its tap target is tight. Add a
  // nearly transparent 96px marker over it so tapping the blue dot is reliable;
  // the marker has no visible effect on the dot's original size.
  private async ensureGpsHitMarker(): Promise<void> {
    const controller = this.controller
    if (!controller || !this.gpsHasFix) return
    const position = await this.toMapCoordinate(this.gpsLat, this.gpsLon)
    if (this.gpsHitMarker) {
      try {
        this.gpsHitMarker.setPosition(position)
      } catch (_error) {
        // Keep the existing hit marker if the map rejects the update.
      }
      return
    }
    try {
      this.gpsHitMarker = await controller.addMarker({
        position: position,
        icon: $r('app.media.ic_gps_hit'),
        anchorU: 0.5,
        anchorV: 0.5,
        clickable: true,
        zIndex: 1
      })
    } catch (_error) {
      // The myLocationClick event remains as the fallback.
    }
  }

  private onGpsHitMarkerClick(marker: map.Marker): void {
    if (!this.gpsHitMarker) return
    let clickedId = ''
    let hitId = ''
    try {
      clickedId = marker.getId()
      hitId = this.gpsHitMarker.getId()
    } catch (_error) {
      return
    }
    if (clickedId.length === 0 || clickedId !== hitId) return
    this.onGpsDotClick({ latitude: this.gpsLat, longitude: this.gpsLon })
  }

  private async onGpsDotClick(position: mapCommon.LatLng): Promise<void> {
    if (this.observerPlanet !== 'Earth') return
    let latitude = position.latitude
    let longitude = position.longitude
    let altitude: number | undefined = undefined
    if (this.gpsHasFix) {
      latitude = this.gpsLat
      longitude = this.gpsLon
      // The GPS dot always reports the GNSS altitude and marks it as GPS,
      // even when it is 0 or when the fix has no vertical accuracy.
      altitude = this.gpsAlt
    } else {
      const wgs = await this.toWgs84(position)
      latitude = wgs.latitude
      longitude = wgs.longitude
    }
    const point = await this.toMapCoordinate(latitude, longitude)
    this.selectedPointSource = 'gps'
    await this.setDraft(latitude, longitude, point, I18n.t('m_current_location'), altitude,
      altitude !== undefined ? 'gps' : undefined)
  }

  // The current observer location is the initial draft. Place it once the map
  // controller reports mapLoad so the user always sees where they are.
  private async placeInitialPoint(): Promise<void> {
    const controller = this.controller
    if (!controller) return
    const point = await this.toMapCoordinate(this.draftLat, this.draftLon)
    this.mapLat = point.latitude
    this.mapLon = point.longitude
    const icon = this.markerIcon()
    try {
      if (this.marker) {
        this.marker.setPosition(point)
        await this.marker.setIcon(icon)
      } else {
        this.marker = await controller.addMarker({ position: point, icon: icon })
      }
      controller.moveCamera(map.newCameraPosition({
        target: point,
        zoom: this.initialZoomValue
      }))
      if (this.initialZoomValue >= 4 && (this.observerPlanet !== 'Earth' || this.localGlobe)) {
        this.syncPlanet2DOverlay()
      }
    } catch (_error) {
      // Keep the draft even if the marker or camera update fails.
    }
  }

  private recenter(): void {
    const controller = this.controller
    if (!controller) return
    // Earth: first tap recenters at the picker zoom, second tap zooms to a
    // navigation/location scale (15). Tapping again returns to the overview.
    // Other bodies keep a single global-view recenter.
    const earth = this.observerPlanet === 'Earth'
    const zoom = earth && this.recenterZoomed ? 15 : this.initialZoomValue
    if (earth) this.recenterZoomed = !this.recenterZoomed
    const point: mapCommon.LatLng = { latitude: this.mapLat, longitude: this.mapLon }
    try {
      controller.moveCamera(map.newCameraPosition({
        target: point,
        zoom: Math.min(zoom, this.maxZoom())
      }))
    } catch (_error) {
      // Keep the current camera if the SDK rejects the update.
    }
  }

  private maxZoom(): number {
    return supports2DMap(this.observerPlanet) ? 20 : 3
  }

  private mapLayerAvailable(): boolean {
    return this.observerPlanet === 'Earth' && !this.localGlobe && this.mapReady
  }

  private setMapLayerType(type: string): void {
    if (type !== 'terrain' && type !== 'satellite') return
    hilog.info(0x0000, 'StellariumArkUI', '[full-map] layer type=%{public}s', type)
    this.layerMenuOpen = false
    this.mapLayerType = type
    const controller = this.controller
    if (!controller) return
    try {
      controller.setMapType(type === 'satellite'
        ? mapCommon.MapType.SATELLITE : mapCommon.MapType.TERRAIN)
      // A map-type switch can reset the style; re-apply the day/night mode.
      this.applyMapNightMode()
      // The topographic layer is only rendered at zoom 5..14.
      if (type === 'terrain') {
        const camera = controller.getCameraPosition()
        if (camera.zoom <= 5) {
          controller.moveCamera(map.newCameraPosition({ target: camera.target, zoom: 6 }))
        }
      }
    } catch (_error) {
      // Keep the current base map if the service rejects the type.
    }
  }

  private focusMap(point: mapCommon.LatLng): void {
    const controller = this.controller
    if (!controller) return
    const target = this.observerPlanet === 'Earth'
      ? 6 : (supports2DMap(this.observerPlanet) ? 5 : 3)
    try {
      controller.moveCamera(map.newCameraPosition({
        target: point,
        zoom: Math.min(target, this.maxZoom())
      }))
    } catch (_error) {
      // Keep the current camera if the SDK rejects the update.
    }
  }

  private scheduleSearch(): void {
    if (this.searchTimer >= 0) clearTimeout(this.searchTimer)
    const query = this.searchQuery.trim()
    this.resultsOpen = query.length > 0
    if (query.length === 0) {
      this.searchRequestId += 1
      this.clearResultLists()
      return
    }
    this.searchTimer = setTimeout(() => { this.runSearch(query) }, 300)
  }

  private async runSearch(query: string): Promise<void> {
    const requestId = ++this.searchRequestId
    this.searchOffline(query)
    // Petal text search is a metered Map Kit API; the build flag keeps the
    // offline results visible without issuing the server call.
    if (this.onlineSearchAllowed()) {
      await this.searchPetal(query, requestId)
    }
  }

  private onlineSearchAllowed(): boolean {
    return METERED_MAP_APIS_ENABLED && this.mapAllowed &&
      this.observerPlanet === 'Earth' && this.hasOnlineNetwork()
  }

  private searchOffline(query: string): void {
    // Pass the observer planet explicitly: the picker's prop is the source of
    // truth and does not depend on when the host's observer hook settles.
    this.locationStore.searchLocations(query, this.observerPlanet)
  }

  private async searchPetal(query: string, requestId: number): Promise<void> {
    if (!this.onlineSearchAllowed() || requestId !== this.searchRequestId) return
    this.petalState = 'loading'
    this.petalResults = []
    try {
      const result = await site.searchByText({
        query: query,
        language: I18n.isChineseLanguage() ? 'zh' : 'en'
      })
      if (!this.onlineSearchAllowed() || requestId !== this.searchRequestId) return
      const sites = result.sites === undefined ? [] : result.sites
      const mapped: Array<MapApiSearchResult> = []
      for (const item of sites) {
        if (!item.location) continue
        const point = await this.toWgs84(item.location)
        const component = item.addressComponent
        mapped.push({
          name: item.name ?? item.formatAddress ?? query,
          address: item.formatAddress ?? '',
          cityName: component.locality ?? component.adminLevel2 ??
            component.adminLevel3 ?? component.adminLevel1 ?? '',
          latitude: point.latitude,
          longitude: point.longitude,
          mapLatitude: item.location.latitude,
          mapLongitude: item.location.longitude,
          source: 'petal'
        })
        if (mapped.length >= 20) break
      }
      if (!this.onlineSearchAllowed() || requestId !== this.searchRequestId) return
      this.petalResults = mapped
      this.petalState = mapped.length > 0 ? 'ok' : 'empty'
    } catch (_error) {
      if (!this.onlineSearchAllowed() || requestId !== this.searchRequestId) return
      this.petalState = 'error'
    }
  }

  private clearResultLists(): void {
    this.petalResults = []
    this.petalState = 'idle'
    this.locationStore.searchLocations('')
  }

  private clearSearchState(): void {
    this.searchQuery = ''
    this.resultsOpen = false
    this.clearResultLists()
  }

  private clearSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer)
      this.searchTimer = -1
    }
    this.searchRequestId += 1
    this.searchQuery = ''
    this.resultsOpen = false
    this.clearResultLists()
  }

  private searchBusy(): boolean {
    return this.petalState === 'loading' || this.locationStore.locSearching
  }

  private async chooseApiResult(item: MapApiSearchResult): Promise<void> {
    const point: mapCommon.LatLng = {
      latitude: item.mapLatitude,
      longitude: item.mapLongitude
    }
    this.selectedPointSource = 'map'
    await this.setDraft(item.latitude, item.longitude, point, item.name, undefined, undefined, item.cityName)
    this.focusMap(point)
    this.resultsOpen = false
    this.clearResultLists()
    this.hideKeyboard()
  }

  private async chooseLocalResult(item: LocSearchItem): Promise<void> {
    const point = await this.toMapCoordinate(item.lat, item.lon)
    this.selectedPointSource = 'named'
    await this.setDraft(item.lat, item.lon, point, item.displayName ?? item.name, item.alt,
      this.observerPlanet === 'Earth' ? 'city' : 'offline')
    this.focusMap(point)
    this.resultsOpen = false
    this.clearResultLists()
    this.hideKeyboard()
  }

  private selectDraft(): void {
    const name = this.selectedName.length > 0 ? this.selectedName : this.locationName
    this.onPick(this.draftLat, this.draftLon, this.selectedAltitude, name, this.selectedPointSource)
    this.onClose()
  }

  private hideKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (_error) {
      // The IME may already be closed.
    }
  }

  private hasOnlineNetwork(): boolean {
    try {
      return connection.hasDefaultNetSync()
    } catch (_error) {
      // Without the network-info permission we assume online and let the map
      // error/timeout fall back to the local globe.
      return true
    }
  }

  private safeTop(): number {
    const inset = this.getUIContext().px2vp(Math.max(0, this.screenSafeTopPixels))
    // The app is immersive and the emulator reports a 0 top inset; keep a
    // status-bar-height margin so the title never sits under the status bar.
    return Math.max(inset, 24) + 8
  }

  private safeBottom(): number {
    const inset = this.getUIContext().px2vp(Math.max(0, this.screenSafeBottomPixels))
    // Reserve the bottom gesture / Xiaoyi bar even when the system bar is
    // hidden and the reported inset is 0.
    return Math.max(inset, 24) + 8
  }

  private sidePanelWidth(): number {
    const width = this.skyWidth > 0 ? this.skyWidth : 900
    return Math.max(300, Math.min(360, width * 0.34))
  }

  private applyMapPadding(): void {
    const controller = this.controller
    if (!controller) return
    const left = Math.round(this.getUIContext().vp2px(this.expandedLayout ? this.sidePanelWidth() : 0))
    const top = Math.round(this.getUIContext().vp2px(
      this.safeTop() + (this.expandedLayout ? 16 : 120)))
    const right = Math.round(this.getUIContext().vp2px(16))
    const bottom = Math.round(this.getUIContext().vp2px(
      this.safeBottom() + (this.expandedLayout ? 16 : 160)))
    const key = left + ',' + top + ',' + right + ',' + bottom
    if (key === this.lastMapPadding) return
    this.lastMapPadding = key
    try {
      controller.setPadding({ left: left, top: top, right: right, bottom: bottom })
    } catch (_error) {
      // Padding is best-effort; the map still works without it.
    }
  }

  private surfaceLabel(): string {
    if (this.mapFailed) return I18n.t('map_surface_unavailable')
    if (this.localGlobe) return I18n.t('map_surface_globe')
    if (this.mapReady) {
      return this.observerPlanet === 'Earth'
        ? I18n.t('map_surface_online')
        : I18n.t('map_surface_planet')
    }
    return I18n.t('map_loading_short')
  }

  private searchPlaceholder(): string {
    if (this.observerPlanet === 'Earth') return I18n.t('map_search_placeholder')
    return I18n.t('map_search_planet_placeholder').replace('{planet}', this.planetLabel(this.observerPlanet))
  }

  // GPS-selected points use a blue pin; map/search picks keep the red pin.
  private markerIcon(): Resource {
    return this.selectedPointSource === 'gps'
      ? $r('app.media.ic_map_pin_blue')
      : $r('app.media.ic_map_pin_red')
  }

  private formatCoordinates(latitude: number, longitude: number): string {
    const ns = latitude >= 0 ? 'N' : 'S'
    const ew = longitude >= 0 ? 'E' : 'W'
    return Math.abs(latitude).toFixed(4) + '°' + ns + ' / ' +
      Math.abs(longitude).toFixed(4) + '°' + ew
  }

  // Coordinates, altitude and the altitude source share one line in the bottom
  // action card, e.g. "29.1439°N / 89.2803°E · 86 m · GPS". On the online
  // Petal map the label shows the map (GCJ02) coordinate, matching the marker
  // and the GPS dot; the draft itself stays WGS84 for the pick result.
  private pointDetailLine(): string {
    const onOnlineMap = this.observerPlanet === 'Earth' && !this.localGlobe
    let line = onOnlineMap
      ? this.formatCoordinates(this.mapLat, this.mapLon)
      : this.formatCoordinates(this.draftLat, this.draftLon)
    const altitude = this.altitudeText()
    if (altitude.length > 0) line += ' · ' + altitude
    return line
  }

  private altitudeText(): string {
    if (this.observerPlanet !== 'Earth') {
      // Non-Earth: always 0 unless an offline place supplied another value.
      let text = this.selectedAltitude.toFixed(0) + ' m'
      if (this.selectedAltitudeSource === 'offline') {
        text += ' · ' + I18n.t('map_altitude_offline')
      }
      return text
    }
    if (this.altitudeResolving) return I18n.t('map_altitude_resolving')
    if (this.selectedAltitudeSource === 'unknown') return I18n.t('map_altitude_unknown')
    let text = this.selectedAltitude.toFixed(0) + ' m'
    if (this.selectedAltitudeSource === 'gps') {
      text += ' · ' + I18n.t('map_altitude_gps')
    } else if (this.selectedAltitudeSource === 'city') {
      text += ' · ' + I18n.t('map_altitude_city')
    }
    return text
  }

  @Builder
  mapLayer() {
    if (this.mapStarted) {
      MapComponent({ mapOptions: this.options, mapCallback: this.callback })
        .width('100%').height('100%')
    }
  }

  @Builder
  topBar() {
    // Back button and title are separate elements. The title uses the same
    // long pill shape and glass backing as the search bar, so it stays legible
    // over bright map tiles without a second stacked plate.
    Row({ space: 8 }) {
      Row() {
        Image($r('app.media.ic_back')).width(18).height(18)
          .supportSvg2(true).colorFilter(tintMatrixFor(this.c.text))
      }
        .width(44).height(44).justifyContent(FlexAlign.Center)
        .backgroundColor(this.c.panelGlassStrong)
        .border({ width: 1, color: this.c.border })
        .borderRadius(22)
        .onClick(() => { this.onClose() })
        .accessibilityText(I18n.t('map_close'))
      Column({ space: 1 }) {
        Text(this.planetLabel(this.observerPlanet)).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.c.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.surfaceLabel()).fontSize(10).fontColor(this.c.sub)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
        .layoutWeight(1).height(44).justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 14, right: 14 })
        .backgroundColor(this.c.panelGlassStrong)
        .border({ width: 1, color: this.c.border })
        .borderRadius(UI_RADIUS_PILL)
    }
      .width('100%')
  }

  @Builder
  searchCard() {
    Row({ space: 8 }) {
      Image($r('app.media.ic_search')).width(16).height(16)
        .supportSvg2(true).colorFilter(tintMatrixFor(this.c.sub))
      TextInput({ text: this.searchQuery, placeholder: this.searchPlaceholder() })
        .layoutWeight(1).height(40).fontSize(13)
        .backgroundColor(Color.Transparent).fontColor(this.c.text).placeholderColor(this.c.sub)
        .onChange((value: string) => {
          this.searchQuery = value
          this.scheduleSearch()
        })
        .onSubmit(() => {
          if (this.searchTimer >= 0) clearTimeout(this.searchTimer)
          const query = this.searchQuery.trim()
          this.resultsOpen = query.length > 0
          if (query.length > 0) this.runSearch(query)
        })
      if (this.searchQuery.length > 0) {
        Row() {
          Image($r('app.media.ic_close')).width(14).height(14)
            .supportSvg2(true).colorFilter(tintMatrixFor(this.c.sub))
        }
          .width(28).height(28).justifyContent(FlexAlign.Center)
          .onClick(() => { this.clearSearch() })
          .accessibilityText(I18n.t('map_search_clear'))
      }
      if (this.searchBusy()) {
        LoadingProgress().width(16).height(16).color(this.c.accent)
      }
    }
      .width('100%').height(44).padding({ left: 12, right: 6 })
      .backgroundColor(this.c.panelGlassStrong)
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PILL)
  }

  @Builder
  resultsPanel() {
    if (this.resultsOpen && this.searchQuery.trim().length > 0) {
      Scroll() {
        Column({ space: 4 }) {
          if (this.observerPlanet === 'Earth' && this.petalState === 'loading') {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color(this.c.accent)
              Text(I18n.t('map_search_loading')).fontSize(11).fontColor(this.c.sub)
            }
              .width('100%').padding(8)
          }
          if (this.observerPlanet === 'Earth' && this.petalResults.length > 0) {
            Text(I18n.t('map_search_online_section')).fontSize(10).fontColor(this.c.tertiary)
              .width('100%').padding({ left: 4, top: 4, bottom: 2 })
            ForEach(this.petalResults, (item: MapApiSearchResult) => {
              Row({ space: 8 }) {
                Column() {
                  Text(item.name).fontSize(12).fontColor(this.c.text).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  if (item.address.length > 0) {
                    Text(item.address).fontSize(10).fontColor(this.c.sub).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }
                }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(I18n.t('map_search_online_badge')).fontSize(8).fontColor(this.c.onAccent)
                  .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                  .backgroundColor(this.c.accent).borderRadius(3)
              }
                .width('100%').padding(8).backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.chooseApiResult(item) })
            }, (item: MapApiSearchResult) =>
              item.mapLatitude.toString() + ',' + item.mapLongitude.toString() + item.name)
          }
          if (this.observerPlanet === 'Earth' && this.petalState === 'error') {
            Text(I18n.t('map_search_local_hint')).fontSize(9).fontColor(this.c.sub)
              .width('100%').padding({ left: 4, top: 2 })
          }
          if (this.locationStore.locSearchResults.length > 0) {
            Text(this.observerPlanet === 'Earth'
              ? I18n.t('map_search_offline_section')
              : I18n.t('map_search_offline_section') + ' · ' + this.planetLabel(this.observerPlanet))
              .fontSize(10).fontColor(this.c.tertiary)
              .width('100%').padding({ left: 4, top: 4, bottom: 2 })
            ForEach(this.locationStore.locSearchResults, (item: LocSearchItem) => {
              Row({ space: 8 }) {
                Column() {
                  Text(item.displayName ?? item.name).fontSize(12).fontColor(this.c.text)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Text(this.contextOf(item)).fontSize(10).fontColor(this.c.sub)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(I18n.t('map_search_offline_badge')).fontSize(8).fontColor(this.c.text)
                  .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                  .backgroundColor(this.c.softStrong).borderRadius(3)
              }
                .width('100%').padding(8).backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.chooseLocalResult(item) })
            }, (item: LocSearchItem) => item.name + item.lat.toString() + item.planet)
          }
          if (!this.searchBusy() && this.petalResults.length === 0 &&
            this.locationStore.locSearchResults.length === 0) {
            Text(I18n.t('map_search_no_results')).fontSize(11).fontColor(this.c.sub)
              .width('100%').padding(10)
          }
        }
          .width('100%').padding(6)
      }
        .width('100%')
        .layoutWeight(this.expandedLayout ? 1 : 0)
        .constraintSize({ maxHeight: this.expandedLayout ? 2000 : 236 })
        .backgroundColor(this.c.panelGlassStrong)
        .borderRadius(UI_RADIUS_CONTROL)
    } else if (this.expandedLayout) {
      Column() {
        Text(I18n.t('map_search_hint')).fontSize(11).fontColor(this.c.sub).width('100%')
      }
        .width('100%').layoutWeight(1).padding({ top: 10 })
    }
  }

  @Builder
  actionCard() {
    Column({ space: 8 }) {
      Column({ space: 2 }) {
        Text(this.selectedName.length > 0 ? this.selectedName : I18n.t('map_selected_point'))
          .fontSize(13).fontColor(this.c.text).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.pointDetailLine())
          .fontSize(10.5).fontColor(this.c.sub).width('100%').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
        .width('100%').alignItems(HorizontalAlign.Start)
      Row({ space: 8 }) {
        Button(I18n.t('map_use_point')).fontSize(12).layoutWeight(1)
          .borderRadius(UI_RADIUS_CONTROL)
          .enabled(this.hasDraft)
          .onClick(() => { this.selectDraft() })
        Button(I18n.t('map_close')).fontSize(12).layoutWeight(1)
          .backgroundColor(this.c.soft).fontColor(this.c.text)
          .borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onClose() })
      }
        .width('100%')
    }
      .width('100%').padding(12)
      .backgroundColor(this.c.panelGlassStrong)
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PANEL)
  }

  @Builder
  layerOption(type: string, label: string) {
    Row({ space: 6 }) {
      if (this.mapLayerType === type) {
        Image($r('app.media.ic_check')).width(12).height(12)
          .supportSvg2(true).colorFilter(tintMatrixFor(this.c.accent))
      }
      Text(label).fontSize(11).fontColor(this.c.text)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
    }
      .width('100%').height(30).padding({ left: 8, right: 8 })
      .borderRadius(UI_RADIUS_CONTROL)
      .backgroundColor(this.mapLayerType === type ? this.c.softStrong : Color.Transparent)
      .onClick(() => { this.setMapLayerType(type) })
  }

  // Bottom-right side bar: recenter, GPS (Earth only) and map type (online
  // Petal only). The layer picker expands above the three small buttons.
  @Builder
  mapSideTools() {
    Row() {
      Blank()
      Column({ space: 8 }) {
        if (this.layerMenuOpen && this.mapLayerAvailable()) {
          Column({ space: 2 }) {
            Text(I18n.t('map_layer_title')).fontSize(10).fontColor(this.c.sub)
              .width('100%').padding({ left: 8, top: 2, bottom: 2 })
            this.layerOption('terrain', I18n.t('map_layer_terrain'))
            this.layerOption('satellite', I18n.t('map_layer_satellite'))
          }
            .width(136).padding(6)
            .backgroundColor(this.c.panelGlassStrong)
            .border({ width: 1, color: this.c.border })
            .borderRadius(UI_RADIUS_CONTROL)
        }
        Row() {
          Image($r('app.media.ic_recenter')).width(18).height(18)
            .supportSvg2(true).colorFilter(tintMatrixFor(this.c.text))
        }
          .width(40).height(40).justifyContent(FlexAlign.Center)
          .backgroundColor(this.c.panelGlassStrong)
          .border({ width: 1, color: this.c.border })
          .borderRadius(20)
          .onClick(() => {
            this.layerMenuOpen = false
            this.recenter()
          })
          .accessibilityText(I18n.t('map_view_selected'))
        if (this.observerPlanet === 'Earth') {
          Row() {
            if (this.gpsBusy) {
              LoadingProgress().width(18).height(18).color(this.c.sub)
            } else {
              Image($r('app.media.ic_location')).width(18).height(18)
                .supportSvg2(true).colorFilter(tintMatrixFor(this.c.text))
            }
          }
            .width(40).height(40).justifyContent(FlexAlign.Center)
            .backgroundColor(this.c.panelGlassStrong)
            .border({ width: 1, color: this.c.border })
            .borderRadius(20)
            .opacity(this.gpsBusy ? 0.6 : 1)
            .onClick(() => {
              if (!this.gpsBusy) {
                this.layerMenuOpen = false
                this.useGps()
              }
            })
            .accessibilityText(I18n.t('map_gps_locate'))
        }
        if (this.mapLayerAvailable()) {
          Row() {
            Image($r('app.media.ic_layers')).width(18).height(18)
              .supportSvg2(true)
              .colorFilter(tintMatrixFor(this.mapLayerType === 'standard' ? this.c.text : this.c.accent))
          }
            .width(40).height(40).justifyContent(FlexAlign.Center)
            .backgroundColor(this.c.panelGlassStrong)
            .border({ width: 1, color: this.c.border })
            .borderRadius(20)
            .onClick(() => { this.layerMenuOpen = !this.layerMenuOpen })
            .accessibilityText(I18n.t('map_layer_title'))
        }
        if (this.gpsMessage.length > 0) {
          Text(this.gpsMessage).fontSize(9).fontColor(this.c.sub)
            .width(160).maxLines(2).textAlign(TextAlign.End)
        }
      }
        .alignItems(HorizontalAlign.End)
    }
      .width('100%').margin({ bottom: 16 })
  }

  @Builder
  loadingLayer() {
    Stack() {
      Row({ space: 8 }) {
        LoadingProgress().width(18).height(18).color(this.c.sub)
        Text(I18n.t('map_loading')).fontSize(11).fontColor(this.c.sub)
      }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.c.panelGlassStrong)
        .borderRadius(UI_RADIUS_PILL)
    }
      .width('100%').height('100%')
      .alignContent(Alignment.Center)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  mapUnavailableLayer() {
    Column() {
      this.topBar()
      Blank()
      Column({ space: 10 }) {
        Text(I18n.t('map_unavailable_title')).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.c.text).textAlign(TextAlign.Center).width('100%')
        Text(this.mapErrorText).fontSize(11).fontColor(this.c.sub)
          .textAlign(TextAlign.Center).width('100%')
        Text(I18n.t('map_unavailable_hint')).fontSize(10).fontColor(this.c.tertiary)
          .textAlign(TextAlign.Center).width('100%')
        Button(I18n.t('map_retry')).fontSize(12).margin({ top: 4 })
          .onClick(() => { this.retryMap() })
      }
        .width('100%').padding(16)
        .backgroundColor(this.c.panelGlassStrong)
        .border({ width: 1, color: this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
      Blank()
    }
      .width('100%').height('100%')
      .padding({ left: 16, right: 16, top: this.safeTop(), bottom: this.safeBottom() })
  }

  @Builder
  phoneOverlay() {
    Column() {
      this.topBar()
      Column({ space: 8 }) {
        this.searchCard()
        this.resultsPanel()
      }
        .width('100%').margin({ top: 8 })
      Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None)
      this.mapSideTools()
      this.actionCard()
    }
      .width('100%').height('100%')
      .padding({ left: 12, right: 12, top: this.safeTop(), bottom: this.safeBottom() })
      .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  tabletOverlay() {
    Row() {
      Column() {
        this.topBar()
        Column({ space: 8 }) {
          this.searchCard()
          this.resultsPanel()
        }
          .width('100%').layoutWeight(1).margin({ top: 8 })
        this.mapSideTools()
        this.actionCard()
      }
        .width(this.sidePanelWidth()).height('100%')
        .padding({ left: 12, right: 12, top: this.safeTop(), bottom: this.safeBottom() })
        .backgroundColor(this.c.panelGlassStrong)
      Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None)
    }
      .width('100%').height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.mapLayer()
      // Red night-mode wash over every map surface (Petal, local globe,
      // non-Earth globe). Chrome is above it, so buttons keep their theme
      // colors and the map still receives every gesture.
      if (this.c.isNight && !this.mapFailed) {
        Row()
          .width('100%').height('100%')
          .backgroundColor(this.c.mapNightTint)
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.mapFailed) {
        this.mapUnavailableLayer()
      } else {
        if (this.expandedLayout) {
          this.tabletOverlay()
        } else {
          this.phoneOverlay()
        }
        if (this.loading) {
          this.loadingLayer()
        }
      }
    }
      .width('100%').height('100%')
      .backgroundColor(this.c.mediaCard)
      .onAreaChange(() => { this.applyMapPadding() })
  }
}
