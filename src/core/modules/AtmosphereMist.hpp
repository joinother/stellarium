#ifndef ATMOSPHERE_MIST_HPP
#define ATMOSPHERE_MIST_HPP

#include <algorithm>
#include <cmath>

namespace AtmosphereMist
{
inline float displayStrength(bool earth, bool landscape, bool scene, float mistOpacity)
{
	if (!earth || landscape || scene || !std::isfinite(mistOpacity)) return 0.f;
	return std::max(0.f, std::min(1.f, mistOpacity));
}

inline const char* shaderSource()
{
	return R"(
uniform highp float mistUndergroundStrength;

highp float mistAtmosphereTransmission(highp float worldZ)
{
	highp float altitude = degrees(asin(clamp(worldZ, -1., 1.)));
	return mix(1., smoothstep(-15., -3., altitude), mistUndergroundStrength);
}
)";
}
}

#endif
