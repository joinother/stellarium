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
#include <QVector4D>
#include <algorithm>
#include <cmath>
#include <vector>

// for legacy fallback tail shape
#define COMET_TAIL_SLICES 16u // segments around the perimeter
#define COMET_TAIL_STACKS 16u // cuts along the rotational axis

namespace
{
struct CometQuadVertex
{
	float x, y;
};

struct CometShaderVars
{
	int projectionMatrix = -1;
	int headPos = -1;
	int comaRadPx = -1;
	int comaIntensity = -1;
	int nucleusSuppress = -1;
	int greenWeight = -1;
	int gasDir = -1;
	int gasLenPx = -1;
	int gasWidthPx = -1;
	int gasIntensity = -1;
	int ionRayStrength = -1;
	int dustIntensity = -1;
	int dustWarmth = -1;
	int dustRibbonStrength = -1;
	int striaeStrength = -1;
	int synA = -1;
	int synM = -1;
	int synB = -1;
	int synMeta = -1;
	int synNorm = -1;
	int seed = -1;
	int phase = -1;
	int tipExtRatio = -1;
};

CometShaderVars s_cometShaderVars;

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

// Symplectic Velocity Verlet integration of a cometary dust grain under reduced solar gravity mu_eff = mu_sun * (1 - beta).
Vec3d integrateDustVerlet(const Vec3d& p0, const Vec3d& v0, double tauDays, double beta, int steps)
{
	constexpr double kMuSun = 0.01720209895 * 0.01720209895; // AU^3 / day^2
	const double muEff = kMuSun * (1.0 - beta);
	const double dt = tauDays / static_cast<double>(steps);
	const double halfDt = 0.5 * dt;
	const double halfDt2 = 0.5 * dt * dt;

	double x = p0[0], y = p0[1], z = p0[2];
	double vx = v0[0], vy = v0[1], vz = v0[2];
	double r2 = std::max(x * x + y * y + z * z, 1e-8);
	double c = -muEff / (r2 * std::sqrt(r2));
	double ax = x * c, ay = y * c, az = z * c;

	for (int s = 0; s < steps; ++s)
	{
		x += vx * dt + ax * halfDt2;
		y += vy * dt + ay * halfDt2;
		z += vz * dt + az * halfDt2;
		r2 = std::max(x * x + y * y + z * z, 1e-8);
		c = -muEff / (r2 * std::sqrt(r2));
		const double ax2 = x * c;
		const double ay2 = y * c;
		const double az2 = z * c;
		vx += (ax + ax2) * halfDt;
		vy += (ay + ay2) * halfDt;
		vz += (az + az2) * halfDt;
		ax = ax2;
		ay = ay2;
		az = az2;
	}
	return Vec3d(x, y, z);
}
}

// These are to avoid having index arrays for each comet when all are equal.
bool Comet::createTailIndices=true;
bool Comet::createTailTextureCoords=true;
StelTextureSP Comet::comaTexture;
StelTextureSP Comet::tailTexture;
QVector<Vec2f> Comet::tailTexCoordArr; // computed only once for all Comets.
QVector<unsigned short> Comet::tailIndices; // computed only once for all Comets.
std::unique_ptr<QOpenGLShaderProgram> Comet::cometShaderProgram;
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
	  renderSeed(hashCometNameSeed(englishName)),
	  lastSynchroneJDE(-1e12),
	  lastSynchroneStriae(-1.0f)
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
			Vec3d orbitNormal = cometEcl ^ vel;
			float faceOn = 0.65f;
			if (orbitNormal.normSquared() > 1e-14)
			{
				orbitNormal.normalize();
				faceOn = static_cast<float>(std::fabs(orbitNormal.dot(viewDir)));
			}
			// Edge-on plane crossings concentrate dust column density along the line of sight.
			const float edgeOnFactor = 1.0f - smoothStepF(0.06f, 0.36f, faceOn);
			const float planeBrightBoost = 1.0f + 0.42f * edgeOnFactor;

			// 4. Comet taxonomy archetype from (q, e, H, dust_brightnessfactor, slope):
			//    - Sunskirter / Great Dust Fan (q < 0.35, db >= 1.0): West, McNaught, Ikeya-Seki, NEOWISE
			//    - Twin-Tail Great Comet (e >= 0.95 & H < 2.5): Hale-Bopp
			//    - Ion-Dominant / Gas-Rich Streamer (low db < 0.9 or volatile-rich): Hyakutake, PANSTARRS, SWAN
			//    - Green C2 / Halley-type (e >= 0.85 & H >= 2.5): 1P/Halley, C/2022 E3 ZTF
			//    - Aged Short-Period (e < 0.80): 10P/Tempel, 161P/Hartley-IRAS, 67P, 2P/Encke
			const float isLongPeriod = smoothStepF(0.75f, 0.95f, static_cast<float>(ecc));
			const float isIntrinsicBright = 1.0f - smoothStepF(1.5f, 6.5f, absoluteMagnitude);
			const float gasDominant = (1.0f - smoothStepF(0.45f, 0.98f, dustTailBrightnessFactor))
			                        * (0.65f + 0.35f * isLongPeriod);
			const float sunskirterScore = closeSunStress * (0.45f + 0.55f * std::max(instantHeat, postSurge))
			                            * (1.0f - 0.75f * gasDominant);

			const float dustFactor = qBound(0.16f, dustTailBrightnessFactor / 1.25f, 1.55f);
			const float dustClassScale = (0.58f + 0.52f * isIntrinsicBright + 0.72f * sunskirterScore)
			                           * (preBuild + 0.48f * postSurge * (0.4f + 0.6f * closeSunStress))
			                           * (1.0f - 0.76f * gasDominant)
			                           * (0.55f + 0.45f * isLongPeriod);
			const float gasClassScale  = (0.38f + 0.82f * isLongPeriod + 0.52f * gasDominant)
			                           * (1.0f - 0.92f * sunskirterScore);
			const float ionRayStrength = qBound(0.38f,
				0.48f + 0.28f * isLongPeriod + 0.24f * gasDominant, 0.92f);
			const float dustRibbonStrength = qBound(0.24f,
				(0.32f + 0.48f * sunskirterScore + 0.18f * postSurge * isLongPeriod * faceOn) * (1.0f - 0.45f * edgeOnFactor), 0.88f);
			// Post-perihelion Finson-Probstein synchrone striae curtain (McNaught, West, Ikeya-Seki, G3 ATLAS)
			const float striaeStrength = qBound(0.0f,
				sunskirterScore * (0.45f + 0.55f * std::max(postSurge, instantHeat)) * (1.0f - 0.35f * edgeOnFactor), 0.95f);
			const float dustWarmth = qBound(0.0f,
				0.28f + 0.46f * sunskirterScore + 0.28f * smoothStepF(100.0f, 150.0f, phaseDeg), 1.0f);
			const float greenComaWeight = qBound(0.10f,
				0.82f - 0.56f * isIntrinsicBright - 0.38f * sunskirterScore + 0.16f * gasDominant, 0.94f);

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

			const float comaZoomBoost = (fov < 45.0f)
				? qBound(0.0f, 2.3f * std::log2(45.0f / std::max(fov, 0.25f)), 6.5f) * faintBoostWeight
				: 0.0f;
			const float rawComaBright = std::pow(10.0f, -0.15f * ((vMagnitude - comaZoomBoost) - 1.2f));
			const float wideHeadCalm = 0.54f + 0.46f * (1.0f - smoothStepF(18.0f, 75.0f, fov));
			const float comaIntensity = (rawComaBright / (1.0f + 1.45f * rawComaBright)) * (0.48f + 0.24f * greenComaWeight) * wideHeadCalm * intensityFovScale;

			const double comaRadAU = 0.5 * std::max(static_cast<double>(tailFactors[0]), 2.5e-5);
			const bool showTail = (activity > 0.01f) && (tailVis * twilightFade > 0.004f) && (distObs > 1e-5);

			double gasLenAU = 0.0;
			float gasIntensity = 0.0f;
			float dustIntensity = 0.0f;

			if (showTail)
			{
				const double maxSpanAU = distObs * 1.65;
				const double baseGasLen = std::max(static_cast<double>(tailFactors[1]) * 1.28, comaRadAU * 12.0 * static_cast<double>(activity));
				gasLenAU = std::min(maxSpanAU, baseGasLen * static_cast<double>(gasClassScale));

				dustIntensity = qMin(0.88f,
					tailVis * dustFactor * (0.76f + 0.52f * dustClassScale) * forwardScatter * planeBrightBoost);
				gasIntensity = qMin(0.68f,
					tailVis * 0.56f * gasClassScale);
			}

			drawAnalyticalComet(core, tailPrj, cometEcl, observerEcl, antiSun,
			                    comaRadAU, gasLenAU, showTail,
			                    vMagnitude, static_cast<float>(screenRd),
			                    comaIntensity, gasIntensity, dustIntensity,
			                    twilightFade, dustWarmth, greenComaWeight,
			                    ionRayStrength, dustRibbonStrength,
			                    striaeStrength, isLongPeriod);
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
	cometShaderProgram.reset();
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
	if (cometShaderProgram && cometVBO && cometVBO->isCreated())
		return true;

	const QByteArray vertSrc =
		StelOpenGL::globalShaderPrefix(StelOpenGL::VERTEX_SHADER) +
		R"(
