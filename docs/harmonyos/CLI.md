# Stellarium 鸿蒙 CLI

## 详情模型检查（2026-09-06）

- `setObjectModelView open` 打开选中目标的资料模型区；`immersive` 全屏查看，`close` 关闭全屏返回原详情，`reset` 重置视角，`dx|dy` 旋转。
- `getObjectModelView` 返回已完成的实际渲染帧：`kind`、`schematic`、`temperatureK`、`immersive`、`rotation`、`viewToBody`、`lighting`、`renderSize`、`renderedAt`。渲染是异步的，写入命令的 accepted 不代表新帧已完成，测试需等待目标和时间戳匹配。
- 无模型目标或取消选择时返回不可用，不拿上一目标的帧冒充成功。模型仅为详情检查，不改变主星图朝向、时间或位置。
- 类型和科学边界见 `PROCEDURAL-OBJECT-MODELS.md`；真实图片优先，程序化模型明确标识示意，未知物理参数不推算。

## 范围

CLI 通过 DevEco 自带的 `hdc` 和鸿蒙官方 `aa start --ps` 启动参数控制应用。它不启动 HTTP 服务、不访问公网、不上传观测位置或设备标识，适合未备案版本的本地调试和自动化测试。

应用收到命令后，会等待隐私同意、Qt 初始化和原生命令桥就绪，再执行命令；结果通过带请求 ID 的 `hilog` 记录返回给 CLI。首次启动若尚未同意隐私政策，CLI 会等待至超时，完成同意后重新执行即可。

`searchObject`、`selectAt` 和 `clearSelection` 的 CLI 结果同时同步到 ArkUI 详情卡；因此通过 CLI 选中行星时，会自动打开与应用内点选相同的详情媒体区域，不需要额外注入触摸事件。

对象详情统一使用一张可拖动的完整资料卡。卡片位置由 ArkUI 保存，连接到选中天体的细线可通过信息设置或本地 CLI 控制：

```bash
node scripts/stellarium-cli.mjs --device <设备ID> --command setObjectDetailConnector --payload 1 --json
node scripts/stellarium-cli.mjs --device <设备ID> --command getObjectDetailConnector --json
```

`enabled` 为 `true` 时显示连接线，`false` 时隐藏；该设置不改变星图投影、选中状态或天体位置，也不产生联网行为。

星座被选中后，可读取详情媒体未来切换为本地 3D 模型所需的能力契约：

```bash
node scripts/stellarium-cli.mjs --device <设备ID> --command getObjectDetailModel --json
```

当前返回 `state: planned`、实际 `assetKey`、`glTF 2.0` 格式、J2000 坐标锚点和二维文化绘图回退路径。只有未来离线模型完成授权、校验与渲染接入后才能改为 `ready`；该命令本身不会下载模型或访问网络。

## 信息级别与自定义字段

- `getInformationSettings` 返回 `infoMode`、保存的 `customInfoMask` 和当前生效的 `activeInfoMask`。预设模式不覆盖自定义字段；两种掩码不应混为一谈。
- `setInformationSetting` 的 `mode|custom` 恢复自定义字段，`mode|all/default/short/none` 使用预设；`mask|整数` 保存并启用自定义字段。
- 自定义掩码为 0 或恰好等于预设也继续标记为 `custom`，不会被误判为“无”或“全部”。使用上游 `custom_selected_info/flag_show_*` 保存，重启和切回自定义均恢复原选择。
- 掩码只控制信息展示，不删除选中天体身份、定位/导航计算数据或模型资源。原始 CLI 天体数据仍保留，ArkTS 根据同一掩码筛选展示字段。
- 实测脚本：`python3 scripts/test-ohos-information-settings.py --device <设备ID> --restart --output /tmp/information-test.json`；结束恢复原信息设置。

## 使用

在仓库根目录执行：

```bash
node scripts/stellarium-cli.mjs --command getAppState
node scripts/stellarium-cli.mjs --command searchObject --payload M31
node scripts/stellarium-cli.mjs --command setFOV --payload 60 --json
```

包含空格、中文或 JSON 的 payload 会由 CLI 自动进行 URI 百分号编码，并在 `QAbility` 内解码；调用方应直接使用 `--payload-json`，不要自行拼接 shell 引号或编码。旧版 `__STEL_CLI_PAYLOAD__` 前缀继续兼容。

搜索回归可在已解锁、已同意隐私政策的设备上执行：

```bash
node scripts/verify-ohos-search.mjs --device 7LZBB26323200303
```

