import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import {
  calendarCategoriesForPlanet,
  countCalendarEventsByCategory,
  filterCalendarEvents,
  hasActiveCalendarFilter,
  monthOverlapsSatelliteWindow,
  parseTonightSatellitePassesToCalendarEvents
} from '../harmonyos/ets-source/state/AstronomyCalendarFilter.ts';

const read = (rel) => readFileSync(new URL('../' + rel, import.meta.url), 'utf8');

test('Earth and off-Earth worlds expose appropriate calendar filter categories', () => {
  const earthCats = calendarCategoriesForPlanet('Earth').map(c => c.id);
  assert.deepEqual(earthCats, ['moon', 'planet', 'meteor', 'solar', 'satellite']);

  const marsCats = calendarCategoriesForPlanet('Mars').map(c => c.id);
  assert.deepEqual(marsCats, ['planet', 'companion', 'eclipse', 'season']);
  assert.ok(!marsCats.includes('solar'));
  assert.ok(!marsCats.includes('satellite'));
  assert.ok(!marsCats.includes('meteor'));
});

test('multi-select category filter, highlight filter, and satellite sub-filters compose accurately', () => {
  const now = Date.UTC(2026, 10, 21, 12, 0, 0);
  const events = [
    { id: 'm1', kind: 'moon-phase', title: '满月', at: now, jd: 2461366, body: '', target: 'Moon', panel: 'astro', tab: 6, isSupermoon: true },
    { id: 'm2', kind: 'moon-phase', title: '上弦月', at: now + 1000, jd: 2461366.1, body: '', target: 'Moon', panel: 'astro', tab: 6 },
    { id: 'p1', kind: 'planetary-event', title: '木星冲日', at: now + 2000, jd: 2461366.2, body: '', target: 'Jupiter', panel: 'astro', tab: 0, subtype: 'opposition' },
    { id: 's1', kind: 'solar-term', title: '小雪', at: now + 3000, jd: 2461366.3, body: '', target: 'Sun', panel: 'astro', tab: 8 },
    { id: 'sat-css', kind: 'satellite-pass', title: '中国空间站 天宫 过境 · 最高 48°', at: now + 4000, jd: 2461366.4, body: '', target: 'CSS (TIANHE)', panel: 'satellites', tab: 0, satCatalogId: '48274', satArchetype: 'tiangong', satMaxAlt: 48, satVisible: true },
    { id: 'sat-noaa', kind: 'satellite-pass', title: 'NOAA 19 气象卫星 过境 · 最高 22°', at: now + 5000, jd: 2461366.5, body: '', target: 'NOAA 19', panel: 'satellites', tab: 0, satCatalogId: '33591', satArchetype: 'earth_obs', satMaxAlt: 22, satVisible: false }
  ];

  const counts = countCalendarEventsByCategory(events);
  assert.equal(counts.moon, 2);
  assert.equal(counts.planet, 1);
  assert.equal(counts.solar, 1);
  assert.equal(counts.satellite, 2);

  // Empty categories -> all
  assert.equal(filterCalendarEvents(events, { selectedCategories: [], satelliteSubFilter: 'all', highlightOnly: false }).length, 6);
  assert.equal(hasActiveCalendarFilter({ selectedCategories: [], satelliteSubFilter: 'all', highlightOnly: false }), false);

  // Multi-select moon + satellite
  const moonAndSat = filterCalendarEvents(events, { selectedCategories: ['moon', 'satellite'], satelliteSubFilter: 'all', highlightOnly: false });
  assert.deepEqual(moonAndSat.map(e => e.id), ['m1', 'm2', 'sat-css', 'sat-noaa']);

  // Satellite sub-filter: stations only
  const stationsOnly = filterCalendarEvents(events, { selectedCategories: ['satellite'], satelliteSubFilter: 'stations', highlightOnly: false });
  assert.deepEqual(stationsOnly.map(e => e.id), ['sat-css']);

  // Satellite sub-filter: high elevation >=30°
  const highAlt = filterCalendarEvents(events, { selectedCategories: ['satellite'], satelliteSubFilter: 'high_alt', highlightOnly: false });
  assert.deepEqual(highAlt.map(e => e.id), ['sat-css']);

  // Highlight only across all events: supermoon, opposition, space station pass
  const highlights = filterCalendarEvents(events, { selectedCategories: [], satelliteSubFilter: 'all', highlightOnly: true });
  assert.deepEqual(highlights.map(e => e.id), ['m1', 'p1', 'sat-css']);
});

