# 脚本与插件实际审计（2026-08-30）

## 结论

当前脚本和插件的核心业务是可用的，主要问题已经从“按钮假成功、列表传输过大、脚本启动卡住”收敛为明确的能力边界：Qt 6 原生脚本支持播放、调速和停止，不支持暂停/继续；插件可以管理随 HAP 编译的模块，但不能由用户导入任意 native 二进制。脚本和插件列表现在都能通过 CLI 返回完整结果，长响应使用分片日志传输，不再因 `hilog` 单行长度被截断。

## 源码盘点

| 项目 | 实际数量/状态 | 说明 |
| --- | ---: | --- |
| 顶层演示脚本 | 48 个 `.ssc` | 面向用户的教程、巡游、历法、行星和天象演示 |
| 测试脚本 | 36 个 `.ssc` | `scripts/tests/`，不应默认展示在用户脚本列表中 |
| 全部脚本 | 84 个 `.ssc` | 上游脚本目录的完整快照 |
| 共享脚本资源 | 6 个 `.inc` | 含通用对象、翻译、状态标签和导航星数据 |
| 当前 HAP 编译插件 | 28 个 | 由 `build/CMakeCache.txt` 的 `USE_PLUGIN_*` 决定 |
| 当前未编译插件 | 5 个 | `HelloStelModule`、`Oculus`、`SimpleDrawLine`、`TelescopeControl`、`Vts` |
| 平板启动时加载 | 6 个 | `Exoplanets`、`MeteorShowers`、`Novae`、`Oculars`、`Satellites`、`SolarSystemEditor` |

顶层脚本按业务分为：视角与导航（`planets_tour`、`constellations_tour`、`zodiac`）、深空巡游（`BAS_Messier_Tour`、`h400_tour`、`bennett`、`messier_marathon`）、行星/月球与历法（`earth_*`、`phobos_phun_*`、`lunar_*`、`analemma` 系列）、地景与天空文化（`landscapes`、`sky_cultures`、`skybox`）、天象演示（`solar_eclipse`、`transit_of_venus`、`supernova`）以及屏幕保护/启动流程（`startup`、`sun`、`screensaver`、`solar_system_screensaver`）。

脚本执行仍由 `StelScriptMgr` 和 `StelMainScriptAPI` 负责。时间、位置、视角、选星、图层、字幕和输出都走 Stellarium 核心；ArkUI 只显示状态和控制按钮，CLI 与界面使用同一命令桥。

## 按钮与状态矩阵

| 操作 | CLI 命令 | 实际结果 | UI 处理 |
| --- | --- | --- | --- |
| 播放 | `playScript` | 立即受理，随后由核心报告实际运行状态 | 进入脚本专注界面并轮询状态 |
| 调速 | `setScriptRate` | 已验证从 `1` 调到 `2`，状态可读回 | 显示当前脚本速率 |
| 停止 | `stopScript` | 已验证停止后 `running=false`、脚本 ID 清空 | 退出专注界面 |
| 暂停 | `pauseScript` | Qt 6 返回 `ok=false`、`supported=false` | 显示“不支持暂停，请使用停止”，不再伪装成功 |
| 继续 | `resumeScript` | Qt 6 返回 `ok=false`、`supported=false` | 同上；该按钮不应作为原生脚本按钮启用 |
| 查看脚本 | `getScriptList` | 完整元数据和 `summary` 两种模式均可用 | 列出名称、作者、许可证、版本、说明和来源 |
| 查看插件 | `getPluginList` | 完整元数据和 `summary` 两种模式均可用 | 列出作者、许可证、版本、来源、加载状态和启动策略 |
| 当前进程加载/卸载 | `loadPlugin` / `unloadPlugin` | 已验证 `AngleMeasure` 加载后状态为 `true`，卸载后为 `false` | 只改变插件生命周期，不重建整页 |

## 本轮 CLI 实测

设备：`192.168.1.30:33805` 平板；安装的是本轮重新构建的 HAP。

