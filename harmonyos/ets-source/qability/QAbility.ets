import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import QAbilityStage from '../qabilitystage/QAbilityStage';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import Window from '@ohos.window'
import hilog from '@ohos.hilog';
import preferences from '@ohos.data.preferences';
import qpa from 'libqohos.so';
import {LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';

export default class QAbility extends UIAbility {

  private localStorage: LocalStorage | null = null;
  private static readonly PRIVACY_STORE = 'stellarium_privacy';
  private static readonly PRIVACY_ACCEPTED_KEY = 'accepted_version';
  private initialWant: Want | undefined = undefined;
  private initialLaunchParam: AbilityConstant.LaunchParam | undefined = undefined;
  private initialWindowStage: Window.WindowStage | undefined = undefined;
  private qtStarted: boolean = false;
  private windowStageAttached: boolean = false;

  private async enterImmersive(windowStage: Window.WindowStage): Promise<void> {
    try {
      const mainWindow = await windowStage.getMainWindow();
      await mainWindow.setWindowLayoutFullScreen(true);
      await mainWindow.setWindowSystemBarEnable([]);
      if (canIUse('SystemCapability.Window.SessionManager')) {
        await mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false);
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::enterImmersive() success');
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility::enterImmersive() failed: ' + JSON.stringify(err));
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): want.parameters: ' + JSON.stringify(want.parameters));
    this.initialWant = want;
    this.initialLaunchParam = launchParam;
  }

  private async hasAcceptedPrivacyPolicy(): Promise<boolean> {
    const store = await preferences.getPreferences(this.context, QAbility.PRIVACY_STORE);
    return store.getSync(QAbility.PRIVACY_ACCEPTED_KEY, '') === '1.0';
  }

  private async rememberPrivacyAcceptance(): Promise<void> {
    const store = await preferences.getPreferences(this.context, QAbility.PRIVACY_STORE);
    store.putSync(QAbility.PRIVACY_ACCEPTED_KEY, '1.0');
    await store.flush();
  }

  private async showPrivacyConsent(): Promise<void> {
    if (await this.hasAcceptedPrivacyPolicy()) {
      this.startQtAfterPrivacyConsent();
      return;
    }
    if (this.initialWindowStage === undefined) {
      return;
    }
    this.localStorage = new LocalStorage({
      privacyConsentCallbacks: {
        onAcceptPrivacy: async (): Promise<void> => {
          await this.rememberPrivacyAcceptance();
          this.startQtAfterPrivacyConsent();
        }
      }
    });
    await this.initialWindowStage.loadContent('pages/PrivacyConsent', this.localStorage);
  }

  private startQtAfterPrivacyConsent(): void {
    if (this.qtStarted || this.initialWant === undefined || this.initialLaunchParam === undefined) {
      return;
    }
    this.qtStarted = true;
    QAbilityStage.initQtAppContextIfNeeded(this.context.getApplicationContext());
    QAbilityStage.handleStageCreateAfterPrivacyConsent();
    qpa.handleAbilityOnCreate(this, this.initialWant, this.initialLaunchParam);
    if (this.initialWindowStage !== undefined) {
      this.attachQtWindowStage(this.initialWindowStage);
    }
  }

  private attachQtWindowStage(windowStage: Window.WindowStage): void {
    if (!this.qtStarted || this.windowStageAttached) {
      return;
    }
    this.windowStageAttached = true;
    qpa.handleAbilityOnWindowStageCreate(this, windowStage);
    this.enterImmersive(windowStage);
  }

  onDestroy(): void | Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onDestroy()');
    return this.qtStarted ? qpa.handleAbilityOnDestroy(this) : undefined;
  }

  onPrepareToTerminate(): boolean {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminate()');
    return this.qtStarted ? qpa.handleAbilityOnPrepareToTerminate(this) : false;
  }

  onPrepareToTerminateAsync(): Promise<boolean> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminateAsync()');
    return this.qtStarted ? qpa.handleAbilityOnPrepareToTerminateAsync(this) : Promise.resolve(false);
  }

  onWindowStageCreate(windowStage: Window.WindowStage) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onWindowStageCreate(): this.launchWant.parameters: ' + JSON.stringify(this.launchWant.parameters));
    this.initialWindowStage = windowStage;
    this.showPrivacyConsent();
  }

  onWindowStageRestore(windowStage: Window.WindowStage): void {
    if (this.qtStarted) {
      qpa.handleAbilityOnWindowStageRestore(this, windowStage);
      this.enterImmersive(windowStage);
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onNewWant(): want.parameters: ' + JSON.stringify(want.parameters));
    if (this.qtStarted) {
      qpa.handleAbilityOnNewWant(this, want, launchParam);
    }
  }

  onForeground() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onForeground()');
    if (this.qtStarted) {
      qpa.handleAbilityOnForeground(this);
    }
    if (this.qtStarted && this.context.windowStage) {
      this.enterImmersive(this.context.windowStage);
    }
  }

  onBackground() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onBackground()');
    if (this.qtStarted) {
      qpa.handleAbilityOnBackground(this);
    }
  }

  onWindowStageDestroy() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onStageDestroy()');
    if (this.qtStarted) {
      qpa.handleAbilityOnWindowStageDestroy(this);
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult | Promise<AbilityConstant.OnContinueResult> {
    return this.qtStarted ? qpa.handleAbilityOnContinue(this, wantParam) : AbilityConstant.OnContinueResult.REJECT;
  }
}
