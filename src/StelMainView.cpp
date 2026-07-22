/*
 * Stellarium
 * Copyright (C) 2007 Fabien Chereau
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

#define MOUSE_TRACKING

#include "StelMainView.hpp"
#include "StelApp.hpp"
#include "StelCore.hpp"
#include "StelFileMgr.hpp"
#include "StelProjector.hpp"
#include "StelPainter.hpp"
#include "StelGui.hpp"
#include "SkyGui.hpp"
#include "StelTranslator.hpp"
#include "StelUtils.hpp"
#include "StelActionMgr.hpp"
#include "StelOpenGL.hpp"
#include "StelOpenGLArray.hpp"
#include "StelProjector.hpp"
#include "StelModuleMgr.hpp"
#include "StelMovementMgr.hpp"
#include "StelObject.hpp"
#include "StelObjectMgr.hpp"
#include "StelObserver.hpp"
#include "StelLocaleMgr.hpp"
#include "StelSkyCultureMgr.hpp"
#include "LandscapeMgr.hpp"
#include "NebulaMgr.hpp"
#include "StelScriptMgr.hpp"
#include "SolarSystem.hpp"

#include <QByteArray>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QJsonDocument>
#include <cstdio>
#include <QJsonObject>
#include <QOpenGLFunctions>
#include <QJsonArray>
#include <QOpenGLWidget>
#include <QApplication>
#include <QTcpSocket>
#include <QGuiApplication>
#include <QMutex>
#include <QWaitCondition>
#include <QHash>
#include <QSet>
#include <QGraphicsSceneMouseEvent>
#include <QGraphicsAnchorLayout>
#include <QGraphicsWidget>
#include <QGraphicsEffect>
#include <QFileInfo>
#include <QIcon>
#include <QImageWriter>
#include <QMoveEvent>
#include <QPluginLoader>
#include <QScreen>
#include <QSettings>
#include <QRegularExpression>
#include <QtPlugin>
#include <QThread>
#include <QTimer>
#include <QVariantMap>
#include <QWidget>
#include <QWindow>
#include <QMessageBox>
#include <QStandardPaths>
#include <QStorageInfo>
#ifdef Q_OS_WIN
	#include <QPinchGesture>
	#include <Windows.h>
	#include <WinUser.h>
#endif
#include <QOpenGLShader>
#include <QOpenGLShaderProgram>
#include <QOpenGLFramebufferObject>
#include <QOpenGLPaintDevice>
#ifdef OPENGL_DEBUG_LOGGING
#include <QOpenGLDebugLogger>
#endif
#include <QLoggingCategory>

Q_LOGGING_CATEGORY(mainview, "stel.MainView")

#include <algorithm>
#include <cmath>
#include <clocale>
#if defined(__OHOS__)
#include <dlfcn.h>
#include <hilog/log.h>
#endif

#ifndef GL_MAX_TEXTURE_MAX_ANISOTROPY
# define GL_MAX_TEXTURE_MAX_ANISOTROPY 0x84FF
#endif

// Initialize static variables
StelMainView* StelMainView::singleton = Q_NULLPTR;

#if defined(__OHOS__)
namespace
{
using OhosSubmitFrameFunc = void (*)(const unsigned char*, int, int);
constexpr int OHOS_INTERACTIVE_RENDER_INTERVAL_MS = 33;
constexpr int OHOS_IDLE_RENDER_INTERVAL_MS = 125;

void ohosMark(const char* message)
{
	OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "StellariumCpp", "%{public}s", message);
}

int currentOhosRenderIntervalMs()
{
	if (!StelApp::isInitialized())
		return OHOS_IDLE_RENDER_INTERVAL_MS;
	return StelMainView::getInstance().needsMaxFPS() ? OHOS_INTERACTIVE_RENDER_INTERVAL_MS : OHOS_IDLE_RENDER_INTERVAL_MS;
}

void markOhosInteraction()
{
	if (StelApp::isInitialized())
		StelMainView::getInstance().thereWasAnEvent();
}

QString formatLx200Ra(int totalSeconds)
{
	totalSeconds %= 86400;
	if (totalSeconds < 0)
		totalSeconds += 86400;
	return QString("%1:%2:%3")
		.arg(totalSeconds / 3600, 2, 10, QChar('0'))
		.arg((totalSeconds / 60) % 60, 2, 10, QChar('0'))
		.arg(totalSeconds % 60, 2, 10, QChar('0'));
}

QString formatLx200Dec(int totalArcSeconds)
{
	const QChar sign = totalArcSeconds < 0 ? QChar('-') : QChar('+');
	int value = std::abs(totalArcSeconds);
	return QString("%1%2%3%4:%5")
		.arg(sign)
		.arg(value / 3600, 2, 10, QChar('0'))
		.arg(QChar(0xDF))
		.arg((value / 60) % 60, 2, 10, QChar('0'))
		.arg(value % 60, 2, 10, QChar('0'));
}

QJsonObject sendLx200Commands(const QString& host, quint16 port, const QStringList& commands)
{
	QJsonObject result;
	result["ok"] = false;
	result["host"] = host;
	result["port"] = int(port);

	QTcpSocket socket;
	socket.connectToHost(host, port);
	if (!socket.waitForConnected(900))
	{
		result["error"] = "LX200 TCP connect failed: " + socket.errorString();
		return result;
	}

	QStringList replies;
	for (const QString& command : commands)
	{
		const QByteArray payload = command.toLatin1();
		if (socket.write(payload) != payload.size() || !socket.waitForBytesWritten(600))
		{
			result["error"] = "LX200 TCP write failed: " + socket.errorString();
			result["command"] = command;
			return result;
		}

		if (command == "#:Q#")
			continue;

		QByteArray reply;
			const qint64 deadline = QDateTime::currentMSecsSinceEpoch() + 900;
		while (QDateTime::currentMSecsSinceEpoch() < deadline)
		{
			if (socket.waitForReadyRead(250))
			{
				reply += socket.readAll();
				if (reply.contains('#') || (!reply.isEmpty() && command == ":MS#"))
					break;
			}
		}
		if (reply.isEmpty())
		{
			result["error"] = "LX200 TCP command timed out";
			result["command"] = command;
			return result;
		}
		replies << QString::fromLatin1(reply);
	}

	result["ok"] = true;
	result["replies"] = replies.join("|");
	result["sent"] = commands.join("|");
	return result;
}

QJsonObject selectedObjectJ2000Json(Vec3d* positionOut = nullptr)
{
	QJsonObject result;
	result["ok"] = false;

	StelCore* core = StelApp::getInstance().getCore();
	StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
	if (!core || !objectMgr || objectMgr->getSelectedObject().isEmpty())
	{
		result["error"] = "no selected object";
		return result;
	}

	const StelObjectP object = objectMgr->getSelectedObject().constFirst();
	Vec3d position = object->getJ2000EquatorialPos(core);
	position.normalize();
	if (positionOut)
		*positionOut = position;

	const double raSigned = std::atan2(position[1], position[0]);
	const double ra = raSigned >= 0.0 ? raSigned : raSigned + 2.0 * M_PI;
	const double dec = std::atan2(position[2], std::sqrt(position[0] * position[0] + position[1] * position[1]));
	result["ok"] = true;
	result["name"] = object->getNameI18n();
	result["englishName"] = object->getEnglishName();
	result["raHours"] = ra * 12.0 / M_PI;
	result["decDegrees"] = dec * 180.0 / M_PI;
	return result;
}

QJsonObject lx200GotoSelected(const QString& payload, bool sync)
{
	const QStringList parts = payload.split('|');
	if (parts.size() < 2)
	{
		QJsonObject result;
		result["ok"] = false;
		result["error"] = "expects host|port";
		return result;
	}

	bool okPort = false;
	const QString host = parts[0].trimmed();
	const int portInt = parts[1].toInt(&okPort);
	if (host.isEmpty() || !okPort || portInt <= 0 || portInt > 65535)
	{
		QJsonObject result;
		result["ok"] = false;
		result["error"] = "invalid LX200 endpoint";
		return result;
	}

	Vec3d position;
	QJsonObject objectResult = selectedObjectJ2000Json(&position);
	if (objectResult["ok"] != true)
		return objectResult;

	const double raSigned = std::atan2(position[1], position[0]);
	const double ra = raSigned >= 0.0 ? raSigned : raSigned + 2.0 * M_PI;
	const double dec = std::atan2(position[2], std::sqrt(position[0] * position[0] + position[1] * position[1]));
	int raSeconds = int(std::floor(0.5 + ra * 43200.0 / M_PI));
	if (raSeconds >= 86400)
		raSeconds -= 86400;
	const int decArcSeconds = int(std::floor(0.5 + dec * 648000.0 / M_PI));

	const QStringList commands = {
		"#:Q#",
		":Sr" + formatLx200Ra(raSeconds) + "#",
		":Sd" + formatLx200Dec(decArcSeconds) + "#",
		sync ? ":CM#" : ":MS#"
	};

	QJsonObject result = sendLx200Commands(host, quint16(portInt), commands);
	result["target"] = objectResult["name"].toString().isEmpty() ? objectResult["englishName"].toString() : objectResult["name"].toString();
	result["ra"] = formatLx200Ra(raSeconds);
	result["dec"] = formatLx200Dec(decArcSeconds);
	result["mode"] = sync ? "sync" : "goto";
	return result;
}

void submitOhosFramebuffer(QOpenGLFunctions* gl)
{
	static int paintCounter = 0;
	static int observedFrames = 0;
	static int submittedFrames = 0;
	if (paintCounter == 0)
		ohosMark("StelRootItem paint reached");
	++paintCounter;

	static bool resolved = false;
	static OhosSubmitFrameFunc submitFrame = nullptr;
	if (!resolved)
	{
		resolved = true;
		void* entryHandle = dlopen("libentry.so", RTLD_NOW | RTLD_NOLOAD);
		if (!entryHandle)
			entryHandle = dlopen("libentry.so", RTLD_NOW);
		submitFrame = reinterpret_cast<OhosSubmitFrameFunc>(entryHandle ? dlsym(entryHandle, "StellariumEntry_submitFrame")
													: dlsym(RTLD_DEFAULT, "StellariumEntry_submitFrame"));
		qInfo() << "OpenHarmony native frame bridge" << (submitFrame ? "resolved." : "not found.");
		ohosMark(submitFrame ? "frame bridge resolved" : "frame bridge not found");
	}
	if (!submitFrame)
		return;

	GLint viewport[4] = {0, 0, 0, 0};
	gl->glGetIntegerv(GL_VIEWPORT, viewport);
	const int width = viewport[2];
	const int height = viewport[3];
	static bool loggedViewport = false;
	if (!loggedViewport)
	{
		loggedViewport = true;
		OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "StellariumCpp", "framebuffer viewport %{public}dx%{public}d", width, height);
	}
	if (width <= 0 || height <= 0)
		return;

	QByteArray pixels;
	pixels.resize(width * height * 4);
	gl->glPixelStorei(GL_PACK_ALIGNMENT, 1);
	gl->glReadPixels(viewport[0], viewport[1], width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
	const GLenum error = gl->glGetError();
	if (error != GL_NO_ERROR)
	{
		qWarning() << "OpenHarmony framebuffer readback failed:" << Qt::hex << error;
		return;
	}

	const unsigned char* rgba = reinterpret_cast<const unsigned char*>(pixels.constData());
	++observedFrames;
	if (submittedFrames == 0)
	{
		const int pixelCount = width * height;
		int maxChannel = 0;
		int litPixels = 0;
		int strongPixels = 0;
		unsigned long long luminanceSum = 0;
		for (int i = 0; i < pixelCount; ++i)
		{
			const int index = i * 4;
			const int brightest = std::max({int(rgba[index]), int(rgba[index + 1]), int(rgba[index + 2])});
			maxChannel = std::max(maxChannel, brightest);
			luminanceSum += brightest;
			if (brightest > 18)
				++litPixels;
			if (brightest > 64)
				++strongPixels;
		}
		if (observedFrames <= 4)
		{
			OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "StellariumCpp",
						 "frame stats n=%{public}d max=%{public}d lit=%{public}d strong=%{public}d avg=%{public}llu",
						 observedFrames, maxChannel, litPixels, strongPixels, luminanceSum / static_cast<unsigned long long>(pixelCount));
		}
		if (maxChannel < 24 || (litPixels < 128 && strongPixels < 8))
			return;
	}

	submitFrame(rgba, width, height);
	++submittedFrames;
	if (submittedFrames == 1)
	{
		qInfo() << "Submitted first Stellarium framebuffer to OpenHarmony native surface:" << width << "x" << height;
		ohosMark("submitted first Stellarium framebuffer");
	}
}

// OHOS command marshaling between the ArkUI/JS thread and the Qt main
// thread. During Qt's bootstrap the ArkUI thread may call commands
// before the Qt main event loop is pumping; a blocking cross-thread
// call there deadlocks the ArkUI thread (and previously aborted the
// process inside makeQtThreadWithMainFuncLauncher). So we marshal
// non-blockingly while bootstrapping, cache the result, and switch to a
// safe blocking marshal once the loop is running.
static QMutex s_ohosCmdMutex;
static bool s_qtLoopRunning = false;
static QSet<QString> s_ohosCmdInflight;
static QHash<QString, QJsonObject> s_ohosCmdCache;

// Cross-thread command queue drained by the OHOS render pump
// (renderOhosFrameNow) on the Qt main thread every frame. OHOS Qt may
// drive rendering via a native vsync callback rather than the Qt event
// loop, so QMetaObject::invokeMethod(..., QueuedConnection) is not
// guaranteed to be pumped; we hand commands to the pump instead.
static QMutex s_ohosCmdQueueMutex;
static QList<std::function<void()>> s_ohosCmdQueue;
static void markQtLoopRunning();

static void ohosDrainCommandQueue()
{
	if (!StelApp::isInitialized())
		return; // keep queued for the next frame
	if (!qApp || QThread::currentThread() != qApp->thread())
		return; // not on the Qt main thread; the render pump will call us there
	QList<std::function<void()>> batch;
	{
		QMutexLocker lock(&s_ohosCmdQueueMutex);
		if (s_ohosCmdQueue.isEmpty())
			return;
		batch = s_ohosCmdQueue;
		s_ohosCmdQueue.clear();
	}
	markQtLoopRunning();
	OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "StellariumCpp", "ohosDrainCommandQueue ran n=%{public}d", (int)batch.size());
	for (auto& fn : batch)
		fn();
}

static void markQtLoopRunning()
{
	QMutexLocker lock(&s_ohosCmdMutex);
	s_qtLoopRunning = true;
}

QString runOhosCommandOnQtThread(const QString& key, const std::function<QJsonObject()>& command)
{
	QJsonObject result;
	if (!qApp)
	{
		result["ok"] = false;
		result["error"] = "qApp not ready";
		return QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact));
	}

	// On the Qt main thread: simply run it. Reaching here also means the
	// event loop is pumping, so mark it as running.
	if (QThread::currentThread() == qApp->thread())
	{
		markQtLoopRunning();
		if (!StelApp::isInitialized())
		{
			result["ok"] = false;
			result["error"] = "StellApp not initialized";
			return QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact));
		}
		return QString::fromUtf8(QJsonDocument(command()).toJson(QJsonDocument::Compact));
	}

	// Off-thread path (ArkUI/JS thread): NEVER block here. The OHOS render
	// pump (renderOhosFrameNow -> ohosDrainCommandQueue, which executes the
	// queued commands on the Qt main thread) is driven from the SAME
	// ArkUI/vsync thread this N-API call arrives on. Blocking this thread
	// therefore stalls the render pump so the drain never runs -> the command
	// times out forever and frames freeze after the first one (verified in
	// hilog: 1.5s-cadence retries, zero "ohosDrainCommandQueue ran"). So we
	// enqueue and return "pending" immediately; the ArkUI side polls again
	// (callNativeWhenReady / interactive retry) and picks up the FRESH result.
	//
	// We deliberately do NOT keep a permanent per-key cache: interactive
	// commands (selectAt, searchObject, getSelectedObjectInfo, moveToSelected,
	// listMatchingObjects) must recompute on every logical request, else a
	// stale first result is replayed forever ("tap twice to select", dead
	// search box). Mechanism = CONSUME-ON-READ result store keyed by cmd|arg:
	//   ready    -> take() the result (erase it) and return it; a later
	//               identical request re-enqueues and recomputes fresh.
	//   in-flight-> return pending (avoid duplicate enqueue).
	//   new      -> mark in-flight, enqueue, return pending.
	// Core still bootstrapping: return pending without touching the queue.
	if (!StelApp::isInitialized())
	{
		result["ok"] = false;
		result["error"] = "pending";
		result["pending"] = true;
		return QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact));
	}
	// Fire-and-forget view commands (zoomBy / dragView / panBy) are called
	// rapidly, never polled for a result, and often repeat with identical
	// args. Routing them through the consume-on-read store would let a stale
	// cached result be returned on the next identical call WITHOUT executing
	// (execute/skip/execute...). So bypass the store: always enqueue a fresh
	// execution and return pending; the caller ignores the return value.
	{
		const QString cmdName = key.section('|', 0, 0);
		if (cmdName == "zoomBy" || cmdName == "dragView" || cmdName == "panBy")
		{
			QMutexLocker qlock(&s_ohosCmdQueueMutex);
			s_ohosCmdQueue.append([command]() { command(); });
			result["ok"] = false;
			result["error"] = "pending";
			result["pending"] = true;
			return QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact));
		}
	}
	{
		QMutexLocker qlock(&s_ohosCmdQueueMutex);
		auto it = s_ohosCmdCache.find(key);
		if (it != s_ohosCmdCache.end())
		{
			QJsonObject r = it.value();
			s_ohosCmdCache.erase(it);        // consume-on-read: fresh next time
			s_ohosCmdInflight.remove(key);
			return QString::fromUtf8(QJsonDocument(r).toJson(QJsonDocument::Compact));
		}
		if (s_ohosCmdInflight.contains(key))
		{
			result["ok"] = false;
			result["error"] = "pending";
			result["pending"] = true;
			return QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact));
		}
		s_ohosCmdInflight.insert(key);
		// Bound the store: fire-and-forget commands (zoomBy, dragView, ...) never
		// have their result consumed, so cap growth defensively.
		if (s_ohosCmdCache.size() > 128)
			s_ohosCmdCache.clear();
		s_ohosCmdQueue.append([key, command]() {
			QJsonObject r = command();
			QMutexLocker l(&s_ohosCmdQueueMutex);
			s_ohosCmdCache.insert(key, r);
			s_ohosCmdInflight.remove(key);
		});
	}
	result["ok"] = false;
	result["error"] = "pending";
	result["pending"] = true;
	return QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact));
}

QJsonObject selectedObjectJson(StelCore* core = nullptr)
{
	QJsonObject result;
	result["ok"] = true;

	StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
	if (!objectMgr || objectMgr->getSelectedObject().isEmpty())
	{
		result["found"] = false;
		return result;
	}

	const StelObjectP object = objectMgr->getSelectedObject().constFirst();
	result["found"] = true;
	result["name"] = object->getNameI18n();
	result["englishName"] = object->getEnglishName();
	result["type"] = object->getObjectTypeI18n();

	if (core)
	{
		const QVariantMap m = object->getInfoMap(core);

		// Normalized magnitude (visual, no extinction)
		if (m.contains("vmag"))
			result["magnitude"] = m["vmag"].toDouble();

		// Normalized altitude / azimuth (apparent, degrees)
		if (m.contains("altitude"))
			result["altitude"] = m["altitude"].toDouble();
		if (m.contains("azimuth"))
			result["azimuth"] = m["azimuth"].toDouble();

		// Normalized RA / Dec (formatted strings for display)
		if (m.contains("ra"))
		{
			double ra = m["ra"].toDouble();
			if (ra < 0) ra += 360.;
			result["ra"] = StelUtils::radToHmsStr(ra * M_PI / 180.);
		}
		if (m.contains("dec"))
			result["dec"] = StelUtils::radToDmsStr(m["dec"].toDouble() * M_PI / 180., true);

		// Constellation (IAU abbreviation, full name via i18n if available)
		if (m.contains("iauConstellation"))
		{
			QString abbrev = m["iauConstellation"].toString();
			result["constellation"] = abbrev;
		}

		// Distance (in AU for solar system, else light-years or parsecs if available)
		if (m.contains("distance"))
		{
			double distAu = m["distance"].toDouble();
			if (distAu > 0)
			{
				if (distAu < 1000.)
					result["distance"] = QString::number(distAu, 'f', 4) + " AU";
				else
					result["distance"] = QString::number(distAu / 63241.077, 'f', 2) + " ly";
			}
		}

		// Plain-text summary info
		const QString info = object->getInfoString(core, StelObject::ShortInfo |
			StelObject::Magnitude | StelObject::AltAzi | StelObject::Distance |
			StelObject::Size | StelObject::PlainText).simplified();
		if (!info.isEmpty())
			result["info"] = info;
	}
	return result;
}

QJsonObject currentStateJson()
{
	QJsonObject result;
	result["ok"] = true;

	StelActionMgr* actionMgr = StelApp::getInstance().getStelActionManager();
	StelCore* core = StelApp::getInstance().getCore();
	StelMovementMgr* movementMgr = GETSTELMODULE(StelMovementMgr);

	if (core)
	{
		const StelLocation& location = core->getCurrentLocation();
		result["timeRate"] = core->getTimeRate();
		result["jd"] = core->getJD();
		result["timeText"] = StelUtils::julianDayToISO8601String(core->getJD() + core->getUTCOffset(core->getJD()) / 24.0);
		result["locationName"] = location.name;
		result["locationRegion"] = location.region;
		result["planetName"] = location.planetName;
		result["latitude"] = location.getLatitude();
		result["longitude"] = location.getLongitude();
		result["altitude"] = location.altitude;
	}

	if (movementMgr)
	{
		result["fov"] = movementMgr->getCurrentFov();
		result["tracking"] = movementMgr->getFlagTracking();
	}

	if (actionMgr)
	{
		const QStringList ids = {
			"actionShow_Stars",
			"actionShow_Stars_Labels",
			"actionShow_Planets",
			"actionShow_Planets_Labels",
			"actionShow_Planets_Orbits",
			"actionShow_Planets_Hints",
			"actionShow_Nebulas",
			"actionShow_MilkyWay",
			"actionShow_Ground",
			"actionShow_Constellation_Lines",
			"actionShow_Constellation_Labels",
			"actionShow_Constellation_Boundaries",
			"actionShow_Constellation_Art",
			"actionShow_Atmosphere",
			"actionShow_Cardinal_Points",
			"actionShow_Azimuthal_Grid",
			"actionShow_Equatorial_Grid",
			"actionShow_Equatorial_J2000_Grid",
			"actionShow_Ecliptic_Grid",
			"actionShow_Meridian_Line",
			"actionShow_Horizon_Line"
		};
		for (const QString& id : ids)
		{
			StelAction* action = actionMgr->findAction(id);
			if (action && action->isCheckable())
				result[id] = action->isChecked();
		}
	}

	return result;
}
}

extern "C" __attribute__((visibility("default"))) const char* StellariumOhos_command(const char* command, const char* payload)
{
	static QByteArray response;
	const QString commandName = QString::fromUtf8(command ? command : "");
	const QString arg = QString::fromUtf8(payload ? payload : "");
	qInfo() << "[StellariumOhos] command received:" << commandName << arg;

	const QString json = runOhosCommandOnQtThread(commandName + "|" + arg, [commandName, arg]() -> QJsonObject {
		QJsonObject result;
		result["ok"] = false;
		qInfo() << "[StellariumOhos] command on Qt thread:" << commandName;

		StelActionMgr* actionMgr = StelApp::getInstance().getStelActionManager();
		StelCore* core = StelApp::getInstance().getCore();
		StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
		StelMovementMgr* movementMgr = GETSTELMODULE(StelMovementMgr);

		if (commandName == "triggerAction" || commandName == "setActionChecked" || commandName == "getActionState")
		{
			StelAction* action = actionMgr ? actionMgr->findAction(arg.section('|', 0, 0)) : nullptr;
			if (!action)
			{
				result["error"] = "action not found";
				result["id"] = arg.section('|', 0, 0);
				return result;
			}

			if (commandName == "triggerAction")
			{
				action->trigger();
				markOhosInteraction();
			}
			else if (commandName == "setActionChecked")
			{
				if (!action->isCheckable())
				{
					result["error"] = "action is not checkable";
					result["id"] = action->getId();
					return result;
				}
				action->setChecked(arg.section('|', 1, 1) == "1" || arg.section('|', 1, 1).toLower() == "true");
				markOhosInteraction();
			}

			result["ok"] = true;
			result["id"] = action->getId();
			result["checkable"] = action->isCheckable();
			result["checked"] = action->isCheckable() ? action->isChecked() : false;
			return result;
		}

		if (commandName == "saveScreenShot")
		{
			StelMainView::getInstance().saveScreenShot();
			result["ok"] = true;
			result["message"] = "screenshot saved";
			return result;
		}

		if (commandName == "searchObject")
		{
			if (!objectMgr)
			{
				result["error"] = "object manager not found";
				return result;
			}

			const QString query = arg.trimmed();
			bool found = !query.isEmpty() && (objectMgr->findAndSelectI18n(query) || objectMgr->findAndSelect(query));
			if (found && movementMgr && !objectMgr->getSelectedObject().isEmpty())
			{
				movementMgr->moveToObject(objectMgr->getSelectedObject().constFirst(), movementMgr->getAutoMoveDuration());
				movementMgr->setFlagTracking(true);
			}
			markOhosInteraction();

			result = selectedObjectJson(core);
			result["ok"] = true;
			result["found"] = found;
			result["query"] = query;
			return result;
		}

	if (commandName == "listMatchingObjects")
	{
		if (!objectMgr) { result["error"] = "object manager not found"; return result; }
		QString prefix = arg.trimmed();
		int maxItems = 10;
		int sep = prefix.indexOf('|');
		if (sep > 0) {
			bool ok = false;
			int n = prefix.mid(sep + 1).toInt(&ok);
			if (ok && n > 0 && n <= 50) { maxItems = n; }
			prefix = prefix.left(sep);
		}
		const auto list = objectMgr->listMatchingObjects(prefix, maxItems, true);
		QJsonArray items;
		for (const auto& pair : list) { items.append(pair.first); }
		result["ok"] = true; result["items"] = items;
		result["count"] = items.size(); result["prefix"] = prefix;
		return result;
	}

	if (commandName == "listObjects")
	{
		if (!objectMgr) { result["error"] = "object manager not found"; return result; }
		QString moduleId = arg.trimmed();
		bool inEnglish = true;
		int sep = moduleId.indexOf('|');
		if (sep > 0) {
			QString lang = moduleId.mid(sep + 1).trimmed().toLower();
			inEnglish = (lang != "false" && lang != "0");
			moduleId = moduleId.left(sep);
		}
		const auto list = objectMgr->listAllModuleObjects(moduleId, inEnglish);
		QJsonArray items;
		for (const auto& pair : list) { items.append(pair.first); }
		result["ok"] = true; result["items"] = items;
		result["count"] = items.size(); result["moduleId"] = moduleId;
		return result;
	}

	if (commandName == "getSkyCultures")
	{
		StelSkyCultureMgr* skyCultureMgr = GETSTELMODULE(StelSkyCultureMgr);
		if (!skyCultureMgr) { result["error"] = "sky culture manager not found"; return result; }
		QJsonArray items;
		for (const QString& name : skyCultureMgr->getSkyCultureListI18()) { items.append(name); }
		result["ok"] = true; result["items"] = items;
		result["current"] = skyCultureMgr->getCurrentSkyCultureNameI18();
		return result;
	}

	if (commandName == "setSkyCulture")
	{
		StelSkyCultureMgr* skyCultureMgr = GETSTELMODULE(StelSkyCultureMgr);
		if (!skyCultureMgr) { result["error"] = "sky culture manager not found"; return result; }
		bool ok = skyCultureMgr->setCurrentSkyCultureNameI18(arg.trimmed());
		result["ok"] = ok;
		result["culture"] = arg.trimmed();
		return result;
	}

		if (commandName == "selectAt")
		{
			if (!objectMgr || !core)
			{
				result["error"] = "selection manager not ready";
				return result;
			}
			const QStringList parts = arg.split('|');
			if (parts.size() < 2)
			{
				result["error"] = "selectAt expects x|y or x|y|height";
				return result;
			}
			bool okX = false;
			bool okY = false;
			const int x = parts[0].toInt(&okX);
			const int y = parts[1].toInt(&okY);
			bool okW = false, okH = false;
			int skyW = 1440, skyH = 960;
			if (parts.size() >= 4)
			{
				skyW = parts[2].toInt(&okW);
				skyH = parts[3].toInt(&okH);
			}
			bool found = false;

		if (okX && okY)
		{
			const StelProjectorP prj = core->getProjection(StelCore::FrameJ2000);
			const Vec4i vp = prj->getViewport();
			const double scaleX = (okW && skyW > 0) ? (double)vp[2] / (double)skyW : (double)vp[2] / 1440.0;
			const double scaleY = (okH && skyH > 0) ? (double)vp[3] / (double)skyH : (double)vp[3] / 960.0;
			const int sx = qRound(x * scaleX);
			// Touch Y comes from top-left (screen); Stellarium's projector unProject expects
			// Y from bottom-left (GL convention). Desktop path flips via (height-1-y); do the same
			// here, otherwise taps in the top half select objects in the bottom half and vice versa.
			const int syTop = qRound(y * scaleY);
			const int sy = vp[3] - 1 - syTop;
			qInfo() << "[StellariumOhos][selectAt] tap" << x << y << "sky" << skyW << skyH
					<< "viewport" << vp[2] << vp[3] << "->stel" << sx << sy;
			OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "StellariumCpp",
						 "selectAt tapX=%{public}d tapY=%{public}d skyW=%{public}d skyH=%{public}d vpW=%{public}d vpH=%{public}d sx=%{public}d syTop=%{public}d syGL=%{public}d",
						 x, y, skyW, skyH, vp[2], vp[3], sx, syTop, sy);
			found = objectMgr->findAndSelect(core, sx, sy);
			qInfo() << "[StellariumOhos][selectAt] found" << found;
			OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "StellariumCpp",
						 "selectAt found=%{public}d", found ? 1 : 0);
		}

		markOhosInteraction();
		result = selectedObjectJson(core);
		result["ok"] = true;
		result["found"] = found;
		result["tapX"] = x;
		result["tapY"] = y;
		return result;
		}

		if (commandName == "dragView")
		{
			const QStringList parts = arg.split('|');
			if (parts.size() != 4)
			{
				result["error"] = "dragView expects x1|y1|x2|y2";
				return result;
			}
			bool okX1 = false;
			bool okY1 = false;
			bool okX2 = false;
			bool okY2 = false;
			const int x1 = parts[0].toInt(&okX1);
			const int y1 = parts[1].toInt(&okY1);
			const int x2 = parts[2].toInt(&okX2);
			const int y2 = parts[3].toInt(&okY2);
			if (!okX1 || !okY1 || !okX2 || !okY2)
			{
				result["error"] = "invalid dragView payload";
				return result;
			}
			movementMgr->dragView(x1, y1, x2, y2);
			markOhosInteraction();
			result["ok"] = true;
			result["fov"] = movementMgr->getCurrentFov();
			return result;
		}

		if (commandName == "panBy")
		{
			if (!movementMgr)
			{
				result["error"] = "movement manager not ready";
				return result;
			}
			const QStringList parts = arg.split('|');
			if (parts.size() != 4)
			{
				result["error"] = "panBy expects dx|dy|width|height";
				return result;
			}
			bool okDx = false;
			bool okDy = false;
			bool okWidth = false;
			bool okHeight = false;
			const double dx = parts[0].toDouble(&okDx);
			const double dy = parts[1].toDouble(&okDy);
			const double width = parts[2].toDouble(&okWidth);
			const double height = parts[3].toDouble(&okHeight);
			if (!okDx || !okDy || !okWidth || !okHeight || width <= 0.0 || height <= 0.0)
			{
				result["error"] = "invalid panBy payload";
				return result;
			}
			const double fovRad = movementMgr->getCurrentFov() * M_PI / 180.0;
			movementMgr->panView(-dx / width * fovRad, dy / height * fovRad);
			movementMgr->setFlagTracking(false);
			markOhosInteraction();
			result["ok"] = true;
			result["fov"] = movementMgr->getCurrentFov();
			return result;
		}

		if (commandName == "zoomBy")
		{
			if (!movementMgr)
			{
				result["error"] = "movement manager not ready";
				return result;
			}
			const QStringList parts = arg.split('|');
			bool okScale = false;
			const double scale = parts.value(0).toDouble(&okScale);
			const bool started = parts.value(1) == "1" || parts.value(1).toLower() == "true";
			if (!okScale || scale <= 0.0)
			{
				result["error"] = "invalid zoom scale";
				return result;
			}
			movementMgr->handlePinch(scale, started);
			markOhosInteraction();
			result["ok"] = true;
			result["fov"] = movementMgr->getCurrentFov();
			return result;
		}

		if (commandName == "getSelectedObjectInfo")
			return selectedObjectJson(core);

		if (commandName == "moveToSelected")
		{
			if (objectMgr && movementMgr && !objectMgr->getSelectedObject().isEmpty())
			{
				movementMgr->moveToObject(objectMgr->getSelectedObject().constFirst(), movementMgr->getAutoMoveDuration());
				movementMgr->setFlagTracking(true);
				result = selectedObjectJson(core);
				result["ok"] = true;
				markOhosInteraction();
				return result;
			}
			result["error"] = "no selected object";
			return result;
		}

		if (commandName == "setTracking")
		{
			if (!movementMgr)
			{
				result["error"] = "movement manager not ready";
				return result;
			}
			const bool enabled = arg == "1" || arg.toLower() == "true";
			movementMgr->setFlagTracking(enabled);
			markOhosInteraction();
			result = currentStateJson();
			return result;
		}

		if (commandName == "setLocation")
		{
			if (!core)
			{
				result["error"] = "core not ready";
				return result;
			}
			const QStringList parts = arg.split('|');
			if (parts.size() < 4)
			{
				result["error"] = "setLocation expects name|lat|lon|alt";
				return result;
			}
			bool okLat = false;
			bool okLon = false;
			bool okAlt = false;
			const double lat = parts[1].toDouble(&okLat);
			const double lon = parts[2].toDouble(&okLon);
			const int alt = parts[3].toInt(&okAlt);
			if (!okLat || !okLon || !okAlt)
			{
				result["error"] = "invalid location payload";
				return result;
			}

			StelLocation location;
			location.name = parts[0].trimmed().isEmpty() ? QStringLiteral("Custom") : parts[0].trimmed();
			location.region = QStringLiteral("User");
			location.planetName = QStringLiteral("Earth");
			location.setLatitude(static_cast<float>(lat));
			location.setLongitude(static_cast<float>(lon));
			location.altitude = alt;
			location.role = QChar('X');
			location.ianaTimeZone = QStringLiteral("system_default");
			core->moveObserverTo(location, 0.0, 0.0);
			markOhosInteraction();
			result = currentStateJson();
			return result;
		}

		if (commandName == "setTimeRate")
		{
			if (!core)
			{
				result["error"] = "core not ready";
				return result;
			}
			bool okRate = false;
			const double rate = arg.toDouble(&okRate);
			if (!okRate)
			{
				result["error"] = "invalid time rate";
				return result;
			}
			core->setTimeRate(rate);
			markOhosInteraction();
			result["ok"] = true;
			result["timeRate"] = core->getTimeRate();
			return result;
		}

		if (commandName == "advanceTime")
		{
			if (!core)
			{
				result["error"] = "core not ready";
				return result;
			}
			bool okH = false;
			const double hours = arg.toDouble(&okH);
			if (!okH)
			{
				result["error"] = "advanceTime expects hours";
				return result;
			}
			core->setJD(core->getJD() + hours / 24.0);
			markOhosInteraction();
			result["ok"] = true;
			result["jd"] = core->getJD();
			return result;
		}

		if (commandName == "setJD")
		{
			if (!core)
			{
				result["error"] = "core not ready";
				return result;
			}
			bool okJD = false;
			const double jd = arg.toDouble(&okJD);
			if (!okJD)
			{
				result["error"] = "setJD expects a Julian Day number";
				return result;
			}
			core->setJD(jd);
			markOhosInteraction();
			result["ok"] = true;
			result["jd"] = core->getJD();
			return result;
		}

		if (commandName == "setLanguage")
		{
			StelLocaleMgr& localeMgr = StelApp::getInstance().getLocaleMgr();
			localeMgr.setAppLanguage(arg);
			markOhosInteraction();
			result["ok"] = true;
			result["appLanguage"] = localeMgr.getAppLanguage();
			result["skyLanguage"] = localeMgr.getSkyLanguage();
			return result;
		}

		if (commandName == "zoomStep")
		{
			if (!movementMgr)
			{
				result["error"] = "movement manager not ready";
				return result;
			}
			bool okF = false;
			const double factor = arg.toDouble(&okF);
			if (!okF || factor <= 0.0)
			{
				result["error"] = "zoomStep expects positive factor";
				return result;
			}
			double aim = movementMgr->getCurrentFov() * factor;
			if (aim < 0.001) aim = 0.001;
			if (aim > 360.0) aim = 360.0;
			movementMgr->zoomTo(aim, 0.4f);
			markOhosInteraction();
			result["ok"] = true;
			result["fov"] = aim;
			return result;
		}

		if (commandName == "getState")
			return currentStateJson();

		if (commandName == "telescopeLx200GotoSelected")
			return lx200GotoSelected(arg, false);

		if (commandName == "telescopeLx200SyncSelected")
			return lx200GotoSelected(arg, true);

		if (commandName == "telescopeLx200Abort")
		{
			const QStringList parts = arg.split('|');
			if (parts.size() < 2)
			{
				result["error"] = "expects host|port";
				return result;
			}
			bool okPort = false;
			const QString host = parts[0].trimmed();
			const int portInt = parts[1].toInt(&okPort);
			if (host.isEmpty() || !okPort || portInt <= 0 || portInt > 65535)
			{
				result["error"] = "invalid LX200 endpoint";
				return result;
			}
			return sendLx200Commands(host, quint16(portInt), {"#:Q#"});
		}

		// ========== Phase 2: New bridge commands ==========

		// getLandscapeList
		if (commandName == "getLandscapeList")
		{
			LandscapeMgr* lmgr = GETSTELMODULE(LandscapeMgr);
			QStringList ids = lmgr->getAllLandscapeIDs();
			QStringList names = lmgr->getAllLandscapeNames();
			QJsonArray items;
			for (int i = 0; i < ids.size(); ++i)
			{
				QJsonObject item;
				item["id"] = ids[i];
				item["name"] = (i < names.size()) ? names[i] : ids[i];
				items.append(item);
			}
			result["ok"] = true;
			result["items"] = items;
			result["current"] = lmgr->getCurrentLandscapeID();
			return result;
		}

		// setLandscape
		if (commandName == "setLandscape")
		{
			LandscapeMgr* lmgr = GETSTELMODULE(LandscapeMgr);
			bool ok = lmgr->setCurrentLandscapeID(arg);
			result["ok"] = ok;
			result["current"] = lmgr->getCurrentLandscapeID();
			return result;
		}

		// setLandscapeTransparency
		if (commandName == "setLandscapeTransparency")
		{
			LandscapeMgr* lmgr = GETSTELMODULE(LandscapeMgr);
			bool convOk = false;
			double val = arg.toDouble(&convOk);
			if (convOk && val >= 0.0 && val <= 1.0)
			{
				lmgr->setLandscapeTransparency(val);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "expects 0.0..1.0";
			}
			return result;
		}

		// getScriptList
		if (commandName == "getScriptList")
		{
			StelScriptMgr* smgr = StelApp::getInstance().getScriptMgr();
			QStringList scripts = smgr->getScriptList();
			QJsonArray items;
			for (const QString& s : scripts)
			{
				items.append(s);
			}
			result["ok"] = true;
			result["items"] = items;
			return result;
		}

		// playScript
		if (commandName == "playScript")
		{
			StelScriptMgr* smgr = StelApp::getInstance().getScriptMgr();
			smgr->playScript(arg);
			result["ok"] = true;
			return result;
		}

		// stopScript
		if (commandName == "stopScript")
		{
			StelApp::getInstance().getScriptMgr()->stopScript();
			result["ok"] = true;
			return result;
		}

		// pauseScript
		if (commandName == "pauseScript")
		{
			StelApp::getInstance().getScriptMgr()->pauseScript();
			result["ok"] = true;
			return result;
		}

		// resumeScript
		if (commandName == "resumeScript")
		{
			StelApp::getInstance().getScriptMgr()->resumeScript();
			result["ok"] = true;
			return result;
		}

		// getLoadedModuleNames
		if (commandName == "getLoadedModuleNames")
		{
			const QList<StelModule*> modules = StelApp::getInstance().getModuleMgr().getAllModules();
			QJsonArray items;
			for (const StelModule* m : modules)
			{
				items.append(m->objectName());
			}
			result["ok"] = true;
			result["items"] = items;
			return result;
		}

		// getRTS — Rise/Transit/Set for selected object
		if (commandName == "getRTS")
		{
			StelObjectMgr* omgr = GETSTELMODULE(StelObjectMgr);
			const QList<StelObjectP> sel = omgr->getSelectedObject();
			if (sel.isEmpty())
			{
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			const StelCore* core = StelApp::getInstance().getCore();
			QString name = sel[0]->getNameI18n();
			double nextRise = sel[0]->getNextRise(core->getJD());
			double nextTransit = sel[0]->getNextTransit(core->getJD());
			double nextSet = sel[0]->getNextSet(core->getJD());
			QJsonObject rts;
			rts["name"] = name;
			rts["nextRiseJD"] = nextRise;
			rts["nextTransitJD"] = nextTransit;
			rts["nextSetJD"] = nextSet;
			rts["currentJD"] = core->getJD();
			result["ok"] = true;
			result["rts"] = rts;
			return result;
		}

		// getAlmanac — sun/moon rise/set/transit
		if (commandName == "getAlmanac")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			PlanetP sun = ssys->getSun();
			PlanetP moon = ssys->getMoon();
			QJsonObject alm;
			alm["currentJD"] = core->getJD();
			if (sun)
			{
				alm["sunNextRise"] = sun->getNextRise(core->getJD());
				alm["sunNextSet"] = sun->getNextSet(core->getJD());
				alm["sunNextTransit"] = sun->getNextTransit(core->getJD());
			}
			if (moon)
			{
				alm["moonNextRise"] = moon->getNextRise(core->getJD());
				alm["moonNextSet"] = moon->getNextSet(core->getJD());
				alm["moonNextTransit"] = moon->getNextTransit(core->getJD());
				alm["moonPhase"] = moon->getPhase(core->getJD());
			}
			result["ok"] = true;
			result["almanac"] = alm;
			return result;
		}

		// getObjectPositions — all planet positions
		if (commandName == "getObjectPositions")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			QStringList planetNames = ssys->getAllPlanetEnglishNames();
			QJsonArray items;
			for (const QString& pn : planetNames)
			{
				PlanetP p = ssys->searchByName(pn);
				if (!p) continue;
				QJsonObject obj;
				Vec3d altaz = core->altAzFromEquatorial(p->getEquinoxEquatorialPos(core->getJD()), core->getJD());
				obj["name"] = p->getNameI18n();
				obj["englishName"] = p->getEnglishName();
				Vec3d eq = p->getEquinoxEquatorialPos(core->getJD());
				obj["ra"] = StelUtils::radToHmsStr(eq[0]/M_PI*12.0);
				obj["dec"] = StelUtils::radToDmsStr(eq[1]/M_PI*180.0);
				obj["altitude"] = altaz[2] * 180.0 / M_PI;
				obj["azimuth"] = std::fmod(altaz[0] * 180.0 / M_PI + 360.0, 360.0);
				obj["magnitude"] = p->getVMagnitude(core->getJD());
				items.append(obj);
			}
			result["ok"] = true;
			result["items"] = items;
			return result;
		}

				// ========== Phase 2b ==========
		// getSkyCultureList
		if (commandName == "getSkyCultureList")
		{
			QStringList ids = StelApp::getInstance().getSkyCultureMgr().getSkyCultureListIDs();
			QStringList names = StelApp::getInstance().getSkyCultureMgr().getSkyCultureListI18();
			QString current = StelApp::getInstance().getSkyCultureMgr().getCurrentSkyCultureID();
			QJsonArray items;
			for (int i = 0; i < ids.size(); i++)
			{
				QJsonObject obj;
				obj["id"] = ids[i];
				obj["name"] = names[i];
				items.append(obj);
			}
			result["ok"] = true;
			result["items"] = items;
			result["current"] = current;
			return result;
		}

		// setSkyCulture
		if (commandName == "setSkyCulture")
		{
			QString id = arg.trimmed();
			bool ok = StelApp::getInstance().getSkyCultureMgr().setCurrentSkyCultureID(id);
			result["ok"] = ok;
			if (!ok) result["error"] = "failed to set sky culture: " + id;
			return result;
		}

		// getPluginList — list all available plugins with loaded status
		if (commandName == "getPluginList")
		{
			QList<StelModuleMgr::PluginDescriptor> plugins = StelApp::getInstance().getModuleMgr().getPluginsList();
			QJsonArray items;
			for (const auto& pd : plugins)
			{
				QJsonObject obj;
				obj["id"] = pd.info.id;
				obj["name"] = pd.info.displayedName;
				obj["loaded"] = pd.loaded;
				obj["loadAtStartup"] = pd.loadAtStartup;
				items.append(obj);
			}
			result["ok"] = true;
			result["items"] = items;
			return result;
		}

		// loadPlugin / unloadPlugin
		if (commandName == "loadPlugin")
		{
			QString pname = arg.trimmed();
			bool ok = StelApp::getInstance().getModuleMgr().loadPlugin(pname) != nullptr;
			result["ok"] = ok;
			if (!ok) result["error"] = "failed to load plugin: " + pname;
			return result;
		}
		if (commandName == "unloadPlugin")
		{
			QString pname = arg.trimmed();
			StelApp::getInstance().getModuleMgr().unloadModule(pname);
			result["ok"] = true;
			return result;
		}

		// getConfigString / setConfigString — read/write Stellarium config
		if (commandName == "getConfigString")
		{
			QString key = arg.trimmed();
			QString val = StelApp::getInstance().getSettings()->value(key).toString();
			result["ok"] = true;
			result["value"] = val;
			return result;
		}
		if (commandName == "setConfigString")
		{
			QStringList parts = arg.split("=", Qt::SkipEmptyParts);
			if (parts.size() >= 2)
			{
				QString key = parts[0].trimmed();
				QString val = parts.mid(1).join("=").trimmed();
				StelApp::getInstance().getSettings()->setValue(key, val);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "format: key=value";
			}
			return result;
		}

				// ========== Phase 2c ==========
		// getObjectInfo — get detailed info for currently selected object
		if (commandName == "getObjectInfo")
		{
			QJsonObject info;
			const QList<StelObjectP>& sel = StelApp::getInstance().getCore()->getSelectedObject();
			if (sel.empty()) {
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			const StelObjectP& obj = sel[0];
			Vec3d altaz = obj->getAltAzPosApparent(StelApp::getInstance().getCore());
			Vec3d radec = obj->getEquinoxEquatorialPos(StelApp::getInstance().getCore());
			info["name"] = obj->getEnglishName();
			info["nameI18"] = obj->getNameI18n();
			info["type"] = obj->getType();
			info["ra"] = radec[0] * 180.0 / M_PI;
			info["dec"] = radec[1] * 180.0 / M_PI;
			info["alt"] = altaz[1] * 180.0 / M_PI;
			info["az"] = altaz[0] * 180.0 / M_PI;
			info["magnitude"] = obj->getVMagnitude(StelApp::getInstance().getCore());
			QString magStr;
			if (obj->getExtraInfo("mag")) {
				magStr = obj->getExtraInfo("mag");
			} else {
				magStr = QString::number(obj->getVMagnitude(StelApp::getInstance().getCore()), 'f', 2);
			}
			info["magStr"] = magStr;
			result["ok"] = true;
			result["info"] = info;
			return result;
		}

		// getConstellationInfo — get current constellation at center
		if (commandName == "getConstellationInfo")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			Vec3d center = core->getJ2000EquatorialRectToAltAz(core->getEquinoxEquatorialRect(core->getAltAzToEquinoxEquatorial(Vec3d(0,0,1))));
			QString constellation = core->getConstellationMgr().getConstellationName(center, core);
			result["ok"] = true;
			result["name"] = constellation;
			return result;
		}

		// getStarCount — number of visible stars by magnitude
		if (commandName == "getStarCount")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			QJsonObject counts;
			counts["visible"] = core->getStarMgr().getVisibleStarCount();
			result["ok"] = true;
			result["counts"] = counts;
			return result;
		}

				// ========== Phase 2d ==========
		// getDSOCounts — count visible DSO objects by type
		if (commandName == "getDSOCounts")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			const NebulaMgr* nm = &core->getNebulaMgr();
			QJsonObject counts;
			// Count all DSO currently displayed
			const QList<StelObjectP>& allDSO = nm->searchAround(core->getAltAzToEquinoxEquatorial(Vec3d(0,0,1)), 180.0, core);
			int total = 0;
			int galaxies = 0, clusters = 0, nebulae = 0, other = 0;
			for (const auto& obj : allDSO) {
				total++;
				QString type = obj->getType();
				if (type.contains("galaxy") || type.contains("Galaxy")) galaxies++;
				else if (type.contains("cluster") || type.contains("Cluster") || type.contains("open") || type.contains("globular")) clusters++;
				else if (type.contains("nebula") || type.contains("Nebula") || type.contains("diffuse") || type.contains("planetary")) nebulae++;
				else other++;
			}
			counts["total"] = total;
			counts["galaxies"] = galaxies;
			counts["clusters"] = clusters;
			counts["nebulae"] = nebulae;
			counts["other"] = other;
			counts["typeFilter"] = nm->getTypeFilters();
			result["ok"] = true;
			result["counts"] = counts;
			return result;
		}

		// setTimeToJD — set simulation time to Julian Day
		if (commandName == "setTimeToJD")
		{
			double jd = param.toDouble();
			StelCore* core = StelApp::getInstance().getCore();
			core->setJD(jd);
			core->setTimeRate(0.0);
			result["ok"] = true;
			result["jd"] = jd;
			return result;
		}

		// getSimulationTime — get current JD and time rate
		if (commandName == "getSimulationTime")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			result["ok"] = true;
			result["jd"] = core->getJD();
			result["jdOfToday"] = core->getJDOfToday();
			result["timeRate"] = core->getTimeRate();
			return result;
		}

				// ========== Phase 2e ==========
		// setLocationByName — move observer to a named location
		if (commandName == "setLocationByName")
		{
			StelCore* core = StelApp::getInstance().getCore();
			StelLocationMgr& locMgr = core->getLocationMgr();
			StelLocation loc = locMgr.locationForName(param);
			if (loc.isValid()) {
				core->moveObserverTo(loc);
				result["ok"] = true;
				result["name"] = loc.name;
				result["latitude"] = loc.getLatitude();
				result["longitude"] = loc.getLongitude();
				result["altitude"] = loc.altitude;
			} else {
				result["ok"] = false;
				result["error"] = "location not found: " + param;
			}
			return result;
		}

		// setLocationCoords — move observer to lat/lon/alt
		if (commandName == "setLocationCoords")
		{
			QStringList parts = param.split(",");
			if (parts.size() >= 2) {
				double lat = parts[0].toDouble();
				double lon = parts[1].toDouble();
				double alt = parts.size() >= 3 ? parts[2].toDouble() : 0.0;
				StelCore* core = StelApp::getInstance().getCore();
				StelLocation loc;
				loc.latitude = lat;
				loc.longitude = lon;
				loc.altitude = alt;
				loc.name = QString("Custom %1,%2").arg(lat).arg(lon);
				core->moveObserverTo(loc);
				result["ok"] = true;
				result["latitude"] = lat;
				result["longitude"] = lon;
				result["altitude"] = alt;
			} else {
				result["ok"] = false;
				result["error"] = "expected lat,lon[,alt]";
			}
			return result;
		}

		// getSelectedObjectInfo — full info for selected object (alias for existing)
		if (commandName == "getSelectedType")
		{
			const QList<StelObjectP>& sel = StelApp::getInstance().getCore()->getSelectedObject();
			if (sel.empty()) {
				result["ok"] = false;
				result["error"] = "no selection";
				return result;
			}
			result["ok"] = true;
			result["type"] = sel[0]->getType();
			result["englishName"] = sel[0]->getEnglishName();
			result["nameI18"] = sel[0]->getNameI18n();
			return result;
		}

				// ========== Phase 2f ==========
		// getFieldOfView — get current FOV and projection info
		if (commandName == "getFieldOfView")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			double fov = core->getMovementMgr()->getCurrentFov();
			result["ok"] = true;
			result["fov"] = fov * 180.0 / M_PI;
			// Direction the center of view is looking at
			Vec3d dir = core->getMovementMgr()->getViewDirection();
			dir.normalize();
			double alt = std::asin(dir[2]) * 180.0 / M_PI;
			double az = std::atan2(dir[0], dir[1]) * 180.0 / M_PI;
			result["centerAlt"] = alt;
			result["centerAz"] = az;
			return result;
		}

		// setFieldOfView — set FOV in degrees
		if (commandName == "setFieldOfView")
		{
			double fov = param.toDouble();
			if (fov >= 0.1 && fov <= 360.0) {
				StelApp::getInstance().getCore()->getMovementMgr()->zoomTo(fov * M_PI / 180.0, 0.3);
				result["ok"] = true;
				result["fov"] = fov;
			} else {
				result["ok"] = false;
				result["error"] = "FOV must be between 0.1 and 360 degrees";
			}
			return result;
		}

		// getConstellationList — get all visible constellation names
		if (commandName == "getConstellationList")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			QStringList names = core->getConstellationMgr().getConstellationsEnglishNames();
			QJsonArray list;
			for (const QString& name : names) {
				list.append(name);
			}
			result["ok"] = true;
			result["constellations"] = list;
			result["total"] = names.size();
			return result;
		}

				// ========== Phase 2g ==========
		// getPlanetPositions — get all solar system planet positions
		if (commandName == "getPlanetPositions")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			const SolarSystem* ss = GETSTELMODULE(SolarSystem);
			QStringList planetNames = QStringList()
				<< "Sun" << "Moon" << "Mercury" << "Venus" << "Earth" << "Mars"
				<< "Jupiter" << "Saturn" << "Uranus" << "Neptune" << "Pluto";
			QJsonArray planets;
			for (const QString& name : planetNames) {
				StelObjectP obj = ss->searchByName(name);
				if (obj) {
					QJsonObject p;
					Vec3d pos = obj->getJ2000EquatorialPos(core);
					double ra = std::atan2(pos[1], pos[0]) * 180.0 / M_PI;
					double dec = std::asin(pos[2] / pos.length()) * 180.0 / M_PI;
					double mag = obj->getVMagnitude(core);
					double dist = obj->getDistance() / AU;
					Vec3d altaz;
					core->getHEMatrix(StelCore::FrameAltAz).multiply(pos, altaz);
					double alt = std::asin(altaz[2] / altaz.length()) * 180.0 / M_PI;
					double az = std::atan2(altaz[0], altaz[1]) * 180.0 / M_PI;
					p["name"] = name;
					p["ra"] = (ra < 0) ? ra + 360 : ra;
					p["dec"] = dec;
					p["magnitude"] = mag;
					p["distanceAU"] = dist;
					p["altitude"] = alt;
					p["azimuth"] = (az < 0) ? az + 360 : az;
					planets.append(p);
				}
			}
			result["ok"] = true;
			result["planets"] = planets;
			return result;
		}

		// getSkyCultureList — get available sky cultures
		if (commandName == "getSkyCultureList")
		{
			QStringList cultures = StelApp::getInstance().getSkyCultureMgr().getSkyCultureList();
			QStringList displayNames;
			for (const QString& id : cultures) {
				displayNames.append(StelApp::getInstance().getSkyCultureMgr().getSkyCultureNameEnglish(id));
			}
			QJsonArray list;
			for (int i = 0; i < cultures.size(); i++) {
				QJsonObject item;
				item["id"] = cultures[i];
				item["name"] = displayNames[i];
				list.append(item);
			}
			result["ok"] = true;
			result["skyCultures"] = list;
			result["current"] = StelApp::getInstance().getSkyCultureMgr().getCurrentSkyCultureID();
			return result;
		}

				// ========== Phase 2h ==========
		// getProjectionList — get all available projection types
		if (commandName == "getProjectionList")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			QStringList keys = core->getAllProjectionTypeKeys();
			QJsonArray list;
			for (const QString& key : keys) {
				QJsonObject item;
				item["key"] = key;
				item["name"] = core->projectionTypeKeyToNameI18n(key);
				list.append(item);
			}
			result["ok"] = true;
			result["projections"] = list;
			result["current"] = core->getCurrentProjectionTypeKey();
			return result;
		}

		// setProjectionType — change sky projection
		if (commandName == "setProjectionType")
		{
			QString key = payload;
			StelCore* core = StelApp::getInstance().getCore();
			QStringList validKeys = core->getAllProjectionTypeKeys();
			if (validKeys.contains(key)) {
				core->setCurrentProjectionTypeKey(key);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "unknown projection type: " + key;
			}
			return result;
		}

		// getDateFormat / setDateFormat — date display format
		if (commandName == "getDateFormat")
		{
			QSettings* conf = StelApp::getInstance().getSettings();
			result["ok"] = true;
			result["format"] = conf->value("localization/date_display_format", "yyyymmdd").toString();
			return result;
		}

		if (commandName == "setDateFormat")
		{
			QSettings* conf = StelApp::getInstance().getSettings();
			conf->setValue("localization/date_display_format", payload);
			StelApp::getInstance().getLocaleMgr().setDateFormatForLanguage(StelApp::getInstance().getLocaleMgr().getAppLanguage(), payload);
			result["ok"] = true;
			return result;
		}

		// getTimeFormat / setTimeFormat — time display format
		if (commandName == "getTimeFormat")
		{
			QSettings* conf = StelApp::getInstance().getSettings();
			result["ok"] = true;
			result["format"] = conf->value("localization/time_display_format", "24h").toString();
			return result;
		}

		if (commandName == "setTimeFormat")
		{
			QSettings* conf = StelApp::getInstance().getSettings();
			conf->setValue("localization/time_display_format", payload);
			StelApp::getInstance().getLocaleMgr().setTimeFormatForLanguage(StelApp::getInstance().getLocaleMgr().getAppLanguage(), payload);
			result["ok"] = true;
			return result;
		}

				// ========== Phase 2i ==========
		// getFPS — get current rendering frame rate
		if (commandName == "getFPS")
		{
			result["ok"] = true;
			result["fps"] = StelApp::getInstance().getFps();
			return result;
		}

		// getDitheringMode / setDitheringMode — control color dithering
		if (commandName == "getDitheringMode")
		{
			StelCore* core = StelApp::getInstance().getCore();
			DitheringMode mode = core->getDitheringMode();
			QString modeName;
			switch (mode) {
				case DitheringMode::Disabled: modeName = "Disabled"; break;
				case DitheringMode::Color565: modeName = "Color565"; break;
				case DitheringMode::Color666: modeName = "Color666"; break;
				case DitheringMode::Color888: modeName = "Color888"; break;
				default: modeName = "Color888"; break;
			}
			result["ok"] = true;
			result["mode"] = modeName;
			return result;
		}

		if (commandName == "setDitheringMode")
		{
			StelCore* core = StelApp::getInstance().getCore();
			core->setDitheringMode(payload);
			result["ok"] = true;
			return result;
		}

		// getLightPollution / setLightPollution — sky brightness / light pollution
		if (commandName == "getLightPollution")
		{
			StelSkyDrawer* drawer = StelApp::getInstance().getCore()->getSkyDrawer();
			double lum = drawer->getLightPollutionLuminance();
			result["ok"] = true;
			result["luminance"] = lum;
			result["bortleScale"] = StelCore::luminanceToBortleScaleIndex(static_cast<float>(lum));
			result["mpsas"] = StelCore::luminanceToMPSAS(static_cast<float>(lum));
			return result;
		}

		if (commandName == "setLightPollution")
		{
			StelSkyDrawer* drawer = StelApp::getInstance().getCore()->getSkyDrawer();
			bool ok;
			double lum = payload.toDouble(&ok);
			if (ok && lum >= 0.0) {
				drawer->setLightPollutionLuminance(lum);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "invalid luminance value";
			}
			return result;
		}

		// setBortleScale — set light pollution by Bortle scale index (1-9)
		if (commandName == "setBortleScale")
		{
			bool ok;
			int index = payload.toInt(&ok);
			if (ok && index >= 1 && index <= 9) {
				float lum = StelCore::bortleScaleIndexToLuminance(index);
				StelApp::getInstance().getCore()->getSkyDrawer()->setLightPollutionLuminance(lum);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "Bortle scale must be 1-9";
			}
			return result;
		}

		// getStarScale / setStarScale — relative star scale
		if (commandName == "getStarScale")
		{
			result["ok"] = true;
			result["scale"] = StelApp::getInstance().getCore()->getSkyDrawer()->getRelativeStarScale();
			return result;
		}

		if (commandName == "setStarScale")
		{
			bool ok;
			double scale = payload.toDouble(&ok);
			if (ok && scale > 0.0) {
				StelApp::getInstance().getCore()->getSkyDrawer()->setRelativeStarScale(scale);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "invalid scale";
			}
			return result;
		}

		// getAbsoluteStarScale / setAbsoluteStarScale
		if (commandName == "getAbsoluteStarScale")
		{
			result["ok"] = true;
			result["scale"] = StelApp::getInstance().getCore()->getSkyDrawer()->getAbsoluteStarScale();
			return result;
		}

		if (commandName == "setAbsoluteStarScale")
		{
			bool ok;
			double scale = payload.toDouble(&ok);
			if (ok && scale > 0.0) {
				StelApp::getInstance().getCore()->getSkyDrawer()->setAbsoluteStarScale(scale);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "invalid scale";
			}
			return result;
		}

				// ========== Phase 2j ==========
		// getScriptStatus — query current script execution state
		if (commandName == "getScriptStatus")
		{
			StelScriptMgr* sm = StelApp::getInstance().getScriptMgr();
			result["ok"] = true;
			result["running"] = sm->scriptIsRunning();
			result["scriptId"] = sm->runningScriptId();
			result["scriptRate"] = sm->getScriptRate();
			return result;
		}

		// getScriptRate / setScriptRate — script execution speed multiplier
		if (commandName == "getScriptRate")
		{
			result["ok"] = true;
			result["rate"] = StelApp::getInstance().getScriptMgr()->getScriptRate();
			return result;
		}

		if (commandName == "setScriptRate")
		{
			bool ok;
			double rate = payload.toDouble(&ok);
			if (ok && rate > 0.0) {
				StelApp::getInstance().getScriptMgr()->setScriptRate(rate);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "invalid rate";
			}
			return result;
		}

		// getSelectedObjects — list currently selected objects
		if (commandName == "getSelectedObjects")
		{
			const QList<StelObjectP>& sel = StelApp::getInstance().getStelObjectMgr()->getSelectedObject();
			QJsonArray list;
			for (const auto& obj : sel) {
				QJsonObject item;
				item["name"] = obj->getNameI18n();
				item["type"] = obj->getType();
				item["designation"] = obj->getEnglishName();
				list.append(item);
			}
			result["ok"] = true;
			result["objects"] = list;
			result["count"] = sel.size();
			return result;
		}

		// clearSelection — deselect all objects
		if (commandName == "clearSelection")
		{
			StelApp::getInstance().getStelObjectMgr()->unSelect();
			result["ok"] = true;
			return result;
		}

				// ========== Phase 2k ==========
		// getMountMode / setMountMode — equatorial vs alt-az mount
		if (commandName == "getMountMode")
		{
			StelMovementMgr* mvmgr = StelApp::getInstance().getCore()->getMovementMgr();
			QString modeName;
			switch (mvmgr->getMountMode()) {
				case StelMovementMgr::MountAltAzimuthal: modeName = "alt-az"; break;
				case StelMovementMgr::MountEquinoxEquatorial: modeName = "equatorial"; break;
				case StelMovementMgr::MountGalactic: modeName = "galactic"; break;
				case StelMovementMgr::MountSupergalactic: modeName = "supergalactic"; break;
				default: modeName = "alt-az"; break;
			}
			result["ok"] = true;
			result["mode"] = modeName;
			result["equatorial"] = mvmgr->getEquatorialMount();
			return result;
		}

		if (commandName == "setMountMode")
		{
			StelMovementMgr* mvmgr = StelApp::getInstance().getCore()->getMovementMgr();
			if (payload == "equatorial" || payload == "1") {
				mvmgr->setMountMode(StelMovementMgr::MountEquinoxEquatorial);
			} else if (payload == "galactic") {
				mvmgr->setMountMode(StelMovementMgr::MountGalactic);
			} else if (payload == "supergalactic") {
				mvmgr->setMountMode(StelMovementMgr::MountSupergalactic);
			} else {
				mvmgr->setMountMode(StelMovementMgr::MountAltAzimuthal);
			}
			result["ok"] = true;
			return result;
		}

		// moveToAltAz — point view to specific altitude/azimuth
		if (commandName == "moveToAltAz")
		{
			QStringList parts = payload.split('|');
			if (parts.size() >= 2) {
				bool ok1, ok2;
				double az = parts[0].toDouble(&ok1);
				double alt = parts[1].toDouble(&ok2);
				if (ok1 && ok2) {
					float duration = parts.size() > 2 ? parts[2].toFloat() : 1.0f;
					StelMovementMgr* mvmgr = StelApp::getInstance().getCore()->getMovementMgr();
					Vec3d aim;
					aim[0] = cos(alt * M_PI/180.) * cos(az * M_PI/180.);
					aim[1] = cos(alt * M_PI/180.) * sin(az * M_PI/180.);
					aim[2] = sin(alt * M_PI/180.);
					mvmgr->moveToAltAzi(aim, Vec3d(0., 0., 1.), duration);
					result["ok"] = true;
				} else {
					result["ok"] = false;
					result["error"] = "invalid az/alt";
				}
			} else {
				result["ok"] = false;
				result["error"] = "usage: az|alt[|duration]";
			}
			return result;
		}

		// getViewDirection — current view direction as alt/az
		if (commandName == "getViewDirection")
		{
			StelCore* core = StelApp::getInstance().getCore();
			Vec3d viewDir = core->getMovementMgr()->getViewDirectionJ2000();
			// Convert J2000 to alt/az
			Vec3d altAz = core->j2000ToAltAz(viewDir, StelCore::RefractionAuto);
			double az = atan2(altAz[1], altAz[0]) * 180. / M_PI;
			double alt = asin(altAz[2]) * 180. / M_PI;
			if (az < 0) az += 360.;
			result["ok"] = true;
			result["azimuth"] = az;
			result["altitude"] = alt;
			return result;
		}

		// getAutoMoveDuration / setAutoMoveDuration — animation speed
		if (commandName == "getAutoMoveDuration")
		{
			result["ok"] = true;
			result["duration"] = StelApp::getInstance().getCore()->getMovementMgr()->getAutoMoveDuration();
			return result;
		}

		if (commandName == "setAutoMoveDuration")
		{
			bool ok;
			float duration = payload.toFloat(&ok);
			if (ok && duration > 0.0f) {
				StelApp::getInstance().getCore()->getMovementMgr()->setAutoMoveDuration(duration);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "invalid duration";
			}
			return result;
		}

				// ========== Phase 2l ==========
		// getFlagGravityLabels / setFlagGravityLabels — gravity label mode
		if (commandName == "getFlagGravityLabels")
		{
			result["ok"] = true;
			result["enabled"] = StelApp::getInstance().getCore()->getFlagGravityLabels();
			return result;
		}

		if (commandName == "setFlagGravityLabels")
		{
			StelApp::getInstance().getCore()->setFlagGravityLabels(payload == "1" || payload == "true");
			result["ok"] = true;
			return result;
		}

		// getFlagClearSky / setFlagClearSky — clear sky mode
		if (commandName == "getFlagClearSky")
		{
			result["ok"] = true;
			result["enabled"] = StelApp::getInstance().getCore()->getFlagClearSky();
			return result;
		}

		if (commandName == "setFlagClearSky")
		{
			StelApp::getInstance().getCore()->setFlagClearSky(payload == "1" || payload == "true");
			result["ok"] = true;
			return result;
		}

		// getSkyCultureInfo — current sky culture details
		if (commandName == "getSkyCultureInfo")
		{
			StelSkyCultureMgr* scm = &StelApp::getInstance().getSkyCultureMgr();
			result["ok"] = true;
			result["id"] = scm->getCurrentSkyCultureID();
			result["name"] = scm->getCurrentSkyCultureNameI18();
			result["englishName"] = scm->getCurrentSkyCultureEnglishName();
			return result;
		}

		// getIsDaylight — whether sun is up (for adaptive UI)
		if (commandName == "getIsDaylight")
		{
			result["ok"] = true;
			result["brightDaylight"] = StelApp::getInstance().getCore()->isBrightDaylight();
			return result;
		}

		// getBasicInfo — app metadata
		if (commandName == "getBasicInfo")
		{
			result["ok"] = true;
			result["version"] = StelApp::getInstance().getApplicationVersion();
			result["dataDir"] = StelFileMgr::getUserDir();
			result["locale"] = StelApp::getInstance().getLocaleMgr().getAppLanguage();
			result["skyLanguage"] = StelApp::getInstance().getLocaleMgr().getSkyLanguage();
			result["jd"] = StelApp::getInstance().getCore()->getJD();
			StelLocation loc = StelApp::getInstance().getCore()->getCurrentLocation();
			result["location"] = loc.name;
			result["latitude"] = loc.latitude;
			result["longitude"] = loc.longitude;
			result["altitude"] = loc.altitude;
			result["planetName"] = loc.planetName;
			return result;
		}

				// ========== Phase 2m ==========
		// getDeltaT — current ΔT value (seconds)
		if (commandName == "getDeltaT")
		{
			StelCore* core = StelApp::getInstance().getCore();
			result["ok"] = true;
			result["deltaT"] = core->getDeltaT();
			result["jd"] = core->getJD();
			result["jde"] = core->getJDE();
			result["algorithm"] = core->getDeltaTAlgorithmDescription();
			return result;
		}

		// getLandscapeInfo — current landscape details
		if (commandName == "getLandscapeInfo")
		{
			const LandscapeMgr* lmgr = StelApp::getInstance().getLandscapeMgr();
			result["ok"] = true;
			result["id"] = lmgr->getCurrentLandscapeId();
			result["name"] = lmgr->getCurrentLandscapeName();
			result["author"] = lmgr->getCurrentLandscapeAuthor();
			result["description"] = lmgr->getCurrentLandscapeDescription();
			result["atmosphere"] = lmgr->getFlagAtmosphere();
			result["fog"] = lmgr->getFlagFog();
			result["ground"] = lmgr->getFlagLandscape();
			result["polyAngle"] = lmgr->getPolyAngle();
			result["transparency"] = lmgr->getLandscapeTransparency();
			return result;
		}

		// getDeltaTAlgorithmDescription — get deltaT algorithm name
		if (commandName == "getDeltaTAlgorithmDescription")
		{
			result["ok"] = true;
			result["description"] = StelApp::getInstance().getCore()->getDeltaTAlgorithmDescription();
			return result;
		}

		// getLandscapeCount — total number of available landscapes
		if (commandName == "getLandscapeCount")
		{
			result["ok"] = true;
			result["count"] = StelApp::getInstance().getLandscapeMgr()->getAllLandscapeCount();
			return result;
		}

		// getStarCount — total number of stars loaded
		if (commandName == "getStarCountFull")
		{
			result["ok"] = true;
			result["total"] = StelApp::getInstance().getCore()->getStarMgr()->getStarCount();
			return result;
		}

				// ========== Phase 2n ==========
		// getGridFlags — get all grid/line display flags
		if (commandName == "getGridFlags")
		{
			GridLinesMgr* gmgr = StelApp::getInstance().getCore()->getGridLinesMgr();
			QJsonObject flags;
			flags["azimuthalGrid"] = gmgr->getFlagAzimuthalGrid();
			flags["equatorGrid"] = gmgr->getFlagEquatorGrid();
			flags["eclipticGrid"] = gmgr->getFlagEclipticGrid();
			flags["equatorLine"] = gmgr->getFlagEquatorLine();
			flags["eclipticLine"] = gmgr->getFlagEclipticLine();
			flags["meridianLine"] = gmgr->getFlagMeridianLine();
			flags["horizonLine"] = gmgr->getFlagHorizonLine();
			flags["zenithNadir"] = gmgr->getFlagZenithNadir();
			flags["cardinalPoints"] = gmgr->getFlagCardinalPoints();
			result["ok"] = true;
			result["flags"] = flags;
			return result;
		}

		// setGridFlag — toggle a single grid/line display
		if (commandName == "setGridFlag")
		{
			QStringList parts = payload.split('|');
			if (parts.size() >= 2) {
				QString flagName = parts[0];
				bool state = parts[1] == "1" || parts[1] == "true";
				GridLinesMgr* gmgr = StelApp::getInstance().getCore()->getGridLinesMgr();
				if (flagName == "azimuthalGrid") gmgr->setFlagAzimuthalGrid(state);
				else if (flagName == "equatorGrid") gmgr->setFlagEquatorGrid(state);
				else if (flagName == "eclipticGrid") gmgr->setFlagEclipticGrid(state);
				else if (flagName == "equatorLine") gmgr->setFlagEquatorLine(state);
				else if (flagName == "eclipticLine") gmgr->setFlagEclipticLine(state);
				else if (flagName == "meridianLine") gmgr->setFlagMeridianLine(state);
				else if (flagName == "horizonLine") gmgr->setFlagHorizonLine(state);
				else if (flagName == "zenithNadir") gmgr->setFlagZenithNadir(state);
				else if (flagName == "cardinalPoints") gmgr->setFlagCardinalPoints(state);
				else {
					result["ok"] = false;
					result["error"] = "unknown grid flag: " + flagName;
					return result;
				}
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "usage: flagName|state";
			}
			return result;
		}

		// getFOV / setFOV — field of view in degrees
		if (commandName == "getFOV")
		{
			result["ok"] = true;
			result["fov"] = StelApp::getInstance().getCore()->getMovementMgr()->getCurrentFov();
			return result;
		}

		if (commandName == "setFOV")
		{
			bool ok;
			double fov = payload.toDouble(&ok);
			if (ok && fov > 0.0 && fov <= 360.0) {
				StelApp::getInstance().getCore()->getMovementMgr()->zoomTo(fov, 0.5f);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "invalid FOV (0-360)";
			}
			return result;
		}

		// getTracking / setTracking — auto-tracking state
		if (commandName == "getTracking")
		{
			result["ok"] = true;
			result["tracking"] = StelApp::getInstance().getCore()->getMovementMgr()->getFlagTracking();
			return result;
		}

		if (commandName == "setTracking")
		{
			StelApp::getInstance().getCore()->getMovementMgr()->setFlagTracking(payload == "1" || payload == "true");
			result["ok"] = true;
			return result;
		}

		// getAutoZoom / setAutoZoom — auto-zoom on selection
		if (commandName == "getAutoZoom")
		{
			result["ok"] = true;
			result["autoZoom"] = StelApp::getInstance().getCore()->getMovementMgr()->getFlagAutoZoom();
			return result;
		}

		if (commandName == "setAutoZoom")
		{
			StelApp::getInstance().getCore()->getMovementMgr()->setFlagAutoZoom(payload == "1" || payload == "true");
			result["ok"] = true;
			return result;
		}

				// ========== Phase 2o ==========
		// getLimitMagnitude / setLimitMagnitude — star visibility limit
		if (commandName == "getLimitMagnitude")
		{
			StelSkyDrawer* drawer = StelApp::getInstance().getCore()->getSkyDrawer();
			result["ok"] = true;
			result["limitMagnitude"] = drawer->getLimitMagnitude();
			result["customStarMagLimit"] = drawer->getCustomStarMagLimit();
			result["flagNebulaMagLimit"] = drawer->getFlagNebulaMagnitudeLimit();
			result["customNebulaMagLimit"] = drawer->getCustomNebulaMagnitudeLimit();
			return result;
		}

		if (commandName == "setLimitMagnitude")
		{
			bool ok;
			double mag = payload.toDouble(&ok);
			if (ok) {
				StelApp::getInstance().getCore()->getSkyDrawer()->setCustomStarMagLimit(mag);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "invalid magnitude";
			}
			return result;
		}

		// getMilkyWayIntensity / setMilkyWayIntensity
		if (commandName == "getMilkyWayIntensity")
		{
			result["ok"] = true;
			result["intensity"] = StelApp::getInstance().getCore()->getMilkyWay()->getIntensity();
			return result;
		}

		if (commandName == "setMilkyWayIntensity")
		{
			bool ok;
			double intensity = payload.toDouble(&ok);
			if (ok && intensity >= 0.0) {
				StelApp::getInstance().getCore()->getMilkyWay()->setIntensity(intensity);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "invalid intensity";
			}
			return result;
		}

		// getAtmosphereIntensity / setAtmosphereIntensity
		if (commandName == "getAtmosphereIntensity")
		{
			result["ok"] = true;
			result["intensity"] = StelApp::getInstance().getCore()->getSkyDrawer()->getAtmosphereFadeDuration();
			return result;
		}

		// getAppVersion — simple version string
		if (commandName == "getAppVersion")
		{
			result["ok"] = true;
			result["version"] = StelApp::getInstance().getApplicationVersion();
			result["qtVersion"] = QT_VERSION_STR;
			return result;
		}

				// ========== Phase 2p ==========
		// getConstellationFlags / setConstellationFlag — constellation display control
		if (commandName == "getConstellationFlags")
		{
			ConstellationMgr* cmgr = GETSTELMODULE(ConstellationMgr);
			QJsonObject flags;
			flags["lines"] = cmgr->getFlagLines();
			flags["boundaries"] = cmgr->getFlagBoundaries();
			flags["art"] = cmgr->getFlagArt();
			flags["labels"] = cmgr->getFlagLabels();
			flags["isolateSelected"] = cmgr->getFlagIsolateSelected();
			result["ok"] = true;
			result["flags"] = flags;
			return result;
		}

		if (commandName == "setConstellationFlag")
		{
			QStringList parts = payload.split('|');
			if (parts.size() >= 2) {
				QString flagName = parts[0];
				bool state = parts[1] == "1" || parts[1] == "true";
				ConstellationMgr* cmgr = GETSTELMODULE(ConstellationMgr);
				if (flagName == "lines") cmgr->setFlagLines(state);
				else if (flagName == "boundaries") cmgr->setFlagBoundaries(state);
				else if (flagName == "art") cmgr->setFlagArt(state);
				else if (flagName == "labels") cmgr->setFlagLabels(state);
				else if (flagName == "isolateSelected") cmgr->setFlagIsolateSelected(state);
				else {
					result["ok"] = false;
					result["error"] = "unknown constellation flag: " + flagName;
					return result;
				}
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "usage: flagName|state";
			}
			return result;
		}

		// getConstellationForPosition — get constellation name at a sky position
		if (commandName == "getConstellationForPosition")
		{
			QStringList parts = payload.split('|');
			if (parts.size() >= 2) {
				bool ok1, ok2;
				double ra = parts[0].toDouble(&ok1);
				double dec = parts[1].toDouble(&ok2);
				if (ok1 && ok2) {
					Vec3d pos;
					StelUtils::spheToRect(ra * M_PI/180., dec * M_PI/180., pos);
					QString cname = StelApp::getInstance().getCore()->getIAUConstellation(pos);
					result["ok"] = true;
					result["constellation"] = cname;
				} else {
					result["ok"] = false;
					result["error"] = "invalid ra/dec";
				}
			} else {
				result["ok"] = false;
				result["error"] = "usage: ra|dec";
			}
			return result;
		}

		// getCurrentViewInfo — comprehensive view state
		if (commandName == "getCurrentViewInfo")
		{
			StelCore* core = StelApp::getInstance().getCore();
			StelMovementMgr* mvmgr = core->getMovementMgr();
			result["ok"] = true;
			result["fov"] = mvmgr->getCurrentFov();
			result["tracking"] = mvmgr->getFlagTracking();
			result["autoZoom"] = mvmgr->getFlagAutoZoom();
			result["jd"] = core->getJD();
			result["timeRate"] = core->getTimeRate();
			result["projection"] = core->getCurrentProjectionTypeKey();
			result["location"] = core->getCurrentLocation().name;
			result["lat"] = core->getCurrentLocation().latitude;
			result["lon"] = core->getCurrentLocation().longitude;
			result["altitude"] = core->getCurrentLocation().altitude;
			return result;
		}

				// ========== Phase 2q ==========
		// getSolarSystemFlags / setSolarSystemFlag
		if (commandName == "getSolarSystemFlags")
		{
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			QJsonObject flags;
			flags["labels"] = ssys->getFlagLabels();
			flags["trails"] = ssys->getFlagTrails();
			flags["hints"] = ssys->getFlagHints();
			flags["pointer"] = ssys->getFlagPointer();
			flags["orbits"] = ssys->getFlagOrbits();
			flags["orbitsWithMoons"] = ssys->getFlagOrbitsWithMoons();
			result["ok"] = true;
			result["flags"] = flags;
			return result;
		}

		if (commandName == "setSolarSystemFlag")
		{
			QStringList parts = payload.split('|');
			if (parts.size() >= 2) {
				QString flagName = parts[0];
				bool state = parts[1] == "1" || parts[1] == "true";
				SolarSystem* ssys = GETSTELMODULE(SolarSystem);
				if (flagName == "labels") ssys->setFlagLabels(state);
				else if (flagName == "trails") ssys->setFlagTrails(state);
				else if (flagName == "hints") ssys->setFlagHints(state);
				else if (flagName == "pointer") ssys->setFlagPointer(state);
				else if (flagName == "orbits") ssys->setFlagOrbits(state);
				else if (flagName == "orbitsWithMoons") ssys->setFlagOrbitsWithMoons(state);
				else {
					result["ok"] = false;
					result["error"] = "unknown solar system flag: " + flagName;
					return result;
				}
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "usage: flagName|state";
			}
			return result;
		}

		// getNebulaFlags / setNebulaFlag
		if (commandName == "getNebulaFlags")
		{
			NebulaMgr* nbmgr = GETSTELMODULE(NebulaMgr);
			QJsonObject flags;
			flags["show"] = nbmgr->getFlagShow();
			flags["hints"] = nbmgr->getFlagHints();
			flags["typeFilters"] = nbmgr->getTypeFilters();
			flags["showOnlyNamed"] = nbmgr->getFlagShowOnlyNamedDSO();
			result["ok"] = true;
			result["flags"] = flags;
			return result;
		}

		if (commandName == "setNebulaFlag")
		{
			QStringList parts = payload.split('|');
			if (parts.size() >= 2) {
				QString flagName = parts[0];
				bool state = parts[1] == "1" || parts[1] == "true";
				NebulaMgr* nbmgr = GETSTELMODULE(NebulaMgr);
				if (flagName == "show") nbmgr->setFlagShow(state);
				else if (flagName == "hints") nbmgr->setFlagHints(state);
				else if (flagName == "showOnlyNamed") nbmgr->setFlagShowOnlyNamedDSO(state);
				else {
					result["ok"] = false;
					result["error"] = "unknown nebula flag: " + flagName;
					return result;
				}
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "usage: flagName|state";
			}
			return result;
		}

		// getMilkyWayFlags / setMilkyWayFlag
		if (commandName == "getMilkyWayFlags")
		{
			MilkyWay* mw = GETSTELMODULE(MilkyWay);
			QJsonObject flags;
			flags["show"] = mw->getFlagShow();
			flags["intensity"] = mw->getIntensity();
			result["ok"] = true;
			result["flags"] = flags;
			return result;
		}

		if (commandName == "setMilkyWayFlag")
		{
			QStringList parts = payload.split('|');
			if (parts.size() >= 2) {
				QString flagName = parts[0];
				bool state = parts[1] == "1" || parts[1] == "true";
				MilkyWay* mw = GETSTELMODULE(MilkyWay);
				if (flagName == "show") mw->setFlagShow(state);
				else {
					result["ok"] = false;
					result["error"] = "unknown milky way flag: " + flagName;
					return result;
				}
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "usage: flagName|state";
			}
			return result;
		}

				// ========== Phase 2r ==========
		// getRTS — get Rise/Transit/Set times for selected object
		if (commandName == "getRTS")
		{
			StelObjectMgr* objMgr = StelApp::getInstance().getStelObjectMgr();
			const QList<StelObjectP>& sel = objMgr->getSelectedObject();
			if (sel.isEmpty()) {
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			StelCore* core = StelApp::getInstance().getCore();
			Vec4d rts = sel.first()->getRTSTime(core);
			result["ok"] = true;
			result["riseJD"] = rts[0];
			result["transitJD"] = rts[1];
			result["setJD"] = rts[2];
			result["status"] = (int)rts[3];
			// Convert to local time strings
			if (rts[0] > 0) result["rise"] = StelUtils::julianDayToISO8601String(rts[0]);
			if (rts[1] > 0) result["transit"] = StelUtils::julianDayToISO8601String(rts[1]);
			if (rts[2] > 0) result["set"] = StelUtils::julianDayToISO8601String(rts[2]);
			return result;
		}

		// getVMagnitude — apparent V magnitude of selected object
		if (commandName == "getVMagnitude")
		{
			StelObjectMgr* objMgr = StelApp::getInstance().getStelObjectMgr();
			const QList<StelObjectP>& sel = objMgr->getSelectedObject();
			if (sel.isEmpty()) {
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			result["ok"] = true;
			result["vMagnitude"] = sel.first()->getVMagnitude(StelApp::getInstance().getCore());
			return result;
		}

		// getDistanceInfo — distance to selected object
		if (commandName == "getDistanceInfo")
		{
			StelObjectMgr* objMgr = StelApp::getInstance().getStelObjectMgr();
			const QList<StelObjectP>& sel = objMgr->getSelectedObject();
			if (sel.isEmpty()) {
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			result["ok"] = true;
			result["distance"] = sel.first()->getDistanceInfo();
			return result;
		}

		// getSolarElongation — solar elongation of selected object
		if (commandName == "getSolarElongation")
		{
			StelObjectMgr* objMgr = StelApp::getInstance().getStelObjectMgr();
			const QList<StelObjectP>& sel = objMgr->getSelectedObject();
			if (sel.isEmpty()) {
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			StelCore* core = StelApp::getInstance().getCore();
			Vec3d obsPos = core->getCurrentObserver()->getHeliocentricEclipticPos();
			Planet* planet = dynamic_cast<Planet*>(sel.first().data());
			if (planet) {
				result["ok"] = true;
				result["elongation"] = planet->getElongation(obsPos);
				result["phaseAngle"] = planet->getPhaseAngle(obsPos);
				result["phase"] = planet->getPhase(obsPos);
			} else {
				result["ok"] = false;
				result["error"] = "not a planet";
			}
			return result;
		}

		// ========== End Phase 2r ==========

		// ========== End Phase 2q ==========

		// ========== End Phase 2p ==========

		// ========== End Phase 2o ==========

		// ========== End Phase 2n ==========

		// ========== End Phase 2m ==========

		// ========== End Phase 2l ==========

		// ========== End Phase 2k ==========

		// ========== End Phase 2j ==========

		// ========== End Phase 2i ==========

		// ========== End Phase 2h ==========

		// ========== End Phase 2g ==========

		// ========== End Phase 2f ==========

		// ========== End Phase 2e ==========

		// ========== End Phase 2d ==========

		// ========== End Phase 2c ==========

		// ========== End Phase 2b ==========

		// ========== End Phase 2 ==========

		result["error"] = "unknown command";
		result["command"] = commandName;
		return result;
	});

	response = json.toUtf8();
	return response.constData();
}
#endif

class StelGLWidget : public QOpenGLWidget
{
public:
	StelGLWidget(const QSurfaceFormat& fmt, StelMainView* parent)
		:
		  QOpenGLWidget(parent),
		  parent(parent),
		  initialized(false)
	{
		qDebug()<<"StelGLWidget constructor";
		setFormat(fmt);

		//because we always draw the full background,
		//lets skip drawing the system background
		setAttribute(Qt::WA_OpaquePaintEvent);
		setAttribute(Qt::WA_AcceptTouchEvents);
		setAttribute(Qt::WA_TouchPadAcceptSingleTouchEvents);
#if defined(__OHOS__)
		setAttribute(Qt::WA_AlwaysStackOnTop);
		qInfo() << "Using always-on-top QOpenGLWidget on OpenHarmony.";
#endif
		setAutoFillBackground(false);
	}

	~StelGLWidget() override
	{
		qDebug()<<"StelGLWidget destroyed";
	}

	void initializeGL() override
	{
		if(initialized)
		{
			qWarning()<<"Double initialization, should not happen";
			Q_ASSERT(false);
			return;
		}

		//This seems to be the correct place to initialize all
		//GL related stuff of the application
		//this includes all the init() calls of the modules

		QOpenGLContext* ctx = context();
		Q_ASSERT(ctx == QOpenGLContext::currentContext());
		StelOpenGL::mainContext = ctx; //throw an error when StelOpenGL functions are executed in another context

		qDebug().nospace() << "initializeGL(windowWidth = " << width() << ", windowHeight = " << height() << ")";
		qInfo() << "OpenGL supported version: " << QString(reinterpret_cast<const char*>(ctx->functions()->glGetString(GL_VERSION)));
		qInfo() << "Current Format: " << this->format();

		if (qApp->property("onetime_opengl_compat").toBool())
		{
			// This may not return the version number set previously!
			qDebug() << "StelGLWidget context format version:" << ctx->format().majorVersion() << "." << context()->format().minorVersion();
			qDebug() << "StelGLWidget has CompatibilityProfile:" << (ctx->format().profile()==QSurfaceFormat::CompatibilityProfile ? "yes" : "no") << "(" <<context()->format().profile() << ")";
		}

		parent->init();
		initialized = true;
	}

protected:
	void paintGL() override
	{
		//this is actually never called because the
		//QGraphicsView intercepts the paint event
		//we have to draw in the background of the scene
		//or as a QGraphicsItem
		qDebug()<<"paintGL";
	}
	void resizeGL(int w, int h) override
	{
		//we probably can ignore this method,
		//it seems it is also never called
		qDebug()<<"resizeGL"<<w<<h;
	}

private:
	StelMainView* parent;
	bool initialized;
};

// A custom QGraphicsEffect to apply the night mode on top of the screen.
class NightModeGraphicsEffect : public QGraphicsEffect
{
public:
	NightModeGraphicsEffect(StelMainView* parent = Q_NULLPTR)
		: QGraphicsEffect(parent),
		  parent(parent), fbo(Q_NULLPTR),
		  vbo(QOpenGLBuffer::VertexBuffer)
	{
		Q_ASSERT(parent->glContext() == QOpenGLContext::currentContext());

		program = new QOpenGLShaderProgram(this);
		const auto vertexCode = StelOpenGL::globalShaderPrefix(StelOpenGL::VERTEX_SHADER) +
				"ATTRIBUTE highp vec4 a_pos;\n"
				"ATTRIBUTE highp vec2 a_texCoord;\n"
				"VARYING highp   vec2 v_texCoord;\n"
				"void main(void)\n"
				"{\n"
				"v_texCoord = a_texCoord;\n"
				"gl_Position = a_pos;\n"
				"}\n";
		const auto fragmentCode = StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) +
				"VARYING highp vec2 v_texCoord;\n"
				"uniform sampler2D  u_source;\n"
				"void main(void)\n"
				"{\n"
				"	mediump vec3 color = texture2D(u_source, v_texCoord).rgb;\n"
				"	mediump float luminance = max(max(color.r, color.g), color.b);\n"
				"	FRAG_COLOR = vec4(luminance, luminance * 0.3, 0.0, 1.0);\n"
				"}\n";
		program->addShaderFromSourceCode(QOpenGLShader::Vertex, vertexCode);
		program->addShaderFromSourceCode(QOpenGLShader::Fragment, fragmentCode);
		program->link();
		vars.pos = program->attributeLocation("a_pos");
		vars.texCoord = program->attributeLocation("a_texCoord");
		vars.source = program->uniformLocation("u_source");

		vbo.create();
		struct VBOData
		{
			const GLfloat pos[8] = {-1, -1, +1, -1, -1, +1, +1, +1};
			const GLfloat texCoord[8] = {0, 0, 1, 0, 0, 1, 1, 1};
		} vboData;
		posOffset = offsetof(VBOData, pos);
		texCoordOffset = offsetof(VBOData, texCoord);
		vbo.bind();
		vbo.setUsagePattern(QOpenGLBuffer::StaticDraw);
		vbo.allocate(&vboData.pos, sizeof vboData);
		if(vao.create())
		{
			vao.bind();
			setupCurrentVAO();
			vao.release();
		}
		vbo.release();
	}

	~NightModeGraphicsEffect() override
	{
		// NOTE: Why Q_ASSERT is here?
		//Q_ASSERT(parent->glContext() == QOpenGLContext::currentContext());
		//clean up fbo
		delete fbo;
	}
protected:
	void draw(QPainter* painter) override
	{
		Q_ASSERT(parent->glContext() == QOpenGLContext::currentContext());
		QOpenGLFunctions* gl = QOpenGLContext::currentContext()->functions();

		QPaintDevice* paintDevice = painter->device();

		int mainFBO;
		gl->glGetIntegerv(GL_FRAMEBUFFER_BINDING, &mainFBO);

		double pixelRatio = paintDevice->devicePixelRatioF();
		QSize size(static_cast<int>(paintDevice->width() * pixelRatio), static_cast<int>(paintDevice->height() * pixelRatio));
		if (fbo && fbo->size() != size)
		{
			delete fbo;
			fbo = Q_NULLPTR;
		}
		if (!fbo)
		{
			QOpenGLFramebufferObjectFormat format;
			format.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
			format.setInternalTextureFormat(GL_RGBA);
			fbo = new QOpenGLFramebufferObject(size, format);
		}

		// we have to use our own paint device
		// we need this because using the original paint device (QOpenGLWidgetPaintDevice when used with QOpenGLWidget) will rebind the default FBO randomly
		// but using 2 GL painters at the same time can mess up the GL state, so we should close the old one first

		// stop drawing to the old paint device to make sure state is reset correctly
		painter->end();

		// create our paint device
		QOpenGLPaintDevice fboPaintDevice(size);
		fboPaintDevice.setDevicePixelRatio(pixelRatio);

		fbo->bind();
		painter->begin(&fboPaintDevice);
		drawSource(painter);
		painter->end();

		painter->begin(paintDevice);

		bindVAO();
		//painter->beginNativePainting();
		program->bind();
		program->setUniformValue(vars.source, 0);
		gl->glBindTexture(GL_TEXTURE_2D, fbo->texture());
		gl->glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		program->release();
		//painter->endNativePainting();
		releaseVAO();
	}

	//! Binds actual VAO if it's supported, sets up the relevant state manually otherwise.
	void bindVAO()
	{
		if(vao.isCreated())
			vao.bind();
		else
			setupCurrentVAO();
	}
	//! Sets the vertex attribute states for the currently bound VAO so that glDraw* commands can work.
	void setupCurrentVAO()
	{
		vbo.bind();
		program->setAttributeBuffer(vars.pos, GL_FLOAT, posOffset, 2, 0);
		program->setAttributeBuffer(vars.texCoord, GL_FLOAT, texCoordOffset, 2, 0);
		vbo.release();
		program->enableAttributeArray(vars.pos);
		program->enableAttributeArray(vars.texCoord);
	}
	//! Binds zero VAO if VAO is supported, manually disables the relevant vertex attributes otherwise.
	void releaseVAO()
	{
		if(vao.isCreated())
		{
			vao.release();
		}
		else
		{
			program->disableAttributeArray(vars.pos);
			program->disableAttributeArray(vars.texCoord);
		}
	}

private:
	StelMainView* parent;
	QOpenGLFramebufferObject* fbo;
	QOpenGLShaderProgram *program;
	struct {
		int pos;
		int texCoord;
		int source;
	} vars;
	int posOffset, texCoordOffset;
	QOpenGLVertexArrayObject vao;
	QOpenGLBuffer vbo;
};

class StelGraphicsScene : public QGraphicsScene
{
public:
	StelGraphicsScene(StelMainView* parent)
		: QGraphicsScene(parent), parent(parent)
	{
		qDebug()<<"StelGraphicsScene constructor";
	}

protected:
	void keyPressEvent(QKeyEvent* event) override
	{
		// Try to trigger a global shortcut.
		StelActionMgr* actionMgr = StelApp::getInstance().getStelActionManager();
		if (actionMgr->pushKey(event->key() + int(event->modifiers()), true)) {
			event->setAccepted(true);
			parent->thereWasAnEvent(); // Refresh screen ASAP
			return;
		}
		//pass event on to items otherwise
		QGraphicsScene::keyPressEvent(event);
	}

private:
	StelMainView* parent;
};

class StelRootItem : public QGraphicsObject
{
public:
	StelRootItem(StelMainView* mainView, QGraphicsItem* parent = Q_NULLPTR)
		: QGraphicsObject(parent),
		  mainView(mainView),
#if defined(__OHOS__)
		  ohosPinchActive(false),
		  ohosPinchStartDistance(0.0),
#endif
		  skyBackgroundColor(0.f,0.f,0.f)
	{
		setFlags(QGraphicsItem::ItemClipsToShape | QGraphicsItem::ItemClipsChildrenToShape | QGraphicsItem::ItemIsFocusable);

		setAcceptHoverEvents(true);

#if defined(Q_OS_WIN) || defined(__OHOS__)
		setAcceptTouchEvents(true);
#endif
#ifdef Q_OS_WIN
		grabGesture(Qt::PinchGesture);
#endif
		setAcceptedMouseButtons(Qt::LeftButton | Qt::RightButton | Qt::MiddleButton);
		previousPaintTime = StelApp::getTotalRunTime();
	}

	void setSize(const QSize& size)
	{
		prepareGeometryChange();
		rect.setSize(size);
		if (StelApp::isInitialized())
		{
			const auto& app = StelApp::getInstance();
			StelCore *core = app.getCore();
			if (core && core->getJD()!=0.0)
				core->setClearSkyOnce();
		}
	}

	//! Set the sky background color. Everything else than black creates a work of art!
	void setSkyBackgroundColor(Vec3f color) { skyBackgroundColor=color; }

	//! Get the sky background color. Everything else than black creates a work of art!
	Vec3f getSkyBackgroundColor() const { return skyBackgroundColor; }


protected:
#if defined(__OHOS__)
	bool event(QEvent* event) override
	{
		switch (event->type())
		{
			case QEvent::TouchBegin:
			case QEvent::TouchUpdate:
			case QEvent::TouchEnd:
			{
				QTouchEvent* touchEvent = static_cast<QTouchEvent*>(event);
				const auto touchPoints = touchEvent->points();
				if (touchPoints.isEmpty())
					break;

				if (event->type() == QEvent::TouchEnd && ohosPinchActive)
				{
					ohosPinchActive = false;
					event->accept();
					mainView->thereWasAnEvent();
					return true;
				}

				if (touchPoints.size() >= 2)
				{
					const QPointF firstPos = touchPoints.at(0).position();
					const QPointF secondPos = touchPoints.at(1).position();
					const double distance = std::hypot(secondPos.x() - firstPos.x(), secondPos.y() - firstPos.y());
					if (distance > 1.0)
					{
						const bool started = event->type() == QEvent::TouchBegin || !ohosPinchActive;
						if (started)
						{
							ohosPinchActive = true;
							ohosPinchStartDistance = distance;
						}
						StelApp::getInstance().handlePinch(distance / ohosPinchStartDistance, started);
						event->accept();
						mainView->thereWasAnEvent();
						return true;
					}
				}

				const QPointF itemPos = touchPoints.first().position();
				QPointF stelPos = itemPos;

				if (event->type() == QEvent::TouchUpdate)
				{
					const bool accepted = StelApp::getInstance().handleMove(stelPos.x(), stelPos.y(), Qt::LeftButton);
					event->setAccepted(accepted);
					if (accepted)
						mainView->thereWasAnEvent();
					return accepted;
				}

				const QEvent::Type mouseType = (event->type() == QEvent::TouchBegin) ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease;
				const Qt::MouseButtons buttons = (mouseType == QEvent::MouseButtonPress) ? Qt::LeftButton : Qt::NoButton;
				QMouseEvent mouseEvent(mouseType, stelPos, stelPos, Qt::LeftButton, buttons, touchEvent->modifiers());
				StelApp::getInstance().handleClick(&mouseEvent);
				event->setAccepted(mouseEvent.isAccepted());
				if (mouseEvent.isAccepted())
					mainView->thereWasAnEvent();
				return mouseEvent.isAccepted();
			}
			default:
				break;
		}
		return QGraphicsObject::event(event);
	}
#endif

	void paint(QPainter *painter, const QStyleOptionGraphicsItem *option, QWidget *widget) override
	{
		Q_UNUSED(option)
		Q_UNUSED(widget)

		//a sanity check
		Q_ASSERT(mainView->glContext() == QOpenGLContext::currentContext());

		StelApp& app = StelApp::getInstance();

		// This can change even on the screen even without actual system settings change.
		// E.g. in KWin 6.1.5 with Wayland backend, if we set 150% scale in System Settings,
		// the app first gets device pixel ratio of 200%, then the widgets are rescaled to 150%
		// while the screen still remains at 200%. This is ugly, and shouldn't behave like this,
		// but the following call seems to be enough to get things working right.
		app.setDevicePixelsPerPixel(mainView->devicePixelRatioF());

		const double now = StelApp::getTotalRunTime();
		double dt = now - previousPaintTime;
		//qDebug()<<"dt"<<dt;
		previousPaintTime = now;

		//important to call this, or Qt may have invalid state after we have drawn (wrong textures, etc...)
		painter->beginNativePainting();

		//fix for bug LP:1628072 caused by QTBUG-56798
#ifndef QT_NO_DEBUG
		StelOpenGL::clearGLErrors();
#endif

		//update and draw
		app.update(dt); // may also issue GL calls
		app.draw();
#if defined(__OHOS__)
		submitOhosFramebuffer(QOpenGLContext::currentContext()->functions());
#endif
		painter->endNativePainting();

		mainView->drawEnded();
	}

	QRectF boundingRect() const override
	{
		return rect;
	}

	//*** Main event handlers to pass on to StelApp ***//
	void mousePressEvent(QGraphicsSceneMouseEvent *event) override
	{
		QMouseEvent ev = convertMouseEvent(event);
		StelApp::getInstance().handleClick(&ev);
		event->setAccepted(ev.isAccepted());
		if(ev.isAccepted())
			mainView->thereWasAnEvent();
	}

	void mouseReleaseEvent(QGraphicsSceneMouseEvent *event) override
	{
		QMouseEvent ev = convertMouseEvent(event);
		StelApp::getInstance().handleClick(&ev);
		event->setAccepted(ev.isAccepted());
		if(ev.isAccepted())
			mainView->thereWasAnEvent();
	}

