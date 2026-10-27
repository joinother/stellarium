import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = relativePath => fs.readFileSync(new URL(`../${relativePath}`, import.meta.url), 'utf8');
const native = read('src/StelMainView.cpp');
const dialog = read('src/gui/LocationDialog.cpp');
const core = read('src/core/StelCore.cpp');
const landscape = read('src/core/modules/LandscapeMgr.cpp');
const catalog = read('src/StelOhosCommandCatalog.hpp');

function block(source, marker) {
  const markerIndex = source.indexOf(marker);
  assert.notEqual(markerIndex, -1, `missing ${marker}`);
  const start = source.indexOf('{', markerIndex + marker.length);
  let depth = 0;
  for (let index = start; index < source.length; index++) {
    if (source[index] === '{') depth++;
    if (source[index] === '}' && --depth === 0) return source.slice(start, index + 1);
  }
  assert.fail(`unclosed ${marker}`);
}

const command = name => block(native, `if (commandName == "${name}")`);
const switchPlanet = command('setObserverPlanet');
const planetList = command('getObserverPlanetList');
const coordinates = block(native, 'static bool parseOhosLocationCoordinates(');
const targetChanged = block(landscape, 'void LandscapeMgr::onTargetLocationChanged(');
const moveObserver = block(core, 'void StelCore::moveObserverTo(');

