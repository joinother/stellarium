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
	, m_headTintColor(0.35f, 1.0f, 0.72f)
	, m_afterglowColor(0.18f, 0.96f, 0.62f)
	, m_bolideTexture(bolideTexture)
	, m_segments(24)
{
}

Meteor::~Meteor()
{
	m_bolideTexture.clear();
	m_outerColorVector.clear();
	m_coreColorVector.clear();
	m_lineColorVector.clear();
	m_trainColorVector.clear();
}

void Meteor::configureMorphology(bool forceFireball, float speedKmS, const QList<ColorPair>& colors)
{
	StelApp& app = StelApp::getInstance();
	const float r = app.getRandF();
	const bool isFast = speedKmS >= 48.f;

	// Choose realistic morphology class:
	//   - MicroNeedle: slender, crisp, fast fine streaks
	//   - MediumStreak: classic colorful emerald / amber / violet streaks
	//   - BrightFireball: thicker glowing spindle with terminal ablation flare & persistent O I/Mg afterglow
	if (forceFireball || m_absMag >= 0.78f || (m_absMag >= 0.58f && r > 0.62f))
	{
		m_widthScale = forceFireball
			? (1.30f + 0.35f * app.getRandF())
			: (1.12f + 0.42f * app.getRandF());
		m_trainSeconds = 0.78f + 0.40f * app.getRandF();
		m_hasTerminalFlare = forceFireball || app.getRandF() > 0.28f;
		m_flarePos = 0.72f + 0.16f * app.getRandF();
		m_flareStrength = forceFireball
			? (0.85f + 0.45f * app.getRandF())
			: (0.50f + 0.55f * app.getRandF());
		m_hasAfterglow = forceFireball || (isFast && app.getRandF() > 0.35f) || app.getRandF() > 0.62f;
		m_afterglowDuration = m_hasAfterglow ? (0.95f + 1.05f * app.getRandF()) : 0.f;
		m_afterglowRemaining = m_afterglowDuration;
	}
	else if (m_absMag >= 0.32f || r > 0.36f)
	{
		m_widthScale = 0.80f + 0.32f * app.getRandF();
		m_trainSeconds = 0.60f + 0.34f * app.getRandF();
		m_hasTerminalFlare = app.getRandF() > 0.62f;
		m_flarePos = 0.74f + 0.15f * app.getRandF();
		m_flareStrength = 0.38f + 0.38f * app.getRandF();
		m_hasAfterglow = isFast && app.getRandF() > 0.75f;
		m_afterglowDuration = m_hasAfterglow ? (0.60f + 0.45f * app.getRandF()) : 0.f;
		m_afterglowRemaining = m_afterglowDuration;
	}
	else
	{
		// Abundant razor-thin micro-meteors providing natural depth & scale contrast
		m_widthScale = 0.48f + 0.24f * app.getRandF();
		m_trainSeconds = 0.44f + 0.26f * app.getRandF();
		m_hasTerminalFlare = false;
		m_flareStrength = 0.f;
		m_hasAfterglow = false;
		m_afterglowDuration = 0.f;
		m_afterglowRemaining = 0.f;
	}

	// Derive head coma tint and ionization afterglow hue from the spectral palette
	if (!colors.isEmpty())
	{
		const Vec4f headRgba = getColorFromName(colors.last().first);
		m_headTintColor = Vec3f(headRgba[0], headRgba[1], headRgba[2]);
		// Persistent trains in Earth's upper atmosphere are dominated by forbidden O I (557.7 nm green)
		// blended slightly with the meteor's primary metallic emission.
		const Vec4f midRgba = getColorFromName(colors[colors.size() / 2].first);
		m_afterglowColor = Vec3f(
			qBound(0.f, 0.14f * 0.60f + midRgba[0] * 0.40f, 1.f),
			qBound(0.f, 0.96f * 0.60f + midRgba[1] * 0.40f, 1.f),
			qBound(0.f, 0.64f * 0.60f + midRgba[2] * 0.40f, 1.f));
	}
}

