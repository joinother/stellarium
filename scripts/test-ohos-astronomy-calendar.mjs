import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const controllerSource = read('harmonyos/ets-source/capability/AstronomyCalendarController.ets');
const source = ['state/AstronomyCalendarText.ts', 'state/AstronomyCalendarEvent.ts', 'state/AstronomyCalendarStore.ets']
  .map(path => read('harmonyos/ets-source/' + path)).concat(controllerSource).join('\n')
  .replace(/^import .*$/gm, '').replace(/^@Observed\r?\n/gm, '');
const calendar = await import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(source))}`);
const { calendarMonth, calendarDate, calendarDays, calendarAt, calendarJd, calendarQuery, calendarNativeEvents,
  calendarMonthEvents, calendarDayEvents, AstronomyCalendarStore, AstronomyCalendarController } = calendar;
const event = (year, month, day = 20, index = 5, kind = 'solar-term') => ({
  id: `${kind}-${year}-${month}-${index}`, kind, index,
  jd: calendarJd(calendarDate(year, month, day).getTime() + 12 * 3600000)
});
const response = (year, month, events = [event(year, month)]) => ({
  ok: true, ...calendarQuery(calendarMonth(year, month)), timeScale: 'UT', events
});
function setup() {
  const store = new AstronomyCalendarStore();
  const calls = [], feeds = [], views = [], reminders = [];
  const hooks = { feedChanged: events => feeds.push(events), viewSky: event => views.push(event),
    remind: async event => { reminders.push(event); return { ok: true, reminderId: 0, message: 'scheduled' }; } };
  const port = { requestLongRunning: (name, payload, ok, fail, progress, attempts, cancelled) =>
    calls.push({ name, payload, ok, fail, cancelled }) };
  return { store, calls, feeds, views, reminders, hooks, controller: new AstronomyCalendarController(port, store, hooks) };
}

test('Gregorian leap boundaries, small years and invalid input', () => {
  assert.equal(calendarMonth(2024, 2).days, 29);
  assert.equal(calendarMonth(2100, 2).days, 28);
  assert.equal(calendarMonth(2000, 2).days, 29);
  assert.equal(calendarDate(99, 1, 1).getFullYear(), 99);
  assert.equal(calendarMonth(3000, 12).days, 31);
  for (const values of [[0, 1], [3001, 1], [2024, 0], [2024, 13], [NaN, 1], [2024, 1.5]]) assert.throws(() => calendarMonth(...values));
});
test('timeline appends next month, preserves details and ignores stale pagination', () => {
  const model = setup();
  model.controller.loadMonth(2026, 12);
  model.calls.at(-1).ok(response(2026, 12));
  const id = model.store.events[0].id;
  model.controller.selectEvent(id);
  model.controller.loadMore();
  const more = model.calls.at(-1);
  assert.equal(JSON.parse(more.payload).year, 2027);
  model.controller.loadMore();
  assert.equal(model.calls.length, 2);
  more.ok(response(2027, 1));
  assert.equal(model.store.events.length, 2);
  assert.equal(model.store.selectedEventId, id);
  model.controller.setLanguage('en');
  assert.equal(model.store.events.length, 2);
  model.controller.loadMore();
  const stale = model.calls.at(-1);
  model.controller.loadMonth(2026, 3);
  stale.ok(response(2027, 2));
  assert.equal(model.store.events.length, 0);
  assert.equal(model.store.loadingMore, false);
});
test('meteor estimates and planetary events survive parsing with local titles and targets', () => {
  const rows = [{ ...event(2026, 11, 18), kind: 'meteor-peak', title: 'Leonids', titleEn: 'Leonids peak', target: 'Leonids', showerCode: 'LEO' },
    { ...event(2026, 11, 20), id: 'planetary-one', kind: 'planetary-event', title: '水星西大距', titleEn: 'Mercury greatest western elongation', target: 'Mercury' }];
  const events = calendarNativeEvents(response(2026, 11, rows), calendarMonth(2026, 11), 'zh');
  assert.equal(events[0].title, '狮子座流星雨极大');
  assert.match(events[0].body, /估算/);
  assert.equal(events[1].target, 'Mercury');
  assert.equal(events[1].phaseIndex, undefined);
});
test('half-open months and day grids preserve midnight millisecond boundaries', () => {
  const month = calendarMonth(2026, 11);
  const events = [month.start - 1, month.start, month.end - 1, month.end].map((at, index) => ({ at, id: String(index) }));
  const filtered = calendarMonthEvents(events, month);
  assert.deepEqual(filtered.map(event => event.id), ['1', '2']);
  for (const event of events) assert.equal(calendarAt(calendarJd(event.at)), event.at);
  assert.equal(calendarDayEvents(filtered, 30).length, 1);
  const cells = calendarDays(month, filtered);
  assert.equal(cells.length % 7, 0);
  assert.equal(cells.filter(cell => cell.day > 0).length, 30);
  assert.equal(cells.find(cell => cell.day === 30).count, 1);
});
test('DST and positive offsets produce exact local month query boundaries', () => {
  const original = process.env.TZ;
  try {
    process.env.TZ = 'America/New_York';
    assert.equal((calendarMonth(2026, 3).end - calendarMonth(2026, 3).start) / 3600000, 31 * 24 - 1);
    assert.equal((calendarMonth(2026, 11).end - calendarMonth(2026, 11).start) / 3600000, 30 * 24 + 1);
    const model = setup();
    model.controller.loadMonth(2026, 3);
    const payload = JSON.parse(model.calls[0].payload);
    assert.equal(calendarAt(payload.endJD), Date.UTC(2026, 3, 1, 4));
    assert.equal(calendarAt(payload.startJD), Date.UTC(2026, 2, 1, 5));
    const at = Date.UTC(2026, 3, 1, 3, 59);
    assert.equal(calendarMonthEvents([{ at, id: 'edge' }], calendarMonth(2026, 3)).length, 1);
    process.env.TZ = 'Asia/Singapore';
    assert.equal(calendarMonthEvents([{ at, id: 'edge' }], calendarMonth(2026, 3)).length, 0);
  } finally {
    if (original === undefined) delete process.env.TZ; else process.env.TZ = original;
  }
});
test('native feed sorts, deduplicates, derives timestamp and localizes routing', () => {
  const solar = event(2026, 3);
  const lunar = event(2026, 3, 10, 2, 'moon-phase');
  const result = response(2026, 3, [solar, solar, { ...lunar, at: 0 }, event(2026, 4, 1)]);
  const events = calendarNativeEvents(result, calendarMonth(2026, 3), 'en');
  assert.deepEqual(events.map(item => item.title), ['Full moon', 'March equinox']);
  assert.deepEqual(events.map(item => [item.target, item.panel, item.tab]), [['Moon', 'astro', 6], ['Sun', 'astro', 8]]);
  assert.equal(events[0].at, calendarAt(lunar.jd));
  assert.equal(events[0].timeScale, 'UT');
  assert.equal(calendarNativeEvents(result, calendarMonth(2026, 3), 'zh-Hans')[0].title, '满月');
});
test('corrupt dates, wrong query and wrong timescale fail closed', () => {
  for (const overrides of [{ ok: false }, { year: 2027 }, { month: 4 }, { timeScale: 'TT' },
    { startJD: NaN }, { endJD: Infinity }, { events: undefined }]) {
    assert.throws(() => calendarNativeEvents({ ...response(2026, 3), ...overrides }, calendarMonth(2026, 3), 'zh'));
  }
  for (const row of [null, { ...event(2026, 3), index: 24 }, { ...event(2026, 3), jd: NaN }, { ...event(2026, 3), id: '' }]) {
    assert.throws(() => calendarNativeEvents(response(2026, 3, [row]), calendarMonth(2026, 3), 'zh'));
  }
});
test('read-only month loading, day/detail selection and explicit action hooks', async () => {
  const model = setup();
  model.controller.loadMonth(2090, 3);
  model.calls[0].ok(response(2090, 3));
  assert.equal(model.store.events.length, 1);
  assert.equal(model.store.loading, false);
  assert.equal(model.calls[0].name, 'getAstronomyCalendarEvents');
  assert.deepEqual(JSON.parse(model.calls[0].payload), calendarQuery(calendarMonth(2090, 3)));
  model.controller.selectDay(20);
  assert.equal(model.store.visibleEvents().length, 1);
  const id = model.store.events[0].id;
  model.controller.selectEvent(id);
  assert.equal(model.store.selectedEvents().length, 1);
  assert.equal(model.views.length, 0);
  assert.equal(model.reminders.length, 0);
  model.controller.viewSky('unknown');
  model.controller.viewSky(id);
  assert.deepEqual(await model.controller.remind(id), { ok: true, reminderId: 0, message: 'scheduled' });
  assert.equal(model.views.length, 1);
  assert.equal(model.reminders.length, 1);
  assert.equal(model.store.actionMessage, 'scheduled');
  model.controller.showMonthEvents();
  assert.equal(model.store.selectedDay, 0);
});
test('December rollover and far years never depend on simulation year', () => {
  const model = setup();
  model.controller.loadMonth(2026, 12);
  model.controller.nextMonth();
  assert.deepEqual([model.store.year, model.store.month], [2027, 1]);
  model.controller.previousMonth();
  assert.deepEqual([model.store.year, model.store.month], [2026, 12]);
  model.controller.loadMonth(2300, 3);
  model.calls.at(-1).ok(response(2300, 3));
  assert.equal(model.store.events.length, 1);
  assert.ok(model.calls.every(call => call.name === 'getAstronomyCalendarEvents'));
});
test('stale success/failure and disposal cannot replace a newly selected month', () => {
  const model = setup();
  model.controller.loadMonth(2026, 3);
  const old = model.calls.at(-1);
  model.controller.loadMonth(2026, 6);
  assert.equal(old.cancelled(), true);
  old.ok(response(2026, 3)); old.fail();
  assert.equal(model.store.loading, true);
  model.calls.at(-1).ok(response(2026, 6));
  assert.equal(new Date(model.store.events[0].at).getMonth(), 5);
  model.controller.reload();
  const pending = model.calls.at(-1);
  model.controller.dispose();
  pending.ok(response(2026, 6)); pending.fail();
  assert.equal(pending.cancelled(), true);
  assert.equal(model.store.loading, false);
  assert.equal(model.store.error, '');
});
test('native error and empty success remain distinct; changing language needs no query', () => {
  const model = setup();
  model.controller.loadMonth(2026, 3);
  model.calls.at(-1).fail();
  assert.notEqual(model.store.error, '');
  model.controller.reload(); model.calls.at(-1).ok(response(2026, 3, []));
  assert.equal(model.store.loaded, true);
  assert.equal(model.store.error, '');
  model.controller.reload(); model.calls.at(-1).ok(response(2026, 3));
  const id = model.store.events[0].id;
  const count = model.calls.length;
  model.controller.setLanguage('en-US');
  assert.equal(model.store.events[0].title, 'March equinox');
  assert.equal(model.store.events[0].id, id);
  assert.equal(model.calls.length, count);
  assert.match(model.store.coverage, /Solar terms/);
  model.controller.setLanguage('zh-Hans');
  assert.equal(model.store.events[0].title, '春分');
});
test('past reminders, duplicate taps, host errors and late messages are handled honestly', async () => {
  const model = setup();
  model.controller.loadMonth(2000, 3); model.calls.at(-1).ok(response(2000, 3));
  assert.equal((await model.controller.remind(model.store.events[0].id)).reason, 'past-event');
  assert.equal(model.reminders.length, 0);
  assert.match(model.store.actionMessage, /已发生/);
  model.controller.loadMonth(2090, 3); model.calls.at(-1).ok(response(2090, 3));
  const id = model.store.events[0].id;
  model.controller.selectEvent(id);
  let release; let count = 0;
  model.hooks.remind = () => { count++; return new Promise(resolve => { release = resolve; }); };
  const pending = model.controller.remind(id);
  assert.equal((await model.controller.remind(id)).reason, 'busy'); assert.equal(count, 1);
  model.controller.nextMonth(); release({ ok: true, reminderId: 42, message: 'old reminder succeeded' });
  assert.equal((await pending).reminderId, 42);
  assert.equal(model.store.actionMessage, '');
  assert.equal(model.store.reminderPendingId, '');
  model.controller.loadMonth(2090, 3); model.calls.at(-1).ok(response(2090, 3));
  model.controller.selectEvent(id);
  model.hooks.remind = async () => { throw new Error('denied'); };
  assert.equal((await model.controller.remind(id)).reason, 'scheduling-error');
  assert.match(model.store.actionMessage, /未设置成功/);
});

test('structured scheduling failures preserve reason, code and partial reminder metadata', async () => {
  const model = setup();
  model.controller.loadMonth(2090, 3); model.calls.at(-1).ok(response(2090, 3));
  const id = model.store.events[0].id;
  model.controller.selectEvent(id);
  for (const failure of [
    { ok: false, reason: 'notification-disabled', code: 1700001, notificationEnabled: false, error: 'Permission required' },
    { ok: false, reason: 'quiet-hours', error: 'Quiet hours' },
    { ok: false, reason: 'quota-or-entitlement', code: 1700002, error: 'Quota exceeded' },
    { ok: false, reason: 'replacement-cleanup-failed', partial: true, reminderId: 0, activeReminderIds: [0, 3], error: 'Cleanup failed' }
  ]) {
    model.hooks.remind = async () => failure;
    assert.deepEqual(await model.controller.remind(id), failure);
    assert.equal(model.store.actionMessage, failure.error);
    assert.equal(model.store.reminderPendingId, '');
  }
  assert.equal((await model.controller.remind('missing')).reason, 'unknown-event');
  model.controller.dispose();
  assert.equal((await model.controller.remind(id)).reason, 'disposed');
});

test('CLI reminder block propagates real outcomes rather than unconditional success', async () => {
  const host = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
  const start = host.indexOf("if (name === 'remindCalendarEvent') {");
  assert.ok(start >= 0);
  const block = host.slice(start, host.indexOf("if (name === 'viewCalendarEvent')", start));
  const run = new Function('calendar', 'payload', 'result', `return (async () => { const name = 'remindCalendarEvent'; ${block} return result; })()`);
  for (const outcome of [
    { ok: true, reminderId: 0, unchanged: true },
    { ok: false, reason: 'past-event', error: 'Event is past' },
    { ok: false, reason: 'permission-denied', code: 201, error: 'Denied' },
    { ok: false, reason: 'busy', message: 'Retry later' },
    { ok: false }
  ]) {
    const result = await run({ remind: async id => { assert.equal(id, 'selected'); return outcome; } }, 'selected', { ok: true });
    assert.equal(result.ok, outcome.ok);
    assert.deepEqual(result.reminder, outcome);
    if (!outcome.ok) {
      assert.equal(result.error, outcome.error ?? outcome.message ?? 'Reminder could not be scheduled');
      assert.equal(result.reason, outcome.reason);
      assert.equal(result.code, outcome.code);
    }
  }
});
test('calendar cannot call mutating legacy commands or obtain simulation state', () => {
  assert.doesNotMatch(controllerSource, /['"](?:getAlmanac|getMoonPhases|getEclipses|getPhenomena|getSimulationTime|getTimeNavigationTarget|setJD|setDate|setTimeRate|triggerAction)['"]/);
  assert.match(controllerSource, /requestLongRunning\('getAstronomyCalendarEvents'/);
  const native = read('src/StelMainView.cpp');
  const start = native.indexOf('if (commandName == "getAstronomyCalendarEvents")');
  assert.ok(start > 0);
  const branch = native.slice(start, native.indexOf('\n\t\tif (commandName ==', start + 1));
  assert.doesNotMatch(branch, /->setJD\(|->setJDE\(|->setTimeRate\(|core->update\(/);
});

test('language refresh after timezone change requeries the new local boundaries', () => {
  const original = process.env.TZ;
  try {
    process.env.TZ = 'UTC';
    const model = setup();
    model.controller.loadMonth(2026, 3); model.calls.at(-1).ok(response(2026, 3));
    process.env.TZ = 'Asia/Singapore';
    model.controller.setLanguage('en');
    assert.equal(model.calls.length, 2);
    assert.equal(model.store.loading, true);
    assert.equal(calendarAt(JSON.parse(model.calls.at(-1).payload).startJD), Date.UTC(2026, 1, 28, 16));
  } finally {
    if (original === undefined) delete process.env.TZ; else process.env.TZ = original;
  }
});
