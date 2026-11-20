#include "../src/core/modules/EnvironmentZoomFade.hpp"

#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>

using EnvironmentZoomFade::combinedLandscapeTransparency;
using EnvironmentZoomFade::environmentVisibility;
using EnvironmentZoomFade::mistVisibility;

int main()
{
	// 1. Mist zoom fade: always active over 14 deg -> 4 deg
	assert(mistVisibility(60.0) == 1.f);
	assert(mistVisibility(14.0) == 1.f);
	assert(mistVisibility(9.0) > 0.49f && mistVisibility(9.0) < 0.51f);
	assert(mistVisibility(4.0) == 0.f);
	assert(mistVisibility(1.0) == 0.f);

	// Monotonicity for mist over [4, 14]
	float prev = 0.f;
	for (int step = 0; step <= 100; ++step)
	{
		const double fov = 4.0 + 0.1 * step;
		const float cur = mistVisibility(fov);
		assert(std::isfinite(cur) && cur >= prev && cur <= 1.f);
		prev = cur;
	}

	// 2. Atmosphere & landscape zoom fade: OFF preserves physical simulation
	for (const double fov : {120.0, 60.0, 10.0, 5.0, 2.0, 0.2})
	{
		assert(environmentVisibility(false, fov) == 1.f);
	}

	// 3. Atmosphere & landscape zoom fade: ON fades smoothly over 10 deg -> 2 deg
	assert(environmentVisibility(true, 60.0) == 1.f);
	assert(environmentVisibility(true, 10.0) == 1.f);
	assert(environmentVisibility(true, 6.0) > 0.49f && environmentVisibility(true, 6.0) < 0.51f);
	assert(environmentVisibility(true, 2.0) == 0.f);
	assert(environmentVisibility(true, 0.5) == 0.f);

	prev = 0.f;
	for (int step = 0; step <= 80; ++step)
	{
		const double fov = 2.0 + 0.1 * step;
		const float cur = environmentVisibility(true, fov);
		assert(std::isfinite(cur) && cur >= prev && cur <= 1.f);
		prev = cur;
	}

	// 4. Non-finite FOV safety
	assert(mistVisibility(std::numeric_limits<double>::quiet_NaN()) == 1.f);
	assert(environmentVisibility(true, std::numeric_limits<double>::infinity()) == 1.f);

	// 5. Combined transparency composes base transparency and zoom visibility cleanly
	assert(std::abs(combinedLandscapeTransparency(0.0, 1.0f) - 0.0) < 1e-6);
	assert(std::abs(combinedLandscapeTransparency(0.0, 0.0f) - 1.0) < 1e-6);
	assert(std::abs(combinedLandscapeTransparency(0.5, 0.5f) - 0.75) < 1e-6);
	assert(std::abs(combinedLandscapeTransparency(1.0, 1.0f) - 1.0) < 1e-6);

	std::cout << "All environment zoom fade checks passed." << std::endl;
	return 0;
}
