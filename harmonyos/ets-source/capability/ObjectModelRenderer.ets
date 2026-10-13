// 对象检查器三维模型渲染器。
//
// 负责天体模型的纹理提交、worker 光栅化调度、模型触摸交互与光照刷新，以及沉浸叠层的发布。
// 可观测子集（objectInspectorModelPixelMap / Immersive / OverlayOpacity / Scale / Interacting /
// objectInspectorProceduralKind）在 state/ObjectMediaStore.ets，本控制器只读写该 store，不新建可观察字段；
// 逐帧/草稿字段（纹理与环纹理三量、旋转/缩放采样、渲染代际/挂起/播放中标志、一次性渲染防抖定时器）
// 留本控制器普通字段，不入被观察 store，避免每帧触发刷新。
//
// 依赖：ObjectModelMediaPort 封装纹理解码 / RGBA→像素图 / PNG 回退读回，本类不 import fileIo/image 的
// 设备能力调用（image 仅用于 PixelMap 类型）；DetailModelRenderClient 为既有 worker 客户端；
// ObjectMediaStore / ObjectDetailStore / InfoWindowStore 以实例引用持有；ObjectModelRendererHostHooks
// 回注 AppStorage 发布、UI 动画（getUIContext().animateTo）与媒体管线保留字段。
import hilog from '@ohos.hilog'
import { image } from '@kit.ImageKit'
import { ObjectMediaStore } from '../state/ObjectMediaStore'
import { ObjectDetailStore } from '../state/ObjectDetailStore'
import { InfoWindowStore } from '../state/InfoWindowStore'
import { ObjectModelMediaPort } from '../bridge/MediaPort'
import { DetailModelRenderClient } from './DetailModelRenderClient'
import { DetailModelResources, DetailModelFrame, DetailModelResult, DetailModelRing, DetailModelLight } from './DetailModelRenderTypes'
import { modelIdentity, modelDrag } from '../common/derive/DetailModelGeometry'
import { objectInspectorPlanetRingSpec } from '../common/derive/media'
import { decodeLocalImage, releaseDecodedImage } from '../common/media/ImageDecoder'
import { describeDecodeError } from '../common/derive/labels'
import { touchScreenX, touchScreenY } from '../common/derive/geometry'

// 宿主 → 控制器回注：
//   - publishModelView：AppStorage.setOrCreate('stellariumObjectModelView', json)（UI 全局观察通道，
//     QAbility 与 CLI 侧读取）；
//   - animateOverlay：getUIContext().animateTo(...)，沉浸叠层的淡入/淡出动画（UI）；
//   - mediaDecodeGeneration / proceduralParticles / resetProcedural：媒体管线保留字段
//     （objectInspectorProceduralKey/Particles、objectInspectorMediaDecodeGeneration），经 hooks 只读/重置。
export interface ObjectModelRendererHostHooks {
  publishModelView(json: string): void
  animateOverlay(open: boolean, body: () => void, onFinish: () => void): void
  mediaDecodeGeneration(): number
  proceduralParticles(): number[][]
  resetProcedural(): void
}

export class ObjectModelRenderer {
  private mediaStore: ObjectMediaStore
  private detailStore: ObjectDetailStore
  private infoStore: InfoWindowStore
  private mediaPort: ObjectModelMediaPort
  private hooks: ObjectModelRendererHostHooks

  // ── 逐帧/草稿字段（留控制器，不入被观察 store）──
  private objectInspectorModelOverlaySerial: number = 0
  private objectInspectorModelRendering: boolean = false
  private objectInspectorModelRenderClient: DetailModelRenderClient | undefined = undefined
  private objectInspectorModelRotation: number[] = modelIdentity()
  private objectInspectorModelLastLighting: number[] = []
  private objectInspectorModelLastRenderTime: number = 0
  private objectInspectorModelTouchCount: number = 0
  private objectInspectorModelTexturePixels: ArrayBuffer | undefined = undefined
  private objectInspectorModelTextureWidth: number = 0
  private objectInspectorModelTextureHeight: number = 0
  private objectInspectorModelTextureStride: number = 0
  private objectInspectorModelRingTexturePixels: ArrayBuffer | undefined = undefined
  private objectInspectorModelRingTextureWidth: number = 0
  private objectInspectorModelRingTextureHeight: number = 0
  private objectInspectorModelRingTextureStride: number = 0
  private objectInspectorModelLastX: number = 0
  private objectInspectorModelLastY: number = 0
  private objectInspectorModelLastPinchDistance: number = 0
  private objectInspectorModelRenderGeneration: number = 0
  private objectInspectorModelRenderPending: boolean = false
  private objectInspectorModelRenderHighQuality: boolean = false
  // 一次性防抖定时器（requestObjectInspectorModelRender 按需挂起，18ms 后自清；非周期轮询）。
  private objectInspectorModelRenderTimer: number = 0
  // 前后台标志（DetailModelRenderClient.setSuspended 的入参来源）。
  private foreground: boolean = true

