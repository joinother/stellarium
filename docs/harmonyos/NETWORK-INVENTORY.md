# HarmonyOS 联网功能台账

> 用途：记录 Stellarium HarmonyOS 版本中所有可能产生网络请求的运行时功能、插件和开发构建步骤。
>
> 维护规则：新增或修改 URL、网络 API、自动更新、文件下载、远程端口或外部网页跳转时，必须先更新本文件，再修改代码。

## 当前结论

- HarmonyOS 构建默认启用 `STELLARIUM_OHOS_OFFLINE=1`。
- 卫星插件在 HarmonyOS 离线构建中已在代码级禁用在线 TLE 更新：不创建网络管理器、不启动更新定时器，旧配置也不能重新开启更新。
- 核心 IP 定位、在线搜索和星表下载在该构建开关下被编译禁用。
- 插件自身的网络实现仍保留，后续若在 HarmonyOS 暴露对应入口，必须增加隐私说明、权限/同意流程、超时和内置数据回退。
- 当前鸿蒙 `module.json5` 未声明 `ohos.permission.INTERNET`，因此已生成 HAP 没有系统授予的公网访问权限；这属于运行时权限边界，不等同于源码中所有网络请求代码都已移除。
- 严格“整个应用绝对不联网”尚未完成代码级封口：HiPS/TOAST、若干插件更新器、MPC 导入和 RemoteSync 的网络实现仍编译保留，必须在提交未备案版本前禁用入口并增加统一离线构建门禁。
- 地图 SDK 当前按项目决定暂缓，不接入花瓣地图或其他地图 SDK。

## 统一数据源替换契约

- 所有可替换的目录、巡天资源和在线接口先登记在 `data/ohos/network-sources.json`，由 `scripts/check-ohos-network-sources.mjs` 校验。
- 构建机支持 `local`、`mirror`、`upstream` 三种来源模式；应用运行时不读取来源 URL，也不新增公网网络权限。
- 卫星更新器已经接入该契约：默认 `upstream` 保持原有开发流程；发布构建应使用 `--source-mode local`，镜像构建必须显式指定 `--source-mode mirror --mirror-base-url ...`。
- `local` 模式读取仓库相对路径下的审核缓存，`mirror` 和 `upstream` 只允许出现在开发/构建阶段；清单记录来源模式、解析端点、字节数和 SHA-256，不记录设备标识、位置或用户查询。
- 这套注册表是替换接口和审计边界，不等同于所有桌面插件已经完成本地化；每个新接入项仍需单独核对授权、隐私字段、缓存和失败回退。

## 运行时联网台账

