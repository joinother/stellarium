// 星空文化制作器行为控制器：负责制作器草稿的加载/保存/校验/重置/撤销、星座与连线的增删、
// 配图（artwork）的导入/移除/锚点绑定与预览解码，以及制作器工程的导入导出。
// 依赖 CommandPort（制作器桥命令）、MediaPort（picker/fileIo、图片解码）、
// SkyCultureMakerStore（向导状态，面板 @ObjectLink 消费）；filesDir 经 hooks 回注。
// 自动保存定时器（650ms 去抖）与画布触摸草稿为瞬态数据，由本控制器自持。
import hilog from '@ohos.hilog'
import { image } from '@kit.ImageKit'
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { SkyCultureMakerConstellation, SkyCultureMakerDraft, ImageDecodeSize } from '../pages/MainWindowModels'
import { CommandPort } from '../bridge/CommandPort'
import { DocumentImportPort, ImagePort } from '../bridge/MediaPort'
import { decodeLocalImage, releaseDecodedImage } from '../common/media/ImageDecoder'
import { validationFromResponse } from '../common/derive/actions'
import { clamp } from '../common/derive/astro'
import { SkyCultureMakerStore } from '../state/SkyCultureMakerStore'
import { BehaviorHostHooks } from './ControllerHooks'

// 本控制器的最小依赖组合：图像解码/存在性（fileExists / decodeLocalImage / releaseDecodedImage）
// + 文档导入（pickDocumentToDirNamed）。ArkTS 禁交叉类型，故用本地接口显式组合两个子接口。
interface SkyCultureMakerMediaPort extends ImagePort, DocumentImportPort {}

export interface SkyCultureMakerHostHooks extends BehaviorHostHooks {
  // 应用 filesDir（宿主 getUIContext().getHostContext() 派生；控制器不 import UI 上下文）。
  stellariumFilesDir(): string
}

export class SkyCultureMakerController {
  private port: CommandPort
  private mediaPort: SkyCultureMakerMediaPort
  private store: SkyCultureMakerStore
  private hooks: SkyCultureMakerHostHooks

  // —— 私有字段：瞬态/草稿字段留控制器，不入被观察 store ——
  private skyCultureMakerArtworkPreviewPath: string = ''
  private skyCultureMakerArtworkDecodeGeneration: number = 0
  private skyCultureMakerArtworkTouchStartX: number = 0
  private skyCultureMakerArtworkTouchStartY: number = 0
  private skyCultureMakerArtworkTouchMoved: boolean = false
  // 自动保存去抖定时器（650ms）。
  private skyCultureMakerSaveTimer: number = 0

  constructor(
    port: CommandPort,
    mediaPort: SkyCultureMakerMediaPort,
    store: SkyCultureMakerStore,
    hooks: SkyCultureMakerHostHooks
  ) {
    this.port = port
    this.mediaPort = mediaPort
    this.store = store
    this.hooks = hooks
  }

  // JSON 桥回包 → 草稿（一次 JSON cast，JSON 例外）。
  skyCultureMakerDraftFromResponse(response: StellariumBridgeResponse): SkyCultureMakerDraft | undefined {
    const values = response as Record<string, Object>
    if (values['draft'] === undefined) return undefined
    try {
      return JSON.parse(JSON.stringify(values['draft'])) as SkyCultureMakerDraft
    } catch (error) {
      hilog.error(0x0000, 'StellariumArkUI', 'Sky culture maker draft decode failed: %{public}s', String(error))
      return undefined
    }
  }

