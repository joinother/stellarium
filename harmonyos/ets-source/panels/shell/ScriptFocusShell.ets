import { curves } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL, UI_RADIUS_PANEL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { ScriptKeyButton } from '../tools/ScriptKeyButton'
import { ScriptStore } from '../../state/ScriptStore'

// 脚本焦点播放壳（脚本 / 回放进行中的播放分支）。
//
// 脚本 / 回放进行中覆盖主界面的整屏壳：全屏触摸承接层 + 底部控制条（状态圆点、
// 标题与文件名、字幕 / 等待提示、速率微调与停止、功能键）。相邻的导览分发
// （`if (this.guideState.active) this.interactiveGuideShell()`）留在宿主，
// 宿主按 guideState.active 二选一渲染；本组件只承载播放分支。
//
// 播放/回放四态（scriptWaiting / scriptRunning / replaying / replayPaused）经 @ObjectLink
// 直接订阅 state/ScriptStore；文案与尺寸由宿主算好后以 @Prop 下发
// （scriptZh / visibleScriptCaptionText / scriptWaitDisplayText / scriptControl*）；
// 动作与触摸由宿主回注。
@Component
export struct ScriptFocusShell {
  @ObjectLink scriptStore: ScriptStore
  @Prop playbackVisible: boolean
  @Prop compact: boolean
  @Prop displayName: string
  @Prop hasCaptions: boolean
  @Prop captionText: string
  @Prop waitText: string
  @Prop rateText: string
  @Prop keyButtonWidth: number
  @Prop controlWidth: number
  @Prop controlHeight: number
  @Prop controlX: number
  @Prop controlY: number
  onSkyTouch: (event: TouchEvent) => void = () => {}
  onControlDragTouch: (event: TouchEvent) => void = () => {}
  onContinue: () => void = () => {}
  onChangeRate: (delta: number) => void = () => {}
  onToggleReplayPause: () => void = () => {}
  onStop: () => void = () => {}
  onSendKey: (key: string) => void = () => {}

  build() {
    Stack() {
      Stack() { }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Block)
        .zIndex(0)
        .onTouch((event: TouchEvent) => { this.onSkyTouch(event) })

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Stack() {
            Circle({ width: 7, height: 7 })
              .fill(this.scriptStore.scriptWaiting ? '#F0B44D' : '#68C8A4')
          }
            .width(18)
            .height(18)
          Column({ space: 2 }) {
            Text(this.scriptStore.scriptWaiting ? I18n.t('script_waiting') : (this.scriptStore.scriptRunning ? I18n.t('script_playing') : (this.scriptStore.replaying ? I18n.t('script_replaying') : I18n.t('script_preparing'))))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#F1FAFF')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.displayName)
              .fontSize(10)
              .fontColor('rgba(205, 228, 244, 0.70)')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          Stack() {
            Rect().width(18).height(3).radius(2).fill('rgba(205, 228, 244, 0.42)')
          }
            .width(30)
            .height(28)
        }
          .width('100%')
          .height(36)
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => { this.onControlDragTouch(event) })

