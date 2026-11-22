import { Theme } from '@kit.ArkUI'
import { map, mapCommon, MapComponent } from '@kit.MapKit'
import { image } from '@kit.ImageKit'
import { connection } from '@kit.NetworkKit'
import { AsyncCallback, BusinessError } from '@ohos.base'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyCalendarEvent, CalendarEclipseMapData } from '../../state/AstronomyCalendarEvent'
import { calendarText } from '../../state/AstronomyCalendarText'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 日食 / 月食全屏交互地图（在线花瓣地图 + 离线全球平图双态无缝回退）：
// 1. 在线且已授隐私时默认挂载华为花瓣地图（MapType.TERRAIN），叠加精确 Web 墨卡托投影的食带可见区 PixelMap、
//    大地线中心食带折线（自动跨 180° 断开）与经 GCJ-02 纠偏的当前定位蓝点，可自由缩放至城市级别查看；
// 2. 支持顶部一键切换「花瓣地图 / 全球平图」及底部「我的位置」快速回中；
// 3. 断网、未授权联网、Map Kit 异常或 12 秒加载超时时自动无缝回退至离线可双指缩放的 earth_cmap.png 全球平图。

const PETAL_TIMEOUT_MS: number = 12000
const OVERLAY_W: number = 360
const OVERLAY_H: number = 256
const DEG2RAD: number = Math.PI / 180

function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : (v > hi ? hi : v)
}

