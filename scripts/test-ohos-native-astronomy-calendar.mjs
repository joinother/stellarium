import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = relative => fs.readFileSync(new URL(`../${relative}`, import.meta.url), 'utf8');
const native = read('src/StelMainView.cpp');
const specific = read('src/core/modules/SpecificTimeMgr.cpp');
const planet = read('src/core/modules/Planet.cpp');

function functionBody(source, marker) {
  const declaration = source.indexOf(marker);
  assert.notEqual(declaration, -1, marker);
  const start = source.indexOf('{', declaration);
  let depth = 0;
  for (let index = start; index < source.length; index++) {
    if (source[index] === '{') depth++;
    if (source[index] === '}' && --depth === 0) return source.slice(start, index + 1);
  }
  assert.fail(`unclosed ${marker}`);
}

const calendar = functionBody(native, 'static QJsonObject ohosAstronomyCalendarEvents(');
const elongation = functionBody(native, 'static double ohosCalendarMoonElongation(');
const search = functionBody(native, 'static bool findOhosCalendarCrossings(');
const alignments = functionBody(native, 'static bool findOhosCalendarAlignments(');
const maxima = functionBody(native, 'static bool findOhosCalendarMaxima(');
const direction = functionBody(native, 'static Vec3d ohosCalendarDirection(');
const longitudeGap = functionBody(native, 'static double ohosCalendarLongitudeGap(');
const meteorActivities = functionBody(native, 'static QJsonArray ohosCalendarMeteorActivities(');
const solarTerm = functionBody(specific, 'double SpecificTimeMgr::getSolarTerm(');
const position = functionBody(planet, 'void Planet::computePosition(const double dateJDE,');
const numericSearch = search
  .replace(/const double /g, 'const ')
  .replace(/\bdouble /g, 'let ')
  .replace(/\bint /g, 'let ')
  .replaceAll('std::isfinite', 'Number.isFinite')
  .replaceAll('std::min', 'Math.min')
  .replaceAll('std::abs', 'Math.abs')
  .replaceAll('crossings.append', 'crossings.push');
const findCrossings = new Function('startJD', 'endJD', 'phaseOffset', 'crossings', numericSearch);
const modulo = value => ((value % 360) + 360) % 360;
const numericAlignments = alignments
  .replace('for (const double direction : {1.0, -1.0})', 'for (const direction of [1.0, -1.0])')
  .replace('[&](double jd)', 'jd =>')
  .replace('StelUtils::fmodpos', 'modulo')
  .replace('std::sort(crossings.begin(), crossings.end())', 'crossings.sort((left, right) => left - right)');
const findAlignments = new Function('findOhosCalendarCrossings', 'modulo',
  `return (startJD, endJD, longitudeOffset, crossings) => ${numericAlignments}`)(findCrossings, modulo);
const numericMaxima = maxima
  .replace(/const double /g, 'const ')
  .replace(/\bdouble /g, 'let ')
  .replace(/\bint /g, 'let ')
  .replaceAll('std::isfinite', 'Number.isFinite')
  .replaceAll('std::abs', 'Math.abs')
  .replaceAll('maxima.append', 'maxima.push');
const findMaxima = new Function('startJD', 'endJD', 'separation', 'maxima', numericMaxima);
const meteorSelection = meteorActivities
  .replace('QJsonObject generic;', 'let generic = {};')
  .replace(/QJsonArray (\w+);/g, 'const $1 = [];')
  .replace(/for \(const QJsonValue& value : (\w+)\)/g, 'for (const value of $1)')
  .replace(/const QJsonObject (\w+) = value.toObject\(\);/g, 'const $1 = value;')
  .replace('const QString activityYear = activity.value("year").toVariant().toString();', 'const activityYear = String(activity.year);')
  .replace('QString::number(year)', 'String(year)')
  .replace('annual.isEmpty()', 'annual.length === 0')
  .replace('!generic.isEmpty()', 'Object.keys(generic).length > 0')
  .replace('QJsonObject activity = generic;', 'const activity = { ...generic };')
  .replace('for (auto field = annualData.begin(); field != annualData.end(); ++field)', 'for (const [fieldKey, fieldValue] of Object.entries(annualData))')
  .replaceAll('field.key()', 'fieldKey')
  .replace('field.value().toDouble()', '(Number(fieldValue) || 0)')
  .replaceAll('field.value()', 'fieldValue')
  .replace('generic.contains("peak")', 'Object.hasOwn(generic, "peak")')
  .replaceAll('.append(', '.push(');
const selectMeteorActivities = new Function('activities', 'year', meteorSelection);

