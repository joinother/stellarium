import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import QAbilityStage from '../qabilitystage/QAbilityStage';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import Window from '@ohos.window'
import hilog from '@ohos.hilog';
import qpa from 'libqohos.so';
import {LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';

export default class QAbility extends UIAbility {

  private static lifecycleSequence: number = 0;
  private localStorage: LocalStorage | null = null;
  private readonly lifecycleId: string = `${Date.now()}-${++QAbility.lifecycleSequence}`;

  private traceLifecycle(event: string, detail: string = ''): void {
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `[LIFECYCLE] ability=${this.lifecycleId} event=${event}${detail ? ` detail=${detail}` : ''}`);
  }

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
    this.traceLifecycle('onCreate:before', JSON.stringify(want.parameters));
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): want.parameters: ' + JSON.stringify(want.parameters));
    QAbilityStage.initQtAppContextIfNeeded(this.context.getApplicationContext());
    qpa.handleAbilityOnCreate(this, want, launchParam);
    this.traceLifecycle('onCreate:after');
  }

  onDestroy(): void | Promise<void> {
    this.traceLifecycle('onDestroy:before');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onDestroy()');
    return qpa.handleAbilityOnDestroy(this);
  }

  onPrepareToTerminate(): boolean {
    this.traceLifecycle('onPrepareToTerminate:before');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminate()');
    return qpa.handleAbilityOnPrepareToTerminate(this);
  }

  onPrepareToTerminateAsync(): Promise<boolean> {
    this.traceLifecycle('onPrepareToTerminateAsync:before');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminateAsync()');
    return qpa.handleAbilityOnPrepareToTerminateAsync(this);
  }

  onWindowStageCreate(windowStage: Window.WindowStage) {
    this.traceLifecycle('onWindowStageCreate:before', JSON.stringify(this.launchWant.parameters));
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onWindowStageCreate(): this.launchWant.parameters: ' + JSON.stringify(this.launchWant.parameters));
    qpa.handleAbilityOnWindowStageCreate(this, windowStage);
    this.traceLifecycle('onWindowStageCreate:after');
    this.enterImmersive(windowStage);
  }

  onWindowStageRestore(windowStage: Window.WindowStage): void {
    this.traceLifecycle('onWindowStageRestore:before');
    qpa.handleAbilityOnWindowStageRestore(this, windowStage);
    this.traceLifecycle('onWindowStageRestore:after');
    this.enterImmersive(windowStage);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.traceLifecycle('onNewWant:before', JSON.stringify(want.parameters));
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onNewWant(): want.parameters: ' + JSON.stringify(want.parameters));
    qpa.handleAbilityOnNewWant(this, want, launchParam);
    this.traceLifecycle('onNewWant:after');
  }

  onForeground() {
    this.traceLifecycle('onForeground:before');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onForeground()');
    qpa.handleAbilityOnForeground(this);
    this.traceLifecycle('onForeground:after');
    if (this.context.windowStage) {
      this.enterImmersive(this.context.windowStage);
    }
  }

  onBackground() {
    this.traceLifecycle('onBackground:before');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onBackground()');
    qpa.handleAbilityOnBackground(this);
    this.traceLifecycle('onBackground:after');
  }

  onWindowStageDestroy() {
    this.traceLifecycle('onWindowStageDestroy:before');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onStageDestroy()');
    qpa.handleAbilityOnWindowStageDestroy(this);
    this.traceLifecycle('onWindowStageDestroy:after');
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult | Promise<AbilityConstant.OnContinueResult> {
    return qpa.handleAbilityOnContinue(this, wantParam);
  }
}
