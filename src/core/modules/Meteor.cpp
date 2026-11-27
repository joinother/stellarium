/*
 * Stellarium
 * Copyright (C) 2014-2015 Marcos Cardinot
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Suite 500, Boston, MA  02110-1335, USA.
 */

#include "Meteor.hpp"
#include "StelCore.hpp"
#include "StelMovementMgr.hpp"
#include "StelPainter.hpp"
#include "StelProjector.hpp"
#include "StelTexture.hpp"
#include "StelUtils.hpp"
#include "StelApp.hpp"

#include <QtMath>
#include <cmath>

#define MAX_ALTITUDE 120.f           //! max meteor altitude in km
#define MIN_ALTITUDE 80.f            //! min meteor altitude in km

Meteor::Meteor(const StelCore* core, const StelTextureSP& bolideTexture)
	: m_core(core)
	, m_alive(false)
	, m_bypassDaylight(false)
	, m_rejectionReason(QStringLiteral("not-initialized"))
	, m_birthJd(0.)
	, m_burnDurationSec(0.)
	, m_totalLifetimeSec(0.)
	, m_breakupTimeSec(0.)
	, m_visibleAtSimTime(false)
	, m_speed(72.)
	, m_initialZ(1.)
	, m_finalZ(1.)
	, m_minDist(1.)
	, m_absMag(.5f)
	, m_aptMag(.5f)
	, m_peakAbsMag(.5f)
	, m_startDelay(0.f)
	, m_trainSeconds(0.55f)
	, m_widthScale(1.0f)
	, m_hasTerminalFlare(false)
	, m_flarePos(0.82f)
	, m_flareStrength(0.6f)
	, m_hasAfterglow(false)
	, m_afterglowRemaining(0.f)
	, m_afterglowDuration(0.f)
	, m_headExtinguished(false)
	, m_headFade(1.f)
	, m_headTintColor(0.78f, 0.96f, 0.88f)
	, m_afterglowColor(0.76f, 0.72f, 0.76f)
	, m_smokeCaptured(false)
	, m_smokeAgeSec(0.f)
	, m_smokeDurationSec(0.f)
	, m_smokeWindFreq(4.2f)
	, m_smokeWindPhase(0.f)
	, m_smokeWindPhase2(0.f)
	, m_smokeDriftRate(0.0025f)
	, m_smokeShearAxis1(1., 0., 0.)
	, m_smokeShearAxis2(0., 1., 0.)
	, m_archetype(Archetype::MicroNeedle)
	, m_lightCurveMode(0)
	, m_glareStyle(0)
	, m_glareSeed(1337u)
	, m_glareAngleOffset(0.28f)
	, m_burstProgress(0.66f)
	, m_burstFlash(0.f)
	, m_burstPeakMag(0.f)
	, m_burnTimeSec(0.f)
	, m_burstAltAzDir(0., 0., 1.)
	, m_burstTriggered(false)
	, m_bolideTexture(bolideTexture)
	, m_segments(48)
{
}

Meteor::~Meteor()
{
	m_bolideTexture.clear();
	m_outerColorVector.clear();
	m_coreColorVector.clear();
	m_lineColorVector.clear();
	m_trainColorVector.clear();
	m_fragments.clear();
}

void Meteor::configureMorphology(bool forceFireball, float speedKmS, const QList<ColorPair>& colors, int forcedArchetype)
{
	StelApp& app = StelApp::getInstance();
	const float r = app.getRandF();
	const bool isFast = speedKmS >= 46.f;

	// Reset persistent smoke, airburst glare & fragment breakup state
	m_smokeCaptured = false;
	m_smokeAgeSec = 0.f;
	m_smokeDurationSec = 0.f;
	m_smokeAnchors.clear();
	m_smokeWeights.clear();
	m_smokeU.clear();
	m_burstFlash = 0.f;
	m_burstPeakMag = 0.f;
	m_burnTimeSec = 0.f;
	m_burstTriggered = false;
	m_glareAngleOffset = 2.f * M_PIf * app.getRandF();
	m_glareSeed = static_cast<unsigned int>(1u + app.getRandF() * 2147483000.f);
	// Diverse natural glare styles so no two dazzling fireballs ever look stamped/identical:
	//   0: Pure soft atmospheric haze (no spikes, ~28%)
	//   1: Asymmetric 4-point cross flare (~22%)
	//   2: Elongated anamorphic streak glare (~18%)
	//   3: Organic uneven eyelash/corneal scatter rays (9..14 irregular fine filaments, ~20%)
	//   4: Classic 6- or 8-point aperture starburst with per-ray variance (~12%)
	const float gsRoll = app.getRandF();
	if (gsRoll < 0.28f) m_glareStyle = 0;
	else if (gsRoll < 0.50f) m_glareStyle = 1;
	else if (gsRoll < 0.68f) m_glareStyle = 2;
	else if (gsRoll < 0.88f) m_glareStyle = 3;
	else m_glareStyle = 4;
	m_lightCurveMode = 0;
	m_fragments.clear();

	// Pick physical meteor archetype with realistic naked-eye rarity:
	//   - MicroNeedle (~72%): razor-sharp hairline streak
	//   - SpectralStreak (~25%): Perseid-class multi-spectral needle (NO glare ring!)
	//   - AirburstBolide (~2%): rare intense airburst with soft atmospheric scattering flash + subtle glare halo
	//   - FragmentingSuperbolide (~1%): rare warm-gold bolide that splits into twin lead chunks + trailing sparks
	if (forcedArchetype >= 0 && forcedArchetype <= 3)
	{
		m_archetype = static_cast<Archetype>(forcedArchetype);
	}
	else if (forceFireball)
	{
		const float roll = app.getRandF();
		if (!isFast && roll < 0.22f)
			m_archetype = Archetype::FragmentingSuperbolide;
		else if (roll < 0.38f)
			m_archetype = Archetype::AirburstBolide;
		else
			m_archetype = Archetype::SpectralStreak;
	}
	else if (m_absMag >= 0.93f)
	{
		const float roll = app.getRandF();
		if (!isFast && roll < 0.14f)
			m_archetype = Archetype::FragmentingSuperbolide;
		else if (roll < 0.26f)
			m_archetype = Archetype::AirburstBolide;
		else
			m_archetype = Archetype::SpectralStreak;
	}
	else if (m_absMag >= 0.48f || r > 0.72f)
	{
		m_archetype = Archetype::SpectralStreak;
	}
	else
	{
		m_archetype = Archetype::MicroNeedle;
	}

	if (m_archetype == Archetype::FragmentingSuperbolide)
	{
		m_lightCurveMode = 2; // Gradual luminous build -> rounded breakup surge -> warm ember trail
		m_widthScale = 1.10f + 0.24f * app.getRandF();
		m_trainSeconds = 0.46f + 0.20f * app.getRandF();
		m_hasTerminalFlare = true;
		m_flarePos = 0.72f + 0.12f * app.getRandF();
		m_flareStrength = 1.15f + 0.45f * app.getRandF();
		m_burstProgress = 0.46f + 0.14f * app.getRandF();
		m_burstPeakMag = 0.92f + 0.22f * app.getRandF();
		m_hasAfterglow = true;
		m_afterglowDuration = 0.45f + 0.30f * app.getRandF();
		m_afterglowRemaining = m_afterglowDuration;
		m_smokeDurationSec = 7.5f + 3.0f * app.getRandF();
		m_smokeWindFreq = 3.2f + 2.4f * app.getRandF();
		m_smokeWindPhase = 2.f * M_PIf * app.getRandF();
		m_smokeWindPhase2 = 2.f * M_PIf * app.getRandF();
		m_smokeDriftRate = 0.0028f + 0.0022f * app.getRandF();
	}
	else if (m_archetype == Archetype::AirburstBolide)
	{
		// Real bolides either swell gradually across their flight (mode 0) or build slowly to a dazzling peak (mode 1)
		m_lightCurveMode = (app.getRandF() < 0.55f) ? 0 : 1;
		m_widthScale = 0.98f + 0.24f * app.getRandF();
		m_trainSeconds = 0.42f + 0.20f * app.getRandF();
		m_hasTerminalFlare = true;
		m_flarePos = 0.74f + 0.10f * app.getRandF();
		m_flareStrength = 1.15f + 0.45f * app.getRandF();
		m_burstProgress = (m_lightCurveMode == 0) ? (0.56f + 0.12f * app.getRandF()) : (0.70f + 0.10f * app.getRandF());
		m_burstPeakMag = 0.88f + 0.24f * app.getRandF();
		m_hasAfterglow = true;
		m_afterglowDuration = 0.50f + 0.35f * app.getRandF();
		m_afterglowRemaining = m_afterglowDuration;
		m_smokeDurationSec = 6.8f + 3.0f * app.getRandF();
		m_smokeWindFreq = 3.6f + 2.6f * app.getRandF();
		m_smokeWindPhase = 2.f * M_PIf * app.getRandF();
		m_smokeWindPhase2 = 2.f * M_PIf * app.getRandF();
		m_smokeDriftRate = 0.0030f + 0.0024f * app.getRandF();
	}
	else if (m_archetype == Archetype::SpectralStreak)
	{
		const bool bright = forceFireball || m_absMag >= 0.72f;
		m_widthScale = bright ? (0.86f + 0.22f * app.getRandF()) : (0.58f + 0.20f * app.getRandF());
		m_trainSeconds = bright ? (0.40f + 0.20f * app.getRandF()) : (0.28f + 0.16f * app.getRandF());
		m_hasTerminalFlare = bright || app.getRandF() > 0.52f;
		m_flarePos = 0.75f + 0.11f * app.getRandF();
		m_flareStrength = bright ? (0.88f + 0.40f * app.getRandF()) : (0.35f + 0.35f * app.getRandF());
		m_burstProgress = 0.80f;
		m_burstPeakMag = 0.f; // Ordinary spectral streaks stay pure needle+flare without airburst glare rings
		m_hasAfterglow = bright && (forceFireball || isFast || app.getRandF() > 0.45f);
		m_afterglowDuration = m_hasAfterglow ? (0.42f + 0.30f * app.getRandF()) : 0.f;
		m_afterglowRemaining = m_afterglowDuration;
		if (m_hasAfterglow)
		{
			m_smokeDurationSec = 6.2f + 3.0f * app.getRandF();
			m_smokeWindFreq = 3.5f + 2.6f * app.getRandF();
			m_smokeWindPhase = 2.f * M_PIf * app.getRandF();
			m_smokeWindPhase2 = 2.f * M_PIf * app.getRandF();
			m_smokeDriftRate = 0.0030f + 0.0024f * app.getRandF();
		}
	}
	else
	{
		// Abundant razor-thin micro-meteors providing crisp astrophotographic depth
		m_widthScale = 0.40f + 0.16f * app.getRandF();
		m_trainSeconds = 0.20f + 0.12f * app.getRandF();
		m_hasTerminalFlare = false;
		m_flareStrength = 0.f;
		m_hasAfterglow = false;
		m_afterglowDuration = 0.f;
		m_afterglowRemaining = 0.f;
	}

	// Derive head coma tint and soft dusty-airglow persistent smoke tint
	if (!colors.isEmpty())
	{
		const Vec4f headRgba = getColorFromName(colors.last().first);
		m_headTintColor = Vec3f(headRgba[0], headRgba[1], headRgba[2]);
		const Vec4f midRgba = getColorFromName(colors[colors.size() / 2].first);
		m_afterglowColor = Vec3f(
			qBound(0.f, 0.78f * 0.72f + midRgba[0] * 0.28f, 1.f),
			qBound(0.f, 0.74f * 0.72f + midRgba[1] * 0.28f, 1.f),
			qBound(0.f, 0.78f * 0.72f + midRgba[2] * 0.28f, 1.f));
	}
}

