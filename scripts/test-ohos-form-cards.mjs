import fs from 'node:fs'
import path from 'node:path'
import assert from 'node:assert/strict'
import {
  SUPPORTED_EDIT_PLANETS,
  applyAnalyticalTimePreview,
  applyCardConfigToSnapshot,
  applySolarShowcaseProjection,
  applyTimeline48hToCard,
  buildAstronomyCard,
  buildFallbackCardForPlanet,
  buildMiniPhaseStrip,
  buildTimeline48hSnapshot,
  clampOrreryDayOffset,
  clampTimeOffsetHours,
  clockToTodayJd,
  computeDaylightDuration,
  computeGoldenHourClock,
  computeOverflowArea,
  computePreviewPhaseForDay,
  computeSolarArcProgress,
  defaultCardConfig,
  estimateHeliocentricLongitudes,
  estimateMoonPhaseAt,
  estimateSolarTermZh,
  extractInverseTextColor,
  focusTargetForCard,
  formatCountdownZh,
  formatOrreryOffsetBadge,
  formatPlanetDisplayList,
  formatPreviewTimeBadge,
  isLightTextColor,
  moonSilhouette,
  nextCyclePlanet,
  normalizeAstronomyCard,
  normalizeCardConfig,
  offsetDaysToJd,
  offsetHoursToJd,
  orbKeyForBody,
  parseHeliocentricPlanets,
  parseRemindedEventIds,
  planetSymbol,
  planetZhName,
  projectSolarSystemOrrery,
  routePlanetForCard,
  routeTargetForCard,
  sliceUpcomingEventPage,
  solarStageFromAltitude
} from '../harmonyos/ets-source/form/AstronomyCardData.ts'

const root = process.cwd()
const formConfigPath = path.join(root, 'harmonyos/resources/base/profile/form_config.json')
const mainPagesPath = path.join(root, 'harmonyos/resources/base/profile/main_pages.json')
const moduleJsonPath = path.join(root, 'harmonyos/module.json5')
const syncScriptPath = path.join(root, 'scripts/sync-ohos-build-sources.sh')
const formAbilityPath = path.join(root, 'harmonyos/ets-source/form/SkyInstrumentFormAbility.ets')
const formEditAbilityPath = path.join(root, 'harmonyos/ets-source/form/SkyInstrumentFormEditAbility.ets')
const liveFormAbilityPath = path.join(root, 'harmonyos/ets-source/form/SkyInstrumentLiveFormAbility.ets')
const mediaDir = path.join(root, 'harmonyos/resources/base/media')

// 1. Validate form_config.json & new 3-card family
const formConfig = JSON.parse(fs.readFileSync(formConfigPath, 'utf8'))
const forms = Array.isArray(formConfig.forms) ? formConfig.forms : []
const expectedForms = [
  { name: 'sky_window_card', source: 'SkyWindowCard.ets', defaultDim: '2*2', panel: "panel: 'sky'", resizable: true, transparent: false },
  { name: 'companion_arc_card', source: 'CompanionArcCard.ets', defaultDim: '2*2', panel: "panel: 'sky'", resizable: true, transparent: false },
  { name: 'solar_arc_card', source: 'SolarArcCard.ets', defaultDim: '2*4', panel: "panel: 'sky'", resizable: true, transparent: false },
  { name: 'celestial_events_card', source: 'CelestialEventsCard.ets', defaultDim: '2*4', panel: "panel: 'calendar'", resizable: true, transparent: false },
  { name: 'floating_orb_card', source: 'FloatingOrbCard.ets', defaultDim: '2*2', panel: "panel: 'sky'", resizable: false, transparent: true },
  { name: 'solar_system_card', source: 'SolarSystemCard.ets', defaultDim: '2*4', panel: "panel: 'astro'", resizable: true, transparent: false }
]

