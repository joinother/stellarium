/*
 * Stellarium
 * Copyright (C) 2015 Marcos Cardinot
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

#include "LandscapeMgr.hpp"
#include "SolarSystem.hpp"
#include "SporadicMeteorMgr.hpp"
#include "StelApp.hpp"
#include "StelCore.hpp"
#include "StelFileMgr.hpp"
#include "StelModuleMgr.hpp"
#include "StelPainter.hpp"
#include "StelTextureMgr.hpp"

#include <QSettings>

#include <cmath>

SporadicMeteorMgr::SporadicMeteorMgr(int zhr, int maxv)
	: m_zhr(zhr)
	, m_maxVelocity(maxv)
	, m_flagShow(true)
	, m_flagForcedShow(false)
	, m_diagnosticElapsedFrames(0)
	, m_diagnosticCandidateCount(0)
	, m_diagnosticRequestedCount(0)
	, m_diagnosticAcceptedCount(0)
	, m_diagnosticRejectedCount(0)
	, m_diagnosticElapsedSeconds(0.)
	, m_lastDeltaTime(0.)
	, m_lastExpectedPerSecond(0.)
	, m_lastSpawnProbability(0.)
	, m_lastMaxMeteorsPerFrame(0)
	, m_lastGenerationSuppression(QStringLiteral("not-started"))
	, m_spawnAccumulator(0.)
{
	setObjectName("SporadicMeteorMgr");
}

SporadicMeteorMgr::~SporadicMeteorMgr()
{
	qDeleteAll(activeMeteors);
	activeMeteors.clear();
	m_bolideTexture.clear();
}

void SporadicMeteorMgr::init()
{
	m_bolideTexture = StelApp::getInstance().getTextureManager().createTextureThread(
				StelFileMgr::getInstallationDir() + "/textures/cometComa.png",
				StelTexture::StelTextureParams(true, GL_LINEAR, GL_CLAMP_TO_EDGE));

	QSettings* conf = StelApp::getInstance().getSettings();
	setZHR(conf->value("astro/meteor_zhr", 10).toInt());
	setFlagForcedMeteorsActivity(conf->value("astro/flag_forced_meteor_activity", false).toBool());
}

double SporadicMeteorMgr::getCallOrder(StelModuleActionName actionName) const
{
	if (actionName == StelModule::ActionDraw)
	{
		static SolarSystem *ss=GETSTELMODULE(SolarSystem);
		return ss->getCallOrder(actionName) + 10.;
	}
	return 0;
}

void SporadicMeteorMgr::update(double deltaTime)
{
	++m_diagnosticElapsedFrames;
	m_lastDeltaTime = qMax(0.0, deltaTime);
	m_diagnosticElapsedSeconds += m_lastDeltaTime;
	m_lastExpectedPerSecond = static_cast<double>(m_zhr) / 3600.0;
	m_lastSpawnProbability = 0.;
	m_lastMaxMeteorsPerFrame = 0;

	if (!m_flagShow)
	{
		m_lastGenerationSuppression = QStringLiteral("display-disabled");
		return;
	}

	// step through and update all active meteors
	foreach (SporadicMeteor* m, activeMeteors)
	{
		if (!m->update(deltaTime))
		{
			//important to delete when no longer active
			activeMeteors.removeOne(m);
			delete m;
		}
	}

	StelCore* core = StelApp::getInstance().getCore();

	// going forward/backward OR current ZHR is zero ?
	// don't create new meteors
	if(!core->getRealTimeSpeed() || m_zhr < 1)
	{
		m_spawnAccumulator = 0.;
		m_lastGenerationSuppression = !core->getRealTimeSpeed()
			? QStringLiteral("real-time-speed-required")
			: QStringLiteral("zhr-zero");
		return;
	}
	m_lastGenerationSuppression = QStringLiteral("none");

	const double spawnDelta = qMin(qMax(deltaTime, 0.), 0.25);
	m_spawnAccumulator += static_cast<double>(m_zhr) * spawnDelta / 3600.0;
	int requested = static_cast<int>(std::floor(m_spawnAccumulator));
	m_spawnAccumulator -= requested;
	m_lastMaxMeteorsPerFrame = requested;
	m_lastSpawnProbability = m_spawnAccumulator;
	for (int i = 0; i < requested; ++i)
	{
		++m_diagnosticCandidateCount;
		++m_diagnosticRequestedCount;
		bool accepted = false;
		for (int attempt = 0; attempt < 64; ++attempt)
		{
			SporadicMeteor* m = new SporadicMeteor(core, m_maxVelocity, m_bolideTexture);
			if (m->isAlive())
			{
				activeMeteors.append(m);
				accepted = true;
				++m_diagnosticAcceptedCount;
				break;
			}
			++m_diagnosticRejectionReasons[m->getRejectionReason()];
			delete m;
		}
		if (!accepted)
			++m_diagnosticRejectedCount;
	}
}

QJsonObject SporadicMeteorMgr::getDiagnostics() const
{
	QJsonObject result;
	StelCore* core = StelApp::getInstance().getCore();
	result[QStringLiteral("zhr")] = m_zhr;
	result[QStringLiteral("maxZhr")] = MaxZHR;
	result[QStringLiteral("displayEnabled")] = m_flagShow;
	result[QStringLiteral("realTimeSpeed")] = core && core->getRealTimeSpeed();
	result[QStringLiteral("timeRate")] = core ? core->getTimeRate() : 0.;
	result[QStringLiteral("activeCount")] = activeMeteors.size();
	result[QStringLiteral("expectedPerSecond")] = m_lastExpectedPerSecond;
	result[QStringLiteral("expectedPerMinute")] = m_lastExpectedPerSecond * 60.0;
	result[QStringLiteral("lastDeltaTime")] = m_lastDeltaTime;
	result[QStringLiteral("lastSpawnProbability")] = m_lastSpawnProbability;
	result[QStringLiteral("lastMaxMeteorsPerFrame")] = m_lastMaxMeteorsPerFrame;
	result[QStringLiteral("generationSuppression")] = m_lastGenerationSuppression;
	result[QStringLiteral("diagnosticElapsedSeconds")] = m_diagnosticElapsedSeconds;
	result[QStringLiteral("diagnosticFrames")] = static_cast<qint64>(m_diagnosticElapsedFrames);
	result[QStringLiteral("candidateCount")] = static_cast<qint64>(m_diagnosticCandidateCount);
	result[QStringLiteral("requestedCount")] = static_cast<qint64>(m_diagnosticRequestedCount);
	result[QStringLiteral("acceptedCount")] = static_cast<qint64>(m_diagnosticAcceptedCount);
	result[QStringLiteral("rejectedCount")] = static_cast<qint64>(m_diagnosticRejectedCount);
	result[QStringLiteral("observedAcceptedPerMinute")] = m_diagnosticElapsedSeconds > 0.
		? static_cast<double>(m_diagnosticAcceptedCount) / m_diagnosticElapsedSeconds * 60.0
		: 0.;
	result[QStringLiteral("spawnAccumulator")] = m_spawnAccumulator;
	QJsonObject rejectionReasons;
	for (auto it = m_diagnosticRejectionReasons.cbegin(); it != m_diagnosticRejectionReasons.cend(); ++it)
		rejectionReasons[it.key()] = static_cast<qint64>(it.value());
	result[QStringLiteral("rejectionReasons")] = rejectionReasons;

	QString drawSuppression = QStringLiteral("none");
	if (!m_flagShow)
		drawSuppression = QStringLiteral("display-disabled");
	else if (!core)
		drawSuppression = QStringLiteral("core-unavailable");
	else if (!core->getSkyDrawer()->getFlagHasAtmosphere() && !m_flagForcedShow)
		drawSuppression = QStringLiteral("atmosphere-disabled");
	else
	{
		LandscapeMgr* landmgr = GETSTELMODULE(LandscapeMgr);
		if (landmgr && landmgr->getFlagAtmosphere() && landmgr->getLuminance() > 5.f)
			drawSuppression = QStringLiteral("daylight-too-bright");
	}
	result[QStringLiteral("drawSuppression")] = drawSuppression;
	return result;
}

void SporadicMeteorMgr::draw(StelCore* core)
{
	if (!m_flagShow || (!core->getSkyDrawer()->getFlagHasAtmosphere() && !getFlagForcedMeteorsActivity()))
	{
		return;
	}

	static LandscapeMgr* landmgr = GETSTELMODULE(LandscapeMgr);
	if (landmgr->getFlagAtmosphere() && landmgr->getLuminance() > 5.f)
	{
		return;
	}

	// step through and draw all active meteors
	StelPainter sPainter(core->getProjection(StelCore::FrameAltAz));
	for (auto* m: std::as_const(activeMeteors))
	{
		m->draw(core, sPainter);
	}
}

void SporadicMeteorMgr::setZHR(int zhr)
{
	zhr = qBound(0, zhr, MaxZHR);
	if(zhr!=m_zhr)
	{
		m_zhr = zhr;
		StelApp::immediateSave("astro/meteor_zhr", zhr);
		emit zhrChanged(zhr);
	}
}
