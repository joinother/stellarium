import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../harmonyos/ets-source/', import.meta.url);
const read = name => readFileSync(new URL(name, root), 'utf8');
const plain = source => stripTypeScriptTypes(source.replace(/^import .*\n/gm, '').replace(/^@Observed\s*$/gm, '').replaceAll('export ', ''));
const policy = plain(read('qability/AstronomyNotificationPolicy.ts'));
const subscriptionPolicy = plain(read('state/OnlineContentContract.ts')) + plain(read('qability/AstronomySubscriptionPolicy.ts'));
const controller = plain(read('capability/NotificationController.ets'));
const notificationText = new Function('I18n', plain(read('capability/NotificationText.ets')) + ';return notificationText')({ getLanguage: () => 'zh_CN' });
const Store = new Function('notificationText', plain(read('state/NotificationStore.ets')) + ';return NotificationStore')(notificationText);
const preferenceValue = changes => ({ subscriptionsVersion: 1, astronomyEventsEnabled: true, satellitePassEnabled: false, digestEnabled: false, dndEnabled: false, dndStartMinutes: 1320, dndEndMinutes: 360, passLeadMinutes: 15, ...changes });

function fixture(initial) {
  const store = new Store();
  const state = { cached: initial === undefined ? '' : JSON.stringify(initial), persisted: initial === undefined ? '' : JSON.stringify(initial), flushes: 0, reads: 0, scheduled: [], hints: [], items: [], cancelIds: [], calendarOpens: 0 };
  const settings = {
    get: async () => { state.reads++; if (state.readError) throw Error('read'); return state.cached; },
    put: async (key, value) => { state.cached = value; },
    flush: async () => { state.flushes++; if (state.flushError) throw Error('flush'); state.persisted = state.cached; }
  };
  const preferences = { getPreferences: async (context, options) => { assert.equal(options.name, 'stellarium_astronomy_reminders'); return settings; } };
  const reminders = {
    configure: () => {},
    schedule: async (payload, bundle, prefs) => { state.scheduled.push({ payload, bundle, prefs }); return state.scheduleResult ?? { ok: true }; },
    list: async () => state.listError ? { ok: false, error: 'read failed' } : { ok: true, items: state.items.slice() },
    cancel: async id => { state.cancelIds.push(id); state.items = state.items.filter(item => item.reminderId !== id); return { ok: true }; },
    cancelAll: async () => { state.items = []; return { ok: true }; }
  };
  reminders.cancelOwned = async item => reminders.cancel(item.reminderId);
  const notifications = { status: async () => state.notificationStatus ?? { ok: true, notificationEnabled: true }, requestAuthorization: async () => true };
  const Controller = new Function('preferences', 'AstronomyReminderService', 'AstronomyNotificationService', 'hasCurrentPrivacyConsent', 'notificationText', policy + subscriptionPolicy + controller + ';return NotificationController')(preferences, reminders, notifications, () => state.consent !== false, notificationText);
  const hooks = { canInteract: () => state.foreground !== false, openCalendar: () => { state.calendarOpens++; }, hostContext: () => ({ abilityInfo: { bundleName: 'org.runtime.app' } }), flashHint: text => state.hints.push(text), almanacSolarTerms: () => { throw Error('stale simulation snapshot'); }, loadAlmanac: () => {}, moonPhases: () => { throw Error('stale simulation snapshot'); }, loadMoonPhases: () => {}, meteorShowers: () => { throw Error('stale simulation snapshot'); }, loadMeteorShowers: () => {} };
  const instance = new Controller(store, hooks);
  return { state, store, instance, hooks, notifications, reminders };
}

const event = () => {
  const at = Date.now() + 86400000;
  return { id: 'term:2030:5', title: '春分', at, jd: at / 86400000 + 2440587.5, body: 'event', target: 'Sun', panel: 'astro', tab: 8, kind: 'equinox' };
};

