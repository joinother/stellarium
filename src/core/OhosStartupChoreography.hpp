/*
 * Sky Instrument / Stellarium HarmonyOS Startup Diorama Choreography
 *
 * Orchestrates the in-engine post-load theatrical reveal:
 *   Beat 1 (0.00s - 1.65s): Unlit dark planetarium dome with restrained
 *     meridian/altitude wireframe lines; real landscape (staggered trees /
 *     buildings or layered Mist Mountain ridges) pops up from the horizon
 *     in dark silhouette with mechanical spring overshoot.
 *   Beat 2 (1.68s - 2.95s):
 *     - Daytime (Sun alt > -6 deg): Sudden solar flash from the EXACT
 *       projected real Sun position (or true solar azimuth edge) washes out
 *       the dome lines and instantaneously illuminates atmosphere & landscape.
 *     - Nighttime (Sun alt <= -6 deg): Cool celestial starlight ripple sweeps
 *       across the dome, dissolving the dome lines and igniting the REAL
 *       Stellarium starfield by magnitude cascade (planets & bright stars
 *       first with subtle sparkle -> constellations -> faint stars & Milky Way)
 *       at 100% exact live coordinates.
 *   Beat 3 (2.55s - 3.45s): Seamless handoff to live interactive star map
 *     with UI chrome fade-in. Zero per-frame cost once inactive.
 */

#ifndef OHOS_STARTUP_CHOREOGRAPHY_HPP
#define OHOS_STARTUP_CHOREOGRAPHY_HPP

#include <algorithm>
#include <cmath>
#include <mutex>

struct OhosStartupState
{
	enum class Phase
	{
		Inactive = 0,
		Armed    = 1, // Holding dark dome frame 0 while ArkTS StartupSky is visible
		Playing  = 2, // Active theatrical reveal
		Skipping = 3  // Fast 0.25s graceful finish on user tap/skip
	};

	Phase phase = Phase::Inactive;
	bool isDaytime = false;
	int forcedMode = 0; // 0 = auto from real Sun alt, 1 = force day, 2 = force night
	bool modeResolved = false;

	double armedAtRunTime = -1.0;
	double startRunTime = -1.0;
	double skipStartElapsed = 0.0;
	double skipStartRunTime = -1.0;
	float elapsed = 0.0f;
	float totalDuration = 3.35f;

	// Derived per-frame shader & module parameters (all normalized 0..1 unless noted)
	float landscapeLift = 2.0f;      // 0..1 during pop-up; 2.0 when inactive (fast-path bypass)
	float landscapeIllum = 1.0f;     // 0 = dark silhouette, 1 = full real lighting
	float atmosphereReveal = 1.0f;   // 0..1 multiplier on Atmosphere visualStrength
	float solarSystemReveal = 1.0f;  // 0..1 gate/fade for Sun/Moon/Planets
	float starfieldReveal = 1.0f;    // 0..1 gate for StarMgr
	float starMagCutoff = 99.0f;     // Sweeps -2.0 -> +7.5 -> 99.0 during night ignition
	float starSparkle = 0.0f;        // 0..1 envelope for crystalline ignition glimmer
	float milkyWayReveal = 1.0f;     // 0..1 multiplier for MilkyWay
	float nebulaReveal = 1.0f;       // 0..1 multiplier for NebulaMgr
	float constellationReveal = 1.0f;// 0..1 gate for ConstellationMgr/AsterismMgr
	float cardinalsReveal = 1.0f;    // 0..1 gate for CardinalPoints
	float domeGridAlpha = 0.0f;      // 0..1 restrained dark planetarium wireframe intensity
	float domeUnfold = 1.0f;         // 0..1 zenith-to-horizon wireframe draw progress
	float flashIntensity = 0.0f;     // 0..1 optical ignition burst (day solar / night ripple)
	float flashProgress = 0.0f;      // 0..1 normalized wave expansion progress
	float uiChromeOpacity = 1.0f;    // 0..1 reported back to ArkUI for HUD fade-in

	// Real Sun screen-space projection (normalized UV 0..1 in viewport, bottom-left origin)
	float sunScreenU = 0.5f;
	float sunScreenV = 0.62f;
	bool sunOnScreen = false;
};

class OhosStartupChoreography
{
public:
	// Start origami unfolding right as the StartupSky title dissolves out of the dark dome (zero dead pause).
	static constexpr float kLiftStartSec = 0.24f;
	static constexpr float kLiftEndSec   = 1.94f;
	static constexpr float kIgniteAtSec  = 2.02f;
	static constexpr float kDayTotalSec  = 3.45f;
	static constexpr float kNightTotalSec = 3.65f;
	static constexpr float kSkipFinishSec = 0.26f;

