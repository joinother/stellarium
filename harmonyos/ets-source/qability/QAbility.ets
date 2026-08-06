import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import QAbilityStage from '../qabilitystage/QAbilityStage';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import Window from '@ohos.window'
import hilog from '@ohos.hilog';
import qpa from 'libqohos.so';
import { command } from 'libentry.so';
import { notifyLifecycle } from '../common/StellariumLifecycle';
import {LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';
import { requestPrivacyConsent } from './PrivacyConsent';

export default class QAbility extends UIAbility {

  private pendingWant: Want | null = null;
  private pendingLaunchParam: AbilityConstant.LaunchParam | null = null;
  private pendingWindowStage: Window.WindowStage | null = null;
  private privacyRequestStarted: boolean = false;
  private privacyAccepted: boolean = false;
  private qtAbilityCreated: boolean = false;
  private qtInitialized: boolean = false;
  private isForeground: boolean = true;

  private async requestPrivacyThenStart(): Promise<void> {
    if (this.privacyRequestStarted || this.privacyAccepted || this.qtInitialized || this.pendingWindowStage === null) {
      return;
    }

    this.privacyRequestStarted = true;
    const accepted = await requestPrivacyConsent(this.context);
    this.privacyRequestStarted = false;
    if (!accepted) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy consent was not accepted; Qt startup remains blocked');
      return;
    }

    this.privacyAccepted = true;
    // The system consent dialog resolves before its dismissal animation ends.
    await new Promise<void>((resolve) => setTimeout(resolve, 300));
    hilog.info(LOG_DOMAIN, LOG_TAG, 'System privacy dialog dismissed; starting Qt window hand-off');
    this.startQtIfReady();
  }

  private async requestPrivacyAfterWindowReady(windowStage: Window.WindowStage): Promise<void> {
    await this.enterImmersive(windowStage);
    await this.requestPrivacyThenStart();
  }

  private initializeQtAbilityIfNeeded(): void {
    if (this.qtAbilityCreated || this.pendingWant === null || this.pendingLaunchParam === null) {
      return;
    }

    // Keep all Qt initialization after the system privacy decision. The native
    // application bootstrap can load platform services, so hiding its window is
    // not sufficient for the AppGallery pre-consent requirement.
    QAbilityStage.initQtAppContextIfNeeded(this.context.getApplicationContext());
    qpa.handleAbilityOnCreate(this, this.pendingWant, this.pendingLaunchParam);
    this.qtAbilityCreated = true;
  }

  private startQtIfReady(): void {
    if (!this.privacyAccepted || this.qtInitialized || this.pendingWant === null ||
      this.pendingLaunchParam === null || this.pendingWindowStage === null || !this.isForeground) {
      return;
    }

    this.qtInitialized = true;
    try {
      this.initializeQtAbilityIfNeeded();
      if (!this.qtAbilityCreated) {
        this.qtInitialized = false;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Qt startup deferred because Ability initialization is incomplete');
        return;
      }
      qpa.handleAbilityOnWindowStageCreate(this, this.pendingWindowStage);
      qpa.handleAbilityOnForeground(this);
    } catch (err) {
      // Keep the ability alive if the native bridge reports a synchronous
      // startup error, so the consent page does not turn into a home-screen flash.
      this.qtInitialized = false;
      hilog.error(LOG_DOMAIN, LOG_TAG, `Qt startup hand-off failed: ${JSON.stringify(err)}`);
      return;
    }
    notifyLifecycle(true);
    try {
      command('setApplicationForeground', '1');
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'QAbility::startQtIfReady lifecycle bridge unavailable');
    }
    this.enterImmersive(this.pendingWindowStage);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Qt startup completed after privacy consent');
  }

  private async enterImmersive(windowStage: Window.WindowStage): Promise<void> {
    try {
      const mainWindow = await windowStage.getMainWindow();
      // Qt replaces the ArkUI content asynchronously after consent. Keep the
      // native window opaque during that hand-off so the launcher cannot flash.
      mainWindow.setWindowBackgroundColor('#070b12');
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
    this.pendingWant = want;
    this.pendingLaunchParam = launchParam;
  }

  onDestroy(): void | Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onDestroy()');
    if (this.qtAbilityCreated) {
      return qpa.handleAbilityOnDestroy(this);
    }
  }

  onPrepareToTerminate(): boolean {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminate()');
    return this.qtAbilityCreated ? qpa.handleAbilityOnPrepareToTerminate(this) : false;
  }

  onPrepareToTerminateAsync(): Promise<boolean> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminateAsync()');
    return this.qtAbilityCreated ? qpa.handleAbilityOnPrepareToTerminateAsync(this) : Promise.resolve(false);
  }

  onWindowStageCreate(windowStage: Window.WindowStage) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onWindowStageCreate(): this.launchWant.parameters: ' + JSON.stringify(this.launchWant.parameters));
    this.pendingWindowStage = windowStage;
    void this.requestPrivacyAfterWindowReady(windowStage);
  }

  onWindowStageRestore(windowStage: Window.WindowStage): void {
    this.pendingWindowStage = windowStage;
    if (this.qtInitialized) {
      qpa.handleAbilityOnWindowStageRestore(this, windowStage);
      this.enterImmersive(windowStage);
    } else {
      void this.requestPrivacyAfterWindowReady(windowStage);
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onNewWant(): want.parameters: ' + JSON.stringify(want.parameters));
    this.pendingWant = want;
    this.pendingLaunchParam = launchParam;
    if (this.qtAbilityCreated) {
      qpa.handleAbilityOnNewWant(this, want, launchParam);
    }
  }

  onForeground() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onForeground()');
    this.isForeground = true;
    if (!this.qtInitialized) {
      this.startQtIfReady();
      return;
    }
    qpa.handleAbilityOnForeground(this);
    notifyLifecycle(true);
    try {
      command('setApplicationForeground', '1');
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'QAbility::onForeground lifecycle bridge unavailable');
    }
    if (this.context.windowStage) {
      this.enterImmersive(this.context.windowStage);
    }
  }

  onBackground() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onBackground()');
    this.isForeground = false;
    if (!this.qtInitialized) {
      return;
    }
    // Release page-owned sensor subscriptions before Qt transitions hidden.
    notifyLifecycle(false);
    try {
      command('setApplicationForeground', '0');
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'QAbility::onBackground lifecycle bridge unavailable');
    }
    qpa.handleAbilityOnBackground(this);
  }

  onWindowStageDestroy() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onStageDestroy()');
    if (this.qtInitialized) {
      qpa.handleAbilityOnWindowStageDestroy(this);
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult | Promise<AbilityConstant.OnContinueResult> {
    return this.qtAbilityCreated
      ? qpa.handleAbilityOnContinue(this, wantParam)
      : AbilityConstant.OnContinueResult.REJECT;
  }
}
