import { image } from '@kit.ImageKit'
import { SkyCultureArtItem, SkyCultureDescriptionBlock, SkyCultureItem, SkyCultureRawItem, StellariumBridgeResponse } from '../pages/StellariumTypes'
import { cleanSkyCultureNarration } from '../common/derive/skycult'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → SkyCultureViewStore 的加载助手。
// 二者均指向宿主自持的详情加载器 loadSkyCultureDetails（写留在宿主的渐进解码字段），
// 本 store 只经 hooks 调用。
export interface SkyCultureViewHostHooks {
  // 使宿主内 in-flight 的详情请求失效（该序号与多个宿主动作共用，仍归宿主）。
  invalidateSkyCultureDetails(): void
  // 触发宿主详情加载器。
  loadSkyCultureDetails(): void
}

// 「星空文化」面板只读详情视图 store：持有详情加载三态、解说/描述、离线艺术图列表、预览弹层
// 标记、单张大图解码结果与文化列表/当前选择，由 LayersPanel / SkyCultureViewTab 等经
// @ObjectLink 观察。桥经 attachPort 注入 CommandPort，本 store 自持 loadSkyCultureList；
// 详情加载与失效经 hooks 回注。
//
// 只放数据与纯计算，不 import UI / NAPI（image 仅用于 PixelMap 类型）。分张解码的
// skyCultureArtStates / skyCultureArtThumbnailPixelMaps 因高频渐进写入留宿主；
// 单张大图 artPreviewPixelMap 每张只写一次，且叠层必须以引用语义拿到 PixelMap——
// @Prop 会拷贝 PixelMap，真机实测导致 Image.onError，故收进本 store。
@Observed
export class SkyCultureViewStore {
  // —— 详情加载三态 ——
  detailsLoading: boolean = false
  detailsReady: boolean = false
  pendingId: string = ''
  detailError: string = ''

  // —— 解说与描述 ——
  narration: string = ''
  description: string = ''
  descriptionBlocks: Array<SkyCultureDescriptionBlock> = []
  narrationExpanded: boolean = false
  descriptionExpanded: boolean = false

  // —— 离线艺术图列表 ——
  artItems: Array<SkyCultureArtItem> = []
  artExpanded: boolean = false

  // —— 艺术图预览弹层标记与解码结果 ——
  artPreviewOpen: boolean = false
  artPreviewPath: string = ''
  artPreviewName: string = ''
  artPreviewRawPath: string = ''
  artPreviewLoading: boolean = false
  artPreviewFailed: boolean = false
  // 单张大图解码结果：由解码回调渐进写入（每张只写一次），以 @ObjectLink 引用语义供叠层组件渲染。
  artPreviewPixelMap: image.PixelMap | undefined = undefined

  // —— 文化列表与当前选择 ——
  skyCultures: string[] = []
  skyCultureList: Array<SkyCultureItem> = []
  skyCultureListLoading: boolean = false
  currentSkyCulture: string = ''
  currentSkyCultureId: string = ''

  // —— 桥 / 宿主助手注入 ——
  private port: CommandPort | null = null
  // 列表请求序号：用于丢弃过期回包。
  private seq: number = 0
  private onChanged: (() => void) | null = null
  private hooks: SkyCultureViewHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  attachHooks(hooks: SkyCultureViewHostHooks): void {
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

  // 星空文化列表：桥读文化清单并触发详情加载；回包以请求序号比对丢弃过期结果。
  loadSkyCultureList(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const hooks = this.hooks
    if (hooks === null) {
      return
    }
    const requestId = ++this.seq
    hooks.invalidateSkyCultureDetails()
    this.pendingId = ''
    this.skyCultureListLoading = true
    port.requestInteractive('getSkyCultureList', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.seq) return
      if (r.ok === true && r.items !== undefined && Array.isArray(r.items)) {
        const arr = r.items as Array<SkyCultureRawItem>
        const list: Array<SkyCultureItem> = []
        for (let i = 0; i < arr.length; i++) {
          const obj: SkyCultureRawItem = arr[i]
          const id = obj.id !== undefined ? obj.id : ''
          const name = obj.name !== undefined ? obj.name : id
          const regions: string[] = obj.region !== undefined ? obj.region : []
          list.push({
            id: id,
            name: name,
            region: regions,
            classification: obj.classification !== undefined ? obj.classification : '',
            beginTime: obj.beginTime !== undefined ? obj.beginTime : 0,
            endTime: obj.endTime !== undefined ? obj.endTime : 0,
            constellationCount: obj.constellationCount !== undefined ? obj.constellationCount : 0,
            asterismCount: obj.asterismCount !== undefined ? obj.asterismCount : 0,
            nativeNameCount: obj.nativeNameCount !== undefined ? obj.nativeNameCount : 0,
            artCount: obj.artCount !== undefined ? obj.artCount : 0,
            hasZodiac: obj.hasZodiac === true,
            hasLunarSystem: obj.hasLunarSystem === true,
          });
        }
        this.skyCultureList = list;
        if (r.current !== undefined) {
          this.currentSkyCultureId = r.current as string;
        }
        hooks.loadSkyCultureDetails()
      }
      this.skyCultureListLoading = false
    }, () => {
      if (requestId !== this.seq) return
      this.skyCultureListLoading = false
    })
  }

  // 文化解说段落：读本 store 的 narration，经 cleanSkyCultureNarration 清洗拆分。
  skyCultureNarrationParagraphs(): string[] {
    return cleanSkyCultureNarration(this.narration).split(/\n+/).map((item: string) => item.trim()).filter((item: string) => item.length > 0)
  }
}
