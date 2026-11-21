export interface CalendarObserverContext {
  latitude?: number
  longitude?: number
  bortleScale?: number
  observerPlanet?: string
}

export function calendarText(language: string, chinese: string, english: string): string {
  return language.toLowerCase().startsWith('zh') ? chinese : english
}

export function calendarMonthTitle(language: string, year: number, month: number): string {
  return calendarText(language, `${year} 年 ${month} 月`, `${year}-${String(month).padStart(2, '0')}`)
}

export function calendarWeekdays(language: string): string[] {
  return language.toLowerCase().startsWith('zh') ? ['日', '一', '二', '三', '四', '五', '六'] :
    ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
}

export function calendarSolarTermTitle(language: string, index: number): string {
  const chinese: string[] = ['小寒', '大寒', '立春', '雨水', '惊蛰', '春分', '清明', '谷雨',
    '立夏', '小满', '芒种', '夏至', '小暑', '大暑', '立秋', '处暑', '白露', '秋分', '寒露', '霜降', '立冬', '小雪', '大雪', '冬至']
  const english: string[] = ['Minor Cold', 'Major Cold', 'Start of Spring', 'Rain Water', 'Awakening of Insects',
    'March equinox', 'Clear and Bright', 'Grain Rain', 'Start of Summer', 'Grain Full', 'Grain in Ear', 'June solstice',
    'Minor Heat', 'Major Heat', 'Start of Autumn', 'End of Heat', 'White Dew', 'September equinox', 'Cold Dew',
    'Frost Descent', 'Start of Winter', 'Minor Snow', 'Major Snow', 'December solstice']
  return index >= 0 && index < 24 ? calendarText(language, chinese[index], english[index]) : ''
}

export function calendarMoonPhaseTitle(language: string, index: number): string {
  const chinese: string[] = ['新月', '上弦', '满月', '下弦']
  const english: string[] = ['New moon', 'First quarter', 'Full moon', 'Last quarter']
  return index >= 0 && index < 4 ? calendarText(language, chinese[index], english[index]) : ''
}

export function calendarPlanetName(language: string, englishName: string): string {
  const map: Record<string, string> = {
    Sun: '太阳', Moon: '月球', Earth: '地球', Mercury: '水星', Venus: '金星',
    Mars: '火星', Phobos: '火卫一', Deimos: '火卫二',
    Jupiter: '木星', Io: '木卫一', Europa: '木卫二', Ganymede: '木卫三', Callisto: '木卫四',
    Saturn: '土星', Titan: '土卫六', Enceladus: '土卫二', Rhea: '土卫五',
    Uranus: '天王星', Titania: '天卫三',
    Neptune: '海王星', Triton: '海卫一',
    Pluto: '冥王星', Charon: '冥卫一',
    Regulus: '轩辕十四', Aldebaran: '毕宿五', Spica: '角宿一', Antares: '心宿二'
  }
  return language.toLowerCase().startsWith('zh') ? (map[englishName] ?? englishName) : englishName
}

export function calendarClockText(atMs: number): string {
  const date = new Date(atMs)
  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
}

// 解析 Meeus 近似太阳-月球黄经距角（0°=新月，90°=上弦，180°=满月，270°=下弦），误差 < 1°。
export function calendarMoonElongationDeg(jd: number): number {
  const t = (jd - 2451545.0) / 36525.0
  const rad = Math.PI / 180.0
  const d = 297.8501921 + 445267.1114034 * t
  const m = 357.5291092 + 35999.0502909 * t
  const mp = 134.9633964 + 477198.8675055 * t
  const elong = d
    + 6.289 * Math.sin(mp * rad)
    - 1.274 * Math.sin((mp - 2 * d) * rad)
    + 0.658 * Math.sin(2 * d * rad)
    - 0.214 * Math.sin(2 * mp * rad)
    - 1.856 * Math.sin(m * rad)
  return ((elong % 360) + 360) % 360
}

// Bortle 1–9 映射至 7 级暗空阶梯（0 = 极暗荒野，6 = 核心城区）。
function bortleToLightTier(bortleScale?: number): number {
  if (bortleScale === undefined || !Number.isFinite(bortleScale)) return -1
  const b = Math.round(bortleScale)
  if (b <= 1) return 0
  if (b === 2) return 1
  if (b <= 4) return 2
  if (b === 5) return 3
  if (b === 6) return 4
  if (b === 7) return 5
  return 6
}

