import { curves } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL, UI_RADIUS_PANEL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { ToolsStore } from '../../state/ToolsStore'

// 录制控制条。
//
// @ObjectLink 取"录制中 / 已暂停 / 控制区展开"三态；`recordCount` 是**高频进度**字段（每记一条可录制
// 命令都写一次），刻意不入被观察 store，以 @Prop 传入。skyWidth 与安全区顶部
// `scriptControlSafeTop()` 都是纯布局量，也以 @Prop 传入，使组件不依赖任何宿主方法。
// 暂停/继续、停止、展开控制由宿主注入（副作用：写录制缓冲、走桥、flashHint）。
//
// 视觉：Row space 6、圆点 8×8、标题 12 号 Medium；宽 Math.min(560, Math.max(260, skyWidth-24))、高 54、
// padding left12/right10、0.84 玻璃底 + backdropBlur 28 + 1px rgba(255,94,94,0.24) 描边、UI_RADIUS_PANEL、
// 阴影 radius18 offsetY8、zIndex 130、入场 OPACITY(160ms) + translateY(-10)(220ms springMotion 0.52/0.88)。
@Component
export struct RecordingControlBar {
  @ObjectLink store: ToolsStore
  @Prop recordCount: number
  @Prop skyWidth: number
  @Prop safeTop: number
  onToggleUi: () => void = () => {}
  onTogglePause: () => void = () => {}
  onStop: () => void = () => {}

  build() {
    Row({ space: 6 }) {
      Circle({ width: 8, height: 8 })
        .fill(this.store.recordingPaused ? '#F0B44D' : '#FF5E5E')
      Text(this.store.recordingPaused ? I18n.t('script_recording_paused') : I18n.t('script_recording'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#F1FAFF')
      if (this.skyWidth >= 410) {
        Text(this.recordCount.toString() + ' ' + I18n.t('script_recording_count'))
          .fontSize(10)
          .fontColor('rgba(205, 228, 244, 0.70)')
          .layoutWeight(1)
      } else {
        Text(this.recordCount.toString()).fontSize(10).fontColor('rgba(205, 228, 244, 0.70)').layoutWeight(1)
      }
      Button(this.store.recordingUiExpanded ? I18n.t('script_focus_controls') : I18n.t('script_open_controls'))
        .fontSize(10)
        .fontColor('#E8F8FF')
        .backgroundColor('rgba(255,255,255,0.10)')
        .borderRadius(UI_RADIUS_CONTROL)
        .height(34)
        .width(46)
        .padding({ left: 0, right: 0 })
        .onClick(() => { this.onToggleUi() })
      Button(this.store.recordingPaused ? I18n.t('btn_resume') : I18n.t('script_pause'))
        .fontSize(10)
        .fontColor('#E8F8FF')
        .backgroundColor('rgba(255,255,255,0.10)')
        .borderRadius(UI_RADIUS_CONTROL)
        .height(34)
        .width(48)
        .padding({ left: 0, right: 0 })
        .onClick(() => { this.onTogglePause() })
      Button(I18n.t('script_stop'))
        .fontSize(10)
        .fontColor('#FFFFFF')
        .backgroundColor('rgba(192,57,43,0.82)')
        .borderRadius(UI_RADIUS_CONTROL)
        .height(34)
        .width(48)
        .padding({ left: 0, right: 0 })
        .onClick(() => { this.onStop() })
    }
      .width(Math.min(560, Math.max(260, this.skyWidth - 24)))
      .height(54)
      .padding({ left: 12, right: 10 })
      .position({ x: Math.max(12, (this.skyWidth - Math.min(560, Math.max(260, this.skyWidth - 24))) / 2), y: this.safeTop })
      .backgroundColor('rgba(10,18,30,0.84)')
      .backdropBlur(28)
      .border({ width: 1, color: 'rgba(255,94,94,0.24)' })
      .borderRadius(UI_RADIUS_PANEL)
      .shadow({ radius: 18, color: 'rgba(0,0,0,0.30)', offsetX: 0, offsetY: 8 })
      .zIndex(130)
      .hitTestBehavior(HitTestMode.Default)
      .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ x: 0, y: -10 }).animation({ duration: 220, curve: curves.springMotion(0.52, 0.88) })))
  }
}
