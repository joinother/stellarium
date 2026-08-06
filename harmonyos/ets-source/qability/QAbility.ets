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
  private privacyHandoffSequence: number = 0;
  private windowStageTracerAttached: boolean = false;

  // Records the system-dialog-to-Qt hand-off without changing its timing.
  private tracePrivacyHandoff(event: string): void {
    this.privacyHandoffSequence++;
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      `[privacy-handoff #${this.privacyHandoffSequence} t=${Date.now()}] ${event}; foreground=${this.isForeground}; qtInitialized=${this.qtInitialized}`,
    );
  }

  private async requestPrivacyThenStart(): Promise<void> {
    if (this.privacyRequestStarted || this.privacyAccepted || this.qtInitialized || this.pendingWindowStage === null) {
      return;
    }

    this.privacyRequestStarted = true;
    this.tracePrivacyHandoff('requesting official Privacy Manager consent');
    const consent = await requestPrivacyConsent(this.context);
    this.tracePrivacyHandoff(
      `official Privacy Manager returned accepted=${consent.accepted}; dialogShown=${consent.dialogShown}`,
    );
    this.privacyRequestStarted = false;
    if (!consent.accepted) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy consent was not accepted; Qt startup remains blocked');
      return;
    }

    if (consent.dialogShown) {
      await this.restoreHostWindowAfterPrivacy();
    }
    this.privacyAccepted = true;
    this.tracePrivacyHandoff('privacy accepted; starting Qt in one lifecycle hand-off');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Privacy consent accepted; starting Qt');
    this.startQtIfReady();
  }

  // Privacy Manager is hosted as a system UIExtension. On some devices its
  // dismissal leaves the host ability temporarily backgrounded. Re-show the
  // already-loaded, opaque bootstrap window before handing it to Qt.
  private async restoreHostWindowAfterPrivacy(): Promise<void> {
    if (this.pendingWindowStage === null) {
      return;
    }
    try {
      this.tracePrivacyHandoff('restoring host window after official dialog');
      const mainWindow = await this.pendingWindowStage.getMainWindow();
      mainWindow.setWindowBackgroundColor('#070b12');
      await mainWindow.showWindow();
      this.isForeground = true;
      this.tracePrivacyHandoff('host window restored after official dialog');
    } catch (err) {
      this.tracePrivacyHandoff(`host window restore failed: ${JSON.stringify(err)}`);
      // Error 1300002 is returned when the system has already restored this
      // window. Consent is valid, so do not turn that harmless state into an
      // infinite launch-screen wait.
      this.isForeground = true;
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Host window restore was unavailable; continuing Qt startup');
    }
  }

  private async requestPrivacyAfterWindowReady(windowStage: Window.WindowStage): Promise<void> {
    await this.enterImmersive(windowStage);
    await this.requestPrivacyThenStart();
  }

  private initializeQtAbilityIfNeeded(): void {
    if (this.qtAbilityCreated || this.pendingWant === null || this.pendingLaunchParam === null) {
      return;
    }

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
      // API 22's Qt plugin expects creation, window-stage attachment, and the
      // first foreground transition to be one contiguous lifecycle sequence.
      // Deferring the native node until after consent leaves its application
      // library unloaded on some physical API 22 devices.
      this.tracePrivacyHandoff('creating Qt application after privacy consent');
      this.initializeQtAbilityIfNeeded();
      if (!this.qtAbilityCreated) {
        this.qtInitialized = false;
        return;
      }
      AppStorage.setOrCreate('stellariumPrivacyNativeStartupAllowed', true);
      this.tracePrivacyHandoff('attaching Qt window stage after privacy consent');
      qpa.handleAbilityOnWindowStageCreate(this, this.pendingWindowStage);
      this.tracePrivacyHandoff('asking Qt bridge to enter foreground');
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
    this.tracePrivacyHandoff('Qt hand-off calls completed');
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
    if (!this.windowStageTracerAttached) {
      try {
        windowStage.on('windowStageEvent', (event: Window.WindowStageEventType) => {
          this.tracePrivacyHandoff(`window stage event=${event}`);
        });
        this.windowStageTracerAttached = true;
      } catch (err) {
        this.tracePrivacyHandoff(`unable to attach window stage tracer: ${JSON.stringify(err)}`);
      }
    }
    this.tracePrivacyHandoff('UIAbility window stage created');
    void this.requestPrivacyAfterWindowReady(windowStage);
  }

  onWindowStageRestore(windowStage: Window.WindowStage): void {
    this.pendingWindowStage = windowStage;
    this.tracePrivacyHandoff('UIAbility window stage restored');
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
    this.tracePrivacyHandoff('UIAbility onForeground');
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
    this.tracePrivacyHandoff('UIAbility onBackground');
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
    this.tracePrivacyHandoff('UIAbility window stage destroyed');
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
