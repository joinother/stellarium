# HarmonyOS 联网功能台账

## 2026-10-01 备案后联网服务再审

本轮重新核对了构建开关和已部署官网：`scripts/set-ohos-network-mode.sh status` 显示当前是联网构建（`INTERNET` 已声明、`STELLARIUM_OHOS_OFFLINE=OFF`、`OFFLINE_APPGALLERY_BUILD=false`）。但联网构建只表示网络代码和权限边界已打开，不表示所有服务已经上线或默认运行。

- 官网目前仍是静态站点；`https://skyinstrument.cn/health`、`/v1/health`、`/v1/catalogs/satellites/stations.3le`、`/v1/catalogs/exoplanets.json` 和 `/v1/surveys/hips/index.json` 当前均返回 404。应用暂不能把官网当作资源 API，也不能打开自动资源更新。
- 当前应继续把恒星、行星纹理、深空图片、天空文化、地景、脚本、六类小型目录和卫星快照作为随包资源；卫星过期提示和用户主动更新入口与服务端上线分开验收。
- 第一阶段只部署版本化静态清单和小型目录/TLE 文件：无账号、无上传、无 SN/UDID/位置/查询词；使用 HTTPS、ETag、大小限制、SHA-256/签名校验、临时文件下载、原子替换和旧版本回退。当前 ECS 足够做验证，不需要先引入数据库或 CDN。
- 第二阶段再评估 HiPS/DSS/多光谱瓦片、天气和 ADS-B。它们分别涉及大流量、天区/位置外发或实时数据，不能复用“小型 JSON 镜像”方案，也不应由一个总开关统一开启。
- SIMBAD、AAVSO/GCVS、MPC、Plate Solver、Push、实况窗、接续和 IAP 继续单独处理：它们分别涉及查询词、用户图片、设备令牌、跨设备状态或订单权益，不属于静态资源分发。
- RemoteControl、RemoteSync、LX200/OnStep/星闪仍限定本机、局域网或本地无线设备，不通过公网服务器中转，也不因备案完成而开放公网监听。

**后续执行顺序：** 先在服务器完成健康检查、资源清单和小型静态文件的灰度端点，再接入应用“用户主动更新”；通过断网、超时、坏签名、空间不足、旧版本回退和隐私撤回测试后，才考虑默认展示在线入口。每个新 URL、AGC 能力、上传字段或后台任务必须先登记到本台账和 `data/ohos/network-sources.json`。

### ECS 承载边界与扩容顺序

- 当前 ECS 适合承载官网、健康检查、版本化清单和小型 TLE/目录文件；不应把高清深空图、HiPS 多光谱瓦片或大规模下载流量长期直接压在单台实例上。
- 当前 Workbench CLI 凭据缺少 `ecs:DescribeInstances` 的只读授权，因此本轮不能据此确认实例的 CPU、内存、磁盘和带宽规格；不扩大运维权限前，不对“当前规格足够”作精确承诺。
- 扩容按实测顺序进行：先监控 CPU、内存、磁盘 I/O、出口带宽、请求量和错误率；静态资源增长后迁移到 OSS + CDN；API 并发持续增长后再增加 ECS 并通过负载均衡分流；数据库、缓存和自动伸缩最后按实际瓶颈引入。
- 近期不预购 CDN/OSS。应用仍保留随包资源和旧版本回退；任何云端资源上线前，必须完成清单签名、SHA-256、大小限制、超时、原子替换、权限和隐私审计。

## 2026-09-30 全量联网本地化复核

本工程当前为联网构建：`ohos.permission.INTERNET` 已声明、`STELLARIUM_OHOS_OFFLINE=OFF`、`OFFLINE_APPGALLERY_BUILD=false`。这只打开了权限和已实现代码路径，不代表所有第三方数据源、华为开放能力或资源服务器已经上线。逐项状态以 `data/ohos/network-localization.json` 为准，审计命令为 `node scripts/check-ohos-network-localization.mjs`，完整说明见 `policy/NETWORK-LOCALIZATION-MATRIX.md`。