void Meteor::init(const float& radiantAlpha, const float& radiantDelta,
		  const float& speed, const QList<ColorPair> colors)
{
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
	if (radiantAlt < 0.0262f) // (<1.5 degrees) earth grazing meteor ?
	{
		// earth-grazers are rare!
		float prob = StelApp::getInstance().getRandF();
		if (prob > 0.3f) {
			m_rejectionReason = QStringLiteral("earth-grazer-probability");
			return;
		}

		// limit lifetime to 12sec
		m_finalZ = -static_cast<float>(m_position[2]);
		m_finalZ = qMax(static_cast<float>(m_position[2]) - static_cast<float>(m_speed) * 12.f, m_finalZ);

		m_minDist = xyDist;
	}
	else
	{
		// limit lifetime to 12sec
		m_finalZ = meteorZ(M_PI_2f - meteorAlt, MIN_ALTITUDE);
		m_finalZ = qMax(static_cast<float>(m_position[2]) - static_cast<float>(m_speed) * 12.0f, m_finalZ);

		m_minDist = sqrt(m_finalZ * m_finalZ + xyDist * xyDist);
	}

	// a meteor cannot hit the observer!
	if (m_minDist < MIN_ALTITUDE) {
		m_rejectionReason = QStringLiteral("observer-distance");
		return;
	}

	// select random magnitude [-4.5; 4.0] with slightly richer distribution of vivid bright meteors
	const float uMag = StelApp::getInstance().getRandF();
	float Mag = uMag * 8.5f - 4.5f;
	// compute RMag and CMag
	RCMag rcMag;
	if (m_core->getSkyDrawer()->computeRCMag(Mag, &rcMag) && rcMag.luminance > 0.f)
		m_absMag = qBound(0.18f, rcMag.luminance, 1.0f);
	else
		m_absMag = qBound(0.18f, std::pow(10.f, -0.4f * (Mag + 4.5f)), 1.f);

	// most visible meteors are under about 220km distant
	// scale max mag down gently if outside this range
	float scale = std::pow(210.0f / m_minDist, 1.65f);
	m_absMag = qBound(0.16f, m_absMag * qMin(scale, 1.0f), 1.0f);
	m_peakAbsMag = m_absMag;
	m_aptMag = m_absMag;

	configureMorphology(false, speed, colors);

	// build the color vector
	buildColorVectors(colors);

	m_alive = true;
}

void Meteor::initInViewport(const Vec3d& centerAltAz, float offsetRightRad, float offsetUpRad,
			    float slopeAngleRad, float speed, const QList<ColorPair>& colors,
			    bool isFireball, float startDelaySec)
{
	m_bypassDaylight = true;
	m_startDelay = qMax(0.f, startDelaySec);
	m_headExtinguished = false;
	m_headFade = 1.f;
	m_speed = static_cast<double>(qBound(24.f, speed, 72.f));

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

	// Burn duration ~0.65..1.15 seconds for crisp, satisfying angular sweep
	const double burnSeconds = isFireball ? (0.95 + 0.30 * StelApp::getInstance().getRandF())
	                                      : (0.62 + 0.32 * StelApp::getInstance().getRandF());
	m_finalZ = m_initialZ - static_cast<float>(m_speed * burnSeconds);
	m_minDist = static_cast<float>(qMax(90.0, startPosKm.norm() * 0.85));

	m_absMag = isFireball ? 0.96f : (0.62f + 0.26f * StelApp::getInstance().getRandF());
	m_peakAbsMag = m_absMag;
	m_aptMag = m_absMag;

	configureMorphology(isFireball, static_cast<float>(m_speed), colors);
	buildColorVectors(colors);

	m_alive = true;
	m_rejectionReason.clear();
}

