import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const constants = read('harmonyos/ets-source/common/QtAppConstants.ets');
// The filing widget is now a shared component (it can no longer be a host
// @Builder), used by the help "about" section and the device/privacy settings.
const filing = read('harmonyos/ets-source/common/ui/AppFilingInfo.ets');
const help = read('harmonyos/ets-source/panels/panels/HelpPanel.ets');
const privacyRows = read('harmonyos/ets-source/panels/settings/DeviceAndLanguageRows.ets');
const models = read('harmonyos/ets-source/common/types/MainWindowModels.ets');
const ability = read('harmonyos/ets-source/qability/QAbility.ets');
assert.match(constants, /APP_ICP_FILING_NUMBER = '新ICP备2026008516号-2A'/);
assert.match(constants, /APP_ICP_FILING_URL = 'https:\/\/beian\.miit\.gov\.cn\/'/);
assert.match(filing, /Hyperlink\(APP_ICP_FILING_URL, APP_ICP_FILING_NUMBER\)/);
assert.equal((help.match(/AppFilingInfo\(/g) ?? []).length + (privacyRows.match(/AppFilingInfo\(/g) ?? []).length, 2);
assert.match(ability, /request\.commandName === 'getAppFilingInfo'/);
assert.match(ability, /number: APP_ICP_FILING_NUMBER, verificationUrl: APP_ICP_FILING_URL/);
assert.match(read('src/StelOhosCommandCatalog.hpp'), /getAppFilingInfo/);
assert.doesNotMatch(constants, /新ICP备2026008516号-1/);
assert.match(models, /OFFLINE_APPGALLERY_BUILD: boolean = (true|false)/);
for (const path of ['common/QtAppConstants.ets', 'common/ui/AppFilingInfo.ets', 'panels/panels/HelpPanel.ets', 'qability/QAbility.ets']) {
  assert.equal(read('harmonyos/ets-source/' + path), read('build/libstellarium-harmonyos/entry/src/main/ets/' + path), path);
}
console.log('APP filing: verified number, shared UI/CLI constants, selected network mode and generated-source sync passed');
