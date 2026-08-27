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
import { scheduleDeepSkyImageExtraction, setDeepSkyImageExtractionForeground } from './StellariumResourceBootstrap';

interface StellariumCliRequest {
  commandName: string;
  payload: string;
  requestId: string;
  attempts: number;
}

export default class QAbility extends UIAbility {

  private pendingWant: Want | null = null;
  private pendingLaunchParam: AbilityConstant.LaunchParam | null = null;
  private pendingWindowStage: Window.WindowStage | null = null;
  private privacyRequestStarted: boolean = false;
  private privacyAccepted: boolean = false;
  private qtAbilityCreated: boolean = false;
  private qtInitialized: boolean = false;
  private isForeground: boolean = true;
  private qtWindowPrepared: boolean = false;
  private privacyWaitingForSystemForeground: boolean = false;
  private privacyHandoffBackgroundObserved: boolean = false;
  private privacyHandoffGeneration: number = 0;
  private cliRequests: StellariumCliRequest[] = [];

  private isCliCommandName(value: string): boolean {
    return /^[A-Za-z][A-Za-z0-9_]*$/.test(value) && value.length <= 96;
  }

  private readCliString(parameters: Record<string, Object> | undefined, key: string): string {
    if (parameters === undefined) {
      return '';
    }
    const value = parameters[key];
    return typeof value === 'string' ? value : '';
  }

