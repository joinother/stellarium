import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../harmonyos/ets-source/', import.meta.url);
const read = name => readFileSync(new URL(name, root), 'utf8').replaceAll('\r\n', '\n');
const main = read('pages/MainWindowNativeNode.ets');
const ability = read('qability/QAbility.ets');
const block = (source, from, to) => source.slice(source.indexOf(from), source.indexOf(to, source.indexOf(from)));
const method = (source, from, to, deps = {}) => {
  const code = stripTypeScriptTypes('class Host {\n' + block(source, from, to) + '\n}');
  return new Function(...Object.keys(deps), code + ';return Host')(...Object.values(deps));
};
const storage = () => ({ values: {}, setOrCreate(key, value) { this.values[key] = value; } });
const i18n = { getLanguage: () => 'en' };
const policyCode = stripTypeScriptTypes(read('qability/AstronomyNotificationPolicy.ts').replaceAll('export ', ''));
const metadataCode = stripTypeScriptTypes(read('qability/AstronomyReminderMetadata.ts').replace(/^import .*\n/gm, '').replaceAll('export ', ''));
const routeFromUri = new Function(policyCode + metadataCode + '; return reminderRouteFromUri')();
const reminderService = { configure() {}, routeFromUri };

test('QAbility defaults event-route lead only for calendar reminders, preserving timer and alarm validation', async () => {
  const validateReminder = new Function(policyCode + '; return validateReminder')();
  const handler = block(ability, "    if (request.commandName === 'scheduleAstronomyReminder') {", "    if (request.commandName === 'scheduleNextSolarTermReminder') {");
  const code = stripTypeScriptTypes('class Host { dispatch(request) {\n' + handler + '\n} }');
  const saved = { passLeadMinutes: 15, dndEnabled: false, astronomyEventsEnabled: true };
  const eventAt = new Date(Date.now() + 86400000).toISOString();
  let received;
  const Host = new Function('AstronomyReminderService', 'hasCurrentPrivacyConsent', code + '; return Host')({
    schedule: async (payload, bundle, preferences, guard) => {
      received = payload;
      assert.equal(bundle, 'org.example.runtime');
      assert.equal(preferences, saved);
      assert.equal(guard(), true);
      return validateReminder(payload, Date.now(), preferences);
    }
  }, () => true);
  for (const scenario of [
    { reminderType: 'timer', expectedLead: undefined },
    { reminderType: 'alarm', expectedLead: undefined },
    { reminderType: 'calendar', expectedLead: 15 },
    { reminderType: undefined, expectedLead: 15 },
    { reminderType: 'calendar', leadMinutes: 0, expectedLead: 0 }
  ]) {
    const host = new Host();
    host.context = { abilityInfo: { bundleName: 'org.example.runtime' } };
    host.isForeground = true;
    host.loadReminderPreferences = async () => saved;
    const result = await new Promise(resolve => {
      host.finishCliRequest = (_request, response) => resolve(JSON.parse(response));
      host.dispatch({ commandName: 'scheduleAstronomyReminder', payload: JSON.stringify({
        title: 'Calendar event', content: 'Open the event detail', panel: 'calendar',
        eventId: 'meteor:stable', eventAt, reminderType: scenario.reminderType,
        triggerSeconds: 60, leadMinutes: scenario.leadMinutes
      }) });
    });
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(received.leadMinutes, scenario.expectedLead);
    assert.equal(result.value.route.panel, 'calendar');
    assert.equal(result.value.route.eventId, 'meteor:stable');
    assert.equal(result.value.route.eventAt, eventAt);
  }
});