function subscriptionFixture(changes = {}) {
  const model = fixture(preferenceValue(changes));
  model.state.feedCalls = 0;
  model.state.nextId = 0;
  const selected = event();
  model.hooks.loadSubscriptionEvents = async category => {
    model.state.feedCalls++;
    if (model.state.feedGate) await model.state.feedGate;
    if (model.state.feedError) throw Error('feed');
    return { generatedAt: Date.now(), observerKey: 'chosen-earth-observer', events: model.state.feedEvents ??
      [{ ...selected, kind: category === 'satellite' ? 'satellite-pass' : selected.kind }] };
  };
  model.reminders.schedule = async (payload, bundle, prefs, guard, limit) => {
    assert.equal(limit, 24);
    assert.equal(guard(), true);
    model.state.scheduled.push({ payload, prefs });
    if (model.state.scheduleResult) return model.state.scheduleResult;
    const match = model.state.items.find(item => item.eventId === payload.eventId && item.subscription === payload.subscription && item.eventAt === payload.eventAt);
    if (match) return { ok: true, reminderId: match.reminderId, unchanged: true };
    const reminderId = model.state.nextId++;
    model.state.items.push({ ...payload, reminderId });
    return { ok: true, reminderId };
  };
  return model;
}

test('legacy manual preferences never silently opt into subscriptions; new satellite/digest fields persist', async () => {
  const old = preferenceValue(); delete old.subscriptionsVersion;
  const legacy = fixture(old);
  await legacy.instance.loadPreferences();
  assert.equal(legacy.store.astronomyEventsEnabled, false);
  assert.equal(legacy.store.satellitePassEnabled, false);
  const model = fixture(preferenceValue({ satellitePassEnabled: true, digestEnabled: true }));
  await model.instance.loadPreferences();
  assert.equal(model.store.satellitePassEnabled, true);
  assert.equal(model.store.digestEnabled, true);
  model.instance.persistPreferences();
  await model.instance.preferenceQueue;
  assert.equal(JSON.parse(model.state.persisted).satellitePassEnabled, true);
});

test('quiet-hours command awaits durable preferences and returns actual rollback without false success', async () => {
  const model = fixture(preferenceValue({ dndEnabled: true, dndStartMinutes: 1350, dndEndMinutes: 395 }));
  let refreshes = 0;
  model.instance.refreshSubscriptions = async () => { refreshes++; };
  const off = { enabled: false, startMinutes: 1350, endMinutes: 395 };
  assert.equal((await model.instance.setQuietHours(off)).ok, true);
  assert.equal(JSON.parse(model.state.persisted).dndEnabled, false);
  assert.equal(refreshes, 1);
  model.state.flushError = true;
  assert.equal((await model.instance.setQuietHours({ ...off, enabled: true })).reason, 'preferences-update-failed');
  assert.equal(model.store.dndEnabled, false);
  assert.equal(JSON.parse(model.state.persisted).dndEnabled, false);
  assert.equal(refreshes, 1);
  model.state.flushError = false;
  await model.instance.loadPreferences();
  model.store.notificationPreferencesError = '';
  assert.equal((await model.instance.setQuietHours({ ...off, enabled: true })).ok, true);
  assert.equal(JSON.parse(model.state.persisted).dndStartMinutes, 1350);
  assert.equal(JSON.parse(model.state.persisted).dndEndMinutes, 395);
});

test('quiet-hours invalid inputs, background, pending writes and read failure never report success', async () => {
  const model = fixture(preferenceValue());
  for (const value of [null, undefined, [], {}, { enabled: 'false', startMinutes: 0, endMinutes: 1 },
    { enabled: true, startMinutes: -1, endMinutes: 1 }, { enabled: true, startMinutes: 0, endMinutes: 1440 },
    { enabled: true, startMinutes: 1.5, endMinutes: 1 }]) assert.equal((await model.instance.setQuietHours(value)).ok, false);
  assert.equal(model.state.flushes, 0);
  const valid = { enabled: true, startMinutes: 1350, endMinutes: 395 };
  model.state.foreground = false;
  assert.equal((await model.instance.setQuietHours(valid)).reason, 'busy');
  model.state.foreground = true;
  model.store.notificationPreferencesBusy = true;
  assert.equal((await model.instance.setQuietHours(valid)).reason, 'busy');
  model.store.notificationPreferencesBusy = false;
  const broken = fixture(preferenceValue());
  broken.state.readError = true;
  assert.equal((await broken.instance.setQuietHours(valid)).reason, 'preferences-unavailable');
  assert.equal(broken.state.flushes, 0);
});

