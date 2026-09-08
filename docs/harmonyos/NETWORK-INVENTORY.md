# HarmonyOS 联网功能台账

## 2026-09-08 审核冻屏：Qt 构建期来源

- `scripts/build-ohos-platform-patch.sh` 仅在开发机缺少指定源码压缩包时访问 `https://codeload.github.com/qt/qtbase/tar.gz/97575d35c0cecdc0fb4e12fc3575afaa9fd9d3f1`；固定修订及 SHA256，支持 `QTBASE_ARCHIVE` 本地包。只发送普通下载请求，不包含应用个人信息或签名材料。
- 不增加应用运行时联网、读取剪贴板或设备标识权限；没有新增国内镜像。后续内部镜像须遵守 Qt 授权并保留同一摘要，不能以不明镜像替换依赖。
- 原生隐私/剪贴板探针只记录调用阶段，不输出 SN、UDID 或剪贴板正文；CLI 写入测试为设备本地调试，返回成功/失败及字符数。

> 用途：记录 Stellarium HarmonyOS 版本中所有可能产生网络请求的运行时功能、插件和开发构建步骤。
>
> 维护规则：新增或修改 URL、网络 API、自动更新、文件下载、远程端口或外部网页跳转时，必须先更新本文件，再修改代码。

## 当前结论

- 2026-09-08 隐私复核：AppGallery 隐私托管服务与系统定位可能独立联网，不能用本应用未声明 INTERNET 承诺全部系统服务离线。用户拟启用境内服务器不代表当前已上传个人数据；现版本定位及姿态按本地处理设计。SN 在 Qt 初始化链被审核发现，其实际处理路径尚待核验，不得外发、写入探针或以“外设连接”作未经验证的解释。AGC 新整改草稿仅保存，未发布；详见 `PRIVACY-REVIEW-2026-09-08.md`。没有新增运行时下载地址或开放联网权限。

- HarmonyOS 构建默认启用 `STELLARIUM_OHOS_OFFLINE=1`。
- 卫星插件以及 Exoplanets、MeteorShowers、Novae、Supernovae、Pulsars、Quasars 六个目录插件在 HarmonyOS 离线构建中已在代码级禁用在线更新：不创建网络管理器、不启动更新定时器，旧配置也不能重新开启更新。
- 核心 IP 定位、在线搜索和星表下载在该构建开关下被编译禁用。
- 插件自身的网络实现仍保留，后续若在 HarmonyOS 暴露对应入口，必须增加隐私说明、权限/同意流程、超时和内置数据回退。
- 当前鸿蒙 `module.json5` 未声明 `ohos.permission.INTERNET`，因此已生成 HAP 没有系统授予的公网访问权限；这属于运行时权限边界，不等同于源码中所有网络请求代码都已移除。
- 严格“整个应用绝对不联网”尚未完成代码级封口：HiPS/TOAST、OnlineQueries、NebulaTextures Plate Solver、Planes、MPC 导入和 RemoteSync 的网络实现仍编译保留，必须在提交未备案版本前禁用入口并增加统一离线构建门禁；本台账不会把“未声明 INTERNET 权限”冒充为所有网络代码已经删除。
- 地图 SDK 当前按项目决定暂缓，不接入花瓣地图或其他地图 SDK。
- 本轮复核新增 `docs/harmonyos/OFFLINE-FEATURE-MATRIX.md`：明确区分“可随包内置”“只能构建机更新”“需要用户主动联网/设备连接”，并补齐六类静态目录的构建机更新命令；不能因为存在镜像路径就宣称客户端已完成本地化。
- 本轮再次核对网络类调用后，补登记星表下载页、帮助页检查更新、卫星自定义 TLE 导入和 Vts 本机连接；“打开外部网页”“局域网控制”和“公网数据请求”分开记录，不能只用“无 INTERNET 权限”作为唯一结论。
- `NebulaTextures` 的 HarmonyOS 入口只接受本地文件并复制到应用用户目录，纹理配置、映射和解码均在本机完成；`importNebulaTexture`、`refreshNebulaTextures` 和 `validateNebulaTexture` 不发起网络请求。上游 Plate Solver 仍保留在桌面插件代码中，但鸿蒙 ArkUI 与 CLI 均明确禁用图像上传，不能把它描述为已本地化。

