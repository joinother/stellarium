#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QStringList>

namespace StellariumOhosCommandCatalog
{

inline QStringList names()
{
	return QStringLiteral(
		"copyTextToClipboard,getGuideState,startGuide,guideAction,beginGuidedSession,endGuidedSession,"
		"setAstroTab,setAstroGroup,setAstroFilter,setAstroScroll,getAstroPanelState,"
		"addBookmark,addDay,addHour,addMinute,addMonth,addYear,advanceTime,angleMeasurePoint,applySessionState,"
		"beginGyroViewTransition,beginSkyGesture,cancelGyroViewTransition,clearSelection,cycleCCD,cycleLens,cycleOcular,cycleTelescope,"
		"deleteBookmark,deleteRecording,downloadStarCatalog,dragView,endPinch,exportConfig,getAboutInfo,"
		"getAbsoluteStarScale,getActionState,getAlmanac,getAltAzCurve,getAngleMeasure,getAnnualElevation,getAppState,"
		"getAppVersion,getAstroCalcContext,getAtmosphereBrightness,getAtmosphereFlags,getAtmosphereIntensity,getAtmosphereParams,"
		"getAutoMoveDuration,getAutoZoom,getAutoZoomResets,getBasicInfo,getBookmarks,getCatalogHealth,getCelestialPositions,getConfigString,"
		"getConstellationArtStatus,getConstellationFlags,getConstellationForPosition,getConstellationInfo,getConstellationList,getCurrentViewInfo,"
		"getDSOCounts,getDateFormat,getDateTimeLocal,getDeepSkyImageStatus,getDeltaT,getDeltaTAlgorithmDescription,getNebulaTextureStatus,"
		"getDistanceInfo,getDitheringMode,getDsoLabels,getEclipses,getEphemeris,getFOV,getFPS,getFieldOfView,"
		"getFlagClearSky,getFlagGravityLabels,getGridFlags,getGyroGuidePosition,getHeliocentricEclipticPositions,"
		"getIsDaylight,getLandscapeCount,getLandscapeInfo,getLandscapeList,getScenery3dList,getLandscapeOpacity,getLightPollution,"
		"getLimitMagnitude,getLoadedModuleNames,getLocationList,getLog,getLunarElongationCurve,getMemoryUsage,"
		"getMeteorDiagnostics,getMeteorShowers,getMeteors,getMilkyWayFlags,getMilkyWayIntensity,getMoonPhases,getMountMode,getNebulaFlags,"
		"getNightMode,getObjectCatalogCategories,getObjectInfo,getObjectPositions,getObjectSpokenText,getObservabilityCalendar,getObserverInfo,"
		"getObserverPlanetList,getOculars,getMosaicCamera,getEquationOfTime,getArchaeoLines,getNavStars,getOrbitDisplaySettings,getPhenomena,getPlanetCalc,getPlanetPairDistanceCurve,"
		"getPlanetPositions,getPlanetTimeSeries,getPlanetaryTransits,getPluginList,getPointerCoordinates,getPolarScopeData,getProjectionInfo,getProjectionList,"
		"getRTS,getRTSCalendar,getSatellites,getSatelliteSources,getSatelliteDetail,getSatellitePasses,getScreenInfo,getScriptList,getScriptRate,getScriptStatus,getScriptCaptions,"
		"getSelectedObjectInfo,getSelectedObjects,getSelectedType,getObjectDetailModel,getObjectDetailConnector,getSessionState,getSiderealTime,getSimulationTime,"
			"getSkyCultureDetails,getSkyCultureInfo,getSkyCultureList,getSkyCultureMakerDraft,getSkyCultureState,getSkyCultureTerritoryGeometry,getSkyCultureVisualSettings,"
		"getSkyCultures,getSolarElongation,getSolarSystemFlags,getStarCatalogStatus,getStarCatalogs,getStarCount,"
		"getStarCountFull,getStarFlags,getStarScale,getState,getTimeFormat,getTimeInfo,getTonightEvents,"
		"getTracking,getTrailDisplaySettings,getVMagnitude,getVideoRecordingState,getViewCenterCoordinates,getViewDirection,getViewportOffset,getNavigationSettings,getInformationSettings,getTimeSettings,getEphemerisSettings,"
		"getViewportSize,getWutTargets,gotoBookmark,gotoNebulaTexture,gotoRADec,gyroDiagnostic,importConfig,importNebulaTexture,importScript,listMatchingObjects,listNebulaTextures,listObjects,"
		"listRecordings,loadPlugin,loadRecording,moveToAltAz,moveToSelected,moveToSelectedAt,panBy,pauseScript,playScript,"
		"pointAtSky,pointAtSkyStop,refreshNebulaTextures,reloadSkyCulture,removeNebulaTexture,resetAngleMeasure,retryDeepSkyImages,resumeScript,saveRecording,saveScreenShot,searchObject,"
		"selectAt,selftestActions,setAbsoluteStarScale,setActionChecked,setActionStates,setApplicationForeground,"
		"setAtmosphereFlag,setAtmosphereParams,setAutoMoveDuration,setAutoZoom,setAutoZoomResets,setBortleScale,setCCD,"
		"setConfigString,setConstellationFlag,setCrosshairs,setDate,setDateFormat,setDitheringMode,setDsoLabels,setFOV,"
		"setFieldOfView,setFlagClearSky,setFlagGravityLabels,setFlatHorizon,setFovMarkerSetting,setGridFlag,setGyroView,"
		"setJD,setLandscape,setLandscapeFadeWithZoom,setLandscapeOpacity,setLandscapeTransparency,setLandscapeUseTransparency,"
		"setLanguage,setLightPollution,setLimitMagnitude,setLocation,setLocationByName,setLocationCoords,setMeteorShowersFlag,setPolarScopeOverlay,centerPolarScope,setScreenSafeArea,"
		"setSatelliteSources,setSatelliteUpdateSetting,importSatelliteTle,refreshSatelliteCatalog,"
		"setMeteors,setMilkyWayFlag,setMilkyWayIntensity,setMountMode,setNebulaFlag,setNebulaTextureConflictAvoidance,setNebulaTexturesVisible,setNightMode,setObserverPlanet,"
		"selectOcularInstrument,setOcularMode,setOcularSetting,rotateOcularReticle,resetOcularInstrument,setMosaicCamera,setEquationOfTime,setArchaeoLineSetting,setNavStarsSetting,setOrbitDisplaySetting,setPluginLoadAtStartup,setPointerCoordinates,setProjectionType,setSatellitesFlag,setScenery3dEnabled,setScenery3dScene,setScriptRate,setSkyCulture,"
		"setSkyCultureCommonNames,setSkyCultureDefault,setSkyCultureLabelStyle,setSkyCultureScreenLabelStyle,"
		"setSkyCultureShortLabels,setSkyCultureVisualColor,setSkyCultureVisualSetting,setSkyDisplaySetting,setSolarSystemFlag,setObjectDetailConnector,"
		"setStarFlag,setStarLabelsAmount,setStarScale,setTelrad,setTimeFormat,setTimeRate,setTimeToJD,setJulianDate,setTracking,"
		"setTrailDisplaySetting,setVerticalClamp,setViewLock,setViewportOffset,setNavigationSetting,setInformationSetting,setTimeSetting,setEphemerisSetting,setTelescopeLivePosition,saveCurrentView,saveAllSettings,restoreDefaultSettings,startPanInertia,startVideoRecording,openPluginFeature,"
		"stopPanInertia,stopScript,continueScript,sendKey,stopVideoRecording,importLandscape,getTelescopeControl,getTelescopeProfiles,saveTelescopeProfile,deleteTelescopeProfile,selectTelescopeProfile,testTelescopeConnection,getTelescopePosition,centerScreenOnTelescope,telescopeLx200Abort,telescopeLx200GotoSelected,telescopeLx200SyncSelected,"
			"triggerAction,unloadPlugin,validateNebulaTexture,zoomBy,zoomStep,getCommandCatalog,getCommandSchema,getCommandStatus,"
			"saveSkyCultureMakerDraft,resetSkyCultureMakerDraft,addSkyCultureMakerConstellation,updateSkyCultureMakerConstellation,removeSkyCultureMakerConstellation,"
			"addSkyCultureMakerLine,addSkyCultureMakerSelectedStar,importSkyCultureMakerArtwork,setSkyCultureMakerArtworkAnchor,removeSkyCultureMakerArtwork,"
			"undoSkyCultureMakerEdit,validateSkyCultureMakerDraft,exportSkyCultureMaker,importSkyCultureMaker").split(',');
}

inline QString categoryFor(const QString& name)
{
	if (name.startsWith("get") || name.startsWith("list") || name == "selftestActions") return QStringLiteral("查询");
	if (name.endsWith("Script") || name == "playScript" || name == "stopScript" || name == "pauseScript" || name == "resumeScript" || name == "continueScript" || name == "sendKey" || name == "getScriptCaptions") return QStringLiteral("脚本");
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
		name.startsWith("telescope") || name == "setTelescopeLivePosition" || name == "startVideoRecording" || name == "stopVideoRecording" ||
			name == "importNebulaTexture" || name == "removeNebulaTexture" || name == "resetSkyCultureMakerDraft" ||
				name == "removeSkyCultureMakerConstellation" || name == "importSkyCultureMaker" || name == "exportSkyCultureMaker" ||
				name == "importSkyCultureMakerArtwork" || name == "removeSkyCultureMakerArtwork";
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
	if (name == "copyTextToClipboard")
	{
		value["transport"] = QStringLiteral("ArkUI");
		value["description"] = QStringLiteral("主动复制指定文本到系统剪贴板；要求有效隐私同意且应用前台，只写不读，响应返回实际完成结果，不回显文本。CLI 文本上限 32768 字符。");
	}
	if (name == "startGuide" || name == "guideAction" || name == "getGuideState")
	{
		value["category"] = QStringLiteral("交互式天文导览");
		value["executionLayer"] = QStringLiteral("ArkUI");
		value["description"] = QStringLiteral("startGuide: solar-neighbours / deep-sky-discovery; guideAction: next, previous, pause, resume, explore, return, closer, wider, center, auto-on, auto-off, retry, stop. accepted仅受理，getGuideState返回state及lastRequestId/result核对实际完成。");
		if (name == "startGuide") value["examplePayload"] = "solar-neighbours";
		if (name == "guideAction") value["examplePayload"] = "explore";
	}
	if (name == "getAstroPanelState" || name == "setAstroTab" || name == "setAstroGroup" || name == "setAstroFilter" || name == "setAstroScroll")
	{
		value["category"] = QStringLiteral("ArkUI 天文计算");
		value["executionLayer"] = QStringLiteral("ArkUI");
		value["description"] = QStringLiteral("鸿蒙 UI 命令：先打开天文计算面板；accepted 仅表示接收，getAstroPanelState 返回最近面板状态，transitioning=false 表示切换结束而非计算完成");
		if (name == "setAstroTab") value["examplePayload"] = "5";
		else if (name == "setAstroGroup") value["examplePayload"] = "0";
		else if (name == "setAstroFilter") value["examplePayload"] = "period|morning";
		else if (name == "setAstroScroll") value["examplePayload"] = "380";
	}
	else if (name == "searchObject") value["examplePayload"] = "M31";
	else if (name == "setFOV" || name == "setFieldOfView") value["examplePayload"] = "45";
	else if (name == "setJulianDate")
	{
		value["description"] = QStringLiteral("设置模拟时间；payload 使用 jd|数值 或 mjd|数值，MJD = JD - 2400000.5");
		value["examplePayload"] = "mjd|51544.50000";
	}
	else if (name == "setLocationCoords") value["examplePayload"] = "39.9042|116.4074|43";
	else if (name == "setPluginLoadAtStartup")
	{
		value["description"] = QStringLiteral("兼容旧客户端的插件启动命令；当前内置插件统一随应用启动加载，payload 中的 0 不再关闭插件");
		value["examplePayload"] = "Satellites|1";
	}
	else if (name == "selectAt") value["examplePayload"] = "720|480|1440|960";
	else if (name == "setActionChecked") value["examplePayload"] = "actionShow_Stars|1";
	else if (name == "getConstellationArtStatus")
	{
		value["description"] = QStringLiteral("诊断当前星空文化的星座艺术文件、纹理加载和视口可见状态");
		value["examplePayload"] = "Ori";
	}
	else if (name == "getSatelliteDetail")
	{
		value["description"] = QStringLiteral("读取单颗卫星的离线身份、发射资料、当前观测、轨道参数和下一次过境");
		value["examplePayload"] = "25544";
	}
	else if (name == "getSatellitePasses")
	{
		value["description"] = QStringLiteral("使用本地 TLE 计算指定卫星未来过境；不下载数据");
		value["examplePayload"] = "{\"id\":\"25544\",\"hours\":24,\"limit\":5,\"minElevation\":10,\"visibleOnly\":true}";
	}
	else if (name == "getSatelliteSources")
	{
		value["description"] = QStringLiteral("读取卫星 TLE 来源和更新策略；远程来源在鸿蒙离线包中只保存不下载");
		value["examplePayload"] = "";
	}
	else if (name == "setSatelliteSources")
	{
		value["description"] = QStringLiteral("保存卫星 TLE 来源；支持 file/http/https，重复或含用户信息的 URL 会被拒绝");
		value["examplePayload"] = "{\"sources\":[{\"url\":\"file:///data/local/tmp/stations.tle\",\"addNew\":true}]}";
	}
	else if (name == "setSatelliteUpdateSetting")
	{
		value["description"] = QStringLiteral("设置卫星自动添加、自动删除、自动显示、更新周期和在线更新开关；鸿蒙离线包强制关闭在线更新");
		value["examplePayload"] = "{\"autoAddEnabled\":true,\"autoRemoveEnabled\":false,\"autoDisplayEnabled\":true,\"updateFrequencyHours\":72}";
	}
	else if (name == "importSatelliteTle")
	{
		value["description"] = QStringLiteral("导入本地 TLE/CSV 文件并更新卫星目录；不访问网络");
		value["examplePayload"] = "{\"paths\":[\"/data/local/tmp/stations.tle\"]}";
	}
	else if (name == "refreshSatelliteCatalog")
	{
		value["description"] = QStringLiteral("按已配置来源刷新卫星目录；鸿蒙离线包明确拒绝网络刷新，请改用本地 TLE 导入");
		value["examplePayload"] = "";
	}
	else if (name == "getObjectDetailModel")
	{
		value["description"] = QStringLiteral("读取选中天体详情媒体的 3D 模型能力契约；星座暂无已安装模型时返回 planned 和二维绘图回退");
	}
	else if (name == "getTelescopeControl")
	{
		value["description"] = QStringLiteral("读取所选 LX200 设备的传输方式和本机/局域网范围；只做校验，不建立连接");
		value["examplePayload"] = "{\"slot\":1}";
	}
	else if (name == "getTelescopeProfiles")
		value["description"] = QStringLiteral("列出 1–9 号望远镜设备槽、默认设备及当前构建可用和未移植的协议；不建立连接");
	else if (name == "saveTelescopeProfile")
	{
		value["description"] = QStringLiteral("新增或更新一个本地持久化的 LX200 TCP 设备配置；保存配置不建立连接");
		value["examplePayload"] = "{\"slot\":1,\"name\":\"LX200\",\"protocol\":\"lx200_tcp\",\"deviceModel\":\"Meade LX200 (compatible)\",\"host\":\"192.168.1.80\",\"port\":4030,\"equinox\":\"J2000\",\"commandDelayMs\":0,\"circles\":[1,2,4]}";
	}
	else if (name == "deleteTelescopeProfile" || name == "selectTelescopeProfile")
		value["examplePayload"] = "1";
	else if (name == "testTelescopeConnection")
	{
		value["description"] = QStringLiteral("仅在用户主动调用时测试所选设备的 TCP 可达性，不发送转向或同步命令；拒绝公网和未分类端点");
		value["examplePayload"] = "{\"slot\":1}";
	}
	else if (name == "getTelescopePosition")
	{
		value["description"] = QStringLiteral("用户主动读取所选望远镜的当前赤经赤纬；真实 LX200 使用 :GR/:GD，离线模拟设备返回模拟位置");
		value["examplePayload"] = "{\"slot\":1}";
	}
	else if (name == "centerScreenOnTelescope")
	{
		value["description"] = QStringLiteral("读取所选望远镜当前位置并将星图平滑居中到该位置");
		value["examplePayload"] = "{\"slot\":1}";
	}
	else if (name == "retryDeepSkyImages")
		value["description"] = QStringLiteral("重新尝试解码当前视野中失败的离线深空资料图，不重载整套图库");
	else if (name == "getNebulaTextureStatus")
		value["description"] = QStringLiteral("诊断星云纹理插件的离线配置、图片文件、解码、四角映射和运行时图层状态");
	else if (name == "listNebulaTextures")
		value["description"] = QStringLiteral("列出用户导入的星云纹理及图片、解码、映射状态；不包含内置深空图库");
	else if (name == "importNebulaTexture")
	{
		value["description"] = QStringLiteral("导入本地图片并立即刷新自定义深空纹理；省略坐标时使用当前视野中心和 FOV 建立初始映射，全程离线");
		value["examplePayload"] = "{\"sourcePath\":\"/data/storage/el2/base/files/imports/m42.png\",\"angularWidthDeg\":2.0,\"maxBrightness\":13.5}";
	}
	else if (name == "gotoNebulaTexture" || name == "removeNebulaTexture" || name == "validateNebulaTexture")
		value["examplePayload"] = "m42_20260901_120000_000.png";
	else if (name == "importScript")
	{
		value["description"] = QStringLiteral("从设备可读路径导入离线 .ssc 脚本到用户脚本目录；不执行脚本内容");
		value["examplePayload"] = "/data/local/tmp/example.ssc";
	}
	else if (name == "getSkyCultureMakerDraft")
		value["description"] = QStringLiteral("读取离线星空文化制作器草稿、撤销状态和草稿路径");
	else if (name == "saveSkyCultureMakerDraft")
	{
		value["description"] = QStringLiteral("保存完整星空文化制作器 JSON 草稿，并返回结构化校验结果");
		value["examplePayload"] = QStringLiteral("{\"id\":\"custom_example\",\"name\":\"示例星空文化\",\"author\":\"作者\",\"license\":\"CC BY 4.0\",\"region\":\"Eastern Asia\",\"classification\":[\"traditional\"],\"native_lang\":\"zh_CN\",\"constellations\":[]}");
	}
	else if (name == "addSkyCultureMakerConstellation")
		value["examplePayload"] = QStringLiteral("{\"id\":\"example\",\"english\":\"Example\",\"native\":\"示例\"}");
	else if (name == "updateSkyCultureMakerConstellation")
		value["examplePayload"] = QStringLiteral("{\"constellationId\":\"example\",\"native\":\"新名称\"}");
	else if (name == "removeSkyCultureMakerConstellation") value["examplePayload"] = "example";
	else if (name == "addSkyCultureMakerLine")
		value["examplePayload"] = QStringLiteral("{\"constellationId\":\"example\",\"hips\":[32349,30438]}");
	else if (name == "addSkyCultureMakerSelectedStar")
		value["examplePayload"] = QStringLiteral("{\"constellationId\":\"example\",\"lineIndex\":0}");
	else if (name == "importSkyCultureMakerArtwork")
	{
		value["description"] = QStringLiteral("把本地图片复制到星空文化草稿并关联指定星座；全程离线，返回图片尺寸和草稿");
		value["examplePayload"] = QStringLiteral("{\"constellationId\":\"example\",\"sourcePath\":\"/data/storage/el2/base/files/imports/example.png\"}");
	}
	else if (name == "setSkyCultureMakerArtworkAnchor")
	{
		value["description"] = QStringLiteral("设置艺术图的三个像素锚点之一；可传 hip，省略时使用星图当前选中的 HIP 恒星");
		value["examplePayload"] = QStringLiteral("{\"constellationId\":\"example\",\"anchorIndex\":0,\"x\":120,\"y\":80,\"hip\":32349}");
	}
	else if (name == "removeSkyCultureMakerArtwork")
		value["examplePayload"] = QStringLiteral("{\"constellationId\":\"example\"}");
	else if (name == "validateSkyCultureMakerDraft")
		value["description"] = QStringLiteral("严格校验文化元数据、年代、星座 ID、折线和本地 HIP 星表引用；payload 留空时校验已保存草稿");
	else if (name == "exportSkyCultureMaker")
		value["description"] = QStringLiteral("在应用用户目录导出标准 Stellarium 星空文化 ZIP，包含 index.json、description.md 和可继续编辑的草稿");
	else if (name == "importSkyCultureMaker")
	{
		value["description"] = QStringLiteral("从设备可读路径导入标准 Stellarium 星空文化 ZIP 为离线草稿");
		value["examplePayload"] = "/data/storage/el2/base/files/imports/example.zip";
	}
	else if (name == "getScriptList")
	{
		value["description"] = QStringLiteral("列出内置和用户脚本；默认返回完整元数据，payload=summary 只返回文件名和数量，适合日志传输");
		value["examplePayload"] = "summary";
	}
	else if (name == "getScriptCaptions")
		value["description"] = QStringLiteral("读取脚本运行时的已本地化屏幕字幕；鸿蒙端由 ArkUI 在安全区内统一显示");
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