ATTRIBUTE highp vec2 a_pos;
uniform highp mat4 u_projectionMatrix;
VARYING highp vec2 v_screenPos;
void main(void)
{
	v_screenPos = a_pos;
	gl_Position = u_projectionMatrix * vec4(a_pos, 0.0, 1.0);
}
)";

	const QByteArray fragSrc =
		StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) +
		R"(
VARYING highp vec2 v_screenPos;

uniform highp vec2 u_headPos;
uniform highp float u_comaRadPx;
uniform mediump float u_comaIntensity;
uniform mediump float u_nucleusSuppress;
uniform mediump float u_greenWeight;

uniform highp vec2 u_gasDir;
uniform highp float u_gasLenPx;
uniform highp float u_gasWidthPx;
uniform mediump float u_gasIntensity;
uniform mediump float u_ionRayStrength;

uniform mediump float u_dustIntensity;
uniform mediump float u_dustWarmth;
uniform mediump float u_dustRibbonStrength;
uniform mediump float u_striaeStrength;
uniform highp vec2 u_synA[22];
uniform highp vec2 u_synM[22];
uniform highp vec2 u_synB[22];
uniform highp vec4 u_synMeta[22];
uniform highp vec2 u_synNorm[22];
uniform highp float u_seed;
uniform highp float u_phase;
uniform mediump float u_tipExtRatio;

