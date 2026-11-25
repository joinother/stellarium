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
#include "LandscapeMgr.hpp"
#include "ToastMgr.hpp"
#include "StelHips.hpp"
#include "StelModuleMgr.hpp"
#include "StelMovementMgr.hpp"
#include "StelOpenGL.hpp"
#include "StelPainter.hpp"
#include "StelProjector.hpp"
#include "StelCore.hpp"
#include "StelApp.hpp"
#include "StelFileMgr.hpp"
#include "StelTexture.hpp"
#include "StelTextureMgr.hpp"
#include "StelTranslator.hpp"
#include "StelUtils.hpp"

#include <QFileInfo>
#include <QNetworkReply>
#include <QOpenGLBuffer>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QOpenGLShaderProgram>
#include <QOpenGLVertexArrayObject>
#include <QSettings>
#include <QSignalBlocker>
#include <QTimer>

Q_LOGGING_CATEGORY(HiPS,"stel.HiPS", QtInfoMsg)

namespace
{
constexpr int PANO_FS_QUAD_COORDS_PER_VERTEX = 2;
constexpr int PANO_VERTEX_ATTRIB_INDEX = 0;

struct SpectralDataset
{
	const char* id;
	const char* title;
	const char* band;
	const char* surveyUrl;
	const char* frame;
	const char* offlinePanoramaFile;
	bool hasDeepOnlineHd;
	const char* source;
	const char* coverage;
	const char* license;
	const char* attribution;
};

const QList<SpectralDataset>& spectralDatasetCatalog()
{
	static const QList<SpectralDataset> catalog = {
		{
			"dss2-color", "光学全天高清巡天", "可见光",
			"https://hips.china-vo.org/m/CDS_P_DSS2_color",
			"equatorial", "data/surveys/dss2-color_4k.jpg", true,
			"ESA Gaia DR3 · China-VO DSS2",
			"全天 4K 无缝光学全景，放大至 14° 以内在线自动叠加 DSS2 超清底片",
			"科研公开巡天数据（署名使用）", "ESA Gaia / STScI DSS2 / China-VO"
		},
		{
			"finkbeiner-ha", "Finkbeiner 氢阿尔法", "Hα 发射线",
			"https://skies.esac.esa.int/FinkbeinerHa",
			"galactic", "data/surveys/finkbeiner-ha_4k.jpg", false,
			"WWT · Finkbeiner Hα 4K",
			"全天 4K 离线 Hα 氢发射星云（巴纳德环、船底座、天鹅座），深红宝石色阶",
			"科研公开巡天数据（署名使用）", "Finkbeiner (2003) / AAS WWT"
		},
		{
			"2mass-color", "2MASS 近红外彩色", "近红外",
			"https://hips.china-vo.org/m/CDS_P_2MASS_color",
			"equatorial", "data/surveys/2mass-color_4k.jpg", true,
			"China-VO · 2MASS J/H/K",
			"全天 4K 离线近红外全景，穿透星际尘埃直视银河系核心，缩放叠加高清瓦片",
			"科研公开巡天数据（署名使用）", "UMass / IPAC / Caltech / China-VO"
		},
		{
			"allwise-color", "AllWISE 中红外尘埃", "中红外",
			"https://hips.china-vo.org/m/CDS_P_allWISE_color",
			"equatorial", "data/surveys/allwise-color_4k.jpg", true,
			"China-VO · AllWISE W1/W2/W4",
			"全天 4K 无缝中红外尘埃与恒星形成区，放大在线自动叠加高清瓦片",
			"科研公开巡天数据（署名使用）", "NASA / JPL-Caltech / UCLA / China-VO"
		},
		{
			"planck-lfi", "Planck 微波全天", "微波",
			"https://hips.china-vo.org/m/CDS_P_PLANCK_R2_LFI_color",
			"galactic", "data/surveys/planck-lfi_4k.jpg", false,
			"China-VO · Planck LFI 4K",
			"全天 4K 离线微波全景，呈现宇宙微波背景与银道面冷尘埃分布",
			"ESA 公开巡天数据（署名使用）", "ESA / Planck / China-VO"
		},
		{
			"haslam-radio", "Haslam 408 MHz 射电", "射电",
			"https://skies.esac.esa.int/Haslam/Haslam408_dsds_Remazeilles2014_mod_HiPS",
			"galactic", "data/surveys/haslam-radio_4k.jpg", false,
			"ESA Sky · Haslam 408 MHz 4K",
			"全天 4K 离线 408 MHz 射电连续谱，展示银盘同步辐射与北极支",
			"科研公开巡天数据（署名使用）", "Haslam et al. / Remazeilles / ESA"
		},
		{
			"galex-nuv", "GALEX 紫外全天", "紫外",
			"https://hips.china-vo.org/m/CDS_P_GALEXGR6_AIS_color",
			"equatorial", "data/surveys/galex-nuv_4k.jpg", true,
			"China-VO · GALEX GR6/7",
			"全天 4K 离线紫外全景，突出年轻炽热恒星与星系紫外核心，缩放叠加高清",
			"NASA 公开巡天数据（署名使用）", "NASA / Caltech / STScI / China-VO"
		},
		{
			"rass-xray", "ROSAT / eROSITA X 射线", "X 射线",
			"https://erosita.mpe.mpg.de/erodat/static/hips/eRASS1_RGB_Rate_c010",
			"equatorial", "data/surveys/rass-xray_4k.jpg", true,
			"WWT ROSAT · MPE eROSITA DR1",
			"100% 全天 4K 离线软 X 射线全景（船帆座与天鹅座遗迹清晰可见），西银半球缩放叠加 eROSITA 高清",
			"科研公开巡天数据（署名使用）", "MPE / ROSAT / eROSITA-DE / AAS WWT"
		},
		{
			"fermi-gamma", "Fermi 伽马射线全天", "伽马射线",
			"https://skies.esac.esa.int/FermiColor",
			"equatorial", "data/surveys/fermi-gamma_4k.jpg", false,
			"ESA Sky · Fermi LAT 4K",
			"全天 4K 离线高能伽马射线全景，展示脉冲星、活动星系核与银盘辐射",
			"NASA/ESA 公开巡天数据（署名使用）", "NASA / Fermi-LAT / ESA"
		}
	};
	return catalog;
}

const SpectralDataset* findSpectralDescriptor(const QString& datasetId)
{
	for (const SpectralDataset& candidate : spectralDatasetCatalog())
	{
		if (datasetId == QString::fromUtf8(candidate.id))
			return &candidate;
	}
	return nullptr;
}

QString resolveOfflinePanoramaPath(const char* relativePath)
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
	spectralFader.setDuration(350);
	lensFader.setDuration(260);
	lensDatasetId = QStringLiteral("finkbeiner-ha");
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
	panoProgram.reset();
	lensProgram.reset();
	panoVao.reset();
	panoVbo.reset();
	prevPanoProjector.reset();
	prevLensProjector.reset();
	spectralPanoramaTextures.clear();
	spectralTextureLru.clear();
}

