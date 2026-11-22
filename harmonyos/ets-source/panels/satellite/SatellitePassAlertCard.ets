import { Theme } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyCalendarEvent } from '../../state/AstronomyCalendarEvent'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 应用内卫星过境立体地球弹出卡片：
// 1. 复刻深空黑圆角弹窗 + 超大细体实时倒计时 + 3D 正射球面地球 + 真实太阳晨昏线 + 夜间微光城市灯；
// 2. 悬空 3D 立体卫星轨道环（按球面深度 z 拆分背面外露段 / 地球本体 / 正面凌空段）+ 用户蓝点 + 卫星白点；
// 3. 入场 1.15s 阻尼动效：卡片柔和淡入 → 地球由小变大并东转聚焦用户经纬度 → 3D 轨道环与双点浮现；
// 4. 离线 0ms 秒开：仅读取应用内置纯自然地貌 earth_cmap.png 抽取海陆轮廓（零政区/国界线），缺图自动降级纯蓝灰晨昏球。

interface Vec3 {
  x: number
  y: number
  z: number
}

interface CityLightSeed {
  lat: number
  lon: number
  weight: number
}

interface EarthLandAtlas {
  width: number
  height: number
  // 0 = 海洋，1..255 = 陆地（数值编码微弱地形明度，用于极简冷蓝灰质感层次）
  land: Uint8Array
}

interface OrbitBasis {
  p0: Vec3
  t0: Vec3
}

const ATLAS_W: number = 360
const ATLAS_H: number = 180
const ANIM_DURATION_MS: number = 1150
const ANIM_FRAME_MS: number = 28
const ORBIT_RADIUS_EARTH: number = 1.115
const DEG2RAD: number = Math.PI / 180

let cachedEarthAtlas: EarthLandAtlas | undefined = undefined
let atlasLoadPromise: Promise<EarthLandAtlas | undefined> | undefined = undefined

// 全球主要夜间城市光斑坐标（仅在地球暗夜半球呈现柔和微光点群，不绘制任何行政界线）
const NIGHT_CITY_LIGHTS: CityLightSeed[] = [
  // 东亚与东南亚
  { lat: 39.9, lon: 116.4, weight: 1.0 },
  { lat: 39.1, lon: 117.2, weight: 0.78 },
  { lat: 38.0, lon: 114.5, weight: 0.65 },
  { lat: 36.1, lon: 120.4, weight: 0.72 },
  { lat: 34.8, lon: 113.6, weight: 0.75 },
  { lat: 34.3, lon: 108.9, weight: 0.72 },
  { lat: 41.8, lon: 123.4, weight: 0.70 },
  { lat: 45.8, lon: 126.5, weight: 0.58 },
  { lat: 31.2, lon: 121.5, weight: 1.0 },
  { lat: 32.1, lon: 118.8, weight: 0.80 },
  { lat: 30.3, lon: 120.2, weight: 0.82 },
  { lat: 30.6, lon: 114.3, weight: 0.82 },
  { lat: 30.7, lon: 104.1, weight: 0.80 },
  { lat: 29.6, lon: 106.5, weight: 0.78 },
  { lat: 28.2, lon: 113.0, weight: 0.65 },
  { lat: 26.1, lon: 119.3, weight: 0.62 },
  { lat: 25.0, lon: 121.5, weight: 0.82 },
  { lat: 23.1, lon: 113.3, weight: 0.96 },
  { lat: 22.5, lon: 114.1, weight: 0.94 },
  { lat: 24.5, lon: 118.1, weight: 0.64 },
  { lat: 37.6, lon: 127.0, weight: 0.94 },
  { lat: 35.2, lon: 129.1, weight: 0.72 },
  { lat: 35.7, lon: 139.7, weight: 1.0 },
  { lat: 34.7, lon: 135.5, weight: 0.86 },
  { lat: 35.2, lon: 136.9, weight: 0.74 },
  { lat: 33.6, lon: 130.4, weight: 0.65 },
  { lat: 43.1, lon: 141.3, weight: 0.56 },
  { lat: 21.0, lon: 105.8, weight: 0.64 },
  { lat: 13.8, lon: 100.5, weight: 0.80 },
  { lat: 10.8, lon: 106.7, weight: 0.68 },
  { lat: 14.6, lon: 121.0, weight: 0.78 },
  { lat: 3.1, lon: 101.7, weight: 0.72 },
  { lat: 1.3, lon: 103.8, weight: 0.84 },
  { lat: -6.2, lon: 106.8, weight: 0.76 },
  // 大洋洲
  { lat: -33.9, lon: 151.2, weight: 0.84 },
  { lat: -37.8, lon: 145.0, weight: 0.78 },
  { lat: -27.5, lon: 153.0, weight: 0.64 },
  { lat: -31.9, lon: 115.9, weight: 0.58 },
  // 南亚与中东
  { lat: 28.6, lon: 77.2, weight: 0.92 },
  { lat: 19.1, lon: 72.9, weight: 0.86 },
  { lat: 13.0, lon: 77.6, weight: 0.74 },
  { lat: 22.6, lon: 88.4, weight: 0.76 },
  { lat: 24.9, lon: 67.0, weight: 0.68 },
  { lat: 25.2, lon: 55.3, weight: 0.78 },
  { lat: 24.7, lon: 46.7, weight: 0.72 },
  { lat: 30.0, lon: 31.2, weight: 0.84 },
  { lat: 41.0, lon: 29.0, weight: 0.82 },
  // 欧洲
  { lat: 51.5, lon: -0.1, weight: 0.96 },
  { lat: 48.9, lon: 2.3, weight: 0.92 },
  { lat: 52.5, lon: 13.4, weight: 0.82 },
  { lat: 45.5, lon: 9.2, weight: 0.84 },
  { lat: 40.4, lon: -3.7, weight: 0.76 },
  { lat: 55.8, lon: 37.6, weight: 0.90 },
  { lat: 59.9, lon: 30.3, weight: 0.72 },
  // 美洲
  { lat: 40.7, lon: -74.0, weight: 1.0 },
  { lat: 41.9, lon: -87.6, weight: 0.84 },
  { lat: 34.1, lon: -118.2, weight: 0.92 },
  { lat: 37.8, lon: -122.4, weight: 0.78 },
  { lat: 29.8, lon: -95.4, weight: 0.78 },
  { lat: 19.4, lon: -99.1, weight: 0.84 },
  { lat: -23.5, lon: -46.6, weight: 0.86 },
  { lat: -34.6, lon: -58.4, weight: 0.76 }
]