void Meteor::init(const float& radiantAlpha, const float& radiantDelta,
		  const float& speed, const QList<ColorPair> colors)
{
	m_bypassDaylight = false;
	m_startDelay = 0.f;
	m_headExtinguished = false;
	m_headFade = 1.f;
	m_rejectionReason.clear();

	if (!StelApp::getInstance().getFlagVividRendering())
	{
		initLegacy(radiantAlpha, radiantDelta, speed, colors);
		return;
	}
	m_segments = 48;

	// meteor speed in km/s
	m_speed = static_cast<double>(speed);

	// find the radiant in horizontal coordinates
	Vec3d radiantAltAz;
	StelUtils::spheToRect(radiantAlpha, radiantDelta, radiantAltAz);
	radiantAltAz = m_core->j2000ToAltAz(radiantAltAz);
	float radiantAlt, radiantAz;
	// S is zero, E is 90 degrees (SDSS)
	StelUtils::rectToSphe(&radiantAz, &radiantAlt, radiantAltAz);

	// meteors won't be visible if radiant is below 0degrees
	if (radiantAlt < 0.f)
	{
		m_rejectionReason = QStringLiteral("radiant-below-horizon");
		return;
	}

	// define the radiant coordinate system
	// rotation matrix to align z axis with radiant
	m_matAltAzToRadiant = Mat4d::zrotation(static_cast<double>(radiantAz)) * Mat4d::yrotation(M_PI_2 - static_cast<double>(radiantAlt));

	// select a random initial meteor altitude in the horizontal system [MIN_ALTITUDE, MAX_ALTITUDE]
	float initialAlt = MIN_ALTITUDE + (MAX_ALTITUDE - MIN_ALTITUDE) * StelApp::getInstance().getRandF();
	// calculates the max z-coordinate for the current radiant
	float maxZ = meteorZ(M_PI_2f - radiantAlt, initialAlt);

	// meteor trajectory
	// select a random xy position in polar coordinates (radiant system)
	const float xyDist = maxZ     * StelApp::getInstance().getRandF(); // [0, maxZ]
	const float theta = 2 * M_PIf * StelApp::getInstance().getRandF(); // [0, 2pi]

	// initial meteor coordinates (radiant system)
	m_position[0] = static_cast<double>(xyDist * std::cos(theta));
	m_position[1] = static_cast<double>(xyDist * std::sin(theta));
	m_position[2] = static_cast<double>(maxZ);
	m_posTrain = m_position;

	// store the initial z-component (radiant system)
	m_initialZ = static_cast<float>(m_position[2]);

	// find the initial meteor coordinates in the horizontal system
	Vec3d positionAltAz = m_position;
	positionAltAz.transfo4d(m_matAltAzToRadiant);

	// find the angle from horizon to meteor
	float meteorAlt = static_cast<float>(std::asin(positionAltAz[2] / positionAltAz.norm()));

	// this meteor should not be visible if it is above the maximum altitude
	// or if it's below the horizon!
	if (positionAltAz[2] > static_cast<double>(MAX_ALTITUDE) || meteorAlt <= 0.f)
	{
		m_rejectionReason = positionAltAz[2] > static_cast<double>(MAX_ALTITUDE)
			? QStringLiteral("above-max-altitude")
			: QStringLiteral("below-horizon");
		return;
	}

	// determine the final z-component and the min distance between meteor and observer
	// Keep shallow earth-grazers (< 8 deg radiant) physically proportioned (15..38 deg arc, ~0.8..1.9s)
	// so they feel authentic rather than slashing across the entire screen.
	const bool isLongGrazer = (radiantAlt < 0.14f);
	if (radiantAlt < 0.0262f) // (<1.5 degrees) deep earth-grazing meteor
	{
		// limit lifetime to 2.4sec so grazers stay physically plausible
		m_finalZ = -static_cast<float>(m_position[2]);
		m_finalZ = qMax(static_cast<float>(m_position[2]) - static_cast<float>(m_speed) * 2.4f, m_finalZ);
		m_minDist = xyDist;
	}
	else if (isLongGrazer)
	{
		const float grazerMinAlt = 74.f + 8.f * StelApp::getInstance().getRandF();
		m_finalZ = meteorZ(M_PI_2f - meteorAlt, grazerMinAlt);
		const float minSweepKm = static_cast<float>(m_speed) * (0.75f + 0.55f * StelApp::getInstance().getRandF());
		m_finalZ = qMin(m_finalZ, static_cast<float>(m_position[2]) - minSweepKm);
		m_finalZ = qMax(static_cast<float>(m_position[2]) - static_cast<float>(m_speed) * 2.1f, m_finalZ);
		m_minDist = sqrt(m_finalZ * m_finalZ + xyDist * xyDist);
	}
	else
	{
		// limit lifetime to 1.8sec
		m_finalZ = meteorZ(M_PI_2f - meteorAlt, MIN_ALTITUDE);
		m_finalZ = qMax(static_cast<float>(m_position[2]) - static_cast<float>(m_speed) * 1.8f, m_finalZ);
		m_minDist = sqrt(m_finalZ * m_finalZ + xyDist * xyDist);
	}

	// a meteor cannot hit the observer!
	if (m_minDist < 72.f) {
		m_rejectionReason = QStringLiteral("observer-distance");
		return;
	}

	// select random magnitude [-3.8; 4.2] with realistic natural falloff
	const float uMag = StelApp::getInstance().getRandF();
	float Mag = isLongGrazer ? (uMag * 5.2f - 3.8f) : (uMag * 8.4f - 3.6f);
	// compute RMag and CMag
	RCMag rcMag;
	if (m_core->getSkyDrawer()->computeRCMag(Mag, &rcMag) && rcMag.luminance > 0.f)
		m_absMag = qBound(0.14f, rcMag.luminance, 1.0f);
	else
		m_absMag = qBound(0.14f, std::pow(10.f, -0.4f * (Mag + 4.2f)), 1.f);

	// most visible meteors are under about 210km distant
	const float refDist = isLongGrazer ? 235.0f : 195.0f;
	float scale = std::pow(refDist / m_minDist, isLongGrazer ? 1.45f : 1.75f);
	m_absMag = qBound(isLongGrazer ? 0.28f : 0.14f, m_absMag * qMin(scale, 1.0f), 1.0f);
	m_peakAbsMag = m_absMag;
	m_aptMag = m_absMag;

	configureMorphology(isLongGrazer && (m_absMag >= 0.78f), speed, colors);
	if (isLongGrazer)
	{
		// Slightly longer graceful wake for rare grazers, kept well within realistic bounds
		m_trainSeconds = qBound(0.42f, qMax(m_trainSeconds, 0.48f + 0.24f * StelApp::getInstance().getRandF()), 0.76f);
	}

	// build the color vector
	buildColorVectors(colors);

	// Bind meteor lifecycle analytically to simulation Julian Day: f(JD)
	m_birthJd = m_core ? m_core->getJD() : 0.0;
	m_burnDurationSec = qMax(0.05, (static_cast<double>(m_initialZ) - static_cast<double>(m_finalZ)) / qMax(1.0, m_speed));
	m_breakupTimeSec = m_burnDurationSec * static_cast<double>(m_burstProgress);

	if (m_hasAfterglow && m_smokeDurationSec > 0.1f)
	{
		m_position[2] = static_cast<double>(m_finalZ);
		m_posTrain[2] = qMin(static_cast<double>(m_initialZ),
				     m_position[2] + m_speed * static_cast<double>(m_trainSeconds));
		captureSmokeTrainAnchors();
	}
	if (m_archetype == Archetype::FragmentingSuperbolide)
	{
		m_position[2] = static_cast<double>(m_initialZ) - m_speed * m_breakupTimeSec;
		spawnBreakupFragments();
	}

	double maxFragTail = 0.0;
	for (const auto& frag : m_fragments)
	{
		maxFragTail = qMax(maxFragTail, m_breakupTimeSec + static_cast<double>(frag.lifeSec) - m_burnDurationSec);
	}
	m_totalLifetimeSec = m_burnDurationSec + qMax(0.35, qMax(static_cast<double>(m_afterglowDuration),
								 qMax(static_cast<double>(m_smokeDurationSec), maxFragTail)));

	m_alive = true;
	evaluateAtSimTime(m_birthJd);
}

void Meteor::initInViewport(const Vec3d& centerAltAz, float offsetRightRad, float offsetUpRad,
			    float slopeAngleRad, float speed, const QList<ColorPair>& colors,
			    bool isFireball, float startDelaySec, Archetype forcedArchetype)
{
	if (!StelApp::getInstance().getFlagVividRendering())
	{
		m_alive = false;
		m_rejectionReason = QStringLiteral("vivid-required");
		return;
	}
	m_segments = 48;
	m_bypassDaylight = true;
	m_startDelay = qMax(0.f, startDelaySec);
	m_headExtinguished = false;
	m_headFade = 1.f;
	m_speed = static_cast<double>(qBound(16.f, speed, 72.f));

	// Clamp target viewing center above horizon (>= 16 deg) so preview streaks always clear the ground.
	Vec3d dir = centerAltAz;
	if (dir.normSquared() < 1e-9)
		dir = Vec3d(0.0, 0.0, 1.0);
	dir.normalize();
	float az = 0.f, alt = 0.f;
	StelUtils::rectToSphe(&az, &alt, dir);
	if (alt < 0.28f)
	{
		alt = 0.36f;
		StelUtils::spheToRect(az, alt, dir);
	}

	// Build tangent basis (right, up) around viewing center
	Vec3d worldUp(0.0, 0.0, 1.0);
	Vec3d right = dir ^ worldUp;
	if (right.normSquared() < 1e-6)
		right = Vec3d(1.0, 0.0, 0.0);
	right.normalize();
	Vec3d up = right ^ dir;
	up.normalize();

	// Entry direction offset within the current viewport
	Vec3d startDir = dir + right * static_cast<double>(offsetRightRad) + up * static_cast<double>(offsetUpRad);
	startDir.normalize();
	if (startDir[2] < 0.16)
	{
		startDir[2] = 0.22;
		startDir.normalize();
	}

	// Place start point at ~108 km altitude along startDir
	const double startAltKm = 104.0 + 12.0 * static_cast<double>(StelApp::getInstance().getRandF());
	const double startRangeKm = qBound(105.0, startAltKm / qMax(0.18, startDir[2]), 360.0);
	const Vec3d startPosKm = startDir * startRangeKm;

	// Build downward diagonal travel direction (parallel-angled streaks across the sky)
	Vec3d travelDir = -up * std::cos(static_cast<double>(slopeAngleRad))
	                  + right * std::sin(static_cast<double>(slopeAngleRad))
	                  - dir * 0.22;
	travelDir.normalize();

	// Radiant lies opposite to travel direction
	Vec3d radiantDir = -travelDir;
	float radAz = 0.f, radAlt = 0.f;
	StelUtils::rectToSphe(&radAz, &radAlt, radiantDir);
	m_matAltAzToRadiant = Mat4d::zrotation(static_cast<double>(radAz)) * Mat4d::yrotation(M_PI_2 - static_cast<double>(radAlt));

	// Transform start position into radiant frame
	Vec3d posRad = startPosKm;
	posRad.transfo4d(m_matAltAzToRadiant.transpose());
	m_position = posRad;
	m_posTrain = posRad;
	m_initialZ = static_cast<float>(m_position[2]);

	// Burn duration: fragmenting superbolides fly slower & longer (~1.45..1.90s) so breakup & sparks unfold vividly
	const double burnSeconds = (forcedArchetype == Archetype::FragmentingSuperbolide)
		? (1.45 + 0.45 * StelApp::getInstance().getRandF())
		: (isFireball ? (0.85 + 0.35 * StelApp::getInstance().getRandF())
		              : (0.45 + 0.25 * StelApp::getInstance().getRandF()));
	m_finalZ = m_initialZ - static_cast<float>(m_speed * burnSeconds);
	m_minDist = static_cast<float>(qMax(90.0, startPosKm.norm() * 0.85));

	m_absMag = isFireball ? 0.94f : (0.58f + 0.24f * StelApp::getInstance().getRandF());
	m_peakAbsMag = m_absMag;
	m_aptMag = m_absMag;

	configureMorphology(isFireball, static_cast<float>(m_speed), colors, static_cast<int>(forcedArchetype));
	if (isFireball)
		m_trainSeconds = qBound(0.42f, qMax(m_trainSeconds, 0.48f + 0.20f * StelApp::getInstance().getRandF()), 0.72f);
	buildColorVectors(colors);

	// Bind preview meteor lifecycle analytically to simulation Julian Day: f(JD)
	m_birthJd = m_core ? m_core->getJD() : 0.0;
	m_burnDurationSec = qMax(0.05, (static_cast<double>(m_initialZ) - static_cast<double>(m_finalZ)) / qMax(1.0, m_speed));
	m_breakupTimeSec = m_burnDurationSec * static_cast<double>(m_burstProgress);

	if (m_hasAfterglow && m_smokeDurationSec > 0.1f)
	{
		m_position[2] = static_cast<double>(m_finalZ);
		m_posTrain[2] = qMin(static_cast<double>(m_initialZ),
				     m_position[2] + m_speed * static_cast<double>(m_trainSeconds));
		captureSmokeTrainAnchors();
	}
	if (m_archetype == Archetype::FragmentingSuperbolide)
	{
		m_position[2] = static_cast<double>(m_initialZ) - m_speed * m_breakupTimeSec;
		spawnBreakupFragments();
	}

	double maxFragTail = 0.0;
	for (const auto& frag : m_fragments)
	{
		maxFragTail = qMax(maxFragTail, m_breakupTimeSec + static_cast<double>(frag.lifeSec) - m_burnDurationSec);
	}
	m_totalLifetimeSec = m_burnDurationSec + qMax(0.35, qMax(static_cast<double>(m_afterglowDuration),
								 qMax(static_cast<double>(m_smokeDurationSec), maxFragTail)));

	m_alive = true;
	m_rejectionReason.clear();
	evaluateAtSimTime(m_birthJd);
}

