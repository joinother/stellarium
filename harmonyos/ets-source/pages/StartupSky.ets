import { I18n } from './I18n'
import { StartupPoint, StartupStarAppearance, startupParticle, startupDepthPoint, startupReleasePoint, startupAppearance, startupSeed, startupEase } from './StartupStarGeometry'
import { STARTUP_GATHER_MS, STARTUP_REVEAL_MS, STARTUP_BG_NORMAL, STARTUP_BG_NIGHT, STARTUP_TITLE_COLORS_NORMAL, STARTUP_TITLE_COLORS_NIGHT } from './StartupStarGeometry'
import { FrameCallback } from '@kit.ArkUI'
import hilog from '@ohos.hilog'
import { notifyStartupCanvasReady } from '../common/PrivacyStartup'
import { AstroColors } from '../state/StellariumTheme'

class StartupFirstFrame extends FrameCallback {
  onIdle(_timeLeft: number): void { notifyStartupCanvasReady() }
}

@Component
export struct StartupSky {
  @Prop nightMode: boolean = false
  @Watch('refreshTitle') @StorageLink('i18nLang') private language: string = ''
  @Watch('updateMotion') @StorageLink('stellariumStartupForeground') private foreground: boolean = true
  @StorageLink('stellariumStartupSkyReady') private skyPrepared: boolean = false
  @StorageLink('stellariumPrivacyNativeStartupAllowed') private nativeStartupAllowed: boolean = false
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private targets: StartupPoint[] = []
  private backgroundAppearance: StartupStarAppearance[] = []
  private letterGroups: number[] = []
  private timer: number = -1
  private elapsed: number = 0
  private assemblyElapsed: number = 0
  private releaseElapsed: number = 0
  private releaseStarted: boolean = false
  private lastTick: number = 0
  private ready: boolean = false
  private coverReleased: boolean = false
  private artComplete: boolean = false
  private title: string = 'Stellarium'
  private fontSize: number = 44
  private canvasWidth: number = 0
  private canvasHeight: number = 0

  aboutToDisappear(): void {
    this.ready = false
    this.stopMotion()
  }

  private refreshTitle(): void {
    this.title = I18n.getLanguage() === 'zh_CN' ? '星象仪' :
      I18n.getLanguage() === 'zh_TW' || I18n.getLanguage() === 'zh_HK' ? '星象儀' : 'Stellarium'
    if (!I18n.getLanguage().startsWith('zh')) {
      try {
        this.title = this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.QAbility_label').id) || 'Stellarium'
      } catch (_error) {}
    }
    if (this.ready) this.prepareLetters()
  }

  private prepareLetters(): void {
    if (this.canvasWidth < 1 || this.canvasHeight < 1) return
    const maskWidth = 640
    const maskHeight = 120
    const mask = new OffscreenCanvas(maskWidth, maskHeight)
    const pen = mask.getContext('2d', new RenderingContextSettings(true))
    pen.font = '400 72px sans-serif'
    const measured = Math.max(1, pen.measureText(this.title).width)
    const maskFont = Math.min(72, 580 / measured * 72)
    pen.font = `400 ${maskFont}px sans-serif`
    pen.textAlign = 'center'
    pen.textBaseline = 'middle'
    pen.fillStyle = AstroColors.starPoint
    pen.fillText(this.title, maskWidth / 2, maskHeight / 2)
    const pixels = pen.getImageData(0, 0, maskWidth, maskHeight)
    const scale = Math.min((this.canvasWidth - 48) / maskWidth, 1.1)
    this.fontSize = maskFont * scale
    const candidates: StartupPoint[] = []
    let seed = 1779033703
    for (let sample = 1; sample <= 30000 && candidates.length < 900; sample++) {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0
      const horizontal = seed / 4294967296
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0
      const vertical = seed / 4294967296
      const column = Math.floor(horizontal * pixels.width)
      const row = Math.floor(vertical * pixels.height)
      if (pixels.data[(row * pixels.width + column) * 4 + 3] > 160) {
        candidates.push({ x: this.canvasWidth / 2 + (horizontal - 0.5) * maskWidth * scale,
          y: this.canvasHeight / 2 + (vertical - 0.5) * maskHeight * scale })
      }
    }
    const skip = Math.max(1, Math.ceil(candidates.length / 900))
    const sampled = candidates.filter((_point: StartupPoint, index: number): boolean => index % skip === 0)
    if (sampled.length > 0) {
      let minimumX = this.canvasWidth
      let maximumX = 0
      let minimumY = this.canvasHeight
      let maximumY = 0
      sampled.forEach((point: StartupPoint) => {
        minimumX = Math.min(minimumX, point.x)
        maximumX = Math.max(maximumX, point.x)
        minimumY = Math.min(minimumY, point.y)
        maximumY = Math.max(maximumY, point.y)
      })
      const fit = Math.min(Math.min(this.canvasWidth * 0.62, 500) / Math.max(1, maximumX - minimumX),
        Math.min(70, this.canvasHeight * 0.12) / Math.max(1, maximumY - minimumY))
      this.targets = sampled.map((point: StartupPoint): StartupPoint => ({
        x: this.canvasWidth / 2 + (point.x - (minimumX + maximumX) / 2) * fit,
        y: this.canvasHeight / 2 + (point.y - (minimumY + maximumY) / 2) * fit
      }))
    } else this.targets = []
    this.letterGroups = this.targets.map((_point: StartupPoint, index: number): number => {
      const weight = startupSeed(index, 10)
      return weight < 0.35 ? 0 : weight < 0.68 ? 1 : weight < 0.83 ? 2 :
        weight < 0.91 ? 3 : weight < 0.98 ? 4 : 5
    })
    this.draw()
  }