该脚本验证梅西耶、NGC、HIP 星表目录号、中文官方名称、希腊字母名称、一级近似匹配与法语/德语官方译名的跨语言反查均会进入候选，不改变观测时间、位置或当前选中目标。

多设备连接时必须指定设备：

```bash
node scripts/stellarium-cli.mjs --device 7LZBB26323200303 --command getTimeInfo --json
node scripts/stellarium-cli.mjs --device 7LZBB26323200303 --command getDeepSkyImageStatus --json
node scripts/stellarium-cli.mjs --device 7LZBB26323200303 --command getDeepSkyImageStatus --payload 'all|0|32' --json
```

`--payload` 沿用 `StellariumOhos_command` 的原有字符串格式。例如 `selectAt` 使用 `x|y|skyW|skyH`，`setActionChecked` 使用 `actionId|1`。CLI 会自动处理 `aa --ps` 对负号开头字符串的限制，并对 payload 做 shell 转义，保证竖线分隔参数不会被 `hdc` 远端 shell 当成管道。命令名不在 CLI 中硬编码，桥接层已支持的命令均可直接调用；可执行 `--help` 查看工具参数。

流星诊断使用与桌面端相同的理论流星率范围（`0–240000` ZHR）。鸿蒙设置页的滑杆前段对 `0–1000` 做精细调整，后段按对数映射到桌面端上限；显示值仍是真实 ZHR，不是滑杆位置。用以下命令可核对当前生成条件、预期速率、实际接受数量和绘制抑制原因：

```bash
node scripts/stellarium-cli.mjs --device <设备ID> --command getMeteorDiagnostics --json
```

重点字段：`zhr`/`maxZhr` 为配置值和上限，`realTimeSpeed` 与 `generationSuppression` 判断是否允许生成，`drawSuppression` 判断是否因白天过亮或图层关闭而不绘制，`activeCount` 为当前存活流星数，`acceptedCount`/`rejectedCount` 用于判断随机辐射点和地平线过滤造成的损失。该诊断只读取本地运行状态，不联网。

导入脚本前，先把文件发送到设备可读路径，再调用导入命令：

```bash
hdc -t <设备ID> file send ./example.ssc /data/local/tmp/example.ssc
node scripts/stellarium-cli.mjs --device <设备ID> --command importScript \
  --payload /data/local/tmp/example.ssc --json
```

## 机器可读目录

命令桥提供统一目录、单命令 schema 和当前状态查询：

```bash
node scripts/stellarium-cli.mjs --list --json
node scripts/stellarium-cli.mjs --describe getWutTargets --json
node scripts/stellarium-cli.mjs --command getCommandStatus --payload getWutTargets --json
```

目录中的每项包含命令名、中文分类、是否修改状态、是否需要确认、离线属性、payload 编码和示例。所有新命令都必须登记到 `src/StelOhosCommandCatalog.hpp`，可在改动后执行：

```bash
node scripts/check-ohos-command-catalog.mjs
```

这个检查会比较 C++ 分发器中的命令和目录，避免新增功能无法被 CLI、AI 或应用内命令面板发现。

## 目录筛选

`listObjects` 可对分类目录在原生分页前筛选。其 payload 为 `模块ID|每页数量|偏移量|可见度|观测方式`，最后两段可省略并默认不过滤：

```bash
node scripts/stellarium-cli.mjs --command listObjects --payload 'NebulaMgr|60|0|above|binocular' --json
node scripts/stellarium-cli.mjs --command listObjects --payload 'NebulaMgr|60|0|good|naked' --json
```

- `可见度`：`all`（不限）、`above`（高度不低于 0 度）、`good`（高度不低于 20 度）。
- `观测方式`：`all`（不限）、`naked`（消光后视星等不高于 6）、`binocular`（不高于 10）、`telescope`（不加星等上限）。
- 返回的每个结果同时含有 `altitudes`、`magnitudes` 与 `visibleNow`，均基于当前本地观测位置和模拟时间计算；不会访问网络或读取设备标识。

浏览分类还提供两个统一目录：`ArtificialObjects` 合并太阳系人工航天器和卫星插件的离线目录；`NebulaMgr:200` 表示全部星云相关深空类型。两者都支持相同的分页和可见性筛选参数，虚拟人造天体目录中的卫星仍可通过 `searchObject` 的 `catalog|ArtificialObjects|<ID>` 选中。

`getStarCount` 返回 `counts.visible`（当前视场内恒星数）、`counts.catalogTotal`（已加载星表的真实条目总数）和 `counts.named`（按稳定天体 ID 去重后的可检索命名恒星数）。这三个数字用途不同，不能互相替代；`getStarCountFull` 还会返回已加载星表级别数和 `catalogReady`。

