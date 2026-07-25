// Auto-extracted from MainWindowNativeNode.ets — shared types & constants
// Do NOT add @Component or @Builder here; this file is import-only.

export interface LangOption { code: string; name: ResourceStr }

export interface HierCity {
  n: string
  la: number
  lo: number
  al: number
  p: number
}

export interface CatOption {
  code: string
  label: ResourceStr
}

export interface NameItem {
  name: string
  zh?: ResourceStr
}

// 天体中文别名表：用于把 Stellarium 核心返回的拉丁/英文名（Jupiter、M31、Orion…）
// 映射成中文显示，并支撑中文/拼音模糊搜索。py 为拼音（无声调），用于「muxing」「jup」这类输入命中。
export interface AliasEntry {
  zh: string
  py: string
  en: string
  type: string
}

// 搜索建议项：zh 用于显示，en 用于真正发给核心检索（核心只认英文/标准标识）。
export interface SearchSug {
  zh: string
  en: string
}

export interface AliasHit {
  zh: string
  en: string
  score: number
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
}

export interface PlanetPosition {
  name: string
  altitude: number
  azimuth: number
  magnitude: number
}
export interface ObjectInfo {
  name: string
  nameI18: string
  type: string
  ra: number
  dec: number
  alt: number
  az: number
  magnitude: number
}

export interface SkyCultureItem {
  id: string
  name: string
}

export interface PluginItem {
  id: string
  name: string
  loaded: boolean
  loadAtStartup: boolean
}

export interface ShellAction {
  label: ResourceStr
  icon: string
  panel: string
}

