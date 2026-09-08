import AbilityStage from '@ohos.app.ability.AbilityStage';
import QAbility from '../qability/QAbility';
import QChildProcess from '../process/QChildProcess';
import QtUtils from '../qability/QtUtils';
import Want from '@ohos.app.ability.Want';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import qpa from 'libqohos.so';
import {APP_LIBRARY_NAME, LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';
import { prepareStellariumResources, prepareStellariumResourcesAsync } from '../qability/StellariumResourceBootstrap';
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent';

export default class QAbilityStage extends AbilityStage {

  // setting "appArgs" overrides arguments from initial Want object
  private static appArgs?: Array<string>;

  private static setupQtApplicationCalled: boolean = false;
  private static setupQtApplicationPromise: Promise<void> | undefined = undefined;
  private static privacyGateReleased: boolean = false;
  private static stageInstance: QAbilityStage | undefined = undefined;
  private static stageCreateForwarded: boolean = false;

  public static releasePrivacyGate(): void {
    if (!hasCurrentPrivacyConsent()) {
      QAbilityStage.privacyGateReleased = false;
      throw new Error('Current privacy statement is not accepted');
    }
    QAbilityStage.privacyGateReleased = true;
    hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-probe] phase=qt-host-gate-released-after-consent');
  }

  private static forwardStageCreateIfNeeded(): void {
    if (!QAbilityStage.privacyGateReleased || QAbilityStage.stageCreateForwarded ||
      QAbilityStage.stageInstance === undefined) {
      return;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-probe] phase=stage-create-forward-start');
    qpa.handleAbilityStageOnCreate(QAbilityStage.stageInstance);
    QAbilityStage.stageCreateForwarded = true;
    hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-probe] phase=stage-create-forward-finish');
  }

  private static async initQtAppContextImpl(appContext: common.ApplicationContext, abilityClassName: string): Promise<void> {
    if (!QAbilityStage.privacyGateReleased || !hasCurrentPrivacyConsent()) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[privacy-gate] blocked Qt application context initialization before consent');
      throw new Error('Qt application context initialization requires privacy consent');
    }
    if (!QAbilityStage.setupQtApplicationCalled) {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-probe] phase=qt-context-init-start');
      const preparationStartedAt = Date.now();
      await prepareStellariumResourcesAsync(appContext);
      if (!hasCurrentPrivacyConsent()) {
        QAbilityStage.privacyGateReleased = false;
        throw new Error('Privacy consent changed during resource preparation');
      }
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `[privacy-probe] phase=resource-prepare-finish; elapsedMs=${Date.now() - preparationStartedAt}`);
      prepareStellariumResources(appContext);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `[startup] Qt resource preparation completed in ${Date.now() - preparationStartedAt} ms`);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-probe] phase=qt-setup-start');
      qpa.setupQtApplication({
        appContext: appContext,
        modulesFactories: QtUtils.getModulesFactoriesMapForQt(),
        appName: APP_LIBRARY_NAME,
        appArgs: QAbilityStage.appArgs,
        abilityClassName: abilityClassName,
        _unusedQChildProcess: new QChildProcess(),
      });
      QAbilityStage.setupQtApplicationCalled = true;
      hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-probe] phase=qt-setup-finish');
      QAbilityStage.forwardStageCreateIfNeeded();
    } else {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::initQtAppContextImpl: already initialized');
    }
  }

  public static initQtAppContextIfNeeded(appContext: common.ApplicationContext): Promise<void> {
    if (QAbilityStage.setupQtApplicationPromise === undefined) {
      QAbilityStage.setupQtApplicationPromise = QAbilityStage.initQtAppContextImpl(appContext, QAbility.name)
        .catch((error: Error) => {
          QAbilityStage.setupQtApplicationPromise = undefined;
          hilog.error(LOG_DOMAIN, LOG_TAG, `Qt application context initialization failed: ${error.message}`);
          throw error;
        });
    }
    return QAbilityStage.setupQtApplicationPromise;
  }

  public static isQtApplicationInitialized(): boolean {
    return QAbilityStage.setupQtApplicationCalled;
  }

  onCreate(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onCreate()');
    QAbilityStage.stageInstance = this;
    if (!QAbilityStage.privacyGateReleased) {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-gate] deferred AbilityStage create for Qt pending consent');
      return;
    }
    QAbilityStage.forwardStageCreateIfNeeded();
  }

  onNewProcessRequest(want: Want): string {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onNewProcessRequest');
    if (!QAbilityStage.isQtApplicationInitialized()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[privacy-gate] ignored Qt process request before consent');
      return '';
    }
    let processKey: string = qpa.handleAbilityStageOnNewProcessRequest(this, want);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onNewProcessRequest: processKey: "' + processKey + '"');
    return processKey;
  }

  onAcceptWant(want: Want): string {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onAcceptWant');
    if (!QAbilityStage.isQtApplicationInitialized()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[privacy-gate] ignored Qt accept-want request before consent');
      return '';
    }
    let instanceKey: string = qpa.handleAbilityStageOnAcceptWant(this, want);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onAcceptWant: instanceKey: "' + instanceKey + '"');
    return instanceKey;
  }

  onDestroy() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbilityStage::onDestroy()');
    if (QAbilityStage.stageCreateForwarded) {
      qpa.handleAbilityStageOnDestroy(this);
      QAbilityStage.stageCreateForwarded = false;
    }
    QAbilityStage.stageInstance = undefined;
  }
}
