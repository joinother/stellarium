// Auto-extracted from MainWindowNativeNode.ets — shared types & constants
// Do NOT add @Component or @Builder here; this file is import-only.

export interface LangOption { code: string; name: ResourceStr }

export interface HierCity {
  n: string
  la: number
  lo: number
  al: number
  p: number
  country: string
  province?: string
  planet?: string
}

export interface CatOption {
  code: string
  label: ResourceStr
  moduleId?: string
  iconKey?: string
}

export interface NameItem {
  name: string
  zh?: ResourceStr
  subtitle?: string
  type?: string
  altitude?: number
  magnitude?: number
  visibleNow?: boolean
}

// 搜索建议项：zh 用于显示，en 用于辅助识别，selection 用对象类型和 ID 精确选中。
export interface SearchSug {
  zh: string
  en: string
  type?: string
  selection?: string
  fuzzy?: boolean
  crossLanguage?: boolean
}

export interface WindowNativeNodeCreateInfo {
  xComponentId: string
  onAppear: () => void
  onAttach: () => void
  onDisAppear: () => void
}

export interface ChipItem {
  id: string
  label: ResourceStr
}

export interface TabItem {
  label: ResourceStr
  id: number
}

export interface LandscapeItem {
  id: string
  name: string
  author?: string
  description?: string
  source?: string
  hasDescription?: boolean
  hasLocation?: boolean
  planet?: string
  latitude?: string
  longitude?: string
  altitude?: number
  timezone?: string
}

export interface ScriptMetadata {
  file: string
  name?: string
  author?: string
  license?: string
  version?: string
  description?: string
  shortcut?: string
  source?: string
  hasMetadata?: boolean
}

export interface PlanetPosition {
  name: string
  englishName?: string
  rightAscension?: string
  declination?: string
  altitude: number
  azimuth: number
  magnitude: number
  distanceAU?: number
  angularSizeArcmin?: number
  transit?: string
}
export interface PolarScopeStar {
  name: string
  englishName: string
  magnitude: number
  radiusDeg: number
  positionAngleDeg: number
}
export interface PolarScopeData {
  hemisphere: string
  poleName: string
  planetName: string
  latitude: number
  siderealHours: number
  hourAngleHours?: number
  hourAngleText: string
  viewAngleText: string
  poleStarName: string
  poleStarEnglishName?: string
  poleStarMagnitude?: number
  poleStarRadiusDeg?: number
  poleScreenValid?: boolean
  poleScreenXRatio?: number
  poleScreenYRatio?: number
  poleStarScreenValid?: boolean
  poleStarScreenXRatio?: number
  poleStarScreenYRatio?: number
  stars: Array<PolarScopeStar>
}
export interface HeliocentricPosition {
  name: string
  englishName: string
  latitude: number
  longitude: number
  distanceAU: number
  isComet: boolean
  isSelectedMinor: boolean
  displayLongitude?: number
  displayRadius?: number
}
export interface CelestialPosition {
  name: string
  englishName: string
  catalogId: string
  firstCoordinate: string
  secondCoordinate: string
  altitude: number
  azimuth: number
  magnitude: number
  type: string
  elongation?: number
  angularSizeArcmin?: number
  distanceAU?: number
  transit?: string
}
export interface ObjectInfo {
  name: string
  nameI18: string
  englishName?: string
  type: string
  typeId?: string
  ra: number
  dec: number
  alt: number
  az: number
  magnitude: number
}

export interface LocSearchItem {
  name: string
  displayName?: string
  lat: number
  lon: number
  alt: number
  planet: string
  country?: string
  region?: string
  province?: string
  searchScore?: number
}

export interface SavedLocation {
  name: string
  lat: number
  lon: number
  alt: number
  planet: string
}

export interface SkyCultureItem {
  id: string
  name: string
  region?: string[]
  classification?: string
  beginTime?: number
  endTime?: number
  constellationCount?: number
  asterismCount?: number
  nativeNameCount?: number
  artCount?: number
  hasZodiac?: boolean
  hasLunarSystem?: boolean
}

