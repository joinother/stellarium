import { Theme } from '@kit.ArkUI'
import { vibrator } from '@kit.SensorServiceKit'
import { BridgeClient } from '../../bridge/BridgeClient'
import { AudioEngine } from '../../capability/AudioEngine'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'

interface LensBandSpec {
  id: string
  shortName: string
  color: string
  nightColor: string
  angleDeg: number
}

// 9 波段均匀排布在圆镜外圈（步进 40°，起始 45° 右下方顺手握持位），与 C++ HipsMgr GPU 着色器严格一致。
const LENS_BANDS: Array<LensBandSpec> = [
  { id: 'finkbeiner-ha', shortName: 'Hα 发射线', color: '#F26B6B', nightColor: '#C44536', angleDeg: 45 },
  { id: 'allwise-color', shortName: '中红外', color: '#FF964F', nightColor: '#C44536', angleDeg: 85 },
  { id: '2mass-color', shortName: '近红外', color: '#F5B95B', nightColor: '#C44536', angleDeg: 125 },
  { id: 'planck-lfi', shortName: '微波', color: '#4CC3D9', nightColor: '#C44536', angleDeg: 165 },
  { id: 'haslam-radio', shortName: '射电', color: '#7E9CE6', nightColor: '#C44536', angleDeg: 205 },
  { id: 'dss2-color', shortName: '可见光', color: '#9AC2FF', nightColor: '#C44536', angleDeg: 245 },
  { id: 'galex-nuv', shortName: '紫外', color: '#A88BFF', nightColor: '#C44536', angleDeg: 285 },
  { id: 'rass-xray', shortName: 'X 射线', color: '#4FD1C5', nightColor: '#C44536', angleDeg: 325 },
  { id: 'fermi-gamma', shortName: '伽马射线', color: '#F2C94C', nightColor: '#C44536', angleDeg: 5 },
]

const DEFAULT_LENS_RADIUS_NORM: number = 0.215
const MIN_LENS_RADIUS_NORM: number = 0.095
const CLOSE_SHRINK_THRESHOLD: number = 0.118
const FULLSCREEN_EXPAND_THRESHOLD: number = 0.44
const FULLSCREEN_TARGET_RADIUS: number = 1.42
const RIM_OUTER_HIT_SLOP_VP: number = 16
const RIM_INNER_GRAB_BAND_VP: number = 30

// Flags bitmask matching HipsMgr.cpp s_atomicLensFlags
const FLAG_DRAGGING: number = 1
const FLAG_RESIZING: number = 2
const FLAG_ROTATING: number = 4
const FLAG_BLOOMING: number = 8
const FLAG_EXPANDING: number = 16

function bandIndexById(id: string): number {
  for (let i = 0; i < LENS_BANDS.length; i += 1) {
    if (LENS_BANDS[i].id === id) return i
  }
  return 0
}

function normalizeAngleDeg(deg: number): number {
  let a = deg % 360
  if (a < 0) a += 360
  return a
}

function bandIndexFromAngle(angleDeg: number): number {
  const shifted = normalizeAngleDeg(angleDeg - 45)
  return Math.round(shifted / 40) % LENS_BANDS.length
}

