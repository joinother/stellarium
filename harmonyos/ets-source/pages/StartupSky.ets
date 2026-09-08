import { I18n } from './I18n'
import { StartupPoint, StartupStarAppearance, startupParticle, startupDepthPoint, startupReleasePoint, startupReveal, startupAppearance, startupSeed, startupEase } from './StartupStarGeometry'
import { STARTUP_GATHER_MS, STARTUP_REVEAL_AT_MS } from './StartupStarGeometry'
import { FrameCallback } from '@kit.ArkUI'
import hilog from '@ohos.hilog'
import { notifyStartupCanvasReady } from '../common/PrivacyStartup'

class StartupFirstFrame extends FrameCallback {
  onIdle(_timeLeft: number): void { notifyStartupCanvasReady() }
}

@Component
export struct StartupSky {
  @Watch('refreshTitle') @StorageLink('i18nLang') private language: string = ''
  @Watch('updateMotion') @StorageLink('stellariumStartupForeground') private foreground: boolean = true
  @StorageLink('stellariumStartupSkyReady') private skyPrepared: boolean = false
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private targets: StartupPoint[] = []
  private backgroundAppearance: StartupStarAppearance[] = []
  private letterGroups: number[] = []
  private timer: number = -1
  private elapsed: number = 0
  private assemblyElapsed: number = 0
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
    pen.fillStyle = '#FFFFFF'
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
      if (this.skyPrepared) this.assemblyElapsed += step
      this.lastTick = now
      this.draw()
      if (!this.artComplete && this.skyPrepared && this.assemblyElapsed >= STARTUP_REVEAL_AT_MS) {
        this.artComplete = true
        hilog.info(0, 'StellariumStartup', '[startup] title-assembled activeMs=%{public}d', this.elapsed)
        AppStorage.setOrCreate('stellariumStartupArtComplete', true)
      }
    }, 33)
  }

  private draw(): void {
    const pen = this.context
    const reveal = startupReveal(this.assemblyElapsed)
    pen.globalAlpha = 1
    pen.fillStyle = '#05070F'
    pen.fillRect(0, 0, this.canvasWidth, this.canvasHeight)
    for (let index = 0; index < 900; index++) {
      const point = startupDepthPoint(index + 1800, this.canvasWidth, this.canvasHeight, this.elapsed, reveal)
      const appearance = this.backgroundAppearance[index]
      const brightness = appearance.brightness * (0.86 + Math.sin(this.elapsed / appearance.period + appearance.phase) * 0.14)
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
    const colors: string[] = ['#CED9EA', '#E9EEFA', '#F4F6FF', '#A5CDF4', '#F4D6AF', '#FFFFFF']
    const radii: number[] = [0.32, 0.5, 0.8, 0.5, 0.65, 1.1]
    const brightness: number[] = [0.4, 0.65, 0.85, 0.6, 0.7, 0.95]
    const emphasis = startupEase(this.assemblyElapsed / STARTUP_GATHER_MS)
    for (let group = 0; group < 6; group++) {
      pen.fillStyle = colors[group]
      pen.globalAlpha = Math.min(1, brightness[group] + emphasis * 0.2) * (1 - reveal * 0.25)
      pen.beginPath()
      const radius = radii[group] * (1 + emphasis * 0.5)
      for (let index = 0; index < this.targets.length; index++) {
        if (this.letterGroups[index] !== group) continue
        const assembled = startupParticle(index, this.targets[index], this.canvasWidth, this.canvasHeight,
          this.elapsed, this.skyPrepared ? this.assemblyElapsed : -1)
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
      .width('100%').height('100%').backgroundColor('#05070F')
      .accessibilityText(this.title)
      .onReady(() => {
        this.backgroundAppearance = []
        for (let index = 0; index < 900; index++) this.backgroundAppearance.push(startupAppearance(index))
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