  private queueCliRequest(want: Want): void {
    const parameters = want.parameters as Record<string, Object> | undefined;
    const commandName = this.readCliString(parameters, 'skyinstrument.cli.command').trim();
    if (commandName.length === 0) {
      return;
    }
    if (!this.isCliCommandName(commandName)) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[cli] rejected invalid command name');
      return;
    }
    const encodedPayload = this.readCliString(parameters, 'skyinstrument.cli.payload');
    const payload = encodedPayload.startsWith('__STEL_CLI_PAYLOAD__')
      ? encodedPayload.substring('__STEL_CLI_PAYLOAD__'.length)
      : encodedPayload;
    if (payload.length > 32768) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[cli] rejected payload larger than 32768 bytes');
      return;
    }
    let requestId = this.readCliString(parameters, 'skyinstrument.cli.requestId').trim();
    if (!/^[A-Za-z0-9_.:-]{1,80}$/.test(requestId)) {
      requestId = `cli-${Date.now()}`;
    }
    if (this.cliRequests.some((request: StellariumCliRequest) => request.requestId === requestId)) {
      return;
    }
    this.cliRequests.push({ commandName: commandName, payload: payload, requestId: requestId, attempts: 0 });
    hilog.info(LOG_DOMAIN, LOG_TAG, '[cli] queued requestId=%{public}s command=%{public}s', requestId, commandName);
    this.drainCliRequests();
  }

  private isCliFireAndForget(commandName: string): boolean {
    return commandName === 'dragView' || commandName === 'zoomBy' || commandName === 'zoomStep' ||
      commandName === 'endPinch' || commandName === 'beginSkyGesture' || commandName === 'panBy' || commandName === 'moveToAltAz' ||
      commandName === 'setGyroView' || commandName === 'gyroDiagnostic' ||
      commandName === 'startPanInertia' || commandName === 'stopPanInertia';
  }

  private drainCliRequests(): void {
    if (!this.qtInitialized || this.cliRequests.length === 0) {
      return;
    }
    const request = this.cliRequests[0];
    request.attempts += 1;
    let rawResponse = '';
    try {
      rawResponse = command(request.commandName, request.payload);
    } catch (err) {
      this.finishCliRequest(request, JSON.stringify({ ok: false, error: String(err) }));
      return;
    }
    let response: Record<string, Object> = {};
    try {
      response = JSON.parse(rawResponse) as Record<string, Object>;
    } catch (err) {
      this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'invalid native response' }));
      return;
    }
    if (response['pending'] === true) {
      if (this.isCliFireAndForget(request.commandName)) {
        this.finishCliRequest(request, JSON.stringify({ ok: true, accepted: true, pending: true }));
        return;
      }
      if (request.attempts < 120) {
        setTimeout(() => this.drainCliRequests(), 80);
        return;
      }
      this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'command timeout', pending: true }));
      return;
    }
    this.finishCliRequest(request, rawResponse);
  }

  private finishCliRequest(request: StellariumCliRequest, response: string): void {
    if (this.cliRequests.length > 0 && this.cliRequests[0].requestId === request.requestId) {
      this.cliRequests.shift();
    } else {
      this.cliRequests = this.cliRequests.filter((item: StellariumCliRequest) => item.requestId !== request.requestId);
    }
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[cli-response] requestId=%{public}s command=%{public}s response=%{public}s',
      request.requestId, request.commandName, response);
    this.drainCliRequests();
  }

  private logPrivacyGate(stage: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[privacy-gate] ${stage}; accepted=${this.privacyAccepted}; qtAbilityCreated=${this.qtAbilityCreated}; qtInitialized=${this.qtInitialized}`);
  }

  private waitForStablePrivacyReturn(): void {
    this.privacyWaitingForSystemForeground = true;
    this.privacyHandoffBackgroundObserved = false;
    const generation = ++this.privacyHandoffGeneration;
    this.logPrivacyGate('privacy dialog accepted; waiting for lifecycle restore');
    setTimeout(() => {
      if (generation !== this.privacyHandoffGeneration || !this.privacyWaitingForSystemForeground ||
        this.privacyHandoffBackgroundObserved || !this.isForeground || this.qtInitialized) {
        return;
      }
      // Some Privacy Manager versions keep the host Ability foreground for the
      // entire consent flow and therefore emit no lifecycle pair. Starting
      // from this settled callback avoids leaving those devices on black.
      this.privacyWaitingForSystemForeground = false;
      this.logPrivacyGate('privacy lifecycle callback absent; starting Qt after settled fallback');
      void this.startQtIfReady();
    }, 420);
  }

  private startQtAfterStablePrivacyForeground(): void {
    const generation = ++this.privacyHandoffGeneration;
    this.privacyWaitingForSystemForeground = false;
    setTimeout(() => {
      if (generation !== this.privacyHandoffGeneration || !this.isForeground || this.qtInitialized) {
        return;
      }
      this.logPrivacyGate('privacy foreground restored; starting Qt');
      void this.startQtIfReady();
    }, 80);
  }

  private async preparePrivacyHostPage(windowStage: Window.WindowStage): Promise<boolean> {
    if (this.qtWindowPrepared) {
      return true;
    }

    try {
      // Keep privacy consent and the Qt page in separate ArkUI roots. Qt must
      // load its page once to inject the native-node createInfo; preloading
      // that page here made it remount after consent and exposed the launcher
      // between two copies of the launch screen on physical devices.
      AppStorage.setOrCreate('stellariumPrivacyNativeStartupAllowed', false);
      const pageLoadStartedAt = Date.now();
      await windowStage.loadContent('pages/PrivacyBootstrap');
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `[privacy-gate] privacy bootstrap page loaded in ${Date.now() - pageLoadStartedAt} ms`);
      this.qtWindowPrepared = true;
      return true;
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, `Privacy host page preparation failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private async requestPrivacyThenStart(): Promise<void> {
    if (this.privacyRequestStarted || this.privacyAccepted || this.qtInitialized || this.pendingWindowStage === null) {
      return;
    }

    this.privacyRequestStarted = true;
    this.logPrivacyGate('requesting system privacy consent');
    const consent = await requestPrivacyConsent(this.context);
    this.privacyRequestStarted = false;
    if (!consent.accepted) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy consent was not accepted; Qt startup remains blocked');
      return;
    }

    // Privacy Manager resolves its Promise only after the user has acted on
    // the system dialog. Start Qt from that official completion point.
    this.privacyAccepted = true;
    if (consent.dialogShown) {
      await this.restoreHostWindowAfterPrivacy();
      this.waitForStablePrivacyReturn();
      return;
    }
    this.logPrivacyGate('system privacy consent accepted');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Privacy consent accepted; starting Qt');
    void this.startQtIfReady();
  }

  private async restoreHostWindowAfterPrivacy(): Promise<void> {
    if (this.pendingWindowStage === null) {
      return;
    }
    try {
      const mainWindow = await this.pendingWindowStage.getMainWindow();
      mainWindow.setWindowBackgroundColor('#070b12');
      await mainWindow.showWindow();
      this.isForeground = true;
      this.logPrivacyGate('privacy host window restored before Qt hand-off');
    } catch (err) {
      // The host can already be visible on some Privacy Manager versions.
      // Continue in that state instead of treating it as a failed consent.
      this.logPrivacyGate('privacy host window already visible or unavailable');
    }
  }

  private async requestPrivacyAfterWindowReady(windowStage: Window.WindowStage): Promise<void> {
    if (!await this.preparePrivacyHostPage(windowStage)) {
      return;
    }
    await this.enterImmersive(windowStage);
    this.logPrivacyGate('privacy bootstrap is ready; requesting system privacy consent');
    await this.requestPrivacyThenStart();
  }

  private async initializeQtAbilityIfNeeded(): Promise<void> {
    if (this.qtAbilityCreated || this.pendingWant === null || this.pendingLaunchParam === null) {
      return;
    }

    // setupQtApplication() enters Qt's Harmony bridge. Keep both this call and
    // the deferred AbilityStage callback behind the Privacy Manager decision.
    QAbilityStage.releasePrivacyGate();
    await QAbilityStage.initQtAppContextIfNeeded(this.context.getApplicationContext());
    qpa.handleAbilityOnCreate(this, this.pendingWant, this.pendingLaunchParam);
    this.qtAbilityCreated = true;
  }

  private async startQtIfReady(): Promise<void> {
    if (!this.privacyAccepted || this.qtInitialized || this.pendingWant === null ||
      this.pendingLaunchParam === null || this.pendingWindowStage === null || !this.isForeground) {
      return;
    }

    this.qtInitialized = true;
    try {
      if (!this.qtWindowPrepared) {
        this.qtInitialized = false;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Qt startup deferred because its single ArkUI host is not prepared');
        return;
      }
      AppStorage.setOrCreate('stellariumStartupPreparing', true);
      const contextInitializationStartedAt = Date.now();
      await this.initializeQtAbilityIfNeeded();
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `[startup] Qt application context initialized in ${Date.now() - contextInitializationStartedAt} ms`);
      // The Qt template normally receives this lifecycle callback directly
      // from onWindowStageCreate(). We defer it until consent so Qt cannot
      // initialize before the policy decision, but it still must run to put
      // the native XComponent createInfo into the page's shared storage.
      qpa.handleAbilityOnWindowStageCreate(this, this.pendingWindowStage);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[startup] requested Qt window-stage page injection');
      // handleAbilityOnWindowStageCreate() schedules loadContent() internally.
      // Allow it to remount the already prepared ArkUI page before releasing
      // the native-node gate, otherwise the visible page has no createInfo.
      await this.enterImmersive(this.pendingWindowStage);
      await new Promise<void>((resolve) => setTimeout(resolve, 160));
      AppStorage.setOrCreate('stellariumStartupPreparing', false);
      AppStorage.setOrCreate('stellariumPrivacyNativeStartupAllowed', true);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[startup] released Qt native-node gate');
      qpa.handleAbilityOnForeground(this);
    } catch (err) {
      // Keep the ability alive if the native bridge reports a synchronous
      // startup error, so the consent page does not turn into a home-screen flash.
      this.qtInitialized = false;
      AppStorage.setOrCreate('stellariumStartupPreparing', false);
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
    // Optional deep-sky images are intentionally not part of the synchronous
    // bootstrap. Start their resumable installation only after consent and the
    // Qt foreground hand-off; completion reloads the existing collection.
    setDeepSkyImageExtractionForeground(true);
    setTimeout(() => {
      scheduleDeepSkyImageExtraction(this.context.getApplicationContext(), () => {
        try {
          command('triggerAction', 'actionShow_DSO_Textures_Reload');
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Reload requested after deep-sky image installation');
        } catch (err) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, `Unable to reload deep-sky images: ${JSON.stringify(err)}`);
        }
      });
    }, 1200);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Qt startup completed after privacy consent');
    this.drainCliRequests();
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
    hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-gate] ability created; Qt initialization is blocked pending consent');
    AppStorage.setOrCreate('stellariumStartupPreparing', false);
    this.pendingWant = want;
    this.pendingLaunchParam = launchParam;
    this.queueCliRequest(want);
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
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onNewWant()');
    this.pendingWant = want;
    this.pendingLaunchParam = launchParam;
    this.queueCliRequest(want);
    if (this.qtAbilityCreated) {
      qpa.handleAbilityOnNewWant(this, want, launchParam);
      this.drainCliRequests();
    }
  }

  onForeground() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onForeground()');
    this.isForeground = true;
    setDeepSkyImageExtractionForeground(true);
    if (!this.qtInitialized) {
      if (this.privacyWaitingForSystemForeground) {
        this.startQtAfterStablePrivacyForeground();
        return;
      }
      void this.startQtIfReady();
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
    setDeepSkyImageExtractionForeground(false);
    if (!this.qtInitialized) {
      if (this.privacyWaitingForSystemForeground) {
        // A real background/foreground pair owns the hand-off. It invalidates
        // the no-lifecycle fallback until onForeground restores the host.
        this.privacyHandoffBackgroundObserved = true;
        this.privacyHandoffGeneration++;
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