## 研发参考网址（不属于运行时联网）

### 2026-09-08 多波段天空预研

- 开发机读取 IVOA、ESA、NASA/IRSA、CDS、Sky Guide 支持页及华为开发 MCP，见 `MULTIWAVELENGTH-SKY-RESEARCH-2026-09-08.md`；应用运行时未增加 URL、权限或请求。
- 通过 `alasky.cds.unistra.fr/hipslist` 及 RASS、GALEXGR6_7 NUV、2MASS Color 的 properties 核对来源/覆盖/格式，未下载整套巡天；SIMBAD TAP 仅发出公开标识 `HIP 91262` 的光谱型查询，无用户位置、设备标识、文件或账户信息外发。
- 将来离线包/境内镜像复用现有资源 provider；本地包必须禁止 properties 外链逃逸。中国虚拟天文台 HiPS 已见 CDS 注册记录，但本站实测、内容授权、覆盖与服务保障未验，不能宣称完整替代。
- 后续开放时分别登记清单/瓦片请求、SIMBAD 元数据补齐；数据提供方可从远程瓦片路径推断感兴趣的天区，应披露且不附加观测位置或设备标识。本轮仅设计，不改服务部署。

2026-09-07 服务器准备：用户购入阿里云上海 ECS，并授权创建 Workbench 官方服务关联角色管理实例。仅准备服务器本机 `127.0.0.1:8080` 健康检查服务；系统依赖通过实例现有官方软件源安装，外发服务器 IP/软件包请求，不上传用户天文数据。此阶段不开放公网服务、不修改安全组、不新增客户端联网权限、不自动抓取上游资源。阶段状态及上线门禁见 `SERVER-PREPARATION.md`。

同日后续用户授权安全加固：安全组 SSH 从全网收紧为 Workbench `100.104.0.0/16`，删除 TCP 3389 入站放行，保留 ICMP 与既有出站规则；全新 CLI 连接通过。通过 Workbench/OSS 上传两个不含秘密的审计及普通用户部署脚本，哈希验证后执行；审计日志仅存服务器本地，不新增日志外发或应用联网。最新边界见 `SERVER-SECURITY.md`。

同日 19:48 用户批准安全更新：通过 Workbench/OSS 上传不含秘密的安全更新脚本，服务器使用已配置的 alinux3 官方源下载元数据和 35 个安全更新包，启用 GPG 校验、不使用 EPEL；外发软件包请求和服务器网络信息，不上传备份、用户资料或应用数据。完成一次批准的重启，资源仍不对公网提供服务。配置备份仅存服务器 0700 目录，未新增收费存储、日志投递或自动更新计划。

同日开发机安装 Workbench CLI 1.0.1：从用户指定的阿里云 `workbench-cli.oss-cn-hangzhou.aliyuncs.com` 获取 ARM64 二进制并校验 SHA-256；从 `aliyun/alibabacloud-aiops-skills` 核对官方 Skill。CLI 使用阿里云 API/WebSocket，外发认证请求、实例/地域及运维命令，返回状态输出；文件传输经过 OSS 中转。19:29 用户配置凭据后指定实例只读 exec 已通过，未传输文件或应用数据。密钥不进入聊天和仓库。这些仅为开发运维工具，不打包进 APP；当前安全组及后续收紧项见 `SERVER-PREPARATION.md`。

同日单实例 RAM 授权准备：用户创建 `skyinstrument-cli` 并批准单台上海 ECS 的查询/命令运维权限；向阿里云 RAM 提交的策略仅涉及该云账号和实例标识，不含 APP 用户数据。官方说明首次有效 CLI 连接可能自动添加 `100.104.0.0/16 → TCP 22` 内网安全组规则，因此须先核对现状、必要时另行确认；当前未执行此安全组变更。权限策略和凭据验证状态见 `SERVER-PREPARATION.md`。

