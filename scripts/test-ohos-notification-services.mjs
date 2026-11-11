import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../harmonyos/ets-source/qability/', import.meta.url);
const read = name => readFileSync(new URL(name, root), 'utf8');
const plain = source => stripTypeScriptTypes(source.replace(/^import .*\n/gm, '').replace(/^export \{.*\} from .*\n/gm, '').replaceAll('export ', ''));
const policy = plain(read('AstronomyNotificationPolicy.ts'));
const metadata = plain(read('AstronomyReminderMetadata.ts'));
const bundle = 'org.example.runtime';
const payload = changes => ({ title: 'Full moon', content: 'Observe the Moon', at: new Date(Date.now() + 86400000).toISOString(), eventId: 'full-moon', kind: 'moon-phase', ...changes });
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };

function fixture() {
  const state = { enabled: true, records: [], nextId: 0, publishCalls: [], cancelCalls: [], notificationCalls: [], agentCalls: [], authCalls: 0, listCalls: 0, failCancel: new Set(), quota: Infinity, stripParameters: true, cached: '', persisted: '', flushes: 0 };
  const preferences = { getPreferences: async (_context, options) => {
    assert.equal(options.name, 'stellarium_reminder_metadata_v1');
    if (state.metadataOpenError) throw Error('open');
    return {
      get: async () => { if (state.metadataReadError) throw Error('read'); return state.cached; },
      put: async (_key, value) => { if (state.metadataPutError) throw Error('put'); state.cached = value; },
      flush: async () => {
        state.flushes++;
        if (state.metadataFlushError || state.failFlushAt === state.flushes) throw Error('flush');
        state.persisted = state.cached;
        if (state.afterFlush) state.afterFlush(state.flushes);
      }
    };
  } };
  const reminderAgentManager = {
    ReminderType: { REMINDER_TYPE_TIMER: 0, REMINDER_TYPE_CALENDAR: 1, REMINDER_TYPE_ALARM: 2 },
    getAllValidReminders: async () => {
      state.listCalls++;
      if (state.listError !== undefined) throw state.listError;
      const records = structuredClone(state.records);
      for (const item of records) {
        if (state.stripParameters && item.reminderReq.wantAgent) delete item.reminderReq.wantAgent.parameters;
        if (state.stripUri && item.reminderReq.wantAgent) delete item.reminderReq.wantAgent.uri;
        if (state.stripFingerprintField) delete item.reminderReq[state.stripFingerprintField];
        if (state.readbackCalendarSeconds !== undefined && item.reminderReq.dateTime) item.reminderReq.dateTime.second = state.readbackCalendarSeconds;
        if (state.readbackNotificationId !== undefined) item.reminderReq.notificationId = state.readbackNotificationId;
      }
      if (state.afterList) state.afterList();
      return records;
    },
    publishReminder: async request => {
      state.publishCalls.push(structuredClone(request));
      if (state.publishGate) await state.publishGate.promise;
      if (state.publishError !== undefined) throw state.publishError;
      if (state.records.length >= state.quota) throw { code: 1700002 };
      const reminderId = state.nextId++;
      state.records.push({ reminderId, reminderReq: structuredClone(request) });
      return reminderId;
    },
    cancelReminder: async id => {
      state.cancelCalls.push(id);
      if (state.failCancel.has(id)) throw { code: 999, message: 'busy' };
      if (!state.records.some(item => item.reminderId === id)) throw { code: 1700003 };
      state.records = state.records.filter(item => item.reminderId !== id);
    },
    cancelAllReminders: async () => { if (state.clearError) throw state.clearError; state.records = []; }
  };
  const notificationManager = {
    ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0, NOTIFICATION_CONTENT_MULTILINE: 1 },
    isNotificationEnabled: async () => { if (state.statusError !== undefined) throw state.statusError; return state.enabled; },
    requestEnableNotification: async () => { state.authCalls++; },
    publish: async request => { if (state.notificationError !== undefined) throw state.notificationError; state.notificationCalls.push(request); },
    cancel: async id => { if (state.notificationCancelGate) await state.notificationCancelGate.promise; if (state.notificationCancelError) throw state.notificationCancelError; state.notificationCalls.push({ cancel: id }); }
  };
  const wantAgent = {
    OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 4 },
    getWantAgent: async info => { state.agentCalls.push(info); if (state.agentError) throw state.agentError; return state.nullAgent ? null : { info }; }
  };
  const load = name => {
    const service = new Function('reminderAgentManager', 'notificationManager', 'wantAgent', 'hasCurrentPrivacyConsent', 'notificationText', 'preferences', policy + metadata + plain(read(name + '.ets')) + ';return ' + name)(reminderAgentManager, notificationManager, wantAgent, () => state.consent !== false, value => value, preferences);
    if (service.configure) service.configure({ abilityInfo: { bundleName: bundle } });
    return service;
  };
  return { state, reminders: load('AstronomyReminderService'), notifications: load('AstronomyNotificationService'), reload: () => { state.cached = state.persisted; return load('AstronomyReminderService'); } };
}

