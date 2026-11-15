#ifndef CONSTELLATION_PRESENTATION_HPP
#define CONSTELLATION_PRESENTATION_HPP

#include <algorithm>
#include <cmath>

namespace ConstellationPresentation
{
struct CenterArrival
{
	bool armed = true;
	double elapsed = 1.6;
	double update(double deltaTime, double centralWeight, bool emphasized)
	{
		if (!emphasized)
		{
			armed = true;
			elapsed = 1.6;
			return 0.;
		}
		if (centralWeight < 0.65) armed = true;
		if (armed && emphasized && centralWeight > 0.96)
		{
			armed = false;
			elapsed = 0.;
		}
		else elapsed = std::min(1.6, elapsed + std::max(0., deltaTime));
		if (elapsed >= 1.6) return 0.;
		const double wave = std::sin(3.141592653589793 * elapsed / 1.6);
		return wave * wave;
	}
};

inline double smooth(double value)
{
	value = std::clamp(value, 0.0, 1.0);
	return value * value * (3.0 - 2.0 * value);
}

inline double zoomOpacity(double fovDegrees, double spanDegrees)
{
	const double ratio = fovDegrees / std::max(1.0, spanDegrees);
	return smooth((ratio - 0.25) / 0.65);
}

inline double centerWeight(double cosine, double fovDegrees)
{
	const double outer = std::clamp(fovDegrees * 0.55, 8.0, 65.0) * 0.017453292519943295;
	const double inner = outer * 0.25;
	return smooth((cosine - std::cos(outer)) / (std::cos(inner) - std::cos(outer)));
}
}

#endif