	static OhosStartupState& state()
	{
		static OhosStartupState s;
		return s;
	}

	static std::mutex& mutex()
	{
		static std::mutex m;
		return m;
	}

	static inline float clamp01(float x)
	{
		return x < 0.0f ? 0.0f : (x > 1.0f ? 1.0f : x);
	}

	static inline float smoothstep(float edge0, float edge1, float x)
	{
		if (edge1 <= edge0)
			return x >= edge1 ? 1.0f : 0.0f;
		const float t = clamp01((x - edge0) / (edge1 - edge0));
		return t * t * (3.0f - 2.0f * t);
	}

	static inline float easeOutCubic(float x)
	{
		const float t = 1.0f - clamp01(x);
		return 1.0f - t * t * t;
	}

	// Arm on initial cold boot so C++ holds dark dome frame 0 while ArkTS StartupSky covers it.
	static void armOnBoot(double nowRunTime)
	{
		std::lock_guard<std::mutex> lock(mutex());
		auto& s = state();
		s.phase = OhosStartupState::Phase::Armed;
		s.forcedMode = 0;
		s.modeResolved = false;
		s.armedAtRunTime = nowRunTime;
		s.startRunTime = -1.0;
		s.elapsed = 0.0f;
		applyParametersLocked(s);
	}

	// Triggered by ArkTS right when StartupSky begins revealing the live sky (or via replay command).
	static void begin(double nowRunTime, int forcedMode = 0)
	{
		std::lock_guard<std::mutex> lock(mutex());
		auto& s = state();
		s.phase = OhosStartupState::Phase::Playing;
		s.forcedMode = forcedMode;
		s.modeResolved = (forcedMode != 0);
		if (forcedMode == 1)
			s.isDaytime = true;
		else if (forcedMode == 2)
			s.isDaytime = false;
		s.totalDuration = s.isDaytime ? kDayTotalSec : kNightTotalSec;
		s.startRunTime = nowRunTime;
		s.elapsed = 0.0f;
		applyParametersLocked(s);
	}

	// Gracefully fast-forward to live star map on tap/key/CLI interaction.
	static void skip(double nowRunTime)
	{
		std::lock_guard<std::mutex> lock(mutex());
		auto& s = state();
		if (s.phase == OhosStartupState::Phase::Inactive)
			return;
		if (s.phase == OhosStartupState::Phase::Armed)
		{
			resetToInactiveLocked(s);
			return;
		}
		if (s.phase == OhosStartupState::Phase::Playing)
		{
			s.phase = OhosStartupState::Phase::Skipping;
			s.skipStartElapsed = static_cast<double>(s.elapsed);
			s.skipStartRunTime = nowRunTime;
		}
	}

	static void forceFinishImmediate()
	{
		std::lock_guard<std::mutex> lock(mutex());
		resetToInactiveLocked(state());
	}

	// Called once per render frame before StelApp::draw() with real Sun altitude & projected UV.
	static void updateFrame(double nowRunTime, double sunAltDeg, float sunU, float sunV, bool sunVisible)
	{
		std::lock_guard<std::mutex> lock(mutex());
		auto& s = state();
		if (s.phase == OhosStartupState::Phase::Inactive)
			return;

		s.sunScreenU = sunU;
		s.sunScreenV = sunV;
		s.sunOnScreen = sunVisible;

		if (!s.modeResolved)
		{
			if (s.forcedMode == 1)
				s.isDaytime = true;
			else if (s.forcedMode == 2)
				s.isDaytime = false;
			else
				s.isDaytime = (sunAltDeg > -6.0);
			s.totalDuration = s.isDaytime ? kDayTotalSec : kNightTotalSec;
			s.modeResolved = true;
		}

		if (s.phase == OhosStartupState::Phase::Armed)
		{
			// Safety failsafe: if ArkTS never calls begin() within 18s after first GL frame,
			// auto-start so the screen can never stay permanently dark.
			if (s.armedAtRunTime >= 0.0 && (nowRunTime - s.armedAtRunTime) > 18.0)
			{
				s.phase = OhosStartupState::Phase::Playing;
				s.startRunTime = nowRunTime;
				s.elapsed = 0.0f;
			}
			else
			{
				s.elapsed = 0.0f;
				applyParametersLocked(s);
				return;
			}
		}

		if (s.phase == OhosStartupState::Phase::Playing)
		{
			if (s.startRunTime < 0.0)
				s.startRunTime = nowRunTime;
			s.elapsed = static_cast<float>(std::max(0.0, nowRunTime - s.startRunTime));
			if (s.elapsed >= s.totalDuration)
			{
				resetToInactiveLocked(s);
				return;
			}
			applyParametersLocked(s);
			return;
		}

		if (s.phase == OhosStartupState::Phase::Skipping)
		{
			const float p = clamp01(static_cast<float>((nowRunTime - s.skipStartRunTime) / static_cast<double>(kSkipFinishSec)));
			s.elapsed = static_cast<float>(s.skipStartElapsed) + (s.totalDuration - static_cast<float>(s.skipStartElapsed)) * easeOutCubic(p);
			if (p >= 1.0f || s.elapsed >= s.totalDuration)
			{
				resetToInactiveLocked(s);
				return;
			}
			applyParametersLocked(s);
		}
	}

