# 插件能力差距审计

更新时间：2026-08-31

## 审计结论

本次按源码插件目录、CMake 构建开关、设备 `getPluginList`、ArkUI 路由和 CLI 命令逐项核对。设备当前实际加载 28 个插件；`HelloStelModule`、`SimpleDrawLine`、`Oculus`、`Vts` 未进入发布包，`TelescopeControl` 也未作为原版插件加载。鸿蒙端的望远镜页是独立的轻量 LX200 桥，不应标成完整 `TelescopeControl` 移植。

未备案版本继续遵守运行时离线边界。公网数据请求、外部网页、本机连接、局域网连接和串口设备连接分别记录，不能用“没有 INTERNET 权限”替代功能审计。

## 能力对照

| 插件 | 原版主要能力 | 鸿蒙当前状态 | 差距与下一步 | 网络/设备边界 | 优先级 |
|---|---|---|---|---|---|
| `AngleMeasure` | 两点角距离、方位和高度测量 | 已有桥和面板 | 补测量历史、复制结果和连续更新 | 离线 | P0 |
| `ArchaeoLines` | 考古天文线、方位、选中天体时角 | 已有桥和面板 | 补完整参数、来源说明和本地化 | 离线 | P1 |
| `Calendars` | 多历法日期转换和说明 | 并入天文计算 | 补更多历法字段和详情 | 离线 | P1 |
| `EquationOfTime` | 均时差曲线和实时值 | 并入时间页 | 补曲线配置和信息完整度 | 离线 | P1 |
| `Exoplanets` | 系外行星目录、标记和详情 | 内置目录、搜索分类 | 补目录来源/版本状态和筛选 | 构建机更新，运行时离线 | P1 |
| `LensDistortionEstimator` | 天文照片导入、星点匹配、镜头畸变拟合 | 随包但无独立 ArkUI 页 | 文件选择、任务进度、结果导出 | 本地图片；不上传 | P2 |
| `MeteorShowers` | 流星雨目录、辐射点、模拟和详情 | 已有面板和本地目录 | 补活动窗口、峰值说明、速率诊断展示 | 构建机更新，运行时离线 | P0 |
| `MosaicCamera` | 相机马赛克视场叠加 | 已有桥和面板 | 补相机参数、旋转和预览布局 | 离线 | P2 |
| `NavStars` | 导航星集合、标记和参数 | 已有桥和面板 | 补集合说明、筛选和导航流程 | 离线 | P1 |
| `NebulaTextures` | 深空纹理导入、显示和 Plate Solver | 已接入本地导入、当前视场自动映射、状态检查、显示/冲突控制、定位和删除 | 补完整 WCS/四角映射编辑器、缩略图预览和更细的资源预热反馈 | 本地纹理离线可用；Plate Solver 涉及上传，离线禁用 | P2 |
| `Novae` | 新星目录和显示 | 内置目录、搜索分类 | 补目录详情、版本和过期状态 | 构建机更新，运行时离线 | P1 |
| `ObjectVisibility` | 按观测地点显示对象可见区域 | 已接入天文计算 > 可观测性宿主 | 当前使用统一的全年观测窗口计算；地图式原版视图仍待补齐 | 离线 | P1 |
| `Observability` | 升落、中天、全年可观测性 | 已有异步计算页 | 补完整桌面字段、导出和取消 | 离线 | P1 |
| `Oculars` | 目镜、望远镜、镜片、CCD、Telrad、十字丝 | 已有桥和模拟页 | 补传感器裁剪、调焦器、配置导入导出 | 离线 | P0 |
| `OnlineQueries` | SIMBAD、AAVSO、GCVS、百科查询 | 已加载但鸿蒙入口禁用 | 不在未备案版开放；未来单独做授权和隐私设计 | 公网查询/外部网页 | P3 |
| `Planes` | 实时 ADS-B 飞机 | 已标记为网络插件，入口禁用 | 未来只增加本地快照导入，不冒充实时数据 | 公网请求会外发位置 | P3 |
| `PointerCoordinates` | 指针坐标、星座和辅助线 | 已有桥和面板 | 补触摸指针、格式和坐标显示开关 | 离线 | P0 |
| `Pulsars` | 脉冲星目录、显示和详情 | 内置目录、搜索分类 | 补目录筛选、来源和版本状态 | 构建机更新，运行时离线 | P1 |
| `Quasars` | 类星体目录、显示和详情 | 内置目录、搜索分类 | 补目录筛选、来源和版本状态 | 构建机更新，运行时离线 | P1 |
| `RemoteControl` | HTTP Web 远程控制 | 已加载但鸿蒙入口禁用 | 未来只支持明确开启、本机绑定、认证和审计 | 本机/局域网监听 | P3 |
| `RemoteSync` | 多实例状态同步 | 已加载但鸿蒙入口禁用 | 未来接入分布式能力前先做认证和状态白名单 | 本机/局域网 TCP | P3 |
| `Satellites` | TLE 来源、导入、更新、分组、过境、显示 | 已有面板、离线目录和 CLI | 补来源测试、批量导入、轨道/过境详情 | 构建机更新；运行时本地导入 | P0 |
| `Scenery3d` | 3D 地景场景、相机移动和光照 | 已有场景列表和开关 | 补触摸相机、场景说明和资源状态 | 离线资源 | P1 |
| `SkyCultureMaker` | 星空文化绘制、编辑和导出 | 已有独立 ArkUI 制作器、版本化草稿、HIP 折线、星座艺术图三点锚定、严格校验及标准 ZIP 导入/导出 | 后续补文化分布 GeoJSON 触摸绘制、星图直接连续画线和桌面旧格式转换器 | 本地文件 | P1 |
| `SolarSystemEditor` | 小行星/彗星导入和轨道元素编辑 | 已载入但无等价 ArkUI 页面，明确标记未移植 | 先做本地 JSON/轨道文件导入；MPC 网络导入保持关闭，不跳转到星表下载页 | 本地文件；MPC 公网 | P2 |
| `Supernovae` | 历史超新星目录和显示 | 内置目录、搜索分类 | 补目录详情、来源和版本状态 | 构建机更新，运行时离线 | P1 |
| `TextUserInterface` | 桌面键盘 TUI 命令面板 | 命令目录和 ArkUI 命令页 | 继续以统一 CLI 为唯一实现，不复制 TUI | 离线 | P1 |
| `TelescopeControl` | 9 槽、串口、TCP、INDI、ASCOM、RTS2、设备模型、转向/同步/中止 | 原版插件未加载；独立桥已支持 9 槽、LX200 TCP/离线模拟、位置回读、星图标记和视场圈 | 后续评估 SerialPort、NexStar、INDI、ASCOM、RTS2；星闪另按传输适配器和厂商协议分层评估，不与轻量桥混接 | TCP 可连本机/局域网；串口为本机设备；星闪为本地无线设备；不自动连接 | P1 |
| `TimeNavigator` | 时间步进、事件跳转、晨昏和升落 | 已接入时间宿主 | 时间页承载时间步进和升落/中天/落下；行星事件导航字段仍待补齐 | 离线 | P1 |
| `Vts` | 本机 VTS TCP 服务连接 | 不打包 | 需要明确本机端口、协议和专用入口后再评估 | 本机 TCP | P3 |
| `HelloStelModule` | 开发者示例模块 | 源码存在但不打包 | 不进入普通用户功能；仅用于开发验证 | 离线 | P3 |
| `Oculus` | Oculus/VR 视图插件 | 源码存在但不打包；当前卡片明确未移植 | 需要独立 VR 设备和渲染管线评估，不与 Oculars 目镜模拟混用 | 设备能力 | P3 |
| `SimpleDrawLine` | 简单绘线开发示例 | 源码存在但不打包 | 不进入普通用户功能；后续如开放应接入独立标注工具 | 离线 | P3 |

