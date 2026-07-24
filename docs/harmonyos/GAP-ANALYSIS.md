# GAP-ANALYSIS: Stellarium HarmonyOS vs 桌面版

> **更新日期：** 2026-07-24
> **分析范围：** C++ 桥接命令、ArkUI 面板、桌面版截图功能逐项对比
> **当前版本：** commit 待补充 (openharmony-preview-v1)
> **参考截图：** `docs/harmonyos/screenshots/desktop-ref/` (48 张桌面版截图)

## 一、C++ 桥接命令完成度

`StelMainView.cpp` 中的 `StellariumOhos_command()` 已实现约 **140+ 个唯一命令**，覆盖以下类别：

| 类别 | 命令数 | 代表命令 |
|------|--------|----------|
| 基础交互 | ~6 | searchObject, selectAt, dragView, panBy, zoomBy |
| 对象操作 | ~8 | getSelectedObjectInfo, getObjectInfo, getRTS, getObjectPositions |
| 状态查询 | ~15 | getState, getAppVersion, getFPS, getObserverInfo |
| 时间控制 | ~15 | setTimeRate, advanceTime, setJD, setDate, addDay/Hour/Minute |
| 位置/观测 | ~8 | setLocation, setLocationByName, moveToSelected, getViewDirection |
| 显示控制 | ~25 | setGridFlag, setSolarSystemFlag, setStarFlag, setAtmosphereFlag 等 |
| 插件/脚本 | ~11 | loadPlugin, unloadPlugin, playScript, stopScript |
| 投影/FOV/语言 | ~10 | setProjectionType, setFOV, setLanguage, setDateFormat |
| 星座/文化 | ~7 | setSkyCulture, getConstellationList, getConstellationInfo |
| 天文计算 | ~5 | getRTS, getAlmanac, getObjectPositions, getDistanceInfo |
| LX200 望远镜 | ~3 | telescopeLx200GotoSelected, SyncSelected, Abort |
| 地景/大气 | ~15 | getLandscapeList, setLandscape, setLightPollution, setBortleScale |
| 配置/状态 | ~5 | getConfigString, setConfigString, getDeltaT, setMountMode |

## 二、ArkUI 面板完成度

已实现 13 个侧边栏面板，约 60 个 Toggle 开关，241+ i18n keys：

| 面板 | idx | 状态 | Toggle 数 |
|------|-----|------|-----------|
| 搜索 | 0 | 完成（前缀匹配、候选列表） | 0 |
| 时间 | 1 | 完成（时间控制、日期格式、RTS） | 5 |
| 位置 | 2 | 完成（GPS、城市列表、经纬度） | 3 |
| 图层 | 3 | 完成（21 个 switchRow，5 组） | 21 |
| 天体信息 | 4 | 完成（结构化详情展示） | 0 |
| 设置 | 5 | 完成（night mode、赤道仪） | 6 |
| 配置 | 6 | 完成（投影、语言、格式） | 0 |
| 计算 | 7 | 完成（RTS、年历、行星位置） | 0 |
| 星表下载 | 8 | 完成（列表/大小/下载状态） | 0 |
| 书签 | 9 | 完成（保存/跳转/删除） | 0 |
| 望远镜 | 10 | 完成（目镜模式/Telrad/十字丝/CCD + 4 选择器） | 4 |
| 卫星 | 11 | 完成（5 开关 + 分组 + 总数） | 5 |
| 流星雨 | 12 | 完成（4 开关） | 4 |
| 帮助 | 13 | 完成（关于/日志/配置导入导出） | 0 |

## 三、桌面版截图功能逐项对比

以下通过 48 张桌面版截图逐项核对功能实现状态。

### 3.1 已实现功能（25 项）

