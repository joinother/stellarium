import { CommandCatalogEntry, CommandCatalogResponse } from '../pages/MainWindowModels'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'

// 命令控制台（command console）域的面板状态，由面板以 @ObjectLink 订阅。
// 本 store 自持 loadCommandCatalog 加载器，并持有 CommandPort 注入（不 import 桥）。
//
// 约束：本域无原地变更（commandNameInput 的 `length === 0` 为读取比较），@ObjectLink 语义等价。
@Observed
export class CommandStore {
  commandCatalog: Array<CommandCatalogEntry> = []
  commandSearchText: string = ''
  commandNameInput: string = ''
  commandPayloadInput: string = ''
  commandResultText: string = ''
  commandPendingConfirmation: string = ''
  commandBusy: boolean = false

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（无并发抑制需求）；seq 预留以保持统一约定。
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

  // 命令控制台：桥查询命令目录；成功时回填并默认选中首个命令。
  loadCommandCatalog(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    port.requestInteractive('getCommandCatalog', '', (r: StellariumBridgeResponse) => {
      const catalogResponse = r as CommandCatalogResponse
      if (catalogResponse.ok !== true || !Array.isArray(catalogResponse.commands)) {
        this.commandResultText = JSON.stringify({ ok: false, error: r.error ?? '命令目录不可用' }, null, 2)
        this.notifyChanged()
        return
      }
      const entries: Array<CommandCatalogEntry> = []
      const raw = catalogResponse.commands as Array<Record<string, Object>>
      for (let i = 0; i < raw.length; i++) {
        const item = raw[i]
        if (typeof item['name'] !== 'string') continue
        entries.push({
          name: item['name'] as string,
          category: typeof item['category'] === 'string' ? item['category'] as string : '工具',
          description: typeof item['description'] === 'string' ? item['description'] as string : '',
          mutatesState: item['mutatesState'] === true,
          requiresConfirmation: item['requiresConfirmation'] === true,
          offline: item['offline'] !== false,
          examplePayload: typeof item['examplePayload'] === 'string' ? item['examplePayload'] as string : undefined,
        })
      }
      this.commandCatalog = entries
      if (this.commandNameInput.length === 0 && entries.length > 0) this.commandNameInput = entries[0].name
      this.notifyChanged()
    }, (r: StellariumBridgeResponse) => {
      this.commandResultText = JSON.stringify({ ok: false, error: r.error ?? '命令目录加载超时' }, null, 2)
      this.notifyChanged()
    })
  }
}