void HipsMgr::setupPanoramaVAO()
{
	auto& gl = *QOpenGLContext::currentContext()->functions();
	panoVbo->bind();
	gl.glVertexAttribPointer(PANO_VERTEX_ATTRIB_INDEX, PANO_FS_QUAD_COORDS_PER_VERTEX, GL_FLOAT, GL_FALSE, 0, nullptr);
	panoVbo->release();
	gl.glEnableVertexAttribArray(PANO_VERTEX_ATTRIB_INDEX);
}

void HipsMgr::bindPanoramaVAO()
{
	if (panoVao && panoVao->isCreated())
		panoVao->bind();
	else
		setupPanoramaVAO();
}

void HipsMgr::releasePanoramaVAO()
{
	if (panoVao && panoVao->isCreated())
	{
		panoVao->release();
	}
	else
	{
		auto& gl = *QOpenGLContext::currentContext()->functions();
		gl.glDisableVertexAttribArray(PANO_VERTEX_ATTRIB_INDEX);
	}
}

void HipsMgr::ensurePanoramaGL()
{
	if (panoVbo && panoVbo->isCreated())
		return;
	auto* ctx = QOpenGLContext::currentContext();
	if (!ctx)
		return;
	auto& gl = *ctx->functions();

	panoVbo.reset(new QOpenGLBuffer(QOpenGLBuffer::VertexBuffer));
	panoVbo->create();
	panoVbo->bind();
	const GLfloat vertices[] = {
		-1.f, -1.f,
		 1.f, -1.f,
		-1.f,  1.f,
		 1.f,  1.f,
	};
	gl.glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
	panoVbo->release();

	panoVao.reset(new QOpenGLVertexArrayObject);
	panoVao->create();
	bindPanoramaVAO();
	setupPanoramaVAO();
	releasePanoramaVAO();
}

StelTextureSP HipsMgr::getSpectralPanoramaTexture(const QString& datasetId)
{
	if (datasetId.isEmpty())
		return StelTextureSP();

	auto it = spectralPanoramaTextures.find(datasetId);
	if (it != spectralPanoramaTextures.end() && it.value())
	{
		spectralTextureLru.removeAll(datasetId);
		spectralTextureLru.append(datasetId);
		return it.value();
	}

	const SpectralDataset* descriptor = findSpectralDescriptor(datasetId);
	if (!descriptor)
		return StelTextureSP();

	const QString fullPath = resolveOfflinePanoramaPath(descriptor->offlinePanoramaFile);
	if (fullPath.isEmpty())
		return StelTextureSP();

	// No mipmaps -> zero dFdx/dFdy wrap seam at RA=0h and 33% less VRAM.
	const StelTexture::StelTextureParams params(false, GL_LINEAR, GL_CLAMP_TO_EDGE);
	StelTextureSP tex = StelApp::getInstance().getTextureManager().createTexture(fullPath, params);
	if (!tex)
		return StelTextureSP();

	spectralPanoramaTextures.insert(datasetId, tex);
	spectralTextureLru.removeAll(datasetId);
	spectralTextureLru.append(datasetId);

	// Cap resident 4K textures at 3 (~96 MB peak VRAM) while keeping active & prev textures resident.
	int guardSteps = 0;
	while (spectralTextureLru.size() > 3 && guardSteps < spectralTextureLru.size())
	{
		const QString victim = spectralTextureLru.first();
		if (victim == activeSpectralId || victim == prevSpectralId ||
		    victim == lensDatasetId || victim == lensPrevDatasetId)
		{
			spectralTextureLru.move(0, spectralTextureLru.size() - 1);
			++guardSteps;
			continue;
		}
		spectralTextureLru.removeFirst();
		spectralPanoramaTextures.remove(victim);
	}
	return tex;
}

