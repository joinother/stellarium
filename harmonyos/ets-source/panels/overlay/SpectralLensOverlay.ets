import { Theme } from '@kit.ArkUI'
import { vibrator } from '@kit.SensorServiceKit'
import { BridgeClient } from '../../bridge/BridgeClient'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'

interface LensBandSpec {
  id: string
  shortName: string
  color: string
  nightColor: string
  angleDeg: number
}

// 9 波段均匀排布在圆镜外圈（步进 40°，起始 45° 右下方顺手握持位），支持顺/逆时针 360° 连续旋切。
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

// Sky Guide 风格多光谱透视放大镜浮层：
//   - 圆镜主体单指自由拖动，镜内由 C++ HipsMgr GPU 光线投射实时渲染 4K 多光谱全景；
//   - 外圈可旋转转柄（9 个波段棘轮刻度），单指绕镜心转动即可 450ms 交叉渐变切换 9 波段；
//   - 顶部紧凑胶囊提供 1× / 2× 放大倍率切换、一键全屏、关闭；
//   - 根容器 HitTestMode.Transparent，镜外所有星图拖动/缩放/点选与底栏交互 100% 透传。
@Component
export struct SpectralLensOverlay {
  @StorageLink('stellariumSpectralLensActive') @Watch('onActiveChanged') active: boolean = false
  @StorageLink('stellariumSpectralLensBand') @Watch('onExternalBandChanged') storedBandId: string = 'finkbeiner-ha'
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private screenW: number = 960
  @State private screenH: number = 600
  @State private normX: number = 0.50
  @State private normY: number = 0.44
  @State private radiusNorm: number = 0.215
  @State private zoomFactor: number = 1.0
  @State private bandIndex: number = 0
  @State private handleAngleDeg: number = 45
  @State private isDraggingLens: boolean = false
  @State private isRotatingHandle: boolean = false
  @State private showRotateTip: boolean = true

  private dragStartWinX: number = 0
  private dragStartWinY: number = 0
  private dragStartNormX: number = 0.50
  private dragStartNormY: number = 0.44
  private tipTimerId: number = -1

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToAppear(): void {
    const idx = bandIndexById(this.storedBandId)
    this.bandIndex = idx
    this.handleAngleDeg = LENS_BANDS[idx].angleDeg
    if (this.active) {
      this.syncNativeLens()
      this.scheduleTipFade()
    }
  }

  aboutToDisappear(): void {
    if (this.tipTimerId >= 0) {
      clearTimeout(this.tipTimerId)
      this.tipTimerId = -1
    }
  }

  private scheduleTipFade(): void {
    this.showRotateTip = true
    if (this.tipTimerId >= 0) clearTimeout(this.tipTimerId)
    this.tipTimerId = setTimeout(() => {
      this.showRotateTip = false
      this.tipTimerId = -1
    }, 3600)
  }

  private onActiveChanged(): void {
    if (this.active) {
      const idx = bandIndexById(this.storedBandId)
      this.bandIndex = idx
      this.handleAngleDeg = LENS_BANDS[idx].angleDeg
      this.syncNativeLens()
      this.scheduleTipFade()
    } else {
      BridgeClient.send('setSpectralLens', '0')
    }
  }

