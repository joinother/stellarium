import type common from '@ohos.app.ability.common';
import { privacyManager } from '@kit.AppGalleryKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import hilog from '@ohos.hilog';
import { DEBUG } from '../../../../build/default/generated/profile/default/BuildProfile';
import { LOG_DOMAIN, LOG_TAG } from '../common/QtAppConstants';

export async function requestPrivacyConsent(
  context: common.UIAbilityContext,
): Promise<boolean> {
  // Privacy Manager is unavailable on emulators. A physical Debug install
  // still exercises the official flow using the module metadata test setup.
  if (DEBUG && deviceInfo.productModel === 'emulator') {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Emulator Debug build: skipping unsupported privacy consent request');
    return true;
  }

  try {
    const management = privacyManager.getAppPrivacyMgmtInfo();
    if (management.type === privacyManager.AppPrivacyMgmtType.UNSUPPORTED || management.privacyInfo.length === 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy Manager has no AppGallery configuration; Qt startup remains blocked');
      return false;
    }

    const privacyStatement = management.privacyInfo.find((item) =>
      item.type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK,
    );
    const accepted = privacyStatement !== undefined && privacyManager.getAppPrivacyResult().some((result) =>
      result.type === privacyManager.AppPrivacyType.PRIVACY_AGREEMENT &&
      result.result === privacyManager.AppPrivacyResultType.FULL_MODE_AGREED &&
      result.id === privacyStatement.id &&
      result.versionCode === privacyStatement.versionCode,
    );
    if (accepted) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Privacy Manager reports the current privacy statement is already accepted');
      return true;
    }

    const consent = await privacyManager.requestAppPrivacyConsent(context);
    const acceptedAfterRequest = consent.results.some((result) =>
      result.type === privacyManager.AppPrivacyType.PRIVACY_AGREEMENT &&
      result.result === privacyManager.AppPrivacyResultType.FULL_MODE_AGREED,
    );
    hilog.info(LOG_DOMAIN, LOG_TAG, `Privacy Manager completed: accepted=${acceptedAfterRequest}`);
    return acceptedAfterRequest;
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Privacy Manager request failed; Qt startup remains blocked: ${JSON.stringify(err)}`);
    return false;
  }
}
