import { I18n } from '../../pages/I18n'
import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { GuideButton } from '../guide/GuideButton'

// 交互式导览提示壳。
//
// 结构：全屏星空触摸承接层（仅 exploring 阶段转交宿主 handleSkyTouch）+ 导览卡片
// （标题/步序/阶段/正文/动作键/来源署名）。卡片可拖动，几何由宿主算好后以 @Prop 传入。
//
// 全部导览按钮是既有 `GuideButton` 组件，触摸/动作经回调回注宿主。
// 导览阶段文案与步序（guidePhase/index/count/stepTitle/stepText/stepKey）由宿主从
// `guideState` 与 `currentGuide()/currentGuideStep()` 逐项算好，简单类型 @Prop 按值下发，
// 宿主改值后重绘即可刷新。

@Component
export struct InteractiveGuideShell {
  @Prop guidePhase: string
  @Prop guideIndex: number
  @Prop guideCount: number
  @Prop guideAutomatic: boolean
  @Prop guideRemaining: number
  @Prop guideTitle: string
  @Prop guideCredit: string
  @Prop guideStepTitle: string
  @Prop guideStepText: string
  @Prop guideStepKey: string
  @Prop cardWidth: number
  @Prop cardHeight: number
  @Prop cardX: number
  @Prop cardY: number

  onSkyTouch: (event: TouchEvent) => void = () => {}
  onControlDragTouch: (event: TouchEvent) => void = () => {}
  onAction: (action: string) => void = () => {}

  build() {
    Stack() {
      Stack() { }.width('100%').height('100%').hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => {
          if (this.guidePhase === 'exploring') this.onSkyTouch(event)
        })
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(this.guideTitle).fontSize(13).fontColor('#A8BDD1').width('100%')
            Text((this.guideIndex + 1).toString() + ' / ' + this.guideCount.toString() + ' · ' + this.guideStepTitle)
              .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#EFF8FF').width('100%')
          }.layoutWeight(1).hitTestBehavior(HitTestMode.Block)
            .onTouch((event: TouchEvent) => { this.onControlDragTouch(event) })
          Button({ type: ButtonType.Circle }) { Image(getIcon('close', false)).width(20).height(20) }
            .id('guide-stop').width(44).height(44).backgroundColor('rgba(255,255,255,0.10)')
            .accessibilityText(I18n.t('guide_exit')).enabled(this.guidePhase !== 'restoring')
            .onClick(() => { this.onAction('stop') })
        }.width('100%').constraintSize({ minHeight: 52 }).hitTestBehavior(HitTestMode.Default)
        Scroll() {
          Column({ space: 12 }) {
            Text(I18n.t('guide_phase_' + this.guidePhase)).fontSize(12).fontColor('#9CD6D3').width('100%')
            ForEach([this.guideStepText], (step: string) => {
              Text(I18n.t(step)).fontSize(15).lineHeight(23).fontColor('#EFF8FF').width('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseInOut }))
            }, (step: string) => this.guideStepKey)
            Text(I18n.t('guide_simulation')).fontSize(12).fontColor('#A8BDD1').width('100%')
            if (this.guidePhase === 'error') {
              Text(I18n.t('guide_error')).fontSize(13).fontColor('#FFD2B6').width('100%')
            } else if (this.guidePhase === 'exploring') {
              Text(I18n.t('guide_explore_hint')).fontSize(13).fontColor('#A8BDD1').width('100%')
            } else {
              Row({ space: 8 }) {
                GuideButton({ label: 'guide_closer', action: 'closer', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
                GuideButton({ label: 'guide_wider', action: 'wider', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
                GuideButton({ label: 'guide_explore', action: 'explore', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
              }.width('100%')
              Row() {
                if (this.guideAutomatic) {
                  GuideButton({ label: 'guide_manual', action: 'auto-off', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
                } else {
                  GuideButton({ label: 'guide_auto', action: 'auto-on', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
                }
                if (this.guideAutomatic) {
                  Text(Math.ceil(this.guideRemaining).toString() + ' s').fontSize(13).fontColor('#A8BDD1').margin({ left: 12 })
                }
              }.width('100%')
            }
            Text(I18n.t(this.guideCredit)).fontSize(11).fontColor('#A8BDD1').width('100%')
          }.width('100%').padding({ bottom: 8 })
        }.id('guide-content').width('100%').layoutWeight(1).scrollBar(BarState.Auto).hitTestBehavior(HitTestMode.Default)
        Row({ space: 8 }) {
          if (this.guidePhase === 'exploring') {
            GuideButton({ label: 'guide_return', action: 'return', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
          } else if (this.guidePhase === 'error') {
            GuideButton({ label: 'guide_retry', action: 'retry', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
          } else {
            GuideButton({ label: 'guide_previous', action: 'previous', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
            if (this.guidePhase === 'paused') {
              GuideButton({ label: 'btn_resume', action: 'resume', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
            } else {
              GuideButton({ label: 'script_pause', action: 'pause', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
            }
            if (this.guideIndex + 1 === this.guideCount) {
              GuideButton({ label: 'guide_finish', action: 'next', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
            } else {
              GuideButton({ label: 'guide_next', action: 'next', phase: this.guidePhase, index: this.guideIndex, onAction: (a: string) => { this.onAction(a) } })
            }
          }
        }.width('100%').height(48).hitTestBehavior(HitTestMode.Default)
      }.width(this.cardWidth).height(this.cardHeight).padding(14)
        .position({ x: this.cardX, y: this.cardY })
        .backgroundColor('rgba(10,18,30,0.92)').borderRadius(UI_RADIUS_PANEL)
        .border({ width: 1, color: 'rgba(147,215,255,0.20)' })
        .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
        .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
  }
}