  // 把草稿写回 store 并刷新配图预览。
  applySkyCultureMakerDraft(draft: SkyCultureMakerDraft): void {
    this.store.id = draft.id ?? ''
    this.store.name = draft.name ?? ''
    this.store.author = draft.author ?? ''
    this.store.license = draft.license ?? 'CC BY 4.0'
    this.store.region = draft.region ?? ''
    this.store.classification = draft.classification !== undefined && draft.classification.length > 0
      ? draft.classification[0] : 'traditional'
    this.store.nativeLang = draft.native_lang ?? 'zh_CN'
    this.store.beginTime = (draft.beginTime ?? 0).toString()
    this.store.endTime = (draft.endTime ?? 0).toString()
    this.store.introduction = draft.introduction ?? ''
    this.store.description = draft.description ?? ''
    this.store.constellations = draft.constellations ?? []
    this.store.draftReady = true
    if (this.store.constellations.length > 0 && this.store.selectedConstellation < 0) {
      this.store.selectedConstellation = 0
    } else if (this.store.selectedConstellation >= this.store.constellations.length) {
      this.store.selectedConstellation = this.store.constellations.length - 1
    }
    this.refreshSkyCultureMakerArtworkPreview()
  }

  // 650ms 去抖自动保存。
  scheduleSkyCultureMakerSave(): void {
    if (!this.store.draftReady) return
    if (this.skyCultureMakerSaveTimer > 0) clearTimeout(this.skyCultureMakerSaveTimer)
    this.skyCultureMakerSaveTimer = setTimeout(() => {
      this.skyCultureMakerSaveTimer = 0
      this.saveSkyCultureMakerDraft(true)
    }, 650) as number
  }

  // 定时器收口：清除在途 650ms 去抖并立即保存（宿主 aboutToDisappear 调用）。
  flushSkyCultureMakerSave(): void {
    if (this.skyCultureMakerSaveTimer > 0) {
      clearTimeout(this.skyCultureMakerSaveTimer)
      this.skyCultureMakerSaveTimer = 0
      this.saveSkyCultureMakerDraft(true)
    }
  }

  saveSkyCultureMakerDraft(silent: boolean = false, onComplete?: (success: boolean) => void): void {
    if (!this.store.draftReady) {
      if (!silent) this.store.status = I18n.t('sky_culture_maker_load_failed')
      if (onComplete !== undefined) onComplete(false)
      return
    }
    if (this.store.saving) {
      if (onComplete !== undefined) onComplete(false)
      return
    }
    this.store.saving = true
    this.port.requestInteractive('saveSkyCultureMakerDraft', JSON.stringify(this.store.currentSkyCultureMakerDraft()), (response: StellariumBridgeResponse) => {
      this.store.saving = false
      if (response.ok !== true) {
        this.store.status = response.error ?? I18n.t('sky_culture_maker_save_failed')
        if (onComplete !== undefined) onComplete(false)
        return
      }
      this.store.canUndo = true
      this.store.validation = validationFromResponse(response)
      if (!silent) this.store.status = I18n.t('sky_culture_maker_saved')
      if (onComplete !== undefined) onComplete(true)
    }, () => {
      this.store.saving = false
      this.store.status = I18n.t('sky_culture_maker_save_failed')
      if (onComplete !== undefined) onComplete(false)
    })
  }

  validateSkyCultureMaker(): void {
    this.port.requestInteractive('validateSkyCultureMakerDraft', JSON.stringify(this.store.currentSkyCultureMakerDraft()), (response: StellariumBridgeResponse) => {
      this.store.validation = validationFromResponse(response)
      this.store.status = response.ok === true
        ? I18n.t('sky_culture_maker_valid')
        : I18n.t('sky_culture_maker_invalid')
      this.store.tab = 2
    }, () => { this.store.status = I18n.t('sky_culture_maker_validate_failed') })
  }

  resetSkyCultureMaker(): void {
    this.port.requestInteractive('resetSkyCultureMakerDraft', '', (response: StellariumBridgeResponse) => {
      const draft = this.skyCultureMakerDraftFromResponse(response)
      if (response.ok === true && draft !== undefined) {
        this.applySkyCultureMakerDraft(draft)
        this.store.validation = undefined
        this.store.canUndo = true
        this.store.status = I18n.t('sky_culture_maker_reset_done')
      } else this.store.status = response.error ?? I18n.t('sky_culture_maker_reset_failed')
    })
  }

