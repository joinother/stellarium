import type common from '@ohos.app.ability.common';
import Window from '@ohos.window';
import fs from '@ohos.file.fs';
import { privacyManager } from '@kit.StoreKit';
import hilog from '@ohos.hilog';
import { LOG_DOMAIN, LOG_TAG } from '../common/QtAppConstants';

const CONSENT_FILE = 'stellarium_privacy_consent_v1';

async function requestLocalConsent(context: common.UIAbilityContext, windowStage: Window.WindowStage): Promise<boolean> {
  const consentPath = `${context.filesDir}/${CONSENT_FILE}`;
  try {
    if (fs.accessSync(consentPath)) {
      return true;
    }
  } catch (_) {
    // The marker does not exist until the user accepts the fallback dialog.
  }

  const mainWindow = await windowStage.getMainWindow();
  const responseIndex = await new Promise<number>((resolve, reject) => {
    mainWindow.getUIContext().getPromptAction().showDialog({
      title: '隐私保护提示',
      message: '为保障天文观测功能正常使用，点击同意后才会进入星图。定位和传感器只会在你主动使用对应功能时申请。',
      buttons: [
        { text: '不同意', color: '#5c6068' },
        { text: '同意', color: '#0a59f7' },
      ],
    }, (err, response) => {
      if (err !== undefined) {
        reject(err);
        return;
      }
      resolve(response.index);
    });
  });

  if (responseIndex !== 1) {
    return false;
  }

  let file: fs.File | undefined = undefined;
  try {
    file = fs.openSync(consentPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    fs.writeSync(file.fd, 'accepted');
    return true;
  } finally {
    if (file !== undefined) {
      fs.closeSync(file);
    }
  }
}

export async function requestPrivacyConsent(
  context: common.UIAbilityContext,
  windowStage: Window.WindowStage,
): Promise<boolean> {
  try {
    const management = privacyManager.getAppPrivacyMgmtInfo();
    if (management.type === privacyManager.AppPrivacyMgmtType.UNSUPPORTED || management.privacyInfo.length === 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Privacy Manager has no AppGallery configuration; using local consent');
      return await requestLocalConsent(context, windowStage);
    }

    const consent = await privacyManager.requestAppPrivacyConsent(context);
    const accepted = consent.results.some((result) =>
      result.type === privacyManager.AppPrivacyType.PRIVACY_AGREEMENT &&
      result.result === privacyManager.AppPrivacyResultType.FULL_MODE_AGREED,
    );
    hilog.info(LOG_DOMAIN, LOG_TAG, `Privacy Manager completed: accepted=${accepted}`);
    return accepted;
  } catch (err) {
    // Debug packages and devices without AppGallery privacy configuration cannot
    // use the service. Keep the app blocked behind a system dialog in that case.
    hilog.warn(LOG_DOMAIN, LOG_TAG, `Privacy Manager unavailable; using local consent: ${JSON.stringify(err)}`);
    try {
      return await requestLocalConsent(context, windowStage);
    } catch (fallbackErr) {
      hilog.error(LOG_DOMAIN, LOG_TAG, `Local privacy consent failed: ${JSON.stringify(fallbackErr)}`);
      return false;
    }
  }
}