test('ring completion preserves the event body for every reminder type', async () => {
  for (const timing of [
    { reminderType: 'timer', triggerSeconds: 120 },
    { reminderType: 'calendar' },
    { reminderType: 'alarm', hour: 14, minute: 25 }
  ]) {
    const { state, reminders } = fixture();
    const content = 'Full moon: open the calendar for observing details.';
    assert.equal((await reminders.schedule(payload({ ...timing, content }), bundle)).ok, true);
    assert.equal(state.publishCalls[0].content, content);
    assert.equal(state.publishCalls[0].expiredContent, content);
  }
});

test('untrusted reminder payloads never crash or call system APIs', async () => {
  const { state, reminders } = fixture();
  const invalid = [null, undefined, true, [], {}, { title: 4 }, payload({ title: null }), payload({ at: '2030-02-30T10:00:00Z' }), payload({ at: '2030-01-01' }), payload({ reminderType: 'other' }), payload({ leadMinutes: NaN }), payload({ jd: Infinity }), payload({ target: {} }), payload({ quietHours: null }), payload({ reminderType: 'timer', triggerSeconds: -1 }), payload({ reminderType: 'alarm', hour: 24 }), payload({ reminderType: 'alarm', daysOfWeek: [1, 1] })];
  for (const input of invalid) assert.equal((await reminders.schedule(input, bundle)).ok, false, JSON.stringify(input));
  assert.equal(state.listCalls, 0);
  assert.equal(state.publishCalls.length, 0);
});

test('calendar event time, lead time and route are independently preserved in list', async () => {
  const { state, reminders } = fixture();
  const eventAt = new Date(Date.now() + 86400000).toISOString();
  const jd = new Date(eventAt).getTime() / 86400000 + 2440587.5;
  const result = await reminders.schedule(payload({ at: undefined, eventAt, jd, target: 'Moon', leadMinutes: 15 }), bundle);
  assert.equal(result.reminderId, 0);
  const request = state.records[0].reminderReq;
  assert.equal(request.wantAgent.pkgName, bundle);
  assert.equal(request.wantAgent.abilityName, 'QAbility');
  assert.equal(request.wantAgent.parameters.jd, jd);
  assert.equal(request.groupId, undefined);
  const date = request.dateTime;
  assert.equal(new Date(date.year, date.month - 1, date.day, date.hour, date.minute, date.second).getTime(), Math.floor((new Date(eventAt).getTime() - 900000) / 60000) * 60000);
  const item = (await reminders.list()).items[0];
  assert.equal(item.eventAt, eventAt);
  assert.equal(item.target, 'Moon');
  assert.equal(item.leadMinutes, 15);
});

test('twenty concurrent same-event calls publish once including id zero and process restart', async () => {
  const { state, reminders, reload } = fixture();
  const request = payload();
  const results = await Promise.all(Array.from({ length: 20 }, () => reminders.schedule(request, bundle)));
  assert.ok(results.every(result => result.ok && result.reminderId === 0));
  assert.equal(state.publishCalls.length, 1);
  assert.equal((await reload().schedule(request, bundle)).unchanged, true);
  assert.equal(state.publishCalls.length, 1);
});

test('subscriptions survive list/restart, never replace manual events, and enforce atomic app budget', async () => {
  const { reminders, state, reload } = fixture();
  const request = payload();
  await reminders.schedule(request, bundle);
  const automatic = { ...request, subscription: 'astronomy' };
  const first = await reminders.schedule(automatic, bundle, undefined, undefined, 2);
  assert.equal(first.ok, true);
  assert.equal(state.records.length, 2);
  assert.equal((await reminders.list()).items[1].subscription, 'astronomy');
  assert.equal((await reload().schedule(automatic, bundle, undefined, undefined, 2)).unchanged, true);
  const quota = await reminders.schedule({ ...automatic, title: 'changed' }, bundle, undefined, undefined, 2);
  assert.equal(quota.reason, 'local-budget');
  assert.equal(state.records.length, 2);
  assert.deepEqual(state.cancelCalls, []);
  const inputs = Array.from({ length: 10 }, (_, index) => ({ ...automatic, eventId: String(index) }));
  const results = await Promise.all(inputs.map(value => reminders.schedule(value, bundle, undefined, undefined, 4)));
  assert.equal(results.filter(result => result.ok).length, 2);
  assert.equal(state.records.length, 4);
});

