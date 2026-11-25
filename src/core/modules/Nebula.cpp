/*
 * Stellarium
 * Copyright (C) 2002 Fabien Chereau
 * Copyright (C) 2011 Alexander Wolf
 * Copyright (C) 2015 Georg Zotti
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

#include "Nebula.hpp"
#include "NebulaMgr.hpp"
#include "Planet.hpp"
#include "StelLocaleMgr.hpp"
#include "StelTexture.hpp"

#include "StelUtils.hpp"
#include "StelApp.hpp"
#include "StelModuleMgr.hpp"
#include "StelCore.hpp"
#include "StelPainter.hpp"
#include "StelSkyDrawer.hpp"
#include "RefractionExtinction.hpp"
#include "StelSkyCultureMgr.hpp"
#include "ConstellationMgr.hpp"

#include <QTextStream>
#include <QFile>
#include <QString>
#include <QRegularExpression>

#include <QDebug>
#include <QBuffer>
#include <QVarLengthArray>

const QString Nebula::NEBULA_TYPE = QStringLiteral("Nebula");
quint64 Nebula::drawFrame = 0;

StelTextureSP Nebula::texRegion;
StelTextureSP Nebula::texPointElement;
StelTextureSP Nebula::texPlanetaryNebula;
bool  Nebula::drawHintProportional = true;
bool  Nebula::surfaceBrightnessUsage = false;
bool  Nebula::designationUsage = false;
float Nebula::hintsBrightness = 0.5f;
float Nebula::labelsBrightness = 1.f;
Vec3f Nebula::labelColor = Vec3f(0.4f,0.3f,0.5f);
QMap<Nebula::NebulaType, Vec3f>Nebula::hintColorMap;
bool Nebula::flagUseTypeFilters = true;
Nebula::CatalogGroup Nebula::catalogFilters = Nebula::CatalogGroup(Nebula::CatNone);
Nebula::TypeGroup Nebula::typeFilters = Nebula::TypeGroup(Nebula::TypeAll);
bool Nebula::flagUseArcsecSurfaceBrightness = false;
bool Nebula::flagUseShortNotationSurfaceBrightness = true;
bool Nebula::flagUseOutlines = true;
bool Nebula::flagShowAdditionalNames = true;
bool Nebula::flagShowOnlyNamedDSO = false;
bool Nebula::flagUseSizeLimits = false;
double Nebula::minSizeLimit = 1.0;
double Nebula::maxSizeLimit = 600.0;

const QMap<Nebula::NebulaType, QString> Nebula::typeEnglishStringMap = // Maps type to english name.
{
	{ NebGx     , L1S(N_("galaxy")) },
	{ NebAGx    , L1S(N_("active galaxy")) },
	{ NebRGx    , L1S(N_("radio galaxy")) },
	{ NebIGx    , L1S(N_("interacting galaxy")) },
	{ NebQSO    , L1S(N_("quasar")) },
	{ NebCl     , L1S(N_("star cluster")) },
	{ NebOc     , L1S(N_("open star cluster")) },
	{ NebGc     , L1S(N_("globular star cluster")) },
	{ NebSA     , L1S(N_("stellar association")) },
	{ NebSC     , L1S(N_("star cloud")) },
	{ NebN      , L1S(N_("nebula")) },
	{ NebPn     , L1S(N_("planetary nebula")) },
	{ NebDn     , L1S(N_("dark nebula")) },
	{ NebRn     , L1S(N_("reflection nebula")) },
	{ NebBn     , L1S(N_("bipolar nebula")) },
	{ NebEn     , L1S(N_("emission nebula")) },
	{ NebCn     , L1S(N_("cluster associated with nebulosity")) },
	{ NebHII    , L1S(N_("HII region")) },
	{ NebSNR    , L1S(N_("supernova remnant")) },
	{ NebISM    , L1S(N_("interstellar matter")) },
	{ NebEMO    , L1S(N_("emission object")) },
	{ NebBLL    , L1S(N_("BL Lac object")) },
	{ NebBLA    , L1S(N_("blazar")) },
	{ NebMolCld , L1S(N_("molecular cloud")) },
	{ NebYSO    , L1S(N_("young stellar object")) },
	{ NebPossQSO, L1S(N_("possible quasar")) },
	{ NebPossPN , L1S(N_("possible planetary nebula")) },
	{ NebPPN    , L1S(N_("protoplanetary nebula")) },
	{ NebStar   , L1S(N_("star")) },
	{ NebSymbioticStar   , L1S(N_("symbiotic star")) },
	{ NebEmissionLineStar, L1S(N_("emission-line star")) },
	{ NebSNC     , L1S(N_("supernova candidate")) },
	{ NebSNRC    , L1S(N_("supernova remnant candidate")) },
	{ NebGxCl    , L1S(N_("cluster of galaxies")) },
	{ NebPartOfGx, L1S(N_("part of a galaxy")) },
	{ NebRegion  , L1S(N_("region of the sky")) },
	{ NebUnknown , L1S(N_("object of unknown nature")) }
};

Nebula::Nebula()
	: StelObject()
	, DSO_nb(0)
	, M_nb(0)
	, NGC_nb(0)
	, IC_nb(0)
	, C_nb(0)
	, B_nb(0)
	, Sh2_nb(0)
	, VdB_nb(0)
	, RCW_nb(0)
	, LDN_nb(0)
	, LBN_nb(0)
	, Cr_nb(0)
	, Mel_nb(0)
	, PGC_nb(0)
	, UGC_nb(0)
	, Arp_nb(0)
	, VV_nb(0)
	, DWB_nb(0)
	, Tr_nb(0)
	, St_nb(0)
	, Ru_nb(0)
	, VdBHa_nb(0)
	, Ced_nb()
	, PK_nb()
	, PNG_nb()
	, SNRG_nb()
	, ACO_nb()
	, HCG_nb()
	, ESO_nb()
	, VdBH_nb()
	, withoutID(false)
	, nameI18()
	, discoverer()
	, discoveryYear()
	, mTypeString()
	, bMag(99.)
	, vMag(99.)
	, majorAxisSize(0.)
	, minorAxisSize(0.)
	, orientationAngle(0)
	, oDistance(0.)
	, oDistanceErr(0.)
	, redshift(99.)
	, redshiftErr(0.)
	, parallax(0.)
	, parallaxErr(0.)
	, nType()
{
	outlineSegments.clear();
	designations.clear();
}

Nebula::~Nebula()
{
}

QString Nebula::getMagnitudeInfoString(const StelCore *core, const InfoStringGroup& flags, const int decimals, const float& magOffset) const
{
	QString res;
	const float mmag = qMin(vMag, bMag);
	if (mmag < 50.f && flags&Magnitude)
	{
		QString emag = "";
		QString fsys = "";
		bool bmag = false;
		float mag = getVMagnitude(core) + magOffset;
		float mage = getVMagnitudeWithExtinction(core, mag, magOffset);
		bool hasAtmosphere = core->getSkyDrawer()->getFlagHasAtmosphere();
		QString tmag = q_("Magnitude");
		if (nType == NebDn || B_nb>0) // Dark nebulae or objects from Barnard catalog
			tmag = q_("Opacity");

		if (bMag < 50.f && vMag > 50.f)
		{
			fsys = QString("(%1 B").arg(q_("photometric passband"));
			if (hasAtmosphere)
				fsys.append(";");
			else
				fsys.append(")");
			mag = getBMagnitude(core);
			mage = getBMagnitudeWithExtinction(core);
			bmag = true;
		}

		const float airmass = getAirmass(core);
		if (nType != NebDn && B_nb==0 && airmass>-1.f) // Don't show extincted magnitude much below horizon where model is meaningless.
		{
			emag = QString("%1 <b>%2</b> %3 <b>%4</b> %5)").arg(q_("reduced to"), QString::number(mage, 'f', decimals), q_("by"), QString::number(airmass, 'f', 2), q_("Airmasses"));
			if (!bmag)
				emag = QString("(%1").arg(emag);
		}
		res = QString("%1: <b>%2</b> %3 %4<br />").arg(tmag, QString::number(mag, 'f', decimals), fsys, emag);
	}
	res += getExtraInfoStrings(Magnitude).join("");
	return res;
}

QString Nebula::getScreenLabel() const
{
	static StelSkyCultureMgr *scMgr=GETSTELMODULE(StelSkyCultureMgr);
	QStringList cLabels = getCultureLabels(scMgr->getScreenLabelStyle());

	// TODO: Decide whether SCs with DSO names should only show common names of these objects, or use common names for all objects.

	QString nameI18n = scMgr->currentSkycultureUsesCommonNames() ? getNameI18n() : QString();
	return (cLabels.isEmpty() ? nameI18n : cLabels.constFirst());
}

QString Nebula::getInfoLabel() const
{
	return getCultureLabels(GETSTELMODULE(StelSkyCultureMgr)->getInfoLabelStyle()).join(" - ");
}

QStringList Nebula::getCultureLabels(StelObject::CulturalDisplayStyle style) const
{
	static StelSkyCultureMgr *scMgr=GETSTELMODULE(StelSkyCultureMgr);
	QStringList labels;
	if (culturalNames.isEmpty())
		return labels;
	for (auto &cName: culturalNames)
		{
			const QString modernName= nameI18.isEmpty() ? getDSODesignation() : nameI18;
			labels << scMgr->createCulturalLabel(cName, style, modernName);
		}
	labels.removeDuplicates();
	labels.removeAll(QString(""));
	labels.removeAll(QString());
	return labels;
}


QString Nebula::getInfoString(const StelCore *core, const InfoStringGroup& flags) const
{
	// rtl tracks the right-to-left status of the text in the current position.
	const bool rtl = StelApp::getInstance().getLocaleMgr().isSkyRTL();
	QString str;
	QTextStream oss(&str);
	bool withDecimalDegree = StelApp::getInstance().getFlagUseDecDegreesOther();

	if ((flags&Name) || (flags&CatalogNumber))
		oss << (rtl ? "<h2 dir=\"rtl\">" : "<h2 dir=\"ltr\">");

	if (!culturalNames.isEmpty() && flags&Name)
		oss << getInfoLabel() << "<br/>";

	if (!nameI18.isEmpty() && flags&Name)
	{
		oss << getNameI18n();
		QString aliases = getI18nAliases();
		if (!aliases.isEmpty() && flagShowAdditionalNames)
			oss << " (" << aliases << ")";
	}

	if (flags&CatalogNumber)
	{	
		if (!nameI18.isEmpty() && !withoutID && flags&Name)
			oss << "<br>";

		oss << designations.join(" - ");
	}

	if ((flags&Name) || (flags&CatalogNumber))
		oss << "</h2>";

	if (flags&Name)
	{
		QStringList extraNames=getExtraInfoStrings(Name);
		if (!extraNames.isEmpty())
			oss << q_("Additional names: ") << extraNames.join(", ") << "<br/>";
	}
	if (flags&CatalogNumber)
	{
		QStringList extraCat=getExtraInfoStrings(CatalogNumber);
		if (!extraCat.isEmpty())
			oss << q_("Additional catalog numbers: ") << extraCat.join(", ") << "<br/>";
	}

	if (flags&ObjectType)
	{
		QString mt = getMorphologicalTypeString();
		if (mt.isEmpty())
			oss << QString("%1: <b>%2</b>").arg(q_("Type"), getObjectTypeI18n()) << "<br/>";
		else
			oss << QString("%1: <b>%2</b> (%3)").arg(q_("Type"), getObjectTypeI18n(), mt) << "<br/>";
		oss << getExtraInfoStrings(ObjectType).join("");
	}

	oss << getMagnitudeInfoString(core, flags, 2);

	if (flags&Extra)
	{
		if (vMag < 50 && bMag < 50)
			oss << QString("%1: <b>%2</b>").arg(q_("Color Index (B-V)"), QString::number(bMag-vMag, 'f', 2)) << "<br/>";
	}
	float mmag = qMin(vMag,bMag);
	if (nType != NebDn && mmag < 50 && flags&Extra)
	{
		QString sb = q_("Surface brightness");
		QString ae = q_("after extinction");
		QString mu;
		if (flagUseShortNotationSurfaceBrightness)
		{
			mu = QString("<sup>m</sup>/□'");
			if (flagUseArcsecSurfaceBrightness)
				mu = QString("<sup>m</sup>/□\"");
		}
		else
		{
			mu = QString("%1/%2<sup>2</sup>").arg(qc_("mag", "magnitude"), q_("arc-min"));
			if (flagUseArcsecSurfaceBrightness)
				mu = QString("%1/%2<sup>2</sup>").arg(qc_("mag", "magnitude"), q_("arc-sec"));
		}

		if (getSurfaceBrightness(core)<99.f)
		{
			if (getAirmass(core)>-1.f && getSurfaceBrightnessWithExtinction(core)<99.f) // Don't show extincted surface brightness much below horizon where model is meaningless.
			{
				oss << QString("%1: <b>%2</b> %5 (%3: <b>%4</b> %5)").arg(sb, QString::number(getSurfaceBrightness(core, flagUseArcsecSurfaceBrightness), 'f', 2),
				                                                          ae, QString::number(getSurfaceBrightnessWithExtinction(core, flagUseArcsecSurfaceBrightness), 'f', 2), mu) << "<br/>";
			}
			else
				oss << QString("%1: <b>%2</b> %3").arg(sb, QString::number(getSurfaceBrightness(core, flagUseArcsecSurfaceBrightness), 'f', 2), mu) << "<br/>";

			if (getContrastIndex(core)<99.f)
				oss << QString("%1: %2").arg(q_("Contrast index"), QString::number(getContrastIndex(core), 'f', 2)) << "<br/>";
		}
	}

	oss << getCommonInfoString(core, flags);

	if (flags&Size && majorAxisSize>0.f)
	{
		QString majorAxS, minorAxS, sizeAx = q_("Size");
		if (withDecimalDegree)
		{
			majorAxS = StelUtils::radToDecDegStr(static_cast<double>(majorAxisSize)*M_PI/180., 5, false, true);
			minorAxS = StelUtils::radToDecDegStr(static_cast<double>(minorAxisSize)*M_PI/180., 5, false, true);
		}
		else
		{
			majorAxS = StelUtils::radToDmsPStr(static_cast<double>(majorAxisSize)*M_PI/180., 2);
			minorAxS = StelUtils::radToDmsPStr(static_cast<double>(minorAxisSize)*M_PI/180., 2);
		}

		if (fuzzyEquals(majorAxisSize, minorAxisSize) || minorAxisSize==0.f)
			oss << QString("%1: %2").arg(sizeAx, majorAxS) << "<br/>";
		else
		{
			oss << QString("%1: %2 x %3").arg(sizeAx, majorAxS, minorAxS) << "<br/>";
			if (orientationAngle>0)
				oss << QString("%1: %2%3").arg(q_("Orientation angle")).arg(orientationAngle).arg(QChar(0x00B0)) << "<br/>";
		}
	}
	if (flags&Size)
		oss << getExtraInfoStrings(Size).join("");

	if (flags&Distance)
	{
		if (qAbs(parallax)>0.f)
		{
			QString dx;
			// distance in light years from parallax
			float distance = 3.162e-5f/(qAbs(parallax)*4.848e-9f);
			float distanceErr = 0.f;

			if (parallaxErr>0.f)
				distanceErr = qAbs(3.162e-5f/(qAbs(parallaxErr + parallax)*4.848e-9f) - distance);

			if (distanceErr>0.f)
				dx = QString("%1%2%3").arg(QString::number(distance, 'f', 3)).arg(QChar(0x00B1)).arg(QString::number(distanceErr, 'f', 3));
			else
				dx = QString("%1").arg(QString::number(distance, 'f', 3));

			if (oDistance==0.f)
			{
				// TRANSLATORS: Unit of measure for distance - Light Years
				QString ly = qc_("ly", "distance");
				oss << QString("%1: %2 %3").arg(q_("Distance"), dx, ly) << "<br/>";
			}
		}

		if (oDistance>0.f)
		{
			QString dx, dy;
			float dc = 3262.f;
			int ms = 1;
			//TRANSLATORS: Unit of measure for distance - kiloparsecs
			QString dupc = qc_("kpc", "distance");
			//TRANSLATORS: Unit of measure for distance - Light Years
			QString duly = qc_("ly", "distance");

			float distance = oDistance;
			float distanceErr = oDistanceErr;
			float distanceLY = oDistance*dc;
			float distanceErrLY= oDistanceErr*dc;
			if (oDistance>=1000.f)
			{
				distance = oDistance/1000.f;
				distanceErr = oDistanceErr/1000.f;
				//TRANSLATORS: Unit of measure for distance - Megaparsecs
				dupc = qc_("Mpc", "distance");
			}

			if (distanceLY>=1e6f)
			{
				distanceLY /= 1e6f;
				distanceErrLY /= 1e6f;
				ms = 3;
				//TRANSLATORS: Unit of measure for distance - Millions of Light Years
				duly = qc_("M ly", "distance");
			}

			if (oDistanceErr>0.f)
			{
				dx = QString("%1%2%3").arg(QString::number(distance, 'f', 3)).arg(QChar(0x00B1)).arg(QString::number(distanceErr, 'f', 3));
				dy = QString("%1%2%3").arg(QString::number(distanceLY, 'f', ms)).arg(QChar(0x00B1)).arg(QString::number(distanceErrLY, 'f', ms));
			}
			else
			{
				dx = QString("%1").arg(QString::number(distance, 'f', 3));
				dy = QString("%1").arg(QString::number(distanceLY, 'f', ms));
			}

			oss << QString("%1: %2 %3 (%4 %5)").arg(q_("Distance"), dx, dupc, dy, duly) << "<br/>";
		}
		oss << getExtraInfoStrings(Distance).join("");
	}

	if (flags&Extra)
	{
		if (redshift<99.f)
		{
			QString z;
			if (redshiftErr>0.f)
				z = QString("%1%2%3").arg(QString::number(redshift, 'f', 6)).arg(QChar(0x00B1)).arg(QString::number(redshiftErr, 'f', 6));
			else
				z = QString("%1").arg(QString::number(redshift, 'f', 6));

			oss << QString("%1: %2").arg(q_("Redshift"), z) << "<br/>";
		}
		if (qAbs(parallax)>0.f)
		{
			QString px;
			if (parallaxErr>0.f)
				px = QString("%1%2%3").arg(QString::number(qAbs(parallax), 'f', 3)).arg(QChar(0x00B1)).arg(QString::number(parallaxErr, 'f', 3));
			else
				px = QString("%1").arg(QString::number(qAbs(parallax), 'f', 3));

			oss << QString("%1: %2 %3").arg(q_("Parallax"), px, qc_("mas", "parallax")) << "<br/>";
		}
		if (!discoverer.isEmpty())
			oss << QString("%1: %2 (%3)").arg(q_("Discoverer"), discoverer, StelUtils::localeDiscoveryDateString(discoveryYear)) << "<br/>";
		if (!getMorphologicalTypeDescription().isEmpty())
			oss << StelUtils::wrapText(QString("%1: %2.").arg(q_("Morphological description"), getMorphologicalTypeDescription())) << "<br/>";
	}

	oss << getSolarLunarInfoString(core, flags);

	postProcessInfoString(str, flags);

	return str;
}

QVariantMap Nebula::getInfoMap(const StelCore *core) const
{
	QVariantMap map = StelObject::getInfoMap(core);

	map["type"]=getObjectTypeI18n(); // replace "Nebula" type by detail. This is localized.
	map.insert("morpho", getMorphologicalTypeString());
	map.insert("surface-brightness", getSurfaceBrightness(core));
	map.insert("designations", withoutID ? QString() : designations.join(" - "));
	map.insert("bmag", bMag);
	if (std::isfinite(oDistance) && oDistance > 0.f)
	{
		map.insert("distance", oDistance);
		map.insert("distance-unit", "kpc");
		map.insert("distance-error", oDistanceErr);
		map.insert("distance-method", "catalog");
	}
	else if (std::isfinite(parallax) && std::isfinite(parallaxErr) && (parallax != 0.f || parallaxErr > 0.f))
	{
		map.insert("distance-status", "low_confidence");
		if (parallax > 0.f && parallaxErr > 0.f && parallax / parallaxErr > 5.f)
		{
			const double distanceLy = PARSEC_LY * 1000. / parallax;
			map.insert("distance-ly", distanceLy);
			map.insert("distance-error-ly", distanceLy * parallaxErr / parallax);
			map.insert("distance-method", "inverse_parallax");
		}
	}
	if (vMag < 50 && bMag < 50)
		map.insert("bV", bMag-vMag);
	if (redshift<99.f)
		map.insert("redshift", redshift);

	double axisMajor = getAngularRadius(core)*(2.*M_PI_180);
	double axisMinor = getAngularRadius(core)*(2.*M_PI_180);
	int    axisPA    = 0;
	if (minorAxisSize>0.f)
	{
		axisMajor = majorAxisSize*M_PI_180;
		axisMinor = minorAxisSize*M_PI_180;
		axisPA    = orientationAngle;
	}
	map.insert("axis-major", axisMajor);
	map.insert("axis-major-dd", axisMajor*M_180_PI);
	map.insert("axis-major-deg", StelUtils::radToDecDegStr(axisMajor, 5));
	map.insert("axis-major-dms", StelUtils::radToDmsPStr(axisMajor, 2));
	map.insert("axis-minor", axisMinor);
	map.insert("axis-minor-dd", axisMinor*M_180_PI);
	map.insert("axis-minor-deg", StelUtils::radToDecDegStr(axisMinor, 5));
	map.insert("axis-minor-dms", StelUtils::radToDmsPStr(axisMinor, 2));
	map.insert("orientation-angle", axisPA);
	map.insert("cultural-names", getCultureLabels(StelObject::CulturalDisplayStyle::Native_Pronounce_Translit_Translated_IPA));

	// TODO: more? Names? Data?
	return map;
}

QString Nebula::getEnglishAliases() const
{
	QString aliases;
	int asize = englishAliases.size();
	if (asize!=0)
	{
		if (asize>2) // Special case for many AKA
		{
			bool firstLine = true;
			for(int i=1; i<=asize; i++)
			{
				aliases.append(englishAliases.at(i-1));
				if (i<asize)
					aliases.append(" - ");

				if ((i % 2)==0 && firstLine) // 2 AKA-items on first line!
				{
					aliases.append("<br />");
					firstLine = false;
				}
				if (i>3 && ((i-2) % 4)==0 && !firstLine &&  i<asize)
					aliases.append("<br />");
			}
		}
		else
			aliases = nameI18Aliases.join(" - ");
	}
	return aliases;
}

QString Nebula::getI18nAliases() const
{
	QString aliases;
	int asize = nameI18Aliases.size();
	if (asize!=0)
	{
		if (asize>2) // Special case for many AKA; NOTE: Should we add size to the config data for skyculture?
		{
			bool firstLine = true;
			for(int i=1; i<=asize; i++)
			{
				aliases.append(nameI18Aliases.at(i-1));
				if (i<asize)
					aliases.append(" - ");

				if ((i % 2)==0 && firstLine) // 2 AKA-items on first line!
				{
					aliases.append("<br />");
					firstLine = false;
				}
				if (i>3 && ((i-2) % 4)==0 && !firstLine &&  i<asize)
					aliases.append("<br />");
			}
		}
		else
			aliases = nameI18Aliases.join(" - ");
	}
	return aliases;
}

float Nebula::getVMagnitude(const StelCore* core) const
{
	Q_UNUSED(core)
	return vMag;
}

float Nebula::getBMagnitude(const StelCore* core) const
{
	Q_UNUSED(core)
	return bMag;
}

float Nebula::getBMagnitudeWithExtinction(const StelCore* core) const
{
	Vec3d altAzPos = getAltAzPosGeometric(core);
	altAzPos.normalize();
	float mag = getBMagnitude(core);
	// without the test, planets flicker stupidly in fullsky atmosphere-less view.
	if (core->getSkyDrawer()->getFlagHasAtmosphere())
		core->getSkyDrawer()->getExtinction().forward(altAzPos, &mag);
	return mag;
}

double Nebula::getAngularRadius(const StelCore *) const
{
	return static_cast<double>(0.5f*majorAxisSize);
}

float Nebula::getSelectPriority(const StelCore* core) const
{
	float selectPriority = StelObject::getSelectPriority(core);
	const NebulaMgr* nebMgr = (static_cast<NebulaMgr*>(StelApp::getInstance().getModuleMgr().getModule("NebulaMgr")));
	// minimize unwanted selection of the deep-sky objects
	if (!nebMgr->getFlagHints())
		return selectPriority+3.f;

	float mag = qMin(getVMagnitude(core), getBMagnitude(core));
	float lim = mag;
	float mLim = 15.0f;

	if (nType==NebRegion) // special case for regions
		mag = 3.f;

	if (!objectInDisplayedCatalog() || !objectInDisplayedType())
		return selectPriority+mLim;

	const StelSkyDrawer* drawer = core->getSkyDrawer();

	if (drawer->getFlagNebulaMagnitudeLimit() && (mag>static_cast<float>(drawer->getCustomNebulaMagnitudeLimit())))
		return selectPriority+mLim;

	const float maxMagHint = nebMgr->computeMaxMagHint(drawer);
	// make very easy to select if labeled
	if (surfaceBrightnessUsage)
	{
		lim = mag = getSurfaceBrightness(core);
		mLim += 1.f;
	}

	if (nType==NebDn)
		lim=mLim - mag - 2.0f*qMin(1.5f, majorAxisSize); // Note that "mag" field is used for opacity in this catalog!
	else if (nType==NebHII) // Sharpless and LBN
		lim=10.0f - 2.0f*qMin(1.5f, majorAxisSize); // Unfortunately, in Sh catalog, we always have mag=99=unknown!

	if (std::min(mLim, lim)<=maxMagHint || !outlineSegments.empty() || nType==NebRegion) // High priority for big DSO (with outlines) or regions
		selectPriority = -10.f;
	else
		selectPriority -= 5.f;

	return selectPriority;
}

Vec3f Nebula::getInfoColor(void) const
{
	return (static_cast<NebulaMgr*>(StelApp::getInstance().getModuleMgr().getModule("NebulaMgr")))->getLabelsColor();
}

double Nebula::getCloseViewFov(const StelCore*) const
{
	return majorAxisSize>0.f ? static_cast<double>(majorAxisSize) * 4. : 1.;
}

float Nebula::getSurfaceBrightness(const StelCore* core, bool arcsec) const
{
	const float sq = (arcsec ? 3600.f*3600.f : 3600.f); // arcsec^2 or arcmin^2
	const float mag = qMin(getVMagnitude(core), getBMagnitude(core));
	if (mag<99.f && majorAxisSize>0.f && nType!=NebDn)
		return mag + 2.5f*log10f(getSurfaceArea()*sq);
	else
		return 99.f;
}

float Nebula::getSurfaceBrightnessWithExtinction(const StelCore* core, bool arcsec) const
{
	const float sq = (arcsec ? 3600.f*3600.f : 3600.f); // arcsec^2 or arcmin^2
	const float mag = qMin(getVMagnitudeWithExtinction(core), getBMagnitudeWithExtinction(core));
	if (mag<99.f && majorAxisSize>0.f && nType!=NebDn)
		return mag + 2.5f*log10f(getSurfaceArea()*sq);
	else
		return 99.f;
}

float Nebula::getContrastIndex(const StelCore* core) const
{
	// Compute an extended object's contrast index: http://www.unihedron.com/projects/darksky/NELM2BCalc.html

	// Sky brightness
	const auto luminance = core->getSkyDrawer()->getLightPollutionLuminance();
	const float B_mpsas = StelCore::luminanceToMPSAS(luminance);
	// Compute an extended object's contrast index
	// Source: Clark, R.N., 1990. Appendix E in Visual Astronomy of the Deep Sky, Cambridge University Press and Sky Publishing.
	// URL: http://www.clarkvision.com/visastro/appendix-e.html
	const float emag = getSurfaceBrightnessWithExtinction(core, true);
	if (emag<99.f)
		return -0.4f * (emag - B_mpsas);
	else
		return 99.f;
}

float Nebula::getSurfaceArea(void) const
{
	if (minorAxisSize==0.f)
		return M_PIf*(majorAxisSize/2.f)*(majorAxisSize/2.f); // S = pi*R^2 = pi*(D/2)^2
	else
		return M_PIf*(majorAxisSize/2.f)*(minorAxisSize/2.f); // S = pi*a*b
}

Vec3f Nebula::getHintColor(Nebula::NebulaType nType)
{
	return hintColorMap.value(nType, hintColorMap.value(NebUnknown));
}

float Nebula::getVisibilityLevelByMagnitude(void) const
{
	StelCore* core = StelApp::getInstance().getCore();

	const float mLim = 15.0f;
	float lim = qMin(vMag, bMag);

	if (surfaceBrightnessUsage)
	{
		lim = getSurfaceBrightness(core) - 3.f;
		if (lim > 90.f) lim = mLim + 1.f;
	}
	else
	{
		if (lim > 90.f) lim = mLim;

		// Dark nebulae. Not sure how to assess visibility from opacity? --GZ
		if (nType==NebDn)
		{
			const float mag = getVMagnitude(core);
			// GZ: ad-hoc visibility formula: assuming good visibility if objects of mag9 are visible, "usual" opacity 5 and size 30', better visibility (discernability) comes with higher opacity and larger size,
			// 9-(opac-5)-2*(angularSize-0.5)
			// GZ Not good for non-Barnards. weak opacity and large surface are antagonists. (some LDN are huge, but opacity 2 is not much to discern).
			// The qMin() maximized the visibility gain for large objects.
			if (majorAxisSize>0.f && mag<90.f)
				lim = mLim - mag - 2.0f*qMin(majorAxisSize, 1.5f);
			else
				lim = (B_nb>0 ? 9.0f : 12.0f); // GZ I assume LDN objects are rather elusive.
		}
		else if (nType==NebHII) // NebHII={Sharpless, LBN, RCW} but also M42.
		{
			// artificially increase visibility of (most) Sharpless and LBN objects. No magnitude recorded:-(
			lim=qMin(lim, 10.0f);
		}
		if (hasBuiltInTexture)
		{
			// Built-in photographed DSOs with missing or dim catalog magnitude (e.g. Sh 2-216,
			// Sh 2-240, vdB, Abell PN) stay quiet at wide FOV and reveal cleanly once zoomed in.
			const float texLim = (majorAxisSize > 0.f)
				? (11.2f - 2.0f * qMin(majorAxisSize, 1.5f))
				: 11.2f;
			lim = qMin(lim, texLim);
		}
	}

	if (nType==NebRegion) // special case for regions
		lim=3.0f;

	return lim;
}

void Nebula::drawOutlines(StelPainter &sPainter, float alpha, const Vec3d& aberration, bool useAberration) const
{
	sPainter.setColor(getHintColor(nType), alpha);
	sPainter.setLineWidth(1.f * sPainter.getProjector()->getScreenScale());
	sPainter.setBlending(true);
	sPainter.setLineSmooth(true);
	const auto& projector = sPainter.getProjector();
	const SphericalCap& viewportHalfspace = projector->getBoundingCap();
	QVarLengthArray<Vec3f, 256> vertices;
	const auto flush = [&]()
	{
		if (vertices.isEmpty())
			return;
		sPainter.enableClientStates(true);
		sPainter.setVertexPointer(3, GL_FLOAT, vertices.constData());
		sPainter.drawFromArray(StelPainter::Lines, vertices.size(), 0, false);
		sPainter.enableClientStates(false);
		vertices.clear();
	};
	const auto apparentPosition = [&](Vec3d point)
	{
		if (useAberration)
		{
			point += aberration;
			point.normalize();
		}
		return point;
	};
	for (const auto* points : outlineSegments)
	{
		if (points->size() < 2)
			continue;
		Vec3d point1 = apparentPosition(points->front());
		for (size_t index = 1; index < points->size(); ++index)
		{
			const Vec3d point2 = apparentPosition(points->at(index));
			Vec3d screen1, screen2;
			bool batched = false;
			if (viewportHalfspace.contains(point1) && viewportHalfspace.contains(point2)
				&& !projector->intersectViewportDiscontinuity(point1, point2)
				&& projector->projectCheck(point1, screen1) && projector->projectCheck(point2, screen2))
			{
				Vec3d midpoint = point1 + point2;
				if (midpoint.normSquared() > 1e-12)
				{
					midpoint.normalize();
					if (projector->projectInPlace(midpoint)
						&& NebulaDrawing::canBatchArc(static_cast<float>(screen1[0] - midpoint[0]),
							static_cast<float>(screen1[1] - midpoint[1]),
							static_cast<float>(screen2[0] - midpoint[0]),
							static_cast<float>(screen2[1] - midpoint[1])))
					{
						vertices.append(Vec3f(screen1[0], screen1[1], 1.f));
						vertices.append(Vec3f(screen2[0], screen2[1], 1.f));
						batched = true;
						if (vertices.size() == 256)
							flush();
					}
				}
			}
			if (!batched)
			{
				flush();
				sPainter.drawGreatCircleArc(point1, point2, &viewportHalfspace);
			}
			point1 = point2;
		}
	}
	flush();
	sPainter.setLineSmooth(false);
}

namespace
{
struct SkyMarkerFrame
{
	Vec3d center;
	Vec3d majorAxis;
	Vec3d minorAxis;
	double majorRad = 0.0;
	double minorRad = 0.0;
	float majorPx = 0.f;
	float scale = 1.f;
	bool valid = false;
};

SkyMarkerFrame buildSkyMarkerFrame(StelPainter& sPainter, const Vec3d& direction,
                                   float sizeLogical, float majorAxisDeg, float minorAxisDeg,
                                   int orientationAngleDeg, bool proportional, float defaultMinorRatio)
{
	SkyMarkerFrame f;
	const auto& prj = sPainter.getProjector();
	f.scale = prj->getScreenScale();
	const double pixPerRad = static_cast<double>(prj->getPixelPerRadAtCenter());
	if (pixPerRad <= 1e-6 || direction.normSquared() <= 1e-12)
		return f;

	f.center = direction;
	f.center.normalize();

	// Exact J2000 orthonormal tangent basis: celestial North and East (N x d).
	Vec3d north(0.0, 0.0, 1.0);
	north -= f.center * f.center[2];
	if (north.normSquared() < 1e-10)
		north = Vec3d(1.0, 0.0, 0.0);
	else
		north.normalize();
	Vec3d east = north ^ f.center;
	east.normalize();

	// Astronomical Position Angle (PA): degrees East of North.
	const double paRad = static_cast<double>(orientationAngleDeg) * M_PI_180;
	f.majorAxis = north * std::cos(paRad) + east * std::sin(paRad);
	f.minorAxis = north * (-std::sin(paRad)) + east * std::cos(paRad);

	const double iconRad = (static_cast<double>(sizeLogical) * static_cast<double>(f.scale)) / pixPerRad;
	const bool hasRealSize = proportional && majorAxisDeg > 0.f;
	const double realMajorRad = hasRealSize ? (0.5 * static_cast<double>(majorAxisDeg) * M_PI_180) : iconRad;
	f.majorRad = std::max(realMajorRad, iconRad);

	double ratio = static_cast<double>(defaultMinorRatio);
	if (majorAxisDeg > 0.f && minorAxisDeg > 0.f)
		ratio = std::clamp(static_cast<double>(minorAxisDeg) / static_cast<double>(majorAxisDeg), 0.14, 1.0);

	// Keep zoomed-out elongated markers legible while preserving true ratios when zoomed in.
	const double minMinorRad = (2.5 * static_cast<double>(f.scale)) / pixPerRad;
	f.minorRad = std::max(f.majorRad * ratio, std::min(f.majorRad, minMinorRad));
	f.majorPx = static_cast<float>(f.majorRad * pixPerRad);
	f.valid = true;
	return f;
}

inline bool projectSkyMarkerPoint(const StelProjectorP& prj, const SkyMarkerFrame& f,
                                  double u, double v, Vec3d& skyOut, Vec3d& screenOut)
{
	const double du = u * f.majorRad;
	const double dv = v * f.minorRad;
	const double r = std::hypot(du, dv);
	if (r > 1e-10)
	{
		const double rClamped = std::min(r, 1.35);
		const double cr = std::cos(rClamped);
		const double sr = std::sin(rClamped) / r;
		skyOut = f.center * cr + (f.majorAxis * du + f.minorAxis * dv) * sr;
	}
	else
	{
		skyOut = f.center;
	}
	return prj->project(skyOut, screenOut);
}

void drawSkyMarkerPolyline(StelPainter& sPainter, const SkyMarkerFrame& f,
                           const QVarLengthArray<Vec2f, 256>& normPts, bool closed)
{
	const auto& prj = sPainter.getProjector();
	const int count = normPts.size();
	if (count < 2)
		return;

	QVarLengthArray<float, 512> seg;
	seg.reserve((count + 1) * 2);
	Vec3d prevSky(0.0);
	bool hasPrev = false;

	auto flushSeg = [&]()
	{
		if (seg.size() >= 4)
		{
			sPainter.setVertexPointer(2, GL_FLOAT, seg.constData());
			sPainter.drawFromArray(StelPainter::LineStrip, seg.size() / 2, 0, false);
		}
		seg.clear();
		hasPrev = false;
	};

	const int total = closed ? (count + 1) : count;
	for (int i = 0; i < total; ++i)
	{
		const Vec2f& p = normPts[i % count];
		Vec3d sky, scr;
		if (!projectSkyMarkerPoint(prj, f, static_cast<double>(p[0]), static_cast<double>(p[1]), sky, scr))
		{
			flushSeg();
			continue;
		}
		if (hasPrev && prj->intersectViewportDiscontinuity(prevSky, sky))
		{
			flushSeg();
		}
		seg.push_back(static_cast<float>(scr[0]));
		seg.push_back(static_cast<float>(scr[1]));
		prevSky = sky;
		hasPrev = true;
	}
	flushSeg();
}
} // anonymous namespace

void Nebula::renderDarkNebulaMarker(StelPainter& sPainter, const Vec3d& direction,
                                    float size, const Vec3f color, float alpha) const
{
	const SkyMarkerFrame f = buildSkyMarkerFrame(sPainter, direction, size,
	                                             majorAxisSize, minorAxisSize, orientationAngle,
	                                             drawHintProportional, 1.0f);
	if (!f.valid)
		return;

	// 4 sky-projected superellipse corner arcs leaving clean cardinal gaps.
	const int ptsPerArc = std::clamp(int(std::lround(f.majorPx / 8.f)), 8, 24);
	constexpr float gapRad = 0.22f; // ~12.6 deg gap on each side of the 4 cardinal midpoints
	constexpr float superExp = 0.625f; // superellipse p = 3.2 (sleek rounded rectangle)

	sPainter.setBlending(true);
	sPainter.setLineSmooth(true);
	sPainter.setLineWidth(f.scale * std::clamp(f.majorPx / 52.f, 0.95f, 1.75f));
	const float drawAlpha = (f.majorPx > 40.f * f.scale) ? (alpha * 0.88f) : alpha;
	sPainter.setColor(color, drawAlpha);
	sPainter.enableClientStates(true);

	QVarLengthArray<Vec2f, 256> arcPts;
	arcPts.reserve(ptsPerArc);
	for (int q = 0; q < 4; ++q)
	{
		arcPts.clear();
		const float startAngle = q * (M_PIf * 0.5f) + gapRad;
		const float endAngle = (q + 1) * (M_PIf * 0.5f) - gapRad;
		for (int i = 0; i < ptsPerArc; ++i)
		{
			const float t = startAngle + (endAngle - startAngle) * (static_cast<float>(i) / static_cast<float>(ptsPerArc - 1));
			const float ct = std::cos(t);
			const float st = std::sin(t);
			const float u = std::copysign(std::pow(std::abs(ct), superExp), ct);
			const float v = std::copysign(std::pow(std::abs(st), superExp), st);
			arcPts.append(Vec2f(u, v));
		}
		drawSkyMarkerPolyline(sPainter, f, arcPts, false);
	}
	sPainter.enableClientStates(false);
}

void Nebula::renderMarkerRoundedRect(StelPainter& sPainter, const Vec3d& direction,
                                     float size, const Vec3f color, float alpha) const
{
	const SkyMarkerFrame f = buildSkyMarkerFrame(sPainter, direction, size,
	                                             majorAxisSize, minorAxisSize, orientationAngle,
	                                             drawHintProportional, 1.0f);
	if (!f.valid)
		return;

	// Sky-projected superellipse (p = 3.2): keeps Stellarium's rounded-rect nebula identity
	// while accurately matching real major/minor axes and astronomical position angle.
	const int numPoints = std::clamp(int(std::lround(f.majorPx / 2.5f)), 36, 160);
	const float* const cossin = StelUtils::ComputeCosSinTheta(numPoints);
	constexpr float superExp = 0.625f;
	QVarLengthArray<Vec2f, 256> normPts;
	normPts.reserve(numPoints);
	for (int n = 0; n < numPoints; ++n)
	{
		const float ct = cossin[2 * n];
		const float st = cossin[2 * n + 1];
		const float u = std::copysign(std::pow(std::abs(ct), superExp), ct);
		const float v = std::copysign(std::pow(std::abs(st), superExp), st);
		normPts.append(Vec2f(u, v));
	}

	sPainter.setBlending(true);
	sPainter.setLineSmooth(true);
	sPainter.setLineWidth(f.scale * std::clamp(f.majorPx / 52.f, 0.95f, 1.75f));
	const float drawAlpha = (f.majorPx > 40.f * f.scale) ? (alpha * 0.88f) : alpha;
	sPainter.setColor(color, drawAlpha);
	sPainter.enableClientStates(true);
	drawSkyMarkerPolyline(sPainter, f, normPts, true);
	sPainter.enableClientStates(false);
}

void Nebula::renderRoundMarker(StelPainter& sPainter, const Vec3d& direction,
                               float size, const Vec3f color, const bool crossed, float alpha) const
{
	// Round markers (globular clusters, planetary nebulae) stay circular so bogus minorAxis
	// entries in PN catalogs (e.g. Sh 2-216) don't squash a round nebula ring into a narrow oval.
	const SkyMarkerFrame f = buildSkyMarkerFrame(sPainter, direction, size,
	                                             majorAxisSize, 0.f, orientationAngle,
	                                             drawHintProportional, 1.0f);
	if (!f.valid)
		return;

	const int numPoints = std::clamp(int(std::lround(f.majorPx / 2.5f)), 32, 160);
	const float* const cossin = StelUtils::ComputeCosSinTheta(numPoints);
	QVarLengthArray<Vec2f, 256> normPts;
	normPts.reserve(numPoints);
	for (int n = 0; n < numPoints; ++n)
		normPts.append(Vec2f(cossin[2 * n], cossin[2 * n + 1]));

	sPainter.setBlending(true);
	sPainter.setLineSmooth(true);
	sPainter.setLineWidth(f.scale * std::clamp(f.majorPx / 45.f, 0.95f, 1.7f));
	const float drawAlpha = (f.majorPx > 40.f * f.scale) ? (alpha * 0.88f) : alpha;
	sPainter.setColor(color, drawAlpha);
	sPainter.enableClientStates(true);
	drawSkyMarkerPolyline(sPainter, f, normPts, true);
	if (crossed)
	{
		QVarLengthArray<Vec2f, 256> crossU;
		crossU.append(Vec2f(-1.f, 0.f));
		crossU.append(Vec2f( 1.f, 0.f));
		drawSkyMarkerPolyline(sPainter, f, crossU, false);

		QVarLengthArray<Vec2f, 256> crossV;
		crossV.append(Vec2f(0.f, -1.f));
		crossV.append(Vec2f(0.f,  1.f));
		drawSkyMarkerPolyline(sPainter, f, crossV, false);
	}
	else if (nType == NebPn || nType == NebPossPN || nType == NebPPN)
	{
		// Classic astronomical planetary nebula symbol: crisp circle + 4 short outward ticks.
		const float tickExt = 1.f + std::clamp(8.f * f.scale / std::max(1.f, f.majorPx), 0.14f, 0.45f);
		const Vec2f dirs[4] = {Vec2f(1.f, 0.f), Vec2f(-1.f, 0.f), Vec2f(0.f, 1.f), Vec2f(0.f, -1.f)};
		for (const Vec2f& dir : dirs)
		{
			QVarLengthArray<Vec2f, 256> tick;
			tick.append(dir);
			tick.append(dir * tickExt);
			drawSkyMarkerPolyline(sPainter, f, tick, false);
		}
	}
	sPainter.enableClientStates(false);
}

void Nebula::renderEllipticMarker(StelPainter& sPainter, const Vec3d& direction, float size,
                                  const float aspectRatio, const Vec3f color, float alpha) const
{
	const float defaultMinorRatio = (aspectRatio > 0.f) ? std::clamp(1.f / aspectRatio, 0.14f, 1.0f) : 0.5f;
	const SkyMarkerFrame f = buildSkyMarkerFrame(sPainter, direction, size,
	                                             majorAxisSize, minorAxisSize, orientationAngle,
	                                             drawHintProportional, defaultMinorRatio);
	if (!f.valid)
		return;

	const int numPoints = std::clamp(int(std::lround(f.majorPx / 2.5f)), 36, 160);
	const float* const cossin = StelUtils::ComputeCosSinTheta(numPoints);
	QVarLengthArray<Vec2f, 256> normPts;
	normPts.reserve(numPoints);
	for (int n = 0; n < numPoints; ++n)
		normPts.append(Vec2f(cossin[2 * n], cossin[2 * n + 1]));

	sPainter.setBlending(true);
	sPainter.setLineSmooth(true);
	sPainter.setLineWidth(f.scale * std::clamp(f.majorPx / 55.f, 0.9f, 1.65f));
	const float drawAlpha = (f.majorPx > 40.f * f.scale) ? (alpha * 0.85f) : alpha;
	sPainter.setColor(color, drawAlpha);
	sPainter.enableClientStates(true);
	drawSkyMarkerPolyline(sPainter, f, normPts, true);
	sPainter.enableClientStates(false);
}

void Nebula::renderMarkerPointedCircle(StelPainter& sPainter, const Vec3d& direction,
                                       float size, const Vec3f color, const bool insideRect, float alpha) const
{
	SkyMarkerFrame f = buildSkyMarkerFrame(sPainter, direction, size,
	                                       majorAxisSize, minorAxisSize, orientationAngle,
	                                       drawHintProportional, 1.0f);
	if (!f.valid)
		return;

	if (insideRect && f.majorPx > 12.f * f.scale)
	{
		const double shrink = std::max(0.75, 1.0 - (4.5 * static_cast<double>(f.scale)) / static_cast<double>(f.majorPx));
		f.majorRad *= shrink;
		f.minorRad *= shrink;
		f.majorPx = static_cast<float>(f.majorPx * shrink);
	}

	// Octave binary-subdivision sky-projected dashed ellipse:
	// N = 2^level primary dashes stay anchored at fixed angles with constant screen length;
	// as the user zooms in (t: 0 -> 1), N midpoint child dashes fade in and bloom symmetrically
	// right out of the center of every gap, handing off seamlessly to 2N dashes at t = 1.
	const auto& prj = sPainter.getProjector();
	const double aPx = static_cast<double>(f.majorPx);
	const double bPx = aPx * (f.majorRad > 1e-12 ? (f.minorRad / f.majorRad) : 1.0);
	const double h = ((aPx - bPx) * (aPx - bPx)) / std::max(1.0, (aPx + bPx) * (aPx + bPx));
	const double perimPx = M_PI * (aPx + bPx) * (1.0 + (3.0 * h) / (10.0 + std::sqrt(std::max(0.0, 4.0 - 3.0 * h))));

	const double targetPitchPx = 13.5 * static_cast<double>(f.scale);
	const double rawN = std::clamp(perimPx / std::max(4.0, targetPitchPx), 8.0, 256.0);
	const double fLevel = std::log2(rawN);
	const int level = std::clamp(static_cast<int>(std::floor(fLevel)), 3, 7); // N in {8, 16, 32, 64, 128} -> up to 256 dashes
	const float t = static_cast<float>(std::clamp(fLevel - static_cast<double>(level), 0.0, 1.0));
	const int baseN = 1 << level;

	const double sectorRad = (2.0 * M_PI) / static_cast<double>(baseN);
	// Smoothly narrow primary angular half-width by 2^(-t) so its screen pixel length stays constant!
	const double primaryHalfRad = 0.25 * sectorRad * std::pow(2.0, -static_cast<double>(t));
	const float smoothLen = std::clamp((t - 0.06f) / 0.88f, 0.f, 1.f);
	const float childLenFactor = smoothLen * smoothLen * (3.f - 2.f * smoothLen);
	const double childHalfRad = 0.125 * sectorRad * static_cast<double>(childLenFactor);
	const float smoothAlpha = std::clamp((t - 0.08f) / 0.68f, 0.f, 1.f);
	const float childAlphaFactor = smoothAlpha * smoothAlpha * (3.f - 2.f * smoothAlpha);

	const int subSegs = (f.majorPx > 90.f * f.scale) ? 3 : 2;
	auto appendArcSegments = [&](QVarLengthArray<float, 1024>& verts, double centerAngle, double halfAngle)
	{
		if (halfAngle <= 1e-5)
			return;
		Vec3d prevSky(0.0), prevScr(0.0);
		bool hasPrev = false;
		for (int s = 0; s <= subSegs; ++s)
		{
			const double ang = centerAngle - halfAngle + (2.0 * halfAngle) * (static_cast<double>(s) / static_cast<double>(subSegs));
			Vec3d sky, scr;
			if (!projectSkyMarkerPoint(prj, f, std::cos(ang), std::sin(ang), sky, scr))
			{
				hasPrev = false;
				continue;
			}
			if (hasPrev && !prj->intersectViewportDiscontinuity(prevSky, sky))
			{
				verts.push_back(static_cast<float>(prevScr[0]));
				verts.push_back(static_cast<float>(prevScr[1]));
				verts.push_back(static_cast<float>(scr[0]));
				verts.push_back(static_cast<float>(scr[1]));
			}
			prevSky = sky;
			prevScr = scr;
			hasPrev = true;
		}
	};

	QVarLengthArray<float, 1024> primaryVerts;
	primaryVerts.reserve(baseN * subSegs * 4);
	for (int k = 0; k < baseN; ++k)
		appendArcSegments(primaryVerts, static_cast<double>(k) * sectorRad, primaryHalfRad);

	if (primaryVerts.size() < 4)
		return;

	sPainter.setBlending(true);
	sPainter.setLineSmooth(true);
	sPainter.setLineWidth(f.scale * std::clamp(f.majorPx / 55.f, 0.9f, 1.6f));
	const float drawAlpha = (f.majorPx > 40.f * f.scale) ? (alpha * 0.85f) : alpha;
	sPainter.enableClientStates(true);

	sPainter.setColor(color, drawAlpha);
	sPainter.setVertexPointer(2, GL_FLOAT, primaryVerts.constData());
	sPainter.drawFromArray(StelPainter::Lines, primaryVerts.size() / 2, 0, false);

	if (childAlphaFactor > 0.01f && childHalfRad > 1e-5)
	{
		QVarLengthArray<float, 1024> childVerts;
		childVerts.reserve(baseN * subSegs * 4);
		for (int k = 0; k < baseN; ++k)
			appendArcSegments(childVerts, (static_cast<double>(k) + 0.5) * sectorRad, childHalfRad);

		if (childVerts.size() >= 4)
		{
			sPainter.setColor(color, drawAlpha * childAlphaFactor);
			sPainter.setVertexPointer(2, GL_FLOAT, childVerts.constData());
			sPainter.drawFromArray(StelPainter::Lines, childVerts.size() / 2, 0, false);
		}
	}

	sPainter.enableClientStates(false);
}

float Nebula::getHintSize(StelPainter& sPainter) const
{
	const float size = 6.0f;
	float scaledSize = 0.0f;
	// Should getPixelPerRadAtCenter() not adjust for HiDPI? Apparently it does not!
	if (drawHintProportional)
	{
		const float scale = sPainter.getProjector()->getScreenScale();
		const float angularRadiusAtCenter = static_cast<float>(getAngularRadius(nullptr)) * M_PI_180f;
		const float pixPerRadAtCenter = static_cast<float>(sPainter.getProjector()->getPixelPerRadAtCenter());
		scaledSize = angularRadiusAtCenter * pixPerRadAtCenter / scale;
	}
	// TODO: Is it correct that for NebRegions any catalog data for getAngularRadius() is ignored? And that NebRegions are ALWAYS drawn with larger symbol?
	if (nType==NebRegion)
		scaledSize = 12.f;

	return qMax(size, scaledSize);
}

void Nebula::drawHints(StelPainter& sPainter, float alpha, const Vec3d& direction) const
{
	Vec3f color = getHintColor(nType);
	float finalSize = getHintSize(sPainter);

	switch (nType)
	{
		case NebGx:
		case NebIGx:
		case NebAGx:
		case NebQSO:
		case NebPossQSO:
		case NebBLL:
		case NebBLA:
		case NebRGx:
		case NebGxCl:
		{
			renderEllipticMarker(sPainter, direction, finalSize, 2.f, color, alpha);
			return;
		}
		case NebOc:
		case NebSA:
		case NebSC:
		case NebCl:
		case NebPartOfGx:
			renderMarkerPointedCircle(sPainter, direction, finalSize, color, false, alpha);
			return;
		case NebGc:
			renderRoundMarker(sPainter, direction, finalSize, color, true, alpha);
			return;
		case NebN:
		case NebHII:
		case NebISM:
		case NebMolCld:
		case NebYSO:
		case NebRn:
		case NebSNR:
		case NebBn:
		case NebEn:
		case NebSNC:
		case NebSNRC:
			renderMarkerRoundedRect(sPainter, direction, finalSize, color, alpha);
			return;
		case NebPn:
		case NebPossPN:
		case NebPPN:
			renderRoundMarker(sPainter, direction, finalSize, color, false, alpha);
			return;
		case NebDn:
			renderDarkNebulaMarker(sPainter, direction, finalSize, color, alpha);
			return;
		case NebCn:
		{
			renderMarkerRoundedRect(sPainter, direction, finalSize, getHintColor(NebN), alpha);
			renderMarkerPointedCircle(sPainter, direction, finalSize, getHintColor(NebCl), true, alpha);
			return;
		}
		case NebRegion:
			Nebula::texRegion->bind();
			break;
		case NebEMO:
		case NebStar:
		case NebSymbioticStar:
		case NebEmissionLineStar:
		case NebUnknown:
		//default: // keep this commented out to let clangd warn us of unhandled cases!
			renderRoundMarker(sPainter, direction, finalSize, color, false, alpha);
			return;
	}

	sPainter.setColor(color, alpha);
	sPainter.setBlending(true, GL_SRC_ALPHA, GL_ONE);

	sPainter.drawSprite2dMode(static_cast<float>(XY[0]), static_cast<float>(XY[1]), finalSize);
}

void Nebula::drawLabel(StelPainter& sPainter, float alpha, const QString& text, float shift) const
{
	sPainter.setColor(labelColor, alpha);
	sPainter.drawText(static_cast<float>(XY[0]), static_cast<float>(XY[1]), text, 0, shift, shift, false);
}

QString Nebula::getDSODesignation() const
{
	QString str = "";
	// Get designation for DSO with priority as given here.
	if (catalogFilters&CatM && M_nb>0)
		str = QString("M %1").arg(M_nb);
	else if (catalogFilters&CatC && C_nb>0)
		str = QString("C %1").arg(C_nb);
	else if (catalogFilters&CatNGC && NGC_nb>0)
		str = QString("NGC %1").arg(NGC_nb);
	else if (catalogFilters&CatIC && IC_nb>0)
		str = QString("IC %1").arg(IC_nb);
	else if (catalogFilters&CatB && B_nb>0)
		str = QString("B %1").arg(B_nb);
	else if (catalogFilters&CatSh2 && Sh2_nb>0)
		str = QString("SH 2-%1").arg(Sh2_nb);
	else if (catalogFilters&CatVdB && VdB_nb>0)
		str = QString("vdB %1").arg(VdB_nb);
	else if (catalogFilters&CatRCW && RCW_nb>0)
		str = QString("RCW %1").arg(RCW_nb);
	else if (catalogFilters&CatLDN && LDN_nb>0)
		str = QString("LDN %1").arg(LDN_nb);
	else if (catalogFilters&CatLBN && LBN_nb > 0)
		str = QString("LBN %1").arg(LBN_nb);
	else if (catalogFilters&CatCr && Cr_nb > 0)
		str = QString("Cr %1").arg(Cr_nb);
	else if (catalogFilters&CatMel && Mel_nb > 0)
		str = QString("Mel %1").arg(Mel_nb);
	else if (catalogFilters&CatPGC && PGC_nb > 0)
		str = QString("PGC %1").arg(PGC_nb);
	else if (catalogFilters&CatUGC && UGC_nb > 0)
		str = QString("UGC %1").arg(UGC_nb);
	else if (catalogFilters&CatCed && !Ced_nb.isEmpty())
		str = QString("Ced %1").arg(Ced_nb);
	else if (catalogFilters&CatArp && Arp_nb > 0)
		str = QString("Arp %1").arg(Arp_nb);
	else if (catalogFilters&CatVV && VV_nb > 0)
		str = QString("VV %1").arg(VV_nb);
	else if (catalogFilters&CatPK && !PK_nb.isEmpty())
		str = QString("PK %1").arg(PK_nb);
	else if (catalogFilters&CatPNG && !PNG_nb.isEmpty())
		str = QString("PN G%1").arg(PNG_nb);
	else if (catalogFilters&CatSNRG && !SNRG_nb.isEmpty())
		str = QString("SNR G%1").arg(SNRG_nb);
	else if (catalogFilters&CatACO && !ACO_nb.isEmpty())
		str = QString("Abell %1").arg(ACO_nb);
	else if (catalogFilters&CatHCG && !HCG_nb.isEmpty())
		str = QString("HCG %1").arg(HCG_nb);	
	else if (catalogFilters&CatESO && !ESO_nb.isEmpty())
		str = QString("ESO %1").arg(ESO_nb);
	else if (catalogFilters&CatVdBH && !VdBH_nb.isEmpty())
		str = QString("vdBH %1").arg(VdBH_nb);
	else if (catalogFilters&CatDWB && DWB_nb > 0)
		str = QString("DWB %1").arg(DWB_nb);
	else if (catalogFilters&CatTr && Tr_nb > 0)
		str = QString("Tr %1").arg(Tr_nb);
	else if (catalogFilters&CatSt && St_nb > 0)
		str = QString("St %1").arg(St_nb);
	else if (catalogFilters&CatRu && Ru_nb > 0)
		str = QString("Ru %1").arg(Ru_nb);
	else if (catalogFilters&CatVdBHa && VdBHa_nb > 0)
		str = QString("vdB-Ha %1").arg(VdBHa_nb);

	if (str.isEmpty() && hasBuiltInTexture && !designations.isEmpty())
		str = designations.constFirst();

	return str;
}

QString Nebula::getDSODesignationWIC() const
{
	if (!withoutID)
		return designations.first();
	else
		return QString();
}


void Nebula::readDSO(QDataStream &in)
{
	float	ra, dec;
	unsigned int oType; // Kludge for MSVC2017

	in	>> DSO_nb >> ra >> dec >> bMag >> vMag >> oType >> mTypeString >> majorAxisSize >> minorAxisSize
		>> orientationAngle >> redshift >> redshiftErr >> parallax >> parallaxErr >> oDistance >> oDistanceErr
		>> NGC_nb >> IC_nb >> M_nb >> C_nb >> B_nb >> Sh2_nb >> VdB_nb >> RCW_nb >> LDN_nb >> LBN_nb >> Cr_nb
		>> Mel_nb >> PGC_nb >> UGC_nb >> Ced_nb >> Arp_nb >> VV_nb >> PK_nb >> PNG_nb >> SNRG_nb >> ACO_nb
		>> HCG_nb >> ESO_nb >> VdBH_nb >> DWB_nb >> Tr_nb >> St_nb >> Ru_nb >> VdBHa_nb;

	Ced_nb = Ced_nb.trimmed();
	PK_nb = PK_nb.trimmed();
	PNG_nb = PNG_nb.trimmed();
	SNRG_nb = SNRG_nb.trimmed();
	ACO_nb = ACO_nb.trimmed();
	HCG_nb = HCG_nb.trimmed();
	ESO_nb = ESO_nb.trimmed();
	VdBH_nb = VdBH_nb.trimmed();

	const unsigned int f = NGC_nb + IC_nb + M_nb + C_nb + B_nb + Sh2_nb + VdB_nb + RCW_nb + LDN_nb + LBN_nb + Cr_nb + Mel_nb + PGC_nb + UGC_nb + Arp_nb + VV_nb + DWB_nb + Tr_nb + St_nb + Ru_nb + VdBHa_nb;
	if (f==0 && Ced_nb.isEmpty() && PK_nb.isEmpty() && PNG_nb.isEmpty() && SNRG_nb.isEmpty() && ACO_nb.isEmpty() && HCG_nb.isEmpty() && ESO_nb.isEmpty() && VdBH_nb.isEmpty())
		withoutID = true;

	if (M_nb > 0) designations << QString("M %1").arg(M_nb);
	if (C_nb > 0)  designations << QString("C %1").arg(C_nb);
	if (NGC_nb > 0) designations << QString("NGC %1").arg(NGC_nb);
	if (IC_nb > 0) designations << QString("IC %1").arg(IC_nb);
	if (B_nb > 0) designations << QString("B %1").arg(B_nb);
	if (Sh2_nb > 0) designations << QString("SH 2-%1").arg(Sh2_nb);
	if (VdB_nb > 0) designations << QString("vdB %1").arg(VdB_nb);
	if (RCW_nb > 0) designations << QString("RCW %1").arg(RCW_nb);
	if (LDN_nb > 0) designations << QString("LDN %1").arg(LDN_nb);
	if (LBN_nb > 0) designations << QString("LBN %1").arg(LBN_nb);
	if (Cr_nb > 0) designations << QString("Cr %1").arg(Cr_nb);
	if (Mel_nb > 0) designations << QString("Mel %1").arg(Mel_nb);
	if (PGC_nb > 0) designations << QString("PGC %1").arg(PGC_nb);
	if (UGC_nb > 0) designations << QString("UGC %1").arg(UGC_nb);
	if (!Ced_nb.isEmpty()) designations << QString("Ced %1").arg(Ced_nb);
	if (Arp_nb > 0) designations << QString("Arp %1").arg(Arp_nb);
	if (VV_nb > 0) designations << QString("VV %1").arg(VV_nb);
	if (!PK_nb.isEmpty()) designations << QString("PK %1").arg(PK_nb);
	if (!PNG_nb.isEmpty()) designations << QString("PN G%1").arg(PNG_nb);
	if (!SNRG_nb.isEmpty()) designations << QString("SNR G%1").arg(SNRG_nb);
	if (!ACO_nb.isEmpty()) designations << QString("Abell %1").arg(ACO_nb);
	if (!HCG_nb.isEmpty()) designations << QString("HCG %1").arg(HCG_nb);
	if (!ESO_nb.isEmpty()) designations << QString("ESO %1").arg(ESO_nb);
	if (!VdBH_nb.isEmpty()) designations << QString("vdBH %1").arg(VdBH_nb);
	if (DWB_nb > 0) designations << QString("DWB %1").arg(DWB_nb);
	if (Tr_nb > 0) designations << QString("Tr %1").arg(Tr_nb);
	if (St_nb > 0) designations << QString("St %1").arg(St_nb);
	if (Ru_nb > 0) designations << QString("Ru %1").arg(Ru_nb);
	if (VdBHa_nb > 0) designations << QString("vdB-Ha %1").arg(VdBHa_nb);

	StelUtils::spheToRect(ra,dec,XYZ);
	Q_ASSERT(fabs(XYZ.normSquared()-1.)<1e-9);
	nType = static_cast<Nebula::NebulaType>(oType);
	pointRegion = SphericalRegionP(new SphericalPoint(getJ2000EquatorialPos(Q_NULLPTR)));
}

bool Nebula::objectInDisplayedType() const
{
	if (!flagUseTypeFilters)
		return true;

	// a QMap which translates all defined nTypes to yet another int for easier filtering. Note some nTypes (commented away) have not been translated so far and are just qualified as "other/unknown"!
	static const QMap<NebulaType, int>map={
		{NebGx			,  0 },  // m Galaxy
		{NebAGx			,  1 },  // Active galaxy
		{NebRGx			,  1 },  // m Radio galaxy
		{NebIGx			,  2 },  // Interacting galaxy
		{NebQSO			,  1 },  // Quasar
		{NebCl			,  3 },  // Star cluster
		{NebOc			,  3 },  // Open star cluster
		{NebGc			, 11 },  // Globular star cluster, usually in the Milky Way Galaxy
		{NebSA			,  3 },  // Stellar association
		{NebSC			,  3 },  // Star cloud
		{NebN			,  5 },  // A nebula
		{NebPn			,  7 },  // Planetary nebula
		{NebDn			,  6 },  // Dark Nebula
		{NebRn			,  5 },  // Reflection nebula
		{NebBn			,  5 },  // Bipolar nebula
		{NebEn			,  5 },  // Emission nebula
		{NebCn			,  9 },  // Cluster associated with nebulosity
		{NebHII			,  4 },  // HII Region
		{NebSNR			,  8 },  // Supernova remnant
		{NebISM			,  4 },  // Interstellar matter
		{NebEMO			,  5 },  // Emission object (from 24.4)
		{NebBLL			,  1 },  // BL Lac object
		{NebBLA			,  1 },  // Blazar
		{NebMolCld	        ,  6 },  // Molecular Cloud
		{NebYSO			,  6 },  // Young Stellar Object
		{NebPossQSO		,  1 },  // Possible Quasar
		{NebPossPN		,  7 },  // Possible Planetary Nebula
		{NebPPN			,  7 },  // Protoplanetary Nebula
		//{NebStar		,    },  // Star
		//{NebSymbioticStar	,    },  // Symbiotic Star
		//{NebEmissionLineStar	,    },  // Emission-line Star
		{NebSNC			,  8 },  // Supernova Candidate
		{NebSNRC		,  8 },  // Supernova Remnant Candidate
		{NebGxCl		, 10 },  // Cluster of Galaxies
		{NebPartOfGx		,  3 },  // Part of a Galaxy (from 24.4)
		//{NebRegion		,    },  // Region of the sky
		{NebUnknown		, 12 }   // m Unknown type, catalog errors, "Unidentified Southern Objects" etc.
	};
	const int cntype = map.value(nType, 12);
	// These "displayed types" are now:
	// 0 = Galaxies
	// 1 = Active Galaxies
	// 2 = Interacting Galaxies
	// 3 = Open Star Clusters
	// 4 = Hydrogen regions (include interstellar matter)
	// 5 = Bright Nebulae
	// 6 = Dark Nebulae
	// 7 = Planetary Nebulae
	// 8 = Supernova Remnants
	// 9 = Cl. assoc.w.Neb
	//10 = Galaxy cluster
	//11 = Globular Cluster
	//12 = Unknown or other
	// TODO: Why can we not just map to TypeGroupFlags and need yet another cntype index?

	bool r = ( (typeFilters&TypeGalaxies             && cntype==0)
		|| (typeFilters&TypeActiveGalaxies       && cntype==1)
		|| (typeFilters&TypeInteractingGalaxies  && cntype==2)
		|| (typeFilters&TypeOpenStarClusters     && cntype==3)
		|| (typeFilters&TypeGlobularStarClusters && cntype==11)
		|| (typeFilters&TypeHydrogenRegions      && cntype==4)
		|| (typeFilters&TypeBrightNebulae        && cntype==5)
		|| (typeFilters&TypeDarkNebulae          && cntype==6)
		|| (typeFilters&TypePlanetaryNebulae     && cntype==7)
		|| (typeFilters&TypeSupernovaRemnants    && cntype==8)
		|| ((typeFilters&TypeOpenStarClusters || typeFilters&TypeBrightNebulae || typeFilters&TypeHydrogenRegions) && cntype==9)
		|| (typeFilters&TypeGalaxyClusters       && cntype==10)
		|| (typeFilters&TypeOther                && cntype==12));

	return r;
}

bool Nebula::objectInDisplayedCatalog() const
{
	if (hasBuiltInTexture && catalogFilters != CatNone)
		return true;
	bool r = ( ((catalogFilters&CatM)     && (M_nb>0))
		|| ((catalogFilters&CatC)     && (C_nb>0))
		|| ((catalogFilters&CatNGC)   && (NGC_nb>0))
		|| ((catalogFilters&CatIC)    && (IC_nb>0))
		|| ((catalogFilters&CatB)     && (B_nb>0))
		|| ((catalogFilters&CatSh2)   && (Sh2_nb>0))
		|| ((catalogFilters&CatVdB)   && (VdB_nb>0))
		|| ((catalogFilters&CatRCW)   && (RCW_nb>0))
		|| ((catalogFilters&CatLDN)   && (LDN_nb>0))
		|| ((catalogFilters&CatLBN)   && (LBN_nb>0))
		|| ((catalogFilters&CatCr)    && (Cr_nb>0))
		|| ((catalogFilters&CatMel)   && (Mel_nb>0))
		|| ((catalogFilters&CatPGC)   && (PGC_nb>0))
		|| ((catalogFilters&CatUGC)   && (UGC_nb>0))
		|| ((catalogFilters&CatCed)   && !(Ced_nb.isEmpty()))
		|| ((catalogFilters&CatArp)   && (Arp_nb>0))
		|| ((catalogFilters&CatVV)    && (VV_nb>0))
		|| ((catalogFilters&CatPK)    && !(PK_nb.isEmpty()))
		|| ((catalogFilters&CatPNG)   && !(PNG_nb.isEmpty()))
		|| ((catalogFilters&CatSNRG)  && !(SNRG_nb.isEmpty()))
		|| ((catalogFilters&CatACO)   && (!ACO_nb.isEmpty()))
		|| ((catalogFilters&CatHCG)   && (!HCG_nb.isEmpty()))
		|| ((catalogFilters&CatESO)   && (!ESO_nb.isEmpty()))
		|| ((catalogFilters&CatVdBH)  && (!VdBH_nb.isEmpty()))
		|| ((catalogFilters&CatDWB)   && (DWB_nb>0))
		|| ((catalogFilters&CatTr)    && (Tr_nb>0))
		|| ((catalogFilters&CatSt)    && (St_nb>0))
		|| ((catalogFilters&CatRu)    && (Ru_nb>0))
		|| ((catalogFilters&CatVdBHa) && (VdBHa_nb>0)))

		// Special case: objects without ID from current catalogs
		|| ((catalogFilters&CatOther) && withoutID);

	return r;
}

bool Nebula::objectInAllowedSizeRangeLimits(void) const
{
	bool r = true;
	if (flagUseSizeLimits)
	{
		const double size = 60. * static_cast<double>(qMax(majorAxisSize, minorAxisSize));
		r = (size>=minSizeLimit && size<=maxSizeLimit);
	}
	return r;
}

Nebula::RenderState Nebula::getRenderState(float maxMagHints, float maxMagLabels) const
{
	RenderState state;
	state.catalogVisible = objectInDisplayedCatalog();
	state.typeVisible = objectInDisplayedType();
	state.sizeAllowed = objectInAllowedSizeRangeLimits();
	state.namedPass = !flagShowOnlyNamedDSO || hasBuiltInTexture || !(getEnglishName().isEmpty() && culturalNames.isEmpty());

	const StelCore* core = StelApp::getInstance().getCore();
	const StelSkyDrawer* drawer = core ? core->getSkyDrawer() : nullptr;
	state.visibilityLevel = getVisibilityLevelByMagnitude();
	state.customMagnitudePass = !(drawer && drawer->getFlagNebulaMagnitudeLimit())
		|| state.visibilityLevel <= static_cast<float>(drawer->getCustomNebulaMagnitudeLimit());

	const bool base = state.catalogVisible && state.typeVisible && state.sizeAllowed
		&& state.namedPass && state.customMagnitudePass;
	const bool outlinesUseDrawPass = !outlineSegments.empty() && flagUseOutlines;
	const float angularSizeLimit = core
		? 5.f / core->getProjection(StelCore::FrameJ2000)->getPixelPerRadAtCenter() * M_180_PIf : 0.f;
	const auto opacity = NebulaDrawing::opacity(state.visibilityLevel, maxMagHints, maxMagLabels,
		majorAxisSize, angularSizeLimit, outlinesUseDrawPass);
	state.outlineDrawn = base && opacity.outlines > 0.f;
	state.hintDrawn = base && opacity.hints > 0.f;
	state.labelDrawn = base && opacity.labels > 0.f;
	state.pickable = state.hintDrawn || state.labelDrawn || state.outlineDrawn;
	return state;
}

StelObjectPickState Nebula::getPickState(const StelCore* core) const
{
	StelObjectPickState state;
	const NebulaMgr* nebulaMgr = GETSTELMODULE(NebulaMgr);
	if (!core || !nebulaMgr)
		return state;

	const float maxMagHints = nebulaMgr->computeMaxMagHint(core->getSkyDrawer());
	const float maxMagLabels = core->getSkyDrawer()->getSkyObjectLimitMagnitude() - 2.f
		+ static_cast<float>(nebulaMgr->getLabelsAmount() * 1.2) - 2.f;
	const RenderState render = getRenderState(maxMagHints, maxMagLabels);
	Vec3d direction = getJ2000EquatorialPos(core);
	if (direction.normSquared() > 0.0)
	{
		direction.normalize();
		state.landscapeVisible = core->getVisibleSkyArea().contains(direction);
	}
	const auto visibility = getDrawVisibility();
	state.pointDrawn = render.hintDrawn && visibility.hintAlpha > 0.05f;
	state.labelDrawn = render.labelDrawn && visibility.labelAlpha > 0.05f;
	state.outlineDrawn = render.outlineDrawn && visibility.outlineAlpha > 0.05f;
	state.pickable = (state.pointDrawn || state.labelDrawn || state.outlineDrawn) && state.landscapeVisible;
	state.visualRadiusRad = state.outlineDrawn ? getAngularRadius(core) * M_PI / 180.0 : 0.0;
	const float mag = getVMagnitudeWithVisualExtinction(core);
	state.hasMagnitude = std::isfinite(mag) && mag < 90.f;
	if (state.hasMagnitude)
		state.magnitude = mag;
	return state;
}

QString Nebula::getMorphologicalTypeString(void) const
{
	return mTypeString;
}

QString Nebula::getConcentrationClass(QString cc) const
{
	QString r = "";
	static const QStringList glclass = {"I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"};
	switch(glclass.indexOf(cc))
	{
		case 0:
			r = qc_("high concentration of stars toward the center", "Shapley-Sawyer Concentration Class");
			break;
		case 1:
			r = qc_("dense central concentration of stars", "Shapley-Sawyer Concentration Class");
			break;
		case 2:
			r = qc_("strong inner core of stars", "Shapley-Sawyer Concentration Class");
			break;
		case 3:
			r = qc_("intermediate rich concentrations of stars", "Shapley-Sawyer Concentration Class");
			break;
		case 4:
		case 5:
		case 6:
			r = qc_("intermediate concentrations of stars", "Shapley-Sawyer Concentration Class");
			break;
		case 7:
			r = qc_("rather loose concentration of stars towards the center", "Shapley-Sawyer Concentration Class");
			break;
		case 8:
			r = qc_("loose concentration of stars towards the center", "Shapley-Sawyer Concentration Class");
			break;
		case 9:
			r = qc_("loose concentration of stars", "Shapley-Sawyer Concentration Class");
			break;
		case 10:
			r = qc_("very loose concentration of stars towards the center", "Shapley-Sawyer Concentration Class");
			break;
		case 11:
			r = qc_("almost no concentration towards the center", "Shapley-Sawyer Concentration Class");
			break;
		default:
			r = qc_("undocumented concentration class", "Shapley-Sawyer Concentration Class");
			break;
	}
	return r;
}

QString Nebula::getMorphologicalTypeDescription(void) const
{
	QString m, r = "";

	// Let's avoid showing a wrong morphological description for galaxies
	// NOTE: Is required the morphological description for galaxies?
	if (QList<NebulaType>({NebGx, NebAGx, NebRGx, NebIGx, NebQSO, NebPossQSO, NebBLA, NebBLL, NebGxCl}).contains(nType))
		return QString();

	static const QRegularExpression GlClRx("\\.*(I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII)\\.*");
	int idx = mTypeString.indexOf(GlClRx);
	if (idx>0)
		m = mTypeString.mid(idx);
	else
		m = mTypeString;

	QRegularExpressionMatch GlClMatch=GlClRx.match(m);
	if (GlClMatch.hasMatch()) // Globular Clusters
	{
		if (m.contains("-")) // middle concentration class
		{
			QStringList cc = m.split("-");
			r = QString("%1 -> %2").arg(getConcentrationClass(cc.at(0)), getConcentrationClass(cc.at(1)));
		}
		else
			r = getConcentrationClass(m);
	}

	static const QRegularExpression OClRx("\\.*(I|II|III|IV)(\\d)(p|m|r)(n*|N*|u*|U*|e*|E*)\\.*");
	idx = mTypeString.indexOf(OClRx);
	if (idx>0)
		m = mTypeString.mid(idx);
	else
		m = mTypeString;

	QRegularExpressionMatch OClMatch=OClRx.match(m);
	if (OClMatch.hasMatch()) // Open Clusters
	{
		QStringList rtxt;
		static const QStringList occlass = { "I", "II", "III", "IV"};
		static const QStringList ocrich = { "p", "m", "r"};

		QStringList occlassStrings = {
			qc_("strong central concentration of stars", "Trumpler's Concentration Class"),
			qc_("little central concentration of stars", "Trumpler's Concentration Class"),
			qc_("no noticeable concentration of stars", "Trumpler's Concentration Class"),
			qc_("a star field condensation", "Trumpler's Concentration Class")};

		rtxt << occlassStrings.value(occlass.indexOf(OClMatch.captured(1).trimmed()),
			 qc_("undocumented concentration class", "Trumpler's Concentration Class"));

		QStringList oclBRangeStrings = {
			qc_("small brightness range of cluster members", "Trumpler's Brightness Class"),
			qc_("medium brightness range of cluster members", "Trumpler's Brightness Class"),
			qc_("large brightness range of cluster members", "Trumpler's Brightness Class")};

		rtxt << oclBRangeStrings.value(OClMatch.captured(2).toInt()-1,
			qc_("undocumented brightness range of cluster members", "Trumpler's Brightness Class"));

		QStringList ocrichStrings = {
			qc_("poor cluster with less than 50 stars", "Trumpler's Number of Members Class"),
			qc_("moderately rich cluster with 50-100 stars", "Trumpler's Number of Members Class"),
			qc_("rich cluster with more than 100 stars", "Trumpler's Number of Members Class")};

		rtxt << ocrichStrings.value(ocrich.indexOf(OClMatch.captured(3).trimmed()),
			qc_("undocumented number of members class", "Trumpler's Number of Members Class"));

		if (!OClMatch.captured(4).trimmed().isEmpty())
			rtxt << qc_("the cluster lies within nebulosity", "nebulosity factor of open clusters");

		r = rtxt.join(", ");
	}

	static const QRegularExpression VdBRx("\\.*(I|II|I-II|II P|P),\\s+(VBR|VB|BR|M|F|VF|:)\\.*");
	idx = mTypeString.indexOf(VdBRx);
	if (idx>0)
		m = mTypeString.mid(idx);
	else
		m = mTypeString;

	QRegularExpressionMatch VdBMatch=VdBRx.match(m);
	if (VdBMatch.hasMatch()) // Reflection Nebulae
	{
		QStringList rtx;
		static const QStringList rnclass = { "I", "II", "I-II", "II P", "P"};
		static const QStringList rnbrightness = { "VBR", "VB", "BR", "M", "F", "VF", ":"};
		switch(rnbrightness.indexOf(VdBMatch.captured(2).trimmed()))
		{
			case 0:
			case 1:
				rtx << qc_("very bright", "Reflection Nebulae Brightness");
				break;
			case 2:
				rtx << qc_("bright", "Reflection Nebulae Brightness");
				break;
			case 3:
				rtx << qc_("moderate brightness", "Reflection Nebulae Brightness");
				break;
			case 4:
				rtx << qc_("faint", "Reflection Nebulae Brightness");
				break;
			case 5:
				rtx << qc_("very faint", "Reflection Nebulae Brightness");
				break;
			case 6:
				rtx << qc_("uncertain brightness", "Reflection Nebulae Brightness");
				break;
			default:
				rtx << qc_("undocumented brightness of reflection nebulae", "Reflection Nebulae Brightness");
				break;
		}
		switch(rnclass.indexOf(VdBMatch.captured(1).trimmed()))
		{
			case 0:
				rtx << qc_("the illuminating star is embedded in the nebulosity", "Reflection Nebulae Classification");
				break;
			case 1:
				rtx << qc_("star is located outside the illuminated nebulosity", "Reflection Nebulae Classification");
				break;
			case 2:
				rtx << qc_("star is located on the corner of the illuminated nebulosity", "Reflection Nebulae Classification");
				break;
			case 3:
			{
				// TRANSLATORS: peculiar: odd or unusual, cf. peculiar star, peculiar galaxy
				rtx << qc_("star is located outside the illuminated peculiar nebulosity", "Reflection Nebulae Classification");
				break;
			}
			case 4:
			{
				// TRANSLATORS: peculiar: odd or unusual, cf. peculiar star, peculiar galaxy
				rtx << qc_("the illuminated peculiar nebulosity", "Reflection Nebulae Classification");
				break;
			}
			default:
				rtx << qc_("undocumented reflection nebulae", "Reflection Nebulae Classification");
				break;
		}
		r = rtx.join(", ");
	}


	static const QRegularExpression HIIRx("\\.*(\\d+),\\s+(\\d+),\\s+(\\d+)\\.*");
	idx = mTypeString.indexOf(HIIRx);
	if (idx>0)
		m = mTypeString.mid(idx);
	else
		m = mTypeString;

	QRegularExpressionMatch HIIMatch=HIIRx.match(m);
	if (HIIMatch.hasMatch()) // HII regions
	{
		const int form	     = HIIMatch.captured(1).toInt();
		const int structure  = HIIMatch.captured(2).toInt();
		const int brightness = HIIMatch.captured(3).toInt();
		const QStringList formList={
			q_("circular form"),
			q_("elliptical form"),
			q_("irregular form")};
		const QStringList structureList={
			q_("amorphous structure"),
			q_("conventional structure"),
			q_("filamentary structure")};
		const QStringList brightnessList={
			qc_("faintest", "HII region brightness"),
			qc_("moderate brightness", "HII region brightness"),
			qc_("brightest", "HII region brightness")};

		QStringList morph;
		morph << formList.value(form-1, q_("undocumented form"));
		morph << structureList.value(structure-1, q_("undocumented structure"));
		morph << brightnessList.value(brightness-1, q_("undocumented brightness"));

		r = morph.join(", ");
	}

	if (nType==NebSNR)
	{
		const QString delim =r.isEmpty() ? "" : "; ";

		if (mTypeString.contains("S") && !mTypeString.contains("S?"))
			r = qc_("remnant shows a shell radio structure", "supernova remnant structure classification") + delim + r;

		if (mTypeString.contains("F") && !mTypeString.contains("F?"))
			r = qc_("remnant shows a filled center ('plerion') radio structure", "supernova remnant structure classification") + delim + r;

		if (mTypeString.contains("C") && !mTypeString.contains("C?"))
			r = qc_("remnant shows a composite (or combination) radio structure", "supernova remnant structure classification") + delim + r;

		if (mTypeString.contains("S?"))
			r = qc_("remnant shows a shell radio structure with some uncertainty", "supernova remnant structure classification") + delim + r;

		if (mTypeString.contains("F?"))
			r = qc_("remnant shows a filled center ('plerion') radio structure with some uncertainty", "supernova remnant structure classification") + delim + r;

		if (mTypeString.contains("C?"))
			r = qc_("remnant shows a composite (or combination) radio structure with some uncertainty", "supernova remnant structure classification") + delim + r;
	}

	return r;
}

QString Nebula::getTypeStringI18n(Nebula::NebulaType nType)
{
	return q_(typeEnglishStringMap.value(nType, q_("undocumented type")));
}

Vec3d Nebula::getJ2000EquatorialPos(const StelCore* core) const
{
	if ((core) && (core->getUseAberration()) && (core->getCurrentPlanet()))
	{
		Vec3d pos=XYZ;
		Q_ASSERT_X(fabs(pos.normSquared()-1.0)<0.0001, "Nebula aberration", "vertex length not unity");
		//pos.normalize(); // Yay - not required!
		Vec3d vel=core->getAberrationVec(core->getJDE());
		pos+=vel;
		pos.normalize();
		return pos;
	}
	else
	{
		return XYZ;
	}
}

// Implemented:
// * Name
// * CatalogNumber
// * Magnitude
// RaDecJ2000
// RaDecOfDate
// AltAzi
// * Distance
// Elongation
// Size
// Velocity
// ProperMotion
// Extra
// HourAngle
// * AbsoluteMagnitude
// GalacticCoord
// SupergalacticCoord
// OtherCoord
// * ObjectType
// EclipticCoordJ2000
// EclipticCoordOfDate
// * IAUConstellation
// - CulturalConstellation
// SiderealTime
// RTSTime
// SolarLunarPosition
QString Nebula::getNarration(const StelCore *core, const InfoStringGroup &flags) const
{
	const Vec3d pos = getEquinoxEquatorialPos(core);

	QString res;

	// Name
	const QString designation = getDSODesignationWIC();
	QStringList names = {getNameI18n()};
	if (culturalNames.length()>0)
	{
		for (const StelObject::CulturalName &cName: culturalNames)
			names.append(cName.translatedI18n);
	}
	names.removeDuplicates();
	names.removeAll("");

	if (flags&Name)
	{
		res=designation;
		if (!names.isEmpty())
			res.append(", " +  q_("called") + " " + names.first() + ","); // TBD: Provide more than 1 name?
	}
	if (flags&ObjectType)// Type
		res.append(" " + q_("is") + " " + typeI18nNebulaStringMap.value(nType, qc_("an object of unknown type", "Nebula narration")) );

	if (flags&Distance)// Distance. Taken from getInfoString. Maybe move that to a private method...
	{
		if (qAbs(parallax)>0.f)
		{
			QString dx;
			// distance in light years from parallax
			float distance = 3.162e-5f/(qAbs(parallax)*4.848e-9f);
			float distanceErr = 0.f;

			if (parallaxErr>0.f)
				distanceErr = qAbs(3.162e-5f/(qAbs(parallaxErr + parallax)*4.848e-9f) - distance);

			if (distanceErr>0.f)
				dx = QString("%1%2%3").arg(StelUtils::narrateDecimal(distance, 3)).arg(QChar(0x00B1)).arg(StelUtils::narrateDecimal(distanceErr, 3));
			else
				dx = QString("%1").arg(StelUtils::narrateDecimal(distance, 3));

			if (oDistance==0.f)
			{
				// TRANSLATORS: Unit of measure for distance - Light Years
				QString ly = qc_("light years", "distance");
				res.append(QString("%1 %2 %3").arg(qc_("in a distance of", "object narration"), dx, ly));
			}
		}
		if (oDistance>0.f)
		{
			QString dx, dy;
			float dc = 3262.f;
			int ms = 1;
			//TRANSLATORS: Unit of measure for distance - kiloparsecs
			QString dupc = qc_("kiloparsec", "object narration");
			//TRANSLATORS: Unit of measure for distance - Light Years
			QString duly = qc_("light years", "object narration");

			float distance = oDistance;
			float distanceErr = oDistanceErr;
			float distanceLY = oDistance*dc;
			float distanceErrLY= oDistanceErr*dc;
			if (oDistance>=1000.f)
			{
				distance = oDistance/1000.f;
				distanceErr = oDistanceErr/1000.f;
				//TRANSLATORS: Unit of measure for distance - Megaparsecs
				dupc = qc_("Megaparsec", "object narration");
			}

			if (distanceLY>=1e6f)
			{
				distanceLY /= 1e6f;
				distanceErrLY /= 1e6f;
				ms = 3;
				//TRANSLATORS: Unit of measure for distance - Millions of Light Years
				duly = qc_("Million light years", "object narration");
			}

			if (oDistanceErr>0.f)
			{
				dx = QString("%1%2%3").arg(StelUtils::narrateDecimal(distance, 3)).arg(QChar(0x00B1)).arg(StelUtils::narrateDecimal(distanceErr, 3));
				dy = QString("%1%2%3").arg(StelUtils::narrateDecimal(distanceLY, ms)).arg(QChar(0x00B1)).arg(StelUtils::narrateDecimal(distanceErrLY, ms));
			}
			else
			{
				dx = QString("%1").arg(StelUtils::narrateDecimal(distance, 3));
				dy = QString("%1").arg(StelUtils::narrateDecimal(distanceLY, ms));
			}

			res.append(QString("%1 %2 %3 (%4 %5)").arg(qc_("in a distance of", "object narration"), dx, dupc, dy, duly));
		}
	}

	if (flags&IAUConstellation) // IAU Constellation
	{
		const QString iauConstellation = ConstellationMgr::getIAUconstellationName(core->getIAUConstellation(pos));
		res.append(" " + qc_("in the constellation of", "object narration") + " " + iauConstellation + ". ");
	}

	if (flags&Extra) // redshift, parallax, Discovery
	{
		if (redshift<99.f && nType<=NebQSO) // useful for galaxy types only.
		{
			QString z;
			if (redshiftErr>0.f)
				z = QString("%1 %2 %3").arg(StelUtils::narrateDecimal(redshift, 6), qc_("plus minus", "object narration"), StelUtils::narrateDecimal(redshiftErr, 6));
			else
				z = QString("%1").arg(StelUtils::narrateDecimal(redshift, 6));

			res += QString("%1 %2").arg(qc_("Its redshift is", "object narration"), z);
		}
		if (qAbs(parallax)>0.5f)
		{
			QString px;
			if (parallaxErr>0.f)
				px = QString("%1 %2 %3").arg(StelUtils::narrateDecimal(qAbs(parallax), 3), qc_("plus minus", "object narration"), StelUtils::narrateDecimal(parallaxErr, 3));
			else
				px = QString("%1").arg(StelUtils::narrateDecimal(qAbs(parallax), 3));

			res += QString("%1 %2 %3").arg(qc_("Its Parallax", "object narration"), px, qc_("milli-arcseconds", "parallax"));
		}


		if (!discoverer.isEmpty())
		{
			res.append(qc_("It was discovered by", "object narration") + " " + discoverer);
			if (!discoveryYear.isEmpty())
				res.append(" " + qc_("in the year", "object narration") + " " + discoveryYear);
			res.append(". ");
		}

		// Shape
		QString morph=getMorphologicalTypeDescription();
		if (!morph.isEmpty())
		{
			res.append(qc_("Morphologically:", "object narration") + " " + morph + ".");
		}
	}
	return res;
}

QMap<Nebula::NebulaType, QString>Nebula::typeI18nNebulaStringMap;

void Nebula::updateI18n()
{
	// The word forms should be with article if needed by the language
	typeI18nNebulaStringMap=
	{
		{ Nebula::NebGx			,  qc_("a Galaxy", "Nebula narration")},
		{ Nebula::NebAGx		,  qc_("an Active galaxy", "Nebula narration")},
		{ Nebula::NebRGx		,  qc_("a Radio galaxy", "Nebula narration")},
		{ Nebula::NebIGx		,  qc_("an Interacting galaxy", "Nebula narration")},
		{ Nebula::NebQSO		,  qc_("a Quasar", "Nebula narration")},
		{ Nebula::NebCl			,  qc_("a Star cluster", "Nebula narration")},
		{ Nebula::NebOc			,  qc_("an Open star cluster", "Nebula narration")},
		{ Nebula::NebGc			,  qc_("a Globular star cluster", "Nebula narration")},
		{ Nebula::NebSA			,  qc_("a Stellar association", "Nebula narration")},
		{ Nebula::NebSC			,  qc_("a Star cloud", "Nebula narration")},
		{ Nebula::NebN			,  qc_("A nebula", "Nebula narration")},
		{ Nebula::NebPn			,  qc_("a Planetary nebula", "Nebula narration")},
		{ Nebula::NebDn			,  qc_("a Dark Nebula", "Nebula narration")},
		{ Nebula::NebRn			,  qc_("a Reflection nebula", "Nebula narration")},
		{ Nebula::NebBn			,  qc_("a Bipolar nebula", "Nebula narration")},
		{ Nebula::NebEn			,  qc_("an emission nebula", "Nebula narration")},
		{ Nebula::NebCn			,  qc_("a cluster associated with nebulosity", "Nebula narration")},
		{ Nebula::NebHII		,  qc_("H two region", "Nebula narration")},
		{ Nebula::NebSNR		,  qc_("a Supernova remnant", "Nebula narration")},
		{ Nebula::NebISM		,  qc_("Interstellar matter", "Nebula narration")},
		{ Nebula::NebEMO		,  qc_("an Emission object", "Nebula narration")},
		{ Nebula::NebBLL		,  qc_("a BL Lacertae object", "Nebula narration")},
		{ Nebula::NebBLA		,  qc_("a Blazar", "Nebula narration")},
		{ Nebula::NebMolCld		,  qc_("a Molecular Cloud", "Nebula narration")},
		{ Nebula::NebYSO		,  qc_("a Young Stellar Object", "Nebula narration")},
		{ Nebula::NebPossQSO		,  qc_("a Possible Quasar", "Nebula narration")},
		{ Nebula::NebPossPN		,  qc_("a Possible Planetary Nebula", "Nebula narration")},
		{ Nebula::NebPPN		,  qc_("a Protoplanetary Nebula", "Nebula narration")},
		{ Nebula::NebStar		,  qc_("a Star", "Nebula narration")},
		{ Nebula::NebSymbioticStar	,  qc_("a Symbiotic Star", "Nebula narration")},
		{ Nebula::NebEmissionLineStar	,  qc_("an Emission-line Star", "Nebula narration")},
		{ Nebula::NebSNC		,  qc_("a Supernova Candidate", "Nebula narration")},
		{ Nebula::NebSNRC		,  qc_("a supernova Remnant Candidate", "Nebula narration")},
		{ Nebula::NebGxCl		,  qc_("a cluster of Galaxies", "Nebula narration")},
		{ Nebula::NebPartOfGx		,  qc_("a part of a Galaxy", "Nebula narration")},
		{ Nebula::NebRegion		,  qc_("a region of the sky", "Nebula narration")},
		{ Nebula::NebUnknown		,  qc_("an object of unknown type", "Nebula narration")}
	};
}
