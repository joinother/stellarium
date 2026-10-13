import { CompactQuickButton } from './CompactQuickButton'

// 手机端右上角常驻快捷区：陀螺仪 + 音频控制。
//
// 两项的开关状态、按下态、整体透明度由宿主以 @Prop 传入；点按动作本体
// （含诊断日志、空闲复位、状态翻转与提示）由宿主回注，组件只负责外观与命中。

@Component
export struct CompactTopQuickControls {
  @Prop gyroActive: boolean
  @Prop audioActive: boolean
  @Prop pressedId: string
  @Prop chromeOpacity: number
  @Prop textColor: string
  onGyro: () => void = () => {}
  onAudio: () => void = () => {}

  build() {
    Column({ space: 10 }) {
      CompactQuickButton({
        iconName: 'gyro', active: this.gyroActive, receiveTap: false,
        pressedState: this.pressedId === 'gyro', textColor: this.textColor,
        onAction: () => { this.onGyro() }
      })
      CompactQuickButton({
        iconName: 'audio', active: this.audioActive, receiveTap: false,
        pressedState: this.pressedId === 'audio', textColor: this.textColor,
        onAction: () => { this.onAudio() }
      })
    }
      .width(44)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Block)
      .opacity(this.chromeOpacity)
      .animation({ duration: 420, curve: Curve.EaseOut })
  }
}