- 已完成本地化：卫星内置 TLE、系外行星、流星雨、新星、超新星、脉冲星、类星体、基础星表、高清资源、地景、天空文化、脚本和本地设备能力；断网使用随包数据。
- 可做境内静态镜像：卫星 TLE 和六类小型 JSON。镜像只提供版本化静态文件，不接收 SN、UDID、位置、查询词或账号；应用必须保留随包回退。
- 尚未完成：官网下的资源接口当前实测 404；HiPS/DSS、多光谱瓦片、SIMBAD/AAVSO/GCVS、实时 ADS-B、照片解算、天气、Push、实况窗、接续和 IAP 仍需分别完成许可、Profile、隐私、服务端或真机验收。
- 多光谱首批已接入用户主动触发的 HiPS 元数据与图层入口：RASS X 射线、GALEX NUV 和 2MASS Color；首次选择时才请求对应 `properties` 与可见瓦片，默认不加载。客户端已加入固定数据集、超时和网络错误回传；数据源、覆盖率、许可证和境内镜像仍须逐产品验收，不能视作已完成离线打包。
- 已明确不做公网镜像：IP 自动定位、望远镜公网中转、RemoteControl/RemoteSync 公网暴露；这些分别使用手动/系统定位和本机/局域网连接。

“已备案”不等于“所有联网功能自动合规”，也不等于上游数据拥有再分发许可。后续每增加一个 URL、API、推送令牌、上传文件或远程端口，都必须同时更新本台账和逐项矩阵。

## 2026-09-23 应用服务部署核查

完整分类、七份目录压缩体积、备案展示缺失和落地顺序见 `server/NETWORK-DEPLOYMENT-PLAN-2026-09-23.md`。22 个来源不等于 22 个服务：优先统一 TLE/六类目录静态更新，基础图像/文化继续随包；查询、瓦片、天气、推送、IAP 分别治理，局域网望远镜/基础本地提醒无需公网后端。

资源服务实测仍 staging/非公开。2026-09-23 从阿里云“我的备案 → App”核实星象仪 APP 号为 `新ICP备2026008516号-2A`，网站号为 `新ICP备2026008516号-1`。应用设置/关于展示 APP 号；点击号码才由系统打开 `https://beian.miit.gov.cn/`，不自动请求、不附加号码、SN、位置或账号参数。浏览器正常访问会发送 IP/标准请求头；官方查询不使用镜像。已加入本地代理提醒权限和代码，但未开放应用资源下载、未新增 INTERNET 权限，也未部署数据代理/支付/远程推送服务。

## 2026-09-23 官网部署与 APP 联网开放边界

- 官网 `https://skyinstrument.cn` 已部署至境内上海 ECS，www/HTTP 跳转 HTTPS；普通访问发送 IP、请求路径和标准浏览器请求头，不附加 SN、观测位置或设备标识。无广告/统计/远程字体，源码/反馈外链只在用户点击后打开。网站访问日志字段和期限见 `website/deploy/README.md`。
- 服务器管理面每日 ACME 续期检查连接 Let's Encrypt，发送公开域名、ACME 账户公钥及签名请求，私钥不外发；HTTP-01 验证开放临时挑战文件。自动续期已获用户同意，不属于 APP 运行时联网，不引入收费证书。
- 本轮未改变 APP 的 INTERNET 权限、Qt 离线宏、ArkUI 离线开关或应用签名。不能仅因网站备案成功，就直接打开所有上游自动更新或 IP 定位。原资源服务仍本机 staging，镜像尚未公开。
- 下一步按服务分批开放：TLE/轻量清单优先境内缓存、由用户主动更新并保留随包回退；星表/高清图/地景/天空文化仍随包及本地导入。大体积多波段瓦片后续再评估 OSS/CDN，当前未购买。
- 放开下载前仍需修正清单签名/哈希与原子落盘、HTTPS/重定向白名单、大小限制、超时和失败回退；隐私同意前禁止请求。天气/ADS-B/IP 定位、外部图像求解上传、任意用户 URL 不随总开关放开。不得把暂未部署的域名路径当作可用镜像。

