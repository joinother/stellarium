import common from '@ohos.app.ability.common'
import { hasCurrentPrivacyConsent, requestPrivacyConsent } from '../qability/PrivacyConsent'
import { I18n } from './I18n'
import hilog from '@ohos.hilog'
import { notifyConsentAccepted } from '../common/PrivacyStartup'

@Component
export struct PrivacyBootstrap {
  @Watch('onHostReady')
  @StorageLink('stellariumPrivacyHostReady')
  private hostReady: boolean = false
  @State private requesting: boolean = false
  @State private requestFailed: boolean = false
  private consentCompleted: boolean = false

  aboutToAppear(): void {
    AppStorage.setOrCreate('i18nLang', I18n.systemLanguage())
    this.onHostReady()
  }

  private onHostReady(): void {
    if (this.hostReady) void this.requestConsent()
  }

  private async requestConsent(): Promise<void> {
    if (!this.hostReady || this.requesting || this.consentCompleted) return
    this.requesting = true
    this.requestFailed = false
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      const consent = await requestPrivacyConsent(context)
      if (!consent.accepted || !hasCurrentPrivacyConsent()) {
        this.requestFailed = true
        return
      }
      this.consentCompleted = true
      notifyConsentAccepted()
    } catch (error) {
      this.requestFailed = true
      hilog.error(0, 'StellariumPrivacy', `[privacy-probe] phase=privacy-host-transfer-failed code=${(error as Error).message}`)
    } finally {
      if (!this.consentCompleted) this.requesting = false
    }
  }

  build() {
    Column({ space: 20 }) {
      if (this.requestFailed) {
        Text(I18n.t('privacy_start_required'))
          .fontSize(16).fontColor('#D8E7F3').textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: 420 }).padding({ left: 24, right: 24 })
        Button(I18n.t('privacy_start_retry')).onClick(() => { void this.requestConsent() })
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
      .hitTestBehavior(this.requestFailed ? HitTestMode.Default : HitTestMode.Transparent)
  }
}