  undoSkyCultureMaker(): void {
    this.port.requestInteractive('undoSkyCultureMakerEdit', '', (response: StellariumBridgeResponse) => {
      const draft = this.skyCultureMakerDraftFromResponse(response)
      if (response.ok === true && draft !== undefined) {
        this.applySkyCultureMakerDraft(draft)
        const values = response as Record<string, Object>
        this.store.canUndo = values['canUndo'] === true
        this.store.status = I18n.t('sky_culture_maker_undo_done')
      } else this.store.status = response.error ?? I18n.t('sky_culture_maker_undo_empty')
    })
  }

  addSkyCultureMakerConstellation(): void {
    let number = this.store.constellations.length + 1
    let id = 'constellation_' + number.toString()
    while (this.store.constellations.some((item: SkyCultureMakerConstellation) => item.id === id)) {
      number += 1
      id = 'constellation_' + number.toString()
    }
    const constellation: SkyCultureMakerConstellation = {
      id: id,
      english: '',
      native: '',
      pronounce: '',
      transliteration: '',
      IPA: '',
      dark: false,
      lines: []
    }
    this.store.constellations = this.store.constellations.concat([constellation])
    this.store.selectedConstellation = this.store.constellations.length - 1
    this.refreshSkyCultureMakerArtworkPreview()
    this.scheduleSkyCultureMakerSave()
  }

  updateSkyCultureMakerConstellation(updated: SkyCultureMakerConstellation): void {
    const index = this.store.selectedConstellation
    if (index < 0 || index >= this.store.constellations.length) return
    this.store.constellations = this.store.constellations.map((item: SkyCultureMakerConstellation, itemIndex: number) => {
      return itemIndex === index ? updated : item
    })
    this.scheduleSkyCultureMakerSave()
  }

  removeSelectedSkyCultureMakerConstellation(): void {
    const index = this.store.selectedConstellation
    if (index < 0 || index >= this.store.constellations.length) return
    this.store.constellations = this.store.constellations.filter((_item: SkyCultureMakerConstellation, itemIndex: number) => itemIndex !== index)
    this.store.selectedConstellation = Math.min(index, this.store.constellations.length - 1)
    this.refreshSkyCultureMakerArtworkPreview()
    this.scheduleSkyCultureMakerSave()
  }

  addSkyCultureMakerHipLine(): void {
    const index = this.store.selectedConstellation
    if (index < 0 || index >= this.store.constellations.length) return
    const parts = this.store.hipLine.trim().split(/[\s,;，；]+/)
    const hips: number[] = []
    for (const part of parts) {
      const value = Number(part.replace(/^HIP/i, ''))
      if (Number.isInteger(value) && value > 0) hips.push(value)
    }
    if (hips.length < 2) {
      this.store.status = I18n.t('sky_culture_maker_line_needs_two')
      return
    }
    const constellation = this.store.constellations[index]
    this.updateSkyCultureMakerConstellation({
      id: constellation.id,
      english: constellation.english,
      native: constellation.native,
      pronounce: constellation.pronounce,
      transliteration: constellation.transliteration,
      IPA: constellation.IPA,
      dark: constellation.dark,
      lines: constellation.lines.concat([hips]),
      image: constellation.image
    })
    this.store.hipLine = ''
    this.store.status = I18n.t('sky_culture_maker_line_added')
  }

  removeSkyCultureMakerLine(lineIndex: number): void {
    const index = this.store.selectedConstellation
    if (index < 0 || index >= this.store.constellations.length) return
    const constellation = this.store.constellations[index]
    this.updateSkyCultureMakerConstellation({
      id: constellation.id,
      english: constellation.english,
      native: constellation.native,
      pronounce: constellation.pronounce,
      transliteration: constellation.transliteration,
      IPA: constellation.IPA,
      dark: constellation.dark,
      lines: constellation.lines.filter((_line: number[], index: number) => index !== lineIndex),
      image: constellation.image
    })
  }