function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : (v > hi ? hi : v)
}

function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
  return t * t * (3 - 2 * t)
}

function easeOutCubic(t: number): number {
  const k = 1 - clamp(t, 0, 1)
  return 1 - k * k * k
}

function wrapLonDeg(lon: number): number {
  let x = ((lon + 180) % 360 + 360) % 360 - 180
  if (x <= -180) x += 360
  return x
}

function latLonToVec3(latDeg: number, lonDeg: number): Vec3 {
  const lat = latDeg * DEG2RAD
  const lon = lonDeg * DEG2RAD
  const cosLat = Math.cos(lat)
  return {
    x: cosLat * Math.cos(lon),
    y: cosLat * Math.sin(lon),
    z: Math.sin(lat)
  }
}

function dot3(a: Vec3, b: Vec3): number {
  return a.x * b.x + a.y * b.y + a.z * b.z
}

function cross3(a: Vec3, b: Vec3): Vec3 {
  return {
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x
  }
}

function normalize3(v: Vec3): Vec3 {
  const len = Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if (len < 1e-6) return { x: 1, y: 0, z: 0 }
  return { x: v.x / len, y: v.y / len, z: v.z / len }
}

function buildEarthLandAtlasFromRgba(rgba: Uint8Array, w: number, h: number): EarthLandAtlas {
  const raw = new Uint8Array(w * h)
  for (let i = 0; i < w * h; i++) {
    const off = i * 4
    const r = rgba[off]
    const g = rgba[off + 1]
    const b = rgba[off + 2]
    // earth_cmap.png 海洋呈均匀深青蓝色（低红通道、蓝显著高于红）；
    // 陆地（植被/荒漠/高原/冰雪）红通道更高或蓝绿差显著更小。
    const isOcean = r < 40 && (b - r) > 26 && (g - r) > 12 && b < 118
    if (isOcean) {
      raw[i] = 0
    } else {
      const luma = Math.round(0.299 * r + 0.587 * g + 0.114 * b)
      raw[i] = clamp(96 + Math.round(luma * 0.62), 96, 255)
    }
  }
  // 轻度 3×3 抗锯齿平滑，让海岸线在 3D 球面缩放时保持柔和细腻
  const smooth = new Uint8Array(w * h)
  for (let y = 0; y < h; y++) {
    const ym = y > 0 ? y - 1 : 0
    const yp = y < h - 1 ? y + 1 : h - 1
    for (let x = 0; x < w; x++) {
      const xm = (x - 1 + w) % w
      const xp = (x + 1) % w
      const c = raw[y * w + x]
      const sum =
        c * 4 +
        raw[y * w + xm] * 2 +
        raw[y * w + xp] * 2 +
        raw[ym * w + x] * 2 +
        raw[yp * w + x] * 2 +
        raw[ym * w + xm] +
        raw[ym * w + xp] +
        raw[yp * w + xm] +
        raw[yp * w + xp]
      smooth[y * w + x] = Math.round(sum / 16)
    }
  }
  return { width: w, height: h, land: smooth }
}

async function decodeEarthAtlasBytes(rawBuffer: ArrayBuffer): Promise<EarthLandAtlas | undefined> {
  let src: image.ImageSource | undefined = undefined
  let pm: image.PixelMap | undefined = undefined
  try {
    src = image.createImageSource(rawBuffer)
    const decodeOpts: image.DecodingOptions = {
      desiredSize: { width: ATLAS_W, height: ATLAS_H },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false
    }
    pm = await src.createPixelMap(decodeOpts)
    const info = await pm.getImageInfo()
    const w = info.size.width
    const h = info.size.height
    if (w <= 0 || h <= 0) return undefined
    const buf = new ArrayBuffer(w * h * 4)
    pm.readPixelsToBufferSync(buf)
    return buildEarthLandAtlasFromRgba(new Uint8Array(buf), w, h)
  } catch (_err) {
    return undefined
  } finally {
    if (pm !== undefined) {
      try { pm.release() } catch (_e) {}
    }
    if (src !== undefined) {
      try { src.release() } catch (_e) {}
    }
  }
}

async function loadEarthLandAtlas(context: Context | undefined, earthMapUri: string): Promise<EarthLandAtlas | undefined> {
  if (cachedEarthAtlas !== undefined) return cachedEarthAtlas
  if (atlasLoadPromise !== undefined) return atlasLoadPromise
  atlasLoadPromise = (async (): Promise<EarthLandAtlas | undefined> => {
    // 优先从应用内置 rawfile 读取纯自然地貌纹理 earth_cmap.png（离线 100% 可用）
    if (context !== undefined) {
      try {
        const rawBytes = await context.resourceManager.getRawFileContent('stellarium/textures/earth_cmap.png')
        const copy = new Uint8Array(rawBytes.byteLength)
        copy.set(rawBytes)
        const atlas = await decodeEarthAtlasBytes(copy.buffer as ArrayBuffer)
        if (atlas !== undefined) {
          cachedEarthAtlas = atlas
          return atlas
        }
      } catch (_rawErr) {
        // Fallback to filesDir path below
      }
    }
    // 回退：从运行期 filesDir 路径读取
    const filePath = earthMapUri.startsWith('file://') ? earthMapUri.substring(7) : earthMapUri
    if (filePath.length > 0) {
      let file: fileIo.File | undefined = undefined
      try {
        const stat = fileIo.statSync(filePath)
        if (stat.size > 0 && stat.size < 8 * 1024 * 1024) {
          const buf = new ArrayBuffer(stat.size)
          file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
          fileIo.readSync(file.fd, buf)
          fileIo.closeSync(file)
          file = undefined
          const atlas = await decodeEarthAtlasBytes(buf)
          if (atlas !== undefined) {
            cachedEarthAtlas = atlas
            return atlas
          }
        }
      } catch (_fileErr) {
        if (file !== undefined) {
          try { fileIo.closeSync(file) } catch (_closeErr) {}
        }
      }
    }
    return undefined
  })()
  const result = await atlasLoadPromise
  if (result === undefined) {
    atlasLoadPromise = undefined
  }
  return result
}

function compassLabel(deg: number | undefined, zh: boolean): string {
  if (deg === undefined || !Number.isFinite(deg)) return '--'
  const norm = ((deg % 360) + 360) % 360
  const dirsZh: string[] = ['北', '东北', '东', '东南', '南', '西南', '西', '西北']
  const dirsEn: string[] = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
  const idx = Math.floor((norm + 22.5) / 45) % 8
  return (zh ? dirsZh[idx] : dirsEn[idx]) + ' ' + Math.round(norm).toString() + '°'
}

