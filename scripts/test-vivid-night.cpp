#include "../src/core/modules/AtmosphereVivid.hpp"
#include <cassert>
#include <limits>
#include <iostream>

int main()
{
	using AtmosphereVivid::visualStrength;
	float previous = 0.f;
	for (int step = -9000; step <= 9000; ++step)
	{
		const double elevation = step / 100.;
		const float strength = visualStrength(true, true, false, elevation);
		assert(std::isfinite(strength) && strength >= previous && strength <= 1.f);
		assert(strength - previous < 0.0013f);
		if (elevation <= -18.) assert(strength == 0.f);
		if (elevation >= -6.) assert(strength == 1.f);
		assert(visualStrength(false, true, false, elevation) == 1.f);
		assert(visualStrength(true, false, false, elevation) == 1.f);
		assert(visualStrength(true, true, true, elevation) == 1.f);
		previous = strength;
	}
	assert(visualStrength(true, true, false, std::numeric_limits<double>::quiet_NaN()) == 1.f);
	assert(visualStrength(true, true, false, std::numeric_limits<double>::infinity()) == 1.f);
	assert(visualStrength(true, true, false, -17.999) < 0.000001f);
	assert(1.f - visualStrength(true, true, false, -6.001) < 0.000001f);
	std::cout << "Vivid night: 18001 elevations, mode exclusions and twilight boundaries passed\n";
}
