# 鸿蒙端原版资源覆盖审计

生成时间：2026-10-02T15:36:09.581Z

## 结论

- **顶层核心资源**：`data`、`textures`、`landscapes`、`stars`、`translations`、`scenery3d` 的源文件与 rawfile 镜像一致；`nebulae`、`skycultures`、`scripts` 的差异符合当前同步脚本的排除规则。
- **三维地景（`scenery3d/`）**：源码 `135` 个文件，rawfile `135` 个文件；已全部进入 rawfile。
- **插件资源**：发现插件自有资源，但它们不在 rawfile 独立目录中；是否可用取决于对应插件是否被编译进 `libstellarium.so`，需要逐插件运行验证。
- **未随包家族**：见下文“未随包家族与原因”；只有被引擎读取且当前功能启用的目录才算真实缺口。
- **资源存在不等于界面使用**：原版桌面 UI 皮肤、按钮图片、QRC 和字体已随 `data` 打包，但鸿蒙界面主要使用 ArkUI/SVG 自绘控件；这属于“已打包、未直接复用”，不是“已完成 UI 移植”。

## 顶层目录对照

|目录|源码文件|期望同步|rawfile|未同步|大小（源码/rawfile）|判定|
|---|---:|---:|---:|---:|---|---|
|`data`|287|287|288|0|28.7 MiB / 28.7 MiB|有差异|
|`textures`|111|111|164|0|30.5 MiB / 54.0 MiB|有差异|
|`landscapes`|703|703|703|0|16.9 MiB / 16.9 MiB|覆盖|
|`nebulae`|682|679|679|0|138.4 MiB / 127.2 MiB|覆盖|
|`stars`|16|16|16|0|88.9 MiB / 88.9 MiB|覆盖|
|`translations`|385|385|385|0|81.4 MiB / 81.4 MiB|覆盖|
|`skycultures`|1297|1227|1227|0|137.5 MiB / 150.1 MiB|覆盖|
|`scenery3d`|135|135|135|0|21.7 MiB / 21.7 MiB|覆盖|
|`scripts`|196|52|90|0|8.1 MiB / 5.1 MiB|有差异|

### 差异解释

- `nebulae` 未同步：无；其中 CMake 文件和 `catalog.txt` 不在现行 `sync-ohos-resources.sh` 的运行时白名单内。
- `skycultures` 未同步：无；这些是构建脚本、说明占位文件或 Python 辅助工具，不是运行时文化资料。
- `scripts` 期望值只包含顶层 `.ssc/.inc`；测试目录、音频/视频样例和审计/构建脚本不进入应用脚本列表。当前顶层资源：52 个，rawfile：90 个。
- **平台差异**：Windows 版 `sync-ohos-resources-windows.ps1` 用 `Get-ChildItem -Recurse` 复制 `scripts`，比 bash 版多带入 `scripts/tests/*.ssc` 等测试脚本（rawfile 90 > 期望 52）；bash 版 `--no-r --dirs` 只取顶层。属“多余包含”而非缺失，本审计记录、不改动。
- `stars` rawfile 额外残留：无；这类文件来自旧同步结果，已将普通目录同步改为带 `--delete` 的镜像模式。

## 文本、简介与翻译

|资源|源码情况|鸿蒙入口|状态|
|---|---|---|---|
|官方 `.qm` 翻译|`stellarium` 43 个；`stellarium-landscapes-descriptions` 42 个；`stellarium-planetary-features` 43 个；`stellarium-remotecontrol` 43 个；`stellarium-scenery3d-descriptions` 42 个；`stellarium-scripts` 43 个；`stellarium-sky` 43 个；`stellarium-skycultures` 43 个；`stellarium-skycultures-descriptions` 43 个|`LocaleMgr` / 核心天体名称 / UI I18n 校验|已打包；域内语言数量以实际编译结果为准|
|天体简介|`StelObject::getInfoMap`、`getInfoString`、`getObjectSpokenText`|`getObjectInfo`、`getObjectSpokenText`|已接入核心详情；需设备抽样检查不同类型简介是否为空|
|地景介绍|`landscapes/*/landscape.ini` 和描述文本|`getLandscapeInfo` 返回 description|已接入当前地景；多语言覆盖需抽样验证|
|星空文化介绍|63 个 description 文件|`getSkyCultureDetails` 返回 description/narration|已接入；界面图片最多展示 24 张，属于展示限制|
|行星地貌简介|`translations/stellarium-planetary-features/*.qm`、`data/nomenclature.*`|当前命令桥未发现独立的行星地貌资料面板|资源已打包；是否完整呈现需补功能验证|
|脚本简介|脚本注释中的名称、作者、描述|`getScriptList` 只返回脚本文件名|脚本列表已接入，原版脚本详情文本尚未确认接入|