assert.equal(forms.length, expectedForms.length, 'must expose the 6 redesigned astronomical widget cards (5+1 transparent)')
assert.equal(forms.filter((f) => f.isDefault === true).length, 1, 'must have exactly one default card')

const syncScript = fs.readFileSync(syncScriptPath, 'utf8')
assert.ok(syncScript.includes('harmonyos/ets-source'), 'sync script must mirror ets-source tree')

const baseStrings = JSON.parse(fs.readFileSync(path.join(root, 'harmonyos/resources/base/element/string.json'), 'utf8')).string
const zhStrings = JSON.parse(fs.readFileSync(path.join(root, 'harmonyos/resources/zh_CN/element/string.json'), 'utf8')).string
const enStrings = JSON.parse(fs.readFileSync(path.join(root, 'harmonyos/resources/en_US/element/string.json'), 'utf8')).string
const hasStringKey = (arr, key) => Array.isArray(arr) && arr.some((item) => item.name === key && typeof item.value === 'string' && item.value.trim().length > 0)

for (const expected of expectedForms) {
  const form = forms.find((f) => f.name === expected.name)
  assert.ok(form, `missing form config: ${expected.name}`)
  assert.ok(typeof form.displayName === 'string' && form.displayName.startsWith('$string:'), `${expected.name} displayName must use $string: resource reference`)
  assert.ok(typeof form.description === 'string' && form.description.startsWith('$string:'), `${expected.name} description must use $string: resource reference`)
  const nameKey = form.displayName.slice('$string:'.length)
  const descKey = form.description.slice('$string:'.length)
  for (const [loc, list] of [['base', baseStrings], ['zh_CN', zhStrings], ['en_US', enStrings]]) {
    assert.ok(hasStringKey(list, nameKey), `${loc} string.json missing ${nameKey}`)
    assert.ok(hasStringKey(list, descKey), `${loc} string.json missing ${descKey}`)
  }
  assert.equal(form.src, `./ets/form/${expected.source}`, `mismatched src for ${expected.name}`)
  assert.equal(form.defaultDimension, expected.defaultDim, `mismatched defaultDimension for ${expected.name}`)
  if (expected.resizable) {
    assert.equal(form.resizable, true, `${expected.name} must support API 20 drag resize`)
  }
  if (expected.transparent) {
    assert.equal(form.transparencyEnabled, true, `${expected.name} must enable API 22 transparent backplate`)
  }
  assert.equal(form.formConfigAbility, 'ability://SkyInstrumentFormEditAbility', `${expected.name} must wire API 18 semi-modal edit`)
  assert.equal(form.sceneAnimationParams?.abilityName, 'SkyInstrumentLiveFormAbility', `${expected.name} must wire API 20 overflow liveForm`)

  const cardPath = path.join(root, 'harmonyos/ets-source/form', expected.source)
  assert.ok(fs.existsSync(cardPath), `missing card source: ${cardPath}`)
  const cardSource = fs.readFileSync(cardPath, 'utf8')
  assert.ok(cardSource.includes(expected.panel), `${expected.name} must deep-link to ${expected.panel}`)
  assert.ok(
    cardSource.includes('observerPlanet: this.observerPlanet') || cardSource.includes('observerPlanet: routePlanetForCard(this.observerPlanet)'),
    `${expected.name} must carry observerPlanet on router action`
  )
  assert.ok(cardSource.includes("message: 'requestOverflow'"), `${expected.name} must support API 20 overflow trigger`)
  assert.ok(cardSource.includes('@LocalStorageProp('), `${expected.name} must bind form data via @LocalStorageProp`)
  assert.ok(!cardSource.includes('AstronomyCardSurface'), `${expected.name} must not reference deprecated AstronomyCardSurface`)
}

// Legacy grey-box form files must stay removed
for (const legacy of ['AstronomyCardSurface.ets', 'SkyInstrumentCard.ets', 'SkyInstrumentCompactCard.ets']) {
  assert.ok(!fs.existsSync(path.join(root, 'harmonyos/ets-source/form', legacy)), `deprecated legacy file still exists: ${legacy}`)
}