void HipsMgr::drawSpectralPanorama(StelCore* core)
{
	const float fade = spectralFader.getInterstate();
	if (fade <= 0.001f || activeSpectralId.isEmpty())
		return;

	StelTextureSP texCur = getSpectralPanoramaTexture(activeSpectralId);
	if (!texCur || !texCur->canBind())
		return;

	ensurePanoramaGL();
	if (!panoVbo || !panoVbo->isCreated())
		return;

	const auto modelView = core->getJ2000ModelViewTransform();
	const auto projector = core->getProjection(modelView);

	if (!panoProgram || !prevPanoProjector || !projector->isSameProjection(*prevPanoProjector))
	{
		panoProgram.reset(new QOpenGLShaderProgram);
		prevPanoProjector = projector;

		const auto vert =
			StelOpenGL::globalShaderPrefix(StelOpenGL::VERTEX_SHADER) +
			R"(
ATTRIBUTE highp vec3 vertex;
VARYING highp vec3 ndcPos;
void main()
{
	gl_Position = vec4(vertex, 1.0);
	ndcPos = vertex;
}
)";
		if (!panoProgram->addShaderFromSourceCode(QOpenGLShader::Vertex, vert))
		{
			qWarning().noquote() << "HipsMgr panorama vertex shader error:\n" << panoProgram->log();
			return;
		}

		const auto frag =
			StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) +
			projector->getUnProjectShader() +
			core->getAberrationShader() +
			R"(
VARYING highp vec3 ndcPos;
uniform sampler2D texCurrent;
uniform sampler2D texPrev;
uniform mediump float crossFade;
uniform mediump float alpha;
uniform mat4 projectionMatrixInverse;
void main(void)
{
	const float PI = 3.14159265359;
	vec4 winPos = projectionMatrixInverse * vec4(ndcPos, 1.0);
	bool ok = false;
	vec3 modelPos = unProject(winPos.x, winPos.y, ok).xyz;
	if (!ok)
	{
		FRAG_COLOR = vec4(0.0);
		return;
	}
	modelPos = normalize(modelPos);
	modelPos = applyAberrationToViewDir(modelPos);
	float ra = atan(modelPos.y, modelPos.x);
	float dec = asin(clamp(modelPos.z, -1.0, 1.0));
	vec2 texc = vec2(fract(ra / (2.0 * PI)), 0.5 + dec / PI);
	vec3 col = texture2D(texCurrent, texc).rgb;
	if (crossFade < 0.999)
	{
		vec3 colPrev = texture2D(texPrev, texc).rgb;
		col = mix(colPrev, col, crossFade);
	}
	FRAG_COLOR = vec4(col, alpha);
}
)";
		if (!panoProgram->addShaderFromSourceCode(QOpenGLShader::Fragment, frag))
		{
			qWarning().noquote() << "HipsMgr panorama fragment shader error:\n" << panoProgram->log();
			return;
		}

		panoProgram->bindAttributeLocation("vertex", PANO_VERTEX_ATTRIB_INDEX);
		if (!StelPainter::linkProg(panoProgram.get(), "HipsMgr 4K spectral panorama program"))
			return;

		panoProgram->bind();
		panoShaderVars.texCurrent = panoProgram->uniformLocation("texCurrent");
		panoShaderVars.texPrev = panoProgram->uniformLocation("texPrev");
		panoShaderVars.crossFade = panoProgram->uniformLocation("crossFade");
		panoShaderVars.alpha = panoProgram->uniformLocation("alpha");
		panoShaderVars.projectionMatrixInverse = panoProgram->uniformLocation("projectionMatrixInverse");
		panoProgram->release();
	}

	if (!panoProgram || !panoProgram->isLinked())
		return;

	StelTextureSP texPrev;
	float cf = 1.0f;
	if (spectralCrossFade < 0.999f && !prevSpectralId.isEmpty() && prevSpectralId != activeSpectralId)
	{
		texPrev = getSpectralPanoramaTexture(prevSpectralId);
		if (texPrev && texPrev->canBind())
			cf = spectralCrossFade * spectralCrossFade * (3.0f - 2.0f * spectralCrossFade);
	}

	auto& gl = *QOpenGLContext::currentContext()->functions();
	panoProgram->bind();

	texCur->bind(0);
	gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	panoProgram->setUniformValue(panoShaderVars.texCurrent, 0);

	if (texPrev && cf < 0.999f)
	{
		texPrev->bind(1);
		gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
		gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	}
	else
	{
		texCur->bind(1);
	}
	panoProgram->setUniformValue(panoShaderVars.texPrev, 1);

	panoProgram->setUniformValue(panoShaderVars.crossFade, static_cast<GLfloat>(cf));
	panoProgram->setUniformValue(panoShaderVars.alpha, static_cast<GLfloat>(fade * spectralOpacity));
	panoProgram->setUniformValue(panoShaderVars.projectionMatrixInverse, projector->getProjectionMatrix().toQMatrix().inverted());
	core->setAberrationUniforms(*panoProgram);
	projector->setUnProjectUniforms(*panoProgram);

	gl.glDisable(GL_DEPTH_TEST);
	gl.glDisable(GL_CULL_FACE);
	gl.glEnable(GL_BLEND);
	gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	bindPanoramaVAO();
	gl.glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	releasePanoramaVAO();
	gl.glDisable(GL_BLEND);

	if (texPrev && cf < 0.999f)
		texPrev->release();
	texCur->release();
	panoProgram->release();
}