test('getAstronomyReminders diagnostics is explicit, uses the guarded query and rechecks access before returning', async () => {
  const handler = block(ability, "    if (request.commandName === 'getAstronomyReminders') {", "    if (request.commandName === 'scheduleAstronomyReminder') {");
  const code = stripTypeScriptTypes('class Host { dispatch(request) {\n' + handler + '\n} }');
  let consent = true;
  let loseAccess = false;
  const calls = [];
  const Host = new Function('AstronomyReminderService', 'hasCurrentPrivacyConsent', code + '; return Host')({
    list: async (diagnostics, guard) => {
      calls.push(diagnostics);
      assert.equal(guard(), true);
      if (loseAccess) consent = false;
      return { ok: true, diagnostics: diagnostics ? { entries: [] } : undefined };
    }
  }, () => consent);
  const host = new Host(); host.isForeground = true;
  const dispatch = payload => new Promise(resolve => {
    host.finishCliRequest = (_request, response) => resolve(JSON.parse(response));
    host.dispatch({ commandName: 'getAstronomyReminders', payload });
  });
  assert.equal((await dispatch('')).diagnostics, undefined);
  assert.ok((await dispatch('diagnostics')).diagnostics);
  assert.ok((await dispatch('{"diagnostics":true}')).diagnostics);
  assert.equal((await dispatch('{"diagnostics":false}')).diagnostics, undefined);
  for (const payload of ['{', 'null', '[]', '{}', '{"diagnostics":"true"}']) assert.equal((await dispatch(payload)).ok, false);
  assert.deepEqual(calls, [false, true, true, false]);
  loseAccess = true;
  const denied = await dispatch('diagnostics');
  assert.equal(denied.ok, false);
  assert.equal(denied.diagnostics, undefined);
  const gate = block(ability, '    const notificationCommands =', "    if (request.commandName === 'getNotificationStatus') {");
  assert.match(gate, /getAstronomyReminders/);
  assert.match(gate, /!hasCurrentPrivacyConsent\(\) \|\| !this\.isForeground/);
});

test('QAbility merges nested event metadata even when top-level panel exists, preserving stable IDs', () => {
  const app = storage();
  const Host = method(ability, '  private routeCardWant(', '  private queueCliRequest(', { AppStorage: app, AstronomyReminderService: reminderService });
  const host = new Host();
  const eventId = 'meteor-peak-GEM-2026-262.2000';
  const eventAt = '2026-12-14T01:00:00.000Z';
  host.routeCardWant({ parameters: { panel: 'calendar', params: JSON.stringify({ eventId, eventAt }) } });
  const route = JSON.parse(app.values.stellariumCardRoute);
  assert.equal(route.eventId, eventId);
  assert.equal(route.eventAt, eventAt);
  host.routeCardWant({ parameters: { panel: 'calendar', eventId, jd: Date.parse(eventAt) / 86400000 + 2440587.5 } });
  assert.equal(JSON.parse(app.values.stellariumCardRoute).eventAt, eventAt);
});

test('URI-only reminder clicks preserve exact calendar identity after parameters are omitted', () => {
  const app = storage();
  const Host = method(ability, '  private routeCardWant(', '  private queueCliRequest(', { AppStorage: app, AstronomyReminderService: reminderService });
  const host = new Host();
  const route = { panel: 'calendar', eventId: 'meteor:特殊/id', eventAt: '2030-12-14T01:00:00Z', target: 'Moon' };
  const uri = 'skyinstrument://astronomy/reminder?notificationId=1000000000&route=' + encodeURIComponent(JSON.stringify(route));
  host.routeCardWant({ uri });
  assert.equal(JSON.parse(app.values.stellariumCardRoute).eventId, route.eventId);
  assert.equal(JSON.parse(app.values.stellariumCardRoute).eventAt, route.eventAt);
  host.routeCardWant({ uri, parameters: { panel: 'calendar' } });
  assert.equal(JSON.parse(app.values.stellariumCardRoute).eventId, route.eventId);
  const saved = app.values.stellariumCardRoute;
  for (const invalid of [uri + '%', 'https://other?route={}', 'skyinstrument://astronomy/reminder?notificationId=0&route=null']) host.routeCardWant({ uri: invalid });
  assert.equal(app.values.stellariumCardRoute, saved);
});