// 2. Validate module.json5 extensionAbilities & main_pages.json
const moduleJson = fs.readFileSync(moduleJsonPath, 'utf8')
for (const token of [
  '"name": "SkyInstrumentFormAbility"',
  '"type": "form"',
  '"name": "SkyInstrumentFormEditAbility"',
  '"type": "formEdit"',
  '"name": "SkyInstrumentLiveFormAbility"',
  '"type": "liveForm"'
]) {
  assert.ok(moduleJson.includes(token), `module.json5 missing extension declaration: ${token}`)
}

const mainPages = JSON.parse(fs.readFileSync(mainPagesPath, 'utf8'))
assert.ok(mainPages.src.includes('form/SkyFormEditPage'), 'main_pages.json must register form/SkyFormEditPage')
assert.ok(mainPages.src.includes('form/SkyLiveFormPage'), 'main_pages.json must register form/SkyLiveFormPage')

// 3. Validate abilities & 3D planet/moon orb assets
const formAbilitySrc = fs.readFileSync(formAbilityPath, 'utf8')
assert.ok(formAbilitySrc.includes('ohos.extra.param.key.edit_form_id'), 'onAddForm must sync preview card from edit_form_id')
assert.ok(formAbilitySrc.includes('HOST_BG_INVERSE_COLOR_KEY'), 'FormAbility must read HOST_BG_INVERSE_COLOR_KEY for transparent backplate text color')
assert.ok(formAbilitySrc.includes('formProvider.requestOverflow'), 'onFormEvent must invoke formProvider.requestOverflow')
assert.ok(formAbilitySrc.includes('formProvider.getFormRect'), 'onFormEvent must query formProvider.getFormRect')
assert.ok(formAbilitySrc.includes("eventType === 'stepTimeOffset'"), 'FormAbility must handle 48h time-scrubbing dial')
assert.ok(formAbilitySrc.includes("eventType === 'stepOrreryDays'"), 'FormAbility must handle Solar System orrery day scrubbing')
assert.ok(formAbilitySrc.includes("eventType === 'toggleOrreryZoom'"), 'FormAbility must handle Solar System inner/full zoom toggle')
assert.ok(formAbilitySrc.includes("eventType === 'cyclePlanet'"), 'FormAbility must handle quick planet carousel')
assert.ok(formAbilitySrc.includes("eventType === 'toggleEventReminder'"), 'FormAbility must handle desktop reminder bell')
assert.ok(formAbilitySrc.includes('reminderAgentManager.publishReminder'), 'FormAbility must schedule background agent reminders')
assert.ok(formAbilitySrc.includes('reminderRouteUri('), 'FormAbility reminders must encode full deep-link route URI')

const liveFormPageSrc = fs.readFileSync(path.join(root, 'harmonyos/ets-source/form/SkyLiveFormPage.ets'), 'utf8')
assert.ok(liveFormPageSrc.includes('cycleFloatingPlanetInPlace'), 'SkyLiveFormPage must allow in-overflow planet switching for FloatingOrbCard')

const formEditSrc = fs.readFileSync(formEditAbilityPath, 'utf8')
assert.ok(formEditSrc.includes('FormEditExtensionAbility'), 'must extend FormEditExtensionAbility')
assert.ok(formEditSrc.includes('previewCardId'), 'must forward previewCardId to edit page')

const liveFormSrc = fs.readFileSync(liveFormAbilityPath, 'utf8')
assert.ok(liveFormSrc.includes('LiveFormExtensionAbility'), 'must extend LiveFormExtensionAbility')
assert.ok(liveFormSrc.includes('onLiveFormCreate'), 'must implement onLiveFormCreate')

