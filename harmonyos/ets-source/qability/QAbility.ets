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

interface WindowAvoidAreaChange {
  type: Window.AvoidAreaType;
  area: Window.AvoidArea;
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
  private privacyProbeStartedAt: number = 0;
  private privacyProbeSequence: number = 0;
  private cliRequests: StellariumCliRequest[] = [];
  private safeAreaWindow: Window.Window | null = null;
  private safeAreaTopPixels: number = 0;

  private readonly avoidAreaChangeCallback = (data: WindowAvoidAreaChange): void => {
    if (data.type === Window.AvoidAreaType.TYPE_SYSTEM || data.type === Window.AvoidAreaType.TYPE_CUTOUT) {
      this.publishScreenSafeArea(data.area.topRect.height);
    }
  };

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
    let payload = encodedPayload;
    if (encodedPayload.startsWith('__STEL_CLI_PAYLOAD_URI__')) {
      try {
        payload = decodeURIComponent(encodedPayload.substring('__STEL_CLI_PAYLOAD_URI__'.length));
      } catch (error) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[cli] rejected malformed percent-encoded payload');
        return;
      }
    } else if (encodedPayload.startsWith('__STEL_CLI_PAYLOAD__')) {
      payload = encodedPayload.substring('__STEL_CLI_PAYLOAD__'.length);
    }
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
      commandName === 'startPanInertia' || commandName === 'stopPanInertia' || commandName === 'playScript';
  }

  private isUiCliCommand(commandName: string): boolean {
    if (commandName === 'setSearchBrowserPage' || commandName === 'selectSearchCategory' || commandName === 'setSearchBrowserFilter') return true;
    if (commandName === 'setAstroTab' || commandName === 'setAstroGroup' || commandName === 'setAstroFilter' || commandName === 'setAstroScroll') return true;
    if (commandName === 'setSatellitePanelGroup' || commandName === 'setSatellitePanelScroll') return true;
    if (commandName === 'setObjectDetailTab') return true;
    if (commandName === 'setObjectModelView') return true;
    return commandName === 'openUiPanel' || commandName === 'openPluginFeature' || commandName === 'closeUiPanel' || commandName === 'backUiPanel' ||
      commandName === 'setLayerTab' || commandName === 'setSkyCultureMakerTab' || commandName === 'setGyroscopeEnabled' || commandName === 'setTelescopeLivePosition';
  }

  private drainCliRequests(): void {
    if (!this.qtInitialized || this.cliRequests.length === 0) {
      return;
    }
    const request = this.cliRequests[0];
    request.attempts += 1;
    if (request.commandName === 'getSearchBrowserState') {
      const state = JSON.parse(AppStorage.get<string>('stellariumSearchBrowserState') ??
        JSON.stringify({ ok: false, error: 'search browser has not loaded' })) as Record<string, Object>;
      state['scrollY'] = AppStorage.get<number>('stellariumSearchBrowserScrollY') ?? 0;
      this.finishCliRequest(request, JSON.stringify(state));
      return;
    }
    if (request.commandName === 'getAstroPanelState') {
      this.finishCliRequest(request, AppStorage.get<string>('stellariumAstroPanelState') ??
        JSON.stringify({ ok: false, error: 'astronomy panel has not loaded' }));
      return;
    }
    if (request.commandName === 'getSatellitePanelState') {
      this.finishCliRequest(request, AppStorage.get<string>('stellariumSatellitePanelState') ??
        JSON.stringify({ ok: false, error: 'satellite panel has not loaded' }));
      return;
    }
    if (request.commandName === 'getObjectModelView') {
      const model = JSON.parse(AppStorage.get<string>('stellariumObjectModelView') ??
        JSON.stringify({ ok: false, error: 'model has not rendered' })) as Record<string, Object>;
      model['detailScrollY'] = AppStorage.get<number>('stellariumObjectDetailScrollY') ?? 0;
      this.finishCliRequest(request, JSON.stringify(model));
      return;
    }
    if (this.isUiCliCommand(request.commandName)) {
      const value = request.payload.trim();
      if (request.commandName === 'setSearchBrowserPage' && !['browse', 'categories', 'root', 'visibility', 'instrument'].includes(value)) {
        this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'expected browse, categories, root, visibility, instrument' }));
        return;
      }
      if (request.commandName === 'selectSearchCategory') {
        const state = JSON.parse(AppStorage.get<string>('stellariumSearchBrowserState') ?? '{}') as Record<string, Object>;
        const categories = state['categories'] as Array<Record<string, Object>> | undefined;
        if (!categories?.some((category: Record<string, Object>) => category['code'] === value)) {
          this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'unknown category; open search browser first' }));
          return;
        }
      }
      if (request.commandName === 'setSearchBrowserFilter' &&
        !/^(visibility\|(all|above|good)|instrument\|(all|naked|binocular|telescope))$/.test(value)) {
        this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'invalid search filter' }));
        return;
      }
      if (request.commandName === 'setAstroScroll' &&
        (value.length === 0 || !Number.isFinite(Number(value)) || Number(value) < 0)) {
        this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'expected non-negative scroll offset' }));
        return;
      }
      if (request.commandName === 'setAstroFilter' &&
        !/^(period\|(evening|midnight|morning|night)|altitude\|(0|10|20|30|45)|magnitude\|(4|6|8|10)|direction\|(all|north|east|south|west))$/.test(value)) {
        this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'invalid tonight filter key or value' }));
        return;
      }
      if ((request.commandName === 'setAstroTab' && !/^[0-9]$/.test(value)) ||
        (request.commandName === 'setAstroGroup' && !/^[0-2]$/.test(value))) {
        this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'expected tab 0..9 or group 0..2' }));
        return;
      }
      if (request.commandName === 'setSatellitePanelScroll' &&
        (value.length === 0 || !Number.isFinite(Number(value)) || Number(value) < 0)) {
        this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'expected non-negative scroll offset' }));
        return;
      }
      if (request.commandName === 'setObjectDetailTab' && !['0', '1', '2', '3'].includes(value)) {
        this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'expected tab index 0..3' }));
        return;
      }
      if (request.commandName === 'setObjectModelView' && !['reset', 'open', 'immersive', 'close'].includes(value)) {
        const parts = value.split('|');
        if (parts.length !== 2 || parts.some((part: string) => part.trim().length === 0 ||
          !Number.isFinite(Number(part)) || Math.abs(Number(part)) > 1000)) {
          this.finishCliRequest(request, JSON.stringify({ ok: false, error: 'expected open, immersive, close, reset, or dx|dy (finite, <=1000)' }));
          return;
        }
      }
      const response = request.commandName === 'openUiPanel' && value.length === 0
        ? JSON.stringify({ ok: false, error: 'panel name is required' })
        : request.commandName === 'setTelescopeLivePosition' && !['1', 'true', 'on', '0', 'false', 'off'].includes(value.toLowerCase())
          ? JSON.stringify({ ok: false, error: 'expected on or off' })
          : request.commandName === 'setTelescopeLivePosition'
            ? JSON.stringify({ ok: true, accepted: true, enabled: ['1', 'true', 'on'].includes(value.toLowerCase()) })
            : JSON.stringify({ ok: true, accepted: true, panel: value });
      this.finishCliRequest(request, response);
      return;
    }
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
    this.publishCliUiEvent(request, response);
    const responseText = String(response);
    const chunkSize = 600;
    const chunkCount = Math.max(1, Math.ceil(responseText.length / chunkSize));
    for (let chunkIndex = 0; chunkIndex < chunkCount; chunkIndex += 1) {
      const chunk = responseText.substring(chunkIndex * chunkSize, (chunkIndex + 1) * chunkSize);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[cli-response] requestId=%{public}s command=%{public}s chunkIndex=%{public}d chunkCount=%{public}d responseChunk=%{public}s',
        request.requestId, request.commandName, chunkIndex, chunkCount, chunk);
    }
    this.drainCliRequests();
  }

  private publishCliUiEvent(request: StellariumCliRequest, response: string): void {
    if (this.isUiCliCommand(request.commandName)) {
      try {
        const parsed = JSON.parse(response) as Record<string, Object>;
        if (parsed['ok'] !== true) {
          return;
        }
        AppStorage.setOrCreate('stellariumCliUiEvent', JSON.stringify({
          requestId: request.requestId,
          commandName: request.commandName,
          payload: request.payload,
          response: parsed,
        }));
      } catch (err) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[cli] UI event publish failed: %{public}s', JSON.stringify(err));
      }
      return;
    }
    if (request.commandName !== 'searchObject' && request.commandName !== 'selectAt' &&
      request.commandName !== 'clearSelection' && request.commandName !== 'getSelectedObjectInfo' &&
      request.commandName !== 'setSkyCulture' && request.commandName !== 'setLanguage' && request.commandName !== 'setSatellitesFlag' &&
      request.commandName !== 'setInformationSetting' && request.commandName !== 'getInformationSettings' &&
      request.commandName !== 'setTimeSetting' && request.commandName !== 'getTimeSettings' &&
      request.commandName !== 'setMosaicCamera' && request.commandName !== 'getMosaicCamera' &&
      request.commandName !== 'getNebulaTextureStatus' && request.commandName !== 'setNebulaTexturesVisible' &&
      request.commandName !== 'setNebulaTextureConflictAvoidance' &&
      request.commandName !== 'setDateFormat' && request.commandName !== 'setTimeFormat' && request.commandName !== 'playScript' &&
      request.commandName !== 'continueScript' && request.commandName !== 'stopScript' &&
      request.commandName !== 'setScriptRate') {
      if (request.commandName !== 'setObjectDetailConnector' && request.commandName !== 'getObjectDetailConnector') {
        return;
      }
    }
    try {
      const parsed = JSON.parse(response) as Record<string, Object>;
      if (parsed['pending'] === true && request.commandName !== 'playScript') {
        return;
      }
      AppStorage.setOrCreate('stellariumCliUiEvent', JSON.stringify({
        requestId: request.requestId,
        commandName: request.commandName,
        payload: request.payload,
        response: parsed,
      }));
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[cli] UI event publish failed: %{public}s', JSON.stringify(err));
    }
  }

  private logPrivacyGate(stage: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[privacy-gate] ${stage}; accepted=${this.privacyAccepted}; qtAbilityCreated=${this.qtAbilityCreated}; qtInitialized=${this.qtInitialized}`);
  }

  private logPrivacyProbe(phase: string, detail: string = ''): void {
    if (this.privacyProbeStartedAt === 0) {
      this.privacyProbeStartedAt = Date.now();
    }
    this.privacyProbeSequence += 1;
    const suffix = detail.length > 0 ? `; ${detail}` : '';
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[privacy-probe] seq=${this.privacyProbeSequence}; phase=${phase}; elapsedMs=${Date.now() - this.privacyProbeStartedAt}; ` +
      `foreground=${this.isForeground}; accepted=${this.privacyAccepted}; qtAbilityCreated=${this.qtAbilityCreated}; ` +
      `qtInitialized=${this.qtInitialized}; windowPrepared=${this.qtWindowPrepared}${suffix}`);
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
      this.logPrivacyProbe('final-page-prepare-start');
      // Privacy Manager documents that one Ability must not call loadContent()
      // more than once. Prepare the final Qt page once before the system
      // dialog, but keep the native sky node gated until consent is accepted.
      AppStorage.setOrCreate('stellariumPrivacyNativeStartupAllowed', false);
      await this.initializeQtAbilityIfNeeded();
      if (!this.qtAbilityCreated) {
        this.logPrivacyProbe('final-page-prepare-failed', 'qt ability was not created');
        return false;
      }
      this.logPrivacyProbe('qt-host-ready-before-consent');
      qpa.handleAbilityOnWindowStageCreate(this, windowStage);
      this.qtWindowPrepared = true;
      this.logPrivacyProbe('final-page-requested', 'single loadContent owner is Qt bridge');
      return true;
    } catch (err) {
      this.logPrivacyProbe('final-page-prepare-failed', `error=${JSON.stringify(err)}`);
      hilog.error(LOG_DOMAIN, LOG_TAG, `Privacy host page preparation failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private async requestPrivacyThenStart(): Promise<void> {
    if (this.privacyRequestStarted || this.privacyAccepted || this.qtInitialized || this.pendingWindowStage === null) {
      return;
    }

    this.privacyRequestStarted = true;
    this.logPrivacyProbe('privacy-request-start');
    this.logPrivacyGate('requesting system privacy consent');
    const consent = await requestPrivacyConsent(this.context);
    this.privacyRequestStarted = false;
    this.logPrivacyProbe('privacy-request-finish', `accepted=${consent.accepted}; dialogShown=${consent.dialogShown}`);
    if (!consent.accepted) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy consent was not accepted; Qt startup remains blocked');
      return;
    }

    // Privacy Manager resolves its Promise only after the user has acted on
    // the system dialog. Start Qt from that official completion point.
    this.privacyAccepted = true;
    if (consent.dialogShown) {
      this.waitForStablePrivacyReturn();
      return;
    }
    this.logPrivacyGate('system privacy consent accepted');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Privacy consent accepted; starting Qt');
    void this.startQtIfReady();
  }

  private async requestPrivacyAfterWindowReady(windowStage: Window.WindowStage): Promise<void> {
    if (!await this.preparePrivacyHostPage(windowStage)) {
      return;
    }
    await this.enterImmersive(windowStage);
    this.logPrivacyProbe('privacy-host-ready', 'system dialog will cover an already prepared opaque host');
    this.logPrivacyGate('privacy host page is ready; requesting system privacy consent');
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
      this.logPrivacyProbe('qt-start-transfer-start');
      const contextInitializationStartedAt = Date.now();
      await this.initializeQtAbilityIfNeeded();
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `[startup] Qt application context initialized in ${Date.now() - contextInitializationStartedAt} ms`);
      await this.enterImmersive(this.pendingWindowStage);
      await new Promise<void>((resolve) => setTimeout(resolve, 160));
      AppStorage.setOrCreate('stellariumStartupPreparing', false);
      AppStorage.setOrCreate('stellariumPrivacyNativeStartupAllowed', true);
      this.logPrivacyProbe('native-node-gate-released');
      hilog.info(LOG_DOMAIN, LOG_TAG, '[startup] released Qt native-node gate');
      qpa.handleAbilityOnForeground(this);
      this.logPrivacyProbe('qt-foreground-requested');
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
    this.logPrivacyProbe('qt-start-transfer-finish');
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
      this.registerScreenSafeArea(mainWindow);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::enterImmersive() success');
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility::enterImmersive() failed: ' + JSON.stringify(err));
    }
  }

  private publishScreenSafeArea(topPixels: number): void {
    const measuredTop = Number.isFinite(topPixels) ? Math.max(0, Math.round(topPixels)) : 0;
    this.safeAreaTopPixels = Math.max(this.safeAreaTopPixels, measuredTop);
    const top = this.safeAreaTopPixels;
    AppStorage.setOrCreate<number>('stellariumScreenSafeTopPixels', top);
    try {
      const result = command('setScreenSafeArea', top.toString());
      hilog.info(LOG_DOMAIN, LOG_TAG, '[safe-area] topPixels=%{public}s native=%{public}s', top.toString(), result);
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[safe-area] native update failed: %{public}s', JSON.stringify(err));
    }
  }

  private registerScreenSafeArea(mainWindow: Window.Window): void {
    if (this.safeAreaWindow !== null && this.safeAreaWindow !== mainWindow) {
      try {
        this.safeAreaWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
      } catch (err) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[safe-area] previous listener removal failed');
      }
    }
    this.safeAreaWindow = mainWindow;
    try {
      const systemArea = mainWindow.getWindowAvoidArea(Window.AvoidAreaType.TYPE_SYSTEM);
      const cutoutArea = mainWindow.getWindowAvoidArea(Window.AvoidAreaType.TYPE_CUTOUT);
      this.publishScreenSafeArea(Math.max(systemArea.topRect.height, cutoutArea.topRect.height));
      mainWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
      mainWindow.on('avoidAreaChange', this.avoidAreaChangeCallback);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[safe-area] avoidAreaChange listener registered');
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[safe-area] avoid area unavailable: %{public}s', JSON.stringify(err));
      this.publishScreenSafeArea(0);
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    this.privacyProbeStartedAt = Date.now();
    this.logPrivacyProbe('ability-create');
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
    this.logPrivacyProbe('window-stage-create');
    void this.requestPrivacyAfterWindowReady(windowStage);
  }

  onWindowStageRestore(windowStage: Window.WindowStage): void {
    this.pendingWindowStage = windowStage;
    this.logPrivacyProbe('window-stage-restore');
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
    this.logPrivacyProbe('ability-foreground');
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
    this.logPrivacyProbe('ability-background');
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
    this.logPrivacyProbe('window-stage-destroy');
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
