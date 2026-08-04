import AbilityStage from '@ohos.app.ability.AbilityStage';
import QAbility from '../qability/QAbility';
import QChildProcess from '../process/QChildProcess';
import QtUtils from '../qability/QtUtils';
import Want from '@ohos.app.ability.Want';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import qpa from 'libqohos.so';
import {APP_LIBRARY_NAME, LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';
import { prepareStellariumResources } from '../qability/StellariumResourceBootstrap';

export default class QAbilityStage extends AbilityStage {

  // setting "appArgs" overrides arguments from initial Want object
  private static appArgs?: Array<string>;

  private static setupQtApplicationCalled: boolean = false;
  private static resourcesPrepared: boolean = false;

  private static prepareResourcesIfNeeded(appContext: common.ApplicationContext): void {
    if (QAbilityStage.resourcesPrepared) {
      return;
    }

    prepareStellariumResources(appContext);
    QAbilityStage.resourcesPrepared = true;
  }

  private static initQtAppContextImpl(appContext: common.ApplicationContext, abilityClassName: string): void {
    if (!QAbilityStage.setupQtApplicationCalled) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::initQtAppContextImpl: init');
      // A specified Ability has a short AcceptWant deadline. The normal path
      // prepares resources in AbilityStage.onCreate before this callback.
      // Keep a fallback for lifecycle variants that skip that stage callback.
      QAbilityStage.prepareResourcesIfNeeded(appContext);
      QAbilityStage.setupQtApplicationCalled = true;
      qpa.setupQtApplication({
        appContext: appContext,
        modulesFactories: QtUtils.getModulesFactoriesMapForQt(),
        appName: APP_LIBRARY_NAME,
        appArgs: QAbilityStage.appArgs,
        abilityClassName: abilityClassName,
        _unusedQChildProcess: new QChildProcess(),
      });
    } else {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::initQtAppContextImpl: already initialized');
    }
  }

  public static initQtAppContextIfNeeded(appContext: common.ApplicationContext): void {
    QAbilityStage.initQtAppContextImpl(appContext, QAbility.name);
  }

  onCreate(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onCreate()');
    QAbilityStage.prepareResourcesIfNeeded(this.context.getApplicationContext());
    qpa.handleAbilityStageOnCreate(this);
  }

  onNewProcessRequest(want: Want): string {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onNewProcessRequest: want.parameters: ' + JSON.stringify(want.parameters));
    QAbilityStage.initQtAppContextIfNeeded(this.context.getApplicationContext());
    let processKey: string = qpa.handleAbilityStageOnNewProcessRequest(this, want);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onNewProcessRequest: processKey: "' + processKey + '"');
    return processKey;
  }

  onAcceptWant(want: Want): string {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onAcceptWant: want.parameters: ' + JSON.stringify(want.parameters));
    QAbilityStage.initQtAppContextIfNeeded(this.context.getApplicationContext());
    let instanceKey: string = qpa.handleAbilityStageOnAcceptWant(this, want);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onAcceptWant: instanceKey: "' + instanceKey + '"');
    return instanceKey;
  }

  onDestroy() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onDestroy()');
    qpa.handleAbilityStageOnDestroy(this);
  }
}