for (const orb of ['sun', 'moon', 'earth', 'mars', 'saturn', 'jupiter', 'titan', 'venus', 'neptune', 'uranus', 'mercury', 'pluto']) {
  const orbFile = path.join(mediaDir, `widget_orb_${orb}.png`)
  assert.ok(fs.existsSync(orbFile) && fs.statSync(orbFile).size > 4096, `missing or empty 3D orb texture: widget_orb_${orb}.png`)
}
for (let i = 0; i < 16; i++) {
  const maskFile = path.join(mediaDir, `widget_phase_${String(i).padStart(2, '0')}.png`)
  assert.ok(fs.existsSync(maskFile) && fs.statSync(maskFile).size > 100, `missing 3D phase mask: ${maskFile}`)
}

// 4. Validate QAbility & MainWindowNativeNode card route & publisher wiring
const qAbilitySrc = fs.readFileSync(path.join(root, 'harmonyos/ets-source/qability/QAbility.ets'), 'utf8')
assert.ok(qAbilitySrc.includes("'observerPlanet'"), 'QAbility card route must whitelist observerPlanet')
assert.ok(qAbilitySrc.includes("'positionMode'"), 'QAbility card route must whitelist positionMode for heliocentric deep-link')
const mainWindowSrc = fs.readFileSync(path.join(root, 'harmonyos/ets-source/pages/MainWindowNativeNode.ets'), 'utf8')
for (const token of ['publishAstronomyCard', 'persistAlmanacCardSnapshot']) {
  assert.ok(mainWindowSrc.includes(token), `MainWindowNativeNode missing card hook: ${token}`)
}

// 5. Data model, multi-instance config, 48h timeline, and overflow bounds unit tests
const now = Date.UTC(2026, 10, 20, 12, 0, 0)
const earthSnapshot = buildAstronomyCard({
  date: '2026-11-20',
  observer: { planet: 'Earth', planetZh: '地球', isEarth: true, atmosphereProfile: 'earth' },
  moon: { phaseName: '盈凸月', illumination: 79, age: 11.2, rise: '2026-11-20T14:25', set: '2026-11-21T03:18' },
  sun: { darkWindowHours: 10.2, astroTwilightEnd: '2026-11-20T18:32', astroTwilightStart: '2026-11-21T04:44' },
  planets: [
    { name: '木星', englishName: 'Jupiter', visible: true, altitude: 44.5, magnitude: -2.4, rise: '2026-11-20T19:10', set: '2026-11-21T08:15' },
    { name: '土星', englishName: 'Saturn', visible: true, altitude: 28.0, magnitude: 0.7, rise: '2026-11-20T13:40', set: '2026-11-21T01:05' },
    { name: '金星', englishName: 'Venus', visible: false, altitude: -12.0, magnitude: -4.1, rise: '2026-11-21T05:10', set: '2026-11-21T15:20' }
  ],
  meteorShowers: [{ name: '狮子座流星雨', zhr: 15 }],
  satellites: { enabled: true, count: 2915 },
  upcomingEvents: [
    { id: 'ev-full-moon', title: '满月 · 望', kind: 'moon-phase', target: 'Moon', jd: 2461369.0, at: now + 4 * 86400000 },
    { id: 'ev-geminids', title: '双子座流星雨极大', kind: 'meteor', target: 'Gemini', jd: 2461389.0, at: now + 24 * 86400000 }
  ]
}, now)

assert.equal(earthSnapshot.schemaVersion, '4')
assert.equal(earthSnapshot.orbBody, 'moon')
assert.equal(earthSnapshot.planetSummary, '2 颗在地平线上')
assert.equal(earthSnapshot.observationSummary, '10.2 小时暗夜')
assert.equal(earthSnapshot.nextEventTitle, '满月 · 望')
assert.equal(earthSnapshot.nextEventCountdown, '4 天后')
assert.equal(formatPlanetDisplayList(earthSnapshot.visiblePlanetsJson, '', 'name'), '木星 · 土星')
assert.equal(formatPlanetDisplayList(earthSnapshot.visiblePlanetsJson, '', 'symbol'), '♃  ♄')
assert.deepEqual(normalizeAstronomyCard(JSON.stringify(earthSnapshot), now), earthSnapshot)
assert.equal(normalizeAstronomyCard(JSON.stringify(earthSnapshot), now + 7 * 3600000).dataStatus, '旧快照')
assert.equal(normalizeAstronomyCard('{bad', now).schemaVersion, '4')