function routeFixture(events) {
  const app = storage();
  const Host = method(main, '  private consumeCardRoute(', '  // 协作会话分享', {
    AppStorage: app, I18n: i18n, hasCurrentPrivacyConsent: () => true,
    isCliPanelName: value => ['calendar', 'astro'].includes(value), hilog: { warn() {} }
  });
  const host = new Host();
  const feedSource = block(main, '        feedChanged: (events:', '\n      }\n      this.calendarController');
  const feedCode = stripTypeScriptTypes('const hooks = {\n' + feedSource + '\n};') + '; return hooks.feedChanged';
  host.feedChanged = new Function('I18n', feedCode).call(host, i18n);
  host.calendarStore = { loaded: false, loading: false, loadingMore: false, selectedEventId: 'old', selectedDay: 8 };
  host.engineReady = true;
  host.pendingCalendarEvent = '';
  host.refreshes = 0;
  host.notificationCtl = () => ({ refreshSubscriptions: async () => { host.refreshes++; } });
  host.calendarCtl = () => ({
    showMonthEvents: () => { host.calendarStore.selectedEventId = ''; },
    loadMonth: (year, month) => {
      host.month = [year, month];
      host.calendarStore.loading = true;
      host.calendarStore.loaded = false;
      host.feedChanged([]);
      host.complete = () => {
        host.calendarStore.loading = false;
        host.calendarStore.loaded = true;
        host.feedChanged(events);
      };
    }
  });
  host.openPanelFromCli = panel => { host.panel = panel; };
  return host;
}

test('notification opens exact month then selects only matching event ID and event time', () => {
  const at = Date.parse('2030-12-14T01:00:00Z');
  const host = routeFixture([{ id: 'meteor:stable', at }]);
  host.cardRoute = JSON.stringify({ panel: 'calendar', eventId: 'meteor:stable', eventAt: new Date(at).toISOString() });
  host.consumeCardRoute();
  assert.equal(host.panel, 'calendar');
  assert.deepEqual(host.month, [new Date(at).getFullYear(), new Date(at).getMonth() + 1]);
  assert.notEqual(host.pendingCalendarEvent, '');
  assert.equal(host.calendarStore.selectedEventId, '');
  host.complete();
  assert.equal(host.calendarStore.selectedEventId, 'meteor:stable');
  assert.equal(host.calendarStore.selectedDay, 0);
  assert.equal(host.pendingCalendarEvent, '');
  assert.equal(host.refreshes, 0);
  host.feedChanged([{ id: 'meteor:stable', at }]);
  assert.equal(host.refreshes, 0);
});

test('missing ID or mismatched time never fabricates selected event; newer routes supersede pending detail', () => {
  const at = Date.now();
  for (const events of [[], [{ id: 'wanted', at: at + 60000 }], [{ id: 'other', at }]]) {
    const host = routeFixture(events);
    host.cardRoute = JSON.stringify({ panel: 'calendar', eventId: 'wanted', eventAt: new Date(at).toISOString() });
    host.consumeCardRoute(); host.complete();
    assert.equal(host.calendarStore.selectedEventId, '');
    assert.match(host.calendarStore.actionMessage, /not found/);
  }
  const host = routeFixture([{ id: 'wanted', at }]);
  host.cardRoute = JSON.stringify({ panel: 'calendar', eventId: 'wanted', eventAt: new Date(at).toISOString() });
  host.consumeCardRoute();
  host.cardRoute = JSON.stringify({ panel: 'astro' });
  host.consumeCardRoute(); host.complete();
  assert.equal(host.calendarStore.selectedEventId, '');
});

test('semantic CLI reports controller failure instead of unconditional success', async () => {
  const app = storage();
  const Host = method(main, '  private async executeFeatureCli(', '  // 巡天 /', {
    AppStorage: app, hasCurrentPrivacyConsent: () => true
  });
  const host = new Host();
  host.applicationInForeground = true;
  host.notificationStore = { astronomyEventsEnabled: false };
  host.notificationCtl = () => ({ loadPreferences: async () => {},
    changeSubscription: async () => ({ ok: false, reason: 'subscription-rolled-back', error: 'quota' }) });
  await host.executeFeatureCli('setNotificationSubscription', 'astronomy|on', 'request-1');
  const result = JSON.parse(app.values.stellariumFeatureCliResult);
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'subscription-rolled-back');
  assert.equal(result.error, 'quota');
  assert.equal(result.state.astronomyEventsEnabled, false);
});