bool Meteor::evaluateAtSimTime(double currentJd)
{
	if (!m_alive)
	{
		m_visibleAtSimTime = false;
		return false;
	}

	const double t = (currentJd - m_birthJd) * 86400.0 - static_cast<double>(m_startDelay);

	// Expire cleanly once past full lifetime or rewound well before birth
	if (t > m_totalLifetimeSec + 0.25 || t < -static_cast<double>(m_startDelay) - 3.0)
	{
		m_alive = false;
		m_visibleAtSimTime = false;
		return false;
	}

	// Waiting for staggered start delay (stays alive and frozen if simulation time is paused!)
	if (t < 0.0)
	{
		m_visibleAtSimTime = false;
		m_burstFlash = 0.f;
		return true;
	}

	m_visibleAtSimTime = true;

	// Analytical head & luminous wake positions as a pure function of simulation time t
	const double burnT = qBound(0.0, t, m_burnDurationSec);
	m_burnTimeSec = static_cast<float>(burnT);
	m_position[2] = static_cast<double>(m_initialZ) - m_speed * burnT;
	const double maxTrainDist = m_speed * static_cast<double>(m_trainSeconds);
	m_posTrain[2] = qMin(static_cast<double>(m_initialZ), m_position[2] + maxTrainDist);

	// Post-burn extinction, chemiluminescent afterglow & drifting mesospheric smoke
	const double postBurnT = qMax(0.0, t - m_burnDurationSec);
	m_headExtinguished = (t >= m_burnDurationSec);
	m_headFade = m_headExtinguished
		? qBound(0.f, 1.f - static_cast<float>(postBurnT) * 4.0f, 1.f)
		: 1.f;
	m_afterglowRemaining = m_hasAfterglow
		? qMax(0.f, m_afterglowDuration - static_cast<float>(postBurnT))
		: 0.f;
	m_smokeAgeSec = (m_smokeCaptured && m_headExtinguished)
		? static_cast<float>(postBurnT)
		: 0.f;

	if (!m_headExtinguished)
	{
		m_absMag = m_peakAbsMag;
	}
	else if (m_afterglowDuration > 0.01f)
	{
		const float glowRatio = m_afterglowRemaining / m_afterglowDuration;
		m_absMag = m_peakAbsMag * qMax(m_headFade, glowRatio * glowRatio * 0.36f);
	}
	else
	{
		m_absMag = m_peakAbsMag * m_headFade;
	}

	// Pure analytical moving light-curve & atmospheric glare (identical forward, paused, or rewound!)
	if (m_burstPeakMag > 0.05f)
	{
		Vec3d headAltAz = radiantToAltAz(m_position);
		const double hn = headAltAz.norm();
		if (hn > 1e-12)
			m_burstAltAzDir = headAltAz / hn;

		const float prog = qBound(0.f, static_cast<float>(burnT / qMax(0.05, m_burnDurationSec)), 1.f);
		float env = 0.f;
		if (m_lightCurveMode == 0)
		{
			const float sigma = (prog < m_burstProgress) ? 0.30f : 0.24f;
			const float d = (prog - m_burstProgress) / sigma;
			env = std::exp(-d * d);
		}
		else if (m_lightCurveMode == 1)
		{
			const float ramp = std::pow(qBound(0.f, prog / qMax(0.15f, m_burstProgress), 1.f), 1.65f);
			const float d = (prog - m_burstProgress) / ((prog < m_burstProgress) ? 0.22f : 0.16f);
			const float peak = std::exp(-d * d);
			env = qBound(0.f, 0.32f * ramp * (1.f - 0.55f * qMax(0.f, prog - m_burstProgress) / qMax(0.1f, 1.f - m_burstProgress)) + 0.80f * peak, 1.05f);
		}
		else
		{
			const float d = (prog - m_burstProgress) / ((prog < m_burstProgress) ? 0.22f : 0.30f);
			const float surge = std::exp(-d * d);
			const float flicker = 1.0f + 0.07f * std::sin(m_burnTimeSec * 24.f) + 0.04f * std::cos(m_burnTimeSec * 39.f);
			env = qBound(0.f, (0.18f * std::sin(prog * M_PIf) + 0.88f * surge) * flicker, 1.08f);
		}
		const float entrySmooth = qBound(0.f, prog / 0.08f, 1.f);
		const float postDecay = (postBurnT > 0.0) ? std::exp(-static_cast<float>(postBurnT) * 3.4f) : 1.f;
		m_burstFlash = m_burstPeakMag * env * entrySmooth * postDecay;
	}
	else
	{
		m_burstFlash = 0.f;
	}

	// Analytical closed-form breakup fragments under exponential atmospheric drag:
	//   v(tf) = v0 * exp(-k * tf),  p(tf) = p0 + v0 * (1 - exp(-k * tf)) / k
	const double tf = t - m_breakupTimeSec;
	m_burstTriggered = (tf >= 0.0);
	for (auto& frag : m_fragments)
	{
		if (tf < 0.0 || tf >= static_cast<double>(frag.lifeSec))
		{
			frag.ageSec = -1.f;
			continue;
		}
		frag.ageSec = static_cast<float>(tf);
		const double k = qMax(1e-4, static_cast<double>(frag.dragRate));
		const double expK = std::exp(-k * tf);
		const double dispFactor = (1.0 - expK) / k;
		frag.posRad = frag.originPosRad + frag.initVelRad * dispFactor;
		const Vec3d curVel = frag.initVelRad * expK;
		const double wakeSec = frag.isLeadChunk ? 0.11 : 0.06;
		frag.prevPosRad = frag.posRad - curVel * wakeSec;
	}

	// Update apparent magnitude based on distance to observer
	const float distNorm = qMax(1.f, static_cast<float>(m_position.norm()));
	const float scale = std::pow(m_minDist / distNorm, 1.5f);
	m_aptMag = qBound(0.f, m_absMag * qMin(scale, 1.0f), 1.0f);

	return true;
}

bool Meteor::update(double deltaTime)
{
	if (!m_alive)
	{
		return false;
	}
	if (!StelApp::getInstance().getFlagVividRendering())
		return updateLegacy(deltaTime);

	Q_UNUSED(deltaTime)
	return evaluateAtSimTime(m_core ? m_core->getJD() : m_birthJd);
}

void Meteor::draw(const StelCore* core, StelPainter& sPainter)
{
	if (!m_alive)
	{
		return;
	}
	if (!StelApp::getInstance().getFlagVividRendering())
	{
		drawLegacy(core, sPainter);
		return;
	}
	// Evaluate strictly at the exact simulation JD of this rendered frame
	if (!evaluateAtSimTime(core ? core->getJD() : m_birthJd) || !m_visibleAtSimTime)
	{
		return;
	}

	double angularHalfWidth = 0.0;
	double bolideAngularSize = 0.0;
	calculateThickness(core, sPainter, angularHalfWidth, bolideAngularSize);

	if (m_smokeCaptured && m_smokeAgeSec < m_smokeDurationSec)
	{
		drawPersistentSmokeTrain(sPainter);
	}

	if (m_burstFlash > 0.01f)
	{
		const Vec3f glareTint = (m_archetype == Archetype::FragmentingSuperbolide)
			? Vec3f(1.0f, 0.86f, 0.54f)
			: Vec3f(0.82f * 0.55f + m_headTintColor[0] * 0.45f,
				0.94f * 0.55f + m_headTintColor[1] * 0.45f,
				0.98f * 0.55f + m_headTintColor[2] * 0.45f);
		drawAirburstGlare(sPainter, m_burstAltAzDir, m_burstFlash, glareTint);
	}

	if (!m_headExtinguished || m_headFade > 0.01f || m_afterglowRemaining > 0.01f)
	{
		Vec3d headDir(0., 0., 1.);
		Vec3d headTangent(0., 1., 0.);
		drawTrain(core, sPainter, angularHalfWidth, headDir, headTangent);

		const float headIntensity = m_aptMag * m_headFade;
		if (headIntensity > 0.03f)
		{
			drawBolide(sPainter, headDir, headTangent, bolideAngularSize, headIntensity);
		}
	}

	if (!m_fragments.isEmpty())
	{
		drawFragments(sPainter);
	}
}

Vec4f Meteor::getColorFromName(QString colorName)
{
	// Spectral emission colors calibrated to real meteor spectroscopy:
	//   emerald / blueGreen : Mg I (518 nm) + O I (557.7 nm forbidden green line)
	//   cyanGreen           : hot Mg/O ionized cyan-mint head transition
	//   amberGold / orangeYellow : Na I (589 nm sodium D-doublet)
	//   paleGold / yellow   : Fe I / warm golden core
	//   iceBlue             : Ca II / Si II high-velocity blue-white
	//   violet              : Ca II H&K violet-lilac
	//   roseMagenta / red   : atmospheric N2 first positive / O I 630 nm wake
	static const QMap<QString, Vec3f> colorMap = {
		{ "oGreen",       {  94.f, 224.f, 114.f}}, // Crisp high-altitude O I 557.7 nm entry needle
		{ "roseGold",     { 246.f, 154.f, 136.f}}, // Warm N2 + Na mid-burn transition
		{ "lilacTip",     { 196.f, 164.f, 248.f}}, // Faint Ca II cool purple extinguishing needle tip
		{ "emerald",      {  92.f, 232.f, 166.f}}, // Mg I 518 nm ablation flare halo
		{ "cyanGreen",    { 146.f, 242.f, 214.f}},
		{ "blueGreen",    { 102.f, 232.f, 184.f}},
		{ "amberGold",    { 255.f, 174.f,  86.f}},
		{ "orangeYellow", { 255.f, 188.f,  96.f}},
		{ "paleGold",     { 255.f, 226.f, 158.f}},
		{ "yellow",       { 255.f, 234.f, 146.f}},
		{ "iceBlue",      { 164.f, 208.f, 255.f}},
		{ "violet",       { 196.f, 156.f, 250.f}},
		{ "roseMagenta",  { 242.f, 134.f, 168.f}},
		{ "red",          { 246.f, 126.f, 130.f}},
		{ "white",        { 246.f, 250.f, 255.f}}
	};
	Vec3f rgb = colorMap.value(colorName, Vec3f(244.f, 249.f, 255.f));
	return Vec4f(rgb / 255.f, 1.0f);
}

void Meteor::buildColorVectors(const QList<ColorPair> colors)
{
	m_outerColorVector.resize(m_segments);
	m_coreColorVector.resize(m_segments);
	m_lineColorVector.resize(m_segments);
	m_trainColorVector.resize(2 * m_segments);

	// Convert weighted color pairs into smooth ordered stops from tail (u=0) to head (u=1)
	struct ColorStop {
		float pos;
		Vec3f rgb;
	};
	QVector<ColorStop> stops;
	if (colors.isEmpty())
	{
		stops.append({0.f, Vec3f(0.95f, 0.97f, 1.0f)});
		stops.append({1.f, Vec3f(1.0f, 1.0f, 1.0f)});
	}
	else if (colors.size() == 1)
	{
		const Vec4f c = getColorFromName(colors.first().first);
		stops.append({0.f, Vec3f(c[0], c[1], c[2])});
		stops.append({1.f, Vec3f(c[0], c[1], c[2])});
	}
	else
	{
		float totalWeight = 0.f;
		for (const auto& cp : colors)
			totalWeight += static_cast<float>(qMax(1, cp.second));

		float accum = 0.f;
		for (int idx = 0; idx < colors.size(); ++idx)
		{
			const float w = static_cast<float>(qMax(1, colors[idx].second));
			const float center = (idx == 0)
				? 0.f
				: (idx == colors.size() - 1 ? 1.f : (accum + 0.5f * w) / totalWeight);
			const Vec4f c = getColorFromName(colors[idx].first);
			stops.append({center, Vec3f(c[0], c[1], c[2])});
			accum += w;
		}
	}

	for (int i = 0; i < m_segments; ++i)
	{
		const float u = static_cast<float>(i) / static_cast<float>(m_segments - 1);
		// Interpolate across stops
		Vec3f outerRgb = stops.last().rgb;
		for (int s = 0; s < stops.size() - 1; ++s)
		{
			if (u >= stops[s].pos && u <= stops[s + 1].pos)
			{
				const float span = qMax(1e-4f, stops[s + 1].pos - stops[s].pos);
				const float t = (u - stops[s].pos) / span;
				// Smoothstep easing for organic spectral plasma transition
				const float st = t * t * (3.f - 2.f * t);
				outerRgb = stops[s].rgb * (1.f - st) + stops[s + 1].rgb * st;
				break;
			}
		}

		// Incandescent white-hot core: crisp colored needle at entry, blazing white at terminal flare,
		// then cooling slightly into the delicate violet/white extinguishing tip
		const float dFlare = (u - m_flarePos) / 0.14f;
		const float flareWhite = m_hasTerminalFlare ? (0.58f * std::exp(-dFlare * dFlare)) : 0.f;
		const float tipCool = (u > 0.86f) ? (0.28f * ((u - 0.86f) / 0.14f)) : 0.f;
		const float whiteMix = qBound(0.18f, 0.20f + 0.34f * std::pow(u, 1.15f) + flareWhite - tipCool, 0.97f);
		const Vec3f coreRgb(
			outerRgb[0] * (1.f - whiteMix) + 1.0f * whiteMix,
			outerRgb[1] * (1.f - whiteMix) + 1.0f * whiteMix,
			outerRgb[2] * (1.f - whiteMix) + 1.0f * whiteMix);

		m_outerColorVector[i] = Vec4f(outerRgb[0], outerRgb[1], outerRgb[2], 1.f);
		m_coreColorVector[i] = Vec4f(coreRgb[0], coreRgb[1], coreRgb[2], 1.f);
		m_lineColorVector[i] = m_coreColorVector[i];
	}

	const Vec4f headOuter = m_outerColorVector.last();
	m_headTintColor = Vec3f(headOuter[0], headOuter[1], headOuter[2]);
}

