import { StellariumBridgeResponse, SessionSnapshot, TonightEvents, TonightPlanet, TonightShower, WutTarget, EphemerisRow, AstroCalcContext, RtsCalendarDay, AltAzPoint, AnnualElevationPoint, ObservabilityDay, LunarElongationPoint, PlanetTimeSeriesPoint, PlanetPairDistancePoint, PlanetCalcItem, PhenomenonItem, EclipseItem, PlanetaryTransitItem, MoonPhaseItem, SeasonEvent, LangOption, HierCity, CatOption, NameItem, SearchSug, WindowNativeNodeCreateInfo, TabItem, ChipItem, LandscapeItem, ScriptMetadata, PlanetPosition, HeliocentricPosition, CelestialPosition, ObjectInfo, SkyCultureItem, SkyCultureRawItem, SkyCultureArtItem, SkyCultureDescriptionBlock, SkyCultureTerritoryEntry, SkyCultureTerritoryPolygon, PluginItem, Scenery3dItem, ShellAction, LocSearchItem, SavedLocation, ObjectDetailField, ObjectDetailModel, SatellitePass, PolarScopeData } from '../../pages/StellariumTypes'

export interface CityPreset {
  lat: number
  lon: number
  alt: number
}

export interface ImageDecodeSize {
  width: number
  height: number
}

export interface ObjectInspectorRingSpec {
  texturePath: string
  innerRadius: number
  outerRadius: number
  tilt: number
  opacity: number
}

export interface HeliocentricPositionOptions {
  includeSelectedMinor: boolean
  includeBrightComets: boolean
  cometMagnitudeLimit: number
}

export interface ConstellationNavigationItem {
  englishName: string
  localizedName: string
}

export interface PluginFeatureRoute {
  panel: string
  kind: string
  catalogModuleId?: string
  astroTab?: number
  graphMode?: number
  layerTab?: number
}

export interface NebulaTextureItem {
  imageUrl: string
  status?: string
  ready?: boolean
  width?: number
  height?: number
  bytes?: number
  centerRaDeg?: number
  centerDecDeg?: number
  mappingValid?: boolean
  decodeError?: string
}

export interface NebulaTextureStatus {
  enabled?: boolean
  avoidAreaConflict?: boolean
  configExists?: boolean
  configLoaded?: boolean
  configError?: string
  layerLoaded?: boolean
  offline?: boolean
  plateSolverAvailable?: boolean
  count?: number
  readyCount?: number
  invalidCount?: number
  items?: Array<NebulaTextureItem>
}

export interface NebulaTextureRefreshResponse extends StellariumBridgeResponse {
  status?: NebulaTextureStatus
}

export interface SkyCultureMakerArtworkAnchor {
  hip: number
  pos: number[]
}

export interface SkyCultureMakerArtwork {
  file: string
  size: number[]
  anchors: SkyCultureMakerArtworkAnchor[]
}

export interface SkyCultureMakerConstellation {
  id: string
  english: string
  native: string
  pronounce: string
  transliteration: string
  IPA: string
  dark: boolean
  lines: number[][]
  image?: SkyCultureMakerArtwork
}

export interface SkyCultureMakerDraft {
  schemaVersion: number
  id: string
  name: string
  author: string
  license: string
  region: string
  classification: string[]
  native_lang: string
  beginTime: number
  endTime: number
  introduction: string
  description: string
  constellations: SkyCultureMakerConstellation[]
  updatedAt?: string
}

export interface SkyCultureMakerIssue {
  severity: string
  code: string
  field: string
  message: string
}

export interface SkyCultureMakerValidation {
  valid: boolean
  errorCount: number
  warningCount: number
  constellationCount: number
  lineCount: number
  starReferenceCount: number
  errors: SkyCultureMakerIssue[]
  warnings: SkyCultureMakerIssue[]
}

export interface TelescopeControlResponse extends StellariumBridgeResponse {
  scope?: string
  transport?: string
  connectionAttempted?: boolean
  networkConnection?: boolean
  connectionAllowed?: boolean
  state?: string
  errorCode?: string
  simulated?: boolean
  testedAtMs?: number
  lastError?: string
  ra?: string
  dec?: string
}

