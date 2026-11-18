// 气压计一次性读数：位置面板「观测环境」的气压计测量模式使用。
// 传感器缺失、服务异常或 2 秒内无回包时 reject，由 UI 回退到按海拔推算。
import { sensor } from '@kit.SensorServiceKit'

const BAROMETER_TIMEOUT_MS: number = 2000

export class BarometerReader {
  // 设备是否提供气压计（sensor.getSensorListSync 可能抛 14500101）。
  static available(): boolean {
    try {
      return sensor.getSensorListSync()
        .some((item: sensor.Sensor) => item.sensorId === sensor.SensorId.BAROMETER)
    } catch (_error) {
      return false
    }
  }

  // 读取一次站点气压，单位 hPa。
  static read(): Promise<number> {
    return new Promise<number>((resolve: (value: number) => void,
      reject: (reason: Error) => void) => {
      let settled = false
      const timer = setTimeout(() => {
        if (settled) return
        settled = true
        reject(new Error('barometer-timeout'))
      }, BAROMETER_TIMEOUT_MS)
      try {
        sensor.once(sensor.SensorId.BAROMETER, (data: sensor.BarometerResponse) => {
          if (settled) return
          settled = true
          clearTimeout(timer)
          resolve(data.pressure)
        })
      } catch (_error) {
        settled = true
        clearTimeout(timer)
        reject(new Error('barometer-unavailable'))
      }
    })
  }
}
