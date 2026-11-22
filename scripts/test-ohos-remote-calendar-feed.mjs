import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import {
  validateRemoteCalendarManifest,
  validateRemoteCalendarFeed,
  mergeRemoteCalendarEvents,
  retractedRemoteEventIds,
  countRemoteDynamicEvents
} from '../harmonyos/ets-source/state/RemoteCalendarFeed.ts';
import {
  calendarCategoryOfKind,
  isHighlightCalendarEvent,
  filterCalendarEvents
} from '../harmonyos/ets-source/state/AstronomyCalendarFilter.ts';
import {
  buildNoaaAuroraEntries,
  buildCalendarFeedArtifacts
} from '../deploy/calendar-feed/build-calendar-feed.mjs';

const readEts = rel => readFileSync(new URL(`../harmonyos/ets-source/${rel}`, import.meta.url), 'utf8');

test('manifest & feed validators accept well-formed artifacts and reject path traversal or bad hashes', () => {
  const now = Date.UTC(2026, 10, 22, 6, 0, 0);
  const artifacts = buildCalendarFeedArtifacts([
    {
      id: 'comet-2026-x1',
      revision: 1,
      action: 'upsert',
      kind: 'comet-event',
      title: 'C/2026 X1 彗星过近日点',
      titleEn: 'Comet C/2026 X1 Perihelion',
      body: '日落后西北低空双筒望远镜可见。',
      at: now + 3 * 86400000,
      target: 'C/2026 X1',
      highlight: true,
      expiresAt: now + 10 * 86400000
    }
  ], now);

  const manifest = validateRemoteCalendarManifest(artifacts.manifestDoc);
  assert.ok(manifest !== undefined);
  assert.equal(manifest.bytes, Buffer.byteLength(artifacts.feedJson, 'utf8'));
  assert.equal(manifest.sha256, createHash('sha256').update(artifacts.feedJson, 'utf8').digest('hex'));

  const feed = validateRemoteCalendarFeed(artifacts.feedDoc, now);
  assert.ok(feed !== undefined);
  assert.equal(feed.entries.length, 1);
  assert.equal(feed.entries[0].id, 'remote:comet-2026-x1');

  assert.equal(validateRemoteCalendarManifest({ ...artifacts.manifestDoc, feedPath: '/v1/calendar/../secret.json' }), undefined);
  assert.equal(validateRemoteCalendarManifest({ ...artifacts.manifestDoc, sha256: 'not-a-hash' }), undefined);
  assert.equal(validateRemoteCalendarFeed({ schemaVersion: 2, generation: 1, updatedAt: now, entries: [] }, now), undefined);
});

test('mergeRemoteCalendarEvents handles upsert, enrich, retract, local regionFilter, and planet isolation', () => {
  const now = Date.UTC(2026, 10, 22, 6, 0, 0);
  const rangeStart = Date.UTC(2026, 10, 1, 0, 0, 0);
  const rangeEnd = Date.UTC(2026, 11, 1, 0, 0, 0);

  const localEvents = [
    {
      id: 'meteor:GEM:2026',
      kind: 'meteor-peak',
      title: '双子座流星雨极大',
      at: Date.UTC(2026, 10, 25, 14, 0, 0),
      jd: Date.UTC(2026, 10, 25, 14, 0, 0) / 86400000 + 2440587.5,
      body: '本地计算极大窗口。',
      target: 'Gemini',
      panel: 'calendar',
      tab: 0,
      observerPlanet: 'Earth'
    },
    {
      id: 'remote:old-launch',
      kind: 'spaceflight',
      title: '旧发射窗口',
      at: Date.UTC(2026, 10, 24, 12, 0, 0),
      jd: Date.UTC(2026, 10, 24, 12, 0, 0) / 86400000 + 2440587.5,
      body: '将被撤回',
      target: '',
      panel: 'calendar',
      tab: 0,
      observerPlanet: 'Earth',
      isRemote: true
    }
  ];

  const feed = validateRemoteCalendarFeed({
    schemaVersion: 1,
    generation: 2026112201,
    updatedAt: now,
    entries: [
      {
        id: 'aurora-g4',
        revision: 1,
        action: 'upsert',
        kind: 'aurora-alert',
        title: 'G4 强地磁暴极光预警',
        body: '北纬 38° 以上地区今夜有望目视极光。',
        at: Date.UTC(2026, 10, 23, 15, 0, 0),
        target: 'North',
        highlight: true,
        regionFilter: { minLat: 38, maxLat: 90 },
        expiresAt: Date.UTC(2026, 10, 26, 0, 0, 0)
      },
      {
        id: 'enrich-gem',
        revision: 2,
        action: 'enrich',
        targetEventId: 'meteor:GEM:2026',
        kind: 'editorial',
        title: '双子座观星攻略',
        body: '今年残月干扰较小，23 时后辐射点升高最佳。',
        badge: '观星攻略',
        at: 0,
        highlight: true
      },
      {
        id: 'retract-old-launch',
        revision: 3,
        action: 'retract',
        targetEventId: 'remote:old-launch',
        kind: 'spaceflight',
        title: '',
        body: '',
        at: 0
      }
    ]
  }, now);
  assert.ok(feed !== undefined);

  // Beijing (39.9°N) receives G4 aurora, enriched meteor event, and has old-launch retracted
  const beijingMerged = mergeRemoteCalendarEvents(localEvents, feed.entries, {
    rangeStart, rangeEnd, observerPlanet: 'Earth',
    observerLatitude: 39.9, observerLongitude: 116.4, regionId: 'follow', language: 'zh', nowMs: now
  });
  assert.equal(beijingMerged.length, 2);
  assert.equal(beijingMerged[0].id, 'remote:aurora-g4');
  assert.equal(beijingMerged[0].isRemote, true);
  assert.equal(Math.abs((beijingMerged[0].jd - 2440587.5) * 86400000 - beijingMerged[0].at) <= 1, true);
  assert.equal(countRemoteDynamicEvents(beijingMerged), 1);

  assert.equal(beijingMerged[1].id, 'meteor:GEM:2026');
  assert.equal(beijingMerged[1].remoteEnriched, true);
  assert.match(beijingMerged[1].body, /观星攻略.*残月干扰较小/);

  // Guangzhou (23.1°N) locally filters out minLat:38 aurora without uploading location
  const guangzhouMerged = mergeRemoteCalendarEvents(localEvents, feed.entries, {
    rangeStart, rangeEnd, observerPlanet: 'Earth',
    observerLatitude: 23.1, observerLongitude: 113.3, regionId: 'follow', language: 'zh', nowMs: now
  });
  assert.equal(guangzhouMerged.length, 1);
  assert.equal(guangzhouMerged[0].id, 'meteor:GEM:2026');

  // Mars observer never receives Earth dynamic overlay events
  const marsMerged = mergeRemoteCalendarEvents([], feed.entries, {
    rangeStart, rangeEnd, observerPlanet: 'Mars',
    observerLatitude: 45, observerLongitude: 0, regionId: 'follow', language: 'zh', nowMs: now
  });
  assert.equal(marsMerged.length, 0);

  assert.ok(retractedRemoteEventIds(feed.entries, now).includes('remote:old-launch'));
});