## 望远镜控制专项

### 当前实际实现

鸿蒙端使用 `src/StelMainView.cpp` 中的轻量望远镜桥。现已补齐 1–9 号设备槽、原生配置持久化、新增/编辑/删除/默认设备、J2000/JNow、0–2000 ms 命令延迟、视场圈配置、连接测试、选中天体/屏幕中心目标来源、按需和实时读取当前位置、星图居中到望远镜，以及与星图同一 J2000 投影绘制的十字标记、视场圈和屏外方向指示。离线模拟器按球面路径平滑转向；真实 LX200 只使用设备回传位置，按连续样本插值，不用目标坐标伪造设备运动。ArkUI 与 CLI 共用同一份原生配置，不另存一套。默认新配置是明确标注的离线模拟设备，可验证转向、同步、中止和坐标回读；真实 LX200 设备只有在用户主动测试、控制、读取位置或开启实时位置时才创建 `QTcpSocket`，每次操作后立即断开。

当前桥仍不是完整源码插件。原版的常驻连接生命周期、串口、内置服务器、远程 Stellarium 服务器、NexStar、INDI、ASCOM、RTS2 仍未移植。当前鸿蒙构建因 `USE_PLUGIN_TELESCOPECONTROL=0` 且 `ENABLE_INDI=0` 没有加载完整插件；Qt SerialPort 也未作为可用依赖接入。设备型号只开放原版资源中使用 LX200 协议的 Meade AutoStar/LX200/ETX70、Losmandy G-11 和 Argo Navis；NexStar/SynScan 不显示为可用。

