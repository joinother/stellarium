# 鸿蒙离线星表更新

## 原则

- 应用运行时不更新卫星、恒星或其他星表，不声明 `INTERNET` 权限，也不发送观测位置、查询词或设备标识。
- 只允许开发机或构建机在人工明确执行后联网更新数据；验证成功后再构建 HAP。
- 下载失败、解析失败或校验失败时保留上一次验证成功的内置数据，不能清空目录或把旧数据显示为最新。多个数据源中部分失败时，更新器会记录失败源并只合并成功源；清单中的 `partial` 和 `sourceErrors` 必须随包保留，不能把部分更新描述为完整同步。

## 可直接随包分发的目录

以下目录插件已经自带 JSON 和 QRC 资源，流星雨不需要联网才能计算、显示或搜索：

| 功能 | 内置资源 | 当前规模 | 运行时更新 |
| --- | --- | ---: | --- |
| 流星雨 | `plugins/MeteorShowers/resources/MeteorShowers.json` | 44 个目录项 | HarmonyOS 禁止 |
| 系外行星 | `plugins/Exoplanets/resources/exoplanets.json` | 约 5,582 个条目 | HarmonyOS 禁止 |
| 新星 | `plugins/Novae/resources/novae.json` | 约 66 个条目 | HarmonyOS 禁止 |
| 历史超新星 | `plugins/Supernovae/resources/supernovae.json` | 约 49 个条目 | HarmonyOS 禁止 |
| 脉冲星 | `plugins/Pulsars/resources/pulsars.json` | 约 3,604 个条目 | HarmonyOS 禁止 |
| 类星体 | `plugins/Quasars/resources/quasars.json` | 约 6,514 个条目 | HarmonyOS 禁止 |

资源是否真正进入插件 QRC 由 `node scripts/check-ohos-offline-catalogs.mjs` 检查；不要只看源目录存在文件就认定 HAP 已包含它。

## 卫星数据

建议每 7 至 14 天、且在发布构建前执行（仅在构建机联网更新阶段）：

```bash
node scripts/update-ohos-astronomy-data.mjs --check --max-age-days 14
node scripts/update-ohos-astronomy-data.mjs --update-satellites
node scripts/update-ohos-astronomy-data.mjs --update-catalogs
scripts/sync-ohos-resources.sh
node scripts/check-ohos-offline-catalogs.mjs
```

更新器从 CelesTrak 的 `stations`、`visual`、`active` GP 3LE 源下载数据，并用 SatNOGS TLE 作为补充源；只替换现有内置卫星的两行 TLE 和更新时间，保留分组、通信和显示元数据。它将来源、抓取时间、SHA-256、字节数、条目数、验证状态和失败源写入 `data/ohos/catalog-manifest.json`，随后随 HAP 一起分发。若某个源返回 403 或暂时不可用，清单会标记部分更新；本次构建记录为 `stations` 21 条、`visual` 157 条、SatNOGS 1671 条读取成功，`active` 返回 HTTP 403。内置 3134 条中实际刷新 796 条，因此必须保留 `partial: true`。

六类静态 JSON 目录也支持构建机通过 `--update-catalogs` 按注册表更新：系外行星、流星雨、新星、历史超新星、脉冲星和类星体会先全部解析、检查目录键和条数，全部成功后才写入对应 `resources/*.json` 和清单，并记录版本和 SHA-256；其中任何一项失败都不会替换这一批已有目录。`local` 模式要求先准备审核缓存，不会偷偷使用当前文件冒充已审核快照。该选项不会被应用调用；流星雨仍然完全可以使用当前 QRC 内置数据离线运行。

卫星 JSON 带有 `offlineSnapshot` 标识。覆盖安装时，若 HAP 内快照与用户目录的旧快照不同，离线构建会替换旧 `modules/Satellites/satellites.json` 并同步有效期基准；否则新 HAP 虽包含新 TLE，插件仍会继续读覆盖安装保留的旧目录。

应用会在卫星面板和设置页读取这份内置清单，不联网地显示数据健康状态：卫星目录抓取时间超过 14 天时标记“已过期”；部分更新标记“建议完整复核”；当前模拟日期超出单颗卫星 TLE 历元范围则单独提示计算有效性。基础 `hip_gaia3` 星表不按模拟日期失效，但在 180 天未复核、清单校验失败或内置文件缺失时标记“已过期”。

## 恒星数据

基础 `hip_gaia3` 星表仅做本地完整性检查：

```bash
node scripts/update-ohos-astronomy-data.mjs --update-stars
```

更深的官方星表容量从数百 MiB 到 GiB，不在例行更新中下载，也不能在未评估 HAP 大小、启动解包时间、数据来源和许可证前自动打包。只有显式传入 `--allow-large-star-download` 后才允许下一阶段实现下载；该开关目前记录构建许可，不下载大文件。

当前 HAP 已内置 `stars_0` 至 `stars_4`，5 个分卷全部通过字节数和 MD5 校验，其中 `stars_4_1v0_6.cat` 为 55,759,776 字节，覆盖到约 12 等星。

## 发布验收

1. 执行 `--check --offline`，确认目录与清单可本地验证。
2. 执行 `node scripts/check-ohos-offline-catalogs.mjs`，确认六类目录的 JSON 和 QRC 均存在。
3. 执行 `scripts/sync-ohos-resources.sh`，确认清单进入 rawfile。
4. 构建 HAP 后解包检查 `satellites.json` 和 `data/ohos/catalog-manifest.json`。
5. 设备端用 `getSatellites`、`getMeteorShowers` 和各目录查询核对本地数据，不产生网络请求。
