import common from '@ohos.app.ability.common'
import { hasCurrentPrivacyConsent, requestPrivacyConsent } from '../qability/PrivacyConsent'
import { I18n } from './I18n'
import hilog from '@ohos.hilog'
import { notifyConsentAccepted } from '../common/PrivacyStartup'
import { commonEventManager } from '@kit.BasicServicesKit'
import { slotsForNightMode, ThemeSlots } from '../state/StellariumTheme'

@Component
export struct PrivacyBootstrap {
  @Prop nightMode: boolean = false
  @Watch('onHostReady')
  @StorageLink('stellariumPrivacyHostReady')
  private hostReady: boolean = false
  @State private requesting: boolean = false
  @State private requestFailed: boolean = false
  @State private helpAvailable: boolean = false
  @State private errorCode: number = 0
  private consentCompleted: boolean = false
  private observationStarted: boolean = false
  private disposed: boolean = false
  private subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined
  private lastRequestAt: number = 0
  private helpTimer: number = -1

  aboutToAppear(): void {
    AppStorage.setOrCreate('i18nLang', I18n.systemLanguage())
    this.onHostReady()
  }

  private onHostReady(): void {
    if (!this.hostReady || this.observationStarted || this.disposed) return
    this.observationStarted = true
    void this.observeSystemConsent()
  }

  private finishVerifiedConsent(): boolean {
    if (this.disposed || this.consentCompleted) return this.consentCompleted
    if (!hasCurrentPrivacyConsent()) return false
    this.consentCompleted = true
    this.requestFailed = false
    this.helpAvailable = false
    this.errorCode = 0
    this.requesting = false
    this.clearHelpTimer()
    AppStorage.setOrCreate('stellariumPrivacyConsentVerifiedUi', true)
    hilog.info(0, 'StellariumPrivacy', '[privacy-probe] phase=hosted-consent-verified')
    notifyConsentAccepted()
    return true
  }

  private async observeSystemConsent(): Promise<void> {
    try {
      const subscriber = await commonEventManager.createSubscriber({
        events: ['usual.event.PRIVACY_STATE_CHANGED']
      })
      if (this.disposed) return
      this.subscriber = subscriber
      commonEventManager.subscribe(subscriber, (error) => {
        if (this.disposed) return
        if (error) {
          hilog.warn(0, 'StellariumPrivacy', `[privacy-probe] phase=consent-event-error code=${error.code}`)
          return
        }
        hilog.info(0, 'StellariumPrivacy', '[privacy-probe] phase=consent-state-event')
        this.finishVerifiedConsent()
      })
      hilog.info(0, 'StellariumPrivacy', '[privacy-probe] phase=system-consent-observer-ready; automaticDialogRequest=false')
    } catch (error) {
      hilog.error(0, 'StellariumPrivacy', `[privacy-probe] phase=consent-observer-failed message=${(error as Error).message}`)
      if (!this.disposed && !this.finishVerifiedConsent()) {
        this.errorCode = -1
        this.requestFailed = true
      }
    }
    if (!this.disposed && !this.finishVerifiedConsent()) {
      this.helpTimer = setTimeout(() => {
        this.helpTimer = -1
        if (!this.disposed && !this.finishVerifiedConsent()) this.helpAvailable = true
      }, 15000)
    }
  }

  private clearHelpTimer(): void {
    if (this.helpTimer !== -1) clearTimeout(this.helpTimer)
    this.helpTimer = -1
  }

  aboutToDisappear(): void {
    this.disposed = true
    this.clearHelpTimer()
    const subscriber = this.subscriber
    this.subscriber = undefined
    if (subscriber !== undefined) {
      try {
        commonEventManager.unsubscribe(subscriber, (error) => {
          if (error) hilog.warn(0, 'StellariumPrivacy', `[privacy-probe] phase=consent-unsubscribe-failed code=${error.code}`)
        })
      } catch (error) {
        hilog.warn(0, 'StellariumPrivacy', `[privacy-probe] phase=consent-unsubscribe-failed message=${(error as Error).message}`)
      }
    }
  }

  private async requestConsent(): Promise<void> {
    if (!this.hostReady || this.requesting || this.consentCompleted || this.disposed) return
    if (Date.now() - this.lastRequestAt < 1500) return
    this.lastRequestAt = Date.now()
    this.requesting = true
    this.requestFailed = false
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      const consent = await requestPrivacyConsent(context)
      if (this.disposed || this.consentCompleted) return
      this.errorCode = consent.errorCode ?? 0
      if (!consent.accepted || !hasCurrentPrivacyConsent()) {
        this.requestFailed = true
        return
      }
      this.finishVerifiedConsent()
    } catch (error) {
      if (this.disposed || this.consentCompleted) return
      this.errorCode = -1
      this.requestFailed = true
      hilog.error(0, 'StellariumPrivacy', `[privacy-probe] phase=privacy-host-transfer-failed code=${(error as Error).message}`)
    } finally {
      if (!this.consentCompleted) this.requesting = false
    }
  }

  private slots(): ThemeSlots {
    return slotsForNightMode(this.nightMode)
  }

  build() {
    Column({ space: 20 }) {
      if (this.requestFailed && !this.requesting) {
        Text(I18n.t(this.errorCode === 1006700003 ? 'privacy_service_unconfigured' :
          this.errorCode !== 0 ? 'privacy_service_unavailable' : 'privacy_start_required'))
          .fontSize(16).fontColor(this.slots().text).textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: 420 }).padding({ left: 24, right: 24 })
        if (this.errorCode > 0) {
          Text(`${this.errorCode}`).fontSize(12).fontColor(this.slots().sub)
        }
      }
      if (this.requestFailed || this.helpAvailable) {
        Button(I18n.t(this.errorCode !== 0 ? 'privacy_service_retry' : 'privacy_start_retry'))
          .enabled(!this.requesting)
          .onClick(() => { void this.requestConsent() })
        Button(I18n.t('privacy_start_exit')).onClick(() => {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext
          void context.terminateSelf()
        })
      }
    }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .padding({ bottom: 64 })
      .hitTestBehavior(this.requestFailed || this.helpAvailable ? HitTestMode.Default : HitTestMode.Transparent)
  }
}