#ifndef MOUSE_TRACKING
	void mouseMoveEvent(QGraphicsSceneMouseEvent *event) override
	{
		QMouseEvent ev = convertMouseEvent(event);
		QPointF pos = ev.pos();
		event->setAccepted(StelApp::getInstance().handleMove(pos.x(), pos.y(), ev.buttons()));
		if(event->isAccepted())
			mainView->thereWasAnEvent();
	}
#endif

	void wheelEvent(QGraphicsSceneWheelEvent *event) override
	{
		QPointF pos = event->scenePos();
		pos.setY(rect.height() - 1 - pos.y());
#if QT_VERSION >= QT_VERSION_CHECK(5, 14, 0)
		QWheelEvent newEvent(pos, event->screenPos(), QPoint(event->delta(), 0), QPoint(event->delta(), 0), event->buttons(), event->modifiers(), Qt::ScrollUpdate, false);
#else
		QWheelEvent newEvent(QPoint(static_cast<int>(pos.x()),static_cast<int>(pos.y())), event->delta(), event->buttons(), event->modifiers(), event->orientation());
#endif
		StelApp::getInstance().handleWheel(&newEvent);
		event->setAccepted(newEvent.isAccepted());
		if(newEvent.isAccepted())
			mainView->thereWasAnEvent();
	}

	void keyPressEvent(QKeyEvent *event) override
	{
		StelApp::getInstance().handleKeys(event);
		if(event->isAccepted())
			mainView->thereWasAnEvent();
	}

	void keyReleaseEvent(QKeyEvent *event) override
	{
		StelApp::getInstance().handleKeys(event);
		if(event->isAccepted())
			mainView->thereWasAnEvent();
	}

	//*** Gesture and touch support, currently only for Windows