2026-09-07 通过华为开发文档 MCP 和华为云/NADC/LAMOST 官方网页继续复核，报告见 [国产化、分发与资源下载](DOMESTIC-RESOURCE-DISTRIBUTION-RESEARCH-2026-09-07.md)。仅开发机查询公开文档，未请求私人观测数据、账号或设备标识，未新增运行时 URL、权限、下载任务或云服务配置。

后续候选机制明确分开：AppGallery Kit 按需应用模块、request.agent 普通资源下载、游戏资源加速、构建用 ohpm-repo。均未接入生产。普通资源拟用国内对象存储/CDN，地址未定；访问会暴露 IP/时间/资源 ID，瓦片还可推断天区，不以“国内镜像”宣称零外发。游戏服务的非游戏接入资格、当前 SDK 不支持的 API 26 暂停模块下载能力都不得预设可用。

合规表述修订：华为核准指引包含单机 APP 的申报情形，运行时离线是当前项目决策，不把“未备案”简化为一律不可分发；新增公网资源下载需重新核对申报和隐私，不能通过系统代下载绕开。当前构建镜像尚缺可信远端清单校验，详见新报告与已知问题。

2026-08-30 对 Sky Guide/Fifth Star Labs 官方官网、News 和 Support 的只读调研仅用于产品设计参考，不会被打包进应用运行时请求列表，也不会因此新增公网权限、网页跳转或数据外发。调研记录见 `docs/harmonyos/SKY-GUIDE-FEATURE-RESEARCH-2026-08-30.md`。其官方页面确认了滤镜、卫星过境、离线运行、AR、时间控制、对象引导、桌面摘要和星声等交互思路；本项目只复用业务抽象和视觉原则，不复制专有图标、照片、插画或代码。

## 统一数据源替换契约

- 所有可替换的目录、巡天资源和在线接口先登记在 `data/ohos/network-sources.json`，由 `scripts/check-ohos-network-sources.mjs` 校验。
- 构建机支持 `local`、`mirror`、`upstream` 三种来源模式；应用运行时不读取来源 URL，也不新增公网网络权限。
- 卫星更新器已经接入该契约：默认 `upstream` 保持原有开发流程；发布构建应使用 `--source-mode local`，镜像构建必须显式指定 `--source-mode mirror --mirror-base-url ...`。
- `local` 模式读取仓库相对路径下的审核缓存，`mirror` 和 `upstream` 只允许出现在开发/构建阶段；清单记录来源模式、解析端点、字节数和 SHA-256，不记录设备标识、位置或用户查询。
- 这套注册表是替换接口和审计边界，不等同于所有桌面插件已经完成本地化；每个新接入项仍需单独核对授权、隐私字段、缓存和失败回退。

## 预研但未接入的本地设备通信

星闪望远镜控制目前只完成接口预研，未加入生产代码、未申请 `ACCESS_NEARLINK`、未扫描或连接设备。星闪属于本地无线设备通信，不等于公网联网，但仍需单独记录权限、设备标识和控制数据边界。设计与分阶段路线见 `docs/harmonyos/TELESCOPE-NEARLINK-RESEARCH-2026-09-02.md`。

| 功能 | 当前状态 | 计划触发方式 | 本地数据 | 网络边界 |
| --- | --- | --- | --- | --- |
| 星闪望远镜控制（SSAP） | 预研，未接入 | 用户主动发现、配对、连接并选择设备；不会自动扫描或后台连接 | 星闪设备地址、名称、服务 UUID、设备能力、目标 RA/Dec 和设备回传位置；默认脱敏日志 | 不访问互联网，不通过星闪转发公网请求；接入前需用户授权、错误/超时/断开处理和能力握手 |

## 运行时联网台账

2026-09-06 卫星异常排查：开发机手动访问 `https://celestrak.org/NORAD/elements/gp.php?CATNR=69196&FORMAT=TLE`，仅外发公开 NORAD 编号/返回格式，取得并校验 STARLINK-36933 的 2026-09-05 TLE 后写入内置资源。没有外发用户观测位置或设备标识，没有新增应用网络请求。来源、文件哈希及单条更新范围见 `SATELLITE-PROPAGATION-AUDIT.md`；其余目录未因此视为已更新。