  private stopMotion(): void {
    if (this.timer >= 0) clearInterval(this.timer)
    this.timer = -1
  }

  private updateMotion(): void {
    this.stopMotion()
    if (!this.ready || !this.foreground) return
    this.lastTick = Date.now()
    this.timer = setInterval(() => {
      const now = Date.now()
      const step = Math.min(100, now - this.lastTick)
      this.elapsed += step
      if (!this.nativeStartupAllowed) {
        this.lastTick = now
        this.draw()
        return
      }
      if (!this.skyPrepared && this.assemblyElapsed < STARTUP_GATHER_MS) {
        this.assemblyElapsed += Math.min(step, 33)
        this.lastTick = now
        this.draw()
        return
      }
      this.assemblyElapsed += step
      // The scatter/reveal waits for the sky gate; it is the hand-off signal
      // ("resources ready, enter the main UI"), so it must not run on a timer
      // decoupled from actual readiness.
      if (this.skyPrepared && !this.releaseStarted && this.assemblyElapsed >= STARTUP_GATHER_MS) {
        this.releaseStarted = true
      }
      if (this.releaseStarted) this.releaseElapsed += step
      this.lastTick = now
      this.draw()
      if (!this.artComplete && this.releaseStarted) {
        this.artComplete = true
        hilog.info(0, 'StellariumStartup', '[startup] title-released activeMs=%{public}d', this.elapsed)
        AppStorage.setOrCreate('stellariumStartupArtComplete', true)
      }
    }, 33)
  }