  constructor(
    mediaStore: ObjectMediaStore,
    detailStore: ObjectDetailStore,
    infoStore: InfoWindowStore,
    mediaPort: ObjectModelMediaPort,
    hooks: ObjectModelRendererHostHooks
  ) {
    this.mediaStore = mediaStore
    this.detailStore = detailStore
    this.infoStore = infoStore
    this.mediaPort = mediaPort
    this.hooks = hooks
  }

  // ── 宿主生命周期收口 ──
  // 本控制器只持一个一次性防抖 setTimeout：requestObjectInspectorModelRender 挂起、触发即自清，
  // 或在 clear()/高画质请求时被 clearTimeout。stop() 清除在途防抖（宿主 aboutToDisappear 收口）。
  stop(): void {
    this.cancelRenderTimer()
  }

  // 应用前后台切换：更新标志并挂起/恢复 worker 看门狗（setSuspended(!foreground)）。
  setForeground(foreground: boolean): void {
    this.foreground = foreground
    this.objectInspectorModelRenderClient?.setSuspended(!foreground)
  }

  // ── 组件消费的只读查询（宿主 @Prop 下发的计算值）──
  isRendering(): boolean {
    return this.objectInspectorModelRendering
  }

  hasTexture(): boolean {
    return this.objectInspectorModelTexturePixels !== undefined
  }

  modelReady(): boolean {
    return this.mediaStore.objectInspectorModelReady(
      this.objectInspectorModelTexturePixels, this.objectInspectorModelTextureWidth, this.objectInspectorModelTextureHeight)
  }

  // 新选择/media 变更时重置视角与双指采样。
  resetRotationForNewMedia(): void {
    this.objectInspectorModelRotation = this.mediaStore.defaultObjectInspectorModelRotation()
    this.objectInspectorModelLastPinchDistance = 0
  }

  private cancelRenderTimer(): void {
    if (this.objectInspectorModelRenderTimer !== 0) {
      clearTimeout(this.objectInspectorModelRenderTimer)
      this.objectInspectorModelRenderTimer = 0
    }
  }

  // 选中身份（渲染/纹理提交的代际校验键）。
  private selectionKey(): string {
    return this.detailStore.selectedName + '\n' + this.detailStore.selectedEnglishName + '\n' + this.detailStore.selectedCatalogId
  }

  // 清空模型渲染器：销毁 worker、复位 store 与纹理、发布未就绪视图。
  clearObjectInspectorModelRenderer(): void {
    this.objectInspectorModelRenderClient?.dispose()
    this.objectInspectorModelRenderClient = undefined
    this.mediaStore.objectInspectorProceduralKind = ''
    this.hooks.resetProcedural()
    this.mediaStore.objectInspectorModelImmersive = false
    this.mediaStore.objectInspectorModelOverlayOpacity = 0
    this.objectInspectorModelOverlaySerial++
    this.hooks.publishModelView(JSON.stringify({
      ok: false, error: 'model is not ready'
    }))
    this.objectInspectorModelTouchCount = 0
    this.objectInspectorModelLastLighting = []
    const oldModelPixelMap = this.mediaStore.objectInspectorModelPixelMap
    this.cancelRenderTimer()
    this.mediaStore.objectInspectorModelPixelMap = undefined
    this.objectInspectorModelTexturePixels = undefined
    this.objectInspectorModelTextureWidth = 0
    this.objectInspectorModelTextureHeight = 0
    this.objectInspectorModelTextureStride = 0
    this.objectInspectorModelRingTexturePixels = undefined
    this.objectInspectorModelRingTextureWidth = 0
    this.objectInspectorModelRingTextureHeight = 0
    this.objectInspectorModelRingTextureStride = 0
    this.objectInspectorModelRendering = false
    this.objectInspectorModelRenderPending = false
    this.objectInspectorModelRenderHighQuality = false
    this.mediaStore.objectInspectorModelInteracting = false
    this.objectInspectorModelRenderGeneration++
    releaseDecodedImage(this.mediaPort, oldModelPixelMap, 'object-inspector-model')
  }