  addSelectedStarToSkyCultureMaker(): void {
    const index = this.store.selectedConstellation
    if (index < 0 || index >= this.store.constellations.length) return
    const constellation = this.store.constellations[index]
    const lineIndex = constellation.lines.length > 0 ? constellation.lines.length - 1 : -1
    this.saveSkyCultureMakerDraft(true, (saved: boolean) => {
      if (!saved) return
      this.port.requestInteractive('addSkyCultureMakerSelectedStar', JSON.stringify({ constellationId: constellation.id, lineIndex: lineIndex }), (response: StellariumBridgeResponse) => {
        const draft = this.skyCultureMakerDraftFromResponse(response)
        if (response.ok === true && draft !== undefined) {
          this.applySkyCultureMakerDraft(draft)
          this.store.status = I18n.t('sky_culture_maker_selected_star_added')
        } else this.store.status = response.error ?? I18n.t('sky_culture_maker_selected_star_failed')
      })
    })
  }

  skyCultureMakerArtworkFilePath(): string {
    const constellation = this.store.selected()
    const assetFile = constellation?.image?.file ?? ''
    if (assetFile.length === 0 || assetFile.startsWith('/') || assetFile.includes('..')) return ''
    const filePath = this.hooks.stellariumFilesDir() + '/stellarium_userdir/sky-culture-maker/assets/' + assetFile
    return this.mediaPort.fileExists(filePath) ? filePath : ''
  }

  clearSkyCultureMakerArtworkPreview(label: string = 'sky-culture-maker-artwork'): void {
    this.skyCultureMakerArtworkDecodeGeneration++
    this.skyCultureMakerArtworkPreviewPath = ''
    this.store.artworkPreviewState = 'empty'
    const oldPixelMap = this.store.artworkPixelMap
    this.store.artworkPixelMap = undefined
    releaseDecodedImage(this.mediaPort, oldPixelMap, label)
  }

  refreshSkyCultureMakerArtworkPreview(): void {
    const artwork = this.store.selected()?.image
    if (artwork === undefined) {
      this.clearSkyCultureMakerArtworkPreview()
      return
    }
    const filePath = this.skyCultureMakerArtworkFilePath()
    if (filePath.length === 0) {
      this.clearSkyCultureMakerArtworkPreview()
      this.store.artworkPreviewState = 'missing'
      hilog.warn(0x0000, 'StellariumArkUI', '[sky-culture-maker] artwork file missing')
      return
    }
    if (this.skyCultureMakerArtworkPreviewPath === filePath &&
      (this.store.artworkPreviewState === 'preparing' || this.store.artworkPixelMap !== undefined)) {
      return
    }
    const generation = ++this.skyCultureMakerArtworkDecodeGeneration
    const oldPixelMap = this.store.artworkPixelMap
    this.store.artworkPixelMap = undefined
    releaseDecodedImage(this.mediaPort, oldPixelMap, 'previous-sky-culture-maker-artwork')
    this.skyCultureMakerArtworkPreviewPath = filePath
    this.store.artworkPreviewState = 'preparing'
    const sourceWidth = Math.max(1, artwork.size?.[0] ?? 1)
    const sourceHeight = Math.max(1, artwork.size?.[1] ?? 1)
    const scale = Math.min(1, 1280 / Math.max(sourceWidth, sourceHeight))
    const desiredSize: ImageDecodeSize = {
      width: Math.max(1, Math.round(sourceWidth * scale)),
      height: Math.max(1, Math.round(sourceHeight * scale))
    }
    decodeLocalImage(this.mediaPort, filePath, 'sky-culture-maker-artwork', (pixelMap: image.PixelMap) => {
      if (generation !== this.skyCultureMakerArtworkDecodeGeneration || this.skyCultureMakerArtworkPreviewPath !== filePath) {
        releaseDecodedImage(this.mediaPort, pixelMap, 'stale-sky-culture-maker-artwork')
        return
      }
      this.store.artworkPixelMap = pixelMap
      this.store.artworkPreviewState = 'ready'
      hilog.info(0x0000, 'StellariumArkUI', '[sky-culture-maker] artwork ready path=%{public}s', filePath)
    }, (error: Error) => {
      if (generation !== this.skyCultureMakerArtworkDecodeGeneration || this.skyCultureMakerArtworkPreviewPath !== filePath) return
      this.store.artworkPreviewState = 'decodeFailed'
      hilog.error(0x0000, 'StellariumArkUI', '[sky-culture-maker] artwork decode failed path=%{public}s error=%{public}s',
        filePath, JSON.stringify(error))
    }, desiredSize)
  }