| 功能/插件 | 默认状态 | 触发方式 | 当前地址或来源 | 传输/返回内容 | 国内镜像或替代评估 |
| --- | --- | --- | --- | --- | --- |
| SIMBAD 在线搜索 | 关闭 | 用户在搜索中主动启用在线搜索 | `https://simbad.u-strasbg.fr/`；备用 `https://simbad.cfa.harvard.edu/`、`https://simbad.cds.unistra.fr/` | 用户输入的天体名称/查询词；返回天体匹配结果 | 不直接抓取镜像。需确认服务协议、限流和数据归属后，才评估国内代理或同类服务 |
| OnlineQueries：系外行星 | 非默认后台任务 | 用户主动执行在线查询 | ASE：`https://ase.exopla.net/index.php/%1` | 天体名称、查询参数；返回系外行星资料 | 不建议未经授权做静态镜像；优先保留可配置服务地址 |
| OnlineQueries：变星 | 非默认后台任务 | 用户主动执行在线查询 | AAVSO VSX：`https://www.aavso.org/vsx/` | 天体名称/坐标；返回变星资料 | 不建议抓取固定镜像；需使用有公开协议的 API 或用户配置地址 |
| OnlineQueries：恒星目录 | 非默认后台任务 | 用户主动执行在线查询 | GCVS：`http://www.sai.msu.su/gcvs/` | 天体名称/查询词；返回恒星资料 | 未验证国内等价公开 API，暂不替换 |
| OnlineQueries：百科 | 非默认后台任务 | 用户主动打开百科链接 | `https://en.wikipedia.org/wiki/%1` | 天体名称进入外部网页 | 不做内容镜像；后续可评估合法中文百科入口，但需保留来源和许可说明 |
| Exoplanets | HarmonyOS 严格离线 | 运行时无更新入口；开发/构建机显式更新后重新打包 | `plugins/Exoplanets/resources/exoplanets.json`；上游 `https://www.stellarium.org/json/exoplanets.json` | HAP 内置系外行星目录 JSON | 可做国内版本化静态镜像，但必须确认上游授权、版本、校验和署名 |
| MeteorShowers | HarmonyOS 严格离线 | 运行时无更新入口；开发/构建机显式更新后重新打包 | `plugins/MeteorShowers/resources/MeteorShowers.json`；上游 `https://stellarium.org/json/MeteorShowers.json` | HAP 内置流星雨目录 JSON，功能本身不依赖网络 | 可做国内静态镜像；需保留 IAU/IMO 来源和更新时间 |
| Novae | HarmonyOS 严格离线 | 运行时无更新入口；开发/构建机显式更新后重新打包 | `plugins/Novae/resources/novae.json`；上游 `https://stellarium.org/json/novae.json` | HAP 内置新星目录 JSON | 可做国内静态镜像；先核对数据许可 |
| Supernovae | HarmonyOS 严格离线 | 运行时无更新入口；开发/构建机显式更新后重新打包 | `plugins/Supernovae/resources/supernovae.json`；上游 `https://stellarium.org/json/supernovae.json` | HAP 内置超新星目录 JSON | 可做国内静态镜像；先核对数据许可 |
| Pulsars | HarmonyOS 严格离线 | 运行时无更新入口；开发/构建机显式更新后重新打包 | `plugins/Pulsars/resources/pulsars.json`；上游 `https://stellarium.org/json/pulsars.json` | HAP 内置脉冲星目录 JSON | 可做国内静态镜像；先核对数据许可 |
| Quasars | HarmonyOS 严格离线 | 运行时无更新入口；开发/构建机显式更新后重新打包 | `plugins/Quasars/resources/quasars.json`；上游 `https://stellarium.org/json/quasars.json` | HAP 内置类星体目录 JSON | 可做国内静态镜像；先核对数据许可 |
| Satellites | HarmonyOS 运行时严格离线 | 应用内可查看/保存 TLE 来源；`importSatelliteTle` 只导入本地文件；`refreshSatelliteCatalog` 在离线包中拒绝网络；仅开发/构建机显式运行 `scripts/update-ohos-astronomy-data.mjs --update-satellites` | CelesTrak GP 3LE：`stations`、`visual`、`active`；SatNOGS TLE API 作补充；用户可保存自定义 `file/http/https` 来源 | 构建机下载公开 TLE，验证后写入下一次 HAP 内置目录；运行时不请求、不保存远程响应；远程 URL 仅作为休眠配置展示 | 构建机可后续评估合规镜像；当前保留来源、时间、校验和和失败回退，部分源失败时标记 `partial`，不把旧数据伪称最新；本地导入不需要镜像 |
| Planes | HarmonyOS 离线包强制禁用；桌面版默认关闭 | 桌面版用户开启飞机图层且处于实时模式；默认约每 15 秒请求。HarmonyOS 离线包在编译门禁下不创建请求 | `https://opendata.adsb.fi/api/v2/lat/%1/lon/%2/dist/%3`；备用 `https://api.airplanes.live/v2/point/%1/%2/%3` | 桌面版外发当前观测纬度、经度、半径；返回实时航空器信息 | 不建议简单镜像，数据时效性决定必须访问实时服务；当前 HarmonyOS 离线包不接入；未来若备案后接入，需单独评估国内服务或受控镜像 |
| HiPS 远程星图层（在线巡天） | 默认不显示 | 鸿蒙端“视图/巡天”页打开“HiPS 巡天”，或恢复了已保存的可见远程图层；页面提示“在线巡天需要网络连接” | 默认目录源：`http://alasky.u-strasbg.fr/MocServer/query?*/P/*&get=record`、`https://data.stellarium.org/surveys/hipslist`；每个图层还请求图层根目录下的 `properties`、不同层级的 `Norder.../Dir.../Npix...` 瓦片及可能的缩略图 | 巡天目录、图层元数据、当前视场对应的多级图像瓦片；请求路径中可能包含当前天区坐标/瓦片编号 | 适合自建合规 HiPS 镜像，但工作量大，需同步目录、元数据和多级瓦片；先确认上游数据许可、署名和更新策略；不接地图 SDK |
| DSS/TOAST 数字化巡天（在线巡天） | 默认不显示 | 鸿蒙端“视图/巡天”页打开“DSS/TOAST 巡天”开关后，按当前视场加载图像 | 默认 `http://dss.stellarium.org/survey/{level}/{x}_{y}.jpg` | 当前天区对应层级、横纵坐标的 JPG 图像瓦片 | 可部署完整瓦片镜像，但需确认原始数据许可、瓦片生成方式和存储成本；目前未验证国内等价公开服务 |
| SolarSystemEditor：MPC 小行星/彗星在线导入 | 不自动请求 | 用户在太阳系编辑器打开 MPC 导入窗口，手动选择下载列表、输入 URL 或执行在线 MPES 查询 | MPC 列表和轨道文件：`https://www.minorplanetcenter.net/iau/Ephemerides/...`、`https://www.minorplanetcenter.net/iau/MPCORB/...`、`https://www.minorplanetcenter.net/iau/ECS/MPCAT/...`；部分编号小行星列表使用 `http://dss.stellarium.org/MPC/mpn-{01..90}.txt`、`mpu-{01..62}.txt`；在线 MPES 查询：`https://www.minorplanetcenter.net/cgi-bin/mpeph2.cgi` | 用户选择的对象列表、轨道根数文件或查询参数；返回小行星/彗星轨道元素和星历数据，并可保存到本地 | 这不是巡天图像图层。优先保留手动导入和内置数据；不建议未经授权镜像 MPC 数据，国内部署前需确认 MPC/IAU 数据许可、服务条款、更新频率和查询接口合规性 |
| 自动 IP 定位 | HarmonyOS 核心路径关闭 | 非 HarmonyOS 或配置为自动位置时触发 | `https://freegeoip.stellarium.org/json/` | 设备公网 IP 推断出的粗略位置 | HarmonyOS 使用北京兜底，不应恢复该请求；国内定位替代应优先使用用户手动位置或经过同意的系统定位 |
| 深星表下载 | HarmonyOS 严格离线 | 桌面配置页用户点击下载更深 `hip_gaia3` 分卷 | `src/gui/ConfigurationDialog.cpp` 中的星表下载 URL | 大体积星表文件，写入用户目录并校验 | 不作为客户端镜像；在构建机预置并审计后随包，受体积、启动时间和授权限制 |
| 帮助页检查更新 | HarmonyOS 应关闭 | 用户主动点击“检查更新” | `https://api.github.com/repos/Stellarium/stellarium/releases/latest` | 版本元数据和发行页链接 | 未备案包禁用；关于/帮助中的网址仅在用户主动打开时交给系统浏览器 |
| 卫星自定义 TLE 导入 | HarmonyOS 应改为本地导入 | 用户在卫星导入页触发源列表下载 | `plugins/Satellites/src/gui/SatellitesImportDialog.cpp` 使用用户配置的 TLE URL | TLE 文本并写入用户目录 | 可保留本地文件导入；不能把实时 TLE 静态镜像宣称为实时，镜像必须走构建期或备案后的显式更新 |
| RemoteControl | 默认不启动 | 用户/命令行启动本机 HTTP 服务 | 本机监听，默认端口 `8090` | 局域网请求可读取或控制应用状态；不是公网数据源 | 无需公网镜像；必须记录监听地址、密码、CORS 和局域网风险 |
| RemoteSync | 默认空闲 | 用户启动服务端或连接到指定主机 | TCP 局域网连接，端口由设置决定 | 会话状态、时间、位置、视角和同步属性 | 无需公网镜像；必须记录连接目标、认证和局域网暴露范围 |
| TelescopeControl 轻量 LX200 桥 | 不自动连接；默认新配置为离线模拟器 | 用户主动点击测试、转向、同步、停止、读取位置或居中到望远镜，显式调用对应 CLI，或主动开启面板内“实时位置” | 真实设备使用用户保存的回环或私网 IP 与 TCP 端口；离线模拟器不建立连接 | 测试发送只读 `:GR#` 赤经探针并校验 LX200 响应后断开；控制会发送目标 RA/Dec 和 LX200 指令；位置读取发送 `:GR`/`:GD`；实时位置仅在开关开启、应用前台且望远镜面板可见时约每秒读取一次，每次仍为短连接；不发送 SN、观测位置或隐私状态 | 不需要公网镜像。只允许本机/私网/链路本地地址；公网、主机名和未分类地址在 socket 前拒绝；不扫描、不监听、不在后台连接。离线模拟器明确标注，不冒充真实硬件 |