## 图片和图形资源

|资源|数量|当前状态|说明|
|---|---:|---|---|
|深空 PNG|674|已打包并由核心纹理机制按需加载|启动阶段不复制全部图片；设备运行时需用 `getDeepSkyImageStatus` 验证引用、文件和纹理就绪状态|
|天空文化绘图|1024|已打包；详情入口可读取路径|源目录 63 个文化目录、65 个描述文件；当前界面最多显示 24 张绘图|
|原版桌面 GUI 图片|213|已打包但鸿蒙未直接复用|鸿蒙主要使用 ArkUI；`data/gui/miscWorldMap.jpg` 另有 `$rawfile('worldmap.jpg')` 替代入口|
|原版应用图标|8|已打包；应用图标另有 HarmonyOS media 配置|需要确认最终签名包使用的是哪套图标资源|
|三维地景模型/纹理|135|已打包、已随首次资源提取落盘|源目录包含 OBJ/MTL/纹理/多语言 description；是否在界面呈现取决于 `Scenery3d` 插件入口|

## 插件资源

插件资源候选共 **132** 个（`plugins/*/resources`、`plugins/*/data`）。它们由各插件的 QRC/模块构建逻辑管理，不会被 `sync-ohos-resources.sh` 复制到 rawfile。

当前 CMake 插件开关：`USE_PLUGIN_ANGLEMEASURE=1`、`USE_PLUGIN_ARCHAEOLINES=1`、`USE_PLUGIN_CALENDARS=1`、`USE_PLUGIN_EQUATIONOFTIME=1`、`USE_PLUGIN_EXOPLANETS=1`、`USE_PLUGIN_HELLOSTELMODULE=0`、`USE_PLUGIN_LENSDISTORTIONESTIMATOR=1`、`USE_PLUGIN_METEORSHOWERS=1`、`USE_PLUGIN_MOSAICCAMERA=1`、`USE_PLUGIN_NAVSTARS=1`、`USE_PLUGIN_NEBULATEXTURES=1`、`USE_PLUGIN_NOVAE=1`、`USE_PLUGIN_OBJECTVISIBILITY=1`、`USE_PLUGIN_OBSERVABILITY=1`、`USE_PLUGIN_OCULARS=1`、`USE_PLUGIN_OCULUS=0`、`USE_PLUGIN_ONLINEQUERIES=1`、`USE_PLUGIN_PLANES=1`、`USE_PLUGIN_POINTERCOORDINATES=1`、`USE_PLUGIN_PULSARS=1`、`USE_PLUGIN_QUASARS=1`、`USE_PLUGIN_REMOTECONTROL=1`、`USE_PLUGIN_REMOTESYNC=1`、`USE_PLUGIN_SATELLITES=1`、`USE_PLUGIN_SCENERY3D=1`、`USE_PLUGIN_SIMPLEDRAWLINE=0`、`USE_PLUGIN_SKYCULTUREMAKER=1`、`USE_PLUGIN_SOLARSYSTEMEDITOR=1`、`USE_PLUGIN_SUPERNOVAE=1`、`USE_PLUGIN_TELESCOPECONTROL=1`、`USE_PLUGIN_TEXTUSERINTERFACE=1`、`USE_PLUGIN_TIMENAVIGATOR=1`、`USE_PLUGIN_VTS=0`。

审计判断：

- 已启用且资源编译进插件模块的插件，可通过核心运行；这需要逐个打开插件面板并检查资源加载日志。
- 未启用插件的资源即使存在于源码，也不属于当前鸿蒙包的可用功能。
- `OnlineQueries`、远程控制、卫星更新等涉及网络的插件必须保持离线默认，并另行登记网络行为；本报告不把它们列为已接入。

## 未随包家族与原因

下列顶层源码目录不进入 rawfile（另有 `plugins/` 由下方插件章节单列）。判定口径：① 同步脚本应实现却缺失；② 有意排除；③ 源本身缺失；④ 体积/政策限制。

