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

#ifndef HIPSMGR_HPP
#define HIPSMGR_HPP

#include "StelModule.hpp"
#include "StelHips.hpp"
#include "StelFader.hpp"
#include "StelProjectorType.hpp"
#include "StelTextureTypes.hpp"
#include <QLoggingCategory>
#include <QJsonArray>
#include <QJsonObject>
#include <QMap>
#include <QStringList>
#include <atomic>
#include <memory>

class QOpenGLBuffer;
class QOpenGLShaderProgram;
class QOpenGLVertexArrayObject;


//! @class HipsMgr
//! This class controls display of Hierarchical Progressive Surveys (HiPS), all-sky surveys in a particular format
//! defined by the International Virtual Observatory Alliance. A full description of the format can be found on the
//! IVOA website. (https://www.ivoa.net/documents/HiPS/20170519/REC-HIPS-1.0-20170519.pdf)
//! Stellarium supports only image-based surveys.
//!
//! @note You can finetune the amount of HiPS-related messages in the logfile by configuring the logging category stel.HiPS.
//! For this, e.g. set environment variable QT_LOGGING_RULES="*.debug=false;stel.HiPS.debug=true;".
//! By default, only Info and more severe messages are displayed.

Q_DECLARE_LOGGING_CATEGORY(HiPS)

class HipsMgr : public StelModule
{
	Q_OBJECT
	Q_PROPERTY(QList<HipsSurveyP> surveys
			MEMBER surveys
			NOTIFY surveysChanged)
	Q_PROPERTY(bool flagShow READ getFlagShow WRITE setFlagShow NOTIFY showChanged)
	Q_PROPERTY(bool flagShowAtmosphericExtinction READ getFlagShowAtmosphericExtinction WRITE setFlagShowAtmosphericExtinction NOTIFY flagShowAtmosphericExtinctionChanged)
	Q_PROPERTY(State state READ getState NOTIFY stateChanged)
	Q_PROPERTY(bool loaded READ isLoaded NOTIFY stateChanged)

public:
	//! @enum State The loading state of the survey sources.
	enum State
	{
		Created,
		Loading,
		Loaded,
	};
	Q_ENUM(State)

	HipsMgr();
	~HipsMgr() override;
	void init() override;
	void deinit() override;
	void update(double deltaTime) override;
	void draw(StelCore* core) override;
	double getCallOrder(StelModuleActionName actionName) const override;

	//! Return the hips survey that has a given url.
	Q_INVOKABLE
	HipsSurveyP getSurveyByUrl(const QString &url);

	int getSurveyCount() const { return surveys.size(); }
	int getVisibleSurveyCount() const;
	//! Return max fade factor (0..1) of any visible sky HiPS survey.
	float getActiveSurveyFade() const;
	//! Return fade factor (0..1) when a non-visible spectral band (IR/H-alpha/Radio/MW/UV/X-ray/Gamma) is active.
	float getNonVisibleSpectralFade() const;
	QJsonArray getSpectralDatasets() const;
	QJsonObject getSpectralState() const;
	bool setSpectralView(const QString& datasetId, bool enabled, QString* error = nullptr);
	void setSpectralOpacity(float opacity);
	float getSpectralOpacity() const { return spectralOpacity; }
	void closeSpectralView();
	bool setSpectralLens(bool enabled, const QString& datasetId, float normX, float normY, float radiusNorm, float zoom, QString* error = nullptr);
	//! Pure lock-free static geometry update safe to call from any thread (ArkUI touch thread).
	static void updateSpectralLensGeometryFast(float normX, float normY, float radiusNorm, float handleAngleDeg = -999.f, int flags = -1);
	QJsonObject getSpectralLensState() const;
	bool isSpectralLensActive() const { return lensFader.getInterstate() > 0.001f; }
	bool shouldDrawLensOverAtmosphere(const StelCore* core) const;
	void drawSpectralLens(StelCore* core);

	State getState() const {return state;}
	bool isLoaded() const {return state == Loaded;}

signals:
	void showChanged(bool value) const;
	void flagShowAtmosphericExtinctionChanged(bool value) const;
	void surveysChanged() const;
	void stateChanged(State value) const;
	//! Emitted when a new survey has been loaded.
	void gotNewSurvey(HipsSurveyP survey) const;
	void toggleDialog() const;

public slots:
	//! Start to load the default sources.
	void loadSources();

	//! Get whether the surveys are displayed.
	bool getFlagShow(void) const;
	//! Set whether the surveys are displayed.
	void setFlagShow(bool b);
	bool getFlagShowAtmosphericExtinction(void) const { return flagShowAtmosphericExtinction; }
	void setFlagShowAtmosphericExtinction(bool b);

private slots:
	// after loading survey list from network, restore the visible surveys from config.ini.
	void restoreVisibleSurveys();
	void saveSurveySettings() const;
	void updateActiveSurveys();

private:
	void setupPanoramaVAO();
	void bindPanoramaVAO();
	void releasePanoramaVAO();
	void ensurePanoramaGL();
	StelTextureSP getSpectralPanoramaTexture(const QString& datasetId);
	void drawSpectralPanorama(StelCore* core);

	QList<HipsSurveyP> surveys;
	QList<HipsSurveyP> activeSurveys;
	bool visible = true;
	bool initialized = false;
	bool flagShowAtmosphericExtinction = false;
	State state = Created;
	//! Used internally to keep track of the loading state.
	int nbSourcesLoaded = 0;
	QMap<QString, HipsSurveyP> spectralSurveys;
	QString activeSpectralId;
	QString prevSpectralId;
	QString lastSpectralDatasetId;
	float spectralOpacity = 1.0f;
	float spectralCrossFade = 1.0f;
	LinearFader spectralFader;
	QMap<QString, StelTextureSP> spectralPanoramaTextures;
	QStringList spectralTextureLru;

	std::unique_ptr<QOpenGLVertexArrayObject> panoVao;
	std::unique_ptr<QOpenGLBuffer> panoVbo;
	std::unique_ptr<QOpenGLShaderProgram> panoProgram;
	StelProjectorP prevPanoProjector;
	struct
	{
		int texCurrent = -1;
		int texPrev = -1;
		int crossFade = -1;
		int alpha = -1;
		int projectionMatrixInverse = -1;
	} panoShaderVars;

	// Sky Guide style multi-spectral magnifying lens (circular X-ray loupe)
	bool lensEnabled = false;
	LinearFader lensFader;
	float lensCenterX = 0.5f;
	float lensCenterY = 0.44f;
	float lensRadiusNorm = 0.215f;
	float lensZoomTarget = 1.0f;
	float lensZoomCurrent = 1.0f;
	QString lensDatasetId;
	QString lensPrevDatasetId;
	float lensCrossFade = 1.0f;
	std::unique_ptr<QOpenGLShaderProgram> lensProgram;
	StelProjectorP prevLensProjector;
	struct
	{
		int texCurrent = -1;
		int texPrev = -1;
		int crossFade = -1;
		int alpha = -1;
		int viewportSize = -1;
		int lensCenter = -1;
		int lensRadiusNorm = -1;
		int lensZoom = -1;
		int handleAngleRad = -1;
		int accentColor = -1;
		int chromeAlpha = -1;
		int lensFlags = -1;
		int activeBandIdx = -1;
		int dpr = -1;
		int projectionMatrixInverse = -1;
	} lensShaderVars;
};

#endif // HIPSMGR_HPP
