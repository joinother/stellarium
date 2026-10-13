// 「图层」面板（activePanel === 'layers'）的开关状态簇。
//
// 持有六组图层开关布尔值：天空与恒星、太阳系、深空与流星、地平与景观、标记与网格、
// 星座与星空文化。宿主以 @State 持有，UI 侧经 @Prop / @ObjectLink 读取，写回由宿主回调完成。
// 不持有端口与 hooks，native 桥与图层预设组装由宿主负责。
//
// 只放数据，不 import UI / NAPI。
@Observed
export class LayerStore {
  // —— 天空与恒星 ——
  stars: boolean = true
  milkyWay: boolean = true
  starLabels: boolean = false
  atmosphere: boolean = true
  luminanceAdaptation: boolean = true
  starTwinkle: boolean = true
  forcedStarTwinkle: boolean = false
  bigStarHalo: boolean = true
  starSpiky: boolean = false
  zodiacalLight: boolean = true

  // —— 太阳系 ——
  planets: boolean = true
  planetOrbits: boolean = false
  planetHints: boolean = false
  planetTrails: boolean = false
  minorBodyMarkers: boolean = false
  planetNomenclature: boolean = false
  enlargeMoon: boolean = false
  enlargePlanets: boolean = false
  enlargeSun: boolean = false

  // —— 深空与流星 ——
  nebulae: boolean = false
  dsoLabels: boolean = true
  dsoTextures: boolean = true
  meteors: boolean = false

  // —— 地平与景观 ——
  ground: boolean = true
  mistHorizon: boolean = true
  fogEffect: boolean = false
  landscapeIllum: boolean = false
  landscapeLabels: boolean = false
  flipHoriz: boolean = false
  flipVert: boolean = false
  cardinalPoints: boolean = true
  compassMarks: boolean = false

  // —— 标记：网格 ——
  gridlinesMaster: boolean = false
  equatorialGrid: boolean = false
  azimuthGrid: boolean = false
  galacticGrid: boolean = false
  eclipticGrid: boolean = false
  equatorialJ2000Grid: boolean = false
  eclipticJ2000Grid: boolean = false
  supergalacticGrid: boolean = false
  fixedEquatorialGrid: boolean = false

  // —— 标记：线 ——
  equatorLine: boolean = false
  eclipticLine: boolean = true
  meridianLine: boolean = false
  horizonLine: boolean = false
  galacticEquator: boolean = false
  supergalacticEq: boolean = false
  equJ2000Line: boolean = false
  eclJ2000Line: boolean = false
  primeVerticalLine: boolean = false
  currentVerticalLine: boolean = false
  colureLines: boolean = false
  precessionCircles: boolean = false
  circumpolarCircles: boolean = false
  invariantPlaneLine: boolean = false
  solarEquatorLine: boolean = false
  fixedEquatorLine: boolean = false
  longitudeLine: boolean = false
  quadratureLine: boolean = false

  // —— 标记：点 ——
  celestialPoles: boolean = false
  eclipticPoles: boolean = false
  galacticPoles: boolean = false
  equinoxPoints: boolean = false
  solsticePoints: boolean = false
  antisolarPoint: boolean = false
  umbraCircle: boolean = false
  penumbraCircle: boolean = false
  zenithNadir: boolean = false
  celestialJ2000Poles: boolean = false
  eclipticJ2000Poles: boolean = false
  equinoxJ2000Pts: boolean = false
  solsticeJ2000Pts: boolean = false
  galacticCenter: boolean = false
  supergalacticPoles: boolean = false
  apexPoints: boolean = false
  umbraCenter: boolean = false

  // —— 标记：方位细分 ——
  intercardinalPts: boolean = false
  secondaryIntercardinalPts: boolean = false
  tertiaryIntercardinalPts: boolean = false

  // —— 标记：视场 ——
  fovMarker: boolean = false
  fovCircularMarker: boolean = false
  fovRectangularMarker: boolean = false

  // —— 星座与星空文化 ——
  constellationLines: boolean = false
  constellationLabels: boolean = false
  constellationBoundaries: boolean = false
  constellationHulls: boolean = false
  constellationArt: boolean = false
  zodiac: boolean = false
  lunarSystem: boolean = false
  asterismLines: boolean = false
  asterismLabels: boolean = false
  rayHelpers: boolean = false

  // —— 巡天（离线 AppGallery 构建下隐藏）——
  hipsSurveys: boolean = false
  toastSurvey: boolean = false
}