test('parseTonightSatellitePassesToCalendarEvents formats rich Chinese/English pass events and filters out-of-month passes', () => {
  const monthStart = new Date(2026, 10, 1, 0, 0, 0, 0).getTime();
  const monthEnd = new Date(2026, 11, 1, 0, 0, 0, 0).getTime();
  const insideMs = new Date(2026, 10, 21, 19, 30, 0, 0).getTime();
  const outsideMs = new Date(2026, 11, 5, 19, 30, 0, 0).getTime();

  const passes = [
    {
      id: '48274',
      name: 'CSS (TIANHE)',
      englishName: 'CSS (TIANHE)',
      startAt: insideMs - 180000,
      peakAt: insideMs,
      endAt: insideMs + 180000,
      peakJd: insideMs / 86400000 + 2440587.5,
      maxAlt: 54.2,
      startAz: 315,
      endAz: 135,
      mag: -1.4,
      rangeKm: 418,
      durationSec: 360,
      visible: true
    },
    {
      id: '25544',
      name: 'ISS (ZARYA)',
      englishName: 'ISS (ZARYA)',
      peakAt: outsideMs,
      maxAlt: 40,
      visible: true
    }
  ];

  const zhEvents = parseTonightSatellitePassesToCalendarEvents(passes, monthStart, monthEnd, 'zh-CN');
  assert.equal(zhEvents.length, 1);
  assert.equal(zhEvents[0].kind, 'satellite-pass');
  assert.equal(zhEvents[0].satArchetype, 'tiangong');
  assert.equal(zhEvents[0].satVisible, true);
  assert.equal(zhEvents[0].satMaxAlt, 54);
  assert.match(zhEvents[0].title, /中国空间站 天宫 过境 · 最高 54°/);
  assert.match(zhEvents[0].body, /西北 → 东南/);

  const enEvents = parseTonightSatellitePassesToCalendarEvents(passes, monthStart, monthEnd, 'en');
  assert.equal(enEvents.length, 1);
  assert.match(enEvents[0].title, /CSS \(TIANHE\) Pass · Max 54°/);
});

test('monthOverlapsSatelliteWindow detects current 48h TLE forecast window accurately', () => {
  const midNov = new Date(2026, 10, 15, 12, 0, 0).getTime();
  assert.equal(monthOverlapsSatelliteWindow(2026, 11, midNov), true);
  assert.equal(monthOverlapsSatelliteWindow(2026, 12, midNov), false);
  assert.equal(monthOverlapsSatelliteWindow(2026, 10, midNov), false);
  // End of Nov overlaps Dec within 48h!
  const endNov = new Date(2026, 10, 30, 12, 0, 0).getTime();
  assert.equal(monthOverlapsSatelliteWindow(2026, 12, endNov), true);
});

test('Calendar panel, controller, store, and SettingsRepository wire filter persistence and satellite passes', () => {
  const panel = read('harmonyos/ets-source/panels/panels/AstronomyCalendarPanel.ets');
  const ctl = read('harmonyos/ets-source/capability/AstronomyCalendarController.ets');
  const repo = read('harmonyos/ets-source/state/SettingsRepository.ets');

  assert.match(panel, /filterBar\(\)/);
  assert.match(panel, /satellitePassCard\(/);
  assert.match(panel, /toggleCategory/);
  assert.match(panel, /setSatelliteSubFilter/);
  assert.match(panel, /setHighlightOnly/);
  assert.match(panel, /clearFilters/);
  assert.match(ctl, /fetchSatellitePassesIfApplicable/);
  assert.match(ctl, /recomputeMonthDays/);
  assert.match(repo, /calendarFilterCategories/);
  assert.match(repo, /calendarHighlightOnly/);
  assert.match(repo, /calendarSatSubFilter/);
});
