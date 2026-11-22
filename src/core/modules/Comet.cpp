/*
 * Stellarium
 * Copyright (C) 2010 Bogdan Marinov
 * Copyright (C) 2014 Georg Zotti (Tails)
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
 
#include "Comet.hpp"
#include "Orbit.hpp"
#include "SolarSystem.hpp"

#include "StelApp.hpp"
#include "StelCore.hpp"
#include "StelOpenGL.hpp"
#include "StelPainter.hpp"

#include "StelTexture.hpp"
#include "StelToneReproducer.hpp"
#include "StelTranslator.hpp"
#include "StelUtils.hpp"
#include "StelMovementMgr.hpp"
#include "StelModuleMgr.hpp"
#include "LandscapeMgr.hpp"

#include <QDebug>
#include <QElapsedTimer>
#include <QMatrix4x4>
#include <QOpenGLBuffer>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QOpenGLShaderProgram>
#include <QOpenGLVertexArrayObject>
#include <QVector2D>
#include <algorithm>
#include <cmath>
#include <vector>

// for legacy fallback tail shape
#define COMET_TAIL_SLICES 16u // segments around the perimeter
#define COMET_TAIL_STACKS 16u // cuts along the rotational axis

namespace
{
struct CometVertex
{
	float x, y;
	float u, v;
	float r, g, b;
};

constexpr int COMET_RIBBON_SEGMENTS = 56;
constexpr int COMET_VBO_MAX_VERTS = 1024;

struct TailShaderVars
{
	int projectionMatrix = -1;
	int isGas = -1;
	int seed = -1;
	int phase = -1;
	int headU = -1;
	int striaeStrength = -1;
	int warmth = -1;
};

struct ComaShaderVars
{
	int projectionMatrix = -1;
	int sunDir2D = -1;
	int seed = -1;
	int nucleusSuppress = -1;
	int greenWeight = -1;
};

TailShaderVars s_tailShaderVars;
ComaShaderVars s_comaShaderVars;

inline float smoothStepF(float edge0, float edge1, float x)
{
	if (edge1 <= edge0)
		return (x >= edge1) ? 1.0f : 0.0f;
	const float t = qBound(0.0f, (x - edge0) / (edge1 - edge0), 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

inline float hashCometNameSeed(const QString& name)
{
	uint h = 2166136261u;
	for (const QChar ch : name)
	{
		h ^= static_cast<uint>(ch.unicode());
		h *= 16777619u;
	}
	return 1.0f + static_cast<float>(h % 10000u) * 0.01f;
}
}

// These are to avoid having index arrays for each comet when all are equal.
bool Comet::createTailIndices=true;
bool Comet::createTailTextureCoords=true;
StelTextureSP Comet::comaTexture;
StelTextureSP Comet::tailTexture;
QVector<Vec2f> Comet::tailTexCoordArr; // computed only once for all Comets.
QVector<unsigned short> Comet::tailIndices; // computed only once for all Comets.
std::unique_ptr<QOpenGLShaderProgram> Comet::tailShaderProgram;
std::unique_ptr<QOpenGLShaderProgram> Comet::comaShaderProgram;
std::unique_ptr<QOpenGLVertexArrayObject> Comet::cometVAO;
std::unique_ptr<QOpenGLBuffer> Comet::cometVBO;
QOpenGLContext* Comet::shaderContext = nullptr;
bool Comet::shaderInitFailed = false;

Comet::Comet(const QString& englishName,
	     double radius,
	     double oblateness,
	     Vec3f halocolor,
	     float albedo,
	     float roughness,
	     float outgas_intensity,
	     float outgas_falloff,
	     const QString& atexMapName,
	     const QString& aobjModelName,
	     posFuncType coordFunc,
	     KeplerOrbit* orbitPtr,
	     OsculatingFunctType *osculatingFunc,
	     bool acloseOrbit,
	     bool hidden,
	     const QString& pTypeStr,
	     float dustTailWidthFact,
	     float dustTailLengthFact,
	     float dustTailBrightnessFact)
	: Planet (englishName,
		  radius,
		  oblateness,
		  halocolor,
		  albedo,
		  roughness,
		  atexMapName,
		  "", // no normalmap.
		  "", // no horizon map
		  aobjModelName,
		  coordFunc,
		  orbitPtr,
		  osculatingFunc,
		  acloseOrbit,
		  hidden,
		  false, //No atmosphere
		  true, //halo
		  pTypeStr),
	  slopeParameter(-10.f), // -10 == uninitialized: used in getVMagnitude()
	  isCometFragment(false),
	  iauDesignation(QString()),
	  extraDesignations(),
	  extraDesignationsHtml(),
	  tailFactors(-1., -1.), // mark "invalid"
	  tailActive(false),
	  tailBright(false),
	  deltaJDEtail(15.0*StelCore::JD_MINUTE), // update tail geometry every 15 minutes only
	  lastJDEtail(0.0),
	  dustTailWidthFactor(dustTailWidthFact),
	  dustTailLengthFactor(dustTailLengthFact),
	  dustTailBrightnessFactor(dustTailBrightnessFact),
	  intensityFovScale(1.0f),
	  intensityMinFov(0.001f), // when zooming in further, Coma is no longer visible.
	  intensityMaxFov(0.010f), // when zooming out further, Coma is fully visible (when enabled).
	  renderSeed(hashCometNameSeed(englishName))
{
	this->outgas_intensity =outgas_intensity;
	this->outgas_falloff   =outgas_falloff;

	gastailVertexArr.clear();
	dusttailVertexArr.clear();
	comaVertexArr.clear();
	gastailColorArr.clear();
	dusttailColorArr.clear();

	//TODO: Name processing?
}

Comet::~Comet()
{
}

void Comet::setAbsoluteMagnitudeAndSlope(const float magnitude, const float slope)
{
	if ((slope < -2.5f) || (slope > 25.0f))
	{
		// Slope G can become slightly smaller than 0. -10 is mark of invalidity.
		qWarning().noquote() << "Suspect slope parameter value" << slope << "for comet" << getEnglishName() << "(rarely exceeding -1...20)";
		return;
	}
	absoluteMagnitude = magnitude;
	slopeParameter = slope;
}

void Comet::translateName(const StelTranslator &translator)
{
	static const QRegularExpression cometNamePattern("^(.+)[(](.+)[)]\\s*$");
	QRegularExpressionMatch matchCometName = cometNamePattern.match(englishName);
	if (matchCometName.hasMatch())
		nameI18 = QString("%1(%2)").arg(matchCometName.captured(1),translator.qtranslate(matchCometName.captured(2), "comet"));
	else
		nameI18 = translator.qtranslate(englishName, "comet");

	if (nameI18 == englishName && translator.getTrueLocaleName().startsWith(QLatin1String("zh"), Qt::CaseInsensitive))
	{
		static const QHash<QString, QString> zhComets = {
			{QStringLiteral("1P/Halley (1986)"), QStringLiteral("哈雷彗星 (1P/Halley)")},
			{QStringLiteral("1P/Halley"), QStringLiteral("哈雷彗星")},
			{QStringLiteral("1I/2017 U1 (`Oumuamua)"), QStringLiteral("奥陌陌 (1I/2017 U1)")},
			{QStringLiteral("2I/2019 Q4 (Borisov)"), QStringLiteral("鲍里索夫星际彗星 (2I/2019 Q4)")},
			{QStringLiteral("C/1995 O1 (Hale-Bopp)"), QStringLiteral("海尔-波普彗星 (C/1995 O1)")},
			{QStringLiteral("C/1996 B2 (Hyakutake)"), QStringLiteral("百武彗星 (C/1996 B2)")},
			{QStringLiteral("C/2020 F3 (NEOWISE)"), QStringLiteral("新智彗星 (C/2020 F3)")},
			{QStringLiteral("C/2006 P1 (McNaught)"), QStringLiteral("麦克诺特彗星 (C/2006 P1)")},
			{QStringLiteral("C/2011 W3 (Lovejoy)"), QStringLiteral("洛夫乔伊彗星 (C/2011 W3)")},
			{QStringLiteral("C/1965 S1-A (Ikeya-Seki)"), QStringLiteral("池谷-关彗星 (C/1965 S1-A)")},
			{QStringLiteral("C/1975 V1 (West)"), QStringLiteral("威斯特彗星 (C/1975 V1)")},
			{QStringLiteral("C/1956 R1 (Arend-Roland)"), QStringLiteral("阿伦德-罗兰彗星 (C/1956 R1)")},
			{QStringLiteral("C/1969 Y1 (Bennett)"), QStringLiteral("贝内特彗星 (C/1969 Y1)")},
			{QStringLiteral("C/2023 A3 (Tsuchinshan-ATLAS)"), QStringLiteral("紫金山-阿特拉斯彗星 (C/2023 A3)")},
			{QStringLiteral("C/2026 C1 (Tsuchinshan)"), QStringLiteral("紫金山彗星 (C/2026 C1)")},
		};
		auto it = zhComets.constFind(englishName);
		if (it != zhComets.constEnd())
			nameI18 = it.value();
	}
}

QString Comet::getInfoStringName(const StelCore *core, const InfoStringGroup& flags) const
{
	Q_UNUSED(core) Q_UNUSED(flags)
	QString str;
	QTextStream oss(&str);

	oss << "<h2>";
	oss << getNameI18n(); // UI translation can differ from sky translation

	if (!iauDesignation.isEmpty() &&  !getNameI18n().contains(iauDesignation))
		oss << QString(" - %1").arg(iauDesignation);

	if (!getExtraDesignations().isEmpty())
		oss << QString(" - %1").arg(extraDesignationsHtml.join(" - "));

	if (sphereScale != 1.)
	{
		oss.setRealNumberNotation(QTextStream::FixedNotation);
		oss.setRealNumberPrecision(1);
		oss << QString::fromUtf8(" (\xC3\x97") << sphereScale << ")";
	}
	oss << "</h2>";

	return str;
}

QString Comet::getNarrationName(const StelCore *core, const InfoStringGroup& flags) const
{
	Q_UNUSED(core) Q_UNUSED(flags)
	QString str;
	QTextStream oss(&str);

	oss << getNameI18n(); // UI translation can differ from sky translation

	if (!iauDesignation.isEmpty() &&  !getNameI18n().contains(iauDesignation))
		oss << QString(" , %1").arg(iauDesignation);

	if (!getExtraDesignations().isEmpty())
		oss << QString(" , %1").arg(getExtraDesignations().join(" , "));

	if (sphereScale != 1.)
		oss << " (" << QString(qc_("magnified %1 times", "object narration")).arg(StelUtils::narrateDecimal(sphereScale, 1)) << ")";
	oss << ". . ";

	return str;
}

QString Comet::getInfoStringAbsoluteMagnitude(const StelCore *core, const InfoStringGroup& flags) const
{
	Q_UNUSED(core)
	QString str;
	QTextStream oss(&str);
	if (flags&AbsoluteMagnitude)
	{
		//TODO: Make sure absolute magnitude is a sane value
		//If the two parameter magnitude system is not used, don't display this
		//value. (Using radius/albedo doesn't make any sense for comets.)
		// Note that slope parameter can be <0 (down to -2?), so -10 is now used for "uninitialized"
		if (slopeParameter >= -9.9f)
			oss << QString("%1: %2<br/>").arg(q_("Absolute Magnitude")).arg(absoluteMagnitude, 0, 'f', 2);
	}

	return str;
}

QString Comet::getNarrationAbsoluteMagnitude(const StelCore *core, const InfoStringGroup& flags) const
{
	Q_UNUSED(core)
	QString str;
	QTextStream oss(&str);
	if (flags&AbsoluteMagnitude)
	{
		//TODO: Make sure absolute magnitude is a sane value
		//If the two parameter magnitude system is not used, don't display this
		//value. (Using radius/albedo doesn't make any sense for comets.)
		// Note that slope parameter can be <0 (down to -2?), so -10 is now used for "uninitialized"
		if (slopeParameter >= -9.9f)
			oss << QString(qc_("The comet is listed with an absolute magnitude of %1", "comet narration")).arg(StelUtils::narrateDecimal(absoluteMagnitude, 2)) << ". ";
	}
	return str;
}

QString Comet::getInfoStringSize(const StelCore *core, const InfoStringGroup &flags) const
{
	// TRANSLATORS: Unit of measure for distance - kilometers
	QString km = qc_("km", "distance");
	// TRANSLATORS: Unit of measure for distance - milliones kilometers
	QString Mkm = qc_("M km", "distance");
	const bool withDecimalDegree = StelApp::getInstance().getFlagUseDecDegreesOther();
	QString str;
	QTextStream oss(&str);

	if (flags&Size)
	{
		// Given the very irregular shape, other terminology like "equatorial radius" do not make much sense.
		oss << QString("<br/>%1: %2 %3<br/>").arg(q_("Core diameter"), QString::number(AU * 2.0 * getEquatorialRadius(), 'f', 1) , qc_("km", "distance"));
	}
	if ((flags&Size) && (tailFactors[0]>0.0f))
	{
		// GZ: Add estimates for coma diameter and tail length.
		QString comaEst = q_("Coma diameter (estimate)");
		const double coma = std::floor(static_cast<double>(tailFactors[0])*AU/1000.0)*1000.0;
		const double tail = static_cast<double>(tailFactors[1])*AU;
		const double distanceKm = AU * getJ2000EquatorialPos(core).norm();
		// Try to estimate tail length in degrees.
		// TODO: Take projection effect into account!
		// The estimates here assume that the tail is seen from the side.
		QString comaDeg, tailDeg;
		if (withDecimalDegree)
		{
			comaDeg = StelUtils::radToDecDegStr(atan(coma/distanceKm),4,false,true);
			tailDeg = StelUtils::radToDecDegStr(atan(tail/distanceKm),4,false,true);
		}
		else
		{
			comaDeg = StelUtils::radToDmsStr(atan(coma/distanceKm));
			tailDeg = StelUtils::radToDmsStr(atan(tail/distanceKm));
		}
		if (coma>1e6)
			oss << QString("%1: %2 %3 (%4)<br/>").arg(comaEst, QString::number(coma*1e-6, 'G', 3), Mkm, comaDeg);
		else
			oss << QString("%1: %2 %3 (%4)<br/>").arg(comaEst, QString::number(coma, 'f', 0), km, comaDeg);
		oss << QString("%1: %2 %3 (%4)<br/>").arg(q_("Gas tail length (estimate)"), QString::number(tail*1e-6, 'G', 3), Mkm, tailDeg);
	}
	return str;
}

QString Comet::getNarrationSize(const StelCore *core, const InfoStringGroup &flags) const
{
	const bool withDecimalDegree = StelApp::getInstance().getFlagUseDecDegreesOther();
	QString str;
	QTextStream oss(&str);

	if (flags&Size)
	{
		// Given the very irregular shape, other terminology like "equatorial radius" do not make much sense.
		oss << QString(qc_("Its core diameter is estimated at %1 kilometers", "comet narration")).arg(StelUtils::narrateDecimal(AU * 2.0 * getEquatorialRadius(), 1)) << ". ";
	}
	if ((flags&Size) && (tailFactors[0]>0.0f))
	{
		// Add estimates for coma diameter and tail length.
		const double coma = std::floor(static_cast<double>(tailFactors[0])*AU/1000.0)*1000.0;
		const double tail = static_cast<double>(tailFactors[1])*AU;
		const double distanceKm = AU * getJ2000EquatorialPos(core).norm();
		// Try to estimate tail length in degrees.
		// TODO: Take projection effect into account!
		// The estimates here assume that the tail is seen from the side.
		QString comaDeg, tailDeg;
		if (withDecimalDegree)
		{
			comaDeg = StelUtils::radToDecDegStr(atan(coma/distanceKm),4,false,true);
			tailDeg = StelUtils::radToDecDegStr(atan(tail/distanceKm),4,false,true);
		}
		else
		{
			comaDeg = StelUtils::radToDmsStr(atan(coma/distanceKm));
			tailDeg = StelUtils::radToDmsStr(atan(tail/distanceKm));
		}
		if (coma>1e6)
			oss << QString(qc_("and the coma diameter at %1 million kilometers (or %2 degrees)", "comet narration")).arg(StelUtils::narrateDecimal(coma*1e-6, 3), comaDeg) << ". ";
		else
			oss << QString(qc_("and the coma diameter at %1 kilometers (or %2 degrees)", "comet narration")).arg(StelUtils::narrateDecimal(coma, 0), comaDeg) << ". ";
		oss << QString(qc_("The gas tail length is estimated to be %1 million kilometers long, or %2 degrees in the sky", "comet narration")).arg(StelUtils::narrateDecimal(tail*1e-6, 3), tailDeg) << ". ";
	}
	return str;
}

QString Comet::getInfoStringExtra(const StelCore *core, const InfoStringGroup &flags) const
{
	Q_UNUSED(core)
	if (flags&Extra)
		return getDiscoveryInfoString();
	return QString();
}

QString Comet::getNarrationExtra(const StelCore *core, const InfoStringGroup &flags) const
{
	Q_UNUSED(core)
	if (flags&Extra)
		return getDiscoveryNarration();
	return QString();
}


QVariantMap Comet::getInfoMap(const StelCore *core) const
{
	QVariantMap map = Planet::getInfoMap(core);
	map.insert("tail-length-km", tailFactors[1]*AUf);
	map.insert("coma-diameter-km", tailFactors[0]*AUf);

	return map;
}

double Comet::getSiderealPeriod() const
{
	const double semiMajorAxis=static_cast<KeplerOrbit*>(orbitPtr)->getSemimajorAxis();
	return ((semiMajorAxis>0) ? KeplerOrbit::calculateSiderealPeriod(semiMajorAxis, 1.0) : 0.);
}


float Comet::getVMagnitude(const StelCore* core) const
{
	return getVMagnitude(core, 1.0);
}

float Comet::getVMagnitude(const StelCore* core, const double eclipseFactor) const
{
	Q_UNUSED(eclipseFactor)
	//If the two parameter system is not used,
	//use the default radius/albedo mechanism
	if (slopeParameter < -9.0f)
	{
		return Planet::getVMagnitude(core, 1.);
	}

	//Calculate distances
	Vec3d observerHeliocentricPosition;
	if (core->getCurrentPlanet()->getPlanetType()==Planet::isObserver)

		observerHeliocentricPosition = Vec3d(0.f,0.f,0.f);
	else
		observerHeliocentricPosition = core->getObserverHeliocentricEclipticPos();

	const Vec3d& cometHeliocentricPosition = getHeliocentricEclipticPos();
	const float cometSunDistance = static_cast<float>(cometHeliocentricPosition.norm());
	const float observerCometDistance = static_cast<float>((observerHeliocentricPosition - cometHeliocentricPosition).norm());

	//Calculate apparent magnitude
	//Sources: http://www.clearskyinstitute.com/xephem/help/xephem.html#mozTocId564354
	//(XEphem manual, section 7.1.2.3 "Magnitude models"), also
	//http://www.ayton.id.au/gary/Science/Astronomy/Ast_comets.htm#Comet%20facts:
	// GZ: Note that Meeus, Astr.Alg.1998 p.231, has m=absoluteMagnitude+5log10(observerCometDistance) + kappa*log10(cometSunDistance)
	// with kappa typically 5..15. MPC provides Slope parameter. So we should expect to have slopeParameter (a word only used for minor planets!) for our comets 2..6
	return absoluteMagnitude + 5.f * std::log10(observerCometDistance) + 2.5f * slopeParameter * std::log10(cometSunDistance);
}

void Comet::update(int deltaTime)
{
	Planet::update(deltaTime);

	//calculate FOV fade value, linear fade between intensityMaxFov and intensityMinFov
	const float vfov = static_cast<float>(StelApp::getInstance().getCore()->getMovementMgr()->getCurrentFov());
	intensityFovScale = qBound(0.25f,(vfov - intensityMinFov) / (intensityMaxFov - intensityMinFov),1.0f);

	// The rest deals with updating tail geometries and brightness
	StelCore* core=StelApp::getInstance().getCore();
	double dateJDE=core->getJDE();

	if (!static_cast<KeplerOrbit*>(orbitPtr)->objectDateGoodEnoughForOrbits(dateJDE)) return; // don't do anything if out of useful date range. This allows having hundreds of comet elements.

	if (tailFactors[0] < 0.0f || fabs(lastJDEtail-dateJDE)>deltaJDEtail)
	{
		lastJDEtail=dateJDE;

		if (tailFactors[0] < 0.0f || static_cast<KeplerOrbit*>(orbitPtr)->getUpdateTails()){
			// Keep physical coma diameter and gas tail length estimates updated for info displays & rendering.
			tailFactors=getComaDiameterAndTailLengthAU();
			tailActive = (tailFactors[1] > 0.0f && tailFactors[0] > 0.0f);

			// Only construct legacy paraboloid meshes if procedural shaders failed to initialize.
			if (shaderInitFailed)
			{
				computeComa(1.0f*tailFactors[0]);
				tailActive = (tailFactors[1] > tailFactors[0]);
				if (tailActive)
				{
					float gasTailEndRadius=qMax(tailFactors[0], 0.025f*tailFactors[1]);
					float gasparameter=gasTailEndRadius*gasTailEndRadius/(2.0f*tailFactors[1]);
					float dustparameter=gasTailEndRadius*gasTailEndRadius*dustTailWidthFactor*dustTailWidthFactor/(2.0f*dustTailLengthFactor*tailFactors[1]);

					computeParabola(gasparameter, gasTailEndRadius, -0.5f*gasparameter, gastailVertexArr, tailTexCoordArr, tailIndices);
					computeParabola(dustparameter, dustTailWidthFactor*gasTailEndRadius, -0.5f*dustparameter, dusttailVertexArr, tailTexCoordArr, tailIndices, 25.0f*static_cast<float>(static_cast<KeplerOrbit*>(orbitPtr)->getVelocity().norm()));

					Vec3d eclposNrm=eclipticPos+aberrationPush; eclposNrm.normalize();
					gasTailRot=Mat4d::rotation(Vec3d(0.0, 0.0, 1.0)^(eclposNrm), std::acos(Vec3d(0.0, 0.0, 1.0).dot(eclposNrm)) );
					Vec3d velocity=static_cast<KeplerOrbit*>(orbitPtr)->getVelocity();
					dustTailRot=gasTailRot * Mat4d::zrotation(atan2(velocity[1], velocity[0]) + M_PI) * Mat4d::yrotation(5.0*velocity.norm());

					Vec3d* gasVertices= static_cast<Vec3d*>(gastailVertexArr.data());
					Vec3d* dustVertices=static_cast<Vec3d*>(dusttailVertexArr.data());
					for (unsigned short int i=0; i<COMET_TAIL_SLICES*COMET_TAIL_STACKS+1; ++i)
					{
						gasVertices[i].transfo4d(gasTailRot);
						dustVertices[i].transfo4d(dustTailRot);
					}
				}
			}
			static_cast<KeplerOrbit*>(orbitPtr)->setUpdateTails(false);
		}
	}

	if (!shaderInitFailed)
	{
		tailBright = true;
		return;
	}

	// Legacy brightness/extinction fallback path
	const bool withAtmosphere=(core->getSkyDrawer()->getFlagHasAtmosphere());
	StelToneReproducer* eye = core->getToneReproducer();
	const float lum = core->getSkyDrawer()->surfaceBrightnessToLuminance(getVMagnitude(core)+13.0f);
	float aLum =eye->adaptLuminanceScaled(lum);
	static StelMovementMgr* mMgr=GETSTELMODULE(StelMovementMgr);
	const float fov = mMgr->getCurrentFov();
	if (fov>20)
		aLum*= (fov/20.0f);

	if (aLum<0.002f)
	{
		tailBright=false;
		return;
	} else
		tailBright=true;

	float gasMagFactor=qMin(0.9f*aLum, 0.7f);
	float dustMagFactor=qMin(dustTailBrightnessFactor*aLum, 0.7f);
	Vec3f gasColor(0.15f*gasMagFactor,0.35f*gasMagFactor,0.6f*gasMagFactor);
	Vec3f dustColor(dustMagFactor, dustMagFactor,0.6f*dustMagFactor);

	if (withAtmosphere)
	{
		Extinction extinction=core->getSkyDrawer()->getVisualExtinction();
		static LandscapeMgr *lMgr=GETSTELMODULE(LandscapeMgr);
		const float avgAtmLum=lMgr->getAtmosphereAverageLuminance();
		const float brightnessDecreasePerVertexFromHead=1.0f/(COMET_TAIL_SLICES*COMET_TAIL_STACKS) * avgAtmLum;
		float brightnessPerVertexFromHead=1.0f;
		const Vec3d tailEclOffset = eclipticPos + aberrationPush;
		gastailColorArr.clear();
		dusttailColorArr.clear();
		for (int i=0; i<gastailVertexArr.size(); ++i)
		{
			Vec3d vertAltAz = core->heliocentricEclipticToAltAz(gastailVertexArr.at(i) + tailEclOffset, StelCore::RefractionOn);
			vertAltAz.normalize();
			float oneMag=0.0f;
			extinction.forward(vertAltAz, &oneMag);
			float extinctionFactor=std::pow(0.4f, oneMag);
			gastailColorArr.append(gasColor*extinctionFactor* brightnessPerVertexFromHead*intensityFovScale);

			vertAltAz = core->heliocentricEclipticToAltAz(dusttailVertexArr.at(i) + tailEclOffset, StelCore::RefractionOn);
			vertAltAz.normalize();
			oneMag=0.0f;
			extinction.forward(vertAltAz, &oneMag);
			extinctionFactor=std::pow(0.4f, oneMag);
			dusttailColorArr.append(dustColor*extinctionFactor * brightnessPerVertexFromHead*intensityFovScale);

			brightnessPerVertexFromHead-=brightnessDecreasePerVertexFromHead;
		}
	}
	else
	{
		gastailColorArr.fill(gasColor  *intensityFovScale, gastailVertexArr.length());
		dusttailColorArr.fill(dustColor*intensityFovScale, dusttailVertexArr.length());
	}
}


// Draw the Comet and all the related infos: name, circle etc... GZ: Taken from Planet.cpp 2013-11-05 and extended
void Comet::draw(StelCore* core, float maxMagLabels, const QFont& planetNameFont, const double eclipseFactor)
{
	Q_UNUSED(eclipseFactor)
	if (hidden)
		return;

	static SolarSystem *ss=GETSTELMODULE(SolarSystem);
	const float vMagnitude=getVMagnitude(core);

	// Exclude drawing if user set a hard limit magnitude.
	if (core->getSkyDrawer()->getFlagPlanetMagnitudeLimit() && (vMagnitude > static_cast<float>(core->getSkyDrawer()->getCustomPlanetMagnitudeLimit())))
		return;

	if (getEnglishName() == core->getCurrentLocation().planetName)
	{ // Maybe even don't do that? E.g., draw tail while riding the comet? Decide later.
		return;
	}

	// This test seemed necessary for reasonable fps in case too many comet elements are loaded.
	// Problematic: Early-out here of course disables the wanted hint circles for dim comets.
	// The line makes hints for comets 5 magnitudes below sky limiting magnitude visible.
	// If comet is too faint to be seen, don't bother rendering. (Massive speedup if people have hundreds of comet elements!)
	if ((ss->getMarkerValue()==0.) && ((vMagnitude-5.0f) > core->getSkyDrawer()->getLimitMagnitude()) && !core->getCurrentLocation().planetName.contains("Observer", Qt::CaseInsensitive))
	{
		return;
	}
	if (!static_cast<KeplerOrbit*>(orbitPtr)->objectDateGoodEnoughForOrbits(core->getJDE())) return; // don't draw at all if out of useful date range. This allows having hundreds of comet elements.

	Mat4d mat = Mat4d::translation(eclipticPos+aberrationPush) * rotLocalToParent;
	// This removed totally the Planet shaking bug!!!
	StelProjector::ModelViewTranformP transfo = core->getHeliocentricEclipticModelViewTransform();
	transfo->combine(mat);

	// Compute the 2D position and check if in the screen
	const StelProjectorP prj = core->getProjection(transfo);
	const double screenRd = (getAngularRadius(core))*M_PI_180*static_cast<double>(prj->getPixelPerRadAtCenter());
	const double viewport_left = prj->getViewportPosX();
	const double viewport_bottom = prj->getViewportPosY();
	const bool projectionValid=prj->project(Vec3d(0.), screenPos);
	if (projectionValid
		&& screenPos[1] > viewport_bottom - screenRd
		&& screenPos[1] < viewport_bottom + prj->getViewportHeight()+screenRd
		&& screenPos[0] > viewport_left - screenRd
		&& screenPos[0] < viewport_left + prj->getViewportWidth() + screenRd)
	{
		// Draw the name, and the circle if it's not too close from the body it's turning around
		// this prevents name overlapping (ie for jupiter satellites)
		float ang_dist = 300.f*static_cast<float>(atan(getEclipticPos().norm()/getEquinoxEquatorialPos(core).norm())/core->getMovementMgr()->getCurrentFov());
		// if (ang_dist==0.f) ang_dist = 1.f; // if ang_dist == 0, the Planet is sun.. --> GZ: we can remove it.

		// by putting here, only draw orbit if Comet is visible for clarity
		drawOrbit(core);  // TODO - fade in here also...

		labelsFader = (flagLabels && ang_dist>0.25f && maxMagLabels>vMagnitude);

		if (core->getFlagClearSky())
		{ // encapsulate painter!
			const StelProjectorP prjin = core->getProjection(StelCore::FrameJ2000);
			StelPainter sPainter(prjin);
			drawHints(core, sPainter, planetNameFont);
			Vec3f color=Vec3f(0.25, 0.75, 1);
			if (vMagnitude < ss->getMarkerMagThreshold())
				ss->drawAsteroidMarker(core, &sPainter, screenPos[0], screenPos[1], color); // This does not draw directly, but record an entry to be drawn in a batch.
		}

		// Only draw the 3D rocky nucleus model when resolved on screen (or in legacy fallback);
		// otherwise Planet::draw3dModel() draws a harsh star-like planet halo disk over the procedural coma.
		if (screenRd > 1.0 || shaderInitFailed)
			draw3dModel(core, transfo, static_cast<float>(screenRd), 1.0);
	}
	else
		if (!projectionValid && prj.data()->getNameI18() == q_("Orthographic"))
			return; // End prematurely. This excludes bad "ghost" comet tail on the wrong hemisphere in ortho projection! Maybe also Fisheye, but it's less problematic.
	else if (permanentDrawingOrbits) // A special case for demos
			drawOrbit(core);


	// If comet is too faint to be seen, don't bother rendering. (Massive speedup if people have hundreds of comets!)
	// This test moved here so that hints are still drawn.
	if ((vMagnitude-5.0f) > core->getSkyDrawer()->getLimitMagnitude())
	{
		return;
	}

	if (tailFactors[0] < 0.0f)
		tailFactors = getComaDiameterAndTailLengthAU();

	if (ensureShaders())
	{
		const Vec3d cometEcl = eclipticPos + aberrationPush;
		const double rHelio = cometEcl.norm();
		if (rHelio > 1e-6)
		{
			const Vec3d antiSun = cometEcl / rHelio;
			const Vec3d observerEcl = (core->getCurrentPlanet()->getPlanetType() == Planet::isObserver)
				? Vec3d(0.0, 0.0, 0.0)
				: core->getObserverHeliocentricEclipticPos();
			const double distObs = (cometEcl - observerEcl).norm();

			// Clean heliocentric ecliptic transform centered at the comet (independent of nucleus spin axis).
			StelProjector::ModelViewTranformP tailTransfo = core->getHeliocentricEclipticModelViewTransform();
			tailTransfo->combine(Mat4d::translation(cometEcl));
			const StelProjectorP tailPrj = core->getProjection(tailTransfo);

			// Compute real astrophysical morphology from orbital elements, perihelion timing, and 3D viewing geometry.
			const KeplerOrbit* kOrbit = static_cast<KeplerOrbit*>(orbitPtr);
			const double periQ = std::max(0.002, kOrbit->getPericenterDistance());
			const double ecc = std::max(0.0, kOrbit->getEccentricity());
			const double tPeri = kOrbit->getTimeAtPericenter();
			double dtDays = core->getJDE() - tPeri;
			const double periodDays = getSiderealPeriod();
			if (periodDays > 10.0)
				dtDays = std::remainder(dtDays, periodDays);

			// 1. Outgassing activity by heliocentric distance (water-ice sublimation ~2.5 AU, CO coma out to ~6.4 AU)
			const float activity = 1.0f - smoothStepF(3.0f, 6.4f, static_cast<float>(rHelio));
			const float closeSunStress = 1.0f - smoothStepF(0.08f, 0.50f, static_cast<float>(periQ));
			const float instantHeat = 1.0f - smoothStepF(0.25f, 1.50f, static_cast<float>(rHelio));

			// 2. Pre-perihelion vs post-perihelion thermal lag & dust surge (peaks ~+5 to +45 days post-perihelion)
			const float postSurge = smoothStepF(-6.0f, 14.0f, static_cast<float>(dtDays))
			                      * (1.0f - smoothStepF(45.0f, 150.0f, static_cast<float>(dtDays)));
			const float preBuild  = 0.78f + 0.22f * smoothStepF(-90.0f, 0.0f, static_cast<float>(dtDays));

			// 3. 3D viewing geometry: phase angle (Mie forward scattering) & orbital-plane tilt (edge-on vs broadside)
			const Vec3d viewDir = (distObs > 1e-6) ? ((cometEcl - observerEcl) / distObs) : Vec3d(0.0, 0.0, 1.0);
			const double cosPhase = qBound(-1.0, (-antiSun).dot(-viewDir), 1.0);
			const float phaseDeg = static_cast<float>(std::acos(cosPhase) * M_180_PI);
			const float forwardScatter = 1.0f + 0.80f * smoothStepF(98.0f, 152.0f, phaseDeg);

			const Vec3d vel = kOrbit->getVelocity();
			const double velNorm = vel.norm();
			Vec3d orbitNormal = cometEcl ^ vel;
			float faceOn = 0.65f;
			if (orbitNormal.normSquared() > 1e-14)
			{
				orbitNormal.normalize();
				faceOn = static_cast<float>(std::fabs(orbitNormal.dot(viewDir)));
			}
			// Edge-on plane crossings compress dust fan into a crisp, bright blade; broadside views open the fan wide.
			const float edgeOnFactor = 1.0f - smoothStepF(0.06f, 0.36f, faceOn);
			const float planeWidthScale = qBound(0.38f, 0.38f + 0.85f * smoothStepF(0.05f, 0.72f, faceOn), 1.25f);
			const float planeBrightBoost = 1.0f + 0.42f * edgeOnFactor;

			// 4. Comet taxonomy archetype from (q, e, H):
			//    - Sunskirter / Striated (q < 0.35): West, McNaught, NEOWISE, C/2024 G3 ATLAS
			//    - Dust-rich Great Long-Period (e >= 0.95 & H < 2.5): Hale-Bopp
			//    - Gas-rich Green C2 / Halley-type (e >= 0.85 & H >= 2.5): Hyakutake, 1P/Halley, ZTF
			//    - Aged Short-Period (e < 0.85): 161P/Hartley-IRAS, 67P, 2P/Encke
			const float isLongPeriod = smoothStepF(0.80f, 0.96f, static_cast<float>(ecc));
			const float isIntrinsicBright = 1.0f - smoothStepF(1.5f, 6.5f, absoluteMagnitude);
			const float sunskirterScore = closeSunStress * (0.45f + 0.55f * std::max(instantHeat, postSurge));

			const float dustClassScale = (0.72f + 0.45f * isIntrinsicBright + 0.55f * sunskirterScore)
			                           * (preBuild + 0.42f * postSurge * (0.4f + 0.6f * closeSunStress));
			const float gasClassScale  = 0.82f + 0.35f * isLongPeriod * (1.0f - 0.35f * sunskirterScore);
			const float striaeStrength = qBound(0.15f,
				0.18f + 0.65f * sunskirterScore + 0.25f * postSurge * isLongPeriod * faceOn, 0.95f) * (1.0f - 0.65f * edgeOnFactor);
			const float dustWarmth = qBound(0.0f,
				0.20f + 0.48f * sunskirterScore + 0.32f * smoothStepF(100.0f, 150.0f, phaseDeg), 1.0f);
			const float greenComaWeight = qBound(0.12f,
				0.82f - 0.52f * isIntrinsicBright - 0.38f * sunskirterScore - 0.22f * postSurge * closeSunStress, 0.92f);

			// Twilight / daylight sky-luminance suppression (forward-scattered great comets remain visible deeper into twilight).
			float twilightFade = 1.0f;
			if (core->getSkyDrawer()->getFlagHasAtmosphere())
			{
				static LandscapeMgr* lMgr = GETSTELMODULE(LandscapeMgr);
				const float avgAtmLum = std::max(0.0f, lMgr->getAtmosphereAverageLuminance());
				const float skyTol = qBound(0.25f, std::pow(10.0f, -0.30f * (vMagnitude - 2.0f)) * 1.25f * forwardScatter, 60.0f);
				twilightFade = 1.0f / (1.0f + avgAtmLum / skyTol);
			}

			// Telescopic aperture boost for faint comets when zooming into narrower FOVs,
			// while keeping bright naked-eye comets translucent and free of white-clipping blowouts.
			static StelMovementMgr* mMgr = GETSTELMODULE(StelMovementMgr);
			const float fov = std::max(0.05f, static_cast<float>(mMgr->getCurrentFov()));
			const float faintBoostWeight = smoothStepF(3.0f, 8.5f, vMagnitude);
			const float zoomBoost = (fov < 45.0f)
				? qBound(0.0f, 2.75f * std::log2(45.0f / std::max(fov, 0.25f)), 7.8f) * faintBoostWeight
				: 0.0f;
			const float effMag = vMagnitude - zoomBoost;

			// Perceptual magnitude-to-radiance mapping with photographic shoulder compression.
			const float rawMagBright = std::pow(10.0f, -0.16f * (effMag - 1.5f));
			const float tailVis = (rawMagBright / (1.0f + 1.15f * rawMagBright)) * activity * intensityFovScale;

			const double comaRadAU = 0.5 * std::max(static_cast<double>(tailFactors[0]), 2.5e-5);
			const bool showTail = (activity > 0.01f) && (tailVis * twilightFade > 0.004f) && (distObs > 1e-5);

			if (showTail)
			{
				Vec3d trailDir = -vel - antiSun * ((-vel).dot(antiSun));
				if (trailDir.normSquared() > 1e-12)
				{
					trailDir.normalize();
				}
				else
				{
					const Vec3d fallbackUp = (std::fabs(antiSun[2]) < 0.9) ? Vec3d(0.0, 0.0, 1.0) : Vec3d(1.0, 0.0, 0.0);
					trailDir = (antiSun ^ fallbackUp);
					trailDir.normalize();
				}

				const double maxSpanAU = distObs * 1.45;
				const double baseGasLen = std::max(static_cast<double>(tailFactors[1]), comaRadAU * 10.5 * static_cast<double>(activity));
				const double gasLenAU = std::min(maxSpanAU, baseGasLen * static_cast<double>(gasClassScale));

				const double dustLenRatio = std::max(static_cast<double>(dustTailLengthFactor), 0.58)
				                          * static_cast<double>(dustClassScale);
				const double baseDustLen = std::max(static_cast<double>(tailFactors[1]) * dustLenRatio,
				                                    comaRadAU * 7.8 * static_cast<double>(activity * dustClassScale));
				const double dustLenAU = std::min(maxSpanAU, baseDustLen);

				const float dustIntensity = qMin(0.88f,
					tailVis * qBound(0.65f, 0.95f * dustTailBrightnessFactor, 1.25f)
					        * (0.90f + 0.35f * dustClassScale) * forwardScatter * planeBrightBoost);
				const float gasIntensity  = qMin(0.32f,
					tailVis * 0.34f * gasClassScale);

				const float fanWidthScale = planeWidthScale * (0.85f + 0.40f * sunskirterScore + 0.20f * postSurge);
				const float curvatureScale = (0.85f + 0.45f * sunskirterScore + 0.25f * postSurge) * (0.45f + 0.55f * faceOn);

				drawProceduralTail(core, tailPrj, false, cometEcl, observerEcl, antiSun, trailDir, velNorm,
				                   comaRadAU, dustLenAU, dustIntensity, twilightFade,
				                   fanWidthScale, curvatureScale, striaeStrength, dustWarmth);
				drawProceduralTail(core, tailPrj, true,  cometEcl, observerEcl, antiSun, trailDir, velNorm,
				                   comaRadAU, gasLenAU,  gasIntensity,  twilightFade,
				                   1.0f, 1.0f, 0.0f, 0.0f);
			}

			drawProceduralComa(core, tailPrj, cometEcl, observerEcl, antiSun, comaRadAU,
			                   vMagnitude, static_cast<float>(screenRd), twilightFade, greenComaWeight);
		}
		return;
	}

	// Legacy fallback if procedural shaders failed to initialize
	if (tailActive && tailBright)
	{
		drawTail(core,transfo,true);  // gas tail
		drawTail(core,transfo,false); // dust tail
	}
	//Coma: this is just a fan disk tilted towards the observer;-)
	drawComa(core, transfo);
	return;
}

void Comet::deinitShader()
{
	if (QOpenGLContext::currentContext())
	{
		if (cometVAO && cometVAO->isCreated())
			cometVAO->destroy();
		if (cometVBO && cometVBO->isCreated())
			cometVBO->destroy();
	}
	cometVAO.reset();
	cometVBO.reset();
	tailShaderProgram.reset();
	comaShaderProgram.reset();
	shaderContext = nullptr;
	shaderInitFailed = false;
}

bool Comet::ensureShaders()
{
	QOpenGLContext* ctx = QOpenGLContext::currentContext();
	if (!ctx)
		return false;

	if (shaderContext != ctx)
	{
		deinitShader();
		shaderContext = ctx;
		shaderInitFailed = false;
	}
	if (shaderInitFailed)
		return false;
	if (tailShaderProgram && comaShaderProgram && cometVBO && cometVBO->isCreated())
		return true;

	const QByteArray vertSrc =
		StelOpenGL::globalShaderPrefix(StelOpenGL::VERTEX_SHADER) +
		R"(
ATTRIBUTE highp vec2 a_pos;
ATTRIBUTE highp vec2 a_uv;
ATTRIBUTE mediump vec3 a_color;
uniform highp mat4 u_projectionMatrix;
VARYING highp vec2 v_uv;
VARYING mediump vec3 v_color;
void main(void)
{
	v_uv = a_uv;
	v_color = a_color;
	gl_Position = u_projectionMatrix * vec4(a_pos, 0.0, 1.0);
}
)";

	const QByteArray noiseHelper = R"(
highp float hash12(highp vec2 p)
{
	highp vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
highp float vnoise(highp vec2 p)
{
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	highp vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}
highp float fbm3(highp vec2 p)
{
	highp float sum = 0.0;
	highp float amp = 0.55;
	sum += amp * vnoise(p); p = p * 2.03 + vec2(17.1, 31.7); amp *= 0.5;
	sum += amp * vnoise(p); p = p * 2.01 + vec2(11.3, 47.9); amp *= 0.5;
	sum += amp * vnoise(p);
	return sum;
}
)";

	const QByteArray tailFragSrc =
		StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) +
		noiseHelper +
		R"(
VARYING highp vec2 v_uv;
VARYING mediump vec3 v_color;
uniform mediump float u_isGas;
uniform highp float u_seed;
uniform highp float u_phase;
uniform highp float u_headU;
uniform mediump float u_striaeStrength;
uniform mediump float u_warmth;
void main(void)
{
	highp float u = clamp(v_uv.x, 0.0, 1.0);
	highp float v = clamp(v_uv.y, -1.0, 1.0);
	highp float oneMinusV2 = max(0.0, 1.0 - v * v);
	highp float oneMinusU = max(0.0, 1.0 - u);

	// Seamless parabolic head onset starting slightly sunward of the nucleus (-0.38 R_coma),
	// so the tail is already glowing right inside the core with zero dark gap and zero flat edge.
	highp float headSpan = clamp(u_headU * 0.90, 0.0025, 0.06);
	highp float uCurved = u - headSpan * 0.52 * v * v;
	highp float headEnvelope = smoothstep(0.0, headSpan, uCurved);

	mediump float density = 0.0;
	mediump vec3 tint = vec3(1.0);

	if (u_isGas > 0.5)
	{
		// Pure silky translucent sapphire-cobalt ion fan (single ultra-soft mist octave, zero zebra stripes)
		highp float edgeMask = pow(oneMinusV2, 2.2);
		highp float across = 0.56 * exp(-v * v * 2.6) + 0.44 * exp(-v * v * 1.10);
		highp float along  = pow(oneMinusU, 1.45) / pow(1.0 + 3.0 * u, 1.35);

		highp float rayOnset = smoothstep(0.08, 0.40, u);
		highp float softRay = vnoise(vec2(u * 0.75 + u_seed * 3.1, v * 2.1 + u_seed * 9.7));
		highp float gasMod = mix(1.0, mix(0.86, 1.14, softRay), rayOnset);

		density = float(headEnvelope * along * edgeMask * across * gasMod);
		tint = mix(vec3(0.24, 0.54, 1.00), vec3(0.11, 0.34, 0.96), float(smoothstep(0.02, 0.35, u)));
	}
	else
	{
		// Pure velvety Finson-Probstein creamy-ivory dust fan (analytical Gaussian + ultra-subtle mist, zero zebra stripes)
		highp float edgeMask = pow(oneMinusV2, 2.3);
		highp float vAsym = (v < 0.0) ? (v * 1.42) : (v * 0.72);
		highp float across = 0.74 * exp(-vAsym * vAsym * 2.65) + 0.32 * exp(-vAsym * vAsym * 1.02);
		highp float along  = pow(oneMinusU, 1.50) / pow(1.0 + 3.5 * u, 1.42);

		highp float mistOnset = smoothstep(0.20, 0.65, u);
		highp float softMist = vnoise(vec2(u * 0.85 + u_seed * 2.1, vAsym * 1.15 + u_seed * 5.7));
		highp float dustMod = mix(1.0, mix(0.94, 1.06, softMist), mistOnset * float(u_striaeStrength));

		density = float(headEnvelope * along * edgeMask * across * dustMod);
		mediump vec3 innerTint = mix(vec3(1.00, 0.98, 0.91), vec3(1.00, 0.94, 0.80), u_warmth);
		mediump vec3 midTint   = mix(vec3(0.96, 0.90, 0.79), vec3(1.00, 0.84, 0.62), u_warmth);
		mediump vec3 outerTint = mix(vec3(0.82, 0.79, 0.74), vec3(0.88, 0.76, 0.66), u_warmth);
		tint = mix(innerTint, midTint, float(smoothstep(0.05, 0.45, u)));
		tint = mix(tint, outerTint, float(smoothstep(0.45, 0.92, u)));
	}

	mediump vec3 outRgb = v_color * tint * density;
	// 1-LSB screen-space dithering eliminates 8-bit framebuffer contour banding on long faint tails
	highp float dither = (hash12(gl_FragCoord.xy) - 0.5) / 255.0;
	outRgb = max(vec3(0.0), outRgb + vec3(float(dither)) * smoothstep(0.0, 0.015, density));
	FRAG_COLOR = vec4(outRgb, 0.0);
}
)";

	const QByteArray comaFragSrc =
		StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) +
		noiseHelper +
		R"(
VARYING highp vec2 v_uv;
VARYING mediump vec3 v_color;
uniform highp vec2 u_sunDir2D;
uniform highp float u_seed;
uniform mediump float u_nucleusSuppress;
uniform mediump float u_greenWeight;
void main(void)
{
	highp float r = length(v_uv);
	if (r >= 0.98)
		discard;

	// Strictly smooth radial envelope reaching zero well inside the quad (never visible box edges)
	highp float outerMask = smoothstep(0.96, 0.55, r);

	// Gentle smooth parabolic bow-shock shift toward the Sun (C-infinity smooth, zero crease)
	highp vec2 shifted = v_uv + u_sunDir2D * (0.065 * (1.0 - r * r));
	highp float rs = length(shifted);

	// 1. Crisp warm creamy-white central condensation (pseudo-nucleus)
	highp float pseudoNucleus = (exp(-r * r * 190.0) * 1.10 + exp(-r * r * 30.0) * 0.48) * float(1.0 - u_nucleusSuppress);
	// 2. Broad smooth inner coma overlapping seamlessly into the tail root
	highp float innerComa = exp(-rs * rs * 7.8);
	// 3. Soft gossamer outer halo
	highp float outerHalo = exp(-rs * rs * 3.0) * 0.44;

	mediump vec3 innerColor = mix(vec3(0.98, 0.95, 0.88), vec3(0.32, 0.88, 0.74), u_greenWeight);
	mediump vec3 outerColor = mix(vec3(0.68, 0.78, 0.92), vec3(0.36, 0.78, 0.82), u_greenWeight);

	mediump vec3 rgb = vec3(1.00, 0.98, 0.92) * float(pseudoNucleus)
	                 + innerColor * float(innerComa) * 0.58
	                 + outerColor * float(outerHalo) * 0.32;

	mediump vec3 outRgb = rgb * v_color * float(outerMask);
	highp float dither = (hash12(gl_FragCoord.xy) - 0.5) / 255.0;
	outRgb = max(vec3(0.0), outRgb + vec3(float(dither)) * smoothstep(0.0, 0.02, float(innerComa + outerHalo)));
	FRAG_COLOR = vec4(outRgb, 0.0);
}
)";

	auto buildProgram = [&](const QByteArray& fragSrc, const char* label) -> std::unique_ptr<QOpenGLShaderProgram>
	{
		std::unique_ptr<QOpenGLShaderProgram> prog(new QOpenGLShaderProgram);
		if (!prog->addShaderFromSourceCode(QOpenGLShader::Vertex, vertSrc))
		{
			qWarning().noquote() << "Comet:" << label << "vertex shader error:\n" << prog->log();
			return nullptr;
		}
		if (!prog->addShaderFromSourceCode(QOpenGLShader::Fragment, fragSrc))
		{
			qWarning().noquote() << "Comet:" << label << "fragment shader error:\n" << prog->log();
			return nullptr;
		}
		prog->bindAttributeLocation("a_pos", 0);
		prog->bindAttributeLocation("a_uv", 1);
		prog->bindAttributeLocation("a_color", 2);
		if (!StelPainter::linkProg(prog.get(), label))
			return nullptr;
		return prog;
	};

	tailShaderProgram = buildProgram(tailFragSrc, "Comet tail shader");
	comaShaderProgram = buildProgram(comaFragSrc, "Comet coma shader");
	if (!tailShaderProgram || !comaShaderProgram)
	{
		deinitShader();
		shaderInitFailed = true;
		return false;
	}

	s_tailShaderVars.projectionMatrix = tailShaderProgram->uniformLocation("u_projectionMatrix");
	s_tailShaderVars.isGas = tailShaderProgram->uniformLocation("u_isGas");
	s_tailShaderVars.seed = tailShaderProgram->uniformLocation("u_seed");
	s_tailShaderVars.phase = tailShaderProgram->uniformLocation("u_phase");
	s_tailShaderVars.headU = tailShaderProgram->uniformLocation("u_headU");
	s_tailShaderVars.striaeStrength = tailShaderProgram->uniformLocation("u_striaeStrength");
	s_tailShaderVars.warmth = tailShaderProgram->uniformLocation("u_warmth");

	s_comaShaderVars.projectionMatrix = comaShaderProgram->uniformLocation("u_projectionMatrix");
	s_comaShaderVars.sunDir2D = comaShaderProgram->uniformLocation("u_sunDir2D");
	s_comaShaderVars.seed = comaShaderProgram->uniformLocation("u_seed");
	s_comaShaderVars.nucleusSuppress = comaShaderProgram->uniformLocation("u_nucleusSuppress");
	s_comaShaderVars.greenWeight = comaShaderProgram->uniformLocation("u_greenWeight");

	cometVBO.reset(new QOpenGLBuffer(QOpenGLBuffer::VertexBuffer));
	if (!cometVBO->create())
	{
		deinitShader();
		shaderInitFailed = true;
		return false;
	}
	cometVBO->setUsagePattern(QOpenGLBuffer::StreamDraw);
	cometVBO->bind();
	cometVBO->allocate(COMET_VBO_MAX_VERTS * static_cast<int>(sizeof(CometVertex)));

	cometVAO.reset(new QOpenGLVertexArrayObject);
	if (cometVAO->create())
	{
		cometVAO->bind();
		QOpenGLFunctions* gl = ctx->functions();
		gl->glEnableVertexAttribArray(0);
		gl->glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(CometVertex), reinterpret_cast<const void*>(offsetof(CometVertex, x)));
		gl->glEnableVertexAttribArray(1);
		gl->glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(CometVertex), reinterpret_cast<const void*>(offsetof(CometVertex, u)));
		gl->glEnableVertexAttribArray(2);
		gl->glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(CometVertex), reinterpret_cast<const void*>(offsetof(CometVertex, r)));
		cometVAO->release();
	}
	cometVBO->release();
	return true;
}

void Comet::drawProceduralTail(StelCore* core, const StelProjectorP& prj, bool gas,
                               const Vec3d& cometEcl, const Vec3d& observerEcl,
                               const Vec3d& antiSun, const Vec3d& trailDir, double velNorm,
                               double comaRadAU, double tailLenAU, float baseIntensity, float twilightFade,
                               float fanWidthScale, float curvatureScale, float striaeStrength, float warmth)
{
	if (tailLenAU <= 1e-7 || baseIntensity * twilightFade <= 0.002f)
		return;

	constexpr int N = COMET_RIBBON_SEGMENTS;
	Vec3d centers[N + 1];
	double uVals[N + 1];
	double halfWidths[N + 1];

	const double bend = qBound(0.14, (0.16 + 7.2 * velNorm) * static_cast<double>(curvatureScale), 0.78);
	const double widthFact = static_cast<double>(qBound(0.55f, dustTailWidthFactor, 2.2f)) * static_cast<double>(qBound(0.35f, fanWidthScale, 1.85f));
	// Start slightly sunward of the nucleus so the parabolic tail root glows right through the core (zero gap)
	const double headStartOffset = -0.38 * comaRadAU;

	for (int i = 0; i <= N; ++i)
	{
		const double s = static_cast<double>(i) / static_cast<double>(N);
		// Dense near head, smoothly graded along full tail without abrupt steps
		const double u = 0.25 * s + 0.75 * s * s;
		uVals[i] = u;

		if (gas)
		{
			// Straight, gently widening translucent blue ion fan (never a thin pencil laser)
			const double lag = 0.020 * u;
			Vec3d dir = antiSun + trailDir * lag;
			dir.normalize();
			centers[i] = antiSun * (headStartOffset * (1.0 - u)) + dir * (tailLenAU * u);
			halfWidths[i] = comaRadAU * (0.62 + 1.15 * std::sqrt(u))
			              + tailLenAU * (0.042 * std::pow(u, 0.82) + 0.032 * u);
		}
		else
		{
			// Smooth Finson-Probstein parabolic head separating cleanly into a broad sweeping dust fan
			const double arcX = u - 0.14 * bend * bend * u * u * u;
			const double arcY = (0.28 * u + 0.72 * u * u) * bend;
			centers[i] = antiSun * (headStartOffset * (1.0 - u) + tailLenAU * arcX)
			           + trailDir * (tailLenAU * arcY);
			halfWidths[i] = comaRadAU * (0.76 + 1.85 * std::sqrt(u))
			              + tailLenAU * (0.068 * std::pow(u, 0.74) + 0.098 * std::pow(u, 1.35)) * widthFact;
		}
	}

	const bool withAtmosphere = core->getSkyDrawer()->getFlagHasAtmosphere();
	const Extinction extinction = withAtmosphere ? core->getSkyDrawer()->getVisualExtinction() : Extinction();

	const double vpW = static_cast<double>(prj->getViewportWidth());
	const double vpH = static_cast<double>(prj->getViewportHeight());
	const double dpr = std::max(1.0, static_cast<double>(core->getCurrentStelProjectorParams().devicePixelsPerPixel));
	const double minRibbonPx = (gas ? 2.4 : 3.2) * dpr;

	struct Section
	{
		bool valid = false;
		Vec3d pL;
		Vec3d pC;
		Vec3d pR;
		float lx = 0.0f, ly = 0.0f;
		float cx = 0.0f, cy = 0.0f;
		float rx = 0.0f, ry = 0.0f;
		float u = 0.0f;
		float intensity = 0.0f;
	};
	Section secs[N + 1];

	Vec3d prevSide(0.0, 0.0, 0.0);
	bool hasPrevSide = false;

	for (int i = 0; i <= N; ++i)
	{
		Vec3d tangent = (i == 0) ? (centers[1] - centers[0])
		              : (i == N) ? (centers[N] - centers[N - 1])
		              : (centers[i + 1] - centers[i - 1]);
		if (tangent.normSquared() < 1e-18)
			tangent = antiSun;
		else
			tangent.normalize();

		Vec3d viewVec = (cometEcl + centers[i]) - observerEcl;
		Vec3d side = tangent ^ viewVec;
		if (side.normSquared() < 1e-14)
		{
			side = trailDir - tangent * trailDir.dot(tangent);
			if (side.normSquared() < 1e-14)
			{
				const Vec3d up = (std::fabs(tangent[2]) < 0.9) ? Vec3d(0.0, 0.0, 1.0) : Vec3d(1.0, 0.0, 0.0);
				side = tangent ^ up;
			}
		}
		side.normalize();

		if (!hasPrevSide)
		{
			if (side.dot(trailDir) < 0.0)
				side = -side;
			hasPrevSide = true;
		}
		else if (side.dot(prevSide) < 0.0)
		{
			side = -side;
		}
		prevSide = side;

		const Vec3d pC = centers[i];
		const Vec3d pL = pC - side * halfWidths[i];
		const Vec3d pR = pC + side * halfWidths[i];

		Vec3d winL, winC, winR;
		const bool okL = prj->project(pL, winL);
		const bool okC = prj->project(pC, winC);
		const bool okR = prj->project(pR, winR);
		if (!okL || !okC || !okR || !std::isfinite(winL[0]) || !std::isfinite(winL[1]) ||
		    !std::isfinite(winC[0]) || !std::isfinite(winC[1]) || !std::isfinite(winR[0]) || !std::isfinite(winR[1]))
			continue;
		if (prj->intersectViewportDiscontinuity(pL, pC) || prj->intersectViewportDiscontinuity(pC, pR))
			continue;

		double dx = winR[0] - winL[0];
		double dy = winR[1] - winL[1];
		double distSq = dx * dx + dy * dy;

		// Analytic subpixel anti-aliasing: widen subpixel ribbons and conserve energy
		double aaEnergy = 1.0;
		const double widthPx = std::sqrt(distSq);
		if (widthPx < minRibbonPx)
		{
			const double midX = winC[0];
			const double midY = winC[1];
			double nx = 0.0, ny = 1.0;
			if (widthPx > 1e-4)
			{
				nx = dx / widthPx;
				ny = dy / widthPx;
			}
			const double halfMin = 0.5 * minRibbonPx;
			winL[0] = midX - nx * halfMin;
			winL[1] = midY - ny * halfMin;
			winR[0] = midX + nx * halfMin;
			winR[1] = midY + ny * halfMin;
			aaEnergy = qBound(0.18, widthPx / minRibbonPx, 1.0);
		}

		float extFactor = 1.0f;
		if (withAtmosphere)
		{
			Vec3d vertAltAz = core->heliocentricEclipticToAltAz(cometEcl + centers[i], StelCore::RefractionOn);
			if (vertAltAz.normSquared() > 1e-12)
			{
				vertAltAz.normalize();
				float oneMag = 0.0f;
				extinction.forward(vertAltAz, &oneMag);
				extFactor = std::pow(0.4f, oneMag);
			}
		}

		secs[i].valid = true;
		secs[i].pL = pL;
		secs[i].pC = pC;
		secs[i].pR = pR;
		secs[i].lx = static_cast<float>(winL[0]);
		secs[i].ly = static_cast<float>(winL[1]);
		secs[i].cx = static_cast<float>(winC[0]);
		secs[i].cy = static_cast<float>(winC[1]);
		secs[i].rx = static_cast<float>(winR[0]);
		secs[i].ry = static_cast<float>(winR[1]);
		secs[i].u = static_cast<float>(uVals[i]);
		secs[i].intensity = baseIntensity * twilightFade * extFactor * static_cast<float>(aaEnergy);
	}

	std::vector<CometVertex> verts;
	verts.reserve(N * 12);

	const double vpLeft = static_cast<double>(prj->getViewportPosX());
	const double vpBottom = static_cast<double>(prj->getViewportPosY());
	const double vpRight = vpLeft + vpW;
	const double vpTop = vpBottom + vpH;

	for (int i = 0; i < N; ++i)
	{
		const Section& a = secs[i];
		const Section& b = secs[i + 1];
		if (!a.valid || !b.valid)
			continue;

		if (prj->intersectViewportDiscontinuity(a.pL, b.pL) ||
		    prj->intersectViewportDiscontinuity(a.pC, b.pC) ||
		    prj->intersectViewportDiscontinuity(a.pR, b.pR))
			continue;

		const double minX = std::min({static_cast<double>(a.lx), static_cast<double>(a.cx), static_cast<double>(a.rx),
		                              static_cast<double>(b.lx), static_cast<double>(b.cx), static_cast<double>(b.rx)});
		const double maxX = std::max({static_cast<double>(a.lx), static_cast<double>(a.cx), static_cast<double>(a.rx),
		                              static_cast<double>(b.lx), static_cast<double>(b.cx), static_cast<double>(b.rx)});
		const double minY = std::min({static_cast<double>(a.ly), static_cast<double>(a.cy), static_cast<double>(a.ry),
		                              static_cast<double>(b.ly), static_cast<double>(b.cy), static_cast<double>(b.ry)});
		const double maxY = std::max({static_cast<double>(a.ly), static_cast<double>(a.cy), static_cast<double>(a.ry),
		                              static_cast<double>(b.ly), static_cast<double>(b.cy), static_cast<double>(b.ry)});
		if (maxX < vpLeft || minX > vpRight || maxY < vpBottom || minY > vpTop)
			continue;

		// Split each segment along the exact v=0 centerline spine so tapered trapezoids
		// never suffer affine diagonal skewing or beaded knots along the bright tail core.
		const CometVertex aL{a.lx, a.ly, a.u, -1.0f, a.intensity, a.intensity, a.intensity};
		const CometVertex aC{a.cx, a.cy, a.u,  0.0f, a.intensity, a.intensity, a.intensity};
		const CometVertex aR{a.rx, a.ry, a.u,  1.0f, a.intensity, a.intensity, a.intensity};
		const CometVertex bL{b.lx, b.ly, b.u, -1.0f, b.intensity, b.intensity, b.intensity};
		const CometVertex bC{b.cx, b.cy, b.u,  0.0f, b.intensity, b.intensity, b.intensity};
		const CometVertex bR{b.rx, b.ry, b.u,  1.0f, b.intensity, b.intensity, b.intensity};

		// Left half (v: -1 .. 0)
		verts.push_back(aL);
		verts.push_back(aC);
		verts.push_back(bL);
		verts.push_back(bL);
		verts.push_back(aC);
		verts.push_back(bC);

		// Right half (v: 0 .. +1)
		verts.push_back(aC);
		verts.push_back(aR);
		verts.push_back(bC);
		verts.push_back(bC);
		verts.push_back(aR);
		verts.push_back(bR);
	}

	if (verts.empty())
		return;

	StelPainter sPainter(prj);
	sPainter.setBlending(true, GL_ONE, GL_ONE);
	sPainter.setCullFace(false);
	sPainter.setDepthTest(false);

	const Mat4f& m = prj->getProjectionMatrix();
	const QMatrix4x4 qMat(m[0], m[4], m[8], m[12],
	                      m[1], m[5], m[9], m[13],
	                      m[2], m[6], m[10], m[14],
	                      m[3], m[7], m[11], m[15]);

	// Gentle simulation-time solar-wind phase progression along ion rays
	const float phase = static_cast<float>(std::fmod(core->getJDE() * 0.20, 100.0));
	const float headU = qBound(0.004f, static_cast<float>(comaRadAU / std::max(tailLenAU, 1e-6)), 0.22f);

	QOpenGLFunctions* gl = QOpenGLContext::currentContext()->functions();
	const bool useVAO = (cometVAO && cometVAO->isCreated());
	if (useVAO)
		cometVAO->bind();

	cometVBO->bind();
	cometVBO->write(0, verts.data(), static_cast<int>(verts.size() * sizeof(CometVertex)));
	if (!useVAO)
	{
		gl->glEnableVertexAttribArray(0);
		gl->glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(CometVertex), reinterpret_cast<const void*>(offsetof(CometVertex, x)));
		gl->glEnableVertexAttribArray(1);
		gl->glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(CometVertex), reinterpret_cast<const void*>(offsetof(CometVertex, u)));
		gl->glEnableVertexAttribArray(2);
		gl->glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(CometVertex), reinterpret_cast<const void*>(offsetof(CometVertex, r)));
	}

	tailShaderProgram->bind();
	tailShaderProgram->setUniformValue(s_tailShaderVars.projectionMatrix, qMat);
	tailShaderProgram->setUniformValue(s_tailShaderVars.isGas, gas ? 1.0f : 0.0f);
	tailShaderProgram->setUniformValue(s_tailShaderVars.seed, renderSeed);
	tailShaderProgram->setUniformValue(s_tailShaderVars.phase, phase);
	tailShaderProgram->setUniformValue(s_tailShaderVars.headU, headU);
	tailShaderProgram->setUniformValue(s_tailShaderVars.striaeStrength, striaeStrength);
	tailShaderProgram->setUniformValue(s_tailShaderVars.warmth, warmth);

	gl->glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(verts.size()));

	tailShaderProgram->release();
	if (!useVAO)
	{
		gl->glDisableVertexAttribArray(0);
		gl->glDisableVertexAttribArray(1);
		gl->glDisableVertexAttribArray(2);
	}
	cometVBO->release();
	if (useVAO)
		cometVAO->release();

	sPainter.setBlending(false);
}

void Comet::drawProceduralComa(StelCore* core, const StelProjectorP& prj,
                               const Vec3d& cometEcl, const Vec3d& observerEcl,
                               const Vec3d& antiSun, double comaRadAU,
                               float vMagnitude, float screenRd, float twilightFade, float greenWeight)
{
	Vec3d winCenter;
	if (!prj->project(Vec3d(0.0, 0.0, 0.0), winCenter) || !std::isfinite(winCenter[0]) || !std::isfinite(winCenter[1]))
		return;

	const double distObs = std::max((cometEcl - observerEcl).norm(), 1e-5);
	const double comaRadRad = std::atan(comaRadAU / distObs);
	const double physComaPx = comaRadRad * static_cast<double>(prj->getPixelPerRadAtCenter());
	const double dpr = std::max(1.0, static_cast<double>(core->getCurrentStelProjectorParams().devicePixelsPerPixel));
	const double minComaPx = qBound(3.2, 9.5 - 0.55 * static_cast<double>(vMagnitude), 14.0) * dpr;
	const double maxComaPx = 0.28 * static_cast<double>(std::max(prj->getViewportWidth(), prj->getViewportHeight()));
	const double comaPx = qBound(minComaPx, physComaPx, maxComaPx);
	const double quadHalf = comaPx * 2.75;

	const double vpLeft = static_cast<double>(prj->getViewportPosX());
	const double vpBottom = static_cast<double>(prj->getViewportPosY());
	if (winCenter[0] + quadHalf < vpLeft || winCenter[0] - quadHalf > vpLeft + prj->getViewportWidth() ||
	    winCenter[1] + quadHalf < vpBottom || winCenter[1] - quadHalf > vpBottom + prj->getViewportHeight())
		return;

	// Compute projected 2D sunward direction for subtle coma bow-shock asymmetry
	QVector2D sunDir2D(0.0f, 1.0f);
	Vec3d winSun;
	if (prj->project(-antiSun * (comaRadAU * 0.5), winSun) && std::isfinite(winSun[0]) && std::isfinite(winSun[1]))
	{
		const float sx = static_cast<float>(winSun[0] - winCenter[0]);
		const float sy = static_cast<float>(winSun[1] - winCenter[1]);
		const float len = std::sqrt(sx * sx + sy * sy);
		if (len > 1e-3f)
			sunDir2D = QVector2D(sx / len, sy / len);
	}

	float extFactor = 1.0f;
	if (core->getSkyDrawer()->getFlagHasAtmosphere())
	{
		Vec3d vertAltAz = core->heliocentricEclipticToAltAz(cometEcl, StelCore::RefractionOn);
		if (vertAltAz.normSquared() > 1e-12)
		{
			vertAltAz.normalize();
			float oneMag = 0.0f;
			core->getSkyDrawer()->getVisualExtinction().forward(vertAltAz, &oneMag);
			extFactor = std::pow(0.4f, oneMag);
		}
	}

	static StelMovementMgr* mMgr = GETSTELMODULE(StelMovementMgr);
	const float fov = std::max(0.05f, static_cast<float>(mMgr->getCurrentFov()));
	const float faintBoostWeight = smoothStepF(3.0f, 8.5f, vMagnitude);
	const float zoomBoost = (fov < 45.0f)
		? qBound(0.0f, 2.3f * std::log2(45.0f / std::max(fov, 0.25f)), 6.5f) * faintBoostWeight
		: 0.0f;
	const float effMag = vMagnitude - zoomBoost;
	const float rawBright = std::pow(10.0f, -0.15f * (effMag - 1.2f));
	const float comaIntensity = (rawBright / (1.0f + 1.35f * rawBright)) * 0.76f * intensityFovScale * extFactor * twilightFade;
	if (comaIntensity <= 0.003f)
		return;

	const float cx = static_cast<float>(winCenter[0]);
	const float cy = static_cast<float>(winCenter[1]);
	const float h = static_cast<float>(quadHalf);

	const CometVertex verts[6] = {
		{cx - h, cy - h, -1.0f, -1.0f, comaIntensity, comaIntensity, comaIntensity},
		{cx + h, cy - h,  1.0f, -1.0f, comaIntensity, comaIntensity, comaIntensity},
		{cx - h, cy + h, -1.0f,  1.0f, comaIntensity, comaIntensity, comaIntensity},
		{cx - h, cy + h, -1.0f,  1.0f, comaIntensity, comaIntensity, comaIntensity},
		{cx + h, cy - h,  1.0f, -1.0f, comaIntensity, comaIntensity, comaIntensity},
		{cx + h, cy + h,  1.0f,  1.0f, comaIntensity, comaIntensity, comaIntensity},
	};

	StelPainter sPainter(prj);
	sPainter.setBlending(true, GL_ONE, GL_ONE);
	sPainter.setCullFace(false);
	sPainter.setDepthTest(false);

	const Mat4f& m = prj->getProjectionMatrix();
	const QMatrix4x4 qMat(m[0], m[4], m[8], m[12],
	                      m[1], m[5], m[9], m[13],
	                      m[2], m[6], m[10], m[14],
	                      m[3], m[7], m[11], m[15]);

	const float nucleusSuppress = smoothStepF(3.0f, 14.0f, screenRd);

	QOpenGLFunctions* gl = QOpenGLContext::currentContext()->functions();
	const bool useVAO = (cometVAO && cometVAO->isCreated());
	if (useVAO)
		cometVAO->bind();

	cometVBO->bind();
	cometVBO->write(0, verts, static_cast<int>(sizeof(verts)));
	if (!useVAO)
	{
		gl->glEnableVertexAttribArray(0);
		gl->glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(CometVertex), reinterpret_cast<const void*>(offsetof(CometVertex, x)));
		gl->glEnableVertexAttribArray(1);
		gl->glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(CometVertex), reinterpret_cast<const void*>(offsetof(CometVertex, u)));
		gl->glEnableVertexAttribArray(2);
		gl->glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(CometVertex), reinterpret_cast<const void*>(offsetof(CometVertex, r)));
	}

	comaShaderProgram->bind();
	comaShaderProgram->setUniformValue(s_comaShaderVars.projectionMatrix, qMat);
	comaShaderProgram->setUniformValue(s_comaShaderVars.sunDir2D, sunDir2D);
	comaShaderProgram->setUniformValue(s_comaShaderVars.seed, renderSeed);
	comaShaderProgram->setUniformValue(s_comaShaderVars.nucleusSuppress, nucleusSuppress);
	comaShaderProgram->setUniformValue(s_comaShaderVars.greenWeight, greenWeight);

	gl->glDrawArrays(GL_TRIANGLES, 0, 6);

	comaShaderProgram->release();
	if (!useVAO)
	{
		gl->glDisableVertexAttribArray(0);
		gl->glDisableVertexAttribArray(1);
		gl->glDisableVertexAttribArray(2);
	}
	cometVBO->release();
	if (useVAO)
		cometVAO->release();

	sPainter.setBlending(false);
}

void Comet::drawTail(StelCore* core, StelProjector::ModelViewTranformP transfo, bool gas)
{	
	StelPainter sPainter(core->getProjection(transfo));
	sPainter.setBlending(true, GL_ONE, GL_ONE);

	tailTexture->bind();

	if (gas) {
		StelVertexArray vaGas(static_cast<const QVector<Vec3d> >(gastailVertexArr), StelVertexArray::Triangles,
				      static_cast<const QVector<Vec2f> >(tailTexCoordArr), tailIndices, static_cast<const QVector<Vec3f> >(gastailColorArr));
		sPainter.drawStelVertexArray(vaGas, true);

	} else {
		StelVertexArray vaDust(static_cast<const QVector<Vec3d> >(dusttailVertexArr), StelVertexArray::Triangles,
				      static_cast<const QVector<Vec2f> >(tailTexCoordArr), tailIndices, static_cast<const QVector<Vec3f> >(dusttailColorArr));
		sPainter.drawStelVertexArray(vaDust, true);
	}
	sPainter.setBlending(false);
}

void Comet::drawComa(StelCore* core, StelProjector::ModelViewTranformP transfo)
{
	// Find rotation matrix from 0/0/1 to viewdirection! crossproduct for axis (normal vector), dotproduct for angle.
	Vec3d eclposNrm=eclipticPos+aberrationPush - core->getObserverHeliocentricEclipticPos()  ; eclposNrm.normalize();
	Mat4d comarot=Mat4d::rotation(Vec3d(0.0, 0.0, 1.0)^(eclposNrm), std::acos(Vec3d(0.0, 0.0, 1.0).dot(eclposNrm)) );
	StelProjector::ModelViewTranformP transfo2 = transfo->clone();
	transfo2->combine(comarot);
	StelPainter sPainter(core->getProjection(transfo2));

	sPainter.setBlending(true, GL_ONE, GL_ONE);

	StelToneReproducer* eye = core->getToneReproducer();
	float lum = core->getSkyDrawer()->surfaceBrightnessToLuminance(getVMagnitudeWithVisualExtinction(core)+11.0f); // How to calibrate?
	// Get the luminance scaled between 0 and 1
	const float aLum =eye->adaptLuminanceScaled(lum);
	const float magFactor=qBound(0.25f*intensityFovScale, aLum*intensityFovScale, 2.0f);
	comaTexture->bind();
	sPainter.setColor(0.3f*magFactor,0.7f*magFactor,magFactor);
	StelVertexArray vaComa(static_cast<const QVector<Vec3d> >(comaVertexArr), StelVertexArray::Triangles, static_cast<const QVector<Vec2f> >(comaTexCoordArr));
	sPainter.drawStelVertexArray(vaComa, true);
	sPainter.setBlending(false);
}

// Formula found at http://www.projectpluto.com/update7b.htm#comet_tail_formula
Vec2f Comet::getComaDiameterAndTailLengthAU() const
{
	const float r = static_cast<float>(getHeliocentricEclipticPos().norm());
	const float mhelio = absoluteMagnitude + slopeParameter * log10(r);
	const float Do = powf(10.0f, ((-0.0033f*mhelio - 0.07f) * mhelio + 3.25f));
	const float common = 1.0f - powf(10.0f, (-2.0f*r));
	const float D = Do * common * (1.0f - powf(10.0f, -r)) * (1000.0f*AU_KMf);
	const float Lo = powf(10.0f, ((-0.0075f*mhelio - 0.19f) * mhelio + 2.1f));
	const float L = Lo*(1.0f-powf(10.0f, -4.0f*r)) * common * (1e6f*AU_KMf);
	return Vec2f(D, L);
}

void Comet::computeComa(const float diameter)
{
	StelPainter::computeFanDisk(0.5f*diameter, 3, 3, comaVertexArr, comaTexCoordArr);
}

//! create parabola shell to represent a tail. Designed for slices=16, stacks=16, but should work with other sizes as well.
//! (Maybe slices must be an even number.)
// Parabola equation: z=x²/2p.
// xOffset for the dust tail, this may introduce a bend. Units are x per sqrt(z).
void Comet::computeParabola(const float parameter, const float radius, const float zshift,
						  QVector<Vec3d>& vertexArr, QVector<Vec2f>& texCoordArr,
						  QVector<unsigned short> &indices, const float xOffset)
{
	// keep the array and replace contents. However, using replace() is only slightly faster.
	if (vertexArr.length() < static_cast<int>(((COMET_TAIL_SLICES*COMET_TAIL_STACKS+1))))
		vertexArr.resize((COMET_TAIL_SLICES*COMET_TAIL_STACKS+1));
	if (createTailIndices) indices.clear();
	if (createTailTextureCoords) texCoordArr.clear();
	// The parabola has triangular faces with vertices on two circles that are rotated against each other. 
	float xa[2*COMET_TAIL_SLICES];
	float ya[2*COMET_TAIL_SLICES];
	float x, y, z;
	
	// fill xa, ya with sin/cosines. TBD: make more efficient with index mirroring etc.
	float da=M_PIf/COMET_TAIL_SLICES; // full circle/2slices
	for (unsigned short int i=0; i<2*COMET_TAIL_SLICES; ++i){
		xa[i]=-sin(i*da);
		ya[i]=cos(i*da);
	}
	
	vertexArr.replace(0, Vec3d(0.0, 0.0, static_cast<double>(zshift)));
	int vertexArrIndex=1;
	if (createTailTextureCoords) texCoordArr << Vec2f(0.5f, 0.5f);
	// define the indices lying on circles, starting at 1: odd rings have 1/slices+1/2slices, even-numbered rings straight 1/slices
	// inner ring#1
	for (unsigned short int ring=1; ring<=COMET_TAIL_STACKS; ++ring){
		z=ring*radius/COMET_TAIL_STACKS; z=z*z/(2*parameter) + zshift;
		const float xShift= xOffset*z*z;
		for (unsigned short int i=ring & 1; i<2*COMET_TAIL_SLICES; i+=2) { // i.e., ring1 has shifted vertices, ring2 has even ones.
			x=xa[i]*radius*ring/COMET_TAIL_STACKS;
			y=ya[i]*radius*ring/COMET_TAIL_STACKS;
			vertexArr.replace(vertexArrIndex++, Vec3d(static_cast<double>(x+xShift), static_cast<double>(y), static_cast<double>(z)));
			if (createTailTextureCoords) texCoordArr << Vec2f(0.5f+ 0.5f*x/radius, 0.5f+0.5f*y/radius);
		}
	}
	// now link the faces with indices.
	if (createTailIndices)
	{
		for (unsigned short i=1; i<COMET_TAIL_SLICES; ++i) indices << 0 << i << i+1;
		indices << 0 << COMET_TAIL_SLICES << 1; // close inner fan.
		// The other slices are a repeating pattern of 2 possibilities. Index @ring always is on the inner ring (slices-agon)
		for (unsigned short ring=1; ring<COMET_TAIL_STACKS; ring+=2) { // odd rings
			const unsigned short int first=(ring-1)*COMET_TAIL_SLICES+1;
			for (unsigned short int i=0; i<COMET_TAIL_SLICES-1; ++i){
				indices << first+i << first+COMET_TAIL_SLICES+i << first+COMET_TAIL_SLICES+1+i;
				indices << first+i << first+COMET_TAIL_SLICES+1+i << first+1+i;
			}
			// closing slice: mesh with other indices...
			indices << ring*COMET_TAIL_SLICES << (ring+1)*COMET_TAIL_SLICES << ring*COMET_TAIL_SLICES+1;
			indices << ring*COMET_TAIL_SLICES << ring*COMET_TAIL_SLICES+1 << first;
		}

		for (unsigned short int ring=2; ring<COMET_TAIL_STACKS; ring+=2) { // even rings: different sequence.
			const unsigned short int first=(ring-1)*COMET_TAIL_SLICES+1;
			for (unsigned short int i=0; i<COMET_TAIL_SLICES-1; ++i){
				indices << first+i << first+COMET_TAIL_SLICES+i << first+1+i;
				indices << first+1+i << first+COMET_TAIL_SLICES+i << first+COMET_TAIL_SLICES+1+i;
			}
			// closing slice: mesh with other indices...
			indices << ring*COMET_TAIL_SLICES << (ring+1)*COMET_TAIL_SLICES << first;
			indices << first << (ring+1)*COMET_TAIL_SLICES << ring*COMET_TAIL_SLICES+1;
		}
	}
	createTailIndices=false;
	createTailTextureCoords=false;
}

void Comet::setIAUDesignation(const QString& designation)
{
	static const QRegularExpression periodicDesignationPattern("^(\\d+)P/");
	static const QRegularExpression periodicCometPattern("^P/([\\w\\s]+)$");
	QRegularExpressionMatch matchPeriodicNumber = periodicDesignationPattern.match(englishName);
	QRegularExpressionMatch matchPeriodicComet  = periodicCometPattern.match(designation);
	if (matchPeriodicNumber.hasMatch() && matchPeriodicComet.hasMatch())
	{
		// combined designation for numbered periodic comets - 1P/1982 U1 or 146P/1984 W1
		iauDesignation = QString("%1P/%2").arg(matchPeriodicNumber.captured(1), matchPeriodicComet.captured(1));
	}
	else
		iauDesignation = designation;
}

void Comet::setExtraDesignations(QStringList codes)
{
	extraDesignations = codes;
	for (const auto& c : std::as_const(codes))
	{
		extraDesignationsHtml << renderDiscoveryDesignationHtml(c);
	}
}

QString Comet::renderDiscoveryDesignationHtml(const QString &plainTextName)
{
	static const QRegularExpression discoveryDesignationPattern("^(\\d{4}[a-z]{1})(\\d+)$");
	QRegularExpressionMatch match=discoveryDesignationPattern.match(plainTextName);
	if (match.hasMatch())
	{
		QString main = match.captured(1);
		QString suffix = match.captured(2);
		return (QString("%1<sub>%2</sub>").arg(main, suffix));
	}
	else
		return plainTextName;
}
