# Stellarium HarmonyOS 与开源桌面版差距报告

> 更新日期：2026-08-24
> 对比基线：当前仓库提交 `c6393b27aa`，以及同一工作区中的桌面版源码
> 结论类型：源码和构建产物核对；未把“编译成功”当作“用户功能完成”

## 三维项目对比与交互取舍

本节专门区分三维行星观察、真实星空观测和大型科学可视化，避免把不同项目的目标混为一谈。

| 项目 | 核心定位 | 适合本项目借鉴的内容 | 不适合直接移植的内容 |
| --- | --- | --- | --- |
| Stellarium | 以观测者为中心的真实星空模拟器，强调地点、地平坐标、天文计算、望远镜和插件 | 当前应用的计算核心、星图、选星、跟踪、FOV、时间和地点交互 | 不直接提供 Celestia 式的自由飞行宇宙相机 |
| Celestia | 自由飞行式三维宇宙浏览器，可在行星、恒星和星系之间移动 | 三维场景层级、行星近景相机、卫星/轨道组织、天体资源加载 | 另一套天体数据库、相机状态和交互体系；整体移植会扩大工程和资源风险 |
| OpenSpace | 面向天文馆、教学展示和科学可视化的大型平台 | 时间线、讲解式场景、数据可视化和多层数据组织 | 体量、依赖和运行环境都偏重，不适合直接移植到鸿蒙 |
| Cosmonium | 基于 Python/Panda3D 的桌面三维宇宙探索程序，部分兼容 Celestia 插件 | 桌面三维场景和 Celestia 资源兼容思路 | Python/Panda3D 运行时和桌面 OpenGL 依赖，不适合作为鸿蒙基础 |

### 交互结论

Celestia Mobile 的价值主要在三维引擎和场景组织，不在于必须照搬它的触摸交互。它沿用自由飞行/相机控制思路，部分手势和控制层级不符合本项目当前的 Pad 观测工作流；评估中不应把“能实现三维”误判为“交互适合用户”。