| 功能/插件 | 默认状态 | 触发方式 | 当前地址或来源 | 传输/返回内容 | 国内镜像或替代评估 |
| --- | --- | --- | --- | --- | --- |
| SIMBAD 在线搜索 | 关闭 | 用户在搜索中主动启用在线搜索 | `https://simbad.u-strasbg.fr/`；备用 `https://simbad.cfa.harvard.edu/`、`https://simbad.cds.unistra.fr/` | 用户输入的天体名称/查询词；返回天体匹配结果 | 不直接抓取镜像。需确认服务协议、限流和数据归属后，才评估国内代理或同类服务 |
| OnlineQueries：系外行星 | 非默认后台任务 | 用户主动执行在线查询 | ASE：`https://ase.exopla.net/index.php/%1` | 天体名称、查询参数；返回系外行星资料 | 不建议未经授权做静态镜像；优先保留可配置服务地址 |
| OnlineQueries：变星 | 非默认后台任务 | 用户主动执行在线查询 | AAVSO VSX：`https://www.aavso.org/vsx/` | 天体名称/坐标；返回变星资料 | 不建议抓取固定镜像；需使用有公开协议的 API 或用户配置地址 |
| OnlineQueries：恒星目录 | 非默认后台任务 | 用户主动执行在线查询 | GCVS：`http://www.sai.msu.su/gcvs/` | 天体名称/查询词；返回恒星资料 | 未验证国内等价公开 API，暂不替换 |
| OnlineQueries：百科 | 非默认后台任务 | 用户主动打开百科链接 | `https://en.wikipedia.org/wiki/%1` | 天体名称进入外部网页 | 不做内容镜像；后续可评估合法中文百科入口，但需保留来源和许可说明 |
| Exoplanets | 自动更新关闭 | 用户主动开启更新或调用更新入口 | `https://www.stellarium.org/json/exoplanets.json` | 系外行星目录 JSON | 适合国内对象存储/CDN 镜像；必须确认上游授权、版本、校验和署名 |
| MeteorShowers | 自动更新关闭 | 用户主动开启更新或刷新目录 | `https://stellarium.org/json/MeteorShowers.json` | 流星雨目录 JSON | 适合国内静态镜像；需保留 IAU/IMO 来源和更新时间 |
| Novae | 自动更新关闭 | 用户主动开启更新 | `https://stellarium.org/json/novae.json` | 新星目录 JSON | 适合国内静态镜像；先核对数据许可 |
| Supernovae | 自动更新关闭 | 用户主动开启更新 | `https://stellarium.org/json/supernovae.json` | 超新星目录 JSON | 适合国内静态镜像；先核对数据许可 |
| Pulsars | 自动更新关闭 | 用户主动开启更新 | `https://stellarium.org/json/pulsars.json` | 脉冲星目录 JSON | 适合国内静态镜像；先核对数据许可 |
| Quasars | 自动更新关闭 | 用户主动开启更新 | `https://stellarium.org/json/quasars.json` | 类星体目录 JSON | 适合国内静态镜像；先核对数据许可 |
| Satellites | HarmonyOS 运行时严格离线 | 应用内无更新入口；仅开发/构建机显式运行 `scripts/update-ohos-astronomy-data.mjs --update-satellites` | CelesTrak GP 3LE：`stations`、`visual`、`active`；SatNOGS TLE API 作补充 | 构建机下载公开 TLE，验证后写入下一次 HAP 内置目录；运行时不请求、不保存远程响应 | 构建机可后续评估合规镜像；当前保留来源、时间、校验和和失败回退，部分源失败时标记 `partial`，不把旧数据伪称最新 |
| Planes | 默认关闭 | 用户开启飞机图层且处于实时模式；默认约每 15 秒请求 | `https://opendata.adsb.fi/api/v2/lat/%1/lon/%2/dist/%3`；备用 `https://api.airplanes.live/v2/point/%1/%2/%3` | 当前观测纬度、经度、半径；返回实时航空器信息 | 不建议简单镜像，数据时效性决定必须访问实时服务；目前没有已验证的国内公开等价 API |
| HiPS 远程星图层（在线巡天） | 默认不显示 | 鸿蒙端“视图/巡天”页打开“HiPS 巡天”，或恢复了已保存的可见远程图层；页面提示“在线巡天需要网络连接” | 默认目录源：`http://alasky.u-strasbg.fr/MocServer/query?*/P/*&get=record`、`https://data.stellarium.org/surveys/hipslist`；每个图层还请求图层根目录下的 `properties`、不同层级的 `Norder.../Dir.../Npix...` 瓦片及可能的缩略图 | 巡天目录、图层元数据、当前视场对应的多级图像瓦片；请求路径中可能包含当前天区坐标/瓦片编号 | 适合自建合规 HiPS 镜像，但工作量大，需同步目录、元数据和多级瓦片；先确认上游数据许可、署名和更新策略；不接地图 SDK |
| DSS/TOAST 数字化巡天（在线巡天） | 默认不显示 | 鸿蒙端“视图/巡天”页打开“DSS/TOAST 巡天”开关后，按当前视场加载图像 | 默认 `http://dss.stellarium.org/survey/{level}/{x}_{y}.jpg` | 当前天区对应层级、横纵坐标的 JPG 图像瓦片 | 可部署完整瓦片镜像，但需确认原始数据许可、瓦片生成方式和存储成本；目前未验证国内等价公开服务 |
| SolarSystemEditor：MPC 小行星/彗星在线导入 | 不自动请求 | 用户在太阳系编辑器打开 MPC 导入窗口，手动选择下载列表、输入 URL 或执行在线 MPES 查询 | MPC 列表和轨道文件：`https://www.minorplanetcenter.net/iau/Ephemerides/...`、`https://www.minorplanetcenter.net/iau/MPCORB/...`、`https://www.minorplanetcenter.net/iau/ECS/MPCAT/...`；部分编号小行星列表使用 `http://dss.stellarium.org/MPC/mpn-{01..90}.txt`、`mpu-{01..62}.txt`；在线 MPES 查询：`https://www.minorplanetcenter.net/cgi-bin/mpeph2.cgi` | 用户选择的对象列表、轨道根数文件或查询参数；返回小行星/彗星轨道元素和星历数据，并可保存到本地 | 这不是巡天图像图层。优先保留手动导入和内置数据；不建议未经授权镜像 MPC 数据，国内部署前需确认 MPC/IAU 数据许可、服务条款、更新频率和查询接口合规性 |
| 自动 IP 定位 | HarmonyOS 核心路径关闭 | 非 HarmonyOS 或配置为自动位置时触发 | `https://freegeoip.stellarium.org/json/` | 设备公网 IP 推断出的粗略位置 | HarmonyOS 使用北京兜底，不应恢复该请求；国内定位替代应优先使用用户手动位置或经过同意的系统定位 |
| RemoteControl | 默认不启动 | 用户/命令行启动本机 HTTP 服务 | 本机监听，默认端口 `8090` | 局域网请求可读取或控制应用状态；不是公网数据源 | 无需公网镜像；必须记录监听地址、密码、CORS 和局域网风险 |
| RemoteSync | 默认空闲 | 用户启动服务端或连接到指定主机 | TCP 局域网连接，端口由设置决定 | 会话状态、时间、位置、视角和同步属性 | 无需公网镜像；必须记录连接目标、认证和局域网暴露范围 |