  selectSkyCultureMakerConstellation(index: number): void {
    if (index < 0 || index >= this.store.constellations.length || index === this.store.selectedConstellation) return
    this.store.selectedConstellation = index
    this.store.artworkAnchorIndex = 0
    this.refreshSkyCultureMakerArtworkPreview()
  }

  applySkyCultureMakerArtworkResponse(response: StellariumBridgeResponse, successText: string): void {
    const draft = this.skyCultureMakerDraftFromResponse(response)
    if (response.ok === true && draft !== undefined) {
      this.applySkyCultureMakerDraft(draft)
      this.store.canUndo = true
      this.store.validation = validationFromResponse(response)
      this.store.status = successText
    } else {
      this.store.status = response.error ?? I18n.t('sky_culture_maker_artwork_failed')
    }
  }

  // picker 选图 → 复制到导入目录 → 桥导入（picker/fileIo 经 MediaPort.pickDocumentToDirNamed）。
  async importSkyCultureMakerArtworkFile(): Promise<void> {
    const constellation = this.store.selected()
    if (constellation === undefined || this.store.artworkImporting) return
    this.store.artworkImporting = true
    try {
      const result = await this.mediaPort.pickDocumentToDirNamed(
        'sky-culture-maker-imports',
        ['图像|.png|.jpg|.jpeg|.webp'],
        (sourceName: string): string => {
          const fileName = sourceName.length > 0 ? sourceName : 'artwork-' + Date.now().toString() + '.png'
          return Date.now().toString() + '-' + fileName
        })
      if (result.cancelled) {
        this.store.artworkImporting = false
        return
      }
      this.port.requestInteractive('importSkyCultureMakerArtwork', JSON.stringify({
        constellationId: constellation.id,
        sourcePath: result.path
      }), (response: StellariumBridgeResponse) => {
        this.store.artworkImporting = false
        this.store.artworkAnchorIndex = 0
        this.applySkyCultureMakerArtworkResponse(response, I18n.t('sky_culture_maker_artwork_imported'))
      }, () => {
        this.store.artworkImporting = false
        this.store.status = I18n.t('sky_culture_maker_artwork_failed')
      })
    } catch (error) {
      this.store.artworkImporting = false
      this.store.status = I18n.t('sky_culture_maker_artwork_failed')
      hilog.error(0x0000, 'StellariumArkUI', 'Sky culture artwork import failed: %{public}s', String(error))
    }
  }

  removeSkyCultureMakerArtwork(): void {
    const constellation = this.store.selected()
    if (constellation === undefined) return
    this.port.requestInteractive('removeSkyCultureMakerArtwork', JSON.stringify({ constellationId: constellation.id }), (response: StellariumBridgeResponse) => {
      this.store.artworkAnchorIndex = 0
      this.applySkyCultureMakerArtworkResponse(response, I18n.t('sky_culture_maker_artwork_removed'))
    })
  }