// 年度重点流星雨背景特征（典型 ZHR 与观测特点），用于丰富详情页说明。
function calendarMeteorProfile(language: string, showerCode?: string): string {
  if (!showerCode) return ''
  const zh: Record<string, string> = {
    QUA: '象限仪座流星雨是年度三大流星雨之一，典型极大 ZHR 约 120，峰值持续时间较短，适合提前守候。',
    LYR: '天琴座流星雨典型 ZHR 约 18，常伴有拖尾持久的明亮火流星。',
    ETA: '宝瓶座η流星雨源自哈雷彗星尘埃带，典型 ZHR 约 50，黎明前辐射点升高后表现最佳。',
    SDA: '宝瓶座δ南流星雨活跃期绵长，典型 ZHR 约 25，低纬度与南半球观测高度更占优势。',
    PER: '英仙座流星雨是北半球夏季最负盛名的年度流星雨，典型 ZHR 约 100，流星明亮且速度快。',
    ORI: '猎户座流星雨同样源自哈雷彗星，典型 ZHR 约 20，流星速度极快、常留余迹。',
    STA: '金牛座南流星雨节奏舒缓、流量不高（ZHR 约 5），但偶有高亮火流星划过夜空。',
    NTA: '金牛座北流星雨流量平和（ZHR 约 5），流星体速度较慢，偶现醒目火流星。',
    LEO: '狮子座流星雨以高速著称（约 71 km/s），常规年份 ZHR 约 15，适合后半夜面向东方守候。',
    GEM: '双子座流星雨是全年最稳定丰沛的流星雨之一，典型 ZHR 可达 120，整夜皆宜且多亮流星。',
    URS: '小熊座流星雨活跃于冬至前后，典型 ZHR 约 10，北半球中高纬度整夜可见辐射点。',
    DRA: '天龙座流星雨辐射点傍晚即高悬北方，常规年份流量温和，适合上半夜观测。'
  }
  const en: Record<string, string> = {
    QUA: 'One of the year’s strongest showers (typical ZHR ~120) with a brief, sharp peak worth watching ahead of time.',
    LYR: 'Typical ZHR ~18, known for crisp meteors and occasional bright fireballs.',
    ETA: 'Born from Halley’s Comet debris (typical ZHR ~50); best seen in the pre-dawn hours as the radiant climbs.',
    SDA: 'A broad summer stream (typical ZHR ~25) favoring southern and low-northern latitudes.',
    PER: 'A classic northern-summer shower (typical ZHR ~100) delivering swift, bright meteors.',
    ORI: 'Shed by Halley’s Comet (typical ZHR ~20), producing fast streaks that often leave glowing trains.',
    STA: 'Modest rates (ZHR ~5) with slow meteors and occasional striking fireballs.',
    NTA: 'Modest rates (ZHR ~5) with slow meteors and a chance of bright fireballs.',
    LEO: 'Famed for ultra-fast meteors (~71 km/s; typical ZHR ~15), best viewed after midnight.',
    GEM: 'The year’s most reliable, prolific shower (typical ZHR ~120), rich in bright meteors all night.',
    URS: 'Active around the December solstice (typical ZHR ~10), circumpolar across mid-northern latitudes.',
    DRA: 'Best watched in the early evening hours when the northern radiant sits highest.'
  }
  const text = language.toLowerCase().startsWith('zh') ? zh[showerCode] : en[showerCode]
  return text ?? ''
}

// 按月日距角评估当晚月光对流星观测的影响（9 级细分）。
export function calendarMeteorMoonImpact(language: string, elongDeg: number): string {
  const e = ((elongDeg % 360) + 360) % 360
  if (e < 22 || e >= 338) {
    return calendarText(language,
      '当晚恰逢新月，整夜几乎无月光干扰，暗弱流星也能清晰现身。',
      'A new moon leaves the night completely dark, allowing even faint meteors to stand out.')
  }
  if (e < 68) {
    return calendarText(language,
      '当晚为蛾眉月，淡薄月光仅在傍晚短暂影响低空，入夜后很快迎来纯黑夜空。',
      'A slender waxing crescent sets early, leaving most of the night free of moonlight.')
  }
  if (e < 112) {
    return calendarText(language,
      '当晚为上弦月，月光主要影响上半夜，午夜月落后仍有充裕的无月暗空窗口。',
      'A first quarter moon brightens the evening hours, but sets around midnight to open a dark viewing window.')
  }
  if (e < 155) {
    return calendarText(language,
      '当晚为盈凸月，夜间多数时段受月光干扰，不过黎明前月落后仍可抓紧守候一段暗空。',
      'A waxing gibbous moon brightens much of the night, though a brief darker window opens before dawn after moonset.')
  }
  if (e < 172 || (e >= 188 && e < 205)) {
    return calendarText(language,
      '当晚接近满月，强烈月光会淹没较暗流星，建议背向月亮、重点捕捉明亮火流星。',
      'A nearly full moon washes out fainter meteors — face away from the Moon and watch for bright fireballs.')
  }
  if (e < 188) {
    return calendarText(language,
      '当晚正逢满月，整夜月光强烈，仅有较亮的流星与火流星能够脱颖而出。',
      'A full moon shines all night, leaving only the brightest meteors and fireballs clearly visible.')
  }
  if (e < 248) {
    return calendarText(language,
      '当晚为亏凸月，较强月光会压缩可见流量，尽量利用遮挡物避开月面直射并守候亮流星。',
      'A waning gibbous moon noticeably reduces faint counts; shield your eyes from direct moonlight and watch for brighter streaks.')
  }
  if (e < 292) {
    return calendarText(language,
      '当晚为下弦月，上半夜无月光干扰、适合提前观星，下半夜月出后暗流星将明显减少。',
      'A last quarter moon leaves evening skies dark before rising after midnight to wash out fainter meteors.')
  }
  return calendarText(language,
    '当晚为残月，月亮要到黎明前才会升起，深夜核心观测时段几乎不受月光影响。',
    'A waning crescent moon rises only shortly before dawn, leaving midnight viewing virtually unaffected.')
}

