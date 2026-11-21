/*
 * Stellarium
 * Copyright (C) 2009, 2012 Matthew Gates
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

#include "Satellite.hpp"
#include "MarkerVisibility.hpp"

#include "StelApp.hpp"
#include "StelCore.hpp"
#include "StelLocaleMgr.hpp"
#include "StelModuleMgr.hpp"
#include "StelMovementMgr.hpp"
#include "StelObject.hpp"
#include "StelPainter.hpp"
#include "StelProjector.hpp"
#include "StelSkyDrawer.hpp"
#include "StelTranslator.hpp"
#include "StelUtils.hpp"
#include "VecMath.hpp"
#include "SolarSystem.hpp"
#include "precession.h"

#include <QVector3D>
#include <QMatrix4x4>

#include "gsatellite/gTime.hpp"
#include "gsatellite/stdsat.h"

#include <cmath>

#define sqr(a) ((a)*(a))

const QString Satellite::SATELLITE_TYPE = QStringLiteral("Satellite");

// static data members - will be initialised in the Satellites class (the StelObjectMgr)
StelTextureSP Satellite::hintTexture;
bool Satellite::showLabels = true;
float Satellite::hintBrightness = 0.f;
float Satellite::hintScale = 1.f;
SphericalCap Satellite::viewportHalfspace = SphericalCap();
Vec3d Satellite::frameSunUnitJ2000 = Vec3d(1., 0., 0.);
bool Satellite::frameSunUnitValid = false;
int Satellite::orbitLineSegments = 90;
int Satellite::orbitLineFadeSegments = 4;
int Satellite::orbitLineSegmentDuration = 20;
int Satellite::orbitLineThickness = 1;
bool Satellite::orbitLinesFlag = true;
bool Satellite::iconicModeFlag = false;
bool Satellite::hideInvisibleSatellitesFlag = false;
bool Satellite::coloredInvisibleSatellitesFlag = true;
Vec3f Satellite::invisibleSatelliteColor = Vec3f(0.2f,0.2f,0.2f);
Vec3f Satellite::transitSatelliteColor = Vec3f(0.f,0.f,0.f);
double Satellite::timeRateLimit = 0.1; // x1000 (~16 minutes per second) by default
int Satellite::tleEpochAge = 30; // default age of TLE's epoch to mark TLE as outdated (used for filters)

bool Satellite::flagCFKnownStdMagnitude = false;
bool Satellite::flagCFApogee = false;
double Satellite::minCFApogee = 20000.;
double Satellite::maxCFApogee = 55000.;
bool Satellite::flagCFPerigee = false;
double Satellite::minCFPerigee = 200.;
double Satellite::maxCFPerigee = 1500.;
bool Satellite::flagCFEccentricity = false;
double Satellite::minCFEccentricity = 0.3;
double Satellite::maxCFEccentricity = 0.9;
bool Satellite::flagCFPeriod = false;
double Satellite::minCFPeriod = 0.;
double Satellite::maxCFPeriod = 150.;
bool Satellite::flagCFInclination = false;
double Satellite::minCFInclination = 120.;
double Satellite::maxCFInclination = 360.;
bool Satellite::flagCFRCS = false;
double Satellite::minCFRCS = 0.1;
double Satellite::maxCFRCS = 100.;
bool Satellite::flagVFAltitude = false;
double Satellite::minVFAltitude = 200.;
double Satellite::maxVFAltitude = 500.;
bool Satellite::flagVFMagnitude = false;
double Satellite::minVFMagnitude = 8.;
double Satellite::maxVFMagnitude = -8.;

#if (SATELLITES_PLUGIN_IRIDIUM == 1)
double Satellite::sunReflAngle = 180.;
//double Satellite::timeShift = 0.;
#endif

Satellite::Satellite(const QString& identifier, const QVariantMap& map)
	: initialized(false)
	, displayed(false)
	, orbitDisplayed(false)
	, userDefined(false)
	, newlyAdded(false)
	, orbitValid(false)
	, launchYear(0)
	, tleEpochJD(0.)
	, jdLaunchYearJan1(0)
	, stdMag(99.)
	, RCS(-1.)
	, perigee(0.)
	, apogee(0.)
	, inclination(0.)
	, eccentricity(0.)
	, status(StatusUnknown)
	, height(0.)
	, range(0.)
	, rangeRate(0.)
	, hintColor(0.f,0.f,0.f)
	, lastUpdated()	
	, isISS(false)
	, isStarlink(false)
	, pSatWrapper(nullptr)
	, visibility(gSatWrapper::UNKNOWN)
	, phaseAngle(0.)
	, infoColor(0.f,0.f,0.f)
	, orbitColor(0.f,0.f,0.f)
	, lastEpochCompForOrbit(0.)
	, epochTime(0.)
{
	// return initialized if the mandatory fields are not present
	if (identifier.isEmpty())
		return;
	if (!map.contains("name") || !map.contains("tle1") || !map.contains("tle2"))
		return;

	id = identifier;
	name  = map.value("name").toString();
	if (name.isEmpty())
		return;
	
	// If there are no such keys, these will be initialized with the default
	// values given them above.
	description = map.value("description", description).toString().trimmed();
	launchDate = map.value("launchDate", map.value("launch-date")).toString().trimmed();
	deployedFrom = map.value("deployedFrom", map.value("deployed-from")).toString().trimmed();
	deploymentDate = map.value("deploymentDate", map.value("deployment-date")).toString().trimmed();
	launchOperator = map.value("operator", map.value("launchOperator")).toString().trimmed();
	launchVehicle = map.value("launchVehicle", map.value("launch-vehicle")).toString().trimmed();
	mission = map.value("mission").toString().trimmed();
	payloadType = map.value("payloadType", map.value("payload-type")).toString().trimmed();
	displayed = map.value("visible", displayed).toBool();
	orbitDisplayed = map.value("orbitVisible", orbitDisplayed).toBool();
	userDefined = map.value("userDefined", userDefined).toBool();
	stdMag = map.value("stdMag", 99.).toDouble();
	RCS = map.value("rcs", -1.).toDouble();
	status = map.value("status", StatusUnknown).toInt();
	// Satellite hint color
	QVariantList list = map.value("hintColor", QVariantList()).toList();
	if (list.count() == 3)
	{
		hintColor[0] = list.at(0).toFloat();
		hintColor[1] = list.at(1).toFloat();
		hintColor[2] = list.at(2).toFloat();
	}

	// Satellite orbit section color
	list = map.value("orbitColor", QVariantList()).toList();
	if (list.count() == 3)
	{
		orbitColor[0] = list.at(0).toFloat();
		orbitColor[1] = list.at(1).toFloat();
		orbitColor[2] = list.at(2).toFloat();
	}
	else
	{
		orbitColor = hintColor;
	}

	// Satellite info color
	list = map.value("infoColor", QVariantList()).toList();
	if (list.count() == 3)
	{
		infoColor[0] = list.at(0).toFloat();
		infoColor[1] = list.at(1).toFloat();
		infoColor[2] = list.at(2).toFloat();
	}
	else
	{
		infoColor = hintColor;
	}

	if (map.contains("comms"))
	{
		for (const auto& comm : map.value("comms").toList())
		{
			QVariantMap commMap = comm.toMap();
			CommLink c;
			c.frequency = commMap.value("frequency").toDouble(); // required!
			if (commMap.contains("modulation")) c.modulation = commMap.value("modulation").toString();
			if (commMap.contains("description")) c.description = commMap.value("description").toString();
			comms.append(c);
		}
	}

	QVariantList groupList =  map.value("groups", QVariantList()).toList();
	if (!groupList.isEmpty())
	{
		for (const auto& group : std::as_const(groupList))
			groups.insert(group.toString());
	}

	// TODO: Somewhere here - some kind of TLE validation.
	QString line1 = map.value("tle1").toString();
	QString line2 = map.value("tle2").toString();
	setNewTleElements(line1, line2);
	// This also sets the international designator and launch year.

	QString dateString = map.value("lastUpdated").toString();
	if (!dateString.isEmpty())
		lastUpdated = QDateTime::fromString(dateString, Qt::ISODate);

	orbitValid = true;
	initialized = true;
	isISS = (id == QStringLiteral("25544"));
	isStarlink = (name.startsWith("STARLINK"));
	moon = GETSTELMODULE(SolarSystem)->getMoon();
	sun = GETSTELMODULE(SolarSystem)->getSun();

	visibilityDescription={
		{ gSatWrapper::RADAR_SUN,	N_("The satellite and the observer are in sunlight") },
		{ gSatWrapper::VISIBLE,		N_("The satellite is sunlit and the observer is in the dark") },
		{ gSatWrapper::RADAR_NIGHT,	N_("The satellite isn't sunlit") },
		{ gSatWrapper::PENUMBRAL,	N_("The satellite is in penumbra") },
		{ gSatWrapper::ANNULAR,		N_("The satellite is eclipsed") },
		{ gSatWrapper::BELOW_HORIZON,   N_("The satellite is below the horizon") }
	};

	StelCore *core = StelApp::getInstance().getCore();
	double JD=core->getJD();
	update(core, JD);
}

Satellite::~Satellite()
{
	if (pSatWrapper)
	{
		delete pSatWrapper;
		pSatWrapper = nullptr;
	}
}

double Satellite::roundToDp(float n, int dp)
{
	// round n to dp decimal places
	return std::floor(static_cast<double>(n) * pow(10., dp) + .5) / pow(10., dp);
}

QString Satellite::getNameI18n() const
{
	const QString appLang = StelApp::getInstance().getLocaleMgr().getAppLanguage();
	if (appLang.startsWith(QLatin1String("zh"), Qt::CaseInsensitive))
	{
		const bool traditional = (appLang.compare(QStringLiteral("zh_TW"), Qt::CaseInsensitive) == 0
			|| appLang.compare(QStringLiteral("zh_HK"), Qt::CaseInsensitive) == 0
			|| appLang.compare(QStringLiteral("zh_MO"), Qt::CaseInsensitive) == 0);
		const QString trimmed = name.trimmed();
		const QString upper = trimmed.toUpper();

		// Unified names for space stations and iconic observatories.
		if (upper == QLatin1String("CSS (TIANHE)") || upper == QLatin1String("TIANGONG (TIANHE)") || upper == QLatin1String("TIANHE"))
			return traditional ? QStringLiteral("天宮空間站（天和核心艙）") : QStringLiteral("天宫空间站（天和核心舱）");
		if (upper == QLatin1String("CSS (WENTIAN)"))
			return traditional ? QStringLiteral("天宮空間站（問天實驗艙）") : QStringLiteral("天宫空间站（问天实验舱）");
		if (upper == QLatin1String("CSS (MENGTIAN)"))
			return traditional ? QStringLiteral("天宮空間站（夢天實驗艙）") : QStringLiteral("天宫空间站（梦天实验舱）");
		if (upper == QLatin1String("ISS (ZARYA)") || upper == QLatin1String("ISS"))
			return traditional ? QStringLiteral("國際空間站（曙光號）") : QStringLiteral("国际空间站（曙光号）");
		if (upper == QLatin1String("ISS (NAUKA)"))
			return traditional ? QStringLiteral("國際空間站（科學號）") : QStringLiteral("国际空间站（科学号）");
		if (upper == QLatin1String("POISK"))
			return traditional ? QStringLiteral("探索號氣閘艙（Poisk）") : QStringLiteral("探索号气闸舱（Poisk）");
		if (upper == QLatin1String("ZVEZDA") || upper == QLatin1String("ISS (ZVEZDA)"))
			return traditional ? QStringLiteral("國際空間站（星辰號服務艙）") : QStringLiteral("国际空间站（星辰号服务舱）");
		if (upper == QLatin1String("ISS (UNITY)"))
			return traditional ? QStringLiteral("國際空間站（團結號節點艙）") : QStringLiteral("国际空间站（团结号节点舱）");
		if (upper == QLatin1String("ISS (DESTINY)"))
			return traditional ? QStringLiteral("國際空間站（命運號實驗艙）") : QStringLiteral("国际空间站（命运号实验舱）");
		if (upper.startsWith(QLatin1String("DRAGON CRS-")) || upper.startsWith(QLatin1String("DRAGON CRS ")))
			return (traditional ? QStringLiteral("貨運龍飛船 ") : QStringLiteral("货运龙飞船 ")) + trimmed.mid(7).trimmed();
		if (upper == QLatin1String("HST"))
			return traditional ? QStringLiteral("哈伯太空望遠鏡") : QStringLiteral("哈勃空间望远镜");
		if (upper == QLatin1String("TIANGONG 1") || upper == QLatin1String("TIANGONG-1"))
			return traditional ? QStringLiteral("天宮一號") : QStringLiteral("天宫一号");
		if (upper == QLatin1String("TIANGONG 2") || upper == QLatin1String("TIANGONG-2"))
			return traditional ? QStringLiteral("天宮二號") : QStringLiteral("天宫二号");

		struct SatPrefixRule { const char* token; const char* zhCN; const char* zhTW; };
		static const SatPrefixRule rules[] = {
			{"SHENZHOU-",       "神舟-",     "神舟-"},
			{"SHENZHOU ",       "神舟 ",     "神舟 "},
			{"TIANZHOU-",       "天舟-",     "天舟-"},
			{"TIANZHOU ",       "天舟 ",     "天舟 "},
			{"SOYUZ-MS ",       "联盟号 MS-", "聯盟號 MS-"},
			{"SOYUZ-MS",        "联盟号 MS",  "聯盟號 MS"},
			{"PROGRESS-MS ",    "进步号 MS-", "進步號 MS-"},
			{"PROGRESS-MS",     "进步号 MS",  "進步號 MS"},
			{"CREW DRAGON ",    "载人龙飞船 ", "載人龍飛船 "},
			{"CREW DRAGON",     "载人龙飞船",  "載人龍飛船"},
			{"CYGNUS ",         "天鹅座货运飞船 ", "天鵝座貨運飛船 "},
			{"STARLINER",       "星际客机",   "星際客機"},
			{"HTV-",            "鹳号货运飞船-", "鸛號貨運飛船-"},
			{"STARLINK",        "星链",     "星鏈"},
			{"BEIDOU",          "北斗",     "北斗"},
			{"QIANFAN",         "千帆",     "千帆"},
			{"HULIANWANG DIGUI","互联低轨", "互聯低軌"},
			{"HULIANWANG",      "互联卫星", "互聯衛星"},
			{"FENGYUN",         "风云",     "風雲"},
			{"GAOFEN",          "高分",     "高分"},
			{"YAOGAN",          "遥感",     "遙感"},
			{"SHIYAN",          "试验",     "試驗"},
			{"SHIJIAN",         "实践",     "實踐"},
			{"TIANHUI",         "天绘",     "天繪"},
			{"TIANLIAN",        "天链",     "天鏈"},
			{"TIANTONG",        "天通",     "天通"},
			{"TIANQI",          "天启",     "天啟"},
			{"ZIYUAN",          "资源",     "資源"},
			{"JILIN",           "吉林",     "吉林"},
			{"HAIYANG",         "海洋",     "海洋"},
			{"YUNHAI",          "云海",     "雲海"},
			{"CHUANGXIN",       "创新",     "創新"},
			{"CZ-",             "长征-",    "長征-"},
			{"ONEWEB",          "一网",     "一網"},
			{"IRIDIUM",         "铱星",     "銥星"},
			{"GLOBALSTAR",      "全球星",   "全球星"},
			{"GLONASS",         "格洛纳斯", "格洛納斯"},
			{"GALILEO",         "伽利略",   "伽利略"},
			{"GPS ",            "GPS导航 ", "GPS導航 "},
			{"NOAA",            "NOAA气象", "NOAA氣象"},
			{"METEOR-M",        "流星气象-M","流星氣象-M"},
			{"COSMOS",          "宇宙号",   "宇宙號"},
			{"GONETS",          "戈涅斯",   "戈涅斯"},
			{"INTELSAT",        "国际通信", "國際通信"},
			{"QZSS",            "准天顶",   "準天頂"},
		};
		for (const auto& rule : rules)
		{
			const QLatin1String tok(rule.token);
			if (upper.startsWith(tok))
			{
				const int len = tok.size();
				// Ensure boundary for alphabetic tokens (unless token ends with '-' or ' ').
				const bool hasDelim = (rule.token[len - 1] == '-' || rule.token[len - 1] == ' ');
				if (hasDelim || upper.size() == len || !upper.at(len).isLetter())
				{
					QString rest = trimmed.mid(len);
					if (rest.endsWith(QLatin1String(" R/B"), Qt::CaseInsensitive))
						rest.replace(rest.size() - 4, 4, traditional ? QStringLiteral(" 火箭殘骸") : QStringLiteral(" 火箭残骸"));
					else if (rest.endsWith(QLatin1String(" DEB"), Qt::CaseInsensitive))
						rest.replace(rest.size() - 4, 4, traditional ? QStringLiteral(" 碎片") : QStringLiteral(" 碎片"));
					return QString::fromUtf8(traditional ? rule.zhTW : rule.zhCN) + rest;
				}
			}
		}
	}

	if (name.compare(QStringLiteral("CSS (TIANHE)"), Qt::CaseInsensitive) == 0)
	{
		const QString translated = q_("TIANGONG (TIANHE)");
		if (translated != QStringLiteral("TIANGONG (TIANHE)"))
			return translated;
	}
	return q_(name);
}

namespace {

struct VerifiedDeploymentRecord
{
	const char* noradId;
	const char* deployedFromZhCN;
	const char* deployedFromZhTW;
	const char* deployedFromEn;
	const char* deploymentDate;
};

const VerifiedDeploymentRecord* findVerifiedDeployment(const QString& satId)
{
	static const VerifiedDeploymentRecord kRecords[] = {
		// Verified ISS on-orbit releases / CubeSat deployments (JAXA J-SSOD, NanoRacks NRCSD, EVA release)
		{"66052", "国际空间站（星辰号/探索号出舱释放）", "國際空間站（星辰號/探索號出艙釋放）", "ISS (Zvezda/Poisk EVA release)", "2025-10-16"},
		{"66906", "国际空间站（NanoRacks 气闸舱部署器）", "國際空間站（NanoRacks 氣閘艙部署器）", "ISS (NanoRacks NRCSD)", "2025-12-02"},
		{"67683", "国际空间站（希望号实验舱 J-SSOD）", "國際空間站（希望號實驗艙 J-SSOD）", "ISS (Kibo J-SSOD)", "2026-02-03"},
		{"67684", "国际空间站（希望号实验舱 J-SSOD）", "國際空間站（希望號實驗艙 J-SSOD）", "ISS (Kibo J-SSOD)", "2026-02-03"},
		{"67685", "国际空间站（希望号实验舱 J-SSOD）", "國際空間站（希望號實驗艙 J-SSOD）", "ISS (Kibo J-SSOD)", "2026-02-03"},
		{"67686", "国际空间站（希望号实验舱 J-SSOD）", "國際空間站（希望號實驗艙 J-SSOD）", "ISS (Kibo J-SSOD)", "2026-02-03"},
		{"67687", "国际空间站（希望号实验舱 J-SSOD）", "國際空間站（希望號實驗艙 J-SSOD）", "ISS (Kibo J-SSOD)", "2026-02-03"},
		{"67688", "国际空间站（希望号实验舱 J-SSOD）", "國際空間站（希望號實驗艙 J-SSOD）", "ISS (Kibo J-SSOD)", "2026-02-03"},
	};
	for (const auto& rec : kRecords)
	{
		if (satId == QLatin1String(rec.noradId))
			return &rec;
	}
	return nullptr;
}

} // namespace

QString Satellite::getDeployedFromI18n() const
{
	if (isStationComplexPrimary() || isStationComplexMember())
		return QString();
	if (!deployedFrom.isEmpty())
		return deployedFrom;

	const QString appLang = StelApp::getInstance().getLocaleMgr().getAppLanguage();
	const bool isZh = appLang.startsWith(QLatin1String("zh"), Qt::CaseInsensitive);
	const bool traditional = isZh && (appLang.compare(QStringLiteral("zh_TW"), Qt::CaseInsensitive) == 0
		|| appLang.compare(QStringLiteral("zh_HK"), Qt::CaseInsensitive) == 0
		|| appLang.compare(QStringLiteral("zh_MO"), Qt::CaseInsensitive) == 0);

	if (const VerifiedDeploymentRecord* rec = findVerifiedDeployment(id))
		return QString::fromUtf8(isZh ? (traditional ? rec->deployedFromZhTW : rec->deployedFromZhCN) : rec->deployedFromEn);

	// Automatic COSPAR parent-spacecraft derivation for any on-orbit station-deployed object:
	// Objects released from a space station inherit the station's COSPAR launch prefix with piece != "A".
	const QString desig = internationalDesignator.trimmed().toUpper();
	if (desig.startsWith(QLatin1String("1998-067")) && desig != QLatin1String("1998-067A") && id != QLatin1String("25544"))
		return isZh ? (traditional ? QStringLiteral("國際空間站（ISS）") : QStringLiteral("国际空间站（ISS）"))
		            : QStringLiteral("International Space Station (ISS)");
	if (desig.startsWith(QLatin1String("2021-035")) && desig != QLatin1String("2021-035A") && id != QLatin1String("48274"))
		return isZh ? (traditional ? QStringLiteral("天宮空間站（CSS）") : QStringLiteral("天宫空间站（CSS）"))
		            : QStringLiteral("Tiangong Space Station (CSS)");
	if (desig.startsWith(QLatin1String("1986-017")) && desig != QLatin1String("1986-017A") && id != QLatin1String("16609"))
		return isZh ? (traditional ? QStringLiteral("和平號空間站（Mir）") : QStringLiteral("和平号空间站（Mir）"))
		            : QStringLiteral("Mir Space Station");
	if (desig.startsWith(QLatin1String("2011-053")) && desig != QLatin1String("2011-053A") && id != QLatin1String("37820"))
		return isZh ? (traditional ? QStringLiteral("天宮一號（Tiangong-1）") : QStringLiteral("天宫一号（Tiangong-1）"))
		            : QStringLiteral("Tiangong-1");
	if (desig.startsWith(QLatin1String("2016-057")) && desig != QLatin1String("2016-057A") && id != QLatin1String("41765"))
		return isZh ? (traditional ? QStringLiteral("天宮二號（Tiangong-2）") : QStringLiteral("天宫二号（Tiangong-2）"))
		            : QStringLiteral("Tiangong-2");
	return QString();
}

QString Satellite::getDeploymentDate() const
{
	if (isStationComplexPrimary() || isStationComplexMember())
		return QString();
	if (!deploymentDate.isEmpty())
		return deploymentDate;
	if (const VerifiedDeploymentRecord* rec = findVerifiedDeployment(id))
		return QString::fromUtf8(rec->deploymentDate);
	return QString();
}

QVariantMap Satellite::getMap(void)
{
	QVariantMap map;
	map["name"] = name;	
	map["stdMag"] = stdMag;
	map["rcs"] = RCS;
	map["status"] = status;
	map["tle1"] = tleElements.first;
	map["tle2"] = tleElements.second;

	if (!description.isEmpty())
		map["description"] = description;
	if (!launchDate.isEmpty())
		map["launchDate"] = launchDate;
	if (!deployedFrom.isEmpty())
		map["deployedFrom"] = deployedFrom;
	if (!deploymentDate.isEmpty())
		map["deploymentDate"] = deploymentDate;
	if (!launchOperator.isEmpty())
		map["operator"] = launchOperator;
	if (!launchVehicle.isEmpty())
		map["launchVehicle"] = launchVehicle;
	if (!mission.isEmpty())
		map["mission"] = mission;
	if (!payloadType.isEmpty())
		map["payloadType"] = payloadType;

	map["visible"] = displayed;
	map["orbitVisible"] = orbitDisplayed;
	if (userDefined)
		map.insert("userDefined", userDefined);
	QVariantList col, orbitCol, infoCol;
	col << roundToDp(hintColor[0],3) << roundToDp(hintColor[1], 3) << roundToDp(hintColor[2], 3);
	orbitCol << roundToDp(orbitColor[0], 3) << roundToDp(orbitColor[1], 3) << roundToDp(orbitColor[2],3);
	infoCol << roundToDp(infoColor[0], 3) << roundToDp(infoColor[1], 3) << roundToDp(infoColor[2],3);
	map["hintColor"] = col;
	map["orbitColor"] = orbitCol;
	map["infoColor"] = infoCol;
	QVariantList commList;
	for (const auto& c : std::as_const(comms))
	{
		QVariantMap commMap;
		commMap["frequency"] = c.frequency;
		if (!c.modulation.isEmpty()) commMap["modulation"] = c.modulation;
		if (!c.description.isEmpty()) commMap["description"] = c.description;
		commList << commMap;
	}
	map["comms"] = commList;
	QVariantList groupList;
	for (const auto& g : std::as_const(groups))
	{
		groupList << g;
	}
	map["groups"] = groupList;

	if (!lastUpdated.isNull())
	{
		// A raw QDateTime is not a recognised JSON data type. --BM
		map["lastUpdated"] = lastUpdated.toString(Qt::ISODate);
	}

	return map;
}

float Satellite::getSelectPriority(const StelCore* core) const
{
	float limit = -10.f;
	static const QString grpStations = QStringLiteral("space stations");
	static const QString grpStationsShort = QStringLiteral("stations");
	if (isISS || groups.contains(grpStations) || groups.contains(grpStationsShort))
		limit = -12.5f;
	else if (visibility == gSatWrapper::VISIBLE)
		limit = -11.5f;

	if (flagVFAltitude) // the visual filter is enabled
		limit = (minVFAltitude<=height && height<=maxVFAltitude) ? limit : 50.f;

	if (flagVFMagnitude) // the visual filter is enabled
		limit = (((stdMag<99.) || (RCS>0.)) && ((maxVFMagnitude<=getVMagnitude(core)) && (getVMagnitude(core)<=minVFMagnitude))) ? limit : 50.f;

	return limit;
}

QString Satellite::getInfoString(const StelCore *core, const InfoStringGroup& flags) const
{
	QString str;
	QTextStream oss(&str);
	static const QString degree = QChar(0x00B0);
	const bool withDecimalDegree = StelApp::getInstance().getFlagUseDecDegreesOther();
	
	if (flags & Name)
	{
		oss << "<h2>" << getNameI18n() << "</h2>";
		if (!description.isEmpty())
		{
			// Let's convert possible \n chars into <br/> in description of satellite
			oss << q_(description).replace("\n", "<br/>") << "<br/>";
		}
	}
	
	if (flags & CatalogNumber)
	{
		QString catalogNumbers;
		if (internationalDesignator.isEmpty())
			catalogNumbers = QString("NORAD %1").arg(id);
		else
			catalogNumbers = QString("NORAD %1; %2 (COSPAR/NSSDC): %3").arg(id, q_("International Designator"), internationalDesignator);
		oss << catalogNumbers << "<br/><br/>";
	}

	if (flags & ObjectType)
		oss << QString("%1: <b>%2</b>").arg(q_("Type"), getObjectTypeI18n())  << "<br/>";
	if (!orbitValid)
	{
		if (flags != InfoStringGroup(None))
			oss << q_("Orbit propagation is invalid at this time. Update the TLE or choose a time near its epoch.") << "<br/>";
		postProcessInfoString(str, flags);
		return str;
	}
	
	if ((flags & Magnitude) && ((stdMag<99.) || (RCS>0.)) && (visibility==gSatWrapper::VISIBLE))
	{
		const int decimals = 2;
		const float airmass = getAirmass(core);
		const float mag=getVMagnitude(core);
		oss << QString("%1: <b>%2</b>").arg(q_("Approx. magnitude"), QString::number(mag, 'f', decimals));
		if (airmass>-1.f) // Don't show extincted magnitude much below horizon where model is meaningless.
			oss << QString(" (%1 <b>%2</b> %3 <b>%4</b> %5)").arg(q_("reduced to"), QString::number(getVMagnitudeWithExtinction(core, mag), 'f', decimals), q_("by"), QString::number(airmass, 'f', decimals), q_("Airmasses"));
		oss << "<br />";
	}

	// Ra/Dec etc.
	oss << getCommonInfoString(core, flags);

	if (flags&Distance)
	{
		QString km = qc_("km", "distance");
		// TRANSLATORS: Slant range: distance between the satellite and the observer
		oss << QString("%1: %2 %3").arg(q_("Range")).arg(qRound(range)).arg(km) << "<br/>";
		// TRANSLATORS: Rate at which the distance changes
		oss << QString("%1: %2 %3").arg(q_("Range rate")).arg(rangeRate, 5, 'f', 3).arg(qc_("km/s", "speed")) << "<br/>";
		// TRANSLATORS: Satellite altitude
		oss << QString("%1: %2 %3").arg(q_("Altitude")).arg(qRound(height)).arg(km) << "<br/>";
		oss << QString("%1 (WGS-84): %2 %3 / %4 %5").arg(q_("Perigee/apogee altitudes")).arg(qRound(perigee)).arg(km).arg(qRound(apogee)).arg(km) << "<br/>";
	}

	if (flags&Size && RCS>0.)
	{
		const double angularSize = getAngularRadius(core)*2.*M_PI_180;
		QString sizeStr;
		if (withDecimalDegree)
			sizeStr = StelUtils::radToDecDegStr(angularSize, 5, false, true);
		else
			sizeStr = StelUtils::radToDmsPStr(angularSize, 2);
		oss << QString("%1: %2").arg(q_("Approx. angular size"), sizeStr) << "<br />";
	}

	if (flags & Extra)
	{
		const double orbitalPeriod = pSatWrapper->getOrbitalPeriod();
		if (orbitalPeriod>0.0)
		{
			// TRANSLATORS: Revolutions per day - measurement of the frequency of a rotation
			QString rpd = qc_("rpd","frequency");
			// TRANSLATORS: minutes - orbital period for artificial satellites
			QString mins = qc_("min", "period");
			oss << QString("%1: %2 %3 (%4 &mdash; %5 %6)")
			       .arg(q_("Orbital period")).arg(orbitalPeriod, 5, 'f', 2)
			       .arg(mins, StelUtils::hoursToHmsStr(orbitalPeriod/60.0, true))
			       .arg(1440.0/orbitalPeriod, 9, 'f', 5).arg(rpd) << "<br/>";
		}
		const double inclination = pSatWrapper->getOrbitalInclination();
		QString incStr = withDecimalDegree ? QString("%1%2").arg(QString::number(inclination, 'f', 4), degree) : StelUtils::decDegToDmsStr(inclination);
		oss << QString("%1: %2").arg(q_("Inclination"), incStr) << "<br/>";
		oss << QString("%1: %2%4/%3%4").arg(q_("SubPoint (Lat./Long.)")).arg(latLongSubPointPosition[0], 5, 'f', 2).arg(latLongSubPointPosition[1], 5, 'f', 3).arg(degree) << "<br/>";
		
		//TODO: This one can be done better
		const char* xyz = "<b>X:</b> %1, <b>Y:</b> %2, <b>Z:</b> %3";
		QString temeCoords = QString(xyz).arg(qRound(position[0])).arg(qRound(position[1])).arg(qRound(position[2]));
		// TRANSLATORS: TEME (True Equator, Mean Equinox) is an Earth-centered inertial coordinate system
		oss << QString("%1: %2 %3").arg(q_("TEME coordinates"), temeCoords, qc_("km", "distance")) << "<br/>";
		
		QString temeVel = QString(xyz).arg(velocity[0], 5, 'f', 2).arg(velocity[1], 5, 'f', 2).arg(velocity[2], 5, 'f', 2);
		// TRANSLATORS: TEME (True Equator, Mean Equinox) is an Earth-centered inertial coordinate system
		oss << QString("%1: %2 %3").arg(q_("TEME velocity"), temeVel, qc_("km/s", "speed")) << "<br/>";

		QString pha = withDecimalDegree ?
				StelUtils::radToDecDegStr(phaseAngle,4,false,true) :
				StelUtils::radToDmsStr(phaseAngle, true);
		oss << QString("%1: %2").arg(q_("Phase angle"), pha) << "<br />";

#if (SATELLITES_PLUGIN_IRIDIUM == 1)
		if (sunReflAngle>0)
		{  // Iridium
			oss << QString("%1: %2%3").arg(q_("Sun reflection angle"))
			       .arg(sunReflAngle,0,'f',1)
			       .arg(degree);
			oss << "<br />";
		}
#endif
		QString updDate;
		if (!lastUpdated.isValid())
			updDate = qc_("unknown", "unknown date");
		else
		{
			const QDate sd = lastUpdated.date();
			const double hours = lastUpdated.time().hour() + lastUpdated.time().minute()/60. + lastUpdated.time().second()/3600.;
			updDate = QString("%1 %2 %3 %4 %5").arg(sd.day())
					.arg(StelLocaleMgr::longGenitiveMonthName(sd.month())).arg(sd.year())
					.arg(qc_("at","at time"), StelUtils::hoursToHmsStr(hours, true));
		}
		oss << QString("%1: %2").arg(q_("Last updated TLE"), updDate) << "<br />";
		oss << QString("%1: %2").arg(q_("Epoch of the TLE"), tleEpoch) << "<br />";
		if (RCS>0.)
			oss << QString("%1: %2 %3<sup>2</sup>").arg(q_("Radar cross-section (RCS)"), QString::number(RCS, 'f', 3), qc_("m","distance")) << "<br />";

		// Groups of the artificial satellites
		QStringList groupList;
		for (const auto&g : groups)
			groupList << q_(g);

		if (!groupList.isEmpty())
		{
			QString group = groups.count()==1 ? q_("Group") : q_("Groups");
			oss << QString("%1: %2").arg(group, groupList.join(", ")) << "<br />";
		}

		if (status!=StatusUnknown)
			oss << QString("%1: %2").arg(q_("Operational status"), getOperationalStatus()) << "<br />";
		//Visibility: Full text		
		oss << q_(visibilityDescription.value(visibility, "")) << "<br />";

		if (!comms.isEmpty() && (status!=Satellite::StatusNonoperational))
		{
			oss << q_("Radio communication") << ":<br/>";
			for (const auto& c : comms)
			{
				oss << getCommLinkInfo(c);
			}
		}
		// Umbra circle info. May not generally be interesting.
		//oss << QString("%1: %2 km, %3: %4 km").arg(q_("Umbra distance"), QString::number(umbraDistance, 'f', 3), q_("Radius"), QString::number(umbraRadius, 'f', 3)) << "<br/>";
		//oss << QString("%1: %2 km, %3: %4 km").arg(q_("Penumbra distance"), QString::number(penumbraDistance, 'f', 3), q_("Radius"), QString::number(penumbraRadius, 'f', 3)) << "<br/>";
	}

	oss << getSolarLunarInfoString(core, flags);
	postProcessInfoString(str, flags);
	return str;
}

QString Satellite::getCommLinkInfo(const CommLink &comm) const
{
	QString commLinkData;
	if (!comm.modulation.isEmpty()) // OK, the signal modulation mode is exist
		commLinkData = comm.modulation;

	if (commLinkData.isEmpty()) // description cannot be empty!
		commLinkData = comm.description;
	else
		commLinkData.append(QString(" %1").arg(comm.description));

	if (commLinkData.isEmpty())
		return QString();

	// Translate some specific communications terms
	// See end of Satellites.cpp file to define translatable terms
	static const QStringList commTerms={ "uplink", "downlink", "beacon", "telemetry", "video", "broadband", "command", "meteorological", "maritime", "mobile telephony", "mobile", "repeater", "digipeater", "-band", "crew voice", "imaging", "mode" };
	for (auto& term: commTerms)
	{
		commLinkData.replace(term, qc_(term, "comms"));
	}
	commLinkData.replace("&", q_("and"));

	const double dop = getDoppler(comm.frequency);
	double ddop = dop;
	QString sign("+");
	if (dop<0.)
	{
		sign='-';
		ddop*=-1;
	}

	commLinkData.append(QString(": %1 %2 (%3%4 %5)<br />").arg(QString::number(comm.frequency, 'f', 3), qc_("MHz", "frequency"), sign, QString::number(ddop, 'f', 3), qc_("kHz", "frequency")));
	return commLinkData;
}

// Calculate perigee and apogee altitudes for mean Earth radius
void Satellite::calculateSatDataFromLine2(const QString &tle)
{
	// Details: http://www.satobs.org/seesat/Dec-2002/0197.html
	const double k = 8681663.653;
	const double meanMotion = tle.left(63).right(11).toDouble();
	const double semiMajorAxis = std::cbrt((k/meanMotion)*(k/meanMotion));
	eccentricity = QString("0.%1").arg(tle.left(33).right(7)).toDouble();
	perigee = semiMajorAxis*(1.0 - eccentricity) - EARTH_RADIUS;
	apogee = semiMajorAxis*(1.0 + eccentricity) - EARTH_RADIUS;
	inclination = QString(tle.left(16).right(8)).toDouble();
}

// Calculate epoch of TLE
void Satellite::calculateEpochFromLine1(const QString &tle)
{
	QString epochStr;
	// Details: https://celestrak.org/columns/v04n03/ or https://en.wikipedia.org/wiki/Two-line_element_set
	int year = tle.left(20).right(2).toInt();
	if (year>=0 && year<57)
		year += 2000;
	else
		year += 1900;
	const double dayOfYear = tle.left(32).right(12).toDouble();
	QDate epoch = QDate(year, 1, 1).addDays(dayOfYear - 1);
	if (!epoch.isValid())
		epochStr = qc_("unknown", "unknown date");
	else
		epochStr = QString("%1 %2 %3, %4 UTC").arg(epoch.day())
				.arg(StelLocaleMgr::longGenitiveMonthName(epoch.month())).arg(year)
				.arg(StelUtils::hoursToHmsStr(24.*(dayOfYear-static_cast<int>(dayOfYear)), true));

	tleEpoch = epochStr;
	tleEpochJD = epoch.toJulianDay() - 0.5 + dayOfYear - std::floor(dayOfYear);
}

QVariantMap Satellite::getInfoMap(const StelCore *core) const
{
	QVariantMap map = orbitValid ? StelObject::getInfoMap(core) : QVariantMap();

	map.insert("description", QString(description).replace("\n", " - "));
	map.insert("catalog", id);
	map.insert("tle1", tleElements.first);
	map.insert("tle2", tleElements.second);
	map.insert("tle-epoch", tleEpoch);
	map.insert("tle-epoch-jd", tleEpochJD);
	map.insert("tle-age-days", core->getJD() - tleEpochJD);
	map.insert("tle-outdated", std::abs(core->getJD() - tleEpochJD) > tleEpochAge);
	map.insert("propagation-status", propagationStatus);
	map.insert("sgp4-error", pSatWrapper ? pSatWrapper->getPropagationError() : -1);

	if (!internationalDesignator.isEmpty())
		map.insert("international-designator", internationalDesignator);
	const QString resolvedDeployedFrom = getDeployedFromI18n();
	const QString resolvedDeploymentDate = getDeploymentDate();
	if (!resolvedDeployedFrom.isEmpty())
	{
		map.insert("deployed-from", resolvedDeployedFrom);
		map.insert("deployment-date", !resolvedDeploymentDate.isEmpty()
			? resolvedDeploymentDate
			: QStringLiteral("标准 TLE 未含释放日期"));
	}
	if (!launchDate.isEmpty())
		map.insert("launch-date", launchDate);
	if (launchYear > 0)
	{
		map.insert("launch-year", launchYear);
		if (launchDate.isEmpty())
		{
			if (!resolvedDeployedFrom.isEmpty())
				map.insert("launch-date", QStringLiteral("%1（母体空间站发射年份）").arg(launchYear));
			else
				map.insert("launch-date", QString::number(launchYear));
		}
	}
	map.insert("launch-date-precision", launchDate.isEmpty() ? QStringLiteral("year") : QStringLiteral("day"));
	if (!launchOperator.isEmpty())
		map.insert("launch-operator", launchOperator);
	if (!launchVehicle.isEmpty())
		map.insert("launch-vehicle", launchVehicle);
	if (!mission.isEmpty())
		map.insert("mission", mission);
	if (!payloadType.isEmpty())
		map.insert("payload-type", payloadType);

	if (stdMag>98.) // replace whatever has been computed
	{
		map.insert("vmag", "?");
		map.insert("vmage", "?");
	}

	map.insert("orbit-valid", initialized && orbitValid);
	map.insert("inclination", pSatWrapper->getOrbitalInclination());
	map.insert("period", pSatWrapper->getOrbitalPeriod());
	map.insert("eccentricity", eccentricity);
	map.insert("perigee-altitude", perigee);
	map.insert("apogee-altitude", apogee);
	const double speedKmS = velocity.norm();
	if (std::isfinite(speedKmS) && speedKmS > 0.0)
		map.insert("orbital-speed", speedKmS);
	map.insert("operational-status", getOperationalStatus());
	if (!orbitValid) return map;
	if (initialized && orbitValid && std::isfinite(range) && range > 0.0)
		map.insert("range", range);
	map.insert("rangerate", rangeRate);
	map.insert("height", height);
	map.insert("subpoint-lat", latLongSubPointPosition[0]);
	map.insert("subpoint-long", latLongSubPointPosition[1]);
	map.insert("TEME-km-X", position[0]);
	map.insert("TEME-km-Y", position[1]);
	map.insert("TEME-km-Z", position[2]);
	map.insert("TEME-speed-X", velocity[0]);
	map.insert("TEME-speed-Y", velocity[1]);
	map.insert("TEME-speed-Z", velocity[2]);
#if (SATELLITES_PLUGIN_IRIDIUM == 1)
	if (sunReflAngle>0.)
	{  // Iridium
		map.insert("sun-reflection-angle", sunReflAngle);
	}
#endif
	map.insert("phase-angle", phaseAngle);
	map.insert("phase-angle-dms", StelUtils::radToDmsStr(phaseAngle));
	map.insert("phase-angle-deg", StelUtils::radToDecDegStr(phaseAngle));
	map.insert("visibility", visibilityDescription.value(visibility, ""));

	return map;
}

QVariantList Satellite::getPassPredictions(StelCore* core, double hours, int limit, double minimumElevation) const
{
	QVariantList passes;
	if (!core || !pSatWrapper || !initialized || !orbitValid)
		return passes;

	const double originalJD = core->getJD();
	const double searchHours = qBound(1.0, hours, 24.0 * 7.0);
	const int maximumPasses = qBound(1, limit, 32);
	const double elevationLimit = qBound(-5.0, minimumElevation, 89.0);
	const double sampleStep = qMax(30.0, searchHours * 3600.0 / 720.0) / 86400.0;
	const double stopJD = originalJD + searchHours / 24.0;
	Satellite* satellite = const_cast<Satellite*>(this);
	const bool originalOrbitLinesFlag = satellite->orbitLinesFlag;
	const bool originalOrbitDisplayed = satellite->orbitDisplayed;
	satellite->orbitLinesFlag = false;
	satellite->orbitDisplayed = false;
	const double sunUpdateStep = 300.0 / 86400.0;
	double lastSunUpdateJD = originalJD - sunUpdateStep;
	bool predictionFailed = false;

	struct PassSample
	{
		double jd = 0.0;
		double altitude = -90.0;
		double azimuth = 0.0;
		double magnitude = 99.0;
		double range = 0.0;
		gSatWrapper::Visibility visibility = gSatWrapper::UNKNOWN;
		double sunAltitude = -90.0;
	};

	auto sampleAt = [&](double jd) -> PassSample {
		core->setJD(jd);
		if (std::abs(jd - lastSunUpdateJD) >= sunUpdateStep)
		{
			core->update(0);
			lastSunUpdateJD = jd;
		}
		satellite->update(core, jd);
		PassSample sample;
		sample.jd = jd;
		if (!satellite->orbitValid)
		{
			predictionFailed = true;
			return sample;
		}
		StelUtils::rectToSphe(&sample.azimuth, &sample.altitude, satellite->elAzPosition);
		sample.azimuth *= M_180_PI;
		sample.altitude *= M_180_PI;
		if (sample.azimuth < 0.0)
			sample.azimuth += 360.0;
		sample.magnitude = satellite->getVMagnitude(core);
		sample.range = satellite->range;
		sample.visibility = satellite->visibility;
		Vec3d sunAltAz = satellite->sun->getAltAzPosGeometric(core);
		double unusedSunAzimuth = 0.0;
		StelUtils::rectToSphe(&unusedSunAzimuth, &sample.sunAltitude, sunAltAz);
		sample.sunAltitude *= M_180_PI;
		return sample;
	};

	auto refineBoundary = [&](double low, double high, bool entering) -> double {
		for (int iteration = 0; iteration < 22; ++iteration)
		{
			const double middle = (low + high) * 0.5;
			const bool above = sampleAt(middle).altitude >= elevationLimit;
			if (entering)
			{
				if (above) high = middle;
				else low = middle;
			}
			else
			{
				if (above) low = middle;
				else high = middle;
			}
		}
		return entering ? high : low;
	};

	auto utcString = [](double jd) {
		return StelUtils::julianDayToISO8601String(jd);
	};
	auto localString = [&](double jd) {
		return StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
	};
	auto visibilityReason = [](gSatWrapper::Visibility visibility) {
		switch (visibility)
		{
		case gSatWrapper::VISIBLE: return QStringLiteral("sunlit_and_observer_dark");
		case gSatWrapper::PENUMBRAL: return QStringLiteral("penumbra");
		case gSatWrapper::RADAR_SUN: return QStringLiteral("observer_in_daylight");
		case gSatWrapper::RADAR_NIGHT: return QStringLiteral("satellite_in_earth_shadow");
		case gSatWrapper::ANNULAR: return QStringLiteral("satellite_eclipsed");
		case gSatWrapper::BELOW_HORIZON: return QStringLiteral("below_horizon");
		default: return QStringLiteral("unknown");
		}
	};

	PassSample previous = sampleAt(originalJD);
	bool inPass = previous.altitude >= elevationLimit;
	double passStartJD = inPass ? originalJD : 0.0;
	PassSample best = previous;
	bool visibleSeen = previous.visibility == gSatWrapper::VISIBLE && previous.altitude >= elevationLimit;
	QString bestVisibilityReason = visibilityReason(previous.visibility);
	int completedPasses = 0;

	auto appendPass = [&](double startJD, double endJD, const PassSample& peak, bool ongoing) {
		if (endJD <= startJD)
			return;
		const PassSample start = sampleAt(startJD);
		const PassSample end = sampleAt(endJD);
		QVariantMap pass;
		pass.insert("start", localString(startJD));
		pass.insert("peak", localString(peak.jd));
		pass.insert("end", localString(endJD));
		// Keep machine-readable event times alongside the localized labels. The
		// HarmonyOS time-navigation bridge uses these values to jump to a
		// satellite pass without reparsing a locale-dependent string.
		pass.insert("startJD", startJD);
		pass.insert("peakJD", peak.jd);
		pass.insert("endJD", endJD);
		pass.insert("startUtc", utcString(startJD));
		pass.insert("peakUtc", utcString(peak.jd));
		pass.insert("endUtc", utcString(endJD));
		pass.insert("appearance", localString(startJD));
		pass.insert("disappearance", localString(endJD));
		pass.insert("startAzimuth", start.azimuth);
		pass.insert("peakAzimuth", peak.azimuth);
		pass.insert("endAzimuth", end.azimuth);
		pass.insert("maxAltitude", peak.altitude);
		pass.insert("maxMagnitude", peak.magnitude);
		pass.insert("peakRangeKm", peak.range);
		pass.insert("durationSeconds", (endJD - startJD) * 86400.0);
		pass.insert("elevationLimit", elevationLimit);
		pass.insert("visible", visibleSeen);
		pass.insert("peakVisible", peak.visibility == gSatWrapper::VISIBLE);
		pass.insert("visibilityReason", visibleSeen ? QStringLiteral("sunlit_and_observer_dark") : bestVisibilityReason);
		pass.insert("peakSunAltitude", peak.sunAltitude);
		pass.insert("ongoing", ongoing);
		pass.insert("offline", true);
		pass.insert("source", QStringLiteral("local TLE propagation"));
		pass.insert("tleEpoch", tleEpoch);
		passes.append(pass);
	};

	for (double jd = originalJD + sampleStep; jd <= stopJD && completedPasses < maximumPasses; jd += sampleStep)
	{
		const PassSample current = sampleAt(qMin(jd, stopJD));
		const bool previousAbove = previous.altitude >= elevationLimit;
		const bool currentAbove = current.altitude >= elevationLimit;
		if (!inPass && !previousAbove && currentAbove)
		{
			passStartJD = refineBoundary(previous.jd, current.jd, true);
			inPass = true;
			best = current;
			visibleSeen = current.visibility == gSatWrapper::VISIBLE;
			bestVisibilityReason = visibilityReason(current.visibility);
		}
		if (inPass)
		{
			if (current.altitude > best.altitude)
				best = current;
			if (current.visibility == gSatWrapper::VISIBLE && current.altitude >= elevationLimit)
				visibleSeen = true;
			if (current.visibility != gSatWrapper::VISIBLE && bestVisibilityReason == QStringLiteral("unknown"))
				bestVisibilityReason = visibilityReason(current.visibility);
		}
		if (inPass && previousAbove && !currentAbove)
		{
			const double passEndJD = refineBoundary(previous.jd, current.jd, false);
			appendPass(passStartJD, passEndJD, best, false);
			++completedPasses;
			inPass = false;
			passStartJD = 0.0;
			visibleSeen = false;
			bestVisibilityReason = QStringLiteral("unknown");
		}
		previous = current;
	}
	if (inPass && completedPasses < maximumPasses)
		appendPass(passStartJD, stopJD, best, true);

	core->setJD(originalJD);
	core->update(0);
	satellite->update(core, originalJD);
	satellite->orbitLinesFlag = originalOrbitLinesFlag;
	satellite->orbitDisplayed = originalOrbitDisplayed;
	if (predictionFailed) passes.clear();
	return passes;
}

QVariantList Satellite::getPassPredictionsAtEpoch(StelCore* core, double startJD, double hours,
	int limit, double minimumElevation, bool* epochOrbitValidOut, QString* propagationStatusOut) const
{
	QVariantList passes;
	if (epochOrbitValidOut) *epochOrbitValidOut = false;
	if (propagationStatusOut) *propagationStatusOut = QStringLiteral("uninitialized");
	if (!core || !initialized || !std::isfinite(startJD) || startJD <= 0.0
		|| tleElements.first.isEmpty() || tleElements.second.isEmpty())
		return passes;

	const PlanetP currentPlanet = core->getCurrentPlanet();
	if (currentPlanet.isNull() || currentPlanet->getEnglishName() != QLatin1String("Earth"))
		return passes;

	SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
	const PlanetP earth = solarSystem ? solarSystem->getEarth() : PlanetP();
	if (earth.isNull())
		return passes;

	QByteArray idBytes = id.toLatin1();
	QByteArray t1 = tleElements.first.toLatin1();
	QByteArray t2 = tleElements.second.toLatin1();
	t1.truncate(130);
	t2.truncate(130);
	gSatTEME localSat(idBytes.data(), t1.data(), t2.data());

	const StelLocation loc = core->getCurrentLocation();
	const double radLatitude = loc.getLatitude() * M_PI_180;
	const double radLongitude = loc.getLongitude() * M_PI_180;
	const double sinLat = std::sin(radLatitude);
	const double cosLat = std::cos(radLatitude);
	const double altKm = loc.altitude / 1000.0;
	const double C = 1.0 / std::sqrt(1.0 + __f * (__f - 2.0) * sinLat * sinLat);
	const double S = (1.0 - __f) * (1.0 - __f) * C;
	const double rEq = (EARTH_RADIUS * C + altKm) * cosLat;
	const double zObs = (EARTH_RADIUS * S + altKm) * sinLat;

	const double searchHours = qBound(1.0, hours, 24.0 * 7.0);
	const int maximumPasses = qBound(1, limit, 32);
	const double elevationLimit = qBound(-5.0, minimumElevation, 89.0);
	const double sampleStep = qMax(30.0, searchHours * 3600.0 / 720.0) / 86400.0;
	const double stopJD = startJD + searchHours / 24.0;
	const double sunUpdateStep = 300.0 / 86400.0;

	double cachedSunJD = startJD - sunUpdateStep * 2.0;
	Vec3d cachedSunEqKm(0.0);
	bool predictionFailed = false;
	bool initialValid = false;
	QString initialStatus = QStringLiteral("uninitialized");

	auto sunGeocentricKmAt = [&](double jd) -> Vec3d {
		if (std::abs(jd - cachedSunJD) >= sunUpdateStep)
		{
			const double jde = jd + core->computeDeltaT(jd) / 86400.0;
			Vec3d earthPos, earthVel;
			earth->computePosition(jde, earthPos, earthVel);
			double obliquity = 0.0, chi = 0.0, omega = 0.0, psi = 0.0;
			getPrecessionAnglesVondrak(jde, &obliquity, &chi, &omega, &psi);
			const Mat4d toEqOfDate = Mat4d::zrotation(-chi) * Mat4d::xrotation(omega) * Mat4d::zrotation(psi);
			cachedSunEqKm = (toEqOfDate * (-earthPos)) * AU;
			cachedSunJD = jd;
		}
		return cachedSunEqKm;
	};

	struct PassSample
	{
		double jd = 0.0;
		double altitude = -90.0;
		double azimuth = 0.0;
		double magnitude = 99.0;
		double range = 0.0;
		gSatWrapper::Visibility visibility = gSatWrapper::UNKNOWN;
		double sunAltitude = -90.0;
		bool valid = false;
		QString status;
	};

	auto sampleAt = [&](double jd) -> PassSample {
		PassSample sample;
		sample.jd = jd;
		const gTime epoch(jd);
		localSat.setEpoch(epoch);
		QString status = QString::fromLatin1(localSat.getPropagationStatus());
		const Vec3d subPoint = localSat.getSubPoint();
		if (status == QLatin1String("valid") && subPoint[2] < 80.0)
			status = QStringLiteral("below_atmosphere_limit");
		sample.status = status;
		sample.valid = (status == QLatin1String("valid"));
		if (!sample.valid)
		{
			predictionFailed = true;
			return sample;
		}

		const double theta = epoch.toThetaLMST(radLongitude);
		const double sinTheta = std::sin(theta);
		const double cosTheta = std::cos(theta);
		const Vec3d obsPos(rEq * cosTheta, rEq * sinTheta, zObs);
		const Vec3d satPos = localSat.getPos();
		const Vec3d slant = satPos - obsPos;
		const double rangeKm = slant.norm();
		if (!std::isfinite(rangeKm) || rangeKm <= 0.0)
		{
			sample.valid = false;
			predictionFailed = true;
			return sample;
		}

		auto toTopo = [&](const Vec3d& d) -> Vec3d {
			return Vec3d(
				sinLat * cosTheta * d[0] + sinLat * sinTheta * d[1] - cosLat * d[2],
				-sinTheta * d[0] + cosTheta * d[1],
				cosLat * cosTheta * d[0] + cosLat * sinTheta * d[1] + sinLat * d[2]);
		};

		Vec3d topoSat = toTopo(slant);
		topoSat.normalize();
		StelUtils::rectToSphe(&sample.azimuth, &sample.altitude, topoSat);
		sample.azimuth *= M_180_PI;
		sample.altitude *= M_180_PI;
		if (sample.azimuth < 0.0)
			sample.azimuth += 360.0;
		sample.range = rangeKm;

		const Vec3d sunGeoKm = sunGeocentricKmAt(jd);
		const Vec3d sunRel = sunGeoKm - obsPos;
		const double sunRelNorm = sunRel.norm();
		const Vec3d topoSun = toTopo(sunRel);
		sample.sunAltitude = sunRelNorm > 0.0
			? std::asin(qBound(-1.0, topoSun[2] / sunRelNorm, 1.0)) * M_180_PI
			: -90.0;

		gSatWrapper::Visibility vis = gSatWrapper::BELOW_HORIZON;
		if (topoSat[2] > 0.0)
		{
			if (topoSun[2] > 0.0)
			{
				vis = gSatWrapper::RADAR_SUN;
			}
			else
			{
				vis = gSatWrapper::VISIBLE;
				const Vec3d satToSun = sunGeoKm - satPos;
				const double psun = satToSun.norm();
				const double pearth = satPos.norm();
				if (psun > 0.0 && pearth > 6371.0)
				{
					const double thetaE = std::asin(qBound(-1.0, (12742.0 / 2.0) / pearth, 1.0));
					const double thetaS = std::asin(qBound(-1.0, (1391000.0 / 2.0) / psun, 1.0));
					const double cosAngle = qBound(-1.0, ((-satPos).dot(satToSun)) / (pearth * psun), 1.0);
					const double angle = std::acos(cosAngle);
					if (thetaE > thetaS && angle < (thetaE - thetaS))
						vis = gSatWrapper::RADAR_NIGHT;
					else if (std::abs(thetaE - thetaS) < angle && angle < (thetaE + thetaS))
						vis = gSatWrapper::PENUMBRAL;
					else if (thetaS > thetaE && angle < (thetaS - thetaE))
						vis = gSatWrapper::ANNULAR;
				}
			}
		}
		sample.visibility = vis;

		double vmag = 7.0;
		if (vis != gSatWrapper::VISIBLE)
			vmag = (vis == gSatWrapper::PENUMBRAL ? 8.0 : 17.0);
		if (vis == gSatWrapper::VISIBLE || vis == gSatWrapper::PENUMBRAL)
		{
			if (isStarlink)
			{
				vmag = 5.93 + 5.0 * std::log10(rangeKm / 1000.0);
				if (name.contains("DARKSAT", Qt::CaseInsensitive))
					vmag *= 0.78;
			}
			else if (stdMag < 99.0)
			{
				Vec3d satToSunDir = sunGeoKm - satPos;
				Vec3d satToObsDir = obsPos - satPos;
				const double sNorm = satToSunDir.norm();
				const double oNorm = satToObsDir.norm();
				double phase = 0.0;
				if (sNorm > 0.0 && oNorm > 0.0)
					phase = std::acos(qBound(-1.0, satToSunDir.dot(satToObsDir) / (sNorm * oNorm), 1.0));
				const double fracil = qMax(0.000001, (1.0 + std::cos(phase)) * 0.5);
				vmag = stdMag - 15.75 + 2.5 * std::log10(rangeKm * rangeKm / fracil);
			}
		}
		sample.magnitude = vmag;
		return sample;
	};

	auto refineBoundary = [&](double low, double high, bool entering) -> double {
		for (int iteration = 0; iteration < 22; ++iteration)
		{
			const double middle = (low + high) * 0.5;
			const bool above = sampleAt(middle).altitude >= elevationLimit;
			if (entering)
			{
				if (above) high = middle;
				else low = middle;
			}
			else
			{
				if (above) low = middle;
				else high = middle;
			}
		}
		return entering ? high : low;
	};

	auto refinePeak = [&](double leftJD, double rightJD, PassSample bestSample) -> PassSample {
		double a = leftJD;
		double b = rightJD;
		for (int iteration = 0; iteration < 18 && (b - a) > (0.5 / 86400.0); ++iteration)
		{
			const double m1 = a + (b - a) / 3.0;
			const double m2 = b - (b - a) / 3.0;
			const PassSample s1 = sampleAt(m1);
			const PassSample s2 = sampleAt(m2);
			if (s1.altitude > bestSample.altitude) bestSample = s1;
			if (s2.altitude > bestSample.altitude) bestSample = s2;
			if (s1.altitude < s2.altitude) a = m1;
			else b = m2;
		}
		return bestSample;
	};

	auto utcString = [](double jd) {
		return StelUtils::julianDayToISO8601String(jd);
	};
	auto localString = [&](double jd) {
		return StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
	};
	auto visibilityReason = [](gSatWrapper::Visibility visibility) {
		switch (visibility)
		{
		case gSatWrapper::VISIBLE: return QStringLiteral("sunlit_and_observer_dark");
		case gSatWrapper::PENUMBRAL: return QStringLiteral("penumbra");
		case gSatWrapper::RADAR_SUN: return QStringLiteral("observer_in_daylight");
		case gSatWrapper::RADAR_NIGHT: return QStringLiteral("satellite_in_earth_shadow");
		case gSatWrapper::ANNULAR: return QStringLiteral("satellite_eclipsed");
		case gSatWrapper::BELOW_HORIZON: return QStringLiteral("below_horizon");
		default: return QStringLiteral("unknown");
		}
	};

	PassSample previous = sampleAt(startJD);
	initialValid = previous.valid;
	initialStatus = previous.status;
	if (epochOrbitValidOut) *epochOrbitValidOut = initialValid;
	if (propagationStatusOut) *propagationStatusOut = initialStatus;
	if (!initialValid)
		return passes;

	bool inPass = previous.altitude >= elevationLimit;
	double passStartJD = inPass ? startJD : 0.0;
	PassSample best = previous;
	bool visibleSeen = previous.visibility == gSatWrapper::VISIBLE && previous.altitude >= elevationLimit;
	QString bestVisibilityReason = visibilityReason(previous.visibility);
	int completedPasses = 0;

	auto appendPass = [&](double passBeginJD, double passFinishJD, PassSample peak, bool ongoing) {
		if (passFinishJD <= passBeginJD)
			return;
		peak = refinePeak(passBeginJD, passFinishJD, peak);
		if (peak.visibility == gSatWrapper::VISIBLE && peak.altitude >= elevationLimit)
			visibleSeen = true;
		const PassSample start = sampleAt(passBeginJD);
		const PassSample end = sampleAt(passFinishJD);
		QVariantMap pass;
		pass.insert("start", localString(passBeginJD));
		pass.insert("peak", localString(peak.jd));
		pass.insert("end", localString(passFinishJD));
		pass.insert("startJD", passBeginJD);
		pass.insert("peakJD", peak.jd);
		pass.insert("endJD", passFinishJD);
		pass.insert("startUtc", utcString(passBeginJD));
		pass.insert("peakUtc", utcString(peak.jd));
		pass.insert("endUtc", utcString(passFinishJD));
		pass.insert("appearance", localString(passBeginJD));
		pass.insert("disappearance", localString(passFinishJD));
		pass.insert("startAzimuth", start.azimuth);
		pass.insert("peakAzimuth", peak.azimuth);
		pass.insert("endAzimuth", end.azimuth);
		pass.insert("maxAltitude", peak.altitude);
		pass.insert("maxMagnitude", peak.magnitude);
		pass.insert("peakRangeKm", peak.range);
		pass.insert("durationSeconds", (passFinishJD - passBeginJD) * 86400.0);
		pass.insert("elevationLimit", elevationLimit);
		pass.insert("visible", visibleSeen);
		pass.insert("peakVisible", peak.visibility == gSatWrapper::VISIBLE);
		pass.insert("visibilityReason", visibleSeen ? QStringLiteral("sunlit_and_observer_dark") : bestVisibilityReason);
		pass.insert("peakSunAltitude", peak.sunAltitude);
		pass.insert("ongoing", ongoing);
		pass.insert("offline", true);
		pass.insert("source", QStringLiteral("local TLE propagation"));
		pass.insert("tleEpoch", tleEpoch);
		passes.append(pass);
	};

	for (double jd = startJD + sampleStep; jd <= stopJD && completedPasses < maximumPasses; jd += sampleStep)
	{
		const PassSample current = sampleAt(qMin(jd, stopJD));
		if (predictionFailed)
			break;
		const bool previousAbove = previous.altitude >= elevationLimit;
		const bool currentAbove = current.altitude >= elevationLimit;
		if (!inPass && !previousAbove && currentAbove)
		{
			passStartJD = refineBoundary(previous.jd, current.jd, true);
			inPass = true;
			best = current;
			visibleSeen = current.visibility == gSatWrapper::VISIBLE;
			bestVisibilityReason = visibilityReason(current.visibility);
		}
		if (inPass)
		{
			if (current.altitude > best.altitude)
				best = current;
			if (current.visibility == gSatWrapper::VISIBLE && current.altitude >= elevationLimit)
				visibleSeen = true;
			if (current.visibility != gSatWrapper::VISIBLE && bestVisibilityReason == QStringLiteral("unknown"))
				bestVisibilityReason = visibilityReason(current.visibility);
		}
		if (inPass && previousAbove && !currentAbove)
		{
			const double passEndJD = refineBoundary(previous.jd, current.jd, false);
			appendPass(passStartJD, passEndJD, best, false);
			++completedPasses;
			inPass = false;
			passStartJD = 0.0;
			visibleSeen = false;
			bestVisibilityReason = QStringLiteral("unknown");
		}
		previous = current;
	}
	if (!predictionFailed && inPass && completedPasses < maximumPasses)
		appendPass(passStartJD, stopJD, best, true);

	if (predictionFailed)
	{
		passes.clear();
		if (epochOrbitValidOut) *epochOrbitValidOut = false;
	}
	return passes;
}

Vec3d Satellite::getJ2000EquatorialPos(const StelCore* core) const
{
	// Bugfix LP:1654331. I assume the elAzPosition has been computed without refraction! We must say this definitely.
	return core->altAzToJ2000(elAzPosition, StelCore::RefractionOff);
}

Vec3f Satellite::getInfoColor(void) const
{
	return infoColor;
}

float Satellite::getVMagnitude(const StelCore* core) const
{	
	Q_UNUSED(core)
	if (!orbitValid) return 99.f;
	float vmag = 7.f; // Optimistic value of magnitude for artificial satellite without data for standard magnitude
	if (iconicModeFlag)
		vmag = 5.0;

	if (!iconicModeFlag && visibility != gSatWrapper::VISIBLE)
		vmag = (visibility == gSatWrapper::PENUMBRAL ? 8.f : 17.f); // Artificial satellite is invisible and 17 is hypothetical value of magnitude

	if ((visibility==gSatWrapper::VISIBLE || visibility==gSatWrapper::PENUMBRAL) && pSatWrapper)
	{
#if(SATELLITES_PLUGIN_IRIDIUM == 1)
		sunReflAngle = -1.;
#endif

		if (isStarlink)
		{
			// Calculation of approx. visual magnitude for Starlink satellites
			// described here: http://www.satobs.org/seesat/Aug-2020/0079.html
			vmag = static_cast<float>(5.93 + 5 * std::log10 ( range / 1000 ));
			if (name.contains("DARKSAT", Qt::CaseInsensitive)) // See https://arxiv.org/abs/2006.08422
				vmag *= 0.78f;
		}
		else if (stdMag<99.) // OK, artificial satellite has value for standard magnitude
		{
			// Calculation of approx. visual magnitude for artificial satellites
			//
			// The standard magnitude may be an estimate based on the mean cross-
			// sectional area derived from its dimensions, or it may be a mean
			// value derived from visual observations. The former are denoted by a
			// letter "d" in column 37; the latter by a "v". To estimate the
			// magnitude at other ranges and illuminations, use the following formula:
			//
			// mag = stdmag - 15.75 + 2.5 * log10 (range * range / fracil)
			//
			// where : stdmag = standard magnitude as defined above
			//
			// range = distance from observer to satellite, km
			//
			// fracil = fraction of satellite illuminated,
			//	    [ 0 <= fracil <= 1 ]
			//
			// Original description: http://mmccants.org/tles/mccdesc.html

			double fracil = qMax(0.000001, static_cast<double>(calculateIlluminatedFraction()));

#if(SATELLITES_PLUGIN_IRIDIUM == 1)
			if (pSatWrapper && name.startsWith("IRIDIUM"))
			{
				Vec3d Sun3d = pSatWrapper->getSunECIPos();
				QVector3D sun(Sun3d.data()[0],Sun3d.data()[1],Sun3d.data()[2]);
				QVector3D sunN = sun; sunN.normalize();

				// position, velocity are known
				QVector3D Vx(velocity.data()[0],velocity.data()[1],velocity.data()[2]); Vx.normalize();

				Vec3d vy = (position^velocity);
				QVector3D Vy(vy.data()[0],vy.data()[1],vy.data()[2]); Vy.normalize();
				QVector3D Vz = QVector3D::crossProduct(Vx,Vy); Vz.normalize();

				// move this to constructor for optimizing
				QMatrix4x4 m0;
				m0.rotate(40, Vy);
				QVector3D Vx0 = m0.mapVector(Vx);

				QMatrix4x4 m[3];
				//m[2] = m[1] = m[0];
				m[0].rotate(0, Vz);
				m[1].rotate(120, Vz);
				m[2].rotate(-120, Vz);

				StelLocation loc   = StelApp::getInstance().getCore()->getCurrentLocation();
				const double  radLatitude    = loc.getLatitude() * KDEG2RAD;
				const double  theta          = pSatWrapper->getEpoch().toThetaLMST(loc.getLongitude() * KDEG2RAD);
				const double sinRadLatitude=sin(radLatitude);
				const double cosRadLatitude=cos(radLatitude);
				const double sinTheta=sin(theta);
				const double cosTheta=cos(theta);

				Vec3d observerECIPos;
				Vec3d observerECIVel;
				pSatWrapper->calcObserverECIPosition(observerECIPos, observerECIVel);

				sunReflAngle = 180.;
				QVector3D mirror;
				for (int i = 0; i<3; i++)
				{
					mirror = m[i].mapVector(Vx0);
					mirror.normalize();

					// reflection R = 2*(V dot N)*N - V
					QVector3D rsun =  2*QVector3D::dotProduct(sun,mirror)*mirror - sun;
					rsun = -rsun;
					Vec3d rSun(rsun.x(),rsun.y(),rsun.z());

					//Vec3d satECIPos  = getTEMEPos();
					Vec3d slantRange = rSun - observerECIPos;
					Vec3d topoRSunPos;
					//top_s
					topoRSunPos[0] = (sinRadLatitude * cosTheta * slantRange[0]
							+ sinRadLatitude * sinTheta * slantRange[1]
							- cosRadLatitude * slantRange[2]);
					//top_e
					topoRSunPos[1] = ((-1.0) * sinTheta * slantRange[0]
							+ cosTheta * slantRange[1]);

					//top_z
					topoRSunPos[2] = (cosRadLatitude * cosTheta * slantRange[0]
							+ cosRadLatitude * sinTheta * slantRange[1]
							+ sinRadLatitude * slantRange[2]);
					sunReflAngle = qMin(elAzPosition.angle(topoRSunPos) * KRAD2DEG, sunReflAngle) ;
				}

				// very simple flare model
				double iridiumFlare = 100;
				if (sunReflAngle<0.5)
					iridiumFlare = -8.92 + sunReflAngle*6;
				else	if (sunReflAngle<0.7)
					iridiumFlare = -5.92 + (sunReflAngle-0.5)*10;
				else
					iridiumFlare = -3.92 + (sunReflAngle-0.7)*5;

				 vmag = qMin(stdMag, iridiumFlare);
			}
			else // not Iridium
#endif
				vmag = static_cast<float>(stdMag);

			vmag += -15.75f + 2.5f * static_cast<float>(std::log10(range * range / fracil));
		}
		else if (RCS>0.) // OK, artificial satellite has RCS value and no standard magnitude
		{
			// Let's try calculate approx. magnitude from RCS value (see DOI: 10.1117/12.2014623)
			double albedo = 0.2;
			if (0.436<=phaseAngle && phaseAngle<1.745)
				albedo = (((((3.1765*phaseAngle - 22.0968)*phaseAngle + 62.182)*phaseAngle - 90.0993)*phaseAngle + 70.3031)*phaseAngle - 27.9227)*phaseAngle + 4.7373;
			else if (1.745<=phaseAngle && phaseAngle<=2.618)
				albedo = ((0.510905*phaseAngle - 2.72607)*phaseAngle + 4.96646)*phaseAngle - 3.02085;

			const double rm = range*1000.;
			const double fdiff = (std::sin(phaseAngle) + (M_PI - phaseAngle)*std::cos(phaseAngle))*(2.*albedo*RCS)/(3.* M_PI * M_PI * rm * rm);

			vmag = static_cast<float>(-26.74 - 2.5*std::log10(fdiff));
		}

		if (visibility==gSatWrapper::PENUMBRAL)
			vmag += 2.0f;
	}
	return vmag;
}

// Calculate illumination fraction of artificial satellite
float Satellite::calculateIlluminatedFraction() const
{
	return (1.f + cos(static_cast<float>(phaseAngle)))*0.5f;
}

QString Satellite::getOperationalStatus() const
{
	const QMap<int,QString>map={
		{ StatusOperational,          qc_("operational", "operational status")},
		{ StatusNonoperational,       qc_("non-operational", "operational status")},
		{ StatusPartiallyOperational, qc_("partially operational", "operational status")},
		{ StatusStandby,              qc_("standby", "operational status")},
		{ StatusSpare,                qc_("spare", "operational status")},
		{ StatusExtendedMission,      qc_("extended mission", "operational status")},
		{ StatusDecayed,              qc_("decayed", "operational status")},
	};
	return map.value(status,              qc_("unknown", "operational status"));
}

double Satellite::getAngularRadius(const StelCore*) const
{
	double radius = 0.05 / 3600.; // assume 0.1 arcsecond default diameter
	if (RCS>0.)
	{
		double halfSize = isISS ?
			 109. * 0.5 :         // Special case: let's use max. size of ISS (109 meters: https://www.nasa.gov/feature/facts-and-figures)
			 std::sqrt(RCS/M_PI); // Let's assume spherical satellites/circular cross-section
		radius = std::atan(halfSize/(1000.*range))*M_180_PI; // Computing an angular size of artificial satellite ("halfSize" in metres, "range" in kilometres)
	}
	return radius;
}

void Satellite::setNewTleElements(const QString& tle1, const QString& tle2)
{
	if (pSatWrapper)
	{
		gSatWrapper *old = pSatWrapper;
		pSatWrapper = nullptr;
		delete old;
	}

	tleElements.first = tle1;
	tleElements.second = tle2;

	pSatWrapper = new gSatWrapper(id, tle1, tle2);
	orbitPoints.clear();
	visibilityPoints.clear();
	clearMotionTrail();
	
	parseInternationalDesignator(tle1);
	calculateEpochFromLine1(tle1);
	calculateSatDataFromLine2(tle2);
}

void Satellite::recomputeSatData()
{
	calculateEpochFromLine1(tleElements.first);
	calculateSatDataFromLine2(tleElements.second);
}

void Satellite::update(const StelCore *core, const double JD, bool updateOrbit)
{
	if (pSatWrapper)
	{
		epochTime = JD; // + timeShift; // We have "true" JD (UTC) from core, satellites don't need JDE!

		pSatWrapper->setEpoch(epochTime);
		QString nextStatus = pSatWrapper->getPropagationStatus();
		if (nextStatus == QLatin1String("valid") && pSatWrapper->getSubPoint()[2] < 80.)
			nextStatus = QStringLiteral("below_atmosphere_limit");
		if (nextStatus != propagationStatus && nextStatus != QLatin1String("valid"))
			qWarning() << "[Satellites][propagation]" << id << name << nextStatus
				<< "tleAgeDays=" << JD - tleEpochJD << "sgp4Error=" << pSatWrapper->getPropagationError();
		propagationStatus = nextStatus;
		orbitValid = nextStatus == QLatin1String("valid");
		if (!orbitValid)
		{
			range = 0.;
			rangeRate = 0.;
			visibility = gSatWrapper::UNKNOWN;
			clearMotionTrail();
			return;
		}
		position                 = pSatWrapper->getTEMEPos();
		velocity                 = pSatWrapper->getTEMEVel();
		latLongSubPointPosition  = pSatWrapper->getSubPoint();
		height                   = latLongSubPointPosition[2]; // km
		/*
		Vec2d pa                 = pSatWrapper->getPerigeeApogeeAltitudes();
		perigee                  = pa[0];
		apogee                   = pa[1];
		*/
		elAzPosition = pSatWrapper->getAltAz();
		elAzPosition.normalize();
		XYZ = Satellite::getJ2000EquatorialPos(core);

		pSatWrapper->getSlantRange(range, rangeRate);
		visibility = pSatWrapper->getVisibilityPredict();
		hasUpdatedOnce = true;

		// Record tight local-horizon motion history for razor-sharp fast-time satellite streaks.
		// Never connects across horizon crossings, large calendar teleports, or time reversals.
		if (elAzPosition[2] < -0.025)
		{
			if (!motionTrail.isEmpty())
				clearMotionTrail();
		}
		else
		{
			const double dJD = JD - motionTrailLastJD;
			if (motionTrail.isEmpty() || std::fabs(dJD) > 0.015)
			{
				motionTrail.clear();
				motionTrail.append({ elAzPosition, JD, visibility });
				motionTrailLastJD = JD;
				motionTrailDir = 0;
			}
			else if (std::fabs(dJD) > (0.12 / 86400.0))
			{
				const int dir = (dJD > 0.0) ? 1 : -1;
				const double cosAng = motionTrail.last().altAzUnit.dot(elAzPosition);
				if ((motionTrailDir != 0 && dir != motionTrailDir) || cosAng < 0.72)
				{
					motionTrail.clear();
					motionTrail.append({ elAzPosition, JD, visibility });
					motionTrailLastJD = JD;
					motionTrailDir = dir;
				}
				else if (cosAng < 0.9999998)
				{
					motionTrail.append({ elAzPosition, JD, visibility });
					motionTrailLastJD = JD;
					motionTrailDir = dir;
					// Keep tight instantaneous window (~39 s simulated time, max 6 samples)
					// so fast-time streaks remain razor-sharp needles rather than broad historical bands.
					const double maxSpanDays = 0.00045;
					while (motionTrail.size() > 6 ||
					       (motionTrail.size() > 2 && std::fabs(JD - motionTrail.first().jd) > maxSpanDays))
					{
						motionTrail.removeFirst();
					}
				}
			}
		}

		// Compute phase angle via dot product (algebraically identical to spherical law of cosines,
		// using the frame-precomputed Sun unit vector when called from Satellites::update()).
		Vec3d satDir = XYZ;
		const double satNorm = satDir.norm();
		if (satNorm > 0.)
		{
			satDir /= satNorm;
			Vec3d sunDir = frameSunUnitValid ? frameSunUnitJ2000 : sun->getJ2000EquatorialPos(core);
			if (!frameSunUnitValid)
				sunDir.normalize();
			phaseAngle = std::acos(qBound(-1.0, -sunDir.dot(satDir), 1.0));
		}
		else
		{
			phaseAngle = 0.0;
		}

		// Compute orbit points to draw orbit line.
		// We suppress computing so that no lines are computed in parallel as long as this uses static variables.
		if (updateOrbit) updateOrbitLines();
	}
}

