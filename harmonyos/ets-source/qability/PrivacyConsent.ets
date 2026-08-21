import type common from '@ohos.app.ability.common';
import { privacyManager } from '@kit.AppGalleryKit';
import hilog from '@ohos.hilog';
import { LOG_DOMAIN, LOG_TAG } from '../common/QtAppConstants';

export interface PrivacyConsentResult {
  accepted: boolean;
  dialogShown: boolean;
}

export async function requestPrivacyConsent(
  context: common.UIAbilityContext,
): Promise<PrivacyConsentResult> {
  try {
    const management = privacyManager.getAppPrivacyMgmtInfo();
    if (management.type === privacyManager.AppPrivacyMgmtType.UNSUPPORTED || management.privacyInfo.length === 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy Manager has no AppGallery configuration; Qt startup remains blocked');
      return { accepted: false, dialogShown: false };
    }

    const privacyStatement = management.privacyInfo.find((item) =>
      item.type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK,
    );
    const privacyResults = privacyManager.getAppPrivacyResult();
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

    const consent = await privacyManager.requestAppPrivacyConsent(context);
    const acceptedAfterRequest = consent.results.some((result) =>
      result.type === privacyManager.AppPrivacyType.PRIVACY_AGREEMENT &&
      result.result === privacyManager.AppPrivacyResultType.FULL_MODE_AGREED,
    );
    return { accepted: acceptedAfterRequest, dialogShown: true };
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Privacy Manager request failed; Qt startup remains blocked: ${JSON.stringify(err)}`);
    return { accepted: false, dialogShown: false };
  }
}
