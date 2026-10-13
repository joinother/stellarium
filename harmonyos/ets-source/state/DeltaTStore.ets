// ΔT（时间差）算法域状态：宿主负责与引擎同步，时间设置面板以 @ObjectLink 订阅。
@Observed
export class DeltaTStore {
  deltaTAlgorithm: string = 'EspenakMeeusModified'
  timeDeltaTAlgorithms: string[] = []
  timeDeltaTCustom: string = ''
  deltaTDescription: string = ''
}