test('quiet-hours CLI is routed with foreground/privacy guards and waits for the actual save outcome', async () => {
  const app = storage();
  let foregroundConsent = true;
  const Host = method(main, '  private async executeFeatureCli(', '  // 巡天 /', {
    AppStorage: app, hasCurrentPrivacyConsent: () => foregroundConsent
  });
  const host = new Host();
  host.applicationInForeground = true;
  host.notificationStore = { dndEnabled: true, dndStartMinutes: 1350, dndEndMinutes: 395 };
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let calls = 0;
  host.notificationCtl = () => ({ loadPreferences: async () => {}, setQuietHours: async value => {
    calls++;
    assert.deepEqual(value, { enabled: false, startMinutes: 1350, endMinutes: 395 });
    await gate;
    return { ok: false, reason: 'preferences-update-failed', error: 'disk error' };
  } });
  const payload = JSON.stringify({ enabled: false, startMinutes: 1350, endMinutes: 395 });
  const saving = host.executeFeatureCli('setNotificationQuietHours', payload, 'quiet-1');
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(app.values.stellariumFeatureCliResult, undefined);
  release(); await saving;
  const response = JSON.parse(app.values.stellariumFeatureCliResult);
  assert.equal(response.ok, false);
  assert.equal(response.error, 'disk error');
  assert.equal(response.state.dndEnabled, true);
  await host.executeFeatureCli('setNotificationQuietHours', '{', 'quiet-2');
  assert.equal(JSON.parse(app.values.stellariumFeatureCliResult).ok, false);
  assert.equal(JSON.parse(app.values.stellariumFeatureCliResult).state.dndStartMinutes, 1350);
  foregroundConsent = false;
  await host.executeFeatureCli('setNotificationQuietHours', payload, 'quiet-3');
  assert.equal(calls, 1);
  assert.match(ability, /request\.commandName === 'setNotificationQuietHours'/);
  const catalog = readFileSync(new URL('../src/StelOhosCommandCatalog.hpp', import.meta.url), 'utf8');
  const restricted = block(catalog, 'inline bool isRestricted(', '\ninline ',);
  for (const name of ['setNotificationSubscription', 'setNotificationQuietHours']) {
    assert.ok(restricted.includes('name == "' + name + '"'));
  }
});

