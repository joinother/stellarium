// 观测点大气条件估算：按国际标准大气（ISA）从海拔推算站点气压与基准气温。
// 气压使用对流层公式，气温使用 15°C 海平面温度 + 0.0065°C/m 递减率。
// 仅用于地球观测点；外星观测点不套用地球大气模型。

export const SEA_LEVEL_PRESSURE_HPA: number = 1013.25
export const SEA_LEVEL_TEMPERATURE_C: number = 15.0
export const TEMPERATURE_LAPSE_C_PER_M: number = 0.0065
export const MIN_ATMOSPHERE_ALTITUDE_M: number = -500
export const MAX_ATMOSPHERE_ALTITUDE_M: number = 9000

function clampedAltitude(altitudeM: number): number {
  if (!Number.isFinite(altitudeM)) return 0
  return Math.max(MIN_ATMOSPHERE_ALTITUDE_M, Math.min(MAX_ATMOSPHERE_ALTITUDE_M, altitudeM))
}

// 对流层气压：p = p0 * (1 - L*h/T0)^(g*M/(R*L))
export function pressureAtAltitudeHpa(altitudeM: number): number {
  const h = clampedAltitude(altitudeM)
  const value = SEA_LEVEL_PRESSURE_HPA * Math.pow(1 - 2.25577e-5 * h, 5.25588)
  return Math.max(1, Math.min(1500, value))
}

// 基准气温：海平面 15°C，每上升 1 m 降低 0.0065°C。
export function temperatureAtAltitudeC(altitudeM: number): number {
  const h = clampedAltitude(altitudeM)
  const value = SEA_LEVEL_TEMPERATURE_C - TEMPERATURE_LAPSE_C_PER_M * h
  return Math.max(-60, Math.min(60, value))
}