### 位置和隐私字段

- 目前已登记的外发位置数据包括：Planes 请求中的观测纬度、经度和搜索半径；HiPS/DSS 请求中的天区瓦片坐标；用户主动发送给远程同步服务的观测位置。
- SIMBAD、OnlineQueries 等查询会外发用户输入的天体名称或查询词。
- 深星表下载、卫星自定义 TLE 导入和帮助页检查更新不应在 HarmonyOS 未备案包中触发；它们分别外发下载请求、用户配置的 URL 请求和版本检查请求。
- RemoteControl、RemoteSync、TelescopeControl、Vts 走本机或局域网连接，不属于“国内公网镜像”问题，但仍可能暴露应用状态、观测位置、控制地址或设备端口。
- 本台账未发现将 SN、设备序列号或隐私政策同意状态作为上述天文查询参数发送的设计。新增网络功能不得把设备标识拼入 URL、请求头或分析参数。

## 开发和构建阶段联网

| 阶段 | 来源 | 说明 | 国内镜像/替代 |
| --- | --- | --- | --- |
| CMake 配置/首次构建 | GitHub `CalcMySky`、`QXlsx`、`md4c`、`fast_float`、`indi`、`nlopt`、`SkyCultureMaker` 依赖 | 仅开发机器构建时下载，不属于 App 运行时联网 | 优先使用本地缓存、制品仓库或经过审计的国内代理；构建环境应支持离线复现 |
| Qt/HarmonyOS 工具链 | Qt、HarmonyOS SDK、DevEco/ hvigor 依赖 | 由开发环境和工具链管理 | 使用已审核的官方安装源或企业制品库，不在 App 内处理 |
| 文档/外部链接 | 源码注释、关于页、帮助页中的官网和项目链接 | 打开链接时可能由系统浏览器联网 | 不等同于应用后台联网；如 HarmonyOS 暴露入口，需标记“将打开外部网页” |