export interface SkyCultureRawItem {
  id?: string
  name?: string
  region?: string[]
  classification?: string
  beginTime?: number
  endTime?: number
  constellationCount?: number
  asterismCount?: number
  nativeNameCount?: number
  artCount?: number
  hasZodiac?: boolean
  hasLunarSystem?: boolean
}

export interface SkyCultureArtItem {
  rawPath: string
  index: number
  name?: string
}

export interface SkyCultureDescriptionBlock {
  index: number
  kind: string
  level?: number
  text: string
}

export interface SkyCultureTerritoryEntry {
  name: string
  beginTime: number
  endTime: number
  countryCode: string
  countryCode3: string
  activeAtSimulationTime: boolean
}

export interface SkyCultureTerritoryPolygon {
  name: string
  beginTime: number
  endTime: number
  points: Array<Array<number>>
}

export interface PluginItem {
  id: string
  name: string
  loaded: boolean
  loadAtStartup: boolean
  description?: string
  authors?: string
  contact?: string
  version?: string
  license?: string
  acknowledgements?: string
  hasPreviewImage?: boolean
  source?: string
}

export interface Scenery3dItem {
  id: string
  name: string
  author?: string
  description?: string
  copyright?: string
  source?: string
  descriptionSource?: string
  landscape?: string
  modelScenery?: string
  modelGround?: string
  planet?: string
  latitude?: string
  longitude?: string
  altitude?: number
  timezone?: string
  current?: boolean
}

export interface ShellAction {
  label: ResourceStr
  icon: string
  panel: string
  section?: ResourceStr
}

export interface ObjectDetailField {
  key: string
  value: string
  section: string
}

export interface ObjectDetailModel {
  schemaVersion: number
  state: string
  format: string
  assetKey: string
  assetPath?: string
  registryPath?: string
  fallbackMediaPath?: string
  coordinateFrame?: string
  interactions?: string[]
  offline: boolean
  source?: string
}


