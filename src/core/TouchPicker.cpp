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

#include "TouchPicker.hpp"

#include "StelApp.hpp"
#include "StelCore.hpp"
#include "StelModuleMgr.hpp"
#include "StelObjectModule.hpp"
#include "StelProjector.hpp"
#include "StelPainter.hpp"
#include "StelSkyDrawer.hpp"
#include "StelUtils.hpp"

#include "Asterism.hpp"
#include "AsterismMgr.hpp"
#include "Constellation.hpp"
#include "ConstellationMgr.hpp"
#include "Nebula.hpp"
#include "NebulaMgr.hpp"
#include "Planet.hpp"
#include "SolarSystem.hpp"
#include "StarMgr.hpp"

#include <QElapsedTimer>
#include <QFontMetrics>
#include <QGuiApplication>
#include <QRectF>
#include <QSet>

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace
{
double s_touchRadiusVp = 66.0;
constexpr double kVisualMarginVp = 3.0;
constexpr double kLabelPaddingVp = 4.0;
constexpr double kAmbiguityDelta = 0.15;
constexpr int kMaxReturnedCandidates = 5;

struct ViewContext
{
	StelProjectorP prj;
	Vec4i viewport;
	double scaleX = 1.0;
	double scaleY = 1.0;
	double dpr = 1.0;
	QPointF tapVp;
	double fov = 60.0;
	double beta = 2.0;
};

struct LabelTarget
{
	bool present = false;
	bool lineHit = false;
	bool modelHit = false;
	QRectF rect;
};

double pointSegmentDistance(const QPointF& point, const QPointF& a, const QPointF& b)
{
	const double dx = b.x() - a.x();
	const double dy = b.y() - a.y();
	const double lengthSquared = dx * dx + dy * dy;
	if (lengthSquared <= 0.0)
		return std::hypot(point.x() - a.x(), point.y() - a.y());
	double t = ((point.x() - a.x()) * dx + (point.y() - a.y()) * dy) / lengthSquared;
	t = qBound(0.0, t, 1.0);
	const double x = a.x() + t * dx;
	const double y = a.y() + t * dy;
	return std::hypot(point.x() - x, point.y() - y);
}

bool makeViewContext(const StelCore* core, int skyW, int skyH, double tapXVp, double tapYVp, ViewContext& ctx)
{
	if (!core || skyW <= 0 || skyH <= 0)
		return false;
	ctx.prj = core->getProjection(StelCore::FrameJ2000);
	if (!ctx.prj)
		return false;
	ctx.viewport = ctx.prj->getViewport();
	if (ctx.viewport[2] <= 0 || ctx.viewport[3] <= 0)
		return false;
	ctx.scaleX = static_cast<double>(ctx.viewport[2]) / static_cast<double>(skyW);
	ctx.scaleY = static_cast<double>(ctx.viewport[3]) / static_cast<double>(skyH);
	if (ctx.scaleX <= 0.0 || ctx.scaleY <= 0.0)
		return false;
	ctx.dpr = qBound(1.0, 0.5 * (ctx.scaleX + ctx.scaleY), 4.0);
	ctx.tapVp = QPointF(tapXVp, tapYVp);
	ctx.fov = ctx.prj->getFov();
	return true;
}

double betaForFov(double fov)
{
	struct Point { double fov; double beta; };
	static const Point points[] = {{2.0, 0.25}, {5.0, 0.5}, {20.0, 1.2}, {60.0, 2.0}, {90.0, 2.6}};
	if (fov <= points[0].fov)
		return points[0].beta;
	for (std::size_t i = 1; i < sizeof(points) / sizeof(points[0]); ++i)
	{
		if (fov <= points[i].fov)
		{
			const double x0 = std::log10(points[i - 1].fov);
			const double x1 = std::log10(points[i].fov);
			const double t = (std::log10(fov) - x0) / (x1 - x0);
			return points[i - 1].beta + t * (points[i].beta - points[i - 1].beta);
		}
	}
	return points[sizeof(points) / sizeof(points[0]) - 1].beta;
}

bool projectToVp(const ViewContext& ctx, const Vec3d& direction, QPointF& screenVp, Vec3d& screenDevice)
{
	Vec3d dir = direction;
	if (dir.normSquared() <= 0.0)
		return false;
	dir.normalize();
	if (!ctx.prj->projectCheck(dir, screenDevice))
		return false;
	screenVp.setX((screenDevice[0] - ctx.viewport[0]) / ctx.scaleX);
	screenVp.setY((ctx.viewport[1] + ctx.viewport[3] - 1 - screenDevice[1]) / ctx.scaleY);
	return true;
}

bool visibleSkyContains(const StelCore* core, const Vec3d& direction)
{
	Vec3d dir = direction;
	if (dir.normSquared() <= 0.0)
		return false;
	dir.normalize();
	return core->getVisibleSkyArea().contains(dir);
}

double angularRadiusToVp(const StelCore* core, const ViewContext& ctx, double angularRadiusDeg)
{
	if (!(angularRadiusDeg > 0.0))
		return 0.0;
	const double rad = angularRadiusDeg * M_PI / 180.0;
	return rad * static_cast<double>(ctx.prj->getPixelPerRadAtCenter()) / ctx.dpr;
}

double visualRadiusForObject(const StelCore* core, const ViewContext& ctx, const StelObjectP& object)
{
	const QString type = object->getType();
	if (type == QLatin1String("Star"))
	{
		RCMag rc;
		const float mag = object->getVMagnitudeWithVisualExtinction(core);
		if (!core->getSkyDrawer()->computeStarRCMag(mag, &rc) || rc.radius <= 0.f)
			return 0.0;
		return rc.radius / ctx.dpr;
	}
	if (type == QLatin1String("Planet"))
	{
		const PlanetP planet = qSharedPointerCast<Planet>(object);
		const double minRadiusVp = (planet && planet->getPlanetType() >= Planet::isAsteroid) ? 2.5 : 4.0;
		return qMax(minRadiusVp, angularRadiusToVp(core, ctx, planet->getSpheroidAngularRadius(core)));
	}
	if (type == QLatin1String("Nebula"))
	{
		// NebulaMgr draws a small hint marker (6 px, or 12 px for regions)
		// rather than a filled disk the size of the catalogue angular radius.
		// Use the marker footprint; the angular radius would let a 4-degree
		// dark nebula swallow nearby stars over a ~50 vp invisible target.
		return 3.0;
	}
	return qMax(0.0, angularRadiusToVp(core, ctx, object->getAngularRadius(core)));
}

QString objectName(const StelObjectP& object)
{
	QString name = object->getNameI18n();
	if (name.isEmpty())
		name = object->getEnglishName();
	if (name.isEmpty())
		name = object->getID();
	return name;
}

double magnitudeForObject(const StelCore* core, const StelObjectP& object, bool& hasMagnitude)
{
	const float mag = object->getVMagnitudeWithVisualExtinction(core);
	hasMagnitude = std::isfinite(mag) && mag < 90.f;
	return hasMagnitude ? static_cast<double>(mag) : 99.0;
}

double typePriorForObject(const StelObjectP& object, bool nebulaHints)
{
	const QString type = object->getType();
	if (type == QLatin1String("Planet"))
		return 1.0;
	if (type == QLatin1String("Satellite"))
		return 1.15;
	if (type == QLatin1String("Nebula"))
		return nebulaHints ? 0.4 : -0.3;
	if (type == QLatin1String("Constellation") || type == QLatin1String("Asterism"))
		return 0.6;
	if (type == QLatin1String("Star"))
		return 0.0;
	return 0.4;
}

QRectF labelRectUpRight(const QFontMetrics& fm, const QString& text, const QPointF& anchor,
						double offsetVp, double dpr)
{
	const double w = fm.horizontalAdvance(text) / dpr;
	const double h = fm.height() / dpr;
	const QRectF rect(anchor.x() + offsetVp, anchor.y() - offsetVp - h, w, h);
	return rect.adjusted(-kLabelPaddingVp, -kLabelPaddingVp, kLabelPaddingVp, kLabelPaddingVp);
}

QRectF labelRectCentered(const QFontMetrics& fm, const QString& text, const QPointF& anchor, double dpr)
{
	const double w = fm.horizontalAdvance(text) / dpr;
	const double h = fm.height() / dpr;
	const QRectF rect(anchor.x() - w / 2.0, anchor.y() - h, w, h);
	return rect.adjusted(-kLabelPaddingVp, -kLabelPaddingVp, kLabelPaddingVp, kLabelPaddingVp);
}

void addCandidate(QList<PickCandidate>& candidates, const ViewContext& ctx, const StelCore* core,
				  const StelObjectP& object, const QPointF& screenVp, double visualRadiusVp,
				  double magnitude, bool hasMagnitude, double typePrior,
				  const LabelTarget& label, bool satellite,
				  const SatellitePickDiagnostics& satelliteRender)
{
	if (!object)
		return;
	if (!label.modelHit && !visibleSkyContains(core, object->getJ2000EquatorialPos(core)))
		return;

	PickCandidate candidate;
	candidate.object = object;
	candidate.name = objectName(object);
	candidate.englishName = object->getEnglishName();
	candidate.type = object->getType();
	candidate.objectType = object->getObjectTypeI18n();
	candidate.id = object->getID();
	candidate.hasMagnitude = hasMagnitude;
	candidate.magnitude = magnitude;
	candidate.screenX = screenVp.x();
	candidate.screenY = screenVp.y();
	candidate.distanceVp = std::hypot(screenVp.x() - ctx.tapVp.x(), screenVp.y() - ctx.tapVp.y());
	candidate.visualRadiusVp = qMax(0.0, visualRadiusVp);
	candidate.typePrior = typePrior;
	candidate.salience = hasMagnitude ? qBound(0.0, (6.5 - magnitude) / 8.0, 1.0) : 0.0;
	const bool pointSource = candidate.type == QLatin1String("Star")
		|| candidate.type == QLatin1String("Planet") || satellite;
	const double magnitudeTerm = (pointSource && hasMagnitude)
		? (0.5 * ctx.beta) * candidate.magnitude : 0.0;
	candidate.directScore = candidate.distanceVp + magnitudeTerm;
	const bool labelTextHit = label.present && label.rect.contains(ctx.tapVp);
	const bool footprintHit = candidate.visualRadiusVp > 0.0
		&& candidate.distanceVp <= candidate.visualRadiusVp + kVisualMarginVp;
	const bool isConstellation = candidate.type == QLatin1String("Constellation")
		|| candidate.type == QLatin1String("Asterism");
	candidate.lineHit = label.lineHit;
	candidate.modelHit = label.modelHit;
	candidate.labelHit = label.lineHit || labelTextHit;
	candidate.directHit = candidate.labelHit || footprintHit || label.modelHit;
	if (footprintHit)
		candidate.directRank = 0;
	else if (labelTextHit)
		candidate.directRank = isConstellation ? 2 : 1;
	else if (label.lineHit)
		candidate.directRank = 3;
	else if (label.modelHit)
		candidate.directRank = 4;
	candidate.satellite = satellite;
	candidate.satelliteRender = satelliteRender;

	const double dEff = qMax(0.0, candidate.distanceVp - candidate.visualRadiusVp);
	const double sigma = qBound(12.0, 12.0 + 0.5 * candidate.visualRadiusVp, 32.0);
	const double gate = qBound(0.0, 1.0 - dEff / (candidate.visualRadiusVp + 20.0), 1.0);
	const double typeGate = qBound(0.0, 1.0 - dEff / 32.0, 1.0);
	candidate.score = dEff * dEff / (2.0 * sigma * sigma)
		- ctx.beta * candidate.salience * gate
		- candidate.typePrior * typeGate;

	candidates.append(candidate);
}

bool differs(double a, double b)
{
	return std::abs(a - b) > 1e-9;
}

int candidateTier(const PickCandidate& c)
{
	if (c.directHit && c.directRank <= 2)
		return c.directRank;
	if (c.nearObjectPriority)
		return 3;
	if (c.directHit)
		return c.directRank + 1; // lineHit (3) -> 4, modelHit (4) -> 5
	return 6;
}

bool candidateLess(const PickCandidate& a, const PickCandidate& b)
{
	const int tierA = candidateTier(a);
	const int tierB = candidateTier(b);
	if (tierA != tierB)
		return tierA < tierB;
	if (tierA == 0)
	{
		// Footprint hits use a PC-style distance + k(FOV)*magnitude score.
		if (differs(a.directScore, b.directScore))
			return a.directScore < b.directScore;
		if (differs(a.typePrior, b.typePrior))
			return a.typePrior > b.typePrior;
		if (differs(a.salience, b.salience))
			return a.salience > b.salience;
		if (differs(a.distanceVp, b.distanceVp))
			return a.distanceVp < b.distanceVp;
	}
	else if (tierA == 5)
	{
		// Overlapping 3D/2D constellation artwork hits: prefer the visually
		// brighter (front-most depth-sliced) model before anchor distance.
		if (std::abs(a.salience - b.salience) > 0.05)
			return a.salience > b.salience;
		if (differs(a.distanceVp, b.distanceVp))
			return a.distanceVp < b.distanceVp;
		if (differs(a.typePrior, b.typePrior))
			return a.typePrior > b.typePrior;
	}
	else if (tierA == 1 || tierA == 2 || tierA == 4)
	{
		// Label and line hits compare anchor distance.
		if (differs(a.distanceVp, b.distanceVp))
			return a.distanceVp < b.distanceVp;
		if (differs(a.typePrior, b.typePrior))
			return a.typePrior > b.typePrior;
		if (differs(a.salience, b.salience))
			return a.salience > b.salience;
	}
	else
	{
		if (differs(a.score, b.score))
			return a.score < b.score;
		if (differs(a.typePrior, b.typePrior))
			return a.typePrior > b.typePrior;
		if (differs(a.salience, b.salience))
			return a.salience > b.salience;
		if (differs(a.distanceVp, b.distanceVp))
			return a.distanceVp < b.distanceVp;
	}
	return a.type != b.type ? a.type < b.type : a.id < b.id;
}
} // namespace