test('dynamic remote events integrate with calendar filters, highlights, and smart notification timing', () => {
  const now = Date.UTC(2026, 10, 22, 6, 0, 0);
  const aurora = {
    id: 'remote:aurora-g4',
    kind: 'aurora-alert',
    title: 'G4 强地磁暴极光预警',
    at: now + 10 * 3600000,
    jd: (now + 10 * 3600000) / 86400000 + 2440587.5,
    body: '面向北方低空观测。',
    target: 'North',
    panel: 'calendar',
    tab: 0,
    isRemote: true,
    remoteHighlight: true
  };

  assert.equal(calendarCategoryOfKind(aurora.kind), 'dynamic');
  assert.equal(isHighlightCalendarEvent(aurora), true);
  assert.equal(filterCalendarEvents([aurora], {
    selectedCategories: ['dynamic'], satelliteSubFilter: 'all', highlightOnly: true
  }, 'Earth').length, 1);

  const timingSrc = readEts('qability/AstronomyNotificationTiming.ts');
  assert.match(timingSrc, /event\.remoteHighlight === true \|\| event\.kind === 'aurora-alert'/);
});

test('NOAA Kp storm builder merges contiguous geomagnetic storm windows with latitude thresholds', () => {
  const now = Date.UTC(2026, 10, 22, 0, 0, 0);
  const rows = [
    ['time_tag', 'kp', 'observed', 'noaa_scale'],
    ['2026-11-22 12:00:00', '3.33', 'predicted', null],
    ['2026-11-22 15:00:00', '6.00', 'predicted', 'G2'],
    ['2026-11-22 18:00:00', '7.33', 'predicted', 'G3'],
    ['2026-11-22 21:00:00', '5.67', 'predicted', 'G1'],
    ['2026-11-23 00:00:00', '3.00', 'predicted', null]
  ];
  const entries = buildNoaaAuroraEntries(rows, now);
  assert.equal(entries.length, 1);
  assert.equal(entries[0].kind, 'aurora-alert');
  assert.equal(entries[0].highlight, true);
  assert.equal(entries[0].regionFilter.minLat, 40);
  assert.match(entries[0].title, /G3/);
});

test('HarmonyOS host wires static SHA-256 feed sync into startup, foreground, calendar, widgets, and subscriptions', () => {
  const serviceSrc = readEts('capability/RemoteCalendarFeedService.ets');
  assert.match(serviceSrc, /https:\/\/skyinstrument\.cn/);
  assert.match(serviceSrc, /computeSha256Hex/);
  assert.match(serviceSrc, /hasCurrentPrivacyConsent\(\)/);
  assert.match(serviceSrc, /OFFLINE_APPGALLERY_BUILD/);

  const mainSrc = readEts('pages/MainWindowNativeNode.ets');
  assert.match(mainSrc, /this\.syncRemoteCalendarFeed\(false\)/);
  assert.match(mainSrc, /this\.calendarController\.refreshRemoteOverlay\(\)/);
  assert.match(mainSrc, /RemoteCalendarFeedService\.getInstance\(\)\.getEntries\(\)/);

  const subFeedSrc = readEts('capability/AstronomySubscriptionFeed.ets');
  assert.match(subFeedSrc, /mergeRemoteCalendarEvents\(/);

  const panelSrc = readEts('panels/panels/AstronomyCalendarPanel.ets');
  assert.match(panelSrc, /remoteDynamicCard\(/);
  assert.match(panelSrc, /this\.host\.syncRemoteFeed\?\.\(\)/);
});