// 按当前 Bortle 暗空等级与当晚月光干扰状态（95° ≤ 距角 < 275° 判为有月光干扰）组合光污染建议。
export function calendarMeteorLightImpact(language: string, bortleScale: number | undefined, elongDeg: number): string {
  const tier = bortleToLightTier(bortleScale)
  if (tier < 0) return ''
  const moonInterferes = elongDeg >= 95 && elongDeg < 275
  const zhMoon: string[] = [
    '好在当前观测地几乎不受人造光污染影响，待月光减弱或背月观测时仍可收获可观流量。',
    '好在当前观测地暗空底质极佳，人造光污染极低，在月光较弱时段仍能看到不少流星。',
    '当前观测地受人造光污染影响较小，待月亮落山或低垂时依旧有不错的观测表现。',
    '同时周边存在一定光污染，叠加月光会进一步降低可见流星数量。',
    '此外周边存在较明显光污染，与月光叠加后仅易目视较亮流星。',
    '叠加当前区域较重的光污染，建议避开灯源并优先守候明亮火流星。',
    '叠加当前城区严重光污染，仅极亮火流星可见，建议驾车前往远离市区的暗空地带。'
  ]
  const zhNoMoon: string[] = [
    '加之当前观测地几乎不受人造光污染影响，整体暗空条件堪称顶级。',
    '加之当前观测地暗空纯净、光污染极低，拥有非常理想的流星观测条件。',
    '同时当前观测地受人造光污染影响不大，整体观测条件良好。',
    '不过周边存在一定人造光污染，实际可见数量会略低于暗空理论值。',
    '不过当前区域光污染较明显，若能前往郊外开阔暗空处，体验会提升不少。',
    '不过当前区域光污染较重，建议远离城区灯火以捕捉更多暗弱流星。',
    '不过当前城区光污染严重，强烈建议前往远离市区的开阔暗空地点观测。'
  ]
  const enMoon: string[] = [
    'Fortunately, your observing site is virtually free of light pollution, so dark windows will still yield strong rates.',
    'Fortunately, your site enjoys very dark skies with minimal light pollution whenever moonlight eases.',
    'Light pollution at your site is modest, so darker intervals still offer rewarding views.',
    'Combined with moderate local light pollution, expect noticeably lower visual counts.',
    'Combined with significant local light pollution, mostly brighter meteors will break through.',
    'With heavy local light pollution on top of moonlight, shield yourself from nearby lights and watch for bright fireballs.',
    'With severe urban light pollution on top of moonlight, only the brightest fireballs will show unless you travel to darker skies.'
  ]
  const enNoMoon: string[] = [
    'Paired with virtually zero local light pollution, observing conditions are truly exceptional.',
    'Paired with pristine dark skies and minimal light pollution, observing conditions are excellent.',
    'With only modest local light pollution, overall viewing conditions are very good.',
    'Moderate local light pollution will trim fainter counts somewhat below dark-sky estimates.',
    'Significant local light pollution will hide fainter streaks — heading out to darker rural skies is well worth it.',
    'Heavy local light pollution will limit counts; traveling away from city lights will dramatically improve the show.',
    'Severe urban light pollution will mask most meteors; travel to a dark, open site outside the city for the best view.'
  ]
  return calendarText(language, moonInterferes ? zhMoon[tier] : zhNoMoon[tier], moonInterferes ? enMoon[tier] : enNoMoon[tier])
}

export function calendarMeteorShowerBody(
  language: string,
  titleZh: string,
  titleEn: string,
  jd: number,
  showerCode?: string,
  context?: CalendarObserverContext
): string {
  const elong = calendarMoonElongationDeg(jd)
  const lead = calendarText(language,
    `${titleZh}预计在此时段迎来活跃高峰（目录模型估算）。建议寻找视野开阔、远离直射灯光的地点，让眼睛适应黑暗 15–20 分钟后再抬头巡视全天。`,
    `${titleEn} is expected to reach peak activity during this window (catalog estimate). Choose an open site away from direct lights and let your eyes dark-adapt for 15–20 minutes.`)
  const profile = calendarMeteorProfile(language, showerCode)
  const moonLine = calendarMeteorMoonImpact(language, elong)
  const lightLine = calendarMeteorLightImpact(language, context?.bortleScale, elong)
  const note = calendarText(language,
    '实际可见流量还会受辐射点高度与天气云量影响；时刻基于流星雨目录估算，非当年精准爆发预报。',
    'Actual rates also depend on radiant altitude and local sky clarity; timing is a catalog estimate rather than an outburst forecast.')
  const parts: string[] = [lead]
  if (profile.length > 0) parts.push(profile)
  parts.push(moonLine)
  if (lightLine.length > 0) parts.push(lightLine)
  parts.push(note)
  return parts.join(language.toLowerCase().startsWith('zh') ? '' : ' ')
}