```text
getScriptList                 ok=true, count=48, details=48
getScriptList summary         ok=true, count=48, items=48
getPluginList                 ok=true, count=28
getPluginList summary         ok=true, items=28
getLoadedModuleNames          ok=true
playScript sun.ssc            accepted=true, 随后 running=true
setScriptRate 2               ok=true, 随后 scriptRate=2
pauseScript                   ok=false, supported=false
stopScript                    ok=true, 随后 running=false
loadPlugin AngleMeasure       ok=true, loaded=true
unloadPlugin AngleMeasure     ok=true, loaded=false
playScript screensaver.ssc    running=true；日志中不再出现 tr is not defined
```

列表完整响应曾因单条 `hilog` 过长而返回“无法解析设备响应”。现在 `QAbility` 将响应按安全长度分片，CLI 按序重组；这不是业务数据减少，而是传输层修复。

## 导入能力现状

### 用户导入脚本

目前可以一键导入单个 `.ssc`：脚本面板使用 HarmonyOS 系统文档选择器，复制到应用沙箱的用户脚本目录，导入完成后自动刷新列表。导入不自动执行；同名文件自动生成带时间戳的新文件名。当前限制为单文件、非空、最大 2 MiB，脚本依赖的自定义 `.inc`、图片、音频或视频不会随单个 `.ssc` 自动打包，因此复杂上游脚本仍需要随包发布或后续增加脚本包格式。

### CLI 导入脚本

`importScript` 仍保留给开发自动化，但只能读取应用进程可访问的路径。直接把文件放到 `/data/local/tmp` 后，普通应用沙箱通常没有读取权限，因此不能把“hdc 发送文件”误认为已经完成应用导入；用户端应使用系统文档选择器。后续可增加受限的内容/小文件传输协议，但不应通过放宽沙箱权限解决。

### 用户导入插件

当前不能一键导入任意插件。HarmonyOS 版本的插件以静态 native 模块编译进 HAP，`loadPlugin` 只能加载已经随包发布的插件；任意 `.so` 还涉及代码签名、ABI、权限、许可证、审核和卸载安全，不能由文件管理器直接安装。用户现在可以一键打开/关闭已编译插件，以及设置下次启动是否加载。

### 上游更新方案

1. 上游新增脚本：同步 `.ssc`、对应 `.inc` 和媒体资源，先做离线资源检查，再通过 `getScriptList` 检查元数据和列表传输。
2. 上游新增插件：先登记插件 ID、许可证、依赖、网络行为和入口命令，确认 HarmonyOS ABI 后静态编译进 HAP，再通过 `getPluginList` 验证加载状态。
3. 以后若需要用户导入复杂脚本，优先设计带 manifest、路径白名单、资源哈希和版本兼容范围的离线脚本包；不要直接开放任意 native 插件安装。
4. 未备案版本继续保持离线；`OnlineQueries`、远程同步、远程控制和在线星表更新不因导入流程自动启用。

## 后续优先级

1. **高：** 为脚本增加离线 manifest 和依赖资源打包，解决单 `.ssc` 无法携带 `.inc`/媒体的问题。
2. **高：** 将测试脚本与用户演示脚本分组展示，避免 `scripts/tests` 混入普通列表。
3. **中：** 为插件建立签名 manifest 校验和能力声明，但仍只允许随 HAP 发布的 native 实现。
4. **中：** 为每个插件补齐 ArkUI 的唯一功能入口和可用状态，避免插件管理页复制业务开关。
5. **低：** 研究上游脚本/插件更新的离线导入包；联网更新必须另行评审、登记和加入国内替代方案。

## 相关入口

- CLI 使用：`docs/harmonyos/CLI.md`
- 菜单与插件统一规划：`docs/harmonyos/MENU-PLUGIN-AUDIT-2026-08-30.md`
- 脚本播放与录制设计：`docs/harmonyos/SCRIPT-DESIGN.md`
- 命令目录：`src/StelOhosCommandCatalog.hpp`