// 常用天体中文别名表（行星/太阳/月亮 + 亮星 + 著名深空 + 常见星座）。
// 核心默认返回拉丁/英文名，这里把它们翻成中文显示；同时用 en/py 做模糊匹配。
export const ALIAS_LIST: AliasEntry[] = [
  // 行星 / 太阳 / 月亮
  { zh: '水星', py: 'shuixing', en: 'Mercury', type: 'planet' },
  { zh: '金星', py: 'jinxing', en: 'Venus', type: 'planet' },
  { zh: '地球', py: 'diqiu', en: 'Earth', type: 'planet' },
  { zh: '火星', py: 'huoxing', en: 'Mars', type: 'planet' },
  { zh: '木星', py: 'muxing', en: 'Jupiter', type: 'planet' },
  { zh: '土星', py: 'tuxing', en: 'Saturn', type: 'planet' },
  { zh: '天王星', py: 'tianwangxing', en: 'Uranus', type: 'planet' },
  { zh: '海王星', py: 'haiwangxing', en: 'Neptune', type: 'planet' },
  { zh: '冥王星', py: 'mingwangxing', en: 'Pluto', type: 'planet' },
  { zh: '太阳', py: 'taiyang', en: 'Sun', type: 'star' },
  { zh: '月球', py: 'yueqiu', en: 'Moon', type: 'moon' },
  // 亮星
  { zh: '天狼星', py: 'tianlangxing', en: 'Sirius', type: 'star' },
  { zh: '老人星', py: 'laorenxing', en: 'Canopus', type: 'star' },
  { zh: '大角星', py: 'dajiaoxing', en: 'Arcturus', type: 'star' },
  { zh: '织女星', py: 'zhinvxing', en: 'Vega', type: 'star' },
  { zh: '五车二', py: 'wucheer', en: 'Capella', type: 'star' },
  { zh: '参宿七', py: 'shenxiuqi', en: 'Rigel', type: 'star' },
  { zh: '南河三', py: 'nanhesan', en: 'Procyon', type: 'star' },
  { zh: '水委一', py: 'shuiweiyi', en: 'Achernar', type: 'star' },
  { zh: '参宿四', py: 'shenxiusi', en: 'Betelgeuse', type: 'star' },
  { zh: '马腹一', py: 'mafuyi', en: 'Hadar', type: 'star' },
  { zh: '牛郎星', py: 'niulangxing', en: 'Altair', type: 'star' },
  { zh: '十字架二', py: 'shizijiaer', en: 'Acrux', type: 'star' },
  { zh: '毕宿五', py: 'bixuwu', en: 'Aldebaran', type: 'star' },
  { zh: '心宿二', py: 'xinxuer', en: 'Antares', type: 'star' },
  { zh: '角宿一', py: 'jiaoxuyi', en: 'Spica', type: 'star' },
  { zh: '北河三', py: 'beihesan', en: 'Pollux', type: 'star' },
  { zh: '北落师门', py: 'beiluoshimen', en: 'Fomalhaut', type: 'star' },
  { zh: '天津四', py: 'tianjinsi', en: 'Deneb', type: 'star' },
  { zh: '轩辕十四', py: 'xuanyuanshisi', en: 'Regulus', type: 'star' },
  { zh: '北河二', py: 'beiheer', en: 'Castor', type: 'star' },
  { zh: '参宿五', py: 'shenxiuwu', en: 'Bellatrix', type: 'star' },
  { zh: '十字架三', py: 'shizijiasan', en: 'Mimosa', type: 'star' },
  { zh: '参宿一', py: 'shenxiuyi', en: 'Alnilam', type: 'star' },
  { zh: '参宿三', py: 'shenxiusan', en: 'Alnitak', type: 'star' },
  { zh: '天枢', py: 'tianshu', en: 'Dubhe', type: 'star' },
  { zh: '天璇', py: 'tianxuan', en: 'Merak', type: 'star' },
  { zh: '天玑', py: 'tianji', en: 'Phecda', type: 'star' },
  { zh: '天权', py: 'tianquan', en: 'Megrez', type: 'star' },
  { zh: '玉衡', py: 'yuheng', en: 'Alioth', type: 'star' },
  { zh: '开阳', py: 'kaiyang', en: 'Mizar', type: 'star' },
  { zh: '摇光', py: 'yaoguang', en: 'Alkaid', type: 'star' },
  { zh: '北极星', py: 'beijixing', en: 'Polaris', type: 'star' },
  { zh: '娄宿三', py: 'louxisan', en: 'Hamal', type: 'star' },
  { zh: '大陵五', py: 'dalingwu', en: 'Algol', type: 'star' },
  { zh: '五车三', py: 'wuchesan', en: 'Menkalinan', type: 'star' },
  { zh: '壁宿一', py: 'bixuyi', en: 'Algenib', type: 'star' },
  { zh: '奎宿九', py: 'kuixiujiu', en: 'Mirach', type: 'star' },
  { zh: '天船三', py: 'tianchuansan', en: 'Mirfak', type: 'star' },
  { zh: '北极二', py: 'beijier', en: 'Kochab', type: 'star' },
  // 著名深空
  { zh: '仙女座星系', py: 'xianvzuoyinxing', en: 'M31', type: 'galaxy' },
  { zh: 'M32', py: '', en: 'M32', type: 'galaxy' },
  { zh: 'M110', py: '', en: 'M110', type: 'galaxy' },
  { zh: '三角座星系', py: 'sanjiiaozuoyinxing', en: 'M33', type: 'galaxy' },
  { zh: '猎户座大星云', py: 'liehuzuodaxingyun', en: 'M42', type: 'nebula' },
  { zh: 'M43', py: '', en: 'M43', type: 'nebula' },
  { zh: '昴星团', py: 'maoxingtuan', en: 'M45', type: 'cluster' },
  { zh: '蟹状星云', py: 'xiezhuangxingyun', en: 'M1', type: 'nebula' },
  { zh: '礁湖星云', py: 'jiaohuxingyun', en: 'M8', type: 'nebula' },
  { zh: '武仙座球状星团', py: 'wuxianzuoqiuzhuangxingtuan', en: 'M13', type: 'cluster' },
  { zh: '哑铃星云', py: 'yalingxingyun', en: 'M27', type: 'nebula' },
  { zh: '涡状星系', py: 'wozhuangyinxing', en: 'M51', type: 'galaxy' },
  { zh: '指环星云', py: 'zhihuanxingyun', en: 'M57', type: 'nebula' },
  { zh: '波德星系', py: 'bodeyinxing', en: 'M81', type: 'galaxy' },
  { zh: '雪茄星系', py: 'xuejiayinxing', en: 'M82', type: 'galaxy' },
  { zh: '草帽星系', py: 'caomaoyinxing', en: 'M104', type: 'galaxy' },
  { zh: '北美洲星云', py: 'beimeizhouxingyun', en: 'NGC 7000', type: 'nebula' },
  { zh: '玫瑰星云', py: 'meiguixingyun', en: 'NGC 2244', type: 'nebula' },
  { zh: '双星团', py: 'shuangxingtuan', en: 'Double Cluster', type: 'cluster' },
  { zh: '蜂巢星团', py: 'fengchaoxingtuan', en: 'M44', type: 'cluster' },
  { zh: '野鸭星团', py: 'yeyaxingtuan', en: 'M11', type: 'cluster' },
  { zh: '马头星云', py: 'matouxingyun', en: 'IC 434', type: 'nebula' },
  { zh: '加州星云', py: 'jiazhouxingyun', en: 'NGC 1499', type: 'nebula' },
  // 常见星座
  { zh: '仙女座', py: '', en: 'Andromeda', type: 'constellation' },
  { zh: '宝瓶座', py: '', en: 'Aquarius', type: 'constellation' },
  { zh: '天鹰座', py: '', en: 'Aquila', type: 'constellation' },
  { zh: '白羊座', py: '', en: 'Aries', type: 'constellation' },
  { zh: '御夫座', py: '', en: 'Auriga', type: 'constellation' },
  { zh: '牧夫座', py: '', en: 'Boötes', type: 'constellation' },
  { zh: '巨蟹座', py: '', en: 'Cancer', type: 'constellation' },
  { zh: '猎犬座', py: '', en: 'Canes Venatici', type: 'constellation' },
  { zh: '大犬座', py: '', en: 'Canis Major', type: 'constellation' },
  { zh: '小犬座', py: '', en: 'Canis Minor', type: 'constellation' },
  { zh: '摩羯座', py: '', en: 'Capricornus', type: 'constellation' },
  { zh: '船底座', py: '', en: 'Carina', type: 'constellation' },
  { zh: '仙后座', py: '', en: 'Cassiopeia', type: 'constellation' },
  { zh: '半人马座', py: '', en: 'Centaurus', type: 'constellation' },
  { zh: '仙王座', py: '', en: 'Cepheus', type: 'constellation' },
  { zh: '鲸鱼座', py: '', en: 'Cetus', type: 'constellation' },
  { zh: '后发座', py: '', en: 'Coma Berenices', type: 'constellation' },
  { zh: '北冕座', py: '', en: 'Corona Borealis', type: 'constellation' },
  { zh: '乌鸦座', py: '', en: 'Corvus', type: 'constellation' },
  { zh: '巨爵座', py: '', en: 'Crater', type: 'constellation' },
  { zh: '天鹅座', py: '', en: 'Cygnus', type: 'constellation' },
  { zh: '海豚座', py: '', en: 'Delphinus', type: 'constellation' },
  { zh: '天龙座', py: '', en: 'Draco', type: 'constellation' },
  { zh: '波江座', py: '', en: 'Eridanus', type: 'constellation' },
  { zh: '双子座', py: '', en: 'Gemini', type: 'constellation' },
  { zh: '天鹤座', py: '', en: 'Grus', type: 'constellation' },
  { zh: '武仙座', py: '', en: 'Hercules', type: 'constellation' },
  { zh: '长蛇座', py: '', en: 'Hydra', type: 'constellation' },
  { zh: '狮子座', py: '', en: 'Leo', type: 'constellation' },
  { zh: '小狮座', py: '', en: 'Leo Minor', type: 'constellation' },
  { zh: '天兔座', py: '', en: 'Lepus', type: 'constellation' },
  { zh: '天秤座', py: '', en: 'Libra', type: 'constellation' },
  { zh: '天琴座', py: '', en: 'Lyra', type: 'constellation' },
  { zh: '麒麟座', py: '', en: 'Monoceros', type: 'constellation' },
  { zh: '蛇夫座', py: '', en: 'Ophiuchus', type: 'constellation' },
  { zh: '猎户座', py: '', en: 'Orion', type: 'constellation' },
  { zh: '飞马座', py: '', en: 'Pegasus', type: 'constellation' },
  { zh: '英仙座', py: '', en: 'Perseus', type: 'constellation' },
  { zh: '凤凰座', py: '', en: 'Phoenix', type: 'constellation' },
  { zh: '双鱼座', py: '', en: 'Pisces', type: 'constellation' },
  { zh: '南鱼座', py: '', en: 'Piscis Austrinus', type: 'constellation' },
  { zh: '人马座', py: '', en: 'Sagittarius', type: 'constellation' },
  { zh: '天蝎座', py: '', en: 'Scorpius', type: 'constellation' },
  { zh: '巨蛇座', py: '', en: 'Serpens', type: 'constellation' },
  { zh: '金牛座', py: '', en: 'Taurus', type: 'constellation' },
  { zh: '三角座', py: '', en: 'Triangulum', type: 'constellation' },
  { zh: '大熊座', py: '', en: 'Ursa Major', type: 'constellation' },
  { zh: '小熊座', py: '', en: 'Ursa Minor', type: 'constellation' },
  { zh: '室女座', py: '', en: 'Virgo', type: 'constellation' },
  { zh: '狐狸座', py: '', en: 'Vulpecula', type: 'constellation' },
]

