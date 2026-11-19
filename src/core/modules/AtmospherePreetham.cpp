/*
 * Stellarium
 * Copyright (C) 2003 Fabien Chereau
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

#include "AtmospherePreetham.hpp"
#include "AtmosphereGridStrip.hpp"
#include "SolarSystem.hpp"
#include "StelModuleMgr.hpp"
#include "AtmosphereVivid.hpp"
#include "AtmosphereMist.hpp"
#include "StelUtils.hpp"
#include "Planet.hpp"
#include "StelApp.hpp"
#include "StelProjector.hpp"
#include "StelToneReproducer.hpp"
#include "StelCore.hpp"
#include "StelPainter.hpp"
#include "Skylight.hpp"

#include <QFile>
#include <QDebug>
#include <QSettings>
#include <QOpenGLShaderProgram>

#if defined(__OHOS__)
#include <QElapsedTimer>
#include <hilog/log.h>

namespace
{
struct PreethamTimingSample
{
	QElapsedTimer timer;
	qint64 prepNs = 0;
	qint64 gridNs = 0;
	qint64 uploadNs = 0;
	quint64 gridCount = 0;
	quint64 cacheHits = 0;
	bool active = false;
	bool resized = false;
	bool uploaded = false;
	bool cacheEligible = false;
	bool cacheReusable = false;

	PreethamTimingSample() { timer.start(); }
	~PreethamTimingSample()
	{
		const qint64 totalNs = timer.nsecsElapsed();
		if (!active)
			prepNs = totalNs;
		struct Aggregate
		{
			int calls = 0, active = 0, resizes = 0, uploads = 0;
			int cacheEligible = 0, cacheReusable = 0;
			quint64 gridCount = 0, cacheHits = 0;
			qint64 totalNs = 0, prepNs = 0, gridNs = 0, uploadNs = 0;
			qint64 prepMaxNs = 0, gridMaxNs = 0, uploadMaxNs = 0;
		};
		static Aggregate aggregate;
		++aggregate.calls;
		aggregate.active += active;
		aggregate.resizes += resized;
		aggregate.uploads += uploaded;
		aggregate.cacheEligible += cacheEligible;
		aggregate.cacheReusable += cacheReusable;
		aggregate.gridCount += gridCount;
		aggregate.cacheHits += cacheHits;
		aggregate.totalNs += totalNs;
		aggregate.prepNs += prepNs;
		aggregate.gridNs += gridNs;
		aggregate.uploadNs += uploadNs;
		aggregate.prepMaxNs = qMax(aggregate.prepMaxNs, prepNs);
		aggregate.gridMaxNs = qMax(aggregate.gridMaxNs, gridNs);
		aggregate.uploadMaxNs = qMax(aggregate.uploadMaxNs, uploadNs);
		if (aggregate.calls != 120)
			return;
		const double averageMs = 1.0 / (aggregate.calls * 1e6);
		OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "StelAtmoPerf",
			"phase=computeColor calls=%{public}d clock=cpuWall "
			"prepAvg=%{public}.3fms gridAvg=%{public}.3fms uploadAvg=%{public}.3fms totalAvg=%{public}.3fms "
			"prepMax=%{public}.3fms gridMax=%{public}.3fms uploadMax=%{public}.3fms",
			aggregate.calls, aggregate.prepNs * averageMs, aggregate.gridNs * averageMs,
			aggregate.uploadNs * averageMs, aggregate.totalNs * averageMs,
			aggregate.prepMaxNs / 1e6, aggregate.gridMaxNs / 1e6, aggregate.uploadMaxNs / 1e6);
		OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "StelAtmoPerf",
			"phase=cache calls=%{public}d active=%{public}d gridCount=%{public}.0f cacheHits=%{public}.0f "
			"cacheEligible=%{public}d cacheReusable=%{public}d uploads=%{public}d resizes=%{public}d",
			aggregate.calls, aggregate.active, double(aggregate.gridCount), double(aggregate.cacheHits),
			aggregate.cacheEligible, aggregate.cacheReusable, aggregate.uploads, aggregate.resizes);
		aggregate = Aggregate{};
	}
};
}
#endif

Q_LOGGING_CATEGORY(Atmo,"stel.Atmosphere", QtInfoMsg)

AtmospherePreetham::AtmospherePreetham(Skylight& sky)
	: viewport(0,0,0,0)
	, sky(sky)
	, skyResolutionY(44)
	, skyResolutionX(44)
	, posGridBuffer(QOpenGLBuffer::VertexBuffer)
	, indicesBuffer(QOpenGLBuffer::IndexBuffer)
	, colorGridBuffer(QOpenGLBuffer::VertexBuffer)
{
	setFadeDuration(1.5f);
	compileShaders(nullptr);
	GL(vao.create());
}

void AtmospherePreetham::compileShaders(const StelProjector* projector)
{
	QOpenGLShader vShader(QOpenGLShader::Vertex);
	{
		QFile vert(":/shaders/preethamAtmosphere.vert");
		if(!vert.open(QFile::ReadOnly))
			qFatal("Failed to open atmosphere vertex shader source");
		QFile toneRepro(":/shaders/xyYToRGB.glsl");
		if(!toneRepro.open(QFile::ReadOnly))
			qFatal("Failed to open ToneReproducer shader source");
		if (!vShader.compileSourceCode(StelOpenGL::globalShaderPrefix(StelOpenGL::VERTEX_SHADER) +
									   "#define main originalAtmosphereMain\n" + vert.readAll() +
									   "\n#undef main\n" + toneRepro.readAll() + AtmosphereVivid::shaderSource() + AtmospherePlanetary::shaderSource() +
									   "\nvoid main() { originalAtmosphereMain(); resultSkyColor = vividAtmosphereColor(resultSkyColor, skyColor.xyz, sunPos, vividStrength); resultSkyColor = planetaryAtmosphereColor(resultSkyColor, skyColor.xyz, sunPos); }\n"))
			qFatal("Error while compiling atmosphere vertex shader: %s", vShader.log().toLatin1().constData());
	}
	if (!vShader.log().isEmpty())
	{
		qCWarning(Atmo) << "Warnings while compiling Preetham atmosphere vertex shader: " << vShader.log();
	}
	QOpenGLShader fShader(QOpenGLShader::Fragment);
	if (!fShader.compileSourceCode(
					StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) +
					(projector ? QByteArray("#define MIST_WORLD_DIRECTION\n") + projector->getUnProjectShader() : QByteArray()) +
					AtmosphereMist::shaderSource() + QByteArray(R"(
VARYING mediump vec3 resultSkyColor;
void main()
{
    highp float transmission = 1.;
#ifdef MIST_WORLD_DIRECTION
    if (mistUndergroundStrength > 0.)
    {
        bool valid = false;
        highp vec3 worldDirection = unProject(gl_FragCoord.x, gl_FragCoord.y, valid);
        if (!valid || !(length(worldDirection) > .00001)) { FRAG_COLOR = vec4(0.); return; }
        transmission = mistAtmosphereTransmission(normalize(worldDirection).z);
    }
#endif
    FRAG_COLOR = vec4(resultSkyColor * transmission, 1.);
}
)")))
	{
		qFatal("Error while compiling Preetham atmosphere fragment shader: %s", fShader.log().toLatin1().constData());
	}
	if (!fShader.log().isEmpty())
	{
		qCWarning(Atmo) << "Warnings while compiling Preetham atmosphere fragment shader: " << vShader.log();
	}
	delete atmoShaderProgram;
	atmoShaderProgram = new QOpenGLShaderProgram();
	atmoShaderProgram->addShader(&vShader);
	atmoShaderProgram->addShader(&fShader);
	atmoShaderProgram->bindAttributeLocation("skyVertex", 0);
	atmoShaderProgram->bindAttributeLocation("skyColor", 1);
	StelPainter::linkProg(atmoShaderProgram, "Preetham atmosphere");

	GL(atmoShaderProgram->bind());
	GL(shaderAttribLocations.alphaWaOverAlphaDa = atmoShaderProgram->uniformLocation("alphaWaOverAlphaDa"));
	GL(shaderAttribLocations.oneOverGamma = atmoShaderProgram->uniformLocation("oneOverGamma"));
	GL(shaderAttribLocations.term2TimesOneOverMaxdLpOneOverGamma = atmoShaderProgram->uniformLocation("term2TimesOneOverMaxdLpOneOverGamma"));
	GL(shaderAttribLocations.term2TimesOneOverMaxdL = atmoShaderProgram->uniformLocation("term2TimesOneOverMaxdL"));
	GL(shaderAttribLocations.flagUseTmGamma = atmoShaderProgram->uniformLocation("flagUseTmGamma"));
	GL(shaderAttribLocations.brightnessScale = atmoShaderProgram->uniformLocation("brightnessScale"));
	GL(shaderAttribLocations.sunPos = atmoShaderProgram->uniformLocation("sunPos"));
	GL(shaderAttribLocations.vividStrength = atmoShaderProgram->uniformLocation("vividStrength"));
	GL(shaderAttribLocations.mistUndergroundStrength = atmoShaderProgram->uniformLocation("mistUndergroundStrength"));
	GL(shaderAttribLocations.planetZenithColor = atmoShaderProgram->uniformLocation("planetZenithColor"));
	GL(shaderAttribLocations.planetHorizonColor = atmoShaderProgram->uniformLocation("planetHorizonColor"));
	GL(shaderAttribLocations.planetTwilightZenith = atmoShaderProgram->uniformLocation("planetTwilightZenith"));
	GL(shaderAttribLocations.planetTwilightHorizon = atmoShaderProgram->uniformLocation("planetTwilightHorizon"));
	GL(shaderAttribLocations.planetSunHaloColor = atmoShaderProgram->uniformLocation("planetSunHaloColor"));
	GL(shaderAttribLocations.planetAtmoParams = atmoShaderProgram->uniformLocation("planetAtmoParams"));
	GL(shaderAttribLocations.term_x = atmoShaderProgram->uniformLocation("term_x"));
	GL(shaderAttribLocations.Ax = atmoShaderProgram->uniformLocation("Ax"));
	GL(shaderAttribLocations.Bx = atmoShaderProgram->uniformLocation("Bx"));
	GL(shaderAttribLocations.Cx = atmoShaderProgram->uniformLocation("Cx"));
	GL(shaderAttribLocations.Dx = atmoShaderProgram->uniformLocation("Dx"));
	GL(shaderAttribLocations.Ex = atmoShaderProgram->uniformLocation("Ex"));
	GL(shaderAttribLocations.term_y = atmoShaderProgram->uniformLocation("term_y"));
	GL(shaderAttribLocations.Ay = atmoShaderProgram->uniformLocation("Ay"));
	GL(shaderAttribLocations.By = atmoShaderProgram->uniformLocation("By"));
	GL(shaderAttribLocations.Cy = atmoShaderProgram->uniformLocation("Cy"));
	GL(shaderAttribLocations.Dy = atmoShaderProgram->uniformLocation("Dy"));
	GL(shaderAttribLocations.Ey = atmoShaderProgram->uniformLocation("Ey"));
	GL(shaderAttribLocations.doSRGB = atmoShaderProgram->uniformLocation("doSRGB"));
	GL(shaderAttribLocations.projectionMatrix = atmoShaderProgram->uniformLocation("projectionMatrix"));
	GL(shaderAttribLocations.skyVertex = atmoShaderProgram->attributeLocation("skyVertex"));
	GL(shaderAttribLocations.skyColor = atmoShaderProgram->attributeLocation("skyColor"));
	GL(atmoShaderProgram->release());

}

AtmospherePreetham::~AtmospherePreetham(void)
{
	delete atmoShaderProgram;
	atmoShaderProgram = Q_NULLPTR;
}

void AtmospherePreetham::setupCurrentVAO()
{
	GL(colorGridBuffer.bind());
	GL(atmoShaderProgram->setAttributeBuffer(shaderAttribLocations.skyColor, GL_FLOAT, 0, 4, 0));
	GL(colorGridBuffer.release());
	GL(atmoShaderProgram->enableAttributeArray(shaderAttribLocations.skyColor));
	GL(posGridBuffer.bind());
	GL(atmoShaderProgram->setAttributeBuffer(shaderAttribLocations.skyVertex, GL_FLOAT, 0, 2, 0));
	GL(posGridBuffer.release());
	GL(atmoShaderProgram->enableAttributeArray(shaderAttribLocations.skyVertex));
}

void AtmospherePreetham::bindVAO()
{
	if(vao.isCreated())
		GL(vao.bind());
	else
		setupCurrentVAO();
}

void AtmospherePreetham::releaseVAO()
{
	if(vao.isCreated())
	{
		GL(vao.release());
	}
	else
	{
		GL(atmoShaderProgram->disableAttributeArray(shaderAttribLocations.skyColor));
		GL(atmoShaderProgram->disableAttributeArray(shaderAttribLocations.skyVertex));
	}
}


void AtmospherePreetham::computeColor(StelCore* core, const double JD, const Planet& currentPlanet, const Planet& sun,
				      const Planet*const moon, const StelLocation& location, const float temperature,
				      const float relativeHumidity, const float extinctionCoefficient, const bool noScatter)
{
#if defined(__OHOS__)
	PreethamTimingSample timing;
#endif
	const StelProjectorP prj = core->getProjection(StelCore::FrameAltAz, StelCore::RefractionOff);
	vividAtmosphereAllowed = currentPlanet.getEnglishName() == "Earth" && !noScatter;
	planetaryProfile_ = noScatter
		? AtmospherePlanetary::earthProfile()
		: AtmospherePlanetary::profileForPlanet(currentPlanet.getEnglishName().toStdString());
	planetaryProfileId = QString::fromLatin1(planetaryProfile_.id);
	if (viewport != prj->getViewport())
	{
#if defined(__OHOS__)
		timing.resized = true;
#endif
		luminanceCacheValid = false;
		// The viewport changed: update the number of point of the grid
		viewport = prj->getViewport();
		skyResolutionY = StelApp::getInstance().getSettings()->value("landscape/atmosphereybin", 44).toUInt();
		skyResolutionX = static_cast<unsigned int>(floorf(0.5f+static_cast<float>(skyResolutionY)*(0.5f*sqrtf(3.0f))*static_cast<float>(prj->getViewportWidth())/static_cast<float>(prj->getViewportHeight())));
		posGrid.resize(static_cast<size_t>((1+skyResolutionX)*(1+skyResolutionY)));
		colorGrid.resize(static_cast<size_t>((1+skyResolutionX)*(1+skyResolutionY)));
		float stepX = static_cast<float>(prj->getViewportWidth()) / (static_cast<float>(skyResolutionX)-0.5f);
		float stepY = static_cast<float>(prj->getViewportHeight()) / static_cast<float>(skyResolutionY);
		float viewport_left = static_cast<float>(prj->getViewportPosX());
		float viewport_bottom = static_cast<float>(prj->getViewportPosY());
		for (unsigned int x=0; x<=skyResolutionX; ++x)
		{
			for(unsigned int y=0; y<=skyResolutionY; ++y)
			{
				Vec2f &v(posGrid[y*(1+skyResolutionX)+x]);
				v[0] = viewport_left + ((x == 0) ? 0.f :
						(x == skyResolutionX) ? static_cast<float>(prj->getViewportWidth()) : (static_cast<float>(x)-0.5f*(y&1))*stepX);
				v[1] = viewport_bottom+static_cast<float>(y)*stepY;
			}
		}
		posGridBuffer.destroy();
		//posGridBuffer = QOpenGLBuffer(QOpenGLBuffer::VertexBuffer);
		Q_ASSERT(posGridBuffer.type()==QOpenGLBuffer::VertexBuffer);
		posGridBuffer.setUsagePattern(QOpenGLBuffer::StaticDraw);
		posGridBuffer.create();
		posGridBuffer.bind();
		posGridBuffer.allocate(posGrid.constData(), static_cast<int>((1+skyResolutionX)*(1+skyResolutionY))*8);
		posGridBuffer.release();
		
		// Generate the indices used to draw the quads
		indicesBuffer.destroy();
		//indicesBuffer = QOpenGLBuffer(QOpenGLBuffer::IndexBuffer);
		Q_ASSERT(indicesBuffer.type()==QOpenGLBuffer::IndexBuffer);
		indicesBuffer.setUsagePattern(QOpenGLBuffer::StaticDraw);
		indicesBuffer.create();
		indicesBuffer.bind();
		if (AtmosphereGridStrip::fitsUnsignedShort(skyResolutionX, skyResolutionY))
		{
			const auto indices = AtmosphereGridStrip::build<std::uint16_t>(skyResolutionX, skyResolutionY);
			gridIndexCount = static_cast<int>(indices.size());
			gridIndexType = GL_UNSIGNED_SHORT;
			indicesBuffer.allocate(indices.data(), static_cast<int>(indices.size() * sizeof(indices[0])));
		}
		else
		{
			const auto indices = AtmosphereGridStrip::build<std::uint32_t>(skyResolutionX, skyResolutionY);
			gridIndexCount = static_cast<int>(indices.size());
			gridIndexType = GL_UNSIGNED_INT;
			indicesBuffer.allocate(indices.data(), static_cast<int>(indices.size() * sizeof(indices[0])));
		}
		indicesBuffer.release();
		
		colorGridBuffer.destroy();
		colorGridBuffer.setUsagePattern(QOpenGLBuffer::DynamicDraw);
		colorGridBuffer.create();
		colorGridBuffer.bind();
		colorGridBuffer.allocate(colorGrid.constData(), static_cast<int>((1+skyResolutionX)*(1+skyResolutionY)*4*4));
		colorGridBuffer.release();

		bindVAO();
		setupCurrentVAO();
		releaseVAO();
	}

	auto sunPos  =  sun.getAltAzPosAuto(core);
	if (qIsNaN(sunPos.norm()))
		sunPos.set(0.,0.,-1.);

	Vec3d moonPos = sunPos;
	// Calculate the atmosphere RGB for each point of the grid. We can use abbreviated numbers here.

	// qCDebug(Atmo, "touch at %f\tnow at %f (%f)\n", touch_angle, separation_angle, separation_angle/touch_angle);
	// bright stars should be visible at total eclipse
	// TODO: correct for atmospheric diffusion
	// TODO: use better coverage function (non-linear)
	// because of above issues, this algorithm darkens more quickly than reality
	if (moon)
	{
		moonPos = moon->getAltAzPosAuto(core);
		if (qIsNaN(moonPos.norm()))
			moonPos.set(0.,0.,-1.);

		// Update the eclipse intensity factor to apply on atmosphere model
		// these are for radii
		const double sun_angular_radius = atan(sun.getEquatorialRadius()/sunPos.norm());
		const double moon_angular_radius = atan(moon->getEquatorialRadius()/moonPos.norm());
		const double touch_angle = sun_angular_radius + moon_angular_radius;

		// determine luminance falloff during solar eclipses
		sunPos.normalize();
		moonPos.normalize();
		double separation_angle = std::acos(sunPos.dot(moonPos));  // angle between them

		if(separation_angle < touch_angle)
		{
			double dark_angle = moon_angular_radius - sun_angular_radius;
			double min = 0.0025; // 0.005f; // 0.0001f;  // so bright stars show up at total eclipse
			if (dark_angle < 0.)
			{
				// annular eclipse
				double asun = sun_angular_radius*sun_angular_radius;
				min = (asun - moon_angular_radius*moon_angular_radius)/asun;  // minimum proportion of sun uncovered
				dark_angle *= -1;
			}

			if (separation_angle < dark_angle)
				eclipseFactor = static_cast<float>(min);
			else
				eclipseFactor = static_cast<float>(min + (1.0-min)*(separation_angle-dark_angle)/(touch_angle-dark_angle));
		}
		else
			eclipseFactor = 1.0f;
	}
	else
	{
		eclipseFactor = 1.f;
		sunPos.normalize();
	}
	// TODO: compute eclipse factor also for Lunar eclipses! (lp:#1471546)

	// No need to calculate if not visible
	if (!getVisualFadeIntensity())
	{
		luminanceCacheValid = false;
		// GZ 20180114: Why did we add light pollution if atmosphere was not visible?????
		// And what is the meaning of 0.001? Approximate contribution of stellar background? Then why is it 0.0001 below???
		if (!overrideAverageLuminance) averageLuminance = 0.001f;
		return;
	}

	// Calculate the atmosphere RGB for each point of the grid

	// GZ: This used a constant Preetham Turbidity of 5 which is already quite hazy.
	// We can work with the k value set in the atmosphere/extinction settings.
	// Given that T=1 = Pure Air where k=0.16, and other values assumed in parallel, we come to an
	// ad-hoc mapping function which should not look to bad: T=25(k-0.16)+1
	//sky.setParamsv(sunPos, 5.f); // To reach the 5 we have k=0.32
	StelSkyDrawer* skyDrawer = StelApp::getInstance().getCore()->getSkyDrawer();

	float turbidity= ( (skyDrawer->getFlagTfromK()) ?  25.f*(extinctionCoefficient-0.16f)+1.f   : static_cast<float>(skyDrawer->getT()));
	// Note that Preetham's model has some quirks for too low turbidities.
	// A hard limit is some assert later, so must be technically at least 1.203.
	// Also, Preetham has optimized to T in[2..6], which translates now to k in [0.2-0.36].
	// In Schaefer-Krisciunas Moon brightness paper, k=0.172 for Mauna Kea. Preetham will likely be too bright here.
	//sky.setParamsv(sunPos, qBound(2.f, turbidity, 6.f));
	Vec3f sunPosF=sunPos.toVec3f();
	Vec3f moonPosF=moonPos.toVec3f();
	sky.setParamsv(&sunPosF[0], qBound(2.f, turbidity, 16.f));  // GZ-AT allow more turbidity for testing

	skyb.setLocation(location.getLatitude() * M_PI_180f, static_cast<float>(location.altitude), temperature, relativeHumidity);
	skyb.setSunMoon(moonPosF[2], sunPosF[2]);

	// Calculate the date from the julian day.
	int year, month, day;
	StelUtils::getDateFromJulianDay(JD, &year, &month, &day);
	const auto moonPhase = moon ? moon->getPhaseAngle(currentPlanet.getHeliocentricEclipticPos()) : 0.;
	const auto moonMagnitude = moon ? moon->getVMagnitudeWithExtinction(core) : 100.f;
	skyb.setDate(year, month, static_cast<float>(moonPhase), moonMagnitude);
	const float pollution = fader.getInterstate() * lightPollutionLuminance;
	const bool planetsVisible = GETSTELMODULE(SolarSystem)->getFlagPlanets();
	const bool cacheSupported = core->getFlagClearSky() && sky.getFlagSchaefer() && !noScatter;
	const bool reuseLuminance = luminanceCacheValid && cacheSupported
		&& cachedSkyBrightness.hasSameLuminanceParameters(skyb)
		&& cachedSunDirection == sunPosF && cachedMoonDirection == moonPosF
		&& cachedEclipseFactor == eclipseFactor && cachedPollution == pollution
		&& cachedPlanetaryLuminanceScale == planetaryProfile_.luminanceScale
		&& cachedPlanetsVisible == planetsVisible && cachedNoScatter == noScatter;
	bool gridChanged = !reuseLuminance;

	// Variables used to compute the average sky luminance
	float sum_lum = 0.f;

	Vec3d point(1., 0., 0.);
	float lumi=0.f;

#if defined(__OHOS__)
	timing.active = true;
	timing.cacheEligible = cacheSupported;
	timing.cacheReusable = reuseLuminance;
	timing.gridCount = core->getFlagClearSky() ? colorGrid.size() : 0;
	timing.prepNs = timing.timer.nsecsElapsed();
#endif
	// Compute the sky color for every point above the ground
	if (core->getFlagClearSky())
	for (unsigned int i=0; i<(1+skyResolutionX)*(1+skyResolutionY); ++i)
	{
		const Vec2f &v(posGrid[i]);
		prj->unProject(static_cast<double>(v[0]),static_cast<double>(v[1]),point);

		Q_ASSERT(fabs(point.normSquared()-1.0) < 1e-10);

		Vec3f pointF=point.toVec3f();
		if (!noScatter && pointF[2] <= 0.f)
			pointF[2] *= -1.f;
		if (reuseLuminance && colorGrid[i][0] == pointF[0]
			&& colorGrid[i][1] == pointF[1] && colorGrid[i][2] == pointF[2])
		{
#if defined(__OHOS__)
			++timing.cacheHits;
#endif
			sum_lum += colorGrid[i][3];
			continue;
		}
		gridChanged = true;
		if (!noScatter)
		{
			if (sky.getFlagSchaefer())
			{
				lumi = skyb.getLuminance(moonPosF[0]*pointF[0]+moonPosF[1]*pointF[1]+moonPosF[2]*pointF[2],
							 sunPosF[0] *pointF[0]+sunPosF[1] *pointF[1]+sunPosF[2] *pointF[2],
							 pointF[2]);
			}
			else // Experimental: Re-allow CIE/Preetham brightness instead.
			{
				skylightStruct2 skylight;
				skylight.pos[0]=pointF.v[0];
				skylight.pos[1]=pointF.v[1];
				skylight.pos[2]=pointF.v[2];
				sky.getxyYValuev(skylight);
				lumi=skylight.color[2];
			}
		}

		lumi *= eclipseFactor * planetaryProfile_.luminanceScale;
		// Add star background luminance
		lumi += 0.0001f;
		// Multiply by the input scale of the ToneConverter (is not done automatically by the xyYtoRGB method called later)
		//lumi*=eye->getInputScale();

		// Add the light pollution luminance AFTER the scaling to avoid scaling it because it is the cause
		// of the scaling itself
		lumi += pollution;

		// Store for later statistics
		sum_lum+=lumi;

		// No need to compute the xy part of the color component
		// This is done in the openGL shader
		// Store the back projected position + luminance in the input color to the shader
		colorGrid[i].set(pointF[0], pointF[1], pointF[2], lumi);
	}
	
#if defined(__OHOS__)
	timing.gridNs = timing.timer.nsecsElapsed() - timing.prepNs;
#endif
	if (gridChanged)
	{
#if defined(__OHOS__)
		const qint64 uploadStartNs = timing.timer.nsecsElapsed();
#endif
		colorGridBuffer.bind();
		colorGridBuffer.allocate(colorGrid.constData(), static_cast<int>((1+skyResolutionX)*(1+skyResolutionY)*4*4));
		colorGridBuffer.release();
#if defined(__OHOS__)
		timing.uploadNs = timing.timer.nsecsElapsed() - uploadStartNs;
		timing.uploaded = true;
#endif
	}
	cachedSkyBrightness = skyb;
	cachedSunDirection = sunPosF;
	cachedMoonDirection = moonPosF;
	cachedEclipseFactor = eclipseFactor;
	cachedPollution = pollution;
	cachedPlanetaryLuminanceScale = planetaryProfile_.luminanceScale;
	cachedPlanetsVisible = planetsVisible;
	cachedNoScatter = noScatter;
	luminanceCacheValid = cacheSupported;
	
	// Update average luminance
	if (!overrideAverageLuminance)
		averageLuminance = sum_lum/static_cast<float>((1+skyResolutionX)*(1+skyResolutionY));
}

// Draw the atmosphere using the precalc values stored in tab_sky
void AtmospherePreetham::draw(StelCore* core)
{
	if (!core->getFlagClearSky())
		return;
	if (StelApp::getInstance().getVisionModeNight())
		return;

	const float atm_intensity = getVisualFadeIntensity();
	if (atm_intensity==0.f)
	    return;

	StelToneReproducer* eye = core->getToneReproducer();
	const auto worldProjector = core->getProjection(StelCore::FrameAltAz, StelCore::RefractionOff);
	if (mistUndergroundStrength > 0.f && (!renderProjector || !worldProjector->isSameProjection(*renderProjector)))
	{
		compileShaders(worldProjector.data());
		renderProjector = worldProjector;
	}

	StelPainter sPainter(core->getProjection2d());
	sPainter.setBlending(true, GL_ONE, GL_ONE);

	GL(atmoShaderProgram->bind());
	if (renderProjector && worldProjector->isSameProjection(*renderProjector))
		worldProjector->setUnProjectUniforms(*atmoShaderProgram);
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.mistUndergroundStrength, mistUndergroundStrength));
	float a, b, c, d;
	bool useTmGamma, sRGB;
	eye->getShadersParams(a, b, c, d, useTmGamma, sRGB);

	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.alphaWaOverAlphaDa, a));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.oneOverGamma, b));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.term2TimesOneOverMaxdLpOneOverGamma, c));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.term2TimesOneOverMaxdL, d));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.flagUseTmGamma, useTmGamma));

	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.brightnessScale, atm_intensity));
	Vec3f sunPos;
	float term_x, Ax, Bx, Cx, Dx, Ex, term_y, Ay, By, Cy, Dy, Ey;
	sky.getShadersParams(sunPos, term_x, Ax, Bx, Cx, Dx, Ex, term_y, Ay, By, Cy, Dy, Ey);
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.sunPos, sunPos[0], sunPos[1], sunPos[2]));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.vividStrength,
		flagVividAtmosphere && vividAtmosphereAllowed ? eclipseFactor : 0.f));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.planetZenithColor,
		planetaryProfile_.zenithColor.r, planetaryProfile_.zenithColor.g, planetaryProfile_.zenithColor.b));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.planetHorizonColor,
		planetaryProfile_.horizonColor.r, planetaryProfile_.horizonColor.g, planetaryProfile_.horizonColor.b));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.planetTwilightZenith,
		planetaryProfile_.twilightZenith.r, planetaryProfile_.twilightZenith.g, planetaryProfile_.twilightZenith.b));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.planetTwilightHorizon,
		planetaryProfile_.twilightHorizon.r, planetaryProfile_.twilightHorizon.g, planetaryProfile_.twilightHorizon.b));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.planetSunHaloColor,
		planetaryProfile_.sunHaloColor.r, planetaryProfile_.sunHaloColor.g, planetaryProfile_.sunHaloColor.b));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.planetAtmoParams,
		planetaryProfile_.mixStrength, planetaryProfile_.hazeExponent,
		planetaryProfile_.sunHaloStrength, planetaryProfile_.zenithAttenuation));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.term_x, term_x));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.Ax, Ax));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.Bx, Bx));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.Cx, Cx));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.Dx, Dx));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.Ex, Ex));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.term_y, term_y));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.Ay, Ay));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.By, By));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.Cy, Cy));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.Dy, Dy));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.Ey, Ey));
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.doSRGB, sRGB));
	const Mat4f& m = sPainter.getProjector()->getProjectionMatrix();
	GL(atmoShaderProgram->setUniformValue(shaderAttribLocations.projectionMatrix,
					      QMatrix4x4(m[0], m[4], m[8], m[12], m[1], m[5], m[9], m[13], m[2], m[6], m[10], m[14], m[3], m[7], m[11], m[15])));


	// And draw everything at once
	bindVAO();
	GL(indicesBuffer.bind());
	sPainter.glFuncs()->glDrawElements(GL_TRIANGLE_STRIP, gridIndexCount, gridIndexType, nullptr);
	GL(indicesBuffer.release());
	releaseVAO();
	
	GL(atmoShaderProgram->release());
	// debug output
	// sPainter.setColor(0.7f, 0.7f, 0.7f);
	// sPainter.drawText(83, 108, QString("Tonemapper::worldAdaptationLuminance(): %1" ).arg(eye->getWorldAdaptationLuminance()));
	// sPainter.drawText(83, 120, QString("AtmospherePreetham::getAverageLuminance(): %1" ).arg(getAverageLuminance()));
}
