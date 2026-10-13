// 对象检查器媒体控制器：解析选中天体的 detail 媒体请求（行星纹理 / 深空图 / 三维模型 /
// 程序化示意），预热并提交解码，管理全屏预览开合与重试。
//
// 依赖 ObjectMediaStore / ObjectDetailStore（可观测状态）与 ImagePort（本机解码）；
// ObjectInspectorMediaHostHooks 回注 filesDir / pathToUri / warmupStatus / 资源解析 /
// 准备失败判定与 ObjectModelRenderer 实例；控制器不 import NAPI/UI，stop() 收口两个预热定时器。
// 三维模型渲染 / 纹理提交 / 触摸在 ObjectModelRenderer，本控制器经 hook 持有其实例，不与其重叠。
import hilog from '@ohos.hilog'
import { image } from '@kit.ImageKit'
import { I18n } from '../pages/I18n'
import { DeepSkyWarmupStatus } from '../qability/StellariumResourceBootstrap'
import { ObjectMediaStore } from '../state/ObjectMediaStore'
import { ObjectDetailStore } from '../state/ObjectDetailStore'
import { ImagePort } from '../bridge/MediaPort'
import { ObjectModelRenderer } from './ObjectModelRenderer'
import { proceduralModelKind, proceduralParticles } from '../common/derive/ProceduralDetailModel'
import { objectInspectorPlanetTexturePath, objectInspectorDeepSkyImageName, objectInspectorFallbackVisualKind, objectInspectorPlanetRingSpec } from '../common/derive/media'
import { decodeLocalImage, releaseDecodedImage } from '../common/media/ImageDecoder'
import { describeDecodeError } from '../common/derive/labels'

// 宿主 → 控制器回注：
//   - filesDir：宿主 stellariumFilesDir()（getUIContext().getHostContext() 派生，控制器不 import UI 上下文）；
//   - pathToUri：宿主 fileUri.getUriFromPath（CoreFileKit NAPI 收在端口/宿主侧）；
//   - warmupStatus / resolveDetailMediaAsset / isPreparationFailed：ResourceBootstrap 三个需要应用上下文的
//     助手（控制器不 import NAPI/UI 上下文）；
//   - objectModelRenderer：既有三维模型渲染器实例（clear/isRendering/hasTexture/request/resetRotation）。
export interface ObjectInspectorMediaHostHooks {
  filesDir(): string
  pathToUri(path: string): string
  warmupStatus(): DeepSkyWarmupStatus
  resolveDetailMediaAsset(relativePath: string): Promise<string>
  isPreparationFailed(relativePath: string): boolean
  objectModelRenderer(): ObjectModelRenderer
}

// 七个行星（不含地球）加月球与太阳：值得在其详情卡打开前预解析的 detail 纹理。
const BODY_DETAIL_TEXTURE_PATHS: Array<string> = [
  'textures/sun.png', 'textures/mercury.png', 'textures/venus.png', 'textures/mars.png',
  'textures/jupiter.png', 'textures/saturn.png', 'textures/uranus.png', 'textures/neptune.png',
  'textures/moon.png',
]

export class ObjectInspectorMediaController {
  private mediaStore: ObjectMediaStore
  private detailStore: ObjectDetailStore
  private mediaPort: ImagePort
  private hooks: ObjectInspectorMediaHostHooks

  // ── 草稿/逐帧字段（留控制器，不入被观察 store：逐帧写入被观察 store 会造成重渲染风暴）──
  private objectInspectorMediaRequestPath: string = ''
  private objectInspectorMediaResolvedRequestPath: string = ''
  private objectInspectorMediaResolvedPath: string = ''
  private objectInspectorMediaResolutionComplete: boolean = false
  private objectInspectorMediaWarmupTimer: number = 0
  private objectInspectorMediaDecodeGeneration: number = 0
  private bodyDetailWarmupTimer: number = 0
  private bodyDetailWarmupIndex: number = 0
  private bodyDetailWarmupPending: Array<string> = []
  private objectInspectorProceduralKey: string = ''
  private objectInspectorProceduralParticles: number[][] = []

  constructor(
    mediaStore: ObjectMediaStore,
    detailStore: ObjectDetailStore,
    mediaPort: ImagePort,
    hooks: ObjectInspectorMediaHostHooks
  ) {
    this.mediaStore = mediaStore
    this.detailStore = detailStore
    this.mediaPort = mediaPort
    this.hooks = hooks
  }