## 2026-09-08 审核冻屏：Qt 构建期来源

- `scripts/build-ohos-platform-patch.sh` 仅在开发机缺少指定源码压缩包时访问 `https://codeload.github.com/qt/qtbase/tar.gz/97575d35c0cecdc0fb4e12fc3575afaa9fd9d3f1`；固定修订及 SHA256，支持 `QTBASE_ARCHIVE` 本地包。只发送普通下载请求，不包含应用个人信息或签名材料。
- 不增加应用运行时联网、读取剪贴板或设备标识权限；没有新增国内镜像。后续内部镜像须遵守 Qt 授权并保留同一摘要，不能以不明镜像替换依赖。
- 原生隐私/剪贴板探针只记录调用阶段，不输出 SN、UDID 或剪贴板正文；CLI 写入测试为设备本地调试，返回成功/失败及字符数。

> 用途：记录 Stellarium HarmonyOS 版本中所有可能产生网络请求的运行时功能、插件和开发构建步骤。
>
> 维护规则：新增或修改 URL、网络 API、自动更新、文件下载、远程端口或外部网页跳转时，必须先更新本文件，再修改代码。

## 当前结论

### 2026-09-30 数字商品与应用内支付（规划中）

- 当前仅准备华为数字商品协议签约和 IAP Kit 沙盒接入，正式支付、订单校验和权益服务尚未接入运行包。
- 计划由用户主动打开付费页后调用华为收银台；客户端不保存商户密钥，不把 SN/UDID、精确位置或观测查询词作为订单参数。
- 若后续增加自有订单/权益服务，必须登记境内 HTTPS 地址、传输字段、保存期限、退款/恢复流程和失败回退；订单号幂等校验应在服务端完成。
- 数字商品服务开通不等于自动开放其他地图、推送、实况窗、接续或第三方数据源；每项能力仍单独走 AGC、隐私和 Profile 门禁。路线详见 `research/DIGITAL-GOODS-AND-IAP-ROADMAP-2026-09.md`。

### 2026-09-23 备案后的分层开放边界

- APP 备案号已核实，但它不等于自动获得 `ohos.permission.INTERNET`、AGC 开放能力、Push/代理提醒资格或第三方数据再分发许可。每项能力仍按“权限—隐私告知—数据授权—失败回退—真机验收”单独开放。
- 本轮新增的后台代理提醒是本地系统能力：使用 `reminderAgentManager`，不联网、不读取 SN/UDID、不上传位置。它依赖用户授权和 AGC“代理提醒”能力/Profile，不依赖资源服务器。
- 首批可以开放的公网服务应只限自有 HTTPS 版本清单和静态目录更新，并且默认仍使用随包资源；当前 ECS 资源服务仍是 loopback staging，尚未作为 APP 下载端点，因此不能打开客户端自动更新开关。
- 望远镜控制分开处理：LX200/OnStep 走用户主动连接的局域网或串口；未来星闪走本地无线设备协议。它们不需要公网云代理，也不应把望远镜控制端口暴露到互联网或通过服务器中转。
- 天气、ADS-B、SIMBAD/MPC 在线查询、HiPS/DSS 多光谱瓦片、Plate Solver 上传和华为 Push 继续逐项申请/审计；备案后可进入开发和灰度阶段，但不能把所有第三方 URL 一次性默认打开。远程资源正式分发前还必须生成带版本、大小、SHA-256、签名、授权署名和旧版回退的清单。

- 2026-09-08 隐私复核：AppGallery 隐私托管服务与系统定位可能独立联网，不能用本应用未声明 INTERNET 承诺全部系统服务离线。用户拟启用境内服务器不代表当前已上传个人数据；现版本定位及姿态按本地处理设计。SN 在 Qt 初始化链被审核发现，其实际处理路径尚待核验，不得外发、写入探针或以“外设连接”作未经验证的解释。AGC 新整改草稿仅保存，未发布；详见 `PRIVACY-REVIEW-2026-09-08.md`。没有新增运行时下载地址或开放联网权限。

