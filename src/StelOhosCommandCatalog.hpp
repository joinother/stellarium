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
		"getAppVersion,getAstroCalcContext,getAtmosphereBrightness,getAtmosphereFlags,getAtmosphereIntensity,getAtmosphereParams,"
		"getAutoMoveDuration,getAutoZoom,getAutoZoomResets,getBasicInfo,getBookmarks,getCatalogHealth,getCelestialPositions,getConfigString,"
		"getConstellationArtStatus,getConstellationFlags,getConstellationForPosition,getConstellationInfo,getConstellationList,getCurrentViewInfo,"
		"getDSOCounts,getDateFormat,getDateTimeLocal,getDeepSkyImageStatus,getDeltaT,getDeltaTAlgorithmDescription,"
		"getDistanceInfo,getDitheringMode,getDsoLabels,getEclipses,getEphemeris,getFOV,getFPS,getFieldOfView,"
		"getFlagClearSky,getFlagGravityLabels,getGridFlags,getGyroGuidePosition,getHeliocentricEclipticPositions,"
		"getIsDaylight,getLandscapeCount,getLandscapeInfo,getLandscapeList,getScenery3dList,getLandscapeOpacity,getLightPollution,"
		"getLimitMagnitude,getLoadedModuleNames,getLocationList,getLog,getLunarElongationCurve,getMemoryUsage,"
		"getMeteorDiagnostics,getMeteorShowers,getMeteors,getMilkyWayFlags,getMilkyWayIntensity,getMoonPhases,getMountMode,getNebulaFlags,"
		"getNightMode,getObjectCatalogCategories,getObjectInfo,getObjectPositions,getObjectSpokenText,getObservabilityCalendar,getObserverInfo,"
		"getObserverPlanetList,getOculars,getMosaicCamera,getEquationOfTime,getArchaeoLines,getNavStars,getOrbitDisplaySettings,getPhenomena,getPlanetCalc,getPlanetPairDistanceCurve,"
		"getPlanetPositions,getPlanetTimeSeries,getPlanetaryTransits,getPluginList,getPointerCoordinates,getPolarScopeData,getProjectionInfo,getProjectionList,"
		"getRTS,getRTSCalendar,getSatellites,getScreenInfo,getScriptList,getScriptRate,getScriptStatus,"
		"getSelectedObjectInfo,getSelectedObjects,getSelectedType,getObjectDetailModel,getObjectDetailConnector,getSessionState,getSiderealTime,getSimulationTime,"
		"getSkyCultureDetails,getSkyCultureInfo,getSkyCultureList,getSkyCultureState,getSkyCultureTerritoryGeometry,getSkyCultureVisualSettings,"
		"getSkyCultures,getSolarElongation,getSolarSystemFlags,getStarCatalogStatus,getStarCatalogs,getStarCount,"
		"getStarCountFull,getStarFlags,getStarScale,getState,getTimeFormat,getTimeInfo,getTonightEvents,"
		"getTracking,getTrailDisplaySettings,getVMagnitude,getVideoRecordingState,getViewCenterCoordinates,getViewDirection,getViewportOffset,getNavigationSettings,getInformationSettings,getTimeSettings,getEphemerisSettings,"
		"getViewportSize,getWutTargets,gotoBookmark,gotoRADec,gyroDiagnostic,importConfig,importScript,listMatchingObjects,listObjects,"
		"listRecordings,loadPlugin,loadRecording,moveToAltAz,moveToSelected,moveToSelectedAt,panBy,pauseScript,playScript,"
		"pointAtSky,pointAtSkyStop,reloadSkyCulture,resetAngleMeasure,retryDeepSkyImages,resumeScript,saveRecording,saveScreenShot,searchObject,"
		"selectAt,selftestActions,setAbsoluteStarScale,setActionChecked,setActionStates,setApplicationForeground,"
		"setAtmosphereFlag,setAtmosphereParams,setAutoMoveDuration,setAutoZoom,setAutoZoomResets,setBortleScale,setCCD,"
		"setConfigString,setConstellationFlag,setCrosshairs,setDate,setDateFormat,setDitheringMode,setDsoLabels,setFOV,"
		"setFieldOfView,setFlagClearSky,setFlagGravityLabels,setFlatHorizon,setFovMarkerSetting,setGridFlag,setGyroView,"
		"setJD,setLandscape,setLandscapeFadeWithZoom,setLandscapeOpacity,setLandscapeTransparency,setLandscapeUseTransparency,"
		"setLanguage,setLightPollution,setLimitMagnitude,setLocation,setLocationByName,setLocationCoords,setMeteorShowersFlag,setPolarScopeOverlay,centerPolarScope,setScreenSafeArea,"
		"setMeteors,setMilkyWayFlag,setMilkyWayIntensity,setMountMode,setNebulaFlag,setNightMode,setObserverPlanet,"
		"selectOcularInstrument,setOcularMode,setOcularSetting,rotateOcularReticle,resetOcularInstrument,setMosaicCamera,setEquationOfTime,setArchaeoLineSetting,setNavStarsSetting,setOrbitDisplaySetting,setPluginLoadAtStartup,setPointerCoordinates,setProjectionType,setSatellitesFlag,setScenery3dEnabled,setScenery3dScene,setScriptRate,setSkyCulture,"
		"setSkyCultureCommonNames,setSkyCultureDefault,setSkyCultureLabelStyle,setSkyCultureScreenLabelStyle,"
		"setSkyCultureShortLabels,setSkyCultureVisualColor,setSkyCultureVisualSetting,setSkyDisplaySetting,setSolarSystemFlag,setObjectDetailConnector,"
		"setStarFlag,setStarLabelsAmount,setStarScale,setTelrad,setTimeFormat,setTimeRate,setTimeToJD,setJulianDate,setTracking,"
		"setTrailDisplaySetting,setVerticalClamp,setViewLock,setViewportOffset,setNavigationSetting,setInformationSetting,setTimeSetting,setEphemerisSetting,saveCurrentView,saveAllSettings,restoreDefaultSettings,startPanInertia,startVideoRecording,"
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
	return name == "setConfigString" || name == "importConfig" || name == "importScript" || name == "exportConfig" ||
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
	else if (name == "getConstellationArtStatus")
	{
		value["description"] = QStringLiteral("诊断当前星空文化的星座艺术文件、纹理加载和视口可见状态");
		value["examplePayload"] = "Ori";
	}
	else if (name == "getObjectDetailModel")
	{
		value["description"] = QStringLiteral("读取选中天体详情媒体的 3D 模型能力契约；星座暂无已安装模型时返回 planned 和二维绘图回退");
	}
	else if (name == "retryDeepSkyImages")
		value["description"] = QStringLiteral("重新尝试解码当前视野中失败的离线深空资料图，不重载整套图库");
	else if (name == "importScript")
	{
		value["description"] = QStringLiteral("从设备可读路径导入离线 .ssc 脚本到用户脚本目录；不执行脚本内容");
		value["examplePayload"] = "/data/local/tmp/example.ssc";
	}
	else if (name == "getScriptList")
	{
		value["description"] = QStringLiteral("列出内置和用户脚本；默认返回完整元数据，payload=summary 只返回文件名和数量，适合日志传输");
		value["examplePayload"] = "summary";
	}
	else if (name == "getPluginList")
	{
		value["description"] = QStringLiteral("列出随 HAP 编译的插件；默认返回完整元数据，payload=summary 只返回运行/启动状态，适合日志传输");
		value["examplePayload"] = "summary";
	}
	else if (name == "pauseScript" || name == "resumeScript")
	{
		value["description"] = QStringLiteral("控制原生脚本暂停或继续；Qt 6 脚本引擎不支持这两项操作，会返回 supported=false");
	}
	else if (name == "getWutTargets") value["examplePayload"] = "{\"category\":\"planets\"}";
	else if (name == "getPolarScopeData") value["description"] = QStringLiteral("读取实时极轴镜分划数据，包括天极/极星屏幕投影、时角和钟面位置；星空由 Stellarium 原生渲染");
	else if (name == "getAstroCalcContext") value["description"] = QStringLiteral("读取离线天文计算上下文，包括观测地点、时区、儒略日、平/视恒星时、时间方程和太阳/月球当前高度方位");
	else if (name == "setPolarScopeOverlay")
	{
		value["description"] = QStringLiteral("在原生星图渲染帧中显示或隐藏极轴镜分划；payload 使用 active|水平翻转|垂直翻转");
		value["examplePayload"] = "1|0|0";
	}
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
