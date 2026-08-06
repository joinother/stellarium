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
  private qtWindowPrepared: boolean = false;
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

  private prepareQtWindowForPrivacy(windowStage: Window.WindowStage): boolean {
    if (this.qtWindowPrepared) {
      return true;
    }

    try {
      // Qt owns the final window page. Prepare that page before the system
      // privacy extension appears, but keep its native XComponent detached.
      // This preserves one opaque host page across the dialog hand-off while
      // keeping Stellarium's C++ application blocked before consent.
      AppStorage.setOrCreate('stellariumPrivacyNativeStartupAllowed', false);
      this.initializeQtAbilityIfNeeded();
      if (!this.qtAbilityCreated) {
        return false;
      }
      this.tracePrivacyHandoff('preparing deferred Qt window page');
      qpa.handleAbilityOnWindowStageCreate(this, windowStage);
      this.qtWindowPrepared = true;
      this.tracePrivacyHandoff('deferred Qt window page requested');
      return true;
    } catch (err) {
      this.tracePrivacyHandoff(`deferred Qt window preparation failed: ${JSON.stringify(err)}`);
      hilog.error(LOG_DOMAIN, LOG_TAG, `Deferred Qt window preparation failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private async requestPrivacyThenStart(): Promise<void> {
    if (this.privacyRequestStarted || this.privacyAccepted || this.qtInitialized || this.pendingWindowStage === null) {
      return;
    }

    this.privacyRequestStarted = true;
    this.tracePrivacyHandoff('requesting official Privacy Manager consent');
    const accepted = await requestPrivacyConsent(this.context);
    this.tracePrivacyHandoff(`official Privacy Manager returned accepted=${accepted}`);
    this.privacyRequestStarted = false;
    if (!accepted) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy consent was not accepted; Qt startup remains blocked');
      return;
    }

    if (!await this.restoreHostWindowAfterPrivacy()) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Privacy consent accepted but host window could not be restored');
      return;
    }
    this.privacyAccepted = true;
    this.tracePrivacyHandoff('privacy accepted; releasing prepared Qt window');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Privacy consent accepted; releasing prepared Qt window');
    this.startQtIfReady();
  }

  // Privacy Manager is hosted as a system UIExtension. On some devices its
  // dismissal leaves the host ability temporarily backgrounded. Re-show the
  // already-loaded, opaque bootstrap window before handing it to Qt.
  private async restoreHostWindowAfterPrivacy(): Promise<boolean> {
    if (this.pendingWindowStage === null) {
      return false;
    }
    try {
      this.tracePrivacyHandoff('restoring host window after official dialog');
      const mainWindow = await this.pendingWindowStage.getMainWindow();
      mainWindow.setWindowBackgroundColor('#070b12');
      await mainWindow.showWindow();
      this.isForeground = true;
      this.tracePrivacyHandoff('host window restored after official dialog');
      return true;
    } catch (err) {
      this.tracePrivacyHandoff(`host window restore failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private async requestPrivacyAfterWindowReady(windowStage: Window.WindowStage): Promise<void> {
    if (!this.prepareQtWindowForPrivacy(windowStage)) {
      return;
    }
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
      if (!this.qtWindowPrepared) {
        this.qtInitialized = false;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Qt startup deferred because its window page is not prepared');
        return;
      }
      // MainWindowNativeNode is already the window root. Its native
      // XComponent is mounted only when this AppStorage switch changes, so no
      // second windowStage.loadContent() runs after the Privacy Manager exits.
      this.tracePrivacyHandoff('releasing deferred Qt native node');
      AppStorage.setOrCreate('stellariumPrivacyNativeStartupAllowed', true);
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