bool HipsMgr::shouldDrawLensOverAtmosphere(const StelCore* core) const
{
	if (!isSpectralLensActive())
		return false;
	// In 2x magnifying mode, draw over optical stars/atmosphere so unzoomed 1x stars
	// don't double-expose inside the zoomed lens.
	if (lensZoomCurrent > 1.04f)
		return true;
	// During daytime with atmosphere visible, non-visible spectral bands punch straight
	// through the blue sky inside the circular lens (while staying behind landscape ground).
	if (lensDatasetId != QLatin1String("dss2-color"))
	{
		if (const auto* lMgr = GETSTELMODULE(LandscapeMgr))
		{
			if (lMgr->getFlagAtmosphere() && lMgr->getAtmosphereFadeIntensity() > 0.05f &&
			    lMgr->getAtmosphereAverageLuminance() > 0.05f)
			{
				Q_UNUSED(core);
				return true;
			}
		}
	}
	return false;
}

void HipsMgr::drawSpectralLens(StelCore* core)
{
	const float fade = lensFader.getInterstate();
	if (fade <= 0.001f || lensDatasetId.isEmpty())
		return;

	StelTextureSP texCur = getSpectralPanoramaTexture(lensDatasetId);
	if (!texCur || !texCur->canBind())
		return;

	ensurePanoramaGL();
	if (!panoVbo || !panoVbo->isCreated())
		return;

	const auto modelView = core->getJ2000ModelViewTransform();
	const auto projector = core->getProjection(modelView);

	if (!lensProgram || !prevLensProjector || !projector->isSameProjection(*prevLensProjector))
	{
		lensProgram.reset(new QOpenGLShaderProgram);
		prevLensProjector = projector;

		const auto vert =
			StelOpenGL::globalShaderPrefix(StelOpenGL::VERTEX_SHADER) +
			R"(
ATTRIBUTE highp vec3 vertex;
VARYING highp vec3 ndcPos;
void main()
{
	gl_Position = vec4(vertex, 1.0);
	ndcPos = vertex;
}
)";
		if (!lensProgram->addShaderFromSourceCode(QOpenGLShader::Vertex, vert))
		{
			qWarning().noquote() << "HipsMgr lens vertex shader error:\n" << lensProgram->log();
			return;
		}

		const auto frag =
			StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) +
			projector->getUnProjectShader() +
			core->getAberrationShader() +
			R"(
