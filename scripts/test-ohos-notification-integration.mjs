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
