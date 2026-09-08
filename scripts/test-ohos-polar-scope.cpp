#include "PolarScopeGeometry.hpp"
#include <cassert>
#include <limits>

int main()
{
	for (const double radius : {20.0, 80.0, 251.0, 670.0, 5000.0})
	{
		for (const double offset : {-4000.0, -100.0, 0.0, 100.0, 4000.0})
		{
			assert(std::abs(polarScopeRadius(offset, offset, offset + radius, offset) - radius) < 1e-6);
			assert(std::abs(polarScopeRadius(offset, offset, offset, offset - radius) - radius) < 1e-6);
		}
		const int step = polarScopeLabelStep(radius, 32.0);
		assert(step == 1 || step == 2 || step == 3 || step == 6 || step == 24);
		if (step < 24)
			assert(2 * radius * std::sin(step * 3.141592653589793 / 24) >= 44);
	}
	assert(polarScopeRadius(0, 0, std::numeric_limits<double>::infinity(), 0) == 0);
	assert(polarScopeLabelStep(20, 32) > polarScopeLabelStep(251, 32));
}