  private onExternalBandChanged(): void {
    const idx = bandIndexById(this.storedBandId)
    if (idx !== this.bandIndex) {
      this.bandIndex = idx
      this.handleAngleDeg = LENS_BANDS[idx].angleDeg
      if (this.active) this.syncNativeLens()
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

  private syncNativeLens(): void {
    if (!this.active) return
    const payload = '1|' + this.currentBand().id + '|' +
      this.normX.toFixed(4) + '|' +
      this.normY.toFixed(4) + '|' +
      this.radiusNorm.toFixed(4) + '|' +
      this.zoomFactor.toFixed(2)
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
      this.handleAngleDeg = LENS_BANDS[clamped].angleDeg
    }
    if (changed) {
      this.triggerDetentHaptic()
      this.syncNativeLens()
    }
  }

  private toggleZoom(): void {
    this.zoomFactor = this.zoomFactor > 1.5 ? 1.0 : 2.0
    this.triggerDetentHaptic()
    this.syncNativeLens()
  }

  private expandToFullScreen(): void {
    const id = this.currentBand().id
    this.active = false
    BridgeClient.send('setSpectralLens', '0')
    BridgeClient.send('setSpectralView', JSON.stringify({ id: id, enabled: true }))
  }

  private closeLens(): void {
    this.active = false
    BridgeClient.send('setSpectralLens', '0')
  }

  private handleLensTouch(event: TouchEvent): void {
    event.stopPropagation()
    if (!event.touches || event.touches.length === 0) return
    const t = event.touches[0]
    if (event.type === TouchType.Down) {
      this.isDraggingLens = true
      this.showRotateTip = false
      this.dragStartWinX = t.windowX
      this.dragStartWinY = t.windowY
      this.dragStartNormX = this.normX
      this.dragStartNormY = this.normY
    } else if (event.type === TouchType.Move && this.isDraggingLens) {
      const dx = t.windowX - this.dragStartWinX
      const dy = t.windowY - this.dragStartWinY
      const nextX = Math.max(0.12, Math.min(0.88, this.dragStartNormX + dx / Math.max(1, this.screenW)))
      const nextY = Math.max(0.14, Math.min(0.80, this.dragStartNormY + dy / Math.max(1, this.screenH)))
      this.normX = nextX
      this.normY = nextY
      this.syncNativeLens()
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isDraggingLens = false
    }
  }

  private handleRotateTouch(event: TouchEvent): void {
    event.stopPropagation()
    if (!event.touches || event.touches.length === 0) return
    const t = event.touches[0]
    if (event.type === TouchType.Down) {
      this.isRotatingHandle = true
      this.showRotateTip = false
    } else if (event.type === TouchType.Move && this.isRotatingHandle) {
      const dx = t.windowX - this.centerX()
      const dy = t.windowY - this.centerY()
      if (dx * dx + dy * dy > 16) {
        const angleDeg = normalizeAngleDeg(Math.atan2(dy, dx) * 180 / Math.PI)
        this.handleAngleDeg = angleDeg
        const nextIdx = bandIndexFromAngle(angleDeg)
        if (nextIdx !== this.bandIndex) {
          this.selectBandIndex(nextIdx, false)
        }
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isRotatingHandle = false
      this.handleAngleDeg = LENS_BANDS[this.bandIndex].angleDeg
    }
  }

  private pillTop(): number {
    const r = this.radiusVp()
    const above = this.centerY() - r - 48
    if (above >= 52) return above
    return Math.min(this.screenH - 120, this.centerY() + r + 14)
  }

  private handleCenterOffset(distFromCenter: number): number[] {
    const rad = this.handleAngleDeg * Math.PI / 180
    return [this.centerX() + Math.cos(rad) * distFromCenter, this.centerY() + Math.sin(rad) * distFromCenter]
  }

  build() {
    Stack() {
      if (this.active) {
        // 1. 圆形光学透视镜框 + 镜面单指拖动区
        Stack({ alignContent: Alignment.Center }) {
          // 内玻璃高光环
          Circle()
            .width(this.radiusVp() * 2 - 4)
            .height(this.radiusVp() * 2 - 4)
            .fill(Color.Transparent)
            .stroke(this.c.isNight ? 'rgba(196,69,54,0.38)' : 'rgba(255,255,255,0.28)')
            .strokeWidth(1)
            .hitTestBehavior(HitTestMode.None)

          // 外金属精密镜圈（随当前波段柔和发光）
          Circle()
            .width(this.radiusVp() * 2 + 2)
            .height(this.radiusVp() * 2 + 2)
            .fill(Color.Transparent)
            .stroke(this.bandAccent(this.currentBand()))
            .strokeWidth(this.isRotatingHandle ? 3.2 : 2.4)
            .opacity(this.isRotatingHandle ? 0.96 : 0.82)
            .hitTestBehavior(HitTestMode.None)

          // 极淡的中心光学准星（拖动或 2× 放大时帮助精准对准星云）
          if (this.isDraggingLens || this.zoomFactor > 1.5) {
            Stack({ alignContent: Alignment.Center }) {
              Row()
                .width(14)
                .height(1)
                .backgroundColor(this.bandAccent(this.currentBand()))
                .opacity(0.55)
              Column()
                .width(1)
                .height(14)
                .backgroundColor(this.bandAccent(this.currentBand()))
                .opacity(0.55)
            }
              .hitTestBehavior(HitTestMode.None)
          }

          // 首次打开或转动转柄时的轻量提示
          if (this.showRotateTip || this.isRotatingHandle) {
            Text(this.isRotatingHandle
              ? (this.currentBand().shortName + ' · ' + (this.bandIndex + 1).toString() + '/9')
              : '转动转柄切换波段')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(this.c.isNight ? 'rgba(32,10,10,0.78)' : 'rgba(12,16,24,0.72)')
              .borderRadius(UI_RADIUS_PILL)
              .border({ width: 0.8, color: this.bandAccent(this.currentBand()) })
              .translate({ y: this.radiusVp() - 28 })
              .hitTestBehavior(HitTestMode.None)
          }
        }
          .id('spectral-lens-ring')
          .width(this.radiusVp() * 2 + 6)
          .height(this.radiusVp() * 2 + 6)
          .borderRadius(this.radiusVp() + 3)
          .position({
            x: this.centerX() - (this.radiusVp() + 3),
            y: this.centerY() - (this.radiusVp() + 3)
          })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.48)', offsetX: 0, offsetY: 6 })
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => { this.handleLensTouch(event) })

        // 2. 镜圈 9 个波段棘轮发光刻度（点击也可直达对应波段）
        ForEach(LENS_BANDS, (spec: LensBandSpec, idx: number) => {
          Stack({ alignContent: Alignment.Center }) {
            Row()
              .width(idx === this.bandIndex ? 10 : 6)
              .height(idx === this.bandIndex ? 10 : 6)
              .borderRadius(idx === this.bandIndex ? 5 : 3)
              .backgroundColor(this.bandAccent(spec))
              .border({
                width: idx === this.bandIndex ? 1.5 : 0.8,
                color: idx === this.bandIndex ? '#FFFFFF' : 'rgba(255,255,255,0.45)'
              })
              .opacity(idx === this.bandIndex ? 1.0 : 0.72)
          }
            .width(22)
            .height(22)
            .position({
              x: this.centerX() + Math.cos(spec.angleDeg * Math.PI / 180) * (this.radiusVp() + 1) - 11,
              y: this.centerY() + Math.sin(spec.angleDeg * Math.PI / 180) * (this.radiusVp() + 1) - 11
            })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => { this.selectBandIndex(idx, true) })
        }, (spec: LensBandSpec) => spec.id)

        // 3. 可 360° 旋转的金属防滑放大镜转柄（单指拖动绕镜心旋转即切 9 波段）
        Stack({ alignContent: Alignment.Center }) {
          Row({ space: 6 }) {
            // 镜圈连接颈环（波段色指示光环）
            Row()
              .width(8)
              .height(16)
              .borderRadius(4)
              .backgroundColor(this.bandAccent(this.currentBand()))
              .opacity(0.92)
            // 防滑滚花刻纹
            Row({ space: 4 }) {
              Row().width(2).height(11).borderRadius(1).backgroundColor('rgba(255,255,255,0.32)')
              Row().width(2).height(13).borderRadius(1).backgroundColor('rgba(255,255,255,0.42)')
              Row().width(2).height(13).borderRadius(1).backgroundColor('rgba(255,255,255,0.42)')
              Row().width(2).height(11).borderRadius(1).backgroundColor('rgba(255,255,255,0.32)')
            }
              .alignItems(VerticalAlign.Center)
            // 尾部指示点
            Row()
              .width(7)
              .height(7)
              .borderRadius(3.5)
              .backgroundColor(this.bandAccent(this.currentBand()))
              .border({ width: 1, color: 'rgba(255,255,255,0.75)' })
          }
            .width(78)
            .height(28)
            .padding({ left: 6, right: 9 })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(this.c.isNight ? '#2A1111' : '#1B2230')
            .borderRadius(14)
            .border({
              width: this.isRotatingHandle ? 1.8 : 1.2,
              color: this.isRotatingHandle ? this.bandAccent(this.currentBand()) : 'rgba(255,255,255,0.34)'
            })
            .shadow({ radius: 14, color: 'rgba(0,0,0,0.55)', offsetX: 0, offsetY: 4 })
            .hitTestBehavior(HitTestMode.None)
        }
          .id('spectral-lens-handle')
          .width(96)
          .height(52)
          .position({
            x: this.handleCenterOffset(this.radiusVp() + 42)[0] - 48,
            y: this.handleCenterOffset(this.radiusVp() + 42)[1] - 26
          })
          .rotate({ angle: this.handleAngleDeg })
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => { this.handleRotateTouch(event) })

        // 4. 紧凑悬浮控制胶囊（波段名 + 1×/2× 放大倍率 + 全屏 + 关闭）
        Row({ space: 6 }) {
          Row({ space: 5 }) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.bandAccent(this.currentBand()))
            Text(this.currentBand().shortName)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.text)
              .maxLines(1)
          }
            .padding({ left: 4, right: 4 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.selectBandIndex(this.bandIndex + 1, true) })

          Row().width(1).height(14).backgroundColor(this.c.border)

          // 1× / 2× 倍率切换按钮
          Text(this.zoomFactor > 1.5 ? '2×' : '1×')
            .id('spectral-lens-zoom-toggle')
            .fontSize(11.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.zoomFactor > 1.5 ? this.c.onAccent : this.c.text)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(UI_RADIUS_PILL)
            .backgroundColor(this.zoomFactor > 1.5 ? this.c.accent : this.c.soft)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.toggleZoom() })

          // 一键展开为全天多光谱
          Text('全屏')
            .id('spectral-lens-fullscreen')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.text)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(UI_RADIUS_PILL)
            .backgroundColor(this.c.soft)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.expandToFullScreen() })

          // 关闭按钮
          Text('✕')
            .id('spectral-lens-close')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.sub)
            .padding({ left: 6, right: 6, top: 4, bottom: 4 })
            .borderRadius(UI_RADIUS_PILL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.closeLens() })
        }
          .id('spectral-lens-pill')
          .height(36)
          .padding({ left: 10, right: 8 })
          .backgroundColor(this.c.hintPillBg)
          .borderRadius(UI_RADIUS_PILL)
          .border({ width: 1, color: this.c.border })
          .shadow({ radius: 18, color: this.c.shadowSoft, offsetX: 0, offsetY: 6 })
          .alignItems(VerticalAlign.Center)
          .position({
            x: Math.max(12, Math.min(this.screenW - 240, this.centerX() - 114)),
            y: this.pillTop()
          })
          .hitTestBehavior(HitTestMode.Default)
          .onClick(() => {})
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
          if (this.active) this.syncNativeLens()
        }
      })
  }
}
