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
  private qtWindowPrepared: boolean = false;
  private privacyWaitingForSystemForeground: boolean = false;
  private privacyHandoffGeneration: number = 0;

  // Records the system-dialog-to-Qt hand-off without changing its timing.
  private tracePrivacyHandoff(event: string): void {
    this.privacyHandoffSequence++;
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      `[privacy-handoff #${this.privacyHandoffSequence} t=${Date.now()}] ${event}; foreground=${this.isForeground}; qtInitialized=${this.qtInitialized}`,
    );
  }

  private waitForStablePrivacyReturn(): void {
    // On physical devices the Privacy Manager promise can resolve before the
    // system sends the matching background/foreground lifecycle pair. Starting
    // Qt in that short gap exposes Home for one frame. Wait for the restored
    // foreground callback instead. The fallback only covers devices which do
    // not emit that pair, so they cannot remain on PrivacyBootstrap forever.
    this.privacyWaitingForSystemForeground = true;
    const generation = ++this.privacyHandoffGeneration;
    this.tracePrivacyHandoff('privacy accepted; waiting for stable system foreground');
    setTimeout(() => {
      if (generation !== this.privacyHandoffGeneration ||
        !this.privacyWaitingForSystemForeground || !this.isForeground || this.qtInitialized) {
        return;
      }
      this.privacyWaitingForSystemForeground = false;
      this.tracePrivacyHandoff('privacy foreground callback absent; stable-return fallback starting Qt');
      this.startQtIfReady();
    }, 1000);
  }

  private startQtAfterStablePrivacyForeground(): void {
    const generation = ++this.privacyHandoffGeneration;
    this.privacyWaitingForSystemForeground = false;
    // Allow the system to restore the opaque ArkUI host before Qt replaces it.
    setTimeout(() => {
      if (generation !== this.privacyHandoffGeneration || !this.isForeground || this.qtInitialized) {
        return;
      }
      this.tracePrivacyHandoff('stable privacy foreground restored; starting Qt');
      this.startQtIfReady();
    }, 80);
  }

  private prepareQtWindowForPrivacy(windowStage: Window.WindowStage): boolean {
    if (this.qtWindowPrepared) {
      return true;
    }

    try {
      // Keep the final ArkUI page as the window root while the system-owned
      // consent sheet is shown. Its native XComponent stays absent until the
      // AppStorage switch is released after consent, so Stellarium itself does
      // not start before the official Privacy Manager decision.
      AppStorage.setOrCreate('stellariumPrivacyNativeStartupAllowed', false);
      this.initializeQtAbilityIfNeeded();
      if (!this.qtAbilityCreated) {
        return false;
      }
      this.tracePrivacyHandoff('preparing final Qt window page before Privacy Manager');
      qpa.handleAbilityOnWindowStageCreate(this, windowStage);
      this.qtWindowPrepared = true;
      this.tracePrivacyHandoff('final Qt window page prepared with native startup blocked');
      return true;
    } catch (err) {
      this.tracePrivacyHandoff(`preparing final Qt window page failed: ${JSON.stringify(err)}`);
      hilog.error(LOG_DOMAIN, LOG_TAG, `Qt window preparation failed: ${JSON.stringify(err)}`);
      return false;
    }
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

    // IMPORTANT - Privacy Manager hand-off on physical devices:
    // Do not start Qt directly from the request promise. Privacy Manager may
    // resolve before its background/foreground lifecycle pair reaches us.
    // Do not call mainWindow.showWindow(), recreate the window stage, or
    // change Qt/native libraries to work around that state.
    this.privacyAccepted = true;
    if (consent.dialogShown) {
      this.waitForStablePrivacyReturn();
      return;
    }
    this.tracePrivacyHandoff('privacy was already accepted; starting Qt');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Privacy consent accepted; starting Qt');
    this.startQtIfReady();
  }

  private async requestPrivacyAfterWindowReady(windowStage: Window.WindowStage): Promise<void> {
    if (!this.prepareQtWindowForPrivacy(windowStage)) {
      return;
    }

    await this.enterImmersive(windowStage);
    // qpa.handleAbilityOnWindowStageCreate schedules loadContent() internally.
    // Let MainWindowNativeNode become the opaque root before the Privacy
    // Manager extension covers it; never replace this page after consent.
    this.tracePrivacyHandoff('waiting for final Qt page before Privacy Manager request');
    await new Promise<void>((resolve) => setTimeout(resolve, 300));
    this.tracePrivacyHandoff('final Qt page delay complete; requesting Privacy Manager');
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
      if (!this.qtWindowPrepared) {
        this.qtInitialized = false;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Qt startup deferred because its final page is not prepared');
        return;
      }
      // The window root has already been prepared. This flips the only gate
      // that mounts the native XComponent, avoiding a second loadContent()
      // call and the one-frame launcher exposure on physical devices.
      AppStorage.setOrCreate('stellariumPrivacyNativeStartupAllowed', true);
      this.tracePrivacyHandoff('released prepared Qt native node after privacy consent');
      this.tracePrivacyHandoff('asking Qt bridge to enter foreground');
      qpa.handleAbilityOnForeground(this);
      this.tracePrivacyHandoff('Qt bridge entered foreground after privacy consent');
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
      if (this.qtWindowPrepared) {
        qpa.handleAbilityOnWindowStageRestore(this, windowStage);
      }
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
      if (this.privacyWaitingForSystemForeground) {
        this.startQtAfterStablePrivacyForeground();
        return;
      }
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
      if (this.privacyWaitingForSystemForeground) {
        // The system-owned consent UI has covered the host. Invalidate the
        // no-callback fallback and wait for its real foreground restoration.
        this.privacyHandoffGeneration++;
        this.tracePrivacyHandoff('privacy hand-off observed background; waiting for restore');
      }
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
    if (this.qtAbilityCreated) {
      qpa.handleAbilityOnWindowStageDestroy(this);
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult | Promise<AbilityConstant.OnContinueResult> {
    return this.qtAbilityCreated
      ? qpa.handleAbilityOnContinue(this, wantParam)
      : AbilityConstant.OnContinueResult.REJECT;
  }
}