bool Meteor::update(double deltaTime)
{
	if (!m_alive)
	{
		return false;
	}

	const double dt = qBound(0.0, deltaTime, 0.15);
	if (m_startDelay > 0.f)
	{
		m_startDelay -= static_cast<float>(dt);
		return true;
	}

	const bool speedBlocked = !m_bypassDaylight && !m_core->getRealTimeSpeed();
	const bool pastBurn = static_cast<float>(m_position[2]) < m_finalZ;

	if (speedBlocked || pastBurn)
	{
		m_headExtinguished = true;
		// Hot head extinguishes crisply (~0.32s)
		m_headFade = qMax(0.f, m_headFade - static_cast<float>(dt) * 3.1f);

		if (m_hasAfterglow && m_afterglowRemaining > 0.f && !speedBlocked)
		{
			m_afterglowRemaining = qMax(0.f, m_afterglowRemaining - static_cast<float>(dt));
			const float glowRatio = m_afterglowDuration > 0.01f
				? (m_afterglowRemaining / m_afterglowDuration)
				: 0.f;
			// Smooth exponential-like ionization decay
			m_absMag = m_peakAbsMag * qMax(m_headFade, glowRatio * glowRatio * 0.58f);
			if (m_headFade <= 0.f && m_afterglowRemaining <= 0.f)
			{
				m_alive = false;
				return false;
			}
		}
		else
		{
			m_absMag -= static_cast<float>(dt) * 2.4f;
			if (m_absMag <= 0.f)
			{
				m_alive = false;
				return false;
			}
		}
	}

	// Only advance head while still burning (once extinguished, ionization train stays anchored in upper atmosphere)
	if (!m_headExtinguished)
	{
		m_position[2] -= m_speed * dt;
		const double maxTrainDist = m_speed * static_cast<double>(m_trainSeconds);
		if (m_position[2] + maxTrainDist > static_cast<double>(m_initialZ))
		{
			m_posTrain[2] = static_cast<double>(m_initialZ);
		}
		else
		{
			m_posTrain[2] = m_position[2] + maxTrainDist;
		}
	}

	// update apparent magnitude based on distance to observer
	const float distNorm = qMax(1.f, static_cast<float>(m_position.norm()));
	const float scale = std::pow(m_minDist / distNorm, 1.5f);
	m_aptMag = qBound(0.f, m_absMag * qMin(scale, 1.0f), 1.0f);

	return true;
}