- HarmonyOS 构建默认启用 `STELLARIUM_OHOS_OFFLINE=1`。
- 卫星插件以及 Exoplanets、MeteorShowers、Novae、Supernovae、Pulsars、Quasars 六个目录插件在 HarmonyOS 离线构建中已在代码级禁用在线更新：不创建网络管理器、不启动更新定时器，旧配置也不能重新开启更新。
- 核心 IP 定位、在线搜索和星表下载在该构建开关下被编译禁用。
- 插件自身的网络实现仍保留，后续若在 HarmonyOS 暴露对应入口，必须增加隐私说明、权限/同意流程、超时和内置数据回退。
- 当前鸿蒙 `module.json5` 未声明 `ohos.permission.INTERNET`，因此已生成 HAP 没有系统授予的公网访问权限；这属于运行时权限边界，不等同于源码中所有网络请求代码都已移除。
- 严格“整个应用绝对不联网”尚未完成代码级封口：HiPS/TOAST、OnlineQueries、NebulaTextures Plate Solver、Planes、MPC 导入和 RemoteSync 的网络实现仍编译保留，必须在提交未备案版本前禁用入口并增加统一离线构建门禁；本台账不会把“未声明 INTERNET 权限”冒充为所有网络代码已经删除。
- 地图 SDK 当前按项目决定暂缓，不接入花瓣地图或其他地图 SDK。
- 本轮复核新增 `docs/harmonyos/specs/OFFLINE-FEATURE-MATRIX.md`：明确区分“可随包内置”“只能构建机更新”“需要用户主动联网/设备连接”，并补齐六类静态目录的构建机更新命令；不能因为存在镜像路径就宣称客户端已完成本地化。
- 本轮再次核对网络类调用后，补登记星表下载页、帮助页检查更新、卫星自定义 TLE 导入和 Vts 本机连接；“打开外部网页”“局域网控制”和“公网数据请求”分开记录，不能只用“无 INTERNET 权限”作为唯一结论。
- `NebulaTextures` 的 HarmonyOS 入口只接受本地文件并复制到应用用户目录，纹理配置、映射和解码均在本机完成；`importNebulaTexture`、`refreshNebulaTextures` 和 `validateNebulaTexture` 不发起网络请求。上游 Plate Solver 仍保留在桌面插件代码中，但鸿蒙 ArkUI 与 CLI 均明确禁用图像上传，不能把它描述为已本地化。

## 研发参考网址（不属于运行时联网）

### 2026-09-08 多波段天空预研

- 开发机读取 IVOA、ESA、NASA/IRSA、CDS、Sky Guide 支持页及华为开发 MCP，见 `MULTIWAVELENGTH-SKY-RESEARCH-2026-09-08.md`；应用运行时未增加 URL、权限或请求。
- 通过 `alasky.cds.unistra.fr/hipslist` 及 RASS、GALEXGR6_7 NUV、2MASS Color 的 properties 核对来源/覆盖/格式，未下载整套巡天；SIMBAD TAP 仅发出公开标识 `HIP 91262` 的光谱型查询，无用户位置、设备标识、文件或账户信息外发。
- 将来离线包/境内镜像复用现有资源 provider；本地包必须禁止 properties 外链逃逸。中国虚拟天文台 HiPS 已见 CDS 注册记录，但本站实测、内容授权、覆盖与服务保障未验，不能宣称完整替代。
- 后续开放时分别登记清单/瓦片请求、SIMBAD 元数据补齐；数据提供方可从远程瓦片路径推断感兴趣的天区，应披露且不附加观测位置或设备标识。本轮仅设计，不改服务部署。

2026-09-07 服务器准备：用户购入阿里云上海 ECS，并授权创建 Workbench 官方服务关联角色管理实例。仅准备服务器本机 `127.0.0.1:8080` 健康检查服务；系统依赖通过实例现有官方软件源安装，外发服务器 IP/软件包请求，不上传用户天文数据。此阶段不开放公网服务、不修改安全组、不新增客户端联网权限、不自动抓取上游资源。阶段状态及上线门禁见 `server/SERVER-PREPARATION.md`。