### 位置和隐私字段

- 目前已登记的外发位置数据包括：Planes 请求中的观测纬度、经度和搜索半径；HiPS/DSS 请求中的天区瓦片坐标；用户主动发送给远程同步服务的观测位置。
- SIMBAD、OnlineQueries 等查询会外发用户输入的天体名称或查询词。
- 本台账未发现将 SN、设备序列号或隐私政策同意状态作为上述天文查询参数发送的设计。新增网络功能不得把设备标识拼入 URL、请求头或分析参数。

## 开发和构建阶段联网

| 阶段 | 来源 | 说明 | 国内镜像/替代 |
| --- | --- | --- | --- |
| CMake 配置/首次构建 | GitHub `CalcMySky`、`QXlsx`、`md4c`、`fast_float`、`indi`、`nlopt`、`SkyCultureMaker` 依赖 | 仅开发机器构建时下载，不属于 App 运行时联网 | 优先使用本地缓存、制品仓库或经过审计的国内代理；构建环境应支持离线复现 |
| Qt/HarmonyOS 工具链 | Qt、HarmonyOS SDK、DevEco/ hvigor 依赖 | 由开发环境和工具链管理 | 使用已审核的官方安装源或企业制品库，不在 App 内处理 |
| 文档/外部链接 | 源码注释、关于页、帮助页中的官网和项目链接 | 打开链接时可能由系统浏览器联网 | 不等同于应用后台联网；如 HarmonyOS 暴露入口，需标记“将打开外部网页” |

## 镜像站实施建议

### 第一阶段：适合做静态镜像

优先考虑 Exoplanets、MeteorShowers、Novae、Supernovae、Pulsars、Quasars 六类 JSON。镜像服务应使用 HTTPS、固定版本或 `ETag`/`Last-Modified`、SHA-256 或签名校验，并在失败时继续使用应用内置目录。镜像前必须确认原始数据的再分发许可、署名和更新频率。

### 第二阶段：需要专门服务

卫星 TLE 可以做国内定时同步服务，但必须保留原始来源和历元信息；HiPS/DSS 需要同步目录、元数据和多级瓦片，不能只替换一个首页 URL。

### 暂不替换

SIMBAD、AAVSO/GCVS/Wikipedia、实时飞机数据目前没有在本项目中验证过授权清晰、接口稳定且功能等价的国内替代。未完成验证前保持用户可选、默认关闭或继续使用内置数据，不宣称存在等价服务。

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
