#include "../src/core/modules/AtmospherePlanetary.hpp"

#include <cassert>
#include <cmath>
#include <iostream>
#include <string>
#include <vector>

using AtmospherePlanetary::Color;
using AtmospherePlanetary::Profile;
using AtmospherePlanetary::evaluateColor;
using AtmospherePlanetary::profileForPlanet;

static bool isFiniteColor(const Color& c)
{
	return std::isfinite(c.r) && std::isfinite(c.g) && std::isfinite(c.b)
		&& c.r >= 0.f && c.g >= 0.f && c.b >= 0.f
		&& c.r <= 1.001f && c.g <= 1.001f && c.b <= 1.001f;
}

int main()
{
	// 1. Lookup & Earth bypass
	const auto& earth = profileForPlanet("Earth");
	assert(std::string(earth.id) == "earth");
	assert(earth.mixStrength == 0.f);
	assert(earth.luminanceScale == 1.f);
	assert(std::string(profileForPlanet("UnknownExoplanet").id) == "earth");
	assert(std::string(profileForPlanet("  mArS ").id) == "mars");

	const Color origDay{0.35f, 0.56f, 0.85f};
	const Color origHorizon{0.72f, 0.80f, 0.90f};
	const Color origSunset{0.62f, 0.44f, 0.30f};
	const Color origNight{0.004f, 0.006f, 0.012f};

	const std::array<float, 3> viewZenith{0.f, 0.f, 1.f};
	const std::array<float, 3> viewMid{0.707f, 0.f, 0.707f};
	const std::array<float, 3> viewSunwardHorizon{0.996f, 0.f, 0.087f};
	const std::array<float, 3> viewAntiSolarHorizon{-0.996f, 0.f, 0.087f};

	const std::array<float, 3> sunNoon{0.5f, 0.f, 0.866f};
	const std::array<float, 3> sunSunset{0.9994f, 0.f, 0.035f}; // ~2 deg elevation
	const std::array<float, 3> sunNight{0.f, 0.f, -0.6f};

	const Color earthEval = evaluateColor(earth, origDay, viewZenith, sunNoon);
	assert(earthEval.r == origDay.r && earthEval.g == origDay.g && earthEval.b == origDay.b);

	// 2. Mars: butterscotch daytime + iconic Martian blue sunset facing the Sun
	const auto& mars = profileForPlanet("Mars");
	assert(std::string(mars.id) == "mars");
	assert(mars.luminanceScale < 0.5f && mars.luminanceScale > 0.2f);
	const Color marsNoonMid = evaluateColor(mars, origDay, viewMid, sunNoon);
	assert(isFiniteColor(marsNoonMid));
	assert(marsNoonMid.r > marsNoonMid.g && marsNoonMid.g > marsNoonMid.b);

	const Color marsSunsetSunward = evaluateColor(mars, origSunset, viewSunwardHorizon, sunSunset);
	const Color marsSunsetAway = evaluateColor(mars, origSunset, viewAntiSolarHorizon, sunSunset);
	assert(isFiniteColor(marsSunsetSunward) && isFiniteColor(marsSunsetAway));
	assert(marsSunsetSunward.b > marsSunsetSunward.r * 1.15f); // Blue sunset glow around the Sun
	assert(marsSunsetAway.r > marsSunsetAway.b);               // Dusty warm sky away from the Sun

	// 3. Venus: warm golden-amber overcast
	const auto& venus = profileForPlanet("Venus");
	assert(std::string(venus.id) == "venus");
	const Color venusDay = evaluateColor(venus, origDay, viewMid, sunNoon);
	assert(isFiniteColor(venusDay));
	assert(venusDay.r > venusDay.g && venusDay.g > venusDay.b * 1.4f);

	// 4. Titan: deep orange-amber tholin haze, dimmer than Mars/Venus
	const auto& titan = profileForPlanet("Titan");
	assert(std::string(titan.id) == "titan");
	assert(titan.luminanceScale < mars.luminanceScale);
	const Color titanDay = evaluateColor(titan, origDay, viewMid, sunNoon);
	assert(isFiniteColor(titanDay));
	assert(titanDay.r > titanDay.g * 1.35f && titanDay.g > titanDay.b * 1.8f);

	// 5. Jupiter: sapphire zenith & upper sky over warm golden-cream ammonia horizon
	const auto& jupiter = profileForPlanet("Jupiter");
	assert(std::string(jupiter.id) == "jupiter");
	const Color jupZenith = evaluateColor(jupiter, origDay, viewZenith, sunNoon);
	const Color jupMid = evaluateColor(jupiter, origDay, viewMid, sunNoon);
	const Color jupHorizon = evaluateColor(jupiter, origHorizon, viewAntiSolarHorizon, sunNoon);
	assert(isFiniteColor(jupZenith) && isFiniteColor(jupMid) && isFiniteColor(jupHorizon));
	assert(jupZenith.b > jupZenith.r * 1.8f);
	assert(jupMid.b > jupMid.r * 1.15f);
	assert(jupHorizon.r > jupHorizon.b);

	// 6. Saturn: slate-blue zenith over pale butterscotch-gold horizon
	const auto& saturn = profileForPlanet("Saturn");
	assert(std::string(saturn.id) == "saturn");
	const Color satHorizon = evaluateColor(saturn, origHorizon, viewAntiSolarHorizon, sunNoon);
	assert(isFiniteColor(satHorizon));
	assert(satHorizon.r > satHorizon.b * 1.3f);

	// 7. Uranus: methane cyan-teal
	const auto& uranus = profileForPlanet("Uranus");
	assert(std::string(uranus.id) == "uranus");
	const Color uraMid = evaluateColor(uranus, origDay, viewMid, sunNoon);
	assert(isFiniteColor(uraMid));
	assert(uraMid.g > uraMid.r * 1.6f && uraMid.b > uraMid.r * 1.8f);

	// 8. Neptune: deep azure-cobalt, dimmer than Uranus
	const auto& neptune = profileForPlanet("Neptune");
	assert(std::string(neptune.id) == "neptune");
	assert(neptune.luminanceScale < uranus.luminanceScale);
	const Color nepMid = evaluateColor(neptune, origDay, viewMid, sunNoon);
	assert(isFiniteColor(nepMid));
	assert(nepMid.b > nepMid.g * 1.5f && nepMid.g > nepMid.r * 1.5f);

	// 9. Pluto & Triton: tenuous nitrogen limb haze (dark zenith, bright icy-blue horizon)
	for (const char* world : {"Pluto", "Triton"})
	{
		const auto& p = profileForPlanet(world);
		assert(p.zenithAttenuation < 0.1f);
		const Color z = evaluateColor(p, origDay, viewZenith, sunNoon);
		const Color h = evaluateColor(p, origHorizon, viewSunwardHorizon, sunNoon);
		assert(isFiniteColor(z) && isFiniteColor(h));
		assert(z.b < 0.08f);
		assert(h.b > 0.40f && h.b > h.r * 1.3f);
	}

	// 10. Night safety & finiteness across all profiles (including exact zenith/nadir)
	const std::vector<std::string> allWorlds{
		"Earth", "Mars", "Venus", "Titan", "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto", "Triton"
	};
	for (const auto& name : allWorlds)
	{
		const auto& p = profileForPlanet(name);
		const Color nightZ = evaluateColor(p, origNight, viewZenith, sunNight);
		const Color nightH = evaluateColor(p, origNight, viewSunwardHorizon, sunNight);
		assert(isFiniteColor(nightZ) && isFiniteColor(nightH));
		assert(std::max({nightZ.r, nightZ.g, nightZ.b}) < 0.03f);
		assert(std::max({nightH.r, nightH.g, nightH.b}) < 0.03f);
	}

	std::cout << "All planetary atmosphere checks passed (" << allWorlds.size() << " worlds)." << std::endl;
	return 0;
}