// Multi-instance config normalization & deep theme override
const parsedCfg = normalizeCardConfig(JSON.stringify({ planetMode: 'Mars', themeStyle: 'deep', labelStyle: 'symbol', overflowMode: 'tap' }))
assert.equal(parsedCfg.planetMode, 'Mars')
assert.equal(parsedCfg.themeStyle, 'deep')
assert.equal(parsedCfg.labelStyle, 'symbol')
assert.equal(parsedCfg.overflowMode, 'tap')
assert.equal(normalizeCardConfig('{"planetMode":"InvalidWorld"}').planetMode, 'follow')

const marsFallback = buildFallbackCardForPlanet('Mars', now)
assert.equal(marsFallback.observerPlanet, 'Mars')
assert.equal(marsFallback.orbBody, 'mars')
assert.equal(marsFallback.skyHexHorizon, '#8F5638')
const marsDeep = applyCardConfigToSnapshot(marsFallback, parsedCfg, now)
assert.equal(marsDeep.skyHexTop, '#050811')
assert.equal(marsDeep.cardLabelStyle, 'symbol')

const moonFallback = buildFallbackCardForPlanet('Moon', now)
assert.equal(moonFallback.orbBody, 'earth')
const titanFallback = buildFallbackCardForPlanet('Titan', now)
assert.equal(titanFallback.orbBody, 'saturn')
const moonNativeSnap = buildAstronomyCard({
  date: '2026-11-20',
  observer: { planet: 'Moon', planetZh: '月球', isEarth: false },
  companion: { name: '地球', englishName: 'Earth', role: 'parent-planet', phaseName: '残地', illumination: 25 }
}, now)
assert.equal(moonNativeSnap.orbBody, 'earth')
const titanNativeSnap = buildAstronomyCard({
  date: '2026-11-20',
  observer: { planet: 'Titan', planetZh: '土卫六', isEarth: false },
  companion: { name: '土星', englishName: 'Saturn', role: 'parent-planet', phaseName: '蛾眉土星', illumination: 30 }
}, now)
assert.equal(titanNativeSnap.orbBody, 'saturn')

// 48h timeline offline interpolation
const tlRaw = buildTimeline48hSnapshot({
  observer: { planet: 'Mars' },
  timeline48h: [
    { at: now, sunAlt: 10, skyHexTop: '#3A231D', skyHexHorizon: '#9C5C38', companionAlt: 20, companionIllum: 50 },
    { at: now + 7200000, sunAlt: -2, skyHexTop: '#161B2E', skyHexHorizon: '#3B5884', companionAlt: 40, companionIllum: 60 }
  ]
}, now)
const liveMars = applyTimeline48hToCard(buildFallbackCardForPlanet('Mars', now), tlRaw, now + 3600000)
assert.equal(liveMars.dataStatus, '48h 离线星历')
assert.equal(liveMars.sunAlt, '4.0')
assert.equal(liveMars.companionAlt, '30.0')

