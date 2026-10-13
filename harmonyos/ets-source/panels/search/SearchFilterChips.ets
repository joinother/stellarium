import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 已选筛选条件 chips（可视度 / 器材）：点击即清除该条件。
//
// 标签文本由宿主计算后以 @Prop 传入（宿主读 store，变更会触发宿主重绘 → @Prop 刷新）。
@Component
export struct SearchFilterChips {
  @Prop visibilityLabel: string
  @Prop instrumentLabel: string
  @Prop textColor: string
  @Prop panelColor: string
  onClearVisibility: () => void = () => {}
  onClearInstrument: () => void = () => {}

  build() {
    Scroll() {
      Row({ space: 7 }) {
        if (this.visibilityLabel.length > 0) {
          Text(this.visibilityLabel + '  x')
            .fontSize(12).fontColor(this.textColor).padding({ left: 12, right: 10, top: 7, bottom: 7 })
            .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_PILL)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut })
                .combine(TransitionEffect.translate({ x: 8, y: 0 }).animation({ duration: 180, curve: Curve.EaseOut })),
              TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseIn })
            ))
            .onClick(() => { this.onClearVisibility() })
        }
        if (this.instrumentLabel.length > 0) {
          Text(this.instrumentLabel + '  x')
            .fontSize(12).fontColor(this.textColor).padding({ left: 12, right: 10, top: 7, bottom: 7 })
            .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_PILL)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut })
                .combine(TransitionEffect.translate({ x: 8, y: 0 }).animation({ duration: 180, curve: Curve.EaseOut })),
              TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseIn })
            ))
            .onClick(() => { this.onClearInstrument() })
        }
      }.padding({ left: 2, right: 8 })
    }.width('100%').height(38).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
  }
}