export interface TelescopeProfile {
  slot: number
  name: string
  protocol: string
  deviceModel: string
  host: string
  port: number
  equinox: string
  commandDelayMs: number
  circles: number[]
  scope?: string
  connectionAllowed?: boolean
  state?: string
  lastError?: string
  testedAtMs?: number
}

export interface TelescopeProfilesResponse extends StellariumBridgeResponse {
  profiles?: TelescopeProfile[]
  selectedSlot?: number
  maxProfiles?: number
  autoConnectSupported?: boolean
}

export const LX200_DEVICE_MODELS: string[] = [
  'Meade AutoStar compatible',
  'Meade LX200 (compatible)',
  'Meade ETX70 (#494 Autostar, #506 CCS)',
  'Losmandy G-11',
  'Wildcard Innovations Argo Navis (Meade mode)'
]

export const TELESCOPE_SIMULATOR_MODEL: string = 'Offline LX200 Simulator'

export interface HeliocentricOrbit {
  name: string
  englishName: string
  radiusAU: number
  color: string
  visualRadius: number
}

export interface ConfigurationOption {
  id: string
  label: string
}

export interface SkyCultureVisualColors {
  constellationLines: string
  constellationLabels: string
  constellationBoundaries: string
  constellationHulls: string
  zodiac: string
  lunarSystem: string
  asterismLines: string
  asterismLabels: string
  rayHelpers: string
}

export interface CelestialPositionOptions {
  category: string
  horizontal: boolean
  magnitudeLimit: number
  maximumRows: number
}

export interface CelestialPositionCategory {
  id: string
  label: string
}

export interface PhenomenaOptions {
  bodyA: string
  bodyB: string
  days: number
  startOffsetMonths: number
  maxSeparation: number
  includeOppositions: boolean
  includePerihelionAphelion: boolean
  includeElongationsQuadratures: boolean
  includeStations: boolean
}

export interface PhenomenaStartOption {
  label: string
  value: number
}

export interface EphemerisOptions {
  days: number
  stepHours: number
  jd?: number
  names?: string[]
  allNakedEye?: boolean
}

export interface RtsCalendarOptions {
  days: number
  jd?: number
}

export interface EclipseOptions {
  months: number
  jd?: number
}

export interface LayerPresetState {
  id: string
  enabled: boolean
}

export const MARKING_LAYER_ACTION_IDS: string[] = [
  'actionShow_Cardinal_Points', 'actionShow_Azimuthal_Grid', 'actionShow_Equatorial_Grid',
  'actionShow_Equatorial_J2000_Grid', 'actionShow_Ecliptic_Grid', 'actionShow_Ecliptic_J2000_Grid',
  'actionShow_Galactic_Grid', 'actionShow_Supergalactic_Grid', 'actionShow_Fixed_Equatorial_Grid',
  'actionShow_Fixed_Equator_Line', 'actionShow_Equator_Line', 'actionShow_Ecliptic_Line',
  'actionShow_Galactic_Equator_Line', 'actionShow_Supergalactic_Equator_Line',
  'actionShow_Equator_J2000_Line', 'actionShow_Ecliptic_J2000_Line', 'actionShow_Meridian_Line',
  'actionShow_Horizon_Line', 'actionShow_Celestial_Poles', 'actionShow_Ecliptic_Poles',
  'actionShow_Galactic_Poles', 'actionShow_Equinox_Points', 'actionShow_Solstice_Points',
  'actionShow_Antisolar_Point', 'actionShow_Umbra_Circle', 'actionShow_Penumbra_Circle',
  'actionShow_Compass_Marks', 'actionShow_Gridlines', 'actionShow_FOV_Center_Marker', 'actionShow_FOV_Circular_Marker',
  'actionShow_FOV_Rectangular_Marker', 'actionShow_Intercardinal_Points',
  'actionShow_Secondary_Intercardinal_Points', 'actionShow_Tertiary_Intercardinal_Points',
  'actionShow_Prime_Vertical_Line', 'actionShow_Current_Vertical_Line', 'actionShow_Colure_Lines',
  'actionShow_Precession_Circles', 'actionShow_Circumpolar_Circles',
  'actionShow_Invariable_Plane_Line', 'actionShow_Ray_Helpers', 'actionShow_Solar_Equator_Line', 'actionShow_Zenith_Nadir',
  'actionShow_Celestial_J2000_Poles', 'actionShow_Ecliptic_J2000_Poles',
  'actionShow_Equinox_J2000_Points', 'actionShow_Solstice_J2000_Points',
  'actionShow_Galactic_Center', 'actionShow_Supergalactic_Poles', 'actionShow_Apex_Points',
  'actionShow_Umbra_Center_Point', 'actionShow_Longitude_Line', 'actionShow_Quadrature_Line'
]