void Meteor::initLegacy(const float& radiantAlpha, const float& radiantDelta,
			const float& speed, const QList<ColorPair> colors)
{
	m_segments = 10;
	m_bypassDaylight = false;
	m_startDelay = 0.f;
	m_headExtinguished = false;
	m_headFade = 1.f;

	// meteor speed in km/s
	m_speed = static_cast<double>(speed);

	// find the radiant in horizontal coordinates
	Vec3d radiantAltAz;
	StelUtils::spheToRect(radiantAlpha, radiantDelta, radiantAltAz);
	radiantAltAz = m_core->j2000ToAltAz(radiantAltAz);
	float radiantAlt, radiantAz;
	StelUtils::rectToSphe(&radiantAz, &radiantAlt, radiantAltAz);

	if (radiantAlt < 0.f)
	{
		m_rejectionReason = QStringLiteral("radiant-below-horizon");
		return;
	}

	m_matAltAzToRadiant = Mat4d::zrotation(static_cast<double>(radiantAz)) * Mat4d::yrotation(M_PI_2 - static_cast<double>(radiantAlt));

	float initialAlt = MIN_ALTITUDE + (MAX_ALTITUDE - MIN_ALTITUDE) * StelApp::getInstance().getRandF();
	float maxZ = meteorZ(M_PI_2f - radiantAlt, initialAlt);

	const float xyDist = maxZ * StelApp::getInstance().getRandF();
	const float theta = 2 * M_PIf * StelApp::getInstance().getRandF();

	m_position[0] = static_cast<double>(xyDist * std::cos(theta));
	m_position[1] = static_cast<double>(xyDist * std::sin(theta));
	m_position[2] = static_cast<double>(maxZ);
	m_posTrain = m_position;
	m_initialZ = static_cast<float>(m_position[2]);

	Vec3d positionAltAz = m_position;
	positionAltAz.transfo4d(m_matAltAzToRadiant);
	float meteorAlt = static_cast<float>(std::asin(positionAltAz[2] / positionAltAz.norm()));

	if (positionAltAz[2] > static_cast<double>(MAX_ALTITUDE) || meteorAlt <= 0.f)
	{
		m_rejectionReason = positionAltAz[2] > static_cast<double>(MAX_ALTITUDE)
			? QStringLiteral("above-max-altitude")
			: QStringLiteral("below-horizon");
		return;
	}

	if (radiantAlt < 0.0262f)
	{
		float prob = StelApp::getInstance().getRandF();
		if (prob > 0.3f)
		{
			m_rejectionReason = QStringLiteral("earth-grazer-probability");
			return;
		}
		m_finalZ = -static_cast<float>(m_position[2]);
		m_finalZ = qMax(static_cast<float>(m_position[2]) - static_cast<float>(m_speed) * 12.f, m_finalZ);
		m_minDist = xyDist;
	}
	else
	{
		m_finalZ = meteorZ(M_PI_2f - meteorAlt, MIN_ALTITUDE);
		m_finalZ = qMax(static_cast<float>(m_position[2]) - static_cast<float>(m_speed) * 12.0f, m_finalZ);
		m_minDist = sqrt(m_finalZ * m_finalZ + xyDist * xyDist);
	}

	if (m_minDist < MIN_ALTITUDE)
	{
		m_rejectionReason = QStringLiteral("observer-distance");
		return;
	}

	float Mag = StelApp::getInstance().getRandF() * 9.0f - 4.5f;
	RCMag rcMag;
	if (m_core->getSkyDrawer()->computeRCMag(Mag, &rcMag) && rcMag.luminance > 0.f)
		m_absMag = rcMag.luminance;
	else
		m_absMag = qBound(0.05f, std::pow(10.f, -0.4f * (Mag + 4.5f)), 1.f);

	float scale = std::pow(184.0f / m_minDist, 2);
	m_absMag *= qMin(scale, 1.0f);
	m_peakAbsMag = m_absMag;
	m_aptMag = m_absMag;

	buildColorVectorsLegacy(colors);
	m_birthJd = m_core ? m_core->getJD() : 0.0;
	m_burnDurationSec = qMax(0.05, (static_cast<double>(m_initialZ) - static_cast<double>(m_finalZ)) / qMax(1.0, m_speed));
	m_totalLifetimeSec = m_burnDurationSec + 0.6;
	m_visibleAtSimTime = true;
	m_alive = true;
}

bool Meteor::updateLegacy(double deltaTime)
{
	Q_UNUSED(deltaTime)
	if (!m_alive)
		return false;

	const double currentJd = m_core ? m_core->getJD() : m_birthJd;
	const double t = (currentJd - m_birthJd) * 86400.0;
	if (t < -2.0 || t > m_totalLifetimeSec + 0.5)
	{
		m_alive = false;
		m_visibleAtSimTime = false;
		return false;
	}
	if (t < 0.0)
	{
		m_visibleAtSimTime = false;
		return true;
	}
	m_visibleAtSimTime = true;

	const double burnT = qMax(0.0, t);
	m_position[2] = static_cast<double>(m_initialZ) - m_speed * burnT;
	m_posTrain[2] = qMin(static_cast<double>(m_initialZ), m_position[2] + m_speed * 0.5);

	const double postBurnT = qMax(0.0, t - m_burnDurationSec);
	m_absMag = qMax(0.f, m_peakAbsMag - static_cast<float>(postBurnT) * 2.f);
	if (m_absMag <= 0.f)
	{
		m_alive = false;
		m_visibleAtSimTime = false;
		return false;
	}

	const float scale = std::pow(m_minDist / qMax(1.f, static_cast<float>(m_position.norm())), 2);
	m_aptMag = qMax(0.f, m_absMag * qMin(scale, 1.f));
	return true;
}

void Meteor::drawLegacy(const StelCore* core, StelPainter& sPainter)
{
	if (!m_alive || !m_visibleAtSimTime)
		return;

	double thickness;
	double bolideSize;
	calculateThicknessLegacy(core, thickness, bolideSize);
	drawTrainLegacy(sPainter, thickness);
	drawBolideLegacy(sPainter, bolideSize);
}

Vec4f Meteor::getColorFromNameLegacy(QString colorName)
{
	static const QMap<QString, Vec3f> colorMap = {
		{ "violet",       { 176.f,  67.f, 172.f}},
		{ "blueGreen",    {   0.f, 255.f, 152.f}},
		{ "yellow",       { 255.f, 255.f,   0.f}},
		{ "orangeYellow", { 255.f, 160.f,   0.f}},
		{ "red",          { 255.f,  30.f,   0.f}}
	};
	const Vec3f rgb = colorMap.value(colorName, Vec3f(255.f));
	return Vec4f(rgb / 255.f, 1.0f);
}

void Meteor::buildColorVectorsLegacy(const QList<ColorPair> colors)
{
	if (colors.isEmpty())
		return;

	QVector<Vec4f> lineColor;
	QVector<Vec4f> trainColor;
	for (const auto& color : colors)
	{
		const int segs = qRound(m_segments * (color.second / 100.f));
		for (int s = 0; s < segs; ++s)
		{
			const Vec4f rgba = getColorFromNameLegacy(color.first);
			lineColor.append(rgba);
			trainColor.append(rgba);
			trainColor.append(rgba);
		}
	}

	const int segs = lineColor.size();
	if (segs < m_segments)
	{
		const Vec4f rgba = getColorFromNameLegacy(colors.last().first);
		for (int s = segs; s < m_segments; ++s)
		{
			lineColor.append(rgba);
			trainColor.append(rgba);
			trainColor.append(rgba);
		}
	}
	else if (segs > m_segments)
	{
		for (int s = segs; s > m_segments; --s)
		{
			lineColor.removeLast();
			trainColor.removeLast();
			trainColor.removeLast();
		}
	}

	if (colors.size() > 1)
	{
		const int firstSegment = StelApp::getInstance().getRandBounded(0, qMax(1, segs));
		const QVector<Vec4f> lineColor2 = lineColor.mid(0, firstSegment);
		const QVector<Vec4f> lineColor1 = lineColor.mid(firstSegment);
		lineColor.clear();
		lineColor.append(lineColor1);
		lineColor.append(lineColor2);

		const int trainSplit = firstSegment * 2;
		const QVector<Vec4f> trainColor2 = trainColor.mid(0, trainSplit);
		const QVector<Vec4f> trainColor1 = trainColor.mid(trainSplit);
		trainColor.clear();
		trainColor.append(trainColor1);
		trainColor.append(trainColor2);
	}

	m_lineColorVector = lineColor;
	m_trainColorVector = trainColor;
}

void Meteor::calculateThicknessLegacy(const StelCore* core, double& thickness, double& bolideSize)
{
	const double maxFOV = core->getMovementMgr()->getMaxFov();
	const double FOV = core->getMovementMgr()->getCurrentFov();
	thickness = 2 * log(FOV + 0.25) / (1.2 * maxFOV - (FOV + 0.25)) + 0.01;
	if (FOV <= 0.5)
		thickness = 0.013 * FOV;
	else if (FOV > 100.0)
		thickness = 0;

	bolideSize = thickness * 3;
}

void Meteor::drawBolideLegacy(StelPainter& sPainter, const double& bolideSize)
{
	if (bolideSize == 0.0 || !m_bolideTexture)
		return;
	const StelProjectorP prj = sPainter.getProjector();
	Vec3d headWin;
	if (!prj || !prj->projectCheck(radiantToAltAz(m_position), headWin))
		return;

	QVector<Vec3d> vertexArrayBolide;
	QVector<Vec4f> colorArrayBolide;
	const Vec4f bolideColor(1, 1, 1, m_aptMag);

	Vec3d topLeft = m_position;
	topLeft[1] -= bolideSize;
	vertexArrayBolide.push_back(radiantToAltAz(topLeft));
	colorArrayBolide.push_back(bolideColor);

	Vec3d topRight = m_position;
	topRight[0] -= bolideSize;
	vertexArrayBolide.push_back(radiantToAltAz(topRight));
	colorArrayBolide.push_back(bolideColor);

	Vec3d bottomRight = m_position;
	bottomRight[1] += bolideSize;
	vertexArrayBolide.push_back(radiantToAltAz(bottomRight));
	colorArrayBolide.push_back(bolideColor);

	Vec3d bottomLeft = m_position;
	bottomLeft[0] += bolideSize;
	vertexArrayBolide.push_back(radiantToAltAz(bottomLeft));
	colorArrayBolide.push_back(bolideColor);

	sPainter.setBlending(true, GL_ONE, GL_ONE);
	sPainter.enableClientStates(true, true, true);
	m_bolideTexture->bind();
	static const float texCoordData[] = {1., 0., 0., 0., 0., 1., 1., 1.};
	sPainter.setTexCoordPointer(2, GL_FLOAT, texCoordData);
	sPainter.setColorPointer(4, GL_FLOAT, colorArrayBolide.constData());
	sPainter.setVertexPointer(3, GL_DOUBLE, vertexArrayBolide.constData());
	sPainter.drawFromArray(StelPainter::TriangleFan, vertexArrayBolide.size(), 0, true);
	sPainter.setBlending(false);
	sPainter.enableClientStates(false);
}

void Meteor::drawTrainLegacy(StelPainter& sPainter, const double& thickness)
{
	if (m_segments != m_lineColorVector.size() || 2 * m_segments != m_trainColorVector.size())
	{
		qWarning() << "Meteor: color arrays have an inconsistent size!";
		return;
	}
	const StelProjectorP prj = sPainter.getProjector();
	if (!prj)
		return;
	const Vec3d headAltAz = radiantToAltAz(m_position);
	const Vec3d tailAltAz = radiantToAltAz(m_posTrain);
	Vec3d hWin, tWin;
	if (prj->intersectViewportDiscontinuity(tailAltAz, headAltAz) ||
	    (!prj->projectCheck(headAltAz, hWin) && !prj->projectCheck(tailAltAz, tWin)))
	{
		return;
	}

	QVector<Vec3d> vertexArrayLine;
	QVector<Vec3d> vertexArrayL;
	QVector<Vec3d> vertexArrayR;
	QVector<Vec3d> vertexArrayTop;

	Vec3d posTrainB = m_posTrain;
	posTrainB[0] += static_cast<double>(thickness) * 0.7;
	posTrainB[1] += static_cast<double>(thickness) * 0.7;
	Vec3d posTrainL = m_posTrain;
	posTrainL[1] -= static_cast<double>(thickness);
	Vec3d posTrainR = m_posTrain;
	posTrainR[0] -= static_cast<double>(thickness);

	for (int i = 0; i < m_segments; ++i)
	{
		const double height = m_posTrain[2] + i * (m_position[2] - m_posTrain[2]) / (m_segments - 1);
		Vec3d posi = m_posTrain;
		posi[2] = height;
		vertexArrayLine.push_back(radiantToAltAz(posi));

		posi = posTrainB;
		posi[2] = height;
		vertexArrayL.push_back(radiantToAltAz(posi));
		vertexArrayR.push_back(radiantToAltAz(posi));

		posi = posTrainL;
		posi[2] = height;
		vertexArrayL.push_back(radiantToAltAz(posi));
		vertexArrayTop.push_back(radiantToAltAz(posi));

		posi = posTrainR;
		posi[2] = height;
		vertexArrayR.push_back(radiantToAltAz(posi));
		vertexArrayTop.push_back(radiantToAltAz(posi));

		const float mag = m_aptMag * (static_cast<float>(i) / static_cast<float>(m_segments - 1));
		m_lineColorVector[i][3] = mag;
		m_trainColorVector[i * 2][3] = mag;
		m_trainColorVector[i * 2 + 1][3] = mag;
	}

	sPainter.setBlending(true);
	sPainter.enableClientStates(true, false, true);
	if (thickness != 0.0)
	{
		sPainter.setColorPointer(4, GL_FLOAT, m_trainColorVector.constData());
		sPainter.setVertexPointer(3, GL_DOUBLE, vertexArrayL.constData());
		sPainter.drawFromArray(StelPainter::TriangleStrip, vertexArrayL.size(), 0, true);
		sPainter.setVertexPointer(3, GL_DOUBLE, vertexArrayR.constData());
		sPainter.drawFromArray(StelPainter::TriangleStrip, vertexArrayR.size(), 0, true);
		sPainter.setVertexPointer(3, GL_DOUBLE, vertexArrayTop.constData());
		sPainter.drawFromArray(StelPainter::TriangleStrip, vertexArrayTop.size(), 0, true);
	}
	sPainter.setColorPointer(4, GL_FLOAT, m_lineColorVector.constData());
	sPainter.setVertexPointer(3, GL_DOUBLE, vertexArrayLine.constData());
	sPainter.drawFromArray(StelPainter::LineStrip, vertexArrayLine.size(), 0, true);
	sPainter.setBlending(false);
	sPainter.enableClientStates(false);
}

float Meteor::meteorZ(float zenithAngle, float altitude)
{
	float distance;

	if (zenithAngle > 1.13446401f) // > 65 degrees?
	{
		const float zcos = cos(zenithAngle);
		constexpr auto R = static_cast<float>(EARTH_RADIUS);
		distance = sqrt(pow(R * zcos, 2) + 2 * R * altitude + pow(altitude, 2));
		distance -= R * zcos;
	}
	else
	{
		// (first order approximation)
		distance = altitude / cos(zenithAngle);
	}

	return distance;
}

Vec3d Meteor::altAzToRadiant(Vec3d position)
{
	position.transfo4d(m_matAltAzToRadiant.transpose());
	position *= 1242;
	return position;
}