  private drawPlanetariumDome(pen: CanvasRenderingContext2D, reveal: number): void {
    const w = this.canvasWidth
    const h = this.canvasHeight
    if (w < 40 || h < 40) return

    const domeEnter = startupEase((this.elapsed - 650) / 1400)
    if (domeEnter <= 0.002) return

    const unfold = startupEase((this.elapsed - 900) / 3400)
    const horizonEnter = startupEase((this.elapsed - 2400) / 1600)
    const sweepEnter = startupEase((this.elapsed - 3200) / 1400)
    const fadeOut = 1 - reveal * 0.65
    const breath = 0.86 + 0.14 * Math.sin(this.elapsed * 0.0018)
    // During the final crossfade into C++ Stage B, keep the dome light so UI-thread compositing stays 100% silky.
    const fullDetail = reveal < 0.25

    const lineRgb = this.nightMode ? '196, 56, 42' : '118, 166, 232'
    const glintRgb = this.nightMode ? '255, 110, 82' : '188, 222, 255'

    const cx = w * 0.5
    const apexY = -h * 0.16
    const maxRadius = Math.hypot(w * 0.62, h * 1.06)
    const horizonY = h * 0.81

    // 1. Subtle unlit planetarium dome ceiling ambient glow
    const vaultGrad = pen.createRadialGradient(cx, h * 0.12, 10, cx, h * 0.36, maxRadius * 0.78)
    vaultGrad.addColorStop(0, `rgba(${lineRgb}, ${(0.085 * domeEnter * breath * fadeOut).toFixed(4)})`)
    vaultGrad.addColorStop(0.55, `rgba(${lineRgb}, ${(0.025 * domeEnter * fadeOut).toFixed(4)})`)
    vaultGrad.addColorStop(1, `rgba(${lineRgb}, 0)`)
    pen.globalAlpha = 1
    pen.fillStyle = vaultGrad
    pen.fillRect(0, 0, w, h)

    // 2. Concentric altitude dome rings unfolding wave-by-wave from zenith
    const ringCount = 5
    for (let r = 0; r < ringCount; r++) {
      const ringFrac = (r + 1) / (ringCount + 0.35)
      const ringReveal = startupEase((unfold - ringFrac * 0.68) / 0.28)
      if (ringReveal <= 0.005) continue
      const lockGlint = Math.exp(-Math.pow((unfold - (ringFrac * 0.68 + 0.22)) / 0.09, 2))
      const radiusX = maxRadius * ringFrac * 1.06
      const radiusY = maxRadius * ringFrac * 0.78
      const baseAlpha = (0.065 + 0.03 * (1 - ringFrac)) * ringReveal * breath * fadeOut
      const glintAlpha = 0.15 * lockGlint * fadeOut

      pen.beginPath()
      pen.ellipse(cx, apexY, radiusX, radiusY, 0, 0.08 * Math.PI, 0.92 * Math.PI)
      pen.lineWidth = lockGlint > 0.2 ? 1.25 : 0.85
      pen.strokeStyle = `rgba(${lockGlint > 0.25 ? glintRgb : lineRgb}, ${(baseAlpha + glintAlpha).toFixed(4)})`
      pen.stroke()
    }

    // 3. Radial azimuth meridian ribs descending across the dome vault
    const meridianCount = 12
    const sweepPhase = ((this.elapsed - 3200) * 0.00085) % (Math.PI * 2)
    const sweepBeamAngle = Math.PI * 0.18 + (Math.sin(sweepPhase) * 0.5 + 0.5) * Math.PI * 0.64
    for (let m = 0; m < meridianCount; m++) {
      const frac = m / (meridianCount - 1)
      const angle = Math.PI * 0.12 + frac * Math.PI * 0.76
      const ribDelay = Math.abs(frac - 0.5) * 0.42
      const ribProgress = startupEase((unfold - ribDelay) / 0.52)
      if (ribProgress <= 0.005) continue

      const startR = maxRadius * 0.14
      const endR = maxRadius * (0.14 + 0.84 * ribProgress)
      const sx = cx + Math.cos(angle) * startR * 1.06
      const sy = apexY + Math.sin(angle) * startR * 0.78
      const ex = cx + Math.cos(angle) * endR * 1.06
      const ey = apexY + Math.sin(angle) * endR * 0.78

      const beamDist = Math.abs(angle - sweepBeamAngle)
      const beamBoost = sweepEnter * Math.exp(-beamDist * beamDist * 18) * 0.16
      const major = (m === 0 || m === 3 || m === 6 || m === 9 || m === 11)
      const alpha = ((major ? 0.105 : 0.062) * breath + beamBoost) * domeEnter * fadeOut

      pen.beginPath()
      pen.moveTo(sx, sy)
      pen.lineTo(ex, ey)
      pen.lineWidth = major || beamBoost > 0.05 ? 1.1 : 0.75
      pen.strokeStyle = `rgba(${beamBoost > 0.06 ? glintRgb : lineRgb}, ${alpha.toFixed(4)})`
      pen.stroke()

      // Subtle crosshair glint at dome intersections when the calibration sweep passes
      if (beamBoost > 0.03) {
        for (let r = 1; r <= 3; r++) {
          const rf = (r + 1) / (ringCount + 0.35)
          if (rf > ribProgress) continue
          const ix = cx + Math.cos(angle) * maxRadius * rf * 1.06
          const iy = apexY + Math.sin(angle) * maxRadius * rf * 0.78
          if (iy < 12 || iy > horizonY - 12) continue
          pen.strokeStyle = `rgba(${glintRgb}, ${(beamBoost * 1.45 * fadeOut).toFixed(4)})`
          pen.lineWidth = 1
          pen.beginPath()
          pen.moveTo(ix - 3.5, iy)
          pen.lineTo(ix + 3.5, iy)
          pen.moveTo(ix, iy - 3.5)
          pen.lineTo(ix, iy + 3.5)
          pen.stroke()
        }
      }
    }

    // 4. Curved horizon stage baseline with fine observatory azimuth ticks
    if (horizonEnter > 0.005) {
      const spanW = w * 0.88
      const leftX = cx - spanW * 0.5
      const rightX = cx + spanW * 0.5
      const sag = Math.min(28, h * 0.038)
      const hAlpha = 0.18 * horizonEnter * breath * fadeOut

      pen.beginPath()
      pen.moveTo(leftX, horizonY + sag)
      pen.quadraticCurveTo(cx, horizonY - sag * 0.5, rightX, horizonY + sag)
      pen.lineWidth = 1.15
      pen.strokeStyle = `rgba(${lineRgb}, ${hAlpha.toFixed(4)})`
      pen.stroke()

      // Subtle horizon stage glow hinting the landscape will rise from below
      const stageGlow = pen.createLinearGradient(0, horizonY - 26, 0, horizonY + 34)
      stageGlow.addColorStop(0, `rgba(${lineRgb}, 0)`)
      stageGlow.addColorStop(0.55, `rgba(${lineRgb}, ${(0.055 * horizonEnter * breath * fadeOut).toFixed(4)})`)
      stageGlow.addColorStop(1, `rgba(${lineRgb}, 0)`)
      pen.fillStyle = stageGlow
      pen.fillRect(0, horizonY - 26, w, 60)

      // Instrument azimuth degree ticks along the horizon arc
      const tickCount = 24
      for (let t = 0; t <= tickCount; t++) {
        const u = t / tickCount
        const tx = leftX + spanW * u
        const ty = (1 - u) * (1 - u) * (horizonY + sag) + 2 * (1 - u) * u * (horizonY - sag * 0.5) + u * u * (horizonY + sag)
        const major = t % 4 === 0
        const tickLen = major ? 7.5 : 3.5
        const sweepU = (sweepBeamAngle - Math.PI * 0.18) / (Math.PI * 0.64)
        const tickBoost = sweepEnter * Math.exp(-Math.pow((u - sweepU) / 0.10, 2)) * 0.24
        pen.beginPath()
        pen.moveTo(tx, ty)
        pen.lineTo(tx, ty + tickLen)
        pen.lineWidth = major ? 1.15 : 0.75
        pen.strokeStyle = `rgba(${tickBoost > 0.08 ? glintRgb : lineRgb}, ${((major ? 0.22 : 0.11) * horizonEnter * fadeOut + tickBoost * fadeOut).toFixed(4)})`
        pen.stroke()
      }
    }

    // 5. Subtle mechanical dome panel-ring cascade (Portal 2 unlit chamber feel, zero fake star constellations)
    if (fullDetail && sweepEnter > 0.02) {
      const panelWave = ((this.elapsed - 3200) * 0.00045) % 1.0
      for (let r = 0; r < ringCount; r++) {
        const ringFrac = (r + 1) / (ringCount + 0.35)
        const dist = Math.min(Math.abs(panelWave - ringFrac), 1.0 - Math.abs(panelWave - ringFrac))
        const pulse = Math.exp(-dist * dist * 55) * 0.13 * sweepEnter * fadeOut
        if (pulse <= 0.008) continue
        const radiusX = maxRadius * ringFrac * 1.06
        const radiusY = maxRadius * ringFrac * 0.78
        pen.beginPath()
        pen.ellipse(cx, apexY, radiusX, radiusY, 0, 0.12 * Math.PI, 0.88 * Math.PI)
        pen.lineWidth = 1.6
        pen.strokeStyle = `rgba(${glintRgb}, ${pulse.toFixed(4)})`
        pen.stroke()
      }
    }
    pen.globalAlpha = 1
  }

