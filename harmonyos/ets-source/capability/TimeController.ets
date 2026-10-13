// 时间操作控制器：负责时间速率档位与暂停/恢复、时间轮暂停、时间跳转与手动设时、
// 时间/星等刷新、时间设置持久化与时间面板定时器，以及 chip 命令分发。
// 依赖 CommandPort（时间桥命令）、TimeStore / TimeSettingsStore / DeltaTStore。
// 时间面板定时器由控制器自持；时间轮重基准、儒略日字段同步、utcOffsetHours、时间设置待定门控、
// UI 动画以及 chip 的跨域动作（选中/居中/视图锁/方向/搜索/定位）经 TimeHostHooks 回注。
import hilog from '@ohos.hilog'
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { TimeStore } from '../state/TimeStore'
import { TimeSettingsStore } from '../state/TimeSettingsStore'
import { DeltaTStore } from '../state/DeltaTStore'
import { dateToJD, jdToLocalTimeText } from '../common/derive/astro'
import { formatRate } from '../common/derive/skycult'
import { getCityPreset } from '../common/derive/actions'
import { BehaviorHostHooks } from './ControllerHooks'

// 宿主 → 控制器回注。
export interface TimeHostHooks extends BehaviorHostHooks {
  // 观测地 UTC 偏移（dock 时钟 / 时间格式化共用）。
  utcOffsetHours(): number
  // 时间设置待定门控（保留 @State，SettingsPanel 消费）。
  timeSettingsPending(): boolean
  setTimeSettingsPending(value: boolean): void
  // 设置回包动画（applyTimeSettings 的 getUIContext().animateTo）。
  animateOption(action: () => void): void
  // 时间轮重基准与儒略日字段同步（宿主 TimeWheelController / JulianDateStore）。
  syncWheelFromSimulation(jd: number): void
  syncJulianDateFields(response: StellariumBridgeResponse, jd: number): void
  // chip 的跨域分支（保留：选中/居中/视图锁/方向/搜索/定位）。
  refreshSelectedObject(): void
  moveToSelectedObject(): void
  setViewLockState(locked: boolean): void
  triggerAction(actionId: string): void
  searchObject(name: string): void
  stopTracking(): void
  setLocation(name: string, lat: number, lon: number, alt: number): void
}

// ===== 时间速率档位系统 =====
// Stellarium 内部单位：Julian days per second (JD/s)
// 1 JD = 86400 秒，所以 1x 实时 = 1/86400 ≈ 1.1574e-5 JD/s
// 档位表：索引 0=暂停, 1=1x, 2=2x, 3=10x, 4=1分/秒, 5=1时/秒, 6=1天/秒, 7=10天/秒
// 负索引 = 倒带：-1=-1x, -2=-1时/秒, -3=-1天/秒
const TIME_SPEED_STEPS: number[] = [
  -864000.0 / 86400.0,   // -10: 倒带 极速(1天/秒反向)
  -360.0 / 86400.0,      // -9:  倒带 快进(1时/秒反向)
  -60.0 / 86400.0,       // -8:  倒带(1分/秒反向)
  -10.0 / 86400.0,       // -7:  倒带 10x
  -2.0 / 86400.0,        // -6:  倒带 2x
  -1.0 / 86400.0,        // -5:  倒带 1x
  0,                      //  0:  停止
  1.0 / 86400.0,         //  1:  实时 1x
  2.0 / 86400.0,         //  2:  2x
  10.0 / 86400.0,        //  3:  10x
  60.0 / 86400.0,        //  4:  1分/秒
  360.0 / 86400.0,       //  5:  1时/秒
  86400.0 / 86400.0,     //  6:  1天/秒
  864000.0 / 86400.0,    //  7:  10天/秒
]
// TIME_SPEED_STEPS 的"零点"索引（停止）和"实时"索引
const TIME_SPEED_IDX_STOP = 6
const TIME_SPEED_IDX_REALTIME = 7