#ifdef Q_OS_WIN
	bool event(QEvent * e) override
	{
		bool r = false;
		switch (e->type()){
			case QEvent::TouchBegin:
			case QEvent::TouchUpdate:
			case QEvent::TouchEnd:
			{
				QTouchEvent *touchEvent = static_cast<QTouchEvent *>(e);
				QList<QTouchEvent::TouchPoint> touchPoints = touchEvent->touchPoints();

				if (touchPoints.count() == 1)
					setAcceptedMouseButtons(Qt::LeftButton | Qt::RightButton | Qt::MiddleButton);

				r = true;
				break;
			}
			case QEvent::Gesture:
				setAcceptedMouseButtons(Qt::NoButton);
				r = gestureEvent(static_cast<QGestureEvent*>(e));
				break;
			default:
				r = QGraphicsObject::event(e);
		}
		return r;
	}

private:
	bool gestureEvent(QGestureEvent *event)
	{
		if (QGesture *pinch = event->gesture(Qt::PinchGesture))
			pinchTriggered(static_cast<QPinchGesture *>(pinch));

		return true;
	}

	void pinchTriggered(QPinchGesture *gesture)
	{
		QPinchGesture::ChangeFlags changeFlags = gesture->changeFlags();
		if (changeFlags & QPinchGesture::ScaleFactorChanged) {
			qreal zoom = gesture->scaleFactor();

			if (zoom < 2 && zoom > 0.5){
				StelApp::getInstance().handlePinch(zoom, true);
			}
		}
	}