function createEclipseMercatorPixelMap(data: CalendarEclipseMapData, isNight: boolean): image.PixelMap | undefined {
  const buf = new ArrayBuffer(OVERLAY_W * OVERLAY_H * 4)
  const out = new Uint8Array(buf)

  if (data.kind === 'lunar' && Array.isArray(data.subLunarPoints) && data.subLunarPoints.length > 0) {
    const subPts = data.subLunarPoints
    const n = subPts.length
    const sinSLat: number[] = []
    const cosSLat: number[] = []
    const sLonRad: number[] = []
    for (let i = 0; i < n; i++) {
      const pt = subPts[i]
      const latR = (pt[0] ?? 0) * DEG2RAD
      sinSLat.push(Math.sin(latR))
      cosSLat.push(Math.cos(latR))
      sLonRad.push((pt[1] ?? 0) * DEG2RAD)
    }
    const uStart = n >= 5 ? 1 : 0
    const uEnd = n >= 5 ? 3 : (n - 1)
    const midIdx = Math.floor(n / 2)
    const mainTotal = uEnd - uStart + 1

    for (let y = 0; y < OVERLAY_H; y++) {
      const mercY = Math.PI * (1 - (2 * (y + 0.5)) / OVERLAY_H)
      const latR = Math.atan(Math.sinh(mercY))
      const sinLat = Math.sin(latR)
      const cosLat = Math.cos(latR)
      const rowOff = y * OVERLAY_W * 4
      for (let x = 0; x < OVERLAY_W; x++) {
        const lonR = (-180 + ((x + 0.5) / OVERLAY_W) * 360) * DEG2RAD
        let visCount = 0
        let mainVisCount = 0
        let midVis = false
        for (let k = 0; k < n; k++) {
          const sinAlt = sinLat * sinSLat[k] + cosLat * cosSLat[k] * Math.cos(lonR - sLonRad[k])
          if (sinAlt >= -0.008) {
            visCount++
            if (k >= uStart && k <= uEnd) mainVisCount++
            if (k === midIdx) midVis = true
          }
        }
        const off = rowOff + x * 4
        if (mainVisCount === mainTotal) {
          // 全程可见（本影全程）：温暖暗红半透明，下方花瓣地图城市清晰可读
          out[off] = isNight ? 215 : 206
          out[off + 1] = isNight ? 58 : 74
          out[off + 2] = isNight ? 40 : 46
          out[off + 3] = 132
        } else if (midVis || mainVisCount > 0) {
          // 月出/月落带食
          out[off] = isNight ? 196 : 222
          out[off + 1] = isNight ? 72 : 122
          out[off + 2] = isNight ? 52 : 82
          out[off + 3] = 92
        } else if (visCount > 0) {
          // 半影可见
          out[off] = isNight ? 176 : 228
          out[off + 1] = isNight ? 80 : 154
          out[off + 2] = isNight ? 60 : 118
          out[off + 3] = 52
        } else {
          // 不可见区轻度暗罩
          out[off] = isNight ? 18 : 22
          out[off + 1] = isNight ? 8 : 34
          out[off + 2] = isNight ? 10 : 56
          out[off + 3] = 72
        }
      }
    }
  } else if (data.kind === 'solar') {
    const cols = data.cols ?? 72
    const rows = data.rows ?? 36
    const grid = data.grid ?? ''
    if (grid.length === cols * rows) {
      for (let y = 0; y < OVERLAY_H; y++) {
        const mercY = Math.PI * (1 - (2 * (y + 0.5)) / OVERLAY_H)
        const latDeg = Math.atan(Math.sinh(mercY)) / DEG2RAD
        const gy = clamp(((90 - latDeg) / 180) * rows - 0.5, 0, rows - 1)
        const r0 = Math.floor(gy)
        const r1 = Math.min(rows - 1, r0 + 1)
        const fy = gy - r0
        const rowOff = y * OVERLAY_W * 4
        for (let x = 0; x < OVERLAY_W; x++) {
          const gx = ((x + 0.5) / OVERLAY_W) * cols - 0.5
          const c0 = ((Math.floor(gx) % cols) + cols) % cols
          const c1 = (c0 + 1) % cols
          const fx = gx - Math.floor(gx)
          const v00 = grid.charCodeAt(r0 * cols + c0) - 48
          const v10 = grid.charCodeAt(r0 * cols + c1) - 48
          const v01 = grid.charCodeAt(r1 * cols + c0) - 48
          const v11 = grid.charCodeAt(r1 * cols + c1) - 48
          const top = v00 + (v10 - v00) * fx
          const bot = v01 + (v11 - v01) * fx
          const val = top + (bot - top) * fy
          if (val <= 0.12) continue
          const off = rowOff + x * 4
          const norm = clamp(val / 3.0, 0, 1)
          if (isNight) {
            out[off] = Math.round(145 + norm * 75)
            out[off + 1] = Math.round(48 + norm * 24)
            out[off + 2] = Math.round(36 + norm * 16)
            out[off + 3] = Math.round(48 + norm * 98)
          } else {
            out[off] = Math.round(58 - norm * 32)
            out[off + 1] = Math.round(74 - norm * 40)
            out[off + 2] = Math.round(102 - norm * 50)
            out[off + 3] = Math.round(44 + norm * 102)
          }
        }
      }
    }
  }

  try {
    const opts: image.InitializationOptions = {
      size: { width: OVERLAY_W, height: OVERLAY_H },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.UNPREMUL,
      editable: false
    }
    return image.createPixelMapSync(buf, opts)
  } catch (_err) {
    return undefined
  }
}

function splitCentralPathSegments(path: number[][]): mapCommon.LatLng[][] {
  const segments: mapCommon.LatLng[][] = []
  let current: mapCommon.LatLng[] = []
  let prevLon = 0
  for (let i = 0; i < path.length; i++) {
    const pt = path[i]
    const lat = clamp(pt[0] ?? 0, -84.5, 84.5)
    const lon = pt[1] ?? 0
    if (current.length > 0 && Math.abs(lon - prevLon) > 90) {
      if (current.length >= 2) segments.push(current)
      current = []
    }
    current.push({ latitude: lat, longitude: lon })
    prevLon = lon
  }
  if (current.length >= 2) segments.push(current)
  return segments
}

@Component
export struct CalendarEclipsePetalModal {
  @Prop event: AstronomyCalendarEvent | undefined = undefined
  @Prop mapData: CalendarEclipseMapData | undefined = undefined
  @Prop language: string = 'zh'
  @Prop observerLat: number = 39.9
  @Prop observerLon: number = 116.4
  @Prop earthMapUri: string = ''
  @Prop onlineMapAllowed: boolean = false
  onClose: () => void = () => {}

  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private usePetalMode: boolean = true
  @State private petalStarted: boolean = false
  @State private petalReady: boolean = false
  @State private petalFailed: boolean = false
  @State private zoomScale: number = 1.0
  @State private baseZoomScale: number = 1.0
  @State private panX: number = 0
  @State private panY: number = 0
  @State private basePanX: number = 0
  @State private basePanY: number = 0

