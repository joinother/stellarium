import type common from '@ohos.app.ability.common'
import preferences from '@ohos.data.preferences'
import systemDateTime from '@ohos.systemDateTime'
import { settings } from '@kit.BasicServicesKit'
import { vibrator } from '@kit.SensorServiceKit'
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent'
import { HapticFeedback, HapticDriver, HapticPreferences, HapticGuard, DEFAULT_HAPTIC_ENABLED, DEFAULT_HAPTIC_INTENSITY } from './HapticFeedback'

export const HAPTIC_PREFERENCES_STORE: string = 'stellarium_haptics'
export const HAPTIC_ENABLED_KEY: string = 'enabled_v1'
export const HAPTIC_INTENSITY_KEY: string = 'intensity_v1'
// OpenHarmony 的 VibrationPriorityManager 读取同一个系统设置键来决定是否
// 丢弃 usage=touch 的请求（IGNORE_FEEDBACK / 14600101）。
const SYSTEM_HAPTIC_FEEDBACK_KEY: string = 'physic_navi_haptic_feedback_enabled'

class HarmonyHapticDriver implements HapticDriver {
  private context: common.Context

  constructor(context: common.Context) { this.context = context }

  async supports(effectId: string): Promise<boolean> {
    if (!canIUse('SystemCapability.Sensors.MiscDevice')) return false
    return vibrator.isSupportEffect(effectId)
  }

  async feedbackMode(): Promise<boolean | undefined> {
    try {
      let value = settings.getValueSync(this.context, SYSTEM_HAPTIC_FEEDBACK_KEY, '')
      if (value !== '0' && value !== '1') {
        value = settings.getValueSync(this.context, SYSTEM_HAPTIC_FEEDBACK_KEY, '', settings.domainName.DEVICE_SHARED)
      }
      if (value === '1') return true
      if (value === '0') return false
      return undefined
    } catch (_) {
      return undefined
    }
  }

  async start(effectId: string, intensity: number): Promise<void> {
    const effect: vibrator.VibratePreset = { type: 'preset', effectId: effectId, count: 1, intensity: intensity }
    const attribute: vibrator.VibrateAttribute = { usage: 'touch' }
    await vibrator.startVibration(effect, attribute)
  }

  async stop(): Promise<void> {
    await vibrator.stopVibration(vibrator.VibratorStopMode.VIBRATOR_STOP_MODE_PRESET)
  }
}

class HarmonyHapticPreferences implements HapticPreferences {
  private context: common.Context

  constructor(context: common.Context) { this.context = context }

  private store(): preferences.Preferences {
    return preferences.getPreferencesSync(this.context, { name: HAPTIC_PREFERENCES_STORE })
  }

  async readEnabled(): Promise<boolean> {
    return this.store().getSync(HAPTIC_ENABLED_KEY, DEFAULT_HAPTIC_ENABLED) === true
  }

  async writeEnabled(enabled: boolean): Promise<void> {
    const store = this.store()
    const previous = store.getSync(HAPTIC_ENABLED_KEY, DEFAULT_HAPTIC_ENABLED) === true
    store.putSync(HAPTIC_ENABLED_KEY, enabled)
    try {
      await store.flush()
    } catch (error) {
      // 只回滚到写入前的值，不能无条件写 false：默认已改为开启，
      // 失败回滚 false 会把后续读取带偏。
      store.putSync(HAPTIC_ENABLED_KEY, previous)
      throw new Error(String(error))
    }
  }

  async readIntensity(): Promise<number> {
    return Number(this.store().getSync(HAPTIC_INTENSITY_KEY, DEFAULT_HAPTIC_INTENSITY))
  }

  async writeIntensity(intensity: number): Promise<void> {
    const store = this.store()
    const previous = Number(store.getSync(HAPTIC_INTENSITY_KEY, DEFAULT_HAPTIC_INTENSITY))
    store.putSync(HAPTIC_INTENSITY_KEY, intensity)
    try {
      await store.flush()
    } catch (error) {
      store.putSync(HAPTIC_INTENSITY_KEY, previous)
      throw new Error(String(error))
    }
  }

}

class HarmonyHapticGuard implements HapticGuard {
  hasConsent(): boolean { return hasCurrentPrivacyConsent() }
  now(): number { return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false) }
}

export function createHapticFeedback(context: common.Context): HapticFeedback {
  return new HapticFeedback(new HarmonyHapticDriver(context), new HarmonyHapticPreferences(context), new HarmonyHapticGuard())
}