## 镜像站实施建议

### 第一阶段：适合做静态镜像

优先考虑 Exoplanets、MeteorShowers、Novae、Supernovae、Pulsars、Quasars 六类 JSON。它们已经随插件 QRC 内置，未备案阶段不需要运行时镜像；备案后若要缩短发版周期，再使用构建机镜像同步，校验成功后重新生成 HAP。镜像服务应使用 HTTPS、固定版本或 `ETag`/`Last-Modified`、SHA-256 或签名校验，并在失败时继续使用应用内置目录。镜像前必须确认原始数据的再分发许可、署名和更新频率。

### 第二阶段：需要专门服务

卫星 TLE 可以做国内定时同步服务，但必须保留原始来源和历元信息；HiPS/DSS 需要同步目录、元数据和多级瓦片，不能只替换一个首页 URL。

### 暂不替换

SIMBAD、AAVSO/GCVS/Wikipedia、实时飞机数据目前没有在本项目中验证过授权清晰、接口稳定且功能等价的国内替代。未完成验证前保持用户可选、默认关闭或继续使用内置数据，不宣称存在等价服务。

星表下载、卫星自定义 TLE 导入、帮助页版本检查和 Plate Solver 也不应直接套用静态镜像方案：前两者可以优先改为构建机/本地文件流程，帮助页可以随包携带版本信息，Plate Solver 则涉及用户图像上传，必须单独取得同意并提供本地失败回退。

