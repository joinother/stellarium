import { Theme } from '@kit.ArkUI'
import { map, mapCommon, site } from '@kit.MapKit'
import { connection } from '@kit.NetworkKit'
import hilog from '@ohos.hilog'
import { I18n } from '../../pages/I18n'
import { LocSearchItem } from '../../pages/StellariumTypes'
import { LocationStore } from '../../state/LocationStore'
import { METERED_MAP_APIS_ENABLED } from '../../common/config/OhosFeatureFlags'
import { inverseMapPoint, MapPoint } from '../../pages/MapCoordinate'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { tintMatrixFor } from '../../common/ui/IconTint'

// 本组件职责：位置面板的地点搜索框 + 离线/在线结果列表。
//
//   - 离线分块扫描（searchLocations）先出结果，避免等待网络；
//   - 地球且允许在线时，防抖 400 ms 后再调用花瓣 site.searchByText，
//     在线结果与离线结果分区展示；输入变化会取消上一次在途请求；
//   - 花瓣返回 GCJ02，落在 WGS84 观测点前先做逆转换；
//   - 选中落地（selectSearchLocation）走原生桥，由宿主完成；
//   - 结果行的「省·国」上下文串依赖宿主的翻译缓存，以 contextOf 回调注入；
//   - 输入框会把草稿名同步给位置选择器，以 onNameDraft 回注。
const ONLINE_SEARCH_DEBOUNCE_MS: number = 400
@Component
export struct LocationSearchPanel {
  @ObjectLink store: LocationStore
  @Prop observerPlanet: string = 'Earth'
  // Privacy/foreground gate owned by the host; online POI search is skipped
  // when it is false and the offline list stays usable.
  @Prop onlineAllowed: boolean = false
  @State c: ThemeSlots = DEFAULT_SLOTS
  onSearch: (query: string) => void = () => {}
  onNameDraft: (name: string) => void = () => {}
  onInputFocus: () => void = () => {}
  onInputBlur: () => void = () => {}
  contextOf: (item: LocSearchItem) => string = () => ''
  onPickItem: (item: LocSearchItem) => void = () => {}

  private onlineTimer: number = -1
  private onlineRequestId: number = 0

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToDisappear(): void {
    // Tab switch unmounts this component; keep the result lists so switching
    // back does not lose the query, but drop any in-flight online request.
    if (this.onlineTimer >= 0) {
      clearTimeout(this.onlineTimer)
      this.onlineTimer = -1
    }
    this.onlineRequestId += 1
  }

  private onlineAllowedNow(): boolean {
    if (!METERED_MAP_APIS_ENABLED) return false
    if (this.observerPlanet !== 'Earth' || !this.onlineAllowed) return false
    try {
      return connection.hasDefaultNetSync()
    } catch (_error) {
      // Without the network-info permission, let the request fail into the
      // offline result list rather than hiding the section.
      return true
    }
  }

  private onlineBusy(): boolean {
    return this.store.locSearchOnlineState === 'loading'
  }

  private scheduleOnlineSearch(query: string): void {
    if (this.onlineTimer >= 0) {
      clearTimeout(this.onlineTimer)
      this.onlineTimer = -1
    }
    const q = query.trim()
    if (q.length === 0 || !this.onlineAllowedNow()) {
      this.cancelOnlineSearch()
      return
    }
    // Petal POI search is metered and network-bound: wait for a pause in
    // typing. The offline scan still runs at its own (faster) cadence.
    this.onlineTimer = setTimeout(() => {
      this.onlineTimer = -1
      this.runOnlineSearch(q)
    }, ONLINE_SEARCH_DEBOUNCE_MS)
  }

  private cancelOnlineSearch(): void {
    if (this.onlineTimer >= 0) {
      clearTimeout(this.onlineTimer)
      this.onlineTimer = -1
    }
    this.onlineRequestId += 1
    this.store.locSearchOnlineResults = []
    this.store.locSearchOnlineState = 'idle'
  }