test('legacy metadata uncertainty leaves existing preferences and reminders but never reports subscription success', async () => {
  const model = subscriptionFixture();
  model.state.items = [{ reminderId: 2, kind: 'unknown', eventId: '' }];
  model.state.scheduleResult = { ok: false, reminderId: 2, reason: 'legacy-reminder-unverified', error: 'Review existing reminders first' };
  const outcome = await model.instance.changeSubscription('astronomy', true);
  assert.equal(outcome.ok, false);
  assert.equal(model.store.astronomyEventsEnabled, true);
  assert.equal(model.store.astronomySubscriptionOk, false);
  assert.deepEqual(model.state.cancelIds, []);
  assert.equal(model.state.scheduled.length, 1);
  assert.match(model.store.astronomySubscriptionStatus, /Review/);
});

test('rolling refresh coalesces concurrent runs and disable cancels only category ownership', async () => {
  const { instance, state, store } = subscriptionFixture({ satellitePassEnabled: true });
  state.items.push({ reminderId: 90, eventId: 'manual', kind: 'moon-phase' });
  await Promise.all(Array.from({ length: 12 }, () => instance.refreshSubscriptions()));
  assert.equal(state.items.length, 3);
  assert.equal(state.scheduled.length, 2);
  assert.equal(state.scheduled[0].payload.panel, 'calendar');
  assert.equal(state.scheduled[0].payload.leadMinutes, 0);
  assert.equal(state.scheduled[1].payload.leadMinutes, 15);
  instance.setAstronomyEventsEnabled(false);
  await instance.preferenceQueue;
  await instance.refreshSubscriptions();
  assert.ok(state.items.some(item => item.reminderId === 90));
  assert.ok(state.items.some(item => item.subscription === 'satellite'));
  assert.ok(!state.items.some(item => item.subscription === 'astronomy'));
  assert.equal(store.astronomyEventsEnabled, false);
});

test('zero entitlement stops at first system rejection and persists switches off without retry storm', async () => {
  const { instance, state, store } = subscriptionFixture({ satellitePassEnabled: true });
  state.scheduleResult = { ok: false, code: 1700002, reason: 'quota-or-entitlement', error: 'quota or entitlement' };
  await instance.refreshSubscriptions();
  await instance.preferenceQueue;
  assert.equal(state.scheduled.length, 1);
  assert.equal(store.astronomyEventsEnabled, false);
  assert.equal(store.satellitePassEnabled, false);
  assert.equal(JSON.parse(state.persisted).astronomyEventsEnabled, false);
  assert.equal(store.astronomyNotificationStatus, 'quota or entitlement');
  await instance.refreshSubscriptions();
  assert.equal(state.scheduled.length, 1);
});

test('unavailable satellite prediction disables persisted subscription and cancels only its owned reminders', async () => {
  for (const failCancel of [false, true]) {
    const model = subscriptionFixture({ astronomyEventsEnabled: false, satellitePassEnabled: true });
    model.state.items = [{ reminderId: 0, subscription: 'satellite' }, { reminderId: 10, kind: 'satellite-pass' }];
    model.state.feedError = true;
    if (failCancel) model.reminders.cancel = async () => ({ ok: false });
    await model.instance.refreshSubscriptions();
    await model.instance.preferenceQueue;
    assert.equal(model.store.satellitePassEnabled, false);
    assert.equal(JSON.parse(model.state.persisted).satellitePassEnabled, false);
    assert.equal(model.state.scheduled.length, 0);
    assert.ok(model.state.items.some(item => item.reminderId === 10));
    assert.equal(model.state.items.length, failCancel ? 2 : 1);
    assert.match(model.store.satelliteSubscriptionStatus, failCancel ? /未能全部取消/ : /暂不可用/);
  }
});