  bindSkyCultureMakerArtworkAnchor(x: number, y: number): void {
    const constellation = this.store.selected()
    const image = constellation?.image
    if (constellation === undefined || image === undefined || image.size.length !== 2) return
    const pixelX = clamp(x / Math.max(1, this.store.artworkRenderWidth) * image.size[0], 0, image.size[0])
    const pixelY = clamp(y / Math.max(1, this.store.artworkRenderHeight) * image.size[1], 0, image.size[1])
    this.port.requestInteractive('setSkyCultureMakerArtworkAnchor', JSON.stringify({
      constellationId: constellation.id,
      anchorIndex: this.store.artworkAnchorIndex,
      x: pixelX,
      y: pixelY
    }), (response: StellariumBridgeResponse) => {
      this.applySkyCultureMakerArtworkResponse(response, I18n.format('sky_culture_maker_anchor_bound', [(this.store.artworkAnchorIndex + 1).toString()]))
      if (response.ok === true && this.store.artworkAnchorIndex < 2) this.store.artworkAnchorIndex += 1
    })
  }

  handleSkyCultureMakerArtworkTouch(event: TouchEvent): boolean {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) return false
    const point = points[0]
    if (event.type === TouchType.Down) {
      this.skyCultureMakerArtworkTouchStartX = point.x
      this.skyCultureMakerArtworkTouchStartY = point.y
      this.skyCultureMakerArtworkTouchMoved = false
    } else if (event.type === TouchType.Move) {
      const deltaX = point.x - this.skyCultureMakerArtworkTouchStartX
      const deltaY = point.y - this.skyCultureMakerArtworkTouchStartY
      if (Math.sqrt(deltaX * deltaX + deltaY * deltaY) > 8) this.skyCultureMakerArtworkTouchMoved = true
    } else if (event.type === TouchType.Up) {
      if (!this.skyCultureMakerArtworkTouchMoved) this.bindSkyCultureMakerArtworkAnchor(point.x, point.y)
      this.skyCultureMakerArtworkTouchMoved = false
    } else if (event.type === TouchType.Cancel) {
      this.skyCultureMakerArtworkTouchMoved = false
    }
    return false
  }

  exportSkyCultureMaker(): void {
    this.saveSkyCultureMakerDraft(true, (saved: boolean) => {
      if (!saved) return
      this.port.requestInteractive('exportSkyCultureMaker', '', (response: StellariumBridgeResponse) => {
        this.store.validation = validationFromResponse(response)
        const values = response as Record<string, Object>
        if (response.ok === true) {
          this.store.exportPath = values['path'] as string
          this.store.exportFileName = values['fileName'] as string
          this.store.status = I18n.t('sky_culture_maker_exported')
        } else this.store.status = response.error ?? I18n.t('sky_culture_maker_export_failed')
        this.store.tab = 2
      })
    })
  }

  // picker 选 .zip → 复制到导入目录 → 桥导入。
  async importSkyCultureMakerFile(): Promise<void> {
    try {
      const result = await this.mediaPort.pickDocumentToDirNamed(
        'sky-culture-maker-imports',
        ['Stellarium 星空文化|.zip'],
        (): string => 'culture-' + Date.now().toString() + '.zip')
      if (result.cancelled) return
      this.port.requestInteractive('importSkyCultureMaker', result.path, (response: StellariumBridgeResponse) => {
        const draft = this.skyCultureMakerDraftFromResponse(response)
        if (response.ok === true && draft !== undefined) {
          this.applySkyCultureMakerDraft(draft)
          this.store.validation = undefined
          this.store.canUndo = true
          this.store.status = I18n.t('sky_culture_maker_imported')
        } else this.store.status = response.error ?? I18n.t('sky_culture_maker_import_failed')
      })
    } catch (error) {
      hilog.error(0x0000, 'StellariumArkUI', 'Sky culture maker import failed: %{public}s', String(error))
      this.store.status = I18n.t('sky_culture_maker_import_failed')
    }
  }
}