VARYING highp vec3 ndcPos;
uniform sampler2D texCurrent;
uniform sampler2D texPrev;
uniform mediump float crossFade;
uniform mediump float alpha;
uniform highp vec2 viewportSize;
uniform highp vec2 lensCenter;
uniform highp float lensRadiusNorm;
uniform highp float lensZoom;
uniform mat4 projectionMatrixInverse;
void main(void)
{
	const float PI = 3.14159265359;
	vec2 uv = ndcPos.xy * 0.5 + 0.5;
	vec2 px = uv * viewportSize;
	vec2 centerPx = vec2(lensCenter.x, 1.0 - lensCenter.y) * viewportSize;
	float radiusPx = lensRadiusNorm * min(viewportSize.x, viewportSize.y);
	vec2 deltaPx = px - centerPx;
	float dist = length(deltaPx);
	if (dist > radiusPx + 2.5)
	{
		discard;
	}

	float zoom = max(1.0, lensZoom);
	vec2 samplePx = centerPx + deltaPx / zoom;
	vec2 sampleNdc = (samplePx / viewportSize) * 2.0 - 1.0;
	vec4 winPos = projectionMatrixInverse * vec4(sampleNdc.x, sampleNdc.y, 0.0, 1.0);
	bool ok = false;
	vec3 modelPos = unProject(winPos.x, winPos.y, ok).xyz;
	if (!ok)
	{
		discard;
	}
	modelPos = normalize(modelPos);
	modelPos = applyAberrationToViewDir(modelPos);
	float ra = atan(modelPos.y, modelPos.x);
	float dec = asin(clamp(modelPos.z, -1.0, 1.0));
	vec2 texc = vec2(fract(ra / (2.0 * PI)), 0.5 + dec / PI);
	vec3 col = texture2D(texCurrent, texc).rgb;
	if (crossFade < 0.999)
	{
		vec3 colPrev = texture2D(texPrev, texc).rgb;
		col = mix(colPrev, col, crossFade);
	}

	float edgeMask = 1.0 - smoothstep(radiusPx - 2.0, radiusPx + 1.0, dist);
	float normR = dist / max(1.0, radiusPx);
	// Subtle optical loupe inner rim shading + crisp glass rim sheen
	float rimShade = 1.0 - 0.16 * smoothstep(0.82, 1.0, normR);
	FRAG_COLOR = vec4(col * rimShade, alpha * edgeMask);
}
)";
		if (!lensProgram->addShaderFromSourceCode(QOpenGLShader::Fragment, frag))
		{
			qWarning().noquote() << "HipsMgr lens fragment shader error:\n" << lensProgram->log();
			return;
		}

		lensProgram->bindAttributeLocation("vertex", PANO_VERTEX_ATTRIB_INDEX);
		if (!StelPainter::linkProg(lensProgram.get(), "HipsMgr 4K spectral lens program"))
			return;

		lensProgram->bind();
		lensShaderVars.texCurrent = lensProgram->uniformLocation("texCurrent");
		lensShaderVars.texPrev = lensProgram->uniformLocation("texPrev");
		lensShaderVars.crossFade = lensProgram->uniformLocation("crossFade");
		lensShaderVars.alpha = lensProgram->uniformLocation("alpha");
		lensShaderVars.viewportSize = lensProgram->uniformLocation("viewportSize");
		lensShaderVars.lensCenter = lensProgram->uniformLocation("lensCenter");
		lensShaderVars.lensRadiusNorm = lensProgram->uniformLocation("lensRadiusNorm");
		lensShaderVars.lensZoom = lensProgram->uniformLocation("lensZoom");
		lensShaderVars.projectionMatrixInverse = lensProgram->uniformLocation("projectionMatrixInverse");
		lensProgram->release();
	}

	if (!lensProgram || !lensProgram->isLinked())
		return;

	StelTextureSP texPrev;
	float cf = 1.0f;
	if (lensCrossFade < 0.999f && !lensPrevDatasetId.isEmpty() && lensPrevDatasetId != lensDatasetId)
	{
		texPrev = getSpectralPanoramaTexture(lensPrevDatasetId);
		if (texPrev && texPrev->canBind())
			cf = lensCrossFade * lensCrossFade * (3.0f - 2.0f * lensCrossFade);
	}

	const float vpW = static_cast<float>(qMax(1, projector->getViewportWidth()));
	const float vpH = static_cast<float>(qMax(1, projector->getViewportHeight()));

	auto& gl = *QOpenGLContext::currentContext()->functions();
	lensProgram->bind();

	texCur->bind(0);
	gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	lensProgram->setUniformValue(lensShaderVars.texCurrent, 0);

	if (texPrev && cf < 0.999f)
	{
		texPrev->bind(1);
		gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
		gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	}
	else
	{
		texCur->bind(1);
	}
	lensProgram->setUniformValue(lensShaderVars.texPrev, 1);

	lensProgram->setUniformValue(lensShaderVars.crossFade, static_cast<GLfloat>(cf));
	lensProgram->setUniformValue(lensShaderVars.alpha, static_cast<GLfloat>(fade));
	lensProgram->setUniformValue(lensShaderVars.viewportSize, QVector2D(vpW, vpH));
	lensProgram->setUniformValue(lensShaderVars.lensCenter, QVector2D(lensCenterX, lensCenterY));
	lensProgram->setUniformValue(lensShaderVars.lensRadiusNorm, static_cast<GLfloat>(lensRadiusNorm));
	lensProgram->setUniformValue(lensShaderVars.lensZoom, static_cast<GLfloat>(lensZoomCurrent));
	lensProgram->setUniformValue(lensShaderVars.projectionMatrixInverse, projector->getProjectionMatrix().toQMatrix().inverted());
	core->setAberrationUniforms(*lensProgram);
	projector->setUnProjectUniforms(*lensProgram);

	gl.glDisable(GL_DEPTH_TEST);
	gl.glDisable(GL_CULL_FACE);
	gl.glEnable(GL_BLEND);
	gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	bindPanoramaVAO();
	gl.glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	releasePanoramaVAO();
	gl.glDisable(GL_BLEND);

	if (texPrev && cf < 0.999f)
		texPrev->release();
	texCur->release();
	lensProgram->release();
}

