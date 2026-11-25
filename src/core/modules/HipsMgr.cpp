/*
 * Stellarium
 * Copyright (C) 2017 Guillaume Chereau
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
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#include "HipsMgr.hpp"
#include "StelHips.hpp"
#include "StelPainter.hpp"
#include "StelCore.hpp"
#include "StelApp.hpp"
#include "StelFileMgr.hpp"
#include "StelTranslator.hpp"
#include "StelUtils.hpp"

#include <QFileInfo>
#include <QNetworkReply>
#include <QSettings>
#include <QSignalBlocker>
#include <QTimer>

Q_LOGGING_CATEGORY(HiPS,"stel.HiPS", QtInfoMsg)

namespace
{
struct SpectralDataset
{
	const char* id;
	const char* title;
	const char* band;
	const char* surveyUrl;
	const char* frame;
	const char* offlineAllskyFile;
	const char* source;
	const char* coverage;
	const char* license;
	const char* attribution;
};

const QList<SpectralDataset>& spectralDatasetCatalog()
{
	static const QList<SpectralDataset> catalog = {
		{
			"dss2-color", "DSS2 光学彩色巡天", "可见光",
			"https://hips.china-vo.org/m/CDS_P_DSS2_color",
			"equatorial", "data/surveys/dss2-color_allsky.jpg",
			"China-VO · DSS2 Color",
			"全天光学深度底片合成，缩放自动加载高清瓦片",
			"科研公开巡天数据（署名使用）", "STScI / DSS2 / China-VO"
		},
		{
			"finkbeiner-ha", "Finkbeiner 氢阿尔法", "Hα 发射线",
			"https://skies.esac.esa.int/FinkbeinerHa",
			"galactic", "data/surveys/finkbeiner-ha_allsky.jpg",
			"ESA Sky · Hα All-Sky",
			"全天 Hα 氢发射星云分布，突出巴纳德环与银道星云",
			"科研公开巡天数据（署名使用）", "Finkbeiner (2003) / ESA"
		},
		{
			"2mass-color", "2MASS 近红外彩色", "近红外",
			"https://hips.china-vo.org/m/CDS_P_2MASS_color",
			"equatorial", "data/surveys/2mass-color_allsky.jpg",
			"China-VO · 2MASS J/H/K",
			"近红外 J/H/K 合成，穿透星际尘埃呈现银河系核心",
			"科研公开巡天数据（署名使用）", "UMass / IPAC / Caltech / China-VO"
		},
		{
			"allwise-color", "AllWISE 中红外尘埃", "中红外",
			"https://hips.china-vo.org/m/CDS_P_allWISE_color",
			"equatorial", "data/surveys/allwise-color_allsky.jpg",
			"China-VO · AllWISE W1/W2/W4",
			"中红外全天尘埃与恒星形成区，色彩层次极其丰富",
			"科研公开巡天数据（署名使用）", "NASA / JPL-Caltech / UCLA / China-VO"
		},
		{
			"planck-lfi", "Planck 微波全天", "微波",
			"https://hips.china-vo.org/m/CDS_P_PLANCK_R2_LFI_color",
			"galactic", "data/surveys/planck-lfi_allsky.jpg",
			"China-VO · Planck LFI",
			"全天微波辐射与宇宙微波背景、银道面冷尘埃分布",
			"ESA 公开巡天数据（署名使用）", "ESA / Planck / China-VO"
		},
		{
			"haslam-radio", "Haslam 408 MHz 射电", "射电",
			"https://skies.esac.esa.int/Haslam/Haslam408_dsds_Remazeilles2014_mod_HiPS",
			"galactic", "data/surveys/haslam-radio_allsky.jpg",
			"ESA Sky · Haslam 408 MHz",
			"全天 408 MHz 射电连续谱，展示银盘同步辐射与北极支",
			"科研公开巡天数据（署名使用）", "Haslam et al. / Remazeilles / ESA"
		},
		{
			"galex-nuv", "GALEX 紫外全天", "紫外",
			"https://hips.china-vo.org/m/CDS_P_GALEXGR6_AIS_color",
			"equatorial", "data/surveys/galex-nuv_allsky.jpg",
			"China-VO · GALEX GR6/7",
			"紫外全天巡天（约 78% 覆盖），突出年轻炽热恒星",
			"NASA 公开巡天数据（署名使用）", "NASA / Caltech / STScI / China-VO"
		},
		{
			"rass-xray", "eROSITA 软 X 射线", "X 射线",
			"https://erosita.mpe.mpg.de/erodat/static/hips/eRASS1_RGB_Rate_c010",
			"equatorial", "data/surveys/rass-xray_allsky.jpg",
			"MPE · SRG/eROSITA DR1",
			"0.2–2.0 keV 软 X 射线西银半球巡天，可见超新星遗迹与 eROSITA 泡",
			"MPE 公开数据释放 DR1（署名使用）", "MPE / eROSITA-DE"
		},
		{
			"fermi-gamma", "Fermi 伽马射线全天", "伽马射线",
			"https://skies.esac.esa.int/FermiColor",
			"equatorial", "data/surveys/fermi-gamma_allsky.jpg",
			"ESA Sky · Fermi LAT Color",
			"全天高能伽马射线分布，展示脉冲星、活动星系核与银盘辐射",
			"NASA/ESA 公开巡天数据（署名使用）", "NASA / Fermi-LAT / ESA"
		}
	};
	return catalog;
}

QString resolveOfflineAllskyPath(const char* relativePath)
{
	if (!relativePath || !relativePath[0])
		return QString();
	const QString rel = QString::fromUtf8(relativePath);
	const QString found = StelFileMgr::findFile(rel);
	if (!found.isEmpty() && QFileInfo::exists(found))
		return found;
	const QString dataRoot = qEnvironmentVariable("STELLARIUM_DATA_ROOT");
	if (!dataRoot.isEmpty())
	{
		const QString candidate = dataRoot + QLatin1Char('/') + rel;
		if (QFileInfo::exists(candidate))
			return candidate;
	}
	return QString();
}

bool isSpectralSurveyUrl(const QString& url)
{
	for (const SpectralDataset& descriptor : spectralDatasetCatalog())
	{
		if (url == QString::fromUtf8(descriptor.surveyUrl)) return true;
	}
	return false;
}
}

HipsMgr::HipsMgr()
{
	setObjectName("HipsMgr");
	connect(this, &HipsMgr::surveysChanged, this, &HipsMgr::restoreVisibleSurveys);
}

HipsMgr::~HipsMgr()
{
#if (QT_VERSION<QT_VERSION_CHECK(6,0,0))
	// This function is no longer available in Qt6. We assume it is OK to run the code in any case, even if we were not connected.
	if (StelApp::getInstance().getNetworkAccessManager()->networkAccessible()==QNetworkAccessManager::Accessible)
#endif
	{
		// Store active HiPS to config.ini if network is available
		QSettings* conf = StelApp::getInstance().getSettings();
		conf->beginGroup("hips");
		conf->setValue("show", getFlagShow());
		conf->setValue("show_atmospheric_extinction", getFlagShowAtmosphericExtinction());

		// remove 0.18.0 scheme
		conf->remove("visible");

		QStringList surveyUrls;
		for (auto &survey: surveys)
		{
			if (survey->isVisible() && survey->planet.isEmpty() && !isSpectralSurveyUrl(survey->getUrl()))
				surveyUrls << survey->getUrl();
		}

		int surveyListSize = surveyUrls.count();
		if (surveyListSize==0)
		{
			// remove old urls
			conf->remove("surveys");
		}
		else
		{
			conf->beginWriteArray("surveys");
			for(int i=0;i<surveyListSize;i++)
			{
				conf->setArrayIndex(i);
				conf->setValue("url", surveyUrls.at(i));
			}
			conf->endArray();
		}

		conf->remove("surveySettings");
		int settingsIndex = 0;
		conf->beginWriteArray("surveySettings");
		for (auto &survey: surveys)
		{
			if (survey->isPlanetarySurvey() || survey->hasDefaultDisplaySettings() || isSpectralSurveyUrl(survey->getUrl()))
				continue;
			conf->setArrayIndex(settingsIndex++);
			conf->setValue("url", survey->getUrl());
			conf->setValue("gamma", survey->getGamma());
			conf->setValue("saturation", survey->getSaturation());
			conf->setValue("brightness", survey->getBrightness());
			conf->setValue("contrast", survey->getContrast());
			conf->setValue("opacity", survey->getOpacity());
			conf->setValue("colorChannel", survey->getColorChannel());
			conf->setValue("invertedColors", survey->getInvertedColors());
		}
		conf->endArray();

		conf->endGroup();
		conf->sync();
	}
}

void HipsMgr::loadSources()
{
	if (state != Created)
		return; // Already loaded.

	state = Loading;
	emit stateChanged(state);
	QSettings* conf = StelApp::getInstance().getSettings();
	conf->beginGroup("hips");

	// Start to load survey lists
	QStringList sources;
	int size = conf->beginReadArray("sources");
	for (int i = 0; i < size; i++)
	{
		conf->setArrayIndex(i);
		sources << conf->value("url").toString();
	}
	conf->endArray();

	// Use fast reachable HiPS registries (China-VO & ESA Sky) plus data.stellarium.org:
	if (sources.isEmpty())
	{
		sources << "https://hips.china-vo.org/hipslist"
			<< "https://skies.esac.esa.int/hipslist"
			<< "https://data.stellarium.org/surveys/hipslist";
	}

	for (QUrl source: std::as_const(sources))
	{
		if (source.scheme().isEmpty()) source.setScheme("file");
		QNetworkRequest req = QNetworkRequest(source);
		req.setRawHeader("User-Agent", StelUtils::getUserAgentString().toLatin1());
		QNetworkReply* networkReply = StelApp::getInstance().getNetworkAccessManager()->get(req);
		connect(networkReply, &QNetworkReply::finished, this, [=] {
			QByteArray data = networkReply->readAll();
			QList<HipsSurveyP> newSurveys = HipsSurvey::parseHipslist(source.toString(), data);
			for (HipsSurveyP &survey: newSurveys)
			{
				connect(survey.data(), &HipsSurvey::propertiesChanged, this, &HipsMgr::surveysChanged);
				connect(survey.data(), &HipsSurvey::visibleChanged, this, &HipsMgr::updateActiveSurveys);
				connect(survey.data(), &HipsSurvey::displaySettingsChanged, this, &HipsMgr::saveSurveySettings);
				emit gotNewSurvey(survey);
			}
			surveys += newSurveys;
			emit surveysChanged();
			nbSourcesLoaded++;
			if (nbSourcesLoaded == sources.size())
			{
				state = Loaded;
				emit stateChanged(state);
			}
		});
	}
	conf->endGroup();
}

void HipsMgr::init()
{
	QSettings* conf = StelApp::getInstance().getSettings();
	conf->beginGroup("hips");
	setFlagShow(conf->value("show", false).toBool());
	flagShowAtmosphericExtinction = conf->value("show_atmospheric_extinction", false).toBool();
	int size = conf->beginReadArray("surveys");
	conf->endArray();	
	conf->endGroup();
	bool hasVisibleSurvey = size>0 ? true: false;

#if (QT_VERSION<QT_VERSION_CHECK(6,0,0))
	// In Qt6 we don't have the online check. We could ping somewhere, or just live with it.
	// There is QNetworkInformation in Qt6.1, but it may give wrong results under certain circumstances.
	// https://doc.qt.io/qt-6/qnetworkinformation.html
	if (StelApp::getInstance().getNetworkAccessManager()->networkAccessible()==QNetworkAccessManager::NotAccessible)
	{
		setFlagShow(false);
		hasVisibleSurvey = false;
	}
#endif
	addAction("actionShow_Hips_Surveys", N_("Display Options"), N_("Toggle Hierarchical Progressive Surveys"), "flagShow", "Ctrl+Alt+D");
	addAction("actionShow_Hips_Surveys_dialog", N_("Display Options"), N_("Toggle HiPS dialog"), this, [this]{emit toggleDialog();});

	// Start loading the sources only after stellarium has time to set up the proxy.
	// We only do it if we actually have a visible survey.  Otherwise it's
	// better not to do it until the user open the survey ui so that we
	// don't make a systematic request to the hipslist files!
	if (hasVisibleSurvey)
		QTimer::singleShot(0, this, &HipsMgr::loadSources);
	initialized = true;
}


void HipsMgr::restoreVisibleSurveys()
{
	qCDebug(HiPS) << "HipsMgr::restoreVisibleSurveys()";
	QSettings* conf = StelApp::getInstance().getSettings();
	conf->beginGroup("hips");

	// Start to load survey lists
	int size = conf->beginReadArray("surveys");
	for (int i = 0; i < size; i++)
	{
		conf->setArrayIndex(i);
		QString url = conf->value("url").toString();
		if (!url.isEmpty())
		{
			qCDebug(HiPS) << "HiPS: Restore visible survey:" << url;
			HipsSurveyP survey=getSurveyByUrl(url);
			if (survey)
				survey->setVisible(true);
		}
	}
	conf->endArray();

	size = conf->beginReadArray("surveySettings");
	for (int i = 0; i < size; i++)
	{
		conf->setArrayIndex(i);
		const QString url = conf->value("url").toString();
		if (isSpectralSurveyUrl(url)) continue;
		HipsSurveyP survey = getSurveyByUrl(url);
		if (survey && !survey->isPlanetarySurvey())
		{
			const QSignalBlocker blocker(survey.data());
			survey->setDisplaySettings(conf->value("gamma", 1.).toFloat(),
			                           conf->value("saturation", 1.).toFloat(),
			                           conf->value("brightness", 1.).toFloat(),
			                           conf->value("contrast", 1.).toFloat(),
			                           conf->value("opacity", 1.).toFloat(),
			                           conf->value("colorChannel", HipsSurvey::ColorChannelRgb).toInt(),
			                           conf->value("invertedColors", false).toBool());
		}
	}
	conf->endArray();
	conf->endGroup();
}

void HipsMgr::saveSurveySettings() const
{
	QSettings* conf = StelApp::getInstance().getSettings();
	conf->beginGroup("hips");
	conf->remove("surveySettings");
	int settingsIndex = 0;
	conf->beginWriteArray("surveySettings");
	for (auto &survey: surveys)
	{
		if (survey->isPlanetarySurvey() || survey->hasDefaultDisplaySettings() || isSpectralSurveyUrl(survey->getUrl()))
			continue;
		conf->setArrayIndex(settingsIndex++);
		conf->setValue("url", survey->getUrl());
		conf->setValue("gamma", survey->getGamma());
		conf->setValue("saturation", survey->getSaturation());
		conf->setValue("brightness", survey->getBrightness());
		conf->setValue("contrast", survey->getContrast());
		conf->setValue("opacity", survey->getOpacity());
		conf->setValue("colorChannel", survey->getColorChannel());
		conf->setValue("invertedColors", survey->getInvertedColors());
	}
	conf->endArray();
	conf->endGroup();
}

void HipsMgr::deinit()
{
}

void HipsMgr::draw(StelCore* core)
{
	if (!visible) return;
	StelPainter sPainter(core->getProjection(StelCore::FrameJ2000));
	for (auto &survey: activeSurveys)
	{
		if (survey->isVisible() && survey->planet.isEmpty())
		{
			survey->draw(&sPainter, 2.0 * M_PI, Q_NULLPTR, flagShowAtmosphericExtinction);
		}
	}
}

void HipsMgr::update(double deltaTime)
{
	for (auto it = activeSurveys.begin(); it != activeSurveys.end();)
	{
		const auto &survey = *it;
		survey->fader.update(static_cast<int>(deltaTime * 1000));
		if (!survey->isVisible() && survey->fader.getInterstate() == 0.f)
			it = activeSurveys.erase(it);
		else
			++it;
	}
}

double HipsMgr::getCallOrder(StelModuleActionName actionName) const
{
	if (actionName==StelModule::ActionDraw)
		return 7;
	return 0;
}

HipsSurveyP HipsMgr::getSurveyByUrl(const QString &url)
{
	for (auto &survey: surveys)
	{
		if (survey->getUrl() == url) return survey;
	}
	return HipsSurveyP(Q_NULLPTR);
}

int HipsMgr::getVisibleSurveyCount() const
{
	int count = 0;
	for (const auto& survey : surveys)
		if (survey->isVisible() && !survey->isPlanetarySurvey())
			++count;
	return count;
}

QJsonArray HipsMgr::getSpectralDatasets() const
{
	QJsonArray datasets;
	for (const SpectralDataset& descriptor : spectralDatasetCatalog())
	{
		QJsonObject item;
		const QString id = QString::fromUtf8(descriptor.id);
		const HipsSurveyP survey = spectralSurveys.value(id);
		const bool hasLocalAllsky = survey
			? survey->hasOfflineAllsky()
			: !resolveOfflineAllskyPath(descriptor.offlineAllskyFile).isEmpty();
		const bool hdReady = survey && survey->isRemotePropertiesLoaded() && survey->hasValidProperties();
		const bool enabled = visible && survey && survey->isVisible();
		item["id"] = id;
		item["title"] = QString::fromUtf8(descriptor.title);
		item["band"] = QString::fromUtf8(descriptor.band);
		item["source"] = QString::fromUtf8(descriptor.source);
		item["coverage"] = QString::fromUtf8(descriptor.coverage);
		item["license"] = QString::fromUtf8(descriptor.license);
		item["attribution"] = QString::fromUtf8(descriptor.attribution);
		item["licenseReviewRequired"] = false;
		item["networkPolicy"] = hasLocalAllsky ? QStringLiteral("offline-first-hd-online") : QStringLiteral("user-initiated");
		item["timeoutSeconds"] = 12;
		item["surveyUrl"] = QString::fromUtf8(descriptor.surveyUrl);
		item["available"] = true;
		item["enabled"] = enabled;
		item["loading"] = survey && survey->isLoading();
		item["offlineReady"] = hasLocalAllsky;
		item["hdReady"] = hdReady;
		item["ready"] = hdReady || hasLocalAllsky;
		item["opacity"] = survey ? static_cast<double>(survey->getOpacity()) : static_cast<double>(spectralOpacity);
		item["error"] = (survey && !hdReady) ? survey->getLastError() : QString();
		datasets.append(item);
	}
	return datasets;
}

QJsonObject HipsMgr::getSpectralState() const
{
	QJsonObject state;
	state["enabled"] = false;
	state["datasetId"] = QString();
	state["loading"] = false;
	state["ready"] = false;
	state["hdReady"] = false;
	state["offlineReady"] = false;
	state["opacity"] = static_cast<double>(spectralOpacity);
	state["visibleTiles"] = 0;
	state["loadedTiles"] = 0;
	state["error"] = QString();
	if (!visible)
		return state;
	for (const SpectralDataset& descriptor : spectralDatasetCatalog())
	{
		const QString id = QString::fromUtf8(descriptor.id);
		const HipsSurveyP survey = spectralSurveys.value(id);
		if (!survey || !survey->isVisible()) continue;
		const bool hdReady = survey->isRemotePropertiesLoaded() && survey->hasValidProperties();
		const bool offlineReady = survey->hasOfflineAllsky();
		state["enabled"] = true;
		state["datasetId"] = id;
		state["loading"] = survey->isLoading();
		state["hdReady"] = hdReady;
		state["offlineReady"] = offlineReady;
		state["ready"] = hdReady || offlineReady;
		state["opacity"] = static_cast<double>(survey->getOpacity());
		state["visibleTiles"] = survey->getVisibleTileCount();
		state["loadedTiles"] = survey->getLoadedTileCount();
		state["error"] = hdReady ? QString() : survey->getLastError();
		break;
	}
	return state;
}

bool HipsMgr::setSpectralView(const QString& datasetId, const bool enabled, QString* error)
{
	const SpectralDataset* descriptor = nullptr;
	for (const SpectralDataset& candidate : spectralDatasetCatalog())
	{
		if (datasetId == QString::fromUtf8(candidate.id))
		{
			descriptor = &candidate;
			break;
		}
	}
	if (!descriptor)
	{
		if (error) *error = QStringLiteral("unknown spectral dataset: %1").arg(datasetId);
		return false;
	}

	if (!enabled)
	{
		if (spectralSurveys.contains(datasetId)) spectralSurveys.value(datasetId)->setVisible(false);
		emit surveysChanged();
		return true;
	}

	lastSpectralDatasetId = datasetId;
	for (auto it = spectralSurveys.cbegin(); it != spectralSurveys.cend(); ++it)
		if (it.key() != datasetId && it.value()) it.value()->setVisible(false);

	HipsSurveyP survey = spectralSurveys.value(datasetId);
	if (!survey)
	{
		const QString frame = QString::fromUtf8(descriptor->frame);
		QMap<QString, QString> initialProperties;
		initialProperties.insert(QStringLiteral("obs_title"), QString::fromUtf8(descriptor->title));
		initialProperties.insert(QStringLiteral("hips_frame"), frame);
		initialProperties.insert(QStringLiteral("hips_status"), QStringLiteral("public master clonableOnce"));
		survey = HipsSurveyP(new HipsSurvey(QString::fromUtf8(descriptor->surveyUrl), QStringLiteral("spectral"), frame, QStringLiteral("image"), initialProperties));
		const QString offlinePath = resolveOfflineAllskyPath(descriptor->offlineAllskyFile);
		if (!offlinePath.isEmpty())
			survey->setOfflineAllskyPath(offlinePath, 3);
		survey->setOpacity(spectralOpacity);
		connect(survey.data(), &HipsSurvey::propertiesChanged, this, &HipsMgr::surveysChanged);
		connect(survey.data(), &HipsSurvey::visibleChanged, this, &HipsMgr::updateActiveSurveys);
		connect(survey.data(), &HipsSurvey::displaySettingsChanged, this, &HipsMgr::saveSurveySettings);
		spectralSurveys.insert(datasetId, survey);
		surveys.append(survey);
		emit gotNewSurvey(survey);
	}
	else
	{
		survey->setOpacity(spectralOpacity);
		if (!survey->isRemotePropertiesLoaded() && !survey->isLoading())
			survey->retryProperties();
	}
	visible = true;
	emit showChanged(true);
	survey->setVisible(true);
	updateActiveSurveys();
	emit surveysChanged();
	return true;
}

void HipsMgr::setSpectralOpacity(float opacity)
{
	spectralOpacity = qBound(0.1f, opacity, 1.0f);
	for (auto it = spectralSurveys.cbegin(); it != spectralSurveys.cend(); ++it)
	{
		if (it.value())
			it.value()->setOpacity(spectralOpacity);
	}
}

void HipsMgr::closeSpectralView()
{
	for (auto it = spectralSurveys.cbegin(); it != spectralSurveys.cend(); ++it)
		if (it.value()) it.value()->setVisible(false);
	if (getVisibleSurveyCount() == 0 && visible)
	{
		visible = false;
		emit showChanged(false);
	}
	emit surveysChanged();
}

bool HipsMgr::getFlagShow(void) const
{
	return visible;
}

void HipsMgr::setFlagShow(bool b)
{
	const bool changed = (visible != b);
	if (changed)
	{
		visible = b;
		emit showChanged(b);
	}
	if (!b)
	{
		for (auto &survey: surveys)
		{
			if (survey->isVisible())
				survey->hideProgressBar();
		}
	}
	else if (initialized && getVisibleSurveyCount() == 0)
	{
		// Turning on the HiPS master switch with no active survey should
		// immediately show the last selected (or default optical DSS2) survey.
		const QString fallbackId = lastSpectralDatasetId.isEmpty()
			? QStringLiteral("dss2-color")
			: lastSpectralDatasetId;
		setSpectralView(fallbackId, true);
	}
}

void HipsMgr::setFlagShowAtmosphericExtinction(bool b)
{
	if (flagShowAtmosphericExtinction == b)
		return;
	flagShowAtmosphericExtinction = b;
	StelApp::immediateSave("hips/show_atmospheric_extinction", b);
	emit flagShowAtmosphericExtinctionChanged(b);
}

void HipsMgr::updateActiveSurveys()
{
	activeSurveys.clear();
	for (auto &survey: surveys)
	{
		if (survey->isVisible() || survey->fader.getInterstate() > 0.f)
			activeSurveys << survey;
	}
}