export interface StellariumBridgeResponse {
  ok?: boolean
  id?: string
  format?: string
  isTimeNow?: boolean
  pending?: boolean
  progress?: number
  totalDays?: number
  totalCandidates?: number
  found?: boolean
  error?: string
  selectionRequired?: boolean
  name?: string
  englishName?: string
  catalogId?: string
  type?: string
  detailMediaPath?: string
  detailMediaKind?: string
  detailMediaLabel?: string
  detailModel?: ObjectDetailModel
  activeTextureStatus?: string
  activeTextureReadyCount?: number
  activeTextureLoadingCount?: number
  activeTextureNotStartedCount?: number
  activeTexturePendingCount?: number
  activeTextureErrorCount?: number
  descriptionBlocks?: SkyCultureDescriptionBlock[]
  descriptionFormatVersion?: number
  retried?: number
  info?: string
  query?: string
  timeRate?: number
  value?: string
  altitudes?: number[]
  magnitudes?: number[]
  visibleNow?: boolean[]
  locations?: Object[]
  timeZone?: string
  jd?: number
  mjd?: number
  startJD?: number
  endJD?: number
  days?: number
  stepHours?: number
  calculationTime?: string
  localTime?: string
  observerLocation?: string
  coordinateFrame?: string
  latitude?: number
  longitude?: number
  altitude?: number
  meanSiderealTime?: string
  apparentSiderealTime?: string
  meanSiderealHours?: number
  apparentSiderealHours?: number
  equationOfTimeMinutes?: number
  sunAltitude?: number
  sunAzimuth?: number
  moonAltitude?: number
  moonAzimuth?: number
  moonIllumination?: number
  offline?: boolean
  calendarSystem?: string
  julianDateStep?: number
  jdOfToday?: number
  year?: number
  timeText?: string
  fov?: number
  mouseNavigation?: boolean
  mouseZooming?: boolean
  moveKeys?: boolean
  zoomKeys?: boolean
  gravityLabels?: boolean
  autoZoomResets?: boolean
  currentFov?: number
  startupFov?: number
  startupAzimuth?: number
  startupAltitude?: number
  maxFov?: number
  de430Available?: boolean
  de431Available?: boolean
  de440Available?: boolean
  de441Available?: boolean
  de430Active?: boolean
  de431Active?: boolean
  de440Active?: boolean
  de441Active?: boolean
  customInfoMask?: number
  startupTimeMode?: string
  startupTimeStop?: boolean
  todayTime?: string
  presetSkyTime?: number
  deltaTAlgorithm?: string
  deltaTDescription?: string
  j2000Ra?: string
  j2000Dec?: string
  ofDateRa?: string
  ofDateDec?: string
  azimuthText?: string
  altitudeText?: string
  galacticLongitude?: string
  galacticLatitude?: string
  j2000RaDegrees?: number
  j2000DecDegrees?: number
  ofDateRaDegrees?: number
  ofDateDecDegrees?: number
  azimuthDegrees?: number
  altitudeDegrees?: number
  galacticLongitudeDegrees?: number
  galacticLatitudeDegrees?: number
  enabled?: boolean
  minutes?: number
  mosaicCamera?: Object
  msFormat?: boolean
  inverted?: boolean
  enableAtStartup?: boolean
  lineWidth?: number
  equinox?: boolean
  solstices?: boolean
  crossquarters?: boolean
  majorStandstills?: boolean
  minorStandstills?: boolean
  polarCircles?: boolean
  zenithPassage?: boolean
  nadirPassage?: boolean
  selectedObject?: boolean
  selectedObjectAzimuth?: boolean
  selectedObjectHourAngle?: boolean
  currentSun?: boolean
  currentMoon?: boolean
  currentPlanet?: number
  setKey?: string
  setDescription?: string
  setKeys?: string[]
  starCount?: number
  highlightWhenVisible?: boolean
  limitInfo?: boolean
  upperLimb?: boolean
  tabulatedDisplay?: boolean
  extraDecimals?: boolean
  useUtc?: boolean
  checked?: boolean
  hasStart?: boolean
  hasEnd?: boolean
  angleDegrees?: number
  angleText?: string
  fovCircularMarkerSize?: number
  fovRectangularMarkerWidth?: number
  fovRectangularMarkerHeight?: number
  fovRectangularMarkerRotation?: number
  orbitIsolated?: boolean
  orbitMajorPlanets?: boolean
  orbitPlanetsOnly?: boolean
  orbitWithMoons?: boolean
  orbitPermanent?: boolean
  orbitThickness?: number
  orbitColorStyle?: string
  trailIsolated?: boolean
  trailSelectionCount?: number
  trailYears?: number
  trailThickness?: number
  trailColor?: string
  constellationFontSize?: number
  constellationLineThickness?: number
  constellationBoundaryThickness?: number
  constellationHullsThickness?: number
  zodiacThickness?: number
  lunarSystemThickness?: number
  constellationArtIntensity?: number
  constellationLinesFadeDuration?: number
  constellationLabelsFadeDuration?: number
  constellationArtFadeDuration?: number
  constellationBoundariesFadeDuration?: number
  constellationHullsFadeDuration?: number
  zodiacFadeDuration?: number
  lunarSystemFadeDuration?: number
  skyCultureColors?: Record<string, string>
  setting?: string
  color?: string
  asterismFontSize?: number
  asterismLineThickness?: number
  rayHelperThickness?: number
  asterismLinesFadeDuration?: number
  asterismLabelsFadeDuration?: number
  rayHelperFadeDuration?: number
  tracking?: boolean
  viewLock?: boolean
  locationName?: string
  locationRegion?: string
  planetName?: string
  target?: string
  ra?: string
  dec?: string
  hourAngle?: string
  infoMode?: string
  selectedInfoMode?: string
  magnitude?: number
  apparentMagnitude?: number
  airmass?: number
  extinction?: number
  azimuth?: number
  constellation?: string
  culture?: string
  cultureId?: string
  region?: string[]
  classification?: string
  license?: string
  boundariesType?: string
  narration?: string
  description?: string
  hasTerritoryArchive?: boolean
  territorySegmentCount?: number
  territoryActiveSegmentCount?: number
  territorySimulationYear?: number
  territoryArchive?: Array<SkyCultureTerritoryEntry>
  territoryPolygons?: Array<SkyCultureTerritoryPolygon>
  beginTime?: number
  endTime?: number
  constellationCount?: number
  asterismCount?: number
  nativeNameCount?: number
  artCount?: number
  constellationArt?: Array<SkyCultureArtItem>
  hasAsterisms?: boolean
  hasZodiac?: boolean
  hasLunarSystem?: boolean
  screenLabelStyle?: string
  infoLabelStyle?: string
  zodiacLabelStyle?: string
  lunarSystemLabelStyle?: string
  abbreviatedNames?: boolean
  overrideCommonNames?: boolean
  defaultId?: string
  usesCommonNames?: boolean
  // 音乐引擎用：英文类型(便于分支) / 光谱型 / 推算温度(越热音越高)
  objectType?: string
  spType?: string
  temperatureK?: number
  distance?: string
  // 富化后的天体详情字段（selectedObjectJson 扩展）
  size?: string
  rise?: string
  set?: string
  transit?: string
  phase?: number
  elongation?: number
  detailFields?: Array<ObjectDetailField>
  keys?: string[]
  ids?: string[]
  typeIds?: string[]
  types?: string[]
  fuzzy?: boolean[]
  crossLanguage?: boolean[]
  replies?: string
  sent?: string
  mode?: string
  // 天文计算桥接命令的返回体
  ephemeris?: Array<EphemerisRow>
  rtsCalendar?: Array<RtsCalendarDay>
  curve?: Array<AltAzPoint>
  annualElevation?: Array<AnnualElevationPoint>
  observability?: Array<ObservabilityDay>
  lunarElongation?: Array<LunarElongationPoint>
  timeSeries?: Array<PlanetTimeSeriesPoint>
  planetPairDistance?: Array<PlanetPairDistancePoint>
  hecPositions?: Array<HeliocentricPosition>
  hecTime?: string
  celestialPositions?: Array<CelestialPosition>
  coordinateMode?: string
  positionTime?: string
  planetCalc?: Array<PlanetCalcItem>
  firstName?: string
  secondName?: string
  angularAvailable?: boolean
  phenomena?: Array<PhenomenonItem>
  eclipses?: Array<EclipseItem>
  planetaryTransits?: Array<PlanetaryTransitItem>
  moonPhases?: Array<MoonPhaseItem>
  wutTargets?: Array<WutTarget>
  polarScope?: PolarScopeData
  period?: string
  observationTime?: string
  angularSizeAvailable?: boolean
  // 恒星时 / 夜视 / 大气参数
  text?: string
  night?: boolean
  nightMode?: boolean
  luminanceAdaptation?: boolean
  starTwinkle?: boolean
  forcedStarTwinkle?: boolean
  bigStarHalo?: boolean
  starSpiky?: boolean
  twinkleAmount?: number
  bortleScale?: number
	meteorZhr?: number
	meteorZhrMax?: number
  milkyWayIntensity?: number
  zodiacalLight?: boolean
  zodiacalIntensity?: number
  pressure?: number
  temperature?: number
  refractionOn?: boolean
  actionShow_Stars?: boolean
  actionShow_Planets?: boolean
  actionShow_Planets_Orbits?: boolean
  actionShow_Planets_Hints?: boolean
  actionShow_Planets_Trails?: boolean
  actionShow_Planets_EnlargeMoon?: boolean
  actionShow_Nebulas?: boolean
  actionShow_MilkyWay?: boolean
  actionShow_Ground?: boolean
  actionShow_Constellation_Lines?: boolean
  actionShow_Constellation_Labels?: boolean
  actionShow_Constellation_Boundaries?: boolean
  actionShow_Constellation_Art?: boolean
  actionShow_Constellation_Hulls?: boolean
  actionShow_Atmosphere?: boolean
  actionShow_Cardinal_Points?: boolean
  actionShow_Azimuthal_Grid?: boolean
  actionShow_Equatorial_Grid?: boolean
  actionShow_Equatorial_J2000_Grid?: boolean
  actionShow_Ecliptic_Grid?: boolean
  actionShow_Meridian_Line?: boolean
  actionShow_Horizon_Line?: boolean
  actionShow_Planets_Labels?: boolean
  actionShow_Stars_Labels?: boolean
  actionShow_DSO_Labels?: boolean
  actionShow_DSO_Textures?: boolean
  actionShow_Planets_EnlargePlanets?: boolean
  actionShow_Planets_EnlargeSun?: boolean
  actionShow_Planets_ShowMinorBodyMarkers?: boolean
  actionShow_Planets_Nomenclature?: boolean
  actionShow_Fog?: boolean
  actionShow_Ecliptic_Line?: boolean
  actionShow_Equator_Line?: boolean
  actionShow_Galactic_Grid?: boolean
  actionShow_Galactic_Equator_Line?: boolean
  actionShow_Supergalactic_Equator_Line?: boolean
  actionShow_Equator_J2000_Line?: boolean
  actionShow_Ecliptic_J2000_Line?: boolean
  actionShow_Celestial_Poles?: boolean
  actionShow_Ecliptic_Poles?: boolean
  actionShow_Galactic_Poles?: boolean
  actionShow_Equinox_Points?: boolean
  actionShow_Solstice_Points?: boolean
  actionShow_Antisolar_Point?: boolean
  actionShow_Umbra_Circle?: boolean
  actionShow_Penumbra_Circle?: boolean
  actionShow_Compass_Marks?: boolean
  actionShow_Gridlines?: boolean
  actionShow_FOV_Center_Marker?: boolean
  actionShow_FOV_Circular_Marker?: boolean
  actionShow_FOV_Rectangular_Marker?: boolean
  actionShow_Intercardinal_Points?: boolean
  actionShow_Secondary_Intercardinal_Points?: boolean
  actionShow_Tertiary_Intercardinal_Points?: boolean
  actionShow_Prime_Vertical_Line?: boolean
  actionShow_Current_Vertical_Line?: boolean
  actionShow_Colure_Lines?: boolean
  actionShow_Precession_Circles?: boolean
  actionShow_Circumpolar_Circles?: boolean
  actionShow_Invariable_Plane_Line?: boolean
  actionShow_Solar_Equator_Line?: boolean
  actionShow_Ecliptic_J2000_Grid?: boolean
  actionShow_Supergalactic_Grid?: boolean
  actionShow_Fixed_Equatorial_Grid?: boolean
  actionShow_Fixed_Equator_Line?: boolean
  actionShow_Zenith_Nadir?: boolean
  actionShow_Celestial_J2000_Poles?: boolean
  actionShow_Ecliptic_J2000_Poles?: boolean
  actionShow_Equinox_J2000_Points?: boolean
  actionShow_Solstice_J2000_Points?: boolean
  actionShow_Galactic_Center?: boolean
  actionShow_Supergalactic_Poles?: boolean
  actionShow_Apex_Points?: boolean
  actionShow_Umbra_Center_Point?: boolean
  actionShow_Longitude_Line?: boolean
  actionShow_Quadrature_Line?: boolean
  actionShow_Ray_Helpers?: boolean
  actionShow_LandscapeIllumination?: boolean
  actionShow_LandscapeLabels?: boolean
  actionShow_Zodiac?: boolean
  actionShow_LunarSystem?: boolean
  actionShow_Asterism_Lines?: boolean
  actionShow_Asterism_Labels?: boolean
  actionShow_Hips_Surveys?: boolean
  actionShow_Toast_Survey?: boolean
  actionShow_Meteors?: boolean
  meteors?: boolean
  dsoLabels?: boolean
  actionShow_Night_Mode?: boolean
  actionHorizontal_Flip?: boolean
  actionVertical_Flip?: boolean
  items?: string[] | Object[]
  details?: Object[]
  count?: number
  hasMore?: boolean
  offset?: number
  prefix?: string
  moduleId?: string
  // ---- 无缝流转 / 会话状态 (getSessionState / applySessionState) ----
  viewJ2000?: number[]
  fovDeg?: number
  location?: object
  selected?: string
  flags?: object
  current?: string
  rts?: Object
  almanac?: Object
  objectInfoData?: Object
  dsoCounts?: Object
  simTime?: Object
  // 视频录制（帧序列方案，#40）
  dir?: string
  frameCount?: number
  diskFrames?: number
  maxFrames?: number
  recording?: boolean
  fps?: number
  duration?: number
  planets?: string[]
  tonight?: TonightEvents
}

