/*
 * Stellarium
 * Copyright (C) 2026 Stellarium Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef TOUCHPICKER_HPP
#define TOUCHPICKER_HPP

#include "StelObject.hpp"

#include <QList>
#include <QString>

class StelCore;

//! Diagnostics for one satellite candidate. Mirrors SatelliteRenderState
//! without exposing the plugin type to callers.
struct SatellitePickDiagnostics
{
	bool displayed = false;
	bool orbitValid = false;
	bool dateRangeOk = false;
	bool timeRateOk = false;
	bool afterLaunch = false;
	bool altitudeFilterPass = true;
	bool magnitudeFilterPass = true;
	bool projectable = false;
	bool landscapeVisible = true;
	bool pointDrawn = false;
	bool labelDrawn = false;
	bool iconDrawn = false;
	bool pickable = false;
	float magSat = 99.f;
	float limitMag = 0.f;
	QString visibility;
};

struct PickCandidate
{
	StelObjectP object;
	QString name;
	QString englishName;
	QString type;
	QString objectType;
	QString id;
	bool hasMagnitude = false;
	double magnitude = 99.0;
	double screenX = 0.0;
	double screenY = 0.0;
	double distanceVp = 0.0;
	double visualRadiusVp = 0.0;
	double directScore = 0.0;
	double score = 0.0;
	double typePrior = 0.0;
	double salience = 0.0;
	bool directHit = false;
	bool labelHit = false;
	bool lineHit = false;
	int directRank = 99;
	bool satellite = false;
	SatellitePickDiagnostics satelliteRender;
};

struct PickResult
{
	bool found = false;
	bool ambiguous = false;
	bool directHit = false;
	bool labelHit = false;
	QString mode = QStringLiteral("none");
	QList<PickCandidate> candidates;
	double elapsedMs = 0.0;
	double baseRadiusVp = 0.0;
	double effectiveRadiusVp = 0.0;
	double fovDeg = 0.0;
	double degPerVp = 0.0;
	double searchRadiusDeg = 0.0;
	int starSearchCount = 0;
	int starMagnitudeFiltered = 0;
	int starRadiusFiltered = 0;
	int starDistanceFiltered = 0;
	int starCandidateCount = 0;
	float starLimit = 0.f;
	bool customStarLimit = false;
	int viewportX = 0;
	int viewportY = 0;
	int viewportWidth = 0;
	int viewportHeight = 0;
};

//! Input-specific picker geometry. The candidate/render-state/scoring model is
//! shared; touch and mouse differ only in base radius and angular cap.
struct PointerProfile
{
	bool touch = true;
	double baseRadiusVp = 66.0;
	double maxAngleDeg = 10.0;
};

struct ObjectScreenInfo
{
	bool found = false;
	bool visible = false;
	double screenX = 0.0;
	double screenY = 0.0;
	double visualRadiusVp = 0.0;
	bool hasMagnitude = false;
	double magnitude = 99.0;
	double dpr = 1.0;
	int viewportWidth = 0;
	int viewportHeight = 0;
};

//! Screen-space touch picker. It mirrors what the renderer actually draws:
//! visual footprints, labels and the current visible-sky cap. Objects expose
//! their render/pick state through StelObject::getPickState().
class TouchPicker
{
public:
	//! Pick candidates around a touch position.
	//! @param core current StelCore
	//! @param xVp touch x in viewport-independent pixels
	//! @param yVp touch y in viewport-independent pixels
	//! @param skyW sky-surface width in vp
	//! @param skyH sky-surface height in vp
	//! @return ranked candidates and pick diagnostics
	static PickResult pickAt(const StelCore* core, int xVp, int yVp, int skyW, int skyH);

	//! Pick candidates with an explicit pointer profile.
	//! @param profile touch or mouse geometry
	//! @return ranked candidates and pick diagnostics
	static PickResult pickAt(const StelCore* core, int xVp, int yVp, int skyW, int skyH,
							 const PointerProfile& profile);

	//! Build the touch profile from the user-configured base radius.
	static PointerProfile touchProfile(double baseRadiusVp);

	//! Build the mouse profile (25 device px, 2 degree angular cap).
	static PointerProfile mouseProfile(double dpr);

	//! Project one object and return its screen footprint and magnitude.
	//! @param core current StelCore
	//! @param object object to project
	//! @param skyW sky-surface width in vp
	//! @param skyH sky-surface height in vp
	//! @return screen information; found=false when projection fails
	static ObjectScreenInfo objectScreenInfo(const StelCore* core, const StelObjectP& object,
												 int skyW, int skyH);

	//! Set the touch acceptance radius; the UI exposes 48/66 vp presets.
	static void setTouchRadiusVp(double radiusVp);

	//! Return the current touch acceptance radius in vp.
	static double getTouchRadiusVp();
};

#endif // TOUCHPICKER_HPP