export class TimeController {
  private timeStore: TimeStore
  private timeSettingsStore: TimeSettingsStore
  private deltaTStore: DeltaTStore
  private port: CommandPort
  private hooks: TimeHostHooks

  // ── 草稿/定时器字段（留控制器，不入被观察 store）──
  private timePanelTimer: number = 0
  private timePanelFullTimer: number = 0
  private timeMarkLoading: boolean = false

  constructor(
    timeStore: TimeStore,
    timeSettingsStore: TimeSettingsStore,
    deltaTStore: DeltaTStore,
    port: CommandPort,
    hooks: TimeHostHooks
  ) {
    this.timeStore = timeStore
    this.timeSettingsStore = timeSettingsStore
    this.deltaTStore = deltaTStore
    this.port = port
    this.hooks = hooks
  }

  // ── 时间面板定时器（自持 start/stop，宿主面板路由/生命周期调用）──
  startPanelTimers(): void {
    this.stopPanelTimers()
    this.timePanelTimer = setInterval(() => { this.refreshSimTimeLight() }, 125) as number
    this.timePanelFullTimer = setInterval(() => {
      this.hooks.refreshState()
      this.timeStore.loadTimeExtras()
    }, 3000) as number
  }

  stopPanelTimers(): void {
    if (this.timePanelTimer !== 0) {
      clearInterval(this.timePanelTimer)
      this.timePanelTimer = 0
    }
    if (this.timePanelFullTimer !== 0) {
      clearInterval(this.timePanelFullTimer)
      this.timePanelFullTimer = 0
    }
  }

  hasPanelTimer(): boolean {
    return this.timePanelTimer !== 0
  }

  setTimeRate(rate: number): void {
    // 速率命令本身不需要结果。此前这里紧跟一次 getState，旧的异步状态会
    // 短暂覆盖刚刚更新的文本，造成“倒带/快进按钮闪一下”的错觉。
    this.port.fire('setTimeRate', rate.toString())
  }

  // 时间轮按下即暂停（跨域写收在宿主）。
  stopTimeWheelSpeed(): void {
    this.timeStore.timeSpeedIndex = TIME_SPEED_IDX_STOP
    this.timeStore.beginRateChange(0, 500)
    this.timeStore.timeRateText = formatRate(0)
  }

  /** Apply speed at given step index. Clamps to valid range. */
  applySpeedStep(index: number): void {
    const idx: number = Math.max(0, Math.min(TIME_SPEED_STEPS.length - 1, index))
    const rate: number = TIME_SPEED_STEPS[idx]
    this.timeStore.timeSpeedIndex = idx
    this.timeStore.beginRateChange(rate, 500)
    this.setTimeRate(rate)
    this.timeStore.timeRateText = formatRate(rate)
  }

  /** 将原生返回的速率映射回时间档位，保证面板重建后按钮状态不会丢失。 */
  syncTimeRateState(rate: number): void {
    // 陈旧/重复回报由 store 统一判定（待定窗口 + 去重），本控制器只负责按结果落库。
    if (this.timeStore.shouldIgnoreEngineRate(rate)) { return }

    this.timeStore.lastSyncedTimeRate = rate
    this.timeStore.timeRateText = formatRate(rate)
    let nearestIndex = 0
    let nearestDistance = Number.MAX_VALUE
    for (let i = 0; i < TIME_SPEED_STEPS.length; i++) {
      const candidate = TIME_SPEED_STEPS[i]
      const distance = Math.abs(candidate - rate)
      if (distance < nearestDistance) {
        nearestDistance = distance
        nearestIndex = i
      }
    }
    this.timeStore.timeSpeedIndex = nearestIndex
  }

  /** Speed up one step. */
  speedUp(): void {
    this.applySpeedStep(this.timeStore.timeSpeedIndex + 1)
  }

  /** Slow down one step (can go into reverse). */
  speedDown(): void {
    this.applySpeedStep(this.timeStore.timeSpeedIndex - 1)
  }