同日后续用户授权安全加固：安全组 SSH 从全网收紧为 Workbench `100.104.0.0/16`，删除 TCP 3389 入站放行，保留 ICMP 与既有出站规则；全新 CLI 连接通过。通过 Workbench/OSS 上传两个不含秘密的审计及普通用户部署脚本，哈希验证后执行；审计日志仅存服务器本地，不新增日志外发或应用联网。最新边界见 `server/SERVER-SECURITY.md`。

同日 19:48 用户批准安全更新：通过 Workbench/OSS 上传不含秘密的安全更新脚本，服务器使用已配置的 alinux3 官方源下载元数据和 35 个安全更新包，启用 GPG 校验、不使用 EPEL；外发软件包请求和服务器网络信息，不上传备份、用户资料或应用数据。完成一次批准的重启，资源仍不对公网提供服务。配置备份仅存服务器 0700 目录，未新增收费存储、日志投递或自动更新计划。

同日开发机安装 Workbench CLI 1.0.1：从用户指定的阿里云 `workbench-cli.oss-cn-hangzhou.aliyuncs.com` 获取 ARM64 二进制并校验 SHA-256；从 `aliyun/alibabacloud-aiops-skills` 核对官方 Skill。CLI 使用阿里云 API/WebSocket，外发认证请求、实例/地域及运维命令，返回状态输出；文件传输经过 OSS 中转。19:29 用户配置凭据后指定实例只读 exec 已通过，未传输文件或应用数据。密钥不进入聊天和仓库。这些仅为开发运维工具，不打包进 APP；当前安全组及后续收紧项见 `server/SERVER-PREPARATION.md`。

同日单实例 RAM 授权准备：用户创建 `skyinstrument-cli` 并批准单台上海 ECS 的查询/命令运维权限；向阿里云 RAM 提交的策略仅涉及该云账号和实例标识，不含 APP 用户数据。官方说明首次有效 CLI 连接可能自动添加 `100.104.0.0/16 → TCP 22` 内网安全组规则，因此须先核对现状、必要时另行确认；当前未执行此安全组变更。权限策略和凭据验证状态见 `server/SERVER-PREPARATION.md`。

2026-09-07 通过华为开发文档 MCP 和华为云/NADC/LAMOST 官方网页继续复核，报告见 [国产化、分发与资源下载](research/DOMESTIC-RESOURCE-DISTRIBUTION-RESEARCH-2026-09-07.md)。仅开发机查询公开文档，未请求私人观测数据、账号或设备标识，未新增运行时 URL、权限、下载任务或云服务配置。

后续候选机制明确分开：AppGallery Kit 按需应用模块、request.agent 普通资源下载、游戏资源加速、构建用 ohpm-repo。均未接入生产。普通资源拟用国内对象存储/CDN，地址未定；访问会暴露 IP/时间/资源 ID，瓦片还可推断天区，不以“国内镜像”宣称零外发。游戏服务的非游戏接入资格、当前 SDK 不支持的 API 26 暂停模块下载能力都不得预设可用。

合规表述修订：华为核准指引包含单机 APP 的申报情形，运行时离线是当前项目决策，不把“未备案”简化为一律不可分发；新增公网资源下载需重新核对申报和隐私，不能通过系统代下载绕开。当前构建镜像尚缺可信远端清单校验，详见新报告与已知问题。

2026-08-30 对 Sky Guide/Fifth Star Labs 官方官网、News 和 Support 的只读调研仅用于产品设计参考，不会被打包进应用运行时请求列表，也不会因此新增公网权限、网页跳转或数据外发。调研记录见 `docs/harmonyos/research/SKY-GUIDE-FEATURE-RESEARCH-2026-08-30.md`。其官方页面确认了滤镜、卫星过境、离线运行、AR、时间控制、对象引导、桌面摘要和星声等交互思路；本项目只复用业务抽象和视觉原则，不复制专有图标、照片、插画或代码。