function solarTermSeasonHighlight(language: string, index: number, southern: boolean): string {
  // index 0..23: 0=小寒(Jan)..5=春分(Mar)..11=夏至(Jun)..17=秋分(Sep)..23=冬至(Dec)
  // Seasons mirror across hemispheres.
  const seasonIdx = Math.floor(((index + 21) % 24) / 6) // 0=spring(N), 1=summer(N), 2=autumn(N), 3=winter(N)
  const effective = southern ? (seasonIdx + 2) % 4 : seasonIdx
  const zh: string[] = [
    '春季夜空星系云集，狮子座、室女座与北斗高悬，适合深空星系巡礼。',
    '夏季银河银心升上中天，人马座与天蝎座星云密布，是拍摄与目视银河的黄金季。',
    '秋季夜空通透，飞马座四边形与仙女座星系（M31）高悬，适合广域深空观测。',
    '冬季亮星云集，猎户座、大犬座与金牛座昴星团璀璨夺目，且黑夜漫长利于观测。'
  ]
  const en: string[] = [
    'Spring skies bring galaxy season, with Leo, Virgo, and Ursa Major riding high.',
    'Summer skies showcase the rich Galactic core across Sagittarius and Scorpius.',
    'Autumn skies turn crisp, putting the Great Square of Pegasus and the Andromeda Galaxy (M31) high overhead.',
    'Winter skies glitter with Orion, Sirius, and the Pleiades across long, dark nights.'
  ]
  return calendarText(language, zh[effective], en[effective])
}

export function calendarSolarTermBody(
  language: string,
  index: number,
  atMs: number,
  context?: CalendarObserverContext
): string {
  const southern = context?.latitude !== undefined && Number.isFinite(context.latitude) && context.latitude < 0
  const clock = calendarClockText(atMs)
  if (index === 5) {
    return southern
      ? calendarText(language,
          `太阳于今日 ${clock} 过赤道，迎来南半球入秋的二分时刻。全球昼夜几乎等长，此后南半球黑夜渐长，夜间观星窗口随之扩大。`,
          `The Sun crosses the celestial equator at ${clock}, marking the start of autumn in the Southern Hemisphere. Day and night are nearly equal, with longer dark skies ahead.`)
      : calendarText(language,
          `太阳于今日 ${clock} 过春分点，北半球正式步入天文春季。全球昼夜几乎等长，春季星系群与北斗七星逐步升上夜间高空。`,
          `The Sun crosses the vernal equinox at ${clock}, marking the start of astronomical spring in the Northern Hemisphere with nearly equal day and night.`)
  }
  if (index === 11) {
    return southern
      ? calendarText(language,
          `太阳于今日 ${clock} 到达全年最北赤纬，南半球迎来入冬至点与全年最长黑夜。银河银心高悬中天，是南天深空与银河观测的黄金时刻。`,
          `At ${clock} the Sun reaches its northernmost point, bringing the winter solstice and the longest night of the year to the Southern Hemisphere with the Galactic core overhead.`)
      : calendarText(language,
          `太阳于今日 ${clock} 到达全年最北赤纬，北半球迎来夏至与全年最长白昼。天文黑夜虽短，但午夜前后夏季银河正优雅拱起在东南至南方夜空。`,
          `At ${clock} the Sun reaches its northernmost declination, bringing the summer solstice and longest day to northern latitudes, while the summer Milky Way arches across midnight skies.`)
  }
  if (index === 17) {
    return southern
      ? calendarText(language,
          `太阳于今日 ${clock} 再次直射赤道，南半球正式迎来入春二分点。全球昼夜几乎等长，春季星空接棒登场。`,
          `The Sun crosses the celestial equator again at ${clock}, ushering in astronomical spring for the Southern Hemisphere with nearly equal day and night.`)
      : calendarText(language,
          `太阳于今日 ${clock} 过秋分点，北半球正式步入天文秋季。全球昼夜几乎等长，此后夜幕逐日拉长，高悬的仙女座星系与秋夜亮星进入理想观测季。`,
          `The Sun crosses the autumnal equinox at ${clock}, starting astronomical autumn in the Northern Hemisphere as nights lengthen for crisp deep-sky viewing.`)
  }
  if (index === 23) {
    return southern
      ? calendarText(language,
          `太阳于今日 ${clock} 到达全年最南赤纬，南半球迎来入夏至点与全年最长白昼。`,
          `At ${clock} the Sun reaches its southernmost declination, marking the summer solstice and longest day in the Southern Hemisphere.`)
      : calendarText(language,
          `太阳于今日 ${clock} 到达全年最南赤纬，北半球迎来冬至与全年最长黑夜。漫长暗夜配以猎户座、天狼星与昴星团，是全年最畅快的观星长夜。`,
          `At ${clock} the Sun reaches its southernmost point, bringing the winter solstice and the longest stargazing night of the year to northern skies.`)
  }
  const lon = (index * 15 + 285) % 360
  const highlight = solarTermSeasonHighlight(language, index, southern)
  return calendarText(language,
    `太阳于今日 ${clock} 运行至黄经 ${lon}°，进入该节气。${highlight}时刻由本地引擎计算并按设备时区显示。`,
    `The Sun reaches ecliptic longitude ${lon}° at ${clock} for this solar term. ${highlight} Calculated locally in your device time zone.`)
}

