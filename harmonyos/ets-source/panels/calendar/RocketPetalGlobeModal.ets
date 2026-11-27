import { Theme } from '@kit.ArkUI'
import { map, mapCommon, MapComponent } from '@kit.MapKit'
import { image } from '@kit.ImageKit'
import { connection } from '@kit.NetworkKit'
import { AsyncCallback, BusinessError } from '@ohos.base'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import {
  RocketDebrisInfo,
  RocketSimulationData,
  formatBeijingTimeFromIso
} from '../../state/RocketLaunchTypes'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 火箭弹道与 NOTAM 落区 3D 球面地图弹窗（花瓣地图 3D 卫星地球 + 凌空 3D 弧线叠加层 + 离线降级）：
// 1. 启用 Map Kit 原生 3D 球面地球（sphereEnabled / setSphereMapEnabled + 昼夜晨昏线 + 城市灯光）与卫星影像底图；
// 2. 贴地图层绘制地面星下点轨迹（MapPolyline）、NOTAM 红色危险区（MapPolygon）、Q行青色圆（MapCircle）与残骸落点标记（Marker）；
// 3. 顶层透明 Canvas 通过 projection.toScreenLocation(latLng, altitudeMeters) 实时投影绘制凌空百公里的 3D 上升弧、
//    助推器/整流罩/一级回落抛物线与参数敏感性落点散布云（不拦截地图手势）；
// 4. 断网、未授权联网或加载超时自动降级至离线地球弹道总览图。

const PETAL_TIMEOUT_MS: number = 12000

function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : (v > hi ? hi : v)
}

function createDotMarkerPixelMap(r: number, g: number, b: number, size: number = 28): image.PixelMap | undefined {
  const buf = new ArrayBuffer(size * size * 4)
  const out = new Uint8Array(buf)
  const cx = (size - 1) * 0.5
  const outerR = size * 0.44
  const innerR = size * 0.30
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dist = Math.hypot(x - cx, y - cx)
      const off = (y * size + x) * 4
      if (dist <= innerR) {
        out[off] = r; out[off + 1] = g; out[off + 2] = b; out[off + 3] = 255
      } else if (dist <= outerR) {
        out[off] = 255; out[off + 1] = 255; out[off + 2] = 255; out[off + 3] = 235
      } else if (dist <= outerR + 2.2) {
        const alpha = Math.round(110 * (1 - (dist - outerR) / 2.2))
        out[off] = r; out[off + 1] = g; out[off + 2] = b; out[off + 3] = Math.max(0, alpha)
      }
    }
  }
  try {
    return image.createPixelMapSync(buf, {
      size: { width: size, height: size },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.UNPREMUL,
      editable: false
    })
  } catch (_e) {
    return undefined
  }
}

@Component
export struct RocketPetalGlobeModal {
  @Prop simulation: RocketSimulationData | undefined = undefined
  @Prop language: string = 'zh'
  @Prop earthMapUri: string = ''
  @Prop onlineMapAllowed: boolean = false
  onClose: () => void = () => {}

  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private usePetalMode: boolean = true
  @State private petalStarted: boolean = false
  @State private petalReady: boolean = false
  @State private petalFailed: boolean = false
  @State private isSatelliteType: boolean = true
  @State private show3dArcs: boolean = true
  @State private showDispersion: boolean = true
  @State private selectedDebris: RocketDebrisInfo | undefined = undefined

  private controller?: map.MapComponentController
  private mapCallback?: AsyncCallback<map.MapComponentController>
  private mapOptions: mapCommon.MapOptions = {
    position: { target: { latitude: 36.5, longitude: 106.0 }, zoom: 3.6, tilt: 32, bearing: 0 },
    mapType: mapCommon.MapType.SATELLITE,
    sphereEnabled: true,
    compassControlsEnabled: false,
    myLocationControlsEnabled: false,
    zoomControlsEnabled: false,
    scaleControlsEnabled: true,
    rotateGesturesEnabled: true,
    tiltGesturesEnabled: true,
    zoomGesturesEnabled: true,
    scrollGesturesEnabled: true
  }
  private polylineRefs: map.MapPolyline[] = []
  private polygonRefs: map.MapPolygon[] = []
  private circleRefs: map.MapCircle[] = []
  private markerRefs: map.Marker[] = []
  private markerDebrisMap: Map<string, RocketDebrisInfo> = new Map<string, RocketDebrisInfo>()
  private timeoutId: number = -1
  private alive: boolean = false

