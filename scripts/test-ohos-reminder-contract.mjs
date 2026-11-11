import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const service = read('harmonyos/ets-source/qability/AstronomyReminderService.ets');
const ability = read('harmonyos/ets-source/qability/QAbility.ets');
const manifest = read('harmonyos/module.json5');
const catalog = read('src/StelOhosCommandCatalog.hpp');
const sync = read('scripts/sync-ohos-build-sources.sh');

for (const name of [
  'getAstronomyReminderStatus',
  'getAstronomyReminders',
  'scheduleAstronomyReminder',
  'scheduleNextSolarTermReminder',
  'cancelAstronomyReminder',
  'clearAstronomyReminders'
]) {
  assert.match(ability, new RegExp(`request.commandName === '${name}'`), `${name} missing from QAbility`);
  assert.match(catalog, new RegExp(name), `${name} missing from native catalog`);
}

assert.match(service, /reminderAgentManager/);
assert.match(service, /getAllValidReminders/);
assert.match(service, /publishReminder/);
assert.match(manifest, /ohos\.permission\.PUBLISH_AGENT_REMINDER/);
assert.ok(fs.existsSync(path.join(root, 'harmonyos/ets-source/qability/AstronomyReminderService.ets')));
// sync-ohos-build-sources.sh mirrors the whole harmonyos/ets-source tree.
assert.match(sync, /mirror_ets_sources/);
const shortcutStart = ability.indexOf("if (request.commandName === 'scheduleNextSolarTermReminder')");
const shortcutEnd = ability.indexOf("if (request.commandName === 'cancelAstronomyReminder')", shortcutStart);
assert.ok(shortcutStart >= 0 && shortcutEnd > shortcutStart, 'solar-term reminder command block missing');
const shortcutHandler = ability.slice(shortcutStart, shortcutEnd);
assert.match(shortcutHandler, /this\.scheduleRealSolarTerm\(request\)/);
const shortcutMethod = ability.match(/  private async scheduleRealSolarTerm\([^\n]*\n[\s\S]*?\n  \}/);
assert.ok(shortcutMethod, 'wall-clock solar-term helper missing');
const shortcut = shortcutHandler + shortcutMethod[0];
assert.match(shortcut, /getAstronomyCalendarEvents/, 'shortcut must query the native month calendar');
assert.match(shortcut, /Date\.now\(\)|new Date\(\)/, 'shortcut must select from wall-clock time');
assert.doesNotMatch(shortcut, /getAlmanac|currentJD|rawCurrentJD|nextSolarTermDate|nextSolarTermJD|directNextDate/i,
  'shortcut must not schedule from simulation-year almanac snapshots');
assert.match(catalog, /getAstronomyCalendarEvents/, 'native month calendar command must be registered');
assert.match(read('src/StelMainView.cpp'), /getAstronomyCalendarEvents/);
console.log('HarmonyOS reminder contract passed.');