test('semantic subscription change returns actual rollback, cancellation and persistence outcomes', async () => {
  const failed = subscriptionFixture();
  failed.state.scheduleResult = { ok: false, code: 1700002, reason: 'quota-or-entitlement', error: 'system quota' };
  assert.equal((await failed.instance.changeSubscription('astronomy', true)).ok, false);
  assert.equal(failed.store.astronomyEventsEnabled, false);
  const saved = subscriptionFixture();
  assert.equal((await saved.instance.changeSubscription('astronomy', true)).ok, true);
  saved.reminders.cancel = async () => ({ ok: false, error: 'cancel failed' });
  assert.equal((await saved.instance.changeSubscription('astronomy', false)).ok, false);
  const persistence = subscriptionFixture();
  persistence.state.flushError = true;
  assert.equal((await persistence.instance.changeSubscription('astronomy', true)).ok, false);
  assert.equal(persistence.state.scheduled.length, 0);
});

test('disable while feed is pending invalidates publication and reconciles newest preferences', async () => {
  const { instance, state } = subscriptionFixture();
  let release;
  state.feedGate = new Promise(resolve => { release = resolve; });
  const pending = instance.refreshSubscriptions();
  await new Promise(resolve => setImmediate(resolve));
  instance.setAstronomyEventsEnabled(false);
  await instance.preferenceQueue;
  release();
  await pending;
  assert.equal(state.scheduled.length, 0);
});

test('busy status, authorization, manual schedule and cancel each resume one coalesced subscription refresh', async () => {
  for (const operation of ['status', 'authorization', 'schedule', 'cancel']) {
    const model = subscriptionFixture();
    await model.instance.loadPreferences();
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    let pending;
    if (operation === 'status') {
      const original = model.notifications.status;
      model.notifications.status = async () => { await gate; return original(); };
      pending = model.instance.refreshStatus();
    } else if (operation === 'authorization') {
      model.notifications.requestAuthorization = async () => { await gate; throw Error('authorization failed'); };
      pending = model.instance.requestAccess();
    } else if (operation === 'schedule') {
      const original = model.reminders.schedule;
      model.reminders.schedule = async (...args) => {
        if (args[0].subscription) return original(...args);
        await gate; return { ok: true };
      };
      pending = model.instance.scheduleEvent(event());
    } else {
      model.reminders.cancel = async () => { await gate; throw Error('cancel failed'); };
      pending = model.instance.cancelAction(0);
    }
    await Promise.all(Array.from({ length: 10 }, () => model.instance.refreshSubscriptions()));
    assert.equal(model.instance.subscriptionRequested, true, operation);
    assert.equal(model.state.feedCalls, 0, operation);
    release();
    await pending;
    await model.instance.subscriptionRun;
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(model.state.feedCalls, 1, operation);
    assert.equal(model.instance.subscriptionRequested, false, operation);
    assert.equal(model.store.astronomyNotificationBusy, false, operation);
    assert.equal(model.instance.subscriptionRun, undefined, operation);
  }
});

test('deferred refresh stays pending in background without self-retry and runs on foreground trigger', async () => {
  const model = subscriptionFixture();
  await model.instance.loadPreferences();
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  model.notifications.requestAuthorization = async () => { await gate; return true; };
  const pending = model.instance.requestAccess();
  await model.instance.refreshSubscriptions();
  model.state.foreground = false;
  release();
  await pending;
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(model.state.feedCalls, 0);
  assert.equal(model.instance.subscriptionRequested, true);
  assert.equal(model.instance.subscriptionRun, undefined);
  model.state.foreground = true;
  await model.instance.refreshSubscriptions();
  assert.equal(model.state.feedCalls, 1);
  assert.equal(model.instance.subscriptionRequested, false);
});