## 统一数据源替换契约

## 联网/离线构建切换（2026-09-30）

当前工程支持一键切换构建边界：

```bash
bash scripts/set-ohos-network-mode.sh status
bash scripts/set-ohos-network-mode.sh online
bash scripts/set-ohos-network-mode.sh offline
```

`online` 会保留 `ohos.permission.INTERNET`，并将 CMake 的 `STELLARIUM_OHOS_OFFLINE` 设为 `OFF`；`offline` 会移除该权限并设为 `ON`。两种模式都会同步生成工程。切换后仍需重新构建 HAP，不能把已有安装包当成新模式。

联网模式目前只代表编译和权限边界已经打开，功能仍按用户主动触发：华为地图、卫星 TLE 更新、在线巡天、在线查询、飞机数据、MPC 导入和远程资源下载分别有自己的入口、隐私说明、超时回退和数据来源审计。备案成功不会自动开启这些功能，也不会自动授予 AGC 的地图、代理提醒、推送、支付或分布式能力。

目前已具备联网模式代码入口的项目项：华为 Map Kit 位置选点、桌面/原生网络插件路径以及应用内网络权限声明；仍需完成 AGC 服务开通、对应 Profile、隐私政策发布、数据来源许可确认和 Pad 断网/超时/回退验收的项目项，不应在生产包里默认启用。

- `STELLARIUM_OHOS_OFFLINE=OFF` 不等于“所有服务自动运行”。用户没有主动打开的地图、查询、巡天和更新功能继续保持关闭。
- 文化研究地图仍使用本地文化资料；在线地图只能作为现代位置选点底图，不能替换文化边界、历史语义或原始资料。
- 星表、高清深空图、天空文化、地景和六类静态目录优先随包；大体积巡天瓦片和 TLE 更新再按服务器、CDN、授权和缓存策略单独接入。

- 所有可替换的目录、巡天资源和在线接口先登记在 `data/ohos/network-sources.json`，由 `scripts/check-ohos-network-sources.mjs` 校验。
- 构建机支持 `local`、`mirror`、`upstream` 三种来源模式；应用运行时不读取来源 URL，也不新增公网网络权限。
- 卫星更新器已经接入该契约：默认 `upstream` 保持原有开发流程；发布构建应使用 `--source-mode local`，镜像构建必须显式指定 `--source-mode mirror --mirror-base-url ...`。
- `local` 模式读取仓库相对路径下的审核缓存，`mirror` 和 `upstream` 只允许出现在开发/构建阶段；清单记录来源模式、解析端点、字节数和 SHA-256，不记录设备标识、位置或用户查询。
- 这套注册表是替换接口和审计边界，不等同于所有桌面插件已经完成本地化；每个新接入项仍需单独核对授权、隐私字段、缓存和失败回退。

## 预研但未接入的本地设备通信

2026-10-01新增研究：[Seestar S50 Pro 接入](research/SEESTAR-S50-PRO-INTEGRATION-RESEARCH-2026-10.md)和[GT5/Watch 5 穿戴路线](research/WEARABLE-GT5-WATCH5-ROADMAP-2026-10.md)。当前只记录方案，不新增运行时请求或开放端口：Seestar 优先用户主动连接的本地 Alpaca，具体 IP/端口通过实机确认；设备发现、指向/曝光、图像传输、穿戴消息和可选云分享分别登记。原始照片本地优先，不默认外传地点、设备序列号或主机 SN/UDID；服务器与收费存储服务未因本次预研启用。

星闪望远镜控制目前只完成接口预研，未加入生产代码、未申请 `ACCESS_NEARLINK`、未扫描或连接设备。星闪属于本地无线设备通信，不等于公网联网，但仍需单独记录权限、设备标识和控制数据边界。设计与分阶段路线见 `docs/harmonyos/TELESCOPE-NEARLINK-RESEARCH-2026-09-02.md`；OnStep开发板验证至单板产品的路线见[产品路线图](research/ONSTEP-NEARLINK-PRODUCT-ROADMAP.md)。不依赖手机/Pad的SN或UDID；控制器自身设备ID与用户终端标识分离。

