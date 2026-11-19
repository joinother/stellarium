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

struct CenterLineAnimation
{
	static constexpr double kDuration = 1.05;
	bool active = false;
	double rawProgress = 1.0;

	double update(double deltaTime, bool featureEnabled, bool eligible, double currentLinePresentation)
	{
		if (!featureEnabled)
		{
			active = false;
			rawProgress = 1.0;
			return 1.0;
		}
		if (eligible)
		{
			if (!active)
			{
				active = true;
				if (currentLinePresentation < 0.08)
					rawProgress = 0.0;
			}
			rawProgress = std::min(1.0, rawProgress + std::max(0.0, deltaTime) / kDuration);
			return smooth(rawProgress);
		}
		active = false;
		if (currentLinePresentation <= 0.02)
			rawProgress = 0.0;
		return smooth(rawProgress);
	}
};

inline double segmentDrawFraction(double overallProgress, int segmentIndex, int segmentCount)
{
	if (segmentCount <= 0 || overallProgress >= 0.999)
		return 1.0;
	if (overallProgress <= 0.001)
		return 0.0;
	if (segmentCount == 1)
		return smooth(overallProgress);
	const double staggerSpan = 0.62;
	const double segDuration = 1.0 - staggerSpan;
	const double start = (static_cast<double>(std::clamp(segmentIndex, 0, segmentCount - 1)) /
	                      static_cast<double>(segmentCount - 1)) * staggerSpan;
	return smooth((overallProgress - start) / segDuration);
}
}

#endif