#endif

private:
	//! Helper function to convert a QGraphicsSceneMouseEvent to a QMouseEvent suitable for StelApp consumption
	QMouseEvent convertMouseEvent(QGraphicsSceneMouseEvent *event) const
	{
		//convert graphics scene mouse event to widget style mouse event
		QEvent::Type t = QEvent::None;
		switch(event->type())
		{
			case QEvent::GraphicsSceneMousePress:
				t = QEvent::MouseButtonPress;
				break;
			case QEvent::GraphicsSceneMouseRelease:
				t = QEvent::MouseButtonRelease;
				break;
			case QEvent::GraphicsSceneMouseMove:
				t = QEvent::MouseMove;
				break;
			case QEvent::GraphicsSceneMouseDoubleClick:
				//note: the old code seems to have ignored double clicks
				// and handled them the same as normal mouse presses
				//if we ever want to handle double clicks, switch out these lines
				t = QEvent::MouseButtonDblClick;
				//t = QEvent::MouseButtonPress;
				break;
			default:
				//warn in release and assert in debug
				qWarning("Unhandled mouse event type %d",event->type());
				Q_ASSERT(false);
		}

		QPointF pos = event->scenePos();
		//Y needs to be inverted
		pos.setY(rect.height() - 1 - pos.y());
		return QMouseEvent(t,pos,event->button(),event->buttons(),event->modifiers());
	}

	QRectF rect;
	double previousPaintTime;
	StelMainView* mainView;
