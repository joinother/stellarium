# GAP-ANALYSIS: Stellarium HarmonyOS vs 桌面版

> **更新日期：** 2026-07-23
> **分析范围：** C++ 桥接命令、ArkUI 面板、桌面版截图功能逐项对比
> **当前版本：** commit 260c379c22 (openharmony-preview-v1)
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

已实现 9 个侧边栏面板，47 个 Toggle 开关，241+ i18n keys：

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
| 帮助 | 8 | 完成 | 0 |

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
| 34 | **补充星表下载** | 02.03.45 "Get catalog 5 of 9" 53.1MB | 无法下载更多星星数据 | **P0** | 桌面版支持下载 9 个额外星表（至 12 等），鸿蒙端未见 downloadCatalog bridge |
| 35 | 书签系统 | 02.03.41 "Save view" | 无法保存/管理常用天体位置 | **P0** | 未见 saveBookmark/addBookmark 桥接 |
| 36 | Oculars/望远镜配置 | 02.04.41-05.03 | 无法配置目镜/望远镜/透镜参数 | **P1** | 仅有 LX200 控制，缺 Oculars 插件完整配置面板 |
| 37 | Satellites 卫星插件 | 多张截图 | 无法显示/追踪人造卫星轨道 | **P1** | 未见 getSatellites/getSatelliteInfo 桥接 |
| 38 | Speech 语音输出 | 02.03.52 | 无语音播报天体信息 | **P2** | 未见 speech/speak 桥接 |
| 39 | 脚本录制 | 02.04.29 record 图标 | 无法录制操作脚本 | **P2** | 有 playScript 但缺 recordScript |
| 40 | 视频录制 | 未见截图 | 无法录制星图视频 | **P2** | 未见 saveVideo 桥接 |
| 41 | Help 帮助面板 | 02.04.29-35 | 缺快捷键/About/Log 查看 | **P2** | 未见 help/getLog 桥接 |
| 42 | 天体轨迹回放 | 未见截图 | 无法回放行星/卫星轨迹 | **P2** | 未见轨迹管理桥接 |
| 43 | 配置导入导出 | 02.03.41 | 无法迁移桌面配置 | **P2** | 有 getConfigString 但无整体导入导出 |
| 44 | 高级选择工具 | 未见截图 | 桌面端支持区域选择，当前仅 selectAt | **P3** | |
| 45 | 天文摄影模拟 | 未见截图 | 无法模拟长曝光效果 | **P3** | |

## 四、完成度估算

| 维度 | 估算 | 说明 |
|------|------|------|
| C++ 桥接命令 | ~85%（140+/170） | 核心命令齐全，缺星表下载/卫星/Oculars/Speech |
| ArkUI 面板 | ~80% | 9 个面板核心完成，缺 Oculars/Help 配置面板 |
| 桌面版核心功能 | ~85% | 搜索/选星/时间/位置/图层/投影/脚本/插件 |
| 桌面版完整功能 | ~60% | 缺星表下载/书签/Oculars/卫星/Speech/录制/帮助 |
| **用户可见差距** | **40%** | 普通用户最需要：星表下载、书签、卫星、Oculars |

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