test('planet enumeration uses the same unfiltered engine collection as LocationDialog', () => {
  assert.match(block(dialog, 'void LocationDialog::populatePlanetList('), /getAllPlanets\(\)/);
  const enumeration = block(planetList, 'for (const auto& planet : ssys->getAllPlanets())');
  assert.doesNotMatch(enumeration, /\b(?:if|continue|break)\b|\.contains\(/);
  assert.match(enumeration, /list\.append\(name\)/);
  assert.match(enumeration, /observerPlanets\.append\(entry\)/);
  assert.match(planetList, /result\["planets"\] = list/);
  assert.match(planetList, /result\["observerPlanets"\] = observerPlanets/);
});

test('localized names and raw texture names preserve the agreed UI schema', () => {
  assert.match(planetList, /entry\["name"\] = name/);
  assert.match(planetList, /entry\["displayName"\] = planet->getNameI18n\(\)/);
  assert.match(planetList, /entry\["mapTexture"\] = name == "Earth" \? QString\(\) : planet->getTextMapName\(\)/);
  assert.doesNotMatch(planetList, /assets\/|stellarium\/textures\/|surface/);
  assert.doesNotMatch(switchPlanet, /" surface"|"garching"|"jupiter"|"mars"/);
});

test('planet changes delegate the English name to the upstream automatic landscape route', () => {
  assert.match(switchPlanet, /core->moveObserverTo\(loc, 0\.0, 0\.0, landscapeHint\)/);
  assert.match(switchPlanet, /const QString landscapeHint = planetChanged && landscapeMgr && landscapeMgr->getFlagLandscapeAutoSelection\(\) \? loc\.planetName : QString\(\)/);
  assert.match(block(dialog, 'void LocationDialog::moveToAnotherPlanet('), /moveObserverTo\(loc, 0\., 0\., loc\.planetName\)/);
  assert.match(moveObserver, /emit targetLocationChanged\(target, landscapeID\)/);
  assert.match(targetChanged, /else if \(flagLandscapeAutoSelection && \(loc\.planetName != currentPlanetName\)\)/);
  assert.match(targetChanged, /setCurrentLandscapeID\("zero"\)/);
  assert.match(targetChanged, /setFlagLandscapeSetsLocation\(false\)/);
  assert.match(targetChanged, /setFlagLandscapeSetsLocation\(landscapeSetsLocation\)/);
});

test('the bridge leaves atmosphere, fog and custom landscape preferences to the engine', () => {
  for (const name of ['setObserverPlanet', 'setLocation', 'setLocationCoords']) {
    assert.doesNotMatch(command(name), /setCurrentLandscape|setFlag(?:Landscape|Atmosphere|Fog|Environment)|setProperty|immediateSave/);
  }
  assert.match(targetChanged, /pl && flagEnvironmentAutoEnabling && currentPlanetName!=loc\.planetName/);
  for (const preference of ['atmosphere', 'fog']) {
    assert.match(targetChanged, new RegExp(`pl->hasAtmosphere\\(\\) && conf->value\\("landscape/flag_${preference}"`));
  }
});

test('coordinate conversion rejects invalid, nonfinite and out of range input before writing', () => {
  assert.match(coordinates, /toDouble\(&latitudeOk\)/);
  assert.match(coordinates, /toDouble\(&longitudeOk\)/);
  assert.match(coordinates, /toInt\(&altitudeOk\)/);
  const invalid = block(coordinates, 'if (!latitudeOk || !longitudeOk || !altitudeOk');
  assert.match(invalid, /result\["error"\]/);
  assert.match(invalid, /return false/);
  assert.match(coordinates, /!std::isfinite\(latitude\) \|\| !std::isfinite\(longitude\)/);
  assert.match(coordinates, /latitude < -90\.0 \|\| latitude > 90\.0 \|\| longitude < -180\.0 \|\| longitude > 180\.0/);
  assert.ok(coordinates.indexOf('return false') < coordinates.indexOf('location.setLatitude'));
  for (const name of ['setObserverPlanet', 'setLocation', 'setLocationCoords']) {
    const body = command(name);
    const validationIndex = body.indexOf('parseOhosLocationCoordinates(');
    assert.ok(validationIndex >= 0, `${name} must use checked conversion`);
    for (const mutation of ['moveObserverTo(', 'resetInitViewPos(', 'unSelect(', 'markOhosInteraction(']) {
      const mutationIndex = body.indexOf(mutation);
      assert.ok(mutationIndex === -1 || validationIndex < mutationIndex, `${name} validates before ${mutation}`);
    }
  }
});

test('payload arity is exact and coordinate-only commands keep both legacy separators', () => {
  assert.match(switchPlanet, /parts\.size\(\) != 1 && parts\.size\(\) != 4 && parts\.size\(\) != 5/);
  assert.match(command('setLocation'), /parts\.size\(\) != 4/);
  const body = command('setLocationCoords');
  assert.match(body, /arg\.contains\('\|'\) \? arg\.split\('\|'\) : arg\.split\(','\)/);
  assert.match(body, /parts\.size\(\) != 2 && parts\.size\(\) != 3/);
  assert.match(body, /if \(parts\.size\(\) == 2\)\s+parts\.append\(QStringLiteral\("0"\)\)/);
});

test('name-only switching inherits coordinates and saved site names can be restored', () => {
  assert.match(switchPlanet, /StelLocation loc = core->getCurrentLocation\(\)/);
  assert.match(switchPlanet, /parts\.size\(\) >= 4 && !parseOhosLocationCoordinates/);
  assert.doesNotMatch(switchPlanet, /setLatitude\(|setLongitude\(|loc\.altitude = 0/);
  assert.match(block(switchPlanet, 'if (planetChanged)'), /loc\.name = planet->getNameI18n\(\)/);
  assert.match(switchPlanet, /if \(parts\.size\(\) == 5 && !parts\[4\]\.trimmed\(\)\.isEmpty\(\)\)\s+loc\.name = parts\[4\]\.trimmed\(\)/);
});

test('same-planet fine tuning cannot reset the initial view or choose another landscape', () => {
  const cleanup = block(switchPlanet, "if (planetChanged && loc.role != QChar('o'))");
  assert.match(cleanup, /movementMgr->resetInitViewPos\(\)/);
  assert.equal(switchPlanet.match(/resetInitViewPos\(/g)?.length, 1);
  assert.match(switchPlanet, /if \(planetChanged \|\| parts\.size\(\) >= 4\)\s+core->moveObserverTo/);
  assert.match(switchPlanet, /planetChanged && landscapeMgr && landscapeMgr->getFlagLandscapeAutoSelection\(\) \? loc\.planetName : QString\(\)/);
});

test('ordinary destinations clear selection of the home planet and observers reuse core tracking', () => {
  const cleanup = block(switchPlanet, "if (planetChanged && loc.role != QChar('o'))");
  assert.match(cleanup, /!selection\.isEmpty\(\) && selection\[0\]->getEnglishName\(\) == loc\.planetName\)\s+objectMgr->unSelect\(\)/);
  assert.match(switchPlanet, /planet->getPlanetType\(\) == Planet::isObserver \? QChar\('o'\) : QChar\('X'\)/);
  const observer = block(moveObserver, "if (target.role==QChar('o'))");
  assert.match(observer, /planet->getParent\(\)->getEnglishName\(\)/);
  assert.match(observer, /setFlagTracking\(true\)/);
  assert.ok(switchPlanet.indexOf('objectMgr->unSelect()') < switchPlanet.indexOf('core->moveObserverTo('));
});

test('successful switch reports committed location including raw observer coordinates and actual landscape', () => {
  assert.match(switchPlanet, /const StelLocation& actual = core->getCurrentLocation\(\)/);
  assert.ok(switchPlanet.indexOf('core->moveObserverTo(') < switchPlanet.indexOf('const StelLocation& actual'));
  for (const [field, expression] of [
    ['planetName', 'actual.planetName'], ['locationName', 'actual.name'],
    ['latitude', 'actual.getLatitude(true)'], ['longitude', 'actual.getLongitude(true)'],
    ['altitude', 'actual.altitude']
  ]) {
    assert.ok(switchPlanet.includes(`result["${field}"] = ${expression};`), `missing actual ${field}`);
  }
  assert.match(switchPlanet, /result\["landscapeID"\] = landscapeMgr \? landscapeMgr->getCurrentLandscapeID\(\)/);
});

test('setLocation and setLocationCoords keep the current body without explicit landscape selection', () => {
  for (const name of ['setLocation', 'setLocationCoords']) {
    const body = command(name);
    assert.match(body, /StelLocation \w+ = core->getCurrentLocation\(\)/);
    assert.doesNotMatch(body, /\.planetName\s*=(?!=)/);
    assert.match(body, /core->moveObserverTo\(\w+, 0\.0, 0\.0\)/);
  }
  assert.match(command('setLocation'), /if \(location\.planetName == "Earth"\)\s+resolveOhosEarthLocation\(location\)/);
  assert.match(command('setLocation'), /result = currentStateJson\(\)/);
});

test('Earth coordinates resolve nearby named metadata with a system timezone fallback', () => {
  const resolveEarth = block(native, 'static void resolveOhosEarthLocation(');
  assert.match(resolveEarth, /location\.ianaTimeZone = QStringLiteral\("system_default"\)/);
  assert.match(resolveEarth, /locationForString\(location\.name\)/);
  assert.match(resolveEarth, /pickLocationsNearby\("Earth",.*0\.5f\)/);
  assert.match(resolveEarth, /candidate\.name\.compare\(location\.name, Qt::CaseInsensitive\) != 0\)\s+continue/);
  const matched = block(resolveEarth, 'if (match.isValid() && match.planetName == "Earth"');
  assert.match(resolveEarth, /match\.getLatitude\(true\)\) <= 0\.5/);
  assert.match(matched, /location\.region = match\.region/);
  assert.match(matched, /location\.state = match\.state/);
  assert.match(matched, /!match\.ianaTimeZone\.isEmpty\(\) && match\.ianaTimeZone != "LMST" && match\.ianaTimeZone != "LTST"/);
  assert.match(matched, /location\.ianaTimeZone = match\.ianaTimeZone/);
  assert.match(switchPlanet, /if \(planetName == "Earth" && \(planetChanged \|\| parts\.size\(\) >= 4\)\)\s+resolveOhosEarthLocation\(loc\)/);
  assert.match(switchPlanet, /else if \(planetChanged\)\s+loc\.ianaTimeZone = QStringLiteral\("LMST"\)/);
  assert.doesNotMatch(switchPlanet, /setUseCustomTimeZone|setCurrentTimeZone/);
  assert.match(block(core, 'void StelCore::setObserver('), /!getUseCustomTimeZone\(\)/);
});

test('the native catalog describes the additional site name and compatible coordinate payloads', () => {
  for (const name of ['getObserverPlanetList', 'setObserverPlanet', 'setLocation', 'setLocationCoords']) {
    assert.match(block(catalog, `else if (name == "${name}")`), /value\["description"\]/);
  }
  assert.match(block(catalog, 'else if (name == "setObserverPlanet")'), /\[\|lat\|lon\|alt\[\|name\]\]/);
  assert.match(block(catalog, 'else if (name == "setLocationCoords")'), /lat,lon\[,alt\].*lat\|lon\[\|alt\]/);
});