#if defined(__OHOS__)
	bool ohosPinchActive;
	double ohosPinchStartDistance;
#endif
	Vec3f skyBackgroundColor;           //! color which is used to initialize the frame. Should be black, but for some applications e.g. dark blue may be preferred.
};

//! Initialize and render Stellarium gui.
class StelGuiItem : public QGraphicsWidget
{
public:
	StelGuiItem(const QSize& size, QGraphicsItem* parent = Q_NULLPTR)
		: QGraphicsWidget(parent)
	{
		resize(size);
		StelApp::getInstance().getGui()->init(this);
		inited=true;
	}

protected:
	void resizeEvent(QGraphicsSceneResizeEvent* event) override
	{
		if(!inited) return;

		Q_UNUSED(event)
		//widget->setGeometry(0, 0, size().width(), size().height());
		StelApp::getInstance().getGui()->forceRefreshGui();
	}
private:
	//QGraphicsWidget *widget;
	// void onSizeChanged();
	bool inited = false; // guards resize during construction
};

StelMainView::StelMainView(QSettings* settings)
	: QGraphicsView(),
	  configuration(settings),
	  guiItem(Q_NULLPTR),
	  gui(Q_NULLPTR),
	  stelApp(Q_NULLPTR),
	  updateQueued(false),
	  flagInvertScreenShotColors(false),
	  flagScreenshotDateFileName(false),
	  flagOverwriteScreenshots(false),
	  flagUseCustomScreenshotSize(false),
	  customScreenshotWidth(1024),
	  customScreenshotHeight(768),
	  screenshotDpi(72),
	  screenShotPrefix("stellarium-"),
	  screenShotFormat("png"),
	  screenShotFileMask("yyyyMMdd-hhmmssz"),
	  screenShotDir(""),
	  flagCursorTimeout(false),
	  lastEventTimeSec(0.0),
#if defined(__OHOS__)
	  lastOhosRenderTimeSec(0.0),
#endif
	  minfps(1.f),
	  maxfps(10000.f),
	  minTimeBetweenFrames(5),
	  fpsTimer(nullptr),
	  screensaverInhibitorTimer(nullptr)
{
#if defined(__OHOS__)
	ohosMark("StelMainView constructor entered");
#endif
	setAttribute(Qt::WA_OpaquePaintEvent);
	setAttribute(Qt::WA_AcceptTouchEvents);
	setAttribute(Qt::WA_TouchPadAcceptSingleTouchEvents);
	setAutoFillBackground(false);
	setMouseTracking(true);

	StelApp::initStatic();

	fpsTimer = new QTimer(this);
	fpsTimer->setTimerType(Qt::PreciseTimer);
	fpsTimer->setInterval(qRound(1000.f/minfps));
	connect(fpsTimer, &QTimer::timeout, this, &StelMainView::fpsTimerUpdate);

	cursorTimeoutTimer = new QTimer(this);
	cursorTimeoutTimer->setSingleShot(true);
	connect(cursorTimeoutTimer, &QTimer::timeout, this, &StelMainView::hideCursor);

	// Can't create 2 StelMainView instances
	Q_ASSERT(!singleton);
	singleton = this;

	qApp->installEventFilter(this);

	setWindowIcon(QIcon(":/mainWindow/icon.bmp"));
	initTitleI18n();
	setObjectName("MainView");

#if defined(__OHOS__)
	setViewportUpdateMode(QGraphicsView::FullViewportUpdate);
#else
	setViewportUpdateMode(QGraphicsView::NoViewportUpdate);
#endif
	setFrameShape(QFrame::NoFrame);
	setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
	setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
	//because we only want child elements to have focus, we turn it off here
	setFocusPolicy(Qt::NoFocus);
	connect(this, &StelMainView::screenshotRequested, this, &StelMainView::doScreenshot);

#ifdef OPENGL_DEBUG_LOGGING
	if (QApplication::testAttribute(Qt::AA_UseOpenGLES))
	{
		// QOpenGLDebugLogger doesn't work with OpenGLES's GL_KHR_debug.
		// See Qt Bug 62070: https://bugreports.qt.io/browse/QTBUG-62070

		glLogger = Q_NULLPTR;
	}
	else
	{
		glLogger = new QOpenGLDebugLogger(this);
		connect(glLogger, &QOpenGLDebugLogger::messageLogged, this, &StelMainView::logGLMessage);
	}
#endif

	QSurfaceFormat glFormat = getDesiredGLFormat(configuration);
	glWidget = new StelGLWidget(glFormat, this);
	setViewport(glWidget);
#if defined(__OHOS__)
	ohosMark("StelMainView viewport glWidget installed");
#endif

	stelScene = new StelGraphicsScene(this);
	setScene(stelScene);
	scene()->setItemIndexMethod(QGraphicsScene::NoIndex);
	rootItem = new StelRootItem(this);

	// Workaround (see Bug #940638) Although we have already explicitly set
	// LC_NUMERIC to "C" in main.cpp there seems to be a bug in OpenGL where
	// it will silently reset LC_NUMERIC to the value of LC_ALL during OpenGL
	// initialization. This has been observed on Ubuntu 11.10 under certain
	// circumstances, so here we set it again just to be on the safe side.
	setlocale(LC_NUMERIC, "C");
	// End workaround

	// We cannot use global mousetracking. Only if mouse is hidden!
	//setMouseTracking(true);

    setRenderHint(QPainter::Antialiasing);
#if defined(__OHOS__)
	ohosMark("StelMainView constructor finished");
#endif
}

