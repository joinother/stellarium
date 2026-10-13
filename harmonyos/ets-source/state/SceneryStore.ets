import { Scenery3dItem, StellariumBridgeResponse } from '../pages/StellariumTypes'
import { Scenery3dResponse } from '../pages/MainWindowModels'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → SceneryStore 的回注（store 不 import 桥/UI/他 store）。
// `scenery3dCurrentId` 由宿主自持（记住当前场景以做恢复），本加载器只经此 setter 上报。
export interface SceneryHostHooks {
  setScenery3dCurrentId(id: string): void
}

// 3D 场景（scenery3d）域 store：持有场景列表与"面板可见"的启用/加载状态，
// 面板经 @ObjectLink 观察。桥经 attachPort 注入 CommandPort，本 store 自持 loadScenery3d；
// 当前场景 id 由宿主自持，加载回包经 SceneryHostHooks.setScenery3dCurrentId 回注。
//
// 字段沿用宿主原名（与面板 @Prop 名不同），避免同时重命名宿主多处引用。
@Observed
export class SceneryStore {
  scenery3dItems: Scenery3dItem[] = []
  scenery3dLoading: boolean = false
  scenery3dEnabled: boolean = false
  scenery3dLoadingId: string = ''

  // —— 桥 / 宿主回注注入 ——
  private port: CommandPort | null = null
  // 本加载器无并发抑制需求，seq 预留未用。
  private seq: number = 0
  private hooks: SceneryHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachHooks(hooks: SceneryHostHooks): void {
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  // 3D 场景列表：桥读场景清单并写入本域状态。
  loadScenery3d(): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    this.scenery3dLoading = true
    port.requestWhenReady('getScenery3dList', '', (r: StellariumBridgeResponse) => {
      this.scenery3dLoading = false
      const response = r as Scenery3dResponse
      if (response.ok !== true) return
      this.scenery3dItems = response.items ?? []
      hooks.setScenery3dCurrentId(response.current ?? '')
      this.scenery3dLoadingId = response.loading ?? ''
      this.scenery3dEnabled = response.enabled === true
    })
  }
}