// Sky Guide 风格多光谱透视放大镜交互层：
//   - 圆镜主体（4K 光谱玻璃 + 金属发光镜圈 + 9 波段刻度点 + 可旋转防滑金属转柄）全部由 C++ HipsMgr
//     在单次 OpenGL 着色器内原子绘制，彻底消除 ArkUI 与 OpenGL 跨层错位与跟手延迟；
//   - 拖动/拉大/旋柄过程中本组件零 @State 重排，仅通过微秒级无锁快通道推送坐标与转角；
//   - 极简无胶囊设计：镜内拖动平移、旋转转柄或点镜圈色点切波段、拉大边缘扩散全屏、缩拢边缘关闭。
@Component
export struct SpectralLensOverlay {
  @StorageLink('stellariumSpectralLensActive') @Watch('onActiveChanged') active: boolean = false
  @StorageLink('stellariumSpectralLensBand') @Watch('onExternalBandChanged') storedBandId: string = 'finkbeiner-ha'
  @StorageLink('stellariumSpectralLensBloomToken') @Watch('onBloomTriggered') bloomToken: number = 0
  @StorageLink('stellariumSpectralLensLivePos') @Watch('onExternalLivePos') externalLivePos: string = ''
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private screenW: number = 960
  @State private screenH: number = 600
  // 静止态锚点（仅在手势抬起 / 动画结束时提交一次，拖动过程零重排）
  @State private normX: number = 0.50
  @State private normY: number = 0.44
  @State private radiusNorm: number = DEFAULT_LENS_RADIUS_NORM
  @State private zoomFactor: number = 1.0
  @State private bandIndex: number = 0
  @State private handleAngleDeg: number = 45
  @State private chromeHidden: boolean = false
  @State private expandPromptVisible: boolean = false
  @State private shrinkClosePromptVisible: boolean = false
  @State private rotatePromptVisible: boolean = false
  @State private showInitialTip: boolean = true

  // 高频手势实时值（非 @State，拖动/缩放/旋柄期间零 ArkUI 布局开销）
  private liveNormX: number = 0.50
  private liveNormY: number = 0.44
  private liveRadiusNorm: number = DEFAULT_LENS_RADIUS_NORM
  private liveHandleAngleDeg: number = 45
  private liveFlags: number = 0

  private dragStartWinX: number = 0
  private dragStartWinY: number = 0
  private dragStartNormX: number = 0.50
  private dragStartNormY: number = 0.44
  private isDraggingLens: boolean = false
  private isResizingLens: boolean = false
  private isRotatingHandle: boolean = false
  private isExpandingFullScreen: boolean = false
  private resizeStartDist: number = 100
  private resizeStartRadiusNorm: number = DEFAULT_LENS_RADIUS_NORM
  private passedFullScreenThreshold: boolean = false
  private passedCloseShrinkThreshold: boolean = false
  private tipTimerId: number = -1
  private bandToastTimerId: number = -1
  private animTimerId: number = -1
  private lastBloomTokenHandled: number = 0

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToAppear(): void {
    const idx = bandIndexById(this.storedBandId)
    this.bandIndex = idx
    this.handleAngleDeg = LENS_BANDS[idx].angleDeg
    this.liveHandleAngleDeg = this.handleAngleDeg
    if (this.active) {
      this.syncFullNativeLens()
      this.scheduleTipFade()
    }
  }

  aboutToDisappear(): void {
    this.clearTimers()
  }

  private clearTimers(): void {
    if (this.tipTimerId >= 0) {
      clearTimeout(this.tipTimerId)
      this.tipTimerId = -1
    }
    if (this.bandToastTimerId >= 0) {
      clearTimeout(this.bandToastTimerId)
      this.bandToastTimerId = -1
    }
    if (this.animTimerId >= 0) {
      clearInterval(this.animTimerId)
      this.animTimerId = -1
    }
  }

  private clearAnimTimer(): void {
    if (this.animTimerId >= 0) {
      clearInterval(this.animTimerId)
      this.animTimerId = -1
    }
  }

  private flashBandToast(): void {
    this.rotatePromptVisible = true
    if (this.bandToastTimerId >= 0) clearTimeout(this.bandToastTimerId)
    this.bandToastTimerId = setTimeout(() => {
      if (!this.isRotatingHandle) this.rotatePromptVisible = false
      this.bandToastTimerId = -1
    }, 1300)
  }

  private scheduleTipFade(): void {
    this.showInitialTip = true
    if (this.tipTimerId >= 0) clearTimeout(this.tipTimerId)
    this.tipTimerId = setTimeout(() => {
      this.showInitialTip = false
      this.tipTimerId = -1
    }, 3400)
  }

  private commitLiveToState(): void {
    this.normX = this.liveNormX
    this.normY = this.liveNormY
    this.radiusNorm = this.liveRadiusNorm
    this.handleAngleDeg = this.liveHandleAngleDeg
  }