test('foreground loss after native fetch blocks all publication and cancellation failures are visible and retryable', async () => {
  const model = subscriptionFixture();
  const original = model.hooks.loadSubscriptionEvents;
  model.hooks.loadSubscriptionEvents = async (...args) => {
    const result = await original(...args);
    model.state.foreground = false;
    return result;
  };
  await model.instance.refreshSubscriptions();
  assert.equal(model.state.scheduled.length, 0);
  model.state.foreground = true;
  model.hooks.loadSubscriptionEvents = original;
  await model.instance.refreshSubscriptions();
  const cancel = model.reminders.cancel;
  model.reminders.cancel = async () => ({ ok: false, error: 'cannot cancel' });
  model.instance.setAstronomyEventsEnabled(false);
  await model.instance.preferenceQueue;
  await model.instance.refreshSubscriptions();
  assert.equal(model.state.items.length, 1);
  assert.equal(model.store.astronomySubscriptionStatus, 'cannot cancel');
  model.reminders.cancel = cancel;
  model.state.consent = false;
  await model.instance.refreshSubscriptions();
  assert.equal(model.state.items.length, 0);
});

test('failed feed preserves active reminders; quiet hours remove only subscriptions; list failure never publishes', async () => {
  const model = subscriptionFixture();
  await model.instance.refreshSubscriptions();
  model.state.feedError = true;
  await model.instance.refreshSubscriptions();
  assert.equal(model.state.items.length, 1);
  assert.match(model.store.astronomySubscriptionStatus, /不可用/);
  model.state.feedError = false;
  model.store.dndEnabled = true;
  model.store.dndEndMinutes = model.store.dndStartMinutes;
  model.instance.persistPreferences();
  await model.instance.preferenceQueue;
  await model.instance.refreshSubscriptions();
  assert.equal(model.state.items.length, 0);
  const broken = subscriptionFixture();
  broken.state.listError = true;
  await broken.instance.refreshSubscriptions();
  assert.equal(broken.state.scheduled.length, 0);
});

test('rolling selection is bounded, validates observer and ignores past, duplicate and too-soon passes', () => {
  const select = new Function(policy + subscriptionPolicy + ';return subscriptionCandidates')();
  const now = Date.now();
  const events = Array.from({ length: 20 }, (_, index) => {
    const at = now + (index + 1) * 3600000;
    return { ...event(), id: String(index), at, jd: at / 86400000 + 2440587.5, kind: 'satellite-pass' };
  });
  const feed = { generatedAt: now, observerKey: 'earth:chosen', events: [events[0], ...events] };
  assert.equal(select(feed, 'satellite', preferenceValue(), now, now + 86400000).length, 6);
  assert.throws(() => select({ ...feed, observerKey: '' }, 'satellite', preferenceValue(), now, now + 86400000));
  assert.throws(() => select({ ...feed, generatedAt: now - 600000 }, 'satellite', preferenceValue(), now, now + 86400000));
  assert.equal(select(feed, 'satellite', preferenceValue({ dndEnabled: true, dndStartMinutes: 0, dndEndMinutes: 0 }), now, now + 86400000).length, 0);
});

test('meteor and planetary events fill the finite window before solar terms', () => {
  const select = new Function(policy + subscriptionPolicy + ';return subscriptionCandidates')();
  const now = Date.now();
  const events = Array.from({ length: 7 }, (_, index) => {
    const at = now + (index + 1) * 3600000;
    return { ...event(), id: String(index), at, jd: at / 86400000 + 2440587.5,
      kind: index === 0 ? 'solar-term' : index % 2 ? 'meteor-peak' : 'planetary-event' };
  });
  const result = select({ generatedAt: now, events }, 'astronomy', preferenceValue(), now, now + 86400000);
  assert.equal(result.length, 6);
  assert.ok(result.every(item => item.kind !== 'solar-term'));
});

test('remote Push Kit policy is separate and urgent messages cannot bypass privacy, subscriptions or quiet hours', () => {
  const accepts = new Function(policy + subscriptionPolicy + ';return acceptsRemoteAstronomyMessage')();
  const now = Date.now();
  const message = { schemaVersion: 1, messageId: 'article-1', category: 'digest', issuedAt: now,
    reference: { kind: 'event', id: 'urgent-event', revision: 1 }, expiresAt: now + 3600000 };
  assert.equal(accepts(message, preferenceValue(), true, true, now), false);
  const prefs = preferenceValue({ digestEnabled: true });
  assert.equal(accepts(message, prefs, true, true, now), true);
  assert.equal(accepts(message, prefs, false, true, now), false);
  assert.equal(accepts(message, prefs, true, false, now), false);
  assert.equal(accepts(message, { ...prefs, dndEnabled: true, dndStartMinutes: 0, dndEndMinutes: 0 }, true, true, now), false);
  assert.equal(accepts({ ...message, expiresAt: now }, prefs, true, true, now), false);
});