## 卫星目录

`getSatellites` 查询内置卫星目录，不会触发 TLE 下载。payload 为 `分组|搜索词|最多返回条数`；三段都可留空，条数默认 40、最大 100：

```bash
node scripts/stellarium-cli.mjs --command getSatellites --payload 'stations|ISS|20' --json
node scripts/stellarium-cli.mjs --command getSatellites --payload '||40' --json
```

卫星面板支持 `openUiPanel satellites`、`setSatellitePanelGroup <group-id>`（空字符串取消筛选）、`setSatellitePanelScroll <非负vp>` 和 `getSatellitePanelState`。设置命令的 accepted 只是受理；用状态查询确认实际分组、匹配结果、加载状态、滚动偏移及轨道线开关。`setSatellitesFlag orbitLines:1/0` 同步现有 ArkUI，开启后自动预览选中的有效卫星，不修改保存的单星轨道设置。`getSatellites` 返回查询 `elapsedMs` 和选中卫星的 `selectedOrbit`（实际采样点数、绘制计数、保存设置与临时预览）。详细语义与验证见 `SATELLITE-PANEL-ORBIT-UX.md`。

选中卫星的详情和过境预测使用同一套本地卫星数据。`getSatelliteDetail` 返回卫星身份、发射资料、当前轨道参数和未来过境；`getSatellitePasses` 只计算超过指定地平高度的过境，不下载 TLE：

```bash
node scripts/stellarium-cli.mjs --command getSatelliteDetail --payload '25544' --json
node scripts/stellarium-cli.mjs --command getSatellitePasses \
  --payload-json '{"id":"25544","hours":24,"limit":5,"minElevation":10,"visibleOnly":true}' --json
```

两条命令都支持 `id`、`hours`（1–168 小时）、`limit`（1–32）和 `minElevation`（−5–89°）。`getSatelliteDetail` 默认计算 48 小时并返回最多 8 条过境，另含 `nextPass` 和 `nextVisiblePass`；`getSatellitePasses` 默认计算 24 小时并返回 `satellitePasses`。每条过境包含出现、最高点、消失时间（本地时间与 UTC）、三处方位角、最大高度、最大星等、可见性、TLE 历元及 `offline/source` 字段。

卫星来源和更新策略也通过 CLI 管理。`getSatelliteSources` 只读取配置，不触发下载；每个来源返回 `url`、`scheme`、`local`、`network`、`valid` 和 `addNew`。`setSatelliteSources` 接受 JSON 数组或 `{"sources":[{"url":"...","addNew":true}]}`，仅允许 `file://`、`http://` 和 `https://`，会拒绝无效、重复或带用户信息的 URL。传入 `{"sources":[]}` 可以清空来源：

```bash
node scripts/stellarium-cli.mjs --command getSatelliteSources --json
node scripts/stellarium-cli.mjs --command setSatelliteSources \
  --payload-json '{"sources":[{"url":"https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=CSV","addNew":true}]}' --json
node scripts/stellarium-cli.mjs --command setSatelliteUpdateSetting \
  --payload-json '{"autoAddEnabled":true,"autoRemoveEnabled":false,"updateFrequencyHours":72}' --json
```

`importSatelliteTle` 只读取设备上的本地 TLE/CSV 文件，不访问网络；`refreshSatelliteCatalog` 在 HarmonyOS 离线包中始终返回失败和明确原因，避免把保存的远程 URL 误当成可用网络。导入示例：

```bash
node scripts/stellarium-cli.mjs --command importSatelliteTle \
  --payload-json '{"paths":["/data/local/tmp/stations.tle"]}' --json
```

发射日期严格区分精度：当前内置 TLE/COSPAR 数据通常只能提供发射年份，详情会显示年份，不会把 TLE 历元或目录更新时间冒充完整发射日期。精确日期、运营方、运载火箭、任务和载荷字段只有在离线富化目录提供时才出现。

返回内容含内置目录的更新时间、TLE 过期数量、当前观测位置是否为地球、模拟日期是否在目录有效范围及精确 NORAD 编号。应用界面选中卫星也通过 `object|Satellite|NORAD编号` 精确定位，不按名称猜测。

## 望远镜控制

当前鸿蒙包提供轻量望远镜控制桥，不等同于源码完整 `TelescopeControl` 插件。设备配置使用原生配置层持久化，ArkUI 和 CLI 共用同一份 1–9 号设备槽。支持明确标注的离线模拟设备和 LX200 TCP 设备；读取、保存、删除和选择配置都不会建立连接：

