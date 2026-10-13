# 鸿蒙端离线功能矩阵

更新时间：2026-08-30

## 结论

当前鸿蒙发布包的基线是“运行时不访问公网”。能随包分发的静态天文数据直接进入 HAP；需要时效性、用户查询或实时观测的数据不伪装成本地数据，而是明确标为构建期更新、用户导入或暂不支持。数据源注册表同时登记了 HiPS 瓦片、在线查询、图像上传和 IP 定位等网络边界，避免只登记首页 URL。

本轮复核还区分了三种容易混淆的“联网”：公网数据请求、打开系统浏览器的外部网页、以及 RemoteControl/RemoteSync/TelescopeControl/Vts 的本机或局域网连接。后者不等于公网镜像，但同样不能在未备案版本中无提示地默认监听或连接。

## 可直接随包分发

| 功能 | 本地资源 | 运行时是否需要网络 | 结论 |
| --- | --- | --- | --- |
| 基础恒星 | `stars/hip_gaia3` 的 `stars_0` 至 `stars_4` | 否 | 已内置，覆盖约 12 等；更深星表需评估 HAP 体积和授权 |
| 太阳系与行星纹理 | `data/`、`textures/` | 否 | 直接打包；贴图缺失应视为资源清单或兼容性错误 |
| 深空目录与图片 | `nebulae/`、内置目录索引 | 否 | 可以随包；不把外部图片 URL 当作本地资源 |
| 天空文化与地景 | `skycultures/`、`landscapes/`、`scenery3d/` | 否 | 可以随包，随包保留说明、来源和许可证 |
| 脚本 | `scripts/*.ssc`、`scripts/*.inc` | 否 | 脚本命令在本地执行；当前脚本没有 HTTP API。注释中的网址不代表运行时请求 |
| 流星雨 | `plugins/MeteorShowers/resources/MeteorShowers.json` | 否 | 已确认可本地计算、搜索和显示；当前约 44 项，运行时禁止更新 |
| 系外行星/新星/超新星/脉冲星/类星体 | 各插件 `resources/*.json` 和 QRC | 否 | 已内置；可由构建机用镜像更新后重新打包 |
| 卫星 | `plugins/Satellites/resources/satellites.json` | 否 | 使用随包 TLE 快照；数据会过期，不能声称永久实时 |
| 目镜、角度测量、极轴镜、日历、时间计算 | C++/Qt 本地逻辑和资源 | 否 | 可离线运行 |
| 脚本、脚本字幕与脚本引用的本地天体 | `scripts/*.ssc`、`scripts/*.inc`、内置星表和星历 | 否 | 当前脚本执行路径未发现运行时 HTTP API；脚本注释中的网址只是来源说明 |
| 地景、天空文化、Scenery3d 场景 | `landscapes/`、`skycultures/`、`scenery3d/` | 否 | 可随包分发；必须同时保留说明、作者、来源和许可证 |
| NebulaTextures 的本地纹理 | 用户导入的本地图像、纹理配置和内置资源 | 否 | 可离线显示；Plate Solver 是另一条需要单独封口的网络路径 |

## 不能仅靠“打包资源”替代

| 功能 | 运行时行为 | 适合的后续方案 |
| --- | --- | --- |
| 在线巡天 HiPS/DSS/TOAST | 按视场和层级请求目录、元数据或瓦片 | 选择有限天区做授权清单化离线包；备案后再做版本化瓦片镜像 |
| OnlineQueries/SIMBAD/AAVSO/GCVS/百科 | 用户查询或打开外部网页 | 未备案包隐藏或明确禁用；备案后采用有授权的接口和隐私提示 |
| MPC 小行星/彗星导入 | 下载轨道文件或发起在线星历查询 | 保留本地文件导入；镜像只做构建输入，不在客户端透明代理 |
| Planes | 按观测位置请求实时航空器数据 | 默认关闭；若接入需单独隐私评估，静态镜像不适合实时数据 |
| NebulaTextures Plate Solver | 上传用户图像并轮询解算结果 | 未备案包关闭；备案后单独做用户同意、上传提示和失败回退 |
| IP 自动定位 | 将设备公网 IP 发给定位服务 | 鸿蒙端使用北京兜底或用户手动位置，不恢复 IP 定位 |
| 星表下载页 | 下载更深的 `hip_gaia3` 分卷 | 不建议运行时打包下载；开发机预置并校验后随下一版 HAP 分发，受 HAP 体积、启动耗时和授权限制 |
| 卫星导入页 | 用户自定义 TLE URL 或源列表 | 可改为用户导入本地文件；实时源不能用静态镜像冒充最新数据 |
| 帮助页检查更新 | 查询 GitHub Releases，或打开发行页 | 未备案包隐藏/禁用检查更新；帮助文本和来源链接可随包，但外部网页必须由用户主动打开 |
| TelescopeControl | 通过串口或 TCP 控制用户设备 | 这是设备连接，不是天文数据镜像；单独管理权限、目标地址和断开状态 |
| RemoteControl/RemoteSync | 本机 HTTP 或局域网同步 | 保留为显式开发/高级功能；限制监听地址、认证和局域网暴露范围 |
| Vts | 连接本机 VTS 服务端口 | 仅本机连接；未备案包默认关闭，不与公网镜像混用 |