Stellarium 本身已有完整的观测交互：鼠标拖动平移、滚轮和双指捏合缩放、点击选星、Space 居中/跟踪、`/` 自动放大、`\` 缩小、键盘控制和时间操作。鸿蒙端应继续以这些语义为基础，只优化触摸反馈、惯性、Dock 和面板布局，不替换成 Celestia Mobile 的飞行模式。

### 三维行星功能边界

- `Planet::drawSphere()` 已提供带纹理、光照、阴影的行星球体绘制，但它属于普通星图渲染流程，不等于独立的“三维行星模式”。
- 桌面版的“使用更精确的三维模型（如果有）”只是太阳系显示选项；OBJ 开关默认关闭，且模型资源必须存在，否则会回退到球体绘制。
- 行星轨道开关控制的是星图中的轨道线，不是围绕选中行星自由旋转的三维轨道场景。
- 后续应在 Stellarium 核心上增加“行星近景观察”入口：选中后居中、FOV 缩放、旋转/拖动、受光面、卫星和轨道开关，并保留代表选中范围的视场框。

### 实施原则

1. Stellarium 继续负责天文计算、星图和主交互。
2. Celestia 只作为三维相机、行星场景层级和资源加载的技术参考。
3. 不整体引入 Celestia 的数据库、UI 或移动端控制层。
4. 每个新增三维控制都必须同时支持触摸、键鼠和 CLI 命令，且不破坏普通星图模式。

## 结论

当前鸿蒙版的核心观星、天体搜索、时间/地点、图层、星空文化、天文计算、卫星、目镜、脚本、书签和会话状态等主流程已经移植。当前最大的差距不是 C++ 算法，而是桌面插件的 GUI 入口和部分资源没有移植。

另一个必须在正式发布前处理的事项是离线边界：当前 HAP 未声明 `ohos.permission.INTERNET`，但若干插件的网络代码仍然编译保留。它降低了实际联网能力，但不能证明源码层面“绝对不会联网”。

## P0：发布前必须处理

### 1. 离线构建仍保留网络代码

- `docs/harmonyos/NETWORK-INVENTORY.md` 已记录 HiPS/TOAST、OnlineQueries、卫星更新、目录更新、MPC 导入、Planes、RemoteControl 和 RemoteSync 等网络或局域网能力。
- 当前策略是默认关闭、无公网权限，而不是统一编译期禁网。
- 对未备案版本，建议增加统一的 OHOS 离线编译门禁：网络插件不编译，远程控制/同步不注册，在线巡天入口不生成；同时保留数据源和权限检查的构建测试。

### 2. Scenery3d 编译了但资源不完整

- `build/CMakeCache.txt` 中 `USE_PLUGIN_SCENERY3D=1`，说明插件参与构建。
- 桌面版场景资源位于 `scenery3d/`，包括 OBJ、MTL、纹理和 `scenery3d.ini`。
- 当前 HAP rawfile 中未发现 `scenery3d/` 场景目录，也没有对应的 OBJ/MTL 模型资源，因此无法认为 3D 地景可用。
- 鸿蒙端也没有 Scenery3d 的专用控制面板；仅有通用插件开关不能替代桌面版的场景选择、视点、阴影和渲染设置。

## P1：核心移植差距

### 1. 已编译插件缺少鸿蒙操作入口

桌面版在 `CMakeLists.txt:580-616` 启用了以下插件，但鸿蒙端当前主要只有通用插件列表开关，未提供对应的桌面配置窗口或操作面板：

- 角度测量、考古线、历法、均时差、系外行星；
- 拼接相机、导航星、星云纹理、天体可见性；
- 平面、指针坐标、脉冲星、类星体、新星和超新星；
- 远程控制、远程同步、3D 地景；
- 星空文化制作器、太阳系编辑器、时间导航器、镜头畸变估算器。

其中部分插件的数据对象或绘制模块可能已经能工作，但没有用户可达的设置和操作流程，仍应按“部分移植”验收，而不是按“完成”验收。

### 2. Oculars 仍不是桌面版完整功能

当前鸿蒙端已有目镜、望远镜、镜片、CCD 选择，以及 Telrad、十字丝和 CCD 开关。桌面版还包括视场旋转、棱镜旋转、传感器裁剪、像素网格、调焦器叠加和更完整的设备参数编辑，这些尚未形成鸿蒙端对应 UI。

### 3. AstroCalc 仍需按桌面字段逐项验收

当前页面已经覆盖位置、星历、升降、天象、图表、今晚、行星、日月食、年历和月相等入口，并加入了选星引导、加载状态和 CSV 导出。剩余风险集中在：

- Graphs 的所有横纵轴组合、筛选条件和曲线显示是否与桌面版逐项一致；
- WUT 表格的字段、可见性判断和本地时间格式；
- 桌面版部分表格的排序、分页、复制和导出细节。

这部分不能只靠源码命令数量判断，需建立固定日期、地点、天体和时区的结果对照测试。

### 4. 3D 资源和高清图像需要独立打包验收

深空图像目前已进入 rawfile，但资源存在“文件在包内、对象映射不正确或 UI 未命中”的风险。应为 M31、玫瑰星云及其他重点对象建立资源清单，逐个验证：对象 ID、纹理路径、包内路径、加载结果和屏幕显示是否对应。

## P2：桌面高级工具与设备能力

以下项目属于开源桌面版能力，但不应在当前未备案离线版本中直接打开：

- 在线百科和在线查询：Qt WebEngine 不可用，OnlineQueries 还会访问外部服务；
- 在线巡天：HiPS、TOAST/DSS 目录和图像瓦片需要网络；
- MPC 小行星/彗星在线导入；
- GPS/自动定位；
- INDI/串口望远镜控制；当前 `ENABLE_INDI=0`、`USE_PLUGIN_TELESCOPECONTROL=0`；
- 语音播放、Qt Multimedia、ShowMySky、XLSX 导入导出和 NLS 构建。

这些不是普通的“忘了做”，而是受 OHOS Qt 组件、外部服务或当前离线发布策略限制。若以后恢复，必须单独设计权限、隐私同意、超时、失败回退和数据授权说明。

## 已完成或基本对齐

- 核心星空渲染、星座和深空天体显示；
- 搜索、候选、选星、跟踪、拖动、捏合缩放和 FOV 控制；
- 时间棘轮、时间流逝、地点选择、北京兜底和观测星球切换；
- 图层、地景、地景随视场淡出、星空文化浏览和文化绘图资源预览；
- 天文计算主要页签、选星引导、加载控件、结果表格和 CSV 导出；
- 星表、书签、卫星、流星雨、Oculars 基础模式、脚本和帧序列录制；
- 配置导入导出、帮助/日志、虚拟指星和会话状态导出/恢复。

这些项目仍需在平板上做回归测试，但从当前桥接命令和 ArkUI 入口看，不属于本轮优先补齐的“功能空白”。

## 建议实施顺序

1. 先增加离线构建门禁和网络能力回归检查，避免未备案包留下可触发的联网路径。
2. 补齐 Scenery3d 场景资源打包，再做鸿蒙 3D 地景入口；先验证模型、纹理、视点和渲染稳定性。
3. 移植角度测量、历法、均时差、时间导航器等不依赖联网的高价值工具入口。
4. 把太阳系编辑器拆成离线子集，仅保留本地轨道元素管理；在线 MPC 导入继续隐藏。
5. 用固定测试数据逐项核对 AstroCalc Graphs、WUT 和表格导出。
6. 最后再评估需要网络、设备或额外 Qt 组件的桌面高级功能。

## 证据位置

- 开源插件开关：`CMakeLists.txt:580-616`
- 当前 OHOS 构建开关：`build/CMakeCache.txt:366-410`、`build/CMakeCache.txt:788-882`
- 插件列表桥：`src/StelMainView.cpp:3932-3965`
- 鸿蒙插件列表 UI：`harmonyos/ets-source/pages/MainWindowNativeNode.ets:5506-5533`、`harmonyos/ets-source/pages/MainWindowNativeNode.ets:14500-14536`
- 网络台账：`docs/harmonyos/NETWORK-INVENTORY.md:7-15`
- 主动关闭项说明：`docs/harmonyos/workbuddy/phase2/stellarium-ohos-port/patches/FEATURES_DISABLED.md:16-26`

## 脚本环境调查

仓库中的“脚本”不是同一种运行环境，移植时必须分别处理：

| 类型 | 运行环境 | 用途 | 是否属于 App 功能 |
| --- | --- | --- | --- |
| `scripts/*.ssc` | Stellarium C++ 内嵌 Qt 6 `QJSEngine`；Qt 6 构建会启用 `ENABLE_SCRIPT_QML=1`，这里的 QML 指 Qt 的脚本模块，不是 ArkUI 页面 | 控制时间、视角、地点、图层、选星和截图，制作天文演示与巡天导览 | 是，属于应用内置脚本 |
| `scripts/*.inc` | 由 Stellarium `.ssc` 预处理器展开 | 共享天体列表、翻译、状态保存等代码 | 是，属于脚本依赖 |
| `scripts/tests/*.ssc` | 同一个 QJSEngine/脚本测试环境 | 回归测试、截图测试、历法和导航计算测试 | 否，测试包不应进入正式 HAP |
| `scripts/stellarium-cli.mjs` | 开发机 Node.js，通过 DevEco `hdc` 和 `aa start --ps` 调用鸿蒙命令桥 | 本地调试、自动化验证、读取带请求 ID 的 hilog 响应 | 否，属于开发工具，不在 App 内执行 |
| `scripts/*.sh`、`*.py`、`*.mjs` | 开发机 Bash、Python、Node.js | 同步源码、生成位置数据、检查 ArkTS、收集日志、构建和资源清单 | 否，属于构建/测试工具 |
| `harmonyos/ets-source/**/*.ets` | 鸿蒙 ArkTS/ArkUI 运行时 | UI、Ability 生命周期、隐私流程、设备交互和命令桥调用 | 是，但不是 `.ssc` 脚本 |
| `plugins/RemoteControl/webroot/js/**` | 桌面版本地 Web 控制台的浏览器 JavaScript | 通过 RemoteControl 网页操作桌面 Stellarium | 否；依赖桌面 Web 服务，离线鸿蒙版不应移植 |

当前构建安装了 `scripts/` 顶层的 48 个 `.ssc`、4 个共享 `.inc` 文件；`scripts/tests/` 被 `scripts/CMakeLists.txt:3-7` 明确排除。`.ssc` 的发现、预处理和执行分别见 `src/scripting/StelScriptMgr.cpp:562-574`、`src/scripting/StelScriptMgr.cpp:825-864` 和 `src/scripting/StelScriptMgr.cpp:797-804`。

### 当前脚本差距

- 脚本列表、运行、停止和速率控制已经有 C++ 命令桥，ArkUI 也有脚本列表入口。
- 暂停/继续按钮被置灰是正确行为：Qt 6 QML 脚本模式下 `pauseScript()` 和 `resumeScript()` 明确“不再可用且不执行”，见 `src/scripting/StelScriptMgr.cpp:939-958`；不能把这两个按钮当作未完成的普通 UI。
- 仍需逐个验证 48 个脚本在鸿蒙上的模块依赖、长时间执行、异常停止、恢复视角和截图路径。特别是涉及 Oculars、导航星、脚本截图目录、非地球观测者和大量 `core.wait()` 的脚本，不能只验证列表出现。
- 当前脚本中文名和描述只覆盖部分脚本，很多条目会退回文件名或通用描述；这属于 UI 本地化差距，不是脚本引擎差距。

## 插件移植优先级

### P0：发布和基础可用性

| 插件/能力 | 原因 |
| --- | --- |
| Scenery3d | 已参与构建但缺少 HAP 场景资源；先补资源，再做场景选择、视点和渲染控制入口 |
| 网络更新总开关 | Exoplanets、MeteorShowers、Novae、Pulsars、Quasars、Supernovae、Satellites 等插件仍含网络更新代码；未备案离线包应统一关闭更新路径 |
| 插件运行状态核对 | `getPluginList` 只能证明插件描述存在，需在设备上确认加载、卸载和对应图层是否真的生效 |

### P1：优先移植的本地高价值插件

1. `TimeNavigator`：直接补强当前时间棘轮和日期/月份/年份快速浏览，是用户已经反复使用的核心流程。
2. `AngleMeasure`：完全离线，适合触摸拖动测量角距离和方位角，移植边界清晰。
3. `PointerCoordinates`：把指针下的赤道/地平坐标直接呈现给用户，和选星、键鼠、触摸板操作强相关。
4. `Calendars` 与 `EquationOfTime`：本地算法工具，能补齐桌面版天文计算和时间工具的可见差距。
5. `NavStars`：离线导航星显示与导航场景，适合在位置和键鼠操控稳定后接入。
6. `ObjectVisibility`：补充按天体类型、星等和可见性筛选，能改善星表和搜索体验。
7. Oculars 高级项：在现有目镜基础上继续补视场旋转、棱镜、传感器裁剪、像素网格和调焦器叠加。
8. `ArchaeoLines`：本地考古天文线和观测方向，功能独立，但用户范围小于前几项。

### P1：已有数据但缺少完整入口的插件

`Novae`、`Supernovae`、`Pulsars`、`Quasars`、`Exoplanets` 和 `MeteorShowers` 的核心对象/目录数据可以继续保留离线，但需要补齐图层开关、对象列表、详情和“更新已关闭”的明确状态。它们不应因为目录更新代码存在就直接开放联网。

### P2：需要拆分桌面界面的插件

- `SolarSystemEditor`：先做本地轨道元素和本地对象编辑；MPC 在线导入继续隐藏。
- `NebulaTextures`：优先解决高清纹理资源映射后，再做纹理选择和显示参数。
- `SkyCultureMaker`：属于创作/编辑工具，需文件选择、图形编辑和导出，适合核心观星功能稳定后移植。
- `MosaicCamera`、`LensDistortionEstimator`：面向天文摄影和专业设备，用户范围较小，且需要复杂参数界面。
- `Planes`：实时航空器数据依赖网络，离线版只可做静态数据或继续关闭。

### P3：当前不建议移植到未备案离线版

- `OnlineQueries`：在线百科、SIMBAD、AAVSO/GCVS 等外部查询。
- `RemoteControl`、`RemoteSync`：开放本机 HTTP 或局域网同步，扩大攻击面和隐私边界。
- `TelescopeControl`：依赖 INDI/SerialPort 和外部设备，当前 `ENABLE_INDI=0`、`USE_PLUGIN_TELESCOPECONTROL=0`。
- `TextUserInterface`：桌面键盘终端式交互，不适合当前 ArkUI/触摸主流程。
- `SkyCultureMaker` 的文件导出高级能力和其他桌面文件对话框功能：待鸿蒙文件访问方案单独确认。

## 脚本移植优先级

### P0：先保证引擎和公共依赖

- 保持 Qt 6 QJSEngine、`core` 和已注册 StelModule 的脚本 API 可用。
- 固定打包 48 个用户脚本和 4 个 `.inc`，校验每个 `include()` 不丢文件。
- 增加脚本命令的开始、停止、异常、超时和恢复初始状态测试。

### P1：用户最有价值的离线脚本

- 观测导览：`constellations_tour`、`modern_constellations_tour`、`planets_tour`、`messier_marathon`、`BAS_Messier_Tour`、`h400_tour`、`best_ngc`。
- 观测目标清单：`double_stars`、`binocular_highlights`、`binosky`、`bennett`、`largest_known_stars`。
- 天象演示：`lunar_total`、`lunar_partial`、`solar_eclipse`、`transit_of_venus`、`BAS_Jupiter_Moons`、`morsels_1` 至 `morsels_4`。
- 星空文化和观测环境：`sky_cultures`、`landscapes`、`zodiac`、`sun`、`analemma`。

### P2：专业或长时间演示脚本

- `earth_1` 至 `earth_7`、`phobos_phun_1` 至 `phobos_phun_5`、`martian_analemma`、`saturnian_analemma`、`uranian_analemma`、`triple_sunrise_and_sunsets`。
- `screensaver`、`solar_system_screensaver`：长时间运行和状态恢复风险较高，不应作为启动默认脚本。
- `skybox`：会生成外部截图资源，需先定义鸿蒙沙盒目录和用户导出流程。

### P3：仅保留在开发测试环境

`scripts/tests/*.ssc` 用于 QJSEngine、历法、导航星、截图、实时计时和回归验证，不进入正式 HAP。`scripts/stellarium-cli.mjs`、日志工具、资源生成器和源码同步脚本也只在开发机运行，不属于用户插件或 App 脚本。

## 综合执行顺序

1. 先做脚本公共依赖和 48 个脚本的自动化可运行性矩阵。
2. 同时补 Scenery3d 资源和离线网络门禁，解决发布级问题。
3. 按 `TimeNavigator`、`AngleMeasure`、`PointerCoordinates`、`Calendars`、`EquationOfTime`、`NavStars` 顺序移植本地插件入口。
4. 补 Oculars 高级项、对象目录类插件和高清纹理映射。
5. 最后处理 SolarSystemEditor 离线子集、SkyCultureMaker、摄影插件和外设/联网能力。