	// Fast thread-safe snapshot getters for rendering modules.
	static inline bool isActive()
	{
		return state().phase != OhosStartupState::Phase::Inactive;
	}

	static inline bool isPlaying()
	{
		const auto p = state().phase;
		return p == OhosStartupState::Phase::Playing || p == OhosStartupState::Phase::Skipping;
	}

	static inline float landscapeLift() { return state().landscapeLift; }
	static inline float landscapeIllum() { return state().landscapeIllum; }
	static inline float atmosphereScale() { return state().atmosphereReveal; }
	static inline float solarSystemScale() { return state().solarSystemReveal; }
	static inline float starfieldScale() { return state().starfieldReveal; }
	static inline float starMagCutoff() { return state().starMagCutoff; }
	static inline float starSparkle() { return state().starSparkle; }
	static inline float milkyWayScale() { return state().milkyWayReveal; }
	static inline float nebulaScale() { return state().nebulaReveal; }
	static inline float constellationScale() { return state().constellationReveal; }
	static inline bool cardinalsVisible() { return state().cardinalsReveal > 0.05f; }
	static inline float domeGridAlpha() { return state().domeGridAlpha; }
	static inline float domeUnfold() { return state().domeUnfold; }
	static inline float flashIntensity() { return state().flashIntensity; }
	static inline float flashProgress() { return state().flashProgress; }
	static inline float uiChromeOpacity() { return state().uiChromeOpacity; }

private:
	static void resetToInactiveLocked(OhosStartupState& s)
	{
		s.phase = OhosStartupState::Phase::Inactive;
		s.elapsed = s.totalDuration;
		s.landscapeLift = 2.0f;
		s.landscapeIllum = 1.0f;
		s.atmosphereReveal = 1.0f;
		s.solarSystemReveal = 1.0f;
		s.starfieldReveal = 1.0f;
		s.starMagCutoff = 99.0f;
		s.starSparkle = 0.0f;
		s.milkyWayReveal = 1.0f;
		s.nebulaReveal = 1.0f;
		s.constellationReveal = 1.0f;
		s.cardinalsReveal = 1.0f;
		s.domeGridAlpha = 0.0f;
		s.domeUnfold = 1.0f;
		s.flashIntensity = 0.0f;
		s.flashProgress = 0.0f;
		s.uiChromeOpacity = 1.0f;
	}