  /** Toggle pause: remember current non-zero speed, restore on unpause. */
  togglePause(): void {
    if (this.timeStore.timeSpeedIndex === TIME_SPEED_IDX_STOP) {
      // Resume: restore last speed or default to 1x
      const resumeIdx = this.timeStore.lastNonZeroSpeedIndex > 0 && this.timeStore.lastNonZeroSpeedIndex !== TIME_SPEED_IDX_STOP ? this.timeStore.lastNonZeroSpeedIndex : TIME_SPEED_IDX_REALTIME
      this.applySpeedStep(resumeIdx)
    } else {
      // Pause: remember current speed
      this.timeStore.lastNonZeroSpeedIndex = this.timeStore.timeSpeedIndex
      this.applySpeedStep(TIME_SPEED_IDX_STOP)
    }
  }

  advanceTime(hours: number): void {
    this.port.requestInteractive('advanceTime', hours.toString(), () => { this.refreshTimeNow() })
    this.hooks.flashHint((hours > 0 ? I18n.t('i0044') : '') + hours.toString() + ' h')
  }

  jumpToTimeMark(mark: string): void {
    if (this.timeMarkLoading) { return }
    const label = mark === 'sunRise' ? '日出' : (mark === 'sunTransit' ? '太阳中天' : (mark === 'sunSet' ? '日落' : '天文昏影'))
    this.timeMarkLoading = true
    this.port.requestInteractive('getAlmanac', '', (response: StellariumBridgeResponse) => {
      const almanac = response.almanac as Record<string, Object> | undefined
      const targetJD = almanac !== undefined ? Number(almanac[mark]) : Number.NaN
      if (response.ok !== true || !Number.isFinite(targetJD) || targetJD <= 0) {
        this.timeMarkLoading = false
        this.hooks.flashHint('当前日期和地点没有可用的' + label + '时刻。')
        return
      }
      this.applySpeedStep(TIME_SPEED_IDX_STOP)
      this.port.requestInteractive('setJD', targetJD.toFixed(6), () => {
        this.timeMarkLoading = false
        this.hooks.syncWheelFromSimulation(targetJD)
        this.refreshTimeNow()
        this.hooks.flashHint('已定位到' + label + '。')
      }, () => {
        this.timeMarkLoading = false
        this.hooks.flashHint(label + '时刻设置失败，请重试。')
      })
    }, () => {
      this.timeMarkLoading = false
      this.hooks.flashHint('获取' + label + '时刻失败，请重试。')
    })
  }

  applyManualTime(): void {
    const jd = dateToJD(this.timeStore.manualYear, this.timeStore.manualMonth, this.timeStore.manualDay, this.timeStore.manualHour, this.timeStore.manualMinute)
    this.port.requestInteractive('setJD', jd.toFixed(6), (r: StellariumBridgeResponse) => {
      this.hooks.refreshState()
      this.hooks.flashHint(String(this.timeStore.manualMonth).padStart(2, '0') + '-' + String(this.timeStore.manualDay).padStart(2, '0') + ' ' + String(this.timeStore.manualHour).padStart(2, '0') + ':' + String(this.timeStore.manualMinute).padStart(2, '0'))
    })
  }

  syncManualTimeFromState(): void {
    this.port.requestInteractive('getState', '', (result) => {
    if (result.jd !== undefined) {
      const jd = result.jd as number
      const z = Math.floor(jd + 0.5)
      const f = jd + 0.5 - z
      let A = z
      if (z >= 2299161) {
        const alpha = Math.floor((z - 1867216.25) / 36524.25)
        A = z + 1 + alpha - Math.floor(alpha / 4)
      }
      const B = A + 1524
      const C = Math.floor((B - 122.1) / 365.25)
      const D = Math.floor(365.25 * C)
      const E = Math.floor((B - D) / 30.6001)
      const day = B - D - Math.floor(30.6001 * E)
      const month = E < 14 ? E - 1 : E - 13
      const year = month > 2 ? C - 4716 : C - 4715
      const dayFraction = f * 24
      const hour = Math.floor(dayFraction)
      const minute = Math.floor((dayFraction - hour) * 60)
      this.timeStore.manualYear = year
      this.timeStore.manualMonth = month
      this.timeStore.manualDay = day
      this.timeStore.manualHour = hour
      this.timeStore.manualMinute = minute
    }
    })
  }