highp float hash12(highp vec2 p)
{
	highp vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// C2-continuous quintic value noise for silky longitudinal dust & plasma ribbons (zero blocky edges)
highp float vnoise(highp vec2 p)
{
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	highp vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(
		mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void main(void)
{
	highp vec2 d = v_screenPos - u_headPos;
	highp float R = max(u_comaRadPx, 2.0);

	mediump vec3 totalRgb = vec3(0.0);
	highp float totalSignal = 0.0;

	// 1. Unified C-infinity analytical Coma & Pseudo-Nucleus (warm dusty ivory vs. vivid emerald-jade C2 Swan halo)
	if (u_comaIntensity > 0.0005)
	{
		highp float r2 = dot(d, d) / (R * R);
		if (r2 < 32.0)
		{
			// Subtle sunward bow-shock offset toward -u_gasDir (smooth, zero crease)
			highp vec2 dComa = d + (-u_gasDir) * (0.12 * R * exp(-r2 * 0.28));
			highp float rs2 = dot(dComa, dComa) / (R * R);

			highp float pseudoNucleus = (exp(-r2 * 22.0) * 0.72 + exp(-r2 * 5.2) * 0.30) * float(1.0 - u_nucleusSuppress);
			highp float innerComa = exp(-rs2 * mix(1.35, 0.92, float(u_greenWeight)));
			highp float outerHalo = exp(-rs2 * mix(0.40, 0.18, float(u_greenWeight))) * mix(0.24, 0.58, float(u_greenWeight));

			mediump vec3 innerColor = mix(vec3(0.99, 0.96, 0.89), vec3(0.05, 0.98, 0.56), u_greenWeight);
			mediump vec3 outerColor = mix(vec3(0.72, 0.80, 0.92), vec3(0.03, 0.86, 0.48), u_greenWeight);

			mediump vec3 comaRgb = vec3(1.00, 0.99, 0.95) * float(pseudoNucleus)
			                     + innerColor * float(innerComa) * mix(0.44, 0.68, u_greenWeight)
			                     + outerColor * float(outerHalo) * mix(0.22, 0.52, u_greenWeight);
			totalRgb += comaRgb * u_comaIntensity;
			totalSignal += pseudoNucleus + innerComa + outerHalo;
		}
	}

	// 2. Continuous 2D Finson-Probstein Synchrone Dust Sheet (22 Newtonian radiation-pressure synchrones)
	//    The 22 widely overlapping 3D synchrones define a seamless continuous (uAge, vBeta) coordinate field
	//    across the entire curved dust sheet, enabling infinite-resolution multi-scale aurora filaments
	//    on sunskirters (McNaught, West) and silky asymptotic mist dissolve with ZERO blunt capsule tips.
	if (u_dustIntensity > 0.0005)
	{
		highp float gRawSum  = 0.0;
		highp float gNormSum = 0.0;
		highp float uSum     = 0.0;
		highp float vSum     = 0.0;
		highp float vDenom   = 0.0;
		highp float qSum     = 0.0;

		for (int k = 0; k < 22; ++k)
		{
			highp vec4 meta = u_synMeta[k]; // x=qNorm, y=wInnerPx, z=wOuterPx, w=ageFrac (<0 invalid)
			if (meta.w < 0.0)
				continue;

			highp vec2 A = u_synA[k];
			highp vec2 M = u_synM[k];
			highp vec2 B = u_synB[k];
			highp float wPad = max(meta.y, meta.z) * 3.2;
			highp vec2 bMin = min(A, min(M, B)) - vec2(wPad);
			highp vec2 bMax = max(A, max(M, B)) + vec2(wPad);
			if (v_screenPos.x < bMin.x || v_screenPos.x > bMax.x ||
			    v_screenPos.y < bMin.y || v_screenPos.y > bMax.y)
				continue;

			// Quadratic Bezier passing exactly through A (s=0), M (s=0.5), B (s=1)
			highp vec2 C  = 2.0 * M - 0.5 * (A + B);
			highp vec2 c1 = 2.0 * (C - A);
			highp vec2 c2 = A - 2.0 * C + B;
			highp vec2 AB = B - A;
			highp float abLen2 = max(dot(AB, AB), 1.0);
			highp float s = clamp(dot(v_screenPos - A, AB) / abLen2, 0.0, 1.0);

			// Two Gauss-Newton steps for exact closest point along the curved synchrone
			highp vec2 Ps = A + s * (c1 + s * c2);
			highp vec2 dP = c1 + 2.0 * s * c2;
			s = clamp(s - dot(Ps - v_screenPos, dP) / max(dot(dP, dP), 1.0), 0.0, 1.0);
			Ps = A + s * (c1 + s * c2);
			dP = c1 + 2.0 * s * c2;
			s = clamp(s - dot(Ps - v_screenPos, dP) / max(dot(dP, dP), 1.0), 0.0, 1.0);

			Ps = A + s * (c1 + s * c2);
			highp vec2 diff = v_screenPos - Ps;
			highp float dist2 = dot(diff, diff);

			// C1 smoothstep parameter sW guarantees zero slope discontinuity (zero Mach-band seam!) across s = 0 at the head
			highp float sW = s * s * (3.0 - 2.0 * s);
			highp float wLoc = mix(meta.y, meta.z, sW);
			highp float v2 = dist2 / max(wLoc * wLoc, 1.0);
			if (v2 < 9.5)
			{
				highp float g = exp(-v2 * 1.05);
				highp vec2 normPair = u_synNorm[k];
				highp float abLen = sqrt(abLen2);
				// Suppress sub-coma-length synchrones from injecting a 0->1 vBeta step across the head (prevents flat mushroom/pen cap!)
				highp float vW = g * smoothstep(0.45 * wLoc, 2.60 * wLoc, abLen);
				gRawSum  += g;
				gNormSum += g * mix(normPair.x, normPair.y, sW);
				uSum     += meta.w * g;
				vSum     += s * vW;
				vDenom   += vW;
				qSum     += meta.x * g;
			}
		}

		if (gRawSum > 1e-4)
		{
			highp float uAge  = clamp(uSum / gRawSum, 0.0, 1.0);
			highp float vBeta = (vDenom > 1e-4) ? clamp(vSum / vDenom, 0.0, 1.0) : 0.0;
			highp float qFlux = clamp(qSum / gRawSum, 0.0, 1.5);
			// Pure C-infinity Gaussian-envelope coverage (eliminates any circular halo/rim around the head!)
			highp float sheetMask = 1.0 - exp(-1.65 * gNormSum);

			// Organic non-periodic Sekanina-Farrell aurora paintbrush bristles in (uAge, vBeta) sheet space:
			// Tiny positive shear (+0.025 * vBeta) keeps striae straight-ish & graceful (zero spiral pinwheel bend!),
			// while mid-to-fine non-periodic vnoise octaves (22 / 44 / 82) generate ~18-22 natural irregular aurora
			// ribbons spanning the entire arch with ZERO periodic seashell ribs and ZERO giant empty V-notches!
			highp float uStria = uAge + 0.025 * vBeta * float(u_striaeStrength);
			highp float uWarp  = uStria + (vnoise(vec2(uStria * 8.0 + u_seed * 0.37, vBeta * 0.55)) - 0.5) * 0.010 * vBeta;
			highp float bBand1 = vnoise(vec2(uWarp * 22.0 + u_seed * 0.53, vBeta * 0.26));
			highp float bBand2 = vnoise(vec2(uWarp * 44.0 + u_seed * 1.37, vBeta * 0.44));
			highp float bBand3 = vnoise(vec2(uWarp * 82.0 + u_seed * 2.71, vBeta * 0.72));
			highp float bristleBand = clamp(0.46 * bBand1 + 0.36 * bBand2 + 0.18 * bBand3, 0.0, 1.0);
			highp float fMid = bBand1;

			// Subtle organic cloud turbulence warping vBeta so no edge ever reads like a rigid mathematical curve
			highp float cloudWarp = ((vnoise(vec2(uAge * 4.4 + u_seed * 0.61, vBeta * 2.0)) - 0.5) * 0.048
			                       + (vnoise(vec2(uAge * 9.5 + u_seed * 1.73, vBeta * 3.6)) - 0.5) * 0.020)
			                       * smoothstep(0.12, 0.42, uAge);
			highp float vOrg = clamp(vBeta + cloudWarp, 0.0, 1.0);

			highp float omU = max(0.0, 1.0 - uAge);

			// Smooth dust comets (Hale-Bopp, Halley, Hyakutake): C1 zero-derivative at vBeta=0 eliminates head-to-tail seam!
			highp float v2s = vBeta * vBeta;
			highp float smoothAlong = pow(max(0.0, 1.0 - v2s), 1.15) * smoothstep(1.0, 0.66, vBeta) / (1.0 + 1.15 * v2s);
			highp float smoothAge   = pow(omU, 0.78) * smoothstep(1.0, 0.76, uAge);
			highp float silkMod     = mix(1.0, 0.86 + 0.28 * fMid, float(u_dustRibbonStrength) * smoothstep(0.08, 0.38, vBeta));
			highp float smoothDensity = smoothAlong * smoothAge * silkMod;

			mediump vec3 headTint  = mix(vec3(1.00, 0.98, 0.92), vec3(1.00, 0.94, 0.78), u_dustWarmth);
			headTint = mix(headTint, vec3(0.68, 0.98, 0.84), u_greenWeight * 0.55);
			mediump vec3 midWarm   = mix(vec3(0.99, 0.87, 0.73), vec3(1.00, 0.86, 0.68), u_dustWarmth);
			midWarm = mix(midWarm, vec3(0.76, 0.86, 0.92), u_greenWeight * 0.55);
			mediump vec3 outerWarm = mix(vec3(0.88, 0.74, 0.62), vec3(0.92, 0.76, 0.62), u_dustWarmth);
			outerWarm = mix(outerWarm, vec3(0.64, 0.74, 0.86), u_greenWeight * 0.50);
			highp float midBlend = smoothstep(0.06, 0.40, max(uAge * 0.78, vBeta * 0.44));
			highp float outBlend = smoothstep(0.18, 0.72, max(vBeta * 0.92, uAge * 0.54));
			mediump vec3 smoothColor = mix(headTint, midWarm, float(midBlend));
			smoothColor = mix(smoothColor, outerWarm, float(outBlend));

			// Striated great sunskirters (McNaught, West) — ORGANIC AURORA PAINTBRUSH + TWIN-SUBTAIL FORK:
			//  1) Rises cleanly from the head as ONE smooth, blazing, silky curved main tail (zero caterpillar ribs!),
			//     forking naturally on the outer sweep (uAge 0.34..0.72) into upper (0.48) & lower (0.24) sub-tails
			//     bridged by soft translucent intermediate-beta mist.
			//  2) Directly upward from the entire crest of the luminous arch, ~18-22 organic irregular aurora bristle
			//     curtains stretch high into the night sky (vOrg 0.36 -> 0.98) and dissolve softly like dry-brush mist!
			highp float archFadeU    = pow(omU, 0.36) * smoothstep(1.0, 0.78, uAge);
			highp float forkGrow     = smoothstep(0.32, 0.70, uAge);
			highp float striaOn      = smoothstep(0.16, 0.40, uAge);

			// Physical bifurcation from ONE sweeping main arch (v=0.36) into upper (0.48) & lower (0.24) sub-tails
			highp float vUpper       = mix(0.36, 0.48, forkGrow);
			highp float vLower       = mix(0.36, 0.24, forkGrow);

			// Smooth silky glowing arch spine + variable-reach organic aurora bristles soaring upward out of the crest
			highp float dvUpper      = vOrg - vUpper;
			highp float wInnerUpper  = mix(0.22, 0.10, forkGrow);
			highp float tuftShape    = smoothstep(0.16, 0.86, bristleBand);
			highp float wOuterBristle = mix(0.18, mix(0.18, 0.54, tuftShape), striaOn);
			highp float wUpperSide   = (dvUpper >= 0.0) ? wOuterBristle : wInnerUpper;
			highp float outerFade    = smoothstep(1.0, 0.70, vOrg);

			// Keep the bright stem & arch spine silky smooth (0.88..1.14), sharpening smoothly into luminous aurora ribbons ONLY upward!
			highp float rootMod      = 0.88 + 0.26 * bristleBand;
			highp float curtainMod   = 0.22 + 1.44 * pow(tuftShape, 1.35);
			highp float bristleMod   = mix(rootMod, curtainMod, smoothstep(0.04, 0.30, dvUpper) * striaOn);
			highp float upperBranch  = mix(1.22, 0.94, forkGrow)
			                         * exp(-pow(dvUpper / max(wUpperSide, 0.06), 2.0))
			                         * mix(1.0, bristleMod, striaOn) * outerFade * archFadeU;

			// Soft dreamy aurora mist glow bathing the soaring curtains (keeps striations silky & atmospheric)
			highp float auroraMist   = 0.28 * striaOn * smoothstep(vUpper - 0.05, vUpper + 0.10, vOrg)
			                         * pow(max(0.0, 1.0 - vOrg), 1.05) * outerFade
			                         * (0.42 + 1.16 * pow(tuftShape, 1.25)) * archFadeU;

			// Soft patchy mist bridging the fork between upper & lower sub-tails
			highp float vMidFork     = 0.5 * (vUpper + vLower);
			highp float valleyPatch  = vnoise(vec2(uWarp * 8.5 + u_seed * 2.13, vOrg * 2.8));
			highp float valleyMist   = 0.26 * forkGrow
			                         * exp(-pow((vOrg - vMidFork) / 0.105, 2.0))
			                         * (0.55 + 0.85 * valleyPatch) * (0.86 + 0.28 * bristleBand)
			                         * archFadeU;

			// Companion lower sub-tail peeling smoothly off the main arch, with subtle misty striated wisps on its outer edge
			highp float dvLower      = vOrg - vLower;
			highp float wLowerOut    = mix(0.09, 0.155, tuftShape * striaOn);
			highp float wLowerSide   = (dvLower < 0.0) ? wLowerOut : 0.088;
			highp float lowerBranch  = 0.58 * forkGrow
			                         * exp(-pow(dvLower / max(wLowerSide, 0.06), 2.0))
			                         * (0.86 + 0.28 * bristleBand)
			                         * pow(omU, 0.42) * smoothstep(1.0, 0.78, uAge);

			highp float striaeDensity = upperBranch + auroraMist + valleyMist + lowerBranch;
			mediump vec3 hornColor   = mix(vec3(1.00, 0.99, 0.93), vec3(1.00, 0.93, 0.78), u_dustWarmth * 0.45);
			mediump vec3 archColor   = mix(hornColor, vec3(0.95, 0.97, 1.00), float(forkGrow));
			mediump vec3 curtainCol  = vec3(0.68, 0.80, 1.00);
			mediump vec3 upperColor  = mix(archColor, curtainCol, float(smoothstep(vUpper + 0.06, 0.88, vOrg)));
			mediump vec3 lowerColor  = vec3(0.88, 0.91, 0.96);
			mediump vec3 striaeColor = (upperColor * float(upperBranch + auroraMist)
			                          + lowerColor * float(valleyMist + lowerBranch)) / max(float(striaeDensity), 1e-4);

			highp float extGrad = mix(1.0, float(u_tipExtRatio), max(uAge * 0.55, vBeta * 0.45));
			highp float combinedDensity = mix(smoothDensity, striaeDensity, float(u_striaeStrength));
			mediump vec3 combinedColor  = mix(smoothColor, striaeColor, u_striaeStrength);

			highp float dustDensity = sheetMask * qFlux * extGrad * combinedDensity;
			highp float optDepth = dustDensity * float(u_dustIntensity) * mix(3.15, 2.55, float(u_striaeStrength));
			highp float dustRadiance = (1.0 - exp(-optDepth)) * 0.96;
			totalRgb += combinedColor * float(dustRadiance);
			totalSignal += dustRadiance;
		}
	}

	// 3. Unified C-infinity analytical Straight Sapphire-Cobalt CO+ Ion Tail with subtle longitudinal plasma rays
	if (u_gasIntensity > 0.0005 && u_gasLenPx > 1.0)
	{
		highp vec2 gasPerp = vec2(-u_gasDir.y, u_gasDir.x);
		highp float xg = dot(d, u_gasDir);
		highp float yg = dot(d, gasPerp);
		if (xg > -2.4 * R && xg < u_gasLenPx)
		{
			highp float tg = xg / u_gasLenPx;
			// C-infinity smooth ramp across xg = 0 eliminates any Mach-band kink/seam across the comet head!
			highp float tPos = clamp(0.5 * (tg + sqrt(tg * tg + 0.0004)), 0.0, 1.0);
			highp float tFan = pow(tPos, 1.15);
			highp float wHead = 0.78 * R * sqrt(1.0 + 2.2 * tPos);
			highp float wGas = sqrt(wHead * wHead + (u_gasWidthPx * tFan) * (u_gasWidthPx * tFan));
			highp float vg = yg / max(wGas, 1.0);
			highp float vg2 = vg * vg;
			if (vg2 < 14.0)
			{
				// Turbulent domain-warped solar-wind braided plasma filaments (authentic C/2009 R1 / Lovejoy / Hyakutake eddies + Hale-Bopp CO+ streamers)
				highp float rayGrow = smoothstep(0.025, 0.22, tPos);
				highp float braidBoost = clamp(float(u_greenWeight) * 0.85 + float(u_ionRayStrength) * 0.40, 0.0, 1.0);
				highp float wave = (0.045 * sin(tPos * 4.6 + u_seed * 1.7)
				                  + 0.024 * sin(tPos * 8.5 + u_seed * 3.1)) * rayGrow;
				highp float eddy1 = (vnoise(vec2(vg * 2.0 + u_seed * 0.71, tPos * 3.4 - u_phase * 0.8)) - 0.5) * 0.52 * rayGrow * braidBoost;
				highp float eddy2 = (vnoise(vec2(vg * 4.4 + u_seed * 1.93, tPos * 6.2 - u_phase * 1.2)) - 0.5) * 0.26 * rayGrow * braidBoost;

				highp float vgw = vg + wave;
				highp float vgw2 = vgw * vgw;
				highp float vBraidA = vgw + eddy1 + eddy2;
				highp float vBraidB = vgw - eddy1 * 0.85 + eddy2 * 1.15;

				highp float inA = vnoise(vec2(vBraidA * 5.8 + u_seed * 1.13, tPos * 1.65 - u_phase));
				highp float inB = vnoise(vec2(vBraidB * 11.2 + u_seed * 2.37, tPos * 2.85 - u_phase * 1.3));
				highp float inC = vnoise(vec2((vBraidA + vBraidB) * 8.5 + u_seed * 3.71, tPos * 4.10 - u_phase * 1.5));
				highp float braidedStrands = pow(clamp(0.42 * inA + 0.36 * inB + 0.22 * inC, 0.0, 1.0), 1.40);

				highp float smoothAcross = 0.56 * exp(-vgw2 * 2.15) + 0.44 * exp(-vgw2 * 0.80);
				highp float rayCore = 0.42 * exp(-vBraidA * vBraidA * 3.6);
				highp float ray1 = 0.26 * exp(-(vBraidA - 0.30) * (vBraidA - 0.30) * 11.5) * rayGrow;
				highp float ray2 = 0.24 * exp(-(vBraidB + 0.26) * (vBraidB + 0.26) * 12.0) * rayGrow;
				highp float ray3 = 0.16 * exp(-(vBraidA - 0.62) * (vBraidA - 0.62) * 14.0) * rayGrow;
				highp float ray4 = 0.14 * exp(-(vBraidB + 0.58) * (vBraidB + 0.58) * 14.0) * rayGrow;
				highp float raySheath = 0.32 * exp(-vgw2 * 0.78);
				highp float ionFilament = (rayCore + ray1 + ray2 + ray3 + ray4 + raySheath)
				                        * mix(1.0, 0.36 + 1.50 * braidedStrands, rayGrow);
				highp float across = mix(smoothAcross, ionFilament, float(u_ionRayStrength));

				highp float sunwardCap = smoothstep(-0.95 * R, 0.75 * R, xg);
				highp float om = max(0.0, 1.0 - tPos);
				highp float along = (om > 1e-5) ? (pow(om, 1.22) / pow(1.0 + 1.45 * tPos, 1.10)) : 0.0;
				highp float extGrad = mix(1.0, float(u_tipExtRatio), tPos);
				highp float gasDensity = sunwardCap * along * across * extGrad;

				// On green-C2 braided plasma comets (Hyakutake, C/2009 R1, Lovejoy), inner braided filaments gleam
				// luminous emerald-mint-white inside the coma before transitioning outward to silver-blue & sapphire tendrils!
				highp float silverCore = float(u_greenWeight) * float(u_ionRayStrength) * smoothstep(0.28, 0.80, braidedStrands)
				                       * exp(-vgw2 * 1.25) * (1.0 - smoothstep(0.18, 0.72, tPos));
				mediump vec3 headIonTint = mix(vec3(0.24, 0.54, 1.00), vec3(0.22, 0.92, 0.76), u_greenWeight * 0.72);
				mediump vec3 gasTint = mix(headIonTint, vec3(0.08, 0.30, 1.00), float(smoothstep(0.03, 0.32, tPos)));
				gasTint = mix(gasTint, vec3(0.86, 0.94, 1.00), float(clamp(silverCore * 0.92, 0.0, 0.88)));
				totalRgb += gasTint * (u_gasIntensity * float(gasDensity));
				totalSignal += gasDensity;
			}
		}
	}

	if (totalSignal <= 0.0002)
		discard;

	// Luminance-preserving photographic filmic shoulder: prevents blown-out white head
	// while keeping deep cobalt-sapphire ion blue and warm creamy-peach dust fully saturated
	mediump float lum = dot(totalRgb, vec3(0.2126, 0.7152, 0.0722));
	totalRgb *= 1.0 / (1.0 + 0.58 * lum);

	// 1-LSB screen-space dithering eliminates 8-bit framebuffer contour banding on long faint tails
	highp float dither = (hash12(gl_FragCoord.xy) - 0.5) / 255.0;
	totalRgb = max(vec3(0.0), totalRgb + vec3(float(dither)) * float(smoothstep(0.0, 0.012, totalSignal)));
	FRAG_COLOR = vec4(totalRgb, 0.0);
}
)";

	std::unique_ptr<QOpenGLShaderProgram> prog(new QOpenGLShaderProgram);
	if (!prog->addShaderFromSourceCode(QOpenGLShader::Vertex, vertSrc))
	{
		qWarning().noquote() << "Comet: analytical vertex shader error:\n" << prog->log();
		shaderInitFailed = true;
		return false;
	}
	if (!prog->addShaderFromSourceCode(QOpenGLShader::Fragment, fragSrc))
	{
		qWarning().noquote() << "Comet: analytical fragment shader error:\n" << prog->log();
		shaderInitFailed = true;
		return false;
	}
	prog->bindAttributeLocation("a_pos", 0);
	if (!StelPainter::linkProg(prog.get(), "Comet analytical shader"))
	{
		shaderInitFailed = true;
		return false;
	}

	cometShaderProgram = std::move(prog);
	s_cometShaderVars.projectionMatrix  = cometShaderProgram->uniformLocation("u_projectionMatrix");
	s_cometShaderVars.headPos           = cometShaderProgram->uniformLocation("u_headPos");
	s_cometShaderVars.comaRadPx         = cometShaderProgram->uniformLocation("u_comaRadPx");
	s_cometShaderVars.comaIntensity     = cometShaderProgram->uniformLocation("u_comaIntensity");
	s_cometShaderVars.nucleusSuppress   = cometShaderProgram->uniformLocation("u_nucleusSuppress");
	s_cometShaderVars.greenWeight       = cometShaderProgram->uniformLocation("u_greenWeight");
	s_cometShaderVars.gasDir            = cometShaderProgram->uniformLocation("u_gasDir");
	s_cometShaderVars.gasLenPx          = cometShaderProgram->uniformLocation("u_gasLenPx");
	s_cometShaderVars.gasWidthPx        = cometShaderProgram->uniformLocation("u_gasWidthPx");
	s_cometShaderVars.gasIntensity      = cometShaderProgram->uniformLocation("u_gasIntensity");
	s_cometShaderVars.ionRayStrength    = cometShaderProgram->uniformLocation("u_ionRayStrength");
	s_cometShaderVars.dustIntensity     = cometShaderProgram->uniformLocation("u_dustIntensity");
	s_cometShaderVars.dustWarmth        = cometShaderProgram->uniformLocation("u_dustWarmth");
	s_cometShaderVars.dustRibbonStrength = cometShaderProgram->uniformLocation("u_dustRibbonStrength");
	s_cometShaderVars.striaeStrength    = cometShaderProgram->uniformLocation("u_striaeStrength");
	auto findArrayUniform = [&](const char* name, const char* elem0) -> int {
		int loc = cometShaderProgram->uniformLocation(name);
		return (loc >= 0) ? loc : cometShaderProgram->uniformLocation(elem0);
	};
	s_cometShaderVars.synA              = findArrayUniform("u_synA", "u_synA[0]");
	s_cometShaderVars.synM              = findArrayUniform("u_synM", "u_synM[0]");
	s_cometShaderVars.synB              = findArrayUniform("u_synB", "u_synB[0]");
	s_cometShaderVars.synMeta           = findArrayUniform("u_synMeta", "u_synMeta[0]");
	s_cometShaderVars.synNorm           = findArrayUniform("u_synNorm", "u_synNorm[0]");
	s_cometShaderVars.seed              = cometShaderProgram->uniformLocation("u_seed");
	s_cometShaderVars.phase             = cometShaderProgram->uniformLocation("u_phase");
	s_cometShaderVars.tipExtRatio       = cometShaderProgram->uniformLocation("u_tipExtRatio");

	cometVBO.reset(new QOpenGLBuffer(QOpenGLBuffer::VertexBuffer));
	if (!cometVBO->create())
	{
		deinitShader();
		shaderInitFailed = true;
		return false;
	}
	cometVBO->setUsagePattern(QOpenGLBuffer::StreamDraw);
	cometVBO->bind();
	cometVBO->allocate(6 * static_cast<int>(sizeof(CometQuadVertex)));

	cometVAO.reset(new QOpenGLVertexArrayObject);
	if (cometVAO->create())
	{
		cometVAO->bind();
		QOpenGLFunctions* gl = ctx->functions();
		gl->glEnableVertexAttribArray(0);
		gl->glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(CometQuadVertex), reinterpret_cast<const void*>(offsetof(CometQuadVertex, x)));
		cometVAO->release();
	}
	cometVBO->release();
	return true;
}