Vec3d Meteor::radiantToAltAz(Vec3d position)
{
	position /= 1242.0; // 1242 to scale down under 1
	position.transfo4d(m_matAltAzToRadiant);
	return position;
}

void Meteor::calculateThickness(const StelCore* core, const StelPainter& sPainter,
				double& angularHalfWidth, double& bolideAngularSize)
{
	const double fovDeg = qBound(0.2, core->getMovementMgr()->getCurrentFov(), 179.0);
	const int vpHeightRaw = sPainter.getProjector() ? sPainter.getProjector()->getViewportHeight() : 1080;
	const double vpHeight = qMax(360.0, static_cast<double>(vpHeightRaw));
	const double radPerPx = (fovDeg * M_PI / 180.0) / vpHeight;

	// Scale cleanly across ALL FOVs (including wide 100-160 deg nightscapes!) so meteors render
	// as sleek, needle-sharp atmospheric spindles rather than bulky blobs or 1px hard lines.
	const double screenScale = qBound(1.0, static_cast<double>(StelApp::getInstance().getScreenScale()), 3.5);
	const double baseCorePx = 0.56 * screenScale;
	angularHalfWidth = qBound(0.00010, baseCorePx * radPerPx, 0.0024);
	bolideAngularSize = angularHalfWidth * 2.15;
}

void Meteor::drawBolide(StelPainter& sPainter, const Vec3d& headDir, const Vec3d& tangentDir,
			const double& bolideAngularSize, float headIntensity)
{
	Q_UNUSED(tangentDir)
	if (bolideAngularSize <= 0.0 || !m_bolideTexture || headIntensity <= 0.01f)
	{
		return;
	}

	const StelProjectorP prj = sPainter.getProjector();
	if (!prj)
		return;

	Vec3d headWin;
	if (!prj->project(headDir, headWin) || !std::isfinite(headWin[0]) || !std::isfinite(headWin[1]))
		return;

	const Vec4i vp = prj->getViewport();
	const double margin = 64.0;
	if (headWin[0] < vp[0] - margin || headWin[0] > vp[0] + vp[2] + margin ||
	    headWin[1] < vp[1] - margin || headWin[1] > vp[1] + vp[3] + margin)
	{
		return;
	}

	const double screenScale = qBound(1.0, static_cast<double>(StelApp::getInstance().getScreenScale()), 3.5);
	// Compact, crisp stellar hotpoint (never a bulky cotton-ball blob)
	const double baseRadiusPx = qBound(1.1, 1.35 * 0.42 * screenScale * static_cast<double>(m_widthScale), 4.6);

	auto drawQuad2d = [&](float radiusPx, const Vec4f& rgba) {
		const float cx = static_cast<float>(headWin[0]);
		const float cy = static_cast<float>(headWin[1]);
		Vec3f verts[4] = {
			Vec3f(cx - radiusPx, cy - radiusPx, 0.f),
			Vec3f(cx + radiusPx, cy - radiusPx, 0.f),
			Vec3f(cx + radiusPx, cy + radiusPx, 0.f),
			Vec3f(cx - radiusPx, cy + radiusPx, 0.f)
		};
		Vec4f cols[4] = { rgba, rgba, rgba, rgba };
		static const float texCoordData[] = { 0.f, 0.f, 1.f, 0.f, 1.f, 1.f, 0.f, 1.f };
		sPainter.setTexCoordPointer(2, GL_FLOAT, texCoordData);
		sPainter.setColorPointer(4, GL_FLOAT, cols);
		sPainter.setVertexPointer(3, GL_FLOAT, verts);
		sPainter.drawFromArray(StelPainter::TriangleFan, 4, 0, false);
	};

	sPainter.setBlending(true, GL_SRC_ALPHA, GL_ONE);
	sPainter.enableClientStates(true, true, true);
	m_bolideTexture->bind();

	// Tight spectral hotpoint halo + sharp pinpoint core
	const Vec4f haloColor(m_headTintColor[0], m_headTintColor[1], m_headTintColor[2],
			      qBound(0.f, headIntensity * 0.36f, 0.65f));
	drawQuad2d(static_cast<float>(baseRadiusPx * 1.55), haloColor);

	const Vec4f coreColor(1.0f, 1.0f, 1.0f, qBound(0.f, headIntensity * 0.92f, 1.0f));
	drawQuad2d(static_cast<float>(baseRadiusPx * 0.55), coreColor);

	sPainter.setBlending(false);
	sPainter.enableClientStates(false);
}

void Meteor::drawTrain(const StelCore* core, StelPainter& sPainter, const double& angularHalfWidth,
		       Vec3d& outHeadDir, Vec3d& outHeadTangent)
{
	Q_UNUSED(core)
	Q_UNUSED(angularHalfWidth)
	if (m_segments != m_outerColorVector.size() || m_segments != m_coreColorVector.size())
	{
		qWarning() << "Meteor: color arrays have an inconsistent size!";
		return;
	}

	const StelProjectorP prj = sPainter.getProjector();
	if (!prj)
		return;

	const Vec4i vp = prj->getViewport();
	const double vpX = static_cast<double>(vp[0]);
	const double vpY = static_cast<double>(vp[1]);
	const double vpW = qMax(1.0, static_cast<double>(vp[2]));
	const double vpH = qMax(1.0, static_cast<double>(vp[3]));
	const double maxDim = qMax(vpW, vpH);
	const double safeMargin = maxDim * 0.18;
	const double maxStepPx = maxDim * 0.08;
	const double centerPxPerRad = qMax(1.0, static_cast<double>(prj->getPixelPerRadAtCenter()));

	// Sample unit sky directions & project safely into 2D screen space, rejecting below-horizon,
	// behind-camera, or stereographic antipode-stretched segments so a meteor ALWAYS curves smoothly
	// with the spherical projection and can NEVER slash straight across the screen!
	QVector<Vec3d> unitPts(m_segments);
	QVector<Vec3d> winPts(m_segments);
	QVector<bool> validPts(m_segments, false);
	for (int i = 0; i < m_segments; ++i)
	{
		const double t = static_cast<double>(i) / static_cast<double>(m_segments - 1);
		Vec3d posi = m_posTrain;
		posi[2] = m_posTrain[2] + t * (m_position[2] - m_posTrain[2]);
		Vec3d altAz = radiantToAltAz(posi);
		const double n = altAz.norm();
		unitPts[i] = (n > 1e-12) ? (altAz / n) : Vec3d(0., 0., 1.);

		// Meteors ablate at 80-120 km altitude; skip any segment dipping below horizon
		if (unitPts[i][2] < -0.02)
			continue;

		Vec3d w;
		if (prj->project(unitPts[i], w) &&
		    std::isfinite(w[0]) && std::isfinite(w[1]) &&
		    w[0] >= vpX - safeMargin && w[0] <= vpX + vpW + safeMargin &&
		    w[1] >= vpY - safeMargin && w[1] <= vpY + vpH + safeMargin)
		{
			winPts[i] = w;
			validPts[i] = true;
		}
	}

	outHeadDir = unitPts.last();
	outHeadTangent = unitPts.last() - unitPts[qMax(0, m_segments - 2)];
	if (outHeadTangent.normSquared() < 1e-12)
		outHeadTangent = Vec3d(0., 1., 0.);
	else
		outHeadTangent.normalize();

	// Split into contiguous projected runs broken on invalid points, projection discontinuities,
	// excessive screen jumps, or extreme stereographic antipode magnification (> 5.5x center scale).
	QVector<QPair<int, int>> runs;
	int runStart = -1;
	for (int i = 0; i < m_segments; ++i)
	{
		bool breaks = !validPts[i];
		if (!breaks && runStart >= 0)
		{
			const double dx = winPts[i][0] - winPts[i - 1][0];
			const double dy = winPts[i][1] - winPts[i - 1][1];
			const double stepPx = std::hypot(dx, dy);
			const double cosAng = qBound(-1.0, unitPts[i - 1].dot(unitPts[i]), 1.0);
			const double dTheta = std::acos(cosAng);
			const bool antipodeStretched = (dTheta > 1e-5) && ((stepPx / dTheta) > centerPxPerRad * 5.5);
			if (prj->intersectViewportDiscontinuity(unitPts[i - 1], unitPts[i]) ||
			    stepPx > maxStepPx ||
			    antipodeStretched)
			{
				if (i - runStart >= 2)
					runs.append(qMakePair(runStart, i - 1));
				runStart = antipodeStretched ? -1 : i;
				continue;
			}
		}
		if (breaks)
		{
			if (runStart >= 0 && i - runStart >= 2)
				runs.append(qMakePair(runStart, i - 1));
			runStart = -1;
		}
		else if (runStart < 0)
		{
			runStart = i;
		}
	}
	if (runStart >= 0 && m_segments - runStart >= 2)
		runs.append(qMakePair(runStart, m_segments - 1));

	// Drop any degenerate run spanning an unphysical > 72% of screen width (projection singularity guard)
	QVector<QPair<int, int>> safeRuns;
	safeRuns.reserve(runs.size());
	for (const auto& run : runs)
	{
		double runLenPx = 0.0;
		for (int i = run.first + 1; i <= run.second; ++i)
			runLenPx += std::hypot(winPts[i][0] - winPts[i - 1][0], winPts[i][1] - winPts[i - 1][1]);
		if (runLenPx <= maxDim * 0.72)
			safeRuns.append(run);
	}
	runs = safeRuns;

	if (runs.isEmpty())
		return;

	// Compute ultra-sharp needle profile (razor-thin hairline entry -> compact ablation flare -> crisp needle tip)
	const double screenScale = qBound(1.0, static_cast<double>(StelApp::getInstance().getScreenScale()), 3.5);
	const double basePx = qBound(0.32, 0.36 * screenScale * static_cast<double>(m_widthScale), 2.1);

	QVector<double> halfWidthPx(m_segments);
	QVector<float> lumProfile(m_segments);
	for (int i = 0; i < m_segments; ++i)
	{
		const float u = static_cast<float>(i) / static_cast<float>(m_segments - 1);
		// Fine razor-sharp entry hairline that builds gracefully and tapers swiftly to a fine pointed tip
		const float entryLine = 0.16f + 0.52f * std::pow(u, 1.35f);
		const float tipTaper = (u > 0.84f)
			? qMax(0.10f, 1.0f - 0.88f * std::pow((u - 0.84f) / 0.16f, 1.15f))
			: 1.0f;
		const float spindle = entryLine * tipTaper;

		float flareBoost = 0.f;
		if (m_hasTerminalFlare)
		{
			// Tight Gaussian terminal ablation burst peaking at m_flarePos (~0.75-0.84)
			const float d = (u - m_flarePos) / 0.082f;
			flareBoost = m_flareStrength * std::exp(-d * d);
		}

		halfWidthPx[i] = basePx * static_cast<double>(qMax(0.14f, spindle * (1.0f + 0.92f * flareBoost)));

		// Crisp entry luminance ramping smoothly into blazing flare burst, then sharp dimming at tip
		const float onset = std::pow(u, 0.85f);
		const float tipDim = (u > 0.88f)
			? qMax(0.18f, 1.0f - 0.78f * ((u - 0.88f) / 0.12f))
			: 1.0f;
		float lum = m_aptMag * (0.28f + 0.72f * onset) * tipDim * (1.0f + 1.05f * flareBoost);
		if (i == 0)
			lum = 0.f;
		lumProfile[i] = qBound(0.f, lum, 1.25f);
	}

	// Stripe-free C1-smooth 5-column Gaussian cross-section ribbon:
	//   -1.0w (0%) -> -0.42w (42%) -> 0.0 (100%) -> +0.42w (42%) -> +1.0w (0%)
	// Eliminates concentric step-edge stripes completely while keeping the core needle-sharp!
	QVector<Vec3f> stripVerts[4];
	QVector<Vec4f> stripCols[4];
	for (int k = 0; k < 4; ++k)
	{
		stripVerts[k].reserve(2 * m_segments);
		stripCols[k].reserve(2 * m_segments);
	}

	auto drawRibbonLayer = [&](double widthMul, float alphaMul, int colorMode) {
		for (const auto& run : runs)
		{
			const int i0 = run.first;
			const int i1 = run.second;

			// Skip runs completely outside the visible viewport
			bool anyInVp = false;
			for (int i = i0; i <= i1; ++i)
			{
				if (winPts[i][0] >= vpX - 32.0 && winPts[i][0] <= vpX + vpW + 32.0 &&
				    winPts[i][1] >= vpY - 32.0 && winPts[i][1] <= vpY + vpH + 32.0)
				{
					anyInVp = true;
					break;
				}
			}
			if (!anyInVp)
				continue;

			for (int k = 0; k < 4; ++k)
			{
				stripVerts[k].clear();
				stripCols[k].clear();
			}
			double lastNx = 0.0, lastNy = 1.0;

			for (int i = i0; i <= i1; ++i)
			{
				const int iPrev = qMax(i0, i - 1);
				const int iNext = qMin(i1, i + 1);
				const double tx = winPts[iNext][0] - winPts[iPrev][0];
				const double ty = winPts[iNext][1] - winPts[iPrev][1];
				const double tLen = std::hypot(tx, ty);
				double nx = lastNx;
				double ny = lastNy;
				if (tLen > 1e-4)
				{
					nx = -ty / tLen;
					ny = tx / tLen;
					lastNx = nx;
					lastNy = ny;
				}

				const double hw = qMin(halfWidthPx[i] * widthMul, 14.0);
				const float cx = static_cast<float>(winPts[i][0]);
				const float cy = static_cast<float>(winPts[i][1]);
				const float ox = static_cast<float>(nx * hw);
				const float oy = static_cast<float>(ny * hw);

				Vec4f col;
				if (colorMode == 0)
				{
					col = m_outerColorVector[i];
				}
				else if (colorMode == 1)
				{
					const Vec4f& o = m_outerColorVector[i];
					const Vec4f& c = m_coreColorVector[i];
					col = Vec4f(o[0] * 0.65f + c[0] * 0.35f,
						    o[1] * 0.65f + c[1] * 0.35f,
						    o[2] * 0.65f + c[2] * 0.35f, 1.f);
				}
				else if (colorMode == 2)
				{
					col = m_coreColorVector[i];
				}
				else
				{
					const float u = static_cast<float>(i) / static_cast<float>(m_segments - 1);
					const float env = std::sin(u * M_PIf);
					col = Vec4f(m_afterglowColor[0], m_afterglowColor[1], m_afterglowColor[2],
						    qBound(0.f, env * env * alphaMul, 0.48f));
				}

				if (colorMode != 3)
				{
					const float fadeScale = (colorMode == 2) ? m_headFade : 1.0f;
					col[3] = qBound(0.f, lumProfile[i] * alphaMul * fadeScale, 1.0f);
				}

				const Vec4f colZero(col[0], col[1], col[2], 0.f);
				const Vec4f colMid(col[0], col[1], col[2], col[3] * 0.42f);
				const Vec3f pL2(cx - ox, cy - oy, 0.f);
				const Vec3f pL1(cx - ox * 0.42f, cy - oy * 0.42f, 0.f);
				const Vec3f pC(cx, cy, 0.f);
				const Vec3f pR1(cx + ox * 0.42f, cy + oy * 0.42f, 0.f);
				const Vec3f pR2(cx + ox, cy + oy, 0.f);

				stripVerts[0].append(pL2); stripCols[0].append(colZero);
				stripVerts[0].append(pL1); stripCols[0].append(colMid);

				stripVerts[1].append(pL1); stripCols[1].append(colMid);
				stripVerts[1].append(pC);  stripCols[1].append(col);

				stripVerts[2].append(pC);  stripCols[2].append(col);
				stripVerts[2].append(pR1); stripCols[2].append(colMid);

				stripVerts[3].append(pR1); stripCols[3].append(colMid);
				stripVerts[3].append(pR2); stripCols[3].append(colZero);
			}

			for (int k = 0; k < 4; ++k)
			{
				if (stripVerts[k].size() >= 4)
				{
					sPainter.setColorPointer(4, GL_FLOAT, stripCols[k].constData());
					sPainter.setVertexPointer(3, GL_FLOAT, stripVerts[k].constData());
					sPainter.drawFromArray(StelPainter::TriangleStrip, stripVerts[k].size(), 0, false);
				}
			}
		}
	};

	// Additive optical blending: smooth feathered spectral bloom + silky needle core (zero concentric stripes!)
	sPainter.setBlending(true, GL_SRC_ALPHA, GL_ONE);
	sPainter.enableClientStates(true, false, true);

	if (!m_headExtinguished || m_headFade > 0.02f)
	{
		// Pass 1: Smoothly feathered outer spectral optical bloom
		drawRibbonLayer(2.60, 0.28f, 0);
		// Pass 2: Seamless mid spectral sheath
		drawRibbonLayer(1.30, 0.72f, 1);
		// Pass 3: Razor-fine incandescent white-hot plasma needle core
		drawRibbonLayer(0.44, 0.98f, 2);
	}

	// Pass 4: Brief chemiluminescent fade (0.45..0.8s) bridging seamlessly into the drifting dust smoke train
	if (m_headExtinguished && m_hasAfterglow && m_afterglowRemaining > 0.f && m_afterglowDuration > 0.01f)
	{
		const float frac = m_afterglowRemaining / m_afterglowDuration;
		const float glowAlpha = m_peakAbsMag * frac * frac * 0.24f;
		if (glowAlpha > 0.01f)
		{
			drawRibbonLayer(1.75, glowAlpha, 3);
		}
	}

	sPainter.setBlending(false);
	sPainter.enableClientStates(false);
}