test('stripped parameters and uri recover durable route, classification and guarded cancellation after restart', async () => {
  const { reminders, state, reload } = fixture();
  state.stripUri = true;
  const request = payload({ subscription: 'astronomy', panel: 'calendar', target: 'Moon', leadMinutes: 15 });
  assert.equal((await reminders.schedule(request, bundle)).ok, true);
  const restarted = reload();
  const item = (await restarted.list()).items[0];
  assert.equal(item.eventId, request.eventId);
  assert.equal(item.eventAt, request.at);
  assert.equal(item.subscription, 'astronomy');
  assert.equal(item.panel, 'calendar');
  assert.equal(item.target, 'Moon');
  assert.equal(item.leadMinutes, 15);
  assert.ok(item.ownershipFingerprint);
  assert.equal((await restarted.schedule(request, bundle)).unchanged, true);
  assert.equal(state.publishCalls.length, 1);
  assert.equal((await restarted.cancelOwned(item)).ok, true);
  assert.deepEqual(state.cancelCalls, [0]);
});

test('calendar minute publication survives system truncation and restart with precise route metadata', async () => {
  const { reminders, state, reload } = fixture();
  state.readbackCalendarSeconds = 0;
  const event = new Date(Date.now() + 2 * 86400000); event.setHours(12, 34, 37, 113);
  const jd = event.getTime() / 86400000 + 2440587.5;
  const request = payload({ at: undefined, eventAt: event.toISOString(), jd, leadMinutes: 15, target: 'Moon', panel: 'calendar' });
  const first = await reminders.schedule(request, bundle);
  assert.equal(first.ok, true);
  assert.deepEqual(state.publishCalls[0].dateTime, {
    year: event.getFullYear(), month: event.getMonth() + 1, day: event.getDate(), hour: 12, minute: 19, second: 0
  });
  const restarted = reload();
  const item = (await restarted.list()).items[0];
  assert.equal(item.eventAt, event.toISOString());
  assert.equal(item.jd, jd);
  assert.equal(item.eventId, request.eventId);
  assert.equal(item.target, 'Moon');
  const again = await restarted.schedule(request, bundle);
  assert.equal(again.unchanged, true);
  assert.equal(again.reminderId, first.reminderId);
  assert.equal(state.publishCalls.length, 1);
  const diagnostic = (await restarted.list(true, () => true)).diagnostics.entries[0];
  assert.equal(diagnostic.actualFingerprint, diagnostic.expectedFingerprints[0]);
  assert.equal(diagnostic.owned, true);
});

test('calendar too-soon guard uses floored minute and respects cross-minute boundaries', () => {
  const validate = new Function(policy + ';return validateReminder')();
  const base = new Date(2030, 0, 1, 12, 34, 0).getTime();
  const now = base + 29000;
  const check = offset => validate(payload({ at: new Date(base + offset).toISOString() }), now);
  assert.equal(check(59999).reason, 'too-soon');
  assert.equal(check(60000).value.fireAt, base + 60000);
  assert.equal(check(119999).value.fireAt, base + 60000);
  assert.equal(check(120000).value.fireAt, base + 120000);
  assert.equal(validate(payload({ at: new Date(base + 97000).toISOString() }), base + 30000).reason, 'too-soon');
});

test('minute-normalized subscription candidates block matching legacy reminders without adopting or cancelling', async () => {
  const { reminders, state, reload } = fixture();
  state.readbackCalendarSeconds = 0;
  const event = new Date(Date.now() + 2 * 86400000); event.setHours(14, 25, 6, 113);
  const request = payload({ at: event.toISOString(), subscription: 'astronomy' });
  assert.equal((await reminders.schedule(request, bundle)).ok, true);
  state.persisted = '';
  const restarted = reload();
  assert.equal((await restarted.schedule(request, bundle)).reason, 'legacy-reminder-unverified');
  assert.equal((await restarted.list()).items[0].kind, 'unknown');
  assert.equal(state.publishCalls.length, 1);
  assert.deepEqual(state.cancelCalls, []);
});