export const CONTENT_LAYER_ACTION_IDS: string[] = [
  'actionShow_Stars', 'actionShow_Stars_Labels', 'actionShow_Planets', 'actionShow_Planets_Labels',
  'actionShow_Planets_Orbits', 'actionShow_Planets_Hints', 'actionShow_Planets_Trails',
  'actionShow_Planets_EnlargeMoon', 'actionShow_Planets_EnlargePlanets',
  'actionShow_Planets_EnlargeSun', 'actionShow_Planets_ShowMinorBodyMarkers',
  'actionShow_Planets_Nomenclature', 'actionShow_Nebulas', 'actionShow_DSO_Textures',
  'actionShow_MilkyWay', 'actionShow_Fog', 'actionShow_Ground', 'actionShow_MistHorizon',
  'actionShow_LandscapeIllumination', 'actionShow_LandscapeLabels',
  'actionShow_Constellation_Lines', 'actionShow_Constellation_Labels',
  'actionShow_Constellation_Boundaries', 'actionShow_Constellation_Art', 'actionShow_Constellation_Hulls', 'actionShow_Zodiac',
  'actionShow_LunarSystem', 'actionShow_Asterism_Lines', 'actionShow_Asterism_Labels',
  'actionShow_Atmosphere', 'actionShow_Hips_Surveys', 'actionShow_Toast_Survey'
]

export interface AstroCsvExport {
  title: string
  rows: Array<Array<string | number | boolean | undefined>>
  headers: Array<string>
}

export const CELESTIAL_POSITION_CATEGORIES: CelestialPositionCategory[] = [
  { id: 'planets', label: '行星' },
  { id: 'stars', label: '亮星' },
  { id: 'deepSky', label: '深空' },
  { id: 'galaxies', label: '星系' },
  { id: 'nebulae', label: '星云' },
  { id: 'clusters', label: '星团' },
  { id: 'comets', label: '彗星' },
  { id: 'minorBodies', label: '小行星' },
]

export const HELIOCENTRIC_PLANET_ORBITS: HeliocentricOrbit[] = [
  { name: '水星', englishName: 'Mercury', radiusAU: 0.39, color: '#AAB5C5', visualRadius: 29 },
  { name: '金星', englishName: 'Venus', radiusAU: 0.72, color: '#DEC18A', visualRadius: 43 },
  { name: '地球', englishName: 'Earth', radiusAU: 1.00, color: '#6BAED6', visualRadius: 57 },
  { name: '火星', englishName: 'Mars', radiusAU: 1.52, color: '#D18467', visualRadius: 70 },
  { name: '木星', englishName: 'Jupiter', radiusAU: 5.20, color: '#D6A06D', visualRadius: 88 },
  { name: '土星', englishName: 'Saturn', radiusAU: 9.54, color: '#D7BF76', visualRadius: 105 },
  { name: '天王星', englishName: 'Uranus', radiusAU: 19.19, color: '#82C9D2', visualRadius: 120 },
  { name: '海王星', englishName: 'Neptune', radiusAU: 30.07, color: '#6F9EDD', visualRadius: 133 },
]

export const HELIOCENTRIC_DISTANCE_GUIDES: HeliocentricOrbit[] = [
  { name: '1 AU', englishName: '', radiusAU: 1.00, color: '#5D7B98', visualRadius: 57 },
  { name: '5 AU', englishName: '', radiusAU: 5.00, color: '#405D79', visualRadius: 87 },
  { name: '15 AU', englishName: '', radiusAU: 15.00, color: '#324B64', visualRadius: 113 },
  { name: '30 AU', englishName: '', radiusAU: 30.00, color: '#2B4058', visualRadius: 133 },
]

