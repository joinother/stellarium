#include "../src/core/modules/PlanetaryCalendarHelper.hpp"

#include <cassert>
#include <cmath>
#include <iostream>
#include <string>

using namespace PlanetaryCalendarHelper;

static int hexChannel(const std::string& hex, int offset)
{
	return std::stoi(hex.substr(static_cast<size_t>(offset), 2), nullptr, 16);
}

int main()
{
	// 1. Metadata & Earth classification
	assert(isEarthName("Earth"));
	assert(isEarthName(" earth "));
	assert(isEarthName(""));
	assert(!isEarthName("Mars"));
	assert(!isEarthName("Moon"));
	assert(!isEarthName("Titan"));

	const auto& mars = metaForPlanet("Mars");
	assert(std::string(mars.englishName) == "Mars");
	assert(std::string(mars.primaryCompanion) == "Phobos");
	assert(mars.semiMajorAxisAU > 1.5 && mars.semiMajorAxisAU < 1.6);
	assert(std::isfinite(mars.vernalEquinoxHelioLonDeg));

	const auto& moon = metaForPlanet("Moon");
	assert(std::string(moon.primaryCompanion) == "Earth");
	assert(std::string(moon.companionRole) == "parent-planet");

	const auto& titan = metaForPlanet("Titan");
	assert(std::string(titan.primaryCompanion) == "Saturn");
	assert(std::string(titan.companionRole) == "parent-planet");

	// 2. Phase illumination math
	// Full phase: observerToTarget and sunToTarget are aligned (cos = +1 -> 100%)
	assert(std::abs(illuminationPercent({1.0, 0.0, 0.0}, {1.0, 0.0, 0.0}) - 100.0) < 1e-6);
	// New phase: opposite vectors (cos = -1 -> 0%)
	assert(std::abs(illuminationPercent({1.0, 0.0, 0.0}, {-1.0, 0.0, 0.0}) - 0.0) < 1e-6);
	// Quarter phase: orthogonal (cos = 0 -> 50%)
	assert(std::abs(illuminationPercent({1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}) - 50.0) < 1e-6);

	assert(companionPhaseLabelZh(99.0, true, "地") == "满地");
	assert(companionPhaseLabelZh(1.0, false, "地") == "新地");
	assert(companionPhaseLabelZh(50.0, true, "土星") == "上弦土星");
	assert(companionPhaseLabelZh(50.0, false, "土星") == "下弦土星");

	// 3. Sky hex gradient for 48h offline widget timeline
	// Airless Moon stays deep space dark even at noon
	const auto moonNoon = skyHexForSunAltitude("Moon", false, 45.0);
	assert(moonNoon.topHex == "#05070D");
	assert(hexChannel(moonNoon.topHex, 1) < 20);

	// Mars noon: butterscotch (R > G > B)
	const auto marsNoon = skyHexForSunAltitude("Mars", true, 40.0);
	assert(marsNoon.horizonHex.size() == 7 && marsNoon.horizonHex[0] == '#');
	assert(hexChannel(marsNoon.horizonHex, 1) > hexChannel(marsNoon.horizonHex, 3));
	assert(hexChannel(marsNoon.horizonHex, 3) > hexChannel(marsNoon.horizonHex, 5));

	// Mars sunset (sunAlt = 1 deg): iconic blue horizon (B > R)
	const auto marsSunset = skyHexForSunAltitude("Mars", true, 1.0);
	assert(hexChannel(marsSunset.horizonHex, 5) > hexChannel(marsSunset.horizonHex, 1));

	// Titan noon: burnt orange tholin haze (R >> B)
	const auto titanNoon = skyHexForSunAltitude("Titan", true, 35.0);
	assert(hexChannel(titanNoon.horizonHex, 1) > hexChannel(titanNoon.horizonHex, 5) * 2);

	// Pluto noon: dark zenith + luminous ice-blue horizon
	const auto plutoNoon = skyHexForSunAltitude("Pluto", true, 30.0);
	assert(hexChannel(plutoNoon.topHex, 5) < 40);
	assert(hexChannel(plutoNoon.horizonHex, 5) > hexChannel(plutoNoon.horizonHex, 1) * 2);

	// Deep night stays dark across all worlds
	const auto marsNight = skyHexForSunAltitude("Mars", true, -30.0);
	assert(hexChannel(marsNight.topHex, 1) < 25 && hexChannel(marsNight.topHex, 5) < 40);

	std::cout << "All planetary calendar helper checks passed." << std::endl;
	return 0;
}
