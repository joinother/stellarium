import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = relativePath => fs.readFileSync(new URL(`../${relativePath}`, import.meta.url), 'utf8');
const native = read('src/StelMainView.cpp');
const dialog = read('src/gui/LocationDialog.cpp');
const core = read('src/core/StelCore.cpp');
const landscape = read('src/core/modules/LandscapeMgr.cpp');
const stelApp = read('src/core/StelApp.cpp');
const catalog = read('src/StelOhosCommandCatalog.hpp');
const host = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
const locationController = read('harmonyos/ets-source/capability/LocationController.ets');
const sessionStore = read('harmonyos/ets-source/state/SessionToolStore.ets');

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

test('observer picker metadata exposes stable planet types and moon parents', () => {
  assert.match(planetList, /const PlanetP parent = planet->getParent\(\)/)
  assert.match(planetList, /entry\["type"\] = planetTypeName\(planet->getPlanetType\(\)\)/)
  assert.match(planetList, /entry\["parent"\] = parent \? parent->getEnglishName\(\) : QString\(\)/)
  for (const type of ['star', 'planet', 'moon', 'observer', 'asteroid', 'dwarfPlanet', 'comet', 'interstellar']) {
    assert.match(planetList, new RegExp(`return QStringLiteral\\("${type}"\\)`))
  }
})

test('planet changes remember the Earth landscape and keep auto-selection for other bodies', () => {
  assert.match(switchPlanet, /core->moveObserverTo\(loc, 0\.0, 0\.0, landscapeHint\)/);
  assert.match(switchPlanet, /if \(planetChanged && landscapeMgr\)/);
  assert.match(switchPlanet, /previousPlanet == QStringLiteral\("Earth"\)/);
  assert.match(switchPlanet, /loc\.planetName != QStringLiteral\("Earth"\)/);
  assert.match(switchPlanet, /value\("landscape\/saved_earth_landscape_id"\)/)
  assert.match(switchPlanet, /earthLandscape != QStringLiteral\("zero"\)/)
  assert.match(switchPlanet, /immediateSaveNow\("landscape\/saved_earth_landscape_id", earthLandscape\)/)
  assert.match(switchPlanet, /landscapeHint = savedEarth/)
  assert.match(switchPlanet, /landscapeHint = loc\.planetName/)
  assert.match(switchPlanet, /landscapeHint = QStringLiteral\("zero"\)/)
  assert.match(switchPlanet, /else if \(landscapeMgr->getFlagLandscapeAutoSelection\(\)\)/)
  assert.match(block(dialog, 'void LocationDialog::moveToAnotherPlanet('), /moveObserverTo\(loc, 0\., 0\., loc\.planetName\)/);
  assert.match(block(dialog, 'void LocationDialog::moveToAnotherPlanet('), /setCurrentLandscapeID\(lMgr->getDefaultLandscapeID\(\)\)/);
  assert.match(moveObserver, /emit targetLocationChanged\(target, landscapeID\)/);
  assert.match(targetChanged, /else if \(flagLandscapeAutoSelection && \(loc\.planetName != currentPlanetName\)\)/);
  assert.match(targetChanged, /getAllLandscapeNames\(\)\.indexOf\(loc\.planetName\) >= 0/);
  assert.match(targetChanged, /loc\.planetName == QStringLiteral\("Earth"\)/);
  assert.match(targetChanged, /setCurrentLandscapeID\(defaultLandscapeID\)/);
  assert.match(targetChanged, /setCurrentLandscapeID\("zero"\)/);
  assert.match(targetChanged, /setFlagLandscapeSetsLocation\(false\)/);
  assert.match(targetChanged, /setFlagLandscapeSetsLocation\(landscapeSetsLocation\)/);
});

