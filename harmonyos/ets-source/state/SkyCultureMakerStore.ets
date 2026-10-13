import { image } from '@kit.ImageKit'
import { I18n } from '../pages/I18n'
import { SkyCultureMakerArtworkAnchor, SkyCultureMakerConstellation, SkyCultureMakerDraft, SkyCultureMakerValidation } from '../pages/MainWindowModels'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → SkyCultureMakerStore 的加载助手。
// 三者均为宿主内被多个动作方法共用的实现（applySkyCultureMakerDraft 亦被保存/校验/重置/撤销等
// 回包消费，skyCultureMakerDraftFromResponse 亦然，ensurePluginLoaded 为宿主通用插件加载器），
// 故留宿主并经具名 hooks 回注（store 不 import 桥/插件管理层）。
export interface SkyCultureMakerHostHooks {
  applySkyCultureMakerDraft(draft: SkyCultureMakerDraft): void
  ensurePluginLoaded(pluginName: string, callback: () => void, failureCallback?: () => void): void
  skyCultureMakerDraftFromResponse(response: StellariumBridgeResponse): SkyCultureMakerDraft | undefined
}

// 星文化制作器（activePanel === 'skyCultureMaker'）向导 store：持有向导骨架、元数据、星座编辑、
// 校验/导出与配图角点状态，由 panels/skyculture/ 下组件经 @ObjectLink 观察；桥经 attachPort
// 注入 CommandPort，本 store 自持 loadSkyCultureMakerDraft。native 桥动作、自动保存定时器、
// 图片解码与手势瞬态仍留宿主（只放数据与纯计算，不 import UI / NAPI，image 仅用于 PixelMap 类型）。
@Observed
export class SkyCultureMakerStore {
  // —— 向导骨架与反馈 ——
  tab: number = 0
  loading: boolean = false
  draftReady: boolean = false
  saving: boolean = false
  status: string = ''
  canUndo: boolean = false

  // —— 元数据字段 ——
  id: string = ''
  name: string = ''
  author: string = ''
  license: string = 'CC BY 4.0'
  region: string = ''
  classification: string = 'traditional'
  nativeLang: string = 'zh_CN'
  beginTime: string = '0'
  endTime: string = '0'
  introduction: string = ''
  description: string = ''

  // —— 星座编辑 ——
  constellations: SkyCultureMakerConstellation[] = []
  selectedConstellation: number = -1
  hipLine: string = ''

  // —— 校验与导出 ——
  validation: SkyCultureMakerValidation | undefined = undefined
  exportPath: string = ''
  exportFileName: string = ''

  // —— 星座配图（角点绑定）——
  artworkImporting: boolean = false
  artworkAnchorIndex: number = 0
  artworkRenderWidth: number = 1
  artworkRenderHeight: number = 1
  artworkPixelMap: image.PixelMap | undefined = undefined
  artworkPreviewState: string = 'empty'

  // —— 桥 / 宿主助手注入 ——
  private port: CommandPort | null = null
  // 本加载器无并发抑制序号；使用启动期重试 0/100/150。seq 预留未用。
  private seq: number = 0
  private onChanged: (() => void) | null = null
  private hooks: SkyCultureMakerHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  attachHooks(hooks: SkyCultureMakerHostHooks): void {
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // —— 纯派生/纯变换（无桥、无定时器、无解码）——

  selected(): SkyCultureMakerConstellation | undefined {
    const index = this.selectedConstellation
    if (index < 0 || index >= this.constellations.length) return undefined
    return this.constellations[index]
  }

  updateConstellation(updated: SkyCultureMakerConstellation): void {
    const index = this.selectedConstellation
    if (index < 0 || index >= this.constellations.length) return
    this.constellations = this.constellations.map((item: SkyCultureMakerConstellation, itemIndex: number) => {
      return itemIndex === index ? updated : item
    })
  }

  artworkAnchor(index: number): SkyCultureMakerArtworkAnchor | undefined {
    const anchors = this.selected()?.image?.anchors ?? []
    return index >= 0 && index < anchors.length ? anchors[index] : undefined
  }

  artworkAnchorHipText(index: number): string {
    const hip = this.artworkAnchor(index)?.hip ?? 0
    return hip > 0 ? hip.toString() : '--'
  }

  artworkPreviewHeight(panelWidth: number): number {
    const artwork = this.selected()?.image
    const width = artwork?.size?.[0] ?? 1
    const height = artwork?.size?.[1] ?? 1
    const availableWidth = Math.max(220, panelWidth - 48)
    return Math.min(228, Math.max(128, availableWidth * height / Math.max(1, width)))
  }

  artworkAnchorX(index: number): number {
    const artwork = this.selected()?.image
    const anchor = this.artworkAnchor(index)
    if (artwork === undefined || anchor === undefined || artwork.size.length !== 2 || anchor.pos.length !== 2) return -20
    return anchor.pos[0] / Math.max(1, artwork.size[0]) * this.artworkRenderWidth - 12
  }

  artworkAnchorY(index: number): number {
    const artwork = this.selected()?.image
    const anchor = this.artworkAnchor(index)
    if (artwork === undefined || anchor === undefined || artwork.size.length !== 2 || anchor.pos.length !== 2) return -20
    return anchor.pos[1] / Math.max(1, artwork.size[1]) * this.artworkRenderHeight - 12
  }

  issueText(code: string, fallback: string): string {
    const key = 'sky_culture_maker_issue_' + code
    const localized = I18n.t(key)
    return localized === key ? fallback : localized
  }

  // 星文化制作器：桥读草稿并落状态；草稿解析 / 应用 / 插件加载经 hooks，重试档 0/100/150。
  loadSkyCultureMakerDraft(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const hooks = this.hooks
    if (hooks === null) {
      return
    }
    if (this.loading) return
    this.loading = true
    this.draftReady = false
    port.requestWhenReady('getSkyCultureMakerDraft', '', (response: StellariumBridgeResponse) => {
      this.loading = false
      const draft = hooks.skyCultureMakerDraftFromResponse(response)
      if (response.ok !== true || draft === undefined) {
        this.status = response.error ?? I18n.t('sky_culture_maker_load_failed')
        return
      }
      hooks.applySkyCultureMakerDraft(draft)
      const values = response as Record<string, Object>
      this.canUndo = values['canUndo'] === true
      this.status = ''
      hooks.ensurePluginLoaded('SkyCultureMaker', () => {})
    }, () => {
      this.loading = false
      this.status = I18n.t('sky_culture_maker_load_failed')
    }, 0, 100, 150)
  }

  // 由当前 store 字段装配草稿。
  currentSkyCultureMakerDraft(): SkyCultureMakerDraft {
    let beginTime = Number(this.beginTime)
    let endTime = Number(this.endTime)
    if (!Number.isFinite(beginTime)) beginTime = 0
    if (!Number.isFinite(endTime)) endTime = 0
    return {
      schemaVersion: 1,
      id: this.id.trim(),
      name: this.name.trim(),
      author: this.author.trim(),
      license: this.license.trim(),
      region: this.region.trim(),
      classification: [this.classification],
      native_lang: this.nativeLang.trim(),
      beginTime: Math.trunc(beginTime),
      endTime: Math.trunc(endTime),
      introduction: this.introduction,
      description: this.description,
      constellations: this.constellations
    }
  }
}