test('legacy journal seconds mismatch remains unowned without automatic migration or repeated publication', async () => {
  const { reminders, state, reload } = fixture();
  const at = new Date(Date.now() + 2 * 86400000); at.setHours(14, 25, 6, 113);
  const request = payload({ at: at.toISOString(), subscription: 'astronomy' });
  state.readbackCalendarSeconds = 0;
  const first = await reminders.schedule(request, bundle);
  assert.equal(first.ok, true);
  assert.equal(first.reminderId, 0);
  const oldJournal = JSON.parse(state.persisted);
  const oldFingerprint = JSON.parse(oldJournal.entries[0].fingerprint);
  oldFingerprint[6][5] = 6;
  oldJournal.entries[0].fingerprint = JSON.stringify(oldFingerprint);
  state.persisted = JSON.stringify(oldJournal);
  const oldService = reload();
  const persisted = state.persisted;
  const flushes = state.flushes;
  const ordinary = await oldService.list();
  assert.equal(ordinary.items[0].kind, 'unknown');
  assert.equal(ordinary.diagnostics, undefined);
  assert.equal(state.persisted, persisted);
  const restarted = reload();
  const diagnostic = await restarted.list(true, () => true);
  assert.equal(state.flushes, flushes);
  assert.equal(state.persisted, persisted);
  const entry = diagnostic.diagnostics.entries[0];
  assert.equal(entry.reminderId, 0);
  assert.equal(entry.request.dateTime.second, 0);
  assert.equal(entry.request.dateTime.minute, 25);
  assert.equal(entry.request.notificationId, state.records[0].reminderReq.notificationId);
  assert.equal(entry.request.wantAgent.pkgName, bundle);
  assert.equal(entry.request.wantAgent.abilityName, 'QAbility');
  assert.equal(entry.wantAgentParametersPresent, false);
  assert.equal(entry.owned, false);
  assert.equal(JSON.parse(entry.expectedFingerprints[0])[6][5], 6);
  assert.equal(JSON.parse(entry.actualFingerprint)[6][5], 0);
  assert.equal((await restarted.schedule(request, bundle)).reason, 'metadata-unverified');
  assert.equal(state.publishCalls.length, 1);
  assert.deepEqual(state.cancelCalls, []);
});

test('diagnostics retain raw missing/changed fields and never emit arbitrary want parameters or uri secrets', async () => {
  const { reminders, state } = fixture();
  await reminders.schedule(payload(), bundle);
  state.stripParameters = false;
  state.records[0].reminderReq.wantAgent.parameters.pushToken = 'SECRET_PUSH_TOKEN';
  state.records[0].reminderReq.wantAgent.uri += '&secret=SECRET_URI_VALUE';
  state.stripFingerprintField = 'content';
  const diagnostic = await reminders.list(true, () => true);
  const entry = diagnostic.diagnostics.entries[0];
  assert.equal(entry.actualFingerprint, '');
  assert.equal(entry.request.content, undefined);
  assert.equal(entry.wantAgentParametersPresent, true);
  assert.equal(entry.wantAgentUriPresent, true);
  assert.equal(entry.expectedFingerprints.length, 1);
  assert.doesNotMatch(JSON.stringify(diagnostic), /SECRET_PUSH_TOKEN|SECRET_URI_VALUE|pushToken/);
  assert.deepEqual(state.cancelCalls, []);
  const fresh = fixture();
  fresh.state.readbackNotificationId = 0;
  assert.equal((await fresh.reminders.schedule(payload(), bundle)).reason, 'metadata-unverified');
  const changed = await fresh.reminders.list(true, () => true);
  assert.equal(changed.diagnostics.entries[0].request.notificationId, 0);
  assert.equal(changed.diagnostics.entries[0].expectedFingerprints.length, 1);
  assert.equal(changed.diagnostics.journalEntries[0].reminderId, 0);
});

test('diagnostics are opt-in, guarded before/after awaits, read-only even for dirty or invalid journals', async () => {
  const { reminders, state } = fixture();
  for (const guard of [undefined, () => false, () => { throw Error('guard'); }]) {
    assert.equal((await reminders.list(true, guard)).ok, false);
  }
  assert.equal(state.listCalls, 0);
  state.consent = false;
  assert.equal((await reminders.list(true, () => true)).diagnostics, undefined);
  state.consent = true;
  state.afterList = () => { state.consent = false; };
  assert.equal((await reminders.list(true, () => true)).diagnostics, undefined);
  delete state.afterList;
  state.consent = true;
  state.failFlushAt = 2;
  await reminders.schedule(payload(), bundle);
  const flushes = state.flushes;
  assert.equal((await reminders.list(true, () => true)).diagnostics.metadataNeedsRepair, true);
  assert.equal(state.flushes, flushes);
  const corrupt = fixture();
  corrupt.state.cached = 'invalid';
  const snapshot = await corrupt.reminders.list(true, () => true);
  assert.equal(snapshot.ok, false);
  assert.equal(snapshot.reason, 'metadata-unavailable');
  assert.ok(snapshot.diagnostics.metadataError);
  assert.equal(corrupt.state.flushes, 0);
});

