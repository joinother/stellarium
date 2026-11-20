#ifndef PLANETARY_CALENDAR_HELPER_HPP
#define PLANETARY_CALENDAR_HELPER_HPP

#include "AtmospherePlanetary.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <limits>
#include <string>

namespace PlanetaryCalendarHelper
{
struct SkyGradientHex
{
	std::string topHex;
	std::string horizonHex;
};

struct BodyMeta
{
	const char* englishName = "Earth";
	const char* nameZh = "地球";
	double semiMajorAxisAU = 1.0;
	const char* primaryCompanion = "Moon";
	const char* companionRole = "moon"; // "moon", "parent-planet", "bright-planet"
	double vernalEquinoxHelioLonDeg = std::numeric_limits<double>::quiet_NaN();
};

inline std::string normalizeKey(const std::string& name)
{
	std::string out;
	out.reserve(name.size());
	for (const unsigned char ch : name)
	{
		if (!std::isspace(ch))
			out.push_back(static_cast<char>(std::tolower(ch)));
	}
	return out;
}

inline const BodyMeta& metaForPlanet(const std::string& englishName)
{
	const std::string key = normalizeKey(englishName);
	static constexpr std::array<BodyMeta, 20> kBodies{{
		{"Mercury",  "水星",   0.3871, "Venus",   "bright-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Venus",    "金星",   0.7233, "Earth",   "bright-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Earth",    "地球",   1.0000, "Moon",    "moon",          0.0},
		{"Moon",     "月球",   1.0000, "Earth",   "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Mars",     "火星",   1.5237, "Phobos",  "moon",          85.07},
		{"Phobos",   "火卫一", 1.5237, "Mars",    "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Deimos",   "火卫二", 1.5237, "Mars",    "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Jupiter",  "木星",   5.2044, "Ganymede","moon",          std::numeric_limits<double>::quiet_NaN()},
		{"Io",       "木卫一", 5.2044, "Jupiter", "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Europa",   "木卫二", 5.2044, "Jupiter", "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Ganymede", "木卫三", 5.2044, "Jupiter", "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Callisto", "木卫四", 5.2044, "Jupiter", "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Saturn",   "土星",   9.5826, "Titan",   "moon",          std::numeric_limits<double>::quiet_NaN()},
		{"Titan",    "土卫六", 9.5826, "Saturn",  "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Enceladus","土卫二", 9.5826, "Saturn",  "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Rhea",     "土卫五", 9.5826, "Saturn",  "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Uranus",   "天王星",19.1913, "Titania", "moon",          std::numeric_limits<double>::quiet_NaN()},
		{"Neptune",  "海王星",30.0700, "Triton",  "moon",          std::numeric_limits<double>::quiet_NaN()},
		{"Triton",   "海卫一",30.0700, "Neptune", "parent-planet", std::numeric_limits<double>::quiet_NaN()},
		{"Pluto",    "冥王星",39.4820, "Charon",  "moon",          std::numeric_limits<double>::quiet_NaN()}
	}};
	for (const auto& body : kBodies)
	{
		if (normalizeKey(body.englishName) == key)
			return body;
	}
	return kBodies[2]; // Earth fallback
}

inline bool isEarthName(const std::string& englishName)
{
	const std::string key = normalizeKey(englishName);
	return key.empty() || key == "earth";
}

inline double illuminationPercent(const std::array<double, 3>& observerToTarget,
                                  const std::array<double, 3>& sunToTarget)
{
	auto norm = [](const std::array<double, 3>& v) {
		return std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
	};
	const double n1 = norm(observerToTarget);
	const double n2 = norm(sunToTarget);
	if (!std::isfinite(n1) || !std::isfinite(n2) || n1 <= 1e-12 || n2 <= 1e-12)
		return 0.0;
	// Phase angle is angle between target->sun (-sunToTarget) and target->observer (-observerToTarget),
	// whose cosine equals dot(sunToTarget, observerToTarget) / (n1 * n2).
	const double cosPhase = std::max(-1.0, std::min(1.0,
		(observerToTarget[0] * sunToTarget[0] +
		 observerToTarget[1] * sunToTarget[1] +
		 observerToTarget[2] * sunToTarget[2]) / (n1 * n2)));
	return 50.0 * (1.0 + cosPhase);
}

inline std::string companionPhaseLabelZh(double illumPercent, bool waxing, const std::string& bodyZh)
{
	if (illumPercent < 3.0) return "新" + bodyZh;
	if (illumPercent > 97.0) return "满" + bodyZh;
	if (illumPercent < 42.0) return waxing ? ("蛾眉" + bodyZh) : ("残" + bodyZh);
	if (illumPercent <= 58.0) return waxing ? ("上弦" + bodyZh) : ("下弦" + bodyZh);
	return waxing ? ("盈凸" + bodyZh) : ("亏凸" + bodyZh);
}

inline std::string rgbToHex(float r, float g, float b)
{
	auto toByte = [](float c) -> int {
		if (!std::isfinite(c)) return 0;
		const float clamped = std::max(0.f, std::min(1.f, c));
		return static_cast<int>(std::lround(clamped * 255.f));
	};
	char buf[8];
	std::snprintf(buf, sizeof(buf), "#%02X%02X%02X", toByte(r), toByte(g), toByte(b));
	return std::string(buf);
}

inline SkyGradientHex skyHexForSunAltitude(const std::string& planetEnglishName,
                                           bool hasAtmosphere,
                                           double sunAltDeg)
{
	if (!hasAtmosphere || !std::isfinite(sunAltDeg))
		return {"#05070D", "#0E1320"};

	auto clampf = [](float v, float lo, float hi) { return std::max(lo, std::min(hi, v)); };
	auto smoothstep = [&](float e0, float e1, float x) {
		const float t = clampf((x - e0) / (e1 - e0), 0.f, 1.f);
		return t * t * (3.f - 2.f * t);
	};
	auto mixc = [](const AtmospherePlanetary::Color& a, const AtmospherePlanetary::Color& b, float t) {
		return AtmospherePlanetary::Color{
			a.r + (b.r - a.r) * t,
			a.g + (b.g - a.g) * t,
			a.b + (b.b - a.b) * t
		};
	};

	const auto& profile = AtmospherePlanetary::profileForPlanet(planetEnglishName);
	const float alt = static_cast<float>(sunAltDeg);
	const float daylight = smoothstep(-8.f, 14.f, alt);
	const float twilight = smoothstep(-18.f, -4.f, alt) * (1.f - smoothstep(0.f, 14.f, alt));

	const AtmospherePlanetary::Color nightTop{0.03f, 0.05f, 0.11f};
	const AtmospherePlanetary::Color nightHorizon{0.07f, 0.10f, 0.19f};

	AtmospherePlanetary::Color dayTop = profile.zenithColor;
	AtmospherePlanetary::Color dayHor = profile.horizonColor;
	if (profile.zenithAttenuation < 0.25f)
	{
		// Tenuous atmospheres (Pluto/Triton) stay dark starry overhead while glowing near the horizon
		dayTop = mixc(nightTop, profile.zenithColor, 0.35f);
	}
	else if (profile.luminanceScale < 0.08f)
	{
		// Outer worlds keep richer, deeper daylight luminance
		const float dim = 0.65f + 0.35f * clampf(profile.luminanceScale / 0.08f, 0.f, 1.f);
		dayTop = {dayTop.r * dim, dayTop.g * dim, dayTop.b * dim};
		dayHor = {dayHor.r * dim, dayHor.g * dim, dayHor.b * dim};
	}

	AtmospherePlanetary::Color top = mixc(nightTop, dayTop, daylight);
	AtmospherePlanetary::Color hor = mixc(nightHorizon, dayHor, daylight);
	top = mixc(top, profile.twilightZenith, twilight * 0.72f);
	hor = mixc(hor, profile.twilightHorizon, twilight * 0.88f);

	return {rgbToHex(top.r, top.g, top.b), rgbToHex(hor.r, hor.g, hor.b)};
}
}

#endif // PLANETARY_CALENDAR_HELPER_HPP
