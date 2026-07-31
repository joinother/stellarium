/*
 * Stellarium
 * Copyright (C) 2009 Fabien Chereau
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

#include "StelLogger.hpp"
#ifdef Q_OS_WIN
#include <windows.h>
#endif
#if defined(__OHOS__)
#include <hilog/log.h>
#endif

// Init statics variables.
QtMessageHandler StelLogger::defaultMsgHandler;
QFile StelLogger::logFile;
QString StelLogger::log;
QMutex StelLogger::fileMutex;

void StelLogger::init(const QString& logFilePath)
{
	logFile.setFileName(logFilePath);

	if (logFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text | QIODevice::Unbuffered))
		defaultMsgHandler = qInstallMessageHandler(StelLogger::debugLogHandler);
}

void StelLogger::deinit()
{
	qInstallMessageHandler(Q_NULLPTR);
	logFile.close();
}

void StelLogger::debugLogHandler(QtMsgType type, const QMessageLogContext& ctx, const QString& msg)
{
	// *** NOTE: see original Qt source in qlogging.cpp (qDefaultMessageHandler) for sensible default code

	//use Qt to format the log message, if possible
	//this uses the format set by qSetMessagePattern
	//or QT_MESSAGE_PATTERN environment var
	QString fmt = qFormatLogMessage(type,ctx,msg);
	//do nothing for null messages
	if(fmt.isNull())
		return;

	//always append newline
	fmt.append(QLatin1Char('\n'));

#if defined(__OHOS__)
	// OpenHarmony has no stderr->hilog bridge: once this handler is installed,
	// every qDebug/qInfo/qWarning would become invisible to `hdc hilog` and only
	// survive in log.txt inside the app sandbox (which a non-root shell cannot
	// read). Mirror each message into hilog so device-side diagnosis works.
	// log.txt still receives the full stream via writeLog() below.
	{
		LogLevel ohosLevel = LOG_INFO;
		switch (type)
		{
			case QtDebugMsg:    ohosLevel = LOG_DEBUG; break;
			case QtInfoMsg:     ohosLevel = LOG_INFO;  break;
			case QtWarningMsg:  ohosLevel = LOG_WARN;  break;
			case QtCriticalMsg: ohosLevel = LOG_ERROR; break;
			case QtFatalMsg:    ohosLevel = LOG_FATAL; break;
			default:            ohosLevel = LOG_INFO;  break;
		}
		const QByteArray ohosMsg = fmt.trimmed().toUtf8();
		OH_LOG_Print(LOG_APP, ohosLevel, 0x0000, "StellariumQt", "%{public}s", ohosMsg.constData());
	}
#endif

#if defined Q_OS_ANDROID
	defaultMsgHandler(type, ctx, msg);
#elif defined Q_OS_WIN
	//Send debug messages to Debugger, if one is attached, instead of stderr
	//This seems to avoid output delays in Qt Creator, allowing for easier debugging
	//Seems to work fine with MSVC and MinGW
	if (IsDebuggerPresent())
	{
		OutputDebugStringW(reinterpret_cast<const wchar_t *>(fmt.utf16()));
	}
	else
#endif
	{
		//this does the same as the default handler in qlogging.cpp
		fprintf(stderr, "%s", qPrintable(fmt));
		fflush(stderr);
	}
	writeLog(fmt);
}

void StelLogger::writeLog(QString msg)
{
	if (!msg.endsWith('\n'))
		msg.append(QLatin1Char('\n'));

	fileMutex.lock();
	const auto utf8 = msg.toUtf8();
	logFile.write(utf8.constData(), utf8.size());
	log += msg;
	fileMutex.unlock();
}