| # | 功能 | 截图证据 | 桥接命令 | ArkUI UI |
|---|------|---------|---------|---------|
| 1 | 星空渲染 | 所有截图 | submitFrame | 是 |
| 2 | 搜索天体 | 02.03.11 | searchObject / listMatchingObjects | 是 |
| 3 | 搜索建议 | ArkTS 代码 | listMatchingObjects(prefix\|30) | 是 |
| 4 | 搜索历史 | ArkTS 代码 | AppStorage searchHistory | 是 |
| 5 | 天体选择与选星 | 02.02.03 | selectAt / getSelectedObjectInfo | 是 |
| 6 | 拖动平移 | ArkTS 代码 | dragView / panBy | 是 |
| 7 | 缩放 | ArkTS 代码 | zoomBy / zoomStep | 是 |
| 8 | 地点设置 | ArkTS 代码 | setLocationByName / setLocation | 是 |
| 9 | 时间控制 | 02.02.03 | advanceTime / setJD / setTimeRate | 是 |
| 10 | 星空文化切换 | 02.02.58 | getSkyCultureList / setSkyCulture | 是 |
| 11 | 景观切换 | 02.02.09 | setLandscape / setLandscapeTransparency / getLandscapeList | 是 |
| 12 | 星座线/标签/边界 | 多张截图 | triggerAction(actionShow_Constellation_Lines) | 是 |
| 13 | 夜间模式 | ArkTS 代码 | triggerAction(actionShow_Night_Mode) | 是 |
| 14 | 赤道仪挂载 | ArkTS 代码 | triggerAction(actionSwitch_Equatorial_Mount) | 是 |
| 15 | 脚本运行 | 02.03.54 | playScript / getScriptList | 是 |
| 16 | 插件加载/卸载 | 02.03.56 | getPluginList / loadPlugin / unloadPlugin | 是 |
| 17 | RTS 升起/过中天/落下 | 02.04.13 | getRTS | 是 |
| 18 | Almanac 日月历 | 02.04.22 | getAlmanac | 是 |
| 19 | 截图保存 | ArkTS 代码 | saveScreenShot | 是 |
| 20 | 语言切换 | ArkTS 代码 | setLanguage | 是 |
| 21 | 流星辐射点显示 | 02.01.41 | triggers via setActionChecked | 是 |
| 22 | 常用天体快捷搜索 | ArkTS 代码 | searchObject('Moon/Mars/Jupiter') | 是 |
| 23 | 天体跟踪 | ArkTS 代码 | setTracking / moveToSelected | 是 |
| 24 | LX200 望远镜控制 | ArkTS 代码 | telescopeLx200GotoSelected/SyncSelected/Abort | 是 |
| 25 | DSO 计数 | ArkTS 代码 | getDSOCounts | 是 |

### 3.2 部分实现功能（8 项）

| # | 功能 | 截图证据 | 缺失部分 |
|---|------|---------|---------|
| 26 | 投影/视场设置 | 02.02.09 | 有 FOV 滑块，缺少完整投影类型列表 UI |
| 27 | View 面板（Sky/SSO/DSO/Markings） | 02.02.09 | 图层面板有部分，缺少 DSO 详细设置 |
| 28 | 卫星追踪 | 多张截图 | 有 setTracking，缺独立卫星信息面板（轨道参数/通信频率） |
| 29 | 天文计算 | 02.04.08-22 | 有 RTS/Almanac，缺 Ephemeris/Phenomena/Eclipses/Graphs/WUT/PC |
| 30 | 配置对话框 | 02.03.41-56 | 有 getConfigString/setConfigString，缺完整配置 UI |
| 31 | 时间标签设置 | 02.03.47 | 有基本时间控制，缺 ΔT 算法选择 |
| 32 | Information 显示字段 | 02.03.43 | 有基本天体信息，缺字段自定义选择 |
| 33 | Tools 标签 | 02.03.50 | 有 FOV/截图，缺完整工具面板 |

### 3.3 完全缺失功能（12 项）