  private offlineSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private offlineCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.offlineSettings)
  private controller?: map.MapComponentController
  private overlayRef?: map.ImageOverlay
  private markerRef?: map.Marker
  private polylines: map.MapPolyline[] = []
  private timeoutId: number = -1
  private alive: boolean = true

  private mapOptions: mapCommon.MapOptions = {
    position: { target: { latitude: 35.0, longitude: 105.0 }, zoom: 3 },
    mapType: mapCommon.MapType.TERRAIN,
    dayNightMode: mapCommon.DayNightMode.AUTO,
    minZoom: 2,
    maxZoom: 12,
    scrollGesturesEnabled: true,
    zoomGesturesEnabled: true,
    rotateGesturesEnabled: false,
    tiltGesturesEnabled: false,
    zoomControlsEnabled: false,
    compassControlsEnabled: false,
    myLocationControlsEnabled: false,
    scaleControlsEnabled: true
  }

  private mapCallback: AsyncCallback<map.MapComponentController> = (error: BusinessError,
    controller: map.MapComponentController): void => {
    if (error || !this.alive || !this.petalStarted) {
      this.onPetalError()
      return
    }
    this.controller = controller
    const events = controller.getEventManager()
    events.on('mapLoad', () => { void this.onPetalLoad() })
    events.on('error', (_err: BusinessError) => { this.onPetalError() })
  }

  onWillApplyTheme(theme: Theme): void {
    const prevNight = this.c.isNight
    this.c = slotsFromTheme(theme)
    if (prevNight !== this.c.isNight) {
      this.mapOptions.dayNightMode = this.c.isNight ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.AUTO
      if (this.petalReady && this.controller) {
        try {
          this.controller.setDayNightMode(this.c.isNight ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.AUTO)
        } catch (_e) {}
        void this.renderPetalOverlays()
      }
      if (!this.usePetalMode || this.petalFailed) {
        this.drawOfflineCanvas()
      }
    }
  }

  aboutToAppear(): void {
    this.alive = true
    const canPetal = this.canUsePetalOnline()
    this.usePetalMode = canPetal
    if (canPetal) {
      this.startPetalMap()
    }
  }

  aboutToDisappear(): void {
    this.alive = false
    this.clearPetalTimeout()
    this.clearPetalOverlays()
    this.petalStarted = false
    this.controller = undefined
  }

  private t(zh: string, en: string): string {
    return calendarText(this.language, zh, en)
  }

  private hasNetwork(): boolean {
    try {
      return connection.hasDefaultNetSync()
    } catch (_err) {
      return true
    }
  }

  private canUsePetalOnline(): boolean {
    return this.onlineMapAllowed && this.hasNetwork()
  }

  private clearPetalTimeout(): void {
    if (this.timeoutId >= 0) {
      clearTimeout(this.timeoutId)
      this.timeoutId = -1
    }
  }

  private clearPetalOverlays(): void {
    if (this.overlayRef !== undefined) {
      try { this.overlayRef.remove() } catch (_e) {}
      this.overlayRef = undefined
    }
    if (this.markerRef !== undefined) {
      try { this.markerRef.remove() } catch (_e) {}
      this.markerRef = undefined
    }
    for (let i = 0; i < this.polylines.length; i++) {
      try { this.polylines[i].remove() } catch (_e) {}
    }
    this.polylines = []
  }

  private computeInitialCamera(): mapCommon.CameraPosition {
    const data = this.mapData
    const obsValid = Number.isFinite(this.observerLat) && Number.isFinite(this.observerLon)
    if (data?.kind === 'lunar') {
      if (this.event?.localVisible === true && obsValid && Math.abs(this.observerLat) < 68) {
        return {
          target: { latitude: clamp(this.observerLat * 0.65, -42, 42), longitude: this.observerLon },
          zoom: 2.2
        }
      }
      if (Array.isArray(data.subLunarPoints) && data.subLunarPoints.length > 0) {
        const mid = data.subLunarPoints[Math.floor(data.subLunarPoints.length / 2)]
        return {
          target: { latitude: clamp(mid[0] ?? 10, -42, 42), longitude: mid[1] ?? 105 },
          zoom: 2.2
        }
      }
    }
    if (this.event?.localVisible === true && obsValid && Math.abs(this.observerLat) < 68) {
      return {
        target: { latitude: clamp(this.observerLat, -60, 60), longitude: this.observerLon },
        zoom: 3.6
      }
    }
    if (data?.kind === 'solar' && Array.isArray(data.centralPath) && data.centralPath.length > 0) {
      const mid = data.centralPath[Math.floor(data.centralPath.length / 2)]
      return {
        target: { latitude: clamp(mid[0] ?? 20, -60, 60), longitude: mid[1] ?? 105 },
        zoom: 3
      }
    }
    return {
      target: {
        latitude: obsValid ? clamp(this.observerLat, -60, 60) : 35,
        longitude: obsValid ? this.observerLon : 105
      },
      zoom: 2.8
    }
  }

  private startPetalMap(): void {
    this.clearPetalTimeout()
    this.clearPetalOverlays()
    this.petalReady = false
    this.petalFailed = false
    this.controller = undefined
    this.mapOptions.position = this.computeInitialCamera()
    this.mapOptions.dayNightMode = this.c.isNight ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.AUTO
    if (!this.canUsePetalOnline()) {
      this.petalStarted = false
      this.petalFailed = true
      this.usePetalMode = false
      return
    }
    this.petalStarted = true
    this.timeoutId = setTimeout(() => {
      if (!this.alive || this.petalReady) return
      this.onPetalError()
    }, PETAL_TIMEOUT_MS)
  }

  private onPetalError(): void {
    this.clearPetalTimeout()
    this.clearPetalOverlays()
    this.petalReady = false
    this.petalFailed = true
    this.petalStarted = false
    this.usePetalMode = false
    this.controller = undefined
  }

  private async toMapCoordinate(latitude: number, longitude: number): Promise<mapCommon.LatLng> {
    const point: mapCommon.LatLng = { latitude: latitude, longitude: longitude }
    try {
      const context = this.getUIContext().getHostContext()
      if (!context) return point
      const points = await map.rectifyCoordinate(context, [{
        coordinateType: mapCommon.CoordinateType.WGS84,
        location: point
      }])
      if (points && points.length > 0) return points[0].location
    } catch (_err) {
      // Fallback to raw WGS84 outside mainland China
    }
    return point
  }

  private async onPetalLoad(): Promise<void> {
    if (!this.alive || !this.petalStarted) return
    this.clearPetalTimeout()
    this.petalReady = true
    this.petalFailed = false
    const controller = this.controller
    if (!controller) return
    try {
      controller.setDayNightMode(this.c.isNight ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.AUTO)
    } catch (_e) {}
    await this.renderPetalOverlays()
  }

  private async renderPetalOverlays(): Promise<void> {
    const controller = this.controller
    const data = this.mapData
    if (!this.alive || !controller || data === undefined) return
    this.clearPetalOverlays()

    // 1. 叠加精确 Web 墨卡托投影的日/月食可见区半透明热力层
    const pm = createEclipseMercatorPixelMap(data, this.c.isNight)
    if (pm !== undefined) {
      try {
        this.overlayRef = await controller.addImageOverlay({
          bounds: {
            southwest: { latitude: -85.0511, longitude: -180 },
            northeast: { latitude: 85.0511, longitude: 180 }
          },
          image: pm,
          transparency: 0,
          clickable: false,
          zIndex: 5
        })
      } catch (_err) {
        // Keep base map & central path visible even if overlay fails
      } finally {
        try { pm.release() } catch (_e) {}
      }
    }

    if (!this.alive || this.controller !== controller) return

    // 2. 日食中心食带（全食带/环食带）双层大地线折线，自动跨 180° 断开
    if (data.kind === 'solar' && Array.isArray(data.centralPath) && data.centralPath.length >= 2) {
      const segments = splitCentralPathSegments(data.centralPath)
      for (let i = 0; i < segments.length; i++) {
        const seg = segments[i]
        try {
          const halo = await controller.addPolyline({
            points: seg,
            color: this.c.isNight ? 0x66FFA082 : 0x88FFFFFF,
            width: 16,
            geodesic: true,
            clickable: false,
            zIndex: 8
          })
          this.polylines.push(halo)
          const core = await controller.addPolyline({
            points: seg,
            color: this.c.isNight ? 0xF0FF7043 : 0xF0FF5722,
            width: 8,
            geodesic: true,
            clickable: false,
            zIndex: 10
          })
          this.polylines.push(core)
        } catch (_err) {
          // Ignore individual segment rejection
        }
      }
    }

    if (!this.alive || this.controller !== controller) return

    // 3. 当前观测位置蓝点（含境内 GCJ-02 纠偏）
    if (Number.isFinite(this.observerLat) && Number.isFinite(this.observerLon)) {
      try {
        const pt = await this.toMapCoordinate(this.observerLat, this.observerLon)
        if (!this.alive || this.controller !== controller) return
        this.markerRef = await controller.addMarker({
          position: pt,
          icon: $r('app.media.ic_map_pin_blue'),
          zIndex: 20,
          clickable: false
        })
      } catch (_err) {
        // Ignore marker failure
      }
    }
  }

  private async recenterToObserver(): Promise<void> {
    const controller = this.controller
    if (!controller || !this.petalReady) return
    if (!Number.isFinite(this.observerLat) || !Number.isFinite(this.observerLon)) return
    const pt = await this.toMapCoordinate(this.observerLat, this.observerLon)
    if (!this.alive || this.controller !== controller) return
    try {
      controller.animateCamera(map.newCameraPosition({ target: pt, zoom: 5 }), 500)
    } catch (_e) {
      try {
        controller.moveCamera(map.newCameraPosition({ target: pt, zoom: 5 }))
      } catch (_e2) {}
    }
  }

  private drawOfflineCanvas(): void {
    const ctx = this.offlineCtx
    const w = ctx.width
    const h = ctx.height
    if (w <= 2 || h <= 2) return
    ctx.clearRect(0, 0, w, h)
    const data = this.mapData
    if (data === undefined) return

    ctx.fillStyle = this.c.isNight ? 'rgba(22, 8, 8, 0.34)' : 'rgba(130, 152, 182, 0.24)'
    ctx.fillRect(0, 0, w, h)

    if (data.kind === 'lunar' && Array.isArray(data.subLunarPoints) && data.subLunarPoints.length > 0) {
      const subPts = data.subLunarPoints
      const cols = 144
      const rows = 72
      const n = subPts.length
      const sinSLat: number[] = []
      const cosSLat: number[] = []
      const sLonRad: number[] = []
      for (let i = 0; i < n; i++) {
        const pt = subPts[i]
        const latR = (pt[0] ?? 0) * DEG2RAD
        sinSLat.push(Math.sin(latR))
        cosSLat.push(Math.cos(latR))
        sLonRad.push((pt[1] ?? 0) * DEG2RAD)
      }
      const uStart = n >= 5 ? 1 : 0
      const uEnd = n >= 5 ? 3 : (n - 1)
      const midIdx = Math.floor(n / 2)
      const mainTotal = uEnd - uStart + 1
      for (let r = 0; r < rows; r++) {
        const y0 = Math.floor((r * h) / rows)
        const y1 = Math.floor(((r + 1) * h) / rows)
        const cellH = Math.max(1, y1 - y0)
        const latR = (90 - ((r + 0.5) / rows) * 180) * DEG2RAD
        const sinLat = Math.sin(latR)
        const cosLat = Math.cos(latR)
        for (let c = 0; c < cols; c++) {
          const lonR = (-180 + ((c + 0.5) / cols) * 360) * DEG2RAD
          let visCount = 0
          let mainVisCount = 0
          let midVis = false
          for (let k = 0; k < n; k++) {
            const sinAlt = sinLat * sinSLat[k] + cosLat * cosSLat[k] * Math.cos(lonR - sLonRad[k])
            if (sinAlt >= -0.008) {
              visCount++
              if (k >= uStart && k <= uEnd) mainVisCount++
              if (k === midIdx) midVis = true
            }
          }
          if (mainVisCount === mainTotal) {
            ctx.fillStyle = this.c.isNight ? 'rgba(220, 62, 42, 0.72)' : 'rgba(205, 86, 54, 0.70)'
          } else if (midVis || mainVisCount > 0) {
            ctx.fillStyle = this.c.isNight ? 'rgba(200, 74, 52, 0.44)' : 'rgba(218, 122, 88, 0.44)'
          } else if (visCount > 0) {
            ctx.fillStyle = this.c.isNight ? 'rgba(180, 82, 60, 0.24)' : 'rgba(224, 152, 124, 0.26)'
          } else {
            ctx.fillStyle = this.c.isNight ? 'rgba(20, 10, 12, 0.36)' : 'rgba(78, 104, 140, 0.34)'
          }
          const x0 = Math.floor((c * w) / cols)
          const x1 = Math.floor(((c + 1) * w) / cols)
          ctx.fillRect(x0, y0, Math.max(1, x1 - x0), cellH)
        }
      }
    } else if (data.kind === 'solar') {
      const cols = data.cols ?? 72
      const rows = data.rows ?? 36
      const grid = data.grid ?? ''
      if (grid.length === cols * rows) {
        for (let r = 0; r < rows; r++) {
          const y0 = Math.floor((r * h) / rows)
          const y1 = Math.floor(((r + 1) * h) / rows)
          const cellH = Math.max(1, y1 - y0)
          for (let c = 0; c < cols; c++) {
            const chCode = grid.charAt(r * cols + c)
            if (chCode === '0') continue
            if (chCode === '3') {
              ctx.fillStyle = this.c.isNight ? 'rgba(220, 72, 52, 0.68)' : 'rgba(30, 38, 52, 0.66)'
            } else if (chCode === '2') {
              ctx.fillStyle = this.c.isNight ? 'rgba(180, 60, 44, 0.48)' : 'rgba(54, 66, 86, 0.50)'
            } else {
              ctx.fillStyle = this.c.isNight ? 'rgba(150, 52, 38, 0.32)' : 'rgba(72, 86, 108, 0.36)'
            }
            const x0 = Math.floor((c * w) / cols)
            const x1 = Math.floor(((c + 1) * w) / cols)
            ctx.fillRect(x0, y0, Math.max(1, x1 - x0), cellH)
          }
        }
      }
      const path = data.centralPath ?? []
      if (path.length >= 2) {
        const drawPath = (strokeColor: string, widthPx: number): void => {
          ctx.strokeStyle = strokeColor
          ctx.lineWidth = widthPx
          ctx.lineCap = 'round'
          ctx.lineJoin = 'round'
          ctx.beginPath()
          let started = false
          let prevLon = 0
          for (let i = 0; i < path.length; i++) {
            const pt = path[i]
            const lat = pt[0] ?? 0
            const lon = pt[1] ?? 0
            const x = ((lon + 180) / 360) * w
            const y = ((90 - lat) / 180) * h
            if (!started || Math.abs(lon - prevLon) > 90) {
              ctx.moveTo(x, y)
              started = true
            } else {
              ctx.lineTo(x, y)
            }
            prevLon = lon
          }
          ctx.stroke()
        }
        drawPath(this.c.isNight ? 'rgba(255, 160, 130, 0.55)' : 'rgba(255, 255, 255, 0.45)', Math.max(4.0, w * 0.012))
        drawPath(this.c.isNight ? '#FF7043' : '#FF5722', Math.max(2.2, w * 0.007))
      }
    }

    ctx.strokeStyle = this.c.isNight ? 'rgba(255,140,120,0.10)' : 'rgba(255,255,255,0.14)'
    ctx.lineWidth = 0.6
    ctx.beginPath()
    ctx.moveTo(0, h * 0.5)
    ctx.lineTo(w, h * 0.5)
    ctx.moveTo(w * 0.5, 0)
    ctx.lineTo(w * 0.5, h)
    ctx.stroke()

    if (Number.isFinite(this.observerLat) && Number.isFinite(this.observerLon)) {
      const px = ((this.observerLon + 180) / 360) * w
      const py = ((90 - this.observerLat) / 180) * h
      ctx.beginPath()
      ctx.arc(px, py, Math.max(4.8, w * 0.015), 0, Math.PI * 2)
      ctx.fillStyle = 'rgba(255, 255, 255, 0.92)'
      ctx.fill()
      ctx.beginPath()
      ctx.arc(px, py, Math.max(3.4, w * 0.011), 0, Math.PI * 2)
      ctx.fillStyle = this.c.isNight ? '#FF6B4A' : '#2979FF'
      ctx.fill()
    }
  }

  private switchMode(toPetal: boolean): void {
    if (toPetal === this.usePetalMode) return
    if (toPetal) {
      if (!this.canUsePetalOnline()) return
      this.usePetalMode = true
      this.startPetalMap()
    } else {
      this.clearPetalTimeout()
      this.clearPetalOverlays()
      this.petalStarted = false
      this.petalReady = false
      this.controller = undefined
      this.usePetalMode = false
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.usePetalMode && this.petalStarted && !this.petalFailed) {
        // 在线花瓣地图（支持自由双指缩放至城市、查看食带路径与当前定位）
        MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
          .width('100%')
          .height('100%')
        if (!this.petalReady) {
          Column({ space: 10 }) {
            LoadingProgress().width(28).height(28).color('#64B5F6')
            Text(this.t('正在加载花瓣地图官方底图…', 'Loading Petal Maps…'))
              .fontSize(12)
              .fontColor('#D6E0F0')
          }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor('rgba(8, 12, 20, 0.88)')
            .hitTestBehavior(HitTestMode.None)
        }
      } else {
        // 离线 / 回退全球平图（纯自然地貌 earth_cmap.png + 双指缩放）
        Column({ space: 14 }) {
          Blank()
          Stack({ alignContent: Alignment.Center }) {
            Image($rawfile('stellarium/textures/earth_cmap.png'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Fill)
              .saturate(this.c.isNight ? 0.15 : 0.35)
              .brightness(this.c.isNight ? 0.45 : 1.18)
              .contrast(0.88)
              .accessibilityLevel('no')
            Canvas(this.offlineCtx)
              .width('100%')
              .height('100%')
              .onReady(() => { this.drawOfflineCanvas() })
          }
            .width('100%')
            .aspectRatio(2.0)
            .clip(true)
            .scale({ x: this.zoomScale, y: this.zoomScale })
            .translate({ x: this.panX, y: this.panY })
            .gesture(
              GestureGroup(GestureMode.Parallel,
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => { this.baseZoomScale = this.zoomScale })
                  .onActionUpdate((ev: GestureEvent) => {
                    this.zoomScale = clamp(this.baseZoomScale * ev.scale, 1.0, 4.0)
                    if (this.zoomScale <= 1.02) { this.panX = 0; this.panY = 0 }
                  }),
                PanGesture({ fingers: 1 })
                  .onActionStart(() => { this.basePanX = this.panX; this.basePanY = this.panY })
                  .onActionUpdate((ev: GestureEvent) => {
                    if (this.zoomScale <= 1.02) return
                    const maxPan = 220 * (this.zoomScale - 1)
                    this.panX = clamp(this.basePanX + ev.offsetX, -maxPan, maxPan)
                    this.panY = clamp(this.basePanY + ev.offsetY, -maxPan * 0.6, maxPan * 0.6)
                  })
              )
            )
            .onClick(() => {
              if (this.zoomScale > 1.2) {
                this.zoomScale = 1.0; this.panX = 0; this.panY = 0
              } else {
                this.zoomScale = 2.2
              }
            })
          Text(this.t('离线全球平图 · 双指缩放或轻点放大 · 蓝点为当前位置', 'Offline global map · Pinch or tap to zoom'))
            .fontSize(12)
            .fontColor('#B8C4DA')
          Blank()
        }
          .width('100%')
          .height('100%')
          .padding({ left: 12, right: 12, top: 48, bottom: 72 })
          .backgroundColor('rgba(6, 9, 16, 0.96)')
      }

      // 顶部工具栏：左侧模式切换（花瓣地图 / 全球平图）+ 右侧关闭按钮
      Row({ space: 8 }) {
        if (this.canUsePetalOnline()) {
          Row({ space: 4 }) {
            Text(this.t('花瓣地图', 'Petal Maps'))
              .fontSize(12)
              .fontWeight(this.usePetalMode ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.usePetalMode ? '#09111E' : '#DCE4F2')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.usePetalMode ? '#EBF2FC' : Color.Transparent)
              .borderRadius(UI_RADIUS_PILL)
              .onClick(() => { this.switchMode(true) })
            Text(this.t('全球平图', 'Global Flat'))
              .fontSize(12)
              .fontWeight(!this.usePetalMode ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(!this.usePetalMode ? '#09111E' : '#DCE4F2')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(!this.usePetalMode ? '#EBF2FC' : Color.Transparent)
              .borderRadius(UI_RADIUS_PILL)
              .onClick(() => { this.switchMode(false) })
          }
            .padding(3)
            .backgroundColor('rgba(10, 14, 24, 0.78)')
            .backdropBlur(20)
            .border({ width: 0.6, color: 'rgba(255,255,255,0.16)' })
            .borderRadius(UI_RADIUS_PILL)
        } else {
          Text(this.t('离线全球平图', 'Offline Global Map'))
            .fontSize(12)
            .fontColor('#DCE4F2')
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor('rgba(10, 14, 24, 0.78)')
            .border({ width: 0.6, color: 'rgba(255,255,255,0.14)' })
            .borderRadius(UI_RADIUS_PILL)
        }

        Blank()

        Button('✕', { type: ButtonType.Circle })
          .width(40)
          .height(40)
          .fontSize(16)
          .fontColor('#F3F5FA')
          .backgroundColor('rgba(10, 14, 24, 0.78)')
          .border({ width: 0.6, color: 'rgba(255,255,255,0.16)' })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onClose() })
      }
        .width('100%')
        .padding({ left: 16, right: 16, top: 44 })
        .alignItems(VerticalAlign.Center)

      // 底部悬浮图例与「我的位置」回中按钮
      Row({ space: 10 }) {
        Row({ space: 10 }) {
          if (this.mapData?.kind === 'lunar') {
            Row({ space: 4 }) {
              Row().width(9).height(9).borderRadius(2).backgroundColor('#CE4A2E')
              Text(this.t('全程可见', 'Full')).fontSize(11).fontColor('#E4ECF8')
            }
            Row({ space: 4 }) {
              Row().width(9).height(9).borderRadius(2).backgroundColor('#DE7A52')
              Text(this.t('带食', 'Partial')).fontSize(11).fontColor('#E4ECF8')
            }
          } else {
            Row({ space: 4 }) {
              Row().width(12).height(3).borderRadius(2).backgroundColor('#FF5722')
              Text(this.t('中心食带', 'Central')).fontSize(11).fontColor('#E4ECF8')
            }
            Row({ space: 4 }) {
              Row().width(9).height(9).borderRadius(2).backgroundColor('#42506A')
              Text(this.t('偏食区', 'Partial')).fontSize(11).fontColor('#E4ECF8')
            }
          }
          Row({ space: 4 }) {
            Row().width(8).height(8).borderRadius(4).backgroundColor('#2979FF')
              .border({ width: 1.2, color: '#FFFFFF' })
            Text(this.t('当前位置', 'You')).fontSize(11).fontColor('#E4ECF8')
          }
        }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('rgba(10, 14, 24, 0.80)')
          .backdropBlur(20)
          .border({ width: 0.6, color: 'rgba(255,255,255,0.15)' })
          .borderRadius(UI_RADIUS_PILL)

        if (this.usePetalMode && this.petalReady) {
          Button(this.t('我的位置', 'My Location'), { type: ButtonType.Capsule })
            .height(32)
            .padding({ left: 12, right: 12 })
            .fontSize(11.5)
            .fontColor('#F2F6FC')
            .backgroundColor('rgba(30, 120, 240, 0.88)')
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { void this.recenterToObserver() })
        }
      }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 14, right: 14, bottom: 28 })
        .position({ x: 0, y: '100%' })
        .markAnchor({ x: 0, y: '100%' })
    }
      .width('100%')
      .height('100%')
      .backgroundColor('#060910')
  }
}