PickResult TouchPicker::pickAt(const StelCore* core, int xVp, int yVp, int skyW, int skyH)
{
	return pickAt(core, xVp, yVp, skyW, skyH, touchProfile(s_touchRadiusVp));
}

PickResult TouchPicker::pickAt(const StelCore* core, int xVp, int yVp, int skyW, int skyH,
							   const PointerProfile& profile)
{
	QElapsedTimer timer;
	timer.start();

	PickResult result;
	ViewContext ctx;
	if (!makeViewContext(core, skyW, skyH, xVp, yVp, ctx))
		return result;

	result.viewportX = ctx.viewport[0];
	result.viewportY = ctx.viewport[1];
	result.viewportWidth = ctx.viewport[2];
	result.viewportHeight = ctx.viewport[3];

	const int tapXDev = ctx.viewport[0] + qRound(xVp * ctx.scaleX);
	const int tapYDev = ctx.viewport[1] + ctx.viewport[3] - 1 - qRound(yVp * ctx.scaleY);
	Vec3d tapDirection;
	if (!ctx.prj->unProject(tapXDev, tapYDev, tapDirection))
		return result;
	tapDirection.normalize();

	result.baseRadiusVp = profile.baseRadiusVp;
	// FOV is the projected diameter, so convert it against the smaller
	// viewport dimension. Keeping this in vp avoids mixing DPR-scaled pixels
	// with the vp coordinates used by the caller.
	const double minViewportVp = static_cast<double>(qMin(skyW, skyH));
	const double degPerVp = ctx.fov / minViewportVp;
	const double cappedRadiusVp = (profile.maxAngleDeg > 0.0 && degPerVp > 0.0)
		? profile.maxAngleDeg / degPerVp : profile.baseRadiusVp;
	// Tighten touch hit tolerance smoothly at wide FOV (>80 deg) so tapping empty
	// sky in a wide-angle dome doesn't accidentally grab distant stars or DSOs.
	const double wideFovRadiusVp = (ctx.fov > 80.0 && profile.baseRadiusVp >= 36.0)
		? qMax(24.0, profile.baseRadiusVp * (80.0 / ctx.fov))
		: profile.baseRadiusVp;
	const double effectiveRadiusVp = qMax(1.0, qMin(wideFovRadiusVp, cappedRadiusVp));
	result.effectiveRadiusVp = effectiveRadiusVp;
	result.fovDeg = ctx.fov;
	result.degPerVp = degPerVp;

	// Effective radius plus a small label margin. The angular cap keeps a
	// 66 vp touch target from covering 14 degrees at FOV 80 on a small phone;
	// mouse uses a much smaller base/profile.
	const double fovRadiusDeg = degPerVp * (effectiveRadiusVp + 12.0);
	if (!(fovRadiusDeg > 0.0))
		return result;
	result.searchRadiusDeg = fovRadiusDeg;
	ctx.fov = ctx.prj->getFov();
	ctx.beta = betaForFov(ctx.fov);

	QFont labelFont = QGuiApplication::font();
	labelFont.setPixelSize(StelApp::getInstance().getScreenFontSize());
	const QFontMetrics labelMetrics(labelFont);

	QList<PickCandidate> candidates;

	// --- Stars -----------------------------------------------------------
	if (StarMgr* starMgr = GETSTELMODULE(StarMgr))
	{
		if (starMgr->getFlagStars())
		{
			const bool starLabels = starMgr->getFlagLabels();
			const StelSkyDrawer* drawer = core->getSkyDrawer();
			const float drawerStarLimit = drawer->getStarLimitMagnitude();
			result.customStarLimit = drawer->getFlagStarMagnitudeLimit();
			const float starLimit = result.customStarLimit
				? qMin(static_cast<float>(drawer->getCustomStarMagnitudeLimit()), drawerStarLimit)
				: drawerStarLimit;
			result.starLimit = starLimit;
			// Pass the visible star magnitude cutoff into StarMgr so deep Gaia catalogs
			// (stars_3..stars_8) prune invisible stars before 6D projection & heap wrapping.
			// Extinction only dims stars, so catalog mag <= starLimit + 0.05 is strictly safe.
			const QList<StelObjectP> stars = starMgr->searchAround(tapDirection, fovRadiusDeg, core, starLimit + 0.05f);
			result.starSearchCount = stars.size();
			const double wideFovStarPenalty = (ctx.fov > 80.0)
				? qMin(1.6, 3.0 * std::log10(ctx.fov / 80.0))
				: 0.0;
			const double labelLimitMag = (drawerStarLimit - 6.5) * 0.7
				+ starMgr->getLabelsAmount() * 1.2 - 2.0 - wideFovStarPenalty;
			const float clearSkyScale = core->getFlagClearSky() ? 1.0f : 0.6f;
			const float minPickLuminance = core->isBrightDaylight() ? 0.30f : 0.18f;

			for (const StelObjectP& star : std::as_const(stars))
			{
				const float mag = star->getVMagnitudeWithVisualExtinction(core);
				// StarMgr::draw() / ZoneArray::draw() cull stars beyond the combined
				// star magnitude limit and render using computeStarRCMag() so daytime
				// visible stars (when realistic star visibility is off) stay in sync.
				if (mag > starLimit)
				{
					++result.starMagnitudeFiltered;
					continue;
				}
				RCMag rc;
				if (!drawer->computeStarRCMag(mag, &rc) || rc.radius <= 0.f)
				{
					++result.starRadiusFiltered;
					continue;
				}
				const float effectiveLum = rc.luminance * clearSkyScale;
				const double rVp = (rc.radius * clearSkyScale) / ctx.dpr;

				QPointF screenVp;
				Vec3d screenDevice;
				if (!projectToVp(ctx, star->getJ2000EquatorialPos(core), screenVp, screenDevice))
				{
					++result.starDistanceFiltered;
					continue;
				}

				LabelTarget label;
				if (starLabels && core->getFlagClearSky() && mag < labelLimitMag
					&& StelPainter::skyLabelVisibility(QStringLiteral("stars"), star->getID()) > 0.05f)
				{
					const QString text = objectName(star);
					if (!text.isEmpty())
					{
						label.present = true;
						label.rect = labelRectUpRight(labelMetrics, text, screenVp,
							(rc.radius * clearSkyScale * 0.7) / ctx.dpr, ctx.dpr);
					}
				}
				const bool labelHit = label.present && label.rect.contains(ctx.tapVp);

				// Reject sub-threshold barely-perceptible star specks that are not
				// visibly standing out on screen so tapping empty sky cancels selection
				// instead of grabbing an invisible background star.
				if (!labelHit && effectiveLum < minPickLuminance)
				{
					++result.starRadiusFiltered;
					continue;
				}

				const double starDistanceVp = std::hypot(screenVp.x() - ctx.tapVp.x(),
					screenVp.y() - ctx.tapVp.y());
				double starAcceptVp = effectiveRadiusVp;
				if (profile.touch)
				{
					if (mag <= 2.5f || rVp >= 2.2)
						starAcceptVp = qMin(effectiveRadiusVp, 34.0);
					else if (effectiveLum >= 0.65f || mag <= 4.2f)
						starAcceptVp = qMin(effectiveRadiusVp, 24.0);
					else
						starAcceptVp = qMin(effectiveRadiusVp, 14.0);
				}
				if (!labelHit && starDistanceVp > starAcceptVp + rVp)
				{
					++result.starDistanceFiltered;
					continue;
				}

				bool hasMagnitude = false;
				const double magnitude = magnitudeForObject(core, star, hasMagnitude);
				++result.starCandidateCount;
				addCandidate(candidates, ctx, core, star, screenVp, rVp, magnitude, hasMagnitude,
					typePriorForObject(star, false), label, false, SatellitePickDiagnostics());
			}
		}
	}

	// --- Planets / Sun / Moon -------------------------------------------
	if (SolarSystem* solarSystem = GETSTELMODULE(SolarSystem))
	{
		if (solarSystem->getFlagPlanets())
		{
			const QList<StelObjectP> planets = solarSystem->searchAround(tapDirection, fovRadiusDeg, core);
			for (const StelObjectP& planet : planets)
			{
				// Planet::draw() culls hidden objects, dim minor bodies, and planets
				// without any visible disc, halo, label or marker. Keep picker in sync.
				if (!planet->getPickState(core).pickable)
					continue;
				QPointF screenVp;
				Vec3d screenDevice;
				if (!projectToVp(ctx, planet->getJ2000EquatorialPos(core), screenVp, screenDevice))
					continue;
				const double rVp = visualRadiusForObject(core, ctx, planet);
				LabelTarget label;
				if (solarSystem->getFlagLabels()
					&& StelPainter::skyLabelVisibility(QStringLiteral("planet:") + planet->getID(), planet->getID()) > 0.05f)
				{
					const QString text = objectName(planet);
					if (!text.isEmpty())
					{
						label.present = true;
						label.rect = labelRectUpRight(labelMetrics, text, screenVp, qMax(7.0, rVp * 0.7), ctx.dpr);
					}
				}
				const bool labelHit = label.present && label.rect.contains(ctx.tapVp);
				const double planetDistVp = std::hypot(screenVp.x() - ctx.tapVp.x(),
					screenVp.y() - ctx.tapVp.y());
				const PlanetP planetObj = qSharedPointerCast<Planet>(planet);
				const bool minorBody = planetObj && planetObj->getPlanetType() >= Planet::isAsteroid;
				const double planetAcceptVp = profile.touch
					? qMin(effectiveRadiusVp, minorBody ? 22.0 : 38.0)
					: effectiveRadiusVp;
				if (!labelHit && planetDistVp > planetAcceptVp + rVp)
					continue;

				bool hasMagnitude = false;
				const double magnitude = magnitudeForObject(core, planet, hasMagnitude);
				addCandidate(candidates, ctx, core, planet, screenVp, rVp, magnitude, hasMagnitude,
					typePriorForObject(planet, false), label, false, SatellitePickDiagnostics());
			}
		}
	}

	// --- Deep-sky objects ------------------------------------------------
	if (NebulaMgr* nebulaMgr = GETSTELMODULE(NebulaMgr))
	{
		// NebulaMgr::draw() renders the whole DSO layer only with clear sky and
		// the hints fader. Faint objects beyond maxMagHints are not drawn unless
		// the renderer actually paints a hint, label or outline.
		const bool nebulaHints = nebulaMgr->getFlagHints();
		if (nebulaMgr->getFlagShow() && nebulaHints && core->getFlagClearSky())
		{
			const float maxMagHints = nebulaMgr->computeMaxMagHint(core->getSkyDrawer());
			const float wideFovLabelPenalty = (ctx.fov > 75.0)
				? static_cast<float>(qMin(2.4, 5.0 * std::log10(ctx.fov / 75.0)))
				: 0.f;
			const float maxMagLabels = core->getSkyDrawer()->getSkyObjectLimitMagnitude() - 2.f
				+ static_cast<float>(nebulaMgr->getLabelsAmount() * 1.2) - 2.f - wideFovLabelPenalty;
			const QList<StelObjectP> nebulae = nebulaMgr->searchAround(tapDirection, fovRadiusDeg, core);
			for (const StelObjectP& nebula : nebulae)
			{
				const NebulaP nebulaObject = qSharedPointerCast<Nebula>(nebula);
				Nebula::RenderState render = nebulaObject->getRenderState(maxMagHints, maxMagLabels);
				const auto drawn = nebulaObject->getDrawVisibility();
				render.hintDrawn = render.hintDrawn && drawn.hintAlpha > 0.05f;
				render.labelDrawn = render.labelDrawn && drawn.labelAlpha > 0.05f;
				render.outlineDrawn = render.outlineDrawn && drawn.outlineAlpha > 0.05f;
				render.pickable = render.hintDrawn || render.labelDrawn || render.outlineDrawn;
				if (!render.pickable)
					continue;

				QPointF screenVp;
				Vec3d screenDevice;
				if (!projectToVp(ctx, nebula->getJ2000EquatorialPos(core), screenVp, screenDevice))
					continue;
				const double rVp = render.outlineDrawn
					? angularRadiusToVp(core, ctx, nebula->getAngularRadius(core))
					: 3.0;

				LabelTarget label;
				if (render.labelDrawn)
				{
					const QString text = objectName(nebula);
					if (!text.isEmpty())
					{
						label.present = true;
						label.rect = labelRectUpRight(labelMetrics, text, screenVp, 15.0 / ctx.dpr, ctx.dpr);
					}
				}
				const bool labelHit = label.present && label.rect.contains(ctx.tapVp);
				const double dsoDistVp = std::hypot(screenVp.x() - ctx.tapVp.x(),
					screenVp.y() - ctx.tapVp.y());
				const double dsoAcceptVp = profile.touch
					? qMin(effectiveRadiusVp, 28.0)
					: effectiveRadiusVp;
				if (!labelHit && dsoDistVp > dsoAcceptVp + rVp)
					continue;

				bool hasMagnitude = false;
				const double magnitude = magnitudeForObject(core, nebula, hasMagnitude);
				addCandidate(candidates, ctx, core, nebula, screenVp, rVp, magnitude, hasMagnitude,
					typePriorForObject(nebula, nebulaHints), label, false, SatellitePickDiagnostics());
			}
		}
	}

	// --- Constellations (labels, visible lines, and 3D/2D artwork) -------
	if (ConstellationMgr* constellationMgr = GETSTELMODULE(ConstellationMgr))
	{
		const bool constellationLabels = constellationMgr->getFlagLabels();
		const bool constellationLines = constellationMgr->getFlagLines();
		const bool constellationArt = constellationMgr->getFlagArt();
		const bool constellationModels = constellationArt && constellationMgr->getFlagArt3d();
		const Vec3d velocity = core->getUseAberration() ? core->getAberrationVec(core->getJDE()) : Vec3d(0.);
		if (constellationLabels || constellationLines || constellationModels)
		{
			const double modelTolDev = (profile.touch ? 13. : 4.) * qMax(ctx.scaleX, ctx.scaleY);
			const QStringList names = constellationMgr->getConstellationsEnglishNames();
			for (const QString& name : names)
			{
				const StelObjectP object = constellationMgr->searchByName(name);
				if (!object)
					continue;
				const Constellation* constellation = dynamic_cast<const Constellation*>(object.data());
				if (!constellation)
					continue;

				QPointF screenVp;
				Vec3d screenDevice;
				const bool anchorVisible = projectToVp(ctx, constellation->getJ2000EquatorialPos(core), screenVp, screenDevice);
				bool anchorProjected = anchorVisible;
				if (!anchorVisible)
				{
					anchorProjected = ctx.prj->project(constellation->getJ2000EquatorialPos(core), screenDevice);
					if (anchorProjected)
						screenVp = QPointF((screenDevice[0] - ctx.viewport[0]) / ctx.scaleX,
							(ctx.viewport[1] + ctx.viewport[3] - 1 - screenDevice[1]) / ctx.scaleY);
				}

				LabelTarget label;
				if (constellationLabels)
				{
					const QString text = constellation->getScreenLabel();
					if (!text.isEmpty())
					{
						for (int anchorIndex = 0; anchorIndex < constellation->getLabelPositions().size(); ++anchorIndex)
						{
							if (StelPainter::skyLabelVisibility(QStringLiteral("constellations"),
								constellation->getLabelLayoutId(anchorIndex)) <= 0.05f)
								continue;
							Vec3d direction = constellation->getLabelPositions().at(anchorIndex);
							direction.normalize();
							direction += velocity;
							direction.normalize();
							QPointF labelVp;
							Vec3d labelDevice;
							if (!projectToVp(ctx, direction, labelVp, labelDevice))
								continue;
							const QRectF rect = labelRectCentered(labelMetrics, text, labelVp, ctx.dpr);
							if (rect.contains(ctx.tapVp))
							{
								label.present = true;
								label.rect = rect;
								screenVp = labelVp;
								anchorProjected = true;
								break;
							}
						}
					}
				}

				bool lineHit = false;
				const bool lineDrawn = constellationLines
					&& constellation->getLinePresentation() > 0.05f
					&& constellation->getLineAnimProgress() > 0.05f;
				const SphericalRegionP region = constellation->getRegion();
				if (lineDrawn && region && region->contains(tapDirection))
				{
					const std::vector<StelObjectP>& lines = constellation->isDarkConstellation()
						? constellation->getDarkConstellationLines()
						: constellation->getConstellationLines();
					for (std::size_t i = 0; i + 1 < lines.size(); i += 2)
					{
						QPointF a;
						QPointF b;
						Vec3d deviceA;
						Vec3d deviceB;
						if (!projectToVp(ctx, lines[i]->getJ2000EquatorialPos(core), a, deviceA)
							|| !projectToVp(ctx, lines[i + 1]->getJ2000EquatorialPos(core), b, deviceB))
							continue;
						if (pointSegmentDistance(ctx.tapVp, a, b) <= 6.0)
						{
							lineHit = true;
							break;
						}
					}
				}
				if (constellationModels && visibleSkyContains(core, tapDirection))
				{
					if (constellation->hasArtModel())
					{
						label.modelHit = constellation->modelContainsPoint(ctx.prj, velocity,
							Vec3d(tapXDev, tapYDev, 0.), modelTolDev);
					}
					else
					{
						label.modelHit = constellation->artPolygonContainsPoint(ctx.prj, velocity,
							Vec3d(tapXDev, tapYDev, 0.), modelTolDev * 0.5);
					}
				}
				if (!label.present && !lineHit && !label.modelHit)
					continue;
				if (!anchorProjected)
					screenVp = ctx.tapVp;
				label.lineHit = lineHit;
				addCandidate(candidates, ctx, core, object, screenVp, 0.0, 99.0, false,
					typePriorForObject(object, false), label, false, SatellitePickDiagnostics());
				if (label.modelHit && !candidates.isEmpty())
				{
					candidates.last().salience = constellation->hasArtModel()
						? static_cast<double>(constellation->getModelIntensity())
						: 0.25;
				}
			}
		}
	}

	// --- Asterisms / sky-culture star groups ----------------------------
	// AsterismMgr is separate from ConstellationMgr. Chinese sky cultures in
	// particular draw their star groups here, so they need the same explicit
	// label/line hit model as IAU constellations.
	if (AsterismMgr* asterismMgr = GETSTELMODULE(AsterismMgr))
	{
		const bool asterismLabels = asterismMgr->getFlagLabels();
		const bool asterismLines = asterismMgr->getFlagLines();
		if (asterismLabels || asterismLines)
		{
			const QVector<QPair<QString, StelObjectP>> objects = asterismMgr->listAllObjects(true);
			for (const auto& entry : objects)
			{
				const StelObjectP object = entry.second;
				const Asterism* asterism = dynamic_cast<const Asterism*>(object.data());
				if (!asterism)
					continue;

				QPointF screenVp;
				Vec3d screenDevice;
				if (!projectToVp(ctx, object->getJ2000EquatorialPos(core), screenVp, screenDevice))
					continue;

				LabelTarget label;
				const bool labelsDrawn = asterismLabels && asterism->isLabelDrawn()
					&& !(asterism->isTelescopic() && ctx.fov > 60.f);
				if (labelsDrawn)
				{
					const QString text = object->getScreenLabel();
					if (!text.isEmpty())
					{
						// Asterism names may have several label anchors. Accept
						// a hit on any of the anchors used by drawNames().
						for (const Vec3d& namePoint : std::as_const(asterism->getLabelAnchors()))
						{
							QPointF labelVp;
							Vec3d labelDevice;
							if (!projectToVp(ctx, namePoint, labelVp, labelDevice))
								continue;
							const QRectF rect = labelRectCentered(labelMetrics, text, labelVp, ctx.dpr);
							if (rect.contains(ctx.tapVp))
							{
								label.present = true;
								label.rect = rect;
								screenVp = labelVp;
								break;
							}
						}
					}
				}

				bool lineHit = false;
				if (asterismLines && asterism->isLinesDrawn())
				{
					const std::vector<StelObjectP>& lines = asterism->getLineSegments();
					for (std::size_t i = 0; i + 1 < lines.size(); i += 2)
					{
						QPointF a;
						QPointF b;
						Vec3d deviceA;
						Vec3d deviceB;
						if (!projectToVp(ctx, lines[i]->getJ2000EquatorialPos(core), a, deviceA)
							|| !projectToVp(ctx, lines[i + 1]->getJ2000EquatorialPos(core), b, deviceB))
							continue;
						if (pointSegmentDistance(ctx.tapVp, a, b) <= 6.0)
						{
							lineHit = true;
							break;
						}
					}
				}
				if (!label.present && !lineHit)
					continue;
				label.lineHit = lineHit;
				addCandidate(candidates, ctx, core, object, screenVp, 0.0, 99.0, false,
					typePriorForObject(object, false), label, false, SatellitePickDiagnostics());
			}
		}
	}

	// --- Satellites (generic object-module render state) ----------------
	if (StelModule* module = StelApp::getInstance().getModuleMgr().getModule(QStringLiteral("Satellites"), true))
	{
		if (StelObjectModule* objectModule = dynamic_cast<StelObjectModule*>(module))
		{
			const double satSearchDeg = qMax(fovRadiusDeg * 1.4, 0.12);
			const QList<StelObjectP> objects = objectModule->searchAround(tapDirection, satSearchDeg, core);
			for (const StelObjectP& object : objects)
			{
				const StelObjectPickState state = object->getPickState(core);
				if (!state.pickable)
					continue;

				QPointF screenVp;
				Vec3d screenDevice;
				if (!projectToVp(ctx, object->getJ2000EquatorialPos(core), screenVp, screenDevice))
					continue;

				double rVp = 0.0;
				if (state.iconDrawn)
					rVp = qMax(14.0 / ctx.dpr, 8.5);
				else if (state.pointDrawn && state.hasMagnitude)
				{
					RCMag rc;
					if (core->getSkyDrawer()->computeRCMag(state.magnitude, &rc) && rc.radius > 0.f)
						rVp = qMax(static_cast<double>(rc.radius / ctx.dpr), 5.0);
				}

				LabelTarget label;
				if (state.labelDrawn
					&& StelPainter::skyLabelVisibility(QStringLiteral("satellites"), object->getID()) > 0.05f)
				{
					const QString text = objectName(object);
					if (!text.isEmpty())
					{
						label.present = true;
						label.rect = labelRectUpRight(labelMetrics, text, screenVp, 10.0 / ctx.dpr, ctx.dpr);
					}
				}
				const bool labelHit = label.present && label.rect.contains(ctx.tapVp);
				const double satDistVp = std::hypot(screenVp.x() - ctx.tapVp.x(),
					screenVp.y() - ctx.tapVp.y());
				const double satAcceptVp = profile.touch
					? qMin(effectiveRadiusVp, 40.0)
					: effectiveRadiusVp;
				if (!labelHit && satDistVp > satAcceptVp + rVp)
					continue;

				SatellitePickDiagnostics diagnostics;
				diagnostics.landscapeVisible = state.landscapeVisible;
				diagnostics.pointDrawn = state.pointDrawn;
				diagnostics.labelDrawn = state.labelDrawn;
				diagnostics.iconDrawn = state.iconDrawn;
				diagnostics.pickable = state.pickable;
				diagnostics.magSat = state.magnitude;
				diagnostics.limitMag = core->getSkyDrawer()->getLimitMagnitude();
				diagnostics.visibility = QStringLiteral("UNKNOWN");

				// When a satellite renders an explicit visual micro-marker/icon on screen,
				// do not penalize its touch-pick score with an eclipsed mag=17 value so faint
				// background stars cannot steal taps directly on the satellite marker.
				const double pickMag = (state.iconDrawn && state.hasMagnitude && state.magnitude > 3.5)
					? 3.5
					: state.magnitude;

				addCandidate(candidates, ctx, core, object, screenVp, rVp, pickMag,
					state.hasMagnitude, typePriorForObject(object, false), label, true, diagnostics);
			}
		}
	}

	// Promote nearby bright/constellation-vertex stars, planets, satellites and
	// close DSOs above passive constellation line/3D-model area hits so tapping
	// a star sitting on a constellation stick-figure selects the star reliably,
	// while tapping the open body of a 3D constellation model still selects the
	// whole constellation instead of getting stolen by faint background stars.
	QSet<QString> constellationVertexStarIds;
	bool hasConstellationModelHit = false;
	for (const PickCandidate& candidate : std::as_const(candidates))
	{
		if (candidate.type == QLatin1String("Constellation") && (candidate.lineHit || candidate.modelHit))
		{
			if (candidate.modelHit)
				hasConstellationModelHit = true;
			if (const Constellation* constellation = dynamic_cast<const Constellation*>(candidate.object.data()))
			{
				const std::vector<StelObjectP>& lines = constellation->isDarkConstellation()
					? constellation->getDarkConstellationLines()
					: constellation->getConstellationLines();
				for (const StelObjectP& endpoint : lines)
				{
					if (endpoint)
						constellationVertexStarIds.insert(endpoint->getID());
				}
			}
		}
	}
	for (PickCandidate& candidate : candidates)
	{
		if (candidate.directHit)
			continue;
		if (candidate.type == QLatin1String("Constellation") || candidate.type == QLatin1String("Asterism"))
			continue;
		const double dEff = qMax(0.0, candidate.distanceVp - candidate.visualRadiusVp);
		double priorityRadiusVp = profile.touch ? 18.0 : 8.0;
		if (candidate.type == QLatin1String("Planet"))
		{
			// Visible planets/Moon/Sun keep priority; faint minor bodies
			// (asteroids/comets fainter than mag 6.5) must not steal taps from
			// an explicit 3D constellation model hit.
			const bool faintMinorBody = candidate.hasMagnitude && candidate.magnitude > 6.5 && candidate.visualRadiusVp <= 4.5;
			if (faintMinorBody && hasConstellationModelHit)
				priorityRadiusVp = -1.0;
			else if (faintMinorBody)
				priorityRadiusVp = profile.touch ? 8.0 : 4.0;
		}
		else if (candidate.type == QLatin1String("Satellite"))
		{
			priorityRadiusVp = profile.touch ? 22.0 : 10.0;
		}
		else if (candidate.type == QLatin1String("Nebula"))
		{
			priorityRadiusVp = profile.touch ? 12.0 : 6.0;
		}
		else if (candidate.type == QLatin1String("Star"))
		{
			const bool isVertexOrBright = constellationVertexStarIds.contains(candidate.id)
				|| (candidate.hasMagnitude && candidate.magnitude <= 3.5)
				|| candidate.visualRadiusVp >= 1.8;
			const bool isMedium = candidate.hasMagnitude && candidate.magnitude <= 4.5;
			if (isVertexOrBright)
				priorityRadiusVp = profile.touch ? 22.0 : 7.0;
			else if (isMedium)
				priorityRadiusVp = profile.touch ? 9.0 : 4.0;
			else if (hasConstellationModelHit)
				priorityRadiusVp = -1.0; // Never let faint field stars steal 3D model taps
			else
				priorityRadiusVp = profile.touch ? 10.0 : 5.0;
		}
		if (priorityRadiusVp >= 0.0 && dEff <= priorityRadiusVp && candidate.distanceVp <= effectiveRadiusVp + candidate.visualRadiusVp)
			candidate.nearObjectPriority = true;
	}

	std::sort(candidates.begin(), candidates.end(), candidateLess);
	result.candidates = candidates.mid(0, kMaxReturnedCandidates);
	if (!result.candidates.isEmpty())
	{
		const PickCandidate& best = result.candidates.first();
		const bool withinTouch = best.distanceVp <= effectiveRadiusVp + best.visualRadiusVp;
		const double emptyScore = (effectiveRadiusVp * effectiveRadiusVp) / (2.0 * 12.0 * 12.0);
		result.found = best.directHit || (withinTouch && best.score <= emptyScore);
		result.directHit = best.directHit;
		result.labelHit = best.labelHit;
		result.mode = best.labelHit ? QStringLiteral("label")
			: best.directHit ? QStringLiteral("direct")
			: result.found ? QStringLiteral("near") : QStringLiteral("none");
		if (!result.found)
			result.mode = QStringLiteral("none");

		if (result.candidates.size() > 1)
		{
			const PickCandidate& second = result.candidates.at(1);
			result.ambiguous = !best.labelHit && !second.labelHit
				&& std::abs(best.score - second.score) < kAmbiguityDelta;
		}
	}

	result.elapsedMs = timer.nsecsElapsed() / 1000000.0;
	return result;
}