test('reused system IDs cannot acquire stale ownership or be cancelled using an old list snapshot', async () => {
  for (const mutate of [request => { request.notificationId++; }, request => { request.title += ' other'; },
    request => { request.dateTime.minute = (request.dateTime.minute + 1) % 60; },
    request => { request.content += ' other'; }, request => { request.wantAgent.pkgName = 'other.bundle'; }]) {
    const { reminders, state, reload } = fixture();
    await reminders.schedule(payload({ subscription: 'astronomy' }), bundle);
    const original = (await reminders.list()).items[0];
    mutate(state.records[0].reminderReq);
    const restarted = reload();
    assert.equal((await restarted.cancelOwned(original)).reason, 'ownership-mismatch');
    const item = (await restarted.list()).items[0];
    assert.equal(item.subscription, undefined);
    assert.equal(item.eventId, '');
    assert.equal(item.kind, 'unknown');
    assert.deepEqual(state.cancelCalls, []);
  }
  const { reminders, state } = fixture();
  const request = payload({ subscription: 'astronomy' });
  await reminders.schedule(request, bundle);
  const old = (await reminders.list()).items[0];
  const notificationId = state.records[0].reminderReq.notificationId;
  await reminders.cancel(0);
  state.nextId = 0;
  await reminders.schedule(request, bundle);
  assert.ok(state.records[0].reminderReq.notificationId > notificationId);
  assert.equal((await reminders.cancelOwned(old)).reason, 'ownership-mismatch');
  assert.deepEqual(state.cancelCalls, [0]);
});

test('metadata prepare errors prevent publication and cancellation; flush retry repairs cached state', async () => {
  for (const error of ['metadataOpenError', 'metadataReadError', 'metadataPutError', 'metadataFlushError']) {
    const { reminders, state } = fixture();
    state[error] = true;
    assert.equal((await reminders.schedule(payload(), bundle)).reason, 'metadata-unavailable');
    assert.equal(state.publishCalls.length, 0);
    assert.deepEqual(state.cancelCalls, []);
    state[error] = false;
    assert.equal((await reminders.schedule(payload(), bundle)).ok, true);
    assert.equal(state.publishCalls.length, 1);
  }
});

test('publish then metadata commit failure preserves old reminder and durable journal recovers without republishing', async () => {
  for (const restart of [false, true]) {
    const { reminders, state, reload } = fixture();
    const request = payload();
    await reminders.schedule(request, bundle);
    state.failFlushAt = state.flushes + 2;
    const changed = { ...request, title: 'Updated Moon' };
    const result = await reminders.schedule(changed, bundle);
    assert.equal(result.ok, false);
    assert.equal(result.partial, true);
    assert.equal(result.reason, 'metadata-commit-failed');
    assert.deepEqual(state.cancelCalls, []);
    assert.equal(state.records.length, 2);
    assert.equal(JSON.parse(state.persisted).entries[1].reminderId, -1);
    const service = restart ? reload() : reminders;
    assert.equal((await service.schedule(changed, bundle)).ok, true);
    assert.equal(state.publishCalls.length, 2);
    assert.deepEqual(state.cancelCalls, [0]);
    assert.equal((await service.list()).items[0].eventId, request.eventId);
  }
});

test('corrupt journal and insufficient system readback fail closed without duplicate publication', async () => {
  for (const raw of ['broken', 'null', '{}', '{"version":1,"nextNotificationId":1000000000,"entries":[null]}']) {
    const { reminders, state } = fixture();
    state.cached = raw;
    assert.equal((await reminders.schedule(payload(), bundle)).reason, 'metadata-unavailable');
    assert.equal(state.publishCalls.length, 0);
    assert.equal((await reminders.list()).ok, false);
  }
  const { reminders, state } = fixture();
  state.stripFingerprintField = 'content';
  const request = payload();
  assert.equal((await reminders.schedule(request, bundle)).reason, 'metadata-unverified');
  assert.equal((await reminders.schedule(request, bundle)).reason, 'metadata-unavailable');
  assert.equal(state.publishCalls.length, 1);
  delete state.stripFingerprintField;
  assert.equal((await reminders.schedule(request, bundle)).unchanged, true);
});