export function calendarMoonPhaseBody(
  language: string,
  index: number,
  atMs: number,
  supermoon: boolean,
  distKm?: number
): string {
  const clock = calendarClockText(atMs)
  const distStr = distKm !== undefined ? Math.round(distKm).toLocaleString('en-US') : ''
  const distNoteZh = distStr.length > 0 ? `（地月距离约 ${distStr} km）` : ''
  const distNoteEn = distStr.length > 0 ? ` (Earth–Moon distance ~${distStr} km)` : ''
  const micromoon = index === 2 && !supermoon && distKm !== undefined && distKm >= 404000
  if (index === 0) {
    return calendarText(language,
      `新月时刻出现在 ${clock}${distNoteZh}。月球与太阳同升同落，整夜几乎没有月光干扰，是追拍银河与寻访暗弱星云星系的黄金暗夜。`,
      `New moon occurs at ${clock}${distNoteEn}. With virtually zero moonlight all night, it is prime time for the Milky Way and faint deep-sky objects.`)
  }
  if (index === 1) {
    return calendarText(language,
      `上弦月时刻出现在 ${clock}${distNoteZh}。前半夜高悬西南天空，明暗交界的晨昏线斜照环形山，双筒或小型望远镜即可欣赏立体阴影；午夜月落后下半夜重归暗空。`,
      `First quarter occurs at ${clock}${distNoteEn}. High in the evening sky with crisp crater shadows along the lunar terminator, setting around midnight to leave darker late-night skies.`)
  }
  if (index === 2 && supermoon) {
    return calendarText(language,
      `超级满月时刻出现在 ${clock}！本次满月恰逢月球运行至近地点附近（≤ 360,000 km${distStr.length > 0 ? `，实测约 ${distStr} km` : ''}），视直径与亮度均高于常规满月，日落前后即可在东方地平线守候大月亮升起。`,
      `Supermoon peaks at ${clock}! Near perigee (≤ 360,000 km${distStr.length > 0 ? `, about ${distStr} km` : ''}), this full Moon looks slightly larger and noticeably brighter — watch the eastern horizon around sunset for a dramatic moonrise.`)
  }
  if (index === 2 && micromoon) {
    return calendarText(language,
      `满月（微满月）时刻出现在 ${clock}，此时月球临近远地点（地月距离约 ${distStr} km，≥ 404,000 km），视直径为全年偏小水平。日落前后自东方升起、整夜照耀夜空。`,
      `A micromoon full phase peaks at ${clock} near apogee (about ${distStr} km, ≥ 404,000 km), appearing subtly smaller than average as it rises in the east around sunset.`)
  }
  if (index === 2) {
    return calendarText(language,
      `满月时刻出现在 ${clock}${distNoteZh}。满月于日落时分自东方升起、整夜洒满银辉，适合月海地貌欣赏与地景合影；暗弱深空目标建议留待无月之夜。`,
      `Full moon occurs at ${clock}${distNoteEn}, rising in the east around sunset and shining all night. Ideal for lunar maria viewing and nightscapes, while faint deep-sky targets are better saved for moonless nights.`)
  }
  return calendarText(language,
    `下弦月时刻出现在 ${clock}${distNoteZh}。上半夜无月干扰、适合深空巡天；月亮在午夜后从东方升起，黎明前高悬南方，可清晰细赏月面晨昏线上的环形山群。`,
    `Last quarter occurs at ${clock}${distNoteEn}. Evening skies remain dark for deep-sky observing before moonrise after midnight reveals dramatic crater relief toward dawn.`)
}

export interface PlanetaryElongationMetrics {
  magnitude?: number
  twilightAltDeg?: number
  planetSetRiseAt?: number
  twilightOffsetMin?: number
  eventAt?: number
}

export interface CalendarEclipseTextParams {
  kind: 'solar-eclipse' | 'lunar-eclipse'
  subtype?: string
  atMs: number
  eclipseMagnitude?: number
  umbralMagnitude?: number
  localVisible?: boolean
  localFullVisible?: boolean
  localDaytime?: boolean
  localMagnitude?: number
  localMaxAlt?: number
  eclipseStartAt?: number
  eclipseEndAt?: number
}

function formatDurationZhEn(language: string, minutes: number): string {
  const safe = Math.max(1, Math.round(minutes))
  const h = Math.floor(safe / 60)
  const m = safe % 60
  if (language.toLowerCase().startsWith('zh')) {
    if (h > 0 && m > 0) return `${h}小时${m}分钟`
    if (h > 0) return `${h}小时`
    return `${m}分钟`
  }
  if (h > 0 && m > 0) return `${h}h ${m}m`
  if (h > 0) return `${h}h`
  return `${m}m`
}