```bash
node scripts/stellarium-cli.mjs --command getTelescopeProfiles --json
node scripts/stellarium-cli.mjs --command saveTelescopeProfile --payload-json \
  '{"slot":1,"name":"Observatory LX200","protocol":"lx200_tcp","deviceModel":"Meade LX200 (compatible)","host":"192.168.1.80","port":4030,"equinox":"J2000","commandDelayMs":0,"circles":[1,2,4]}' --json
node scripts/stellarium-cli.mjs --command selectTelescopeProfile --payload '1' --json
node scripts/stellarium-cli.mjs --command getTelescopeControl --payload-json '{"slot":1}' --json
```

不接真实硬件时，可创建离线模拟设备验证控制、脚本和 CLI 链路。模拟器不会建立 socket，也不会控制真实赤道仪：

```bash
node scripts/stellarium-cli.mjs --command saveTelescopeProfile --payload-json \
  '{"slot":9,"name":"Offline simulator","protocol":"simulated","deviceModel":"Offline LX200 Simulator","host":"","port":0,"equinox":"J2000","commandDelayMs":0,"circles":[1,2,4]}' --json
```

用户主动测试连接、转向、同步或中止时才创建短连接，操作后立即断开。连接测试会发送只读的 LX200 `:GR#` 赤经探针，只有返回合法坐标格式才标记设备可用，避免把无关 TCP 服务误判为望远镜。支持选中天体和屏幕中心两种目标来源：

```bash
node scripts/stellarium-cli.mjs --command testTelescopeConnection --payload-json '{"slot":1}' --json
node scripts/stellarium-cli.mjs --command telescopeLx200GotoSelected \
  --payload-json '{"slot":1,"targetSource":"selected"}' --json
node scripts/stellarium-cli.mjs --command telescopeLx200SyncSelected \
  --payload-json '{"slot":1,"targetSource":"screen_center"}' --json
node scripts/stellarium-cli.mjs --command telescopeLx200Abort --payload-json '{"slot":1}' --json
node scripts/stellarium-cli.mjs --command getTelescopePosition --payload-json '{"slot":1}' --json
node scripts/stellarium-cli.mjs --command centerScreenOnTelescope --payload-json '{"slot":1}' --json
node scripts/stellarium-cli.mjs --command openUiPanel --payload telescope --json
node scripts/stellarium-cli.mjs --command setTelescopeLivePosition --payload on --json
node scripts/stellarium-cli.mjs --command setTelescopeLivePosition --payload off --json
```

兼容旧的 `host|port` 参数，但新功能应使用设备槽。真实连接只允许回环、RFC1918 IPv4、链路本地地址和 IPv6 ULA；公网 IP、主机名和未分类地址在创建 socket 前拒绝。连接状态区分未测试、可用和不可用，错误响应不会再显示为发送成功。`getTelescopePosition` 使用 LX200 `:GR`/`:GD` 按需读取位置，`centerScreenOnTelescope` 读取后平滑居中星图。“实时位置”默认关闭；用户在面板点击“转向”成功后会自动开启，也可通过开关或 CLI 单独控制。它仅在应用前台且望远镜面板可见时约每秒读取一次，面板关闭或应用转入后台会立即停止。星图使用 J2000 投影绘制望远镜十字标记、配置视场圈和屏外方向指示；离线模拟器按球面路径平滑转向，真实设备只按回传坐标移动。当前可选真实设备型号仅来自原版 `device_models.json` 中使用 LX200 协议的五项。串口 LX200、NexStar、INDI、ASCOM 和 RTS2 尚未移植。

## 批量与结构化调用

简单命令仍使用字符串 payload；需要对象或数组的命令使用 `--payload-json`：

```bash
node scripts/stellarium-cli.mjs --command getWutTargets \
  --payload-json '{"category":"planets","minAltitude":20}' --json
```

批量文件按顺序执行，单项失败不会阻止后续项：

```json
[
  {"command":"setFOV","payload":"45"},
  {"command":"getTimeInfo"},
  {"command":"getSelectedObjectInfo"}
]
```

```bash
node scripts/stellarium-cli.mjs --batch commands.json --json
```

交互模式使用 JSONL，适合 AI Agent 或脚本保持一个本地控制会话：

```bash
node scripts/stellarium-cli.mjs --interactive
{"command":"searchObject","payload":"M31"}
{"command":"getSelectedObjectInfo"}
exit
```

ArkUI 菜单也使用同一个本地 Want 通道，可直接打开、返回或关闭，无需模拟点击 Dock：