void TouchPicker::setTouchRadiusVp(double radiusVp)
{
	s_touchRadiusVp = qBound(24.0, radiusVp, 96.0);
}

double TouchPicker::getTouchRadiusVp()
{
	return s_touchRadiusVp;
}

PointerProfile TouchPicker::touchProfile(double baseRadiusVp)
{
	PointerProfile profile;
	profile.touch = true;
	profile.baseRadiusVp = qBound(24.0, baseRadiusVp, 96.0);
	profile.maxAngleDeg = 10.0;
	return profile;
}

PointerProfile TouchPicker::mouseProfile(double dpr)
{
	PointerProfile profile;
	profile.touch = false;
	profile.baseRadiusVp = qMax(1.0, 25.0 / qBound(1.0, dpr, 4.0));
	profile.maxAngleDeg = 2.0;
	return profile;
}

ObjectScreenInfo TouchPicker::objectScreenInfo(const StelCore* core, const StelObjectP& object,
													   int skyW, int skyH)
{
	ObjectScreenInfo info;
	if (!core || !object)
		return info;

	ViewContext ctx;
	if (skyW <= 0 || skyH <= 0)
	{
		const double dpr = QGuiApplication::primaryScreen()
			? QGuiApplication::primaryScreen()->devicePixelRatio() : 1.0;
		const int vpW = core->getProjection(StelCore::FrameJ2000)->getViewportWidth();
		const int vpH = core->getProjection(StelCore::FrameJ2000)->getViewportHeight();
		skyW = qMax(1, qRound(vpW / dpr));
		skyH = qMax(1, qRound(vpH / dpr));
	}
	if (!makeViewContext(core, skyW, skyH, 0.0, 0.0, ctx))
		return info;

	QPointF screenVp;
	Vec3d screenDevice;
	const Vec3d direction = object->getJ2000EquatorialPos(core);
	if (!projectToVp(ctx, direction, screenVp, screenDevice))
		return info;

	info.found = true;
	info.visible = visibleSkyContains(core, direction);
	info.screenX = screenVp.x();
	info.screenY = screenVp.y();
	info.visualRadiusVp = visualRadiusForObject(core, ctx, object);
	info.magnitude = magnitudeForObject(core, object, info.hasMagnitude);
	info.dpr = ctx.dpr;
	info.viewportWidth = ctx.viewport[2];
	info.viewportHeight = ctx.viewport[3];
	return info;
}