  private draw(): void {
    const pen = this.context
    const reveal = this.skyPrepared ? startupEase(this.releaseElapsed / STARTUP_REVEAL_MS) : 0
    pen.globalAlpha = 1
    pen.fillStyle = this.nightMode ? STARTUP_BG_NIGHT : STARTUP_BG_NORMAL
    pen.fillRect(0, 0, this.canvasWidth, this.canvasHeight)
    this.drawPlanetariumDome(pen, reveal)
    // Keep background dust motes whisper-faint so the loading dome reads as an unlit planetarium
    // chamber rather than a fake night sky that abruptly disappears before real stars ignite.
    const dustAtten = 0.13 * (1 - reveal)
    if (dustAtten > 0.003) {
      for (let index = 0; index < 900; index++) {
        const point = startupDepthPoint(index + 1800, this.canvasWidth, this.canvasHeight, this.elapsed, reveal)
        const appearance = this.backgroundAppearance[index]
        const brightness = appearance.brightness * (0.86 + Math.sin(this.elapsed / appearance.period + appearance.phase) * 0.14) * dustAtten
        pen.fillStyle = appearance.color
        if (appearance.radius > 1.35) {
          pen.globalAlpha = brightness * 0.07
          pen.beginPath()
          pen.arc(point.x, point.y, appearance.radius * 3, 0, Math.PI * 2)
          pen.fill()
        }
        pen.globalAlpha = brightness
        pen.beginPath()
        pen.arc(point.x, point.y, appearance.radius, 0, Math.PI * 2)
        pen.fill()
      }
    }
    const colors: string[] = this.nightMode ? STARTUP_TITLE_COLORS_NIGHT : STARTUP_TITLE_COLORS_NORMAL
    const radii: number[] = [0.32, 0.5, 0.8, 0.5, 0.65, 1.1]
    const brightness: number[] = [0.4, 0.65, 0.85, 0.6, 0.7, 0.95]
    const emphasis = startupEase(this.assemblyElapsed / STARTUP_GATHER_MS)
    const titleFade = Math.max(0, 1 - reveal * 1.45)
    for (let group = 0; group < 6; group++) {
      pen.fillStyle = colors[group]
      pen.globalAlpha = Math.min(1, brightness[group] + emphasis * 0.2) * titleFade
      pen.beginPath()
      const radius = radii[group] * (1 + emphasis * 0.5)
      for (let index = 0; index < this.targets.length; index++) {
        if (this.letterGroups[index] !== group) continue
        const assembled = startupParticle(index, this.targets[index], this.canvasWidth, this.canvasHeight,
          this.elapsed, this.assemblyElapsed)
        const point = startupReleasePoint(index, assembled, this.canvasWidth, this.canvasHeight, reveal)
        pen.moveTo(point.x + radius, point.y)
        pen.arc(point.x, point.y, radius, 0, Math.PI * 2)
      }
      pen.fill()
    }
    if (this.targets.length === 0) {
      pen.globalAlpha = 0.7
      pen.font = `300 ${this.fontSize}px sans-serif`
      pen.textAlign = 'center'
      pen.textBaseline = 'middle'
      pen.fillText(this.title, this.canvasWidth / 2, this.canvasHeight / 2)
    }
    pen.globalAlpha = 1
  }

  build() {
    Canvas(this.context)
      .width('100%').height('100%').backgroundColor(this.nightMode ? STARTUP_BG_NIGHT : STARTUP_BG_NORMAL)
      .accessibilityText(this.title)
      .onReady(() => {
        this.backgroundAppearance = []
        for (let index = 0; index < 900; index++) this.backgroundAppearance.push(startupAppearance(index, this.nightMode))
        this.ready = true
        this.canvasWidth = this.context.width
        this.canvasHeight = this.context.height
        this.refreshTitle()
        this.updateMotion()
        if (!this.coverReleased) {
          this.coverReleased = true
          this.getUIContext().postFrameCallback(new StartupFirstFrame())
        }
      })
      .onAreaChange((_old: Area, area: Area) => {
        this.canvasWidth = Number(area.width)
        this.canvasHeight = Number(area.height)
        if (this.ready) this.prepareLetters()
      })
  }
}
