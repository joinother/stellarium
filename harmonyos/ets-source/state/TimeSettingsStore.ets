// 时间设置（设置面板「时间」标签页）域状态：日期/时间格式与启动时间来源；消费方以 @ObjectLink 观察。
// `timeSettingsPending` 刻意不并入：它同时被启动时间设置区与其他面板读取，仍由宿主持有并以 @Prop 传入。
// 配置回读加载器 loadConfigurationSettings（8 连发）在 capability/SettingsController；本 store 为纯数据
//（无 CommandPort / 无 IO），跨域 setter 由控制器经 TimeSettingsHostHooks 注入调用。

@Observed
export class TimeSettingsStore {
  configDateFormat: string = 'yyyymmdd'
  configTimeFormat: string = '24h'
  startupTimeMode: string = 'actual'
  startupTimeStop: boolean = false
  startupTodayTime: string = '12:00:00'
  startupPresetLocalTime: string = ''
  timeSettingsZone: string = ''
  // 「预设天空时间」（JD）：由宿主 applyTimeSettings 从配置回包写入；当前无 ArkTS 读取方，
  // 保留以供后续使用（默认 0）。
  presetSkyTime: number = 0
}