export function calendarEclipseBody(language: string, p: CalendarEclipseTextParams): string {
  const date = new Date(p.atMs)
  const dateZh = `${date.getMonth() + 1}月${date.getDate()}日`
  const dateEn = `${date.getMonth() + 1}/${date.getDate()}`
  const clock = calendarClockText(p.atMs)
  const startClock = p.eclipseStartAt !== undefined && p.eclipseStartAt > 0 ? calendarClockText(p.eclipseStartAt) : ''
  const endClock = p.eclipseEndAt !== undefined && p.eclipseEndAt > 0 ? calendarClockText(p.eclipseEndAt) : ''

  if (p.kind === 'lunar-eclipse') {
    const labelZh = p.subtype === 'total' ? '月全食' : (p.subtype === 'partial' ? '月偏食' : '半影月食')
    const labelEn = p.subtype === 'total' ? 'total lunar eclipse' : (p.subtype === 'partial' ? 'partial lunar eclipse' : 'penumbral lunar eclipse')
    let localLineZh: string
    let localLineEn: string
    if (p.localVisible === true) {
      const spanZh = startClock.length > 0 && endClock.length > 0 ? `（${startClock}–${endClock}，食甚 ${clock}）` : `（食甚 ${clock}）`
      const spanEn = startClock.length > 0 && endClock.length > 0 ? ` (${startClock}–${endClock}, maximum at ${clock})` : ` (maximum at ${clock})`
      localLineZh = p.localFullVisible === true
        ? `${labelZh}将于 ${dateZh} 精彩上演${spanZh}，您当前所在地点全程可见。`
        : `${labelZh}将于 ${dateZh} 上演${spanZh}，您当前所在地点可见部分食程（月出或月落带食）。`
      localLineEn = p.localFullVisible === true
        ? `This ${labelEn} unfolds on ${dateEn}${spanEn} and is visible in full from your location.`
        : `This ${labelEn} unfolds on ${dateEn}${spanEn}, partially visible during moonrise or moonset from your location.`
    } else if (p.localDaytime === true) {
      localLineZh = `${labelZh}将于 ${dateZh} ${clock} 达到食甚。真不巧，此次天文现象出现在当地白天，因此您当前所在地点无法观看。下方地图展示全球各地可观察到月食的具体位置。`
      localLineEn = `This ${labelEn} peaks on ${dateEn} at ${clock}, occurring during local daytime so it is not visible from your location. See the global visibility map below.`
    } else {
      localLineZh = `${labelZh}将于 ${dateZh} ${clock} 达到食甚。不过此次月食期间月球位于您当前地平线以下，无法本地观看。下方地图展示全球各地可观察到月食的具体位置。`
      localLineEn = `This ${labelEn} peaks on ${dateEn} at ${clock}, while the Moon is below your horizon. Check the global visibility map below for viewing regions.`
    }
    return calendarText(language, localLineZh, localLineEn)
  }

  // Solar eclipse
  const labelZh = p.subtype === 'total' ? '日全食'
    : (p.subtype === 'annular' ? '日环食' : (p.subtype === 'hybrid' ? '全环食' : '日偏食'))
  const labelEn = p.subtype === 'total' ? 'total solar eclipse'
    : (p.subtype === 'annular' ? 'annular solar eclipse' : (p.subtype === 'hybrid' ? 'hybrid solar eclipse' : 'partial solar eclipse'))
  let localLineZh: string
  let localLineEn: string
  if (p.localVisible === true) {
    const magPct = p.localMagnitude !== undefined && p.localMagnitude > 0 ? `（当地最大食分 ${p.localMagnitude.toFixed(2)}）` : ''
    const spanZh = startClock.length > 0 && endClock.length > 0 ? `，初亏 ${startClock}、食甚 ${clock}、复圆 ${endClock}` : `，食甚 ${clock}`
    localLineZh = `${dateZh}，${labelZh}将在您所在地点可见${magPct}${spanZh}。查看下方地图了解全球食带与偏食覆盖区域。`
    localLineEn = `On ${dateEn}, this ${labelEn} is visible from your location (local maximum at ${clock}). Explore the global path map below.`
  } else {
    localLineZh = `${dateZh} ${clock}，${labelZh}现象即将拉开序幕。不过，您当前所在位置无法观察此次${labelZh}，需要前往食带内观赏。查看下方地图，了解此次日食的所有可观测地点。`
    localLineEn = `On ${dateEn} at ${clock}, this ${labelEn} begins, though it is not visible from your current location. Check the global map below for all viewing regions.`
  }
  return calendarText(language, localLineZh, localLineEn)
}

export function calendarEclipseScienceNote(language: string, kind: 'solar-eclipse' | 'lunar-eclipse', subtype?: string): string {
  if (kind === 'lunar-eclipse') {
    return calendarText(language,
      '红色最深的区域代表可看到整个月食过程的地方，浅红色区域代表月食过程中月亮升起或落下的区域。当太阳、地球、月球排成一条直线、月球步入地球阴影时，月食随之出现。本影是太阳光被地球完全挡住的阴影内部，而在半影区，太阳光仅被部分遮挡。',
      'The deepest red region sees the entire lunar eclipse; lighter bands see it at moonrise or moonset. Lunar eclipses occur when Earth passes directly between the Sun and Moon, casting its dark umbra and softer penumbra across the lunar surface.')
  }
  if (subtype === 'annular') {
    return calendarText(language,
      '若地球、月球、太阳成一条直线，但月球处于轨道较远段、视直径略小于太阳而无法完全遮挡日面，太阳边缘便会露出一圈明亮的“火环”，这就是日环食现象。深色细线为环食中心带，灰色覆盖区域可见日偏食。',
      'When the Moon aligns directly with the Sun near apogee, its apparent disk is slightly smaller than the Sun, leaving a glowing ring of sunlight—an annular solar eclipse. The dark line traces annularity; gray zones experience a partial eclipse.')
  }
  if (subtype === 'total') {
    return calendarText(language,
      '当月球本影扫过地球表面、将耀眼日面完全遮挡时，白昼瞬间化作暮色，平常难以目睹的银白色日冕将清晰舒展在太阳四周。深色曲线为全食带，灰色覆盖区域可见日偏食。',
      'Where the Moon’s dark umbra sweeps across Earth, the solar disk is completely covered and the pearly solar corona blooms into view. The dark curve marks totality; gray regions see a partial solar eclipse.')
  }
  return calendarText(language,
    '当太阳、月球与地球近似成一直线时，月球半影扫过地球部分区域，使太阳呈现缺口般的日偏食奇观。灰色覆盖区域均可看到不同程度的偏食。',
    'When Earth passes through the Moon’s penumbra, part of the solar disk is obscured in a partial solar eclipse across the shaded region.')
}