  // 纹理提交失败：仅在解码代际未过期时置失败状态并记录日志。
  failObjectInspectorModelTexture(mediaGeneration: number, reason: string): void {
    if (mediaGeneration !== this.hooks.mediaDecodeGeneration()) {
      return
    }
    this.mediaStore.objectInspectorMediaLoading = false
    this.mediaStore.objectInspectorMediaDecoding = false
    this.mediaStore.objectInspectorMediaLoadFailed = true
    hilog.error(0x0000, 'StellariumArkUI',
      '[detail-model] CPU texture load failed uri=%{public}s reason=%{public}s',
      this.mediaStore.objectInspectorMediaPath, reason)
  }

  // 提交 CPU 纹理：校验选中身份 / 路径 / 解码代际后写入纹理并触发渲染。
  commitObjectInspectorModelTexture(
    texture: ArrayBuffer,
    ringTexture: ArrayBuffer | undefined,
    mediaGeneration: number,
    expectedSelection: string,
    expectedPath: string,
    sourceLabel: string,
  ): void {
    const currentSelection = this.selectionKey()
    if (currentSelection !== expectedSelection || this.mediaStore.objectInspectorMediaPath !== expectedPath ||
      mediaGeneration !== this.hooks.mediaDecodeGeneration()) {
      return
    }
    this.objectInspectorModelTexturePixels = texture
    this.objectInspectorModelTextureWidth = 512
    this.objectInspectorModelTextureHeight = 256
    this.objectInspectorModelTextureStride = 512 * 4
    if (ringTexture !== undefined) {
      this.objectInspectorModelRingTexturePixels = ringTexture
      this.objectInspectorModelRingTextureWidth = 512
      this.objectInspectorModelRingTextureHeight = 2
      this.objectInspectorModelRingTextureStride = 512 * 4
    } else {
      this.objectInspectorModelRingTexturePixels = undefined
      this.objectInspectorModelRingTextureWidth = 0
      this.objectInspectorModelRingTextureHeight = 0
      this.objectInspectorModelRingTextureStride = 0
    }
    this.mediaStore.objectInspectorMediaLoading = false
    this.mediaStore.objectInspectorMediaDecoding = true
    this.mediaStore.objectInspectorMediaLoadFailed = false
    hilog.info(0x0000, 'StellariumArkUI',
      '[detail-model] CPU texture ready uri=%{public}s bytes=%{public}s source=%{public}s phase=%{public}s',
      expectedPath, texture.byteLength.toString(), sourceLabel, this.detailStore.selectedPhase)
    this.requestObjectInspectorModelRender(true)
  }

  // 从 PNG 侧车文件解码模型纹理（可选环纹理），解码与读回经 MediaPort。
  decodeObjectInspectorModelTextureFromPng(
    pngFilePath: string,
    ringPngFilePath: string,
    mediaGeneration: number,
    expectedSelection: string,
    expectedPath: string,
  ): void {
    if (pngFilePath.length === 0) {
      this.failObjectInspectorModelTexture(mediaGeneration, 'sidecar and PNG are both missing')
      return
    }
    decodeLocalImage(this.mediaPort, pngFilePath, 'model', (pixelMap: image.PixelMap) => {
      const pixels = new ArrayBuffer(512 * 256 * 4)
      try {
        this.mediaPort.readPixelMapPixels(pixelMap, pixels, 'model-texture-fallback')
      } catch (err) {
        releaseDecodedImage(this.mediaPort, pixelMap, 'model-texture-fallback')
        this.failObjectInspectorModelTexture(mediaGeneration, 'PNG readback failed: ' + describeDecodeError(err as Error))
        return
      }
      releaseDecodedImage(this.mediaPort, pixelMap, 'model-texture-fallback')
      if (ringPngFilePath.length === 0) {
        this.commitObjectInspectorModelTexture(pixels, undefined, mediaGeneration, expectedSelection, expectedPath, 'png')
        return
      }
      decodeLocalImage(this.mediaPort, ringPngFilePath, 'model', (ringPixelMap: image.PixelMap) => {
        const ringPixels = new ArrayBuffer(512 * 2 * 4)
        let ringTexture: ArrayBuffer | undefined = undefined
        try {
          this.mediaPort.readPixelMapPixels(ringPixelMap, ringPixels, 'model-ring-texture-fallback')
          ringTexture = ringPixels
        } catch (err) {
          hilog.warn(0x0000, 'StellariumArkUI', '[detail-model] ring PNG readback failed error=%{public}s',
            describeDecodeError(err as Error))
        }
        releaseDecodedImage(this.mediaPort, ringPixelMap, 'model-ring-texture-fallback')
        this.commitObjectInspectorModelTexture(pixels, ringTexture, mediaGeneration, expectedSelection, expectedPath, 'png')
      }, (err: Error) => {
        hilog.warn(0x0000, 'StellariumArkUI', '[detail-model] ring PNG decode failed error=%{public}s',
          describeDecodeError(err))
        this.commitObjectInspectorModelTexture(pixels, undefined, mediaGeneration, expectedSelection, expectedPath, 'png')
      }, { width: 512, height: 2 })
    }, (err: Error) => {
      this.failObjectInspectorModelTexture(mediaGeneration, 'PNG decode failed: ' + describeDecodeError(err))
    }, { width: 512, height: 256 })
  }