  applyTimeSettings(result: StellariumBridgeResponse): void {
    if (result.ok !== true) return
    this.hooks.animateOption(() => {
      this.timeSettingsStore.startupTimeMode = result.startupTimeMode ?? this.timeSettingsStore.startupTimeMode
      this.deltaTStore.deltaTAlgorithm = result.deltaTAlgorithm ?? this.deltaTStore.deltaTAlgorithm
    })
    this.timeSettingsStore.startupTimeStop = result.startupTimeStop ?? this.timeSettingsStore.startupTimeStop
    this.timeSettingsStore.startupTodayTime = result.todayTime ?? this.timeSettingsStore.startupTodayTime
    this.timeSettingsStore.startupPresetLocalTime = result.presetLocalTime ?? this.timeSettingsStore.startupPresetLocalTime
    if (result.presetSkyTime !== undefined) this.timeSettingsStore.presetSkyTime = Number(result.presetSkyTime)
    this.timeSettingsStore.configDateFormat = result.dateFormat ?? this.timeSettingsStore.configDateFormat
    this.timeSettingsStore.configTimeFormat = result.timeFormat ?? this.timeSettingsStore.configTimeFormat
    this.timeStore.observationTimeText = result.formattedTime ?? this.timeStore.observationTimeText
    this.timeSettingsStore.timeSettingsZone = result.timeZone ?? this.timeSettingsStore.timeSettingsZone
    this.deltaTStore.deltaTDescription = result.deltaTDescription ?? this.deltaTStore.deltaTDescription
    this.deltaTStore.timeDeltaTAlgorithms = result.deltaTAlgorithms ?? this.deltaTStore.timeDeltaTAlgorithms
    this.deltaTStore.timeDeltaTCustom = result.deltaTCustom ?? this.deltaTStore.timeDeltaTCustom
  }

  saveTimePreference(command: string, payload: string, message: string): void {
    if (this.hooks.timeSettingsPending()) return
    this.hooks.setTimeSettingsPending(true)
    this.port.requestInteractive(command, payload, (result: StellariumBridgeResponse) => {
      this.hooks.setTimeSettingsPending(false)
      if (result.ok !== true) {
        this.hooks.flashHint(I18n.t('time_settings_invalid') + ' ' + (result.error ?? ''))
        return
      }
      this.applyTimeSettings(result)
      this.hooks.flashHint(I18n.t(message))
      this.refreshSimTimeLight()
    }, () => {
      this.hooks.setTimeSettingsPending(false)
      this.hooks.flashHint(I18n.t('msg_apply_failed'))
    })
  }

  setStartupTimeSetting(key: string, value: string): void {
    if (key === 'startupStop' && (value === '1') === this.timeSettingsStore.startupTimeStop) return
    if (key === 'startupMode' && value === this.timeSettingsStore.startupTimeMode) return
    this.saveTimePreference('setTimeSetting', key + '|' + value.trim(),
      key === 'applyStartup' || key === 'deltaT' || key === 'deltaCustom' ? 'time_settings_applied' : 'time_settings_saved')
  }

  setConfigurationTimeFormat(value: string): void {
    this.saveTimePreference('setTimeFormat', value, 'time_settings_applied')
  }

  /**
   * 时间类操作后刷新「时间/速度」显示。
   * 立即刷一次（响应快），350ms 后再刷一次（引擎异步应用 JD/timeRate 需要时间窗口）。
   */
  refreshTimeNow(): void {
    this.hooks.refreshState()
    // 注意：此处必须是 setTimeout(refreshState)，绝不能调 refreshTimeNow 自身（会无限递归栈溢出）
    setTimeout(() => { this.hooks.refreshState() }, 350)
  }

