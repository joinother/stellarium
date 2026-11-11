# 星象仪在线数据镜像（TLE + 目录）

把国外的星历/目录源（CelesTrak、SatNOGS、Stellarium 各插件目录）在**自己的 ECS** 上抓一份，
再以静态站点对外提供。App 端用 `--source-mode mirror --mirror-base-url https://<域名>` 构建，
就只依赖自家域名，不再直连国外。

## 目录内容

| 文件 | 作用 |
|---|---|
| `sources.json` | 要镜像的源清单（由仓库 `data/ohos/network-sources.json` 导出，含 `mirrorPath`） |
| `fetch-mirror.mjs` | 抓取脚本：原子落盘 + 格式校验 + 失败保留上一版 + 写 `manifest.json` |
| `nginx-tle-mirror.conf` | 只读静态站点（`/v1/catalogs/...`） |
| `tle-mirror.service` / `tle-mirror.timer` | systemd，每 3 小时刷新一次 |

当前镜像的路径约定：

```
/v1/catalogs/satellites/stations.3le
/v1/catalogs/satellites/visual.3le
/v1/catalogs/satellites/active.3le
/v1/catalogs/satellites/satnogs.json
/v1/catalogs/exoplanets.json
/v1/catalogs/meteor-showers.json
/v1/catalogs/novae.json
/v1/catalogs/supernovae.json
/v1/catalogs/pulsars.json
/v1/catalogs/quasars.json
/v1/manifest.json
```

## 本地加固（2026-11-11，尚未部署）

抓取器只接受注册的 HTTPS 源，每源总超时 60 秒；先检查 Content-Length，再对解压后的响应流计数，最多 16 MiB，拒绝无效 UTF-8。原始响应字节用于文件、大小与 SHA-256，避免编码转换导致校验值不一致。

- CSV 必须有完整 GP 列头、至少一行数据、有效 NORAD 编号/日期/数值和轨道范围；支持引号、转义双引号、逗号和 CRLF。
- TLE 必须是完整 3LE 三行组、同一编号、69 字符轨道行、正确校验和及基本轨道字段；SatNOGS 必须是非空数组，编号与有效 TLE 对相符。
- 六类 JSON 目录验证各自集合键、版本、条目对象和最低数量；支持既有数字/数字字符串版本。它不是各目录全部科学字段的验证器。
- 未支持的格式（包括当前 MPC 页面）返回 `unsupported_format`，不发起下载；不再把任意文本当作有效资源。

公开清单只包含公共 `/v1/catalogs/...` 路由和白名单元数据，不输出服务器 root、上游地址或原始异常。`ok` 表示该源最近记录的刷新结果，`status` 为 `fresh` / `stale` / `unavailable`；`available` 表示磁盘文件经过本轮重新验证，`stale` 明确标注失败回退。`fresh` 只表示抓取验证成功，不保证轨道历元足够新。

失败保留原文件。仅在旧文件通过新格式校验、且已有 SHA-256/大小与文件相符时，保留其 `bytes`、`sha256`、`lastSuccessAt`；只有旧版成功清单才可用 `generatedAt` 迁移成功时间。旧版失败记录若没有哈希，可从有效文件恢复哈希/大小，但 `lastSuccessAt` 为 null，不以文件修改时间伪造新鲜度。损坏文件不会被列为 available；既有静态 URL 仍可能提供该旧文件，消费者必须遵守清单，迁移时需处理被拒收的历史文件。

每个资源与清单通过同文件系统临时文件、fsync、rename 发布，临时文件放在 root 而非公开的 `root/v1` 内。`.refresh.lock` 目录拒绝并发写入，正常异常路径会清理；进程被强杀可能留下锁，必须先确认没有刷新任务再由维护人员处理。root 必须是可信目录，不应含指向目录外的符号链接。

任一选中源失败返回退出码 1，但仍写入完整清单并发布其他有效源。`--only` 保留并复核未选中的注册资源，不清空它们；`--dry-run` 仍抓取并验证，但不写文件或获取写锁。清单原子替换不等于多文件事务：固定 URL/缓存仍可能跨代，签名、不可变版本 URL、整体激活和客户端回滚留给后续 v2。

## 身份迁移步骤（仅方案，不代表已执行）

按 `docs/harmonyos/server/SERVER-SECURITY.md` 在获准维护窗口内执行，Workbench 必须验证实际 OS 身份；日常 skyops 不负责提权。