void Comet::updateDustSynchrones(double dateJDE, float striaeStrength, float isLongPeriod)
{
	if (std::fabs(dateJDE - lastSynchroneJDE) <= 0.04 &&
	    std::fabs(striaeStrength - lastSynchroneStriae) <= 0.04f)
		return;

	const KeplerOrbit* kOrbit = static_cast<KeplerOrbit*>(orbitPtr);
	if (!kOrbit)
		return;

	Vec3d cometNowPos, cometNowVel;
	kOrbit->stateAtTimeInVSOP87Coordinates(dateJDE, cometNowPos, cometNowVel);
	const double rNow = std::max(cometNowPos.norm(), 0.01);
	const double periQ = std::max(0.002, kOrbit->getPericenterDistance());
	const double tPeri = kOrbit->getTimeAtPericenter();
	double dtDays = dateJDE - tPeri;
	const double periodDays = getSiderealPeriod();
	if (periodDays > 10.0)
		dtDays = std::remainder(dtDays, periodDays);

	// Adaptive Finson-Probstein dust age window (includes extra outer mist buffer so tails dissolve asymptotically):
	double maxTau = qBound(26.0, 42.0 * std::sqrt(rNow * periQ) + 14.0, 62.0);
	if (periQ < 0.35 && dtDays > 0.5 && dtDays < 48.0)
	{
		maxTau = std::min(dtDays + 9.2, 20.5);
	}
	maxTau *= (0.58 + 0.42 * static_cast<double>(isLongPeriod));

	// Uniform physical silicate dust radiation-pressure envelope beta in [betaInner, 0.985] (< 1.0 => strictly bound,
	// distortion-free continuous (uAge, vBeta) coordinate atlas; betaInner ~ 0.08 keeps the arch underside soft & natural).
	const double betaInner = 0.04 + 0.05 * static_cast<double>(striaeStrength);
	constexpr double betaOuter = 0.985;
	const double betaMid = 0.5 * (betaInner + betaOuter);

	double qRaw[COMET_SYNCHRONE_COUNT];
	double qMax = 1e-6;

	const double tauPow = 1.24 - 0.18 * static_cast<double>(striaeStrength);
	for (int k = 0; k < COMET_SYNCHRONE_COUNT; ++k)
	{
		const double u = (static_cast<double>(k) + 0.35) / static_cast<double>(COMET_SYNCHRONE_COUNT);
		const float ageFrac = static_cast<float>(k) / static_cast<float>(COMET_SYNCHRONE_COUNT - 1);
		const double tau = std::max(0.08, maxTau * std::pow(u, tauPow));

		Vec3d pEmit, vEmit;
		kOrbit->stateAtTimeInVSOP87Coordinates(dateJDE - tau, pEmit, vEmit);
		const double rEmit = std::max(pEmit.norm(), 0.01);

		const int steps = qBound(18, static_cast<int>(std::ceil(tau / std::max(0.14, 0.60 * std::min(rEmit, periQ)))), 48);

		DustSynchroneSample& syn = dustSynchrones[k];
		syn.relA = (k == 0) ? Vec3d(0.0, 0.0, 0.0) : (integrateDustVerlet(pEmit, vEmit, tau, betaInner, steps) - cometNowPos);
		syn.relM = integrateDustVerlet(pEmit, vEmit, tau, betaMid, steps) - cometNowPos;
		syn.relB = integrateDustVerlet(pEmit, vEmit, tau, betaOuter, steps) - cometNowPos;

		qRaw[k] = std::pow(1.0 / rEmit, 1.80);
		if (qRaw[k] > qMax)
			qMax = qRaw[k];
		syn.ageFrac = ageFrac;
	}

	for (int k = 0; k < COMET_SYNCHRONE_COUNT; ++k)
	{
		DustSynchroneSample& syn = dustSynchrones[k];
		// Smooth gently-compressed physical outgassing flux Q(t_e) so perihelion arch shines brightest
		// while the older sweeping right wing retains luminous presence as it fades out.
		syn.weight = qBound(0.52f, static_cast<float>(std::pow(qRaw[k] / qMax, 0.55)), 1.0f);
	}

	lastSynchroneJDE = dateJDE;
	lastSynchroneStriae = striaeStrength;
}