// API 20 Overflow Rect Compliance across every official Form Kit size (width x height max ratios)
const overflowCases = [
  { w: 158, h: 158, maxWRatio: 1.50, maxHRatio: 1.50, label: '2*2' },
  { w: 332, h: 158, maxWRatio: 1.25, maxHRatio: 1.50, label: '2*4' },
  { w: 332, h: 332, maxWRatio: 1.25, maxHRatio: 1.25, label: '4*4' },
  { w: 158, h: 74, maxWRatio: 1.50, maxHRatio: 2.00, label: '1*2' },
  { w: 332, h: 498, maxWRatio: 1.25, maxHRatio: 1.10, label: '6*4' }
]
for (const c of overflowCases) {
  const area = computeOverflowArea(c.w, c.h)
  assert.ok(area.duration > 0 && area.duration <= 3500, `${c.label} duration exceeds 3500ms`)
  assert.ok(area.left <= 0 && area.top <= 0, `${c.label} overflow must cover card origin`)
  assert.ok(area.left + area.width >= c.w && area.top + area.height >= c.h, `${c.label} overflow must contain full card rect`)
  const maxW = c.w * c.maxWRatio
  const maxH = c.h * c.maxHRatio
  const minLeft = -(maxW - c.w) / 2
  const minTop = -(maxH - c.h) / 2
  assert.ok(area.width <= maxW + 1, `${c.label} width ${area.width} exceeds max ${maxW}`)
  assert.ok(area.height <= maxH + 1, `${c.label} height ${area.height} exceeds max ${maxH}`)
  assert.ok(area.left >= minLeft - 1 && area.left + area.width <= c.w - minLeft + 1, `${c.label} horizontal rect exceeds centered IJKL`)
  assert.ok(area.top >= minTop - 1 && area.top + area.height <= c.h - minTop + 1, `${c.label} vertical rect exceeds centered IJKL`)
}

// Misc helpers
assert.equal(SUPPORTED_EDIT_PLANETS.length, 9)
assert.equal(planetSymbol('Sun'), '☀')
assert.equal(planetZhName('Sun'), '太阳')
assert.equal(orbKeyForBody('Sun'), 'sun')
assert.equal(routePlanetForCard('Sun'), 'Earth')
assert.equal(routeTargetForCard('Sun'), 'Sun')
assert.equal(routePlanetForCard('Mars'), 'Mars')
assert.equal(planetSymbol('Saturn'), '♄')
assert.equal(planetZhName('Titan'), '土卫六')
assert.equal(orbKeyForBody('Phobos'), 'mars')
assert.equal(formatCountdownZh(now + 45 * 60000, now), '45 分钟后')
assert.equal(formatCountdownZh(now + 5 * 3600000, now), '5 小时后')
assert.equal(formatCountdownZh(now + 3 * 86400000, now), '3 天后')
const strip = buildMiniPhaseStrip(11, now)
assert.equal(strip.length, 5)
assert.equal(strip[0].isToday, true)
const est = estimateMoonPhaseAt(now)
assert.ok(est.illumination >= 0 && est.illumination <= 100)
for (const illumination of [0, 25, 50, 75, 100]) {
  assert.ok(!moonSilhouette(112, illumination, 20).includes('NaN'))
}

// Solar telemetry, 24 solar terms, diurnal arc & Sun card projection tests
assert.equal(solarStageFromAltitude(28), '白昼晴光')
assert.equal(solarStageFromAltitude(3), '黄金时刻')
assert.equal(solarStageFromAltitude(-3), '蓝调暮光')
assert.equal(solarStageFromAltitude(-15), '天文暮光')
assert.equal(solarStageFromAltitude(-22), '天文暗夜')
assert.equal(computeDaylightDuration('06:58', '16:59'), '10h 01m')
assert.equal(computeGoldenHourClock('16:59'), '16:21')
const middayProg = computeSolarArcProgress('06:00', '18:00', new Date(2026, 10, 20, 12, 0).getTime(), 35)
assert.ok(middayProg > 0.48 && middayProg < 0.52, `solar noon progress expected ~0.50, got ${middayProg}`)
const termStr = estimateSolarTermZh(now)
assert.ok(termStr.includes('立冬') || termStr.includes('小雪'), `expected late-Nov solar term, got ${termStr}`)
const sunCard = applySolarShowcaseProjection(buildFallbackCardForPlanet('Earth', now), now)
assert.equal(sunCard.observerPlanet, 'Sun')
assert.equal(sunCard.orbBody, 'sun')
assert.ok(sunCard.daylightDuration.includes('h '))
assert.ok(sunCard.solarTermText.length > 0)

