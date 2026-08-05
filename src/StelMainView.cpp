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
#include "SporadicMeteorMgr.hpp"
#include "../plugins/Oculars/src/Oculars.hpp"
#include "../plugins/Satellites/src/Satellites.hpp"
#include "../plugins/MeteorShowers/src/MeteorShowersMgr.hpp"
#include "../plugins/MeteorShowers/src/MeteorShower.hpp"
#include "../plugins/MeteorShowers/src/MeteorShowers.hpp"
#include "StelScriptMgr.hpp"
#include "SolarSystem.hpp"
#include "ConstellationMgr.hpp"
#include "StelLocationMgr.hpp"
#include "StarMgr.hpp"
#include "GridLinesMgr.hpp"
#include "MilkyWay.hpp"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QFile>

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
constexpr int OHOS_FALLBACK_INTERACTIVE_RENDER_INTERVAL_MS = 20;  // 50 FPS while CPU-copying frames.
constexpr int OHOS_IDLE_RENDER_INTERVAL_MS = 33;        // 30 FPS once the scene settles.

// Once the dedicated render pump is running it owns presentation to the
// XComponent. The QGraphics paint path can still be entered by Qt, but must
// not submit a duplicate framebuffer to the native surface.
static bool s_ohosRenderPumpActive = false;
static bool s_ohosZeroCopyActive = false;
static bool s_ohosZeroCopySupported = true;

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

// Render resolution scale factor (0.0-1.0). Reduces the framebuffer resolution
// to cut down glReadPixels + glTexImage2D data size. The XComponent upscales
// the texture to full screen automatically.
// 65% keeps labels readable while avoiding a full-resolution CPU readback.
// The shared-texture path below always renders at native resolution.
constexpr double OHOS_RENDER_SCALE = 0.65;

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
	const double readbackScale = (s_ohosZeroCopyActive || tryZeroCopy)
		? 1.0
		: (StelMainView::getInstance().needsMaxFPS() ? 0.50 : 0.65);
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

// Cross-thread command queue drained by the OHOS render pump
// (renderOhosFrameNow) on the Qt main thread every frame. OHOS Qt may
// drive rendering via a native vsync callback rather than the Qt event
// loop, so QMetaObject::invokeMethod(..., QueuedConnection) is not
// guaranteed to be pumped; we hand commands to the pump instead.
static QMutex s_ohosCmdQueueMutex;
static QList<std::function<void()>> s_ohosCmdQueue;
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
// --- Manual view-control modes (OHOS bridge) -------------------------------
// s_viewLock ("锁定视角"): when ON, ALL manual panning (dragView / panBy) is
// ignored — the view direction is frozen — but pinch zoom (zoomBy / zoomStep)
// keeps working. Toggled any time from the ArkTS panel.
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
static double s_ohosPanInertiaVx = 0.0; // viewport pixels per millisecond
static double s_ohosPanInertiaVy = 0.0;
static double s_ohosPanInertiaElapsedSec = 0.0;

static void ohosApplyPanDelta(StelCore* core, double dx, double dy)
{
	if (!core || s_viewLock)
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
	movementMgr->setFlagTracking(false);
}

static void ohosUpdatePanInertia(double dtSec)
{
	if (!s_ohosPanInertiaActive || s_viewLock)
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
		if (cmdName == "zoomBy" || cmdName == "zoomStep" || cmdName == "dragView" || cmdName == "panBy" || cmdName == "moveToAltAz" || cmdName == "gyroDiagnostic" || cmdName == "startPanInertia" || cmdName == "stopPanInertia")
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

// Complete object prose is expensive to generate. Initial selections need it for
// the detail sheet, but the 300ms live refresh only needs the changing values.
QJsonObject selectedObjectJson(StelCore* core = nullptr, bool includeFullInfo = true)
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

		// Plain-text summary info
		const QString info = object->getInfoString(core, StelObject::ShortInfo |
			StelObject::Magnitude | StelObject::AltAzi | StelObject::Distance |
			StelObject::Size | StelObject::PlainText).simplified();
		if (!info.isEmpty())
			result["info"] = info;
		if (includeFullInfo)
		{
			const QString fullInfo = object->getInfoString(core, StelObject::AllInfo | StelObject::PlainText).simplified();
			if (!fullInfo.isEmpty())
				result["fullInfo"] = fullInfo;
		}
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

		if (SporadicMeteorMgr* mmgr = GETSTELMODULE(SporadicMeteorMgr))
			result["meteors"] = mmgr->getFlagShow();
		if (NebulaMgr* nmgr = GETSTELMODULE(NebulaMgr))
			result["dsoLabels"] = nmgr->getDesignationUsage();
		if (movementMgr)
			result["autoZoomResets"] = movementMgr->getFlagAutoZoomOutResetsDirection();

		return result;
	}
}