  private onActiveChanged(): void {
    if (this.active) {
      AudioEngine.getInstance().playUiCue('loupe_open')
      const idx = bandIndexById(this.storedBandId)
      this.bandIndex = idx
      this.handleAngleDeg = LENS_BANDS[idx].angleDeg
      this.liveHandleAngleDeg = this.handleAngleDeg
      this.isExpandingFullScreen = false
      this.expandPromptVisible = false
      this.shrinkClosePromptVisible = false
      this.rotatePromptVisible = false
      if (this.bloomToken > 0 && this.bloomToken !== this.lastBloomTokenHandled) {
        this.startBloomFromBlueCircle()
      } else {
        this.liveRadiusNorm = DEFAULT_LENS_RADIUS_NORM
        this.radiusNorm = DEFAULT_LENS_RADIUS_NORM
        this.liveFlags = 0
        this.chromeHidden = false
        this.syncFullNativeLens()
        this.scheduleTipFade()
      }
    } else {
      AudioEngine.getInstance().playUiCue('loupe_close')
      this.clearAnimTimer()
      this.isExpandingFullScreen = false
      this.isResizingLens = false
      this.isDraggingLens = false
      this.isRotatingHandle = false
      this.liveFlags = 0
      this.chromeHidden = false
      this.expandPromptVisible = false
      this.shrinkClosePromptVisible = false
      this.rotatePromptVisible = false
      BridgeClient.send('setSpectralLens', '0')
    }
  }

  private onBloomTriggered(): void {
    if (this.bloomToken > 0 && this.bloomToken !== this.lastBloomTokenHandled && this.active) {
      this.startBloomFromBlueCircle()
    }
  }

  // 长按星空蓝色小圈 → 平滑膨胀为完整多光谱透视放大镜（零 ArkUI 重排，纯 GPU 膨胀）
  private startBloomFromBlueCircle(): void {
    this.lastBloomTokenHandled = this.bloomToken
    this.clearAnimTimer()
    const lx = AppStorage.get<number>('stellariumSpectralLensLaunchX')
    const ly = AppStorage.get<number>('stellariumSpectralLensLaunchY')
    if (lx !== undefined && lx >= 0.08 && lx <= 0.92) this.liveNormX = lx
    if (ly !== undefined && ly >= 0.08 && ly <= 0.88) this.liveNormY = ly

    const minSide = Math.max(240, Math.min(this.screenW, this.screenH))
    const startR = Math.max(0.055, Math.min(0.11, 60 / minSide))
    const targetR = DEFAULT_LENS_RADIUS_NORM
    this.liveRadiusNorm = startR
    this.liveFlags = FLAG_BLOOMING
    this.chromeHidden = true
    this.isExpandingFullScreen = false
    this.triggerDetentHaptic()
    this.syncFullNativeLens()

    const startedAt = Date.now()
    const durationMs = 260
    this.animTimerId = setInterval(() => {
      if (!this.active) {
        this.clearAnimTimer()
        return
      }
      const t = Math.min(1, (Date.now() - startedAt) / durationMs)
      const easeOut = 1 - Math.pow(1 - t, 3)
      this.liveRadiusNorm = startR + (targetR - startR) * easeOut
      this.syncFastGeometry()
      if (t >= 1) {
        this.clearAnimTimer()
        this.liveRadiusNorm = targetR
        this.liveFlags = 0
        this.syncFastGeometry()
        this.commitLiveToState()
        this.chromeHidden = false
        this.scheduleTipFade()
      }
    }, 12)
  }