test('the actual native crossing kernel finds all four ordered lunar phases', () => {
  const period = 29.530588853;
  const newMoon = 2460987.78125;
  const start = newMoon - 3;
  const end = start + 31;
  const events = [];
  for (let phase = 0; phase < 4; phase++) {
    const roots = [];
    assert.equal(findCrossings(start, end, jd => modulo((jd - newMoon) * 360 / period - phase * 90), roots), true);
    for (const jd of roots) events.push({ phase, jd });
  }
  events.sort((left, right) => left.jd - right.jd);
  assert.deepEqual(events.map(event => event.phase), [0, 1, 2, 3]);
  for (const event of events) assert.ok(Math.abs(event.jd - (newMoon + event.phase * period / 4)) < 1e-8);
});

test('half-open month boundaries include start, exclude end, and do not duplicate adjacent months', () => {
  const roots = [];
  const offset = jd => modulo((jd - 2460000.5) * 12);
  assert.equal(findCrossings(2460000.5, 2460030.5, offset, roots), true);
  assert.deepEqual(roots, [2460000.5]);
  const next = [];
  findCrossings(2460030.5, 2460060.5, offset, next);
  assert.deepEqual(next, [2460030.5]);
});

test('crossing search handles nonlinear speed, a partial final step, and two same-kind events', () => {
  const start = 1000.123;
  const roots = [];
  const first = start + 0.01;
  const period = 29.53;
  const end = first + period + 0.01;
  const longitude = jd => {
    const angle = (jd - first) * 2 * Math.PI / period;
    return modulo(angle * 180 / Math.PI + 4 * Math.sin(angle));
  };
  assert.equal(findCrossings(start, end, longitude, roots), true);
  assert.equal(roots.length, 2);
  assert.ok(Math.abs(roots[0] - first) < 1e-8);
  assert.ok(Math.abs(roots[1] - first - period) < 1e-8);
});

test('invalid ephemeris results fail explicitly including inside refinement', () => {
  assert.equal(findCrossings(0, 31, () => NaN, []), false);
  assert.equal(findCrossings(0, 31, jd => jd > 3 ? Infinity : modulo(jd * 12), []), false);
  assert.equal(findCrossings(0, 31, jd => Number.isInteger(jd * 4) ? modulo((jd - 0.1) * 12) : NaN, []), false);
});

test('planetary alignments cover direct and retrograde crossings without false opposite-longitude events', () => {
  for (const speed of [12, -12]) {
    const roots = [];
    assert.equal(findAlignments(1000, 1031, jd => (jd - 1002) * speed, roots), true);
    assert.equal(roots.length, 1);
    assert.ok(Math.abs(roots[0] - 1002) < 1e-8);
  }
  const roots = [];
  assert.equal(findAlignments(0, 31, jd => (jd - 4) * (jd - 14) * (jd - 24) / 100, roots), true);
  assert.equal(roots.length, 3, 'retrograde loop may yield three distinct conjunctions');
  for (let index = 0; index < roots.length; index++) assert.ok(Math.abs(roots[index] - [4, 14, 24][index]) < 1e-8);
  const boundary = [];
  findAlignments(1000, 1030, jd => -(jd - 1000) * 12, boundary);
  assert.deepEqual(boundary, [1000]);
  assert.equal(findAlignments(0, 31, () => NaN, []), false);
});

test('greatest elongation search refines true angular maxima and respects month edges', () => {
  const roots = [];
  assert.equal(findMaxima(1000, 1031.13, jd => Math.cos((jd - 1002.12345) * Math.PI / 10), roots), true);
  assert.equal(roots.length, 2);
  assert.ok(Math.abs(roots[0] - 1002.12345) < 1e-6);
  assert.ok(Math.abs(roots[1] - 1022.12345) < 1e-6);
  const boundary = [];
  findMaxima(0, 20, jd => Math.cos(jd * Math.PI / 10), boundary);
  assert.deepEqual(boundary, [0]);
  const nearEnd = [];
  findMaxima(0, 30.13, jd => -((jd - 30.12) ** 2), nearEnd);
  assert.equal(nearEnd.length, 1);
  assert.ok(Math.abs(nearEnd[0] - 30.12) < 1e-7);
});

test('greatest elongation search rejects nonfinite samples and emits no monotonic or flat extrema', () => {
  for (const value of [() => 4, jd => jd, jd => -jd]) {
    const roots = [];
    assert.equal(findMaxima(0, 31, value, roots), true);
    assert.deepEqual(roots, []);
  }
  assert.equal(findMaxima(0, 31, () => NaN, []), false);
  assert.equal(findMaxima(0, 31, jd => jd > 10 ? Infinity : jd, []), false);
  assert.equal(findMaxima(0, 31, jd => Number.isInteger(jd * 2) ? -((jd - 3) ** 2) : NaN, []), false);
});

