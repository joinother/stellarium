// 语音播报服务（PLAN §15.3 P4-3 / §15.10 M1-4，本片 M1-A 子组②）。
//
// 原宿主 MainWindowNativeNode 的 speakSelectedObject(11) 私有方法逐字下沉。
// 本模块**不 import NAPI/UI**（§15.7 规则 1）：朗读文本经 CommandPort（getObjectSpokenText）拉取；
// 结果文本写回 GuideStore.speechStatus 与 flashHint 经 SpeechHints 具名注入（§13.1 规则 6）。
//
// 说明（与宿主原注释一致）：当前构建基于 OpenHarmony 基础 SDK（API 24），其 kit 列表不含
// @kit.CoreSpeechKit，故无法做真正的 TTS 音频播报，仅生成可读中文文本。待切换到含 CoreSpeechKit
// 的 SDK 后，可在此经 PlatformPort.speak 接真实语音合成（端口已预留 speak 槽位）。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { SpokenTextResponse } from '../pages/MainWindowModels'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

export interface SpeechHints {
  flashHint(text: ResourceStr): void
  setSpeechStatus(text: string): void
}

// 生成选中天体的可读朗读文本（原宿主 speakSelectedObject，逐字搬入）。
// 差异仅：this.callNativeWhenReady → port.requestWhenReady；this.guideStore.speechStatus = x →
// hints.setSpeechStatus(x)；this.flashHint → hints.flashHint。
export function speakSelectedObject(port: CommandPort, hints: SpeechHints): void {
  port.requestWhenReady('getObjectSpokenText', '', (r: StellariumBridgeResponse) => {
    const resp = r as SpokenTextResponse
    if (resp.ok !== true || !resp.text) {
      hints.flashHint(I18n.t('msg_no_selection_for_tts'))
      return
    }
    hints.setSpeechStatus(resp.text)
    hints.flashHint('已生成朗读文本（当前 SDK 未集成语音合成）')
  })
}