  // ── 宿主生命周期收口 ──
  stop(): void {
    this.stopObjectInspectorMediaWarmup()
    this.stopBodyDetailWarmup()
  }

  // ── ObjectModelRenderer 媒体管线回注（媒体解码代际与程序化粒子的只读/复位）──
  mediaDecodeGeneration(): number {
    return this.objectInspectorMediaDecodeGeneration
  }

  proceduralParticles(): number[][] {
    return this.objectInspectorProceduralParticles
  }

  resetProcedural(): void {
    this.objectInspectorProceduralKey = ''
    this.objectInspectorProceduralParticles = []
  }

  // 选中切换/清空时的请求解析状态复位。
  clearResolutionState(): void {
    this.objectInspectorMediaRequestPath = ''
    this.objectInspectorMediaResolvedRequestPath = ''
    this.objectInspectorMediaResolvedPath = ''
    this.objectInspectorMediaResolutionComplete = false
  }

  private objectInspectorFilePath(relativePath: string): string {
    const path = this.hooks.filesDir() + '/stellarium/' + relativePath
    try {
      return this.mediaPort.fileExists(path) ? path : ''
    } catch (_err) {
      return ''
    }
  }

  clearObjectInspectorDecodedImage(): void {
    const oldPixelMap = this.mediaStore.objectInspectorMediaPixelMap
    this.mediaStore.objectInspectorMediaPixelMap = undefined
    this.objectInspectorMediaDecodeGeneration++
    this.hooks.objectModelRenderer().clearObjectInspectorModelRenderer()
    releaseDecodedImage(this.mediaPort, oldPixelMap, 'object-inspector')
  }

  private updateObjectInspectorMediaWarmup(kind: string): void {
    if (kind !== 'image') {
      this.mediaStore.objectInspectorMediaWarmupState = 'unknown'
      this.mediaStore.objectInspectorMediaWarmupInstalled = 0
      this.mediaStore.objectInspectorMediaWarmupTotal = 0
      this.mediaStore.objectInspectorMediaWarmupFailed = 0
      return
    }
    try {
      const status: DeepSkyWarmupStatus = this.hooks.warmupStatus()
      this.mediaStore.objectInspectorMediaWarmupState = status.state
      this.mediaStore.objectInspectorMediaWarmupInstalled = status.installed
      this.mediaStore.objectInspectorMediaWarmupTotal = status.total
      this.mediaStore.objectInspectorMediaWarmupFailed = status.failed
    } catch (err) {
      this.mediaStore.objectInspectorMediaWarmupState = 'unknown'
      hilog.warn(0x0000, 'StellariumArkUI',
        '[detail-media] unable to read warmup status error=%{public}s', JSON.stringify(err))
    }
  }

  private startObjectInspectorMediaWarmup(): void {
    if (this.objectInspectorMediaWarmupTimer !== 0) {
      return
    }
    this.objectInspectorMediaWarmupTimer = setInterval(() => {
      if (!this.mediaStore.objectInspectorMediaLoading || this.mediaStore.objectInspectorMediaKind !== 'image') {
        this.stopObjectInspectorMediaWarmup()
        return
      }
      this.updateObjectInspectorMediaWarmup('image')
    }, 500) as number
  }

  stopObjectInspectorMediaWarmup(): void {
    if (this.objectInspectorMediaWarmupTimer !== 0) {
      clearInterval(this.objectInspectorMediaWarmupTimer)
      this.objectInspectorMediaWarmupTimer = 0
    }
  }

  // Resolves the detail textures of the seven planets, the Moon and the Sun once
  // the sky has presented its first frame, one body per tick, so opening their
  // cards does not have to copy the packaged texture on demand. This only makes
  // the existing on-select work happen earlier: it never moves the view, never
  // shows a dialog and never blocks the UI thread.
  startBodyDetailWarmup(): void {
    if (this.bodyDetailWarmupTimer !== 0) {
      return
    }
    this.bodyDetailWarmupPending = BODY_DETAIL_TEXTURE_PATHS.slice()
    this.bodyDetailWarmupIndex = 0
    this.stepBodyDetailWarmup()
    this.bodyDetailWarmupTimer = setInterval(() => {
      this.stepBodyDetailWarmup()
    }, 120) as number
  }