test('timer remaining seconds are not an ownership field, but original duration still controls replacement', async () => {
  const { reminders, state, reload } = fixture();
  const request = payload({ reminderType: 'timer', at: undefined, triggerSeconds: 60 });
  await reminders.schedule(request, bundle);
  state.records[0].reminderReq.triggerTimeInSeconds = 49;
  const restarted = reload();
  assert.equal((await restarted.schedule(request, bundle)).unchanged, true);
  assert.equal((await restarted.list()).items[0].eventId, request.eventId);
  assert.equal((await restarted.schedule({ ...request, triggerSeconds: 90 }, bundle)).replaced, true);
  assert.deepEqual(state.cancelCalls, [0]);
});

test('legacy equivalent detection compares all available immutable request fields, never just titles or IDs', async () => {
  for (const field of ['title', 'content', 'time', 'bundle', 'repeat']) {
    const { reminders, state, reload } = fixture();
    const request = payload({ subscription: 'astronomy' });
    await reminders.schedule(request, bundle);
    state.persisted = '';
    const native = state.records[0].reminderReq;
    if (field === 'time') native.dateTime.minute = (native.dateTime.minute + 1) % 60;
    else if (field === 'bundle') native.wantAgent.pkgName = 'other.bundle';
    else if (field === 'repeat') native.repeatDays = [1];
    else native[field] += ' changed';
    assert.equal((await reload().schedule(request, bundle)).ok, true);
    assert.deepEqual(state.cancelCalls, []);
    assert.equal(state.records.length, 2);
  }
});

test('loss of foreground during metadata flush prevents publication and URI preserves exact route', async () => {
  const { reminders, state } = fixture();
  let foreground = true;
  state.afterFlush = () => { foreground = false; };
  const request = payload({ panel: 'calendar', eventId: 'meteor:特殊/id', target: 'Moon' });
  assert.equal((await reminders.schedule(request, bundle, undefined, () => foreground)).reason, 'interaction-unavailable');
  assert.equal(state.publishCalls.length, 0);
  delete state.afterFlush;
  assert.equal((await reminders.schedule(request, bundle)).ok, true);
  const native = state.records[0].reminderReq;
  const route = reminders.routeFromUri(native.wantAgent.uri);
  assert.equal(route.eventId, request.eventId);
  assert.equal(route.eventAt, request.at);
  assert.equal(route.target, 'Moon');
  assert.equal(native.wantAgent.parameters.eventId, request.eventId);
});

test('replacement serializes and preserves the old reminder on quota/publish failure', async () => {
  const { state, reminders } = fixture();
  const request = payload();
  await reminders.schedule(request, bundle);
  state.quota = 1;
  const failure = await reminders.schedule({ ...request, title: 'Changed' }, bundle);
  assert.equal(failure.reason, 'quota-or-entitlement');
  assert.deepEqual(failure.activeReminderIds, [0]);
  assert.deepEqual(state.cancelCalls, []);
  assert.equal((await reminders.schedule(request, bundle)).unchanged, true);
  state.quota = 30;
  state.publishError = { code: 201 };
  assert.equal((await reminders.schedule({ ...request, title: 'Changed' }, bundle)).reason, 'permission-denied');
  assert.equal(state.records[0].reminderId, 0);
  delete state.publishError;
  const replaced = await reminders.schedule({ ...request, title: 'Changed' }, bundle);
  assert.equal(replaced.replaced, true);
  assert.equal(state.records.length, 1);
  assert.equal(state.records[0].reminderReq.title, 'Changed');
});

test('replacement cleanup failure is explicit and retry repairs without another publication', async () => {
  const { state, reminders } = fixture();
  const request = payload();
  await reminders.schedule(request, bundle);
  state.failCancel.add(0);
  const changed = { ...request, content: 'Updated content' };
  const failure = await reminders.schedule(changed, bundle);
  assert.equal(failure.ok, false);
  assert.equal(failure.partial, true);
  assert.deepEqual(failure.activeReminderIds, [1, 0]);
  assert.equal((await reminders.list()).items.length, 2);
  state.failCancel.clear();
  assert.equal((await reminders.schedule(changed, bundle)).ok, true);
  assert.equal(state.publishCalls.length, 2);
  assert.deepEqual(state.records.map(item => item.reminderId), [1]);
});

