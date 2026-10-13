// 自检行为控制器。
//
// 自检是一组 action 开关的整体翻转，用于启动期验证 C++ 动作目录与桥通道。
// 控制器不 import NAPI/UI：桥经 CommandPort 发出（含录制记录）；重试窗口 0ms × 100 × 120 = 12s
// 撑过 StelApp 初始化，确保命令真正跑到 C++ 自检。日志经 hilog（与 TimeController 等控制器一致）。
import hilog from '@ohos.hilog'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'

// 自检动作 ID 全表。
export const SELFTEST_ACTION_IDS: string[] = [
  "actionHorizontal_Flip",
  "actionShow_Antisolar_Point",
  "actionShow_Apex_Points",
  "actionShow_Asterism_Labels",
  "actionShow_Asterism_Lines",
  "actionShow_Atmosphere",
  "actionShow_Azimuthal_Grid",
  "actionShow_Celestial_J2000_Poles",
  "actionShow_Celestial_Poles",
  "actionShow_Circumpolar_Circles",
  "actionShow_Colure_Lines",
  "actionShow_Compass_Marks",
  "actionShow_Constellation_Hulls",
  "actionShow_Constellation_Art",
  "actionShow_Constellation_Boundaries",
  "actionShow_Constellation_Labels",
  "actionShow_Constellation_Lines",
  "actionShow_Current_Vertical_Line",
  "actionShow_DSO_Textures",
  "actionShow_Ecliptic_Grid",
  "actionShow_Ecliptic_J2000_Grid",
  "actionShow_Ecliptic_J2000_Line",
  "actionShow_Ecliptic_J2000_Poles",
  "actionShow_Ecliptic_Line",
  "actionShow_Ecliptic_Poles",
  "actionShow_Equator_J2000_Line",
  "actionShow_Equator_Line",
  "actionShow_Equatorial_Grid",
  "actionShow_Equatorial_J2000_Grid",
  "actionShow_Equinox_J2000_Points",
  "actionShow_Equinox_Points",
  "actionShow_FOV_Center_Marker",
  "actionShow_Gridlines",
  "actionShow_Fixed_Equator_Line",
  "actionShow_Fixed_Equatorial_Grid",
  "actionShow_Fog",
  "actionShow_Galactic_Center",
  "actionShow_Galactic_Equator_Line",
  "actionShow_Galactic_Grid",
  "actionShow_Galactic_Poles",
  "actionShow_Ground",
  "actionShow_MistHorizon",
  "actionShow_Hips_Surveys",
  "actionShow_Horizon_Line",
  "actionShow_Intercardinal_Points",
  "actionShow_Invariable_Plane_Line",
  "actionShow_LandscapeIllumination",
  "actionShow_LandscapeLabels",
  "actionShow_Longitude_Line",
  "actionShow_LunarSystem",
  "actionShow_Meridian_Line",
  "actionShow_MilkyWay",
  "actionShow_Nebulas",
  "actionShow_Night_Mode",
  "actionShow_Penumbra_Circle",
  "actionShow_Planets",
  "actionShow_Planets_EnlargeMoon",
  "actionShow_Planets_EnlargePlanets",
  "actionShow_Planets_EnlargeSun",
  "actionShow_Planets_Hints",
  "actionShow_Planets_Nomenclature",
  "actionShow_Planets_Orbits",
  "actionShow_Planets_ShowMinorBodyMarkers",
  "actionShow_Planets_Trails",
  "actionShow_Precession_Circles",
  "actionShow_Prime_Vertical_Line",
  "actionShow_Quadrature_Line",
  "actionShow_Ray_Helpers",
  "actionShow_Solar_Equator_Line",
  "actionShow_Solstice_J2000_Points",
  "actionShow_Solstice_Points",
  "actionShow_Stars",
  "actionShow_Stars_Labels",
  "actionShow_Supergalactic_Equator_Line",
  "actionShow_Supergalactic_Grid",
  "actionShow_Supergalactic_Poles",
  "actionShow_Toast_Survey",
  "actionShow_Umbra_Center_Point",
  "actionShow_Umbra_Circle",
  "actionShow_Zenith_Nadir",
  "actionShow_Zodiac",
  "actionSwitch_Equatorial_Mount",
  "actionVertical_Flip"
]

export class SelfTestController {
  private port: CommandPort

  constructor(port: CommandPort) {
    this.port = port
  }

  // 整包下发自检 action id 并打印回包。
  selfTestAllActions(): void {
    hilog.info(0x0000, 'StellariumArkUI', 'selftest send %{public}d ids', SELFTEST_ACTION_IDS.length)
    // 引擎核心(StelApp)在启动早期尚未就绪，命令会先返回 pending 不入队；
    // 用更长重试窗口(100ms x 120 = 12s)撑过初始化，确保真正跑到 C++ 自检。
    this.port.requestWhenReady('selftestActions', SELFTEST_ACTION_IDS.join('|'), (r: StellariumBridgeResponse) => {
      // 把整包响应(含 total/missing)打在一行里，避免被启动期日志冲掉
      hilog.info(0x0000, 'StellariumArkUI', 'selftest done %{public}s', JSON.stringify(r))
    }, undefined, 0, 100, 120)
  }
}