## 新增联网功能登记模板

开发新功能时复制以下条目并填写：

| 项目 | 内容 |
| --- | --- |
| 功能/插件 |  |
| 运行时还是构建时 |  |
| 默认是否联网 |  |
| 触发方式 |  |
| 完整 URL/端口 |  |
| 外发字段 |  |
| 返回数据和本地缓存 |  |
| 超时、失败回退 |  |
| 国内镜像可行性 |  |
| 数据授权/署名 |  |
| 隐私、权限和审核影响 |  |
| 相关代码和测试 |  |

## 2026-09-07 网站备案与项目官网本地预览

- `website/` 为独立静态网站，不改变 HarmonyOS 应用离线策略、权限、签名或资源后端。
- 构建阶段从 npm registry 获取依赖；网站运行时字体、星群绘制、应用截图均本地，无自动第三方图片/字体、统计、广告或账号请求。
- 网站外链：`https://github.com/joinother/stellarium`、其 `/issues`、`https://stellarium.org/`。仅用户主动点击打开，浏览器会向目的站发送常规网络连接信息；不携带应用观测位置、搜索词、设备号或账号凭据。
- 本地静态预览仅监听 `127.0.0.1:3000`，只读 GET/HEAD，无上传和目录列表。开发框架预览只用于本机，不可作为公网生产服务。
- 计划在已购国内 ECS 静态托管 `skyinstrument.cn`，不部署第三方云，不改变 DNS/安全组，不为未完成备案开公网。镜像/资源更新 API 与官网分开，不能将官网上线等同于应用联网功能已授权。
- 已在阿里云原订单新增网站，保留 APP；当前进入身份证/人脸验证及真实性承诺书上传阶段，未正式提交审核。资料由本人处理，不在仓库保存身份证、住址、电话或签名照片。
- 正式上线前核实个人主体与真实网站用途、获得真实备案号并展示、完善运营联系和日志留存隐私说明、验证依赖安全/授权；具体见 `website/README.md`。

## 2026-09-08 天文通调研：候选联网能力，尚未启用