export interface SessionSnapshot {
  viewJ2000?: number[]
  fovDeg?: number
  jd?: number
  location?: object
  selected?: string
  flags?: object
}

export interface SeasonEvent {
  label?: string
  jd?: number
  date?: string
  durationDays?: number
}

// 今夜天文事件聚合（getTonightEvents 返回）
export interface TonightMoon {
  phaseName?: string
  illumination?: number
  age?: number
  rise?: string
  transit?: string
  set?: string
  transitJd?: number
}
export interface TonightSun {
  rise?: string
  transit?: string
  set?: string
  astroTwilightEnd?: string
  astroTwilightStart?: string
  astroTwilightEndJd?: number
  darkWindowHours?: number
}
export interface TonightPlanet {
  name?: string
  englishName?: string
  rise?: string
  transit?: string
  set?: string
  transitJd?: number
  magnitude?: number
  altitude?: number
  visible?: boolean
}
export interface TonightShower {
  name?: string
  zhr?: number
  status?: string
  primeJd?: number
}
export interface TonightSatellites {
  count?: number
  enabled?: boolean
}
export interface TonightEvents {
  date?: string
  moon?: TonightMoon
  sun?: TonightSun
  planets?: Array<TonightPlanet>
  meteorShowers?: Array<TonightShower>
  satellites?: TonightSatellites
}

