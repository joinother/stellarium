import type common from '@ohos.app.ability.common';
import { privacyManager } from '@kit.AppGalleryKit';
import hilog from '@ohos.hilog';
import { LOG_DOMAIN, LOG_TAG } from '../common/QtAppConstants';

export interface PrivacyConsentResult {
  accepted: boolean;
  dialogShown: boolean;
}

export function hasCurrentPrivacyConsent(): boolean {
  try {
    const management = privacyManager.getAppPrivacyMgmtInfo();
    if (management.type !== privacyManager.AppPrivacyMgmtType.FULL_MODE) {
      return false;
    }
    const statement = management.privacyInfo.find((item) =>
      item.type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK);
    return statement !== undefined && privacyManager.getAppPrivacyResult().some((result) =>
      result.type === privacyManager.AppPrivacyType.PRIVACY_AGREEMENT &&
      result.result === privacyManager.AppPrivacyResultType.FULL_MODE_AGREED &&
      result.id === statement.id && result.versionCode === statement.versionCode);
  } catch (_) {
    return false;
  }
}

export async function requestPrivacyConsent(
  context: common.UIAbilityContext,
): Promise<PrivacyConsentResult> {
  try {
    hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-probe] phase=management-query-start');
    const management = privacyManager.getAppPrivacyMgmtInfo();
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[privacy-probe] phase=management-query-finish; type=${management.type}; linkCount=${management.privacyInfo.length}`);
    if (management.type === privacyManager.AppPrivacyMgmtType.UNSUPPORTED || management.privacyInfo.length === 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy Manager has no AppGallery configuration; Qt startup remains blocked');
      return { accepted: false, dialogShown: false };
    }

    const privacyStatement = management.privacyInfo.find((item) =>
      item.type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK,
    );
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[privacy-probe] phase=result-query-start; statementConfigured=${privacyStatement !== undefined}`);
    const privacyResults = privacyManager.getAppPrivacyResult();
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[privacy-probe] phase=result-query-finish; resultCount=${privacyResults.length}`);
    const accepted = privacyStatement !== undefined && privacyResults.some((result) =>
      result.type === privacyManager.AppPrivacyType.PRIVACY_AGREEMENT &&
      result.result === privacyManager.AppPrivacyResultType.FULL_MODE_AGREED &&
      result.id === privacyStatement.id &&
      result.versionCode === privacyStatement.versionCode,
    );
    if (accepted) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Privacy Manager reports the current privacy statement is already accepted');
      return { accepted: true, dialogShown: false };
    }

    hilog.info(LOG_DOMAIN, LOG_TAG, '[privacy-probe] phase=dialog-request-start');
    const consent = await privacyManager.requestAppPrivacyConsent(context);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[privacy-probe] phase=dialog-request-finish; resultCount=${consent.results.length}`);
    const acceptedAfterRequest = consent.results.some((result) =>
      result.type === privacyManager.AppPrivacyType.PRIVACY_AGREEMENT &&
      result.result === privacyManager.AppPrivacyResultType.FULL_MODE_AGREED &&
      privacyStatement !== undefined && result.id === privacyStatement.id &&
      result.versionCode === privacyStatement.versionCode,
    ) && hasCurrentPrivacyConsent();
    return { accepted: acceptedAfterRequest, dialogShown: true };
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Privacy Manager request failed; Qt startup remains blocked: ${JSON.stringify(err)}`);
    return { accepted: false, dialogShown: false };
  }
}
