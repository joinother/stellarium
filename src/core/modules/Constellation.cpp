/*
 * Stellarium
 * Copyright (C) 2002 Fabien Chereau
 * Copyright (C) 2012 Timothy Reaves
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

#include "StelLocaleMgr.hpp"
#include "StelProjector.hpp"
#include "Constellation.hpp"
#include "StarMgr.hpp"
#include "StelModuleMgr.hpp"
#include "NebulaMgr.hpp"

#include "StelSpeechMgr.hpp"
#include "StelTexture.hpp"
#include "StelPainter.hpp"
#include "StelApp.hpp"
#include "StelCore.hpp"
#include "StelUtils.hpp"
#include "ConstellationMgr.hpp"
#include "StelSkyCultureMgr.hpp"
#include "ZoneArray.hpp"
#include "StelModuleMgr.hpp"
#include "StelSkyCultureMgr.hpp"

#include <QString>
#include <QJsonArray>
#include <QTextStream>
#include <QDebug>
#include <QFontMetrics>
#include <QIODevice>
#include <QFile>
#include <QDataStream>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <cmath>
#if defined(__OHOS__)
#include <QElapsedTimer>
#include <hilog/log.h>
#endif

const QString Constellation::CONSTELLATION_TYPE = QStringLiteral("Constellation");

Vec3f Constellation::lineColor = Vec3f(0.4f,0.4f,0.8f);
Vec3f Constellation::labelColor = Vec3f(0.4f,0.4f,0.8f);
Vec3f Constellation::boundaryColor = Vec3f(0.8f,0.3f,0.3f);
Vec3f Constellation::hullColor = Vec3f(0.6f,0.2f,0.2f);
bool Constellation::singleSelected = false;
bool Constellation::seasonalRuleEnabled = false;
float Constellation::artIntensityFovScale = 1.0f;

Constellation::Constellation()
	: numberOfSegments(0)
	, beginSeason(0)
	, endSeason(0)
	, singleStarConstellationRadius(cos(M_PI/360.)) // default radius of 1/2 degrees
	, convexHull(nullptr)
	, artOpacity(1.f)
{
}

Constellation::~Constellation()
{
}

bool Constellation::read(const QJsonObject& data, StarMgr *starMgr)
{
	static NebulaMgr *nebulaMgr=GETSTELMODULE(NebulaMgr);
	static StelCore *core=StelApp::getInstance().getCore();
	const QString id = data["id"].toString();
	const QStringList idParts = id.split(" ");
	if (idParts.size() == 3 && idParts[0] == "CON")
	{
		abbreviation = idParts[2].trimmed();
	}
	else
	{
		qWarning().nospace() << "Bad constellation id: expected \"CON cultureName Abbrev\", got " << id;
		return false;
	}

	const QJsonValue names = data["common_name"].toObject();
	culturalName.translated = names["english"].toString().trimmed();
	culturalName.byname = names["byname"].toString().trimmed();
	culturalName.native = names["native"].toString().trimmed();
	culturalName.pronounce = names["pronounce"].toString().trimmed();
	culturalName.IPA = names["IPA"].toString().trimmed();
	culturalName.transliteration = names["transliteration"].toString().trimmed();

	context = names["context"].toString().trimmed();
	if (culturalName.translated.isEmpty() && culturalName.native.isEmpty() && culturalName.pronounce.isEmpty())
		qWarning() << "No name for constellation" << id;

	constellation.clear();
	const QJsonArray &linesArray=data["lines"].toArray();
	if (linesArray.isEmpty())
	{
		qWarning().nospace() << "Empty lines array found for constellation " << id << " (" << culturalName.native << ")";
		return false;
	}

	const bool isDarkConstellation = (!linesArray[0].toArray().isEmpty() && linesArray[0].toArray()[0].isArray());
	if (isDarkConstellation)
	{
		for (const auto& polyLineObj : linesArray) // auto=[[ra, dec], [ra, dec], ...]
		{
			const auto& polyLine = polyLineObj.toArray();
			if (polyLine.size() < 2) continue; // one point doesn't define a segment

			const auto numSegments = polyLine.size() - 1;
			dark_constellation.reserve(dark_constellation.size() + 2 * numSegments);

			Vec3d prevPoint = Vec3d(0.);
			int darkConstLineIndex=0;
			for (qsizetype i = 0; i < polyLine.size(); ++i)
			{
				if (polyLine[i].isString())
				{
					// Can be "thin" or "bold", but we don't support these modifiers yet, so ignore this entry
					const auto s = polyLine[i].toString();
					if (s == "thin" || s == "bold")
						continue;
				}

				if (!polyLine[i].isArray())
				{
					qWarning().nospace() << "Error in constellation " << id << ": bad point"
							     << polyLine[i].toString() << ": isn't an array of two numbers (RA and dec)";
					return false;
				}
				const QJsonArray arr = polyLine[i].toArray();
				if (arr.size() != 2 || !arr[0].isDouble() || !arr[1].isDouble())
				{
					qWarning().nospace() << "Error in constellation " << id << ": bad point"
							     << polyLine[i].toString() << ": isn't an array of two numbers (RA and dec)";
					return false;
				}

				const double RA = arr[0].toDouble() * (M_PI_180*15.);
				const double DE = arr[1].toDouble() * M_PI_180;
				Vec3d newPoint;
				StelUtils::spheToRect(RA, DE, newPoint);

				if (prevPoint != Vec3d(0.))
				{
					dark_constellation.push_back(QSharedPointer<StelObject>(new CoordObject(QString("%1_%2.A").arg(abbreviation, QString::number(darkConstLineIndex)), prevPoint)));
					dark_constellation.push_back(QSharedPointer<StelObject>(new CoordObject(QString("%1_%2.B").arg(abbreviation, QString::number(darkConstLineIndex)), newPoint)));
				}
				prevPoint = newPoint;
				++darkConstLineIndex;
			}
		}
		numberOfSegments = dark_constellation.size() / 2;
		// Name tag should go to constellation's centre of gravity
		Vec3d XYZname1(0.);
		for(unsigned int ii=0;ii<numberOfSegments*2;ii+=2)
		{
			XYZname1 += dark_constellation[ii]->getJ2000EquatorialPos(nullptr);
		}
		XYZname1.normalize();
		XYZname.append(XYZname1);
	}
	else
	{
		for (const auto& polyLineObj : linesArray)
		{
			const auto& polyLine = polyLineObj.toArray();
			if (polyLine.size() < 2) continue; // one point doesn't define a segment

			const auto numSegments = polyLine.size() - 1;
			constellation.reserve(constellation.size() + 2 * numSegments);

			StelObjectP prevPoint = nullptr;
			for (qsizetype i = 0; i < polyLine.size(); ++i)
			{
				StelObjectP newPoint;
				if (polyLine[i].isString() && polyLine[i].toString().startsWith("DSO:"))
				{
					QString DSOname=polyLine[i].toString().remove(0,4);
					newPoint = nebulaMgr->searchByID(DSOname);
					if (!newPoint)
					{
						qWarning().nospace() << "Error in constellation " << abbreviation << ": can't find DSO " << DSOname << "... skipping constellation";
						return false;
					}
				}
				else
				{
					if (polyLine[i].isString())
					{
						// Can be "thin" or "bold", but we don't support these modifiers yet, so ignore this entry
						const auto s = polyLine[i].toString();
						if (s == "thin" || s == "bold")
							continue;
					}
					const StarId HP = StelUtils::getLongLong(polyLine[i]);
					if (HP > 0)
					{
						newPoint = HP <= NR_OF_HIP ? starMgr->searchHP(HP)
									   : starMgr->searchGaia(HP);
						if (!newPoint)
						{
							qWarning().nospace() << "Error in constellation " << abbreviation << ": can't find star HIP " << HP << "... skipping constellation";
							return false;
						}
					}
				}

				if (prevPoint)
				{
					constellation.push_back(prevPoint);
					constellation.push_back(newPoint);
				}
				prevPoint = newPoint;
			}
		}

		numberOfSegments = constellation.size() / 2;
		if (data.contains("single_star_radius"))
		{
			double rd = data["single_star_radius"].toDouble(0.5);
			singleStarConstellationRadius = cos(rd*M_PI/180.);
		}

		// Name tag should go to constellation's centre of gravity
		Vec3d XYZname1(0.);
		for(unsigned int ii=0;ii<numberOfSegments*2;++ii)
		{
			XYZname1 += constellation[ii]->getJ2000EquatorialPos(core);
		}
		XYZname1.normalize();
		XYZname.append(XYZname1);
	}

	// At this point we have either a constellation or a dark_constellation filled

	// Sometimes label placement is suboptimal. Allow a correction from the automatic solution in label_offset:[dRA_deg, dDec_deg]
	if (data.contains("label_offset"))
	{
		QJsonArray offset=data["label_offset"].toArray();
		if (offset.size()!=2)
			qWarning() << "Bad constellation label offset given for " << id << ", ignoring";
		else
		{
			double ra, dec;
			StelUtils::rectToSphe(&ra, &dec, XYZname[0]);
			ra  += offset[0].toDouble()*M_PI_180;
			dec += offset[1].toDouble()*M_PI_180;
			StelUtils::spheToRect(ra, dec, XYZname[0]);
		}
	}
	// Manual label placement: Manual positions can have more than one (e.g., Serpens has two parts). In this case, discard automatically derived position.
	if (data.contains("label_positions"))
	{
		XYZname.clear();
		const QJsonArray &labelPosArray=data["label_positions"].toArray();
		for (const auto& labelPos : labelPosArray)
		{
			const auto& labelArray=labelPos.toArray();
			if (labelArray.size() != 2)
			{
				qWarning() << "Bad label position given for constellation" << id << "... skipping";
				continue;
			}
			const double RA = labelArray[0].toDouble() * (M_PI_180*15.);
			const double DE = labelArray[1].toDouble() * M_PI_180;
			Vec3d newPoint;
			StelUtils::spheToRect(RA, DE, newPoint);
			XYZname.append(newPoint);
		}
	}

	//qDebug() << "Convex hull for " << englishName;
	if (data.contains("hull_extension"))
	{
		const QJsonArray &hullExtraArray=data["hull_extension"].toArray();

		for (qsizetype i = 0; i < hullExtraArray.size(); ++i)
		{
			if (hullExtraArray[i].isString() && hullExtraArray[i].toString().startsWith("DSO:"))
			{
				QString DSOname=hullExtraArray[i].toString().remove(0,4);
				const StelObjectP newDSO = nebulaMgr->searchByID(DSOname);
				if (!newDSO)
				{
					qWarning().nospace() << "Error in hull_extension for constellation " << abbreviation << ": can't find DSO " << DSOname << "... skipping";
				}
				else
					hullExtension.push_back(newDSO);
			}
			else
			{
				const StarId HP = StelUtils::getLongLong(hullExtraArray[i]);
				if (HP > 0)
				{
					const StelObjectP newStar = HP <= NR_OF_HIP ? starMgr->searchHP(HP)
										    : starMgr->searchGaia(HP);
					if (!newStar)
					{
						qWarning().nospace() << "Error in hull_extension for constellation " << abbreviation << ": can't find StarId " << HP << "... skipping";
					}
					else
						hullExtension.push_back(newStar);
				}
				else
				{
					qWarning().nospace() << "Error in hull_extension for constellation " << abbreviation << ": bad element: " << hullExtraArray[i].toString() << "... skipping";
				}
			}
		}
	}
	hullRadius=data["hull_radius"].toDouble(data["single_star_radius"].toDouble(0.5));

	convexHull=makeConvexHull(constellation, hullExtension, dark_constellation, XYZname.constFirst(), hullRadius);

	beginSeason = 1;
	endSeason = 12;
	const auto visib = data["visibility"];
	if (visib.isUndefined()) return true;
	const auto visibility = visib.toObject();
	const auto months = visibility["months"].toArray();
	if (months.size() != 2)
	{
		qWarning() << "Unexpected format of \"visibility\" entry in constellation" << id;
		return true; // not critical
	}
	beginSeason = months[0].toInt();
	endSeason = months[1].toInt();
	seasonalRuleEnabled = true;

	return true;
}

QString Constellation::getScreenLabel() const
{
	static StelSkyCultureMgr *scMgr=GETSTELMODULE(StelSkyCultureMgr);
	return getCultureLabel(scMgr->getScreenLabelStyle());
}
QString Constellation::getInfoLabel() const
{
	static StelSkyCultureMgr *scMgr=GETSTELMODULE(StelSkyCultureMgr);
	return getCultureLabel(scMgr->getInfoLabelStyle());
}

void Constellation::setNarration(const QString &narration)
{
	this->narration=narration;
}

QString Constellation::getNarration(const StelCore *core, const InfoStringGroup &flags) const
{
	Q_UNUSED(core) Q_UNUSED(flags)
	const StelTranslator& trans = StelApp::getInstance().getLocaleMgr().getSkyCultureDescriptionsTranslator();

	QString toBeSpoken=trans.qtranslate(narration);
	// Strip away HTML and markdown elements like underscores or stars.
	static const QRegularExpression br("<br/?>");
	static const QRegularExpression img("<img .*>");
	static const QRegularExpression latin("_([^_]{0,50})_");
	static const QRegularExpression star("\\*([^\\*]{0,50})\\*");
	QString stripped=toBeSpoken.remove(br).remove(img).replace(latin, "\\1").replace(star, "\\1");

	qCDebug(Speech) << "Constellation name" << getEnglishName() << "narration:" << stripped;

	// Try to get a little break between title and story.
	return getNameI18n() + ". . . " + stripped;
}

QString Constellation::getCultureLabel(StelObject::CulturalDisplayStyle style) const
{
	static StelSkyCultureMgr *scMgr=GETSTELMODULE(StelSkyCultureMgr);
	return scMgr->createCulturalLabel(culturalName, style, getNameI18n(), abbreviationI18n);
}

void Constellation::drawOptim(StelPainter& sPainter, const StelCore* core, const SphericalCap& viewportHalfspace) const
{
	if (lineFader.getInterstate()<=0.0001f)
		return;
	if (!isSeasonallyVisible())
		return;

	const bool isDarkConstellation = !(dark_constellation.empty());
	const float darkFactor = (isDarkConstellation? 0.6667f : 1.0f);
	sPainter.setColor(lineColor*darkFactor, lineFader.getInterstate() * linePresentation);

	if (isDarkConstellation)
		for (unsigned int i=0;i<numberOfSegments;++i)
		{
			Vec3d pos1=dark_constellation[2*i]->getJ2000EquatorialPos(core);
			Vec3d pos2=dark_constellation[2*i+1]->getJ2000EquatorialPos(core);
			//pos1.normalize();
			//pos2.normalize();
			sPainter.drawGreatCircleArc(pos1, pos2, &viewportHalfspace);
		}
	else
		for (unsigned int i=0;i<numberOfSegments;++i)
		{
			Vec3d star1=constellation[2*i]->getJ2000EquatorialPos(core);
			Vec3d star2=constellation[2*i+1]->getJ2000EquatorialPos(core);
			star1.normalize();
			star2.normalize();
			if (star1.fuzzyEquals(star2))
			{
				// draw single-star segment as circle
				SphericalCap scCircle(star1, singleStarConstellationRadius);
				sPainter.drawSphericalRegion(&scCircle, StelPainter::SphericalPolygonDrawModeBoundary);
			}
			else
			{
				if (GETSTELMODULE(ConstellationMgr)->getFlagArt3d())
				{
					Vec3d screen1, screen2;
					const auto projector = sPainter.getProjector();
					if (projector->project(star1, screen1) && projector->project(star2, screen2))
					{
						const double length = std::hypot(screen2[0] - screen1[0], screen2[1] - screen1[1]);
						const double fraction = qMin(0.2, 4.0 * projector->getScreenScale() / qMax(1., length));
						const Vec3d original1 = star1;
						star1 = normalize(star1 * (1.0 - fraction) + star2 * fraction);
						star2 = normalize(star2 * (1.0 - fraction) + original1 * fraction);
					}
				}
				sPainter.drawGreatCircleArc(star1, star2, &viewportHalfspace);
			}
		}
}

// observer centered J2000 coordinates.
// These are either automatically computed from all stars forming the lines,
// or from the manually defined label point(s).
Vec3d Constellation::getJ2000EquatorialPos(const StelCore*) const
{
	if (XYZname.length() ==1)
		return XYZname.first();
	else
	{
		Vec3d point(0.0);
		for (Vec3d namePoint: XYZname)
		{
			point += namePoint;
		}
		point.normalize();
		return point;
	}
}

void Constellation::drawName(const Vec3d &xyName, StelPainter& sPainter, int anchorIndex) const
{
	if (nameFader.getInterstate()==0.0f)
		return;

	// TODO: Find a solution of fallbacks when components are missing?
	if (isSeasonallyVisible())
	{
		QString name = getScreenLabel();
		sPainter.setColor(labelColor, nameFader.getInterstate() * labelPresentation);
		sPainter.queueSkyLabel(getLabelLayoutId(anchorIndex), static_cast<float>(xyName[0]), static_cast<float>(xyName[1]),
			name, 99.f, 0, -sPainter.getFontMetrics().boundingRect(name).width()/2, 0, getID());
	}
}

void Constellation::drawArtOptim(StelPainter& sPainter, const SphericalRegion& region, const Vec3d& obsVelocity) const
{
	if (isSeasonallyVisible())
	{
		const float intensity = artFader.getInterstate() * artOpacity * artIntensityFovScale * artPresentation;
		if (GETSTELMODULE(ConstellationMgr)->getFlagArt3d() && !modelIndices.isEmpty())
		{
			if (modelIntensity() > 0.003f && region.intersects(boundingCap))
				drawArtModel(sPainter, modelIntensity(), obsVelocity);
			return;
		}
		if (artTexture && intensity > 0.0f && region.intersects(boundingCap))
		{
			sPainter.setColor(intensity,intensity,intensity);

			// The texture is not fully loaded
			if (artTexture->bind(0, true)==false)
				return;

			sPainter.drawStelVertexArray(artPolygon, false, obsVelocity);
		}
	}
}

void Constellation::loadArtModel(const QString& path, const Mat4d& transform, int width, int height)
{
	QFile file(path);
	if (!file.open(QIODevice::ReadOnly)) return;
	if (file.size() < 12 || file.size() > 4800012 || file.read(4) != "SCM1") return;
	QDataStream stream(&file);
	stream.setByteOrder(QDataStream::LittleEndian);
	stream.setFloatingPointPrecision(QDataStream::SinglePrecision);
	quint32 vertexCount = 0, indexCount = 0;
	stream >> vertexCount >> indexCount;
	if (!vertexCount || vertexCount > 65535 || !indexCount || indexCount > 600000 || indexCount % 3 ||
	    file.size() != 12 + qint64(vertexCount) * 24 + qint64(indexCount) * 4) return;
	QVector<Vec3d> positions;
	QVector<Vec3f> colors;
	QVector<unsigned short> indices;
	positions.reserve(vertexCount);
	colors.reserve(vertexCount);
	indices.reserve(indexCount);
	const double span = ((transform * Vec3d(width, height * 0.5, 0.)) -
	                     (transform * Vec3d(0., height * 0.5, 0.))).norm();
	const Vec3f light = normalize(Vec3f(-0.35f, 0.5f, 0.8f));
	float minimumHorizontal = 1.f, maximumHorizontal = 0.f;
	float minimumVertical = 1.f, maximumVertical = 0.f;
	for (quint32 vertex = 0; vertex < vertexCount; ++vertex)
	{
		float horizontal, vertical, depth, normalX, normalY, normalZ;
		stream >> horizontal >> vertical >> depth >> normalX >> normalY >> normalZ;
		if (!std::isfinite(horizontal) || !std::isfinite(vertical) || !std::isfinite(depth) ||
		    !std::isfinite(normalX) || !std::isfinite(normalY) || !std::isfinite(normalZ) ||
		    horizontal < -0.1f || horizontal > 1.1f || vertical < -0.1f || vertical > 1.1f ||
		    std::abs(depth) > 2.f) return;
		minimumHorizontal = qMin(minimumHorizontal, horizontal);
		maximumHorizontal = qMax(maximumHorizontal, horizontal);
		minimumVertical = qMin(minimumVertical, vertical);
		maximumVertical = qMax(maximumVertical, vertical);
		Vec3d position = transform * Vec3d(horizontal * width, vertical * height, 0.);
		position.normalize();
		position *= 1.0 - qBound(-0.25, double(depth) * span * 0.25, 0.25);
		positions.append(position);
		Vec3f normal(normalX, normalY, normalZ);
		if (normal.normSquared() < 0.1f || normal.normSquared() > 4.f) return;
		normal.normalize();
		const float rim = std::pow(1.f - qMin(1.f, std::abs(normal[2])), 3.f);
		const float shade = 0.025f + 0.12f * qMax(0.f, normal * light) + 0.55f * rim;
		colors.append(Vec3f(shade * 0.60f, shade * 0.75f, shade));
	}
	for (quint32 index = 0; index < indexCount; ++index)
	{
		quint32 value;
		stream >> value;
		if (value >= vertexCount) return;
		indices.append(value);
	}
	if (stream.status() != QDataStream::Ok) return;
	modelPositions.swap(positions);
	modelColors.swap(colors);
	modelIndices.swap(indices);
	modelCenter = normalize(transform * Vec3d(width * (minimumHorizontal + maximumHorizontal) * 0.5,
	                                        height * (minimumVertical + maximumVertical) * 0.5, 0.));
	modelRight = normalize(transform * Vec3d(width, height * 0.5, 0.) - transform * Vec3d(0., height * 0.5, 0.));
	modelRight = normalize(modelRight - modelCenter * (modelRight * modelCenter));
	modelUp = normalize(modelCenter ^ modelRight);
	double minimumCosine = 1.;
	double poseMargin = 0.;
	for (const Vec3d& position : modelPositions)
	{
		boundingCap.d = qMin(boundingCap.d, boundingCap.n * normalize(position));
		minimumCosine = qMin(minimumCosine, modelCenter * normalize(position));
		poseMargin = qMax(poseMargin, std::asin(qMin(1., 2. * std::sin(0.40 * 0.5) * (position - modelCenter).norm() / position.norm())));
	}
	modelSpanDegrees = 2. * std::acos(qBound(-1., minimumCosine, 1.)) * 180. / M_PI;
	boundingCap.d = std::cos(qMin(M_PI, std::acos(qBound(-1., boundingCap.d, 1.)) + poseMargin));
	modelCachedYaw = 100.f;
	modelCachedIntensity = -1.f;
	modelProjected.resize(modelPositions.size());
	modelValid.resize(modelPositions.size());
	modelDrawColors.resize(modelPositions.size());
	modelVisibleIndices.reserve(modelIndices.size());
}

float Constellation::modelIntensity() const
{
	return artFader.getInterstate() * artOpacity * artPresentation * modelZoomOpacity;
}

void Constellation::prepareModelPose() const
{
	if (modelCachedYaw == modelYaw && modelCachedPitch == modelPitch && modelCachedRoll == modelRoll) return;
	const Mat4d rotation = Mat4d::rotation(modelCenter, modelRoll) * Mat4d::rotation(modelUp, modelYaw) * Mat4d::rotation(modelRight, modelPitch);
	modelDirections.resize(modelPositions.size());
	modelDepths.resize(modelPositions.size());
	for (int index = 0; index < modelPositions.size(); ++index)
	{
		const Vec3d position = modelCenter + rotation * (modelPositions.at(index) - modelCenter);
		modelDirections[index] = normalize(position);
		modelDepths[index] = float((1. - position.norm()) * 2.);
	}
	modelCachedYaw = modelYaw;
	modelCachedPitch = modelPitch;
	modelCachedRoll = modelRoll;
}

void Constellation::drawArtModel(StelPainter& painter, float intensity, const Vec3d& velocity) const
{
#if defined(__OHOS__)
	QElapsedTimer timing;
	timing.start();
#endif
	const auto projector = painter.getProjector();
	prepareModelPose();
	bool allValid = true;
	const int vertexCount = modelPositions.size();
	const Vec3d* directions = modelDirections.constData();
	const float* depths = modelDepths.constData();
	Vec3f* projected = modelProjected.data();
	bool* valid = modelValid.data();
	const bool hasVelocity = velocity.normSquared() > 0.;
	for (int index = 0; index < vertexCount; ++index)
	{
		if (hasVelocity)
		{
			Vec3d direction = directions[index] + velocity;
			direction.normalize();
			valid[index] = projector->project(direction, projected[index]);
		}
		else
		{
			valid[index] = projector->project(directions[index], projected[index]);
		}
		allValid = allValid && valid[index];
		projected[index][2] = depths[index];
	}
	const bool seam = projector->hasProjectionDiscontinuity();
	const QVector<unsigned short>* indices = &modelIndices;
	if (!allValid || seam)
	{
		modelVisibleIndices.clear();
		for (int offset = 0; offset < modelIndices.size(); offset += 3)
		{
			const auto first = modelIndices.at(offset), second = modelIndices.at(offset + 1), third = modelIndices.at(offset + 2);
			if (!modelValid.at(first) || !modelValid.at(second) || !modelValid.at(third)) continue;
			if (seam && (projector->intersectViewportDiscontinuity(modelDirections.at(first), modelDirections.at(second)) ||
			    projector->intersectViewportDiscontinuity(modelDirections.at(second), modelDirections.at(third)) ||
			    projector->intersectViewportDiscontinuity(modelDirections.at(third), modelDirections.at(first)))) continue;
			modelVisibleIndices.append(first);
			modelVisibleIndices.append(second);
			modelVisibleIndices.append(third);
		}
		indices = &modelVisibleIndices;
	}
	if (indices->isEmpty()) return;
	if (modelCachedIntensity != intensity)
	{
		for (int index = 0; index < modelColors.size(); ++index)
		{
			const Vec3f& color = modelColors.at(index);
			modelDrawColors[index] = Vec4f(color[0], color[1], color[2], intensity);
		}
		modelCachedIntensity = intensity;
	}
#if defined(__OHOS__)
	const qint64 projectionNs = timing.nsecsElapsed();
#endif
	auto* gl = QOpenGLContext::currentContext()->functions();
	GLint oldDepthFunction;
	gl->glGetIntegerv(GL_DEPTH_FUNC, &oldDepthFunction);
	painter.setCullFace(false);
	painter.setDepthTest(true);
	painter.setDepthMask(true);
	gl->glClear(GL_DEPTH_BUFFER_BIT);
	gl->glDepthFunc(GL_LEQUAL);
	painter.setVertexPointer(3, GL_FLOAT, modelProjected.constData());
	painter.setColorPointer(4, GL_FLOAT, modelDrawColors.constData());
	painter.enableClientStates(true, false, true);
	painter.drawTrianglesWithDepthPrepass(indices->size(), indices->constData());
	painter.enableClientStates(false);
	painter.setDepthMask(true);
	gl->glClear(GL_DEPTH_BUFFER_BIT);
	painter.setDepthMask(false);
	painter.setDepthTest(false);
	gl->glDepthFunc(oldDepthFunction);
	painter.setBlending(true, GL_ONE, GL_ONE);
	painter.setCullFace(true);
#if defined(__OHOS__)
	static qint64 projectionTotal = 0, drawingTotal = 0;
	static int draws = 0;
	projectionTotal += projectionNs;
	drawingTotal += timing.nsecsElapsed() - projectionNs;
	if (++draws == 600)
	{
		OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "StelModelPerf",
			"draws=600 projectionAvg=%{public}.3fms drawingAvg=%{public}.3fms",
			projectionTotal / 6.e8, drawingTotal / 6.e8);
		projectionTotal = drawingTotal = 0;
		draws = 0;
	}
#endif
}

bool Constellation::modelContainsPoint(const StelProjectorP& projector, const Vec3d& velocity, const Vec3d& point, double tolerance) const
{
	if (modelIndices.isEmpty() || modelIntensity() <= 0.015f || !isSeasonallyVisible()) return false;
	Vec3d direction;
	if (!projector->unProject(point[0], point[1], direction)) return false;
	double margin = 0.;
	for (const Vec3d offset : {Vec3d(tolerance, tolerance, 0.), Vec3d(tolerance, -tolerance, 0.),
	                         Vec3d(-tolerance, tolerance, 0.), Vec3d(-tolerance, -tolerance, 0.)})
	{
		Vec3d edge;
		if (!projector->unProject(point[0] + offset[0], point[1] + offset[1], edge))
		{
			margin = M_PI;
			break;
		}
		margin = qMax(margin, std::acos(qBound(-1., normalize(direction) * normalize(edge), 1.)));
	}
	const double expanded = std::cos(qMin(M_PI, std::acos(qBound(-1., boundingCap.d, 1.)) + margin));
	if (normalize(direction - velocity) * boundingCap.n < expanded) return false;
	prepareModelPose();
	QVector<Vec3f> projected(modelDirections.size());
	QVector<bool> valid(modelDirections.size());
	for (int index = 0; index < modelDirections.size(); ++index)
		valid[index] = projector->project(normalize(modelDirections.at(index) + velocity), projected[index]);
	const bool seam = projector->hasProjectionDiscontinuity();
	const auto edgeDistance = [&point](const Vec3f& start, const Vec3f& end)
	{
		const double horizontal = end[0] - start[0], vertical = end[1] - start[1];
		const double length = horizontal * horizontal + vertical * vertical;
		const double fraction = length > 0. ? qBound(0., ((point[0] - start[0]) * horizontal + (point[1] - start[1]) * vertical) / length, 1.) : 0.;
		return std::hypot(point[0] - start[0] - fraction * horizontal, point[1] - start[1] - fraction * vertical);
	};
	const auto side = [&point](const Vec3f& start, const Vec3f& end)
	{
		return (end[0] - start[0]) * (point[1] - start[1]) - (end[1] - start[1]) * (point[0] - start[0]);
	};
	for (int offset = 0; offset < modelIndices.size(); offset += 3)
	{
		const auto first = modelIndices.at(offset), second = modelIndices.at(offset + 1), third = modelIndices.at(offset + 2);
		if (!valid.at(first) || !valid.at(second) || !valid.at(third)) continue;
		const Vec3f& firstPoint = projected.at(first);
		const Vec3f& secondPoint = projected.at(second);
		const Vec3f& thirdPoint = projected.at(third);
		if (point[0] < std::min({firstPoint[0], secondPoint[0], thirdPoint[0]}) - tolerance ||
		    point[0] > std::max({firstPoint[0], secondPoint[0], thirdPoint[0]}) + tolerance ||
		    point[1] < std::min({firstPoint[1], secondPoint[1], thirdPoint[1]}) - tolerance ||
		    point[1] > std::max({firstPoint[1], secondPoint[1], thirdPoint[1]}) + tolerance) continue;
		if (seam && (projector->intersectViewportDiscontinuity(modelDirections.at(first), modelDirections.at(second)) ||
		    projector->intersectViewportDiscontinuity(modelDirections.at(second), modelDirections.at(third)) ||
		    projector->intersectViewportDiscontinuity(modelDirections.at(third), modelDirections.at(first)))) continue;
		const double firstSide = side(firstPoint, secondPoint), secondSide = side(secondPoint, thirdPoint), thirdSide = side(thirdPoint, firstPoint);
		if ((firstSide > 0. && secondSide > 0. && thirdSide > 0.) ||
		    (firstSide < 0. && secondSide < 0. && thirdSide < 0.)) return true;
		if (edgeDistance(firstPoint, secondPoint) <= tolerance || edgeDistance(secondPoint, thirdPoint) <= tolerance ||
		    edgeDistance(thirdPoint, firstPoint) <= tolerance) return true;
	}
	return false;
}

// Draw the art texture
void Constellation::drawArt(StelPainter& sPainter) const
{
	// Is this ever used?
	Q_ASSERT(0);
	sPainter.setBlending(true, GL_ONE, GL_ONE);
	sPainter.setCullFace(true);
	SphericalRegionP region = sPainter.getProjector()->getViewportConvexPolygon();
	drawArtOptim(sPainter, *region, Vec3d(0.));
	sPainter.setCullFace(false);
}

const Constellation* Constellation::isStarIn(const StelObject* s) const
{
	if (constellation.empty())
		return nullptr;

	for(unsigned int i=0;i<numberOfSegments*2;++i)
	{
		// constellation[i]==s test was not working
		if (constellation[i]->getID()==s->getID()) // don't compare englishNames, we may have duplicate names!
		{
			// qDebug() << "Const matched. " << getEnglishName();
			return this;
		}
	}
	return nullptr;
}

void Constellation::update(int deltaTime)
{
	lineFader.update(deltaTime);
	nameFader.update(deltaTime);
	artFader.update(deltaTime);
	boundaryFader.update(deltaTime);
	hullFader.update(deltaTime);
}

void Constellation::drawBoundaryOptim(StelPainter& sPainter, const Vec3d& obsVelocity) const
{
	if (boundaryFader.getInterstate()==0.0f)
		return;

	sPainter.setBlending(true);
	sPainter.setColor(boundaryColor, boundaryFader.getInterstate());

	unsigned int i, j;
	size_t size;
	std::vector<Vec3d> *points;

	if (singleSelected) size = isolatedBoundarySegments.size();
	else size = sharedBoundarySegments.size();

	const SphericalCap& viewportHalfspace = sPainter.getProjector()->getBoundingCap();

	for (i=0;i<size;i++)
	{
		if (singleSelected) points = isolatedBoundarySegments[i];
		else points = sharedBoundarySegments[i];

		for (j=0;j<points->size()-1;j++)
		{
			Vec3d point0=points->at(j)+obsVelocity;
			point0.normalize();
			Vec3d point1=points->at(j+1)+obsVelocity;
			point1.normalize();

			sPainter.drawGreatCircleArc(point0, point1, &viewportHalfspace);
		}
	}
}

void Constellation::drawHullOptim(StelPainter& sPainter, const Vec3d& obsVelocity) const
{
	if (hullFader.getInterstate()==0.0f || (!convexHull) )
		return;

	sPainter.setBlending(true);
	sPainter.setColor(hullColor, hullFader.getInterstate());

	sPainter.drawSphericalRegion(convexHull.data(), StelPainter::SphericalPolygonDrawModeBoundary, nullptr, true, 5, obsVelocity); // draw nice with aberration
}


bool Constellation::isSeasonallyVisible() const
{
	// Is supported seasonal rules by current sky culture?
	if (!seasonalRuleEnabled)
		return true;

	bool visible = false;
	int year, month, day;
	// Get the current month
	StelUtils::getDateFromJulianDay(StelApp::getInstance().getCore()->getJD(), &year, &month, &day);
	if (endSeason >= beginSeason)
	{
		// OK, it's a "normal" season rule...
		if ((month >= beginSeason) && (month <= endSeason))
			visible = true;
	}
	else
	{
		// ...oops, it's a "inverted" season rule
		if (((month>=1) && (month<=endSeason)) || ((month>=beginSeason) && (month<=12)))
			visible = true;
	}
	return visible;
}

QString Constellation::getInfoString(const StelCore *core, const InfoStringGroup &flags) const
{
	Q_UNUSED(core)
	QString str;
	QTextStream oss(&str);
	// Strip away HTML elements break and image.
	static const QRegularExpression br("<br/?>");
	static const QRegularExpression img("<img .*>");

	if (flags&Name)
	{
		oss << "<h2>" << getInfoLabel() << "</h2>";
	}

	if (flags&ObjectType)
		oss << QString("%1: <b>%2</b>").arg(q_("Type"), getObjectTypeI18n()) << "<br />";

	oss << getSolarLunarInfoString(core, flags);

	if (flags&Extra && !narration.isEmpty())
		oss << QString("%1: ").arg(qc_("Legend", "constellation origin")) << StelUtils::wrapText(StelSkyCultureMgr::markdownToHTML(narration).remove(br).remove(img));
	postProcessInfoString(str, flags);

	return str;
}

StelObjectP Constellation::getBrightestStarInConstellation(void) const
{
	if (constellation.empty())
		return nullptr;

	float maxMag = 99.f;
	StelObjectP brightest;
	// maybe the brightest star has always odd index,
	// so check all segment endpoints:
	for (int i=2*static_cast<int>(numberOfSegments)-1;i>=0;i--)
	{
		const float Mag = constellation[i]->getVMagnitude(Q_NULLPTR);
		if (Mag < maxMag)
		{
			brightest = constellation[i];
			maxMag = Mag;
		}
	}
	for (unsigned int i=0; i<hullExtension.size();++i)
	{
		const float Mag = hullExtension[i]->getVMagnitude(Q_NULLPTR);
		if (Mag < maxMag)
		{
			brightest = hullExtension[i];
			maxMag = Mag;
		}
	}
	return brightest;
}

struct hullEntry
{
	StelObjectP obj;
	double x;
	double y;
};
// simple function only for ordering from Sedgewick 1990, Algorithms in C (p.353) used for sorting.
// The result fulfills the same purpose as some atan2, but with simpler operations.
static double theta(const hullEntry &p1, const hullEntry &p2)
{
	const double dx = p2.x-p1.x;
	const double ax = abs(dx);
	const double dy = p2.y-p1.y;
	const double ay = abs(dy);
	const double asum = ax+ay;
	double t = (asum==0) ? 0.0 : dy/asum;
	if (dx<0.)
		t=2-t;
	else if (dy<0.)
		t=4+t;
	return t*M_PI_2;
}

SphericalRegionP Constellation::makeConvexHull(const std::vector<StelObjectP> &starLines, const std::vector<StelObjectP> &hullExtension, const std::vector<StelObjectP> &darkLines, const Vec3d projectionCenter, const double hullRadius)
{
	static StelCore *core=StelApp::getInstance().getCore();
	// 1. Project every first star of a line pair (or just coordinates from a dark constellation) into a 2D tangential plane around projectionCenter.
	// Stars more than 90° from center cannot be projected of course and are skipped.
	double raC, deC;
	StelUtils::rectToSphe(&raC, &deC, projectionCenter);

	// starLines contains pairs of vertices, and some stars (or DSO) occur more than twice.
	QStringList idList;
	QList<StelObjectP>uniqueObjectList;
	foreach(auto &obj, starLines)
	{
		if (!idList.contains(obj->getID()))
		{
			// Take this star into consideration. However, the "star"s may be pointers to the same star, we must compare IDs.
			idList.append(obj->getID());
			uniqueObjectList.append(obj);
		}
	}
	foreach(auto &obj, hullExtension)
	{
		if (!idList.contains(obj->getID()))
		{
			// Take this star into consideration. However, the "star"s may be pointers to the same star, we must compare IDs.
			idList.append(obj->getID());
			uniqueObjectList.append(obj);
		}
	}
	foreach(auto &obj, darkLines)
	{
		if (!idList.contains(obj->getID()))
		{
			// Take this coordinate into consideration. However, the elements may be pointers to the same direction, we must compare IDs.
			idList.append(obj->getID());
			uniqueObjectList.append(obj);
		}
	}

	QList<hullEntry> hullList;
	// Perspective (gnomonic) projection from Snyder 1987, Map Projections: A Working Manual (USGS).
	// we must use an almost-dummy object type with unique name.
	foreach(auto &obj, uniqueObjectList)
	{
		hullEntry entry;
		entry.obj=obj;
		double ra, de;
		StelUtils::rectToSphe(&ra, &de, entry.obj->getJ2000EquatorialPos(core));
		const double cosC=sin(deC)*sin(de) + cos(deC)*cos(de)*cos(ra-raC);
		if (cosC<=0.) // distance 90° or more from projection center? Discard!
		{
			qWarning() << "Cannot include object" << entry.obj->getID() <<  "in convex hull: too far from projection center.";
			continue;
		}
		const double kP=1./cosC;
		entry.x = -kP*cos(de)*sin(ra-raC); // x must be negative here.
		entry.y =  kP*(cos(deC)*sin(de)-sin(deC)*cos(de)*cos(ra-raC));
		hullList.append(entry);
		//qDebug().noquote().nospace() << "[ " << entry.x << " " << entry.y << " " << ra*M_180_PI/15 << " " << de*M_180_PI << " (" << entry.obj->getID() << ") ]"; // allows Postscript graphics, looks OK.
	}
	//qDebug() << "Hull candidates: " << hullList.length();
	if (hullList.count() < 3)
	{
		//qDebug() << "List length" << hullList.count() << " not enough for a convex hull... create circular area";
		SphericalRegionP res;
		switch (hullList.count())
		{
			case 0:
				res = new EmptySphericalRegion;
				break;
			case 1:
				res = new SphericalCap(projectionCenter, cos(hullRadius*M_PI_180));
				break;
			case 2:
				double halfDist=0.5*acos(hullList.at(0).obj->getJ2000EquatorialPos(core).dot(hullList.at(1).obj->getJ2000EquatorialPos(core)));
				res = new SphericalCap(projectionCenter, cos(halfDist+hullRadius*M_PI_180));
				break;
		}
		return res;
	}

	// 2. Apply Package Wrapping from Sedgewick 1990, Algorithms in C to find the outer points wrapping all points.
	// find minY
	int min=0;
	for(int i=1; i<hullList.count(); ++i)
	{
		const hullEntry &entry=hullList.at(i);
		if (entry.y<hullList.at(min).y)
			min=i;
	}
	//qDebug() << "min entry is " << hullList.at(min).obj->getID();

	const int N=hullList.count(); // N...number of unique stars in constellation.
	//qDebug() << "unique stars N=" << N;
	hullList.append(hullList.at(min));

	//QStringList debugList;
	//// DUMP HULL LINE
	//for(int i=0; i<hullList.count(); ++i)
	//{
	//	const hullEntry &entry=hullList.at(i);
	//	debugList << entry.obj->getID();
	//}
	//qDebug() << "Hull candidate: " << debugList.join(" - ");
	//debugList.clear();

	int M=0;
	double th=0.0;
	for (M=0; M<N; ++M)
	{
#if (QT_VERSION<QT_VERSION_CHECK(5,13,0))
		std::swap(hullList[M], hullList[min]);
#else
		hullList.swapItemsAt(M, min);
#endif

		//// DUMP HULL LINE
		//for(int i=0; i<hullList.count(); ++i)
		//{
		//	const hullEntry &entry=hullList.at(i);
		//	debugList << entry.obj->getID();
		//	if (i==M)
		//		debugList << "|";
		//}
		//qDebug() << "Hull candidate after swap at M=" << M << debugList.join(" - ");
		//debugList.clear();

		min=N; double v=th; th=M_PI*2.0;
		for (int i=M+1; i<=N; ++i)
		{
			//qDebug() << "From M:" << M << "(" << hullList.at(M).obj->getID() << ") to i: " << i << "=" << hullList.at(i).obj->getID() << ": th=" << theta(hullList.at(M), hullList.at(i)) * M_180_PI ;

			if (theta(hullList.at(M), hullList.at(i)) > v)
				if(theta(hullList.at(M), hullList.at(i))< th)
				{
					min=i;
					th=theta(hullList.at(M), hullList.at(min));
					//qDebug() << "min:" << min << "th:" << th * M_180_PI;
				}
		}

		if (min==N)
		{
			//qDebug().nospace() << "min==N=" << N << ", we're done sorting. Hull should be of length M=" << M;
			break; // now M+1 is holds number of "valid" hull points.
		}
	}
	++M;
	//qDebug() << "Hull length" << M << "of" << hullList.count();
#if (QT_VERSION<QT_VERSION_CHECK(6,0,0))
	for (int e=0; e<=N-M; ++e) hullList.pop_back();
#else
	hullList.remove(M, N-M);
#endif
	//hullList.remove(M-1, N-M+1);

	//// DUMP HULL LINE
	//for(int i=0; i<hullList.count(); ++i)
	//{
	//	const hullEntry &entry=hullList.at(i);
	//	debugList << entry.obj->getID();
	//}
	//qDebug() << "Final Hull, M=" << M << debugList.join(" - ");
	//debugList.clear();

	//Now create a SphericalRegion
	QList<Vec3d> hullPoints;
	foreach(const hullEntry &entry, hullList)
	{
		Vec3d pos=entry.obj->getJ2000EquatorialPos(core);
		hullPoints.append(pos);
	}
#if (QT_VERSION<QT_VERSION_CHECK(6,0,0))
	SphericalPolygon *hull=new SphericalPolygon(hullPoints.toVector());
#else
	SphericalConvexPolygon *hull=new SphericalConvexPolygon(hullPoints);
#endif
	//qDebug() << "Successful hull:" << hull->toJSON();
	return hull;
}

void Constellation::makeConvexHull()
{
	// For 2-star automatic hulls, we must recreate the default XYZname (balance point) as hull circle center.
	if (constellation.size()==2 && XYZname.length()==1)
	{
		static StelCore *core=StelApp::getInstance().getCore();
		Vec3d XYZname1(0.);
		for(unsigned int i=0;i<constellation.size();++i)
		{
			XYZname1 += constellation.at(i)->getJ2000EquatorialPos(core);
		}
		XYZname1.normalize();
		convexHull=makeConvexHull(constellation, hullExtension, dark_constellation, XYZname1, hullRadius);
	}
	else
		convexHull=makeConvexHull(constellation, hullExtension, dark_constellation, XYZname.constFirst(), hullRadius);
}
