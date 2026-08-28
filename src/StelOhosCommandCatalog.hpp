#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QStringList>

namespace StellariumOhosCommandCatalog
{

inline QStringList names()
{
	return QStringLiteral(
		"addBookmark,addDay,addHour,addMinute,addMonth,addYear,advanceTime,angleMeasurePoint,applySessionState,"
		"beginGyroViewTransition,beginSkyGesture,cancelGyroViewTransition,clearSelection,cycleCCD,cycleLens,cycleOcular,cycleTelescope,"
		"deleteBookmark,deleteRecording,downloadStarCatalog,dragView,endPinch,exportConfig,getAboutInfo,"
		"getAbsoluteStarScale,getActionState,getAlmanac,getAltAzCurve,getAngleMeasure,getAnnualElevation,getAppState,"
		"getAppVersion,getAtmosphereBrightness,getAtmosphereFlags,getAtmosphereIntensity,getAtmosphereParams,"
		"getAutoMoveDuration,getAutoZoom,getAutoZoomResets,getBasicInfo,getBookmarks,getCatalogHealth,getCelestialPositions,getConfigString,"
		"getConstellationFlags,getConstellationForPosition,getConstellationInfo,getConstellationList,getCurrentViewInfo,"
		"getDSOCounts,getDateFormat,getDateTimeLocal,getDeepSkyImageStatus,getDeltaT,getDeltaTAlgorithmDescription,"
		"getDistanceInfo,getDitheringMode,getDsoLabels,getEclipses,getEphemeris,getFOV,getFPS,getFieldOfView,"
		"getFlagClearSky,getFlagGravityLabels,getGridFlags,getGyroGuidePosition,getHeliocentricEclipticPositions,"
		"getIsDaylight,getLandscapeCount,getLandscapeInfo,getLandscapeList,getLandscapeOpacity,getLightPollution,"
		"getLimitMagnitude,getLoadedModuleNames,getLocationList,getLog,getLunarElongationCurve,getMemoryUsage,"
		"getMeteorShowers,getMeteors,getMilkyWayFlags,getMilkyWayIntensity,getMoonPhases,getMountMode,getNebulaFlags,"
		"getNightMode,getObjectInfo,getObjectPositions,getObjectSpokenText,getObservabilityCalendar,getObserverInfo,"
		"getObserverPlanetList,getOculars,getOrbitDisplaySettings,getPhenomena,getPlanetCalc,getPlanetPairDistanceCurve,"
		"getPlanetPositions,getPlanetTimeSeries,getPlanetaryTransits,getPluginList,getPolarScopeData,getProjectionInfo,getProjectionList,"
		"getRTS,getRTSCalendar,getSatellites,getScreenInfo,getScriptList,getScriptRate,getScriptStatus,"
		"getSelectedObjectInfo,getSelectedObjects,getSelectedType,getSessionState,getSiderealTime,getSimulationTime,"
		"getSkyCultureDetails,getSkyCultureInfo,getSkyCultureList,getSkyCultureTerritoryGeometry,getSkyCultureVisualSettings,"
		"getSkyCultures,getSolarElongation,getSolarSystemFlags,getStarCatalogStatus,getStarCatalogs,getStarCount,"
		"getStarCountFull,getStarFlags,getStarScale,getState,getTimeFormat,getTimeInfo,getTonightEvents,"
		"getTracking,getTrailDisplaySettings,getVMagnitude,getVideoRecordingState,getViewCenterCoordinates,getViewDirection,getViewportOffset,"
		"getViewportSize,getWutTargets,gotoBookmark,gotoRADec,gyroDiagnostic,importConfig,listMatchingObjects,listObjects,"
		"listRecordings,loadPlugin,loadRecording,moveToAltAz,moveToSelected,moveToSelectedAt,panBy,pauseScript,playScript,"
		"pointAtSky,pointAtSkyStop,reloadSkyCulture,resetAngleMeasure,resumeScript,saveRecording,saveScreenShot,searchObject,"
		"selectAt,selftestActions,setAbsoluteStarScale,setActionChecked,setActionStates,setApplicationForeground,"
		"setAtmosphereFlag,setAtmosphereParams,setAutoMoveDuration,setAutoZoom,setAutoZoomResets,setBortleScale,setCCD,"
		"setConfigString,setConstellationFlag,setCrosshairs,setDate,setDateFormat,setDitheringMode,setDsoLabels,setFOV,"
		"setFieldOfView,setFlagClearSky,setFlagGravityLabels,setFlatHorizon,setFovMarkerSetting,setGridFlag,setGyroView,"
		"setJD,setLandscape,setLandscapeFadeWithZoom,setLandscapeOpacity,setLandscapeTransparency,setLandscapeUseTransparency,"
        "setLanguage,setLightPollution,setLimitMagnitude,setLocation,setLocationByName,setLocationCoords,setMeteorShowersFlag,setScreenSafeArea,"
		"setMeteors,setMilkyWayFlag,setMilkyWayIntensity,setMountMode,setNebulaFlag,setNightMode,setObserverPlanet,"
		"setOcularMode,setOrbitDisplaySetting,setPluginLoadAtStartup,setProjectionType,setSatellitesFlag,setScriptRate,setSkyCulture,"
		"setSkyCultureCommonNames,setSkyCultureDefault,setSkyCultureLabelStyle,setSkyCultureScreenLabelStyle,"
		"setSkyCultureShortLabels,setSkyCultureVisualColor,setSkyCultureVisualSetting,setSkyDisplaySetting,setSolarSystemFlag,"
		"setStarFlag,setStarLabelsAmount,setStarScale,setTelrad,setTimeFormat,setTimeRate,setTimeToJD,setJulianDate,setTracking,"
		"setTrailDisplaySetting,setVerticalClamp,setViewLock,setViewportOffset,startPanInertia,startVideoRecording,"
		"stopPanInertia,stopScript,stopVideoRecording,telescopeLx200Abort,telescopeLx200GotoSelected,telescopeLx200SyncSelected,"
		"triggerAction,unloadPlugin,zoomBy,zoomStep,getCommandCatalog,getCommandSchema,getCommandStatus").split(',');
}

inline QString categoryFor(const QString& name)
{
	if (name.startsWith("get") || name.startsWith("list") || name == "selftestActions") return QStringLiteral("查询");
	if (name.endsWith("Script") || name == "playScript" || name == "stopScript" || name == "pauseScript" || name == "resumeScript") return QStringLiteral("脚本");
	if (name.contains("Plugin") || name.startsWith("telescope") || name.startsWith("cycleOcular") || name.startsWith("cycleLens") || name.startsWith("cycleCCD")) return QStringLiteral("插件");
	if (name.contains("Recording") || name.contains("Video")) return QStringLiteral("录制");
	if (name.startsWith("getCommand")) return QStringLiteral("CLI");
	if (name.startsWith("set") || name.startsWith("add") || name.startsWith("delete") || name.startsWith("clear") || name.startsWith("select") || name.startsWith("goto") || name.startsWith("move") || name.startsWith("zoom") || name.startsWith("pan") || name.startsWith("advance")) return QStringLiteral("控制");
	return QStringLiteral("工具");
}

inline bool isRestricted(const QString& name)
{
	return name == "setConfigString" || name == "importConfig" || name == "exportConfig" ||
		name == "downloadStarCatalog" || name == "loadPlugin" || name == "unloadPlugin" || name == "setPluginLoadAtStartup" ||
		name.startsWith("telescope") || name == "startVideoRecording" || name == "stopVideoRecording";
}

inline QJsonObject item(const QString& name)
{
	QJsonObject value;
	value["name"] = name;
	value["category"] = categoryFor(name);
	value["description"] = QStringLiteral("通过统一命令总线调用 Stellarium 的 %1 能力").arg(name);
	value["mutatesState"] = !(name.startsWith("get") || name.startsWith("list") || name == "selftestActions");
	value["requiresConfirmation"] = isRestricted(name);
	value["offline"] = name != "downloadStarCatalog";
	value["payload"] = QJsonObject{{"type", "string"}, {"required", false}, {"encoding", "legacy-or-json"}};
	if (name == "searchObject") value["examplePayload"] = "M31";
	else if (name == "setFOV" || name == "setFieldOfView") value["examplePayload"] = "45";
	else if (name == "setJulianDate")
	{
		value["description"] = QStringLiteral("设置模拟时间；payload 使用 jd|数值 或 mjd|数值，MJD = JD - 2400000.5");
		value["examplePayload"] = "mjd|51544.50000";
	}
	else if (name == "setLocationCoords") value["examplePayload"] = "39.9042|116.4074|43";
	else if (name == "setPluginLoadAtStartup")
	{
		value["description"] = QStringLiteral("设置插件是否随应用启动加载；不等同于插件当前运行状态或插件内部功能开关");
		value["examplePayload"] = "Satellites|1";
	}
	else if (name == "selectAt") value["examplePayload"] = "720|480|1440|960";
	else if (name == "setActionChecked") value["examplePayload"] = "actionShow_Stars|1";
	else if (name == "getWutTargets") value["examplePayload"] = "{\"category\":\"planets\"}";
	else if (name == "getPolarScopeData") value["description"] = QStringLiteral("读取实时极轴镜分划数据，包括天极/极星屏幕投影、时角和钟面位置；星空由 Stellarium 原生渲染");
	else if (name == "getCommandSchema") value["examplePayload"] = "getTimeInfo";
	return value;
}

inline QJsonArray all()
{
	QJsonArray result;
	for (const QString& name : names()) result.append(item(name));
	return result;
}

inline QJsonObject schema(const QString& command)
{
	if (!names().contains(command)) return QJsonObject();
	QJsonObject result = item(command);
	result["protocol"] = QStringLiteral("StellariumOhos_command");
	result["transport"] = QStringLiteral("local-hdc-aa-want");
	result["result"] = QJsonObject{{"type", "object"}, {"required", QJsonArray{"ok"}}};
	return result;
}

}