test('construction and preference reads never schedule, write or ask for notification permission', async () => {
  const { state, store, instance } = fixture(preferenceValue());
  assert.equal(state.reads, 0);
  await Promise.all([instance.loadPreferences(), instance.loadPreferences()]);
  assert.equal(state.reads, 1);
  assert.equal(state.flushes, 0);
  assert.equal(store.passLeadMinutes, 15);
  assert.equal(store.dndEnabled, false);
  assert.equal(state.scheduled.length, 0);
});

test('manual event schedules exact event route using persisted lead and runtime bundle', async () => {
  const { state, store, instance } = fixture(preferenceValue());
  const selected = event();
  const result = await instance.scheduleEvent(selected);
  assert.equal(result.ok, true);
  assert.equal(result.message, '提醒已交给系统管理。');
  const call = state.scheduled[0];
  assert.equal(call.payload.eventAt, new Date(selected.at).toISOString());
  for (const key of ['jd', 'target', 'tab', 'kind']) assert.equal(call.payload[key], selected[key]);
  assert.equal(call.payload.panel, 'calendar');
  assert.equal(call.payload.eventId, selected.id);
  assert.equal(call.payload.leadMinutes, 15);
  assert.equal(call.bundle, 'org.runtime.app');
  assert.equal(call.prefs.dndEnabled, false);
  assert.equal(store.astronomyNotificationBusy, false);
});

test('preference writes persist latest snapshot in order and flush failure restores saved values', async () => {
  const { state, store, instance } = fixture(preferenceValue());
  await instance.loadPreferences();
  store.passLeadMinutes = 20; instance.persistPreferences();
  store.passLeadMinutes = 25; instance.persistPreferences();
  await instance.preferenceQueue;
  assert.equal(JSON.parse(state.persisted).passLeadMinutes, 25);
  assert.equal(store.notificationPreferencesBusy, false);
  state.flushError = true;
  store.passLeadMinutes = 30; instance.persistPreferences();
  await instance.preferenceQueue;
  assert.equal(store.passLeadMinutes, 25);
  assert.equal(JSON.parse(state.cached).passLeadMinutes, 25);
  assert.equal(JSON.parse(state.persisted).passLeadMinutes, 25);
  assert.match(store.notificationPreferencesError, /保存失败/);
});

test('preference read failure blocks scheduling and retry recovers; malformed persisted values fail closed', async () => {
  const { state, instance, store } = fixture(preferenceValue());
  state.readError = true;
  assert.equal((await instance.scheduleEvent(event())).reason, 'preferences-unavailable');
  assert.equal(state.scheduled.length, 0);
  assert.equal(store.notificationPreferencesLoaded, false);
  state.readError = false;
  await instance.scheduleEvent(event());
  assert.equal(state.scheduled.length, 1);
  const malformed = fixture(preferenceValue({ dndStartMinutes: -1 }));
  await malformed.instance.scheduleEvent(event());
  assert.equal(malformed.state.scheduled.length, 0);
});

test('a first preference write before load rolls back to initial defaults on flush failure', async () => {
  const { state, store, instance } = fixture();
  state.flushError = true;
  store.passLeadMinutes = 30;
  instance.persistPreferences();
  await instance.preferenceQueue;
  assert.equal(store.passLeadMinutes, 5);
  assert.equal(JSON.parse(state.cached).passLeadMinutes, 5);
});

test('list failure preserves prior list/count and permission state; individual zero cancellation refreshes', async () => {
  const { state, store, instance } = fixture();
  state.items = [{ reminderId: 0, title: 'event' }];
  await instance.refreshStatus();
  assert.equal(store.astronomyReminderListLoaded, true);
  assert.equal(store.astronomyReminders[0].reminderId, 0);
  state.listError = true;
  state.notificationStatus = { ok: false, error: 'status failed' };
  await instance.refreshStatus();
  assert.equal(store.astronomyNotificationEnabled, true);
  assert.equal(store.astronomyReminderCount, 1);
  assert.equal(store.astronomyReminders.length, 1);
  assert.equal(store.astronomyReminderListError, 'read failed');
  state.listError = false;
  instance.cancelReminder(0);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(state.cancelIds, [0]);
  assert.equal(store.astronomyReminders.length, 0);
  state.items = [{ reminderId: 7 }];
  instance.cancelReminder(undefined);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(state.items.length, 1);
});