// Get radii and distances of shadow circles
Vec4d Satellite::getUmbraData()
{
	const double rhoE=position.norm(); // geocentric Satellite distance, km
	return Satellite::getUmbraData(rhoE);
}

//! Get radii and geocentric antisolar distances of shadow circles in km for a hypothetical object in geocentric distance rhoE [km].
//! Vec4d(umbraDistance, umbraRadius, penumbraDistance, penumbraRadius);
Vec4d Satellite::getUmbraData(const double rhoE)
{
	static StelCore *core = StelApp::getInstance().getCore();
	static PlanetP earth  = GETSTELMODULE(SolarSystem)->getEarth();
	static PlanetP sun    = GETSTELMODULE(SolarSystem)->getSun();

	// Compute locations of umbra and penumbra circles. These should show where the satellite enters/exits umbra/penumbra.
	// The computation follows ideas from https://celestrak.org/columns/v03n01/
	// These sources mention ECI coordinates (Earth Centered Inertial). Presumably TEME (True Equator Mean Equinox) are equivalent, at least for our purposes.
	const double rS=earth->getHeliocentricEclipticPos().norm()*AU; // distance earth...sun
	const double thetaE=asin((earth->getEquatorialRadius()*AU)/(rhoE));
	Vec3d sunEquinoxEqPos = sun->getEquinoxEquatorialPos(core);
	Vec3d sunTEME=sunEquinoxEqPos*AU;
	const double thetaS=asin((sun->getEquatorialRadius()*AU)/(sunTEME.norm()));
	Q_ASSERT(thetaE>thetaS);
	const double theta=thetaE-thetaS; // angle so that satellite dives into umbra
	// angle at Sun:
	const double sigma=asin(sin(theta)*rhoE/rS);
	// angle in geocenter
	const double eta=M_PI-sigma-theta;
	// complement
	const double mu=M_PI-eta;
	// geocentric distance of shadow circle towards antisun
	const double umbraDistance=rhoE*cos(mu);
	// radius of shadow circle
	const double umbraRadius=rhoE*sin(mu);
	// Repeat for penumbra
	const double thetaP=thetaE+thetaS; // angle so that satellite touches penumbra
	// angle at Sun:
	const double sigmaP=asin(sin(thetaP)*rhoE/rS);
	// angle in geocenter
	const double etaP=M_PI-sigmaP-thetaP;
	// complement
	const double muP=M_PI-etaP;
	// geocentric distance of shadow circle towards antisun
	const double penumbraDistance=rhoE*cos(muP);
	// radius of shadow circle
	const double penumbraRadius=rhoE*sin(muP);
	//// DBG OUT
	//StelObjectMgr *om=GETSTELMODULE(StelObjectMgr);
	//om->setExtraInfoString(StelObject::DebugAid, QString("&rho;<sub>E</sub> %1, r<sub>S</sub> %2, &theta;<sub>E</sub> %3°, &theta;<sub>S</sub> %4° <br/>")
	//		       .arg(QString::number(rhoE, 'f', 3),
	//			    QString::number(rS, 'f', 3),
	//			    QString::number(thetaE*M_180_PI, 'f', 3),
	//			    QString::number(thetaS*M_180_PI, 'f', 3)
	//			    )
	//		       );
	//om->addToExtraInfoString(StelObject::DebugAid, QString("&theta; %1°, &sigma; %2°, &eta; %3°, &mu; %4° <br/>")
	//		       .arg(
	//			    QString::number(theta*M_180_PI, 'f', 3),
	//			    QString::number(sigma*M_180_PI, 'f', 3),
	//			    QString::number(eta*M_180_PI, 'f', 3),
	//			    QString::number(mu*M_180_PI, 'f', 3)
	//			    )
	//		       );
	//om->addToExtraInfoString(StelObject::DebugAid, QString("&theta;<sub>P</sub> %1°, &sigma; %2°, &eta; %3°, &mu; %4° <br/>")
	//		       .arg(
	//			    QString::number(thetaP*M_180_PI, 'f', 3),
	//			    QString::number(sigmaP*M_180_PI, 'f', 3),
	//			    QString::number(etaP*M_180_PI, 'f', 3),
	//			    QString::number(muP*M_180_PI, 'f', 3)
	//			    )
	//		       );
	return Vec4d(umbraDistance, umbraRadius, penumbraDistance, penumbraRadius);
}