```bash
node scripts/stellarium-cli.mjs --command openUiPanel --payload time
node scripts/stellarium-cli.mjs --command openUiPanel --payload dataHub
node scripts/stellarium-cli.mjs --command openUiPanel --payload settingsInformation
node scripts/stellarium-cli.mjs --command openUiPanel --payload settingsTime
node scripts/stellarium-cli.mjs --command backUiPanel
node scripts/stellarium-cli.mjs --command closeUiPanel
```

陀螺仪可通过 ArkUI CLI 直接控制，便于真机姿态和性能回归，不需要模拟点击：

```bash
node scripts/stellarium-cli.mjs --device <设备ID> --command setGyroscopeEnabled --payload 1 --json
node scripts/stellarium-cli.mjs --device <设备ID> --command setGyroscopeEnabled --payload 0 --json
```

`openUiPanel` 只接受应用内已登记的面板名；这些命令不进入 Stellarium C++ 命令目录，不监听端口，也不产生联网行为。

`settingsInformation`、`settingsTime` 是设置子页语义入口，复用 `selectConfigTab` 的正常转场；不需要寻找标签坐标。打开后可用 `setInformationSetting`、`setDateFormat`、`setTimeFormat`、`setTimeSetting` 修改选项，以对应查询命令确认结果。`accepted` 仍只代表路由请求已接收，截图/布局树用于确认子页实际呈现，不能把该回执当成动画已完成。

插件入口也可以通过同一条本机 UI 命令回归：

```bash
node scripts/stellarium-cli.mjs --device <设备ID> --command openPluginFeature --payload ObjectVisibility --json
node scripts/stellarium-cli.mjs --device <设备ID> --command openPluginFeature --payload SkyCultureMaker --json
node scripts/stellarium-cli.mjs --device <设备ID> --command openUiPanel --payload skyCultureMaker --json
node scripts/stellarium-cli.mjs --device <设备ID> --command setSkyCultureMakerTab --payload 1 --json
```

`openPluginFeature` 与插件管理卡片共用 `pluginFeatureRoute`；控制型插件、目录型插件和宿主型插件会进入对应页面，未移植或离线禁用的模块只显示状态提示，不会猜测性跳转。

### 星空文化制作器

星空文化制作器与桌面插件共用 Stellarium 标准 `index.json`、`description.md` 和 `illustrations/` 结构。草稿和图片只保存在应用沙箱，不访问网络。`setSkyCultureMakerTab` 的 `0/1/2` 分别对应概况、星座、校验与导出。

```bash
node scripts/stellarium-cli.mjs --command getSkyCultureMakerDraft --json
node scripts/stellarium-cli.mjs --command saveSkyCultureMakerDraft --payload-json \
  '{"id":"custom_example","name":"示例星空文化","author":"原作者或贡献者","license":"CC BY 4.0","region":"Eastern Asia","classification":["traditional"],"native_lang":"zh_CN","constellations":[]}' --json
node scripts/stellarium-cli.mjs --command addSkyCultureMakerConstellation --payload-json \
  '{"id":"example","english":"Example","native":"示例"}' --json
node scripts/stellarium-cli.mjs --command addSkyCultureMakerLine --payload-json \
  '{"constellationId":"example","hips":[32349,30438]}' --json
node scripts/stellarium-cli.mjs --command importSkyCultureMakerArtwork --payload-json \
  '{"constellationId":"example","sourcePath":"/data/storage/el2/base/files/imports/example.png"}' --json
node scripts/stellarium-cli.mjs --command setSkyCultureMakerArtworkAnchor --payload-json \
  '{"constellationId":"example","anchorIndex":0,"x":120,"y":80,"hip":32349}' --json
node scripts/stellarium-cli.mjs --command validateSkyCultureMakerDraft --json
node scripts/stellarium-cli.mjs --command exportSkyCultureMaker --json
```

`setSkyCultureMakerArtworkAnchor` 必须设置 `0–2` 三个锚点。自动化可显式传 `hip`；触摸界面和交互式 CLI 也可省略 `hip`，改用星图当前选中的 HIP 恒星。导入 ZIP 会恢复可编辑草稿及其引用图片；导出前会检查元数据、年代、唯一 ID、折线、已安装 HIP 星表、图片文件和三点锚定。

## 普通用户入口

## 儒略日时间控制

`setJulianDate` 明确要求时间标度，避免把修正儒略日当作完整儒略日。该命令只修改本地模拟时间，并将时间速率暂停：

```bash
node scripts/stellarium-cli.mjs --command setJulianDate --payload 'jd|2451545.00000'
node scripts/stellarium-cli.mjs --command setJulianDate --payload 'mjd|51544.50000'
```