|目录|文件数|大小|类别|原因|
|---|---:|---:|---|---|
|`po`|857|594.0 MiB|②/④|② 翻译源文件（`.po`），运行时只加载编译后的 `.qm`（已随 `translations/` 打包）。|
|`atmosphere`|313|58.7 MiB|②/④|② 仅 `AtmosphereLightweight` 使用 `atmosphere/lightweight.amsh`；`landscape/atmosphere_model` 默认 `preetham`，且 OHOS 为 GLES2 已编译掉 ShowMySky。当前不读取。|
|`guide`|347|51.2 MiB|②/④|② 原版用户手册/图片（PDF/PNG），非运行时资源。|
|`models`|45|17.8 MiB|②/④|②/④ 引擎按 `models/<objModelName>` 读取 3D 网格（`Planet.cpp`），但开关 `astro/flag_use_obj_models` 默认 false、App 未暴露该开关；含 `moon-vertices-indices.bin`（源仅 `*.7z`）。是否打包属体积/产品决策。|
|`src`|504|15.7 MiB|②/④|② C++/GLSL 源码，已编译进 `libstellarium.so`。|
|`util`|86|3.9 MiB|②/④|② 构建/维护工具，非运行时资源。|
|`releases`|16|1.5 MiB|②/④|② 发布归档，非运行时资源。|
|`cmake`|22|238.8 KiB|②/④|② CMake 模块，构建期使用。|
|`doc`|14|212.4 KiB|②/④|② 仓库文档与示意图，非运行时资源。|
|`android`|2|41.5 KiB|②/④|② 其他平台打包配置。|

> `models/` 与 `atmosphere/` 是仅有的“引擎会读取、但按当前默认配置不启用”的目录；本审计只记录，不擅自纳入打包范围。

## 三维地景（scenery3d/）

- 源码：`135` 个文件，约 21.7 MiB；rawfile：`135` 个文件，约 21.7 MiB。
- 未同步差异：无。
- 两个平台的同步脚本（bash 的 `DIRS` 与 Windows 的镜像列表）都包含 `scenery3d`；此前报告“未打包”系旧版脚本/旧报告结论，已按当前 rawfile 实测更正。

## 静态入口证据

- ArkUI 调用天空文化列表/详情/区域几何：`已找到`。
- ArkUI 调用脚本列表：`已找到`。
- C++ 深空状态审计命令：`已找到`。
- 原版世界地图资源：`已进入 rawfile；ArkUI 使用独立 worldmap.jpg`。

## 后续优先级

1. **P0：** 在设备上验证深空图片引用、实际文件、纹理就绪三者是否一致，并记录 M31、M42、M31 以外的代表样本。
2. **P1：** 明确插件启用矩阵，逐个补资源加载探针；尤其是 Oculars、SolarSystemEditor、NebulaTextures、Satellites、MeteorShowers 和 Scenery3d。
3. **P1：** 接入行星地貌简介和脚本详情文本，不只显示文件名。
4. **待决策（体积/产品）：** `models/`（约 17.8 MiB，含 `moon-vertices-indices.bin` 的 `*.7z`）与 `atmosphere/`（约 58.7 MiB）是否随包 —— 二者仅由默认关闭的配置项启用（`astro/flag_use_obj_models`、`landscape/atmosphere_model`），需产品确认后再改同步脚本。
5. **P2：** 为天空文化补齐官方可用语言资源；当前 `en`、`zh_CN` 之外不要假称已完成多语言。

本报告只做静态资源覆盖审计；“已接入”表示代码入口存在，不替代平板/模拟器上的真实渲染验证。

## 决策（2026-10-02，用户确认）

`models/`（17.8 MiB）与 `atmosphere/`（58.7 MiB）**均不纳入 HAP**，保持现状（HAP 708.8 MiB）：

- `models/`：打开 `astro/flag_use_obj_models` 后，Ida/Vesta/Gaspra/Halley/67P 等小天体改用实测形状网格渲染；App 未暴露该开关，界面无差别。**后续若要露出"真实形状模型"开关，此项为必须，届时再按 bash 白名单补入两平台同步脚本（并解压 `moon-vertices-indices.bin.7z`）。**
- `atmosphere/`：仅在把大气模型从默认 `preetham` 切换到轻量/ShowMySky 时使用；本套 GLES2 构建已用 `ENABLE_SHOWMYSKY` 编译掉高质量路径。**维持不打包，未来评估时须连同编译开关一起决策。**

结论同步记录：`docs/harmonyos/CHANGELOG.md` 与本文"未随包家族与原因"表。