test('listing and cancelAll wait for in-flight publication; queue recovers after failure', async () => {
  const { state, reminders } = fixture();
  state.publishGate = deferred();
  const scheduled = reminders.schedule(payload(), bundle);
  const listed = reminders.list();
  const cleared = reminders.cancelAll();
  state.publishGate.resolve();
  assert.equal((await scheduled).ok, true);
  assert.equal((await listed).items.length, 1);
  assert.equal((await cleared).ok, true);
  assert.equal(state.records.length, 0);
  state.clearError = { code: 999 };
  assert.equal((await reminders.cancelAll()).ok, false);
  delete state.clearError;
  assert.equal((await reminders.schedule(payload(), bundle)).ok, true);
});

test('same event across years stays separate; different events have distinct notification IDs', async () => {
  const { state, reminders } = fixture();
  const request = payload();
  await reminders.schedule(request, bundle);
  await reminders.schedule({ ...request, at: new Date(Date.now() + 365 * 86400000).toISOString() }, bundle);
  await reminders.schedule({ ...request, eventId: 'different-event' }, bundle);
  assert.equal(state.records.length, 3);
  assert.equal(new Set(state.records.map(item => item.reminderReq.notificationId)).size, 3);
});

test('legacy equivalents block duplicates but remain unowned and are never auto-cancelled', async () => {
  const { state, reminders, reload } = fixture();
  const request = payload();
  await reminders.schedule(request, bundle);
  const legacy = structuredClone(state.records[0]);
  delete legacy.reminderReq.wantAgent.parameters.astronomyEventKey;
  delete legacy.reminderReq.wantAgent.parameters.astronomySignature;
  delete legacy.reminderReq.wantAgent.parameters.eventAt;
  state.records = [{ ...legacy, reminderId: 40 }, { ...legacy, reminderId: 41 }, { reminderId: 42, reminderReq: { ...legacy.reminderReq, wantAgent: { pkgName: 'other.bundle' } } }];
  state.persisted = '';
  const legacyService = reload();
  const result = await legacyService.schedule(request, bundle);
  assert.equal(result.reason, 'legacy-reminder-unverified');
  assert.deepEqual(state.cancelCalls, []);
  assert.equal(state.records.length, 3);
  const items = (await legacyService.list()).items;
  assert.ok(items.every(item => item.ownershipFingerprint === undefined && item.subscription === undefined && item.kind === 'unknown'));
});

test('cancel accepts zero, missing reminders are idempotent, other failures retained', async () => {
  const { state, reminders } = fixture();
  await reminders.schedule(payload(), bundle);
  assert.equal((await reminders.cancel(0)).ok, true);
  assert.equal((await reminders.cancel(0)).unchanged, true);
  for (const id of [-1, 1.5, NaN, Infinity, '0', 2147483648]) assert.equal((await reminders.cancel(id)).ok, false);
  state.failCancel.add(1);
  assert.equal((await reminders.cancel(1)).ok, false);
});

test('notification authorization and reminder listing failure remain distinguishable', async () => {
  const { state, reminders } = fixture();
  state.enabled = false;
  assert.equal((await reminders.schedule(payload(), bundle)).reason, 'notification-disabled');
  assert.equal(state.authCalls, 0);
  state.statusError = null;
  const unknown = await reminders.status();
  assert.equal(unknown.ok, false);
  assert.equal(unknown.notificationEnabled, undefined);
  delete state.statusError;
  state.enabled = true;
  state.listError = { code: 201 };
  const status = await reminders.status();
  assert.equal(status.notificationEnabled, true);
  assert.equal(status.ok, false);
  assert.equal((await reminders.list()).items, undefined);
  assert.equal((await reminders.schedule(payload(), bundle)).ok, false);
  assert.equal(state.publishCalls.length, 0);
});

test('quiet hours use fire time, cross midnight, preserve boundary and disabled category rules', async () => {
  const { state, reminders } = fixture();
  const day = new Date(Date.now() + 2 * 86400000); day.setHours(23, 0, 0, 0);
  const request = payload({ at: day.toISOString() });
  const prefs = { dndEnabled: true, dndStartMinutes: 22 * 60, dndEndMinutes: 6 * 60 };
  assert.equal((await reminders.schedule(request, bundle, prefs)).reason, 'quiet-hours');
  assert.equal((await reminders.schedule(request, bundle, { astronomyEventsEnabled: false })).reason, 'category-disabled');
  assert.equal((await reminders.schedule({ ...request, kind: 'calendar' }, bundle, { astronomyEventsEnabled: false })).ok, true);
  assert.equal((await reminders.schedule({ ...request, quietHours: { enabled: false, startMinutes: 0, endMinutes: 0 } }, bundle, prefs)).reason, 'quiet-hours');
  day.setHours(6);
  assert.equal((await reminders.schedule({ ...request, at: day.toISOString() }, bundle, prefs)).ok, true);
  day.setHours(22);
  assert.equal((await reminders.schedule({ ...request, at: day.toISOString() }, bundle, prefs)).reason, 'quiet-hours');
  assert.equal((await reminders.schedule({ ...request, leadMinutes: 120 }, bundle, prefs)).ok, true);
  assert.equal(state.authCalls, 0);
});

