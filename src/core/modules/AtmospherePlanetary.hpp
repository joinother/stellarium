#ifndef ATMOSPHERE_PLANETARY_HPP
#define ATMOSPHERE_PLANETARY_HPP

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <string>

namespace AtmospherePlanetary
{
struct Color
{
	float r = 0.f;
	float g = 0.f;
	float b = 0.f;
};

struct Profile
{
	const char* id = "earth";
	float mixStrength = 0.f;
	float luminanceScale = 1.f;
	float hazeExponent = 1.f;
	float sunHaloStrength = 0.f;
	float zenithAttenuation = 1.f;
	Color zenithColor = {0.22f, 0.52f, 0.96f};
	Color horizonColor = {0.50f, 0.72f, 1.00f};
	Color twilightZenith = {0.10f, 0.18f, 0.46f};
	Color twilightHorizon = {1.00f, 0.36f, 0.10f};
	Color sunHaloColor = {1.00f, 0.96f, 0.88f};
};

inline const Profile& earthProfile()
{
	static constexpr Profile kEarth{
		"earth",
		0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
		{0.22f, 0.52f, 0.96f},
		{0.50f, 0.72f, 1.00f},
		{0.10f, 0.18f, 0.46f},
		{1.00f, 0.36f, 0.10f},
		{1.00f, 0.96f, 0.88f}
	};
	return kEarth;
}

inline const Profile& profileForPlanet(const std::string& englishName)
{
	std::string key;
	key.reserve(englishName.size());
	for (const unsigned char ch : englishName)
	{
		if (!std::isspace(ch))
			key.push_back(static_cast<char>(std::tolower(ch)));
	}

	static constexpr std::array<Profile, 9> kProfiles{{
		// Mars: iron-oxide dusty butterscotch sky, iconic blue sunset near the solar limb
		{
			"mars",
			0.96f, 0.35f, 0.58f, 0.65f, 1.0f,
			{0.62f, 0.41f, 0.29f},
			{0.90f, 0.63f, 0.42f},
			{0.36f, 0.27f, 0.34f},
			{0.36f, 0.64f, 0.98f},
			{0.58f, 0.78f, 1.00f}
		},
		// Venus: dense sulfuric-acid cloud overcast with warm golden-amber daylight
		{
			"venus",
			0.97f, 0.45f, 0.36f, 0.72f, 1.0f,
			{0.92f, 0.72f, 0.32f},
			{0.98f, 0.85f, 0.48f},
			{0.52f, 0.30f, 0.12f},
			{0.88f, 0.44f, 0.14f},
			{1.00f, 0.91f, 0.62f}
		},
		// Titan: thick nitrogen/methane tholin haze glowing burnt orange-amber
		{
			"titan",
			0.97f, 0.065f, 0.34f, 0.68f, 1.0f,
			{0.76f, 0.40f, 0.13f},
			{0.95f, 0.58f, 0.20f},
			{0.36f, 0.16f, 0.06f},
			{0.68f, 0.26f, 0.08f},
			{0.98f, 0.74f, 0.34f}
		},
		// Jupiter: deep H2/He Rayleigh sapphire overhead fading to warm golden-cream ammonia haze
		{
			"jupiter",
			0.94f, 0.09f, 1.45f, 0.38f, 1.0f,
			{0.14f, 0.40f, 0.86f},
			{0.90f, 0.72f, 0.44f},
			{0.10f, 0.22f, 0.50f},
			{0.84f, 0.50f, 0.24f},
			{0.96f, 0.88f, 0.72f}
		},
		// Saturn: slate-cerulean upper sky transitioning into warm butterscotch-gold haze
		{
			"saturn",
			0.94f, 0.055f, 1.15f, 0.42f, 1.0f,
			{0.26f, 0.46f, 0.76f},
			{0.92f, 0.76f, 0.44f},
			{0.18f, 0.26f, 0.44f},
			{0.86f, 0.56f, 0.24f},
			{0.96f, 0.88f, 0.64f}
		},
		// Uranus: methane red-absorbing ethereal cyan-teal atmosphere
		{
			"uranus",
			0.95f, 0.032f, 0.72f, 0.32f, 1.0f,
			{0.18f, 0.62f, 0.74f},
			{0.56f, 0.88f, 0.90f},
			{0.09f, 0.30f, 0.42f},
			{0.26f, 0.58f, 0.68f},
			{0.74f, 0.94f, 0.96f}
		},
		// Neptune: deep azure-cobalt methane sky with electric cerulean horizon
		{
			"neptune",
			0.95f, 0.024f, 0.78f, 0.30f, 1.0f,
			{0.08f, 0.24f, 0.80f},
			{0.26f, 0.58f, 0.98f},
			{0.05f, 0.14f, 0.44f},
			{0.14f, 0.32f, 0.72f},
			{0.50f, 0.76f, 1.00f}
		},
		// Pluto: tenuous N2/CH4 haze — dark starry zenith, luminous ice-blue limb horizon
		{
			"pluto",
			0.96f, 0.012f, 2.40f, 0.50f, 0.06f,
			{0.03f, 0.06f, 0.14f},
			{0.34f, 0.64f, 0.94f},
			{0.02f, 0.05f, 0.12f},
			{0.28f, 0.56f, 0.88f},
			{0.56f, 0.80f, 1.00f}
		},
		// Triton: tenuous nitrogen haze — starry zenith with pale lavender-blue horizon glow
		{
			"triton",
			0.96f, 0.012f, 2.20f, 0.45f, 0.06f,
			{0.04f, 0.06f, 0.14f},
			{0.42f, 0.58f, 0.90f},
			{0.03f, 0.05f, 0.12f},
			{0.36f, 0.48f, 0.82f},
			{0.62f, 0.76f, 0.98f}
		}
	}};

	for (const auto& profile : kProfiles)
	{
		if (key == profile.id)
			return profile;
	}
	return earthProfile();
}

inline Color evaluateColor(const Profile& profile, const Color& original,
                           const std::array<float, 3>& viewDirection,
                           const std::array<float, 3>& solarDirection)
{
	if (profile.mixStrength <= 0.f)
		return original;

	auto clampf = [](float v, float lo, float hi) { return std::max(lo, std::min(hi, v)); };
	auto smoothstep = [&](float edge0, float edge1, float x) {
		const float t = clampf((x - edge0) / (edge1 - edge0), 0.f, 1.f);
		return t * t * (3.f - 2.f * t);
	};
	auto mixf = [](float a, float b, float t) { return a + (b - a) * t; };
	auto mixc = [&](const Color& a, const Color& b, float t) -> Color {
		return {mixf(a.r, b.r, t), mixf(a.g, b.g, t), mixf(a.b, b.b, t)};
	};

	const float viewLen = std::sqrt(viewDirection[0] * viewDirection[0] + viewDirection[1] * viewDirection[1] + viewDirection[2] * viewDirection[2]);
	const float sunLen = std::sqrt(solarDirection[0] * solarDirection[0] + solarDirection[1] * solarDirection[1] + solarDirection[2] * solarDirection[2]);
	const std::array<float, 3> v = viewLen > 0.0001f
		? std::array<float, 3>{viewDirection[0] / viewLen, viewDirection[1] / viewLen, viewDirection[2] / viewLen}
		: std::array<float, 3>{0.f, 0.f, 1.f};
	const std::array<float, 3> s = sunLen > 0.0001f
		? std::array<float, 3>{solarDirection[0] / sunLen, solarDirection[1] / sunLen, solarDirection[2] / sunLen}
		: std::array<float, 3>{0.f, 0.f, -1.f};

	constexpr float radToDeg = 57.2957795f;
	const float solarElevation = std::asin(clampf(s[2], -1.f, 1.f)) * radToDeg;
	const float viewZ = clampf(std::abs(v[2]), 0.f, 1.f);
	const float horizon = std::pow(clampf(1.f - viewZ, 0.f, 1.f), std::max(profile.hazeExponent, 0.05f));

	const float horizNorm = std::sqrt(std::max((v[0] * v[0] + v[1] * v[1]) * (s[0] * s[0] + s[1] * s[1]), 0.f));
	const float horizAlign = (v[0] * s[0] + v[1] * s[1]) / std::max(horizNorm, 0.0001f);
	const float sunward = smoothstep(-0.35f, 0.92f, horizAlign);

	const float sunDot = clampf(v[0] * s[0] + v[1] * s[1] + v[2] * s[2], -1.f, 1.f);
	const float sunHaloWide = std::pow(std::max(sunDot, 0.f), 5.f);
	const float sunHaloTight = std::pow(std::max(sunDot, 0.f), 22.f);

	const float daylight = smoothstep(-8.f, 14.f, solarElevation);
	const float twilight = smoothstep(-18.f, -4.f, solarElevation) * (1.f - smoothstep(0.f, 16.f, solarElevation));
	const float sunVisible = smoothstep(-10.f, 4.f, solarElevation);

	const Color daySky = mixc(profile.zenithColor, profile.horizonColor, horizon);
	const Color duskSky = mixc(profile.twilightZenith, profile.twilightHorizon,
	                           std::pow(horizon, 0.85f) * (0.25f + 0.75f * sunward));
	const Color nightZenith = {
		profile.twilightZenith.r * 0.45f,
		profile.twilightZenith.g * 0.45f,
		profile.twilightZenith.b * 0.45f
	};
	const Color basePalette = mixc(nightZenith, daySky, daylight);
	Color palette = mixc(basePalette, duskSky, twilight * (0.30f + 0.70f * horizon * (0.35f + 0.65f * sunward)));

	const float haloMix = clampf(profile.sunHaloStrength * sunVisible * (0.35f * sunHaloWide + 0.65f * sunHaloTight), 0.f, 0.85f);
	palette = mixc(palette, profile.sunHaloColor, haloMix);

	const float luminance = std::max(0.2126f * original.r + 0.7152f * original.g + 0.0722f * original.b, 0.f);
	const float origPeak = std::max(original.r, std::max(original.g, original.b));
	const float zenithAtten = mixf(profile.zenithAttenuation, 1.f, horizon);
	const float skyIntensity = clampf(mixf(luminance, origPeak, 0.45f) * zenithAtten * (1.f + 0.15f * haloMix), 0.f, 1.f);
	const float palPeak = std::max(palette.r, std::max(palette.g, palette.b));
	const float normScale = skyIntensity / std::max(palPeak, 0.0001f);
	Color target = {palette.r * normScale, palette.g * normScale, palette.b * normScale};

	const float coreBloom = clampf(0.28f * sunHaloTight * sunVisible * profile.sunHaloStrength, 0.f, 0.45f);
	const float bloomVal = std::min(skyIntensity * 1.1f, 1.f);
	target = mixc(target, {bloomVal, bloomVal, bloomVal}, coreBloom);

	return mixc(original, target, clampf(profile.mixStrength, 0.f, 1.f));
}

inline const char* shaderSource()
{
	return R"(
uniform vec3 planetZenithColor;
uniform vec3 planetHorizonColor;
uniform vec3 planetTwilightZenith;
uniform vec3 planetTwilightHorizon;
uniform vec3 planetSunHaloColor;
uniform vec4 planetAtmoParams;

vec3 planetaryAtmosphereColor(vec3 original, vec3 viewDirection, vec3 solarDirection)
{
	if (planetAtmoParams.x <= 0.) return original;
	vec3 v = normalize(viewDirection);
	vec3 s = normalize(solarDirection);
	float solarElevation = degrees(asin(clamp(s.z, -1., 1.)));
	float viewZ = clamp(abs(v.z), 0., 1.);
	float horizonBase = clamp(1. - viewZ, 0., 1.);
	float horizon = horizonBase > 0.00001 ? pow(horizonBase, max(planetAtmoParams.y, 0.05)) : 0.;
	float horizNorm = sqrt(max((v.x * v.x + v.y * v.y) * (s.x * s.x + s.y * s.y), 0.));
	float horizAlign = (v.x * s.x + v.y * s.y) / max(horizNorm, 0.0001);
	float sunward = smoothstep(-0.35, 0.92, horizAlign);
	float sunDot = clamp(dot(v, s), -1., 1.);
	float sunHaloWide = sunDot > 0.0001 ? pow(sunDot, 5.) : 0.;
	float sunHaloTight = sunDot > 0.0001 ? pow(sunDot, 22.) : 0.;
	float daylight = smoothstep(-8., 14., solarElevation);
	float twilight = smoothstep(-18., -4., solarElevation) * (1. - smoothstep(0., 16., solarElevation));
	float sunVisible = smoothstep(-10., 4., solarElevation);
	vec3 daySky = mix(planetZenithColor, planetHorizonColor, horizon);
	float duskHorizon = horizon > 0.00001 ? pow(horizon, 0.85) : 0.;
	vec3 duskSky = mix(planetTwilightZenith, planetTwilightHorizon, duskHorizon * (0.25 + 0.75 * sunward));
	vec3 nightZenith = planetTwilightZenith * 0.45;
	vec3 basePalette = mix(nightZenith, daySky, daylight);
	vec3 palette = mix(basePalette, duskSky, twilight * (0.30 + 0.70 * horizon * (0.35 + 0.65 * sunward)));
	float haloMix = clamp(planetAtmoParams.z * sunVisible * (0.35 * sunHaloWide + 0.65 * sunHaloTight), 0., 0.85);
	palette = mix(palette, planetSunHaloColor, haloMix);
	float luminance = max(dot(original, vec3(0.2126, 0.7152, 0.0722)), 0.);
	float origPeak = max(original.r, max(original.g, original.b));
	float zenithAtten = mix(planetAtmoParams.w, 1., horizon);
	float skyIntensity = clamp(mix(luminance, origPeak, 0.45) * zenithAtten * (1. + 0.15 * haloMix), 0., 1.);
	float palPeak = max(palette.r, max(palette.g, palette.b));
	vec3 target = palette * (skyIntensity / max(palPeak, 0.0001));
	float coreBloom = clamp(0.28 * sunHaloTight * sunVisible * planetAtmoParams.z, 0., 0.45);
	target = mix(target, vec3(min(skyIntensity * 1.1, 1.)), coreBloom);
	return mix(original, target, clamp(planetAtmoParams.x, 0., 1.));
}
)";
}
}

#endif // ATMOSPHERE_PLANETARY_HPP