test('busy/manual privacy/partial-failure results are explicit without retrying publication', async () => {
  const { state, instance, store } = fixture();
  store.astronomyNotificationBusy = true;
  const busy = await instance.scheduleEvent(event());
  assert.equal(busy.ok, false);
  assert.equal(busy.reason, 'busy');
  assert.match(busy.error, /稍后重试/);
  store.astronomyNotificationBusy = false;
  state.consent = false;
  const privacy = await instance.scheduleEvent(event());
  assert.equal(privacy.ok, false);
  assert.equal(privacy.reason, 'privacy-required');
  assert.match(privacy.error, /隐私协议/);
  assert.equal(state.scheduled.length, 0);
  state.consent = true;
  state.scheduleResult = { ok: false, partial: true, error: 'cleanup needed' };
  state.items = [{ reminderId: 0 }, { reminderId: 1 }];
  assert.deepEqual(await instance.scheduleEvent(event()), { ok: false, partial: true, error: 'cleanup needed', message: 'cleanup needed' });
  assert.equal(store.astronomyReminders.length, 2);
  assert.equal(state.scheduled.length, 1);
});

test('service outcome reaches calendar and CLI unchanged regardless of localized message', async () => {
  const calendarSource = ['state/AstronomyCalendarText.ts', 'state/AstronomyCalendarEvent.ts',
    'state/AstronomyCalendarStore.ets', 'capability/AstronomyCalendarController.ets'].map(name => plain(read(name))).join('\n');
  const { AstronomyCalendarStore, AstronomyCalendarController } = new Function(calendarSource +
    ';return { AstronomyCalendarStore, AstronomyCalendarController }')();
  const host = read('pages/MainWindowNativeNode.ets');
  const start = host.indexOf("if (name === 'remindCalendarEvent') {");
  assert.ok(start >= 0);
  const block = host.slice(start, host.indexOf("if (name === 'viewCalendarEvent')", start));
  const execute = new Function('calendar', 'payload', `return (async () => {
    const name = 'remindCalendarEvent'; const result = {ok: true}; ${block} return result;
  })()`);
  for (const serviceResult of [
    { ok: true, reminderId: 0, unchanged: true, activeReminderIds: [0] },
    { ok: false, reason: 'notification-disabled', code: 1700001, notificationEnabled: false, error: '提醒已交给系统管理。' },
    { ok: false, reason: 'quiet-hours', error: 'Quiet hours' },
    { ok: false, reason: 'quota-or-entitlement', code: 1700002, activeReminderIds: [9], error: 'Quota exceeded' },
    { ok: false, reason: 'replacement-cleanup-failed', partial: true, reminderId: 0, activeReminderIds: [0, 9], error: 'Cleanup failed' }
  ]) {
    const model = fixture(preferenceValue());
    model.state.scheduleResult = { ...serviceResult };
    const store = new AstronomyCalendarStore();
    const selected = event();
    store.events = [selected]; store.selectedEventId = selected.id;
    const calendar = new AstronomyCalendarController({}, store, {
      remind: selected => model.instance.scheduleEvent(selected), viewSky: () => {}, feedChanged: () => {}
    });
    const result = await execute(calendar, selected.id);
    assert.equal(result.ok, serviceResult.ok);
    for (const [key, value] of Object.entries(serviceResult)) assert.deepEqual(result.reminder[key], value);
    assert.equal(store.actionMessage, result.reminder.message);
    if (!serviceResult.ok) {
      assert.equal(result.error, serviceResult.error);
      assert.equal(result.reason, serviceResult.reason);
      assert.equal(result.code, serviceResult.code);
    }
    assert.equal(model.state.scheduled.length, 1);
  }
});