  private stepBodyDetailWarmup(): void {
    if (this.bodyDetailWarmupIndex >= this.bodyDetailWarmupPending.length) {
      hilog.info(0x0000, 'StellariumArkUI', '[body-warmup] completed count=%{public}d',
        this.bodyDetailWarmupPending.length)
      this.stopBodyDetailWarmup()
      return
    }
    const relativePath = this.bodyDetailWarmupPending[this.bodyDetailWarmupIndex]
    this.bodyDetailWarmupIndex++
    try {
      this.hooks.resolveDetailMediaAsset(relativePath).then((resolved: string) => {
        if (resolved.length === 0) {
          hilog.warn(0x0000, 'StellariumArkUI', '[body-warmup] unavailable path=%{public}s', relativePath)
        } else {
          hilog.info(0x0000, 'StellariumArkUI', '[body-warmup] ready path=%{public}s', resolved)
        }
      }).catch((err: Error) => {
        hilog.warn(0x0000, 'StellariumArkUI', '[body-warmup] failed path=%{public}s error=%{public}s',
          relativePath, JSON.stringify(err))
      })
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[body-warmup] failed path=%{public}s error=%{public}s',
        relativePath, JSON.stringify(err))
    }
  }

  stopBodyDetailWarmup(): void {
    if (this.bodyDetailWarmupTimer !== 0) {
      clearInterval(this.bodyDetailWarmupTimer)
      this.bodyDetailWarmupTimer = 0
    }
    this.bodyDetailWarmupIndex = 0
    this.bodyDetailWarmupPending = []
  }

  refreshObjectInspectorMedia(): void {
    const planetTexturePath = objectInspectorPlanetTexturePath(this.detailStore.selectedEnglishName)
    const deepSkyImageName = planetTexturePath.length === 0 && this.detailStore.selectedDetailMediaPath.length === 0
      ? objectInspectorDeepSkyImageName(objectInspectorFallbackVisualKind(this.detailStore.selectedObjectType, this.detailStore.selectedType), this.detailStore.objectInspectorSearchText())
      : ''
    const requestedPath = planetTexturePath.length > 0
      ? planetTexturePath
      : (this.detailStore.selectedDetailMediaPath.length > 0
        ? this.detailStore.selectedDetailMediaPath
        : (deepSkyImageName.length > 0 ? 'nebulae/default/' + deepSkyImageName : ''))
    const proceduralKind = requestedPath.length === 0 || (planetTexturePath.length === 0 &&
      this.objectInspectorMediaResolutionComplete && this.objectInspectorMediaResolvedRequestPath === requestedPath &&
      this.objectInspectorMediaResolvedPath.length === 0)
      ? proceduralModelKind(this.detailStore.selectedObjectType + ' ' + this.detailStore.selectedType) : ''
    const proceduralKey = proceduralKind.length > 0
      ? [proceduralKind, this.detailStore.selectedCatalogId, this.detailStore.selectedEnglishName, this.detailStore.selectedTemperatureK.toString()].join('|') : ''
    if (this.objectInspectorMediaResolvedRequestPath !== requestedPath) {
      this.objectInspectorMediaResolvedRequestPath = ''
      this.objectInspectorMediaResolvedPath = ''
      this.objectInspectorMediaResolutionComplete = false
    }
    const resolvedPath = this.objectInspectorMediaResolvedRequestPath === requestedPath &&
      this.objectInspectorMediaResolvedPath.length > 0
      ? this.objectInspectorMediaResolvedPath
      : requestedPath
    const filePath = resolvedPath.length > 0 ? this.objectInspectorFilePath(resolvedPath) : ''
    const path = filePath.length > 0 ? this.hooks.pathToUri(filePath) : ''
    const kind = planetTexturePath.length > 0 || proceduralKind.length > 0
      ? 'model'
      : (this.detailStore.selectedDetailMediaPath.length > 0 ? 'constellation' : (deepSkyImageName.length > 0 ? 'image' : 'visual'))
    const modelRawFilePath = kind === 'model' && resolvedPath.length > 0
      ? this.objectInspectorFilePath(resolvedPath + '.model.rgba')
      : ''
    const ringSpec = kind === 'model' ? objectInspectorPlanetRingSpec(this.detailStore.selectedEnglishName) : undefined
    const ringRawFilePath = ringSpec === undefined
      ? ''
      : this.objectInspectorFilePath(ringSpec.texturePath + '.model.rgba')
    const ringPngFilePath = ringSpec === undefined
      ? ''
      : this.objectInspectorFilePath(ringSpec.texturePath)
    const resolutionAlreadyAttempted = this.objectInspectorMediaResolutionComplete &&
      this.objectInspectorMediaResolvedRequestPath === requestedPath
    const shouldResolve = requestedPath.length > 0 && path.length === 0 && !resolutionAlreadyAttempted
    const mediaKeySame = path === this.mediaStore.objectInspectorMediaPath && kind === this.mediaStore.objectInspectorMediaKind &&
      proceduralKey === this.objectInspectorProceduralKey
    if (mediaKeySame && (this.mediaStore.objectInspectorMediaDecoding || this.hooks.objectModelRenderer().isRendering())) {
      return
    }
    const shouldDecode = path.length > 0 && (kind === 'image' || kind === 'constellation' || kind === 'model') &&
      !(mediaKeySame && this.mediaStore.objectInspectorMediaLoadFailed) &&
      (!mediaKeySame || (kind === 'model'
        ? !this.hooks.objectModelRenderer().hasTexture()
        : this.mediaStore.objectInspectorMediaPixelMap === undefined))
    if (mediaKeySame &&
      this.mediaStore.objectInspectorMediaLoading === (shouldResolve || shouldDecode) &&
      this.mediaStore.objectInspectorMediaDecoding === shouldDecode &&
      (!shouldResolve || this.objectInspectorMediaRequestPath === requestedPath)) { return }
    this.clearObjectInspectorDecodedImage()
    this.mediaStore.objectInspectorMediaPath = path
    this.mediaStore.objectInspectorMediaKind = kind
    this.mediaStore.objectInspectorProceduralKind = proceduralKind
    this.objectInspectorProceduralKey = proceduralKey
    this.objectInspectorProceduralParticles = proceduralParticles(proceduralKind, proceduralKey)
    this.mediaStore.objectInspectorMediaLabel = kind === 'model'
      ? (proceduralKind.length > 0 ? I18n.t('model_schematic') : I18n.t('model_offline'))
      : (kind === 'constellation' ? this.detailStore.selectedDetailMediaLabel : (kind === 'image' ? '离线深空资料图像' : '本地天体类别示意'))
    this.mediaStore.objectInspectorMediaFullscreen = false
    this.mediaStore.objectInspectorMediaPreviewPath = ''
    this.mediaStore.objectInspectorMediaPreviewLoading = false
    this.mediaStore.objectInspectorMediaPreviewFailed = false
    this.mediaStore.objectInspectorModelScale = 1
    this.hooks.objectModelRenderer().resetRotationForNewMedia()
    this.mediaStore.objectInspectorMediaLoading = shouldResolve || shouldDecode
    this.mediaStore.objectInspectorMediaDecoding = shouldDecode
    this.mediaStore.objectInspectorMediaLoadFailed = false
    this.mediaStore.objectInspectorMediaPreparationFailed = false
    this.mediaStore.objectInspectorMediaNoMatch = false
    this.updateObjectInspectorMediaWarmup(kind)
    this.objectInspectorMediaRequestPath = this.mediaStore.objectInspectorMediaLoading ? requestedPath : ''
    if (proceduralKind.length > 0) {
      this.hooks.objectModelRenderer().requestObjectInspectorModelRender(true)
      return
    }
    if (shouldResolve) {
      const expectedSelection = this.detailStore.selectedName + '\n' + this.detailStore.selectedEnglishName + '\n' + this.detailStore.selectedCatalogId
      const expectedRequestPath = requestedPath
      const warmupStatus: DeepSkyWarmupStatus = this.hooks.warmupStatus()
      hilog.info(0x0000, 'StellariumArkUI',
        '[detail-media] warmup state=%{public}s installed=%{public}s total=%{public}s pending=%{public}s failed=%{public}s',
        warmupStatus.state, warmupStatus.installed.toString(), warmupStatus.total.toString(),
        warmupStatus.pending.toString(), warmupStatus.failed.toString())
      this.startObjectInspectorMediaWarmup()
      this.hooks.resolveDetailMediaAsset(requestedPath).then((actualPath: string) => {
        const currentSelection = this.detailStore.selectedName + '\n' + this.detailStore.selectedEnglishName + '\n' + this.detailStore.selectedCatalogId
        if (currentSelection !== expectedSelection || this.objectInspectorMediaRequestPath !== expectedRequestPath) { return }
        this.mediaStore.objectInspectorMediaLoading = false
        this.objectInspectorMediaRequestPath = ''
        this.objectInspectorMediaResolvedRequestPath = expectedRequestPath
        this.objectInspectorMediaResolvedPath = actualPath
        this.objectInspectorMediaResolutionComplete = true
        this.mediaStore.objectInspectorMediaNoMatch = actualPath.length === 0
        this.mediaStore.objectInspectorMediaLoadFailed = false
        this.mediaStore.objectInspectorMediaPreparationFailed = false
        this.stopObjectInspectorMediaWarmup()
        this.updateObjectInspectorMediaWarmup(kind)
        hilog.info(0x0000, 'StellariumArkUI',
          '[detail-media] selection=%{public}s requested=%{public}s resolved=%{public}s',
          this.detailStore.selectedName, expectedRequestPath, actualPath)
        this.refreshObjectInspectorMedia()
      }).catch((err: Error) => {
        const currentSelection = this.detailStore.selectedName + '\n' + this.detailStore.selectedEnglishName + '\n' + this.detailStore.selectedCatalogId
        if (currentSelection !== expectedSelection || this.objectInspectorMediaRequestPath !== expectedRequestPath) { return }
        this.mediaStore.objectInspectorMediaLoading = false
        this.objectInspectorMediaRequestPath = ''
        this.objectInspectorMediaResolutionComplete = true
        this.mediaStore.objectInspectorMediaNoMatch = false
        this.mediaStore.objectInspectorMediaLoadFailed = false
        this.mediaStore.objectInspectorMediaPreparationFailed =
          this.hooks.isPreparationFailed(expectedRequestPath)
        this.stopObjectInspectorMediaWarmup()
        hilog.error(0x0000, 'StellariumArkUI',
          '[detail-media] request failed request=%{public}s error=%{public}s', expectedRequestPath, err.message)
      })
    }
    if (shouldDecode) {
      const expectedSelection = this.detailStore.selectedName + '\n' + this.detailStore.selectedEnglishName + '\n' + this.detailStore.selectedCatalogId
      const expectedPath = path
      const generation = this.objectInspectorMediaDecodeGeneration
      hilog.info(0x0000, 'StellariumArkUI',
        '[detail-media] decoding local image kind=%{public}s uri=%{public}s', kind, expectedPath)
      if (kind === 'model') {
        this.mediaStore.loadObjectInspectorModelRawTexture(modelRawFilePath, ringRawFilePath, generation, expectedSelection, expectedPath,
          filePath, ringPngFilePath)
        return
      }
      decodeLocalImage(this.mediaPort, filePath, kind, (pixelMap: image.PixelMap) => {
        const currentSelection = this.detailStore.selectedName + '\n' + this.detailStore.selectedEnglishName + '\n' + this.detailStore.selectedCatalogId
        if (currentSelection !== expectedSelection || this.mediaStore.objectInspectorMediaPath !== expectedPath ||
          generation !== this.objectInspectorMediaDecodeGeneration) {
          releaseDecodedImage(this.mediaPort, pixelMap, 'stale-object-inspector')
          return
        }
        const oldPixelMap = this.mediaStore.objectInspectorMediaPixelMap
        this.mediaStore.objectInspectorMediaPixelMap = pixelMap
        releaseDecodedImage(this.mediaPort, oldPixelMap, 'previous-object-inspector')
        this.mediaStore.objectInspectorMediaLoading = false
        this.mediaStore.objectInspectorMediaLoadFailed = false
        this.mediaStore.objectInspectorMediaDecoding = false
        if (this.mediaStore.objectInspectorMediaFullscreen) {
          this.mediaStore.objectInspectorMediaPreviewLoading = false
          this.mediaStore.objectInspectorMediaPreviewFailed = false
        }
        hilog.info(0x0000, 'StellariumArkUI',
          '[detail-media] pixel map ready kind=%{public}s uri=%{public}s', kind, expectedPath)
      }, (err: Error) => {
        const currentSelection = this.detailStore.selectedName + '\n' + this.detailStore.selectedEnglishName + '\n' + this.detailStore.selectedCatalogId
        if (currentSelection !== expectedSelection || this.mediaStore.objectInspectorMediaPath !== expectedPath ||
          generation !== this.objectInspectorMediaDecodeGeneration) {
          return
        }
        this.mediaStore.objectInspectorMediaDecoding = false
        this.mediaStore.objectInspectorMediaLoading = false
        this.mediaStore.objectInspectorMediaLoadFailed = true
        if (this.mediaStore.objectInspectorMediaFullscreen) {
          this.mediaStore.objectInspectorMediaPreviewLoading = false
          this.mediaStore.objectInspectorMediaPreviewFailed = true
        }
        hilog.error(0x0000, 'StellariumArkUI',
          '[detail-media] pixel map decode failed kind=%{public}s uri=%{public}s error=%{public}s',
          kind, expectedPath, describeDecodeError(err))
      })
    }
  }

  openObjectInspectorMediaPreview(): void {
    if (this.mediaStore.objectInspectorMediaPath.length === 0) { return }
    this.mediaStore.objectInspectorMediaPreviewLoading = this.mediaStore.objectInspectorMediaPixelMap === undefined && !this.mediaStore.objectInspectorMediaLoadFailed
    this.mediaStore.objectInspectorMediaPreviewFailed = this.mediaStore.objectInspectorMediaLoadFailed
    this.mediaStore.objectInspectorMediaPreviewPath = this.mediaStore.objectInspectorMediaPath
    this.mediaStore.objectInspectorMediaFullscreen = true
    hilog.info(0x0000, 'StellariumArkUI',
      '[detail-media-preview] open kind=%{public}s request=%{public}s resolved=%{public}s uri=%{public}s',
      this.mediaStore.objectInspectorMediaKind, this.objectInspectorMediaResolvedRequestPath,
      this.objectInspectorMediaResolvedPath, this.mediaStore.objectInspectorMediaPath)
  }

  closeObjectInspectorMediaPreview(): void {
    hilog.info(0x0000, 'StellariumArkUI', '[detail-media-preview] close')
    this.mediaStore.objectInspectorMediaFullscreen = false
    this.mediaStore.objectInspectorMediaPreviewPath = ''
    this.mediaStore.objectInspectorMediaPreviewLoading = false
    this.mediaStore.objectInspectorMediaPreviewFailed = false
  }

  retryObjectInspectorMediaPreview(): void {
    this.mediaStore.objectInspectorMediaPreviewFailed = false
    this.mediaStore.objectInspectorMediaPreviewLoading = true
    this.mediaStore.objectInspectorMediaPreviewPath = ''
    hilog.info(0x0000, 'StellariumArkUI', '[detail-media-preview] retry uri=%{public}s', this.mediaStore.objectInspectorMediaPath)
    this.retryObjectInspectorMedia()
  }

  onObjectInspectorMediaPreviewLoaded(): void {
    if (!this.mediaStore.objectInspectorMediaFullscreen) { return }
    this.mediaStore.objectInspectorMediaPreviewLoading = false
    this.mediaStore.objectInspectorMediaPreviewFailed = false
    hilog.info(0x0000, 'StellariumArkUI', '[detail-media-preview] image loaded uri=%{public}s', this.mediaStore.objectInspectorMediaPreviewPath)
  }

  onObjectInspectorMediaPreviewError(): void {
    if (!this.mediaStore.objectInspectorMediaFullscreen) { return }
    this.mediaStore.objectInspectorMediaPreviewLoading = false
    this.mediaStore.objectInspectorMediaPreviewFailed = true
    hilog.error(0x0000, 'StellariumArkUI', '[detail-media-preview] image failed uri=%{public}s', this.mediaStore.objectInspectorMediaPreviewPath)
  }

  retryObjectInspectorMedia(): void {
    const retryPath = this.objectInspectorMediaResolvedRequestPath.length > 0
      ? this.objectInspectorMediaResolvedRequestPath
      : this.objectInspectorMediaRequestPath
    hilog.info(0x0000, 'StellariumArkUI',
      '[detail-media] retry request=%{public}s resolved=%{public}s', retryPath, this.objectInspectorMediaResolvedPath)
    this.clearObjectInspectorDecodedImage()
    this.mediaStore.objectInspectorMediaPath = ''
    this.objectInspectorMediaResolvedPath = ''
    this.objectInspectorMediaResolvedRequestPath = ''
    this.objectInspectorMediaResolutionComplete = false
    this.objectInspectorMediaRequestPath = ''
    this.mediaStore.objectInspectorMediaLoading = false
    this.mediaStore.objectInspectorMediaDecoding = false
    this.mediaStore.objectInspectorMediaLoadFailed = false
    this.mediaStore.objectInspectorMediaPreparationFailed = false
    this.mediaStore.objectInspectorMediaNoMatch = false
    this.refreshObjectInspectorMedia()
  }
}