  // 长按呼出后手指不抬起直接滑动：零重排实时拖扫，抬手一次性提交锚点
  private onExternalLivePos(): void {
    if (!this.active || this.isExpandingFullScreen || this.externalLivePos.length === 0) return
    if (this.externalLivePos.startsWith('END|')) {
      this.liveFlags = 0
      this.syncFastGeometry()
      this.commitLiveToState()
      this.chromeHidden = false
      return
    }
    const parts = this.externalLivePos.split('|')
    if (parts.length < 2) return
    const nx = Number(parts[0])
    const ny = Number(parts[1])
    if (Number.isFinite(nx) && Number.isFinite(ny)) {
      this.liveNormX = Math.max(0.10, Math.min(0.90, nx))
      this.liveNormY = Math.max(0.12, Math.min(0.84, ny))
      this.liveFlags = FLAG_DRAGGING
      if (!this.chromeHidden) this.chromeHidden = true
      this.syncFastGeometry()
    }
  }

  private onExternalBandChanged(): void {
    const idx = bandIndexById(this.storedBandId)
    if (idx !== this.bandIndex) {
      this.bandIndex = idx
      this.handleAngleDeg = LENS_BANDS[idx].angleDeg
      this.liveHandleAngleDeg = this.handleAngleDeg
      if (this.active) this.syncFullNativeLens()
    }
  }

  private currentBand(): LensBandSpec {
    return LENS_BANDS[this.bandIndex] ?? LENS_BANDS[0]
  }

  private bandAccent(spec: LensBandSpec): string {
    return this.c.isNight ? spec.nightColor : spec.color
  }

  private radiusVp(): number {
    const minSide = Math.max(240, Math.min(this.screenW, this.screenH))
    return this.radiusNorm * minSide
  }

  private centerX(): number {
    return this.normX * this.screenW
  }

  private centerY(): number {
    return this.normY * this.screenH
  }

  // 完整同步（开关/切波段/切倍率时调用）
  private syncFullNativeLens(): void {
    if (!this.active) return
    const payload = '1|' + this.currentBand().id + '|' +
      this.liveNormX.toFixed(4) + '|' +
      this.liveNormY.toFixed(4) + '|' +
      this.liveRadiusNorm.toFixed(4) + '|' +
      this.zoomFactor.toFixed(2) + '|' +
      this.liveHandleAngleDeg.toFixed(2) + '|' +
      this.liveFlags.toString()
    BridgeClient.send('setSpectralLens', payload)
  }

  // 2 微秒纯几何快通道（拖动/拉大/旋柄高频 Move 专用，零 JSON、零日志、零重排）
  private syncFastGeometry(): void {
    if (!this.active) return
    const payload = '2|' +
      this.liveNormX.toFixed(4) + '|' +
      this.liveNormY.toFixed(4) + '|' +
      this.liveRadiusNorm.toFixed(4) + '|' +
      this.liveHandleAngleDeg.toFixed(2) + '|' +
      this.liveFlags.toString()
    BridgeClient.send('setSpectralLens', payload)
  }

  private triggerDetentHaptic(): void {
    try {
      vibrator.startVibration(
        { type: 'time', duration: 10 },
        { id: 0, usage: 'touch' }
      ).catch(() => {})
    } catch (_) {
      // Ignore if device or sandbox does not expose vibrator
    }
  }

  private selectBandIndex(idx: number, snapAngle: boolean): void {
    const clamped = ((idx % LENS_BANDS.length) + LENS_BANDS.length) % LENS_BANDS.length
    const changed = clamped !== this.bandIndex
    this.bandIndex = clamped
    this.storedBandId = LENS_BANDS[clamped].id
    if (snapAngle) {
      this.liveHandleAngleDeg = LENS_BANDS[clamped].angleDeg
      this.handleAngleDeg = this.liveHandleAngleDeg
    }
    if (changed) {
      this.triggerDetentHaptic()
      AudioEngine.getInstance().playUiCue('loupe_blip')
      AudioEngine.getInstance().playBandCue(LENS_BANDS[clamped].id)
      this.syncFullNativeLens()
      if (snapAngle) this.flashBandToast()
    }
  }

