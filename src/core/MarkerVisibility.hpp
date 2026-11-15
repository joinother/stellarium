#ifndef MARKER_VISIBILITY_HPP
#define MARKER_VISIBILITY_HPP

#include <algorithm>
#include <cmath>

namespace MarkerVisibility
{
inline float magnitudeOpacity(float magnitude, float limit, float width = 0.75f)
{
	if (!std::isfinite(magnitude) || !std::isfinite(limit) || !std::isfinite(width) || width <= 0.f)
		return 0.f;
	const float weight = std::clamp((limit - magnitude) / width, 0.f, 1.f);
	return weight * weight * (3.f - 2.f * weight);
}
}

#endif
