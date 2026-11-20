#ifndef ENVIRONMENT_ZOOM_FADE_HPP
#define ENVIRONMENT_ZOOM_FADE_HPP

#include <algorithm>
#include <cmath>

namespace EnvironmentZoomFade
{
constexpr double MIST_FADE_START_FOV = 14.0;
constexpr double MIST_FADE_END_FOV = 4.0;
constexpr double ENV_FADE_START_FOV = 10.0;
constexpr double ENV_FADE_END_FOV = 2.0;

inline float smoothFactor(double fovDegrees, double fadeEndDegrees, double fadeStartDegrees)
{
	if (!std::isfinite(fovDegrees))
		return 1.f;
	const double span = fadeStartDegrees - fadeEndDegrees;
	if (span <= 0.0)
		return fovDegrees >= fadeStartDegrees ? 1.f : 0.f;
	const double t = std::max(0.0, std::min(1.0, (fovDegrees - fadeEndDegrees) / span));
	return static_cast<float>(t * t * (3.0 - 2.0 * t));
}

inline float mistVisibility(double fovDegrees)
{
	return smoothFactor(fovDegrees, MIST_FADE_END_FOV, MIST_FADE_START_FOV);
}

inline float environmentVisibility(bool enabled, double fovDegrees)
{
	if (!enabled)
		return 1.f;
	return smoothFactor(fovDegrees, ENV_FADE_END_FOV, ENV_FADE_START_FOV);
}

inline double combinedLandscapeTransparency(double baseTransparency, float envVisibility)
{
	const double clampedBase = std::isfinite(baseTransparency)
		? std::max(0.0, std::min(1.0, baseTransparency))
		: 0.0;
	const double clampedEnv = std::isfinite(envVisibility)
		? std::max(0.0, std::min(1.0, static_cast<double>(envVisibility)))
		: 1.0;
	return 1.0 - (1.0 - clampedBase) * clampedEnv;
}
}

#endif // ENVIRONMENT_ZOOM_FADE_HPP