  // 拉大圆镜至阈值：纯 GPU 水波扩散铺满整屏后零闪烁无缝移交全屏 4K 多光谱
  private expandToFullScreenAnimated(): void {
    if (this.isExpandingFullScreen) return
    AudioEngine.getInstance().playUiCue('loupe_fullscreen')
    this.clearAnimTimer()
    this.isExpandingFullScreen = true
    this.isResizingLens = false
    this.isDraggingLens = false
    this.isRotatingHandle = false
    this.chromeHidden = true
    this.expandPromptVisible = false
    this.showInitialTip = false
    this.liveFlags = FLAG_EXPANDING

    const startR = this.liveRadiusNorm
    const targetBandId = this.currentBand().id
    const startedAt = Date.now()
    const durationMs = 230
    this.animTimerId = setInterval(() => {
      if (!this.active) {
        this.clearAnimTimer()
        this.isExpandingFullScreen = false
        return
      }
      const t = Math.min(1, (Date.now() - startedAt) / durationMs)
      const ease = 1 - Math.pow(1 - t, 2.4)
      this.liveRadiusNorm = startR + (FULLSCREEN_TARGET_RADIUS - startR) * ease
      this.syncFastGeometry()
      if (t >= 1) {
        this.clearAnimTimer()
        this.isExpandingFullScreen = false
        this.liveFlags = 0
        this.liveRadiusNorm = DEFAULT_LENS_RADIUS_NORM
        this.radiusNorm = DEFAULT_LENS_RADIUS_NORM
        BridgeClient.send('setSpectralView', JSON.stringify({ id: targetBandId, enabled: true }))
        this.active = false
      }
    }, 12)
  }

  private closeLens(): void {
    this.clearAnimTimer()
    this.isExpandingFullScreen = false
    this.liveFlags = 0
    this.liveRadiusNorm = DEFAULT_LENS_RADIUS_NORM
    this.radiusNorm = DEFAULT_LENS_RADIUS_NORM
    this.active = false
    BridgeClient.send('setSpectralLens', '0')
  }