  // 光照变化时触发重渲染（250ms 节流）。
  refreshObjectInspectorModelLighting(): void {
    if (!this.infoStore.infoWinVisible || this.detailStore.bottomCardIndex !== 2) return
    const lighting = this.detailStore.selectedDetailModel?.lighting
    if (lighting === undefined || this.objectInspectorModelTexturePixels === undefined) return
    const values = lighting.viewToBody.concat(lighting.sunDirectionBody)
    const changed = values.some((value: number, index: number) =>
      Math.abs(value - (this.objectInspectorModelLastLighting[index] ?? 10)) > 0.0001)
    if (changed && Date.now() - this.objectInspectorModelLastRenderTime >= 250) {
      this.requestObjectInspectorModelRender(!this.mediaStore.objectInspectorModelInteracting)
    }
  }

  // 按拖动增量旋转模型并请求低画质重渲染。
  rotateObjectInspectorModel(deltaX: number, deltaY: number): void {
    this.objectInspectorModelRotation = modelDrag(this.objectInspectorModelRotation, deltaX, deltaY)
    this.requestObjectInspectorModelRender(false)
  }

  // 请求渲染：低画质经 18ms 防抖合帧，高画质立即冲刷。
  requestObjectInspectorModelRender(highQuality: boolean): void {
    if (!this.modelReady()) {
      return
    }
    this.objectInspectorModelRenderHighQuality = this.objectInspectorModelRenderHighQuality || highQuality
    this.objectInspectorModelRenderPending = true
    if (this.objectInspectorModelRendering) {
      return
    }
    if (!highQuality) {
      if (this.objectInspectorModelRenderTimer !== 0) {
        return
      }
      this.objectInspectorModelRenderTimer = setTimeout(() => {
        this.objectInspectorModelRenderTimer = 0
        this.flushObjectInspectorModelRender()
      }, 18)
      return
    }
    if (this.objectInspectorModelRenderTimer !== 0) {
      clearTimeout(this.objectInspectorModelRenderTimer)
      this.objectInspectorModelRenderTimer = 0
    }
    this.flushObjectInspectorModelRender()
  }

  // 冲刷挂起的渲染请求（合并高画质标志）。
  private flushObjectInspectorModelRender(): void {
    if (this.objectInspectorModelRendering || !this.objectInspectorModelRenderPending ||
      !this.modelReady()) {
      return
    }
    const renderHighQuality = this.objectInspectorModelRenderHighQuality
    this.objectInspectorModelRenderPending = false
    this.objectInspectorModelRenderHighQuality = false
    this.objectInspectorModelRendering = true
    this.renderObjectInspectorModel(renderHighQuality)
  }