| 功能 | 当前状态 | 计划触发方式 | 本地数据 | 网络边界 |
| --- | --- | --- | --- | --- |
| 星闪望远镜控制（SSAP） | 预研，未接入 | 用户主动发现、配对、连接并选择设备；不会自动扫描或后台连接 | 星闪设备地址、名称、服务 UUID、设备能力、目标 RA/Dec 和设备回传位置；默认脱敏日志 | 不访问互联网，不通过星闪转发公网请求；接入前需用户授权、错误/超时/断开处理和能力握手 |

## 运行时联网台账

2026-09-30 Map Kit 排障：地图状态向 CLI 返回 SDK 数字错误码和失败阶段，日志只记录 `phase/operation/code`，不输出经纬度、查询词、账号、证书或 SDK 原始错误正文。仍只在用户主动选用华为地图时联网；未增加定位、相机或设备标识权限。

| HarmonyOS Map Kit / 华为地图位置选点 | 默认关闭 | 用户在“位置→地图”主动选择“华为地图” | HarmonyOS `@kit.MapKit` 地图组件；当前不使用应用自有 HTTP 地址 | 地图组件可能处理当前地图视口、用户主动点击的地图坐标以及服务运行所需的系统网络/地图信息；不附加 SN、UDID、账号或文化叠加数据。位置页使用 WGS84 与华为地图站点坐标纠偏，结果回写本地观测位置 | 华为地图是当前国产化系统服务选项，不做未经授权的二次镜像；默认离线 `worldmap.jpg`，超时/失败可回退。需在 AGC 开通地图服务、重新生成对应 Profile，并在隐私政策中保持可见 |

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
| RemoteControl | 默认不启动 | 用户/命令行启动桌面版 HTTP 服务 | 默认仅绑定 `127.0.0.1:8090`；显式改为局域网地址时必须启用密码 | 局域网请求可读取或控制应用状态；服务为明文 HTTP，不是公网数据源 | 不允许直接暴露公网；若需跨设备访问，使用受控 VPN/内网反向代理并限制防火墙，不能把应用端口直接映射到互联网 |
| RemoteSync | 默认空闲 | 用户启动服务端或连接到指定主机 | TCP 局域网连接，端口由设置决定 | 会话状态、时间、位置、视角和同步属性 | 无需公网镜像；必须记录连接目标、认证和局域网暴露范围 |
| Collaboration session / Ability continuation | 默认不主动发送；当前未开启系统 Ability 接续 | 用户点击导出/导入、CLI 导出/导入；第二阶段才启用系统接续 | 剪贴板、系统分享或本地文件；未来经用户配对的分布式链路；当前不新增公网端点 | 版本化接续包中的视线、视场、模拟时间、选中目标和图层状态；位置默认排除 | 不包含 SN、UDID、账号、密码或望远镜凭据；接续包默认 24 小时过期；开启系统接续前需核对 Profile、AGC 接续服务、授权、配对、加密和删除策略 |
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

- 研究报告：`research/STARGAZING-HUB-RESEARCH-2026-09-08.md`。本轮仅操作用户已安装的第三方应用、查阅公开资料与华为文档；不改变星象仪运行时联网行为、签名、权限或服务端配置。第三方应用页面的联网不等于星象仪已经接入这些服务；未对该应用抓包，不能宣称掌握其完整外发字段。
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

## 2026-09-23 DevEco 自动签名与 Clash 路由