void HipsMgr::draw(StelCore* core)
{
	const float panoFade = spectralFader.getInterstate();
	const bool hasSpectralPano = !activeSpectralId.isEmpty() && panoFade > 0.001f;
	if (hasSpectralPano)
		drawSpectralPanorama(core);

	// Nighttime 1x spectral lens draws at CallOrder=7 so optical stars & constellation lines
	// sit crisply on top of the lens; daytime or 2x lens draws inside LandscapeMgr::draw
	// (right after atmosphere and right before landscape ground).
	if (isSpectralLensActive() && !shouldDrawLensOverAtmosphere(core))
		drawSpectralLens(core);

	if (!visible)
		return;

	StelPainter sPainter(core->getProjection(StelCore::FrameJ2000));
	const double fovDeg = core->getMovementMgr() ? core->getMovementMgr()->getCurrentFov() : 60.0;

	// Hybrid online HD zoom: for bands with ultra-deep online HiPS (Order 6-9),
	// smoothly fade live remote tiles in over the 4K panorama when zoomed inside 14 deg.
	if (hasSpectralPano && fovDeg < 14.0)
	{
		const SpectralDataset* desc = findSpectralDescriptor(activeSpectralId);
		const HipsSurveyP survey = spectralSurveys.value(activeSpectralId);
		if (desc && desc->hasDeepOnlineHd && survey && survey->isVisible() &&
		    survey->isRemotePropertiesLoaded() && survey->hasValidProperties())
		{
			const float hdZoomFactor = static_cast<float>(qBound(0.0, (14.0 - fovDeg) / 6.0, 1.0));
			if (hdZoomFactor > 0.01f)
			{
				const float savedOpacity = survey->getOpacity();
				{
					const QSignalBlocker blocker(survey.data());
					survey->setOpacity(spectralOpacity * panoFade * hdZoomFactor);
				}
				survey->draw(&sPainter, 2.0 * M_PI, Q_NULLPTR, flagShowAtmosphericExtinction);
				{
					const QSignalBlocker blocker(survey.data());
					survey->setOpacity(savedOpacity);
				}
			}
		}
	}

	// Draw any standard non-spectral HiPS surveys normally.
	for (auto &survey: activeSurveys)
	{
		if (survey->isVisible() && survey->planet.isEmpty() && !isSpectralSurveyUrl(survey->getUrl()))
		{
			survey->draw(&sPainter, 2.0 * M_PI, Q_NULLPTR, flagShowAtmosphericExtinction);
		}
	}
}

void HipsMgr::update(double deltaTime)
{
	spectralFader.update(static_cast<int>(deltaTime * 1000));
	if (spectralCrossFade < 1.0f)
	{
		spectralCrossFade = qMin(1.0f, spectralCrossFade + static_cast<float>(deltaTime / 0.45));
		if (spectralCrossFade >= 1.0f)
			prevSpectralId.clear();
	}
	if (!spectralFader && spectralFader.getInterstate() <= 0.f && !activeSpectralId.isEmpty())
	{
		activeSpectralId.clear();
		prevSpectralId.clear();
	}

	lensFader.update(static_cast<int>(deltaTime * 1000));
	if (lensCrossFade < 1.0f)
	{
		lensCrossFade = qMin(1.0f, lensCrossFade + static_cast<float>(deltaTime / 0.45));
		if (lensCrossFade >= 1.0f)
			lensPrevDatasetId.clear();
	}
	if (std::fabs(lensZoomCurrent - lensZoomTarget) > 0.001f)
	{
		const float alpha = qMin(1.0f, static_cast<float>(deltaTime * 12.0));
		lensZoomCurrent += (lensZoomTarget - lensZoomCurrent) * alpha;
		if (std::fabs(lensZoomCurrent - lensZoomTarget) < 0.002f)
			lensZoomCurrent = lensZoomTarget;
	}

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
	if (!visible)
		return 0;
	int count = (!activeSpectralId.isEmpty() && spectralFader) ? 1 : 0;
	for (const auto& survey : surveys)
	{
		if (survey->isVisible() && !survey->isPlanetarySurvey() && !isSpectralSurveyUrl(survey->getUrl()))
			++count;
	}
	return count;
}

float HipsMgr::getActiveSurveyFade() const
{
	float maxFade = spectralFader.getInterstate();
	if (!visible)
		return maxFade;
	for (const auto& survey : activeSurveys)
	{
		if (survey && survey->planet.isEmpty() && !isSpectralSurveyUrl(survey->getUrl()))
			maxFade = qMax(maxFade, survey->getInterstate());
	}
	return maxFade;
}

float HipsMgr::getNonVisibleSpectralFade() const
{
	const float fade = spectralFader.getInterstate();
	if (fade <= 0.f || activeSpectralId.isEmpty())
		return 0.f;
	const bool curNonVis = (activeSpectralId != QLatin1String("dss2-color"));
	if (spectralCrossFade < 0.999f && !prevSpectralId.isEmpty())
	{
		const bool prevNonVis = (prevSpectralId != QLatin1String("dss2-color"));
		if (curNonVis != prevNonVis)
		{
			const float cf = spectralCrossFade * spectralCrossFade * (3.0f - 2.0f * spectralCrossFade);
			return fade * (curNonVis ? cf : (1.0f - cf));
		}
	}
	return curNonVis ? fade : 0.f;
}

