import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../harmonyos/ets-source/', import.meta.url);
const plain = name => stripTypeScriptTypes(readFileSync(new URL(name, root), 'utf8').replace(/^import .*\n/gm, '').replaceAll('export ', ''));
const calendar = plain('state/AstronomyCalendarEvent.ts');
const loader = plain('capability/AstronomySubscriptionFeed.ets');
const languageState = { value: 'en' };
const Loader = new Function('I18n', 'calendarText', 'calendarSolarTermTitle', 'calendarMoonPhaseTitle', calendar + loader + ';return AstronomySubscriptionFeedLoader')(
  { getLanguage: () => languageState.value }, (language, zh, en) => en, () => 'Solar term', () => 'Moon phase');

function monthFixture() {
  const state = { calls: [], gates: [], fail: false };
  const feed = new Loader({ observer: async () => undefined, request: async (command, payload) => {
    const query = JSON.parse(payload);
    state.calls.push(query);
    if (state.gates.length) await state.gates.shift();
    if (state.fail) return { ok: false, error: 'native failure' };
    return { ok: true, ...query, timeScale: 'UT', events: [{ id: 'phase-' + query.month, kind: 'moon-phase', index: 0, jd: query.startJD + 1 }] };
  } });
  const load = month => {
    const from = new Date(2030, month - 1, 1).getTime();
    return feed.load('astronomy', from, from + 86400000);
  };
  return { feed, state, load };
}

test('month cache coalesces concurrent reads, expires after six hours, and errors remain retryable', async () => {
  const { state, load } = monthFixture();
  let release;
  state.gates.push(new Promise(resolve => { release = resolve; }));
  const requests = Array.from({ length: 15 }, () => load(1));
  assert.equal(state.calls.length, 1);
  release();
  await Promise.all(requests);
  await load(1);
  assert.equal(state.calls.length, 1);
  const originalNow = Date.now;
  const later = Date.now() + 6 * 3600000 + 1;
  try {
    Date.now = () => later;
    await load(1);
    assert.equal(state.calls.length, 2);
    state.fail = true;
    await assert.rejects(load(2));
    state.fail = false;
    await load(2);
    assert.equal(state.calls.length, 4);
  } finally { Date.now = originalNow; }
});

test('month cache is bounded to six LRU entries and distinguishes language and local timezone boundaries', async () => {
  const { state, load } = monthFixture();
  for (let month = 1; month <= 6; month++) await load(month);
  await load(1);
  await load(7);
  await load(1);
  assert.equal(state.calls.length, 7);
  await load(2);
  assert.equal(state.calls.length, 8);
  const originalTz = process.env.TZ;
  try {
    languageState.value = 'zh';
    await load(1);
    assert.equal(state.calls.length, 9);
    process.env.TZ = 'Pacific/Honolulu';
    await load(1);
    process.env.TZ = 'Asia/Tokyo';
    await load(1);
    assert.notEqual(state.calls.at(-1).startJD, state.calls.at(-2).startJD);
    assert.equal(state.calls.length, 11);
  } finally {
    languageState.value = 'en';
    if (originalTz === undefined) delete process.env.TZ;
    else process.env.TZ = originalTz;
  }
});

test('invalidate clears cached and in-flight generations without caching stale completion', async () => {
  const { state, feed, load } = monthFixture();
  let releaseOld;
  state.gates.push(new Promise(resolve => { releaseOld = resolve; }));
  const old = load(1);
  const rejected = assert.rejects(old, /invalidated/);
  feed.invalidate();
  await load(1);
  releaseOld();
  await rejected;
  await load(1);
  assert.equal(state.calls.length, 2);
  feed.invalidate();
  await load(1);
  assert.equal(state.calls.length, 3);
});

test('cached month events still pass through current-time subscription filtering', async () => {
  const { state, load } = monthFixture();
  const at = new Date(2030, 0, 2).getTime();
  const source = plain('qability/AstronomyNotificationPolicy.ts') + plain('qability/AstronomySubscriptionPolicy.ts');
  const candidates = new Function(source + ';return subscriptionCandidates')();
  const preferences = { astronomyEventsEnabled: true, dndEnabled: false, passLeadMinutes: 0 };
  const originalNow = Date.now;
  try {
    Date.now = () => at - 60000;
    const initial = await load(1);
    assert.equal(candidates(initial, 'astronomy', preferences, Date.now(), at + 86400000).length, 1);
    Date.now = () => at + 1000;
    const cached = await load(1);
    assert.equal(state.calls.length, 1);
    assert.equal(cached.generatedAt, Date.now());
    assert.equal(candidates(cached, 'astronomy', preferences, Date.now(), at + 86400000).length, 0);
  } finally { Date.now = originalNow; }
});

