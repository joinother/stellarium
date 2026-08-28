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
#include "StelLogger.hpp"
#include "StelProjector.hpp"
#include "StelPainter.hpp"
#include "StelGui.hpp"
#include "SkyGui.hpp"
#include "StelTranslator.hpp"
#include "StelUtils.hpp"
#include "SolarEclipseComputer.hpp"
#include "SpecificTimeMgr.hpp"
#include "planetsephems/sidereal_time.h"
#include "StelActionMgr.hpp"
#include "StelOpenGL.hpp"
#include "StelOpenGLArray.hpp"
#include "StelProjector.hpp"
#include "StelModuleMgr.hpp"
#include "modules/LabelMgr.hpp"
#include "StelMovementMgr.hpp"
#include "StelObject.hpp"
#include "StelObjectMgr.hpp"
#include "StelObserver.hpp"
#include "StelLocaleMgr.hpp"
#include "StelSkyCultureMgr.hpp"
#include "StelSkyLayerMgr.hpp"
#include "StelSkyImageTile.hpp"
#include "LandscapeMgr.hpp"
#include "Nebula.hpp"
#include "NebulaMgr.hpp"
#include "SporadicMeteorMgr.hpp"
#include "../plugins/Oculars/src/Oculars.hpp"
#include "../plugins/AngleMeasure/src/AngleMeasure.hpp"
#include "../plugins/Satellites/src/Satellites.hpp"
#include "../plugins/MeteorShowers/src/MeteorShowersMgr.hpp"
#include "../plugins/MeteorShowers/src/MeteorShower.hpp"
#include "../plugins/MeteorShowers/src/MeteorShowers.hpp"
#include "StelScriptMgr.hpp"
#include "SolarSystem.hpp"
#include "ConstellationMgr.hpp"
#include "Constellation.hpp"
#include "AsterismMgr.hpp"
#include "StelLocationMgr.hpp"
#include "StarMgr.hpp"
#include "GridLinesMgr.hpp"
#include "MilkyWay.hpp"
#include "ZodiacalLight.hpp"
#include "SpecialMarkersMgr.hpp"
#include "StelOhosCommandCatalog.hpp"

#ifndef STELLARIUM_OHOS_OFFLINE
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#endif
#include <QFile>

#include <QByteArray>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QElapsedTimer>
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
#include <atomic>
#include <algorithm>
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
#include <QTextStream>
#include <QTextDocument>
#include <QtPlugin>
#include <QThread>
#include <QTimer>
#include <QVariantMap>
#include <QWidget>
#include <QWindow>
#include <QMessageBox>
#include <QStandardPaths>
#include <functional>
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
#include <limits>
#include <clocale>
#if defined(__OHOS__)
#include <dlfcn.h>
#include <EGL/egl.h>
#include <hilog/log.h>
#include <QtGui/qopenglcontext_platform.h>
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
using OhosSubmitTextureFunc = bool (*)(unsigned int, int, int, void*, void*);
// The CPU fallback still copies every frame GPU -> CPU -> GPU. Keep it below
// the display refresh rate, but do not cap it at 30 FPS when recent timings
// show a frame has enough headroom for fluid touch manipulation.
constexpr int OHOS_ZERO_COPY_INTERACTIVE_RENDER_INTERVAL_MS = 8; // 120 FPS on high-refresh displays.
// Keep the CPU fallback on the same high-refresh cadence. It may not reach
// 120 FPS on every device, but it must never trade image sharpness for speed.
constexpr int OHOS_FALLBACK_INTERACTIVE_RENDER_INTERVAL_MS = 8;
constexpr int OHOS_IDLE_RENDER_INTERVAL_MS = 33;        // 30 FPS once the scene settles.

// Once the dedicated render pump is running it owns presentation to the
// XComponent. The QGraphics paint path can still be entered by Qt, but must
// not submit a duplicate framebuffer to the native surface.
static bool s_ohosRenderPumpActive = false;
static bool s_ohosZeroCopyActive = false;
static bool s_ohosZeroCopySupported = true;
static std::atomic<bool> s_ohosApplicationForeground{true};
static std::atomic<bool> s_ohosScriptRenderHeartbeat{false};
static std::atomic<quint64> s_ohosSkippedGraphicsPaints{0};

// Lock-free FPS counter: updated by renderOhosFrameNow() on Qt thread,
// read by StellariumOhos_command("getFPS") on ArkUI thread.
static std::atomic<float> s_ohosRenderFps{0.0f};
// Updated on the Qt render thread and read by ArkTS without crossing the
// command queue. The edge guide must use the same projector as the star map:
// altitude/azimuth deltas are not a screen-space direction in wide fields.
static std::atomic<float> s_ohosSelectedScreenXRatio{0.0f};
static std::atomic<float> s_ohosSelectedScreenYRatio{0.0f};
static std::atomic<bool> s_ohosSelectedScreenValid{false};
static std::atomic<bool> s_ohosSelectedScreenVisible{false};

// Ignore delayed settle phases left behind by an earlier object selection.
static std::atomic<quint64> s_ohosNavigationSerial{0};
// Last ArkUI safe point. Layout changes should animate only the delta between
// two safe regions, never re-apply the full offset and drift the selected body.
static QString s_ohosSafeTargetObject;
static double s_ohosSafeTargetY = 0.0;
static double s_ohosSafeTargetHeight = 0.0;
// A manual zoom must preserve a selected body's current screen position. This
// is separate from Stellarium tracking, which intentionally recenters targets.
static QString s_ohosZoomAnchorObject;
static double s_ohosZoomAnchorXRatio = 0.5;
static double s_ohosZoomAnchorYRatio = 0.5;
// Automatic selection navigation owns the camera until its safe-area movement
// settles. Capturing an anchor before that would cancel the centering motion.
static double s_ohosSelectedAnchorHoldUntilSec = 0.0;

void ohosMark(const char* message)
{
	OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "StellariumCpp", "%{public}s", message);
}

int currentOhosRenderIntervalMs()
{
	if (!StelApp::isInitialized())
		return OHOS_IDLE_RENDER_INTERVAL_MS;
	if (!StelMainView::getInstance().needsMaxFPS())
		return OHOS_IDLE_RENDER_INTERVAL_MS;
	return s_ohosZeroCopyActive
		? OHOS_ZERO_COPY_INTERACTIVE_RENDER_INTERVAL_MS
		: OHOS_FALLBACK_INTERACTIVE_RENDER_INTERVAL_MS;
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
	static OhosSubmitTextureFunc submitTexture = nullptr;
	if (!resolved)
	{
		resolved = true;
		void* entryHandle = dlopen("libentry.so", RTLD_NOW | RTLD_NOLOAD);
		if (!entryHandle)
			entryHandle = dlopen("libentry.so", RTLD_NOW);
		submitFrame = reinterpret_cast<OhosSubmitFrameFunc>(entryHandle ? dlsym(entryHandle, "StellariumEntry_submitFrame")
													: dlsym(RTLD_DEFAULT, "StellariumEntry_submitFrame"));
		submitTexture = reinterpret_cast<OhosSubmitTextureFunc>(entryHandle ? dlsym(entryHandle, "StellariumEntry_submitTexture")
													: dlsym(RTLD_DEFAULT, "StellariumEntry_submitTexture"));
		qInfo() << "OpenHarmony native frame bridge" << (submitFrame ? "resolved." : "not found.");
		ohosMark(submitTexture ? "zero-copy frame bridge resolved" : (submitFrame ? "frame bridge resolved" : "frame bridge not found"));
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

	// The bridge has to synchronously copy the GL frame into the Native XComponent.
	// Favor motion while the sky is being manipulated, then restore detail once
	// the user has stopped. This avoids letting the smooth ArkUI shell outrun the
	// sky renderer during drags and pinch gestures.
	QOpenGLContext* currentContext = QOpenGLContext::currentContext();
	auto* nativeContext = currentContext ? currentContext->nativeInterface<QNativeInterface::QEGLContext>() : nullptr;
	const bool tryZeroCopy = submitTexture && s_ohosZeroCopySupported && nativeContext;

	// The old 25%/40% fallback made the effective displayed resolution only
	// about 13%/21% after the render scale, which is visibly blurred. Try the
	// shared GPU texture at native resolution from its very first frame; only a
	// confirmed driver failure falls back to the balanced CPU-copy scale.
	// Always keep the submitted framebuffer at native resolution. The shared
	// texture path avoids the copy cost when available; the CPU fallback may be
	// slower, but upscaling a reduced framebuffer would visibly blur labels and
	// stars during interaction.
	const double readbackScale = 1.0;
	const int readW = qMax(1, int(width * readbackScale));
	const int readH = qMax(1, int(height * readbackScale));

	// Create downsample FBO + texture (once)
	static GLuint s_readbackFBO = 0;
	static GLuint s_readbackTex = 0;
	static int s_readbackW = 0;
	static int s_readbackH = 0;
	if (s_readbackFBO == 0 || s_readbackW != readW || s_readbackH != readH)
	{
		if (s_readbackFBO == 0)
		{
			gl->glGenFramebuffers(1, &s_readbackFBO);
			gl->glGenTextures(1, &s_readbackTex);
		}
		glBindTexture(GL_TEXTURE_2D, s_readbackTex);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, readW, readH, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glBindTexture(GL_TEXTURE_2D, 0);
		s_readbackW = readW;
		s_readbackH = readH;
	}

	// Get QOpenGLExtraFunctions for glBlitFramebuffer
	QOpenGLExtraFunctions* extraFns = QOpenGLContext::currentContext()->extraFunctions();

	// Blit (downsample) from main framebuffer to readback FBO
	GLint mainFBO = 0;
	gl->glGetIntegerv(GL_FRAMEBUFFER_BINDING, &mainFBO);
	gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, mainFBO);
	gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, s_readbackFBO);
	gl->glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, s_readbackTex, 0);
	if (extraFns)
	{
		extraFns->glBlitFramebuffer(0, 0, width, height, 0, 0, readW, readH, GL_COLOR_BUFFER_BIT, GL_LINEAR);
	}

	// When both EGL contexts can join the same share group, the XComponent can
	// sample this texture directly. That removes the full-frame GPU -> CPU -> GPU
	// transfer which is the dominant source of motion stutter on HarmonyOS.
	if (tryZeroCopy)
	{
		gl->glFlush();
		if (submitTexture(s_readbackTex, readW, readH,
			reinterpret_cast<void*>(nativeContext->display()),
			reinterpret_cast<void*>(nativeContext->nativeContext())))
		{
			s_ohosZeroCopyActive = true;
			gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, mainFBO);
			gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, mainFBO);
			return;
		}
		s_ohosZeroCopyActive = false;
		s_ohosZeroCopySupported = false;
	}

	// Synchronous glReadPixels (PBO caused SIGSEGV on emulator due to glMapBufferRange)
	static QByteArray pixels;
	const int neededSize = readW * readH * 4;
	if (pixels.size() < neededSize)
		pixels.resize(neededSize);

	gl->glPixelStorei(GL_PACK_ALIGNMENT, 1);
	gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, s_readbackFBO);

	const double readPixelsStart = StelApp::getTotalRunTime();

	// Synchronous readback - blocks until GPU finishes, but is stable
	gl->glReadPixels(0, 0, readW, readH, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
	const unsigned char* rgba = reinterpret_cast<const unsigned char*>(pixels.constData());

	const double readPixelsEnd = StelApp::getTotalRunTime();

	gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, mainFBO);
	gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, mainFBO);

	const GLenum error = gl->glGetError();
	if (error != GL_NO_ERROR)
	{
		qWarning() << "OpenHarmony framebuffer readback failed:" << Qt::hex << error;
		return;
	}

	if (!rgba)
		return;
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

	const double submitFrameStart = StelApp::getTotalRunTime();
	submitFrame(rgba, readW, readH);
	const double submitFrameEnd = StelApp::getTotalRunTime();
	++submittedFrames;

	static int s_submitFrameCounter = 0;
	if ((s_submitFrameCounter++ % 30) == 0)
	{
		const double readMs = (readPixelsEnd - readPixelsStart) * 1000.0;
		const double submitMs = (submitFrameEnd - submitFrameStart) * 1000.0;
		OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "StellariumFps",
			"submitDetail: readPixels=%{public}.1fms submitFrame=%{public}.1fms rw=%{public}d rh=%{public}d fw=%{public}d fh=%{public}d",
			readMs, submitMs, readW, readH, width, height);
	}

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

struct OhosRtsCalendarJob
{
	QString key;
	StelObjectP object;
	QString name;
	double originalJD = 0.0;
	double firstLocalMidnight = 0.0;
	int totalDays = 0;
	int nextDay = 0;
	QJsonArray rows;
};

static OhosRtsCalendarJob* s_ohosRtsCalendarJob = nullptr;
static constexpr qint64 OHOS_RTS_CALENDAR_SLICE_MS = 18;

// Cross-thread command queue drained by the OHOS render pump
// (renderOhosFrameNow) on the Qt main thread every frame. OHOS Qt may
// drive rendering via a native vsync callback rather than the Qt event
// loop, so QMetaObject::invokeMethod(..., QueuedConnection) is not
// guaranteed to be pumped; we hand commands to the pump instead.
static QMutex s_ohosCmdQueueMutex;
static QList<std::function<void()>> s_ohosCmdQueue;
static std::atomic_bool s_ohosScriptStartPending{false};
static std::atomic_uint64_t s_ohosScriptStartGeneration{0};
// Device pose samples supersede one another. Keeping a dedicated latest-value
// slot prevents the render thread from replaying stale gyro positions.
static std::function<void()> s_pendingGyroCommand;
// View-altitude-based landscape auto-fade (port feature). When the observer
// TILTS THE VIEW DOWN toward the ground (lower view-center altitude), the
// ground texture gradually becomes transparent so the lower-hemisphere sky is
// revealed instead of being occluded by an opaque landscape. Capped so the
// ground fades away completely once the view has moved below the horizon.
// Driven every frame from renderOhosFrameNow().
static bool s_landscapeFadeWithZoom = true;
static float s_landscapeFadeSmooth = 0.f;
// Virtual pointing-stick target: after pointAtSky centers the view on a sky
// direction, select whatever object sits at screen-center on the NEXT frame
// (the projector is only refreshed during app.update, so a same-frame
// findAndSelect would use the stale, pre-move projection).
static bool s_pendingPointSelect = false;
// Virtual pointing-stick: smooth "gyroscope follow" tracking. When a watch (or
// any orientation source) streams alt|az with track=1, we remember the target
// J2000 direction and ease the view toward it every frame, so the on-screen sky
// follows the user's hand like a real gyroscope-equipped pointing stick.
static bool s_pointTracking = false;
static Vec3d s_trackTargetJ2000(0.0, 0.0, 1.0);
static const double s_trackLerpK = 0.18; // fraction of remaining angle per frame
// The first pose after enabling the sensor should not snap the sky away from
// the user's current view. Streamed gyro samples update the target while this
// short, one-time hand-off runs in the render loop.
static bool s_gyroTransitionArmed = false;
static bool s_gyroTransitionActive = false;
static Vec3d s_gyroTransitionStartJ2000(0.0, 0.0, 1.0);
static Vec3d s_gyroTransitionTargetJ2000(0.0, 0.0, 1.0);
static double s_gyroTransitionStartSec = 0.0;
static constexpr double OHOS_GYRO_HANDOFF_SECONDS = 0.35;
// A gyro pose and a selected-object screen anchor both own the camera
// direction. While the sensor drives the view, leave the anchor suspended.
static bool s_gyroViewActive = false;
// --- Manual view-control modes (OHOS bridge) -------------------------------
// s_viewLock ("固定目标位置"): keeps a selected body's last released screen
// position as the zoom anchor. Manual panning remains available.
static bool s_viewLock = false;
// s_verticalClamp ("卡在天顶↔天底"): when ON, finger drags are translated
// DIRECTLY into Δazimuth/Δaltitude (decoupled axes, via panView) instead of the
// native unproject-based dragView. This fixes two problems at once:
//   1. altitude is clamped to [-90°, +90°] inside panView, so you can reach the
//      zenith/nadir but never flip past them (no upside-down sky);
//   2. the native dragView unprojects both touch points and takes their azimuth
//      difference — near the poles the meridians converge, so a purely vertical
//      swipe that is slightly left/right of the screen centre produces a huge
//      azimuth delta and the view spins. Decoupling the axes eliminates that
//      parasitic rotation entirely: vertical finger motion only ever changes
//      altitude, horizontal motion only ever changes azimuth.
static bool s_verticalClamp = true;
// Momentum from a finger pan lives on the Qt render thread. The ArkTS gesture
// layer only supplies one final velocity; advancing it here avoids queuing a
// bridge call for every 16 ms animation tick when presentation is slower.
static bool s_ohosPanInertiaActive = false;
static bool s_ohosPinchActive = false;
static double s_ohosPinchAnchorRelaxUntilSec = 0.0;
enum class OhosPinchAnchorMode
{
	None,
	SelectedObject,
	SkyPoint
};
static OhosPinchAnchorMode s_ohosPinchAnchorMode = OhosPinchAnchorMode::None;
static Vec3d s_ohosPinchSkyPointJ2000(0.0, 0.0, 1.0);
static double s_ohosPinchTargetXRatio = 0.5;
static double s_ohosPinchTargetYRatio = 0.5;
static double s_ohosPanInertiaVx = 0.0; // viewport pixels per millisecond
static double s_ohosPanInertiaVy = 0.0;
static double s_ohosPanInertiaElapsedSec = 0.0;
static bool s_ohosCaptureSelectedAnchorAfterPan = false;

static void ohosApplyPanDelta(StelCore* core, double dx, double dy)
{
	if (!core)
		return;
	StelMovementMgr* movementMgr = core->getMovementMgr();
	if (!movementMgr)
		return;
	if (s_verticalClamp)
	{
		const StelProjectorP prj = core->getProjection(StelCore::FrameJ2000);
		const double ppr = prj ? static_cast<double>(prj->getPixelPerRadAtCenter()) : 0.0;
		if (ppr <= 1e-9)
			return;
		// ArkTS deltas describe finger motion. StelMovementMgr::panView moves
		// the camera, so the old signs made the sky travel against the hand in
		// both axes. Keep direct manipulation: drag right/up shows sky moving
		// right/up, and the render-thread inertia below inherits the same frame.
		movementMgr->panView(-dx / ppr, dy / ppr);
	}
	else
	{
		// The decoupled mode is the default on OHOS. Preserve the native path
		// only for callers that explicitly turn it off.
		movementMgr->dragView(0, 0, qRound(dx), qRound(dy));
	}
	// Manual panning takes ownership immediately. An in-flight selection move
	// must not write a stale camera direction on the next render frame.
	++s_ohosNavigationSerial;
	movementMgr->cancelAutoMove();
	movementMgr->setFlagTracking(false);
	// Every drag frame establishes the user's new intended target position
	// before the following render frame applies time-flow compensation.
	// A user drag takes ownership immediately; do not leave it waiting for an
	// earlier automatic-centering animation's safety window to expire.
	s_ohosSelectedAnchorHoldUntilSec = 0.0;
	s_ohosCaptureSelectedAnchorAfterPan = true;
}

static void ohosUpdatePanInertia(double dtSec)
{
	if (!s_ohosPanInertiaActive)
	{
		s_ohosPanInertiaActive = false;
		return;
	}
	const double safeDtSec = qBound(0.001, dtSec, 0.080);
	const double dtMs = safeDtSec * 1000.0;
	ohosApplyPanDelta(StelApp::getInstance().getCore(), s_ohosPanInertiaVx * dtMs, s_ohosPanInertiaVy * dtMs);
	s_ohosPanInertiaElapsedSec += safeDtSec;
	const double decay = std::pow(0.955, dtMs / 16.667);
	s_ohosPanInertiaVx *= decay;
	s_ohosPanInertiaVy *= decay;
	const double speed = std::hypot(s_ohosPanInertiaVx, s_ohosPanInertiaVy);
	if (speed < 0.010 || s_ohosPanInertiaElapsedSec > 1.8)
		s_ohosPanInertiaActive = false;
	else
		markOhosInteraction();
}
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
		if (s_ohosCmdQueue.isEmpty() && !s_pendingGyroCommand)
			return;
		batch = s_ohosCmdQueue;
		s_ohosCmdQueue.clear();
		if (s_pendingGyroCommand)
		{
			batch.append(std::move(s_pendingGyroCommand));
			s_pendingGyroCommand = {};
		}
	}
	markQtLoopRunning();
	// 只在批量大时才打日志，避免每帧一条 WARN 日志造成 IO 开销
	if (batch.size() > 4)
		OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "StellariumCpp", "ohosDrainCommandQueue ran n=%{public}d", (int)batch.size());
	for (auto& fn : batch)
		fn();
}

// Gradually fade the landscape as the observer zooms in and tilts the view
// down toward the ground. Zoom controls the primary fade and reaches complete
// transparency at maximum zoom; looking toward the nadir adds a softer fade
// without making the landscape disappear by itself. A selected object that is
// geometrically above the horizon but behind a local tree or ridge gets a
// temporary extra fade, so the selection marker remains useful.
// Reuses the engine's own transparency path: LandscapeMgr applies
// (1 - transparency) * landFader as the ground alpha, so pushing transparency
// toward 1.0 removes the landscape entirely once it would otherwise occlude
// the lower-hemisphere sky.
static void ohosUpdateLandscapeFadeWithZoom()
{
	if (!s_landscapeFadeWithZoom)
		return;
	StelApp* app = &StelApp::getInstance();
	if (!app || !app->isInitialized())
		return;
	StelCore* core = app->getCore();
	LandscapeMgr* lmgr = GETSTELMODULE(LandscapeMgr);
	if (!core || !lmgr)
		return;
	StelMovementMgr* mvmgr = core->getMovementMgr();
	if (!mvmgr)
		return;
	// Altitude (degrees) of the direction the camera points at screen-center.
	// +90 = straight up, 0 = horizon, -90 = straight down at the ground.
	const Vec3d vdir = mvmgr->getViewDirectionJ2000();
	Vec3d altAz = core->j2000ToAltAz(vdir, StelCore::RefractionOff);
	double altRad = 0.0, aziRad = 0.0;
	StelUtils::rectToSphe(&aziRad, &altRad, altAz);
	const double altView = altRad * 180.0 / M_PI;

	const auto smoothstep = [](double value) {
		value = qBound(0.0, value, 1.0);
		return value * value * (3.0 - 2.0 * value);
	};

	// Zooming in makes the ground progressively less useful. The normal view
	// remains opaque down to 60 deg FOV; the maximum useful zoom (4 deg) fades
	// it away entirely, even when the camera is still near the horizon.
	const double fov = mvmgr->getCurrentFov();
	const double zoomFade = smoothstep((60.0 - fov) / (60.0 - 4.0));

	// Tilting down is an additional, gentler cue. It starts before the horizon
	// and reaches 75% at the nadir, so the ground still has spatial context
	// unless the user also zooms all the way in.
	const double nadirFade = smoothstep((15.0 - altView) / (15.0 - -90.0)) * 0.75;
	double target = zoomFade + (1.0 - zoomFade) * nadirFade;

	// The sky object and its selection reticle are rendered before the local
	// landscape. If a selected object is above the mathematical horizon but the
	// current landscape texture covers that exact direction, keep the landscape
	// translucent enough for the object to remain identifiable. Do not apply
	// this while the user controls landscape opacity manually: disabling the
	// automatic fade is an explicit request for a fixed ground layer.
	StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
	if (objectMgr && !objectMgr->getSelectedObject().isEmpty())
	{
		const StelObjectP object = objectMgr->getSelectedObject().constFirst();
		const Vec3d objectAltAz = object->getAltAzPosAuto(core);
		double objectAz = 0.0;
		double objectAlt = 0.0;
		StelUtils::rectToSphe(&objectAz, &objectAlt, objectAltAz);
		const bool aboveHorizon = objectAlt >= 0.0;
		const float landscapeOpacity = lmgr->getLandscapeOpacity(objectAltAz);
		if (aboveHorizon && landscapeOpacity > 0.5f)
			target = qMax(target, 0.82);
	}
	// Smooth toward the target so the fade is gradual (slow trailing follow),
	// not a hard pop, while you are dragging the view.
	const float rate = 0.18f;
	float cur = s_landscapeFadeSmooth + (static_cast<float>(target) - s_landscapeFadeSmooth) * rate;
	s_landscapeFadeSmooth = cur;
	lmgr->setFlagLandscapeUseTransparency(true);
	lmgr->setLandscapeTransparency(static_cast<double>(cur));
}

// Called once per frame AFTER app.update(dt) (so the projector reflects the
// just-applied view direction). If pointAtSky recentered the view on a sky
// direction, select whatever object now sits at screen-center.
static void ohosProcessPendingPointSelect()
{
	if (!s_pendingPointSelect)
		return;
	s_pendingPointSelect = false;
	StelApp* app = &StelApp::getInstance();
	if (!app || !app->isInitialized())
		return;
	StelCore* core = app->getCore();
	StelObjectMgr* omgr = GETSTELMODULE(StelObjectMgr);
	if (!core || !omgr)
		return;
	const StelProjectorP prj = core->getProjection(StelCore::FrameJ2000);
	if (!prj)
		return;
	const Vec4i vp = prj->getViewport();
	const int cx = vp[2] / 2;
	const int cy = vp[3] / 2;
	omgr->findAndSelect(core, cx, cy);
}

// Called every frame BEFORE app.update(dt) while a watch/gyro source is
// streaming orientations (track=1). Eases the current view direction toward the
// latest target so the sky visually follows the user's hand (gyroscope feel).
static void ohosUpdatePointTracking()
{
	if (!s_pointTracking)
		return;
	StelApp* app = &StelApp::getInstance();
	if (!app || !app->isInitialized())
		return;
	StelCore* core = app->getCore();
	StelMovementMgr* mvmgr = core ? core->getMovementMgr() : nullptr;
	if (!core || !mvmgr)
		return;
	Vec3d cur = mvmgr->getViewDirectionJ2000();
	Vec3d next = cur + (s_trackTargetJ2000 - cur) * s_trackLerpK;
	if (next.normSquared() < 1e-9)
	{
		// cur and target are nearly antipodal; just snap.
		mvmgr->setViewDirectionJ2000(s_trackTargetJ2000);
		return;
	}
	next.normalize();
	mvmgr->setViewDirectionJ2000(next);
}

static void ohosUpdateGyroTransition()
{
	if (!s_gyroTransitionActive)
		return;
	StelApp* app = &StelApp::getInstance();
	if (!app || !app->isInitialized())
		return;
	StelCore* core = app->getCore();
	StelMovementMgr* mvmgr = core ? core->getMovementMgr() : nullptr;
	if (!mvmgr)
		return;
	const double elapsed = StelApp::getTotalRunTime() - s_gyroTransitionStartSec;
	const double progress = qBound(0.0, elapsed / OHOS_GYRO_HANDOFF_SECONDS, 1.0);
	const double eased = progress * progress * (3.0 - 2.0 * progress);
	Vec3d next = s_gyroTransitionStartJ2000 * (1.0 - eased) + s_gyroTransitionTargetJ2000 * eased;
	if (next.normSquared() > 1e-9)
	{
		next.normalize();
		mvmgr->setViewDirectionJ2000(next);
	}
	if (progress >= 1.0)
		s_gyroTransitionActive = false;
}

static void ohosUpdateSelectedScreenProjection()
{
	s_ohosSelectedScreenValid.store(false);
	s_ohosSelectedScreenVisible.store(false);
	StelApp* app = &StelApp::getInstance();
	if (!app || !app->isInitialized())
		return;
	StelCore* core = app->getCore();
	StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
	if (!core || !objectMgr || objectMgr->getSelectedObject().isEmpty())
		return;
	const StelProjectorP projector = core->getProjection(StelCore::FrameJ2000);
	if (!projector)
		return;
	const Vec4i viewport = projector->getViewport();
	if (viewport[2] <= 1 || viewport[3] <= 1)
		return;
	Vec3d projected;
	if (!projector->project(objectMgr->getSelectedObject().constFirst()->getJ2000EquatorialPos(core), projected))
		return;
	const float xRatio = static_cast<float>((projected[0] - viewport[0]) / viewport[2]);
	const float yRatio = static_cast<float>((viewport[1] + viewport[3] - 1 - projected[1]) / viewport[3]);
	s_ohosSelectedScreenXRatio.store(xRatio);
	s_ohosSelectedScreenYRatio.store(yRatio);
	s_ohosSelectedScreenVisible.store(projector->checkInViewport(projected));
	s_ohosSelectedScreenValid.store(true);
}

static void ohosCaptureSelectedZoomAnchor()
{
	// A selection change or an interrupted gesture must never reuse the
	// previous object's screen anchor. Clear first so every early return also
	// leaves no stale target for the render-loop maintainer.
	s_ohosZoomAnchorObject.clear();
	StelApp* app = &StelApp::getInstance();
	if (!app || !app->isInitialized())
		return;
	StelCore* core = app->getCore();
	StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
	if (!core || !objectMgr || objectMgr->getSelectedObject().isEmpty())
		return;
	const StelProjectorP projector = core->getProjection(StelCore::FrameJ2000);
	if (!projector)
		return;
	const Vec4i viewport = projector->getViewport();
	if (viewport[2] <= 1 || viewport[3] <= 1)
		return;
	const StelObjectP selectedObject = objectMgr->getSelectedObject().constFirst();
	Vec3d projected;
	if (!projector->project(selectedObject->getJ2000EquatorialPos(core), projected))
		return;
	s_ohosZoomAnchorObject = selectedObject->getEnglishName();
	s_ohosZoomAnchorXRatio = (projected[0] - viewport[0]) / viewport[2];
	s_ohosZoomAnchorYRatio = (viewport[1] + viewport[3] - 1 - projected[1]) / viewport[3];
}

static void ohosBeginPinchAnchor(double touchX, double touchY, double touchWidth, double touchHeight)
{
	s_ohosPinchAnchorMode = OhosPinchAnchorMode::None;
	StelApp* app = &StelApp::getInstance();
	if (!app || !app->isInitialized() || touchWidth <= 1.0 || touchHeight <= 1.0)
		return;
	StelCore* core = app->getCore();
	if (!core)
		return;
	const StelProjectorP projector = core->getProjection(StelCore::FrameJ2000);
	if (!projector)
		return;
	const Vec4i viewport = projector->getViewport();
	if (viewport[2] <= 1 || viewport[3] <= 1)
		return;

	s_ohosPinchTargetXRatio = qBound(0.0, touchX / touchWidth, 1.0);
	s_ohosPinchTargetYRatio = qBound(0.0, touchY / touchHeight, 1.0);
	StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
	if (objectMgr && !objectMgr->getSelectedObject().isEmpty())
	{
		Vec3d projected;
		const StelObjectP selectedObject = objectMgr->getSelectedObject().constFirst();
		if (projector->project(selectedObject->getJ2000EquatorialPos(core), projected)
			&& projector->checkInViewport(projected))
		{
			const double selectedTouchX = ((projected[0] - viewport[0]) / viewport[2]) * touchWidth;
			const double selectedTouchY = ((viewport[1] + viewport[3] - 1 - projected[1]) / viewport[3]) * touchHeight;
			const double threshold = qBound(48.0, qMin(touchWidth, touchHeight) * 0.08, 96.0);
			if (std::hypot(selectedTouchX - touchX, selectedTouchY - touchY) <= threshold)
			{
				ohosCaptureSelectedZoomAnchor();
				s_ohosPinchAnchorMode = OhosPinchAnchorMode::SelectedObject;
				return;
			}
		}
	}

	const double viewportX = viewport[0] + s_ohosPinchTargetXRatio * viewport[2];
	const double viewportY = viewport[1] + viewport[3] - 1 - s_ohosPinchTargetYRatio * viewport[3];
	if (projector->unProject(viewportX, viewportY, s_ohosPinchSkyPointJ2000))
	{
		s_ohosPinchSkyPointJ2000.normalize();
		s_ohosPinchAnchorMode = OhosPinchAnchorMode::SkyPoint;
	}
}

static void ohosUpdatePinchTarget(double touchX, double touchY, double touchWidth, double touchHeight)
{
	if (s_ohosPinchAnchorMode != OhosPinchAnchorMode::SkyPoint || touchWidth <= 1.0 || touchHeight <= 1.0)
		return;
	s_ohosPinchTargetXRatio = qBound(0.0, touchX / touchWidth, 1.0);
	s_ohosPinchTargetYRatio = qBound(0.0, touchY / touchHeight, 1.0);
}

static void ohosMaintainPinchSkyAnchor()
{
	if (!s_ohosPinchActive || s_ohosPinchAnchorMode != OhosPinchAnchorMode::SkyPoint || s_gyroViewActive)
		return;
	StelApp* app = &StelApp::getInstance();
	if (!app || !app->isInitialized())
		return;
	StelCore* core = app->getCore();
	StelMovementMgr* movementMgr = core ? core->getMovementMgr() : nullptr;
	if (!core || !movementMgr)
		return;
	const StelProjectorP projector = core->getProjection(StelCore::FrameJ2000);
	if (!projector)
		return;
	const Vec4i viewport = projector->getViewport();
	if (viewport[2] <= 1 || viewport[3] <= 1)
		return;
	Vec3d projected;
	if (!projector->project(s_ohosPinchSkyPointJ2000, projected))
		return;
	const double desiredX = viewport[0] + s_ohosPinchTargetXRatio * viewport[2];
	const double desiredY = viewport[1] + viewport[3] - 1 - s_ohosPinchTargetYRatio * viewport[3];
	if (std::abs(desiredX - projected[0]) < 1.5 && std::abs(desiredY - projected[1]) < 1.5)
		return;
	movementMgr->dragView(qRound(projected[0]), qRound(projected[1]), qRound(desiredX), qRound(desiredY));
}

static void ohosDeferSelectedAnchor(double seconds)
{
	s_ohosZoomAnchorObject.clear();
	s_ohosSelectedAnchorHoldUntilSec = StelApp::getTotalRunTime() + qMax(0.0, seconds);
	qInfo() << "[StellariumOhos][anchor] deferred for" << seconds << "seconds";
}

static void ohosMaintainSelectedZoomAnchor()
{
	if (s_gyroViewActive)
		return;
	StelApp* app = &StelApp::getInstance();
	if (!app || !app->isInitialized())
		return;
	// Script tours own selection, zoom and camera movement. Applying the
	// user's manual selection anchor here would fight autoZoomIn/zoomTo and
	// leave each scripted target off-center.
	if (app->getScriptMgr().scriptIsRunning())
		return;
	if (StelApp::getTotalRunTime() < s_ohosSelectedAnchorHoldUntilSec)
		return;
	StelCore* core = app->getCore();
	StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
	StelMovementMgr* movementMgr = core ? core->getMovementMgr() : nullptr;
	if (!core || !objectMgr || !movementMgr || objectMgr->getSelectedObject().isEmpty())
		return;
	const StelObjectP selectedObject = objectMgr->getSelectedObject().constFirst();
	if (selectedObject->getEnglishName() != s_ohosZoomAnchorObject)
	{
		ohosCaptureSelectedZoomAnchor();
		qInfo() << "[StellariumOhos][anchor] captured" << selectedObject->getEnglishName();
		return;
	}
	const StelProjectorP projector = core->getProjection(StelCore::FrameJ2000);
	if (!projector)
		return;
	const Vec4i viewport = projector->getViewport();
	if (viewport[2] <= 1 || viewport[3] <= 1)
		return;
	Vec3d projected;
	if (!projector->project(selectedObject->getJ2000EquatorialPos(core), projected))
		return;
	const double desiredX = viewport[0] + s_ohosZoomAnchorXRatio * viewport[2];
	const double desiredY = viewport[1] + viewport[3] - 1
		- s_ohosZoomAnchorYRatio * viewport[3];
	const double deltaX = desiredX - projected[0];
	const double deltaY = desiredY - projected[1];
	// The projector and the native drag API both quantize to framebuffer
	// pixels. Avoid alternating one-pixel corrections while a pinch is still
	// changing the FOV; the subpixel error is invisible, the oscillation is not.
	const double deadband = (s_ohosPinchActive || StelApp::getTotalRunTime() < s_ohosPinchAnchorRelaxUntilSec) ? 2.0 : 1.25;
	if (std::abs(deltaX) < deadband && std::abs(deltaY) < deadband)
		return;
	// Do not approximate pixels as altitude/azimuth deltas here. That drifts at
	// wide fields and near the poles. dragView unprojects both screen points in
	// the current projection, so it preserves the selected body's exact screen
	// position regardless of the active projection or FOV.
	movementMgr->dragView(qRound(projected[0]), qRound(projected[1]),
		qRound(desiredX), qRound(desiredY));
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
	// Fire-and-forget view commands (zoomBy / zoomStep / dragView / panBy) are called
	// rapidly, never polled for a result, and often repeat with identical
	// args. Routing them through the consume-on-read store would let a stale
	// cached result be returned on the next identical call WITHOUT executing
	// (execute/skip/execute...). So bypass the store: always enqueue a fresh
	// execution and return pending; the caller ignores the return value.
	{
		const QString cmdName = key.section('|', 0, 0);
		if (cmdName == "setGyroView")
		{
			QMutexLocker qlock(&s_ohosCmdQueueMutex);
			s_pendingGyroCommand = [command]() { command(); };
			result["ok"] = false;
			result["error"] = "pending";
			result["pending"] = true;
			return QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact));
		}
		if (cmdName == "zoomBy" || cmdName == "zoomStep" || cmdName == "endPinch" || cmdName == "beginSkyGesture" || cmdName == "dragView" || cmdName == "panBy" || cmdName == "moveToAltAz" || cmdName == "gyroDiagnostic" || cmdName == "startPanInertia" || cmdName == "stopPanInertia")
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

// 由光谱型（如 "A1V"）估算有效温度(K)，供 ArkTS 音乐引擎把"越热音越高"映射成音高。
// 仅做音乐用途的近似：按光谱型字母取该型代表温度，再用亚型号数字微调。
static int ohosTemperatureFromSpType(const QString& sp)
{
	if (sp.isEmpty())
		return 0;
	const QChar c = sp.at(0).toUpper();
	int base = 0;
	switch (c.unicode())
	{
		case 'O': base = 30000; break;
		case 'B': base = 20000; break;
		case 'A': base = 8750;  break;
		case 'F': base = 6750;  break;
		case 'G': base = 5600;  break;
		case 'K': base = 4450;  break;
		case 'M': base = 3500;  break;
		case 'L': base = 2200;  break;
		case 'T': base = 1400;  break;
		case 'W': base = 50000; break; // Wolf-Rayet：极热
		case 'C': base = 4200;  break; // 碳星
		case 'S': base = 3200;  break; // S 型星
		default:  base = 0;     break;
	}
	if (base > 0 && sp.length() > 1)
	{
		const int digit = sp.at(1).digitValue();
		if (digit >= 0 && digit <= 9)
		{
			// 亚型号 0 最热、9 最冷：在本型带宽内做轻微线性降温
			const double width = base * 0.16;
			base = int(base - width * 0.5 + width * (digit / 9.0));
		}
	}
	return base;
}

QJsonObject constellationDetailMediaJson(const StelObjectP& object)
{
	QJsonObject result;
	if (!object || object->getType() != Constellation::CONSTELLATION_TYPE)
		return result;

	const QString abbreviation = object->getID();
	if (abbreviation.isEmpty())
		return result;

	auto imagePathForCulture = [&abbreviation](const StelSkyCulture& culture, const QString& cultureId) {
		for (const QJsonValue& constellation : culture.constellations)
		{
			if (!constellation.isObject())
				continue;
			const QJsonObject record = constellation.toObject();
			const QStringList idParts = record.value(QStringLiteral("id")).toString().split(' ', Qt::SkipEmptyParts);
			if (idParts.size() != 3 || idParts.at(0) != QStringLiteral("CON") || idParts.at(2) != abbreviation)
				continue;
			const QString imageFile = record.value(QStringLiteral("image")).toObject().value(QStringLiteral("file")).toString();
			if (!imageFile.isEmpty())
				return QStringLiteral("skycultures/%1/%2").arg(cultureId, imageFile);
		}
		return QString();
	};

	StelSkyCultureMgr& skyCultureMgr = StelApp::getInstance().getSkyCultureMgr();
	const QString currentCultureId = skyCultureMgr.getCurrentSkyCultureID();
	const QMap<QString, StelSkyCulture> cultures = skyCultureMgr.getDirToNameMap();
	QString rawPath = imagePathForCulture(cultures.value(currentCultureId), currentCultureId);
	QString label = QStringLiteral("当前天空文化星座绘图");

	// The IAU culture intentionally contains only stick figures. Its 88
	// abbreviations are identical to the modern culture, which supplies the
	// corresponding original illustrations.
	if (rawPath.isEmpty() && currentCultureId == QStringLiteral("modern_iau"))
	{
		rawPath = imagePathForCulture(cultures.value(QStringLiteral("modern")), QStringLiteral("modern"));
		label = QStringLiteral("现代星座绘图");
	}
	if (rawPath.isEmpty())
		return result;

	result[QStringLiteral("detailMediaPath")] = rawPath;
	result[QStringLiteral("detailMediaKind")] = QStringLiteral("constellation");
	result[QStringLiteral("detailMediaLabel")] = label;
	return result;
}

// Complete object prose is expensive to generate. Initial selections need it for
// the detail sheet, but the 300ms live refresh only needs the changing values.
QJsonObject selectedObjectJson(StelCore* core = nullptr, bool includeDetails = false)
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
	if (object->getType() == QLatin1String("Nebula"))
	{
		const NebulaP nebula = qSharedPointerCast<Nebula>(object);
		const QString catalogId = nebula->getDSODesignationWIC();
		if (!catalogId.isEmpty())
			result["catalogId"] = catalogId;
	}
	const QJsonObject detailMedia = constellationDetailMediaJson(object);
	for (auto it = detailMedia.constBegin(); it != detailMedia.constEnd(); ++it)
		result[it.key()] = it.value();

	if (core)
	{
		const QVariantMap m = object->getInfoMap(core);
		if (includeDetails)
		{
			QJsonArray detailFields;
			QSet<QString> emittedKeys;
			auto appendField = [&detailFields, &emittedKeys](const QString& key, const QString& section, QString value) {
				value.remove(QRegularExpression(QStringLiteral("<[^>]*>")));
				value.replace(QRegularExpression(QStringLiteral("[\\r\\n]+")), QStringLiteral(" · "));
				value = value.simplified();
				if (value.isEmpty() || value == QLatin1String("?") || value == QLatin1String("---") || emittedKeys.contains(key))
					return;
				QJsonObject field;
				field[QStringLiteral("key")] = key;
				field[QStringLiteral("section")] = section;
				field[QStringLiteral("value")] = value;
				detailFields.append(field);
				emittedKeys.insert(key);
			};
			auto appendText = [&m, &appendField](const QString& key, const QString& section, const QString& mapKey) {
				if (!m.contains(mapKey))
					return;
				const QVariant value = m.value(mapKey);
				QString text;
				if (value.metaType().id() == QMetaType::QStringList)
					text = value.toStringList().join(QStringLiteral(" · "));
				else
					text = value.toString();
				appendField(key, section, text);
			};
			auto appendLocalizedText = [&m, &appendField](const QString& key, const QString& section, const QString& mapKey) {
				if (!m.contains(mapKey))
					return;
				appendField(key, section, q_(m.value(mapKey).toString()));
			};
			auto appendNumber = [&m, &appendField](const QString& key, const QString& section, const QString& mapKey,
				int decimals, const QString& suffix = QString()) {
				if (!m.contains(mapKey))
					return;
				bool ok = false;
				const double number = m.value(mapKey).toDouble(&ok);
				if (!ok || !std::isfinite(number))
					return;
				appendField(key, section, QString::number(number, 'f', decimals) + suffix);
			};
			auto appendPositiveNumber = [&m, &appendNumber](const QString& key, const QString& section, const QString& mapKey,
				int decimals, const QString& suffix = QString()) {
				bool ok = false;
				const double number = m.value(mapKey).toDouble(&ok);
				if (ok && std::isfinite(number) && number > 0.0)
					appendNumber(key, section, mapKey, decimals, suffix);
			};
			auto appendScaledPositiveNumber = [&m, &appendField](const QString& key, const QString& section,
				const QString& mapKey, double scale, int decimals, const QString& suffix = QString()) {
				bool ok = false;
				const double number = m.value(mapKey).toDouble(&ok);
				if (ok && std::isfinite(number) && number > 0.0)
					appendField(key, section, QString::number(number * scale, 'f', decimals) + suffix);
			};
			auto appendNonZeroNumber = [&m, &appendField](const QString& key, const QString& section,
				const QString& mapKey, int decimals, const QString& suffix = QString()) {
				bool ok = false;
				const double number = m.value(mapKey).toDouble(&ok);
				if (ok && std::isfinite(number) && std::abs(number) > std::numeric_limits<double>::epsilon())
					appendField(key, section, QString::number(number, 'g', decimals) + suffix);
			};
			auto appendDegreePair = [&m, &appendField](const QString& key, const QString& section,
				const QString& firstKey, const QString& secondKey) {
				bool firstOk = false;
				bool secondOk = false;
				const double first = m.value(firstKey).toDouble(&firstOk);
				const double second = m.value(secondKey).toDouble(&secondOk);
				if (firstOk && secondOk && std::isfinite(first) && std::isfinite(second))
					appendField(key, section, QStringLiteral("%1°, %2°").arg(first, 0, 'f', 3).arg(second, 0, 'f', 3));
			};

			appendText(QStringLiteral("designations"), QStringLiteral("identity"), QStringLiteral("designations"));
			appendText(QStringLiteral("culturalNames"), QStringLiteral("identity"), QStringLiteral("cultural-names"));
			appendText(QStringLiteral("designation"), QStringLiteral("identity"), QStringLiteral("designation"));
			appendText(QStringLiteral("catalogNumber"), QStringLiteral("identity"), QStringLiteral("catalog"));
			appendText(QStringLiteral("internationalDesignator"), QStringLiteral("identity"), QStringLiteral("international-designator"));

			appendText(QStringLiteral("hourAngle"), QStringLiteral("coordinates"), QStringLiteral("hourAngle-hms"));
			if (m.contains(QStringLiteral("raJ2000")) && m.contains(QStringLiteral("decJ2000")))
			{
				const double raJ2000 = m.value(QStringLiteral("raJ2000")).toDouble() * M_PI / 180.0;
				const double decJ2000 = m.value(QStringLiteral("decJ2000")).toDouble() * M_PI / 180.0;
				appendField(QStringLiteral("equatorialJ2000"), QStringLiteral("coordinates"),
					StelUtils::radToHmsStr(raJ2000) + QStringLiteral("  ") + StelUtils::radToDmsStr(decJ2000, true));
			}
			appendDegreePair(QStringLiteral("geometricAltAz"), QStringLiteral("coordinates"),
				QStringLiteral("altitude-geometric"), QStringLiteral("azimuth-geometric"));
			appendDegreePair(QStringLiteral("eclipticCurrent"), QStringLiteral("coordinates"), QStringLiteral("elong"), QStringLiteral("elat"));
			appendDegreePair(QStringLiteral("eclipticJ2000"), QStringLiteral("coordinates"), QStringLiteral("elongJ2000"), QStringLiteral("elatJ2000"));
			appendDegreePair(QStringLiteral("galactic"), QStringLiteral("coordinates"), QStringLiteral("glong"), QStringLiteral("glat"));
			appendDegreePair(QStringLiteral("supergalactic"), QStringLiteral("coordinates"), QStringLiteral("sglong"), QStringLiteral("sglat"));
			appendNumber(QStringLiteral("parallacticAngle"), QStringLiteral("coordinates"), QStringLiteral("parallacticAngle"), 2, QStringLiteral("°"));

				auto appendMagnitude = [&m, &appendNumber](const QString& key, const QString& mapKey, const QString& suffix = QString()) {
					bool ok = false;
					const double magnitude = m.value(mapKey).toDouble(&ok);
					if (ok && std::isfinite(magnitude) && magnitude > -50.0 && magnitude < 50.0)
						appendNumber(key, QStringLiteral("observation"), mapKey, 2, suffix);
				};
				appendMagnitude(QStringLiteral("blueMagnitude"), QStringLiteral("bmag"));
				appendMagnitude(QStringLiteral("surfaceBrightness"), QStringLiteral("surface-brightness"), QStringLiteral(" 等/平方角分"));
			appendNumber(QStringLiteral("colorIndex"), QStringLiteral("observation"), QStringLiteral("bV"), 2);

			appendText(QStringLiteral("spectralClass"), QStringLiteral("physical"), QStringLiteral("spectral-class"));
			appendText(QStringLiteral("starType"), QStringLiteral("physical"), QStringLiteral("star-type"));
			appendText(QStringLiteral("morphology"), QStringLiteral("physical"), QStringLiteral("morpho"));
			appendNumber(QStringLiteral("redshift"), QStringLiteral("physical"), QStringLiteral("redshift"), 6);
			if (m.contains(QStringLiteral("axis-major-dms")) || m.contains(QStringLiteral("axis-minor-dms")))
			{
				const QString major = m.value(QStringLiteral("axis-major-dms")).toString();
				const QString minor = m.value(QStringLiteral("axis-minor-dms")).toString();
				appendField(QStringLiteral("angularAxes"), QStringLiteral("physical"),
					minor.isEmpty() ? major : QStringLiteral("%1 × %2").arg(major, minor));
			}
			appendNumber(QStringLiteral("positionAngle"), QStringLiteral("physical"), QStringLiteral("orientation-angle"), 1, QStringLiteral("°"));
			appendNumber(QStringLiteral("albedo"), QStringLiteral("physical"), QStringLiteral("albedo"), 3);

			if (m.contains(QStringLiteral("variable-star")))
			{
				appendText(QStringLiteral("variabilityType"), QStringLiteral("stellar"), QStringLiteral("variable-star"));
				appendPositiveNumber(QStringLiteral("stellarParallax"), QStringLiteral("stellar"), QStringLiteral("parallax"), 3, QStringLiteral(" mas"));
				appendNumber(QStringLiteral("stellarAbsoluteMagnitude"), QStringLiteral("stellar"), QStringLiteral("absolute-mag"), 2);
				appendPositiveNumber(QStringLiteral("stellarDistance"), QStringLiteral("stellar"), QStringLiteral("distance-ly"), 2, QStringLiteral(" 光年"));
				appendPositiveNumber(QStringLiteral("variabilityPeriod"), QStringLiteral("stellar"), QStringLiteral("period"), 6, QStringLiteral(" 天"));
				appendPositiveNumber(QStringLiteral("doubleStarObservationYear"), QStringLiteral("stellar"), QStringLiteral("wds-year"), 0);
				appendNumber(QStringLiteral("doubleStarPositionAngle"), QStringLiteral("stellar"), QStringLiteral("wds-position-angle"), 1, QStringLiteral("°"));
				appendPositiveNumber(QStringLiteral("doubleStarSeparation"), QStringLiteral("stellar"), QStringLiteral("wds-separation"), 2, QStringLiteral("″"));
			}

			appendNumber(QStringLiteral("heliocentricDistance"), QStringLiteral("orbit"), QStringLiteral("heliocentric-distance"), 4, QStringLiteral(" AU"));
			appendText(QStringLiteral("phaseAngle"), QStringLiteral("orbit"), QStringLiteral("phase-angle-dms"));
			if (m.contains(QStringLiteral("is-waning")))
				appendField(QStringLiteral("illuminationTrend"), QStringLiteral("orbit"),
					m.value(QStringLiteral("is-waning")).toBool() ? QStringLiteral("waning") : QStringLiteral("waxing"));
			appendPositiveNumber(QStringLiteral("orbitalSpeed"), QStringLiteral("orbit"), QStringLiteral("velocity-kms"), 3, QStringLiteral(" km/s"));
			appendPositiveNumber(QStringLiteral("heliocentricSpeed"), QStringLiteral("orbit"), QStringLiteral("heliocentric-velocity-kms"), 3, QStringLiteral(" km/s"));
			appendNumber(QStringLiteral("centralLongitude"), QStringLiteral("surface"), QStringLiteral("central_l"), 2, QStringLiteral("°"));
			appendNumber(QStringLiteral("centralLatitude"), QStringLiteral("surface"), QStringLiteral("central_b"), 2, QStringLiteral("°"));
			appendNumber(QStringLiteral("rotationAxisAngle"), QStringLiteral("surface"), QStringLiteral("pa_axis"), 2, QStringLiteral("°"));
			appendNumber(QStringLiteral("subsolarLongitude"), QStringLiteral("surface"), QStringLiteral("subsolar_l"), 2, QStringLiteral("°"));
			appendNumber(QStringLiteral("subsolarLatitude"), QStringLiteral("surface"), QStringLiteral("subsolar_b"), 2, QStringLiteral("°"));
			bool eclipseOk = false;
			const double eclipseMagnitude = m.value(QStringLiteral("eclipse-magnitude")).toDouble(&eclipseOk);
			if (eclipseOk && std::isfinite(eclipseMagnitude) && eclipseMagnitude > 0.0)
			{
				appendScaledPositiveNumber(QStringLiteral("eclipseObscuration"), QStringLiteral("surface"), QStringLiteral("eclipse-obscuration"), 1.0, 2, QStringLiteral("%"));
				appendPositiveNumber(QStringLiteral("eclipseMagnitude"), QStringLiteral("surface"), QStringLiteral("eclipse-magnitude"), 3);
				appendNumber(QStringLiteral("eclipseCrescentAngle"), QStringLiteral("surface"), QStringLiteral("eclipse-crescent-angle"), 2, QStringLiteral("°"));
			}

			appendText(QStringLiteral("moonPhaseName"), QStringLiteral("lunar"), QStringLiteral("phase-name"));
			appendPositiveNumber(QStringLiteral("moonAge"), QStringLiteral("lunar"), QStringLiteral("age"), 2, QStringLiteral(" 天"));
			appendNumber(QStringLiteral("librationLongitude"), QStringLiteral("lunar"), QStringLiteral("libration_l"), 2, QStringLiteral("°"));
			appendNumber(QStringLiteral("librationLatitude"), QStringLiteral("lunar"), QStringLiteral("libration_b"), 2, QStringLiteral("°"));
			appendNumber(QStringLiteral("colongitude"), QStringLiteral("lunar"), QStringLiteral("colongitude"), 2, QStringLiteral("°"));
			appendPositiveNumber(QStringLiteral("penumbralMagnitude"), QStringLiteral("lunar"), QStringLiteral("penumbral-eclipse-magnitude"), 3);
			appendPositiveNumber(QStringLiteral("umbralMagnitude"), QStringLiteral("lunar"), QStringLiteral("umbral-eclipse-magnitude"), 3);

			appendPositiveNumber(QStringLiteral("tailLength"), QStringLiteral("comet"), QStringLiteral("tail-length-km"), 0, QStringLiteral(" km"));
			appendPositiveNumber(QStringLiteral("comaDiameter"), QStringLiteral("comet"), QStringLiteral("coma-diameter-km"), 0, QStringLiteral(" km"));

			if (m.contains(QStringLiteral("tle-epoch")))
			{
				appendLocalizedText(QStringLiteral("description"), QStringLiteral("satellite"), QStringLiteral("description"));
				appendText(QStringLiteral("tleEpoch"), QStringLiteral("satellite"), QStringLiteral("tle-epoch"));
				appendText(QStringLiteral("tleLine1"), QStringLiteral("satellite"), QStringLiteral("tle1"));
				appendText(QStringLiteral("tleLine2"), QStringLiteral("satellite"), QStringLiteral("tle2"));
				appendPositiveNumber(QStringLiteral("range"), QStringLiteral("satellite"), QStringLiteral("range"), 1, QStringLiteral(" km"));
				appendNumber(QStringLiteral("rangeRate"), QStringLiteral("satellite"), QStringLiteral("rangerate"), 3, QStringLiteral(" km/s"));
				appendPositiveNumber(QStringLiteral("height"), QStringLiteral("satellite"), QStringLiteral("height"), 1, QStringLiteral(" km"));
				appendDegreePair(QStringLiteral("subpoint"), QStringLiteral("satellite"), QStringLiteral("subpoint-lat"), QStringLiteral("subpoint-long"));
				appendNumber(QStringLiteral("inclination"), QStringLiteral("satellite"), QStringLiteral("inclination"), 2, QStringLiteral("°"));
				appendPositiveNumber(QStringLiteral("orbitalPeriod"), QStringLiteral("satellite"), QStringLiteral("period"), 2, QStringLiteral(" 分"));
				appendPositiveNumber(QStringLiteral("perigeeAltitude"), QStringLiteral("satellite"), QStringLiteral("perigee-altitude"), 0, QStringLiteral(" km"));
				appendPositiveNumber(QStringLiteral("apogeeAltitude"), QStringLiteral("satellite"), QStringLiteral("apogee-altitude"), 0, QStringLiteral(" km"));
				appendPositiveNumber(QStringLiteral("sunReflectionAngle"), QStringLiteral("satellite"), QStringLiteral("sun-reflection-angle"), 2, QStringLiteral("°"));
				appendText(QStringLiteral("operationalStatus"), QStringLiteral("satellite"), QStringLiteral("operational-status"));
				appendLocalizedText(QStringLiteral("visibility"), QStringLiteral("satellite"), QStringLiteral("visibility"));
			}

			appendText(QStringLiteral("hostStarName"), QStringLiteral("plugin"), QStringLiteral("starProperName"));
			appendText(QStringLiteral("hostStarAliases"), QStringLiteral("plugin"), QStringLiteral("starAltNames"));
			appendText(QStringLiteral("hostSpectralType"), QStringLiteral("plugin"), QStringLiteral("stype"));
			if (m.contains(QStringLiteral("starProperName")) || m.contains(QStringLiteral("hasHabitablePlanets")))
				appendPositiveNumber(QStringLiteral("hostDistance"), QStringLiteral("plugin"), QStringLiteral("distance"), 2, QStringLiteral(" pc"));
			appendPositiveNumber(QStringLiteral("hostMass"), QStringLiteral("plugin"), QStringLiteral("smass"), 3, QStringLiteral(" M☉"));
			appendNumber(QStringLiteral("hostMetallicity"), QStringLiteral("plugin"), QStringLiteral("smetal"), 3);
			appendPositiveNumber(QStringLiteral("hostRadius"), QStringLiteral("plugin"), QStringLiteral("sradius"), 3, QStringLiteral(" R☉"));
			appendPositiveNumber(QStringLiteral("effectiveTemperature"), QStringLiteral("plugin"), QStringLiteral("effectiveTemp"), 0, QStringLiteral(" K"));
			if (m.contains(QStringLiteral("hasHabitablePlanets")))
				appendField(QStringLiteral("hasHabitablePlanets"), QStringLiteral("plugin"),
					m.value(QStringLiteral("hasHabitablePlanets")).toBool() ? QStringLiteral("yes") : QStringLiteral("no"));

			appendText(QStringLiteral("novaType"), QStringLiteral("plugin"), QStringLiteral("nova-type"));
			appendText(QStringLiteral("supernovaType"), QStringLiteral("plugin"), QStringLiteral("sntype"));
			appendNumber(QStringLiteral("maximumMagnitude"), QStringLiteral("plugin"), QStringLiteral("max-magnitude"), 2);
			appendNumber(QStringLiteral("minimumMagnitude"), QStringLiteral("plugin"), QStringLiteral("min-magnitude"), 2);
			appendPositiveNumber(QStringLiteral("peakJulianDay"), QStringLiteral("plugin"), QStringLiteral("peakJD"), 3);
			appendPositiveNumber(QStringLiteral("declineTwoMagnitudes"), QStringLiteral("plugin"), QStringLiteral("m2"), 2, QStringLiteral(" 天"));
			appendPositiveNumber(QStringLiteral("declineThreeMagnitudes"), QStringLiteral("plugin"), QStringLiteral("m3"), 2, QStringLiteral(" 天"));
			appendPositiveNumber(QStringLiteral("declineSixMagnitudes"), QStringLiteral("plugin"), QStringLiteral("m6"), 2, QStringLiteral(" 天"));
			appendPositiveNumber(QStringLiteral("declineNineMagnitudes"), QStringLiteral("plugin"), QStringLiteral("m9"), 2, QStringLiteral(" 天"));
			if (m.contains(QStringLiteral("peakJD")) && !m.contains(QStringLiteral("dmeasure")))
				appendScaledPositiveNumber(QStringLiteral("transientDistance"), QStringLiteral("plugin"), QStringLiteral("distance"), 1000.0, 2, QStringLiteral(" 光年"));
			appendText(QStringLiteral("notes"), QStringLiteral("plugin"), QStringLiteral("notes"));
			appendText(QStringLiteral("note"), QStringLiteral("plugin"), QStringLiteral("note"));

			appendNumber(QStringLiteral("absoluteMagnitude"), QStringLiteral("plugin"), QStringLiteral("amag"), 2);
			appendNumber(QStringLiteral("radioFlux6cm"), QStringLiteral("plugin"), QStringLiteral("f6"), 2, QStringLiteral(" Jy"));
			appendNumber(QStringLiteral("radioFlux20cm"), QStringLiteral("plugin"), QStringLiteral("f20"), 2, QStringLiteral(" Jy"));
			appendText(QStringLiteral("sourceClass"), QStringLiteral("plugin"), QStringLiteral("sclass"));

			if (m.contains(QStringLiteral("dmeasure")) || m.contains(QStringLiteral("bperiod")))
			{
				appendPositiveNumber(QStringLiteral("annualParallax"), QStringLiteral("plugin"), QStringLiteral("parallax"), 3, QStringLiteral(" mas"));
				appendPositiveNumber(QStringLiteral("binaryPeriod"), QStringLiteral("plugin"), QStringLiteral("bperiod"), 6, QStringLiteral(" 天"));
				appendPositiveNumber(QStringLiteral("pulseFrequency"), QStringLiteral("plugin"), QStringLiteral("frequency"), 6, QStringLiteral(" Hz"));
				appendNonZeroNumber(QStringLiteral("frequencyDerivative"), QStringLiteral("plugin"), QStringLiteral("pfrequency"), 8, QStringLiteral(" Hz/s"));
				appendNonZeroNumber(QStringLiteral("periodDerivative"), QStringLiteral("plugin"), QStringLiteral("pderivative"), 8, QStringLiteral(" s/s"));
				appendPositiveNumber(QStringLiteral("pulsePeriod"), QStringLiteral("plugin"), QStringLiteral("period"), 9, QStringLiteral(" s"));
				appendPositiveNumber(QStringLiteral("dispersionMeasure"), QStringLiteral("plugin"), QStringLiteral("dmeasure"), 3, QStringLiteral(" pc/cm³"));
				appendNumber(QStringLiteral("eccentricity"), QStringLiteral("plugin"), QStringLiteral("eccentricity"), 6);
				appendPositiveNumber(QStringLiteral("electronDensityDistance"), QStringLiteral("plugin"), QStringLiteral("distance"), 3, QStringLiteral(" kpc"));
				appendPositiveNumber(QStringLiteral("distanceEstimate"), QStringLiteral("plugin"), QStringLiteral("adistance"), 3, QStringLiteral(" kpc"));
				appendPositiveNumber(QStringLiteral("profileWidth50"), QStringLiteral("plugin"), QStringLiteral("w50"), 2, QStringLiteral(" ms"));
				appendText(QStringLiteral("glitchCount"), QStringLiteral("plugin"), QStringLiteral("glitch"));
				appendPositiveNumber(QStringLiteral("flux400"), QStringLiteral("plugin"), QStringLiteral("s400"), 2, QStringLiteral(" mJy"));
				appendPositiveNumber(QStringLiteral("flux600"), QStringLiteral("plugin"), QStringLiteral("s600"), 2, QStringLiteral(" mJy"));
				appendPositiveNumber(QStringLiteral("flux1400"), QStringLiteral("plugin"), QStringLiteral("s1400"), 2, QStringLiteral(" mJy"));
			}

			appendText(QStringLiteral("meteorStatus"), QStringLiteral("plugin"), QStringLiteral("status"));
			appendText(QStringLiteral("meteorCode"), QStringLiteral("plugin"), QStringLiteral("id"));
			appendPositiveNumber(QStringLiteral("meteorVelocity"), QStringLiteral("plugin"), QStringLiteral("velocity"), 1, QStringLiteral(" km/s"));
			appendPositiveNumber(QStringLiteral("populationIndex"), QStringLiteral("plugin"), QStringLiteral("population-index"), 2);
			appendText(QStringLiteral("parentBody"), QStringLiteral("plugin"), QStringLiteral("parent"));
			appendText(QStringLiteral("maximumZhr"), QStringLiteral("plugin"), QStringLiteral("zhr-max"));

			result[QStringLiteral("detailFields")] = detailFields;
		}

		// Normalized magnitude (visual, no extinction)
		if (m.contains("vmag"))
			result["magnitude"] = m["vmag"].toDouble();
		// 观测条件：核心已计算大气消光后的星等和气团质量，直接透传给前端。
		if (m.contains("vmage"))
			result["apparentMagnitude"] = m["vmage"].toDouble();
		if (m.contains("airmass"))
		{
			const double airmass = m["airmass"].toDouble();
			if (airmass >= 0.0)
				result["airmass"] = airmass;
		}
		if (m.contains("vmag") && m.contains("vmage"))
			result["extinction"] = m["vmage"].toDouble() - m["vmag"].toDouble();

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

		// 音乐引擎所需：英文类型(便于分支) + 光谱型 + 推算温度(越热音越高)
		QString ohosType = object->getObjectType();
		if (!ohosType.isEmpty())
			result["objectType"] = ohosType;
		if (m.contains("spectral-class"))
		{
			const QString sp = m["spectral-class"].toString();
			result["spType"] = sp;
			const int tk = ohosTemperatureFromSpType(sp);
			if (tk > 0)
				result["temperatureK"] = tk;
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

		// Angular size (DSO / planets / Moon), formatted string
		if (m.contains("size-dms"))
			result["size"] = m["size-dms"].toString();

		// Rise / Set / Transit (local time strings; "---" when not applicable)
		if (m.contains("rise"))
			result["rise"] = m["rise"].toString();
		if (m.contains("set"))
			result["set"] = m["set"].toString();
		if (m.contains("transit"))
			result["transit"] = m["transit"].toString();

		// Phase (0..1 for solar-system bodies) -> percent
		if (m.contains("phase"))
			result["phase"] = m["phase"].toDouble() * 100.0;

		// Elongation (radians) -> degrees
		if (m.contains("elongation"))
			result["elongation"] = m["elongation"].toDouble() * 180.0 / M_PI;

	}
	return result;
}

QJsonObject currentStateJson()
{
	QJsonObject result;
	result["ok"] = true;
	// The ArkUI shell is rendered separately from Stellarium's Qt scene.  Return
	// the authoritative property here instead of inferring night mode from a UI action.
	result["nightMode"] = StelApp::getInstance().getVisionModeNight();

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
	if (core)
	{
		StelSkyDrawer* drawer = core->getSkyDrawer();
		if (drawer)
		{
			result["luminanceAdaptation"] = drawer->getFlagLuminanceAdaptation();
			result["starTwinkle"] = drawer->getFlagTwinkle();
			result["forcedStarTwinkle"] = drawer->getFlagForcedTwinkle();
			result["bigStarHalo"] = drawer->getFlagDrawBigStarHalo();
			result["starSpiky"] = drawer->getFlagStarSpiky();
			result["twinkleAmount"] = drawer->getTwinkleAmount();
			result["bortleScale"] = StelCore::luminanceToBortleScaleIndex(
				static_cast<float>(drawer->getLightPollutionLuminance()));
		}
	}
	if (SporadicMeteorMgr* mmgr = GETSTELMODULE(SporadicMeteorMgr))
		result["meteorZhr"] = mmgr->getZHR();
	if (MilkyWay* milkyWay = GETSTELMODULE(MilkyWay))
		result["milkyWayIntensity"] = milkyWay->getIntensity();
	if (ZodiacalLight* zlight = GETSTELMODULE(ZodiacalLight))
	{
		result["zodiacalLight"] = zlight->getFlagShow();
		result["zodiacalIntensity"] = zlight->getIntensity();
	}
	if (SpecialMarkersMgr* markerMgr = GETSTELMODULE(SpecialMarkersMgr))
	{
		result["fovCircularMarkerSize"] = markerMgr->getFOVCircularMarkerSize();
		result["fovRectangularMarkerWidth"] = markerMgr->getFOVRectangularMarkerWidth();
		result["fovRectangularMarkerHeight"] = markerMgr->getFOVRectangularMarkerHeight();
		result["fovRectangularMarkerRotation"] = markerMgr->getFOVRectangularMarkerRotationAngle();
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
			"actionShow_Planets_Trails",
			"actionShow_Planets_EnlargeMoon",
			"actionShow_Planets_EnlargePlanets",
			"actionShow_Planets_EnlargeSun",
			"actionShow_Planets_ShowMinorBodyMarkers",
			"actionShow_Planets_Nomenclature",
			"actionShow_Nebulas",
			"actionShow_DSO_Textures",
			"actionShow_MilkyWay",
			"actionShow_Fog",
			"actionShow_Ground",
			"actionShow_LandscapeIllumination",
			"actionShow_LandscapeLabels",
			"actionShow_Constellation_Lines",
			"actionShow_Constellation_Labels",
				"actionShow_Constellation_Boundaries",
				"actionShow_Constellation_Art",
				"actionShow_Constellation_Hulls",
			"actionShow_Zodiac",
			"actionShow_LunarSystem",
			"actionShow_Asterism_Lines",
			"actionShow_Asterism_Labels",
			"actionShow_Atmosphere",
			"actionShow_Cardinal_Points",
			"actionShow_Azimuthal_Grid",
			"actionShow_Equatorial_Grid",
			"actionShow_Equatorial_J2000_Grid",
			"actionShow_Ecliptic_Grid",
			"actionShow_Ecliptic_J2000_Grid",
			"actionShow_Galactic_Grid",
			"actionShow_Supergalactic_Grid",
			"actionShow_Fixed_Equatorial_Grid",
			"actionShow_Fixed_Equator_Line",
			"actionShow_Equator_Line",
			"actionShow_Ecliptic_Line",
			"actionShow_Galactic_Equator_Line",
			"actionShow_Supergalactic_Equator_Line",
			"actionShow_Equator_J2000_Line",
			"actionShow_Ecliptic_J2000_Line",
			"actionShow_Meridian_Line",
			"actionShow_Horizon_Line",
			"actionShow_Celestial_Poles",
			"actionShow_Ecliptic_Poles",
			"actionShow_Galactic_Poles",
			"actionShow_Equinox_Points",
			"actionShow_Solstice_Points",
			"actionShow_Antisolar_Point",
			"actionShow_Umbra_Circle",
			"actionShow_Penumbra_Circle",
				"actionShow_Compass_Marks",
				"actionShow_Gridlines",
			"actionShow_FOV_Center_Marker",
			"actionShow_FOV_Circular_Marker",
			"actionShow_FOV_Rectangular_Marker",
			"actionShow_Intercardinal_Points",
			"actionShow_Secondary_Intercardinal_Points",
			"actionShow_Tertiary_Intercardinal_Points",
			"actionShow_Prime_Vertical_Line",
			"actionShow_Current_Vertical_Line",
			"actionShow_Colure_Lines",
			"actionShow_Precession_Circles",
			"actionShow_Circumpolar_Circles",
			"actionShow_Invariable_Plane_Line",
			"actionShow_Solar_Equator_Line",
			"actionShow_Zenith_Nadir",
			"actionShow_Celestial_J2000_Poles",
			"actionShow_Ecliptic_J2000_Poles",
			"actionShow_Equinox_J2000_Points",
			"actionShow_Solstice_J2000_Points",
			"actionShow_Galactic_Center",
			"actionShow_Supergalactic_Poles",
			"actionShow_Apex_Points",
			"actionShow_Umbra_Center_Point",
			"actionShow_Longitude_Line",
				"actionShow_Quadrature_Line",
				"actionShow_Ray_Helpers",
			"actionShow_Hips_Surveys",
			"actionShow_Toast_Survey"
		};
		for (const QString& id : ids)
		{
			StelAction* action = actionMgr->findAction(id);
			if (action && action->isCheckable())
				result[id] = action->isChecked();
		}

		if (SporadicMeteorMgr* mmgr = GETSTELMODULE(SporadicMeteorMgr))
			result["meteors"] = mmgr->getFlagShow();
		if (NebulaMgr* nmgr = GETSTELMODULE(NebulaMgr))
			result["dsoLabels"] = nmgr->getDesignationUsage();
		if (movementMgr)
			result["autoZoomResets"] = movementMgr->getFlagAutoZoomOutResetsDirection();

		return result;
	}

	return result;
}

namespace {
// OHOS 星表下载器：把 ConfigurationDialog 里耦合 UI 的下载逻辑抽成不依赖界面的版本，
// 通过 N-API 命令桥触发；进度由 ArkTS 侧轮询 getStarCatalogStatus 获取（桥是请求-响应模式，无 C++→ArkTS 推送）。
#ifndef STELLARIUM_OHOS_OFFLINE
struct StarCatalogDownloader
{
	QPointer<QNetworkReply> reply;
	QFile* file = nullptr;
	QVariantMap target;
	QString id;
	qint64 bytes = 0;
	bool done = false;
	bool error = false;
	QString errorStr;
	bool md5ok = false;

	void connectReply(QNetworkReply* r)
	{
		QObject::connect(r, &QNetworkReply::readyRead, [this, r]() {
			if (!file) return;
			qint64 sz = r->bytesAvailable();
			bytes += sz;
			file->write(r->read(sz));
		});
		QObject::connect(r, &QNetworkReply::finished, [this]() { onFinished(); });
		QObject::connect(r, QOverload<QNetworkReply::NetworkError>::of(&QNetworkReply::errorOccurred),
		                 [this](QNetworkReply::NetworkError) { onError(); });
	}

	void start(const QString& catalogId)
	{
		reset();
		StarMgr* sm = GETSTELMODULE(StarMgr);
		if (!sm) { error = true; errorStr = "no StarMgr"; done = true; return; }
		QVariantMap found;
		for (const QVariant& v : sm->getCatalogsDescription())
		{
			QVariantMap m = v.toMap();
			if (m.value("id").toString() == catalogId) { found = m; break; }
		}
		if (found.isEmpty()) { error = true; errorStr = "catalog not found: " + catalogId; done = true; return; }
		target = found; id = catalogId;
		QString fileName = found.value("fileName").toString();
		QString path = StelFileMgr::getUserDir() + "/stars/hip_gaia3/" + fileName;
		file = new QFile(path);
		if (!file->open(QIODevice::WriteOnly)) {
			qWarning() << "[StellariumOhos] cannot open star catalog file:" << QDir::toNativeSeparators(path);
			error = true; errorStr = "cannot open file: " + path; done = true;
			delete file; file = nullptr; return;
		}
		QNetworkRequest req(found.value("url").toString());
		req.setAttribute(QNetworkRequest::CacheSaveControlAttribute, false);
		req.setAttribute(QNetworkRequest::RedirectionTargetAttribute, false);
		req.setRawHeader("User-Agent", StelUtils::getUserAgentString().toLatin1());
		reply = StelApp::getInstance().getNetworkAccessManager()->get(req);
		reply->setReadBufferSize(1024*1024*2);
		connectReply(reply);
		qInfo() << "[StellariumOhos] star catalog download start:" << catalogId << found.value("url").toString();
	}

	void onFinished()
	{
		if (!reply) return;
		if (reply->error() != QNetworkReply::NoError) { onError(); return; }
		QVariant redirect = reply->attribute(QNetworkRequest::RedirectionTargetAttribute);
		if (!redirect.isNull())
		{
			// SourceForge 的 /download URL 会 302 跳转到 CDN，跟随重定向。
			QNetworkRequest req(redirect.toUrl());
			req.setAttribute(QNetworkRequest::CacheSaveControlAttribute, false);
			req.setAttribute(QNetworkRequest::RedirectionTargetAttribute, false);
			req.setRawHeader("User-Agent", StelUtils::getUserAgentString().toLatin1());
			QNetworkReply* old = reply;
			reply = StelApp::getInstance().getNetworkAccessManager()->get(req);
			reply->setReadBufferSize(1024*1024*2);
			connectReply(reply);
			old->deleteLater();
			return;
		}
		if (file) { file->close(); file->deleteLater(); file = nullptr; }
		StarMgr* sm = GETSTELMODULE(StarMgr);
		if (sm) md5ok = sm->checkAndLoadCatalog(target, true);
		done = true;
		qInfo() << "[StellariumOhos] star catalog download finished:" << id << "md5ok=" << md5ok;
		if (reply) { reply->deleteLater(); reply = nullptr; }
	}

	void onError()
	{
		error = true;
		errorStr = reply ? reply->errorString() : QString("unknown");
		done = true;
		qWarning() << "[StellariumOhos] star catalog download error:" << id << errorStr;
		if (file) { file->close(); file->deleteLater(); file = nullptr; }
		if (reply) { reply->deleteLater(); reply = nullptr; }
	}

	void reset()
	{
		if (file) { file->close(); delete file; file = nullptr; }
		if (reply) { reply->deleteLater(); reply = nullptr; }
		bytes = 0; done = false; error = false; errorStr.clear(); md5ok = false; target.clear(); id.clear();
	}
};
static StarCatalogDownloader g_starDownloader;
#endif
constexpr int OHOS_SATELLITE_CATALOG_MAX_AGE_DAYS = 14;
constexpr int OHOS_STAR_CATALOG_MAX_AGE_DAYS = 180;

double catalogAgeDays(const QDateTime& checkedAt)
{
	if (!checkedAt.isValid())
		return -1.0;
	return qMax(0.0, checkedAt.toUTC().secsTo(QDateTime::currentDateTimeUtc()) / 86400.0);
}

QJsonObject catalogStatus(const QString& status, const QDateTime& checkedAt, int maxAgeDays)
{
	QJsonObject result;
	result["status"] = status;
	result["checkedAt"] = checkedAt.isValid() ? checkedAt.toUTC().toString(Qt::ISODate) : QString();
	result["ageDays"] = catalogAgeDays(checkedAt);
	result["maxAgeDays"] = maxAgeDays;
	return result;
}

QJsonObject getOhosCatalogHealth()
{
	QJsonObject result;
	QJsonObject satellites = catalogStatus("unknown", QDateTime(), OHOS_SATELLITE_CATALOG_MAX_AGE_DAYS);
	QJsonObject stars = catalogStatus("unknown", QDateTime(), OHOS_STAR_CATALOG_MAX_AGE_DAYS);
	QString manifestPath;
	try { manifestPath = StelFileMgr::findFile(QStringLiteral("data/ohos/catalog-manifest.json")); }
	catch (...) { manifestPath.clear(); }

	QFile manifestFile(manifestPath);
	QJsonParseError parseError;
	const bool opened = !manifestPath.isEmpty() && manifestFile.open(QIODevice::ReadOnly);
	const QJsonDocument manifest = opened ? QJsonDocument::fromJson(manifestFile.readAll(), &parseError) : QJsonDocument();
	if (!opened || parseError.error != QJsonParseError::NoError || !manifest.isObject())
	{
		result["manifestPresent"] = false;
		result["satellites"] = satellites;
		result["stars"] = stars;
		return result;
	}

	result["manifestPresent"] = true;
	const QJsonObject catalogs = manifest.object().value("catalogs").toObject();
	const QJsonObject satelliteManifest = catalogs.value("satellites").toObject();
	const QDateTime satelliteUpdatedAt = QDateTime::fromString(satelliteManifest.value("fetchedAt").toString(), Qt::ISODate);
	const double satelliteAge = catalogAgeDays(satelliteUpdatedAt);
	const bool partial = satelliteManifest.value("partial").toBool(false);
	const bool verified = satelliteManifest.value("verified").toBool(false);
	const bool satelliteIntegrityFailure = !verified && !partial;
	const bool satelliteStale = !satelliteUpdatedAt.isValid() || satelliteAge > OHOS_SATELLITE_CATALOG_MAX_AGE_DAYS || satelliteIntegrityFailure;
	satellites = catalogStatus(satelliteStale ? "stale" : (partial ? "attention" : "current"), satelliteUpdatedAt, OHOS_SATELLITE_CATALOG_MAX_AGE_DAYS);
	satellites["verified"] = verified;
	satellites["partial"] = partial;
	satellites["sourceErrors"] = satelliteManifest.value("sourceErrors").toArray().size();
	satellites["entries"] = satelliteManifest.value("entries").toInt();

	const QJsonObject starManifest = catalogs.value("stars").toObject();
	const QDateTime starsCheckedAt = QDateTime::fromString(starManifest.value("checkedAt").toString(), Qt::ISODate);
	const double starsAge = catalogAgeDays(starsCheckedAt);
	const bool starsVerified = starManifest.value("verified").toBool(false);
	QJsonArray missingFiles;
	for (const QJsonValue& fileValue : starManifest.value("files").toArray())
	{
		const QJsonObject file = fileValue.toObject();
		const QString fileName = file.value("file").toString();
		const qint64 expectedBytes = qint64(file.value("bytes").toDouble());
		QString filePath;
		try { filePath = StelFileMgr::findFile(QStringLiteral("stars/hip_gaia3/%1").arg(fileName)); }
		catch (...) { filePath.clear(); }
		const QFileInfo fileInfo(filePath);
		if (fileName.isEmpty() || !fileInfo.isFile() || (expectedBytes > 0 && fileInfo.size() != expectedBytes))
			missingFiles.append(fileName);
	}
	const bool starStale = !starsCheckedAt.isValid() || starsAge > OHOS_STAR_CATALOG_MAX_AGE_DAYS || !starsVerified || !missingFiles.isEmpty();
	stars = catalogStatus(starStale ? "stale" : "current", starsCheckedAt, OHOS_STAR_CATALOG_MAX_AGE_DAYS);
	stars["verified"] = starsVerified;
	stars["missingFiles"] = missingFiles;
	stars["files"] = starManifest.value("files").toArray().size();

	result["satellites"] = satellites;
	result["stars"] = stars;
	return result;
}

// ---- Bookmarks store (OHOS bridge) ----
// 保存当前视图（J2000 视方向单位向量 + 视场 + 选中天体名）到 userDir/bookmarks.json
struct BookmarkItem
{
	QString id;
	QString name;
	double vx = 0, vy = 0, vz = 1;   // view direction (J2000 equatorial, unit vector)
	double fov = 60;
	QString object;                 // selected object display name (optional)
};
static QList<BookmarkItem> g_bookmarks;
static bool g_bookmarksLoaded = false;

static QString bookmarksPath()
{
	return StelFileMgr::getUserDir() + "/bookmarks.json";
}

static void bookmarksLoad()
{
	g_bookmarks.clear();
	QFile f(bookmarksPath());
	if (f.open(QIODevice::ReadOnly))
	{
		const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
		f.close();
		if (doc.isArray())
		{
			for (const QJsonValue& v : doc.array())
			{
				const QJsonObject o = v.toObject();
				BookmarkItem it;
				it.id = o.value("id").toString();
				it.name = o.value("name").toString();
				it.vx = o.value("vx").toDouble();
				it.vy = o.value("vy").toDouble();
				it.vz = o.value("vz").toDouble();
				it.fov = o.value("fov").toDouble();
				it.object = o.value("object").toString();
				g_bookmarks.append(it);
			}
		}
	}
	g_bookmarksLoaded = true;
}

static void bookmarksSave()
{
	QJsonArray arr;
	for (const BookmarkItem& it : g_bookmarks)
	{
		QJsonObject o;
		o["id"] = it.id;
		o["name"] = it.name;
		o["vx"] = it.vx;
		o["vy"] = it.vy;
		o["vz"] = it.vz;
		o["fov"] = it.fov;
		o["object"] = it.object;
		arr.append(o);
	}
	QFile f(bookmarksPath());
	if (f.open(QIODevice::WriteOnly))
	{
		f.write(QJsonDocument(arr).toJson());
		f.close();
	}
}

// ---- Script recordings store (OHOS bridge) ----
// 把 ArkTS 侧录制的命令序列（searchObject / setTimeRate / ...）持久化到
// userDir/recordings/<name>.json，供「脚本录制 / 回放」面板保存与重放。
struct RecordingItem
{
	QString file;    // 文件名（不含目录），如 20260723-203000.json
	QString name;    // 显示名
	QString created; // 创建时间字符串
	int count = 0;   // 命令条数
};
static QString recordingsDir()
{
	QString dir = StelFileMgr::getUserDir() + "/recordings";
	QDir d(dir);
	if (!d.exists())
		d.mkpath(dir);
	return dir;
}
static QList<RecordingItem> recordingsList()
{
	QList<RecordingItem> out;
	QDir dir(recordingsDir());
	const QStringList files = dir.entryList(QStringList() << "*.json", QDir::Files, QDir::Time);
	for (const QString& f : files)
	{
		RecordingItem it;
		it.file = f;
		QFile file(dir.filePath(f));
		if (file.open(QIODevice::ReadOnly))
		{
			const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
			file.close();
			const QJsonObject o = doc.object();
			it.name = o.value("name").toString(f);
			it.created = o.value("created").toString("");
			it.count = o.value("commands").toArray().size();
		}
		out.append(it);
	}
	return out;
}

// ---- Video frames recorder (OHOS bridge) ----
// 当前 OpenHarmony 基础 SDK 不含视频编码器，因此先实现“帧序列录制”：
// 按设定 fps 定时调用 saveScreenShot，保存到 userDir/videos/<timestamp>/frame_*.jpg。
// 用户可在外部把这些帧合成为真正视频。
struct VideoRecorder
{
	bool recording = false;
	QString dir;
	int fps = 1;
	int frameCount = 0;
	int maxFrames = 0;
	QTimer* timer = nullptr;
};
static VideoRecorder g_videoRecorder;

static void videoCaptureFrame()
{
	if (!g_videoRecorder.recording)
		return;
	if (g_videoRecorder.frameCount >= g_videoRecorder.maxFrames)
	{
		g_videoRecorder.recording = false;
		if (g_videoRecorder.timer)
			g_videoRecorder.timer->stop();
		return;
	}
	QString prefix = QString("frame_%1").arg(g_videoRecorder.frameCount++, 5, 10, QChar('0'));
	StelMainView::getInstance().saveScreenShot(prefix, g_videoRecorder.dir, true);
}

static QString videosDir()
{
	QString dir = StelFileMgr::getUserDir() + "/videos";
	QDir d(dir);
	if (!d.exists())
		d.mkpath(dir);
	return dir;
}

// 统计某视频目录下已生成的 frame_*.jpg 数量（用于上报真实落盘帧数）。
static int countVideoFrames(const QString& dir)
{
	QDir d(dir);
	if (!d.exists())
		return 0;
	int n = 0;
	QStringList entries = d.entryList(QStringList() << "frame_*.jpg" << "frame_*.jpeg" << "frame_*.png", QDir::Files);
	n = entries.size();
	return n;
}

}

extern "C" __attribute__((visibility("default"))) const char* StellariumOhos_command(const char* command, const char* payload)
{
	static QByteArray response;
	const QString commandName = QString::fromUtf8(command ? command : "");
	const QString arg = QString::fromUtf8(payload ? payload : "");
	// 高频命令（dragView/zoomBy/panBy）不打日志，避免每秒数十条 qInfo 造成 CPU/IO 开销
	if (commandName != "dragView" && commandName != "zoomBy" && commandName != "panBy" && commandName != "setGyroView" && commandName != "getGyroGuidePosition")
		qInfo() << "[StellariumOhos] command received:" << commandName << arg;

	// getFPS: read from a lock-free atomic updated by renderOhosFrameNow().
	// Avoids calling StelApp::getInstance().getFps() from the ArkUI thread
	// (not thread-safe) and avoids the async queue (which returns pending forever).
	if (commandName == "getFPS")
	{
		QJsonObject fpsResult;
		fpsResult["ok"] = true;
		fpsResult["fps"] = s_ohosRenderFps.load();
		response = QString::fromUtf8(QJsonDocument(fpsResult).toJson(QJsonDocument::Compact)).toUtf8();
		return response.constData();
	}
	if (commandName == "getGyroGuidePosition")
	{
		QJsonObject guideResult;
		guideResult["ok"] = true;
		guideResult["valid"] = s_ohosSelectedScreenValid.load();
		guideResult["visible"] = s_ohosSelectedScreenVisible.load();
		guideResult["xRatio"] = s_ohosSelectedScreenXRatio.load();
		guideResult["yRatio"] = s_ohosSelectedScreenYRatio.load();
		response = QString::fromUtf8(QJsonDocument(guideResult).toJson(QJsonDocument::Compact)).toUtf8();
		return response.constData();
	}
	if (commandName == "setApplicationForeground")
	{
		const bool foreground = arg == "1" || arg.compare("true", Qt::CaseInsensitive) == 0;
		s_ohosApplicationForeground.store(foreground);
		if (qApp && StelApp::isInitialized())
		{
			QMetaObject::invokeMethod(qApp, [foreground]() {
				if (StelApp::isInitialized())
					StelMainView::getInstance().setOhosApplicationForeground(foreground);
			}, Qt::QueuedConnection);
		}
		QJsonObject lifecycleResult;
		lifecycleResult["ok"] = true;
		lifecycleResult["foreground"] = foreground;
		response = QString::fromUtf8(QJsonDocument(lifecycleResult).toJson(QJsonDocument::Compact)).toUtf8();
		return response.constData();
	}
	if (commandName == "setScreenSafeArea")
	{
		bool ok = false;
		const int topPixels = arg.toInt(&ok);
		QJsonObject safeAreaResult;
		if (!ok)
		{
			safeAreaResult["ok"] = false;
			safeAreaResult["error"] = "invalid safe area height";
		}
		else
		{
			LabelMgr::setOhosScreenSafeAreaTop(topPixels);
			safeAreaResult["ok"] = true;
			safeAreaResult["topPixels"] = qMax(0, topPixels);
		}
		response = QString::fromUtf8(QJsonDocument(safeAreaResult).toJson(QJsonDocument::Compact)).toUtf8();
		return response.constData();
	}

	const QString json = runOhosCommandOnQtThread(commandName + "|" + arg, [commandName, arg]() -> QJsonObject {
		QJsonObject result;
		result["ok"] = false;
		if (commandName != "dragView" && commandName != "zoomBy" && commandName != "panBy" && commandName != "setGyroView" && commandName != "getGyroGuidePosition")
			qInfo() << "[StellariumOhos] command on Qt thread:" << commandName;

		StelActionMgr* actionMgr = StelApp::getInstance().getStelActionManager();
		StelCore* core = StelApp::getInstance().getCore();
		StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
		StelMovementMgr* movementMgr = GETSTELMODULE(StelMovementMgr);

		if (commandName == "getCommandCatalog")
		{
			result["ok"] = true;
			result["version"] = 1;
			result["offlineOnly"] = true;
			result["transport"] = "local-hdc-aa-want";
			result["commands"] = StellariumOhosCommandCatalog::all();
			return result;
		}
		if (commandName == "getCommandSchema")
		{
			const QString requested = arg.trimmed();
			const QJsonObject schema = StellariumOhosCommandCatalog::schema(requested);
			if (schema.isEmpty())
			{
				result["error"] = "unknown command";
				return result;
			}
			result["ok"] = true;
			result["schema"] = schema;
			return result;
		}
		if (commandName == "getCommandStatus")
		{
			const QString requested = arg.trimmed();
			const QJsonObject schema = StellariumOhosCommandCatalog::schema(requested);
			if (schema.isEmpty())
			{
				result["error"] = "unknown command";
				return result;
			}
			result["ok"] = true;
			result["available"] = true;
			result["loaded"] = true;
			result["restricted"] = schema.value("requiresConfirmation").toBool();
			result["network"] = !schema.value("offline").toBool();
			result["command"] = requested;
			return result;
		}
		if (commandName == "getCatalogHealth")
		{
			result["ok"] = true;
			const QJsonObject health = getOhosCatalogHealth();
			result["manifestPresent"] = health.value("manifestPresent").toBool(false);
			result["satellites"] = health.value("satellites").toObject();
			result["stars"] = health.value("stars").toObject();
			return result;
		}

		if (commandName == "setActionStates")
		{
			const QJsonDocument document = QJsonDocument::fromJson(arg.toUtf8());
			const QJsonArray states = document.isArray() ? document.array() : QJsonArray();
			int applied = 0;
			for (const QJsonValue& value : states)
			{
				const QJsonObject state = value.toObject();
				StelAction* action = actionMgr ? actionMgr->findAction(state.value("id").toString()) : nullptr;
				if (!action || !action->isCheckable())
					continue;
				action->setChecked(state.value("enabled").toBool());
				++applied;
			}
			markOhosInteraction();
			result["ok"] = true;
			result["applied"] = applied;
			return result;
		}

		if (commandName == "setFovMarkerSetting")
		{
			const QString setting = arg.section('|', 0, 0);
			bool parsed = false;
			const double value = arg.section('|', 1, 1).toDouble(&parsed);
			if (!parsed)
			{
				result["error"] = "invalid marker value";
				return result;
			}

			SpecialMarkersMgr* markerMgr = GETSTELMODULE(SpecialMarkersMgr);
			if (!markerMgr)
			{
				result["error"] = "marker manager unavailable";
				return result;
			}

			if (setting == "circleSize" && value >= 0.1 && value <= 180.0)
				markerMgr->setFOVCircularMarkerSize(value);
			else if (setting == "rectWidth" && value >= 0.1 && value <= 180.0)
				markerMgr->setFOVRectangularMarkerWidth(value);
			else if (setting == "rectHeight" && value >= 0.1 && value <= 180.0)
				markerMgr->setFOVRectangularMarkerHeight(value);
			else if (setting == "rectRotation" && value >= -180.0 && value <= 180.0)
				markerMgr->setFOVRectangularMarkerRotationAngle(value);
			else
			{
				result["error"] = "marker value out of range";
				return result;
			}

			markOhosInteraction();
			result["ok"] = true;
			return result;
		}

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

	if (commandName == "getAngleMeasure")
	{
		AngleMeasure* measure = GETSTELMODULE(AngleMeasure);
		if (!measure)
		{
			result["error"] = "AngleMeasure plugin not loaded";
			return result;
		}
		result["ok"] = true;
		result["enabled"] = measure->isEnabled();
		result["hasStart"] = measure->hasMeasurementStart();
		result["hasEnd"] = measure->hasMeasurementEnd();
		result["angleDegrees"] = measure->getMeasuredAngle() * M_180_PI;
		result["angleText"] = measure->getMeasuredAngleText();
		return result;
	}

	if (commandName == "resetAngleMeasure")
	{
		AngleMeasure* measure = GETSTELMODULE(AngleMeasure);
		if (!measure)
		{
			result["error"] = "AngleMeasure plugin not loaded";
			return result;
		}
		measure->resetMeasurement();
		result["ok"] = true;
		return result;
	}

	if (commandName == "angleMeasurePoint")
	{
		AngleMeasure* measure = GETSTELMODULE(AngleMeasure);
		if (!measure || !core)
		{
			result["error"] = "AngleMeasure plugin not loaded";
			return result;
		}
		const QStringList parts = arg.split('|');
		if (parts.size() < 2)
		{
			result["error"] = "angleMeasurePoint expects x|y or x|y|width|height";
			return result;
		}
		bool okX = false;
		bool okY = false;
		const double x = parts[0].toDouble(&okX);
		const double y = parts[1].toDouble(&okY);
		bool okW = false;
		bool okH = false;
		int skyW = 1440;
		int skyH = 960;
		if (parts.size() >= 4)
		{
			skyW = parts[2].toInt(&okW);
			skyH = parts[3].toInt(&okH);
		}
		if (!okX || !okY)
		{
			result["error"] = "invalid angle measurement point";
			return result;
		}
		const StelProjectorP prj = core->getProjection(StelCore::FrameJ2000);
		const Vec4i vp = prj->getViewport();
		const double scaleX = (okW && skyW > 0) ? static_cast<double>(vp[2]) / skyW : static_cast<double>(vp[2]) / 1440.0;
		const double scaleY = (okH && skyH > 0) ? static_cast<double>(vp[3]) / skyH : static_cast<double>(vp[3]) / 960.0;
		const double sx = x * scaleX;
		const double sy = vp[3] - 1.0 - y * scaleY;
		if (!measure->isEnabled())
			measure->enableAngleMeasure(true);
		if (!measure->setPointFromScreen(sx, sy))
		{
			result["error"] = "unable to project measurement point";
			return result;
		}
		markOhosInteraction();
		result["ok"] = true;
		result["enabled"] = measure->isEnabled();
		result["hasStart"] = measure->hasMeasurementStart();
		result["hasEnd"] = measure->hasMeasurementEnd();
		result["angleDegrees"] = measure->getMeasuredAngle() * M_180_PI;
		result["angleText"] = measure->getMeasuredAngleText();
		return result;
	}

	if (commandName == "selftestActions")
	{
		QStringList ids = arg.split('|', Qt::SkipEmptyParts);
		QStringList missingIds;
		for (const QString& id : ids)
		{
			StelAction* a = actionMgr ? actionMgr->findAction(id) : nullptr;
			if (!a) missingIds.append(id);
		}
		result["ok"] = true;
		result["total"] = ids.size();
		result["missing"] = missingIds.size();
		qInfo() << "[StellariumOhos] selftest_summary total=" << ids.size() << "missing=" << missingIds.size();
		for (const QString& m : missingIds)
			qInfo() << "[StellariumOhos] selftest_missing" << m;
		return result;
	}

	if (commandName == "getStarCatalogs")
	{
		StarMgr* sm = GETSTELMODULE(StarMgr);
		QJsonArray arr;
		if (sm)
		{
			for (const QVariant& v : sm->getCatalogsDescription())
				arr.append(QJsonObject::fromVariantMap(v.toMap()));
		}
		result["ok"] = true;
		result["catalogs"] = arr;
		return result;
	}

	if (commandName == "downloadStarCatalog")
	{
	#ifdef STELLARIUM_OHOS_OFFLINE
		result["ok"] = false;
		result["error"] = "offline build: catalog downloads are disabled";
	#else
		g_starDownloader.start(arg);
		result["ok"] = true;
		result["started"] = true;
		result["id"] = arg;
	#endif
		return result;
	}

	if (commandName == "getStarCatalogStatus")
	{
	#ifdef STELLARIUM_OHOS_OFFLINE
		result["ok"] = true;
		result["state"] = "disabled";
		result["error"] = "offline build: catalog downloads are disabled";
	#else
		result["ok"] = true;
		result["id"] = g_starDownloader.id;
		result["state"] = g_starDownloader.done ? (g_starDownloader.error ? QString("error") : QString("done")) : QString("downloading");
		result["bytes"] = (qint64)g_starDownloader.bytes;
		result["error"] = g_starDownloader.errorStr;
		result["md5ok"] = g_starDownloader.md5ok;
	#endif
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

			const QStringList searchParts = arg.split('|');
			QString query = searchParts.value(0).trimmed();
			const bool selectOnly = searchParts.contains(QStringLiteral("selectOnly"), Qt::CaseInsensitive);
			QString preferredModule;
			bool found = false;
			if (query == QLatin1String("object") && searchParts.size() >= 3)
			{
				const QString objectType = searchParts.value(1).trimmed();
				const QString objectId = searchParts.value(2).trimmed();
				const StelObjectP object = objectMgr->searchByID(objectType, objectId);
				if (object)
				{
					found = objectMgr->setSelectedObject(object);
					query = object->getEnglishName();
				}
				else
				{
					qWarning() << "[StellariumOhos][search-select] object not found type="
							<< objectType << "id=" << objectId;
				}
			}
			if (query == QLatin1String("catalog") && searchParts.size() >= 3)
			{
				const QString moduleId = searchParts.value(1).trimmed();
				const QString objectId = searchParts.value(2).trimmed();
				// Catalog subsets use names such as "StarMgr:1". The lookup API
				// belongs to StarMgr itself, so normalise the subset suffix first.
				preferredModule = moduleId.section(':', 0, 0).toLower();
				query = objectId;
				const auto objects = objectMgr->listAllModuleObjects(moduleId, true);
				qInfo() << "[StellariumOhos][catalog-select] module=" << moduleId
						<< "id=" << objectId << "candidates=" << objects.size();
				for (const auto& pair : objects)
				{
					if (pair.second && (pair.second->getID() == objectId
							|| pair.second->getEnglishName() == objectId
							|| pair.first == objectId))
					{
						found = objectMgr->setSelectedObject(pair.second);
						query = pair.second->getEnglishName();
						qInfo() << "[StellariumOhos][catalog-select] found=" << found
								<< "name=" << pair.second->getEnglishName()
								<< "id=" << pair.second->getID();
						break;
					}
				}
				if (!found)
					qWarning() << "[StellariumOhos][catalog-select] not found module=" << moduleId << "id=" << objectId;
			}

			// A catalog page stores the object's stable ID, while the module index
			// can temporarily refresh on a different schedule. Resolve the two
			// catalog types that have dedicated lookup APIs before falling back to
			// the global index, otherwise e.g. Leo may be reported missing or be
			// claimed by Leo Meteor Shower instead of the constellation.
			if (!found && !query.isEmpty() && preferredModule == QLatin1String("constellationmgr"))
			{
				if (auto* constellationMgr = GETSTELMODULE(ConstellationMgr))
				{
					StelObjectP constellation = constellationMgr->searchByName(query);
					if (!constellation)
						constellation = constellationMgr->searchByNameI18n(query);
					if (constellation)
						found = objectMgr->setSelectedObject(constellation);
				}
			}
			else if (!found && !query.isEmpty() && preferredModule == QLatin1String("starmgr"))
			{
				if (auto* starMgr = GETSTELMODULE(StarMgr))
				{
					StelObjectP star = starMgr->searchByName(query);
					if (!star)
						star = starMgr->searchByNameI18n(query);
					if (star)
						found = objectMgr->setSelectedObject(star);
				}
			}
			if (!found)
			{
				found = !query.isEmpty() && (objectMgr->findAndSelectI18n(query) || objectMgr->findAndSelect(query));
			}
			// Constellation names are culture data. Some cultures do not expose
			// them through the generic object-manager index, so query their module
			// directly before reporting a false "not found" result.
			if (!found && !query.isEmpty())
			{
				if (auto* constellationMgr = GETSTELMODULE(ConstellationMgr))
				{
					StelObjectP constellation = constellationMgr->searchByName(query);
					if (!constellation)
						constellation = constellationMgr->searchByNameI18n(query);
					if (constellation)
						found = objectMgr->setSelectedObject(constellation);
				}
			}
			const bool selectedObserverPlanet = found && core && !objectMgr->getSelectedObject().isEmpty()
				&& core->getCurrentPlanet()
				&& objectMgr->getSelectedObject().constFirst()->getEnglishName().compare(
					core->getCurrentPlanet()->getEnglishName(), Qt::CaseInsensitive) == 0;
			if (found && !objectMgr->getSelectedObject().isEmpty()
				&& objectMgr->getSelectedObject().constFirst()->getType().compare(
					QLatin1String("Nebula"), Qt::CaseInsensitive) == 0)
			{
				if (auto* skyLayerMgr = GETSTELMODULE(StelSkyLayerMgr))
				{
					skyLayerMgr->setFlagShow(true);
					StelAction* reloadAction = actionMgr ? actionMgr->findAction("actionShow_DSO_Textures_Reload") : nullptr;
					if (reloadAction)
					{
						reloadAction->trigger();
						qInfo() << "[dso-textures] reloaded after deep-sky selection:"
							<< objectMgr->getSelectedObject().constFirst()->getEnglishName();
					}
				}
			}
			if (found && !selectOnly && movementMgr && !objectMgr->getSelectedObject().isEmpty() && !selectedObserverPlanet)
			{
				const StelObjectP target = objectMgr->getSelectedObject().first();
				const QString type = target->getType().toLower();
				const QString englishName = target->getEnglishName().toLower();
				// Target FOV tuned for phone-screen visibility:
				//   planets/sun/moon ~1.5° (large enough to see disk/detail)
				//   stars           ~0.8° (tight on the point source + label)
				//   nebulae/galaxies ~6°  (show extended structure context)
				//   constellations  ~45° (show pattern across sky)
				//   default          ~3°  (generic object, reasonably close)
				double targetFov = 3.0;
				if (type.contains("constellation"))
					targetFov = 45.0;
				else if (type.contains("planet") || englishName == "sun" || englishName == "moon")
					targetFov = 1.5;
				else if (type.contains("star") || type.contains("star_object"))
					targetFov = 0.8;
				else if (type.contains("nebula") || type.contains("galaxy") || type.contains("cluster"))
					targetFov = 6.0;
				else if (type.contains("satellite"))
					targetFov = 30.0;

				// ArkUI's moveToSelectedAt is the single owner of search
				// navigation. Starting a second delayed zoom here caused the target
				// to move again after it had already been placed in the safe area.
				movementMgr->cancelAutoMove();
				movementMgr->setFlagTracking(false);
				qInfo() << "[StellariumOhos][navigate]" << target->getEnglishName()
						<< "type=" << type << "single-owner=ArkUI";
				result["navigationTargetFov"] = targetFov;
			}
			markOhosInteraction();

			// FullInfo expands a large rich-text block and can take a visible slice
			// of a frame on a tablet. Return the data needed to open the card now;
			// ArkTS requests the long prose after the selection/navigation settles.
			result = selectedObjectJson(core, false);
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
		const QString query = prefix.trimmed();
		auto normalizeSearchText = [](QString value) {
			// Search input can come from a keyboard, IME, voice input, or a
			// catalog alias. Normalize equivalent Unicode forms before matching.
			value = value.normalized(QString::NormalizationForm_KC).toCaseFolded();
			const QString decomposed = value.normalized(QString::NormalizationForm_D);
			QString folded;
			folded.reserve(decomposed.size());
			for (int index = 0; index < decomposed.size(); ++index)
			{
				const QChar character = decomposed.at(index);
				const QChar previous = index > 0 ? decomposed.at(index - 1) : QChar();
				const bool latinLikeMark = character.category() == QChar::Mark_NonSpacing
					&& (previous.script() == QChar::Script_Latin
						|| previous.script() == QChar::Script_Greek
						|| previous.script() == QChar::Script_Cyrillic);
				if (latinLikeMark)
					continue;
				const int digit = character.digitValue();
				if (digit >= 0)
					folded.append(QChar(QLatin1Char('0').unicode() + digit));
				else
					folded.append(character);
			}
			folded.remove(QRegularExpression(QStringLiteral("[\\p{P}\\p{S}\\s]+")));
			return folded;
		};
		const QString normalizedQuery = normalizeSearchText(query);
		struct SearchCandidate
		{
			QString label;
			StelObjectP object;
			int rank;
			bool crossLanguage = false;
		};
		QVector<SearchCandidate> candidates;
		QHash<QString, int> candidateIndexes;
		auto addCandidate = [&](const QString& label, const StelObjectP& object, int forcedRank = -1, bool crossLanguage = false)
		{
			if (!object || label.trimmed().isEmpty() || normalizedQuery.isEmpty())
				return;
			const QString normalizedLabel = normalizeSearchText(label.trimmed());
			if (normalizedLabel.isEmpty())
				return;
			int rank = forcedRank;
			if (rank < 0)
			{
				if (normalizedLabel == normalizedQuery)
					rank = 0;
				else if (normalizedLabel.startsWith(normalizedQuery))
					rank = 1;
				else if (normalizedLabel.contains(normalizedQuery))
					rank = 2;
			}
			if (rank < 0)
				return;
			const QString objectKey = object->getType() + QLatin1Char('|') + object->getID();
			auto existing = candidateIndexes.constFind(objectKey);
			if (existing != candidateIndexes.constEnd())
			{
				SearchCandidate& current = candidates[*existing];
				if (rank < current.rank || (rank == current.rank && label.size() < current.label.size()))
				{
					current.label = label.trimmed();
					current.rank = rank;
					current.crossLanguage = crossLanguage;
				}
				return;
			}
			candidateIndexes.insert(objectKey, candidates.size());
			candidates.append({label.trimmed(), object, rank, crossLanguage});
		};

		// Reuse every loaded module's own index. It understands official aliases,
		// catalog designations and plugin-specific availability rules without
		// rebuilding whole star/DSO catalogues on every keystroke.
		QStringList queryVariants;
		auto addVariant = [&queryVariants](const QString& value) {
			const QString trimmed = value.trimmed();
			if (!trimmed.isEmpty() && !queryVariants.contains(trimmed, Qt::CaseInsensitive))
				queryVariants.append(trimmed);
		};
		addVariant(query);
		QString spacedQuery = query;
		spacedQuery.replace(QRegularExpression(QStringLiteral("[\\s_-]+")), QStringLiteral(" "));
		addVariant(spacedQuery.simplified());
		addVariant(normalizedQuery);
		addVariant(StelUtils::substituteGreek(query));
		for (const QString& variant : std::as_const(queryVariants))
		{
			const auto indexedMatches = objectMgr->listMatchingObjects(variant, maxItems * 4, false);
			for (const auto& pair : indexedMatches)
			{
				addCandidate(pair.first, pair.second);
				if (pair.second)
				{
					addCandidate(pair.second->getEnglishName(), pair.second);
					addCandidate(pair.second->getNameI18n(), pair.second);
					addCandidate(pair.second->getID(), pair.second);
				}
			}
		}

		// The active Qt translation catalog only indexes the selected language.
		// Merge the generated official aliases into the normal result set instead
		// of using them only when local results are empty. This preserves exact
		// local matches while keeping useful cross-language candidates visible.
		auto differsByAtMostOne = [](const QString& left, const QString& right) {
			if (qAbs(left.size() - right.size()) > 1)
				return false;
			int leftIndex = 0;
			int rightIndex = 0;
			int differences = 0;
			while (leftIndex < left.size() && rightIndex < right.size())
			{
				if (left.at(leftIndex) == right.at(rightIndex))
				{
					++leftIndex;
					++rightIndex;
					continue;
				}
				if (++differences > 1)
					return false;
				if (left.size() > right.size())
					++leftIndex;
				else if (right.size() > left.size())
					++rightIndex;
				else
				{
					++leftIndex;
					++rightIndex;
				}
			}
			return true;
		};
		if (!normalizedQuery.isEmpty())
		{
			struct CrossLanguageAlias { QString englishName; };
			static QHash<QString, QVector<CrossLanguageAlias>> aliasesByNormalizedName;
			static bool aliasesLoaded = false;
			if (!aliasesLoaded)
			{
				aliasesLoaded = true;
				const QString indexPath = StelFileMgr::findFile(QStringLiteral("data/search/multilingual-sky-aliases.tsv"));
				QFile indexFile(indexPath);
				if (indexFile.open(QFile::ReadOnly | QFile::Text))
				{
					QTextStream stream(&indexFile);
					while (!stream.atEnd())
					{
						const QString line = stream.readLine();
						if (line.startsWith(QLatin1Char('#')))
							continue;
						const QStringList fields = line.split(QLatin1Char('\t'));
						if (fields.size() < 2)
							continue;
						const QString normalizedAlias = normalizeSearchText(fields.at(0));
						const QString englishName = fields.at(1).trimmed();
						if (!normalizedAlias.isEmpty() && !englishName.isEmpty())
							aliasesByNormalizedName[normalizedAlias].append({englishName});
					}
					qInfo() << "[StellariumOhos][search] loaded official multilingual aliases:" << aliasesByNormalizedName.size();
				}
				else
				{
					qWarning() << "[StellariumOhos][search] multilingual alias index unavailable:" << indexPath;
				}
			}

			auto addCrossLanguageAlias = [&](const QString& normalizedAlias, int rank) {
				const auto aliases = aliasesByNormalizedName.constFind(normalizedAlias);
				if (aliases == aliasesByNormalizedName.constEnd())
					return;
				for (const CrossLanguageAlias& alias : *aliases)
				{
					const StelObjectP object = objectMgr->searchByName(alias.englishName);
					if (object)
						addCandidate(object->getNameI18n(), object, rank, true);
				}
			};

			addCrossLanguageAlias(normalizedQuery, 3);
			if (candidates.size() < maxItems * 4 && normalizedQuery.size() >= 2)
			{
				for (auto it = aliasesByNormalizedName.constBegin(); it != aliasesByNormalizedName.constEnd() && candidates.size() < maxItems * 4; ++it)
				{
					if (it.key().startsWith(normalizedQuery))
						addCrossLanguageAlias(it.key(), 4);
				}
			}
			if (candidates.size() < maxItems * 4 && normalizedQuery.size() >= 3)
			{
				for (auto it = aliasesByNormalizedName.constBegin(); it != aliasesByNormalizedName.constEnd() && candidates.size() < maxItems * 4; ++it)
				{
					if (it.key().contains(normalizedQuery))
						addCrossLanguageAlias(it.key(), 5);
				}
			}
			// A one-character typo in a translated name should behave like a
			// one-character typo in English. Resolve only close official aliases;
			// this stays bounded by the result cap and never scans object catalogs.
			if (candidates.size() < maxItems * 4 && normalizedQuery.size() >= 3)
			{
				for (auto it = aliasesByNormalizedName.constBegin(); it != aliasesByNormalizedName.constEnd() && candidates.size() < maxItems * 4; ++it)
				{
					if (!differsByAtMostOne(normalizedQuery, it.key()))
						continue;
					addCrossLanguageAlias(it.key(), 7);
				}
			}
		}

		// A typo or a missing Chinese connective character should not turn an
		// otherwise known object into a dead end. This fallback is bounded and
		// only consults the module's indexed prefix candidates.
		if (normalizedQuery.size() >= 3 && candidates.size() < maxItems * 4)
		{
			QSet<QString> fuzzyPrefixes;
			fuzzyPrefixes.insert(query.left(query.size() - 1).trimmed());
			fuzzyPrefixes.insert(query.left(qMax(2, (query.size() * 2) / 3)).trimmed());
			for (const QString& fuzzyPrefix : std::as_const(fuzzyPrefixes))
			{
				if (fuzzyPrefix.size() < 2)
					continue;
				const auto nearMatches = objectMgr->listMatchingObjects(fuzzyPrefix, 12, false);
				for (const auto& pair : nearMatches)
				{
					if (!pair.second)
						continue;
					auto addNearMatch = [&](const QString& label) {
						if (differsByAtMostOne(normalizedQuery, normalizeSearchText(label)))
							addCandidate(label, pair.second, 6);
					};
					addNearMatch(pair.first);
					addNearMatch(pair.second->getEnglishName());
					addNearMatch(pair.second->getNameI18n());
					addNearMatch(pair.second->getID());
				}
			}
		}
		std::sort(candidates.begin(), candidates.end(), [](const SearchCandidate& left, const SearchCandidate& right) {
			if (left.rank != right.rank)
				return left.rank < right.rank;
			return left.label.localeAwareCompare(right.label) < 0;
		});
		QJsonArray items;
		QJsonArray keys;
		QJsonArray ids;
		QJsonArray typeIds;
		QJsonArray types;
		QJsonArray fuzzy;
		QJsonArray crossLanguage;
		for (int i = 0; i < candidates.size() && i < maxItems; ++i)
		{
			const auto& candidate = candidates.at(i);
			items.append(candidate.label);
			// pair.first is a localized display label. Keep it for the UI, but
			// return the object's stable English name for the follow-up selection.
			const QString key = candidate.object ? candidate.object->getEnglishName() : QString();
			keys.append(key.isEmpty() ? candidate.label : key);
			ids.append(candidate.object ? candidate.object->getID() : QString());
			typeIds.append(candidate.object ? candidate.object->getType() : QString());
			types.append(candidate.object ? candidate.object->getObjectTypeI18n() : QString());
			fuzzy.append(candidate.rank >= 6);
			crossLanguage.append(candidate.crossLanguage);
		}
		result["ok"] = true; result["items"] = items; result["keys"] = keys;
		result["ids"] = ids; result["typeIds"] = typeIds; result["types"] = types; result["fuzzy"] = fuzzy; result["crossLanguage"] = crossLanguage;
		result["count"] = items.size(); result["prefix"] = query;
		return result;
	}

	if (commandName == "listObjects")
	{
		if (!objectMgr) { result["error"] = "object manager not found"; return result; }
		StelCore* core = StelApp::getInstance().getCore();
		if (!core) { result["error"] = "core not ready"; return result; }
		const QStringList options = arg.split('|');
		QString moduleId = options.value(0).trimmed();
		int maxItems = 60;
		int offset = 0;
		bool inEnglish = true;
		bool isLimit = false;
		const int requestedLimit = options.value(1).trimmed().toInt(&isLimit);
		if (isLimit)
			maxItems = qBound(1, requestedLimit, 120);
		else if (options.size() > 1)
			inEnglish = (options.value(1).trimmed().toLower() != "false" && options.value(1).trimmed() != "0");
		bool isOffset = false;
		const int requestedOffset = options.value(2).trimmed().toInt(&isOffset);
		if (isOffset)
			offset = qMax(0, requestedOffset);
		const QString visibilityFilter = options.value(3).trimmed().toLower();
		const QString instrumentFilter = options.value(4).trimmed().toLower();
		const auto list = objectMgr->listAllModuleObjects(moduleId, inEnglish);
		QJsonArray items;
		QJsonArray keys;
		QJsonArray types;
		QJsonArray altitudes;
		QJsonArray magnitudes;
		QJsonArray visibleNow;
		QSet<QString> seenIds;
		int uniqueCount = 0;
		for (const auto& pair : list)
		{
			const StelObjectP object = pair.second;
			const QString id = object ? object->getID() : pair.first;
			if (id.isEmpty() || seenIds.contains(id))
				continue;
			seenIds.insert(id);
			const Vec3d altAz = object ? object->getAltAzPosAuto(core) : Vec3d();
			double azimuth = 0.0;
			double altitude = -M_PI_2;
			if (object && altAz.normSquared() > 0.0)
				StelUtils::rectToSphe(&azimuth, &altitude, altAz);
			const double altitudeDegrees = altitude * M_180_PI;
			const double magnitude = object ? object->getVMagnitudeWithExtinction(core) : 99.0;
			if (visibilityFilter == QStringLiteral("above") && altitudeDegrees < 0.0)
				continue;
			if (visibilityFilter == QStringLiteral("good") && altitudeDegrees < 20.0)
				continue;
			if (instrumentFilter == QStringLiteral("naked") && magnitude > 6.0)
				continue;
			if (instrumentFilter == QStringLiteral("binocular") && magnitude > 10.0)
				continue;
			if (uniqueCount >= offset && items.size() < maxItems)
			{
				QString displayName = object ? object->getNameI18n() : pair.first;
				if (displayName.isEmpty())
					displayName = pair.first;
				items.append(displayName);
				keys.append(id);
				types.append(object ? object->getObjectTypeI18n() : QString());
				altitudes.append(altitudeDegrees);
				magnitudes.append(magnitude);
				visibleNow.append(altitudeDegrees >= 0.0);
			}
			++uniqueCount;
		}
		result["ok"] = true; result["items"] = items; result["keys"] = keys;
		result["types"] = types; result["altitudes"] = altitudes; result["magnitudes"] = magnitudes; result["visibleNow"] = visibleNow;
		result["count"] = uniqueCount; result["hasMore"] = offset + items.size() < uniqueCount;
		result["offset"] = offset; result["moduleId"] = moduleId;
		result["visibilityFilter"] = visibilityFilter; result["instrumentFilter"] = instrumentFilter;
		qInfo() << "[StellariumOhos][catalog-page] module=" << moduleId
				<< "offset=" << offset << "returned=" << items.size() << "total=" << uniqueCount;
		return result;
	}

	if (commandName == "getSkyCultures")
	{
		StelSkyCultureMgr* skyCultureMgr = GETSTELMODULE(StelSkyCultureMgr);
		if (!skyCultureMgr) { result["error"] = "sky culture manager not found"; return result; }
		QJsonArray items;
		for (const QString& name : skyCultureMgr->getSkyCultureListI18()) { items.append(name); }
		result["ok"] = true; result["items"] = items;
		result["count"] = items.size();
		result["current"] = skyCultureMgr->getCurrentSkyCultureNameI18();
		result["currentId"] = skyCultureMgr->getCurrentSkyCultureID();
		result["installDir"] = StelFileMgr::getInstallationDir();
		result["userDir"] = StelFileMgr::getUserDir();
		QJsonArray searchPaths;
		for (const QString& p : StelFileMgr::getSearchPaths()) { searchPaths.append(p); }
		result["searchPaths"] = searchPaths;
		result["skyculturesModernIndex"] = StelFileMgr::findFile("skycultures/modern/index.json");
		return result;
	}

	if (commandName == "setSkyCulture")
	{
		StelSkyCultureMgr* skyCultureMgr = GETSTELMODULE(StelSkyCultureMgr);
		if (!skyCultureMgr) { result["error"] = "sky culture manager not found"; return result; }
		// 调用方可能传本地化显示名（设置面板）或稳定 ID（星图文化列表）。
		// 两种都要接受，否则其中一侧的按钮会全部静默失效。
		const QString wanted = arg.trimmed();
		bool ok = skyCultureMgr->setCurrentSkyCultureID(wanted);
		if (!ok) { ok = skyCultureMgr->setCurrentSkyCultureNameI18(wanted); }
		result["ok"] = ok;
		if (!ok) { result["error"] = "unknown sky culture: " + wanted; }
		result["culture"] = skyCultureMgr->getCurrentSkyCultureNameI18();
		result["cultureId"] = skyCultureMgr->getCurrentSkyCultureID();
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
			// The desktop default is tuned for a mouse cursor. Give a one-shot
			// touch pick a finger-sized target without changing desktop selection
			// behavior or leaving a global radius behind for later operations.
			objectMgr->setObjectSearchRadius(44.0);
			found = objectMgr->findAndSelect(core, sx, sy);
			objectMgr->setObjectSearchRadius(25.0);
			qInfo() << "[StellariumOhos][selectAt] found" << found;
			OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "StellariumCpp",
						 "selectAt found=%{public}d", found ? 1 : 0);
		}

		markOhosInteraction();
			// Keep the tap response lightweight so the selected target can be drawn
			// immediately. The full detail prose is loaded asynchronously by ArkTS.
			result = selectedObjectJson(core, false);
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
			s_ohosPanInertiaActive = false;
			ohosApplyPanDelta(core, x2 - x1, y2 - y1);
			markOhosInteraction();
			result["ok"] = true;
			result["fov"] = movementMgr->getCurrentFov();
			return result;
		}

		if (commandName == "beginSkyGesture")
		{
			if (!movementMgr)
			{
				result["error"] = "movement manager not ready";
				return result;
			}
			// A touch on unobstructed sky owns the camera immediately. This also
			// invalidates panel-safe-area timers before the drag threshold is met.
			++s_ohosNavigationSerial;
			movementMgr->cancelAutoMove();
			s_ohosPanInertiaActive = false;
			s_ohosSelectedAnchorHoldUntilSec = 0.0;
			ohosCaptureSelectedZoomAnchor();
			markOhosInteraction();
			result["ok"] = true;
			return result;
		}

		if (commandName == "startPanInertia")
		{
			const QStringList parts = arg.split('|');
			bool okX = false;
			bool okY = false;
			const double vx = parts.value(0).toDouble(&okX);
			const double vy = parts.value(1).toDouble(&okY);
			if (!okX || !okY)
			{
				result["ok"] = true;
				return result;
			}
			s_ohosPanInertiaVx = qBound(-4.0, vx, 4.0);
			s_ohosPanInertiaVy = qBound(-4.0, vy, 4.0);
			s_ohosPanInertiaElapsedSec = 0.0;
			s_ohosPanInertiaActive = std::hypot(s_ohosPanInertiaVx, s_ohosPanInertiaVy) >= 0.05;
			markOhosInteraction();
			result["ok"] = true;
			return result;
		}

		if (commandName == "stopPanInertia")
		{
			s_ohosPanInertiaActive = false;
			s_ohosPanInertiaVx = 0.0;
			s_ohosPanInertiaVy = 0.0;
			result["ok"] = true;
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
			s_ohosSelectedAnchorHoldUntilSec = 0.0;
			s_ohosCaptureSelectedAnchorAfterPan = true;
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
			bool okCenterX = false;
			bool okCenterY = false;
			bool okTouchWidth = false;
			bool okTouchHeight = false;
			const double centerX = parts.value(2).toDouble(&okCenterX);
			const double centerY = parts.value(3).toDouble(&okCenterY);
			const double touchWidth = parts.value(4).toDouble(&okTouchWidth);
			const double touchHeight = parts.value(5).toDouble(&okTouchHeight);
			const bool hasTouchCenter = parts.size() >= 6 && okCenterX && okCenterY
				&& okTouchWidth && okTouchHeight && touchWidth > 1.0 && touchHeight > 1.0;
			if (!okScale || scale <= 0.0)
			{
				result["error"] = "invalid zoom scale";
				return result;
			}
			if (started)
			{
				// A pinch takes ownership of the camera immediately. Invalidate
				// delayed safe-area/selection callbacks before capturing the current
				// screen position, otherwise the old move can overwrite the gesture.
				++s_ohosNavigationSerial;
				movementMgr->cancelAutoMove();
				s_ohosSelectedAnchorHoldUntilSec = 0.0;
				s_ohosPinchActive = true;
				if (hasTouchCenter)
					ohosBeginPinchAnchor(centerX, centerY, touchWidth, touchHeight);
				else
				{
					ohosCaptureSelectedZoomAnchor();
					s_ohosPinchAnchorMode = OhosPinchAnchorMode::SelectedObject;
				}
			}
			else if (hasTouchCenter)
				ohosUpdatePinchTarget(centerX, centerY, touchWidth, touchHeight);
			movementMgr->handlePinch(scale, started);
			markOhosInteraction();
			result["ok"] = true;
			result["fov"] = movementMgr->getCurrentFov();
			return result;
		}

		if (commandName == "endPinch")
		{
			// The last absolute scale and endPinch may be drained in the same
			// render frame. Apply its anchor once before clearing gesture state so
			// the final frame cannot jump away from the fingers.
			if (s_ohosPinchAnchorMode == OhosPinchAnchorMode::SkyPoint)
				ohosMaintainPinchSkyAnchor();
			else if (s_ohosPinchAnchorMode == OhosPinchAnchorMode::SelectedObject)
				ohosMaintainSelectedZoomAnchor();
			s_ohosPinchActive = false;
			s_ohosPinchAnchorMode = OhosPinchAnchorMode::None;
			s_ohosPinchAnchorRelaxUntilSec = StelApp::getTotalRunTime() + 0.18;
			s_ohosCaptureSelectedAnchorAfterPan = true;
			result["ok"] = true;
			return result;
		}

		if (commandName == "getSelectedObjectInfo")
		{
			const QString detailMode = arg.trimmed().toLower();
			return selectedObjectJson(core, detailMode == QStringLiteral("details") || detailMode == QStringLiteral("full"));
		}

		if (commandName == "moveToSelectedAt")
		{
			if (!objectMgr || !movementMgr || !core || objectMgr->getSelectedObject().isEmpty())
			{
				result["error"] = "no selected object";
				return result;
			}
			const QStringList parts = arg.split('|');
			bool okX = false;
			bool okY = false;
			bool okW = false;
			bool okH = false;
			const double x = parts.value(0).toDouble(&okX);
			const double y = parts.value(1).toDouble(&okY);
			const double width = parts.value(2).toDouble(&okW);
			const double height = parts.value(3).toDouble(&okH);
			const QString mode = parts.value(4).trimmed().toLower();
			if ((parts.size() != 4 && parts.size() != 5) || !okX || !okY || !okW || !okH || width <= 1.0 || height <= 1.0)
			{
				result["error"] = "moveToSelectedAt expects x|y|width|height|[focus|layout]";
				return result;
			}
			// A new safe-area request supersedes every previous search/layout
			// animation. Otherwise an older timer can recenter the selected object
			// after this request has completed.
			++s_ohosNavigationSerial;
			movementMgr->cancelAutoMove();
			// Horizontal viewport offsets translate the projected image directly,
			// which is ideal for a tablet's side panel. Stellarium deliberately
			// compensates its vertical offset while tracking an object, though, so
			// a phone's top card needs an explicit, animated vertical pan below.
			const StelObjectP selectedObject = objectMgr->getSelectedObject().constFirst();
			const double horizontalOffset = mode == QLatin1String("center")
				? 0.0 : ((x / width) - 0.5) * 100.0;
			// Do not estimate the vertical adjustment from field of view. That
			// approximation is visibly wrong at high zoom and when a phone sheet
			// changes from 6/10 to 9/10. Measure the selected body's actual
			// projected position and convert the required screen-pixel delta with
			// the projector's local pixel-per-radian scale instead.
			auto verticalPanToTarget = [core, selectedObject, y, height]() {
				const StelProjectorP prj = core->getProjection(StelCore::FrameJ2000);
				if (!prj)
					return 0.0;
				const Vec4i viewport = prj->getViewport();
				const double ppr = static_cast<double>(prj->getPixelPerRadAtCenter());
				if (viewport[3] <= 1 || ppr <= 1e-9)
					return 0.0;
				Vec3d projected;
				if (!prj->project(selectedObject->getJ2000EquatorialPos(core), projected))
					return 0.0;
				const double currentTopY = static_cast<double>(viewport[3] - 1) - projected[1];
				const double desiredTopY = (y / height) * viewport[3];
				return (desiredTopY - currentTopY) / ppr;
			};
			const double verticalPan = verticalPanToTarget();
			const bool hasPreviousSafePoint = s_ohosSafeTargetObject == selectedObject->getEnglishName()
				&& s_ohosSafeTargetHeight > 1.0;
			const double layoutVerticalPan = hasPreviousSafePoint ? verticalPan : 0.0;
			qInfo() << "[StellariumOhos][safe-target]" << objectMgr->getSelectedObject().constFirst()->getEnglishName()
					<< "screen" << x << y << width << height
					<< "horizontalOffset" << horizontalOffset << "verticalPan" << verticalPan
					<< "layoutVerticalPan" << layoutVerticalPan << "mode" << mode;
			const quint64 serial = ++s_ohosNavigationSerial;
			ohosDeferSelectedAnchor(mode == "layout" && hasPreviousSafePoint ? 0.45 : 1.15);
			auto animateVerticalPan = [movementMgr, verticalPanToTarget, serial]() {
				const double verticalPan = verticalPanToTarget();
				QTimer* timer = new QTimer(&StelMainView::getInstance());
				timer->setInterval(16);
				QObject::connect(timer, &QTimer::timeout, timer, [timer, movementMgr, verticalPanToTarget, verticalPan, serial, step = 0, previous = 0.0]() mutable {
					if (serial != s_ohosNavigationSerial.load())
					{
						timer->stop();
						timer->deleteLater();
						return;
					}
					++step;
					const double progress = (1.0 - std::cos(M_PI * qMin(step, 20) / 20.0)) * 0.5;
					movementMgr->panView(0.0, verticalPan * (progress - previous));
					markOhosInteraction();
					previous = progress;
					if (step >= 20)
					{
						timer->stop();
						timer->deleteLater();
						// Zoom and move-to-object use separate animations. Correct once
						// after the main pan finishes from the *actual* projected point,
						// otherwise the selected body can drift below its safe centre as
						// the zoom animation settles.
						QTimer::singleShot(64, &StelMainView::getInstance(), [movementMgr, verticalPanToTarget, serial]() {
							if (serial != s_ohosNavigationSerial.load())
								return;
							const double remainingPan = verticalPanToTarget();
							if (std::abs(remainingPan) > 1e-5)
							{
								movementMgr->panView(0.0, remainingPan);
								markOhosInteraction();
							}
						});
					}
				});
				timer->start();
			};
			// A layout transition moves an already positioned target. Re-running
			// moveToObject() here first snaps it to the ordinary centre. Animate
			// only the changed projection/vertical distance instead. Do not use
			// moveViewport(duration): its QTimeLine is not clocked consistently by
			// the OHOS render pump, producing a visible jump when a side panel closes.
			if (mode == "layout" && hasPreviousSafePoint)
			{
				movementMgr->setFlagTracking(false);
				const auto animateLayoutShift = [movementMgr, core, horizontalOffset, layoutVerticalPan, serial]() {
					const double startHorizontalOffset = core->getViewportHorizontalOffset();
					QTimer* timer = new QTimer(&StelMainView::getInstance());
					timer->setInterval(16);
					QObject::connect(timer, &QTimer::timeout, timer, [timer, movementMgr, core, startHorizontalOffset, horizontalOffset, layoutVerticalPan, serial, step = 0, previous = 0.0]() mutable {
						if (serial != s_ohosNavigationSerial.load())
						{
							timer->stop();
							timer->deleteLater();
							return;
						}
						++step;
						const double progress = (1.0 - std::cos(M_PI * qMin(step, 20) / 20.0)) * 0.5;
						core->setViewportHorizontalOffset(startHorizontalOffset + (horizontalOffset - startHorizontalOffset) * progress);
						movementMgr->panView(0.0, layoutVerticalPan * (progress - previous));
						markOhosInteraction();
						previous = progress;
						if (step >= 20)
						{
							// Keep Stellarium's viewport target in sync for the next layout change.
							movementMgr->moveViewport(horizontalOffset, 0.0, 0.0f);
							timer->stop();
							timer->deleteLater();
						}
					});
					timer->start();
				};
				animateLayoutShift();
			}
			else
			{
				movementMgr->setFlagTracking(false);
				movementMgr->moveViewport(horizontalOffset, 0.0, 0.0f);
				movementMgr->moveToObject(selectedObject, 0.70f, StelMovementMgr::ZoomNone);
				QTimer::singleShot(690, &StelMainView::getInstance(), animateVerticalPan);
			}
			s_ohosSafeTargetObject = selectedObject->getEnglishName();
			s_ohosSafeTargetY = y;
			s_ohosSafeTargetHeight = height;
			result = selectedObjectJson(core, false);
			result["ok"] = true;
			result["safeTargetX"] = x;
			result["safeTargetY"] = y;
			result["viewportHorizontalOffset"] = core->getViewportHorizontalOffset();
			result["viewportVerticalOffset"] = core->getViewportVerticalOffset();
			markOhosInteraction();
			return result;
		}

		if (commandName == "moveToSelected")
		{
			if (objectMgr && movementMgr && !objectMgr->getSelectedObject().isEmpty())
			{
				ohosDeferSelectedAnchor(movementMgr->getAutoMoveDuration() + 0.15);
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
			if (!enabled)
				movementMgr->cancelAutoMove();
			movementMgr->setFlagTracking(enabled);
			markOhosInteraction();
			result = currentStateJson();
			return result;
		}

		if (commandName == "setVerticalClamp")
		{
			s_verticalClamp = (arg == "1" || arg.toLower() == "true");
			result["ok"] = true;
			result["verticalClamp"] = s_verticalClamp;
			return result;
		}

		if (commandName == "setViewLock")
		{
			s_viewLock = (arg == "1" || arg.toLower() == "true");
			if (s_viewLock)
				s_ohosCaptureSelectedAnchorAfterPan = true;
			result["ok"] = true;
			result["viewLock"] = s_viewLock;
			return result;
		}

		if (commandName == "setFlatHorizon")
		{
			// "画面防弯曲": cap the maximum FOV so the view can never zoom out
			// into the fish-eye "little ball" look; the horizon stays flat or
			// only slightly curved. OFF restores the full projection range.
			if (!movementMgr)
			{
				result["error"] = "movement manager not ready";
				return result;
			}
			const bool enabled = (arg == "1" || arg.toLower() == "true");
			movementMgr->setUserMaxFov(enabled ? 100.0 : 360.0);
			result["ok"] = true;
			result["flatHorizon"] = enabled;
			result["maxFov"] = movementMgr->getMaxFov();
			result["fov"] = movementMgr->getCurrentFov();
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
			++s_ohosNavigationSerial;
			movementMgr->cancelAutoMove();
			s_ohosSelectedAnchorHoldUntilSec = 0.0;
			ohosCaptureSelectedZoomAnchor();
			// Use the pending aim FOV so rapid button taps compose continuously
			// instead of repeatedly restarting from the in-between current FOV.
			double aim = movementMgr->getAimFov() * factor;
			if (aim < 0.001) aim = 0.001;
			if (aim > 360.0) aim = 360.0;
			movementMgr->zoomTo(aim, 0.18f);
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

		// setLandscapeFadeWithZoom — toggle the port's FOV-based ground auto-fade
		if (commandName == "setLandscapeFadeWithZoom")
		{
			bool convOk = false;
			int v = arg.toInt(&convOk);
			s_landscapeFadeWithZoom = (v != 0);
			if (!s_landscapeFadeWithZoom)
			{
				// user wants a fixed (opaque) ground: cancel any fade state
				LandscapeMgr* lmgr = GETSTELMODULE(LandscapeMgr);
				if (lmgr) { lmgr->setFlagLandscapeUseTransparency(false); lmgr->setLandscapeTransparency(0.0); }
				s_landscapeFadeSmooth = 0.f;
			}
			result["ok"] = true;
			result["enabled"] = s_landscapeFadeWithZoom;
			return result;
		}

	// setLandscapeUseTransparency — manually enable/disable landscape transparency.
	// Takes manual control, which also disables the FOV-based auto-fade.
	if (commandName == "setLandscapeUseTransparency")
	{
		bool convOk = false;
		int v = arg.toInt(&convOk);
		LandscapeMgr* lmgr = GETSTELMODULE(LandscapeMgr);
		if (lmgr)
		{
			lmgr->setFlagLandscapeUseTransparency(v != 0);
			s_landscapeFadeWithZoom = false;
			s_landscapeFadeSmooth = 0.f;
			result["ok"] = true;
		} else {
			result["ok"] = false;
			result["error"] = "LandscapeMgr missing";
		}
		return result;
	}

		// pointAtSky — virtual pointing-stick target side.
		// arg: "<alt>|<az>[|<track>]" in degrees (apparent horizontal coords).
		//  - track omitted / "0": one-shot. Recenters the view on that sky
		//    direction immediately and selects the object at screen-center on the
		//    next frame.
		//  - track "1": continuous "watch gyro" mode. Remembers the target J2000
		//    direction; ohosUpdatePointTracking() eases the view toward it every
		//    frame so the sky follows the user's hand. No selection yet (view is
		//    still moving). The watch streams many of these as it rotates.
		// This is the "你指到哪，其他屏幕就显示到对应的星星" 收口逻辑 —— 手表/分布式
		// 只是另一种触发方式，最终都归一化到这条命令。
		if (commandName == "pointAtSky")
		{
			if (!core || !movementMgr)
			{
				result["error"] = "core/movement not ready";
				return result;
			}
			const QStringList parts = arg.split('|');
			if (parts.size() < 2)
			{
				result["error"] = "pointAtSky expects alt|az[|track]";
				return result;
			}
			bool okAlt = false, okAz = false;
			const double altDeg = parts[0].toDouble(&okAlt);
			const double azDeg = parts[1].toDouble(&okAz);
			if (!okAlt || !okAz)
			{
				result["error"] = "alt/az not numeric";
				return result;
			}
			const double altRad = altDeg * M_PI / 180.0;
			const double azRad = azDeg * M_PI / 180.0;
			// Build the AltAz-frame unit vector using Stellarium's convention
			// (spheToRect(longitude=M_PI-az, latitude=alt, v)).
			Vec3d altAzVec;
			StelUtils::spheToRect(M_PI - azRad, altRad, altAzVec);
			const Vec3d j2000 = core->altAzToJ2000(altAzVec, StelCore::RefractionOff);
			const bool track = (parts.size() >= 3 && parts[2] == "1");
			if (track)
			{
				// Continuous watch-gyro follow: just update the target; the
				// per-frame easing does the visible motion.
				s_trackTargetJ2000 = j2000;
				s_pointTracking = true;
				result["ok"] = true;
				result["tracking"] = true;
				result["alt"] = altDeg;
				result["az"] = azDeg;
				return result;
			}
			// One-shot: snap now and select center next frame.
			s_pointTracking = false;
			movementMgr->setViewDirectionJ2000(j2000);
			// Defer the center-selection to the next frame (projection refresh).
			s_pendingPointSelect = true;
			result["ok"] = true;
			result["alt"] = altDeg;
			result["az"] = azDeg;
			result["j2000"] = QString("[%1,%2,%3]").arg(j2000[0],0,'f',4).arg(j2000[1],0,'f',4).arg(j2000[2],0,'f',4);
			return result;
		}

		// pointAtSkyStop — end "watch gyro" tracking and lock onto whatever is now
		// at screen-center (the star the user's hand is finally pointing at).
		if (commandName == "pointAtSkyStop")
		{
			s_pointTracking = false;
			s_pendingPointSelect = true;
			result["ok"] = true;
			return result;
		}

		// gotoRADec - jump the view to a specific RA/Dec (J2000 equatorial coordinates).
		// arg: "<ra_hours>|<dec_degrees>[|select_nearest]" where ra is in hours
		// (0-24), dec in degrees (-90 to +90), and select_nearest defaults to true.
		if (commandName == "gotoRADec")
		{
			if (!core || !movementMgr)
			{
				result["error"] = "core/movement not ready";
				return result;
			}
			const QStringList parts = arg.split('|');
			if (parts.size() < 2)
			{
				result["error"] = "gotoRADec expects ra_hours|dec_degrees";
				return result;
			}
			bool okRA = false, okDec = false;
			const double raHours = parts[0].toDouble(&okRA);
			const double decDeg = parts[1].toDouble(&okDec);
			if (!okRA || !okDec)
			{
				result["error"] = "ra/dec not numeric";
				return result;
			}
			// Convert RA (hours) to radians, Dec (degrees) to radians
			const double raRad = raHours * M_PI / 12.0;  // hours -> radians (24h = 2*pi)
			const double decRad = decDeg * M_PI / 180.0; // degrees -> radians
			Vec3d j2000;
			StelUtils::spheToRect(raRad, decRad, j2000);
			movementMgr->setViewDirectionJ2000(j2000);
			const bool selectNearest = parts.size() < 3 || parts[2].trimmed() != QStringLiteral("0");
			if (selectNearest)
				s_pendingPointSelect = true;
			result["ok"] = true;
			result["ra"] = raHours;
			result["dec"] = decDeg;
			return result;
		}


	// getScriptList
		if (commandName == "getScriptList")
		{
			StelScriptMgr& smgr = StelApp::getInstance().getScriptMgr();
			QStringList scripts = smgr.getScriptList();
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
			StelScriptMgr& smgr = StelApp::getInstance().getScriptMgr();
			if (arg.trimmed().isEmpty())
			{
				result["error"] = "script name is empty";
				return result;
			}
			if (smgr.scriptIsRunning() || s_ohosScriptStartPending.exchange(true))
			{
				result["error"] = "a script is already running or starting";
				return result;
			}

			// runScript() is deliberately blocking in upstream Stellarium. Do not
			// invoke it from ohosDrainCommandQueue(), which is also responsible for
			// returning the current frame to the surface. Schedule it after this
			// command callback has returned so bridge polling and rendering remain
			// responsive while the script enters its own event loop.
			const QString scriptName = arg.trimmed();
			const quint64 generation = s_ohosScriptStartGeneration.fetch_add(1) + 1;
			QTimer::singleShot(0, qApp, [scriptName, generation]() {
				QElapsedTimer timer;
				timer.start();
				bool started = false;
				if (generation == s_ohosScriptStartGeneration.load() && StelApp::isInitialized())
				{
					StelScriptMgr& scriptMgr = StelApp::getInstance().getScriptMgr();
					started = scriptMgr.runScript(scriptName);
				}
				qInfo() << "[StellariumOhos][script] playScript started=" << started
				       << "arg=" << scriptName << "elapsedMs=" << timer.elapsed();
				s_ohosScriptStartPending.store(false);
			});
			result["ok"] = true;
			result["accepted"] = true;
			result["script"] = scriptName;
			return result;
		}

		// stopScript
		if (commandName == "stopScript")
		{
			s_ohosScriptStartGeneration.fetch_add(1);
			s_ohosScriptStartPending.store(false);
			StelApp::getInstance().getScriptMgr().stopScript();
			result["ok"] = true;
			return result;
		}

		// pauseScript
		if (commandName == "pauseScript")
		{
			StelApp::getInstance().getScriptMgr().pauseScript();
			result["ok"] = true;
			return result;
		}

		// resumeScript
		if (commandName == "resumeScript")
		{
			StelApp::getInstance().getScriptMgr().resumeScript();
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

		// getRTS is implemented below (Phase 2r) using getRTSTime().

		// getAlmanac — sun/moon rise/set/transit
		if (commandName == "getAlmanac")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			PlanetP sun = ssys->getSun();
			PlanetP moon = ssys->getMoon();
			QJsonObject alm;
			auto formatLocal = [&](double jd) -> QString {
				if (jd <= 0.0)
					return QString();
				return StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
			};
			auto addEvents = [&](const QString& prefix, const Vec4d& rts) {
				alm[prefix + "Rise"] = rts[0];
				alm[prefix + "Transit"] = rts[1];
				alm[prefix + "Set"] = rts[2];
				alm[prefix + "RiseText"] = formatLocal(rts[0]);
				alm[prefix + "TransitText"] = formatLocal(rts[1]);
				alm[prefix + "SetText"] = formatLocal(rts[2]);
			};
			alm["currentJD"] = core->getJD();
			if (sun)
			{
				Vec4d srts = sun->getRTSTime(core);
				addEvents("sun", srts);
				if (srts[0] > 0.0 && srts[2] > srts[0])
				{
					const double daylightHours = (srts[2] - srts[0]) * 24.0;
					alm["daylightHours"] = daylightHours;
					alm["nightHours"] = 24.0 - daylightHours;
				}
				addEvents("civil", sun->getRTSTime(core, -6.0));
				addEvents("nautical", sun->getRTSTime(core, -12.0));
				addEvents("astronomical", sun->getRTSTime(core, -18.0));
			}
				if (moon)
				{
					Vec4d mrts = moon->getRTSTime(core);
					addEvents("moon", mrts);
					alm["moonPhase"] = moon->getInfoMap(core).value("illumination", 0.0).toDouble();
				}
				const double localJD = core->getJD() + core->getUTCOffset(core->getJD()) / 24.0;
				int year = 0;
				int month = 0;
				int day = 0;
				StelUtils::getDateFromJulianDay(localJD, &year, &month, &day);
				SpecificTimeMgr* specificTimeMgr = GETSTELMODULE(SpecificTimeMgr);
				if (specificTimeMgr)
				{
					const double marchEquinox = specificTimeMgr->getEquinox(year, SpecificTimeMgr::Equinox::March);
					const double juneSolstice = specificTimeMgr->getSolstice(year, SpecificTimeMgr::Solstice::June);
					const double septemberEquinox = specificTimeMgr->getEquinox(year, SpecificTimeMgr::Equinox::September);
					const double decemberSolstice = specificTimeMgr->getSolstice(year, SpecificTimeMgr::Solstice::December);
					const double nextMarchEquinox = specificTimeMgr->getEquinox(year + 1, SpecificTimeMgr::Equinox::March);
					const QList<QPair<QString, double>> seasonTimes = {
						qMakePair(QStringLiteral("春分"), marchEquinox),
						qMakePair(QStringLiteral("夏至"), juneSolstice),
						qMakePair(QStringLiteral("秋分"), septemberEquinox),
						qMakePair(QStringLiteral("冬至"), decemberSolstice),
						qMakePair(QStringLiteral("春分"), nextMarchEquinox)
					};
					QJsonArray seasonEvents;
					for (int index = 0; index < 4; ++index)
					{
						const double eventJD = seasonTimes.at(index).second;
						const double nextEventJD = seasonTimes.at(index + 1).second;
						if (eventJD <= 0.0 || nextEventJD <= 0.0)
							continue;
						QJsonObject event;
						event["label"] = seasonTimes.at(index).first;
						event["jd"] = eventJD;
						event["date"] = formatLocal(eventJD);
						event["durationDays"] = nextEventJD - eventJD;
						seasonEvents.append(event);
					}
					alm["seasonYear"] = year;
					alm["seasonEvents"] = seasonEvents;
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
			// getAllPlanetEnglishNames() also contains catalogued minor bodies,
			// comets and satellites. The AstroCalc position table is deliberately
			// the compact major-body table, matching its labels and fixed layout.
			QStringList planetNames = QStringList() << "Sun" << "Moon" << "Mercury" << "Venus"
											   << "Mars" << "Jupiter" << "Saturn" << "Uranus" << "Neptune";
			QJsonArray items;
			for (const QString& pn : planetNames)
			{
				PlanetP p = qSharedPointerCast<Planet>(ssys->searchByName(pn));
				if (!p) continue;
				QJsonObject obj;
				double ra = 0.0;
				double dec = 0.0;
				StelUtils::rectToSphe(&ra, &dec, p->getEquinoxEquatorialPos(core));
				obj["name"] = p->getNameI18n();
				obj["englishName"] = p->getEnglishName();
				obj["ra"] = StelUtils::radToHmsStr(ra);
				obj["dec"] = StelUtils::radToDmsStr(dec);
				Vec3d altaz = p->getAltAzPosApparent(core);
				obj["altitude"] = std::asin(altaz[2] / altaz.norm()) * 180.0 / M_PI;
				obj["azimuth"] = std::fmod(std::atan2(altaz[1], -altaz[0]) * 180.0 / M_PI + 360.0, 360.0);
				obj["magnitude"] = p->getVMagnitude(core);
				items.append(obj);
			}
			result["ok"] = true;
			result["items"] = items;
			return result;
		}

		// getHeliocentricEclipticPositions - desktop AstroCalc HEC major-body table.
		if (commandName == "getHeliocentricEclipticPositions")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const bool includeSelectedMinor = options.value("includeSelectedMinor").toBool(false);
			const bool includeBrightComets = options.value("includeBrightComets").toBool(false);
			const double cometMagnitudeLimit = qBound(-5.0, options.value("cometMagnitudeLimit").toDouble(9.0), 15.0);
			StelCore* core = StelApp::getInstance().getCore();
			SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
			if (!core || !solarSystem)
			{
				result["ok"] = false;
				result["error"] = "solar system unavailable";
				return result;
			}

			QSet<QString> includedNames;
			QJsonArray positions;
			auto appendPlanet = [&](const PlanetP& planet, bool selectedMinor) {
				if (!planet || includedNames.contains(planet->getEnglishName())) return;
				const Vec3d position = planet->getHeliocentricEclipticPos();
				const double distance = position.norm();
				if (distance <= 0.000001) return; // The Sun is the graph origin, not a data point.
				double longitude = 0.0;
				double latitude = 0.0;
				StelUtils::rectToSphe(&longitude, &latitude, position);
				longitude = StelUtils::fmodpos(longitude, 2.0 * M_PI);
				QJsonObject item;
				item["englishName"] = planet->getEnglishName();
				item["name"] = planet->getNameI18n();
				item["latitude"] = latitude * M_180_PI;
				item["longitude"] = longitude * M_180_PI;
				item["distanceAU"] = distance;
				item["isComet"] = planet->getPlanetType() == Planet::isComet;
				item["isSelectedMinor"] = selectedMinor;
				positions.append(item);
				includedNames.insert(planet->getEnglishName());
			};

			for (const PlanetP& planet : solarSystem->getAllPlanets())
			{
				if (planet && planet->getPlanetType() == Planet::isPlanet)
					appendPlanet(planet, false);
			}
			if (includeBrightComets)
			{
				for (const PlanetP& planet : solarSystem->getAllPlanets())
				{
					if (planet && planet->getPlanetType() == Planet::isComet
						&& planet->getVMagnitude(core) <= cometMagnitudeLimit)
						appendPlanet(planet, false);
				}
			}
			if (includeSelectedMinor)
			{
				const QList<StelObjectP>& selectedObjects = StelApp::getInstance().getStelObjectMgr().getSelectedObject();
				for (const StelObjectP& object : selectedObjects)
				{
					PlanetP planet = qSharedPointerCast<Planet>(object);
					if (planet && planet->getPlanetType() >= Planet::isAsteroid)
						appendPlanet(planet, true);
				}
			}
			result["ok"] = true;
			result["hecTime"] = StelUtils::julianDayToISO8601String(core->getJD() + core->getUTCOffset(core->getJD()) / 24.0);
			result["hecPositions"] = positions;
			return result;
		}

		if (commandName == "getCelestialPositions")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const QString category = options.value("category").toString("planets");
			const bool horizontal = options.value("horizontal").toBool(true);
			const double magnitudeLimit = qBound(-5.0, options.value("magnitudeLimit").toDouble(6.0), 25.0);
			const int maximumRows = qBound(10, options.value("maximumRows").toInt(80), 120);
			StelCore* core = StelApp::getInstance().getCore();
			SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
			NebulaMgr* nebulaMgr = GETSTELMODULE(NebulaMgr);
			StarMgr* starMgr = GETSTELMODULE(StarMgr);
			if (!core || !solarSystem)
			{
				result["ok"] = false;
				result["error"] = "celestial data unavailable";
				return result;
			}

			PlanetP sun = solarSystem->getSun();
			QList<QJsonObject> positions;
			auto appendObject = [&](const auto& object, const QString& catalogId = QString()) {
				if (!object || !object->isAboveRealHorizon(core)) return;
				const double magnitude = object->getVMagnitudeWithExtinction(core);
				if (magnitude > magnitudeLimit) return;
				const Vec3d altAz = object->getAltAzPosAuto(core);
				double azimuth = 0.0;
				double altitude = 0.0;
				StelUtils::rectToSphe(&azimuth, &altitude, altAz);
				azimuth = StelUtils::fmodpos(3.0 * M_PI - azimuth, 2.0 * M_PI);
				double firstCoordinate = azimuth;
				double secondCoordinate = altitude;
				QString firstText;
				QString secondText;
				if (horizontal)
				{
					firstText = StelUtils::radToDmsStr(firstCoordinate, true);
					secondText = StelUtils::radToDmsStr(secondCoordinate, true);
				}
				else
				{
					const Vec3d equatorial = object->getJ2000EquatorialPos(core);
					StelUtils::rectToSphe(&firstCoordinate, &secondCoordinate, equatorial);
					firstText = StelUtils::radToHmsStr(firstCoordinate);
					secondText = StelUtils::radToDmsStr(secondCoordinate, true);
				}
				QString englishName = object->getEnglishName();
				if (englishName.isEmpty()) englishName = catalogId;
				if (englishName.isEmpty()) englishName = object->getID();
				QString name = object->getNameI18n();
				if (name.isEmpty()) name = catalogId;
				if (name.isEmpty()) name = englishName;
				QJsonObject position;
				position["name"] = name;
				position["englishName"] = englishName;
				position["catalogId"] = catalogId;
				position["firstCoordinate"] = firstText;
				position["secondCoordinate"] = secondText;
				position["altitude"] = altitude * M_180_PI;
				position["azimuth"] = azimuth * M_180_PI;
				position["magnitude"] = magnitude;
				position["type"] = object->getObjectTypeI18n();
				if (sun && object->getEnglishName() != sun->getEnglishName())
					position["elongation"] = object->getJ2000EquatorialPos(core).angle(sun->getJ2000EquatorialPos(core)) * M_180_PI;
				positions.append(position);
			};

			if (category == QStringLiteral("planets") || category == QStringLiteral("comets") || category == QStringLiteral("minorBodies"))
			{
				const QList<PlanetP>& candidates = category == QStringLiteral("planets") ? solarSystem->getAllPlanets() : solarSystem->getAllMinorBodies();
				for (const PlanetP& planet : candidates)
				{
					if (!planet || planet == core->getCurrentPlanet()) continue;
					const Planet::PlanetType planetType = planet->getPlanetType();
					if (category == QStringLiteral("planets") && planetType == Planet::isUNDEFINED) continue;
					if (category == QStringLiteral("comets") && planetType != Planet::isComet) continue;
					if (category == QStringLiteral("minorBodies") && planetType < Planet::isAsteroid) continue;
					if (!planet->hasValidPositionalData(core->getJD(), Planet::PositionQuality::OrbitPlotting)) continue;
					appendObject(planet);
				}
			}
			else if (category == QStringLiteral("stars") && starMgr)
			{
				for (const StelObjectP& star : starMgr->getHipparcosStars())
					appendObject(star);
			}
			else if (nebulaMgr)
			{
				for (const NebulaP& nebula : nebulaMgr->getAllDeepSkyObjects())
				{
					if (!nebula || !nebula->objectInDisplayedCatalog() || !nebula->objectInAllowedSizeRangeLimits()) continue;
					const QString type = nebula->getObjectType();
					if (category == QStringLiteral("galaxies") && !type.contains(QStringLiteral("Galaxy"), Qt::CaseInsensitive)) continue;
					if (category == QStringLiteral("nebulae") && !type.contains(QStringLiteral("Nebula"), Qt::CaseInsensitive)) continue;
					if (category == QStringLiteral("clusters") && !type.contains(QStringLiteral("Cluster"), Qt::CaseInsensitive)) continue;
					appendObject(nebula, nebula->getDSODesignationWIC());
				}
			}

			std::sort(positions.begin(), positions.end(), [](const QJsonObject& first, const QJsonObject& second) {
				const double firstAltitude = first.value("altitude").toDouble();
				const double secondAltitude = second.value("altitude").toDouble();
				if (!qFuzzyCompare(firstAltitude + 91.0, secondAltitude + 91.0)) return firstAltitude > secondAltitude;
				return first.value("magnitude").toDouble() < second.value("magnitude").toDouble();
			});
			QJsonArray items;
			for (int index = 0; index < positions.size() && index < maximumRows; ++index)
				items.append(positions.at(index));
			result["ok"] = true;
			result["celestialPositions"] = items;
			result["coordinateMode"] = horizontal ? QStringLiteral("horizontal") : QStringLiteral("equatorial");
			result["positionTime"] = StelUtils::julianDayToISO8601String(core->getJD() + core->getUTCOffset(core->getJD()) / 24.0);
			return result;
		}

		// ========== Phase 2b ==========
		// getSkyCultureList
		if (commandName == "getSkyCultureList")
		{
			StelSkyCultureMgr& skyCultureMgr = StelApp::getInstance().getSkyCultureMgr();
			const QStringList ids = skyCultureMgr.getSkyCultureListIDs();
			const QMap<QString, QString> namesById = skyCultureMgr.getDirToI18Map();
			const QString current = skyCultureMgr.getCurrentSkyCultureID();
			const QMap<QString, StelSkyCulture> cultures = skyCultureMgr.getDirToNameMap();
			auto classificationName = [](const StelSkyCulture::CLASSIFICATION classification) {
				switch (classification)
				{
					case StelSkyCulture::TRADITIONAL: return QStringLiteral("traditional");
					case StelSkyCulture::ETHNOGRAPHIC: return QStringLiteral("ethnographic");
					case StelSkyCulture::HISTORICAL: return QStringLiteral("historical");
					case StelSkyCulture::SINGLE: return QStringLiteral("single");
					case StelSkyCulture::COMPARATIVE: return QStringLiteral("comparative");
					case StelSkyCulture::PERSONAL: return QStringLiteral("personal");
					default: return QStringLiteral("incomplete");
				}
			};
			QJsonArray items;
			for (int i = 0; i < ids.size(); i++)
			{
				QJsonObject obj;
				obj["id"] = ids[i];
				const StelSkyCulture culture = cultures.value(ids[i]);
				obj["name"] = namesById.value(ids[i], culture.englishName);
				obj["region"] = culture.region;
				obj["classification"] = classificationName(culture.classification);
				obj["beginTime"] = culture.beginTime;
				obj["endTime"] = culture.endTime;
				obj["constellationCount"] = culture.constellations.size();
				obj["asterismCount"] = culture.asterisms.size();
				obj["nativeNameCount"] = culture.names.size();
				obj["hasZodiac"] = !culture.zodiac.isEmpty();
				obj["hasLunarSystem"] = !culture.lunarSystem.isEmpty();
				int artCount = 0;
				for (const QJsonValue& constellation : culture.constellations)
				{
					if (constellation.isObject() && constellation.toObject().contains("image")) ++artCount;
				}
				obj["artCount"] = artCount;
				items.append(obj);
			}
			result["ok"] = true;
			result["items"] = items;
			result["current"] = current;
			return result;
		}

		if (commandName == "getSkyCultureDetails")
		{
			StelSkyCultureMgr& skyCultureMgr = StelApp::getInstance().getSkyCultureMgr();
			AsterismMgr* asterismMgr = GETSTELMODULE(AsterismMgr);
			const QString id = skyCultureMgr.getCurrentSkyCultureID();
			const StelSkyCulture culture = skyCultureMgr.getDirToNameMap().value(id);
			QString classification = QStringLiteral("incomplete");
			switch (culture.classification)
			{
				case StelSkyCulture::TRADITIONAL: classification = QStringLiteral("traditional"); break;
				case StelSkyCulture::ETHNOGRAPHIC: classification = QStringLiteral("ethnographic"); break;
				case StelSkyCulture::HISTORICAL: classification = QStringLiteral("historical"); break;
				case StelSkyCulture::SINGLE: classification = QStringLiteral("single"); break;
				case StelSkyCulture::COMPARATIVE: classification = QStringLiteral("comparative"); break;
				case StelSkyCulture::PERSONAL: classification = QStringLiteral("personal"); break;
				default: break;
			}
			int artCount = 0;
			QJsonArray constellationArt;
			for (const QJsonValue& constellation : culture.constellations)
			{
				if (!constellation.isObject()) continue;
				const QJsonObject constellationObject = constellation.toObject();
				const QJsonObject image = constellationObject.value(QStringLiteral("image")).toObject();
				const QString imageFile = image.value(QStringLiteral("file")).toString();
				if (imageFile.isEmpty()) continue;
				++artCount;
				QJsonObject art;
				art[QStringLiteral("rawPath")] = QStringLiteral("skycultures/%1/%2").arg(id, imageFile);
				art[QStringLiteral("index")] = artCount;
				QString displayName;
				const QStringList idParts = constellationObject.value(QStringLiteral("id")).toString().split(' ', Qt::SkipEmptyParts);
				if (idParts.size() == 3)
				{
					if (ConstellationMgr* constellationMgr = GETSTELMODULE(ConstellationMgr))
					{
						const StelObjectP constellationObject = constellationMgr->searchByID(idParts.at(2));
						if (constellationObject)
							displayName = constellationObject->getNameI18n().trimmed();
					}
				}
				if (displayName.isEmpty())
				{
					const QJsonObject commonName = constellationObject.value(QStringLiteral("common_name")).toObject();
					displayName = commonName.value(QStringLiteral("native")).toString().trimmed();
				}
				if (!displayName.isEmpty())
					art[QStringLiteral("name")] = displayName;
				constellationArt.append(art);
			}
			result["ok"] = true;
			result["id"] = id;
			result["name"] = skyCultureMgr.getCurrentSkyCultureNameI18();
			result["englishName"] = skyCultureMgr.getCurrentSkyCultureEnglishName();
			result["region"] = culture.region;
			result["classification"] = classification;
			result["license"] = culture.license;
			result["beginTime"] = culture.beginTime;
			result["endTime"] = culture.endTime;
			QString boundaryType = QStringLiteral("none");
			switch (culture.boundariesType)
			{
				case StelSkyCulture::BoundariesType::IAU: boundaryType = QStringLiteral("iau"); break;
				case StelSkyCulture::BoundariesType::Own: boundaryType = QStringLiteral("own"); break;
				default: break;
			}
			result["boundariesType"] = boundaryType;
			result["constellationCount"] = culture.constellations.size();
			result["asterismCount"] = culture.asterisms.size();
			result["nativeNameCount"] = culture.names.size();
			result["artCount"] = artCount;
			result["constellationArt"] = constellationArt;
			result["hasAsterisms"] = asterismMgr && asterismMgr->isLinesDefined();
			result["hasZodiac"] = !culture.zodiac.isEmpty();
			result["hasLunarSystem"] = !culture.lunarSystem.isEmpty();
			result["screenLabelStyle"] = skyCultureMgr.getScreenLabelStyleString();
			result["infoLabelStyle"] = skyCultureMgr.getInfoLabelStyleString();
			result["zodiacLabelStyle"] = skyCultureMgr.getZodiacLabelStyleString();
			result["lunarSystemLabelStyle"] = skyCultureMgr.getLunarSystemLabelStyleString();
			result["abbreviatedNames"] = skyCultureMgr.getFlagUseAbbreviatedNames();
			result["overrideCommonNames"] = skyCultureMgr.getFlagOverrideUseCommonNames();
			result["defaultId"] = skyCultureMgr.getDefaultSkyCultureID();
			result["usesCommonNames"] = skyCultureMgr.currentSkycultureUsesCommonNames();
			result["narration"] = skyCultureMgr.getCurrentSkyCultureNarration();
			QTextDocument descriptionDocument;
			descriptionDocument.setHtml(skyCultureMgr.getCurrentSkyCultureHtmlDescription());
			QString plainDescription = descriptionDocument.toPlainText();
			plainDescription.replace(QRegularExpression(QStringLiteral("[ \\t]+\\n")), QStringLiteral("\n"));
			plainDescription.replace(QRegularExpression(QStringLiteral("\\n{3,}")), QStringLiteral("\n\n"));
			result["description"] = plainDescription.trimmed();

			// The desktop culture map renders GeoJSON boundaries. Mobile exposes only
			// the associated period metadata, never the boundary coordinates.
			const QString territoryPath = StelFileMgr::findFile(QStringLiteral("skycultures/%1/territory.geojson").arg(id));
			QJsonArray territoryArchive;
			int territorySegmentCount = 0;
			int activeTerritorySegmentCount = 0;
			int simulationYear = 0;
			int simulationMonth = 0;
			int simulationDay = 0;
			const double localJD = core->getJD() + core->getUTCOffset(core->getJD()) / 24.0;
			StelUtils::getDateFromJulianDay(localJD, &simulationYear, &simulationMonth, &simulationDay);
			if (!territoryPath.isEmpty())
			{
				QFile territoryFile(territoryPath);
				if (territoryFile.open(QFile::ReadOnly))
				{
					QJsonParseError parseError;
					const QJsonDocument territoryDocument = QJsonDocument::fromJson(territoryFile.readAll(), &parseError);
					if (parseError.error == QJsonParseError::NoError && territoryDocument.isObject())
					{
						const QJsonArray features = territoryDocument.object().value(QStringLiteral("features")).toArray();
						for (const QJsonValue& featureValue : features)
						{
							if (!featureValue.isObject()) continue;
							const QJsonObject properties = featureValue.toObject().value(QStringLiteral("properties")).toObject();
							if (properties.isEmpty()) continue;
							const int beginTime = properties.value(QStringLiteral("beginTime")).toInt();
							const int endTime = properties.value(QStringLiteral("endTime")).toInt();
							const bool active = (beginTime == 0 || simulationYear >= beginTime)
								&& (endTime == 0 || endTime >= 9000 || simulationYear <= endTime);
							QJsonObject entry;
							entry["name"] = properties.value(QStringLiteral("name")).toString();
							entry["beginTime"] = beginTime;
							entry["endTime"] = endTime;
							entry["countryCode"] = properties.value(QStringLiteral("ISO3166-1-Alpha-2")).toString();
							entry["countryCode3"] = properties.value(QStringLiteral("ISO3166-1-Alpha-3")).toString();
							entry["activeAtSimulationTime"] = active;
							territoryArchive.append(entry);
							++territorySegmentCount;
							if (active) ++activeTerritorySegmentCount;
						}
					}
				}
			}
			result["hasTerritoryArchive"] = !territoryPath.isEmpty();
			result["territorySegmentCount"] = territorySegmentCount;
			result["territoryActiveSegmentCount"] = activeTerritorySegmentCount;
			result["territorySimulationYear"] = simulationYear;
			result["territoryArchive"] = territoryArchive;
			return result;
		}

		if (commandName == "getSkyCultureTerritoryGeometry")
		{
			StelSkyCultureMgr& skyCultureMgr = StelApp::getInstance().getSkyCultureMgr();
			bool yearIsValid = false;
			int selectedYear = arg.trimmed().toInt(&yearIsValid);
			if (!yearIsValid)
			{
				const double localJD = core->getJD() + core->getUTCOffset(core->getJD()) / 24.0;
				int month = 0;
				int day = 0;
				StelUtils::getDateFromJulianDay(localJD, &selectedYear, &month, &day);
			}
			selectedYear = qBound(-40000, selectedYear, 10000);
			const QString id = skyCultureMgr.getCurrentSkyCultureID();
			const QString territoryPath = StelFileMgr::findFile(QStringLiteral("skycultures/%1/territory.geojson").arg(id));
			QJsonArray polygons;
			if (!territoryPath.isEmpty())
			{
				QFile territoryFile(territoryPath);
				if (territoryFile.open(QFile::ReadOnly))
				{
					QJsonParseError parseError;
					const QJsonDocument territoryDocument = QJsonDocument::fromJson(territoryFile.readAll(), &parseError);
					if (parseError.error == QJsonParseError::NoError && territoryDocument.isObject())
					{
						const QJsonArray features = territoryDocument.object().value(QStringLiteral("features")).toArray();
						for (const QJsonValue& featureValue : features)
						{
							if (!featureValue.isObject()) continue;
							const QJsonObject feature = featureValue.toObject();
							const QJsonObject properties = feature.value(QStringLiteral("properties")).toObject();
							const int beginTime = properties.value(QStringLiteral("beginTime")).toInt();
							const int endTime = properties.value(QStringLiteral("endTime")).toInt();
							if ((beginTime != 0 && selectedYear < beginTime) || (endTime != 0 && endTime < 9000 && selectedYear > endTime)) continue;

							auto appendPolygon = [&](const QJsonArray& ring) {
								if (ring.size() < 3) return;
								const int stride = qMax(1, (ring.size() + 159) / 160);
								QJsonArray points;
								for (int pointIndex = 0; pointIndex < ring.size(); pointIndex += stride)
								{
									const QJsonArray coordinate = ring.at(pointIndex).toArray();
									if (coordinate.size() < 2) continue;
									QJsonArray point;
									point.append(coordinate.at(0).toDouble());
									point.append(coordinate.at(1).toDouble());
									points.append(point);
								}
								if (points.size() < 3) return;
								QJsonObject polygon;
								polygon["name"] = properties.value(QStringLiteral("name")).toString();
								polygon["beginTime"] = beginTime;
								polygon["endTime"] = endTime;
								polygon["points"] = points;
								polygons.append(polygon);
							};

							const QJsonObject geometry = feature.value(QStringLiteral("geometry")).toObject();
							const QString geometryType = geometry.value(QStringLiteral("type")).toString();
							const QJsonArray coordinates = geometry.value(QStringLiteral("coordinates")).toArray();
							if (geometryType == QLatin1String("Polygon") && !coordinates.isEmpty())
								appendPolygon(coordinates.at(0).toArray());
							else if (geometryType == QLatin1String("MultiPolygon"))
							{
								for (const QJsonValue& polygonValue : coordinates)
								{
									const QJsonArray polygonRings = polygonValue.toArray();
									if (!polygonRings.isEmpty()) appendPolygon(polygonRings.at(0).toArray());
								}
							}
						}
					}
				}
			}
			result["ok"] = true;
			result["year"] = selectedYear;
			result["territoryPolygons"] = polygons;
			return result;
		}

		if (commandName == "setSkyCultureLabelStyle")
		{
			StelSkyCultureMgr& skyCultureMgr = StelApp::getInstance().getSkyCultureMgr();
			const QStringList parts = arg.split('|');
			const QString target = parts.value(0).trimmed().toLower();
			const QString style = parts.value(1).trimmed();
			if (parts.size() != 2 || style.isEmpty())
			{
				result["ok"] = false;
				result["error"] = "setSkyCultureLabelStyle expects target|style";
				return result;
			}
			if (target == QLatin1String("screen"))
				skyCultureMgr.setScreenLabelStyle(style);
			else if (target == QLatin1String("info"))
				skyCultureMgr.setInfoLabelStyle(style);
			else if (target == QLatin1String("zodiac"))
				skyCultureMgr.setZodiacLabelStyle(style);
			else if (target == QLatin1String("lunar"))
				skyCultureMgr.setLunarSystemLabelStyle(style);
			else
			{
				result["ok"] = false;
				result["error"] = "unknown sky culture label target";
				return result;
			}
			result["ok"] = true;
			result["target"] = target;
			result["style"] = style;
			result["screenLabelStyle"] = skyCultureMgr.getScreenLabelStyleString();
			result["infoLabelStyle"] = skyCultureMgr.getInfoLabelStyleString();
			result["zodiacLabelStyle"] = skyCultureMgr.getZodiacLabelStyleString();
			result["lunarSystemLabelStyle"] = skyCultureMgr.getLunarSystemLabelStyleString();
			return result;
		}

		if (commandName == "setSkyCultureDefault")
		{
			StelSkyCultureMgr& skyCultureMgr = StelApp::getInstance().getSkyCultureMgr();
			const bool ok = skyCultureMgr.setDefaultSkyCultureID(arg.trimmed());
			result["ok"] = ok;
			result["defaultId"] = skyCultureMgr.getDefaultSkyCultureID();
			if (!ok)
				result["error"] = "invalid sky culture default";
			return result;
		}

		if (commandName == "setSkyCultureCommonNames")
		{
			StelSkyCultureMgr& skyCultureMgr = StelApp::getInstance().getSkyCultureMgr();
			const bool enabled = arg == "1" || arg.compare("true", Qt::CaseInsensitive) == 0;
			skyCultureMgr.setFlagOverrideUseCommonNames(enabled);
			result["ok"] = true;
			result["overrideCommonNames"] = skyCultureMgr.getFlagOverrideUseCommonNames();
			return result;
		}

		if (commandName == "reloadSkyCulture")
		{
			StelApp::getInstance().getSkyCultureMgr().reloadSkyCulture();
			result["ok"] = true;
			return result;
		}

		if (commandName == "setSkyCultureScreenLabelStyle")
		{
			StelSkyCultureMgr& skyCultureMgr = StelApp::getInstance().getSkyCultureMgr();
			skyCultureMgr.setScreenLabelStyle(arg);
			result["ok"] = true;
			result["screenLabelStyle"] = skyCultureMgr.getScreenLabelStyleString();
			return result;
		}

		if (commandName == "setSkyCultureShortLabels")
		{
			StelSkyCultureMgr& skyCultureMgr = StelApp::getInstance().getSkyCultureMgr();
			skyCultureMgr.setFlagUseAbbreviatedNames(arg == "1" || arg.compare("true", Qt::CaseInsensitive) == 0);
			result["ok"] = true;
			result["abbreviatedNames"] = skyCultureMgr.getFlagUseAbbreviatedNames();
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

		// setPluginLoadAtStartup — persist whether a plugin should load on the next launch
		if (commandName == "setPluginLoadAtStartup")
		{
			const QStringList parts = arg.split('|');
			if (parts.size() != 2)
			{
				result["ok"] = false;
				result["error"] = "format: pluginId|0|1";
				return result;
			}

			const QString pluginId = parts[0].trimmed();
			const bool enabled = parts[1] == "1" || parts[1].compare("true", Qt::CaseInsensitive) == 0;
			StelModuleMgr& moduleMgr = StelApp::getInstance().getModuleMgr();
			bool found = false;
			for (const auto& descriptor : moduleMgr.getPluginsList())
			{
				if (descriptor.info.id == pluginId)
				{
					found = true;
					break;
				}
			}
			if (!found)
			{
				result["ok"] = false;
				result["error"] = "unknown plugin: " + pluginId;
				return result;
			}

			moduleMgr.setPluginLoadAtStartup(pluginId, enabled);
			result["ok"] = true;
			result["id"] = pluginId;
			result["loadAtStartup"] = enabled;
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
			const QList<StelObjectP>& sel = StelApp::getInstance().getStelObjectMgr().getSelectedObject();
			if (sel.empty()) {
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			const StelObjectP& obj = sel[0];
			Vec3d altaz = obj->getAltAzPosApparent(StelApp::getInstance().getCore());
			Vec3d radec = obj->getEquinoxEquatorialPos(StelApp::getInstance().getCore());
			// `name` is the display contract used by the HarmonyOS detail UI.
			// Keep the stable English identifier separate so a localized catalog
			// name can never be accidentally replaced by it.
			info["name"] = obj->getNameI18n();
			if (info["name"].toString().isEmpty()) info["name"] = obj->getEnglishName();
			info["nameI18"] = obj->getNameI18n();
			info["englishName"] = obj->getEnglishName();
			info["type"] = obj->getObjectTypeI18n();
			info["typeId"] = obj->getType();
			info["ra"] = radec[0] * 180.0 / M_PI;
			info["dec"] = radec[1] * 180.0 / M_PI;
			info["alt"] = altaz[1] * 180.0 / M_PI;
			info["az"] = altaz[0] * 180.0 / M_PI;
			info["magnitude"] = obj->getVMagnitude(StelApp::getInstance().getCore());
			QString magStr = QString::number(obj->getVMagnitude(StelApp::getInstance().getCore()), 'f', 2);
			info["magStr"] = magStr;
			result["ok"] = true;
			result["info"] = info;
			return result;
		}

		// getObjectSpokenText — plain-language Chinese description of the
		// currently selected object, intended for Text-To-Speech playback.
		if (commandName == "getObjectSpokenText")
		{
			QJsonObject out;
			const QList<StelObjectP>& sel = StelApp::getInstance().getStelObjectMgr().getSelectedObject();
			if (sel.empty())
			{
				out["ok"] = false;
				out["error"] = "no object selected";
				return out;
			}
			const StelObjectP& obj = sel[0];
			const StelCore* core = StelApp::getInstance().getCore();

			auto azToCompass = [](double az) -> QString {
				const QString dirs[8] = { "正北", "东北", "正东", "东南", "正南", "西南", "正西", "西北" };
				int idx = qRound(az / 45.0) % 8;
				if (idx < 0) idx += 8;
				return dirs[idx];
			};

			QString name = obj->getNameI18n();
			QString typeI18 = obj->getObjectTypeI18n();
			double mag = obj->getVMagnitude(core);

			// Use getInfoMap for altitude/azimuth/distance (same source as the
			// object info panel) because getAltAzPosApparent returns a direction
			// vector, not angles.
			const QVariantMap m = obj->getInfoMap(core);
			double alt = m.value("altitude", 0.0).toDouble();
			double az = m.value("azimuth", 0.0).toDouble();

			QString spoken = name;
			if (!typeI18.isEmpty())
				spoken += QString("，类型 %1").arg(typeI18);

			// Constellation the object belongs to (consistent with panel display)
			Vec3d posJ2000 = obj->getJ2000EquatorialPos(core);
			QList<StelObjectP> csts = GETSTELMODULE(ConstellationMgr)->searchAround(posJ2000, 0.5, core);
			if (!csts.isEmpty())
				spoken += QString("，位于 %1").arg(csts.first()->getNameI18n());

			spoken += QString("，视星等 %1").arg(QString::number(mag, 'f', 2));

			spoken += QString("，高度 %1 度，方位 %2")
					  .arg(QString::number(alt, 'f', 0))
					  .arg(azToCompass(az));

			if (m.contains("distance"))
			{
				double distAu = m["distance"].toDouble();
				if (distAu > 0)
				{
					if (distAu < 0.01)
						spoken += QString("，距离 %1 天文单位").arg(QString::number(distAu, 'f', 4));
					else if (distAu < 1000.)
						spoken += QString("，距离 %1 天文单位").arg(QString::number(distAu, 'f', 2));
					else
						spoken += QString("，距离 %1 光年").arg(QString::number(distAu / 63241.077, 'f', 1));
				}
			}

			out["ok"] = true;
			out["text"] = spoken;
			return out;
		}

		// getConstellationInfo — get current constellation at center
		if (commandName == "getConstellationInfo")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			Vec3d viewDir = GETSTELMODULE(StelMovementMgr)->getViewDirectionJ2000();
			QList<StelObjectP> csts = GETSTELMODULE(ConstellationMgr)->searchAround(viewDir, 0.5, core);
			QString constellation = csts.isEmpty() ? QString() : csts.first()->getNameI18n();
			result["ok"] = true;
			result["name"] = constellation;
			return result;
		}

		// getStarCount — number of visible stars by magnitude
		if (commandName == "getStarCount")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			QJsonObject counts;
			Vec3d viewDir = GETSTELMODULE(StelMovementMgr)->getViewDirectionJ2000();
			double starFov = core->getMovementMgr()->getCurrentFov();
			counts["visible"] = GETSTELMODULE(StarMgr)->searchAround(viewDir, starFov, core).size();
			result["ok"] = true;
			result["counts"] = counts;
			return result;
		}

				// ========== Phase 2d ==========
		// getDSOCounts — count visible DSO objects by type
		if (commandName == "getDSOCounts")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			NebulaMgr* nm = GETSTELMODULE(NebulaMgr);
			QJsonObject counts;
			// Count all DSO currently displayed
			const QList<StelObjectP>& allDSO = nm->searchAround(GETSTELMODULE(StelMovementMgr)->getViewDirectionJ2000(), 180.0, core);
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


		// setJulianDate accepts a named date scale so the UI and CLI cannot
		// accidentally treat an MJD value as a full Julian Day. setTimeToJD is
		// retained as the legacy JD-only form used by the existing time controls.
		if (commandName == "setJulianDate" || commandName == "setTimeToJD")
		{
			QString scale = QStringLiteral("jd");
			QString numericText = arg.trimmed();
			if (commandName == "setJulianDate")
			{
				const int separator = numericText.indexOf('|');
				if (separator <= 0 || separator == numericText.size() - 1)
				{
					result["error"] = "setJulianDate expects jd|number or mjd|number";
					return result;
				}
				scale = numericText.left(separator).trimmed().toLower();
				numericText = numericText.mid(separator + 1).trimmed();
				if (scale != "jd" && scale != "mjd")
				{
					result["error"] = "setJulianDate scale must be jd or mjd";
					return result;
				}
			}
			bool numberOk = false;
			const double suppliedValue = numericText.toDouble(&numberOk);
			if (!numberOk || !std::isfinite(suppliedValue))
			{
				result["error"] = "Julian date must be a finite number";
				return result;
			}
			const double jd = scale == "mjd" ? suppliedValue + 2400000.5 : suppliedValue;
			if (!std::isfinite(jd))
			{
				result["error"] = "Julian date is outside the supported numeric range";
				return result;
			}
			StelCore* core = StelApp::getInstance().getCore();
			core->setJD(jd);
			core->setTimeRate(0.0);
			result["ok"] = true;
			result["jd"] = jd;
			result["mjd"] = jd - 2400000.5;
			result["calendarSystem"] = jd < 2299161.0 ? "julian" : "gregorian";
			return result;
		}

		// getSimulationTime — get current JD and time rate
		if (commandName == "getSimulationTime")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			const double jd = core->getJD();
			const double localJD = jd + core->getUTCOffset(jd) / 24.0;
			int year = 0;
			int month = 0;
			int day = 0;
			StelUtils::getDateFromJulianDay(localJD, &year, &month, &day);
			result["ok"] = true;
			result["jd"] = jd;
			result["mjd"] = jd - 2400000.5;
			result["calendarSystem"] = jd < 2299161.0 ? "julian" : "gregorian";
			result["julianDateStep"] = 0.00001;
			result["jdOfToday"] = jd;
			result["timeRate"] = core->getTimeRate();
			result["year"] = year;
			return result;
		}

				// ========== Phase 2e ==========
		// setLocationByName — move observer to a named location
		if (commandName == "setLocationByName")
		{
			StelCore* core = StelApp::getInstance().getCore();
			StelLocationMgr& locMgr = StelApp::getInstance().getLocationMgr();
			StelLocation loc = locMgr.locationForString(arg);
			if (loc.isValid()) {
				core->moveObserverTo(loc);
				result["ok"] = true;
				result["name"] = loc.name;
				result["latitude"] = loc.getLatitude();
				result["longitude"] = loc.getLongitude();
				result["altitude"] = loc.altitude;
			} else {
				result["ok"] = false;
				result["error"] = "location not found: " + arg;
			}
			return result;
		}

		// setLocationCoords — move observer to lat/lon/alt
		if (commandName == "setLocationCoords")
		{
			QStringList parts = arg.split(",");
			if (parts.size() >= 2) {
				double lat = parts[0].toDouble();
				double lon = parts[1].toDouble();
				double alt = parts.size() >= 3 ? parts[2].toDouble() : 0.0;
				StelCore* core = StelApp::getInstance().getCore();
				StelLocation loc;
				loc.setLatitude(lat);
				loc.setLongitude(lon);
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

		// getObserverPlanetList — list bodies the observer can stand on
		if (commandName == "getObserverPlanetList")
		{
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			QJsonArray list;
			if (ssys)
			{
				const QStringList names = ssys->getAllPlanetEnglishNames();
				for (const QString& n : names)
					list.append(n);
			}
			result["ok"] = true;
			result["planets"] = list;
			return result;
		}

		// setObserverPlanet — relocate the observer onto another planet (sky + landscape recompute)
		if (commandName == "setObserverPlanet")
		{
			if (!core)
			{
				result["error"] = "core not ready";
				return result;
			}
			const QStringList parts = arg.split('|');
			const QString planetName = parts.size() > 0 ? parts[0].trimmed() : QString();
			if (planetName.isEmpty())
			{
				result["error"] = "setObserverPlanet expects planetName[|lat|lon|alt]";
				return result;
			}
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			if (!ssys || !ssys->searchByEnglishName(planetName))
			{
				result["error"] = "unknown planet: " + planetName;
				return result;
			}
			const double lat = parts.size() > 1 ? parts[1].toDouble() : 0.0;
			const double lon = parts.size() > 2 ? parts[2].toDouble() : 0.0;
			const double alt = parts.size() > 3 ? parts[3].toDouble() : 0.0;
			StelLocation loc;
			loc.name = planetName + " surface";
			loc.region = QStringLiteral("User");
			loc.planetName = planetName;
			loc.setLatitude(static_cast<float>(lat));
			loc.setLongitude(static_cast<float>(lon));
			loc.altitude = alt;
			loc.role = QChar('X');
			loc.ianaTimeZone = QStringLiteral("system_default");
			// Best-effort landscape mapping (extraterrestrial landscapes are bundled)
			QString landscapeID;
			if (planetName == "Moon") landscapeID = "moon";
			else if (planetName == "Mars") landscapeID = "mars";
			else if (planetName == "Jupiter") landscapeID = "jupiter";
			else if (planetName == "Saturn") landscapeID = "saturn";
			else if (planetName == "Uranus") landscapeID = "uranus";
			else if (planetName == "Neptune") landscapeID = "neptune";
			else if (planetName == "Sun") landscapeID = "sun";
			else if (planetName == "Earth") landscapeID = "garching";
			core->moveObserverTo(loc, 0.0, 0.0, landscapeID);
			markOhosInteraction();
			result["ok"] = true;
			result["planetName"] = planetName;
			result["landscapeID"] = landscapeID;
			return result;
		}

		// getSelectedObjectInfo — full info for selected object (alias for existing)
		if (commandName == "getSelectedType")
		{
			const QList<StelObjectP>& sel = StelApp::getInstance().getStelObjectMgr().getSelectedObject();
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
			// getCurrentFov() 返回的已经是「度」，不能再乘 180/PI（会得到 3437 这类荒谬值）
			result["fov"] = fov;
			// Direction the center of view is looking at
			Vec3d adir = core->j2000ToAltAz(core->getMovementMgr()->getViewDirectionJ2000(), StelCore::RefractionOff);
			double alt = std::asin(adir[2]) * 180.0 / M_PI;
			double az = std::atan2(adir[1], -adir[0]) * 180.0 / M_PI;
			result["centerAlt"] = alt;
			result["centerAz"] = az;
			return result;
		}

		// setViewportOffset — 把投影中心在屏幕上平移，单位为屏幕宽/高的百分比（[-50, 50]）。
		// 用途：平板端右侧详情面板会遮挡画面右半部分，此时把投影中心左移，
		// 使被选中的天体正好落在「左侧工具栏与右侧详情面板之间」的可视空白区中央。
		// 参数格式："hPct|vPct"，例如 "-15.5|0"
		if (commandName == "setViewportOffset")
		{
			StelCore* core = StelApp::getInstance().getCore();
			if (!core) { result["error"] = "core not ready"; return result; }
			const QStringList parts = arg.split('|');
			bool okH = false;
			const double hPct = parts.size() > 0 ? parts[0].trimmed().toDouble(&okH) : 0.0;
			bool okV = false;
			const double vPct = parts.size() > 1 ? parts[1].trimmed().toDouble(&okV) : 0.0;
			if (!okH) { result["error"] = "expects hPct|vPct"; return result; }
			core->setViewportOffset(hPct, okV ? vPct : 0.0);
			result["ok"] = true;
			result["hOffset"] = core->getViewportHorizontalOffset();
			result["vOffset"] = core->getViewportVerticalOffset();
			return result;
		}

		// getViewportOffset — 读回当前视口偏移百分比
		if (commandName == "getViewportOffset")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			if (!core) { result["error"] = "core not ready"; return result; }
			result["ok"] = true;
			result["hOffset"] = core->getViewportHorizontalOffset();
			result["vOffset"] = core->getViewportVerticalOffset();
			return result;
		}

		// setFieldOfView — set FOV in degrees
		if (commandName == "setFieldOfView")
		{
			double fov = arg.toDouble();
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
			QStringList names = GETSTELMODULE(ConstellationMgr)->getConstellationsEnglishNames();
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
					double dec = std::asin(pos[2] / pos.norm()) * 180.0 / M_PI;
					double mag = obj->getVMagnitude(core);
				double dist = (qSharedPointerCast<Planet>(obj)) ? qSharedPointerCast<Planet>(obj)->getDistance() : 0.0;
				Vec3d altaz = obj->getAltAzPosApparent(core);
				double alt = std::asin(altaz[2] / altaz.norm()) * 180.0 / M_PI;
				double az = std::atan2(altaz[1], -altaz[0]) * 180.0 / M_PI;
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
			QString key = arg;
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
			conf->setValue("localization/date_display_format", arg);
			StelApp::getInstance().getLocaleMgr().setDateFormatStr(arg);
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
			conf->setValue("localization/time_display_format", arg);
			StelApp::getInstance().getLocaleMgr().setTimeFormatStr(arg);
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
			core->setDitheringMode(arg);
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
			double lum = arg.toDouble(&ok);
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
			int index = arg.toInt(&ok);
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

		if (commandName == "setSkyDisplaySetting")
		{
			const QStringList parts = arg.split('|');
			if (parts.size() < 2)
			{
				result["ok"] = false;
				result["error"] = "usage: setting|value";
				return result;
			}
			const QString setting = parts[0];
			const QString value = parts[1];
			const bool enabled = value == "1" || value.compare("true", Qt::CaseInsensitive) == 0;
			StelSkyDrawer* drawer = StelApp::getInstance().getCore()->getSkyDrawer();
			if (setting == "luminanceAdaptation") drawer->setFlagLuminanceAdaptation(enabled);
			else if (setting == "starTwinkle") drawer->setFlagTwinkle(enabled);
			else if (setting == "forcedStarTwinkle") drawer->setFlagForcedTwinkle(enabled);
			else if (setting == "bigStarHalo") drawer->setFlagDrawBigStarHalo(enabled);
			else if (setting == "starSpiky") drawer->setFlagStarSpiky(enabled);
			else if (setting == "twinkleAmount")
			{
				bool ok = false;
				const double amount = value.toDouble(&ok);
				if (!ok || amount < 0.0 || amount > 1.0)
				{
					result["ok"] = false;
					result["error"] = "twinkle amount must be 0..1";
					return result;
				}
				drawer->setTwinkleAmount(amount);
			}
			else if (setting == "bortleScale")
			{
				bool ok = false;
				const int index = value.toInt(&ok);
				if (!ok || index < 1 || index > 9)
				{
					result["ok"] = false;
					result["error"] = "Bortle scale must be 1-9";
					return result;
				}
				drawer->setLightPollutionLuminance(StelCore::bortleScaleIndexToLuminance(index));
			}
			else if (setting == "meteorZhr")
			{
				bool ok = false;
				const int zhr = value.toInt(&ok);
				SporadicMeteorMgr* mmgr = GETSTELMODULE(SporadicMeteorMgr);
				if (!ok || !mmgr || zhr < 0 || zhr > 1000)
				{
					result["ok"] = false;
					result["error"] = "meteor ZHR must be 0-1000";
					return result;
				}
				mmgr->setZHR(zhr);
			}
			else if (setting == "zodiacalLight" || setting == "zodiacalIntensity")
			{
				ZodiacalLight* zlight = GETSTELMODULE(ZodiacalLight);
				if (!zlight)
				{
					result["ok"] = false;
					result["error"] = "zodiacal light module unavailable";
					return result;
				}
				if (setting == "zodiacalLight") zlight->setFlagShow(enabled);
				else
				{
					bool ok = false;
					const double intensity = value.toDouble(&ok);
					if (!ok || intensity < 0.0 || intensity > 5.0)
					{
						result["ok"] = false;
						result["error"] = "zodiacal intensity must be 0..5";
						return result;
					}
					zlight->setIntensity(intensity);
				}
			}
			else
			{
				result["ok"] = false;
				result["error"] = "unknown sky display setting: " + setting;
				return result;
			}
			markOhosInteraction();
			result = currentStateJson();
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
			double scale = arg.toDouble(&ok);
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
			double scale = arg.toDouble(&ok);
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
			StelScriptMgr& sm = StelApp::getInstance().getScriptMgr();
			result["ok"] = true;
			result["running"] = sm.scriptIsRunning();
			result["scriptId"] = sm.runningScriptId();
			result["scriptRate"] = sm.getScriptRate();
			return result;
		}

		// getScriptRate / setScriptRate — script execution speed multiplier
		if (commandName == "getScriptRate")
		{
			result["ok"] = true;
			result["rate"] = StelApp::getInstance().getScriptMgr().getScriptRate();
			return result;
		}

		if (commandName == "setScriptRate")
		{
			bool ok;
			double rate = arg.toDouble(&ok);
			if (ok && rate > 0.0) {
				StelApp::getInstance().getScriptMgr().setScriptRate(rate);
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
			const QList<StelObjectP>& sel = StelApp::getInstance().getStelObjectMgr().getSelectedObject();
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
			StelApp::getInstance().getStelObjectMgr().unSelect();
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
			if (arg == "equatorial" || arg == "1") {
				mvmgr->setMountMode(StelMovementMgr::MountEquinoxEquatorial);
			} else if (arg == "galactic") {
				mvmgr->setMountMode(StelMovementMgr::MountGalactic);
			} else if (arg == "supergalactic") {
				mvmgr->setMountMode(StelMovementMgr::MountSupergalactic);
			} else {
				mvmgr->setMountMode(StelMovementMgr::MountAltAzimuthal);
			}
			result["ok"] = true;
			return result;
		}

		// moveToAltAz — point view to specific altitude/azimuth
		if (commandName == "gyroDiagnostic")
		{
			const QStringList parts = arg.split('|');
			if (parts.size() >= 4)
				qInfo().noquote() << QString("GYRO_RAW a=%1 b=%2 g=%3 samples=%4").arg(parts[0], parts[1], parts[2], parts[3]);
			result["ok"] = true;
			return result;
		}

		// moveToAltAz — point view to specific altitude/azimuth
		if (commandName == "moveToAltAz")
		{
			QStringList parts = arg.split('|');
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
					// A fixed world-Z up vector is parallel to the view at zenith and
					// nadir, which leaves the camera roll undefined and flips the sky.
					// Keep a continuous tangent basis instead.
					Vec3d aimUp(0., 0., 1.);
					aimUp -= aim * aim.dot(aimUp);
					if (aimUp.normSquared() < 1.e-8)
						aimUp = Vec3d(-cos(az * M_PI / 180.), -sin(az * M_PI / 180.), 0.) * (alt >= 0. ? 1. : -1.);
					else
						aimUp.normalize();
					if (parts.size() >= 6)
					{
						bool okUpX = false, okUpY = false, okUpZ = false;
						aimUp = Vec3d(parts[3].toDouble(&okUpX), parts[4].toDouble(&okUpY), parts[5].toDouble(&okUpZ));
						if (okUpX && okUpY && okUpZ && aimUp.normSquared() >= 0.0001)
							aimUp.normalize();
					}
					mvmgr->moveToAltAzi(aim, aimUp, duration);
					// ArkTS app logs are not exposed on every retail device. Keep a
					// throttled native record for validating the gyro coordinate frame.
					static int gyroDiagnosticCount = 0;
					if (parts.size() >= 9 && (++gyroDiagnosticCount % 120 == 0))
					{
						qInfo().noquote() << QString("GYRO_NATIVE raw=%1,%2,%3 -> az=%4 alt=%5")
							.arg(parts[6], parts[7], parts[8], parts[0], parts[1]);
					}
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

		if (commandName == "beginGyroViewTransition")
		{
			s_gyroTransitionArmed = true;
			s_gyroTransitionActive = false;
			// Searching first starts an automatic centering move. The device pose
			// must own the camera before sensor frames arrive, otherwise that move
			// overwrites every other gyro update.
			if (StelCore* core = StelApp::getInstance().getCore())
				core->getMovementMgr()->cancelAutoMove();
			s_gyroViewActive = true;
			result["ok"] = true;
			return result;
		}

		if (commandName == "cancelGyroViewTransition")
		{
			s_gyroTransitionArmed = false;
			s_gyroTransitionActive = false;
			s_gyroViewActive = false;
			// Resume a saved view lock from the camera position where the user
			// stopped using the gyro; correcting against an old anchor would jump.
			if (s_viewLock)
				s_ohosCaptureSelectedAnchorAfterPan = true;
			result["ok"] = true;
			return result;
		}

		// setGyroView — direct, non-animated view pose for device-pose tracking.
		//
		// moveToAltAz must not be used for this. Its auto-move path
		// (StelMovementMgr::updateAutoMove) unconditionally overwrites the
		// requested up vector with the local zenith on every frame when no
		// target object is set, so the device roll we send is thrown away, and
		// the forced upright vector snaps the view whenever the aim passes
		// close to the zenith. It also restarts an interpolation on every
		// sample, which shows up as stutter at sensor rates.
		//
		// Payload: az|alt[|upX|upY|upZ]  (up given in the same alt-az frame)
		if (commandName == "setGyroView")
		{
			const QStringList parts = arg.split('|');
			if (parts.size() < 2)
			{
				result["ok"] = false;
				result["error"] = "usage: az|alt[|upX|upY|upZ]";
				return result;
			}
			bool okAz = false, okAlt = false;
			const double azDeg = parts[0].toDouble(&okAz);
			const double altDeg = parts[1].toDouble(&okAlt);
			if (!okAz || !okAlt)
			{
				result["ok"] = false;
				result["error"] = "invalid az/alt";
				return result;
			}

			StelCore* core = StelApp::getInstance().getCore();
			StelMovementMgr* mvmgr = core->getMovementMgr();
			s_gyroViewActive = true;
			mvmgr->cancelAutoMove();
			// Sensor pose is continuous interaction, not an occasional command.
			// Keep the render pump at its high-refresh cadence while it is active.
			markOhosInteraction();
			if (mvmgr->getMountMode() != StelMovementMgr::MountAltAzimuthal)
				mvmgr->setMountMode(StelMovementMgr::MountAltAzimuthal);
			// The device pose owns the view while the gyro is on; object
			// tracking would fight it for the same frame.
			if (mvmgr->getFlagTracking())
				mvmgr->setFlagTracking(false);

			const double azRad = azDeg * M_PI / 180.;
			const double altRad = altDeg * M_PI / 180.;
			Vec3d aim(cos(altRad) * cos(azRad), cos(altRad) * sin(azRad), sin(altRad));
			aim.normalize();
			const Vec3d targetJ2000 = core->altAzToJ2000(aim, StelCore::RefractionOff);
			if (s_gyroTransitionArmed)
			{
				s_gyroTransitionArmed = false;
				s_gyroTransitionActive = true;
				s_gyroTransitionStartJ2000 = mvmgr->getViewDirectionJ2000();
				s_gyroTransitionTargetJ2000 = targetJ2000;
				s_gyroTransitionStartSec = StelApp::getTotalRunTime();
				result["ok"] = true;
				return result;
			}
			if (s_gyroTransitionActive)
			{
				s_gyroTransitionTargetJ2000 = targetJ2000;
				result["ok"] = true;
				return result;
			}

			// Keep physical zenith at the top through normal views so the horizon
			// remains level. The zenith projection becomes undefined only at the
			// two poles, where we blend to a transported basis to avoid a flip.
			const Vec3d zenith(0., 0., 1.);
			Vec3d zenithUp = zenith - aim * aim.dot(zenith);
			static Vec3d previousGyroUp(0., 0., 1.);
			static bool hasPreviousGyroUp = false;
			Vec3d transportedUp = previousGyroUp - aim * aim.dot(previousGyroUp);
			if (transportedUp.normSquared() < 1e-8)
				transportedUp = Vec3d(1., 0., 0.) - aim * aim.dot(Vec3d(1., 0., 0.));
			const double zenithStrength = zenithUp.normSquared();
			const double zenithBlend = std::clamp((zenithStrength - 0.01) / 0.09, 0.0, 1.0);
			Vec3d up = !hasPreviousGyroUp
				? zenithUp
				: transportedUp * (1.0 - zenithBlend) + zenithUp * zenithBlend;
			if (up.normSquared() < 1e-8)
				up = Vec3d(1., 0., 0.) - aim * aim.dot(Vec3d(1., 0., 0.));
			up.normalize();
			previousGyroUp = up;
			hasPreviousGyroUp = true;

			// Order matters: setViewDirectionJ2000() re-reads the *current* up
			// vector when it calls core->lookAtJ2000().
			mvmgr->setViewUpVector(up); // mount frame == alt-az here
			mvmgr->setViewDirectionJ2000(targetJ2000);
			result["ok"] = true;
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

		// getViewCenterCoordinates — all supported coordinate systems for the
		// current center of view. ArkUI can switch presentation without repeating
		// astronomical transforms or issuing multiple bridge requests.
		if (commandName == "getViewCenterCoordinates")
		{
			const StelCore* core = StelApp::getInstance().getCore();
			if (!core || !core->getMovementMgr())
			{
				result["ok"] = false;
				result["error"] = "core/movement not ready";
				return result;
			}

			const Vec3d viewJ2000 = core->getMovementMgr()->getViewDirectionJ2000();
			double j2000Ra = 0.0;
			double j2000Dec = 0.0;
			StelUtils::rectToSphe(&j2000Ra, &j2000Dec, viewJ2000);
			j2000Ra = StelUtils::fmodpos(j2000Ra, 2.0 * M_PI);

			double ofDateRa = 0.0;
			double ofDateDec = 0.0;
			StelUtils::rectToSphe(&ofDateRa, &ofDateDec,
				core->j2000ToEquinoxEqu(viewJ2000, StelCore::RefractionOff));
			ofDateRa = StelUtils::fmodpos(ofDateRa, 2.0 * M_PI);

			double horizontalLongitude = 0.0;
			double altitude = 0.0;
			StelUtils::rectToSphe(&horizontalLongitude, &altitude,
				core->j2000ToAltAz(viewJ2000, StelCore::RefractionOff));
			const double azimuth = StelUtils::fmodpos(3.0 * M_PI - horizontalLongitude, 2.0 * M_PI);

			double galacticLongitude = 0.0;
			double galacticLatitude = 0.0;
			StelUtils::rectToSphe(&galacticLongitude, &galacticLatitude,
				core->j2000ToGalactic(viewJ2000));
			galacticLongitude = StelUtils::fmodpos(galacticLongitude, 2.0 * M_PI);

			constexpr double radiansToDegrees = 180.0 / M_PI;
			result["ok"] = true;
			result["j2000Ra"] = StelUtils::radToHmsStr(j2000Ra, true);
			result["j2000Dec"] = StelUtils::radToDmsStr(j2000Dec, true);
			result["ofDateRa"] = StelUtils::radToHmsStr(ofDateRa, true);
			result["ofDateDec"] = StelUtils::radToDmsStr(ofDateDec, true);
			result["azimuthText"] = StelUtils::radToDmsStr(azimuth, true);
			result["altitudeText"] = StelUtils::radToDmsStr(altitude, true);
			result["galacticLongitude"] = StelUtils::radToDmsStr(galacticLongitude, true);
			result["galacticLatitude"] = StelUtils::radToDmsStr(galacticLatitude, true);
			result["j2000RaDegrees"] = j2000Ra * radiansToDegrees;
			result["j2000DecDegrees"] = j2000Dec * radiansToDegrees;
			result["ofDateRaDegrees"] = ofDateRa * radiansToDegrees;
			result["ofDateDecDegrees"] = ofDateDec * radiansToDegrees;
			result["azimuthDegrees"] = azimuth * radiansToDegrees;
			result["altitudeDegrees"] = altitude * radiansToDegrees;
			result["galacticLongitudeDegrees"] = galacticLongitude * radiansToDegrees;
			result["galacticLatitudeDegrees"] = galacticLatitude * radiansToDegrees;
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
			float duration = arg.toFloat(&ok);
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
			StelApp::getInstance().getCore()->setFlagGravityLabels(arg == "1" || arg == "true");
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
			StelApp::getInstance().getCore()->setFlagClearSky(arg == "1" || arg == "true");
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
			result["version"] = StelUtils::getApplicationVersion();
			result["dataDir"] = StelFileMgr::getUserDir();
			result["locale"] = StelApp::getInstance().getLocaleMgr().getAppLanguage();
			result["skyLanguage"] = StelApp::getInstance().getLocaleMgr().getSkyLanguage();
			result["jd"] = StelApp::getInstance().getCore()->getJD();
			StelLocation loc = StelApp::getInstance().getCore()->getCurrentLocation();
			result["location"] = loc.name;
			result["latitude"] = loc.getLatitude(false);
			result["longitude"] = loc.getLongitude(false);
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
			result["algorithm"] = core->getCurrentDeltaTAlgorithmDescription();
			return result;
		}

		// getLandscapeInfo — current landscape details
		if (commandName == "getLandscapeInfo")
		{
			const LandscapeMgr* lmgr = GETSTELMODULE(LandscapeMgr);
			result["ok"] = true;
			result["id"] = lmgr->getCurrentLandscapeID();
			result["name"] = lmgr->getCurrentLandscapeName();
			result["author"] = QString();
			result["description"] = lmgr->getCurrentLandscapeHtmlDescription();
			result["atmosphere"] = lmgr->getFlagAtmosphere();
			result["fog"] = lmgr->getFlagFog();
			result["ground"] = lmgr->getFlagLandscape();
			result["polyAngle"] = 0.0;
			result["transparency"] = lmgr->getLandscapeTransparency();
			return result;
		}

		// getDeltaTAlgorithmDescription — get deltaT algorithm name
		if (commandName == "getDeltaTAlgorithmDescription")
		{
			result["ok"] = true;
			result["description"] = core->getCurrentDeltaTAlgorithmDescription();
			return result;
		}

		// getLandscapeCount — total number of available landscapes
		if (commandName == "getLandscapeCount")
		{
			result["ok"] = true;
			result["count"] = GETSTELMODULE(LandscapeMgr)->getAllLandscapeIDs().size();
			return result;
		}

		// getStarCount — total number of stars loaded
		if (commandName == "getStarCountFull")
		{
			result["ok"] = true;
			result["total"] = GETSTELMODULE(StarMgr)->listAllObjects(true).size();
			return result;
		}

				// ========== Phase 2n ==========
		// getGridFlags — get all grid/line display flags
		if (commandName == "getGridFlags")
		{
			GridLinesMgr* gmgr = GETSTELMODULE(GridLinesMgr);
			QJsonObject flags;
			flags["azimuthalGrid"] = gmgr->getFlagAzimuthalGrid();
			flags["equatorGrid"] = gmgr->getFlagEquatorGrid();
			flags["eclipticGrid"] = gmgr->getFlagEclipticGrid();
			flags["equatorLine"] = gmgr->getFlagEquatorLine();
			flags["eclipticLine"] = gmgr->getFlagEclipticLine();
			flags["meridianLine"] = gmgr->getFlagMeridianLine();
			flags["horizonLine"] = gmgr->getFlagHorizonLine();
			flags["zenithNadir"] = gmgr->getFlagZenithNadir();
			flags["cardinalPoints"] = GETSTELMODULE(LandscapeMgr)->getFlagCardinalPoints();
			result["ok"] = true;
			result["flags"] = flags;
			return result;
		}

		// setGridFlag — toggle a single grid/line display
		if (commandName == "setGridFlag")
		{
			QStringList parts = arg.split('|');
			if (parts.size() >= 2) {
				QString flagName = parts[0];
				bool state = parts[1] == "1" || parts[1] == "true";
				GridLinesMgr* gmgr = GETSTELMODULE(GridLinesMgr);
				if (flagName == "azimuthalGrid") gmgr->setFlagAzimuthalGrid(state);
				else if (flagName == "equatorGrid") gmgr->setFlagEquatorGrid(state);
				else if (flagName == "eclipticGrid") gmgr->setFlagEclipticGrid(state);
				else if (flagName == "equatorLine") gmgr->setFlagEquatorLine(state);
				else if (flagName == "eclipticLine") gmgr->setFlagEclipticLine(state);
				else if (flagName == "meridianLine") gmgr->setFlagMeridianLine(state);
				else if (flagName == "horizonLine") gmgr->setFlagHorizonLine(state);
				else if (flagName == "zenithNadir") gmgr->setFlagZenithNadir(state);
				else if (flagName == "cardinalPoints") GETSTELMODULE(LandscapeMgr)->setFlagCardinalPoints(state);
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
			double fov = arg.toDouble(&ok);
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
			StelApp::getInstance().getCore()->getMovementMgr()->setFlagTracking(arg == "1" || arg == "true");
			result["ok"] = true;
			return result;
		}

		// getAutoZoom / setAutoZoom — auto-zoom on selection
		if (commandName == "getAutoZoom")
		{
			result["ok"] = true;
			result["autoZoom"] = StelApp::getInstance().getCore()->getMovementMgr()->getFlagAutoZoomOutResetsDirection();
			return result;
		}

		if (commandName == "setAutoZoom")
		{
			StelApp::getInstance().getCore()->getMovementMgr()->setFlagAutoZoomOutResetsDirection(arg == "1" || arg == "true");
			result["ok"] = true;
			return result;
		}

		// getMeteors / setMeteors — sporadic meteor display (SporadicMeteorMgr)
		if (commandName == "getMeteors")
		{
			SporadicMeteorMgr* mmgr = GETSTELMODULE(SporadicMeteorMgr);
			result["ok"] = true;
			result["meteors"] = mmgr ? mmgr->getFlagShow() : false;
			return result;
		}
		if (commandName == "setMeteors")
		{
			SporadicMeteorMgr* mmgr = GETSTELMODULE(SporadicMeteorMgr);
			if (mmgr)
			{
				mmgr->setFlagShow(arg == "1" || arg == "true");
				markOhosInteraction();
				result["ok"] = true;
			}
			else
			{
				result["ok"] = false;
				result["error"] = "meteor module unavailable";
			}
			return result;
		}

		// getDsoLabels / setDsoLabels — DSO designation labels (NebulaMgr::flagDesignationLabels)
		if (commandName == "getDsoLabels")
		{
			NebulaMgr* nmgr = GETSTELMODULE(NebulaMgr);
			result["ok"] = true;
			result["dsoLabels"] = nmgr ? nmgr->getDesignationUsage() : false;
			return result;
		}
		if (commandName == "setDsoLabels")
		{
			NebulaMgr* nmgr = GETSTELMODULE(NebulaMgr);
			if (nmgr)
			{
				nmgr->setDesignationUsage(arg == "1" || arg == "true");
				markOhosInteraction();
				result["ok"] = true;
			}
			else
			{
				result["ok"] = false;
				result["error"] = "nebula module unavailable";
			}
			return result;
		}

		// getAutoZoomResets / setAutoZoomResets — auto-zoom-out resets direction
		if (commandName == "getAutoZoomResets")
		{
			StelMovementMgr* mvmgr = GETSTELMODULE(StelMovementMgr);
			result["ok"] = true;
			result["autoZoomResets"] = mvmgr ? mvmgr->getFlagAutoZoomOutResetsDirection() : false;
			return result;
		}
		if (commandName == "setAutoZoomResets")
		{
			StelMovementMgr* mvmgr = GETSTELMODULE(StelMovementMgr);
			if (mvmgr)
			{
				mvmgr->setFlagAutoZoomOutResetsDirection(arg == "1" || arg == "true");
				markOhosInteraction();
				result["ok"] = true;
			}
			else
			{
				result["ok"] = false;
				result["error"] = "movement module unavailable";
			}
			return result;
		}

				// ========== Phase 2o ==========
		// getLimitMagnitude / setLimitMagnitude — star visibility limit
		if (commandName == "getLimitMagnitude")
		{
			StelSkyDrawer* drawer = StelApp::getInstance().getCore()->getSkyDrawer();
			result["ok"] = true;
			result["limitMagnitude"] = drawer->getLimitMagnitude();
			result["customStarMagLimit"] = drawer->getCustomStarMagnitudeLimit();
			result["starMagnitudeLimitEnabled"] = drawer->getFlagStarMagnitudeLimit();
			result["flagNebulaMagLimit"] = drawer->getFlagNebulaMagnitudeLimit();
			result["customNebulaMagLimit"] = drawer->getCustomNebulaMagnitudeLimit();
			return result;
		}

		if (commandName == "setLimitMagnitude")
		{
			bool ok;
			double mag = arg.toDouble(&ok);
			if (ok) {
				StelSkyDrawer* drawer = StelApp::getInstance().getCore()->getSkyDrawer();
				// The custom value alone is inert in Stellarium. It takes effect only
				// while the explicit user magnitude-limit flag is enabled.
				drawer->setFlagStarMagnitudeLimit(true);
				drawer->setCustomStarMagnitudeLimit(std::clamp(mag, 2.0, 9.0));
				result["ok"] = true;
				result["customStarMagLimit"] = drawer->getCustomStarMagnitudeLimit();
				result["starMagnitudeLimitEnabled"] = drawer->getFlagStarMagnitudeLimit();
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
			result["intensity"] = GETSTELMODULE(MilkyWay)->getIntensity();
			return result;
		}

		if (commandName == "setMilkyWayIntensity")
		{
			bool ok;
			double intensity = arg.toDouble(&ok);
			if (ok && intensity >= 0.0) {
				GETSTELMODULE(MilkyWay)->setIntensity(intensity);
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
			result["intensity"] = GETSTELMODULE(LandscapeMgr)->getAtmosphereFadeDuration();
			return result;
		}

		// getAppVersion — simple version string
		if (commandName == "getAppVersion")
		{
			result["ok"] = true;
			result["version"] = StelUtils::getApplicationVersion();
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
			flags["constellationPick"] = cmgr->getFlagConstellationPick();
			result["ok"] = true;
			result["flags"] = flags;
			return result;
		}

		if (commandName == "setConstellationFlag")
		{
			QStringList parts = arg.split('|');
			if (parts.size() >= 2) {
				QString flagName = parts[0];
				bool state = parts[1] == "1" || parts[1] == "true";
				ConstellationMgr* cmgr = GETSTELMODULE(ConstellationMgr);
				if (flagName == "lines") cmgr->setFlagLines(state);
				else if (flagName == "boundaries") cmgr->setFlagBoundaries(state);
				else if (flagName == "art") cmgr->setFlagArt(state);
				else if (flagName == "labels") cmgr->setFlagLabels(state);
				else if (flagName == "isolateSelected") cmgr->setFlagIsolateSelected(state);
				else if (flagName == "constellationPick") cmgr->setFlagConstellationPick(state);
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

		if (commandName == "getOrbitDisplaySettings")
		{
			SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
			if (!solarSystem)
			{
				result["error"] = "solar system module unavailable";
				return result;
			}
			result["ok"] = true;
			result["orbitIsolated"] = solarSystem->getFlagIsolatedOrbits();
			result["orbitMajorPlanets"] = solarSystem->getFlagPlanetsOrbits();
			result["orbitPlanetsOnly"] = solarSystem->getFlagPlanetsOrbitsOnly();
			result["orbitWithMoons"] = solarSystem->getFlagOrbitsWithMoons();
			result["orbitPermanent"] = solarSystem->getFlagPermanentOrbits();
			result["orbitThickness"] = solarSystem->getOrbitsThickness();
			result["orbitColorStyle"] = solarSystem->getOrbitColorStyle();
			return result;
		}

		if (commandName == "setOrbitDisplaySetting")
		{
			const QString setting = arg.section('|', 0, 0).trimmed();
			const QString value = arg.section('|', 1, 1).trimmed();
			SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
			if (!solarSystem)
			{
				result["error"] = "solar system module unavailable";
				return result;
			}

			const bool enabled = value == "1" || value.compare("true", Qt::CaseInsensitive) == 0;
			if (setting == "isolated")
				solarSystem->setFlagIsolatedOrbits(enabled);
			else if (setting == "majorPlanets")
				solarSystem->setFlagPlanetsOrbits(enabled);
			else if (setting == "planetsOnly")
				solarSystem->setFlagPlanetsOrbitsOnly(enabled);
			else if (setting == "withMoons")
				solarSystem->setFlagOrbitsWithMoons(enabled);
			else if (setting == "permanent")
				solarSystem->setFlagPermanentOrbits(enabled);
			else if (setting == "thickness")
			{
				bool parsed = false;
				const int thickness = value.toInt(&parsed);
				if (!parsed || thickness < 1 || thickness > 5)
				{
					result["error"] = "orbit thickness must be between 1 and 5";
					return result;
				}
				solarSystem->setOrbitsThickness(thickness);
			}
			else if (setting == "colorStyle")
			{
				if (value != "one_color" && value != "groups" && value != "major_planets" && value != "major_planets_minor_types")
				{
					result["error"] = "unknown orbit color style";
					return result;
				}
				solarSystem->setOrbitColorStyle(value);
			}
			else
			{
				result["error"] = "unknown orbit display setting";
				return result;
			}

			markOhosInteraction();
			result["ok"] = true;
			return result;
		}

		if (commandName == "getTrailDisplaySettings")
		{
			SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
			if (!solarSystem)
			{
				result["error"] = "solar system module unavailable";
				return result;
			}
			result["ok"] = true;
			result["trailIsolated"] = solarSystem->getFlagIsolatedTrails();
			result["trailSelectionCount"] = solarSystem->getNumberIsolatedTrails();
			result["trailYears"] = solarSystem->getMaxTrailTimeExtent();
			result["trailThickness"] = solarSystem->getTrailsThickness();
			result["trailColor"] = solarSystem->getTrailsColor().toHtmlColor().toUpper();
			return result;
		}

		if (commandName == "setTrailDisplaySetting")
		{
			const QString setting = arg.section('|', 0, 0).trimmed();
			const QString value = arg.section('|', 1, 1).trimmed();
			SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
			if (!solarSystem)
			{
				result["error"] = "solar system module unavailable";
				return result;
			}

			if (setting == "isolated")
			{
				const bool enabled = value == "1" || value.compare("true", Qt::CaseInsensitive) == 0;
				solarSystem->setFlagIsolatedTrails(enabled);
			}
			else if (setting == "selectionCount" || setting == "years" || setting == "thickness")
			{
				bool parsed = false;
				const int number = value.toInt(&parsed);
				if (!parsed)
				{
					result["error"] = "trail setting expects an integer";
					return result;
				}
				if (setting == "selectionCount" && number >= 1 && number <= 5)
					solarSystem->setNumberIsolatedTrails(number);
				else if (setting == "years" && number >= 1 && number <= 250)
					solarSystem->setMaxTrailTimeExtent(number);
				else if (setting == "thickness" && number >= 1 && number <= 5)
					solarSystem->setTrailsThickness(number);
				else
				{
					result["error"] = "trail setting value out of range";
					return result;
				}
			}
			else if (setting == "color")
			{
				QString colorText = value;
				if (colorText.startsWith('#')) colorText.remove(0, 1);
				const QRegularExpression hexColorExpression(QStringLiteral("^[0-9A-Fa-f]{6}$"));
				if (!hexColorExpression.match(colorText).hasMatch())
				{
					result["error"] = "trail color expects #RRGGBB";
					return result;
				}
				bool redOk = false;
				bool greenOk = false;
				bool blueOk = false;
				const int red = colorText.mid(0, 2).toInt(&redOk, 16);
				const int green = colorText.mid(2, 2).toInt(&greenOk, 16);
				const int blue = colorText.mid(4, 2).toInt(&blueOk, 16);
				if (!redOk || !greenOk || !blueOk)
				{
					result["error"] = "invalid trail color";
					return result;
				}
				const Vec3f color(red / 255.f, green / 255.f, blue / 255.f);
				solarSystem->setTrailsColor(color);
				StelApp::immediateSave("color/object_trails_color", color.toStr());
			}
			else
			{
				result["error"] = "unknown trail display setting";
				return result;
			}

			markOhosInteraction();
			result["ok"] = true;
			result["trailColor"] = solarSystem->getTrailsColor().toHtmlColor().toUpper();
			return result;
		}

		if (commandName == "getSkyCultureVisualSettings")
		{
			ConstellationMgr* cmgr = GETSTELMODULE(ConstellationMgr);
			AsterismMgr* amgr = GETSTELMODULE(AsterismMgr);
			if (!cmgr || !amgr)
			{
				result["error"] = "sky culture display managers unavailable";
				return result;
			}
			result["ok"] = true;
			result["constellationFontSize"] = cmgr->getFontSize();
			result["constellationLineThickness"] = cmgr->getConstellationLineThickness();
			result["constellationBoundaryThickness"] = cmgr->getBoundariesThickness();
			result["constellationHullsThickness"] = cmgr->getHullsThickness();
			result["zodiacThickness"] = cmgr->getZodiacThickness();
			result["lunarSystemThickness"] = cmgr->getLunarSystemThickness();
			result["constellationArtIntensity"] = cmgr->getArtIntensity();
			result["constellationLinesFadeDuration"] = cmgr->getLinesFadeDuration();
			result["constellationLabelsFadeDuration"] = cmgr->getLabelsFadeDuration();
			result["constellationArtFadeDuration"] = cmgr->getArtFadeDuration();
			result["constellationBoundariesFadeDuration"] = cmgr->getBoundariesFadeDuration();
			result["constellationHullsFadeDuration"] = cmgr->getHullsFadeDuration();
			result["zodiacFadeDuration"] = cmgr->getZodiacFadeDuration();
			result["lunarSystemFadeDuration"] = cmgr->getLunarSystemFadeDuration();
			result["asterismFontSize"] = amgr->getFontSize();
			result["asterismLineThickness"] = amgr->getAsterismLineThickness();
			result["rayHelperThickness"] = amgr->getRayHelperThickness();
			result["asterismLinesFadeDuration"] = amgr->getLinesFadeDuration();
			result["asterismLabelsFadeDuration"] = amgr->getLabelsFadeDuration();
			result["rayHelperFadeDuration"] = amgr->getRayHelpersFadeDuration();
			QJsonObject colors;
			colors["constellationLines"] = cmgr->getLinesColor().toHtmlColor().toUpper();
			colors["constellationLabels"] = cmgr->getLabelsColor().toHtmlColor().toUpper();
			colors["constellationBoundaries"] = cmgr->getBoundariesColor().toHtmlColor().toUpper();
			colors["constellationHulls"] = cmgr->getHullsColor().toHtmlColor().toUpper();
			colors["zodiac"] = cmgr->getZodiacColor().toHtmlColor().toUpper();
			colors["lunarSystem"] = cmgr->getLunarSystemColor().toHtmlColor().toUpper();
			colors["asterismLines"] = amgr->getLinesColor().toHtmlColor().toUpper();
			colors["asterismLabels"] = amgr->getLabelsColor().toHtmlColor().toUpper();
			colors["rayHelpers"] = amgr->getRayHelpersColor().toHtmlColor().toUpper();
			result["skyCultureColors"] = colors;
			return result;
		}

		if (commandName == "setSkyCultureVisualSetting")
		{
			const QString setting = arg.section('|', 0, 0);
			bool parsed = false;
			const double value = arg.section('|', 1, 1).toDouble(&parsed);
			if (!parsed)
			{
				result["error"] = "invalid sky culture display value";
				return result;
			}

			ConstellationMgr* cmgr = GETSTELMODULE(ConstellationMgr);
			AsterismMgr* amgr = GETSTELMODULE(AsterismMgr);
			if (!cmgr || !amgr)
			{
				result["error"] = "sky culture display managers unavailable";
				return result;
			}

			if (setting == "constellationFontSize" && value >= 8.0 && value <= 40.0)
				cmgr->setFontSize(qRound(value));
			else if (setting == "constellationLineThickness" && value >= 1.0 && value <= 5.0)
				cmgr->setConstellationLineThickness(qRound(value));
			else if (setting == "constellationBoundaryThickness" && value >= 1.0 && value <= 5.0)
				cmgr->setBoundariesThickness(qRound(value));
			else if (setting == "constellationHullsThickness" && value >= 1.0 && value <= 5.0)
				cmgr->setHullsThickness(qRound(value));
			else if (setting == "zodiacThickness" && value >= 1.0 && value <= 5.0)
				cmgr->setZodiacThickness(qRound(value));
			else if (setting == "lunarSystemThickness" && value >= 1.0 && value <= 5.0)
				cmgr->setLunarSystemThickness(qRound(value));
			else if (setting == "constellationArtIntensity" && value >= 0.0 && value <= 1.0)
				cmgr->setArtIntensity(static_cast<float>(value));
			else if (setting == "constellationLinesFadeDuration" && value >= 0.1 && value <= 10.0)
				cmgr->setLinesFadeDuration(static_cast<float>(value));
			else if (setting == "constellationLabelsFadeDuration" && value >= 0.1 && value <= 10.0)
				cmgr->setLabelsFadeDuration(static_cast<float>(value));
			else if (setting == "constellationArtFadeDuration" && value >= 0.1 && value <= 10.0)
				cmgr->setArtFadeDuration(static_cast<float>(value));
			else if (setting == "constellationBoundariesFadeDuration" && value >= 0.1 && value <= 10.0)
				cmgr->setBoundariesFadeDuration(static_cast<float>(value));
			else if (setting == "constellationHullsFadeDuration" && value >= 0.1 && value <= 10.0)
				cmgr->setHullsFadeDuration(static_cast<float>(value));
			else if (setting == "zodiacFadeDuration" && value >= 0.1 && value <= 10.0)
				cmgr->setZodiacFadeDuration(static_cast<float>(value));
			else if (setting == "lunarSystemFadeDuration" && value >= 0.1 && value <= 10.0)
				cmgr->setLunarSystemFadeDuration(static_cast<float>(value));
			else if (setting == "asterismFontSize" && value >= 8.0 && value <= 40.0)
				amgr->setFontSize(qRound(value));
			else if (setting == "asterismLineThickness" && value >= 1.0 && value <= 5.0)
				amgr->setAsterismLineThickness(qRound(value));
			else if (setting == "rayHelperThickness" && value >= 1.0 && value <= 5.0)
				amgr->setRayHelperThickness(qRound(value));
			else if (setting == "asterismLinesFadeDuration" && value >= 0.1 && value <= 10.0)
				amgr->setLinesFadeDuration(static_cast<float>(value));
			else if (setting == "asterismLabelsFadeDuration" && value >= 0.1 && value <= 10.0)
				amgr->setLabelsFadeDuration(static_cast<float>(value));
			else if (setting == "rayHelperFadeDuration" && value >= 0.1 && value <= 10.0)
				amgr->setRayHelpersFadeDuration(static_cast<float>(value));
			else
			{
				result["error"] = "sky culture display value out of range";
				return result;
			}

			markOhosInteraction();
			result["ok"] = true;
			return result;
		}

		if (commandName == "setSkyCultureVisualColor")
		{
			const QString setting = arg.section('|', 0, 0).trimmed();
			QString colorText = arg.section('|', 1, 1).trimmed();
			if (colorText.startsWith('#')) colorText.remove(0, 1);
			const QRegularExpression hexColorExpression(QStringLiteral("^[0-9A-Fa-f]{6}$"));
			if (!hexColorExpression.match(colorText).hasMatch())
			{
				result["error"] = "sky culture color expects #RRGGBB";
				return result;
			}
			bool redOk = false;
			bool greenOk = false;
			bool blueOk = false;
			const int red = colorText.mid(0, 2).toInt(&redOk, 16);
			const int green = colorText.mid(2, 2).toInt(&greenOk, 16);
			const int blue = colorText.mid(4, 2).toInt(&blueOk, 16);
			if (!redOk || !greenOk || !blueOk)
			{
				result["error"] = "invalid sky culture color";
				return result;
			}
			const Vec3f color(red / 255.f, green / 255.f, blue / 255.f);
			ConstellationMgr* cmgr = GETSTELMODULE(ConstellationMgr);
			AsterismMgr* amgr = GETSTELMODULE(AsterismMgr);
			if (!cmgr || !amgr)
			{
				result["error"] = "sky culture display managers unavailable";
				return result;
			}

			if (setting == "constellationLines")
			{
				cmgr->setLinesColor(color);
				StelApp::immediateSave("color/const_lines_color", color.toStr());
			}
			else if (setting == "constellationLabels")
			{
				cmgr->setLabelsColor(color);
				StelApp::immediateSave("color/const_names_color", color.toStr());
			}
			else if (setting == "constellationBoundaries")
			{
				cmgr->setBoundariesColor(color);
				StelApp::immediateSave("color/const_boundary_color", color.toStr());
			}
			else if (setting == "constellationHulls")
			{
				cmgr->setHullsColor(color);
				StelApp::immediateSave("color/const_hull_color", color.toStr());
			}
			else if (setting == "zodiac")
			{
				cmgr->setZodiacColor(color);
				StelApp::immediateSave("color/skyculture_zodiac_color", color.toStr());
			}
			else if (setting == "lunarSystem")
			{
				cmgr->setLunarSystemColor(color);
				StelApp::immediateSave("color/skyculture_lunarsystem_color", color.toStr());
			}
			else if (setting == "asterismLines")
			{
				amgr->setLinesColor(color);
				StelApp::immediateSave("color/asterism_lines_color", color.toStr());
			}
			else if (setting == "asterismLabels")
			{
				amgr->setLabelsColor(color);
				StelApp::immediateSave("color/asterism_names_color", color.toStr());
			}
			else if (setting == "rayHelpers")
			{
				amgr->setRayHelpersColor(color);
				StelApp::immediateSave("color/rayhelper_lines_color", color.toStr());
			}
			else
			{
				result["error"] = "unknown sky culture color";
				return result;
			}

			markOhosInteraction();
			result["ok"] = true;
			result["setting"] = setting;
			result["color"] = color.toHtmlColor().toUpper();
			return result;
		}

		// getConstellationForPosition — get constellation name at a sky position
		if (commandName == "getConstellationForPosition")
		{
			QStringList parts = arg.split('|');
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
			result["autoZoom"] = mvmgr->getFlagAutoZoomOutResetsDirection();
			result["jd"] = core->getJD();
			result["timeRate"] = core->getTimeRate();
			result["projection"] = core->getCurrentProjectionTypeKey();
			result["location"] = core->getCurrentLocation().name;
			result["lat"] = core->getCurrentLocation().getLatitude(false);
			result["lon"] = core->getCurrentLocation().getLongitude(false);
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
			QStringList parts = arg.split('|');
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
			QStringList parts = arg.split('|');
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
			QStringList parts = arg.split('|');
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
			StelObjectMgr* objMgr = &StelApp::getInstance().getStelObjectMgr();
			const QList<StelObjectP>& sel = objMgr->getSelectedObject();
			if (sel.isEmpty()) {
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			StelCore* core = StelApp::getInstance().getCore();
			const StelObjectP object = sel.first();
			const double currentJD = core->getJD();
			double previous[3] = { 0.0, 0.0, 0.0 };
			double next[3] = { 0.0, 0.0, 0.0 };

			// getRTSTime() calculates the local civil date containing core->getJD().
			// Scan nearby dates so the result is truly the previous/next event rather
			// than an event earlier today labelled as "next".
			for (int dayOffset = -2; dayOffset <= 2; ++dayOffset)
			{
				core->setJD(currentJD + dayOffset);
				core->update(0);
				const Vec4d rts = object->getRTSTime(core);
				for (int event = 0; event < 3; ++event)
				{
					const double eventJD = rts[event];
					if (eventJD <= 0.0)
						continue;
					if (eventJD <= currentJD && eventJD > previous[event])
						previous[event] = eventJD;
					if (eventJD >= currentJD && (next[event] <= 0.0 || eventJD < next[event]))
						next[event] = eventJD;
				}
			}
			core->setJD(currentJD);
			core->update(0);
			auto formatLocal = [&](double jd) -> QString {
				if (jd <= 0.0)
					return QString();
				return StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
			};

			QJsonObject rtsResult;
			rtsResult["name"] = object->getNameI18n();
			if (rtsResult["name"].toString().isEmpty())
				rtsResult["name"] = object->getEnglishName();
			rtsResult["nextRiseJD"] = next[0];
			rtsResult["nextTransitJD"] = next[1];
			rtsResult["nextSetJD"] = next[2];
			rtsResult["nextRiseText"] = formatLocal(next[0]);
			rtsResult["nextTransitText"] = formatLocal(next[1]);
			rtsResult["nextSetText"] = formatLocal(next[2]);
			rtsResult["prevRiseJD"] = previous[0];
			rtsResult["prevTransitJD"] = previous[1];
			rtsResult["prevSetJD"] = previous[2];
			rtsResult["prevRiseText"] = formatLocal(previous[0]);
			rtsResult["prevTransitText"] = formatLocal(previous[1]);
			rtsResult["prevSetText"] = formatLocal(previous[2]);
			result["ok"] = true;
			result["rts"] = rtsResult;
			return result;
		}

		// getRTSCalendar — desktop AstroCalc's daily rise/transit/set table for
		// the selected object, adapted to a compact mobile result list.
		if (commandName == "getRTSCalendar")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const QList<StelObjectP>& selected = objectMgr->getSelectedObject();
			if (selected.isEmpty())
			{
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			const StelObjectP object = selected.first();
			const int days = qBound(1, options.value("days").toInt(14), 366);
			const double currentJD = core->getJD();
			double startJD = options.value("jd").toDouble(currentJD);
			if (startJD <= 0.0) startJD = currentJD;
			const QString requestKey = object->getEnglishName() + QLatin1Char('|') + arg;
			if (s_ohosRtsCalendarJob && s_ohosRtsCalendarJob->key != requestKey)
			{
				delete s_ohosRtsCalendarJob;
				s_ohosRtsCalendarJob = nullptr;
			}
			if (!s_ohosRtsCalendarJob)
			{
				s_ohosRtsCalendarJob = new OhosRtsCalendarJob;
				s_ohosRtsCalendarJob->key = requestKey;
				s_ohosRtsCalendarJob->object = object;
				s_ohosRtsCalendarJob->name = object->getNameI18n().isEmpty() ? object->getEnglishName() : object->getNameI18n();
				s_ohosRtsCalendarJob->originalJD = currentJD;
				s_ohosRtsCalendarJob->totalDays = days;
				const double utcOffset = core->getUTCOffset(startJD) / 24.0;
				s_ohosRtsCalendarJob->firstLocalMidnight = std::floor(startJD + utcOffset - 0.5) + 0.5 - utcOffset;
			}

			OhosRtsCalendarJob& job = *s_ohosRtsCalendarJob;
			PlanetP sun = GETSTELMODULE(SolarSystem)->getSun();
			PlanetP moon = GETSTELMODULE(SolarSystem)->getMoon();

			auto formatLocal = [&](double jd) -> QString {
				return jd > 0.0 ? StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0) : QString();
			};
			auto localDateNumber = [&](double jd) -> int {
				int year = 0;
				int month = 0;
				int day = 0;
				StelUtils::getDateFromJulianDay(jd + core->getUTCOffset(jd) / 24.0, &year, &month, &day);
				return year * 10000 + month * 100 + day;
			};

			QElapsedTimer sliceTimer;
			sliceTimer.start();
			int processedDays = 0;
			while (job.nextDay < job.totalDays && (processedDays == 0 || sliceTimer.elapsed() < OHOS_RTS_CALENDAR_SLICE_MS))
			{
				const int dayOffset = job.nextDay;
				const double localMidnight = job.firstLocalMidnight + dayOffset;
				const double localNoon = localMidnight + 0.5;
				core->setJD(localNoon);
				core->update(0);
				const Vec4d rts = job.object->StelObject::getRTSTime(core);
				const int expectedDate = localDateNumber(localNoon);
				const bool alwaysBelow = rts[3] < 0.0;
				const bool circumpolar = rts[3] > 50.0;
				const bool validTransit = rts[1] > 0.0 && rts[3] != 20.0 && localDateNumber(rts[1]) == expectedDate;
				const bool validRise = rts[0] > 0.0 && rts[3] != 30.0 && !alwaysBelow && !circumpolar && localDateNumber(rts[0]) == expectedDate;
				const bool validSet = rts[2] > 0.0 && rts[3] != 40.0 && !alwaysBelow && !circumpolar && localDateNumber(rts[2]) == expectedDate;
				QJsonObject row;
				row["date"] = formatLocal(localNoon);
				row["rise"] = validRise ? formatLocal(rts[0]) : QString();
				row["transit"] = validTransit ? formatLocal(rts[1]) : QString();
				row["set"] = validSet ? formatLocal(rts[2]) : QString();
				row["riseJD"] = validRise ? rts[0] : 0.0;
				row["transitJD"] = validTransit ? rts[1] : 0.0;
				row["setJD"] = validSet ? rts[2] : 0.0;
				if (alwaysBelow)
					row["status"] = sun && job.object == sun ? QStringLiteral("极夜") : QStringLiteral("从不升起");
				else if (circumpolar)
					row["status"] = sun && job.object == sun ? QStringLiteral("极昼") : QStringLiteral("拱极不落");
				else if (!validTransit)
					row["status"] = QStringLiteral("当天无中天");
				if (validTransit)
				{
					core->setJD(rts[1]);
					core->update(0);
					double azimuth = 0.0;
					double altitude = 0.0;
					StelUtils::rectToSphe(&azimuth, &altitude, job.object->getAltAzPosAuto(core));
					row["transitAltitude"] = altitude * M_180_PI;
					const float magnitude = job.object->getVMagnitudeWithExtinction(core);
					if (magnitude < 50.0f) row["magnitude"] = magnitude;
					if (sun && job.object != sun)
						row["solarElongation"] = job.object->getJ2000EquatorialPos(core).angle(sun->getJ2000EquatorialPos(core)) * M_180_PI;
					if (moon && job.object != moon && core->getCurrentPlanet() == GETSTELMODULE(SolarSystem)->getEarth())
						row["lunarElongation"] = job.object->getJ2000EquatorialPos(core).angle(moon->getJ2000EquatorialPos(core)) * M_180_PI;
				}
				job.rows.append(row);
				++job.nextDay;
				++processedDays;
			}
			core->setJD(job.originalJD);
			core->update(0);
			if (job.nextDay < job.totalDays)
			{
				result["ok"] = false;
				result["pending"] = true;
				result["progress"] = job.nextDay;
				result["totalDays"] = job.totalDays;
				return result;
			}
			result["ok"] = true;
			result["name"] = job.name;
			result["rtsCalendar"] = job.rows;
			delete s_ohosRtsCalendarJob;
			s_ohosRtsCalendarJob = nullptr;
			return result;
		}

		// getVMagnitude — apparent V magnitude of selected object
		if (commandName == "getVMagnitude")
		{
			StelObjectMgr* objMgr = &StelApp::getInstance().getStelObjectMgr();
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
			StelObjectMgr* objMgr = &StelApp::getInstance().getStelObjectMgr();
			const QList<StelObjectP>& sel = objMgr->getSelectedObject();
			if (sel.isEmpty()) {
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			result["ok"] = true;
			result["distance"] = (qSharedPointerCast<Planet>(sel.first())) ? qSharedPointerCast<Planet>(sel.first())->getDistance() : 0.0;
			return result;
		}

		// getSolarElongation — solar elongation of selected object
		if (commandName == "getSolarElongation")
		{
			StelObjectMgr* objMgr = &StelApp::getInstance().getStelObjectMgr();
			const QList<StelObjectP>& sel = objMgr->getSelectedObject();
			if (sel.isEmpty()) {
				result["ok"] = false;
				result["error"] = "no object selected";
				return result;
			}
			StelCore* core = StelApp::getInstance().getCore();
			Vec3d obsPos = core->getCurrentObserver()->getCenterVsop87Pos();
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

				// ========== Phase 2s ==========
		// getScreenInfo — screen dimensions and DPI
		if (commandName == "getScreenInfo")
		{
			result["ok"] = true;
			result["width"] = QGuiApplication::primaryScreen()->size().width();
			result["height"] = QGuiApplication::primaryScreen()->size().height();
			result["dpi"] = QGuiApplication::primaryScreen()->logicalDotsPerInch();
			result["devicePixelRatio"] = QGuiApplication::primaryScreen()->devicePixelRatio();
			return result;
		}

		// getMemoryUsage — approximate memory usage
		if (commandName == "getMemoryUsage")
		{
			result["ok"] = true;
			#if QT_VERSION >= QT_VERSION_CHECK(5, 12, 0)
			result["mallocSize"] = 0;
			#endif
			result["note"] = "memory usage is approximate";
			return result;
		}

		// getObserverInfo — current observer details
		if (commandName == "getObserverInfo")
		{
			StelCore* core = StelApp::getInstance().getCore();
			const StelObserver* obs = core->getCurrentObserver();
			StelLocation loc = obs->getCurrentLocation();
			result["ok"] = true;
			result["name"] = loc.name;
			result["latitude"] = loc.getLatitude(false);
			result["longitude"] = loc.getLongitude(false);
			result["altitude"] = loc.altitude;
			result["planet"] = loc.planetName;
			result["country"] = QString();
			result["region"] = loc.region;
			result["state"] = loc.state;
			result["timeZone"] = loc.ianaTimeZone;
			return result;
		}

		// getDateTimeLocal — local date/time string
		if (commandName == "getDateTimeLocal")
		{
			StelCore* core = StelApp::getInstance().getCore();
			result["ok"] = true;
			result["iso"] = StelUtils::julianDayToISO8601String(core->getJD());
			result["jd"] = core->getJD();
			result["jde"] = core->getJDE();
			return result;
		}

				// ========== Phase 2t ==========
		// getStarFlags / setStarFlag — star display control
		if (commandName == "getStarFlags")
		{
			StarMgr* smgr = GETSTELMODULE(StarMgr);
			QJsonObject flags;
			flags["stars"] = smgr->getFlagStars();
			flags["labels"] = smgr->getFlagLabels();
			flags["labelsAmount"] = smgr->getLabelsAmount();
			result["ok"] = true;
			result["flags"] = flags;
			return result;
		}

		if (commandName == "setStarFlag")
		{
			QStringList parts = arg.split('|');
			if (parts.size() >= 2) {
				QString flagName = parts[0];
				bool state = parts[1] == "1" || parts[1] == "true";
				StarMgr* smgr = GETSTELMODULE(StarMgr);
				if (flagName == "stars") smgr->setFlagStars(state);
				else if (flagName == "labels") smgr->setFlagLabels(state);
				else {
					result["ok"] = false;
					result["error"] = "unknown star flag: " + flagName;
					return result;
				}
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "usage: flagName|state";
			}
			return result;
		}

		// setStarLabelsAmount — star label density (0-10)
		if (commandName == "setStarLabelsAmount")
		{
			bool ok;
			double amount = arg.toDouble(&ok);
			if (ok && amount >= 0.0 && amount <= 10.0) {
				GETSTELMODULE(StarMgr)->setLabelsAmount(amount);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "amount must be 0-10";
			}
			return result;
		}

		// getAppState — comprehensive application state summary
		if (commandName == "getAppState")
		{
			StelCore* core = StelApp::getInstance().getCore();
			StelMovementMgr* mvmgr = core->getMovementMgr();
			StelSkyDrawer* drawer = core->getSkyDrawer();
			result["ok"] = true;
			result["jd"] = core->getJD();
			result["timeRate"] = core->getTimeRate();
			result["fov"] = mvmgr->getCurrentFov();
			result["tracking"] = mvmgr->getFlagTracking();
			result["location"] = core->getCurrentLocation().name;
			result["lat"] = core->getCurrentLocation().getLatitude(false);
			result["lon"] = core->getCurrentLocation().getLongitude(false);
			result["limitMagnitude"] = drawer->getLimitMagnitude();
			result["starScale"] = drawer->getRelativeStarScale();
			result["projection"] = core->getCurrentProjectionTypeKey();
			result["fps"] = StelApp::getInstance().getFps();
			result["language"] = StelApp::getInstance().getLocaleMgr().getAppLanguage();
			return result;
		}

		// getDeepSkyImageStatus — distinguish copied files from textures that
		// the lazy deep-sky renderer has actually made ready for display.
		if (commandName == "getDeepSkyImageStatus")
		{
			const QString dataRoot = qEnvironmentVariable("STELLARIUM_DATA_ROOT");
			const QString imageRoot = dataRoot.isEmpty()
				? StelFileMgr::findFile("nebulae/default")
				: dataRoot + "/nebulae/default";
			const QString indexPath = imageRoot + "/textures.json";
			QJsonArray referencedImages;
			QFile indexFile(indexPath);
			if (indexFile.open(QFile::ReadOnly))
			{
				const QJsonDocument indexDocument = QJsonDocument::fromJson(indexFile.readAll());
				std::function<void(const QJsonValue&)> collectImageUrls = [&](const QJsonValue& value) {
					if (value.isObject())
					{
						const QJsonObject object = value.toObject();
						const QString imageUrl = object.value("imageUrl").toString();
						if (!imageUrl.isEmpty())
							referencedImages.append(imageUrl);
						for (const QString& key : object.keys())
							collectImageUrls(object.value(key));
					}
					else if (value.isArray())
					{
						for (const QJsonValue& child : value.toArray())
							collectImageUrls(child);
					}
				};
				if (indexDocument.isObject())
					collectImageUrls(indexDocument.object());
				else if (indexDocument.isArray())
					collectImageUrls(indexDocument.array());
			}

			QSet<QString> referencedNames;
			for (const QJsonValue& value : referencedImages)
				referencedNames.insert(QFileInfo(value.toString()).fileName());
			const QStringList diskNames = QDir(imageRoot).entryList(QStringList() << "*.png", QDir::Files, QDir::Name);
			QSet<QString> diskSet;
			for (const QString& name : diskNames)
				diskSet.insert(name);
			QJsonArray missingFiles;
			qint64 diskBytes = 0;
			for (const QString& name : diskNames)
				diskBytes += QFileInfo(imageRoot + "/" + name).size();
			for (const QString& name : std::as_const(referencedNames))
				if (!diskSet.contains(name))
					missingFiles.append(name);

			QStringList activeReady;
			QStringList activeLoading;
			QStringList activeNotStarted;
			QStringList activeErrors;
			bool layerVisible = false;
			int layerCount = 0;
			if (auto* skyLayerMgr = GETSTELMODULE(StelSkyLayerMgr))
			{
				const QMap<QString, StelSkyLayerP> layers = skyLayerMgr->getAllSkyLayers();
				for (auto iter = layers.cbegin(); iter != layers.cend(); ++iter)
				{
					const auto* tile = qobject_cast<const StelSkyImageTile*>(iter.value().data());
					if (!tile)
						continue;
					++layerCount;
					layerVisible = layerVisible || skyLayerMgr->getShowLayer(iter.key());
					tile->collectTextureStatus(activeReady, activeLoading, activeNotStarted, activeErrors);
				}
			}
			activeReady.removeDuplicates();
			activeLoading.removeDuplicates();
			activeNotStarted.removeDuplicates();
			activeErrors.removeDuplicates();

			QJsonArray targets;
			QStringList requested;
			const QStringList probeParts = arg.trimmed().split('|', Qt::KeepEmptyParts);
			const bool allRequested = probeParts.value(0).compare("all", Qt::CaseInsensitive) == 0;
			int targetOffset = 0;
			int targetLimit = allRequested ? 8 : 6;
			if (allRequested)
			{
				bool offsetOk = false;
				bool limitOk = false;
				targetOffset = probeParts.value(1).toInt(&offsetOk);
				const int requestedLimit = probeParts.value(2).toInt(&limitOk);
				if (!offsetOk || targetOffset < 0)
					targetOffset = 0;
				if (limitOk && requestedLimit > 0)
					targetLimit = qBound(1, requestedLimit, 64);
			}
			if (allRequested)
				requested = diskNames.mid(targetOffset, targetLimit);
			else
				requested = QStringList() << "m31.png" << "n2244.png" << "m42.png" << "m51-vasey.png" << "m13.png" << "pleiades.png";
			for (const QString& name : std::as_const(requested))
			{
				QJsonObject item;
				const QString normalized = QFileInfo(name).fileName();
				item["name"] = normalized;
				item["referenced"] = referencedNames.contains(normalized);
				const QFileInfo fileInfo(imageRoot + "/" + normalized);
				item["onDisk"] = fileInfo.exists() && fileInfo.size() > 0;
				item["bytes"] = fileInfo.exists() ? fileInfo.size() : 0;
				item["textureReady"] = activeReady.contains(normalized);
				item["textureLoading"] = activeLoading.contains(normalized);
				item["textureNotStarted"] = activeNotStarted.contains(normalized);
				item["textureError"] = activeErrors.contains(normalized);
				targets.append(item);
			}

			result["ok"] = true;
			result["imageRoot"] = imageRoot;
			result["indexPresent"] = QFileInfo::exists(indexPath);
			result["referencedCount"] = referencedNames.size();
			result["onDiskCount"] = diskNames.size();
			result["missingCount"] = missingFiles.size();
			result["missingFiles"] = missingFiles;
			result["diskBytes"] = diskBytes;
			result["layerCount"] = layerCount;
			result["layerVisible"] = layerVisible;
			result["activeTextureReadyCount"] = activeReady.size();
			result["activeTextureLoadingCount"] = activeLoading.size();
			result["activeTextureNotStartedCount"] = activeNotStarted.size();
			result["activeTexturePendingCount"] = activeLoading.size() + activeNotStarted.size();
			result["activeTextureErrorCount"] = activeErrors.size();
			result["targetOffset"] = allRequested ? targetOffset : 0;
			result["targetLimit"] = allRequested ? targetLimit : requested.size();
			result["targetTotal"] = diskNames.size();
			result["targetHasMore"] = allRequested && targetOffset + requested.size() < diskNames.size();
			result["targets"] = targets;
			qInfo() << "[dso-probe] deep-sky status: referenced=" << referencedNames.size()
					<< "onDisk=" << diskNames.size() << "missing=" << missingFiles.size()
					<< "activeReady=" << activeReady.size() << "activeLoading=" << activeLoading.size()
					<< "activeNotStarted=" << activeNotStarted.size()
					<< "activeErrors=" << activeErrors.size();
			return result;
		}

				// ========== Phase 2u ==========
		// getAtmosphereFlags / setAtmosphereFlag
		if (commandName == "getAtmosphereFlags")
		{
			LandscapeMgr* lmgr = GETSTELMODULE(LandscapeMgr);
			QJsonObject flags;
			flags["atmosphere"] = lmgr->getFlagAtmosphere();
			flags["fog"] = lmgr->getFlagFog();
			flags["landscape"] = lmgr->getFlagLandscape();
			flags["cardinals"] = lmgr->getFlagCardinalPoints();
			result["ok"] = true;
			result["flags"] = flags;
			return result;
		}

		if (commandName == "setAtmosphereFlag")
		{
			QStringList parts = arg.split('|');
			if (parts.size() >= 2) {
				QString flagName = parts[0];
				bool state = parts[1] == "1" || parts[1] == "true";
				LandscapeMgr* lmgr = GETSTELMODULE(LandscapeMgr);
				if (flagName == "atmosphere") lmgr->setFlagAtmosphere(state);
				else if (flagName == "fog") lmgr->setFlagFog(state);
				else if (flagName == "landscape") lmgr->setFlagLandscape(state);
				else if (flagName == "cardinals") lmgr->setFlagCardinalPoints(state);
				else {
					result["ok"] = false;
					result["error"] = "unknown atmosphere flag: " + flagName;
					return result;
				}
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "usage: flagName|state";
			}
			return result;
		}

		// getLandscapeOpacity / setLandscapeOpacity
		if (commandName == "getLandscapeOpacity")
		{
			result["ok"] = true;
			result["opacity"] = GETSTELMODULE(LandscapeMgr)->getLandscapeTransparency();
			return result;
		}

		if (commandName == "setLandscapeOpacity")
		{
			bool ok;
			double opacity = arg.toDouble(&ok);
			if (ok && opacity >= 0.0 && opacity <= 1.0) {
				GETSTELMODULE(LandscapeMgr)->setLandscapeTransparency(opacity);
				result["ok"] = true;
			} else {
				result["ok"] = false;
				result["error"] = "opacity must be 0-1";
			}
			return result;
		}

		// getAtmosphereBrightness — atmospheric brightness factor
		if (commandName == "getAtmosphereBrightness")
		{
			result["ok"] = true;
			result["brightness"] = GETSTELMODULE(LandscapeMgr)->getAtmosphereFadeDuration();
			return result;
		}

				// ========== Phase 2v ==========
		// getProjectionInfo — current projection details
		if (commandName == "getProjectionInfo")
		{
			StelCore* core = StelApp::getInstance().getCore();
			result["ok"] = true;
			result["currentKey"] = core->getCurrentProjectionTypeKey();
			result["allKeys"] = QJsonArray::fromStringList(core->getAllProjectionTypeKeys());
			result["viewportWidth"] = core->getProjection(StelCore::FrameJ2000)->getViewportWidth();
			result["viewportHeight"] = core->getProjection(StelCore::FrameJ2000)->getViewportHeight();
			return result;
		}

		// getViewportSize — screen viewport dimensions
		if (commandName == "getViewportSize")
		{
			StelCore* core = StelApp::getInstance().getCore();
			result["ok"] = true;
			result["width"] = core->getProjection(StelCore::FrameJ2000)->getViewportWidth();
			result["height"] = core->getProjection(StelCore::FrameJ2000)->getViewportHeight();
			return result;
		}

		// getTimeInfo — detailed time information
		if (commandName == "getTimeInfo")
		{
			StelCore* core = StelApp::getInstance().getCore();
			StelLocaleMgr& locale = StelApp::getInstance().getLocaleMgr();
			result["ok"] = true;
			result["jd"] = core->getJD();
			result["jde"] = core->getJDE();
			result["timeRate"] = core->getTimeRate();
			result["isTimeNow"] = core->getIsTimeNow();
			result["iso"] = StelUtils::julianDayToISO8601String(core->getJD());
			result["utcOffset"] = core->getCurrentLocation().getLongitude();
			return result;
		}

		// getLocationList — search locations by case-insensitive substring.
		// The ArkUI picker also merges its offline Chinese-name index.
		if (commandName == "getLocationList")
		{
			const QString query = arg.trimmed();
			const QString needle = query.toLower();
			const StelLocationMgr& locMgr = StelApp::getInstance().getLocationMgr();
			QJsonArray list;
			int count = 0;
			if (needle.isEmpty()) {
				result["ok"] = true;
				result["locations"] = list;
				result["count"] = 0;
				return result;
			}
			for (const auto& loc : locMgr.getAll()) {
				if (loc.name.toLower().contains(needle) || loc.state.toLower().contains(needle) ||
					loc.region.toLower().contains(needle)) {
					QJsonObject item;
					item["name"] = loc.name;
					item["englishName"] = loc.name;
					item["lat"] = loc.getLatitude(false);
					item["lon"] = loc.getLongitude(false);
					item["alt"] = loc.altitude;
					item["country"] = QString();
					item["planet"] = loc.planetName;
					list.append(item);
					if (++count >= 20) break;
				}
			}
			result["ok"] = true;
			result["locations"] = list;
			result["count"] = count;
			return result;
		}

				// ========== Phase 2w ==========
		// setDate — set date by ISO string
		if (commandName == "setDate")
		{
			bool jdOk = false; double jd = StelUtils::getJulianDayFromISO8601String(arg, &jdOk);
			if (jdOk && jd > 0) {
				StelApp::getInstance().getCore()->setJD(jd);
				result["ok"] = true;
				result["jd"] = jd;
			} else {
				result["ok"] = false;
				result["error"] = "invalid ISO date";
			}
			return result;
		}

		// addDay — add/subtract days from current time
		if (commandName == "addDay")
		{
			bool ok;
			double days = arg.toDouble(&ok);
			if (ok) {
				StelCore* core = StelApp::getInstance().getCore();
				core->setJD(core->getJD() + days);
				result["ok"] = true;
				result["jd"] = core->getJD();
			} else {
				result["ok"] = false;
				result["error"] = "invalid days";
			}
			return result;
		}

		// addHour — add/subtract hours from current time
		if (commandName == "addHour")
		{
			bool ok;
			double hours = arg.toDouble(&ok);
			if (ok) {
				StelCore* core = StelApp::getInstance().getCore();
				core->setJD(core->getJD() + hours / 24.0);
				result["ok"] = true;
				result["jd"] = core->getJD();
			} else {
				result["ok"] = false;
				result["error"] = "invalid hours";
			}
			return result;
		}

		// addMinute — add/subtract minutes from current time
		if (commandName == "addMinute")
		{
			bool ok;
			double minutes = arg.toDouble(&ok);
			if (ok) {
				StelCore* core = StelApp::getInstance().getCore();
				core->setJD(core->getJD() + minutes / 1440.0);
				result["ok"] = true;
				result["jd"] = core->getJD();
			} else {
				result["ok"] = false;
				result["error"] = "invalid minutes";
			}
			return result;
		}

		// addYear — add/subtract years from current time
		if (commandName == "addYear")
		{
			bool ok;
			double years = arg.toDouble(&ok);
			if (ok) {
				StelCore* core = StelApp::getInstance().getCore();
				core->setJD(core->getJD() + years * 365.25);
				result["ok"] = true;
				result["jd"] = core->getJD();
			} else {
				result["ok"] = false;
				result["error"] = "invalid years";
			}
			return result;
		}

		// addMonth — add/subtract months from current time
		if (commandName == "addMonth")
		{
			bool ok;
			double months = arg.toDouble(&ok);
			if (ok) {
				StelCore* core = StelApp::getInstance().getCore();
				core->setJD(core->getJD() + months * 30.4375);
				result["ok"] = true;
				result["jd"] = core->getJD();
			} else {
				result["ok"] = false;
				result["error"] = "invalid months";
			}
			return result;
		}

		// ========== End Phase 2w ==========

		// ========== End Phase 2v ==========

		// ========== End Phase 2u ==========

		// ========== End Phase 2t ==========

		// ========== End Phase 2s ==========

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

		// ---- Bookmarks (OHOS bridge) ----
		if (commandName == "addBookmark")
		{
			if (!g_bookmarksLoaded) bookmarksLoad();
			BookmarkItem it;
			it.id = QString("bm_%1").arg(QDateTime::currentMSecsSinceEpoch());
			it.name = arg.isEmpty() ? QString("书签") : arg;
			if (movementMgr)
			{
				const Vec3d d = movementMgr->getViewDirectionJ2000();
				it.vx = d[0]; it.vy = d[1]; it.vz = d[2];
				it.fov = movementMgr->getCurrentFov();
			}
			if (objectMgr && !objectMgr->getSelectedObject().isEmpty())
			{
				StelObjectP obj = objectMgr->getSelectedObject().first();
				it.object = obj->getEnglishName();
			}
			g_bookmarks.append(it);
			bookmarksSave();
			result["ok"] = true;
			result["id"] = it.id;
			result["name"] = it.name;
			return result;
		}

		if (commandName == "getBookmarks")
		{
			if (!g_bookmarksLoaded) bookmarksLoad();
			QJsonArray items;
			for (const BookmarkItem& it : g_bookmarks)
			{
				QJsonObject o;
				o["id"] = it.id;
				o["name"] = it.name;
				o["fov"] = it.fov;
				o["object"] = it.object;
				o["vx"] = it.vx; o["vy"] = it.vy; o["vz"] = it.vz;
				items.append(o);
			}
			result["ok"] = true;
			result["items"] = items;
			result["count"] = g_bookmarks.size();
			return result;
		}

		if (commandName == "deleteBookmark")
		{
			if (!g_bookmarksLoaded) bookmarksLoad();
			const int removed = g_bookmarks.removeIf([&](const BookmarkItem& it) { return it.id == arg; });
			bookmarksSave();
			result["ok"] = true;
			result["removed"] = removed;
			return result;
		}

		if (commandName == "gotoBookmark")
		{
			if (!g_bookmarksLoaded) bookmarksLoad();
			bool found = false;
			for (const BookmarkItem& it : g_bookmarks)
			{
				if (it.id == arg)
				{
					if (movementMgr)
					{
						movementMgr->setViewDirectionJ2000(Vec3d(it.vx, it.vy, it.vz));
						movementMgr->setFov(it.fov);
					}
					found = true;
					break;
				}
			}
		if (found) { result["ok"] = true; }
		else { result["ok"] = false; result["error"] = "bookmark not found: " + arg; }
		return result;
	}

		// ========== Session continuation (无缝流转 / 跨设备接续) ==========
		// getSessionState — export the full current session so it can be handed off
		// to another device (seamless continuation). Returns ok:true plus the view
		// J2000 vector, FOV (deg), JD, observer location, selected object and key flags.
		if (commandName == "getSessionState")
		{
			if (!core || !movementMgr) { result["error"] = "core/movement not ready"; return result; }
			const Vec3d d = movementMgr->getViewDirectionJ2000();
			result["ok"] = true;
			QJsonArray v;
			v.append(d[0]); v.append(d[1]); v.append(d[2]);
			result["viewJ2000"] = v;
			// getCurrentFov() 已是「度」，字段名 fovDeg 直接取用即可
			result["fovDeg"] = movementMgr->getCurrentFov();
			result["jd"] = core->getJD();
			const StelLocation& loc = core->getCurrentLocation();
			QJsonObject lo;
			lo["name"] = loc.name;
			lo["planetName"] = loc.planetName;
			lo["latitude"] = loc.getLatitude();
			lo["longitude"] = loc.getLongitude();
			lo["altitude"] = loc.altitude;
			lo["ianaTimeZone"] = loc.ianaTimeZone;
			result["location"] = lo;
			QString selName;
			if (objectMgr && !objectMgr->getSelectedObject().isEmpty())
				selName = objectMgr->getSelectedObject().first()->getEnglishName();
			result["selected"] = selName;
			QJsonObject fl;
			LandscapeMgr* lm = GETSTELMODULE(LandscapeMgr);
			if (lm) { fl["atmosphere"] = lm->getFlagAtmosphere(); fl["fog"] = lm->getFlagFog(); fl["landscape"] = lm->getFlagLandscape(); fl["cardinals"] = lm->getFlagCardinalPoints(); }
			ConstellationMgr* cm = GETSTELMODULE(ConstellationMgr);
			if (cm) { fl["constLines"] = cm->getFlagLines(); fl["constLabels"] = cm->getFlagLabels(); }
			fl["tracking"] = movementMgr->getFlagTracking();
			fl["flipHorz"] = core->getFlipHorz();
			fl["flipVert"] = core->getFlipVert();
			if (SporadicMeteorMgr* mm = GETSTELMODULE(SporadicMeteorMgr)) fl["meteors"] = mm->getFlagShow();
			result["flags"] = fl;
			return result;
		}

		// applySessionState — import a session produced by getSessionState on another
		// device and restore view / FOV / time / location / selection. This is the
		// target end of 无缝流转: a source device exports, transfers the JSON over the
		// (future) distributed soft-bus, and the target device applies it to continue.
		if (commandName == "applySessionState")
		{
			if (!core || !movementMgr) { result["ok"] = false; result["error"] = "core/movement not ready"; return result; }
			const QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			if (doc.isNull() || !doc.isObject()) { result["ok"] = false; result["error"] = "applySessionState expects JSON"; return result; }
			const QJsonObject s = doc.object();
			if (s.contains("jd") && s["jd"].isDouble()) core->setJD(s["jd"].toDouble());
			if (s.contains("location") && s["location"].isObject())
			{
				const QJsonObject lo = s["location"].toObject();
				const QString planet = lo["planetName"].toString();
				if (!planet.isEmpty())
				{
					StelLocation loc;
					loc.name = lo["name"].toString(planet + " surface");
					loc.planetName = planet;
					loc.setLatitude(static_cast<float>(lo["latitude"].toDouble()));
					loc.setLongitude(static_cast<float>(lo["longitude"].toDouble()));
					loc.altitude = lo["altitude"].toInt();
					loc.role = QChar('X');
					loc.ianaTimeZone = lo["ianaTimeZone"].toString(QStringLiteral("system_default"));
					QString landscapeID;
					if (planet == "Moon") landscapeID = "moon";
					else if (planet == "Mars") landscapeID = "mars";
					else if (planet == "Jupiter") landscapeID = "jupiter";
					else if (planet == "Saturn") landscapeID = "saturn";
					else if (planet == "Uranus") landscapeID = "uranus";
					else if (planet == "Neptune") landscapeID = "neptune";
					else if (planet == "Sun") landscapeID = "sun";
					else if (planet == "Earth") landscapeID = "garching";
					core->moveObserverTo(loc, 0.0, 0.0, landscapeID);
				}
			}
			// view vector must be restored AFTER moveObserverTo (which can re-aim)
			if (s.contains("viewJ2000") && s["viewJ2000"].isArray())
			{
				const QJsonArray v = s["viewJ2000"].toArray();
				if (v.size() == 3)
					movementMgr->setViewDirectionJ2000(Vec3d(v[0].toDouble(), v[1].toDouble(), v[2].toDouble()));
			}
			if (s.contains("fovDeg") && s["fovDeg"].isDouble())
				movementMgr->setFov(s["fovDeg"].toDouble() * M_PI / 180.0);
			if (s.contains("flags") && s["flags"].isObject())
			{
				const QJsonObject flags = s["flags"].toObject();
				if (flags.contains("flipHorz")) core->setFlipHorz(flags["flipHorz"].toBool());
				if (flags.contains("flipVert")) core->setFlipVert(flags["flipVert"].toBool());
			}
			if (s.contains("selected") && objectMgr)
			{
				const QString sel = s["selected"].toString();
				if (!sel.isEmpty())
					objectMgr->findAndSelect(sel);
				else
					objectMgr->unSelect();
			}
			markOhosInteraction();
			result["ok"] = true;
			return result;
		}

	// ========== Oculars plugin (望远镜/目镜配置) ==========
		if (commandName == "getOculars")
		{
			Oculars* oculars = GETSTELMODULE(Oculars);
			if (!oculars) { result["ok"] = false; result["error"] = "Oculars plugin not loaded"; return result; }
			QJsonObject o;
			o["ocularMode"] = oculars->getEnableOcular();
			o["telrad"] = oculars->getEnableTelrad();
			o["crosshairs"] = oculars->getEnableCrosshairs();
			o["ccd"] = oculars->getEnableCCD();
			o["ocularIndex"] = oculars->getSelectedOcularIndex();
			o["telescopeIndex"] = oculars->getSelectedTelescopeIndex();
			o["lensIndex"] = oculars->getSelectedLensIndex();
			o["ccdIndex"] = oculars->getSelectedCCDIndex();
			o["ocularCount"] = oculars->getOcularCount();
			o["telescopeCount"] = oculars->getTelescopeCount();
			o["lensCount"] = oculars->getLensCount();
			o["ccdCount"] = oculars->getCCDCount();
			QJsonArray on, tn, ln, cn;
			for (const QString& s : oculars->getOcularNames()) on.append(s);
			for (const QString& s : oculars->getTelescopeNames()) tn.append(s);
			for (const QString& s : oculars->getLensNames()) ln.append(s);
			for (const QString& s : oculars->getCCDNames()) cn.append(s);
			o["ocularNames"] = on;
			o["telescopeNames"] = tn;
			o["lensNames"] = ln;
			o["ccdNames"] = cn;
			result["ok"] = true;
			result["oculars"] = o;
			return result;
		}
		if (commandName == "setOcularMode")
		{
			Oculars* oculars = GETSTELMODULE(Oculars);
			if (!oculars) { result["ok"] = false; result["error"] = "Oculars plugin not loaded"; return result; }
			oculars->enableOcular(arg.trimmed() == "1" || arg.trimmed() == "true");
			result["ok"] = true;
			return result;
		}
		if (commandName == "setTelrad")
		{
			Oculars* oculars = GETSTELMODULE(Oculars);
			if (!oculars) { result["ok"] = false; result["error"] = "Oculars plugin not loaded"; return result; }
			oculars->toggleTelrad(arg.trimmed() == "1" || arg.trimmed() == "true");
			result["ok"] = true;
			return result;
		}
		if (commandName == "setCrosshairs")
		{
			Oculars* oculars = GETSTELMODULE(Oculars);
			if (!oculars) { result["ok"] = false; result["error"] = "Oculars plugin not loaded"; return result; }
			oculars->toggleCrosshairs(arg.trimmed() == "1" || arg.trimmed() == "true");
			result["ok"] = true;
			return result;
		}
		if (commandName == "setCCD")
		{
			Oculars* oculars = GETSTELMODULE(Oculars);
			if (!oculars) { result["ok"] = false; result["error"] = "Oculars plugin not loaded"; return result; }
			oculars->toggleCCD(arg.trimmed() == "1" || arg.trimmed() == "true");
			result["ok"] = true;
			return result;
		}
		if (commandName == "cycleOcular" || commandName == "cycleTelescope" || commandName == "cycleLens" || commandName == "cycleCCD")
		{
			Oculars* oculars = GETSTELMODULE(Oculars);
			if (!oculars) { result["ok"] = false; result["error"] = "Oculars plugin not loaded"; return result; }
			bool forward = (arg.trimmed() != "prev");
			if (commandName == "cycleOcular") { if (forward) oculars->incrementOcularIndex(); else oculars->decrementOcularIndex(); }
			else if (commandName == "cycleTelescope") { if (forward) oculars->incrementTelescopeIndex(); else oculars->decrementTelescopeIndex(); }
			else if (commandName == "cycleLens") { if (forward) oculars->incrementLensIndex(); else oculars->decrementLensIndex(); }
			else { if (forward) oculars->incrementCCDIndex(); else oculars->decrementCCDIndex(); }
			int idx = -1;
			if (commandName == "cycleOcular") idx = oculars->getSelectedOcularIndex();
			else if (commandName == "cycleTelescope") idx = oculars->getSelectedTelescopeIndex();
			else if (commandName == "cycleLens") idx = oculars->getSelectedLensIndex();
			else idx = oculars->getSelectedCCDIndex();
			result["ok"] = true;
			result["index"] = idx;
			return result;
		}

		// ========== Satellites plugin (卫星) ==========
		if (commandName == "getSatellites")
		{
			Satellites* sats = static_cast<Satellites*>(StelApp::getInstance().getModuleMgr().getModule(QStringLiteral("Satellites"), true));
			if (!sats) { result["ok"] = false; result["error"] = "Satellites plugin not loaded"; return result; }
			const QStringList options = arg.split('|');
			const QString group = options.value(0).trimmed();
			const QString query = options.value(1).trimmed();
			bool limitOk = false;
			int limit = options.value(2).toInt(&limitOk);
			if (!limitOk || limit <= 0) limit = 40;
			limit = qBound(1, limit, 100);
			StelCore* core = StelApp::getInstance().getCore();
			QJsonObject s;
			QJsonArray groups;
			for (const QString& g : sats->getGroupIdList()) groups.append(g);
			s["groups"] = groups;
			s["labels"] = sats->getFlagLabelsVisible();
			s["orbitLines"] = sats->getFlagOrbitLines();
			s["hints"] = sats->getFlagHintsVisible();
			s["iconicMode"] = sats->getFlagIconicMode();
			s["hideInvisible"] = sats->getFlagHideInvisible();
			const QVariantMap catalog = sats->getCatalogSummary(group, query, limit);
			s["count"] = catalog.value("count").toInt();
			s["offline"] =
#ifdef STELLARIUM_OHOS_OFFLINE
				true;
#else
				false;
#endif
			s["observerIsEarth"] = core->getCurrentPlanet()->getEnglishName() == QStringLiteral("Earth");
			s["dateInRange"] = sats->isDateInValidRange(core);
			s["newestUpdate"] = catalog.value("newestUpdate").toString();
			s["outdatedCount"] = catalog.value("outdatedCount").toInt();
			s["matchedCount"] = catalog.value("matchedCount").toInt();
			s["items"] = QJsonArray::fromVariantList(catalog.value("items").toList());
			result["ok"] = true;
			result["satellites"] = s;
			return result;
		}
		if (commandName == "setSatellitesFlag")
		{
			Satellites* sats = static_cast<Satellites*>(StelApp::getInstance().getModuleMgr().getModule(QStringLiteral("Satellites"), true));
			if (!sats) { result["ok"] = false; result["error"] = "Satellites plugin not loaded"; return result; }
			QStringList parts = arg.split(":", Qt::SkipEmptyParts);
			QString name = parts.size() > 0 ? parts[0].trimmed() : "";
			bool val = (parts.size() > 1 && (parts[1].trimmed() == "1" || parts[1].trimmed() == "true"));
			bool ok = true;
			if (name == "labels") sats->setFlagLabelsVisible(val);
			else if (name == "orbitLines") sats->setFlagOrbitLines(val);
			else if (name == "hints") sats->setFlagHintsVisible(val);
			else if (name == "iconicMode") sats->setFlagIconicMode(val);
			else if (name == "hideInvisible") sats->setFlagHideInvisible(val);
			else ok = false;
			result["ok"] = ok;
			if (!ok) result["error"] = "unknown satellite flag: " + name;
			return result;
		}
		if (commandName == "getMeteorShowers")
		{
			MeteorShowersMgr* ms = GETSTELMODULE(MeteorShowersMgr);
			if (!ms) { result["ok"] = false; result["error"] = "MeteorShowers plugin not loaded"; return result; }
			QJsonObject m;
			m["enabled"] = ms->getEnablePlugin();
			m["labels"] = ms->getEnableLabels();
			m["activeOnly"] = ms->getActiveRadiantOnly();
			m["marker"] = ms->getEnableMarker();
			result["ok"] = true;
			result["meteorShowers"] = m;
			// Active shower list with details
			QJsonArray showerList;
			MeteorShowers* msColl = ms->getMeteorShowers();
			if (msColl)
			{
				QVector<QPair<QString, StelObjectP>> all = msColl->listAllObjects(false);
				for (const auto& pr : all)
				{
					MeteorShowerP sh = qSharedPointerCast<MeteorShower>(pr.second);
					if (!sh) continue;
					MeteorShower::Status st = sh->getStatus();
					if (st == MeteorShower::ACTIVE_CONFIRMED || st == MeteorShower::ACTIVE_GENERIC)
					{
						QVariantMap infoMap = sh->getInfoMap(core);
						QJsonObject so;
						so["name"] = sh->getNameI18n();
						so["englishName"] = sh->getEnglishName();
						so["zhr"] = sh->getZHR();
						so["status"] = (st == MeteorShower::ACTIVE_CONFIRMED) ? "confirmed" : "generic";
						so["speed"] = infoMap.value("velocity", 0).toInt();
						so["popIdx"] = infoMap.value("population-index", 0).toFloat();
						so["parent"] = infoMap.value("parent", "").toString();
						so["zhrMax"] = infoMap.value("zhr-max", 0).toInt();
						showerList.append(so);
					}
				}
			}
			result["showerList"] = showerList;
			return result;
		}
		if (commandName == "setMeteorShowersFlag")
		{
			MeteorShowersMgr* ms = GETSTELMODULE(MeteorShowersMgr);
			if (!ms) { result["ok"] = false; result["error"] = "MeteorShowers plugin not loaded"; return result; }
			QStringList parts = arg.split(":", Qt::SkipEmptyParts);
			QString name = parts.size() > 0 ? parts[0].trimmed() : "";
			bool val = (parts.size() > 1 && (parts[1].trimmed() == "1" || parts[1].trimmed() == "true"));
			bool ok = true;
			if (name == "enabled") ms->setEnablePlugin(val);
			else if (name == "labels") ms->setEnableLabels(val);
			else if (name == "activeOnly") ms->setActiveRadiantOnly(val);
			else if (name == "marker") ms->setEnableMarker(val);
			else ok = false;
			result["ok"] = ok;
			if (!ok) result["error"] = "unknown meteor showers flag: " + name;
			return result;
		}

		// getTonightEvents — 聚合"今晚看什么"：月相、日月升落与天文暮光、
		// 主要行星升落/星等/可见性、活跃流星雨、卫星概况。供 ArkTS 今夜天文事件面板。
		if (commandName == "getTonightEvents")
		{
			StelCore* core = StelApp::getInstance().getCore();
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			// 暗夜开始时刻（天文暮光结束），供流星雨等事件的跳转时间基准
			double darkStartJd = 0;

			auto fmtLocal = [&](double jd) -> QString {
				if (jd <= 0) return QString();
				return StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
			};
			auto moonPhaseNameZh = [](double age) -> QString {
				if (age < 1.0 || age > 28.5) return QStringLiteral("新月");
				if (age < 6.4) return QStringLiteral("蛾眉月");
				if (age < 8.4) return QStringLiteral("上弦月");
				if (age < 13.9) return QStringLiteral("盈凸月");
				if (age < 15.9) return QStringLiteral("满月");
				if (age < 21.4) return QStringLiteral("亏凸月");
				if (age < 23.4) return QStringLiteral("下弦月");
				return QStringLiteral("残月");
			};

			QJsonObject out;

			// 月相
			QJsonObject moonObj;
			PlanetP moon = ssys->getMoon();
			if (moon)
			{
				QVariantMap mim = moon->getInfoMap(core);
				double age = mim.value("age", 0).toDouble();
				double illum = mim.value("illumination", 0).toDouble();
				moonObj["phaseName"] = moonPhaseNameZh(age);
				moonObj["illumination"] = illum;
				moonObj["age"] = age;
				Vec4d mrts = moon->getRTSTime(core);
				moonObj["rise"] = fmtLocal(mrts[0]);
				moonObj["transit"] = fmtLocal(mrts[1]);
				moonObj["set"] = fmtLocal(mrts[2]);
				moonObj["transitJd"] = mrts[1];
			}
			out["moon"] = moonObj;

			// 太阳与天文暮光
			QJsonObject sunObj;
			PlanetP sun = ssys->getSun();
			if (sun)
			{
				Vec4d srts = sun->getRTSTime(core);
				sunObj["rise"] = fmtLocal(srts[0]);
				sunObj["transit"] = fmtLocal(srts[1]);
				sunObj["set"] = fmtLocal(srts[2]);
				Vec4d astro = sun->getRTSTime(core, -18.0);
				const double astroEnd = astro[2];
				double astroStart = astro[0];
				// getRTSTime() returns the morning and evening events in the same
				// civil date. For tonight, the following morning belongs to tomorrow.
				if (astroStart > 0.0 && astroEnd > 0.0 && astroStart <= astroEnd)
					astroStart += 1.0;
				sunObj["astroTwilightEnd"] = fmtLocal(astroEnd);
				sunObj["astroTwilightStart"] = fmtLocal(astroStart);
				sunObj["astroTwilightEndJd"] = astroEnd;
				if (astroEnd > 0.0 && astroStart > astroEnd)
					sunObj["darkWindowHours"] = (astroStart - astroEnd) * 24.0;
				darkStartJd = astroEnd;
			}
			out["sun"] = sunObj;

			// 主要行星升落 + 星等 + 当前可见性
			QJsonArray planets;
			QStringList planetNames = QStringList() << "Mercury" << "Venus" << "Mars"
												   << "Jupiter" << "Saturn" << "Uranus" << "Neptune";
			for (const QString& pn : planetNames)
			{
				PlanetP p = qSharedPointerCast<Planet>(ssys->searchByName(pn));
				if (!p) continue;
				QJsonObject po;
				po["name"] = p->getNameI18n();
				po["englishName"] = pn;
				Vec4d rts = p->getRTSTime(core);
				po["rise"] = fmtLocal(rts[0]);
				po["transit"] = fmtLocal(rts[1]);
				po["set"] = fmtLocal(rts[2]);
				po["magnitude"] = p->getVMagnitude(core);
				po["transitJd"] = rts[1];
				Vec3d altaz = p->getAltAzPosApparent(core);
				double alt = std::asin(altaz[2] / altaz.norm()) * 180.0 / M_PI;
				po["altitude"] = alt;
				po["visible"] = alt > 0;
				planets.append(po);
			}
			out["planets"] = planets;

			// 活跃流星雨
			QJsonArray showers;
			MeteorShowersMgr* msMgr = GETSTELMODULE(MeteorShowersMgr);
			if (msMgr && msMgr->getEnablePlugin())
			{
				MeteorShowers* msColl = msMgr->getMeteorShowers();
				if (msColl)
				{
					QVector<QPair<QString, StelObjectP>> all = msColl->listAllObjects(false);
					for (const auto& pr : all)
					{
						MeteorShowerP sh = qSharedPointerCast<MeteorShower>(pr.second);
						if (!sh) continue;
						MeteorShower::Status st = sh->getStatus();
						if (st == MeteorShower::ACTIVE_CONFIRMED || st == MeteorShower::ACTIVE_GENERIC)
						{
							QJsonObject so;
							so["name"] = sh->getNameI18n();
							so["zhr"] = sh->getZHR();
							so["status"] = (st == MeteorShower::ACTIVE_CONFIRMED) ? "confirmed" : "generic";
							// 跳转基准：暗夜开始后约 6 小时（辐射点升高的观测窗口）
							so["primeJd"] = darkStartJd > 0 ? darkStartJd + 0.25 : core->getJD();
							showers.append(so);
						}
					}
				}
			}
			out["meteorShowers"] = showers;

			// 卫星概况
			QJsonObject satObj;
			Satellites* sats = static_cast<Satellites*>(StelApp::getInstance().getModuleMgr().getModule(QStringLiteral("Satellites"), true));
			if (sats)
			{
				satObj["count"] = sats->listAllIds().size();
				satObj["enabled"] = true;
			}
			else
			{
				satObj["enabled"] = false;
				satObj["count"] = 0;
			}
			out["satellites"] = satObj;

			out["date"] = fmtLocal(core->getJD());

			result["ok"] = true;
			result["tonight"] = out;
			return result;
		}

		// getWutTargets — AstroCalc「今天天象」：使用与桌面版相同的目录来源，
		// 按观测时段、高度、星等、角大小及方位筛选，避免 ArkUI 侧拼接假数据。
		if (commandName == "getWutTargets")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const QString period = options.value("period").toString(QStringLiteral("midnight"));
			const QString category = options.value("category").toString(QStringLiteral("planets"));
			const double minimumAltitude = qBound(0.0, options.value("minAltitude").toDouble(20.0), 80.0);
			const double maximumMagnitude = qBound(-5.0, options.value("maxMagnitude").toDouble(6.0), 15.0);
			const bool limitAngularSize = options.value("limitAngularSize").toBool(false);
			const double minimumAngularSizeArcmin = qBound(0.0, options.value("minAngularSizeArcmin").toDouble(10.0), 21600.0);
			const double maximumAngularSizeArcmin = qBound(minimumAngularSizeArcmin, options.value("maxAngularSizeArcmin").toDouble(600.0), 21600.0);
			const QString direction = options.value("direction").toString(QStringLiteral("all"));
			const bool angularSizeAvailable = !QStringList({QStringLiteral("stars"), QStringLiteral("variableStars"), QStringLiteral("highProperMotion"), QStringLiteral("carbonStars"), QStringLiteral("bariumStars")}).contains(category);
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			NebulaMgr* nebulaMgr = GETSTELMODULE(NebulaMgr);
			StarMgr* starMgr = GETSTELMODULE(StarMgr);
			PlanetP sun = ssys->getSun();
			if (!sun)
			{
				result["ok"] = false;
				result["error"] = "Sun unavailable";
				return result;
			}

			const double originalJD = core->getJD();
			Vec4d civilTwilight = sun->getRTSTime(core, -6.0);
			double evening = civilTwilight[2];
			double morning = civilTwilight[0];
			if (evening <= 0.0 || morning <= 0.0)
			{
				result["ok"] = false;
				result["error"] = "no civil twilight at this location";
				return result;
			}
			if (morning <= evening)
				morning += 1.0;
			const double midnight = (evening + morning) / 2.0;
			QList<double> sampleJDs;
			if (period == QStringLiteral("evening"))
				sampleJDs.append(evening);
			else if (period == QStringLiteral("morning"))
				sampleJDs.append(morning);
			else if (period == QStringLiteral("night"))
			{
				sampleJDs.append(evening);
				sampleJDs.append(midnight);
				sampleJDs.append(morning);
			}
			else
				sampleJDs.append(midnight);

			auto fmtLocal = [&](double jd) -> QString {
				return jd > 0.0 ? StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0) : QString();
			};
			QList<QJsonObject> targets;
			const QMap<QString, double> directionAzimuth = {
				{QStringLiteral("north"), 0.0}, {QStringLiteral("northeast"), 45.0},
				{QStringLiteral("east"), 90.0}, {QStringLiteral("southeast"), 135.0},
				{QStringLiteral("south"), 180.0}, {QStringLiteral("southwest"), 225.0},
				{QStringLiteral("west"), 270.0}, {QStringLiteral("northwest"), 315.0}};
			auto directionMatches = [&](double azimuth) {
				if (direction == QStringLiteral("all") || !directionAzimuth.contains(direction)) return true;
				const double delta = std::abs(StelUtils::fmodpos(azimuth - directionAzimuth.value(direction) + 180.0, 360.0) - 180.0);
				return delta <= 22.5;
			};
			auto maxAltitude = [&](const StelObjectP& object) {
				double ra = 0.0;
				double declination = 0.0;
				StelUtils::rectToSphe(&ra, &declination, object->getEquinoxEquatorialPos(core));
				return 90.0 - std::abs(static_cast<double>(core->getCurrentLocation().getLatitude()) - declination * M_180_PI);
			};
			auto appendTarget = [&](const StelObjectP& object, const QString& fallbackName, bool ignoreMagnitude = false, bool sizeIsApplicable = true) {
				if (!object) return;
				double bestJD = 0.0;
				double bestAltitude = -91.0;
				double bestAzimuth = 0.0;
				double bestMagnitude = 99.0;
				double bestAngularSize = 0.0;
				for (const double jd : sampleJDs)
				{
					core->setJD(jd);
					core->update(0);
					const double magnitude = object->getVMagnitude(core);
					if (!ignoreMagnitude && magnitude > maximumMagnitude) continue;
					const double angularSize = object->getAngularRadius(core) * 120.0;
					if (limitAngularSize && sizeIsApplicable && angularSize > 0.0
						&& (angularSize < minimumAngularSizeArcmin || angularSize > maximumAngularSizeArcmin)) continue;
					const Vec3d altAz = object->getAltAzPosAuto(core);
					if (altAz.normSquared() <= 0.0) continue;
					const double altitude = std::asin(altAz[2] / altAz.norm()) * M_180_PI;
					const double azimuth = StelUtils::fmodpos(std::atan2(altAz[1], -altAz[0]) * M_180_PI, 360.0);
					if (altitude < minimumAltitude || !directionMatches(azimuth)) continue;
					if (altitude > bestAltitude)
					{
						bestJD = jd;
						bestAltitude = altitude;
						bestAzimuth = azimuth;
						bestMagnitude = magnitude;
						bestAngularSize = angularSize;
					}
				}
				if (bestJD <= 0.0) return;
				core->setJD(bestJD);
				core->update(0);
				QString designation = object->getEnglishName();
				if (designation.isEmpty()) designation = fallbackName;
				if (designation.isEmpty()) designation = object->getID();
				QString name = object->getNameI18n();
				if (name.isEmpty()) name = fallbackName;
				if (name.isEmpty()) name = designation;
				const Vec4d rts = object->getRTSTime(core, minimumAltitude);
				QJsonObject target;
				target["name"] = name;
				target["englishName"] = designation;
				target["type"] = object->getObjectTypeI18n();
				target["jd"] = bestJD;
				target["altitude"] = bestAltitude;
				target["azimuth"] = bestAzimuth;
				if (!ignoreMagnitude) target["magnitude"] = bestMagnitude;
				if (sizeIsApplicable && bestAngularSize > 0.0) target["angularSizeArcmin"] = bestAngularSize;
				target["rise"] = fmtLocal(rts[0]);
				target["transit"] = fmtLocal(rts[1]);
				target["maxAltitude"] = maxAltitude(object);
				target["set"] = fmtLocal(rts[2]);
				const QString constellationId = core->getIAUConstellation(object->getEquinoxEquatorialPos(core));
				target["constellationId"] = constellationId;
				target["constellation"] = ConstellationMgr::getIAUconstellationName(constellationId);
				if (target["constellation"].toString().isEmpty()) target["constellation"] = constellationId;
				targets.append(target);
			};

			if (category == QStringLiteral("planets") || category == QStringLiteral("asteroids") || category == QStringLiteral("comets")
				|| category == QStringLiteral("plutinos") || category == QStringLiteral("dwarfPlanets") || category == QStringLiteral("cubewanos")
				|| category == QStringLiteral("scatteredDisc") || category == QStringLiteral("oortCloud") || category == QStringLiteral("sednoids") || category == QStringLiteral("interstellar"))
			{
				const QMap<QString, Planet::PlanetType> planetTypes = {
					{QStringLiteral("planets"), Planet::isPlanet}, {QStringLiteral("asteroids"), Planet::isAsteroid},
					{QStringLiteral("comets"), Planet::isComet}, {QStringLiteral("plutinos"), Planet::isPlutino},
					{QStringLiteral("dwarfPlanets"), Planet::isDwarfPlanet}, {QStringLiteral("cubewanos"), Planet::isCubewano},
					{QStringLiteral("scatteredDisc"), Planet::isSDO}, {QStringLiteral("oortCloud"), Planet::isOCO},
					{QStringLiteral("sednoids"), Planet::isSednoid}, {QStringLiteral("interstellar"), Planet::isInterstellar}};
				const Planet::PlanetType expectedType = planetTypes.value(category);
				for (const PlanetP& planet : ssys->getAllPlanets())
					if (planet && planet != core->getCurrentPlanet() && planet->getPlanetType() == expectedType)
						appendTarget(qSharedPointerCast<StelObject>(planet), planet->getEnglishName());
			}
			else if (starMgr && (category == QStringLiteral("stars") || category == QStringLiteral("carbonStars") || category == QStringLiteral("bariumStars")))
			{
				const QList<StelObjectP> stars = category == QStringLiteral("carbonStars") ? starMgr->getHipparcosCarbonStars()
					: (category == QStringLiteral("bariumStars") ? starMgr->getHipparcosBariumStars() : starMgr->getHipparcosStars());
				for (const StelObjectP& star : stars) appendTarget(star, QString(), false, false);
			}
			else if (starMgr && (category == QStringLiteral("variableStars") || category == QStringLiteral("algolVariables") || category == QStringLiteral("cepheidVariables") || category == QStringLiteral("highProperMotion")))
			{
				const QList<StelACStarData> stars = category == QStringLiteral("algolVariables") ? starMgr->getHipparcosAlgolTypeStars()
					: (category == QStringLiteral("cepheidVariables") ? starMgr->getHipparcosClassicalCepheidsTypeStars()
					: (category == QStringLiteral("highProperMotion") ? starMgr->getHipparcosHighPMStars() : starMgr->getHipparcosVariableStars()));
				for (const StelACStarData& star : stars) appendTarget(star.first, QString(), false, false);
			}
			else if (nebulaMgr)
			{
				QList<NebulaP> candidates;
				if (category == QStringLiteral("messier")) candidates = nebulaMgr->getDeepSkyObjectsByType(QStringLiteral("100"));
				else if (category == QStringLiteral("ngcic")) { candidates = nebulaMgr->getDeepSkyObjectsByType(QStringLiteral("108")); candidates.append(nebulaMgr->getDeepSkyObjectsByType(QStringLiteral("109"))); }
				else if (category == QStringLiteral("caldwell")) candidates = nebulaMgr->getDeepSkyObjectsByType(QStringLiteral("101"));
				else if (category == QStringLiteral("herschel400")) candidates = nebulaMgr->getDeepSkyObjectsByType(QStringLiteral("151"));
				else candidates = nebulaMgr->getAllDeepSkyObjects();
				for (const NebulaP& nebula : candidates)
				{
					if (!nebula) continue;
					const Nebula::NebulaType type = nebula->getDSOType();
					bool matches = category == QStringLiteral("messier") || category == QStringLiteral("ngcic") || category == QStringLiteral("caldwell") || category == QStringLiteral("herschel400") || category == QStringLiteral("deepSky");
					if (category == QStringLiteral("brightNebulae")) matches = QList<Nebula::NebulaType>({Nebula::NebN, Nebula::NebBn, Nebula::NebEn, Nebula::NebRn, Nebula::NebHII, Nebula::NebISM, Nebula::NebCn, Nebula::NebSNR}).contains(type);
					else if (category == QStringLiteral("darkNebulae")) matches = QList<Nebula::NebulaType>({Nebula::NebDn, Nebula::NebMolCld, Nebula::NebYSO}).contains(type);
					else if (category == QStringLiteral("galaxies")) matches = type == Nebula::NebGx;
					else if (category == QStringLiteral("openClusters")) matches = QList<Nebula::NebulaType>({Nebula::NebCl, Nebula::NebOc, Nebula::NebSA, Nebula::NebSC, Nebula::NebCn}).contains(type);
					else if (category == QStringLiteral("planetaryNebulae")) matches = QList<Nebula::NebulaType>({Nebula::NebPn, Nebula::NebPossPN, Nebula::NebPPN}).contains(type);
					else if (category == QStringLiteral("symbioticStars")) matches = type == Nebula::NebSymbioticStar;
					else if (category == QStringLiteral("emissionLineStars")) matches = type == Nebula::NebEmissionLineStar;
					else if (category == QStringLiteral("supernovaCandidates")) matches = type == Nebula::NebSNC;
					else if (category == QStringLiteral("snrCandidates")) matches = type == Nebula::NebSNRC;
					else if (category == QStringLiteral("supernovaRemnants")) matches = type == Nebula::NebSNR;
					else if (category == QStringLiteral("galaxyClusters")) matches = type == Nebula::NebGxCl;
					else if (category == QStringLiteral("globularClusters")) matches = type == Nebula::NebGc;
					else if (category == QStringLiteral("skyRegions")) matches = type == Nebula::NebRegion;
					else if (category == QStringLiteral("activeGalaxies")) matches = QList<Nebula::NebulaType>({Nebula::NebQSO, Nebula::NebPossQSO, Nebula::NebAGx, Nebula::NebRGx, Nebula::NebBLA, Nebula::NebBLL}).contains(type);
					else if (category == QStringLiteral("interactingGalaxies")) matches = type == Nebula::NebIGx;
					if (!matches) continue;
					QString designation = nebula->getDSODesignation();
					if (designation.isEmpty()) designation = nebula->getDSODesignationWIC();
					appendTarget(qSharedPointerCast<StelObject>(nebula), designation, category == QStringLiteral("darkNebulae") || category == QStringLiteral("skyRegions"), category != QStringLiteral("skyRegions"));
				}
			}

			core->setJD(originalJD);
			core->update(0);
			std::sort(targets.begin(), targets.end(), [](const QJsonObject& first, const QJsonObject& second) {
				const double firstAltitude = first.value("altitude").toDouble();
				const double secondAltitude = second.value("altitude").toDouble();
				if (!qFuzzyCompare(firstAltitude + 91.0, secondAltitude + 91.0)) return firstAltitude > secondAltitude;
				return first.value("magnitude").toDouble(99.0) < second.value("magnitude").toDouble(99.0);
			});
			while (targets.size() > 120) targets.removeLast();
			QJsonArray items;
			for (const QJsonObject& target : targets) items.append(target);
			result["ok"] = true;
			result["period"] = period;
			result["angularSizeAvailable"] = angularSizeAvailable;
			result["observationTime"] = fmtLocal(period == QStringLiteral("evening") ? evening : (period == QStringLiteral("morning") ? morning : midnight));
			result["wutTargets"] = items;
			return result;
		}

		// ========== Help/日志 与 配置导入导出 ==========
		// getLog — 返回应用日志尾部（arg=最大字符数，默认 8000）
		if (commandName == "getLog")
		{
			int maxChars = arg.trimmed().isEmpty() ? 8000 : arg.trimmed().toInt();
			if (maxChars <= 0) maxChars = 8000;
			const QString& full = StelLogger::getLog();
			QString tail = full.length() > maxChars ? full.right(maxChars) : full;
			result["ok"] = true;
			result["log"] = tail;
			result["totalChars"] = full.length();
			result["logFile"] = StelLogger::getLogFileName();
			return result;
		}
		// getAboutInfo — 版本/构建/路径信息（About 页数据源）
		if (commandName == "getAboutInfo")
		{
			result["ok"] = true;
			result["version"] = StelUtils::getApplicationVersion();
			result["qtVersion"] = QT_VERSION_STR;
			result["userDir"] = StelFileMgr::getUserDir();
			result["configFile"] = StelApp::getInstance().getSettings()->fileName();
			result["logFile"] = StelLogger::getLogFileName();
			return result;
		}
		// exportConfig — 导出 config.ini 全文（先 sync 落盘再读）
		if (commandName == "exportConfig")
		{
			QSettings* conf = StelApp::getInstance().getSettings();
			conf->sync();
			QFile f(conf->fileName());
			if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
			{
				result["ok"] = false;
				result["error"] = "cannot read config: " + conf->fileName();
				return result;
			}
			QString content = QString::fromUtf8(f.readAll());
			f.close();
			result["ok"] = true;
			result["content"] = content;
			result["configFile"] = conf->fileName();
			return result;
		}
		// importConfig — 导入 ini 文本：按 [section] + key=value 逐条写入并 sync
		if (commandName == "importConfig")
		{
			QSettings* conf = StelApp::getInstance().getSettings();
			QString section;
			int applied = 0;
			const QStringList lines = arg.split('\n');
			for (const QString& rawLine : lines)
			{
				QString line = rawLine.trimmed();
				if (line.isEmpty() || line.startsWith('#') || line.startsWith(';'))
					continue;
				if (line.startsWith('[') && line.endsWith(']'))
				{
					section = line.mid(1, line.length() - 2).trimmed();
					continue;
				}
				int eq = line.indexOf('=');
				if (eq <= 0)
					continue;
				QString key = line.left(eq).trimmed();
				QString val = line.mid(eq + 1).trimmed();
				QString fullKey = section.isEmpty() ? key : section + "/" + key;
				conf->setValue(fullKey, val);
				applied++;
			}
			conf->sync();
			result["ok"] = true;
			result["applied"] = applied;
			return result;
		}

		// ===== 脚本录制 / 回放（#39）=====
		if (commandName == "listRecordings")
		{
			QJsonArray items;
			for (const RecordingItem& it : recordingsList())
			{
				QJsonObject o;
				o["file"] = it.file;
				o["name"] = it.name;
				o["created"] = it.created;
				o["count"] = it.count;
				items.append(o);
			}
			result["ok"] = true;
			result["items"] = items;
			return result;
		}

		if (commandName == "saveRecording")
		{
			// payload: name|jsonText
			QString name = arg.section('|', 0, 0).trimmed();
			QString jsonText = arg.mid(arg.indexOf('|') + 1);
			if (name.isEmpty())
				name = QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss");
			QString file = name;
			file.replace('/', '_').replace('\\', '_').replace(':', '_').replace(' ', '_');
			if (!file.endsWith(".json"))
				file += ".json";
			QFile f(recordingsDir() + "/" + file);
			if (!f.open(QIODevice::WriteOnly))
			{
				result["ok"] = false;
				result["error"] = "cannot open file";
				return result;
			}
			// 包裹成标准结构：{name, created, commands:[{c,p,t}]}。
			// t 为可选的相对毫秒时间；旧版仅含 c/p 的录制保持兼容。
			QJsonObject root;
			root["name"] = name;
			root["created"] = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss");
			QJsonDocument incoming = QJsonDocument::fromJson(jsonText.toUtf8());
			if (incoming.isArray())
				root["commands"] = incoming.array();
			else if (incoming.isObject() && incoming.object().contains("commands"))
				root["commands"] = incoming.object().value("commands");
			else
				root["commands"] = QJsonArray();
			f.write(QJsonDocument(root).toJson());
			f.close();
			result["ok"] = true;
			result["file"] = file;
			result["name"] = name;
			return result;
		}

		if (commandName == "loadRecording")
		{
			// payload: file
			QFile f(recordingsDir() + "/" + arg);
			if (!f.open(QIODevice::ReadOnly))
			{
				result["ok"] = false;
				result["error"] = "not found";
				return result;
			}
			const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
			f.close();
			result["ok"] = true;
			result["name"] = doc.object().value("name").toString(arg);
			result["commands"] = doc.object().value("commands").toArray();
			return result;
		}

		if (commandName == "deleteRecording")
		{
			QFile f(recordingsDir() + "/" + arg);
			bool removed = f.remove();
			result["ok"] = removed;
			if (!removed)
				result["error"] = "cannot remove";
			return result;
		}

		// ===== 视频帧序列录制（#40，基础 SDK 无视频编码器，先输出帧图）=====
		if (commandName == "startVideoRecording")
		{
			QStringList parts = arg.split('|', Qt::SkipEmptyParts);
			int fps = parts.size() > 0 ? parts[0].toInt() : 1;
			int duration = parts.size() > 1 ? parts[1].toInt() : 5;
			if (fps < 1) fps = 1;
			if (fps > 30) fps = 30;
			if (duration < 1) duration = 1;
			if (duration > 60) duration = 60;
			if (g_videoRecorder.recording)
			{
				result["ok"] = false;
				result["error"] = "already recording";
				return result;
			}
			QString dir = videosDir() + "/" + QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss");
			QDir d(dir);
			if (!d.exists())
				d.mkpath(dir);
			g_videoRecorder.recording = true;
			g_videoRecorder.dir = dir;
			g_videoRecorder.fps = fps;
			g_videoRecorder.frameCount = 0;
			g_videoRecorder.maxFrames = fps * duration;
			if (!g_videoRecorder.timer)
			{
				g_videoRecorder.timer = new QTimer(&StelMainView::getInstance());
				QObject::connect(g_videoRecorder.timer, &QTimer::timeout, videoCaptureFrame);
			}
			g_videoRecorder.timer->setInterval(qMax(50, 1000 / fps));
			g_videoRecorder.timer->start();
			result["ok"] = true;
			result["dir"] = dir;
			result["fps"] = fps;
			result["duration"] = duration;
			result["maxFrames"] = g_videoRecorder.maxFrames;
			return result;
		}

		if (commandName == "stopVideoRecording")
		{
			g_videoRecorder.recording = false;
			if (g_videoRecorder.timer)
				g_videoRecorder.timer->stop();
			int disk = countVideoFrames(g_videoRecorder.dir);
			result["ok"] = true;
			result["dir"] = g_videoRecorder.dir;
			result["frameCount"] = g_videoRecorder.frameCount;
			result["diskFrames"] = disk;
			result["fps"] = g_videoRecorder.fps;
			return result;
		}

		if (commandName == "getVideoRecordingState")
		{
			result["ok"] = true;
			result["recording"] = g_videoRecorder.recording;
			result["dir"] = g_videoRecorder.dir;
			result["frameCount"] = g_videoRecorder.frameCount;
			result["maxFrames"] = g_videoRecorder.maxFrames;
			result["fps"] = g_videoRecorder.fps;
			return result;
		}

		// ========== 天文计算（AstroCalc）桥接命令 ==========

		// getSiderealTime — 当地恒星时（小时，[0,24)）
		if (commandName == "getSiderealTime")
		{
			StelCore* core = StelApp::getInstance().getCore();
			// getLocalSiderealTime() 返回弧度，需换算成小时：2π rad = 24 h
			double lst = core->getLocalSiderealTime() * 12.0 / M_PI;
			lst = std::fmod(lst, 24.0);
			if (lst < 0) lst += 24.0;
			int h = (int)lst;
			int m = (int)((lst - h) * 60.0);
			result["ok"] = true;
			result["hours"] = lst;
			result["h"] = h;
			result["m"] = m;
			int s = (int)(((lst - h) * 60.0 - m) * 60.0);
			result["s"] = s;
			result["text"] = QString("%1h %2m %3s").arg(h).arg(m, 2, 10, QChar('0')).arg(s, 2, 10, QChar('0'));
			return result;
		}

		// getPolarScopeData — 离线极轴镜模拟数据。
		// 极轴镜的视场固定在天球极点，显示位置由当前恒星时和恒星的
		// 实时赤道坐标计算。ArkUI 只绘制分划，不在 UI 层硬编码星点坐标。
		if (commandName == "getPolarScopeData")
		{
			if (!core)
			{
				result["error"] = "core unavailable";
				return result;
			}
			const StelLocation& location = core->getCurrentLocation();
			const QString observerPlanet = core->getCurrentPlanet() ? core->getCurrentPlanet()->getEnglishName() : QString();
			if (observerPlanet.compare(QStringLiteral("Earth"), Qt::CaseInsensitive) != 0)
			{
				result["error"] = QStringLiteral("polar scope requires an Earth observer");
				result["observerPlanet"] = observerPlanet;
				return result;
			}

			const bool north = location.getLatitude() >= 0.0f;
			const Vec3d poleEquinox(0.0, 0.0, north ? 1.0 : -1.0);
			const Vec3d poleJ2000 = core->equinoxEquToJ2000(poleEquinox, StelCore::RefractionOff);
			StarMgr* stars = GETSTELMODULE(StarMgr);
			if (!stars)
			{
				result["error"] = "star manager unavailable";
				return result;
			}

			double siderealHours = core->getLocalSiderealTime() * 12.0 / M_PI;
			siderealHours = std::fmod(siderealHours, 24.0);
			if (siderealHours < 0.0) siderealHours += 24.0;
			auto formatHours = [](double hours) {
				hours = std::fmod(hours, 24.0);
				if (hours < 0.0) hours += 24.0;
				const int h = static_cast<int>(hours);
				const int m = static_cast<int>((hours - h) * 60.0);
				const int s = qBound(0, static_cast<int>(((hours - h) * 60.0 - m) * 60.0 + 0.5), 59);
				return QStringLiteral("%1h %2m %3s").arg(h, 2, 10, QChar('0')).arg(m, 2, 10, QChar('0')).arg(s, 2, 10, QChar('0'));
			};

			struct PolarStar {
				StelObjectP object;
				double radiusDeg = 0.0;
				double positionAngleDeg = 0.0;
				double magnitude = 99.0;
			};
			QList<PolarStar> polarStars;
			const QList<StelObjectP> candidates = stars->searchAround(poleJ2000, 12.0, core);
			for (const StelObjectP& object : candidates)
			{
				if (!object) continue;
				Vec3d position = core->j2000ToEquinoxEqu(object->getJ2000EquatorialPos(core), StelCore::RefractionOff);
				position.normalize();
				const double dot = qBound(-1.0, position * poleEquinox, 1.0);
				const double radiusDeg = std::acos(dot) * M_180_PI;
				const double magnitude = object->getVMagnitude(core);
				if (radiusDeg > 12.0 || magnitude > 8.0) continue;
				double ra = std::atan2(position[1], position[0]);
				if (ra < 0.0) ra += 2.0 * M_PI;
				double hourAngle = siderealHours - ra * 12.0 / M_PI;
				hourAngle = std::fmod(hourAngle, 24.0);
				if (hourAngle < 0.0) hourAngle += 24.0;
				// 12-hour clock position: HA 0h is at the top and increases clockwise.
				double positionAngleDeg = std::fmod(360.0 - hourAngle * 15.0 + 360.0, 360.0);
				if (!north) positionAngleDeg = std::fmod(360.0 - positionAngleDeg + 360.0, 360.0);
				PolarStar star;
				star.object = object;
				star.radiusDeg = radiusDeg;
				star.positionAngleDeg = positionAngleDeg;
				star.magnitude = magnitude;
				polarStars.append(star);
			}
			std::sort(polarStars.begin(), polarStars.end(), [](const PolarStar& left, const PolarStar& right) {
				return left.magnitude < right.magnitude;
			});

			const QString preferredName = north ? QStringLiteral("Polaris") : QStringLiteral("Sigma Octantis");
			PolarStar poleStar;
			bool hasPoleStar = false;
			for (const PolarStar& star : polarStars)
			{
				if (star.object->getEnglishName().compare(preferredName, Qt::CaseInsensitive) == 0)
				{
					poleStar = star;
					hasPoleStar = true;
					break;
				}
			}
			if (!hasPoleStar && !polarStars.isEmpty())
			{
				for (const PolarStar& star : polarStars)
					if (star.radiusDeg <= 2.0) { poleStar = star; hasPoleStar = true; break; }
			}

			result["ok"] = true;
			result["hemisphere"] = north ? QStringLiteral("north") : QStringLiteral("south");
			result["poleName"] = north ? QStringLiteral("北天极") : QStringLiteral("南天极");
			result["planetName"] = observerPlanet;
			result["latitude"] = location.getLatitude();
			result["siderealHours"] = siderealHours;
			result["poleRa"] = QStringLiteral("00h 00m 00s");
			result["poleDec"] = north ? QStringLiteral("+90° 00′ 00″") : QStringLiteral("-90° 00′ 00″");
			// The live Stellarium renderer supplies the stars. Keep this payload
			// limited to reticle geometry so ArkUI never builds a second sky layer.
			result["stars"] = QJsonArray();
			result["starCount"] = polarStars.size();
			const StelProjectorP projector = core->getProjection(StelCore::FrameJ2000, StelCore::RefractionOff);
			const Vec4i viewport = projector ? projector->getViewport() : Vec4i();
			auto appendScreenPosition = [&result, &projector, &viewport](const Vec3d& position,
				const QString& validKey, const QString& xKey, const QString& yKey) {
				Vec3d projected;
				const bool valid = projector && viewport[2] > 1 && viewport[3] > 1
					&& projector->project(position, projected);
				result[validKey] = valid;
				if (!valid) return;
				result[xKey] = (projected[0] - viewport[0]) / viewport[2];
				result[yKey] = (viewport[1] + viewport[3] - 1.0 - projected[1]) / viewport[3];
			};
			appendScreenPosition(poleJ2000, QStringLiteral("poleScreenValid"),
				QStringLiteral("poleScreenXRatio"), QStringLiteral("poleScreenYRatio"));
			if (hasPoleStar)
			{
				appendScreenPosition(poleStar.object->getJ2000EquatorialPos(core),
					QStringLiteral("poleStarScreenValid"), QStringLiteral("poleStarScreenXRatio"),
					QStringLiteral("poleStarScreenYRatio"));
				const Vec3d position = poleStar.object->getEquinoxEquatorialPos(core);
				double ra = std::atan2(position[1], position[0]);
				if (ra < 0.0) ra += 2.0 * M_PI;
				double hourAngle = siderealHours - ra * 12.0 / M_PI;
				hourAngle = std::fmod(hourAngle, 24.0);
				if (hourAngle < 0.0) hourAngle += 24.0;
				result["poleStarName"] = poleStar.object->getNameI18n().isEmpty() ? poleStar.object->getEnglishName() : poleStar.object->getNameI18n();
				result["poleStarEnglishName"] = poleStar.object->getEnglishName();
				result["poleStarMagnitude"] = poleStar.magnitude;
				result["poleStarRadiusDeg"] = poleStar.radiusDeg;
				result["hourAngleHours"] = hourAngle;
				result["hourAngleText"] = formatHours(hourAngle);
				result["viewAngleHours"] = poleStar.positionAngleDeg / 15.0;
				result["viewAngleText"] = formatHours(poleStar.positionAngleDeg / 15.0);
			}
			else
			{
				result["poleStarName"] = north ? QStringLiteral("北极星附近亮星") : QStringLiteral("南天极附近亮星");
				result["hourAngleText"] = QStringLiteral("--");
				result["viewAngleText"] = QStringLiteral("--");
			}
			QJsonObject polarScope = result;
			polarScope.remove("ok");
			result["polarScope"] = polarScope;
			return result;
		}

		// getNightMode / setNightMode — 夜视（红光）模式
		if (commandName == "getNightMode")
		{
			result["ok"] = true;
			result["night"] = StelApp::getInstance().getVisionModeNight();
			return result;
		}
		if (commandName == "setNightMode")
		{
			bool on = (arg.trimmed() == "1" || arg.trimmed().toLower() == "true");
			StelApp::getInstance().setVisionModeNight(on);
			result["ok"] = true;
			result["night"] = StelApp::getInstance().getVisionModeNight();
			return result;
		}

		// getAtmosphereParams / setAtmosphereParams — 大气折射与消光参数
		// Stellarium 没有全局的“折射开关”，折射由大气参数驱动：气压设为 0 mbar 即等价于关闭折射。
		if (commandName == "getAtmosphereParams")
		{
			StelSkyDrawer* drawer = StelApp::getInstance().getCore()->getSkyDrawer();
			if (!drawer)
			{
				result["error"] = "sky drawer not available";
				return result;
			}
			result["ok"] = true;
			result["pressure"] = drawer->getAtmospherePressure();
			result["temperature"] = drawer->getAtmosphereTemperature();
			result["extinction"] = drawer->getExtinctionCoefficient();
			result["refractionOn"] = drawer->getAtmospherePressure() > 0.0;
			return result;
		}
		if (commandName == "setAtmosphereParams")
		{
			StelSkyDrawer* drawer = StelApp::getInstance().getCore()->getSkyDrawer();
			if (!drawer)
			{
				result["error"] = "sky drawer not available";
				return result;
			}
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject jo = doc.isObject() ? doc.object() : QJsonObject();
			if (jo.contains("pressure"))
				drawer->setAtmospherePressure(qBound(0.0, jo.value("pressure").toDouble(), 1500.0));
			if (jo.contains("temperature"))
				drawer->setAtmosphereTemperature(qBound(-60.0, jo.value("temperature").toDouble(), 60.0));
			if (jo.contains("extinction"))
				drawer->setExtinctionCoefficient(qBound(0.0, jo.value("extinction").toDouble(), 1.0));
			result["ok"] = true;
			result["pressure"] = drawer->getAtmospherePressure();
			result["temperature"] = drawer->getAtmosphereTemperature();
			result["extinction"] = drawer->getExtinctionCoefficient();
			result["refractionOn"] = drawer->getAtmospherePressure() > 0.0;
			return result;
		}

		// getEphemeris — 一个或多个天体的星历表：随时间变化的 RA/Dec/高度/方位/星等
		if (commandName == "getEphemeris")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject jo = doc.isObject() ? doc.object() : QJsonObject();
			QString name = jo.value("name").toString();
			QStringList names;
			if (jo.value("names").isArray())
			{
				for (const QJsonValue& value : jo.value("names").toArray())
				{
					const QString objectName = value.toString();
					if (!objectName.isEmpty() && !names.contains(objectName))
						names.append(objectName);
				}
			}
			const bool allNakedEye = jo.value("allNakedEye").toBool(false);
			double startJD = jo.value("jd").toDouble(0.0);
			const int days = qBound(1, jo.value("days").toInt(14), 31);
			const int stepHours = qBound(1, jo.value("stepHours").toInt(24), 24);

			if (allNakedEye)
			{
				SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
				if (!solarSystem || core->getCurrentPlanet()->getEnglishName() != QStringLiteral("Earth"))
				{
					result["ok"] = false;
					result["error"] = "Naked-eye planet ephemeris is available on Earth only";
					return result;
				}
				names = QStringList() << "Mercury" << "Venus" << "Mars" << "Jupiter" << "Saturn";
			}
			else if (!name.isEmpty() && names.isEmpty())
				names.append(name);

			QList<StelObjectP> objects;
			if (!names.isEmpty())
			{
				for (const QString& objectName : names)
				{
					StelObjectP object = objectMgr->searchByName(objectName);
					if (object)
						objects.append(object);
				}
			}
			else
			{
				const QList<StelObjectP>& sel = objectMgr->getSelectedObject();
				if (!sel.isEmpty()) objects.append(sel.first());
			}
			if (objects.isEmpty())
			{
				result["ok"] = false;
				result["error"] = names.isEmpty() ? "no object selected" : ("object not found: " + names.join(','));
				return result;
			}
			if (startJD <= 0) startJD = core->getJD();
			const double origJD = core->getJD();
			QJsonArray rows;
			const int samples = (days * 24) / stepHours;
			for (int i = 0; i <= samples; ++i)
			{
				const double jd = startJD + i * stepHours / 24.0;
				core->setJD(jd);
				core->update(0);
				for (const StelObjectP& object : objects)
				{
					double ra = 0.0;
					double dec = 0.0;
					StelUtils::rectToSphe(&ra, &dec, object->getEquinoxEquatorialPos(core));
					double az = 0.0;
					double alt = 0.0;
					StelUtils::rectToSphe(&az, &alt, object->getAltAzPosAuto(core));
					QJsonObject row;
					row["jd"] = jd;
					row["date"] = StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
					row["bodyName"] = object->getNameI18n().isEmpty() ? object->getEnglishName() : object->getNameI18n();
					row["bodyEnglishName"] = object->getEnglishName();
					row["ra"] = StelUtils::radToHmsStr(ra);
					row["dec"] = StelUtils::radToDmsStr(dec);
					row["altitude"] = alt * 180.0 / M_PI;
					row["azimuth"] = StelUtils::fmodpos(az * 180.0 / M_PI, 360.0);
					row["magnitude"] = object->getVMagnitude(core);
					rows.append(row);
				}
			}
			core->setJD(origJD);
			core->update(0);
			result["ok"] = true;
			QStringList objectNames;
			for (const StelObjectP& object : objects)
				objectNames.append(object->getNameI18n().isEmpty() ? object->getEnglishName() : object->getNameI18n());
			result["name"] = objectNames.join(QStringLiteral("、"));
			result["ephemeris"] = rows;
			return result;
		}

		// getAltAzCurve — 选中（或指定）天体在一段时间内的高度/方位变化曲线（用于图表）
		if (commandName == "getAltAzCurve")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject jo = doc.isObject() ? doc.object() : QJsonObject();
			QString name = jo.value("name").toString();
			double startJD = jo.value("jd").toDouble(0.0);
			const int hours = qBound(1, jo.value("hours").toInt(24), 72);
			const int stepMin = qBound(5, jo.value("stepMin").toInt(30), 60);
			const bool includeSun = jo.value("includeSun").toBool(false);
			const bool includeMoon = jo.value("includeMoon").toBool(false);

			StelObjectP obj;
			if (!name.isEmpty())
				obj = objectMgr->searchByName(name);
			else
			{
				const QList<StelObjectP>& sel = objectMgr->getSelectedObject();
				if (!sel.isEmpty()) obj = sel.first();
			}
			if (!obj)
			{
				result["ok"] = false;
				result["error"] = name.isEmpty() ? "no object selected" : ("object not found: " + name);
				return result;
			}
			if (startJD <= 0) startJD = core->getJD();
			const double origJD = core->getJD();
			SolarSystem* solarSystem = (includeSun || includeMoon) ? GETSTELMODULE(SolarSystem) : nullptr;
			PlanetP sun = (includeSun && solarSystem) ? solarSystem->getSun() : PlanetP();
			PlanetP moon = (includeMoon && solarSystem) ? solarSystem->getMoon() : PlanetP();
			QJsonArray rows;
			int n = (hours * 60) / stepMin;
			for (int i = 0; i <= n; i++)
			{
				double jd = startJD + i * stepMin / 1440.0;
				core->setJD(jd);
				core->update(0);
				double az = 0.0;
				double alt = 0.0;
				StelUtils::rectToSphe(&az, &alt, obj->getAltAzPosAuto(core));
				QJsonObject row;
				row["jd"] = jd;
				row["t"] = i * stepMin / 60.0; // hours from start
				row["altitude"] = alt * 180.0 / M_PI;
				row["azimuth"] = StelUtils::fmodpos(az * 180.0 / M_PI, 360.0);
				if (sun)
				{
					double sunAzimuth = 0.0;
					double sunAltitude = 0.0;
					StelUtils::rectToSphe(&sunAzimuth, &sunAltitude, sun->getAltAzPosAuto(core));
					row["sunAltitude"] = sunAltitude * 180.0 / M_PI;
				}
				if (moon)
				{
					double moonAzimuth = 0.0;
					double moonAltitude = 0.0;
					StelUtils::rectToSphe(&moonAzimuth, &moonAltitude, moon->getAltAzPosAuto(core));
					row["moonAltitude"] = moonAltitude * 180.0 / M_PI;
				}
				rows.append(row);
			}
			core->setJD(origJD);
			core->update(0);
			result["ok"] = true;
			result["name"] = obj->getNameI18n();
			result["curve"] = rows;
			return result;
		}

		// getLunarElongationCurve - angular distance between the Moon and the selected target.
		if (commandName == "getLunarElongationCurve")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const QString name = options.value("name").toString();
			double startJD = options.value("jd").toDouble(0.0);
			const int days = qBound(7, options.value("days").toInt(30), 90);
			const int stepHours = qBound(1, options.value("stepHours").toInt(12), 24);

			StelObjectP object;
			if (!name.isEmpty())
				object = objectMgr->searchByName(name);
			else
			{
				const QList<StelObjectP>& selected = objectMgr->getSelectedObject();
				if (!selected.isEmpty()) object = selected.first();
			}
			if (!object)
			{
				result["ok"] = false;
				result["error"] = name.isEmpty() ? "no object selected" : ("object not found: " + name);
				return result;
			}

			SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
			PlanetP moon = solarSystem ? solarSystem->getMoon() : PlanetP();
			if (!moon)
			{
				result["ok"] = false;
				result["error"] = "Moon unavailable";
				return result;
			}
			if (object == moon || object->getType() == "Satellite")
			{
				result["ok"] = false;
				result["error"] = "lunar separation is unavailable for the Moon or satellites";
				return result;
			}

			if (startJD <= 0.0) startJD = core->getJD();
			const double originalJD = core->getJD();
			QJsonArray rows;
			const int samples = (days * 24) / stepHours;
			for (int index = 0; index <= samples; ++index)
			{
				const double jd = startJD + index * stepHours / 24.0;
				core->setJD(jd);
				core->update(0);
				QJsonObject row;
				row["jd"] = jd;
				row["t"] = index * stepHours / 24.0;
				row["date"] = StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
				row["separation"] = moon->getJ2000EquatorialPos(core).angle(object->getJ2000EquatorialPos(core)) * M_180_PI;
				rows.append(row);
			}
			core->setJD(originalJD);
			core->update(0);
			result["ok"] = true;
			result["name"] = object->getNameI18n();
			if (result["name"].toString().isEmpty()) result["name"] = object->getEnglishName();
			result["lunarElongation"] = rows;
			return result;
		}

		// getPlanetTimeSeries - two independent planetary quantities sampled over time.
		if (commandName == "getPlanetTimeSeries")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const QString name = options.value("name").toString();
			double startJD = options.value("jd").toDouble(0.0);
			const int days = qBound(7, options.value("days").toInt(30), 3650);
			const int stepHours = qBound(1, options.value("stepHours").toInt(24), 240);
			const QString leftMetric = options.value("leftMetric").toString("angularSize");
			const QString rightMetric = options.value("rightMetric").toString("magnitude");
			const QStringList metrics = {
				"magnitude", "phase", "distance", "elongation", "angularSize",
				"phaseAngle", "heliocentricDistance", "transitAltitude", "rightAscension", "declination"
			};
			if (!metrics.contains(leftMetric) || !metrics.contains(rightMetric))
			{
				result["ok"] = false;
				result["error"] = "unsupported graph metric";
				return result;
			}

			StelObjectP object;
			if (!name.isEmpty())
				object = objectMgr->searchByName(name);
			else
			{
				const QList<StelObjectP>& selected = objectMgr->getSelectedObject();
				if (!selected.isEmpty()) object = selected.first();
			}
			Planet* planet = object ? dynamic_cast<Planet*>(object.data()) : nullptr;
			if (!planet)
			{
				result["ok"] = false;
				result["error"] = "selected object is not a planet";
				return result;
			}

			if (startJD <= 0.0) startJD = core->getJD();
			const double originalJD = core->getJD();
			auto measure = [&](const QString& metric) -> double {
				const Vec3d observerPosition = core->getCurrentObserver()->getCenterVsop87Pos();
				if (metric == "magnitude") return planet->getVMagnitude(core);
				if (metric == "phase") return planet->getPhase(observerPosition) * 100.0;
				if (metric == "distance")
				{
					double distance = planet->getJ2000EquatorialPos(core).norm();
					if (planet->getEnglishName() == "Moon") distance *= AU * 0.001;
					return distance;
				}
				if (metric == "elongation") return planet->getElongation(observerPosition) * M_180_PI;
				if (metric == "angularSize") return planet->getSpheroidAngularRadius(core) * 7200.0;
				if (metric == "phaseAngle") return planet->getPhaseAngle(observerPosition) * M_180_PI;
				if (metric == "heliocentricDistance") return planet->getHeliocentricEclipticPos().norm();
				if (metric == "transitAltitude")
				{
					double azimuth = 0.0;
					double altitude = 0.0;
					StelUtils::rectToSphe(&azimuth, &altitude, planet->getAltAzPosAuto(core));
					return altitude * M_180_PI;
				}
				double rightAscension = 0.0;
				double declination = 0.0;
				StelUtils::rectToSphe(&rightAscension, &declination, planet->getEquinoxEquatorialPos(core));
				if (metric == "rightAscension")
				{
					rightAscension = 2.0 * M_PI - rightAscension;
					return rightAscension * 12.0 / M_PI;
				}
				return declination * M_180_PI;
			};

			QJsonArray rows;
			const int samples = (days * 24) / stepHours;
			for (int index = 0; index <= samples; ++index)
			{
				double jd = startJD + index * stepHours / 24.0;
				core->setJD(jd);
				core->update(0);
				if (leftMetric == "transitAltitude" || rightMetric == "transitAltitude")
				{
					const double transitJD = planet->getRTSTime(core)[1];
					if (transitJD > 0.0)
					{
						jd = transitJD;
						core->setJD(jd);
						core->update(0);
					}
				}
				QJsonObject row;
				row["jd"] = jd;
				row["t"] = (jd - startJD) * 24.0;
				row["date"] = StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
				row["left"] = measure(leftMetric);
				row["right"] = measure(rightMetric);
				rows.append(row);
			}
			core->setJD(originalJD);
			core->update(0);
			result["ok"] = true;
			result["name"] = object->getNameI18n();
			if (result["name"].toString().isEmpty()) result["name"] = object->getEnglishName();
			result["timeSeries"] = rows;
			return result;
		}

		// getAnnualElevation - sampled elevation for the current local year at a fixed local hour.
		if (commandName == "getAnnualElevation")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const QString name = options.value("name").toString();
			const int hour = qBound(0, options.value("hour").toInt(0), 23);

			StelObjectP object;
			if (!name.isEmpty())
				object = objectMgr->searchByName(name);
			else
			{
				const QList<StelObjectP>& selected = objectMgr->getSelectedObject();
				if (!selected.isEmpty()) object = selected.first();
			}
			if (!object)
			{
				result["ok"] = false;
				result["error"] = name.isEmpty() ? "no object selected" : ("object not found: " + name);
				return result;
			}

			const double originalJD = core->getJD();
			const double originalOffset = core->getUTCOffset(originalJD) / 24.0;
			int year = 0;
			int month = 0;
			int day = 0;
			StelUtils::getDateFromJulianDay(originalJD + originalOffset, &year, &month, &day);
			double localStartJD = 0.0;
			StelUtils::getJDFromDate(&localStartJD, year, 1, 1, hour, 0, 0);
			QJsonArray rows;
			for (int dayOffset = 0; dayOffset <= 366; dayOffset += 3)
			{
				const double approximateLocalJD = localStartJD + static_cast<double>(dayOffset);
				const double sampleJD = approximateLocalJD - core->getUTCOffset(approximateLocalJD) / 24.0;
				core->setJD(sampleJD);
				core->update(0);
				double azimuth = 0.0;
				double altitude = 0.0;
				StelUtils::rectToSphe(&azimuth, &altitude, object->getAltAzPosAuto(core));
				QJsonObject row;
				row["jd"] = sampleJD;
				row["date"] = StelUtils::julianDayToISO8601String(sampleJD + core->getUTCOffset(sampleJD) / 24.0).left(10);
				row["altitude"] = altitude * M_180_PI;
				row["azimuth"] = StelUtils::fmodpos(azimuth * M_180_PI, 360.0);
				rows.append(row);
			}
			core->setJD(originalJD);
			core->update(0);
			result["ok"] = true;
			result["name"] = object->getNameI18n();
			if (result["name"].toString().isEmpty()) result["name"] = object->getEnglishName();
			result["annualElevation"] = rows;
			return result;
		}

		// getObservabilityCalendar - future nightly observing windows for the selected target.
		if (commandName == "getObservabilityCalendar")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const QString name = options.value("name").toString();
			double startJD = options.value("jd").toDouble(0.0);
			const int days = qBound(7, options.value("days").toInt(30), 90);
			const double minAltitude = qBound(0.0, options.value("minAltitude").toDouble(20.0), 80.0);

			StelObjectP object;
			if (!name.isEmpty())
				object = objectMgr->searchByName(name);
			else
			{
				const QList<StelObjectP>& selected = objectMgr->getSelectedObject();
				if (!selected.isEmpty()) object = selected.first();
			}
			if (!object)
			{
				result["ok"] = false;
				result["error"] = name.isEmpty() ? "no object selected" : ("object not found: " + name);
				return result;
			}

			SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
			PlanetP sun = solarSystem ? solarSystem->getSun() : PlanetP();
			PlanetP moon = solarSystem ? solarSystem->getMoon() : PlanetP();
			if (!sun || !moon)
			{
				result["ok"] = false;
				result["error"] = "Sun or Moon unavailable";
				return result;
			}

			if (startJD <= 0.0) startJD = core->getJD();
			const double originalJD = core->getJD();
			QJsonArray rows;
			for (int day = 0; day < days; ++day)
			{
				core->setJD(startJD + static_cast<double>(day));
				core->update(0);
				const Vec4d twilight = sun->getRTSTime(core, -18.0);
				double dusk = twilight[2];
				double dawn = twilight[0];
				QJsonObject row;
				if (dusk <= 0.0 || dawn <= 0.0)
				{
					row["date"] = StelUtils::julianDayToISO8601String(startJD + day + core->getUTCOffset(startJD + day) / 24.0).left(10);
					row["darkHours"] = 0.0;
					row["visibleHours"] = 0.0;
					rows.append(row);
					continue;
				}
				if (dawn <= dusk) dawn += 1.0;
				const int samples = 24;
				const double step = (dawn - dusk) / static_cast<double>(samples);
				double maxAltitude = -90.0;
				double bestJD = dusk;
				double visibleHours = 0.0;
				double previousAltitude = -90.0;
				for (int sample = 0; sample <= samples; ++sample)
				{
					const double sampleJD = dusk + step * sample;
					core->setJD(sampleJD);
					core->update(0);
					double azimuth = 0.0;
					double altitude = 0.0;
					StelUtils::rectToSphe(&azimuth, &altitude, object->getAltAzPosAuto(core));
					const double altitudeDegrees = altitude * M_180_PI;
					if (altitudeDegrees > maxAltitude)
					{
						maxAltitude = altitudeDegrees;
						bestJD = sampleJD;
					}
					if (sample > 0 && previousAltitude >= minAltitude && altitudeDegrees >= minAltitude)
						visibleHours += step * 24.0;
					previousAltitude = altitudeDegrees;
				}

				core->setJD(bestJD);
				core->update(0);
				double moonAzimuth = 0.0;
				double moonAltitude = 0.0;
				StelUtils::rectToSphe(&moonAzimuth, &moonAltitude, moon->getAltAzPosAuto(core));
				const QVariantMap moonInfo = moon->getInfoMap(core);
				row["date"] = StelUtils::julianDayToISO8601String(dusk + core->getUTCOffset(dusk) / 24.0).left(10);
				row["bestJD"] = bestJD;
				row["peakTime"] = StelUtils::julianDayToISO8601String(bestJD + core->getUTCOffset(bestJD) / 24.0);
				row["maxAltitude"] = maxAltitude;
				row["visibleHours"] = visibleHours;
				row["darkHours"] = (dawn - dusk) * 24.0;
				row["moonIllumination"] = moonInfo.value("illumination", 0.0).toDouble();
				row["moonAltitude"] = moonAltitude * M_180_PI;
				rows.append(row);
			}
			core->setJD(originalJD);
			core->update(0);
			result["ok"] = true;
			result["name"] = object->getNameI18n();
			if (result["name"].toString().isEmpty()) result["name"] = object->getEnglishName();
			result["observability"] = rows;
			return result;
		}

		// getPlanetCalc — 行星计算器：各行星距离/相位/距角/星等/高度/升落
		if (commandName == "getPlanetCalc")
		{
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			QStringList planetNames = QStringList() << "Mercury" << "Venus" << "Mars" << "Jupiter"
													   << "Saturn" << "Uranus" << "Neptune" << "Pluto" << "Sun" << "Moon";
			auto formatLocal = [&](double jd) -> QString {
				if (jd <= 0.0)
					return QString();
				return StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
			};
			QJsonArray items;
			for (const QString& pn : planetNames)
			{
				PlanetP p = qSharedPointerCast<Planet>(ssys->searchByName(pn));
				if (!p) continue;
				QJsonObject po;
				po["name"] = p->getNameI18n();
				po["englishName"] = pn;
				double ra = 0.0;
				double dec = 0.0;
				StelUtils::rectToSphe(&ra, &dec, p->getEquinoxEquatorialPos(core));
				po["ra"] = StelUtils::radToHmsStr(ra);
				po["dec"] = StelUtils::radToDmsStr(dec);
				Vec3d aa = p->getAltAzPosApparent(core);
				po["altitude"] = std::asin(aa[2] / aa.norm()) * 180.0 / M_PI;
				po["azimuth"] = std::fmod(std::atan2(aa[1], -aa[0]) * 180.0 / M_PI + 360.0, 360.0);
				po["magnitude"] = p->getVMagnitude(core);
				const Vec4d rts = p->getRTSTime(core);
				po["rise"] = formatLocal(rts[0]);
				po["transit"] = formatLocal(rts[1]);
				po["set"] = formatLocal(rts[2]);
				if (pn != "Sun")
				{
					double dist = p->getDistance(); // AU
					po["distanceAU"] = dist;
				}
				if (pn == "Moon")
				{
					QVariantMap mim = p->getInfoMap(core);
					po["illumination"] = mim.value("illumination", 0).toDouble();
					po["age"] = mim.value("age", 0).toDouble();
				}
				else if (pn != "Sun" && pn != "Pluto")
				{
					Vec3d obsPos = core->getCurrentObserver()->getCenterVsop87Pos();
					po["elongation"] = p->getElongation(obsPos);
					po["phaseAngle"] = p->getPhaseAngle(obsPos);
					po["phase"] = p->getPhase(obsPos);
				}
				items.append(po);
			}
			result["ok"] = true;
			result["planetCalc"] = items;
			return result;
		}

		// getPlanetPairDistanceCurve - linear and angular distance between two solar-system bodies.
		if (commandName == "getPlanetPairDistanceCurve")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const QString firstName = options.value("first").toString("Sun");
			const QString secondName = options.value("second").toString("Moon");
			double centerJD = options.value("jd").toDouble(0.0);
			const int days = qBound(7, options.value("days").toInt(40), 365);
			const int stepDays = qBound(1, options.value("stepDays").toInt(4), 30);
			SolarSystem* solarSystem = GETSTELMODULE(SolarSystem);
			PlanetP first = solarSystem ? qSharedPointerCast<Planet>(solarSystem->searchByName(firstName)) : PlanetP();
			PlanetP second = solarSystem ? qSharedPointerCast<Planet>(solarSystem->searchByName(secondName)) : PlanetP();
			if (!first || !second || first == second)
			{
				result["ok"] = false;
				result["error"] = "two different solar-system bodies are required";
				return result;
			}

			if (centerJD <= 0.0) centerJD = core->getJD();
			const double originalJD = core->getJD();
			const double utcOffset = core->getUTCOffset(centerJD) / 24.0;
			const double localMidnightJD = std::floor(centerJD + utcOffset - 0.5) + 0.5 - utcOffset;
			const PlanetP currentPlanet = core->getCurrentPlanet();
			const bool angularAvailable = first != currentPlanet && second != currentPlanet;
			QJsonArray rows;
			for (int dayOffset = -days; dayOffset <= days; dayOffset += stepDays)
			{
				const double jd = localMidnightJD + dayOffset;
				core->setJD(jd);
				core->update(0);
				const Vec3d firstPosition = first->getJ2000EquatorialPos(core);
				const Vec3d secondPosition = second->getJ2000EquatorialPos(core);
				QJsonObject row;
				row["jd"] = jd;
				row["t"] = dayOffset;
				row["date"] = StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0);
				row["linearDistance"] = (firstPosition - secondPosition).norm();
				if (angularAvailable)
					row["angularDistance"] = firstPosition.angle(secondPosition) * M_180_PI;
				rows.append(row);
			}
			core->setJD(originalJD);
			core->update(0);
			result["ok"] = true;
			result["firstName"] = first->getNameI18n();
			if (result["firstName"].toString().isEmpty()) result["firstName"] = first->getEnglishName();
			result["secondName"] = second->getNameI18n();
			if (result["secondName"].toString().isEmpty()) result["secondName"] = second->getEnglishName();
			result["angularAvailable"] = angularAvailable;
			result["planetPairDistance"] = rows;
			return result;
		}

		// getPhenomena — 扫描天体接近、留点及行星轨道事件，再细化事件时刻。
		if (commandName == "getPhenomena")
		{
			struct PhenomenaSample
			{
				QList<double> pairSeparations;
				QList<double> solarSeparations;
				QList<double> heliocentricDistances;
				QList<double> rightAscensions;
			};

			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject jo = doc.isObject() ? doc.object() : QJsonObject();
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			const QStringList defaultPlanetNames = QStringList() << "Mercury" << "Venus" << "Mars" << "Jupiter"
															  << "Saturn" << "Uranus" << "Neptune";
			const QStringList selectablePlanetNames = QStringList() << "Sun" << "Moon" << "Mercury" << "Venus"
																 << "Mars" << "Jupiter" << "Saturn" << "Uranus" << "Neptune" << "Pluto";
			QList<QJsonObject> phenomenaList;
			QList<PlanetP> planets;
			PlanetP sun = ssys->getSun();
			if (!sun)
			{
				result["ok"] = false;
				result["error"] = "Sun unavailable";
				return result;
			}
			const QString primaryName = jo.value("bodyA").toString();
			const QString secondaryName = jo.value("bodyB").toString();
			const bool customPair = !primaryName.isEmpty() && primaryName != QStringLiteral("all");
			auto findPlanet = [&](const QString& name) -> PlanetP {
				return qSharedPointerCast<Planet>(ssys->searchByName(name));
			};
			if (customPair)
			{
				PlanetP primary = findPlanet(primaryName);
				if (!primary)
				{
					result["ok"] = false;
					result["error"] = "Selected body unavailable";
					return result;
				}
				planets.append(primary);
				const QStringList targetNames = secondaryName.isEmpty() || secondaryName == QStringLiteral("all")
					? selectablePlanetNames : QStringList() << secondaryName;
				for (const QString& name : targetNames)
				{
					if (name == primaryName)
						continue;
					PlanetP target = findPlanet(name);
					if (target)
						planets.append(target);
				}
			}
			else
			{
				for (const QString& name : defaultPlanetNames)
				{
					PlanetP planet = findPlanet(name);
					if (planet)
						planets.append(planet);
				}
			}
			if (planets.size() < 2)
			{
				result["ok"] = false;
				result["error"] = "Not enough bodies to compare";
				return result;
			}
			const double origJD = core->getJD();
			const double startJD = jo.value("jd").toDouble(origJD) + qBound(0, jo.value("startOffsetMonths").toInt(0), 24) * 30.4375;
			const int horizon = qBound(1, jo.value("days").toInt(400), 730);
			const double maxSeparation = qBound(0.5, jo.value("maxSeparation").toDouble(4.0), 20.0);
			const bool includeOppositions = jo.value("includeOppositions").toBool(true);
			const bool includePerihelionAphelion = jo.value("includePerihelionAphelion").toBool(true);
			const bool includeElongationsQuadratures = jo.value("includeElongationsQuadratures").toBool(true);
			const bool includeStations = jo.value("includeStations").toBool(true);
			const double coarseStep = 0.25; // 6 hours

			QList<QPair<int, int>> pairs;
			if (customPair)
			{
				for (int index = 1; index < planets.size(); ++index)
					pairs.append(qMakePair(0, index));
			}
			else
			{
				for (int a = 0; a < planets.size(); ++a)
					for (int b = a + 1; b < planets.size(); ++b)
						pairs.append(qMakePair(a, b));
			}

			auto separationAt = [&](double jd) -> PhenomenaSample {
				core->setJD(jd);
				core->update(0);
				PhenomenaSample sample;
				QList<Vec3d> positions;
				for (const PlanetP& planet : planets)
				{
					Vec3d position = planet->getEquinoxEquatorialPos(core);
					double ra = 0.0;
					double dec = 0.0;
					StelUtils::rectToSphe(&ra, &dec, position);
					position.normalize();
					positions.append(position);
					sample.heliocentricDistances.append(planet->getHeliocentricEclipticPos().norm());
					sample.rightAscensions.append(ra * 180.0 / M_PI);
				}
				Vec3d sunPosition = sun->getEquinoxEquatorialPos(core);
				sunPosition.normalize();
				for (const QPair<int, int>& pair : pairs)
					sample.pairSeparations.append(std::acos(qBound(-1.0, positions[pair.first].dot(positions[pair.second]), 1.0)) * 180.0 / M_PI);
				for (const Vec3d& position : positions)
					sample.solarSeparations.append(std::acos(qBound(-1.0, position.dot(sunPosition), 1.0)) * 180.0 / M_PI);
				return sample;
			};

			auto separationDeg = [&](PlanetP first, PlanetP second, double jd) -> double {
				core->setJD(jd);
				core->update(0);
				Vec3d firstPos = first->getEquinoxEquatorialPos(core); firstPos.normalize();
				Vec3d secondPos = second->getEquinoxEquatorialPos(core); secondPos.normalize();
				return std::acos(qBound(-1.0, firstPos.dot(secondPos), 1.0)) * 180.0 / M_PI;
			};

			auto refineMinimum = [&](PlanetP first, PlanetP second, double jd0) -> QPair<double, double> {
				double bestJD = jd0;
				double bestSeparation = 999.0;
				for (int k = -36; k <= 36; ++k)
				{
					const double jd = jd0 + k * (1.0 / 144.0); // 10 minutes
					const double separation = separationDeg(first, second, jd);
					if (separation < bestSeparation)
					{
						bestSeparation = separation;
						bestJD = jd;
					}
				}
				return qMakePair(bestJD, bestSeparation);
			};

			auto refineMaximum = [&](PlanetP first, PlanetP second, double jd0) -> QPair<double, double> {
				double bestJD = jd0;
				double bestSeparation = -1.0;
				for (int k = -36; k <= 36; ++k)
				{
					const double jd = jd0 + k * (1.0 / 144.0);
					const double separation = separationDeg(first, second, jd);
					if (separation > bestSeparation)
					{
						bestSeparation = separation;
						bestJD = jd;
					}
				}
				return qMakePair(bestJD, bestSeparation);
			};

			auto refineSolarCrossing = [&](PlanetP planet, double start, double end, double target) -> QPair<double, double> {
				double startValue = separationDeg(planet, sun, start) - target;
				for (int iteration = 0; iteration < 18; ++iteration)
				{
					const double middle = (start + end) / 2.0;
					const double middleValue = separationDeg(planet, sun, middle) - target;
					if ((startValue <= 0.0 && middleValue <= 0.0) || (startValue >= 0.0 && middleValue >= 0.0))
					{
						start = middle;
						startValue = middleValue;
					}
					else
						end = middle;
				}
				const double eventJD = (start + end) / 2.0;
				return qMakePair(eventJD, separationDeg(planet, sun, eventJD));
			};

			auto refineDistanceExtremum = [&](PlanetP planet, double jd0, bool minimum) -> QPair<double, double> {
				double bestJD = jd0;
				double bestDistance = minimum ? 999.0 : -1.0;
				for (int k = -36; k <= 36; ++k)
				{
					const double jd = jd0 + k * (1.0 / 144.0);
					const double distance = planet->getHeliocentricEclipticPos(jd + core->computeDeltaT(jd) / 86400.0).norm();
					if ((minimum && distance < bestDistance) || (!minimum && distance > bestDistance))
					{
						bestDistance = distance;
						bestJD = jd;
					}
				}
				return qMakePair(bestJD, bestDistance);
			};

			auto refineStationaryPoint = [&](PlanetP planet, double jd0, bool maximum) -> QPair<double, double> {
				core->setJD(jd0);
				core->update(0);
				Vec3d centerPosition = planet->getEquinoxEquatorialPos(core);
				double referenceRA = 0.0;
				double dec = 0.0;
				StelUtils::rectToSphe(&referenceRA, &dec, centerPosition);
				referenceRA *= 180.0 / M_PI;
				double bestJD = jd0;
				double bestRA = maximum ? -999.0 : 999.0;
				for (int k = -36; k <= 36; ++k)
				{
					const double jd = jd0 + k * (1.0 / 144.0);
					core->setJD(jd);
					core->update(0);
					Vec3d position = planet->getEquinoxEquatorialPos(core);
					double ra = 0.0;
					StelUtils::rectToSphe(&ra, &dec, position);
					ra *= 180.0 / M_PI;
					while (ra - referenceRA > 180.0) ra -= 360.0;
					while (ra - referenceRA < -180.0) ra += 360.0;
					if ((maximum && ra > bestRA) || (!maximum && ra < bestRA))
					{
						bestRA = ra;
						bestJD = jd;
					}
				}
				return qMakePair(bestJD, StelUtils::fmodpos(bestRA, 360.0));
			};

			auto addPhenomenon = [&](const QString& type, PlanetP first, PlanetP second, const QPair<double, double>& event,
				const QString& metricLabel, const QString& metricUnit = QStringLiteral("°")) {
				QJsonObject po;
				po["type"] = type;
				po["bodyA"] = first->getNameI18n();
				po["bodyB"] = second->getNameI18n();
				po["jd"] = event.first;
				po["date"] = StelUtils::julianDayToISO8601String(event.first + core->getUTCOffset(event.first) / 24.0);
				po["separation"] = event.second;
				po["metricLabel"] = metricLabel;
				po["metricUnit"] = metricUnit;
				phenomenaList.append(po);
			};

			const int samples = static_cast<int>(horizon / coarseStep);
			PhenomenaSample previous = separationAt(startJD);
			PhenomenaSample current = separationAt(startJD + coarseStep);
			for (int i = 1; i < samples; ++i)
			{
				const double jd = startJD + (i + 1) * coarseStep;
				const PhenomenaSample next = separationAt(jd);
				for (int pairIndex = 0; pairIndex < pairs.size(); ++pairIndex)
				{
					if (current.pairSeparations[pairIndex] <= previous.pairSeparations[pairIndex]
						&& current.pairSeparations[pairIndex] < next.pairSeparations[pairIndex]
						&& current.pairSeparations[pairIndex] <= maxSeparation)
					{
						const QPair<int, int>& pair = pairs[pairIndex];
						const QPair<double, double> event = refineMinimum(planets[pair.first], planets[pair.second], startJD + i * coarseStep);
						if (event.second <= maxSeparation)
							addPhenomenon(QStringLiteral("合"), planets[pair.first], planets[pair.second], event, QStringLiteral("角距"));
					}
				}
				const int specialPlanetEnd = customPair ? 1 : planets.size();
				for (int planetIndex = 0; planetIndex < specialPlanetEnd; ++planetIndex)
				{
					const QString englishName = planets[planetIndex]->getEnglishName();
					const bool outerPlanet = englishName == "Mars" || englishName == "Jupiter" || englishName == "Saturn"
						|| englishName == "Uranus" || englishName == "Neptune";
					const bool innerPlanet = englishName == "Mercury" || englishName == "Venus";
					const bool eligibleForOrbitalEvents = planets[planetIndex] != sun && englishName != "Moon";
					if (includeOppositions && outerPlanet && current.solarSeparations[planetIndex] >= previous.solarSeparations[planetIndex]
						&& current.solarSeparations[planetIndex] > next.solarSeparations[planetIndex]
						&& current.solarSeparations[planetIndex] >= 170.0)
					{
						const QPair<double, double> event = refineMaximum(planets[planetIndex], sun, startJD + i * coarseStep);
						if (event.second >= 170.0)
							addPhenomenon(QStringLiteral("冲"), planets[planetIndex], sun, event, QStringLiteral("距日"));
					}
					if (includeElongationsQuadratures && innerPlanet && current.solarSeparations[planetIndex] >= previous.solarSeparations[planetIndex]
						&& current.solarSeparations[planetIndex] > next.solarSeparations[planetIndex]
						&& current.solarSeparations[planetIndex] >= 10.0)
					{
						const QPair<double, double> event = refineMaximum(planets[planetIndex], sun, startJD + i * coarseStep);
						core->setJD(event.first);
						core->update(0);
						const double direction = planets[planetIndex]->getElongationDLambda() * 180.0 / M_PI;
						addPhenomenon(direction < 180.0 ? QStringLiteral("东大距") : QStringLiteral("西大距"),
							planets[planetIndex], sun, event, QStringLiteral("距日"));
					}
					if (includeElongationsQuadratures && outerPlanet)
					{
						const double currentOffset = current.solarSeparations[planetIndex] - 90.0;
						const double nextOffset = next.solarSeparations[planetIndex] - 90.0;
						if ((currentOffset <= 0.0 && nextOffset > 0.0) || (currentOffset >= 0.0 && nextOffset < 0.0))
						{
							const QPair<double, double> event = refineSolarCrossing(planets[planetIndex], startJD + i * coarseStep, jd, 90.0);
							core->setJD(event.first);
							core->update(0);
							const double direction = planets[planetIndex]->getElongationDLambda() * 180.0 / M_PI;
							addPhenomenon(direction < 180.0 ? QStringLiteral("东方照") : QStringLiteral("西方照"),
								planets[planetIndex], sun, event, QStringLiteral("距日"));
						}
					}
					if (includePerihelionAphelion && eligibleForOrbitalEvents && current.heliocentricDistances[planetIndex] <= previous.heliocentricDistances[planetIndex]
						&& current.heliocentricDistances[planetIndex] < next.heliocentricDistances[planetIndex])
					{
						const QPair<double, double> event = refineDistanceExtremum(planets[planetIndex], startJD + i * coarseStep, true);
						addPhenomenon(QStringLiteral("近日点"), planets[planetIndex], sun, event, QStringLiteral("日心距"), QStringLiteral(" AU"));
					}
					if (includePerihelionAphelion && eligibleForOrbitalEvents && current.heliocentricDistances[planetIndex] >= previous.heliocentricDistances[planetIndex]
						&& current.heliocentricDistances[planetIndex] > next.heliocentricDistances[planetIndex])
					{
						const QPair<double, double> event = refineDistanceExtremum(planets[planetIndex], startJD + i * coarseStep, false);
						addPhenomenon(QStringLiteral("远日点"), planets[planetIndex], sun, event, QStringLiteral("日心距"), QStringLiteral(" AU"));
					}
					const double previousMotion = StelUtils::fmodpos(current.rightAscensions[planetIndex] - previous.rightAscensions[planetIndex] + 180.0, 360.0) - 180.0;
					const double nextMotion = StelUtils::fmodpos(next.rightAscensions[planetIndex] - current.rightAscensions[planetIndex] + 180.0, 360.0) - 180.0;
					if (includeStations && eligibleForOrbitalEvents && previousMotion > 0.0 && nextMotion < 0.0)
					{
						const QPair<double, double> event = refineStationaryPoint(planets[planetIndex], startJD + i * coarseStep, true);
						addPhenomenon(QStringLiteral("留（转逆行）"), planets[planetIndex], sun, event, QStringLiteral("赤经"));
					}
					if (includeStations && eligibleForOrbitalEvents && previousMotion < 0.0 && nextMotion > 0.0)
					{
						const QPair<double, double> event = refineStationaryPoint(planets[planetIndex], startJD + i * coarseStep, false);
						addPhenomenon(QStringLiteral("留（转顺行）"), planets[planetIndex], sun, event, QStringLiteral("赤经"));
					}
				}
				previous = current;
				current = next;
			}
			QJsonArray items;
			core->setJD(origJD);
			core->update(0);
			// 按日期排序（QJsonArray 的迭代器不支持 std::sort，先在 QList 上排好再装回去）
			std::sort(phenomenaList.begin(), phenomenaList.end(), [](const QJsonObject& x, const QJsonObject& y) {
				return x.value("jd").toDouble() < y.value("jd").toDouble();
			});
			QList<QJsonObject> deduplicated;
			for (const QJsonObject& po : phenomenaList)
			{
				int duplicateIndex = -1;
				for (int index = deduplicated.size() - 1; index >= 0; --index)
				{
					const QJsonObject& previousEvent = deduplicated.at(index);
					if (po.value("jd").toDouble() - previousEvent.value("jd").toDouble() >= 30.0)
						break;
					if (po.value("type").toString() == previousEvent.value("type").toString()
						&& po.value("bodyA").toString() == previousEvent.value("bodyA").toString()
						&& po.value("bodyB").toString() == previousEvent.value("bodyB").toString())
					{
						duplicateIndex = index;
						break;
					}
				}
				if (duplicateIndex >= 0)
				{
					const bool conjunction = po.value("type").toString() == QStringLiteral("合");
					const double candidateValue = po.value("separation").toDouble();
					const double previousValue = deduplicated.at(duplicateIndex).value("separation").toDouble();
					if ((conjunction && candidateValue < previousValue) || (!conjunction && candidateValue > previousValue))
						deduplicated[duplicateIndex] = po;
					continue;
				}
				deduplicated.append(po);
			}
			for (const QJsonObject& po : deduplicated)
				items.append(po);
			result["ok"] = true;
			result["phenomena"] = items;
			return result;
		}

		if (commandName == "getMoonPhases")
		{
			QElapsedTimer moonPhaseTimer;
			moonPhaseTimer.start();
			struct MoonPhaseDefinition
			{
				double elongation;
				QString name;
			};

			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			const int days = qBound(1, options.value("days").toInt(30), 365);
			const double startJD = options.value("jd").toDouble(core->getJD());
			const double endJD = startJD + static_cast<double>(days);
			const double originalJD = core->getJD();
			const bool originalTopocentric = core->getUseTopocentricCoordinates();
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			PlanetP sun = ssys->getSun();
			PlanetP moon = ssys->getMoon();
			PlanetP earth = ssys->getEarth();
			if (!sun || !moon || !earth)
			{
				result["error"] = "Sun, Moon, or Earth unavailable";
				return result;
			}

			core->setUseTopocentricCoordinates(false);
			auto phaseOffset = [&](double jd, double target) -> double {
				core->setJD(jd);
				core->update(0);
				double moonRa = 0.0;
				double moonDec = 0.0;
				double sunRa = 0.0;
				double sunDec = 0.0;
				double moonLongitude = 0.0;
				double moonLatitude = 0.0;
				double sunLongitude = 0.0;
				double sunLatitude = 0.0;
				const double obliquity = earth->getRotObliquity(core->getJDE());
				StelUtils::rectToSphe(&moonRa, &moonDec, moon->getEquinoxEquatorialPos(core));
				StelUtils::rectToSphe(&sunRa, &sunDec, sun->getEquinoxEquatorialPos(core));
				StelUtils::equToEcl(moonRa, moonDec, obliquity, &moonLongitude, &moonLatitude);
				StelUtils::equToEcl(sunRa, sunDec, obliquity, &sunLongitude, &sunLatitude);
				return StelUtils::fmodpos((moonLongitude - sunLongitude) * M_180_PI - target, 360.0);
			};

			QList<QPair<MoonPhaseDefinition, double>> phaseEvents;
			const QList<MoonPhaseDefinition> phases = {
				{0.0, QStringLiteral("新月")},
				{90.0, QStringLiteral("上弦")},
				{180.0, QStringLiteral("满月")},
				{270.0, QStringLiteral("下弦")}
			};
			for (const MoonPhaseDefinition& phase : phases)
			{
				const double step = 0.25;
				double leftJD = startJD;
				double leftOffset = phaseOffset(leftJD, phase.elongation);
				if (leftOffset < 0.001)
					phaseEvents.append(qMakePair(phase, leftJD));
				for (double rightJD = startJD + step; rightJD <= endJD + 0.0001; rightJD += step)
				{
					const double rightOffset = phaseOffset(rightJD, phase.elongation);
					if (rightOffset < leftOffset)
					{
						double lower = leftJD;
						double upper = rightJD;
						for (int iteration = 0; iteration < 24; ++iteration)
						{
							const double middle = (lower + upper) * 0.5;
							if (phaseOffset(middle, phase.elongation) > 180.0)
								lower = middle;
							else
								upper = middle;
						}
						phaseEvents.append(qMakePair(phase, (lower + upper) * 0.5));
					}
					leftJD = rightJD;
					leftOffset = rightOffset;
				}
			}

			std::sort(phaseEvents.begin(), phaseEvents.end(), [](const QPair<MoonPhaseDefinition, double>& first, const QPair<MoonPhaseDefinition, double>& second) {
				return first.second < second.second;
			});
			core->setUseTopocentricCoordinates(true);
			auto formatLocal = [&](double jd) -> QString {
				return jd > 0.0 ? StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0) : QString();
			};
			QJsonArray items;
			for (const QPair<MoonPhaseDefinition, double>& event : phaseEvents)
			{
				core->setJD(event.second);
				core->update(0);
				const Vec3d altAz = moon->getAltAzPosApparent(core);
				const Vec4d rts = moon->getRTSTime(core);
				const QVariantMap moonInfo = moon->getInfoMap(core);
				QJsonObject item;
				item["phase"] = event.first.name;
				item["jd"] = event.second;
				item["date"] = formatLocal(event.second);
				item["illumination"] = moonInfo.value("illumination", 0.0).toDouble();
				item["altitude"] = std::asin(altAz[2] / altAz.norm()) * M_180_PI;
				item["azimuth"] = StelUtils::fmodpos(std::atan2(altAz[1], -altAz[0]) * M_180_PI, 360.0);
				item["rise"] = formatLocal(rts[0]);
				item["transit"] = formatLocal(rts[1]);
				item["set"] = formatLocal(rts[2]);
				items.append(item);
			}
			core->setJD(originalJD);
			core->setUseTopocentricCoordinates(originalTopocentric);
			core->update(0);
			result["ok"] = true;
			result["moonPhases"] = items;
			qInfo() << "[StellariumOhos][moon-phase] days=" << days
					<< "events=" << items.size()
					<< "elapsedMs=" << moonPhaseTimer.elapsed();
			return result;
		}

		// getPlanetaryTransits — Mercury/Venus transits across the Sun. This is the
		// same Besselian-element iteration used by AstroCalc's desktop transit table.
		if (commandName == "getPlanetaryTransits")
		{
			struct TransitElements
			{
				double x = 0.0;
				double y = 0.0;
				double d = 0.0;
				double tf1 = 0.0;
				double tf2 = 0.0;
				double L1 = 0.0;
				double L2 = 0.0;
				double mu = 0.0;
			};
			struct LocalTransitParams
			{
				double dt = 0.0;
				double L1 = 0.0;
				double L2 = 0.0;
				double ce = 0.0;
				double magnitude = 0.0;
				double altitude = 0.0;
			};

			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject options = doc.isObject() ? doc.object() : QJsonObject();
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			PlanetP earth = ssys ? ssys->getEarth() : PlanetP();
			PlanetP sun = ssys ? ssys->getSun() : PlanetP();
			if (!ssys || !earth || !sun || core->getCurrentPlanet() != earth)
			{
				result["ok"] = false;
				result["error"] = "planetary transits are only available for an observer on Earth";
				return result;
			}

			const double originalJD = core->getJD();
			const bool originalTopocentric = core->getUseTopocentricCoordinates();
			double startJD = options.value("jd").toDouble(originalJD);
			if (startJD <= 0.0) startJD = originalJD;
			const int years = qBound(1, options.value("years").toInt(20), 100);
			const double stopJD = startJD + static_cast<double>(years) * 365.2425;

			auto computeElements = [&](PlanetP object) -> TransitElements {
				core->setUseTopocentricCoordinates(false);
				core->update(0);
				TransitElements elements;
				double raPlanet = 0.0;
				double decPlanet = 0.0;
				double raSun = 0.0;
				double decSun = 0.0;
				const Vec3d sunPosition = sun->getEquinoxEquatorialPos(core);
				StelUtils::rectToSphe(&raSun, &decSun, sunPosition);
				StelUtils::rectToSphe(&raPlanet, &decPlanet, object->getEquinoxEquatorialPos(core));
				const double sunDistanceAu = sunPosition.norm();
				const double earthRadiusAu = earth->getEquatorialRadius() * AU;
				const double planetDistanceEarthRadii = object->getEquinoxEquatorialPos(core).norm() * AU / earthRadiusAu;
				const double gast = get_apparent_sidereal_time(core->getJD(), core->getJDE());
				double raDifference = StelUtils::fmodpos(raPlanet - raSun, 2.0 * M_PI);
				if (raDifference > M_PI) raDifference -= 2.0 * M_PI;
				constexpr double sunEarthRadiusRatio = 109.12278;
				const double solarRadiusEarthRadii = sunDistanceAu * 23454.7925;
				const double ratio = planetDistanceEarthRadii / solarRadiusEarthRadii;
				const double auxiliaryRa = raSun - ((ratio * std::cos(decPlanet) * raDifference) / ((1.0 - ratio) * std::cos(decSun)));
				elements.d = decSun - (ratio * (decPlanet - decSun) / (1.0 - ratio));
				elements.x = std::cos(decPlanet) * std::sin(raPlanet - auxiliaryRa) * planetDistanceEarthRadii;
				elements.y = (std::cos(elements.d) * std::sin(decPlanet)
					- std::cos(decPlanet) * std::sin(elements.d) * std::cos(raPlanet - auxiliaryRa)) * planetDistanceEarthRadii;
				double z = (std::sin(decPlanet) * std::sin(elements.d)
					+ std::cos(decPlanet) * std::cos(elements.d) * std::cos(raPlanet - auxiliaryRa)) * planetDistanceEarthRadii;
				const double planetEarthRadiusRatio = object->getEquatorialRadius() / earth->getEquatorialRadius();
				const double f1 = std::asin((sunEarthRadiusRatio + planetEarthRadiusRatio) / (solarRadiusEarthRadii * (1.0 - ratio)));
				const double f2 = std::asin((sunEarthRadiusRatio - planetEarthRadiusRatio) / (solarRadiusEarthRadii * (1.0 - ratio)));
				elements.tf1 = std::tan(f1);
				elements.tf2 = std::tan(f2);
				elements.L1 = z * elements.tf1 + planetEarthRadiusRatio / std::cos(f1);
				elements.L2 = z * elements.tf2 - planetEarthRadiusRatio / std::cos(f2);
				elements.mu = StelUtils::fmodpos(gast - auxiliaryRa * M_180_PI, 360.0);
				return elements;
			};

			auto localTransit = [&](double jd, int contact, bool central, PlanetP object) -> LocalTransitParams {
				const StelLocation& location = core->getCurrentLocation();
				const Vec4d geocentricCoordinates = earth->getRectangularCoordinates(
					static_cast<double>(location.getLongitude()), static_cast<double>(location.getLatitude()), static_cast<double>(location.altitude));
				const double rc = geocentricCoordinates[0] / earth->getEquatorialRadius();
				const double rs = geocentricCoordinates[1] / earth->getEquatorialRadius();
				core->setUseTopocentricCoordinates(false);
				core->setJD(jd);
				core->update(0);
				const TransitElements current = computeElements(object);
				core->setJD(jd - 5.0 / 1440.0);
				core->update(0);
				const TransitElements before = computeElements(object);
				core->setJD(jd + 5.0 / 1440.0);
				core->update(0);
				const TransitElements after = computeElements(object);
				const double xdot = (after.x - before.x) * 6.0;
				const double ydot = (after.y - before.y) * 6.0;
				const double ddot = (after.d - before.d) * 6.0;
				double mudot = after.mu - before.mu;
				if (mudot < 0.0) mudot += 360.0;
				mudot *= 6.0 * M_PI_180;
				const double theta = StelUtils::fmodpos((current.mu + location.getLongitude()) * M_PI_180, 2.0 * M_PI);
				const double xi = rc * std::sin(theta);
				const double eta = rs * std::cos(current.d) - rc * std::sin(current.d) * std::cos(theta);
				const double zeta = rs * std::sin(current.d) + rc * std::cos(current.d) * std::cos(theta);
				const double xidot = mudot * rc * std::cos(theta);
				const double etadot = mudot * xi * std::sin(current.d) - zeta * ddot;
				const double u = current.x - xi;
				const double v = current.y - eta;
				const double udot = xdot - xidot;
				const double vdot = ydot - etadot;
				const double rateSquared = udot * udot + vdot * vdot;
				const double rate = std::sqrt(rateSquared);
				const double delta = (u * vdot - udot * v) / rate;
				const double L1 = current.L1 - zeta * current.tf1;
				const double L2 = current.L2 - zeta * current.tf2;
				const double L = central ? L2 : L1;
				const double ce = 1.0 - std::pow(delta / L, 2.0);
				const double contactFactor = ce > 0.0 ? contact * std::sqrt(ce) : 0.0;
				LocalTransitParams params;
				params.dt = L * contactFactor / rate - (u * udot + v * vdot) / rateSquared;
				params.L1 = L1;
				params.L2 = L2;
				params.ce = ce;
				params.magnitude = (L1 - std::sqrt(u * u + v * v)) / (L1 + L2);
				params.altitude = std::asin(rc * std::cos(current.d) * std::cos(theta) + rs * std::sin(current.d)) * M_180_PI;
				return params;
			};

			auto refineLocalTransit = [&](double jd, int contact, bool central, PlanetP object) -> QPair<double, LocalTransitParams> {
				LocalTransitParams params;
				for (int iteration = 0; iteration < 20; ++iteration)
				{
					params = localTransit(jd, contact, central, object);
					jd += params.dt / 24.0;
					if (std::fabs(params.dt) <= 0.000001) break;
				}
				return qMakePair(jd, localTransit(jd, contact, central, object));
			};

			auto localVisibilityMinutes = [&](double firstJD, double lastJD, PlanetP object) -> double {
				QList<double> boundaries;
				boundaries.append(firstJD);
				constexpr int samples = 24;
				double previousJD = firstJD;
				double previousAltitude = localTransit(previousJD, 0, false, object).altitude + 0.3;
				for (int sample = 1; sample <= samples; ++sample)
				{
					const double currentJD = firstJD + (lastJD - firstJD) * sample / samples;
					const double currentAltitude = localTransit(currentJD, 0, false, object).altitude + 0.3;
					if ((previousAltitude < 0.0 && currentAltitude > 0.0) || (previousAltitude > 0.0 && currentAltitude < 0.0))
					{
						double lower = previousJD;
						double upper = currentJD;
						double lowerAltitude = previousAltitude;
						for (int iteration = 0; iteration < 18; ++iteration)
						{
							const double middle = (lower + upper) * 0.5;
							const double middleAltitude = localTransit(middle, 0, false, object).altitude + 0.3;
							if ((lowerAltitude <= 0.0 && middleAltitude <= 0.0) || (lowerAltitude >= 0.0 && middleAltitude >= 0.0))
							{
								lower = middle;
								lowerAltitude = middleAltitude;
							}
							else
								upper = middle;
						}
						boundaries.append((lower + upper) * 0.5);
					}
					previousJD = currentJD;
					previousAltitude = currentAltitude;
				}
				boundaries.append(lastJD);
				std::sort(boundaries.begin(), boundaries.end());
				double visibleMinutes = 0.0;
				for (int index = 0; index + 1 < boundaries.size(); ++index)
				{
					const double begin = boundaries.at(index);
					const double end = boundaries.at(index + 1);
					if (localTransit((begin + end) * 0.5, 0, false, object).altitude >= -0.3)
						visibleMinutes += (end - begin) * 1440.0;
				}
				return visibleMinutes;
			};

			auto formatLocal = [&](double jd) -> QString {
				return jd > 0.0 ? StelUtils::julianDayToISO8601String(jd + core->getUTCOffset(jd) / 24.0) : QString();
			};

			QJsonArray transits;
			const QList<QPair<QString, QPair<double, double>>> candidates = {
				qMakePair(QStringLiteral("Mercury"), qMakePair(2451612.023, 115.8774771)),
				qMakePair(QStringLiteral("Venus"), qMakePair(2451996.706, 583.921361))
			};
			for (const QPair<QString, QPair<double, double>>& candidate : candidates)
			{
				PlanetP object = ssys->searchByEnglishName(candidate.first);
				if (!object) continue;
				const double referenceJD = candidate.second.first;
				const double synodicPeriod = candidate.second.second;
				const int firstIndex = static_cast<int>(std::floor((startJD - referenceJD) / synodicPeriod)) - 1;
				const int conjunctions = static_cast<int>(std::ceil((stopJD - startJD) / synodicPeriod)) + 3;
				for (int index = 0; index < conjunctions; ++index)
				{
					double jd = referenceJD + (firstIndex + index) * synodicPeriod;
					if (jd < startJD - 2.0 || jd > stopJD + 2.0) continue;
					double deltaHours = 1.0;
					for (int iteration = 0; iteration < 20 && std::fabs(deltaHours) > 0.1 / 86400.0; ++iteration)
					{
						core->setUseTopocentricCoordinates(false);
						core->setJD(jd);
						core->update(0);
						const TransitElements current = computeElements(object);
						core->setJD(jd - 5.0 / 1440.0);
						core->update(0);
						const TransitElements before = computeElements(object);
						core->setJD(jd + 5.0 / 1440.0);
						core->update(0);
						const TransitElements after = computeElements(object);
						const double xdot = (after.x - before.x) * 6.0;
						const double ydot = (after.y - before.y) * 6.0;
						const double rateSquared = xdot * xdot + ydot * ydot;
						deltaHours = -(current.x * xdot + current.y * ydot) / rateSquared;
						jd += deltaHours / 24.0;
					}
					core->setJD(jd);
					core->update(0);
					const TransitElements geocentric = computeElements(object);
					if (std::sqrt(geocentric.x * geocentric.x + geocentric.y * geocentric.y) > 0.9972 + geocentric.L1 || jd < startJD || jd > stopJD)
						continue;

					const QPair<double, LocalTransitParams> middle = refineLocalTransit(jd, 0, false, object);
					if (middle.second.magnitude <= 0.0) continue;
					const QPair<double, LocalTransitParams> first = refineLocalTransit(middle.first, -1, false, object);
					const QPair<double, LocalTransitParams> last = refineLocalTransit(middle.first, 1, false, object);
					const double firstJD = std::min(first.first, last.first);
					const double lastJD = std::max(first.first, last.first);
					const QPair<double, LocalTransitParams> second = refineLocalTransit(middle.first, -1, true, object);
					const QPair<double, LocalTransitParams> third = refineLocalTransit(middle.first, 1, true, object);
					const bool hasInteriorContacts = second.second.ce > 0.0 && third.second.ce > 0.0;
					const double visibleMinutes = localVisibilityMinutes(firstJD, lastJD, object);

					core->setUseTopocentricCoordinates(true);
					core->setJD(middle.first);
					core->update(0);
					double azimuth = 0.0;
					double altitude = 0.0;
					StelUtils::rectToSphe(&azimuth, &altitude, object->getAltAzPosAuto(core));
					const double minimumSeparation = object->getElongation(core->getObserverHeliocentricEclipticPos()) * M_180_PI;
					QJsonObject item;
					item["planet"] = candidate.first == QStringLiteral("Mercury") ? QStringLiteral("水星") : QStringLiteral("金星");
					item["jd"] = middle.first;
					item["date"] = formatLocal(middle.first);
					item["firstContact"] = formatLocal(firstJD);
					item["middle"] = formatLocal(middle.first);
					item["lastContact"] = formatLocal(lastJD);
					item["firstContactVisible"] = first.second.altitude >= -0.3;
					item["middleVisible"] = altitude * M_180_PI >= -0.3;
					item["lastContactVisible"] = last.second.altitude >= -0.3;
					item["magnitude"] = middle.second.magnitude;
					item["minimumSeparation"] = minimumSeparation;
					item["durationMin"] = (lastJD - firstJD) * 1440.0;
					item["observableDurationMin"] = visibleMinutes;
					item["localVisible"] = visibleMinutes > 0.0;
					item["sunAltitude"] = altitude * M_180_PI;
					if (hasInteriorContacts)
					{
						item["secondContact"] = formatLocal(std::min(second.first, third.first));
						item["thirdContact"] = formatLocal(std::max(second.first, third.first));
						item["secondContactVisible"] = second.second.altitude >= -0.3;
						item["thirdContactVisible"] = third.second.altitude >= -0.3;
					}
					transits.append(item);
				}
			}
			core->setJD(originalJD);
			core->setUseTopocentricCoordinates(originalTopocentric);
			core->update(0);
			result["ok"] = true;
			result["planetaryTransits"] = transits;
			return result;
		}

		// getEclipses — 未来若干个月内的日食与月食预报
		if (commandName == "getEclipses")
		{
			struct LocalSolarEclipseParams
			{
				double dt = 0.0;
				double L2 = 0.0;
				double ce = 0.0;
				double magnitude = 0.0;
				double altitude = 0.0;
			};

			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject jo = doc.isObject() ? doc.object() : QJsonObject();
			double startJD = jo.value("jd").toDouble(0.0);
			const int months = qBound(1, jo.value("months").toInt(36), 60);
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			if (startJD <= 0) startJD = core->getJD();
			const double origJD = core->getJD();
			QJsonArray items;
			QList<QJsonObject> eclipseList;
			PlanetP sun = ssys->getSun();
			PlanetP moon = ssys->getMoon();
			if (!sun || !moon)
			{
				result["ok"] = false;
				result["error"] = "Sun or Moon unavailable";
				return result;
			}

			auto phaseDistance = [&](double jd, double target) -> double {
				core->setJD(jd);
				core->update(0);
				Vec3d sv = sun->getEquinoxEquatorialPos(core); sv.normalize();
				Vec3d mv = moon->getEquinoxEquatorialPos(core); mv.normalize();
				double c = qBound(-1.0, sv.dot(mv), 1.0);
				const double elongation = std::acos(c) * 180.0 / M_PI;
				return target == 0.0 ? elongation : std::fabs(180.0 - elongation);
			};

			// New and full moon estimates are stable enough to bracket with +/- 1.5 days.
			// Ternary refinement needs only 24 core updates per lunation and remains smooth on API 22.
			auto refinePhase = [&](double estimate, double target) -> double {
				double left = estimate - 1.5;
				double right = estimate + 1.5;
				for (int i = 0; i < 12; ++i)
				{
					const double third = (right - left) / 3.0;
					const double first = left + third;
					const double second = right - third;
					if (phaseDistance(first, target) < phaseDistance(second, target))
						right = second;
					else
						left = first;
				}
				const double resultJD = (left + right) / 2.0;
				phaseDistance(resultJD, target);
				return resultJD;
			};

			auto localSolarEclipse = [&](double jd, int contact, bool central) -> LocalSolarEclipseParams {
				const StelLocation& location = core->getCurrentLocation();
				PlanetP earth = ssys->getEarth();
				const Vec4d geocentricCoords = earth->getRectangularCoordinates(
					static_cast<double>(location.getLongitude()), static_cast<double>(location.getLatitude()),
					static_cast<double>(location.altitude));
				const double earthRadius = earth->getEquatorialRadius();
				const double rc = geocentricCoords[0] / earthRadius;
				const double rs = geocentricCoords[1] / earthRadius;

				core->setUseTopocentricCoordinates(false);
				core->setJD(jd);
				core->update(0);
				const EclipseBesselParameters bp = calcBesselParameters(true);
				const double theta = StelUtils::fmodpos((bp.elems.mu + location.getLongitude()) * M_PI_180, 2.0 * M_PI);
				const double xi = rc * std::sin(theta);
				const double eta = rs * std::cos(bp.elems.d) - rc * std::sin(bp.elems.d) * std::cos(theta);
				const double zeta = rs * std::sin(bp.elems.d) + rc * std::cos(bp.elems.d) * std::cos(theta);
				const double xidot = bp.mudot * rc * std::cos(theta);
				const double etadot = bp.mudot * xi * std::sin(bp.elems.d) - zeta * bp.ddot;
				const double u = bp.elems.x - xi;
				const double v = bp.elems.y - eta;
				const double udot = bp.xdot - xidot;
				const double vdot = bp.ydot - etadot;
				const double rateSquared = udot * udot + vdot * vdot;
				const double delta = (u * vdot - udot * v) / std::sqrt(rateSquared);
				const double L1 = bp.elems.L1 - zeta * bp.elems.tf1;
				const double L2 = bp.elems.L2 - zeta * bp.elems.tf2;
				const double L = central ? L2 : L1;
				const double ce = 1.0 - (delta / L) * (delta / L);
				const double contactFactor = ce > 0.0 ? contact * std::sqrt(ce) : 0.0;
				LocalSolarEclipseParams local;
				local.dt = (L * contactFactor / std::sqrt(rateSquared)) - (u * udot + v * vdot) / rateSquared;
				local.L2 = L2;
				local.ce = ce;
				local.magnitude = (L1 - std::sqrt(u * u + v * v)) / (L1 + L2);
				local.altitude = std::asin(rc * std::cos(bp.elems.d) * std::cos(theta) + rs * std::sin(bp.elems.d)) * M_180_PI;
				return local;
			};

			auto refineLocalContact = [&](double jd, int contact, bool central) -> QPair<double, LocalSolarEclipseParams> {
				LocalSolarEclipseParams local;
				for (int iteration = 0; iteration < 20; ++iteration)
				{
					local = localSolarEclipse(jd, contact, central);
					jd += local.dt / 24.0;
					if (std::fabs(local.dt) <= 0.000001)
						break;
				}
				local = localSolarEclipse(jd, contact, central);
				return qMakePair(jd, local);
			};

			auto visibleSolarEclipseWindow = [&](double firstJD, double lastJD) -> QPair<double, double> {
				QList<double> boundaries;
				boundaries.append(firstJD);
				constexpr int samples = 18;
				double previousJD = firstJD;
				double previousAltitude = localSolarEclipse(previousJD, 0, false).altitude + 0.3;
				for (int sample = 1; sample <= samples; ++sample)
				{
					const double currentJD = firstJD + (lastJD - firstJD) * sample / samples;
					const double currentAltitude = localSolarEclipse(currentJD, 0, false).altitude + 0.3;
					if ((previousAltitude < 0.0 && currentAltitude > 0.0)
						|| (previousAltitude > 0.0 && currentAltitude < 0.0))
					{
						double left = previousJD;
						double right = currentJD;
						double leftAltitude = previousAltitude;
						for (int iteration = 0; iteration < 18; ++iteration)
						{
							const double middle = (left + right) / 2.0;
							const double middleAltitude = localSolarEclipse(middle, 0, false).altitude + 0.3;
							if ((leftAltitude <= 0.0 && middleAltitude <= 0.0)
								|| (leftAltitude >= 0.0 && middleAltitude >= 0.0))
							{
								left = middle;
								leftAltitude = middleAltitude;
							}
							else
								right = middle;
						}
						boundaries.append((left + right) / 2.0);
					}
					previousJD = currentJD;
					previousAltitude = currentAltitude;
				}
				boundaries.append(lastJD);
				std::sort(boundaries.begin(), boundaries.end());
				for (int index = 0; index + 1 < boundaries.size(); ++index)
				{
					const double begin = boundaries.at(index);
					const double end = boundaries.at(index + 1);
					if (localSolarEclipse((begin + end) / 2.0, 0, false).altitude >= -0.3)
						return qMakePair(begin, end);
				}
				return qMakePair(0.0, 0.0);
			};

			const double limitJD = startJD + months * 30.436875;
			constexpr double synodicMonth = 29.530588853;
			constexpr double referenceNewMoon = 2451550.09765;
			const int firstLunation = static_cast<int>(std::floor((startJD - referenceNewMoon) / synodicMonth)) - 1;
			const int lunations = static_cast<int>(std::ceil((limitJD - startJD) / synodicMonth)) + 3;
			const bool originalTopocentric = core->getUseTopocentricCoordinates();
			SolarEclipseComputer eclipseComputer(core, &StelApp::getInstance().getLocaleMgr());
			for (int i = 0; i < lunations; ++i)
			{
				const double estimate = referenceNewMoon + (firstLunation + i) * synodicMonth;
				// The instant of geocentric conjunction is close to, but not necessarily
				// identical with, greatest eclipse. Use the native Besselian iteration so
				// central duration and path data are evaluated at the correct instant.
				const double newMoonJD = eclipseComputer.getJDofMinimumDistance(refinePhase(estimate, 0.0));
				if (newMoonJD >= startJD && newMoonJD <= limitJD)
				{
					double dRatio, latDeg, lngDeg, altitude, pathWidth, duration, magnitude;
					core->setJD(newMoonJD);
					core->update(0);
					calcSolarEclipseData(newMoonJD, dRatio, latDeg, lngDeg, altitude, pathWidth, duration, magnitude);
					if (magnitude > 0.0)
					{
						QString type = QStringLiteral("偏食");
						// calcSolarEclipseData returns a signed central duration: negative is total,
						// positive is annular. Avoid generateEclipseMap(), which creates a full
						// worldwide path and is unnecessarily expensive for a compact event list.
						if (duration < 0.0) type = QStringLiteral("全食");
						else if (duration > 0.0) type = QStringLiteral("环食");
						else if (magnitude >= 1.0) type = QStringLiteral("中心食");
						QJsonObject ev;
						ev["kind"] = "solar";
						ev["type"] = type;
						ev["jd"] = newMoonJD;
						ev["date"] = StelUtils::julianDayToISO8601String(newMoonJD + core->getUTCOffset(newMoonJD) / 24.0);
						ev["magnitude"] = magnitude;
						ev["pathWidthKm"] = pathWidth;
						const auto eclipseBessel = calcSolarEclipseBessel();
						double gamma = std::sqrt(eclipseBessel.x * eclipseBessel.x + eclipseBessel.y * eclipseBessel.y);
						if (eclipseBessel.y < 0.0) gamma = -gamma;
						ev["gamma"] = gamma;
						const double brownLunation = std::round((newMoonJD - 2423436.40347) / 29.530588);
						const int lunarNumber = static_cast<int>(brownLunation) + 1 - 953;
						const int nodeNumber = lunarNumber + 105;
						const int sarosSeed = 136 + 38 * nodeNumber;
						const int nodeShift = -61 * nodeNumber;
						const int sarosCorrection = qFloor(nodeShift / 358.0 + 0.5 - nodeNumber / (12.0 * 358.0 * 358.0));
						int saros = 1 + ((sarosSeed + sarosCorrection * 223 - 1) % 223);
						if (sarosSeed + sarosCorrection * 223 - 1 < 0) saros -= 223;
						if (saros < -223) saros += 223;
						ev["saros"] = saros;
						// calcSolarEclipseData() already returns the central duration in minutes.
						ev["durationMin"] = duration;
						ev["centralLat"] = latDeg;
						ev["centralLng"] = lngDeg;

						const QPair<double, LocalSolarEclipseParams> localMaximum = refineLocalContact(newMoonJD, 0, false);
						const LocalSolarEclipseParams localMaxParams = localMaximum.second;
						if (localMaxParams.magnitude > 0.0 && localMaxParams.ce > 0.0)
						{
							const QPair<double, LocalSolarEclipseParams> localFirst = refineLocalContact(localMaximum.first, -1, false);
							const QPair<double, LocalSolarEclipseParams> localLast = refineLocalContact(localMaximum.first, 1, false);
							const double geometricFirst = std::min(localFirst.first, localLast.first);
							const double geometricLast = std::max(localFirst.first, localLast.first);
							const QPair<double, double> visibleWindow = visibleSolarEclipseWindow(geometricFirst, geometricLast);
							const bool locallyVisible = visibleWindow.first > 0.0 && visibleWindow.second > visibleWindow.first;
							ev["localVisible"] = locallyVisible;
							if (locallyVisible)
							{
								const double visibleMaximumJD = qBound(visibleWindow.first, localMaximum.first, visibleWindow.second);
								const LocalSolarEclipseParams visibleMaximum = localSolarEclipse(visibleMaximumJD, 0, false);
								ev["localMagnitude"] = visibleMaximum.magnitude;
								ev["localMax"] = StelUtils::julianDayToISO8601String(visibleMaximumJD + core->getUTCOffset(visibleMaximumJD) / 24.0);
								ev["localSunAltitude"] = visibleMaximum.altitude;
								ev["localFirstContact"] = StelUtils::julianDayToISO8601String(visibleWindow.first + core->getUTCOffset(visibleWindow.first) / 24.0);
								ev["localLastContact"] = StelUtils::julianDayToISO8601String(visibleWindow.second + core->getUTCOffset(visibleWindow.second) / 24.0);
								ev["localFirstContactLabel"] = visibleWindow.first > geometricFirst + 1.0 / 1440.0 ? QStringLiteral("日出") : QStringLiteral("初亏");
								ev["localLastContactLabel"] = visibleWindow.second < geometricLast - 1.0 / 1440.0 ? QStringLiteral("日落") : QStringLiteral("复圆");

								const QPair<double, LocalSolarEclipseParams> centralFirst = refineLocalContact(localMaximum.first, -1, true);
								const QPair<double, LocalSolarEclipseParams> centralLast = refineLocalContact(localMaximum.first, 1, true);
								if (centralFirst.second.ce > 0.0 && centralLast.second.ce > 0.0)
								{
									const double centralStart = std::max(std::min(centralFirst.first, centralLast.first), visibleWindow.first);
									const double centralEnd = std::min(std::max(centralFirst.first, centralLast.first), visibleWindow.second);
									if (centralEnd > centralStart)
									{
										ev["localCentralType"] = localMaxParams.L2 < 0.0 ? QStringLiteral("全食") : QStringLiteral("环食");
										ev["localCentralStart"] = StelUtils::julianDayToISO8601String(centralStart + core->getUTCOffset(centralStart) / 24.0);
										ev["localCentralEnd"] = StelUtils::julianDayToISO8601String(centralEnd + core->getUTCOffset(centralEnd) / 24.0);
									}
								}
							}
						}
						else
						{
							ev["localVisible"] = false;
						}
						eclipseList.append(ev);
					}
				}

				const double fullMoonJD = refinePhase(estimate + synodicMonth * 0.5, 180.0);
				if (fullMoonJD >= startJD && fullMoonJD <= limitJD)
				{
					core->setJD(fullMoonJD);
					core->update(0);
					const QVariantMap moonInfo = moon->getInfoMap(core);
					const double penumbralMagnitude = moonInfo.value("penumbral-eclipse-magnitude", 0.0).toDouble();
					const double umbralMagnitude = moonInfo.value("umbral-eclipse-magnitude", 0.0).toDouble();
					if (penumbralMagnitude > 0.0)
					{
						QString type = QStringLiteral("半影食");
						if (umbralMagnitude >= 1.0) type = QStringLiteral("全食");
						else if (umbralMagnitude > 0.0) type = QStringLiteral("偏食");
						double azimuth = 0.0;
						double altitudeRad = 0.0;
						StelUtils::rectToSphe(&azimuth, &altitudeRad, moon->getAltAzPosAuto(core));
						const double altitudeDeg = altitudeRad * 180.0 / M_PI;
						const bool topocentricBeforeGamma = core->getUseTopocentricCoordinates();
						core->setUseTopocentricCoordinates(false);
						core->update(0);
						double sunRa = 0.0;
						double sunDec = 0.0;
						double moonRa = 0.0;
						double moonDec = 0.0;
						StelUtils::rectToSphe(&sunRa, &sunDec, sun->getEquinoxEquatorialPos(core));
						StelUtils::rectToSphe(&moonRa, &moonDec, moon->getEquinoxEquatorialPos(core));
						const double shadowRa = StelUtils::fmodpos(sunRa + M_PI, 2.0 * M_PI);
						const double shadowDec = -sunDec;
						const double raDifference = StelUtils::fmodpos(moonRa - shadowRa, 2.0 * M_PI);
						const double besselX = std::cos(moonDec) * std::sin(raDifference) * 3600.0 * M_180_PI;
						const double besselY = (std::cos(shadowDec) * std::sin(moonDec)
							- std::sin(shadowDec) * std::cos(moonDec) * std::cos(raDifference)) * 3600.0 * M_180_PI;
						const double moonDistance = moon->getEclipticPos().norm();
						const double moonSemidiameter = std::atan(moon->getEquatorialRadius() / moonDistance) * M_180_PI * 3600.0;
						double gamma = std::sqrt(besselX * besselX + besselY * besselY) * 0.2725076 / moonSemidiameter;
						if (besselY < 0.0) gamma = -gamma;
						core->setUseTopocentricCoordinates(topocentricBeforeGamma);
						core->update(0);
						const double brownLunation = std::round((fullMoonJD - 2423436.40347) / 29.530588 - 0.25);
						const int lunarNumber = static_cast<int>(brownLunation) + 1 - 953;
						const int nodeNumber = lunarNumber + 105;
						const int sarosSeed = 148 + 38 * nodeNumber;
						const int nodeShift = -61 * nodeNumber;
						const int sarosCorrection = qFloor(nodeShift / 358.0 + 0.5 - nodeNumber / (12.0 * 358.0 * 358.0));
						int saros = 1 + ((sarosSeed + sarosCorrection * 223 - 1) % 223);
						if (sarosSeed + sarosCorrection * 223 - 1 < 0) saros -= 223;
						if (saros < -223) saros += 223;
						QString visibility = QStringLiteral("不可见");
						if (altitudeDeg >= 45.0) visibility = QStringLiteral("观测条件极佳");
						else if (altitudeDeg >= 30.0) visibility = QStringLiteral("观测条件良好");
						else if (altitudeDeg >= 0.0) visibility = QStringLiteral("月亮较低");
						if (umbralMagnitude < 1.0 && penumbralMagnitude < 0.7) visibility = QStringLiteral("不易肉眼观测");
						QJsonObject ev;
						ev["kind"] = "lunar";
						ev["type"] = type;
						ev["jd"] = fullMoonJD;
						ev["date"] = StelUtils::julianDayToISO8601String(fullMoonJD + core->getUTCOffset(fullMoonJD) / 24.0);
						ev["magnitude"] = umbralMagnitude > 0.0 ? umbralMagnitude : penumbralMagnitude;
						ev["saros"] = saros;
						ev["gamma"] = gamma;
						ev["penumbralMagnitude"] = penumbralMagnitude;
						ev["umbralMagnitude"] = umbralMagnitude;
						ev["localMoonAltitude"] = altitudeDeg;
						ev["visibility"] = visibility;
						eclipseList.append(ev);
					}
				}
			}
			core->setJD(origJD);
			core->setUseTopocentricCoordinates(originalTopocentric);
			core->update(0);
			// QJsonArray 的迭代器不支持 std::sort，先在 QList 上按时间排好再装回去
			std::sort(eclipseList.begin(), eclipseList.end(), [](const QJsonObject& x, const QJsonObject& y) {
				return x.value("jd").toDouble() < y.value("jd").toDouble();
			});
			for (const QJsonObject& ev : eclipseList)
				items.append(ev);
			result["ok"] = true;
			result["eclipses"] = items;
			return result;
		}

		result["error"] = "unknown command";
		result["command"] = commandName;
		return result;
	});

	response = json.toUtf8();
	return response.constData();
}
} // anonymous namespace (OHOS helpers + command bridge)
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

#if defined(__OHOS__)
		if (s_ohosRenderPumpActive)
		{
			const quint64 skipped = s_ohosSkippedGraphicsPaints.fetch_add(1) + 1;
			if ((skipped % 120) == 1)
				qInfo() << "[StellariumOhos][render] skipped graphics paint while native pump owns frame" << skipped;
			return;
		}
#endif

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
			if (!s_ohosRenderPumpActive)
				submitOhosFramebuffer(QOpenGLContext::currentContext()->functions());
#endif
		painter->endNativePainting();

		mainView->ohosDrawEnded();
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
		qInfo() << " - Non power of two textures" << ((oglFeatures&QOpenGLFunctions::NPOTTextureRepeat) ? "can" : "CANNOT") << "use GL_REPEAT as wrap argeter.";
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
	if (!s_ohosApplicationForeground.load())
		return;
	s_ohosRenderPumpActive = true;
	markQtLoopRunning();
	updateQueued = false;
	fpsTimer->setInterval(currentOhosRenderIntervalMs());
	renderOhosFrameNow();
	fpsTimer->start();
	qWarning() << "Started OpenHarmony render pump.";
}

void StelMainView::setOhosApplicationForeground(bool foreground)
{
	s_ohosApplicationForeground.store(foreground);
	if (!fpsTimer)
		return;

	if (!foreground)
	{
		// The app has no background task. Stop every continuous render activity
		// while retaining the OpenGL scene so returning to the foreground is fast.
		fpsTimer->stop();
		s_ohosRenderFps.store(0.0f);
		s_ohosPanInertiaActive = false;
		s_gyroTransitionActive = false;
		if (g_videoRecorder.timer)
			g_videoRecorder.timer->stop();
		ohosMark("OpenHarmony rendering paused in background");
		return;
	}

	lastOhosRenderTimeSec = 0.0;
	startOhosRenderPump();
	requestOhosSceneRepaint();
	ohosMark("OpenHarmony rendering resumed in foreground");
}

void StelMainView::setOhosScriptRenderHeartbeat(bool active)
{
	const bool wasActive = s_ohosScriptRenderHeartbeat.exchange(active);
	if (wasActive == active)
		return;
	if (fpsTimer)
	{
		if (active)
		{
			fpsTimer->stop();
			qInfo() << "[StellariumOhos][render] script heartbeat owns frame timer";
		}
		else if (s_ohosApplicationForeground.load())
		{
			fpsTimer->setInterval(currentOhosRenderIntervalMs());
			fpsTimer->start();
			qInfo() << "[StellariumOhos][render] normal frame timer restored after script";
		}
	}
}

void StelMainView::renderOhosFrameNow()
{
	if (!s_ohosApplicationForeground.load())
		return;
	const double t0 = StelApp::getTotalRunTime();
	ohosDrainCommandQueue();
	ohosUpdateLandscapeFadeWithZoom();
	const double t1 = StelApp::getTotalRunTime();
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
	// The presentation bridge is responsible for transport, not quality. Keep
	// Qt rendering at the device pixel size for both zero-copy and fallback.
	const int width = qMax(1, int(glWidget->width() * pixelRatio));
	const int height = qMax(1, int(glWidget->height() * pixelRatio));

	StelApp& app = StelApp::getInstance();
	app.setDevicePixelsPerPixel(devicePixelRatioF());
	gl->glBindFramebuffer(GL_FRAMEBUFFER, glWidget->defaultFramebufferObject());
	gl->glViewport(0, 0, width, height);

	const double t2 = StelApp::getTotalRunTime();
	ohosUpdatePointTracking();
	ohosUpdateGyroTransition();
		ohosUpdatePanInertia(dt);
		if (s_ohosCaptureSelectedAnchorAfterPan)
		{
			s_ohosCaptureSelectedAnchorAfterPan = false;
			ohosCaptureSelectedZoomAnchor();
		}
		// Capture the user's post-drag screen position before simulation time
		// advances. The maintainer below then compensates this very frame instead
		// of anchoring one time-step late and visibly drifting after release.
		app.update(dt);
		if (s_ohosPinchActive && s_ohosPinchAnchorMode == OhosPinchAnchorMode::SkyPoint)
			ohosMaintainPinchSkyAnchor();
		else
			ohosMaintainSelectedZoomAnchor();
		ohosUpdateSelectedScreenProjection();
	ohosProcessPendingPointSelect();
	const double t3 = StelApp::getTotalRunTime();
	app.draw();
	const double t4 = StelApp::getTotalRunTime();
	submitOhosFramebuffer(gl);
	const double t5 = StelApp::getTotalRunTime();

	const int intervalMs = currentOhosRenderIntervalMs();
	const bool maxFps = needsMaxFPS();
	static int s_frameCounter = 0;
	if ((s_frameCounter++ % 30) == 0)
	{
		const double cmdMs = (t1 - t0) * 1000.0;
		const double setupMs = (t2 - t1) * 1000.0;
		const double updateMs = (t3 - t2) * 1000.0;
		const double drawMs = (t4 - t3) * 1000.0;
		const double submitMs = (t5 - t4) * 1000.0;
		const double totalMs = (t5 - t0) * 1000.0;
		OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "StellariumFps",
			"frame: total=%{public}.1fms cmd=%{public}.1fms setup=%{public}.1fms update=%{public}.1fms draw=%{public}.1fms submit=%{public}.1fms interval=%{public}dms maxFps=%{public}d fps=%{public}.1f",
			totalMs, cmdMs, setupMs, updateMs, drawMs, submitMs, intervalMs, maxFps ? 1 : 0,
			static_cast<double>(app.getFps()));
	}

	// Update lock-free FPS counter every frame for getFPS command.
	// Compute from actual frame time delta for accuracy.
#if defined(__OHOS__)
	if (dt > 0.001 && dt < 0.25)
		s_ohosRenderFps.store(1.0f / static_cast<float>(dt));
#endif
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
	#if defined(__OHOS__)
	// Recents uses the Qt window title instead of the ArkTS label.
	setWindowTitle(QStringLiteral("星象仪"));
	#else
	setWindowTitle(StelUtils::getApplicationName());
	#endif
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
	if (s_ohosScriptRenderHeartbeat.load())
		return;
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
	const int interactiveInterval = currentOhosRenderIntervalMs();
	if (fpsTimer && fpsTimer->interval() != interactiveInterval)
		fpsTimer->setInterval(interactiveInterval);
	// Update lock-free FPS counter for getFPS command
	s_ohosRenderFps.store(StelApp::getInstance().getFps());
#endif
}

bool StelMainView::needsMaxFPS() const
{
	const double now = StelApp::getTotalRunTime();

	// Determines when the next display will need to be triggered
	// The desktop policy keeps maximum FPS for several seconds after an event.
	// On HarmonyOS each frame crosses the GPU/CPU bridge, so returning to the
	// lower idle cadence promptly avoids wasting work after a drag or pinch ends.
	// after that, it switches back to the default minfps value to save power.
	// The fps is also kept to max if the timerate is higher than normal speed.
	const double timeRate = stelApp->getCore()->getTimeRate();
#if defined(__OHOS__)
	return (now - lastEventTimeSec < 0.8) || fabs(timeRate) > StelCore::JD_SECOND;
#else
	return (now - lastEventTimeSec < 4.0) || fabs(timeRate) > StelCore::JD_SECOND;
#endif
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