## 构建机更新边界

构建机可以在人工明确执行时使用 `local`、`mirror` 或 `upstream`。应用运行时不读取这些 URL。

```bash
node scripts/update-ohos-astronomy-data.mjs --update-catalogs --source-mode local --offline
node scripts/update-ohos-astronomy-data.mjs --update-catalogs --source-mode mirror --mirror-base-url https://mirror.example.cn
node scripts/update-ohos-astronomy-data.mjs --update-satellites --source-mode local --offline
```

`--update-catalogs` 现在会先完成六类静态 JSON 的解析、目录结构检查、版本/条数/SHA-256 记录，再统一写入资源和清单；下载或解析失败时不会替换任何一类已有目录。`local` 模式需要预先准备 `data/ohos/mirror-cache/`，没有审核缓存时应让命令失败，而不是回退到未经审核的当前文件。更新后必须执行资源同步和 HAP 解包审计。

流星雨的“本地打包”与“定期更新”是两件事：前者已经完成；后者只能在构建机拿到最新数据并重新打包，不能在未备案应用内后台下载。

## 镜像方案修订

1. 未备案阶段：只发布本地资源，关闭所有公网运行时入口，不配置客户端镜像地址；本机/局域网控制功能也必须默认关闭并显式提示。
2. 备案后静态目录：优先做版本化 HTTPS 文件、清单、SHA-256/签名校验、原子替换和旧版本回退；镜像服务不接收 SN、设备标识、位置或查询词。
3. 卫星 TLE：镜像仅作为构建输入；保留来源、抓取时间、历元、条数和 `partial` 状态，并在应用中提示过期。
4. HiPS/DSS：不能只替换一个首页 URL，必须同时镜像目录、`properties`、多级瓦片、缩略图和许可署名；建议先做小范围离线包。
5. 实时飞机、在线查询、Plate Solver：不套用静态镜像模板，它们分别涉及实时性、用户查询外发和图像上传。

## 复核后的优先级

1. **立即可做：** 继续扩大本地静态资源包，包括流星雨目录、六类目录、卫星 TLE 快照、现有星表分卷、天空文化、地景、Scenery3d 和已审核的深空图像；这些不需要客户端镜像就能工作。
2. **备案后优先：** 为静态 JSON 和选定 HiPS/DSS 天区建立版本化镜像。镜像只给构建机或显式更新器使用，发布包仍以内置资源为回退，不把实时查询接口伪装成静态文件。
3. **单独立项：** HiPS/DSS 全量瓦片、MPC 小行星/彗星在线查询、SIMBAD/OnlineQueries、Planes、Plate Solver。它们分别受数据量、查询外发、位置外发或图像上传约束，不能通过“加一个缓存目录”直接完成本地化。
4. **不纳入公网镜像：** RemoteControl、RemoteSync、TelescopeControl、Vts。它们是控制或设备连接能力，应采用本机/局域网权限、认证、超时和断开状态管理。

## 审计命令

```bash
node scripts/check-ohos-offline-catalogs.mjs
node scripts/check-ohos-network-sources.mjs
node scripts/update-ohos-astronomy-data.mjs --check --offline --source-mode local
git diff --check
```

源码中的 URL、网络类和外部链接仍需持续审计；文档或“关于”页中的网址只在用户主动打开时才会交给系统浏览器，不等同于应用后台联网。
