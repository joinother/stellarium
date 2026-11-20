import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { validateReminder, normalizeRoute, routeError } from '../harmonyos/ets-source/qability/AstronomyNotificationPolicy.ts';
import { buildAstronomyCard, buildTimeline48hSnapshot, interpolateTimeline48h, applyTimeline48hToCard } from '../harmonyos/ets-source/form/AstronomyCardData.ts';

const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
const calSrc = ['harmonyos/ets-source/state/AstronomyCalendarText.ts', 'harmonyos/ets-source/state/AstronomyCalendarEvent.ts']
	.map(read).join('\n').replace(/^import .*$/gm, '');
const { calendarMonth, calendarQuery, calendarNativeEvents, calendarJd } = await import(
	`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(calSrc))}`
);

test('calendarQuery omits planet for Earth and passes explicit planet for off-Earth worlds', () => {
	const m = calendarMonth(2026, 11);
	const earthQ = calendarQuery(m);
	assert.equal(earthQ.planet, undefined);
	assert.equal(calendarQuery(m, 'Earth').planet, undefined);
	assert.equal(calendarQuery(m, 'Mars').planet, 'Mars');
	assert.equal(calendarQuery(m, 'Titan').planet, 'Titan');
});

test('calendarNativeEvents parses off-Earth companion phases, eclipses, seasons, and Earth elongations', () => {
	const m = calendarMonth(2026, 11);
	const midMs = m.start + 10 * 86400000;
	const midJd = calendarJd(midMs);
	const response = {
		ok: true,
		year: 2026,
		month: 11,
		startJD: calendarJd(m.start),
		endJD: calendarJd(m.end),
		timeScale: 'UT',
		observerPlanet: 'Mars',
		events: [
			{
				id: 'planetary-event-Mars-Earth-Sun-greatest-elongation-1',
				kind: 'planetary-event',
				index: 0,
				jd: midJd,
				title: '地球东大距',
				titleEn: 'Earth greatest eastern elongation (Mars)',
				body: '从火星观测，地球达到与太阳的最大角距（约 42.3°），为傍晚昏星最佳观测窗口。',
				target: 'Earth',
				primary: 'Earth',
				secondary: 'Sun',
				subtype: 'greatest-elongation',
				direction: 'east',
				separationDegrees: 42.3,
				observerPlanet: 'Mars'
			},
			{
				id: 'planetary-season-Mars-0-1',
				kind: 'planetary-season',
				index: 0,
				jd: midJd + 2,
				title: '火星北半球春分',
				titleEn: 'Mars Northern Spring Equinox',
				body: '按火星日心太阳黄经 Ls = 0° 精确计算的当地季节节点。',
				target: 'Sun',
				observerPlanet: 'Mars'
			},
			{
				id: 'companion-eclipse-Moon-Earth-1',
				kind: 'companion-eclipse',
				index: 0,
				jd: midJd + 4,
				title: '月球见地球食日',
				titleEn: 'Earth solar eclipse from Moon',
				body: '在月球上可见地球从太阳前方经过并遮挡阳光。',
				target: 'Earth',
				observerPlanet: 'Moon'
			}
		]
	};
	const events = calendarNativeEvents(response, m, 'zh-CN');
	assert.equal(events.length, 3);
	assert.equal(events[0].observerPlanet, 'Mars');
	assert.equal(events[0].target, 'Earth');
	assert.match(events[0].body, /从火星观测/);
	assert.equal(events[1].kind, 'planetary-season');
	assert.equal(events[2].kind, 'companion-eclipse');
	assert.equal(events[2].observerPlanet, 'Moon');
});