### 连接和隐私边界

- TCP 控制可能连接本机或局域网设备；它不是公网天文数据，但仍会向目标地址发送目标赤经赤纬和 LX200 控制指令。
- 源码原版的串口连接只访问本机设备节点，不需要联网；鸿蒙端尚未移植串口配置和设备权限流程。
- 当前不提供自动发现、不扫描局域网、不监听端口、不在后台连接；不提供“随应用启动连接”。
- 未备案版本不开放 INDI、ASCOM、RTS2 和远程控制；未来接入前必须增加用户确认、地址白名单或明确目标、超时、断开状态和日志脱敏。
- `getTelescopeControl` 和 `getTelescopeProfiles` 只返回配置、传输类型和范围分类，不做 DNS 查询、不建立 socket。
- 所有实际连接在创建 socket 前检查地址范围；只接受回环、私网 IPv4、链路本地和 IPv6 ULA，公网、主机名及未分类地址直接拒绝。

## 已补代码

- 插件路由为 `TelescopeControl` 指向现有望远镜控制宿主，避免插件卡片显示“无控制页”。由于完整插件没有进入当前包，路由不会伪造插件加载状态。
- 新增 `getTelescopeProfiles`、`saveTelescopeProfile`、`deleteTelescopeProfile`、`selectTelescopeProfile` 和 `testTelescopeConnection`，并让现有转向、同步、中止接受设备槽 JSON。
- 望远镜页拆为设备槽、设备配置、目标来源和控制状态四区；修改主机或端口会即时离线校验，测试连接有明确的连接中、可用和失败状态。
- 增加离线模拟协议、未测试/可用/不可用状态、`getTelescopePosition` 和 `centerScreenOnTelescope`；修正 LX200 单字节确认等待和错误码校验，避免每条 `:Sr`/`:Sd` 命令空等超时或把设备拒绝误报为成功。
- 增加 `setTelescopeLivePosition` 和面板实时位置状态；仅在用户开启、应用前台且望远镜面板可见时轮询，关闭面板、退后台或切换设备会停止。
- 增加原生星图望远镜十字标记、配置视场圈和屏外方向指示；转向动画全程维持交互帧率，真实设备标记按回报样本平滑移动。

## 后续顺序

1. P0：完成所有已有控制页的状态、错误、加载和取消反馈，补统一 CLI 回归。
2. P1：补 Satellites、MeteorShowers、Oculars、PointerCoordinates、TimeNavigator 和天文计算的剩余桌面字段。
3. P1：望远镜下一步验证真实设备长期稳定性；串口另做 HarmonyOS 设备权限与 Qt SerialPort 验证，星闪按 `docs/harmonyos/TELESCOPE-NEARLINK-RESEARCH-2026-09-02.md` 先做接口和服务诊断，再按厂商协议实现；NexStar、INDI、ASCOM、RTS2 分开评估，不与 LX200 桥耦合。
4. P2：继续补本地文件型编辑器，包括 SolarSystemEditor、SkyCultureMaker 的文化分布多边形，以及 LensDistortionEstimator。
5. P3：备案和权限方案明确前，保持 OnlineQueries、Planes、RemoteControl、RemoteSync、Vts 关闭。

## 验证口径

设备验证应覆盖配置新增/更新/删除/默认槽、J2000/JNow、屏幕中心目标、私网连接失败状态，以及 `8.8.8.8` 和主机名在 `connectionAttempted=false` 时被拒绝。验证只读诊断不得产生连接日志。构建验证使用 `cmake --build build --parallel --target stellarium`、`scripts/sync-ohos-build-sources.sh` 和 `scripts/check-ohos.sh`。

## 入口回归矩阵

设备实际加载的 28 个插件均已按 ID 走集中路由。控制型插件进入独立面板；目录型插件进入搜索分类；时间方程、时间导航器、历法、可观测性和文本界面进入唯一宿主；`ObjectVisibility` 复用“天文计算 > 可观测性”，`SkyCultureMaker` 进入独立制作器。`SolarSystemEditor`、`LensDistortionEstimator`、`Oculus`、`Vts`、`SimpleDrawLine` 和 `HelloStelModule` 仍显示明确的“未移植”，不再默认跳到语义不一致的页面。

`pluginFeatureRoute` 是唯一入口判定点，插件管理卡片和 CLI `openPluginFeature` 共用这张表。新增插件必须同时补路由、宿主、CLI/资源边界和本矩阵，禁止依赖默认 `unavailable` 以外的猜测性跳转。