  private arcSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private arcCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.arcSettings)
  private arcCanvasReady: boolean = false

  private offlineSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private offlineCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.offlineSettings)

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private isZh(): boolean {
    return this.language.toLowerCase().startsWith('zh')
  }

  private t(zh: string, en: string): string {
    return this.isZh() ? zh : en
  }

  private hasNetwork(): boolean {
    try {
      return connection.hasDefaultNetSync()
    } catch (_e) {
      return true
    }
  }

  private canUsePetalOnline(): boolean {
    return this.onlineMapAllowed && this.hasNetwork()
  }

  private computeOverviewCamera(): mapCommon.CameraPosition {
    const sim = this.simulation
    if (!sim) {
      return { target: { latitude: 33.0, longitude: 104.0 }, zoom: 4.3, tilt: 56, bearing: 0 }
    }
    // Oblique side-profile 3D camera positioned slightly south of trajectory midpoint (Reference Img 7!)
    // so elevated ascent & debris arcs visibly arch above the Earth's horizon instead of projecting flat.
    let midLat = sim.site.latDeg
    let midLon = sim.site.lonDeg
    if (sim.trajectory.length > 2) {
      const idx = Math.min(sim.trajectory.length - 1, Math.floor(sim.trajectory.length * 0.35))
      midLat = (sim.site.latDeg + sim.trajectory[idx].lat) * 0.5
      midLon = (sim.site.lonDeg + sim.trajectory[idx].lon) * 0.5
    }
    return {
      target: { latitude: clamp(midLat - 2.6, -62, 62), longitude: midLon },
      zoom: 5.5,
      tilt: 68,
      bearing: 0
    }
  }

  private computeTopDownGlobeCamera(): mapCommon.CameraPosition {
    const sim = this.simulation
    if (!sim) {
      return { target: { latitude: 35.0, longitude: 104.0 }, zoom: 3.4, tilt: 10, bearing: 0 }
    }
    let midLat = sim.site.latDeg
    let midLon = sim.site.lonDeg
    if (sim.trajectory.length > 2) {
      const idx = Math.min(sim.trajectory.length - 1, Math.floor(sim.trajectory.length * 0.4))
      midLat = (sim.site.latDeg + sim.trajectory[idx].lat) * 0.5
      midLon = (sim.site.lonDeg + sim.trajectory[idx].lon) * 0.5
    }
    return {
      target: { latitude: clamp(midLat, -65, 65), longitude: midLon },
      zoom: 3.4,
      tilt: 10,
      bearing: 0
    }
  }

  aboutToAppear(): void {
    this.alive = true
    this.mapCallback = (err: BusinessError, ctrl: map.MapComponentController) => {
      if (!this.alive) return
      if (err || !ctrl) {
        this.onPetalError()
        return
      }
      this.controller = ctrl
      try {
        const evMgr = ctrl.getEventManager()
        evMgr.on('mapLoad', () => {
          void this.onPetalLoad()
        })
        evMgr.on('cameraMove', () => {
          this.redraw3dArcOverlay()
        })
        evMgr.on('cameraIdle', () => {
          this.redraw3dArcOverlay()
        })
        evMgr.on('markerClick', (marker: map.Marker) => {
          const title = marker.getTitle()
          const matched = this.markerDebrisMap.get(title)
          if (matched !== undefined) {
            this.selectedDebris = matched
          }
        })
      } catch (_e) {}
      // In case mapLoad already fired before listener attachment
      setTimeout(() => {
        if (this.alive && this.controller && !this.petalReady) {
          void this.onPetalLoad()
        }
      }, 900)
    }

    if (this.canUsePetalOnline()) {
      this.usePetalMode = true
      this.startPetalMap()
    } else {
      this.usePetalMode = false
      this.petalFailed = true
    }
  }

  aboutToDisappear(): void {
    this.alive = false
    this.clearTimeoutSafe()
    this.clearOverlays()
    this.controller = undefined
  }

  private clearTimeoutSafe(): void {
    if (this.timeoutId >= 0) {
      clearTimeout(this.timeoutId)
      this.timeoutId = -1
    }
  }

  private clearOverlays(): void {
    for (let i = 0; i < this.polylineRefs.length; i++) {
      try { this.polylineRefs[i].remove() } catch (_e) {}
    }
    for (let i = 0; i < this.polygonRefs.length; i++) {
      try { this.polygonRefs[i].remove() } catch (_e) {}
    }
    for (let i = 0; i < this.circleRefs.length; i++) {
      try { this.circleRefs[i].remove() } catch (_e) {}
    }
    for (let i = 0; i < this.markerRefs.length; i++) {
      try { this.markerRefs[i].remove() } catch (_e) {}
    }
    this.polylineRefs = []
    this.polygonRefs = []
    this.circleRefs = []
    this.markerRefs = []
    this.markerDebrisMap.clear()
  }

  private startPetalMap(): void {
    this.clearTimeoutSafe()
    this.clearOverlays()
    this.petalReady = false
    this.petalFailed = false
    this.controller = undefined
    this.mapOptions.position = this.computeOverviewCamera()
    this.mapOptions.mapType = this.isSatelliteType ? mapCommon.MapType.SATELLITE : mapCommon.MapType.TERRAIN
    this.mapOptions.sphereEnabled = true
    this.petalStarted = true
    this.timeoutId = setTimeout(() => {
      if (!this.alive || this.petalReady) return
      this.onPetalError()
    }, PETAL_TIMEOUT_MS)
  }

  private onPetalError(): void {
    this.clearTimeoutSafe()
    this.clearOverlays()
    this.petalReady = false
    this.petalFailed = true
    this.petalStarted = false
    this.usePetalMode = false
    this.controller = undefined
  }

  private async onPetalLoad(): Promise<void> {
    if (!this.alive || !this.controller) return
    this.clearTimeoutSafe()
    this.petalReady = true
    this.petalFailed = false
    const ctrl = this.controller
    // Enable 3D globe with real-time day/night terminator & city lights (API 26), fallback to API 15 setSphereEnabled
    try {
      await ctrl.setSphereMapEnabled(true, {
        sunLightEnabled: true,
        cityLightEnabled: true,
        animateDuration: 450
      })
    } catch (_e1) {
      try {
        ctrl.setSphereEnabled(true, 450)
      } catch (_e2) {}
    }
    try {
      ctrl.setMapType(this.isSatelliteType ? mapCommon.MapType.SATELLITE : mapCommon.MapType.TERRAIN)
    } catch (_e) {}
    await this.renderPetalOverlays()
    this.redraw3dArcOverlay()
  }

  private async renderPetalOverlays(): Promise<void> {
    const ctrl = this.controller
    const sim = this.simulation
    if (!this.alive || !ctrl || !sim) return
    this.clearOverlays()

    // 1. Ground sub-satellite track (geodesic polyline hugging Earth surface)
    if (sim.trajectory.length >= 2) {
      const groundPts: mapCommon.LatLng[] = []
      for (let i = 0; i < sim.trajectory.length; i += 2) {
        groundPts.push({ latitude: sim.trajectory[i].lat, longitude: sim.trajectory[i].lon })
      }
      const last = sim.trajectory[sim.trajectory.length - 1]
      groundPts.push({ latitude: last.lat, longitude: last.lon })
      try {
        const line = await ctrl.addPolyline({
          points: groundPts,
          color: 0xCCDA52FF,
          width: 4,
          geodesic: true,
          zIndex: 5
        })
        this.polylineRefs.push(line)
      } catch (_e) {}
    }

    // 2. NOTAM danger polygon (red) + Q-line circle (cyan)
    if (sim.notam && sim.notam.valid) {
      if (Array.isArray(sim.notam.polygon) && sim.notam.polygon.length >= 3) {
        const polyPts: mapCommon.LatLng[] = []
        for (let i = 0; i < sim.notam.polygon.length; i++) {
          polyPts.push({ latitude: sim.notam.polygon[i][0], longitude: sim.notam.polygon[i][1] })
        }
        try {
          const poly = await ctrl.addPolygon({
            points: polyPts,
            fillColor: 0x4CE83E3E,
            strokeColor: 0xFFFF4646,
            strokeWidth: 4,
            zIndex: 8
          })
          this.polygonRefs.push(poly)
        } catch (_e) {}
      }
      if (sim.notam.hasCircle && sim.notam.circleRadiusKm > 0) {
        try {
          const circle = await ctrl.addCircle({
            center: { latitude: sim.notam.circleLatDeg, longitude: sim.notam.circleLonDeg },
            radius: sim.notam.circleRadiusKm * 1000,
            fillColor: 0x1A38D9E8,
            strokeColor: 0xCC48E8F5,
            strokeWidth: 3,
            zIndex: 7
          })
          this.circleRefs.push(circle)
        } catch (_e) {}
      }
    }

    // 3. Launch pad & Debris impact markers (sleek compact custom dot PixelMaps)
    const padIcon = createDotMarkerPixelMap(255, 86, 72, 26)
    const debInsideIcon = createDotMarkerPixelMap(56, 232, 114, 24)
    const debOutsideIcon = createDotMarkerPixelMap(255, 206, 74, 24)
    const stageIcon = createDotMarkerPixelMap(92, 234, 255, 20)

    try {
      const padMarker = await ctrl.addMarker({
        position: { latitude: sim.site.latDeg, longitude: sim.site.lonDeg },
        icon: padIcon,
        anchorU: 0.5,
        anchorV: 0.5,
        title: this.isZh() ? `发射场：${sim.site.nameZh}` : `Pad: ${sim.site.nameEn}`,
        snippet: `${sim.site.latDeg.toFixed(3)}°N, ${sim.site.lonDeg.toFixed(3)}°E`,
        clickable: true,
        zIndex: 12
      })
      this.markerRefs.push(padMarker)
    } catch (_e) {}

    for (let i = 0; i < sim.debris.length; i++) {
      const deb = sim.debris[i]
      const title = this.isZh() ? deb.labelZh : deb.labelEn
      this.markerDebrisMap.set(title, deb)
      try {
        const m = await ctrl.addMarker({
          position: { latitude: deb.impactLatDeg, longitude: deb.impactLonDeg },
          icon: deb.insideNotam ? debInsideIcon : debOutsideIcon,
          anchorU: 0.5,
          anchorV: 0.5,
          title: title,
          snippet: `${this.t('射程', 'Downrange')} ${deb.downrangeKm.toFixed(1)} km · ${deb.insideNotam ? this.t('航警区内', 'Inside NOTAM') : this.t('区外', 'Outside')}`,
          clickable: true,
          zIndex: 14
        })
        this.markerRefs.push(m)
      } catch (_e) {}
    }

    // 4. Elevated staging milestones (suspended at real altitude on 3D globe!)
    const elevCodes = ['BOOSTER_SEP', 'FAIRING_SEP', 'STAGE_SEP', 'SECO']
    for (let i = 0; i < sim.events.length; i++) {
      const ev = sim.events[i]
      if (!elevCodes.includes(ev.code)) continue
      try {
        const m = await ctrl.addMarker({
          position: { latitude: ev.latDeg, longitude: ev.lonDeg },
          altitude: Math.round(ev.altKm * 1000),
          icon: stageIcon,
          anchorU: 0.5,
          anchorV: 0.5,
          title: this.isZh() ? ev.labelZh : ev.labelEn,
          snippet: `T+${Math.round(ev.tSec)}s · ${ev.altKm.toFixed(1)} km · ${ev.speedKmS.toFixed(2)} km/s`,
          clickable: true,
          zIndex: 15
        })
        this.markerRefs.push(m)
      } catch (_e) {}
    }
  }

  // Project 3D (lat, lon, altMeters) -> screen pixels using Map Kit Projection API 26 toScreenLocation(pos, alt)
  private project3dPoint(proj: map.Projection, lat: number, lon: number, altMeters: number): mapCommon.MapPoint | undefined {
    const pos: mapCommon.LatLng = { latitude: lat, longitude: lon }
    try {
      const pt = proj.toScreenLocation(pos, altMeters)
      if (pt && Number.isFinite(pt.positionX) && Number.isFinite(pt.positionY)) {
        return pt
      }
    } catch (_e1) {
      try {
        const pt2 = proj.toScreenLocation(pos)
        if (pt2 && Number.isFinite(pt2.positionX) && Number.isFinite(pt2.positionY)) {
          return pt2
        }
      } catch (_e2) {}
    }
    return undefined
  }

  private redraw3dArcOverlay(): void {
    const w = this.arcCtx.width
    const h = this.arcCtx.height
    if (!this.arcCanvasReady || w <= 10 || h <= 10) return
    this.arcCtx.clearRect(0, 0, w, h)

    const ctrl = this.controller
    const sim = this.simulation
    if (!ctrl || !sim || !this.petalReady) return

    let proj: map.Projection | undefined = undefined
    try {
      proj = ctrl.getProjection()
    } catch (_e) {
      return
    }
    if (!proj) return

    // Density conversion: MapPoint is in physical px; CanvasRenderingContext2D uses vp
    const dpr = Math.max(1, vp2px(1))
    const toVpX = (px: number): number => px / dpr
    const toVpY = (py: number): number => py / dpr

    // Camera state for front-hemisphere globe occlusion & high-zoom clamping
    let camLat = sim.site.latDeg
    let camLon = sim.site.lonDeg
    let camZoom = 4.4
    try {
      const camPos = ctrl.getCameraPosition()
      if (camPos && camPos.target) {
        camLat = camPos.target.latitude
        camLon = camPos.target.longitude
      }
      if (camPos && Number.isFinite(camPos.zoom)) {
        camZoom = camPos.zoom
      }
    } catch (_e) {}

    // Front-hemisphere check prevents back-of-Earth or extreme-limb points from shooting off the globe!
    const deg2rad = Math.PI / 180
    const sinCamLat = Math.sin(camLat * deg2rad)
    const cosCamLat = Math.cos(camLat * deg2rad)
    const isFrontHemisphere = (lat: number, lon: number, altKm: number): boolean => {
      if (camZoom >= 6.0) return true
      const cosAng = sinCamLat * Math.sin(lat * deg2rad) +
        cosCamLat * Math.cos(lat * deg2rad) * Math.cos((lon - camLon) * deg2rad)
      // At globe zoom levels, clip points past ~74 deg from camera center so lines stay cleanly anchored to the visible sphere
      const horizonLimit = Math.max(0.18, 0.28 - altKm * 0.00018)
      return cosAng >= horizonLimit
    }

    const inSafeCanvas = (x: number, y: number, margin: number): boolean => {
      return Number.isFinite(x) && Number.isFinite(y) &&
        x >= -margin && x <= w + margin && y >= -margin && y <= h + margin
    }

    // 1. Monte-Carlo sensitivity dispersion scatter dots (green inside NOTAM, amber outside)
    if (this.showDispersion && Array.isArray(sim.dispersion) && sim.dispersion.length > 0) {
      for (let i = 0; i < sim.dispersion.length; i++) {
        const dp = sim.dispersion[i]
        if (!isFrontHemisphere(dp[0], dp[1], 0)) continue
        const sp = this.project3dPoint(proj, dp[0], dp[1], 0)
        if (!sp) continue
        const x = toVpX(sp.positionX), y = toVpY(sp.positionY)
        if (!inSafeCanvas(x, y, 8)) continue
        this.arcCtx.beginPath()
        this.arcCtx.arc(x, y, 3.0, 0, Math.PI * 2)
        this.arcCtx.fillStyle = dp[2] === 1 ? 'rgba(56, 232, 114, 0.92)' : 'rgba(255, 184, 58, 0.85)'
        this.arcCtx.fill()
      }
    }

    if (!this.show3dArcs) return

    // Helper: cap projected altitude gracefully at very close zooms (>= 7.5) so local NOTAM view
    // shows a clean grounded re-entry curve into the polygon instead of shooting off screen corners.
    const effectiveAltMeters = (altKm: number): number => {
      if (camZoom >= 7.5) {
        return Math.min(altKm, 18.0) * 1000
      }
      return Math.min(altKm, 480.0) * 1000
    }
    const maxSegJump = w * 0.38

    // 2. Elevated 3D parabolic fallback arcs for booster / fairing / stage1 + vertical curtain ribs to ground
    for (let d = 0; d < sim.debris.length; d++) {
      const deb = sim.debris[d]
      if (!Array.isArray(deb.arc) || deb.arc.length < 2) continue
      const strokeColor = deb.kind === 'booster'
        ? 'rgba(255, 152, 56, 0.92)'
        : (deb.kind === 'fairing' ? 'rgba(255, 206, 84, 0.86)' : 'rgba(232, 82, 232, 0.90)')
      const ribColor = deb.kind === 'booster'
        ? 'rgba(255, 152, 56, 0.28)'
        : (deb.kind === 'fairing' ? 'rgba(255, 206, 84, 0.24)' : 'rgba(232, 82, 232, 0.24)')

      let prevX = 0, prevY = 0, hasPrev = false
      for (let i = 0; i < deb.arc.length; i++) {
        const pt = deb.arc[i]
        const lat = pt[1], lon = pt[2], altKm = pt[3]
        if (!isFrontHemisphere(lat, lon, altKm)) { hasPrev = false; continue }
        const spAir = this.project3dPoint(proj, lat, lon, effectiveAltMeters(altKm))
        const spGnd = this.project3dPoint(proj, lat, lon, 0)
        if (!spAir) { hasPrev = false; continue }
        const x = toVpX(spAir.positionX), y = toVpY(spAir.positionY)
        if (!inSafeCanvas(x, y, 80)) { hasPrev = false; continue }

        // Vertical drop-line connecting elevated debris arc straight down to its ground shadow
        if (spGnd && i % 4 === 0 && altKm > 2.0) {
          const gx = toVpX(spGnd.positionX), gy = toVpY(spGnd.positionY)
          if (inSafeCanvas(gx, gy, 80) && Math.hypot(x - gx, y - gy) < h * 0.45) {
            this.arcCtx.beginPath()
            this.arcCtx.moveTo(gx, gy)
            this.arcCtx.lineTo(x, y)
            this.arcCtx.strokeStyle = ribColor
            this.arcCtx.lineWidth = 1.0
            this.arcCtx.stroke()
          }
        }

        if (hasPrev && Math.hypot(x - prevX, y - prevY) < maxSegJump) {
          this.arcCtx.beginPath()
          this.arcCtx.moveTo(prevX, prevY)
          this.arcCtx.lineTo(x, y)
          this.arcCtx.strokeStyle = strokeColor
          this.arcCtx.lineWidth = 2.2
          this.arcCtx.stroke()
        }
        prevX = x; prevY = y; hasPrev = true
      }
    }

    // 3. Elevated 3D powered ascent arc + translucent vertical altitude curtain to ground track
    const track = sim.trajectory
    if (track.length >= 2 && camZoom < 8.0) {
      let prevX = 0, prevY = 0, prevGx = 0, prevGy = 0, hasPrev = false
      for (let i = 0; i < track.length; i++) {
        const s = track[i]
        if (!isFrontHemisphere(s.lat, s.lon, s.altKm)) { hasPrev = false; continue }
        const spAir = this.project3dPoint(proj, s.lat, s.lon, effectiveAltMeters(s.altKm))
        const spGnd = this.project3dPoint(proj, s.lat, s.lon, 0)
        if (!spAir || !spGnd) { hasPrev = false; continue }
        const x = toVpX(spAir.positionX), y = toVpY(spAir.positionY)
        const gx = toVpX(spGnd.positionX), gy = toVpY(spGnd.positionY)
        if (!inSafeCanvas(x, y, 80) || !inSafeCanvas(gx, gy, 80)) { hasPrev = false; continue }

        if (hasPrev && Math.hypot(x - prevX, y - prevY) < maxSegJump) {
          // Soft translucent altitude curtain fill between ground track and elevated 3D arc
          this.arcCtx.beginPath()
          this.arcCtx.moveTo(prevGx, prevGy)
          this.arcCtx.lineTo(gx, gy)
          this.arcCtx.lineTo(x, y)
          this.arcCtx.lineTo(prevX, prevY)
          this.arcCtx.closePath()
          this.arcCtx.fillStyle = s.pVis ? 'rgba(116, 232, 255, 0.20)' : 'rgba(76, 180, 255, 0.13)'
          this.arcCtx.fill()

          // Vertical rib every ~14 samples to anchor visual elevation above Earth surface
          if (i % 14 === 0 && s.altKm >= 12.0) {
            this.arcCtx.beginPath()
            this.arcCtx.moveTo(gx, gy)
            this.arcCtx.lineTo(x, y)
            this.arcCtx.strokeStyle = 'rgba(176, 234, 255, 0.48)'
            this.arcCtx.lineWidth = 1.1
            this.arcCtx.stroke()
          }

          // Luminous plume halo stroke
          if (s.pVis) {
            this.arcCtx.beginPath()
            this.arcCtx.moveTo(prevX, prevY)
            this.arcCtx.lineTo(x, y)
            this.arcCtx.strokeStyle = s.sun === 'red_twilight' ? 'rgba(255, 160, 86, 0.42)' : 'rgba(128, 240, 255, 0.42)'
            this.arcCtx.lineWidth = 7.5
            this.arcCtx.lineCap = 'round'
            this.arcCtx.stroke()
          }

          this.arcCtx.beginPath()
          this.arcCtx.moveTo(prevX, prevY)
          this.arcCtx.lineTo(x, y)
          this.arcCtx.strokeStyle = s.ph === 0 ? '#FF5E4D' : (s.ph === 1 ? '#FFD84A' : '#4CE8FF')
          this.arcCtx.lineWidth = 3.0
          this.arcCtx.lineCap = 'round'
          this.arcCtx.stroke()
        }
        prevX = x; prevY = y; prevGx = gx; prevGy = gy; hasPrev = true
      }
    }
  }

  private focusOverview(): void {
    const ctrl = this.controller
    if (!ctrl) return
    try {
      ctrl.animateCamera(map.newCameraPosition(this.computeOverviewCamera()), 550)
    } catch (_e) {}
  }

  private focusTopDownGlobe(): void {
    const ctrl = this.controller
    if (!ctrl) return
    try {
      ctrl.animateCamera(map.newCameraPosition(this.computeTopDownGlobeCamera()), 550)
    } catch (_e) {}
  }

  private focusNotamOrBooster(): void {
    const ctrl = this.controller
    const sim = this.simulation
    if (!ctrl || !sim) return
    let lat = sim.site.latDeg
    let lon = sim.site.lonDeg
    let zoom = 8.2
    if (sim.notam && sim.notam.valid) {
      lat = sim.notam.centerLatDeg
      lon = sim.notam.centerLonDeg
      zoom = 8.8
    } else if (sim.debris.length > 0) {
      lat = sim.debris[0].impactLatDeg
      lon = sim.debris[0].impactLonDeg
      zoom = 7.6
    }
    try {
      ctrl.animateCamera(map.newCameraPosition({
        target: { latitude: lat, longitude: lon },
        zoom: zoom,
        tilt: 18,
        bearing: 0
      }), 550)
    } catch (_e) {}
  }

  private toggleMapStyle(): void {
    this.isSatelliteType = !this.isSatelliteType
    const ctrl = this.controller
    if (!ctrl) return
    try {
      ctrl.setMapType(this.isSatelliteType ? mapCommon.MapType.SATELLITE : mapCommon.MapType.TERRAIN)
    } catch (_e) {}
  }

  private drawOfflineFallback(): void {
    const ctx = this.offlineCtx
    const w = ctx.width
    const h = ctx.height
    const sim = this.simulation
    if (w <= 10 || h <= 10 || !sim) return
    ctx.clearRect(0, 0, w, h)
    ctx.fillStyle = '#091120'
    ctx.fillRect(0, 0, w, h)

    // Compute tight regional bounding box around pad + trajectory + debris + observer
    let minLat = Math.min(sim.site.latDeg, sim.observer.latDeg)
    let maxLat = Math.max(sim.site.latDeg, sim.observer.latDeg)
    let minLon = Math.min(sim.site.lonDeg, sim.observer.lonDeg)
    let maxLon = Math.max(sim.site.lonDeg, sim.observer.lonDeg)
    for (let i = 0; i < sim.trajectory.length; i += 4) {
      minLat = Math.min(minLat, sim.trajectory[i].lat)
      maxLat = Math.max(maxLat, sim.trajectory[i].lat)
      minLon = Math.min(minLon, sim.trajectory[i].lon)
      maxLon = Math.max(maxLon, sim.trajectory[i].lon)
    }
    const padLat = Math.max(3, (maxLat - minLat) * 0.2)
    const padLon = Math.max(4, (maxLon - minLon) * 0.2)
    minLat -= padLat; maxLat += padLat; minLon -= padLon; maxLon += padLon

    const mx = (lon: number): number => 24 + ((lon - minLon) / Math.max(0.5, maxLon - minLon)) * (w - 48)
    const my = (lat: number): number => 24 + (1 - (lat - minLat) / Math.max(0.5, maxLat - minLat)) * (h - 48)

    // Lat/lon grid
    ctx.strokeStyle = 'rgba(130, 158, 200, 0.16)'
    ctx.lineWidth = 0.8
    for (let k = 0; k <= 4; k++) {
      const gx = 24 + (k / 4) * (w - 48)
      const gy = 24 + (k / 4) * (h - 48)
      ctx.beginPath(); ctx.moveTo(gx, 24); ctx.lineTo(gx, h - 24); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(24, gy); ctx.lineTo(w - 24, gy); ctx.stroke()
    }

    // NOTAM polygon
    if (sim.notam && sim.notam.valid && sim.notam.polygon.length >= 3) {
      ctx.beginPath()
      for (let i = 0; i < sim.notam.polygon.length; i++) {
        const x = mx(sim.notam.polygon[i][1]), y = my(sim.notam.polygon[i][0])
        if (i === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.closePath()
      ctx.fillStyle = 'rgba(232, 66, 66, 0.35)'
      ctx.fill()
      ctx.strokeStyle = '#FF5252'
      ctx.lineWidth = 2
      ctx.stroke()
    }

    // Trajectory ground track
    if (sim.trajectory.length >= 2) {
      ctx.beginPath()
      for (let i = 0; i < sim.trajectory.length; i++) {
        const x = mx(sim.trajectory[i].lon), y = my(sim.trajectory[i].lat)
        if (i === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.strokeStyle = '#4CE8FF'
      ctx.lineWidth = 2.6
      ctx.stroke()
    }

    // Dispersion scatter
    if (Array.isArray(sim.dispersion)) {
      for (let i = 0; i < sim.dispersion.length; i++) {
        const dp = sim.dispersion[i]
        ctx.beginPath()
        ctx.arc(mx(dp[1]), my(dp[0]), 2.6, 0, Math.PI * 2)
        ctx.fillStyle = dp[2] === 1 ? '#38E872' : '#FFB83A'
        ctx.fill()
      }
    }

    // Pad & debris points
    ctx.beginPath()
    ctx.arc(mx(sim.site.lonDeg), my(sim.site.latDeg), 5.5, 0, Math.PI * 2)
    ctx.fillStyle = '#FF644E'
    ctx.fill()
    for (let i = 0; i < sim.debris.length; i++) {
      const deb = sim.debris[i]
      ctx.beginPath()
      ctx.arc(mx(deb.impactLonDeg), my(deb.impactLatDeg), 4.5, 0, Math.PI * 2)
      ctx.fillStyle = '#FFE054'
      ctx.fill()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Base Map layer (Petal Maps 3D Satellite Globe or Offline vector fallback)
      if (this.usePetalMode && !this.petalFailed) {
        MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
          .width('100%')
          .height('100%')

        // Transparent non-blocking 3D airborne arc + dispersion Canvas
        Canvas(this.arcCtx)
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
          .onReady(() => {
            this.arcCanvasReady = true
            this.redraw3dArcOverlay()
          })
      } else {
        Canvas(this.offlineCtx)
          .width('100%')
          .height('100%')
          .onReady(() => {
            this.drawOfflineFallback()
          })
      }

      // Top floating bar
      Row({ space: 8 }) {
        Text(this.t('✕ 关闭', '✕ Close'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F6FF')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('rgba(11, 17, 30, 0.84)')
          .borderRadius(UI_RADIUS_PILL)
          .onClick(() => { this.onClose() })

        Text(this.simulation ? (this.isZh() ? this.simulation.titleZh : this.simulation.titleEn) : '')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F6F9FF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor('rgba(11, 17, 30, 0.78)')
          .borderRadius(UI_RADIUS_PILL)
      }
        .width('100%')
        .padding({ left: 16, right: 16, top: 44 })

      // Loading spinner while Petal Maps initializes
      if (this.usePetalMode && !this.petalReady && !this.petalFailed) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color('#64D8FF')
          Text(this.t('正在加载花瓣 3D 卫星地球…', 'Loading Petal 3D Satellite Globe…'))
            .fontSize(12)
            .fontColor('#EEF4FF')
        }
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .backgroundColor('rgba(11, 17, 30, 0.86)')
          .borderRadius(UI_RADIUS_PILL)
          .position({ x: 16, y: 94 })
      }

      // Bottom quick controls + selected debris detail popup (Reference Img 1/8)
      Column({ space: 10 }) {
        if (this.selectedDebris !== undefined) {
          Column({ space: 4 }) {
            Row() {
              Text(this.isZh() ? this.selectedDebris.labelZh : this.selectedDebris.labelEn)
                .fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').layoutWeight(1)
              Text('✕').fontSize(13).fontColor('#B8C6DF').padding(4).onClick(() => { this.selectedDebris = undefined })
            }.width('100%')
            Text(`${this.t('落点时刻', 'Impact')}: ${formatBeijingTimeFromIso(this.selectedDebris.impactTimeUtc)}`)
              .fontSize(11).fontColor('#D4E1F7')
            Text(`${this.t('落点坐标', 'Coords')}: ${this.selectedDebris.impactLonDeg.toFixed(4)}°E, ${this.selectedDebris.impactLatDeg.toFixed(4)}°N · ${this.t('射程', 'Range')} ${this.selectedDebris.downrangeKm.toFixed(1)} km`)
              .fontSize(11).fontColor('#D4E1F7')
            if (this.selectedDebris.distanceToNotamKm >= 0) {
              Text(`${this.t('NOTAM 落区判定', 'NOTAM Check')}: ${this.selectedDebris.insideNotam ? this.t('命中危险区内 ✓', 'Inside Danger Zone ✓') : this.t('区外落点', 'Outside Zone')} (${this.selectedDebris.distanceToNotamKm.toFixed(1)} km)`)
                .fontSize(11)
                .fontColor(this.selectedDebris.insideNotam ? '#46E27E' : '#FFBE55')
            }
          }
            .width('100%')
            .padding(12)
            .backgroundColor('rgba(12, 18, 32, 0.92)')
            .borderRadius(UI_RADIUS_CARD)
            .border({ width: 1, color: 'rgba(120, 175, 255, 0.35)' })
        }

        Scroll() {
          Row({ space: 8 }) {
            if (this.usePetalMode && !this.petalFailed) {
              Text(this.t('斜视3D轨道', 'Oblique 3D'))
                .fontSize(12).fontColor('#F2F6FF')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor('rgba(14, 22, 38, 0.88)')
                .borderRadius(UI_RADIUS_PILL)
                .onClick(() => { this.focusOverview() })

              Text(this.t('全球俯瞰', 'Globe Top'))
                .fontSize(12).fontColor('#F2F6FF')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor('rgba(14, 22, 38, 0.88)')
                .borderRadius(UI_RADIUS_PILL)
                .onClick(() => { this.focusTopDownGlobe() })

              Text(this.t('聚焦落区', 'Focus Drop Zone'))
                .fontSize(12).fontColor('#F2F6FF')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor('rgba(14, 22, 38, 0.88)')
                .borderRadius(UI_RADIUS_PILL)
                .onClick(() => { this.focusNotamOrBooster() })

              Text(this.isSatelliteType ? this.t('卫星底图', 'Satellite') : this.t('地形底图', 'Terrain'))
                .fontSize(12).fontColor('#9EEFFF')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor('rgba(14, 22, 38, 0.88)')
                .borderRadius(UI_RADIUS_PILL)
                .onClick(() => { this.toggleMapStyle() })

              Text(this.show3dArcs ? this.t('凌空3D弧 ✓', '3D Arcs ✓') : this.t('凌空3D弧', '3D Arcs'))
                .fontSize(12).fontColor(this.show3dArcs ? '#46E27E' : '#B7C5DE')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor('rgba(14, 22, 38, 0.88)')
                .borderRadius(UI_RADIUS_PILL)
                .onClick(() => {
                  this.show3dArcs = !this.show3dArcs
                  this.redraw3dArcOverlay()
                })

              if (this.simulation && Array.isArray(this.simulation.dispersion) && this.simulation.dispersion.length > 0) {
                Text(this.showDispersion ? this.t('散布云 ✓', 'Scatter ✓') : this.t('散布云', 'Scatter'))
                  .fontSize(12).fontColor(this.showDispersion ? '#46E27E' : '#B7C5DE')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor('rgba(14, 22, 38, 0.88)')
                  .borderRadius(UI_RADIUS_PILL)
                  .onClick(() => {
                    this.showDispersion = !this.showDispersion
                    this.redraw3dArcOverlay()
                  })
              }
            } else {
              Text(this.t('离线弹道模式（连接网络后自动启用花瓣 3D 卫星地球）', 'Offline Track Mode (Petal 3D Satellite Globe activates when online)'))
                .fontSize(11).fontColor('#CBD7EE')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor('rgba(14, 22, 38, 0.88)')
                .borderRadius(UI_RADIUS_CONTROL)
            }
          }
        }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
      }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 26 })
        .position({ x: 0, y: '100%' })
        .translate({ y: -150 })
    }
      .width('100%')
      .height('100%')
      .backgroundColor('#060B16')
  }
}
