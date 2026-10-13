import { image } from '@kit.ImageKit'
import { SkyCultureArtItem, TabItem } from '../../pages/StellariumTypes'
import { ConfigurationOption, OFFLINE_APPGALLERY_BUILD } from '../../pages/MainWindowModels'
import { AtmosphereStore } from '../../state/AtmosphereStore'
import { LayerStore } from '../../state/LayerStore'
import { LayerViewStore } from '../../state/LayerViewStore'
import { OverlayStore } from '../../state/OverlayStore'
import { SkyCultureSettingsStore } from '../../state/SkyCultureSettingsStore'
import { SkyCultureViewStore } from '../../state/SkyCultureViewStore'
import { SurveyStore } from '../../state/SurveyStore'
import { LayerPresetBar } from '../layers/LayerPresetBar'
import { LayerTabs } from '../layers/LayerTabs'
import { LayerSkyTab, LayerSsoTab, LayerDsoTab, LayerMarkingsTab, LayerLandscapeTab, LayerSurveysTab } from '../layers/LayerViewTabs'
import { SkyCultureViewTab } from '../skyculture/SkyCultureViewTab'

// 「图层」面板，对应 `activePanel === 'layers'`：组装图层预设条 + 视图标签页选择器 +
// 六个图层页签（Sky/Sso/Dso/Markings/Landscape/Surveys）+ 星空文化页签 SkyCultureViewTab；
// 预设条与页签选择器之间有一条横向分隔线，「清除坐标与标记」已上移到面板标题栏。
//
// 「天空」页分 恒星 / 天空 / 观测条件 三节；大气折射块（ObservationAidBlock）挂在观测条件节内。
//
// 五个 store（layer / layerView / skyCultureView / skyCultureSettings / atmosphere）走 @ObjectLink；
// 主题色、当前页签、标签数据、解码结果 / canvas 上下文等走 @Prop 或普通成员；
// native 桥 / 定时器 / 解码 / canvas 绘制 / 快捷键分发动作用回调注入宿主。
@Component
export struct LayersPanel {
  @ObjectLink layerStore: LayerStore
  @ObjectLink layerViewStore: LayerViewStore
  @ObjectLink overlayStore: OverlayStore
  @ObjectLink skyCultureViewStore: SkyCultureViewStore
  @ObjectLink skyCultureSettingsStore: SkyCultureSettingsStore
  @ObjectLink atmosphereStore: AtmosphereStore
  @ObjectLink surveyStore: SurveyStore
  @Prop nightModeOn: boolean
  @Prop viewTab: number
  @Prop expandedLayout: boolean
  @Prop foldTablet: boolean
  @Prop viewTabContentOpacity: number
  @Prop viewTabContentOffsetX: number
  @Prop layerTabs: TabItem[]
  @Prop skyCultureArtStates: Record<string, string> = {}
  @Prop skyCultureArtThumbnailPixelMaps: Record<string, image.PixelMap> = {}
  @Prop narrationParagraphs: Array<string> = []
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop cardBorder: string
  @Prop inputColor: string
  @Prop pickerSurface: string
  @Prop pickerHeader: string
  @Prop pickerHeaderActive: string
  @Prop pickerSelected: string
  @Prop pickerOption: string
  mapContextSettings: RenderingContextSettings = new RenderingContextSettings(true)
  mapContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.mapContextSettings)
  onPreset: (preset: string) => void = () => {}
  onSelectTab: (id: number) => void = () => {}
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onRefreshSurvey: () => void = () => {}
  onSelectSpectral: (id: string) => void = () => {}
  onCloseSpectral: () => void = () => {}
  onSetSkyDisplay: (setting: string, value: boolean | number) => void = () => {}
  onStarMagLimit: (value: number) => void = () => {}
  onMilkyWayBright: (value: number) => void = () => {}
  onAtmosphere: (pressure: number, temperature: number, extinction: number) => void = () => {}
  onSetOrbitFlag: (setting: string, enabled: boolean) => void = () => {}
  onSetOrbitThickness: (value: number) => void = () => {}
  onSetOrbitColorStyle: (index: number) => void = () => {}
  onLoadOrbitSettings: () => void = () => {}
  onSetTrailFlag: (setting: string, enabled: boolean) => void = () => {}
  onSetTrailNumber: (setting: string, value: number) => void = () => {}
  onLoadTrailSettings: () => void = () => {}
  onApplyTrailColor: () => void = () => {}
  onTriggerAction: (actionId: string) => void = () => {}
  onSetFovMarker: (setting: string, value: number) => void = () => {}
  onToggleViewCoordinates: (visible: boolean) => void = () => {}
  onSelectViewCoordinateFamily: (family: string) => void = () => {}
  onSelectViewEquatorialEpoch: (epoch: string) => void = () => {}
  onSetLandscapeFadeWithZoom: (isOn: boolean) => void = () => {}
  onImportLandscape: () => void = () => {}
  onSelectLandscape: (id: string, name: string) => void = () => {}
  onChangeLandscapeTransparency: (val: number) => void = () => {}
  onLoadList: () => void = () => {}
  onSelectCulture: (id: string) => void = () => {}
  onRowArea: (id: string, area: Area) => void = () => {}
  onReloadList: () => void = () => {}
  onSelectLabelMode: (target: string, index: number) => void = () => {}
  onSetShortLabels: (enabled: boolean) => void = () => {}
  onSetCommonNames: (enabled: boolean) => void = () => {}
  onSetIsolation: (enabled: boolean) => void = () => {}
  onSetSinglePick: (enabled: boolean) => void = () => {}
  onConstellationSelection: (actionId: string, hint: string) => void = () => {}
  onSetStyleOption: (target: string, optionIndex: number, enabled: boolean) => void = () => {}
  getColorOptions: () => Array<ConfigurationOption> = () => []
  onSetVisualColor: (setting: string, color: string) => void = () => {}
  onSetVisualSetting: (setting: string, value: number) => void = () => {}
  onSetDefault: () => void = () => {}
  onSyncTimeFollowTimer: () => void = () => {}
  onRefreshSimulationYear: () => void = () => {}
  onLoadTerritoryMap: () => void = () => {}
  onMapReady: () => void = () => {}
  onMapAreaChange: (width: number, height: number) => void = () => {}
  onLoadObserverInfo: (force: boolean) => void = () => {}
  onArtDecodeError: (rawPath: string) => void = () => {}
  onOpenArtPreview: (art: SkyCultureArtItem) => void = () => {}

  build() {
      Column() {
        LayerPresetBar({ subColor: this.subColor, textColor: this.textColor, panelColor: this.panelColor, onPreset: (preset: string) => { this.onPreset(preset) } })
        // 图层预设 tag 与子面板标签 tag 之间的横向分隔线
        Row().width('100%').height(0.5).backgroundColor(this.cardBorder).margin({ top: 2, bottom: 2 })
        LayerTabs({ tabs: this.layerTabs, activeTab: this.viewTab, foldTablet: this.foldTablet, textColor: this.textColor, subColor: this.subColor, accentColor: this.accentColor, panelColor: this.panelColor, onSelectTab: (id: number) => { this.onSelectTab(id) } })
        Column({ space: 0 }) {
          if (this.viewTab === 0) {
            LayerSkyTab({
              layerStore: this.layerStore,
              layerViewStore: this.layerViewStore,
              nightModeOn: this.nightModeOn,
              refractionOn: this.atmosphereStore.refractionOn,
              atmoPressure: this.atmosphereStore.atmoPressure,
              atmoTemperature: this.atmosphereStore.atmoTemperature,
              atmoExtinction: this.atmosphereStore.atmoExtinction,
              textColor: this.textColor,
              subColor: this.subColor,
              accentColor: this.accentColor,
              panelColor: this.panelColor,
              cardBorder: this.cardBorder,
              onToggleLayer: (actionId: string, cmd: string, value: boolean) => { this.onToggleLayer(actionId, cmd, value) },
              onSetSkyDisplay: (setting: string, value: boolean | number) => { this.onSetSkyDisplay(setting, value) },
              onStarMagLimit: (value: number) => { this.onStarMagLimit(value) },
              onMilkyWayBright: (value: number) => { this.onMilkyWayBright(value) },
              onAtmosphere: (pressure: number, temperature: number, extinction: number) => { this.onAtmosphere(pressure, temperature, extinction) }
            })
          } else if (this.viewTab === 1) {
            LayerSsoTab({
              layerStore: this.layerStore,
              layerViewStore: this.layerViewStore,
              expandedLayout: this.expandedLayout,
              textColor: this.textColor,
              subColor: this.subColor,
              accentColor: this.accentColor,
              panelColor: this.panelColor,
              onToggleLayer: (actionId: string, cmd: string, value: boolean) => { this.onToggleLayer(actionId, cmd, value) },
              onSetOrbitFlag: (setting: string, enabled: boolean) => { this.onSetOrbitFlag(setting, enabled) },
              onSetOrbitThickness: (value: number) => { this.onSetOrbitThickness(value) },
              onSetOrbitColorStyle: (index: number) => { this.onSetOrbitColorStyle(index) },
              onLoadOrbitSettings: () => { this.onLoadOrbitSettings() },
              onSetTrailFlag: (setting: string, enabled: boolean) => { this.onSetTrailFlag(setting, enabled) },
              onSetTrailNumber: (setting: string, value: number) => { this.onSetTrailNumber(setting, value) },
              onLoadTrailSettings: () => { this.onLoadTrailSettings() },
              onApplyTrailColor: () => { this.onApplyTrailColor() },
              onTriggerAction: (actionId: string) => { this.onTriggerAction(actionId) }
            })
          } else if (this.viewTab === 2) {
            LayerDsoTab({
              layerStore: this.layerStore,
              subColor: this.subColor,
              onToggleLayer: (actionId: string, cmd: string, value: boolean) => { this.onToggleLayer(actionId, cmd, value) }
            })
          } else if (this.viewTab === 3) {
            LayerMarkingsTab({
              layerStore: this.layerStore,
              layerViewStore: this.layerViewStore,
              overlayStore: this.overlayStore,
              textColor: this.textColor,
              subColor: this.subColor,
              accentColor: this.accentColor,
              panelColor: this.panelColor,
              cardBorder: this.cardBorder,
              onToggleLayer: (actionId: string, cmd: string, value: boolean) => { this.onToggleLayer(actionId, cmd, value) },
              onSetFovMarker: (setting: string, value: number) => { this.onSetFovMarker(setting, value) },
              onToggleViewCoordinates: (visible: boolean) => { this.onToggleViewCoordinates(visible) },
              onSelectViewCoordinateFamily: (family: string) => { this.onSelectViewCoordinateFamily(family) },
              onSelectViewEquatorialEpoch: (epoch: string) => { this.onSelectViewEquatorialEpoch(epoch) }
            })
          } else if (this.viewTab === 4) {
            LayerLandscapeTab({
              layerStore: this.layerStore,
              layerViewStore: this.layerViewStore,
              textColor: this.textColor,
              subColor: this.subColor,
              accentColor: this.accentColor,
              panelColor: this.panelColor,
              onToggleLayer: (actionId: string, cmd: string, value: boolean) => { this.onToggleLayer(actionId, cmd, value) },
              onSetLandscapeFadeWithZoom: (isOn: boolean) => { this.onSetLandscapeFadeWithZoom(isOn) },
              onImportLandscape: () => { this.onImportLandscape() },
              onSelectLandscape: (id: string, name: string) => { this.onSelectLandscape(id, name) },
              onChangeLandscapeTransparency: (val: number) => { this.onChangeLandscapeTransparency(val) }
            })
          } else if (this.viewTab === 5) {
            SkyCultureViewTab({
              settings: this.skyCultureSettingsStore,
              layerStore: this.layerStore,
              skyCultureViewStore: this.skyCultureViewStore,
              artStates: this.skyCultureArtStates,
              artThumbnailPixelMaps: this.skyCultureArtThumbnailPixelMaps,
              narrationParagraphs: this.narrationParagraphs,
              textColor: this.textColor,
              subColor: this.subColor,
              accentColor: this.accentColor,
              panelColor: this.panelColor,
              cardBorder: this.cardBorder,
              inputColor: this.inputColor,
              pickerSurface: this.pickerSurface,
              pickerHeader: this.pickerHeader,
              pickerHeaderActive: this.pickerHeaderActive,
              pickerSelected: this.pickerSelected,
              pickerOption: this.pickerOption,
              mapContext: this.mapContext,
              onToggleLayer: (actionId: string, cmd: string, value: boolean) => { this.onToggleLayer(actionId, cmd, value) },
              onLoadList: () => { this.onLoadList() },
              onSelectCulture: (id: string) => { this.onSelectCulture(id) },
              onRowArea: (id: string, area: Area) => { this.onRowArea(id, area) },
              onReloadList: () => { this.onReloadList() },
              onSelectLabelMode: (target: string, index: number) => { this.onSelectLabelMode(target, index) },
              onSetShortLabels: (enabled: boolean) => { this.onSetShortLabels(enabled) },
              onSetCommonNames: (enabled: boolean) => { this.onSetCommonNames(enabled) },
              onSetIsolation: (enabled: boolean) => { this.onSetIsolation(enabled) },
              onSetSinglePick: (enabled: boolean) => { this.onSetSinglePick(enabled) },
              onConstellationSelection: (actionId: string, hint: string) => { this.onConstellationSelection(actionId, hint) },
              onSetStyleOption: (target: string, optionIndex: number, enabled: boolean) => { this.onSetStyleOption(target, optionIndex, enabled) },
              getColorOptions: () => this.getColorOptions(),
              onSetVisualColor: (setting: string, color: string) => { this.onSetVisualColor(setting, color) },
              onSetVisualSetting: (setting: string, value: number) => { this.onSetVisualSetting(setting, value) },
              onSetDefault: () => { this.onSetDefault() },
              onSyncTimeFollowTimer: () => { this.onSyncTimeFollowTimer() },
              onRefreshSimulationYear: () => { this.onRefreshSimulationYear() },
              onLoadTerritoryMap: () => { this.onLoadTerritoryMap() },
              onMapReady: () => { this.onMapReady() },
              onMapAreaChange: (width: number, height: number) => { this.onMapAreaChange(width, height) },
              onLoadObserverInfo: (force: boolean) => { this.onLoadObserverInfo(force) },
              onArtDecodeError: (rawPath: string) => { this.onArtDecodeError(rawPath) },
              onOpenArtPreview: (art: SkyCultureArtItem) => { this.onOpenArtPreview(art) }
            })
          } else if (this.viewTab === 6 && !OFFLINE_APPGALLERY_BUILD) {
            LayerSurveysTab({
              layerStore: this.layerStore,
              surveyStore: this.surveyStore,
              textColor: this.textColor,
              subColor: this.subColor,
              accentColor: this.accentColor,
              panelColor: this.panelColor,
              lineColor: this.cardBorder,
              onToggleLayer: (actionId: string, cmd: string, value: boolean) => { this.onToggleLayer(actionId, cmd, value) },
              onRefreshSurvey: () => { this.onRefreshSurvey() },
              onSelectSpectral: (id: string) => { this.onSelectSpectral(id) },
              onCloseSpectral: () => { this.onCloseSpectral() }
            })
          } else {
            LayerSkyTab({
              layerStore: this.layerStore,
              layerViewStore: this.layerViewStore,
              nightModeOn: this.nightModeOn,
              refractionOn: this.atmosphereStore.refractionOn,
              atmoPressure: this.atmosphereStore.atmoPressure,
              atmoTemperature: this.atmosphereStore.atmoTemperature,
              atmoExtinction: this.atmosphereStore.atmoExtinction,
              textColor: this.textColor,
              subColor: this.subColor,
              accentColor: this.accentColor,
              panelColor: this.panelColor,
              cardBorder: this.cardBorder,
              onToggleLayer: (actionId: string, cmd: string, value: boolean) => { this.onToggleLayer(actionId, cmd, value) },
              onSetSkyDisplay: (setting: string, value: boolean | number) => { this.onSetSkyDisplay(setting, value) },
              onStarMagLimit: (value: number) => { this.onStarMagLimit(value) },
              onMilkyWayBright: (value: number) => { this.onMilkyWayBright(value) },
              onAtmosphere: (pressure: number, temperature: number, extinction: number) => { this.onAtmosphere(pressure, temperature, extinction) }
            })
          }
        }
          .width('100%')
          .opacity(this.viewTabContentOpacity)
          .translate({ x: this.viewTabContentOffsetX, y: 0 })
      }
        .width('100%')
  }
}