两种输入表示同一时刻，`MJD = JD - 2400000.5`。`getSimulationTime` 返回 `jd`、`mjd` 及 `calendarSystem`；当 JD 小于 `2299161.0` 时，日期面板按儒略历提示，否则按格里历提示。

`stellarium-cli.mjs` 是开发机和自动化使用的本地 CLI；应用不监听 HTTP 端口、不开放公网控制，也不把 `hdc` 当作普通用户权限。应用抽屉中已增加“命令”入口，直接读取同一目录并执行同一命令桥，支持筛选、payload、JSON 结果和高风险命令确认。这样普通用户、AI 和 ArkUI 点击操作最终走同一套命令实现，不会产生三套行为。

脚本和插件也通过同一命令总线调用：脚本使用 `playScript`/`stopScript`/`setScriptRate`；插件清单使用 `getPluginList`，当前进程载入使用 `loadPlugin`/`unloadPlugin`。内置插件统一随应用启动载入，旧客户端仍可调用 `setPluginLoadAtStartup`（例如 `Satellites|1`）但该命令只保留兼容性，不再允许 `|0` 关闭内置插件；各插件功能则使用自己的命令。三类状态不得混用。未备案版本保持离线，网络更新和外部设备命令必须继续受目录权限标记约束。

`getPluginList` 的每个条目还返回原版 `StelPluginInfo` 的 `description`、`authors`、`contact`、`version`、`license`、`acknowledgements`、`hasPreviewImage` 和 `source`。`getLandscapeList` 的每个条目返回 `landscape.ini` 中的 `author`、`description`、`source`、地点/星球/时区字段；`getLandscapeInfo` 返回当前地景的完整说明。`getScriptList` 的 `items` 仍是旧的 `.ssc` 文件名数组，同时新增 `details` 数组，逐项返回 `Name`、`Author`、`License`、`Version`、`Description`、`Shortcut` 和来源路径，旧 CLI 无需改动即可继续使用。

导入脚本使用系统文档选择器，应用只接受 `.ssc` 文件并复制到应用沙箱中的用户脚本目录，完成后立即刷新脚本列表。CLI 或自动化流程也可以调用：

```bash
node scripts/stellarium-cli.mjs --device <设备ID> --command importScript \
  --payload /data/local/tmp/example.ssc --json
```

`importScript` 只复制脚本，不执行脚本；同名文件和超过 2 MiB 的文件会被拒绝。鸿蒙版本的插件随 HAP 静态编译，`loadPlugin` 只负责当前进程内即时初始化已随包发布的插件，不支持从文件管理器安装任意 `.so` 插件。这样可以保持签名、权限和离线边界可审计。

设备端响应通过带序号的 `responseChunk` 日志分片传输，CLI 会自动重组完整 JSON；因此 `getScriptList`、`getPluginList` 等长查询不再因为 `hilog` 单行长度而出现“无法解析设备响应”。`pauseScript` 和 `resumeScript` 在 Qt 6 原生脚本引擎下会明确返回 `ok=false`、`supported=false`，不能把不支持的操作报告为成功。

CLI 的 `importScript` 只适用于应用进程可读取的路径。普通应用通常不能读取开发机通过 `hdc file send` 放入的 `/data/local/tmp`，所以开发机传文件与应用导入不是同一步；用户端请使用脚本面板的 HarmonyOS 系统文档选择器。插件仍不能通过文件管理器导入任意 native 二进制。

## 官方依据

鸿蒙官方 `aa` 工具支持显式启动 Ability 以及 `--ps <key> <value>` 字符串 Want 参数；官方 Want 文档将 `parameters` 定义为应用间传递自定义键值的载体。当前实现使用这些参数，不注册自定义 URI，不新增网络端口。

官方开发建议还包括：

- 使用 `aa start -W -b <包名> -a <Ability>` 测量 Ability 从启动请求到首帧或前台的耗时，适合定位“正在唤醒星空”或启动卡顿。
- 使用 `aa force-stop <包名>` 清理上一次进程状态，再执行冷启动测试；不要用强制停止代替正常生命周期测试。
- 使用 `hdc shell hilog` 查看系统日志，按请求 ID、包名和日志标签过滤，避免把完整日志流直接回传到主机造成丢行。
- 使用官方 `uitest` 命令进行界面级自动化：`screenCap` 截图、`dumpLayout` 获取控件树、`uiInput click/swipe/drag/keyEvent` 注入触摸和键鼠事件。

例如，启动耗时和界面检查可以这样执行：