void StelMainView::resizeEvent(QResizeEvent* event)
{
	if(scene())
	{
		const QSize& sz = event->size();
		scene()->setSceneRect(QRect(QPoint(0, 0), sz));
		rootItem->setSize(sz);
		if(guiItem)
			guiItem->setGeometry(QRectF(0.0,0.0,sz.width(),sz.height()));
		if (StelApp::isInitialized()  && !isFullScreen())
		{
			StelApp::immediateSave("video/screen_w", sz.width());
			StelApp::immediateSave("video/screen_h", sz.height());
		}
		emit sizeChanged(sz);
	}
	QGraphicsView::resizeEvent(event);
}

bool StelMainView::eventFilter(QObject *obj, QEvent *event)
{
	if(event->type() == QEvent::FileOpen)
	{
		QFileOpenEvent *openEvent = static_cast<QFileOpenEvent *>(event);
		//qDebug() << "load script:" << openEvent->file();
		qApp->setProperty("onetime_startup_script", openEvent->file());
	}
	return QGraphicsView::eventFilter(obj, event);
}

void StelMainView::mouseMoveEvent(QMouseEvent *event)
{
	if (flagCursorTimeout) 
	{
		// Show the previous cursor and reset the timeout if the current is "hidden"
		if (QGuiApplication::overrideCursor() && (QGuiApplication::overrideCursor()->shape() == Qt::BlankCursor) )
		{
			QGuiApplication::restoreOverrideCursor();
		}

		cursorTimeoutTimer->start();
	}
	
#ifdef MOUSE_TRACKING
	QPointF pos = event->pos();
	//Y needs to be inverted
	int height1 = StelApp::getInstance().mainWin->height();
	pos.setY(height1 - 1 - pos.y());
	event->setAccepted(StelApp::getInstance().handleMove(pos.x(), pos.y(), event->buttons()));
	if(event->isAccepted())
		thereWasAnEvent();
#endif

	QGraphicsView::mouseMoveEvent(event);
}


void StelMainView::focusSky() {
	//scene()->setActiveWindow(0);
	rootItem->setFocus();
}

StelMainView::~StelMainView()
{
	//delete the night view graphic effect here while GL context is still valid
	rootItem->setGraphicsEffect(Q_NULLPTR);
	StelApp::deinitStatic();
	delete guiItem;
	guiItem=Q_NULLPTR;
}

QSurfaceFormat StelMainView::getDesiredGLFormat(QSettings* configuration)
{
	//use the default format as basis
	QSurfaceFormat fmt = QSurfaceFormat::defaultFormat();
	qDebug() << "Default surface format: " << fmt;

	//if on an GLES build, do not set the format
	const auto openGLModuleType = QOpenGLContext::openGLModuleType();
	qInfo() << "OpenGL module type:" << (openGLModuleType==QOpenGLContext::LibGL
	                                      ? "desktop OpenGL"
	                                      : openGLModuleType==QOpenGLContext::LibGLES
	                                        ? "OpenGL ES 2 or higher"
	                                        : std::to_string(openGLModuleType).c_str());
	if (openGLModuleType==QOpenGLContext::LibGL)
	{
		fmt.setRenderableType(QSurfaceFormat::OpenGL);
		fmt.setVersion(3, 3);
		fmt.setProfile(QSurfaceFormat::CoreProfile);

		if (qApp && qApp->property("onetime_opengl_compat").toBool())
		{
			qInfo() << "Setting OpenGL Compatibility profile from command line...";
			fmt.setProfile(QSurfaceFormat::CompatibilityProfile);
			fmt.setOption(QSurfaceFormat::DeprecatedFunctions);
		}
		// FIXME: temporary hook for Qt5-based macOS bundles
		#if defined(Q_OS_MACOS) && (QT_VERSION < QT_VERSION_CHECK(6, 0, 0))
		fmt.setProfile(QSurfaceFormat::CompatibilityProfile);
		#endif
	}

	// NOTE: multisampling is implemented via FBO now, so it's not requested here.

	//request some sane buffer formats
	fmt.setRedBufferSize(8);
	fmt.setGreenBufferSize(8);
	fmt.setBlueBufferSize(8);
	fmt.setDepthBufferSize(24);
	// Without stencil buffer the debug versions of Qt will repeatedly emit warnings like:
	// "OpenGL paint engine: attempted to use stencil test without requesting a stencil buffer."
	fmt.setStencilBufferSize(8);

	if(qApp && qApp->property("onetime_single_buffer").toBool())
		fmt.setSwapBehavior(QSurfaceFormat::SingleBuffer);

	// VSync control. NOTE: it must be applied to the default format (QSurfaceFormat::setDefaultFormat) to take effect.
#ifdef Q_OS_MACOS
	// FIXME: workaround for bug LP:#1705832 (https://bugs.launchpad.net/stellarium/+bug/1705832)
	// Qt: https://bugreports.qt.io/browse/QTBUG-53273
	const bool vsdef = false; // use vsync=false by default on macOS
#else
	const bool vsdef = true;
#endif
	if (configuration && configuration->value("video/vsync", vsdef).toBool())
		fmt.setSwapInterval(1);
	else
		fmt.setSwapInterval(0);

#ifdef OPENGL_DEBUG_LOGGING
	//try to enable GL debugging using GL_KHR_debug
	fmt.setOption(QSurfaceFormat::DebugContext);
#endif

	return fmt;
}

void StelMainView::init()
{
#ifdef OPENGL_DEBUG_LOGGING
	if (glLogger)
	{
		if(!QOpenGLContext::currentContext()->hasExtension(QByteArrayLiteral("GL_KHR_debug")))
			qWarning()<<"GL_KHR_debug extension missing, OpenGL debug logger will likely not work";
		if(glLogger->initialize())
		{
			qInfo()<<"OpenGL debug logger initialized";
			glLogger->disableMessages(QOpenGLDebugMessage::AnySource, QOpenGLDebugMessage::AnyType,
			                          QOpenGLDebugMessage::NotificationSeverity);
			glLogger->startLogging(QOpenGLDebugLogger::SynchronousLogging);
			//the internal log buffer may not be empty, so check it
			for (const auto& msg : glLogger->loggedMessages())
			{
				logGLMessage(msg);
			}
		}
		else
			qWarning()<<"Failed to initialize OpenGL debug logger";

		connect(QOpenGLContext::currentContext(), &QOpenGLContext::aboutToBeDestroyed, this, &StelMainView::contextDestroyed);
		//for easier debugging, print the address of the main GL context
		qDebug()<<"CurCtxPtr:"<<QOpenGLContext::currentContext();
	}
#endif

	qInfo() << "Initializing StelMainView";

	glInfo.mainContext = QOpenGLContext::currentContext();
	glInfo.surface = glInfo.mainContext->surface();
	glInfo.functions = glInfo.mainContext->functions();
	glInfo.vendor = QString(reinterpret_cast<const char*>(glInfo.functions->glGetString(GL_VENDOR)));
	glInfo.renderer = QString(reinterpret_cast<const char*>(glInfo.functions->glGetString(GL_RENDERER)));
	const auto format = glInfo.mainContext->format();
	glInfo.supportsLuminanceTextures = format.profile() == QSurfaceFormat::CompatibilityProfile ||
	                                   format.majorVersion() < 3;
	glInfo.isGLES = format.renderableType()==QSurfaceFormat::OpenGLES;
	glInfo.majorVersion = format.majorVersion();
	qInfo().nospace() << "Luminance textures are " << (glInfo.supportsLuminanceTextures ? "" : "not ") << "supported";
	glInfo.isCoreProfile = format.profile() == QSurfaceFormat::CoreProfile;
        #if defined Q_OS_HAIKU || defined Q_OS_SOLARIS
        // Haiku OS/Solaris hasn't hardware acceleration and we shouldn't use High Graphics Mode here
        glInfo.isHighGraphicsMode = false;
        #else
	// GLES will always provide high graphics functions due to our choice of QOpenGLExtraFunctions,
	// so we also need to check that we have at least GLES3 to enable high graphics mode.
	// For desktop OpenGL our target version is also at least 3, so it's compatible with this check.
	// And we do need to check that high-graphics functions are available, since GL3.0 is not sufficient.
	glInfo.isHighGraphicsMode = glInfo.majorVersion >= 3 && !!StelOpenGL::highGraphicsFunctions();
	if (qApp->property("onetime_force_low_graphics").toBool())
		glInfo.isHighGraphicsMode = false;
        #endif
	qInfo() << "Running in" << (glInfo.isHighGraphicsMode ? "High" : "Low") << "Graphics Mode";

	auto& gl = *QOpenGLContext::currentContext()->functions();
	if(format.majorVersion() * 1000 + format.minorVersion() >= 4006 ||
	   glInfo.mainContext->hasExtension("GL_EXT_texture_filter_anisotropic") ||
	   glInfo.mainContext->hasExtension("GL_ARB_texture_filter_anisotropic"))
	{
		StelOpenGL::clearGLErrors();
		gl.glGetIntegerv(GL_MAX_TEXTURE_MAX_ANISOTROPY, &glInfo.maxAnisotropy);
		const auto error = gl.glGetError();
		if(error != GL_NO_ERROR)
		{
			qWarning() << "Failed to get maximum texture anisotropy:" << StelOpenGL::getGLErrorText(error);
		}
		else if(glInfo.maxAnisotropy > 0)
		{
			qInfo() << "Maximum texture anisotropy:" << glInfo.maxAnisotropy;
		}
		else
		{
			qWarning() << "Maximum texture anisotropy is not positive:" << glInfo.maxAnisotropy;
			glInfo.maxAnisotropy = 0;
		}
	}
	else
	{
		qWarning() << "Anisotropic filtering is not supported!";
	}

	if(format.majorVersion() > 4 || glInfo.mainContext->hasExtension("GL_ARB_sample_shading"))
	{
		auto addr = glInfo.mainContext->getProcAddress("glMinSampleShading");
		if(!addr)
			addr = glInfo.mainContext->getProcAddress("glMinSampleShadingARB");
		glInfo.glMinSampleShading = reinterpret_cast<decltype(glInfo.glMinSampleShading)>(addr);
	}
	gl.glGetIntegerv(GL_MAX_TEXTURE_SIZE, &glInfo.maxTextureSize);
	qInfo() << "Maximum 2D texture size:" << glInfo.maxTextureSize;

	gui = new StelGui();

	// Should be check of requirements disabled? -- NO! This is intentional here, and does no harm.
	if (configuration->value("main/check_requirements", true).toBool())
	{
		// Find out lots of debug info about supported version of OpenGL and vendor/renderer.
		processOpenGLdiagnosticsAndWarnings(configuration, glInfo.mainContext);
	}

	//setup StelOpenGLArray global state
	StelOpenGLArray::initGL();

	//create and initialize main app
	stelApp = new StelApp(this);
	stelApp->setGui(gui);
	stelApp->init(configuration);
	//this makes sure the app knows how large the window is
	connect(stelScene, &StelGraphicsScene::sceneRectChanged, stelApp, &StelApp::glWindowHasBeenResized);
#ifdef ENABLE_SPOUT
	QObject::connect(stelScene, &StelGraphicsScene::sceneRectChanged, [&](const QRectF& rect)
	{
        stelApp->glPhysicalWindowHasBeenResized(getPhysicalSize(rect));
	});
#endif

	//also immediately set the current values
	stelApp->glWindowHasBeenResized(stelScene->sceneRect());
#ifdef ENABLE_SPOUT
	stelApp->glPhysicalWindowHasBeenResized(getPhysicalSize(stelScene->sceneRect()));
#endif

	StelActionMgr *actionMgr = stelApp->getStelActionManager();
	actionMgr->addAction("actionSave_Screenshot_Global", N_("Miscellaneous"), N_("Save screenshot"), this, "saveScreenShot()", "Ctrl+S");
	actionMgr->addAction("actionReload_Shaders", N_("Miscellaneous"), N_("Reload shaders (for development)"), this, "reloadShaders()", "Ctrl+R, P");
	actionMgr->addAction("actionSet_Full_Screen_Global", N_("Display Options"), N_("Full-screen mode"), this, "fullScreen", "F11");
	
	StelPainter::initGLShaders();

	guiItem = new StelGuiItem(size(), rootItem);
#if defined(__OHOS__)
	guiItem->setVisible(false);
	guiItem->setEnabled(false);
	guiItem->setAcceptedMouseButtons(Qt::NoButton);
	ohosMark("Desktop Qt GUI disabled for OpenHarmony ArkUI shell");
#endif
	scene()->addItem(rootItem);
	//set the default focus to the sky
	focusSky();
	nightModeEffect = new NightModeGraphicsEffect(this);
	updateNightModeProperty(StelApp::getInstance().getVisionModeNight());
	//install the effect on the whole view
	rootItem->setGraphicsEffect(nightModeEffect);

	flagInvertScreenShotColors = configuration->value("main/invert_screenshots_colors", false).toBool();
	setScreenshotFormat(configuration->value("main/screenshot_format", "png").toString()); // includes check for supported formats.
	flagScreenshotDateFileName=configuration->value("main/screenshot_datetime_filename", false).toBool();
	screenShotFileMask = configuration->value("main/screenshot_datetime_filemask", "yyyyMMdd-hhmmssz").toString();
	flagUseCustomScreenshotSize=configuration->value("main/screenshot_custom_size", false).toBool();
	customScreenshotWidth=configuration->value("main/screenshot_custom_width", 1024).toInt();
	customScreenshotHeight=configuration->value("main/screenshot_custom_height", 768).toInt();
	screenshotDpi=configuration->value("main/screenshot_dpi", 72).toInt();
	setFlagCursorTimeout(configuration->value("gui/flag_mouse_cursor_timeout", false).toBool());
	setCursorTimeout(configuration->value("gui/mouse_cursor_timeout", 10.f).toDouble());
	setMaxFps(configuration->value("video/maximum_fps",10000.f).toFloat());
	setMinFps(configuration->value("video/minimum_fps",10000.f).toFloat());
        setMinTimeBetweenFrames(qMax(0, configuration->value("video/min_time_between_frames",5).toInt()));
	setSkyBackgroundColor(Vec3f(configuration->value("color/sky_background_color", "0,0,0").toString()));

	// XXX: This should be done in StelApp::init(), unfortunately for the moment we need to init the gui before the
	// plugins, because the gui creates the QActions needed by some plugins.
	stelApp->initPlugIns();

	// The script manager can only be fully initialized after the plugins have loaded.
	stelApp->initScriptMgr();

#ifndef NO_GUI
	// Set the global stylesheet, this is only useful for the tooltips.
	StelGui* sgui = dynamic_cast<StelGui*>(stelApp->getGui());
	if (sgui!=Q_NULLPTR)
		setStyleSheet(sgui->getStelStyle().qtStyleSheet);
	connect(stelApp, &StelApp::visionNightModeChanged, this, &StelMainView::updateNightModeProperty);
#endif

	// I doubt this will have any effect on framerate, but may cause problems elsewhere?
	QThread::currentThread()->setPriority(QThread::HighestPriority);

#ifndef NDEBUG
	// Get an overview of module callOrders
	if (mainview().isDebugEnabled())
	{
		StelApp::getInstance().dumpModuleActionPriorities(StelModule::ActionDraw);
		StelApp::getInstance().dumpModuleActionPriorities(StelModule::ActionUpdate);
		StelApp::getInstance().dumpModuleActionPriorities(StelModule::ActionHandleMouseClicks);
		StelApp::getInstance().dumpModuleActionPriorities(StelModule::ActionHandleMouseMoves);
		StelApp::getInstance().dumpModuleActionPriorities(StelModule::ActionHandleKeys);
	}
#endif

	// check conflicts for keyboard shortcuts...
	if (configuration->childGroups().contains("shortcuts"))
	{
		QStringList defaultShortcuts =  actionMgr->getShortcutsList();
		QStringList conflicts;
		configuration->beginGroup("shortcuts");
		QStringList cstActionNames = configuration->allKeys();
		QMultiMap<QString, QString> cstActionsMap; // It is possible we have a very messed-up setup with duplicates
		for (QStringList::const_iterator cstActionName = cstActionNames.constBegin(); cstActionName != cstActionNames.constEnd(); ++cstActionName)
		{
			#if (QT_VERSION>=QT_VERSION_CHECK(5, 14, 0))
			QStringList singleCustomActionShortcuts = configuration->value((*cstActionName).toLocal8Bit().constData()).toString().split(" ", Qt::SkipEmptyParts);
			#else
			QStringList singleCustomActionShortcuts = configuration->value((*cstActionName).toLocal8Bit().constData()).toString().split(" ", QString::SkipEmptyParts);
			#endif
			singleCustomActionShortcuts.removeAll("\"\"");

			// Add 1-2 entries per action
			for (QStringList::const_iterator cstActionShortcut = singleCustomActionShortcuts.constBegin(); cstActionShortcut != singleCustomActionShortcuts.constEnd(); ++cstActionShortcut)
				if (strcmp( (*cstActionShortcut).toLocal8Bit().constData(), "") )
					cstActionsMap.insert((*cstActionShortcut), (*cstActionName));
		}
		// Now we have a QMultiMap with (customShortcut, actionName). It may contain multiple keys!
		QStringList allMapKeys=cstActionsMap.keys();
		QStringList uniqueMapKeys=cstActionsMap.uniqueKeys();
		for (auto &key : uniqueMapKeys)
			allMapKeys.removeOne(key);
		conflicts << allMapKeys; // Add the remaining (duplicate) keys

		// Check every shortcut from the Map that it is not assigned to its own correct action
		for (QMultiMap<QString, QString>::const_iterator it=cstActionsMap.constBegin(); it != cstActionsMap.constEnd(); ++it)
		{
			QString customKey(it.key());
			QString actionName=cstActionsMap.value(it.key());
			StelAction *action = actionMgr->findAction(actionName);
			if (action && defaultShortcuts.contains(customKey) && actionMgr->findActionFromShortcut(customKey)->getId()!=action->getId())
				conflicts << customKey;
		}
		configuration->endGroup();

		if (!conflicts.isEmpty())
		{
			QMessageBox::warning(&getInstance(), q_("Attention!"), QString("%1: %2").arg(q_("Shortcuts have conflicts! Please press F7 after program startup and check following multiple assignments"), conflicts.join("; ")), QMessageBox::Ok);
			qCritical() << "Conflicting keyboard shortcut assignments found. Please resolve:" << conflicts.join("; "); // Repeat in logfile for later retrieval.
		}
	}
	if (qApp->property("onetime_inhibit_screensaver").toBool())
		connect (this, &StelMainView::fullScreenChanged, this, &StelMainView::disableScreensaver);
}

void StelMainView::updateNightModeProperty(bool b)
{
	// So that the bottom bar tooltips get properly rendered in night mode.
	setProperty("nightMode", b);
	nightModeEffect->setEnabled(b);
}

void StelMainView::reloadShaders()
{
	//make sure GL context is bound
	glContextMakeCurrent();
	emit reloadShadersRequested();
}