  // 镜内单指平移 + 镜圈边缘拉大缩放：Move 全程零 @State 刷新，100% GPU 原生跟手！
  private handleLensTouch(event: TouchEvent): void {
    event.stopPropagation()
    if (this.isExpandingFullScreen || !event.touches || event.touches.length === 0) return
    const t = event.touches[0]
    const cx = this.liveNormX * this.screenW
    const cy = this.liveNormY * this.screenH
    const minSide = Math.max(240, Math.min(this.screenW, this.screenH))
    if (event.type === TouchType.Down) {
      this.clearAnimTimer()
      this.showInitialTip = false
      const dist = Math.hypot(t.windowX - cx, t.windowY - cy)
      const rVp = this.liveRadiusNorm * minSide
      if (dist >= Math.max(36, rVp - RIM_INNER_GRAB_BAND_VP)) {
        this.isResizingLens = true
        this.isDraggingLens = false
        this.resizeStartDist = Math.max(12, dist)
        this.resizeStartRadiusNorm = this.liveRadiusNorm
        this.passedFullScreenThreshold = this.liveRadiusNorm >= FULLSCREEN_EXPAND_THRESHOLD
        this.passedCloseShrinkThreshold = this.liveRadiusNorm <= CLOSE_SHRINK_THRESHOLD
        this.liveFlags = FLAG_RESIZING
        this.chromeHidden = true
        this.expandPromptVisible = this.passedFullScreenThreshold
        this.shrinkClosePromptVisible = this.passedCloseShrinkThreshold
      } else {
        this.isDraggingLens = true
        this.isResizingLens = false
        this.dragStartWinX = t.windowX
        this.dragStartWinY = t.windowY
        this.dragStartNormX = this.liveNormX
        this.dragStartNormY = this.liveNormY
        this.liveFlags = FLAG_DRAGGING
        this.chromeHidden = true
      }
      this.syncFastGeometry()
    } else if (event.type === TouchType.Move) {
      if (this.isResizingLens) {
        const curDist = Math.hypot(t.windowX - cx, t.windowY - cy)
        const deltaNorm = (curDist - this.resizeStartDist) / minSide
        const nextR = Math.max(MIN_LENS_RADIUS_NORM, Math.min(1.25, this.resizeStartRadiusNorm + deltaNorm))
        this.liveRadiusNorm = nextR
        if (nextR >= FULLSCREEN_EXPAND_THRESHOLD && !this.passedFullScreenThreshold) {
          this.passedFullScreenThreshold = true
          this.expandPromptVisible = true
          this.triggerDetentHaptic()
        } else if (nextR < FULLSCREEN_EXPAND_THRESHOLD && this.passedFullScreenThreshold) {
          this.passedFullScreenThreshold = false
          this.expandPromptVisible = false
        }
        if (nextR <= CLOSE_SHRINK_THRESHOLD && !this.passedCloseShrinkThreshold) {
          this.passedCloseShrinkThreshold = true
          this.shrinkClosePromptVisible = true
          this.triggerDetentHaptic()
        } else if (nextR > CLOSE_SHRINK_THRESHOLD && this.passedCloseShrinkThreshold) {
          this.passedCloseShrinkThreshold = false
          this.shrinkClosePromptVisible = false
        }
        this.syncFastGeometry()
      } else if (this.isDraggingLens) {
        const dx = t.windowX - this.dragStartWinX
        const dy = t.windowY - this.dragStartWinY
        this.liveNormX = Math.max(0.10, Math.min(0.90, this.dragStartNormX + dx / Math.max(1, this.screenW)))
        this.liveNormY = Math.max(0.12, Math.min(0.84, this.dragStartNormY + dy / Math.max(1, this.screenH)))
        this.syncFastGeometry()
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      const wasResizing = this.isResizingLens
      this.isResizingLens = false
      this.isDraggingLens = false
      this.expandPromptVisible = false
      this.shrinkClosePromptVisible = false
      if (wasResizing && this.liveRadiusNorm >= FULLSCREEN_EXPAND_THRESHOLD) {
        this.expandToFullScreenAnimated()
        return
      }
      if (wasResizing && this.liveRadiusNorm <= CLOSE_SHRINK_THRESHOLD) {
        this.closeLens()
        return
      }
      this.liveFlags = 0
      this.syncFastGeometry()
      this.commitLiveToState()
      this.chromeHidden = false
    }
  }

  // 旋转转柄：Move 全程零 @State 重排，仅在棘轮跨档切波段时更新标签与震动反馈
  private handleRotateTouch(event: TouchEvent): void {
    event.stopPropagation()
    if (this.isExpandingFullScreen || !event.touches || event.touches.length === 0) return
    const t = event.touches[0]
    if (event.type === TouchType.Down) {
      this.isRotatingHandle = true
      this.showInitialTip = false
      this.rotatePromptVisible = true
      this.liveFlags = FLAG_ROTATING
      this.syncFastGeometry()
    } else if (event.type === TouchType.Move && this.isRotatingHandle) {
      const dx = t.windowX - (this.liveNormX * this.screenW)
      const dy = t.windowY - (this.liveNormY * this.screenH)
      if (dx * dx + dy * dy > 16) {
        const angleDeg = normalizeAngleDeg(Math.atan2(dy, dx) * 180 / Math.PI)
        this.liveHandleAngleDeg = angleDeg
        const nextIdx = bandIndexFromAngle(angleDeg)
        if (nextIdx !== this.bandIndex) {
          this.selectBandIndex(nextIdx, false)
        } else {
          this.syncFastGeometry()
        }
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isRotatingHandle = false
      this.rotatePromptVisible = false
      this.liveFlags = 0
      this.liveHandleAngleDeg = LENS_BANDS[this.bandIndex].angleDeg
      this.syncFastGeometry()
      this.commitLiveToState()
    }
  }

  private handleCenterOffset(distFromCenter: number): number[] {
    const rad = this.handleAngleDeg * Math.PI / 180
    return [this.centerX() + Math.cos(rad) * distFromCenter, this.centerY() + Math.sin(rad) * distFromCenter]
  }

  build() {
    Stack() {
      if (this.active) {
        // 1. 透明圆镜触控热区（全部视觉由 C++ GPU 单着色器原子绘制，零错位零延迟）
        Stack()
          .id('spectral-lens-ring')
          .width((this.radiusVp() + RIM_OUTER_HIT_SLOP_VP) * 2)
          .height((this.radiusVp() + RIM_OUTER_HIT_SLOP_VP) * 2)
          .borderRadius(this.radiusVp() + RIM_OUTER_HIT_SLOP_VP)
          .backgroundColor(Color.Transparent)
          .position({
            x: this.centerX() - (this.radiusVp() + RIM_OUTER_HIT_SLOP_VP),
            y: this.centerY() - (this.radiusVp() + RIM_OUTER_HIT_SLOP_VP)
          })
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => { this.handleLensTouch(event) })

        // 2. 镜圈 9 个波段刻度透明点击热区（静止态生效）
        if (!this.chromeHidden) {
          ForEach(LENS_BANDS, (spec: LensBandSpec, idx: number) => {
            Stack()
              .width(24)
              .height(24)
              .backgroundColor(Color.Transparent)
              .position({
                x: this.centerX() + Math.cos(spec.angleDeg * Math.PI / 180) * (this.radiusVp() + 1) - 12,
                y: this.centerY() + Math.sin(spec.angleDeg * Math.PI / 180) * (this.radiusVp() + 1) - 12
              })
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => { this.selectBandIndex(idx, true) })
          }, (spec: LensBandSpec) => spec.id)

          // 3. 透明转柄触控热区（视觉由 GPU 与镜圈同帧绘制）
          Stack()
            .id('spectral-lens-handle')
            .width(100)
            .height(56)
            .backgroundColor(Color.Transparent)
            .position({
              x: this.handleCenterOffset(this.radiusVp() + 42)[0] - 50,
              y: this.handleCenterOffset(this.radiusVp() + 42)[1] - 28
            })
            .rotate({ angle: this.handleAngleDeg })
            .hitTestBehavior(HitTestMode.Block)
            .onTouch((event: TouchEvent) => { this.handleRotateTouch(event) })

          if (this.showInitialTip) {
            Text('转动转柄切波段 · 拉大进全屏 · 缩拢关闭')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(this.c.isNight ? 'rgba(32,10,10,0.78)' : 'rgba(12,16,24,0.74)')
              .borderRadius(UI_RADIUS_PILL)
              .border({ width: 0.8, color: this.bandAccent(this.currentBand()) })
              .position({
                x: Math.max(12, Math.min(this.screenW - 230, this.centerX() - 108)),
                y: Math.min(this.screenH - 132, this.centerY() + this.radiusVp() - 32)
              })
              .hitTestBehavior(HitTestMode.None)
          }
        }

        // 顶部瞬态状态浮标（仅在拉大/缩拢过阈值或切波段时短暂展示，静止零遮挡）
        if (this.expandPromptVisible || this.shrinkClosePromptVisible || this.rotatePromptVisible) {
          Row() {
            Text(this.expandPromptVisible
              ? '松手扩散至全屏多光谱'
              : (this.shrinkClosePromptVisible
                ? '松手关闭透视镜'
                : (this.currentBand().shortName + ' · ' + (this.bandIndex + 1).toString() + '/9')))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .backgroundColor(this.c.isNight ? 'rgba(32,10,10,0.82)' : 'rgba(12,16,24,0.78)')
              .borderRadius(UI_RADIUS_PILL)
              .border({ width: 1, color: this.bandAccent(this.currentBand()) })
          }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .position({ x: 0, y: 48 })
            .hitTestBehavior(HitTestMode.None)
        }
      }
    }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .onAreaChange((_oldVal: Area, newVal: Area) => {
        const w = Number(newVal.width)
        const h = Number(newVal.height)
        if (w > 100 && h > 100) {
          this.screenW = w
          this.screenH = h
          if (this.active) this.syncFullNativeLens()
        }
      })
  }
}