export interface WutTarget {
  name?: string
  englishName?: string
  type?: string
  jd?: number
  altitude?: number
  azimuth?: number
  magnitude?: number
  angularSizeArcmin?: number
  rise?: string
  transit?: string
  maxAltitude?: number
  set?: string
  constellation?: string
  constellationId?: string
}

// ---- 天文计算（AstroCalc）数据结构 ----
// 星历表：选中天体随日期变化的位置
export interface EphemerisRow {
  jd?: number
  date?: string
  bodyName?: string
  bodyEnglishName?: string
  ra?: string
  dec?: string
  raOfDate?: string
  decOfDate?: string
  altitude?: number
  azimuth?: number
  geometricAltitude?: number
  geometricAzimuth?: number
  polarDistanceDegrees?: number
  polarDistanceJ2000Degrees?: number
  hourAngle?: string
  hourAngleDegrees?: number
  meanSiderealTime?: string
  apparentSiderealTime?: string
  aboveHorizon?: boolean
  airmass?: number
  magnitude?: number
  phase?: number
  distanceAU?: number
  elongationDegrees?: number
  angularSizeArcmin?: number
  heliocentricDistanceAU?: number
}

export interface AstroCalcContext {
  jd?: number
  localTime?: string
  observerLocation?: string
  timeZone?: string
  latitude?: number
  longitude?: number
  altitude?: number
  meanSiderealTime?: string
  apparentSiderealTime?: string
  meanSiderealHours?: number
  apparentSiderealHours?: number
  equationOfTimeMinutes?: number
  sunAltitude?: number
  sunAzimuth?: number
  moonAltitude?: number
  moonAzimuth?: number
  moonIllumination?: number
  offline?: boolean
}
// 每个本地日期的升起、中天、落下数据；对应桌面 AstroCalc 的 RTS 表。
export interface RtsCalendarDay {
  date?: string
  rise?: string
  transit?: string
  set?: string
  riseJD?: number
  transitJD?: number
  setJD?: number
  transitAltitude?: number
  magnitude?: number
  solarElongation?: number
  lunarElongation?: number
  status?: string
}
// 高度/方位角曲线上的一个采样点（t = 距起始时刻的小时数）
export interface AltAzPoint {
  jd?: number
  t?: number
  altitude?: number
  azimuth?: number
  sunAltitude?: number
  moonAltitude?: number
}
// 全年固定时刻高度曲线：与桌面版 Monthly Elevation 使用相同的三日采样。
export interface AnnualElevationPoint {
  jd?: number
  date?: string
  altitude?: number
  azimuth?: number
}
// 月度可见性：每个天文暗夜的目标窗口和月光干扰。
export interface ObservabilityDay {
  date?: string
  bestJD?: number
  peakTime?: string
  maxAltitude?: number
  visibleHours?: number
  darkHours?: number
  moonIllumination?: number
  moonAltitude?: number
}
// 月球距角曲线：目标相对月亮的赤道坐标夹角。
export interface LunarElongationPoint {
  jd?: number
  t?: number
  date?: string
  separation?: number
}
// 双变量行星时间曲线：left 和 right 对应各自选择的物理量。
export interface PlanetTimeSeriesPoint {
  jd?: number
  t?: number
  date?: string
  left?: number
  right?: number
}
// 两个太阳系天体之间的线性距离与表观角距离。
export interface PlanetPairDistancePoint {
  jd?: number
  t?: number
  date?: string
  linearDistance?: number
  angularDistance?: number
}
// 行星计算器条目
export interface PlanetCalcItem {
  name?: string
  englishName?: string
  ra?: string
  dec?: string
  altitude?: number
  azimuth?: number
  magnitude?: number
  distanceAU?: number
  rise?: string
  transit?: string
  set?: string
  illumination?: number
  age?: number
  elongation?: number
  phaseAngle?: number
  phase?: number
  phaseAngleDegrees?: number
  elongationDegrees?: number
  heliocentricDistanceAU?: number
}
// 天象（行星间的合）
export interface PhenomenonItem {
  type?: string
  bodyA?: string
  bodyB?: string
  jd?: number
  date?: string
  separation?: number
  metricLabel?: string
  metricUnit?: string
}
// 日食 / 月食
export interface EclipseItem {
  kind?: string
  type?: string
  jd?: number
  date?: string
  magnitude?: number
  saros?: number
  gamma?: number
  pathWidthKm?: number
  durationMin?: number
  centralLat?: number
  centralLng?: number
  localVisible?: boolean
  localMagnitude?: number
  localMax?: string
  localSunAltitude?: number
  localFirstContact?: string
  localLastContact?: string
  localFirstContactLabel?: string
  localLastContactLabel?: string
  localCentralType?: string
  localCentralStart?: string
  localCentralEnd?: string
  penumbralMagnitude?: number
  umbralMagnitude?: number
  localMoonAltitude?: number
  visibility?: string
  note?: string
}
// 水星、金星凌日：接触时刻和可见性均以当前观测地点计算。
export interface PlanetaryTransitItem {
  planet?: string
  jd?: number
  date?: string
  firstContact?: string
  secondContact?: string
  middle?: string
  thirdContact?: string
  lastContact?: string
  firstContactVisible?: boolean
  secondContactVisible?: boolean
  middleVisible?: boolean
  thirdContactVisible?: boolean
  lastContactVisible?: boolean
  magnitude?: number
  minimumSeparation?: number
  durationMin?: number
  observableDurationMin?: number
  localVisible?: boolean
  sunAltitude?: number
}
// 月相预报：以月球相对太阳的地心黄经差为准。
export interface MoonPhaseItem {
  phase?: string
  jd?: number
  date?: string
  illumination?: number
  altitude?: number
  azimuth?: number
  rise?: string
  transit?: string
  set?: string
}