1. 先确认刷新没有运行，备份原 unit、drop-in、脚本、注册表与清单；记录 owner/mode。暂停后续 timer 调度需纳入维护授权。
2. 建立无登录 shell、无密码、无 sudo/附加权限的系统用户和组 `tle-mirror`。保持 `/opt/tle-mirror` 和脚本为 root 所有且服务用户不可写；仅 `/srv/tle-mirror` 数据树交给该账号，目录 0755、公开文件 0644，保持 nginx 可读。不要递归改动网站目录或凭据。
3. 安装新 unit 后检查合并配置：空 capabilities、NoNewPrivileges、严格只读系统、私有临时目录/设备、唯一持久可写数据目录；MemoryHigh 192 MiB、MemoryMax 256 MiB、CPUQuota 50%、TasksMax 32、NOFILE 256。这些是初始限制，需维护环境验证峰值和 900 秒整批时限。
4. 当前线上有 `health.conf`，使用忽略错误的 `ExecStartPost` 并引用可选通知环境文件。刷新现在会在部分失败时退出 1，普通 ExecStartPost 不会执行；迁移时应另设受限的失败通知/状态检查单元，或先禁用旧 hook。核对它的读写目录与凭据访问需求，不要为兼容 hook 放宽抓取器权限或把通知密钥交给抓取器。
5. 在目标 Linux 上运行 `systemd-analyze verify`，检查 effective User/Group、目录可写/不可写边界。先用本地 fixtures 测试，再按维护授权进行一次刷新；核对成功/失败、清单、静态读取和 timer 下次时间。当前 MPC 不支持仍会导致非零，不能以全成功作为预期。
6. 若失败，保留诊断和上一版数据；按记录恢复原文件、身份归属和 unit 配置。不要自动退回 root 重跑；回退旧 root 单元必须作为明确维护决定。此次本地工作未创建服务器账号、未改变 ownership、未部署或重启。

## 离线测试

从仓库根执行 `node --test deploy/tle-mirror/test/fetch-mirror.test.mjs`。网络入口全部注入 mock fetch；测试仅使用本地 fixtures、现有随包 JSON 和临时目录，不访问生产或上游。Node 18+ 可运行抓取器；本次实测 Node 26.7.0。审计与测试结果见 `docs/harmonyos/server/SERVER-RESOURCE-AUDIT-2026-11-11.md`。

## 抓取失败的两种已知情况

- `satellites.tle.active` 常返回 **HTTP 403**：CelesTrak 对 `GROUP=active` 这类大分组限制自动抓取。
  脚本会保留上一版文件；首次部署时可用仓库里已构建的 `satellites.json` 兜底，或降低刷新频率到每天一次。
- `catalog.mpc` 返回的不是预期格式（页面变动/需要不同参数）：脚本按“格式不符”拒收，不会写坏文件。

## App 侧怎么接

```bash
# 用镜像构建（替换 upstream）
node scripts/update-ohos-astronomy-data.mjs --all \
  --source-mode mirror \
  --mirror-base-url https://<域名>
```

镜像地址与 `data/ohos/network-sources.json` 里的 `mirrorPath` 一一对应，改域名只改 `--mirror-base-url`。

## 已部署实例（2026-11-03）

| 项 | 值 |
|---|---|
| 实例 | `i-uf68vk358s8l58afzswt`（cn-shanghai，2 vCPU / 1.8 GiB / 40 GiB，Alibaba Cloud Linux 3） |
| 脚本 | `/opt/tle-mirror/`（`fetch-mirror.mjs` + `sources.json`） |
| 数据 | `/srv/tle-mirror/`（约 7.7 MB） |
| 对外 | `https://skyinstrument.cn/v1/...`（挂在既有站点的 apex server 块里） |
| 刷新 | `tle-mirror.timer`，每 3 小时；`systemctl list-timers tle-mirror.timer` |
| 配置备份 | `/etc/skyinstrument-website/nginx.conf.bak-20261103015512` |

注意这台机器上跑了**两个** nginx 实例，pid 文件不同，别混：

- `/etc/skyinstrument-website/nginx.conf` → 80/443，site（`skyinstrument.cn`），镜像就挂在这里
- `/etc/skyinstrument/nginx.conf` → 仅 127.0.0.1:8080

改完配置只重载站点那个：

```bash
nginx -t -c /etc/skyinstrument-website/nginx.conf && \
  nginx -s reload -c /etc/skyinstrument-website/nginx.conf
```

回滚：把 `.bak-*` 覆盖回去再 reload 即可（`/v1/` 那一块是唯一改动）。

2026-11-11 只读复核：即使每 3 小时刷新，`satellites.csv.active` 仍返回上游 403，公开文件停留在 11 月 4 日；不能承诺三小时间隔避免限流。`catalog.mpc` 无有效镜像。以上部署表是历史记录，本地加固尚未上线。