- DevEco Studio 日志记录到自动签名页面调用 `com.huawei.devecostudio.region`，随后请求 `connect-api.cloud.huawei.com`；同一时段还出现 `grs.dbankcloud.cn`、`grs.dbankcloud.com`、`grs.dbankcloud.asia`、`grs.platform.dbankcloud.ru` 和 `devecostudio-drcn.deveco.dbankcloud.com` 的 TLS handshake/GRS 超时。该证据说明代理/TUN 路由可能影响自动签名、区域发现和 SDK 检查，不等同于项目证书或 HAP 本地签名损坏。
- 当前 Clash Verge 使用本机 Mihomo 外部控制器 `127.0.0.1:9097`，TUN 已启用，规则末端为代理选择；当前工程用已有本地 Debug 签名构建并安装成功，说明“构建/安装”与“DevEco 在线自动生成签名”是两个独立环节。
- 处理原则：只对日志确认的 DevEco/Huawei 服务添加窄域名 `DIRECT` 规则，放在最终 `MATCH` 之前；不关闭全局代理、不开放 LAN、不把应用运行时资源域名加入开发机规则，也不把 API 密钥、订阅地址或完整 Clash 配置写入仓库。
- 已建立本机可复用 Skill：`~/.codex/skills/clash-control/SKILL.md`，通过外部控制器只读检查版本、配置、规则、连接和代理提供者；写规则前先备份、校验、再重载，并要求用 DevEco 日志确认具体域名。
- 本轮没有修改 Clash 配置或代理节点。下次复现自动签名失败时，先记录失败时间和 DevEco 日志，再决定是否通过 Clash 配置覆盖增加最小直连规则；订阅更新可能覆盖手工修改，不能把临时运行时规则当成长期配置。

## 2026-09-30 联网构建与卫星更新实测

- 当前验证包为联网构建：`STELLARIUM_OHOS_OFFLINE=OFF`、运行时网络开关可用；这只表示网络边界已打开，不代表地图、天气、星表、推送、支付和所有外部资源已经全部接入。
- 卫星更新已补齐空来源配置的显式刷新路径：用户首次点击刷新且来源列表为空时恢复 Stellarium 原版的 47 个 TLE 来源，随后才启动更新；来源会写入应用配置，仍可在界面或 CLI 删除、替换。离线包继续拒绝远程刷新，只支持本地 TLE 导入。
- MateBook Pro 实测 `refreshSatelliteCatalog` 返回 `offline=false`、`sourceCount=47`、`sourcesRestored=true`；随后 `getSatelliteSources` 回读 47 个 HTTPS 来源，未读取位置、SN 或 UDID。远程下载是否部分成功仍以目录更新时间、历元年龄和错误字段为准，不能只看“刷新已开始”。

### 2026-09-30 运行时刷新复核

- MateBook Pro 联网包再次执行 `refreshSatelliteCatalog`，返回 `offline=false`、`ok=true`、`sourceCount=47`；等待异步任务后，`getSatelliteSources` 仍回读 47 个合法 HTTPS 来源，`getCatalogHealth` 为 3134 条、`partial=false`、`verified=true`、`status=current`。
- 过境计算不依赖实时接口：ISS（NORAD 25544）返回本地 TLE 传播的下一次可见过境；中国空间站核心舱（NORAD 48274）存在于同一内置目录。网络失败时继续使用带快照时间、历元年龄、哈希和过期状态的本地目录。
- 本轮没有把地图、天气、在线巡天、飞机 ADS-B、深空图像下载或望远镜局域网连接宣称为“已全部打通”；它们仍由各自的主动入口、隐私说明、来源许可、超时回退和 AGC/Profile 状态单独管理。
- 构建机已在 2026-09-30 更新并校验内置卫星目录：3134 条目录、3134 条有效 TLE，SHA-256 `522577d2ffbe3e37ca30690f8c0a3ccfda06cd8dd30faf2f131edd5b9713e841`；构建发布应优先使用这一随包快照，并显示数据历元和过期提示。
- 本地化/国内化路线：构建机按 `local → mirror → upstream` 选择数据源，统一生成带来源、抓取时间、历元、条数、哈希和 `partial` 标记的清单；应用运行时优先读随包资源，用户主动更新后写入缓存，失败回退到最近一次有效快照。尚未部署经过授权的国内 TLE 镜像端点，不把官网静态站点冒充数据 API。