// Transparent backplate inverse color parsing & luminance check
assert.equal(extractInverseTextColor({ mTextColor: '#FF181818', mWallpaperType: 1 }), '#FF181818')
assert.equal(extractInverseTextColor('{"mTextColor":"#FFFFFF"}'), '#FFFFFF')
assert.equal(extractInverseTextColor('bad-color'), '')
assert.equal(isLightTextColor('#F5F9FF'), true)
assert.equal(isLightTextColor('#FF181818'), false)

// Interactive widget helpers: planet cycle, 48h time dial, 5-day phase scrubber, reminder state
assert.equal(nextCyclePlanet('Earth'), 'Sun')
assert.equal(nextCyclePlanet('Sun'), 'Mars')
assert.equal(nextCyclePlanet('Mars'), 'Moon')
assert.equal(nextCyclePlanet('Neptune'), 'Earth')
assert.equal(clampTimeOffsetHours(-4), 0)
assert.equal(clampTimeOffsetHours(12), 12)
assert.equal(clampTimeOffsetHours(99), 44)
assert.ok(formatPreviewTimeBadge(8, now + 8 * 3600000).startsWith('+8h · '))
assert.equal(formatPreviewTimeBadge(0, now), '')
const day3Moon = computePreviewPhaseForDay(11.0, 3, false)
assert.ok(day3Moon.illumination > 90 && day3Moon.phaseName === '满月')
const day3Earth = computePreviewPhaseForDay(11.0, 3, true)
assert.equal(day3Earth.phaseName, '满地')
assert.deepEqual(parseRemindedEventIds('["ev-1","ev-2"]'), ['ev-1', 'ev-2'])
assert.deepEqual(parseRemindedEventIds('invalid'), [])

// Offline analytical time-scrubbing must vary sunAlt & sky gradient across +4h / +8h on unsynced worlds
const jup4h = applyAnalyticalTimePreview(buildFallbackCardForPlanet('Jupiter', now + 4 * 3600000), 'Jupiter', now + 4 * 3600000, 4)
const jup8h = applyAnalyticalTimePreview(buildFallbackCardForPlanet('Jupiter', now + 8 * 3600000), 'Jupiter', now + 8 * 3600000, 8)
assert.notEqual(jup4h.sunAlt, jup8h.sunAlt, 'Jupiter +4h and +8h analytical sunAlt must advance with solar rotation')
assert.ok(JSON.parse(jup4h.visiblePlanetsJson).length >= 2, 'Jupiter preset must provide fallback visible planets')

// Upcoming event pagination: Hero must NEVER duplicate into subsequent list; pager only appears when remaining > pageSize
const sevenEvents = Array.from({ length: 7 }, (_, i) => ({
  id: `ev-${i}`, title: `天象 ${i + 1}`, kind: 'planet', target: 'Mars', at: now + (i + 1) * 86400000, jd: 2461370 + i
}))
const p0 = sliceUpcomingEventPage(sevenEvents, 0, 2)
assert.equal(p0.hero?.id, 'ev-0')
assert.deepEqual(p0.items.map((e) => e.id), ['ev-1', 'ev-2'], 'page 0 must start from event #2 without duplicating Hero')
assert.equal(p0.pageCount, 3)
const p1 = sliceUpcomingEventPage(sevenEvents, 1, 2)
assert.deepEqual(p1.items.map((e) => e.id), ['ev-3', 'ev-4'], 'page 1 must reveal unseen events #4 and #5')
const p2 = sliceUpcomingEventPage(sevenEvents, 2, 2)
assert.deepEqual(p2.items.map((e) => e.id), ['ev-5', 'ev-6'], 'page 2 must reveal unseen events #6 and #7')
const pSmall = sliceUpcomingEventPage(sevenEvents.slice(0, 3), 0, 2)
assert.equal(pSmall.pageCount, 1, 'when remaining events fit on one page, pageCount must be 1 so pager hides')

