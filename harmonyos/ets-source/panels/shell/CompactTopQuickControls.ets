import { Theme } from '@kit.ArkUI'
import { CompactQuickButton } from './CompactQuickButton'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 右上角常驻快捷区：陀螺仪（设备支持真实硬件陀螺仪时显示）+ 音频控制。
//
// 两项的开关状态、按下态、整体透明度由宿主以 @Prop 传入；点按动作本体
// （含诊断日志、空闲复位、状态翻转与提示）由宿主回注，组件只负责外观与命中。

@Component
export struct CompactTopQuickControls {
  @Prop gyroActive: boolean
  @Prop audioActive: boolean
  @Prop showGyro: boolean = true
  @Prop receiveTap: boolean = true
  @Prop pressedId: string
  @Prop chromeOpacity: number
  @State c: ThemeSlots = DEFAULT_SLOTS
  onGyro: () => void = () => {}
  onAudio: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 10 }) {
      if (this.showGyro) {
        CompactQuickButton({
          iconName: 'gyro', active: this.gyroActive, receiveTap: this.receiveTap,
          pressedState: this.pressedId === 'gyro',
          tooltip: '陀螺仪跟随',
          onAction: () => { this.onGyro() }
        })
      }
      CompactQuickButton({
        iconName: 'audio', active: this.audioActive, receiveTap: this.receiveTap,
        pressedState: this.pressedId === 'audio',
        tooltip: '星空音效',
        onAction: () => { this.onAudio() }
      })
    }
      .width(44)
      .alignItems(HorizontalAlign.Center)
      .opacity(this.chromeOpacity)
      .animation({ duration: 420, curve: Curve.EaseOut })
  }
}
