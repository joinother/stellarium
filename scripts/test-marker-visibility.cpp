#include "../src/core/MarkerVisibility.hpp"
#include <cassert>
#include <limits>

int main()
{
	for (float limit : {-3.f, 0.f, 6.f, 18.f})
	{
		assert(MarkerVisibility::magnitudeOpacity(limit, limit) == 0.f);
		assert(MarkerVisibility::magnitudeOpacity(limit + 1.f, limit) == 0.f);
		assert(MarkerVisibility::magnitudeOpacity(limit - 1.f, limit) == 1.f);
		assert(std::abs(MarkerVisibility::magnitudeOpacity(limit - .375f, limit) - .5f) < 1.e-6f);
		float previous = 0.f;
		for (int sample = 0; sample <= 1000; ++sample)
		{
			const float value = MarkerVisibility::magnitudeOpacity(limit - sample / 1000.f, limit);
			assert(value >= previous && value <= 1.f);
			assert(value - previous < .003f);
			previous = value;
		}
	}
	assert(MarkerVisibility::magnitudeOpacity(std::numeric_limits<float>::quiet_NaN(), 6.f) == 0.f);
	assert(MarkerVisibility::magnitudeOpacity(1.f, 6.f, 0.f) == 0.f);
}