void Meteor::captureSmokeTrainAnchors()
{
	if (m_smokeCaptured)
		return;
	m_smokeCaptured = true;
	m_smokeAgeSec = 0.f;
	m_smokeAnchors.clear();
	m_smokeWeights.clear();
	m_smokeU.clear();

	constexpr int kSmokeSamples = 36;
	m_smokeAnchors.reserve(kSmokeSamples);
	m_smokeWeights.reserve(kSmokeSamples);
	m_smokeU.reserve(kSmokeSamples);

	// Capture anchors across the meteor's luminous ablation path [u = 0.18 .. 0.96]
	// Concentrating dust density around the terminal ablation flare (where real smoke persists longest!)
	for (int i = 0; i < kSmokeSamples; ++i)
	{
		const float frac = static_cast<float>(i) / static_cast<float>(kSmokeSamples - 1);
		const float u = 0.18f + 0.78f * frac;
		Vec3d posi = m_posTrain;
		posi[2] = m_posTrain[2] + static_cast<double>(u) * (m_position[2] - m_posTrain[2]);
		Vec3d altAz = radiantToAltAz(posi);
		const double n = altAz.norm();
		const Vec3d dir = (n > 1e-12) ? (altAz / n) : Vec3d(0., 0., 1.);
		m_smokeAnchors.append(dir);
		m_smokeU.append(u);

		// Density profile: continuous gossamer dust trail along upper track + prominent curling puff at ablation flare
		const float dFlare = (u - m_flarePos) / 0.16f;
		const float flareCloud = std::exp(-dFlare * dFlare);
		const float endFade = std::pow(std::sin(frac * M_PIf), 0.75f);
		const float w = qBound(0.f, endFade * (0.42f + 0.78f * flareCloud), 1.0f);
		m_smokeWeights.append(w);
	}

	// Build two orthonormal wind-shear axes perpendicular to the midpoint sky vector
	const Vec3d& pStart = m_smokeAnchors.first();
	const Vec3d& pEnd = m_smokeAnchors.last();
	Vec3d mid = (pStart + pEnd) * 0.5;
	if (mid.normSquared() < 1e-10)
		mid = Vec3d(0., 0., 1.);
	else
		mid.normalize();

	Vec3d pathDir = pEnd - pStart;
	if (pathDir.normSquared() < 1e-10)
		pathDir = Vec3d(0., 1., 0.);
	else
		pathDir.normalize();

	// Shear axis 1: sideways across the track (creates authentic S-curves & crescent wind hooks!)
	Vec3d ax1 = mid ^ pathDir;
	if (ax1.normSquared() < 1e-10)
		ax1 = Vec3d(1., 0., 0.);
	else
		ax1.normalize();
	// Shear axis 2: gently along-track / diagonal secondary eddy
	Vec3d ax2 = ax1 ^ mid;
	if (ax2.normSquared() < 1e-10)
		ax2 = Vec3d(0., 1., 0.);
	else
		ax2.normalize();

	m_smokeShearAxis1 = ax1;
	m_smokeShearAxis2 = ax2;
}

void Meteor::drawPersistentSmokeTrain(StelPainter& sPainter)
{
	if (!m_smokeCaptured || m_smokeAnchors.size() < 4 || m_smokeDurationSec <= 0.05f)
		return;
	const float age = m_smokeAgeSec;
	if (age <= 0.02f || age >= m_smokeDurationSec)
		return;

	const StelProjectorP prj = sPainter.getProjector();
	if (!prj)
		return;

	const Vec4i vp = prj->getViewport();
	const double vpX = static_cast<double>(vp[0]);
	const double vpY = static_cast<double>(vp[1]);
	const double vpW = qMax(1.0, static_cast<double>(vp[2]));
	const double vpH = qMax(1.0, static_cast<double>(vp[3]));
	const double maxDim = qMax(vpW, vpH);
	const double safeMargin = maxDim * 0.18;
	const double maxStepPx = maxDim * 0.08;
	const double centerPxPerRad = qMax(1.0, static_cast<double>(prj->getPixelPerRadAtCenter()));

	// Smooth birth (0..0.30s) and long gentle atmospheric dissipation (0.30s..duration)
	const float lifeFrac = qBound(0.f, age / m_smokeDurationSec, 1.f);
	const float fadeIn = qBound(0.f, age / 0.30f, 1.f);
	const float fadeOut = std::pow(qMax(0.f, 1.f - lifeFrac), 1.45f);
	const float masterAlpha = fadeIn * fadeOut * qBound(0.32f, m_peakAbsMag, 1.0f);
	if (masterAlpha <= 0.008f)
		return;

	// Compute wind-sheared drifted sky positions for each smoke anchor
	const int nPts = m_smokeAnchors.size();
	QVector<Vec3d> driftedDir(nPts);
	QVector<Vec3d> winPts(nPts);
	QVector<bool> validPts(nPts, false);

	const double driftAmp = static_cast<double>(m_smokeDriftRate) * static_cast<double>(age);
	for (int i = 0; i < nPts; ++i)
	{
		const float u = m_smokeU[i];
		// Two-harmonic mesospheric wind shear: bends straight trail into organic S-wave & curling hook
		const double wave1 = std::sin(static_cast<double>(m_smokeWindFreq * u + m_smokeWindPhase));
		const double wave2 = 0.52 * std::sin(static_cast<double>(m_smokeWindFreq * 2.25f * u + m_smokeWindPhase2));
		// Localized vortex curl right at the terminal ablation flare (like the real Perseid video!)
		const float dFlare = (u - m_flarePos) / 0.14f;
		const double flareCurl = 0.85 * std::exp(-static_cast<double>(dFlare * dFlare))
			* std::sin(static_cast<double>(m_smokeWindPhase + 0.55f * age));

		const double shift1 = driftAmp * (0.35 + 0.90 * wave1 + flareCurl);
		const double shift2 = driftAmp * (0.32 * wave2);

		Vec3d dir = m_smokeAnchors[i] + m_smokeShearAxis1 * shift1 + m_smokeShearAxis2 * shift2;
		const double dn = dir.norm();
		dir = (dn > 1e-12) ? (dir / dn) : m_smokeAnchors[i];
		driftedDir[i] = dir;

		Vec3d w;
		if (prj->project(dir, w) &&
		    std::isfinite(w[0]) && std::isfinite(w[1]) &&
		    w[0] >= vpX - safeMargin && w[0] <= vpX + vpW + safeMargin &&
		    w[1] >= vpY - safeMargin && w[1] <= vpY + vpH + safeMargin)
		{
			winPts[i] = w;
			validPts[i] = true;
		}
	}

	// Split into contiguous projected runs (never crossing discontinuity or off-screen jumps)
	QVector<QPair<int, int>> runs;
	int runStart = -1;
	double totalTrackPx = 0.0;
	for (int i = 0; i < nPts; ++i)
	{
		bool breaks = !validPts[i];
		if (!breaks && runStart >= 0)
		{
			const double dx = winPts[i][0] - winPts[i - 1][0];
			const double dy = winPts[i][1] - winPts[i - 1][1];
			const double step = std::hypot(dx, dy);
			const double cosAng = qBound(-1.0, driftedDir[i - 1].dot(driftedDir[i]), 1.0);
			const double dTheta = std::acos(cosAng);
			const bool antipodeStretched = (dTheta > 1e-5) && ((step / dTheta) > centerPxPerRad * 5.5);
			if (prj->intersectViewportDiscontinuity(driftedDir[i - 1], driftedDir[i]) || step > maxStepPx || antipodeStretched)
			{
				if (i - runStart >= 3)
					runs.append(qMakePair(runStart, i - 1));
				runStart = antipodeStretched ? -1 : i;
				continue;
			}
			totalTrackPx += step;
		}
		if (breaks)
		{
			if (runStart >= 0 && i - runStart >= 3)
				runs.append(qMakePair(runStart, i - 1));
			runStart = -1;
		}
		else if (runStart < 0)
		{
			runStart = i;
		}
	}
	if (runStart >= 0 && nPts - runStart >= 3)
		runs.append(qMakePair(runStart, nPts - 1));

	// Never inflate tiny distant meteors into visible smoke smudges
	if (runs.isEmpty() || totalTrackPx < 36.0)
		return;

	// Width scales naturally with both screen density and actual projected meteor trail length
	const double screenScale = qBound(1.0, static_cast<double>(StelApp::getInstance().getScreenScale()), 3.5);
	const double maxBaseHalfW = qBound(3.5 * screenScale, totalTrackPx * 0.085, 22.0 * screenScale);
	const double diffuseFactor = 0.30 + 0.78 * std::pow(static_cast<double>(lifeFrac), 0.55);

	// Authentic chemiluminescent / airglow-lit meteoric smoke (dusty rose-silver & pale sage-ash)
	const Vec3f outerSmokeRgb(
		qBound(0.f, m_afterglowColor[0] * 0.35f + 0.72f * 0.65f, 1.f),
		qBound(0.f, m_afterglowColor[1] * 0.35f + 0.74f * 0.65f, 1.f),
		qBound(0.f, m_afterglowColor[2] * 0.35f + 0.84f * 0.65f, 1.f));
	const Vec3f innerSmokeRgb(
		qBound(0.f, m_afterglowColor[0] * 0.45f + 0.90f * 0.55f, 1.f),
		qBound(0.f, m_afterglowColor[1] * 0.45f + 0.80f * 0.55f, 1.f),
		qBound(0.f, m_afterglowColor[2] * 0.45f + 0.86f * 0.55f, 1.f));

	// Stripe-free C1 flat-topped 6-column Gaussian smoke ribbon:
	//   -1.0w (0%) -> -0.58w (26%) -> -0.22w (88%) -> +0.22w (88%) -> +0.58w (26%) -> +1.0w (0%)
	// Flat Gaussian dome at center completely eliminates Mach-band center ridge stripes!
	QVector<Vec3f> sVerts[5];
	QVector<Vec4f> sCols[5];
	for (int k = 0; k < 5; ++k)
	{
		sVerts[k].reserve(2 * nPts);
		sCols[k].reserve(2 * nPts);
	}

	auto drawGaussianSmokeVeil = [&](double widthMul, float alphaMul, const Vec3f& rgb) {
		for (const auto& run : runs)
		{
			const int i0 = run.first;
			const int i1 = run.second;

			bool anyInVp = false;
			for (int i = i0; i <= i1; ++i)
			{
				if (winPts[i][0] >= vpX - 48.0 && winPts[i][0] <= vpX + vpW + 48.0 &&
				    winPts[i][1] >= vpY - 48.0 && winPts[i][1] <= vpY + vpH + 48.0)
				{
					anyInVp = true;
					break;
				}
			}
			if (!anyInVp)
				continue;

			for (int k = 0; k < 5; ++k)
			{
				sVerts[k].clear();
				sCols[k].clear();
			}
			double lastNx = 0.0, lastNy = 1.0;

			for (int i = i0; i <= i1; ++i)
			{
				const int iPrev = qMax(i0, i - 1);
				const int iNext = qMin(i1, i + 1);
				const double tx = winPts[iNext][0] - winPts[iPrev][0];
				const double ty = winPts[iNext][1] - winPts[iPrev][1];
				const double tLen = std::hypot(tx, ty);
				double nx = lastNx;
				double ny = lastNy;
				if (tLen > 1e-4)
				{
					nx = -ty / tLen;
					ny = tx / tLen;
					lastNx = nx;
					lastNy = ny;
				}

				const float u = m_smokeU[i];
				const float wDens = m_smokeWeights[i];
				const float endCap = (i == i0 || i == i1) ? 0.f : 1.f;
				// Smooth low-frequency cloud density modulation (no high-frequency vertex beading!)
				const float softWisp = 0.80f + 0.20f * std::sin(u * 9.0f + m_smokeWindPhase2);
				const double hw = maxBaseHalfW * diffuseFactor * widthMul * static_cast<double>(0.32f + 0.85f * wDens);

				const float cx = static_cast<float>(winPts[i][0]);
				const float cy = static_cast<float>(winPts[i][1]);
				const float ox = static_cast<float>(nx * hw);
				const float oy = static_cast<float>(ny * hw);

				const float peakA = qBound(0.f, masterAlpha * wDens * softWisp * endCap * alphaMul, 0.52f);
				const Vec4f c0(rgb[0], rgb[1], rgb[2], 0.f);
				const Vec4f c1(rgb[0], rgb[1], rgb[2], peakA * 0.26f);
				const Vec4f c2(rgb[0], rgb[1], rgb[2], peakA * 0.88f);

				const Vec3f p0(cx - ox,         cy - oy,         0.f);
				const Vec3f p1(cx - ox * 0.58f, cy - oy * 0.58f, 0.f);
				const Vec3f p2(cx - ox * 0.22f, cy - oy * 0.22f, 0.f);
				const Vec3f p3(cx + ox * 0.22f, cy + oy * 0.22f, 0.f);
				const Vec3f p4(cx + ox * 0.58f, cy + oy * 0.58f, 0.f);
				const Vec3f p5(cx + ox,         cy + oy,         0.f);

				sVerts[0].append(p0); sCols[0].append(c0); sVerts[0].append(p1); sCols[0].append(c1);
				sVerts[1].append(p1); sCols[1].append(c1); sVerts[1].append(p2); sCols[1].append(c2);
				sVerts[2].append(p2); sCols[2].append(c2); sVerts[2].append(p3); sCols[2].append(c2);
				sVerts[3].append(p3); sCols[3].append(c2); sVerts[3].append(p4); sCols[3].append(c1);
				sVerts[4].append(p4); sCols[4].append(c1); sVerts[4].append(p5); sCols[4].append(c0);
			}

			for (int k = 0; k < 5; ++k)
			{
				if (sVerts[k].size() >= 4)
				{
					sPainter.setColorPointer(4, GL_FLOAT, sCols[k].constData());
					sPainter.setVertexPointer(3, GL_FLOAT, sVerts[k].constData());
					sPainter.drawFromArray(StelPainter::TriangleStrip, sVerts[k].size(), 0, false);
				}
			}
		}
	};

	// Single silky C1-Gaussian smoke veil (zero concentric nested stripes!)
	sPainter.setBlending(true, GL_SRC_ALPHA, GL_ONE);
	sPainter.enableClientStates(true, false, true);
	drawGaussianSmokeVeil(1.85, 0.36f, innerSmokeRgb);
	sPainter.setBlending(false);
	sPainter.enableClientStates(false);
}