test('meteor peaks use bundled J2000 catalog longitudes with annual inheritance and no invented day-of-year', () => {
  const catalog = JSON.parse(read('plugins/MeteorShowers/resources/MeteorShowers.json'));
  const showerHeader = read('plugins/MeteorShowers/src/MeteorShower.hpp');
  assert.match(showerHeader, /Peak solar longitude \(J2000\)/);
  for (const [code, peak] of Object.entries({ QUA: 283.15, PER: 140, LEO: 235.27, GEM: 262.2 })) {
    assert.equal(catalog.showers[code].activity.find(entry => entry.year === 'generic').peak, peak);
  }
  assert.equal(catalog.showers.LEO.activity.find(entry => entry.year === '2002').peak, 236.898);
  assert.equal(catalog.showers.GEM.activity.find(entry => entry.year === '2024').peak, undefined);
  assert.equal(selectMeteorActivities(catalog.showers.GEM.activity, 2024)[0].peak, 262.2);
  assert.equal(selectMeteorActivities(catalog.showers.LEO.activity, 2002)[0].peak, 236.898);
  assert.equal(selectMeteorActivities(catalog.showers.LEO.activity, 2026)[0].peak, 235.27);
  assert.equal(selectMeteorActivities(catalog.showers.LEO.activity, 2026)[0].year, 'generic');
  assert.match(meteorActivities, /activityYear == QString::number\(year\)/);
  assert.match(meteorActivities, /QJsonObject activity = generic/);
  assert.match(meteorActivities, /activity\[field.key\(\)\] = field.value\(\)/);
  assert.match(calendar, /QFile showerCatalog\(":\/MeteorShowers\/MeteorShowers.json"\)/);
  assert.match(calendar, /shower.key\(\) == "ANT"/);
  assert.match(calendar, /meteorSolarLongitude\(jd\) - peak/);
  assert.match(calendar, /event\["timingQuality"\] = "catalog-estimate"/);
  assert.match(calendar, /event\["longitudeFrame"\] = "J2000"/);
  assert.doesNotMatch(calendar, /JDfromSolarLongitude|searchEvents\(|getStatus\(|addDays\(/);
});

test('meteor activity selection preserves multiple annual peaks and never leaks another year', () => {
  const activities = [{ year: 'generic', peak: 12 }, { year: '2026', peak: 14 },
    { year: '2026', peak: 15 }, { year: '2025', peak: 18 }];
  assert.deepEqual(selectMeteorActivities(activities, 2026).map(entry => entry.peak), [14, 15]);
  assert.deepEqual(selectMeteorActivities(activities, 2027), [{ year: 'generic', peak: 12 }]);
  assert.deepEqual(selectMeteorActivities([{ year: '2025', peak: 18 }], 2026), []);
  assert.deepEqual(selectMeteorActivities([{ year: '2026', peak: 0 }], 2026), [{ year: '2026', peak: 0 }]);
  assert.deepEqual(selectMeteorActivities([{ year: 'generic', peak: 12 }, { year: '2026', peak: 0 }], 2026), [{ year: '2026', peak: 12 }]);
  assert.equal(activities[0].peak, 12, 'merging annual overrides must not mutate the catalog');
});

test('calendar request strictly validates month and optional paired local UTC boundaries', () => {
  assert.ok(calendar.includes('\\\\A[0-9]{4}-[0-9]{2}\\\\z'));
  assert.match(calendar, /!document.isObject\(\)/);
  for (const field of ['requestedYear', 'requestedMonth']) {
    assert.ok(calendar.includes(`std::floor(${field}) != ${field}`));
    assert.ok(calendar.includes(`!std::isfinite(${field})`));
  }
  assert.match(calendar, /year < 1 \|\| year > 3000 \|\| month < 1 \|\| month > 12/);
  assert.match(calendar, /QDate firstDay\(year, month, 1\)/);
  assert.match(calendar, /firstDay.addMonths\(1\).toJulianDay\(\)/);
  assert.match(calendar, /!options.value\("startJD"\).isDouble\(\) \|\| !options.value\("endJD"\).isDouble\(\)/);
  assert.match(calendar, /std::abs\(startJD - monthStartJD\) > 2.0/);
  assert.match(calendar, /std::abs\(endJD - monthEndJD\) > 2.0/);
  assert.match(calendar, /endJD - startJD < 27.0 \|\| endJD - startJD > 33.0/);
  assert.ok(calendar.indexOf('range must describe') < calendar.indexOf('GETSTELMODULE'));
});

test('native route and all calculation helpers never alter shared simulation state', () => {
  assert.match(native, /if \(commandName == "getAstronomyCalendarEvents"\)\s+return ohosAstronomyCalendarEvents\(core, arg\);/);
  for (const body of [calendar, elongation, solarTerm, position, search, alignments, maxima, direction, longitudeGap, meteorActivities]) {
    assert.doesNotMatch(body, /(?:core|objectMgr|movementMgr)->(?:set|update|move|select|unSelect)/);
    assert.doesNotMatch(body, /getRTSTime|getInfoMap|getAltAzPos|StellariumOhos_command|setTopocentric/);
  }
  assert.doesNotMatch(calendar, /getJD\(\)|getJDE\(\)|getUTCOffset\(|getCurrentLocation|getCurrentPlanet/);
  assert.match(elongation, /earth->computePosition\(jde, earthPosition, earthVelocity\)/);
  assert.match(elongation, /moon->computePosition\(jde - lightTime, moonPosition, moonVelocity\)/);
  assert.doesNotMatch(position, /lastJDE\s*=|eclipticPos\s*=|aberrationPush\s*=/);
  assert.match(position, /coordFunc\(dateJDE, &eclPosition\[0\], &eclVelocity\[0\], orbitPtr\)/);
});

test('term reuse and epoch conversion return UT once without subtracting DeltaT twice', () => {
  assert.match(calendar, /specificTimeMgr->getSolarTerm\(eventYear, index\)/);
  assert.match(solarTerm, /const double jde = jd \+ core->computeDeltaT\(jd\) \/ 86400.0/);
  assert.match(solarTerm, /return \(lowJD \+ highJD\) \* 0.5/);
  assert.doesNotMatch(calendar, /eventJD\s*[-+]\s*core->computeDeltaT/);
  assert.match(elongation, /jd \+ core->computeDeltaT\(jd\) \/ 86400.0/);
  assert.match(elongation, /getPrecessionAnglesVondrak\(jde,/);
  assert.match(elongation, /20.4898 \/ \(3600.0 \* earthPosition.norm\(\)\)/);
  assert.match(calendar, /std::round\(\(eventJD - 2440587.5\) \* 86400000.0\)/);
  assert.match(calendar, /event\["timeScale"\] = "UT"/);
});

test('schema agrees with calendar integration and makes no unsupported visibility claims', () => {
  for (const field of ['id', 'kind', 'index', 'title', 'titleEn', 'jd', 'at', 'body', 'target', 'panel', 'tab', 'phase']) {
    assert.ok(calendar.includes(`event["${field}"]`), field);
  }
  assert.match(calendar, /phase.isEmpty\(\) \? 8 : 6/);
  assert.match(calendar, /"new-moon", "first-quarter", "full-moon", "last-quarter"/);
  assert.match(calendar, /QJsonArray\{"solar-term", "moon-phase", "meteor-peak", "planetary-event"\}/);
  assert.match(calendar, /QJsonArray\{"eclipse", "satellite-pass"\}/);
  assert.doesNotMatch(calendar, /event\["(?:altitude|azimuth|rise|set|visible|illumination)"\]/);
  assert.match(calendar, /eventJD >= startJD && eventJD < endJD/);
  assert.match(calendar, /std::sort\(events.begin\(\), events.end\(\)/);
});

test('planetary events use epoch-local vectors, light time and aberration without importing mutable phenomena routines', () => {
  assert.match(direction, /earth->computePosition\(jde, earthPosition, earthVelocity\)/);
  assert.match(direction, /body->computePosition\(jde - lightTime, bodyPosition, bodyVelocity\)/);
  assert.match(direction, /bodyPosition - earthPosition \+ earthVelocity \* lightTime/);
  assert.match(direction, /iteration < 2/);
  assert.match(longitudeGap, /getPrecessionAnglesVondrak\(jde,/);
  assert.doesNotMatch(calendar, /findNextOpposition|findClosestApproach|findGreatestElongationApproach|calcSolarEclipse|generateEclipseMap/);
  assert.match(calendar, /angle == 180 && planetIndex < 2/);
  assert.match(calendar, /if \(planetIndex < 2\)\s*\{\s*QList<double> maxima/);
  for (const field of ['subtype', 'primary', 'secondary', 'direction', 'alignment', 'separationDegrees']) {
    assert.ok(calendar.includes(`event["${field}"]`), field);
  }
  assert.match(calendar, /event\["direction"\] = east \? "east" : "west"/);
});