double Satellite::getDoppler(double freq) const
{
	return  -freq*((rangeRate*1000.0)/SPEED_OF_LIGHT);
}

void Satellite::recalculateOrbitLines(void)
{
	orbitPoints.clear();
	visibilityPoints.clear();
	lastOrbitStepSeconds = 0.0;
}

void Satellite::updateOrbitLines()
{
	if (initialized && displayed && orbitValid && orbitLinesFlag && shouldDisplayOrbit())
		computeOrbitPoints();
}

QVariantMap Satellite::getOrbitLineStatus() const
{
	return {{"id", id}, {"enabled", orbitLinesFlag}, {"configured", orbitDisplayed},
		{"selectedPreview", orbitPreview}, {"requested", shouldDisplayOrbit()},
		{"orbitValid", isOrbitValid()}, {"displayed", displayed},
		{"pointCount", orbitPoints.size()}, {"drawCount", orbitDrawCount},
		{"lastDrawJD", orbitLastDrawJD}, {"expandProgress", orbitExpandProgress},
		{"stepSeconds", orbitStepSeconds}};
}

SatFlags Satellite::getFlags() const
{
	// There's also a faster, but less readable way: treating them as uint.
	SatFlags flags;
	double orbitalPeriod = pSatWrapper->getOrbitalPeriod();
	if (displayed)
		flags |= SatDisplayed;
	else
		flags |= SatNotDisplayed;
	if (orbitDisplayed)
		flags |= SatOrbit;
	if (userDefined)
		flags |= SatUser;
	if (newlyAdded)
		flags |= SatNew;
	if (!orbitValid)
		flags |= SatError;
	if (RCS>0. && RCS <= 0.1)
		flags |= SatSmallSize;
	if (RCS>0.1 && RCS <= 1.0)
		flags |= SatMediumSize;
	if (RCS>1.0)
		flags |= SatLargeSize;
	if (eccentricity < 0.25 && (inclination>=0. && inclination<=180.) && apogee<4400.)
		flags |= SatLEO;
	if (eccentricity < 0.25 && inclination<25. && (orbitalPeriod>=1100. && orbitalPeriod<=2000.))
		flags |= SatGSO;
	if (eccentricity < 0.25 && (inclination>=0. && inclination<=180.) && apogee>=4400. && orbitalPeriod<1100.)
		flags |= SatMEO;
	if (eccentricity >= 0.25 && (inclination>=0. && inclination<=180.) && perigee<=70000. && orbitalPeriod<=14000.)
		flags |= SatHEO;
	if (eccentricity < 0.25 && (inclination>=25. && inclination<=180.) && (orbitalPeriod>=1100. && orbitalPeriod<=2000.))
		flags |= SatHGSO;
	if (qAbs(inclination) >= 89.5 && qAbs(inclination) <= 90.5)
		flags |= SatPolarOrbit;
	if (qAbs(inclination) <= 0.5)
		flags |= SatEquatOrbit;
	if ((qAbs(inclination) >= 97.5 && qAbs(inclination) <= 98.5) && (orbitalPeriod>=96. && orbitalPeriod<=100.))
		flags |= SatPSSO;
	// definition: https://en.wikipedia.org/wiki/High_Earth_orbit
	if (perigee>35786. && orbitalPeriod>1440.)
		flags |= SatHEarthO;
	if (qAbs(StelApp::getInstance().getCore()->getJD() - tleEpochJD) > tleEpochAge)
		flags |= SatOutdatedTLE;
	if (getCustomFiltersFlag())
		flags |= SatCustomFilter;
	if (!comms.isEmpty())
		flags |= SatCommunication;
	if (apogee<=100.0 || height<=100.0) // Karman line, atmosphere: thermosphere
		flags |= SatReentry;
	if (status == StatusOperational)
	{
		flags |= SatOperationalOS;
		flags |= SatActiveOS;
	}
	if (status == StatusNonoperational)
		flags |= SatNonoperationalOS;
	if (status == StatusPartiallyOperational)
	{
		flags |= SatPartiallyOperationalOS;
		flags |= SatActiveOS;
	}
	if (status == StatusStandby)
	{
		flags |= SatStandbyOS;
		flags |= SatActiveOS;
	}
	if (status == StatusSpare)
	{
		flags |= SatSpareOS;
		flags |= SatActiveOS;
	}
	if (status == StatusExtendedMission)
	{
		flags |= SatExtendedMissionOS;
		flags |= SatActiveOS;
	}
	if (status == StatusDecayed)
		flags |= SatDecayedOS;

	return flags;
}

