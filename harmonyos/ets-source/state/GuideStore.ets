import { GuideState } from '../common/derive/AstronomyGuide'

// 「交互导览 / 语音播报」域状态 store（纯数据）：持有导览播放器会话快照 guideState（phase /
// guideId / index / count / automatic / remaining / error）与朗读文本 speechStatus。
//
// 为何独立成 store：state/ 下无同义 store —— ToolsStore 是工具/帮助/角度测量/录制，ScriptStore
// 是脚本播放/录制/视频，SessionToolStore 是会话续传；导览与播报同属独立的「交互导览 + 朗读」链。
//
// 消费方：InteractiveGuideShell 经 @Prop 逐项接收 phase/index/count/automatic/remaining
// （简单类型按值下发），由宿主读 store 后下发；speechStatus 仅在各详情面板内显示。
//
// 约束：guideState 与 speechStatus 只做整体赋值（含 animateTo 内赋值），不得原地变更字段。
//
// 导览引擎、tick 定时器与桥调用在 capability/GuideController；本 store 保持纯状态，不 import UI/NAPI/桥。
@Observed
export class GuideStore {
  guideState: GuideState = { active: false, phase: 'idle', guideId: '', index: 0, count: 0, automatic: false, remaining: 0, error: '' }
  speechStatus: string = ''
}