  // Petal returns GCJ02 in the mainland; the engine observer point is WGS84.
  // Mirror the full-screen picker: inverse-convert, then verify with
  // rectifyCoordinate so overseas WGS84 results are left untouched.
  private async onlineToWgs84(position: mapCommon.LatLng): Promise<mapCommon.LatLng> {
    let candidate: MapPoint = position
    try {
      candidate = inverseMapPoint(position, (point: MapPoint): MapPoint =>
        map.convertCoordinateSync(mapCommon.CoordinateType.WGS84, mapCommon.CoordinateType.GCJ02, point))
    } catch (_error) {
      candidate = position
    }
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

  private onlineAltitude(cityName: string, latitude: number, longitude: number): number {
    if (cityName.length > 0) {
      const byCity = this.store.altitudeForCityName(cityName, 'Earth', latitude, longitude)
      if (byCity.found) return Math.round(byCity.altitude)
    }
    const nearest = this.store.altitudeForPoint(latitude, longitude, 'Earth')
    return nearest.found ? Math.round(nearest.altitude) : 0
  }

  private async runOnlineSearch(query: string): Promise<void> {
    const requestId = ++this.onlineRequestId
    this.store.locSearchOnlineState = 'loading'
    this.store.locSearchOnlineResults = []
    try {
      const result = await site.searchByText({
        query: query,
        language: I18n.isChineseLanguage() ? 'zh' : 'en'
      })
      if (requestId !== this.onlineRequestId) return
      const sites = result.sites === undefined ? [] : result.sites
      const items: Array<LocSearchItem> = []
      for (const siteItem of sites) {
        if (!siteItem.location) continue
        const component = siteItem.addressComponent
        const cityName = component.locality ?? component.adminLevel2 ??
          component.adminLevel3 ?? component.adminLevel1 ?? ''
        const point = await this.onlineToWgs84(siteItem.location)
        if (requestId !== this.onlineRequestId) return
        const name = siteItem.name ?? siteItem.formatAddress ?? query
        items.push({
          name: name,
          displayName: name,
          lat: point.latitude,
          lon: point.longitude,
          alt: this.onlineAltitude(cityName, point.latitude, point.longitude),
          planet: 'Earth',
          country: component.countryCode ?? 'ZZ',
          province: component.adminLevel1 ?? component.adminLevel2 ?? ''
        })
        if (items.length >= 20) break
      }
      if (requestId !== this.onlineRequestId) return
      this.store.locSearchOnlineResults = items
      this.store.locSearchOnlineState = items.length > 0 ? 'ok' : 'empty'
      hilog.info(0x0000, 'StellariumArkUI', '[panel-poi] done matches=%{public}d', items.length)
    } catch (error) {
      if (requestId !== this.onlineRequestId) return
      this.store.locSearchOnlineResults = []
      this.store.locSearchOnlineState = 'error'
      hilog.warn(0x0000, 'StellariumArkUI', '[panel-poi] failed: %{public}s',
        error instanceof Error ? error.message : 'search error')
    }
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        TextInput({ text: this.store.locSearchQuery, placeholder: I18n.t('loc_search_placeholder') })
          .height(36)
          .fontSize(13)
          .fontColor(this.c.text)
          .placeholderColor(this.c.sub)
          .backgroundColor(this.c.input)
          .border({ width: 1, color: this.c.inputBorder })
          .borderRadius(UI_RADIUS_CONTROL)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.store.locSearchQuery = value
            this.onNameDraft(value.length > 0 ? value : I18n.t('custom_location'))
            clearTimeout(this.store.locSearchDebounce)
            this.store.locSearchDebounce = setTimeout(() => { this.onSearch(value) }, 260)
            this.scheduleOnlineSearch(value)
          })
          .onFocus(() => { this.onInputFocus() })
          .onBlur(() => { this.onInputBlur() })
          .onSubmit(() => {
            clearTimeout(this.store.locSearchDebounce)
            this.onSearch(this.store.locSearchQuery)
            if (this.onlineTimer >= 0) {
              clearTimeout(this.onlineTimer)
              this.onlineTimer = -1
            }
            const query = this.store.locSearchQuery.trim()
            if (query.length > 0 && this.onlineAllowedNow()) this.runOnlineSearch(query)
          })
        if (this.store.locSearching || this.onlineBusy()) {
          LoadingProgress().width(18).height(18).color(this.c.accent)
        } else {
          Button() {
             Image($r('app.media.ic_search')).width(16).height(16).supportSvg2(true).colorFilter(tintMatrixFor(this.c.onAccent))
           }
             .width(40)
             .height(36)
             .backgroundColor(this.c.accent)
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => {
              clearTimeout(this.store.locSearchDebounce)
              this.onSearch(this.store.locSearchQuery)
              if (this.onlineTimer >= 0) {
                clearTimeout(this.onlineTimer)
                this.onlineTimer = -1
              }
              const query = this.store.locSearchQuery.trim()
              if (query.length > 0 && this.onlineAllowedNow()) this.runOnlineSearch(query)
            })
        }
      }
        .width('100%')
      // Online Petal POI results come first; they are the only results that
      // can cover places missing from the offline hierarchy.
      if (this.store.locSearchOnlineResults.length > 0) {
        Text(I18n.t('map_search_online_section')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2, top: 2 })
        Column({ space: 4 }) {
          ForEach(this.store.locSearchOnlineResults, (item: LocSearchItem) => {
            Row() {
              Column() {
                Row() {
                  Text(item.displayName ?? item.name).fontSize(12).fontColor(this.c.text).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  Text(I18n.t('map_search_online_badge')).fontSize(8).fontColor(this.c.onAccent)
                    .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                    .backgroundColor(this.c.accent).borderRadius(3)
                }.width('100%')
                if (this.contextOf(item).length > 0) {
                  Text(this.contextOf(item)).fontSize(10).fontColor(this.c.tertiary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Text(this.store.formatDegrees(item.lat, 'N', 'S') + ' / ' + this.store.formatDegrees(item.lon, 'E', 'W'))
                  .fontSize(10).fontColor(this.c.tertiary)
              }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              Image($r('app.media.ic_location')).width(14).height(14).fillColor(this.c.tertiary)
            }
              .width('100%')
              .height(58)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.c.soft)
              .border({ width: 1, color: this.c.soft })
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onPickItem(item) })
          }, (item: LocSearchItem) => 'poi|' + item.name + item.lat.toString() + item.lon.toString())
        }
          .width('100%')
      }
      if (this.store.locSearchOnlineState === 'error') {
        Text(I18n.t('map_search_local_hint')).fontSize(10).fontColor(this.c.tertiary).width('100%').padding({ left: 2, top: 2 })
      }
      if (this.store.locSearchResults.length > 0) {
        Text(this.store.locSearchOnlineResults.length > 0
          ? I18n.t('map_search_offline_section') : I18n.t('loc_search_results'))
          .fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2, top: 2 })
        Column({ space: 4 }) {
          ForEach(this.store.locSearchResults, (item: LocSearchItem) => {
            Row() {
              Column() {
                Text(item.displayName ?? item.name).fontSize(12).fontColor(this.c.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.contextOf(item).length > 0) {
                  Text(this.contextOf(item)).fontSize(10).fontColor(this.c.tertiary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Text(this.store.formatDegrees(item.lat, 'N', 'S') + ' / ' + this.store.formatDegrees(item.lon, 'E', 'W'))
                  .fontSize(10).fontColor(this.c.tertiary)
              }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              Image($r('app.media.ic_location')).width(14).height(14).fillColor(this.c.tertiary)
            }
              .width('100%')
              .height(58)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.c.soft)
              .border({ width: 1, color: this.c.soft })
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onPickItem(item) })
          }, (item: LocSearchItem) => item.name + item.lat.toString())
        }
          .width('100%')
      }
      if (this.store.locSearching && this.store.locSearchResults.length === 0) {
        Text(I18n.t('search_catalog_loading')).fontSize(11).fontColor(this.c.tertiary).width('100%').padding({ left: 2, top: 2 })
      } else if (this.onlineBusy() && this.store.locSearchOnlineResults.length === 0 &&
        this.store.locSearchResults.length === 0) {
        Text(I18n.t('map_search_loading')).fontSize(11).fontColor(this.c.tertiary).width('100%').padding({ left: 2, top: 2 })
      } else if (this.store.locSearchQuery.trim().length > 0 && !this.store.locSearching && !this.onlineBusy() &&
        this.store.locSearchResults.length === 0 && this.store.locSearchOnlineResults.length === 0 &&
        this.store.locSearchOnlineState !== 'error') {
        Text(I18n.t('loc_no_results')).fontSize(11).fontColor(this.c.tertiary).width('100%').padding({ left: 2, top: 2 })
      }
    }
      .width('100%')
      .margin({ top: 10 })
  }
}
