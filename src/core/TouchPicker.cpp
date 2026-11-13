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
		const float mag = object->getVMagnitudeWithExtinction(core);
		if (!core->getSkyDrawer()->computeRCMag(mag, &rc) || rc.radius <= 0.f)
			return 0.0;
		return rc.radius / ctx.dpr;
	}
	if (type == QLatin1String("Planet"))
	{
		const PlanetP planet = qSharedPointerCast<Planet>(object);
		return qMax(4.0, angularRadiusToVp(core, ctx, planet->getSpheroidAngularRadius(core)));
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
	const float mag = object->getVMagnitudeWithExtinction(core);
	hasMagnitude = std::isfinite(mag) && mag < 90.f;
	return hasMagnitude ? static_cast<double>(mag) : 99.0;
}

double typePriorForObject(const StelObjectP& object, bool nebulaHints)
{
	const QString type = object->getType();
	if (type == QLatin1String("Planet"))
		return 1.0;
	if (type == QLatin1String("Satellite"))
		return 0.7;
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
	if (!visibleSkyContains(core, object->getJ2000EquatorialPos(core)))
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
	candidate.labelHit = label.lineHit || labelTextHit;
	candidate.directHit = candidate.labelHit || footprintHit;
	if (footprintHit)
		candidate.directRank = 0;
	else if (labelTextHit)
		candidate.directRank = isConstellation ? 2 : 1;
	else if (label.lineHit)
		candidate.directRank = 3;
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

bool candidateLess(const PickCandidate& a, const PickCandidate& b)
{
	if (a.directHit != b.directHit)
		return a.directHit;
	if (a.directHit)
	{
		if (a.directRank != b.directRank)
			return a.directRank < b.directRank;
		// Footprint hits use a PC-style distance + k(FOV)*magnitude score.
		// Label and constellation hits still compare anchor distance so text
		// is not stolen by a nearby bright star.
		if (a.directRank == 0)
		{
			if (differs(a.directScore, b.directScore))
				return a.directScore < b.directScore;
		}
		else if (differs(a.distanceVp, b.distanceVp))
			return a.distanceVp < b.distanceVp;
		if (differs(a.typePrior, b.typePrior))
			return a.typePrior > b.typePrior;
		if (differs(a.salience, b.salience))
			return a.salience > b.salience;
		if (differs(a.distanceVp, b.distanceVp))
			return a.distanceVp < b.distanceVp;
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
	const double effectiveRadiusVp = qMax(1.0, qMin(profile.baseRadiusVp, cappedRadiusVp));
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
			const QList<StelObjectP> stars = starMgr->searchAround(tapDirection, fovRadiusDeg, core);
			result.starSearchCount = stars.size();

			const bool starLabels = starMgr->getFlagLabels();
			const StelSkyDrawer* drawer = core->getSkyDrawer();
			result.customStarLimit = drawer->getFlagStarMagnitudeLimit();
			const float starLimit = result.customStarLimit
				? static_cast<float>(drawer->getCustomStarMagnitudeLimit())
				: drawer->getLimitMagnitude();
			result.starLimit = starLimit;
			const double labelLimitMag = (drawer->getLimitMagnitude() - 6.5) * 0.7
				+ starMgr->getLabelsAmount() * 1.2 - 2.0;

			for (const StelObjectP& star : std::as_const(stars))
			{
				const float mag = star->getVMagnitudeWithExtinction(core);
				// StarMgr::draw() culls stars beyond the current magnitude limit;
				// computeRCMag() alone would still admit a catalog star that is
				// not actually on screen.
				if (mag > starLimit)
				{
					++result.starMagnitudeFiltered;
					continue;
				}
				RCMag rc;
				if (!drawer->computeRCMag(mag, &rc) || rc.radius <= 0.f)
				{
					++result.starRadiusFiltered;
					continue;
				}
				const double rVp = rc.radius / ctx.dpr;

				QPointF screenVp;
				Vec3d screenDevice;
				if (!projectToVp(ctx, star->getJ2000EquatorialPos(core), screenVp, screenDevice))
				{
					++result.starDistanceFiltered;
					continue;
				}
				const double starDistanceVp = std::hypot(screenVp.x() - ctx.tapVp.x(),
					screenVp.y() - ctx.tapVp.y());
				if (starDistanceVp > effectiveRadiusVp + rVp + 24.0)
				{
					++result.starDistanceFiltered;
					continue;
				}

				LabelTarget label;
				if (starLabels && core->getFlagClearSky() && mag < labelLimitMag)
				{
					const QString text = objectName(star);
					if (!text.isEmpty())
					{
						label.present = true;
						label.rect = labelRectUpRight(labelMetrics, text, screenVp,
							(rc.radius * 0.7) / ctx.dpr, ctx.dpr);
					}
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
				// Planet::draw() culls hidden objects and planets beyond the
				// optional hard magnitude limit. Keep the picker in sync.
				if (!planet->getPickState(core).pickable)
					continue;
				QPointF screenVp;
				Vec3d screenDevice;
				if (!projectToVp(ctx, planet->getJ2000EquatorialPos(core), screenVp, screenDevice))
					continue;
				const double rVp = visualRadiusForObject(core, ctx, planet);
				bool hasMagnitude = false;
				const double magnitude = magnitudeForObject(core, planet, hasMagnitude);
				addCandidate(candidates, ctx, core, planet, screenVp, rVp, magnitude, hasMagnitude,
					typePriorForObject(planet, false), LabelTarget(), false, SatellitePickDiagnostics());
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
			const float maxMagLabels = core->getSkyDrawer()->getLimitMagnitude() - 2.f
				+ static_cast<float>(nebulaMgr->getLabelsAmount() * 1.2) - 2.f;
			const QList<StelObjectP> nebulae = nebulaMgr->searchAround(tapDirection, fovRadiusDeg, core);
			for (const StelObjectP& nebula : nebulae)
			{
				const NebulaP nebulaObject = qSharedPointerCast<Nebula>(nebula);
				const Nebula::RenderState render = nebulaObject->getRenderState(maxMagHints, maxMagLabels);
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

				bool hasMagnitude = false;
				const double magnitude = magnitudeForObject(core, nebula, hasMagnitude);
				addCandidate(candidates, ctx, core, nebula, screenVp, rVp, magnitude, hasMagnitude,
					typePriorForObject(nebula, nebulaHints), label, false, SatellitePickDiagnostics());
			}
		}
	}

	// --- Constellations (explicit labels / lines only) -------------------
	if (ConstellationMgr* constellationMgr = GETSTELMODULE(ConstellationMgr))
	{
		const bool constellationLabels = constellationMgr->getFlagLabels();
		const bool constellationLines = constellationMgr->getFlagLines();
		if (constellationLabels || constellationLines)
		{
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
				if (!projectToVp(ctx, constellation->getJ2000EquatorialPos(core), screenVp, screenDevice))
					continue;

				LabelTarget label;
				if (constellationLabels)
				{
					const QString text = constellation->getScreenLabel();
					if (!text.isEmpty())
					{
						const QRectF rect = labelRectCentered(labelMetrics, text, screenVp, ctx.dpr);
						if (rect.contains(ctx.tapVp))
						{
							label.present = true;
							label.rect = rect;
						}
					}
				}

				bool lineHit = false;
				const SphericalRegionP region = constellation->getRegion();
				if (constellationLines && region && region->contains(tapDirection))
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
				if (!label.present && !lineHit)
					continue;
				label.lineHit = lineHit;
				addCandidate(candidates, ctx, core, object, screenVp, 0.0, 99.0, false,
					typePriorForObject(object, false), label, false, SatellitePickDiagnostics());
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
			const QList<StelObjectP> objects = objectModule->searchAround(tapDirection, fovRadiusDeg, core);
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
					rVp = qMax(11.0 / ctx.dpr / 2.0, 3.0);
				else if (state.pointDrawn && state.hasMagnitude)
				{
					RCMag rc;
					if (core->getSkyDrawer()->computeRCMag(state.magnitude, &rc) && rc.radius > 0.f)
						rVp = rc.radius / ctx.dpr;
				}

				LabelTarget label;
				if (state.labelDrawn)
				{
					const QString text = objectName(object);
					if (!text.isEmpty())
					{
						label.present = true;
						label.rect = labelRectUpRight(labelMetrics, text, screenVp, 10.0 / ctx.dpr, ctx.dpr);
					}
				}

				SatellitePickDiagnostics diagnostics;
				diagnostics.landscapeVisible = state.landscapeVisible;
				diagnostics.pointDrawn = state.pointDrawn;
				diagnostics.labelDrawn = state.labelDrawn;
				diagnostics.iconDrawn = state.iconDrawn;
				diagnostics.pickable = state.pickable;
				diagnostics.magSat = state.magnitude;
				diagnostics.limitMag = core->getSkyDrawer()->getLimitMagnitude();
				diagnostics.visibility = QStringLiteral("UNKNOWN");

				addCandidate(candidates, ctx, core, object, screenVp, rVp, state.magnitude,
					state.hasMagnitude, typePriorForObject(object, false), label, true, diagnostics);
			}
		}
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