namespace {
// OHOS 星表下载器：把 ConfigurationDialog 里耦合 UI 的下载逻辑抽成不依赖界面的版本，
// 通过 N-API 命令桥触发；进度由 ArkTS 侧轮询 getStarCatalogStatus 获取（桥是请求-响应模式，无 C++→ArkTS 推送）。
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

	const QString json = runOhosCommandOnQtThread(commandName + "|" + arg, [commandName, arg]() -> QJsonObject {
		QJsonObject result;
		result["ok"] = false;
		if (commandName != "dragView" && commandName != "zoomBy" && commandName != "panBy" && commandName != "setGyroView" && commandName != "getGyroGuidePosition")
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
		g_starDownloader.start(arg);
		result["ok"] = true;
		result["started"] = true;
		result["id"] = arg;
		return result;
	}

	if (commandName == "getStarCatalogStatus")
	{
		result["ok"] = true;
		result["id"] = g_starDownloader.id;
		result["state"] = g_starDownloader.done ? (g_starDownloader.error ? QString("error") : QString("done")) : QString("downloading");
		result["bytes"] = (qint64)g_starDownloader.bytes;
		result["error"] = g_starDownloader.errorStr;
		result["md5ok"] = g_starDownloader.md5ok;
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
			bool found = false;
			if (query == QLatin1String("catalog") && searchParts.size() >= 3)
			{
				const QString moduleId = searchParts.value(1).trimmed();
				const QString objectId = searchParts.value(2).trimmed();
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
			else
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
					const StelObjectP constellation = constellationMgr->searchByName(query);
					if (constellation)
						found = objectMgr->setSelectedObject(constellation);
				}
			}
			if (found && !selectOnly && movementMgr && !objectMgr->getSelectedObject().isEmpty())
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

				// Transit zoom: pull back slightly during pan so user sees approach
				const double currentFov = movementMgr->getCurrentFov();
				const double transitFov = std::max(targetFov * 3.0, std::max(currentFov, 12.0));
				const quint64 serial = ++s_ohosNavigationSerial;
				movementMgr->setFlagTracking(false);
				if (currentFov + 0.5 < transitFov)
					movementMgr->zoomTo(transitFov, 0.40f);
				QTimer::singleShot(520, &StelMainView::getInstance(), [movementMgr, targetFov, serial]() {
					if (serial == s_ohosNavigationSerial.load())
						movementMgr->zoomTo(targetFov, 0.85f);
				});
				qInfo() << "[StellariumOhos][navigate]" << target->getEnglishName()
						<< "type=" << type << "fov" << currentFov << "->" << targetFov;
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
		const auto list = objectMgr->listMatchingObjects(prefix, maxItems, true);
		QJsonArray items;
		QJsonArray keys;
		for (const auto& pair : list)
		{
			items.append(pair.first);
			// pair.first is a localized display label. Keep it for the UI, but
			// return the object's stable English name for the follow-up selection.
			const QString key = pair.second ? pair.second->getEnglishName() : QString();
			keys.append(key.isEmpty() ? pair.first : key);
		}
		result["ok"] = true; result["items"] = items; result["keys"] = keys;
		result["count"] = items.size(); result["prefix"] = prefix;
		return result;
	}

