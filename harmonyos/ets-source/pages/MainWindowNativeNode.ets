import { abilityAccessCtrl, common, Permissions, Want } from '@kit.AbilityKit'
import { geoLocationManager } from '@kit.LocationKit'
import { sensor } from '@kit.SensorServiceKit'
import { curves } from '@kit.ArkUI'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { media } from '@kit.MediaKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { systemShare } from '@kit.ShareKit'
import { privacyManager } from '@kit.AppGalleryKit'
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent'
import { isEngineReady } from 'libentry.so'
import { writeClipboardText } from '../qability/ClipboardService'
import { fileIo, fileUri, picker } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { image } from '@kit.ImageKit'
import hilog from '@ohos.hilog'
import display from '@ohos.display'
import preferences from '@ohos.data.preferences'
import { LOCATION_HIERARCHY } from '../common/location/hierarchy'
import { LOCATION_COUNTRY_NAMES } from '../common/location/countries'
import { LOCATION_ZH_NAMES } from '../common/location/names_zh'
import { ASTRONOMY_GUIDES, AstronomyGuide, GuideState, GuideStep } from '../common/derive/AstronomyGuide'

import { StellariumBridgeResponse, SessionSnapshot, TonightPlanet, TonightShower, TonightEvents, WutTarget, EphemerisRow, AstroCalcContext, RtsCalendarDay, AltAzPoint, AnnualElevationPoint, ObservabilityDay, LunarElongationPoint, PlanetTimeSeriesPoint, PlanetPairDistancePoint, PlanetCalcItem, PhenomenonItem, EclipseItem, PlanetaryTransitItem, MoonPhaseItem, SeasonEvent, LangOption, HierCity, NameItem, SearchSug, WindowNativeNodeCreateInfo, ChipItem, LandscapeItem, ScriptMetadata, HeliocentricPosition, CelestialPosition, ObjectInfo, SkyCultureItem, SkyCultureRawItem, SkyCultureArtItem, SkyCultureDescriptionBlock, SkyCultureTerritoryEntry, SkyCultureTerritoryPolygon, PluginItem, Scenery3dItem, ShellAction, LocSearchItem, SavedLocation, ObjectDetailField, ObjectDetailModel, SatellitePass, KeyboardShortcutItem } from './StellariumTypes'
import { setLifecycleListener } from '../common/StellariumLifecycle'
import { AudioEngine } from '../capability/AudioEngine'
import { I18n, LANGUAGE_DISPLAY, PROJECTION_KEYS } from './I18n'
import { DeepSkyWarmupStatus, getDeepSkyResourceWarmupStatus, isStellariumDetailMediaPreparationFailed, resolveStellariumDetailMediaAsset } from '../qability/StellariumResourceBootstrap'
import { UI_RADIUS_CONTROL, UI_RADIUS_PANEL, UI_RADIUS_SHEET, UI_RADIUS_PILL, UI_OPTION_ANIMATION_MS } from '../common/ui/UiTokens'
import { getIcon } from '../common/ui/ShellIcons'
import { dockItemIndex } from '../common/ui/DockGeometry'
import {
  CHROME_ROW_OFFSET,
  CHROME_ZOOM_BUTTON_SIZE,
  chromeZoomButtonLeft,
  chromeZoomButtonTop
} from '../common/ui/ChromeGeometry'
import { gyroRotateAboutAxis, gyroMultiplyQuaternions, gyroFilterDeviceVector, gyroCross, gyroRotateAboutVertical, gyroScreenAxisForDisplay, shortestGyroAzimuthDelta, wrapGyroAzimuth, gyroNormalizeVector, gyroNormalizeQuaternion, gyroConjugateQuaternion, gyroDot, gyroMagneticHeadingFromDeviceVectors } from '../common/derive/gyro'
import { jdToLocalTimeText, graphModeLabel, graphStartOptionLabel, planetMetricUnit, planetPairBodyName, phenomenonCaption, hecPointColor, hecLayoutPositions, hecPointLeft, hecPointTop, messierNumberOf, minorPlanetNumberOf, fmtDegMin, clamp, distance } from '../common/derive/astro'
import { resourceText, describeDecodeError, zhNameOf, zhType, planetZh, sensZh, scriptZh, scriptDesc, pluginZh, pluginDesc, pluginHostName, pluginFeatureRoute, approximateTimeZoneDisplay, panelTitleFor, celestialTitle, quickLocationLabel } from '../common/derive/labels'
import { isSafeSkyCultureArtPath, cleanSkyCultureDescription, cleanSkyCultureNarration, isCliPanelName, parseObservingList, formatRate, configDitheringLabel, isRecordable } from '../common/derive/skycult'
import { primaryDockActions, moreActions, observingHubActions, skyDataHubActions, automationHubActions, getCityPreset, validationFromResponse, officialLocationAliases, panelRouteParent, inferredPanelRouteDirection, locationSearchMatchScore } from '../common/derive/actions'
import { quickActionById, quickCandidateRowsFor } from '../common/derive/quickActions'
import { pointInsideRect, pointOverlapsUiObstacle, touchScreenX, touchScreenY, touchWindowX, touchWindowY, azBarHeight, compactTopQuickY, baseCompactObjectPeekY, expandedDetailSummaryHeight, isPhoneDetailPeek, useTabletObjectInspector, useExpandedDetailSummary, railTop, expandedMainPanelLeft, panelLeft, panelRight, baseExpandedDetailSummaryX, baseExpandedDetailSummaryY, baseTabletInspectorX, baseTabletInspectorY, tabletInspectorHeight, baseBottomCardX, baseBottomCardY, expandedDockWidth, expandedDockLeft, dockWidthPixels, dockLeft, chromeRowPosXLeft, chromeRowPosXRight, guideCardHeight, guideCardX, guideCardY, scriptControlWidth, scriptControlX, scriptControlY, isPanelBackPoint, isDockPoint, isObjectDetailCardPoint, canShowExpandedDetailSummary, expandedDetailSummaryWidth } from '../common/derive/geometry'
import { catalogIconForModule, catalogIconForObjectType, wutCategoryOptions, wutCategoryKey, wutDirectionLabel } from '../common/derive/catalog'
import { objectInspectorFallbackVisualKind, objectInspectorStarColor } from '../common/derive/media'
import { BridgeClient } from '../bridge/BridgeClient'
import { CommandPort } from '../bridge/CommandPort'
import { MediaPort, MediaSaveResult, ScreenCaptureState, MediaImportResult } from '../bridge/MediaPort'
import { PlatformPort } from '../bridge/PlatformPort'
import { SensorPort, SensorProbeInfo } from '../bridge/SensorPort'
import { LocationPort, LocationFix } from '../bridge/LocationPort'
import { LocationController, LocationHostHooks } from '../capability/LocationController'
import { LocationStoreHostHooks, LocationDraft } from '../state/LocationStore'
import { decodeLocalImage, releaseDecodedImage } from '../common/media/ImageDecoder'
import { copyTextToClipboard } from '../common/platform/Clipboard'
import { shareFile } from '../common/platform/Share'
import { saveScreenshot, exportScreenshotToUserStorage } from '../common/platform/Screenshot'
import { speakSelectedObject } from '../common/SpeechService'
import { StartupBridge, StartupHooks } from '../capability/StartupBridge'
import { SensorController, GyroGuideLayout, SensorHostHooks } from '../capability/SensorController'
import { NotificationController, NotificationHostHooks } from '../capability/NotificationController'
import { SurveyController, SurveyHostHooks } from '../capability/SurveyController'
import { ARController, ARHostHooks } from '../capability/ARController'
import { KeyboardShortcutController, KeyboardShortcutHostHooks, KeyboardShortcutInputHooks } from '../capability/KeyboardShortcutController'
import { TimeTransitionController, TimeTransitionHostHooks } from '../capability/TimeTransitionController'
import { publishAstronomyCard } from '../qability/AstronomyCardService'
import { CardTonightData } from '../form/AstronomyCardData'
import { RecordingController, RecordingHostHooks } from '../capability/RecordingController'
import { ObjectModelRenderer, ObjectModelRendererHostHooks } from '../capability/ObjectModelRenderer'
import { SkyInputController, SkyInputHostHooks } from '../capability/SkyInputController'
import { DetailConnectorController, DetailConnectorHostHooks } from '../capability/DetailConnectorController'
import { LayerController, LayerHostHooks } from '../capability/LayerController'
import { SkyTextureStatusController, SkyTextureStatusHostHooks } from '../capability/SkyTextureStatusController'
import { NebulaTextureController, NebulaTextureHostHooks } from '../capability/NebulaTextureController'
import { OcularController } from '../capability/OcularController'
import { TelescopeController, TelescopeHostHooks } from '../capability/TelescopeController'
import { PolarScopeController, PolarScopeHostHooks, PolarScopeSessionFlags } from '../capability/PolarScopeController'
import { ViewCoordinateController, ViewCoordinateHostHooks } from '../capability/ViewCoordinateController'
import { SatelliteController, SatelliteHostHooks } from '../capability/SatelliteController'
import { AstroCalcController, AstroCalcHostHooks } from '../capability/AstroCalcController'
import { PluginFeatureController, PluginFeatureHostHooks } from '../capability/PluginFeatureController'
import { ObjectInspectorMediaController, ObjectInspectorMediaHostHooks } from '../capability/ObjectInspectorMediaController'
import { ScriptPlaybackController, ScriptPlaybackHostHooks } from '../capability/ScriptPlaybackController'
import { GuideController, GuideControllerHooks } from '../capability/GuideController'
import { SettingsController, TimeSettingsHostHooks } from '../capability/SettingsController'
import { TimeController, TimeHostHooks } from '../capability/TimeController'
import { SkyCultureController, SkyCultureHostHooks } from '../capability/SkyCultureController'
import { SkyCultureMakerController, SkyCultureMakerHostHooks } from '../capability/SkyCultureMakerController'
import { BehaviorHostHooks } from '../capability/ControllerHooks'
import { SearchController, SearchHostHooks } from '../capability/SearchController'
import { SelfTestController } from '../capability/SelfTestController'
import { TimeStore } from '../state/TimeStore'
import { SatelliteStore } from '../state/SatelliteStore'
import { ScriptStore } from '../state/ScriptStore'
import { SceneryStore } from '../state/SceneryStore'
import { ARStore } from '../state/ARStore'
import { CatalogStore } from '../state/CatalogStore'
import { MeteorStore } from '../state/MeteorStore'
import { CommandStore } from '../state/CommandStore'
import { TimeSpeedChips } from '../panels/time/TimeSpeedChips'
import { JulianDateStore } from '../state/JulianDateStore'
import { JulianDateControls } from '../panels/time/JulianDateControls'
import { SiderealTimeRow } from '../panels/time/SiderealTimeRow'
import { EquationOfTimeBlock } from '../panels/time/EquationOfTimeBlock'
import { EquationOfTimeStore } from '../state/EquationOfTimeStore'
import { DeltaTStore } from '../state/DeltaTStore'
import { TimeSettingsStore } from '../state/TimeSettingsStore'
import { SettingsChoiceButton } from '../common/ui/SettingsChoiceButton'
import { NightModeStore } from '../state/NightModeStore'
import { SettingsRepository, SettingsPersistencePort, UiSettings, UI_SETTINGS_STORE, UI_SETTINGS_KEY } from '../state/SettingsRepository'
import { accentForNightMode, slotsForNightMode, stellariumTheme, AstroColors, DEFAULT_SLOTS, ThemeSlots } from '../state/StellariumTheme'
import { TimeWheelController } from '../state/TimeWheelController'
import { BookmarkStore } from '../state/BookmarkStore'
import { BookmarkPanel } from '../panels/panels/BookmarkPanel'
import { SearchStore } from '../state/SearchStore'
import { ObjectDetailStore } from '../state/ObjectDetailStore'
import { GyroStore } from '../state/GyroStore'
import { WutStore } from '../state/WutStore'
import { NotificationStore } from '../state/NotificationStore'
import { SurveyStore } from '../state/SurveyStore'
import { KeyboardShortcutStore } from '../state/KeyboardShortcutStore'
import { AstroStore } from '../state/AstroStore'
import { LocationStore } from '../state/LocationStore'
import { CityChipsRow } from '../panels/location/CityChipsRow'
import { LocationPickerPanel } from '../panels/location/LocationPickerPanel'
import { LocationPickerStore } from '../state/LocationPickerStore'
import { LayerStore } from '../state/LayerStore'
import { LayerPresetBar } from '../panels/layers/LayerPresetBar'
import { LayerTabs } from '../panels/layers/LayerTabs'
import { LayerViewStore } from '../state/LayerViewStore'
import { LayerSkyTab, LayerSsoTab, LayerDsoTab, LayerMarkingsTab, LayerLandscapeTab, LayerSurveysTab } from '../panels/layers/LayerViewTabs'
import { TelescopeStore } from '../state/TelescopeStore'
import { OcularSelector } from '../panels/telescope/OcularSelector'
import { OcularMetric } from '../panels/telescope/OcularMetric'
import { Lx200Panel } from '../panels/telescope/Lx200Panel'
import { Lx200ObjectControls } from '../panels/telescope/Lx200ObjectControls'
import { SkyCultureMakerStore } from '../state/SkyCultureMakerStore'
import { SkyCultureViewStore } from '../state/SkyCultureViewStore'
import { SkyCultureSettingsStore } from '../state/SkyCultureSettingsStore'
import { AstroSelectionGuide, PhenomenonRelationMark } from '../panels/astro/AstroGuides'
import { ContinuationSection } from '../panels/astro/ContinuationSection'
import { WutTargetCard } from '../panels/astro/WutTargetCard'
import { AstroPanel } from '../panels/astro/AstroPanel'
import { InfoRow } from '../common/ui/InfoRow'
import { ObjectMediaStore } from '../state/ObjectMediaStore'
import { ObjectDataRow, StructuredDetailRow, DetailSectionTitle } from '../panels/object/DetailRows'
import { TabletInspectorMediaCard, TabletInspectorNoticeRow, TabletInspectorModelBlock, TabletInspectorProgressRow, TabletInspectorFallbackVisual } from '../panels/object/TabletInspectorMedia'
import { ObjectDataTile, ObjectMetric, ObjectScheduleTile, ObjectDetailTab, ObjectCompactMetric } from '../panels/object/DetailTiles'
import { ObjectDistanceNotice, SelectedLiveInfoRows, SelectedCoordinateRow, SelectedCoordinateRows } from '../panels/object/DetailLiveRows'
import { StructuredDetailRows } from '../panels/object/StructuredDetailRows'
import { SatellitePassDetails } from '../panels/object/SatellitePassDetails'
import { TabletInspectorMediaGroup } from '../panels/object/TabletInspectorMediaGroup'
import { PanelHeader } from '../panels/shell/PanelHeader'
import { DockButton } from '../panels/shell/DockButton'
import { CompactTopQuickControls } from '../panels/shell/CompactTopQuickControls'
import { HubActionList } from '../panels/shell/HubActionList'
import { ConstellationCultureView } from '../panels/object/ConstellationCultureView'
import { SkyCultureMakerTabs } from '../panels/skyculture/SkyCultureMakerTabs'
import { SkyCultureMakerOverview } from '../panels/skyculture/SkyCultureMakerOverview'
import { SkyCultureMakerConstellationEditor } from '../panels/skyculture/SkyCultureMakerConstellationEditor'
import { SkyCultureMakerValidationPanel } from '../panels/skyculture/SkyCultureMakerValidationPanel'
import { SearchBar } from '../panels/search/SearchBar'
import { SearchSuggestions } from '../panels/search/SearchSuggestions'
import { SearchFilterMenu } from '../panels/search/SearchFilterMenu'
import { SearchFilterChips } from '../panels/search/SearchFilterChips'
import { SearchCategoryBrowse } from '../panels/search/SearchCategoryBrowse'
import { SearchConstellationChips } from '../panels/search/SearchConstellationChips'
import { SearchCoordinateInput } from '../panels/search/SearchCoordinateInput'
import { TimeJumpActions } from '../panels/time/TimeJumpActions'
import { ManualTimeBlock } from '../panels/time/ManualTimeBlock'
import { TimeWheelStore } from '../state/TimeWheelStore'
import { TimeWheelScrubber } from '../panels/time/TimeWheelScrubber'
import { OverlayStore } from '../state/OverlayStore'
import { PolarScopeStore } from '../state/PolarScopeStore'
import { ArchaeoStore } from '../state/ArchaeoStore'
import { NavStarsStore } from '../state/NavStarsStore'
import { MosaicStore } from '../state/MosaicStore'
import { ObservingListStore } from '../state/ObservingListStore'
import { AudioStore } from '../state/AudioStore'
import { EphemerisStore } from '../state/EphemerisStore'
import { NebulaTextureStore } from '../state/NebulaTextureStore'
import { PluginStore } from '../state/PluginStore'
import { NavigationSettingsStore } from '../state/NavigationSettingsStore'
import { ViewSettingsStore } from '../state/ViewSettingsStore'
import { InfoWindowStore } from '../state/InfoWindowStore'
import { LanguageStore } from '../state/LanguageStore'
import { AtmosphereStore } from '../state/AtmosphereStore'
import { GuideStore } from '../state/GuideStore'
import { PointerCoordinatesPanel } from '../panels/view/PointerCoordinatesPanel'
import { ViewCenterCoordinateOverlay } from '../panels/overlay/ViewCenterCoordinateOverlay'
import { PolarScopeOverlay } from '../panels/overlay/PolarScopeOverlay'
import { ObjectInspectorMediaPreviewOverlay } from '../panels/overlay/ObjectInspectorMediaPreviewOverlay'
import { SkyCultureArtPreviewOverlay } from '../panels/overlay/SkyCultureArtPreviewOverlay'
import { ObjectInspectorModelOverlay } from '../panels/overlay/ObjectInspectorModelOverlay'
import { ToolsStore } from '../state/ToolsStore'
import { ToolsPanel } from '../panels/tools/ToolsPanel'
import { RecordingControlBar } from '../panels/tools/RecordingControlBar'
import { RecordingFocusShell } from '../panels/tools/RecordingFocusShell'
import { SessionToolStore } from '../state/SessionToolStore'
import { ObserverPlanetSection, PointingTestSection, WatchGyroSection, TonightEventsSection } from '../panels/astro/SessionToolSections'
import { GyroTargetGuide } from '../panels/astro/GyroTargetGuide'
import { SkyCultureMakerPanel } from '../panels/skyculture/SkyCultureMakerPanel'
import { SkyCultureViewTab } from '../panels/skyculture/SkyCultureViewTab'
import { PanelHandle } from '../panels/shell/PanelChromeExtras'
import { ScriptFocusShell } from '../panels/shell/ScriptFocusShell'
import { CompactShell } from '../panels/shell/CompactShell'
import { HarmonyShell } from '../panels/shell/HarmonyShell'
import { HoverObservatoryShell } from '../panels/shell/HoverObservatoryShell'
import { ExpandedShell } from '../panels/shell/ExpandedShell'
import { ScriptKeyButton } from '../panels/tools/ScriptKeyButton'
import { GuideLibrary } from '../panels/guide/GuideLibrary'
import { InteractiveGuideShell } from '../panels/shell/InteractiveGuideShell'
import { AngleMeasurePanel } from '../panels/panels/AngleMeasurePanel'
import { AudioPanel } from '../panels/panels/AudioPanel'
import { Scenery3dPanel } from '../panels/panels/Scenery3dPanel'
import { ARPreviewPanel } from '../panels/ar/ARPreviewPanel'
import { CatalogsPanel } from '../panels/panels/CatalogsPanel'
import { PlacePanel } from '../panels/panels/PlacePanel'
import { CommandsPanel } from '../panels/panels/CommandsPanel'
import { NavStarsPanel } from '../panels/panels/NavStarsPanel'
import { ArchaeoLinesPanel } from '../panels/panels/ArchaeoLinesPanel'
import { MosaicCameraPanel } from '../panels/panels/MosaicCameraPanel'
import { MorePanel } from '../panels/panels/MorePanel'
import { QuickPanel, QuickPanelStore } from '../panels/panels/QuickPanel'
import { TimePanel } from '../panels/panels/TimePanel'
import { HelpPanel } from '../panels/panels/HelpPanel'
import { MeteorShowersPanel } from '../panels/panels/MeteorShowersPanel'
import { NebulaTexturesPanel } from '../panels/panels/NebulaTexturesPanel'
import { ScriptsPanel } from '../panels/panels/ScriptsPanel'
import { LayersPanel } from '../panels/panels/LayersPanel'
import { ObservingPanel } from '../panels/panels/ObservingPanel'
import { SearchPanel } from '../panels/panels/SearchPanel'
import { ObjectPanel } from '../panels/panels/ObjectPanel'
import { SatellitesPanel } from '../panels/panels/SatellitesPanel'
import { TelescopePanel } from '../panels/panels/TelescopePanel'
import { OcularsPanel } from '../panels/panels/OcularsPanel'
import { SettingsQuickLegacyPanel } from '../panels/panels/SettingsQuickLegacyPanel'
import { SettingsPanel } from '../panels/panels/SettingsPanel'
import { ConfigFallbackPanel } from '../panels/panels/ConfigFallbackPanel'
import { SkyCultureSectionHeader, SkyCultureMetaItem, SkyCultureLabelSettingCard, SkyCultureFilterPicker } from '../panels/skyculture/SkyCultureViewParts'
import { SatelliteGroupSelector } from '../panels/satellite/SatelliteGroupSelector'
import {
  ImageDecodeSize, HeliocentricPositionOptions, ConstellationNavigationItem, PluginFeatureRoute,
  NebulaTextureItem, NebulaTextureStatus, NebulaTextureRefreshResponse, SkyCultureMakerArtworkAnchor, SkyCultureMakerArtwork, SkyCultureMakerConstellation,
  SkyCultureMakerDraft, SkyCultureMakerIssue,
  HeliocentricOrbit, ConfigurationOption, SkyCultureVisualColors, CelestialPositionOptions,
  CelestialPositionCategory, PhenomenaOptions, PhenomenaStartOption, EphemerisOptions, RtsCalendarOptions, EclipseOptions,
  LayerPresetState, MARKING_LAYER_ACTION_IDS, CONTENT_LAYER_ACTION_IDS, AstroCsvExport, CELESTIAL_POSITION_CATEGORIES, HELIOCENTRIC_PLANET_ORBITS,
  HELIOCENTRIC_DISTANCE_GUIDES, PHENOMENA_START_OPTIONS,
  GyroGuideProjection, SkyUiObstacle, BookmarkItem,
  BookmarkRaw, BookmarksResponse, BOOKMARK_STORE, SEARCH_HISTORY_STORE, OBSERVING_STORE, LOCATION_STORE, QUICK_PANEL_STORE, INFO_WINDOW_STORE, NIGHT_MODE_STORE, ObserverLocationRecord, OFFLINE_APPGALLERY_BUILD,
  OcularsData, OcularsResponse, PointerCoordinatesData, PointerCoordinatesResponse,
  EquationOfTimeData, ArchaeoLinesData, ArchaeoPlanetOption, SatellitesData, SatelliteListItem,
  SatelliteSource, SatelliteUpdateSettings, SatelliteSourcesResponse, CatalogHealthEntry,
  MeteorShowersData, LogResponse,
  ScreenshotResponse, SpokenTextResponse, RecordCmd,
  RecordingEntry, RecordingsResponse, RecordingDetailResponse, ScriptCaption,
  CommandCatalogEntry, ExportConfigResponse
} from './MainWindowModels'

// Sky-texture status banner. Its visibility is driven purely by the live
// deep-sky texture state reported by getDeepSkyImageStatus: pending>0 or a
// "loading" status shows "N 项待完成", an error status shows a retry action,
// and a ready view hides it immediately. It is never retracted on a timer while
// textures are still loading. A view that keeps reporting pending textures far
// beyond any plausible load is escalated to an actionable retry state instead of
// a silent hide, so the note can never stick forever without an affordance.

// 使域 store 能在不 import NAPI 的前提下调用桥；行为与直接调用宿主方法完全一致
// （callNativeWhenReady 仍走宿主的录制记录，默认重试参数 200ms × 60 显式传入）。
// 用具名 class 实现接口，避免 ArkTS 匿名对象字面量越界；先例 state/TimeWheelController.ets。
class HostCommandPort implements CommandPort {
  private readonly requestFn: (name: string, payload: string) => StellariumBridgeResponse
  private readonly whenReadyFn: (name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, attempt?: number, intervalMs?: number, maxAttempts?: number) => void
  private readonly interactiveFn: (name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void) => void
  private readonly longRunningFn: (name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, onProgress?: (r: StellariumBridgeResponse) => void, maxAttempts?: number, isCancelled?: () => boolean) => void
  private readonly fireFn: (name: string, payload: string) => void

  constructor(
    requestFn: (name: string, payload: string) => StellariumBridgeResponse,
    whenReadyFn: (name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, attempt?: number, intervalMs?: number, maxAttempts?: number) => void,
    interactiveFn: (name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void) => void,
    longRunningFn: (name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, onProgress?: (r: StellariumBridgeResponse) => void, maxAttempts?: number, isCancelled?: () => boolean) => void,
    fireFn: (name: string, payload: string) => void
  ) {
    this.requestFn = requestFn
    this.whenReadyFn = whenReadyFn
    this.interactiveFn = interactiveFn
    this.longRunningFn = longRunningFn
    this.fireFn = fireFn
  }

  request(name: string, payload: string = ''): StellariumBridgeResponse {
    return this.requestFn(name, payload)
  }

  requestWhenReady(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, attempt?: number, intervalMs?: number, maxAttempts?: number): void {
    this.whenReadyFn(name, payload, onOk, onFailure, attempt, intervalMs, maxAttempts)
  }

  requestInteractive(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void): void {
    this.interactiveFn(name, payload, onOk, onFailure)
  }

  requestLongRunning(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, onProgress?: (r: StellariumBridgeResponse) => void, maxAttempts?: number, isCancelled?: () => boolean): void {
    this.longRunningFn(name, payload, onOk, onFailure, onProgress, maxAttempts, isCancelled)
  }

  fire(name: string, payload: string = ''): void {
    this.fireFn(name, payload)
  }
}

// 避免 ArkTS 匿名对象字面量越界；先例 HostCommandPort。
class HostMediaPort implements MediaPort {
  // 宿主 UI 上下文工厂经 configure 惰性注入（适配器在字段初始化时构造，此时 getUIContext 尚不可用）。
  private contextFactory: (() => common.UIAbilityContext) | null = null

  configure(contextFactory: () => common.UIAbilityContext): void {
    this.contextFactory = contextFactory
  }

  fileExists(path: string): boolean {
    return fileIo.accessSync(path)
  }

  openReadOnlyFile(path: string, label: string): number {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
    hilog.info(0x0000, 'StellariumArkUI',
      '[detail-media] create image source kind=%{public}s path=%{public}s fd=%{public}s',
      label, path, file.fd.toString())
    return file.fd
  }

  closeFile(fd: number, label: string): void {
    try {
      fileIo.closeSync(fd)
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[detail-media] file close failed kind=%{public}s error=%{public}s',
        label, JSON.stringify(err))
    }
  }

  createImageSource(fd: number, label: string): image.ImageSource {
    return image.createImageSource(fd)
  }

  createPixelMap(source: image.ImageSource, label: string, desiredSize?: ImageDecodeSize): Promise<image.PixelMap> {
    const pixelMapPromise = label === 'model'
      ? (desiredSize === undefined
        ? source.createPixelMapUsingAllocator({
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredDynamicRange: image.DecodingDynamicRange.SDR
        }, image.AllocatorType.SHARE_MEMORY)
        : source.createPixelMapUsingAllocator({
          desiredSize: desiredSize,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredDynamicRange: image.DecodingDynamicRange.SDR
        }, image.AllocatorType.SHARE_MEMORY))
      : (desiredSize === undefined
        ? source.createPixelMap()
        : source.createPixelMap({ desiredSize: desiredSize }))
    if (label === 'model') {
      return pixelMapPromise.then((pixelMap: image.PixelMap) => {
        hilog.info(0x0000, 'StellariumArkUI',
          '[detail-media] decode promise settled kind=%{public}s bytes=%{public}s',
          label, pixelMap.getPixelBytesNumber().toString())
        return pixelMap
      })
    }
    return pixelMapPromise
  }

  releaseImageSource(source: image.ImageSource, label: string): void {
    source.release().catch((err: Error) => {
      hilog.warn(0x0000, 'StellariumArkUI', '[detail-media] image source release failed kind=%{public}s error=%{public}s',
        label, JSON.stringify(err))
    })
  }

  releasePixelMap(pixelMap: image.PixelMap | undefined, label: string): void {
    if (pixelMap === undefined) {
      return
    }
    pixelMap.release().then(() => {
      hilog.info(0x0000, 'StellariumArkUI', '[detail-media] released pixel map kind=%{public}s', label)
    }).catch((err: Error) => {
      hilog.warn(0x0000, 'StellariumArkUI', '[detail-media] pixel map release failed kind=%{public}s error=%{public}s',
        label, JSON.stringify(err))
    })
  }

  saveFileAs(sourcePath: string, fileName: string, suffixLabel: string, onDone: (result: MediaSaveResult) => void): void {
    const factory = this.contextFactory
    if (factory === null) {
      onDone(MediaSaveResult.Failed)
      return
    }
    const run = async (): Promise<void> => {
      try {
        const context = factory()
        const saveOptions = new picker.DocumentSaveOptions()
        saveOptions.newFileNames = [fileName]
        saveOptions.fileSuffixChoices = [suffixLabel]
        const selectedUris = await new picker.DocumentViewPicker(context).save(saveOptions)
        if (selectedUris.length === 0 || selectedUris[0].length === 0) {
          onDone(MediaSaveResult.Cancelled)
          return
        }
        await fileIo.copy(fileUri.getUriFromPath(sourcePath), selectedUris[0])
        onDone(MediaSaveResult.Saved)
      } catch (error) {
        hilog.error(0x0000, 'StellariumArkUI', 'Export file failed: %{public}s', String(error))
        onDone(MediaSaveResult.Failed)
      }
    }
    void run()
  }

  saveTextFileAs(text: string, fileName: string, suffixLabel: string, onDone: (result: MediaSaveResult) => void): void {
    const factory = this.contextFactory
    if (factory === null) {
      onDone(MediaSaveResult.Failed)
      return
    }
    const run = async (): Promise<void> => {
      try {
        const context = factory()
        const saveOptions = new picker.DocumentSaveOptions()
        saveOptions.newFileNames = [fileName]
        saveOptions.fileSuffixChoices = [suffixLabel]
        const selectedUris = await new picker.DocumentViewPicker(context).save(saveOptions)
        if (selectedUris.length === 0 || selectedUris[0].length === 0) {
          onDone(MediaSaveResult.Cancelled)
          return
        }
        const scratchPath = context.cacheDir + '/' + fileName
        const file = fileIo.openSync(scratchPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        const encoder = new util.TextEncoder('utf-8')
        const bytes = encoder.encodeInto(text)
        fileIo.writeSync(file.fd, bytes.buffer)
        fileIo.closeSync(file)
        await fileIo.copy(fileUri.getUriFromPath(scratchPath), selectedUris[0])
        try { fileIo.unlinkSync(scratchPath) } catch (error) {}
        onDone(MediaSaveResult.Saved)
      } catch (error) {
        hilog.error(0x0000, 'StellariumArkUI', 'Export text file failed: %{public}s', String(error))
        onDone(MediaSaveResult.Failed)
      }
    }
    void run()
  }

  deleteFile(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (error) {
    }
  }

  pickDocumentToDir(dirName: string, fileSuffixFilters: string[], fallbackFileName: string): Promise<MediaImportResult> {
    const factory = this.contextFactory
    if (factory === null) {
      const missing: MediaImportResult = { cancelled: true, path: '' }
      return Promise.resolve(missing)
    }
    const run = async (): Promise<MediaImportResult> => {
      const context = factory()
      const options = new picker.DocumentSelectOptions()
      options.fileSuffixFilters = fileSuffixFilters
      options.maxSelectNumber = 1
      const selectedUris = await new picker.DocumentViewPicker(context).select(options)
      if (selectedUris.length === 0 || selectedUris[0].length === 0) {
        const cancelled: MediaImportResult = { cancelled: true, path: '' }
        return cancelled
      }
      const importDir = context.filesDir + '/' + dirName
      fileIo.mkdirSync(importDir, true)
      const sourceName = selectedUris[0].substring(selectedUris[0].lastIndexOf('/') + 1).replace(/[^A-Za-z0-9._-]/g, '_')
      const sourcePath = importDir + '/' + (sourceName.length > 0 ? sourceName : fallbackFileName)
      await fileIo.copy(selectedUris[0], fileUri.getUriFromPath(sourcePath))
      const imported: MediaImportResult = { cancelled: false, path: sourcePath }
      return imported
    }
    return run()
  }

  // 后缀过滤、单文件、源名清洗 `[^A-Za-z0-9._-]` → `_`、importDir 落盘；最终名由 buildFileName 提供）。
  pickDocumentToDirNamed(dirName: string, fileSuffixFilters: string[], buildFileName: (sourceName: string) => string): Promise<MediaImportResult> {
    const factory = this.contextFactory
    if (factory === null) {
      const missing: MediaImportResult = { cancelled: true, path: '' }
      return Promise.resolve(missing)
    }
    const run = async (): Promise<MediaImportResult> => {
      const context = factory()
      const options = new picker.DocumentSelectOptions()
      options.fileSuffixFilters = fileSuffixFilters
      options.maxSelectNumber = 1
      const selectedUris = await new picker.DocumentViewPicker(context).select(options)
      if (selectedUris.length === 0 || selectedUris[0].length === 0) {
        const cancelled: MediaImportResult = { cancelled: true, path: '' }
        return cancelled
      }
      const importDir = context.filesDir + '/' + dirName
      fileIo.mkdirSync(importDir, true)
      const sourceName = selectedUris[0].substring(selectedUris[0].lastIndexOf('/') + 1).replace(/[^A-Za-z0-9._-]/g, '_')
      const sourcePath = importDir + '/' + buildFileName(sourceName)
      await fileIo.copy(selectedUris[0], fileUri.getUriFromPath(sourcePath))
      const imported: MediaImportResult = { cancelled: false, path: sourcePath }
      return imported
    }
    return run()
  }

  importScriptDocument(): Promise<MediaImportResult> {
    const factory = this.contextFactory
    if (factory === null) {
      const missing: MediaImportResult = { cancelled: true, path: '' }
      return Promise.resolve(missing)
    }
    const run = async (): Promise<MediaImportResult> => {
      const context = factory()
      const options = new picker.DocumentSelectOptions()
      options.fileSuffixFilters = ['Stellarium 脚本|.ssc']
      options.maxSelectNumber = 1
      const selectedUris = await new picker.DocumentViewPicker(context).select(options)
      if (selectedUris.length === 0 || selectedUris[0].length === 0) {
        const cancelledResult: MediaImportResult = { cancelled: true, path: '' }
        return cancelledResult
      }
      const scriptDir = context.filesDir + '/stellarium_userdir/scripts'
      fileIo.mkdirSync(scriptDir, true)
      const baseName = HostMediaPort.scriptImportFileName(selectedUris[0])
      let fileName = baseName
      let destinationPath = scriptDir + '/' + fileName
      if (fileIo.accessSync(destinationPath)) {
        fileName = baseName.replace(/\.ssc$/i, '') + '-' + Date.now().toString() + '.ssc'
        destinationPath = scriptDir + '/' + fileName
      }
      await fileIo.copy(selectedUris[0], fileUri.getUriFromPath(destinationPath))
      const imported: MediaImportResult = { cancelled: false, path: destinationPath }
      return imported
    }
    return run()
  }

  private static scriptImportFileName(uri: string): string {
    let name = uri.substring(uri.lastIndexOf('/') + 1)
    const queryIndex = name.indexOf('?')
    if (queryIndex >= 0) name = name.substring(0, queryIndex)
    try {
      name = decodeURIComponent(name)
    } catch (_error) {
    }
    name = name.trim().replace(/[\\/:*?"<>|\u0000-\u001F]/g, '_')
    if (name.length === 0 || !name.toLowerCase().endsWith('.ssc')) {
      name = 'imported-' + Date.now().toString() + '.ssc'
    }
    if (name.length > 120) {
      name = name.substring(0, 116) + '.ssc'
    }
    return name
  }

  importLandscapeDocument(): Promise<MediaImportResult> {
    const factory = this.contextFactory
    if (factory === null) {
      const missing: MediaImportResult = { cancelled: true, path: '' }
      return Promise.resolve(missing)
    }
    const run = async (): Promise<MediaImportResult> => {
      const context = factory()
      const options = new picker.DocumentSelectOptions()
      options.fileSuffixFilters = ['Stellarium 地景 ZIP|.zip']
      options.maxSelectNumber = 1
      const selectedUris = await new picker.DocumentViewPicker(context).select(options)
      if (selectedUris.length === 0 || selectedUris[0].length === 0) {
        const cancelled: MediaImportResult = { cancelled: true, path: '' }
        return cancelled
      }
      const importDir = context.filesDir + '/stellarium_userdir/landscape-imports'
      fileIo.mkdirSync(importDir, true)
      const baseName = HostMediaPort.landscapeImportFileName(selectedUris[0])
      let fileName = baseName
      let destinationPath = importDir + '/' + fileName
      if (fileIo.accessSync(destinationPath)) {
        fileName = baseName.replace(/\.zip$/i, '') + '-' + Date.now().toString() + '.zip'
        destinationPath = importDir + '/' + fileName
      }
      await fileIo.copy(selectedUris[0], fileUri.getUriFromPath(destinationPath))
      const imported: MediaImportResult = { cancelled: false, path: destinationPath }
      return imported
    }
    return run()
  }

  private static landscapeImportFileName(uri: string): string {
    let name = uri.substring(uri.lastIndexOf('/') + 1)
    const queryIndex = name.indexOf('?')
    if (queryIndex >= 0) name = name.substring(0, queryIndex)
    try { name = decodeURIComponent(name) } catch (_error) {}
    name = name.trim().replace(/[\\/:*?"<>|\u0000-\u001F]/g, '_')
    if (name.length === 0 || !name.toLowerCase().endsWith('.zip')) name = 'imported-landscape-' + Date.now().toString() + '.zip'
    if (name.length > 120) name = name.substring(0, 116) + '.zip'
    return name
  }

  // ── 对象模型渲染：worker 光栅化结果的像素图创建与 PNG 回退读回。 ──
  createPixelMapFromRgba(pixels: ArrayBuffer, width: number, height: number, label: string): Promise<image.PixelMap> {
    return image.createPixelMap(pixels, {
      size: { width: width, height: height },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.UNPREMUL,
      editable: false
    }).then((pixelMap: image.PixelMap) => {
      hilog.info(0x0000, 'StellariumArkUI',
        '[detail-model] render pixel map created kind=%{public}s bytes=%{public}s',
        label, pixelMap.getPixelBytesNumber().toString())
      return pixelMap
    })
  }

  readPixelMapPixels(pixelMap: image.PixelMap, buffer: ArrayBuffer, label: string): void {
    try {
      pixelMap.readPixelsToBufferSync(buffer)
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[detail-model] pixel readback failed kind=%{public}s error=%{public}s',
        label, JSON.stringify(err))
      throw err as Error
    }
  }

  // store/控制器不 import fileIo）。尺寸不符或 IO 失败抛 Error，语义与原地一致。
  readRawSidecar(path: string, expectedBytes: number, label: string): ArrayBuffer {
    let file: fileIo.File | undefined = undefined
    try {
      const pixels = new ArrayBuffer(expectedBytes)
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const bytesRead = fileIo.readSync(file.fd, pixels)
      fileIo.closeSync(file)
      file = undefined
      if (bytesRead !== expectedBytes) {
        throw new Error(label + ' has unexpected size: ' + bytesRead.toString())
      }
      return pixels
    } catch (err) {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file)
        } catch (_closeErr) { }
      }
      throw err as Error
    }
  }

  // ── 屏幕录制：NAPI 细节收在本具名适配器，控制器只依赖端口。 ──
  private screenCapture?: media.AVScreenCaptureRecorder
  private screenCaptureFile?: fileIo.File

  screenVideoDir(): string {
    const factory = this.contextFactory
    if (factory === null) {
      return ''
    }
    return factory().filesDir + '/recordings/videos'
  }

  makeDir(path: string): void {
    // 目标目录已存在时 fileIo.mkdirSync(path, true) 仍会抛 EEXIST("File exists")，
    // 未捕获会中断整个屏幕录制启动（表现为“没有生成有效视频”）。建目录只需 best-effort。
    try { fileIo.mkdirSync(path, true) } catch (error) {
      hilog.warn(0x0000, 'StellariumArkUI', 'makeDir failed path=%{public}s err=%{public}s', path, String(error))
    }
  }

  fileSize(path: string): number {
    try {
      return fileIo.statSync(path).size
    } catch (error) {
      return 0
    }
  }

  hasActiveScreenCapture(): boolean {
    return this.screenCapture !== undefined
  }

  private closeScreenCaptureFile(): void {
    if (this.screenCaptureFile !== undefined) {
      try { fileIo.closeSync(this.screenCaptureFile.fd) } catch (error) {}
      this.screenCaptureFile = undefined
    }
  }

  async beginScreenCapture(filePath: string, onState: (state: ScreenCaptureState) => void, onError: (message: string) => void): Promise<void> {
    this.screenCaptureFile = fileIo.openSync(filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    const displayInfo = display.getDefaultDisplaySync()
    const frameWidth = Math.max(64, Math.floor(displayInfo.width / 64) * 64)
    const frameHeight = Math.max(2, Math.floor(displayInfo.height / 2) * 2)
    const recorder = await media.createAVScreenCaptureRecorder()
    this.screenCapture = recorder
    recorder.on('stateChange', (state: media.AVScreenCaptureStateCode) => {
      if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STARTED) {
        onState(ScreenCaptureState.Started)
      } else if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_CANCELED) {
        onState(ScreenCaptureState.Canceled)
      } else if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STOPPED_BY_USER) {
        onState(ScreenCaptureState.StoppedByUser)
      } else if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_INTERRUPTED_BY_OTHER ||
        state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STOPPED_BY_CALL ||
        state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STOPPED_BY_USER_SWITCHES) {
        onState(ScreenCaptureState.Interrupted)
      }
    })
    recorder.on('error', (error) => {
      hilog.error(0x0000, 'StellariumArkUI', 'Screen capture error: %{public}s', String(error))
      onError('录屏失败')
    })
    const file = this.screenCaptureFile
    const config: media.AVScreenCaptureRecordConfig = {
      fd: file.fd,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      videoBitrate: 10000000,
      displayId: displayInfo.id,
      fillMode: media.AVScreenCaptureFillMode.PRESERVE_ASPECT_RATIO,
      preset: media.AVScreenCaptureRecordPreset.SCREEN_RECORD_PRESET_H264_AAC_MP4
    }
    await recorder.init(config)
    await recorder.startRecording()
  }

  async stopScreenCapture(): Promise<void> {
    const recorder = this.screenCapture
    this.screenCapture = undefined
    if (recorder !== undefined) {
      try { recorder.off('stateChange') } catch (error) {}
      try { recorder.off('error') } catch (error) {}
      try { await recorder.stopRecording() } catch (error) {}
      try { await recorder.release() } catch (error) {}
    }
    this.closeScreenCaptureFile()
  }

  async releaseScreenCapture(): Promise<void> {
    const recorder = this.screenCapture
    this.screenCapture = undefined
    if (recorder !== undefined) {
      try { recorder.off('stateChange') } catch (error) {}
      try { recorder.off('error') } catch (error) {}
      try { await recorder.release() } catch (error) {}
    }
    this.closeScreenCaptureFile()
  }

  async saveVideoToGallery(path: string): Promise<boolean> {
    const factory = this.contextFactory
    if (factory === null) {
      return false
    }
    try {
      const context = factory()
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      const request = photoAccessHelper.MediaAssetChangeRequest.createVideoAssetRequest(
        context, fileUri.getUriFromPath(path))
      await helper.applyChanges(request)
      return true
    } catch (error) {
      hilog.error(0x0000, 'StellariumArkUI', 'Save video to gallery failed: %{public}s', String(error))
      return false
    }
  }
}

class HostPlatformPort implements PlatformPort {
  private contextFactory: (() => common.UIAbilityContext) | null = null
  private expandedFactory: (() => boolean) | null = null

  configure(contextFactory: () => common.UIAbilityContext, expandedFactory: () => boolean): void {
    this.contextFactory = contextFactory
    this.expandedFactory = expandedFactory
  }

  async writeClipboardText(text: string): Promise<boolean> {
    const result = await writeClipboardText(text)
    return result.ok
  }

  shareFile(
    path: string,
    utdType: string,
    title: string,
    description: string,
    anchorId: string,
    expanded: boolean,
    onDone: (ok: boolean) => void,
  ): void {
    const factory = this.contextFactory
    if (factory === null) {
      onDone(false)
      return
    }
    const run = async (): Promise<void> => {
      try {
        const context = factory()
        const data = new systemShare.SharedData({
          utd: utdType,
          uri: fileUri.getUriFromPath(path),
          title: title,
          description: description
        })
        const controller = new systemShare.ShareController(data)
        const options: systemShare.ShareControllerOptions = expanded ? { anchor: anchorId } : {}
        await controller.show(context, options)
        onDone(true)
      } catch (error) {
        hilog.error(0x0000, 'StellariumArkUI', 'Share failed: %{public}s', String(error))
        onDone(false)
      }
    }
    void run()
  }

  speak(text: string): void {
    // 基础 SDK 无 @kit.CoreSpeechKit；此处保留槽位，暂不发声（朗读文本由 SpeechService 生成后显示）。
  }
}

// 宿主 → SensorPort 的具名适配器。转发 sensor.* 查询/订阅/退订。
class HostSensorPort implements SensorPort {
  // 控制器只给 label（不 import sensor 命名空间），适配器在此映射到 SensorId。
  private static sensorIdForLabel(label: string): sensor.SensorId {
    if (label === 'gravity') return sensor.SensorId.GRAVITY
    if (label === 'magnetic-field') return sensor.SensorId.MAGNETIC_FIELD
    if (label === 'orientation-fallback') return sensor.SensorId.ORIENTATION
    return sensor.SensorId.ROTATION_VECTOR
  }

  probeSensor(label: string): SensorProbeInfo | undefined {
    const sensorType = HostSensorPort.sensorIdForLabel(label)
    try {
      const info = sensor.getSingleSensorSync(sensorType)
      hilog.info(0x0000, 'StellariumArkUI', '[gyro-probe] sensor=%{public}s supported=true name=%{public}s vendor=%{public}s',
        label, info.sensorName, info.vendorName)
      return { sensorName: info.sensorName, vendorName: info.vendorName }
    } catch (error) {
      hilog.warn(0x0000, 'StellariumArkUI', '[gyro-probe] sensor=%{public}s supported=false error=%{public}s', label, JSON.stringify(error))
      return undefined
    }
  }

  subscribeRotationVector(callback: (data: sensor.RotationVectorResponse) => void, intervalNs: number): void {
    sensor.on(sensor.SensorId.ROTATION_VECTOR, callback, { interval: intervalNs })
  }

  unsubscribeRotationVector(callback: (data: sensor.RotationVectorResponse) => void): void {
    sensor.off(sensor.SensorId.ROTATION_VECTOR, callback)
  }

  subscribeOrientation(callback: (data: sensor.OrientationResponse) => void, intervalNs: number): void {
    sensor.on(sensor.SensorId.ORIENTATION, callback, { interval: intervalNs })
  }

  unsubscribeOrientation(callback: (data: sensor.OrientationResponse) => void): void {
    sensor.off(sensor.SensorId.ORIENTATION, callback)
  }

  subscribeGravity(callback: (data: sensor.GravityResponse) => void, intervalNs: number): void {
    sensor.on(sensor.SensorId.GRAVITY, callback, { interval: intervalNs })
  }

  unsubscribeGravity(callback: (data: sensor.GravityResponse) => void): void {
    sensor.off(sensor.SensorId.GRAVITY, callback)
  }

  subscribeMagneticField(callback: (data: sensor.MagneticFieldResponse) => void, intervalNs: number): void {
    sensor.on(sensor.SensorId.MAGNETIC_FIELD, callback, { interval: intervalNs })
  }

  unsubscribeMagneticField(callback: (data: sensor.MagneticFieldResponse) => void): void {
    sensor.off(sensor.SensorId.MAGNETIC_FIELD, callback)
  }
}

// 宿主 → LocationPort 的具名适配器。承载 abilityAccessCtrl / geoLocationManager /
// @ohos.data.preferences 三处 NAPI，使 LocationController 不 import NAPI。
// UI 上下文工厂经 configure 惰性注入（适配器在字段初始化时构造，此时 getUIContext 尚不可用）。
class HostLocationPort implements LocationPort {
  private contextFactory: (() => common.UIAbilityContext) | null = null

  configure(contextFactory: () => common.UIAbilityContext): void {
    this.contextFactory = contextFactory
  }

  private context(): common.UIAbilityContext {
    const factory = this.contextFactory
    if (factory === null) {
      throw new Error('HostLocationPort not configured')
    }
    return factory()
  }

  async requestLocationPermissions(): Promise<boolean> {
    const context = this.context()
    const atManager = abilityAccessCtrl.createAtManager()
    const permissions: Array<Permissions> = [
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION'
    ]
    const permissionResult = await atManager.requestPermissionsFromUser(context, permissions)
    return permissionResult.authResults.some((result: number) => result === 0)
  }

  async getCurrentLocation(): Promise<LocationFix> {
    const current = await geoLocationManager.getCurrentLocation({
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      scenario: geoLocationManager.LocationRequestScenario.DAILY_LIFE_SERVICE,
      maxAccuracy: 2000,
      timeoutMs: 5000
    })
    return {
      latitude: current.latitude,
      longitude: current.longitude,
      altitude: Number.isFinite(current.altitude) ? current.altitude : 0
    }
  }

  async readObserverLocation(): Promise<string> {
    try {
      const store = await preferences.getPreferences(this.context(), LOCATION_STORE)
      return (await store.get('location', '')) as string
    } catch (e) {
      return ''
    }
  }

  async writeObserverLocation(json: string): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context(), LOCATION_STORE)
      await store.put('location', json)
      await store.flush()
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'save observer location failed: %{public}s', String(e))
    }
  }
}

// 宿主 → SettingsPersistencePort 的具名适配器：承载 @ohos.data.preferences，
// 使 SettingsRepository 不 import NAPI。store 名与 key 由 SettingsRepository 定义。
class HostSettingsPort implements SettingsPersistencePort {
  private contextFactory: (() => common.UIAbilityContext) | null = null

  configure(contextFactory: () => common.UIAbilityContext): void {
    this.contextFactory = contextFactory
  }

  private context(): common.UIAbilityContext {
    const factory = this.contextFactory
    if (factory === null) {
      throw new Error('HostSettingsPort not configured')
    }
    return factory()
  }

  async read(): Promise<string | null> {
    try {
      const store = await preferences.getPreferences(this.context(), UI_SETTINGS_STORE)
      const value = await store.get(UI_SETTINGS_KEY, '')
      return typeof value === 'string' && value.length > 0 ? value : null
    } catch (error) {
      hilog.warn(0x0000, 'StellariumArkUI', '[settings] read failed')
      return null
    }
  }

  async write(json: string): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(this.context(), UI_SETTINGS_STORE)
      await store.put(UI_SETTINGS_KEY, json)
      await store.flush()
      return true
    } catch (error) {
      hilog.warn(0x0000, 'StellariumArkUI', '[settings] write failed')
      return false
    }
  }

  async clear(): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(this.context(), UI_SETTINGS_STORE)
      await store.delete(UI_SETTINGS_KEY)
      await store.flush()
      return true
    } catch (error) {
      hilog.warn(0x0000, 'StellariumArkUI', '[settings] clear failed')
      return false
    }
  }
}

@Component
export struct WindowNativeNode {
  @State private createInfo: WindowNativeNodeCreateInfo | undefined = undefined
  @Watch('onPrivacyNativeStartupAllowedChanged')
  @StorageLink('stellariumPrivacyNativeStartupAllowed')
  private privacyNativeStartupAllowed: boolean = false
  @StorageLink('stellariumScreenSafeTopPixels')
  private screenSafeTopPixels: number = 0
  @StorageLink('stellariumScreenSafeBottomPixels')
  private screenSafeBottomPixels: number = 0
  @Watch('onCliUiEventChanged')
  @StorageLink('stellariumCliUiEvent')
  private cliUiEvent: string = ''
  @Watch('onCardRouteChanged')
  @StorageLink('stellariumCardRoute')
  private cardRoute: string = ''
  // 作为 .cat「打开方式」被拉起时由 QAbility 写入；此处消费并导入（见 handleOpenCatalogUri）。
  @Watch('onOpenCatalogUriChanged')
  @StorageLink('stellariumOpenCatalogUri')
  private openCatalogUri: string = ''
  @Watch('onQtContentReadyForCatalog')
  @StorageLink('stellariumQtContentReady')
  private qtContentReadyForCatalog: boolean = false
  private pendingOpenCatalogUri: string = ''
  private privacyPageStartupStarted: boolean = false
  private lastCliUiEventId: string = ''
  @State private isExpandedLayout: boolean = false
  @State private isFoldHoverLayout: boolean = false
  @State private isFoldableDevice: boolean = false
  @State private isFoldTabletLayout: boolean = false
  @State private foldStatusValue: number = 0
  @State private foldDisplayModeValue: number = 0
  @State private foldAngleValue: number = 180
  // Some emulator and device transitions report a fold status before the first
  // usable angle sample. Keep that stale 180-degree startup value from forcing
  // a half-folded device back into the tablet shell.
  @State private hasUsableFoldAngle: boolean = false
  @State private responsiveLayoutMode: string = 'compact'
  @State private uiLayoutOverride: string = 'auto'
  @State private activePanel: string = 'object'
  // 面板可见性变化时同步"返回可消费"镜像（系统返回手势据此决定接管还是退出），见 publishBackConsumable。
  @Watch('publishBackConsumable') @State private panelVisible: boolean = false
  @State private panelNavigationDepth: number = 0
  private panelNavigationStack: string[] = []
  // 系统返回请求令牌：ApplicationRoot.onBackPress 置为 Date.now()，此处 @Watch 执行应用内返回。
  @StorageLink('stellariumRequestBack') @Watch('onRequestBack') private requestBackToken: number = 0
  private lastPanelBackAt: number = 0
  // 主界面「两次返回确认」的窗口与上一次时间戳（见 handleHomeBackConfirm）。
  private readonly HOME_BACK_CONFIRM_MS: number = 2500
  private lastHomeBackAt: number = 0
  @State private searchStore: SearchStore = new SearchStore()
  @State private objectDetailStore: ObjectDetailStore = new ObjectDetailStore()
  @State private gyroStore: GyroStore = new GyroStore()
  @State private notificationStore: NotificationStore = new NotificationStore()
  @State private surveyStore: SurveyStore = new SurveyStore()
  @State private arStore: ARStore = new ARStore()
  @State private keyboardShortcutStore: KeyboardShortcutStore = new KeyboardShortcutStore()
  @State private wutStore: WutStore = new WutStore()
  @State private astroStore: AstroStore = new AstroStore()
  @State private objectMediaStore: ObjectMediaStore = new ObjectMediaStore()
  @State private tools: ToolsStore = new ToolsStore()
  private searchPanelScroller: Scroller = new Scroller()
  // / 端口适配器（宿主具名实现，aboutToAppear 里 configure 后注入服务层）。
  private hostCommandPort: HostCommandPort | null = null
  private hostMediaPort: HostMediaPort = new HostMediaPort()
  private hostPlatformPort: HostPlatformPort = new HostPlatformPort()
  private hostSensorPort: HostSensorPort = new HostSensorPort()
  // 位置域端口适配器（aboutToAppear 里 configure UI 上下文）。
  private hostLocationPort: HostLocationPort = new HostLocationPort()
  // 统一 UI 偏好持久化（Preferences 端口在 aboutToAppear 注入）。
  private hostSettingsPort: HostSettingsPort = new HostSettingsPort()
  private settingsRepository: SettingsRepository = new SettingsRepository()
  private persistedSettingsApplied: boolean = false
  // 位置域控制器（惰性构造；NAPI 经 LocationPort，跨域写经 LocationHostHooks）。
  private locationControllerImpl: LocationController | null = null
  // 启动桥服务（惰性构造，持有跨域 store 引用与宿主生命周期 hooks）。
  private startupBridgeImpl: StartupBridge | null = null
  // 传感器/陀螺仪控制器（惰性构造；注入 SensorPort/CommandPort/store 与宿主 hooks）。
  private sensorControllerImpl: SensorController | null = null
  // 通知/后台提醒控制器（惰性构造；注入 NotificationStore 与宿主 hooks）。
  private notificationControllerImpl: NotificationController | null = null
  // 巡天 / 多波段图层控制器（惰性构造；注入 SurveyStore / CommandPort 与宿主 hooks）。
  private surveyControllerImpl: SurveyController | null = null
  // AR 预研控制器（惰性构造；注入 ARStore / CommandPort 与宿主 hooks）。
  private arControllerImpl: ARController | null = null
  // 键盘快捷键控制器（惰性构造；注入 KeyboardShortcutStore / CommandPort 与宿主 hooks）。
  private keyboardShortcutControllerImpl: KeyboardShortcutController | null = null
  // 时间平滑过渡控制器（惰性构造；注入 CommandPort 与宿主 hooks）。
  private timeTransitionControllerImpl: TimeTransitionController | null = null
  // 录制/回放/录屏控制器（惰性构造；recordBuffer 属 保留字段，经 hooks 读写）。
  private recordingControllerImpl: RecordingController | null = null
  // 对象检查器三维模型渲染器（惰性构造；逐帧/草稿字段留控制器，可观测子集在 ObjectMediaStore）。
  private objectModelRendererImpl: ObjectModelRenderer | null = null
  // 天空输入控制器骨架（惰性构造；鼠标/键盘/滚轮轴/点按序列/惯性方法 + 16 个草稿字段）。
  private skyInputControllerImpl: SkyInputController | null = null
  // 详情连接线 / 详情刷新定时器控制器（惰性构造；指向线几何 @State 由宿主持有经 hooks 逐帧写入）。
  private detailConnectorControllerImpl: DetailConnectorController | null = null
  // 图层 / 视图标签控制器（惰性构造；标签 @State 与过渡量由宿主持有经 hooks 读写）。
  private layerControllerImpl: LayerController | null = null
  // SkyTexture 状态观察控制器（惰性构造；定时器自持 start/stop，状态条字段在 ToolsStore）。
  private skyTextureStatusControllerImpl: SkyTextureStatusController | null = null
  // 星云纹理控制器（惰性构造；picker/fileIo 经 MediaPort，状态在 NebulaTextureStore）。
  private nebulaTextureControllerImpl: NebulaTextureController | null = null
  // 星空文化控制器（惰性构造；选择/标签/视觉 + 时间跟随 + Art 预览；状态在 skyCulture* store）。
  private skyCultureControllerImpl: SkyCultureController | null = null
  // 星空文化制作器控制器（惰性构造；Maker 向导 CRUD + 画布触摸 + 自动保存定时器）。
  private skyCultureMakerControllerImpl: SkyCultureMakerController | null = null
  // 目镜/拼接相机/均时差/古天文线写回控制器（惰性构造；状态在 telescope/mosaic/equationOfTime/archaeo store）。
  private ocularControllerImpl: OcularController | null = null
  // LX200 望远镜编辑器/控制命令控制器（惰性构造；状态在 TelescopeStore，live-position 定时器自持）。
  private telescopeControllerImpl: TelescopeController | null = null
  // 极轴镜行为控制器（惰性构造；状态在 PolarScopeStore，polarScopeTimer 由控制器自持）。
  private polarScopeControllerImpl: PolarScopeController | null = null
  // 视图中心坐标叠层行为控制器（惰性构造；开关/坐标系/历元在 OverlayStore，viewCoordinateTimer 自持）。
  private viewCoordinateControllerImpl: ViewCoordinateController | null = null
  // 卫星行为控制器（惰性构造；状态在 SatelliteStore，publish* 保留项经 hooks 注入）。
  private satelliteControllerImpl: SatelliteController | null = null
  // 天文计算行为控制器（惰性构造；状态在 astro/ephemeris/wut store，picker/animateTo/Scroller
  // 与保留项 publishAstroPanelState/applySelectedObject 经 hooks 注入）。
  private astroCalcControllerImpl: AstroCalcController | null = null
  // 插件功能行为控制器（惰性构造；状态在 PluginStore，跨域路由经 hooks 注入）。
  private pluginFeatureControllerImpl: PluginFeatureController | null = null
  // 对象检查器媒体控制器（惰性构造；媒体渲染器经 hooks 持有，侧车读取上移 MediaPort）。
  private objectInspectorMediaControllerImpl: ObjectInspectorMediaController | null = null
  // 脚本录制回放 UI 控制器（惰性构造；状态在 ScriptStore/ToolsStore，状态轮询定时器自持）。
  private scriptPlaybackControllerImpl: ScriptPlaybackController | null = null
  // 交互导览行为控制器（惰性构造；状态在 GuideStore，播放器与 250ms tick 定时器自持）。
  private guideControllerImpl: GuideController | null = null
  // 设置配置回读控制器（惰性构造；状态写 TimeSettingsStore 本域字段，跨域字段经 hooks 具名 setter）。
  private settingsControllerImpl: SettingsController | null = null
  // 时间操作控制器（惰性构造；状态在 time/timeSettings/deltaT store，时间面板定时器自持）。
  private timeControllerImpl: TimeController | null = null
  private searchControllerImpl: SearchController | null = null
  private selfTestControllerImpl: SelfTestController | null = null
  // 陀螺仪观测时，若已选目标落在视场外，在安全边缘给出方向提示。
  // 坐标本身不参与渲染，只有这三个 @State 会驱动提示箭头刷新。
  // The compact phone quick controls are tapped through a transparent layer
  // above Qt, so keep their pressed appearance in explicit ArkUI state.
  @State private compactQuickPressed: string = ''
  // 富化的天体详情（独立浮动窗口，不切换当前菜单；默认收起，可展开）
  @State private infoWindowStore: InfoWindowStore = new InfoWindowStore()
  @State private fullInspectorRequested: boolean = false
  @State private compactPanelSnapRatio: number = 0.6
  @State private compactPanelDragOffsetY: number = 0
  // 平板/展开布局的快捷面板同样可上拉展开，底部与 Dock 对齐。
  @State private expandedPanelDragOffsetY: number = 0
  // 时间面板“时间轮 + 倒带/实时”两块的自然高度（vp），用于平板紧凑高度。
  @State private timeSpeedBlockHeight: number = 0
  private lastInfoWinCloseMs: number = 0
  private dismissedObjectName: string = ''
  @State private panelContentKey: number = 0
  // 文本输入聚焦标志：聚焦时天空键盘处理器让位给输入法（搜索/位置输入）。
  @State private keyboardTextInputFocused: boolean = false
  private languageSwitchTimer: number = -1
  @State private cardOffsetX: number = 0
  @State private cardOffsetY: number = 0
  @State private objectDetailConnectorX: number = 0
  @State private objectDetailConnectorY: number = 0
  @State private objectDetailConnectorLength: number = 0
  @State private objectDetailConnectorAngle: number = 0
  @State private objectDetailConnectorEndX: number = 0
  @State private objectDetailConnectorEndY: number = 0
  @State private objectDetailConnectorTargetX: number = 0
  @State private objectDetailConnectorTargetY: number = 0
  @State private objectDetailConnectorTargetOnScreen: boolean = false
  @State private objectDetailContentOpacity: number = 1
  @State private objectDetailContentTranslateX: number = 0
  private objectCardDragging: boolean = false
  private objectDetailTabTransitionId: number = 0
  private objectCardDragStartX: number = 0
  private objectCardDragStartY: number = 0
  private objectCardDragStartOffsetX: number = 0
  private objectCardDragStartOffsetY: number = 0
  // objectInspectorModel* 的 22 个逐帧/草稿字段（纹理三量 + 环纹理三量、旋转/缩放采样、
  // 刻意不入被观察 store（逐帧写入入 store 会造成重渲染风暴）。
  private objectDetailScroller: Scroller = new Scroller()
  // 程序化音乐默认开（打开应用即播放），可静音并持久化。
  @State private audioStore: AudioStore = new AudioStore()
  private fpsTimer: number = 0
  private stateRefreshTimer: number = -1
  private stateRefreshRequestPending: boolean = false
  private stateRefreshQueued: boolean = false
  // getState 的请求序号：作为 payload 附在命令后，使桥的 consume-on-read 缓存键
  // 每次刷新唯一。被放弃的轮询链留下的旧快照因此不会被后续刷新消费。
  private stateRefreshSerial: number = 0
  /** 主界面 Dock 右上的常驻时钟文本（HH:mm），面板未打开时显示。 */
  @State private dockClockText: string = ''
  /** Dock 时钟的独立轻量刷新定时器（1s），不并入时间面板 125ms 高频刷新。 */
  private dockClockTimer: number = 0
  /** 引擎（Qt 核心）已确认可响应命令；此前的轮询/回读全部跳过，避免同步桥调用堵塞 UI 线程。 */
  private engineReady: boolean = false
  /** 时间域状态（速度档位索引/速率文本/恒星时/手工时间选择器）；换挡行为在 capability/TimeController.ets。 */
  @State private timeStore: TimeStore = new TimeStore()
  // 原生命令在下一渲染帧才生效。此窗口内忽略轮询到的旧速率，避免按钮
  // 刚显示“-2x”又被上一帧的“-10x”短暂盖回去而产生闪烁。
  /** 时间轴相对真实当前时刻的偏移秒数（0=此刻，负=过去，正=未来）*/
  // 时间轴的中心 JD。它不是系统时间的固定快照：模拟时间接近边界时会
  // 重新定锚到当前模拟时间，避免快进后游标永远卡在两端。
  // 时间转轴：顶部选择要调整的字段，底部同一条刻度轴只控制该字段。
  @State private timeWheelStore: TimeWheelStore = new TimeWheelStore()
  // JD/MJD are edited explicitly, so the periodic native time poll does not
  // replace a partially typed number while the user is still entering it.
  @State private julianStore: JulianDateStore = new JulianDateStore()
  @State private languageStore: LanguageStore = new LanguageStore()
  @StorageLink('i18nLang') private i18nLang: string = I18n.systemLanguage()
  @State private bridgeSyncStarted: boolean = false
  @State private nightModeStore: NightModeStore = new NightModeStore()
  // 宿主直属 UI 的主题槽位缓存。WithTheme 只作用于子树，宿主的 onWillApplyTheme 收到的是祖先主题，
  // 因此宿主按 nightMode 直接取与子树同源的槽位。
  private hostSlotsNight: boolean | undefined = undefined
  private hostSlotsCache: ThemeSlots = DEFAULT_SLOTS
  @State private locationText: string = '--'
  @State private coordinateText: string = '--'
  @State private altitudeText: string = '--'
  // 位置选择器状态簇（picker 坐标/名称/状态、层级选择、地图渲染尺寸、时区、选点方式 + 层级翻译纯计算）
  // 随 locationPickerPanel 组件化迁移到 LocationPickerStore（j）。
  @State private locationPickerStore: LocationPickerStore = new LocationPickerStore()
  // 观测/会话工具区块状态（观测星球切换、指星笔、手表陀螺仪模拟、今晚天象）—— s 组件化。
  @State private sessionToolStore: SessionToolStore = new SessionToolStore()
  @State private watchLastSend: number = 0
  @State private canUseDistributed: boolean = false
  @State private locationStore: LocationStore = new LocationStore()
  @State private layerStore: LayerStore = new LayerStore()
  @State private layerViewStore: LayerViewStore = new LayerViewStore()
  @State private fovText: string = '--'
  @State private trackingText: string = 'Off'
  @State private trackingRequestPending: boolean = false
  private trackingRequestSerial: number = 0
  private trackingStateIgnoreUntilMs: number = 0
  @State private skyWidth: number = 1
  @State private skyHeight: number = 1
  @State private panelWidth: number = 336
  // 离屏幕边框的安全留白(vp)：约 0.7cm，避免 UI 贴边
  private readonly EDGE_MARGIN: number = 44
  @State private obsListStore: ObservingListStore = new ObservingListStore()
  @State private isLoading: boolean = true
  @State private splashGone: boolean = false
  private startupViewportCheckedAt: number = 0
  @State private viewTab: number = 0  // View面板子标签索引
  @State private configTab: number = 0  // 统一设置面板子标签索引；默认显示主设置
  @State private timeSettingsStore: TimeSettingsStore = new TimeSettingsStore()
  @State private ephemerisStore: EphemerisStore = new EphemerisStore()
  @State private timeSettingsPending: boolean = false
  @State private deltaTStore: DeltaTStore = new DeltaTStore()
  @State private navigationStore: NavigationSettingsStore = new NavigationSettingsStore()
  private astroPanelScroller: Scroller = new Scroller()
  // 说明：竖直限位默认开（天顶↔天底间拖动不翻转）；viewLock 开启后仍可自由拖动、松手记录位置；
  // flatHorizon 限制最大视场角、保持地平线平直。
  @State private viewSettingsStore: ViewSettingsStore = new ViewSettingsStore()
  // 大气观测辅助（atmoPressure / atmoTemperature / atmoExtinction / refractionOn，共 4 字段）
  @State private atmosphereStore: AtmosphereStore = new AtmosphereStore()
  // 星文化制作器向导状态（m，见 state/SkyCultureMakerStore.ets）
  @State private skyCultureMakerStore: SkyCultureMakerStore = new SkyCultureMakerStore()
  // skyCultureMakerArtworkPPath / skyCultureMakerArtworkDecodeGeneration /
  @State private skyCultureViewStore: SkyCultureViewStore = new SkyCultureViewStore()
  @State private skyCultureArtStates: Record<string, string> = {}
  // 控制器经 hooks 读写（+ 双重约束）。
  // 星空文化面板设置状态簇（见 state/SkyCultureSettingsStore.ets）
  @State private skyCultureSettingsStore: SkyCultureSettingsStore = new SkyCultureSettingsStore()
  private skyCultureMapContextSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private skyCultureMapContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.skyCultureMapContextSettings)
  private skyCultureMapRenderWidth: number = 0
  private skyCultureMapRenderHeight: number = 0
  @State private polarScopeStore: PolarScopeStore = new PolarScopeStore()
  @State private pluginStore: PluginStore = new PluginStore()
  @State private nebulaTextureStore: NebulaTextureStore = new NebulaTextureStore()
  @State private navStarsStore: NavStarsStore = new NavStarsStore()
  @State private landscapeDetailOpen: boolean = false
  // 新增面板控制
  @State private planetLabels: boolean = false
  private applicationInForeground: boolean = true
  // The gyro control itself becomes a live compass while it is enabled.
  @State private currentFovText: string = '--'
  // 4 个 @State 读数由宿主持有（类逐帧保留，，「高频字段不入 store」）；
  // 时间格式化 / TimeWheel 钩子），属跨域共用，按 由宿主持有。
  @State private viewCoordinatePrimaryText: string = '--'
  @State private viewCoordinateSecondaryText: string = '--'
  @State private viewCoordinateOffsetX: number = 0
  @State private viewCoordinateOffsetY: number = 0
  /** 观测地 UTC 偏移（小时），由 getState 的 timeText-jd 差值校准，供轻量时间刷新使用 */
  private utcOffsetHours: number = 8
  @State private fovSliderValue: number = 60
  @State private currentProjection: string = 'ProjectionPerspective'
  @State private panelIdleOpacity: number = 1.0
  @State private panelIdleGlass: boolean = false
  @State private panelRouteOpacity: number = 1.0
  @State private panelRouteOffsetX: number = 0
  @State private panelPresentationOpacity: number = 1.0
  @State private panelPresentationOffsetY: number = 0
  @State private viewTabContentOpacity: number = 1.0
  @State private viewTabContentOffsetX: number = 0
  @State private configTabContentOpacity: number = 1.0
  @State private configTabContentOffsetX: number = 0
  @State private panelOffsetX: number = 0
  @State private panelOffsetY: number = 0
  private panelDataLoadTimer: number = -1
  private panelRouteDirection: number = 1
  private widePanelScroller: Scroller = new Scroller()
  private compactPanelScroller: Scroller = new Scroller()
  private scriptListScroller: Scroller = new Scroller()
  @State private bookmarkStore: BookmarkStore = new BookmarkStore()
  @State private telescopeStore: TelescopeStore = new TelescopeStore()
  @State private overlayStore: OverlayStore = new OverlayStore()
  @State private mosaicStore: MosaicStore = new MosaicStore()
  @State private equationOfTimeStore: EquationOfTimeStore = new EquationOfTimeStore()
  @State private archaeoStore: ArchaeoStore = new ArchaeoStore()
  // 卫星（Satellites）
  // SatellitesPanel 改为 @ObjectLink 订阅该 store，刷新粒度不再落在宿主整棵树上。
  // 下面两个"资源目录健康"字段与星表域共用、且不是卫星面板的入参，故仍由宿主持有。
  @State private satelliteStore: SatelliteStore = new SatelliteStore()
  // recordBuffer 与脚本播放引擎字段刻意由宿主持有，理由见 state/ScriptStore.ets 头注。
  @State private scriptStore: ScriptStore = new ScriptStore()
  // 小簇批处理（第三批）：scenery3d / catalogs / meteorShowers / commandConsole。
  // 各簇的非面板字段（scenery3dCurrentId、catalogHealthLoaded、catalogManifestPresent）由宿主持有。
  @State private sceneryStore: SceneryStore = new SceneryStore()
  @State private catalogStore: CatalogStore = new CatalogStore()
  @State private meteorStore: MeteorStore = new MeteorStore()
  @State private commandStore: CommandStore = new CommandStore()
  @State private catalogHealthLoaded: boolean = false
  @State private catalogManifestPresent: boolean = false
  // catalogHealthLoaded / catalogManifestPresent 仍由宿主持有（与卫星面板共用）。
  private satellitePanelScroller: Scroller = new Scroller()
  private satelliteGroupScroller: Scroller = new Scroller()
  // 三维地景：直接读取原版 scenery3d.ini 与语言描述文件
  @State private scenery3dCurrentId: string = ''
  @State private skyTouchFeedback: boolean = false
  @State private skyTouchX: number = 0   // 触摸点窗口坐标(px)，供反馈圈跟随手指
  @State private skyTouchY: number = 0
  @State private skyTouchFeedbackMulti: boolean = false
  @State private skyTouchX2: number = 0
  @State private skyTouchY2: number = 0
  @State private actionHint: ResourceStr = ''
  // ===== 脚本录制 / 回放（39）=====
  @State private recordBuffer: Array<RecordCmd> = []
  @State private guideStore: GuideStore = new GuideStore()
  private hintTimer: number = 0
  // 离线搜索分块扫描草稿（locSearchRequestId / locationSearchScan* / locationSearchLastPublishMs）
  private panelIdleTimer: number = -1
  private lastOverlayActivityMs: number = 0
  // 目标详情自动刷新：选中天体后每 180ms 重新拉一次坐标，让“地平坐标”随地球自转实时变化。
  // objectDetailConnectorAnimateGeometry 是宿主 @State（指向线过渡开关），控制器经 hooks 写入。
  @State private objectDetailConnectorAnimateGeometry: boolean = false
  private foregroundRefreshPaused: boolean = false
  // Structured details are loaded after a new target is drawn. Keeping this
  // timer separate from the live-value poll prevents it from delaying panning.
  private lastSafeNavigationPayload: string = ''
  private lastSafeNavigationAt: number = 0
  // 时间面板打开时，每 1s 拉一次 getState，让"时间"字段像走动的钟一样实时更新
  // （否则只在打开瞬间刷新一次，点按钮/时间流逝都不会再更新，永远显示 --）
  // （控制器自持 startPanelTimers()/stopPanelTimers()；面板路由/生命周期调用）。
  private skyCultureDetailsRequestId: number = 0
  // skyCultureDetailsRequestId 与由宿主持有的 loadSkyCultureDetails（永久登记）共用，
  // 按 单一持有者 = 宿主，控制器经 hooks 读写。
  // 控制器经 SkyInputHostHooks 读写。
  private skyTouchActive: boolean = false
  private skyDragging: boolean = false
  // （子组「可观测子集入 GyroStore、逐帧草稿留控制器」）。
  private touchStartedOnUi: boolean = false
  private skySelectionRequestSerial: number = 0
  private lastCenterKeyAt: number = 0
  private lastDockActionAt: number = 0
  private lastDockActionPanel: string = ''
  private dockTouchActive: boolean = false
  private SELFTEST: boolean = false  // 开发自检：启动即对全部开关跑一次 findAction，验证无死开关。发布前改 false。
  private foldStatusChanged = (status: display.FoldStatus): void => {
    this.foldStatusValue = status as number
    const halfFolded = this.foldStatusValue === 3 || this.foldStatusValue === 13 || this.foldStatusValue === 21 || this.foldStatusValue === 22 || this.foldStatusValue === 23
    if (halfFolded && (this.foldAngleValue >= 155 || this.foldAngleValue <= 0)) {
      this.hasUsableFoldAngle = false
    }
    this.updateResponsiveLayout('foldStatusChange')
  }
  private foldDisplayModeChanged = (mode: display.FoldDisplayMode): void => {
    this.foldDisplayModeValue = mode as number
    this.updateResponsiveLayout('foldDisplayModeChange')
  }
  private foldAngleChanged = (angles: Array<number>): void => {
    if (angles.length > 0 && Number.isFinite(angles[0])) {
      this.foldAngleValue = clamp(angles[0], 0, 180)
      this.hasUsableFoldAngle = this.foldAngleValue > 0 && this.foldAngleValue < 180
      this.updateResponsiveLayout('foldAngleChange')
    }
  }
  private handleApplicationLifecycle = (foreground: boolean): void => {
    this.applicationInForeground = foreground
    if (!foreground && this.guideStore.guideState.phase === 'observing') this.guideCtl().pausePlayer()
    this.objectModelRendererCtl().setForeground(foreground)
    if (foreground) {
      // 回前台时引擎可能已被外部（CLI/配置）改变；引擎就绪后立即同步一次 UI store。
      if (this.engineReady) this.refreshStateNow()
      if (this.foregroundRefreshPaused) {
        this.foregroundRefreshPaused = false
        if (this.activePanel === 'time' && this.panelVisible) {
          this.timeStore.loadTimeExtras()
          this.timeCtl().startPanelTimers()
        }
        if (this.objectDetailStore.selectedStatus === 'Selected' && ((this.activePanel === 'object' && this.panelVisible) || this.infoWindowStore.infoWinVisible)) {
          this.detailConnectorCtl().startDetailAutoRefresh()
        }
      }
      if (this.audioStore.musicEnabled) {
        void AudioEngine.getInstance().start()
      }
      this.gyroCtl().resumeAfterForeground()
      this.viewCoordinateCtl().syncViewCoordinateTimer()
      this.syncDockClockTimer()
      this.skyCultureCtl().syncSkyCultureTimeFollowTimer()
      this.polarScopeCtl().syncPolarScopeTimer()
      this.astroCalcCtl().syncAstroCalcContextTimer()
      this.telescopeCtl().syncTelescopeLivePosition()
      return
    }

    // This app declares no background task. Stop ArkUI polling and audio
    // rendering as soon as the Ability leaves the foreground.
    this.foregroundRefreshPaused = this.timeCtl().hasPanelTimer() || this.detailConnectorCtl().hasDetailTimer()
    this.timeCtl().stopPanelTimers()
    this.viewCoordinateCtl().stopViewCoordinateTimer()
    this.stopDockClockTimer()
    if (this.timeWheelController !== undefined) { this.timeWheelController.stop() }
    this.skyCultureCtl().stopSkyCultureTimeFollowTimer()
    this.polarScopeCtl().stopPolarScopeTimer()
    this.astroCalcCtl().stopAstroCalcContextTimer()
    this.telescopeCtl().stopTelescopeLivePosition(false)
    this.detailConnectorCtl().stopDetailAutoRefresh()
    this.skyInputCtl().stop()
    this.keyboardShortcutCtl().setSkyFocused(false)
    void AudioEngine.getInstance().stop()
    this.gyroCtl().pauseForBackground()
  }
  // 时间轮交互控制器（普通类，非可观测）：拖动/惯性/轨道重基准/引擎推送。
  // 跨域依赖以回调注入：引擎推送、暂停速度、UTC 偏移。
  private timeWheelController: TimeWheelController | undefined = undefined

// ===== 生命周期与启动 =====

  // 城市快速定位预设数据: id -> "lat|lon|alt"


  private dismissSplash(): void {
    if (this.splashGone) return
    if (this.skyWidth < 2 || this.skyHeight < 2 || Date.now() - this.startupViewportCheckedAt < 80) return
    this.startupViewportCheckedAt = Date.now()
    const viewport = this.callNative('getPresentationState', '')
    if (viewport.ok !== true || (viewport as Record<string, Object>)['ready'] !== true) return
    const viewportWidth = Number((viewport as Record<string, Object>)['width'])
    const viewportHeight = Number((viewport as Record<string, Object>)['height'])
    const matching = viewport.ok === true && viewportWidth > 0 && viewportHeight > 0 &&
      Math.abs(viewportWidth / viewportHeight / (this.skyWidth / this.skyHeight) - 1) < 0.008
    if (!matching) return
    this.isLoading = false
    this.splashGone = true
    this.stopTwinkle()
    hilog.info(0, 'StellariumArkUI', '[startup] presented-frame-ready width=%{public}d height=%{public}d',
      viewportWidth, viewportHeight)
    AppStorage.setOrCreate('stellariumStartupSkyReady', true)
    this.objectInspectorMediaCtl().startBodyDetailWarmup()
  }

  private startTwinkle(): void {
    if (this.fpsTimer !== 0) { return }
    this.fpsTimer = setInterval(() => {
      try {
        this.dismissSplash()
      } catch (e) {
      }
    }, 100) as number
  }

  private stopTwinkle(): void {
    if (this.fpsTimer !== 0) { clearInterval(this.fpsTimer); this.fpsTimer = 0 }
  }

  private isHalfFoldedStatus(): boolean {
    return this.foldStatusValue === 3 || this.foldStatusValue === 13 || this.foldStatusValue === 21 || this.foldStatusValue === 22 || this.foldStatusValue === 23
  }

  private responsiveFoldAngle(): number {
    if (this.isFoldableDevice && this.isHalfFoldedStatus() && !this.hasUsableFoldAngle) {
      // HALF_FOLD is sufficient to select the observatory layout. 110 degrees
      // is a neutral visual split until the sensor delivers a live value.
      return 110
    }
    return clamp(this.foldAngleValue, 0, 180)
  }

  private refreshFoldState(source: string): void {
    try {
      this.isFoldableDevice = display.isFoldable()
      if (this.isFoldableDevice) {
        this.foldStatusValue = display.getFoldStatus() as number
        this.foldDisplayModeValue = display.getFoldDisplayMode() as number
      }
      hilog.info(0x0000, 'StellariumArkUI', 'foldState source=%{public}s foldable=%{public}s status=%{public}s mode=%{public}s angle=%{public}s', source, this.isFoldableDevice.toString(), this.foldStatusValue.toString(), this.foldDisplayModeValue.toString(), this.foldAngleValue.toString())
    } catch (e) {
      this.isFoldableDevice = false
      hilog.warn(0x0000, 'StellariumArkUI', 'foldState unavailable source=%{public}s', source)
    }
  }

  private registerFoldListeners(): void {
    this.refreshFoldState('aboutToAppear')
    try {
      display.on('foldStatusChange', this.foldStatusChanged)
      display.on('foldDisplayModeChange', this.foldDisplayModeChanged)
      display.on('foldAngleChange', this.foldAngleChanged)
    } catch (e) {
      hilog.warn(0x0000, 'StellariumArkUI', 'fold listeners unavailable')
    }
  }

  private unregisterFoldListeners(): void {
    try {
      display.off('foldStatusChange', this.foldStatusChanged)
      display.off('foldDisplayModeChange', this.foldDisplayModeChanged)
      display.off('foldAngleChange', this.foldAngleChanged)
    } catch (e) { }
  }

  private updateResponsiveLayout(source: string): void {
    const width = this.skyWidth > 1 ? this.skyWidth : 1
    const height = this.skyHeight > 1 ? this.skyHeight : 1
    const shortSide = Math.min(width, height)
    const longSide = Math.max(width, height)
    const aspect = shortSide > 0 ? longSide / shortSide : 1
    const halfFolded = this.isHalfFoldedStatus()
    const folded = this.foldStatusValue === 2
    const explicitlyExpanded = this.foldStatusValue === 1 || this.foldStatusValue === 11 || this.foldDisplayModeValue === 1
    // Fold state describes the physical device, not this window. In floating
    // mode API 22 can still report an expanded fold state after the app window
    // has become phone-sized, so the actual content bounds take precedence.
    const compactWindow = shortSide < 520
    const largeFoldCanvas = this.isFoldableDevice && shortSide >= 620 && aspect <= 1.55
    const tabletCanvas = shortSide >= 700 || (shortSide >= 620 && longSide >= 1000 && aspect <= 1.75)
    const desktopCanvas = width >= 900 && height >= 520
    const angle = this.responsiveFoldAngle()
    const prevMode = this.responsiveLayoutMode
    let nextMode = prevMode

    if (compactWindow) {
      nextMode = 'compact'
    } else if (this.isFoldableDevice && folded && !halfFolded) {
      nextMode = 'compact'
    } else if (this.isFoldableDevice && halfFolded) {
      if (prevMode === 'expanded') {
        nextMode = angle <= 140 ? 'hover' : 'expanded'
      } else if (prevMode === 'hover') {
        if (angle >= 158 && (explicitlyExpanded || largeFoldCanvas || tabletCanvas || desktopCanvas)) {
          nextMode = 'expanded'
        } else if (angle <= 55) {
          nextMode = 'compact'
        } else {
          nextMode = 'hover'
        }
      } else {
        if (angle >= 158 && (explicitlyExpanded || largeFoldCanvas || tabletCanvas || desktopCanvas)) {
          nextMode = 'expanded'
        } else if (angle >= 68) {
          nextMode = 'hover'
        } else {
          nextMode = 'compact'
        }
      }
    } else if (!folded && (explicitlyExpanded || largeFoldCanvas || tabletCanvas || desktopCanvas)) {
      nextMode = 'expanded'
    } else {
      nextMode = 'compact'
    }

    if (this.uiLayoutOverride === 'compact' || this.uiLayoutOverride === 'expanded') {
      nextMode = this.uiLayoutOverride
    }
    const applyLayout = (): void => {
      this.responsiveLayoutMode = nextMode
      this.isFoldHoverLayout = nextMode === 'hover'
      this.isFoldTabletLayout = this.isFoldableDevice && nextMode === 'expanded' && shortSide < 760
      this.isExpandedLayout = nextMode === 'expanded'
      AppStorage.setOrCreate('stellariumReadableUi', this.isLargeDesktopCanvas())
      this.publishUiLayoutState()
    }
    if (nextMode !== prevMode) {
      try {
        if (source === 'onAreaChange') {
          applyLayout()
        } else {
          this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, applyLayout)
        }
      } catch (e) {
        applyLayout()
      }
    } else {
      applyLayout()
    }
    hilog.info(0x0000, 'StellariumArkUI', 'layout source=%{public}s w=%{public}s h=%{public}s foldable=%{public}s status=%{public}s displayMode=%{public}s angle=%{public}s uiMode=%{public}s hover=%{public}s foldTablet=%{public}s expanded=%{public}s', source, width.toString(), height.toString(), this.isFoldableDevice.toString(), this.foldStatusValue.toString(), this.foldDisplayModeValue.toString(), angle.toString(), nextMode, this.isFoldHoverLayout.toString(), this.isFoldTabletLayout.toString(), this.isExpandedLayout.toString())
  }

  aboutToAppear(): void {
    hilog.info(0x0000, 'StellariumArkUI', '[privacy-probe] phase=main-page-appear')
    const localStorage = this.getUIContext().getSharedLocalStorage()
    if (localStorage) {
      this.createInfo = localStorage.get<WindowNativeNodeCreateInfo>('createInfo')
    }
    // 配置媒体 / 平台 / 传感器三个端口适配器（服务层经它们调用 NAPI，不直接 import）。
    this.hostMediaPort.configure((): common.UIAbilityContext => this.getUIContext().getHostContext() as common.UIAbilityContext)
    this.hostPlatformPort.configure(
      (): common.UIAbilityContext => this.getUIContext().getHostContext() as common.UIAbilityContext,
      (): boolean => this.isExpandedLayout
    )
    // 配置位置端口适配器（权限/定位/preferences NAPI 在此收口）。
    this.hostLocationPort.configure((): common.UIAbilityContext => this.getUIContext().getHostContext() as common.UIAbilityContext)
    // 配置统一设置持久化端口，并异步加载上次保存的 UI 偏好（引擎权威项不在此列）。
    this.hostSettingsPort.configure((): common.UIAbilityContext => this.getUIContext().getHostContext() as common.UIAbilityContext)
    this.settingsRepository.attachPort(this.hostSettingsPort)
    this.loadPersistedUiSettings()
    // 把宿主桥注入 ToolsStore。ToolsStore 消费方均为 @ObjectLink，字段赋值即刷新，
    // 故此处 onChanged 注入等价空实现（该域无 publish* 发布点）。
    const hostPort = this.commandPort()
    this.tools.attachPort(hostPort, () => {})
    // 动作回包后的 UI 提示经 ToolsHostHooks.flashHint 注入（store 不触碰 UI）。
    // 配置整包四法（saveAllCoreSettings / restoreCoreDefaults / exportConfig / importConfig）
    this.tools.attachHooks({
      flashHint: (text: ResourceStr): void => { this.flashHint(text) },
      saveAppSettings: (): void => { this.saveAppSettings() },
      copyConfigExportText: (text: string, successHint: ResourceStr): void => {
        copyTextToClipboard(this.hostPlatformPort, text, successHint, { flashHint: (hint: ResourceStr): void => this.flashHint(hint) })
      },
      resetUiSettings: (): void => { this.settingsRepository.resetToDefaults() },
      exitAppAfterRestore: (): void => { this.exitAppAfterRestore() }
    })
    // （解散 SettingsController）：信息模式 / 导航 / 星历 / 显示四域设置动作并回各 store。
    // 均复用同一 HostCommandPort；可观测状态写各 store（无 publish* 发布点，不注入 onChanged），
    // SelectionService 保留族 / 跨 store / 宿主 @State / hilog 经各自具名 hooks 注入。
    this.infoWindowStore.attachPort(hostPort)
    this.infoWindowStore.attachHooks({
      flashHint: (text: ResourceStr): void => { this.flashHint(text) },
      applySelectedInfoMode: (mode: string): void => { this.applySelectedInfoMode(mode) },
      refreshSelectedObject: (): void => { this.refreshSelectedObject() },
      clearSelectedDetailLoaded: (): void => { this.objectDetailStore.selectedDetailLoaded = false },
      persistDetailDisplayMode: (mode: string): void => { this.writeDetailModeStorage(mode) }
    })
    this.navigationStore.attachPort(hostPort)
    this.navigationStore.attachHooks({
      flashHint: (text: ResourceStr): void => { this.flashHint(text) },
      setAutoZoomResets: (value: boolean): void => { this.viewSettingsStore.autoZoomResets = value }
    })
    this.ephemerisStore.attachPort(hostPort)
    this.ephemerisStore.attachHooks({
      flashHint: (text: ResourceStr): void => { this.flashHint(text) }
    })
    this.viewSettingsStore.attachPort(hostPort)
    this.viewSettingsStore.attachHooks({
      flashHint: (text: ResourceStr): void => { this.flashHint(text) },
      setCurrentProjection: (name: string): void => { this.currentProjection = name },
      reloadConfigurationSettings: (): void => { this.settingsCtl().loadConfigurationSettings() },
      logProjectionError: (name: string, error: string): void => {
        hilog.error(0x0000, 'StellariumArkUI', 'setProjectionType rejected %{public}s err=%{public}s', name, error)
      }
    })
    // 望远镜/目镜域复用同一个 HostCommandPort 实例。其消费方均为 @ObjectLink，
    // 字段赋值即刷新，且该域无 publish* 发布点，故 onChanged 传空实现。
    this.telescopeStore.attachPort(hostPort, () => {})
    // 「是否应刷新」谓词读宿主 applicationInForeground / panelVisible / activePanel，故宿主保留
    // shouldRefreshTelescopePosition，并在 telescopeCtl() 构造时经 TelescopeHostHooks 注入
    //（控制器不触碰 UI 生命周期；state/TelescopeStore 现为纯数据）。
    // 图层视图域（地景列表 / 行星轨道 / 行星轨迹）复用同一实例；消费方均为
    // @ObjectLink，字段赋值即刷新，该域无 publish* 发布点，onChanged 传空实现。
    this.layerViewStore.attachPort(hostPort, () => {})
    // 星表下载域复用同一 HostCommandPort 实例。其消费方（CatalogsPanel）为
    // @ObjectLink，字段赋值即刷新，该域无 publish* 发布点，故 onChanged 传空实现。
    this.catalogStore.attachPort(hostPort, () => {})
    // 代际 languageRefreshSerial（起单一持有者为 LanguageStore）、读写 SearchStore 的
    // pendingPluginCatalogId / searchCategory / categoryModuleId，并调用搜索域动作 loadCategoryObjects
    //（起为 SearchStore 方法）与 CLI 发布点 publishSearchBrowserState —— 全部经
    // CatalogHostHooks 具名注入。
    this.catalogStore.attachHooks({
      languageSerial: (): number => this.languageStore.languageRefreshSerial,
      // download 启动/轮询的 UI 提示经 CatalogHostHooks.flashHint 注入。
      flashHint: (text: ResourceStr): void => { this.flashHint(text) },
      pendingPluginCatalogId: (): string => this.searchStore.pendingPluginCatalogId,
      clearPendingPluginCatalogId: (): void => { this.searchStore.pendingPluginCatalogId = '' },
      searchCategory: (): string => this.searchStore.searchCategory,
      categoryModuleId: (): string => this.searchStore.categoryModuleId,
      loadCategoryObjects: (category: string, moduleIdOverride: string): void => { this.searchStore.loadCategoryObjects(category, moduleIdOverride) },
      publishSearchBrowserState: (): void => { this.publishSearchBrowserState() },
      // 「跨域共用」标志（catalogHealthLoaded / catalogManifestPresent）仍由宿主持有、经 setter 注入，
      // satelliteCatalogHealth 归属 SatelliteStore 亦经 setter 注入（store 不 import 他 store）。
      setCatalogHealthLoaded: (loaded: boolean): void => { this.catalogHealthLoaded = loaded },
      setCatalogManifestPresent: (present: boolean): void => { this.catalogManifestPresent = present },
      setSatelliteCatalogHealth: (health: CatalogHealthEntry): void => { this.satelliteStore.satelliteCatalogHealth = health }
    })
    // 登记的「引擎自用 / 已登记约定」字段 scenery3dCurrentId 仍由宿主持有，加载器经
    // SceneryHostHooks.setScenery3dCurrentId 注入（宿主保留字段本身）。
    this.sceneryStore.attachPort(hostPort)
    this.sceneryStore.attachHooks({
      setScenery3dCurrentId: (id: string): void => { this.scenery3dCurrentId = id }
    })
    // 相机拼接（MosaicCamera）与古天文辅助线（ArchaeoLines）两域复用同一实例。
    // 两者消费方均为 @ObjectLink，字段赋值即刷新，该域无 publish* 发布点，onChanged 传空实现。
    this.mosaicStore.attachPort(hostPort, () => {})
    this.archaeoStore.attachPort(hostPort, () => {})
    // 插件管理 / 命令控制台 / 均时差 / 星云贴图四域复用同一实例。其消费方均为
    // @ObjectLink，字段赋值即刷新，四个域都无 publish* 发布点，故 onChanged 传空实现。
    this.pluginStore.attachPort(hostPort, () => {})
    this.commandStore.attachPort(hostPort, () => {})
    this.equationOfTimeStore.attachPort(hostPort, () => {})
    this.nebulaTextureStore.attachPort(hostPort, () => {})
    // store，复用同一 HostCommandPort；两 store 无 publish* 发布点，故仅注入端口与跨域/UI hooks。
    this.nightModeStore.attachPort(hostPort)
    this.nightModeStore.attachPersistFn((night: boolean) => { this.persistNightModePreference(night) })
    this.julianStore.attachPort(hostPort)
    this.julianStore.attachHooks({
      syncWheelFromSimulation: (jd: number): void => { this.wheel().syncFromSimulation(jd) },
      refreshSimTimeLight: (): void => { this.timeCtl().refreshSimTimeLight() }
    })
    this.sessionToolStore.attachPort(hostPort, () => {})
    // 会话导出/应用/迁移的 UI 提示、剪贴板、ToolsStore 文本框与分布式能力经具名注入。
    this.sessionToolStore.attachHooks({
      flashHint: (text: ResourceStr): void => this.flashHint(text),
      copySessionJson: (text: string, successHint: ResourceStr): void => {
        copyTextToClipboard(this.hostPlatformPort, text, successHint, { flashHint: (hint: ResourceStr): void => this.flashHint(hint) })
      },
      sessionImportText: (): string => this.tools.sessionImportText,
      setSessionExportText: (text: string): void => { this.tools.sessionExportText = text },
      shareSessionJson: (json: string): void => { this.shareCollaborationSession(json) },
      canUseDistributed: (): boolean => this.canUseDistributed
    })
    // 导览域的引擎/定时器/桥在 GuideController；跨域/UI/引擎动作经
    // guideCtl() 的具名 hooks 注入（state/GuideStore 为纯状态）。
    this.guideCtl()
    this.skyCultureSettingsStore.attachPort(hostPort, () => {})
    this.objectDetailStore.attachPort(hostPort, () => {})
    this.objectDetailStore.attachHooks({
      requestSatellitePasses: (expectedName: string): void => { this.requestSatellitePasses(expectedName) }
    })
    // Preferences 读写（原 getUIContext + @ohos.data.preferences）与持久化助手经 hooks 注入
    //（store 不 import NAPI/UI 上下文）。
    this.bookmarkStore.attachPort(hostPort)
    this.bookmarkStore.attachHooks({
      readBookmarksStorage: (): Promise<string> => this.readBookmarksStorage(),
      saveBookmarksToStorage: (): void => { this.saveBookmarksToStorage() },
      // 书签增删跳转提示经 BookmarkHostHooks.flashHint 注入。
      flashHint: (text: ResourceStr): void => { this.flashHint(text) }
    })
    this.obsListStore.attachHooks({
      readObservingListStorage: (): Promise<string> => this.readObservingListStorage(),
      writeObservingListStorage: (json: string): Promise<void> => this.writeObservingListStorage(json),
      saveObservingListStorage: (): void => { this.saveObservingListToStorage() }
    })
    this.overlayStore.attachPort(hostPort, () => {})
    // （其 loadSkyCultureConstellationSelectionFlags 已在 自持）；SkyCultuStore /
    // SkyCultureMakerStore 新增同一端口。三域消费方均为 @ObjectLink，字段赋值即刷新，无 publish*
    // 发布点，onChanged 传空实现。loadSkyCultureDetails（详情，写 保留的 skyCultureArtStates
    // 渐进字段）仍由宿主持有、登记 B3，只经 hooks 注入调用；skyCultureActiveColorTarget /
    // drawSkyCultureTerritoryMap / skyCultureCurrentId / applySkyCultureMakerDraft / ensurePluginLoaded /
    // skyCultureMakerDraftFromResponse 同经具名 hooks 注入（store 不 import 桥/UI/他 store）。
    this.skyCultureSettingsStore.attachHooks({
      skyCultureActiveColorTarget: (): string => this.skyCultureActiveColorTarget(),
      drawSkyCultureTerritoryMap: (): void => { this.drawSkyCultureTerritoryMap() },
      skyCultureCurrentId: (): string => this.skyCultureViewStore.currentSkyCultureId
    })
    this.skyCultureViewStore.attachPort(hostPort, () => {})
    this.skyCultureViewStore.attachHooks({
      invalidateSkyCultureDetails: (): void => { ++this.skyCultureDetailsRequestId },
      loadSkyCultureDetails: (): void => { this.loadSkyCultureDetails() }
    })
    this.skyCultureMakerStore.attachPort(hostPort, () => {})
    this.skyCultureMakerStore.attachHooks({
      applySkyCultureMakerDraft: (draft: SkyCultureMakerDraft): void => this.skyCultureMakerCtl().applySkyCultureMakerDraft(draft),
      ensurePluginLoaded: (pluginName: string, callback: () => void, failureCallback?: () => void): void => this.pluginFeatureCtl().ensurePluginLoaded(pluginName, callback, failureCallback),
      skyCultureMakerDraftFromResponse: (response: StellariumBridgeResponse): SkyCultureMakerDraft | undefined => this.skyCultureMakerCtl().skyCultureMakerDraftFromResponse(response)
    })
    // 卫星域有 publish* CLI 发布点（publishSatellitePanelState），
    // 故 onChanged 用它，保持 CLI 侧 satellitePanelState 与 store 同步。
    this.satelliteStore.attachPort(hostPort, (error: string) => { this.publishSatellitePanelState(error) })
    // 位置域的 loadSavedLocations 读 AppStorage 而非桥，port 暂未使用（预留）。
    this.locationStore.attachPort(hostPort, () => {})
    // 离线搜索 / 保存点的跨域读（LocationPickerStore 助手 + SessionToolStore.observerPlanet）
    // 与跨 store 动作（setLocation / pickerMode）经具名 hooks 注入，store 不 import 他 store。
    this.locationStore.attachHooks({
      flashHint: (text: ResourceStr): void => { this.flashHint(text) },
      currentDraft: (): LocationDraft => {
        return {
          name: this.locationPickerStore.locationPickerName,
          latitude: this.locationPickerStore.locationPickerLatitude,
          longitude: this.locationPickerStore.locationPickerLongitude,
          altitude: this.locationPickerStore.locationPickerAltitude,
          planet: this.sessionToolStore.observerPlanet
        }
      },
      observerPlanet: (): string => this.sessionToolStore.observerPlanet,
      quickLocationSearch: (query: string, observerPlanet: string): Array<LocSearchItem> => this.locationPickerStore.quickLocationSearch(query, observerPlanet),
      isCurrentObserverPlanet: (city: HierCity, observerPlanet: string): boolean => this.locationPickerStore.isCurrentObserverPlanet(city, observerPlanet),
      locationDisplayName: (name: string): string => this.locationPickerStore.locationDisplayName(name),
      locationSearchCountryName: (countryCode: string, observerPlanet: string): string => this.locationPickerStore.locationSearchCountryName(countryCode, observerPlanet),
      translateProvince: (name: string): string => this.locationPickerStore.translateProvince(name),
      locationPlanet: (city: HierCity): string => this.locationPickerStore.locationPlanet(city),
      applyLocation: (name: string, lat: number, lon: number, alt: number, planet: string): void => { this.locationCtl().setLocation(name, lat, lon, alt, planet) },
      setPickerMode: (mode: string): void => { this.locationPickerStore.locationPickMode = mode }
    })
    // astro 域桥加载 / 请求序号在 astroCalcCtl()；store 只保留数据与纯派生，
    // 故不 attachPort，只注入纯跨域读取 / 格式化 hooks。
    this.astroStore.attachHooks({
      hasSelectedObject: () => this.objectDetailStore.hasSelectedObject(),
      selectedObjectName: () => this.objectDetailStore.selectedName,
      wutCategory: () => this.wutStore.wutCategory,
      wutObservationTime: () => this.wutStore.wutObservationTime,
      fmtDateTime: (s: string | undefined) => this.astroCalcCtl().fmtDateTime(s)
    })
    // 经具名 hooks 回指控制器；每 1s 计时器与面板开合只调用 store 的 loadPolarScopeData /
    // cancelPolarScopeRequest。
    this.polarScopeStore.attachPort(hostPort)
    this.polarScopeStore.attachHooks({
      shouldRefreshPolarScope: () => this.polarScopeCtl().shouldRefreshPolarScope()
    })
    // publishAstroPanelState，保持 CLI 侧 astroPanelState 的 wut 字段同步。
    this.wutStore.attachPort(hostPort, () => { this.publishAstroPanelState() })
    // 故此处三个 hooks 转发给控制器（store 仍不 import NAPI/UI，不走桥、无 publish*，不注入 CommandPort）。
    this.objectMediaStore.attachHooks({
      readRawSidecar: (path: string, expectedBytes: number, label: string): ArrayBuffer => this.hostMediaPort.readRawSidecar(path, expectedBytes, label),
      decodeObjectInspectorModelTextureFromPng: (pngFilePath: string, ringPngFilePath: string, mediaGeneration: number, expectedSelection: string, expectedPath: string): void =>
        this.objectModelRendererCtl().decodeObjectInspectorModelTextureFromPng(pngFilePath, ringPngFilePath, mediaGeneration, expectedSelection, expectedPath),
      commitObjectInspectorModelTexture: (texture: ArrayBuffer, ringTexture: ArrayBuffer | undefined, mediaGeneration: number, expectedSelection: string, expectedPath: string, sourceLabel: string): void =>
        this.objectModelRendererCtl().commitObjectInspectorModelTexture(texture, ringTexture, mediaGeneration, expectedSelection, expectedPath, sourceLabel),
      failObjectInspectorModelTexture: (mediaGeneration: number, reason: string): void => this.objectModelRendererCtl().failObjectInspectorModelTexture(mediaGeneration, reason)
    })
    // TimeStore，均复用同一 HostCommandPort 实例。三者消费方均为 @ObjectLink（字段赋值即刷新），
    // 且无 publish* 发布点，故 onChanged 传空实现。跨 store 写入的字段与两个与宿主动作共享的
    // 助手（applySelectedInfoMode / applyTimeSettings / syncNightModeFromEngine）按 「额外注入」
    // 经具名 hooks 注入；applyAtmosphereResponse 已于 并回 AtmosphereStore。
    this.locationPickerStore.attachPort(hostPort, () => {})
    this.locationPickerStore.attachHooks({
      setSkyCultureObserverLatitude: (value: number): void => { this.skyCultureSettingsStore.skyCultureObserverLatitude = value },
      setObserverPlanet: (value: string): void => { this.sessionToolStore.observerPlanet = value }
    })
    // 启动恢复上次观测点（含 GPS 定点）：不再每次重启回退引擎默认北京。引擎未就绪由
    // setLocation 内的 callNativeWhenReady 重试兜底（起经位置控制器）。
    this.locationCtl().restoreObserverLocation()
    this.timeStore.attachPort(hostPort, () => {})
    this.timeStore.attachHooks({
      // TimeStore 在 getNightMode 首次入队时记录该序号，回包到达时用它校验快照年龄。
      nightModeEpoch: (): number => this.nightModeStore.nightModeEpoch(),
      syncNightModeFromEngine: (engineNight: boolean, requestEpoch: number): void => this.nightModeStore.syncNightModeFromEngine(engineNight, requestEpoch),
      applyAtmosphereResponse: (response: StellariumBridgeResponse): void => this.atmosphereStore.applyAtmosphereResponse(response)
    })
    // 设置「配置回读」加载在 settingsCtl()：TimeSettingsStore 为纯数据，
    // 8 连发桥读归 SettingsController；跨域 setter 作为 TimeSettingsHostHooks 在该控制器惰性构造处注入。
    // 航海星 / 流星雨 / 搜索三域分别自持加载器（loadNavStars / loadMeteorShowers /
    // loadConstellationNavigation）与其配对写方；三者复用同一 HostCommandPort 实例，消费方均为
    // @ObjectLink（字段赋值即刷新），无 publish* 发布点，故 onChanged 传空实现。
    // SearchStore 的 loadConstellationNavigation 经 SearchHostHooks.languageSerial 只读 LanguageStore
    // 的语言刷新代际（单一持有者，宿主不留副本）。
    this.navStarsStore.attachPort(hostPort, () => {})
    this.meteorStore.attachPort(hostPort, () => {})
    this.searchStore.attachPort(hostPort, () => {})
    // 插件加载器与搜索历史 Preferences 读写经 SearchHostHooks 具名注入（store 不 import 桥/UI/
    // NAPI）；语言刷新代际仍只读 LanguageStore。
    this.searchStore.attachHooks({
      languageSerial: (): number => this.languageStore.languageRefreshSerial,
      publishSearchBrowserState: (): void => { this.publishSearchBrowserState() },
      categoryModuleIdFor: (category: string): string => this.catalogStore.categoryModuleIdFor(category),
      ensurePluginLoaded: (pluginName: string, callback: () => void, failureCallback?: () => void): void => this.pluginFeatureCtl().ensurePluginLoaded(pluginName, callback, failureCallback),
        celestialTitle: (nativeName: string, englishName: string): string => celestialTitle(nativeName, englishName),
      readSearchHistoryStorage: (): Promise<string> => this.readSearchHistoryStorage(),
      writeSearchHistoryStorage: (json: string): Promise<void> => this.writeSearchHistoryStorage(json)
    })
    // （AudioEngine 是原生桥）与 UI 提示经具名 hooks 注入（store 不 import NAPI/UI）。
    this.audioStore.attachHooks({
      setMusicPlaying: (enabled: boolean): void => {
        const engine = AudioEngine.getInstance()
        if (enabled) { engine.start().then(() => { engine.setMuted(false) }) } else { engine.setMuted(true) }
      },
      flashHint: (text: ResourceStr): void => this.flashHint(text)
    })
    this.startPageAfterPrivacyIfNeeded()
  }

  private onQtNativeNodeAttach(): void {
    hilog.info(0x0000, 'StellariumArkUI', '[privacy-probe] phase=qt-native-node-attach')
    if (this.createInfo !== undefined) {
      this.createInfo.onAttach()
    }
  }

  private onQtNativeNodeAppear(): void {
    hilog.info(0x0000, 'StellariumArkUI', '[privacy-probe] phase=qt-native-node-appear')
    if (this.createInfo !== undefined) {
      this.createInfo.onAppear()
    }
  }

  private onQtNativeNodeDisappear(): void {
    hilog.info(0x0000, 'StellariumArkUI', '[privacy-probe] phase=qt-native-node-disappear')
    if (this.createInfo !== undefined) {
      this.createInfo.onDisAppear()
    }
  }

  private onQtSurfaceAppear(): void {
    hilog.info(0x0000, 'StellariumArkUI', '[privacy-probe] phase=qt-surface-appear')
  }

  private onPrivacyNativeStartupAllowedChanged(): void {
    hilog.info(0x0000, 'StellariumArkUI',
      '[privacy-probe] phase=native-node-gate-observed allowed=%{public}s', this.privacyNativeStartupAllowed.toString())
    this.startPageAfterPrivacyIfNeeded()
  }

  private onCliUiEventChanged(): void {
    if (this.cliUiEvent.length === 0) {
      return
    }
    try {
      const event = JSON.parse(this.cliUiEvent) as Record<string, Object>
      const requestId = event['requestId'] as string
      if (requestId === undefined || requestId.length === 0 || requestId === this.lastCliUiEventId) {
        return
      }
      this.lastCliUiEventId = requestId
      const commandName = event['commandName'] as string
      const response = event['response'] as StellariumBridgeResponse
      if (commandName === 'setUiLayoutMode') {
        const mode = String(event['payload'] ?? '').trim().toLowerCase()
        if (mode === 'auto' || mode === 'compact' || mode === 'expanded') {
          this.uiLayoutOverride = mode
          this.updateResponsiveLayout('cli')
        }
        return
      }
      if (commandName === 'startGuide' || commandName === 'guideAction') {
        this.guideCtl().executeGuideRequest(commandName, String(event['payload'] ?? ''), requestId)
        return
      }
      if (commandName === 'setSatellitesFlag' && response.ok === true) {
        const parts = String(event['payload'] ?? '').split(':')
        const enabled = parts[1] === '1' || parts[1] === 'true'
        this.satelliteStore.satelliteFlagMutationId++
        if (parts[0] === 'labels') this.satelliteStore.satLabels = enabled
        else if (parts[0] === 'orbitLines') this.satelliteStore.satOrbitLines = enabled
        else if (parts[0] === 'hints') this.satelliteStore.satHints = enabled
        else if (parts[0] === 'iconicMode') this.satelliteStore.satIconicMode = enabled
        else if (parts[0] === 'hideInvisible') this.satelliteStore.satHideInvisible = enabled
        this.publishSatellitePanelState()
        return
      }
      if (commandName === 'setSatellitePanelGroup') {
        this.satelliteCtl().selectSatelliteGroup(String(event['payload'] ?? '').trim())
        return
      }
      if (commandName === 'setLocationMapProvider') {
        this.locationCtl().setLocationMapProvider(String(event['payload'] ?? '').trim())
        return
      }
      if ((commandName === 'setObserverPlanet' || commandName === 'setLocation' || commandName === 'setLocationCoords' || commandName === 'setLocationByName') && response.ok === true) {
        this.locationCtl().syncObserverFromNative()
        return
      }
      if (commandName === 'setSearchBrowserPage' || commandName === 'selectSearchCategory') {
        if (!this.panelVisible || this.activePanel !== 'search') this.openPanelFromCli('search')
        this.searchStore.searchText = ''
        const value = String(event['payload'] ?? '').trim()
        if (commandName === 'selectSearchCategory') this.searchCtl().selectSearchFilterCategory(value)
        else this.searchCtl().setSearchFilterPage(value === 'browse' ? '' : value)
        this.publishSearchBrowserState()
        return
      }
      if (commandName === 'setSearchBrowserFilter') {
        if (!this.panelVisible || this.activePanel !== 'search') this.openPanelFromCli('search')
        const parts = String(event['payload'] ?? '').split('|')
        if (parts[0] === 'visibility') this.searchCtl().selectSearchVisibilityFilter(parts[1])
        else this.searchCtl().selectSearchInstrumentFilter(parts[1])
        this.publishSearchBrowserState()
        return
      }
      if (commandName === 'setAstroTab' || commandName === 'setAstroGroup') {
        if (this.panelVisible && this.activePanel === 'astro') {
          if (commandName === 'setAstroTab') this.astroCalcCtl().selectAstroTab(Number(event['payload']))
          else this.astroCalcCtl().selectAstroGroup(Number(event['payload']))
        }
        this.publishAstroPanelState()
        return
      }
      if (commandName === 'setAstroFilter') {
        const parts = String(event['payload'] ?? '').split('|')
        this.astroCalcCtl().selectAstroFilter(parts[0], parts[1])
        return
      }
      if (commandName === 'setAstroScroll') {
        this.astroPanelScroller.scrollTo({ xOffset: 0, yOffset: Number(event['payload']), animation: false })
        this.publishAstroPanelState()
        return
      }
      if (commandName === 'setSatellitePanelScroll') {
        const offset = Number(event['payload'])
        if (Number.isFinite(offset) && offset >= 0) {
          this.satellitePanelScroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false })
        }
        this.publishSatellitePanelState()
        return
      }
      if (commandName === 'setObjectDetailTab') {
        if (this.objectDetailStore.selectedName.length > 0) {
          this.infoWindowStore.infoWinVisible = true
          this.selectObjectDetailTab(Number(event['payload']))
        }
        return
      }
      if (commandName === 'setObjectModelView') {
        const value = String(event['payload'] ?? '').trim()
        if (this.objectMediaStore.objectInspectorMediaKind !== 'model') {
          AppStorage.setOrCreate('stellariumObjectModelView', JSON.stringify({
            ok: false, requestId: requestId, error: 'selected object has no 3D model'
          }))
          return
        }
        if (value === 'open') {
          this.infoWindowStore.infoWinVisible = true
          this.selectObjectDetailTab(2)
        } else if (value === 'immersive') {
          this.objectModelRendererCtl().setObjectInspectorModelImmersive(true)
        } else if (value === 'close') {
          this.objectModelRendererCtl().setObjectInspectorModelImmersive(false)
        } else if (value === 'reset') {
          this.objectModelRendererCtl().resetObjectInspectorModelView()
        } else {
          const parts = value.split('|')
          this.objectModelRendererCtl().rotateObjectInspectorModel(Number(parts[0]), Number(parts[1]))
          this.objectModelRendererCtl().requestObjectInspectorModelRender(true)
        }
        return
      }
      if (commandName === 'setMosaicCamera' || commandName === 'getMosaicCamera') {
        if (response.ok === true) this.mosaicStore.loadMosaicCamera(false)
        return
      }
      if (commandName === 'getNebulaTextureStatus' || commandName === 'setNebulaTexturesVisible' ||
        commandName === 'setNebulaTextureConflictAvoidance') {
        if (response.ok === true) this.nebulaTextureStore.nebulaTextureStatus = response as NebulaTextureStatus
        return
      }
      if (commandName === 'setTimeSetting' || commandName === 'getTimeSettings' ||
        commandName === 'setDateFormat' || commandName === 'setTimeFormat') {
        this.timeCtl().applyTimeSettings(response)
        return
      }
      if (commandName === 'setInformationSetting' || commandName === 'getInformationSettings') {
        if (response.ok !== true) return
        this.infoWindowStore.informationMode = response.infoMode ?? this.infoWindowStore.informationMode
        if (response.customInfoMask !== undefined) this.infoWindowStore.informationCustomMask = Number(response.customInfoMask)
        this.applySelectedInfoMode(this.infoWindowStore.informationMode)
        this.objectDetailStore.selectedDetailLoaded = false
        this.refreshSelectedObject()
        return
      }
      if (commandName === 'setLanguage' && response.ok === true) {
        const language = String(event['payload'] ?? '').trim()
        if (language.length > 0) this.setLanguage(language)
        return
      }
      if (commandName === 'openUiPanel') {
        const panel = String(event['payload'] ?? '').trim()
        if (isCliPanelName(panel)) {
          this.openPanelFromCli(panel)
          hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] opened panel=%{public}s', panel)
        } else {
          hilog.warn(0x0000, 'StellariumArkUI', '[cli-ui] rejected panel=%{public}s', panel)
        }
        return
      }
      if (commandName === 'openPluginFeature') {
        const pluginId = String(event['payload'] ?? '').trim()
        if (pluginId.length > 0) {
          this.pluginFeatureCtl().openPluginFeature(pluginId)
          hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] opened plugin feature=%{public}s', pluginId)
        } else {
          hilog.warn(0x0000, 'StellariumArkUI', '[cli-ui] rejected empty plugin feature')
        }
        return
      }
      if (commandName === 'setLayerTab') {
        const tabId = Number(String(event['payload'] ?? '').trim())
        if (this.activePanel === 'layers' && this.panelVisible && Number.isInteger(tabId) && tabId >= 0 && tabId <= 6) {
          this.layerCtl().selectViewTab(tabId)
          hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] layer tab=%{public}d', tabId)
        } else {
          hilog.warn(0x0000, 'StellariumArkUI', '[cli-ui] rejected layer tab=%{public}s', String(event['payload'] ?? ''))
        }
        return
      }
      if (commandName === 'setSkyCultureMakerTab') {
        const tabId = Number(String(event['payload'] ?? '').trim())
        if (this.activePanel === 'skyCultureMaker' && this.panelVisible && Number.isInteger(tabId) && tabId >= 0 && tabId <= 2) {
          this.skyCultureMakerStore.tab = tabId
          hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] sky culture maker tab=%{public}d', tabId)
        } else {
          hilog.warn(0x0000, 'StellariumArkUI', '[cli-ui] rejected sky culture maker tab=%{public}s', String(event['payload'] ?? ''))
        }
        return
      }
      if (commandName === 'setGyroscopeEnabled') {
        const value = String(event['payload'] ?? '').trim().toLowerCase()
        if (value === '1' || value === 'true' || value === 'on') {
          this.gyroCtl().toggleGyroscope(true)
          hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] gyroscope enabled=true')
        } else if (value === '0' || value === 'false' || value === 'off') {
          this.gyroCtl().toggleGyroscope(false)
          hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] gyroscope enabled=false')
        } else {
          hilog.warn(0x0000, 'StellariumArkUI', '[cli-ui] rejected gyroscope value=%{public}s', value)
        }
        return
      }
      if (commandName === 'setTelescopeLivePosition') {
        const value = String(event['payload'] ?? '').trim().toLowerCase()
        const enabled = value === '1' || value === 'true' || value === 'on'
        this.telescopeCtl().setTelescopeLivePosition(enabled)
        hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] telescope live position enabled=%{public}s', enabled.toString())
        return
      }
      if (commandName === 'setSkyCulture' && response.ok === true) {
        const cultureId = response.cultureId !== undefined
          ? String(response.cultureId)
          : String(event['payload'] ?? '').trim()
        if (cultureId.length > 0) {
          this.skyCultureCtl().captureSkyCultureAnchor(cultureId)
          this.skyCultureViewStore.pendingId = cultureId
          this.skyCultureViewStore.currentSkyCultureId = cultureId
          this.loadSkyCultureDetails()
          hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] sky culture=%{public}s', cultureId)
        }
        return
      }
      if (commandName === 'closeUiPanel') {
        this.closePanel(true)
        hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] closed panel')
        return
      }
      if (commandName === 'playScript' && response.ok === true) {
        this.scriptStore.scriptFocusActive = true
        this.scriptStore.scriptLaunching = false
        this.scriptStore.scriptLaunchingName = ''
        this.scriptStore.scriptId = String(event['payload'] ?? '')
        this.scriptStore.scriptStartGraceUntil = Date.now() + 2500
        this.panelVisible = false
        this.infoWindowStore.infoWinVisible = false
        this.scriptPlaybackCtl().startScriptStatusPolling()
        return
      }
      if (commandName === 'continueScript' && response.ok === true) {
        this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
          this.scriptStore.scriptWaiting = false
          this.scriptStore.scriptWaitMessage = ''
        })
        return
      }
      if (commandName === 'setScriptRate' && response.ok === true) {
        const rate = Number(String(event['payload'] ?? '').trim())
        if (Number.isFinite(rate) && rate > 0) {
          this.scriptStore.scriptRate = rate
        }
        return
      }
      if (commandName === 'stopScript' && response.ok === true && this.scriptStore.scriptSessionActive(this.tools.recording, this.guideStore.guideState.active)) {
        this.scriptPlaybackCtl().finishNativeScriptUi(I18n.t('script_stopped'))
        return
      }
      if (commandName === 'backUiPanel') {
        this.goBackPanel()
        hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] navigated back')
        return
      }
      if ((commandName === 'setObjectDetailConnector' || commandName === 'getObjectDetailConnector') &&
        (response as Record<string, Object>)['enabled'] !== undefined) {
        const enabled = (response as Record<string, Object>)['enabled'] as boolean
        this.setObjectDetailConnector(enabled, false)
        hilog.info(0x0000, 'StellariumArkUI', '[cli-ui] detail connector=%{public}s', enabled.toString())
        return
      }
      if (commandName === 'clearSelection' || response.found !== true) {
        this.applySelectedObject(response)
        return
      }
      this.applySelectedObject(response, false, 'center')
      hilog.info(0x0000, 'StellariumArkUI',
        '[cli-ui] selection synchronized command=%{public}s name=%{public}s',
        commandName, this.objectDetailStore.selectedName)
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[cli-ui] event ignored: %{public}s', JSON.stringify(err))
    }
  }

  private startPageAfterPrivacyIfNeeded(): void {
    if (!this.privacyNativeStartupAllowed || this.privacyPageStartupStarted) {
      return
    }
    this.privacyPageStartupStarted = true
    this.startTwinkle()
    // Keep the old AppStorage value as a migration fallback while the durable
    // preferences store is opened asynchronously.
    const stored = AppStorage.get<string>("observingList")
    if (stored) this.obsListStore.observingList = parseObservingList(stored)
    this.obsListStore.loadObservingListFromStorage()
    this.searchStore.loadSearchHistoryFromStorage()
    this.bookmarkStore.loadBookmarksFromStorage()
    this.registerFoldListeners()
    this.subscribeApplicationLifecycle()
    this.startupBridge().startupBridgeSync()
    // 快捷面板编辑态的落盘 / 提示经 hooks 注入面板自己的 store（面板不 import NAPI）。
    this.quickPanelStore.configure({
      saveOrder: (json: string) => { this.saveQuickActionOrder(json) },
      hint: (text: string) => { this.flashHint(text) }
    })
    this.loadQuickActionOrderFromStorage()
    this.loadDetailModeFromStorage()
  }

  // ── 详情卡「呈现轴」持久化（观测模式）──
  // store `stellarium_info_window` / key `detailDisplayMode`。切换**不触碰桥**：
  // 信息级别（数据轴）与详情卡形态（呈现轴）正交，见 specs/OBJECT-DETAIL-OBSERVE-MODE.md §3/§4.6。
  private async writeDetailModeStorage(mode: string): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, INFO_WINDOW_STORE)
      await store.put('detailDisplayMode', mode)
      await store.flush()
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'save detail display mode failed: %{public}s', String(e))
    }
  }

  // 读失败 / 缺省一律回落天文馆模式（等价于升级前的观感）。
  private async loadDetailModeFromStorage(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, INFO_WINDOW_STORE)
      const raw = await store.get('detailDisplayMode', 'planetarium')
      this.infoWindowStore.restoreDetailDisplayMode(typeof raw === 'string' ? raw : 'planetarium')
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'load detail display mode failed: %{public}s', String(e))
    }
  }

  // 观测模式开关（快捷面板格子与设置页 Toggle 的同一入口）：只切呈现轴，并给一次提示。
  private applyObserveMode(enabled: boolean): void {
    const target = enabled ? 'observe' : 'planetarium'
    const changed = this.infoWindowStore.detailDisplayMode !== target
    this.infoWindowStore.setDetailDisplayMode(target)
    if (changed) {
      this.flashHint(I18n.t(enabled ? 'detail_switched_observe' : 'detail_switched_planetarium'))
    }
  }

  // 快捷面板 12 格顺序的持久化（store `stellarium_quick_panel` / key `order`，与书签 / 观测列表同套）。
  // 校验与回落默认在 store 内（它拿到的串一定是合法的），此处只负责读写盘。
  private saveQuickActionOrder(json: string): void {
    if (json.length === 0) return
    this.writeQuickActionOrder(json)
  }

  private async writeQuickActionOrder(json: string): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, QUICK_PANEL_STORE)
      await store.put('order', json)
      await store.flush()
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'save quick panel order failed: %{public}s', String(e))
    }
  }

  // 从 preferences 恢复顺序；缺省 / 损坏时 store 自行回落默认（见 QuickPanelStore.restoreOrder）。
  private async loadQuickActionOrderFromStorage(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, QUICK_PANEL_STORE)
      const raw = await store.get('order', '')
      if (typeof raw !== 'string' || raw.length === 0) return
      const parsed = JSON.parse(raw) as Object[]
      const order: string[] = []
      for (const entry of parsed) order.push(String(entry))
      this.quickPanelStore.restoreOrder(order)
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'load quick panel order failed: %{public}s', String(e))
    }
  }

  // 启动期自动定位（只触发一次）。GPS 可用时更新为真实位置，不可用时回退到已保存/默认位置。
  aboutToDisappear(): void {
    this.guideCtl().stopGuideTimer()
    this.guideCtl().resetJourneyFlags()
    this.guideCtl().stopPlayer()
    this.skyCultureMakerCtl().flushSkyCultureMakerSave()
    this.searchCtl().stop()
    this.saveAppSettings()
    this.skyInputCtl().stop()
    this.keyboardShortcutCtl().setSkyFocused(false)
    this.gyroCtl().stopGyroscope(false)
    this.detailConnectorCtl().stop()
    this.objectInspectorMediaCtl().stopObjectInspectorMediaWarmup()
    this.objectInspectorMediaCtl().stopBodyDetailWarmup()
    this.objectInspectorMediaCtl().clearObjectInspectorDecodedImage()
    this.skyCultureCtl().invalidateSkyCultureArtDecode()
    this.skyCultureCtl().clearSkyCultureArtThumbnails()
    if (this.stateRefreshTimer >= 0) {
      clearTimeout(this.stateRefreshTimer)
      this.stateRefreshTimer = -1
    }
    if (this.panelDataLoadTimer >= 0) {
      clearTimeout(this.panelDataLoadTimer)
      this.panelDataLoadTimer = -1
    }
    this.stateRefreshRequestPending = false
    this.stateRefreshQueued = false
    const skyCulturePixelMap = this.skyCultureViewStore.artPreviewPixelMap
    this.skyCultureViewStore.artPreviewPixelMap = undefined
    releaseDecodedImage(this.hostMediaPort, skyCulturePixelMap, 'disappear-sky-culture-art')
    this.skyCultureMakerCtl().clearSkyCultureMakerArtworkPreview('disappear-sky-culture-maker-artwork')
    this.skyTextureStatusCtl().stop()
    this.timeCtl().stopPanelTimers()
    this.viewCoordinateCtl().stopViewCoordinateTimer()
    this.stopDockClockTimer()
    if (this.timeWheelController !== undefined) { this.timeWheelController.stop() }
    this.skyCultureCtl().stopSkyCultureTimeFollowTimer()
    this.polarScopeCtl().stopPolarScopeTimer()
    this.astroCalcCtl().stopAstroCalcContextTimer()
    this.telescopeCtl().stopTelescopeLivePosition(false)
    this.scriptPlaybackCtl().stopScriptStatusPolling()
    this.recordingCtl().stop()
    this.unregisterFoldListeners()
    this.unsubscribeApplicationLifecycle()
  }

  private subscribeApplicationLifecycle(): void {
    setLifecycleListener(this.handleApplicationLifecycle)
  }

  private unsubscribeApplicationLifecycle(): void {
    setLifecycleListener(undefined)
  }

  // validateTelescopeEditorStatus / selectTelescopeProfile / beginNewTelescopeProfile / selectTelescopeProtocol /
  // saveTelescopeProfile / deleteTelescopeProfile / testTelescopeConnection / applyLx200Result /


  private confirmPrivacyRevocation(): void {
    this.getUIContext().showAlertDialog({
      title: I18n.t('privacy_revoke'),
      message: I18n.t('privacy_revoke_message'),
      primaryButton: {
        value: I18n.t('cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.t('privacy_revoke_confirm'),
        fontColor: this.hostSlots().errorText,
        action: () => { this.revokePrivacyConsent() }
      }
    })
  }

  private revokePrivacyConsent(): void {
    try {
      this.gyroCtl().stopGyroscope(false)
      privacyManager.disableService()
      AppStorage.setOrCreate('stellariumPrivacyHostReady', false)
      this.privacyNativeStartupAllowed = false
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      void context.terminateSelf().catch((err: Error) => {
        hilog.error(0x0000, 'StellariumArkUI', 'Failed to terminate after privacy revocation: %{public}s', JSON.stringify(err))
      })
    } catch (err) {
      hilog.error(0x0000, 'StellariumArkUI', 'Failed to revoke privacy consent: %{public}s', JSON.stringify(err))
      this.flashHint(I18n.t('privacy_revoke_failed'))
    }
  }

// ===== 桥包装 =====

  private callNative(name: string, payload: string = ''): StellariumBridgeResponse {
    const r = BridgeClient.request(name, payload)
    // 录制：仅在录制开启、非回放、且命令可录制时记录，并对短时重试用去重窗口避免重复。
    if (r.ok === true) { this.recordingCtl().recordAcceptedCommand(name, payload) }
    return r
  }

  // Fire-and-forget: 调用 C++ 桥但不解析返回的 JSON，减少拖动时的 GC 压力。
  // 用于 dragView / zoomBy / panBy 等不需要返回值的连续命令。
  private callNativeFire(name: string, payload: string = ''): void {
    const raw = BridgeClient.send(name, payload)
    if (raw.length === 0) { return }
    if (this.tools.recording && !this.tools.recordingPaused && !this.scriptStore.replaying && isRecordable(name)) {
      let accepted = false
      try {
        accepted = (JSON.parse(raw) as StellariumBridgeResponse).ok === true
      } catch (err) {
        accepted = false
      }
      if (accepted) { this.recordingCtl().recordAcceptedCommand(name, payload) }
    }
  }

  // Retry a native command until the Stellarium core is initialized.
  // At startup the ArkUI thread may call the bridge before Qt has finished
  // bootstrapping; those calls return ok:false and are retried on a short
  // backoff instead of crashing the process.
  private callNativeWhenReady(name: string, payload: string = '', onOk?: (r: StellariumBridgeResponse) => void, attempt: number = 0, intervalMs: number = 200, maxAttempts: number = 60, onFailure?: (r: StellariumBridgeResponse) => void): void {
    BridgeClient.requestWhenReady(name, payload, (r: StellariumBridgeResponse) => {
      // 录制：仅在录制开启、非回放、且命令可录制时记录，并对短时重试用去重窗口避免重复。
      this.recordingCtl().recordAcceptedCommand(name, payload)
      if (onOk) onOk(r)
    }, attempt, intervalMs, maxAttempts, onFailure)
  }

  // Interactive commands (tap-select, search, get-info, move-to) run on the
  // OHOS render pump one frame later and are delivered via a consume-on-read
  // store on the C++ side, so the first call returns {pending}. Poll fast
  // (50ms x 40 = 2s) so a single tap/search resolves without a visible delay
  // and WITHOUT blocking the render thread. onOk receives the FRESH result.
  private callInteractive(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void): void {
    this.callNativeWhenReady(name, payload, onOk, 0, 100, 15, onFailure)
  }

  private callLongRunningInteractive(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, onProgress?: (r: StellariumBridgeResponse) => void, maxAttempts: number = 240, isCancelled?: () => boolean): void {
    let attempt = 0
    const poll = (): void => {
      // A superseded request must stop re-issuing its payload. The engine keeps a
      // single long-running job, so a stale loop used to cancel the newest job on
      // every tick and neither side ever produced a result.
      if (isCancelled !== undefined && isCancelled()) { return }
      const response = this.callNative(name, payload)
      if (response.ok === true) {
        onOk(response)
        return
      }
      if (response.pending === true && attempt < maxAttempts) {
        if (onProgress) onProgress(response)
        ++attempt
        setTimeout(poll, 100)
        return
      }
      // A panel can be opened by CLI during the short window between ArkUI
      // creation and Qt bridge readiness. Treat only these startup errors as
      // transient; real calculation errors still reach the failure state.
      const transientStartupError = response.error === 'bridge not available' ||
        response.error === 'bridge parse failed' || response.error === 'command timeout'
      if (transientStartupError && attempt < maxAttempts) {
        if (onProgress) onProgress(response)
        ++attempt
        setTimeout(poll, 100)
        return
      }
      if (onFailure) onFailure(response)
    }
    poll()
  }

// ===== 控制器访问器 =====

  // / 宿主桥端口的惰性单例。首次调用构造 HostCommandPort 并缓存，
  // 之后 aboutToAppear 里的各 store 与 UI 回调共用同一实例（行为与原先的局部 const 一致）。
  private commandPort(): CommandPort {
    if (this.hostCommandPort === null) {
      this.hostCommandPort = new HostCommandPort(
        (name: string, payload: string) => this.callNative(name, payload),
        (name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, attempt?: number, intervalMs?: number, maxAttempts?: number) => {
          this.callNativeWhenReady(name, payload, onOk, attempt ?? 0, intervalMs ?? 200, maxAttempts ?? 60, onFailure)
        },
        (name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void) => {
          this.callInteractive(name, payload, onOk, onFailure)
        },
        (name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void, onProgress?: (r: StellariumBridgeResponse) => void, maxAttempts?: number, isCancelled?: () => boolean) => {
          this.callLongRunningInteractive(name, payload, onOk, onFailure, onProgress, maxAttempts, isCancelled)
        },
        (name: string, payload: string) => { this.callNativeFire(name, payload) }
      )
    }
    return this.hostCommandPort
  }

  // / 启动桥服务的惰性单例。持有各域 store 实例与宿主生命周期 hooks，
  // 在首次调用（aboutToAppear 末尾或 onAreaChange）时构造。
  private startupBridge(): StartupBridge {
    if (this.startupBridgeImpl === null) {
      this.startupBridgeImpl = new StartupBridge(
        this.commandPort(),
        {
          flashHint: (text: ResourceStr): void => this.flashHint(text),
          dismissSplash: (): void => this.dismissSplash(),
          setLanguage: (language: string): void => this.setLanguage(language),
          syncViewCoordinateTimer: (): void => this.viewCoordinateCtl().syncViewCoordinateTimer(),
          syncDockClockTimer: (): void => this.syncDockClockTimer(),
          setCurrentProjection: (value: string): void => { this.currentProjection = value },
          bridgeSyncStarted: (): boolean => this.bridgeSyncStarted,
          setBridgeSyncStarted: (value: boolean): void => { this.bridgeSyncStarted = value },
          selftestEnabled: (): boolean => this.SELFTEST,
          runSelftest: (): void => this.selfTestCtl().selfTestAllActions(),
          restoreObserverLocation: (): void => { this.locationCtl().restoreObserverLocation() },
          setScriptMetadata: (raw: Object | undefined): void => { this.scriptPlaybackCtl().setScriptMetadata(raw) },
          reloadConfigurationSettings: (): void => { this.settingsCtl().loadConfigurationSettings() },
          // 引擎启动确认后由 StartupBridge 调用；立即读引擎状态，不排队、不延时。
          refreshRuntimeState: (): void => { this.engineReady = true; this.refreshStateNow() },
          // Startbridge 的「引擎就绪」以 StelApp::isInitialized() 为准：
          // 出帧就绪可能早于 init 完成，提前投放查询会在 init 期间堆积重试链。
          enginePresentationReady: (): boolean => isEngineReady()
        },
        this.skyCultureViewStore, this.pluginStore, this.nightModeStore, this.telescopeStore,
        this.gyroStore, this.languageStore, this.audioStore, this.viewSettingsStore,
        this.overlayStore, this.astroStore, this.layerViewStore, this.scriptStore,
        this.layerStore
      )
    }
    return this.startupBridgeImpl
  }

  // 传感器/陀螺仪控制器惰性构造。端口/桥/store 与宿主 hooks 在此注入，
  // 控制器不 import NAPI/UI。watchLastSend 属 保留字段，经 hooks 读写。
  private gyroCtl(): SensorController {
    if (this.sensorControllerImpl === null) {
      const hooks: SensorHostHooks = {
        canUseSensors: (): boolean => this.privacyNativeStartupAllowed && this.applicationInForeground && hasCurrentPrivacyConsent(),
        flashHint: (text: ResourceStr): void => this.flashHint(text),
        displayRotation: (): number => {
          try {
            return Number(display.getDefaultDisplaySync().rotation)
          } catch (error) {
            hilog.warn(0x0000, 'StellariumArkUI', '[gyro-probe] displayRotation unavailable')
            return -1
          }
        },
        objectSelected: (): boolean => this.objectDetailStore.selectedStatus === 'Selected',
        guideLayout: (): GyroGuideLayout => {
          const layout: GyroGuideLayout = {
            isExpandedLayout: this.isExpandedLayout,
            panelVisible: this.panelVisible,
            panelOffsetX: this.panelOffsetX,
            panelWidth: this.panelWidth,
            edgeMargin: this.EDGE_MARGIN,
            skyWidth: this.skyWidth,
            skyHeight: this.skyHeight,
            isFoldHoverLayout: this.isFoldHoverLayout,
            fovSliderValue: this.fovSliderValue
          }
          return layout
        },
        guideProjection: (): GyroGuideProjection | undefined => {
          const projection = this.callNative('getGyroGuidePosition') as GyroGuideProjection
          return projection
        },
        watchLastSend: (): number => this.watchLastSend,
        setWatchLastSend: (value: number): void => { this.watchLastSend = value }
      }
      this.sensorControllerImpl = new SensorController(
        this.gyroStore, this.hostSensorPort, this.commandPort(), this.sessionToolStore, hooks
      )
    }
    return this.sensorControllerImpl
  }

  // 通知/后台提醒控制器惰性构造。状态已在 NotificationStore（只搬行为）；
  // UI 提示、UIAbility 上下文、年历节气快照与加载触发经 hooks 回注。
  private notificationCtl(): NotificationController {
    if (this.notificationControllerImpl === null) {
      const hooks: NotificationHostHooks = {
        flashHint: (text: ResourceStr): void => this.flashHint(text),
        hostContext: (): common.UIAbilityContext => this.getUIContext().getHostContext() as common.UIAbilityContext,
        almanacSolarTerms: (): SeasonEvent[] => this.astroStore.almanacSolarTerms,
        loadAlmanac: (): void => { this.astroCalcCtl().loadAlmanac() }
      }
      this.notificationControllerImpl = new NotificationController(this.notificationStore, hooks)
    }
    return this.notificationControllerImpl
  }

  // 巡天 / 多波段图层控制器惰性构造。状态已在 SurveyStore（只搬行为）；
  // 巡天开关回写 LayerStore、UI 提示经 hooks 回注。
  private surveyCtl(): SurveyController {
    if (this.surveyControllerImpl === null) {
      const hooks: SurveyHostHooks = {
        applySurveyFlags: (hipsEnabled: boolean, toastEnabled: boolean): void => {
          this.layerStore.hipsSurveys = hipsEnabled
          this.layerStore.toastSurvey = toastEnabled
        },
        flashHint: (text: ResourceStr): void => this.flashHint(text)
      }
      this.surveyControllerImpl = new SurveyController(this.surveyStore, this.commandPort(), hooks)
    }
    return this.surveyControllerImpl
  }

  // AR 预研控制器惰性构造。状态已在 ARStore（只搬行为）；UI 提示经 hooks 回注。
  private arCtl(): ARController {
    if (this.arControllerImpl === null) {
      const hooks: ARHostHooks = {
        flashHint: (text: ResourceStr): void => this.flashHint(text)
      }
      this.arControllerImpl = new ARController(this.arStore, this.commandPort(), hooks)
    }
    return this.arControllerImpl
  }

  // 键盘快捷键控制器惰性构造。状态已在 KeyboardShortcutStore（只搬行为）。
  private keyboardShortcutCtl(): KeyboardShortcutController {
    if (this.keyboardShortcutControllerImpl === null) {
      const hooks: KeyboardShortcutHostHooks = {
        flashHint: (text: ResourceStr): void => this.flashHint(text)
      }
      this.keyboardShortcutControllerImpl = new KeyboardShortcutController(this.keyboardShortcutStore, this.commandPort(), hooks)
    }
    return this.keyboardShortcutControllerImpl
  }

  // 时间平滑过渡控制器惰性构造。
  private timeTransitionCtl(): TimeTransitionController {
    if (this.timeTransitionControllerImpl === null) {
      const hooks: TimeTransitionHostHooks = {
        flashHint: (text: ResourceStr): void => this.flashHint(text),
        getSimulationTime: (onOk: (jd: number, timeRate: number) => void, onFailure: () => void): void => {
          this.commandPort().requestInteractive('getSimulationTime', '', (r: StellariumBridgeResponse) => {
            if (r.ok !== true) { onFailure(); return }
            onOk(Number(r.jd), Number(r.timeRate ?? 0))
          }, () => onFailure())
        },
        setTimeRate: (rate: number): void => { this.timeCtl().setTimeRate(rate) },
        syncTimeRateState: (rate: number): void => { this.timeCtl().syncTimeRateState(rate) },
        syncWheelFromSimulation: (jd: number): void => { this.wheel().syncFromSimulation(jd) },
        refreshTimeNow: (): void => { this.timeCtl().refreshTimeNow() },
        refreshState: (): void => { this.refreshState() }
      }
      this.timeTransitionControllerImpl = new TimeTransitionController(this.commandPort(), hooks)
    }
    return this.timeTransitionControllerImpl
  }

  // 录制/回放/录屏控制器惰性构造。状态已在 ScriptStore（只搬行为与定时器）；
  // recordBuffer 属 保留字段，经 hooks 读写。
  private recordingCtl(): RecordingController {
    if (this.recordingControllerImpl === null) {
      const hooks: RecordingHostHooks = {
        flashHint: (text: ResourceStr): void => this.flashHint(text),
        sessionBusy: (): boolean => this.scriptStore.scriptSessionActive(this.tools.recording, this.guideStore.guideState.active),
        hidePanelAndInfo: (): void => {
          this.panelVisible = false
          this.infoWindowStore.infoWinVisible = false
        },
        openScriptsPanel: (): void => { this.setPanel('scripts') },
        changeScriptRate: (direction: number): void => { this.scriptPlaybackCtl().changeScriptRate(direction) },
        loadRecordings: (): void => { this.scriptPlaybackCtl().loadRecordings() },
        startVideoStatePolling: (): void => { this.scriptPlaybackCtl().startVideoStatePolling() },
        stopVideoStatePolling: (): void => { this.scriptPlaybackCtl().stopVideoStatePolling() },
        recordBufferLength: (): number => this.recordBuffer.length,
        recordBufferSnapshot: (): Array<RecordCmd> => this.recordBuffer,
        recordBufferPush: (cmd: RecordCmd): void => { this.recordBuffer.push(cmd) },
        recordBufferClear: (): void => { this.recordBuffer = [] }
      }
      this.recordingControllerImpl = new RecordingController(
        this.scriptStore, this.tools, this.commandPort(), this.hostMediaPort, hooks
      )
    }
    return this.recordingControllerImpl
  }

  // 对象检查器三维模型渲染器惰性构造。MediaPort / 三个 store / UI 与媒体管线保留字段
  // 经 hooks 注入，控制器不 import NAPI/UI。
  private objectModelRendererCtl(): ObjectModelRenderer {
    if (this.objectModelRendererImpl === null) {
      const hooks: ObjectModelRendererHostHooks = {
        publishModelView: (json: string): void => { AppStorage.setOrCreate('stellariumObjectModelView', json) },
        animateOverlay: (open: boolean, body: () => void, onFinish: () => void): void => {
          this.getUIContext().animateTo(open
            ? { duration: 220, curve: Curve.EaseOut }
            : { duration: 180, curve: Curve.EaseIn, onFinish: onFinish }, body)
        },
        mediaDecodeGeneration: (): number => this.objectInspectorMediaCtl().mediaDecodeGeneration(),
        proceduralParticles: (): number[][] => this.objectInspectorMediaCtl().proceduralParticles(),
        resetProcedural: (): void => { this.objectInspectorMediaCtl().resetProcedural() }
      }
      this.objectModelRendererImpl = new ObjectModelRenderer(
        this.objectMediaStore, this.objectDetailStore, this.infoWindowStore, this.hostMediaPort, hooks
      )
    }
    return this.objectModelRendererImpl
  }

  // /天空输入控制器惰性构造。桥 fire 经同一 HostCommandPort；宿主保留动作（isUiPoint /
  // skyZoomButtonAt / dockActionAt 热路径、路由/选中/缩放/详情刷新收放/Dock/陀螺退出/面板拖动落盘）
  // 经 SkyInputHostHooks 具名注入，控制器不 import NAPI/UI。
  private skyInputCtl(): SkyInputController {
    if (this.skyInputControllerImpl === null) {
      const hooks: SkyInputHostHooks = {
        isUiPoint: (x: number, y: number): boolean => this.isUiPoint(x, y),
        flashHint: (text: string): void => this.flashHint(text),
        skyWidth: (): number => this.skyWidth,
        skyHeight: (): number => this.skyHeight,
        navigationMouseEnabled: (): boolean => this.navigationStore.navigationMouseEnabled,
        navigationMouseZoomEnabled: (): boolean => this.navigationStore.navigationMouseZoomEnabled,
        gyroscopeEnabled: (): boolean => this.gyroStore.gyroscopeEnabled,
        stopGyroscope: (updateStatus: boolean): void => this.gyroCtl().stopGyroscope(updateStatus),
        angleMeasureEnabled: (): boolean => this.tools.angleMeasureEnabled,
        measureAngleAt: (x: number, y: number): void => this.measureAngleAt(x, y),
        requestSkySelection: (x: number, y: number): void => this.requestSkySelection(x, y),
        clearSkySelectionFromDoubleTap: (x: number, y: number): void => this.clearSkySelectionFromDoubleTap(x, y),
        zoomStep: (factor: number): void => this.zoomStep(factor),
        setPanel: (panel: string): void => this.setPanel(panel),
        closePanel: (): void => this.closePanel(),
        moveToSelectedObject: (): void => this.moveToSelectedObject(),
        centerSelectedObjectFromKeyboard: (): void => this.centerSelectedObjectFromKeyboard(),
        persistNightMode: (): void => this.nightModeStore.persistNightMode(),
        modelImmersive: (): boolean => this.objectMediaStore.objectInspectorModelImmersive,
        setModelImmersive: (value: boolean): void => this.objectModelRendererCtl().setObjectInspectorModelImmersive(value),
        // ── 触屏主路径（handleSkyTouch / emitFluidDrag）hooks ──
        isExpandedLayout: (): boolean => this.isExpandedLayout,
        isFoldHoverLayout: (): boolean => this.isFoldHoverLayout,
        isFoldTabletLayout: (): boolean => this.isFoldTabletLayout,
        panelVisible: (): boolean => this.panelVisible,
        panelWidth: (): number => this.panelWidth,
        panelOffsetX: (): number => this.panelOffsetX,
        panelOffsetY: (): number => this.panelOffsetY,
        edgeMargin: (): number => this.EDGE_MARGIN,
        fovSliderValue: (): number => this.fovSliderValue,
        setFovSliderValue: (value: number): void => { this.fovSliderValue = value },
        polarScopeVisible: (): boolean => this.polarScopeStore.polarScopeVisible,
        compactDockWidthPercent: (): number => this.compactDockWidthPercent(),
        dockTop: (): number => this.dockTop(),
        dockHeight: (): number => this.dockHeight(),
        keyboardTextInputFocused: (): boolean => this.keyboardTextInputFocused,
        compactTopQuickX: (): number => this.compactTopQuickX(),
        isCompactTopQuickPoint: (x: number, y: number): boolean => this.isCompactTopQuickPoint(x, y),
        lastInfoWinCloseMs: (): number => this.lastInfoWinCloseMs,
        touchStartedOnUi: (): boolean => this.touchStartedOnUi,
        setTouchStartedOnUi: (value: boolean): void => { this.touchStartedOnUi = value },
        skyTouchActive: (): boolean => this.skyTouchActive,
        setSkyTouchActive: (value: boolean): void => { this.skyTouchActive = value },
        setSkyDragging: (value: boolean): void => { this.skyDragging = value },
        dockTouchActive: (): boolean => this.dockTouchActive,
        setDockTouchActive: (value: boolean): void => { this.dockTouchActive = value },
        skyTouchFeedback: (): boolean => this.skyTouchFeedback,
        setSkyTouchFeedback: (value: boolean): void => { this.skyTouchFeedback = value },
        setSkyTouchPoint: (x: number, y: number): void => { this.skyTouchX = x; this.skyTouchY = y },
        setSkyTouchPoint2: (x: number, y: number): void => { this.skyTouchX2 = x; this.skyTouchY2 = y },
        skyTouchX2: (): number => this.skyTouchX2,
        skyTouchY2: (): number => this.skyTouchY2,
        setSkyTouchFeedbackMulti: (value: boolean): void => { this.skyTouchFeedbackMulti = value },
        setCurrentFovText: (text: string): void => { this.currentFovText = text },
        setPanelOffset: (offsetX: number, offsetY: number): void => { this.panelOffsetX = offsetX; this.panelOffsetY = offsetY },
        cancelSelectedObjectUiChange: (): void => this.cancelSelectedObjectUiChange(),
        pauseDetailRefreshForSkyDrag: (): void => this.detailConnectorCtl().pauseDetailRefreshForSkyDrag(),
        resumeDetailRefreshAfterSkyDrag: (): void => this.detailConnectorCtl().resumeDetailRefreshAfterSkyDrag(),
        scheduleSelectedObjectForUiChange: (delay: number): void => this.scheduleSelectedObjectForUiChange(delay),
        scheduleSkyTextureStatusCheck: (): void => this.skyTextureStatusCtl().start(),
        scheduleRecordingViewCheckpoint: (delay: number): void => this.recordingCtl().scheduleRecordingViewCheckpoint(delay),
        resetPanelIdle: (): void => this.resetPanelIdle(),
        toggleMusic: (): void => this.audioStore.toggleMusic(),
        musicHintText: (): string => this.audioStore.musicEnabled ? I18n.t('music_on_hint') : I18n.t('music_off_hint'),
        toggleGyroscope: (value: boolean): void => this.gyroCtl().requestGyroscopeToggle(value),
        skyZoomButtonAt: (x: number, y: number): string => this.skyZoomButtonAt(x, y),
        dockActionAt: (x: number, y: number): ShellAction | null => this.dockActionAt(x, y),
        activateDockAction: (item: ShellAction): void => this.activateDockAction(item),
        requestFieldOfView: (onResult: (fov: number) => void): void => {
          this.callInteractive('getFieldOfView', '', (r: StellariumBridgeResponse) => {
            if (r.ok === true && r.fov !== undefined) { onResult(r.fov) }
          })
        }
      }
      this.skyInputControllerImpl = new SkyInputController(this.commandPort(), this.nightModeStore, hooks)
    }
    return this.skyInputControllerImpl
  }

  // 位置域控制器惰性构造。NAPI（权限/定位/preferences）经 HostLocationPort；跨域写
  // （SessionToolStore.observerPlanet、位置头部三 @State）与 GPS 门禁经 LocationHostHooks 注入。
  private locationCtl(): LocationController {
    if (this.locationControllerImpl === null) {
      const hooks: LocationHostHooks = {
        flashHint: (text: ResourceStr): void => this.flashHint(text),
        refreshState: (): void => { this.refreshState() },
        loadObserverInfo: (): void => { this.locationPickerStore.loadObserverInfo(true) },
        setObserverPlanetCrossStore: (name: string): void => { this.sessionToolStore.observerPlanet = name },
        setLocationTexts: (location: string, coordinate: string, altitude: string): void => {
          this.locationText = location
          this.coordinateText = coordinate
          this.altitudeText = altitude
        },
        privacyAllowed: (): boolean => this.privacyNativeStartupAllowed,
        inForeground: (): boolean => this.applicationInForeground,
        hasPrivacyConsent: (): boolean => hasCurrentPrivacyConsent()
      }
      this.locationControllerImpl = new LocationController(
        this.commandPort(), this.hostLocationPort, this.locationPickerStore, this.locationStore, this.sessionToolStore, hooks
      )
    }
    return this.locationControllerImpl
  }

  // 行为控制器共享宿主 hook（STATE-；后续 D 轨道控制器接口 extends BehaviorHostHooks）。
  private behaviorHooks(): BehaviorHostHooks {
    return {
      refreshState: (): void => { this.refreshState() },
      flashHint: (text: ResourceStr): void => { this.flashHint(text) },
      panelChange: (panel: string, visible: boolean): void => {
        this.activePanel = panel
        this.panelVisible = visible
        this.syncDockClockTimer()
      }
    }
  }

  // 详情连接线 / 详情刷新定时器控制器惰性构造。指向线几何 9 个 @State 与过渡开关由宿主持有、
  // 经 hooks 逐帧 get/set；面板/星图状态、几何派生、宿主保留控制器
  // （objectDetailConnectorObstacles / refreshSelectedObject / scheduleSkyTextureStatusCheck）经 hooks 注入。
  private detailConnectorCtl(): DetailConnectorController {
    if (this.detailConnectorControllerImpl === null) {
      const hooks: DetailConnectorHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        },
        activePanel: (): string => this.activePanel,
        panelVisible: (): boolean => this.panelVisible,
        skyDragging: (): boolean => this.skyDragging,
        skyWidth: (): number => this.skyWidth,
        skyHeight: (): number => this.skyHeight,
        isFoldHoverLayout: (): boolean => this.isFoldHoverLayout,
        bottomCardY: (): number => this.bottomCardY(),
        hoverBottomCardY: (): number => this.hoverBottomCardY(),
        detailCardX: (): number => this.detailCardX(),
        detailCardY: (): number => this.detailCardY(),
        detailCardWidth: (): number => this.detailCardWidth(),
        detailCardHeight: (): number => this.detailCardHeight(),
        objectDetailConnectorObstacles: (): SkyUiObstacle[] => this.objectDetailConnectorObstacles(),
        refreshSelectedObject: (): void => { this.refreshSelectedObject() },
        scheduleSkyTextureStatusCheck: (): void => { this.skyTextureStatusCtl().start() },
        gyroGuideProjection: (): GyroGuideProjection => this.callNative('getGyroGuidePosition') as GyroGuideProjection,
        connectorVisible: (): boolean => this.overlayStore.objectDetailConnectorVisible,
        connectorX: (): number => this.objectDetailConnectorX,
        setConnectorX: (value: number): void => { this.objectDetailConnectorX = value },
        connectorY: (): number => this.objectDetailConnectorY,
        setConnectorY: (value: number): void => { this.objectDetailConnectorY = value },
        connectorLength: (): number => this.objectDetailConnectorLength,
        setConnectorLength: (value: number): void => { this.objectDetailConnectorLength = value },
        connectorAngle: (): number => this.objectDetailConnectorAngle,
        setConnectorAngle: (value: number): void => { this.objectDetailConnectorAngle = value },
        connectorEndX: (): number => this.objectDetailConnectorEndX,
        setConnectorEndX: (value: number): void => { this.objectDetailConnectorEndX = value },
        connectorEndY: (): number => this.objectDetailConnectorEndY,
        setConnectorEndY: (value: number): void => { this.objectDetailConnectorEndY = value },
        connectorTargetX: (): number => this.objectDetailConnectorTargetX,
        setConnectorTargetX: (value: number): void => { this.objectDetailConnectorTargetX = value },
        connectorTargetY: (): number => this.objectDetailConnectorTargetY,
        setConnectorTargetY: (value: number): void => { this.objectDetailConnectorTargetY = value },
        connectorTargetOnScreen: (): boolean => this.objectDetailConnectorTargetOnScreen,
        setConnectorTargetOnScreen: (value: boolean): void => { this.objectDetailConnectorTargetOnScreen = value },
        setConnectorAnimateGeometry: (value: boolean): void => { this.objectDetailConnectorAnimateGeometry = value }
      }
      this.detailConnectorControllerImpl = new DetailConnectorController(this.objectDetailStore, this.infoWindowStore, hooks)
    }
    return this.detailConnectorControllerImpl
  }

  // 图层 / 视图标签控制器惰性构造。桥经 HostCommandPort；标签 @State 与两组过渡量由宿主持有、
  // 经 hooks 读写；标签切换动画的 getUIContext().animateTo 归宿主，经
  // animateTabIn / animateTabOut 注入（控制器不 import UI）。
  private layerCtl(): LayerController {
    if (this.layerControllerImpl === null) {
      const hooks: LayerHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        },
        setTrackingText: (value: string): void => { this.trackingText = value },
        setLandscapeDetailOpen: (value: boolean): void => { this.landscapeDetailOpen = value },
        persistEquatorialMount: (): void => { this.telescopeStore.persistEquatorialMount() },
        persistNightMode: (): void => { this.nightModeStore.persistNightMode() },
        applyNightMode: (enabled: boolean): void => { this.nightModeStore.applyNightMode(enabled, true) },
        syncSkyCultureTimeFollowTimer: (): void => { this.skyCultureCtl().syncSkyCultureTimeFollowTimer() },
        loadScriptList: (): void => { this.scriptPlaybackCtl().loadScriptList() },
        loadRecordings: (): void => { this.scriptPlaybackCtl().loadRecordings() },
        loadVideoRecordingState: (): void => { this.scriptPlaybackCtl().loadVideoRecordingState() },
        refreshNotificationStatus: (): void => { this.notificationCtl().refreshStatus() },
        loadSurveyState: (): void => { this.surveyCtl().loadSurveyState() },
        loadKeyboardShortcuts: (): void => { this.keyboardShortcutCtl().load() },
        viewTab: (): number => this.viewTab,
        setViewTab: (value: number): void => { this.viewTab = value },
        viewTabContentOpacity: (): number => this.viewTabContentOpacity,
        setViewTabContentOpacity: (value: number): void => { this.viewTabContentOpacity = value },
        viewTabContentOffsetX: (): number => this.viewTabContentOffsetX,
        setViewTabContentOffsetX: (value: number): void => { this.viewTabContentOffsetX = value },
        configTab: (): number => this.configTab,
        setConfigTab: (value: number): void => { this.configTab = value },
        configTabContentOpacity: (): number => this.configTabContentOpacity,
        setConfigTabContentOpacity: (value: number): void => { this.configTabContentOpacity = value },
        configTabContentOffsetX: (): number => this.configTabContentOffsetX,
        setConfigTabContentOffsetX: (value: number): void => { this.configTabContentOffsetX = value },
        animateTabIn: (durationMs: number, onFinish: () => void, action: () => void): void => {
          this.getUIContext().animateTo({ duration: durationMs, curve: Curve.EaseIn, onFinish: onFinish }, action)
        },
        animateTabOut: (durationMs: number, action: () => void): void => {
          this.getUIContext().animateTo({ duration: durationMs, curve: Curve.EaseOut }, action)
        }
      }
      this.layerControllerImpl = new LayerController(
        this.commandPort(), this.hostMediaPort, this.layerViewStore, this.layerStore,
        this.sceneryStore, this.objectDetailStore, this.viewSettingsStore,
        this.scriptStore, this.pluginStore, hooks
      )
    }
    return this.layerControllerImpl
  }

  // SkyTexture 状态观察控制器惰性构造。桥经 HostCommandPort；状态条四字段写 ToolsStore；
  // 定时器自持 start()/stop()，宿主生命周期（aboutToDisappear / 缩放后触发）改调入口。
  private skyTextureStatusCtl(): SkyTextureStatusController {
    if (this.skyTextureStatusControllerImpl === null) {
      const hooks: SkyTextureStatusHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        }
      }
      this.skyTextureStatusControllerImpl = new SkyTextureStatusController(this.commandPort(), this.tools, hooks)
    }
    return this.skyTextureStatusControllerImpl
  }

  // 星云纹理控制器惰性构造。桥经 HostCommandPort；picker/fileIo 导入段经 HostMediaPort；
  // 状态整体写 NebulaTextureStore（面板 @ObjectLink 消费）。
  private nebulaTextureCtl(): NebulaTextureController {
    if (this.nebulaTextureControllerImpl === null) {
      const hooks: NebulaTextureHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        }
      }
      this.nebulaTextureControllerImpl = new NebulaTextureController(
        this.commandPort(), this.hostMediaPort, this.nebulaTextureStore, hooks
      )
    }
    return this.nebulaTextureControllerImpl
  }

  // 星空文化行为控制器惰性构造（选择/标签/视觉 + 时间跟随 + Art 预览）。桥经 HostCommandPort；
  // fileIo/image 经 HostMediaPort / common/media/ImageDecoder；详情加载器（永久保由宿主持有）与共享请求
  // 序号、渐进字段、UI 上下文派生量、标签下拉动画、锚点校正滚动经 hooks 注入。
  private skyCultureCtl(): SkyCultureController {
    if (this.skyCultureControllerImpl === null) {
      const hooks: SkyCultureHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        },
        loadSkyCultureDetails: (): void => { this.loadSkyCultureDetails() },
        skyCultureDetailsRequestId: (): number => this.skyCultureDetailsRequestId,
        nextSkyCultureDetailsRequestId: (): number => { return ++this.skyCultureDetailsRequestId },
        skyCultureActiveColorTarget: (): string => this.skyCultureActiveColorTarget(),
        skyCultureArtStates: (): Record<string, string> => this.skyCultureArtStates,
        setSkyCultureArtStates: (next: Record<string, string>): void => { this.skyCultureArtStates = next },
        skyCultureArtThumbnailPixelMaps: (): Record<string, image.PixelMap> => this.skyCultureViewStore.artThumbnails,
        setSkyCultureArtThumbnailPixelMaps: (next: Record<string, image.PixelMap>): void => { this.skyCultureViewStore.artThumbnails = next },
        stellariumFilesDir: (): string => this.stellariumFilesDir(),
        pathToUri: (path: string): string => fileUri.getUriFromPath(path),
        resolveDetailMediaAsset: (relativePath: string): Promise<string> => {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext
          return resolveStellariumDetailMediaAsset(context.getApplicationContext(), relativePath)
        },
        shouldFollowSkyCultureSimulationTime: (): boolean => this.shouldFollowSkyCultureSimulationTime(),
        animatePickerCollapse: (action: () => void): void => {
          this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion(0.46, 0.86) }, action)
        },
        correctSkyCultureRowScroll: (id: string, delta: number): void => { this.correctSkyCultureRowScroll(id, delta) }
      }
      this.skyCultureControllerImpl = new SkyCultureController(
        this.commandPort(), this.hostMediaPort, this.skyCultureViewStore, this.skyCultureSettingsStore, hooks
      )
    }
    return this.skyCultureControllerImpl
  }

  // 星空文化制作器控制器惰性构造。桥经 HostCommandPort；picker/fileIo 经 HostMediaPort；
  // 图片解码经 common/media/ImageDecoder；filesDir 经 hooks 注入；自动保存定时器与画布触摸草稿自持。
  private skyCultureMakerCtl(): SkyCultureMakerController {
    if (this.skyCultureMakerControllerImpl === null) {
      const hooks: SkyCultureMakerHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        },
        stellariumFilesDir: (): string => this.stellariumFilesDir()
      }
      this.skyCultureMakerControllerImpl = new SkyCultureMakerController(
        this.commandPort(), this.hostMediaPort, this.skyCultureMakerStore, hooks
      )
    }
    return this.skyCultureMakerControllerImpl
  }

  // 目镜/拼接相机/均时差/古天文线写回控制器惰性构造。桥经 HostCommandPort；
  // 状态整体写 TelescopeStore / MosaicStore / EquationOfTimeStore / ArchaeoStore；无 UI hook。
  private ocularCtl(): OcularController {
    if (this.ocularControllerImpl === null) {
      this.ocularControllerImpl = new OcularController(
        this.commandPort(), this.telescopeStore, this.mosaicStore, this.equationOfTimeStore, this.archaeoStore
      )
    }
    return this.ocularControllerImpl
  }

  // LX200 望远镜编辑器/控制命令控制器惰性构造。桥经 HostCommandPort；状态写 TelescopeStore；
  // live-position 定时器簇由控制器自持；「是否应刷新实时位置」谓词经 hooks 注入。
  private telescopeCtl(): TelescopeController {
    if (this.telescopeControllerImpl === null) {
      const hooks: TelescopeHostHooks = {
        shouldRefreshTelescopePosition: (): boolean => this.shouldRefreshTelescopePosition()
      }
      this.telescopeControllerImpl = new TelescopeController(this.commandPort(), this.telescopeStore, hooks)
    }
    return this.telescopeControllerImpl
  }

  // 极轴镜行为控制器惰性构造。桥经 HostCommandPort；状态写 PolarScopeStore；
  // 面板路由 / refreshState / flashHint 经 BehaviorHostHooks；叠层几何与桥回包 flags 抽取
  //（宿主 getUIContext().px2vp 与 `as Record<...>`）经宿主 hooks 注入（控制器禁 as）。
  private polarScopeCtl(): PolarScopeController {
    if (this.polarScopeControllerImpl === null) {
      const hooks: PolarScopeHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        },
        applicationInForeground: (): boolean => this.applicationInForeground,
        skyHeight: (): number => this.skyHeight,
        screenSafeTopPixels: (): number => this.screenSafeTopPixels,
        polarScopeTopInset: (): number => this.polarScopeTopInset(),
        polarScopeFooterHeight: (): number => this.polarScopeFooterHeight(),
        polarScopeSessionFlags: (response: StellariumBridgeResponse): PolarScopeSessionFlags => {
          const flags = response.flags as Record<string, Object>
          const location = response.location as Record<string, Object>
          const result: PolarScopeSessionFlags = {
            horizontalFlip: flags !== undefined && flags['flipHorz'] === true,
            verticalFlip: flags !== undefined && flags['flipVert'] === true,
            planetName: response.location && location['planetName'] !== undefined ? String(location['planetName']) : 'Earth'
          }
          return result
        }
      }
      this.polarScopeControllerImpl = new PolarScopeController(this.commandPort(), this.polarScopeStore, hooks)
    }
    return this.polarScopeControllerImpl
  }

  // 视图中心坐标叠层行为控制器惰性构造。桥经 HostCommandPort；开关/坐标系/历元写 OverlayStore；
  // 叠层 4 个 @State 与 5 个 A-保留几何方法经宿主 hooks 读写；
  // applicationInForeground / saveAppSettings / stopSkyInertia 经 hooks 注入。
  private viewCoordinateCtl(): ViewCoordinateController {
    if (this.viewCoordinateControllerImpl === null) {
      const hooks: ViewCoordinateHostHooks = {
        applicationInForeground: (): boolean => this.applicationInForeground,
        saveAppSettings: (): void => { this.saveAppSettings() },
        stopSkyInertia: (): void => { this.skyInputCtl().stopSkyInertia() },
        viewCoordinateOffsetX: (): number => this.viewCoordinateOffsetX,
        setViewCoordinateOffsetX: (value: number): void => { this.viewCoordinateOffsetX = value },
        viewCoordinateOffsetY: (): number => this.viewCoordinateOffsetY,
        setViewCoordinateOffsetY: (value: number): void => { this.viewCoordinateOffsetY = value },
        setViewCoordinatePrimaryText: (text: string): void => { this.viewCoordinatePrimaryText = text },
        setViewCoordinateSecondaryText: (text: string): void => { this.viewCoordinateSecondaryText = text },
        viewCoordinateRestOffsetX: (): number => this.clampedViewCoordinateOffsetX(Math.max(16, (this.skyWidth - this.viewCoordinateOverlayWidth()) / 2)),
        viewCoordinateRestOffsetY: (): number => this.clampedViewCoordinateOffsetY(this.isFoldHoverLayout ? 52 : (this.isExpandedLayout ? 64 : 102))
      }
      this.viewCoordinateControllerImpl = new ViewCoordinateController(this.commandPort(), this.overlayStore, hooks)
    }
    return this.viewCoordinateControllerImpl
  }

  // 卫星行为控制器惰性构造。桥经 HostCommandPort；状态整体写 SatelliteStore；
  // 分组过渡动画与 CLI 发布点 publishSatellitePanelState（保留）经宿主 hooks 注入。
  private satelliteCtl(): SatelliteController {
    if (this.satelliteControllerImpl === null) {
      const hooks: SatelliteHostHooks = {
        publishSatellitePanelState: (error: string): void => { this.publishSatellitePanelState(error) },
        animateSatelliteGroupChange: (action: () => void): void => {
          this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, action)
        }
      }
      this.satelliteControllerImpl = new SatelliteController(this.commandPort(), this.satelliteStore, hooks)
    }
    return this.satelliteControllerImpl
  }

  // 天文计算行为控制器惰性构造。桥经 HostCommandPort；picker/fileIo 经 HostMediaPort；
  // 状态在 astro/ephemeris/wut/search store；DatePicker/animateTo/Scroller/tab 过渡与保由宿主持有方法
  // （publishAstroPanelState / applySelectedObject）经宿主 hooks 注入；applyAtmosphereResponse 直接写
  // AtmosphereStore（并回 store）。
  private astroCalcCtl(): AstroCalcController {
    if (this.astroCalcControllerImpl === null) {
      const hooks: AstroCalcHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        },
        publishAstroPanelState: (): void => { this.publishAstroPanelState() },
        astroPanelContextActive: (): boolean => this.applicationInForeground && this.activePanel === 'astro' && this.panelVisible,
        astroPanelOnScreen: (): boolean => this.panelVisible && this.activePanel === 'astro',
        scrollAstroPanelToTop: (): void => { this.astroPanelScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false }) },
        saveAppSettings: (): void => { this.saveAppSettings() },
        animateAstroIn: (durationMs: number, onFinish: () => void, action: () => void): void => {
          this.getUIContext().animateTo({ duration: durationMs, curve: Curve.EaseIn, onFinish: onFinish }, action)
        },
        animateAstroOut: (durationMs: number, onFinish: () => void, action: () => void): void => {
          this.getUIContext().animateTo({ duration: durationMs, curve: Curve.EaseOut, onFinish: onFinish }, action)
        },
        showDatePicker: (selected: Date, onAccept: (year: number | undefined, month: number | undefined, day: number | undefined) => void): void => {
          this.getUIContext().showDatePickerDialog({
            start: new Date('1900-01-01'),
            end: new Date('2100-12-31'),
            selected: selected,
            onAccept: (value: DatePickerResult) => { onAccept(value.year, value.month, value.day) },
            onCancel: () => {}
          })
        },
        applySelectedObject: (result: StellariumBridgeResponse, fromRefresh: boolean, placement: string, userReselect: boolean): void => {
          this.applySelectedObject(result, fromRefresh, placement, userReselect)
        },
        setPanel: (panel: string): void => { this.setPanel(panel) },
        applyAtmosphereResponse: (result: StellariumBridgeResponse): void => { this.atmosphereStore.applyAtmosphereResponse(result) },
        hasSelectedObject: (): boolean => this.objectDetailStore.hasSelectedObject(),
        selectedObjectName: (): string => this.objectDetailStore.selectedName,
        hecLayoutPositions: (positions: Array<HeliocentricPosition>): Array<HeliocentricPosition> => hecLayoutPositions(positions),
        animateTimeToJd: (targetJd: number, label: string, onFinished?: () => void): void => { this.timeTransitionCtl().animate(targetJd, label, onFinished) },
        persistAlmanacCardSnapshot: (): void => { this.persistAlmanacCardSnapshot() }
      }
      this.astroCalcControllerImpl = new AstroCalcController(
        this.commandPort(), this.hostMediaPort, this.astroStore, this.ephemerisStore, this.wutStore, this.searchStore, hooks)
    }
    return this.astroCalcControllerImpl
  }

  // 交互导览行为控制器惰性构造。状态在 GuideStore（纯数据：guideState / speechStatus）；
  // 播放器与 250ms tick 定时器由控制器自持；桥经 HostCommandPort；面板/陀螺仪/后台任务互斥/
  // 刷新与重载/animateTo 经宿主 hooks 注入（控制器不触碰 UI 上下文）。
  private guideCtl(): GuideController {
    if (this.guideControllerImpl === null) {
      const hooks: GuideControllerHooks = {
        flashHint: (text: ResourceStr): void => this.flashHint(text),
        publishGuideState: (): void => this.publishGuideState(),
        sessionBusy: (): boolean => this.scriptStore.scriptSessionActive(this.tools.recording, this.guideStore.guideState.active),
        polarScopeVisible: (): boolean => this.polarScopeStore.polarScopeVisible,
        panelVisible: (): boolean => this.panelVisible,
        setPanelVisible: (value: boolean): void => { this.panelVisible = value },
        hideInfoWindow: (): void => { this.infoWindowStore.infoWinVisible = false },
        applicationInForeground: (): boolean => this.applicationInForeground,
        gyroscopeEnabled: (): boolean => this.gyroStore.gyroscopeEnabled,
        setGyroscopeEnabled: (value: boolean): void => { this.gyroStore.gyroscopeEnabled = value },
        startGyroscope: (): void => this.gyroCtl().startGyroscope(),
        stopGyroscope: (updateStatus: boolean): void => this.gyroCtl().stopGyroscope(updateStatus),
        stopSkyInertia: (): void => this.skyInputCtl().stopSkyInertia(),
        stopCompetingTasks: (): void => {
          this.detailConnectorCtl().stopDetailAutoRefresh()
          this.timeCtl().stopPanelTimers()
          this.skyCultureCtl().stopSkyCultureTimeFollowTimer()
          this.astroCalcCtl().stopAstroCalcContextTimer()
          this.telescopeCtl().stopTelescopeLivePosition(false)
        },
        refreshState: (): void => { this.refreshState() },
        reloadObserverInfo: (): void => { this.locationPickerStore.loadObserverInfo(true) },
        animateTo: (action: () => void): void => {
          this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, action)
        }
      }
      this.guideControllerImpl = new GuideController(this.commandPort(), this.guideStore, hooks)
    }
    return this.guideControllerImpl
  }

  // 设置「配置回读」控制器惰性构造：桥经 HostCommandPort；本域字段写 TimeSettingsStore；
  // 跨域字段经 TimeSettingsHostHooks 具名 setter 写入各域 store；无 publish* 发布点，故无 onChanged。
  // 控制器不 import UI/NAPI。
  private settingsCtl(): SettingsController {
    if (this.settingsControllerImpl === null) {
      const hooks: TimeSettingsHostHooks = {
        setUseMetricUnits: (value: boolean): void => { this.viewSettingsStore.useMetricUnits = value },
        setConfigDitheringMode: (mode: string): void => { this.viewSettingsStore.configDitheringMode = mode },
        setAutoZoomResets: (value: boolean): void => { this.viewSettingsStore.autoZoomResets = value },
        setNavigationMouseEnabled: (value: boolean): void => { this.navigationStore.navigationMouseEnabled = value },
        setNavigationMouseZoomEnabled: (value: boolean): void => { this.navigationStore.navigationMouseZoomEnabled = value },
        setNavigationMoveKeysEnabled: (value: boolean): void => { this.navigationStore.navigationMoveKeysEnabled = value },
        setNavigationZoomKeysEnabled: (value: boolean): void => { this.navigationStore.navigationZoomKeysEnabled = value },
        setNavigationGravityLabelsEnabled: (value: boolean): void => { this.navigationStore.navigationGravityLabelsEnabled = value },
        setNavigationStartupFov: (value: number): void => { this.navigationStore.navigationStartupFov = value },
        setNavigationStartupAzimuth: (value: number): void => { this.navigationStore.navigationStartupAzimuth = value },
        setNavigationStartupAltitude: (value: number): void => { this.navigationStore.navigationStartupAltitude = value },
        setNavigationMaxFov: (value: number): void => { this.navigationStore.navigationMaxFov = value },
        setEphemerisAvailability: (de430Available: boolean, de431Available: boolean, de440Available: boolean, de441Available: boolean): void => {
          this.ephemerisStore.ephemerisDe430Available = de430Available
          this.ephemerisStore.ephemerisDe431Available = de431Available
          this.ephemerisStore.ephemerisDe440Available = de440Available
          this.ephemerisStore.ephemerisDe441Available = de441Available
        },
        setEphemerisActive: (de430Active: boolean, de431Active: boolean, de440Active: boolean, de441Active: boolean): void => {
          this.ephemerisStore.ephemerisDe430Active = de430Active
          this.ephemerisStore.ephemerisDe431Active = de431Active
          this.ephemerisStore.ephemerisDe440Active = de440Active
          this.ephemerisStore.ephemerisDe441Active = de441Active
        },
        informationMode: (): string => this.infoWindowStore.informationMode,
        setInformationMode: (mode: string): void => { this.infoWindowStore.informationMode = mode },
        setInformationCustomMask: (mask: number): void => { this.infoWindowStore.informationCustomMask = mask },
        applySelectedInfoMode: (mode: string): void => this.applySelectedInfoMode(mode),
        applyTimeSettings: (response: StellariumBridgeResponse): void => this.timeCtl().applyTimeSettings(response)
      }
      this.settingsControllerImpl = new SettingsController(this.commandPort(), this.timeSettingsStore, hooks)
    }
    return this.settingsControllerImpl
  }

  // 插件功能行为控制器惰性构造。桥经 HostCommandPort；状态整体写 PluginStore；跨域路由
  // （astro/search store、viewTab 宿主 @State、openSubPanel 壳层路由）经宿主 hooks 注入。
  private pluginFeatureCtl(): PluginFeatureController {
    if (this.pluginFeatureControllerImpl === null) {
      const hooks: PluginFeatureHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        },
        refreshCatalogCategoriesIfSearchVisible: (): void => {
          if (this.activePanel === 'search') this.catalogStore.loadObjectCatalogCategories(this.languageStore.languageRefreshSerial)
        },
        setViewTab: (value: number): void => { this.viewTab = value },
        openSubPanel: (panel: string): void => { this.openSubPanel(panel) }
      }
      this.pluginFeatureControllerImpl = new PluginFeatureController(
        this.commandPort(), this.pluginStore, this.searchStore, this.astroStore, hooks)
    }
    return this.pluginFeatureControllerImpl
  }

  // 对象检查器媒体控制器惰性构造。解码经 MediaPort/ImageDecoder；UI 上下文派生量（filesDir /
  // pathToUri / 预热状态 / 媒体解析 / 准备失败）、三维渲染器实例经宿主 hooks 注入（控制器不 import NAPI/UI）。
  private objectInspectorMediaCtl(): ObjectInspectorMediaController {
    if (this.objectInspectorMediaControllerImpl === null) {
      const hooks: ObjectInspectorMediaHostHooks = {
        filesDir: (): string => this.stellariumFilesDir(),
        pathToUri: (path: string): string => fileUri.getUriFromPath(path),
        warmupStatus: (): DeepSkyWarmupStatus => {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext
          return getDeepSkyResourceWarmupStatus(context.getApplicationContext())
        },
        resolveDetailMediaAsset: (relativePath: string): Promise<string> => {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext
          return resolveStellariumDetailMediaAsset(context.getApplicationContext(), relativePath)
        },
        isPreparationFailed: (relativePath: string): boolean => {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext
          return isStellariumDetailMediaPreparationFailed(context.getApplicationContext(), relativePath)
        },
        objectModelRenderer: (): ObjectModelRenderer => this.objectModelRendererCtl()
      }
      this.objectInspectorMediaControllerImpl = new ObjectInspectorMediaController(
        this.objectMediaStore, this.objectDetailStore, this.hostMediaPort, hooks)
    }
    return this.objectInspectorMediaControllerImpl
  }

  // 脚本录制回放 UI 控制器惰性构造。桥经 HostCommandPort；脚本/录制状态在 ScriptStore、录制 UI
  // 开关在 ToolsStore；控制条几何/拖动落位、UI 动画、收尾重载经宿主 hooks 注入（控制器不 import UI）。
  private scriptPlaybackCtl(): ScriptPlaybackController {
    if (this.scriptPlaybackControllerImpl === null) {
      const hooks: ScriptPlaybackHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        },
        scriptControlSafeTop: (): number => this.scriptControlSafeTop(),
        isExpandedLayout: (): boolean => this.isExpandedLayout,
        skyWidth: (): number => this.skyWidth,
        skyHeight: (): number => this.skyHeight,
        guideCardWidth: (): number => this.guideCardWidth(),
        stopSkyInertia: (): void => this.skyInputCtl().stopSkyInertia(),
        guideActive: (): boolean => this.guideStore.guideState.active,
        dismissScriptOverlays: (): void => {
          this.panelVisible = false
          this.infoWindowStore.infoWinVisible = false
          this.gyroStore.gyroCalibPanelOpen = false
        },
        reloadObserverInfo: (): void => { this.locationPickerStore.loadObserverInfo(true) },
        loadPlanetList: (): void => { this.sessionToolStore.loadPlanetList() },
        sessionBusy: (): boolean => this.scriptStore.scriptSessionActive(this.tools.recording, this.guideStore.guideState.active),
        requestStopGuide: (): void => { this.guideCtl().executeGuideRequest('guideAction', 'stop') },
        finishReplay: (message: string): void => this.recordingCtl().finishRecordingReplay(message),
        stopBackgroundTimers: (): void => {
          this.timeCtl().stopPanelTimers()
          this.skyCultureCtl().stopSkyCultureTimeFollowTimer()
          this.polarScopeCtl().stopPolarScopeTimer()
        },
        logScriptError: (filename: string, error: string): void => {
          hilog.error(0x0000, 'StellariumArkUI', 'playScript failed %{public}s err=%{public}s', filename, error)
        },
        stopVideoRecording: (): void => { this.recordingCtl().stopVideoRecording() },
        animateWaiting: (action: () => void): void => {
          this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion(0.55, 0.90) }, action)
        },
        animateCaptions: (action: () => void): void => {
          this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, action)
        }
      }
      this.scriptPlaybackControllerImpl = new ScriptPlaybackController(
        this.scriptStore, this.tools, this.commandPort(), this.hostMediaPort, hooks)
    }
    return this.scriptPlaybackControllerImpl
  }

  // 时间操作控制器惰性构造。桥经 HostCommandPort；状态在 time/timeSettings/deltaT store；
  // 时间轮/儒略日同步、utcOffsetHours、timeSettingsPending 门控、UI 动画与 chip 跨域动作经 hooks 注入。
  private timeCtl(): TimeController {
    if (this.timeControllerImpl === null) {
      const hooks: TimeHostHooks = {
        refreshState: (): void => { this.refreshState() },
        flashHint: (text: ResourceStr): void => { this.flashHint(text) },
        panelChange: (panel: string, visible: boolean): void => {
          this.activePanel = panel
          this.panelVisible = visible
          this.syncDockClockTimer()
        },
        utcOffsetHours: (): number => this.utcOffsetHours,
        timeSettingsPending: (): boolean => this.timeSettingsPending,
        setTimeSettingsPending: (value: boolean): void => { this.timeSettingsPending = value },
        animateOption: (action: () => void): void => {
          this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, action)
        },
        syncWheelFromSimulation: (jd: number): void => { this.wheel().syncFromSimulation(jd) },
        syncJulianDateFields: (response: StellariumBridgeResponse, jd: number): void => { this.julianStore.syncJulianDateFields(response, jd) },
        refreshSelectedObject: (): void => { this.refreshSelectedObject() },
        moveToSelectedObject: (): void => { this.moveToSelectedObject() },
        setViewLockState: (locked: boolean): void => { this.layerCtl().setViewLockState(locked) },
        triggerAction: (actionId: string): void => { this.triggerAction(actionId) },
        searchObject: (name: string): void => { this.searchObject(name) },
        stopTracking: (): void => { this.stopTracking() },
        setLocation: (name: string, lat: number, lon: number, alt: number): void => { this.locationCtl().setLocation(name, lat, lon, alt) }
      }
      this.timeControllerImpl = new TimeController(
        this.timeStore, this.timeSettingsStore, this.deltaTStore, this.commandPort(), hooks)
    }
    return this.timeControllerImpl
  }

  // 搜索 / 筛选行为控制器惰性构造。桥经 HostCommandPort；可观测状态写 SearchStore；
  // 面板滚动复位 / animateTo 过渡（宿主 getUIContext）/ CLI 发布点 / 选中入口经 hooks 注入。
  private searchCtl(): SearchController {
    if (this.searchControllerImpl === null) {
      const hooks: SearchHostHooks = {
        animateFilterChange: (action: () => void): void => {
          this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, action)
        },
        resetSearchScroll: (): void => { this.searchPanelScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false }) },
        publishSearchBrowserState: (error: string): void => { this.publishSearchBrowserState(error) },
        searchObject: (name: string, catalogModuleId: string, exactSelectionPayload: string): void => {
          this.searchObject(name, catalogModuleId, exactSelectionPayload)
        }
      }
      this.searchControllerImpl = new SearchController(
        this.commandPort(), this.searchStore, this.catalogStore, this.languageStore, hooks)
    }
    return this.searchControllerImpl
  }

  // 自检行为控制器惰性构造（桥经 HostCommandPort；SELFTEST_ACTION_IDS 随控制器）。
  private selfTestCtl(): SelfTestController {
    if (this.selfTestControllerImpl === null) {
      this.selfTestControllerImpl = new SelfTestController(this.commandPort())
    }
    return this.selfTestControllerImpl
  }

// ===== AppStorage 发布/镜像与持久化助手 =====

  private saveAppSettings(): void {
    AppStorage.setOrCreate("stellariumSettings", JSON.stringify({
      nightMode: this.nightModeStore.nightMode,
      equatorialMount: this.telescopeStore.equatorialMount,
      gyroscopeEnabled: this.gyroStore.gyroscopeVisualEnabled(),
      gyroscopeSensitivityText: this.gyroStore.gyroscopeSensitivityText,
      selectedLanguage: this.languageStore.selectedLanguage,
      useMetricUnits: this.viewSettingsStore.useMetricUnits,
      musicEnabled: this.audioStore.musicEnabled,
      viewCoordinatesVisible: this.overlayStore.viewCoordinatesVisible,
      viewCoordinateFamily: this.overlayStore.viewCoordinateFamily,
      viewEquatorialEpoch: this.overlayStore.viewEquatorialEpoch,
      objectDetailConnectorVisible: this.overlayStore.objectDetailConnectorVisible,
      astroTab: this.astroStore.astroTab.toString(),
      astroGroup: this.astroStore.astroGroup.toString(),
      positionMode: this.astroStore.positionMode.toString(),
      celestialPositionCategory: this.astroStore.celestialPositionCategory,
      celestialPositionMagnitude: this.astroStore.celestialPositionMagnitude.toString(),
      celestialPositionHorizontal: this.astroStore.celestialPositionHorizontal.toString(),
      ephemerisMode: this.astroStore.ephemerisMode.toString(),
      ephemerisDays: this.astroStore.ephemerisDays.toString(),
      ephemerisStepHours: this.astroStore.ephemerisStepHours.toString(),
      rtsCalendarDays: this.astroStore.rtsCalendarDays.toString(),
      graphMode: this.astroStore.graphMode.toString(),
      eclipseMonths: this.astroStore.eclipseMonths.toString(),
      moonPhaseDays: this.astroStore.moonPhaseDays.toString()
    }))
    // 统一持久化：纯 UI 偏好写入 Preferences（stellarium_ui）。夜间模式、赤道仪是
    // 引擎行为，由各自的 C++ setter 写 config.ini，不进入 UI 仓库。
    this.settingsRepository.patch(this.collectUiSettings())
  }

  // 聚合当前纯 UI 偏好。字段与 SettingsRepository.UiSettings 一一对应。
  private collectUiSettings(): UiSettings {
    const current = this.settingsRepository.snapshot()
    const next: UiSettings = {
      schemaVersion: current.schemaVersion,
      musicEnabled: this.audioStore.musicEnabled,
      useMetricUnits: this.viewSettingsStore.useMetricUnits,
      viewCoordinatesVisible: this.overlayStore.viewCoordinatesVisible,
      viewCoordinateFamily: this.overlayStore.viewCoordinateFamily,
      viewEquatorialEpoch: this.overlayStore.viewEquatorialEpoch,
      objectDetailConnectorVisible: this.overlayStore.objectDetailConnectorVisible,
      astroTab: this.astroStore.astroTab,
      astroGroup: this.astroStore.astroGroup,
      positionMode: this.astroStore.positionMode,
      celestialPositionCategory: this.astroStore.celestialPositionCategory,
      celestialPositionMagnitude: this.astroStore.celestialPositionMagnitude,
      celestialPositionHorizontal: this.astroStore.celestialPositionHorizontal,
      ephemerisMode: this.astroStore.ephemerisMode,
      ephemerisDays: this.astroStore.ephemerisDays,
      ephemerisStepHours: this.astroStore.ephemerisStepHours,
      rtsCalendarDays: this.astroStore.rtsCalendarDays,
      graphMode: this.astroStore.graphMode,
      eclipseMonths: this.astroStore.eclipseMonths,
      moonPhaseDays: this.astroStore.moonPhaseDays
    }
    return next
  }

  // 恢复默认设置成功后退出应用：main/restore_defaults 只在下一次启动时生效。
  // 退出前再清空一次 UI 偏好，覆盖退出窗口内可能发生的 saveAppSettings 回写。
  private exitAppAfterRestore(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    setTimeout(() => {
      this.settingsRepository.resetToDefaults().then(() => {
        return this.clearUiBehaviorPreferences()
      }).then(() => {
        context.terminateSelf().catch(() => {})
      }).catch(() => {
        context.terminateSelf().catch(() => {})
      })
    }, 800)
  }

  // 「恢复默认」必须连 UI 行为缓存一起清掉：夜间模式/快捷面板排序/信息窗模式各自
  // 存在独立 Preferences 里，只清 stellarium_ui 会让下次启动继续用夜间首帧主题。
  private async clearUiBehaviorPreferences(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
    const storeNames: string[] = [NIGHT_MODE_STORE, QUICK_PANEL_STORE, INFO_WINDOW_STORE]
    for (let index = 0; index < storeNames.length; index++) {
      try {
        const store = await preferences.getPreferences(ctx, storeNames[index])
        await store.clear()
        await store.flush()
      } catch (error) {
        hilog.warn(0x0000, 'StellariumArkUI', '[reset] clear preference failed: %{public}s', storeNames[index])
      }
    }
    this.nightModeStore.nightMode = false
    AppStorage.setOrCreate('stellariumNightMode', false)
  }

  // 启动时从 Preferences 载入 UI 偏好；有数据时填充 AppStorage 镜像并触发现有恢复流程。
  private async loadPersistedUiSettings(): Promise<void> {    const hasPersisted = await this.settingsRepository.load()
    if (!hasPersisted || this.persistedSettingsApplied) {
      return
    }
    this.persistedSettingsApplied = true
    const settings = this.settingsRepository.snapshot()
    AppStorage.setOrCreate('stellariumSettings', JSON.stringify({
      useMetricUnits: settings.useMetricUnits,
      musicEnabled: settings.musicEnabled,
      viewCoordinatesVisible: settings.viewCoordinatesVisible,
      viewCoordinateFamily: settings.viewCoordinateFamily,
      viewEquatorialEpoch: settings.viewEquatorialEpoch,
      objectDetailConnectorVisible: settings.objectDetailConnectorVisible,
      astroTab: settings.astroTab.toString(),
      astroGroup: settings.astroGroup.toString(),
      positionMode: settings.positionMode.toString(),
      celestialPositionCategory: settings.celestialPositionCategory,
      celestialPositionMagnitude: settings.celestialPositionMagnitude.toString(),
      celestialPositionHorizontal: settings.celestialPositionHorizontal.toString(),
      ephemerisMode: settings.ephemerisMode.toString(),
      ephemerisDays: settings.ephemerisDays.toString(),
      ephemerisStepHours: settings.ephemerisStepHours.toString(),
      rtsCalendarDays: settings.rtsCalendarDays.toString(),
      graphMode: settings.graphMode.toString(),
      eclipseMonths: settings.eclipseMonths.toString(),
      moonPhaseDays: settings.moonPhaseDays.toString()
    }))
    if (this.startupBridgeImpl !== null) {
      this.startupBridge().restoreStartupSettings()
    }
  }

  // "返回可消费"镜像：ApplicationRoot.onBackPress 据此决定系统返回是否由应用接管。
  // 恒为 true：主界面也接管（两次确认才退出，避免夜间误返回打断暗视力），退出由 handleHomeBackConfirm 显式执行。
  private publishBackConsumable(): void {
    if (AppStorage.get<boolean>('stellariumBackConsumable') !== true) {
      AppStorage.setOrCreate<boolean>('stellariumBackConsumable', true)
    }
  }

  //（桥经 CommandPort.request，UI 提示经 CatalogHostHooks.flashHint）。

  // ===== 书签本地持久化（@ohos.data.preferences）=====
  private async saveObservingListToStorage(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, OBSERVING_STORE)
      await store.put('observingList', JSON.stringify(this.obsListStore.observingList))
      await store.flush()
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'save observing list failed: %{public}s', String(e))
    }
  }

  //（AppStorage 写入 + Preferences 经 ObservingListHostHooks.saveObservingListStorage 注入）。

  // Preferences 原始读取助手：供 ObservingListStore.loadObservingListFromStorage 经 hooks 调用
  //（store 不 import NAPI/UI 上下文）。
  private async readObservingListStorage(): Promise<string> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
    const store = await preferences.getPreferences(ctx, OBSERVING_STORE)
    const jsonStr: Object = await store.get('observingList', '')
    return typeof jsonStr === 'string' ? jsonStr : ''
  }

  // Preferences 迁移写回助手：供 store 首次读取到空库时把内存值写回。
  private async writeObservingListStorage(json: string): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
    const store = await preferences.getPreferences(ctx, OBSERVING_STORE)
    await store.put('observingList', json)
    await store.flush()
  }

  // ===== 书签本地持久化（@ohos.data.preferences）=====
  private async saveBookmarksToStorage(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, BOOKMARK_STORE)
      const jsonStr: string = JSON.stringify(this.bookmarkStore.list)
      await store.put('bookmarks', jsonStr)
      await store.flush()
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'save bookmarks failed: %{public}s', String(e))
    }
  }

  // Preferences 原始读取助手：供 BookmarkStore.loadBookmarksFromStorage 经 hooks 调用。
  private async readBookmarksStorage(): Promise<string> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
    const store = await preferences.getPreferences(ctx, BOOKMARK_STORE)
    return (await store.get('bookmarks', '[]')) as string
  }

  // Preferences 原始读写助手：供 SearchStore.loadSearchHistoryFromStorage / saveSearchHistoryToStorage
  // 经 hooks 调用（；与 readBookmarksStorage 同型，承载 getUIContext + @ohos.data.preferences）。
  private async readSearchHistoryStorage(): Promise<string> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
    const store = await preferences.getPreferences(ctx, SEARCH_HISTORY_STORE)
    return (await store.get('history', '[]')) as string
  }

  private async writeSearchHistoryStorage(json: string): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
    const store = await preferences.getPreferences(ctx, SEARCH_HISTORY_STORE)
    await store.put('history', json)
    await store.flush()
  }

  // （NAPI 细节收在顶层 HostMediaPort 适配器）。

  // ===== 目镜 / 拼接相机 / 均时差 / 古天文线写回 =====
  // setOcularMode / setMosaicCamera / setEquationOfTime / setArchaeoLineSetting / applyArchaeoLineSetting /
  // setTelrad / setCrosshairs / setCCD / selectOcularInstrument / setOcularSetting /


  // ===== 卫星（Satellites 插件桥）=====
  private publishSatellitePanelState(error: string = ''): void {
    AppStorage.setOrCreate('stellariumSatellitePanelState', JSON.stringify({
      ok: error.length === 0, error: error, panel: this.activePanel, group: this.satelliteStore.activeSatGroup,
      loading: this.satelliteStore.satelliteListLoading, matchedCount: this.satelliteStore.satMatchedCount,
      ids: this.satelliteStore.satItems.map((item: SatelliteListItem) => item.id),
      groups: this.satelliteStore.satGroups, requestId: this.satelliteStore.satelliteListRequestId,
      orbitLines: this.satelliteStore.satOrbitLines, hints: this.satelliteStore.satHints,
      elapsedMs: this.satelliteStore.satelliteListElapsedMs,
      scrollY: this.satellitePanelScroller.currentOffset()?.yOffset ?? 0,
      groupScrollY: this.satelliteGroupScroller.currentOffset()?.yOffset ?? 0
    }))
  }

  // 保留的 CLI 发布点：本体由宿主持有，「天文计算」tab 过渡态经 控制器回读
  //（requestedAstroTab / astroTransitionSerial 即原 astroRequestedTab / astroTransitionId）。
  private publishAstroPanelState(): void {
    const requestedTab = this.astroCalcCtl().requestedAstroTab()
    AppStorage.setOrCreate('stellariumAstroPanelState', JSON.stringify({
      ok: true, group: this.astroStore.astroGroup, tab: this.astroStore.astroTab,
      requestedTab: requestedTab, transitionId: this.astroCalcCtl().astroTransitionSerial(),
      transitioning: requestedTab >= 0,
      loading: this.wutStore.wutLoading,
      period: this.wutStore.wutPeriod, altitude: this.wutStore.wutMinAltitude,
      magnitude: this.wutStore.wutMaxMagnitude, direction: this.wutStore.wutDirection,
      scrollY: this.activePanel === 'astro' && this.panelVisible ? this.astroPanelScroller.currentOffset().yOffset : 0
    }))
  }

  // 「当前面板」的只读回读（CLI getUiPanelState）：openUiPanel / closeUiPanel 只返回 accepted，
  // 断言「面板确实开了」需要这条命令（此前只能退回坐标点击验证）。与 getAstroPanelState 同一套
  // AppStorage 发布方式，由页面在面板状态变化时写入。
  private publishUiPanelState(): void {
    this.publishUiLayoutState()
    AppStorage.setOrCreate('stellariumUiPanelState', JSON.stringify({
      ok: true, panel: this.activePanel, visible: this.panelVisible,
      expanded: this.isExpandedLayout, foldHover: this.isFoldHoverLayout,
      panelTop: this.isExpandedLayout ? this.expandedPanelTop() : this.compactPanelTop(),
      panelHeight: this.isExpandedLayout ? this.expandedPanelHeight() : this.compactPanelHeight(),
      dockTop: this.dockTop(),
      navigationDepth: this.panelNavigationDepth, backAvailable: this.canGoBackPanel(),
      editable: this.activePanel === 'quick' ? this.quickPanelStore.editable : false
    }))
  }

  private publishSearchBrowserState(error: string = ''): void {
    AppStorage.setOrCreate('stellariumSearchBrowserState', JSON.stringify({
      ok: error.length === 0, error: error, page: this.searchStore.searchFilterPage || 'browse',
      category: this.searchStore.searchCategory, moduleId: this.searchStore.categoryModuleId,
      visibility: this.searchStore.searchVisibilityFilter, instrument: this.searchStore.searchInstrumentFilter,
      categories: this.catalogStore.searchAllCategoryOptions(), scrollY: this.searchPanelScroller.currentOffset()?.yOffset ?? 0
    }))
  }

  private publishGuideState(): void {
    AppStorage.setOrCreate('stellariumGuideState', JSON.stringify({
      ok: true, state: this.guideStore.guideState, lastRequestId: this.guideCtl().lastRequestId(),
      result: this.guideCtl().lastResult(), guides: ASTRONOMY_GUIDES
    }))
  }

// ===== 面板路由与返回 =====

  private openPanelFromCli(panel: string): void {
    if (panel === 'settingsInformation' || panel === 'settingsTime' || panel === 'settingsPrivacy') {
      this.openPanelFromCli('settings')
      this.layerCtl().selectConfigTab(panel === 'settingsInformation' ? 1 : (panel === 'settingsTime' ? 3 : -1))
      return
    }
    const parent = panelRouteParent(panel)
    this.panelNavigationStack = parent.length > 0 ? [parent] : []
    this.panelNavigationDepth = this.panelNavigationStack.length
    this.setPanel(panel, true, true)
  }

  // 年历加载完成后，拉取今夜天象并刷新桌面卡片快照。
  private persistAlmanacCardSnapshot(): void {
    this.callNativeWhenReady('getTonightEvents', '', (response: StellariumBridgeResponse) => {
      if (response.ok !== true || response.tonight === undefined) return
      const tonight = response.tonight as TonightEvents
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      void publishAstronomyCard(context, tonight as CardTonightData).then((result) => {
        hilog.info(0xD003, 'Stellarium', '[form-update] updated=%{public}d failed=%{public}d', result.updatedForms, result.failedForms)
      }).catch((error: Error) => {
        hilog.warn(0xD003, 'Stellarium', 'save card snapshot failed: %{public}s', error.message)
      })
    })
  }

  // 天象卡片点击路由：QAbility 写入 AppStorage('stellariumCardRoute')，此处消费并打开对应面板。
  private onCardRouteChanged(): void {
    this.consumeCardRoute()
  }

  private consumeCardRoute(): void {
    if (this.cardRoute.length === 0) return
    try {
      const route = JSON.parse(this.cardRoute) as Record<string, Object>
      const panel = String(route['panel'] ?? '').trim()
      if (!isCliPanelName(panel)) return
      const tab = Number(String(route['tab'] ?? ''))
      this.openPanelFromCli(panel)
      if (panel === 'astro' && Number.isInteger(tab) && tab >= 0 && tab <= 9) {
        setTimeout(() => { this.astroCalcCtl().selectAstroTab(tab) }, 220)
      }
      AppStorage.setOrCreate('stellariumCardRoute', '')
    } catch (error) {
      hilog.warn(0x0000, 'StellariumArkUI', '[form-route] ignored malformed route')
    }
  }

  // 协作会话分享：把会话信封落盘到 cacheDir 后拉起系统分享。
  private shareCollaborationSession(json: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const path = context.cacheDir + '/stellarium-observation-handoff-' + Date.now().toString() + '.json'
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      const encoder = new util.TextEncoder('utf-8')
      const bytes = encoder.encodeInto(json)
      fileIo.writeSync(file.fd, bytes.buffer)
      fileIo.closeSync(file)
      shareFile(this.hostMediaPort, this.hostPlatformPort, path, utd.UniformDataType.PLAIN_TEXT,
        I18n.t('session_share'), I18n.t('session_share_description'), 'session-share',
        { flashHint: (text: ResourceStr): void => this.flashHint(text), isExpandedLayout: (): boolean => this.isExpandedLayout })
    } catch (error) {
      hilog.error(0x0000, 'StellariumArkUI', 'Session share failed: %{public}s', String(error))
      this.flashHint(I18n.t('m_session_export_failed'))
    }
  }

  // 导出配置并落盘后拉起系统分享。
  private shareConfigBackup(): void {
    this.callNativeWhenReady('exportConfig', '', (r: StellariumBridgeResponse) => {
      const resp = r as ExportConfigResponse
      const content = resp.ok === true ? (resp.content ?? '') : ''
      if (content.length === 0) {
        this.flashHint(I18n.t('config_export_failed'))
        return
      }
      try {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext
        const path = context.cacheDir + '/stellarium-config-backup-' + Date.now().toString() + '.json'
        const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        const encoder = new util.TextEncoder('utf-8')
        const bytes = encoder.encodeInto(content)
        fileIo.writeSync(file.fd, bytes.buffer)
        fileIo.closeSync(file)
        shareFile(this.hostMediaPort, this.hostPlatformPort, path, utd.UniformDataType.PLAIN_TEXT,
          I18n.t('config_share'), I18n.t('config_share_description'), 'config-share',
          { flashHint: (text: ResourceStr): void => this.flashHint(text), isExpandedLayout: (): boolean => this.isExpandedLayout })
      } catch (error) {
        hilog.error(0x0000, 'StellariumArkUI', 'Config share failed: %{public}s', String(error))
        this.flashHint(I18n.t('config_export_failed'))
      }
    })
  }

  // 恢复默认 TLE 来源前先确认。
  private confirmRestoreSatelliteSources(): void {    this.getUIContext().showAlertDialog({
      title: I18n.t('sat_source_restore_title'),
      message: I18n.t('sat_source_restore_message'),
      primaryButton: { value: I18n.t('sat_source_cancel'), action: () => {} },
      secondaryButton: { value: I18n.t('sat_source_restore'), action: () => { this.satelliteCtl().restoreSatelliteSources() } }
    })
  }

  private setPanel(panel: string, preserveHistory: boolean = false, forceVisible: boolean = false, routeDirection: number = 0): void {
    if (!preserveHistory) {
      this.panelNavigationStack = []
      this.panelNavigationDepth = 0
    }
    // “应用配置”由“设置”；保留旧面板名兼容历史命令和书签。
    if (panel === 'config') panel = 'settings'
    // 天体详情是跨设备的独立浮动卡片，不再打开第二个“对象”面板。
    if (panel === 'object') {
      this.toggleObjectInspector()
      return
    }
    // 插件管理和设置共用同一套界面，直达入口只负责选中对应标签。
    if (panel === 'pluginManager') {
      this.configTab = 6
      panel = 'settings'
    } else if (panel === 'settings' && this.configTab >= 4 && this.configTab <= 6) {
      this.configTab = 0
    }
    if (panel === 'polarScope') {
      this.polarScopeCtl().enterPolarScope()
      return
    }
    const currentPanel = this.activePanel
    const resolvedRouteDirection = routeDirection === 0
      ? inferredPanelRouteDirection(currentPanel, panel)
      : (routeDirection < 0 ? -1 : 1)
    hilog.info(0x0000, 'StellariumArkUI', 'setPanel ' + panel)
    const nextVisible = forceVisible ? true : (this.activePanel === panel ? !this.panelVisible : true)
    // 快捷面板每次打开都回到 6×2；“更多操作”的展开态只是临时 UI 状态。
    if (panel === 'quick' && nextVisible) {
      this.quickPanelStore.setExpanded(false)
    }
    // 每次打开面板都回到默认高度（0.6），与手机一致。
    if (nextVisible) {
      this.compactPanelSnapRatio = 0.6
      this.compactPanelDragOffsetY = 0
      this.expandedPanelDragOffsetY = 0
    }
    const switchingPanel = this.panelVisible && nextVisible && this.activePanel !== panel
    this.panelRouteDirection = resolvedRouteDirection
    if (switchingPanel) {
      hilog.info(0x0000, 'StellariumArkUI', '[panel-transition] direction=%{public}d from=%{public}s to=%{public}s',
        resolvedRouteDirection, currentPanel, panel)
    }
    const routeSerial = nextVisible ? this.beginPanelRouteTransition(switchingPanel) : 0
    if (panel !== 'object') {
      this.fullInspectorRequested = false
      this.infoWindowStore.infoWinExpanded = false
    }
    this.timeCtl().stopPanelTimers()
    this.skyCultureCtl().stopSkyCultureTimeFollowTimer()
    this.polarScopeCtl().stopPolarScopeTimer()
    this.astroCalcCtl().stopAstroCalcContextTimer()
    this.telescopeCtl().stopTelescopeLivePosition(false)
    if (!nextVisible) {
      this.schedulePanelDataLoad(panel, false)
      const closeSerial = ++this.panelContentKey
      const closeDirection = this.panelRouteDirection
      this.getUIContext().animateTo({ duration: 170, curve: Curve.EaseIn, onFinish: () => {
        if (this.panelContentKey !== closeSerial) return
        this.panelVisible = false
        this.panelRouteOpacity = 1
        this.panelRouteOffsetX = 0
        this.panelPresentationOpacity = 1
        this.panelPresentationOffsetY = 0
        if (panel === 'object') {
          this.fullInspectorRequested = false
          this.infoWindowStore.infoWinExpanded = false
        }
        this.publishUiPanelState()
      } }, () => {
        this.panelRouteOpacity = 0
        this.panelRouteOffsetX = -closeDirection * 18
        this.panelPresentationOpacity = 0
        this.panelPresentationOffsetY = this.isExpandedLayout ? 0 : 18
      })
      this.scheduleSelectedObjectForUiChange(220)
      return
    }
    if (switchingPanel) {
      const direction = this.panelRouteDirection
      this.schedulePanelDataLoad(panel, false)
      this.getUIContext().animateTo({ duration: 145, curve: Curve.EaseIn, onFinish: () => {
        if (this.panelContentKey !== routeSerial) return
        this.activePanel = panel
        this.panelVisible = true
        this.panelRouteOpacity = 0
        this.panelRouteOffsetX = direction * 10
        this.resetPanelIdle()
        this.schedulePanelDataLoad(panel, true)
        this.scheduleSelectedObjectForUiChange(380)
        this.publishUiPanelState()
        this.finishPanelRouteTransition(routeSerial)
      } }, () => {
        if (this.panelContentKey !== routeSerial) return
        this.panelRouteOpacity = 0
        this.panelRouteOffsetX = -direction * 18
      })
      return
    }
    this.activePanel = panel
    this.panelVisible = true
    this.resetPanelIdle()
    this.schedulePanelDataLoad(panel, true)
    this.scheduleSelectedObjectForUiChange(380)
    this.publishUiPanelState()
    this.finishPanelRouteTransition(routeSerial)
  }

  private schedulePanelDataLoad(panel: string, visible: boolean): void {
    if (this.panelDataLoadTimer >= 0) {
      clearTimeout(this.panelDataLoadTimer)
      this.panelDataLoadTimer = -1
    }
    if (!visible) return
    this.panelDataLoadTimer = setTimeout(() => {
      this.panelDataLoadTimer = -1
      if (!this.panelVisible || this.activePanel !== panel) return
      this.skyCultureCtl().syncSkyCultureTimeFollowTimer()
      this.polarScopeCtl().syncPolarScopeTimer()
      if (panel === 'place') {
        this.sessionToolStore.refreshTonight()
      }
      if (panel === 'observing' && !this.wutStore.wutHasResult && !this.wutStore.wutLoading) {
        this.wutStore.loadWutTargets()
      }
      if (panel === 'search') {
        this.catalogStore.loadObjectCatalogCategories(this.languageStore.languageRefreshSerial)
        this.searchStore.loadConstellationNavigation(this.languageStore.languageRefreshSerial)
        if (this.searchStore.categoryObjects.length === 0) this.searchStore.loadCategoryObjects(this.searchStore.searchCategory)
      }
      if (panel === 'time') {
        this.timeStore.loadTimeExtras()
        this.pluginFeatureCtl().ensurePluginLoaded('EquationOfTime', () => { this.equationOfTimeStore.loadEquationOfTime() })
        this.timeCtl().startPanelTimers()
      }
      if (panel === 'astro') {
        this.publishAstroPanelState()
        this.astroCalcCtl().loadAstroTab(this.astroStore.astroTab)
      } else if (panel === 'layers') {
        this.refreshState()
        if (this.viewTab === 4) this.layerViewStore.loadLandscapeList()
      } else if (panel === 'ar') {
        this.arCtl().loadCapabilities()
      } else if (panel === 'settings') {
        this.refreshState()
        this.catalogStore.loadCatalogHealth()
        this.settingsCtl().loadConfigurationSettings()
        if (this.configTab === 6) this.pluginStore.loadPluginList()
      } else if (panel === 'place') {
        this.refreshState()
        this.sessionToolStore.loadPlanetList()
        this.locationPickerStore.loadObserverInfo()
        this.locationStore.loadSavedLocations()
      } else if (panel === 'catalogs') {
        // 离线与在线模式都加载：面板统一显示 9 级星表（引擎 checked 状态为准，桥不可用回退静态快照）。
        this.catalogStore.loadStarCatalogs()
      } else if (panel === 'bookmarks') {
        this.bookmarkStore.loadBookmarks()
      } else if (panel === 'oculars') {
        this.pluginFeatureCtl().ensurePluginLoaded('Oculars', () => { this.telescopeStore.loadOculars(false) })
      } else if (panel === 'mosaicCamera') {
      this.pluginFeatureCtl().ensurePluginLoaded('MosaicCamera', () => { this.mosaicStore.loadMosaicCamera() })
    } else if (panel === 'archaeoLines') {
      this.pluginFeatureCtl().ensurePluginLoaded('ArchaeoLines', () => { this.archaeoStore.loadArchaeoLines() })
      } else if (panel === 'angleMeasure') {
        this.pluginFeatureCtl().ensurePluginLoaded('AngleMeasure', () => { this.tools.loadAngleMeasure() })
      } else if (panel === 'navStars') {
        this.pluginFeatureCtl().ensurePluginLoaded('NavStars', () => { this.navStarsStore.loadNavStars(false) })
      } else if (panel === 'satellites') {
        this.catalogStore.loadCatalogHealth()
        this.pluginFeatureCtl().ensurePluginLoaded('Satellites', () => { this.satelliteStore.loadSatellites(true, true) })
      } else if (panel === 'meteorshowers') {
        this.pluginFeatureCtl().ensurePluginLoaded('MeteorShowers', () => { this.meteorStore.loadMeteorShowers() })
      } else if (panel === 'scenery3d') {
        this.pluginFeatureCtl().ensurePluginLoaded('Scenery3d', () => { this.sceneryStore.loadScenery3d() })
      } else if (panel === 'nebulaTextures') {
        this.pluginFeatureCtl().ensurePluginLoaded('NebulaTextures', () => { this.nebulaTextureStore.loadNebulaTextureStatus() })
      } else if (panel === 'skyCultureMaker') {
        this.skyCultureMakerStore.loadSkyCultureMakerDraft()
      } else if (panel === 'pointerCoordinates') {
        this.pluginFeatureCtl().ensurePluginLoaded('PointerCoordinates', () => { this.overlayStore.loadPointerCoordinates() })
      } else if (panel === 'observing') {
      } else if (panel === 'commands') {
        this.commandStore.loadCommandCatalog()
      } else if (panel === 'help') {
        this.tools.loadAboutInfo()
      } else if (panel === 'scripts') {
        this.scriptPlaybackCtl().loadScriptList()
        this.scriptPlaybackCtl().loadRecordings()
        this.scriptPlaybackCtl().loadVideoRecordingState()
      } else if (panel === 'telescope') {
        this.telescopeCtl().loadTelescopeControlStatus()
      }
    }, 280) as number
  }

  private beginPanelRouteTransition(switchingPanel: boolean): number {
    const serial = this.panelContentKey + 1
    this.panelContentKey = serial
    this.panelRouteOpacity = switchingPanel ? 1 : 0
    this.panelRouteOffsetX = 0
    if (!switchingPanel) {
      this.panelPresentationOpacity = 0
      this.panelPresentationOffsetY = this.isExpandedLayout ? 0 : 24
    }
    hilog.info(0x0000, 'StellariumArkUI', '[panel-transition] begin serial=%{public}d switching=%{public}s', serial, switchingPanel.toString())
    return serial
  }

  private finishPanelRouteTransition(serial: number): void {
    if (serial <= 0) return
    setTimeout(() => {
      if (this.panelContentKey !== serial) return
      this.resetPanelScroll(this.isExpandedLayout ? this.widePanelScroller : this.compactPanelScroller)
      this.getUIContext().animateTo({ duration: 320, curve: curves.springMotion(0.46, 0.86) }, () => {
        if (this.panelContentKey !== serial) return
        this.panelRouteOpacity = 1
        this.panelRouteOffsetX = 0
        this.panelPresentationOpacity = 1
        this.panelPresentationOffsetY = 0
        hilog.info(0x0000, 'StellariumArkUI', '[panel-transition] finish serial=%{public}d panel=%{public}s', serial, this.activePanel)
      })
    }, 16)
  }

  private resetPanelScroll(scroller: Scroller): void {
    try {
      scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    } catch (error) {
      hilog.warn(0x0000, 'StellariumArkUI', 'reset panel scroll failed: %{public}s', String(error))
    }
  }

  // ===== 返回栈（面板 + 面板内标签）=====
  // 栈条目编码为 'panel#viewTab#configTab'（兼容仅 'panel' 的旧式条目）。这样"在同一个面板里换了
  // 界面"（图层面板的视图标签、设置面板的页签、更多菜单进入子面板）都能被返回手势/返回按钮撤销；
  // 此前只记面板名，换过标签后返回会因栈空而直接关面板。
  private encodePanelRoute(panel: string, viewTab: number, configTab: number): string {
    return panel + '#' + viewTab.toString() + '#' + configTab.toString()
  }

  private pushPanelRoute(): void {
    if (!this.panelVisible || this.activePanel.length === 0) return
    const entry = this.encodePanelRoute(this.activePanel, this.viewTab, this.configTab)
    const n = this.panelNavigationStack.length
    if (n > 0 && this.panelNavigationStack[n - 1] === entry) return
    let next = this.panelNavigationStack.concat([entry])
    if (next.length > 32) next = next.slice(next.length - 32)
    this.panelNavigationStack = next
    this.panelNavigationDepth = next.length
  }

  // 面板内标签切换（UI 回调经此进入）：先压返回栈，再交给 LayerController 切标签。
  private switchViewTab(id: number): void {
    if (id === this.viewTab) return
    this.pushPanelRoute()
    this.layerCtl().selectViewTab(id)
  }

  private switchConfigTab(id: number): void {
    if (id === this.configTab) return
    this.pushPanelRoute()
    this.layerCtl().selectConfigTab(id)
  }

  // 系统返回请求（ApplicationRoot.onBackPress → AppStorage → 此处执行应用内返回）。
  // 顺序 = 叠层由上到下：全屏叠层 → 信息窗 → 极轴镜 → 面板 → 主界面两次确认退出。
  private onRequestBack(): void {
    if (this.requestBackToken === 0) return
    if (this.objectMediaStore.objectInspectorMediaFullscreen) {
      this.objectInspectorMediaCtl().closeObjectInspectorMediaPreview()
      return
    }
    if (this.objectMediaStore.objectInspectorModelImmersive) {
      this.objectModelRendererCtl().setObjectInspectorModelImmersive(false)
      return
    }
    if (this.skyCultureViewStore.artPreviewOpen) {
      this.skyCultureCtl().closeSkyCultureArtPreview()
      return
    }
    if (this.infoWindowStore.infoWinVisible) { this.dismissObjectInspector(); return }
    if (this.polarScopeStore.polarScopeVisible) { this.polarScopeCtl().closePolarScope(); return }
    if (this.panelVisible) { this.handlePanelBackTap(); return }
    this.handleHomeBackConfirm()
  }

  // 已在主界面（无面板/无叠层）时按返回：夜间误触直接退回桌面会打断暗视力，所以改为两次确认。
  private handleHomeBackConfirm(): void {
    const now = Date.now()
    if (now - this.lastHomeBackAt < this.HOME_BACK_CONFIRM_MS) {
      this.lastHomeBackAt = 0
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      void context.terminateSelf().catch((err: Error) => {
        hilog.error(0x0000, 'StellariumArkUI', 'Failed to terminate on back confirm: %{public}s', JSON.stringify(err))
      })
      return
    }
    this.lastHomeBackAt = now
    this.flashHint(I18n.t('back_again_to_exit'))
  }

  private openSubPanel(panel: string): void {
    if (this.activePanel !== panel && this.panelVisible) {
      this.pushPanelRoute()
    }
    this.setPanel(panel, true, true)
  }

  private canGoBackPanel(): boolean {
    return this.panelNavigationStack.length > 0 || panelRouteParent(this.activePanel).length > 0
  }

  private handlePanelBackTap(): void {
    const now = Date.now()
    if (now - this.lastPanelBackAt < 240) return
    this.lastPanelBackAt = now
    // 快捷面板处于自定义编辑态时，返回键先「丢弃编辑」而不关面板：编辑态需要一条明确的取消路径，
    // 否则误拖无处撤回（见计划 §13.5）。
    if (this.activePanel === 'quick' && this.quickPanelStore.editable) {
      this.quickPanelStore.discardEdit()
      return
    }
    hilog.info(0x0000, 'StellariumArkUI', '[panel-back] panel=%{public}s stack=%{public}d parent=%{public}s',
      this.activePanel, this.panelNavigationStack.length, panelRouteParent(this.activePanel))
    this.goBackPanel()
  }

  private goBackPanel(): void {
    let entry = ''
    if (this.panelNavigationStack.length > 0) {
      entry = this.panelNavigationStack[this.panelNavigationStack.length - 1]
      this.panelNavigationStack = this.panelNavigationStack.slice(0, this.panelNavigationStack.length - 1)
    } else {
      entry = panelRouteParent(this.activePanel)
    }
    if (entry.length === 0) {
      this.closePanel(true)
      return
    }
    this.panelNavigationDepth = this.panelNavigationStack.length
    const parts: string[] = entry.split('#')
    const targetPanel: string = parts.length > 0 ? parts[0] : ''
    if (targetPanel.length === 0) {
      this.closePanel(true)
      return
    }
    if (targetPanel === this.activePanel) {
      // 同一面板内返回上一个标签：只恢复标签，不重开面板。
      if (parts.length >= 3) {
        const v = Number(parts[1])
        const c = Number(parts[2])
        if (Number.isFinite(v)) this.viewTab = v
        if (Number.isFinite(c)) this.configTab = c
      }
      return
    }
    this.setPanel(targetPanel, true, true, -1)
    if (parts.length >= 3) {
      const v = Number(parts[1])
      const c = Number(parts[2])
      if (Number.isFinite(v)) this.viewTab = v
      if (Number.isFinite(c)) this.configTab = c
    }
    this.publishUiPanelState()
  }

  private closePanel(force: boolean = false): void {
    if (this.viewSettingsStore.uiLocked && !force) {
      return
    }
    if (this.polarScopeStore.polarScopeVisible) {
      this.polarScopeCtl().closePolarScope()
      return
    }
    // 关面板即丢弃未提交的快捷面板自定义（点面板外 / 关按钮 / 切路由都会走到这里）。
    this.quickPanelStore.discardEdit()
    // 关面板时停掉时间面板定时器，避免后台空转
    this.timeCtl().stopPanelTimers()
    this.skyCultureCtl().stopSkyCultureTimeFollowTimer()
    this.polarScopeCtl().stopPolarScopeTimer()
    this.astroCalcCtl().stopAstroCalcContextTimer()
    this.telescopeCtl().stopTelescopeLivePosition(false)
    if (this.panelDataLoadTimer >= 0) {
      clearTimeout(this.panelDataLoadTimer)
      this.panelDataLoadTimer = -1
    }
    if (this.activePanel === 'search') {
      this.astroCalcCtl().clearTargetPickerFlags()
    }
    const closingObjectPanel = this.activePanel === 'object'
    this.panelNavigationStack = []
    this.panelNavigationDepth = 0
    const closeSerial = ++this.panelContentKey
    const closeDirection = this.panelRouteDirection
    this.getUIContext().animateTo({ duration: 170, curve: Curve.EaseIn, onFinish: () => {
      if (this.panelContentKey !== closeSerial) return
      this.panelVisible = false
      this.panelRouteOpacity = 1
      this.panelRouteOffsetX = 0
      this.panelPresentationOpacity = 1
      this.panelPresentationOffsetY = 0
      if (closingObjectPanel) {
        this.fullInspectorRequested = false
        this.infoWindowStore.infoWinExpanded = false
      }
      this.publishUiPanelState()
    } }, () => {
      this.panelRouteOpacity = 0
      this.panelRouteOffsetX = -closeDirection * 18
      this.panelPresentationOpacity = 0
      this.panelPresentationOffsetY = this.isExpandedLayout ? 0 : 18
    })
    this.scheduleSelectedObjectForUiChange(220)
    this.publishUiPanelState()
  }

// ===== 命中测试与触摸分发 =====

  private resetPanelIdle(): void {
    if (this.panelIdleTimer >= 0) {
      clearTimeout(this.panelIdleTimer)
    }
    this.panelIdleOpacity = 1.0
    this.panelIdleGlass = false
    this.panelIdleTimer = setTimeout(() => {
      if (!this.viewSettingsStore.uiLocked) {
        this.panelIdleOpacity = 0.88
        this.panelIdleGlass = true
      }
      this.panelIdleTimer = -1
    }, 5000)
  }

  private notePanelTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down || event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.resetPanelIdle()
    }
  }

  private isUiPoint(x: number, y: number): boolean {
    // 录制聚焦态（控制条收起）：除顶部录制控制条外，面板/详情卡/搜索/Dock/底部条等界面
    // 全部隐藏，不得留下“幽灵命中区”吞掉拖动。此前只有录制条被排除，其余隐藏界面的命中区
    // 仍在，导致星图（含中央）多处拖不动。
    if (this.tools.recording && !this.tools.recordingUiExpanded &&
      !this.scriptStore.scriptPlaybackVisible(this.guideStore.guideState.active)) {
      return x >= 16 && x <= Math.max(266, this.skyWidth - 16) &&
        y >= this.EDGE_MARGIN - 8 && y <= this.EDGE_MARGIN + 58
    }
    if (this.guideStore.guideState.active) {
      return x >= guideCardX(this.isExpandedLayout, this.skyWidth, this.guideCardWidth(), this.scriptStore.scriptControlOffsetX) && x <= guideCardX(this.isExpandedLayout, this.skyWidth, this.guideCardWidth(), this.scriptStore.scriptControlOffsetX) + this.guideCardWidth() &&
        y >= guideCardY(this.skyHeight, guideCardHeight(this.skyHeight, this.scriptControlSafeTop()), this.scriptControlSafeTop(), this.scriptStore.scriptControlOffsetY) && y <= guideCardY(this.skyHeight, guideCardHeight(this.skyHeight, this.scriptControlSafeTop()), this.scriptControlSafeTop(), this.scriptStore.scriptControlOffsetY) + guideCardHeight(this.skyHeight, this.scriptControlSafeTop())
    }
    if (this.polarScopeStore.polarScopeVisible) {
      const headerTop = this.polarScopeTopInset()
      const left = (this.skyWidth - this.polarScopeControlWidth()) / 2
      if (x >= left && x <= left + this.polarScopeControlWidth() &&
        ((y >= headerTop && y <= headerTop + 60) ||
          (y >= this.skyHeight - this.polarScopeFooterHeight() - 12 && y <= this.skyHeight - 12))) {
        return true
      }
      return false
    }
    if (this.tools.recording && !this.scriptStore.scriptPlaybackVisible(this.guideStore.guideState.active) &&
      x >= 16 && x <= Math.max(266, this.skyWidth - 16) &&
      y >= this.EDGE_MARGIN - 8 && y <= this.EDGE_MARGIN + 58) {
      return true
    }
    if (isDockPoint(x, y, this.polarScopeStore.polarScopeVisible, this.isExpandedLayout, this.skyWidth, this.skyHeight, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent(), this.dockTop(), this.dockHeight())) {
      return true
    }
    if (this.overlayStore.viewCoordinatesVisible) {
      const coordinateLeft = this.viewCoordinateOverlayLeft()
      const coordinateTop = this.viewCoordinateOverlayTop()
      const coordinateWidth = this.viewCoordinateOverlayWidth()
      if (x >= coordinateLeft - 8 && x <= coordinateLeft + coordinateWidth + 8 &&
        y >= coordinateTop - 8 && y <= coordinateTop + 92) {
        return true
      }
    }
    // 顶部搜索栏：点击区域不穿透到星图
    if (this.isExpandedLayout) {
      const sbX = this.EDGE_MARGIN + 64
      const sbY = this.EDGE_MARGIN
      const sbW = 300
      const sbH = 44
      if (x >= sbX && x <= sbX + sbW && y >= sbY && y <= sbY + sbH) {
        return true
      }
    } else {
      if (this.isFoldHoverLayout && y >= this.hoverConsoleTop() - 8) {
        return true
      }
      if (x >= 16 && x <= 16 + 280 && y >= 50 && y <= 50 + 44) {
        return true
      }
      if (this.isCompactTopQuickPoint(x, y)) {
        return true
      }
      if (this.isCompactMorePoint(x, y)) {
        return true
      }
    }
    if (isObjectDetailCardPoint(x, y, this.objectDetailStore.isObjectDetailCardRendered(this.infoWindowStore.infoWinVisible), this.detailCardX(), this.detailCardY(), this.detailCardWidth(), this.detailCardHeight())) {
      return true
    }
    if (this.isExpandedLayout) {
      // 浮动面板区域（含 30vp 余量，覆盖圆角/边距，杜绝点面板却拖星图）
      if (this.panelVisible) {
        const pl = panelLeft(this.isExpandedLayout, this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN)
        const pr = panelRight(this.isExpandedLayout, this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN)
        const pt = this.panelTop()
        if (x >= pl - 30 && x <= pr + 30 && y >= pt - 30 && y <= pt + this.expandedPanelHeight() + 30) {
          return true
        }
      }
      return false
    }
    if (this.panelVisible) {
      const panelW = this.isFoldHoverLayout ? this.skyWidth * 0.72 : this.skyWidth * 0.94
      const panelX = (this.skyWidth - panelW) / 2
      const panelBottom = this.compactPanelBottom()
      const panelY = panelBottom - this.compactPanelHeight()
      if (x >= panelX - 12 && x <= panelX + panelW + 12 && y >= panelY - 18 && y <= panelBottom + 10) {
        return true
      }
    }
    if (this.isCompactTopQuickPoint(x, y)) {
      return true
    }
    return y >= this.skyHeight - 80
  }

  private handleUiTap(x: number, y: number): boolean {
    // 防闪退保护：确保所有数组和状态变量有效
    try {
	    if (typeof x !== 'number' || typeof y !== 'number' || isNaN(x) || isNaN(y)) { return false }
	    if (this.handleCompactTopQuickTap(x, y)) { return true }
    const dockItem = this.dockActionAt(x, y)
    if (dockItem !== null) {
      this.activateDockAction(dockItem)
      return true
    }
    if (this.polarScopeStore.polarScopeVisible) {
      const headerTop = this.polarScopeTopInset()
      const right = (this.skyWidth + this.polarScopeControlWidth()) / 2 - 6
      if (y >= headerTop + 6 && y <= headerTop + 54) {
        if (x >= right - 48 && x <= right) {
          this.polarScopeCtl().closePolarScope()
          return true
        }
        if (x >= right - 104 && x <= right - 56) {
          this.polarScopeCtl().recenterPolarScope()
          return true
        }
      }
    }
	    // 顶部搜索栏已移除，搜索功能通过左侧图标进入分类面板
    // 浮动详情窗优先处理（其区域内已由 isUiPoint 拦截，不会落到星图选星）
      if (this.isExpandedLayout && this.handleExpandedDetailSummaryTap(x, y)) { return true }
      if ((!this.panelVisible || !useExpandedDetailSummary()) && this.handleInfoWinTap(x, y)) { return true }

    if (!this.panelVisible) {
		      return false
		    }

    const left = panelLeft(this.isExpandedLayout, this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN)
    const top = this.panelTop()
    const right = panelRight(this.isExpandedLayout, this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN)
    if (isPanelBackPoint(x, y, this.canGoBackPanel(), this.isExpandedLayout, this.isFoldHoverLayout, this.panelWidth, this.skyWidth, this.compactPanelTop(), this.panelOffsetX, this.EDGE_MARGIN, this.expandedPanelTop())) {
      this.handlePanelBackTap()
      return true
    }
    if (x >= right - 60 && x <= right && y >= top && y <= top + 60) {
      if (!this.viewSettingsStore.uiLocked) {
        this.closePanel(true)
      }
      return true
    }

    if (x < left || x > right || y < top || y > top + 900) {
      return false
    }
    this.resetPanelIdle()

    // Layer toggles are handled by Toggle.onChange in the LayerSwitchRow component
    // Hardcoded coordinates removed - layout changed with grouped sections

    if (this.activePanel === 'search') {
      if (y >= 505 && y <= 562) {
        if (x >= 1095 && x < 1165) { this.searchObject('Moon'); return true }
        if (x >= 1165 && x < 1230) { this.searchObject('Mars'); return true }
        if (x >= 1230 && x <= 1345) { this.searchObject('Jupiter'); return true }
      }
    } else if (this.activePanel === 'time') {
      if (y >= 545 && y <= 595) {
        // 循环升档按钮：倒带 | 停止 | 实时 | 减速 | 快进（快进/倒带可连点升档）
        if (x >= 1040 && x < 1110) { this.timeCtl().handleChip('rewind'); return true }
        if (x >= 1110 && x < 1180) { this.timeCtl().handleChip('stop'); return true }
        if (x >= 1180 && x < 1250) { this.timeCtl().handleChip('realtime'); return true }
        if (x >= 1250 && x < 1320) { this.timeCtl().handleChip('slower'); return true }
        if (x >= 1320 && x <= 1400) { this.timeCtl().handleChip('fast'); return true }
      }
      if (y >= 610 && y <= 660) {
        if (x >= 1095 && x < 1220) { this.timeCtl().advanceTime(12); return true }
        if (x >= 1220 && x <= 1345) { this.timeCtl().advanceTime(-12); return true }
      }
    } else if (this.activePanel === 'object') {
      if (y >= 560 && y <= 615) {
        if (x >= 1095 && x < 1160) { this.refreshSelectedObject(); this.refreshState(); return true }
        if (x >= 1160 && x < 1225) { this.moveToSelectedObject(); return true }
        if (x >= 1225 && x <= 1310) { this.callInteractive('setTracking', '0', () => { this.refreshState() }); return true }
      }
      if (!OFFLINE_APPGALLERY_BUILD && y >= 630 && y <= 690) {
        if (x >= 1095 && x < 1175) { this.telescopeCtl().lx200GotoSelected(); return true }
        if (x >= 1175 && x < 1245) { this.telescopeCtl().lx200SyncSelected(); return true }
        if (x >= 1245 && x <= 1320) { this.telescopeCtl().lx200Abort(); return true }
      }
    } else if (this.activePanel === 'place') {
      if (y >= 455 && y <= 505 && x >= 1300 && x <= right) { this.locationCtl().useDeviceLocation(); return true }
    }

    return true
    } catch (e) {
      hilog.error(0x0000, 'StellariumArkUI', 'handleUiTap crash: ' + (e instanceof Error ? e.message : String(e)))
      return false
    }
  }

  private handleOverlayTouch(event: TouchEvent): void {
    if (event.source === SourceType.Mouse) { return }
    try {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) {
      return
    }
    const x = touchWindowX(points[0])
    const y = touchWindowY(points[0])
    // Do not rebuild the whole ArkUI shell for every Move event. Refresh the
    // chrome idle timers on gesture start/end, and at most twice per second
    // while a long drag is in progress.
    const activityNow = Date.now()
    if (event.type !== TouchType.Move || activityNow - this.lastOverlayActivityMs >= 500) {
      this.lastOverlayActivityMs = activityNow
      this.resetPanelIdle()
    }
    if (event.type === TouchType.Down) {
      this.touchStartedOnUi = this.isUiPoint(x, y)
      if (this.touchStartedOnUi) {
        this.skyTouchFeedback = false
        this.skyTouchActive = false
      }
      hilog.info(0x0000, 'StellariumArkUI', 'overlay touch down ' + Math.round(x).toString() + ',' + Math.round(y).toString() + ' ui=' + (this.touchStartedOnUi ? '1' : '0') + ' sky=' + this.skyWidth.toString() + 'x' + this.skyHeight.toString())
    }
    if (this.touchStartedOnUi) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.handleUiTap(x, y)
        this.touchStartedOnUi = false
      }
      return
    }
    this.handleSkySurfaceTouch(event)
    } catch (e) {
      hilog.error(0x0000, 'StellariumArkUI', 'handleOverlayTouch crash: ' + (e instanceof Error ? e.message : String(e)))
    }
  }

  private focusSkyKeyboard(x: number, y: number): void {
    if (!this.isUiPoint(x, y)) {
      this.getUIContext().getFocusController().requestFocus('sky-keyboard-target')
    }
  }

  private handleSkySurfaceTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down && event.source !== SourceType.Mouse && event.touches.length > 0) {
      this.focusSkyKeyboard(event.touches[0].x, event.touches[0].y)
    }
    this.skyInputCtl().handleSkyTouch(event)
  }

  private handleSkySurfaceMouse(event: MouseEvent): void {
    if (event.action === MouseAction.Press) { this.focusSkyKeyboard(event.x, event.y) }
    this.skyInputCtl().handleSkyMouse(event)
  }

  private handleSkyKeyboard(event: KeyEvent, panelOnly: boolean = false): boolean {
    const hooks: KeyboardShortcutInputHooks = {
      skyWidth: (): number => this.skyWidth,
      skyHeight: (): number => this.skyHeight,
      zoomStep: (factor: number): void => this.zoomStep(factor),
      centerSelectedObjectFromKeyboard: (): void => this.centerSelectedObjectFromKeyboard(),
      moveToSelectedObject: (): void => this.moveToSelectedObject(),
      closeKeyboardOverlay: (): void => {
        if (this.objectMediaStore.objectInspectorModelImmersive) this.objectModelRendererCtl().setObjectInspectorModelImmersive(false)
        else this.closePanel()
      }
    }
    return panelOnly ? this.keyboardShortcutCtl().handlePanelKey(event, hooks) : this.keyboardShortcutCtl().handleSkyKey(event, hooks)
  }

  private requestSkySelection(x: number, y: number): void {
    const requestSerial = ++this.skySelectionRequestSerial
    const payload = Math.round(x).toString() + '|' + Math.round(y).toString() + '|' +
      Math.round(this.skyWidth).toString() + '|' + Math.round(this.skyHeight).toString()
    this.callInteractive('selectAt', payload, (result) => {
      if (requestSerial !== this.skySelectionRequestSerial) {
        hilog.info(0x0000, 'StellariumArkUI', 'selectAt result ignored after newer selection gesture')
        return
      }
      hilog.info(0x0000, 'StellariumArkUI', 'selectAt result: ' + JSON.stringify(result))
      this.applySelectedObject(result, false, '', true)
      if (result.found === true) {
        // 轻量回包只有名称/类型；星等 / 方位 / 距离等动态值立刻单独补一次（见方法注释）。
        this.refreshSelectedDynamicValues()
      } else {
        // 「已选中 XX」是纯状态播报，观测时反复点选会刷屏（用户要求去掉）；点了空处仍提示一次。
        this.flashHint(I18n.t('i0075'))
      }
    })
  }

  private clearSkySelectionFromDoubleTap(x: number, y: number): void {
    const requestSerial = ++this.skySelectionRequestSerial
    this.skyInputCtl().resetSkyTapSequence()
    this.detailConnectorCtl().stop()
    this.applySelectedObject({ ok: true, found: false } as StellariumBridgeResponse)
    hilog.info(0x0000, 'StellariumArkUI', 'double tap cleared sky selection at ' +
      Math.round(x).toString() + ',' + Math.round(y).toString())
    this.callInteractive('clearSelection', '', (result) => {
      if (requestSerial !== this.skySelectionRequestSerial) { return }
      this.applySelectedObject(result)
    })
  }

  private centerSelectedObjectFromKeyboard(): void {
    const now = Date.now()
    if (now - this.lastCenterKeyAt < 220) { return }
    this.lastCenterKeyAt = now
    if (this.objectDetailStore.selectedStatus !== 'Selected' || this.objectDetailStore.selectedName.length === 0) {
      this.flashHint('请先选择天体')
      return
    }
    if (this.gyroStore.gyroscopeEnabled) {
      this.gyroCtl().updateGyroTargetGuide(true)
      return
    }
    this.navigateSelectedObjectTo(this.skyWidth / 2, this.skyHeight / 2, 'keyboard-center')
    this.flashHint('已居中')
  }

  /**
 * 手机端右上角常驻快捷区：陀螺仪 + 音频控制。
 * 这两项是观星高频功能，手机端保留顶部快捷入口；它们与底部 Dock
 * 共享同一状态和命令，不再依赖已经弃用的左侧栏。
 */
  /** 手机端右上快捷区左上角坐标（与顶部搜索栏同高，靠右缘） */
  private compactTopQuickX(): number {
    return this.skyWidth - 18 - 44
  }

  private isCompactTopQuickPoint(x: number, y: number): boolean {
    if (this.isExpandedLayout) { return false }
    const qx = this.compactTopQuickX()
    const qy = compactTopQuickY()
    return x >= qx - 8 && x <= qx + 52 && y >= qy - 8 && y <= qy + 108
  }

  /**
 * 星图缩放按钮命中（vp）：返回 'in'（+放大）| 'out'（−缩小）| ''。
 * 几何必须与 panels/shell/PanelChromeExtras.ets 的 SkyZoomLayer 保持一致：
 * posX=dockLeft, posY=dockTop-104, padding-left 4, 两个 44x44 按钮间距 8。
 */
  private skyZoomButtonAt(x: number, y: number): string {
    if (this.panelVisible || this.polarScopeStore.polarScopeVisible) { return '' }
    // 几何与 SkyZoomLayer 共用 common/ui/ChromeGeometry：绘制位置和命中区域必须同源，
    // 否则两者会各自漂移（曾出现"点 + 无响应、点 − 变成放大"的整列错位）。
    const horizontal = this.chromeZoomHorizontal()
    const rowY = this.chromeRowY()
    const inTop = chromeZoomButtonTop(rowY, horizontal, 0)
    const outTop = chromeZoomButtonTop(rowY, horizontal, 1)
    const inLeft = chromeZoomButtonLeft(chromeRowPosXLeft(this.isExpandedLayout, this.EDGE_MARGIN, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.compactDockWidthPercent()), horizontal, 0)
    const outLeft = chromeZoomButtonLeft(chromeRowPosXLeft(this.isExpandedLayout, this.EDGE_MARGIN, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.compactDockWidthPercent()), horizontal, 1)
    const within = (v: number, start: number): boolean => v >= start && v <= start + CHROME_ZOOM_BUTTON_SIZE
    if (horizontal) {
      // 横排两枚按钮同一行、左右并排，靠 x 区分。
      if (within(y, inTop)) {
        if (within(x, inLeft)) { return 'in' }
        if (within(x, outLeft)) { return 'out' }
      }
      return ''
    }
    // 竖排两枚按钮同一列、上下排列，靠 y 区分（上 + 下 −）。
    if (within(x, inLeft)) {
      if (within(y, inTop)) { return 'in' }
      if (within(y, outTop)) { return 'out' }
    }
    return ''
  }

  private compactQuickIdAt(x: number, y: number): string {
    if (this.isExpandedLayout) { return '' }
    const qx = this.compactTopQuickX()
    const qy = compactTopQuickY()
    if (x < qx || x > qx + 44) { return '' }
    if (y >= qy && y <= qy + 44) { return 'gyro' }
    if (y >= qy + 54 && y <= qy + 98) { return 'audio' }
    return ''
  }

  // The native sky XComponent can consume ArkUI Button.onClick on phones.
  // Route these two high-frequency controls through the same coordinate path
  // as the tablet rail so their visual and touch regions always agree.
  private handleCompactTopQuickTap(x: number, y: number): boolean {
    if (this.isExpandedLayout || !this.isCompactTopQuickPoint(x, y)) {
      return false
    }
    const quickId = this.compactQuickIdAt(x, y)
    if (quickId === 'gyro') {
      this.resetPanelIdle()
      if (!this.gyroStore.gyroscopeVisualEnabled()) this.syncEquatorialOffForGyro()
      this.gyroCtl().requestGyroscopeToggle(!this.gyroStore.gyroscopeVisualEnabled())
      return true
    }
    if (quickId === 'audio') {
      this.resetPanelIdle()
      this.audioStore.toggleMusic()
      this.flashHint(this.audioStore.musicEnabled ? I18n.t('music_on_hint') : I18n.t('music_off_hint'))
      return true
    }
    return false
  }

  private handleCompactTopQuickTouch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) {
      this.compactQuickPressed = ''
      return
    }
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) { return }
    const windowX = points[0].windowX
    const windowY = points[0].windowY
    const x = typeof windowX === 'number' ? windowX : this.compactTopQuickX() + (points[0].x ?? 0)
    const y = typeof windowY === 'number' ? windowY : compactTopQuickY() + (points[0].y ?? 0)
    if (event.type === TouchType.Down) {
      this.skyInputCtl().stopSkyInertia()
      this.skyTouchFeedback = false
      this.compactQuickPressed = this.compactQuickIdAt(x, y)
      return
    }
    if (event.type === TouchType.Up) {
      this.compactQuickPressed = ''
      this.handleCompactTopQuickTap(x, y)
    }
  }

  private isExpandedDetailSummaryPoint(x: number, y: number): boolean {
    if (!useExpandedDetailSummary() || !canShowExpandedDetailSummary(this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN)) { return false }
    const sx = this.expandedDetailSummaryX()
    const sy = this.expandedDetailSummaryY()
    return x >= sx - 8 && x <= sx + expandedDetailSummaryWidth(this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN) + 8 && y >= sy - 8 && y <= sy + expandedDetailSummaryHeight() + 8
  }

  private handleExpandedDetailSummaryTap(x: number, y: number): boolean {
    if (!this.isExpandedDetailSummaryPoint(x, y)) { return false }
    const sx = this.expandedDetailSummaryX()
    const sy = this.expandedDetailSummaryY()
    const sw = expandedDetailSummaryWidth(this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN)
    if (y <= sy + 42 && x >= sx + sw - 40) {
      this.dismissObjectInspector()
      return true
    }
    return true
  }

  private handleObjectInspectorDragTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) { return }
    const point = points[0]
    const x = touchScreenX(point)
    const y = touchScreenY(point)
    if (event.type === TouchType.Down) {
      this.objectCardDragging = true
      this.objectCardDragStartX = x
      this.objectCardDragStartY = y
      this.objectCardDragStartOffsetX = this.cardOffsetX
      this.objectCardDragStartOffsetY = this.cardOffsetY
      this.skyInputCtl().stopSkyInertia()
      this.resetPanelIdle()
      return
    }
    if (event.type === TouchType.Move && this.objectCardDragging) {
      this.cardOffsetX = this.objectCardDragStartOffsetX + x - this.objectCardDragStartX
      this.cardOffsetY = this.objectCardDragStartOffsetY + y - this.objectCardDragStartY
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.objectCardDragging = false
      const baseX = baseBottomCardX(this.isExpandedLayout, this.isFoldHoverLayout, this.skyWidth, this.EDGE_MARGIN, this.bottomCardWidth())
      const baseY = this.isFoldHoverLayout ? this.baseHoverBottomCardY() : baseBottomCardY(this.isExpandedLayout, this.skyHeight, this.EDGE_MARGIN, this.scriptControlSafeTop())
      const width = this.detailCardWidth()
      const height = this.detailCardHeight()
      this.cardOffsetX = this.clampedObjectCardOffsetX(baseX, width)
      this.cardOffsetY = this.clampedObjectCardOffsetY(baseY, height)
    }
  }

  private isCompactMorePoint(x: number, y: number): boolean {
    if (this.isExpandedLayout) {
      return false
    }
    return y >= this.skyHeight - 92 && x >= this.skyWidth * 0.72 && x <= this.skyWidth - 18
  }

  private dockActionAt(x: number, y: number): ShellAction | null {
    if (!isDockPoint(x, y, this.polarScopeStore.polarScopeVisible, this.isExpandedLayout, this.skyWidth, this.skyHeight, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent(), this.dockTop(), this.dockHeight())) {
      return null
    }
    const actions = this.canonicalDockActions()
    if (actions.length === 0) {
      return null
    }
    const padding = this.isExpandedLayout ? 8 : 12
    const usableLeft = dockLeft(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()) + padding
    const usableWidth = Math.max(1, dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()) - padding * 2)
    const itemWidth = usableWidth / actions.length
    const index = Math.floor((x - usableLeft) / itemWidth)
    return index >= 0 && index < actions.length ? actions[index] : null
  }

  private activateDockAction(item: ShellAction): void {
    const now = Date.now()
    if (item.panel === this.lastDockActionPanel && now - this.lastDockActionAt < 360) {
      return
    }
    this.lastDockActionPanel = item.panel
    this.lastDockActionAt = now
    if (item.panel === 'more') {
      this.setPanel('more')
      return
    }
    if (item.panel === 'object') {
      this.showFullObjectInspector()
      return
    }
    this.setPanel(item.panel)
  }

  private activateDockAtLocal(x: number, y: number): void {
    const actions = this.canonicalDockActions()
    const width = dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent())
    const index = dockItemIndex(x, y, width, this.dockHeight(), actions.length, this.isExpandedLayout ? 8 : 12)
    if (index >= 0) this.activateDockAction(actions[index])
  }

  private handleDockTouch(event: TouchEvent, localToDock: boolean = false): void {
    event.stopPropagation()
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) { return }
    this.notePanelTouch(event)
    const x = touchScreenX(points[0])
    const y = touchScreenY(points[0])
    if (event.type === TouchType.Down) {
      this.dockTouchActive = true
      this.skyInputCtl().stopSkyInertia()
      hilog.info(0x0000, 'StellariumArkUI', '[DOCK] down screen=%{public}d,%{public}d left=%{public}d top=%{public}d width=%{public}d', Math.round(x), Math.round(y), Math.round(dockLeft(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent())), Math.round(this.dockTop()), Math.round(dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent())))
      return
    }
    if (event.type === TouchType.Up) {
      if (this.dockTouchActive) {
        this.dockTouchActive = false
        if (localToDock) {
          this.activateDockAtLocal(points[0].x, points[0].y)
          return
        }
        const item = this.dockActionAt(x, y)
        hilog.info(0x0000, 'StellariumArkUI', '[DOCK] up screen=%{public}d,%{public}d item=%{public}s', Math.round(x), Math.round(y), item === null ? 'none' : item.panel)
        if (item !== null) { this.activateDockAction(item) }
      }
      return
    }
    if (event.type === TouchType.Cancel) {
      this.dockTouchActive = false
    }
  }

  // 底部详情卡片触摸交互：只处理头部关闭按钮，
  // Swiper body 区域返回 false，让 Swiper 自身手势系统处理水平滑动。
  private handleInfoWinTap(x: number, y: number): boolean {
    if (!isObjectDetailCardPoint(x, y, this.objectDetailStore.isObjectDetailCardRendered(this.infoWindowStore.infoWinVisible), this.detailCardX(), this.detailCardY(), this.detailCardWidth(), this.detailCardHeight())) { return false }
    const bcX = this.detailCardX()
    const bcY = this.detailCardY()
    const bcW = this.detailCardWidth()
    // 只处理头部区域（前 ~48px：名称 + 类型 + 关闭按钮）
    const headerH = 48
    if (y <= bcY + headerH) {
      const closeW = 40
      if (x >= bcX + bcW - closeW) {
        this.dismissObjectInspector()
        return true
      }
      // 头部其他区域点击不做任何操作
      return true
    }
    // Swiper body 区域也消费触摸，防止详情卡内点击穿透到星图选星。
    // Swiper 的水平滑动仍由 ArkUI 组件自身处理。
    return true
  }

// ===== 几何与布局 =====

  // （定时器自持；面板路由 / refreshState / flashHint 经 BehaviorHostHooks，叠层几何与桥回包 flags
  // 抽取经 PolarScopeHostHooks）。宿主保留叠层几何 polarScopeTopInset / polarScopeControlWidth /
  // polarScopeFooterHeight（A-保留 51，PolarScopeOverlay 以 @Prop 消费）与命中区。

  private polarScopeTopInset(): number {
    const safeTop = this.getUIContext().px2vp(Math.max(0, this.screenSafeTopPixels))
    return Math.max(8, safeTop + 8)
  }

  private polarScopeControlWidth(): number {
    return Math.max(0, Math.min(520, this.skyWidth - 32))
  }

  private polarScopeFooterHeight(): number {
    return this.isExpandedLayout ? 148 : 176
  }

  private mediaPreviewTopInset(): number {
    const safeTop = this.getUIContext().px2vp(Math.max(0, this.screenSafeTopPixels))
    return Math.max(18, safeTop + 12)
  }

  private viewCoordinateOverlayWidth(): number {
    return Math.min(this.isExpandedLayout ? 310 : 270, Math.max(210, this.skyWidth - 32))
  }

  private viewCoordinateOverlayLeft(): number {
    const base = Math.max(16, (this.skyWidth - this.viewCoordinateOverlayWidth()) / 2)
    return base + this.clampedViewCoordinateOffsetX(base)
  }

  private viewCoordinateOverlayTop(): number {
    const base = this.isFoldHoverLayout ? 52 : (this.isExpandedLayout ? 64 : 102)
    return base + this.clampedViewCoordinateOffsetY(base)
  }

  private clampedViewCoordinateOffsetX(base: number): number {
    const width = this.viewCoordinateOverlayWidth()
    return clamp(this.viewCoordinateOffsetX, 8 - base, this.skyWidth - width - 8 - base)
  }

  private clampedViewCoordinateOffsetY(base: number): number {
    const height = 92
    return clamp(this.viewCoordinateOffsetY, 8 - base, this.skyHeight - height - 8 - base)
  }

  // 顶层 HostLocationPort 适配器）。


  private scriptControlSafeTop(): number {
    const safeTop = this.getUIContext().px2vp(Math.max(0, this.screenSafeTopPixels))
    return Math.max(this.EDGE_MARGIN, safeTop + 12)
  }

  private guideCardWidth(): number { return Math.max(200, Math.min(440, this.skyWidth - 24)) }

  // ── 顶部搜索栏（中等宽度，点击打开搜索面板） ──
  private bottomCardX(): number {
    const base = baseBottomCardX(this.isExpandedLayout, this.isFoldHoverLayout, this.skyWidth, this.EDGE_MARGIN, this.bottomCardWidth())
    return base + this.clampedObjectCardOffsetX(base, this.bottomCardWidth())
  }

  private bottomCardY(): number {
    const base = baseBottomCardY(this.isExpandedLayout, this.skyHeight, this.EDGE_MARGIN, this.scriptControlSafeTop())
    return base + this.clampedObjectCardOffsetY(base, this.bottomCardHeight())
  }

  private detailCardX(): number {
    return this.bottomCardX()
  }

  private detailCardY(): number {
    return this.detailConnectorCtl().objectDetailCardY()
  }

  private detailCardWidth(): number {
    return this.bottomCardWidth()
  }

  private detailCardHeight(): number {
    return this.bottomCardHeight()
  }

  private clampedObjectCardOffsetX(base: number, width: number): number {
    return clamp(this.cardOffsetX, 8 - base, this.skyWidth - width - 8 - base)
  }

  private clampedObjectCardOffsetY(base: number, height: number): number {
    const top = this.scriptControlSafeTop()
    const bottom = this.isExpandedLayout ? this.skyHeight - 8 : this.compactPanelBottom()
    return clamp(this.cardOffsetY, top - base, Math.max(top, bottom - height) - base)
  }

  private bottomCardWidth(): number {
    // 手机详情卡保持左右对称留白，避免视觉上贴住右侧边框。
    if (!this.isExpandedLayout && !this.isFoldHoverLayout) { return Math.min(380, Math.max(286, this.skyWidth - 58)) }
    if (!this.isExpandedLayout) { return Math.min(318, Math.max(280, this.skyWidth - 52)) }
    // Keep the same responsive width while other panels open and close.
    return clamp(this.skyWidth * 0.38, 340, 480)
  }

  private bottomCardHeight(): number {
    // 观测极简卡：内容只有页头 + 三 tag + 按钮行（见 ObjectDetailCardHeader 的取值），
    // 高度必须与内容一致，否则卡内会留大片空底（展开 / 天文馆模式仍走下面的全量高度）。
    if (this.infoWindowStore.observeCompact()) {
      return this.observeCompactCardHeight()
    }
    if (this.isExpandedLayout) { return Math.min(440, Math.max(360, this.skyHeight - 176)) }
    const available = Math.max(120, this.compactPanelBottom() - this.scriptControlSafeTop())
    if (this.isFoldHoverLayout) { return Math.min(380, available, Math.max(120, this.compactPanelBottom() - this.hoverConsoleTop() - 20)) }
    return Math.min(available, clamp(this.skyHeight * 0.56, 320, 420))
  }

  // 观测极简卡高度 = 拖拽柄 26 + 标题行 (16 内边距 + 36 聚焦圈) + 三 tag 行 (3+46+7) + 下沿箭头条 28。
  private observeCompactCardHeight(): number {
    return 26 + 52 + 56 + 28
  }

  private expandedDetailSummaryX(): number {
    const base = baseExpandedDetailSummaryX(this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN)
    return base + this.clampedObjectCardOffsetX(base, expandedDetailSummaryWidth(this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN))
  }

  private expandedDetailSummaryY(): number {
    // 上移：原先 +84 使小详情卡偏中，遮挡视野中心；贴近顶部留出更多星空可视区
    const base = baseExpandedDetailSummaryY(this.EDGE_MARGIN)
    return base + this.clampedObjectCardOffsetY(base, expandedDetailSummaryHeight())
  }

  // 平板检查器固定贴在左侧：保留大部分星图，并给底部 Dock 留出触控空间。
  private tabletInspectorWidth(): number {
    return clamp(this.skyWidth * 0.32, 340, 390)
  }

  private tabletInspectorX(): number {
    const base = baseTabletInspectorX(this.EDGE_MARGIN)
    return base + this.clampedObjectCardOffsetX(base, this.tabletInspectorWidth())
  }

  private tabletInspectorY(): number {
    const base = baseTabletInspectorY(this.EDGE_MARGIN)
    return base + this.clampedObjectCardOffsetY(base, tabletInspectorHeight(this.skyHeight, this.EDGE_MARGIN))
  }

  private compactObjectPeekWidth(): number {
    // Keep the selected-object peek entirely clear of the right-side gyro and
    // audio controls. On narrow phones the old 250vp minimum overlapped them.
    const quickLeft = this.compactTopQuickX()
    return Math.min(Math.max(210, quickLeft - 34), 320)
  }

  private compactObjectPeekX(): number {
    const base = this.baseCompactObjectPeekX()
    return base + this.clampedObjectCardOffsetX(base, this.compactObjectPeekWidth())
  }

  private baseCompactObjectPeekX(): number {
    const quickLeft = this.compactTopQuickX()
    const rightBound = quickLeft - 14
    return Math.max(16, Math.min((this.skyWidth - this.compactObjectPeekWidth()) / 2, rightBound - this.compactObjectPeekWidth()))
  }

  private compactObjectPeekY(): number {
    const base = baseCompactObjectPeekY()
    return base + this.clampedObjectCardOffsetY(base, 72)
  }

  private hoverBottomCardY(): number {
    const base = this.baseHoverBottomCardY()
    return base + this.clampedObjectCardOffsetY(base, this.bottomCardHeight())
  }

  private baseHoverBottomCardY(): number {
    return Math.max(this.scriptControlSafeTop(), this.compactPanelBottom() - this.bottomCardHeight())
  }

  private compactPanelUsableHeight(): number {
    if (this.isFoldHoverLayout) {
      return Math.max(120, Math.min(520, this.compactPanelBottom() - this.hoverConsoleTop() - 12))
    }
    return Math.max(120, this.compactPanelBottom() - this.scriptControlSafeTop() - 16)
  }

  private hoverSkyPaneHeight(): number {
    const angle = clamp(this.responsiveFoldAngle(), 55, 150)
    const ratio = clamp(0.43 + ((angle - 55) / 95) * 0.13, 0.43, 0.56)
    return clamp(this.skyHeight * ratio, 240, Math.max(280, this.skyHeight - 320))
  }

  private hoverConsoleTop(): number {
    return this.hoverSkyPaneHeight() + 10
  }

  private hoverPanelTop(): number {
    return this.compactPanelTop()
  }

  // ── 快捷面板二期：自定义（拖动-替换）──
  // 12 格顺序（条目 id 序列，长度恒 12）。编辑态只在内存里改，「完成」才落盘；返回 / 点面板外即丢弃。
  // 顺序与编辑态全部收在面板自己的 store（QuickPanelStore，定义在 panels/panels/QuickPanel.ets）：
  // 进入 / 提交 / 丢弃 / 恢复默认 / 拖动-替换都是 store 的方法，宿主只持有实例并注入落盘与提示 hooks。
  @State private quickPanelStore: QuickPanelStore = new QuickPanelStore()

  // 标题栏动作按钮的标签：图层面板 = 清除坐标与标记；快捷面板 = 进入 / 退出自定义（编辑态）。
  // 空串即不渲染该按钮（PanelHeader 既有约定）。
  private panelHeaderActionLabel(): string {
    if (this.activePanel === 'layers') return '清除坐标与标记'
    if (this.activePanel === 'quick') {
      return I18n.t(this.quickPanelStore.editable ? 'quick_customize_done' : 'quick_customize')
    }
    return ''
  }

  // 快捷面板要求动作按钮「只出图标不出文字」：自定义=铅笔、完成=勾。其余面板返回空串走文字路径。
  private panelHeaderActionIcon(): string {
    if (this.activePanel !== 'quick') return ''
    return this.quickPanelStore.editable ? 'check' : 'edit'
  }

  private handlePanelHeaderAction(): void {
    if (this.activePanel === 'quick') {
      this.quickPanelStore.toggleEdit()
      this.publishUiPanelState()
      return
    }
    if (this.activePanel === 'layers') { this.layerCtl().clearMarkingLayers() }
  }

  // 快捷面板高度按内容算（标题栏 + 两行图标；编辑态再加候选带与操作条），只用于该面板（见 QUICK-ACTIONS-PANEL-PLAN §6/§13.5）。
  // 单元格宽由面板内宽均分（QuickActionCell 是 layoutWeight(1) + aspectRatio(1)），所以高度可预知；
  // 容器高度与内容一致时 Scroll 不会把内容垂直居中，图标就贴着标题栏。
  //
  // 但格子宽度是「均分后的浮点值」，ArkUI 落布局时会把它对齐到整物理像素，且取整方向不保证向下：
  // 直接拿理论值当高度就会比真实两行矮一点点（计划 §12.6 第 4 条实测视口 112.7vp < 真实两行 113.3vp，
  // 密度 3.5 下差约 2px），第二行下沿随即被 Scroll 视口切掉。故这里把格子显式**向上**对齐到整物理像素，
  // 让由它推出的面板高度必定不小于图标的真实高度 —— 宁可多出不足 1px 的空白，也不切掉图标。
  private quickPanelGridCellSize(): number {
    const inner = this.isExpandedLayout
      ? this.panelWidth - 36
      : (this.isFoldHoverLayout ? this.skyWidth * 0.64 : this.skyWidth * 0.94) - this.compactPanelHorizontalPadding() * 2
    // 分子扣掉 5 个格间隙（QuickActionGrid 的 Row space = 4）。
    const cell = Math.max((inner - 20) / 6, 40)
    const density = this.getUIContext().vp2px(1)
    if (!(density > 0)) return cell
    return Math.ceil(cell * density) / density
  }

  private quickPanelContentHeight(): number {
    const cell = this.quickPanelGridCellSize()
    // 槽位固定两行（行宽 6）。
    const slots = cell * 2 + 6
    // 展开/编辑态才出现：分隔线（上距 10 + 高 1）+ 候选带（首行上距 12，行内径 6）。
    // 行数必须与 QuickPanel 的行渲染同源，否则高度对不上会被 Scroll 垂直居中。
    const showMore = this.quickPanelStore.expanded || this.quickPanelStore.editable
    const candidateRows = showMore ? quickCandidateRowsFor(this.quickPanelStore.order) : 0
    const candidates = candidateRows > 0 ? (10 + 1 + 12 + candidateRows * cell + (candidateRows - 1) * 6) : 0
    const editableExtra = this.quickPanelStore.editable ? (8 + 28) : 0
    // 理论高度之外再留 4 物理像素的「取整余量」：内容里有两类逐项物理像素对齐 ——
    // 每行 6 格按浮点宽均分后各自对齐（每行最多多占 1px），以及固定 chrome（抓手 / 头部 / 内外边距）
    // 各自对齐。真机 Mate 80 Pro 实测真实占用比理论值多约 2px，第二行下沿就被 Scroll 视口切掉；
    // 4px 不足半个 vp，肉眼不可见，但保证视口永远不小于内容。
    const grid = slots + candidates + editableExtra + this.getUIContext().px2vp(4)
    const header = this.timeStore.panelSubtitle(this.activePanel).length > 0 ? 56 : 44
    if (this.isExpandedLayout) {
      // PanelHandle 高 30（28 + margin 2），floatingPanel 内边距 18。
      const height = 18 + 30 + header + 14 + grid + 18
      // 超出可用高度时交给面板内 Scroll。
      return Math.min(height, this.expandedPanelUsableHeight())
    }
    // PanelHandle 高 30（28 + margin 2），compactPanel 内边距 top 12 / bottom 16。
    const height = 12 + 30 + header + 14 + grid + 16
    // 展开后可能超出可用高度；超出部分交给面板内 Scroll，避免顶到状态栏。
    return Math.min(height, this.compactPanelUsableHeight())
  }

  private compactPanelHeight(): number {
    if (this.activePanel === 'quick') {
      // quick 的高度完全由内容决定（展开态切换时由面板的 .animation 过渡），
      // 拖动只负责跨阈值切换展开态。
      return this.quickPanelContentHeight()
    }
    const usable = this.compactPanelUsableHeight()
    const minH = Math.min(usable, 280)
    return clamp(usable * this.compactPanelSnapRatio - this.compactPanelDragOffsetY, minH, usable)
  }

  private updateCompactPanelDrag(offsetY: number): void {
    const usable = this.compactPanelUsableHeight()
    this.compactPanelDragOffsetY = clamp(offsetY, -usable * 0.34, usable * 0.12)
    if (this.activePanel === 'quick') {
      // 实时预览：上拖略过阈值即展开，下拖即收起（内容高度随 store 变化）。
      if (this.compactPanelDragOffsetY < -8 && !this.quickPanelStore.expanded) {
        this.quickPanelStore.setExpanded(true)
      } else if (this.compactPanelDragOffsetY > 8 && this.quickPanelStore.expanded) {
        this.quickPanelStore.setExpanded(false)
      }
    }
  }

  private settleCompactPanelDrag(): void {
    if (this.activePanel === 'quick') {
      const expand = this.compactPanelDragOffsetY < -24
      const collapse = this.compactPanelDragOffsetY > 24
      this.getUIContext().animateTo({ duration: 320, curve: curves.springMotion(0.46, 0.86) }, () => {
        if (expand) this.quickPanelStore.setExpanded(true)
        if (collapse) this.quickPanelStore.setExpanded(false)
        this.compactPanelDragOffsetY = 0
      })
      this.scheduleSelectedObjectForUiChange(350)
      return
    }
    const usable = this.compactPanelUsableHeight()
    const effectiveRatio = (usable * this.compactPanelSnapRatio - this.compactPanelDragOffsetY) / usable
    const nextRatio = this.compactPanelDragOffsetY > 32 ? 0.6 : (effectiveRatio >= 0.74 ? 0.9 : 0.6)
    this.getUIContext().animateTo({ duration: 360, curve: curves.springMotion(0.46, 0.86) }, () => {
      this.compactPanelSnapRatio = nextRatio
      this.compactPanelDragOffsetY = 0
    })
    this.scheduleSelectedObjectForUiChange(390)
  }

  private updateExpandedPanelDrag(offsetY: number): void {
    // 仅快捷面板需要拖拽展开；搜索/图层/设置沿用全高，不参与高度拖拽。
    if (this.activePanel !== 'quick') return
    const usable = this.expandedPanelUsableHeight()
    this.expandedPanelDragOffsetY = clamp(offsetY, -usable * 0.34, usable * 0.12)
    if (this.expandedPanelDragOffsetY < -8 && !this.quickPanelStore.expanded) {
      this.quickPanelStore.setExpanded(true)
    } else if (this.expandedPanelDragOffsetY > 8 && this.quickPanelStore.expanded) {
      this.quickPanelStore.setExpanded(false)
    }
  }

  private settleExpandedPanelDrag(): void {
    if (this.activePanel !== 'quick') return
    const expand = this.expandedPanelDragOffsetY < -24
    const collapse = this.expandedPanelDragOffsetY > 24
    this.getUIContext().animateTo({ duration: 320, curve: curves.springMotion(0.46, 0.86) }, () => {
      if (expand) this.quickPanelStore.setExpanded(true)
      if (collapse) this.quickPanelStore.setExpanded(false)
      this.expandedPanelDragOffsetY = 0
    })
    this.scheduleSelectedObjectForUiChange(350)
  }

  private expandedUiAllowed(): boolean {
    // updateResponsiveLayout() has already classified this window as expanded.
    // Do not apply a second, stricter size threshold here: the physical Pad
    // reports a 673vp short side in landscape and otherwise loses its rail.
    return this.isExpandedLayout
  }

  // 快捷面板标题栏文案 = 位置面板「位置」行的同一字符串（引擎轮询在 handleEngineState 里
  // 按「来源 + 观测星球」持续刷新 locationText），两处显示必须完全一致。
  private quickPanelLocationLabel(): string {
    return this.locationText
  }

  // 快捷操作面板各项当前值（一律读既有 store，与池中 id 一一对应）。
  // 入口类（type === 'entry'）**刻意不入表**：查不到即恒为 false，格子永远不会显示成「永久点亮」。
  private async persistNightModePreference(night: boolean): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const store = await preferences.getPreferences(ctx, NIGHT_MODE_STORE)
      await store.put('nightMode', night)
      await store.flush()
    } catch (error) {
      hilog.warn(0x0000, 'StellariumArkUI', '[night] persist preference failed')
    }
  }

  private quickActionValues(): Record<string, boolean> {
    return {
      'constellation_lines': this.layerStore.constellationLines,
      'constellation_labels': this.layerStore.constellationLabels,
      'constellation_art': this.layerStore.constellationArt,
      'equatorial_grid': this.layerStore.equatorialGrid,
      'azimuthal_grid': this.layerStore.azimuthGrid,
      'ground': this.layerStore.ground,
      'atmosphere': this.layerStore.atmosphere,
      'cardinal_points': this.layerStore.cardinalPoints,
      'nebulae': this.layerStore.nebulae,
      'satellites': this.satelliteStore.satHints,
      'gyroscope': this.gyroStore.gyroscopeVisualEnabled(),
      'night_mode': this.nightModeStore.nightMode,
      'equatorial_mount': this.telescopeStore.equatorialMount,
      'flip_horizontal': this.polarScopeStore.polarScopeHorizontalFlip,
      'observe_mode': this.infoWindowStore.observeModeEnabled()
    }
  }

  // 陀螺仪驱动时引擎会强制 Alt-Az；先清掉赤道仪开关，避免两个模式同时写星图。
  private syncEquatorialOffForGyro(): void {
    if (this.telescopeStore.equatorialMount) {
      this.telescopeStore.equatorialMount = false
      this.telescopeStore.persistEquatorialMount()
      this.layerCtl().applyLayerSwitch('actionSwitch_Equatorial_Mount', '', false)
    }
  }

  // 快捷操作面板的动作分发：入口类跳面板，开关类各走本域既有入口，图层类走 applyLayerSwitch。
  private quickToggle(id: string, value: boolean): void {
    const item = quickActionById(id)
    if (item === undefined) return
    if (item.type === 'entry') {
      // 入口类不切换开关态，只跳面板（格子恒不高亮，见 quickActionValues 注释）。
      this.openSubPanel(item.openPanel)
      return
    }
    if (id === 'satellites') {
      this.satelliteCtl().setSatelliteFlag('hints', value)
      return
    }
    if (id === 'gyroscope') {
      if (value) this.syncEquatorialOffForGyro()
      this.gyroCtl().requestGyroscopeToggle(value)
      return
    }
    if (id === 'night_mode') {
      this.nightModeStore.applyNightMode(value, true)
      return
    }
    if (id === 'equatorial_mount') {
      // 陀螺仪会持续把引擎拉回 Alt-Az，选赤道仪前先停掉它，避免来回切换。
      if (value && this.gyroStore.gyroscopeVisualEnabled()) {
        this.gyroCtl().requestGyroscopeToggle(false)
      }
      this.telescopeStore.equatorialMount = value
      this.layerCtl().applyLayerSwitch('actionSwitch_Equatorial_Mount', '', value)
      return
    }
    if (id === 'flip_horizontal') {
      // 引擎那一位是**全局**镜像，应用内唯一真值就是极轴镜那一份（由会话 flags.flipHorz 回读），
      // 故复用其写入入口：含乐观写与失败回滚，快捷面板与极轴镜叠层天然同步（见计划 §13.6）。
      this.polarScopeCtl().setPolarScopeHorizontalFlip(value)
      return
    }
    if (id === 'observe_mode') {
      // 只切详情卡的**呈现轴**：不调 setInformationSetting、不刷新选中详情（数据本来就在 store 里）。
      this.applyObserveMode(value)
      return
    }
    // 其余图层类：走公开入口 applyLayerSwitch（与图层面板同一路径，附带「已显示/已隐藏」提示）。
    if (item.actionId.length > 0) { this.layerCtl().applyLayerSwitch(item.actionId, '', value) }
  }

  private canonicalDockActions(): ShellAction[] {
    return [
      primaryDockActions()[0],
      primaryDockActions()[1],
      primaryDockActions()[2],
      primaryDockActions()[3],
      { label: I18n.t('c_more_functions'), icon: 'more', panel: 'more' }
    ] as ShellAction[]
  }

  // 手机与半折：左右两端取同一个 x，等价于跟随 dock 两端（与改造前，回归安全）。
  // 平板：改贴屏幕左右缘 —— 平板 dock 宽度封顶 640，且面板打开时会被挤到面板右侧，
  // 继续跟随 dock 两端会让三件套随面板开合整体横移，读数位置"漂"。
  private chromeRowY(): number {
    return this.dockTop() - CHROME_ROW_OFFSET
  }

  // 竖排（手机·半折，列高 96）还是横排（平板，一行 44 高）：平板 dock 只有 54 高，
  // 96 高的竖排压在它上方过于突兀，横排更贴近平板的工具条语汇。
  private chromeZoomHorizontal(): boolean {
    return this.isExpandedLayout
  }

  private compactDockWidthPercent(): number {
    if (this.isFoldHoverLayout) {
      return 58
    }
    // Keep the phone Dock a stable width when a panel opens instead of letting
    // it jump between a panel-visible and idle percentage.
    const width = Math.max(1, this.skyWidth)
    const targetWidth = Math.min(420, Math.max(288, width - 48))
    return clamp(targetWidth * 100 / width, 82, 92)
  }

  private compactDockLabelFontSize(): number {
    if (this.isExpandedLayout) return this.isLargeDesktopCanvas() ? 14 : 12
    return this.isFoldHoverLayout ? 11 : 12
  }

  private compactDockIconSize(): number {
    if (this.isExpandedLayout) return this.isLargeDesktopCanvas() ? 28 : 24
    return this.isFoldHoverLayout ? 22 : 23
  }

  private compactDockItemHeight(): number {
    if (this.isExpandedLayout) return this.isLargeDesktopCanvas() ? 68 : 62
    return this.isFoldHoverLayout ? 52 : 56
  }

  private compactPanelHorizontalPadding(): number {
    return this.isFoldHoverLayout ? 14 : 18
  }

  private dockTop(): number {
    return Math.max(0, this.skyHeight - this.dockHeight() - this.dockBottomClearance())
  }

  private dockHeight(): number {
    return this.isExpandedLayout ? (this.isLargeDesktopCanvas() ? 78 : 72) : 66
  }

  private isLargeDesktopCanvas(): boolean {
    // Freeform HarmonyOS PC windows report vp dimensions after display density
    // conversion, so a visually large 2-in-1 window can be ~540vp wide even
    // though it covers >1000 physical pixels. Keep phones out of this branch
    // while treating that PC window as a readable large canvas.
    return this.isExpandedLayout && (this.skyWidth >= 520 || (this.skyWidth >= 700 && this.skyHeight >= 500))
  }

  private publishUiLayoutState(): void {
    AppStorage.setOrCreate('stellariumUiLayoutState', JSON.stringify({
      ok: true, ready: this.skyWidth > 1 && this.skyHeight > 1,
      width: this.skyWidth, height: this.skyHeight, mode: this.responsiveLayoutMode,
      override: this.uiLayoutOverride, expanded: this.isExpandedLayout,
      readable: this.isLargeDesktopCanvas(), touchCoordinateSpace: 'component',
      dockLeft: dockLeft(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()),
      dockTop: this.dockTop(), dockHeight: this.dockHeight(),
      dockWidth: dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()),
      dockLabelFontSize: this.compactDockLabelFontSize()
    }))
  }

  private dockBottomClearance(): number {
    return this.getUIContext().px2vp(Math.max(0, this.screenSafeBottomPixels)) + 30
  }

  private dockBottom(): number {
    return this.dockTop() + this.dockHeight()
  }

  private compactPanelBottom(): number {
    return this.dockTop() - 10
  }

  private compactPanelTop(): number {
    return this.compactPanelBottom() - this.compactPanelHeight()
  }

  private panelTop(): number {
    return this.isExpandedLayout ? this.expandedPanelTop() : (this.EDGE_MARGIN + this.panelOffsetY)
  }

  // 展开布局的底部面板可用高度：Dock 上沿 - 10vp 间距 - 顶部安全边距。
  private expandedPanelUsableHeight(): number {
    return Math.max(220, this.dockTop() - 10 - this.EDGE_MARGIN)
  }

  // 展开布局面板高度：quick 由内容决定并可拖拽展开；时间与手机一致，默认 0.6
  // 可用高度（显示到倒带-实时一行，其余交给滚动）；搜索/图层/设置沿用平板全高。
  private expandedPanelHeight(): number {
    const usable = this.expandedPanelUsableHeight()
    if (this.activePanel === 'quick') {
      return Math.min(this.quickPanelContentHeight(), usable)
    }
    if (this.activePanel === 'time') {
      const block = this.timeSpeedBlockHeight
      if (block <= 0) return usable * 0.6
      const header = this.timeStore.panelSubtitle(this.activePanel).length > 0 ? 56 : 44
      return Math.min(18 + 30 + header + 14 + block + 18, usable)
    }
    return usable
  }

  // 底部对齐：面板下沿固定在 Dock 上方 10vp。
  private expandedPanelTop(): number {
    return Math.max(this.EDGE_MARGIN, this.dockTop() - 10 - this.expandedPanelHeight())
  }

  private objectInspectorInlineModelSize(): number {
    return Math.min(200, Math.max(80, this.bottomCardWidth() - 112))
  }

  // 手机上的常驻控件随空闲状态变为轻透玻璃；展开和平板悬停布局保持各自的面板规则。
  private phoneChromeOpacity(): number {
    return (!this.isExpandedLayout && !this.isFoldHoverLayout) ? this.panelIdleOpacity : 1.0
  }

  private phoneChromeIsGlass(): boolean {
    return !this.isExpandedLayout && !this.isFoldHoverLayout && this.panelIdleGlass
  }

// ===== 各域行为 =====

// ----- 对象选中 / 详情 -----

  // 拉取当前选中天体的信息并刷新详情面板。
  // 加防重入：避免自动刷新(1Hz)与手动“刷新”按钮重叠，导致 consume-on-read 结果被互相冲掉。
  // callNativeWhenReady 放弃轮询时不会回调，所以配 detailRefreshGuard 兜底复位，防止永久卡死。
  // detailRefreshing / detailRefreshGuard 的所有权随 移交 capability/DetailConnectorController.ets。
  private refreshSelectedObject(): void {
    if (this.detailConnectorCtl().isDetailRefreshing()) { return }
    const expectedName = this.objectDetailStore.selectedName
    const selectionSerial = this.skySelectionRequestSerial
    this.detailConnectorCtl().beginDetailRefresh()
    const detailsNeeded = !this.objectDetailStore.selectedDetailLoaded && (this.fullInspectorRequested || useTabletObjectInspector())
    if (detailsNeeded && this.objectDetailStore.selectedDetailRequestPending) {
      this.detailConnectorCtl().endDetailRefresh()
      return
    }
    const details = detailsNeeded ? 'details' : ''
    if (details === 'details') { this.objectDetailStore.selectedDetailRequestPending = true }
    this.callInteractive('getSelectedObjectInfo', details, (r) => {
      if (details === 'details') { this.objectDetailStore.selectedDetailRequestPending = false }
      this.detailConnectorCtl().endDetailRefresh()
      if (selectionSerial !== this.skySelectionRequestSerial || expectedName !== this.objectDetailStore.selectedName) {
        return
      }
      this.applySelectedObject(r, true)
    }, () => {
      if (details === 'details') { this.objectDetailStore.selectedDetailRequestPending = false }
      this.detailConnectorCtl().endDetailRefresh()
    })
  }

  private objectDetailMarkerSize(): number {
    const fov = clamp(this.fovSliderValue > 0 ? this.fovSliderValue : 60, 4, 180)
    return clamp(32 * Math.pow(60 / fov, 0.35), 24, 58)
  }

  // 只补「动态值」的即时刷新（星等 / 大气消光后星等 / 方位 / 距离 …）。
  //
  // 触摸点选的 `selectAt` 回包是**刻意轻量**的：C++ 侧走 `selectedObjectJson(core, false, false)`，
  // 即 `includeDynamic = false`（卫星的 getInfoMap 会在渲染线程同步算遥测，带上它会拖慢选中绘制），
  // 所以它只有名称 / 类型 / 媒体字段 —— 星等一类全都不在回包里。
  //
  // 原先这些动态值只由 `requestSelectedDetails` 的 550ms 定时器发出，而那条请求带 `details`
  // （要等结构化字段全量收集完）→ 星等于是排在「550ms + 全量收集」之后才出现，比名称慢一大截。
  // 这里在选中回包落地后立刻用**同一条命令但不带 details**补一次：动态值随即可用，
  // 全量结构化字段仍走原来的 550ms 那条路（两者互不覆盖：不带 details 的回包没有 detailFields 键）。
  private refreshSelectedDynamicValues(): void {
    // 刻意**不**做 `isDetailRefreshing()` 短路：每次选中都会换 `skySelectionRequestSerial`，上一轮
    // 180ms 轮询的在途回包本就会被丢弃，不必等它收尾；若等，点选恰好落在轮询在途窗口（约占一次
    // 180ms 周期的 100ms）时这次补拉会被挡掉，星等又退回 550ms 之后。直接发起并重置守卫即可。
    const expectedName = this.objectDetailStore.selectedName
    const selectionSerial = this.skySelectionRequestSerial
    this.detailConnectorCtl().beginDetailRefresh()
    this.callInteractive('getSelectedObjectInfo', '', (r) => {
      this.detailConnectorCtl().endDetailRefresh()
      if (selectionSerial !== this.skySelectionRequestSerial || expectedName !== this.objectDetailStore.selectedName) {
        return
      }
      this.applySelectedObject(r, true)
    }, () => {
      this.detailConnectorCtl().endDetailRefresh()
    })
  }

  private requestSelectedDetails(expectedName: string): void {
    if (this.objectDetailStore.selectedDetailTimer !== 0) {
      clearTimeout(this.objectDetailStore.selectedDetailTimer)
    }
    this.objectDetailStore.selectedDetailRequestPending = true
    // Let selection, initial layout, and navigation start finish before asking
    // Qt to collect the complete structured field set.
    this.objectDetailStore.selectedDetailTimer = setTimeout(() => {
      this.objectDetailStore.selectedDetailTimer = 0
      if (!this.infoWindowStore.infoWinVisible || this.objectDetailStore.selectedName !== expectedName) {
        this.objectDetailStore.selectedDetailRequestPending = false
        return
      }
      if (this.skyDragging) {
        this.requestSelectedDetails(expectedName)
        return
      }
      this.callInteractive('getSelectedObjectInfo', 'details', (r) => {
        const returnedName = r.name && r.name.length > 0 ? r.name : r.englishName
        if (r.ok === true && r.found === true && returnedName === this.objectDetailStore.selectedName) {
          this.applySelectedObject(r, true)
        }
        this.objectDetailStore.selectedDetailRequestPending = false
      }, () => {
        this.objectDetailStore.selectedDetailRequestPending = false
      })
    }, 550) as number
  }

  private moveToSelectedObject(fromLayoutChange: boolean = false): void {
    if (!this.objectDetailStore.hasSelectedObject()) {
      this.flashHint(I18n.t('center_requires_selection'))
      return
    }
    // Sensor pose is the camera owner while gyro mode is active. Starting a
    // second auto-move here creates a visible jump when the next pose sample
    // correctly takes control back, so center/track only refresh the guide.
    if (this.gyroStore.gyroscopeEnabled) {
      this.gyroCtl().updateGyroTargetGuide(true)
      this.flashHint(I18n.t('center_unavailable_gyro'))
      return
    }
    if (fromLayoutChange) {
      this.placeSelectedObjectInSafeArea('layout')
      return
    }
    this.navigateSelectedObjectTo(this.skyWidth / 2, this.skyHeight / 2, 'center')
  }

  private navigateSelectedObjectTo(x: number, y: number, mode: string = 'focus'): void {
    if (this.skyWidth <= 1 || this.skyHeight <= 1) { return }
    const payload = `${Math.round(x)}|${Math.round(y)}|${Math.round(this.skyWidth)}|${Math.round(this.skyHeight)}|${mode}`
    const navigationKey = this.objectDetailStore.selectedName + '|' + payload
    hilog.info(0x0000, 'StellariumArkUI', 'safe-target request mode=%{public}s compact=%{public}s panel=%{public}s drawer=%{public}s info=%{public}s target=%{public}s',
      mode, (!this.isExpandedLayout).toString(), this.panelVisible.toString(), 'false', this.infoWindowStore.infoWinVisible.toString(), payload)
    const now = Date.now()
    // A layout callback can re-fire long after its animation has settled.
    // Repeating the same safe point would move a time-anchored target for no
    // visible UI change. Focus commands still pass through after the short
    // debounce so the explicit centre action remains available.
    if (mode === 'layout' && navigationKey === this.lastSafeNavigationPayload) {
      hilog.info(0x0000, 'StellariumArkUI', 'safe-target skipped unchanged layout')
      return
    }
    if (navigationKey === this.lastSafeNavigationPayload && now - this.lastSafeNavigationAt < 420) {
      return
    }
    this.lastSafeNavigationPayload = navigationKey
    this.lastSafeNavigationAt = now
    this.callInteractive('moveToSelectedAt', payload, (r) => {
      if (r.ok !== true) {
        this.flashHint(r.error ?? I18n.t('msg_apply_failed'))
        return
      }
      this.applySelectedObject(r)
      if (mode === 'center') {
        this.flashHint(I18n.t('center_applied'))
      }
    }, (r) => {
      this.flashHint(r.error ?? I18n.t('msg_apply_failed'))
    })
  }

  private placeSelectedObjectInSafeArea(mode: string = 'focus'): void {
    const fallback = this.isExpandedLayout ? this.expandedSafeTargetPoint() : this.compactSafeTargetPoint()
    if (mode === 'selection' || mode === 'layout') {
      const localTarget = this.selectedObjectLayoutAvoidanceTarget(fallback)
      if (localTarget.length === 2) {
        this.navigateSelectedObjectTo(localTarget[0], localTarget[1], mode)
      }
      return
    }
    this.navigateSelectedObjectTo(fallback[0], fallback[1], mode)
  }

  private selectedObjectUiObstacles(): SkyUiObstacle[] {
    const obstacles: SkyUiObstacle[] = []
    obstacles.push({
      label: 'bottom-dock', left: dockLeft(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()), top: this.dockTop(),
      right: dockLeft(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()) + dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()), bottom: this.skyHeight
    })
    if (this.isExpandedLayout) {
      if (this.panelVisible) {
        obstacles.push({
          label: 'panel', left: expandedMainPanelLeft(this.EDGE_MARGIN, this.panelOffsetX), top: this.panelTop(),
          right: expandedMainPanelLeft(this.EDGE_MARGIN, this.panelOffsetX) + this.panelWidth,
          bottom: this.panelTop() + this.expandedPanelHeight()
        })
      }
      if (this.infoWindowStore.infoWinVisible) {
        if (useTabletObjectInspector()) {
          obstacles.push({
            label: 'object-inspector', left: this.tabletInspectorX(), top: this.tabletInspectorY(),
            right: this.tabletInspectorX() + this.tabletInspectorWidth(), bottom: this.tabletInspectorY() + tabletInspectorHeight(this.skyHeight, this.EDGE_MARGIN)
          })
        } else if (useExpandedDetailSummary() && canShowExpandedDetailSummary(this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN)) {
          obstacles.push({
            label: 'summary', left: this.expandedDetailSummaryX(), top: this.expandedDetailSummaryY(),
            right: this.expandedDetailSummaryX() + expandedDetailSummaryWidth(this.skyWidth, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN),
            bottom: this.expandedDetailSummaryY() + expandedDetailSummaryHeight()
          })
        } else {
          obstacles.push({
            label: 'object-card', left: this.bottomCardX(), top: this.bottomCardY(),
            right: this.bottomCardX() + this.bottomCardWidth(),
            bottom: this.bottomCardY() + this.bottomCardHeight()
          })
        }
      }
      return obstacles
    }

    if (this.panelVisible) {
      const sheetTop = this.compactPanelTop()
      obstacles.push({ label: 'sheet', left: 0, top: sheetTop, right: this.skyWidth, bottom: this.compactPanelBottom() })
    }
    if (!this.panelVisible && this.infoWindowStore.infoWinVisible) {
      if (isPhoneDetailPeek()) {
        obstacles.push({
          label: 'object-peek', left: this.compactObjectPeekX(), top: this.compactObjectPeekY(),
          right: this.compactObjectPeekX() + this.compactObjectPeekWidth(), bottom: this.compactObjectPeekY() + 64
        })
      } else {
        obstacles.push({
          label: 'object-card', left: this.bottomCardX(), top: this.bottomCardY(),
          right: this.bottomCardX() + this.bottomCardWidth(), bottom: this.bottomCardY() + this.bottomCardHeight()
        })
      }
    }
    return obstacles
  }

  private selectedObjectLayoutAvoidanceTarget(fallback: number[]): number[] {
    const projection = this.callNative('getGyroGuidePosition') as GyroGuideProjection
    if (projection.ok !== true || projection.valid !== true || projection.visible !== true ||
      typeof projection.xRatio !== 'number' || typeof projection.yRatio !== 'number') {
      hilog.info(0x0000, 'StellariumArkUI', 'safe-target skipped unavailable projection')
      return []
    }
    const currentX = (projection.xRatio as number) * this.skyWidth
    const currentY = (projection.yRatio as number) * this.skyHeight
    const obstacles = this.selectedObjectUiObstacles()
    let collision: SkyUiObstacle | undefined = undefined
    for (let index = 0; index < obstacles.length; index++) {
      if (pointOverlapsUiObstacle(currentX, currentY, obstacles[index])) {
        collision = obstacles[index]
        break
      }
    }
    if (collision === undefined) {
      hilog.info(0x0000, 'StellariumArkUI', 'safe-target skipped clear x=%{public}d y=%{public}d', Math.round(currentX), Math.round(currentY))
      return []
    }

    const edge = 18
    const gap = 30
    const minX = edge
    const maxX = this.skyWidth - edge
    const minY = edge
    const maxY = this.skyHeight - edge
    const candidates: number[][] = [
      [collision.left - gap, currentY], [collision.right + gap, currentY],
      [currentX, collision.top - gap], [currentX, collision.bottom + gap]
    ]
    let best: number[] = []
    let bestDistance = Number.MAX_VALUE
    for (let index = 0; index < candidates.length; index++) {
      const candidateX = clamp(candidates[index][0], minX, maxX)
      const candidateY = clamp(candidates[index][1], minY, maxY)
      let clear = true
      for (let obstacleIndex = 0; obstacleIndex < obstacles.length; obstacleIndex++) {
        if (pointOverlapsUiObstacle(candidateX, candidateY, obstacles[obstacleIndex], 12)) {
          clear = false
          break
        }
      }
      const distance = Math.pow(candidateX - currentX, 2) + Math.pow(candidateY - currentY, 2)
      if (clear && distance < bestDistance) {
        best = [candidateX, candidateY]
        bestDistance = distance
      }
    }
    if (best.length !== 2 || !Number.isFinite(best[0]) || !Number.isFinite(best[1])) {
      if (!Number.isFinite(fallback[0]) || !Number.isFinite(fallback[1])) {
        hilog.info(0x0000, 'StellariumArkUI', 'safe-target skipped no clear candidate')
        return []
      }
      best = fallback
    }
    hilog.info(0x0000, 'StellariumArkUI', 'safe-target collision %{public}s at=%{public}d|%{public}d target=%{public}d|%{public}d',
      collision.label, Math.round(currentX), Math.round(currentY), Math.round(best[0]), Math.round(best[1]))
    return best
  }

  // UI layout changes only refresh the connector. The selected object owns its
  // current sky position; opening a panel must never move the sky behind it.
  private scheduleSelectedObjectForUiChange(delay: number = 360): void {
    if (this.objectDetailStore.selectedUiLayoutTimer !== 0) {
      clearTimeout(this.objectDetailStore.selectedUiLayoutTimer)
      this.objectDetailStore.selectedUiLayoutTimer = 0
    }
    if (this.objectDetailStore.selectedStatus !== 'Selected') {
      return
    }
    this.objectDetailStore.selectedUiLayoutTimer = setTimeout(() => {
      this.objectDetailStore.selectedUiLayoutTimer = 0
      if (this.objectDetailStore.selectedStatus === 'Selected') {
        this.detailConnectorCtl().refreshObjectDetailConnector()
      }
    }, delay) as number
  }

  private cancelSelectedObjectUiChange(): void {
    if (this.objectDetailStore.selectedUiLayoutTimer !== 0) {
      clearTimeout(this.objectDetailStore.selectedUiLayoutTimer)
      this.objectDetailStore.selectedUiLayoutTimer = 0
    }
  }

  private compactSafeTargetPoint(): number[] {
    // Phone inspectors deliberately live at the top, not at the bottom.
    // Calculate the vertical gap from their real rendered bounds so a locked
    // target never lands inside either the inspector, the bottom dock, or an
    // open sheet. The centre x is clear of the left zoom controls and the
    // right quick controls.
    let top = 38
    let bottom = this.compactPanelBottom()

    // Compact panels replace the detailed object card. Reserving the hidden
    // card's area made a 9/10 sheet calculate a target underneath itself.
    if (this.infoWindowStore.infoWinVisible && !this.panelVisible) {
      if (isPhoneDetailPeek()) {
        top = Math.max(top, this.compactObjectPeekY() + 72 + 28)
      } else {
        top = Math.max(top, this.bottomCardY() + this.bottomCardHeight() + 28)
      }
    }
    let sheetTop = -1
    if (this.panelVisible) {
      sheetTop = this.compactPanelTop()
      bottom = Math.min(bottom, sheetTop - 32)
    }

    // On very short screens, preserve a reachable sky target even when the
    // detail card and a 9/10 sheet leave no conventional vertical gap.
    if (bottom - top < 96) {
      bottom = Math.max(bottom, top + 96)
    }
    const targetY = clamp((top + bottom) / 2, top + 20, bottom - 20)
    hilog.info(0x0000, 'StellariumArkUI', 'compact-safe h=%{public}d usable=%{public}d snap=%{public}s drag=%{public}s sheetTop=%{public}d top=%{public}d bottom=%{public}d targetY=%{public}d',
      Math.round(this.skyHeight), Math.round(this.compactPanelUsableHeight()), this.compactPanelSnapRatio.toString(), this.compactPanelDragOffsetY.toString(), Math.round(sheetTop), Math.round(top), Math.round(bottom), Math.round(targetY))
    return [this.skyWidth / 2, targetY]
  }

  private expandedSafeTargetPoint(): number[] {
    const left = this.panelVisible ? expandedMainPanelLeft(this.EDGE_MARGIN, this.panelOffsetX) + this.panelWidth + 18 : this.EDGE_MARGIN + 64
    const right = this.panelVisible ? this.skyWidth - this.EDGE_MARGIN
      : (this.infoWindowStore.infoWinVisible ? this.bottomCardX() - 18 : this.skyWidth - this.EDGE_MARGIN)
    let top = this.EDGE_MARGIN + 24
    // With both cards open, keep the target below the compact object summary
    // and inside the unobstructed sky to the right of the Pad panel.
    if (this.panelVisible && this.infoWindowStore.infoWinVisible && useExpandedDetailSummary()) {
      top = this.expandedDetailSummaryY() + expandedDetailSummaryHeight() + 28
    }
    const bottom = this.skyHeight - this.EDGE_MARGIN
    if (right - left < 120 || bottom - top < 120) {
      return [this.skyWidth / 2, this.skyHeight / 2]
    }
    return [(left + right) / 2, (top + bottom) / 2]
  }

  private applySelectedInfoMode(mode: string): void {
    this.infoWindowStore.informationMode = mode
    if (mode === 'all') {
      this.infoWindowStore.infoLevel = 0
    } else if (mode === 'default') {
      this.infoWindowStore.infoLevel = 1
    } else if (mode === 'short') {
      this.infoWindowStore.infoLevel = 2
    } else if (mode === 'none') {
      this.infoWindowStore.infoLevel = 3
    } else if (mode === 'custom') {
      this.infoWindowStore.infoLevel = 0
    }
  }

  // applyCustomInformationMask 已于 并回 state/ObjectDetailStore.ets（30 个被清字段全在该 store，
  // 掩码判定以谓词传入）。

  private updateSelectedLiveDetails(fields: Array<ObjectDetailField>): void {
    const previous = this.objectDetailStore.selectedDetailFields
    const updated = previous
      .filter((field: ObjectDetailField) => field.live !== true || fields.some((item: ObjectDetailField) => item.key === field.key))
      .map((field: ObjectDetailField) => field.live === true
        ? (fields.find((item: ObjectDetailField) => item.key === field.key) ?? field) : field)
    this.objectDetailStore.selectedDetailFields = updated.concat(fields.filter((field: ObjectDetailField) =>
      !previous.some((item: ObjectDetailField) => item.key === field.key)))
  }

  // fromRefresh=true 时来自“详情自动刷新”等后台轮询：仅刷新数值，绝不重置展开态、也绝不因瞬时未命中而关窗。
  // userReselect=true 表示这是一次“用户主动选择”（星图点选 / 搜索结果 / WUT 行）：
  // 若用户此前手动关闭了同一目标的详情卡，再次选中它时必须重新弹出，而不是继续抑制。
  private applySelectedObject(result: StellariumBridgeResponse, fromRefresh: boolean = false, placement: string = '', userReselect: boolean = false): void {
    if (result.ok !== true) {
      this.objectDetailStore.selectedStatus = result.error ? result.error : 'Core not ready'
      return
    }
    if (result.found === true) {
      const incomingName = result.name && result.name.length > 0 ? result.name : (result.englishName ? result.englishName : '')
      // 核心的 type 已经由 StelObject::getObjectTypeI18n() 按官方 .qm
      // 资源本地化。objectType 只保留给音频和旧桥接数据，不应覆盖显示文本。
      const incomingType = (result.type && result.type.length > 0)
        ? result.type
        : ((result.objectType && (result.objectType as string).length > 0) ? (result.objectType as string) : 'Object')
      // 只有真正换了目标才重开详情。用户手动关闭同一目标后，任何后续刷新/误触
      // 都只更新数值，不能把卡片重新弹回来。
      const targetChanged = (this.objectDetailStore.selectedName !== incomingName) || (this.objectDetailStore.selectedType !== incomingType)
      const reopenDismissedDetail = userReselect && !targetChanged && !this.infoWindowStore.infoWinVisible
        && this.dismissedObjectName === incomingName
      const preserveClosedDetail = !userReselect && !this.infoWindowStore.infoWinVisible && !targetChanged && this.dismissedObjectName === incomingName
      const isNewSelection = targetChanged
      this.objectDetailStore.selectedName = incomingName
      this.objectDetailStore.selectedEnglishName = result.englishName && result.englishName.length > 0 ? result.englishName : ''
      this.objectDetailStore.selectedCatalogId = result.catalogId && result.catalogId.length > 0 ? result.catalogId : ''
      this.objectDetailStore.selectedDetailMediaPath = result.detailMediaPath && result.detailMediaPath.length > 0 ? result.detailMediaPath : ''
      this.objectDetailStore.selectedDetailMediaKind = result.detailMediaKind && result.detailMediaKind.length > 0 ? result.detailMediaKind : ''
      this.objectDetailStore.selectedDetailMediaLabel = result.detailMediaLabel && result.detailMediaLabel.length > 0 ? result.detailMediaLabel : ''
      this.objectDetailStore.selectedDetailModel = result.detailModel
      this.objectModelRendererCtl().refreshObjectInspectorModelLighting()
      this.objectDetailStore.selectedConstellationCultureId = result.constellationCultureId && result.constellationCultureId.length > 0 ? result.constellationCultureId : ''
      this.objectDetailStore.selectedConstellationCultureName = result.constellationCultureName && result.constellationCultureName.length > 0 ? result.constellationCultureName : ''
      this.objectDetailStore.selectedConstellationCultureDescription = result.constellationCultureDescription && result.constellationCultureDescription.length > 0 ? result.constellationCultureDescription : ''
      this.objectDetailStore.selectedConstellationCultureDescriptionBlocks = result.constellationCultureDescriptionBlocks !== undefined ? result.constellationCultureDescriptionBlocks : []
      this.objectDetailStore.selectedConstellationCultureDescriptionSource = result.constellationCultureDescriptionSource && result.constellationCultureDescriptionSource.length > 0 ? result.constellationCultureDescriptionSource : ''
      this.objectDetailStore.selectedObjectType = result.objectType && result.objectType.length > 0 ? result.objectType : ''
      this.objectDetailStore.selectedTemperatureK = typeof result.temperatureK === 'number' ? result.temperatureK : 0
      this.objectDetailStore.selectedType = incomingType
      this.objectInspectorMediaCtl().refreshObjectInspectorMedia()
      if (result.infoMode !== undefined) {
        if (result.infoMode === 'custom' && result.customInfoMask !== undefined) {
          this.infoWindowStore.informationCustomMask = Number(result.customInfoMask)
        }
        this.applySelectedInfoMode(result.infoMode)
      }
      this.objectDetailStore.selectedStatus = 'Selected'
      const mag = (typeof result.magnitude === 'number') ? (result.magnitude as number) : 99
      const showBasicInfo = this.infoWindowStore.infoLevel <= 2
      const showObservedInfo = this.infoWindowStore.infoLevel <= 1
      this.objectDetailStore.selectedMagnitude = showBasicInfo && mag < 98 ? mag.toFixed(2) : ''
      const apparentMag = (typeof result.apparentMagnitude === 'number') ? (result.apparentMagnitude as number) : 99
      this.objectDetailStore.selectedApparentMagnitude = showObservedInfo && apparentMag < 98 ? apparentMag.toFixed(2) : ''
      this.objectDetailStore.selectedAirmass = showObservedInfo && typeof result.airmass === 'number' ? (result.airmass as number).toFixed(2) : ''
      this.objectDetailStore.selectedExtinction = showObservedInfo && typeof result.extinction === 'number' ? (result.extinction as number).toFixed(2) : ''
      if (result.detailFields !== undefined) {
        this.objectDetailStore.selectedDetailFields = result.detailFields
        this.objectDetailStore.selectedDetailLoaded = true
      } else if (result.liveDetailFields !== undefined && this.objectDetailStore.selectedDetailLoaded) {
        this.updateSelectedLiveDetails(result.liveDetailFields)
      }
      if (result.satellitePasses !== undefined) {
        this.objectDetailStore.selectedSatellitePasses = result.satellitePasses
        this.objectDetailStore.selectedSatellitePassesLoaded = true
      }
      const ra: string = result.ra ? result.ra : ''
      const dec: string = result.dec ? result.dec : ''
      this.objectDetailStore.selectedCoordEq = showBasicInfo && result.equatorialOfDate
        ? result.equatorialOfDate
        : (showBasicInfo && (ra.length > 0 || dec.length > 0) ? (ra + '  ' + dec).trim() : '')
      this.objectDetailStore.selectedCoordEqJ2000 = showBasicInfo && result.equatorialJ2000 ? result.equatorialJ2000 : ''
      this.objectDetailStore.selectedCoordApparentAltAz = showObservedInfo && result.apparentAltAz ? result.apparentAltAz : ''
      this.objectDetailStore.selectedCoordGeometricAltAz = showObservedInfo && result.geometricAltAz ? result.geometricAltAz : ''
      this.objectDetailStore.selectedCoordEcliptic = showBasicInfo && result.eclipticCurrent ? result.eclipticCurrent : ''
      this.objectDetailStore.selectedCoordEclipticJ2000 = showBasicInfo && result.eclipticJ2000 ? result.eclipticJ2000 : ''
      this.objectDetailStore.selectedCoordGalactic = showBasicInfo && result.galactic ? result.galactic : ''
      this.objectDetailStore.selectedCoordSupergalactic = showBasicInfo && result.supergalactic ? result.supergalactic : ''
      this.objectDetailStore.selectedCoordParallactic = showObservedInfo && result.parallacticAngle ? result.parallacticAngle : ''
      const hasAlt: boolean = typeof result.altitude === 'number'
      const hasAz: boolean = typeof result.azimuth === 'number'
      this.gyroCtl().setGuideTarget(hasAz ? result.azimuth as number : Number.NaN, hasAlt ? result.altitude as number : Number.NaN)
      // A stationary device may not pass the sensor movement threshold again
      // after a search. Recalculate the edge guide at selection time instead
      // of waiting for the next meaningful orientation delta.
      if (this.gyroStore.gyroscopeEnabled) {
        this.gyroCtl().updateGyroTargetGuide(true)
      }
      this.objectDetailStore.selectedCoordAlt = showObservedInfo && (hasAlt || hasAz)
        ? (I18n.t('coord_alt') + ' ' + (hasAlt ? fmtDegMin(result.altitude as number) : '--') + '  ' + I18n.t('coord_az') + ' ' + (hasAz ? fmtDegMin(result.azimuth as number) : '--'))
        : ''
      this.objectDetailStore.selectedHourAngle = showObservedInfo && result.hourAngle && result.hourAngle.length > 0 ? result.hourAngle : ''
      this.objectDetailStore.selectedMeanSiderealTime = showObservedInfo && result.meanSiderealTime && result.meanSiderealTime.length > 0 ? result.meanSiderealTime : ''
      this.objectDetailStore.selectedApparentSiderealTime = showObservedInfo && result.apparentSiderealTime && result.apparentSiderealTime.length > 0 ? result.apparentSiderealTime : ''
      this.objectDetailStore.selectedConstellation = showBasicInfo && result.constellation && result.constellation.length > 0 ? result.constellation : ''
      this.objectDetailStore.selectedDistance = showObservedInfo && result.distance && result.distance.length > 0 ? result.distance : ''
      this.objectDetailStore.selectedDistanceCompact = result.distanceCompact ?? result.distance ?? ''
      this.objectDetailStore.selectedDistanceStatus = result.distanceStatus ?? 'unavailable'
      this.objectDetailStore.selectedTleOutdated = result.tleOutdated === true
      // 过滤接近0的角直径（小行星等天体角直径极小，显示0无意义）
      const rawSize = result.size && result.size.length > 0 ? result.size : ''
      if (showObservedInfo && rawSize.length > 0) {
        const sizeMatch = rawSize.match(/([\d.]+)/)
        if (sizeMatch && parseFloat(sizeMatch[1]) === 0) {
          this.objectDetailStore.selectedSize = ''
        } else {
          this.objectDetailStore.selectedSize = rawSize
        }
      } else {
        this.objectDetailStore.selectedSize = ''
      }
      this.objectDetailStore.selectedRise = showObservedInfo && result.rise && result.rise.length > 0 ? result.rise : ''
      this.objectDetailStore.selectedSet = showObservedInfo && result.set && result.set.length > 0 ? result.set : ''
      this.objectDetailStore.selectedTransit = showObservedInfo && result.transit && result.transit.length > 0 ? result.transit : ''
      this.objectDetailStore.selectedPhase = showObservedInfo && typeof result.phase === 'number' ? (result.phase as number).toFixed(0) + '%' : ''
      this.objectDetailStore.selectedElongation = showObservedInfo && typeof result.elongation === 'number' ? (result.elongation as number).toFixed(1) + '°' : ''
      this.objectDetailStore.applyCustomInformationMask(this.infoWindowStore.informationMode, (key: string): boolean => this.infoWindowStore.informationMaskHas(key))
      // 选中成功后弹出独立浮动详情窗口（新目标默认收起，不打扰当前菜单；同一目标刷新时保留展开态）
      if (targetChanged) {
        this.dismissedObjectName = ''
        this.objectDetailConnectorLength = 0
        this.objectDetailStore.selectedConstellationCultureDescriptionExpanded = false
        // 换了目标就回到极简形态：观测模式下的「展开」只对当前这颗天体有效。
        this.infoWindowStore.resetObserveExpand()
      }
      // 再次点选同一目标：清除“已关闭”记录并恢复展开态，让详情页重新弹出。
      if (reopenDismissedDetail) {
        this.dismissedObjectName = ''
        this.infoWindowStore.infoWinExpanded = true
        this.fullInspectorRequested = true
      }
      if (!preserveClosedDetail) {
        this.infoWindowStore.infoWinVisible = true
      }
      if (isNewSelection) {
        this.infoWindowStore.infoWinExpanded = true
        this.fullInspectorRequested = true
        this.objectMediaStore.objectInspectorMoreOpen = false
        this.objectDetailStore.bottomCardIndex = 2
        this.detailConnectorCtl().markObjectCardPlacementPending()
        // The lightweight tap/search response deliberately has no detailFields.
        // Never leave the previous target's structured data visible while loading.
        this.objectDetailStore.selectedDetailFields = []
        this.objectDetailStore.selectedDetailLoaded = false
        this.objectDetailStore.selectedDetailRequestPending = false
        this.objectDetailStore.selectedSatellitePasses = []
        this.objectDetailStore.selectedSatellitePassesLoaded = false
        this.objectDetailStore.selectedSatellitePassesRequested = false
        // Sensor tracking owns the camera. A gyro-mode search selects the
        // target and opens its card, but never starts a safe-area fly-to.
        if (!this.gyroStore.gyroscopeEnabled && !this.sessionToolStore.isObserverPlanetSelection(incomingName)) {
          if (placement === 'center') {
            this.navigateSelectedObjectTo(this.skyWidth / 2, this.skyHeight / 2, 'center')
          }
        }
      }
      this.gyroCtl().updateGyroTargetGuide(true)
      // 天体名称和资料均来自核心；不再用本地手写别名表覆盖官方名称。
      this.objectDetailStore.selectedInfo = ''
      // 换了新天体 → 按它的"性格"响一声（模仿 Sky Guide 的叮）
      if (isNewSelection) {
        AudioEngine.getInstance().chimeForSelection(result)
      }
      this.detailConnectorCtl().startDetailAutoRefresh()
      if (isNewSelection && !this.objectDetailStore.selectedDetailLoaded) {
        this.requestSelectedDetails(this.objectDetailStore.selectedName)
      }
    } else {
      this.objectDetailStore.selectedName = ''
      this.objectDetailStore.selectedEnglishName = ''
      this.objectDetailStore.selectedCatalogId = ''
      this.objectDetailStore.selectedDetailMediaPath = ''
      this.objectDetailStore.selectedDetailMediaKind = ''
      this.objectDetailStore.selectedDetailMediaLabel = ''
      this.objectDetailStore.selectedDetailModel = undefined
      this.objectDetailStore.selectedConstellationCultureId = ''
      this.objectDetailStore.selectedConstellationCultureName = ''
      this.objectDetailStore.selectedConstellationCultureDescription = ''
      this.objectDetailStore.selectedConstellationCultureDescriptionBlocks = []
      this.objectDetailStore.selectedConstellationCultureDescriptionSource = ''
      this.objectDetailStore.selectedObjectType = ''
      this.objectDetailStore.selectedTemperatureK = 0
      this.objectDetailStore.selectedType = ''
      this.objectDetailStore.selectedSatellitePasses = []
      this.objectDetailStore.selectedSatellitePassesLoaded = false
      this.objectDetailStore.selectedSatellitePassesRequested = false
      this.objectDetailStore.selectedStatus = result.query && result.query.length > 0 ? 'Try English name' : 'No match'
      this.objectDetailStore.selectedMagnitude = ''
      this.objectDetailStore.selectedApparentMagnitude = ''
      this.objectDetailStore.selectedAirmass = ''
      this.objectDetailStore.selectedExtinction = ''
      this.objectDetailStore.selectedDetailFields = []
      this.objectDetailStore.selectedDetailLoaded = false
      this.objectDetailStore.selectedDetailRequestPending = false
      this.objectDetailStore.selectedCoordEq = ''
      this.objectDetailStore.selectedCoordEqJ2000 = ''
      this.objectDetailStore.selectedCoordApparentAltAz = ''
      this.objectDetailStore.selectedCoordGeometricAltAz = ''
      this.objectDetailStore.selectedCoordEcliptic = ''
      this.objectDetailStore.selectedCoordEclipticJ2000 = ''
      this.objectDetailStore.selectedCoordGalactic = ''
      this.objectDetailStore.selectedCoordSupergalactic = ''
      this.objectDetailStore.selectedCoordParallactic = ''
      this.objectDetailStore.selectedCoordAlt = ''
      this.objectDetailStore.selectedHourAngle = ''
      this.objectDetailStore.selectedMeanSiderealTime = ''
      this.objectDetailStore.selectedApparentSiderealTime = ''
      this.objectDetailStore.selectedConstellation = ''
      this.objectDetailStore.selectedDistance = ''
      this.objectDetailStore.selectedDistanceCompact = ''
      this.objectDetailStore.selectedDistanceStatus = ''
      this.objectDetailStore.selectedTleOutdated = false
      this.gyroCtl().clearGuideTarget()
      this.gyroStore.gyroGuideVisible = false
      this.objectDetailStore.selectedSize = ''
      this.objectDetailStore.selectedRise = ''
      this.objectDetailStore.selectedSet = ''
      this.objectDetailStore.selectedTransit = ''
      this.objectDetailStore.selectedPhase = ''
      this.objectDetailStore.selectedElongation = ''
      this.objectMediaStore.objectInspectorMoreOpen = false
      this.objectMediaStore.objectInspectorMediaPath = ''
      this.objectMediaStore.objectInspectorMediaKind = 'none'
      this.objectMediaStore.objectInspectorMediaLabel = ''
      this.objectMediaStore.objectInspectorMediaLoading = false
      this.objectMediaStore.objectInspectorMediaDecoding = false
      this.objectInspectorMediaCtl().clearObjectInspectorDecodedImage()
      this.objectMediaStore.objectInspectorMediaLoadFailed = false
      this.objectMediaStore.objectInspectorMediaPreparationFailed = false
      this.objectInspectorMediaCtl().stopObjectInspectorMediaWarmup()
      this.objectInspectorMediaCtl().clearResolutionState()
      this.objectMediaStore.objectInspectorMediaFullscreen = false
      this.objectMediaStore.objectInspectorMediaPreviewPath = ''
      this.objectMediaStore.objectInspectorMediaPreviewLoading = false
      this.objectMediaStore.objectInspectorMediaPreviewFailed = false
      this.infoWindowStore.infoWinVisible = false
      this.objectDetailStore.selectedInfo = '当前位置没有可选天体，请放大或使用搜索'
      this.astroCalcCtl().clearRtsSelectionResults()
    }
  }

  /** 儒略日 -> 'YYYY-MM-DD HH:mm:ss' 本地显示文本（入参需已含 UTC 偏移）。 */

  private formatObservationTime(raw: string): string {
    if (!raw || raw.length === 0) {
      return '--'
    }
    // C++ has already applied the observation location's UTC offset before it
    // serializes timeText. Parsing the ISO value as a device-local Date applied
    // a second timezone conversion every 3 seconds, racing the lightweight JD
    // refresh and making the digits visibly jump. Preserve that local clock.
    let text = raw.trim()
    if (text.endsWith('Z')) {
      text = text.slice(0, -1)
    } else {
      const plus = text.lastIndexOf('+')
      const minus = text.lastIndexOf('-')
      const zoneStart = Math.max(plus, minus)
      if (zoneStart > 10) {
        text = text.slice(0, zoneStart)
      }
    }
    return text.replace('T', ' ')
  }

  private dismissObjectInspector(): void {
    if (this.objectDetailStore.selectedUiLayoutTimer !== 0) {
      clearTimeout(this.objectDetailStore.selectedUiLayoutTimer)
      this.objectDetailStore.selectedUiLayoutTimer = 0
    }
    this.infoWindowStore.infoWinVisible = false
    this.detailConnectorCtl().stopObjectDetailConnectorRefresh()
    this.infoWindowStore.infoWinExpanded = false
    this.objectMediaStore.objectInspectorMoreOpen = false
    this.dismissedObjectName = this.objectDetailStore.selectedName
    // 关卡片即结束本次「临时展开」，下次选星仍以极简形态出现。
    this.infoWindowStore.resetObserveExpand()
    this.lastInfoWinCloseMs = Date.now()
    this.skyTouchActive = false
    this.skyTouchFeedback = false
    this.skyDragging = false
    // Closing the inspector must not alter the camera mode. Tracking and
    // fixed-position anchoring are independent of the card's visibility.
  }

  private showFullObjectInspector(): void {
    this.infoWindowStore.infoWinVisible = true
    this.infoWindowStore.infoWinExpanded = true
    this.fullInspectorRequested = true
    this.objectMediaStore.objectInspectorMoreOpen = false
    this.objectDetailStore.bottomCardIndex = 2
    this.detailConnectorCtl().markObjectCardPlacementPending()
    this.dismissedObjectName = ''
    this.resetPanelIdle()
    this.refreshSelectedObject()
    this.detailConnectorCtl().startObjectDetailConnectorRefresh()
    this.scheduleSelectedObjectForUiChange(320)
  }

  private toggleObjectInspector(): void {
    if (!this.objectDetailStore.hasSelectedObject()) {
      this.flashHint(I18n.t('center_requires_selection'))
      return
    }
    if (this.infoWindowStore.infoWinVisible) {
      this.dismissObjectInspector()
    } else {
      this.showFullObjectInspector()
    }
  }

  private selectedDisplayValue(key: string): string {
    switch (key) {
      case 'selectedAirmass': return this.objectDetailStore.selectedAirmass
      case 'selectedApparentMagnitude': return this.objectDetailStore.selectedApparentMagnitude
      case 'selectedApparentSiderealTime': return this.objectDetailStore.selectedApparentSiderealTime
      case 'selectedConstellation': return zhNameOf(this.objectDetailStore.selectedConstellation)
      case 'selectedCoordAlt': return this.objectDetailStore.selectedCoordAlt
      case 'selectedCoordApparentAltAz': return this.objectDetailStore.selectedCoordApparentAltAz || this.objectDetailStore.selectedCoordAlt
      case 'selectedCoordEcliptic': return this.objectDetailStore.selectedCoordEcliptic
      case 'selectedCoordEclipticJ2000': return this.objectDetailStore.selectedCoordEclipticJ2000
      case 'selectedCoordEq': return this.objectDetailStore.selectedCoordEq.trim()
      case 'selectedCoordEqJ2000': return this.objectDetailStore.selectedCoordEqJ2000.trim()
      case 'selectedCoordGalactic': return this.objectDetailStore.selectedCoordGalactic
      case 'selectedCoordGeometricAltAz': return this.objectDetailStore.selectedCoordGeometricAltAz
      case 'selectedCoordParallactic': return this.objectDetailStore.selectedCoordParallactic
      case 'selectedCoordSupergalactic': return this.objectDetailStore.selectedCoordSupergalactic
      case 'selectedDistance': return this.objectDetailStore.selectedDistance
      case 'selectedElongation': return this.objectDetailStore.selectedElongation
      case 'selectedEnglishName': return this.objectDetailStore.selectedEnglishName
      case 'selectedExtinction': return this.objectDetailStore.selectedExtinction
      case 'selectedHourAngle': return this.objectDetailStore.selectedHourAngle
      case 'selectedMagnitude': return this.objectDetailStore.selectedMagnitude
      case 'selectedMeanSiderealTime': return this.objectDetailStore.selectedMeanSiderealTime
      case 'selectedPhase': return this.objectDetailStore.selectedPhase
      case 'selectedRise': return this.objectDetailStore.selectedRise
      case 'selectedSet': return this.objectDetailStore.selectedSet
      case 'selectedSize': return this.objectDetailStore.selectedSize
      case 'selectedTransit': return this.objectDetailStore.selectedTransit
      case 'extinctionUnits': return this.objectDetailStore.selectedExtinction.length > 0 ? this.objectDetailStore.selectedExtinction + ' 等' : ''
      case 'atmosphere': return this.objectDetailStore.expandedAtmosphereSummary()
      default: return ''
    }
  }

  private selectObjectDetailTab(index: number): void {
    if (index === this.objectDetailStore.bottomCardIndex) return
    const direction = index > this.objectDetailStore.bottomCardIndex ? 1 : -1
    const transitionId = ++this.objectDetailTabTransitionId
    this.getUIContext().animateTo({ duration: 100, curve: Curve.EaseIn, onFinish: () => {
      if (transitionId !== this.objectDetailTabTransitionId) return
      this.objectDetailStore.bottomCardIndex = index
      this.objectDetailContentTranslateX = 0 - direction * 10
      this.getUIContext().animateTo({ duration: 170, curve: Curve.EaseOut }, () => {
        this.objectDetailContentOpacity = 1
        this.objectDetailContentTranslateX = 0
      })
    } }, () => {
      this.objectDetailContentOpacity = 0
      this.objectDetailContentTranslateX = direction * 8
    })
  }

  private toggleSelectedObservingList(): void {
    const idx = this.obsListStore.observingList.indexOf(this.objectDetailStore.selectedName)
    if (idx >= 0) {
      this.obsListStore.observingList = this.obsListStore.observingList.filter((item: string) => item !== this.objectDetailStore.selectedName)
      this.flashHint(I18n.t('i0079'))
    } else {
      this.obsListStore.observingList = this.obsListStore.observingList.concat([this.objectDetailStore.selectedName])
      this.flashHint(I18n.t('i0080'))
    }
    this.obsListStore.persistObservingList()
  }

// ----- 详情连接线 -----

  private objectDetailConnectorObstacles(): SkyUiObstacle[] {
    const obstacles: SkyUiObstacle[] = []
    const layoutObstacles = this.selectedObjectUiObstacles()
    for (let index = 0; index < layoutObstacles.length; index++) {
      const obstacle = layoutObstacles[index]
      // The detail card is the start of the connector, not an obstacle to
      // route around. The panel and Dock remain real visual boundaries.
      if (obstacle.label !== 'object-card' && obstacle.label !== 'object-inspector' &&
        obstacle.label !== 'summary' && obstacle.label !== 'object-peek') {
        obstacles.push(obstacle)
      }
    }
    if (this.overlayStore.viewCoordinatesVisible) {
      obstacles.push({
        label: 'view-coordinates', left: this.viewCoordinateOverlayLeft() - 8,
        top: this.viewCoordinateOverlayTop() - 8,
        right: this.viewCoordinateOverlayLeft() + this.viewCoordinateOverlayWidth() + 8,
        bottom: this.viewCoordinateOverlayTop() + 100
      })
    }
    if (this.polarScopeStore.polarScopeVisible) {
      const headerTop = this.polarScopeTopInset()
      const left = (this.skyWidth - this.polarScopeControlWidth()) / 2
      const right = left + this.polarScopeControlWidth()
      obstacles.push({ label: 'polar-scope-header', left: left, top: headerTop,
        right: right, bottom: headerTop + 60 })
      obstacles.push({ label: 'polar-scope-footer', left: left,
        top: this.skyHeight - this.polarScopeFooterHeight() - 12, right: right,
        bottom: this.skyHeight - 12 })
    }
    if (this.gyroStore.gyroscopeEnabled && this.gyroStore.gyroCalibPanelOpen) {
      const calibrationLeft = this.isExpandedLayout ? this.EDGE_MARGIN + 64 : 16
      const calibrationTop = this.isExpandedLayout ? railTop(this.EDGE_MARGIN) + 120 : 80
      obstacles.push({ label: 'gyro-calibration', left: calibrationLeft - 8, top: calibrationTop - 8,
        right: calibrationLeft + (this.isExpandedLayout ? 320 : Math.min(360, this.skyWidth - 32)) + 8,
        bottom: calibrationTop + 270 })
    }
    if (!this.isExpandedLayout && this.isCompactTopQuickPoint(this.compactTopQuickX(), compactTopQuickY())) {
      const quickX = this.compactTopQuickX()
      const quickY = compactTopQuickY()
      obstacles.push({ label: 'compact-quick', left: quickX - 8, top: quickY - 8,
        right: quickX + 52, bottom: quickY + 106 })
    }
    return obstacles
  }

  private setObjectDetailConnector(enabled: boolean, syncNative: boolean = true): void {
    this.overlayStore.objectDetailConnectorVisible = enabled
    this.detailConnectorCtl().refreshObjectDetailConnector()
    this.saveAppSettings()
    if (syncNative) {
      this.callInteractive('setObjectDetailConnector', enabled ? '1' : '0', () => {})
    }
  }

// ----- 搜索 -----

  // Retained as a reference implementation for diagnosing sensor-fusion
  // differences. The active implementation above intentionally does not
  // anchor the sky view to an arbitrary startup pose.
  private searchObject(name: string, catalogModuleId: string = '', exactSelectionPayload: string = '', placement: string = ''): void {
    const query = name.trim()
    if (query.length === 0) {
      return
    }
    this.flashHint(I18n.t('i0070').replace('%s', query))
    // 保存搜索历史（去重，最多保留 20 条）
    const hist = this.searchStore.searchHistory.filter(h => h !== query)
    hist.unshift(query)
    this.searchStore.searchHistory = hist.slice(0, 20)
    this.searchStore.saveSearchHistoryToStorage()
    const gyroSelection = this.gyroStore.gyroscopeEnabled
    let payload = exactSelectionPayload.length > 0
      ? exactSelectionPayload
      : (catalogModuleId.length > 0 ? 'catalog|' + catalogModuleId + '|' + query : query)
    if (gyroSelection) { payload += '|selectOnly' }
    this.callInteractive('searchObject', payload, (result) => {
      if (result.found === true) {
        const selectedEnglishName = result.englishName ?? result.name ?? query
        const observerPlanetSelection = this.sessionToolStore.isObserverPlanetSelection(selectedEnglishName)
        const returnToGraph = this.astroCalcCtl().graphPickerActive()
        const returnToRts = this.astroCalcCtl().rtsPickerActive()
        const returnToEphemeris = this.astroCalcCtl().ephemerisPickerActive()
        const returnToAstroCalc = returnToGraph || returnToRts || returnToEphemeris
        // Close the search sheet before calculating the target's final safe
        // point. Otherwise the first navigation avoids the old 9/10 sheet,
        // then visibly performs a second correction for the top detail card.
        if (this.activePanel === 'search' && !returnToAstroCalc) {
          // Do this in-place instead of closePanel(): that generic helper
          // schedules a later recenter for the closing sheet, which can race
          // the newly opened object card and undo its safe target.
          this.timeCtl().stopPanelTimers()
          this.getUIContext().animateTo({ duration: 260, curve: curves.springMotion(0.45, 0.9) }, () => {
            this.panelVisible = false
          })
        }
        const selectionPlacement = placement.length > 0 ? placement : (returnToAstroCalc ? '' : 'center')
        this.applySelectedObject(result, false, selectionPlacement, true)
        if (returnToGraph) {
          this.astroCalcCtl().clearTargetPickerFlags()
          this.astroStore.astroTab = 4
          this.setPanel('astro')
        } else if (returnToRts) {
          this.astroCalcCtl().clearTargetPickerFlags()
          this.astroStore.astroTab = 2
          this.setPanel('astro')
        } else if (returnToEphemeris) {
          this.astroCalcCtl().clearTargetPickerFlags()
          this.astroStore.astroTab = 1
          this.setPanel('astro')
          this.astroCalcCtl().loadEphemeris()
        }
        // Search navigation and safe-area placement already own the camera.
        // Enabling tracking here would call moveToObject() a second time after
        // the detail card is laid out, pulling a safely placed target back to
        // the screen centre. Keep gyro/observer selections explicitly stopped;
        // normal searches remain anchored at the position reached by navigation.
        if (gyroSelection || observerPlanetSelection) {
          this.setTrackingState(false)
        } else {
          this.trackingText = 'Off'
        }
        const displayName = zhNameOf(this.objectDetailStore.selectedName.length > 0 ? this.objectDetailStore.selectedName : query)
        this.flashHint(I18n.t('i0071').replace('%s', displayName))
      } else {
        this.applySelectedObject(result)
        this.flashHint(I18n.t('i0072').replace('%s', query))
      }
    })
  }

// ----- 位置 / 观测点 -----

  private addWutTargetToObservingList(target: WutTarget): void {
    const name = (target.englishName ?? '').trim()
    if (name.length === 0 || this.obsListStore.observingList.includes(name)) { return }
    this.obsListStore.observingList = this.obsListStore.observingList.concat([name])
    this.obsListStore.persistObservingList()
    this.flashHint(I18n.t('i0080'))
  }

  private removeObservingTarget(name: string): void {
    this.obsListStore.observingList = this.obsListStore.observingList.filter((item: string) => item !== name)
    this.obsListStore.persistObservingList()
    this.flashHint(I18n.t('i0079'))
  }

  // 精确到角秒：地球自转约 15″/秒，300ms 刷新时用户能直接看到坐标连续变化。

  // 天体名称由核心的官方 .qm 资源提供。ArkUI 只负责排版，不再维护
  // 第二套恒星、行星或深空天体译名。

  private wutTargetTitle(target: WutTarget): string {
    return celestialTitle(target.name ?? '', target.englishName ?? '')
  }

  // 前者迁至 common/derive/labels.ets（纯函数），后者迁至 LocationPickerStore。


  // 虚拟指星笔（多设备联动）目标端测试入口：输入高度角/方位角，调 pointAtSky
  // 把星图中心转到该方向并选中那颗星。手表/分布式未来只是另一种触发方式。
  private pointAtSkyTest(): void {
    const alt = this.sessionToolStore.pointAlt.trim()
    const az = this.sessionToolStore.pointAz.trim()
    this.callNativeWhenReady('pointAtSky', alt + '|' + az, (r: StellariumBridgeResponse) => {
      if (!r.ok) {
        this.sessionToolStore.pointResult = '指星笔命令未响应'
        this.flashHint('指星笔命令未响应')
        return
      }
      this.sessionToolStore.pointResult = '已指向 高度角' + alt + '° 方位角' + az + '°（星图下一帧转过去并选中中心星）'
      this.flashHint('星图已转向 ' + alt + '°/' + az + '°')
      // 等一帧让 pointAtSky 完成中心选中，再读选中天体
      setTimeout(() => {
        this.callNativeWhenReady('getSelectedObjectInfo', '', (r2: StellariumBridgeResponse) => {
          if (!r2.ok) return
          if (r2.found) {
            const nm = (r2.name !== undefined && r2.name !== null) ? String(r2.name) : '未知'
            const tp = (r2.type !== undefined && r2.type !== null) ? String(r2.type) : ''
            this.sessionToolStore.pointResult = '指向命中：' + nm + '（' + tp + '）'
            this.flashHint('指向命中：' + nm)
          } else {
            this.sessionToolStore.pointResult = '指向方向：' + alt + '°/' + az + '° 该处暂无可选中天体'
            this.flashHint('该处暂无可选中天体')
          }
        })
      }, 400)
    })
  }

  // （实测：该路径为桥驱动 pointAtSky，归 CommandPort）。

  // Jump to specific RA/Dec coordinates (J2000 equatorial).
  private goToCoordinates(): void {
    const raStr: string = this.searchStore.coordInputRA.trim()
    const decStr: string = this.searchStore.coordInputDec.trim()
    if (raStr.length === 0 || decStr.length === 0) { return }
    // Parse RA: support formats like "5.5", "5h30m", "05:30:00"
    let raHours: number = 0
    if (raStr.includes('h')) {
      const parts: string[] = raStr.replace('m', '').split('h')
      raHours = parseFloat(parts[0]) + (parts.length > 1 ? parseFloat(parts[1]) / 60 : 0)
    } else if (raStr.includes(':')) {
      const parts: string[] = raStr.split(':')
      raHours = parseFloat(parts[0]) + (parts.length > 1 ? parseFloat(parts[1]) / 60 : 0) + (parts.length > 2 ? parseFloat(parts[2]) / 3600 : 0)
    } else {
      raHours = parseFloat(raStr)
    }
    // Parse Dec: support formats like "+45.5", "45:30:00", "-45d30m"
    let decDeg: number = 0
    const decClean: string = decStr.replace(/[d°′″'"]/g, '')
    if (decClean.includes(':')) {
      const parts: string[] = decClean.split(':')
      decDeg = parseFloat(parts[0]) + (parts.length > 1 ? parseFloat(parts[1]) / 60 : 0) + (parts.length > 2 ? parseFloat(parts[2]) / 3600 : 0)
    } else {
      decDeg = parseFloat(decClean)
    }
    if (isNaN(raHours) || isNaN(decDeg)) { return }
    this.callInteractive('gotoRADec', `${raHours}|${decDeg}`, (r: StellariumBridgeResponse) => {
      if (!r.ok) {
        this.flashHint(I18n.t('msg_navigation_failed'))
        return
      }
      this.flashHint(I18n.t('msg_goto_coord'))
    })
  }

  // 多设备接续 / 无缝流转（能力 A 的"会话搬运"目标端 + 脚手架）
  // 把当前星图会话(视线/FOV/时间/位置/选中星)导出成 JSON，可在另一台鸿蒙设备导入接续；
  // 完整跨设备一键流转需华为分布式软总线(Distributed Hardware Kit)。当前基础 SDK 已把
  // "导出/导入"做成统一命令桥，切到含分布式能力的 SDK 后这里即可改为设备发现+拉起目标 Ability。


  // 点击今晚天象卡片：跳到事件发生时刻，并锁定主角(lock)、框入卫星(月球)
  private gotoTonightEvent(jd: number, lock: string, title: string): void {
    const label = title.replace(/[^0-9A-Za-z\u4e00-\u9fa5]/g, '')
    this.flashHint(I18n.t('msg_navigating'))
    this.callNativeWhenReady('setJD', jd.toString(), () => {
      this.callNativeWhenReady('searchObject', lock, (r2: StellariumBridgeResponse) => {
        this.satelliteCtl().frameSatellite()
        const found = r2.found === true
        this.flashHint(found
          ? ('已跳至『' + label + '』时刻，锁定『' + lock + '』并框入月球(卫星)')
          : ('已跳至『' + label + '』时刻，但未找到『' + lock + '』'))
      })
    })
  }

// ----- 星空文化 -----

  private shouldFollowSkyCultureSimulationTime(): boolean {
    return this.applicationInForeground && this.activePanel === 'layers' && this.panelVisible &&
      this.viewTab === 5 && this.skyCultureSettingsStore.skyCultureTimeFiltering && !this.skyCultureSettingsStore.skyCultureRangeFiltering && this.skyCultureSettingsStore.skyCultureTimeFollowSimulation
  }

  // 宿主保留上面的前后台/面板路由谓词 shouldFollowSkyCultureSimulationTime 经 SkyCultureHostHooks 注入。
  // 锚点校正滚动的宿主侧（Scroller / 展开布局判定）经 correctSkyCultureRowScroll 注入。
  private correctSkyCultureRowScroll(id: string, delta: number): void {
    try {
      const scroller = this.isExpandedLayout ? this.widePanelScroller : this.compactPanelScroller
      const offset = scroller.currentOffset()
      const targetOffset = Math.max(0, offset.yOffset + delta)
      scroller.scrollTo({ xOffset: offset.xOffset, yOffset: targetOffset, animation: false })
      hilog.info(0x0000, 'StellariumArkUI',
        '[sky-culture-anchor] id=%{public}s delta=%{public}s offset=%{public}s',
        id, delta.toFixed(1), targetOffset.toFixed(1))
    } catch (error) {
      hilog.warn(0x0000, 'StellariumArkUI',
        '[sky-culture-anchor] correction failed id=%{public}s error=%{public}s', id, String(error))
    }
  }

  private loadSkyCultureDetails(): void {
    if (this.skyCultureViewStore.currentSkyCultureId.length === 0) return
    const requestId = ++this.skyCultureDetailsRequestId
    this.skyCultureViewStore.detailsLoading = true
    this.skyCultureViewStore.detailError = ''
    this.callInteractive('getSkyCultureDetails', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.skyCultureDetailsRequestId) return
      if (r.ok !== true) {
        this.skyCultureViewStore.detailError = '未能读取该文化的资料。'
        this.skyCultureViewStore.detailsLoading = false
        this.skyCultureCtl().clearSkyCultureAnchor()
        return
      }
      this.skyCultureViewStore.currentSkyCultureId = r.id !== undefined ? r.id : this.skyCultureViewStore.currentSkyCultureId
      this.skyCultureCtl().armSkyCultureAnchor(this.skyCultureViewStore.currentSkyCultureId, requestId)
      this.skyCultureViewStore.currentSkyCulture = r.name !== undefined ? this.skyCultureSettingsStore.skyCultureDisplayName(this.skyCultureViewStore.currentSkyCultureId, r.name) : this.skyCultureViewStore.currentSkyCulture
      this.skyCultureSettingsStore.skyCultureLabelPickerOpen = ''
      this.skyCultureSettingsStore.skyCultureRegions = r.region !== undefined ? r.region : []
      this.skyCultureSettingsStore.skyCultureClassification = r.classification !== undefined ? r.classification : ''
      this.skyCultureSettingsStore.skyCultureLicense = r.license !== undefined ? r.license : ''
      this.skyCultureSettingsStore.skyCultureBoundariesType = r.boundariesType !== undefined ? r.boundariesType : 'none'
      this.skyCultureSettingsStore.skyCultureUsesCommonNames = r.usesCommonNames === true
      this.skyCultureSettingsStore.skyCultureBeginTime = r.beginTime !== undefined ? r.beginTime : 0
      this.skyCultureSettingsStore.skyCultureEndTime = r.endTime !== undefined ? r.endTime : 0
      this.skyCultureSettingsStore.skyCultureConstellationCount = r.constellationCount !== undefined ? r.constellationCount : 0
      this.skyCultureSettingsStore.skyCultureAsterismCount = r.asterismCount !== undefined ? r.asterismCount : 0
      this.skyCultureSettingsStore.skyCultureNativeNameCount = r.nativeNameCount !== undefined ? r.nativeNameCount : 0
      this.skyCultureSettingsStore.skyCultureArtCount = r.artCount !== undefined ? r.artCount : 0
      this.skyCultureSettingsStore.skyCultureHasAsterisms = r.hasAsterisms === true
      this.skyCultureSettingsStore.skyCultureHasZodiac = r.hasZodiac === true
      this.skyCultureSettingsStore.skyCultureHasLunarSystem = r.hasLunarSystem === true
      this.skyCultureSettingsStore.skyCultureShortLabels = r.abbreviatedNames === true
      this.skyCultureSettingsStore.skyCultureOverrideCommonNames = r.overrideCommonNames === true
      this.skyCultureSettingsStore.skyCultureDefaultId = r.defaultId !== undefined ? r.defaultId : ''
      this.skyCultureSettingsStore.skyCultureScreenStyleMask = this.skyCultureSettingsStore.skyCultureStyleMaskFromBridge(r.screenLabelStyle)
      this.skyCultureSettingsStore.skyCultureInfoStyleMask = this.skyCultureSettingsStore.skyCultureStyleMaskFromBridge(r.infoLabelStyle)
      this.skyCultureSettingsStore.skyCultureScreenLabelMode = this.skyCultureSettingsStore.skyCultureScreenLabelModeFromBridge(r.screenLabelStyle)
      this.skyCultureSettingsStore.skyCultureInfoLabelMode = this.skyCultureSettingsStore.skyCultureScreenLabelModeFromBridge(r.infoLabelStyle)
      this.skyCultureSettingsStore.skyCultureZodiacLabelMode = this.skyCultureSettingsStore.skyCultureScreenLabelModeFromBridge(r.zodiacLabelStyle)
      this.skyCultureSettingsStore.skyCultureLunarLabelMode = this.skyCultureSettingsStore.skyCultureScreenLabelModeFromBridge(r.lunarSystemLabelStyle)
      this.skyCultureViewStore.narration = cleanSkyCultureNarration(r.narration !== undefined ? r.narration : '')
      this.skyCultureViewStore.description = cleanSkyCultureDescription(r.description !== undefined ? r.description : '')
      this.skyCultureViewStore.descriptionBlocks = r.descriptionBlocks !== undefined ? r.descriptionBlocks : []
      this.skyCultureCtl().clearSkyCultureArtThumbnails()
      this.skyCultureViewStore.artItems = r.constellationArt !== undefined ? r.constellationArt : []
      this.skyCultureArtStates = {}
      this.skyCultureCtl().closeSkyCultureArtPreview()
      this.skyCultureCtl().prepareSkyCultureArtResources(this.skyCultureViewStore.artItems, requestId)
      this.skyCultureSettingsStore.skyCultureHasTerritoryArchive = r.hasTerritoryArchive === true
      this.skyCultureSettingsStore.skyCultureTerritorySegmentCount = r.territorySegmentCount !== undefined ? r.territorySegmentCount : 0
      this.skyCultureSettingsStore.skyCultureTerritoryArchive = r.territoryArchive !== undefined ? r.territoryArchive : []
      if (r.territorySimulationYear !== undefined) {
        this.skyCultureSettingsStore.skyCultureSimulationYear = r.territorySimulationYear
        if (this.skyCultureSettingsStore.skyCultureTimeFollowSimulation) this.skyCultureSettingsStore.setSkyCultureTimeYear(this.skyCultureSettingsStore.skyCultureSimulationYear)
        if (!this.skyCultureSettingsStore.skyCultureTerritoryMapExpanded) this.skyCultureSettingsStore.setSkyCultureTerritoryMapYear(r.territorySimulationYear)
      }
      this.skyCultureViewStore.detailsReady = true
      this.skyCultureViewStore.pendingId = ''
      this.skyCultureViewStore.detailsLoading = false
      this.skyCultureSettingsStore.loadSkyCultureConstellationSelectionFlags()
      this.skyCultureSettingsStore.loadSkyCultureVisualSettings()
    }, () => {
      if (requestId !== this.skyCultureDetailsRequestId) return
      this.skyCultureViewStore.pendingId = ''
      this.skyCultureViewStore.detailsLoading = false
      this.skyCultureViewStore.detailError = '未能读取该文化的资料。'
      this.skyCultureCtl().clearSkyCultureAnchor()
    })
  }

  // 登记宿主控制器：可用配色目标（读 layerStore 图层开关 + hasZodiac/hasLunarSystem）。
  private skyCultureColorOptions(): ConfigurationOption[] {
    const options: ConfigurationOption[] = []
    if (this.layerStore.constellationLines) options.push({ id: 'constellationLines', label: '星座连线' })
    if (this.layerStore.constellationLabels) options.push({ id: 'constellationLabels', label: '星座标签' })
    if (this.layerStore.constellationBoundaries) options.push({ id: 'constellationBoundaries', label: '星座边界' })
    if (this.layerStore.constellationHulls) options.push({ id: 'constellationHulls', label: '星座区域边界' })
    if (this.layerStore.asterismLines) options.push({ id: 'asterismLines', label: '星群连线' })
    if (this.layerStore.asterismLabels) options.push({ id: 'asterismLabels', label: '星群标签' })
    if (this.layerStore.rayHelpers) options.push({ id: 'rayHelpers', label: '辅助射线' })
    if (this.layerStore.zodiac && this.skyCultureSettingsStore.skyCultureHasZodiac) options.push({ id: 'zodiac', label: '文化黄道' })
    if (this.layerStore.lunarSystem && this.skyCultureSettingsStore.skyCultureHasLunarSystem) options.push({ id: 'lunarSystem', label: '月宿系统' })
    return options
  }

  private skyCultureActiveColorTarget(): string {
    const options = this.skyCultureColorOptions()
    for (const option of options) {
      if (option.id === this.skyCultureSettingsStore.skyCultureColorTarget) return option.id
    }
    return options.length > 0 ? options[0].id : 'constellationLines'
  }

  private stellariumFilesDir(): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    return context.getApplicationContext().filesDir
  }

  private drawSkyCultureTerritoryMap(): void {
    const width = this.skyCultureMapRenderWidth
    const height = this.skyCultureMapRenderHeight
    if (width <= 0 || height <= 0) return
    this.skyCultureMapContext.clearRect(0, 0, width, height)
    this.skyCultureMapContext.lineWidth = 1.2
    this.skyCultureMapContext.strokeStyle = AstroColors.cultureMapStroke
    this.skyCultureMapContext.fillStyle = AstroColors.cultureMapFill
    for (let polygonIndex = 0; polygonIndex < this.skyCultureSettingsStore.skyCultureTerritoryMapPolygons.length; polygonIndex++) {
      const points = this.skyCultureSettingsStore.skyCultureTerritoryMapPolygons[polygonIndex].points
      if (points.length < 3) continue
      let started = false
      let crossesDateLine = false
      let previousLongitude = 0
      this.skyCultureMapContext.beginPath()
      for (let pointIndex = 0; pointIndex < points.length; pointIndex++) {
        const point = points[pointIndex]
        if (point.length < 2) continue
        const longitude = point[0]
        const latitude = point[1]
        const x = (longitude + 180) / 360 * width
        const y = (90 - latitude) / 180 * height
        if (!started || Math.abs(longitude - previousLongitude) > 180) {
          if (started) crossesDateLine = true
          this.skyCultureMapContext.moveTo(x, y)
          started = true
        } else {
          this.skyCultureMapContext.lineTo(x, y)
        }
        previousLongitude = longitude
      }
      if (!started) continue
      this.skyCultureMapContext.closePath()
      if (!crossesDateLine) this.skyCultureMapContext.fill()
      this.skyCultureMapContext.stroke()
    }
  }

// ----- 天文计算 -----

  private resetAngleMeasure(): void {
    this.callInteractive('resetAngleMeasure', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.tools.angleMeasureHasStart = false
        this.tools.angleMeasureHasEnd = false
        this.tools.angleMeasureText = ''
      }
    })
  }

  private measureAngleAt(x: number, y: number): void {
    const payload = Math.round(x).toString() + '|' + Math.round(y).toString() + '|' +
      Math.round(this.skyWidth).toString() + '|' + Math.round(this.skyHeight).toString()
    this.callInteractive('angleMeasurePoint', payload, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.flashHint('测量点无效，请重新点击')
        return
      }
      this.tools.angleMeasureHasStart = r.hasStart === true
      this.tools.angleMeasureHasEnd = r.hasEnd === true
      this.tools.angleMeasureText = r.angleText ?? ''
      this.flashHint(this.tools.angleMeasureHasEnd ? '角距离：' + this.tools.angleMeasureText : '已记录第一个位置，请点击第二个位置')
    })
  }

  private jdToDateStr(jd: string): string {
    if (jd.indexOf('T') >= 0) {
      const match = jd.match(/^(?:\d{4}-)?(\d{2})-(\d{2})T(\d{2}):(\d{2})/)
      if (match !== null) return parseInt(match[1]).toString() + '/' + parseInt(match[2]).toString() + ' ' + match[3] + ':' + match[4]
    }
    const numJd = parseFloat(jd);
    if (numJd <= 0) return '--'
    const date = new Date((numJd - 2440587.5) * 86400000)
    return (date.getMonth() + 1).toString() + '/' + date.getDate().toString()
      + ' ' + date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0')
  }

  // 大气参数回包写入 AtmosphereStore（已于 并回 store.applyAtmosphereResponse）；
  // TimeStore.loadTimeExtras 与 AstroCalcController 经 hooks 路由到 store。

  // ---- 天文计算辅助：高度曲线 ----

  private planetTimeSeriesValueLabel(value: number | undefined, metric: string): string {
    return (value ?? 0).toFixed(metric === 'angularSize' ? 0 : 1) + planetMetricUnit(metric)
  }

  private celestialPositionSubtitle(position: CelestialPosition): string {
    if (position.catalogId.length > 0 && position.catalogId !== celestialTitle(position.name, position.englishName)) return position.catalogId
    return position.type
  }

// ----- 卫星 -----

  private requestSatellitePasses(expectedName: string): void {
    if (this.objectDetailStore.selectedName !== expectedName || this.objectDetailStore.selectedSatellitePassesLoaded) return
    const payload = JSON.stringify({ hours: 12, limit: 3, minElevation: 10, visibleOnly: false })
    this.callInteractive('getSatellitePasses', payload, (r) => {
      if (this.objectDetailStore.selectedName !== expectedName) return
      if (r.ok === true) {
        this.objectDetailStore.selectedSatellitePasses = r.satellitePassList ?? []
      } else {
        this.objectDetailStore.selectedSatellitePasses = []
      }
      this.objectDetailStore.selectedSatellitePassesLoaded = true
    }, () => {
      if (this.objectDetailStore.selectedName === expectedName) {
        this.objectDetailStore.selectedSatellitePasses = []
        this.objectDetailStore.selectedSatellitePassesLoaded = true
      }
    })
  }

// ----- 时间 -----

  // 4 个 @State 与几何方法经 ViewCoordinateHostHooks 注入）。宿主保留 5 个 A-保留几何方法
  //（viewCoordinateOverlayWidth / Left / Top + clampedViewCoordinateOffsetX / Y，G 类逐帧读数，
  //）与命中区。

  private stopDockClockTimer(): void {
    if (this.dockClockTimer !== 0) {
      clearInterval(this.dockClockTimer)
      this.dockClockTimer = 0
    }
  }

  /** Dock 常驻时钟：1s 轮询 getSimulationTime，只写 dockClockText 一个 @State。 */
  private syncDockClockTimer(): void {
    this.stopDockClockTimer()
    if (this.timeWheelController !== undefined) { this.timeWheelController.stop() }
    if (!this.applicationInForeground) { return }
    this.refreshDockClock()
    this.dockClockTimer = setInterval(() => {
      this.refreshDockClock()
    }, 1000)
  }

  private refreshDockClock(): void {
    // 引擎未就绪时 command() 会同步等待 Qt 线程（启动期还在加载插件），
    // 反复轮询会把 UI 线程占满并触发 appfreeze。就绪由 StartupBridge 事件置位。
    if (!this.engineReady) { return }
    this.callInteractive('getSimulationTime', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true || r.jd === undefined) { return }
      const jd: number = r.jd as number
      // 固定走本地 jd 格式化：jdToLocalTimeText 返回定长 'YYYY-MM-DD HH:mm:ss'，截取后 5 位为 HH:mm
      const text: string = jdToLocalTimeText(jd + this.utcOffsetHours / 24.0).substring(11, 16)
      if (text !== this.dockClockText) {
        this.dockClockText = text
      }
    })
    // The FOV chip above the dock reads the same @State the zoom paths write, but
    // a programmatic view change (restoring the saved view, safe-area recentring)
    // never goes through changeFovBySlider/zoomStep, so the chip could sit on a
    // stale value. Refresh it on the same 1 s tick as the clock and only write on
    // change, so an unchanged FOV costs no re-render.
    this.callInteractive('getFieldOfView', '', (f: StellariumBridgeResponse) => {
      if (f.ok !== true || f.fov === undefined) { return }
      const fovText: string = (f.fov as number).toFixed(1) + '°'
      if (fovText !== this.currentFovText) { this.currentFovText = fovText }
    })
  }

// ----- 望远镜 / 目镜 -----

  private shouldRefreshTelescopePosition(): boolean {
    return this.telescopeStore.lx200LivePositionEnabled && this.applicationInForeground && this.panelVisible &&
      this.activePanel === 'telescope' && !this.telescopeStore.lx200EditingNew
  }

  // Catalogs may contain many thousands of entries. Request small pages so the
  // first page is usable immediately and append more only when the user scrolls.

  private stopTracking(): void {
    this.setTrackingState(false)
  }

  // ---- 选中天体的独立浮动详情窗口 ----
  // 默认收起（仅一行概要），点头部展开为可滚动的富详情卡（约半屏）。
  // 它独立于右侧菜单面板（activePanel），选中天体时不再强制切换菜单，
  // 因此不会打扰用户正在进行的操作。
  private setTrackingState(enabled: boolean): void {
    if (enabled && !this.objectDetailStore.hasSelectedObject()) {
      this.flashHint(I18n.t('tracking_requires_selection'))
      return
    }
    if (this.gyroStore.gyroscopeEnabled) {
      this.gyroCtl().updateGyroTargetGuide(true)
      this.flashHint(I18n.t('tracking_unavailable_gyro'))
      return
    }
    const requestSerial = ++this.trackingRequestSerial
    this.trackingRequestPending = true
    this.trackingText = enabled ? 'On' : 'Off'
    if (enabled) {
      // Native tracking owns the camera centre, so it supersedes the optional
      // fixed-screen-position mode. The native response is authoritative and
      // refreshState() will confirm the final toggle state.
      this.viewSettingsStore.viewLock = false
    }
    this.callInteractive('setTracking', enabled ? '1' : '0', (result: StellariumBridgeResponse) => {
      if (requestSerial !== this.trackingRequestSerial) { return }
      this.trackingRequestPending = false
      if (result.tracking !== undefined) {
        this.trackingText = result.tracking === true ? 'On' : 'Off'
      }
      if (result.viewLock !== undefined) {
        this.viewSettingsStore.viewLock = result.viewLock === true
      }
      this.trackingStateIgnoreUntilMs = Date.now() + 450
      this.flashHint(this.trackingText === 'On' ? I18n.t('tracking_enabled') : I18n.t('tracking_disabled'))
    }, () => {
      if (requestSerial !== this.trackingRequestSerial) { return }
      this.trackingRequestPending = false
      this.trackingText = enabled ? 'Off' : 'On'
      this.flashHint('跟踪状态更新失败，请重试')
    })
  }

// ----- 图层 / 显示 -----

  private changeFovBySlider(val: number): void {
    this.callInteractive('setFOV', Math.round(val).toString(), (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'changeFovBySlider %{public}d ok=%{public}s', Math.round(val), r.ok === true ? '1' : '0')
    })
  }

  private wheel(): TimeWheelController {
    if (this.timeWheelController === undefined) {
      this.timeWheelController = new TimeWheelController(
        this.timeWheelStore,
        (jd: number) => { this.callNativeFire('setTimeToJD', jd.toFixed(8)) },
        () => { this.timeCtl().stopTimeWheelSpeed() },
        () => { return this.utcOffsetHours }
      )
    }
    return this.timeWheelController
  }

  private zoomStep(factor: number): void {
    hilog.info(0x0000, 'StellariumArkUI', 'zoomStep factor=%{public}s', factor.toString())
    // Discrete zoom is a direct view command. Do not route it through the
    // result-polling cache, which can make a tap appear to do nothing.
    this.callNativeFire('zoomStep', factor.toString())
    this.skyTextureStatusCtl().start()
    setTimeout(() => {
      this.refreshState()
      this.callInteractive('getFieldOfView', '', (r: StellariumBridgeResponse) => {
        if (r.ok === true && r.fov !== undefined) {
          const fovDeg = r.fov as number
          // 只更新常驻的 FOV 读数（dock 上方的胶囊），不再弹 "视场 xx°" 提示：
          // 胶囊一直可见，提示属于重复反馈，且会盖住星图中央。
          this.currentFovText = fovDeg.toFixed(1) + '°'
          this.fovSliderValue = fovDeg
        }
      })
    }, 450)
  }

// ----- 导入导出 / 配置 -----

  // 的「设置面板选项 / 配置行为」控制器已于 解散：18 法按字段归属并回

  // 设置选项分组判定（原 SettingsController.settingsChoiceSelected，跨 4 个 store 的谓词，由宿主持有；零副作用）。
  private settingsChoiceSelected(group: string, value: string): boolean {
    if (group === 'information') return this.infoWindowStore.informationMode === value
    if (group === 'date') return this.timeSettingsStore.configDateFormat === value
    if (group === 'time') return this.timeSettingsStore.configTimeFormat === value
    if (group === 'startup') return this.timeSettingsStore.startupTimeMode === value
    return false
  }

  // 设置选项分派（原 SettingsController.selectSettingsChoice）：跨域分派由宿主持有，调各 store 新方法 / timeCtl()。
  private selectSettingsChoice(group: string, value: string): void {
    if (this.settingsChoiceSelected(group, value)) return
    if (group === 'information') this.infoWindowStore.setInformationMode(value)
    else if (group === 'date') this.timeCtl().saveTimePreference('setDateFormat', value, 'time_settings_applied')
    else if (group === 'time') this.timeCtl().setConfigurationTimeFormat(value)
    else if (group === 'startup') this.timeCtl().setStartupTimeSetting('startupMode', value)
  }

  //（picker/fileIo 经 MediaPort.importLandscapeDocument；名称清洗收在 HostMediaPort 适配器）。

  private async saveFileAs(path: string, fileName: string, suffixLabel: string): Promise<void> {
    if (path.length === 0 || !this.hostMediaPort.fileExists(path)) {
      this.flashHint('没有可导出的文件')
      return
    }
    this.hostMediaPort.saveFileAs(path, fileName, suffixLabel, (result: MediaSaveResult) => {
      if (result === MediaSaveResult.Saved) {
        this.flashHint('文件已导出')
      } else if (result === MediaSaveResult.Failed) {
        this.flashHint('导出失败')
      }
    })
  }

  private setLanguage(lang: string): void {
    // Map to I18n code (handle codes like pt_BR, zh_HK that C++ may not support)
    const i18nCode = I18n.fromStellariumCode(lang)
    // 同步 I18n 模块（触发 AppStorage 变更 → UI 重渲染）
    I18n.setLanguage(i18nCode)
    // The panel contains many static text nodes. Updating this local storage
    // link and the panel identity makes the open panel rebuild immediately,
    // rather than waiting for it to be closed and opened again.
    this.i18nLang = i18nCode
    this.languageStore.selectedLanguage = lang
    const languageSerial = ++this.languageStore.languageRefreshSerial
    this.languageStore.languageRevision++
    this.panelContentKey++
    // 持久化语言选择
    try {
      const settings = AppStorage.get<string>('stellariumSettings')
      const s: Record<string, Object> = settings ? JSON.parse(settings) as Record<string, Object> : {} as Record<string, Object>
      s.selectedLanguage = lang
      AppStorage.setOrCreate('stellariumSettings', JSON.stringify(s))
    } catch (e) { }
    // 立即提示，不等 C++ 确认（避免阻塞触摸和星图交互）
    this.flashHint(I18n.t('msg_lang_switched_done') + ': ' + (LANGUAGE_DISPLAY[lang] ?? LANGUAGE_DISPLAY[i18nCode] ?? lang))
    // 延迟同步 C++ 侧语言，避免同步 N-API 调用阻塞 UI 线程导致星图无响应。
    // 这里不能 refreshState：该全量状态刷新会与选中对象的安全居中动画竞争，
    // 表现为星图先上移又下移。
    if (this.languageSwitchTimer >= 0) {
      clearTimeout(this.languageSwitchTimer)
      this.languageSwitchTimer = -1
    }
    this.languageSwitchTimer = setTimeout(() => {
      this.languageSwitchTimer = -1
      this.callNativeWhenReady('setLanguage', lang, () => {
        if (this.languageStore.languageRefreshSerial !== languageSerial) return
        const selectedCategoryModuleId = this.searchStore.categoryModuleId
        this.catalogStore.objectCatalogCategories = []
        this.searchStore.categoryObjects = []
        this.searchStore.searchSuggestions = []
        this.searchStore.constellationNavigationItems = []
        this.catalogStore.loadObjectCatalogCategories(languageSerial)
        this.searchStore.loadConstellationNavigation(languageSerial)
        this.searchStore.loadCategoryObjects(this.searchStore.searchCategory, selectedCategoryModuleId)
        const query = this.searchStore.searchText.trim()
        if (query.length > 0) this.searchCtl().fetchSuggestions(query, languageSerial)
      }, 0, 300, 3)
    }, 50)
  }

// ----- 杂项 -----

  // 所有设备共享同一动作模型。布局只决定面板如何呈现，不改变入口和语义。

  private moreActionStartsSection(item: ShellAction, index: number): boolean {
    if (index === 0) return true
    const actions = moreActions()
    return actions[index - 1].section !== item.section
  }

  // 状态写 SatelliteStore；分组 180ms 过渡动画与 CLI 发布点经 SatelliteHostHooks）。
  // publishSatellitePanelState（`publish*` 保留项）与 requestSatellitePasses（选中管线 ）由宿主持有。
  private catalogHealthText(title: string, health: CatalogHealthEntry): string {
    if (!this.catalogHealthLoaded) return title + '状态检查中'
    if (!this.catalogManifestPresent || health.status === 'unknown') return title + '状态不可用'
    const checkedAt = health.checkedAt ? health.checkedAt.replace('T', ' ').replace('Z', ' UTC') : '未记录'
    if (health.status === 'stale') return title + '已过期，请在下次发布前更新或复核（上次：' + checkedAt + '）'
    if (health.status === 'attention') return title + '部分更新，建议下次发布前完整复核（上次：' + checkedAt + '）'
    return title + '已核验（' + checkedAt + '）'
  }

  // 宿主直属 UI 的取色入口：nightMode 变化时重建一次槽位缓存。
  private hostSlots(): ThemeSlots {
    const night = this.nightModeStore.nightMode
    if (this.hostSlotsNight !== night) {
      this.hostSlotsNight = night
      this.hostSlotsCache = slotsForNightMode(night)
    }
    return this.hostSlotsCache
  }

  private catalogHealthColor(health: CatalogHealthEntry): ResourceColor {
    const c = this.hostSlots()
    if (!this.catalogHealthLoaded || !this.catalogManifestPresent || health.status === 'unknown') return c.sub
    if (health.status === 'stale' || health.status === 'attention') return c.warning
    return c.tertiary
  }

  // 确保插件已加载，未加载时先 loadPlugin 再回调


  // ===== 帮助面板：关于 / 日志 / 配置导入导出 =====
  // exportConfig / importConfig 已于 并回 state/ToolsStore.ets（桥经 CommandPort，剪贴板经 hooks）。

  // ===== 朗读 / 语音播报 =====
  // 说明：当前构建基于 OpenHarmony 基础 SDK（API 24），其 kit 列表不含
  // @kit.CoreSpeechKit（语音合成仅存在于华为 HarmonyOS 的 HMS SDK），因此
  // 无法在此环境做真正的 TTS 音频播报。这里保留 C++ 侧生成的"可读中文描述"
  // （getObjectSpokenText 命令），点按按钮即在面板中显示该文本，验证命令通道，
  // 待切换到含 CoreSpeechKit 的 SDK 后即可接真实语音合成。
  private refreshState(): void {
    this.publishBackConsumable()
    if (this.stateRefreshRequestPending) {
      this.stateRefreshQueued = true
      return
    }
    if (this.stateRefreshTimer >= 0) return
    this.stateRefreshTimer = setTimeout(() => {
      this.stateRefreshTimer = -1
      this.refreshStateNow()
    }, 48) as number
  }

  private refreshStateNow(): void {
    if (this.stateRefreshRequestPending) {
      this.stateRefreshQueued = true
      return
    }
    this.stateRefreshRequestPending = true
    const nightEpoch = this.nightModeStore.nightModeEpoch()
    const stateNonce = (++this.stateRefreshSerial).toString()
    this.callInteractive('getState', stateNonce, (result) => {
    if (result.selectedInfoMode !== undefined) {
      this.applySelectedInfoMode(result.selectedInfoMode)
    }
    this.layerStore.stars = result.actionShow_Stars === true
    this.layerStore.planets = result.actionShow_Planets === true
    this.layerStore.planetOrbits = result.actionShow_Planets_Orbits === true
    this.layerStore.planetHints = result.actionShow_Planets_Hints === true
    if (result.actionShow_Planets_Trails !== undefined) this.layerStore.planetTrails = result.actionShow_Planets_Trails === true
    if (result.actionShow_Planets_EnlargeMoon !== undefined) this.layerStore.enlargeMoon = result.actionShow_Planets_EnlargeMoon === true
    this.layerStore.nebulae = result.actionShow_Nebulas === true
    this.layerStore.milkyWay = result.actionShow_MilkyWay === true
    this.layerStore.ground = result.actionShow_Ground === true
    this.layerStore.mistHorizon = result.actionShow_MistHorizon === true
    this.layerStore.constellationLines = result.actionShow_Constellation_Lines === true
    this.layerStore.constellationLabels = result.actionShow_Constellation_Labels === true
    this.layerStore.constellationBoundaries = result.actionShow_Constellation_Boundaries === true
    this.layerStore.constellationArt = result.actionShow_Constellation_Art === true
    this.layerStore.constellationHulls = result.actionShow_Constellation_Hulls === true
    this.layerStore.atmosphere = result.actionShow_Atmosphere === true
    this.layerStore.cardinalPoints = result.actionShow_Cardinal_Points === true
    this.layerStore.intercardinalPts = result.actionShow_Intercardinal_Points === true
    this.layerStore.secondaryIntercardinalPts = result.actionShow_Secondary_Intercardinal_Points === true
    this.layerStore.tertiaryIntercardinalPts = result.actionShow_Tertiary_Intercardinal_Points === true
    this.layerStore.compassMarks = result.actionShow_Compass_Marks === true
    this.layerStore.gridlinesMaster = result.actionShow_Gridlines === true
    this.layerStore.fovMarker = result.actionShow_FOV_Center_Marker === true
    this.layerStore.fovCircularMarker = result.actionShow_FOV_Circular_Marker === true
    this.layerStore.fovRectangularMarker = result.actionShow_FOV_Rectangular_Marker === true
    if (result.fovCircularMarkerSize !== undefined) this.layerViewStore.fovCircularMarkerSize = result.fovCircularMarkerSize
    if (result.fovRectangularMarkerWidth !== undefined) this.layerViewStore.fovRectangularMarkerWidth = result.fovRectangularMarkerWidth
    if (result.fovRectangularMarkerHeight !== undefined) this.layerViewStore.fovRectangularMarkerHeight = result.fovRectangularMarkerHeight
    if (result.fovRectangularMarkerRotation !== undefined) this.layerViewStore.fovRectangularMarkerRotation = result.fovRectangularMarkerRotation
    this.layerStore.azimuthGrid = result.actionShow_Azimuthal_Grid === true
    this.layerStore.equatorialGrid = result.actionShow_Equatorial_Grid === true
    this.layerStore.equatorialJ2000Grid = result.actionShow_Equatorial_J2000_Grid === true
    this.layerStore.eclipticGrid = result.actionShow_Ecliptic_Grid === true
    this.layerStore.meridianLine = result.actionShow_Meridian_Line === true
    this.layerStore.horizonLine = result.actionShow_Horizon_Line === true
    this.planetLabels = result.actionShow_Planets_Labels === true
    this.layerStore.starLabels = result.actionShow_Stars_Labels === true
    this.layerStore.dsoLabels = result.dsoLabels === true
    this.layerStore.dsoTextures = result.actionShow_DSO_Textures === true
    this.layerStore.enlargePlanets = result.actionShow_Planets_EnlargePlanets === true
    this.layerStore.enlargeSun = result.actionShow_Planets_EnlargeSun === true
    this.layerStore.minorBodyMarkers = result.actionShow_Planets_ShowMinorBodyMarkers === true
    this.layerStore.planetNomenclature = result.actionShow_Planets_Nomenclature === true
    this.layerStore.fogEffect = result.actionShow_Fog === true
    if (result.actionShow_Ecliptic_Line !== undefined) this.layerStore.eclipticLine = result.actionShow_Ecliptic_Line === true
    if (result.actionShow_Equator_Line !== undefined) this.layerStore.equatorLine = result.actionShow_Equator_Line === true
    if (result.actionShow_Galactic_Grid !== undefined) this.layerStore.galacticGrid = result.actionShow_Galactic_Grid === true
    if (result.actionShow_Galactic_Equator_Line !== undefined) this.layerStore.galacticEquator = result.actionShow_Galactic_Equator_Line === true
    if (result.actionShow_Supergalactic_Equator_Line !== undefined) this.layerStore.supergalacticEq = result.actionShow_Supergalactic_Equator_Line === true
    if (result.actionShow_Equator_J2000_Line !== undefined) this.layerStore.equJ2000Line = result.actionShow_Equator_J2000_Line === true
    if (result.actionShow_Ecliptic_J2000_Line !== undefined) this.layerStore.eclJ2000Line = result.actionShow_Ecliptic_J2000_Line === true
    if (result.actionShow_Celestial_Poles !== undefined) this.layerStore.celestialPoles = result.actionShow_Celestial_Poles === true
    if (result.actionShow_Ecliptic_Poles !== undefined) this.layerStore.eclipticPoles = result.actionShow_Ecliptic_Poles === true
    if (result.actionShow_Galactic_Poles !== undefined) this.layerStore.galacticPoles = result.actionShow_Galactic_Poles === true
    if (result.actionShow_Equinox_Points !== undefined) this.layerStore.equinoxPoints = result.actionShow_Equinox_Points === true
    if (result.actionShow_Solstice_Points !== undefined) this.layerStore.solsticePoints = result.actionShow_Solstice_Points === true
    if (result.actionShow_Antisolar_Point !== undefined) this.layerStore.antisolarPoint = result.actionShow_Antisolar_Point === true
    if (result.actionShow_Umbra_Circle !== undefined) this.layerStore.umbraCircle = result.actionShow_Umbra_Circle === true
    if (result.actionShow_Penumbra_Circle !== undefined) this.layerStore.penumbraCircle = result.actionShow_Penumbra_Circle === true
    if (result.actionShow_Compass_Marks !== undefined) this.layerStore.compassMarks = result.actionShow_Compass_Marks === true
    if (result.actionShow_FOV_Center_Marker !== undefined) this.layerStore.fovMarker = result.actionShow_FOV_Center_Marker === true
    if (result.actionShow_FOV_Circular_Marker !== undefined) this.layerStore.fovCircularMarker = result.actionShow_FOV_Circular_Marker === true
    if (result.actionShow_FOV_Rectangular_Marker !== undefined) this.layerStore.fovRectangularMarker = result.actionShow_FOV_Rectangular_Marker === true
    if (result.actionShow_Intercardinal_Points !== undefined) this.layerStore.intercardinalPts = result.actionShow_Intercardinal_Points === true
    if (result.actionShow_Secondary_Intercardinal_Points !== undefined) this.layerStore.secondaryIntercardinalPts = result.actionShow_Secondary_Intercardinal_Points === true
    if (result.actionShow_Tertiary_Intercardinal_Points !== undefined) this.layerStore.tertiaryIntercardinalPts = result.actionShow_Tertiary_Intercardinal_Points === true
    if (result.actionShow_Prime_Vertical_Line !== undefined) this.layerStore.primeVerticalLine = result.actionShow_Prime_Vertical_Line === true
    if (result.actionShow_Current_Vertical_Line !== undefined) this.layerStore.currentVerticalLine = result.actionShow_Current_Vertical_Line === true
    if (result.actionShow_Colure_Lines !== undefined) this.layerStore.colureLines = result.actionShow_Colure_Lines === true
    if (result.actionShow_Precession_Circles !== undefined) this.layerStore.precessionCircles = result.actionShow_Precession_Circles === true
    if (result.actionShow_Circumpolar_Circles !== undefined) this.layerStore.circumpolarCircles = result.actionShow_Circumpolar_Circles === true
    if (result.actionShow_Invariable_Plane_Line !== undefined) this.layerStore.invariantPlaneLine = result.actionShow_Invariable_Plane_Line === true
    if (result.actionShow_Solar_Equator_Line !== undefined) this.layerStore.solarEquatorLine = result.actionShow_Solar_Equator_Line === true
    if (result.actionShow_Ecliptic_J2000_Grid !== undefined) this.layerStore.eclipticJ2000Grid = result.actionShow_Ecliptic_J2000_Grid === true
    if (result.actionShow_Supergalactic_Grid !== undefined) this.layerStore.supergalacticGrid = result.actionShow_Supergalactic_Grid === true
    if (result.actionShow_Fixed_Equatorial_Grid !== undefined) this.layerStore.fixedEquatorialGrid = result.actionShow_Fixed_Equatorial_Grid === true
    if (result.actionShow_Fixed_Equator_Line !== undefined) this.layerStore.fixedEquatorLine = result.actionShow_Fixed_Equator_Line === true
    if (result.actionShow_Zenith_Nadir !== undefined) this.layerStore.zenithNadir = result.actionShow_Zenith_Nadir === true
    if (result.actionShow_Celestial_J2000_Poles !== undefined) this.layerStore.celestialJ2000Poles = result.actionShow_Celestial_J2000_Poles === true
    if (result.actionShow_Ecliptic_J2000_Poles !== undefined) this.layerStore.eclipticJ2000Poles = result.actionShow_Ecliptic_J2000_Poles === true
    if (result.actionShow_Equinox_J2000_Points !== undefined) this.layerStore.equinoxJ2000Pts = result.actionShow_Equinox_J2000_Points === true
    if (result.actionShow_Solstice_J2000_Points !== undefined) this.layerStore.solsticeJ2000Pts = result.actionShow_Solstice_J2000_Points === true
    if (result.actionShow_Galactic_Center !== undefined) this.layerStore.galacticCenter = result.actionShow_Galactic_Center === true
    if (result.actionShow_Supergalactic_Poles !== undefined) this.layerStore.supergalacticPoles = result.actionShow_Supergalactic_Poles === true
    if (result.actionShow_Apex_Points !== undefined) this.layerStore.apexPoints = result.actionShow_Apex_Points === true
    if (result.actionShow_Umbra_Center_Point !== undefined) this.layerStore.umbraCenter = result.actionShow_Umbra_Center_Point === true
    if (result.actionShow_Longitude_Line !== undefined) this.layerStore.longitudeLine = result.actionShow_Longitude_Line === true
    if (result.actionShow_Quadrature_Line !== undefined) this.layerStore.quadratureLine = result.actionShow_Quadrature_Line === true
    if (result.actionShow_Ray_Helpers !== undefined) this.layerStore.rayHelpers = result.actionShow_Ray_Helpers === true
    if (result.actionShow_LandscapeIllumination !== undefined) this.layerStore.landscapeIllum = result.actionShow_LandscapeIllumination === true
    if (result.actionShow_LandscapeLabels !== undefined) this.layerStore.landscapeLabels = result.actionShow_LandscapeLabels === true
    if (result.actionShow_Zodiac !== undefined) this.layerStore.zodiac = result.actionShow_Zodiac === true
    if (result.actionShow_LunarSystem !== undefined) this.layerStore.lunarSystem = result.actionShow_LunarSystem === true
    if (result.actionShow_Asterism_Lines !== undefined) this.layerStore.asterismLines = result.actionShow_Asterism_Lines === true
    if (result.actionShow_Asterism_Labels !== undefined) this.layerStore.asterismLabels = result.actionShow_Asterism_Labels === true
    if (result.actionShow_Hips_Surveys !== undefined) this.layerStore.hipsSurveys = result.actionShow_Hips_Surveys === true
    if (result.actionShow_Toast_Survey !== undefined) this.layerStore.toastSurvey = result.actionShow_Toast_Survey === true
    this.layerStore.meteors = result.meteors === true
    if (result.satHints !== undefined) this.satelliteStore.satHints = result.satHints === true
    if (result.bortleScale !== undefined) this.layerViewStore.bortleScale = Math.round(result.bortleScale as number)
    if (result.milkyWayIntensity !== undefined) this.layerViewStore.milkyWayBright = Math.max(0, Math.min(6, Math.round((result.milkyWayIntensity as number) * 3)))
    if (result.luminanceAdaptation !== undefined) this.layerStore.luminanceAdaptation = result.luminanceAdaptation === true
    if (result.starTwinkle !== undefined) this.layerStore.starTwinkle = result.starTwinkle === true
    if (result.forcedStarTwinkle !== undefined) this.layerStore.forcedStarTwinkle = result.forcedStarTwinkle === true
    if (result.bigStarHalo !== undefined) this.layerStore.bigStarHalo = result.bigStarHalo === true
    if (result.starSpiky !== undefined) this.layerStore.starSpiky = result.starSpiky === true
    if (result.meteorZhr !== undefined) this.layerViewStore.meteorZhr = Math.round(result.meteorZhr as number)
    if (result.meteorZhrMax !== undefined) this.layerViewStore.meteorZhrMax = Math.max(1000, Math.round(result.meteorZhrMax as number))
    if (result.zodiacalLight !== undefined) this.layerStore.zodiacalLight = result.zodiacalLight === true
    if (result.zodiacalIntensity !== undefined) this.layerViewStore.zodiacalIntensity = result.zodiacalIntensity as number
    this.viewSettingsStore.autoZoomResets = result.autoZoomResets === true
    // The native Stellarium property is authoritative. The QAction is not
    // guaranteed to update when the time-panel uses the direct bridge command.
    if (result.nightMode !== undefined) {
      this.nightModeStore.syncNightModeFromEngine(result.nightMode === true, nightEpoch)
          } else if (result.actionShow_Night_Mode !== undefined) {
      this.nightModeStore.syncNightModeFromEngine(result.actionShow_Night_Mode === true, nightEpoch)
          }
    this.layerStore.flipHoriz = result.actionHorizontal_Flip === true
    this.layerStore.flipVert = result.actionVertical_Flip === true
    if (result.timeRate !== undefined) {
      this.timeCtl().syncTimeRateState(result.timeRate as number)
    }
    if (result.timeText !== undefined) {
      this.timeStore.observationTimeText = result.formattedTime ?? this.formatObservationTime(result.timeText)
      // 顺便校准 UTC 偏移（timeText 已含观测地偏移，jd 是纯 UTC；差值即偏移小时数）
      // 供轻量刷新 refreshSimTimeLight 使用，避免每次都跑全量 getState
      if (result.jd !== undefined) {
        const localMs = Date.parse(result.timeText.endsWith('Z') ? result.timeText : result.timeText + 'Z')
        const utcMs = ((result.jd as number) - 2440587.5) * 86400000
        if (!Number.isNaN(localMs)) {
          this.utcOffsetHours = Math.round((localMs - utcMs) / 3600000 * 4) / 4 // 取到一刻钟精度
        }
      }
    }
    // 只有当原生确实返回了观测者经纬度时，才用原生值刷新头部位置字段，
    // 否则保留 setLocation 已应用到头部的值（避免被 planetName 等字段清成“未命名”或空值）。
    if (result.latitude !== undefined && result.longitude !== undefined) {
      this.coordinateText = this.locationStore.formatDegrees(result.latitude, 'N', 'S') + ' / ' + this.locationStore.formatDegrees(result.longitude, 'E', 'W')
      if (result.locationName !== undefined && result.locationName.length > 0) {
        const planetName = result.planetName && result.planetName.length > 0 ? result.planetName : 'Earth'
        // 位置名按来源 + 观测星球取值（GPS / 自定义位置 / 名称），与快捷面板标题栏同一规则；
        // 否则引擎回读的「自定义位置」会把自动定位结果冲掉。
        this.locationText = quickLocationLabel(this.locationPickerStore.locationSource,
          this.locationPickerStore.locationDisplayName(result.locationName), planetName) + ' · ' + planetZh(planetName)
      }
      if (result.altitude !== undefined) {
        this.altitudeText = result.altitude.toFixed(0) + ' m'
      }
      if (result.planetName !== undefined && result.planetName.length > 0) {
        this.sessionToolStore.observerPlanet = result.planetName
      }
    }
    if (result.fov !== undefined) {
      this.fovText = result.fov.toFixed(1) + '°'
      this.fovSliderValue = result.fov
      this.currentFovText = result.fov.toFixed(1) + '°'
    }
    if (result.tracking !== undefined && !this.trackingRequestPending && Date.now() >= this.trackingStateIgnoreUntilMs) {
      this.trackingText = result.tracking ? 'On' : 'Off'
    }
    if (result.viewLock !== undefined) {
      this.viewSettingsStore.viewLock = result.viewLock === true
    }
      this.stateRefreshRequestPending = false
      if (this.stateRefreshQueued) {
        this.stateRefreshQueued = false
        this.refreshState()
      }
    }, () => {
      this.stateRefreshRequestPending = false
      if (this.stateRefreshQueued) {
        this.stateRefreshQueued = false
        this.refreshState()
      }
    })
  }

  // 写 ViewSettingsStore；trackingText 经 LayerHostHooks.setTrackingText 注入）。


  // setProjection → ViewSettingsStore / setEphemerisEnabled → EphemerisStore / setInformationMode /
  // setInformationField → InfoWindowStore / setNavigationBoolean / setNavigationMaxFov →
  // NavigationSettingsStore / saveAllCoreSettings / restoreCoreDefaults → ToolsStore /
  // setConfigurationDithering / setDistanceUnit → ViewSettingsStore / applyCustomInformationMask →
  // ObjectDetailStore。以上均于 解散 SettingsController 时并回各 store；跨域分派
  // settingsChoiceSelected / selectSettingsChoice 由宿主持有（上方薄分派）。

  private triggerAction(actionId: string): void {
    hilog.info(0x0000, 'StellariumArkUI', 'triggerAction send %{public}s', actionId)
    this.flashHint(I18n.t('msg_command_sent'))
    this.callInteractive('triggerAction', actionId, (r: StellariumBridgeResponse) => {
      hilog.info(0x0000, 'StellariumArkUI', 'triggerAction %{public}s ok=%{public}s err=%{public}s', actionId, r.ok === true ? '1' : '0', r.error ?? '')
      this.refreshState()
      if (actionId.indexOf('actionDisplayInfo_') === 0) {
        this.refreshSelectedObject()
      }
    })
  }

  // setFovMarkerSetting 已于 并回 state/ViewSettingsStore.ets。


  private selectCommandEntry(item: CommandCatalogEntry): void {
    this.commandStore.commandNameInput = item.name
    this.commandStore.commandPayloadInput = item.examplePayload ?? ''
    this.commandStore.commandPendingConfirmation = ''
    this.commandStore.commandResultText = ''
  }

  private executeCommandFromPanel(force: boolean = false): void {
    const commandName = this.commandStore.commandNameInput.trim()
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(commandName)) {
      this.commandStore.commandResultText = JSON.stringify({ ok: false, error: '请输入合法命令名' }, null, 2)
      return
    }
    const selected = this.commandStore.commandCatalog.find((item: CommandCatalogEntry) => item.name === commandName)
    if (selected === undefined) {
      this.commandStore.commandResultText = JSON.stringify({ ok: false, error: '命令不在当前版本目录中，请先刷新目录' }, null, 2)
      return
    }
    if (selected.requiresConfirmation && !force) {
      this.commandStore.commandPendingConfirmation = commandName
      this.commandStore.commandResultText = '该命令可能修改文件、插件、录制或外部设备状态，请确认后执行。'
      return
    }
    this.commandStore.commandPendingConfirmation = ''
    this.commandStore.commandBusy = true
    this.callInteractive(commandName, this.commandStore.commandPayloadInput, (r: StellariumBridgeResponse) => {
      this.commandStore.commandBusy = false
      this.commandStore.commandResultText = JSON.stringify(r, null, 2)
      this.refreshState()
    }, (r: StellariumBridgeResponse) => {
      this.commandStore.commandBusy = false
      this.commandStore.commandResultText = JSON.stringify({ ok: false, error: r.error ?? '命令执行超时' }, null, 2)
    })
  }

  // 搜索建议 / 筛选行为（scheduleSuggestions / fetchSuggestions / selectSearchSuggestion /
  //（建议去抖定时器自持；面板滚动复位 / animateTo / CLI 发布点 / searchObject 经 SearchHostHooks 注入）。

  private openConstellationGuide(name: string, moduleId: string = 'ConstellationMgr', displayName: string = ''): void {
    this.flashHint('已开启星座名称和连线，正在定位' + (displayName.length > 0 ? displayName : zhNameOf(name)))
    this.callInteractive('setActionChecked', 'actionShow_Constellation_Boundaries|0', () => {
      this.layerStore.constellationBoundaries = false
      this.callInteractive('setActionChecked', 'actionShow_Constellation_Lines|1', () => {
        this.layerStore.constellationLines = true
        this.callInteractive('setActionChecked', 'actionShow_Constellation_Labels|1', () => {
          this.layerStore.constellationLabels = true
          this.searchObject(name, moduleId)
        })
      })
    })
  }

  private flashHint(text: ResourceStr): void {
    this.actionHint = text
    if (this.hintTimer !== 0) {
      clearTimeout(this.hintTimer)
    }
    this.hintTimer = setTimeout(() => {
      this.actionHint = ''
    }, 1600) as number
  }

  // 用系统浏览器打开外部链接（星表下载页等）。宿主持有 UI 上下文，面板只回调 URL。
  private openExternalUrl(url: string): void {
    if (url.length === 0) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }
    context.startAbility(want).then((): void => {
      hilog.info(0x0000, 'StellariumArkUI', 'opened external url %{public}s', url)
    }).catch((): void => {
      this.flashHint(I18n.t('catalog_open_source_failed'))
    })
  }

  // 手动导入星表：选本地 .cat（不看文件名，桥按 MD5 识别目标级），异步拷到用户目录再交桥导入。
  private importCatalogFile(): void {
    if (this.catalogStore.catalogImporting) {
      hilog.warn(0xD002, 'Stellarium', '[star-catalog] picker skipped: an import is already running')
      return
    }
    const run = async (): Promise<void> => {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const options = new picker.DocumentSelectOptions()
      options.fileSuffixFilters = [I18n.t('catalog_file_filter') + '|.cat']
      options.maxSelectNumber = 1
      let selectedUris: string[] = []
      try {
        selectedUris = await new picker.DocumentViewPicker(context).select(options)
      } catch (error) {
        hilog.info(0xD002, 'Stellarium', '[star-catalog] picker dismissed: %{public}s',
          JSON.stringify(error))
        this.flashHint(I18n.t('catalog_import_cancelled'))
        return
      }
      if (selectedUris.length === 0 || selectedUris[0].length === 0) {
        hilog.info(0xD002, 'Stellarium', '[star-catalog] picker returned no file')
        this.flashHint(I18n.t('catalog_import_cancelled'))
        return
      }
      hilog.info(0xD002, 'Stellarium', '[star-catalog] picked uri=%{public}s', selectedUris[0])
      this.stageAndImportCatalog(selectedUris[0], context)
    }
    run().catch((error: Error) => {
      hilog.error(0xD002, 'Stellarium', '[star-catalog] picker flow failed: %{public}s',
        JSON.stringify(error))
      this.flashHint(I18n.t('catalog_import_failed'))
    })
  }

  // 把沙箱外的 .cat（picker / 打开方式给的 URI）落到用户目录后交桥按 MD5 导入。
  private stageAndImportCatalog(uri: string, context: common.UIAbilityContext): void {
    const run = async (): Promise<void> => {
      let baseName = uri.substring(uri.lastIndexOf('/') + 1)
      const queryIndex = baseName.indexOf('?')
      if (queryIndex >= 0) baseName = baseName.substring(0, queryIndex)
      try {
        baseName = decodeURIComponent(baseName)
      } catch (_error) {
      }
      baseName = baseName.trim()
      if (!baseName.toLowerCase().endsWith('.cat')) {
        baseName = 'catalog-import-' + Date.now().toString() + '.cat'
      }
      const destDir = context.filesDir + '/stellarium_userdir/stars/hip_gaia3'
      const destPath = destDir + '/' + baseName
      // 先 access 再按需 mkdir：真机上 mkdirSync(recursion) 会抛 13900015（文件存在）。
      // 整段（含 unlink）必须包在 try 里 —— 原先裸奔时任一抛出都会变成未处理的 promise rejection，
      // 既不弹提示也不写日志，「手动导入」因此表现为「点了没反应、列表不变」。
      try {
        if (!fileIo.accessSync(destDir)) fileIo.mkdirSync(destDir, true)
        if (fileIo.accessSync(destPath)) fileIo.unlinkSync(destPath)
      } catch (error) {
        hilog.error(0xD002, 'Stellarium', '[star-catalog] prepare failed dir=%{public}s err=%{public}s',
          destDir, JSON.stringify(error))
        this.flashHint(I18n.t('catalog_import_failed'))
        return
      }
      hilog.info(0xD002, 'Stellarium', '[star-catalog] staging uri=%{public}s -> %{public}s',
        uri, destPath)
      try {
        await fileIo.copy(uri, fileUri.getUriFromPath(destPath))
      } catch (error) {
        // 这条路径原先只弹通用提示、不写日志，导致「导入失败」查不到原因。
        hilog.error(0xD002, 'Stellarium', '[star-catalog] copy failed err=%{public}s',
          JSON.stringify(error))
        this.flashHint(I18n.t('catalog_import_failed'))
        return
      }
      this.catalogStore.importLocalCatalog(destPath)
    }
    run().catch((error: Error) => {
      hilog.error(0xD002, 'Stellarium', '[star-catalog] stage flow failed: %{public}s',
        JSON.stringify(error))
      this.flashHint(I18n.t('catalog_import_failed'))
    })
  }

  // 「打开方式」收到的 .cat：Qt 就绪后按文件名匹配星表并导入（引擎未就绪先挂起）。
  private onOpenCatalogUriChanged(): void {
    const uri = this.openCatalogUri
    if (uri.length === 0) {
      return
    }
    this.openCatalogUri = ''
    hilog.info(0xD002, 'Stellarium', '[star-catalog] open-with uri=%{public}s qtReady=%{public}s',
      uri, String(this.qtContentReadyForCatalog))
    if (this.qtContentReadyForCatalog) {
      this.handleOpenCatalogUri(uri)
    } else {
      this.pendingOpenCatalogUri = uri
    }
  }

  private onQtContentReadyForCatalog(): void {
    if (!this.qtContentReadyForCatalog || this.pendingOpenCatalogUri.length === 0) {
      return
    }
    const uri = this.pendingOpenCatalogUri
    this.pendingOpenCatalogUri = ''
    this.handleOpenCatalogUri(uri)
  }

  // 「打开方式」收到的 .cat：打开星表面板并把文件交导入（桥按 MD5 识别目标级）。
  private handleOpenCatalogUri(uri: string): void {
    this.setPanel('catalogs')
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.stageAndImportCatalog(uri, context)
  }

  private currentGuide(): AstronomyGuide {
    return ASTRONOMY_GUIDES.find((guide: AstronomyGuide) => guide.id === this.guideStore.guideState.guideId) ?? ASTRONOMY_GUIDES[0]
  }

  private currentGuideStep(): GuideStep { return this.currentGuide().steps[this.guideStore.guideState.index] }

  // 夜间模式颜色方案

  private selectedStatusZh(en: string): string {
    return I18n.selectedStatus(en)
  }

// ===== 页面渲染入口与内联 @Builder =====

  build() {
    WithTheme({ theme: stellariumTheme(this.nightModeStore.nightMode) }) {
    Stack() {
      // Language refresh anchor: reading i18nLang creates a reactive
      // dependency on AppStorage('i18nLang'). When language changes,
      // ArkUI re-executes build() and all I18n.t() calls re-evaluate.
      // Using a real (but invisible) element ensures the dependency is tracked.
      Text(this.i18nLang)
        .fontSize(0.1)
        .opacity(0)
        .width(0)
        .height(0)
        .zIndex(-1)
      Text('')
        .fontSize(1)
        .width(1)
        .height(1)
        .position({ x: 0, y: 0 })
        .id('sky-keyboard-target')
        .hitTestBehavior(HitTestMode.None)
        .focusable(true)
        .defaultFocus(true)
        .onFocus(() => { this.keyboardShortcutCtl().setSkyFocused(true) })
        .onBlur(() => { this.keyboardShortcutCtl().setSkyFocused(false) })
        .onKeyEvent((event: KeyEvent): boolean => this.handleSkyKeyboard(event))
      XComponent({
        type: XComponentType.SURFACE,
        id: 'stellarium_entry_gl_probe',
        libraryname: 'entry'
      })
        .width('100%')
        .height('100%')
        .zIndex(0)
        .hitTestBehavior(HitTestMode.None)
        .onAppear(() => { this.onQtSurfaceAppear() })

      if (this.createInfo !== undefined && this.privacyNativeStartupAllowed) {
        XComponent({
          type: XComponentType.NODE,
          id: this.createInfo.xComponentId,
          libraryname: 'qohos'
        })
          .onAttach(() => { this.onQtNativeNodeAttach() })
          .onAppear(() => { this.onQtNativeNodeAppear() })
          .onDisAppear(() => { this.onQtNativeNodeDisappear() })
          .width('100%')
          .height('100%')
          .zIndex(-1)
          .opacity(0.01)
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.None)
          .enabled(false)
      }

      if (this.skyTouchFeedback) {
        Row()
          .width(120)
          .height(120)
          .borderRadius(60)
          .backgroundColor(this.hostSlots().chipInactiveBg)
          .border({ width: 1, color: this.hostSlots().border })
          .shadow({ radius: 42, color: this.hostSlots().accentSoft, offsetX: 0, offsetY: 0 })
          .align(Alignment.Center)
          .offset({ x: this.skyTouchX - this.skyWidth / 2, y: this.skyTouchY - this.skyHeight / 2 })
          .hitTestBehavior(HitTestMode.None)
          .zIndex(0)
          .animation({ duration: 0, curve: Curve.Linear })
      }
      if (this.skyTouchFeedbackMulti) {
        Row()
          .width(120)
          .height(120)
          .borderRadius(60)
          .backgroundColor(this.hostSlots().chipInactiveBg)
          .border({ width: 1, color: this.hostSlots().border })
          .shadow({ radius: 42, color: this.hostSlots().accentSoft, offsetX: 0, offsetY: 0 })
          .align(Alignment.Center)
          .offset({ x: this.skyTouchX2 - this.skyWidth / 2, y: this.skyTouchY2 - this.skyHeight / 2 })
          .hitTestBehavior(HitTestMode.None)
          .zIndex(0)
          .animation({ duration: 0, curve: Curve.Linear })
      }

        // 画布触摸层：与 toolbar/panel 平级（都是 1234 根 Stack 的子），
      // 承接 selectAt/onTouch。关键：不能挂在 1352 全屏 UI 父上，
      // 否则会抑制其子组件（toolbar/面板按钮）的 onClick。
      // 参考已验证的 compactShell：onTouch 挂在独立 Blank 上而非全屏 UI 父。
      Stack() { }
        .width('100%')
        .height('100%')
        // 星图触摸由各布局内部的专属触摸面处理，禁止全屏层穿透 UI。
        .hitTestBehavior(HitTestMode.None)
        .onTouch((event: TouchEvent) => {
          this.handleOverlayTouch(event)
        })

      if (this.scriptStore.scriptPlaybackVisible(this.guideStore.guideState.active)) {
        if (this.guideStore.guideState.active) {
          InteractiveGuideShell({
            guidePhase: this.guideStore.guideState.phase,
            guideIndex: this.guideStore.guideState.index,
            guideCount: this.guideStore.guideState.count,
            guideAutomatic: this.guideStore.guideState.automatic,
            guideRemaining: this.guideStore.guideState.remaining,
            guideTitle: I18n.t(this.currentGuide().title),
            guideCredit: I18n.t(this.currentGuide().credit),
            guideStepTitle: planetZh(this.currentGuideStep().title),
            guideStepText: this.currentGuideStep().text,
            guideStepKey: this.currentGuideStep().target,
            cardWidth: this.guideCardWidth(),
            cardHeight: guideCardHeight(this.skyHeight, this.scriptControlSafeTop()),
            cardX: guideCardX(this.isExpandedLayout, this.skyWidth, this.guideCardWidth(), this.scriptStore.scriptControlOffsetX),
            cardY: guideCardY(this.skyHeight, guideCardHeight(this.skyHeight, this.scriptControlSafeTop()), this.scriptControlSafeTop(), this.scriptStore.scriptControlOffsetY),
            onSkyTouch: (event: TouchEvent) => { this.handleSkySurfaceTouch(event) },
            onSkyMouse: (event: MouseEvent) => { this.handleSkySurfaceMouse(event) },
            onSkyAxis: (event: AxisEvent) => { this.skyInputCtl().handleSkyAxis(event) },
            onControlDragTouch: (event: TouchEvent) => { this.scriptPlaybackCtl().handleScriptControlDragTouch(event) },
            onAction: (action: string) => { this.guideCtl().executeGuideRequest('guideAction', action) }
          })
        } else {
          ScriptFocusShell({
            scriptStore: this.scriptStore,
            playbackVisible: this.scriptStore.scriptPlaybackVisible(this.guideStore.guideState.active),
            compact: this.scriptStore.scriptControlCompact(this.skyWidth),
            displayName: scriptZh(this.scriptStore.scriptId.length > 0 ? this.scriptStore.scriptId : (this.scriptStore.scriptLaunchingName.length > 0 ? this.scriptStore.scriptLaunchingName : this.scriptStore.replayName)),
            hasCaptions: this.scriptStore.visibleScriptCaptions().length > 0,
            captionText: this.scriptStore.visibleScriptCaptionText(),
            waitText: this.scriptStore.scriptWaitDisplayText(),
            rateText: (this.scriptStore.replaying ? this.scriptStore.replayRate : this.scriptStore.scriptRate).toFixed((this.scriptStore.replaying ? this.scriptStore.replayRate : this.scriptStore.scriptRate) < 1 ? 2 : 1) + 'x',
            keyButtonWidth: this.scriptStore.scriptKeyButtonWidth(this.skyWidth),
            controlWidth: scriptControlWidth(this.skyWidth, this.scriptStore.replaying),
            controlHeight: this.scriptStore.scriptControlHeight(),
            controlX: scriptControlX(this.skyWidth, this.scriptStore.replaying, this.scriptStore.scriptControlOffsetX),
            controlY: scriptControlY(this.skyHeight, this.scriptControlSafeTop(), this.scriptStore.scriptControlHeight(), this.scriptStore.scriptControlOffsetY),
            onSkyTouch: (event: TouchEvent) => { this.handleSkySurfaceTouch(event) },
            onSkyMouse: (event: MouseEvent) => { this.handleSkySurfaceMouse(event) },
            onSkyAxis: (event: AxisEvent) => { this.skyInputCtl().handleSkyAxis(event) },
            onControlDragTouch: (event: TouchEvent) => { this.scriptPlaybackCtl().handleScriptControlDragTouch(event) },
            onContinue: () => { this.scriptPlaybackCtl().continueNativeScript() },
            onChangeRate: (delta: number) => { this.recordingCtl().changePlaybackRate(delta) },
            onToggleReplayPause: () => { this.recordingCtl().toggleReplayPause() },
            onStop: () => { this.scriptPlaybackCtl().stopScriptPlayback() },
            onSendKey: (k: string) => { this.scriptPlaybackCtl().sendScriptKey(k) }
          })
        }
      }
      if (!this.scriptStore.scriptPlaybackVisible(this.guideStore.guideState.active) && this.tools.recording && !this.tools.recordingUiExpanded) {
        RecordingFocusShell({
          onSkyTouch: (event: TouchEvent) => { this.handleSkySurfaceTouch(event) },
          onSkyMouse: (event: MouseEvent) => { this.handleSkySurfaceMouse(event) },
          onSkyAxis: (event: AxisEvent) => { this.skyInputCtl().handleSkyAxis(event) }
        })
      }
      if (!this.scriptStore.scriptPlaybackVisible(this.guideStore.guideState.active) && !(this.tools.recording && !this.tools.recordingUiExpanded) && !this.polarScopeStore.polarScopeVisible) {
        Stack() {
          if (this.isFoldHoverLayout) {
            Stack() {
              HoverObservatoryShell({
                objectDetailStore: this.objectDetailStore,
                objectMediaStore: this.objectMediaStore,
                overlayStore: this.overlayStore,
                observationTimeText: this.timeStore.observationTimeText,
                currentFovText: this.currentFovText,
                skyWidth: this.skyWidth,
                skyHeight: this.skyHeight,
                hoverSkyPaneHeight: this.hoverSkyPaneHeight(),
                dockTop: this.dockTop(),
                panelIdleGlass: this.panelIdleGlass,
                panelVisible: this.panelVisible,
                isExpandedLayout: this.isExpandedLayout,
                activePanel: this.activePanel,
                languageRevision: this.languageStore.languageRevision,
                actions: this.canonicalDockActions(),
                chromeOpacity: this.phoneChromeOpacity(),
                chromeIsGlass: this.phoneChromeIsGlass(),
                dockWidthPercent: this.compactDockWidthPercent(),
                dockIconSize: this.compactDockIconSize(),
                dockLabelFontSize: this.compactDockLabelFontSize(),
                dockItemHeight: this.compactDockItemHeight(),
                infoWinVisible: this.infoWindowStore.infoWinVisible,
                bottomCardIndex: this.objectDetailStore.bottomCardIndex,
                liveInfoVisible: this.infoWindowStore.selectedLiveInfoVisible(),
                contentOpacity: this.objectDetailContentOpacity,
                contentTranslateX: this.objectDetailContentTranslateX,
                cardWidth: this.bottomCardWidth(),
                cardHeight: this.bottomCardHeight(),
                viewLock: this.viewSettingsStore.viewLock,
                speechStatus: this.guideStore.speechStatus,
                inObservingList: this.obsListStore.observingList.includes(this.objectDetailStore.selectedName),
                iconName: this.objectDetailStore.objectInspectorIcon(),
                detailDisplayMode: this.infoWindowStore.detailDisplayMode,
                observeExpanded: this.infoWindowStore.observeExpanded,
                distanceText: this.objectDetailStore.objectDistanceNoticeText(this.infoWindowStore.distanceInformationVisible()),
                distanceSummaryText: this.objectDetailStore.objectDistanceSummary(this.infoWindowStore.distanceInformationVisible()),
                imageHeight: this.objectMediaStore.objectInspectorImageHeight(),
                inlineModelSize: this.objectInspectorInlineModelSize(),
                modelReady: this.objectModelRendererCtl().modelReady(),
                modelRendering: this.objectModelRendererCtl().isRendering(),
                hasModelTexture: this.objectModelRendererCtl().hasTexture(),
                modelNotice: this.objectMediaStore.objectInspectorModelNotice(),
                warmupText: this.objectMediaStore.objectInspectorMediaWarmupText(),
                fallbackKind: objectInspectorFallbackVisualKind(this.objectDetailStore.selectedObjectType, this.objectDetailStore.selectedType),
                satelliteVisible: this.objectDetailStore.selectedObjectIsArtificialSatellite(),
                tleEpoch: this.objectDetailStore.selectedSatelliteTleEpoch(),
                cultureVisible: this.objectDetailStore.selectedObjectIsConstellation(),
                connectorVisible: this.overlayStore.objectDetailConnectorVisible && !this.infoWindowStore.observeModeEnabled(),
                connectorLength: this.objectDetailConnectorLength,
                connectorX: this.objectDetailConnectorX,
                connectorY: this.objectDetailConnectorY,
                connectorAngle: this.objectDetailConnectorAngle,
                connectorAnimateGeometry: this.objectDetailConnectorAnimateGeometry,
                connectorTargetOnScreen: this.objectDetailConnectorTargetOnScreen,
                connectorTargetX: this.objectDetailConnectorTargetX,
                connectorTargetY: this.objectDetailConnectorTargetY,
                connectorEndX: this.objectDetailConnectorEndX,
                connectorEndY: this.objectDetailConnectorEndY,
                markerSize: this.objectDetailMarkerSize(),
                detailX: this.detailCardX(),
                detailY: this.detailCardY(),
                detailWidth: this.detailCardWidth(),
                detailHeight: this.detailCardHeight(),
                scroller: this.objectDetailScroller,
                onSkyTouch: (event: TouchEvent) => { this.handleSkySurfaceTouch(event) },
                onSkyMouse: (event: MouseEvent) => { this.handleSkySurfaceMouse(event) },
                onSkyAxis: (event: AxisEvent) => { this.skyInputCtl().handleSkyAxis(event) },
                onDockTouch: (event: TouchEvent) => { this.handleDockTouch(event) },
                onDockTap: (item: ShellAction) => { this.activateDockAction(item) },
                onPanelTouch: (event: TouchEvent) => { this.notePanelTouch(event) },
                resolve: (key: string) => this.selectedDisplayValue(key),
                nameOf: (name: string) => zhNameOf(name),
                typeOf: (type: string) => zhType(type),
                onDragTouch: (event: TouchEvent) => { this.handleObjectInspectorDragTouch(event) },
                onDismiss: () => { this.dismissObjectInspector() },
                onSelectTab: (index: number) => { this.selectObjectDetailTab(index) },
                onLoadPasses: () => { this.objectDetailStore.loadSelectedSatellitePasses() },
                onMediaOpen: () => { this.objectInspectorMediaCtl().openObjectInspectorMediaPreview() },
                onMediaRetry: () => { this.objectInspectorMediaCtl().retryObjectInspectorMedia() },
                onModelExpand: () => { this.objectModelRendererCtl().setObjectInspectorModelImmersive(true) },
                onModelTouch: (event: TouchEvent) => { this.objectModelRendererCtl().handleObjectInspectorModelTouch(event) },
                onCenter: () => { this.moveToSelectedObject() },
                onCenterObject: () => { this.moveToSelectedObject() },
                onExpandObserve: () => { this.infoWindowStore.setObserveExpanded(true) },
                onCollapseObserve: () => { this.infoWindowStore.setObserveExpanded(false) },
                onToggleLock: () => { this.layerCtl().toggleViewLock() },
                onToggleObserving: () => { this.toggleSelectedObservingList() },
                onRefresh: () => { this.refreshSelectedObject(); this.refreshState() },
                onReselect: () => { this.triggerAction('actionGoto_ReSelect_Last_Selected_Object'); this.refreshSelectedObject() },
                onSpeak: () => { speakSelectedObject(this.commandPort(), { flashHint: (text: ResourceStr): void => this.flashHint(text), setSpeechStatus: (text: string): void => { this.guideStore.speechStatus = text } }) }
              })
              if (this.panelVisible) {
                Stack() { this.compactPanel() }
                  .position({ x: 0, y: this.hoverPanelTop() })
                  .width('100%')
                  .hitTestBehavior(HitTestMode.Default)
                  .zIndex(30)
              }
            }
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
                .combine(TransitionEffect.scale({ x: 0.985, y: 0.985 }).animation({ duration: 220, curve: curves.springMotion(0.55, 0.88) })))
          } else if (this.isExpandedLayout) {
            Stack() {
              ExpandedShell({
                objectDetailStore: this.objectDetailStore,
                objectMediaStore: this.objectMediaStore,
                overlayStore: this.overlayStore,
                gyroStore: this.gyroStore,
                expandedUiAllowed: this.expandedUiAllowed(),
                panelVisible: this.panelVisible,
                isExpandedLayout: this.isExpandedLayout,
                activePanel: this.activePanel,
                languageRevision: this.languageStore.languageRevision,
                actions: this.canonicalDockActions(),
                chromeOpacity: this.phoneChromeOpacity(),
                chromeIsGlass: this.phoneChromeIsGlass(),
                dockWidthPercent: this.compactDockWidthPercent(),
                dockIconSize: this.compactDockIconSize(),
                dockLabelFontSize: this.compactDockLabelFontSize(),
                dockItemHeight: this.compactDockItemHeight(),
                skyHeight: this.skyHeight,
                polarScopeVisible: this.polarScopeStore.polarScopeVisible,
                dockClockText: this.dockClockText,
                dockWidth: dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()),
                dockLeft: dockLeft(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()),
                dockTop: this.dockTop(),
                expandedDockWidth: expandedDockWidth(this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN),
                dockHeight: this.dockHeight(),
                expandedDockLeft: expandedDockLeft(this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN),
                gyroPanelLeft: this.EDGE_MARGIN + 64,
                gyroPanelTop: railTop(this.EDGE_MARGIN) + 120,
                infoWinVisible: this.infoWindowStore.infoWinVisible,
                bottomCardIndex: this.objectDetailStore.bottomCardIndex,
                liveInfoVisible: this.infoWindowStore.selectedLiveInfoVisible(),
                contentOpacity: this.objectDetailContentOpacity,
                contentTranslateX: this.objectDetailContentTranslateX,
                cardWidth: this.bottomCardWidth(),
                cardHeight: this.bottomCardHeight(),
                viewLock: this.viewSettingsStore.viewLock,
                speechStatus: this.guideStore.speechStatus,
                inObservingList: this.obsListStore.observingList.includes(this.objectDetailStore.selectedName),
                iconName: this.objectDetailStore.objectInspectorIcon(),
                detailDisplayMode: this.infoWindowStore.detailDisplayMode,
                observeExpanded: this.infoWindowStore.observeExpanded,
                distanceText: this.objectDetailStore.objectDistanceNoticeText(this.infoWindowStore.distanceInformationVisible()),
                distanceSummaryText: this.objectDetailStore.objectDistanceSummary(this.infoWindowStore.distanceInformationVisible()),
                imageHeight: this.objectMediaStore.objectInspectorImageHeight(),
                inlineModelSize: this.objectInspectorInlineModelSize(),
                modelReady: this.objectModelRendererCtl().modelReady(),
                modelRendering: this.objectModelRendererCtl().isRendering(),
                hasModelTexture: this.objectModelRendererCtl().hasTexture(),
                modelNotice: this.objectMediaStore.objectInspectorModelNotice(),
                warmupText: this.objectMediaStore.objectInspectorMediaWarmupText(),
                fallbackKind: objectInspectorFallbackVisualKind(this.objectDetailStore.selectedObjectType, this.objectDetailStore.selectedType),
                satelliteVisible: this.objectDetailStore.selectedObjectIsArtificialSatellite(),
                tleEpoch: this.objectDetailStore.selectedSatelliteTleEpoch(),
                cultureVisible: this.objectDetailStore.selectedObjectIsConstellation(),
                connectorVisible: this.overlayStore.objectDetailConnectorVisible && !this.infoWindowStore.observeModeEnabled(),
                connectorLength: this.objectDetailConnectorLength,
                connectorX: this.objectDetailConnectorX,
                connectorY: this.objectDetailConnectorY,
                connectorAngle: this.objectDetailConnectorAngle,
                connectorAnimateGeometry: this.objectDetailConnectorAnimateGeometry,
                connectorTargetOnScreen: this.objectDetailConnectorTargetOnScreen,
                connectorTargetX: this.objectDetailConnectorTargetX,
                connectorTargetY: this.objectDetailConnectorTargetY,
                connectorEndX: this.objectDetailConnectorEndX,
                connectorEndY: this.objectDetailConnectorEndY,
                markerSize: this.objectDetailMarkerSize(),
                detailX: this.detailCardX(),
                detailY: this.detailCardY(),
                detailWidth: this.detailCardWidth(),
                detailHeight: this.detailCardHeight(),
                scroller: this.objectDetailScroller,
                onSkyTouch: (event: TouchEvent) => { this.handleSkySurfaceTouch(event) },
                onSkyMouse: (event: MouseEvent) => { this.handleSkySurfaceMouse(event) },
                onSkyAxis: (event: AxisEvent) => { this.skyInputCtl().handleSkyAxis(event) },
                onDockTouch: (event: TouchEvent) => { this.handleDockTouch(event) },
                onDockTap: (item: ShellAction) => { this.activateDockAction(item) },
                onPanelTouch: (event: TouchEvent) => { this.notePanelTouch(event) },
                onOpenTime: () => { this.setPanel('time') },
                onZoomIn: () => { this.zoomStep(0.8) },
                onZoomOut: () => { this.zoomStep(1.25) },
                fovText: this.currentFovText,
                chromeRowY: this.chromeRowY(),
                chromeRowWidth: dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()),
                chromeRowPosXLeft: chromeRowPosXLeft(this.isExpandedLayout, this.EDGE_MARGIN, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.compactDockWidthPercent()),
                chromeRowPosXRight: chromeRowPosXRight(this.isExpandedLayout, this.EDGE_MARGIN, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.compactDockWidthPercent()),
                chromeZoomHorizontal: this.chromeZoomHorizontal(),
                onFlashHint: (text: string) => { this.flashHint(text) },
                onCalibrate: () => { this.gyroCtl().calibrateGyroscope() },
                onToggleGyroscope: (enabled: boolean) => { this.gyroCtl().requestGyroscopeToggle(enabled) },
                resolve: (key: string) => this.selectedDisplayValue(key),
                nameOf: (name: string) => zhNameOf(name),
                typeOf: (type: string) => zhType(type),
                onDragTouch: (event: TouchEvent) => { this.handleObjectInspectorDragTouch(event) },
                onDismiss: () => { this.dismissObjectInspector() },
                onSelectTab: (index: number) => { this.selectObjectDetailTab(index) },
                onLoadPasses: () => { this.objectDetailStore.loadSelectedSatellitePasses() },
                onMediaOpen: () => { this.objectInspectorMediaCtl().openObjectInspectorMediaPreview() },
                onMediaRetry: () => { this.objectInspectorMediaCtl().retryObjectInspectorMedia() },
                onModelExpand: () => { this.objectModelRendererCtl().setObjectInspectorModelImmersive(true) },
                onModelTouch: (event: TouchEvent) => { this.objectModelRendererCtl().handleObjectInspectorModelTouch(event) },
                onCenter: () => { this.moveToSelectedObject() },
                onCenterObject: () => { this.moveToSelectedObject() },
                onExpandObserve: () => { this.infoWindowStore.setObserveExpanded(true) },
                onCollapseObserve: () => { this.infoWindowStore.setObserveExpanded(false) },
                onToggleLock: () => { this.layerCtl().toggleViewLock() },
                onToggleObserving: () => { this.toggleSelectedObservingList() },
                onRefresh: () => { this.refreshSelectedObject(); this.refreshState() },
                onReselect: () => { this.triggerAction('actionGoto_ReSelect_Last_Selected_Object'); this.refreshSelectedObject() },
                onSpeak: () => { speakSelectedObject(this.commandPort(), { flashHint: (text: ResourceStr): void => this.flashHint(text), setSpeechStatus: (text: string): void => { this.guideStore.speechStatus = text } }) }
              })
              if (this.panelVisible) {
                Stack({ alignContent: Alignment.TopStart }) { this.floatingPanel() }
                  .width(this.panelWidth)
                  .height(this.expandedPanelHeight())
                  .position({ x: expandedMainPanelLeft(this.EDGE_MARGIN, this.panelOffsetX), y: this.expandedPanelTop() })
                  .animation({ duration: 320, curve: curves.springMotion(0.46, 0.86) })
                  // Default keeps the panel above the sibling sky surface while still
                  // letting its deepest child (Button, Slider, Scroll, TextInput) own
                  // the gesture. Block would stop those controls at this outer shell.
                  .hitTestBehavior(HitTestMode.Default)
                  .zIndex(30)
              }
            }
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
                .combine(TransitionEffect.scale({ x: 1.015, y: 1.015 }).animation({ duration: 220, curve: curves.springMotion(0.55, 0.88) })))
          } else {
            // 手机/折叠半折壳已组件化（CompactShell）；面板仍是宿主薄 @Builder（compactPanel），
            // 无法跨组件调用，故在同一过渡包裹内由宿主渲染。
            Stack() {
              CompactShell({
                objectDetailStore: this.objectDetailStore,
                objectMediaStore: this.objectMediaStore,
                overlayStore: this.overlayStore,
                gyroStore: this.gyroStore,
                skyHeight: this.skyHeight,
                panelVisible: this.panelVisible,
                isExpandedLayout: this.isExpandedLayout,
                polarScopeVisible: this.polarScopeStore.polarScopeVisible,
                activePanel: this.activePanel,
                languageRevision: this.languageStore.languageRevision,
                actions: this.canonicalDockActions(),
                chromeOpacity: this.phoneChromeOpacity(),
                chromeIsGlass: this.phoneChromeIsGlass(),
                dockWidthPercent: this.compactDockWidthPercent(),
                dockIconSize: this.compactDockIconSize(),
                dockLabelFontSize: this.compactDockLabelFontSize(),
                dockItemHeight: this.compactDockItemHeight(),
                dockClockText: this.dockClockText,
                dockWidth: dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()),
                dockLeft: dockLeft(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()),
                dockTop: this.dockTop(),
                musicEnabled: this.audioStore.musicEnabled,
                compactQuickPressed: this.compactQuickPressed,
                quickX: this.compactTopQuickX(),
                quickY: compactTopQuickY(),
                infoWinVisible: this.infoWindowStore.infoWinVisible,
                bottomCardIndex: this.objectDetailStore.bottomCardIndex,
                liveInfoVisible: this.infoWindowStore.selectedLiveInfoVisible(),
                contentOpacity: this.objectDetailContentOpacity,
                contentTranslateX: this.objectDetailContentTranslateX,
                cardWidth: this.bottomCardWidth(),
                cardHeight: this.bottomCardHeight(),
                viewLock: this.viewSettingsStore.viewLock,
                speechStatus: this.guideStore.speechStatus,
                inObservingList: this.obsListStore.observingList.includes(this.objectDetailStore.selectedName),
                iconName: this.objectDetailStore.objectInspectorIcon(),
                detailDisplayMode: this.infoWindowStore.detailDisplayMode,
                observeExpanded: this.infoWindowStore.observeExpanded,
                distanceText: this.objectDetailStore.objectDistanceNoticeText(this.infoWindowStore.distanceInformationVisible()),
                distanceSummaryText: this.objectDetailStore.objectDistanceSummary(this.infoWindowStore.distanceInformationVisible()),
                imageHeight: this.objectMediaStore.objectInspectorImageHeight(),
                inlineModelSize: this.objectInspectorInlineModelSize(),
                modelReady: this.objectModelRendererCtl().modelReady(),
                modelRendering: this.objectModelRendererCtl().isRendering(),
                hasModelTexture: this.objectModelRendererCtl().hasTexture(),
                modelNotice: this.objectMediaStore.objectInspectorModelNotice(),
                warmupText: this.objectMediaStore.objectInspectorMediaWarmupText(),
                fallbackKind: objectInspectorFallbackVisualKind(this.objectDetailStore.selectedObjectType, this.objectDetailStore.selectedType),
                satelliteVisible: this.objectDetailStore.selectedObjectIsArtificialSatellite(),
                tleEpoch: this.objectDetailStore.selectedSatelliteTleEpoch(),
                cultureVisible: this.objectDetailStore.selectedObjectIsConstellation(),
                connectorVisible: this.overlayStore.objectDetailConnectorVisible && !this.infoWindowStore.observeModeEnabled(),
                connectorLength: this.objectDetailConnectorLength,
                connectorX: this.objectDetailConnectorX,
                connectorY: this.objectDetailConnectorY,
                connectorAngle: this.objectDetailConnectorAngle,
                connectorAnimateGeometry: this.objectDetailConnectorAnimateGeometry,
                connectorTargetOnScreen: this.objectDetailConnectorTargetOnScreen,
                connectorTargetX: this.objectDetailConnectorTargetX,
                connectorTargetY: this.objectDetailConnectorTargetY,
                connectorEndX: this.objectDetailConnectorEndX,
                connectorEndY: this.objectDetailConnectorEndY,
                markerSize: this.objectDetailMarkerSize(),
                detailX: this.detailCardX(),
                detailY: this.detailCardY(),
                detailWidth: this.detailCardWidth(),
                detailHeight: this.detailCardHeight(),
                scroller: this.objectDetailScroller,
                onSkyTouch: (event: TouchEvent) => { this.handleSkySurfaceTouch(event) },
                onSkyMouse: (event: MouseEvent) => { this.handleSkySurfaceMouse(event) },
                onSkyAxis: (event: AxisEvent) => { this.skyInputCtl().handleSkyAxis(event) },
                onDockTouch: (event: TouchEvent) => { this.handleDockTouch(event) },
                onDockTap: (item: ShellAction) => { this.activateDockAction(item) },
                onPanelTouch: (event: TouchEvent) => { this.notePanelTouch(event) },
                onOpenTime: () => { this.setPanel('time') },
                onZoomIn: () => { this.zoomStep(0.8) },
                onZoomOut: () => { this.zoomStep(1.25) },
                fovText: this.currentFovText,
                chromeRowY: this.chromeRowY(),
                chromeRowWidth: dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()),
                chromeRowPosXLeft: chromeRowPosXLeft(this.isExpandedLayout, this.EDGE_MARGIN, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.compactDockWidthPercent()),
                chromeRowPosXRight: chromeRowPosXRight(this.isExpandedLayout, this.skyWidth, this.EDGE_MARGIN, this.panelVisible, this.panelWidth, this.panelOffsetX, this.compactDockWidthPercent()),
                chromeZoomHorizontal: this.chromeZoomHorizontal(),
                onGyro: () => {
                  hilog.info(0x0000, 'StellariumArkUI', '[DIAG] gyro button CLICKED gyroscopeEnabled=%{public}s', this.gyroStore.gyroscopeEnabled.toString())
                  this.resetPanelIdle()
                  if (!this.gyroStore.gyroscopeEnabled) this.syncEquatorialOffForGyro()
                  this.gyroCtl().toggleGyroscope(!this.gyroStore.gyroscopeEnabled)
                },
                onAudio: () => {
                  hilog.info(0x0000, 'StellariumArkUI', '[DIAG] audio button CLICKED musicEnabled=%{public}s', this.audioStore.musicEnabled.toString())
                  this.resetPanelIdle()
                  this.audioStore.toggleMusic()
                  this.flashHint(this.audioStore.musicEnabled ? I18n.t('music_on_hint') : I18n.t('music_off_hint'))
                },
                onCompactTopQuickTouch: (event: TouchEvent) => { this.handleCompactTopQuickTouch(event) },
                onFlashHint: (text: string) => { this.flashHint(text) },
                onCalibrate: () => { this.gyroCtl().calibrateGyroscope() },
                onToggleGyroscope: (enabled: boolean) => { this.gyroCtl().requestGyroscopeToggle(enabled) },
                resolve: (key: string) => this.selectedDisplayValue(key),
                nameOf: (name: string) => zhNameOf(name),
                typeOf: (type: string) => zhType(type),
                onDragTouch: (event: TouchEvent) => { this.handleObjectInspectorDragTouch(event) },
                onDismiss: () => { this.dismissObjectInspector() },
                onSelectTab: (index: number) => { this.selectObjectDetailTab(index) },
                onLoadPasses: () => { this.objectDetailStore.loadSelectedSatellitePasses() },
                onMediaOpen: () => { this.objectInspectorMediaCtl().openObjectInspectorMediaPreview() },
                onMediaRetry: () => { this.objectInspectorMediaCtl().retryObjectInspectorMedia() },
                onModelExpand: () => { this.objectModelRendererCtl().setObjectInspectorModelImmersive(true) },
                onModelTouch: (event: TouchEvent) => { this.objectModelRendererCtl().handleObjectInspectorModelTouch(event) },
                onCenter: () => { this.moveToSelectedObject() },
                onCenterObject: () => { this.moveToSelectedObject() },
                onExpandObserve: () => { this.infoWindowStore.setObserveExpanded(true) },
                onCollapseObserve: () => { this.infoWindowStore.setObserveExpanded(false) },
                onToggleLock: () => { this.layerCtl().toggleViewLock() },
                onToggleObserving: () => { this.toggleSelectedObservingList() },
                onRefresh: () => { this.refreshSelectedObject(); this.refreshState() },
                onReselect: () => { this.triggerAction('actionGoto_ReSelect_Last_Selected_Object'); this.refreshSelectedObject() },
                onSpeak: () => { speakSelectedObject(this.commandPort(), { flashHint: (text: ResourceStr): void => this.flashHint(text), setSpeechStatus: (text: string): void => { this.guideStore.speechStatus = text } }) }
              })
              if (this.panelVisible) {
                Stack({ alignContent: Alignment.Bottom }) {
                  this.compactPanel()
                }
                  .width('100%')
                  .height(this.compactPanelHeight() + 10)
                  .position({ x: 0, y: this.compactPanelTop() })
                  .hitTestBehavior(HitTestMode.Transparent)
                  .zIndex(30)
              }
            }
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
                .combine(TransitionEffect.scale({ x: 0.985, y: 0.985 }).animation({ duration: 220, curve: curves.springMotion(0.55, 0.88) })))
          }

          // Dock uses a dedicated top-level hit target. The expanded sky surface
          // intentionally blocks gestures, so relying on the visual Dock's child
          // handlers lets tablet touches be intercepted before they reach it.
          Stack() { }
            .width(dockWidthPixels(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()))
            .height(this.dockHeight())
            .position({ x: dockLeft(this.isExpandedLayout, this.skyWidth, this.panelVisible, this.panelWidth, this.panelOffsetX, this.EDGE_MARGIN, this.compactDockWidthPercent()), y: this.dockTop() })
            .hitTestBehavior(HitTestMode.Block)
            .zIndex(80)
            .onTouch((event: TouchEvent) => {
              this.handleDockTouch(event, true)
            })

            HarmonyShell({
              overlayStore: this.overlayStore,
              gyroStore: this.gyroStore,
              isExpandedLayout: this.isExpandedLayout,
            viewCoordinatesVisible: this.overlayStore.viewCoordinatesVisible,
            primaryText: this.viewCoordinatePrimaryText,
            secondaryText: this.viewCoordinateSecondaryText,
            overlayWidth: this.viewCoordinateOverlayWidth(),
            overlayLeft: this.viewCoordinateOverlayLeft(),
            overlayTop: this.viewCoordinateOverlayTop(),
            hintTop: (this.isExpandedLayout || this.isFoldHoverLayout) ? 16 : 58,
            actionHint: this.actionHint,
            onHandleViewCoordinateTouch: (event: TouchEvent) => { this.viewCoordinateCtl().handleViewCoordinateTouch(event) }
          })
        }
          .width('100%')
          .height('100%')
          .zIndex(3)
          .hitTestBehavior(HitTestMode.Default)
      }
      if (!this.scriptStore.scriptPlaybackVisible(this.guideStore.guideState.active) && this.tools.recording) {
        RecordingControlBar({
          store: this.tools, recordCount: this.scriptStore.recordCount, skyWidth: this.skyWidth, safeTop: this.scriptControlSafeTop(),
          onToggleUi: () => { this.scriptPlaybackCtl().toggleRecordingUi() },
          onTogglePause: () => { this.recordingCtl().toggleRecordingPause() },
          onStop: () => { this.recordingCtl().stopRecording() }
        })
      }
      if (!this.scriptStore.scriptPlaybackVisible(this.guideStore.guideState.active) && (!this.tools.recording || this.tools.recordingUiExpanded)) {
        if (this.polarScopeStore.polarScopeVisible) {
            PolarScopeOverlay({
              polarScopeStore: this.polarScopeStore,
              controlWidth: this.polarScopeControlWidth(),
            topInset: this.polarScopeTopInset(),
            footerHeight: this.polarScopeFooterHeight(),
            skyWidth: this.skyWidth,
            skyHeight: this.skyHeight,
            isExpandedLayout: this.isExpandedLayout,
            onSkyTouch: (event: TouchEvent) => { this.handleSkySurfaceTouch(event) },
            onSkyMouse: (event: MouseEvent) => { this.handleSkySurfaceMouse(event) },
            onSkyAxis: (event: AxisEvent) => { this.skyInputCtl().handleSkyAxis(event) },
            onRecenter: () => { this.polarScopeCtl().recenterPolarScope() },
            onClose: () => { this.polarScopeCtl().closePolarScope() },
            onHorizontalFlipChange: (value: boolean) => { this.polarScopeCtl().setPolarScopeHorizontalFlip(value) },
            onVerticalFlipChange: (value: boolean) => { this.polarScopeCtl().setPolarScopeVerticalFlip(value) }
          })
        }
        if (this.skyCultureViewStore.artPreviewOpen) {
            SkyCultureArtPreviewOverlay({
              skyCultureViewStore: this.skyCultureViewStore,
              topInset: this.mediaPreviewTopInset(),
            closeSkyCultureArtPreview: () => { this.skyCultureCtl().closeSkyCultureArtPreview() },
            onSkyCultureArtLoaded: () => { this.skyCultureCtl().onSkyCultureArtLoaded() },
            onSkyCultureArtError: () => { this.skyCultureCtl().onSkyCultureArtError() },
            onRetrySkyCultureArtPreview: () => { this.skyCultureCtl().retrySkyCultureArtPreview() }
          })
        }
        if (this.objectMediaStore.objectInspectorMediaFullscreen) {
            ObjectInspectorMediaPreviewOverlay({
              objectMediaStore: this.objectMediaStore,
              titleText: zhNameOf(this.objectDetailStore.selectedName),
            topInset: this.mediaPreviewTopInset(),
            closeObjectInspectorMediaPreview: () => { this.objectInspectorMediaCtl().closeObjectInspectorMediaPreview() },
            onObjectInspectorMediaPreviewLoaded: () => { this.objectInspectorMediaCtl().onObjectInspectorMediaPreviewLoaded() },
            onObjectInspectorMediaPreviewError: () => { this.objectInspectorMediaCtl().onObjectInspectorMediaPreviewError() },
            retryObjectInspectorMediaPreview: () => { this.objectInspectorMediaCtl().retryObjectInspectorMediaPreview() }
          })
        }
        if (this.objectMediaStore.objectInspectorModelImmersive) {
            ObjectInspectorModelOverlay({
              objectMediaStore: this.objectMediaStore,
              titleText: this.objectDetailStore.selectedName,
            noticeText: this.objectMediaStore.objectInspectorModelNotice(),
            topInset: this.mediaPreviewTopInset(),
            onCloseOverlay: () => { this.objectModelRendererCtl().setObjectInspectorModelImmersive(false) },
            onResetView: () => { this.objectModelRendererCtl().resetObjectInspectorModelView() },
            onStageTouch: (event: TouchEvent) => { this.objectModelRendererCtl().handleObjectInspectorModelTouch(event) }
          })
        }
      }

      if (this.tools.skyTextureStatusVisible) {
        Row({ space: 8 }) {
          if (!this.tools.skyTextureStatusError) {
            LoadingProgress().width(16).height(16).color(this.hostSlots().spinner)
          }
          Text(this.tools.skyTextureStatusText)
            .fontSize(11).fontColor(this.hostSlots().textStrong).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.tools.skyTextureStatusError) {
            Button('重试')
              .height(28).fontSize(10).fontColor(this.hostSlots().textStrong)
              .backgroundColor(this.hostSlots().overlayButton).borderRadius(UI_RADIUS_PILL)
              .onClick(() => { this.skyTextureStatusCtl().retrySkyTextureStatus() })
          }
        }
          .height(38).padding({ left: 12, right: 10 })
          .backgroundColor(this.tools.skyTextureStatusError ? this.hostSlots().errorBg : this.hostSlots().panelGlassStrong)
          .backdropBlur(18).borderRadius(UI_RADIUS_PILL)
          .position({ x: 16, y: (this.isExpandedLayout || this.isFoldHoverLayout) ? 58 : 98 })
          .constraintSize({ maxWidth: Math.max(220, this.skyWidth - 32) })
          .zIndex(92).hitTestBehavior(HitTestMode.Transparent)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

    }
      .width('100%')
      .height('100%')
      .backgroundColor(AstroColors.windowBase)
      .onKeyEvent((event: KeyEvent): boolean => this.handleSkyKeyboard(event, true))
      .onAreaChange((oldArea: Area, newArea: Area) => {
        // 布局硬回调：稳定触发。冷启动期 ArkUI setTimeout 重试不可靠，
        // 这里借 onAreaChange 反复尝试把启动命令送到 Qt 线程。
        this.startupBridge().startupBridgeSync()
        this.skyWidth = Number(newArea.width) > 1 ? Number(newArea.width) : 1
        this.skyHeight = Number(newArea.height) > 1 ? Number(newArea.height) : 1
        this.refreshFoldState('onAreaChange')
        this.updateResponsiveLayout('onAreaChange')
        if (this.polarScopeStore.polarScopeVisible) this.polarScopeCtl().syncNativePolarScopeOverlay(true)
        if (this.isFoldTabletLayout) {
          this.panelWidth = Math.min(Math.max(this.skyWidth * 0.42, 300), 340)
        } else if (this.isExpandedLayout) {
          // Pad and 2-in-1 windows share the same panel. Extra-wide PC
          // canvases can use a little more room without covering the sky.
          const expandedPanelMax = this.isLargeDesktopCanvas() ? 520 : (this.skyWidth >= 1440 ? 480 : 420)
          this.panelWidth = Math.min(Math.max(this.skyWidth * 0.33, 340), expandedPanelMax)
        } else {
          this.panelWidth = Math.min(Math.max(this.skyWidth * 0.28, 280), 400)
        }
        // 首次布局即发布一次面板状态，保证 getUiPanelState 在用户还没开关过面板时也有可读值。
        this.publishUiPanelState()
      })
    }
  }

  // 收起当前页面按钮：把右侧浮动面板收回到左侧栏
  // 「更多」按钮：与搜索、时间、位置和图层共用同一主面板。

  // 音乐开关按钮（左侧栏底部）：开着时音符亮起，静音时变暗

  // 陀螺仪按钮（平板左侧栏，与手机端 compactQuickButton 共用 ic_gyro.svg）

  // 平板/桌面浮动面板与手机底部面板：体内调用 this.panelContent()。
  // ArkUI 不能在子组件里调用宿主 @Builder（会整应用退出，，
  // 故二者是刻意的宿主薄 @Builder，不是遗漏（定论，复核仍然成立）。

  @Builder
  floatingPanel() {
    Column() {
      // 平板/展开布局也用顶部抓手：快捷面板自下而上展开，上拉显示更多按钮。
      PanelHandle({ onDrag: (offsetY: number) => { this.updateExpandedPanelDrag(offsetY) }, onDragFinish: () => { this.settleExpandedPanelDrag() } })
      PanelHeader({
        title: panelTitleFor(this.activePanel, this.configTab, this.isExpandedLayout, this.timeStore.timePanelClockText(), this.quickPanelLocationLabel()), subtitle: this.timeStore.panelSubtitle(this.activePanel), canGoBack: this.canGoBackPanel(),
        routeOpacity: this.panelRouteOpacity, routeOffsetX: this.panelRouteOffsetX,
        headerActionLabel: this.panelHeaderActionLabel(),
        headerActionIcon: this.panelHeaderActionIcon(),
        titleAsButton: this.activePanel === 'quick',
        onBack: () => { this.handlePanelBackTap() },
        onClose: () => { this.closePanel(true); this.resetPanelIdle() },
        onHeaderAction: () => { this.handlePanelHeaderAction() },
        onTitleTap: () => { this.openSubPanel('place') }
      })
      Scroll(this.widePanelScroller) {
        Column() {
          Column() {
            this.panelContent()
          }
            .width('100%')
            .opacity(this.panelRouteOpacity)
            .translate({ x: this.panelRouteOffsetX, y: 0 })
        }
          .width('100%')
      // Keep the route host stable. Changing its id on every navigation makes
      // ArkUI replace the node and bypass the explicit out/swap/in animation.
      .id('panel-content-' + this.i18nLang)
      }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .id('panel-scroll-' + this.i18nLang)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onAppear(() => { this.resetPanelScroll(this.widePanelScroller) })
    }
      .width(this.panelWidth)
      .height(this.activePanel === 'quick' ? this.quickPanelContentHeight() : this.expandedPanelHeight())
      .constraintSize({ maxHeight: this.activePanel === 'quick' ? this.quickPanelContentHeight() : this.expandedPanelHeight() })
      .padding({ top: 18, left: 18, right: 18, bottom: 18 })
      .backgroundColor(this.panelIdleGlass ? this.hostSlots().panelGlass : this.hostSlots().panelGlassStrong)
      .backdropBlur(this.panelIdleGlass ? 45 : 30)
      .border({ width: 0.5, color: this.hostSlots().border })
      .borderRadius(UI_RADIUS_SHEET)
      .shadow({ radius: 34, color: this.hostSlots().shadowSoft, offsetX: 0, offsetY: 18 })
      .onTouch((event: TouchEvent) => { this.notePanelTouch(event) })
      .scale({ x: this.panelIdleOpacity < 1 ? 0.97 : 1.0, y: this.panelIdleOpacity < 1 ? 0.97 : 1.0 })
      .opacity(this.panelIdleOpacity * this.panelPresentationOpacity)
      .translate({ y: this.panelPresentationOffsetY })
      .animation({ duration: 320, curve: curves.springMotion(0.46, 0.86) })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 260, curve: curves.springMotion(0.46, 0.86) })
          .combine(TransitionEffect.translate({ x: -22, y: 0 }).animation({ duration: 320, curve: curves.springMotion(0.46, 0.86) })),
        TransitionEffect.OPACITY.animation({ duration: 190, curve: Curve.EaseIn })
          .combine(TransitionEffect.translate({ x: -14, y: 0 }).animation({ duration: 220, curve: Curve.EaseIn }))
      ))
  }

  @Builder
  compactPanel() {
    Column() {
      PanelHandle({ onDrag: (offsetY: number) => { this.updateCompactPanelDrag(offsetY) }, onDragFinish: () => { this.settleCompactPanelDrag() } })
      PanelHeader({
        title: panelTitleFor(this.activePanel, this.configTab, this.isExpandedLayout, this.timeStore.timePanelClockText(), this.quickPanelLocationLabel()), subtitle: this.timeStore.panelSubtitle(this.activePanel), canGoBack: this.canGoBackPanel(),
        routeOpacity: this.panelRouteOpacity, routeOffsetX: this.panelRouteOffsetX,
        headerActionLabel: this.panelHeaderActionLabel(),
        headerActionIcon: this.panelHeaderActionIcon(),
        titleAsButton: this.activePanel === 'quick',
        onBack: () => { this.handlePanelBackTap() },
        onClose: () => { this.closePanel(true); this.resetPanelIdle() },
        onHeaderAction: () => { this.handlePanelHeaderAction() },
        onTitleTap: () => { this.openSubPanel('place') }
      })
      Scroll(this.compactPanelScroller) {
        Column() {
          Column() {
            this.panelContent()
          }
            .width('100%')
            .opacity(this.panelRouteOpacity)
            .translate({ x: this.panelRouteOffsetX, y: 0 })
        }
          .width('100%')
          .padding({ bottom: this.activePanel === 'quick' ? 0 : 34 })
          .id('panel-content-' + this.i18nLang)
      }
        .width('100%')
        .layoutWeight(1)
        .id('panel-scroll-' + this.i18nLang)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onAppear(() => { this.resetPanelScroll(this.compactPanelScroller) })
    }
      .width(this.isFoldHoverLayout ? '64%' : '94%')
      .height(this.compactPanelHeight())
      .padding({ top: 12, left: this.compactPanelHorizontalPadding(), right: this.compactPanelHorizontalPadding(), bottom: 16 })
      .backgroundColor(this.panelIdleGlass ? this.hostSlots().panelGlass : this.hostSlots().panelGlassStrong)
      .backdropBlur(this.panelIdleGlass ? 45 : 30)
      .border({ width: 0.5, color: this.hostSlots().border })
      .borderRadius(UI_RADIUS_SHEET)
      .shadow({ radius: 30, color: this.hostSlots().shadowSoft, offsetX: 0, offsetY: 14 })
      .margin({ bottom: 10 })
      .hitTestBehavior(HitTestMode.Default)
      .onTouch((event: TouchEvent) => { this.notePanelTouch(event) })
      .alignSelf(ItemAlign.Center)
      .scale({ x: this.panelIdleOpacity < 1 ? 0.98 : 1.0, y: this.panelIdleOpacity < 1 ? 0.98 : 1.0 })
      .opacity(this.panelIdleOpacity * this.panelPresentationOpacity)
      .translate({ y: this.panelPresentationOffsetY })
      .animation({ duration: 320, curve: curves.springMotion(0.46, 0.86) })
  }

  @Builder
  panelContent() {
    if (this.activePanel === 'more') {
      MorePanel({
        actions: moreActions(),
        languageRevision: this.languageStore.languageRevision,
        startsSection: (item: ShellAction, index: number) => this.moreActionStartsSection(item, index),
        onOpenPanel: (panel: string) => { this.openSubPanel(panel) }
      })
    } else if (this.activePanel === 'observeHub') {
      HubActionList({
        actions: observingHubActions(), description: I18n.t('more_workspace_observing_desc'),
        languageRevision: this.languageStore.languageRevision,
        onOpenPanel: (panel: string) => { this.openSubPanel(panel) }
      })
    } else if (this.activePanel === 'dataHub') {
      HubActionList({
        actions: skyDataHubActions(), description: I18n.t('more_sky_data_desc'),
        languageRevision: this.languageStore.languageRevision,
        onOpenPanel: (panel: string) => { this.openSubPanel(panel) }
      })
    } else if (this.activePanel === 'automationHub') {
      HubActionList({
        actions: automationHubActions(), description: I18n.t('more_automation_desc'),
        languageRevision: this.languageStore.languageRevision,
        onOpenPanel: (panel: string) => { this.openSubPanel(panel) }
      })
    } else if (this.activePanel === 'object') {
      ObjectPanel({
        objectDetailStore: this.objectDetailStore,
        objectMediaStore: this.objectMediaStore,
        telescopeStore: this.telescopeStore,
        fullInspectorRequested: this.fullInspectorRequested,
        viewLock: this.viewSettingsStore.viewLock,
        speechStatus: this.guideStore.speechStatus,
        observingListStore: this.obsListStore,
        isPlannedModel: this.objectDetailStore.selectedDetailModel !== undefined && this.objectDetailStore.selectedDetailModel.state === 'planned',
        imageHeight: this.objectMediaStore.objectInspectorImageHeight(),
        iconName: this.objectDetailStore.objectInspectorIcon(),
        inlineModelSize: this.objectInspectorInlineModelSize(),
        modelReady: this.objectModelRendererCtl().modelReady(),
        modelRendering: this.objectModelRendererCtl().isRendering(),
        hasModelTexture: this.objectModelRendererCtl().hasTexture(),
        modelNotice: this.objectMediaStore.objectInspectorModelNotice(),
        warmupText: this.objectMediaStore.objectInspectorMediaWarmupText(),
        fallbackKind: objectInspectorFallbackVisualKind(this.objectDetailStore.selectedObjectType, this.objectDetailStore.selectedType),
        satVisible: this.objectDetailStore.selectedObjectIsArtificialSatellite(),
        tleEpoch: this.objectDetailStore.selectedSatelliteTleEpoch(),
        nameOf: (raw: string) => zhNameOf(raw),
        typeOf: (type: string) => zhType(type),
        statusOf: (en: string) => this.selectedStatusZh(en),
        displayValue: (key: string) => this.selectedDisplayValue(key),
        onChip: (id: string) => { this.timeCtl().handleChip(id) },
        onToggleObserving: () => {
          if (this.obsListStore.observingList.includes(this.objectDetailStore.selectedName)) {
            this.obsListStore.observingList = this.obsListStore.observingList.filter((item: string) => item !== this.objectDetailStore.selectedName)
            this.flashHint(I18n.t('i0079'))
          } else {
            this.obsListStore.observingList = this.obsListStore.observingList.concat([this.objectDetailStore.selectedName])
            this.flashHint(I18n.t('i0080'))
          }
          this.obsListStore.persistObservingList()
        },
        onGotoReselect: () => { this.triggerAction('actionGoto_ReSelect_Last_Selected_Object') },
        onSpeak: () => { speakSelectedObject(this.commandPort(), { flashHint: (text: ResourceStr): void => this.flashHint(text), setSpeechStatus: (text: string): void => { this.guideStore.speechStatus = text } }) },
        onOpenMedia: () => { this.objectInspectorMediaCtl().openObjectInspectorMediaPreview() },
        onRetryMedia: () => { this.objectInspectorMediaCtl().retryObjectInspectorMedia() },
        onModelExpand: () => { this.objectModelRendererCtl().setObjectInspectorModelImmersive(true) },
        onModelTouch: (event: TouchEvent) => { this.objectModelRendererCtl().handleObjectInspectorModelTouch(event) },
        onLoadSatPasses: () => { this.objectDetailStore.loadSelectedSatellitePasses() },
        onGoto: () => { this.telescopeCtl().lx200GotoSelected() },
        onSync: () => { this.telescopeCtl().lx200SyncSelected() },
        onAbort: () => { this.telescopeCtl().lx200Abort() }
      })
    } else if (this.activePanel === 'time') {
      // 不经参数传递，变化可正常触发重建）；面板首屏直接给时间转轴与时间控制按钮
      // Sky Guide 风格时间拖动滑块（-365天 ~ +365天）：置于面板最前，手机端打开即可直接拖动
      TimePanel({
        timeWheelStore: this.timeWheelStore,
        timeStore: this.timeStore,
        equationOfTimeStore: this.equationOfTimeStore,
        julianStore: this.julianStore,
        nightModeStore: this.nightModeStore,
        manualYear: this.timeStore.manualYear,
        manualMonth: this.timeStore.manualMonth,
        manualDay: this.timeStore.manualDay,
        manualHour: this.timeStore.manualHour,
        manualMinute: this.timeStore.manualMinute,
        onSelectUnit: (unit: string) => { this.wheel().selectUnit(unit) },
        onWheelTouch: (event: TouchEvent) => { this.wheel().handleTouch(event) },
        onChip: (id: string) => { this.timeCtl().handleChip(id) },
        onEquationToggle: (setting: string, enabled: boolean) => { this.ocularCtl().setEquationOfTime(setting, enabled) },
        onAdjustJulian: (scale: string, direction: number) => { this.julianStore.adjustJulianDate(scale, direction) },
        onApplyJulian: (scale: string) => { this.julianStore.applyJulianDateInput(scale) },
        onNightMode: (enabled: boolean) => { this.nightModeStore.applyNightMode(enabled, true) },
        onPickDate: (year: number, monthIndex: number, day: number) => {
          this.timeStore.manualYear = year; this.timeStore.manualMonth = monthIndex + 1; this.timeStore.manualDay = day
        },
        onPickTime: (hour: number, minute: number) => { this.timeStore.manualHour = hour; this.timeStore.manualMinute = minute },
        onApplyManual: () => { this.timeCtl().applyManualTime() },
        onResetManual: () => { this.timeCtl().syncManualTimeFromState(); this.flashHint(I18n.t('i0081')) },
        onSpeedBlockHeight: (height: number) => {
          if (Math.abs(height - this.timeSpeedBlockHeight) > 0.5) this.timeSpeedBlockHeight = height
        }
      })
    } else if (this.activePanel === 'place') {
      PlacePanel({
        locationPickerStore: this.locationPickerStore,
        locationStore: this.locationStore,
        sessionToolStore: this.sessionToolStore,
        locationText: this.locationText,
        coordinateText: this.coordinateText,
        altitudeText: this.altitudeText,
        expandedLayout: this.isExpandedLayout,
        skyWidth: this.skyWidth,
        mapAllowed: this.privacyNativeStartupAllowed && this.applicationInForeground && hasCurrentPrivacyConsent(),
        planetLabel: (en: string) => planetZh(en),
        contextOf: (item: LocSearchItem) => this.locationPickerStore.locationResultContext(item, this.sessionToolStore.observerPlanet),
        onUseDeviceLocation: () => { this.locationCtl().useDeviceLocation() },
        onSearchLocations: (query: string) => { this.locationStore.searchLocations(query) },
        onInputFocus: () => { this.keyboardTextInputFocused = true },
        onInputBlur: () => { this.keyboardTextInputFocused = false },
        onPickSearchItem: (item: LocSearchItem) => { this.locationStore.selectSearchLocation(item) },
        onApply: () => { this.locationCtl().applyPickerLocation() },
        onSelectMapProvider: (provider: string) => { this.locationCtl().setLocationMapProvider(provider) },
        onPickMap: (latitude: number, longitude: number) => { this.locationPickerStore.applyPickedCoordinates(latitude, longitude) },
        onMapFallback: () => { this.locationCtl().setLocationMapProvider('offline') },
        onSelectContinent: (c: string) => { this.locationCtl().selectContinent(c) },
        onSelectCountry: (c: string) => { this.locationCtl().selectCountry(c) },
        onSelectRegion: (r: string) => { this.locationCtl().selectRegion(r) },
        onSelectCity: (c: string) => { this.locationCtl().selectCityByName(c) },
        onSaveCurrent: () => { this.locationStore.saveCurrentLocation() },
        onApplyLocation: (name: string, lat: number, lon: number, alt: number, planet: string) => { this.locationCtl().setLocation(name, lat, lon, alt, planet) },
        onDeleteLocation: (name: string) => { this.locationStore.deleteSavedLocation(name) },
        onChip: (id: string) => { this.timeCtl().handleChip(id) },
        onSelectPlanet: (name: string) => { this.locationCtl().setObserverPlanet(name) },
        onPoint: () => { this.pointAtSkyTest() },
        onSend: () => { this.gyroCtl().watchGyroSend() },
        onStart: () => { this.gyroCtl().watchGyroStart() },
        onStop: () => { this.gyroCtl().watchGyroStop() },
        onExport: () => { this.sessionToolStore.sessionExport() },
        onSessionApply: () => { this.sessionToolStore.sessionApply() },
        onHandoff: () => { this.sessionToolStore.sessionHandoff() },
        onRefreshTonight: () => { this.sessionToolStore.refreshTonight() },
        onJump: (jd: number, lock: string, title: string) => { this.gotoTonightEvent(jd, lock, title) }
      })
    } else if (this.activePanel === 'layers') {
      LayersPanel({
        layerStore: this.layerStore,
        layerViewStore: this.layerViewStore,
        skyCultureViewStore: this.skyCultureViewStore,
        skyCultureSettingsStore: this.skyCultureSettingsStore,
        atmosphereStore: this.atmosphereStore,
        overlayStore: this.overlayStore,
        surveyStore: this.surveyStore,
        nightModeOn: this.nightModeStore.nightMode,
        viewTab: this.viewTab,
        expandedLayout: this.isExpandedLayout,
        foldTablet: this.isFoldTabletLayout,
        viewTabContentOpacity: this.viewTabContentOpacity,
        viewTabContentOffsetX: this.viewTabContentOffsetX,
        layerTabs: this.layerCtl().layerTabItems(),
        skyCultureArtStates: this.skyCultureArtStates,
        narrationParagraphs: this.skyCultureViewStore.skyCultureNarrationParagraphs(),
        mapContext: this.skyCultureMapContext,
        onPreset: (preset: string) => { this.layerCtl().applyLayerPreset(preset) },
        onSelectTab: (id: number) => { this.switchViewTab(id) },
        onToggleLayer: (actionId: string, cmd: string, value: boolean) => { this.layerCtl().applyLayerSwitch(actionId, cmd, value) },
        onRefreshSurvey: () => { this.surveyCtl().loadSurveyState() },
        onSelectSpectral: (id: string) => { this.surveyCtl().setSpectralDataset(id) },
        onCloseSpectral: () => { this.surveyCtl().closeSpectralView() },
        onSetSkyDisplay: (setting: string, value: boolean | number) => { this.layerCtl().setSkyDisplaySetting(setting, value) },
        onStarMagLimit: (value: number) => { this.layerCtl().applyStarMagLimit(value) },
        onMilkyWayBright: (value: number) => { this.layerCtl().applyMilkyWayBright(value) },
        onAtmosphere: (pressure: number, temperature: number, extinction: number) => { this.astroCalcCtl().applyAtmosphere(pressure, temperature, extinction) },
        onSetOrbitFlag: (setting: string, enabled: boolean) => { this.layerCtl().setOrbitDisplayFlag(setting, enabled) },
        onSetOrbitThickness: (value: number) => { this.layerCtl().setOrbitDisplayThickness(value) },
        onSetOrbitColorStyle: (index: number) => { this.layerCtl().setOrbitColorStyle(index) },
        onLoadOrbitSettings: () => { this.layerViewStore.loadOrbitDisplaySettings() },
        onSetTrailFlag: (setting: string, enabled: boolean) => { this.layerCtl().setTrailDisplayFlag(setting, enabled) },
        onSetTrailNumber: (setting: string, value: number) => { this.layerCtl().setTrailDisplayNumber(setting, value) },
        onLoadTrailSettings: () => { this.layerViewStore.loadTrailDisplaySettings() },
        onApplyTrailColor: () => { this.layerCtl().applyTrailColor() },
        onTriggerAction: (actionId: string) => { this.triggerAction(actionId) },
        onSetFovMarker: (setting: string, value: number) => { this.viewSettingsStore.setFovMarkerSetting(setting, value) },
        onToggleViewCoordinates: (visible: boolean) => { this.viewCoordinateCtl().setViewCoordinatesVisible(visible) },
        onSelectViewCoordinateFamily: (family: string) => { this.viewCoordinateCtl().setViewCoordinateFamily(family) },
        onSelectViewEquatorialEpoch: (epoch: string) => { this.viewCoordinateCtl().setViewEquatorialEpoch(epoch) },
        onSetLandscapeFadeWithZoom: (isOn: boolean) => { this.layerCtl().setLandscapeFadeWithZoom(isOn) },
        onImportLandscape: () => { this.layerCtl().importLandscapeFile() },
        onSelectLandscape: (id: string, name: string) => { this.layerCtl().selectLandscape(id, name) },
        onChangeLandscapeTransparency: (val: number) => { this.layerCtl().changeLandscapeTransparency(val) },
        onLoadList: () => { this.skyCultureViewStore.loadSkyCultureList() },
        onSelectCulture: (id: string) => { this.skyCultureCtl().selectSkyCulture(id) },
        onRowArea: (id: string, area: Area) => { this.skyCultureCtl().handleSkyCultureRowArea(id, area) },
        onReloadList: () => { this.callInteractive('reloadSkyCulture', '', () => { this.skyCultureViewStore.loadSkyCultureList() }) },
        onSelectLabelMode: (target: string, index: number) => { this.skyCultureCtl().selectSkyCultureLabelMode(target, index) },
        onSetShortLabels: (enabled: boolean) => { this.skyCultureCtl().setSkyCultureShortLabels(enabled) },
        onSetCommonNames: (enabled: boolean) => { this.skyCultureCtl().setSkyCultureCommonNames(enabled) },
        onSetIsolation: (enabled: boolean) => { this.skyCultureCtl().setSkyCultureConstellationIsolation(enabled) },
        onSetSinglePick: (enabled: boolean) => { this.skyCultureCtl().setSkyCultureConstellationSinglePick(enabled) },
        onConstellationSelection: (actionId: string, hint: string) => { this.skyCultureCtl().applySkyCultureConstellationSelection(actionId, hint) },
        onSetStyleOption: (target: string, optionIndex: number, enabled: boolean) => { this.skyCultureCtl().setSkyCultureStyleOption(target, optionIndex, enabled) },
        getColorOptions: () => this.skyCultureColorOptions(),
        onSetVisualColor: (setting: string, color: string) => { this.skyCultureCtl().setSkyCultureVisualColor(setting, color) },
        onSetVisualSetting: (setting: string, value: number) => { this.skyCultureCtl().setSkyCultureVisualSetting(setting, value) },
        onSetDefault: () => { this.skyCultureCtl().setCurrentSkyCultureAsDefault() },
        onSyncTimeFollowTimer: () => { this.skyCultureCtl().syncSkyCultureTimeFollowTimer() },
        onRefreshSimulationYear: () => { this.skyCultureCtl().refreshSkyCultureSimulationYear(true) },
        onLoadTerritoryMap: () => { this.skyCultureSettingsStore.loadSkyCultureTerritoryMap() },
        onMapReady: () => { this.drawSkyCultureTerritoryMap() },
        onMapAreaChange: (width: number, height: number) => { this.skyCultureMapRenderWidth = width; this.skyCultureMapRenderHeight = height; this.drawSkyCultureTerritoryMap() },
        onLoadObserverInfo: (force: boolean) => { this.locationPickerStore.loadObserverInfo(force) },
        onArtDecodeError: (rawPath: string) => { this.skyCultureCtl().setSkyCultureArtStatus(rawPath, 'decodeFailed') },
        onOpenArtPreview: (art: SkyCultureArtItem) => { this.skyCultureCtl().openSkyCultureArtPreview(art) }
      })
    } else if (this.activePanel === 'quick') {
      QuickPanel({
        store: this.quickPanelStore,
        nightModeStore: this.nightModeStore,
        values: this.quickActionValues(),
        onToggle: (id: string, value: boolean) => { this.quickToggle(id, value) },
        onHint: (text: string) => { this.flashHint(text) }
      })
    } else if (this.activePanel === 'pointerCoordinates') {
      PointerCoordinatesPanel({
        store: this.overlayStore,
        onSetSetting: (setting: string, value: string) => { this.viewCoordinateCtl().setPointerCoordinates(setting, value) }
      })
    } else if (this.activePanel === 'commands') {
      CommandsPanel({
        commandStore: this.commandStore,
        onSearchTextChange: (value: string) => { this.commandStore.commandSearchText = value },
        onNameInputChange: (value: string) => { this.commandStore.commandNameInput = value; this.commandStore.commandPendingConfirmation = '' },
        onPayloadInputChange: (value: string) => { this.commandStore.commandPayloadInput = value },
        onSelectEntry: (item: CommandCatalogEntry) => { this.selectCommandEntry(item) },
        onRefreshCatalog: () => { this.commandStore.loadCommandCatalog() },
        onExecute: (force: boolean) => { this.executeCommandFromPanel(force) }
      })
    } else if (this.activePanel === 'settings_quick_legacy') {
      SettingsQuickLegacyPanel({
        gyroStore: this.gyroStore,
        nightModeStore: this.nightModeStore,
        telescopeStore: this.telescopeStore,
        viewSettingsStore: this.viewSettingsStore,
        liveMode: this.viewSettingsStore.liveMode,
        fovSliderValue: this.fovSliderValue,
        currentProjection: this.currentProjection,
        selectedLanguage: this.languageStore.selectedLanguage,
        skyCultureViewStore: this.skyCultureViewStore,
        satelliteCatalogHealth: this.satelliteStore.satelliteCatalogHealth,
        starCatalogHealth: this.catalogStore.starCatalogHealth,
        gyroSensitivityText: sensZh(this.gyroStore.gyroscopeSensitivityText),
        onToggleGyroscope: (v: boolean) => { this.gyroCtl().toggleGyroscope(v); this.flashHint(v ? I18n.t('s0719') : I18n.t('s0720')) },
        onRevoke: () => { this.confirmPrivacyRevocation() },
        onApplyLayerSwitch: (actionId: string, cmd: string, value: boolean) => { this.layerCtl().applyLayerSwitch(actionId, cmd, value) },
        onSpeedDown: () => { this.timeCtl().speedDown() },
        onTogglePause: () => { this.timeCtl().togglePause() },
        onSpeedUp: () => { this.timeCtl().speedUp() },
        onFovChange: (val: number) => { this.fovSliderValue = Math.round(val); this.changeFovBySlider(val) },
        onSetProjection: (name: string) => { this.viewSettingsStore.setProjection(name) },
        onSetLanguage: (lang: string) => { this.setLanguage(lang) },
        onSetSkyCulture: (name: string) => { this.skyCultureCtl().setSkyCulture(name) },
        onSetUnits: (metric: boolean) => { this.viewSettingsStore.useMetricUnits = metric; this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=' + metric, () => {}) },
        catalogHealthTextOf: (title: string, health: CatalogHealthEntry) => this.catalogHealthText(title, health),
        catalogHealthColorOf: (health: CatalogHealthEntry) => this.catalogHealthColor(health)
      })
    } else if (this.activePanel === 'search') {
      SearchPanel({
        store: this.searchStore,
        languageRevision: this.languageStore.languageRevision,
        visibilityLabel: this.searchStore.searchVisibilityLabel(),
        instrumentLabel: this.searchStore.searchInstrumentLabel(),
        categories: this.catalogStore.searchAllCategoryOptions(),
        categoryIconKey: this.catalogStore.searchCategoryIcon(this.searchStore.searchCategory),
        categoryLabel: this.catalogStore.searchCategoryLabel(this.searchStore.searchCategory),
        scroller: this.searchPanelScroller,
        onInput: (value: string) => { this.searchCtl().scheduleSuggestions(value.trim()) },
        onSubmit: (text: string) => {
          this.searchCtl().stop()
          this.searchObject(text)
          this.searchStore.searchSuggestions = []
        },
        onInputFocus: () => {
          // 聚焦搜索框时，天空键盘处理器让位给输入法。
          this.keyboardTextInputFocused = true
          // 手机上把候选结果留在软键盘之上；用户仍可把面板拖回 6/10 吸附点。
          if (!this.isExpandedLayout && !this.isFoldHoverLayout && this.compactPanelSnapRatio < 0.9) {
            this.getUIContext().animateTo({ duration: 260, curve: curves.springMotion(0.48, 0.90) }, () => {
              this.compactPanelSnapRatio = 0.9
              this.compactPanelDragOffsetY = 0
            })
            this.scheduleSelectedObjectForUiChange(300)
          }
        },
        onInputBlur: () => { this.keyboardTextInputFocused = false },
        onSetPage: (page: string) => { this.searchCtl().setSearchFilterPage(page) },
        onSelectCategory: (code: string) => { this.searchCtl().selectSearchFilterCategory(code) },
        onSelectVisibility: (filter: string) => { this.searchCtl().selectSearchVisibilityFilter(filter) },
        onSelectInstrument: (filter: string) => { this.searchCtl().selectSearchInstrumentFilter(filter) },
        suggestionSubtitle: (title: string, englishName: string) => { return this.searchStore.celestialSubtitle(title, englishName) },
        onSelectSuggestion: (item: SearchSug) => { this.searchCtl().selectSearchSuggestion(item) },
        iconFor: (item: NameItem) => { return this.catalogStore.categoryObjectIcon(item, this.searchStore.searchCategory) },
        categorySubtitle: (item: NameItem) => { return this.searchStore.categoryObservationSubtitle(item) },
        onOpenCategories: () => { this.searchCtl().setSearchFilterPage('categories') },
        onOpenFilters: () => { this.searchCtl().setSearchFilterPage('root') },
        onRetry: () => { this.searchStore.loadCategoryObjects(this.searchStore.searchCategory) },
        onLoadMore: () => { this.searchStore.loadMoreCategoryObjects() },
        onSelectCategoryObject: (item: NameItem) => {
          if (this.searchStore.searchCategory === 'constellation') {
            this.openConstellationGuide(item.name ?? '', this.searchStore.categoryModuleId)
          } else {
            this.searchObject(item.name ?? '', this.searchStore.categoryModuleId)
          }
        },
        onClearVisibility: () => { this.searchCtl().selectSearchVisibilityFilter('all') },
        onClearInstrument: () => { this.searchCtl().selectSearchInstrumentFilter('all') },
        onOpenConstellation: (item: ConstellationNavigationItem) => { this.openConstellationGuide(item.englishName, 'ConstellationMgr', item.localizedName) },
        onGoCoordinates: () => { this.goToCoordinates() }
      })
    } else if (this.activePanel === 'settings') {
      SettingsPanel({
        gyroStore: this.gyroStore,
        overlayStore: this.overlayStore,
        deltaTStore: this.deltaTStore,
        timeSettingsStore: this.timeSettingsStore,
        ephemerisStore: this.ephemerisStore,
        navigationStore: this.navigationStore,
        viewSettingsStore: this.viewSettingsStore,
        notificationStore: this.notificationStore,
        keyboardShortcutStore: this.keyboardShortcutStore,
        scroller: this.scriptListScroller,
        configTab: this.configTab,
        configTabContentOpacity: this.configTabContentOpacity,
        configTabContentOffsetX: this.configTabContentOffsetX,
        i18nLang: this.i18nLang,
        selectedLanguage: this.languageStore.selectedLanguage,
        isExpandedLayout: this.isExpandedLayout,
        informationMode: this.infoWindowStore.informationMode,
        informationSettingPending: this.infoWindowStore.informationSettingPending,
        observeMode: this.infoWindowStore.observeModeEnabled(),
        onToggleObserveMode: (enabled: boolean) => { this.applyObserveMode(enabled) },
        currentProjection: this.currentProjection,
        configDitheringMode: this.viewSettingsStore.configDitheringMode,
        timeSettingsPending: this.timeSettingsPending,
        observationTimeText: this.timeStore.observationTimeText,
        scriptLaunching: this.scriptStore.scriptLaunching,
        scriptLaunchingName: this.scriptStore.scriptLaunchingName,
        scriptList: this.scriptStore.scriptList,
        pluginStore: this.pluginStore,
        fovText: this.fovText,
        informationMaskHas: (key: string) => { return this.infoWindowStore.informationMaskHas(key) },
        pluginMetaLine: (plugin: PluginItem) => { return this.pluginFeatureCtl().pluginMetaLine(plugin) },
        pluginFeatureDestination: (id: string) => { return this.pluginFeatureCtl().pluginFeatureDestination(id) },
        pluginFeatureIsActionable: (id: string) => { return this.pluginFeatureCtl().pluginFeatureIsActionable(id) },
        pluginFeatureActionLabel: (id: string) => { return this.pluginFeatureCtl().pluginFeatureActionLabel(id) },
        scriptMetaLine: (filename: string) => { return this.scriptStore.scriptMetaLine(filename) },
        scriptSourceLine: (filename: string) => { return this.scriptStore.scriptSourceLine(filename) },
        hasSelectedObject: () => { return this.objectDetailStore.hasSelectedObject() },
        selectConfigTab: (tabId: number) => { this.switchConfigTab(tabId) },
        setLanguage: (lang: string) => { this.setLanguage(lang) },
        setEphemerisEnabled: (key: string, available: boolean, enabled: boolean) => { this.ephemerisStore.setEphemerisEnabled(key, available, enabled) },
        setDistanceUnit: (useMetric: boolean) => { this.viewSettingsStore.setDistanceUnit(useMetric) },
        setConfigurationDithering: (value: string) => { this.viewSettingsStore.setConfigurationDithering(value) },
        setProjection: (name: string) => { this.viewSettingsStore.setProjection(name) },
        saveAppSettings: () => { this.saveAppSettings() },
        flashHint: (text: ResourceStr) => { this.flashHint(text) },
        saveAllCoreSettings: () => { this.tools.saveAllCoreSettings() },
        restoreCoreDefaults: () => { this.tools.restoreCoreDefaults() },
        saveCurrentViewAsStartup: () => { this.startupBridge().saveCurrentViewAsStartup() },
        setViewLockState: (enabled: boolean) => { this.layerCtl().setViewLockState(enabled) },
        setNavigationBoolean: (setting: string, enabled: boolean) => { this.navigationStore.setNavigationBoolean(setting, enabled) },
        setNavigationMaxFov: (value: number) => { this.navigationStore.setNavigationMaxFov(value) },
        selectSettingsChoice: (group: string, value: string) => { this.selectSettingsChoice(group, value) },
        setStartupTimeSetting: (key: string, value: string) => { this.timeCtl().setStartupTimeSetting(key, value) },
        setInformationField: (key: string, enabled: boolean) => { this.infoWindowStore.setInformationField(key, enabled) },
        setObjectDetailConnector: (enabled: boolean) => { this.setObjectDetailConnector(enabled) },
        toggleGyroscope: (enabled: boolean) => { this.gyroCtl().toggleGyroscope(enabled) },
        confirmPrivacyRevocation: () => { this.confirmPrivacyRevocation() },
        requestNotificationAccess: () => { this.notificationCtl().requestAccess() },
        scheduleNextSolarTermReminder: () => { this.notificationCtl().scheduleNextSolarTerm() },
        clearAstronomyReminders: () => { this.notificationCtl().clearReminders() },
        keyboardShortcutQueryChange: (value: string) => { this.keyboardShortcutStore.keyboardShortcutQuery = value; this.keyboardShortcutCtl().load() },
        keyboardShortcutSelectChange: (item: KeyboardShortcutItem) => { this.keyboardShortcutCtl().select(item) },
        keyboardShortcutPrimaryChange: (value: string) => { this.keyboardShortcutStore.keyboardShortcutPrimary = value },
        keyboardShortcutAlternateChange: (value: string) => { this.keyboardShortcutStore.keyboardShortcutAlternate = value },
        keyboardShortcutSaveChange: () => { this.keyboardShortcutCtl().save() },
        keyboardShortcutResetSelectedChange: () => { this.keyboardShortcutCtl().resetSelected() },
        keyboardShortcutResetAllChange: () => { this.keyboardShortcutCtl().resetAll() },
        loadPluginList: () => { this.pluginStore.loadPluginList() },
        openPluginFeature: (id: string) => { this.pluginFeatureCtl().openPluginFeature(id) },
        playScriptByName: (filename: string) => { this.scriptPlaybackCtl().playScriptByName(filename) },
        triggerAction: (actionId: string) => { this.triggerAction(actionId) },
        moveToSelectedObject: () => { this.moveToSelectedObject() },
        onOpenLayersSky: () => { this.viewTab = 0; this.openSubPanel('layers') },
        onOpenTools: () => { this.openSubPanel('tools') }
      })
    } else if (this.activePanel === 'astro') {
      AstroPanel({
        store: this.astroStore,
        wutStore: this.wutStore,
        objectDetailStore: this.objectDetailStore,
        scroller: this.astroPanelScroller,
        host: {
          almanacHoursLabel: (key: string) => this.astroStore.almanacHoursLabel(key),
          altAzMaxLabel: () => this.astroStore.altAzMaxLabel(),
          altAzMidpointLabel: () => this.astroStore.altAzMidpointLabel(),
          altAzNowLabel: () => this.astroStore.altAzNowLabel(),
          altAzRangeLabel: () => this.astroStore.altAzRangeLabel(),
          altAzVisibleHours: () => this.astroStore.altAzVisibleHours(),
          altBarHeight: (alt: number | undefined) => this.astroStore.altBarHeight(alt),
          altBarWidth: () => this.astroStore.altBarWidth(),
          altCurveSegmentWidth: () => this.astroStore.altCurveSegmentWidth(),
          altitudeCurveColor: (altitude: number | undefined, color: ResourceColor) => this.astroStore.altitudeCurveColor(altitude, color),
          annualBarHeight: (altitude: number | undefined) => this.astroStore.annualBarHeight(altitude),
          annualBarWidth: () => this.astroStore.annualBarWidth(),
          annualMaxLabel: () => this.astroStore.annualMaxLabel(),
          astroNeedsSelectedObject: () => this.astroStore.astroNeedsSelectedObject(),
          azimuthNowLabel: () => this.astroStore.azimuthNowLabel(),
          callNative: (name: string, payload?: string) => { this.callNative(name, payload) },
          celestialPositionSubtitle: (position: CelestialPosition) => this.celestialPositionSubtitle(position),
          celestialPositionTitle: (position: CelestialPosition) => celestialTitle(position.name, position.englishName),
          chooseEclipseStartDate: () => { this.astroCalcCtl().chooseEclipseStartDate() },
          chooseEphemerisStartDate: () => { this.astroCalcCtl().chooseEphemerisStartDate() },
          chooseGraphStartDate: () => { this.astroCalcCtl().chooseGraphStartDate() },
          chooseRtsCalendarStartDate: () => { this.astroCalcCtl().chooseRtsCalendarStartDate() },
          eclipseStartOptionLabel: (offsetDays: number) => this.astroStore.eclipseStartOptionLabel(offsetDays),
          ephemerisStartOptionLabel: (offsetDays: number) => this.ephemerisStore.ephemerisStartOptionLabel(offsetDays),
          exportCurrentAstroCsv: () => this.astroCalcCtl().exportCurrentAstroCsv(),
          filteredEclipses: () => this.astroStore.filteredEclipses(),
          fmtClock: (s: string | undefined) => this.astroCalcCtl().fmtClock(s),
          fmtDateTime: (s: string | undefined) => this.astroCalcCtl().fmtDateTime(s),
          fmtEphemerisDate: (s: string | undefined) => this.astroCalcCtl().fmtEphemerisDate(s),
          fmtNum: (v: number | undefined, digits: number, suffix: string) => this.astroCalcCtl().fmtNum(v, digits, suffix),
          graphCustomStartLabel: () => this.astroStore.graphCustomStartLabel(),
          graphTargetLabel: () => this.astroStore.graphTargetLabel(),
          hasSelectedObject: () => this.objectDetailStore.hasSelectedObject(),
          hecPointColor: (position: HeliocentricPosition) => hecPointColor(position, accentForNightMode(this.nightModeStore.nightMode)),
          hecPointLeft: (position: HeliocentricPosition) => hecPointLeft(position),
          hecPointTop: (position: HeliocentricPosition) => hecPointTop(position),
          hecTitle: (position: HeliocentricPosition) => celestialTitle(position.name, position.englishName),
          jdToDateStr: (jd: string) => this.jdToDateStr(jd),
          jumpToAlmanacSeason: (event: SeasonEvent) => { this.astroCalcCtl().jumpToAlmanacSeason(event) },
          jumpToEphemerisRow: (row: EphemerisRow) => { this.astroCalcCtl().jumpToEphemerisRow(row) },
          jumpToMoonPhase: (item: MoonPhaseItem) => { this.astroCalcCtl().jumpToMoonPhase(item) },
          jumpToObservabilityDay: (day: ObservabilityDay) => { this.astroCalcCtl().jumpToObservabilityDay(day) },
          jumpToPhenomenon: (item: PhenomenonItem) => { this.astroCalcCtl().jumpToPhenomenon(item) },
          jumpToRts: (key: string) => { this.astroCalcCtl().jumpToRts(key) },
          jumpToRtsCalendar: (day: RtsCalendarDay) => { this.astroCalcCtl().jumpToRtsCalendar(day) },
          jumpToWutTarget: (target: WutTarget) => { this.astroCalcCtl().jumpToWutTarget(target) },
          loadAlmanac: () => { this.astroCalcCtl().loadAlmanac() },
          loadAltAzCurve: () => { this.astroCalcCtl().loadAltAzCurve() },
          loadAnnualElevation: () => { this.astroCalcCtl().loadAnnualElevation() },
          loadCelestialPositions: () => { this.astroCalcCtl().loadCelestialPositions() },
          loadEclipses: () => { this.astroCalcCtl().loadEclipses() },
          loadEphemeris: () => { this.astroCalcCtl().loadEphemeris() },
          loadHeliocentricPositions: () => { this.astroCalcCtl().loadHeliocentricPositions() },
          loadLunarElongation: () => { this.astroCalcCtl().loadLunarElongation() },
          loadMoonPhases: () => { this.astroCalcCtl().loadMoonPhases() },
          loadObservabilityCalendar: () => { this.astroCalcCtl().loadObservabilityCalendar() },
          loadPhenomena: () => { this.astroCalcCtl().loadPhenomena() },
          loadPlanetCalc: () => { this.astroCalcCtl().loadPlanetCalc() },
          loadPlanetPairDistance: () => { this.astroCalcCtl().loadPlanetPairDistance() },
          loadPlanetPositions: () => { this.astroCalcCtl().loadPlanetPositions() },
          loadPlanetTimeSeries: () => { this.astroCalcCtl().loadPlanetTimeSeries() },
          loadPlanetaryTransits: () => { this.astroCalcCtl().loadPlanetaryTransits() },
          loadRTS: () => { this.astroCalcCtl().loadRTS() },
          loadRtsCalendar: () => { this.astroCalcCtl().loadRtsCalendar() },
          loadTonightAstro: () => { this.astroCalcCtl().loadTonightAstro() },
          loadWutTargets: () => { this.wutStore.loadWutTargets() },
          lunarElongationBarWidth: () => this.astroStore.lunarElongationBarWidth(),
          lunarElongationClosestLabel: () => this.astroStore.lunarElongationClosestLabel(),
          lunarElongationLineTop: () => this.astroStore.lunarElongationLineTop(),
          lunarElongationNowLabel: () => this.astroStore.lunarElongationNowLabel(),
          markRtsCalendarForRegeneration: () => { this.astroCalcCtl().markRtsCalendarForRegeneration() },
          openAstroTargetPicker: () => { this.astroCalcCtl().openAstroTargetPicker() },
          openEphemerisTargetPicker: () => { this.astroCalcCtl().openEphemerisTargetPicker() },
          openGraphTargetPicker: () => { this.astroCalcCtl().openGraphTargetPicker() },
          openRtsTargetPicker: () => { this.astroCalcCtl().openRtsTargetPicker() },
          phenomenaBodyName: (body: string) => this.astroStore.phenomenaBodyName(body),
          planetPairBarWidth: () => this.astroStore.planetPairBarWidth(),
          planetPairCurrentIndex: () => this.astroStore.planetPairCurrentIndex(),
          planetPairSegmentWidth: () => this.astroStore.planetPairSegmentWidth(),
          planetTimeSeriesBarWidth: () => this.astroStore.planetTimeSeriesBarWidth(),
          planetTimeSeriesSegmentWidth: () => this.astroStore.planetTimeSeriesSegmentWidth(),
          planetTimeSeriesValueLabel: (value: number | undefined, metric: string) => this.planetTimeSeriesValueLabel(value, metric),
          publishAstroPanelState: () => { this.publishAstroPanelState() },
          reloadCurrentGraph: () => { this.astroCalcCtl().reloadCurrentGraph() },
          reloadEclipses: () => { this.astroCalcCtl().reloadEclipses() },
          rtsCalendarStartOptionLabel: (offsetDays: number) => this.astroStore.rtsCalendarStartOptionLabel(offsetDays),
          searchObject: (name: string, catalogModuleId?: string, exactSelectionPayload?: string, placement?: string) => { this.searchObject(name, catalogModuleId, exactSelectionPayload, placement) },
          selectAstroFilter: (key: string, value: string) => { this.astroCalcCtl().selectAstroFilter(key, value) },
          selectAstroGroup: (group: number) => { this.astroCalcCtl().selectAstroGroup(group) },
          selectAstroTab: (tab: number) => { this.astroCalcCtl().selectAstroTab(tab) },
          wutCategoryTitle: () => this.wutStore.wutCategoryTitle(),
          wutTargetSubtitle: (target: WutTarget) => this.searchStore.wutTargetSubtitle(target),
          wutTargetTitle: (target: WutTarget) => this.wutTargetTitle(target),
        }
      })
        } else if (this.activePanel === 'help') {
      HelpPanel({
        tools: this.tools,
        onOpenTools: () => { this.openSubPanel('tools') }
      })
	    } else if (this.activePanel === 'catalogs') {
      CatalogsPanel({
        catalogStore: this.catalogStore,
        onDownload: (id: string) => { this.catalogStore.startCatalogDownload(id) },
        onOpenCatalogSource: (url: string) => { this.openExternalUrl(url) },
        onImportCatalog: () => { this.importCatalogFile() }
      })
    } else if (this.activePanel === 'bookmarks') {
      BookmarkPanel({
        store: this.bookmarkStore,
        selectedName: this.objectDetailStore.selectedName,
        onSaveView: () => { this.bookmarkStore.addCurrentBookmark() },
        onGoto: (id: string) => { this.bookmarkStore.gotoBookmark(id) },
        onDelete: (id: string) => { this.bookmarkStore.deleteBookmark(id) }
      })
    } else if (this.activePanel === 'oculars') {
      OcularsPanel({
        store: this.telescopeStore,
        onOpenSubPanel: (name: string) => { this.openSubPanel(name) },
        onSetOcularMode: (isOn: boolean) => { this.ocularCtl().setOcularMode(isOn) },
        onSetTelrad: (isOn: boolean) => { this.ocularCtl().setTelrad(isOn) },
        onSetCrosshairs: (isOn: boolean) => { this.ocularCtl().setCrosshairs(isOn) },
        onSetCcd: (isOn: boolean) => { this.ocularCtl().setCCD(isOn) },
        onSelectInstrument: (kind: string, index: number) => { this.ocularCtl().selectOcularInstrument(kind, index) },
        onChangeCcdRotation: (value: number, mode: SliderChangeMode) => { this.ocularCtl().changeOcularCcdRotation(value, mode) },
        onChangePrismRotation: (value: number, mode: SliderChangeMode) => { this.ocularCtl().changeOcularPrismRotation(value, mode) },
        onResetInstrument: (target: string) => { this.ocularCtl().resetOcularInstrument(target) },
        onRotateReticle: (dir: string) => { this.ocularCtl().rotateOcularReticle(dir) },
        onSetOcularSetting: (setting: string, isOn: boolean) => { this.ocularCtl().setOcularSetting(setting, isOn) },
        onChangeMaskOpacity: (value: number, mode: SliderChangeMode) => { this.ocularCtl().changeOcularMaskOpacity(value, mode) },
        onChangeCropSize: (setting: string, value: number, mode: SliderChangeMode) => { this.ocularCtl().changeOcularCropSize(setting, value, mode) }
      })
    } else if (this.activePanel === 'mosaicCamera') {
      MosaicCameraPanel({
        mosaicStore: this.mosaicStore,
        onSetSetting: (setting: string, value: string) => { this.ocularCtl().setMosaicCamera(setting, value) }
      })
    } else if (this.activePanel === 'archaeoLines') {
      ArchaeoLinesPanel({
        archaeoStore: this.archaeoStore,
        onSetSetting: (setting: string, value: string) => { this.ocularCtl().setArchaeoLineSetting(setting, value) },
        onLineWidthPreview: (value: number) => { this.archaeoStore.archaeoLineWidth = value },
        onSetLineWidth: (value: number) => { this.ocularCtl().setArchaeoLineSetting('lineWidth', value.toString()) }
      })
    } else if (this.activePanel === 'angleMeasure') {
      AngleMeasurePanel({
        store: this.tools,
        onToggle: (enabled: boolean) => { this.tools.toggleAngleMeasure(enabled) },
        onReset: () => { this.resetAngleMeasure() }
      })
    } else if (this.activePanel === 'navStars') {
      NavStarsPanel({
        navStarsStore: this.navStarsStore,
        onSetSetting: (setting: string, value: string) => { this.navStarsStore.setNavStarsSetting(setting, value) }
      })
    } else if (this.activePanel === 'satellites') {
      SatellitesPanel({
        satelliteStore: this.satelliteStore,
        panelScroller: this.satellitePanelScroller,
        groupScroller: this.satelliteGroupScroller,
        onPublishState: () => { this.publishSatellitePanelState() },
        catalogHealthTextOf: (title: string, health: CatalogHealthEntry) => this.catalogHealthText(title, health),
        catalogHealthColorOf: (health: CatalogHealthEntry) => this.catalogHealthColor(health),
        onDeleteSource: (index: number) => { this.satelliteCtl().deleteSatelliteSource(index) },
        onEditSource: (index: number) => { this.satelliteCtl().editSatelliteSource(index) },
        onToggleSourceEnabled: (index: number, enabled: boolean) => { this.satelliteCtl().setSatelliteSourceEnabled(index, enabled) },
        onRestoreSources: () => { this.confirmRestoreSatelliteSources() },
        onSourceInput: (value: string) => { this.satelliteStore.satSourceInput = value },
        onSourceAddNew: (value: boolean) => { this.satelliteStore.satSourceAddNew = value },
        onAddSource: () => { this.satelliteCtl().addSatelliteSource() },
        onRefreshCatalog: () => { this.satelliteCtl().refreshSatelliteCatalog() },
        onTleFileInput: (value: string) => { this.satelliteStore.satTleFileInput = value },
        onImportTle: () => { this.satelliteCtl().importSatelliteTleFile() },
        onSetUpdateSetting: (key: string, value: boolean | number) => { this.satelliteCtl().setSatelliteUpdateSetting(key, value) },
        onUpdateFrequencyInput: (value: string) => { this.satelliteStore.satUpdateFrequencyInput = value },
        onSubmitUpdateFrequency: () => {
          const hours = Number(this.satelliteStore.satUpdateFrequencyInput)
          if (Number.isFinite(hours)) this.satelliteCtl().setSatelliteUpdateSetting('updateFrequencyHours', Math.round(hours))
        },
        onSetFlag: (flag: string, isOn: boolean) => { this.satelliteCtl().setSatelliteFlag(flag, isOn) },
        onSelectGroup: (group: string) => { this.satelliteCtl().selectSatelliteGroup(group) },
        onQueryChange: (value: string) => { this.satelliteStore.satQuery = value; this.satelliteStore.loadSatellites() },
        onSubmitQuery: () => { this.satelliteStore.loadSatellites(false, true) },
        onSearchObject: (item: SatelliteListItem) => { this.searchObject(item.name, '', 'object|Satellite|' + item.id) }
      })
    } else if (this.activePanel === 'meteorshowers') {
      MeteorShowersPanel({
        meteorStore: this.meteorStore,
        onSetFlag: (flag: string, value: boolean) => { this.meteorStore.setMeteorShowersFlag(flag, value) },
        onSearch: (name: string) => { this.searchObject(name, '', '', 'center') }
      })
    } else if (this.activePanel === 'scenery3d') {
      Scenery3dPanel({
        sceneryStore: this.sceneryStore,
        onToggleEnabled: (enabled: boolean) => { this.layerCtl().setScenery3dEnabled(enabled) },
        onSelectScene: (id: string) => { this.layerCtl().setScenery3dScene(id) }
      })
    } else if (this.activePanel === 'ar') {
      ARPreviewPanel({
        arStore: this.arStore,
        onSetMode: (mode: string) => { this.arCtl().setMode(mode) },
        onSetRevealProgress: (value: number) => { this.arCtl().setRevealProgress(value) }
      })
    } else if (this.activePanel === 'skyCultureMaker') {
      SkyCultureMakerPanel({
        store: this.skyCultureMakerStore,
        panelWidth: this.panelWidth,
        onEdited: () => { this.skyCultureMakerCtl().scheduleSkyCultureMakerSave() },
        onAdd: () => { this.skyCultureMakerCtl().addSkyCultureMakerConstellation() },
        onSelect: (index: number) => { this.skyCultureMakerCtl().selectSkyCultureMakerConstellation(index) },
        onUpdate: (updated: SkyCultureMakerConstellation) => { this.skyCultureMakerCtl().updateSkyCultureMakerConstellation(updated) },
        onRemoveSelected: () => { this.skyCultureMakerCtl().removeSelectedSkyCultureMakerConstellation() },
        onRemoveLine: (lineIndex: number) => { this.skyCultureMakerCtl().removeSkyCultureMakerLine(lineIndex) },
        onAddHipLine: () => { this.skyCultureMakerCtl().addSkyCultureMakerHipLine() },
        onAddSelectedStar: () => { this.skyCultureMakerCtl().addSelectedStarToSkyCultureMaker() },
        onImportArtwork: () => { this.skyCultureMakerCtl().importSkyCultureMakerArtworkFile() },
        onRemoveArtwork: () => { this.skyCultureMakerCtl().removeSkyCultureMakerArtwork() },
        onArtworkTouch: (event: TouchEvent) => { this.skyCultureMakerCtl().handleSkyCultureMakerArtworkTouch(event) },
        onValidate: () => { this.skyCultureMakerCtl().validateSkyCultureMaker() },
        onImport: () => { this.skyCultureMakerCtl().importSkyCultureMakerFile() },
        onExport: () => { this.skyCultureMakerCtl().exportSkyCultureMaker() },
        onShare: () => { shareFile(this.hostMediaPort, this.hostPlatformPort, this.skyCultureMakerStore.exportPath, utd.UniformDataType.ZIP_ARCHIVE, this.skyCultureMakerStore.exportFileName, I18n.t('sky_culture_maker_share_description'), 'sky-culture-maker-share', { flashHint: (text: ResourceStr): void => this.flashHint(text), isExpandedLayout: (): boolean => this.isExpandedLayout }) },
        onSaveAs: () => { this.saveFileAs(this.skyCultureMakerStore.exportPath, this.skyCultureMakerStore.exportFileName, 'ZIP 压缩包|.zip') },
        onSaveDraft: () => { this.skyCultureMakerCtl().saveSkyCultureMakerDraft(false) },
        onUndo: () => { this.skyCultureMakerCtl().undoSkyCultureMaker() },
        onReset: () => { this.skyCultureMakerCtl().resetSkyCultureMaker() }
      })
        } else if (this.activePanel === 'nebulaTextures') {
      NebulaTexturesPanel({
        store: this.nebulaTextureStore,
        onSetVisible: (enabled: boolean) => { this.nebulaTextureCtl().setNebulaTextureVisible(enabled) },
        onRefresh: () => { this.nebulaTextureCtl().refreshNebulaTextures() },
        onImport: () => { this.nebulaTextureCtl().importNebulaTextureFile() },
        onSetConflictAvoidance: (value: boolean) => { this.nebulaTextureCtl().setNebulaTextureFlag('setNebulaTextureConflictAvoidance', value, this.nebulaTextureStore.nebulaTextureStatus?.avoidAreaConflict === true) },
        onGoto: (imageUrl: string) => { this.nebulaTextureCtl().gotoNebulaTexture(imageUrl) },
        onRemove: (imageUrl: string) => { this.nebulaTextureCtl().removeNebulaTexture(imageUrl) }
      })
    } else if (this.activePanel === 'scripts') {
      ScriptsPanel({
        tools: this.tools,
        guideSessionActive: this.scriptStore.scriptSessionActive(this.tools.recording, this.guideStore.guideState.active),
        scriptStore: this.scriptStore,
        scriptMetaLine: (filename: string) => { return this.scriptStore.scriptMetaLine(filename) },
        scriptSourceLine: (filename: string) => { return this.scriptStore.scriptSourceLine(filename) },
        onStartGuide: (id: string) => { this.guideCtl().executeGuideRequest('startGuide', id) },
        onStopPlayback: () => { this.scriptPlaybackCtl().stopScriptPlayback() },
        onImportScript: () => { this.scriptPlaybackCtl().importScriptFile() },
        onPlayScript: (name: string) => { this.scriptPlaybackCtl().playScriptByName(name) },
        onToggleRecording: () => { this.tools.recording ? this.recordingCtl().stopRecording() : this.recordingCtl().startRecording() },
        onSaveRecording: () => { this.recordingCtl().saveCurrentRecording() },
        onSetRecordName: (value: string) => { this.scriptStore.recordName = value },
        onPlayRecording: (file: string) => { this.recordingCtl().playRecording(file) },
        onLoadRecording: (file: string, name: string) => { this.scriptPlaybackCtl().loadRecordingByName(file, name) },
        onShareRecording: (rec: RecordingEntry, idx: number) => {
          shareFile(this.hostMediaPort, this.hostPlatformPort, rec.path ?? '', utd.UniformDataType.PLAIN_TEXT, rec.name,
            'Stellarium 操作录制', 'recording-share-' + idx.toString(),
            { flashHint: (text: ResourceStr): void => this.flashHint(text), isExpandedLayout: (): boolean => this.isExpandedLayout })
        },
        onDeleteRecording: (file: string) => { this.recordingCtl().deleteRecording(file) },
        onToggleScreenVideo: () => {
          if (this.scriptStore.screenVideoRecording) this.recordingCtl().stopScreenVideoRecording()
          else this.recordingCtl().startScreenVideoRecording()
        },
        onSaveScreenVideoToGallery: (result: SaveButtonOnClickResult) => { void this.recordingCtl().saveScreenVideoToGallery(result === SaveButtonOnClickResult.SUCCESS) },
        onShareScreenVideo: () => {
          shareFile(this.hostMediaPort, this.hostPlatformPort, this.scriptStore.screenVideoPath, utd.UniformDataType.VIDEO, this.scriptStore.screenVideoFileName,
            'Stellarium 屏幕视频', 'screen-video-share',
            { flashHint: (text: ResourceStr): void => this.flashHint(text), isExpandedLayout: (): boolean => this.isExpandedLayout })
        },
        onSaveScreenVideoAs: () => { this.saveFileAs(this.scriptStore.screenVideoPath, this.scriptStore.screenVideoFileName, 'MP4 视频|.mp4') },
        onSetVideoFps: (value: string) => { this.scriptStore.videoFps = value },
        onSetVideoDuration: (value: string) => { this.scriptStore.videoDuration = value },
        onToggleVideoRecording: () => { this.scriptStore.videoRecording ? this.recordingCtl().stopVideoRecording() : this.recordingCtl().startVideoRecording() },
        onShareVideoArchive: () => {
          shareFile(this.hostMediaPort, this.hostPlatformPort, this.scriptStore.videoArchivePath, utd.UniformDataType.ZIP_ARCHIVE,
            this.scriptStore.videoArchiveFileName, 'Stellarium 高质量星图帧序列', 'video-frames-share',
            { flashHint: (text: ResourceStr): void => this.flashHint(text), isExpandedLayout: (): boolean => this.isExpandedLayout })
        },
        onExportVideoArchive: () => { this.saveFileAs(this.scriptStore.videoArchivePath, this.scriptStore.videoArchiveFileName, 'ZIP 压缩包|.zip') }
      })
    } else if (this.activePanel === 'observing') {
      ObservingPanel({
        wutStore: this.wutStore,
        observingListStore: this.obsListStore,
        onOpenSearch: () => { this.openSubPanel('search') },
        onClearAll: () => {
          this.obsListStore.observingList = []
          this.obsListStore.persistObservingList()
          this.flashHint(I18n.t('i0302'))
        },
        onSelectCategory: (category: string) => {
          if (this.wutStore.wutCategory !== category) {
            this.wutStore.wutCategory = category
            this.wutStore.loadWutTargets()
          }
        },
        onRefreshTargets: () => { this.wutStore.loadWutTargets() },
        onJumpTarget: (target: WutTarget) => { this.astroCalcCtl().jumpToWutTarget(target) },
        onAddTarget: (target: WutTarget) => { this.addWutTargetToObservingList(target) },
        onRemoveTarget: (name: string) => { this.removeObservingTarget(name) },
        onSearchName: (name: string) => { this.searchObject(name) },
        targetTitleOf: (target: WutTarget) => this.wutTargetTitle(target),
        targetSubtitleOf: (target: WutTarget) => this.searchStore.wutTargetSubtitle(target),
        typeOf: (type: string) => zhType(type),
        displayNameOf: (name: string) => this.wutStore.observingDisplayName(name)
      })
    } else if (this.activePanel === 'telescope') {
      TelescopePanel({
        store: this.telescopeStore,
        onBeginNew: () => { this.telescopeCtl().beginNewTelescopeProfile() },
        onSelectProfile: (slot: number) => { this.telescopeCtl().selectTelescopeProfile(slot) },
        onSelectProtocol: (protocol: string) => { this.telescopeCtl().selectTelescopeProtocol(protocol) },
        onValidateEditor: () => { this.telescopeCtl().validateTelescopeEditorStatus() },
        onSave: () => { this.telescopeCtl().saveTelescopeProfile() },
        onDelete: () => { this.telescopeCtl().deleteTelescopeProfile() },
        onTest: () => { this.telescopeCtl().testTelescopeConnection() },
        onGoto: () => { this.telescopeCtl().lx200GotoSelected() },
        onSync: () => { this.telescopeCtl().lx200SyncSelected() },
        onAbort: () => { this.telescopeCtl().lx200Abort() },
        onReadPosition: (center: boolean) => { this.telescopeCtl().readTelescopePosition(center) },
        onSetLivePosition: (enabled: boolean) => { this.telescopeCtl().setTelescopeLivePosition(enabled) }
      })
    } else if (this.activePanel === 'tools') {
      ToolsPanel({
        store: this.tools,
        configImportText: this.tools.configImportText,
        sessionImportText: this.tools.sessionImportText,
        onScreenshot: () => { saveScreenshot(this.commandPort(), this.hostMediaPort, { flashHint: (text: ResourceStr): void => this.flashHint(text), screenshotSaving: (): boolean => this.tools.screenshotSaving, setScreenshotSaving: (saving: boolean): void => { this.tools.screenshotSaving = saving } }) },
        onExportConfig: () => { this.tools.exportConfig() },
        onShareConfig: () => { this.shareConfigBackup() },
        onImportConfig: () => { this.tools.importConfig() },
        onConfigImportText: (value: string) => { this.tools.configImportText = value },
        onSessionExport: () => { this.sessionToolStore.sessionExport() },
        onSessionShare: () => { this.sessionToolStore.sessionShare() },
        onSessionApply: () => { this.sessionToolStore.sessionApply() },
        onSessionImportText: (value: string) => { this.tools.sessionImportText = value },
        onLoadLog: () => { this.tools.loadLog() },
        onCollapseLog: () => { this.tools.logVisible = false }
      })
    } else if (this.activePanel === 'audio') {
      AudioPanel({
        audioStore: this.audioStore,
        onToggleMusic: (enabled: boolean) => {
          this.audioStore.musicEnabled = enabled
          const engine = AudioEngine.getInstance()
          if (enabled) { engine.start().then(() => { engine.setMuted(false) }) } else { engine.setMuted(true) }
          this.audioStore.persistMusicEnabled()
          this.flashHint(enabled ? I18n.t('music_on_hint') : I18n.t('music_off_hint'))
        },
        onVolumeChange: (value: number) => {
          this.audioStore.audioVolume = value
          AudioEngine.getInstance().setVolume(value)
        }
      })
    } else {
      ConfigFallbackPanel({
        gyroStore: this.gyroStore,
        layerStore: this.layerStore,
        nightModeStore: this.nightModeStore,
        telescopeStore: this.telescopeStore,
        isExpandedLayout: this.isExpandedLayout,
        fovText: this.fovText,
        selectedLanguage: this.languageStore.selectedLanguage,
        viewSettingsStore: this.viewSettingsStore,
        observingListStore: this.obsListStore,
        skyCultureViewStore: this.skyCultureViewStore,
        observingDisplayName: (name: string) => { return this.wutStore.observingDisplayName(name) },
        selectObservingTarget: (name: string) => { this.searchObject(name); this.flashHint(I18n.t('i0082')) },
        removeObservingTarget: (name: string) => { this.removeObservingTarget(name) },
        clearObservingList: () => { this.obsListStore.observingList = []; this.obsListStore.persistObservingList(); this.flashHint(I18n.t('i0302')) },
        setLegacyDistanceUnit: (useMetric: boolean) => {
          this.viewSettingsStore.useMetricUnits = useMetric
          this.callInteractive('setConfigString', 'astronomy/flag_use_km_for_distance=' + (useMetric ? 'true' : 'false'), () => {})
        },
        handleChip: (id: string) => { this.timeCtl().handleChip(id) },
        toggleGyroscope: (enabled: boolean) => { this.gyroCtl().toggleGyroscope(enabled) },
        flashHint: (text: ResourceStr) => { this.flashHint(text) },
        setLanguage: (lang: string) => { this.setLanguage(lang) },
        setSkyCulture: (culture: string) => { this.skyCultureCtl().setSkyCulture(culture) },
        triggerAction: (actionId: string) => { this.triggerAction(actionId) },
        refreshState: () => { this.refreshState() },
        saveScreenshot: () => { saveScreenshot(this.commandPort(), this.hostMediaPort, { flashHint: (text: ResourceStr): void => this.flashHint(text), screenshotSaving: (): boolean => this.tools.screenshotSaving, setScreenshotSaving: (saving: boolean): void => { this.tools.screenshotSaving = saving } }) }
      })
    }
  }
}
