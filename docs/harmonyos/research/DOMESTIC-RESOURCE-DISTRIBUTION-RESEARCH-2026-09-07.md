# 国产化、应用分发与资源下载复核

核对日期：2026-09-07。性质：官方资料与当前源码复核，不是已上线能力清单。本轮不部署服务器、不下载大资源、不新增权限、不切换签名、不构建或上传。

## 1. 决策摘要

- 当前版本继续保持不访问公网的运行时基线：基础星图、名称搜索、默认文化、常用图像和行星纹理应随包可用。市场下载安装应用与应用自身下载资源分开看待。
- 后续联网版本的普通数据包优先评估「国内对象存储/CDN＋HarmonyOS 系统上传下载服务」，避免把所有资源拆成应用模块，也避免渲染器直接访问远程 URL。
- 大型独立功能（例如未来独立三维浏览引擎）可评估 AppGallery Kit 按需模块；它是受应用市场管理的应用模块分发，不是任意第三方插件市场。
- 游戏资源加速服务确实支持模型、纹理后台下载，但其业务面向游戏，本应用接入资格尚未确认，不作为当前落地前提。
- 「国产化」分开推进：国产系统适配、国内基础设施、可复现依赖供应链、国内科学数据补充；国内托管不改变数据作者、开源许可证或科学来源，也不代表所有底层代码均为国产。

## 2. 仓库实况与复核发现

| 项目 | 已核验事实 | 不应声称已完成的部分 |
| --- | --- | --- |
| 数据源注册表 | `data/ohos/network-sources.json` 有 22 项；运行时 local-only，构建有 local/mirror/upstream | 注册镜像路径不等于镜像已经部署；注册表和脚本的构建默认值仍为 upstream |
| 构建更新器 | `scripts/ohos-data-sources.mjs` 解析来源；`update-ohos-astronomy-data.mjs` 支持本地缓存、镜像根地址与上游 | 尚未先获取并认证远端发布清单；下载后自行计算 SHA-256 只是记录，不是与可信预期值比较 |
| 写入方式 | 六类目录先解析再逐文件临时写入/rename，最后写清单 | 单文件原子替换不等于整批资源事务；中途进程终止仍可能出现资源/清单不一致 |
| URL 边界 | 镜像地址通过 URL 拼接，下载使用 fetch 默认行为 | 尚未强制 HTTPS、来源/重定向白名单、响应最大字节数、版本防回退；不适合直接当生产下载器 |
| 运行时安装 | `StellariumResourceBootstrap.ets` 从 rawfile 准备沙箱资源、按优先级提取深空图像，已有准备失败和预热状态 | 这是本地解包/复制，不是网络下载；没有接入 request.agent、moduleInstallManager 或 assetDownloadManager |
| 发布分发 | 现有 `.app` 发布流程见 `RELEASE-PACKAGING.md` | 签名引用为 release 不能代替 Release 构建，也不能证明最终包通过上架检查 |
| 权限 | 已检查源码 `harmonyos/module.json5` 未声明 INTERNET | 不能据此证明所有 Native 路径没有网络行为；生产包仍需解包与网络行为验收 |

### 2.1 本地资源规模

只读统计当前生成工程 `entry/src/main/resources/rawfile/stellarium/` 的普通文件逻辑大小，不是压缩后 APP/HAP 大小，也不包含全部 QRC、原生库或安装后缓存。

| 目录 | 文件数 | MiB |
| --- | ---: | ---: |
| skycultures | 1290 | 154.41 |
| nebulae | 679 | 127.21 |
| stars | 16 | 88.90 |
| translations | 385 | 80.78 |
| textures | 164 | 53.98 |
| data | 287 | 28.68 |
| scenery3d | 135 | 21.69 |
| landscapes | 703 | 16.87 |
| scripts | 52 | 4.79 |

合计 3711 文件、605,335,812 字节，约 577.29 MiB。因此先做逐资源许可/重复文件/实际依赖审计，再决定分包。不能为缩包擅自删除语言包、文化资料或降低画质。没有获得当前 AGC 账号对应的正式包大小限制，不能拿游戏资源总配额或模块调试文件上限代替应用上传上限。

### 2.2 必须先补的清单一致性问题