void Satellite::setFlags(const SatFlags& flags)
{
	displayed = flags.testFlag(SatDisplayed);
	orbitDisplayed = flags.testFlag(SatOrbit);
	userDefined = flags.testFlag(SatUser);
}

bool Satellite::getCustomFiltersFlag() const
{
	double orbitalPeriod = pSatWrapper->getOrbitalPeriod();
	// Apogee
	bool cfa = true;
	if (flagCFApogee)
		cfa = (apogee>=minCFApogee && apogee<=maxCFApogee);
	// Perigee
	bool cfp = true;
	if (flagCFPerigee)
		cfp = (perigee>=minCFPerigee && perigee<=maxCFPerigee);
	// Eccentricity
	bool cfe = true;
	if (flagCFEccentricity)
		cfe = (eccentricity>=minCFEccentricity && eccentricity<=maxCFEccentricity);
	// Known standard magnitude
	bool cfm = true;
	if (flagCFKnownStdMagnitude)
		cfm = (stdMag<99.0);
	// Period
	bool cft = true;
	if (flagCFPeriod)
		cft = (orbitalPeriod>=minCFPeriod && orbitalPeriod<=maxCFPeriod);
	// Inclination
	bool cfi = true;
	if (flagCFInclination)
		cfi = (inclination>=minCFInclination && inclination<=maxCFInclination);
	// RCS
	bool cfr = true;
	if (flagCFRCS)
		cfr = (RCS>=minCFRCS && RCS<=maxCFRCS);

	return (cfa && cfp && cfe && cfm && cft && cfi && cfr);
}