test('native month loader uses actual month boundaries and shared converter without simulation mutation', async () => {
  const calls = [];
  const from = new Date(2030, 11, 20).getTime();
  const until = from + 45 * 86400000;
  const feed = new Loader({
    observer: async () => undefined,
    request: async (command, payload) => {
      const query = JSON.parse(payload); calls.push({ command, query });
      return { ok: true, ...query, timeScale: 'UT', events: [{ id: String(query.month), kind: 'moon-phase', index: 0, jd: query.startJD + 1 }] };
    }
  });
  const result = await feed.load('astronomy', from, until);
  assert.equal(calls.length, 3);
  assert.ok(calls.every(call => call.command === 'getAstronomyCalendarEvents'));
  assert.deepEqual(calls.map(call => [call.query.year, call.query.month]), [[2030, 12], [2031, 1], [2031, 2]]);
  assert.equal(result.events.length, 3);
});

function satelliteFixture() {
  const from = Date.now();
  const passAt = from + 3600000;
  const state = { observer: { key: 'earth:chosen:1,2,3', satelliteIds: ['25544'] }, calls: [], response: {
    ok: true, satellitePasses: { satelliteId: '25544', name: 'ISS', englishName: 'ISS (ZARYA)',
      calculatedAt: new Date(from).toISOString(), orbitValid: true, dataStatus: 'local',
      passes: [{ startJD: passAt / 86400000 + 2440587.5, visible: true, ongoing: false },
        { startJD: (passAt + 100000) / 86400000 + 2440587.5, visible: false, ongoing: false }] }
  } };
  const feed = new Loader({ observer: async () => state.observer, request: async (command, payload) => {
    state.calls.push({ command, payload: JSON.parse(payload) });
    if (state.changeObserver) state.observer = { ...state.observer, key: 'changed' };
    return state.response;
  } });
  return { feed, state, from };
}

test('satellite loader requests explicit real epoch, only accepts visible passes and preserves observer identity', async () => {
  const { feed, state, from } = satelliteFixture();
  const result = await feed.load('satellite', from, from + 2 * 86400000);
  assert.equal(state.calls[0].command, 'getSatellitePasses');
  assert.equal(state.calls[0].payload.startJD, from / 86400000 + 2440587.5);
  assert.equal(state.calls[0].payload.visibleOnly, true);
  assert.equal(result.events.length, 1);
  assert.equal(result.events[0].panel, 'satellites');
  assert.equal(result.events[0].kind, 'satellite-pass');
  assert.ok(result.events[0].id.includes(state.observer.key));
  assert.equal(result.observerKey, state.observer.key);
});

test('missing observer, stale TLE, stale simulation clock and observer changes fail without fabricated passes', async () => {
  for (const failure of ['observer', 'tle', 'clock', 'change', 'identity']) {
    const { feed, state, from } = satelliteFixture();
    if (failure === 'observer') state.observer = undefined;
    if (failure === 'tle') state.response.satellitePasses.dataStatus = 'stale';
    if (failure === 'clock') state.response.satellitePasses.calculatedAt = new Date(from - 86400000).toISOString();
    if (failure === 'change') state.changeObserver = true;
    if (failure === 'identity') state.response.satellitePasses.satelliteId = 'wrong';
    await assert.rejects(feed.load('satellite', from, from + 86400000));
    if (failure === 'observer') assert.equal(state.calls.length, 0);
  }
});

test('default satellite set includes both stations and fails honestly if one is absent', async () => {
  const { feed, state, from } = satelliteFixture();
  delete state.observer.satelliteIds;
  await assert.rejects(feed.load('satellite', from, from + 86400000));
  assert.deepEqual(state.calls.map(call => call.payload.id), ['25544', '48274']);
});

test('unsupported explicit epoch never falls back to the mutating legacy prediction', async () => {
  const { feed, state, from } = satelliteFixture();
  state.response = { ok: false, reason: 'explicit_epoch_prediction_unsupported' };
  await assert.rejects(feed.load('satellite', from, from + 86400000), /explicit_epoch_prediction_unsupported/);
  assert.equal(state.calls.length, 1);
  assert.equal(state.calls[0].payload.startJD, from / 86400000 + 2440587.5);
});
