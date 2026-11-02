# HarmonyOS 插件审计（2026-11-03）

编译进 `libstellarium.so` 的插件共 27 个（静态链接，无独立 .so）。下表按「有没有 ArkUI 面板 / 离线能不能用 / 要不要联网」三列过一遍，最后列出待补项。

判据来自代码，不是猜的：

- 编译集合：`CMakeLists.txt` 里 `ADD_PLUGIN(<id> 1)`（`ENABLE_SCRIPTING=1`、`STELLARIUM_GUI_MODE=Standard`）
- 入口路由：`harmonyos/ets-source/common/derive/labels.ets` 的 `pluginFeatureRoute()`
- 面板实现：`harmonyos/ets-source/panels/**`

## 一、有完整 ArkUI 面板（可用）

| 插件 | 入口 | 面板 | 离线可用 | 说明 |
|---|---|---|---|---|
| Satellites | 天体数据与扩展 → 卫星 | `satellites` | ✅ | TLE 随包内置；本轮已修「导入本地」改走文件选择器 |
| Oculars | 观测工作区 → 目镜/望远镜 | `oculars` | ✅ | 目镜/望远镜配置 |
| MeteorShowers | 天体数据与扩展 | `meteorshowers` | ✅ | 目录随包 |
| AngleMeasure | 观测工作区 | `angleMeasure` | ✅ | 角距测量 |
| ArchaeoLines | 图层/工具 | `archaeoLines` | ✅ | 考古天文线 |
| NavStars | 观测工作区 | `navStars` | ✅ | 导航星 |
| PointerCoordinates | 工具 | `pointerCoordinates` | ✅ | 指针坐标 |
| Scenery3d | 天体数据与扩展 | `scenery3d` | ✅（需地景资源） | 3D 地景 |
| TelescopeControl | 观测工作区 → 望远镜控制 | `telescope` | ✅（需局域网望远镜） | **只有客户端，没有服务端**（见下） |
| NebulaTextures | 工具 | `nebulaTextures` | ✅ | 星云贴图替换 |
| SkyCultureMaker | 工具 | `skyCultureMaker` | ✅ | 星文化编辑器 |
| RemoteControl | 插件管理 → 打开 | `settings`（无线控制区） | ✅ | **本轮新增**：设置里开关 + 端口，暴露 `0.0.0.0:8090` |

## 二、作为宿主页面的一部分（无独立面板）

| 插件 | 入口 | 挂在哪 | 离线可用 |
|---|---|---|---|
| EquationOfTime | 插件管理 → 打开 | 时间面板（均时差） | ✅ |
| TimeNavigator | 插件管理 → 打开 | 时间面板 | ✅ |
| Calendars | 插件管理 → 打开 | 天文计算 → 历法页（tab 8） | ✅ |
| Observability | 插件管理 → 打开 | 天文计算 → 可见性（tab 4 / 图 3） | ✅ |
| ObjectVisibility | 插件管理 → 打开 | 同上 | ✅ |
| TextUserInterface | 插件管理 → 打开 | 命令面板（脚本/命令） | ✅ |

## 三、目录型（没有面板，走搜索）

| 插件 | 入口 | 离线可用 |
|---|---|---|
| Exoplanets / Pulsars / Quasars / Novae / Supernovae | 插件管理 → 打开目录 | ✅（目录随包，本轮已刷新） |

## 四、只有 API / 需要联网（当前仅提示）

| 插件 | 现状 | 联网后应有 |
|---|---|---|
| OnlineQueries | 路由 `offline`，点了提示"离线构建不支持" | Simbad / Wikipedia 在线查询；需要 INTERNET + 镜像/反代 |
| RemoteSync | 路由 `offline` | 多设备设置同步；需要账号与配对，短期不做 |
| Planes | 路由 `network`，无面板 | 实时航班叠加；需要 OpenSky 之类数据源，长期再说 |

## 五、无 ArkUI 界面（有意保留在包里）

| 插件 | 处理 |
|---|---|
| LensDistortionEstimator | 桌面端标定工具，平板上无意义；路由为 `unavailable`，点开提示"无面板" |
| SolarSystemEditor | 同上 |

## 六、待补 / 待决

1. **联网开关**：`OFFLINE_APPGALLERY_BUILD`（`common/types/MainWindowModels.ets:443`）仍为 `true`。翻成 `false` 后 OnlineQueries 才真的能查；但需要先有 TLE/目录镜像，否则直连国外源在国内体验很差。
2. **RemoteSync**：没有配对协议和账号体系，翻开关也跑不起来，建议长期保持 `offline`，别在 UI 上假装可用。
3. **Planes**：要接实时航班源（OpenSky 免费额度有限），等镜像和反代上线后再评估。
4. **TelescopeControl 无服务端**：`plugins/TelescopeControl/src` 只有 `TelescopeClient`（LX200 / RTS2 都是往外连），没有 `QTcpServer`。所以它不会把端口暴露在内网；反过来也没法让别的设备通过网络驱动望远镜。真要做"局域网望远镜服务端"是独立工作量（LX200 服务端 + 端口冲突处理 + 鉴权），不建议顺手做。
5. **无线控制的鉴权**：RemoteControl 支持 `use_password`，目前 UI 没提供密码输入（默认无密码，仅限内网）。如果要给"半可信网络"用，建议补一个密码框。