void Satellite::parseInternationalDesignator(const QString& tle1)
{
	Q_ASSERT(!tle1.isEmpty());
	
	// The designator is encoded in chunk 3 on the first line.
	QStringList tleData = tle1.split(" ");
	QString rawString = tleData.at(2);
	bool ok;
	int year = rawString.left(2).toInt(&ok);
	if (!rawString.isEmpty() && ok)
	{
		// Y2K bug :) I wonder what NORAD will do in 2057. :)
		if (year < 57)
			year += 2000;
		else
			year += 1900;
		internationalDesignator = QString::number(year) + "-" + rawString.mid(2);
		launchYear = year;
	}
	else
	{
		year = 1957;
		launchYear = 0;
	}
	
	StelUtils::getJDFromDate(&jdLaunchYearJan1, year, 1, 1, 0, 0, 0);	
}

bool Satellite::operator <(const Satellite& another) const
{
	// If interface strings are used, you'll need QString::localeAwareCompare()
	int comp = name.compare(another.name);
	if (comp < 0)
		return true;
	if (comp > 0)
		return false;
	
	// If the names are the same, compare IDs, i.e. NORAD numbers.
	return (id < another.id);
}

StelObjectPickState Satellite::getPickState(const StelCore* core) const
{
	StelObjectPickState state;
	if (!core)
		return state;
	const StelProjectorP projection = core->getProjection(StelCore::FrameJ2000);
	const SatelliteRenderState render = getRenderState(core, projection.data(), true);
	state.pickable = render.pickable();
	state.pointDrawn = render.pointDrawn;
	state.labelDrawn = render.labelDrawn;
	state.outlineDrawn = false;
	state.iconDrawn = render.iconDrawn || render.markerDrawn;
	state.landscapeVisible = render.landscapeVisible;
	state.hasMagnitude = true;
	state.magnitude = (render.pointDrawn || render.iconDrawn || render.markerDrawn) ? render.magSat : render.txtMag;
	return state;
}