// Context-preserving landing route helpers (time offsets, solar milestones, companion focus)
assert.equal(focusTargetForCard('Earth', 'Moon', 'moon'), 'Moon')
assert.equal(focusTargetForCard('Sun', '', 'sun'), 'Sun')
assert.equal(focusTargetForCard('Moon', 'Earth', 'earth'), 'Earth')
assert.equal(focusTargetForCard('Titan', 'Saturn', 'saturn'), 'Saturn')
assert.equal(offsetHoursToJd(now, 0), 0)
assert.ok(offsetHoursToJd(now, 8) > 2460000, 'offsetHoursToJd(+8h) must produce valid future JD')
assert.equal(offsetDaysToJd(now, 0), 0)
assert.ok(offsetDaysToJd(now, 3) > offsetHoursToJd(now, 8), 'offsetDaysToJd(+3d) must exceed +8h JD')
assert.ok(clockToTodayJd('16:55', now) > 2460000, 'clockToTodayJd must produce valid today JD')
assert.equal(clockToTodayJd('—', now), 0)

// 3D Solar System Orrery Keplerian math & Painter's-algorithm Z-ordering tests
const helioNow = estimateHeliocentricLongitudes(now)
assert.equal(helioNow.length, 8, 'must compute all 8 major planets')
const earthNow = helioNow.find((p) => p.id === 'Earth')
assert.ok(earthNow && earthNow.distAU > 0.96 && earthNow.distAU < 1.04, 'Earth heliocentric distance must be ~1 AU')
// Late Nov: Sun is at ~238° geocentric -> Earth is at ~58° heliocentric!
assert.ok(earthNow.lonDeg > 40 && earthNow.lonDeg < 80, `Expected late-Nov Earth heliocentric lon ~58°, got ${earthNow.lonDeg}`)
const helioPlus30 = parseHeliocentricPlanets('[{"id":"Earth","lon":58.2,"distAU":0.99}]', now, 30)
const earthPlus30 = helioPlus30.find((p) => p.id === 'Earth')
assert.ok(earthPlus30 && earthPlus30.lonDeg > 82 && earthPlus30.lonDeg < 95, `Earth +30d should advance ~30°, got ${earthPlus30?.lonDeg}`)
assert.equal(clampOrreryDayOffset(5000), 3650)
assert.equal(clampOrreryDayOffset(-5000), -3650)
assert.ok(formatOrreryOffsetBadge(0, now).startsWith('此刻 · '))
assert.ok(formatOrreryOffsetBadge(365, now + 365 * 86400000).startsWith('+1年 · '))

const planFull = projectSolarSystemOrrery(helioNow, 260, 148, false, 55, 'Saturn')
assert.equal(planFull.orbits.length, 8)
assert.equal(planFull.backNodes.length + planFull.frontNodes.length, 8, 'every planet must be Z-sorted into back or front hemisphere')
assert.ok(planFull.orbits[7].ry < planFull.orbits[7].rx * 0.7, '3D tilted orbit must be compressed vertically by cos(tiltDeg)')
const planInner = projectSolarSystemOrrery(helioNow, 260, 148, true, 0, 'Mars')
assert.equal(planInner.orbits.length, 4, 'inner-only mode must show Mercury..Mars')
assert.ok(Math.abs(planInner.orbits[3].ry - planInner.orbits[3].rx) < 0.5, 'top-down 0° tilt must be circular')

console.log(`HarmonyOS interactive widget contract, transparent backplate, overflow & data tests passed: ${expectedForms.length} cards, 12 3D orbs, ${overflowCases.length} overflow specs`)