void Meteor::drawAirburstGlare(StelPainter& sPainter, const Vec3d& burstDir, float burstIntensity, const Vec3f& tintRgb)
{
	if (!m_bolideTexture || burstIntensity <= 0.01f)
		return;
	const StelProjectorP prj = sPainter.getProjector();
	if (!prj)
		return;

	Vec3d win;
	if (!prj->project(burstDir, win) || !std::isfinite(win[0]) || !std::isfinite(win[1]))
		return;
	const Vec4i vp = prj->getViewport();
	const double margin = 220.0;
	if (win[0] < vp[0] - margin || win[0] > vp[0] + vp[2] + margin ||
	    win[1] < vp[1] - margin || win[1] > vp[1] + vp[3] + margin)
	{
		return;
	}

	const double screenScale = qBound(1.0, static_cast<double>(StelApp::getInstance().getScreenScale()), 3.5);
	const float intensity = qBound(0.f, burstIntensity, 1.25f);
	const float smoothGlow = intensity * std::sqrt(intensity); // smooth gradual bloom as fireball brightens
	const float cx = static_cast<float>(win[0]);
	const float cy = static_cast<float>(win[1]);

	// 1. Continuous atmospheric Mie scattering glow moving smoothly with the blazing fireball
	sPainter.setBlending(true, GL_SRC_ALPHA, GL_ONE);
	sPainter.enableClientStates(true, true, true);
	m_bolideTexture->bind();

	auto drawBloomQuad = [&](float rPx, const Vec4f& rgba) {
		Vec3f verts[4] = {
			Vec3f(cx - rPx, cy - rPx, 0.f),
			Vec3f(cx + rPx, cy - rPx, 0.f),
			Vec3f(cx + rPx, cy + rPx, 0.f),
			Vec3f(cx - rPx, cy + rPx, 0.f)
		};
		Vec4f cols[4] = { rgba, rgba, rgba, rgba };
		static const float tc[] = { 0.f, 0.f, 1.f, 0.f, 1.f, 1.f, 0.f, 1.f };
		sPainter.setTexCoordPointer(2, GL_FLOAT, tc);
		sPainter.setColorPointer(4, GL_FLOAT, cols);
		sPainter.setVertexPointer(3, GL_FLOAT, verts);
		sPainter.drawFromArray(StelPainter::TriangleFan, 4, 0, false);
	};

	const float baseGlareR = static_cast<float>(qBound(14.0, (16.0 + 32.0 * intensity) * screenScale, 118.0));
	// Wide continuous atmospheric haze illumination (smoothly lights the sky around the fireball)
	drawBloomQuad(baseGlareR * 2.40f, Vec4f(tintRgb[0], tintRgb[1], tintRgb[2], qBound(0.f, smoothGlow * 0.22f, 0.28f)));
	// Warm/bright inner scattering aura
	drawBloomQuad(baseGlareR * 1.02f, Vec4f(0.95f * 0.45f + tintRgb[0] * 0.55f,
						0.95f * 0.45f + tintRgb[1] * 0.55f,
						0.95f * 0.45f + tintRgb[2] * 0.55f,
						qBound(0.f, smoothGlow * 0.36f, 0.48f)));
	// Blazing incandescent center
	drawBloomQuad(baseGlareR * 0.28f, Vec4f(1.f, 1.f, 1.f, qBound(0.f, smoothGlow * 0.78f, 0.94f)));

	// 2. Dazzling optical diffraction starburst rays ("刺眼光芒射线") — emerge gracefully only when truly dazzling!
	const float spikeT = qBound(0.f, (intensity - 0.26f) / 0.62f, 1.f);
	const float spikeVis = spikeT * spikeT * (3.f - 2.f * spikeT); // smoothstep
	if (spikeVis > 0.01f)
	{
		sPainter.enableClientStates(true, false, true);

		auto drawStarburstRay = [&](float angleRad, float lengthPx, float halfBasePx, float alphaPeak, const Vec3f& rayRgb) {
			const float dx = std::cos(angleRad);
			const float dy = std::sin(angleRad);
			const float nx = -dy;
			const float ny = dx;

			// Needle-sharp feathered diamond ray: bright white-hot root -> tinted mid -> invisible razor tip
			const Vec3f pMid1(cx + dx * lengthPx * 0.16f, cy + dy * lengthPx * 0.16f, 0.f);
			const Vec3f pTip(cx + dx * lengthPx, cy + dy * lengthPx, 0.f);
			const Vec3f pBack(cx - dx * halfBasePx * 0.8f, cy - dy * halfBasePx * 0.8f, 0.f);
			const Vec3f pLeft(cx + nx * halfBasePx, cy + ny * halfBasePx, 0.f);
			const Vec3f pRight(cx - nx * halfBasePx, cy - ny * halfBasePx, 0.f);

			const Vec4f cCore(1.f, 0.99f, 0.96f, qBound(0.f, alphaPeak, 0.92f));
			const Vec4f cEdge(rayRgb[0], rayRgb[1], rayRgb[2], 0.f);
			const Vec4f cMid(rayRgb[0] * 0.45f + 0.55f, rayRgb[1] * 0.45f + 0.55f, rayRgb[2] * 0.45f + 0.55f, qBound(0.f, alphaPeak * 0.48f, 0.65f));

			// Left half triangle fan from center -> tip -> left edge -> back
			Vec3f vL[3] = { pBack, pLeft, pTip };
			Vec4f cL[3] = { cCore, cEdge, cEdge };
			sPainter.setColorPointer(4, GL_FLOAT, cL);
			sPainter.setVertexPointer(3, GL_FLOAT, vL);
			sPainter.drawFromArray(StelPainter::Triangles, 3, 0, false);

			Vec3f vR[3] = { pBack, pTip, pRight };
			Vec4f cR[3] = { cCore, cEdge, cEdge };
			sPainter.setColorPointer(4, GL_FLOAT, cR);
			sPainter.setVertexPointer(3, GL_FLOAT, vR);
			sPainter.drawFromArray(StelPainter::Triangles, 3, 0, false);

			// Crisp white inner spine needle along the first 55% of the ray
			const float spineW = qMax(0.45f, halfBasePx * 0.34f);
			const Vec3f pTipInner(cx + dx * lengthPx * 0.62f, cy + dy * lengthPx * 0.62f, 0.f);
			Vec3f vS[4] = {
				Vec3f(cx + nx * spineW, cy + ny * spineW, 0.f),
				pTipInner,
				Vec3f(cx - nx * spineW, cy - ny * spineW, 0.f),
				pMid1
			};
			Vec4f cS[4] = { cEdge, cEdge, cEdge, cMid };
			sPainter.setColorPointer(4, GL_FLOAT, cS);
			sPainter.setVertexPointer(3, GL_FLOAT, vS);
			sPainter.drawFromArray(StelPainter::TriangleFan, 4, 0, false);
		};

		// Deterministic fast hash per ray index -> [0, 1] so every meteor has its own unique organic signature
		auto rayRand = [&](int idx) -> float {
			unsigned int h = m_glareSeed ^ static_cast<unsigned int>(idx * 2654435761u);
			h ^= (h >> 16);
			h *= 2246822519u;
			h ^= (h >> 13);
			return static_cast<float>(h & 0xFFFFu) / 65535.f;
		};

		const float primaryLen = baseGlareR * (1.20f + 0.85f * spikeVis);
		const float primaryBaseW = static_cast<float>(qBound(1.0, 1.45 * screenScale * (0.62 + 0.52 * spikeVis), 4.8));

		if (m_glareStyle == 0)
		{
			// Style 0: Pure atmospheric scattering haze (no sharp spikes — lush hazy glow only!)
		}
		else if (m_glareStyle == 1)
		{
			// Style 1: Delicate asymmetric 4-point cross flare (subtle natural lens/eye cross)
			const float axisRatio = 0.62f + 0.34f * rayRand(1);
			for (int k = 0; k < 4; ++k)
			{
				const float ang = m_glareAngleOffset + (M_PIf * 0.5f) * static_cast<float>(k) + (rayRand(10 + k) - 0.5f) * 0.05f;
				const float lenMul = ((k % 2 == 0) ? 1.18f : axisRatio) * (0.86f + 0.28f * rayRand(20 + k));
				const float wMul = 0.80f + 0.30f * rayRand(30 + k);
				drawStarburstRay(ang, primaryLen * lenMul, primaryBaseW * wMul, spikeVis * (0.46f + 0.16f * rayRand(40 + k)), tintRgb);
			}
		}
		else if (m_glareStyle == 2)
		{
			// Style 2: Cinematic elongated anamorphic streak + tiny faint cross glints
			const float mainAng = m_glareAngleOffset * 0.18f - 0.14f; // gently near-horizontal / slightly tilted
			const float longMul = 1.45f + 0.55f * rayRand(2);
			drawStarburstRay(mainAng,          primaryLen * longMul, primaryBaseW * 0.95f, spikeVis * 0.56f, tintRgb);
			drawStarburstRay(mainAng + M_PIf,  primaryLen * longMul * (0.88f + 0.20f * rayRand(3)), primaryBaseW * 0.95f, spikeVis * 0.54f, tintRgb);
			// Faint short perpendicular glint
			drawStarburstRay(mainAng + M_PIf * 0.5f, primaryLen * 0.42f, primaryBaseW * 0.62f, spikeVis * 0.26f, tintRgb);
			drawStarburstRay(mainAng - M_PIf * 0.5f, primaryLen * 0.38f, primaryBaseW * 0.62f, spikeVis * 0.24f, tintRgb);
		}
		else if (m_glareStyle == 3)
		{
			// Style 3: Organic uneven eyelash / corneal scatter rays (9..14 irregular fine radial filaments!)
			const int rayCount = 9 + static_cast<int>(rayRand(4) * 6.f);
			for (int k = 0; k < rayCount; ++k)
			{
				const float baseSector = (2.f * M_PIf * static_cast<float>(k)) / static_cast<float>(rayCount);
				const float ang = m_glareAngleOffset + baseSector + (rayRand(50 + k) - 0.5f) * 0.42f;
				const float lenMul = 0.36f + 1.05f * std::pow(rayRand(70 + k), 1.35f);
				const float wMul = 0.42f + 0.56f * rayRand(90 + k);
				const float shimmer = 0.86f + 0.14f * std::sin(m_burnTimeSec * (11.f + 9.f * rayRand(110 + k)) + static_cast<float>(k));
				const float aPeak = spikeVis * (0.24f + 0.36f * rayRand(130 + k)) * shimmer;
				drawStarburstRay(ang, primaryLen * lenMul, primaryBaseW * wMul, aPeak, tintRgb);
			}
		}
		else
		{
			// Style 4: Classic 6- or 8-point aperture starburst with per-ray organic length & weight variance
			const int points = (rayRand(5) < 0.55f) ? 6 : 8;
			const float step = (2.f * M_PIf) / static_cast<float>(points);
			for (int k = 0; k < points; ++k)
			{
				const float ang = m_glareAngleOffset + step * static_cast<float>(k);
				const float pairJitter = 0.78f + 0.46f * rayRand(150 + (k % (points / 2)));
				const float rayJitter = 0.88f + 0.24f * rayRand(170 + k);
				drawStarburstRay(ang, primaryLen * pairJitter * rayJitter, primaryBaseW * (0.72f + 0.36f * rayRand(190 + k)),
						 spikeVis * (0.44f + 0.16f * rayRand(210 + k)), tintRgb);
			}
		}

		// Whisper-soft faint optical atmospheric halo ring (barely perceptible at extreme peak only, never a hard circle)
		if (spikeVis > 0.35f)
		{
			constexpr int kRingSegs = 48;
			const float ringR = baseGlareR * 1.18f;
			const float ringHalfW = qMax(8.0f, ringR * 0.48f);
			const float ringAlpha = qBound(0.f, (spikeVis - 0.35f) * 0.068f, 0.048f);

			QVector<Vec3f> rInVerts, rOutVerts;
			QVector<Vec4f> rInCols, rOutCols;
			rInVerts.reserve(2 * (kRingSegs + 1));
			rInCols.reserve(2 * (kRingSegs + 1));
			rOutVerts.reserve(2 * (kRingSegs + 1));
			rOutCols.reserve(2 * (kRingSegs + 1));

			const Vec4f cPeak(tintRgb[0] * 0.65f + 0.35f, tintRgb[1] * 0.65f + 0.35f, tintRgb[2] * 0.65f + 0.35f, ringAlpha);
			const Vec4f cZero(cPeak[0], cPeak[1], cPeak[2], 0.f);
			for (int i = 0; i <= kRingSegs; ++i)
			{
				const float ang = (2.f * M_PIf * static_cast<float>(i)) / static_cast<float>(kRingSegs);
				const float ca = std::cos(ang);
				const float sa = std::sin(ang);
				const Vec3f pInner(cx + ca * (ringR - ringHalfW), cy + sa * (ringR - ringHalfW), 0.f);
				const Vec3f pMid(cx + ca * ringR, cy + sa * ringR, 0.f);
				const Vec3f pOuter(cx + ca * (ringR + ringHalfW), cy + sa * (ringR + ringHalfW), 0.f);
				rInVerts.append(pInner); rInCols.append(cZero);
				rInVerts.append(pMid);   rInCols.append(cPeak);
				rOutVerts.append(pMid);   rOutCols.append(cPeak);
				rOutVerts.append(pOuter); rOutCols.append(cZero);
			}
			sPainter.setColorPointer(4, GL_FLOAT, rInCols.constData());
			sPainter.setVertexPointer(3, GL_FLOAT, rInVerts.constData());
			sPainter.drawFromArray(StelPainter::TriangleStrip, rInVerts.size(), 0, false);
			sPainter.setColorPointer(4, GL_FLOAT, rOutCols.constData());
			sPainter.setVertexPointer(3, GL_FLOAT, rOutVerts.constData());
			sPainter.drawFromArray(StelPainter::TriangleStrip, rOutVerts.size(), 0, false);
		}
	}

	sPainter.setBlending(false);
	sPainter.enableClientStates(false);
}