SatelliteRenderState Satellite::getRenderState(const StelCore* core, const StelProjector* prj, bool dateRangeOk,
	const FrameDrawContext* ctx) const
{
	SatelliteRenderState st;
	if (!core)
		return st;

	st.displayed = displayed;
	st.orbitValid = initialized && orbitValid;
	st.dateRangeOk = dateRangeOk;
	st.timeRateOk = ctx ? ctx->timeRateOk : (qAbs(core->getTimeRate()) < timeRateLimit);
	st.afterLaunch = (ctx ? ctx->currentJD : core->getJD()) >= jdLaunchYearJan1;
	st.visibility = visibility;
	if (!st.displayed || !st.orbitValid || !st.dateRangeOk || !st.timeRateOk || !st.afterLaunch)
		return st;

	// Deduplicate docked station modules & co-orbiting visiting spacecraft into their primary
	// station complex on the sky (both rendering and touch picking), unless explicitly selected.
	const bool isSelectedForComplex = orbitPreview || (ctx && !ctx->selectedId.isEmpty() && ctx->selectedId == id);
	if (isStationComplexMember() && !isSelectedForComplex)
		return st;

	st.altitudeFilterPass = !flagVFAltitude || (minVFAltitude <= height && height <= maxVFAltitude);
	if (!st.altitudeFilterPass)
		return st;

	// Frustum-cull BEFORE expensive atmospheric extinction, landscape polygon check, and Sun/Moon transit angle.
	// When an orbit must be drawn for this satellite, continue computing magnitudeFilterPass even if off-screen.
	const bool needsOrbitCheck = shouldDisplayOrbit() && orbitLinesFlag;
	if (prj)
	{
		st.projectable = prj->projectCheck(XYZ, st.screenWin);
		if (!st.projectable && !needsOrbitCheck)
			return st;
	}

	if (hideInvisibleSatellitesFlag && visibility != gSatWrapper::VISIBLE && !needsOrbitCheck)
		return st;

	st.magSat = getVMagnitudeWithVisualExtinction(core);
	st.limitMag = ctx ? ctx->limitMag : (core->getSkyDrawer() ? core->getSkyDrawer()->getLimitMagnitude() : 0.f);
	st.magnitudeFilterPass = !flagVFMagnitude
		|| ((stdMag < 99. || RCS > 0.) && (maxVFMagnitude <= st.magSat && st.magSat <= minVFMagnitude));
	if (!st.magnitudeFilterPass)
		return st;

	if (!st.projectable)
		return st;

	if (!ctx || ctx->checkLandscape)
	{
		Vec3d dir = XYZ;
		if (dir.normSquared() > 0.)
		{
			dir.normalize();
			st.landscapeVisible = core->getVisibleSkyArea().contains(dir);
		}
	}

	if (prj)
	{
		const bool hasMoon = ctx ? ctx->hasMoon : !moon.isNull();
		const bool hasSun = ctx ? ctx->hasSun : !sun.isNull();
		if (hasMoon && hasSun)
		{
			const Vec3d moonPos = ctx ? ctx->moonPos : moon->getJ2000EquatorialPos(core);
			const double moonAng = ctx ? ctx->moonAngRad : moon->getSpheroidAngularRadius(core);
			const Vec3d sunPos = ctx ? ctx->sunPos : sun->getJ2000EquatorialPos(core);
			const double sunAng = ctx ? ctx->sunAngRad : sun->getSpheroidAngularRadius(core);
			st.transitSunMoon = (XYZ.angle(moonPos) * M_180_PI <= moonAng)
				|| (XYZ.angle(sunPos) * M_180_PI <= sunAng);
			if (st.transitSunMoon)
			{
				const int screenSizeSat = static_cast<int>(
					getAngularRadius(core) * (2. * M_PI_180) * static_cast<double>(prj->getPixelPerRadAtCenter()));
				st.spriteSize = qMin(screenSizeSat, 15);
			}
		}
	}

	if (!iconicModeFlag)
	{
		static const QString grpStations = QStringLiteral("space stations");
		static const QString grpStationsShort = QStringLiteral("stations");
		static const QString grpCrewed = QStringLiteral("crewed");
		const bool isSelected = orbitPreview || (ctx && !ctx->selectedId.isEmpty() && ctx->selectedId == id);
		const bool isStation = isISS
			|| groups.contains(grpStations)
			|| groups.contains(grpStationsShort)
			|| groups.contains(grpCrewed);
		const double fovDeg = ctx ? ctx->fovDeg
			: (core->getMovementMgr() ? core->getMovementMgr()->getCurrentFov() : 60.0);
		const float zoomReveal = qBound(0.f, static_cast<float>((36.0 - fovDeg) / 24.0), 1.0f);
		const float shadowZoomReveal = qBound(0.f, static_cast<float>((28.0 - fovDeg) / 18.0), 1.0f);

		if (hideInvisibleSatellitesFlag && visibility != gSatWrapper::VISIBLE && !isSelected)
		{
			st.pointDrawn = false;
			st.labelDrawn = false;
			st.markerDrawn = false;
			st.markerOpacity = 0.f;
			st.txtMag = st.magSat;
		}
		else if (st.transitSunMoon)
		{
			st.pointDrawn = st.spriteSize > 0;
			st.markerDrawn = isSelected || isStation;
			st.markerOpacity = isSelected ? 1.0f : 0.85f;
			st.labelDrawn = showLabels || isSelected;
			st.txtMag = st.magSat;
		}
		else
		{
			const bool sunlit = (visibility == gSatWrapper::VISIBLE);
			const bool penumbra = (visibility == gSatWrapper::PENUMBRAL);
			const float effectiveLimit = st.limitMag + 3.2f * zoomReveal;
			st.pointDrawn = (sunlit || penumbra) && (st.magSat <= effectiveLimit);

			// Tiered subtle satellite micro-marker:
			// - Always crisp for selected satellite & space stations
			// - Crisp for visible/bright sunlit satellites so they stand apart from stars
			// - Progressively reveals faint & Earth-shadow satellites when zooming in (< 28 deg)
			if (isSelected)
			{
				st.markerDrawn = true;
				st.markerOpacity = 1.0f;
			}
			else if (isStation)
			{
				st.markerDrawn = true;
				st.markerOpacity = sunlit ? 0.94f : (0.54f + 0.38f * zoomReveal);
			}
			else if (sunlit && st.magSat <= 5.2f)
			{
				st.markerDrawn = true;
				st.markerOpacity = qBound(0.46f, 0.92f - qMax(0.f, st.magSat - 1.5f) * 0.12f, 0.92f);
			}
			else if (sunlit && st.pointDrawn)
			{
				st.markerDrawn = true;
				st.markerOpacity = qBound(0.32f, 0.40f + 0.46f * zoomReveal, 0.86f);
			}
			else if (penumbra && (st.pointDrawn || zoomReveal > 0.12f))
			{
				st.markerDrawn = true;
				st.markerOpacity = qBound(0.28f, 0.34f + 0.46f * zoomReveal, 0.80f);
			}
			else if (!sunlit && !penumbra && shadowZoomReveal > 0.05f)
			{
				st.markerDrawn = true;
				st.markerOpacity = 0.28f + 0.56f * shadowZoomReveal;
			}

			float txtMag = st.magSat;
			if (isSelected || isStation)
				txtMag = qMin(st.magSat, st.limitMag - 2.6f);
			else if (penumbra)
				txtMag = qMin(st.magSat - 3.f, st.limitMag - (0.6f + 1.4f * zoomReveal));
			else if (!sunlit)
				txtMag = (shadowZoomReveal > 0.05f)
					? (st.limitMag - (0.4f + 1.8f * shadowZoomReveal))
					: (st.magSat - 10.f);
			else if (st.markerDrawn)
				txtMag = qMin(st.magSat, st.limitMag - (0.8f + 1.2f * zoomReveal));

			st.txtMag = txtMag;
			st.labelDrawn = isSelected || (showLabels && (st.markerDrawn || txtMag <= st.limitMag));
		}
	}
	else
	{
		const bool iconAllowed = !(hideInvisibleSatellitesFlag && visibility != gSatWrapper::VISIBLE);
		st.iconDrawn = iconAllowed;
		st.labelDrawn = showLabels && iconAllowed;
		st.txtMag = st.magSat;
	}

	return st;
}

void Satellite::draw(StelCore* core, StelPainter& painter)
{
	const SatelliteRenderState st = getRenderState(core, painter.getProjector().data(), true);

	// Keep the original early-out before orbit drawing: a satellite which is
	// hidden by its own display/time/filter gates must not leave an orbit.
	if (!st.displayed || !st.orbitValid || !st.dateRangeOk || !st.timeRateOk || !st.afterLaunch
		|| !st.altitudeFilterPass || !st.magnitudeFilterPass)
		return;

	if (st.projectable)
	{
		if (!iconicModeFlag)
		{
			static const Vec3f color(1.f, 1.f, 1.f);
			if (st.transitSunMoon)
			{
				painter.setColor(transitSatelliteColor, 1.f);
				if (st.pointDrawn)
					painter.drawSprite2dMode(XYZ, st.spriteSize);

				if (st.labelDrawn)
				{
					if (!core->isBrightDaylight()) // crossing of the Moon
						painter.setColor(color, hintBrightness);
					painter.queueSkyLabel(id, XYZ, name, st.magSat, 0, 10, 10);
				}
			}
			else
			{
				static StelSkyDrawer* sd = core->getSkyDrawer();
				if (st.pointDrawn)
				{
					RCMag rcMag;
					Vec3f vf(XYZ.toVec3f());
					Vec3f altAz(vf);
					altAz.normalize();
					core->j2000ToAltAzInPlaceNoRefraction(&altAz);
					sd->preDrawPointSource(&painter);
					sd->computeRCMag(st.magSat, &rcMag);
					// allow height-dependent twinkle and suppress twinkling in higher altitudes. Keep 0.1 twinkle amount in zenith.
					sd->drawPointSource(&painter, vf.toVec3d(), rcMag, color*hintBrightness, true, qMin(1.0f, 1.0f-0.9f*altAz[2]));
					sd->postDrawPointSource(&painter);
				}

				if (st.labelDrawn)
				{
					const float labelOpacity = hintBrightness * MarkerVisibility::magnitudeOpacity(st.txtMag, st.limitMag);
					if (visibility == gSatWrapper::VISIBLE)
						painter.setColor(hintColor, labelOpacity);
					else if (visibility == gSatWrapper::PENUMBRAL)
						painter.setColor(0.5f*hintColor, labelOpacity);
					else
						painter.setColor(invisibleSatelliteColor, labelOpacity);

					painter.queueSkyLabel(id, XYZ, name, st.magSat, 0, 10, 10);
				}
			}
		}
		else if (st.iconDrawn)
		{
			Vec3f drawColor = (coloredInvisibleSatellitesFlag && visibility != gSatWrapper::VISIBLE) ? invisibleSatelliteColor : hintColor;
			if (visibility == gSatWrapper::PENUMBRAL)
				drawColor = (invisibleSatelliteColor + hintColor)*0.5f;
			painter.setColor(drawColor, hintBrightness);
			if (st.transitSunMoon)
				painter.setColor(transitSatelliteColor, 1.f);

			if (st.labelDrawn)
				painter.queueSkyLabel(id, XYZ, name, st.magSat, 0, 10, 10);

			painter.drawSprite2dMode(XYZ, 11);
		}
	}

	if (shouldDisplayOrbit() && Satellite::orbitLinesFlag && orbitValid && core->getFlagClearSky())
		drawOrbit(core, painter);
}