test('native adapter checks object envelope rather than asserting incompatible bridge arrays', () => {
  const source = read('capability/AstronomySubscriptionFeed.ets');
  const plain = stripTypeScriptTypes(source.replace(/^import .*\n/gm, '').replaceAll('export ', ''));
  const decode = new Function(plain + ';return decodeSubscriptionNativeResponse')();
  const envelope = { ok: true, satellitePasses: { satelliteId: '25544', calculatedAt: '2030-01-01T00:00:00Z',
    orbitValid: true, dataStatus: 'local', passes: [] } };
  assert.deepEqual(decode(JSON.stringify(envelope)), envelope);
  assert.throws(() => decode(JSON.stringify({ ok: true, satellitePasses: [] })), /envelope/);
  const unsupported = { ok: false, reason: 'explicit_epoch_prediction_unsupported' };
  assert.deepEqual(decode(JSON.stringify(unsupported)), unsupported);
  assert.doesNotMatch(block(main, '  private notificationCtl(', '  private haptics('), /as SubscriptionNativeResponse|as unknown/);
  assert.match(readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8'), /result\["satellitePasses"\] = response/);
});

test('notification landing routes dispatch notification-settings, satellite pass sky jump, and gyro star-finding mode', () => {
  const host = routeFixture([]);
  const calls = [];
  host.openPanelFromCli = panel => { calls.push(['panel', panel]); };
  host.setPanel = (panel, immediate, silent) => { calls.push(['setPanel', panel, immediate, silent]); };
  host.timeTransitionCtl = () => ({
    animate: (jd, label, onDone) => { calls.push(['animate', jd, label]); onDone(); }
  });
  host.callInteractive = (cmd, arg, onOk) => { calls.push(['call', cmd, arg]); onOk({ ok: true, target: arg }); };
  host.applySelectedObject = resp => { calls.push(['applySelected', resp.target]); };
  host.refreshState = () => { calls.push(['refreshState']); };
  host.gyroCtl = () => ({ toggleGyroscope: on => { calls.push(['gyro', on]); } });
  host.satelliteCtl = () => ({ setSatelliteFlag: (name, on) => { calls.push(['satFlag', name, on]); } });

  host.cardRoute = JSON.stringify({ panel: 'notification-settings' });
  host.consumeCardRoute();
  assert.equal(host.configTab, -1);
  assert.deepEqual(calls.splice(0), [['panel', 'settings']]);

  const passAt = Date.parse('2030-11-20T12:30:00Z');
  host.cardRoute = JSON.stringify({
    panel: 'satellites', kind: 'satellite-pass', eventId: 'satellite-pass-25544-1234',
    target: 'ISS (ZARYA)', eventAt: new Date(passAt).toISOString()
  });
  host.consumeCardRoute();
  assert.deepEqual(calls[0], ['setPanel', '', true, true]);
  assert.deepEqual(calls[1], ['satFlag', 'hints', true]);
  assert.equal(calls[2][0], 'call');
  assert.equal(calls[2][1], 'setJD');
  assert.deepEqual(calls[3], ['call', 'searchObject', 'object|Satellite|25544']);
  assert.deepEqual(calls[4], ['applySelected', 'object|Satellite|25544']);
  assert.deepEqual(calls[5], ['call', 'moveToSelected', '']);
  assert.deepEqual(calls[6], ['refreshState']);
  calls.splice(0);

  // Feed-style pass:<norad>:<obs>:<sec> eventId also resolves to object|Satellite|<norad> and centers camera
  host.cardRoute = JSON.stringify({
    panel: 'satellites', kind: 'satellite-pass', eventId: 'pass:20580:default:1795303634',
    target: 'HST', eventAt: new Date(passAt).toISOString()
  });
  host.consumeCardRoute();
  assert.equal(calls[2][1], 'setJD');
  assert.deepEqual(calls[3], ['call', 'searchObject', 'object|Satellite|20580']);
  assert.deepEqual(calls[5], ['call', 'moveToSelected', '']);
  assert.deepEqual(calls[6], ['refreshState']);
  calls.splice(0);

  // Calendar notifications always land in the Astronomy Calendar panel on the exact month/event;
  // jumping into the sky + centering happens when the user taps "View sky" inside the calendar event.
  host.cardRoute = JSON.stringify({
    panel: 'calendar', kind: 'planetary-event', eventId: 'planetary-event-Uranus-Sun-opposition-1795646520',
    target: 'Uranus', eventAt: new Date(passAt).toISOString()
  });
  host.calendarStore = { loaded: false, loading: false, loadingMore: false, selectedEventId: '', selectedDay: 0, actionMessage: '' };
  host.calendarCtl = () => ({
    showMonthEvents: () => { calls.push(['calendarShowMonth']); },
    loadMonth: (y, m) => { calls.push(['calendarLoadMonth', y, m]); }
  });
  host.consumeCardRoute();
  assert.deepEqual(calls[0], ['calendarShowMonth']);
  assert.deepEqual(calls[1], ['calendarLoadMonth', new Date(passAt).getFullYear(), new Date(passAt).getMonth() + 1]);
  assert.deepEqual(calls[2], ['panel', 'calendar']);
  calls.splice(0);

  host.cardRoute = JSON.stringify({ panel: 'sky', kind: 'find', target: 'Moon' });
  host.consumeCardRoute();
  assert.deepEqual(calls, [
    ['setPanel', '', true, true],
    ['call', 'searchObject', 'Moon'],
    ['applySelected', 'Moon'],
    ['gyro', true],
    ['refreshState']
  ]);
});

test('landing time-changed pill resets via real actionReturn_To_Current_Time and calendar viewSky uses typed target resolution', () => {
  const resetBlock = block(main, '  private returnToNowFromLanding(', '  private toggleFindStarFromLanding(');
  assert.doesNotMatch(resetBlock, /'setTimeNow'/);
  assert.match(resetBlock, /triggerAction',\s*'actionReturn_To_Current_Time'/);
  assert.match(resetBlock, /resetRateToRealTime\(\)/);

  const calendarsStore = read('state/CalendarsStore.ets');
  assert.doesNotMatch(calendarsStore, /'setTimeToNow'/);
  assert.match(calendarsStore, /triggerAction',\s*'actionReturn_To_Current_Time'/);

  const uiPointBlock = block(main, '  private isUiPoint(', '  private handleOverlayTouch(');
  assert.match(uiPointBlock, /landingBannerVisible[\s\S]*landingTimePillY\(\)/);

  const calendarViewBlock = block(main, '        viewSky: (event: AstronomyCalendarEvent): void => {', '        remind: (event: AstronomyCalendarEvent)');
  assert.match(calendarViewBlock, /object\|Planet\|\$\{rawTarget\}/);
  assert.match(calendarViewBlock, /object\|MeteorShower\|\$\{showerCode\}/);
  assert.match(calendarViewBlock, /object\|Satellite\|\$\{satId\}/);
  assert.match(calendarViewBlock, /setMeteorShowersFlag',\s*'enabled\|1'/);
  assert.match(calendarViewBlock, /setMeteorShowersFlag',\s*'marker\|1'/);
  assert.match(calendarViewBlock, /applySelectedObject\(response,\s*false,\s*'',\s*true\)/);

  const mainViewCpp = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
  const searchBlock = block(mainViewCpp, '\t\tif (commandName == "searchObject")', '\tif (commandName == "listMatchingObjects")');
  const fallbackRegion = searchBlock.slice(searchBlock.indexOf('GETSTELMODULE(SolarSystem)'));
  const findSelectIdx = fallbackRegion.indexOf('objectMgr->findAndSelectI18n(query)');
  const satIdx = fallbackRegion.indexOf('satellites->searchByNameI18n(query)');
  assert.ok(findSelectIdx > 0 && satIdx > findSelectIdx,
    'SolarSystem and StelObjectMgr must resolve before Satellites fallback in searchObject');

  const satellitesCpp = readFileSync(new URL('../plugins/Satellites/src/Satellites.cpp', import.meta.url), 'utf8');
  const normBlock = block(satellitesCpp, 'QString normalizeSatelliteSearch(', 'bool satelliteMatchesExactNormalized(');
  assert.doesNotMatch(normBlock, /QRegularExpression/, 'normalizeSatelliteSearch must not compile regexes per satellite');
  const searchByNameBlock = block(satellitesCpp, 'StelObjectP Satellites::searchByNameI18n(', 'StelObjectP Satellites::searchByID(');
  assert.doesNotMatch(searchByNameBlock, /satelliteMatchesSearch\(/, 'exact satellite lookups must not use substring search');
});

test('search panel embeds calendar preview strip and dock menu remembers calendar route and scroll position across close/reopen', () => {
  const searchPanel = read('panels/panels/SearchPanel.ets');
  assert.match(searchPanel, /SearchCalendarStrip\(\{/);
  assert.match(searchPanel, /onOpenCalendar:/);
  assert.match(searchPanel, /onOpenCalendarEvent:/);

  const strip = read('panels/search/SearchCalendarStrip.ets');
  assert.match(strip, /this\.onOpenCalendar\(\)/);
  assert.match(strip, /ScrollDirection\.Horizontal/);

  const dockBlock = block(main, '  private activateDockAction(', '  private activateDockAtLocal(');
  assert.match(dockBlock, /this\.dockPanelMemory\.get\(item\.panel\)/);
  assert.match(dockBlock, /this\.saveCurrentDockPanelMemory\(\)/);
  assert.match(dockBlock, /this\.pendingScrollRestoreOffsetY/);

  const closeBlock = block(main, '  private closePanel(', '  private publishUiPanelState(');
  assert.match(closeBlock, /this\.saveCurrentDockPanelMemory\(\)/);

  const backBlock = block(main, '  private handlePanelBackTap(', '  private goBackPanel(');
  assert.match(backBlock, /this\.activePanel === 'calendar' && this\.calendarStore\.selectedEventId\.length > 0/);
  assert.match(backBlock, /this\.restoreScrollKeyAsync\('calendar:list'/);
});

test('layer-1 TIMER live view complies with SDK timer/flight layout and module.json5 drops unused sensor permissions', () => {
  const liveViewSrc = read('capability/LiveViewController.ets');
  assert.ok(liveViewSrc.includes("event: 'TIMER'"), 'live view must target TIMER scenario');
  assert.ok(liveViewSrc.includes('CapsuleType.CAPSULE_TYPE_TIMER'), 'capsule must use official CAPSULE_TYPE_TIMER enum');
  assert.ok(liveViewSrc.includes('${placeholder.timer}'), 'live view must use system native timer placeholder');
  assert.ok(liveViewSrc.includes('LayoutType.LAYOUT_TYPE_FLIGHT'), 'satellite passes should render FlightLayout rise/set extension');
  assert.ok(liveViewSrc.includes('ExtensionType.EXTENSION_TYPE_CAPSULE_TEXT'), 'TIMER spec requires auxiliary status text');
  assert.ok(liveViewSrc.includes('liveViewManager.stopLiveView(stopView)'), 'stopLiveView must pass a LiveView object');

  const moduleJsonText = read('../module.json5').replace(/^\s*\/\/.*$/gm, '');
  const moduleJson = JSON.parse(moduleJsonText);
  const permNames = moduleJson.module.requestPermissions.map(p => p.name);
  assert.ok(!permNames.includes('ohos.permission.ACCELEROMETER'), 'unused ACCELEROMETER permission should be removed');
  assert.ok(!permNames.includes('ohos.permission.GYROSCOPE'), 'unused GYROSCOPE permission should be removed');
  const qAbility = moduleJson.module.abilities.find(a => a.name === 'QAbility');
  const homeSkill = qAbility.skills.find(s => Array.isArray(s.entities) && s.entities.includes('entity.system.home'));
  assert.ok(homeSkill !== undefined && homeSkill.uris === undefined, 'home skill must not mix uris per Push Kit skill rules');
});

test('settings panel defaults to Device & Privacy (-1) and resolves more as route parent for back navigation', () => {
  const actionsSrc = read('common/derive/actions.ets');
  const routeParentFn = actionsSrc.slice(
    actionsSrc.indexOf('export function panelRouteParent('),
    actionsSrc.indexOf('export function inferredPanelRouteDirection(')
  );
  assert.match(routeParentFn, /moreActions\(\)\.some\(\(item: ShellAction\) => item\.panel === panel\)\) return 'more'/);

  assert.match(main, /@State private configTab: number = -1/);
  const setPanelHead = main.slice(main.indexOf('private setPanel('), main.indexOf('const currentPanel = this.activePanel'));
  assert.match(setPanelHead, /this\.activePanel === 'more' && routeDirection >= 0/);
  assert.match(setPanelHead, /this\.configTab = -1/);

  const canGoBackBlock = block(main, '  private canGoBackPanel(', '  private handlePanelBackTap(');
  assert.match(canGoBackBlock, /this\.panelNavigationDepth > 0 \|\| panelRouteParent\(this\.activePanel\)\.length > 0/);

  const settingsLoad = main.slice(main.indexOf("} else if (panel === 'settings') {"), main.indexOf("} else if (panel === 'place') {"));
  assert.match(settingsLoad, /if \(this\.configTab === -1\) void this\.notificationCtl\(\)\.refreshStatus\(\)/);
});

test('in-app satellite pass alert renders rounded 3D orthographic Earth orbit card with offline fallback and preview trigger', () => {
  const cardSrc = read('panels/satellite/SatellitePassAlertCard.ets');
  assert.ok(cardSrc.includes('export struct SatellitePassAlertCard'), 'SatellitePassAlertCard component must exist');
  assert.ok(cardSrc.includes('stellarium/textures/earth_cmap.png'), 'card must read bundled physical earth_cmap.png');
  assert.ok(!cardSrc.includes('worldmap.jpg'), 'card must never reference uncertified political worldmap.jpg');
  assert.ok(cardSrc.includes('NIGHT_CITY_LIGHTS'), 'card must render night-side city lights');
  assert.ok(cardSrc.includes('ORBIT_RADIUS_EARTH'), 'card must render elevated 3D orbital ring');
  assert.ok(cardSrc.includes('computeSolarSubpoint'), 'card must compute day/night solar terminator');
  assert.ok(cardSrc.includes('onTrackInSky') && cardSrc.includes('onToggleLiveView') && cardSrc.includes('onDismiss'),
    'card must expose sky tracking, Live View toggle, and dismiss callbacks');
  assert.ok(cardSrc.includes('borderRadius(28)'), 'card must use rounded floating card framing');

  assert.ok(main.includes('SatellitePassAlertCard({'), 'MainWindowNativeNode must mount SatellitePassAlertCard');
  assert.ok(main.includes('this.satAlertCardWidth()') && main.includes('this.satAlertCardHeight()'),
    'isUiPoint must protect full SatellitePassAlertCard touch bounds');
  assert.ok(main.includes('previewSatPassCard: () => { this.previewSatellitePassAlertCard() }'),
    'Settings Live View section must expose pass card preview hook');

  const notifSrc = read('panels/settings/NotificationSection.ets');
  assert.ok(notifSrc.includes('onPreviewSatPassCard'), 'NotificationSection must expose preview pass card button');
  assert.ok(!notifSrc.includes('RegionScopePicker'), 'NotificationSection must not expose custom region picker');
});

test('calendar eclipse map integrates Petal Maps fullscreen explorer with Mercator overlay, polyline path, and offline fallback', () => {
  const modalSrc = read('panels/calendar/CalendarEclipsePetalModal.ets');
  assert.ok(modalSrc.includes("from '@kit.MapKit'"), 'eclipse modal must use HarmonyOS Map Kit');
  assert.ok(modalSrc.includes('addImageOverlay'), 'eclipse modal must render Web Mercator eclipse PixelMap overlay');
  assert.ok(modalSrc.includes('addPolyline'), 'solar eclipse modal must render central totality path polyline');
  assert.ok(modalSrc.includes('rectifyCoordinate'), 'observer blue pin must rectify WGS84 to GCJ02 inside China');
  assert.ok(modalSrc.includes("$rawfile('stellarium/textures/earth_cmap.png')"), 'offline fallback must use bundled physical earth_cmap.png');
  assert.ok(!modalSrc.includes('worldmap.jpg'), 'eclipse modal must never reference uncertified political worldmap.jpg');

  const visualsSrc = read('panels/calendar/CalendarEventVisuals.ets');
  assert.ok(visualsSrc.includes('CalendarEclipsePetalModal({'), 'CalendarEclipseMapCard must mount CalendarEclipsePetalModal');
  assert.ok(visualsSrc.includes('onlineMapAllowed'), 'CalendarEclipseMapCard must honor privacy/online gate');

  const calSrc = read('panels/panels/AstronomyCalendarPanel.ets');
  assert.ok(calSrc.includes('onlineMapAllowed: this.onlineMapAllowed'), 'AstronomyCalendarPanel must forward onlineMapAllowed');
});