export const PHENOMENA_START_OPTIONS: PhenomenaStartOption[] = [
  { label: '现在', value: 0 },
  { label: '3 个月后', value: 3 },
  { label: '6 个月后', value: 6 },
  { label: '1 年后', value: 12 },
]

export interface TonightPlanetRow {
  name: string
  line: string
  jd: number
  lock: string
}

// 星表下载（C++ 桥 getStarCatalogs / downloadStarCatalog / getStarCatalogStatus）。
// magRange/count/sizeMb/checksum 由桥回包按 defaultStarsConfig.json 原样带出；
// `source` 是从 url 派生的下载渠道标签，离线构建下用于在面板里标注来源。
export interface StarCatalogItem {
  id: string
  name: string
  size: string
  key: string
  fileName: string
  url: string
  html: string
  checked: boolean
  magRange: string
  count: string
  sizeMb: number
  checksum: string
  source: string
  sourcePage: string
}
export interface StarCatalogRaw {
  id?: string
  name?: string
  size?: string
  key?: string
  fileName?: string
  url?: string
  html?: string
  checked?: boolean | string | number
  magRange?: number[]
  count?: number
  sizeMb?: number
  checksum?: string
}
export interface StarCatalogsResponse extends StellariumBridgeResponse {
  catalogs?: StarCatalogRaw[]
}
export interface StarCatalogStatusResponse extends StellariumBridgeResponse {
  id?: string
  state?: string
  bytes?: number
  error?: string
  md5ok?: boolean
}
export interface LimitMagnitudeResponse extends StellariumBridgeResponse {
  limitMagnitude?: number
  customStarMagLimit?: number
  starMagnitudeLimitEnabled?: boolean
}
export interface GyroGuideProjection extends StellariumBridgeResponse {
  valid?: boolean
  visible?: boolean
  xRatio?: number
  yRatio?: number
}
export interface SkyUiObstacle {
  label: string
  left: number
  top: number
  right: number
  bottom: number
}

// 书签（C++ 桥 addBookmark / getBookmarks / deleteBookmark / gotoBookmark）
export interface BookmarkItem {
  id: string
  name: string
  fov: number
  object: string
}
export interface BookmarkRaw {
  id?: string
  name?: string
  fov?: number
  object?: string
}
export interface BookmarksResponse extends StellariumBridgeResponse {
  items?: BookmarkRaw[]
  count?: number
}

// 观测点持久化记录（LOCATION_STORE）：让 GPS / 选点后的位置跨重启保留，不再回退默认北京。
export interface ObserverLocationRecord {
  name: string
  latitude: number
  longitude: number
  altitude: number
  planet: string
  // 位置来源（gps / map / named）：快捷操作面板标题据此显示 `GPS` 或名称；旧记录缺失时回落 named。
  source?: string
}

export const BOOKMARK_STORE: string = 'stellarium_bookmarks'
export const SEARCH_HISTORY_STORE: string = 'stellarium_search_history'
export const OBSERVING_STORE: string = 'stellarium_observing_list'
export const LOCATION_STORE: string = 'stellarium_observer_location'
export const QUICK_PANEL_STORE: string = 'stellarium_quick_panel'
// 详情卡「呈现轴」持久化（key `detailDisplayMode` = 'planetarium' / 'observe'）：
// 与信息级别（数据轴，C++ 配置）正交，见 specs/OBJECT-DETAIL-OBSERVE-MODE.md §7。
export const INFO_WINDOW_STORE: string = 'stellarium_info_window'
export const OFFLINE_APPGALLERY_BUILD: boolean = true


