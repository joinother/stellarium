# GAP-ANALYSIS: Stellarium HarmonyOS vs 桌面版

> **更新日期：** 2026-07-22
> **分析范围：** C++ 桥接命令、ArkUI 面板、桌面版功能对比
> **当前版本：** commit 260c379c22 (openharmony-preview-v1)

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

## 三、与桌面版差距

### 3.1 确认缺失（按优先级）

| # | 缺失项 | 影响 | 优先级 | 说明 |
|---|--------|------|--------|------|
| 1 | 书签系统 | 无法保存/管理常用天体位置 | P0 | 桌面版有完整书签管理；未见桥接命令 |
| 2 | Satellites 卫星插件 | 无法显示/追踪人造卫星 | P1 | 桌面版内置卫星插件 |
| 3 | 视频录制 | 无法录制星图视频 | P1 | 未见 saveVideo 命令 |
| 4 | 天体轨迹回放 | 无法回放行星/卫星轨迹 | P1 | 需桌面端轨迹数据模型 |
| 5 | 配置导入导出 | 无法迁移桌面配置 | P1 | 有 getConfigString 但无整体导入导出 |
| 6 | DSO 星表完整过滤 | 深空天体筛选不完整 | P2 | 有 getDSOCounts 但缺详细分类 |
| 7 | AstroCalc 完整计算 | 星历/日食/月食计算不完整 | P2 | 有部分桥接，缺完整 AstroCalcDialog |
| 8 | 翻译文件加载异常 | 切换语言后部分星名不变化 | ✅已修复 | 资源提取残数据（marker 门控 + `hdc install -r` 保留旧数据）→ 加自愈抽取 + 可观测日志（commit fdd8f627df） |

### 3.2 待核对项目

| 缺失项 | 说明 |
|--------|------|
| 太阳系轨道可视化细节 | 有 orbits 开关，可能缺更多选项 |
| 自定义星图颜色/主题 | 未见专门接口 |
| 高级选择工具 | 桌面端支持区域选择，当前仅 selectAt |
| 文件系统操作 | 桌面端 StelFileMgr，鸿蒙走 rawfile |
| 天文摄影/长曝光模拟 | 未见相关命令 |

## 四、完成度估算

| 维度 | 估算 |
|------|------|
| C++ 桥接命令 | ~85%（140+/170） |
| ArkUI 面板 | ~80%（核心完成，细节待补） |
| 桌面版核心功能覆盖 | ~85%（搜索/选星/时间/位置/图层/投影/脚本/插件） |
| 桌面版完整功能覆盖 | ~65%（缺书签/卫星/录制/轨迹/高级计算） |

## 五、Phase 3 建议路线

| 优先级 | 功能 | 工作量 |
|--------|------|--------|
| P0 | 书签系统（BookmarkMgr 桥接 + ArkUI） | 中 |
| ✅P1 | 翻译文件加载修复（已完成，commit fdd8f627df） | 低 |
| P1 | Satellites 卫星插件 | 高 |
| P1 | 视频录制 | 低-中 |
| P1 | 天体轨迹回放 | 高 |
| P2 | 配置导入导出 | 低 |
| P2 | DSO 星表完整过滤 | 中 |
| P2 | AstroCalc 完整数据计算 | 高 |
