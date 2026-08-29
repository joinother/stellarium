# Stellarium 鸿蒙 CLI

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

## 使用

在仓库根目录执行：

```bash
node scripts/stellarium-cli.mjs --command getAppState
node scripts/stellarium-cli.mjs --command searchObject --payload M31
node scripts/stellarium-cli.mjs --command setFOV --payload 60 --json
```

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

`getStarCount` 返回 `counts.visible`（当前视场内恒星数）、`counts.catalogTotal`（已加载星表的真实条目总数）和 `counts.named`（按稳定天体 ID 去重后的可检索命名恒星数）。这三个数字用途不同，不能互相替代；`getStarCountFull` 还会返回已加载星表级别数和 `catalogReady`。

## 卫星目录

`getSatellites` 查询内置卫星目录，不会触发 TLE 下载。payload 为 `分组|搜索词|最多返回条数`；三段都可留空，条数默认 40、最大 100：

```bash
node scripts/stellarium-cli.mjs --command getSatellites --payload 'stations|ISS|20' --json
node scripts/stellarium-cli.mjs --command getSatellites --payload '||40' --json
```

返回内容含内置目录的更新时间、TLE 过期数量、当前观测位置是否为地球、模拟日期是否在目录有效范围及精确 NORAD 编号。应用界面选中卫星也通过 `object|Satellite|NORAD编号` 精确定位，不按名称猜测。

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

## 普通用户入口

## 儒略日时间控制

`setJulianDate` 明确要求时间标度，避免把修正儒略日当作完整儒略日。该命令只修改本地模拟时间，并将时间速率暂停：

```bash
node scripts/stellarium-cli.mjs --command setJulianDate --payload 'jd|2451545.00000'
node scripts/stellarium-cli.mjs --command setJulianDate --payload 'mjd|51544.50000'
```

两种输入表示同一时刻，`MJD = JD - 2400000.5`。`getSimulationTime` 返回 `jd`、`mjd` 及 `calendarSystem`；当 JD 小于 `2299161.0` 时，日期面板按儒略历提示，否则按格里历提示。

`stellarium-cli.mjs` 是开发机和自动化使用的本地 CLI；应用不监听 HTTP 端口、不开放公网控制，也不把 `hdc` 当作普通用户权限。应用抽屉中已增加“命令”入口，直接读取同一目录并执行同一命令桥，支持筛选、payload、JSON 结果和高风险命令确认。这样普通用户、AI 和 ArkUI 点击操作最终走同一套命令实现，不会产生三套行为。

脚本和插件也通过同一命令总线调用：脚本使用 `playScript`/`stopScript`/`setScriptRate`；插件清单使用 `getPluginList`，当前进程载入使用 `loadPlugin`/`unloadPlugin`，随应用启动载入使用 `setPluginLoadAtStartup`（例如 `Satellites|1`），各插件功能则使用自己的命令。三类状态不得混用。未备案版本保持离线，网络更新和外部设备命令必须继续受目录权限标记约束。

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