function formatClock(ms: number | undefined): string {
  if (ms === undefined || !Number.isFinite(ms)) return '--:--'
  const d = new Date(ms)
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return `${hh}:${mm}`
}

function computeSolarSubpoint(timestampMs: number, observerLat: number, observerLon: number, preferTwilightPreview: boolean): Vec3 {
  const date = new Date(timestampMs)
  const startOfYear = Date.UTC(date.getUTCFullYear(), 0, 1)
  const dayOfYear = Math.floor((timestampMs - startOfYear) / 86400000) + 1
  const declDeg = 23.44 * Math.sin(((2 * Math.PI) / 365) * (dayOfYear - 81))
  const utcHours = date.getUTCHours() + date.getUTCMinutes() / 60 + date.getUTCSeconds() / 3600
  let sunLonDeg = wrapLonDeg((12 - utcHours) * 15)
  let sunVec = latLonToVec3(declDeg, sunLonDeg)
  // 若为白天手动预览卡片，把预览球体的太阳时角设为当地傍晚天文昏影（观测地处于晨昏线夜侧），
  // 完整展现真实可见过境时的「昼夜晨昏线 + 暗夜城市微光」效果。
  if (preferTwilightPreview) {
    const obsVec = latLonToVec3(observerLat, observerLon)
    if (dot3(obsVec, sunVec) > 0.04) {
      sunLonDeg = wrapLonDeg(observerLon - 106)
      sunVec = latLonToVec3(declDeg, sunLonDeg)
    }
  }
  return sunVec
}

function computeOrbitBasis(observerLat: number, observerLon: number, startAz: number | undefined, endAz: number | undefined, maxAlt: number | undefined): OrbitBasis {
  const obs = latLonToVec3(observerLat, observerLon)
  // 局部正东与正北切向量
  const east = normalize3({ x: -Math.sin(observerLon * DEG2RAD), y: Math.cos(observerLon * DEG2RAD), z: 0 })
  const north = normalize3(cross3(obs, east))

  // 根据过境升起→落下方位角推导地面航向角（默认西南→东北 / 西北→东南高仰角过境）
  let headingAzDeg = 46
  if (startAz !== undefined && endAz !== undefined && Number.isFinite(startAz) && Number.isFinite(endAz)) {
    const sx = Math.sin(startAz * DEG2RAD)
    const sy = Math.cos(startAz * DEG2RAD)
    const ex = Math.sin(endAz * DEG2RAD)
    const ey = Math.cos(endAz * DEG2RAD)
    const dx = ex - sx
    const dy = ey - sy
    if (dx * dx + dy * dy > 0.01) {
      headingAzDeg = Math.atan2(dx, dy) / DEG2RAD
    }
  }
  const hr = headingAzDeg * DEG2RAD
  const tangent = normalize3({
    x: east.x * Math.sin(hr) + north.x * Math.cos(hr),
    y: east.y * Math.sin(hr) + north.y * Math.cos(hr),
    z: east.z * Math.sin(hr) + north.z * Math.cos(hr)
  })
  // 过顶仰角低于 90° 时，令轨道最近点相对用户蓝点略有横向偏移，真实呈现仰角差异
  const alt = maxAlt !== undefined && Number.isFinite(maxAlt) ? clamp(maxAlt, 15, 90) : 72
  const sideOffsetRad = clamp((90 - alt) * 0.14, 0.8, 10.5) * DEG2RAD
  const side = normalize3(cross3(obs, tangent))
  const p0 = normalize3({
    x: obs.x * Math.cos(sideOffsetRad) + side.x * Math.sin(sideOffsetRad),
    y: obs.y * Math.cos(sideOffsetRad) + side.y * Math.sin(sideOffsetRad),
    z: obs.z * Math.cos(sideOffsetRad) + side.z * Math.sin(sideOffsetRad)
  })
  // 重新正交化切向量，保证 p0 · t0 === 0
  const proj = dot3(tangent, p0)
  const t0 = normalize3({
    x: tangent.x - p0.x * proj,
    y: tangent.y - p0.y * proj,
    z: tangent.z - p0.z * proj
  })
  return { p0: p0, t0: t0 }
}

