import { SpectralDataset } from '../common/types/StellariumTypes'

// HiPS / TOAST 巡天域状态 store：持有巡天状态文案、多波段数据集列表、当前多波段图层 id 与状态文案。
// 消费方以 @ObjectLink 订阅；字段随桥回包更新，宿主与组件的刷新语义不变。
@Observed
export class SurveyStore {
  surveyStateText: string = ''
  spectralDatasets: Array<SpectralDataset> = []
  spectralActiveId: string = ''
  spectralStateText: string = ''
}