当前 `satellites.json` 实际 SHA-256 为 `cab4048a008dc2c77b763d773247bf66e299f03635e04bc43daa52116e2a6c14`；`catalog-manifest.json` 中对应值仍是 `f82d11a95714c7c8d21b72cd6d3a25ba49f175309fc4ce66bab27f4ef7a69670`，二者不一致。

历史记录说明 9 月 6 日单独更新过 STARLINK-36933，但本轮未重建全部变更来源，不能把这一次单条更新冒称整份目录刷新。清单仍记录 8 月 27 日批量抓取、796/3134 条刷新、partial=true；本次约距该时间 10.9 天。

现有 `--check` 会打印哈希和年龄，但没有比较清单哈希；`check-ohos-offline-catalogs.mjs` 检查资源与 QRC 并输出哈希，也没有比较清单。因此三项检查退出成功并不代表发布资源链路完整通过。

后续修复应保留批量抓取时间、部分更新状态及单条补丁来源，增加「最终产物哈希＋补丁记录」和不一致时失败的门禁；不能只改 fetchedAt 或 verified 把旧数据标新。本轮只登记，未改动目录或清单。

## 3. 华为官方能力选型

下列能力通过华为开发文档 MCP 先搜索、再读取完整文档。当前项目 API 24、兼容基线 API 22，不能直接套用 API 26 的新增接口。

| 方式 | 官方能力与约束 | 对本应用的建议 |
| --- | --- | --- |
| APP 整包分发 | `.app` 是上架单元，含 HAP/HSP；发布要求 Release。安装、更新由应用市场处理。[发布应用](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-publish-app) | 当前正式路线；应用业务不因此获得运行时下载能力 |
| AppGallery Kit 按需模块 | moduleInstallManager 起于 4.1.0(11)，Stage；正式分发需上架，先拆基础/增强模块，支持手机、平板、PC/2in1。可本地调试。[开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/store-moduleinstall_arkts) | 候选用于独立功能；不是脱离宿主发布、任意加载用户原生插件的许可 |
| 系统文件下载 | request.agent.create 自 API 10，需 INTERNET；支持进度、暂停续传、网络条件与前后台任务。[接口文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-request) | 未来普通资源包首选；当前离线版不启用 |
| 游戏资源加速 | 从 5.1.0(18) 支持手机/平板，PC/2in1 从 API 26；配合 AGC 资源任务，下载接口需 INTERNET。[业务概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/graphics-accelerate-assetdownload-introduction) | 未确认非游戏接入资格；不要当作全设备通用能力 |
| Cloud Foundation Kit 云存储 | 需网络权限；PC/2in1 从 6.1.0(23)，最低 API 22 时不能不加判断地依赖。[配置说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/cloudfoundation-storage-config) | 可选托管方案；公开静态资源暂优先标准 HTTPS 传输，减少客户端厂商 SDK 耦合 |
| ohpm-repo | 官方支持私有仓及选择性导出/下载/导入中心仓依赖。[批量导入说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-ohpm-repo-export-metadata) | 只服务构建供应链，不作为用户下载天文图片的资源服务器 |

补充核对：本机 SDK 有 moduleInstallManager 声明与 fetchModules，但没有 pauseTask；官方把 pauseTask 标为 26.0.0。不要让统一 UI 显示当前后端做不到的暂停功能，应通过 capabilities 告知用户「可取消」或「可暂停」。应用内 HSP 随宿主 APP 发布、同包名同进程，不能用 HSP 拆分来声称引擎获得了进程隔离。[HSP](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/in-app-hsp)

### 3.1 普通下载器需要正确使用的细节

- 资源写入应用沙箱的暂存区。系统下载完成后，仍须由应用认证清单、校验、解包、索引并激活，不直接覆盖正在渲染的文件。
- 使用 request.agent 的 BACKGROUND 模式处理用户主动允许的后台下载，不依靠后台 JS 定时器续命；这也不保证任务无限运行或进程回调永不丢失。保存 taskId 和任务映射，进程重启后对账、重新订阅并验证磁盘内容。
- 下载至「用户文件」与下载到「应用沙箱」不同：API 20 起前者要求 FOREGROUND 且 overwrite=true。不要把公开 Downloads 目录当后台资源缓存目录。
- 明确配置网络、计费网络和漫游策略，不照搬 ANY、roaming=true 等默认值；移动网络需用户确认。离线开关和撤回授权应阻止新任务并取消相应未完成任务。
- API 18 支持最高限速；API 20 支持最低速度与超时；API 22 支持任务通知通过 WantAgent 返回应用指定页面。本项目可评估这些能力，但本轮未接入。[文件上传下载指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/app-file-upload-download)
- 禁止明文 HTTP、默认任意重定向和无限重试。支持断点续传须结合不可变 URL、ETag/Range 行为测试；过期临时 URL 的续签不得把别的版本接在旧文件尾部。
- 已安装资源放持久目录，临时下载放可回收缓存。清缓存只清未固定数据；校验/解包放后台任务，切换索引短时完成，不在 UI 帧中整包扫描。