	if (commandName == "listObjects")
	{
		if (!objectMgr) { result["error"] = "object manager not found"; return result; }
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
		const auto list = objectMgr->listAllModuleObjects(moduleId, inEnglish);
		QJsonArray items;
		QJsonArray keys;
		QSet<QString> seenIds;
		int uniqueCount = 0;
		for (const auto& pair : list)
		{
			const StelObjectP object = pair.second;
			const QString id = object ? object->getID() : pair.first;
			if (id.isEmpty() || seenIds.contains(id))
				continue;
			seenIds.insert(id);
			if (uniqueCount >= offset && items.size() < maxItems)
			{
				QString displayName = object ? object->getNameI18n() : pair.first;
				if (displayName.isEmpty())
					displayName = pair.first;
				items.append(displayName);
				keys.append(id);
			}
			++uniqueCount;
		}
		result["ok"] = true; result["items"] = items; result["keys"] = keys;
		result["count"] = uniqueCount; result["hasMore"] = offset + items.size() < uniqueCount;
		result["offset"] = offset; result["moduleId"] = moduleId;
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
			if (s_viewLock)
			{
				// View locked: panning disabled (zoom still allowed elsewhere).
				result["ok"] = true;
				result["locked"] = true;
				return result;
			}
			ohosApplyPanDelta(core, x2 - x1, y2 - y1);
			markOhosInteraction();
			result["ok"] = true;
			result["fov"] = movementMgr->getCurrentFov();
			return result;
		}

