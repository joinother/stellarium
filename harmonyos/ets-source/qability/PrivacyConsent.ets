import type common from '@ohos.app.ability.common';
import { privacyManager } from '@kit.StoreKit';
import hilog from '@ohos.hilog';
import { DEBUG } from '../../../../build/default/generated/profile/default/BuildProfile';
import { LOG_DOMAIN, LOG_TAG } from '../common/QtAppConstants';

export async function requestPrivacyConsent(
  context: common.UIAbilityContext,
): Promise<boolean> {
  // AppGallery cannot resolve privacy declarations for locally Debug-signed
  // installs. Keep this bypass build-time only: Release artifacts still use
  // the platform consent flow exclusively and never use a custom dialog.
  if (DEBUG) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Debug build: skipping AppGallery privacy consent request');
    return true;
  }

  try {
    const management = privacyManager.getAppPrivacyMgmtInfo();
    if (management.type === privacyManager.AppPrivacyMgmtType.UNSUPPORTED || management.privacyInfo.length === 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy Manager has no AppGallery configuration; Qt startup remains blocked');
      return false;
    }

    const consent = await privacyManager.requestAppPrivacyConsent(context);
    const accepted = consent.results.some((result) =>
      result.type === privacyManager.AppPrivacyType.PRIVACY_AGREEMENT &&
      result.result === privacyManager.AppPrivacyResultType.FULL_MODE_AGREED,
    );
    hilog.info(LOG_DOMAIN, LOG_TAG, `Privacy Manager completed: accepted=${accepted}`);
    return accepted;
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Privacy Manager request failed; Qt startup remains blocked: ${JSON.stringify(err)}`);
    return false;
  }
}
