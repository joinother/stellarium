import { PluginItem, StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 插件管理（设置 > 插件管理）列表域状态：持有 pluginList 与 pluginListLoading。
// 宿主持有实例，SettingsPanel 以 @ObjectLink 观察。
// 自持 CommandPort 与发布回调，并自持加载器 loadPluginList。
// 约束：所有更新必须是"字段整体赋值"（pluginList 含 map(...) 后整体替换，无 push/splice 等原地变更）。
@Observed
export class PluginStore {
  pluginList: Array<PluginItem> = []
  pluginListLoading: boolean = false

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（无并发抑制需求）；保留字段以统一各 store 的加载器约定。
  private seq: number = 0
  private onChanged: (() => void) | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
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

  // 插件管理列表：桥查询插件清单。
  loadPluginList(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    this.pluginListLoading = true
    port.requestInteractive('getPluginList', '', (r: StellariumBridgeResponse) => {
      this.pluginListLoading = false
      if (r.ok === true && r.items !== undefined && Array.isArray(r.items)) {
        const arr = r.items as Array<Record<string, Object>>;
        const list: Array<PluginItem> = [];
        for (let i = 0; i < arr.length; i++) {
          const obj = arr[i];
          const id = obj['id'] !== undefined ? obj['id'] as string : '';
          const name = obj['name'] !== undefined ? obj['name'] as string : id;
          const loaded = obj['loaded'] !== undefined ? obj['loaded'] as boolean : false;
          const startup = true
          list.push({
            id: id,
            name: name,
            loaded: loaded,
            loadAtStartup: startup,
            description: obj['description'] as string | undefined,
            authors: obj['authors'] as string | undefined,
            contact: obj['contact'] as string | undefined,
            version: obj['version'] as string | undefined,
            license: obj['license'] as string | undefined,
            acknowledgements: obj['acknowledgements'] as string | undefined,
            hasPreviewImage: obj['hasPreviewImage'] as boolean | undefined,
            source: obj['source'] as string | undefined
          });
        }
        this.pluginList = list;
      }
      this.notifyChanged()
    }, () => {
      this.pluginListLoading = false
      this.notifyChanged()
    })
  }
}
