#ifndef ATMOSPHERE_VIVID_HPP
#define ATMOSPHERE_VIVID_HPP

namespace AtmosphereVivid
{
inline const char* shaderSource()
{
	return R"(
uniform float vividStrength;

vec3 vividAtmosphereColor(vec3 original, vec3 viewDirection, vec3 solarDirection, float strength)
{
	if (strength <= 0.) return original;
	float solarElevation = degrees(asin(clamp(solarDirection.z, -1., 1.)));
	float height = abs(viewDirection.z);
	float horizon = 1. - smoothstep(0.02, 0.55, height);
	float horizontalNorm = sqrt((viewDirection.x * viewDirection.x + viewDirection.y * viewDirection.y)
	                         * (solarDirection.x * solarDirection.x + solarDirection.y * solarDirection.y));
	float alignment = (viewDirection.x * solarDirection.x + viewDirection.y * solarDirection.y) / max(horizontalNorm, 0.0001);
	float sunward = smoothstep(-0.35, 0.9, alignment);
	float daylight = smoothstep(-6., 12., solarElevation);
	float twilight = smoothstep(-18., -6., solarElevation) * (1. - smoothstep(-1., 12., solarElevation));
	vec3 daytime = mix(vec3(0.22, 0.52, 0.96), vec3(0.50, 0.72, 1.), horizon);
	vec3 palette = mix(vec3(0.10, 0.18, 0.46), daytime, daylight);
	vec3 dusk = mix(vec3(0.34, 0.28, 0.48), vec3(1., 0.36, 0.10), horizon * sunward);
	palette = mix(palette, dusk, twilight * (0.35 + 0.65 * horizon));
	float luminance = max(dot(original, vec3(0.2126, 0.7152, 0.0722)), 0.);
	float scale = luminance / max(dot(palette, vec3(0.2126, 0.7152, 0.0722)), 0.0001);
	vec3 target = vec3(palette.r * scale, palette.g * scale, palette.b * scale);
	float peak = max(target.r, max(target.g, target.b));
	float gamut = min(1., max(1. - luminance, 0.) / max(peak - luminance, 0.0001));
	target = mix(vec3(luminance), target, gamut);
	float amount = 0.78 * smoothstep(0.02, 0.9, strength);
	return mix(original, target, amount);
}
)";
}
}

#endif
