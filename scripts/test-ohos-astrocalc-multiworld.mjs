import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = rel => readFileSync(root + rel, 'utf8');

const cpp = read('src/StelMainView.cpp');
const astroPanel = read('harmonyos/ets-source/panels/astro/AstroPanel.ets');
const astroStore = read('harmonyos/ets-source/state/AstroStore.ets');
const astroCtl = read('harmonyos/ets-source/capability/AstroCalcController.ets');

// 1. C++ multi-world getAlmanac: emits observerPlanet/companion/Ls seasons and omits Earth 24 solar terms off-Earth
const almanacBlock = cpp.slice(cpp.indexOf('if (commandName == "getAlmanac")'), cpp.indexOf('if (commandName == "getObjectPositions")'));
assert.match(almanacBlock, /alm\["observerPlanet"\] = obsEn;/);
assert.match(almanacBlock, /alm\["isEarth"\] = isEarth;/);
assert.match(almanacBlock, /alm\["solarDayHours"\] = solarDayHours;/);
assert.match(almanacBlock, /alm\["companionNameZh"\]/);
assert.match(almanacBlock, /alm\["solarTerms"\] = QJsonArray\(\);/);
assert.match(almanacBlock, /obsZh \+ QStringLiteral\("春分 \(Ls 0°\)"\)/);

// 2. C++ multi-world getPhenomena: includes Earth and excludes observerPlanet
const phenomBlock = cpp.slice(cpp.indexOf('if (commandName == "getPhenomena")'), cpp.indexOf('if (commandName == "getMoonPhases")'));
assert.match(phenomBlock, /"Mercury", "Venus", "Earth", "Mars"/);
assert.match(phenomBlock, /name\.compare\(obsEn, Qt::CaseInsensitive\) != 0/);
assert.match(phenomBlock, /result\["observerPlanet"\] = obsEn;/);

// 3. C++ multi-world getPlanetaryTransits: supports inner-planet transits off-Earth without rejecting non-Earth
const transitBlock = cpp.slice(cpp.indexOf('if (commandName == "getPlanetaryTransits")'), cpp.indexOf('if (commandName == "getEclipses")'));
assert.doesNotMatch(transitBlock, /planetary transits are only available for an observer on Earth/);
assert.match(transitBlock, /if \(observerPlanet != earth\)/);
assert.match(transitBlock, /cMeta\.semiMajorAxisAU >= obsMeta\.semiMajorAxisAU - 0\.05/);
assert.match(transitBlock, /ohosCalendarTopocentricAlt\(core, observerPlanet, loc, sun, midJD\)/);

// 4. C++ multi-world getEclipses: supports parent-planet solar eclipses from moons & satellite solar/shadow eclipses from planets
const eclipseBlock = cpp.slice(cpp.indexOf('if (commandName == "getEclipses")'), cpp.lastIndexOf('result["error"] = "unknown command";'));
assert.match(eclipseBlock, /if \(!earth \|\| observerPlanet != earth\)/);
assert.match(eclipseBlock, /if \(isMoonObserver\)/);
assert.match(eclipseBlock, /"Phobos", "火卫一"/);
assert.match(eclipseBlock, /"Io", "木卫一"/);
assert.match(eclipseBlock, /"Titan", "土卫六"/);
assert.match(eclipseBlock, /ev\["occulter"\] = satZh;/);
assert.match(eclipseBlock, /rUmbra = std::max\(0\.0, rObs - L \* \(rSunPhys - rObs\) \/ D\)/);

// 5. ArkTS top-bar quick planet switcher + multi-world UI + cache invalidation
assert.match(astroPanel, /\.id\('astro-planet-switcher'\)/);
assert.match(astroPanel, /\.id\('astro-planet-' \+ pEn\)/);
assert.match(astroPanel, /switchObserverPlanet\(pEn\)/);
assert.match(astroPanel, /this\.phenomenaBodyChoices\(\)/);
assert.match(astroPanel, /this\.eclipseRowTitle\(e\)/);
assert.match(astroPanel, /\.id\('astro-open-calendars-btn'\)/);
assert.match(astroStore, /invalidateForPlanetChange\(/);
assert.match(astroCtl, /switchObserverPlanet\(planetEn: string\): void/);
assert.match(astroCtl, /const planetKey = this\.astroStore\.observerPlanet \|\| 'Earth'/);

// 6. Regression guard: floatingPanel() must NOT clamp inner panelContent() Column to .height('100%') inside Scroll(widePanelScroller)
const mainNode = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
const floatingBlock = mainNode.slice(mainNode.indexOf('floatingPanel() {'), mainNode.indexOf('compactPanel() {'));
assert.doesNotMatch(floatingBlock, /this\.panelContent\(\)\s*\}\s*\.width\('100%'\)\s*\.height\('100%'\)/,
  'floatingPanel() must not clamp inner panelContent() Column to height("100%"), which disables vertical scrolling on tablet!');

console.log('AstroCalc multi-world engine & UI checks OK.');