  /**
   * 轻量时间刷新：只取 jd + timeRate（getSimulationTime 极轻），不做 getState 全量状态同步。
   * 用于时间面板的高频（~120ms）流式刷新，让读秒像水一样连续流动而不是每秒跳一大格。
   * 注意：不要在这里改动除时间/速率以外的任何 @State，否则会引发全局重排、拖动星图变卡。
   */
  refreshSimTimeLight(): void {
    this.port.requestInteractive('getSimulationTime', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true || r.jd === undefined) { return }
      const jd: number = r.jd as number
      // jd 是 UTC；加上观测地 UTC 偏移后再格式化，与 getState 的 timeText 口径保持一致
      const text: string = r.formattedTime ?? jdToLocalTimeText(jd + this.hooks.utcOffsetHours() / 24.0)
      if (text !== this.timeStore.observationTimeText) {
        this.timeStore.observationTimeText = text
      }
      if (r.timeRate !== undefined) {
        this.syncTimeRateState(r.timeRate as number)
      }
      this.hooks.syncWheelFromSimulation(jd)
      this.hooks.syncJulianDateFields(r, jd)
    })
  }

  handleChip(id: string): void {
    if (id === 'refresh') {
      this.hooks.refreshSelectedObject()
      this.hooks.refreshState()
    } else if (id === 'center') {
      this.hooks.moveToSelectedObject()
    } else if (id === 'lock-view') {
      this.hooks.setViewLockState(true)
    } else if (id === 'unlock-view') {
      this.hooks.setViewLockState(false)
    } else if (id === 'now') {
      // 现在：回到当前时刻 + 重置为1x
      this.hooks.triggerAction('actionReturn_To_Current_Time')
      this.applySpeedStep(TIME_SPEED_IDX_REALTIME)
      this.timeStore.timeRateText = '1x'
      this.refreshTimeNow()
    } else if (id === 'stop') {
      // 停止按钮是可逆状态：运行时停止，停止后恢复到停止前速度。
      if (this.timeStore.timeSpeedIndex === TIME_SPEED_IDX_STOP) {
        this.applySpeedStep(this.timeStore.lastNonZeroSpeedIndex === TIME_SPEED_IDX_STOP ? TIME_SPEED_IDX_REALTIME : this.timeStore.lastNonZeroSpeedIndex)
      } else {
        this.timeStore.lastNonZeroSpeedIndex = this.timeStore.timeSpeedIndex
        this.applySpeedStep(TIME_SPEED_IDX_STOP)
      }
      this.refreshTimeNow()
    } else if (id === 'realtime') {
      // 实时：回到当前时刻 + 恢复 1x 正常速度
      this.hooks.triggerAction('actionReturn_To_Current_Time')
      this.applySpeedStep(TIME_SPEED_IDX_REALTIME)
      this.timeStore.timeRateText = '1x'
      this.refreshTimeNow()
    } else if (id === 'rewind') {
      // 倒带：单按钮循环升档 -1x → -2x → -10x → -1分/秒 → -1时/秒 → -1天/秒 → 回到-1x
      let rewIdx = 5 // 默认从 -1x 起步（非倒带状态按下时）
      if (this.timeStore.timeSpeedIndex < TIME_SPEED_IDX_STOP) {
        // 已在倒带中：再点升一档（索引减小=更快反向）；到底(0)循环回 -1x
        rewIdx = this.timeStore.timeSpeedIndex === 0 ? 5 : this.timeStore.timeSpeedIndex - 1
      }
      this.applySpeedStep(rewIdx)
      this.hooks.flashHint(I18n.t('s0763_rewind') + ' ' + this.timeStore.timeRateText)
      this.refreshTimeNow()
    } else if (id === 'faster' || id === 'fast' || id === 'warp') {
      // 快进：单按钮循环升档 1x → 2x → 10x → 1分/秒 → 1时/秒 → 1天/秒 → 10天/秒 → 回到1x
      let fwdIdx = TIME_SPEED_IDX_REALTIME // 默认回 1x（停止/倒带状态按下时从 1x 起步）
      if (this.timeStore.timeSpeedIndex >= TIME_SPEED_IDX_REALTIME) {
        // 已在正向：升一档；到顶(13)循环回 1x
        fwdIdx = this.timeStore.timeSpeedIndex >= 13 ? TIME_SPEED_IDX_REALTIME : this.timeStore.timeSpeedIndex + 1
      }
      this.applySpeedStep(fwdIdx)
      this.hooks.flashHint(I18n.t('s0765_fast') + ' ' + this.timeStore.timeRateText)
      this.refreshTimeNow()
    } else if (id === 'slower') {
      // 减速：向"停止"方向降一档（快进降档、倒带也降档），降到1x再点=停止，不会跨进反向
      let prevIdx = this.timeStore.timeSpeedIndex
      if (this.timeStore.timeSpeedIndex > TIME_SPEED_IDX_STOP) {
        prevIdx = this.timeStore.timeSpeedIndex - 1
      } else if (this.timeStore.timeSpeedIndex < TIME_SPEED_IDX_STOP) {
        prevIdx = this.timeStore.timeSpeedIndex + 1
      }
      this.applySpeedStep(prevIdx)
      this.hooks.flashHint(prevIdx === TIME_SPEED_IDX_STOP ? I18n.t('s0761_stop') : I18n.t('s0759_slower') + ' ' + this.timeStore.timeRateText)
      this.refreshTimeNow()
    } else if (id === '+12h') {
      this.advanceTime(12)
    } else if (id === '-12h') {
      this.advanceTime(-12)
    } else if (id === 'sunRise' || id === 'sunTransit' || id === 'sunSet' || id === 'astronomicalSet') {
      this.jumpToTimeMark(id)
    } else if (id === 'Moon') {
      this.hooks.searchObject('Moon')
    } else if (id === 'Mars') {
      this.hooks.searchObject('Mars')
    } else if (id === 'Jupiter') {
      this.hooks.searchObject('Jupiter')
    } else if (id.startsWith('city_')) {
      const cityId = id.substring(5)
      const preset = getCityPreset(cityId)
      if (preset !== undefined) {
        this.hooks.setLocation(cityId, preset.lat, preset.lon, preset.alt)
      }
    } else if (id === 'Beijing') {
      this.hooks.setLocation('Beijing', 39.9042, 116.4074, 44)
    } else if (id === 'Sun' || id === 'Mercury' || id === 'Venus' || id === 'Saturn' || id === 'Sirius' || id === 'Vega' || id === 'Betelgeuse' || id === 'Polaris' || id === 'M31' || id === 'M42' || id === 'M45' || id === 'NGC 2244') {
      this.hooks.searchObject(id)
    // 方向快捷查看
    } else if (id === 'east') {
      this.hooks.stopTracking(); this.hooks.triggerAction('actionLook_Towards_East'); this.hooks.refreshState(); this.hooks.flashHint(I18n.t('i0084'))
    } else if (id === 'south') {
      this.hooks.stopTracking(); this.hooks.triggerAction('actionLook_Towards_South'); this.hooks.refreshState(); this.hooks.flashHint(I18n.t('i0085'))
    } else if (id === 'west') {
      this.hooks.stopTracking(); this.hooks.triggerAction('actionLook_Towards_West'); this.hooks.refreshState(); this.hooks.flashHint(I18n.t('i0086'))
    } else if (id === 'north') {
      this.hooks.stopTracking(); this.hooks.triggerAction('actionLook_Towards_North'); this.hooks.refreshState(); this.hooks.flashHint(I18n.t('i0087'))
    } else if (id === 'zenith') {
      this.hooks.stopTracking(); this.hooks.triggerAction('actionLook_Towards_Zenith'); this.hooks.refreshState(); this.hooks.flashHint(I18n.t('i0088'))
    } else if (id === 'ncp') {
      this.hooks.stopTracking(); this.hooks.triggerAction('actionLook_Towards_NCP'); this.hooks.refreshState(); this.hooks.flashHint(I18n.t('i0089'))
    }
  }
}