export interface StellariumBridgeResponse {
  ok?: boolean
  pending?: boolean
  found?: boolean
  error?: string
  name?: string
  englishName?: string
  type?: string
  info?: string
  query?: string
  timeRate?: number
  jd?: number
  timeText?: string
  fov?: number
  tracking?: boolean
  locationName?: string
  locationRegion?: string
  planetName?: string
  latitude?: number
  longitude?: number
  altitude?: number
  target?: string
  ra?: string
  dec?: string
  magnitude?: number
  azimuth?: number
  constellation?: string
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
  replies?: string
  sent?: string
  mode?: string
  actionShow_Stars?: boolean
  actionShow_Planets?: boolean
  actionShow_Planets_Orbits?: boolean
  actionShow_Planets_Hints?: boolean
  actionShow_Nebulas?: boolean
  actionShow_MilkyWay?: boolean
  actionShow_Ground?: boolean
  actionShow_Constellation_Lines?: boolean
  actionShow_Constellation_Labels?: boolean
  actionShow_Constellation_Boundaries?: boolean
  actionShow_Constellation_Art?: boolean
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
  actionShow_Meteors?: boolean
  meteors?: boolean
  dsoLabels?: boolean
  autoZoomResets?: boolean
  actionShow_Night_Mode?: boolean
  actionHorizontal_Flip?: boolean
  actionVertical_Flip?: boolean
  items?: string[] | Object[]
  count?: number
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
