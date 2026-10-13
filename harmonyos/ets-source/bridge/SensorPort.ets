// 传感器能力端口：以纯接口提供传感器可用性查询与旋转矢量 / 方向 / 重力 / 磁场的
// 订阅与退订语义，使 SensorController 无需 import sensor.* 设备能力模块。
// 上报类型经 @kit.SensorServiceKit 的类型再导出短别名暴露，控制器只从本文件导入类型，
// 不直接触碰 sensor.on/off。
// 宿主在 aboutToAppear 注入具名实现 HostSensorPort（MainWindowNativeNode.ets）。
import { sensor } from '@kit.SensorServiceKit'

// 传感器可用性查询结果（对应 sensor.getSingleSensorSync 的返回信息）。
export interface SensorProbeInfo {
  sensorName: string
  vendorName: string
}

// 上报数据类型短别名：控制器经这些别名声明回调字段，无需 import 设备能力模块命名空间。
export type RotationVectorSample = sensor.RotationVectorResponse
export type OrientationSample = sensor.OrientationResponse
export type GravitySample = sensor.GravityResponse
export type MagneticFieldSample = sensor.MagneticFieldResponse

export interface SensorPort {
  // 查询某传感器是否可用（对应 sensor.getSingleSensorSync）；不可用返回 undefined。
  // label 同时用于适配器侧诊断日志与 SensorId 映射：
  // 'rotation-vector' / 'gravity' / 'magnetic-field' / 'orientation-fallback'。
  probeSensor(label: string): SensorProbeInfo | undefined
  // 旋转矢量（对应 sensor.on/off(ROTATION_VECTOR)）。
  subscribeRotationVector(callback: (data: RotationVectorSample) => void, intervalNs: number): void
  unsubscribeRotationVector(callback: (data: RotationVectorSample) => void): void
  // 方向（对应 sensor.on/off(ORIENTATION)）。
  subscribeOrientation(callback: (data: OrientationSample) => void, intervalNs: number): void
  unsubscribeOrientation(callback: (data: OrientationSample) => void): void
  // 重力（对应 sensor.on/off(GRAVITY)）。
  subscribeGravity(callback: (data: GravitySample) => void, intervalNs: number): void
  unsubscribeGravity(callback: (data: GravitySample) => void): void
  // 磁场（对应 sensor.on/off(MAGNETIC_FIELD)）。
  subscribeMagneticField(callback: (data: MagneticFieldSample) => void, intervalNs: number): void
  unsubscribeMagneticField(callback: (data: MagneticFieldSample) => void): void
}
