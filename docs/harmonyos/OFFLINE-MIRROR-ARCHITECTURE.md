# 本地数据与镜像服务预研

## 目标

HarmonyOS 发布包保持运行时离线。所有可联网的目录、巡天图层和在线查询都提前登记为可替换数据源，发布包只读取本地内置资源；构建机才允许在明确选择后读取本地缓存、镜像服务或上游服务。

六类静态目录（流星雨、系外行星、新星、历史超新星、脉冲星、类星体）已经有插件自带的 QRC JSON 资源。正确策略是“内置资源作为运行时基线，镜像只服务于下一次构建”，而不是应用首次打开后再下载。

统一注册表位于 `data/ohos/network-sources.json`，校验命令为：

```bash
node scripts/check-ohos-network-sources.mjs
```

## 三种构建源

| 模式 | 用途 | 网络行为 | 适合发布构建 |
| --- | --- | --- | --- |
| `local` | 使用 `data/ohos/mirror-cache/` 中的人工审核文件 | 不联网 | 是，最可复现 |
| `mirror` | 从明确指定的镜像根地址读取 | 仅构建机联网 | 是，需校验清单和授权 |
| `upstream` | 直接读取原始来源 | 仅构建机联网 | 仅开发更新，不建议作为发布默认 |

应用运行时不读取这三种远程地址。发布包内只有经过校验的数据和 `catalog-manifest.json`。

## 镜像端设计

镜像服务建议使用 HTTPS、只读、版本化静态文件，统一前缀 `/v1/`：

```text
GET /v1/manifest.json
GET /v1/catalogs/satellites/stations.3le
GET /v1/catalogs/satellites/visual.3le
GET /v1/catalogs/exoplanets.json
GET /v1/surveys/hips/index.json
GET /v1/surveys/dss/{level}/{x}_{y}.jpg
```

每份资源应同时出现在清单中，至少包含：`sourceId`、`version`、`fetchedAt`、`contentType`、`bytes`、`sha256`、`license`、`attribution` 和 `upstreamReference`。客户端构建脚本先下载清单，再下载文件并核对 SHA-256；失败时保留旧资源。

镜像服务不应接收经纬度、搜索词、SN、设备序列号或隐私同意状态。实时飞机、在线天体查询和 MPC 查询若未来接入镜像，必须单独评估：这些请求天然携带位置或对象查询，不能把“镜像”当成隐私问题的自动解决方案。

## 本地目录设计

```text
data/ohos/
├── network-sources.json       # 源 ID、上游、镜像路径、数据边界
├── catalog-manifest.json      # 当前进入 HAP 的版本和校验结果
└── mirror-cache/              # 构建机缓存，不作为运行时网络目录
    ├── satellites/*.3le
    ├── catalogs/*.json
    └── surveys/{hips,dss}/
```

本地缓存文件必须通过临时文件写入、解析校验和 SHA-256 校验后才替换旧文件。缓存不应提交包含个人位置、查询历史或设备信息的响应。

## 接入顺序

1. 卫星 TLE、流星雨、系外行星、新星、超新星、脉冲星和类星体目录；其中后六类优先使用插件现有 QRC 资源，更新时才走构建机镜像。
2. HiPS 目录及巡天瓦片，先做静态目录和瓦片清单，再考虑增量同步。
3. MPC 小行星/彗星导入、SIMBAD 和其他在线查询，先做用户主动触发、隐私提示、脱敏和结果缓存。
4. 实时飞机数据和 NebulaTextures Plate Solver，默认继续关闭；它们分别涉及位置外发和图像上传，不能直接套用目录镜像方案。

## 当前实现状态

统一注册表、解析器和校验契约已建立，构建期卫星更新器已实际支持三种源模式。已验证 `local` 模式在 `--offline` 下只读本地缓存，`mirror` 模式通过明确的镜像根地址读取，`upstream` 模式保持原始开发更新流程。没有为 HarmonyOS 打开网络权限，也没有把桌面端所有插件的网络实现误标记为已经本地化；后续每接入一个数据源，都必须更新注册表、联网台账、资源清单和设备验收记录。

示例：

```bash
node scripts/update-ohos-astronomy-data.mjs --update-satellites --source-mode local --offline
node scripts/update-ohos-astronomy-data.mjs --update-satellites --source-mode mirror --mirror-base-url https://mirror.example.cn
node scripts/update-ohos-astronomy-data.mjs --update-satellites --source-mode upstream
```

`--offline` 与非 `local` 更新模式会直接失败，避免构建脚本在未注意时联网。`--verify-only` 可用于只校验内存中的合并结果，不写回目录和清单。