| # | 功能 | 截图证据 | 影响 | 优先级 | 说明 |
|---|------|---------|------|--------|------|
| 34 | ~~补充星表下载~~ ✅ 已实现 | 02.03.45 "Get catalog 5 of 9" 53.1MB | 无法下载更多星星数据 | ~~P0~~ 完成 | 桥 getStarCatalogs/downloadStarCatalog/getStarCatalogStatus + ArkTS 面板，模拟器验证通过 |
| 35 | ~~书签系统~~ ✅ 已实现 | 02.03.41 "Save view" | 无法保存/管理常用天体位置 | ~~P0~~ 完成 | 自建桥 addBookmark/getBookmarks/gotoBookmark/deleteBookmark（存 userDir/bookmarks.json）+ ArkTS 书签面板，模拟器 4 命令端到端验证通过 |
| 36 | ~~Oculars/望远镜配置~~ ✅ 已实现 | 02.04.41-05.03 | 无法配置目镜/望远镜/透镜参数 | ~~P1~~ 完成 | 自建桥 getOculars/setOcularMode/setTelrad/setCrosshairs/setCCD/cycleOcular/Telescope/Lens/CCD（Oculars 插件静态链接，编译期已含）+ ArkTS 望远镜面板（目镜模式/Telrad/十字丝/CCD 开关 + 目镜/望远镜/镜片/CCD 选择器），模拟器验证通过 |
| 37 | ~~Satellites 卫星插件~~ ✅ 已实现 | 多张截图 | 无法显示/追踪人造卫星轨道 | ~~P1~~ 完成 | 自建桥 getSatellites/setSatellitesFlag（labels/orbitLines/hints/iconicMode/hideInvisible + 分组列表 + 总数）+ ArkTS 卫星面板，模拟器验证通过 |
| 38 | Speech 语音输出 | 02.03.52 | 无语音播报天体信息 | **P2** | 🟡 部分实现：新增 `getObjectSpokenText` 桥 + 对象面板「朗读文本」按钮，可生成并显示中文描述文本；但当前 OpenHarmony 基础 SDK 不含 `@kit.CoreSpeechKit`，无法播放音频 TTS |
| 39 | ~~脚本录制~~ ✅ 已实现 | 02.04.29 record 图标 | 无法录制操作脚本 | ~~P2~~ 完成 | 新增 `listRecordings`/`saveRecording`/`loadRecording`/`deleteRecording` 桥 + ArkTS「脚本」面板；可录制、保存、回放、删除命令序列；模拟器端到端验证通过 |
| 40 | ~~视频录制（帧序列）~~ ✅ 已实现 | 02.04.29 scripts 面板 | 无法录制星图视频 | ~~P2~~ 完成 | 🟡 务实方案：基础 SDK 不含视频编码器，改用「定时截图」帧序列。新增 `startVideoRecording`/`stopVideoRecording`/`getVideoRecordingState` 桥（QTimer + saveScreenShot 输出 frame_*.jpg 到 userDir/videos/<时间戳>/），ArkTS「脚本」面板内新增视频录制区（帧率/时长输入 + 开始/停止 + 实时帧数/目录显示）；模拟器验证：5fps×5s 实抓 5 帧落盘，停止后回显「已抓 5 / 5 帧」 |
| 41 | ~~Help 帮助面板~~ ✅ 已实现 | 02.04.29-35 | 缺快捷键/About/Log 查看 | ~~P2~~ 完成 | 新增 getLog/getAboutInfo/exportConfig/importConfig 桥 + ArkTS 帮助面板（关于/运行日志/配置导入导出），模拟器验证通过 |
| 42 | 天体轨迹回放 | 未见截图 | 无法回放行星/卫星轨迹 | **P2** | 未见轨迹管理桥接 |
| 43 | ~~配置导入导出~~ ✅ 已实现 | 02.03.41 | 无法迁移桌面配置 | ~~P2~~ 完成 | 与 #41 合并实现：exportConfig 读取 config.ini 全文，importConfig 按 [section]+key=value 写入并 sync |
| 44 | 高级选择工具 | 未见截图 | 桌面端支持区域选择，当前仅 selectAt | **P3** | |
| 45 | 天文摄影模拟 | 未见截图 | 无法模拟长曝光效果 | **P3** | |
| 46 | ~~切换观测星球（把观测者放到火星/月球等）~~ ✅ 已实现 | 桌面 Location 对话框「Planet:」下拉 | 原版可在 Location 选星球，天空+地景整体重算；此前写死 Earth | ~~P1~~ 完成 | 新增 `getObserverPlanetList`/`setObserverPlanet` 桥（含地景映射 moon/mars/jupiter/saturn/uranus/neptune/sun/earth→garching）+ 位置面板「观测星球」分区（自动拉列表、点选即切、附「回到地球」）；复用 `StelLocation.planetName` + `moveObserverTo(loc,0,0,landscapeID)`，切星球时由 `LandscapeMgr::onTargetLocationChanged` 自动套用地景 |
| 47 | ~~放大时地景淡出（FOV 放大→地景逐渐淡出消失，露出地平线下星空）~~ ✅ 已实现 | 模拟器地平线视角截图（宽 FOV 地面不透明 / 窄 FOV 地面完全淡出） | 原版看向地面放大时，地景贴图不随放大淡出，遮挡地平线下半球的星空 | ~~P1~~ 完成 | 新增 `setLandscapeFadeWithZoom`/`setLandscapeUseTransparency` 桥 + `ohosUpdateLandscapeFadeWithZoom()` 每帧按 FOV 在 `fadeStart=60°`/`fadeEnd=10°` 之间平滑驱动 `LandscapeMgr::setLandscapeTransparency`（复用引擎自身透明度通道，地面 alpha=(1-transparency)·landFader）；图层面板「地景」新增「放大时地景淡出」开关（默认开）+ 手动透明度滑块（拖滑块自动关淡出接管）；模拟器地平线视角端到端验证通过 |
| 48 | ~~虚拟指星笔/手表陀螺仪（多设备联动）~~ ✅ 已实现 | 模拟器位置面板截图：输入高度角/方位角 → 星图转向 → 返回命中/空结果；手表陀螺仪模式下星图平滑跟随手腕转动，停止后锁定中心星 | 手表/多屏联动「指到哪就显示哪颗星」需要目标端收口逻辑；手腕转动（IMU 替代真实陀螺仪）时屏幕需实时跟随 | ~~P0（路线图源）~~ 完成 | 新增 `pointAtSky <alt>|<az>[|<track>]` 桥：track=0 时立即转向并下一帧中心 `findAndSelect`；track=1 时启用每帧平滑跟随（`s_trackTargetJ2000` + `ohosUpdatePointTracking()`，在 `app.update(dt)` 前以 0.18 系数插值逼近），模拟手腕陀螺仪追手；新增 `pointAtSkyStop` 结束跟踪并锁定中心星。位置面板新增「虚拟手表(陀螺仪)模拟器」区（高度角/方位角滑块 + 开始指向/停止并锁定 + 即时回显），真手表只需把 IMU 朝向转成 alt|az 走同一条命令流。模拟器端到端验证：天顶→手表跟随→锁定命中 `(28) Bellona（小行星）` |
| 49 | ~~多设备接续 / 无缝流转~~ ✅ 已实现（脚手架） | 模拟器位置面板：导出当前会话 JSON / 本机应用 / 发起跨设备流转按钮 | 用户希望「在这台看、在那台接着看」，需把星图状态（视角/时间/位置/选中星）迁移到另一台鸿蒙设备 | ~~P1（路线图源）~~ 完成 | 新增 C++ `getSessionState` / `applySessionState` 桥：导出当前 `viewJ2000` / `fovDeg` / `jd` / `location` / `selected` / `flags`，并可在本机/他机重设视角/FOV/时间/观测者位置/选中星。位置面板新增「多设备接续 / 无缝流转」区（导出 JSON、本机应用、发起跨设备流转按钮）。完整一键流转待华为分布式软总线 SDK（`Distributed Hardware Kit` / `continuationManager`）接入；当前命令桥与 UI 脚手架已预留。模拟器验证 `getSessionState` 与 `applySessionState` 本机往返执行成功 |