test('timer and alarm validate their own fields without needing a date', async () => {
  const { reminders, state } = fixture();
  assert.equal((await reminders.schedule(payload({ at: undefined, reminderType: 'timer', triggerSeconds: 5 }), bundle)).ok, true);
  assert.equal(state.records[0].reminderReq.triggerTimeInSeconds, 5);
  assert.equal((await reminders.schedule(payload({ at: undefined, reminderType: 'alarm', hour: 0, minute: 0, daysOfWeek: [] }), bundle)).ok, true);
  assert.deepEqual(state.records[1].reminderReq.daysOfWeek, []);
});

test('privacy denial blocks publication and authorization, cancellation remains available', async () => {
  const { reminders, notifications, state } = fixture();
  state.consent = false;
  assert.equal((await reminders.schedule(payload(), bundle)).reason, 'privacy-required');
  assert.equal(await notifications.publish({ id: 0, title: 't', text: 'b' }, bundle), false);
  assert.equal(await notifications.requestAuthorization({}), false);
  assert.equal(state.authCalls, 0);
  assert.equal(state.publishCalls.length, 0);
  assert.equal((await reminders.cancel(0)).ok, true);
});

test('foreground guard is rechecked after asynchronous reads and calendar panel is allowed', async () => {
  const { reminders, state } = fixture();
  let checks = 0;
  const guarded = await reminders.schedule(payload({ panel: 'calendar' }), bundle, undefined, () => ++checks < 2);
  assert.equal(guarded.reason, 'interaction-unavailable');
  assert.equal(state.publishCalls.length, 0);
  const published = await reminders.schedule(payload({ panel: 'calendar' }), bundle, undefined, () => true);
  assert.equal(published.ok, true);
  assert.equal(state.records[0].reminderReq.wantAgent.parameters.panel, 'calendar');
});

test('ordinary notification validation and system/WantAgent failures resolve false', async () => {
  const { notifications, state } = fixture();
  for (const request of [null, {}, { id: -1, title: 't', text: 'b' }, { id: 0, title: {}, text: 'b' }, { id: 0, title: 't', text: 'b', lines: ['1', '2', '3', '4'] }, { id: 0, title: 't', text: 'b', route: { jd: NaN } }]) assert.equal(await notifications.publish(request, bundle), false);
  const request = { id: 0, title: 't', text: 'b', route: { target: 'Sun' } };
  assert.equal(await notifications.publish(request), false);
  state.agentError = { code: 16000007 };
  assert.equal(await notifications.publish(request, bundle), false);
  delete state.agentError;
  state.nullAgent = true;
  assert.equal(await notifications.publish(request, bundle), false);
  state.nullAgent = false;
  state.notificationError = null;
  assert.equal(await notifications.publish(request, bundle), false);
  delete state.notificationError;
  assert.equal(await notifications.publish(request, bundle), true);
  assert.equal(state.notificationCalls.length, 1);
  assert.equal(state.authCalls, 0);
});

test('ordinary notifications create per-ID runtime WantAgents, cancel awaits completion', async () => {
  const { notifications, state } = fixture();
  for (const id of [0, 1]) assert.equal(await notifications.publish({ id, title: 't', text: 'b', route: { panel: 'astro', tab: 8, eventId: 'term-' + id, jd: 2462000, target: 'Sun' } }, bundle), true);
  const first = state.agentCalls[0];
  assert.equal(first.wants[0].bundleName, bundle);
  assert.equal(first.wants[0].abilityName, 'QAbility');
  assert.equal(first.wants[0].parameters.jd, 2462000);
  assert.equal(first.requestCode, 0);
  assert.notEqual(first.wants[0].uri, state.agentCalls[1].wants[0].uri);
  state.notificationCancelGate = deferred();
  let finished = false;
  const cancelling = notifications.cancel(0).then(value => { finished = true; return value; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(finished, false);
  state.notificationCancelGate.resolve();
  assert.equal(await cancelling, true);
  state.notificationCancelError = { code: 999 };
  assert.equal(await notifications.cancel(1), false);
  assert.equal(await notifications.cancel(-1), false);
});