void Comet::drawAnalyticalComet(StelCore* core, const StelProjectorP& prj,
                                const Vec3d& cometEcl, const Vec3d& observerEcl,
                                const Vec3d& antiSun,
                                double comaRadAU, double gasLenAU,
                                bool showTail, float vMagnitude, float screenRd,
                                float comaIntensity, float gasIntensity, float dustIntensity,
                                float twilightFade, float warmth, float greenWeight,
                                float ionRayStrength, float dustRibbonStrength,
                                float striaeStrength, float isLongPeriod)
{
	Vec3d winHead;
	if (!prj->project(Vec3d(0.0, 0.0, 0.0), winHead) || !std::isfinite(winHead[0]) || !std::isfinite(winHead[1]))
		return;

	const double distObs = std::max((cometEcl - observerEcl).norm(), 1e-5);
	const double pixelPerRad = static_cast<double>(prj->getPixelPerRadAtCenter());
	const double dpr = std::max(1.0, static_cast<double>(core->getCurrentStelProjectorParams().devicePixelsPerPixel));
	const double vpLeft   = static_cast<double>(prj->getViewportPosX());
	const double vpBottom = static_cast<double>(prj->getViewportPosY());
	const double vpW      = static_cast<double>(prj->getViewportWidth());
	const double vpH      = static_cast<double>(prj->getViewportHeight());
	const double vpRight  = vpLeft + vpW;
	const double vpTop    = vpBottom + vpH;
	const double maxVp    = std::max(vpW, vpH);

	static StelMovementMgr* mMgrComa = GETSTELMODULE(StelMovementMgr);
	const float curFov = std::max(0.05f, static_cast<float>(mMgrComa->getCurrentFov()));
	const double wideFovScale = 0.42 + 0.58 * static_cast<double>(1.0f - smoothStepF(15.0f, 70.0f, curFov));
	const double physComaPx = std::atan(comaRadAU / distObs) * pixelPerRad;
	const double minComaPx  = qBound(1.5, 3.8 - 0.24 * static_cast<double>(vMagnitude), 4.8) * wideFovScale * dpr;
	const double maxComaPx  = 0.20 * maxVp;
	const double comaPx     = qBound(minComaPx, physComaPx, maxComaPx);

	if (showTail && dustIntensity > 0.002f)
	{
		updateDustSynchrones(core->getJDE(), striaeStrength, isLongPeriod);
	}

	// Atmospheric extinction at head and down-tail midpoint
	const bool withAtmosphere = core->getSkyDrawer()->getFlagHasAtmosphere();
	float extHead = 1.0f;
	float extTip  = 1.0f;
	if (withAtmosphere)
	{
		const Extinction extinction = core->getSkyDrawer()->getVisualExtinction();
		Vec3d altAzHead = core->heliocentricEclipticToAltAz(cometEcl, StelCore::RefractionOn);
		if (altAzHead.normSquared() > 1e-12)
		{
			altAzHead.normalize();
			float oneMag = 0.0f;
			extinction.forward(altAzHead, &oneMag);
			extHead = std::pow(0.4f, oneMag);
		}
		if (showTail)
		{
			Vec3d midOffset = (dustIntensity > 0.002f)
				? dustSynchrones[COMET_SYNCHRONE_COUNT / 2].relM
				: (antiSun * (0.60 * gasLenAU));
			Vec3d altAzTip = core->heliocentricEclipticToAltAz(cometEcl + midOffset, StelCore::RefractionOn);
			if (altAzTip.normSquared() > 1e-12)
			{
				altAzTip.normalize();
				float oneMag = 0.0f;
				extinction.forward(altAzTip, &oneMag);
				extTip = std::pow(0.4f, oneMag);
			}
		}
		else
		{
			extTip = extHead;
		}
	}

	const float headScale = twilightFade * extHead;
	const float finalComaInt = comaIntensity * headScale;
	float finalGasInt = showTail ? (gasIntensity * headScale) : 0.0f;
	float finalDustInt = showTail ? (dustIntensity * headScale) : 0.0f;
	const float tipExtRatio = qBound(0.12f, extTip / std::max(extHead, 0.01f), 1.6f);

	if (finalComaInt <= 0.002f && finalGasInt <= 0.002f && finalDustInt <= 0.002f)
		return;

	// Compute projected 2D screen-space geometry for gas tail
	const Vec3d viewDir = (cometEcl - observerEcl) / distObs;
	const double probeAU = qBound(comaRadAU * 0.5, std::max(gasLenAU, 0.05) * 0.12, distObs * 0.06);

	auto projectDir2D = [&](const Vec3d& dir3D, double stepAU, QVector2D& outDir) -> bool
	{
		Vec3d winProbe;
		const Vec3d p = dir3D * stepAU;
		if (!prj->project(p, winProbe) || !std::isfinite(winProbe[0]) || !std::isfinite(winProbe[1]) ||
		    prj->intersectViewportDiscontinuity(Vec3d(0.0, 0.0, 0.0), p))
			return false;
		const double dx = winProbe[0] - winHead[0];
		const double dy = winProbe[1] - winHead[1];
		const double len = std::sqrt(dx * dx + dy * dy);
		if (len < 1e-4)
			return false;
		outDir = QVector2D(static_cast<float>(dx / len), static_cast<float>(dy / len));
		return true;
	};

	QVector2D gasDir(0.0f, 1.0f);
	const bool hasGasDir = projectDir2D(antiSun, probeAU, gasDir);
	double gasLenPx = 0.0;
	double gasWidthPx = 0.0;
	const double minGasWidthPx = 1.8 * dpr;

	if (showTail && gasLenAU > 1e-7 && finalGasInt > 0.002f && hasGasDir)
	{
		const Vec3d gasTip3D = antiSun * gasLenAU;
		Vec3d winGasTip;
		bool gotGasTip = false;
		if (prj->project(gasTip3D, winGasTip) && std::isfinite(winGasTip[0]) && std::isfinite(winGasTip[1]) &&
		    !prj->intersectViewportDiscontinuity(Vec3d(0.0, 0.0, 0.0), gasTip3D))
		{
			const double projLen = (winGasTip[0] - winHead[0]) * static_cast<double>(gasDir.x())
			                     + (winGasTip[1] - winHead[1]) * static_cast<double>(gasDir.y());
			if (projLen > 1.0)
			{
				gasLenPx = projLen;
				gotGasTip = true;
			}
		}
		if (!gotGasTip)
		{
			const double cosA = qBound(-1.0, antiSun.dot(viewDir), 1.0);
			const double foreshorten = std::sqrt(std::max(0.0, 1.0 - cosA * cosA));
			gasLenPx = std::atan((gasLenAU * foreshorten) / distObs) * pixelPerRad;
		}
		const double gasHalfWidthAU = comaRadAU * 1.45 + gasLenAU * 0.068;
		gasWidthPx = std::atan(gasHalfWidthAU / distObs) * pixelPerRad;
		gasWidthPx = std::min(gasWidthPx, std::max(comaPx * 1.35, gasLenPx * 0.14));
		if (gasWidthPx < minGasWidthPx)
		{
			finalGasInt *= static_cast<float>(qBound(0.22, gasWidthPx / minGasWidthPx, 1.0));
			gasWidthPx = minGasWidthPx;
		}
		if (gasLenPx < 2.0)
			finalGasInt = 0.0f;
	}
	else
	{
		finalGasInt = 0.0f;
	}

	// Project real 3D Finson-Probstein synchrones to 2D screen space
	QVector2D synA[COMET_SYNCHRONE_COUNT];
	QVector2D synM[COMET_SYNCHRONE_COUNT];
	QVector2D synB[COMET_SYNCHRONE_COUNT];
	QVector4D synMeta[COMET_SYNCHRONE_COUNT];
	QVector2D synNorm[COMET_SYNCHRONE_COUNT];
	bool synValid[COMET_SYNCHRONE_COUNT] = {};
	int validSynCount = 0;

	const double vpCx = vpLeft + 0.5 * vpW;
	const double vpCy = vpBottom + 0.5 * vpH;
	const double vpBound = 3.5 * maxVp;
	const double maxRelAU = distObs * 1.60;

	auto projectRelPt = [&](const Vec3d& rel, QVector2D& outPt) -> bool
	{
		if (rel.norm() > maxRelAU)
			return false;
		Vec3d w;
		if (!prj->project(rel, w) || !std::isfinite(w[0]) || !std::isfinite(w[1]) ||
		    prj->intersectViewportDiscontinuity(Vec3d(0.0, 0.0, 0.0), rel))
			return false;
		if (std::fabs(w[0] - vpCx) > vpBound || std::fabs(w[1] - vpCy) > vpBound)
			return false;
		outPt = QVector2D(static_cast<float>(w[0]), static_cast<float>(w[1]));
		return true;
	};

	for (int k = 0; k < COMET_SYNCHRONE_COUNT; ++k)
	{
		synMeta[k] = QVector4D(0.0f, 1.0f, 1.0f, -1.0f);
		if (finalDustInt <= 0.002f)
			continue;

		const DustSynchroneSample& s = dustSynchrones[k];
		QVector2D pA, pM, pB;
		const bool okA = (k == 0)
			? (pA = QVector2D(static_cast<float>(winHead[0]), static_cast<float>(winHead[1])), true)
			: projectRelPt(s.relA, pA);
		const bool okM = projectRelPt(s.relM, pM);
		const bool okB = projectRelPt(s.relB, pB);

		if (okA && okM && okB)
		{
			synA[k] = pA;
			synM[k] = pM;
			synB[k] = pB;
			synValid[k] = true;
			++validSynCount;
		}
		else if (okA && okM)
		{
			synA[k] = pA;
			synM[k] = 0.5f * (pA + pM);
			synB[k] = pM;
			synValid[k] = true;
			++validSynCount;
		}
	}

	// Build tight screen-space bounding quad enclosing coma + gas tail + all valid synchrones, clamped to viewport
	const double comaPad = comaPx * (4.9 + 1.2 * static_cast<double>(greenWeight));
	double minX = winHead[0] - comaPad;
	double maxX = winHead[0] + comaPad;
	double minY = winHead[1] - comaPad;
	double maxY = winHead[1] + comaPad;

	auto expandPt = [&](double px, double py, double pad)
	{
		minX = std::min(minX, px - pad);
		maxX = std::max(maxX, px + pad);
		minY = std::min(minY, py - pad);
		maxY = std::max(maxY, py + pad);
	};

	if (finalGasInt > 0.0005f && gasLenPx > 1.0)
	{
		const double gasPad = std::max(comaPx * 3.0, gasWidthPx * 3.6);
		expandPt(winHead[0] + static_cast<double>(gasDir.x()) * gasLenPx,
		         winHead[1] + static_cast<double>(gasDir.y()) * gasLenPx, gasPad);
	}

	if (validSynCount > 0 && finalDustInt > 0.002f)
	{
		// Wide seamless Gaussian overlap (~1.55x neighbor spacing) guarantees a mathematically flat,
		// 100% continuous 2D (uAge, vBeta) sheet atlas for ALL comets (zero visible discrete capsules or fork prongs!).
		constexpr double overlapInner = 1.55;
		constexpr double overlapOuter = 1.62;
		const double headScale = 1.12 - 0.44 * static_cast<double>(striaeStrength);
		const double minWInner = std::max(1.6 * dpr, headScale * comaPx);
		const double minWOuter = std::max(2.6 * dpr, 1.25 * comaPx);
		const double maxWInner = 0.24 * maxVp;
		const double maxWOuter = 0.42 * maxVp;

		for (int k = 0; k < COMET_SYNCHRONE_COUNT; ++k)
		{
			if (!synValid[k])
				continue;

			int prevIdx = -1;
			for (int j = k - 1; j >= 0; --j) { if (synValid[j]) { prevIdx = j; break; } }
			int nextIdx = -1;
			for (int j = k + 1; j < COMET_SYNCHRONE_COUNT; ++j) { if (synValid[j]) { nextIdx = j; break; } }

			double dInner = comaPx * 0.5;
			double dMid = comaPx;
			double dTip = comaPx * 1.4;
			if (prevIdx >= 0 && nextIdx >= 0)
			{
				dInner = 0.5 * (static_cast<double>((synA[k] - synA[prevIdx]).length())
				              + static_cast<double>((synA[nextIdx] - synA[k]).length()));
				dMid   = 0.5 * (static_cast<double>((synM[k] - synM[prevIdx]).length())
				              + static_cast<double>((synM[nextIdx] - synM[k]).length()));
				dTip   = 0.5 * (static_cast<double>((synB[k] - synB[prevIdx]).length())
				              + static_cast<double>((synB[nextIdx] - synB[k]).length()));
			}
			else if (prevIdx >= 0)
			{
				dInner = static_cast<double>((synA[k] - synA[prevIdx]).length());
				dMid   = static_cast<double>((synM[k] - synM[prevIdx]).length());
				dTip   = static_cast<double>((synB[k] - synB[prevIdx]).length());
			}
			else if (nextIdx >= 0)
			{
				dInner = static_cast<double>((synA[nextIdx] - synA[k]).length());
				dMid   = static_cast<double>((synM[nextIdx] - synM[k]).length());
				dTip   = static_cast<double>((synB[nextIdx] - synB[k]).length());
			}

			// Match wInnerPx strictly to true inner spacing dInner (NEVER bloated by dMid!) so dust never bleeds
			// past the comet head or creates side horns/flat caps; compensate at wOuterPx so mid-arch (s=0.5) still
			// satisfies 0.5*(wInnerPx + wOuterPx) >= overlapInner * dMid for 100% seamless continuous sheet coverage.
			double wInnerPx = qBound(minWInner, overlapInner * dInner, maxWInner);
			const double midNeededOuter = 2.0 * overlapInner * dMid - wInnerPx;
			double wOuterPx = qBound(minWOuter, std::max(overlapOuter * dTip, midNeededOuter), maxWOuter);
			if (k <= 2 && striaeStrength > 0.1f)
			{
				const double leadInnerCap = std::max(1.6 * dpr, comaPx * (0.68 + 0.22 * static_cast<double>(k)));
				wInnerPx = std::min(wInnerPx, leadInnerCap + (wInnerPx - leadInnerCap) * (1.0 - static_cast<double>(striaeStrength)));
			}

			// Exact partition-of-unity normalization for exp(-1.05 * u^2) (integral = sqrt(pi/1.05) = 1.73):
			const double overlapA = std::max(1.0, 1.73 * (wInnerPx / std::max(dInner, 0.35 * comaPx)));
			const double overlapB = std::max(1.0, 1.73 * (wOuterPx / std::max(std::max(dTip, dMid), 0.5)));

			synMeta[k] = QVector4D(dustSynchrones[k].weight, static_cast<float>(wInnerPx), static_cast<float>(wOuterPx), dustSynchrones[k].ageFrac);
			synNorm[k] = QVector2D(static_cast<float>(1.0 / overlapA),
			                       static_cast<float>(1.0 / overlapB));

			const double synPad = std::max(wInnerPx, wOuterPx) * 3.2;
			expandPt(static_cast<double>(synA[k].x()), static_cast<double>(synA[k].y()), synPad);
			expandPt(static_cast<double>(synM[k].x()), static_cast<double>(synM[k].y()), synPad);
			expandPt(static_cast<double>(synB[k].x()), static_cast<double>(synB[k].y()), synPad);
		}
	}
	else
	{
		finalDustInt = 0.0f;
	}

	minX = std::max(minX, vpLeft);
	maxX = std::min(maxX, vpRight);
	minY = std::max(minY, vpBottom);
	maxY = std::min(maxY, vpTop);
	if (minX >= maxX || minY >= maxY)
		return;

	const float x0 = static_cast<float>(minX);
	const float x1 = static_cast<float>(maxX);
	const float y0 = static_cast<float>(minY);
	const float y1 = static_cast<float>(maxY);

	const CometQuadVertex verts[6] = {
		{x0, y0}, {x1, y0}, {x0, y1},
		{x0, y1}, {x1, y0}, {x1, y1},
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
		gl->glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(CometQuadVertex), reinterpret_cast<const void*>(offsetof(CometQuadVertex, x)));
	}

	cometShaderProgram->bind();
	cometShaderProgram->setUniformValue(s_cometShaderVars.projectionMatrix, qMat);
	cometShaderProgram->setUniformValue(s_cometShaderVars.headPos, QVector2D(static_cast<float>(winHead[0]), static_cast<float>(winHead[1])));
	cometShaderProgram->setUniformValue(s_cometShaderVars.comaRadPx, static_cast<float>(comaPx));
	cometShaderProgram->setUniformValue(s_cometShaderVars.comaIntensity, finalComaInt);
	cometShaderProgram->setUniformValue(s_cometShaderVars.nucleusSuppress, nucleusSuppress);
	cometShaderProgram->setUniformValue(s_cometShaderVars.greenWeight, greenWeight);
	cometShaderProgram->setUniformValue(s_cometShaderVars.gasDir, gasDir);
	cometShaderProgram->setUniformValue(s_cometShaderVars.gasLenPx, static_cast<float>(gasLenPx));
	cometShaderProgram->setUniformValue(s_cometShaderVars.gasWidthPx, static_cast<float>(gasWidthPx));
	cometShaderProgram->setUniformValue(s_cometShaderVars.gasIntensity, finalGasInt);
	cometShaderProgram->setUniformValue(s_cometShaderVars.ionRayStrength, ionRayStrength);
	const float solarWindPhase = static_cast<float>(std::fmod(core->getJDE() * 0.16, 100.0));
	cometShaderProgram->setUniformValue(s_cometShaderVars.dustIntensity, finalDustInt);
	cometShaderProgram->setUniformValue(s_cometShaderVars.dustWarmth, warmth);
	cometShaderProgram->setUniformValue(s_cometShaderVars.dustRibbonStrength, dustRibbonStrength);
	cometShaderProgram->setUniformValue(s_cometShaderVars.striaeStrength, striaeStrength);
	if (finalDustInt > 0.0005f)
	{
		cometShaderProgram->setUniformValueArray(s_cometShaderVars.synA, synA, COMET_SYNCHRONE_COUNT);
		cometShaderProgram->setUniformValueArray(s_cometShaderVars.synM, synM, COMET_SYNCHRONE_COUNT);
		cometShaderProgram->setUniformValueArray(s_cometShaderVars.synB, synB, COMET_SYNCHRONE_COUNT);
		cometShaderProgram->setUniformValueArray(s_cometShaderVars.synMeta, synMeta, COMET_SYNCHRONE_COUNT);
		cometShaderProgram->setUniformValueArray(s_cometShaderVars.synNorm, synNorm, COMET_SYNCHRONE_COUNT);
	}
	cometShaderProgram->setUniformValue(s_cometShaderVars.seed, renderSeed);
	cometShaderProgram->setUniformValue(s_cometShaderVars.phase, solarWindPhase);
	cometShaderProgram->setUniformValue(s_cometShaderVars.tipExtRatio, tipExtRatio);

	gl->glDrawArrays(GL_TRIANGLES, 0, 6);

	cometShaderProgram->release();
	if (!useVAO)
	{
		gl->glDisableVertexAttribArray(0);
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
