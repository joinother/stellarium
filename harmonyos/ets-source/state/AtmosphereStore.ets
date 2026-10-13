// 「大气观测辅助」域状态：气压 / 温度 / 消光（atmoPressure / atmoTemperature / atmoExtinction）
// 与大气折射开关（refractionOn），由且仅由图层面板（LayersPanel → 天空页「观测条件」→ ObservationAidBlock）消费。
// 本 store 自持回包写入 applyAtmosphereResponse；动作 applyAtmosphere 仍由宿主驱动。
//
// refractionOn 与 atmo* 同属「观测点大气条件」消费链，故成组于此而非 OverlayStore（叠层语义）。
// 约束：均为标量，只做整体赋值，无原地变更。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'

@Observed
export class AtmosphereStore {
  atmoPressure: number = 1013
  atmoTemperature: number = 10
  atmoExtinction: number = 0.13
  refractionOn: boolean = true

  // 大气参数回包写入：仅当回包成功时更新本域 4 个字段。
  applyAtmosphereResponse(r: StellariumBridgeResponse): void {
    if (r.ok !== true) return
    if (r.pressure !== undefined) this.atmoPressure = r.pressure
    if (r.temperature !== undefined) this.atmoTemperature = r.temperature
    if (r.extinction !== undefined) this.atmoExtinction = r.extinction
    this.refractionOn = (r.refractionOn === true)
  }
}