// This is a series of various diagnostics based on "bugs" reported for 0.13.0 and 0.13.1.
// Almost all can be traced to insufficient driver level.
// No changes of OpenGL state is done here.
// If problems are detected, warn the user one time, but continue. Warning panel will be suppressed on next start.
// Work in progress, as long as we get reports about bad systems or until OpenGL startup is finalized and safe.
// Several tests do not apply to MacOS X.
void StelMainView::processOpenGLdiagnosticsAndWarnings(QSettings *conf, QOpenGLContext *context) const
{
#ifdef Q_OS_MACOS
	Q_UNUSED(conf);
#endif
	QSurfaceFormat format=context->format();

	// These tests are not required on MacOS X
#ifndef Q_OS_MACOS
	bool openGLerror=false;
	if (format.renderableType()==QSurfaceFormat::OpenGL || format.renderableType()==QSurfaceFormat::OpenGLES)
	{
		qInfo().noquote() << "Detected:" << (format.renderableType()==QSurfaceFormat::OpenGL  ? "OpenGL" : "OpenGL ES" ) << QString("%1.%2").arg(format.majorVersion()).arg(format.minorVersion());
	}
	else
	{
		openGLerror=true;
		qCritical() << "Neither OpenGL nor OpenGL ES detected: Unsupported Format!";
	}
#endif
	QOpenGLFunctions* gl = context->functions();

	QString glDriver(reinterpret_cast<const char*>(gl->glGetString(GL_VERSION)));
	qInfo().noquote() << "Driver version string:" << glDriver;
	qInfo().noquote() << "GL vendor:" << QString(reinterpret_cast<const char*>(gl->glGetString(GL_VENDOR)));
	QString glRenderer(reinterpret_cast<const char*>(gl->glGetString(GL_RENDERER)));
	qInfo().noquote() << "GL renderer:" << glRenderer;

	// Minimal required version of OpenGL for Qt5 is 2.1 and OpenGL Shading Language may be 1.20 (or OpenGL ES is 2.0 and GLSL ES is 1.0).
	// As of V0.13.0..1, we use GLSL 1.10/GLSL ES 1.00 (implicitly, by omitting a #version line), but in case of using ANGLE we need hardware
	// detected as providing ps_3_0.
	// This means, usually systems with OpenGL3 support reported in the driver will work, those with reported 2.1 only will almost certainly fail.
	// If platform does not even support minimal OpenGL version for Qt5, then tell the user about troubles and quit from application.
	// This test is apparently not applicable on MacOS X due to its behaving differently from all other known OSes.
	// The correct way to handle driver issues on MacOS X remains however unclear for now.
#ifndef Q_OS_MACOS
	bool isMesa=glDriver.contains("Mesa", Qt::CaseInsensitive);
	#if (defined Q_OS_WIN) && (QT_VERSION<QT_VERSION_CHECK(6,0,0))
	bool isANGLE=glRenderer.startsWith("ANGLE", Qt::CaseSensitive);
	#endif
	if ( openGLerror ||
	     ((format.renderableType()==QSurfaceFormat::OpenGL  ) && (format.version() < QPair<int, int>(2, 1)) && !isMesa) ||
	     ((format.renderableType()==QSurfaceFormat::OpenGL  ) && (format.version() < QPair<int, int>(2, 0)) &&  isMesa) || // Mesa defaults to 2.0 but works!
	     ((format.renderableType()==QSurfaceFormat::OpenGLES) && (format.version() < QPair<int, int>(2, 0)))  )
	{
	#if (defined Q_OS_WIN) && (QT_VERSION<QT_VERSION_CHECK(6,0,0))
		if ((!isANGLE) && (!isMesa))
			qCritical() << "Oops... Insufficient OpenGL version. Please update drivers, graphics hardware, or use --angle-mode (or even --mesa-mode) option.";
		else if (isANGLE)
			qCritical() << "Oops... Insufficient OpenGLES version in ANGLE. Please update drivers, graphics hardware, or use --mesa-mode option.";
	#elif (defined Q_OS_WIN)
		if (!isMesa)
			qCritical() << "Oops... Insufficient OpenGL version. Please update drivers, graphics hardware, or use --mesa-mode option.";
		else
                        qCritical() << "Oops... Insufficient OpenGL version. Mesa failed! Please send a bug report.";

		#if (QT_VERSION<QT_VERSION_CHECK(6,0,0))
		QMessageBox::critical(Q_NULLPTR, "Stellarium", q_("Insufficient OpenGL version. Please update drivers, graphics hardware, or use --angle-mode (or --mesa-mode) option."), QMessageBox::Abort, QMessageBox::Abort);
		#else
		QMessageBox::critical(Q_NULLPTR, "Stellarium", q_("Insufficient OpenGL version. Please update drivers, graphics hardware, or use --mesa-mode option."), QMessageBox::Abort, QMessageBox::Abort);
		#endif
	#else
		qCritical() << "Oops... Insufficient OpenGL version. Please update drivers, or graphics hardware.";
		QMessageBox::critical(Q_NULLPTR, "Stellarium", q_("Insufficient OpenGL version. Please update drivers, or graphics hardware."), QMessageBox::Abort, QMessageBox::Abort);
	#endif
		exit(1);
	}
#endif
	// This call requires OpenGL2+.
	QString glslString(reinterpret_cast<const char*>(gl->glGetString(GL_SHADING_LANGUAGE_VERSION)));
	qInfo().noquote() << "GL Shading Language version:" << glslString;

	// Only give extended info if called on command line, for diagnostic.
	if (qApp->property("dump_OpenGL_details").toBool())
		dumpOpenGLdiagnostics();

#if (defined Q_OS_WIN) && (QT_VERSION<QT_VERSION_CHECK(6,0,0))
	// If we have ANGLE, check esp. for insufficient ps_2 level.
	if (isANGLE)
	{
		static const QRegularExpression angleVsPsRegExp(" vs_(\\d)_(\\d) ps_(\\d)_(\\d)");
		int angleVSPSpos=glRenderer.indexOf(angleVsPsRegExp);

		if (angleVSPSpos >-1)
		{
			QRegularExpressionMatch match=angleVsPsRegExp.match(glRenderer);
			float vsVersion=match.captured(1).toFloat() + 0.1f*match.captured(2).toFloat();
			float psVersion=match.captured(3).toFloat() + 0.1f*match.captured(4).toFloat();
			qInfo() << "VS Version Number detected:" << vsVersion;
			qInfo() << "PS Version Number detected:" << psVersion;
			if ((vsVersion<2.0f) || (psVersion<3.0f))
			{
				openGLerror=true;
				qCritical() << "This is not enough: we need DirectX9 with vs_2_0 and ps_3_0 or later.";
				qCritical() << "You should update graphics drivers, graphics hardware, or use the --mesa-mode option.";
				qCritical() << "Else, please try to use an older version like 0.12.9, and try with --safe-mode";

				if (conf->value("main/ignore_opengl_warning", false).toBool())
				{
					qWarning() << "Config option main/ignore_opengl_warning found, continuing. Expect problems.";
				}
				else
				{
					qInfo() << "You can try to run in an unsupported degraded mode by ignoring the warning and continuing.";
					qInfo() << "But more than likely problems will persist.";
					QMessageBox::StandardButton answerButton=
					QMessageBox::critical(Q_NULLPTR, "Stellarium", q_("Your DirectX/OpenGL ES subsystem has problems. See log for details.\nIgnore and suppress this notice in the future and try to continue in degraded mode anyway?"),
					                      QMessageBox::Ignore|QMessageBox::Abort, QMessageBox::Abort);
					if (answerButton == QMessageBox::Abort)
					{
						qCritical() << "Aborting due to ANGLE OpenGL ES / DirectX vs or ps version problems.";
						exit(1);
					}
					else
					{
						qWarning() << "Ignoring all warnings, continuing without further question.";
						conf->setValue("main/ignore_opengl_warning", true);
					}
				}
			}
			else
				qInfo() << "vs/ps version is fine, we should not see a graphics problem.";
		}
		else
		{
			qCritical() << "Cannot parse ANGLE shader version string. This may indicate future problems.";
			qCritical() << "Please send a bug report that includes this log file and states if Stellarium runs or has problems.";
		}
	}
#endif
#ifndef Q_OS_MACOS
        // Do a similar test for Mesa: Ensure we have at least Mesa 10, Mesa 9 on FreeBSD (used for hardware-acceleration of AMD IGP) was reported to lose the stars.
	if (isMesa)
	{
                static const QRegularExpression mesaRegExp("Mesa (\\d+\\.\\d+)"); // we need only major version. Minor should always be here. Test?
		int mesaPos=glDriver.indexOf(mesaRegExp);

		if (mesaPos >-1)
		{
			float mesaVersion=mesaRegExp.match(glDriver).captured(1).toFloat();
                        qInfo() << "Mesa version number detected:" << mesaVersion;
			if ((mesaVersion<10.0f))
			{
				openGLerror=true;
                                qCritical() << "This is not enough: we need Mesa 10.0 or later.";
				qCritical() << "You should update graphics drivers or graphics hardware.";
				qCritical() << "Else, please try to use an older version like 0.12.9, and try there with --safe-mode";

				if (conf->value("main/ignore_opengl_warning", false).toBool())
				{
					qWarning() << "Config option main/ignore_opengl_warning found, continuing. Expect problems.";
				}
				else
				{
					qInfo() << "You can try to run in an unsupported degraded mode by ignoring the warning and continuing.";
					qInfo() << "But more than likely problems will persist.";
					QMessageBox::StandardButton answerButton=
                                        QMessageBox::critical(Q_NULLPTR, "Stellarium", q_("Your OpenGL/Mesa subsystem has problems. See log for details.\nIgnore and suppress this notice in the future and try to continue in degraded mode anyway?"),
					                      QMessageBox::Ignore|QMessageBox::Abort, QMessageBox::Abort);
					if (answerButton == QMessageBox::Abort)
					{
                                                qCritical() << "Aborting due to OpenGL/Mesa insufficient version problems.";
						exit(1);
					}
					else
					{
						qWarning() << "Ignoring all warnings, continuing without further question.";
						conf->setValue("main/ignore_opengl_warning", true);
					}
				}
			}
			else
                                qInfo() << "Mesa version is fine, we should not see a graphics problem.";
		}
		else
		{
                        qCritical() << "Cannot parse Mesa Driver version string. This may indicate future problems.";
			qCritical() << "Please send a bug report that includes this log file and states if Stellarium runs or has problems.";
		}
	}
#endif

	// Although our shaders are only GLSL1.10, there are frequent problems with systems just at this level of programmable shaders.
	// If GLSL version is less than 1.30 or GLSL ES 1.00, Stellarium usually does run properly on Windows or various Linux flavours.
	// Depending on whatever driver/implementation details, Stellarium may crash or show only minor graphical errors.
	// On these systems, we show a warning panel that can be suppressed by a config option which is automatically added on first run.
	// Again, based on a sample size of one, Macs have been reported already to always work in this case.
#ifndef Q_OS_MACOS
	static const QRegularExpression glslRegExp("^(\\d\\.\\d\\d)");
	int pos=glslString.indexOf(glslRegExp);
	// VC4 drivers on Raspberry Pi reports ES 1.0.16 or so, we must step down to one cipher after decimal.
	static const QRegularExpression glslesRegExp("ES (\\d\\.\\d)");
	int posES=glslString.indexOf(glslesRegExp);
	if (pos >-1)
	{
		float glslVersion=glslRegExp.match(glslString).captured(1).toFloat();
		qInfo() << "GLSL Version Number detected:" << glslVersion;
		if (glslVersion<1.3f)
		{
			openGLerror=true;
			qCritical() << "This is not enough: we need GLSL1.30 or later.";
			#ifdef Q_OS_WIN
			qCritical() << "You should update graphics drivers, graphics hardware, or use the --mesa-mode option.";
			#else
			qCritical() << "You should update graphics drivers or graphics hardware.";
			#endif
			qCritical() << "Else, please try to use an older version like 0.12.9, and try there with --safe-mode";

			if (conf->value("main/ignore_opengl_warning", false).toBool())
			{
				qWarning() << "Config option main/ignore_opengl_warning found, continuing. Expect problems.";
			}
			else
			{
				qInfo() << "You can try to run in an unsupported degraded mode by ignoring the warning and continuing.";
				qInfo() << "But more than likely problems will persist.";
				QMessageBox::StandardButton answerButton=
				QMessageBox::critical(Q_NULLPTR, "Stellarium", q_("Your OpenGL subsystem has problems. See log for details.\nIgnore and suppress this notice in the future and try to continue in degraded mode anyway?"),
				                      QMessageBox::Ignore|QMessageBox::Abort, QMessageBox::Abort);
				if (answerButton == QMessageBox::Abort)
				{
					qCritical() << "Aborting due to OpenGL/GLSL version problems.";
					exit(1);
				}
				else
				{
					qWarning() << "Ignoring all warnings, continuing without further question.";
					conf->setValue("main/ignore_opengl_warning", true);
				}
			}
		}
		else
			qInfo() << "GLSL version is fine, we should not see a graphics problem.";
	}
	else if (posES >-1)
	{
		float glslesVersion=glslesRegExp.match(glslString).captured(1).toFloat();
		qInfo() << "GLSL ES Version Number detected:" << glslesVersion;
		if (glslesVersion<1.0f) // TBD: is this possible at all?
		{
			openGLerror=true;
			qCritical() << "This is not enough: we need GLSL ES 1.00 or later.";
#ifdef Q_OS_WIN
			qCritical() << "You should update graphics drivers, graphics hardware, or use the --mesa-mode option.";
#else
			qCritical() << "You should update graphics drivers or graphics hardware.";
#endif
			qCritical() << "Else, please try to use an older version like 0.12.9, and try there with --safe-mode";

			if (conf->value("main/ignore_opengl_warning", false).toBool())
			{
				qWarning() << "Config option main/ignore_opengl_warning found, continuing. Expect problems.";
			}
			else
			{
				qInfo() << "You can try to run in an unsupported degraded mode by ignoring the warning and continuing.";
				qInfo() << "But more than likely problems will persist.";
				QMessageBox::StandardButton answerButton=
				QMessageBox::critical(Q_NULLPTR, "Stellarium", q_("Your OpenGL ES subsystem has problems. See log for details.\nIgnore and suppress this notice in the future and try to continue in degraded mode anyway?"),
				                      QMessageBox::Ignore|QMessageBox::Abort, QMessageBox::Abort);
				if (answerButton == QMessageBox::Abort)
				{
					qCritical() << "Aborting due to OpenGL ES/GLSL ES version problems.";
					exit(1);
				}
				else
				{
					qWarning() << "Ignoring all warnings, continuing without further question.";
					conf->setValue("main/ignore_opengl_warning", true);
				}
			}
		}
		else
		{
			if (openGLerror)
				qWarning() << "GLSL ES version is OK, but there were previous errors, expect problems.";
			else
				qInfo() << "GLSL ES version is fine, we should not see a graphics problem.";
		}
	}
	else
	{
		qCritical() << "Cannot parse GLSL (ES) version string. This may indicate future problems.";
		qCritical() << "Please send a bug report that includes this log file and states if Stellarium works or has problems.";
	}
#endif
}

// Get physical dimensions given the virtual dimensions for the screen where this window is located.
QRectF StelMainView::getPhysicalSize(const QRectF& virtualRect) const
{
	auto window = this->window();
	if(window)
	{
		auto pixelRatio = window->devicePixelRatio();
		QRectF newRect(virtualRect.x(), virtualRect.y(), virtualRect.width() * pixelRatio, virtualRect.height() * pixelRatio);
		return newRect;
	}

	// If the platform does not support getting the QWindow backing instance of this QWidget
	return virtualRect;
}

// Debug info about OpenGL capabilities.
void StelMainView::dumpOpenGLdiagnostics() const
{
	QOpenGLContext *context = QOpenGLContext::currentContext();
	if (context)
	{
		context->functions()->initializeOpenGLFunctions();
		qDebug() << "initializeOpenGLFunctions()...";
		QOpenGLFunctions::OpenGLFeatures oglFeatures=context->functions()->openGLFeatures();
		qInfo() << "OpenGL Features:";
		qInfo() << " - glActiveTexture() function" << ((oglFeatures&QOpenGLFunctions::Multitexture) ? "is" : "is NOT") << "available.";
		qInfo() << " - Shader functions" << ((oglFeatures&QOpenGLFunctions::Shaders) ? "are" : "are NOT ") << "available.";
		qInfo() << " - Vertex and index buffer functions" << ((oglFeatures&QOpenGLFunctions::Buffers) ? "are" : "are NOT") << "available.";
		qInfo() << " - Framebuffer object functions" << ((oglFeatures&QOpenGLFunctions::Framebuffers) ? "are" : "are NOT") << "available.";
		qInfo() << " - glBlendColor()" << ((oglFeatures&QOpenGLFunctions::BlendColor) ? "is" : "is NOT") << "available.";
		qInfo() << " - glBlendEquation()" << ((oglFeatures&QOpenGLFunctions::BlendEquation) ? "is" : "is NOT") << "available.";
		qInfo() << " - glBlendEquationSeparate()" << ((oglFeatures&QOpenGLFunctions::BlendEquationSeparate) ? "is" : "is NOT") << "available.";
		qInfo() << " - glBlendFuncSeparate()" << ((oglFeatures&QOpenGLFunctions::BlendFuncSeparate) ? "is" : "is NOT") << "available.";
		qInfo() << " - Blend subtract mode" << ((oglFeatures&QOpenGLFunctions::BlendSubtract) ? "is" : "is NOT") << "available.";
		qInfo() << " - Compressed texture functions" << ((oglFeatures&QOpenGLFunctions::CompressedTextures) ? "are" : "are NOT") << "available.";
		qInfo() << " - glSampleCoverage() function" << ((oglFeatures&QOpenGLFunctions::Multisample) ? "is" : "is NOT") << "available.";
		qInfo() << " - Separate stencil functions" << ((oglFeatures&QOpenGLFunctions::StencilSeparate) ? "are" : "are NOT") << "available.";
		qInfo() << " - Non power of two textures" << ((oglFeatures&QOpenGLFunctions::NPOTTextures) ? "are" : "are NOT") << "available.";
		qInfo() << " - Non power of two textures" << ((oglFeatures&QOpenGLFunctions::NPOTTextureRepeat) ? "can" : "CANNOT") << "use GL_REPEAT as wrap parameter.";
		qInfo() << " - The fixed function pipeline" << ((oglFeatures&QOpenGLFunctions::FixedFunctionPipeline) ? "is" : "is NOT") << "available.";
		GLfloat lineWidthRange[2];
		context->functions()->glGetFloatv(GL_ALIASED_LINE_WIDTH_RANGE, lineWidthRange);
		qInfo() << "Line widths available from" << lineWidthRange[0] << "to" << lineWidthRange[1];

		qInfo() << "OpenGL shader capabilities and details:";
		qInfo() << " - Vertex Shader:" << (QOpenGLShader::hasOpenGLShaders(QOpenGLShader::Vertex, context) ? "YES" : "NO");
		qInfo() << " - Fragment Shader:" << (QOpenGLShader::hasOpenGLShaders(QOpenGLShader::Fragment, context) ? "YES" : "NO");
		qInfo() << " - Geometry Shader:" << (QOpenGLShader::hasOpenGLShaders(QOpenGLShader::Geometry, context) ? "YES" : "NO");
		qInfo() << " - TessellationControl Shader:" << (QOpenGLShader::hasOpenGLShaders(QOpenGLShader::TessellationControl, context) ? "YES" : "NO");
		qInfo() << " - TessellationEvaluation Shader:" << (QOpenGLShader::hasOpenGLShaders(QOpenGLShader::TessellationEvaluation, context) ? "YES" : "NO");
		qInfo() << " - Compute Shader:" << (QOpenGLShader::hasOpenGLShaders(QOpenGLShader::Compute, context) ? "YES" : "NO");
		
		// List available extensions. Not sure if this is in any way useful?
		QSet<QByteArray> extensionSet=context->extensions();
		qInfo() << "We have" << extensionSet.count() << "OpenGL extensions:";
		QMap<QString, QString> extensionMap;
		QSetIterator<QByteArray> iter(extensionSet);
		while (iter.hasNext())
		{
			if (!iter.peekNext().isEmpty()) {// Don't insert empty lines
				extensionMap.insert(QString(iter.peekNext()), QString(iter.peekNext()));
			}
			iter.next();
		}
		QMapIterator<QString, QString> iter2(extensionMap);
		while (iter2.hasNext()) {
			qInfo().noquote() << " -" << iter2.next().key();
		}

		QFunctionPointer programParameterPtr =context->getProcAddress("glProgramParameteri");
		if (programParameterPtr == Q_NULLPTR) {
			qWarning() << "glProgramParameteri cannot be resolved here. BAD!";
		}
		programParameterPtr =context->getProcAddress("glProgramParameteriEXT");
		if (programParameterPtr == Q_NULLPTR) {
			qWarning() << "glProgramParameteriEXT cannot be resolved here. BAD!";
		}
	}
	else
	{
		qCritical() << "dumpOpenGLdiagnostics(): No OpenGL context";
	}
}

void StelMainView::deinit()
{
	glContextMakeCurrent();
	deinitGL();
	delete stelApp;
	stelApp = Q_NULLPTR;
}

#if defined(__OHOS__)
void StelMainView::startOhosRenderPump()
{
	ohosMark("startOhosRenderPump entered");
	markQtLoopRunning();
	updateQueued = false;
	fpsTimer->setInterval(currentOhosRenderIntervalMs());
	renderOhosFrameNow();
	fpsTimer->start();
	qWarning() << "Started OpenHarmony render pump.";
}

void StelMainView::renderOhosFrameNow()
{
	ohosDrainCommandQueue();
	if (!stelApp || !glWidget || !glWidget->context() || !StelApp::isInitialized())
	{
		requestOhosSceneRepaint();
		return;
	}

	glWidget->makeCurrent();
	QOpenGLContext* currentContext = QOpenGLContext::currentContext();
	if (!currentContext)
		return;

	QOpenGLFunctions* gl = currentContext->functions();
	const double now = StelApp::getTotalRunTime();
	double dt = lastOhosRenderTimeSec > 0.0 ? now - lastOhosRenderTimeSec : 0.0;
	if (dt < 0.0 || dt > 0.25)
		dt = currentOhosRenderIntervalMs() / 1000.0;
	lastOhosRenderTimeSec = now;

	const double pixelRatio = glWidget->devicePixelRatioF();
	const int width = qMax(1, int(glWidget->width() * pixelRatio));
	const int height = qMax(1, int(glWidget->height() * pixelRatio));

	StelApp& app = StelApp::getInstance();
	app.setDevicePixelsPerPixel(devicePixelRatioF());
	gl->glBindFramebuffer(GL_FRAMEBUFFER, glWidget->defaultFramebufferObject());
	gl->glViewport(0, 0, width, height);

	app.update(dt);
	app.draw();
	submitOhosFramebuffer(gl);
}

void StelMainView::requestOhosSceneRepaint()
{
	updateQueued = false;
	if (rootItem)
		rootItem->update();
	if (stelScene)
		stelScene->invalidate(stelScene->sceneRect(), QGraphicsScene::AllLayers);
	if (glWidget)
		glWidget->repaint();
}
#endif

// Update the translated title
void StelMainView::initTitleI18n()
{
	setWindowTitle(StelUtils::getApplicationName());
}

void StelMainView::setFullScreen(bool b)
{
	if (b)
		showFullScreen();
	else
	{
		showNormal();

		// Not enough. If we had started in fullscreen, the inner part of the window is at 0/0, with the frame extending to top/left off screen.
		// Therefore moving is not possible. We must move to the stored position or at least defaults.
		if ( (x()<0)  && (y()<0))
		{
			QSettings *conf = stelApp->getSettings();
			int screen = conf->value("video/screen_number", 0).toInt();
			if (screen < 0 || screen >= qApp->screens().count())
			{
				qWarning() << "Screen" << screen << "not found";
				screen = 0;
			}
			QRect screenGeom = qApp->screens().at(screen)->geometry();
			int x = conf->value("video/screen_x", 0).toInt();
			int y = conf->value("video/screen_y", 0).toInt();
			move(x + screenGeom.x(), y + screenGeom.y());
		}
	}
	StelApp::immediateSave("video/fullscreen", b);
	emit fullScreenChanged(b);
}