        Stack() {
          if (this.hasCaptions) {
            Text(this.captionText)
              .fontSize(this.compact ? 11 : 12)
              .lineHeight(this.compact ? 16 : 17)
              .fontColor('#F2FAFF')
              .width('100%')
              .maxLines(this.scriptStore.scriptWaiting ? 1 : 4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 10, right: 10, top: 7, bottom: 7 })
              .position({ x: 0, y: this.scriptStore.scriptWaiting ? 46 : 0 })
              .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
          } else if (!this.scriptStore.scriptWaiting) {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color('#7FB3DC')
              Text(I18n.t('script_playing'))
                .fontSize(11)
                .fontColor('rgba(205, 228, 244, 0.72)')
            }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
          }

          if (this.scriptStore.scriptWaiting) {
            Row({ space: 8 }) {
              Image(getIcon('info', false)).width(16).height(16).fillColor('#D6EEFF')
              Text(this.waitText)
                .fontSize(11)
                .fontColor('#E7F6FF')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Button() {
                Row({ space: 5 }) {
                  Image(getIcon('time_resume', false)).width(16).height(16)
                  Text(I18n.t('script_continue'))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#F6FCFF')
                    .maxLines(1)
                }
              }
                .height(34)
                .width(this.compact ? 82 : 96)
                .backgroundColor('#4E89B5')
                .borderRadius(UI_RADIUS_CONTROL)
                .stateEffect(true)
                .enabled(this.scriptStore.scriptRunning)
                .onClick(() => { this.onContinue() })
            }
              .width('100%')
              .height(44)
              .padding({ left: 9, right: 6 })
              .backgroundColor('rgba(78, 137, 181, 0.30)')
              .border({ width: 0.5, color: 'rgba(147, 215, 255, 0.30)' })
              .borderRadius(UI_RADIUS_CONTROL)
              .position({ x: 0, y: 0 })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ x: 0, y: -5 }).animation({ duration: 190, curve: curves.springMotion(0.55, 0.90) })),
                TransitionEffect.OPACITY.animation({ duration: 110, curve: Curve.EaseIn })
              ))
          }
        }
          .width('100%')
          .height(this.scriptStore.replaying ? 78 : 82)
          .backgroundColor('rgba(91, 147, 191, 0.14)')
          .border({ width: 0.5, color: 'rgba(147, 215, 255, 0.18)' })
          .borderRadius(UI_RADIUS_CONTROL)
          .clip(true)

        Row({ space: 5 }) {
          Button() {
            Image(getIcon('time_slower', false)).width(18).height(18)
          }
            .backgroundColor('rgba(255,255,255,0.10)')
            .borderRadius(UI_RADIUS_CONTROL)
            .height(34)
            .width(36)
            .enabled(this.playbackVisible)
            .onClick(() => { this.onChangeRate(-1) })
          Text(this.rateText)
            .fontSize(11)
            .fontColor('#D9F1FF')
            .width(44)
            .textAlign(TextAlign.Center)
            .maxLines(1)
          Button() {
            Image(getIcon('time_fast', false)).width(18).height(18)
          }
            .backgroundColor('rgba(255,255,255,0.10)')
            .borderRadius(UI_RADIUS_CONTROL)
            .height(34)
            .width(36)
            .enabled(this.playbackVisible)
            .onClick(() => { this.onChangeRate(1) })
          if (this.scriptStore.replaying) {
            Button() {
              Image(getIcon(this.scriptStore.replayPaused ? 'time_realtime' : 'pause', false)).width(18).height(18)
            }
              .backgroundColor('rgba(255,255,255,0.10)')
              .borderRadius(UI_RADIUS_CONTROL)
              .height(34)
              .width(36)
              .onClick(() => { this.onToggleReplayPause() })
          }
          Blank()
          Button() {
            Row({ space: 5 }) {
              Image(getIcon('time_stop', false)).width(17).height(17)
              Text(I18n.t('script_stop'))
                .fontSize(11)
                .fontColor('#FFFFFF')
                .maxLines(1)
            }
          }
            .backgroundColor('rgba(192, 57, 43, 0.82)')
            .borderRadius(UI_RADIUS_CONTROL)
            .height(34)
            .width(this.compact ? 68 : 76)
            .stateEffect(true)
            .onClick(() => { this.onStop() })
        }
          .width('100%')
          .height(34)
          .zIndex(2)
          .hitTestBehavior(HitTestMode.Default)

        if (this.scriptStore.scriptRunning && !this.scriptStore.replaying) {
          Row({ space: 5 }) {
            ScriptKeyButton({ label: '−', keyName: '-', btnWidth: this.keyButtonWidth, isEnabled: this.scriptStore.scriptRunning && !this.scriptStore.replaying, onKey: (k: string) => { this.onSendKey(k) } })
            ScriptKeyButton({ label: '+', keyName: '+', btnWidth: this.keyButtonWidth, isEnabled: this.scriptStore.scriptRunning && !this.scriptStore.replaying, onKey: (k: string) => { this.onSendKey(k) } })
            ScriptKeyButton({ label: '[', keyName: '[', btnWidth: this.keyButtonWidth, isEnabled: this.scriptStore.scriptRunning && !this.scriptStore.replaying, onKey: (k: string) => { this.onSendKey(k) } })
            ScriptKeyButton({ label: ']', keyName: ']', btnWidth: this.keyButtonWidth, isEnabled: this.scriptStore.scriptRunning && !this.scriptStore.replaying, onKey: (k: string) => { this.onSendKey(k) } })
            ScriptKeyButton({ label: 'N', keyName: 'N', btnWidth: this.keyButtonWidth, isEnabled: this.scriptStore.scriptRunning && !this.scriptStore.replaying, onKey: (k: string) => { this.onSendKey(k) } })
            ScriptKeyButton({ label: 'B', keyName: 'B', btnWidth: this.keyButtonWidth, isEnabled: this.scriptStore.scriptRunning && !this.scriptStore.replaying, onKey: (k: string) => { this.onSendKey(k) } })
          }
            .height(34)
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .hitTestBehavior(HitTestMode.Default)
      }
      }
      .width(this.controlWidth)
      .height(this.controlHeight)
      .padding({ left: 12, right: 10, top: 8, bottom: 8 })
      .position({ x: this.controlX, y: this.controlY })
      .backgroundColor('rgba(10, 18, 30, 0.84)')
      .backdropBlur(28)
      .border({ width: 1, color: 'rgba(147, 215, 255, 0.20)' })
      .borderRadius(UI_RADIUS_PANEL)
      .shadow({ radius: 18, color: 'rgba(0,0,0,0.30)', offsetX: 0, offsetY: 8 })
      .zIndex(120)
      .hitTestBehavior(HitTestMode.Default)
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 0, y: -12 }).animation({ duration: 240, curve: curves.springMotion(0.5, 0.86) })),
        TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseIn })
          .combine(TransitionEffect.translate({ x: 0, y: -6 }).animation({ duration: 160, curve: Curve.EaseIn }))
      ))
    }
  }
}