```bash
hdc -t 7LZBB26323200303 shell aa start -W -b com.joinother.skyinstrument -a QAbility
hdc -t 7LZBB26323200303 shell uitest screenCap -p /data/local/tmp/skyinstrument.png
hdc -t 7LZBB26323200303 shell uitest dumpLayout -b com.joinother.skyinstrument -p /data/local/tmp/skyinstrument-layout.json
hdc -t 7LZBB26323200303 shell uitest uiInput keyEvent 2050
```

上述 `uitest` 命令属于设备端调试工具，不是应用运行时能力；正式包不会因此增加端口或网络权限。官方文档：[`aa工具`](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/aa-tool)、[`SDK命令行工具简介`](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/command-line-tools-overview)、[`UI测试`](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uitest-guidelines)。

## 限制

- CLI 需要已连接、已授权的 `hdc` 设备和可调试安装包。
- 结果通过日志回传，超大结果可能受系统日志单行长度限制；查询类命令建议按范围或数量参数分批调用。
- `getDeepSkyImageStatus` 默认检查重点图片；传入 `--payload 'all|偏移|数量'` 分页列出已复制 PNG，单页数量最多 64。`onDisk` 只代表资源已复制，`textureReady` 才代表当前惰性纹理树已经取得可绑定纹理；`textureLoading` 表示正在后台读取，`textureNotStarted` 表示尚未开始绑定。没有进入当前视场的图片可能保持未实例化，不应据此判定资源缺失。
- `getConstellationArtStatus` 接受星座缩写或名称（例如 `Ori`），也可传 `all`；返回艺术文件是否落盘、纹理是否未启动/加载中/可绑定/失败，以及当前视口相交和有效亮度，用于区分资源、解码与绘制问题。
- 连续视图命令（如 `dragView`、`zoomBy`）返回“已入队”，不等待逐帧完成。
- 这是开发者控制通道，不是面向普通用户的应用内命令行界面；Release 包也不会因此监听网络端口。

## 选中天体的实时详情

卫星传播诊断：`getSelectedObjectInfo` 返回 `orbitValid`、`propagationStatus`、`tleAgeDays`、`tleOutdated`、`sgp4Error`。失效轨道不提供当前坐标/距离，不绘制星图标记，仍可通过目录选择查看资料。居中或开启跟踪返回 `errorCode=invalid_orbit`；`getSatelliteDetail/getSatellitePasses` 的 `dataStatus` 区分 `invalid_orbit/stale/local`。包更新时间不是单条 TLE 历元，详见 `SATELLITE-PROPAGATION-AUDIT.md`。

跨天体距离统一契约：`getSelectedObjectInfo` 的 `distance` 是展示字符串，`distanceCompact` 为省略误差的摘要；数值读取 `distanceValue` 并同时读取 `distanceUnit`，跨单位比较使用 `distanceLightYears`。可用时另含 `distanceErrorLightYears`、`distanceMethod`。`getDistanceInfo` 保留数值 `distance`，单位不再一律视为 AU，格式化值为 `distanceText`。无可靠数据不返回伪造的 0；状态还包括 `catalog`、`estimated`、`low_confidence`、`redshift_only`、`unsupported_unit`。类星体红移不直接当作距离。完整映射见 `OBJECT-DISTANCE-AUDIT.md`。

`setObjectDetailTab` 参数 `0/1/2/3` 分别进入观测、坐标、资料、操作；需要已有选中对象，不改变星图视角。返回 accepted 仅为入队确认，需检查后续详情或实际布局确认完成。

人造卫星的 `distance` 为按公里显示的观测者斜距，与补充资料的 `range` 一致；`distanceKm` 为未格式化数值，`distanceReference=observer`，不能当作离地高度。`distanceStatus` 为 `computed`、`unavailable` 或 `invalid_orbit`；后两者不返回伪造的距离。这个状态说明当前是否有可用计算值，不是 TLE 时效或测量精度评级，计算仍依赖本地轨道数据、模拟时间与观测位置。自然卫星（月球等）不走人造卫星字段映射，保留太阳系 AU 距离。

`getSelectedObjectInfo` 的轻量响应包含实时坐标及 `liveDetailFields`；`getSelectedObjectInfo details` 才返回完整 `detailFields`。字段的 `live: true` 表示应由下一份实时快照替换，消失的动态字段不得继续显示旧值。轨道光照、月面、卫星斜距/速率/星下点等走该通道；说明、目录编号、TLE 保持首次资料加载，不在心跳里重复分发。过境预测仍需显式请求 `getSatellitePasses`，不再阻塞坐标刷新。