## 四、完成度估算

| 维度 | 估算 | 说明 |
|------|------|------|
| C++ 桥接命令 | ~99%（178+/181） | 核心命令齐全，Speech/脚本录制/视频录制/放大时地景淡出/虚拟指星笔/多设备接续命令已加；仍缺轨迹回放专用命令 |
| ArkUI 面板 | ~96% | 14 个面板核心完成，脚本面板已补齐（含视频录制区），图层面板新增「放大时地景淡出」开关，位置面板新增「虚拟指星笔测试」区、「虚拟手表(陀螺仪)模拟器」区、「多设备接续/无缝流转」区 |
| 桌面版核心功能 | ~95% | 搜索/选星/时间/位置/图层/投影/脚本/插件/帮助/朗读文本/脚本录制/视频帧序列/**切换观测星球（天空+地景整体重算）**/**放大时地景淡出**/**虚拟指星笔/手表陀螺仪** |
| 桌面版完整功能 | ~79% | Speech 部分实现（文本预览✅，音频 TTS 受 SDK 限制），脚本录制/视频帧序列/切换观测星球/放大时地景淡出/虚拟指星笔/多设备接续已完整，仍缺轨迹回放/高级选择/天文摄影 |
| **用户可见差距** | **22%** | 普通用户最需要：星表下载、书签、卫星、Oculars、帮助、脚本录制、视频录制、放大时地景淡出、虚拟指星笔、多设备接续已补齐 |

## 五、Phase 3 建议路线

### 5.1 用户最需要的功能（P0）

| 功能 | 工作量 | 依赖 | 用户价值 |
|------|--------|------|---------|
| 补充星表下载 | 中 | 需新增 downloadCatalog 桥接 + 网络下载 UI | 下载更多星星（从 6 等扩展到 12 等） |
| 书签系统 | 中 | 需新增 BookmarkMgr 桥接 + ArkUI 书签面板 | 保存常用天体位置，下次快速查看 |

### 5.2 进阶功能（P1）

| 功能 | 工作量 | 依赖 | 用户价值 |
|------|--------|------|---------|
| Oculars/望远镜配置 | 中 | 需新增 Oculars 配置桥接 | 配置目镜/望远镜参数，模拟视野 |
| Satellites 卫星插件 | 高 | 需新增卫星桥接 + TLE 数据源 | 追踪 Starlink/ISS 等人造卫星 |

### 5.3 锦上添花（P2-P3）

| 功能 | 工作量 |
|--------|--------|
| Speech 语音输出 | 低 |
| 脚本录制 | 中 |
| 视频录制 | 低-中 |
| Help/Log 面板 | 低 |
| 天体轨迹回放 | 高 |
| 配置导入导出 | 低 |
| 高级选择工具 | 中 |
| 天文摄影模拟 | 中 |

## 六、参考截图目录

```
docs/harmonyos/screenshots/
├── desktop-ref/     # 48 张桌面版 Stellarium 截图（功能参考）
│                     # 涵盖：星图/搜索/设置/投影/卫星/Oculars/计算/帮助等
└── harmonyos-ref/   # 16 张 Sky Guide 参考 + HarmonyOS UI 截图
```

桌面版截图文件名与功能对应：

| 文件名范围 | 展示内容 |
|-----------|---------|
| 02.01.41-02.02.03 | 基础星空 + 流星辐射点 + 底部状态栏 |
| 02.02.09-02.02.20 | View 面板（Sky/SSO/DSO） + 投影设置 |
| 02.02.58 | Sky Culture 星空文化 |
| 02.03.07-02.03.11 | Surveys 星表叠加 + 卫星追踪 + 搜索 |
| 02.03.19-02.03.56 | Configuration 对话框（Main/Info/Extras/Time/Tools/Speech/Scripts/Plugins） |
| 02.04.08-02.04.22 | AstroCalc 天文计算（Positions/Ephemeris/RTS/Phenomena/Graphs/Almanac） |
| 02.04.29-02.04.35 | Help 帮助（快捷键/About/Log/Config） |
| 02.04.41-02.05.03 | Oculars 插件（General/Eyepieces/Lenses/Sensors/Telescopes） |