		if (commandName == "startPanInertia")
		{
			const QStringList parts = arg.split('|');
			bool okX = false;
			bool okY = false;
			const double vx = parts.value(0).toDouble(&okX);
			const double vy = parts.value(1).toDouble(&okY);
			if (!okX || !okY || s_viewLock)
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
			if (s_viewLock)
			{
				result["ok"] = true;
				result["locked"] = true;
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
			return selectedObjectJson(core, arg.trimmed().toLower() == "full");

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
			// Horizontal viewport offsets translate the projected image directly,
			// which is ideal for a tablet's side panel. Stellarium deliberately
			// compensates its vertical offset while tracking an object, though, so
			// a phone's top card needs an explicit, animated vertical pan below.
			const StelObjectP selectedObject = objectMgr->getSelectedObject().constFirst();
			const double horizontalOffset = ((x / width) - 0.5) * 100.0;
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
		// arg: "<ra_hours>|<dec_degrees>" where ra is in hours (0-24) and dec in degrees (-90 to +90).
		// Recenters the view on that sky direction and selects the nearest object on the next frame.
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
		// runScript() reports failure (missing file, syntax error, already
		// running). Swallowing it made every failed tour look like a success.
			const bool started = smgr.runScript(arg);
			qInfo() << "[StellariumOhos][script] playScript started=" << started << "arg=" << arg;
			result["ok"] = started;
			if (!started) { result["error"] = "failed to run script: " + arg; }
			return result;
		}

		// stopScript
		if (commandName == "stopScript")
		{
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
			alm["currentJD"] = core->getJD();
			if (sun)
			{
				Vec4d srts = sun->getRTSTime(core);
				alm["sunNextRise"] = srts[0];
				alm["sunNextTransit"] = srts[1];
				alm["sunNextSet"] = srts[2];
			}
			if (moon)
			{
				Vec4d mrts = moon->getRTSTime(core);
				alm["moonNextRise"] = mrts[0];
				alm["moonNextTransit"] = mrts[1];
				alm["moonNextSet"] = mrts[2];
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
				PlanetP p = qSharedPointerCast<Planet>(ssys->searchByName(pn));
				if (!p) continue;
				QJsonObject obj;
				Vec3d eq = p->getEquinoxEquatorialPos(core);
				obj["name"] = p->getNameI18n();
				obj["englishName"] = p->getEnglishName();
				obj["ra"] = StelUtils::radToHmsStr(eq[0]/M_PI*12.0);
				obj["dec"] = StelUtils::radToDmsStr(eq[1]/M_PI*180.0);
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
			const QList<StelObjectP>& sel = StelApp::getInstance().getStelObjectMgr().getSelectedObject();
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

		// setTimeToJD — set simulation time to Julian Day
		if (commandName == "setTimeToJD")
		{
			double jd = arg.toDouble();
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
			result["jdOfToday"] = core->getJD();
			result["timeRate"] = core->getTimeRate();
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

		// getSkyCultureList — get available sky cultures
		if (commandName == "getSkyCultureList")
		{
			QStringList cultures = StelApp::getInstance().getSkyCultureMgr().getSkyCultureListIDs();
			QStringList displayNames = StelApp::getInstance().getSkyCultureMgr().getSkyCultureListEnglish();
			QJsonArray list;
			for (int i = 0; i < cultures.size(); i++) {
				QJsonObject item;
				item["id"] = cultures[i];
				item["name"] = (i < displayNames.size()) ? displayNames[i] : cultures[i];
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
			result["ok"] = true;
			return result;
		}

		if (commandName == "cancelGyroViewTransition")
		{
			s_gyroTransitionArmed = false;
			s_gyroTransitionActive = false;
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
			// 前一次升起/中天/落下：把时间回拨 1.5 天后重算（取回拨后首个事件，即本次之前最近的一次）
			{
				double origJD = core->getJD();
				core->setJD(origJD - 1.5);
				Vec4d prevRts = sel.first()->getRTSTime(core);
				core->setJD(origJD);
				result["prevRiseJD"] = prevRts[0];
				result["prevTransitJD"] = prevRts[1];
				result["prevSetJD"] = prevRts[2];
				if (prevRts[0] > 0) result["prevRise"] = StelUtils::julianDayToISO8601String(prevRts[0]);
				if (prevRts[1] > 0) result["prevTransit"] = StelUtils::julianDayToISO8601String(prevRts[1]);
				if (prevRts[2] > 0) result["prevSet"] = StelUtils::julianDayToISO8601String(prevRts[2]);
			}
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

		// getLocationList — search locations by name prefix
		if (commandName == "getLocationList")
		{
			QString prefix = arg.toLower();
			const StelLocationMgr& locMgr = StelApp::getInstance().getLocationMgr();
			QJsonArray list;
			int count = 0;
			for (const auto& loc : locMgr.getAll()) {
				if (loc.name.toLower().startsWith(prefix) || loc.name.toLower().startsWith(prefix)) {
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
			Satellites* sats = GETSTELMODULE(Satellites);
			if (!sats) { result["ok"] = false; result["error"] = "Satellites plugin not loaded"; return result; }
			QJsonObject s;
			QJsonArray groups;
			for (const QString& g : sats->getGroupIdList()) groups.append(g);
			s["groups"] = groups;
			s["labels"] = sats->getFlagLabelsVisible();
			s["orbitLines"] = sats->getFlagOrbitLines();
			s["hints"] = sats->getFlagHintsVisible();
			s["iconicMode"] = sats->getFlagIconicMode();
			s["hideInvisible"] = sats->getFlagHideInvisible();
			s["count"] = sats->listAllIds().size();
			result["ok"] = true;
			result["satellites"] = s;
			return result;
		}
		if (commandName == "setSatellitesFlag")
		{
			Satellites* sats = GETSTELMODULE(Satellites);
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
				sunObj["astroTwilightEnd"] = fmtLocal(astro[2]);
				sunObj["astroTwilightStart"] = fmtLocal(astro[0]);
				sunObj["astroTwilightEndJd"] = astro[2];
				if (astro[2] > 0 && astro[0] > astro[2])
					sunObj["darkWindowHours"] = (astro[0] - astro[2]) * 24.0;
				darkStartJd = astro[2];
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
			Satellites* sats = GETSTELMODULE(Satellites);
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
			// 包裹成标准结构：{name, created, commands:[{c,p}]}
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

		// getEphemeris — 选中（或指定）天体的星历表：随时间变化的 RA/Dec/高度/方位/星等
		if (commandName == "getEphemeris")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject jo = doc.isObject() ? doc.object() : QJsonObject();
			QString name = jo.value("name").toString();
			double startJD = jo.value("jd").toDouble(0.0);
			int days = jo.value("days").toInt(14);
			int stepHours = jo.value("stepHours").toInt(24);

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
			double origJD = core->getJD();
			QJsonArray rows;
			double jd = startJD;
			double endJD = startJD + days;
			while (jd <= endJD)
			{
				core->setJD(jd);
				Vec3d eq = obj->getEquinoxEquatorialPos(core);
				Vec3d aa = obj->getAltAzPosApparent(core);
				double alt = std::asin(aa[2] / aa.norm()) * 180.0 / M_PI;
				double az = std::fmod(std::atan2(aa[1], -aa[0]) * 180.0 / M_PI + 360.0, 360.0);
				QJsonObject row;
				row["jd"] = jd;
				row["date"] = StelUtils::julianDayToISO8601String(jd);
				row["ra"] = StelUtils::radToHmsStr(eq[0]);
				row["dec"] = StelUtils::radToDmsStr(eq[1]);
				row["altitude"] = alt;
				row["azimuth"] = az;
				row["magnitude"] = obj->getVMagnitude(core);
				rows.append(row);
				jd += stepHours / 24.0;
			}
			core->setJD(origJD);
			result["ok"] = true;
			result["name"] = obj->getNameI18n();
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
			int hours = jo.value("hours").toInt(24);
			int stepMin = jo.value("stepMin").toInt(10);

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
			double origJD = core->getJD();
			QJsonArray rows;
			int n = (hours * 60) / stepMin;
			for (int i = 0; i <= n; i++)
			{
				double jd = startJD + i * stepMin / 1440.0;
				core->setJD(jd);
				Vec3d aa = obj->getAltAzPosApparent(core);
				double alt = std::asin(aa[2] / aa.norm()) * 180.0 / M_PI;
				double az = std::fmod(std::atan2(aa[1], -aa[0]) * 180.0 / M_PI + 360.0, 360.0);
				QJsonObject row;
				row["jd"] = jd;
				row["t"] = i * stepMin / 60.0; // hours from start
				row["altitude"] = alt;
				row["azimuth"] = az;
				rows.append(row);
			}
			core->setJD(origJD);
			result["ok"] = true;
			result["name"] = obj->getNameI18n();
			result["curve"] = rows;
			return result;
		}

		// getPlanetCalc — 行星计算器：各行星距离/相位/距角/星等/高度/升落
		if (commandName == "getPlanetCalc")
		{
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			QStringList planetNames = QStringList() << "Mercury" << "Venus" << "Mars" << "Jupiter"
												   << "Saturn" << "Uranus" << "Neptune" << "Pluto" << "Sun" << "Moon";
			QJsonArray items;
			for (const QString& pn : planetNames)
			{
				PlanetP p = qSharedPointerCast<Planet>(ssys->searchByName(pn));
				if (!p) continue;
				QJsonObject po;
				po["name"] = p->getNameI18n();
				po["englishName"] = pn;
				Vec3d eq = p->getEquinoxEquatorialPos(core);
				po["ra"] = StelUtils::radToHmsStr(eq[0]);
				po["dec"] = StelUtils::radToDmsStr(eq[1]);
				Vec3d aa = p->getAltAzPosApparent(core);
				po["altitude"] = std::asin(aa[2] / aa.norm()) * 180.0 / M_PI;
				po["azimuth"] = std::fmod(std::atan2(aa[1], -aa[0]) * 180.0 / M_PI + 360.0, 360.0);
				po["magnitude"] = p->getVMagnitude(core);
				if (pn != "Sun")
				{
					double dist = p->getDistance(); // AU
					po["distanceAU"] = dist;
					Vec4d rts = p->getRTSTime(core);
					po["rise"] = StelUtils::julianDayToISO8601String(rts[0]);
					po["transit"] = StelUtils::julianDayToISO8601String(rts[1]);
					po["set"] = StelUtils::julianDayToISO8601String(rts[2]);
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

		// getPhenomena — 行星间的合（最小角距），未来约 400 天内距角 < 4° 的事件
		if (commandName == "getPhenomena")
		{
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			QStringList planetNames = QStringList() << "Mercury" << "Venus" << "Mars" << "Jupiter"
												   << "Saturn" << "Uranus" << "Neptune";
			QList<QJsonObject> phenomenaList;
			QList<PlanetP> planets;
			for (const QString& pn : planetNames)
			{
				PlanetP p = qSharedPointerCast<Planet>(ssys->searchByName(pn));
				if (p) planets.append(p);
			}
			double origJD = core->getJD();
			double startJD = origJD;
			int horizon = 400; // days
			QJsonArray items;
			for (int a = 0; a < planets.size(); a++)
			{
				for (int b = a + 1; b < planets.size(); b++)
				{
					double bestJD = 0, bestSep = 999;
					for (int d = 0; d <= horizon; d++)
					{
						double jd = startJD + d;
						core->setJD(jd);
						Vec3d va = planets[a]->getEquinoxEquatorialPos(core); va.normalize();
						Vec3d vb = planets[b]->getEquinoxEquatorialPos(core); vb.normalize();
						double sep = std::acos(qBound(-1.0, va.dot(vb), 1.0)) * 180.0 / M_PI;
						if (sep < bestSep) { bestSep = sep; bestJD = jd; }
					}
					if (bestSep < 4.0)
					{
						QJsonObject po;
						po["bodyA"] = planets[a]->getNameI18n();
						po["bodyB"] = planets[b]->getNameI18n();
						po["jd"] = bestJD;
						po["date"] = StelUtils::julianDayToISO8601String(bestJD);
						po["separation"] = bestSep;
						phenomenaList.append(po);
					}
				}
			}
			core->setJD(origJD);
			// 按日期排序（QJsonArray 的迭代器不支持 std::sort，先在 QList 上排好再装回去）
			std::sort(phenomenaList.begin(), phenomenaList.end(), [](const QJsonObject& x, const QJsonObject& y) {
				return x.value("jd").toDouble() < y.value("jd").toDouble();
			});
			for (const QJsonObject& po : phenomenaList)
				items.append(po);
			result["ok"] = true;
			result["phenomena"] = items;
			return result;
		}

		// getEclipses — 未来若干个月内的日食与月食预报
		if (commandName == "getEclipses")
		{
			QJsonDocument doc = QJsonDocument::fromJson(arg.toUtf8());
			QJsonObject jo = doc.isObject() ? doc.object() : QJsonObject();
			double startJD = jo.value("jd").toDouble(0.0);
			int months = jo.value("months").toInt(36);
			SolarSystem* ssys = GETSTELMODULE(SolarSystem);
			if (startJD <= 0) startJD = core->getJD();
			double origJD = core->getJD();
			QJsonArray items;
			QList<QJsonObject> eclipseList;

			auto elongDeg = [&](double jd) -> double {
				core->setJD(jd);
				PlanetP sun = ssys->getSun();
				PlanetP moon = ssys->getMoon();
				if (!sun || !moon) return -1;
				Vec3d sv = sun->getEquinoxEquatorialPos(core); sv.normalize();
				Vec3d mv = moon->getEquinoxEquatorialPos(core); mv.normalize();
				double c = qBound(-1.0, sv.dot(mv), 1.0);
				return std::acos(c) * 180.0 / M_PI;
			};
			auto refineMin = [&](double jd0, double target) -> double {
				double best = jd0, bestE = 999;
				for (int k = -144; k <= 144; k++)
				{
					double jd = jd0 + k * (1.0 / 144.0);
					double e = elongDeg(jd);
					double diff = (target == 0.0) ? e : std::fabs(e - 180.0);
					if (e >= 0 && diff < bestE) { bestE = diff; best = jd; }
				}
				return best;
			};

			double limitJD = startJD + months * 30.0;
			double prevPhase = elongDeg(startJD);
			int solarCount = 0, lunarCount = 0;
			for (double jd = startJD; jd <= limitJD; jd += 1.0)
			{
				double e = elongDeg(jd);
				// 检测过近（日食：elong→0）或过远（月食：elong→180）
				bool solarCand = (prevPhase > 1.0 && e <= 1.0) || (e <= 1.0 && jd == startJD);
				bool lunarCand = (prevPhase < 179.0 && e >= 179.0) || (e >= 179.0 && jd == startJD);
				if (solarCand)
				{
					double nm = refineMin(jd, 0.0);
					double dRatio, latDeg, lngDeg, altitude, pathWidth, duration, magnitude;
					calcSolarEclipseData(nm, dRatio, latDeg, lngDeg, altitude, pathWidth, duration, magnitude);
					if (magnitude > 0 && solarCount < 12)
					{
						QString type = magnitude >= 1.0 ? QStringLiteral("中心食") : QStringLiteral("偏食");
						// 用 SolarEclipseComputer 区分全食/环食/混合食
						SolarEclipseComputer sec(core, &StelApp::getInstance().getLocaleMgr());
						SolarEclipseComputer::EclipseMapData map = sec.generateEclipseMap(nm);
						switch (map.eclipseType)
						{
							case SolarEclipseComputer::EclipseMapData::EclipseType::Total: type = QStringLiteral("全食"); break;
							case SolarEclipseComputer::EclipseMapData::EclipseType::Annular: type = QStringLiteral("环食"); break;
							case SolarEclipseComputer::EclipseMapData::EclipseType::Hybrid: type = QStringLiteral("全环食"); break;
							default: break;
						}
						QJsonObject ev;
						ev["kind"] = "solar";
						ev["type"] = type;
						ev["jd"] = nm;
						ev["date"] = StelUtils::julianDayToISO8601String(nm);
						ev["magnitude"] = magnitude;
						ev["pathWidthKm"] = pathWidth * 6371.0 * 2.0 * M_PI / 360.0 * 1000.0; // 近似
						ev["durationMin"] = duration / 60.0;
						ev["centralLat"] = latDeg;
						ev["centralLng"] = lngDeg;
						eclipseList.append(ev);
						solarCount++;
					}
				}
				else if (lunarCand)
				{
					double fm = refineMin(jd, 180.0);
					// 几何估算：月球进入地影的程度
					double sep = std::fabs(180.0 - elongDeg(fm));
					double moonAngR = 0.26;            // 月球角半径（度，近似）
					double umbraAngR = 0.73;          // 地影在本影处的角半径（度，近似）
					double umbralMag = (umbraAngR - sep) / (2.0 * moonAngR);
					if (umbralMag > 0 && lunarCount < 12)
					{
						QString type = umbralMag >= 1.0 ? QStringLiteral("全食") : QStringLiteral("偏食");
						QJsonObject ev;
						ev["kind"] = "lunar";
						ev["type"] = type;
						ev["jd"] = fm;
						ev["date"] = StelUtils::julianDayToISO8601String(fm);
						ev["magnitude"] = umbralMag;
						ev["note"] = QStringLiteral("几何估算");
						eclipseList.append(ev);
						lunarCount++;
					}
				}
				prevPhase = e;
			}
			core->setJD(origJD);
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
	s_ohosRenderPumpActive = true;
	markQtLoopRunning();
	updateQueued = false;
	fpsTimer->setInterval(currentOhosRenderIntervalMs());
	renderOhosFrameNow();
	fpsTimer->start();
	qWarning() << "Started OpenHarmony render pump.";
}

void StelMainView::renderOhosFrameNow()
{
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
	// Optimistically draw the first frame at native resolution as well. A driver
	// that rejects sharing disables s_ohosZeroCopySupported during presentation,
	// so the following fallback frames return to OHOS_RENDER_SCALE.
	const double renderScale = s_ohosZeroCopySupported ? 1.0 : OHOS_RENDER_SCALE;
	const int width = qMax(1, int(glWidget->width() * pixelRatio * renderScale));
	const int height = qMax(1, int(glWidget->height() * pixelRatio * renderScale));

	StelApp& app = StelApp::getInstance();
	app.setDevicePixelsPerPixel(devicePixelRatioF());
	gl->glBindFramebuffer(GL_FRAMEBUFFER, glWidget->defaultFramebufferObject());
	gl->glViewport(0, 0, width, height);

	const double t2 = StelApp::getTotalRunTime();
	ohosUpdatePointTracking();
	ohosUpdateGyroTransition();
	ohosUpdatePanInertia(dt);
	app.update(dt);
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