UI 空闲时按 180ms 周期尝试更新；桥接未返回或用户拖动星图时跳过，不承诺每帧都采样。数字显示仍遵守原精度，所以静态字段、暂停时间，以及在该精度下尚未改变的值不会跳动。`scripts/test-ohos-detail-live.py` 通过 CLI 驱动时间与选星、读取实际 UI 文本，核验坐标页、资料方块和卫星补充字段；最后恢复时间速率与选择。

## 拼接相机与离线纹理探针

- `openUiPanel mosaicCamera/nebulaTextures` 可直接打开对应 ArkTS 面板；`openPluginFeature MosaicCamera/NebulaTextures` 保持插件入口兼容。
- `getMosaicCamera` 中 visible/enabled 均为布尔值；`setMosaicCamera` 支持相机名、显隐、赤经赤纬、旋转及位置操作。没有选中对象时 setToSelected 返回错误，而不是静默成功。
- `getNebulaTextureStatus` 中 imageDecodeCount 为本进程文件校验解码次数，layerRebuildCount 为自定义图层成功重建次数。ready 仍仅表示文件和映射校验通过，不等于 GPU 纹理就绪；layerLoaded 仅表示图层已注册。
- 连续调用状态、显隐和冲突避让不得增加以上两项计数；显式 refreshNebulaTextures 重建一次，未改动文件复用校验缓存。文件大小/修改时间变化自动重新校验。
- `importNebulaTexture` 仅接受应用能读取的路径；/data/local/tmp 不能当成应用沙箱内的可读路径。GUI 通过系统选择器授权后复制到临时目录，再导入插件目录。原图按字节保存，不改变分辨率、质量或编码。
- 自定义列表不包含内置深空图库；离线当前视野映射为近似放置，精确放置需提供 corners 等坐标参数，不启用上传图片的在线板解。
- 回归：`python3 scripts/test-ohos-plugin-panels.py --device <设备> --output <报告.json>`。复制内置图片作为独立临时测试条目，最后删除该条目、恢复开关及当前相机；不删除或改写内置源图。

## 时间偏好与启动时间

- `getTimeSettings` 返回实际生效的日期/时间格式、格式化预览 `formattedTime`、观测地时区、启动模式/暂停、`todayTime`、`presetLocalTime` 和完整 ΔT 算法列表/自定义参数。
- `setDateFormat` 接受 `system_default/yyyymmdd/ddmmyyyy/mmddyyyy/wwyyyymmdd/wwddmmyyyy/wwmmddyyyy`；`setTimeFormat` 接受 `system_default/24h/12h`。立即影响原生和 ArkTS 星图时钟、时间面板；ISO 输入与机器字段保持稳定，不按显示格式解析。
- `setTimeSetting startupMode|actual/today/preset` 与 `startupStop|0/1` 自动保存，通常下次启动生效，不移动当前模拟时间。
- `todayTime|HH:mm[:ss]`：设备当天日期、观测地时区下的指定钟点。`presetLocal|YYYY-MM-DDTHH:mm:ss`：固定的观测地本地日期与时刻，不带 UTC 后缀。
- `presetCurrent|1` 把当前星图模拟时刻按观测地时区保存，并选中 preset 模式（与原版“使用当前时间”一致）；不能把 UTC JD 直接写成上游本地预设 JD。
- `applyStartup|1` 明确将已保存的启动来源立即应用到当前模拟，并按启动暂停设置恢复 0 或 1 倍时间流速；不使用尚未保存的输入框内容。
- `deltaT|算法键` 即时应用。`deltaCustom|基准年,ndot,a,b,c` 编辑并保存自定义公式参数（有限数值，绝对值不超过 1e6）；仅选中 Custom 时用于计算。ΔT 秒数 = a+b·u+c·u²，u=(年份−基准年)/100。
- 写入后返回权威设置快照并同步 ArkTS；错误输入不改变已保存设置。`getState`/`getSimulationTime` 同时返回 `formattedTime`，保持全量与轻量刷新一致，原始 `timeText`/`jd` 不变。
- 真机回归：`python3 scripts/test-ohos-time-settings.py --device <设备> --restart --output <报告.json>`，测试结束恢复原始时间偏好和模拟时刻/流速。
# 天文计算动效操作补充（2026-09-06）

`openUiPanel astro` 后使用 `setAstroGroup 0..2`、`setAstroTab 0..9`；今晚筛选使用 `setAstroFilter`（如 `period|morning`）。`getAstroPanelState` 返回最近面板状态，等待 `transitioning=false` 和目标 tab 一致才表示页面切换完成，不代表计算完成或动画帧率。完整参数与边界见 `ASTRO-CALC-MOTION.md`。