void Meteor::spawnBreakupFragments()
{
	m_fragments.clear();
	StelApp& app = StelApp::getInstance();

	// 2 glowing companion lead chunks (matching the iconic twin-head Shijiazhuang superbolide!)
	for (int i = 0; i < 2; ++i)
	{
		BreakupFragment f;
		const float ang = 2.f * M_PIf * app.getRandF();
		const double lateralSpeed = 0.55 + 0.95 * static_cast<double>(app.getRandF());
		f.originPosRad = m_position;
		f.originPosRad[2] += 1.6 + 3.8 * static_cast<double>(i) + 1.4 * static_cast<double>(app.getRandF());
		f.initVelRad = Vec3d(std::cos(ang) * lateralSpeed, std::sin(ang) * lateralSpeed, -m_speed * (0.90 - 0.09 * i));
		f.posRad = f.originPosRad;
		f.prevPosRad = f.originPosRad - f.initVelRad * 0.12;
		f.dragRate = 0.18f + 0.12f * app.getRandF();
		f.sizePx = 3.2f + 0.9f * app.getRandF();
		f.brightness = 1.0f - 0.10f * i;
		f.ageSec = -1.f;
		f.lifeSec = 1.25f + 0.45f * app.getRandF();
		f.isLeadChunk = true;
		m_fragments.append(f);
	}

	// 7-9 smaller trailing glowing sparks/fragments fanned behind the twin lead chunks
	const int sparkCount = 7 + static_cast<int>(app.getRandF() * 3.f);
	for (int i = 0; i < sparkCount; ++i)
	{
		BreakupFragment f;
		const float ang = 2.f * M_PIf * app.getRandF();
		const double lateralSpeed = 0.8 + 2.2 * static_cast<double>(app.getRandF());
		const double speedFrac = 0.48 + 0.34 * static_cast<double>(app.getRandF());
		f.originPosRad = m_position;
		f.originPosRad[2] += 3.5 + 9.5 * static_cast<double>(app.getRandF());
		f.initVelRad = Vec3d(std::cos(ang) * lateralSpeed, std::sin(ang) * lateralSpeed, -m_speed * speedFrac);
		f.posRad = f.originPosRad;
		f.prevPosRad = f.originPosRad - f.initVelRad * 0.07;
		f.dragRate = 0.48f + 0.55f * app.getRandF();
		f.sizePx = 1.15f + 1.05f * app.getRandF();
		f.brightness = 0.65f + 0.32f * app.getRandF();
		f.ageSec = -1.f;
		f.lifeSec = 0.70f + 0.72f * app.getRandF();
		f.isLeadChunk = false;
		m_fragments.append(f);
	}
}

void Meteor::drawFragments(StelPainter& sPainter)
{
	if (m_fragments.isEmpty() || !m_bolideTexture)
		return;
	const StelProjectorP prj = sPainter.getProjector();
	if (!prj)
		return;

	const Vec4i vp = prj->getViewport();
	const double vpX = static_cast<double>(vp[0]);
	const double vpY = static_cast<double>(vp[1]);
	const double vpW = qMax(1.0, static_cast<double>(vp[2]));
	const double vpH = qMax(1.0, static_cast<double>(vp[3]));
	const double margin = 64.0;
	const double maxSegPx = qMax(vpW, vpH) * 0.22;
	const double screenScale = qBound(1.0, static_cast<double>(StelApp::getInstance().getScreenScale()), 3.5);

	sPainter.setBlending(true, GL_SRC_ALPHA, GL_ONE);
	static const float tc[] = { 0.f, 0.f, 1.f, 0.f, 1.f, 1.f, 0.f, 1.f };

	for (const auto& frag : m_fragments)
	{
		if (frag.ageSec < 0.f || frag.ageSec >= frag.lifeSec || frag.lifeSec <= 0.01f)
			continue;

		Vec3d headDir = radiantToAltAz(frag.posRad);
		const double hn = headDir.norm();
		if (hn < 1e-12) continue;
		headDir /= hn;

		Vec3d headWin;
		if (!prj->project(headDir, headWin) || !std::isfinite(headWin[0]) || !std::isfinite(headWin[1]))
			continue;
		if (headWin[0] < vpX - margin || headWin[0] > vpX + vpW + margin ||
		    headWin[1] < vpY - margin || headWin[1] > vpY + vpH + margin)
			continue;

		const float lifeFrac = qBound(0.f, frag.ageSec / frag.lifeSec, 1.f);
		// Thermal blackbody cooling: incandescent white-gold -> bright amber -> molten orange-red ember
		Vec3f rgb;
		if (lifeFrac < 0.35f)
		{
			const float t = lifeFrac / 0.35f;
			rgb = Vec3f(1.0f, 0.96f - 0.18f * t, 0.86f - 0.50f * t);
		}
		else
		{
			const float t = (lifeFrac - 0.35f) / 0.65f;
			rgb = Vec3f(1.0f - 0.14f * t, 0.78f - 0.48f * t, 0.36f - 0.28f * t);
		}
		const float alpha = qBound(0.f, frag.brightness * std::pow(1.f - lifeFrac, 1.25f), 1.f);
		if (alpha < 0.02f)
			continue;

		// Short glowing ember wake behind fragment
		Vec3d tailDir = radiantToAltAz(frag.prevPosRad);
		const double tn = tailDir.norm();
		Vec3d tailWin;
		if (tn > 1e-12)
		{
			tailDir /= tn;
			if (prj->project(tailDir, tailWin) &&
			    std::isfinite(tailWin[0]) && std::isfinite(tailWin[1]) &&
			    !prj->intersectViewportDiscontinuity(tailDir, headDir))
			{
				const double dx = headWin[0] - tailWin[0];
				const double dy = headWin[1] - tailWin[1];
				const double len = std::hypot(dx, dy);
				if (len > 1.0 && len < maxSegPx)
				{
					const float nx = static_cast<float>(-dy / len);
					const float ny = static_cast<float>(dx / len);
					const float hw = static_cast<float>(qBound(0.5, 0.48 * frag.sizePx * screenScale, 3.6));
					Vec3f wv[4] = {
						Vec3f(static_cast<float>(tailWin[0]), static_cast<float>(tailWin[1]), 0.f),
						Vec3f(static_cast<float>(tailWin[0]), static_cast<float>(tailWin[1]), 0.f),
						Vec3f(static_cast<float>(headWin[0]) - nx * hw, static_cast<float>(headWin[1]) - ny * hw, 0.f),
						Vec3f(static_cast<float>(headWin[0]) + nx * hw, static_cast<float>(headWin[1]) + ny * hw, 0.f)
					};
					Vec4f wc[4] = {
						Vec4f(rgb[0], rgb[1], rgb[2], 0.f),
						Vec4f(rgb[0], rgb[1], rgb[2], 0.f),
						Vec4f(rgb[0], rgb[1], rgb[2], alpha * 0.55f),
						Vec4f(rgb[0], rgb[1], rgb[2], alpha * 0.55f)
					};
					sPainter.enableClientStates(true, false, true);
					sPainter.setColorPointer(4, GL_FLOAT, wc);
					sPainter.setVertexPointer(3, GL_FLOAT, wv);
					sPainter.drawFromArray(StelPainter::TriangleStrip, 4, 0, false);
				}
			}
		}

		// Glowing fragment head + soft warm atmospheric coma for lead chunks
		sPainter.enableClientStates(true, true, true);
		m_bolideTexture->bind();
		const float cx = static_cast<float>(headWin[0]);
		const float cy = static_cast<float>(headWin[1]);
		const float rCore = static_cast<float>(qBound(1.3, frag.sizePx * 1.15 * screenScale, 9.5));

		auto drawSpot = [&](float rPx, const Vec4f& rgba) {
			Vec3f v[4] = {
				Vec3f(cx - rPx, cy - rPx, 0.f),
				Vec3f(cx + rPx, cy - rPx, 0.f),
				Vec3f(cx + rPx, cy + rPx, 0.f),
				Vec3f(cx - rPx, cy + rPx, 0.f)
			};
			Vec4f c[4] = { rgba, rgba, rgba, rgba };
			sPainter.setTexCoordPointer(2, GL_FLOAT, tc);
			sPainter.setColorPointer(4, GL_FLOAT, c);
			sPainter.setVertexPointer(3, GL_FLOAT, v);
			sPainter.drawFromArray(StelPainter::TriangleFan, 4, 0, false);
		};

		if (frag.isLeadChunk)
		{
			drawSpot(rCore * 4.2f, Vec4f(rgb[0], rgb[1], rgb[2], alpha * 0.28f));
			drawSpot(rCore * 1.8f, Vec4f(rgb[0], rgb[1], rgb[2], alpha * 0.72f));
			drawSpot(rCore * 0.78f, Vec4f(1.f, 0.98f, 0.92f, alpha));
		}
		else
		{
			drawSpot(rCore * 2.1f, Vec4f(rgb[0], rgb[1], rgb[2], alpha * 0.52f));
			drawSpot(rCore * 0.85f, Vec4f(1.f, 0.94f, 0.82f, alpha * 0.92f));
		}
	}

	sPainter.setBlending(false);
	sPainter.enableClientStates(false);
}