test('invalid events, foreground loss and thrown scheduling return explicit failures', async () => {
  const model = fixture(preferenceValue());
  assert.equal((await model.instance.scheduleEvent({ ...event(), at: NaN })).reason, 'validation');
  model.state.foreground = false;
  assert.equal((await model.instance.scheduleEvent(event())).reason, 'interaction-unavailable');
  assert.equal(model.state.scheduled.length, 0);
  model.state.foreground = true;
  model.reminders.schedule = async () => { throw Error('service unavailable'); };
  const result = await model.instance.scheduleEvent(event());
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'scheduling-error');
  assert.equal(model.store.astronomyNotificationBusy, false);
});

test('list refresh failure cannot replace a completed scheduling outcome', async () => {
  const model = fixture(preferenceValue());
  model.reminders.list = async () => { throw Error('list failed'); };
  for (const outcome of [{ ok: true, reminderId: 0 }, { ok: false, code: 201, reason: 'permission-denied', error: 'Denied' }]) {
    model.state.scheduleResult = { ...outcome };
    const result = await model.instance.scheduleEvent(event());
    for (const [key, value] of Object.entries(outcome)) assert.deepEqual(result[key], value);
    assert.notEqual(model.store.astronomyReminderListError, '');
    assert.equal(model.store.astronomyNotificationBusy, false);
  }
});

test('notification UI exposes simple categories and no manual manager or dead digest switch', () => {
  const section = read('panels/settings/NotificationSection.ets');
  const ui = section.slice(section.indexOf('  build() {'));
  assert.match(ui, /onToggleAstronomyEvents\(enabled\)/);
  assert.match(ui, /onToggleSatellitePass\(enabled\)/);
  assert.doesNotMatch(ui, /onOpenCalendar|onCancelReminder|chooseDateTime|onToggleDigest|onScheduleCountdown/);
  assert.match(section, /reminderListError/);
});

test('legacy shortcuts only open calendar and never read simulation-year snapshots', () => {
  const { instance, state } = fixture();
  instance.scheduleNextSolarTerm();
  instance.scheduleNextMoonPhase();
  instance.scheduleNextMeteorShower();
  assert.equal(state.calendarOpens, 3);
  assert.equal(state.scheduled.length, 0);
  state.foreground = false;
  instance.scheduleNextSolarTerm();
  assert.equal(state.calendarOpens, 3);
});

test('Chinese, English and other-language fallback cover UI text and reactive status', () => {
  assert.equal(notificationText('选择日期与时间', 'en'), 'Choose date and time');
  assert.equal(notificationText('静默时段', 'fr'), 'Quiet hours');
  assert.equal(notificationText('Notifications enabled', 'zh_CN'), '通知已开启');
  for (const file of ['panels/settings/NotificationSection.ets', 'capability/NotificationController.ets']) {
    for (const match of read(file).matchAll(/(?:this\.t|notificationText)\('([^']*[\u4e00-\u9fff][^']*)'\)/g)) {
      assert.doesNotMatch(notificationText(match[1], 'en'), /[\u4e00-\u9fff]/, match[1]);
    }
  }
});

test('foreground loss after preference wait prevents scheduling and host exceptions never reject', async () => {
  const { instance, state, hooks, notifications, reminders, store } = fixture();
  const scheduled = instance.scheduleEvent(event());
  state.foreground = false;
  await scheduled;
  assert.equal(state.scheduled.length, 0);
  hooks.canInteract = () => { throw Error('host detached'); };
  hooks.flashHint = () => { throw Error('UI detached'); };
  await assert.doesNotReject(instance.requestAccess());
  await assert.doesNotReject(instance.scheduleEvent(event()));
  hooks.canInteract = () => true;
  notifications.requestAuthorization = async () => { throw Error('permission service'); };
  await assert.doesNotReject(instance.requestAccess());
  reminders.list = async () => { throw Error('list service'); };
  await assert.doesNotReject(instance.refreshStatus());
  assert.equal(store.astronomyNotificationBusy, false);
  instance.cancelReminder(0);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(store.astronomyNotificationBusy, false);
});