// 望远镜/目镜配置（Oculars 插件桥）
export interface OcularInstrumentItem {
  index: number
  name: string
  apparentFov?: number
  focalLength?: number
  fieldStop?: number
  binocular?: boolean
  permanentCrosshair?: boolean
  diameter?: number
  focalRatio?: number
  horizontalFlipped?: boolean
  verticalFlipped?: boolean
  equatorial?: boolean
  multiplier?: number
  resolutionX?: number
  resolutionY?: number
  chipWidth?: number
  chipHeight?: number
  binningX?: number
  binningY?: number
  rotation?: number
}
export interface OcularsData {
  ocularMode: boolean
  telrad: boolean
  crosshairs: boolean
  ccd: boolean
  ocularIndex: number
  telescopeIndex: number
  lensIndex: number
  ccdIndex: number
  ocularNames: string[]
  telescopeNames: string[]
  lensNames: string[]
  ccdNames: string[]
  ocularItems: OcularInstrumentItem[]
  telescopeItems: OcularInstrumentItem[]
  lensItems: OcularInstrumentItem[]
  ccdItems: OcularInstrumentItem[]
  ocularReady: boolean
  ccdReady: boolean
  hasSelection: boolean
  requireSelection: boolean
  autoLimitMagnitude: boolean
  hideGridsLines: boolean
  autoScaleTelrad: boolean
  autoScaleCcd: boolean
  semiTransparentMask: boolean
  maskOpacity: number
  showResolutionCriteria: boolean
  autoSetMountForCcd: boolean
  horizontalCoordinates: boolean
  sensorCropOverlay: boolean
  sensorPixelGrid: boolean
  focuserOverlay: boolean
  scaleImageCircle: boolean
  maxExposureTimeForCcd: boolean
  showContour: boolean
  showCardinals: boolean
  alignCrosshair: boolean
  smallFocuserOverlay: boolean
  mediumFocuserOverlay: boolean
  largeFocuserOverlay: boolean
  dmsDegrees: boolean
  initFov: boolean
  initDirection: boolean
  oagLimits: boolean
  ccdCropHSize: number
  ccdCropVSize: number
  ccdPrismRotation: number
  guiPanelEnabled: boolean
  magnification?: number
  actualFov?: number
  exitPupil?: number
  limitMagnitude?: number
  ccdFovX?: number
  ccdFovY?: number
  ccdPixelScaleX?: number
  ccdPixelScaleY?: number
  ccdRotation?: number
}
export interface OcularsResponse extends StellariumBridgeResponse {
  oculars?: OcularsData
}
export interface OcularModeResponse extends StellariumBridgeResponse {
  applied?: boolean
  selectionRequired?: boolean
}
export interface PointerCoordinatesData {
  enabled: boolean
  enableAtStartup: boolean
  showCoordinatesButton: boolean
  showConstellation: boolean
  showCrossedLines: boolean
  showElongation: boolean
  coordinateSystem: string
  coordinatesPlace: string
}
export interface PointerCoordinatesResponse extends StellariumBridgeResponse {
  pointerCoordinates?: PointerCoordinatesData
}

export interface MosaicCameraData {
  enabled: boolean
  currentCamera: string
  names: string[]
  ra: number
  dec: number
  rotation: number
  visible: boolean
}
export interface EquationOfTimeData {
  enabled: boolean
  msFormat: boolean
  inverted: boolean
  enableAtStartup: boolean
  minutes: number
}
export interface ArchaeoLinesData {
  enabled: boolean
  lineWidth: number
  equinox: boolean
  solstices: boolean
  crossquarters: boolean
  majorStandstills: boolean
  minorStandstills: boolean
  polarCircles: boolean
  zenithPassage: boolean
  nadirPassage: boolean
  selectedObject: boolean
  selectedObjectAzimuth: boolean
  selectedObjectHourAngle: boolean
  currentSun: boolean
  currentMoon: boolean
  currentPlanet: number
}

export interface ArchaeoPlanetOption {
  id: number
  label: ResourceStr
  value: string
}

