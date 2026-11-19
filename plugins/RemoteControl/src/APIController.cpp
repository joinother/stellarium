/*
 * Stellarium Remote Control plugin
 * Copyright (C) 2015 Florian Schaukowitsch
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

#include "APIController.hpp"
#include "StelApp.hpp"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThread>

int APIServiceResponse::metaTypeId = qRegisterMetaType<APIServiceResponse>();
int APIServiceResponse::parametersMetaTypeId = qRegisterMetaType<APIParameters>();

APIController::APIController(int prefixLength, QObject* parent) : HttpRequestHandler(parent), m_prefixLength(prefixLength)
{
}

APIController::~APIController()
{
	//Services are not deleted here
	//use the QObject parent relationship for that
}

void APIController::update(double deltaTime)
{
	for (auto& service : m_serviceMap)
	{
		service->update(deltaTime);
	}
}

void APIController::registerService(RemoteControlServiceInterface *service)
{
	QByteArray key = service->getPath().latin1();
	if(m_serviceMap.contains(key))
	{
		qWarning()<<"Service"<<key<<"already registered, skipping...";
		return;
	}
	m_serviceMap.insert(key, service);
}

void APIController::performGet(RemoteControlServiceInterface *service, const QByteArray &operation, const APIParameters &parameters, APIServiceResponse *response)
{
	Q_ASSERT(QThread::currentThread() == StelApp::getInstance().thread());
	service->get(operation, parameters, *response);
}

void APIController::performPost(RemoteControlServiceInterface *service, const QByteArray &operation, const APIParameters &parameters, const QByteArray &data, APIServiceResponse *response)
{
	Q_ASSERT(QThread::currentThread() == StelApp::getInstance().thread());
	service->post(operation, parameters, data, *response);
}

void APIController::service(HttpRequest &request, HttpResponse &response)
{
	//disable caching by default for services
	response.setHeader("Cache-Control","no-cache");
	//default content type is text
	response.setHeader("Content-Type","text/plain");

	//use the raw path here
	QByteArray path = request.getRawPath();
	QByteArray pathWithoutPrefix = path.right(path.size()-m_prefixLength);

	int slashIdx = pathWithoutPrefix.indexOf('/');

	QByteArray serviceString = pathWithoutPrefix;
	QByteArray operation;
	if(slashIdx>=0)
	{
		serviceString = pathWithoutPrefix.mid(0,slashIdx);
		operation = pathWithoutPrefix.mid(slashIdx+1);
	}

	if ((serviceString.isEmpty() || serviceString == "info") && request.getMethod() == "GET")
	{
		QJsonArray services;
		for (auto sit = m_serviceMap.cbegin(); sit != m_serviceMap.cend(); ++sit)
			services.append(QString::fromUtf8(sit.key()));

		QJsonObject endpoints;
		endpoints.insert("GET /api/info", "API catalog and auth info");
		endpoints.insert("GET /api/main/status", "Time, location, FOV, selected object, action/property deltas");
		endpoints.insert("GET /api/main/view", "Current view direction (j2000, jNow, altAz)");
		endpoints.insert("GET /api/main/plugins", "Installed plugins and load status");
		endpoints.insert("POST /api/main/focus", "Focus object (target=<name>&mode=center|zoom|mark)");
		endpoints.insert("POST /api/main/fov", "Set field of view in degrees (fov=<deg>)");
		endpoints.insert("POST /api/main/time", "Set Julian Day / rate (time=<jd>&timerate=<daysPerSec>)");
		endpoints.insert("POST /api/main/move", "Pan camera (x=<-1..1>&y=<-1..1>)");
		endpoints.insert("POST /api/main/view", "Set view direction (az=<rad>&alt=<rad> or j2000/jNow/altAz)");
		endpoints.insert("GET /api/objects/find", "Search objects (str=<query>)");
		endpoints.insert("GET /api/objects/info", "Detailed object info (name=<name>&format=json|html)");
		endpoints.insert("GET /api/stelaction/list", "List all toggleable actions");
		endpoints.insert("POST /api/stelaction/do", "Trigger or toggle action (id=<actionId>)");
		endpoints.insert("GET /api/stelproperty/list", "List all properties");
		endpoints.insert("POST /api/stelproperty/set", "Set property (id=<propId>&value=<val>)");
		endpoints.insert("GET /api/location/planetlist", "List observer planets");
		endpoints.insert("POST /api/location/setlocationfields", "Set observer location (latitude, longitude, altitude, name, planet)");
		endpoints.insert("GET /api/view/listskyculture", "List sky cultures");
		endpoints.insert("GET /api/view/listlandscape", "List landscapes");
		endpoints.insert("GET /api/view/listprojection", "List projections");

		QJsonObject info;
		info.insert("ok", true);
		info.insert("server", QStringLiteral("Stellarium RemoteControl"));
		info.insert("version", QStringLiteral(REMOTECONTROL_PLUGIN_VERSION));
		info.insert("services", services);
		info.insert("auth", QJsonArray{
			QStringLiteral("Authorization: Basic base64(':password' or 'user:password')"),
			QStringLiteral("Authorization: Bearer <password>"),
			QStringLiteral("X-API-Key: <password>")
		});
		info.insert("endpoints", endpoints);

		response.setHeader("Content-Type", "application/json; charset=utf-8");
		response.write(QJsonDocument(info).toJson(QJsonDocument::Compact), true);
		return;
	}

	//try to find service
	auto it = m_serviceMap.find(serviceString);
	if(it!=m_serviceMap.end())
	{
		RemoteControlServiceInterface* sv = *it;

		//create the response object
		APIServiceResponse apiresponse;
		if(request.getMethod()=="GET")
		{
#ifdef FORCE_THREADED_SERVICES
			sv->get(operation, request.getParameterMap(), apiresponse);
#else
			if(sv->isThreadSafe())
			{
				sv->get(operation,request.getParameterMap(), apiresponse);
			}
			else
			{
				//invoke it in the main thread!
				QMetaObject::invokeMethod(this,"performGet",Qt::BlockingQueuedConnection,
							  Q_ARG(RemoteControlServiceInterface*, sv),
							  Q_ARG(QByteArray, operation),
							  Q_ARG(APIParameters, request.getParameterMap()),
							  Q_ARG(APIServiceResponse*, &apiresponse));
			}
#endif
			applyAPIResponse(apiresponse,response);
		}
		else if (request.getMethod()=="POST")
		{
#ifdef FORCE_THREADED_SERVICES
			sv->post(operation, request.getParameterMap(), request.getBody(), apiresponse);
#else
			if(sv->isThreadSafe())
			{
				sv->post(operation, request.getParameterMap(), request.getBody(), apiresponse);
			}
			else
			{
				QMetaObject::invokeMethod(this,"performPost",Qt::BlockingQueuedConnection,
							  Q_ARG(RemoteControlServiceInterface*, sv),
							  Q_ARG(QByteArray, operation),
							  Q_ARG(APIParameters, request.getParameterMap()),
							  Q_ARG(QByteArray, request.getBody()),
							  Q_ARG(APIServiceResponse*, &apiresponse));
			}
#endif
			applyAPIResponse(apiresponse,response);
		}
		else
		{
			response.setStatus(405,"Method Not allowed");
			QString str(QStringLiteral("Method %1 not allowed for service %2"));
			response.write(str.arg(QString::fromLatin1(request.getMethod()), QString::fromUtf8(pathWithoutPrefix)).toUtf8(),true);
		}
	}
	else
	{
		response.setStatus(400,"Bad Request");
		QString str(QStringLiteral("Unknown service: '%1'\n\nAvailable services:\n").arg(QString::fromUtf8(pathWithoutPrefix)));
		for (auto it = m_serviceMap.begin(); it != m_serviceMap.end(); ++it)
		{
			str.append(QString::fromUtf8(it.key()));
			str.append("\n");
		}
		response.write(str.toUtf8(),true);
	}
}

void APIController::applyAPIResponse(const APIServiceResponse &apiresponse, HttpResponse &httpresponse)
{
	if(apiresponse.status != -1)
	{
		httpresponse.setStatus(apiresponse.status, apiresponse.statusText);
	}

	//apply headers
	QMapIterator<QByteArray,QByteArray> i(apiresponse.headers);
	while (i.hasNext())
	{
		i.next();
		httpresponse.getHeaders().insert(i.key(), i.value());
	}

	//send response data, if any
	if(apiresponse.responseData.isEmpty())
	{
		httpresponse.getHeaders().clear();
		httpresponse.setStatus(500,"Internal Server Error");
		httpresponse.write("Service provided no response",true);
	}
	httpresponse.write(apiresponse.responseData,true);
}