void Meteor::draw(const StelCore* core, StelPainter& sPainter)
{
	if (!m_alive || m_startDelay > 0.f)
	{
		return;
	}

	double angularHalfWidth = 0.0;
	double bolideAngularSize = 0.0;
	calculateThickness(core, sPainter, angularHalfWidth, bolideAngularSize);

	Vec3d headDir(0., 0., 1.);
	Vec3d headTangent(0., 1., 0.);
	drawTrain(core, sPainter, angularHalfWidth, headDir, headTangent);

	const float headIntensity = m_aptMag * m_headFade;
	if (headIntensity > 0.02f)
	{
		drawBolide(sPainter, headDir, headTangent, bolideAngularSize, headIntensity);
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
		{ "emerald",      {  16.f, 250.f, 142.f}},
		{ "cyanGreen",    {  96.f, 255.f, 210.f}},
		{ "blueGreen",    {  24.f, 248.f, 162.f}},
		{ "amberGold",    { 255.f, 146.f,  36.f}},
		{ "orangeYellow", { 255.f, 162.f,  48.f}},
		{ "paleGold",     { 255.f, 214.f, 118.f}},
		{ "yellow",       { 255.f, 224.f,  98.f}},
		{ "iceBlue",      { 108.f, 178.f, 255.f}},
		{ "violet",       { 186.f, 108.f, 255.f}},
		{ "roseMagenta",  { 255.f,  76.f, 138.f}},
		{ "red",          { 255.f,  72.f,  84.f}},
		{ "white",        { 242.f, 248.f, 255.f}}
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

		// Incandescent white-hot core: slightly tinted at the cool tail, blazing white at body & head
		const float whiteMix = qBound(0.42f, 0.42f + 0.54f * std::pow(u, 0.85f), 0.96f);
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
	if (bolideAngularSize <= 0.0 || !m_bolideTexture || headIntensity <= 0.01f)
	{
		return;
	}

	// Build true camera-facing orthonormal frame (S, U) around headDir on the unit celestial sphere
	Vec3d S = headDir ^ tangentDir;
	if (S.normSquared() < 1e-10)
	{
		Vec3d ref(0., 0., 1.);
		if (std::fabs(headDir[2]) > 0.9)
			ref = Vec3d(1., 0., 0.);
		S = headDir ^ ref;
	}
	S.normalize();
	Vec3d U = S ^ headDir;
	U.normalize();

	auto drawQuad = [&](double radiusRad, const Vec4f& rgba) {
		Vec3d verts[4] = {
			headDir - S * radiusRad - U * radiusRad,
			headDir + S * radiusRad - U * radiusRad,
			headDir + S * radiusRad + U * radiusRad,
			headDir - S * radiusRad + U * radiusRad
		};
		Vec4f cols[4] = { rgba, rgba, rgba, rgba };
		static const float texCoordData[] = { 0.f, 0.f, 1.f, 0.f, 1.f, 1.f, 0.f, 1.f };
		sPainter.setTexCoordPointer(2, GL_FLOAT, texCoordData);
		sPainter.setColorPointer(4, GL_FLOAT, cols);
		sPainter.setVertexPointer(3, GL_DOUBLE, verts);
		sPainter.drawFromArray(StelPainter::TriangleFan, 4, 0, true);
	};

	sPainter.setBlending(true, GL_SRC_ALPHA, GL_ONE);
	sPainter.enableClientStates(true, true, true);
	m_bolideTexture->bind();

	const double scaledSize = bolideAngularSize * static_cast<double>(m_widthScale);
	// Outer spectral emission coma (tinted emerald / amber / violet / ice-blue)
	const Vec4f haloColor(m_headTintColor[0], m_headTintColor[1], m_headTintColor[2],
			      qBound(0.f, headIntensity * 0.65f, 0.95f));
	drawQuad(scaledSize * 1.45, haloColor);

	// Inner incandescent white-hot plasma head
	const Vec4f coreColor(1.0f, 1.0f, 1.0f, qBound(0.f, headIntensity * 1.05f, 1.0f));
	drawQuad(scaledSize * 0.62, coreColor);

	sPainter.setBlending(false);
	sPainter.enableClientStates(false);
}

void Meteor::drawTrain(const StelCore* core, StelPainter& sPainter, const double& angularHalfWidth,
		       Vec3d& outHeadDir, Vec3d& outHeadTangent)
{
	Q_UNUSED(core)
	if (m_segments != m_outerColorVector.size() || m_segments != m_coreColorVector.size())
	{
		qWarning() << "Meteor: color arrays have an inconsistent size!";
		return;
	}

	// Sample unit sky directions along the visible trail [m_posTrain -> m_position]
	QVector<Vec3d> unitPts(m_segments);
	for (int i = 0; i < m_segments; ++i)
	{
		const double t = static_cast<double>(i) / static_cast<double>(m_segments - 1);
		Vec3d posi = m_posTrain;
		posi[2] = m_posTrain[2] + t * (m_position[2] - m_posTrain[2]);
		Vec3d altAz = radiantToAltAz(posi);
		const double n = altAz.norm();
		unitPts[i] = (n > 1e-12) ? (altAz / n) : Vec3d(0., 0., 1.);
	}

	// Compute smooth camera-facing sideways normal S_i = normalize(unitPts[i] ^ tangent)
	QVector<Vec3d> sideVecs(m_segments);
	Vec3d lastValidSide(1., 0., 0.);
	for (int i = 0; i < m_segments; ++i)
	{
		const int iPrev = qMax(0, i - 1);
		const int iNext = qMin(m_segments - 1, i + 1);
		Vec3d tangent = unitPts[iNext] - unitPts[iPrev];
		Vec3d side = unitPts[i] ^ tangent;
		const double sn = side.norm();
		if (sn > 1e-10)
		{
			side /= sn;
			lastValidSide = side;
		}
		else
		{
			side = lastValidSide;
		}
		sideVecs[i] = side;
	}

	outHeadDir = unitPts.last();
	outHeadTangent = unitPts.last() - unitPts[qMax(0, m_segments - 2)];
	if (outHeadTangent.normSquared() < 1e-12)
		outHeadTangent = Vec3d(0., 1., 0.);
	else
		outHeadTangent.normalize();

	// Compute tapered spindle profile & flare luminance per segment
	QVector<double> halfWidthProfile(m_segments);
	QVector<float> lumProfile(m_segments);
	const double baseW = angularHalfWidth * static_cast<double>(m_widthScale);

	for (int i = 0; i < m_segments; ++i)
	{
		const float u = static_cast<float>(i) / static_cast<float>(m_segments - 1);

		// Razor-thin onset at u=0, smooth slender needle swell peaking ~u=0.78, sleek pointed tip
		const float rise = std::pow(u, 1.38f);
		const float tipTaper = std::pow(qMax(0.01f, 1.0f - 0.88f * std::pow(u, 6.5f)), 0.42f);
		float spindle = rise * tipTaper;

		float flareBoost = 0.f;
		if (m_hasTerminalFlare)
		{
			const float d = (u - m_flarePos) / 0.092f;
			flareBoost = m_flareStrength * std::exp(-d * d);
		}

		// Slight broadening if persistent ionization train is diffusing after head extinguishes
		const float afterglowRatio = (m_headExtinguished && m_hasAfterglow && m_afterglowDuration > 0.01f)
			? (1.0f - m_afterglowRemaining / m_afterglowDuration)
			: 0.f;
		const float diffuseBoost = 1.0f + 0.85f * afterglowRatio;

		halfWidthProfile[i] = baseW * static_cast<double>(qMax(0.04f, spindle * (1.0f + 0.52f * flareBoost) * diffuseBoost));

		// Smooth brightness ramp along the streak with terminal flare burst
		float lum = m_aptMag * std::pow(u, 1.42f) * (1.0f + 0.92f * flareBoost);
		// Gentle soft fade at the very tip of the tail
		if (i == 0)
			lum = 0.f;
		lumProfile[i] = qBound(0.f, lum, 1.25f);
	}

	QVector<Vec3d> ribbonVerts(2 * m_segments);
	auto drawRibbonLayer = [&](double widthMul, float alphaMul, int colorMode) {
		for (int i = 0; i < m_segments; ++i)
		{
			const double hw = halfWidthProfile[i] * widthMul;
			const Vec3d offset = sideVecs[i] * hw;
			ribbonVerts[2 * i]     = unitPts[i] - offset;
			ribbonVerts[2 * i + 1] = unitPts[i] + offset;

			Vec4f col;
			if (colorMode == 0)
			{
				// Outer saturated spectral emission halo
				col = m_outerColorVector[i];
			}
			else if (colorMode == 1)
			{
				// Mid sheath: rich saturated spectral emission hue gently warmed toward core
				const Vec4f& o = m_outerColorVector[i];
				const Vec4f& c = m_coreColorVector[i];
				col = Vec4f(o[0] * 0.82f + c[0] * 0.18f,
					    o[1] * 0.82f + c[1] * 0.18f,
					    o[2] * 0.82f + c[2] * 0.18f, 1.f);
			}
			else if (colorMode == 2)
			{
				// Incandescent white-hot core (extinguishes rapidly once head stops burning)
				col = m_coreColorVector[i];
			}
			else
			{
				// Persistent O I / Mg ionization afterglow
				const float u = static_cast<float>(i) / static_cast<float>(m_segments - 1);
				const float env = std::sin(u * M_PIf);
				col = Vec4f(m_afterglowColor[0], m_afterglowColor[1], m_afterglowColor[2],
					    qBound(0.f, env * env * alphaMul, 0.85f));
				m_trainColorVector[2 * i]     = col;
				m_trainColorVector[2 * i + 1] = col;
				continue;
			}

			const float fadeScale = (colorMode == 2) ? m_headFade : 1.0f;
			col[3] = qBound(0.f, lumProfile[i] * alphaMul * fadeScale, 1.0f);
			m_trainColorVector[2 * i]     = col;
			m_trainColorVector[2 * i + 1] = col;
		}

		sPainter.setColorPointer(4, GL_FLOAT, m_trainColorVector.constData());
		sPainter.setVertexPointer(3, GL_DOUBLE, ribbonVerts.constData());
		sPainter.drawFromArray(StelPainter::TriangleStrip, ribbonVerts.size(), 0, true);
	};

	// Additive optical blending: outer spectral glow + mid sheath + blazing white-hot core
	sPainter.setBlending(true, GL_SRC_ALPHA, GL_ONE);
	sPainter.enableClientStates(true, false, true);

	if (!m_headExtinguished || m_headFade > 0.02f)
	{
		// Pass 1: Wide soft spectral aura (emerald / amber / rose-magenta / ice-blue)
		drawRibbonLayer(2.65, 0.36f, 0);
		// Pass 2: Vibrant saturated mid spectral sheath
		drawRibbonLayer(1.32, 0.78f, 1);
		// Pass 3: Razor-fine incandescent white-hot plasma needle core
		drawRibbonLayer(0.38, 0.96f, 2);
	}

	// Pass 4: Persistent ionization afterglow for bright meteors / fireballs
	if (m_headExtinguished && m_hasAfterglow && m_afterglowRemaining > 0.f && m_afterglowDuration > 0.01f)
	{
		const float frac = m_afterglowRemaining / m_afterglowDuration;
		const float glowAlpha = m_peakAbsMag * frac * frac * 0.56f;
		if (glowAlpha > 0.01f)
		{
			drawRibbonLayer(2.25, glowAlpha, 3);
		}
	}

	sPainter.setBlending(false);
	sPainter.enableClientStates(false);
}