export function calendarSolarEclipseSafetyNote(language: string): string {
  return calendarText(language,
    '切勿用肉眼、普通墨镜、双筒或未加专业巴德膜/太阳滤镜的望远镜直视太阳（除全食食既至生光阶段外），以免造成永久性视力损伤。请务必佩戴符合 ISO 12312-2 标准的专业日食眼镜。',
    'Never look directly at the Sun without ISO 12312-2 certified solar eclipse glasses or a proper solar filter (except during the brief total phase of a total solar eclipse).')
}

export function calendarPlanetaryBody(
  language: string,
  primary: string | undefined,
  secondary: string | undefined,
  subtype: string | undefined,
  direction: string | undefined,
  alignment: string | undefined,
  separationDegrees?: number,
  elongation?: PlanetaryElongationMetrics
): string {
  const pZh = primary ? calendarPlanetName('zh', primary) : '该行星'
  const pEn = primary ?? 'This planet'
  const sZh = secondary ? calendarPlanetName('zh', secondary) : ''
  const sEn = secondary ?? ''
  if (subtype === 'opposition') {
    return calendarText(language,
      `${pZh}迎来冲日，步入本年度最理想的整夜观测窗口！此时${pZh}与太阳分居地球两侧，日落时自东方升起、午夜高悬中天、整夜可见，且距地球最近、亮度与视直径均处于全年高位。`,
      `${pEn} reaches opposition — its finest observing window of the year! Opposite the Sun in Earth’s sky, it rises at sunset, climbs highest around midnight, and shines at peak brightness and apparent size all night.`)
  }
  if (subtype === 'greatest-elongation' && (direction === 'east' || direction === 'west')) {
    const isEast = direction === 'east'
    const sepStr = separationDegrees !== undefined && Number.isFinite(separationDegrees) ? `${Math.round(separationDegrees)}°` : ''
    const dateObj = elongation?.eventAt !== undefined ? new Date(elongation.eventAt) : undefined
    const dateZh = dateObj !== undefined ? `${dateObj.getMonth() + 1}月${dateObj.getDate()}日` : '今日'
    const dateEn = dateObj !== undefined ? `${dateObj.getMonth() + 1}/${dateObj.getDate()}` : 'today'
    const magStr = elongation?.magnitude !== undefined && Number.isFinite(elongation.magnitude)
      ? `${elongation.magnitude >= 0 ? '+' : ''}${elongation.magnitude.toFixed(1)}` : ''
    const altStr = elongation?.twilightAltDeg !== undefined && Number.isFinite(elongation.twilightAltDeg) && elongation.twilightAltDeg > 0
      ? `${Math.round(elongation.twilightAltDeg)}°` : ''
    const setRiseClock = elongation?.planetSetRiseAt !== undefined && elongation.planetSetRiseAt > 0
      ? calendarClockText(elongation.planetSetRiseAt) : ''
    const offsetStrZh = elongation?.twilightOffsetMin !== undefined && elongation.twilightOffsetMin > 0
      ? formatDurationZhEn('zh', elongation.twilightOffsetMin) : ''
    const offsetStrEn = elongation?.twilightOffsetMin !== undefined && elongation.twilightOffsetMin > 0
      ? formatDurationZhEn('en', elongation.twilightOffsetMin) : ''

    if (isEast) {
      const leadZh = `${pZh}在 ${dateZh}达到其最大东距角${sepStr.length > 0 ? `：${sepStr}` : ''}。在此夜前后一周的晚间，${magStr.length > 0 ? `${pZh}的星等达到 ${magStr}，` : ''}形成本轮最佳傍晚观测时机。`
      const localZh = altStr.length > 0
        ? `当天日落时，${pZh}将位于西方地平线以上约 ${altStr}，并自逐渐变暗的天空中慢慢显现${setRiseClock.length > 0 && offsetStrZh.length > 0 ? `，并于 ${setRiseClock}（日落后 ${offsetStrZh}）落下。` : '。'}`
        : `日落后不久面向西方低空即可寻觅它的身影。`
      const orbitZh = `${pZh}的轨道在地球轨道之内，大多数时候紧随太阳升起、落下，仅在达到最大东距角前后才会在天黑后依然留在西方地平线之上。`
      const leadEn = `${pEn} reaches greatest eastern elongation${sepStr.length > 0 ? ` (${sepStr})` : ''} on ${dateEn}${magStr.length > 0 ? `, shining around mag ${magStr}` : ''} for its best evening apparition.`
      const localEn = altStr.length > 0
        ? ` At sunset it stands ~${altStr} above the western horizon${setRiseClock.length > 0 && offsetStrEn.length > 0 ? `, setting at ${setRiseClock} (${offsetStrEn} after sunset).` : '.'}`
        : ' Look low in the west shortly after sunset.'
      return calendarText(language, leadZh + localZh + orbitZh, leadEn + localEn)
    } else {
      const leadZh = `${pZh}在 ${dateZh}达到其最大西距角${sepStr.length > 0 ? `：${sepStr}` : ''}。在此夜前后一周的清晨，${magStr.length > 0 ? `${pZh}的星等达到 ${magStr}，` : ''}形成本轮最佳黎明观测时机。`
      const localZh = altStr.length > 0
        ? `当天日出时，${pZh}将升至东方地平线以上约 ${altStr}${setRiseClock.length > 0 && offsetStrZh.length > 0 ? `，早于日出 ${offsetStrZh}（${setRiseClock}）便已从东方升起。` : '。'}`
        : `日出前的一小段时间内面向东方低空即可轻松寻找。`
      const orbitZh = `${pZh}作为地内行星平时紧邻太阳，只有在最大西距角前后才会在黎明前的东方晨空中高悬可见。`
      const leadEn = `${pEn} reaches greatest western elongation${sepStr.length > 0 ? ` (${sepStr})` : ''} on ${dateEn}${magStr.length > 0 ? `, shining around mag ${magStr}` : ''} for its finest morning apparition.`
      const localEn = altStr.length > 0
        ? ` At sunrise it climbs to ~${altStr} above the eastern horizon${setRiseClock.length > 0 && offsetStrEn.length > 0 ? `, rising at ${setRiseClock} (${offsetStrEn} before sunrise).` : '.'}`
        : ' Look low in the east before sunrise.'
      return calendarText(language, leadZh + localZh + orbitZh, leadEn + localEn)
    }
  }
  if (subtype === 'conjunction' && secondary && secondary !== 'Sun') {
    const sepValid = separationDegrees !== undefined && Number.isFinite(separationDegrees) && separationDegrees >= 0
    const sepZh = sepValid ? `（最近角距约 ${separationDegrees.toFixed(1)}°）` : ''
    const sepEn = sepValid ? ` (closest separation ~${separationDegrees.toFixed(1)}°)` : ''
    const isStarPair = secondary === 'Regulus' || secondary === 'Aldebaran' || secondary === 'Spica' || secondary === 'Antares'
    const isMoonPair = primary === 'Moon'
    if (isMoonPair || isStarPair) {
      return calendarText(language,
        `${pZh}与${sZh}在夜空中近距离相合${sepZh}，两者在黄经上彼此擦肩而过、同框辉映。肉眼与双筒望远镜皆宜观赏，具体可观测时段请结合当地升落时间。`,
        `${pEn} and ${sEn} make a close pairing in the sky${sepEn}, ideal for naked-eye or binocular viewing. Check local rise and set times for the best window.`)
    }
    return calendarText(language,
      `${pZh}与${sZh}上演行星相合${sepZh}，两颗行星在黄经上彼此擦肩而过、同框闪耀夜空。双筒或低倍广角目镜尤宜同场观赏；具体可观测时段请结合当地两星的升落时间。`,
      `${pEn} and ${sEn} meet in conjunction${sepEn}, passing closely in ecliptic longitude for a striking pairing in binoculars or wide-field views. Check local rise and set times for the optimal window.`)
  }
  if (subtype === 'conjunction' && secondary === 'Sun') {
    const detailZh = alignment === 'inferior'
      ? '（下合，位于太阳与地球之间）'
      : (alignment === 'superior' ? '（上合，运行至太阳远侧）' : '（运行至太阳背后）')
    const detailEn = alignment === 'inferior'
      ? ' (inferior conjunction, passing between Earth and the Sun)'
      : (alignment === 'superior' ? ' (superior conjunction, passing behind the Sun)' : ' (passing behind the Sun)')
    return calendarText(language,
      `${pZh}到达合日位置${detailZh}，因与太阳角距过近而完全隐没在耀眼日光中，不适合目视或摄影观测。严禁使用双筒或未加专业太阳滤镜的望远镜在太阳附近搜索目标。`,
      `${pEn} reaches solar conjunction${detailEn}, hidden in the Sun’s glare and unsuitable for viewing. Never sweep near the Sun with binoculars or an unfiltered telescope.`)
  }
  return calendarText(language,
    '本事件由行星地心视位置实时推算：合与冲按黄经差定义，大距按与太阳的角距极大定义。实际观测请结合当地升落时刻，严禁将无滤镜光学仪器指向太阳附近。',
    'Computed from geocentric apparent planetary positions (ecliptic longitude for conjunction/opposition; maximum angular separation for greatest elongation). Check local rise/set times and never point unfiltered optics near the Sun.')
}