test('Earth uses the configured default (guereins) independently of auto-selection', () => {
  const init = block(landscape, 'void LandscapeMgr::init()');
  assert.match(init, /init_location\/landscape_name/);
  assert.match(init, /QStringLiteral\("guereins"\)/);
  assert.match(init, /setCurrentLandscapeID\(defaultLandscapeID\)/);
  assert.doesNotMatch(init, /#ifdef __OHOS__/);

  const setLandscape = command('setLandscape');
  assert.match(setLandscape, /getCurrentLandscapeID\(\) == arg/);
  assert.match(setLandscape, /saved_earth_landscape_id/);
  assert.match(setLandscape, /immediateSaveNow\("landscape\/saved_earth_landscape_id", arg\)/);
  assert.match(setLandscape, /planetName == QStringLiteral\("Earth"\)/);

  const stelAppInit = block(stelApp, 'void StelApp::init(QSettings* conf)');
  assert.match(stelAppInit, /keepEarthLandscape/);
  assert.match(stelAppInit, /currentLandscapeID = landscape->getCurrentLandscapeID\(\)/);
  assert.match(stelAppInit, /currentLandscapeID != QStringLiteral\("zero"\)/);
  assert.match(stelAppInit, /!keepEarthLandscape && landscape->getFlagLandscapeAutoSelection/);
  assert.doesNotMatch(stelAppInit, /#ifdef __OHOS__/);

  const restore = command('restoreSavedEarthLandscape');
  assert.doesNotMatch(restore, /getFlagLandscapeAutoSelection/);
  assert.match(restore, /target = lmgr->getDefaultLandscapeID\(\)/);
  assert.match(restore, /current == target/);
  assert.match(restore, /setCurrentLandscapeID\(target\)/);
});

test('session continuation carries the panorama instead of hardcoding Earth', () => {
  const sessionExport = command('getSessionState');
  assert.match(sessionExport, /result\["landscapeID"\] = lm->getCurrentLandscapeID\(\)/);

  const sessionApply = command('applySessionState');
  assert.match(sessionApply, /s\.value\("landscapeID"\)\.toString\(\)/);
  assert.doesNotMatch(sessionApply, /planet == "Earth"\) landscapeID = "garching"/);
  assert.match(sessionApply, /saved_earth_landscape_id/);
  assert.match(sessionApply, /lm->getDefaultLandscapeID\(\)/);
});

test('landscape auto-selection and environment auto-enable are exposed through the OHOS bridge', () => {
  assert.match(native, /commandName == "getLandscapeAutoSelection"/)
  assert.match(native, /commandName == "setLandscapeAutoSelection"/)
  assert.match(native, /commandName == "restoreSavedEarthLandscape"/)
  assert.match(native, /commandName == "applyLandscapeDefaults"/)
  assert.match(native, /lmgr->setFlagLandscapeAutoSelection\(enabled\)/)
  assert.match(native, /result\["landscapeAutoSelection"\] = landscape->getFlagLandscapeAutoSelection\(\)/)
  assert.match(locationController, /requestWhenReady\('restoreSavedEarthLandscape'/)
  assert.match(host, /requestWhenReady\('applyLandscapeDefaults'/)
  assert.match(catalog, /getLandscapeAutoSelection/)
  assert.match(catalog, /setLandscapeAutoSelection/)
  assert.match(catalog, /applyLandscapeDefaults/)
  assert.match(catalog, /restoreSavedEarthLandscape/)

  // PC's "Auto-enable atmosphere" is a fixed ON behavior on OHOS (no Location
  // dialog). Startup must persist it and the bridge must expose the value.
  assert.match(native, /commandName == "getEnvironmentAutoEnable"/)
  assert.match(native, /commandName == "setEnvironmentAutoEnable"/)
  assert.match(native, /commandName == "applyEnvironmentDefaults"/)
  assert.match(native, /lmgr->setFlagEnvironmentAutoEnable\(true\)/)
  assert.match(native, /immediateSaveNow\("viewing\/flag_environment_auto_enable", true\)/)
  assert.match(host, /requestWhenReady\('applyEnvironmentDefaults'/)
  assert.match(catalog, /getEnvironmentAutoEnable/)
  assert.match(catalog, /setEnvironmentAutoEnable/)
  assert.match(catalog, /applyEnvironmentDefaults/)
});

test('place panel location rows reuse the observer picker localized label', () => {
  // 位置条目与下拉列表必须同源：引擎本地化的卫星/全览点名称不能只靠 planetZh。
  assert.match(sessionStore, /observerPlanetLabel\(name: string\): string/)
  assert.match(locationController, /observerPlanetLabel\(targetPlanet\)/)
  assert.match(host, /' · ' \+ this\.sessionToolStore\.observerPlanetLabel\(planetName\)/)
  // 全屏选点顶部标题（以及搜索占位、离线分区）复用同一标签。
  assert.match(host, /planetLabel: \(en: string\) => this\.sessionToolStore\.observerPlanetLabel\(en\)/)
  assert.match(read('harmonyos/ets-source/panels/location/LocationFullScreenMap.ets'),
    /Text\(this\.planetLabel\(this\.observerPlanet\)\)/)
});

test('automatic environment switching preserves stored atmosphere and fog preferences', () => {
  for (const name of ['setObserverPlanet', 'setLocation', 'setLocationCoords']) {
    // The only bridge-side write allowed here is the OHOS Earth-landscape memory;
    // landscape/atmosphere/fog preferences must still be handled by LandscapeMgr.
    const body = command(name).replace(
      /StelApp::immediateSaveNow\("landscape\/saved_earth_landscape_id", earthLandscape\);\r?\n/g, '');
    assert.doesNotMatch(body, /setCurrentLandscape|setFlag(?:Landscape|Atmosphere|Fog|Environment)|setProperty|immediateSave/);
  }
  assert.match(targetChanged, /pl && flagEnvironmentAutoEnabling && currentPlanetName!=loc\.planetName/);
  const autoPlanet = block(targetChanged, 'if (pl && flagEnvironmentAutoEnabling && currentPlanetName!=loc.planetName)');
  assert.match(autoPlanet, /const bool hasAtmosphere = pl->hasAtmosphere\(\)/);
  assert.match(autoPlanet, /setFlagAtmosphereAndFogForEnvironment\(/);
  assert.match(autoPlanet, /hasAtmosphere && conf->value\("landscape\/flag_atmosphere"/);
  assert.match(autoPlanet, /hasAtmosphere && conf->value\("landscape\/flag_fog"/);
  // Automatic switching must not call the persisting user-action setters.
  assert.doesNotMatch(targetChanged, /setFlagAtmosphere\(|setFlagFog\(/);
  const observerBranch = block(targetChanged, "if (loc.role==QChar('o'))");
  assert.match(observerBranch, /setFlagAtmosphereAndFogForEnvironment\(false, false\)/);
  assert.doesNotMatch(observerBranch, /setFlagAtmosphere\(|setFlagFog\(/);

  const atmosphereInternal = block(landscape, 'void LandscapeMgr::setFlagAtmosphereInternal(');
  assert.match(atmosphereInternal, /if \(saveToConfig\)\s+StelApp::immediateSave\("landscape\/flag_atmosphere"/);
  const fogInternal = block(landscape, 'void LandscapeMgr::setFlagFogInternal(');
  assert.match(fogInternal, /if \(saveToConfig\)\s+StelApp::immediateSave\("landscape\/flag_fog"/);
  assert.match(block(landscape, 'void LandscapeMgr::setFlagAtmosphere(const bool displayed)'),
    /setFlagAtmosphereInternal\(displayed, true\)/);
  assert.match(block(landscape, 'void LandscapeMgr::setFlagFog(const bool displayed)'),
    /setFlagFogInternal\(displayed, true\)/);
  assert.match(block(landscape, 'void LandscapeMgr::setFlagAtmosphereAndFogForEnvironment('),
    /setFlagAtmosphereInternal\(showAtmosphere, false\)[\s\S]*setFlagFogInternal\(showFog, false\)/);

  // The other automatic paths (return home, Location dialog preview) use the
  // same non-persisting route.
  assert.match(block(core, 'void StelCore::returnToHome('),
    /setFlagAtmosphereAndFogForEnvironment\(/);
  assert.doesNotMatch(block(core, 'void StelCore::returnToHome('),
    /setFlagAtmosphere\(|setFlagFog\(/);
  const locationFields = block(dialog, 'void LocationDialog::setFieldsFromLocation(');
  assert.match(locationFields, /setFlagAtmosphereAndFogForEnvironment\(/);
  assert.doesNotMatch(locationFields, /setProperty\("atmosphereDisplayed"|setProperty\("fogDisplayed"/);
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
  const hintBlock = block(switchPlanet, 'if (planetChanged && landscapeMgr)');
  assert.equal(hintBlock.match(/landscapeHint = /g)?.length, 3);
  assert.match(hintBlock, /if \(loc\.planetName == QStringLiteral\("Earth"\)\)/);
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
