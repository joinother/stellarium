import type common from '@ohos.app.ability.common'
import preferences from '@ohos.data.preferences'
import systemDateTime from '@ohos.systemDateTime'
import { vibrator } from '@kit.SensorServiceKit'
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent'
import { HapticFeedback, HapticDriver, HapticPreferences, HapticGuard } from './HapticFeedback'

export const HAPTIC_PREFERENCES_STORE: string = 'stellarium_haptics'
export const HAPTIC_ENABLED_KEY: string = 'enabled_v1'

class HarmonyHapticDriver implements HapticDriver {
  async supports(effectId: string): Promise<boolean> {
    if (!canIUse('SystemCapability.Sensors.MiscDevice')) return false
    return vibrator.isSupportEffect(effectId)
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
    return this.store().getSync(HAPTIC_ENABLED_KEY, false) === true
  }

  async writeEnabled(enabled: boolean): Promise<void> {
    const store = this.store()
    store.putSync(HAPTIC_ENABLED_KEY, enabled)
    try {
      await store.flush()
    } catch (error) {
      store.putSync(HAPTIC_ENABLED_KEY, false)
      throw new Error(String(error))
    }
  }
}

class HarmonyHapticGuard implements HapticGuard {
  hasConsent(): boolean { return hasCurrentPrivacyConsent() }
  now(): number { return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false) }
}

export function createHapticFeedback(context: common.Context): HapticFeedback {
  return new HapticFeedback(new HarmonyHapticDriver(), new HarmonyHapticPreferences(context), new HarmonyHapticGuard())
}