void StelMainView::drawEnded()
{
	updateQueued = false;

#if defined(__OHOS__)
	const int requiredFpsInterval = currentOhosRenderIntervalMs();
#else
	const int requiredFpsInterval = qRound(1000.f / getDesiredFps());
#endif
#ifndef Q_OS_MACOS
	if(fpsTimer->interval() != requiredFpsInterval)
		fpsTimer->setInterval(requiredFpsInterval);
#else
	// FIXME: workaround for https://github.com/Stellarium/stellarium/issues/2778, in which touchpad-based
	// view manipulation can be very laggy on Macs in circumstances where frame rendering more time than
	// the trackpad move update rate from the OS. This is perhaps a bug in Qt; see the discussion around
	// https://github.com/Stellarium/stellarium/issues/2778#issuecomment-1722766935 and below for details.
	fpsTimer->setInterval(qMax(minTimeBetweenFrames, requiredFpsInterval));
#endif

	if(!fpsTimer->isActive())
		fpsTimer->start();

	emit frameFinished();
}

void StelMainView::setFlagCursorTimeout(bool b)
{
	if (b == flagCursorTimeout) return;

	flagCursorTimeout = b;
	if (b) 	// enable timer
	{
		cursorTimeoutTimer->start();
	}
	else	// disable timer
	{
		// Show the previous cursor if the current is "hidden" 
		if (QGuiApplication::overrideCursor() && (QGuiApplication::overrideCursor()->shape() == Qt::BlankCursor) )
		{
			// pop the blank cursor
			QGuiApplication::restoreOverrideCursor();
		}
		// and stop the timer 
		cursorTimeoutTimer->stop();
	}
	
	StelApp::immediateSave("gui/flag_mouse_cursor_timeout", b);
	emit flagCursorTimeoutChanged(b);
}

void StelMainView::hideCursor()
{
	// timeout fired...
	// if the feature is not asked, do nothing
	if (!flagCursorTimeout) return;

	// "hide" the current cursor by pushing a Blank cursor
	QGuiApplication::setOverrideCursor(Qt::BlankCursor);
}

void StelMainView::fpsTimerUpdate()
{
#if defined(__OHOS__)
	const int requiredFpsInterval = currentOhosRenderIntervalMs();
	if (fpsTimer->interval() != requiredFpsInterval)
		fpsTimer->setInterval(requiredFpsInterval);
	renderOhosFrameNow();
	return;
#endif
	if(!updateQueued)
	{
		updateQueued = true;
#if defined(__OHOS__)
		glWidget->repaint();
#else
		QTimer::singleShot(0, glWidget, qOverload<>(&StelGLWidget::update));
#endif
	}
}

#ifdef OPENGL_DEBUG_LOGGING
void StelMainView::logGLMessage(const QOpenGLDebugMessage &debugMessage)
{
	qDebug()<<debugMessage;
}

void StelMainView::contextDestroyed()
{
	qDebug()<<"Main OpenGL context destroyed";
}
#endif

void StelMainView::thereWasAnEvent()
{
	lastEventTimeSec = StelApp::getTotalRunTime();
#if defined(__OHOS__)
	updateQueued = false;
	if (fpsTimer && fpsTimer->interval() != OHOS_INTERACTIVE_RENDER_INTERVAL_MS)
		fpsTimer->setInterval(OHOS_INTERACTIVE_RENDER_INTERVAL_MS);
#endif
}

bool StelMainView::needsMaxFPS() const
{
	const double now = StelApp::getTotalRunTime();

	// Determines when the next display will need to be triggered
	// The current policy is that after an event, the FPS is maximum for 2.5 seconds
	// after that, it switches back to the default minfps value to save power.
	// The fps is also kept to max if the timerate is higher than normal speed.
	const double timeRate = stelApp->getCore()->getTimeRate();
	return (now - lastEventTimeSec < 2.5) || fabs(timeRate) > StelCore::JD_SECOND;
}

void StelMainView::moveEvent(QMoveEvent * event)
{
	const QPoint &pos=event->pos();

	// We use the glWidget instead of the event, as we want the screen that shows most of the widget.
	QWindow* win = glWidget->windowHandle();
	if(win)
	{
		stelApp->setDevicePixelsPerPixel(win->devicePixelRatio());
	}

	if (StelApp::isInitialized())
	{
		StelApp::immediateSave("video/screen_x", pos.x());
		StelApp::immediateSave("video/screen_y", pos.y());
	}
}

void StelMainView::closeEvent(QCloseEvent* event)
{
	Q_UNUSED(event)
	stelApp->quit();
}

//! Delete openGL textures (to call before the GLContext disappears)
void StelMainView::deinitGL()
{
	//fix for bug 1628072 caused by QTBUG-56798
#ifndef QT_NO_DEBUG
	StelOpenGL::clearGLErrors();
#endif

	stelApp->deinit();
	delete gui;
	gui = Q_NULLPTR;
}

void StelMainView::setScreenshotFormat(const QString filetype)
{
	const QString candidate=filetype.toLower();
	const QByteArray candBA=candidate.toUtf8();

	// Make sure format is supported by Qt, but restrict some useless formats.
	QList<QByteArray> formats = QImageWriter::supportedImageFormats();
	formats.removeOne("icns");
	formats.removeOne("wbmp");
	formats.removeOne("cur");
	if (formats.contains(candBA))
	{
		screenShotFormat=candidate;
		// apply setting immediately
		configuration->setValue("main/screenshot_format", candidate);
		emit screenshotFormatChanged(candidate);
	}
	else
	{
		qCritical() << "Invalid filetype for screenshot: " << filetype;
	}
}

void StelMainView::setFlagScreenshotDateFileName(bool b)
{
	flagScreenshotDateFileName=b;
	StelApp::getInstance().getSettings()->setValue("main/screenshot_datetime_filename", b);
	emit flagScreenshotDateFileNameChanged(b);
}

void StelMainView::setScreenshotFileMask(const QString filemask)
{
	screenShotFileMask = filemask;
	StelApp::getInstance().getSettings()->setValue("main/screenshot_datetime_filemask", filemask);
	emit screenshotFileMaskChanged(filemask);
}

void StelMainView::setScreenshotDpi(int dpi)
{
	screenshotDpi=dpi;
	StelApp::getInstance().getSettings()->setValue("main/screenshot_dpi", dpi);
	emit screenshotDpiChanged(dpi);
}

void StelMainView::saveScreenShot(const QString& filePrefix, const QString& saveDir, const bool overwrite)
{
	screenShotPrefix = QFileInfo(filePrefix).fileName(); // Strip away any path elements (Security issue!)
	if (screenShotPrefix.isEmpty())
		screenShotPrefix = "stellarium-";
	screenShotDir = saveDir;
	flagOverwriteScreenshots=overwrite;
	emit screenshotRequested();
}

void StelMainView::doScreenshot(void)
{
	QFileInfo shotDir;
	// Make a screenshot which may be larger than the current window. This is harder than you would think:
	// fbObj the framebuffer governs size of the target image, that's the easy part, but it also has its limits.
	// However, the GUI parts need to be placed properly,
	// HiDPI screens interfere, and the viewing angle has to be maintained.
	// First, image size:
	glWidget->makeCurrent();
	const auto pixelRatio = StelApp::getInstance().getDevicePixelsPerPixel();
	int physImgWidth  = int(stelScene->width() * pixelRatio);
	int physImgHeight = int(stelScene->height() * pixelRatio);
	bool nightModeWasEnabled=nightModeEffect->isEnabled();
	nightModeEffect->setEnabled(false);
	if (flagUseCustomScreenshotSize)
	{
		// Borrowed from Scenery3d renderer: determine maximum framebuffer size as minimum of texture, viewport and renderbuffer size
		QOpenGLContext *context = QOpenGLContext::currentContext();
		if (context)
		{
			context->functions()->initializeOpenGLFunctions();
			//qDebug() << "initializeOpenGLFunctions()...";
			// TODO: Investigate this further when GL memory issues should appear.
			// Make sure we have enough free GPU memory!
#ifndef NDEBUG
#ifdef GL_GPU_MEMORY_INFO_CURRENT_AVAILABLE_VIDMEM_NVX
			GLint freeGLmemory;
			context->functions()->glGetIntegerv(GL_GPU_MEMORY_INFO_CURRENT_AVAILABLE_VIDMEM_NVX, &freeGLmemory);
			qCDebug(mainview)<<"Free GPU memory:" << freeGLmemory << "kB -- we ask for " << customScreenshotWidth*customScreenshotHeight*8 / 1024 <<"kB";
#endif
#ifdef GL_RENDERBUFFER_FREE_MEMORY_ATI
			GLint freeGLmemoryAMD[4];
			context->functions()->glGetIntegerv(GL_RENDERBUFFER_FREE_MEMORY_ATI, freeGLmemoryAMD);
			qCDebug(mainview)<<"Free GPU memory (AMD version):" << static_cast<uint>(freeGLmemoryAMD[1])/1024 << "+"
			                 << static_cast<uint>(freeGLmemoryAMD[3])/1024 << " of "
			                 << static_cast<uint>(freeGLmemoryAMD[0])/1024 << "+"
			                 << static_cast<uint>(freeGLmemoryAMD[2])/1024 << "kB -- we ask for "
			                 << customScreenshotWidth*customScreenshotHeight*8 / 1024 <<"kB";
#endif
#endif
			GLint texSize,viewportSize[2],rbSize;
			context->functions()->glGetIntegerv(GL_MAX_TEXTURE_SIZE, &texSize);
			context->functions()->glGetIntegerv(GL_MAX_VIEWPORT_DIMS, viewportSize);
			context->functions()->glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE, &rbSize);
			qCDebug(mainview)<<"Maximum texture size:"<<texSize;
			qCDebug(mainview)<<"Maximum viewport dims:"<<viewportSize[0]<<viewportSize[1];
			qCDebug(mainview)<<"Maximum renderbuffer size:"<<rbSize;
			int maximumFramebufferSize = qMin(texSize,qMin(rbSize,qMin(viewportSize[0],viewportSize[1])));
			qCDebug(mainview)<<"Maximum framebuffer size:"<<maximumFramebufferSize;

			physImgWidth =qMin(maximumFramebufferSize, customScreenshotWidth);
			physImgHeight=qMin(maximumFramebufferSize, customScreenshotHeight);
		}
		else
		{
			qCWarning(mainview) << "No GL context for screenshot! Aborting.";
			return;
		}
	}
	// The texture format depends on used GL version. RGB is fine on OpenGL. on GLES, we must use RGBA and circumvent problems with a few more steps.
	bool isGLES=(QOpenGLContext::currentContext()->format().renderableType() == QSurfaceFormat::OpenGLES);

	QOpenGLFramebufferObjectFormat fbFormat;
	fbFormat.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
	fbFormat.setInternalTextureFormat(isGLES ? GL_RGBA : GL_RGB); // try to avoid transparent background!
	QOpenGLFramebufferObject * fbObj = new QOpenGLFramebufferObject(physImgWidth, physImgHeight, fbFormat);
	fbObj->bind();
	// Now the painter has to be convinced to paint to the potentially larger image frame.
	QOpenGLPaintDevice fbObjPaintDev(physImgWidth, physImgHeight);

	// It seems the projector has its own knowledge about image size. We must adjust fov and image size, but reset afterwards.
	StelCore *core=StelApp::getInstance().getCore();
	StelProjector::StelProjectorParams pParams=core->getCurrentStelProjectorParams();
	StelProjector::StelProjectorParams sParams=pParams;
	//qCDebug(mainview) << "Screenshot Viewport: x" << pParams.viewportXywh[0] << "/y" << pParams.viewportXywh[1] << "/w" << pParams.viewportXywh[2] << "/h" << pParams.viewportXywh[3];
	const auto virtImgWidth  = std::ceil(physImgWidth  / pixelRatio);
	const auto virtImgHeight = std::ceil(physImgHeight / pixelRatio);
	sParams.viewportXywh[2] = virtImgWidth;
	sParams.viewportXywh[3] = virtImgHeight;

	sParams.viewportCenter.set(0.0+(0.5+pParams.viewportCenterOffset.v[0])*virtImgWidth,
	                           0.0+(0.5+pParams.viewportCenterOffset.v[1])*virtImgHeight);
	sParams.viewportFovDiameter = qMin(virtImgWidth,virtImgHeight);
	core->setCurrentStelProjectorParams(sParams);

	QPainter painter;
	painter.begin(&fbObjPaintDev);
	// next line was above begin(), but caused a complaint. Maybe use after begin()?
	painter.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing);
	stelScene->setSceneRect(0, 0, virtImgWidth, virtImgHeight);

#ifndef NO_GUI
	// push the button bars back to the sides where they belong, and fix root item clipping its children.
	dynamic_cast<StelGui*>(gui)->getSkyGui()->setGeometry(0, 0, virtImgWidth, virtImgHeight);
	rootItem->setSize(QSize(virtImgWidth, virtImgHeight));
	dynamic_cast<StelGui*>(gui)->forceRefreshGui(); // refresh bar position.
#endif

	stelScene->render(&painter, QRectF(), QRectF(0,0,virtImgWidth,virtImgHeight) , Qt::KeepAspectRatio);
	painter.end();

	QImage im;
	if (isGLES)
	{
		// We have RGBA texture with possibly empty spots when atmosphere was off.
		// See toImage() help entry why to create wrapper here.
		QImage fboImage(fbObj->toImage());
		//qDebug() << "FBOimage format:" << fboImage.format(); // returns Format_RGBA8888_Premultiplied
		QImage im2(fboImage.constBits(), fboImage.width(), fboImage.height(), QImage::Format_RGBX8888);
		im=im2.copy();
	}
	else
		im=fbObj->toImage();
	fbObj->release();
	delete fbObj;
	// reset viewport and GUI
	core->setCurrentStelProjectorParams(pParams);
	nightModeEffect->setEnabled(nightModeWasEnabled);
	stelScene->setSceneRect(0, 0, pParams.viewportXywh[2], pParams.viewportXywh[3]);
	rootItem->setSize(QSize(pParams.viewportXywh[2], pParams.viewportXywh[3]));
#ifndef NO_GUI
	StelGui* stelGui = dynamic_cast<StelGui*>(gui);
	if (stelGui)
	{
		stelGui->getSkyGui()->setGeometry(0, 0, pParams.viewportXywh[2], pParams.viewportXywh[3]);
		stelGui->forceRefreshGui();
	}
#endif
	if (nightModeWasEnabled)
	{
		for (int row=0; row<im.height(); ++row)
			for (int col=0; col<im.width(); ++col)
			{
				QRgb rgb=im.pixel(col, row);
				int gray=qGray(rgb);
				im.setPixel(col, row, qRgb(gray, 0, 0));
			}
	}
	if (flagInvertScreenShotColors)
		im.invertPixels();

	if (StelFileMgr::getScreenshotDir().isEmpty())
	{
		qWarning() << "Oops, the directory for screenshots is not set! Let's try create and set it...";
		// Create a directory for screenshots if main/screenshot_dir option is unset and user do screenshot at the moment!
		QString screenshotDirSuffix = "/Stellarium";
		QString screenshotDir;
		if (!QStandardPaths::standardLocations(QStandardPaths::PicturesLocation).isEmpty())
		{
			screenshotDir = QStandardPaths::standardLocations(QStandardPaths::PicturesLocation).constFirst();
			screenshotDir.append(screenshotDirSuffix);
		}
		else
			screenshotDir = StelFileMgr::getUserDir().append(screenshotDirSuffix);

		try
		{
			StelFileMgr::setScreenshotDir(screenshotDir);
			StelApp::getInstance().getSettings()->setValue("main/screenshot_dir", screenshotDir);
		}
		catch (std::runtime_error &e)
		{
			qCritical() << "Error: cannot create screenshot directory:" << e.what();
		}
	}

	if (screenShotDir == "")
		shotDir = QFileInfo(StelFileMgr::getScreenshotDir());
	else
		shotDir = QFileInfo(screenShotDir);

	if (!shotDir.isDir())
	{
		qCritical() << "Requested screenshot directory is not a directory: " << QDir::toNativeSeparators(shotDir.filePath());
		return;
	}
	else if (!shotDir.isWritable())
	{
		qCritical() << "Requested screenshot directory is not writable: " << QDir::toNativeSeparators(shotDir.filePath());
		return;
	}

	QFileInfo shotPath;
	if (flagOverwriteScreenshots)
	{
		shotPath = QFileInfo(shotDir.filePath() + "/" + screenShotPrefix + "." + screenShotFormat);
	}
	else
	{
		QString shotPathString;
		if (flagScreenshotDateFileName)
		{
			// name screenshot files with current time
			QString currentTime = QDateTime::currentDateTime().toString(screenShotFileMask);
			shotPathString = QString("%1/%2%3.%4").arg(shotDir.filePath(), screenShotPrefix, currentTime, screenShotFormat);
			shotPath = QFileInfo(shotPathString);
		}
		else
		{
			// build filter for file list, so we only select Stellarium screenshot files (prefix*.format)
			QString shotFilePattern = QString("%1*.%2").arg(screenShotPrefix, screenShotFormat);
			QStringList fileNameFilters(shotFilePattern);
			// get highest-numbered file in screenshot directory
			QDir dir(shotDir.filePath());
			QStringList existingFiles = dir.entryList(fileNameFilters);

			// screenshot number - default to 1 for empty directory
			int shotNum = 1;
			if (!existingFiles.empty())
			{
				// already have screenshots, find largest number
				QString lastFileName = existingFiles[existingFiles.size() - 1];

				// extract number from highest-numbered file name
				QString lastShotNumString = lastFileName.replace(screenShotPrefix, "").replace("." + screenShotFormat, "");
				// new screenshot number = start at highest number
				shotNum = lastShotNumString.toInt() + 1;
			}

			// build new screenshot path: "path/prefix-num.format"
			// num is at least 3 characters
			QString shotNumString = QString::number(shotNum).rightJustified(3, '0');
			shotPathString = QString("%1/%2%3.%4").arg(shotDir.filePath(), screenShotPrefix, shotNumString, screenShotFormat);
			shotPath = QFileInfo(shotPathString);
			// validate if new screenshot number is valid (non-existent)
			while (shotPath.exists()) {
				shotNum++;
				shotNumString = QString::number(shotNum).rightJustified(3, '0');
				shotPathString = QString("%1/%2%3.%4").arg(shotDir.filePath(), screenShotPrefix, shotNumString, screenShotFormat);
				shotPath = QFileInfo(shotPathString);
			}
		}
	}
	/*
	// OPTIONAL: Determine free space and reject storing. This should avoid filling user space.
	QStorageInfo storageInfo(shotPath.filePath());
	if (storageInfo.bytesAvailable() < 50*1024*1024)
	{
		qWarning() << "Less than 50MB free. Not storing screenshot to" << shotPath.filePath();
		qWarning() << "You must clean up your system to free disk space!";
		return;
	}
	*/

	// Set preferred image resolution (for some printing workflows)
	im.setDotsPerMeterX(qRound(screenshotDpi*100./2.54));
	im.setDotsPerMeterY(qRound(screenshotDpi*100./2.54));
	qInfo() << "Saving screenshot to file: " << QDir::toNativeSeparators(shotPath.filePath());

	QImageWriter imageWriter(shotPath.filePath());
	if (screenShotFormat=="tif")
		imageWriter.setCompression(1); // use LZW
	if (screenShotFormat=="jpg")
	{
		imageWriter.setQuality(75); // This is actually default
	}
	if (screenShotFormat=="jpeg")
	{
		imageWriter.setQuality(100);
	}
	if (!imageWriter.write(im))
	{
		qCritical() << "Failed to write screenshot to:" << QDir::toNativeSeparators(shotPath.filePath());
	}
}

QPoint StelMainView::getMousePos() const
{
	return glWidget->mapFromGlobal(QCursor::pos());
}

QOpenGLContext* StelMainView::glContext() const
{
	return glWidget->context();
}

void StelMainView::glContextMakeCurrent()
{
	glWidget->makeCurrent();
}

void StelMainView::glContextDoneCurrent()
{
	glWidget->doneCurrent();
}

// Set the sky background color. Everything else than black creates a work of art!
void StelMainView::setSkyBackgroundColor(Vec3f color)
{
	rootItem->setSkyBackgroundColor(color);
	StelApp::getInstance().getSettings()->setValue("color/sky_background_color", color.toStr());
	emit skyBackgroundColorChanged(color);
}

// Get the sky background color. Everything else than black creates a work of art!
Vec3f StelMainView::getSkyBackgroundColor() const
{
	return rootItem->getSkyBackgroundColor();
}

QRectF StelMainView::setWindowSize(int width, int height)
{
	// Make sure to leave fullscreen if necessary.
	if (isFullScreen())
		setFullScreen(false);
	QRect geo=geometry();
	geo.setWidth(width);
	geo.setHeight(height);
	setGeometry(geo);

	return stelScene->sceneRect(); // retrieve what was finally available.
}

void StelMainView::bumpScreensaver()
{
#ifdef Q_OS_WIN
	EXECUTION_STATE state = SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
	if (state==NULL)
		qWarning() << "Cannot trigger screensaver inhibition";
#else
	qInfo() << "Screensaver deactivation not implemented on this operating system.";
#endif
}

// take action to inhibit screensaver when display is running in fullscreen mode
// private slot. Connect to fullScreenChanged(b)
void StelMainView::disableScreensaver(bool fullscreen)
{
	if (fullscreen)
	{
		//qInfo() << "Disabling screensaver while in fullscreen";
		screensaverInhibitorTimer = new QTimer(this);
		screensaverInhibitorTimer->setTimerType(Qt::VeryCoarseTimer);
		connect(screensaverInhibitorTimer, &QTimer::timeout, this, &StelMainView::bumpScreensaver);
		screensaverInhibitorTimer->start(30000); // Bump system every 30 seconds
	}
	else
	{
		//qInfo() << "Re-enabling screensaver while leaving fullscreen";
		if (screensaverInhibitorTimer)
		{
			screensaverInhibitorTimer->stop();
			delete screensaverInhibitorTimer;
			screensaverInhibitorTimer=nullptr;
#ifdef Q_OS_WIN
			EXECUTION_STATE state = SetThreadExecutionState(ES_CONTINUOUS);
			if (state==NULL)
				qWarning() << "Cannot disable screensaver inhibition";
#else
			qInfo() << "Screensaver reactivation not yet implemented on this platform.";
#endif
		}
	}
}