@Component
export struct SatellitePassAlertCard {
  @Prop event: AstronomyCalendarEvent | undefined = undefined
  @Prop language: string = 'zh'
  @Prop observerLat: number = 39.9
  @Prop observerLon: number = 116.4
  @Prop earthMapUri: string = ''
  @Prop liveViewActive: boolean = false
  @Prop cardWidth: number = 340
  @Prop compactHeight: boolean = false
  onTrackInSky: () => void = () => {}
  onToggleLiveView: () => void = () => {}
  onDismiss: () => void = () => {}

  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private nowMs: number = Date.now()
  @State private cardOpacity: number = 0
  @State private cardScale: number = 0.96

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings)
  private canvasReady: boolean = false
  private atlas: EarthLandAtlas | undefined = undefined
  private animStartMs: number = 0
  private animProgress: number = 0
  private animTimerId: number = 0
  private clockTimerId: number = 0
  private settledGlobePm: image.PixelMap | undefined = undefined
  private settledGlobeKey: string = ''
  private alive: boolean = true

  onWillApplyTheme(theme: Theme): void {
    const prevNight = this.c.isNight
    this.c = slotsFromTheme(theme)
    if (prevNight !== this.c.isNight) {
      this.releaseSettledGlobe()
      if (this.canvasReady) this.drawScene()
    }
  }

  aboutToAppear(): void {
    this.alive = true
    this.nowMs = Date.now()
    this.animStartMs = Date.now()
    this.animProgress = 0
    this.atlas = cachedEarthAtlas

    // 卡片淡入微缩放动效（匹配参考帧 1→2）
    setTimeout(() => {
      if (!this.alive) return
      animateTo({ duration: 360, curve: Curve.EaseOut }, () => {
        this.cardOpacity = 1
        this.cardScale = 1
      })
    }, 16)

    // 异步加载内置地球纯自然地貌海陆轮廓（已缓存时 0ms 直接命中）
    const hostCtx = this.getUIContext().getHostContext()
    void loadEarthLandAtlas(hostCtx, this.earthMapUri).then((loaded: EarthLandAtlas | undefined) => {
      if (!this.alive) return
      this.atlas = loaded
      this.releaseSettledGlobe()
      if (this.canvasReady) this.drawScene()
    })

    // 1.15s 地球由小变大 + 东转聚焦 + 轨道浮现帧驱动
    this.animTimerId = setInterval(() => {
      if (!this.alive) return
      const elapsed = Date.now() - this.animStartMs
      this.animProgress = clamp(elapsed / ANIM_DURATION_MS, 0, 1)
      if (this.canvasReady) this.drawScene()
      if (this.animProgress >= 1) {
        clearInterval(this.animTimerId)
        this.animTimerId = 0
      }
    }, ANIM_FRAME_MS)

    // 1 秒倒计时 + 卫星沿 3D 轨道实时推进
    this.clockTimerId = setInterval(() => {
      if (!this.alive) return
      this.nowMs = Date.now()
      if (this.canvasReady && this.animProgress >= 1) {
        this.drawScene()
      }
    }, 1000)
  }

  aboutToDisappear(): void {
    this.alive = false
    if (this.animTimerId !== 0) {
      clearInterval(this.animTimerId)
      this.animTimerId = 0
    }
    if (this.clockTimerId !== 0) {
      clearInterval(this.clockTimerId)
      this.clockTimerId = 0
    }
    this.releaseSettledGlobe()
  }

  private releaseSettledGlobe(): void {
    if (this.settledGlobePm !== undefined) {
      try { this.settledGlobePm.release() } catch (_e) {}
      this.settledGlobePm = undefined
      this.settledGlobeKey = ''
    }
  }

  private isZh(): boolean {
    return this.language.toLowerCase().startsWith('zh')
  }

  private cleanSatelliteTitle(): string {
    const ev = this.event
    if (ev === undefined) return this.isZh() ? '空间站经过' : 'Station Pass'
    const raw = ev.title
      .replace(/\s*过境\s*·.*$/, '')
      .replace(/\s*Pass\s*·.*$/, '')
      .trim()
    if (this.isZh()) {
      if (raw.includes('中国空间站')) return '中国空间站经过'
      if (raw.includes('国际空间站') || raw.includes('ISS')) return '国际空间站经过'
      return raw.endsWith('经过') ? raw : `${raw}经过`
    }
    return raw.toLowerCase().includes('pass') ? raw : `${raw} Pass`
  }

  private countdownText(): string {
    const ev = this.event
    const zh = this.isZh()
    if (ev === undefined) return zh ? '即将过境' : 'Soon'
    const startMs = ev.satStartAt ?? ev.at
    const endMs = ev.satEndAt ?? (startMs + Math.max(240, ev.satDurationSec ?? 360) * 1000)
    const targetMs = this.nowMs < startMs ? startMs : endMs
    const remainSec = Math.max(0, Math.ceil((targetMs - this.nowMs) / 1000))
    const hrs = Math.floor(remainSec / 3600)
    const mins = Math.floor((remainSec % 3600) / 60)
    const secs = remainSec % 60
    const secStr = String(secs).padStart(2, '0')
    if (hrs > 0) {
      return zh ? `${hrs}小时${mins}分` : `${hrs}h ${mins}m`
    }
    if (mins > 0) {
      return zh ? `${mins}分钟${secStr}秒` : `${mins}m ${secStr}s`
    }
    return zh ? `${secs}秒` : `${secs}s`
  }

  private isPassingNow(): boolean {
    const ev = this.event
    if (ev === undefined) return false
    const startMs = ev.satStartAt ?? ev.at
    const endMs = ev.satEndAt ?? (startMs + 360000)
    return this.nowMs >= startMs && this.nowMs < endMs
  }

  private durationLabel(): string {
    const ev = this.event
    const zh = this.isZh()
    if (ev === undefined) return ''
    let sec = ev.satDurationSec
    if ((sec === undefined || sec <= 0) && ev.satStartAt !== undefined && ev.satEndAt !== undefined) {
      sec = Math.max(60, Math.round((ev.satEndAt - ev.satStartAt) / 1000))
    }
    if (sec === undefined || sec <= 0) return ''
    const mins = Math.max(1, Math.round(sec / 60))
    return zh ? `持续 ${mins} 分钟` : `${mins} min`
  }

  private sampleLandBilinear(atlas: EarthLandAtlas, latRad: number, lonRad: number): number {
    const u = ((lonRad / Math.PI) + 1) * 0.5 * atlas.width
    const v = (0.5 - latRad / Math.PI) * atlas.height
    const x0 = ((Math.floor(u) % atlas.width) + atlas.width) % atlas.width
    const x1 = (x0 + 1) % atlas.width
    const y0 = clamp(Math.floor(v), 0, atlas.height - 1)
    const y1 = clamp(y0 + 1, 0, atlas.height - 1)
    const fx = u - Math.floor(u)
    const fy = v - Math.floor(v)
    const row0 = y0 * atlas.width
    const row1 = y1 * atlas.width
    const a = atlas.land[row0 + x0]
    const b = atlas.land[row0 + x1]
    const c = atlas.land[row1 + x0]
    const d = atlas.land[row1 + x1]
    const top = a + (b - a) * fx
    const bot = c + (d - c) * fx
    return top + (bot - top) * fy
  }

  private rasterizeEarthGlobe(
    size: number,
    camE: Vec3,
    camN: Vec3,
    camF: Vec3,
    sunVec: Vec3,
    nightVision: boolean
  ): image.PixelMap | undefined {
    const buf = new ArrayBuffer(size * size * 4)
    const data = new Uint8Array(buf)
    const half = size * 0.5
    const invR = 1 / (half - 1.2)
    const atlas = this.atlas

    // 极简冷蓝灰海陆质感配色（或夜视暗红护眼配色）
    const dayOceanR = nightVision ? 42 : 84
    const dayOceanG = nightVision ? 17 : 106
    const dayOceanB = nightVision ? 17 : 138
    const dayLandR = nightVision ? 108 : 168
    const dayLandG = nightVision ? 40 : 178
    const dayLandB = nightVision ? 36 : 192
    const nightOceanR = nightVision ? 15 : 13
    const nightOceanG = nightVision ? 6 : 20
    const nightOceanB = nightVision ? 7 : 37
    const nightLandR = nightVision ? 33 : 27
    const nightLandG = nightVision ? 13 : 36
    const nightLandB = nightVision ? 14 : 58
    const rimDayR = nightVision ? 210 : 152
    const rimDayG = nightVision ? 76 : 184
    const rimDayB = nightVision ? 64 : 226
    const rimNightR = nightVision ? 84 : 62
    const rimNightG = nightVision ? 30 : 78
    const rimNightB = nightVision ? 28 : 108

    for (let py = 0; py < size; py++) {
      const nv = (half - (py + 0.5)) * invR
      const nv2 = nv * nv
      const rowOff = py * size * 4
      for (let px = 0; px < size; px++) {
        const nu = ((px + 0.5) - half) * invR
        const r2 = nu * nu + nv2
        if (r2 > 1.035) continue

        // 球体边缘 1.5px 抗锯齿羽化
        const dist = Math.sqrt(r2)
        const alphaF = dist <= 0.985 ? 1.0 : clamp((1.015 - dist) / 0.03, 0, 1)
        if (alphaF <= 0) continue

        const clampedR2 = r2 > 0.9999 ? 0.9999 : r2
        const nw = Math.sqrt(1 - clampedR2)
        const ex = nu * camE.x + nv * camN.x + nw * camF.x
        const ey = nu * camE.y + nv * camN.y + nw * camF.y
        const ez = nu * camE.z + nv * camN.z + nw * camF.z

        // 陆地掩膜 + 轻微高程层次（无底图时平滑降级为纯蓝灰晨昏球）
        let landFactor = 0
        let relief = 0
        if (atlas !== undefined) {
          const latRad = Math.asin(clamp(ez, -1, 1))
          const lonRad = Math.atan2(ey, ex)
          const sampled = this.sampleLandBilinear(atlas, latRad, lonRad)
          if (sampled > 28) {
            landFactor = smoothstep(28, 108, sampled)
            relief = clamp((sampled - 110) / 145, 0, 1)
          }
        }

        // 真实太阳晨昏线与球面漫反射明暗
        const sunDot = ex * sunVec.x + ey * sunVec.y + ez * sunVec.z
        const dayBlend = smoothstep(-0.14, 0.22, sunDot)
        const shade = 0.80 + 0.22 * nw + 0.10 * clamp(sunDot, 0, 1)

        const baseDayR = (dayOceanR + (dayLandR - dayOceanR) * landFactor + relief * 14) * shade
        const baseDayG = (dayOceanG + (dayLandG - dayOceanG) * landFactor + relief * 14) * shade
        const baseDayB = (dayOceanB + (dayLandB - dayOceanB) * landFactor + relief * 12) * shade

        const nightShade = 0.84 + 0.16 * nw
        const baseNightR = (nightOceanR + (nightLandR - nightOceanR) * landFactor) * nightShade
        const baseNightG = (nightOceanG + (nightLandG - nightOceanG) * landFactor) * nightShade
        const baseNightB = (nightOceanB + (nightLandB - nightOceanB) * landFactor) * nightShade

        let outR = baseNightR + (baseDayR - baseNightR) * dayBlend
        let outG = baseNightG + (baseDayG - baseNightG) * dayBlend
        let outB = baseNightB + (baseDayB - baseNightB) * dayBlend

        // 大气层边缘柔和菲涅耳辉光，确保暗夜侧边缘也有干净细腻的球体轮廓
        const rimPow = Math.pow(1 - nw, 3.0)
        const rimStrength = rimPow * (0.20 + 0.28 * dayBlend)
        const rimR = rimNightR + (rimDayR - rimNightR) * dayBlend
        const rimG = rimNightG + (rimDayG - rimNightG) * dayBlend
        const rimB = rimNightB + (rimDayB - rimNightB) * dayBlend
        outR = outR + (rimR - outR) * rimStrength
        outG = outG + (rimG - outG) * rimStrength
        outB = outB + (rimB - outB) * rimStrength

        const off = rowOff + px * 4
        data[off] = clamp(Math.round(outR), 0, 255)
        data[off + 1] = clamp(Math.round(outG), 0, 255)
        data[off + 2] = clamp(Math.round(outB), 0, 255)
        data[off + 3] = clamp(Math.round(alphaF * 255), 0, 255)
      }
    }

    try {
      const initOpts: image.InitializationOptions = {
        size: { width: size, height: size },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.UNPREMUL,
        editable: false
      }
      return image.createPixelMapSync(buf, initOpts)
    } catch (_err) {
      return undefined
    }
  }

  private drawOrbitSegment(
    ctx: CanvasRenderingContext2D,
    points: number[][],
    strokeStyle: string,
    lineWidth: number
  ): void {
    if (points.length < 2) return
    ctx.strokeStyle = strokeStyle
    ctx.lineWidth = lineWidth
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.beginPath()
    let started = false
    for (let i = 0; i < points.length; i++) {
      const pt = points[i]
      if (pt[2] < 0) {
        started = false
        continue
      }
      if (!started) {
        ctx.moveTo(pt[0], pt[1])
        started = true
      } else {
        ctx.lineTo(pt[0], pt[1])
      }
    }
    ctx.stroke()
  }

  private drawScene(): void {
    const ctx = this.ctx
    const w = ctx.width
    const h = ctx.height
    if (w <= 4 || h <= 4) return
    ctx.clearRect(0, 0, w, h)

    const nightVision = this.c.isNight
    const ev = this.event
    const obsLat = Number.isFinite(this.observerLat) ? clamp(this.observerLat, -85, 85) : 39.9
    const obsLon = Number.isFinite(this.observerLon) ? wrapLonDeg(this.observerLon) : 116.4
    const eased = easeOutCubic(this.animProgress)

    // 入场动效（复刻参考 4 帧）：
    // 地球从 0.56× 阻尼放大至 1.0×，同时从偏西 66° 东转聚焦到用户所在半球
    const maxRadius = Math.min(w * 0.36, h * 0.435)
    const radius = maxRadius * (0.56 + 0.44 * eased)
    const targetCamLat = clamp(obsLat - 6, -54, 54)
    const targetCamLon = wrapLonDeg(obsLon + 6)
    const camLat = clamp(targetCamLat - 8 * (1 - eased), -60, 60)
    const camLon = wrapLonDeg(targetCamLon - 66 * (1 - eased))

    const camF = latLonToVec3(camLat, camLon)
    const camE = normalize3({ x: -Math.sin(camLon * DEG2RAD), y: Math.cos(camLon * DEG2RAD), z: 0 })
    const camN = normalize3(cross3(camF, camE))

    const passTimeMs = ev !== undefined ? (ev.satStartAt ?? ev.at) : this.nowMs
    const isPreview = ev !== undefined && ev.id.endsWith('-preview')
    const sunVec = computeSolarSubpoint(passTimeMs, obsLat, obsLon, isPreview)

    const cx = w * 0.5
    const cy = h * 0.52

    // 计算 3D 轨道环与前后遮挡关系
    const orbitReveal = smoothstep(0.30, 0.86, this.animProgress)
    const basis = computeOrbitBasis(obsLat, obsLon, ev?.satStartAz, ev?.satEndAz, ev?.satMaxAlt)
    const backLimbPts: number[][] = []
    const frontPts: number[][] = []
    const steps = 160
    if (orbitReveal > 0.01) {
      for (let i = 0; i <= steps; i++) {
        const theta = (i / steps) * Math.PI * 2
        const cosT = Math.cos(theta)
        const sinT = Math.sin(theta)
        const qx = ORBIT_RADIUS_EARTH * (cosT * basis.p0.x + sinT * basis.t0.x)
        const qy = ORBIT_RADIUS_EARTH * (cosT * basis.p0.y + sinT * basis.t0.y)
        const qz = ORBIT_RADIUS_EARTH * (cosT * basis.p0.z + sinT * basis.t0.z)
        const u = qx * camE.x + qy * camE.y + qz * camE.z
        const v = qx * camN.x + qy * camN.y + qz * camN.z
        const depth = qx * camF.x + qy * camF.y + qz * camF.z
        const sx = cx + u * radius
        const sy = cy - v * radius
        const outsideGlobe = (u * u + v * v) >= 0.96
        if (depth >= 0) {
          frontPts.push([sx, sy, 1])
          backLimbPts.push([sx, sy, -1])
        } else if (outsideGlobe) {
          backLimbPts.push([sx, sy, 1])
          frontPts.push([sx, sy, -1])
        } else {
          backLimbPts.push([sx, sy, -1])
          frontPts.push([sx, sy, -1])
        }
      }
    }

    // Layer 1: 地球背面超出边缘外露的轨道弧段（被地球本体遮挡的真实 3D 层次）
    if (orbitReveal > 0.01) {
      const backColor = nightVision
        ? `rgba(255, 130, 108, ${(0.36 * orbitReveal).toFixed(2)})`
        : `rgba(186, 204, 228, ${(0.42 * orbitReveal).toFixed(2)})`
      this.drawOrbitSegment(ctx, backLimbPts, backColor, 1.35)
    }

    // Layer 2: 3D 球面地球本体（动画中用 148px 保丝滑，定焦后缓存 228px 高清球体）
    const settled = this.animProgress >= 1
    let globePm: image.PixelMap | undefined = undefined
    let shouldReleaseTemp = false
    if (settled) {
      const key = `${Math.round(camLat * 10)}:${Math.round(camLon * 10)}:${nightVision ? 1 : 0}:${this.atlas !== undefined ? 1 : 0}:${Math.round(sunVec.x * 100)}`
      if (this.settledGlobePm === undefined || this.settledGlobeKey !== key) {
        this.releaseSettledGlobe()
        this.settledGlobePm = this.rasterizeEarthGlobe(228, camE, camN, camF, sunVec, nightVision)
        this.settledGlobeKey = key
      }
      globePm = this.settledGlobePm
    } else {
      globePm = this.rasterizeEarthGlobe(148, camE, camN, camF, sunVec, nightVision)
      shouldReleaseTemp = true
    }

    if (globePm !== undefined) {
      ctx.drawImage(globePm, cx - radius, cy - radius, radius * 2, radius * 2)
      if (shouldReleaseTemp) {
        try { globePm.release() } catch (_e) {}
      }
    } else {
      // 极端回退：纯蓝灰球体兜底，绝不空白
      ctx.beginPath()
      ctx.arc(cx, cy, radius, 0, Math.PI * 2)
      ctx.fillStyle = nightVision ? '#261012' : '#24344E'
      ctx.fill()
    }

    // 外圈微弱大气层轮廓环
    ctx.beginPath()
    ctx.arc(cx, cy, radius + 0.6, 0, Math.PI * 2)
    ctx.strokeStyle = nightVision ? 'rgba(255, 110, 92, 0.24)' : 'rgba(170, 200, 236, 0.22)'
    ctx.lineWidth = 0.9
    ctx.stroke()

    // 暗夜半球细腻城市微光点群（仅渲染可见面且处于晨昏线夜侧的城市集群）
    for (let i = 0; i < NIGHT_CITY_LIGHTS.length; i++) {
      const city = NIGHT_CITY_LIGHTS[i]
      const cv = latLonToVec3(city.lat, city.lon)
      const depth = dot3(cv, camF)
      if (depth <= 0.10) continue
      const sDot = dot3(cv, sunVec)
      if (sDot > 0.05) continue
      const nightness = smoothstep(0.05, -0.14, sDot)
      const limbFade = smoothstep(0.10, 0.34, depth)
      const alpha = nightness * limbFade * city.weight * (0.55 + 0.35 * eased)
      if (alpha < 0.06) continue
      const cu = dot3(cv, camE)
      const cvn = dot3(cv, camN)
      const sx = cx + cu * radius
      const sy = cy - cvn * radius
      const dotR = (0.85 + city.weight * 0.75) * (0.7 + 0.3 * eased)
      ctx.beginPath()
      ctx.arc(sx, sy, dotR * 2.1, 0, Math.PI * 2)
      ctx.fillStyle = nightVision
        ? `rgba(255, 130, 98, ${(alpha * 0.22).toFixed(2)})`
        : `rgba(235, 240, 252, ${(alpha * 0.20).toFixed(2)})`
      ctx.fill()
      ctx.beginPath()
      ctx.arc(sx, sy, dotR, 0, Math.PI * 2)
      ctx.fillStyle = nightVision
        ? `rgba(255, 178, 148, ${(alpha * 0.85).toFixed(2)})`
        : `rgba(246, 248, 255, ${(alpha * 0.82).toFixed(2)})`
      ctx.fill()
    }

    // 用户当前位置蓝点（随地球自转精确定位）
    if (orbitReveal > 0.05) {
      const obsVec = latLonToVec3(obsLat, obsLon)
      const obsDepth = dot3(obsVec, camF)
      if (obsDepth > 0.02) {
        const ou = dot3(obsVec, camE)
        const ov = dot3(obsVec, camN)
        const ox = cx + ou * radius
        const oy = cy - ov * radius
        ctx.beginPath()
        ctx.arc(ox, oy, 7.2, 0, Math.PI * 2)
        ctx.fillStyle = nightVision
          ? `rgba(255, 96, 68, ${(0.28 * orbitReveal).toFixed(2)})`
          : `rgba(38, 148, 255, ${(0.30 * orbitReveal).toFixed(2)})`
        ctx.fill()
        ctx.beginPath()
        ctx.arc(ox, oy, 3.6, 0, Math.PI * 2)
        ctx.fillStyle = nightVision
          ? `rgba(255, 108, 78, ${orbitReveal.toFixed(2)})`
          : `rgba(30, 144, 255, ${orbitReveal.toFixed(2)})`
        ctx.fill()
      }
    }

    // Layer 3: 地球正面凌空 3D 轨道环 + 发光白色卫星亮点
    if (orbitReveal > 0.01) {
      const glowColor = nightVision
        ? `rgba(255, 142, 118, ${(0.24 * orbitReveal).toFixed(2)})`
        : `rgba(196, 220, 250, ${(0.26 * orbitReveal).toFixed(2)})`
      const coreColor = nightVision
        ? `rgba(255, 186, 166, ${(0.86 * orbitReveal).toFixed(2)})`
        : `rgba(228, 236, 248, ${(0.86 * orbitReveal).toFixed(2)})`
      this.drawOrbitSegment(ctx, frontPts, glowColor, 3.8)
      this.drawOrbitSegment(ctx, frontPts, coreColor, 1.55)

      // 计算卫星在 3D 轨道环上的实时位置角 thetaSat
      let thetaSat = -0.34
      if (ev !== undefined) {
        const startMs = ev.satStartAt ?? ev.at
        const endMs = ev.satEndAt ?? (startMs + 360000)
        if (this.nowMs < startMs) {
          const secsToRise = clamp((startMs - this.nowMs) / 1000, 0, 1800)
          // 临近过境时，白点从西南/西北来向缓缓逼近过顶位置
          thetaSat = -0.14 - (secsToRise / 1800) * 0.56
        } else {
          const span = Math.max(60000, endMs - startMs)
          const passFrac = clamp((this.nowMs - startMs) / span, 0, 1)
          thetaSat = -0.22 + passFrac * 0.44
        }
      }
      const cosS = Math.cos(thetaSat)
      const sinS = Math.sin(thetaSat)
      const sx3 = ORBIT_RADIUS_EARTH * (cosS * basis.p0.x + sinS * basis.t0.x)
      const sy3 = ORBIT_RADIUS_EARTH * (cosS * basis.p0.y + sinS * basis.t0.y)
      const sz3 = ORBIT_RADIUS_EARTH * (cosS * basis.p0.z + sinS * basis.t0.z)
      const su = sx3 * camE.x + sy3 * camE.y + sz3 * camE.z
      const sv = sx3 * camN.x + sy3 * camN.y + sz3 * camN.z
      const sDepth = sx3 * camF.x + sy3 * camF.y + sz3 * camF.z
      if (sDepth >= -0.05 || (su * su + sv * sv) >= 0.96) {
        const satX = cx + su * radius
        const satY = cy - sv * radius
        ctx.beginPath()
        ctx.arc(satX, satY, 8.5, 0, Math.PI * 2)
        ctx.fillStyle = nightVision
          ? `rgba(255, 196, 174, ${(0.28 * orbitReveal).toFixed(2)})`
          : `rgba(255, 255, 255, ${(0.26 * orbitReveal).toFixed(2)})`
        ctx.fill()
        ctx.beginPath()
        ctx.arc(satX, satY, 3.6, 0, Math.PI * 2)
        ctx.fillStyle = nightVision
          ? `rgba(255, 224, 212, ${orbitReveal.toFixed(2)})`
          : `rgba(255, 255, 255, ${orbitReveal.toFixed(2)})`
        ctx.fill()
      }
    }
  }

  private passVisible(): boolean {
    return this.event?.satVisible !== false
  }

  private passStartMs(): number | undefined {
    return this.event?.satStartAt ?? this.event?.at
  }

  private passEndMs(): number | undefined {
    const startMs = this.passStartMs()
    if (this.event?.satEndAt !== undefined) return this.event.satEndAt
    if (startMs === undefined) return undefined
    return startMs + Math.max(240, this.event?.satDurationSec ?? 360) * 1000
  }

  private passPeakMs(): number | undefined {
    if (this.event?.at !== undefined) return this.event.at
    const s = this.passStartMs()
    const e = this.passEndMs()
    return s !== undefined && e !== undefined ? Math.round((s + e) * 0.5) : undefined
  }

  private maxAltText(): string {
    const alt = this.event?.satMaxAlt
    return alt !== undefined && Number.isFinite(alt) ? `${Math.round(alt)}°` : '--'
  }

  private magText(): string {
    const mag = this.event?.satMag
    if (mag === undefined || !Number.isFinite(mag) || mag >= 90) return ''
    return this.isZh() ? `星等 ${mag.toFixed(1)}` : `Mag ${mag.toFixed(1)}`
  }

  build() {
    Column({ space: 0 }) {
      // 顶部：居中卫星名 + 超大细体倒计时 + 右上角关闭圆钮
      Stack({ alignContent: Alignment.TopEnd }) {
        Column({ space: 4 }) {
          Text(this.cleanSatelliteTitle())
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.isNight ? '#E89B8B' : 'rgba(232, 238, 248, 0.82)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.countdownText())
            .fontSize(this.compactHeight ? 30 : 35)
            .fontWeight(FontWeight.Lighter)
            .fontColor(this.c.isNight ? '#FFB2A0' : '#F6F8FC')
            .fontFeature('"tnum" 1')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.isPassingNow()) {
            Text(this.isZh() ? '正在过境 · 剩余可见时间' : 'Passing overhead · remaining')
              .fontSize(10.5)
              .fontColor(this.c.isNight ? '#FF8A72' : '#78B9FF')
          }
        }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 16, left: 36, right: 36, bottom: 2 })

        Button('×', { type: ButtonType.Circle })
          .width(28)
          .height(28)
          .fontSize(15)
          .fontColor(this.c.isNight ? '#D88D7E' : 'rgba(220, 228, 240, 0.78)')
          .backgroundColor(this.c.isNight ? 'rgba(255, 96, 76, 0.14)' : 'rgba(255, 255, 255, 0.10)')
          .margin({ top: 12, right: 12 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onDismiss() })
      }
        .width('100%')

      // 中部核心：纯深空 3D 旋转地球 + 晨昏线 + 夜灯 + 3D 悬空轨道环 + 用户蓝点 + 卫星白点
      Canvas(this.ctx)
        .width('100%')
        .height(this.compactHeight ? 156 : 196)
        .onReady(() => {
          this.canvasReady = true
          this.drawScene()
        })

      // 下方详细信息面板：可见性标签 + 升起/最高仰角/落下三列遥测 + 操作按钮
      Column({ space: 10 }) {
        Divider()
          .color(this.c.isNight ? 'rgba(255, 108, 86, 0.14)' : 'rgba(255, 255, 255, 0.08)')

        Row({ space: 6 }) {
          Text(this.passVisible()
            ? (this.isZh() ? '肉眼可见' : 'Naked-eye')
            : (this.isZh() ? '微弱/地影' : 'Faint'))
            .fontSize(10.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.isNight ? '#FF9882' : (this.passVisible() ? '#6EE7B7' : '#FCD34D'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.c.isNight
              ? 'rgba(255, 96, 76, 0.14)'
              : (this.passVisible() ? 'rgba(16, 185, 129, 0.16)' : 'rgba(245, 158, 11, 0.16)'))
            .borderRadius(UI_RADIUS_PILL)
          if (this.magText().length > 0) {
            Text(this.magText())
              .fontSize(10.5)
              .fontColor(this.c.isNight ? '#D89688' : '#C8D3E4')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.c.isNight ? 'rgba(255, 96, 76, 0.10)' : 'rgba(255, 255, 255, 0.07)')
              .borderRadius(UI_RADIUS_PILL)
          }
          if (this.durationLabel().length > 0) {
            Text(this.durationLabel())
              .fontSize(10.5)
              .fontColor(this.c.isNight ? '#C88578' : '#9EB0C9')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.c.isNight ? 'rgba(255, 96, 76, 0.10)' : 'rgba(255, 255, 255, 0.07)')
              .borderRadius(UI_RADIUS_PILL)
          }
        }
          .width('100%')
          .justifyContent(FlexAlign.Center)

        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(this.isZh() ? '升起' : 'Rise')
              .fontSize(10)
              .fontColor(this.c.isNight ? '#B8766A' : '#8596B0')
            Text(formatClock(this.passStartMs()))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.isNight ? '#FFB8A8' : '#F0F4FA')
              .fontFeature('"tnum" 1')
            Text(compassLabel(this.event?.satStartAz, this.isZh()))
              .fontSize(10)
              .fontColor(this.c.isNight ? '#C8897C' : '#9AA9C0')
              .maxLines(1)
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 7, bottom: 7, left: 4, right: 4 })
            .backgroundColor(this.c.isNight ? 'rgba(255, 96, 76, 0.08)' : 'rgba(255, 255, 255, 0.05)')
            .borderRadius(12)

          Column({ space: 2 }) {
            Text(this.isZh() ? '最高仰角' : 'Peak Alt')
              .fontSize(10)
              .fontColor(this.c.isNight ? '#B8766A' : '#8596B0')
            Text(this.maxAltText())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.c.isNight ? '#FF927A' : '#7BC4FF')
              .fontFeature('"tnum" 1')
            Text((this.isZh() ? '过顶 ' : 'Max ') + formatClock(this.passPeakMs()))
              .fontSize(10)
              .fontColor(this.c.isNight ? '#C8897C' : '#9AA9C0')
              .maxLines(1)
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 7, bottom: 7, left: 4, right: 4 })
            .backgroundColor(this.c.isNight ? 'rgba(255, 96, 76, 0.12)' : 'rgba(56, 148, 255, 0.10)')
            .borderRadius(12)

          Column({ space: 2 }) {
            Text(this.isZh() ? '落下' : 'Set')
              .fontSize(10)
              .fontColor(this.c.isNight ? '#B8766A' : '#8596B0')
            Text(formatClock(this.passEndMs()))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.isNight ? '#FFB8A8' : '#F0F4FA')
              .fontFeature('"tnum" 1')
            Text(compassLabel(this.event?.satEndAz, this.isZh()))
              .fontSize(10)
              .fontColor(this.c.isNight ? '#C8897C' : '#9AA9C0')
              .maxLines(1)
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 7, bottom: 7, left: 4, right: 4 })
            .backgroundColor(this.c.isNight ? 'rgba(255, 96, 76, 0.08)' : 'rgba(255, 255, 255, 0.05)')
            .borderRadius(12)
        }
          .width('100%')

        Row({ space: 10 }) {
          Button(this.isZh() ? '星图追踪' : 'Track in Sky', { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(38)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.isNight ? '#F2B2A4' : '#E6ECF5')
            .backgroundColor(this.c.isNight ? 'rgba(255, 96, 76, 0.16)' : 'rgba(255, 255, 255, 0.11)')
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.onTrackInSky() })

          Button(this.liveViewActive
            ? (this.isZh() ? '停止实况窗' : 'Stop Live View')
            : (this.isZh() ? '开启实况窗' : 'Start Live View'), { type: ButtonType.Capsule })
            .layoutWeight(1.2)
            .height(38)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.liveViewActive
              ? (this.c.isNight ? '#F2B2A4' : '#E6ECF5')
              : (this.c.isNight ? '#1A0606' : '#08111F'))
            .backgroundColor(this.liveViewActive
              ? (this.c.isNight ? 'rgba(255, 96, 76, 0.22)' : 'rgba(255, 255, 255, 0.16)')
              : (this.c.isNight ? '#FF6B4A' : '#EBF2FC'))
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.onToggleLiveView() })
        }
          .width('100%')
      }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
    }
      .width(this.cardWidth)
      .backgroundColor(this.c.isNight ? 'rgba(18, 5, 6, 0.94)' : 'rgba(8, 10, 16, 0.93)')
      .backdropBlur(32)
      .border({
        width: 0.8,
        color: this.c.isNight ? 'rgba(255, 108, 86, 0.26)' : 'rgba(255, 255, 255, 0.13)'
      })
      .borderRadius(28)
      .shadow({
        radius: 36,
        color: 'rgba(0, 0, 0, 0.60)',
        offsetX: 0,
        offsetY: 14
      })
      .opacity(this.cardOpacity)
      .scale({ x: this.cardScale, y: this.cardScale })
      .clip(true)
  }
}