- 研究报告：`STARGAZING-HUB-RESEARCH-2026-09-08.md`。本轮仅操作用户已安装的第三方应用、查阅公开资料与华为文档；不改变星象仪运行时联网行为、签名、权限或服务端配置。第三方应用页面的联网不等于星象仪已经接入这些服务；未对该应用抓包，不能宣称掌握其完整外发字段。
- 研究来源：`laysky.com`、`stargazinghub.com`、Apple App Store、Google Play、`github.com/esa/tetra3`、`github.com/dstndstn/astrometry.net`、华为开发知识 MCP。仅开发阶段查阅，不写入应用下载白名单，也不调用天文通私有接口。

| 候选功能 | 未来触发/默认状态 | 预计外发字段，实施前再审计 | 离线回退与国内化边界 |
|---|---|---|---|
| 观星天气与地点对比 | 用户主动刷新；目前关闭 | 经用户确认的观测坐标或地区、预报时间范围、语言；不发送设备序列号 | 本地天文窗口保持可用，气象缓存标过期；供应商未选定，云层/视宁度字段与商用缓存权需验证 |
| 地图/光害/高程包 | 用户打开地图或选择离线区域；目前不新增接入 | 地图瓦片范围、层级、资源版本；区域本身可能暴露位置 | 无底图方位示意、合法内置地景；地图合规与数据再分发权独立核验，不擅自镜像 |
| TLE/流星目录更新 | 明确更新操作及未来可关闭的策略；不在本轮改变当前默认 | 目录/卫星 ID、版本；本地传播不需要上传观测位置 | 经许可内置包，显示数据历元和年龄；沿用现有更新清单审计，不能用下载日伪装新 TLE |
| 解算索引与高清资源 | 用户主动选择下载；目前只预研 | 资源包 ID、版本、下载范围；索引下载无需照片内容 | 本地包优先；授权后对象存储/CDN 分发、完整性校验、失败恢复 |
| 在线照片解算 | 独立选择并说明上传范围；默认关闭 | 图片内容，可能含 EXIF/位置/设备信息；上传前最小化元数据 | 本地解算失败不得自动转云端；供应商、保留期限、删除机制和权限均未确定 |
| 极光/太阳实时资料 | 用户主动刷新；默认关闭 | 数据类型、时间、必要时区域；无需账号/设备号 | 历史缓存标时间；近实时数据不伪装离线推算，国内等价来源尚未确认 |

- 本地事件提醒与服务卡片不必依赖云推送；更新卡片应读共享快照，不启动后台星图渲染或偷偷刷新所有网络数据。
- 用户自定义来源不豁免离线开关、来源说明、大小/协议/重定向限制和数据校验；服务端代理需单独阻止 SSRF，不把局域网设备控制权限扩展成任意 URL 抓取权限。
- 上述均未选定正式供应商，API 端点、配额、费用、授权和验收为后续开放门槛；本轮不新增外链入口、不采购、不部署。

### 同日补充：laysky.com 官网关联来源

- 仅开发调研：阅读官网教程、下载/隐私页面，并经官网链接访问 `darkmap.cn`（重定向至 `www.darkmap.cn`）。官网另列 `ms.darkmap.cn`、`game.darkmap.cn`、`cs.darkmap.cn` 工具入口；这里只登记链接发现，不表示已测试或接入。
- 页面公开说明涉及世界夜空亮度图集、VIIRS、JMA 云图、ECMWF 与地图服务；旧天气教程还提到 OpenWeather。它们是候选来源线索，不是本项目新增供应商，也不是当前天文通完整网络拓扑的证据。
- 原始图集 DOI `10.5880/GFZ.1.4.2016.001` 访问未成功，许可未核验；不得据此自动下载打包。没有获取竞品瓦片、使用私有接口、向其提交图片或主动填写用户坐标。
- 后续若开发观测分享卡，默认隐藏精确观测位置；导出本地文件不等于联网分享，用户选择分享目标后再解释外发内容。新官网帮助/数据页目前仅规划，不新增应用网络权限或外链。