## 4. 国产化与国内服务架构

### 4.1 国内托管不等于重新实现科学引擎

保留 Stellarium 核心与 Qt/OpenGL ES 等已有依赖，通过 ArkUI/系统能力完成设备适配。建立源代码版本、构建工具、依赖、许可证与资源的物料清单；CMake/npm/ohpm/Qt 各自锁定与归档，不能把 ohpm 私仓说成能镜像所有工具链。优先企业内部审核缓存，不使用来源不明的 GitHub 代理，不改用户全局源与签名。

华为官方 ohpm-repo 支持选择性批量缓存，不需要把中心仓所有包拉下来。具体版本的 Node 配套条件按[快速开始](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-ohpm-repo-quickstart)核验，不在本轮升级现有开发环境。

### 4.2 资源端推荐结构（拟议，未部署）

```text
授权上游 / 国内科学数据
  → 构建机同步与人工审核 → 隔离暂存 → 校验 / 来源 / 许可 / 版本
  → 独立资源发布签名 → 国内对象存储的不可变版本 → CDN
  → 客户端统一资源服务 → 持久资源仓 → Stellarium / 详情 / 三维后端
```

国内对象存储和 CDN 可以承载图片、星表及数据包。华为云 OBS＋CDN 是已核对的候选：支持私有桶回源授权，使用中国大陆加速范围时加速域名需备案；费用要分别算存储、请求、回源与 CDN 流量。[OBS 官方指南](https://support.huaweicloud.com/usermanual-obs/obs_03_0600.html)

设计要求：

- 用自有资源域名和标准 HTTPS，不把厂商桶名写进业务/渲染代码。当前 `/v1/` 路径只是协议版本，还应增加数据版本或内容哈希，禁止原地覆盖已发布资源。
- 小型发布索引短缓存；已发布内容以版本/哈希寻址、长期缓存。先上传内容并验证，再发布签名索引；不能先公布下载入口再补文件。
- 发布凭据留在构建机/服务端；客户端只内置公钥。资源发布签名与 APP 的 Release 签名分开，包含 keyId、轮换和撤销策略，不挪用用户现有签名配置。
- CDN 只获得必要读权限；客户端不持有云账号 AK/SK，不开放上传和桶目录枚举。私有桶回源授权不等于下载者鉴权，有付费/受限数据时需另行设计授权。
- 禁止泛 URL 代理和随意回源；审核清单决定可同步的公开来源、版本、许可和路径。即使是国内服务器也不能任意镜像整站。
- 资源请求仍暴露 IP、时间、包 ID 和 HTTP 元数据；巡天瓦片 ID 还能推断浏览天区。不能把「未上传地理经纬度」说成「没有任何数据外发」。最小化访问日志及留存，不附带 SN、查询历史、观测位置。
- 初期资源包失败保留上个有效版本，不暗中切境外上游。容量预算包括旧版本＋下载暂存＋解包后文件＋缓存，不只算网络包大小。

### 4.3 国内天文数据的可替代范围

- 国家天文科学数据中心（NADC/China-VO）有数据归档、共享和分析服务，可作为合作与数据源评估入口，未证明所有所需巡天/查询均有可商用等价镜像。[NADC](https://nadc.china-vo.org/?locale=zh-CN)
- LAMOST 是有价值的恒星光谱/参数补充，但不是完整星图位置目录、TLE 或 SIMBAD 的直接替代。DR13 本轮查到的公告面向国内天文学家与国际合作者，不能据此向全部应用用户重分发。[DR13 公告](https://www.lamost.org/public/node/507?locale=zh)
- 国内发布、全球公开和商业再分发是不同条件；逐数据集确认访问范围、衍生图像、批量下载、再分发、署名与缓存许可，不因“公开可下载”直接认定可打包。[LAMOST 数据政策](https://dr.lamost.org/policies/data_policy.html)
- China-VO 有 HiPS 可视化历史研究资料，但历史论文不能证明当前服务可用、覆盖完整或具备稳定服务承诺。需联系数据提供方并做具体目录/瓦片/许可验收，当前不替换 HiPS URL。
- 本轮未证实国内有与 CelesTrak、SIMBAD、实时 ADS-B 完全等价且授权适用的服务；保留内置快照和独立适配器，不以过期静态文件冒充实时数据。

## 5. 按资源类型分发，不混用机制

| 内容 | 当前离线路线 | 联网版候选及限制 |
| --- | --- | --- |
| 基础星表、默认 UI、常用图片、行星纹理 | 必须可本地用；现有资源不擅自删减 | 内置兜底不移走；更新非首屏前置条件 |
| 高精度星表分卷、更多文化/地景/三维资产 | 当前继续随包或现有受支持的本地导入 | 版本化数据包；先统计、授权、索引，不能为缩包破坏全语言体验 |
| 流星雨与六类 JSON 目录 | QRC 内置，可离线计算 | 小文件独立更新，解析＋一致性校验；不需要瓦片 |
| 卫星 TLE | 内置快照＋本地导入，保留逐星历元 | 小文件更新，不必每两周等 APP 发版；频率依据用途/上游限流，14 天不是所有卫星的精度保证 |
| 星系/星云单幅图片 | 本地预热、解码、GPU 上传状态区分 | 极大单图才评估图像金字塔；下载成功不等于纹理就绪 |
| HiPS/DSS 巡天 | 先做有限天区、明确层级的授权离线包 | 适合多级瓦片；保持投影/坐标/层级、properties、目录、缩略图及署名，缺块显示可辨识的低级兜底 |
| 脚本 | 沿用现有本地导入限制 | 审核脚本能力和资源依赖；不能把脚本当普通 JSON 完成下载就自动执行 |
| 原生插件/新增引擎 | 随 APP 构建、签名、审核 | 宿主兼容的按需模块候选；不通过资源 CDN 热更 .so/.abc 或任意可执行文件 |
| 真实飞机、在线解算、在线查询 | 当前不开放公网路径 | 各自隐私/权限/授权评估；位置、图像、查询外发不属于单纯静态资源分发 |

不承诺“所有地方的全部最高精度资源都提前解码进内存”。合理目标是首屏和当前视场优先、邻近视场小范围预取、取消过期请求、受控磁盘/内存/GPU 缓存；后台资源任务不能抢占星图绘制。三维 CPU 绘制慢不是 CDN 能解决的问题。

## 6. 统一资源服务与 CLI 契约（设计，未实现）

渲染器只请求逻辑 assetId；统一服务决定 bundled、imported、downloaded 或 module 来源。禁止各插件私建下载器。底层存储/下载来源可以替换，不改天文计算和 UI 业务。

资源清单拟包含：schemaVersion、packId、version、contentHash、compressedBytes、unpackedBytes、兼容 app/engine/schema 范围、依赖包、文件表及每文件 SHA-256、license、attribution、sourceRevision、publishedAt、可选数据历元/有效期、keyId 和签名。抓取时间、数据历元、发布和审核时间分开。

建议三组独立状态，而不是一个模糊的“加载中”：

1. 安装：notInstalled / queued / waitingNetwork / downloading / paused / verifying / unpacking / indexing / installed / failed / cancelled。
2. 媒体显示：preparing / decoding / uploading / ready / decodeFailed / unsupported / noMatchingAsset。
3. 数据健康：current / stale / partial / incompatible / integrityFailed；已安装不代表数据最新，已下载不代表可显示。

统一 UI 显示总大小、所需空间、进度、版本、来源、原因和操作；不知道总大小时用不定进度，不虚构百分比。暂停/续传按钮由后端能力决定。下载、解码失败保持已显示的有效内容，提供重试；目录确实没有对应资源时直说，不无限转圈。

拟议 CLI：resource.list、resource.inspect、resource.install、resource.pause、resource.resume、resource.cancel、resource.verify、resource.remove、resource.pin、resource.events。离线版本 install 只允许受支持的本地包；远程路径返回 OFFLINE_POLICY，不能悄悄联网。上述命令尚未登记，不能当现成命令运行。

每条异步操作返回 requestId/taskId＋accepted，最终事件含 phase、bytes、totalBytes（未知可为空）、errorCode、retryable 和版本；events 携带单调递增序号并可补拉，状态快照可在进程重启后恢复。ArkUI、脚本、AI 共用同一接口。已有 getDeepSkyImageStatus/getCatalogHealth 与 ArkUI 预热状态应接入，而不是删除重做。

验证资源包时拒绝目录穿越、绝对路径、符号链接、压缩炸弹、超额文件、未知可执行类型和不兼容版本；独立暂存后用版本目录/活动指针完成整批切换，保留旧版。用户数据与官方资源分区，不以覆盖安装清空用户导入内容。

## 7. 上架与备案边界修订

华为 APP 核准指引明确列有「您的 APP 为单机 APP」选项，并在“应用无需核准”下说明未通过公共互联网提供互联网信息服务的情形。应按真实业务及审核要求申报，不能简单说“没有 INTERNET 权限就一定免备案”，也不能反向说“所有未备案软件都不能分发”。这是依据官方文档的技术合规判断边界，不是审批承诺。[官方 APP 核准指引](https://developer.huawei.com/consumer/cn/doc/app/50130)

将来加资源下载，即使走系统代理、国内 CDN 或华为托管，仍须重新核对实际联网、隐私说明与申报。按需模块的单机申报边界应先向 AGC 确认，不能视为绕过项目离线限制的手段。APP 备案、CDN/域名备案、内容再分发授权、软件开源义务分别处理，不可互相替代。

当前上架仍按 `RELEASE-PACKAGING.md` 手动制作 Release APP、检测与测试后提交。先小范围测试资源缺失/首次启动/覆盖安装，再按市场实际支持的发布配置推进；不承诺此次未操作的 AGC 账号已具备某项资格或配额。

## 8. 分期计划和验收

| 优先级 | 工作 | 可验证的完成条件 |
| --- | --- | --- |
| P0 发布前 | 清单/文件哈希门禁；记录单条 TLE 补丁来源 | 资源或清单任一改变即失败；partial、历史日期不被清洗；从最终发布包再次核验 |
| P1 离线可做 | 整批资源事务、恢复、授权物料表、受控预热、统一状态/CLI | 断电/空间不足/解码失败不破坏旧资源；首次离线即可用；不新增公网请求 |
| P1 构建侧 | 锁版本的审核缓存与可信发布清单；国内制品源预演 | 空缓存、错误摘要、跨源重定向、过期/回退版本明确失败；可离线重现 |
| P2 联网获准后 | 国内对象存储/CDN＋request.agent 下载服务 | 网络中断、后台/重启、取消、流量拒绝、撤回同意、Range/版本变化全部有正确状态和旧版回退 |
| P2 按需模块预演 | 仅选一个真正独立增强模块 | 基础包缺模块仍可用；模块安装/失败/取消/不兼容可恢复；最低 API、手机/Pad/PC 分别验证 |
| P3 | 小范围 HiPS 多波段包、国内科学数据合作 | 许可明确、覆盖可查询、坐标/层级匹配；缺块不会冒充完整巡天 |

本轮实际验证：22 项来源注册表通过；10 个 bundled 注册项的 QRC/JSON 检查通过（其中四项 TLE 源指向同一卫星目录，不是十份独立目录）；3134 条 TLE 结构校验通过；额外清单哈希比较失败，已单独登记。未验证最终 Release APP、真实 CDN 下载、设备后台恢复或云服务资格。

## 9. 检索记录

华为 MCP 搜索词：资源分发 Asset Delivery 按需下载、request.agent 后台断点续传、APP/HAP 资源大小、单机应用备案、OBS/CDN 国内域名、ohpm-repo 私仓。以搜索返回的 document/cn/... 标识取得全文；重要结论与 API 条件链接已放在相应段落。

另用官方网页补查华为云 OBS/CDN、NADC 和 LAMOST。工信部解读页搜索可检索但全文打开失败，本报告备案操作依据本轮成功取得全文的华为 APP 核准指引；不把搜索摘要当新的法律结论。未获取准确账号配额、实时计费报价或数据商业授权，均作为待确认项。