// 卫星（Satellites 插件桥）
export interface SatellitesData {
  groups: string[]
  labels: boolean
  orbitLines: boolean
  hints: boolean
  iconicMode: boolean
  hideInvisible: boolean
  count: number
  offline: boolean
  observerIsEarth: boolean
  dateInRange: boolean
  newestUpdate: string
  outdatedCount: number
  matchedCount: number
  catalogCreator?: string
  catalogSnapshot?: string
  catalogSource?: string
  items: SatelliteListItem[]
}
export interface SatelliteListItem {
  id: string
  name: string
  englishName: string
  displayed: boolean
  outdated: boolean
  tleEpoch: string
  lastUpdated: string
  heightKm: number
}
export interface SatelliteSource {
  index: number
  url: string
  addNew: boolean
  local: boolean
  network: boolean
  scheme: string
  valid: boolean
}
export interface SatelliteSourceInput {
  url: string
  addNew: boolean
}
export interface SatelliteUpdateSettings {
  updatesEnabled: boolean
  autoAddEnabled: boolean
  autoRemoveEnabled: boolean
  autoDisplayEnabled: boolean
  updateFrequencyHours: number
  secondsToUpdate: number
  updateState: number
}
export interface SatelliteSourcesResponse extends StellariumBridgeResponse {
  offline?: boolean
  remoteSourcesAreDormant?: boolean
  sources?: SatelliteSource[]
  settings?: SatelliteUpdateSettings
}
export interface SatellitesResponse extends StellariumBridgeResponse {
  satellites?: SatellitesData
}
export interface CatalogHealthEntry {
  status?: string
  checkedAt?: string
  ageDays?: number
  maxAgeDays?: number
  verified?: boolean
  partial?: boolean
  sourceErrors?: number
  entries?: number
  files?: number
  missingFiles?: string[]
}
export interface CatalogHealthResponse extends StellariumBridgeResponse {
  manifestPresent?: boolean
  satellites?: CatalogHealthEntry
  stars?: CatalogHealthEntry
}

// 流星雨（MeteorShowers 插件桥）
export interface MeteorShowersData {
  enabled: boolean
  labels: boolean
  activeOnly: boolean
  marker: boolean
  catalogVersion?: string
  catalogName?: string
  catalogSource?: string
}
export interface MeteorShowerItem {
  name: string
  englishName: string
  zhr: number
  status: string
  speed: number
  popIdx: number
  parent: string
  peakDate: string
  activeStart: string
  activeEnd: string
}
export interface MeteorShowersResponse extends StellariumBridgeResponse {
  meteorShowers?: MeteorShowersData
  showerList?: MeteorShowerItem[]
}
export interface Scenery3dResponse extends StellariumBridgeResponse {
  items?: Scenery3dItem[]
  current?: string
  enabled?: boolean
  loading?: string
}
export interface LogResponse extends StellariumBridgeResponse {
  log?: string
  totalChars?: number
  logFile?: string
}
export interface AboutResponse extends StellariumBridgeResponse {
  version?: string
  qtVersion?: string
  userDir?: string
  configFile?: string
  logFile?: string
}
export interface ExportConfigResponse extends StellariumBridgeResponse {
  content?: string
  configFile?: string
}
export interface ScreenshotResponse extends StellariumBridgeResponse {
  path?: string
  fileName?: string
  bytes?: number
}
export interface ImportConfigResponse extends StellariumBridgeResponse {
  applied?: number
}
export interface SpokenTextResponse extends StellariumBridgeResponse {
  text?: string
}
export interface RecordCmd {
  c: string
  p: string
  // Relative time from recording start, in milliseconds. Optional for
  // compatibility with recordings created before the timeline was added.
  t?: number
}
export interface RecordingEntry {
  file: string
  path?: string
  bytes?: number
  name: string
  created: string
  count: number
}
export interface RecordingsResponse extends StellariumBridgeResponse {
  items?: Array<RecordingEntry>
}
export interface RecordingDetailResponse extends StellariumBridgeResponse {
  path?: string
  fileName?: string
  bytes?: number
  name?: string
  commands?: Array<RecordCmd>
}
export interface ScriptStatusResponse extends StellariumBridgeResponse {
  running?: boolean
  waiting?: boolean
  waitMessage?: string
  scriptId?: string
  scriptRate?: number
}
export interface ScriptCaption {
  id: number
  text: string
  visible: boolean
}
export interface ScriptCaptionsResponse extends StellariumBridgeResponse {
  captions?: Array<ScriptCaption>
}

export interface CommandCatalogEntry {
  name: string
  category: string
  description: string
  mutatesState: boolean
  requiresConfirmation: boolean
  offline: boolean
  examplePayload?: string
}
export interface CommandCatalogResponse extends StellariumBridgeResponse {
  commands?: Array<Object>
}

// 望远镜配置选择器的展示数据（非响应式，@Builder 内实时读取 @State）
export class OcularSelInfo {
  name: string = ''
  countText: string = ''
}