  // 执行一次 worker 光栅化，结果经代际校验后发布像素图并回收旧图。
  private renderObjectInspectorModel(highQuality: boolean): void {
    if (!this.modelReady()) {
      this.objectInspectorModelRendering = false
      return
    }
    const generation = this.objectInspectorModelRenderGeneration
    const immersive = this.mediaStore.objectInspectorModelImmersive
    const renderSize = highQuality ? (immersive ? 640 : 320) : 224
    const transform = this.detailStore.objectInspectorModelTransform(this.objectInspectorModelRotation)
    const inspectionRotation = this.objectInspectorModelRotation.slice()
    const lighting = this.detailStore.selectedDetailModel?.lighting
    const started = Date.now()
    let computeMs = 0
    let pixelMapStarted = 0
    let uiPulseCount = 0
    let uiMaxDelayMs = 0
    this.objectInspectorModelLastRenderTime = started
    this.objectInspectorModelLastLighting = lighting === undefined ? [] :
      lighting.viewToBody.concat(lighting.sunDirectionBody)
    if (this.mediaStore.objectInspectorModelPixelMap === undefined) this.mediaStore.objectInspectorMediaDecoding = true
    const ring = objectInspectorPlanetRingSpec(this.detailStore.selectedEnglishName)
    const renderRing: DetailModelRing | undefined = ring === undefined ? undefined : {
      innerRadius: ring.innerRadius, outerRadius: ring.outerRadius, opacity: ring.opacity
    }
    const renderLighting: DetailModelLight | undefined = lighting === undefined ? undefined : {
      viewToBody: lighting.viewToBody, sunDirectionBody: lighting.sunDirectionBody, emissive: lighting.emissive
    }
    const resources: DetailModelResources = {
      texture: this.objectInspectorModelTexturePixels,
      textureWidth: this.objectInspectorModelTextureWidth,
      textureHeight: this.objectInspectorModelTextureHeight,
      textureStride: this.objectInspectorModelTextureStride,
      ringTexture: this.objectInspectorModelRingTexturePixels,
      ringWidth: this.objectInspectorModelRingTextureWidth,
      ringHeight: this.objectInspectorModelRingTextureHeight,
      ringSpec: renderRing,
      kind: this.mediaStore.objectInspectorProceduralKind,
      temperature: this.detailStore.selectedTemperatureK,
      particles: this.hooks.proceduralParticles()
    }
    const frame: DetailModelFrame = {
      renderSize: renderSize, scale: this.mediaStore.objectInspectorModelScale, transform: transform, lighting: renderLighting
    }
    if (this.objectInspectorModelRenderClient === undefined) {
      this.objectInspectorModelRenderClient = new DetailModelRenderClient()
    }
    this.objectInspectorModelRenderClient.setSuspended(!this.foreground)
    this.objectInspectorModelRenderClient.render(resources, frame).then((result: DetailModelResult) => {
      if (generation !== this.objectInspectorModelRenderGeneration || !this.modelReady()) {
        throw new Error('stale model frame')
      }
      const resultPixels = result.pixels
      if (resultPixels === undefined) {
        throw new Error('model frame missing')
      }
      computeMs = result.computeMs
      uiPulseCount = result.uiPulseCount ?? 0
      uiMaxDelayMs = result.uiMaxDelayMs ?? 0
      pixelMapStarted = Date.now()
      return this.mediaPort.createPixelMapFromRgba(resultPixels, renderSize, renderSize, 'object-inspector-model')
    }).then((pixelMap: image.PixelMap) => {
      if (generation !== this.objectInspectorModelRenderGeneration ||
        !this.modelReady()) {
        releaseDecodedImage(this.mediaPort, pixelMap, 'stale-object-inspector-model')
        return
      }
      const oldPixelMap = this.mediaStore.objectInspectorModelPixelMap
      this.mediaStore.objectInspectorModelPixelMap = pixelMap
      this.hooks.publishModelView(JSON.stringify({
        ok: true, selectedEnglishName: this.detailStore.selectedEnglishName,
        rotation: inspectionRotation, viewToBody: transform,
        lighting: lighting, renderSize: renderSize, renderedAt: this.objectInspectorModelLastRenderTime,
        kind: this.mediaStore.objectInspectorProceduralKind || 'textured-sphere',
        schematic: this.mediaStore.objectInspectorProceduralKind.length > 0,
        temperatureK: this.detailStore.selectedTemperatureK > 0 ? this.detailStore.selectedTemperatureK : null,
        immersive: immersive, renderer: 'worker', computeMs: computeMs,
        uiPulseCount: uiPulseCount, uiMaxDelayMs: uiMaxDelayMs,
        pixelMapMs: Date.now() - pixelMapStarted, totalMs: Date.now() - started
      }))
      releaseDecodedImage(this.mediaPort, oldPixelMap, 'previous-object-inspector-model')
      this.objectInspectorModelRendering = false
      this.mediaStore.objectInspectorMediaDecoding = false
      this.mediaStore.objectInspectorMediaLoadFailed = false
      const renderAgain = this.objectInspectorModelRenderPending
      const renderAgainHighQuality = this.objectInspectorModelRenderHighQuality
      this.objectInspectorModelRenderPending = false
      this.objectInspectorModelRenderHighQuality = false
      if (renderAgain) {
        this.requestObjectInspectorModelRender(renderAgainHighQuality)
      }
    }).catch((err: Error) => {
      if (generation !== this.objectInspectorModelRenderGeneration) {
        return
      }
      this.objectInspectorModelRendering = false
      this.mediaStore.objectInspectorMediaDecoding = false
      this.mediaStore.objectInspectorMediaLoadFailed = true
      hilog.error(0x0000, 'StellariumArkUI',
        '[detail-model] sphere render failed error=%{public}s', JSON.stringify(err))
      this.hooks.publishModelView(JSON.stringify({
        ok: false, error: 'model render failed', selectedEnglishName: this.detailStore.selectedEnglishName
      }))
    })
  }