QJsonArray HipsMgr::getSpectralDatasets() const
{
	QJsonArray datasets;
	for (const SpectralDataset& descriptor : spectralDatasetCatalog())
	{
		QJsonObject item;
		const QString id = QString::fromUtf8(descriptor.id);
		const HipsSurveyP survey = spectralSurveys.value(id);
		const bool hasLocalPano = spectralPanoramaTextures.contains(id) ||
			!resolveOfflinePanoramaPath(descriptor.offlinePanoramaFile).isEmpty();
		const bool hdReady = descriptor.hasDeepOnlineHd
			? (survey && survey->isRemotePropertiesLoaded() && survey->hasValidProperties())
			: hasLocalPano;
		const bool enabled = visible && spectralFader && (activeSpectralId == id);
		item["id"] = id;
		item["title"] = QString::fromUtf8(descriptor.title);
		item["band"] = QString::fromUtf8(descriptor.band);
		item["source"] = QString::fromUtf8(descriptor.source);
		item["coverage"] = QString::fromUtf8(descriptor.coverage);
		item["license"] = QString::fromUtf8(descriptor.license);
		item["attribution"] = QString::fromUtf8(descriptor.attribution);
		item["licenseReviewRequired"] = false;
		item["networkPolicy"] = descriptor.hasDeepOnlineHd
			? QStringLiteral("offline-4k-hybrid-hd")
			: QStringLiteral("offline-4k-complete");
		item["timeoutSeconds"] = 12;
		item["surveyUrl"] = QString::fromUtf8(descriptor.surveyUrl);
		item["available"] = true;
		item["enabled"] = enabled;
		item["loading"] = descriptor.hasDeepOnlineHd && survey && survey->isLoading();
		item["offlineReady"] = hasLocalPano;
		item["hdReady"] = hdReady;
		item["ready"] = hasLocalPano || hdReady;
		item["opacity"] = static_cast<double>(spectralOpacity);
		item["error"] = (descriptor.hasDeepOnlineHd && survey && !hdReady && !hasLocalPano) ? survey->getLastError() : QString();
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
	if (!visible || !spectralFader || activeSpectralId.isEmpty())
		return state;

	const SpectralDataset* descriptor = findSpectralDescriptor(activeSpectralId);
	if (!descriptor)
		return state;
	const HipsSurveyP survey = spectralSurveys.value(activeSpectralId);
	const bool offlineReady = spectralPanoramaTextures.contains(activeSpectralId) ||
		!resolveOfflinePanoramaPath(descriptor->offlinePanoramaFile).isEmpty();
	const bool hdReady = descriptor->hasDeepOnlineHd
		? (survey && survey->isRemotePropertiesLoaded() && survey->hasValidProperties())
		: offlineReady;
	state["enabled"] = true;
	state["datasetId"] = activeSpectralId;
	state["loading"] = descriptor->hasDeepOnlineHd && survey && survey->isLoading();
	state["hdReady"] = hdReady;
	state["offlineReady"] = offlineReady;
	state["ready"] = offlineReady || hdReady;
	state["opacity"] = static_cast<double>(spectralOpacity);
	state["visibleTiles"] = survey ? survey->getVisibleTileCount() : 0;
	state["loadedTiles"] = survey ? survey->getLoadedTileCount() : 0;
	state["error"] = (descriptor->hasDeepOnlineHd && survey && !hdReady && !offlineReady) ? survey->getLastError() : QString();
	return state;
}

bool HipsMgr::setSpectralView(const QString& datasetId, const bool enabled, QString* error)
{
	const SpectralDataset* descriptor = findSpectralDescriptor(datasetId);
	if (!descriptor)
	{
		if (error) *error = QStringLiteral("unknown spectral dataset: %1").arg(datasetId);
		return false;
	}

	if (!enabled)
	{
		if (activeSpectralId == datasetId)
			spectralFader = false;
		if (spectralSurveys.contains(datasetId))
			spectralSurveys.value(datasetId)->setVisible(false);
		emit surveysChanged();
		return true;
	}

	// Opening full-screen spectral view cleanly dismisses the circular lens.
	if (lensEnabled)
	{
		lensEnabled = false;
		lensFader = false;
	}
	lastSpectralDatasetId = datasetId;
	if (activeSpectralId != datasetId)
	{
		if (!activeSpectralId.isEmpty() && spectralFader.getInterstate() > 0.01f)
		{
			prevSpectralId = activeSpectralId;
			spectralCrossFade = 0.0f;
		}
		else
		{
			prevSpectralId.clear();
			spectralCrossFade = 1.0f;
		}
		activeSpectralId = datasetId;
	}
	spectralFader = true;

	for (auto it = spectralSurveys.cbegin(); it != spectralSurveys.cend(); ++it)
		if (it.key() != datasetId && it.value()) it.value()->setVisible(false);

	if (descriptor->hasDeepOnlineHd)
	{
		HipsSurveyP survey = spectralSurveys.value(datasetId);
		if (!survey)
		{
			const QString frame = QString::fromUtf8(descriptor->frame);
			QMap<QString, QString> initialProperties;
			initialProperties.insert(QStringLiteral("obs_title"), QString::fromUtf8(descriptor->title));
			initialProperties.insert(QStringLiteral("hips_frame"), frame);
			initialProperties.insert(QStringLiteral("hips_status"), QStringLiteral("public master clonableOnce"));
			survey = HipsSurveyP(new HipsSurvey(QString::fromUtf8(descriptor->surveyUrl), QStringLiteral("spectral"), frame, QStringLiteral("image"), initialProperties));
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
		survey->setVisible(true);
	}

	visible = true;
	emit showChanged(true);
	if (auto* toast = GETSTELMODULE(ToastMgr))
	{
		if (toast->getFlagShow())
			toast->setFlagShow(false);
	}
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
	spectralFader = false;
	for (auto it = spectralSurveys.cbegin(); it != spectralSurveys.cend(); ++it)
		if (it.value()) it.value()->setVisible(false);
	if (getVisibleSurveyCount() == 0 && visible)
	{
		visible = false;
		emit showChanged(false);
	}
	emit surveysChanged();
}

bool HipsMgr::setSpectralLens(const bool enabled, const QString& datasetId,
                              const float normX, const float normY,
                              const float radiusNorm, const float zoom,
                              QString* error)
{
	if (!enabled)
	{
		lensEnabled = false;
		lensFader = false;
		return true;
	}

	const QString resolvedId = datasetId.isEmpty()
		? (lensDatasetId.isEmpty() ? QStringLiteral("finkbeiner-ha") : lensDatasetId)
		: datasetId;
	const SpectralDataset* descriptor = findSpectralDescriptor(resolvedId);
	if (!descriptor)
	{
		if (error) *error = QStringLiteral("unknown spectral dataset: %1").arg(resolvedId);
		return false;
	}

	// Opening circular magnifying lens cleanly closes full-screen spectral mode
	// so the outside sky shows normal optical stars & constellations.
	if (visible && spectralFader)
		closeSpectralView();

	if (lensDatasetId != resolvedId)
	{
		if (!lensDatasetId.isEmpty() && lensFader.getInterstate() > 0.01f)
		{
			lensPrevDatasetId = lensDatasetId;
			lensCrossFade = 0.0f;
		}
		else
		{
			lensPrevDatasetId.clear();
			lensCrossFade = 1.0f;
		}
		lensDatasetId = resolvedId;
	}
	lastSpectralDatasetId = resolvedId;

	if (normX >= 0.0f && normX <= 1.0f)
		lensCenterX = normX;
	if (normY >= 0.0f && normY <= 1.0f)
		lensCenterY = normY;
	if (radiusNorm >= 0.05f && radiusNorm <= 0.49f)
		lensRadiusNorm = radiusNorm;
	if (zoom >= 1.0f && zoom <= 3.0f)
	{
		const bool wasInactive = !lensEnabled && lensFader.getInterstate() <= 0.01f;
		lensZoomTarget = zoom;
		if (wasInactive)
			lensZoomCurrent = zoom;
	}

	lensEnabled = true;
	lensFader = true;
	return true;
}

QJsonObject HipsMgr::getSpectralLensState() const
{
	QJsonObject state;
	state["enabled"] = lensEnabled;
	state["active"] = isSpectralLensActive();
	state["datasetId"] = lensDatasetId;
	state["x"] = static_cast<double>(lensCenterX);
	state["y"] = static_cast<double>(lensCenterY);
	state["radius"] = static_cast<double>(lensRadiusNorm);
	state["zoom"] = static_cast<double>(lensZoomTarget);
	state["currentZoom"] = static_cast<double>(lensZoomCurrent);
	if (const SpectralDataset* desc = findSpectralDescriptor(lensDatasetId))
	{
		state["title"] = QString::fromUtf8(desc->title);
		state["band"] = QString::fromUtf8(desc->band);
	}
	return state;
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
		spectralFader = false;
		for (auto &survey: surveys)
		{
			if (survey->isVisible())
				survey->hideProgressBar();
		}
	}
	else
	{
		if (auto* toast = GETSTELMODULE(ToastMgr))
		{
			if (toast->getFlagShow())
				toast->setFlagShow(false);
		}
		if (initialized && getVisibleSurveyCount() == 0)
		{
			// Turning on the HiPS master switch with no active survey should
			// immediately show the last selected (or default optical) survey.
			const QString fallbackId = lastSpectralDatasetId.isEmpty()
				? QStringLiteral("dss2-color")
				: lastSpectralDatasetId;
			setSpectralView(fallbackId, true);
		}
		else if (!activeSpectralId.isEmpty())
		{
			spectralFader = true;
		}
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