void Satellite::drawOrbit(StelCore *core, StelPainter& painter)
{
	const int size = orbitPoints.size();
	if (size < 2 || visibilityPoints.size() < size)
		return;

	const bool isFadingOut = !orbitDisplayed && !orbitPreview && orbitExpandProgress > 0.004f;
	const bool isPreview = (orbitPreview || isFadingOut) && !orbitDisplayed;
	const float rawT = orbitDisplayed ? 1.0f : qBound(0.f, orbitExpandProgress, 1.f);
	const float invT = 1.0f - rawT;
	const float revealT = orbitDisplayed ? 1.0f : (1.0f - invT * invT * invT);
	if (revealT <= 0.004f)
		return;
	// Smooth opacity envelope: quick silky fade-in as the arc expands on select,
	// and a full smoothstep dissolve when deselecting so the orbit never snaps off.
	float orbitFadeAlpha = 1.0f;
	if (!orbitDisplayed)
	{
		if (orbitPreview)
		{
			const float inT = qBound(0.f, rawT / 0.35f, 1.f);
			orbitFadeAlpha = inT * inT * (3.0f - 2.0f * inT);
		}
		else
		{
			orbitFadeAlpha = rawT * rawT * (3.0f - 2.0f * rawT);
		}
	}
	if (orbitFadeAlpha <= 0.004f)
		return;

	const StelProjectorP prj = painter.getProjector();
	const double fovDeg = qBound(0.02, core->getMovementMgr()->getCurrentFov(), 179.0);
	const int vpH = prj ? prj->getViewportHeight() : 1080;
	const double radPerPx = (fovDeg * M_PI / 180.0) / qMax(360.0, static_cast<double>(vpH));
	const double screenScale = qBound(1.0, static_cast<double>(StelApp::getInstance().getScreenScale()), 3.5);
	const double thicknessMul = qBound(1.0, static_cast<double>(orbitLineThickness), 4.0);
	const double baseCoreW = qBound(1e-7, (isPreview ? 1.05 : 0.82) * screenScale * thicknessMul * radPerPx, 0.0042);

	QVector<Vec3d> j2kPts(size);
	QVector<double> cumArc(size, 0.0);
	QVector<double> altSin(size, 0.0);
	for (int i = 0; i < size; ++i)
	{
		const Vec4d& op = orbitPoints[i];
		Vec3d azVec(op[0], op[1], op[2]);
		const double azN = azVec.norm();
		altSin[i] = (azN > 1e-9) ? (op[2] / azN) : 0.0;
		Vec3d pos = core->altAzToJ2000(azVec, StelCore::RefractionOff);
		const double pn = pos.norm();
		j2kPts[i] = (pn > 1e-10) ? (pos / pn) : XYZ;
		if (i > 0)
		{
			const double dot = qBound(-1.0, j2kPts[i - 1].dot(j2kPts[i]), 1.0);
			cumArc[i] = cumArc[i - 1] + std::acos(dot);
		}
	}

	QVector<Vec3d> sideVecs(size);
	Vec3d lastSide(1., 0., 0.);
	for (int i = 0; i < size; ++i)
	{
		const int ip = qMax(0, i - 1);
		const int in = qMin(size - 1, i + 1);
		Vec3d tan = j2kPts[in] - j2kPts[ip];
		Vec3d side = j2kPts[i] ^ tan;
		const double sn = side.norm();
		if (sn > 1e-10) { side /= sn; lastSide = side; }
		else { side = lastSide; }
		sideVecs[i] = side;
	}

	const int centerIdx = size / 2;
	const float halfSpanIdx = qMax(1.0f, static_cast<float>(size - 1) * 0.5f);
	const float revealSpanIdx = qMax(1.0f, revealT * halfSpanIdx);
	const double dashPeriodRad = qBound(1e-5, 16.0 * screenScale * radPerPx, 0.036);

	// Locate the satellite's exact live continuous position along the cached orbit polyline
	// so the solid-past / dashed-future transition and forward direction chevrons glide
	// smoothly every frame instead of stepping once per orbitStepSeconds.
	const double dtFromComp = (gTime(epochTime) - gTime(lastEpochCompForOrbit)).getDblSeconds();
	const double estIdx = qBound(0.0,
		static_cast<double>(centerIdx) + dtFromComp / qMax(1.0, orbitStepSeconds),
		static_cast<double>(size - 1));
	double liveIdx = estIdx;
	double liveArc = cumArc[qBound(0, static_cast<int>(estIdx), size - 1)];
	Vec3d satDir = XYZ;
	const double satNorm = satDir.norm();
	if (satNorm > 1e-10)
	{
		satDir /= satNorm;
		const int winLo = qMax(0, static_cast<int>(std::floor(estIdx)) - 2);
		const int winHi = qMin(size - 2, static_cast<int>(std::ceil(estIdx)) + 2);
		double bestDistSq = 1e9;
		for (int i = winLo; i <= winHi; ++i)
		{
			const Vec3d ab = j2kPts[i + 1] - j2kPts[i];
			const double abLenSq = ab.normSquared();
			const double t = (abLenSq > 1e-14)
				? qBound(0.0, (satDir - j2kPts[i]).dot(ab) / abLenSq, 1.0)
				: 0.0;
			Vec3d proj = j2kPts[i] + ab * t;
			const double pn = proj.norm();
			if (pn > 1e-10) proj /= pn;
			const double dSq = (satDir - proj).normSquared();
			if (dSq < bestDistSq)
			{
				bestDistSq = dSq;
				liveIdx = static_cast<double>(i) + t;
				liveArc = cumArc[i] + (cumArc[i + 1] - cumArc[i]) * t;
			}
		}
	}

	// Blend sunlit color with custom orbitColor when a satellite specifies an explicit non-neutral tint.
	const Vec3f sunlitBase(0.56f, 0.88f, 1.0f);
	const float orbitChroma = qMax(qAbs(orbitColor[0] - orbitColor[1]), qMax(qAbs(orbitColor[1] - orbitColor[2]), qAbs(orbitColor[0] - orbitColor[2])));
	const Vec3f sunlitCol = (orbitChroma > 0.12f)
		? (sunlitBase * 0.65f + orbitColor * 0.35f)
		: sunlitBase;
	const Vec3f penumbraCol(1.0f, 0.78f, 0.42f);
	const Vec3f shadowCol(0.52f, 0.74f, 0.96f);

	QVector<Vec3f> nodeRgb(size);
	QVector<float> nodeAlpha(size, 0.f);
	QVector<double> nodeWidth(size, baseCoreW);
	QVector<bool> nodeEclipsed(size, false);

	for (int i = 0; i < size; ++i)
	{
		const float distIdx = std::fabs(static_cast<float>(i) - static_cast<float>(liveIdx));
		if (distIdx > revealSpanIdx)
		{
			nodeAlpha[i] = 0.f;
			continue;
		}
		const Vec4d& op = orbitPoints[i];
		if (flagVFAltitude && (op[3] < minVFAltitude || op[3] > maxVFAltitude))
		{
			nodeAlpha[i] = 0.f;
			continue;
		}
		const gSatWrapper::Visibility vis = visibilityPoints[i];
		const bool eclipsed = (vis != gSatWrapper::VISIBLE && vis != gSatWrapper::PENUMBRAL);
		nodeEclipsed[i] = eclipsed;
		if (hideInvisibleSatellitesFlag && vis != gSatWrapper::VISIBLE)
		{
			nodeAlpha[i] = 0.f;
			continue;
		}

		const bool isFuture = (static_cast<double>(i) >= liveIdx);
		const float segFade = calculateOrbitSegmentIntensity(i);
		const float frontierFade = (revealT < 0.995f && distIdx > revealSpanIdx - 3.5f)
			? qBound(0.f, (revealSpanIdx - distIdx) / 3.5f, 1.f)
			: 1.f;
		const float fracFromCenter = qBound(0.f, distIdx / halfSpanIdx, 1.f);
		const float dirAlpha = isFuture
			? (0.94f - 0.18f * fracFromCenter)
			: (0.78f * (1.0f - 0.56f * fracFromCenter));
		const double dirWidth = isFuture ? 1.0 : 0.90;
		const float horizonMul = (altSin[i] >= -0.005) ? 1.0f : 0.34f;

		Vec3f rgb = sunlitCol;
		float visMul = 1.0f;
		if (vis == gSatWrapper::PENUMBRAL)
		{
			rgb = penumbraCol;
			visMul = 0.86f;
		}
		else if (eclipsed)
		{
			rgb = shadowCol;
			visMul = 0.72f;
		}

		nodeRgb[i] = rgb;
		nodeAlpha[i] = qBound(0.f, hintBrightness * orbitFadeAlpha * segFade * frontierFade * dirAlpha * visMul * horizonMul, 0.96f);
		nodeWidth[i] = baseCoreW * dirWidth * (eclipsed ? 0.90 : 1.0);
	}

	orbitRibbonVerts.clear();
	orbitRibbonColors.clear();
	orbitRibbonVerts.reserve(size * 32 + 512);
	orbitRibbonColors.reserve(size * 32 + 512);

	auto pushQuad = [&](const Vec3d& a0, const Vec3d& a1, const Vec3d& b0, const Vec3d& b1,
		const Vec4f& ca0, const Vec4f& ca1, const Vec4f& cb0, const Vec4f& cb1) {
		orbitRibbonVerts.append(a0); orbitRibbonColors.append(ca0);
		orbitRibbonVerts.append(a1); orbitRibbonColors.append(ca1);
		orbitRibbonVerts.append(b1); orbitRibbonColors.append(cb1);

		orbitRibbonVerts.append(a0); orbitRibbonColors.append(ca0);
		orbitRibbonVerts.append(b1); orbitRibbonColors.append(cb1);
		orbitRibbonVerts.append(b0); orbitRibbonColors.append(cb0);
	};

	auto emitOrbitSubSpan = [&](int i, double spanStartF, double spanEndF, bool dashed,
		const Vec3f& coreRgb0, const Vec3f& coreRgb1) {
		const double segArc = cumArc[i + 1] - cumArc[i];
		const double subArc = segArc * (spanEndF - spanStartF);
		if (subArc <= 1e-12)
			return;
		const int subSteps = dashed
			? qBound(1, static_cast<int>(std::ceil(subArc / qMax(0.0004, dashPeriodRad * 0.20))), 16)
			: 1;
		for (int s = 0; s < subSteps; ++s)
		{
			const double f0 = spanStartF + (spanEndF - spanStartF) * (static_cast<double>(s) / static_cast<double>(subSteps));
			const double f1 = spanStartF + (spanEndF - spanStartF) * (static_cast<double>(s + 1) / static_cast<double>(subSteps));
			const double arcMid = cumArc[i] + segArc * (0.5 * (f0 + f1));
			float dashMul = 1.0f;
			if (dashed)
			{
				// Future path is drawn as a crisp dashed line anchored relative to liveArc:
				// brief breathing gap [0.00..0.38) then clean dash [0.38..1.00) with smooth AA ends.
				const double futureDist = qMax(0.0, arcMid - liveArc);
				const double cyc = std::fmod(futureDist / dashPeriodRad, 1.0);
				if (cyc < 0.38)
					continue;
				if (cyc < 0.44)
					dashMul = static_cast<float>((cyc - 0.38) / 0.06);
				else if (cyc > 0.94)
					dashMul = static_cast<float>((1.0 - cyc) / 0.06);
			}

			Vec3d p0 = j2kPts[i] * (1.0 - f0) + j2kPts[i + 1] * f0;
			Vec3d p1 = j2kPts[i] * (1.0 - f1) + j2kPts[i + 1] * f1;
			const double p0n = p0.norm(); if (p0n > 1e-10) p0 /= p0n;
			const double p1n = p1.norm(); if (p1n > 1e-10) p1 /= p1n;

			Vec3d s0 = sideVecs[i] * (1.0 - f0) + sideVecs[i + 1] * f0;
			Vec3d s1 = sideVecs[i] * (1.0 - f1) + sideVecs[i + 1] * f1;
			const double s0n = s0.norm(); if (s0n > 1e-10) s0 /= s0n;
			const double s1n = s1.norm(); if (s1n > 1e-10) s1 /= s1n;

			const double cW0 = nodeWidth[i] * (1.0 - f0) + nodeWidth[i + 1] * f0;
			const double cW1 = nodeWidth[i] * (1.0 - f1) + nodeWidth[i + 1] * f1;
			const double oW0 = cW0 * 2.15;
			const double oW1 = cW1 * 2.15;

			const float a0 = (nodeAlpha[i] * static_cast<float>(1.0 - f0) + nodeAlpha[i + 1] * static_cast<float>(f0)) * dashMul;
			const float a1 = (nodeAlpha[i] * static_cast<float>(1.0 - f1) + nodeAlpha[i + 1] * static_cast<float>(f1)) * dashMul;
			const Vec3f rgb0 = nodeRgb[i] * static_cast<float>(1.0 - f0) + nodeRgb[i + 1] * static_cast<float>(f0);
			const Vec3f rgb1 = nodeRgb[i] * static_cast<float>(1.0 - f1) + nodeRgb[i + 1] * static_cast<float>(f1);
			const Vec3f cRgb0 = coreRgb0 * static_cast<float>(1.0 - f0) + coreRgb1 * static_cast<float>(f0);
			const Vec3f cRgb1 = coreRgb0 * static_cast<float>(1.0 - f1) + coreRgb1 * static_cast<float>(f1);

			const Vec4f edge0(rgb0[0], rgb0[1], rgb0[2], 0.f);
			const Vec4f edge1(rgb1[0], rgb1[1], rgb1[2], 0.f);
			const Vec4f core0(cRgb0[0], cRgb0[1], cRgb0[2], a0);
			const Vec4f core1(cRgb1[0], cRgb1[1], cRgb1[2], a1);

			pushQuad(p0 - s0 * oW0, p0 - s0 * cW0, p1 - s1 * oW1, p1 - s1 * cW1, edge0, core0, edge1, core1);
			pushQuad(p0 - s0 * cW0, p0 + s0 * cW0, p1 - s1 * cW1, p1 + s1 * cW1, core0, core0, core1, core1);
			pushQuad(p0 + s0 * cW0, p0 + s0 * oW0, p1 + s1 * cW1, p1 + s1 * oW1, core0, edge0, core1, edge1);
		}
	};

	for (int i = 0; i < size - 1; ++i)
	{
		if (nodeAlpha[i] < 0.004f && nodeAlpha[i + 1] < 0.004f)
			continue;
		const double segDot = j2kPts[i].dot(j2kPts[i + 1]);
		if (segDot < 0.5)
			continue;

		const float boost0 = (static_cast<double>(i) >= liveIdx && visibilityPoints[i] == gSatWrapper::VISIBLE) ? 0.24f : 0.f;
		const float boost1 = (static_cast<double>(i + 1) >= liveIdx && visibilityPoints[i + 1] == gSatWrapper::VISIBLE) ? 0.24f : 0.f;
		const Vec3f coreRgb0(
			nodeRgb[i][0] + (1.f - nodeRgb[i][0]) * boost0,
			nodeRgb[i][1] + (1.f - nodeRgb[i][1]) * boost0,
			nodeRgb[i][2] + (1.f - nodeRgb[i][2]) * boost0);
		const Vec3f coreRgb1(
			nodeRgb[i + 1][0] + (1.f - nodeRgb[i + 1][0]) * boost1,
			nodeRgb[i + 1][1] + (1.f - nodeRgb[i + 1][1]) * boost1,
			nodeRgb[i + 1][2] + (1.f - nodeRgb[i + 1][2]) * boost1);

		// Past trajectory (behind satellite): solid line.
		// Future trajectory (ahead of satellite): dashed line.
		// When a chord straddles liveArc, split cleanly at the exact satellite position.
		if (cumArc[i + 1] <= liveArc)
		{
			emitOrbitSubSpan(i, 0.0, 1.0, false, coreRgb0, coreRgb1);
		}
		else if (cumArc[i] >= liveArc)
		{
			emitOrbitSubSpan(i, 0.0, 1.0, true, coreRgb0, coreRgb1);
		}
		else
		{
			const double segArc = cumArc[i + 1] - cumArc[i];
			const double splitF = (segArc > 1e-12) ? qBound(0.0, (liveArc - cumArc[i]) / segArc, 1.0) : 0.5;
			if (splitF > 1e-4)
				emitOrbitSubSpan(i, 0.0, splitF, false, coreRgb0, coreRgb1);
			if (1.0 - splitF > 1e-4)
				emitOrbitSubSpan(i, splitF, 1.0, true, coreRgb0, coreRgb1);
		}
	}

	// Selected-satellite orbital landmarks: continuously gliding direction chevrons,
	// minute ticks, shadow transitions & culmination apex (fade out smoothly on deselect)
	if ((orbitPreview || isFadingOut) && revealT > 0.35f)
	{
		const float landmarkEnv = qBound(0.f, (revealT - 0.35f) / 0.45f, 1.f) * hintBrightness * orbitFadeAlpha;
		auto emitStroke = [&](const Vec3d& a, const Vec3d& b, double halfW, const Vec4f& col) {
			Vec3d dir = b - a;
			Vec3d mid = a + b;
			Vec3d side = mid ^ dir;
			const double sn = side.norm();
			if (sn <= 1e-10) return;
			side /= sn;
			const Vec4f edgeCol(col[0], col[1], col[2], 0.f);
			const double outW = halfW * 1.9;
			pushQuad(a - side * outW, a - side * halfW, b - side * outW, b - side * halfW, edgeCol, col, edgeCol, col);
			pushQuad(a - side * halfW, a + side * halfW, b - side * halfW, b + side * halfW, col, col, col, col);
			pushQuad(a + side * halfW, a + side * outW, b + side * halfW, b + side * outW, col, edgeCol, col, edgeCol);
		};
		auto emitDiamond = [&](const Vec3d& center, const Vec3d& tanUnit, const Vec3d& sideUnit, double r, const Vec4f& col) {
			const Vec3d pN = center + tanUnit * r;
			const Vec3d pS = center - tanUnit * r;
			const Vec3d pE = center + sideUnit * r;
			const Vec3d pW = center - sideUnit * r;
			const Vec4f outer(col[0], col[1], col[2], col[3] * 0.25f);
			orbitRibbonVerts.append(center); orbitRibbonColors.append(col);
			orbitRibbonVerts.append(pN); orbitRibbonColors.append(outer);
			orbitRibbonVerts.append(pE); orbitRibbonColors.append(outer);

			orbitRibbonVerts.append(center); orbitRibbonColors.append(col);
			orbitRibbonVerts.append(pE); orbitRibbonColors.append(outer);
			orbitRibbonVerts.append(pS); orbitRibbonColors.append(outer);

			orbitRibbonVerts.append(center); orbitRibbonColors.append(col);
			orbitRibbonVerts.append(pS); orbitRibbonColors.append(outer);
			orbitRibbonVerts.append(pW); orbitRibbonColors.append(outer);

			orbitRibbonVerts.append(center); orbitRibbonColors.append(col);
			orbitRibbonVerts.append(pW); orbitRibbonColors.append(outer);
			orbitRibbonVerts.append(pN); orbitRibbonColors.append(outer);
		};

		// Continuous arc-length sampler along the orbit polyline so forward chevrons
		// glide smoothly ahead of the satellite every frame instead of freezing on discrete nodes.
		auto sampleOrbitAtArc = [&](double targetArc, Vec3d& outPos, Vec3d& outFwd, Vec3d& outSide, double& outAltSin) -> bool {
			if (targetArc <= cumArc[0] || targetArc >= cumArc[size - 1])
				return false;
			const auto it = std::upper_bound(cumArc.cbegin(), cumArc.cend(), targetArc);
			int seg = static_cast<int>(it - cumArc.cbegin()) - 1;
			seg = qBound(0, seg, size - 2);
			const double segLen = cumArc[seg + 1] - cumArc[seg];
			if (segLen <= 1e-12 || j2kPts[seg].dot(j2kPts[seg + 1]) < 0.5)
				return false;
			const double t = qBound(0.0, (targetArc - cumArc[seg]) / segLen, 1.0);
			outPos = j2kPts[seg] * (1.0 - t) + j2kPts[seg + 1] * t;
			const double pn = outPos.norm();
			if (pn <= 1e-10) return false;
			outPos /= pn;
			Vec3d tan = j2kPts[seg + 1] - j2kPts[seg];
			tan -= outPos * outPos.dot(tan);
			const double tn = tan.norm();
			if (tn <= 1e-10) return false;
			outFwd = tan / tn;
			outSide = outPos ^ outFwd;
			const double sn = outSide.norm();
			if (sn <= 1e-10) return false;
			outSide /= sn;
			outAltSin = altSin[seg] * (1.0 - t) + altSin[seg + 1] * t;
			return true;
		};

		// 1. Continuously gliding forward motion chevrons ahead of the live satellite position
		const int maxRevealIdx = qBound(0, static_cast<int>(std::floor(liveIdx + revealSpanIdx - 2.0)), size - 1);
		const double maxFutureRevealArc = cumArc[maxRevealIdx];
		const double chevronTargetArc = qBound(0.012, 30.0 * screenScale * radPerPx, 0.055);
		const double chevronSpacingArc = qBound(0.045, 115.0 * screenScale * radPerPx, 0.22);
		const double armLen = qBound(0.0014, 6.5 * screenScale * radPerPx, 0.022);
		for (int cIdx = 0; cIdx < 3; ++cIdx)
		{
			const double targetArc = liveArc + chevronTargetArc + static_cast<double>(cIdx) * chevronSpacingArc;
			if (targetArc >= maxFutureRevealArc)
				break;
			Vec3d pos, fwd, side;
			double chevAltSin = 0.0;
			if (!sampleOrbitAtArc(targetArc, pos, fwd, side, chevAltSin))
				continue;
			if (chevAltSin < 0.0)
				continue;
			const Vec3d tip = pos + fwd * (armLen * 0.45);
			const Vec3d wingL = tip - fwd * armLen - side * (armLen * 0.68);
			const Vec3d wingR = tip - fwd * armLen + side * (armLen * 0.68);
			const float chevAlpha = (cIdx == 0 ? 0.94f : (cIdx == 1 ? 0.74f : 0.56f)) * landmarkEnv;
			const Vec4f chevCol(0.84f, 0.96f, 1.0f, chevAlpha);
			emitStroke(wingL, tip, baseCoreW * 0.95, chevCol);
			emitStroke(wingR, tip, baseCoreW * 0.95, chevCol);
		}

		// 2. Subtle time ticks along the future above-horizon arc (every 60s for LEO, 600s for MEO/GSO)
		const double tickIntervalSec = (orbitStepSeconds <= 12.0) ? 60.0 : 600.0;
		const int tickStride = qMax(4, static_cast<int>(std::lround(tickIntervalSec / qMax(1.0, orbitStepSeconds))));
		const double tickHalfLen = qBound(0.0006, 3.2 * screenScale * radPerPx, 0.011);
		const int firstTickIdx = qMax(centerIdx + tickStride, static_cast<int>(std::ceil(liveIdx)) + 2);
		for (int i = firstTickIdx; i < size - 2; i += tickStride)
		{
			if (static_cast<float>(i) - static_cast<float>(liveIdx) > revealSpanIdx - 2.0f)
				break;
			if (altSin[i] < 0.02 || nodeAlpha[i] < 0.12f)
				continue;
			const Vec3d a = j2kPts[i] - sideVecs[i] * tickHalfLen;
			const Vec3d b = j2kPts[i] + sideVecs[i] * tickHalfLen;
			const Vec4f tickCol(nodeRgb[i][0], nodeRgb[i][1], nodeRgb[i][2], qMin(0.85f, nodeAlpha[i] * 0.95f) * landmarkEnv);
			emitStroke(a, b, baseCoreW * 0.62, tickCol);
		}

		// 3. Earth-shadow entry/exit marker & pass culmination (apex) diamond
		int apexIdx = -1;
		double bestAltSin = 0.14; // > ~8 deg altitude
		for (int i = 1; i < size - 1; ++i)
		{
			const float distIdx = std::fabs(static_cast<float>(i) - static_cast<float>(centerIdx));
			if (distIdx > revealSpanIdx - 1.5f)
				continue;
			if (altSin[i] > bestAltSin)
			{
				bestAltSin = altSin[i];
				apexIdx = i;
			}
			// Sunlit <-> Eclipsed transition above horizon
			const bool curSun = (visibilityPoints[i] == gSatWrapper::VISIBLE);
			const bool prvSun = (visibilityPoints[i - 1] == gSatWrapper::VISIBLE);
			const bool curShd = (visibilityPoints[i] == gSatWrapper::RADAR_NIGHT || visibilityPoints[i] == gSatWrapper::ANNULAR);
			const bool prvShd = (visibilityPoints[i - 1] == gSatWrapper::RADAR_NIGHT || visibilityPoints[i - 1] == gSatWrapper::ANNULAR);
			if (altSin[i] >= 0.02 && ((curSun && prvShd) || (prvSun && curShd)))
			{
				Vec3d tan = j2kPts[i + 1] - j2kPts[i - 1];
				const double tn = tan.norm();
				if (tn > 1e-10)
				{
					tan /= tn;
					const double r = qBound(0.0010, 4.4 * screenScale * radPerPx, 0.016);
					emitDiamond(j2kPts[i], tan, sideVecs[i], r, Vec4f(1.0f, 0.82f, 0.44f, 0.95f * landmarkEnv));
				}
			}
		}
		if (apexIdx > 1 && apexIdx < size - 2 && qAbs(apexIdx - centerIdx) >= 3)
		{
			Vec3d tan = j2kPts[apexIdx + 1] - j2kPts[apexIdx - 1];
			const double tn = tan.norm();
			if (tn > 1e-10)
			{
				tan /= tn;
				const double r = qBound(0.0011, 4.8 * screenScale * radPerPx, 0.017);
				emitDiamond(j2kPts[apexIdx], tan, sideVecs[apexIdx], r, Vec4f(0.86f, 0.96f, 1.0f, 0.92f * landmarkEnv));
			}
		}
	}

	if (!orbitRibbonVerts.isEmpty())
	{
		painter.setBlending(true, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		painter.enableClientStates(true, false, true);
		painter.setVertexPointer(3, GL_DOUBLE, orbitRibbonVerts.constData());
		painter.setColorPointer(4, GL_FLOAT, orbitRibbonColors.constData());
		painter.drawFromArray(StelPainter::Triangles, orbitRibbonVerts.size(), 0, true);
		painter.setBlending(false);
		painter.enableClientStates(false);
		++orbitDrawCount;
		orbitLastDrawJD = core->getJD();
	}
}

float Satellite::calculateOrbitSegmentIntensity(int segNum)
{
	const int endDist = (orbitLineSegments/2) - abs(segNum-1 - (orbitLineSegments/2) % orbitLineSegments);
	if (endDist > orbitLineFadeSegments)
		return 1.0;
	else
		return (endDist  + 1) / (orbitLineFadeSegments + 1.0);
}

void Satellite::computeOrbitPoints()
{
	const auto validSample = [this]() {
		if (pSatWrapper->getPropagationStatus() == QLatin1String("valid"))
		{
			const Vec3d sample = pSatWrapper->getAltAz();
			if (std::isfinite(sample[0]) && std::isfinite(sample[1]) && std::isfinite(sample[2]) && sample.normSquared() > 0.)
				return true;
		}
		recalculateOrbitLines();
		pSatWrapper->setEpoch(epochTime);
		return false;
	};
	// Adaptive per-satellite sampling step: keeps LEO passes silky-smooth (~6s chords over ±9 min)
	// while scaling proportionally for MEO/HEO/GSO so high-altitude satellites also reveal a full arc.
	const double orbitalPeriodMin = pSatWrapper ? pSatWrapper->getOrbitalPeriod() : 95.0;
	int effectiveSegSec = qMax(2, orbitLineSegmentDuration);
	if (orbitPreview)
	{
		if (orbitalPeriodMin > 900.0)
			effectiveSegSec = qBound(30, static_cast<int>(std::lround(orbitalPeriodMin * 60.0 * 0.18 / qMax(1, orbitLineSegments))), 90);
		else if (orbitalPeriodMin > 150.0)
			effectiveSegSec = qBound(15, static_cast<int>(std::lround(orbitalPeriodMin * 60.0 * 0.25 / qMax(1, orbitLineSegments))), 60);
		else if (effectiveSegSec <= 5)
			effectiveSegSec = 6;
	}
	if (lastOrbitStepSeconds > 0.0 && std::fabs(lastOrbitStepSeconds - static_cast<double>(effectiveSegSec)) > 0.5)
	{
		orbitPoints.clear();
		visibilityPoints.clear();
	}
	orbitStepSeconds = static_cast<double>(effectiveSegSec);
	lastOrbitStepSeconds = orbitStepSeconds;

	gTimeSpan computeInterval(0, 0, 0, effectiveSegSec);
	gTimeSpan orbitSpan(0, 0, 0, orbitLineSegments * effectiveSegSec / 2);
	gTime epochTm;
	gTime epoch(epochTime);
	gTime lastEpochComp(lastEpochCompForOrbit);	
	int diffSlots;

	if (orbitPoints.isEmpty())//Setup orbitPoints
	{
		epochTm  = epoch - orbitSpan;

		for (int i=0; i<=orbitLineSegments; i++)
		{
			pSatWrapper->setEpoch(epochTm.getGmtTm());
			if (!validSample()) return;
			Vec3d sat = pSatWrapper->getAltAz();
			orbitPoints.append(Vec4d(sat[0],sat[1],sat[2],pSatWrapper->getSubPoint()[2]));
			visibilityPoints.append(pSatWrapper->getVisibilityPredict());
			epochTm    += computeInterval;
		}
		lastEpochCompForOrbit = epochTime;
	}
	else if (epochTime > lastEpochCompForOrbit)
	{
		// compute next orbit point when clock runs forward
		gTimeSpan diffTime = epoch - lastEpochComp;
		diffSlots          = static_cast<int>(diffTime.getDblSeconds()/effectiveSegSec);

		if (diffSlots > 0)
		{
			if (diffSlots > orbitLineSegments)
			{
				diffSlots = orbitLineSegments + 1;
				epochTm  = epoch - orbitSpan;
			}
			else
			{
				epochTm   = lastEpochComp + orbitSpan + computeInterval;
			}

			for (int i=0; i<diffSlots; i++)
			{
				//remove points at beginning of list and add points at end.
				orbitPoints.removeFirst();
				visibilityPoints.removeFirst();
				pSatWrapper->setEpoch(epochTm.getGmtTm());
				if (!validSample()) return;
				Vec3d sat = pSatWrapper->getAltAz();
				orbitPoints.append(Vec4d(sat[0],sat[1],sat[2],pSatWrapper->getSubPoint()[2]));
				visibilityPoints.append(pSatWrapper->getVisibilityPredict());
				epochTm    += computeInterval;
			}

			lastEpochCompForOrbit = epochTime;
		}
	}
	else if (epochTime < lastEpochCompForOrbit)
	{
		// compute next orbit point when clock runs backward
		gTimeSpan diffTime = lastEpochComp - epoch;
		diffSlots          = static_cast<int>(diffTime.getDblSeconds()/effectiveSegSec);

		if (diffSlots > 0)
		{
			if (diffSlots > orbitLineSegments)
			{
				diffSlots = orbitLineSegments + 1;
				epochTm   = epoch + orbitSpan;
			}
			else
			{
				epochTm   = epoch - orbitSpan - computeInterval;
			}
			for (int i=0; i<diffSlots; i++)
			{ //remove points at end of list and add points at beginning.
				orbitPoints.removeLast();
				visibilityPoints.removeLast();
				pSatWrapper->setEpoch(epochTm.getGmtTm());
				if (!validSample()) return;
				Vec3d sat = pSatWrapper->getAltAz();
				orbitPoints.push_front(Vec4d(sat[0],sat[1],sat[2],pSatWrapper->getSubPoint()[2]));
				visibilityPoints.push_front(pSatWrapper->getVisibilityPredict());
				epochTm -= computeInterval;
			}
			lastEpochCompForOrbit = epochTime;
		}
	}
	pSatWrapper->setEpoch(epochTime);
}

bool operator <(const SatelliteP& left, const SatelliteP& right)
{
	if (left.isNull())
	{
		if (right.isNull())
			return false;
		else
			return true;
	}
	if (right.isNull())
		return false; // No sense to check the left one now
	
	return ((*left) < (*right));
}