test('dual-track notification policy validates observerPlanet and isolates Mars vs Earth reminder keys', () => {
	const now = Date.UTC(2026, 10, 20, 12, 0, 0);
	const eventAt = new Date(now + 3 * 3600000).toISOString();
	assert.equal(routeError({ panel: 'calendar', observerPlanet: 'Mars' }), '');
	assert.equal(normalizeRoute({ panel: 'calendar', observerPlanet: 'Earth' }).observerPlanet, undefined);
	assert.equal(normalizeRoute({ panel: 'calendar', observerPlanet: 'Mars' }).observerPlanet, 'Mars');

	const earthRem = validateReminder({
		title: '星象仪 · 金星东大距',
		content: '地球视角',
		eventAt,
		eventId: 'ev-1',
		kind: 'planetary-event',
		target: 'Venus',
		panel: 'calendar'
	}, now);
	const marsRem = validateReminder({
		title: '星象仪 · 【火星】地球东大距',
		content: '火星视角',
		eventAt,
		eventId: 'ev-1',
		kind: 'planetary-event',
		target: 'Earth',
		panel: 'calendar',
		observerPlanet: 'Mars'
	}, now);
	assert.equal(earthRem.ok, true);
	assert.equal(marsRem.ok, true);
	assert.equal(earthRem.value?.route.observerPlanet, undefined);
	assert.equal(marsRem.value?.route.observerPlanet, 'Mars');
	assert.notEqual(earthRem.value?.eventKey, marsRem.value?.eventKey);
});

test('48-hour lightweight timeline snapshot builds and interpolates offline live sky state for Mars and Earth', () => {
	const t0 = Date.UTC(2026, 10, 20, 12, 0, 0);
	const tonight = {
		date: '2026-11-20',
		observer: {
			planet: 'Mars',
			planetZh: '火星',
			hasAtmosphere: true,
			atmosphereProfile: 'mars',
			solarDayHours: 24.66,
			isEarth: false
		},
		companion: {
			name: '火卫一',
			englishName: 'Phobos',
			role: 'moon',
			phaseName: '盈凸火卫一',
			illumination: 72,
			altitude: 24.5
		},
		sunCycle: {
			sunAltitude: 32.0,
			isDaytime: true,
			solarDayHours: 24.66,
			nextSunEventType: 'sunset',
			nextSunEventText: '2026-11-20T17:45:00'
		},
		planets: [{ name: '地球', visible: true }],
		meteorShowers: [],
		satellites: { enabled: false, count: 0 },
		timeline48h: [
			{ at: t0, sunAlt: 30.0, skyHexTop: '#A0684A', skyHexHorizon: '#E09C68', companionAlt: 20.0, companionIllum: 70.0 },
			{ at: t0 + 2 * 3600000, sunAlt: 10.0, skyHexTop: '#604850', skyHexHorizon: '#60A0F0', companionAlt: 40.0, companionIllum: 80.0 },
			{ at: t0 + 48 * 3600000, sunAlt: 28.0, skyHexTop: '#A0684A', skyHexHorizon: '#E09C68', companionAlt: 15.0, companionIllum: 75.0 }
		]
	};
	const card = buildAstronomyCard(tonight, t0);
	assert.equal(card.observerPlanet, 'Mars');
	assert.equal(card.observerPlanetName, '火星');
	assert.equal(card.atmosphereProfile, 'mars');
	assert.equal(card.meteorSummary, '仅地球适用');
	assert.equal(card.satelliteSummary, '仅地球适用');
	assert.match(card.summary, /火星 · 日落 17:45/);

	const timelineJson = buildTimeline48hSnapshot(tonight, t0);
	assert.ok(timelineJson.length > 0);
	// Interpolate 1 hour into the 2-hour window (midpoint!)
	const mid = interpolateTimeline48h(timelineJson, t0 + 3600000);
	assert.ok(mid && mid.valid);
	assert.equal(mid.sunAlt, 20.0);
	assert.equal(mid.companionAlt, 30.0);
	assert.equal(mid.companionIllum, 75.0);
	assert.equal(mid.skyHexTop, '#80584D');

	// Apply live 48h timeline 10 hours later (even beyond 6h legacy staleness!)
	const refreshed = applyTimeline48hToCard({ ...card }, timelineJson, t0 + 3600000);
	assert.equal(refreshed.dataStatus, '48h 离线星历');
	assert.equal(refreshed.sunAlt, '20.0');
	assert.equal(refreshed.skyHexTop, '#80584D');
	assert.equal(refreshed.moonSummary, '75% 照明');

	// Beyond 48h + 15min grace window returns undefined
	assert.equal(interpolateTimeline48h(timelineJson, t0 + 49 * 3600000), undefined);
});