	static void applyParametersLocked(OhosStartupState& s)
	{
		const float t = s.elapsed;

		// Beat 1: Landscape staggered pop-up (0.14s -> 1.62s)
		if (t <= kLiftStartSec)
			s.landscapeLift = 0.0f;
		else if (t >= kLiftEndSec)
			s.landscapeLift = 1.0f;
		else
			s.landscapeLift = (t - kLiftStartSec) / (kLiftEndSec - kLiftStartSec);

		// Restrained dark planetarium meridian/altitude dome lines:
		// Present during dark handoff & landscape rise, dissolve sharply at ignition.
		const float domeIn = 0.55f + 0.45f * smoothstep(0.0f, 0.45f, t);
		const float domePulse = 0.88f + 0.12f * std::sin(t * 2.5f);
		const float domeOut = 1.0f - smoothstep(kIgniteAtSec, kIgniteAtSec + 0.24f, t);
		s.domeGridAlpha = clamp01(domeIn * domePulse * domeOut);
		s.domeUnfold = 0.52f + 0.48f * easeOutCubic(t / 0.65f);

		if (s.isDaytime)
		{
			// DAYTIME: Dark silhouette stage -> sudden solar flash from real Sun -> full daylight
			const float igniteU = clamp01((t - kIgniteAtSec) / 0.46f);
			s.atmosphereReveal = easeOutCubic(igniteU);
			s.landscapeIllum = easeOutCubic(clamp01((t - kIgniteAtSec) / 0.42f));
			s.solarSystemReveal = smoothstep(kIgniteAtSec, kIgniteAtSec + 0.20f, t);
			s.starfieldReveal = smoothstep(kIgniteAtSec + 0.04f, kIgniteAtSec + 0.44f, t);
			s.starMagCutoff = 99.0f;
			s.starSparkle = 0.0f;
			s.milkyWayReveal = smoothstep(kIgniteAtSec + 0.12f, kIgniteAtSec + 0.55f, t);
			s.nebulaReveal = smoothstep(kIgniteAtSec + 0.15f, kIgniteAtSec + 0.60f, t);
			s.constellationReveal = smoothstep(kIgniteAtSec + 0.25f, kIgniteAtSec + 0.70f, t);
			s.cardinalsReveal = smoothstep(kIgniteAtSec + 0.45f, kIgniteAtSec + 0.85f, t);

			// Solar flash burst: crisp 90ms rise to peak, graceful 0.82s warm optical decay
			if (t < kIgniteAtSec)
			{
				s.flashIntensity = 0.0f;
				s.flashProgress = 0.0f;
			}
			else
			{
				const float ft = t - kIgniteAtSec;
				s.flashProgress = clamp01(ft / 0.90f);
				if (ft < 0.09f)
					s.flashIntensity = easeOutCubic(ft / 0.09f);
				else
				{
					const float decay = 1.0f - clamp01((ft - 0.09f) / 0.82f);
					s.flashIntensity = decay * decay * std::sqrt(decay);
				}
			}

			s.uiChromeOpacity = smoothstep(2.80f, 3.35f, t);
		}
		else
		{
			// NIGHTTIME: Dark silhouette stage -> celestial ripple -> magnitude-cascaded real star ignition
			s.atmosphereReveal = smoothstep(kIgniteAtSec + 0.08f, kIgniteAtSec + 0.88f, t);
			s.landscapeIllum = smoothstep(kIgniteAtSec + 0.06f, kIgniteAtSec + 0.88f, t);
			s.solarSystemReveal = smoothstep(kIgniteAtSec + 0.02f, kIgniteAtSec + 0.42f, t);

			if (t < kIgniteAtSec)
			{
				s.starfieldReveal = 0.0f;
				s.starMagCutoff = -10.0f;
				s.starSparkle = 0.0f;
			}
			else
			{
				const float starU = clamp01((t - kIgniteAtSec) / 1.32f);
				s.starfieldReveal = smoothstep(kIgniteAtSec, kIgniteAtSec + 0.10f, t);
				s.starMagCutoff = (starU >= 0.985f) ? 99.0f : (-2.0f + 9.8f * std::pow(starU, 1.22f));
				s.starSparkle = std::sin(starU * 3.14159265f);
			}

			s.milkyWayReveal = smoothstep(kIgniteAtSec + 0.36f, kIgniteAtSec + 1.32f, t);
			s.nebulaReveal = smoothstep(kIgniteAtSec + 0.45f, kIgniteAtSec + 1.38f, t);
			s.constellationReveal = smoothstep(kIgniteAtSec + 0.55f, kIgniteAtSec + 1.25f, t);
			s.cardinalsReveal = smoothstep(kIgniteAtSec + 0.65f, kIgniteAtSec + 1.15f, t);

			// Cool silver-blue celestial starlight ripple wave across dome
			if (t < kIgniteAtSec)
			{
				s.flashIntensity = 0.0f;
				s.flashProgress = 0.0f;
			}
			else
			{
				const float ft = t - kIgniteAtSec;
				s.flashProgress = clamp01(ft / 0.85f);
				if (ft < 0.12f)
					s.flashIntensity = easeOutCubic(ft / 0.12f);
				else
				{
					const float decay = 1.0f - clamp01((ft - 0.12f) / 0.74f);
					s.flashIntensity = decay * decay;
				}
			}

			s.uiChromeOpacity = smoothstep(2.95f, 3.55f, t);
		}
	}
};

#endif // OHOS_STARTUP_CHOREOGRAPHY_HPP
