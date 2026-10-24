import { I18n } from '../pages/I18n'
import { AstroColors } from './StellariumTheme'
// 传感器 / 陀螺仪域状态 store：持有导览姿态（gyroGuide*）、开关与状态（gyroscopeEnabled /
// gyroscopeStatus / gyroscopeSensitivityText）、罗盘读数（gyroCompass*）与校准面板 / 校准偏移。
// 消费方以 @ObjectLink 订阅；字段随传感器事件更新，宿主与组件的刷新语义不变。
@Observed
export class GyroStore {
  gyroGuideVisible: boolean = false
  gyroGuideAngle: number = 0
  gyroGuideX: number = 0
  gyroGuideY: number = 0
  gyroscopeEnabled: boolean = false
  // 切换中的乐观 UI：pending 期间指示器显示 pendingTarget，避免控件状态与引擎回包打架。
  gyroscopePending: boolean = false
  gyroscopePendingTarget: boolean = false
  gyroscopeStatus: ResourceStr = I18n.t('m_gyro_off')
  gyroscopeSensitivityText: string = 'Standard'
  gyroCalibPanelOpen: boolean = false
  gyroCompassText: string = '罗盘 --'
  gyroCompassAngle: number = 0
  gyroOffsetAz: number = 0    // 方位角校准偏移（度）
  gyroOffsetAlt: number = 0   // 高度角校准偏移（度）
  gyroCompassAzAlignment: number = 0

  // 切换中的乐观显示值（pending 期间取目标态）。
  gyroscopeVisualEnabled(): boolean {
    return this.gyroscopePending ? this.gyroscopePendingTarget : this.gyroscopeEnabled
  }

  // 陀螺仪指示点颜色：切换中黄、开启绿、关闭灰。
  gyroIndicatorColor(): string {
    if (this.gyroscopePending) return AstroColors.gyroPending
    if (this.gyroscopeEnabled) return AstroColors.gyroEnabled
    return AstroColors.gyroIdle
  }
}