  // 复位视角与缩放并请求高画质重渲染。
  resetObjectInspectorModelView(): void {
    this.objectInspectorModelRotation = this.mediaStore.defaultObjectInspectorModelRotation()
    this.mediaStore.objectInspectorModelScale = 1
    this.objectInspectorModelLastPinchDistance = 0
    this.mediaStore.objectInspectorModelInteracting = false
    this.requestObjectInspectorModelRender(true)
  }

  // 切换沉浸叠层（淡入/淡出经 hooks.animateOverlay）。
  setObjectInspectorModelImmersive(open: boolean): void {
    if (open === this.mediaStore.objectInspectorModelImmersive &&
      this.mediaStore.objectInspectorModelOverlayOpacity === (open ? 1 : 0)) return
    const serial = ++this.objectInspectorModelOverlaySerial
    if (open) {
      this.mediaStore.objectInspectorModelImmersive = true
      this.mediaStore.objectInspectorModelOverlayOpacity = 0
      this.hooks.animateOverlay(true, () => {
        this.mediaStore.objectInspectorModelOverlayOpacity = 1
      }, () => {})
      this.requestObjectInspectorModelRender(true)
    } else {
      this.hooks.animateOverlay(false, () => {
        this.mediaStore.objectInspectorModelOverlayOpacity = 0
      }, () => {
        if (serial !== this.objectInspectorModelOverlaySerial) return
        this.mediaStore.objectInspectorModelImmersive = false
        this.requestObjectInspectorModelRender(true)
      })
    }
  }

  // 处理模型触摸：单指旋转、双指缩放。
  handleObjectInspectorModelTouch(event: TouchEvent): void {
    event.stopPropagation()
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.objectInspectorModelTouchCount = 0
      this.objectInspectorModelLastPinchDistance = 0
      this.mediaStore.objectInspectorModelInteracting = false
      this.requestObjectInspectorModelRender(true)
      return
    }
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) { return }
    const x = touchScreenX(points[0])
    const y = touchScreenY(points[0])
    if (event.type === TouchType.Down || this.objectInspectorModelTouchCount !== points.length) {
      this.objectInspectorModelTouchCount = points.length
      this.mediaStore.objectInspectorModelInteracting = true
      this.objectInspectorModelLastX = x
      this.objectInspectorModelLastY = y
      if (points.length > 1) {
        const secondX = touchScreenX(points[1])
        const secondY = touchScreenY(points[1])
        const deltaX = secondX - x
        const deltaY = secondY - y
        this.objectInspectorModelLastPinchDistance = Math.sqrt(deltaX * deltaX + deltaY * deltaY)
      } else {
        this.objectInspectorModelLastPinchDistance = 0
      }
      return
    }
    if (event.type === TouchType.Move) {
      if (points.length > 1) {
        const secondX = touchScreenX(points[1])
        const secondY = touchScreenY(points[1])
        const deltaX = secondX - x
        const deltaY = secondY - y
        const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY)
        if (this.objectInspectorModelLastPinchDistance > 0) {
          const rawScaleFactor = distance / this.objectInspectorModelLastPinchDistance
          if (Number.isFinite(rawScaleFactor) && Math.abs(rawScaleFactor - 1) > 0.002) {
            const scaleFactor = 1 + (rawScaleFactor - 1) * 0.68
            this.mediaStore.objectInspectorModelScale = Math.max(0.82, Math.min(1.20,
              this.mediaStore.objectInspectorModelScale * scaleFactor))
            this.requestObjectInspectorModelRender(false)
          }
        }
        this.objectInspectorModelLastPinchDistance = distance
        return
      }
      const deltaX = x - this.objectInspectorModelLastX
      const deltaY = y - this.objectInspectorModelLastY
      this.objectInspectorModelLastX = x
      this.objectInspectorModelLastY = y
      this.objectInspectorModelLastPinchDistance = 0
      this.rotateObjectInspectorModel(deltaX, deltaY)
      return
    }
  }
}
